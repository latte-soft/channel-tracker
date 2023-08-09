-- MIT License | Copyright (C) 2023 Latte Softworks <https://latte.to>

type PastVersion = {
    VersionHash: string,
    RobloxVersion: string?,
}

local PastVersions = {}

function PastVersions.Parse(pastVersionsFile: string?): {PastVersion}
    if not pastVersionsFile then
        return {}
    end

    local PastVersions = {}

    for VersionHash, RobloxVersion in string.gmatch(pastVersionsFile, "(version%-[%l%d]+) ?([%d%.]*)\n?") do
        -- `RobloxVersion` CAN be nil.. We are intentionally, potentially setting this as nil
        table.insert(PastVersions, {
            VersionHash = VersionHash,
            RobloxVersion = RobloxVersion,
        })
    end

    return PastVersions
end

function PastVersions.Serialize(pastVersions: {PastVersion}): string
    local Entries: {string} = {}

    for _, PastVersion in pastVersions do
        local Entry = PastVersion.VersionHash
        if PastVersion.RobloxVersion then
            Entry ..= " " .. PastVersion.RobloxVersion
        end

        table.insert(Entries, Entry)
    end

    return table.concat(Entries, "\n")
end

return PastVersions
