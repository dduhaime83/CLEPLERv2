------------------------------------------------------------
-- CLEPLER
-- widgets/widgets_healing.lua
--
-- Live status + leech management window.
--   * PLer status (HP / mana)
--   * Current heal target + queue size
--   * Add / remove out-of-group leeches
--   * Drag-and-drop priority reorder (with up/down fallback)
--   * Per-leech live status (HP, range, LOS, in-zone)
--
-- Reads the scanner cache (updated on heartbeat), not live
-- TLOs, so Draw stays cheap.
------------------------------------------------------------

local ImGui    = require('ImGui')
local mq       = require('mq')
local State    = require('state')
local WatchList = require('watchlist')
local Scanner  = require('scanner')
local HealQueue = require('healqueue')
local Buffs    = require('buffs')
local Hots     = require('hots')
local Med     = require('med')
local Config   = require('config')

local Widget = {}

-- ImGuiDir enum (Up=2, Down=3). Defensive in case the enum
-- global isn't injected in some builds.
local Dir = ImGuiDir or { Up = 2, Down = 3 }

-- Drag-drop payload type
local DND_TYPE = "CLEPLER_WATCH_ROW"

-- Input buffer for the add-target field (persists across frames)
Widget.addBuf = ""

------------------------------------------------------------
-- Color helpers
------------------------------------------------------------

local function HPColor(hp)
    if hp >= 75 then return 0.2, 1.0, 0.2, 1.0 end
    if hp >= 40 then return 1.0, 0.8, 0.2, 1.0 end
    return 1.0, 0.3, 0.3, 1.0
end

------------------------------------------------------------
-- Resolve a watchlist entry to its cached scanner record
------------------------------------------------------------

local function StatusFor(player)
    if not player or not player.Name then
        return nil, "unknown"
    end

    local rec = Scanner.FindByName(player.Name)

    if not rec then
        return nil, "not in zone"
    end

    if rec.Dead then
        return rec, "dead"
    end

    if not State.Settings.IgnoreRange
        and rec.Distance
        and rec.Distance > State.Settings.MaxHealRange then
        return rec, "out of range"
    end

    if not State.Settings.IgnoreLOS
        and rec.LineOfSight == false then
        return rec, "no LOS"
    end

    return rec, "ok"
end

------------------------------------------------------------
-- Header: PLer + queue summary
------------------------------------------------------------

local function DrawHeader()

    local meHP   = mq.TLO.Me.PctHPs() or 0
    local meMana = mq.TLO.Me.PctMana() or 0
    local meCast = mq.TLO.Me.Casting() or ""

    ImGui.TextColored(0.6, 0.8, 1.0, 1.0, "PLer:")
    ImGui.SameLine()
    ImGui.Text(string.format("HP %d%%   Mana %d%%", meHP, meMana))
    if meCast and meCast ~= "" then
        ImGui.SameLine()
        ImGui.TextColored(1.0, 0.8, 0.2, 1.0, "(casting " .. meCast .. ")")
    end

    ImGui.SameLine()
    ImGui.Text("   |   Queue:")
    ImGui.SameLine()
    ImGui.Text(tostring(HealQueue.Count()))

    local top = HealQueue.Next()
    if top then
        ImGui.SameLine()
        ImGui.Text("   |   Next:")
        ImGui.SameLine()
        ImGui.TextColored(1.0, 0.9, 0.6, 1.0,
            string.format("%s (%d%%)", top.Name or "?", top.HP or 0))
    end

    -- Buffing toggle (persisted).
    ImGui.SameLine()
    ImGui.Text("   |   Buffs:")
    ImGui.SameLine()
    local buffOn, buffPressed = ImGui.Checkbox("##buffing",
        State.Settings.Buffing == true)
    if buffPressed then
        State.Settings.Buffing = buffOn
        Config.Save()
    end

    -- HotRolling toggle (persisted).
    ImGui.SameLine()
    ImGui.Text("   |   HoT:")
    ImGui.SameLine()
    local hotOn, hotPressed = ImGui.Checkbox("##hotrolling",
        State.Settings.HotRolling == true)
    if hotPressed then
        State.Settings.HotRolling = hotOn
        Config.Save()
    end

    -- MedBreaks toggle (persisted).
    ImGui.SameLine()
    ImGui.Text("   |   Med:")
    ImGui.SameLine()
    local medOn, medPressed = ImGui.Checkbox("##medbreaks",
        State.Settings.MedBreaks == true)
    if medPressed then
        State.Settings.MedBreaks = medOn
        Config.Save()
    end

    -- Medding status indicator. Lights up red while the PLer is
    -- sitting on a med break so the operator sees it at a glance.
    if Med.IsMedding() then
        ImGui.SameLine()
        ImGui.TextColored(1.0, 0.3, 0.3, 1.0, "[MEDDING]")
    end

    ImGui.Separator()
