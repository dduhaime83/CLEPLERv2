------------------------------------------------------------
-- CLEPLER
-- spellbook.lua
--
-- Full spellbook cache (every spell the caster owns), distinct
-- from spells.lua which only caches the 12 memorized gem slots.
--
-- Used to answer "is this spell in my book?" and to memorize a
-- spell into a gem so the healer/buff checker can cast it.
--
-- MQ2 API:
--   mq.TLO.Me.Book(i).Name() / .ID()  -- i is 1..spellbook size
--   /memspell <gem> "<spellname>"     -- memorize a spell
--
-- Spellbooks can have holes (empty slots mid-range), so Refresh
-- scans a fixed cap and skips invalid entries rather than
-- breaking on the first empty one.
------------------------------------------------------------

local mq        = require('mq')
local State     = require('state')
local Spells    = require('spells')

local Spellbook = {}

-- RoF2 clients have an 8*90 = 720-slot book; use a generous cap
-- and tolerate nil/empty entries without breaking.
Spellbook.MaxSlots = 1000

Spellbook.ByName = {}   -- lowercased name -> { Index, ID, Name }
Spellbook.Entries = {}   -- array of records in book-index order

------------------------------------------------------------
-- pcall wrapper (TLO access can throw on stale/invalid data)
------------------------------------------------------------

local function SafeCall(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

------------------------------------------------------------
-- Refresh the spellbook cache
------------------------------------------------------------

function Spellbook.Refresh()
    Spellbook.ByName = {}
    Spellbook.Entries = {}

    for i = 1, Spellbook.MaxSlots do
        local id = SafeCall(function()
            return mq.TLO.Me.Book(i).ID()
        end)
        local name = SafeCall(function()
            return mq.TLO.Me.Book(i).Name()
        end)

        if id and id ~= 0 and name and name ~= "" then
            local rec = { Index = i, ID = id, Name = name }
            Spellbook.ByName[name:lower()] = rec
            table.insert(Spellbook.Entries, rec)
        end
    end

    if State.Settings.Debug then
        print(string.format("[CLEPLER] spellbook: %d spells known",
            #Spellbook.Entries))
    end
end

------------------------------------------------------------
-- Lookups
------------------------------------------------------------

-- Exact (case-insensitive) name -> record, or nil.
function Spellbook.Get(name)
    if not name then return nil end
    return Spellbook.ByName[name:lower()]
end

function Spellbook.Has(name)
    return name ~= nil and Spellbook.ByName[name:lower()] ~= nil
end

-- Case-insensitive substring match. Returns the first matching
-- record in book-index order, or nil.
function Spellbook.Find(substr)
    if not substr or substr == "" then
        return nil
    end
    local needle = substr:lower()
    for _, rec in ipairs(Spellbook.Entries) do
        if rec.Name:lower():find(needle, 1, true) then
            return rec
        end
    end
    return nil
end

------------------------------------------------------------
-- Memorize a spell into a gem slot.
--   Fire-and-forget: issues /memspell and returns true; does NOT
--   wait for memorization to finish (blocking the main loop
--   would stall heartbeats/UI and could be unsafe while
--   healing). After the spell lands, run /clepler reloadspells
--   to refresh the gem cache.
--   Returns false if the spell isn't in the book or gem is bad.
------------------------------------------------------------

function Spellbook.Memorize(name, gem)
    if not name or not gem then
        return false
    end
    gem = tonumber(gem)
    if not gem or gem < 1 or gem > 12 then
        return false
    end

    -- Resolve exact name first, then substring match.
    local rec = Spellbook.Get(name) or Spellbook.Find(name)
    if not rec then
        return false
    end

    if State.Settings.TestMode then
        print(string.format(
            "[CLEPLER][TEST] would memorize %s into gem %d",
            rec.Name, gem))
        return true
    end

    mq.cmd(string.format('/memspell %d "%s"', gem, rec.Name))
    print(string.format("[CLEPLER] memorizing %s into gem %d",
        rec.Name, gem))
    return true
end

-- Is a spell currently memorized in a gem slot? Delegates to the
-- spells.lua gem cache (refreshed on load + /clepler reloadspells).
function Spellbook.IsMemorized(name)
    return Spells.Has(name)
end

------------------------------------------------------------
-- Count of known spells
------------------------------------------------------------

function Spellbook.Count()
    return #Spellbook.Entries
end

return Spellbook
