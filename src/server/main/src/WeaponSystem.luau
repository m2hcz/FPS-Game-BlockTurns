local WeaponSystem = {}

local initialized = false

function WeaponSystem.Initialize()
	if initialized then
		return
	end

	initialized = true
end

return WeaponSystem
