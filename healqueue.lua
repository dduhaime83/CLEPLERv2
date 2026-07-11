--========================================================--
-- healqueue.lua
--
-- CLEPLER
-- Heal request prioritization engine.
--
-- Responsibilities:
--   * Maintain a prioritized healing queue
--   * Select the best heal target
--   * Track emergency targets
--   * Prevent duplicate queue entries
--   * Keep healing decisions separate from casting
--
-- No spell casting occurs here.
--========================================================--

local mq = require('mq')
local State = require('state')

local HealQueue = {}

HealQueue.Queue = {}
HealQueue.LastBuild = 0

------------------------------------------------------------
-- Priority tiers (higher = healed first)
--
-- Powerlevel model: the out-of-group leech is the primary
-- focus. Only the PLer's own critical survival outranks a
-- leech (a dead PLer heals no one). Group members are last.
------------------------------------------------------------

local PRIORITY = {
    SELF_EMERGENCY   = 1000,
    LEECH_EMERGENCY  = 900,
    LEECH            = 800,
    SELF             = 700,
    GROUP_EMERGENCY  = 600,
    GROUP            = 500,
}

-- Emergency HP threshold for triage tiering (independent of
-- the per-spell FastHealPct used by the healer).
local EMERGENCY_HP = 35

-- Default "heal below this HP%" for leeches that don't set a
-- per-leech threshold (HealBelowPct == 0 means inherit this).
local DEFAULT_LEECH_HEAL_BELOW = 75

------------------------------------------------------------
-- Internal
------------------------------------------------------------

local function Insert(entry)
    table.insert(HealQueue.Queue, entry)
end

------------------------------------------------------------
-- Queue member
--
-- Stores tier + watchlist priority + HP for a correct
-- multi-field sort (see Sort()).
------------------------------------------------------------

local function Evaluate(member, scanner)

    if not member then
        return
    end

    if member.Dead then
        return
    end

    -- Never queue an unresolvable spawn: id <= 0 can't be
    -- targeted or cast on (0 is truthy in Lua, so guard numerically).
    if (tonumber(member.ID) or 0) <= 0 then
        return
    end

    local hp = member.HP or 100
    local isSelf = (member.ID == mq.TLO.Me.ID())
    local isLeech = member.Watchlist == true

    --------------------------------------------------------
    -- Range / LOS gating: skip unreachable targets so they
    -- don't starve reachable ones. (Self is always reachable.)
    --------------------------------------------------------
    if not isSelf then
        if not State.Settings.IgnoreRange
            and member.Distance
            and member.Distance > State.Settings.MaxHealRange then
            return
        end

        if not State.Settings.IgnoreLOS
            and member.LineOfSight == false then
            return
        end
    end

    --------------------------------------------------------
    -- Tier assignment
    --------------------------------------------------------
    local tier

    if isSelf then
        if hp <= 20 then
            tier = PRIORITY.SELF_EMERGENCY
        elseif hp <= 60 then
            tier = PRIORITY.SELF
        else
            return          -- self is healthy; nothing to do
        end

    elseif isLeech then
        -- Per-leech "heal below" threshold (0 = inherit the
        -- global default). Emergency triage stays global so any
        -- enabled leech is protected at EMERGENCY_HP regardless
        -- of its custom threshold.
        local healBelow = tonumber(member.HealBelowPct) or 0
        if healBelow <= 0 then
            healBelow = DEFAULT_LEECH_HEAL_BELOW
        end
        if healBelow > 100 then healBelow = 100 end

        if hp <= EMERGENCY_HP then
            tier = PRIORITY.LEECH_EMERGENCY
        elseif hp <= healBelow then
            tier = PRIORITY.LEECH
        else
            return
        end

    else
        -- Group member (secondary in a PL)
        if hp <= 20 then
            tier = PRIORITY.GROUP_EMERGENCY
        elseif hp <= 75 then
            tier = PRIORITY.GROUP
        else
            return
        end
    end

    Insert({
        Name = member.Name,
        ID = member.ID,
        HP = hp,
        Aggro = member.Aggro or 0,
        Distance = member.Distance or 9999,
        LineOfSight = member.LineOfSight,
        Watchlist = isLeech,
        WatchPriority = member.Priority or 999,
        Tier = tier,
        Record = member,
    })
end

