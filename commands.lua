------------------------------------------------------------
-- CLEPLER
-- commands.lua
--
-- Binds the /clepler slash command and routes subcommands.
------------------------------------------------------------

local mq        = require('mq')
local State     = require('state')
local Window    = require('window')
local Spells    = require('spells')
local WatchList = require('watchlist')

local Commands = {}

local bound = false

------------------------------------------------------------
-- Usage
------------------------------------------------------------

local function Usage()
    print("[CLEPLER] usage: /clepler on|off|pause|ui|reloadspells" ..
          "|add <name>|remove <name>|debug|test|status|quit")
end

------------------------------------------------------------
-- Status dump
------------------------------------------------------------

local function Status()
    print(string.format("[CLEPLER] v%s  enabled=%s  paused=%s  test=%s",
        tostring(State.Version),
        tostring(State.Enabled),
        tostring(State.Paused),
        tostring(State.Settings.TestMode)))
    print(string.format("[CLEPLER] watchlist entries: %d",
        #(WatchList.GetPlayers() or {})))
end

------------------------------------------------------------
-- Handler
------------------------------------------------------------

local function Handler(...)
    local args = { ... }
    local cmd  = args[1]

    if not cmd or cmd == "" then
        Usage()
        return

    elseif cmd == "on" then
        State.Enabled = true
        print("[CLEPLER] healing ENABLED")

    elseif cmd == "off" then
        State.Enabled = false
        print("[CLEPLER] healing disabled")

    elseif cmd == "pause" then
        State.Paused = not State.Paused
        print(string.format("[CLEPLER] %s", State.Paused and "PAUSED" or "resumed"))

    elseif cmd == "ui" then
        Window.Open = not Window.Open

    elseif cmd == "reloadspells" then
        Spells.Refresh()

    elseif cmd == "add" then
        local name = args[2]
        if WatchList.Add(name) then
            print(string.format("[CLEPLER] added '%s' to watchlist", name))
            WatchList.Save()
        else
            print("[CLEPLER] add failed (missing or duplicate name)")
        end

    elseif cmd == "remove" then
        local name = args[2]
        if WatchList.Remove(name) then
            print(string.format("[CLEPLER] removed '%s' from watchlist", name or ""))
            WatchList.Save()
        else
            print("[CLEPLER] remove failed (not found)")
        end

    elseif cmd == "debug" then
        State.Settings.Debug = not State.Settings.Debug
        print(string.format("[CLEPLER] debug=%s", tostring(State.Settings.Debug)))

    elseif cmd == "test" then
        State.Settings.TestMode = not State.Settings.TestMode
        print(string.format("[CLEPLER] testmode=%s (dry run, no casts)",
            tostring(State.Settings.TestMode)))

    elseif cmd == "status" then
        Status()

    elseif cmd == "quit" or cmd == "exit" then
        State.Running = false
        print("[CLEPLER] shutting down")

    else
        Usage()
    end
end

------------------------------------------------------------
-- Register / Unregister
------------------------------------------------------------

function Commands.Register()
    if bound then return end
    mq.bind("/clepler", Handler)
    bound = true
    print("[CLEPLER] bound /clepler")
end

function Commands.Unregister()
    if not bound then return end
    pcall(mq.unbind, "/clepler")
    bound = false
end

return Commands
