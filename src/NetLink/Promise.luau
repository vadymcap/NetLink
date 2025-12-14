--!strict
--[[
	@class Promise
	Lightweight Promise implementation for async operations.
	Provides chainable async operations with proper error handling.
]]

local Promise = {}
Promise.__index = Promise

export type Promise = {
	andThen: (self: Promise, successHandler: (T...) -> ...any, failureHandler: ((any) -> ...any)?) -> ProximityPromptService,
	catch: (self: Promise, failureHandler: (any) -> ...any) -> Promise,
	tap: (self: Promise, tapHandler: (T...) -> ()) -> Promise,
	await: (self: Promise) -> (boolean, T...),
	expect: (self: Promise) -> T...,
}

--[=[
	Creates a new Promise that executes the provided callback.
	
	@param callback (resolve: (T...) -> (), reject: (reason: any) -> ()) -> () -- Executor function
	@return Promise<T...>
]=]
function Promise.new(callback: (resolve: (T...) -> (), reject: (reason: any) -> ()) -> ()): Promise
	local self = setmetatable({
		_status = "pending",
		_value = nil,
		_successHandlers = {},
		_failureHandlers = {},
	}, Promise)

	local function resolve(...: T...)
		if self._status == "pending" then
			self._status = "resolved"
			self._value = table.pack(...)

			for _, handler in self._successHandlers do
				task.spawn(handler, ...)
			end
		end
	end

	local function reject(reason: any)
		if self._status == "pending" then
			self._status = "rejected"
			self._value = reason

			for _, handler in self._failureHandlers do
				task.spawn(handler, reason)
			end
		end
	end

	task.spawn(function()
		local success, err = pcall(callback, resolve, reject)
		if not success then
			reject(err)
		end
	end)

	return self :: any
end

--[=[
	Creates a Promise that resolves immediately with the given value.
	
	@param value T... -- Value(s) to resolve with
	@return Promise<T...>
]=]
function Promise.resolved(...: T...): Promise
	return Promise.new(function(resolve)
		resolve(...)
	end)
end

--[=[
	Creates a Promise that rejects immediately with the given reason.
	
	@param reason any -- Rejection reason
	@return Promise<never>
]=]
function Promise.reject(reason: any): Promise
	return Promise.new(function(_, reject)
		reject(reason)
	end)
end

--[=[
	Chains a success handler and optionally a failure handler.
	
	@param successHandler (T...) -> ...any -- Called when Promise resolves
	@param failureHandler ((any) -> ...any)? -- Called when Promise rejects
	@return Promise<...any> -- New Promise with chained result
]=]
function Promise:andThen<T..., U...>(
	successHandler: (T...) -> U...,
	failureHandler: ((any) -> U...)?
): Promise
	return Promise.new(function(resolve, reject)
		if self._status == "resolved" then
			local success, result = pcall(successHandler, table.unpack(self._value))
			if success then
				resolve(result)
			else
				reject(result)
			end
		elseif self._status == "rejected" then
			if failureHandler then
				local success, result = pcall(failureHandler, self._value)
				if success then
					resolve(result)
				else
					reject(result)
				end
			else
				reject(self._value)
			end
		else
			table.insert(self._successHandlers, function(...)
				local success, result = pcall(successHandler, ...)
				if success then
					resolve(result)
				else
					reject(result)
				end
			end)

			if failureHandler then
				table.insert(self._failureHandlers, function(reason)
					local success, result = pcall(failureHandler, reason)
					if success then
						resolve(result)
					else
						reject(result)
					end
				end)
			else
				table.insert(self._failureHandlers, reject)
			end
		end
	end)
end

--[=[
	Chains a failure handler.
	
	@param failureHandler (any) -> ...any -- Called when Promise rejects
	@return Promise<T...>
]=]
function Promise:catch(failureHandler: (any) -> T...): Promise
	return self:andThen(function(...)
		return ...
	end, failureHandler)
end

--[=[
	Executes a function when the Promise resolves without affecting the chain.
	Useful for side effects like logging.
	
	@param tapHandler (T...) -> () -- Function to execute on success
	@return Promise<T...> -- Returns self for chaining
]=]
function Promise:tap(tapHandler: (T...) -> ()): Promise
	if self._status == "resolved" then
		task.spawn(tapHandler, table.unpack(self._value))
	elseif self._status == "pending" then
		table.insert(self._successHandlers, tapHandler)
	end

	return self :: any
end

--[=[
	Yields the current thread until the Promise settles.
	
	@return boolean -- Whether the Promise resolved successfully
	@return T... -- The resolved value(s) or rejection reason
]=]
function Promise:await(): (boolean, T...)
	if self._status == "resolved" then
		return true, table.unpack(self._value)
	elseif self._status == "rejected" then
		return false, self._value
	end

	local thread = coroutine.running()

	self:andThen(
		function(...)
			task.spawn(thread, true, ...)
		end,
		function(reason)
			task.spawn(thread, false, reason)
		end
	)

	return coroutine.yield()
end

--[=[
	Yields until the Promise resolves, or throws an error if rejected.
	
	@return T... -- The resolved value(s)
	@error Throws if Promise rejects
]=]
function Promise:expect(): T...
	local success, result = self:await()
	if not success then
		error(result, 2)
	end
	return result
end

return Promise