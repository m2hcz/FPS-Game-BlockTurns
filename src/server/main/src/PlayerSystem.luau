local PlayerSystem = {}

local initialized = false

function PlayerSystem.Initialize()
	if initialized then
		return
	end

	initialized = true
end

return {
	PlayerSystem = PlayerSystem,
}
