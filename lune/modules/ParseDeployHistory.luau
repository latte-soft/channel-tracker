-- GPLv3 | Copyright (C) 2023 Latte Softworks <latte.to>

export type Deployment = {
    DeployType: string,
    BinaryType: string,
    BinaryHash: string,
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

    for DeployType, BinaryType, BinaryHash, Extra in string.gmatch(deployHistoryData, "(%a+) (%w+) (version%-[%l%d]+)(.*)%.%.%.") do
        local Deployment: Deployment = {
            DeployType = DeployType,
            BinaryType = BinaryType,
            BinaryHash = BinaryHash,
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
            -- DeployHistory is always in GMT-4, EDT
            local Timestamp = os.time({
                month = Month,
                day = Day,
                year = Year,

                hour = Hour,
                min = Minute,
                sec = Second,
            })

            Timestamp += 60 * 60 * 4 -- Match to GMT+0
            Deployment.Time.Timestamp = Timestamp

            -- Matching the `Last-Modified` header format: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Last-Modified
            Deployment.Time.Formatted = os.date("%a, %d %b %Y %H:%M:%S GMT", Timestamp)
        end

        local FileVersionString = string.match(Extra, "file version: (%d+,? ?%d*,? ?%d*,? ?%d*)")
        if FileVersionString then
            Deployment.RobloxVersion = string.gsub(FileVersionString, ", ", ".")
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