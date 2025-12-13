local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Spawn = require(script.Parent.Parent.Spawn)

local Remote = ReplicatedStorage:WaitForChild("RedEvent") :: RemoteEvent

type CallList = { { any } }
type EventMap = { [string]: { { any } } }

local ListenerMap = {} :: { [string]: (player: Player, ...any) -> () }
local OutgoingMap = {} :: { [Player]: { Fire: EventMap?, Call: CallList? } }

local getOutboundMap = function(player: Player, kind: "Fire" | "Call")
	local map = OutgoingMap[player]
	if not map then
		map = {}
		OutgoingMap[player] = map
	end

	local specific = map[kind] or {}
	map[kind] = specific

	return specific
end :: ((player: Player, kind: "Fire") -> EventMap) & ((player: Player, kind: "Call") -> CallList)

--#region Inbound traffic
local function handleIncomingFire(player: Player, fireSection: EventMap): ()
	debug.profilebegin("Red.ServerEvent.Start.MultipleFire")

	for eventId: string, callList: CallList in fireSection do
		local callback = ListenerMap[eventId]

		if not callback then
			continue
		end

		for _: number, call: { any } in callList do
			Spawn(callback, player, unpack(call))
		end
	end

	debug.profileend()
end

local function handleIncomingCall(player: Player, callSection: EventMap): ()
	debug.profilebegin("Red.ServerEvent.Start.Call")

	local function noListener(callList: CallList): ()
		local map = getOutboundMap(player, "Call")

		for _: number, call: { any } in callList do
			local callId: string = call[1]
			local payload: { any } = {
				callId,
				false, --> success
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

		for _: number, call: { any } in callList do
			Spawn(function()
				local callId: string = call[1]
				local result: { any } = {
					callId,
					pcall(callback, player, unpack(call, 2)), --> success, return data...
				}

				local map = getOutboundMap(player, "Call")
				table.insert(map, result)
			end)
		end
	end

	debug.profileend()
end

local function OnServerEvent(player: Player, fireSection: EventMap?, callSection: EventMap?): ()
	debug.profilebegin("Red.ServerEvent.Start")

	if fireSection then
		handleIncomingFire(player, fireSection)
	end

	if callSection then
		handleIncomingCall(player, callSection)
	end

	debug.profileend()
end
--#endregion

--#region Outbound traffic
local function handleOutgoing(): ()
	debug.profilebegin("Red.ServerEvent.Outgoing")

	for player, outbound in OutgoingMap do
		Remote:FireClient(player, outbound.Fire, outbound.Call)
	end

	table.clear(OutgoingMap)

	debug.profileend()
end

local function Fire(player: Player, eventId: string, args: { any }): ()
	local map = getOutboundMap(player, "Fire")
	if not map[eventId] then
		map[eventId] = {}
	end

	table.insert(map[eventId], args)
end

local function FireNow(player: Player, eventId: string, args: { any }): ()
	Remote:FireClient(player, { [eventId] = { args } })
end
--#endregion

local function Listen(eventId: string, callback: (player: Player, ...any) -> ()): ()
	ListenerMap[eventId] = callback
end

local function Start(): ()
	debug.setmemorycategory("Red.ServerEvent.Start")

	Remote.OnServerEvent:Connect(OnServerEvent)
	RunService.Heartbeat:Connect(handleOutgoing)
end

return {
	Fire = Fire,
	FireNow = FireNow,
	Listen = Listen,

	Start = Start,
}
