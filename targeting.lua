------------------------------------------------------------
-- CLEPLER
-- targeting.lua
--
-- Centralized target operations. Keeps spawn-target save/
-- restore logic in one place so the caster (and future
-- modules) don't each hand-roll it.
--
-- MQ2 API:
--   /target id <id>        -- target a spawn by id
--   /target clear         -- drop target
--   mq.TLO.Target.ID()    -- current target id (0 if none)
------------------------------------------------------------

local mq        = require('mq')
local State     = require('state')

local Targeting = {}

------------------------------------------------------------
-- pcall wrapper (TLO access can throw on stale/invalid data)
------------------------------------------------------------

local function SafeCall(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

------------------------------------------------------------
-- Target a spawn by id
------------------------------------------------------------

function Targeting.Set(id)
    if not id then return end
    mq.cmd("/target id " .. tostring(id))
end

------------------------------------------------------------
-- Clear the current target
------------------------------------------------------------

function Targeting.Clear()
    mq.cmd("/target clear")
end

------------------------------------------------------------
-- Current target id (0 or nil if none)
------------------------------------------------------------

function Targeting.CurrentID()
    local id = SafeCall(function() return mq.TLO.Target.ID() end)
    return tonumber(id) or 0
end

------------------------------------------------------------
-- Save the current target id for later restoration.
-- Returns the id (or nil if there is no target).
------------------------------------------------------------

function Targeting.Save()
    local id = Targeting.CurrentID()
    if id and id > 0 then
        return id
    end
    return nil
end

------------------------------------------------------------
-- Restore a previously saved target. No-op for nil/invalid ids
-- so callers can pass through whatever Save() returned.
------------------------------------------------------------

function Targeting.Restore(id)
    id = tonumber(id)
    if id and id > 0 then
        Targeting.Set(id)
    end
end

return Targeting
