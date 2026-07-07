------------------------------------------------------------
-- CLEPLER
-- hots.lua
--
-- Proactive heal-over-time roller. Keeps a HoT rolling on the
-- priority leech so it never dips into emergency in the first
-- place -- mitigation rather than reaction.
--
-- Tracker-based, same model as buffs.lua: out-of-group leeches
-- expose no buff window to MQ, so we record cast time + duration
-- per (character, HoT) and refresh before expiry.
--
-- Design:
--   * Runs on its own Heartbeat ("Hots", HotInterval ms).
--   * Healing always wins: if the heal queue is non-empty we
--     skip entirely (reactive heals take priority over the
--     proactive HoT).
--   * One HoT cast globally per pulse.
--   * Walk targets in priority order; first eligible (target,
--     HoT) pair wins.
--   * Only Type=="Spell" HoTs are castable via /cast <gem>.
--   * We never MarkFresh in TestMode (no HoT actually lands).
------------------------------------------------------------

local mq        = require('mq')
local State     = require('state')
local Scanner   = require('scanner')
local WatchList = require('watchlist')
local HealQueue = require('healqueue')
local Profiles  = require('healprofiles')
local Spells    = require('spells')
local Caster    = require('caster')

local Hots = {}

------------------------------------------------------------
-- pcall wrapper
------------------------------------------------------------

