--!strict
--[=[
	@class Event
	Manages event ID generation and synchronization.
	
	@private
]=]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(script.Parent.Promise)
type Promise<T...> = Promise.Promise<T...>

local Remote = ReplicatedStorage:WaitForChild("NetLinkEvent") :: RemoteEvent

local NextShared = 0
local NextUnique = 0

--[=[
	Converts a number to a compact unsigned integer string.
	
	@private
	@param n number
	@return string
]=]
local function uInt(n: number): string
	return string.pack(`I{if n == 0 then 1 else math.ceil(math.log(n + 1, 2) / 8)}`, n)
end

--[=[
	Generates a unique ID for client-side operations.
	
	@return string
]=]
local function Unique(): string
	NextUnique += 1

	if NextUnique == 0xFFFF then
		NextUnique = 0
	end

	return uInt(NextUnique)
end

--[=[
	Generates or retrieves a shared event ID synchronized across server and client.
	
	@param name string -- Event name
	@return Promise<string>
]=]
local function Shared(name: string): Promise<string>
	if Remote:GetAttribute(name) then
		return Promise.resolve(Remote:GetAttribute(name))
	end

	if RunService:IsServer() then
		local id = uInt(NextShared)
		Remote:SetAttribute(name, id)

		NextShared += 1

		return Promise.resolve(id)
	end

	local changed = Remote:GetAttributeChangedSignal(name)
	return Promise.new(function(resolve)
		changed:Wait()
		resolve(Remote:GetAttribute(name))
	end)
end

return {
	Unique = Unique,
	Shared = Shared,
}