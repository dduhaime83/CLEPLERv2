------------------------------------------------------------
-- CLEPLER
-- widgets/widgets_remote.lua
--
-- Cross-toon viewer UI (rendered on a "viewer" role toon, i.e.
-- the leech being driven). Reads the cleric's published state
-- from Remote.Status (a cache fed by Remote.PollStatus) and
-- sends commands back via Remote.SendCommand.
--
-- Two tabs:
--   * Status  -- live read-only view of the cleric's PLer /
--               queue / toggles / stats / watchlist
--   * Controls -- toggleable options (pause/follow/med/buffs/
--               hots) + add/remove leech + per-leech reorder,
--               enable, and heal-below threshold. All commands
--               are disabled while one is pending (until the
--               cleric acks or the 3s timeout fires).
------------------------------------------------------------

local ImGui   = require('ImGui')
local Window  = require('window')
local State   = require('state')
local Remote  = require('remote')

local Widget = {}

-- ImGuiDir enum (Up=2, Down=3). Defensive in case the enum
-- global isn't injected in some builds.
local Dir = ImGuiDir or { Up = 2, Down = 3 }

-- Input buffers (persist across frames).
Widget.addBuf    = ""
Widget.removeBuf = ""

------------------------------------------------------------
-- Color helpers
------------------------------------------------------------

local function HPColor(hp)
    if hp >= 75 then return 0.2, 1.0, 0.2, 1.0 end
    if hp >= 40 then return 1.0, 0.8, 0.2, 1.0 end
    return 1.0, 0.3, 0.3, 1.0
end

local function StatusColor(status)
    if status == "ok" then return 0.2, 1.0, 0.2, 1.0 end
    return 1.0, 0.5, 0.3, 1.0
end

------------------------------------------------------------
-- Pending-command guard. Returns true if a command is in flight
-- (caller should disable controls).
------------------------------------------------------------

local function Pending()
    return Remote.Pending()
end

-- A command can be sent if none is pending, OR the pending one
-- has timed out (>3s with no ack) -- in which case we let the
-- operator retry rather than deadlock the controls.
local function CanSend()
    if not Remote.Pending() then return true end
    return Remote.PendingAgeMs() > 3000
end

-- Wrap a control action so it only fires when no command is
-- pending (or the pending one timed out). Returns true if sent.
local function TrySend(action, a1, a2, a3)
    if not CanSend() then return false end
    Remote.SendCommand(action, a1, a2, a3)
    return true
end

------------------------------------------------------------
-- Header: source + connection status
------------------------------------------------------------

local function DrawHeader(s)
    local name = (s and s.Source) or "(no source)"
    ImGui.TextColored(0.6, 0.8, 1.0, 1.0, "CLEPLER Remote")
    ImGui.SameLine()
    ImGui.Text("  --  Source:")
    ImGui.SameLine()
    ImGui.TextColored(1.0, 0.9, 0.6, 1.0, name)

    -- Staleness / connection indicator.
    local age = Remote.StatusAgeMs()
    local pcol, plabel
    if age < 0 then
        pcol = { 1.0, 0.5, 0.3, 1.0 }; plabel = "[no data]"
    elseif age > 5000 then
        pcol = { 1.0, 0.4, 0.4, 1.0 }; plabel = "[STALE: cleric not responding?]"
    else
        pcol = { 0.2, 1.0, 0.2, 1.0 }; plabel = string.format("[live %dms]", age)
    end
    ImGui.SameLine()
    ImGui.TextColored(pcol[1], pcol[2], pcol[3], pcol[4], plabel)

    -- Pending-command indicator.
    if Pending() then
        local p_age = Remote.PendingAgeMs()
        local pc
        if p_age > 3000 then
            pc = { 1.0, 0.4, 0.4, 1.0 }
            ImGui.SameLine()
            ImGui.TextColored(pc[1], pc[2], pc[3], pc[4],
                string.format("[no ack %dms]", p_age))
        else
            pc = { 1.0, 0.8, 0.2, 1.0 }
            ImGui.SameLine()
            ImGui.TextColored(pc[1], pc[2], pc[3], pc[4],
                string.format("[sending... %dms]", p_age))
        end
    end

    ImGui.Separator()
end

------------------------------------------------------------
-- STATUS TAB
------------------------------------------------------------

