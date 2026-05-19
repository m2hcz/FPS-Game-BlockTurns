local DataManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local main = ServerStorage:WaitForChild("main")
local serverlib = main:WaitForChild("lib")
local src = main:WaitForChild("src")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local lib = Shared:WaitForChild("lib")

local Maid = require(lib:WaitForChild("Maid"))
local FastSignal = require(lib:WaitForChild("FastSignal"))

local serverNet = require(src:WaitForChild("serverNet"))
local ProfileStore = require(serverlib:WaitForChild("ProfileStore"))

export type PlayerData = {
	DataVersion: number,
	Winstreak: number,

	CreatedAtUnix: number,
	LastLoginUnix: number,
	LastLogoutUnix: number,
}

type MaidObject = {
	GiveTask: (self: MaidObject, task: any) -> any,
	DoCleaning: (self: MaidObject) -> (),
}

type SignalConnection = {
	Disconnect: (self: SignalConnection) -> (),
}

type Signal<T...> = {
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> SignalConnection,
	Fire: (self: Signal<T...>, T...) -> (),
	Destroy: ((self: Signal<T...>) -> ())?,
}

type Profile<T> = {
	Data: T,
	AddUserId: (self: Profile<T>, userId: number) -> (),
	Reconcile: (self: Profile<T>) -> (),
	EndSession: (self: Profile<T>) -> (),
	OnSessionEnd: {
		Connect: (self: any, callback: () -> ()) -> SignalConnection,
	},
}

type ProfileStore<T> = {
	StartSessionAsync: (
		self: ProfileStore<T>,
		key: string,
		options: {
			Cancel: () -> boolean,
		}
	) -> Profile<T>?,
}

type DataManagerType = {
	PlayerStore: ProfileStore<PlayerData>,
	Profiles: { [number]: Profile<PlayerData> },
	Maids: { [number]: MaidObject },
	Signals: { [number]: Signal<PlayerData> },
	LoadedPlayers: { [number]: boolean },
	ServerMaid: MaidObject,

	Initialize: () -> (),
	Destroy: () -> (),
	GetData: (player: Player) -> PlayerData?,
	WaitForData: (player: Player, timeoutSeconds: number?) -> PlayerData?,
	IsLoaded: (player: Player) -> boolean,
}

local PlayerDataClass = {}

PlayerDataClass.Default = table.freeze({
	DataVersion = 1,
	Winstreak = 0,

	CreatedAtUnix = 0,
	LastLoginUnix = 0,
	LastLogoutUnix = 0,
}) :: PlayerData

function PlayerDataClass.new(): PlayerData
	return table.clone(PlayerDataClass.Default)
end

local function normalizeNumber(value: unknown, fallback: number): number
	local numberValue = tonumber(value)

	if numberValue == nil then
		return fallback
	end

	if numberValue ~= numberValue then
		return fallback
	end

	if numberValue == math.huge or numberValue == -math.huge then
		return fallback
	end

	return numberValue
end

function PlayerDataClass.reconcile(rawData: any): PlayerData
	local now = DateTime.now().UnixTimestamp
	local data = rawData :: PlayerData

	data.DataVersion = normalizeNumber(data.DataVersion, PlayerDataClass.Default.DataVersion)
	data.Winstreak = normalizeNumber(data.Winstreak, PlayerDataClass.Default.Winstreak)

	data.CreatedAtUnix = normalizeNumber(data.CreatedAtUnix, 0)
	data.LastLoginUnix = normalizeNumber(data.LastLoginUnix, 0)
	data.LastLogoutUnix = normalizeNumber(data.LastLogoutUnix, 0)

	if data.CreatedAtUnix <= 0 then
		data.CreatedAtUnix = now
	end

	data.LastLoginUnix = now

	return data
end

function PlayerDataClass.markLogout(data: PlayerData)
	data.LastLogoutUnix = DateTime.now().UnixTimestamp
end

local STORE_NAME = "PlayerStore"
local LOAD_TIMEOUT_SECONDS = 30

