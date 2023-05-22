-- Month "bindings" for os.time input
local MonthBindings: {[string]: number} = {
    Jan = 1,
    Feb = 2,
    Mar = 3,
    Apr = 4,
    May = 5,
    Jun = 6,
    Jul = 7,
    Aug = 8,
    Sep = 9,
    Oct = 10,
    Nov = 11,
    Dec = 12,
}

local function GetTimestampFromLastModified(lastModifiedHeader: string): number?
    -- Example input: "Wed, 17 May 2023 21:22:52 GMT"
    -- We can ignore the "Wed, ", as the day of the month is provided. We still need to
    -- evaluate the month into a number, though.
    local Day, MonthName, Year, Hour, Minute, Second = string.match(lastModifiedHeader, "(%d+) (%u%l+) (%d+) (%d+):(%d+):(%d+) GMT")

    if Day and MonthName and Year and Hour and Minute and Second then
        local Month = MonthBindings[MonthName]
        if Month then
            return os.time({
                month = Month,
                day = tonumber(Day),
                year = tonumber(Year),
                
                hour = tonumber(Hour),
                min = tonumber(Minute),
                sec = tonumber(Second),
            })
        end
    end

    -- Fall-back to nil
    return
end

return GetTimestampFromLastModified
