# NetLink

<div align="center">
    <a href="LICENSE">
        <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License"></img>
    </a>
    <a href="README.md">
        <img src="https://img.shields.io/badge/version-1.0.0-green.svg" alt="Version"></img>
    </a>
    <a href="https://discord.gg/gQRfWpTsEE">
        <img src="https://img.shields.io/badge/discord-caps-brightgreen.svg" alt="Discord"></img>
    </a>
</div>

**High-performance networking library for Roblox development.**

A lightweight, type-safe library that streamlines client-server communication with automatic batching, rate limiting, and support for both reliable and unreliable delivery. Say goodbye to RemoteEvent boilerplate and hello to clean, efficient networking.

---

## Features

- **Auto-Batching** - Events are automatically batched per Heartbeat for optimal performance
- **Type-Safe** - Full Luau strict type support with comprehensive types
- **Rate Limiting** - Built-in protection against spam and abuse with 4 strategies
- **Dual Transport** - Support for both reliable (RemoteEvent) and unreliable (UnreliableRemoteEvent) delivery
- **Namespace-Based** - Organize events into logical namespaces
- **Flexible Targeting** - Fire to one player, all players, lists, or filtered groups
- **Promises** - Built-in Promise support for async client-server calls

---

## Installation

### Manual Installation

1. Download the NetLink module files
2. Place the `NetLink` folder in `ReplicatedStorage`
3. Require it in your scripts:

```lua
local NetLink = require(game.ReplicatedStorage.NetLink)
```

---

## Quick Start

### Server-Side

```lua
local NetLink = require(game.ReplicatedStorage.NetLink)

-- Create a namespace with rate limiting
local Combat = NetLink.Server("Combat")

-- Listen for events
Combat:On("Attack", function(player, targetId, damage)
    print(player.Name, "attacked", targetId, "for", damage)
end)

-- Fire to a specific player
Combat:Fire(player, "TakeDamage", 25)

-- Fire to all players
Combat:FireAll("RoundStart", roundNumber)

-- Fire to all except one
Combat:FireAllExcept(player, "PlayerEliminated", player.Name)
```

### Client-Side

```lua
local NetLink = require(game.ReplicatedStorage.NetLink)
local Combat = NetLink.Client("Combat")

-- Listen for server events
Combat:On("TakeDamage", function(damage)
    print("Took damage:", damage)
end)

-- Fire to server
Combat:Fire("Attack", targetId, 50)

-- Call server and get response
Combat:Call("GetPlayerStats")
    :andThen(function(stats)
        print("Stats:", stats)
    end)
    :catch(function(err)
        warn("Failed to get stats:", err)
    end)
```

---

## Basic Usage

### Creating Namespaces

```lua
-- Server-side namespace (reliable)
local Combat = NetLink.Server("Combat")

-- Server-side namespace (unreliable, for high-frequency data)
local Movement = NetLink.Server("Movement", true)
```
```lua
-- Client-side namespace (reliable)
local UI = NetLink.Client("UI")

-- Client-side namespace (unreliable)
local Camera = NetLink.Client("Camera", true)
```

### Event Communication

```lua
-- SERVER: Multiple listening patterns
Combat:On("Attack", function(player, targetId)
    -- Single event
end)

Combat:On("Defend", function(player, defendState)
    -- Single event
end)

Combat:On("UseSkill", function(player, skillName)
    -- Single event
end)

-- SERVER: Multiple firing patterns
Combat:Fire(player, "Hit", damage)           -- Single player
Combat:FireNow(player, "CriticalHit", 100)   -- Immediate (unbatched)
Combat:FireAll("GameOver", winner)            -- All players
Combat:FireAllExcept(attacker, "PlayerHit", targetId) -- All except one
Combat:FireList({player1, player2}, "TeamWin") -- Specific list

-- Filter-based firing
Combat:FireWithFilter(function(p)
    return p.Team == game.Teams.Red
end, "TeamMessage", "Red team wins!")
```
```lua
-- CLIENT: Fire and Call
local Combat = NetLink.Client("Combat")

Combat:Fire("RequestRespawn")
Combat:FireNow("EmergencyStop") -- Immediate

-- Promise-based server calls
Combat:Call("PurchaseItem", itemId, price)
    :andThen(function(success, newBalance)
        print("Purchase result:", success, newBalance)
    end)
```

---

## Rate Limiting

### Quick Setup

```lua
-- Use presets for instant protection
local Combat = NetLink.Server("Combat")
    :WithRateLimit("strict")   -- 5 calls/second
    :WithRateLimit("normal")   -- 10 calls/second (recommended)
    :WithRateLimit("relaxed")  -- 20 calls/second
    :WithRateLimit("burst")    -- 10 calls/second, 50 burst capacity
```

