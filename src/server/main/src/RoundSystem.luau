local RoundSystem = {}

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local src = script.Parent
local DataManager = require(src:WaitForChild("DataManager"))
local PlayerSystem = require(src:WaitForChild("PlayerSystem")).PlayerSystem
local TeamSystem = require(src:WaitForChild("TeamSystem"))
local WeaponSystem = require(src:WaitForChild("WeaponSystem"))
local serverNet = require(src:WaitForChild("serverNet"))

export type MatchStatus = "Active" | "Cancelled" | "Ended"
export type MatchPhase = "CharacterSelection" | "WeaponSelection" | "Action" | "RoundEnded"
export type MatchTeamName = "Blue" | "Red"
type MatchHistoryResult = "Win" | "Loss" | "Draw"

export type MatchPlayer = {
	Player: Player,
	UserId: number,
	Team: MatchTeamName,
}

export type MatchScores = {
	Blue: number,
	Red: number,
}

export type Match = {
	Id: number,
	Key: string,
	Status: MatchStatus,
	Phase: MatchPhase,
	PhaseToken: number,
	PhaseStartedAtUnix: number,
	PhaseEndsAtUnix: number,
	CreatedAtUnix: number,
	EndedAtUnix: number?,
	RoundNumber: number,
	MaxRounds: number,
	RoundsToWin: number,
	LastRoundWinner: MatchTeamName?,
	Scores: MatchScores,
	Players: { MatchPlayer },
	CharacterSelections: { [number]: string },
	WeaponSelections: { [number]: string },
}

type Connection = {
	Disconnect: (self: Connection) -> (),
}

type RoundSystemType = {
	RequiredPlayers: number,
	TeamSize: number,
	MaxRounds: number,
	RoundsToWin: number,
	Initialize: () -> (),
	Destroy: () -> (),
	GetCurrentMatch: () -> Match?,
	GetActiveMatches: () -> { Match },
	GetMatchForPlayer: (player: Player) -> Match?,
	GetQueuedPlayers: () -> { Player },
	TryCreateMatch: () -> Match?,
	TryCreateMatches: () -> { Match },
	SubmitCharacterSelection: (player: Player, characterId: string) -> boolean,
	SubmitWeaponSelection: (player: Player, weaponId: string) -> boolean,
	EndRound: (matchId: number, winningTeam: MatchTeamName?) -> (),
	EndMatch: (matchId: number) -> (),
}

local TEAM_SIZE = TeamSystem.TeamSize
local REQUIRED_PLAYERS = TeamSystem.RequiredPlayers

local MATCH_READY_TIMEOUT_SECONDS = 30
local CHARACTER_SELECTION_SECONDS = 20
local WEAPON_SELECTION_SECONDS = 15
local ACTION_SECONDS = 180
local ROUND_END_SECONDS = 5
local MAX_ROUNDS = 5
local ROUNDS_TO_WIN = 3
local SERVER_MATCH_SCOPE = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)

local PHASE_DURATIONS: { [MatchPhase]: number } = {
	CharacterSelection = CHARACTER_SELECTION_SECONDS,
	WeaponSelection = WEAPON_SELECTION_SECONDS,
	Action = ACTION_SECONDS,
	RoundEnded = ROUND_END_SECONDS,
}

local initialized = false
local nextMatchId = 0
local queue: { Player } = {}
local queueHead = 1
local queueTail = 0
local queuedCount = 0
local staleQueueSlots = 0
local queuedUserIds: { [number]: boolean } = {}
local waitingForDataTokens: { [number]: number } = {}
local nextReadyWaitToken = 0
local activeMatches: { [number]: Match } = {}
local playerMatchIds: { [number]: number } = {}
local connections: { Connection } = {}
local creatingMatches = false

RoundSystem.TeamSize = TEAM_SIZE
RoundSystem.RequiredPlayers = REQUIRED_PLAYERS
RoundSystem.MaxRounds = MAX_ROUNDS
RoundSystem.RoundsToWin = ROUNDS_TO_WIN

local onPhaseExpired

local function nowUnix(): number
	return DateTime.now().UnixTimestamp
end

local function isPlayerInGame(player: Player): boolean
	return player.Parent == Players
end

local function isPlayerAvailable(player: Player): boolean
	return isPlayerInGame(player) and playerMatchIds[player.UserId] == nil
end

