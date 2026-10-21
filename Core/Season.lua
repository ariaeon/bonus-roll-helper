-- Bonus Roll Helper: current-season definition.
-- Only IDs live here; names, boss order and loot are read from the Encounter
-- Journal at runtime so the addon stays localized and follows hotfixes.
-- Update this file when a new season starts.
local _, BRH = ...

BRH.Season = {
    name = "Midnight Season 2",

    -- Nebulous Voidcore
    currencyID = 3418,

    -- Raids: journal instance ID and, per journal encounter ID, the Nebulous
    -- Voidcache item ID that the bonus roll prompt (and Simulationcraft's
    -- "source" field) reports for that boss.
    raids = {
        {
            journalInstanceID = 1320, -- The Venomous Abyss
            voidcaches = {
                [2888] = 278285, -- Nek'zali the Soulcoiler
                [2874] = 278283, -- Entombed Sentinels
                [2894] = 278286, -- The Lost Explorers
                [2882] = 278287, -- Vashnik the Malignant
                [2871] = 278288, -- Sszorak
                [2887] = 278289, -- The Twin Fangs
                [2883] = 278290, -- The Coiled Altar
                [2895] = 278284 -- Ula'tek
            }
        },
        {
            journalInstanceID = 1317, -- The Tidebound Grotto
            voidcaches = {
                [2849] = 274708 -- Nymrissa Wavecaller
            }
        },
        {
            journalInstanceID = 1324, -- The Unbinding of Kith'ix (12.1.5)
            voidcaches = {
                [2896] = 286019 -- Kith'ix
            }
        }
    },

    -- Mythic+ dungeons: the whole dungeon is one Voidcore pool.
    -- challengeMapID is only used for the dungeon icon.
    dungeons = {
        { journalInstanceID = 1322, challengeMapID = 588, voidcache = 279618 }, -- Altar of Fangs
        { journalInstanceID = 1311, challengeMapID = 586, voidcache = 279620 }, -- Den of Nalorakk
        { journalInstanceID = 1304, challengeMapID = 587, voidcache = 279623 }, -- Murder Row
        { journalInstanceID = 1309, challengeMapID = 584, voidcache = 279619 }, -- The Blinding Vale
        { journalInstanceID = 1313, challengeMapID = 585, voidcache = 279625 }, -- Voidscar Arena
        { journalInstanceID = 1041, challengeMapID = 249, voidcache = 279621 }, -- Kings' Rest
        { journalInstanceID = 1202, challengeMapID = 399, voidcache = 279622 }, -- Ruby Life Pools
        { journalInstanceID = 1030, challengeMapID = 250, voidcache = 279624 } -- Temple of Sethraliss
    },

    -- Items the Encounter Journal lists that a Nebulous Voidcache never awards.
    -- Non-equipment ("Other" slot) entries are dropped automatically.
    excludedItems = {
        [258045] = true, -- Murder Row
        [270909] = true, -- Ula'tek
        [275937] = true, -- The Coiled Altar
        [275938] = true, -- The Coiled Altar (Mythic)
        [281227] = true -- Nek'zali the Soulcoiler
    }
}
