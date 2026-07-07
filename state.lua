------------------------------------------------------------
-- CLEPLER
-- state.lua
--
-- Central runtime + configuration state. Shared by every
-- module. Settings defaults MUST match config.lua so that
-- Config.Load()/Save() round-trips cleanly through the INI.
------------------------------------------------------------

local State = {}

State.Version = "0.2"

------------------------------------------------------------
-- Runtime flags
------------------------------------------------------------

State.Running  = false   -- set true by init.lua once the loop starts
State.Enabled  = false   -- /clepler on|off  (is healing active)
State.Paused    = false   -- /clepler pause   (skips Heartbeat.Pulse)

------------------------------------------------------------
-- Live heal context (read by widgets)
------------------------------------------------------------

State.CurrentTarget = nil
State.CurrentSpell  = nil
State.LastAction    = ""
State.LastError     = ""

------------------------------------------------------------
-- Settings (persisted to CLEPLER.ini via config.lua)
-- Keep these keys/types in sync with Config.Reset().
------------------------------------------------------------

State.Settings = {
    ScanDelay        = 100,
    ReturnTarget     = true,
    AnnounceHeals    = true,
    IgnoreLOS        = false,
    IgnoreRange      = false,
    TestMode         = true,
    UseFastHeal      = true,
    FastHealPct      = 30,
    UseBigHeal       = true,
    BigHealPct       = 65,
    UseCompleteHeal  = true,
    CompleteHealPct  = 40,
    UseHoT           = false,
    HoTPct           = 85,
    Debug            = false,
}

------------------------------------------------------------
-- Collections
------------------------------------------------------------

-- Named leech roster (managed by watchlist.lua). v1 healing is
-- group-only; the watchlist is loaded/saved but not yet merged
-- into the scanner. See watchlist.lua.
State.WatchList = {}

-- Optional spell-role overrides (reserved for future use).
State.SpellRoles = {}

-- Simple runtime counters.
State.Stats = {
    HealsCast     = 0,
    Emergencies   = 0,
    FailedCasts   = 0,
}

return State
