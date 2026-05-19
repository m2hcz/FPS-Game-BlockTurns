local FastSignal = {}
FastSignal.__index = FastSignal

local Connection = {}
Connection.__index = Connection

function Connection.new(signal, callback)
	return setmetatable({
		_signal = signal,
		_callback = callback,
		Connected = true,
	}, Connection)
end

function Connection:Disconnect()
	if not self.Connected then
		return
	end

	self.Connected = false
	self._signal._connections[self] = nil
end

function FastSignal.new()
	return setmetatable({
		_connections = {},
		_destroyed = false,
	}, FastSignal)
end

function FastSignal:Connect(callback)
	assert(type(callback) == "function", "FastSignal callback must be a function")
	assert(not self._destroyed, "Cannot connect to a destroyed signal")

	local connection = Connection.new(self, callback)
	self._connections[connection] = true

	return connection
end

function FastSignal:Once(callback)
	local connection

	connection = self:Connect(function(...)
		if connection then
			connection:Disconnect()
		end

		callback(...)
	end)

	return connection
end

function FastSignal:Fire(...)
	if self._destroyed then
		return
	end

	for connection in self._connections do
		if connection.Connected then
			task.spawn(connection._callback, ...)
		end
	end
end

function FastSignal:Destroy()
	if self._destroyed then
		return
	end

	self._destroyed = true

	for connection in self._connections do
		connection.Connected = false
	end

	table.clear(self._connections)
end

FastSignal.DisconnectAll = FastSignal.Destroy

return FastSignal
