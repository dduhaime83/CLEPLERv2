------------------------------------------------------------
-- CLEPLER
-- buffs.lua
--
-- Level-aware buff checker / caster.
--
-- Out-of-group leeches have no buff window exposed to MQ, so
-- we can't read "is Symbol up on target X". Instead we track
-- cast time + duration per (character, buff) and refresh before
-- expiry. This is a tracker-based approximation.
--
-- Design:
--   * Runs on its own Heartbeat ("Buffs", BuffInterval ms).
--   * Healing always wins: if the heal queue is non-empty we
--     skip entirely.
--   * One buff cast globally per pulse (walk targets in priority
--     order; first eligible target/buff wins, then return).
--   * Profile order = preference order. A candidate is skipped
--     when its recipient level is below MinLevel, when a fresher
--     same-line buff of equal/higher rank is up, or when a fresh
--     buff that Supersedes this entry's Line is up.
--   * Tracker is keyed by character name (survives zoning) plus
--     the profile buff Name.
--   * We never MarkFresh in TestMode (no buff actually lands).
------------------------------------------------------------

local mq        = require('mq')
local State     = require('state')
local Scanner   = require('scanner')
local WatchList = require('watchlist')
local HealQueue = require('healqueue')
local Profiles  = require('healprofiles')
local Spells    = require('spells')
local Caster    = require('caster')

local Buffs = {}

------------------------------------------------------------
-- pcall wrapper
------------------------------------------------------------

