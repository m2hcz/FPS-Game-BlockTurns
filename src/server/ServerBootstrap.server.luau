local ServerStorage = game:GetService("ServerStorage")

local main = ServerStorage:WaitForChild("main")
local src = main:WaitForChild("src")
local BootModule = require(src:WaitForChild("BootModule"))

BootModule.Initialize()