### Custom Configuration

```lua
local Trading = NetLink.Server("Trading")
    :WithRateLimit({
        MaxCalls = 3,        -- Max calls per window
        TimeWindow = 5,      -- Window duration in seconds
        Strategy = "sliding", -- fixed | sliding | token | leaky
        OnExceeded = function(key, attempts)
            local player = Players:GetPlayerByUserId(tonumber(key))
            if player and attempts > 50 then
                player:Kick("Rate limit abuse detected")
            end
        end
    })
```

### Monitoring

```lua
-- Get rate limiter instance
local limiter = Combat:GetRateLimiter()

-- Check statistics
local stats = limiter:GetStats()
print("Total checks:", stats.TotalChecks)
print("Blocked:", stats.TotalBlocked)
print("Block rate:", stats.BlockRate * 100, "%")

-- Get remaining calls for a player
local remaining = limiter:GetRemaining(tostring(player.UserId))
Combat:Fire(player, "UpdateRateLimit", remaining)

-- Reset rate limit for a player
Combat:ResetRateLimit(player)
```

---

## Examples

### Combat System

```lua
-- Server
local Combat = NetLink.Server("Combat")
    :WithRateLimit({
        MaxCalls = 5,
        TimeWindow = 1,
        Strategy = "sliding",
    })

Combat:On("Attack", function(player, targetId, weaponId)
    local target = Players:GetPlayerByUserId(targetId)
    if not target then return end
        
    local damage = calculateDamage(weaponId)
    Combat:Fire(target, "TakeDamage", damage, player.Name)
    Combat:FireAllExcept(target, "PlayerAttacked", player.Name, target.Name)
end)

Combat:On("AbilityUsed", function(player, targetId, weaponId)
     if not canUseAbility(player, abilityId) then return end
        
    Combat:FireAll("AbilityUsed", player.Name, abilityId, targetPos)
end)
```
```lua
-- Client
local Combat = NetLink.Client("Combat")

Combat:On("TakeDamage", function(damage, attackerName)
    updateHealthUI(damage)
    playHitEffect()
end)

Combat:On("AbilityUsed", function(player, targetId, weaponId)
     if not canUseAbility(player, abilityId) then return end
        
    Combat:FireAll("AbilityUsed", player.Name, abilityId, targetPos)
end)

Combat:On("AbilityUsed", function(playerName, abilityId, position)
    playAbilityVFX(abilityId, position)
end)

-- Fire attack
local targetPlayer = getTargetUnderCrosshair()
if targetPlayer then
    Combat:Fire("Attack", targetPlayer.UserId, equippedWeapon)
end
```

### Chat System with Token Bucket

```lua
-- Server: Allow bursts but limit sustained spam
local Chat = NetLink.Server("Chat")
    :WithRateLimit({
        MaxCalls = 5,
        TimeWindow = 1,
        Strategy = "token",
        BurstSize = 10,    -- Allow 10 messages in quick succession
        RefillRate = 5,    -- Refill 5 tokens per second
        OnExceeded = function(key, attempts)
            local player = Players:GetPlayerByUserId(tonumber(key))
            if player and attempts == 1 then
                Chat:Fire(player, "Warning", "Slow down your messages!")
            elseif player and attempts > 20 then
                player:Kick("Chat spam")
            end
        end
    })

Chat:On("SendMessage", function(player, message)
    if #message > 200 then return end -- Validate
    
    Chat:FireAll("NewMessage", player.Name, message)
end)

-- Grant VIP extra capacity
Players.PlayerAdded:Connect(function(player)
    if player:GetAttribute("IsVIP") then
        local limiter = Chat:GetRateLimiter()
        if limiter then
            limiter:AddTokens(tostring(player.UserId), 20)
        end
    end
end)
```

### High-Frequency Movement Sync (Unreliable)

```lua
-- Server: Use unreliable for position updates
local Movement = NetLink.Server("Movement", true) -- Unreliable mode

Movement:On("UpdatePosition", function(player, position, rotation)
    -- Broadcast to nearby players only (optimization)
    local nearbyPlayers = getNearbyPlayers(player, 100)
    Movement:FireList(nearbyPlayers, "PlayerMoved", player.UserId, position, rotation)
end)
```
```lua
-- Client: Send frequent updates without flooding
local Movement = NetLink.Client("Movement", true)
local RunService = game:GetService("RunService")

RunService.Heartbeat:Connect(function()
    local character = player.Character
    if not character then return end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp then
        Movement:Fire("UpdatePosition", hrp.Position, hrp.CFrame.LookVector)
    end
end)

Movement:On("PlayerMoved", function(userId, position, rotation)
    updatePlayerGhost(userId, position, rotation)
end)
```

