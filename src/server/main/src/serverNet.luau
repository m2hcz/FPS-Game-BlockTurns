local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")

local remotes = shared:FindFirstChild("remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "remotes"
	remotes.Parent = shared
end

local bootClientRemote = remotes:FindFirstChild("bootClient")
if not bootClientRemote then
	bootClientRemote = Instance.new("RemoteEvent")
	bootClientRemote.Name = "bootClient"
	bootClientRemote.Parent = remotes
end

return {
	bootClient = {
		Remote = bootClientRemote,

		Fire = function(player: Player, ...)
			bootClientRemote:FireClient(player, ...)
		end,
	},
}
