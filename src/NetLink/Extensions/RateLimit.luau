--!strict
--[[
	@class RateLimit
	Advanced rate limiting system for preventing spam and abuse.
	
	Provides multiple rate limiting strategies:
	- Fixed window: Simple time-based limiting
	- Sliding window: More accurate, memory-efficient limiting
	- Token bucket: Burst tolerance with gradual refill
	- Leaky bucket: Smooth rate enforcement
	
	Features:
	- Per-player and per-event limiting
	- Automatic cleanup of old data
	- Customizable penalties
	- Built-in statistics tracking
]]

local RateLimit = {}
RateLimit.__index = RateLimit

export type Strategy = "fixed" | "sliding" | "token" | "leaky"

export type RateLimitConfig = {
	MaxCalls: number,
	TimeWindow: number,
	Strategy: Strategy?,
	BurstSize: number?,
	RefillRate: number?,
	OnExceeded: ((key: string, attempts: number) -> ())?,
}

export type RateLimitStats = {
	TotalChecks: number,
	TotalBlocked: number,
	TotalAllowed: number,
	BlockRate: number,
	MostBlockedKeys: { { Key: string, Count: number } },
}

--[=[
	Creates a new RateLimit instance.
	
	@param config RateLimitConfig -- Configuration options
	@return RateLimit
	
	Example:
```lua
	local limiter = RateLimit.new({
		MaxCalls = 10,
		TimeWindow = 1,
		Strategy = "sliding",
		OnExceeded = function(key, attempts)
			warn(`Player {key} exceeded rate limit ({attempts} attempts)`)
		end
	})
```
]=]
function RateLimit.new(config: RateLimitConfig): RateLimit
	assert(config.MaxCalls > 0, "MaxCalls must be positive")
	assert(config.TimeWindow > 0, "TimeWindow must be positive")

	local strategy = config.Strategy or "sliding"
	
	local self = setmetatable({
		_maxCalls = config.MaxCalls,
		_timeWindow = config.TimeWindow,
		_strategy = strategy,
		_burstSize = config.BurstSize or config.MaxCalls,
		_refillRate = config.RefillRate or (config.MaxCalls / config.TimeWindow),
		_onExceeded = config.OnExceeded,
		
		-- Storage for different strategies
		_fixedWindows = {} :: { [string]: { Count: number, WindowStart: number } },
		_slidingCalls = {} :: { [string]: { number } },
		_tokenBuckets = {} :: { [string]: { Tokens: number, LastRefill: number } },
		_leakyBuckets = {} :: { [string]: { Queue: number, LastLeak: number } },
		
		-- Statistics
		_stats = {
			TotalChecks = 0,
			TotalBlocked = 0,
			TotalAllowed = 0,
			BlockedByKey = {} :: { [string]: number },
		},
		
		-- Cleanup
		_lastCleanup = os.clock(),
		_cleanupInterval = 60, -- Clean up every 60 seconds
	}, RateLimit)

	return self
end

--[=[
	Checks if a key can perform an action based on rate limits.
	
	@param key string -- Unique identifier (usually player.UserId)
	@return boolean -- Whether the action is allowed
	@return number? -- Time until next available slot (if blocked)
	
	Example:
```lua
	local allowed, retryAfter = limiter:Check(tostring(player.UserId))
	if not allowed then
		player:Kick(`Rate limit exceeded. Retry after {retryAfter} seconds`)
	end
```
]=]
function RateLimit:Check(key: string): (boolean, number?)
	self._stats.TotalChecks += 1
	
	-- Perform periodic cleanup
	self:_performCleanup()
	
	local allowed: boolean
	local retryAfter: number?
	
	if self._strategy == "fixed" then
		allowed, retryAfter = self:_checkFixed(key)
	elseif self._strategy == "sliding" then
		allowed, retryAfter = self:_checkSliding(key)
	elseif self._strategy == "token" then
		allowed, retryAfter = self:_checkTokenBucket(key)
	elseif self._strategy == "leaky" then
		allowed, retryAfter = self:_checkLeakyBucket(key)
	else
		error(`Unknown strategy: {self._strategy}`)
	end
	
	if allowed then
		self._stats.TotalAllowed += 1
	else
		self._stats.TotalBlocked += 1
		self._stats.BlockedByKey[key] = (self._stats.BlockedByKey[key] or 0) + 1
		
		if self._onExceeded then
			self._onExceeded(key, self._stats.BlockedByKey[key])
		end
	end
	
	return allowed, retryAfter