local function SafeCall(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

------------------------------------------------------------
-- Tracker helpers (keyed on lowercased name + buff Name)
------------------------------------------------------------

local function TrackerKey(targetName, buffName)
    if not targetName or not buffName then return nil end
    return (targetName:lower()) .. "||" .. buffName
end

local function NowMs()
    return mq.gettime()
end

-- Seconds until a tracked buff expires (<=0 means expired/none).
local function RemainingSec(targetName, buffEntry)
    local key = TrackerKey(targetName, buffEntry.Name)
    if not key then return 0 end
    local rec = State.BuffTracker[key]
    if not rec then return 0 end
    local expiresAt = rec.CastAt + (rec.Duration or 0) * 1000
    return (expiresAt - NowMs()) / 1000
end

-- True when the buff is tracked and not within the refresh
-- buffer of expiring.
function Buffs.IsFresh(targetName, buffEntry)
    local remaining = RemainingSec(targetName, buffEntry)
    if remaining <= 0 then
        return false
    end
    local buffer = State.Settings.BuffRefreshBuffer or 0
    return remaining > buffer
end

-- Record a fresh cast. Skipped in TestMode (no buff lands).
function Buffs.MarkFresh(targetName, buffEntry, durationSec)
    if State.Settings.TestMode then return end
    local key = TrackerKey(targetName, buffEntry.Name)
    if not key then return end
    State.BuffTracker[key] = {
        CastAt    = NowMs(),
        Duration  = durationSec or (State.Settings.BuffDefaultDurationSec or 1800),
    }
end

------------------------------------------------------------
-- Supersede check
--   A candidate buff is superseded when, for the same target,
--   some OTHER buff is fresh AND either:
--     (a) that other buff's Supersedes list contains the
--         candidate's Line (combo suppresses lower lines), or
--     (b) it shares the candidate's Line and has equal/higher
--         Rank (higher tier of the same line wins).
------------------------------------------------------------

function Buffs.IsSuperseded(targetName, buffEntry, allBuffs)
    if not buffEntry or not buffEntry.Line then return false end

    local candLine = buffEntry.Line
    local candRank = buffEntry.Rank or 0

    for _, other in ipairs(allBuffs or {}) do
        if other and other.Name ~= buffEntry.Name and other.Line then
            if Buffs.IsFresh(targetName, other) then

                -- (a) other explicitly supersedes this line
                if other.Supersedes then
                    for _, line in ipairs(other.Supersedes) do
                        if line == candLine then
                            return true
                        end
                    end
                end

                -- (b) same line, equal-or-higher rank
                if other.Line == candLine
                   and (other.Rank or 0) >= candRank then
                    return true
                end

            end
        end
    end

    return false
end

------------------------------------------------------------
-- Resolve a profile buff entry to a memorized spell name.
--   1. exact name match in the gem cache
--   2. substring match on entry.Match (e.g. "Symbol" ->
--      "Symbol of Ryltan")
-- Returns the memorized spell name, or nil.
------------------------------------------------------------

function Buffs.Resolve(entry)
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

------------------------------------------------------------
-- Is a buff entry castable right now?
--   memorized, ready, and (if mana cost known) affordable
------------------------------------------------------------

local function IsCastable(spellName)
    if not spellName then return false end
    if not Spells.Has(spellName) then return false end
    if not Spells.Ready(spellName) then return false end
    return true
end

------------------------------------------------------------
-- Clear all tracked buffs for a character.
-- Called when a leech is dead (EQ buffs drop on death, so a
-- stale tracker entry would otherwise look fresh after rez).
------------------------------------------------------------

function Buffs.ClearFor(targetName)
    if not targetName or targetName == "" then return end
    local prefix = (targetName:lower()) .. "||"
    for key in pairs(State.BuffTracker) do
        if key:sub(1, #prefix) == prefix then
            State.BuffTracker[key] = nil
        end
    end
end

------------------------------------------------------------
-- Target collection
--   Out-of-group leeches first (watchlist priority order),
--   then group members if State.Settings.BuffGroup is on.
--   Each entry is a scanner member record with ID/Name/Level.
--   Dead targets are skipped and have their tracker cleared.
------------------------------------------------------------

local function CollectTargets()
    local targets = {}

    -- Leeches (the powerleveling focus).
    for _, player in ipairs(WatchList.GetPlayers() or {}) do
        if player and player.Enabled ~= false then
            local rec = Scanner.FindByName(player.Name)
            if rec and rec.Name and rec.Dead then
                Buffs.ClearFor(rec.Name)
            elseif rec and rec.ID and rec.ID ~= 0 then
                table.insert(targets, rec)
            end
        end
    end

    -- Optional group members.
    if State.Settings.BuffGroup then
        for _, rec in ipairs(Scanner.GetGroup() or {}) do
            if rec and rec.Name and rec.Dead then
                Buffs.ClearFor(rec.Name)
            elseif rec and rec.ID and rec.ID ~= 0 then
                table.insert(targets, rec)
            end
        end
    end

    return targets
end

------------------------------------------------------------
-- Pick the first eligible (target, buff) pair.
-- Returns target record, buff entry, resolved spell name.
------------------------------------------------------------

local function PickCandidate()
    local buffs = Profiles.Buffs()
    if type(buffs) ~= "table" then return nil end

    local targets = CollectTargets()

    for _, target in ipairs(targets) do
        for _, buff in ipairs(buffs) do

            -- AA / non-spell buffs aren't castable via /cast yet.
            if buff and buff.Type == "Spell" then

                -- Level gate (level-aware).
                local minLevel = buff.MinLevel or 1
                if (target.Level or 0) >= minLevel then

                    local spellName = Buffs.Resolve(buff)

                    if IsCastable(spellName)
                       and not Buffs.IsFresh(target.Name, buff)
                       and not Buffs.IsSuperseded(target.Name, buff, buffs) then
                        return target, buff, spellName
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

function Buffs.Pulse()

    if not State.Enabled then return end
    if not State.Settings.Buffing then return end

    -- Healing always wins. Don't start a buff while someone
    -- needs a heal.
    if HealQueue.Count() > 0 then return end

    -- Mana gate: don't buff while OOM-ish.
    local manaPct = SafeCall(function() return mq.TLO.Me.PctMana() end) or 100
    if manaPct < (State.Settings.BuffMinManaPct or 0) then return end

    -- Don't queue a buff mid-cast.
    local casting = SafeCall(function() return mq.TLO.Me.Casting() end)
    if casting and casting ~= "" then return end

    local target, buff, spellName = PickCandidate()
    if not target or not buff or not spellName then
        return
    end

    -- Final guard: re-check that no heal need appeared while we
    -- were picking. Healing takes priority over buffs.
    if HealQueue.Count() > 0 then return end

    local ok = Caster.Cast(spellName, target.ID, buff)

    if ok then
        -- Only record the buff as fresh when we actually cast it
        -- (not in TestMode, where Caster short-circuits to a dry
        -- run and no buff lands).
        local duration = Spells.Duration(spellName)
        Buffs.MarkFresh(target.Name, buff, duration)

        if State.Settings.Debug then
            print(string.format("[CLEPLER] buff %s on %s (lvl %d) for %ds",
                spellName, tostring(target.Name),
                tonumber(target.Level) or 0, duration))
        end
    end
end

------------------------------------------------------------
-- UI helper: per-target buff status.
--   Returns an array of { Name, Status, Remaining } where
--   Status is "fresh", "expiring", "missing".
--   `allBuffs` optional; defaults to the active profile.
------------------------------------------------------------

function Buffs.BuffStatusFor(targetName, allBuffs)
    local out = {}
    local buffs = allBuffs or Profiles.Buffs()
    if type(buffs) ~= "table" then return out end

    local target = Scanner.FindByName(targetName)
    local level  = target and target.Level or nil

    for _, buff in ipairs(buffs) do
        if buff and buff.Name then
            local remaining = RemainingSec(targetName, buff)
            local status

            if level and level < (buff.MinLevel or 1) then
                status = "low"
            elseif remaining > (State.Settings.BuffRefreshBuffer or 0) then
                status = "fresh"
            elseif remaining > 0 then
                status = "expiring"
            elseif Buffs.IsSuperseded(targetName, buff, buffs) then
                status = "covered"
            else
                status = "missing"
            end

            table.insert(out, {
                Name      = buff.Name,
                Status    = status,
                Remaining = math.max(0, math.floor(remaining)),
            })
        end
    end

    return out
end

return Buffs
