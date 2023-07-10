-- https://github.com/latte-soft/channel-tracker

--[[
    Copyright (C) 2023 Latte Softworks <latte.to>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local net = require("@lune/net")
local task = require("@lune/task")
local serde = require("@lune/serde")

local ExtraTypes = require("modules/ExtraTypes")

local WebhookQueue = require("modules/WebhookQueue")
local PastVersions = require("modules/PastVersions")
local ParseArgs = require("modules/ParseArgs")
local EnsureFileTree = require("modules/EnsureFileTree")
local ParseDeployHistory = require("modules/ParseDeployHistory")
local GetTimestampFromLastModified = require("modules/GetTimestampFromLastModified")

-- Input args
local Args = ParseArgs(process.args, {
    ["config-file"] = "config.json",
})

local ConfigFile = Args["config-file"]

-- Set global config at init..
assert(fs.isFile(ConfigFile), `Given config file path "{ConfigFile}" not found, did you make a typo?`)
local Config: ExtraTypes.Config = serde.decode("json", fs.readFile(ConfigFile))

-- Make sure all z-channels in the config are set to lowercase for s3
local ZChannels = Config.ZChannels or {}

print(`* Checking ({#ZChannels}) z-channel names..`)
for Index, ChannelName in ZChannels do
    local LowercaseChannelName = string.lower(ChannelName)

    if LowercaseChannelName ~= ChannelName then
        print(`[#] Converting input channel name "{ChannelName}" to lowercase: "{LowercaseChannelName}"`)
    end

    ZChannels[Index] = LowercaseChannelName
end

-- Keep in mind, this ONLY works with WindowsPlayer, MacPlayer, and MacStudio
-- BinaryTypes; not WindowsStudio64. (Example input: "5750427"; `575, 427`)
local function ParseRobloxVersion(version: string): string?
    -- We have no accurate way to get the major version without expecting 3 hardcoded
    -- numbers, as there's no definite seperator (as there is a possibility for no
    -- zeroes at all) between it and the patch ver. The patch number can be lead by
    -- any number of zeros after major ver
    local Major, Patch = string.match(version, "(%d%d%d)0*(%d*)")

    if not Major then
        return
    elseif Patch == "" then
        Patch = "0" -- Fallback, if the patch ver is literally set to `0` for some reason
    end

    return `{Major}.{Patch}`
end

-- Lol..
local function GetLatestRobloxVersionForBinaryType(binaryType: string, deployHistoryData: string): string?
    local Deployments = ParseDeployHistory(deployHistoryData)

    for ReverseIndex = #Deployments, 1, -1 do
        local Deployment = Deployments[ReverseIndex]

        if Deployment.BinaryType == binaryType then
            local Ending = string.match(Deployment.RobloxVersion, "%d+$")
            if Ending then
                return ParseRobloxVersion(Ending)
            end

            break
        end
    end

    -- :(
    return
end

local function SafeReadFile(filePath: string): string?
    if fs.isFile(filePath) then
        local Success, Contents = pcall(fs.readFile, filePath)
        if Success then
            return Contents
        end
    end

    return nil
end

local function EveryThreadInTableIsDead(threadTable: {thread})
    for _, Thread in threadTable do
        if coroutine.status(Thread) ~= "dead" then
            return false
        end
    end

    return true
end

local function ConstructDiff(versionHash1: string, robloxVersion1: string?, versionHash2: string, robloxVersion2: string?): string
    local Diff = `+ {versionHash1}`
    if robloxVersion1 then
        Diff ..= ` ({robloxVersion1})`
    end
    if versionHash2 then
        local BeforeDiffLine = `- {versionHash2}`
        if robloxVersion2 then
            BeforeDiffLine ..= ` ({robloxVersion2})`
        end

        Diff = BeforeDiffLine .. "\n" .. Diff
    end

    return Diff
end

local function VersionIsLess(newVersion: string, oldVersion: string): boolean
    local NewVersionMajor, NewVersionMinor = string.match(newVersion, "(%d+)%.(%d+)")
    local OldVersionMajor, OldVersionMinor = string.match(newVersion, "(%d+)%.(%d+)")

    if not NewVersionMajor or not OldVersionMajor then
        return false
    end

    -- Check if major version is already less, or check if the major version is the SAME
    -- *AND* make sure minor version is less
    if NewVersionMajor < OldVersionMajor or (NewVersionMajor == NewVersionMajor and NewVersionMinor < OldVersionMinor) then
        return true
    end

    return false
end

local function NewWebhookObject(): WebhookQueue.WebhookObject
    -- For more code reuse!
    local WebhookObject = {
        embeds = {}
    }

    if Config.Discord.Username then
        WebhookObject.username = Config.Discord.Username
    end
    if Config.Discord.AvatarUrl then
        WebhookObject.avatar_url = Config.Discord.AvatarUrl
    end

    return WebhookObject
end

-- Used in worker threads individually
local function CheckChannel(channelName: string, postToWebhook: boolean?)
    -- This is used in the inital run loop for each worker, so that we don't log any
    -- "new" versions falsely, that haven't actually been tracked. Think of it like
    -- the bot just "catching up" to the current 'state' of the channel
    postToWebhook = if postToWebhook == nil then true else postToWebhook

    -- "LIVE" is a pseudo identifier for production; top level dir on setup.rbxcdn
    local ChannelPath = if channelName == "LIVE" then
        "https://setup.rbxcdn.com/"
    else
        `https://setup.rbxcdn.com/channel/{channelName}/`

    local DbPath = `db/{channelName}/`

    -- We'll use this throughout each specific BinaryType check to add embeds etc
    local WebhookObjects: {WebhookQueue.WebhookObject} = {}

    -- This is structred in this way to be ordered..
    local Responses = {
        {"WindowsPlayer", net.request(ChannelPath .. "version")},
        {"WindowsStudio64", net.request(ChannelPath .. "versionQTStudio")},
        {"MacPlayer", net.request(ChannelPath .. "mac/version")},
        {"MacStudio", net.request(ChannelPath .. "mac/versionStudio")},
    }

    for _, ResponseTree in Responses do
        local BinaryType: string = ResponseTree[1]
        local Response: net.FetchResponse = ResponseTree[2]

        if Response.statusCode ~= 200 then
            continue
        end

        EnsureFileTree({
            db = {
                [channelName] = {
                    [BinaryType] = {}
                }
            }
        })

        local BinaryTypePath = DbPath .. BinaryType .. "/"
        local VersionHash = Response.body

        local OldVersionFile = SafeReadFile(BinaryTypePath .. "Version.txt")

        local OldVersionHash, OldRobloxVersion
        if OldVersionFile then
            local SplitOldVersionFile = string.split(OldVersionFile, "\n")

            OldVersionHash = SplitOldVersionFile[1]
            OldRobloxVersion = SplitOldVersionFile[2]
        end

        -- If this version is being caught for the first time or the version is different than what we know..
        if OldVersionFile and VersionHash == OldVersionHash then
            continue
        end

        local LastModifiedHeader = Response.headers["last-modified"]
        local DeploymentTime = if LastModifiedHeader then GetTimestampFromLastModified(LastModifiedHeader) else nil

        -- Also for checking if this a new deployment, or a "revert" later
        local PastVersionsFile = SafeReadFile(BinaryTypePath .. "PastVersions.txt")
        local PastVersions = PastVersions.Parse(PastVersionsFile)

        -- Can be changed by our iter in a min
        local IsPastVersion = false

        -- Does *not* support WindowsStudio64. And yes, there are SLIGHT differences to each
        -- of these, according the the specs we've reversed
        local RobloxVersion

        for _, PastVersion in PastVersions do
            if PastVersion.VersionHash == VersionHash then
                IsPastVersion = true

                if PastVersion.RobloxVersion then
                    RobloxVersion = PastVersion.RobloxVersion
                end

                break
            end
        end

        -- Add the "NEW" old version hash to PastVersions, and re-serialize to file
        if OldVersionHash then
            table.insert(PastVersions, {
                VersionHash = OldVersionHash,
                RobloxVersion = OldRobloxVersion,
            })

            fs.writeFile(BinaryTypePath .. `PastVersions.txt`, PastVersions.Serialize(PastVersions))
        end

        -- If still not in a past logged version..
        if not RobloxVersion then
            if BinaryType == "WindowsPlayer" then
                local RobloxVersionResponse = net.request(ChannelPath .. `{VersionHash}-RobloxVersion.txt`)
                if RobloxVersionResponse.statusCode == 200 then
                    local VersionString = string.match(RobloxVersionResponse.body, "%d+, %d+, %d+, (%d+)")
                    if VersionString then
                        RobloxVersion = ParseRobloxVersion(VersionString)
                    end
                end
            elseif BinaryType == "WindowsStudio64" then
                local DeployHistoryResponse = net.request(ChannelPath .. "DeployHistory.txt")
                if DeployHistoryResponse.statusCode == 200 then
                    -- Might still be nil!
                    RobloxVersion = GetLatestRobloxVersionForBinaryType("Studio64", DeployHistoryResponse.body)
                end
            elseif BinaryType == "MacPlayer" then
                local RobloxVersionResponse = net.request(ChannelPath .. `mac/{VersionHash}-RobloxVersion.txt`)
                if RobloxVersionResponse.statusCode == 200 then
                    local VersionString = string.match(RobloxVersionResponse.body, "%d+")
                    if VersionString then
                        RobloxVersion = ParseRobloxVersion(VersionString)
                    end
                end
            elseif BinaryType == "MacStudio" then
                local RobloxVersionResponse = net.request(ChannelPath .. `mac/{VersionHash}-RobloxStudioVersion.txt`)
                if RobloxVersionResponse.statusCode == 200 then
                    local VersionString = string.match(RobloxVersionResponse.body, "%d+")
                    if VersionString then
                        RobloxVersion = ParseRobloxVersion(VersionString)
                    end
                end
            end
        end

        -- Used in the embed
        local DeploymentType = if IsPastVersion or (RobloxVersion and OldRobloxVersion and VersionIsLess(RobloxVersion, OldRobloxVersion)) then "Revert" else "New"

        local BulletPoints = {`• Hash: **\`{VersionHash}\`**`}
        if RobloxVersion then
            table.insert(BulletPoints, `• Version: **\`{RobloxVersion}\`**`)
        end
        if DeploymentTime then
            table.insert(BulletPoints, `• Deploy Time: <t:{DeploymentTime}:D> @ <t:{DeploymentTime}:T>`)
        end

        -- Yeah, this is hacky, what a price to pay for good formatting!
        local PlatformEmoji = if Config.Discord.PlatformEmojis then
            if BinaryType == "WindowsPlayer" or BinaryType == "WindowsStudio64" and Config.Discord.PlatformEmojis.Windows then
                ` {Config.Discord.PlatformEmojis.Windows} `
            elseif BinaryType == "MacPlayer" or BinaryType == "MacStudio" and Config.Discord.PlatformEmojis.MacOs then
                ` {Config.Discord.PlatformEmojis.MacOs} `
            else
                ""
        else
            ""

        -- The "diff" embedded in the Discord Webhook embed
        local Diff = ConstructDiff(VersionHash, RobloxVersion, OldVersionHash, OldRobloxVersion)

        print(`[+] {DeploymentType} {BinaryType}@{channelName}\n    * Hash: {VersionHash}\n    * Version: {RobloxVersion}\n    * Deploy Time: {LastModifiedHeader}`)
    
        local WebhookObject = NewWebhookObject()
        local EmbedObject = {
            title = `[{DeploymentType}]{PlatformEmoji}{BinaryType}@{channelName}`,
            description = table.concat(BulletPoints, "\n") .. "\n```diff\n" .. Diff .. "\n```",
            url = ChannelPath .. "DeployHistory.txt",
            color = 0x518dc9,
        }

        -- Only for WindowsPlayer@LIVE
        if channelName == "LIVE" and BinaryType == "WindowsPlayer" then
            EmbedObject.footer = {
                text = "This deployment is now likely \"active\", meaning users should now, generally be on this version."
            }

            -- And also..
            if Config.Discord.LiveUpdatePingRoleId then
                WebhookObject.content = `<@&{Config.Discord.LiveUpdatePingRoleId}>`
            end
        end

        WebhookObject.embeds = {EmbedObject}
        table.insert(WebhookObjects, WebhookObject)

        -- Now write new version info to file
        local NewVersionInfoToWrite = VersionHash
        if RobloxVersion then
            NewVersionInfoToWrite ..= "\n" .. RobloxVersion
        end

        fs.writeFile(BinaryTypePath .. "Version.txt", NewVersionInfoToWrite)
    end

    -- Now, we'll finalize and post to the webhook, if applicable
    if postToWebhook and #WebhookObjects >= 1 then
        for _, WebhookObject in WebhookObjects do
            local WebhookArray = if channelName == "LIVE" then Config.Discord.Webhooks.Live else Config.Discord.Webhooks.ZChannels
            for _, WebhookUrl in WebhookArray do
                WebhookQueue.Add(WebhookUrl, WebhookObject)
            end
        end
    end
end

-- For checking *specifically* LIVE, via parsing DeployHistory
local function CheckLivePre(postToWebhook: boolean?)
    postToWebhook = if postToWebhook == nil then true else postToWebhook

    local WebhookObjects: {WebhookQueue.WebhookObject} = {}

    -- Now we'll handle each individual DeployHistory out; the "Windows" and "Mac" stuff are
    -- just identifiers for the main body so we can reuse code <3
    local Responses = {
        {"Windows", "https://setup.rbxcdn.com/DeployHistory.txt"},
        {"Mac", "https://setup.rbxcdn.com/mac/DeployHistory.txt"},
    }

    for _, ResponseTree in Responses do
        local Platform: string = ResponseTree[1]
        local Url: string = ResponseTree[2]

        local Response: net.FetchResponse = net.request(Url)

        if Response.statusCode ~= 200 then
            continue
        end

        local Deployments = ParseDeployHistory(Response.body)
        local CheckedBinaryTypes = setmetatable({}, {__mode = "v"})

        -- Traverse the array in reverse
        for ReverseIndex = #Deployments, 1, -1 do
            local Deployment = Deployments[ReverseIndex]

            -- For skipping new BinaryTypes we've already checked new versions for
            if CheckedBinaryTypes[Deployment.BinaryType] then
                continue
            end

            CheckedBinaryTypes[Deployment.BinaryType] = true

            -- Resolving the psuedo BinaryType for this is a mess lol
            local BinaryType = if Platform == "Windows" then
                if Deployment.BinaryType == "Studio64" then
                    "WindowsStudio64"
                elseif Deployment.BinaryType == "Studio" then
                    "WindowsStudio"
                else
                    Deployment.BinaryType -- Just itself, if other than ones we manually want to re-bind
            else -- Mac
                if Deployment.BinaryType == "Client" then
                    "MacPlayer"
                elseif Deployment.BinaryType == "Studio" then
                    "MacStudio"
                else
                    Deployment.BinaryType

            EnsureFileTree({
                db = {
                    LIVEPRE = {
                        [Platform] = {
                            [BinaryType] = {},
                        },
                    },
                },
            })

            -- It'll always be `LIVE`, so no need to check for anything else
            local BinaryTypePath = `db/LIVEPRE/{Platform}/{BinaryType}/`
            local OldVersionFile = SafeReadFile(BinaryTypePath .. "Version.txt")

            local OldVersionHash, OldRobloxVersion
            if OldVersionFile then
                local SplitOldVersionFile = string.split(OldVersionFile, "\n")

                OldVersionHash = SplitOldVersionFile[1]
                OldRobloxVersion = SplitOldVersionFile[2]
            end

            if OldVersionFile and Deployment.VersionHash == OldVersionHash then
                continue
            end

            local PastVersionsFile = SafeReadFile(BinaryTypePath .. "PastVersions.txt")
            local PastVersions = if PastVersionsFile then string.split(PastVersionsFile, "\n") else {}

            -- Add the old version hash to PastVersions, and re-write to file
            if OldVersionHash then
                table.insert(PastVersions, OldVersionHash)
                fs.writeFile(BinaryTypePath .. `PastVersions.txt`, table.concat(PastVersions, "\n"))
            end

            local BulletPoints = {`• Hash: **\`{Deployment.VersionHash}\`**`}
            if Deployment.RobloxVersion then
                table.insert(BulletPoints, `• Version: **\`{Deployment.RobloxVersion}\`**`)
            end
            if Deployment.Time.Timestamp then
                table.insert(BulletPoints, `• Deploy Time: <t:{Deployment.Time.Timestamp}:D> @ <t:{Deployment.Time.Timestamp}:T>`)
            end

            local PlatformEmoji = if Config.Discord.PlatformEmojis then
                if Platform == "Windows" then
                    ` {Config.Discord.PlatformEmojis.Windows} `
                else -- Mac
                    ` {Config.Discord.PlatformEmojis.MacOs} `
            else
                ""

            local Diff = ConstructDiff(Deployment.VersionHash, Deployment.RobloxVersion, OldVersionHash, OldRobloxVersion)

            print(`[+] {Deployment.DeployType} {BinaryType}@LIVEPRE\n    * Hash: {Deployment.VersionHash}\n    * Version: {Deployment.RobloxVersion}\n    * Deploy Time: {Deployment.Time.Formatted}`)

            local WebhookObject = NewWebhookObject()
            local EmbedObject = {
                title = `[{Deployment.DeployType}]{PlatformEmoji}{BinaryType}@LIVE`,
                description = table.concat(BulletPoints, "\n") .. "\n```diff\n" .. Diff .. "\n```",
                url = Url,
                color = 0x518dc9,
            }

            -- Only for WindowsPlayer
            if BinaryType == "WindowsPlayer" then 
                EmbedObject.footer = {
                    text = "⚠️ This version may not yet be \"active\", meaning users shouldn't receive this update until later, which could take any amount of time. Occasionally, this deployment may *never* be set to active due to issues internally!"
                }

                -- And we'll also optionally ping for it
                if Config.Discord.LiveUpdatePingRoleId then
                    WebhookObject.content = `<@&{Config.Discord.LiveUpdatePingRoleId}>`
                end
            end

            WebhookObject.embeds = {EmbedObject}
            table.insert(WebhookObjects, WebhookObject)

            local NewVersionInfoToWrite = Deployment.VersionHash
            if Deployment.RobloxVersion then
                NewVersionInfoToWrite ..= "\n" .. Deployment.RobloxVersion
            end

            fs.writeFile(BinaryTypePath .. "Version.txt", NewVersionInfoToWrite)
        end
    end

    if postToWebhook and #WebhookObjects >= 1 then
        for _, WebhookObject in WebhookObjects do
            -- Post to all `LIVEPRE` webhooks
            for _, WebhookUrl in Config.Discord.Webhooks.LivePre do
                WebhookQueue.Add(WebhookUrl, WebhookObject)
            end
        end
    end
end

-- Let's make sure to start the webhook queue listener thread first
print("* Starting webhook queue listener..")
WebhookQueue.Start()

-- Before anything else, let's run through each channel to make sure we're
-- caught up with the current 'state' of each channel
-- FYI, the `false` arg here tells CheckChannel to not post to any
-- webhooks, soley for this
print("* Checking initial state of each channel (this could take a min)")
if Config.TrackLive then
    CheckChannel("LIVE", false)
    CheckLivePre(false)
end

local InitCheckThreads = {}
for _, ChannelName in ZChannels do
    table.insert(InitCheckThreads, task.spawn(CheckChannel, ChannelName, false))
    task.wait(0.5)
end

repeat
    task.wait(1)
until EveryThreadInTableIsDead(InitCheckThreads)

-- Now we'll calculate and create how many threads w/ how many ZChannels there are
-- We'll also create an extra thread for LIVE specifically, if tracking it is enabled
local ChannelsPerThread = math.floor(#ZChannels / Config.Workers.Amount)
local RemainingChannels = #ZChannels % Config.Workers.Amount

local ChannelGroups = {}
local ZChannelListIndex = 1

print(`* Creating {Config.Workers.Amount} workers, with {ChannelsPerThread} channels per worker ({RemainingChannels} remainders)`)

-- Go through the initial list (without remainders)
for GroupIndex = 1, Config.Workers.Amount do
    local ChannelGroup = {}

    for _ = 1, ChannelsPerThread do
        table.insert(ChannelGroup, ZChannels[ZChannelListIndex])
        ZChannelListIndex += 1
    end

    ChannelGroups[GroupIndex] = ChannelGroup
end

-- Spread out remainder channels into each created thread
-- Note that we're still using `ZChannelListIndex`, created prior
for RemainderIndex = 1, RemainingChannels do
    table.insert(ChannelGroups[RemainderIndex], ZChannels[ZChannelListIndex])
    ZChannelListIndex += 1
end

-- Give LIVE its own thread, if it is to be tracked
print("(Giving LIVE its own worker)")
if Config.TrackLive then
    -- For normal active ver check
    table.insert(ChannelGroups, {"LIVE"})

    task.spawn(function()
        while true do
            local Success, Error = pcall(CheckLivePre)
            if not Success then
                print(`[!] Unexpected error making DeployHistory request: {Error}`)
            end

            task.wait(Config.Workers.CheckIntervalLive)
        end
    end)
end

-- Finally, create running threads per channel group! <3
for _, ChannelGroup in ChannelGroups do
    task.spawn(function()
        while true do
            local _, Error = pcall(function()
                for _, ChannelName in ChannelGroup do
                    CheckChannel(ChannelName)
                end
            end)

            if Error then
                print(`[!] Unexpected error during process: {Error}`)
            end
            
            -- Wait the given interval at the end of the cycle..
            task.wait(Config.Workers.CheckInterval) 
        end
    end)
end

print(`* Now running {Config.Workers.Amount} workers, with a check-interval of {Config.Workers.CheckInterval} after each cycle`)
