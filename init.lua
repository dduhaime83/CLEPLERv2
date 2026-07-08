------------------------------------------------------------
-- CLEPLER
-- init.lua
------------------------------------------------------------
local mq=require('mq')

local State=require('state')
local Config=require('config')
local Heartbeat=require('heartbeat')
local Commands=require('commands')
local WatchList=require('watchlist')
local Scanner=require('scanner')
local Spells=require('spells')
local Engine=require('engine')
local Healer=require('healer')
local Buffs=require('buffs')
local Hots=require('hots')
local Med=require('med')
local Follow=require('follow')
local Spellbook=require('spellbook')
local Loadout=require('loadout')
local Remote=require('remote')
local UI=require('ui')

Config.Initialize()
WatchList.Load()
Loadout.Load()
Spells.Refresh()
Spellbook.Refresh()
Commands.Register()

-- Capture the effective role at startup. Runtime branching reads
-- this, not the live setting, so role changes only take full
-- effect after a reload.
State.RemoteEffectiveRole = State.Settings.RemoteRole or "off"

-- Viewer toons are the leech being driven -- they must NOT run
-- any healing/buff/follow logic (they have no cleric spells).
-- Source/off toons run the full CLEPLER pipeline.
local isViewer = (State.RemoteEffectiveRole == "viewer")

if not isViewer then
    Heartbeat.Register("Scanner",State.Settings.ScanDelay,Scanner.Scan)
    Heartbeat.Register("Engine",100,Engine.Pulse)
    Heartbeat.Register("Healer",25,Healer.Pulse)
    Heartbeat.Register("Hots",State.Settings.HotInterval,Hots.Pulse)
    Heartbeat.Register("Med",1000,Med.Pulse)
    Heartbeat.Register("Follow",1000,Follow.Pulse)
    Heartbeat.Register("Buffs",State.Settings.BuffInterval,Buffs.Pulse)
else
    -- Seed the viewer's applied-ack so pending logic is sane.
    print("[CLEPLER] running as REMOTE VIEWER (no local healing)")
end

mq.imgui.init("CLEPLER",UI.Draw)

State.Running=true
print("[CLEPLER] v"..State.Version.." Loaded")

while State.Running do
    mq.doevents()
    -- Loadout + Remote pulse unconditionally (outside the paused
    -- heartbeat) so gem-mem and cross-toon status/commands still
    -- progress while healing is paused.
    Loadout.Pulse()
    Remote.Pulse()
    if not isViewer and not State.Paused then
        Heartbeat.Pulse()
    end
    mq.delay(10)
end

Commands.Unregister()
Config.Save()
WatchList.Save()
