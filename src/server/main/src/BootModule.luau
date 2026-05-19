local BootModule = {}

local src = script.Parent

local DataManager = require(src:WaitForChild("DataManager"))
local RoundSystem = require(src:WaitForChild("RoundSystem"))
local TeamSystem = require(src:WaitForChild("TeamSystem"))
local PlayerSystemModule = require(src:WaitForChild("PlayerSystem"))
local WeaponSystem = require(src:WaitForChild("WeaponSystem"))

type LifecycleModule = {
	Initialize: (() -> ())?,
	Destroy: (() -> ())?,
}

type SystemDefinition<T> = {
	name: string,
	module: T,
	required: boolean,
}

type BootModuleType = {
	Initialize: () -> (),
	Destroy: () -> (),
	IsInitialized: () -> boolean,
}

local initialized = false
local initializing = false

local systems: { SystemDefinition<LifecycleModule> } = {
	{
		name = "DataManager",
		module = DataManager,
		required = true,
	},
	{
		name = "RoundSystem",
		module = RoundSystem,
		required = true,
	},
	{
		name = "TeamSystem",
		module = TeamSystem,
		required = true,
	},
	{
		name = "PlayerSystem",
		module = PlayerSystemModule.PlayerSystem,
		required = true,
	},
	{
		name = "WeaponSystem",
		module = WeaponSystem,
		required = true,
	},
}

local function assertValidSystem(system: SystemDefinition<LifecycleModule>)
	if type(system.module) ~= "table" then
		if system.required then
			error(`System {system.name} is required but did not return a table`, 3)
		end

		return false
	end

	if system.required and type(system.module.Initialize) ~= "function" then
		error(`System {system.name} is required but has no Initialize function`, 3)
	end

	return true
end

local function initializeSystem(system: SystemDefinition<LifecycleModule>)
	if not assertValidSystem(system) then
		return
	end

	local initialize = system.module.Initialize

	if initialize == nil then
		return
	end

	local ok, err = xpcall(initialize, debug.traceback)

	if not ok then
		error(`Failed to initialize {system.name}: {err}`, 0)
	end
end

local function destroySystem(system: SystemDefinition<LifecycleModule>)
	if type(system.module) ~= "table" then
		return
	end

	local destroy = system.module.Destroy

	if destroy == nil then
		return
	end

	local ok, err = xpcall(destroy, debug.traceback)

	if not ok then
		warn(`Failed to destroy {system.name}: {err}`)
	end
end

function BootModule.Initialize()
	if initialized then
		return
	end

	if initializing then
		error("BootModule.Initialize was called while initialization was already running", 2)
	end

	initializing = true

	local ok, err = xpcall(function()
		for _, system in systems do
			initializeSystem(system)
		end
	end, debug.traceback)

	initializing = false

	if not ok then
		BootModule.Destroy()
		error(`BootModule initialization failed: {err}`, 0)
	end

	initialized = true
end

function BootModule.Destroy()
	if not initialized and not initializing then
		return
	end

	initialized = false
	initializing = false

	for index = #systems, 1, -1 do
		destroySystem(systems[index])
	end
end

function BootModule.IsInitialized(): boolean
	return initialized
end

return BootModule :: BootModuleType
