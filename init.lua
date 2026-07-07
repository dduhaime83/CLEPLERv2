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
local UI=require('ui')

Config.Initialize()
WatchList.Load()
Loadout.Load()
Spells.Refresh()
Spellbook.Refresh()
Commands.Register()

Heartbeat.Register("Scanner",State.Settings.ScanDelay,Scanner.Scan)
Heartbeat.Register("Engine",100,Engine.Pulse)
Heartbeat.Register("Healer",25,Healer.Pulse)
Heartbeat.Register("Hots",State.Settings.HotInterval,Hots.Pulse)
Heartbeat.Register("Med",1000,Med.Pulse)
Heartbeat.Register("Follow",1000,Follow.Pulse)
Heartbeat.Register("Buffs",State.Settings.BuffInterval,Buffs.Pulse)

mq.imgui.init("CLEPLER",UI.Draw)

State.Running=true
print("[CLEPLER] v"..State.Version.." Loaded")

while State.Running do
    mq.doevents()
    -- Loadout.Pulse drains the gem-mem queue unconditionally, so
    -- re-gemming still progresses even while healing is paused.
    Loadout.Pulse()
    if not State.Paused then
        Heartbeat.Pulse()
    end
    mq.delay(10)
end

Commands.Unregister()
Config.Save()
WatchList.Save()
