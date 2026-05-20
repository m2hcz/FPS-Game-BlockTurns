local WeaponSystem = {}

export type WeaponId = "Rifle" | "SMG" | "Shotgun"

export type WeaponOption = {
	Id: WeaponId,
	DisplayName: string,
}

type WeaponSystemType = {
	Initialize: () -> (),
	Destroy: () -> (),
	GetWeaponOptions: () -> { WeaponOption },
	GetDefaultWeaponId: () -> WeaponId,
	IsValidWeapon: (weaponId: string) -> boolean,
	BeginWeaponSelection: (players: { Player }, matchId: number, roundNumber: number) -> (),
	AssignWeapon: (player: Player, weaponId: string) -> WeaponId?,
	EndWeaponSelection: (players: { Player }) -> { [number]: WeaponId },
	ClearWeaponSelection: (player: Player) -> (),
}

local WEAPON_OPTIONS: { WeaponOption } = table.freeze({
	{
		Id = "Rifle",
		DisplayName = "Rifle",
	},
	{
		Id = "SMG",
		DisplayName = "SMG",
	},
	{
		Id = "Shotgun",
		DisplayName = "Shotgun",
	},
})

local DEFAULT_WEAPON_ID: WeaponId = "Rifle"

local validWeapons: { [string]: boolean } = {}
local initialized = false

for _, option in WEAPON_OPTIONS do
	validWeapons[option.Id] = true
end

function WeaponSystem.GetWeaponOptions(): { WeaponOption }
	return table.clone(WEAPON_OPTIONS)
end

function WeaponSystem.GetDefaultWeaponId(): WeaponId
	return DEFAULT_WEAPON_ID
end

function WeaponSystem.IsValidWeapon(weaponId: string): boolean
	return validWeapons[weaponId] == true
end

function WeaponSystem.BeginWeaponSelection(players: { Player }, matchId: number, roundNumber: number)
	for _, player in players do
		player:SetAttribute("MatchId", matchId)
		player:SetAttribute("MatchRound", roundNumber)
		player:SetAttribute("SelectedWeapon", nil)
		player:SetAttribute("CanSelectWeapon", true)
	end
end

function WeaponSystem.AssignWeapon(player: Player, weaponId: string): WeaponId?
	if not WeaponSystem.IsValidWeapon(weaponId) then
		return nil
	end

	local selectedWeapon = weaponId :: WeaponId
	player:SetAttribute("SelectedWeapon", selectedWeapon)

	return selectedWeapon
end

function WeaponSystem.EndWeaponSelection(players: { Player }): { [number]: WeaponId }
	local selections: { [number]: WeaponId } = {}

	for _, player in players do
		local selectedWeapon = player:GetAttribute("SelectedWeapon")

		if type(selectedWeapon) ~= "string" or not WeaponSystem.IsValidWeapon(selectedWeapon) then
			selectedWeapon = DEFAULT_WEAPON_ID
			player:SetAttribute("SelectedWeapon", selectedWeapon)
		end

		player:SetAttribute("CanSelectWeapon", false)
		selections[player.UserId] = selectedWeapon :: WeaponId
	end

	return selections
end

function WeaponSystem.ClearWeaponSelection(player: Player)
	player:SetAttribute("SelectedWeapon", nil)
	player:SetAttribute("CanSelectWeapon", nil)
end

function WeaponSystem.Initialize()
	if initialized then
		return
	end

	initialized = true
end

function WeaponSystem.Destroy()
	if not initialized then
		return
	end

	initialized = false
end

return WeaponSystem :: WeaponSystemType
