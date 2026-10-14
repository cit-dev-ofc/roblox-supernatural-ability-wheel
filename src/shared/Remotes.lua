--[[
	Creates (server) or waits for (client) the two RemoteEvents used by the
	ability system. Only the server creates instances; clients never do.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)

local Remotes = {}

local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild(Config.Remotes.FolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Config.Remotes.FolderName
		folder.Parent = ReplicatedStorage
	end
	for _, name in ipairs({ Config.Remotes.Request, Config.Remotes.Response, Config.Remotes.Visual, Config.Remotes.Loadout, Config.Remotes.LoadoutState }) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild(Config.Remotes.FolderName)
end

Remotes.Request = folder:WaitForChild(Config.Remotes.Request)
Remotes.Response = folder:WaitForChild(Config.Remotes.Response)
Remotes.Visual = folder:WaitForChild(Config.Remotes.Visual)
Remotes.Loadout = folder:WaitForChild(Config.Remotes.Loadout)
Remotes.LoadoutState = folder:WaitForChild(Config.Remotes.LoadoutState)

return Remotes
