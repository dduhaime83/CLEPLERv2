------------------------------------------------------------
-- CLEPLER
-- loadout.lua
--
-- Gem loadout: a per-gem spell assignment (gem 1..12 -> spell
-- name) the operator configures in the Settings tab. "Mem All"
-- memorizes every assigned spell into its gem if it isn't
-- already there.
--
-- Memming is slow (~5s per spell) and you can't cast a gem
-- while it's being rememorized, so MemAll is NOT a tight loop.
-- It builds a queue of gems that need changing and drains it
-- one at a time from Loadout.Pulse(), which init.lua calls
-- every main-loop tick (unconditionally, outside the paused
-- heartbeat). Each /memspell is spaced by CommandDelay so the
-- previous one can land.
--
-- While a mem sequence is active, State.MemmingLoadout is set
-- so follow.lua stops moving (movement can interrupt memming
-- and isn't useful while re-gemming).
--
-- MQ2 API:
--   /memspell <gem> "<spellname>"   (via Spellbook.Memorize)
--   mq.TLO.Ini(file, section, key)()  INI read
--   /ini "<file>" "<section>" "<key>" "<value>"
--   mq.TLO.Me.CombatState()  -> "COMBAT" etc.
--   mq.TLO.Me.Casting()      -> spell name or ""
------------------------------------------------------------

local mq        = require('mq')
local State     = require('state')
local Spells    = require('spells')
local Spellbook = require('spellbook')
local Follow    = require('follow')

local Loadout = {}

Loadout.File    = mq.configDir .. "\\CLEPLER.ini"
Loadout.Section = "GemLoadout"

-- 12 gem slots; "" = unassigned. Loaded from INI.
Loadout.Slots = {}
for i = 1, 12 do Loadout.Slots[i] = "" end

-- Queue state machine (button-triggered).
Loadout.Queue         = {}
Loadout.Active        = false
Loadout.LastCommandAt = 0
Loadout.CommandDelay  = 5500   -- ms between /memspell (memming takes a few sec)

------------------------------------------------------------
-- pcall wrapper
------------------------------------------------------------

local function SafeCall(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

local function AmCasting()
    local c = SafeCall(function() return mq.TLO.Me.Casting() end)
    return c ~= nil and c ~= ""
end

local function InCombat()
    local cs = SafeCall(function() return mq.TLO.Me.CombatState() end)
    return cs == "COMBAT"
end

------------------------------------------------------------
-- Load / Save (CLEPLER.ini, "GemLoadout" section -- separate
-- from the scalar State.Settings so the generic config loop
-- never touches it).
------------------------------------------------------------

local function ReadKey(key, default)
    local v = SafeCall(function()
        return mq.TLO.Ini(Loadout.File, Loadout.Section, key)()
    end)
    if v == nil or v == "" then return default end
    return v
end

function Loadout.Load()
    for i = 1, 12 do
        Loadout.Slots[i] = ReadKey("Gem" .. i, "") or ""
    end
end

-- Write all 12 slots (used on load/init).
function Loadout.Save()
    for i = 1, 12 do
        mq.cmdf('/ini "%s" "%s" "%s" "%s"',
            Loadout.File, Loadout.Section, "Gem" .. i, Loadout.Slots[i] or "")
    end
end

-- Write a single slot (used by the UI on each edit -- avoids 12
-- INI writes per keystroke).
function Loadout.SaveGem(gem)
    gem = tonumber(gem)
    if not gem or gem < 1 or gem > 12 then return end
    mq.cmdf('/ini "%s" "%s" "%s" "%s"',
        Loadout.File, Loadout.Section, "Gem" .. gem, Loadout.Slots[gem] or "")
end

function Loadout.Get(gem)
    gem = tonumber(gem)
    if not gem or gem < 1 or gem > 12 then return "" end
    return Loadout.Slots[gem] or ""
end

function Loadout.Set(gem, name)
    gem = tonumber(gem)
    if not gem or gem < 1 or gem > 12 then return false end
    Loadout.Slots[gem] = name or ""
    return true
end

------------------------------------------------------------
-- Build the mem queue from the loadout. Only gems whose
-- assigned spell differs from (or is absent in) the current
-- gem get queued.
------------------------------------------------------------

function Loadout.MemAll()

    if Loadout.Active then
        print("[CLEPLER] memall already in progress")
        return
    end

    -- Memming a gem blanks it for several seconds and you can't
    -- cast from a gem mid-memorize, so don't run this while live
    -- healing is active. Pause (or /clepler off) first --
    -- Loadout.Pulse keeps draining the queue while paused.
    if State.Enabled and not State.Paused then
        print("[CLEPLER] memall skipped: pause healing (/clepler pause) or /clepler off first")
        return
    end

    -- /memspell is a real game action, and Spellbook.Memorize
    -- short-circuits to a dry-run print under TestMode. Left
    -- unguarded, MemAll would build the queue and Pulse would
    -- "drain" it (even showing [MEMMING] progress) while nothing
    -- actually gets re-gemmed -- exactly the "loads but never
    -- mems" symptom. Bail early with a clear, actionable message
    -- instead of silently no-opping.
    if State.Settings.TestMode then
        print("[CLEPLER] memall skipped: Test Mode is ON (dry run, no casts). Disable Test Mode to memorize.")
        return
    end

    if InCombat() then
        print("[CLEPLER] memall skipped: in combat")
        return
    end
    if AmCasting() then
        print("[CLEPLER] memall skipped: casting")
        return
    end

    -- Fresh caches so we know what's scribed and what's memmed.
    Spellbook.Refresh()
    Spells.Refresh()

    Loadout.Queue = {}
    for gem = 1, 12 do
        local spell = Loadout.Slots[gem] or ""
        if spell ~= "" then
            local rec = Spellbook.Get(spell) or Spellbook.Find(spell)
            if not rec then
                print(string.format(
                    "[CLEPLER] gem %d: '%s' not in spellbook, skipping",
                    gem, spell))
            else
                local cur = Spells.Database.ByGem[gem]
                local curName = (cur and cur.Name) or ""
                if curName:lower() == rec.Name:lower() then
                    -- already the right spell here
                else
                    table.insert(Loadout.Queue, { Gem = gem, Name = rec.Name })
                end
            end
        end
    end

    if #Loadout.Queue == 0 then
        print("[CLEPLER] memall: nothing to memorize (all gems correct)")
        return
    end

    Loadout.Active       = true
    State.MemmingLoadout = true
    Follow.Stop("memming")
    print(string.format("[CLEPLER] memall: queuing %d gem(s)", #Loadout.Queue))
end

function Loadout.Cancel(reason)
    if not Loadout.Active then return end
    Loadout.Active        = false
    Loadout.Queue         = {}
    Loadout.LastCommandAt = 0
    State.MemmingLoadout  = false
    print(string.format("[CLEPLER] memall cancelled (%s)", reason or "manual"))
end

------------------------------------------------------------
-- Pulse (called unconditionally from the init main loop, NOT
-- the paused heartbeat -- the operator may pause healing before
-- re-gemming). No-ops unless a mem sequence is active.
------------------------------------------------------------

function Loadout.Pulse()

    if not Loadout.Active then return end

    -- Bail out if conditions go bad mid-sequence.
    if InCombat() then Loadout.Cancel("combat"); return end
    if AmCasting() then return end   -- wait for the cast to finish

    local now = mq.gettime()
    if Loadout.LastCommandAt > 0
        and now - Loadout.LastCommandAt < Loadout.CommandDelay then
        return
    end

    local job = table.remove(Loadout.Queue, 1)
    if not job then
        Loadout.Active        = false
        Loadout.LastCommandAt = 0
        State.MemmingLoadout  = false
        Spells.Refresh()
        print("[CLEPLER] memall complete (run /clepler reloadspells if gems changed)")
        return
    end

    Follow.Stop("memming")
    Spellbook.Memorize(job.Name, job.Gem)
    Loadout.LastCommandAt = now
end

return Loadout
