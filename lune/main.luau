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

assert(
    table.find({"linux", "macos", "windows"}, process.os) ~= nil,
    `[!] Unsupported operating system "{process.os}"; expected "linux", "macos", or "windows"\nExitting..`
)

local Types = require("modules/Types")

local ParseArgs = require("modules/ParseArgs")
local EnsureFileTree = require("modules/EnsureFileTree")
local WebhookQueue = require("modules/WebhookQueue")
local GetTimestampFromLastModified = require("modules/GetTimestampFromLastModified")

-- Input args
local Args = ParseArgs(process.args, {
    ["config-file"] = "config.json",
})

local ConfigFile = Args["config-file"]

-- Set global config at init..
assert(fs.isFile(ConfigFile), `Given config file path "{ConfigFile}" not found, did you make a typo?`)
local Config: Types.Config = serde.decode("json", fs.readFile(ConfigFile))

-- Make sure all z-channels in the config are set to lowercase for s3
local ZChannels = Config.ZChannels

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
    -- We have no accurate way to get the major version without expecting 3
    -- hardcoded numbers, as there's no seperator between it and the patch ver.
    -- The patch number can be lead by any number of zeros after major
    local Major, Patch = string.match(version, "(%d%d%d)0*(%d+)")

    return `{Major}.{Patch}`
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
    local WebhookObject: WebhookQueue.WebhookObject = {
        username = Config.Discord.Username,
        avatar_url = Config.Discord.AvatarUrl,
        embeds = {},
    }

    -- This is structred in this way to be ordered..
    local Responses = {
        {"WindowsPlayer", net.request(ChannelPath .. "version")},
        {"WindowsStudio64", net.request(ChannelPath .. "versionQTStudio")},
        {"MacPlayer", net.request(ChannelPath .. "mac/version")},
        {"MacStudio", net.request(ChannelPath .. "mac/versionStudio")},
    }

    -- Automatically ensure the folder for said BinaryType in the channel exists, as
    -- this will be the same throughout
    local GoodResponses = {}

    for _, ResponseTree in Responses do
        local BinaryType: string = ResponseTree[1]
        local Response: net.FetchResponse = ResponseTree[2]

        local StatusCodeIsGood = Response.statusCode == 200
        GoodResponses[BinaryType] = StatusCodeIsGood

        if StatusCodeIsGood then
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
            local OldVersionHash, OldRobloxVersion do
                local SplitOldVersionFile = string.split(OldVersionFile, "\n")

                OldVersionHash = SplitOldVersionFile[1]
                OldRobloxVersion = SplitOldVersionFile[2]
            end
            
            print(`{BinaryType}@{channelName} | {OldVersionHash}, {OldRobloxVersion}`)

            -- If this version is being caught for the first time or the version is different than what we know..
            if not OldVersionFile or VersionHash ~= OldVersionHash then
                local LastModifiedHeader = Response.headers["last-modified"]
                local DeploymentTime = if LastModifiedHeader then GetTimestampFromLastModified(LastModifiedHeader) else nil

                -- Does *not* support WindowsStudio64. And yes, there are SLIGHT differences to each
                -- of these, according the the specs we've reversed
                local RobloxVersion
                if BinaryType == "WindowsPlayer" then
                    local RobloxVersionResponse = net.request(ChannelPath .. `{VersionHash}-RobloxVersion.txt`)
                    if RobloxVersionResponse.statusCode == 200 then
                        local VersionString = string.match(RobloxVersionResponse.body, "%d+, %d+, %d+, (%d+)")
                        if VersionString then
                            RobloxVersion = ParseRobloxVersion(VersionString)
                        end
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

                -- The "diff" embedded in the Discord Webhook embed
                local Diff = `+ {VersionHash}`
                if RobloxVersion then
                    Diff ..= ` ({RobloxVersion})`
                end
                if OldVersionHash then
                    local BeforeDiffLine = `- {OldVersionHash}`
                    if OldRobloxVersion then
                        BeforeDiffLine ..= ` ({OldRobloxVersion})`
                    end
    
                    Diff = BeforeDiffLine .. "\n" .. Diff
                end

                -- Checking if this a new deployment, or a "revert"
                local PastVersionsFile = SafeReadFile(BinaryTypePath .. "PastVersions.txt")
                local PastVersions = if PastVersionsFile then string.split(PastVersionsFile, "\n") else {}
    
                -- Used in the embed
                local DeploymentType = if table.find(PastVersions, VersionHash) then "Revert" else "New"
    
                -- Add the old version hash to PastVersions, and re-write to file
                if OldVersionHash then
                    table.insert(PastVersions, OldVersionHash)
                    fs.writeFile(BinaryTypePath .. `PastVersions.txt`, table.concat(PastVersions, "\n"))
                end

                local BulletPoints = {`• Binary Hash: **\`{VersionHash}\`**`}
                if RobloxVersion then
                    table.insert(BulletPoints, `• Roblox Version: **\`{RobloxVersion}\`**`)
                end
                if DeploymentTime then
                    table.insert(BulletPoints, `• Deployment Time: <t:{DeploymentTime}:D> @ <t:{DeploymentTime}:T>`)
                end
    
                -- Various BinaryType-specific config for the final embed
                local PlatformEmoji = if BinaryType == "WindowsPlayer" or BinaryType == "WindowsStudio64" then
                    Config.Discord.PlatformEmojis.Windows
                else -- MacPlayer/MacStudio
                    Config.Discord.PlatformEmojis.MacOs
                
                local EmbedUrl = if BinaryType == "WindowsPlayer" or BinaryType == "WindowsStudio64" then
                        ChannelPath .. `{VersionHash}-rbxManifest.txt`
                    elseif BinaryType == "MacPlayer" then
                        ChannelPath .. `{VersionHash}-Roblox.dmg`
                    else -- MacStudio
                        ChannelPath .. `{VersionHash}-RobloxStudio.dmg`

                print(`[+] {DeploymentType} {BinaryType}@{channelName}\n    * Binary Hash: {VersionHash}\n    * Roblox Version: {RobloxVersion}\n    * Deployment Time: {LastModifiedHeader}`)

                local EmbedObject = {
                    title = `[{DeploymentType}] {PlatformEmoji} {BinaryType}@{channelName}`,
                    description = table.concat(BulletPoints, "\n") .. "\n```diff\n" .. Diff .. "\n```",
                    url = EmbedUrl,
                    color = 0x518dc9,
                }

                -- Only for WindowsPlayer@LIVE
                if channelName == "LIVE" and BinaryType == "WindowsPlayer" then
                    EmbedObject.footer = {
                        text = "⚠️ This version may not yet be \"active\", meaning most users shouldn't receive this update until later, which could take any amount of time. (Sometimes a few hours, or even up to a day!)"
                    }

                    -- And also..
                    WebhookObject.content = `<@&{Config.Discord.LiveUpdatePingRoleId}>`
                end

                table.insert(WebhookObject.embeds, EmbedObject)
    
                -- Now write new version info to file
                local NewVersionInfoToWrite = VersionHash
                if RobloxVersion then
                    NewVersionInfoToWrite ..= "\n" .. RobloxVersion
                end
    
                fs.writeFile(BinaryTypePath .. "Version.txt", NewVersionInfoToWrite)
            end
        end
    end

    -- Now, we'll finalize and post to the webhook, if applicable
    if postToWebhook and #WebhookObject.embeds >= 1 then
        local WebhookArray = if channelName == "LIVE" then Config.Discord.Webhooks.Live else Config.Discord.Webhooks.ZChannels
        for _, WebhookUrl in WebhookArray do
            WebhookQueue.Add(WebhookUrl, WebhookObject)
        end
    end
end

-- Let's make sure to start the webhook queue listener thread first
print("* Starting webhook queue listener..")
WebhookQueue.Start()

-- Before anything else, let's run through each channel to make sure we're
-- caught up with the current 'state' of each channel
-- FYI, the 2nd `false` arg here tells CheckChannel to not post to any
-- webhooks, soley for this
print("* Checking initial state of each channel (this could take a min)")
if Config.TrackLive then
    CheckChannel("LIVE", false)
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
    table.insert(ChannelGroups, {"LIVE"})
end

-- Finally, create running threads per channel group! <3
for _, ChannelGroup in ChannelGroups do
    task.spawn(function()
        while true do
            for _, ChannelName in ChannelGroup do
                CheckChannel(ChannelName)

                -- Wait the given interval
                task.wait(Config.Workers.CheckInterval) 
            end
        end
    end)
end

print(`* Now running {Config.Workers.Amount} workers, with a check-interval of {Config.Workers.CheckInterval}`)
print(`* Each z-channel will be checked at an absolute MINIMUM of every ~{ChannelsPerThread * Config.Workers.CheckInterval} seconds`)
