local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies --
local Promise = require(ReplicatedStorage.Packages.Promise)
type Promise<T...> = Promise.Promise<T...>

local Remote = ReplicatedStorage:FindFirstChild("RedEvent") :: RemoteEvent

--#region Setup the RemoteEvent
if RunService:IsServer() then
	Remote = Instance.new("RemoteEvent")
	Remote.Name = "RedEvent"
	Remote.Parent = ReplicatedStorage
elseif not Remote then
	Remote = ReplicatedStorage:WaitForChild("RedEvent") :: RemoteEvent
end
--#endregion

-- Modules --
local Event = require(script.Event)
local Serdes = require(script.Serdes)
local Identifier = require(script.Identifier)
local ClientEvent = require(script.ClientEvent)
local ServerEvent = require(script.ServerEvent)

local cachedEventIds: { [string]: string } = {}

--#region EventId caching
local function getCachedEventId(self: Server | Client, event: string): string?
	local formatted = self.Name .. "_" .. event
	return cachedEventIds[formatted]
end

local function getEventId(self: Server | Client, event: string): Promise<string>
	local formatted = self.Name .. "_" .. event

	local cached = getCachedEventId(self, event)
	if cached then
		return Promise.resolve(cached)
	end

	return Event.Shared(formatted):tap(function(eventId: string): ()
		cachedEventIds[formatted] = eventId
	end) :: any
end
--#endregion

if RunService:IsServer() then
	ServerEvent.Start()
else
	ClientEvent.Start()
end

--#region Server
local Server = {}
Server.__index = Server

function Server.new(name: string)
	return setmetatable({ Name = name }, Server)
end

export type Server = typeof(Server.new(...))

function Server.Fire(self: Server, player: Player, event: string, ...: any): ()
	local args = { ... }

	getEventId(self, event):tap(function(eventId: string): ()
		ServerEvent.Fire(player, eventId, args)
	end)
end

function Server.FireNow(self: Server, player: Player, event: string, ...: any): ()
	local args = { ... }

	getEventId(self, event):tap(function(eventId: string): ()
		ServerEvent.FireNow(player, eventId, args)
	end)
end

function Server.FireAll(self: Server, event: string, ...: any): ()
	local args = { ... }

	getEventId(self, event):tap(function(eventId: string): ()
		for _, player in Players:GetPlayers() do
			ServerEvent.Fire(player, eventId, args)
		end
	end)
end

function Server.FireAllExcept(self: Server, except: Player, event: string, ...: any): ()
	local args = { ... }

	getEventId(self, event):tap(function(eventId: string): ()
		for _, player in Players:GetPlayers() do
			if player ~= except then
				ServerEvent.Fire(player, eventId, args)
			end
		end
	end)
end

function Server.FireList(self: Server, playerList: { Player }, event: string, ...: any): ()
	local args = { ... }

	getEventId(self, event):tap(function(eventId: string): ()
		for _, player in playerList do
			ServerEvent.Fire(player, eventId, args)
		end
	end)
end

function Server.FireWithFilter(self: Server, filter: (player: Player) -> boolean, event: string, ...: any): ()
	local args = { ... }

	getEventId(self, event):tap(function(eventId: string): ()
		for _, player in Players:GetPlayers() do
			if filter(player) then
				ServerEvent.Fire(player, eventId, args)
			end
		end
	end)
end

function Server:On(
	events: { [string]: (player: Player, ...any) -> () } | string,
	callback: (player: Player, ...any) -> ()
): ()
	if type(events) == "table" then
		for name, callback in events do
			self:On(name, callback)
		end
	else
		getEventId(self, events):tap(function(eventId: string)
			ServerEvent.Listen(eventId, callback :: any)
		end)
	end
end
--#endregion

--#region Client
local Client = {}
Client.__index = Client

function Client.new(name: string)
	return setmetatable({ Name = name }, Client)
end

export type Client = typeof(Client.new(...))

function Client.Fire(self: Client, event: string, ...: any): ()
	local args = { ... }

	getEventId(self, event):tap(function(eventId: string): ()
		ClientEvent.Fire(eventId, args)
	end)
end

function Client.FireNow(self: Client, event: string, ...: any): ()
	local args = { ... }

	getEventId(self, event):tap(function(eventId: string): ()
		ClientEvent.FireNow(eventId, args)
	end)
end

function Client.Call(self: Client, event: string, ...: any): Promise<...any>
	local args = { ... }

	return getEventId(self, event):andThen(function(eventId: string)
		return ClientEvent.Call(eventId, args)
	end) :: any
end

function Client.On(self: Client, events: { [string]: (...any) -> () } | string, callback: (...any) -> ()?): ()
	if type(events) == "table" then
		for name, callback in events do
			self:On(name, callback)
		end
	else
		getEventId(self, events):tap(function(eventId: string)
			ClientEvent.Listen(eventId, callback :: any)
		end)
	end
end

--#endregion

local ServerMap = {}
local ClientMap = {}

export type Serdes<I, O> = Serdes.Serdes<I, O>

return {
	Serdes = Serdes,
	Identifier = Identifier,

	Server = function(name: string)
		assert(RunService:IsServer(), "Red.Server can only be used on the server.")

		if not ServerMap[name] then
			ServerMap[name] = Server.new(name)
		end
		return ServerMap[name]
	end,

	Client = function(name: string)
		assert(RunService:IsClient(), "Red.Client can only be used on the client.")

		if not ClientMap[name] then
			ClientMap[name] = Client.new(name)
		end
		return ClientMap[name]
	end,
}
