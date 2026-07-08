------------------------------------------------------------
-- CLEPLER
-- remote.lua
--
-- Cross-toon live status + remote control for same-PC boxing.
-- The cleric (role "source") publishes its state to a shared
-- INI; a leech toon (role "viewer") polls it and renders a
-- status window, and can send commands (reorder watchlist,
-- toggle buffs/med/follow/pause) back to the cleric.
--
-- Two shared files in mq.configDir (shared across all MQ2
-- clients on the same machine):
--   CLEPLER_Remote.ini  -- source WRITES status, viewer READS
--   CLEPLER_Cmd.ini     -- viewer WRITES commands, source READS
--
-- Status commit: source writes every status row first, then
-- writes [Status].StatusSeq LAST. Viewer only adopts a snapshot
-- when StatusSeq changes, so it never renders a half-written one.
--
-- Command protocol (single-slot, one viewer):
--   viewer writes [Cmd] Action/Arg1/Arg2/Arg3, THEN Seq (commit)
--   source applies when Cmd.Seq > Ack.Seq, then writes [Ack] Seq
--   viewer: pending until Ack.Seq >= its sent Seq, or 3s timeout
--
-- Staleness: source writes os.time() as Updated. If the viewer
-- sees no StatusSeq change for several seconds it shows "stale".
--
-- Remote.Pulse() runs UNCONDITIONALLY from init.lua's main loop
-- (not the paused heartbeat) so status/commands still work while
-- the cleric's healing is paused.
------------------------------------------------------------

local mq        = require('mq')
local State     = require('state')
local WatchList = require('watchlist')
local Scanner   = require('scanner')
local HealQueue = require('healqueue')
local Med       = require('med')
local Follow    = require('follow')
local Config    = require('config')

local Remote = {}

Remote.StatusFile = mq.configDir .. "\\CLEPLER_Remote.ini"
Remote.CmdFile    = mq.configDir .. "\\CLEPLER_Cmd.ini"

Remote.StatusSection = "Status"
Remote.StatsSection   = "Stats"
Remote.WatchSection   = "Watch"

-- Viewer-side cache of the last adopted snapshot.
Remote.Status = nil

-- Command protocol state (viewer side).
Remote.LastAppliedAck = 0     -- highest [Ack].Seq we've seen
Remote.LastSentSeq    = 0     -- last [Cmd].Seq we sent
Remote.PendingSince   = 0     -- mq.gettime() when we sent it

-- Source-side: highest [Cmd].Seq we've already applied (runtime
-- only; the persisted source of truth is [Ack].Seq in the file).
Remote.SourceAppliedSeq = 0

-- Throttle timers.
Remote.LastPublish = 0
Remote.LastCmdPoll = 0
Remote.LastStatusPoll = 0

------------------------------------------------------------
-- pcall wrapper
------------------------------------------------------------

