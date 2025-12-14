--!strict
--[=[
	@class NetLink
	High-performance networking library for Roblox.
	
	Provides namespace-based event system with batching, type safety,
	and flexible communication patterns. Supports both reliable (RemoteEvent)
	and unreliable (UnreliableRemoteEvent) communication.
]=]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReliableRemote = ReplicatedStorage:FindFirstChild("NetLinkEvent") :: RemoteEvent?
local UnreliableRemote = ReplicatedStorage:FindFirstChild("NetLinkEventUnreliable") :: UnreliableRemoteEvent?

-- Setup RemoteEvent (Reliable)
if RunService:IsServer() then
	ReliableRemote = Instance.new("RemoteEvent")
	ReliableRemote.Name = "NetLinkEvent"
	ReliableRemote.Parent = ReplicatedStorage
	
	UnreliableRemote = Instance.new("UnreliableRemoteEvent")
	UnreliableRemote.Name = "NetLinkEventUnreliable"
	UnreliableRemote.Parent = ReplicatedStorage
elseif not ReliableRemote then
	ReliableRemote = ReplicatedStorage:WaitForChild("NetLinkEvent") :: RemoteEvent
	UnreliableRemote = ReplicatedStorage:WaitForChild("NetLinkEventUnreliable") :: UnreliableRemoteEvent
end

local cachedEventIds: { [string]: string } = {}


local Promise = require(script.Promise)
local Event = require(script.Event)
local ServerEvent = require(script.ServerEvent)
local ClientEvent = require(script.ClientEvent)

local Extensions = script.Extensions
local RateLimit = require(Extensions.RateLimit)

type Promise<T...> = Promise.PromiseType<T...>
type RateLimit = RateLimit.RateLimit
type RateLimitConfig = RateLimit.RateLimitConfig

--[=[
	@within NetLink
	Gets a cached event ID if available.
	
	@private
	@param namespace Server | Client
	@param event string
	@return string?
]=]
local function getCachedEventId(namespace: Server | Client, event: string): string?
	local formatted = namespace.Name .. "_" .. event
	return cachedEventIds[formatted]
end

--[=[
	@within NetLink
	Retrieves or generates an event ID for the given namespace and event name.
	
	@private
	@param namespace Server | Client
	@param event string
	@return Promise<string>
]=]
local function getEventId(namespace: Server | Client, event: string): Promise<string>
	local formatted = namespace.Name .. "_" .. event

	local cached = getCachedEventId(namespace, event)
	if cached then
		return Promise.resolve(cached)
	end

	return Event.Shared(formatted):tap(function(eventId: string)
		cachedEventIds[formatted] = eventId
	end) :: any
end

-- Start event systems
if RunService:IsServer() then
	ServerEvent.Start()
else
	ClientEvent.Start()
end

--[=[
	@class Server
	Server-side namespace for handling client communication.
]=]
local Server = {}
Server.__index = Server

function Server.new(name: string, unreliable: boolean?)
	return setmetatable({ 
		Name = name,
		Unreliable = unreliable or false,
		_rateLimiter = nil :: RateLimit?,
	}, Server)
end

export type Server = typeof(Server.new(...))

--[=[
	@within Server
	Fires an event to a specific player (batched).
	Event will be sent on the next Heartbeat.
	
	@param player Player -- Target player
	@param event string -- Event name
	@param ... any -- Arguments to send
]=]
function Server:Fire(player: Player, event: string, ...: any)
	local args = { ... }

	getEventId(self, event):tap(function(eventId: string)
		ServerEvent.Fire(player, eventId, args, self.Unreliable)
	end)
end

--[=[
	@within Server
	Fires an event to a specific player immediately (unbatched).
	Event is sent instantly without waiting for Heartbeat.
	
	@param player Player -- Target player
	@param event string -- Event name
	@param ... any -- Arguments to send
]=]
function Server:FireNow(player: Player, event: string, ...: any)
	local args = { ... }

	getEventId(self, event):tap(function(eventId: string)
		ServerEvent.FireNow(player, eventId, args, self.Unreliable)
	end)
