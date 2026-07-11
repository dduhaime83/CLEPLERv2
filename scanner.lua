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
-- pcall wrapper for TLO reads that may be absent in some
-- MQ builds (e.g. XTarget).
------------------------------------------------------------

local function SafeCall(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

------------------------------------------------------------
-- Identity/field readers. In VeryVanilla MQ, an accessor
-- like member.Spawn() can return a non-nil wrapper whose
-- fields (.ID, .CleanName, .Level, .Class.ShortName) are nil
-- for spawns that are zoning, out of range, or otherwise
-- momentarily unresolvable. Calling .ID() on such a wrapper
-- crashes with "attempt to call field 'ID' (a nil value)".
-- Wrap every field read in pcall so the heartbeat can't die.
------------------------------------------------------------

local function SafeID(spawn)
    if not spawn then
        return 0
    end

    local ok, value = pcall(function()
        return spawn.ID() or 0
    end)

    if ok then
        return tonumber(value) or 0
    end

    return 0
end

local function SafeName(spawn, fallback)
    fallback = fallback or ""

    if not spawn then
        return fallback
    end

    local ok, value = pcall(function()
        return spawn.CleanName()
    end)

    if ok and value then
        return value
    end

    return fallback
end

local function SafeClass(spawn)
    if not spawn then
        return ""
    end

    local ok, value = pcall(function()
        return spawn.Class.ShortName()
    end)

    if ok and value then
        return value
    end

    return ""
end

local function SafeLevel(spawn)
    if not spawn then
        return 0
    end

    local ok, value = pcall(function()
        return spawn.Level() or 0
    end)

    if ok then
        return tonumber(value) or 0
    end

    return 0
end

local function SafePet(member)
    if not member then
        return false
    end

    local ok, value = pcall(function()
        return member.Pet() or false
    end)

    if ok then
        return value or false
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
        ID = SafeID(spawn),
        Name = SafeName(spawn, ""),
        Class = SafeClass(spawn),
        Level = SafeLevel(spawn),
        HP = SafePct(spawn),
        Aggro = SafeAggro(spawn),
        Distance = SafeDistance(spawn),
        Dead = SafeDead(spawn),
        LineOfSight = SafeLOS(spawn),
        Pet = SafePet(member),
        Spawn = spawn,
        Watchlist = false,
        Priority = 999,
    }

    return record
end

------------------------------------------------------------
-- Build one watchlist leech record from a spawn lookup
------------------------------------------------------------

local function BuildWatchMember(name, priority, healBelowPct)
    local spawn = ResolveSpawn(name)
    if not spawn then
        return nil
    end

    local record = {
        ID = SafeID(spawn),
        Name = SafeName(spawn, name),
        Class = SafeClass(spawn),
        Level = SafeLevel(spawn),
        HP = SafePct(spawn),
        Aggro = SafeAggro(spawn),
        Distance = SafeDistance(spawn),
        Dead = SafeDead(spawn),
        LineOfSight = SafeLOS(spawn),
        Pet = false,
        Spawn = spawn,
        Watchlist = true,
        Priority = priority or 999,
        HealBelowPct = tonumber(healBelowPct) or 0,
    }

    return record
end

------------------------------------------------------------
-- Main Tank detection
------------------------------------------------------------

local function DetectMainTank()
    local tank = mq.TLO.Group.MainTank()

    if tank and tank() then
        Scanner.MainTank = SafeName(tank, nil)
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
        local spawn = SafeCall(function()
            return assist.Target()
        end)

        if spawn and SafeCall(function() return spawn() end) then
            local id = SafeID(spawn)
            if id ~= 0 then
                Scanner.AssistTarget = id
                return
            end
        end
    end

    local target = mq.TLO.Target

    local isNPC = SafeCall(function()
        return target() and target.Type() == "NPC"
    end)

    if isNPC then
        local id = SafeID(target)
        if id ~= 0 then
            Scanner.AssistTarget = id
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

    -- Some MQ Lua builds expose XTarget differently, or not at
    -- all (VeryVanilla returns nil for mq.TLO.XTarget as a
    -- table reference). Treat it as optional and never let it
    -- break the scanner heartbeat.
    local xtCount = SafeCall(function()
        if mq.TLO.XTarget then
            return mq.TLO.XTarget()
        end
        return nil
    end)

    if not xtCount then
        xtCount = SafeCall(function()
            if mq.TLO.Me and mq.TLO.Me.XTarget then
                return mq.TLO.Me.XTarget()
            end
            return nil
        end)
    end

    xtCount = tonumber(xtCount) or 0
    if xtCount > 0 then
        Scanner.GroupInCombat = true
        return
    end

    local combatState = SafeCall(function()
        return mq.TLO.Me.CombatState()
    end)

    if combatState == "COMBAT" then
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

    local meID = SafeID(mq.TLO.Me)
    -- self is already marked seen by Scanner.Update(); nothing
    -- to do here.

    for i, player in ipairs(State.WatchList) do
        if player.Enabled and player.Name and player.Name ~= "" then
            local record = BuildWatchMember(player.Name, i, player.HealBelowPct)
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

    local meHP = SafePct(mq.TLO.Me)

    if meHP < Scanner.LowestHP then
        Scanner.LowestHP = meHP

        Scanner.LowestMember = {
            ID = SafeID(mq.TLO.Me),
            Name = SafeName(mq.TLO.Me, ""),
            HP = meHP,
            Aggro = SafeAggro(mq.TLO.Me),
            Distance = 0,
            Dead = SafeDead(mq.TLO.Me),
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
    local meID = SafeID(mq.TLO.Me)
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

    local meHP = SafePct(mq.TLO.Me)

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

    if SafeName(mq.TLO.Me, ""):lower() == needle then
        return {
            ID = SafeID(mq.TLO.Me),
            Name = SafeName(mq.TLO.Me, ""),
            HP = SafePct(mq.TLO.Me),
            Aggro = SafeAggro(mq.TLO.Me),
            Distance = 0,
            Dead = SafeDead(mq.TLO.Me),
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