end

------------------------------------------------------------
-- HoT status for one leech (tracker-based).
------------------------------------------------------------

local function DrawLeechHots(name)
    local status = Hots.HotStatusFor(name)
    if not status or #status == 0 then return end

    ImGui.TextDisabled("      HoT:")
    for _, s in ipairs(status) do
        ImGui.SameLine()
        local color
        if s.Status == "fresh" then
            color = { 0.2, 1.0, 0.2, 1.0 }
        elseif s.Status == "expiring" then
            color = { 1.0, 0.8, 0.2, 1.0 }
        elseif s.Status == "covered" then
            color = { 0.4, 0.7, 1.0, 1.0 }
        else
            color = { 1.0, 0.4, 0.4, 1.0 }
        end
        local label
        if s.Status == "down" then
            label = string.format("%s:down", s.Name)
        elseif s.Status == "covered" then
            label = string.format("%s:covered", s.Name)
        else
            label = string.format("%s:%ds", s.Name, s.Remaining)
        end
        ImGui.TextColored(color[1], color[2], color[3], color[4], label)
    end
end

------------------------------------------------------------
-- Buff status for one leech (uses the tracker, not live buff
-- windows, since out-of-group leeches expose none to MQ).
------------------------------------------------------------

local function DrawLeechBuffs(name)
    local status = Buffs.BuffStatusFor(name)
    if not status or #status == 0 then return end

    ImGui.TextDisabled("      buffs:")
    for _, s in ipairs(status) do
        ImGui.SameLine()
        local color
        if s.Status == "fresh" then
            color = { 0.2, 1.0, 0.2, 1.0 }
        elseif s.Status == "expiring" then
            color = { 1.0, 0.8, 0.2, 1.0 }
        elseif s.Status == "covered" then
            color = { 0.4, 0.7, 1.0, 1.0 }
        elseif s.Status == "low" then
            color = { 0.5, 0.5, 0.5, 1.0 }
        else
            color = { 1.0, 0.4, 0.4, 1.0 }
        end
        local label
        if s.Status == "missing" then
            label = string.format("%s:need", s.Name)
        elseif s.Status == "covered" then
            label = string.format("%s:covered", s.Name)
        elseif s.Status == "low" then
            label = string.format("%s:low", s.Name)
        else
            label = string.format("%s:%ds", s.Name, s.Remaining)
        end
        ImGui.TextColored(color[1], color[2], color[3], color[4], label)
    end
end

------------------------------------------------------------
-- Add-target row
------------------------------------------------------------

