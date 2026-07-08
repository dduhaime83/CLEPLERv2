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
local Config    = require('config')
local Spellbook = require('spellbook')
local Hots      = require('hots')
local Follow    = require('follow')
local Loadout   = require('loadout')
local Remote   = require('remote')

local Commands = {}

local bound = false

------------------------------------------------------------
-- Usage
------------------------------------------------------------

local function Usage()
    print("[CLEPLER] usage: /clepler on|off|pause|ui|reloadspells" ..
          "|add <name>|remove <name>|mem <gem> <spell>|memall|debug|test|buffs|hots|med|follow|remote <off|source|viewer>|status|quit")
end

------------------------------------------------------------
-- Status dump
------------------------------------------------------------

local function Status()
    print(string.format("[CLEPLER] v%s  enabled=%s  paused=%s  test=%s  buffs=%s  hots=%s  med=%s  follow=%s",
        tostring(State.Version),
        tostring(State.Enabled),
        tostring(State.Paused),
        tostring(State.Settings.TestMode),
        tostring(State.Settings.Buffing),
        tostring(State.Settings.HotRolling),
        tostring(State.Settings.MedBreaks),
        tostring(State.Settings.FollowEnabled)))
    print(string.format("[CLEPLER] follow status: %s", Follow.Status()))
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
        Follow.Stop("off")
        print("[CLEPLER] healing disabled")

    elseif cmd == "pause" then
        State.Paused = not State.Paused
        if State.Paused then
            Follow.Stop("paused")
        end
        print(string.format("[CLEPLER] %s", State.Paused and "PAUSED" or "resumed"))

    elseif cmd == "ui" then
        Window.Open = not Window.Open

    elseif cmd == "reloadspells" then
        Spells.Refresh()
        Spellbook.Refresh()

    elseif cmd == "mem" then
        -- /clepler mem <gem> <spell name...>
        local gem = args[2]
        local name = nil
        if args[3] then
            -- concatenate the rest of the spell name
            local parts = {}
            for i = 3, #args do
                table.insert(parts, args[i])
            end
            name = table.concat(parts, " ")
        end
        if not gem or not name or name == "" then
            print("[CLEPLER] usage: /clepler mem <gem 1-12> <spell name>")
        else
            if Spellbook.Memorize(name, gem) then
                if not State.Settings.TestMode then
                    print("[CLEPLER] run /clepler reloadspells once it lands")
                end
            else
                print("[CLEPLER] mem failed (spell not in book or bad gem)")
            end
        end

    elseif cmd == "memall" then
        -- /clepler memall [cancel]
        if args[2] == "cancel" then
            Loadout.Cancel("manual")
        else
            Loadout.MemAll()
        end

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

    elseif cmd == "buffs" then
        State.Settings.Buffing = not State.Settings.Buffing
        print(string.format("[CLEPLER] buffing=%s",
            tostring(State.Settings.Buffing)))
        Config.Save()

    elseif cmd == "hots" then
        State.Settings.HotRolling = not State.Settings.HotRolling
        print(string.format("[CLEPLER] hot rolling=%s",
            tostring(State.Settings.HotRolling)))
        Config.Save()

    elseif cmd == "med" then
        State.Settings.MedBreaks = not State.Settings.MedBreaks
        print(string.format("[CLEPLER] med breaks=%s",
            tostring(State.Settings.MedBreaks)))
        Config.Save()

    elseif cmd == "follow" then
        State.Settings.FollowEnabled = not State.Settings.FollowEnabled
        if not State.Settings.FollowEnabled then
            Follow.Stop("off")
        end
        print(string.format("[CLEPLER] follow=%s  (%s)",
            tostring(State.Settings.FollowEnabled), Follow.Status()))
        Config.Save()

    elseif cmd == "remote" then
        local role = args[2]
        if role == "off" or role == "source" or role == "viewer" then
            Remote.SetRole(role)
            print(string.format(
                "[CLEPLER] remote role set to '%s' (reload CLEPLER for it to take full effect)", role))
        else
            print("[CLEPLER] usage: /clepler remote <off|source|viewer>")
        end

    elseif cmd == "status" then
        Status()

    elseif cmd == "quit" or cmd == "exit" then
        Loadout.Cancel("quit")
        Follow.Stop("quit")
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
