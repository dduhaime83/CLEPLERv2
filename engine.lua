------------------------------------------------------------
-- CLEPLER
-- engine.lua
------------------------------------------------------------
local State=require('state')
local Scanner=require('scanner')
local Spells=require('spells')
local Healer=require('healer')

local Engine={}

function Engine.Pulse()
    Scanner.Scan()
    -- Decision logic will be expanded in next revision.
end

return Engine