local function SafeCall(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

local function IniRead(file, section, key, default)
    local v = SafeCall(function()
        return mq.TLO.Ini(file, section, key)()
    end)
    if v == nil or v == "" then return default end
    return v
end

local function IniWrite(file, section, key, value)
    mq.cmdf('/ini "%s" "%s" "%s" "%s"', file, section, key, tostring(value))
end

local function toBool(v)
    if v == "true" or v == true then return true end
    return false
end

------------------------------------------------------------
-- SOURCE: build the snapshot table from live state
------------------------------------------------------------

local function LeeStatus(rec)
    if not rec then return "not in zone" end
    if rec.Dead then return "dead" end
    if not State.Settings.IgnoreRange
        and rec.Distance
        and rec.Distance > State.Settings.MaxHealRange then
        return "out of range"
    end
    if not State.Settings.IgnoreLOS and rec.LineOfSight == false then
        return "no LOS"
    end
    return "ok"
end

local function BuildSnapshot()
    local meHP   = SafeCall(function() return mq.TLO.Me.PctHPs() end) or 0
    local meMana = SafeCall(function() return mq.TLO.Me.PctMana() end) or 0
    local meCast = SafeCall(function() return mq.TLO.Me.Casting() end) or ""
    local meName = SafeCall(function() return mq.TLO.Me.CleanName() end) or "(cleric)"

    local snap = {
        Source       = meName,
        StatusSeq    = 0,            -- set by Publish on commit
        Updated       = tostring(os.time()),
        Enabled      = State.Enabled,
        Paused       = State.Paused,
        PLerHP       = tonumber(meHP) or 0,
        PLerMana     = tonumber(meMana) or 0,
        PLerCasting  = meCast,
        QueueCount   = HealQueue.Count(),
        NextName     = "",
        NextHP       = 0,
        Medding      = Med.IsMedding(),
        FollowStatus = Follow.Status(),
        FollowEnabled= State.Settings.FollowEnabled,
        Buffing      = State.Settings.Buffing,
        HotRolling   = State.Settings.HotRolling,
        MedBreaks    = State.Settings.MedBreaks,
        Stats        = {
            HealsCast    = State.Stats.HealsCast or 0,
            Emergencies  = State.Stats.Emergencies or 0,
            FailedCasts  = State.Stats.FailedCasts or 0,
            BuffsCast    = State.Stats.BuffsCast or 0,
            HotsCast     = State.Stats.HotsCast or 0,
        },
        Watch = {},
    }

    local top = HealQueue.Next()
    if top then
        snap.NextName = top.Name or ""
        snap.NextHP   = top.HP or 0
    end

    local players = WatchList.GetPlayers() or {}
    for _, p in ipairs(players) do
        local rec = Scanner.FindByName(p.Name)
        table.insert(snap.Watch, {
            Name         = p.Name or "",
            Enabled      = p.Enabled == true,
            HP           = rec and tonumber(rec.HP) or 0,
            Status       = LeeStatus(rec),
            Distance     = rec and tonumber(rec.Distance) or 0,
            HealBelowPct = tonumber(p.HealBelowPct) or 0,
        })
    end

    return snap
end

------------------------------------------------------------
-- SOURCE: publish snapshot to the status file.
--   Writes all rows first, then commits StatusSeq last so the
--   viewer never adopts a partial snapshot.
------------------------------------------------------------

local SeqCounter = 0

function Remote.Publish()
    -- Keep the scanner + heal queue fresh so the published status
    -- (leech HP/status, queue, next target) stays live even while
    -- the cleric's healing is PAUSED (heartbeat is skipped while
    -- paused, but Remote.Pulse runs unconditionally). This only
    -- reads TLO state -- it never casts.
    if Scanner.Scan then
        SafeCall(function() Scanner.Scan() end)
    elseif Scanner.Update then
        SafeCall(function() Scanner.Update() end)
    end
    if HealQueue.Build then
        SafeCall(function() HealQueue.Build(Scanner) end)
    end

    local snap = BuildSnapshot()
    SeqCounter = SeqCounter + 1

    local f = Remote.StatusFile

    -- Per-leech rows first.
    IniWrite(f, Remote.WatchSection, "Count", #snap.Watch)
    for i, w in ipairs(snap.Watch) do
        local sec = Remote.WatchSection .. i
        IniWrite(f, sec, "Name", w.Name)
        IniWrite(f, sec, "Enabled", tostring(w.Enabled))
        IniWrite(f, sec, "HP", w.HP)
        IniWrite(f, sec, "Status", w.Status)
        IniWrite(f, sec, "Distance", w.Distance)
        IniWrite(f, sec, "HealBelowPct", w.HealBelowPct)
    end

    -- Stats.
    IniWrite(f, Remote.StatsSection, "HealsCast",   snap.Stats.HealsCast)
    IniWrite(f, Remote.StatsSection, "Emergencies", snap.Stats.Emergencies)
    IniWrite(f, Remote.StatsSection, "FailedCasts", snap.Stats.FailedCasts)
    IniWrite(f, Remote.StatsSection, "BuffsCast",   snap.Stats.BuffsCast)
    IniWrite(f, Remote.StatsSection, "HotsCast",    snap.Stats.HotsCast)

    -- Header (commit: StatusSeq written LAST).
    IniWrite(f, Remote.StatusSection, "Source",        snap.Source)
    IniWrite(f, Remote.StatusSection, "Updated",        snap.Updated)
    IniWrite(f, Remote.StatusSection, "Enabled",       tostring(snap.Enabled))
    IniWrite(f, Remote.StatusSection, "Paused",        tostring(snap.Paused))
    IniWrite(f, Remote.StatusSection, "PLerHP",        snap.PLerHP)
    IniWrite(f, Remote.StatusSection, "PLerMana",      snap.PLerMana)
    IniWrite(f, Remote.StatusSection, "PLerCasting",   snap.PLerCasting)
    IniWrite(f, Remote.StatusSection, "QueueCount",    snap.QueueCount)
    IniWrite(f, Remote.StatusSection, "NextName",      snap.NextName)
    IniWrite(f, Remote.StatusSection, "NextHP",        snap.NextHP)
    IniWrite(f, Remote.StatusSection, "Medding",       tostring(snap.Medding))
    IniWrite(f, Remote.StatusSection, "FollowStatus",  snap.FollowStatus)
    IniWrite(f, Remote.StatusSection, "FollowEnabled", tostring(snap.FollowEnabled))
    IniWrite(f, Remote.StatusSection, "Buffing",       tostring(snap.Buffing))
    IniWrite(f, Remote.StatusSection, "HotRolling",    tostring(snap.HotRolling))
    IniWrite(f, Remote.StatusSection, "MedBreaks",     tostring(snap.MedBreaks))
    IniWrite(f, Remote.StatusSection, "StatusSeq",     SeqCounter)
end

------------------------------------------------------------
-- SOURCE: poll + apply pending command from the viewer.
------------------------------------------------------------

local function ResolveRow(index, name)
    -- Stale-viewer guard: verify the row at `index` still
    -- matches `name`; if not, fall back to a name lookup so a
    -- command never mutates the wrong leech.
    local players = WatchList.GetPlayers() or {}
    local p = players[index]
    if p and p.Name and p.Name:lower() == (name or ""):lower() then
        return index
    end
    -- fall back: find by name
    if name and name ~= "" then
        for i, q in ipairs(players) do
            if q.Name and q.Name:lower() == name:lower() then
                return i
            end
        end
    end
    return nil
end

function Remote.PollCommand()

    local cmdSeq = tonumber(IniRead(Remote.CmdFile, "Cmd", "Seq", "0")) or 0
    local ackSeq = tonumber(IniRead(Remote.CmdFile, "Ack", "Seq", "0")) or 0

    -- Persisted source of truth: only apply if Cmd.Seq > Ack.Seq.
    if cmdSeq <= ackSeq then
        Remote.SourceAppliedSeq = ackSeq
        return
    end
    -- Already applied this one (runtime guard).
    if cmdSeq <= Remote.SourceAppliedSeq then return end

    local action = IniRead(Remote.CmdFile, "Cmd", "Action", "")
    local a1 = IniRead(Remote.CmdFile, "Cmd", "Arg1", "")
    local a2 = IniRead(Remote.CmdFile, "Cmd", "Arg2", "")
    local a3 = IniRead(Remote.CmdFile, "Cmd", "Arg3", "")
    local applied = false

    if action == "MoveUp" then
        local idx = ResolveRow(tonumber(a1) or 0, a2)
        if idx then WatchList.MoveUp(idx); applied = true end
    elseif action == "MoveDown" then
        local idx = ResolveRow(tonumber(a1) or 0, a2)
        if idx then WatchList.MoveDown(idx); applied = true end
    elseif action == "Add" then
        if WatchList.Add(a1) then applied = true end
    elseif action == "Remove" then
        if WatchList.Remove(a1) then applied = true end
    elseif action == "SetEnabled" then
        local idx = ResolveRow(tonumber(a1) or 0, a2)
        if idx then WatchList.SetEnabled(State.WatchList[idx].Name, toBool(a3)); applied = true end
    elseif action == "SetHealBelowPct" then
        local idx = ResolveRow(tonumber(a1) or 0, a2)
        if idx then WatchList.SetHealBelowPct(idx, tonumber(a3) or 0); applied = true end
    elseif action == "Pause" then
        State.Paused = toBool(a1)
        if State.Paused then Follow.Stop("paused") end
        applied = true
    elseif action == "Follow" then
        State.Settings.FollowEnabled = toBool(a1)
        if not State.Settings.FollowEnabled then Follow.Stop("off") end
        applied = true
    elseif action == "Med" then
        State.Settings.MedBreaks = toBool(a1); applied = true
    elseif action == "Buffs" then
        State.Settings.Buffing = toBool(a1); applied = true
    elseif action == "Hots" then
        State.Settings.HotRolling = toBool(a1); applied = true
    end

    if applied then
        -- Persist watchlist/toggle changes to the cleric's INI.
        WatchList.Save()
        Config.Save()
    end

    -- Ack (commit) -- persists across cleric reloads.
    IniWrite(Remote.CmdFile, "Ack", "Seq", cmdSeq)
    Remote.SourceAppliedSeq = cmdSeq

    if State.Settings.Debug then
        print(string.format("[CLEPLER] remote cmd applied: %s %s/%s/%s",
            action, tostring(a1), tostring(a2), tostring(a3)))
    end
end

------------------------------------------------------------
-- VIEWER: poll status file into Remote.Status cache.
--   Only adopts a snapshot when StatusSeq changes.
------------------------------------------------------------

local lastStatusSeq = -1
local statusChangedAt = 0      -- local mq.gettime() of last adopt

function Remote.PollStatus()

    local seq = tonumber(IniRead(Remote.StatusFile, Remote.StatusSection, "StatusSeq", "0")) or 0
    if seq <= 0 then
        -- No source has published yet (or file is empty). Don't
        -- adopt a fake snapshot -- show "no data" instead.
        Remote.Status = nil
        lastStatusSeq = -1
        statusChangedAt = 0
        return
    end
    if seq == lastStatusSeq then
        return  -- no new snapshot
    end

    -- New snapshot -- adopt it.
    lastStatusSeq = seq
    statusChangedAt = mq.gettime()

    local f = Remote.StatusFile
    local s = {}

    s.Source       = IniRead(f, Remote.StatusSection, "Source", "(no source)")
    s.Updated      = IniRead(f, Remote.StatusSection, "Updated", "0")
    s.Enabled      = toBool(IniRead(f, Remote.StatusSection, "Enabled", "false"))
    s.Paused       = toBool(IniRead(f, Remote.StatusSection, "Paused", "false"))
    s.PLerHP       = tonumber(IniRead(f, Remote.StatusSection, "PLerHP", "0")) or 0
    s.PLerMana     = tonumber(IniRead(f, Remote.StatusSection, "PLerMana", "0")) or 0
    s.PLerCasting  = IniRead(f, Remote.StatusSection, "PLerCasting", "")
    s.QueueCount   = tonumber(IniRead(f, Remote.StatusSection, "QueueCount", "0")) or 0
    s.NextName     = IniRead(f, Remote.StatusSection, "NextName", "")
    s.NextHP       = tonumber(IniRead(f, Remote.StatusSection, "NextHP", "0")) or 0
    s.Medding      = toBool(IniRead(f, Remote.StatusSection, "Medding", "false"))
    s.FollowStatus = IniRead(f, Remote.StatusSection, "FollowStatus", "off")
    s.FollowEnabled= toBool(IniRead(f, Remote.StatusSection, "FollowEnabled", "false"))
    s.Buffing      = toBool(IniRead(f, Remote.StatusSection, "Buffing", "false"))
    s.HotRolling   = toBool(IniRead(f, Remote.StatusSection, "HotRolling", "false"))
    s.MedBreaks    = toBool(IniRead(f, Remote.StatusSection, "MedBreaks", "false"))

    s.Stats = {
        HealsCast   = tonumber(IniRead(f, Remote.StatsSection, "HealsCast", "0")) or 0,
        Emergencies = tonumber(IniRead(f, Remote.StatsSection, "Emergencies", "0")) or 0,
        FailedCasts = tonumber(IniRead(f, Remote.StatsSection, "FailedCasts", "0")) or 0,
        BuffsCast   = tonumber(IniRead(f, Remote.StatsSection, "BuffsCast", "0")) or 0,
        HotsCast    = tonumber(IniRead(f, Remote.StatsSection, "HotsCast", "0")) or 0,
    }

    local count = tonumber(IniRead(f, Remote.WatchSection, "Count", "0")) or 0
    s.Watch = {}
    for i = 1, count do
        local sec = Remote.WatchSection .. i
        table.insert(s.Watch, {
            Name         = IniRead(f, sec, "Name", "?"),
            Enabled      = toBool(IniRead(f, sec, "Enabled", "false")),
            HP           = tonumber(IniRead(f, sec, "HP", "0")) or 0,
            Status       = IniRead(f, sec, "Status", "unknown"),
            Distance     = tonumber(IniRead(f, sec, "Distance", "0")) or 0,
            HealBelowPct = tonumber(IniRead(f, sec, "HealBelowPct", "0")) or 0,
        })
    end

    Remote.Status = s

    -- Also refresh ack tracking for pending commands.
    local ackSeq = tonumber(IniRead(Remote.CmdFile, "Ack", "Seq", "0")) or 0
    if ackSeq > Remote.LastAppliedAck then
        Remote.LastAppliedAck = ackSeq
        if Remote.LastSentSeq > 0 and ackSeq >= Remote.LastSentSeq then
            -- Our pending command was acked.
            Remote.LastSentSeq  = 0
            Remote.PendingSince = 0
        end
    end
end

-- Local adopt time (ms) of the current cached snapshot, for
-- staleness display.
function Remote.StatusAgeMs()
    if statusChangedAt == 0 then return -1 end
    return mq.gettime() - statusChangedAt
end

------------------------------------------------------------
-- VIEWER: send a command to the cleric.
--   Writes Action/Args first, then Seq LAST (commit).
------------------------------------------------------------

function Remote.Pending()
    return Remote.LastSentSeq > 0
end

function Remote.PendingAgeMs()
    if Remote.PendingSince == 0 then return 0 end
    return mq.gettime() - Remote.PendingSince
end

function Remote.SendCommand(action, a1, a2, a3)

    -- Determine next seq: max(Cmd.Seq, Ack.Seq) + 1.
    local cmdSeq = tonumber(IniRead(Remote.CmdFile, "Cmd", "Seq", "0")) or 0
    local ackSeq = tonumber(IniRead(Remote.CmdFile, "Ack", "Seq", "0")) or 0
    local nextSeq = math.max(cmdSeq, ackSeq) + 1
    if nextSeq <= Remote.LastSentSeq then
        nextSeq = Remote.LastSentSeq + 1
    end

    local f = Remote.CmdFile
    IniWrite(f, "Cmd", "Action", action or "")
    IniWrite(f, "Cmd", "Arg1", a1 or "")
    IniWrite(f, "Cmd", "Arg2", a2 or "")
    IniWrite(f, "Cmd", "Arg3", a3 or "")
    -- Commit last.
    IniWrite(f, "Cmd", "Seq", nextSeq)

    Remote.LastSentSeq  = nextSeq
    Remote.PendingSince = mq.gettime()
end

------------------------------------------------------------
-- Pulse (called UNCONDITIONALLY from init.lua). Branches by
-- role so status/commands work even while healing is paused.
------------------------------------------------------------

function Remote.Pulse()

    local role = State.RemoteEffectiveRole
    if role ~= "source" and role ~= "viewer" then
        return
    end

    local now = mq.gettime()

    if role == "source" then
        if now - Remote.LastPublish >= 1000 then
            Remote.Publish()
            Remote.LastPublish = now
        end
        if now - Remote.LastCmdPoll >= 500 then
            Remote.PollCommand()
            Remote.LastCmdPoll = now
        end
    else -- viewer
        if now - Remote.LastStatusPoll >= 500 then
            Remote.PollStatus()
            Remote.LastStatusPoll = now
        end
    end
end

------------------------------------------------------------
-- Role setter (used by commands + UI). "source"/"viewer"/"off".
------------------------------------------------------------

function Remote.SetRole(role)
    if role ~= "source" and role ~= "viewer" and role ~= "off" then
        return false
    end
    State.Settings.RemoteRole = role
    Config.Save()
    -- Reset viewer command state on role change.
    if role ~= "viewer" then
        Remote.LastSentSeq    = 0
        Remote.PendingSince   = 0
    end
    if role == "source" then
        -- Re-seed source applied-seq from the persisted ack so a
        -- reload doesn't reapply the last command.
        local ackSeq = tonumber(IniRead(Remote.CmdFile, "Ack", "Seq", "0")) or 0
        Remote.SourceAppliedSeq = ackSeq
    end
    print(string.format("[CLEPLER] remote role = %s", role))
    return true
end

return Remote