end

--[=[
	Fixed window rate limiting strategy.
	Simple and memory efficient, but can allow bursts at window boundaries.
	
	@private
	@param key string
	@return boolean, number?
]=]
function RateLimit:_checkFixed(key: string): (boolean, number?)
	local now = os.clock()
	local window = self._fixedWindows[key]
	
	if not window then
		self._fixedWindows[key] = { Count = 1, WindowStart = now }
		return true, nil
	end
	
	local elapsed = now - window.WindowStart
	
	if elapsed >= self._timeWindow then
		-- New window
		window.Count = 1
		window.WindowStart = now
		return true, nil
	end
	
	if window.Count < self._maxCalls then
		window.Count += 1
		return true, nil
	end
	
	local retryAfter = self._timeWindow - elapsed
	return false, retryAfter
end

--[=[
	Sliding window rate limiting strategy.
	More accurate than fixed window, tracks individual timestamps.
	
	@private
	@param key string
	@return boolean, number?
]=]
function RateLimit:_checkSliding(key: string): (boolean, number?)
	local now = os.clock()
	local calls = self._slidingCalls[key] or {}
	
	-- Remove old calls outside the time window
	local validCalls = {}
	for _, timestamp in calls do
		if now - timestamp < self._timeWindow then
			table.insert(validCalls, timestamp)
		end
	end
	
	if #validCalls < self._maxCalls then
		table.insert(validCalls, now)
		self._slidingCalls[key] = validCalls
		return true, nil
	end
	
	-- Calculate retry time based on oldest call
	table.sort(validCalls)
	local oldestCall = validCalls[1]
	local retryAfter = self._timeWindow - (now - oldestCall)
	
	return false, retryAfter
end

--[=[
	Token bucket rate limiting strategy.
	Allows bursts up to BurstSize, refills at RefillRate tokens/second.
	
	@private
	@param key string
	@return boolean, number?
]=]
function RateLimit:_checkTokenBucket(key: string): (boolean, number?)
	local now = os.clock()
	local bucket = self._tokenBuckets[key]
	
	if not bucket then
		self._tokenBuckets[key] = {
			Tokens = self._burstSize - 1,
			LastRefill = now,
		}
		return true, nil
	end
	
	-- Refill tokens
	local elapsed = now - bucket.LastRefill
	local tokensToAdd = elapsed * self._refillRate
	bucket.Tokens = math.min(self._burstSize, bucket.Tokens + tokensToAdd)
	bucket.LastRefill = now
	
	if bucket.Tokens >= 1 then
		bucket.Tokens -= 1
		return true, nil
	end
	
	local retryAfter = (1 - bucket.Tokens) / self._refillRate
	return false, retryAfter
end

--[=[
	Leaky bucket rate limiting strategy.
	Smooths out request rates, enforces steady flow.
	
	@private
	@param key string
	@return boolean, number?
]=]
function RateLimit:_checkLeakyBucket(key: string): (boolean, number?)
	local now = os.clock()
	local bucket = self._leakyBuckets[key]
	
	if not bucket then
		self._leakyBuckets[key] = {
			Queue = 1,
			LastLeak = now,
		}
		return true, nil
	end
	
	-- Leak tokens
	local elapsed = now - bucket.LastLeak
	local tokensToLeak = elapsed * self._refillRate
	bucket.Queue = math.max(0, bucket.Queue - tokensToLeak)
	bucket.LastLeak = now
	
	if bucket.Queue < self._maxCalls then
		bucket.Queue += 1
		return true, nil
	end
	
	local retryAfter = (bucket.Queue - self._maxCalls + 1) / self._refillRate
	return false, retryAfter