------------------------------------------------------------
-- Sort queue
--
-- Emergency leeches: HP first, then watchlist priority.
-- Everyone else: watchlist priority first, then HP.
------------------------------------------------------------

local function Sort()

    table.sort(HealQueue.Queue, function(a, b)

        if a.Tier ~= b.Tier then
            return a.Tier > b.Tier
        end

        if a.Tier == PRIORITY.LEECH_EMERGENCY then
            if a.HP ~= b.HP then
                return a.HP < b.HP
            end
            return (a.WatchPriority or 999) < (b.WatchPriority or 999)
        end

        if (a.WatchPriority or 999) ~= (b.WatchPriority or 999) then
            return (a.WatchPriority or 999) < (b.WatchPriority or 999)
        end

        return a.HP < b.HP

    end)

end

------------------------------------------------------------
-- Build queue
------------------------------------------------------------

function HealQueue.Build(scanner)

    HealQueue.Queue = {}

    if not scanner then
        return
    end

    -- Prefer the merged list (group + watchlist leeches);
    -- fall back to group-only for older scanner builds.
    local members = scanner.GetAll and scanner.GetAll() or scanner.GetGroup() or {}

    for _, member in ipairs(members) do
        Evaluate(member, scanner)
    end

    --------------------------------------------------------
    -- Evaluate self separately
    --------------------------------------------------------

    local me = {
        ID = mq.TLO.Me.ID(),
        Name = mq.TLO.Me.CleanName(),
        HP = mq.TLO.Me.PctHPs(),
        Aggro = mq.TLO.Me.PctAggro(),
        Distance = 0,
        Dead = mq.TLO.Me.Dead(),
        LineOfSight = true,
        Watchlist = false,
        Priority = 999,
    }

    Evaluate(me, scanner)

    Sort()

    HealQueue.LastBuild = mq.gettime()
end

------------------------------------------------------------
-- Queue size
------------------------------------------------------------

function HealQueue.Count()
    return #HealQueue.Queue
end

------------------------------------------------------------
-- Next target
------------------------------------------------------------

function HealQueue.Next()

    if #HealQueue.Queue == 0 then
        return nil
    end

    return HealQueue.Queue[1]
end

------------------------------------------------------------
-- Pop target
------------------------------------------------------------

function HealQueue.Pop()

    if #HealQueue.Queue == 0 then
        return nil
    end

    return table.remove(HealQueue.Queue, 1)
end

------------------------------------------------------------
-- Peek
------------------------------------------------------------

function HealQueue.Peek(index)

    index = index or 1

    return HealQueue.Queue[index]
end

------------------------------------------------------------
-- Empty?
------------------------------------------------------------

function HealQueue.Empty()

    return #HealQueue.Queue == 0
end

------------------------------------------------------------
-- Find by name
------------------------------------------------------------

function HealQueue.Find(name)

    for _, entry in ipairs(HealQueue.Queue) do
        if entry.Name == name then
            return entry
        end
    end

    return nil
end

------------------------------------------------------------
-- Highest priority value
------------------------------------------------------------

function HealQueue.Priority()

    if HealQueue.Empty() then
        return 0
    end

    return HealQueue.Queue[1].Tier
end

------------------------------------------------------------
-- Lowest HP currently queued
------------------------------------------------------------

function HealQueue.LowestHP()

    if HealQueue.Empty() then
        return 100
    end

    return HealQueue.Queue[1].HP
end

------------------------------------------------------------
-- Debug dump
------------------------------------------------------------

function HealQueue.Debug()

    local tierName = {
        [PRIORITY.SELF_EMERGENCY]  = "SELF_EMERGENCY",
        [PRIORITY.LEECH_EMERGENCY] = "LEECH_EMERGENCY",
        [PRIORITY.LEECH]           = "LEECH",
        [PRIORITY.SELF]            = "SELF",
        [PRIORITY.GROUP_EMERGENCY] = "GROUP_EMERGENCY",
        [PRIORITY.GROUP]           = "GROUP",
    }

    for i, entry in ipairs(HealQueue.Queue) do
        printf(
            "%d %-18s HP:%3d Tier:%-16s WP:%d",
            i,
            entry.Name,
            entry.HP,
            tierName[entry.Tier] or tostring(entry.Tier),
            entry.WatchPriority or 0
        )
    end

end

------------------------------------------------------------
-- Clear
------------------------------------------------------------

function HealQueue.Clear()

    HealQueue.Queue = {}

end

return HealQueue