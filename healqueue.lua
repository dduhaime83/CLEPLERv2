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

local HealQueue = {}

HealQueue.Queue = {}
HealQueue.LastBuild = 0

------------------------------------------------------------
-- Priority Weights
------------------------------------------------------------

local PRIORITY = {
    SELF_EMERGENCY = 1000,
    TANK_EMERGENCY = 950,
    PLAYER_EMERGENCY = 900,

    SELF = 800,
    MAIN_TANK = 700,
    GROUP = 600,

    LIGHT = 100,
}

------------------------------------------------------------
-- Internal
------------------------------------------------------------

local function Insert(entry)
    table.insert(HealQueue.Queue, entry)
end

------------------------------------------------------------
-- Queue member
------------------------------------------------------------

local function Evaluate(member, scanner)

    if not member then
        return
    end

    if member.Dead then
        return
    end

    local hp = member.HP or 100

    local priority = nil

    --------------------------------------------------------

    if member.Name == mq.TLO.Me.CleanName() then

        if hp <= 20 then
            priority = PRIORITY.SELF_EMERGENCY
        elseif hp <= 60 then
            priority = PRIORITY.SELF
        end

    elseif scanner.GetMainTank()
        and member.Name == scanner.GetMainTank() then

        if hp <= 25 then
            priority = PRIORITY.TANK_EMERGENCY
        elseif hp <= 70 then
            priority = PRIORITY.MAIN_TANK
        end

    else

        if hp <= 20 then
            priority = PRIORITY.PLAYER_EMERGENCY
        elseif hp <= 75 then
            priority = PRIORITY.GROUP
        elseif hp <= 90 then
            priority = PRIORITY.LIGHT
        end

    end

    --------------------------------------------------------

    if priority then

        Insert({
            Name = member.Name,
            ID = member.ID,
            HP = hp,
            Aggro = member.Aggro or 0,
            Distance = member.Distance or 9999,
            Priority = priority - hp,
            Record = member,
        })

    end
end

------------------------------------------------------------
-- Sort queue
------------------------------------------------------------

local function Sort()

    table.sort(HealQueue.Queue, function(a, b)

        if a.Priority == b.Priority then
            return a.HP < b.HP
        end

        return a.Priority > b.Priority

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

    local members = scanner.GetGroup()

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

    return HealQueue.Queue[1].Priority
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

    for i, entry in ipairs(HealQueue.Queue) do
        printf(
            "%d %-18s HP:%3d Priority:%4d",
            i,
            entry.Name,
            entry.HP,
            entry.Priority
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