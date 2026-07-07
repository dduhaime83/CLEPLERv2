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

return Spells
