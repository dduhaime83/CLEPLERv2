--========================================================--
-- healprofiles.lua
--
-- CLEPLER
-- Healing profile definitions.
--
-- Responsibilities:
--   * Define spell priorities
--   * Define heal thresholds
--   * Define emergency heals
--   * Define HoTs
--   * Define group heals
--   * Define cures
--
-- This module contains only data and lookup helpers.
--========================================================--

local Profiles = {}

------------------------------------------------------------
-- Default Profile
------------------------------------------------------------

Profiles.Default = {

    --------------------------------------------------------
    -- Thresholds
    --------------------------------------------------------

    Thresholds = {

        Emergency = 20,
        Fast = 40,
        Big = 65,
        Light = 85,
        Group = 70,
        HoT = 90,

        Cure = true,
    },

    --------------------------------------------------------
    -- Emergency
    --------------------------------------------------------

    Emergency = {

        {
            Name = "Divine Arbitration",
            Type = "AA",
        },

        {
            Name = "Burst of Life",
            Type = "AA",
        },

        {
            Name = "Complete Heal",
            Type = "Spell",
        },

    },

    --------------------------------------------------------
    -- Fast Heals
    --------------------------------------------------------

    Fast = {

        {
            Name = "Remedy",
            Type = "Spell",
        },

        {
            Name = "Graceful Remedy",
            Type = "Spell",
        },

        {
            Name = "Mystical Intervention",
            Type = "Spell",
        },

    },

    --------------------------------------------------------
    -- Big Heals
    --------------------------------------------------------

    Big = {

        {
            Name = "Complete Heal",
            Type = "Spell",
        },

        {
            Name = "Light",
            Type = "Spell",
        },

        {
            Name = "Superior Healing",
            Type = "Spell",
        },

    },

    --------------------------------------------------------
    -- Light Heals
    --------------------------------------------------------

    Light = {

        {
            Name = "Light Healing",
            Type = "Spell",
        },

        {
            Name = "Healing",
            Type = "Spell",
        },

        {
            Name = "Minor Healing",
            Type = "Spell",
        },

    },

    --------------------------------------------------------
    -- Heal over Time
    --------------------------------------------------------

    HoT = {

        {
            Name = "Celestial Renewal",
            Type = "Spell",
        },

        {
            Name = "Elixir",
            Type = "Spell",
        },

    },

    --------------------------------------------------------
    -- Group Healing
    --------------------------------------------------------

    Group = {

        {
            Name = "Word of Health",
            Type = "Spell",
        },

        {
            Name = "Word of Healing",
            Type = "Spell",
        },

        {
            Name = "Beacon of Life",
            Type = "AA",
        },

    },

    --------------------------------------------------------
    -- Cures
    --------------------------------------------------------

    Cure = {

        Poison = {

            {
                Name = "Counteract Poison",
                Type = "Spell",
            },

        },

        Disease = {

            {
                Name = "Counteract Disease",
                Type = "Spell",
            },

        },

        Curse = {

            {
                Name = "Remove Greater Curse",
                Type = "Spell",
            },

        },

        Corruption = {

            {
                Name = "Purify Soul",
                Type = "AA",
            },

        },

    },

    --------------------------------------------------------
    -- Resurrection
    --------------------------------------------------------

    Resurrection = {

        {
            Name = "Resurrection",
            Type = "Spell",
        },

        {
            Name = "Reviviscence",
            Type = "Spell",
        },

    },

    --------------------------------------------------------
    -- Buffs
    --------------------------------------------------------

    Buffs = {

        "Symbol",
        "Armor",
        "Aegolism",
        "Temperance",
    },

}

------------------------------------------------------------
-- Active Profile
------------------------------------------------------------

Profiles.Active = Profiles.Default

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

function Profiles.Get()
    return Profiles.Active
end

function Profiles.Set(profile)

    if profile then
        Profiles.Active = profile
    end

end

function Profiles.Reset()

    Profiles.Active = Profiles.Default

end

------------------------------------------------------------
-- Section lookup
------------------------------------------------------------

function Profiles.Section(name)

    return Profiles.Active[name]

end

------------------------------------------------------------
-- Threshold lookup
------------------------------------------------------------

function Profiles.Threshold(name)

    return Profiles.Active.Thresholds[name]

end

------------------------------------------------------------
-- Iterate a spell list
------------------------------------------------------------

function Profiles.ForEach(section, callback)

    local list = Profiles.Active[section]

    if not list then
        return
    end

    for _, spell in ipairs(list) do
        callback(spell)
    end

end

------------------------------------------------------------
-- Get cure list
------------------------------------------------------------

function Profiles.CureList(typeName)

    return Profiles.Active.Cure[typeName]

end

------------------------------------------------------------
-- Get buff list
------------------------------------------------------------

function Profiles.Buffs()

    return Profiles.Active.Buffs

end

------------------------------------------------------------
-- Is cures enabled?
------------------------------------------------------------

function Profiles.UseCures()

    return Profiles.Active.Thresholds.Cure

end

------------------------------------------------------------
-- Clone profile
------------------------------------------------------------

function Profiles.Clone()

    local function copy(tbl)

        local new = {}

        for k, v in pairs(tbl) do

            if type(v) == "table" then
                new[k] = copy(v)
            else
                new[k] = v
            end

        end

        return new
    end

    return copy(Profiles.Active)

end

return Profiles