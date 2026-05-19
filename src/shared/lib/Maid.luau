local Maid = {}
Maid.__index = Maid

local function cleanTask(taskValue)
	local taskType = typeof(taskValue)

	if taskType == "RBXScriptConnection" then
		if taskValue.Connected then
			taskValue:Disconnect()
		end
	elseif taskType == "Instance" then
		taskValue:Destroy()
	elseif taskType == "function" then
		taskValue()
	elseif taskType == "thread" then
		task.cancel(taskValue)
	elseif type(taskValue) == "table" then
		if type(taskValue.Destroy) == "function" then
			taskValue:Destroy()
		elseif type(taskValue.Disconnect) == "function" then
			taskValue:Disconnect()
		elseif type(taskValue.DoCleaning) == "function" then
			taskValue:DoCleaning()
		end
	end
end

function Maid.new()
	return setmetatable({
		_tasks = {},
		_destroyed = false,
	}, Maid)
end

function Maid:GiveTask(taskValue)
	assert(not self._destroyed, "Cannot add tasks to a destroyed Maid")

	local tasks = self._tasks
	local index = #tasks + 1
	tasks[index] = taskValue

	return taskValue
end

function Maid:DoCleaning()
	if self._destroyed then
		return
	end

	self._destroyed = true

	local tasks = self._tasks
	self._tasks = {}

	for _, taskValue in tasks do
		local ok, err = pcall(cleanTask, taskValue)
		if not ok then
			warn(`Maid cleanup failed: {err}`)
		end
	end
end

Maid.Destroy = Maid.DoCleaning

return Maid
