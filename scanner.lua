--========================================================--
-- scanner.lua
--
-- CLEPLER
-- Fast group/raid scanning module.
--
-- Responsibilities:
--   * Maintain cached observations
--   * Detect HP changes
--   * Detect aggro
--   * Detect deaths
--   * Determine assist target
--   * Expose snapshot to healer logic
--
-- No spell casting occurs here.
--========================================================--

local mq = require('mq')

local Scanner = {}

Scanner.Group = {}
Scanner.MainTank = nil
Scanner.AssistTarget = nil
Scanner.LowestMember = nil
Scanner.LowestHP = 100
Scanner.GroupInCombat = false
Scanner.LastUpdate = 0

------------------------------------------------------------
-- Internal helper
------------------------------------------------------------

local function SafePct(spawn)
    if not spawn then
        return 0
    end

    local ok, value = pcall(function()
        return spawn.PctHPs() or 0
    end)

    if ok then
        return value
    end

    return 0
end

local function SafeAggro(spawn)
    if not spawn then
        return 0
    end

    local ok, value = pcall(function()
        return spawn.PctAggro() or 0
    end)

    if ok then
        return value
    end

    return 0
end

local function SafeDistance(spawn)
    if not spawn then
        return 9999
    end

    local ok, value = pcall(function()
        return spawn.Distance() or 9999
    end)

    if ok then
        return value
    end

    return 9999
end

local function SafeDead(spawn)
    if not spawn then
        return true
    end

    local ok, value = pcall(function()
        return spawn.Dead() or false
    end)

    if ok then
        return value
    end

    return true
end

------------------------------------------------------------
-- Build one member record
------------------------------------------------------------

local function BuildMember(index)
    local member = mq.TLO.Group.Member(index)

    if not member() then
        return nil
    end

    local spawn = member.Spawn()

    if not spawn then
        return nil
    end

    local record = {
        ID = spawn.ID() or 0,
        Name = spawn.CleanName() or "",
        Class = spawn.Class.ShortName() or "",
        Level = spawn.Level() or 0,
        HP = SafePct(spawn),
        Aggro = SafeAggro(spawn),
        Distance = SafeDistance(spawn),
        Dead = SafeDead(spawn),
        Pet = member.Pet() or false,
        Spawn = spawn,
    }

    return record
end

------------------------------------------------------------
-- Main Tank detection
------------------------------------------------------------

local function DetectMainTank()
    local tank = mq.TLO.Group.MainTank()

    if tank and tank() then
        Scanner.MainTank = tank.CleanName()
        return
    end

    Scanner.MainTank = nil
end

------------------------------------------------------------
-- Assist target
------------------------------------------------------------

local function DetectAssist()
    local assist = mq.TLO.Group.MainAssist()

    if assist and assist() then
        local spawn = assist.Target()

        if spawn and spawn() then
            Scanner.AssistTarget = spawn.ID()
            return
        end
    end

    local target = mq.TLO.Target

    if target() then
        if target.Type() == "NPC" then
            Scanner.AssistTarget = target.ID()
            return
        end
    end

    Scanner.AssistTarget = nil
end

------------------------------------------------------------
-- Combat detection
------------------------------------------------------------

local function DetectCombat()
    Scanner.GroupInCombat = false

    local xt = mq.TLO.XTarget

    if xt() and xt() > 0 then
        Scanner.GroupInCombat = true
        return
    end

    if mq.TLO.Me.CombatState() == "COMBAT" then
        Scanner.GroupInCombat = true
        return
    end
end

------------------------------------------------------------
-- Lowest HP
------------------------------------------------------------

local function FindLowest()
    Scanner.LowestHP = 100
    Scanner.LowestMember = nil

    for _, member in ipairs(Scanner.Group) do
        if not member.Dead then
            if member.HP < Scanner.LowestHP then
                Scanner.LowestHP = member.HP
                Scanner.LowestMember = member
            end
        end
    end

    local meHP = mq.TLO.Me.PctHPs()

    if meHP < Scanner.LowestHP then
        Scanner.LowestHP = meHP

        Scanner.LowestMember = {
            ID = mq.TLO.Me.ID(),
            Name = mq.TLO.Me.CleanName(),
            HP = meHP,
            Aggro = mq.TLO.Me.PctAggro(),
            Distance = 0,
            Dead = mq.TLO.Me.Dead(),
            Spawn = mq.TLO.Me,
        }
    end
end

------------------------------------------------------------
-- Update group cache
------------------------------------------------------------

function Scanner.Update()

    Scanner.Group = {}

    local members = mq.TLO.Group.Members() or 0

    for i = 1, members do
        local record = BuildMember(i)

        if record then
            table.insert(Scanner.Group, record)
        end
    end

    DetectMainTank()
    DetectAssist()
    DetectCombat()
    FindLowest()

    Scanner.LastUpdate = mq.gettime()
end

------------------------------------------------------------
-- Public Queries
------------------------------------------------------------

function Scanner.GetLowest()
    return Scanner.LowestMember
end

function Scanner.GetGroup()
    return Scanner.Group
end

function Scanner.GetMainTank()
    return Scanner.MainTank
end

function Scanner.GetAssistTarget()
    return Scanner.AssistTarget
end

function Scanner.InCombat()
    return Scanner.GroupInCombat
end

function Scanner.MemberCount()
    return #Scanner.Group
end

function Scanner.AnyoneBelow(percent)
    for _, member in ipairs(Scanner.Group) do
        if not member.Dead and member.HP <= percent then
            return true
        end
    end

    local meHP = mq.TLO.Me.PctHPs()

    if meHP <= percent then
        return true
    end

    return false
end

function Scanner.FindByName(name)
    for _, member in ipairs(Scanner.Group) do
        if member.Name == name then
            return member
        end
    end

    if mq.TLO.Me.CleanName() == name then
        return {
            ID = mq.TLO.Me.ID(),
            Name = mq.TLO.Me.CleanName(),
            HP = mq.TLO.Me.PctHPs(),
            Aggro = mq.TLO.Me.PctAggro(),
            Distance = 0,
            Dead = mq.TLO.Me.Dead(),
            Spawn = mq.TLO.Me,
        }
    end

    return nil
end

return Scanner