end

--[=[
	@within Server
	Fires an event to all connected players (batched).
	
	@param event string -- Event name
	@param ... any -- Arguments to send
]=]
function Server:FireAll(event: string, ...: any)
	local args = { ... }

	getEventId(self, event):tap(function(eventId: string)
		for _, player in Players:GetPlayers() do
			ServerEvent.Fire(player, eventId, args, self.Unreliable)
		end
	end)
end

--[=[
	@within Server
	Fires an event to all players except one (batched).
	
	@param except Player -- Player to exclude
	@param event string -- Event name
	@param ... any -- Arguments to send
]=]
function Server:FireAllExcept(except: Player, event: string, ...: any)
	local args = { ... }

	getEventId(self, event):tap(function(eventId: string)
		for _, player in Players:GetPlayers() do
			if player ~= except then
				ServerEvent.Fire(player, eventId, args, self.Unreliable)
			end
		end
	end)
end

--[=[
	@within Server
	Fires an event to a specific list of players (batched).
	
	@param playerList {Player} -- Array of target players
	@param event string -- Event name
	@param ... any -- Arguments to send
]=]
function Server:FireList(playerList: { Player }, event: string, ...: any)
	local args = { ... }

	getEventId(self, event):tap(function(eventId: string)
		for _, player in playerList do
			ServerEvent.Fire(player, eventId, args, self.Unreliable)
		end
	end)
end

--[=[
	@within Server
	Fires an event to players matching a filter function (batched).
	
	@param filter (player: Player) -> boolean -- Filter function
	@param event string -- Event name
	@param ... any -- Arguments to send
]=]
function Server:FireWithFilter(filter: (player: Player) -> boolean, event: string, ...: any)
	local args = { ... }

	getEventId(self, event):tap(function(eventId: string)
		for _, player in Players:GetPlayers() do
			if filter(player) then
				ServerEvent.Fire(player, eventId, args, self.Unreliable)
			end
		end
	end)
end

--[=[
	@within Server
	Registers event listener(s) for incoming client events.
	
	@param events {[string]: (player: Player, ...any) -> ()} | string -- Event name or table of events
	@param callback ((player: Player, ...any) -> ())? -- Callback function (if events is a string)
]=]
function Server:On(
	events: { [string]: (player: Player, ...any) -> () } | string,
	callback: (player: Player, ...any) -> ()?
)
	if type(events) == "table" then
		for name, cb in events do
			self:On(name, cb)
		end
	else
		getEventId(self, events):tap(function(eventId: string)
			ServerEvent.Listen(eventId, function(player : Player, ...)
				-- Rate limit check
				if self._rateLimiter then
					local allowed, retryAfter = self._rateLimiter:Check(tostring(player.UserId))
					if not allowed then
						warn(`[NetLink] Rate limit exceeded for {player.Name} on event {events}. Retry after {retryAfter}s`)
						return
					end
				end
				
				callback(player, ...)
			end)
		end)
	end
end

--[=[
	@within Server
	Enables rate limiting for this namespace.
	
	@param config RateLimitConfig | "strict" | "normal" | "relaxed" | "burst" -- Rate limit configuration or preset
	@return Server -- Returns self for chaining
	
	Example:
	```lua
	local Combat = NetLink.Server("Combat")
		:WithRateLimit("strict")
		:WithRateLimit({
			MaxCalls = 5,
			TimeWindow = 1,
			Strategy = "sliding",
			OnExceeded = function(key, attempts)
				local player = Players:GetPlayerByUserId(tonumber(key))
				if player and attempts > 20 then
					player:Kick("Rate limit abuse")
				end
			end
		})
	```
]=]
function Server:WithRateLimit(config: RateLimitConfig | "strict" | "normal" | "relaxed" | "burst"): Server
	if type(config) == "string" then
		config = RateLimit.Preset(config)
	end
	
	self._rateLimiter = RateLimit.new(config)
	return self
end

