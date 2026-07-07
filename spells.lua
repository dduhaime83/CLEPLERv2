------------------------------------------------------------
-- CLEPLER
-- spells.lua
--
-- Memorized-spell discovery. Scans gems 1..12 and builds a
-- name->record map so the caster can resolve a spell name to
-- its gem slot, readiness, mana cost, and range.
------------------------------------------------------------

local mq     = require('mq')
local Spells = {}

Spells.Database = {}        -- keyed by spell name
Spells.Database.ByGem = {}  -- keyed by gem index

------------------------------------------------------------
-- pcall wrapper (TLO access can throw on stale/invalid data)
------------------------------------------------------------

local function SafeCall(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

------------------------------------------------------------
-- Refresh the gem cache
------------------------------------------------------------

function Spells.Refresh()
    Spells.Database = {}
    Spells.Database.ByGem = {}

    for gem = 1, 12 do
        local name = SafeCall(function()
            return mq.TLO.Me.Gem(gem)()
        end)

        if name and name ~= "" then
            local record = { Gem = gem, Name = name }
            Spells.Database[name]       = record
            Spells.Database.ByGem[gem]  = record
            print(string.format("[CLEPLER] gem %d: %s", gem, name))
        end
    end
end

------------------------------------------------------------
-- Lookups
------------------------------------------------------------

function Spells.Get(name)
    if not name then return nil end
    return Spells.Database[name]
end

function Spells.Has(name)
    return name ~= nil and Spells.Database[name] ~= nil
end

function Spells.GemFor(name)
    local record = Spells.Database[name]
    return record and record.Gem or nil
end

------------------------------------------------------------
-- Substring match across the gem cache.
-- Used by the buff checker: a profile entry names a base
-- spell (e.g. "Symbol") whose memorized instance may differ
-- (e.g. "Symbol of Ryltan"). Returns the first memorized
-- spell record whose name contains `substr` (case-insensitive),
-- or nil.
------------------------------------------------------------

function Spells.FindByMatch(substr)
    if not substr or substr == "" then
        return nil
    end
    local needle = substr:lower()
    -- Deterministic: scan gems 1..12 in order rather than
    -- relying on pairs() hash order over the name-keyed table.
    for gem = 1, 12 do
        local record = Spells.Database.ByGem[gem]
        local name = record and record.Name
        if name and name:lower():find(needle, 1, true) then
            return record
        end
    end
    return nil
end

------------------------------------------------------------
-- Readiness / cost / range
--   Me.SpellReady(name) -> true when not on recovery/recast
--   Spell(name).Mana()  -> mana cost
--   Spell(name).MyRange() / .Range()
------------------------------------------------------------

function Spells.Ready(name)
    if not name or not Spells.Has(name) then
        return false
    end
    local value = SafeCall(function()
        return mq.TLO.Me.SpellReady(name)()
    end)
    return value == true
end

function Spells.Mana(name)
    if not name then return 0 end
    local value = SafeCall(function()
        return mq.TLO.Spell(name).Mana()
    end)
    return value or 0
end

function Spells.Range(name)
    if not name then return 0 end
    local value = SafeCall(function()
        return mq.TLO.Spell(name).MyRange()
    end)
    if not value then
        value = SafeCall(function()
            return mq.TLO.Spell(name).Range()
        end)
    end
    return value or 0
end

------------------------------------------------------------
-- Spell duration in seconds.
--   Spell(name).MyDuration() returns ticks (1 tick = 6 sec);
--   falls back to .Duration(), then to the configured default.
------------------------------------------------------------

function Spells.Duration(name)
    if not name then return 0 end
    local ticks = SafeCall(function()
        return mq.TLO.Spell(name).MyDuration()
    end)
    if not ticks or ticks <= 0 then
        ticks = SafeCall(function()
            return mq.TLO.Spell(name).Duration()
        end)
    end
    if ticks and ticks > 0 then
        return ticks * 6
    end
    -- Fall back to the configured default so the tracker still
    -- ages the buff out on schedule.
    local State = require('state')
    return State.Settings.BuffDefaultDurationSec or 1800
end

return Spells
