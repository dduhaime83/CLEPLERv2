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
    HealWatchList     = true,
    MaxHealRange      = 200,
    -- Buff checker (see buffs.lua). Level-aware: each buff entry
    -- in healprofiles.lua carries a MinLevel for the recipient.
    Buffing             = true,    -- master toggle for buff casting
    BuffInterval        = 2000,    -- ms between buff pulses
    BuffRefreshBuffer   = 120,     -- sec early-refresh safety margin
    BuffGroup           = false,   -- also buff group members (not just leeches)
    BuffMinManaPct      = 20,      -- skip buffing below this mana %
    BuffDefaultDurationSec = 1800,  -- fallback when MQ reports no duration
    -- Proactive HoT rolling: keep a heal-over-time on the
    -- priority leech so it doesn't dip into emergency in the
    -- first place. Tracker-based, same model as buffs.
    HotRolling          = true,    -- master toggle for HoT rolling
    HotInterval         = 2000,    -- ms between HoT pulses
    HotRefreshBuffer    = 12,      -- sec early-refresh margin (~2 ticks)
    HotMinManaPct       = 25,      -- skip HoT rolling below this mana %
    HotOnlyLeech        = true,    -- only roll HoT on leeches (not group)
    HotDefaultDurationSec = 72,    -- fallback when MQ reports no HoT duration
    -- Med breaks: when mana drops below MedManaFloorPct the PLer
    -- sits to med and suspends non-essential casts; it stands
    -- and resumes at MedManaCeilingPct. Hysteresis prevents
    -- thrashing. Emergency self-heals still fire while medding.
    MedBreaks           = true,    -- master toggle for med breaks
    MedManaFloorPct     = 15,      -- sit below this mana %
    MedManaCeilingPct   = 85,      -- stand/resume above this mana %
    -- Auto-follow: stick to the priority (top enabled) leech via
    -- MQ2MoveUtils /stick id so the PLer chases automatically.
    -- Stops for heals (caster pauses stick before every cast),
    -- med breaks, combat, casting, and pause.
    FollowEnabled       = false,   -- master toggle (off by default for safety)
    FollowDistance      = 20,      -- /stick distance in units
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

-- Buff tracker: keyed by "<LowerName>||<BuffName>" ->
-- { CastAt = ms, Duration = sec }. Maintained by buffs.lua.
-- Uses character name (not spawn id) so it survives zoning.
State.BuffTracker = {}

-- HoT tracker: same shape as BuffTracker, maintained by hots.lua.
-- Keyed by "<LowerName>||<HotName>".
State.HotTracker = {}

-- Runtime flag: a gem-loadout mem sequence is in progress.
-- Set by loadout.lua; read by follow.lua (stop moving while
-- re-gemming). Cleared when the queue drains or is cancelled.
State.MemmingLoadout = false

-- Simple runtime counters.
State.Stats = {
    HealsCast     = 0,
    Emergencies   = 0,
    FailedCasts   = 0,
    BuffsCast     = 0,
    HotsCast      = 0,
}

return State
