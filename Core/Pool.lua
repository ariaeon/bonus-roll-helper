-- Bonus Roll Helper: season sources and Voidcore loot pools.
--
-- A "source" is something a Voidcore can be spent on: a raid boss or a whole
-- Mythic+ dungeon.  A "bucket" is the difficulty a pool is tracked on:
--   raid    → EJ difficulty ID (17 LFR, 14 Normal, 15 Heroic, 16 Mythic)
--   dungeon → "hero" (keys below +10) or "myth" (+10 and up)
--
-- Pools are read from the Encounter Journal per class spec.  EJ_GetNumLoot()
-- returns partial or empty results until the item data is cached, so reads are
-- queued and retried until complete, one read per tick.
local _, BRH = ...

local Pool = {}
BRH.Pool = Pool

local DUNGEON_EJ_DIFFICULTY = 23 -- Mythic; M+ loot tables are the same list
local TICK_DELAY = 0.05
local RETRY_DELAY = 0.3
local BLOCKED_DELAY = 0.5
local MAX_ATTEMPTS = 10

Pool.RAID_DIFFICULTIES = { 17, 14, 15, 16 }
Pool.KEY_TIERS = { "hero", "myth" }

-- ── Sources ───────────────────────────────────────────────────────────────────

Pool.sections = {} -- { { title, kind, sources = { source, ... } }, ... }
local sourcesByKey = {}
local sourcesByVoidcache = {}

local function AddSource(section, source)
    table.insert(section.sources, source)
    sourcesByKey[source.key] = source
    if source.voidcacheID then
        sourcesByVoidcache[source.voidcacheID] = source
    end
end

-- order: the boss's position in the raid (shown as its row badge).
local function MakeRaidSource(raid, encounterID, name, instanceName, order)
    return {
        key = "R:" .. encounterID,
        kind = "raid",
        journalInstanceID = raid.journalInstanceID,
        encounterID = encounterID,
        name = name or ("Encounter " .. encounterID),
        instanceName = instanceName,
        voidcacheID = raid.voidcaches[encounterID],
        order = order
    }
end

local function MakeDungeonSource(dungeon)
    local name = EJ_GetInstanceInfo(dungeon.journalInstanceID)
    local icon
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and dungeon.challengeMapID then
        icon = select(4, C_ChallengeMode.GetMapUIInfo(dungeon.challengeMapID))
    end
    return {
        key = "D:" .. dungeon.journalInstanceID,
        kind = "dungeon",
        journalInstanceID = dungeon.journalInstanceID,
        name = name or ("Dungeon " .. dungeon.journalInstanceID),
        instanceName = name,
        voidcacheID = dungeon.voidcache,
        icon = icon
    }, name ~= nil
end

