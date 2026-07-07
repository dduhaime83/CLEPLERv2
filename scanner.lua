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
local State = require('state')
local WatchList = require('watchlist')

local Scanner = {}

Scanner.Group = {}
Scanner.WatchMembers = {}
Scanner.All = {}
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
-- Line of sight
------------------------------------------------------------

local function SafeLOS(spawn)
    if not spawn then
        return false
    end

    local ok, value = pcall(function()
        return spawn.LineOfSight()
    end)

    if ok then
        return value == true
    end

    return false
end

------------------------------------------------------------
-- Resolve a watchlist leech to an in-zone spawn.
-- Exact PC match only; returns nil if not found/valid.
------------------------------------------------------------

local function ResolveSpawn(name)
    if not name or name == "" then
        return nil
    end

    local candidates = {
        "pc =" .. name,
        "=" .. name,
    }

    for _, query in ipairs(candidates) do
        local spawn
        local okSpawn = pcall(function()
            spawn = mq.TLO.Spawn(query)
        end)
        if okSpawn and spawn then
            -- Validate: must be a real PC with an exact
            -- (case-insensitive) name match. Use both pcall
            -- returns, not just the first.
            local okValid, matches = pcall(function()
                return spawn()
                    and spawn.Type() == "PC"
                    and (spawn.CleanName() or ""):lower() == name:lower()
            end)
            if okValid and matches then
                return spawn
            end
        end
    end

    return nil
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
        LineOfSight = SafeLOS(spawn),
        Pet = member.Pet() or false,
        Spawn = spawn,
        Watchlist = false,
        Priority = 999,
    }

    return record
end

------------------------------------------------------------
-- Build one watchlist leech record from a spawn lookup
------------------------------------------------------------

local function BuildWatchMember(name, priority)
    local spawn = ResolveSpawn(name)
    if not spawn then
        return nil
    end

    local record = {
        ID = spawn.ID() or 0,
        Name = spawn.CleanName() or name,
        Class = (spawn.Class and spawn.Class.ShortName()) or "",
        Level = spawn.Level() or 0,
        HP = SafePct(spawn),
        Aggro = SafeAggro(spawn),
        Distance = SafeDistance(spawn),
        Dead = SafeDead(spawn),
        LineOfSight = SafeLOS(spawn),
        Pet = false,
        Spawn = spawn,
        Watchlist = true,
        Priority = priority or 999,
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
-- Build watchlist leech records (out-of-group targets)
-- Skips disabled entries, self, and names already in the
-- group (dedupe by ID).
------------------------------------------------------------

local function BuildWatchMembers(seenIDs)
    Scanner.WatchMembers = {}

    if not State.Settings.HealWatchList then
        return
    end

    local meID = mq.TLO.Me.ID() or 0
    -- self is already marked seen by Scanner.Update(); nothing
    -- to do here.

    for i, player in ipairs(State.WatchList) do
        if player.Enabled and player.Name and player.Name ~= "" then
            local record = BuildWatchMember(player.Name, i)
            if record and record.ID ~= 0 and not seenIDs[record.ID] then
                seenIDs[record.ID] = true
                table.insert(Scanner.WatchMembers, record)
            end
        end
    end
end

------------------------------------------------------------
-- Lowest HP
------------------------------------------------------------

local function FindLowest()
    Scanner.LowestHP = 100
    Scanner.LowestMember = nil

    for _, member in ipairs(Scanner.All) do
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
            LineOfSight = true,
            Spawn = mq.TLO.Me,
            Watchlist = false,
            Priority = 999,
        }
    end
end

------------------------------------------------------------
-- Update group + watchlist cache
------------------------------------------------------------

function Scanner.Update()

    Scanner.Group = {}
    Scanner.WatchMembers = {}
    Scanner.All = {}

    local seenIDs = {}

    -- Exclude self from the group/watchlist lists; healqueue
    -- adds self separately. (Some MQ builds include self in
    -- Group.Member(i), so mark it seen before the loop.)
    local meID = mq.TLO.Me.ID() or 0
    if meID ~= 0 then
        seenIDs[meID] = true
    end

    local members = mq.TLO.Group.Members() or 0

    for i = 1, members do
        local record = BuildMember(i)

        if record and record.ID ~= 0 and not seenIDs[record.ID] then
            seenIDs[record.ID] = true
            table.insert(Scanner.Group, record)
        end
    end

    BuildWatchMembers(seenIDs)

    -- All = group + watchlist leeches (self excluded; healqueue
    -- adds self separately).
    for _, m in ipairs(Scanner.Group) do
        table.insert(Scanner.All, m)
    end
    for _, m in ipairs(Scanner.WatchMembers) do
        table.insert(Scanner.All, m)
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

function Scanner.GetWatchMembers()
    return Scanner.WatchMembers
end

function Scanner.GetAll()
    return Scanner.All
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
    for _, member in ipairs(Scanner.All) do
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
    local needle = (name or ""):lower()
    if needle == "" then
        return nil
    end

    for _, member in ipairs(Scanner.All) do
        if member.Name and member.Name:lower() == needle then
            return member
        end
    end

    if (mq.TLO.Me.CleanName() or ""):lower() == needle then
        return {
            ID = mq.TLO.Me.ID(),
            Name = mq.TLO.Me.CleanName(),
            HP = mq.TLO.Me.PctHPs(),
            Aggro = mq.TLO.Me.PctAggro(),
            Distance = 0,
            Dead = mq.TLO.Me.Dead(),
            LineOfSight = true,
            Spawn = mq.TLO.Me,
            Watchlist = false,
            Priority = 999,
        }
    end

    return nil
end

------------------------------------------------------------
-- Alias: init.lua registers "Scanner.Scan" as a Heartbeat
-- task. Expose Scan -> Update so both names work.
------------------------------------------------------------
Scanner.Scan = Scanner.Update

return Scanner