local function trimQueueBuffer()
	if queueTail == 0 then
		return
	end

	local staleLimit = math.max(32, queuedCount)

	if queueHead < 64 and queueHead < queueTail / 2 and staleQueueSlots < staleLimit then
		return
	end

	local writeIndex = 1

	for readIndex = queueHead, queueTail do
		local player = queue[readIndex]

		if player ~= nil and queuedUserIds[player.UserId] then
			queue[writeIndex] = player
			writeIndex += 1
		end
	end

	for index = writeIndex, queueTail do
		queue[index] = nil
	end

	queueHead = 1
	queueTail = writeIndex - 1
	staleQueueSlots = 0
end

local function advanceQueueHead()
	while queueHead <= queueTail do
		local player = queue[queueHead]

		if player ~= nil and queuedUserIds[player.UserId] then
			break
		end

		queue[queueHead] = nil
		queueHead += 1
	end

	trimQueueBuffer()
end

local function resetQueue()
	table.clear(queue)
	table.clear(queuedUserIds)

	queueHead = 1
	queueTail = 0
	queuedCount = 0
	staleQueueSlots = 0
end

local function removeQueuedPlayer(userId: number)
	if not queuedUserIds[userId] then
		return
	end

	queuedUserIds[userId] = nil
	queuedCount = math.max(queuedCount - 1, 0)
	staleQueueSlots += 1

	advanceQueueHead()
end

local function compactQueue()
	for index = queueHead, queueTail do
		local player = queue[index]

		if player ~= nil and queuedUserIds[player.UserId] and not isPlayerAvailable(player) then
			queuedUserIds[player.UserId] = nil
			queuedCount = math.max(queuedCount - 1, 0)
			staleQueueSlots += 1
			queue[index] = nil
		end
	end

	advanceQueueHead()
end

local function queuePlayer(player: Player)
	if not isPlayerAvailable(player) or queuedUserIds[player.UserId] then
		return
	end

	queuedUserIds[player.UserId] = true
	queuedCount += 1
	queueTail += 1
	queue[queueTail] = player
end

local function queuePlayerWhenReady(player: Player)
	if not initialized or not isPlayerInGame(player) or waitingForDataTokens[player.UserId] ~= nil then
		return
	end

	nextReadyWaitToken += 1

	local userId = player.UserId
	local waitToken = nextReadyWaitToken
	waitingForDataTokens[userId] = waitToken

	task.spawn(function()
		local data = DataManager.WaitForData(player, MATCH_READY_TIMEOUT_SECONDS)

		if waitingForDataTokens[userId] ~= waitToken then
			return
		end

		waitingForDataTokens[userId] = nil

		if not initialized or data == nil or not isPlayerAvailable(player) then
			return
		end

		queuePlayer(player)
		RoundSystem.TryCreateMatches()
	end)
end

local function popMatchPlayers(): { Player }?
	compactQueue()

	if queuedCount < REQUIRED_PLAYERS then
		return nil
	end

	local players = {}

	while #players < REQUIRED_PLAYERS and queueHead <= queueTail do
		local player = queue[queueHead]
		queue[queueHead] = nil
		queueHead += 1

		if player == nil or not queuedUserIds[player.UserId] then
			continue
		end

		queuedUserIds[player.UserId] = nil
		queuedCount = math.max(queuedCount - 1, 0)

		if isPlayerAvailable(player) then
			table.insert(players, player)
		end
	end

	advanceQueueHead()

	if #players < REQUIRED_PLAYERS then
		for _, player in players do
			queuePlayer(player)
		end

		return nil
	end

	return players
end

local function getMatchPlayerInstances(match: Match): { Player }
	local players = {}

	for _, matchPlayer in match.Players do
		local player = matchPlayer.Player

		if isPlayerInGame(player) then
			table.insert(players, player)
		end
	end

	return players
end

local function getWinningTeam(match: Match): MatchTeamName?
	if match.Scores.Blue > match.Scores.Red then
		return "Blue"
	end

	if match.Scores.Red > match.Scores.Blue then
		return "Red"
	end

	return nil
end

local function getResultForTeam(match: Match, teamName: MatchTeamName): MatchHistoryResult
	local winningTeam = getWinningTeam(match)

	if winningTeam == nil then
		return "Draw"
	end

	if winningTeam == teamName then
		return "Win"
	end

	return "Loss"
end

