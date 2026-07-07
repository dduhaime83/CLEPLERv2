------------------------------------------------------------
-- CLEPLER
-- ui.lua
------------------------------------------------------------
local ImGui=require('ImGui')
local Window=require('window')

local UI={}

function UI.Draw()

    if not Window.Open then return end

    ImGui.SetNextWindowSize(Window.Width,Window.Height,ImGuiCond.FirstUseEver)

    local open=Window.Open
    open=ImGui.Begin(Window.Title,open)
    Window.Open=open

    ImGui.Text("CLEPLER v0.1")
    ImGui.Separator()
    ImGui.Text("Core loaded successfully.")
    ImGui.Text("Watch list and healing widgets will be added next.")

    ImGui.End()

end

return UI
