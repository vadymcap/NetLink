--!strict
--[=[
	@class Spawn
	Optimized thread spawning utility.
	
	@private
]=]

local freeThreads: { thread } = {}

local function runCallback(callback, thread, ...)
	callback(...)
	table.insert(freeThreads, thread)
end

local function yielder()
	while true do
		runCallback(coroutine.yield())
	end
end

--[=[
	Spawns a function in a reusable thread for better performance.
	
	@param callback (...any) -> () -- Function to execute
	@param ... any -- Arguments to pass
]=]
local function Spawn(callback: (...any) -> (), ...: any)
	local thread = table.remove(freeThreads)
	if not thread then
		thread = coroutine.create(yielder)
		coroutine.resume(thread)
	end

	task.spawn(thread, callback, thread, ...)
end

return Spawn