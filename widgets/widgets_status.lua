------------------------------------------------------------
-- CLEPLER
-- widgets/widgets_status.lua
--
-- Live status overview: PLer, group, and watchlist leeches.
-- Reads the scanner cache (heartbeat-driven), not live TLOs.
------------------------------------------------------------

local ImGui    = require('ImGui')
local mq       = require('mq')
local State    = require('state')
local Scanner  = require('scanner')
local HealQueue = require('healqueue')
local WatchList = require('watchlist')

local Widget = {}

local function HPColor(hp)
    if hp >= 75 then return 0.2, 1.0, 0.2, 1.0 end
    if hp >= 40 then return 1.0, 0.8, 0.2, 1.0 end
    return 1.0, 0.3, 0.3, 1.0
end

local function Row(name, hp, dist, los, tag)
    ImGui.Text(name or "?")
    ImGui.SameLine(120)
    if hp then
        local r, g, b, a = HPColor(hp)
        ImGui.TextColored(r, g, b, a, string.format("%3d%%", hp))
    else
        ImGui.TextDisabled("  --")
    end
    if dist then
        ImGui.SameLine(180)
        ImGui.TextDisabled(string.format("d:%d", dist))
    end
    if los ~= nil then
        ImGui.SameLine(240)
        if los then
            ImGui.TextColored(0.2, 1.0, 0.2, 1.0, "LOS")
        else
            ImGui.TextColored(1.0, 0.3, 0.3, 1.0, "noLOS")
        end
    end
    if tag then
        ImGui.SameLine(300)
        ImGui.TextDisabled(tag)
    end
end

function Widget.Draw()

    -- PLer
    ImGui.TextColored(0.6, 0.8, 1.0, 1.0, "PLer (you)")
    local meHP   = mq.TLO.Me.PctHPs() or 0
    local meMana = mq.TLO.Me.PctMana() or 0
    local r, g, b, a = HPColor(meHP)
    Row(mq.TLO.Me.CleanName() or "Me", meHP, 0, true,
        string.format("mana %d%%", meMana))

    ImGui.Separator()

    -- Watchlist leeches (primary focus)
    local leeches = Scanner.GetWatchMembers and Scanner.GetWatchMembers() or {}
    ImGui.Text(string.format("Leeches in zone: %d", #leeches))
    for _, m in ipairs(leeches) do
        Row(m.Name, m.HP, m.Distance, m.LineOfSight,
            m.Dead and "dead" or "leech")
    end
    if #leeches == 0 then
        ImGui.TextDisabled("  none in range/zone")
    end

    ImGui.Separator()

    -- Group (secondary)
    local group = Scanner.GetGroup() or {}
    ImGui.Text(string.format("Group: %d", #group))
    for _, m in ipairs(group) do
        Row(m.Name, m.HP, m.Distance, m.LineOfSight,
            m.Dead and "dead" or m.Class)
    end

    ImGui.Separator()

    -- Queue
    ImGui.Text(string.format("Heal queue: %d", HealQueue.Count()))
    local top = HealQueue.Next()
    if top then
        ImGui.Text(string.format("  next: %s (%d%%)", top.Name or "?", top.HP or 0))
    end

    ImGui.Separator()
    ImGui.TextDisabled(string.format("Current target: %s   Current spell: %s",
        tostring(State.CurrentTarget), tostring(State.CurrentSpell)))
    if State.LastError and State.LastError ~= "" then
        ImGui.TextColored(1.0, 0.4, 0.4, 1.0, "err: " .. State.LastError)
    end
end

return Widget
