local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Packages --
local Promise = require(ReplicatedStorage.Packages.Promise)
type Promise<T...> = Promise.Promise<T...>

local Remote = ReplicatedStorage:WaitForChild("RedEvent") :: RemoteEvent

local NextShared = 0
local NextUnique = 0

local function uInt(n: number): string
	return string.pack(`I{if n == 0 then 1 else math.ceil(math.log(n + 1, 2) / 8)}`, n)
end

local function Unique(): string
	NextUnique += 1

	if NextUnique == 0xFFFF then
		NextUnique = 0
	end

	return uInt(NextUnique)
end

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
	return Promise.new(function(resolve): ()
		changed:Wait()
		resolve(Remote:GetAttribute(name))
	end)
end

return {
	Unique = Unique,
	Shared = Shared,
}
