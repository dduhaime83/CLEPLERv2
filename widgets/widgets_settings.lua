------------------------------------------------------------
-- CLEPLER
-- widgets/widgets_settings.lua
--
-- Settings tab:
--   * TestMode toggle (dry run, no casts)
--   * Gem Loadout editor: 12 text fields (one per gem) +
--     "Mem All" button. Persists to CLEPLER.ini [GemLoadout].
--     Shows the currently-memorized spell next to each field
--     for feedback.
------------------------------------------------------------

local ImGui    = require('ImGui')
local State    = require('state')
local Config   = require('config')
local Loadout  = require('loadout')
local Spells   = require('spells')
local Remote   = require('remote')
local Card     = require('controls.controls_card')
local Button   = require('controls.controls_button')

local Widget = {}

-- Per-gem input buffers (persist across frames). Lazily seeded
-- from the loadout on first draw so manual INI edits show up.
Widget.gemBuf = nil

local function EnsureBuffers()
    if Widget.gemBuf then return end
    Widget.gemBuf = {}
    for i = 1, 12 do
        Widget.gemBuf[i] = Loadout.Get(i)
    end
end

------------------------------------------------------------
-- Remote role card (source/off/viewer)
------------------------------------------------------------

local function DrawRemoteRole()

    Card.Begin("Cross-Toon Remote")

    local role = State.Settings.RemoteRole or "off"
    ImGui.Text("Role:")
    ImGui.SameLine()
    local rcol
    if role == "source" then rcol = { 0.2, 1.0, 0.2, 1.0 }
    elseif role == "viewer" then rcol = { 0.4, 0.7, 1.0, 1.0 }
    else rcol = { 0.6, 0.6, 0.6, 1.0 } end
    ImGui.TextColored(rcol[1], rcol[2], rcol[3], rcol[4], role)

    ImGui.SameLine()
    if Button.Draw("Off", 0, 0) and role ~= "off" then
        Remote.SetRole("off")
    end
    ImGui.SameLine()
    if Button.Draw("Source", 0, 0) and role ~= "source" then
        Remote.SetRole("source")
    end
    ImGui.SameLine()
    if Button.Draw("Viewer", 0, 0) and role ~= "viewer" then
        Remote.SetRole("viewer")
    end

    ImGui.TextDisabled(
        "Source = cleric publishes live status + accepts remote " ..
        "commands. Viewer = a leech toon renders that status and " ..
        "can reorder the watchlist / toggle options. Reload CLEPLER " ..
        "(/lua run init) after changing role for it to take full effect.")

    Card.End()
end

------------------------------------------------------------
-- Gem loadout card
------------------------------------------------------------

local function DrawLoadout()

    Card.Begin("Gem Loadout")

    ImGui.TextDisabled(
        "Assign a spell per gem (substring OK, e.g. \"Symbol\"). " ..
        "Empty = unassigned. Click Mem All to memorize any that " ..
        "aren't already in their gem.")

    EnsureBuffers()

    for gem = 1, 12 do

        ImGui.PushID(gem)

        ImGui.Text(string.format("Gem %2d:", gem))
        ImGui.SameLine()

        local text, changed = ImGui.InputText("##gem", Widget.gemBuf[gem] or "", 0)
        if changed then
            Widget.gemBuf[gem] = text or ""
            Loadout.Set(gem, Widget.gemBuf[gem])
            Loadout.SaveGem(gem)
        end

        -- Current contents of this gem (from the gem cache).
        ImGui.SameLine()
        local cur = Spells.Database.ByGem[gem]
        local curName = (cur and cur.Name) or ""
        if curName ~= "" then
            ImGui.TextColored(0.5, 0.7, 0.5, 1.0, string.format("mem: %s", curName))
        else
            ImGui.TextDisabled("mem: (empty)")
        end

        ImGui.PopID()
    end

    Card.End()

    -- Mem All + status.
    if Button.Draw("Mem All", 120, 0) then
        Loadout.MemAll()
    end

    if Loadout.Active then
        ImGui.SameLine()
        ImGui.TextColored(1.0, 0.8, 0.2, 1.0,
            string.format("[MEMMING: %d gem(s) left]", #Loadout.Queue))
        ImGui.SameLine()
        if Button.Draw("Cancel##memall", 0, 0) then
            Loadout.Cancel("manual")
        end
    end
end

------------------------------------------------------------
-- Main draw
------------------------------------------------------------

function Widget.Draw()

    -- TestMode toggle (persisted).
    local tmOn, tmPressed = ImGui.Checkbox("Test Mode (dry run, no casts)",
        State.Settings.TestMode == true)
    if tmPressed then
        State.Settings.TestMode = tmOn
        Config.Save()
    end

    ImGui.Separator()
    DrawRemoteRole()
    DrawLoadout()
end

return Widget
