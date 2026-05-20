local PlayerSystem = {}

export type CharacterId = "Assault" | "Recon" | "Support"

export type CharacterOption = {
	Id: CharacterId,
	DisplayName: string,
}

type PlayerSystemType = {
	Initialize: () -> (),
	Destroy: () -> (),
	GetCharacterOptions: () -> { CharacterOption },
	GetDefaultCharacterId: () -> CharacterId,
	IsValidCharacter: (characterId: string) -> boolean,
	BeginCharacterSelection: (players: { Player }, matchId: number, roundNumber: number) -> (),
	AssignCharacter: (player: Player, characterId: string) -> CharacterId?,
	EndCharacterSelection: (players: { Player }) -> { [number]: CharacterId },
	ClearCharacterSelection: (player: Player) -> (),
}

local CHARACTER_OPTIONS: { CharacterOption } = table.freeze({
	{
		Id = "Assault",
		DisplayName = "Assault",
	},
	{
		Id = "Recon",
		DisplayName = "Recon",
	},
	{
		Id = "Support",
		DisplayName = "Support",
	},
})

local DEFAULT_CHARACTER_ID: CharacterId = "Assault"

local validCharacters: { [string]: boolean } = {}
local initialized = false

for _, option in CHARACTER_OPTIONS do
	validCharacters[option.Id] = true
end

function PlayerSystem.GetCharacterOptions(): { CharacterOption }
	return table.clone(CHARACTER_OPTIONS)
end

function PlayerSystem.GetDefaultCharacterId(): CharacterId
	return DEFAULT_CHARACTER_ID
end

function PlayerSystem.IsValidCharacter(characterId: string): boolean
	return validCharacters[characterId] == true
end

function PlayerSystem.BeginCharacterSelection(players: { Player }, matchId: number, roundNumber: number)
	for _, player in players do
		player:SetAttribute("MatchId", matchId)
		player:SetAttribute("MatchRound", roundNumber)
		player:SetAttribute("SelectedCharacter", nil)
		player:SetAttribute("CanSelectCharacter", true)
	end
end

function PlayerSystem.AssignCharacter(player: Player, characterId: string): CharacterId?
	if not PlayerSystem.IsValidCharacter(characterId) then
		return nil
	end

	local selectedCharacter = characterId :: CharacterId
	player:SetAttribute("SelectedCharacter", selectedCharacter)

	return selectedCharacter
end

function PlayerSystem.EndCharacterSelection(players: { Player }): { [number]: CharacterId }
	local selections: { [number]: CharacterId } = {}

	for _, player in players do
		local selectedCharacter = player:GetAttribute("SelectedCharacter")

		if type(selectedCharacter) ~= "string" or not PlayerSystem.IsValidCharacter(selectedCharacter) then
			selectedCharacter = DEFAULT_CHARACTER_ID
			player:SetAttribute("SelectedCharacter", selectedCharacter)
		end

		player:SetAttribute("CanSelectCharacter", false)
		selections[player.UserId] = selectedCharacter :: CharacterId
	end

	return selections
end

function PlayerSystem.ClearCharacterSelection(player: Player)
	player:SetAttribute("SelectedCharacter", nil)
	player:SetAttribute("CanSelectCharacter", nil)
end

function PlayerSystem.Initialize()
	if initialized then
		return
	end

	initialized = true
end

function PlayerSystem.Destroy()
	if not initialized then
		return
	end

	initialized = false
end

return {
	PlayerSystem = PlayerSystem :: PlayerSystemType,
}
