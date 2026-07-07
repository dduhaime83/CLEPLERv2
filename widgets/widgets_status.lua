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

-- Input buffer for the add-target field (persists across frames).
Widget.addBuf = ""

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

    -- Watchlist management: add + remove targets directly from
    -- the main tab so you don't have to switch to Healing.
    ImGui.TextColored(0.6, 0.8, 1.0, 1.0, "Watchlist:")
    ImGui.SameLine()
    local text, changed = ImGui.InputText("##status_addtarget",
        Widget.addBuf, 0)
    if changed then
        Widget.addBuf = text or ""
    end
    ImGui.SameLine()
    if ImGui.Button("Add Target") then
        local name = Widget.addBuf and
            Widget.addBuf:gsub("^%s+", ""):gsub("%s+$", "")
        if name and name ~= "" then
            if WatchList.Add(name) then
                WatchList.Save()
                Widget.addBuf = ""
            else
                print("[CLEPLER] add failed (missing or duplicate name)")
            end
        end
    end

    -- Watchlist leeches (primary focus). Show every roster entry
    -- (not just in-zone ones) so you can remove offline targets too.
    local roster = WatchList.GetPlayers() or {}
    local inZone = Scanner.GetWatchMembers and Scanner.GetWatchMembers() or {}
    local inZoneByName = {}
    for _, m in ipairs(inZone) do
        if m.Name then inZoneByName[m.Name:lower()] = m end
    end

    ImGui.Text(string.format("Targets (%d)", #roster))
    for i, p in ipairs(roster) do
        ImGui.PushID(i)
        if ImGui.Button("Remove") then
            WatchList.RemoveAt(i)
            WatchList.Save()
            ImGui.PopID()
            -- Lua 5.1 has no goto; break out and let the rest of
            -- the list redraw next frame (avoids shifted-index /
            -- duplicate-ID issues from mutating mid-iteration).
            break
        end
        ImGui.SameLine()
        local rec = p.Name and inZoneByName[p.Name:lower()] or nil
        if rec then
            Row(p.Name or "?", rec.HP, rec.Distance, rec.LineOfSight,
                rec.Dead and "dead" or
                (p.Enabled == false and "off" or "leech"))
        else
            Row(p.Name or "?", nil, nil, nil,
                p.Enabled == false and "off / not in zone"
                                   or "not in zone")
        end
        ImGui.PopID()
    end
    if #roster == 0 then
        ImGui.TextDisabled("  none -- add a target above")
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
