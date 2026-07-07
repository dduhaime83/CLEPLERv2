------------------------------------------------------------
-- CLEPLER
-- watchlist.lua
--
-- Ordered roster of out-of-group leeches (the primary heal
-- focus). Array index == heal priority (1 = highest).
-- Reordering the array reorders priority.
--
-- Persisted to CLEPLER_WatchList.ini as Player1..N in array
-- order, so INI order == priority.
------------------------------------------------------------

local mq    = require('mq')
local State = require('state')

local WatchList = {}

WatchList.File    = mq.configDir .. "\\CLEPLER_WatchList.ini"
WatchList.Section = "Players"

------------------------------------------------------------
-- Record factory
------------------------------------------------------------

local function NewPlayer(name)
    return { Name = name, Enabled = true, Priority = 1, HealBelowPct = 0 }
end

------------------------------------------------------------
-- Clamp a percent to 0..100 (integer). 0 means "inherit the
-- global default leech heal threshold".
------------------------------------------------------------

local function ClampPct(v)
    v = tonumber(v) or 0
    if v < 0 then v = 0 end
    if v > 100 then v = 100 end
    return math.floor(v)
end

------------------------------------------------------------
-- Normalize: ensure each entry's Priority matches its index
------------------------------------------------------------

function WatchList.Normalize()
    for i, p in ipairs(State.WatchList) do
        p.Priority = i
    end
end

------------------------------------------------------------
-- Lookup
------------------------------------------------------------

local function FindIndex(name)
    if not name then return nil end
    for i, p in ipairs(State.WatchList) do
        if p.Name and p.Name:lower() == name:lower() then
            return i
        end
    end
    return nil
end

------------------------------------------------------------
-- INI read helper
------------------------------------------------------------

local function Read(key, default)
    local value = mq.TLO.Ini(WatchList.File, WatchList.Section, key)()
    if value == nil or value == "" then
        return default
    end
    return value
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------

function WatchList.GetPlayers()
    return State.WatchList
end

function WatchList.Count()
    return #State.WatchList
end

function WatchList.Add(name)
    if not name or name == "" then return false end
    if FindIndex(name) then return false end          -- dedupe
    table.insert(State.WatchList, NewPlayer(name))
    WatchList.Normalize()
    return true
end

function WatchList.Remove(name)
    local idx = FindIndex(name)
    if not idx then return false end
    table.remove(State.WatchList, idx)
    WatchList.Normalize()
    return true
end

function WatchList.RemoveAt(index)
    if index < 1 or index > #State.WatchList then return false end
    table.remove(State.WatchList, index)
    WatchList.Normalize()
    return true
end

-- Move entry at `from` to `to`, shifting others.
function WatchList.Move(from, to)
    local n = #State.WatchList
    if from < 1 or from > n then return false end
    if to < 1 then to = 1 end
    if to > n then to = n end
    if from == to then return false end

    local entry = table.remove(State.WatchList, from)
    table.insert(State.WatchList, to, entry)
    WatchList.Normalize()
    return true
end

function WatchList.MoveUp(index)
    return WatchList.Move(index, index - 1)
end

function WatchList.MoveDown(index)
    return WatchList.Move(index, index + 1)
end

function WatchList.SetEnabled(name, enabled)
    local idx = FindIndex(name)
    if not idx then return false end
    State.WatchList[idx].Enabled = enabled and true or false
    return true
end

-- Set the per-leech "heal below this HP%" threshold. 0 = inherit
-- the global default. Index-based because the UI row has i and
-- duplicate names are disallowed.
function WatchList.SetHealBelowPct(index, pct)
    if index < 1 or index > #State.WatchList then return false end
    State.WatchList[index].HealBelowPct = ClampPct(pct)
    return true
end

function WatchList.ToggleEnabled(index)
    if index < 1 or index > #State.WatchList then return false end
    State.WatchList[index].Enabled = not State.WatchList[index].Enabled
    return true
end

------------------------------------------------------------
-- Persistence (order == priority)
------------------------------------------------------------

function WatchList.Load()
    State.WatchList = {}

    local count = tonumber(Read("Count", "0")) or 0

    for i = 1, count do
        local name = Read("Player" .. i, "")
        if name and name ~= "" then
            local en = Read("Player" .. i .. "Enabled", "true")
            local hb = Read("Player" .. i .. "HealBelowPct", "0")
            local player = NewPlayer(name)
            player.Enabled = (en:lower() == "true")
            player.HealBelowPct = ClampPct(hb)
            table.insert(State.WatchList, player)
        end
    end

    WatchList.Normalize()

    print(string.format("[CLEPLER] watchlist loaded: %d entries", #State.WatchList))
end

function WatchList.Save()

    mq.cmdf('/ini "%s" "%s" "%s" "%s"',
        WatchList.File, WatchList.Section, "Count", #State.WatchList)

    for i, player in ipairs(State.WatchList) do
        mq.cmdf('/ini "%s" "%s" "%s" "%s"',
            WatchList.File, WatchList.Section, "Player" .. i, player.Name or "")
        mq.cmdf('/ini "%s" "%s" "%s" "%s"',
            WatchList.File, WatchList.Section, "Player" .. i .. "Enabled",
            tostring(player.Enabled))
        mq.cmdf('/ini "%s" "%s" "%s" "%s"',
            WatchList.File, WatchList.Section, "Player" .. i .. "HealBelowPct",
            tostring(player.HealBelowPct or 0))
    end
end

return WatchList