local function buildMatchSnapshot(match: Match, player: Player)
	local teamAttribute = player:GetAttribute("MatchTeam")
	local team: MatchTeamName? = nil
	local winningTeam = if match.Status == "Ended" then getWinningTeam(match) else nil
	local matchResult: MatchHistoryResult? = nil

	if teamAttribute == "Blue" then
		team = "Blue"
	elseif teamAttribute == "Red" then
		team = "Red"
	end

	if match.Status == "Ended" and team ~= nil then
		matchResult = getResultForTeam(match, team)
	end

	return {
		matchId = match.Id,
		matchKey = match.Key,
		status = match.Status,
		phase = match.Phase,
		phaseStartedAtUnix = match.PhaseStartedAtUnix,
		phaseEndsAtUnix = match.PhaseEndsAtUnix,
		roundNumber = match.RoundNumber,
		maxRounds = match.MaxRounds,
		roundsToWin = match.RoundsToWin,
		lastRoundWinner = match.LastRoundWinner,
		winningTeam = winningTeam,
		matchResult = matchResult,
		scoreBlue = match.Scores.Blue,
		scoreRed = match.Scores.Red,
		team = team,
		selectedCharacter = player:GetAttribute("SelectedCharacter"),
		selectedWeapon = player:GetAttribute("SelectedWeapon"),
		characterOptions = PlayerSystem.GetCharacterOptions(),
		weaponOptions = WeaponSystem.GetWeaponOptions(),
	}
end

local function notifyMatch(match: Match)
	for _, matchPlayer in match.Players do
		local player = matchPlayer.Player

		if isPlayerInGame(player) then
			serverNet.matchPhase.Fire(player, buildMatchSnapshot(match, player))
		end
	end
end

local function setMatchAttributes(match: Match)
	for _, matchPlayer in match.Players do
		local player = matchPlayer.Player

		if isPlayerInGame(player) then
			player:SetAttribute("MatchStatus", match.Status)
			player:SetAttribute("MatchRound", match.RoundNumber)
			player:SetAttribute("MatchPhase", match.Phase)
			player:SetAttribute("MatchPhaseEndsAtUnix", match.PhaseEndsAtUnix)
			player:SetAttribute("MatchScoreBlue", match.Scores.Blue)
			player:SetAttribute("MatchScoreRed", match.Scores.Red)
		end
	end
end

local function clearMatchAttributes(player: Player)
	player:SetAttribute("MatchStatus", nil)
	player:SetAttribute("MatchRound", nil)
	player:SetAttribute("MatchPhase", nil)
	player:SetAttribute("MatchPhaseEndsAtUnix", nil)
	player:SetAttribute("MatchScoreBlue", nil)
	player:SetAttribute("MatchScoreRed", nil)
	PlayerSystem.ClearCharacterSelection(player)
	WeaponSystem.ClearWeaponSelection(player)
	TeamSystem.ClearPlayerTeam(player)
end

local function setMatchPhase(match: Match, phase: MatchPhase)
	local timestamp = nowUnix()
	local duration = PHASE_DURATIONS[phase]

	match.Phase = phase
	match.PhaseStartedAtUnix = timestamp
	match.PhaseEndsAtUnix = timestamp + duration
	match.PhaseToken += 1

	setMatchAttributes(match)
	notifyMatch(match)

	local matchId = match.Id
	local phaseToken = match.PhaseToken

	task.delay(duration, function()
		onPhaseExpired(matchId, phase, phaseToken)
	end)
end

local function recordMatchResults(match: Match)
	if match.Status ~= "Ended" then
		return
	end

	for _, matchPlayer in match.Players do
		local player = matchPlayer.Player

		if not isPlayerInGame(player) then
			continue
		end

		local selectedCharacter = player:GetAttribute("SelectedCharacter")
		local selectedWeapon = player:GetAttribute("SelectedWeapon")

		local recorded = false
		local ok, err = pcall(function()
			recorded = DataManager.RecordMatchResult(player, {
				MatchKey = match.Key,
				MatchId = match.Id,
				Result = getResultForTeam(match, matchPlayer.Team),
				Team = matchPlayer.Team,
				ScoreBlue = match.Scores.Blue,
				ScoreRed = match.Scores.Red,
				RoundCount = match.RoundNumber,
				StartedAtUnix = match.CreatedAtUnix,
				EndedAtUnix = match.EndedAtUnix or nowUnix(),
				SelectedCharacter = if type(selectedCharacter) == "string" then selectedCharacter else nil,
				SelectedWeapon = if type(selectedWeapon) == "string" then selectedWeapon else nil,
			})
		end)

		if not ok then
			warn(`Failed to record match result for {player.Name}: {err}`)
		elseif not recorded then
			warn(`Skipped match result for {player.Name}: player data was not loaded`)
		end
	end
