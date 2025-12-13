local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules --
local Event = require(script.Parent.Event)
local Spawn = require(script.Parent.Parent.Spawn)

-- Packages --
local Promise = require(ReplicatedStorage.Packages.Promise)
type Promise<T...> = Promise.Promise<T...>

local Remote = ReplicatedStorage:WaitForChild("RedEvent") :: RemoteEvent

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
local FIRE_COUNT = 0 -- NOTE: Can technically be a boolean

local CALL_MAP: EventMap = {}
local CALL_COUNT = 0

--#region Inbound traffic
local function handleIncomingFire(fireSection: EventMap): ()
	debug.profilebegin("Red.ClientEvent.Start.Fire")

	for eventId: string, callList: { { any } } in fireSection do
		local callback = ListenerMap[eventId]

		if not callback then
			continue
		end

		for _: number, call: { any } in callList do
			Spawn(callback, unpack(call))
		end
	end

	debug.profileend()
end

--[=[
	Handles the resolution (or rejection) of promises returned by `:Call()` upon receiving a response from the server.

	@param callSection { { any } } -- An array of responses. Responses: { [1]: string (callId), [2]: boolean (success), ... (payload) }
]=]
local function handleCallResumption(callSection: { { any } }): ()
	debug.profilebegin("Red.ClientEvent.Start.Call")

	for _: number, call: { any } in callSection do
		local id: string = call[1]
		local success: boolean = call[2]

		local caller = CallerMap[id]
		if not caller then
			continue
		end

		if success then
			caller.Resolve(unpack(call, 3))
		else
			caller.Reject(unpack(call, 3))
		end

		CallerMap[id] = nil
	end

	debug.profileend()
end

local function OnClientEvent(fireSection: EventMap?, callSection: { { any } }?): ()
	debug.profilebegin("Red.ClientEvent.Start")

	if fireSection then
		handleIncomingFire(fireSection)
	end

	if callSection then
		handleCallResumption(callSection)
	end

	debug.profileend()
end
--#endregion

--#region Outbound traffic
local function handleOutgoing(): ()
	debug.profilebegin("Red.ClientEvent.Outgoing")

	if CALL_COUNT ~= 0 or FIRE_COUNT ~= 0 then
		Remote:FireServer(FIRE_MAP, CALL_MAP)

		FIRE_COUNT = 0
		CALL_COUNT = 0
		table.clear(FIRE_MAP)
		table.clear(CALL_MAP)
	end

	debug.profileend()
end

local function Fire(eventId: string, args: { any }): ()
	FIRE_COUNT += 1

	if not FIRE_MAP[eventId] then
		FIRE_MAP[eventId] = {}
	end

	table.insert(FIRE_MAP[eventId], args)
end

local function FireNow(eventId: string, args: { any }): ()
	Remote:FireServer({ [eventId] = { args } })
end

local function Call(eventId: string, args: { any }): Promise<...any>
	CALL_COUNT += 1

	return Promise.new(function(resolve, reject): ()
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
--#endregion

local function Listen(eventId: string, callback: (...any) -> ()): ()
	ListenerMap[eventId] = callback
end

local function Start(): ()
	debug.setmemorycategory("Red.ClientEvent.Start")

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
