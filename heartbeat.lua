------------------------------------------------------------
-- CLEPLER
--
-- heartbeat.lua
------------------------------------------------------------

local mq = require('mq')

local Heartbeat = {}

Heartbeat.Tasks = {}

function Heartbeat.Register(name, interval, callback)

    if type(callback) ~= "function" then
        print(string.format("[CLEPLER] Skipping Heartbeat '%s' (missing callback)", name))
        return
    end

    Heartbeat.Tasks[name] = {
        Name = name,
        Interval = interval,
        Callback = callback,
        LastRun = 0,
        Enabled = true,
    }

    print(string.format("[CLEPLER] Registered Heartbeat '%s'", name))
end

function Heartbeat.Remove(name)
    Heartbeat.Tasks[name] = nil
end

function Heartbeat.Enable(name)
    if Heartbeat.Tasks[name] then
        Heartbeat.Tasks[name].Enabled = true
    end
end

function Heartbeat.Disable(name)
    if Heartbeat.Tasks[name] then
        Heartbeat.Tasks[name].Enabled = false
    end
end

function Heartbeat.Pulse()

    local now = mq.gettime()

    for _, task in pairs(Heartbeat.Tasks) do

        if task.Enabled and (now - task.LastRun) >= task.Interval then

            task.LastRun = now

            local ok, err = pcall(task.Callback)

            if not ok then
                print(string.format("[CLEPLER] Heartbeat '%s' failed:", task.Name))
                print(err)
            end

        end

    end

end

return Heartbeat