--[=[
	@within Server
	Gets the rate limiter for this namespace (if enabled).
	
	@return RateLimit?
	
	Example:
	```lua
	local limiter = Combat:GetRateLimiter()
	if limiter then
		local stats = limiter:GetStats()
		print(`Block rate: {stats.BlockRate * 100}%`)
	end
	```
]=]
function Server:GetRateLimiter(): RateLimit?
	return self._rateLimiter
end

--[=[
	@within Server
	Resets rate limit data for a specific player.
	
	@param player Player
	
	Example:
	```lua
	Combat:ResetRateLimit(player)
	```
]=]
function Server:ResetRateLimit(player: Player)
	if self._rateLimiter then
		self._rateLimiter:Reset(tostring(player.UserId))
	end
end

--[=[
	@class Client
	Client-side namespace for server communication.
]=]
local Client = {}
Client.__index = Client

function Client.new(name: string, unreliable: boolean?)
	return setmetatable({ 
		Name = name,
		Unreliable = unreliable or false
	}, Client)
end

export type Client = typeof(Client.new(...))

--[=[
	@within Client
	Fires an event to the server (batched).
	Event will be sent on the next Heartbeat.
	
	@param event string -- Event name
	@param ... any -- Arguments to send
]=]
function Client:Fire(event: string, ...: any)
	local args = { ... }

	getEventId(self, event):tap(function(eventId: string)
		ClientEvent.Fire(eventId, args, self.Unreliable)
	end)
end

--[=[
	@within Client
	Fires an event to the server immediately (unbatched).
	Event is sent instantly without waiting for Heartbeat.
	
	@param event string -- Event name
	@param ... any -- Arguments to send
]=]
function Client:FireNow(event: string, ...: any)
	local args = { ... }

	getEventId(self, event):tap(function(eventId: string)
		ClientEvent.FireNow(eventId, args, self.Unreliable)
	end)
end

--[=[
	@within Client
	Calls a server function and returns a Promise with the result.
	
	@param event string -- Event name
	@param ... any -- Arguments to send
	@return Promise<...any>
]=]
function Client:Call(event: string, ...: any): Promise<...any>
	local args = { ... }

	return getEventId(self, event):andThen(function(eventId: string)
		return ClientEvent.Call(eventId, args)
	end) :: any
end

--[=[
	@within Client
	Registers event listener(s) for incoming server events.
	
	@param events {[string]: (...any) -> ()} | string -- Event name or table of events
	@param callback ((...any) -> ())? -- Callback function (if events is a string)
]=]
function Client:On(events: { [string]: (...any) -> () } | string, callback: (...any) -> ()?)
	if type(events) == "table" then
		for name, cb in events do
			self:On(name, cb)
		end
	else
		getEventId(self, events):tap(function(eventId: string)
			ClientEvent.Listen(eventId, callback :: any)
		end)
	end
end

local ServerMap = {}
local ClientMap = {}

local NetLink = {
	Promise = Promise,
}

--[=[
	@within NetLink
	Creates or retrieves a server namespace.
	
	@param name string -- Namespace identifier
	@param unreliable boolean? -- Whether to use UnreliableRemoteEvent (default: false)
	@return Server
]=]
function NetLink.Server(name: string, unreliable: boolean?): Server
	assert(RunService:IsServer(), "NetLink.Server can only be used on the server.")

	local key = name .. (if unreliable then "_unreliable" else "_reliable")
	
	if not ServerMap[key] then
		ServerMap[key] = Server.new(name, unreliable)
	end
	return ServerMap[key]
end

--[=[
	@within NetLink
	Creates or retrieves a client namespace.
	
	@param name string -- Namespace identifier
	@param unreliable boolean? -- Whether to use UnreliableRemoteEvent (default: false)
	@return Client
]=]
function NetLink.Client(name: string, unreliable: boolean?): Client
	assert(RunService:IsClient(), "NetLink.Client can only be used on the client.")

	local key = name .. (if unreliable then "_unreliable" else "_reliable")
	
	if not ClientMap[key] then
		ClientMap[key] = Client.new(name, unreliable)
	end
	return ClientMap[key]
end

return NetLink