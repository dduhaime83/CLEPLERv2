------------------------------------------------------------
-- CLEPLER
-- healer.lua
--
-- Heal decision engine. Runs on a fast Heartbeat (~25ms).
-- Consumes the triage queue built by Engine.Pulse and casts
-- the best available heal on the top-priority target.
--
-- Pipeline:
--   Scanner.Scan (group scan)
--     -> Engine.Pulse (HealQueue.Build)
--       -> Healer.Pulse (pick spell + Caster.Cast)
------------------------------------------------------------

local mq        = require('mq')
local State     = require('state')
local Scanner   = require('scanner')
local HealQueue = require('healqueue')
local Profiles  = require('healprofiles')
local Spells    = require('spells')
local Caster    = require('caster')

local Healer = {}

------------------------------------------------------------
-- Pick a spell for a queued entry.
--
-- v1 supports memorized Spells only; AA entries (Type ~= "Spell")
-- are skipped because /cast <gem> cannot fire them.
--
-- NOTE: UseFastHeal / UseBigHeal / UseCompleteHeal flags are reserved
-- for a later refinement (per-spell-name gating); today every spell
-- in the chosen section is considered.
--
-- Selection (safe for low-HP leeches -- avoids leading with
-- Complete Heal, which is too slow for tiny HP pools):
--   HP <= FastHealPct -> Fast, Light, Big
--   HP <= BigHealPct  -> Big, Light, Fast
--   else (queued top-up):
--       UseHoT -> HoT, Light
--       else   -> Light, Fast
-- Returns spellName, profileEntry or nil.
------------------------------------------------------------

local function PickSpell(entry)

    if not entry then return nil end

    local hp = entry.HP or 100
    local s  = State.Settings

    local order
    if hp <= s.FastHealPct then
        order = { "Fast", "Light", "Big" }
    elseif hp <= s.BigHealPct then
        order = { "Big", "Light", "Fast" }
    elseif s.UseHoT and hp <= s.HoTPct then
        order = { "HoT", "Light" }
    else
        order = s.UseHoT and { "HoT", "Light" } or { "Light", "Fast" }
    end

    for _, sectionName in ipairs(order) do

        local list = Profiles.Section(sectionName)
        if type(list) == "table" then

            for _, sp in ipairs(list) do

                if sp and sp.Type == "Spell" and sp.Name then
                    if Spells.Has(sp.Name) and Spells.Ready(sp.Name) then
                        return sp.Name, sp
                    end
                end

            end

        end

    end

    return nil
end

------------------------------------------------------------
-- Pulse
------------------------------------------------------------

function Healer.Pulse()

    if not State.Enabled then return end
    if HealQueue.Empty() then return end

    local entry = HealQueue.Next()
    if not entry then return end

    -- Reset per-pulse so LastError reflects only this attempt.
    State.LastError = ""

    local spellName, sp = PickSpell(entry)
    if not spellName then
        State.LastError = "no ready heal for " .. tostring(entry.Name)
        return
    end

    local ok = Caster.Cast(spellName, entry.ID, sp)

    if ok then
        -- Count an emergency only when we actually acted on one
        -- (cast or dry-run), not every pulse it sits atop the
        -- queue while the caster is throttled.
        if entry.Tier == 1000 or entry.Tier == 900 or entry.Tier == 600 then
            State.Stats.Emergencies = State.Stats.Emergencies + 1
        end
    else
        -- Only count genuine failures (memorized/ready/mana/range/LOS).
        -- Throttle, already-casting, and stunned return false without
        -- setting LastError, so they don't inflate the counter.
        if State.LastError ~= "" then
            State.Stats.FailedCasts = State.Stats.FailedCasts + 1
        end
    end

end

return Healer
