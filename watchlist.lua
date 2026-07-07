------------------------------------------------------------
-- CLEPLER
-- watchlist.lua
------------------------------------------------------------
local mq=require('mq')
local State=require('state')
local WatchList={}
WatchList.File=mq.configDir.."\\CLEPLER_WatchList.ini"
local function NewPlayer(name)
 return {Name=name,Enabled=true,Online=false,Dead=false,HP=100,Mana=100,
 Distance=99999,SpawnID=0,Level=0,Class="",LineOfSight=false,
 InRange=false,Status="Offline",LastSpell=""}
end
function WatchList.GetPlayers() return State.WatchList end
function WatchList.Add(name)
 if not name or name=="" then return false end
 table.insert(State.WatchList,NewPlayer(name))
 return true
end
function WatchList.Load() State.WatchList={} end
function WatchList.Save() end
return WatchList