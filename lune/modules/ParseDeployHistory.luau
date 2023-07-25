-- GPLv3 | Copyright (C) 2023 Latte Softworks <latte.to>

export type Deployment = {
    DeployType: string,
    BinaryType: string,
    VersionHash: string,
    Time: {
        Timestamp: number?,
        Formatted: string?,
    },
    RobloxVersion: string?,
    GitHash: string?,
}

local function ConvertAllToNumber(...: string): ...number
    local Numbers = {}

    for _, NumberString in {...} do
        local Converted = tonumber(NumberString)
        assert(Converted, `String "{NumberString}" couldn't be converted to type \`number\``)
        table.insert(Numbers, Converted)
    end

    return unpack(Numbers)
end

local function ParseDeployHistory(deployHistoryData: string): {Deployment}
    local DeploymentObjects = {}

    for DeployType, BinaryType, VersionHash, Extra in string.gmatch(deployHistoryData, "(%u%l+) (%w+) (version%-[%l%d]+) ([%w/:,!#\" ]*)") do
        local Deployment: Deployment = {
            DeployType = DeployType,
            BinaryType = BinaryType,
            VersionHash = VersionHash,
            Time = {},
        }

        -- We'll check for extra stuff..
        local Month, Day, Year, Hour, Minute, Second, Meridiem = string.match(Extra, "(%d+)/(%d+)/(%d+) (%d+):(%d+):(%d+) ([aApP][mM])")
        if Month then -- Every other match will also be valid; this is soley for checks!
            Month, Day, Year, Hour, Minute, Second = ConvertAllToNumber(Month, Day, Year, Hour, Minute, Second)
            Meridiem = string.upper(Meridiem) -- "AM"/"PM"
            
            -- If it's PM, increase by 12 hours for 24H format
            Hour = if Meridiem == "AM" then Hour else Hour + 12

            -- Convert to timestamp, then increase by 4 hours, as to our knowledge, LIVE's
            -- DeployHistory is always in UTC-5, EST
            local Timestamp = os.time({
                month = Month,
                day = Day,
                year = Year,

                hour = Hour,
                min = Minute,
                sec = Second,
            })

            Timestamp += 60 * 60 * 5 -- Match to UTC+0 (Because it's originally UTC-5; deployed from New York)
            Deployment.Time.Timestamp = Timestamp

            -- Matching the `Last-Modified` header format: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Last-Modified
            Deployment.Time.Formatted = os.date("%a, %d %b %Y %H:%M:%S GMT", Timestamp)
        end

        -- bro they literally spelled "file version" wrong for so long in early win/mac deployhistory
        local FileVersionString = string.match(Extra, "file vers?ion: (%d+,? ?%d*,? ?%d*,? ?%d*)")
        if FileVersionString then
            Deployment.RobloxVersion = string.gsub(FileVersionString, ", *", ".")
        end

        local GitHash = string.match(Extra, "git hash: ([%l%d]+)")
        if GitHash then
            Deployment.GitHash = GitHash
        end

        -- Now we'll add it to the array of other objects!
        table.insert(DeploymentObjects, Deployment)
    end

    return DeploymentObjects
end

return ParseDeployHistory
