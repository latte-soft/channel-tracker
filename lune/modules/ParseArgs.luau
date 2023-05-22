-- GPLv3 | Copyright (C) 2023 Latte Softworks <latte.to>

type OptionsTable = {[string]: string | number | boolean}

local function ParseArgs(args: {string}, optionsTable: OptionsTable): OptionsTable
    for _, Arg in args do
        local Option, Value = string.match(Arg, "(.+):(.+)")

        -- If it doesn't match..
        assert(Option and Value, `[!] Argument input "{Arg}" isn't formatted correctly. Format: "option:value"`)
    
        local DefaultOption = optionsTable[Option]

        -- If it is nil, it isn't a defined arg
        assert(DefaultOption ~= nil, `[!] "{Option}" isn't a valid option`)
    
        local OptionType = type(DefaultOption)
        local OutputValue: any = Value -- Just itself (`string`) initially
    
        if OptionType == "boolean" then
            local ValueLowercase = string.lower(Value)
            OutputValue = if ValueLowercase == "true" then true elseif ValueLowercase == "false" then false else nil
            assert(Value ~= nil, `[!] "{Value}" isn't a valid boolean type; expected "true" or "false"`)
        elseif OptionType == "number" then
            OutputValue = tonumber(Value)
            assert(OutputValue, `[!] Failed to convert given input "{OutputValue}" to a number value`)
        end
    
        optionsTable[Option] = OutputValue
    end

    return optionsTable
end

return ParseArgs