### Inventory System with Server Calls

```lua
-- Server
local Inventory = NetLink.Server("Inventory")
    :WithRateLimit("sliding")

Inventory:On("EquipItem", function(player, itemId)
    local success = equipItemForPlayer(player, itemId)
    
    if success then
        Inventory:Fire(player, "ItemEquipped", itemId)
        Inventory:FireAllExcept(player, "PlayerEquipped", player.Name, itemId)
    end
end)

Inventory:On("GetInventory", function(player)
    local items = getPlayerInventory(player)
    return items -- Automatically sent back to client
end)
```
```lua
-- Client
local Inventory = NetLink.Client("Inventory")

-- Request inventory with Promise
Inventory:Call("GetInventory")
    :andThen(function(items)
        displayInventory(items)
    end)
    :catch(function(err)
        warn("Failed to load inventory:", err)
    end)

-- Equip item
equipButton.Activated:Connect(function()
    Inventory:Fire("EquipItem", selectedItemId)
end)

Inventory:On("ItemEquipped", function(itemId)
    print("Equipped:", itemId)
    updateEquipmentUI(itemId)
end)
```

### Admin System with Strict Limits

```lua
local Admin = NetLink.Server("Admin")
    :WithRateLimit({
        MaxCalls = 2,
        TimeWindow = 1,
        Strategy = "sliding",
    })

Admin:On("ExecuteCommand", function(player, command, args)
    -- Verify admin status
    if not isAdmin(player) then
        player:Kick("Unauthorized admin access attempt")
        return
    end
    
    -- Execute command
    executeAdminCommand(command, args)
    
    -- Log to all admins
    Admin:FireWithFilter(isAdmin, "CommandExecuted", player.Name, command)
end)
```

### Dynamic Rate Adjustment

```lua
-- Adjust limits based on server performance
local Combat = NetLink.Server("Combat"):WithRateLimit("normal")

RunService.Heartbeat:Connect(function(deltaTime)
    local fps = 1 / deltaTime
    local limiter = Combat:GetRateLimiter()
    
    if not limiter then return end
    
    if fps < 30 then
        limiter:SetMaxCalls(5)  -- Stricter under load
    elseif fps > 55 then
        limiter:SetMaxCalls(15) -- More generous when smooth
    else
        limiter:SetMaxCalls(10) -- Normal
    end
end)
```

---

## API Reference

### NetLink

#### `NetLink.Server(name: string, unreliable: boolean?) → Server`
Creates or retrieves a server namespace.

#### `NetLink.Client(name: string, unreliable: boolean?) → Client`
Creates or retrieves a client namespace.

#### `NetLink.Promise`
Access to the built-in Promise implementation.

#### `NetLink.RateLimit`
Access to the RateLimit module for standalone use.

---

### Server

#### `Server:Fire(player: Player, event: string, ...any)`
Fires an event to a specific player (batched, sent on next Heartbeat).

#### `Server:FireNow(player: Player, event: string, ...any)`
Fires an event to a specific player immediately (unbatched).

#### `Server:FireAll(event: string, ...any)`
Fires an event to all connected players (batched).

#### `Server:FireAllExcept(except: Player, event: string, ...any)`
Fires an event to all players except one (batched).

#### `Server:FireList(playerList: {Player}, event: string, ...any)`
Fires an event to a specific list of players (batched).

#### `Server:FireWithFilter(filter: (Player) → boolean, event: string, ...any)`
Fires an event to players matching a filter function (batched).

#### `Server:On(events: {[string]: (Player, ...any) → ()} | string, callback?)`
Registers event listener(s) for incoming client events.

#### `Server:WithRateLimit(config: RateLimitConfig | preset) → Server`
Enables rate limiting for this namespace. Returns self for chaining.

#### `Server:GetRateLimiter() → RateLimit?`
Gets the rate limiter for this namespace (if enabled).

#### `Server:ResetRateLimit(player: Player)`
Resets rate limit data for a specific player.

---

### Client

#### `Client:Fire(event: string, ...any)`
Fires an event to the server (batched, sent on next Heartbeat).

#### `Client:FireNow(event: string, ...any)`
Fires an event to the server immediately (unbatched).

#### `Client:Call(event: string, ...any) → Promise<...any>`
Calls a server function and returns a Promise with the result.