end

--[=[
	Resets rate limit data for a specific key.
	
	@param key string -- Key to reset
	
	Example:
```lua
	limiter:Reset(tostring(player.UserId))
```
]=]
function RateLimit:Reset(key: string)
	self._fixedWindows[key] = nil
	self._slidingCalls[key] = nil
	self._tokenBuckets[key] = nil
	self._leakyBuckets[key] = nil
	self._stats.BlockedByKey[key] = nil
end

--[=[
	Resets all rate limit data.
	
	Example:
```lua
	limiter:ResetAll()
```
]=]
function RateLimit:ResetAll()
	table.clear(self._fixedWindows)
	table.clear(self._slidingCalls)
	table.clear(self._tokenBuckets)
	table.clear(self._leakyBuckets)
	table.clear(self._stats.BlockedByKey)
end

--[=[
	Gets the current number of remaining calls for a key.
	
	@param key string
	@return number -- Remaining calls available
	
	Example:
```lua
	local remaining = limiter:GetRemaining(tostring(player.UserId))
	print(`You have {remaining} requests remaining`)
```
]=]
function RateLimit:GetRemaining(key: string): number
	if self._strategy == "fixed" then
		local window = self._fixedWindows[key]
		if not window then return self._maxCalls end
		
		local now = os.clock()
		if now - window.WindowStart >= self._timeWindow then
			return self._maxCalls
		end
		
		return math.max(0, self._maxCalls - window.Count)
		
	elseif self._strategy == "sliding" then
		local calls = self._slidingCalls[key] or {}
		local now = os.clock()
		
		local validCount = 0
		for _, timestamp in calls do
			if now - timestamp < self._timeWindow then
				validCount += 1
			end
		end
		
		return math.max(0, self._maxCalls - validCount)
		
	elseif self._strategy == "token" then
		local bucket = self._tokenBuckets[key]
		if not bucket then return self._burstSize end
		
		local now = os.clock()
		local elapsed = now - bucket.LastRefill
		local tokensToAdd = elapsed * self._refillRate
		local currentTokens = math.min(self._burstSize, bucket.Tokens + tokensToAdd)
		
		return math.floor(currentTokens)
		
	elseif self._strategy == "leaky" then
		local bucket = self._leakyBuckets[key]
		if not bucket then return self._maxCalls end
		
		local now = os.clock()
		local elapsed = now - bucket.LastLeak
		local tokensToLeak = elapsed * self._refillRate
		local currentQueue = math.max(0, bucket.Queue - tokensToLeak)
		
		return math.max(0, math.floor(self._maxCalls - currentQueue))
	end
	
	return 0
end