end

local function releaseMatchPlayers(match: Match, requeuePlayers: boolean, excludedUserId: number?)
	for _, matchPlayer in match.Players do
		local player = matchPlayer.Player
		playerMatchIds[matchPlayer.UserId] = nil

		if isPlayerInGame(player) then
			clearMatchAttributes(player)

			if requeuePlayers and matchPlayer.UserId ~= excludedUserId then
				queuePlayer(player)
			end
		end
	end
end

local function finishMatch(matchId: number, status: MatchStatus, requeuePlayers: boolean, excludedUserId: number?)
	local match = activeMatches[matchId]

	if match == nil or match.Status ~= "Active" then
		return
	end

	match.Status = status
	match.EndedAtUnix = nowUnix()
	match.PhaseToken += 1
	activeMatches[matchId] = nil

	recordMatchResults(match)
	setMatchAttributes(match)
	notifyMatch(match)
	releaseMatchPlayers(match, requeuePlayers, excludedUserId)

	if requeuePlayers then
		RoundSystem.TryCreateMatches()
	end
end

local function hasEverySelection(match: Match, selections: { [number]: string }): boolean
	for _, matchPlayer in match.Players do
		if selections[matchPlayer.UserId] == nil then
			return false
		end
	end

	return true
end

local function startWeaponSelection(match: Match)
	local players = getMatchPlayerInstances(match)

	if #players < REQUIRED_PLAYERS then
		finishMatch(match.Id, "Cancelled", true, nil)
		return
	end

	WeaponSystem.BeginWeaponSelection(players, match.Id, match.RoundNumber)
	setMatchPhase(match, "WeaponSelection")
end

local function startActionPhase(match: Match)
	local players = getMatchPlayerInstances(match)

	if #players < REQUIRED_PLAYERS then
		finishMatch(match.Id, "Cancelled", true, nil)
		return
	end

	setMatchPhase(match, "Action")
end

local function finishCharacterSelection(match: Match)
	if match.Phase ~= "CharacterSelection" or match.Status ~= "Active" then
		return
	end

	match.CharacterSelections = PlayerSystem.EndCharacterSelection(getMatchPlayerInstances(match))
	startWeaponSelection(match)
end

local function finishWeaponSelection(match: Match)
	if match.Phase ~= "WeaponSelection" or match.Status ~= "Active" then
		return
	end

	match.WeaponSelections = WeaponSystem.EndWeaponSelection(getMatchPlayerInstances(match))
	startActionPhase(match)
end

local function shouldFinishMatch(match: Match): boolean
	return match.Scores.Blue >= match.RoundsToWin
		or match.Scores.Red >= match.RoundsToWin
		or match.RoundNumber >= match.MaxRounds
end

local function startRound(match: Match)
	if match.Status ~= "Active" then
		return
	end

	local players = getMatchPlayerInstances(match)

	if #players < REQUIRED_PLAYERS then
		finishMatch(match.Id, "Cancelled", true, nil)
		return
	end

	match.RoundNumber += 1
	match.LastRoundWinner = nil
	table.clear(match.CharacterSelections)
	table.clear(match.WeaponSelections)

	PlayerSystem.BeginCharacterSelection(players, match.Id, match.RoundNumber)
	for _, player in players do
		WeaponSystem.ClearWeaponSelection(player)
	end

	setMatchPhase(match, "CharacterSelection")
end

local function finishRoundEndPhase(match: Match)
	if shouldFinishMatch(match) then
		finishMatch(match.Id, "Ended", true, nil)
	else
		startRound(match)
	end
end

onPhaseExpired = function(matchId: number, phase: MatchPhase, phaseToken: number)
	local match = activeMatches[matchId]

	if match == nil or match.Status ~= "Active" then
		return
	end

	if match.Phase ~= phase or match.PhaseToken ~= phaseToken then
		return
	end

	if phase == "CharacterSelection" then
		finishCharacterSelection(match)
	elseif phase == "WeaponSelection" then
		finishWeaponSelection(match)
	elseif phase == "Action" then
		RoundSystem.EndRound(matchId, nil)
	elseif phase == "RoundEnded" then
		finishRoundEndPhase(match)
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

	local timestamp = nowUnix()
	local match: Match = {
		Id = nextMatchId,
		Key = `{SERVER_MATCH_SCOPE}:{nextMatchId}`,
		Status = "Active",
		Phase = "CharacterSelection",
		PhaseToken = 0,
		PhaseStartedAtUnix = timestamp,
		PhaseEndsAtUnix = timestamp,
		CreatedAtUnix = timestamp,
		RoundNumber = 0,
		MaxRounds = MAX_ROUNDS,
		RoundsToWin = ROUNDS_TO_WIN,
		Scores = {
			Blue = 0,
			Red = 0,
		},
		Players = matchPlayers,
		CharacterSelections = {},
		WeaponSelections = {},
	}

	activeMatches[match.Id] = match
	startRound(match)

	return match
