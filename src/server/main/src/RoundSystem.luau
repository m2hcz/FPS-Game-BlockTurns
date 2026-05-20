local RoundSystem = {}

local Players = game:GetService("Players")

local src = script.Parent
local TeamSystem = require(src:WaitForChild("TeamSystem"))

export type MatchStatus = "Waiting" | "Active"

export type MatchPlayer = {
	Player: Player,
	Team: "Blue" | "Red",
}

export type Match = {
	Id: number,
	Status: MatchStatus,
	CreatedAtUnix: number,
	Players: { MatchPlayer },
}

type Connection = {
	Disconnect: (self: Connection) -> (),
}

type RoundSystemType = {
	RequiredPlayers: number,
	TeamSize: number,
	Initialize: () -> (),
	Destroy: () -> (),
	GetCurrentMatch: () -> Match?,
	GetQueuedPlayers: () -> { Player },
	TryCreateMatch: () -> Match?,
}

local TEAM_SIZE = TeamSystem.TeamSize
local REQUIRED_PLAYERS = TEAM_SIZE * 2

local initialized = false
local nextMatchId = 0
local currentMatch: Match?
local queuedPlayers: { [number]: Player } = {}
local connections: { Connection } = {}

RoundSystem.TeamSize = TEAM_SIZE
RoundSystem.RequiredPlayers = REQUIRED_PLAYERS

local function nowUnix(): number
	return DateTime.now().UnixTimestamp
end

local function isPlayerEligible(player: Player): boolean
	return player.Parent == Players
end

local function removeQueuedPlayer(userId: number)
	queuedPlayers[userId] = nil
end

local function queuePlayer(player: Player)
	if not isPlayerEligible(player) then
		return
	end

	queuedPlayers[player.UserId] = player
end

local function getQueuedPlayers(): { Player }
	local players = {}

	for userId, player in queuedPlayers do
		if isPlayerEligible(player) then
			table.insert(players, player)
		else
			queuedPlayers[userId] = nil
		end
	end

	table.sort(players, function(left, right)
		return left.UserId < right.UserId
	end)

	return players
end

local function popMatchPlayers(): { Player }?
	local players = getQueuedPlayers()

	if #players < REQUIRED_PLAYERS then
		return nil
	end

	local matchPlayers = {}

	for index = 1, REQUIRED_PLAYERS do
		local player = players[index]
		removeQueuedPlayer(player.UserId)
		table.insert(matchPlayers, player)
	end

	return matchPlayers
end

local function createMatch(players: { Player }): Match
	nextMatchId += 1

	local assignments = TeamSystem.AssignMatchTeams(players)
	local matchPlayers: { MatchPlayer } = {}

	for _, player in players do
		table.insert(matchPlayers, {
			Player = player,
			Team = assignments[player],
		})
	end

	local match: Match = {
		Id = nextMatchId,
		Status = "Active",
		CreatedAtUnix = nowUnix(),
		Players = matchPlayers,
	}

	currentMatch = match
	return match
end

local function onPlayerRemoving(player: Player)
	removeQueuedPlayer(player.UserId)

	if currentMatch == nil then
		return
	end

	for _, matchPlayer in currentMatch.Players do
		if matchPlayer.Player == player then
			currentMatch.Status = "Waiting"
			break
		end
	end
end

function RoundSystem.GetCurrentMatch(): Match?
	return currentMatch
end

function RoundSystem.GetQueuedPlayers(): { Player }
	return getQueuedPlayers()
end

function RoundSystem.TryCreateMatch(): Match?
	if currentMatch ~= nil and currentMatch.Status == "Active" then
		return currentMatch
	end

	local players = popMatchPlayers()

	if players == nil then
		return nil
	end

	return createMatch(players)
end

function RoundSystem.Initialize()
	if initialized then
		return
	end

	initialized = true

	table.insert(connections, Players.PlayerAdded:Connect(function(player)
		queuePlayer(player)
		RoundSystem.TryCreateMatch()
	end))

	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))

	for _, player in Players:GetPlayers() do
		queuePlayer(player)
	end

	RoundSystem.TryCreateMatch()
end

function RoundSystem.Destroy()
	if not initialized then
		return
	end

	initialized = false

	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
	table.clear(queuedPlayers)
	currentMatch = nil
end

return RoundSystem :: RoundSystemType