local function DrawStatusTab(s)

    if not s then
        ImGui.TextDisabled("Waiting for cleric to publish status...")
        return
    end

    -- PLer summary
    ImGui.Text("PLer:")
    ImGui.SameLine()
    local r, g, b, a = HPColor(s.PLerHP)
    ImGui.TextColored(r, g, b, a, string.format("HP %d%%", s.PLerHP))
    ImGui.SameLine()
    ImGui.Text(string.format("  Mana %d%%", s.PLerMana))
    if s.PLerCasting and s.PLerCasting ~= "" then
        ImGui.SameLine()
        ImGui.TextColored(1.0, 0.8, 0.2, 1.0, "(casting " .. s.PLerCasting .. ")")
    end

    -- Queue
    ImGui.SameLine()
    ImGui.Text("   |   Queue:")
    ImGui.SameLine()
    ImGui.Text(tostring(s.QueueCount))
    if s.NextName and s.NextName ~= "" then
        ImGui.SameLine()
        ImGui.Text("   |   Next:")
        ImGui.SameLine()
        ImGui.TextColored(1.0, 0.9, 0.6, 1.0,
            string.format("%s (%d%%)", s.NextName, s.NextHP))
    end

    -- State badges
    ImGui.Separator()
    if s.Enabled and not s.Paused then
        ImGui.TextColored(0.2, 1.0, 0.2, 1.0, "[HEALING ON]")
    elseif s.Paused then
        ImGui.TextColored(1.0, 0.8, 0.2, 1.0, "[PAUSED]")
    else
        ImGui.TextColored(1.0, 0.4, 0.4, 1.0, "[healing off]")
    end

    if s.Medding then
        ImGui.SameLine()
        ImGui.TextColored(1.0, 0.3, 0.3, 1.0, "[MEDDING]")
    end
    ImGui.SameLine()
    local fc = (s.FollowStatus and string.find(s.FollowStatus, "following", 1, true))
        and { 0.2, 1.0, 0.2, 1.0 } or { 0.6, 0.6, 0.6, 1.0 }
    ImGui.TextColored(fc[1], fc[2], fc[3], fc[4],
        "[FOLLOW: " .. tostring(s.FollowStatus) .. "]")

    -- Toggle readout
    ImGui.Separator()
    ImGui.TextDisabled(string.format(
        "Buffs:%s  HoT:%s  Med:%s  Follow:%s",
        s.Buffing and "on" or "off",
        s.HotRolling and "on" or "off",
        s.MedBreaks and "on" or "off",
        s.FollowEnabled and "on" or "off"))

    -- Stats
    ImGui.Separator()
    ImGui.TextDisabled(string.format(
        "Heals:%d  Emergencies:%d  Failed:%d  Buffs cast:%d  HoTs cast:%d",
        s.Stats.HealsCast, s.Stats.Emergencies, s.Stats.FailedCasts,
        s.Stats.BuffsCast, s.Stats.HotsCast))

    -- Watchlist (read-only here; reorder is on the Controls tab)
    ImGui.Separator()
    local watch = s.Watch or {}
    if #watch == 0 then
        ImGui.TextDisabled("No leeches on the cleric's watchlist.")
        return
    end

    ImGui.Text(string.format("Leeches (%d)  --  priority top to bottom", #watch))
    ImGui.Separator()

    for i, w in ipairs(watch) do
        ImGui.PushID(i)

        -- Enabled marker
        if w.Enabled then
            ImGui.TextColored(0.2, 1.0, 0.2, 1.0, "*")
        else
            ImGui.TextDisabled("-")
        end
        ImGui.SameLine()

        -- HP bar
        if w.HP and w.HP > 0 then
            ImGui.ProgressBar(w.HP / 100, 90, 0, string.format("%d%%", w.HP))
        else
            ImGui.TextDisabled("[no data]")
        end
        ImGui.SameLine()

        -- Status + distance
        local sr, sg, sb, sa = StatusColor(w.Status)
        ImGui.TextColored(sr, sg, sb, sa, w.Status)
        if w.Distance and w.Distance > 0 then
            ImGui.SameLine()
            ImGui.TextDisabled(string.format("d:%d", w.Distance))
        end
        ImGui.SameLine()

        -- Name + heal-below
        local hb = w.HealBelowPct or 0
        local hbLabel = (hb == 0) and "auto" or (tostring(hb) .. "%")
        ImGui.Text(string.format("#%d  %s  (heal<%s)", i, w.Name, hbLabel))

        ImGui.PopID()
    end
end

------------------------------------------------------------
-- CONTROLS TAB (toggleable options + leech management)
------------------------------------------------------------

local function DrawToggleRow(label, current, action)
    ImGui.Text(label)
    ImGui.SameLine()
    local on = current == true
    -- Display-only checkbox that sends a command on press (we
    -- can't bind directly because the value lags the ack).
    local _, pressed = ImGui.Checkbox("##" .. action, on)
    if pressed then
        TrySend(action, tostring(not on))
    end
end

local function DrawControlsTab(s)

    if not s then
        ImGui.TextDisabled("Waiting for cleric to publish status...")
        return
    end

    -- Master toggles (each sends a command; disabled while pending)
    if Pending() then
        ImGui.TextColored(1.0, 0.8, 0.2, 1.0, "[command in flight -- wait for ack]")
    end

    DrawToggleRow("Pause healing:", s.Paused, "Pause")
    DrawToggleRow("Auto-follow:",   s.FollowEnabled, "Follow")
    DrawToggleRow("Med breaks:",    s.MedBreaks, "Med")
    DrawToggleRow("Buffing:",       s.Buffing, "Buffs")
    DrawToggleRow("HoT rolling:",   s.HotRolling, "Hots")

    -- Add / remove leech
    ImGui.Separator()
    ImGui.Text("Add leech:")
    ImGui.SameLine()
    local atext, achanged = ImGui.InputText("##radd", Widget.addBuf, 0)
    if achanged then Widget.addBuf = atext or "" end
    ImGui.SameLine()
    if ImGui.Button("Add##r") and Widget.addBuf and Widget.addBuf ~= "" then
        local name = Widget.addBuf:gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then
            if TrySend("Add", name) then
                Widget.addBuf = ""
            end
        end
    end

    ImGui.SameLine()
    ImGui.Text("Remove:")
    ImGui.SameLine()
    local rtext, rchanged = ImGui.InputText("##rremove", Widget.removeBuf, 0)
    if rchanged then Widget.removeBuf = rtext or "" end
    ImGui.SameLine()
    if ImGui.Button("Remove##r") and Widget.removeBuf and Widget.removeBuf ~= "" then
        local name = Widget.removeBuf:gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then
            if TrySend("Remove", name) then
                Widget.removeBuf = ""
            end
        end
    end

    -- Per-leech rows: reorder / enable / heal-below / remove
    ImGui.Separator()
    local watch = s.Watch or {}
    if #watch == 0 then
        ImGui.TextDisabled("No leeches to manage.")
        return
    end

    ImGui.Text(string.format("Leeches (%d)  --  reorder with the arrows", #watch))
    ImGui.Separator()

    for i, w in ipairs(watch) do
        ImGui.PushID(i)

        if ImGui.ArrowButton("up", Dir.Up) then
            TrySend("MoveUp", tostring(i), w.Name)
        end
        ImGui.SameLine()
        if ImGui.ArrowButton("dn", Dir.Down) then
            TrySend("MoveDown", tostring(i), w.Name)
        end
        ImGui.SameLine()

        -- Enable toggle
        local _, epressed = ImGui.Checkbox("##en", w.Enabled)
        if epressed then
            TrySend("SetEnabled", tostring(i), w.Name, tostring(not w.Enabled))
        end
        ImGui.SameLine()

        -- HP / status (read-only context)
        local sr, sg, sb, sa = StatusColor(w.Status)
        ImGui.TextColored(sr, sg, sb, sa,
            string.format("%s  %d%%  %s", w.Name, w.HP, w.Status))
        ImGui.SameLine()

        -- Heal-below stepper
        ImGui.TextDisabled("heal<")
        ImGui.SameLine()
        if ImGui.Button("-##hbdn") then
            TrySend("SetHealBelowPct", tostring(i), w.Name,
                tostring((w.HealBelowPct or 0) - 5))
        end
        ImGui.SameLine()
        local hb = w.HealBelowPct or 0
        if hb == 0 then
            ImGui.TextDisabled("auto")
        else
            ImGui.Text(string.format("%d%%", hb))
        end
        ImGui.SameLine()
        if ImGui.Button("+##hbup") then
            TrySend("SetHealBelowPct", tostring(i), w.Name,
                tostring((w.HealBelowPct or 0) + 5))
        end
        ImGui.SameLine()
        if ImGui.Button("Auto##hb") then
            TrySend("SetHealBelowPct", tostring(i), w.Name, "0")
        end

        ImGui.PopID()
    end
end

------------------------------------------------------------
-- Main draw
------------------------------------------------------------

function Widget.Draw()

    ImGui.SetNextWindowSize(Window.Width, Window.Height, ImGuiCond.FirstUseEver)

    local open, shouldDraw = ImGui.Begin("CLEPLER Remote", Window.Open)
    Window.Open = open

    if shouldDraw then
        local s = Remote.Status
        DrawHeader(s)

        if ImGui.BeginTabBar("clepler_remote_tabs") then
            if ImGui.BeginTabItem("Status") then
                DrawStatusTab(s)
                ImGui.EndTabItem()
            end
            if ImGui.BeginTabItem("Controls") then
                DrawControlsTab(s)
                ImGui.EndTabItem()
            end
            ImGui.EndTabBar()
        end
    end

    ImGui.End()
end

return Widget
