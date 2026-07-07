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
local UI=require('ui')

Config.Initialize()
WatchList.Load()
Spells.Refresh()
Commands.Register()

Heartbeat.Register("Scanner",State.Settings.ScanDelay,Scanner.Scan)
Heartbeat.Register("Engine",100,Engine.Pulse)
Heartbeat.Register("Healer",25,Healer.Pulse)

mq.imgui.init("CLEPLER",UI.Draw)

State.Running=true
print("[CLEPLER] v"..State.Version.." Loaded")

while State.Running do
    mq.doevents()
    if not State.Paused then
        Heartbeat.Pulse()
    end
    mq.delay(10)
end

Commands.Unregister()
Config.Save()
WatchList.Save()
