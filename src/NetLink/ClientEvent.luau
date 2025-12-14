--!strict
--[=[
	@class ClientEvent
	Handles client-side event batching and dispatching.
	
	@private
]=]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Event = require(script.Parent.Event)
local Spawn = require(script.Parent.Internal.Spawn)
local Promise = require(script.Parent.Promise)

type Promise<T...> = Promise.Promise<T...>

local Remote = ReplicatedStorage:WaitForChild("NetLinkEvent") :: RemoteEvent

type callback = (...any) -> ()
type EventMap = { [string]: { { any } } }

local ListenerMap = {} :: { [string]: callback }

local CallerMap = {} :: {
	[string]: {
		Resolve: callback,
		Reject: callback,
	},
}

local FIRE_MAP: EventMap = {}
local FIRE_COUNT = 0

local CALL_MAP: EventMap = {}
local CALL_COUNT = 0

--[=[
	Handles incoming Fire events from server.
	
	@private
	@param fireSection EventMap
]=]
local function handleIncomingFire(fireSection: EventMap)
	debug.profilebegin("NetLink.ClientEvent.Fire")

	for eventId: string, callList: { { any } } in fireSection do
		local callback = ListenerMap[eventId]

		if not callback then
			continue
		end

		for _, call: { any } in callList do
			Spawn(callback, table.unpack(call))
		end
	end

	debug.profileend()
end

--[=[
	Handles resolution or rejection of Call promises.
	
	@private
	@param callSection {{any}}
]=]
local function handleCallResumption(callSection: { { any } })
	debug.profilebegin("NetLink.ClientEvent.Call")

	for _, call: { any } in callSection do
		local id: string = call[1]
		local success: boolean = call[2]

		local caller = CallerMap[id]
		if not caller then
			continue
		end

		if success then
			caller.Resolve(table.unpack(call, 3))
		else
			caller.Reject(table.unpack(call, 3))
		end

		CallerMap[id] = nil
	end

	debug.profileend()
end

--[=[
	Main handler for incoming events from server.
	
	@private
	@param fireSection EventMap?
	@param callSection {{any}}?
]=]
local function OnClientEvent(fireSection: EventMap?, callSection: { { any } }?)
	debug.profilebegin("NetLink.ClientEvent.Start")

	if fireSection then
		handleIncomingFire(fireSection)
	end

	if callSection then
		handleCallResumption(callSection)
	end

	debug.profileend()
end

--[=[
	Processes and sends all queued outgoing events.
	
	@private
]=]
local function handleOutgoing()
	debug.profilebegin("NetLink.ClientEvent.Outgoing")

	if CALL_COUNT ~= 0 or FIRE_COUNT ~= 0 then
		Remote:FireServer(FIRE_MAP, CALL_MAP)

		FIRE_COUNT = 0
		CALL_COUNT = 0
		table.clear(FIRE_MAP)
		table.clear(CALL_MAP)
	end

	debug.profileend()
end

--[=[
	Queues an event to be sent to server (batched).
	
	@param eventId string
	@param args {any}
]=]
local function Fire(eventId: string, args: { any })
	FIRE_COUNT += 1

	if not FIRE_MAP[eventId] then
		FIRE_MAP[eventId] = {}
	end

	table.insert(FIRE_MAP[eventId], args)
end

--[=[
	Sends an event to server immediately (unbatched).
	
	@param eventId string
	@param args {any}
]=]
local function FireNow(eventId: string, args: { any })
	Remote:FireServer({ [eventId] = { args } })
end

--[=[
	Calls a server function and returns a Promise.
	
	@param eventId string
	@param args {any}
	@return Promise<...any>
]=]
local function Call(eventId: string, args: { any }): Promise<...any>
	CALL_COUNT += 1

	return Promise.new(function(resolve, reject)
		local callId = Event.Unique()

		if not CALL_MAP[eventId] then
			CALL_MAP[eventId] = {}
		end

		table.insert(args, 1, callId)
		table.insert(CALL_MAP[eventId], args)

		CallerMap[callId] = {
			Resolve = resolve,
			Reject = reject,
		}
	end)
end

--[=[
	Registers a listener for an event.
	
	@param eventId string
	@param callback (...any) -> ()
]=]
local function Listen(eventId: string, callback: (...any) -> ())
	ListenerMap[eventId] = callback
end

--[=[
	Initializes the client event system.
]=]
local function Start()
	debug.setmemorycategory("NetLink.ClientEvent.Start")

	Remote.OnClientEvent:Connect(OnClientEvent)
	RunService.Heartbeat:Connect(handleOutgoing)
end

return {
	Call = Call,
	Fire = Fire,
	FireNow = FireNow,
	Listen = Listen,
	Start = Start,
}