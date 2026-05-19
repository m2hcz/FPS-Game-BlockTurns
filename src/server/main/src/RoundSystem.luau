local RoundSystem = {}

local initialized = false

function RoundSystem.Initialize()
	if initialized then
		return
	end

	initialized = true
end

return RoundSystem
