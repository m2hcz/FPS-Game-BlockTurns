local RoundSystem = {}

local Players = game:GetService("Players")

local src = script.Parent
local DataManager = require(src:WaitForChild("DataManager"))
local TeamSystem = require(src:WaitForChild("TeamSystem"))

export type MatchStatus = "Active" | "Cancelled" | "Ended"

export type MatchPlayer = {
	Player: Player,
	UserId: number,
	Team: "Blue" | "Red",
}

export type Match = {
	Id: number,
	Status: MatchStatus,
	CreatedAtUnix: number,
	EndedAtUnix: number?,
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
	GetActiveMatches: () -> { Match },
	GetMatchForPlayer: (player: Player) -> Match?,
	GetQueuedPlayers: () -> { Player },
	TryCreateMatch: () -> Match?,
	TryCreateMatches: () -> { Match },
	EndMatch: (matchId: number) -> (),
}

local TEAM_SIZE = TeamSystem.TeamSize
local REQUIRED_PLAYERS = TeamSystem.RequiredPlayers
local MATCH_READY_TIMEOUT_SECONDS = 30

local initialized = false
local nextMatchId = 0
local queue: { Player } = {}
local queuedUserIds: { [number]: boolean } = {}
local waitingForDataUserIds: { [number]: boolean } = {}
local activeMatches: { [number]: Match } = {}
local playerMatchIds: { [number]: number } = {}
local connections: { Connection } = {}

RoundSystem.TeamSize = TEAM_SIZE
RoundSystem.RequiredPlayers = REQUIRED_PLAYERS

local function nowUnix(): number
	return DateTime.now().UnixTimestamp
end

local function isPlayerInGame(player: Player): boolean
	return player.Parent == Players
end

local function isPlayerAvailable(player: Player): boolean
	return isPlayerInGame(player) and playerMatchIds[player.UserId] == nil
end

local function removeQueuedPlayer(userId: number)
	if not queuedUserIds[userId] then
		return
	end

	queuedUserIds[userId] = nil

	for index = #queue, 1, -1 do
		if queue[index].UserId == userId then
			table.remove(queue, index)
			return
		end
	end
end

local function compactQueue()
	for index = #queue, 1, -1 do
		local player = queue[index]

		if not isPlayerAvailable(player) then
			queuedUserIds[player.UserId] = nil
			table.remove(queue, index)
		end
	end
end

local function queuePlayer(player: Player)
	if not isPlayerAvailable(player) or queuedUserIds[player.UserId] then
		return
	end

	queuedUserIds[player.UserId] = true
	table.insert(queue, player)
end

local function queuePlayerWhenReady(player: Player)
	if not initialized or not isPlayerInGame(player) or waitingForDataUserIds[player.UserId] then
		return
	end

	waitingForDataUserIds[player.UserId] = true

	task.spawn(function()
		local userId = player.UserId
		local data = DataManager.WaitForData(player, MATCH_READY_TIMEOUT_SECONDS)
		waitingForDataUserIds[userId] = nil

		if not initialized or data == nil or not isPlayerAvailable(player) then
			return
		end

		queuePlayer(player)
		RoundSystem.TryCreateMatches()
	end)
end

local function popMatchPlayers(): { Player }?
	compactQueue()

	if #queue < REQUIRED_PLAYERS then
		return nil
	end

	local players = {}

	while #players < REQUIRED_PLAYERS and #queue > 0 do
		local player = table.remove(queue, 1)
		queuedUserIds[player.UserId] = nil

		if isPlayerAvailable(player) then
			table.insert(players, player)
		end
	end

	if #players < REQUIRED_PLAYERS then
		for _, player in players do
			queuePlayer(player)
		end

		return nil
	end

	return players
end

