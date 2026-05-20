local TeamSystem = {}

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")

export type MatchTeamName = "Blue" | "Red"

export type MatchAssignment = {
	Player: Player,
	Team: MatchTeamName,
}

type MatchTeams = {
	Blue: Team,
	Red: Team,
}

type TeamSystemType = {
	TeamSize: number,
	RequiredPlayers: number,
	Initialize: () -> (),
	Destroy: () -> (),
	GetMatchTeams: () -> MatchTeams,
	ClearPlayerTeam: (player: Player) -> (),
	AssignMatchTeams: (matchId: number, players: { Player }) -> { MatchAssignment },
}

local TEAM_SIZE = 5
local REQUIRED_PLAYERS = TEAM_SIZE * 2

local TEAM_COLORS: { [MatchTeamName]: BrickColor } = {
	Blue = BrickColor.new("Bright blue"),
	Red = BrickColor.new("Bright red"),
}

local rng = Random.new()
local initialized = false
local matchTeams: MatchTeams?

TeamSystem.TeamSize = TEAM_SIZE
TeamSystem.RequiredPlayers = REQUIRED_PLAYERS

local function getOrCreateTeam(name: MatchTeamName): Team
	local existing = Teams:FindFirstChild(name)
	local color = TEAM_COLORS[name]

	if existing and existing:IsA("Team") then
		existing.TeamColor = color
		existing.AutoAssignable = false
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local team = Instance.new("Team")
	team.Name = name
	team.TeamColor = color
	team.AutoAssignable = false
	team.Parent = Teams

	return team
end

local function shufflePlayers(players: { Player }): { Player }
	local shuffled = table.clone(players)

	for index = #shuffled, 2, -1 do
		local swapIndex = rng:NextInteger(1, index)
		shuffled[index], shuffled[swapIndex] = shuffled[swapIndex], shuffled[index]
	end

	return shuffled
end

local function assertValidPlayers(players: { Player })
	assert(#players == REQUIRED_PLAYERS, `Expected {REQUIRED_PLAYERS} players, got {#players}`)

	local seenUserIds: { [number]: boolean } = {}

	for _, player in players do
		assert(player.Parent == Players, `Player {player.Name} is not in Players`)
		assert(not seenUserIds[player.UserId], `Player {player.Name} was assigned twice`)
		seenUserIds[player.UserId] = true
	end
end

function TeamSystem.GetMatchTeams(): MatchTeams
	if matchTeams == nil then
		matchTeams = {
			Blue = getOrCreateTeam("Blue"),
			Red = getOrCreateTeam("Red"),
		}
	end

	return matchTeams
end

function TeamSystem.ClearPlayerTeam(player: Player)
	player.Team = nil
	player.Neutral = true
	player:SetAttribute("MatchId", nil)
	player:SetAttribute("MatchTeam", nil)
end

function TeamSystem.AssignMatchTeams(matchId: number, players: { Player }): { MatchAssignment }
	assertValidPlayers(players)

	local teams = TeamSystem.GetMatchTeams()
	local shuffled = shufflePlayers(players)
	local assignments: { MatchAssignment } = {}

	for index, player in shuffled do
		local teamName: MatchTeamName = if index <= TEAM_SIZE then "Blue" else "Red"

		player.Team = teams[teamName]
		player.Neutral = false
		player:SetAttribute("MatchId", matchId)
		player:SetAttribute("MatchTeam", teamName)

		table.insert(assignments, {
			Player = player,
			Team = teamName,
		})
	end

	return assignments
end

function TeamSystem.Initialize()
	if initialized then
		return
	end

	initialized = true
	TeamSystem.GetMatchTeams()
end

function TeamSystem.Destroy()
	if not initialized then
		return
	end

	initialized = false
end

return TeamSystem :: TeamSystemType
