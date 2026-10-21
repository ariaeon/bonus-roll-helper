-- Bonus Roll Helper: namespace, saved variables, event/callback plumbing,
-- spec helpers and slash commands.
local ADDON_NAME, BRH = ...

BRH.ADDON_NAME = ADDON_NAME
BRH.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

-- ── Internal callbacks ────────────────────────────────────────────────────────
-- Messages: DB_READY, LOGIN, POOL_UPDATED, HISTORY_UPDATED, MARKS_UPDATED

local callbacks = {}

function BRH.On(message, fn)
    callbacks[message] = callbacks[message] or {}
    table.insert(callbacks[message], fn)
end

function BRH.Fire(message, ...)
    local list = callbacks[message]
    if not list then
        return
    end
    for _, fn in ipairs(list) do
        fn(...)
    end
end

-- ── Game events ───────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

-- Handlers receive the event payload without the event name.
function BRH.RegisterEvent(event, fn)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
        return
    end
    if not eventHandlers[event] then
        eventHandlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(eventHandlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(eventHandlers[event]) do
        fn(...)
    end
end)

-- Payloads can be secret values in restricted contexts (12.x); never inspect those.
function BRH.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

-- ── Saved variables ───────────────────────────────────────────────────────────

local DB_DEFAULTS = {
    point = nil, -- { point, relativePoint, x, y } of the main window
    promptEnabled = true
}

local CHAR_DEFAULTS = {
    wish = {}, -- [itemID] = true
    avoid = {}, -- [itemID] = true
    looted = {}, -- [itemID] = true  (owned / received as normal loot)
    notLooted = {}, -- [itemID] = true  (user cleared an auto-detected looted flag)
    manualRolled = {}, -- [bucketKey] = { [itemID] = true }
    raidDifficulty = 16,
    keyTier = "myth",
    selectedSource = nil
}

-- Defaults only hold empty tables or scalars, so a fresh {} is a full copy.
local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = type(value) == "table" and {} or value
        end
    end
    return target
end

BRH.RegisterEvent("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then
        return
    end
    BonusRollHelperDB = ApplyDefaults(BonusRollHelperDB or {}, DB_DEFAULTS)
    BonusRollHelperCharDB = ApplyDefaults(BonusRollHelperCharDB or {}, CHAR_DEFAULTS)
    BRH.db = BonusRollHelperDB
    BRH.char = BonusRollHelperCharDB
    BRH.Fire("DB_READY")
end)

BRH.RegisterEvent("PLAYER_LOGIN", function()
    BRH.Fire("LOGIN")
end)

-- ── Output ────────────────────────────────────────────────────────────────────

function BRH.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffb066ffBonus Roll Helper|r: " .. tostring(message))
end

function BRH.Percent(fraction)
    return string.format("%d%%", math.floor((fraction or 0) * 100 + 0.5))
end

-- ── Class / spec helpers ──────────────────────────────────────────────────────

function BRH.GetClassID()
    return select(3, UnitClass("player"))
end

-- Returns { { specID, name, icon, role }, ... } for the player's class.
function BRH.GetClassSpecs()
    if BRH.classSpecs then
        return BRH.classSpecs
    end
    local classID = BRH.GetClassID()
    local specs = {}
    for i = 1, GetNumSpecializationsForClassID(classID) do
        local specID, name, _, icon, role = GetSpecializationInfoForClassID(classID, i)
        if specID then
            specs[#specs + 1] = {
                specID = specID,
                name = name,
                icon = icon,
                role = role
            }
        end
    end
    if #specs > 0 then
        BRH.classSpecs = specs
    end
    return specs
end

function BRH.GetSpecInfo(specID)
    for _, spec in ipairs(BRH.GetClassSpecs()) do
        if spec.specID == specID then
            return spec
        end
    end
end

function BRH.GetActiveSpecID()
    local index = C_SpecializationInfo.GetSpecialization()
    if not index then
        return nil
    end
    local specID = C_SpecializationInfo.GetSpecializationInfo(index)
    if specID and specID > 0 then
        return specID
    end
end

-- The spec Voidcore rolls use: the loot spec, or the active spec when the loot
-- spec is set to "Current Specialization".
function BRH.GetLootSpecID()
    local specID = GetLootSpecialization()
    if not specID or specID == 0 then
        specID = BRH.GetActiveSpecID()
    end
    return specID
end

function BRH.SetLootSpec(specID)
    if InCombatLockdown() then
        BRH.Print("Can't change loot specialization in combat.")
        return
    end
    SetLootSpecialization(specID)
end

-- ── Item helpers ──────────────────────────────────────────────────────────────

function BRH.QualityColor(quality)
    quality = quality or Enum.ItemQuality.Epic
    if C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        if r then
            return r, g, b
        end
    end
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then
        return color.r, color.g, color.b
    end
    return 0.64, 0.21, 0.93
end

-- ── Slash commands ────────────────────────────────────────────────────────────

local function PrintHelp()
    BRH.Print("commands:")
    print("  /brh – open or close the window")
    print("  /brh popup – toggle the helper shown next to the Voidcore bonus roll prompt")
    print("  /brh test – preview that helper for the selected boss")
    print("  /brh simc – re-read the Simulationcraft bonus roll log")
    print("  /brh resetmarks – clear your wishlist and avoid list")
end

StaticPopupDialogs["BONUSROLLHELPER_RESET_MARKS"] = {
    text = "Clear your Bonus Roll Helper wishlist and avoid list for this character?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        wipe(BRH.char.wish)
        wipe(BRH.char.avoid)
        BRH.Fire("MARKS_UPDATED")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3
}

SLASH_BONUSROLLHELPER1 = "/brh"
SLASH_BONUSROLLHELPER2 = "/bonusroll"
SlashCmdList.BONUSROLLHELPER = function(message)
    local command = strtrim(message or ""):lower()
    if command == "" then
        BRH.ToggleMainFrame()
    elseif command == "popup" then
        BRH.db.promptEnabled = not BRH.db.promptEnabled
        BRH.Print("bonus roll prompt helper " .. (BRH.db.promptEnabled and "enabled." or "disabled."))
    elseif command == "test" then
        BRH.RollPrompt.ShowTest()
    elseif command == "simc" then
        BRH.History.Reload()
        BRH.Print(BRH.History.GetStatusText())
    elseif command == "resetmarks" then
        StaticPopup_Show("BONUSROLLHELPER_RESET_MARKS")
    else
        PrintHelp()
    end
end

-- ── Addon compartment (minimap addon menu) ────────────────────────────────────

function BonusRollHelper_OnAddonCompartmentClick()
    BRH.ToggleMainFrame()
end

function BonusRollHelper_OnAddonCompartmentEnter(_, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
    GameTooltip:AddLine("Bonus Roll Helper")
    GameTooltip:AddLine("Click to open the Voidcore planner.", 1, 1, 1)
    GameTooltip:Show()
end

function BonusRollHelper_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
