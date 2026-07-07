------------------------------------------------------------
-- CLEPLER
-- watchlist.lua
--
-- Named leech roster with INI persistence.
--
-- NOTE (v1): Healing currently targets the group only. The
-- watchlist is loaded/saved and editable via /clepler add &
-- remove, but is NOT yet merged into the scanner. Wiring
-- watchlist names into Scanner + HealQueue is the next step.
------------------------------------------------------------

local mq    = require('mq')
local State = require('state')

local WatchList = {}

WatchList.File    = mq.configDir .. "\\CLEPLER_WatchList.ini"
WatchList.Section = "Players"

------------------------------------------------------------
-- Record factory (persisted fields only: Name, Enabled)
------------------------------------------------------------

local function NewPlayer(name)
    return { Name = name, Enabled = true }
end

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

function WatchList.Add(name)
    if not name or name == "" then return false end
    if FindIndex(name) then return false end          -- dedupe
    table.insert(State.WatchList, NewPlayer(name))
    return true
end

function WatchList.Remove(name)
    local idx = FindIndex(name)
    if not idx then return false end
    table.remove(State.WatchList, idx)
    return true
end

function WatchList.SetEnabled(name, enabled)
    local idx = FindIndex(name)
    if not idx then return false end
    State.WatchList[idx].Enabled = enabled and true or false
    return true
end

------------------------------------------------------------
-- Persistence
------------------------------------------------------------

function WatchList.Load()
    State.WatchList = {}

    local count = tonumber(Read("Count", "0")) or 0

    for i = 1, count do
        local name = Read("Player" .. i, "")
        if name and name ~= "" then
            local en = Read("Player" .. i .. "Enabled", "true")
            local player = NewPlayer(name)
            player.Enabled = (en:lower() == "true")
            table.insert(State.WatchList, player)
        end
    end

    print(string.format("[CLEPLER] watchlist loaded: %d entries", #State.WatchList))
end

function WatchList.Save()

    -- Clear the section by writing a fresh Count first.
    mq.cmdf('/ini "%s" "%s" "%s" "%s"',
        WatchList.File, WatchList.Section, "Count", #State.WatchList)

    for i, player in ipairs(State.WatchList) do
        mq.cmdf('/ini "%s" "%s" "%s" "%s"',
            WatchList.File, WatchList.Section, "Player" .. i, player.Name or "")
        mq.cmdf('/ini "%s" "%s" "%s" "%s"',
            WatchList.File, WatchList.Section, "Player" .. i .. "Enabled",
            tostring(player.Enabled))
    end
end

return WatchList
