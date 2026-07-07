------------------------------------------------------------
-- widgets/widgets_debug.lua
--
-- Debug / diagnostics tab. Shows runtime flags plus a
-- spellbook browser (filter + first matches) so you can verify
-- which spells CLEPLER sees as known/memorized.
------------------------------------------------------------

local ImGui    = require('ImGui')
local State    = require('state')
local Spellbook = require('spellbook')
local Spells   = require('spells')
local Button   = require('controls.controls_button')
local Card     = require('controls.controls_card')

local Widget = {}

-- Filter buffer persists across frames.
Widget.filterBuf = ""

-- Max matches to render (keep the tab cheap).
local MAX_MATCHES = 25

function Widget.Draw()

    Card.Begin("Runtime")
    ImGui.Text("Debug: " .. tostring(State.Settings.Debug))
    ImGui.Text("Test Mode: " .. tostring(State.Settings.TestMode))
    ImGui.Text("Buffing: " .. tostring(State.Settings.Buffing))
    Card.End()

    Card.Begin("Spellbook")
    ImGui.Text(string.format("Known spells: %d   Memorized gems: %d",
        Spellbook.Count(), (function()
            local n = 0
            for gem = 1, 12 do
                if Spells.Database.ByGem[gem] then n = n + 1 end
            end
            return n
        end)()))

    if Button.Draw("Refresh Spellbook") then
        Spellbook.Refresh()
    end

    ImGui.SameLine()
    ImGui.TextDisabled("filter:")
    ImGui.SameLine()
    local text, changed = ImGui.InputText("##sb_filter", Widget.filterBuf, 0)
    if changed then
        Widget.filterBuf = text or ""
    end

    local needle = Widget.filterBuf or ""
    if needle ~= "" then
        local shown = 0
        for _, rec in ipairs(Spellbook.Entries) do
            if shown >= MAX_MATCHES then
                ImGui.TextDisabled(string.format("  ...(%d+ more, refine filter)",
                    MAX_MATCHES))
                break
            end
            if rec.Name:lower():find(needle:lower(), 1, true) then
                shown = shown + 1
                local mem = Spells.Has(rec.Name) and " [mem]" or ""
                ImGui.Text(string.format("  %d. %s%s", rec.Index,
                    rec.Name, mem))
            end
        end
        if shown == 0 then
            ImGui.TextDisabled("  no matches")
        end
    end
    Card.End()
end

return Widget