local function releaseMatchPlayers(match: Match, requeuePlayers: boolean, excludedUserId: number?)
	for _, matchPlayer in match.Players do
		local player = matchPlayer.Player
		playerMatchIds[matchPlayer.UserId] = nil

		if isPlayerInGame(player) then
			TeamSystem.ClearPlayerTeam(player)

			if requeuePlayers and matchPlayer.UserId ~= excludedUserId then
				queuePlayer(player)
			end
		end
	end
end

local function createMatch(players: { Player }): Match
	nextMatchId += 1

	local assignments = TeamSystem.AssignMatchTeams(nextMatchId, players)
	local matchPlayers: { MatchPlayer } = {}

	for _, assignment in assignments do
		playerMatchIds[assignment.Player.UserId] = nextMatchId

		table.insert(matchPlayers, {
			Player = assignment.Player,
			UserId = assignment.Player.UserId,
			Team = assignment.Team,
		})
	end

	local match: Match = {
		Id = nextMatchId,
		Status = "Active",
		CreatedAtUnix = nowUnix(),
		Players = matchPlayers,
	}

	activeMatches[match.Id] = match
	return match
end

local function cancelMatch(matchId: number, requeuePlayers: boolean, excludedUserId: number?)
	local match = activeMatches[matchId]

	if match == nil or match.Status ~= "Active" then
		return
	end

	match.Status = "Cancelled"
	match.EndedAtUnix = nowUnix()
	activeMatches[matchId] = nil

	releaseMatchPlayers(match, requeuePlayers, excludedUserId)
end

local function onPlayerRemoving(player: Player)
	waitingForDataUserIds[player.UserId] = nil
	removeQueuedPlayer(player.UserId)

	local matchId = playerMatchIds[player.UserId]
	if matchId ~= nil then
		cancelMatch(matchId, true, player.UserId)
		RoundSystem.TryCreateMatches()
	end
end

function RoundSystem.GetCurrentMatch(): Match?
	local matches = RoundSystem.GetActiveMatches()
	return matches[1]
end

function RoundSystem.GetActiveMatches(): { Match }
	local matches = {}

	for _, match in activeMatches do
		table.insert(matches, match)
	end

	table.sort(matches, function(left, right)
		return left.Id < right.Id
	end)

	return matches
end

function RoundSystem.GetMatchForPlayer(player: Player): Match?
	local matchId = playerMatchIds[player.UserId]

	if matchId == nil then
		return nil
	end

	return activeMatches[matchId]
end

function RoundSystem.GetQueuedPlayers(): { Player }
	compactQueue()
	return table.clone(queue)
end

function RoundSystem.TryCreateMatch(): Match?
	local players = popMatchPlayers()

	if players == nil then
		return nil
	end

	return createMatch(players)
end

function RoundSystem.TryCreateMatches(): { Match }
	local createdMatches = {}

	while true do
		local match = RoundSystem.TryCreateMatch()

		if match == nil then
			break
		end

		table.insert(createdMatches, match)
	end

	return createdMatches
end

function RoundSystem.EndMatch(matchId: number)
	local match = activeMatches[matchId]

	if match == nil or match.Status ~= "Active" then
		return
	end

	match.Status = "Ended"
	match.EndedAtUnix = nowUnix()
	activeMatches[matchId] = nil

	releaseMatchPlayers(match, false, nil)
end

function RoundSystem.Initialize()
	if initialized then
		return
	end

	initialized = true

	table.insert(connections, Players.PlayerAdded:Connect(function(player)
		queuePlayerWhenReady(player)
	end))

	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))

	for _, player in Players:GetPlayers() do
		queuePlayerWhenReady(player)
	end
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
	table.clear(queue)
	table.clear(queuedUserIds)
	table.clear(waitingForDataUserIds)

	local matchIds = {}
	for matchId in activeMatches do
		table.insert(matchIds, matchId)
	end

	for _, matchId in matchIds do
		cancelMatch(matchId, false)
	end

	table.clear(activeMatches)
	table.clear(playerMatchIds)
end

return RoundSystem :: RoundSystemType