local function SafeCall(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

------------------------------------------------------------
-- Tracker helpers (keyed on lowercased name + HoT Name)
------------------------------------------------------------

local function TrackerKey(targetName, hotName)
    if not targetName or not hotName then return nil end
    return (targetName:lower()) .. "||" .. hotName
end

local function NowMs()
    return mq.gettime()
end

-- Seconds until a tracked HoT expires (<=0 means expired/none).
local function RemainingSec(targetName, hotEntry)
    local key = TrackerKey(targetName, hotEntry.Name)
    if not key then return 0 end
    local rec = State.HotTracker[key]
    if not rec then return 0 end
    local expiresAt = rec.CastAt + (rec.Duration or 0) * 1000
    return (expiresAt - NowMs()) / 1000
end

-- True when the HoT is tracked and not within the refresh
-- buffer of expiring.
function Hots.IsFresh(targetName, hotEntry)
    local remaining = RemainingSec(targetName, hotEntry)
    if remaining <= 0 then
        return false
    end
    local buffer = State.Settings.HotRefreshBuffer or 0
    return remaining > buffer
end

-- Is ANY HoT currently fresh on the target? (Avoid stacking
-- multiple HoTs when one is still rolling.)
function Hots.AnyFresh(targetName)
    local hots = Profiles.Hots()
    if type(hots) ~= "table" then return false end
    for _, hot in ipairs(hots) do
        if hot and hot.Name and Hots.IsFresh(targetName, hot) then
            return true
        end
    end
    return false
end

-- Record a fresh HoT cast. Skipped in TestMode.
function Hots.MarkFresh(targetName, hotEntry, durationSec)
    if State.Settings.TestMode then return end
    local key = TrackerKey(targetName, hotEntry.Name)
    if not key then return end
    State.HotTracker[key] = {
        CastAt    = NowMs(),
        Duration  = durationSec or (State.Settings.BuffDefaultDurationSec or 1800),
    }
end

-- Clear all tracked HoTs for a character (e.g. on death: HoTs
-- drop when the target dies).
function Hots.ClearFor(targetName)
    if not targetName or targetName == "" then return end
    local prefix = (targetName:lower()) .. "||"
    for key in pairs(State.HotTracker) do
        if key:sub(1, #prefix) == prefix then
            State.HotTracker[key] = nil
        end
    end
end

------------------------------------------------------------
-- Resolve a profile HoT entry to a memorized spell name.
--   1. exact name in the gem cache
--   2. substring match on entry.Match
------------------------------------------------------------

function Hots.Resolve(entry)
    if not entry then return nil end

    if entry.Name and Spells.Has(entry.Name) then
        return entry.Name
    end

    local match = entry.Match or entry.Name
    if match then
        local rec = Spells.FindByMatch(match)
        if rec then return rec.Name end
    end

    return nil
end

local function IsCastable(spellName)
    if not spellName then return false end
    if not Spells.Has(spellName) then return false end
    if not Spells.Ready(spellName) then return false end
    return true
end

------------------------------------------------------------
-- Target collection
--   Out-of-group leeches first (watchlist priority order),
--   then group members unless HotOnlyLeech is on.
--   Dead targets are skipped and have their tracker cleared.
------------------------------------------------------------

local function CollectTargets()
    local targets = {}

    for _, player in ipairs(WatchList.GetPlayers() or {}) do
        if player and player.Enabled ~= false then
            local rec = Scanner.FindByName(player.Name)
            if rec and rec.Name and rec.Dead then
                Hots.ClearFor(rec.Name)
            elseif rec and rec.ID and rec.ID ~= 0 then
                table.insert(targets, rec)
            end
        end
    end

    if not State.Settings.HotOnlyLeech then
        for _, rec in ipairs(Scanner.GetGroup() or {}) do
            if rec and rec.Name and rec.Dead then
                Hots.ClearFor(rec.Name)
            elseif rec and rec.ID and rec.ID ~= 0 then
                table.insert(targets, rec)
            end
        end
    end

    return targets
end

------------------------------------------------------------
-- Pick the first eligible (target, HoT) pair.
--   Skips a target when any HoT is already fresh on it (no
--   stacking). Returns target record, HoT entry, resolved name.
------------------------------------------------------------

local function PickCandidate()
    local hots = Profiles.Hots()
    if type(hots) ~= "table" then return nil end

    local targets = CollectTargets()

    for _, target in ipairs(targets) do
        -- Don't stack: if any HoT is still rolling here, move on.
        if not Hots.AnyFresh(target.Name) then
            for _, hot in ipairs(hots) do
                if hot and hot.Type == "Spell" then
                    local spellName = Hots.Resolve(hot)
                    if IsCastable(spellName)
                       and not Hots.IsFresh(target.Name, hot) then
                        return target, hot, spellName
                    end
                end
            end
        end
    end

    return nil
end

------------------------------------------------------------
-- Pulse (Heartbeat entry point)
------------------------------------------------------------

function Hots.Pulse()

    if not State.Enabled then return end
    if not State.Settings.HotRolling then return end

    -- Reactive healing always wins.
    if HealQueue.Count() > 0 then return end

    -- Mana gate.
    local manaPct = SafeCall(function() return mq.TLO.Me.PctMana() end) or 100
    if manaPct < (State.Settings.HotMinManaPct or 0) then return end

    -- Don't start a HoT mid-cast.
    local casting = SafeCall(function() return mq.TLO.Me.Casting() end)
    if casting and casting ~= "" then return end

    local target, hot, spellName = PickCandidate()
    if not target or not hot or not spellName then
        return
    end

    -- Final guard: a heal need may have appeared while picking.
    if HealQueue.Count() > 0 then return end

    local ok = Caster.Cast(spellName, target.ID, hot)

    if ok then
        local duration = Spells.Duration(spellName,
            State.Settings.HotDefaultDurationSec or 72)
        Hots.MarkFresh(target.Name, hot, duration)

        if State.Settings.Debug then
            print(string.format("[CLEPLER] HoT %s on %s for %ds",
                spellName, tostring(target.Name), duration))
        end
    end
end

------------------------------------------------------------
-- UI helper: per-target HoT status.
--   Returns array of { Name, Status, Remaining }.
------------------------------------------------------------

function Hots.HotStatusFor(targetName)
    local out = {}
    local hots = Profiles.Hots()
    if type(hots) ~= "table" then return out end

    for _, hot in ipairs(hots) do
        if hot and hot.Name then
            local remaining = RemainingSec(targetName, hot)
            local status
            if remaining > (State.Settings.HotRefreshBuffer or 0) then
                status = "fresh"
            elseif remaining > 0 then
                status = "expiring"
            elseif Hots.AnyFresh(targetName) then
                -- Another HoT is rolling here; this one is
                -- intentionally suppressed (no stacking).
                status = "covered"
            else
                status = "down"
            end
            table.insert(out, {
                Name      = hot.Name,
                Status    = status,
                Remaining = math.max(0, math.floor(remaining)),
            })
        end
    end

    return out
end

return Hots
