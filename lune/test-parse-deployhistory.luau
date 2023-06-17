local fs = require("@lune/fs")
local net = require("@lune/net")
local serde = require("@lune/serde")

local ParseDeployHistory = require("modules/ParseDeployHistory")

local Parsed = ParseDeployHistory(net.request("https://setup.rbxcdn.com/DeployHistory.txt").body)

--[[
for _, Deployment in Parsed do
    if Deployment.BinaryType == "version" then
        print(Deployment)
    end
end
]]

print(Parsed)
fs.writeFile("Windows-LIVE.lua", serde.encode("json", Parsed))
