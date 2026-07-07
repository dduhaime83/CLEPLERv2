------------------------------------------------------------
-- CLEPLER
-- engine.lua
------------------------------------------------------------
local State=require('state')
local Scanner=require('scanner')
local HealQueue=require('healqueue')

local Engine={}

-- Pipeline step: rebuild the prioritized heal queue from the
-- latest scanner snapshot. Scanning itself is handled by the
-- dedicated "Scanner" Heartbeat task (Scanner.Scan).
function Engine.Pulse()
    HealQueue.Build(Scanner)
end

return Engine
