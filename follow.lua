------------------------------------------------------------
-- CLEPLER
-- follow.lua
--
-- Auto-follow the priority (top enabled) leech via MQ2MoveUtils
-- /stick id <spawnid> <dist>. Keeps the PLer glued to the leech
-- so the operator doesn't have to manually chase during a
-- powerleveling session.
--
-- Safety first -- following never preempts a heal:
--   * Movement breaks spell casts in EQ, so the shared cast path
--     (caster.lua) calls Follow.PauseForCast() -> /stick off
--     immediately before any /cast. The next Pulse re-sticks once
--     the cast is done and conditions allow.
--   * Follow stops entirely while: disabled, paused, medding
--     (don't break a med break to chase), dead, in combat (the
--     PLer should stand & heal, not chase), or mid-cast.
--
-- MQ2MoveUtils API (verified):
--   /stick id <#> <dist>   stick to spawn id # at <dist> units
--   /stick off             stop sticking
--   /stick id holds through target changes (good for healing)
--   ERROR if SpawnID is not a positive integer, so we validate.
------------------------------------------------------------

local mq       = require('mq')
local State    = require('state')
local WatchList = require('watchlist')
local Scanner  = require('scanner')
local Med      = require('med')

local Follow = {}

-- Runtime state
Follow.Active        = false   -- are we currently issuing /stick?
Follow.LastSpawnID   = 0       -- last spawn id we stuck to
Follow.LastName      = ""      -- name of that spawn (for UI)
Follow.LastDistance  = -1      -- last distance we issued (re-stick on change)
Follow.LastStickAt   = 0       -- ms of last /stick issue (keepalive throttle)
Follow.StoppedReason = "off"   -- why we're not following (for UI)

------------------------------------------------------------
-- pcall wrapper
------------------------------------------------------------

local function SafeCall(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

------------------------------------------------------------
-- Self-state reads
------------------------------------------------------------

local function AmCasting()
    local c = SafeCall(function() return mq.TLO.Me.Casting() end)
    return c ~= nil and c ~= ""
end

local function AmDead()
    return SafeCall(function() return mq.TLO.Me.Dead() end) == true
end

local function InCombat()
    local cs = SafeCall(function() return mq.TLO.Me.CombatState() end)
    return cs == "COMBAT"
end

local function MyID()
    local v = SafeCall(function() return mq.TLO.Me.ID() end)
    return tonumber(v) or 0
end

------------------------------------------------------------
-- Resolve the priority (top enabled) leech to a scanner record.
-- Re-resolved every pulse so priority changes (add/remove/
-- reorder) and zoning are picked up immediately.
------------------------------------------------------------

local function PriorityLeech()
    local players = WatchList.GetPlayers() or {}
    for _, p in ipairs(players) do
        if p.Enabled and p.Name and p.Name ~= "" then
            local rec = Scanner.FindByName(p.Name)
            if rec and rec.ID and rec.ID > 0 and not rec.Dead then
                return rec
            end
        end
    end
    return nil
end

------------------------------------------------------------
-- Stop following. Only issues /stick off if we believe we were
-- actually sticking (avoids command spam). Always records the
-- reason so the UI can show why we're idle.
------------------------------------------------------------

function Follow.Stop(reason)
    if Follow.Active then
        mq.cmd("/stick off")
        Follow.Active      = false
        Follow.LastSpawnID = 0
    end
    if reason then
        Follow.StoppedReason = reason
    end
end

------------------------------------------------------------
-- Called by the shared cast path (caster.lua) right before a
-- cast. Movement interrupts spell casting in EQ, so we must be
-- standing still. Always safe to call; no-ops if not following.
------------------------------------------------------------

function Follow.PauseForCast()
    Follow.Stop("casting")
end

function Follow.IsFollowing()
    return Follow.Active
end

------------------------------------------------------------
-- Human-readable status for the UI.
--   "off" | "paused" | "medding" | "combat" | "casting"
--   | "dead" | "no target" | "following:<name>"
------------------------------------------------------------

function Follow.Status()
    if not State.Enabled then return "off" end
    if not State.Settings.FollowEnabled then return "off" end
    if State.Paused then return "paused" end
    if Med.IsMedding() then return "medding" end
    if InCombat() then return "combat" end
    if AmDead() then return "dead" end
    if Follow.Active then
        return "following:" .. (Follow.LastName or "?")
    end
    return Follow.StoppedReason or "idle"
end

------------------------------------------------------------
-- Pulse (Heartbeat entry point, ~1000ms).
--   Re-sticks only when needed: target changed, we weren't
--   following, the distance setting changed, or a keepalive
--   interval elapsed. Avoids issuing /stick every pulse.
------------------------------------------------------------

function Follow.Pulse()

    if not State.Enabled then Follow.Stop("off"); return end
    if not State.Settings.FollowEnabled then Follow.Stop("off"); return end
    if State.Paused then Follow.Stop("paused"); return end

    -- Medding: stay seated, don't chase. Do NOT stand here --
    -- the med module owns posture and will stand at the ceiling
    -- or on combat aggro.
    if Med.IsMedding() then Follow.Stop("medding"); return end

    if AmDead() then Follow.Stop("dead"); return end

    -- Combat: stop chasing so the PLer can stand and heal.
    -- (Med.Break() also stands on combat, but that runs on its
    -- own 1000ms pulse; stopping follow here is immediate.)
    if InCombat() then Follow.Stop("combat"); return end

    -- Don't issue movement commands mid-cast.
    if AmCasting() then Follow.Stop("casting"); return end

    -- Resolve the priority leech.
    local rec = PriorityLeech()
    if not rec then Follow.Stop("no target"); return end

    -- Never follow ourselves or our mount (MQ2 errors on it).
    if rec.ID == MyID() then Follow.Stop("self"); return end

    local dist = tonumber(State.Settings.FollowDistance) or 20
    if dist < 1 then dist = 1 end
    local id   = rec.ID

    -- Re-issue /stick only when something changed or as a
    -- keepalive. Keeps command chatter down.
    local now = mq.gettime()
    local needStick = false
    if not Follow.Active then needStick = true end
    if Follow.LastSpawnID ~= id then needStick = true end
    if Follow.LastDistance ~= dist then needStick = true end
    if now - Follow.LastStickAt > 8000 then needStick = true end

    if needStick then
        mq.cmd(string.format("/stick id %d %d", id, dist))
        Follow.Active       = true
        Follow.LastSpawnID  = id
        Follow.LastName     = rec.Name
        Follow.LastDistance = dist
        Follow.LastStickAt  = now
        Follow.StoppedReason = ""
    end
end

return Follow
