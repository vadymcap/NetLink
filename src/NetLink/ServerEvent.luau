--!strict
--[=[
	@class ServerEvent
	Handles server-side event batching and dispatching.
	
	@private
]=]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Spawn = require(script.Parent.Internal.Spawn)

local Remote = ReplicatedStorage:WaitForChild("NetLinkEvent") :: RemoteEvent

type CallList = { { any } }
type EventMap = { [string]: { { any } } }

local ListenerMap = {} :: { [string]: (player: Player, ...any) -> () }
local OutgoingMap = {} :: { [Player]: { Fire: EventMap?, Call: CallList? } }

--[=[
	Retrieves or creates an outbound map for a player.
	
	@private
	@param player Player
	@param kind "Fire" | "Call"
	@return EventMap | CallList
]=]
local function getOutboundMap(player: Player, kind: "Fire"): EventMap
	local map = OutgoingMap[player]
	if not map then
		map = {}
		OutgoingMap[player] = map
	end

	local specific = map[kind] or {}
	map[kind] = specific

	return specific
end

--[=[
	Handles incoming Fire events from clients.
	
	@private
	@param player Player
	@param fireSection EventMap
]=]
local function handleIncomingFire(player: Player, fireSection: EventMap)
	debug.profilebegin("NetLink.ServerEvent.MultipleFire")

	for eventId: string, callList: CallList in fireSection do
		local callback = ListenerMap[eventId]

		if not callback then
			continue
		end

		for _, call: { any } in callList do
			Spawn(callback, player, table.unpack(call))
		end
	end

	debug.profileend()
end

--[=[
	Handles incoming Call events from clients.
	
	@private
	@param player Player
	@param callSection EventMap
]=]
local function handleIncomingCall(player: Player, callSection: EventMap)
	debug.profilebegin("NetLink.ServerEvent.Call")

	local function noListener(callList: CallList)
		local map = getOutboundMap(player, "Call")

		for _, call: { any } in callList do
			local callId: string = call[1]
			local payload: { any } = {
				callId,
				false,
				"Event has no listener.",
			}

			table.insert(map, payload)
		end
	end

	for eventId: string, callList: CallList in callSection do
		local callback = ListenerMap[eventId]

		if not callback then
			noListener(callList)
			continue
		end

		for _, call: { any } in callList do
			Spawn(function()
				local callId: string = call[1]
				local result: { any } = {
					callId,
					pcall(callback, player, table.unpack(call, 2)),
				}

				local map = getOutboundMap(player, "Call") :: any
				table.insert(map, result)
			end)
		end
	end

	debug.profileend()
end

--[=[
	Main handler for incoming events from clients.
	
	@private
	@param player Player
	@param fireSection EventMap?
	@param callSection EventMap?
]=]
local function OnServerEvent(player: Player, fireSection: EventMap?, callSection: EventMap?)
	debug.profilebegin("NetLink.ServerEvent.Start")

	if fireSection then
		handleIncomingFire(player, fireSection)
	end

	if callSection then
		handleIncomingCall(player, callSection)
	end

	debug.profileend()
end

--[=[
	Processes and sends all queued outgoing events.
	
	@private
]=]
local function handleOutgoing()
	debug.profilebegin("NetLink.ServerEvent.Outgoing")

	for player, outbound in OutgoingMap do
		Remote:FireClient(player, outbound.Fire, outbound.Call)
	end

	table.clear(OutgoingMap)

	debug.profileend()
end

--[=[
	Queues an event to be sent to a player (batched).
	
	@param player Player
	@param eventId string
	@param args {any}
]=]
local function Fire(player: Player, eventId: string, args: { any })
	local map = getOutboundMap(player, "Fire")
	if not map[eventId] then
		map[eventId] = {}
	end

	table.insert(map[eventId], args)
end

--[=[
	Sends an event to a player immediately (unbatched).
	
	@param player Player
	@param eventId string
	@param args {any}
]=]
local function FireNow(player: Player, eventId: string, args: { any })
	Remote:FireClient(player, { [eventId] = { args } })
end

--[=[
	Registers a listener for an event.
	
	@param eventId string
	@param callback (player: Player, ...any) -> ()
]=]
local function Listen(eventId: string, callback: (player: Player, ...any) -> ())
	ListenerMap[eventId] = callback
end

--[=[
	Initializes the server event system.
]=]
local function Start()
	debug.setmemorycategory("NetLink.ServerEvent.Start")

	Remote.OnServerEvent:Connect(OnServerEvent)
	RunService.Heartbeat:Connect(handleOutgoing)
end

return {
	Fire = Fire,
	FireNow = FireNow,
	Listen = Listen,
	Start = Start,
}