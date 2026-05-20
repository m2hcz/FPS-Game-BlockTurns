local TeamSystem = {}

local Teams = game:GetService("Teams")

export type MatchTeamName = "Blue" | "Red"

type MatchTeams = {
	Blue: Team,
	Red: Team,
}

type TeamSystemType = {
	TeamSize: number,
	Initialize: () -> (),
	Destroy: () -> (),
	GetMatchTeams: () -> MatchTeams,
	ClearPlayerTeam: (player: Player) -> (),
	AssignMatchTeams: (players: { Player }) -> { [Player]: MatchTeamName },
}

local TEAM_SIZE = 5

local initialized = false
local matchTeams: MatchTeams?

TeamSystem.TeamSize = TEAM_SIZE

local function getOrCreateTeam(name: MatchTeamName, color: BrickColor): Team
	local existing = Teams:FindFirstChild(name)

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
		local swapIndex = Random.new():NextInteger(1, index)
		shuffled[index], shuffled[swapIndex] = shuffled[swapIndex], shuffled[index]
	end

	return shuffled
end

function TeamSystem.GetMatchTeams(): MatchTeams
	if matchTeams == nil then
		matchTeams = {
			Blue = getOrCreateTeam("Blue", BrickColor.new("Bright blue")),
			Red = getOrCreateTeam("Red", BrickColor.new("Bright red")),
		}
	end

	return matchTeams
end

function TeamSystem.ClearPlayerTeam(player: Player)
	player.Team = nil
	player.Neutral = true
end

function TeamSystem.AssignMatchTeams(players: { Player }): { [Player]: MatchTeamName }
	assert(#players == TEAM_SIZE * 2, `Expected {TEAM_SIZE * 2} players, got {#players}`)

	local teams = TeamSystem.GetMatchTeams()
	local assignments: { [Player]: MatchTeamName } = {}
	local shuffled = shufflePlayers(players)

	for index, player in shuffled do
		local teamName: MatchTeamName = if index <= TEAM_SIZE then "Blue" else "Red"
		local team = teams[teamName]

		player.Team = team
		player.Neutral = false
		assignments[player] = teamName
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