local LOAD_FAILED_MESSAGE = "Your data could not be loaded safely. Please rejoin."
local SESSION_ENDED_MESSAGE = "Your data session ended. Please rejoin."

local DataTemplate: PlayerData = PlayerDataClass.new()

DataManager.PlayerStore = ProfileStore.New(STORE_NAME, DataTemplate) :: ProfileStore<PlayerData>

local Profiles: { [number]: Profile<PlayerData> } = {}
local Maids: { [number]: MaidObject } = {}
local Signals: { [number]: Signal<PlayerData> } = {}
local LoadingPlayers: { [number]: boolean } = {}

DataManager.Profiles = Profiles
DataManager.Maids = Maids
DataManager.Signals = Signals
DataManager.LoadedPlayers = {}
DataManager.ServerMaid = Maid.new()

local initialized = false
local shuttingDown = false
local bindToCloseRegistered = false

local function getProfileKey(player: Player): string
	return tostring(player.UserId)
end

local function ensureMaid(userId: number): MaidObject
	local maid = Maids[userId]

	if maid == nil then
		maid = Maid.new()
		Maids[userId] = maid
	end

	return maid
end

local function ensureSignal(userId: number): Signal<PlayerData>
	local signal = Signals[userId]

	if signal == nil then
		signal = FastSignal.new()
		Signals[userId] = signal
	end

	return signal
end

local function destroySignal(userId: number)
	local signal = Signals[userId]
	Signals[userId] = nil

	if signal and signal.Destroy then
		signal:Destroy()
	end
end

local function cleanPlayerState(userId: number)
	local maid = Maids[userId]

	if maid then
		maid:DoCleaning()
		Maids[userId] = nil
	end

	Profiles[userId] = nil
	LoadingPlayers[userId] = nil
	DataManager.LoadedPlayers[userId] = nil

	destroySignal(userId)
end

local function upsertNumberValue(parent: Instance, name: string, value: number): NumberValue
	local existing = parent:FindFirstChild(name)

	if existing and not existing:IsA("NumberValue") then
		existing:Destroy()
		existing = nil
	end

	local numberValue = existing :: NumberValue?

	if numberValue == nil then
		numberValue = Instance.new("NumberValue")
		numberValue.Name = name
		numberValue.Parent = parent
	end

	numberValue.Value = value

	return numberValue
end

local function loadLeaderstats(player: Player, data: PlayerData)
	local leaderstats = player:FindFirstChild("leaderstats")

	if leaderstats == nil then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	upsertNumberValue(leaderstats, "Winstreak", data.Winstreak)
end

local function fireBootClient(player: Player)
	if player.Parent ~= Players then
		return
	end

	local ok, err = pcall(function()
		serverNet.bootClient.Fire(player)
	end)

	if not ok then
		warn(`Failed to boot client for {player.Name}: {err}`)
	end
end

local function endSession(profile: Profile<PlayerData>)
	local ok, err = pcall(function()
		profile:EndSession()
	end)

	if not ok then
		warn(`Failed to end profile session: {err}`)
	end
end

local function startSession(player: Player): Profile<PlayerData>?
	local profile: Profile<PlayerData>?

	local ok, err = pcall(function()
		profile = DataManager.PlayerStore:StartSessionAsync(getProfileKey(player), {
			Cancel = function()
				return player.Parent ~= Players or shuttingDown
			end,
		})
	end)

	if not ok then
		warn(`Failed to start profile session for {player.Name}: {err}`)
		return nil
	end

	return profile
end

local function prepareProfile(player: Player, profile: Profile<PlayerData>): boolean
	local ok, err = pcall(function()
		profile:AddUserId(player.UserId)
		profile:Reconcile()
		PlayerDataClass.reconcile(profile.Data)
	end)

	if not ok then
		warn(`Failed to prepare profile for {player.Name}: {err}`)
		return false
	end

	return true
end

local function onSessionEnd(player: Player, userId: number)
	Profiles[userId] = nil
	LoadingPlayers[userId] = nil
	DataManager.LoadedPlayers[userId] = nil

	if not shuttingDown and player.Parent == Players then
		player:Kick(SESSION_ENDED_MESSAGE)
	end
