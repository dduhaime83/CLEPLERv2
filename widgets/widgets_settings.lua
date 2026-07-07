local ImGui=require("ImGui")
local State=require("state")
local Widget={}
function Widget.Draw() ImGui.Text("Test Mode: "..tostring(State.Settings.TestMode)) end
return Widget
