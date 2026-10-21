-- Bonus Roll Helper: small panel shown with the Nebulous Voidcore bonus roll
-- prompt – odds for your loot spec on this boss, a verdict, and a one-click
-- loot spec switch when another spec has better wishlist odds.
local _, BRH = ...

local Theme = BRH.Theme
local Pool = BRH.Pool
local History = BRH.History
local Odds = BRH.Odds

local RollPrompt = {}
BRH.RollPrompt = RollPrompt

local WIDTH, HEIGHT = 350, 138

local frame
local active -- { source, bucket, spellID }

local function Hide()
    active = nil
    if frame then
        frame:Hide()
    end
end

local function Anchor()
    if not frame then
        return
    end
    frame:ClearAllPoints()
    local bonusRollFrame = _G.BonusRollFrame
    if bonusRollFrame and bonusRollFrame:IsShown() then
        frame:SetPoint("BOTTOM", bonusRollFrame, "TOP", 0, 10)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -150)
    end
end

local function Create()
    frame = CreateFrame("Frame", "BonusRollHelperPrompt", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    Theme.ApplyBackdrop(frame, Theme.color.window, Theme.color.accent)
    frame:Hide()

    frame.title = Theme.CreateText(frame, "GameFontNormalSmall", Theme.color.accent)
    frame.title:SetPoint("TOPLEFT", 12, -10)
    frame.title:SetText("BONUS ROLL HELPER")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetScale(0.8)
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", Hide)

    frame.source = Theme.CreateText(frame, "GameFontHighlight")
    frame.source:SetPoint("TOPLEFT", 12, -28)
    frame.source:SetPoint("RIGHT", frame, "RIGHT", -120, 0)

    frame.spec = Theme.CreateText(frame, "GameFontHighlightSmall", Theme.color.muted)
    frame.spec:SetPoint("TOPLEFT", frame.source, "BOTTOMLEFT", 0, -5)
    frame.spec:SetPoint("RIGHT", frame, "RIGHT", -120, 0)

    frame.badge = Theme.CreatePanel(frame)
    frame.badge:SetSize(100, 26)
    frame.badge:SetPoint("TOPRIGHT", -12, -28)
    frame.badge.text = Theme.CreateText(frame.badge, "GameFontNormal", nil, "CENTER")
    frame.badge.text:SetPoint("CENTER")

    frame.bar = Theme.CreateStackBar(frame, WIDTH - 24, 8)
    frame.bar:SetPoint("TOPLEFT", 12, -70)

    frame.stats = Theme.CreateText(frame, "GameFontHighlightSmall")
    frame.stats:SetPoint("TOPLEFT", frame.bar, "BOTTOMLEFT", 0, -7)

    frame.switch = Theme.CreateButton(frame, "", 130, 22)
    frame.switch:SetPoint("BOTTOMRIGHT", -10, 9)
    frame.switch:SetScript("OnClick", function(self)
        if self.specID then
            BRH.SetLootSpec(self.specID)
        end
    end)

    frame.advice = Theme.CreateText(frame, "GameFontHighlightSmall", Theme.color.muted)
    frame.advice:SetPoint("BOTTOMLEFT", 12, 14)
    frame.advice:SetPoint("RIGHT", frame.switch, "LEFT", -8, 0)

    -- Click anywhere else to open the full planner on this boss.
    frame:SetScript("OnMouseUp", function()
        if not active then
            return
        end
        BRH.char.selectedSource = active.source.key
        if active.source.kind == "raid" then
            BRH.char.raidDifficulty = active.bucket
        else
            BRH.char.keyTier = active.bucket
        end
        BRH.UI.SetViewSpec(nil)
        BRH.ShowMainFrame()
    end)
end

local function SetBadge(verdictKey, text)
    local color = verdictKey and Odds.VERDICTS[verdictKey].color or Theme.color.muted
    frame.badge:SetBackdropColor(color[1], color[2], color[3], 0.16)
    frame.badge:SetBackdropBorderColor(color[1], color[2], color[3], 0.9)
    frame.badge.text:SetText(text)
    frame.badge.text:SetTextColor(color[1], color[2], color[3])
end

function RollPrompt.Update()
    if not active or not frame or not frame:IsShown() then
        return
    end
    local source, bucket = active.source, active.bucket
    local specID = BRH.GetLootSpecID()
    local spec = BRH.GetSpecInfo(specID)

    frame.source:SetText(source.name .. "  " .. Theme.Colorize(Pool.ShortBucketLabel(source.kind, bucket),
        Theme.color.muted))
    frame.spec:SetText("Loot spec: " .. (spec and ("|T" .. spec.icon .. ":14:14:0:0:64:64:5:59:5:59|t " .. spec.name) or "?"))
    frame.switch:Hide()

    local odds = specID and Odds.Compute(source, bucket, specID)
    if not odds then
        SetBadge(nil, "Loading…")
        frame.bar:SetSegments({})
        frame.stats:SetText("")
        frame.advice:SetText("Reading loot from the Adventure Guide…")
        return
    end

    SetBadge(odds.verdict, Odds.VERDICTS[odds.verdict].label)
    frame.bar:SetSegments({
        { odds.pWish, Theme.color.wish },
        { odds.pDupe, Theme.color.looted },
        { odds.pOther, Theme.color.other },
        { odds.pAvoid, Theme.color.avoid }
    })
    frame.stats:SetText(table.concat({
        Theme.Colorize("Wishlist " .. BRH.Percent(odds.pWish), Theme.color.wish),
        Theme.Colorize("Avoid " .. BRH.Percent(odds.pAvoid), Theme.color.avoid),
        Theme.Colorize("Duplicate " .. BRH.Percent(odds.pDupe), Theme.color.looted),
        Theme.Colorize(odds.remaining .. " items left", Theme.color.muted)
    }, "   "))

    local best = Odds.BestSpec(source, bucket)
    if best and best.spec.specID ~= specID and best.odds.pWish > odds.pWish then
        frame.advice:SetText(string.format("%s: %s wishlist chance here.", best.spec.name,
            BRH.Percent(best.odds.pWish)))
        frame.switch.label:SetText("Switch to " .. best.spec.name)
        frame.switch.specID = best.spec.specID
        frame.switch:Show()
    elseif odds.wish == 0 then
        frame.advice:SetText("No wishlist items in this pool for any spec you can pick.")
    else
        frame.advice:SetText("Your loot spec is the best choice here.")
    end
end

function RollPrompt.Show(source, bucket, spellID)
    if not frame then
        Create()
    end
    active = {
        source = source,
        bucket = bucket,
        spellID = spellID
    }
    Anchor()
    frame:Show()
    RollPrompt.Update()
    -- Blizzard's prompt frame may show after us on the same event.
    C_Timer.After(0.1, Anchor)
end

function RollPrompt.ShowTest()
    local source = BRH.UI.GetSelectedSource()
    if source then
        RollPrompt.Show(source, Pool.GetDefaultBucket(source))
    end
end

-- ── Events ────────────────────────────────────────────────────────────────────

local function FindPrompt(spellID)
    local prompts = GetSpellConfirmationPromptsInfo and GetSpellConfirmationPromptsInfo()
    for _, entry in ipairs(prompts or {}) do
        if entry.spellID == spellID then
            return entry
        end
    end
end

local function ResolveBucket(source, entry)
    if source.kind == "raid" then
        local bucket = History.RaidDifficultyFromContext(entry.itemContext)
        if bucket then
            return bucket
        end
        local _, _, difficultyID = GetInstanceInfo()
        for _, raidDifficulty in ipairs(Pool.RAID_DIFFICULTIES) do
            if raidDifficulty == difficultyID then
                return difficultyID
            end
        end
        return BRH.char.raidDifficulty
    end
    local keyLevel = entry.treasureContextLevel
    if keyLevel and keyLevel > 0 then
        return History.KeyTierFromLevel(keyLevel)
    end
    return BRH.char.keyTier
end

BRH.RegisterEvent("SPELL_CONFIRMATION_PROMPT", function(spellID)
    if not BRH.db or not BRH.db.promptEnabled or BRH.IsSecret(spellID) then
        return
    end
    local entry = FindPrompt(spellID)
    local source = entry and BRH.Pool.GetSourceByVoidcache(entry.displayItemID)
    if source then
        RollPrompt.Show(source, ResolveBucket(source, entry), spellID)
    end
end)

BRH.RegisterEvent("SPELL_CONFIRMATION_TIMEOUT", function(spellID)
    if active and active.spellID and active.spellID == spellID then
        Hide()
    end
end)

BRH.RegisterEvent("BONUS_ROLL_RESULT", function()
    if active and active.spellID then
        Hide()
    end
end)

BRH.On("POOL_UPDATED", RollPrompt.Update)
BRH.On("HISTORY_UPDATED", RollPrompt.Update)
BRH.On("MARKS_UPDATED", RollPrompt.Update)
BRH.RegisterEvent("PLAYER_LOOT_SPEC_UPDATED", function()
    C_Timer.After(0, RollPrompt.Update)
end)
