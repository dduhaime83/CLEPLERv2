local ImGui=require("ImGui")
local B={}
function B.Draw(label) return ImGui.Button(label) end
return B