end

local function onPlayerRemoving(player: Player)
	waitingForDataTokens[player.UserId] = nil
	removeQueuedPlayer(player.UserId)

	local matchId = playerMatchIds[player.UserId]
	if matchId ~= nil then
		finishMatch(matchId, "Cancelled", true, player.UserId)
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

	local players = {}

	for index = queueHead, queueTail do
		local player = queue[index]

		if player ~= nil and queuedUserIds[player.UserId] then
			table.insert(players, player)
		end
	end

	return players
end

function RoundSystem.TryCreateMatch(): Match?
	local players = popMatchPlayers()

	if players == nil then
		return nil
	end

	return createMatch(players)
end

function RoundSystem.TryCreateMatches(): { Match }
	if creatingMatches then
		return {}
	end

	creatingMatches = true

	local ok, result = xpcall(function()
		local createdMatches = {}

		while true do
			local match = RoundSystem.TryCreateMatch()

			if match == nil then
				break
			end

			table.insert(createdMatches, match)
		end

		return createdMatches
	end, debug.traceback)

	creatingMatches = false

	if not ok then
		error(`Failed to create matches: {result}`, 0)
	end

	return result
end

function RoundSystem.SubmitCharacterSelection(player: Player, characterId: string): boolean
	local match = RoundSystem.GetMatchForPlayer(player)

	if match == nil or match.Status ~= "Active" or match.Phase ~= "CharacterSelection" then
		return false
	end

	local selectedCharacter = PlayerSystem.AssignCharacter(player, characterId)

	if selectedCharacter == nil then
		return false
	end

	match.CharacterSelections[player.UserId] = selectedCharacter

	if hasEverySelection(match, match.CharacterSelections) then
		task.defer(function()
			finishCharacterSelection(match)
		end)
	end

	return true
end

function RoundSystem.SubmitWeaponSelection(player: Player, weaponId: string): boolean
	local match = RoundSystem.GetMatchForPlayer(player)

	if match == nil or match.Status ~= "Active" or match.Phase ~= "WeaponSelection" then
		return false
	end

	local selectedWeapon = WeaponSystem.AssignWeapon(player, weaponId)

	if selectedWeapon == nil then
		return false
	end

	match.WeaponSelections[player.UserId] = selectedWeapon

	if hasEverySelection(match, match.WeaponSelections) then
		task.defer(function()
			finishWeaponSelection(match)
		end)
	end

	return true
end

function RoundSystem.EndRound(matchId: number, winningTeam: MatchTeamName?)
	local match = activeMatches[matchId]

	if match == nil or match.Status ~= "Active" or match.Phase ~= "Action" then
		return
	end

	if winningTeam == "Blue" or winningTeam == "Red" then
		match.Scores[winningTeam] += 1
		match.LastRoundWinner = winningTeam
	else
		match.LastRoundWinner = nil
	end

	setMatchPhase(match, "RoundEnded")
end

function RoundSystem.EndMatch(matchId: number)
	finishMatch(matchId, "Ended", false, nil)
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

	table.insert(connections, serverNet.selectCharacter.Remote.OnServerEvent:Connect(function(player, characterId)
		if type(characterId) == "string" then
			RoundSystem.SubmitCharacterSelection(player, characterId)
		end
	end))

	table.insert(connections, serverNet.selectWeapon.Remote.OnServerEvent:Connect(function(player, weaponId)
		if type(weaponId) == "string" then
			RoundSystem.SubmitWeaponSelection(player, weaponId)
		end
	end))

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
	resetQueue()
	table.clear(waitingForDataTokens)

	local matchIds = {}
	for matchId in activeMatches do
		table.insert(matchIds, matchId)
	end

	for _, matchId in matchIds do
		finishMatch(matchId, "Cancelled", false, nil)
	end

	table.clear(activeMatches)
	table.clear(playerMatchIds)
	creatingMatches = false
end

return RoundSystem :: RoundSystemType
