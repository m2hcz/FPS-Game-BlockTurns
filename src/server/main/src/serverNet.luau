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

local function getOrCreateRemoteEvent(name: string): RemoteEvent
	local existing = remotes:FindFirstChild(name)

	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = name
	remoteEvent.Parent = remotes

	return remoteEvent
end

local matchPhaseRemote = getOrCreateRemoteEvent("matchPhase")
local selectCharacterRemote = getOrCreateRemoteEvent("selectCharacter")
local selectWeaponRemote = getOrCreateRemoteEvent("selectWeapon")

return {
	bootClient = {
		Remote = bootClientRemote,

		Fire = function(player: Player, ...)
			bootClientRemote:FireClient(player, ...)
		end,
	},

	matchPhase = {
		Remote = matchPhaseRemote,

		Fire = function(player: Player, ...)
			matchPhaseRemote:FireClient(player, ...)
		end,
	},

	selectCharacter = {
		Remote = selectCharacterRemote,
	},

	selectWeapon = {
		Remote = selectWeaponRemote,
	},
}