end

local function loadPlayer(player: Player)
	local userId = player.UserId

	if player.Parent ~= Players then
		return
	end

	if Profiles[userId] ~= nil or LoadingPlayers[userId] then
		return
	end

	LoadingPlayers[userId] = true
	ensureMaid(userId)

	local loadedSignal = ensureSignal(userId)
	local profile = startSession(player)

	LoadingPlayers[userId] = nil

	if player.Parent ~= Players then
		if profile then
			endSession(profile)
		end

		return
	end

	if profile == nil then
		cleanPlayerState(userId)
		player:Kick(LOAD_FAILED_MESSAGE)
		return
	end

	if not prepareProfile(player, profile) then
		endSession(profile)
		cleanPlayerState(userId)
		player:Kick(LOAD_FAILED_MESSAGE)
		return
	end

	local maid = ensureMaid(userId)

	maid:GiveTask(profile.OnSessionEnd:Connect(function()
		onSessionEnd(player, userId)
	end))

	Profiles[userId] = profile
	DataManager.LoadedPlayers[userId] = true

	loadLeaderstats(player, profile.Data)
	loadedSignal:Fire(profile.Data)
end

local function removePlayer(player: Player)
	local userId = player.UserId
	local profile = Profiles[userId]

	if profile then
		PlayerDataClass.markLogout(profile.Data)

		Profiles[userId] = nil
		endSession(profile)
	end

	cleanPlayerState(userId)
end

local function setupBoot(player: Player)
	local userId = player.UserId
	local maid = ensureMaid(userId)
	local loadedSignal = ensureSignal(userId)

	maid:GiveTask(loadedSignal:Once(function()
		fireBootClient(player)
	end))
end

local function startPlayer(player: Player)
	setupBoot(player)
	task.spawn(loadPlayer, player)
end

local function shutdown()
	shuttingDown = true

	for _, player in Players:GetPlayers() do
		removePlayer(player)
	end
end

function DataManager.GetData(player: Player): PlayerData?
	if player.Parent ~= Players then
		return nil
	end

	local profile = Profiles[player.UserId]

	if profile == nil then
		return nil
	end

	return profile.Data
end

function DataManager.IsLoaded(player: Player): boolean
	return Profiles[player.UserId] ~= nil
end

function DataManager.WaitForData(player: Player, timeoutSeconds: number?): PlayerData?
	local profile = Profiles[player.UserId]

	if profile then
		return profile.Data
	end

	if player.Parent ~= Players then
		return nil
	end

	local thread = coroutine.running()
	local resumed = false
	local signal = ensureSignal(player.UserId)

	local connection: SignalConnection?

	connection = signal:Once(function(data: PlayerData)
		if resumed then
			return
		end

		resumed = true

		if connection then
			connection:Disconnect()
		end

		task.spawn(thread, data)
	end)

	task.delay(timeoutSeconds or LOAD_TIMEOUT_SECONDS, function()
		if resumed then
			return
		end

		resumed = true

		if connection then
			connection:Disconnect()
		end

		task.spawn(thread, nil)
	end)

	return coroutine.yield()
end

function DataManager.Initialize()
	if initialized then
		return
	end

	initialized = true
	shuttingDown = false

	DataManager.ServerMaid:GiveTask(Players.PlayerAdded:Connect(startPlayer))
	DataManager.ServerMaid:GiveTask(Players.PlayerRemoving:Connect(removePlayer))

	if not bindToCloseRegistered then
		bindToCloseRegistered = true
		game:BindToClose(shutdown)
	end

	for _, player in Players:GetPlayers() do
		startPlayer(player)
	end
end

function DataManager.Destroy()
	if not initialized then
		return
	end

	initialized = false
	shuttingDown = true

	DataManager.ServerMaid:DoCleaning()
	DataManager.ServerMaid = Maid.new()
	shutdown()
end

return DataManager :: DataManagerType
