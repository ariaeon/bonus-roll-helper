-- Bonus Roll Helper: what you already have.
--
-- Bonus-rolled  – items won from a Nebulous Voidcore.  They leave that
--                 source's pool on that difficulty.  Read from the bonus roll
--                 log the Simulationcraft addon keeps (its "bonus_roll_items"
--                 export), because Blizzard's Voidcache tooltip is unreliable.
-- Looted        – items you own or received as normal loot.  They stay in the
--                 pool, so a roll can give you a duplicate.
-- Wishlist / avoid marks are per character and shared by every spec.
local _, BRH = ...

local History = {}
BRH.History = History

-- Item creation context of a raid bonus roll → EJ raid difficulty.
local RAID_CONTEXT_DIFFICULTY = {
    [3] = 14, -- Raid Normal
    [4] = 17, -- Raid Finder
    [5] = 15, -- Raid Heroic
    [6] = 16 -- Raid Mythic
}

function History.RaidDifficultyFromContext(context)
    return RAID_CONTEXT_DIFFICULTY[context]
end

function History.KeyTierFromLevel(keyLevel)
    return (keyLevel or 0) >= 10 and "myth" or "hero"
end

-- ── Simulationcraft bonus roll log ────────────────────────────────────────────

local entriesByBucket = {} -- [bucketKey] = { { itemID, specID, ts }, ... } oldest first
History.status = {
    state = "missing",
    matched = 0,
    total = 0
}

-- Simulationcraft stores each won roll as
-- { currency, source = voidcacheID, context, keyLevel, itemId, spec, season, ts }
-- in SimulationCraftDB.char["Name - Realm"].bonusRolls.
local function GetSimcRollLog()
    if not C_AddOns.IsAddOnLoaded("Simulationcraft") then
        return nil
    end
    local sv = _G.SimulationCraftDB
    local charKey = UnitName("player") .. " - " .. GetRealmName()
    local charData = type(sv) == "table" and type(sv.char) == "table" and sv.char[charKey]
    if type(charData) == "table" and type(charData.bonusRolls) == "table" then
        return charData.bonusRolls
    end
    local aceAddon = LibStub and LibStub("AceAddon-3.0", true)
    local simc = aceAddon and aceAddon:GetAddon("Simulationcraft", true)
    local rolls = simc and simc.db and simc.db.char and simc.db.char.bonusRolls
    return type(rolls) == "table" and rolls or {}
end

function History.Reload()
    wipe(entriesByBucket)
    local log = GetSimcRollLog()
    if not log then
        History.status = {
            state = "missing",
            matched = 0,
            total = 0
        }
        BRH.Fire("HISTORY_UPDATED")
        return
    end

    local records = {}
    for index, roll in ipairs(log) do
        if type(roll) == "table" and roll.itemId and roll.source then
            records[#records + 1] = {
                roll = roll,
                index = index
            }
        end
    end
    table.sort(records, function(a, b)
        local ta, tb = a.roll.ts or 0, b.roll.ts or 0
        if ta ~= tb then
            return ta < tb
        end
        return a.index < b.index
    end)

    local matched = 0
    for _, record in ipairs(records) do
        local roll = record.roll
        local source = BRH.Pool.GetSourceByVoidcache(roll.source)
        local bucket
        if source and source.kind == "raid" then
            bucket = RAID_CONTEXT_DIFFICULTY[roll.context]
        elseif source then
            bucket = History.KeyTierFromLevel(roll.keyLevel)
        end
        if bucket then
            local bucketKey = BRH.Pool.BucketKey(source, bucket)
            entriesByBucket[bucketKey] = entriesByBucket[bucketKey] or {}
            table.insert(entriesByBucket[bucketKey], {
                itemID = roll.itemId,
                specID = (roll.spec and roll.spec > 0) and roll.spec or nil,
                ts = roll.ts
            })
            matched = matched + 1
        end
    end

    History.status = {
        state = #records > 0 and "ok" or "empty",
        matched = matched,
        total = #records
    }
    BRH.Fire("HISTORY_UPDATED")
end

function History.GetStatusText()
    local status = History.status
    if status.state == "missing" then
        return "Simulationcraft is not enabled, so bonus-rolled items can't be detected."
    elseif status.state == "empty" then
        return "Simulationcraft has no bonus rolls logged for this character yet."
    end
    local text = string.format("Simulationcraft: %d bonus roll%s this season", status.matched,
        status.matched == 1 and "" or "s")
    if status.total > status.matched then
        text = text .. string.format(" (%d from older seasons or other content)", status.total - status.matched)
    end
    return text
end

