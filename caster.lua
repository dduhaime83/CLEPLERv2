------------------------------------------------------------
-- CLEPLER
-- caster.lua
--
-- Single safe casting path. All spell casts go through here so
-- gating logic (throttle, casting, stunned, mana, gem ready,
-- range, LOS) is applied consistently.
--
-- v1 supports memorized Spells only (cast by gem). AA entries
-- in healprofiles.lua are skipped by the healer.
------------------------------------------------------------

local mq     = require('mq')
local State  = require('state')
local Spells = require('spells')
local Targeting = require('targeting')

local Caster = {}

------------------------------------------------------------
-- Throttle (Healer.Pulse runs every ~25ms)
------------------------------------------------------------

Caster.LastAttempt  = 0
Caster.AttemptDelay = 500   -- ms between cast attempts

------------------------------------------------------------
-- pcall wrapper
------------------------------------------------------------

local function SafeCall(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

------------------------------------------------------------
-- Spawn helpers
------------------------------------------------------------

local function GetSpawn(id)
    return SafeCall(function()
        return mq.TLO.Spawn("id " .. tostring(id))
    end)
end

local function SpawnDistance(id)
    local spawn = GetSpawn(id)
    if not spawn then return 9999 end
    local d = SafeCall(function() return spawn.Distance() end)
    return d or 9999
end

local function SpawnLOS(id)
    local spawn = GetSpawn(id)
    if not spawn then return false end
    local v = SafeCall(function() return spawn.LineOfSight() end)
    return v == true
end

------------------------------------------------------------
-- Self-state gates
------------------------------------------------------------

local function AmCasting()
    local casting = SafeCall(function() return mq.TLO.Me.Casting() end)
    return casting ~= nil and casting ~= ""
end

local function AmStunned()
    local v = SafeCall(function() return mq.TLO.Me.Stunned() end)
    return v == true
end

local function CurrentMana()
    local v = SafeCall(function() return mq.TLO.Me.CurrentMana() end)
    return v or 0
end

------------------------------------------------------------
-- Cast
--   spellName : memorized spell name
--   targetID  : spawn id of the heal target
--   entry     : optional profile entry (for logging)
-- returns true on success (or dry-run), false otherwise
------------------------------------------------------------

function Caster.Cast(spellName, targetID, entry)

    if not spellName or not targetID then
        return false
    end

    -- Throttle
    local now = mq.gettime()
    if now - Caster.LastAttempt < Caster.AttemptDelay then
        return false
    end

    --------------------------------------------------------
    -- Dry run
    --------------------------------------------------------
    if State.Settings.TestMode then
        Caster.LastAttempt  = now
        State.CurrentTarget = tostring(targetID)
        State.CurrentSpell  = spellName
        State.LastAction    = "test"
        print(string.format("[CLEPLER][TEST] would cast %s on id %s",
            spellName, tostring(targetID)))
        return true
    end

    --------------------------------------------------------
    -- Self gates
    --------------------------------------------------------
    if AmCasting() then return false end
    if AmStunned() then return false end

    local gem = Spells.GemFor(spellName)
    if not gem then
        State.LastError = "not memorized: " .. spellName
        return false
    end

    if not Spells.Ready(spellName) then
        State.LastError = "not ready: " .. spellName
        return false
    end

    local cost = Spells.Mana(spellName)
    if CurrentMana() < cost then
        State.LastError = "insufficient mana: " .. spellName
        return false
    end

    --------------------------------------------------------
    -- Target gates
    --------------------------------------------------------
    if not State.Settings.IgnoreRange then
        local range = Spells.Range(spellName)
        if range > 0 and SpawnDistance(targetID) > range then
            State.LastError = "out of range: " .. spellName
            return false
        end
    end

    if not State.Settings.IgnoreLOS then
        if not SpawnLOS(targetID) then
            State.LastError = "no LOS: " .. spellName
            return false
        end
    end

    --------------------------------------------------------
    -- Cast
    --------------------------------------------------------
    local oldTarget = nil
    if State.Settings.ReturnTarget then
        oldTarget = Targeting.Save()
    end

    Targeting.Set(targetID)
    mq.delay(100)
    mq.cmd("/cast " .. tostring(gem))

    Caster.LastAttempt  = now
    State.CurrentTarget = tostring(targetID)
    State.CurrentSpell  = spellName
    State.LastAction    = "cast"
    State.LastError     = ""

    -- Route the counter by entry category: buff casts feed
    -- BuffsCast, HoT casts feed HotsCast, heals feed HealsCast.
    -- entry is optional so callers without a profile entry still
    -- count as heals.
    if entry and entry.Category == "Buff" then
        State.Stats.BuffsCast = State.Stats.BuffsCast + 1
    elseif entry and entry.Category == "Hot" then
        State.Stats.HotsCast = State.Stats.HotsCast + 1
    else
        State.Stats.HealsCast = State.Stats.HealsCast + 1
    end

    if State.Settings.Debug then
        print(string.format("[CLEPLER] cast %s (gem %d) on id %s",
            spellName, gem, tostring(targetID)))
    end

    --------------------------------------------------------
    -- Restore target
    --------------------------------------------------------
    if State.Settings.ReturnTarget and oldTarget then
        mq.delay(200)
        Targeting.Restore(oldTarget)
    end

    return true
end

return Caster