#### `Client:On(events: {[string]: (...any) → ()} | string, callback?)`
Registers event listener(s) for incoming server events.

---

### RateLimit

#### `RateLimit.new(config: RateLimitConfig) → RateLimit`
Creates a new RateLimit instance.

#### `RateLimit.Preset(preset: string) → RateLimitConfig`
Returns a preset configuration ("strict", "normal", "relaxed", "burst").

#### `RateLimit:Check(key: string) → (boolean, number?)`
Checks if a key can perform an action. Returns allowed status and retry time.

#### `RateLimit:GetRemaining(key: string) → number`
Gets the current number of remaining calls for a key.

#### `RateLimit:GetStats() → RateLimitStats`
Gets comprehensive statistics about rate limiting.

#### `RateLimit:Reset(key: string)`
Resets rate limit data for a specific key.

#### `RateLimit:ResetAll()`
Resets all rate limit data.

#### `RateLimit:AddTokens(key: string, amount: number)`
Adds tokens to a token bucket (token bucket strategy only).

#### `RateLimit:SetMaxCalls(newMax: number)`
Adjusts the maximum calls limit dynamically.

---

## Rate Limiting Strategies

| Strategy | Best For | Pros | Cons |
|----------|----------|------|------|
| **fixed** | General purpose | Simple, efficient | Boundary bursts |
| **sliding** ⭐ | Critical events | Accurate, fair | More memory |
| **token** | Chat, APIs | Burst tolerance | Complex config |
| **leaky** | Queues | Smooth rates | Can delay legit requests |

### Presets

```lua
"strict"   -- 5 calls/sec, sliding window
"normal"   -- 10 calls/sec, sliding window (recommended)
"relaxed"  -- 20 calls/sec, fixed window
"burst"    -- 10 calls/sec base, 50 burst capacity
```

---

## Best Practices

✅ **DO:**
- Use namespaces to organize related events
- Enable rate limiting on server namespaces to prevent abuse
- Use unreliable transport for high-frequency, non-critical data (position updates, animations)
- Use reliable transport for critical gameplay events (damage, purchases, chat)
- Use `FireNow()` sparingly, only when immediate delivery is required
- Monitor rate limit statistics in production
- Use Promises for client-server calls that need responses

❌ **DON'T:**
- Create too many namespaces (group related events together)
- Use reliable transport for 60Hz updates (use unreliable instead)
- Forget to enable rate limiting on public-facing endpoints
- Send large data payloads frequently (compress or batch them)
- Mix reliable and unreliable modes in the same namespace

---

## Type Definitions

```lua
export type Server = {
    Fire: (self: Server, player: Player, event: string, ...any) -> (),
    FireNow: (self: Server, player: Player, event: string, ...any) -> (),
    FireAll: (self: Server, event: string, ...any) -> (),
    FireAllExcept: (self: Server, except: Player, event: string, ...any) -> (),
    FireList: (self: Server, playerList: {Player}, event: string, ...any) -> (),
    FireWithFilter: (self: Server, filter: (Player) -> boolean, event: string, ...any) -> (),
    On: (self: Server, events: {[string]: (Player, ...any) -> ()} | string, callback: ((Player, ...any) -> ())?) -> (),
    WithRateLimit: (self: Server, config: RateLimitConfig | string) -> Server,
    GetRateLimiter: (self: Server) -> RateLimit?,
    ResetRateLimit: (self: Server, player: Player) -> (),
}

export type Client = {
    Fire: (self: Client, event: string, ...any) -> (),
    FireNow: (self: Client, event: string, ...any) -> (),
    Call: (self: Client, event: string, ...any) -> Promise<...any>,
    On: (self: Client, events: {[string]: (...any) -> ()} | string, callback: ((...any) -> ())?) -> (),
}

export type RateLimitConfig = {
    MaxCalls: number,
    TimeWindow: number,
    Strategy: "fixed" | "sliding" | "token" | "leaky"?,
    BurstSize: number?,
    RefillRate: number?,
    OnExceeded: ((key: string, attempts: number) -> ())?,
}
```

---

## Performance Tips

- **Batching**: Events are automatically batched per Heartbeat. Use `FireNow()` only when necessary.
- **Unreliable Transport**: Use for high-frequency updates where occasional packet loss is acceptable.
- **Rate Limiting**: Prevents malicious clients from overloading your server.
- **Namespace Isolation**: Different namespaces = different rate limiters = better granularity.
- **Event ID Caching**: Event IDs are generated once and cached for the session.

---

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

---

## License

MIT License - Created by Vadym Maist

---

## Credits

Vadym Maist (aka Vaist, WhatAboutCap, Cap)