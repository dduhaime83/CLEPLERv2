------------------------------------------------------------
-- CLEPLER
-- med.lua
--
-- Mana management with hysteresis. When mana drops below the
-- floor the PLer sits to med and suspends non-essential casts
-- (buffs, HoTs, non-emergency heals); it stands and resumes at
-- the ceiling. The floor/ceiling gap prevents sit/stand
-- thrashing around a single threshold.
--
-- Emergency self-heals still fire while medding -- a dead PLer
-- heals no one. The healer gates on Med.IsMedding() for
-- non-emergency spells; self-emergency heals bypass it.
--
-- MQ2 API:
--   mq.TLO.Me.Sitting()  -> bool
--   mq.TLO.Me.Standing() -> bool
--   mq.TLO.Me.PctMana()  -> 0..100
--   /sit on | /sit off | /stand
------------------------------------------------------------

local mq    = require('mq')
local State = require('state')

local Med = {}

-- Runtime state: are we currently in a med break?
Med.Medding = false

------------------------------------------------------------
-- pcall wrapper
------------------------------------------------------------

local function SafeCall(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

------------------------------------------------------------
-- Read current mana %
------------------------------------------------------------

local function PctMana()
    local v = SafeCall(function() return mq.TLO.Me.PctMana() end)
    return tonumber(v) or 100
end

------------------------------------------------------------
-- Is the PLer currently sitting?
------------------------------------------------------------

function Med.IsSitting()
    local v = SafeCall(function() return mq.TLO.Me.Sitting() end)
    return v == true
end

function Med.IsStanding()
    local v = SafeCall(function() return mq.TLO.Me.Standing() end)
    return v == true
end

------------------------------------------------------------
-- Sit / stand
------------------------------------------------------------

function Med.Sit()
    if Med.IsSitting() then return end
    mq.cmd("/sit on")
end

function Med.Stand()
    if not Med.IsSitting() and Med.IsStanding() then return end
    mq.cmd("/stand")
end

------------------------------------------------------------
-- Pulse (Heartbeat entry point).
--   Drives the hysteresis state machine and the actual
--   sit/stand commands. Cheap to run frequently.
------------------------------------------------------------

function Med.Pulse()

    if not State.Enabled then return end

    -- If med breaks were toggled off mid-break, clear any stale
    -- medding state so we stand and stop suppressing casts.
    if not State.Settings.MedBreaks then
        if Med.Medding then Med.Break() end
        return
    end

    -- Don't sit/med while in combat -- a cleric on the ground
    -- heals no one, and sitting tanks AC. Stand and let the
    -- healer handle incoming damage.
    local combat = SafeCall(function() return mq.TLO.Me.CombatState() end)
    if combat == "COMBAT" then
        if Med.Medding then Med.Break() end
        return
    end

    local mana   = PctMana()
    local floor  = State.Settings.MedManaFloorPct or 15
    local ceil   = State.Settings.MedManaCeilingPct or 85

    -- Dead? Don't try to sit/stand.
    local dead = SafeCall(function() return mq.TLO.Me.Dead() end)
    if dead == true then
        return
    end

    -- Don't manage posture while casting (sitting mid-cast is
    -- impossible anyway, and standing mid-cast cancels nothing
    -- useful here).
    local casting = SafeCall(function() return mq.TLO.Me.Casting() end)
    if casting and casting ~= "" then
        return
    end

    --------------------------------------------------------
    -- Hysteresis transitions
    --------------------------------------------------------
    if not Med.Medding then
        if mana <= floor then
            Med.Medding = true
            Med.Sit()
            if State.Settings.Debug then
                print(string.format(
                    "[CLEPLER] med break: sitting at %d%% mana", mana))
            end
        end
    else
        if mana >= ceil then
            Med.Medding = false
            Med.Stand()
            if State.Settings.Debug then
                print(string.format(
                    "[CLEPLER] med break: resuming at %d%% mana", mana))
            end
        end
    end
end

------------------------------------------------------------
-- Should non-essential casts be suppressed right now?
--   True when medding. Emergency self-heals bypass this
--   (the healer checks Med.IsMedding() only for non-emergency).
------------------------------------------------------------

function Med.IsMedding()
    return State.Settings.MedBreaks == true and Med.Medding == true
end

------------------------------------------------------------
-- Force-clear the medding state (e.g. on combat aggro, so we
-- stand and can heal). The next Pulse re-evaluates.
------------------------------------------------------------

function Med.Break()
    if Med.Medding then
        Med.Medding = false
        Med.Stand()
    end
end

return Med
