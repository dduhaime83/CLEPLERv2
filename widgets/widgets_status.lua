------------------------------------------------------------
-- widgets/status.lua
------------------------------------------------------------
local ImGui=require('ImGui')
local State=require('state')
local Widget={}
function Widget.Draw()
    ImGui.Text("Target: "..(State.CurrentTarget or "None"))
    ImGui.Text("Spell : "..(State.CurrentSpell or "None"))
end
return Widget
