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

        -- Proactive rolling HoTs. Listed highest preference
        -- first. Match is a substring fallback against the
        -- memorized spell name (e.g. "Celestial" matches
        -- "Celestial Renewal"). Category="Hot" routes the cast
        -- counter to State.Stats.HotsCast (see caster.lua).
        {
            Name = "Celestial Renewal",
            Match = "Celestial",
            Type = "Spell",
            Category = "Hot",
        },

        {
            Name = "Elixir",
            Match = "Elixir",
            Type = "Spell",
            Category = "Hot",
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

        -- Combo HP+AC line. These supersede the standalone
        -- Symbol (hp) and Armor (ac) lines, so they are listed
        -- first (highest preference). Higher Rank wins within a
        -- line; a fresh same-line buff of equal/higher rank, or
        -- any fresh buff that Supersedes this entry's Line,
        -- suppresses re-casting.
        --
        -- LEVEL-AWARE FRAMEWORK: MinLevel is the recipient's
        -- minimum level to receive the buff. The values below are
        -- conservative placeholders -- tune them to your server's
        -- ruleset (e.g. Aegolism commonly requires a level 45+
        -- target). Match is a substring fallback against the
        -- memorized spell name (e.g. "Symbol" matches
        -- "Symbol of Ryltan").
        {
            Name = "Aegolism",
            Match = "Aegolism",
            MinLevel = 45,
            Line = "hp_ac",
            Rank = 2,
            Supersedes = { "hp", "ac" },
            Type = "Spell",
            Category = "Buff",
        },
        {
            Name = "Temperance",
            Match = "Temperance",
            MinLevel = 1,
            Line = "hp_ac",
            Rank = 1,
            Supersedes = { "hp", "ac" },
            Type = "Spell",
            Category = "Buff",
        },
        {
            Name = "Symbol",
            Match = "Symbol",
            MinLevel = 1,
            Line = "hp",
            Rank = 1,
            Type = "Spell",
            Category = "Buff",
        },
        {
            Name = "Armor",
            Match = "Armor",
            MinLevel = 1,
            Line = "ac",
            Rank = 1,
            Type = "Spell",
            Category = "Buff",
        },

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
-- Get HoT list
------------------------------------------------------------

function Profiles.Hots()

    return Profiles.Active.HoT

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