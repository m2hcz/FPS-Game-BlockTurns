local TeamSystem = {}

local initialized = false

function TeamSystem.Initialize()
	if initialized then
		return
	end

	initialized = true
end

return TeamSystem
