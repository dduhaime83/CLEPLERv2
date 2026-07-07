------------------------------------------------------------
-- CLEPLER
--
-- config.lua
------------------------------------------------------------

local mq = require('mq')
local State = require('state')

local Config = {}

Config.File = mq.configDir .. "\\CLEPLER.ini"

local function Read(key, default)
    local value = mq.TLO.Ini(Config.File, "Settings", key)()

    if value == nil or value == "" then
        return default
    end

    if type(default) == "boolean" then
        return value:lower() == "true"
    end

    if type(default) == "number" then
        return tonumber(value) or default
    end

    return value
end

local function Write(key, value)
    mq.cmdf('/ini "%s" "Settings" "%s" "%s"',
        Config.File, key, tostring(value))
end

function Config.Load()
    for key, default in pairs(State.Settings) do
        State.Settings[key] = Read(key, default)
    end
end

function Config.Save()
    for key, value in pairs(State.Settings) do
        Write(key, value)
    end
end

function Config.Reset()
    State.Settings = {
        ScanDelay = 100,
        ReturnTarget = true,
        AnnounceHeals = true,
        IgnoreLOS = false,
        IgnoreRange = false,
        TestMode = true,
        UseFastHeal = true,
        FastHealPct = 30,
        UseBigHeal = true,
        BigHealPct = 65,
        UseCompleteHeal = true,
        CompleteHealPct = 40,
        UseHoT = false,
        HoTPct = 85,
        HealWatchList = true,
        MaxHealRange = 200,
        Buffing = true,
        BuffInterval = 2000,
        BuffRefreshBuffer = 120,
        BuffGroup = false,
        BuffMinManaPct = 20,
        BuffDefaultDurationSec = 1800,
        Debug = false,
    }

    Config.Save()
end

function Config.Initialize()
    Config.Load()
    Config.Save()
end

return Config
