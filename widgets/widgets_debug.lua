------------------------------------------------------------
-- widgets/debug.lua
------------------------------------------------------------
local ImGui=require('ImGui')
local State=require('state')
local Widget={}
function Widget.Draw()
    ImGui.Text("Debug: "..tostring(State.Settings.Debug))
    ImGui.Text("Test Mode: "..tostring(State.Settings.TestMode))
end
return Widget