-- Returns { [itemID] = entry } of items currently out of the pool for this
-- source/bucket.  entry is the SimC record or { manual = true }.
--
-- Blizzard refills a spec's pool once every item in it has been won, so the
-- log is replayed in order and a completed pool is cleared again.
function History.GetRolledSet(source, bucket)
    local bucketKey = BRH.Pool.BucketKey(source, bucket)
    local set = {}
    for _, entry in ipairs(entriesByBucket[bucketKey] or {}) do
        set[entry.itemID] = entry
        local pool = entry.specID and BRH.Pool.GetPool(source, bucket, entry.specID)
        if pool and #pool > 0 then
            local complete = true
            for _, item in ipairs(pool) do
                if not set[item.itemID] then
                    complete = false
                    break
                end
            end
            if complete then
                for _, item in ipairs(pool) do
                    set[item.itemID] = nil
                end
            end
        end
    end
    local manual = BRH.char.manualRolled[bucketKey]
    if manual then
        for itemID in pairs(manual) do
            set[itemID] = set[itemID] or {
                manual = true
            }
        end
    end
    return set
end

function History.IsManualRolled(source, bucket, itemID)
    local manual = BRH.char.manualRolled[BRH.Pool.BucketKey(source, bucket)]
    return manual ~= nil and manual[itemID] == true
end

function History.SetManualRolled(source, bucket, itemID, rolled)
    local bucketKey = BRH.Pool.BucketKey(source, bucket)
    local manual = BRH.char.manualRolled[bucketKey] or {}
    manual[itemID] = rolled or nil
    BRH.char.manualRolled[bucketKey] = next(manual) and manual or nil
    BRH.Fire("MARKS_UPDATED")
end

-- ── Wishlist / avoid ──────────────────────────────────────────────────────────

-- Returns "wish", "avoid" or nil.
function History.GetMark(itemID)
    if BRH.char.wish[itemID] then
        return "wish"
    elseif BRH.char.avoid[itemID] then
        return "avoid"
    end
end

-- mark: "wish", "avoid" or nil to clear.
function History.SetMark(itemID, mark)
    BRH.char.wish[itemID] = nil
    BRH.char.avoid[itemID] = nil
    if mark == "wish" then
        BRH.char.wish[itemID] = true
    elseif mark == "avoid" then
        BRH.char.avoid[itemID] = true
    end
    BRH.Fire("MARKS_UPDATED")
end

function History.ToggleMark(itemID, mark)
    History.SetMark(itemID, History.GetMark(itemID) ~= mark and mark or nil)
end

-- ── Looted ────────────────────────────────────────────────────────────────────

local function IsOwned(itemID)
    return C_Item.IsEquippedItem(itemID) or C_Item.GetItemCount(itemID, true, false, true, true) > 0
end

-- Once seen in your bags, bank or gear an item stays "looted" even if you sell
-- or scrap it later, unless you clear it by hand.
function History.IsLooted(itemID)
    local char = BRH.char
    if char.notLooted[itemID] then
        return false
    end
    if char.looted[itemID] then
        return true
    end
    if IsOwned(itemID) then
        char.looted[itemID] = true
        return true
    end
    return false
end

function History.SetLooted(itemID, looted)
    BRH.char.looted[itemID] = looted or nil
    BRH.char.notLooted[itemID] = (not looted) or nil
    BRH.Fire("MARKS_UPDATED")
end

local function RecordLoot(itemID)
    if not itemID then
        return
    end
    local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(itemID)
    if not equipLoc or equipLoc == "" or (classID ~= Enum.ItemClass.Weapon and classID ~= Enum.ItemClass.Armor) then
        return
    end
    BRH.char.looted[itemID] = true
    BRH.char.notLooted[itemID] = nil
    BRH.Fire("MARKS_UPDATED")
end

-- "You receive loot: %s." → "^You receive loot: (.+)%.$"
local function FormatToPattern(format)
    local pattern = format:gsub("%%%d?%$?s", "\001"):gsub("%%%d?%$?d", "\002")
    pattern = pattern:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    pattern = pattern:gsub("\001", "(.+)"):gsub("\002", "%%d+")
    return "^" .. pattern .. "$"
end

local selfLootPatterns
local function GetSelfLootPatterns()
    if not selfLootPatterns then
        selfLootPatterns = {}
        for _, format in ipairs({ LOOT_ITEM_SELF, LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_SELF_MULTIPLE,
                                  LOOT_ITEM_PUSHED_SELF_MULTIPLE }) do
            if type(format) == "string" then
                selfLootPatterns[#selfLootPatterns + 1] = FormatToPattern(format)
            end
        end
    end
    return selfLootPatterns
end

BRH.RegisterEvent("CHAT_MSG_LOOT", function(text)
    if BRH.IsSecret(text) or type(text) ~= "string" then
        return
    end
    for _, pattern in ipairs(GetSelfLootPatterns()) do
        local link = text:match(pattern)
        if link then
            RecordLoot(tonumber(link:match("item:(%d+)")))
            return
        end
    end
end)

BRH.RegisterEvent("ENCOUNTER_LOOT_RECEIVED", function(_, itemID, _, _, playerName)
    if BRH.IsSecret(itemID) or BRH.IsSecret(playerName) then
        return
    end
    if playerName and Ambiguate(playerName, "short") == UnitName("player") then
        RecordLoot(itemID)
    end
end)

-- Simulationcraft logs the roll in its own BONUS_ROLL_RESULT handler; read it
-- back once that has run.
BRH.RegisterEvent("BONUS_ROLL_RESULT", function()
    C_Timer.After(1, History.Reload)
end)

BRH.On("LOGIN", History.Reload)
