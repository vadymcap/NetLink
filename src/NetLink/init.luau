--!strict
--[[
	@class NetLink
	High-performance networking library for Roblox.
	
	Provides namespace-based event system with batching, type safety,
	and flexible communication patterns. Supports both reliable (RemoteEvent)
	and unreliable (UnreliableRemoteEvent) communication.
]]

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
			ServerEvent.Listen(eventId, callback :: any)
		end)
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