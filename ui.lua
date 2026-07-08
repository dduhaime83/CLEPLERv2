------------------------------------------------------------
-- CLEPLER
-- ui.lua
--
-- ImGui window. Hosts the status / healing / settings / debug
-- widgets in a tab bar.
------------------------------------------------------------

local ImGui         = require('ImGui')
local Window        = require('window')
local State         = require('state')
local StatusWidget  = require('widgets.widgets_status')
local HealingWidget = require('widgets.widgets_healing')
local SettingsWidget = require('widgets.widgets_settings')
local DebugWidget   = require('widgets.widgets_debug')
local RemoteWidget   = require('widgets.widgets_remote')

local UI = {}

function UI.Draw()

    if not Window.Open then return end

    -- Viewer toons get the cross-toon remote UI (the cleric's
    -- live status + a Controls tab to reorder/toggle remotely).
    if State.RemoteEffectiveRole == "viewer" then
        RemoteWidget.Draw()
        return
    end

    ImGui.SetNextWindowSize(Window.Width, Window.Height, ImGuiCond.FirstUseEver)

    -- MQ ImGui binding returns (open, shouldDraw): first is the
    -- p_open flag (false when the close button is clicked), second
    -- is whether the window content should be drawn this frame.
    local open, shouldDraw = ImGui.Begin(Window.Title, Window.Open)
    Window.Open = open

    if shouldDraw then

        ImGui.Text("CLEPLER v" .. tostring(State.Version))
        ImGui.SameLine()
        if State.Enabled then
            ImGui.TextColored(0.2, 1.0, 0.2, 1.0, "[HEALING ON]")
        else
            ImGui.TextColored(1.0, 0.4, 0.4, 1.0, "[healing off]")
        end
        if State.Settings.TestMode then
            ImGui.SameLine()
            ImGui.TextColored(1.0, 0.8, 0.2, 1.0, "[TEST MODE]")
        end

        ImGui.Separator()

        if ImGui.BeginTabBar("clepler_tabs") then

            if ImGui.BeginTabItem("Status") then
                StatusWidget.Draw()
                ImGui.EndTabItem()
            end

            if ImGui.BeginTabItem("Healing") then
                HealingWidget.Draw()
                ImGui.EndTabItem()
            end

            if ImGui.BeginTabItem("Settings") then
                SettingsWidget.Draw()
                ImGui.EndTabItem()
            end

            if ImGui.BeginTabItem("Debug") then
                DebugWidget.Draw()
                ImGui.EndTabItem()
            end

            ImGui.EndTabBar()
        end

    end

    ImGui.End()
end

return UI