--[=[
	Gets comprehensive statistics about rate limiting.
	
	@return RateLimitStats
	
	Example:
```lua
	local stats = limiter:GetStats()
	print(`Block rate: {stats.BlockRate * 100}%`)
	print("Most blocked players:")
	for _, entry in stats.MostBlockedKeys do
		print(`  {entry.Key}: {entry.Count} blocks`)
	end
```
]=]
function RateLimit:GetStats(): RateLimitStats
	local blockRate = 0
	if self._stats.TotalChecks > 0 then
		blockRate = self._stats.TotalBlocked / self._stats.TotalChecks
	end
	
	-- Get top blocked keys
	local sortedBlocked = {}
	for key, count in self._stats.BlockedByKey do
		table.insert(sortedBlocked, { Key = key, Count = count })
	end
	
	table.sort(sortedBlocked, function(a, b)
		return a.Count > b.Count
	end)
	
	-- Get top 10
	local topBlocked = {}
	for i = 1, math.min(10, #sortedBlocked) do
		table.insert(topBlocked, sortedBlocked[i])
	end
	
	return {
		TotalChecks = self._stats.TotalChecks,
		TotalBlocked = self._stats.TotalBlocked,
		TotalAllowed = self._stats.TotalAllowed,
		BlockRate = blockRate,
		MostBlockedKeys = topBlocked,
	}
end

--[=[
	Adds tokens to a token bucket (for token bucket strategy only).
	Useful for granting extra capacity to VIP players.
	
	@param key string
	@param amount number
	
	Example:
```lua
	-- Give VIP player extra tokens
	if player:GetAttribute("IsVIP") then
		limiter:AddTokens(tostring(player.UserId), 10)
	end
```
]=]
function RateLimit:AddTokens(key: string, amount: number)
	if self._strategy ~= "token" then
		warn("AddTokens only works with 'token' strategy")
		return
	end
	
	local bucket = self._tokenBuckets[key]
	if not bucket then
		self._tokenBuckets[key] = {
			Tokens = math.min(self._burstSize, amount),
			LastRefill = os.clock(),
		}
	else
		bucket.Tokens = math.min(self._burstSize, bucket.Tokens + amount)
	end
end

--[=[
	Adjusts the maximum calls limit dynamically.
	
	@param newMax number
	
	Example:
```lua
	-- Increase limit during off-peak hours
	if hour >= 2 and hour <= 6 then
		limiter:SetMaxCalls(20)
	else
		limiter:SetMaxCalls(10)
	end
```
]=]
function RateLimit:SetMaxCalls(newMax: number)
	assert(newMax > 0, "MaxCalls must be positive")
	self._maxCalls = newMax
end

--[=[
	Performs cleanup of old data to prevent memory leaks.
	
	@private
]=]
function RateLimit:_performCleanup()
	local now = os.clock()
	if now - self._lastCleanup < self._cleanupInterval then
		return
	end
	
	self._lastCleanup = now
	
	-- Clean up sliding window data
	for key, calls in self._slidingCalls do
		local validCalls = {}
		for _, timestamp in calls do
			if now - timestamp < self._timeWindow then
				table.insert(validCalls, timestamp)
			end
		end
		
		if #validCalls == 0 then
			self._slidingCalls[key] = nil
		else
			self._slidingCalls[key] = validCalls
		end
	end
	
	-- Clean up fixed windows
	for key, window in self._fixedWindows do
		if now - window.WindowStart >= self._timeWindow * 2 then
			self._fixedWindows[key] = nil
		end
	end
	
	-- Clean up inactive buckets
	for key, bucket in self._tokenBuckets do
		if now - bucket.LastRefill >= self._timeWindow * 2 then
			self._tokenBuckets[key] = nil
		end
	end
	
	for key, bucket in self._leakyBuckets do
		if now - bucket.LastLeak >= self._timeWindow * 2 then
			self._leakyBuckets[key] = nil
		end
	end
end

--[=[
	Creates a preset configuration for common use cases.
	
	@param preset "strict" | "normal" | "relaxed" | "burst"
	@return RateLimitConfig
	
	Example:
```lua
	local strictLimiter = RateLimit.new(RateLimit.Preset("strict"))
	local relaxedLimiter = RateLimit.new(RateLimit.Preset("relaxed"))
```
]=]
function RateLimit.Preset(preset: "strict" | "normal" | "relaxed" | "burst"): RateLimitConfig
	if preset == "strict" then
		return {
			MaxCalls = 5,
			TimeWindow = 1,
			Strategy = "sliding",
		}
	elseif preset == "normal" then
		return {
			MaxCalls = 10,
			TimeWindow = 1,
			Strategy = "sliding",
		}
	elseif preset == "relaxed" then
		return {
			MaxCalls = 20,
			TimeWindow = 1,
			Strategy = "fixed",
		}
	elseif preset == "burst" then
		return {
			MaxCalls = 10,
			TimeWindow = 1,
			Strategy = "token",
			BurstSize = 50,
			RefillRate = 10,
		}
	else
		error(`Unknown preset: {preset}`)
	end
end

export type RateLimit = typeof(RateLimit.new(...))
return RateLimit