local function DrawAddRow()

    ImGui.Text("Add leech:")
    ImGui.SameLine()

    local text, changed = ImGui.InputText("##addtarget", Widget.addBuf, 0)
    if changed then
        Widget.addBuf = text or ""
    end

    ImGui.SameLine()
    if ImGui.Button("Add") then
        local name = Widget.addBuf and Widget.addBuf:gsub("^%s+", ""):gsub("%s+$", "")
        if name and name ~= "" then
            if WatchList.Add(name) then
                WatchList.Save()
                Widget.addBuf = ""
            else
                print("[CLEPLER] add failed (missing or duplicate name)")
            end
        end
    end

    ImGui.SameLine()
    ImGui.TextDisabled("(drag rows to reorder, or use the arrows)")
    ImGui.Separator()
end

------------------------------------------------------------
-- One leech row
------------------------------------------------------------

local function DrawLeechRow(i, player)

    ImGui.PushID(i)

    -- Up / Down / Remove (left side)
    if ImGui.ArrowButton("up", Dir.Up) then
        WatchList.MoveUp(i)
        WatchList.Save()
    end

    ImGui.SameLine()
    if ImGui.ArrowButton("dn", Dir.Down) then
        WatchList.MoveDown(i)
        WatchList.Save()
    end

    ImGui.SameLine()
    if ImGui.Button("Remove") then
        WatchList.RemoveAt(i)
        WatchList.Save()
        ImGui.PopID()
        return
    end

    -- Enable toggle
    ImGui.SameLine()
    local newVal, pressed = ImGui.Checkbox("##en", player.Enabled == true)
    if pressed then
        player.Enabled = newVal
        WatchList.Save()
    end

    -- Live status
    ImGui.SameLine()
    local rec, status = StatusFor(player)
    if rec and rec.HP then
        local hp = rec.HP
        ImGui.ProgressBar(hp / 100, 90, 0, string.format("%d%%", hp))
    else
        ImGui.TextDisabled("[no data]")
    end

    ImGui.SameLine()
    local scolor
    if status == "ok" then scolor = { 0.2, 1.0, 0.2, 1.0 }
    else scolor = { 1.0, 0.5, 0.3, 1.0 } end
    ImGui.TextColored(scolor[1], scolor[2], scolor[3], scolor[4], status)

    if rec and rec.Distance then
        ImGui.SameLine()
        ImGui.TextDisabled(string.format("d:%d", rec.Distance))
    end

    -- Name (drag source + drop target). This is the last item
    -- on the line so it fills the remaining width.
    ImGui.SameLine()
    local label = string.format("#%d  %s", i, player.Name or "?")
    ImGui.Selectable(label, false)

    if ImGui.BeginDragDropSource() then
        ImGui.SetDragDropPayload(DND_TYPE, tostring(i))
        ImGui.Text(label)
        ImGui.EndDragDropSource()
    end

    if ImGui.BeginDragDropTarget() then
        local payload = ImGui.AcceptDragDropPayload(DND_TYPE)
        if payload and payload.Data then
            local from = tonumber(payload.Data)
            if from and from ~= i then
                WatchList.Move(from, i)
                WatchList.Save()
            end
        end
        ImGui.EndDragDropTarget()
    end

    ImGui.PopID()
end

------------------------------------------------------------
-- Main draw
------------------------------------------------------------

function Widget.Draw()

    DrawHeader()

    local players = WatchList.GetPlayers() or {}

    if #players == 0 then
        ImGui.TextDisabled("No leeches on the watchlist. Add one above.")
        ImGui.Separator()
        return
    end

    ImGui.Text(string.format("Leeches (%d)  --  priority top to bottom",
        #players))
    ImGui.Separator()

    for i, player in ipairs(players) do
        DrawLeechRow(i, player)
        DrawLeechBuffs(player.Name)
        DrawLeechHots(player.Name)
    end

    ImGui.Separator()
    ImGui.TextDisabled(string.format("Emergencies: %d   Failed casts: %d   Buffs cast: %d   HoTs cast: %d",
        State.Stats.Emergencies or 0,
        State.Stats.FailedCasts or 0,
        State.Stats.BuffsCast or 0,
        State.Stats.HotsCast or 0))
end

return Widget