-- Builds the section/source lists.  Boss order and names come from the
-- Encounter Journal; bosses the journal does not list yet still get a row from
-- the Voidcache table.  Rebuilt until the journal has answered for everything.
function Pool.BuildSources()
    if Pool.built then
        return
    end
    local season = BRH.Season
    local sections = {}
    wipe(sourcesByKey)
    wipe(sourcesByVoidcache)
    local complete = true

    for _, raid in ipairs(season.raids) do
        local instanceName = EJ_GetInstanceInfo(raid.journalInstanceID)
        local section = {
            title = instanceName or ("Raid " .. raid.journalInstanceID),
            kind = "raid",
            sources = {}
        }
        local listed = {}
        local index = 1
        while true do
            local name, _, encounterID = EJ_GetEncounterInfoByIndex(index, raid.journalInstanceID)
            if not name then
                break
            end
            listed[encounterID] = true
            AddSource(section, MakeRaidSource(raid, encounterID, name, instanceName, index))
            index = index + 1
        end
        if index == 1 then
            complete = false
        end
        for encounterID in pairs(raid.voidcaches) do
            if not listed[encounterID] then
                local name = EJ_GetEncounterInfo(encounterID)
                AddSource(section, MakeRaidSource(raid, encounterID, name, instanceName, #section.sources + 1))
            end
        end
        if #section.sources > 0 then
            sections[#sections + 1] = section
        end
    end

    local dungeonSection = {
        title = "Mythic+ Dungeons",
        kind = "dungeon",
        sources = {}
    }
    for _, dungeon in ipairs(season.dungeons) do
        local source, named = MakeDungeonSource(dungeon)
        complete = complete and named
        AddSource(dungeonSection, source)
    end
    sections[#sections + 1] = dungeonSection

    Pool.sections = sections
    Pool.built = complete
end

function Pool.GetSource(key)
    Pool.BuildSources()
    return key and sourcesByKey[key]
end

function Pool.GetSourceByVoidcache(voidcacheID)
    Pool.BuildSources()
    return voidcacheID and sourcesByVoidcache[voidcacheID]
end

function Pool.GetFirstSource()
    Pool.BuildSources()
    local section = Pool.sections[1]
    return section and section.sources[1]
end

-- ── Buckets ───────────────────────────────────────────────────────────────────

function Pool.GetDefaultBucket(source)
    if source.kind == "raid" then
        return BRH.char.raidDifficulty
    end
    return BRH.char.keyTier
end

function Pool.BucketKey(source, bucket)
    return source.key .. ":" .. tostring(bucket)
end

local KEY_TIER_LABELS = {
    hero = "Below +10",
    myth = "+10 and up"
}

function Pool.BucketLabel(source, bucket)
    if source.kind == "raid" then
        return GetDifficultyInfo(bucket) or tostring(bucket)
    end
    return "Mythic+ " .. (KEY_TIER_LABELS[bucket] or tostring(bucket))
end

function Pool.ShortBucketLabel(kind, bucket)
    if kind == "raid" then
        local labels = {
            [17] = "LFR",
            [14] = "Normal",
            [15] = "Heroic",
            [16] = "Mythic"
        }
        return labels[bucket] or tostring(bucket)
    end
    return KEY_TIER_LABELS[bucket] or tostring(bucket)
end

local function EJDifficulty(source, bucket)
    if source.kind == "raid" then
        return bucket
    end
    return DUNGEON_EJ_DIFFICULTY
end

-- ── Encounter Journal reads ───────────────────────────────────────────────────
-- The journal has one global selection shared with Blizzard's Adventure Guide,
-- so every read saves and restores it, and reads pause while the guide is open.

local function SaveJournalState()
    local state = {
        tier = EJ_GetCurrentTier(),
        difficulty = EJ_GetDifficulty()
    }
    if EJ_GetLootFilter then
        state.classID, state.specID = EJ_GetLootFilter()
    end
    if C_EncounterJournal.GetSlotFilter then
        state.slot = C_EncounterJournal.GetSlotFilter()
    end
    local journal = _G.EncounterJournal
    if journal then
        state.instanceID = journal.instanceID
        state.encounterID = journal.encounterID
    end
    return state
end

local function RestoreJournalState(state)
    if state.tier then
        EJ_SelectTier(state.tier)
    end
    if state.instanceID then
        EJ_SelectInstance(state.instanceID)
        if state.encounterID then
            EJ_SelectEncounter(state.encounterID)
        end
    end
    if state.difficulty and EJ_IsValidInstanceDifficulty(state.difficulty) then
        EJ_SetDifficulty(state.difficulty)
    end
    if state.classID then
        EJ_SetLootFilter(state.classID, state.specID or 0)
    end
    if state.slot then
        C_EncounterJournal.SetSlotFilter(state.slot)
    end
end

-- Returns items, complete.  complete is false while item data is still loading.
local function ReadPool(job)
    local state = SaveJournalState()
    local items, complete = {}, true

    EJ_SelectInstance(job.journalInstanceID)
    if EJ_IsValidInstanceDifficulty(job.difficulty) then
        EJ_SetDifficulty(job.difficulty)
        if job.encounterID then
            EJ_SelectEncounter(job.encounterID)
        end
        C_EncounterJournal.SetSlotFilter(Enum.ItemSlotFilterType.NoFilter)
        EJ_SetLootFilter(job.classID, job.specID)

        local count = EJ_GetNumLoot() or 0
        if count == 0 then
            complete = false
        end
        local seen = {}
        for index = 1, count do
            local info = C_EncounterJournal.GetLootInfoByIndex(index)
            if not info or not info.itemID then
                complete = false
            elseif not seen[info.itemID] then
                seen[info.itemID] = true
                if not info.link then
                    complete = false
                end
                if info.filterType ~= Enum.ItemSlotFilterType.Other and not BRH.Season.excludedItems[info.itemID] then
                    items[#items + 1] = {
                        itemID = info.itemID,
                        link = info.link,
                        name = info.name,
                        icon = info.icon,
                        quality = info.itemQuality,
                        slot = info.slot,
                        armorType = info.armorType
                    }
                end
            end
        end
    end

    RestoreJournalState(state)
    return items, complete
end

-- ── Read queue ────────────────────────────────────────────────────────────────

local cache = {} -- [cacheKey] = items
local pending = {} -- [cacheKey] = true while queued
local queue = {}
local tickScheduled = false
local ProcessNext

local function ScheduleTick(delay)
    if tickScheduled then
        return
    end
    tickScheduled = true
    C_Timer.After(delay, ProcessNext)
end

local function IsJournalOpen()
    return _G.EncounterJournal ~= nil and _G.EncounterJournal:IsShown()
end

ProcessNext = function()
    tickScheduled = false
    if #queue == 0 then
        return
    end
    if IsJournalOpen() then
        ScheduleTick(BLOCKED_DELAY)
        return
    end
    -- Loot data loads more reliably with the journal addon present (as other
    -- loot addons do); load it out of combat only.
    if not C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
        if InCombatLockdown() then
            ScheduleTick(BLOCKED_DELAY)
            return
        end
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    end

    local job = table.remove(queue, 1)
    local items, complete = ReadPool(job)
    job.attempts = job.attempts + 1

    if complete or job.attempts >= MAX_ATTEMPTS then
        cache[job.cacheKey] = items
        pending[job.cacheKey] = nil
        BRH.Fire("POOL_UPDATED")
        if #queue > 0 then
            ScheduleTick(TICK_DELAY)
        end
    else
        queue[#queue + 1] = job
        ScheduleTick(#queue == 1 and RETRY_DELAY or TICK_DELAY)
    end
end

-- Returns the Voidcore pool (array of item records) for source/bucket/spec, or
-- nil while it is loading (POOL_UPDATED fires when it is ready).
function Pool.GetPool(source, bucket, specID)
    if not source or not bucket or not specID then
        return nil
    end
    local difficulty = EJDifficulty(source, bucket)
    local cacheKey = source.key .. ":" .. difficulty .. ":" .. specID
    local items = cache[cacheKey]
    if items then
        return items
    end
    if not pending[cacheKey] then
        pending[cacheKey] = true
        queue[#queue + 1] = {
            cacheKey = cacheKey,
            journalInstanceID = source.journalInstanceID,
            encounterID = source.encounterID,
            difficulty = difficulty,
            classID = BRH.GetClassID(),
            specID = specID,
            attempts = 0
        }
        ScheduleTick(TICK_DELAY)
    end
    return nil
end

-- True when loads are waiting for the Adventure Guide to close.
function Pool.IsBlocked()
    return #queue > 0 and IsJournalOpen()
end

-- Warm the pools for the current loot spec shortly after login so the window
-- and the bonus roll helper are instant.
BRH.On("LOGIN", function()
    C_Timer.After(6, function()
        local specID = BRH.GetLootSpecID()
        if not specID then
            return
        end
        Pool.BuildSources()
        for _, section in ipairs(Pool.sections) do
            for _, source in ipairs(section.sources) do
                Pool.GetPool(source, Pool.GetDefaultBucket(source), specID)
            end
        end
    end)
end)

-- Follow the raid difficulty you are actually playing.
BRH.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType ~= "raid" then
        return
    end
    for _, raidDifficulty in ipairs(Pool.RAID_DIFFICULTIES) do
        if raidDifficulty == difficultyID then
            BRH.char.raidDifficulty = difficultyID
            return
        end
    end
end)
