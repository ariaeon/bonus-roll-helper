-- Bonus Roll Helper: main window – header (spec + difficulty + Voidcores),
-- boss/dungeon sidebar, loot panel and footer.
local _, BRH = ...

local Theme = BRH.Theme
local Pool = BRH.Pool
local History = BRH.History
local Odds = BRH.Odds

local UI = {}
BRH.UI = UI

local WIDTH, HEIGHT = 920, 620
local HEADER_HEIGHT = 64
local FOOTER_HEIGHT = 30
local PADDING = 10
local SIDEBAR_WIDTH = 256
local SIDEBAR_GUTTER = 22
local ROW_WIDTH = SIDEBAR_WIDTH - SIDEBAR_GUTTER - 2
local ROW_HEIGHT = 40
local SECTION_HEIGHT = 28
local SPEC_BUTTON_SIZE = 30
local SPEC_BUTTON_SPACING = 44

local frame
local specButtons = {}
local difficultyGroups = {}
local currency
local sidebar = {
    rows = {},
    headers = {}
}
local footer

-- ── View state ────────────────────────────────────────────────────────────────

local viewSpecID -- session only; nil follows the loot spec

function UI.GetViewSpecID()
    return viewSpecID or BRH.GetLootSpecID()
end

function UI.SetViewSpec(specID)
    viewSpecID = specID
    UI.RequestRefresh()
end

function UI.GetSelectedSource()
    return Pool.GetSource(BRH.char.selectedSource) or Pool.GetFirstSource()
end

function UI.SelectSource(source)
    BRH.char.selectedSource = source.key
    UI.RequestRefresh()
end

local refreshScheduled = false

function UI.RequestRefresh()
    if refreshScheduled or not frame or not frame:IsShown() then
        return
    end
    refreshScheduled = true
    C_Timer.After(0.05, function()
        refreshScheduled = false
        UI.Refresh()
    end)
end

-- Short wishlist chance text for a spec button / sidebar row.
local function OddsText(odds)
    if not odds then
        return "…", Theme.color.muted
    end
    if odds.remaining == 0 or odds.wish == 0 then
        return "–", Theme.color.muted
    end
    return BRH.Percent(odds.pWish), Odds.VERDICTS[odds.verdict].color
end

-- ── Header ────────────────────────────────────────────────────────────────────

local function CreateSpecButtons(header)
    for index, spec in ipairs(BRH.GetClassSpecs()) do
        local button = CreateFrame("Button", nil, header, "BackdropTemplate")
        button:SetSize(SPEC_BUTTON_SIZE, SPEC_BUTTON_SIZE)
        button:SetPoint("TOPLEFT", header, "TOPLEFT", 270 + (index - 1) * SPEC_BUTTON_SPACING, -10)
        Theme.ApplyBackdrop(button, Theme.color.track, Theme.color.border)
        button.spec = spec

        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("TOPLEFT", 2, -2)
        button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        button.icon:SetTexture(spec.icon)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- Purple corner pip = current loot spec.
        button.lootPip = Theme.CreatePanel(button, Theme.color.accent, Theme.color.window)
        button.lootPip:SetSize(10, 10)
        button.lootPip:SetPoint("TOPRIGHT", 4, 4)
        button.lootPip:SetFrameLevel(button:GetFrameLevel() + 2)

        button.odds = Theme.CreateText(button, "GameFontHighlightSmall", nil, "CENTER")
        button.odds:SetPoint("TOP", button, "BOTTOM", 0, -3)
        Theme.SetFontSize(button.odds, 10)

        button:SetScript("OnClick", function(self)
            UI.SetViewSpec(self.spec.specID)
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.spec.name)
            if self.spec.specID == BRH.GetLootSpecID() then
                GameTooltip:AddLine("Your current loot specialization", Theme.Unpack(Theme.color.accent))
            end
            GameTooltip:AddLine("Click to view the loot pools of this spec.", 1, 1, 1)
            GameTooltip:AddLine("The number is its chance at a wishlist item from the selected boss.",
                Theme.Unpack(Theme.color.muted))
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        specButtons[index] = button
    end
end

local function CreateDifficultyGroup(header, kind, buckets, buttonWidth)
    local group = CreateFrame("Frame", nil, header)
    group:SetSize(#buckets * (buttonWidth + 4), 24)
    group.buttons = {}
    for index, bucket in ipairs(buckets) do
        local button = Theme.CreateButton(group, Pool.ShortBucketLabel(kind, bucket), buttonWidth, 24)
        button:SetPoint("LEFT", (index - 1) * (buttonWidth + 4), 0)
        button.bucket = bucket
        button:SetScript("OnClick", function(self)
            if kind == "raid" then
                BRH.char.raidDifficulty = self.bucket
            else
                BRH.char.keyTier = self.bucket
            end
            UI.RequestRefresh()
        end)
        group.buttons[index] = button
    end
    difficultyGroups[kind] = group
    return group
end

local function CreateCurrency(header)
    currency = CreateFrame("Frame", nil, header)
    currency:SetSize(150, 36)
    currency:SetPoint("RIGHT", header, "RIGHT", -46, 0)
    currency.icon = currency:CreateTexture(nil, "ARTWORK")
    currency.icon:SetSize(28, 28)
    currency.icon:SetPoint("LEFT")
    currency.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    currency.count = Theme.CreateText(currency, "GameFontHighlightLarge")
    currency.count:SetPoint("TOPLEFT", currency.icon, "TOPRIGHT", 8, 1)
    currency.label = Theme.CreateText(currency, "GameFontHighlightSmall", Theme.color.muted)
    currency.label:SetPoint("BOTTOMLEFT", currency.icon, "BOTTOMRIGHT", 8, 0)
    currency.label:SetText("Nebulous Voidcores")
    currency:EnableMouse(true)
    currency:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetCurrencyByID(BRH.Season.currencyID)
        GameTooltip:Show()
    end)
    currency:SetScript("OnLeave", GameTooltip_Hide)
end

local function CreateHeader()
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_HEIGHT)

    local line = Theme.CreateRect(header, "ARTWORK", Theme.color.accent)
    line:SetPoint("BOTTOMLEFT", 1, 0)
    line:SetPoint("BOTTOMRIGHT", -1, 0)
    line:SetHeight(1)

    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(34, 34)
    logo:SetPoint("LEFT", 14, 0)
    logo:SetTexture(Theme.icon.addon)
    logo:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local title = Theme.CreateText(header, "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -1)
    title:SetText("Bonus Roll Helper")

    local subtitle = Theme.CreateText(header, "GameFontHighlightSmall", Theme.color.muted)
    subtitle:SetPoint("BOTTOMLEFT", logo, "BOTTOMRIGHT", 10, 1)
    subtitle:SetText(BRH.Season.name)

    CreateSpecButtons(header)

    local difficultyLeft = 270 + #specButtons * SPEC_BUTTON_SPACING + 14
    local raid = CreateDifficultyGroup(header, "raid", Pool.RAID_DIFFICULTIES, 56)
    raid:SetPoint("TOPLEFT", header, "TOPLEFT", difficultyLeft, -13)
    local dungeon = CreateDifficultyGroup(header, "dungeon", Pool.KEY_TIERS, 82)
    dungeon:SetPoint("TOPLEFT", header, "TOPLEFT", difficultyLeft, -13)

    CreateCurrency(header)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("RIGHT", header, "RIGHT", -8, 0)
end

local function UpdateHeader(source, bucket, specID)
    local lootSpecID = BRH.GetLootSpecID()
    for _, button in ipairs(specButtons) do
        local selected = button.spec.specID == specID
        button:SetBackdropBorderColor(Theme.Unpack(selected and Theme.color.accent or Theme.color.border))
        button.icon:SetDesaturated(not selected)
        button.icon:SetAlpha(selected and 1 or 0.7)
        button.lootPip:SetShown(button.spec.specID == lootSpecID)
        local text, color = OddsText(source and Odds.Compute(source, bucket, button.spec.specID))
        button.odds:SetText(text)
        button.odds:SetTextColor(Theme.Unpack(color))
    end

    for kind, group in pairs(difficultyGroups) do
        group:SetShown(source ~= nil and source.kind == kind)
        for _, button in ipairs(group.buttons) do
            button:SetSelected(button.bucket == bucket)
        end
    end

    local info = C_CurrencyInfo.GetCurrencyInfo(BRH.Season.currencyID)
    currency.icon:SetTexture(info and info.iconFileID or Theme.icon.addon)
    currency.count:SetText(info and info.quantity or 0)
    if info and info.name then
        currency.label:SetText(info.name)
    end
end

-- ── Sidebar ───────────────────────────────────────────────────────────────────

local function ShowSourceTooltip(row)
    local source = row.source
    local bucket = Pool.GetDefaultBucket(source)
    local odds = Odds.Compute(source, bucket, UI.GetViewSpecID())
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(source.name)
    GameTooltip:AddLine(Pool.BucketLabel(source, bucket), Theme.Unpack(Theme.color.muted))
    if odds then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Wishlist", BRH.Percent(odds.pWish) .. "  (" .. odds.wish .. ")", 1, 1, 1,
            Theme.Unpack(Theme.color.wish))
        GameTooltip:AddDoubleLine("Avoid", BRH.Percent(odds.pAvoid) .. "  (" .. odds.avoid .. ")", 1, 1, 1,
            Theme.Unpack(Theme.color.avoid))
        GameTooltip:AddDoubleLine("Looted (duplicate)", BRH.Percent(odds.pDupe) .. "  (" .. odds.dupe .. ")", 1, 1,
            1, Theme.Unpack(Theme.color.looted))
        GameTooltip:AddDoubleLine("Items left in pool", odds.remaining .. " / " .. odds.total, 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function CreateSourceRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)

    row.selectedBg = Theme.CreateRect(row, "BACKGROUND", Theme.color.selected)
    row.selectedBg:SetAllPoints()
    row.selectedBg:SetAlpha(0.55)
    row.selectedBar = Theme.CreateRect(row, "ARTWORK", Theme.color.accent)
    row.selectedBar:SetPoint("TOPLEFT")
    row.selectedBar:SetPoint("BOTTOMLEFT")
    row.selectedBar:SetWidth(3)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.05)

    -- Dungeons show their icon, raid bosses their number in the raid.
    row.iconFrame = Theme.CreatePanel(row, Theme.color.track)
    row.iconFrame:SetSize(28, 28)
    row.iconFrame:SetPoint("LEFT", 10, 0)
    row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", 1, -1)
    row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.number = Theme.CreateText(row.iconFrame, "GameFontHighlight", Theme.color.muted, "CENTER")
    row.number:SetPoint("CENTER")

    row.odds = Theme.CreateText(row, "GameFontHighlight", nil, "RIGHT")
    row.odds:SetPoint("RIGHT", -8, 0)

    row.name = Theme.CreateText(row, "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", 8, -2)
    row.name:SetPoint("RIGHT", row, "RIGHT", -48, 0)

    row.bar = Theme.CreateStackBar(row, ROW_WIDTH - 10 - 28 - 8 - 48, 4)
    row.bar:SetPoint("BOTTOMLEFT", row.iconFrame, "BOTTOMRIGHT", 8, 3)

    row:SetScript("OnClick", function(self)
        UI.SelectSource(self.source)
    end)
    row:SetScript("OnEnter", ShowSourceTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

local function CreateSectionHeader(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(ROW_WIDTH, SECTION_HEIGHT)
    header.title = Theme.CreateText(header, "GameFontNormalSmall", Theme.color.accent)
    header.title:SetPoint("BOTTOMLEFT", 10, 6)
    header.note = Theme.CreateText(header, "GameFontHighlightSmall", Theme.color.muted, "RIGHT")
    header.note:SetPoint("BOTTOMRIGHT", -8, 6)
    header.title:SetPoint("RIGHT", header.note, "LEFT", -6, 0)
    return header
end

local function CreateSidebar()
    local panel = Theme.CreatePanel(frame, Theme.color.panel)
    panel:SetPoint("TOPLEFT", PADDING, -(HEADER_HEIGHT + PADDING))
    panel:SetPoint("BOTTOMLEFT", PADDING, FOOTER_HEIGHT + 4)
    panel:SetWidth(SIDEBAR_WIDTH)

    sidebar.scroll = Theme.CreateScrollArea(panel, ROW_WIDTH)
    sidebar.scroll:SetPoint("TOPLEFT", 1, -2)
    sidebar.scroll:SetPoint("BOTTOMRIGHT", -(SIDEBAR_GUTTER + 1), 4)
end

local function UpdateSidebar(selected, specID)
    local child = sidebar.scroll.child
    for _, row in ipairs(sidebar.rows) do
        row:Hide()
    end
    for _, header in ipairs(sidebar.headers) do
        header:Hide()
    end

    local y, rowIndex = 0, 0
    for sectionIndex, section in ipairs(Pool.sections) do
        local header = sidebar.headers[sectionIndex] or CreateSectionHeader(child)
        sidebar.headers[sectionIndex] = header
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", 0, -y)
        header.title:SetText(section.title:upper())
        local bucket = section.kind == "raid" and BRH.char.raidDifficulty or BRH.char.keyTier
        header.note:SetText(Pool.ShortBucketLabel(section.kind, bucket))
        header:Show()
        y = y + SECTION_HEIGHT

        for _, source in ipairs(section.sources) do
            rowIndex = rowIndex + 1
            local row = sidebar.rows[rowIndex] or CreateSourceRow(child)
            sidebar.rows[rowIndex] = row
            row.source = source
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)

            local isSelected = selected ~= nil and source.key == selected.key
            row.selectedBg:SetShown(isSelected)
            row.selectedBar:SetShown(isSelected)
            row.name:SetText(source.name)

            if source.icon then
                row.icon:SetTexture(source.icon)
                row.icon:Show()
                row.number:Hide()
            else
                row.icon:Hide()
                row.number:SetText(source.order or "")
                row.number:Show()
            end

            local odds = Odds.Compute(source, Pool.GetDefaultBucket(source), specID)
            local text, color = OddsText(odds)
            row.odds:SetText(text)
            row.odds:SetTextColor(Theme.Unpack(color))
            if odds then
                row.bar:SetSegments({
                    { odds.pWish, Theme.color.wish },
                    { odds.pDupe, Theme.color.looted },
                    { odds.pOther, Theme.color.other },
                    { odds.pAvoid, Theme.color.avoid }
                })
            else
                row.bar:SetSegments({})
            end
            row:Show()
            y = y + ROW_HEIGHT
        end
        y = y + 4
    end
    child:SetHeight(math.max(y, 1))
end

-- ── Footer ────────────────────────────────────────────────────────────────────

local LEGEND = {
    { icon = "wish", text = "Wishlist" },
    { icon = "avoid", text = "Avoid" },
    { icon = "looted", text = "Looted · still in pool" },
    { icon = "rolled", text = "Bonus-rolled · out of pool" }
}

local function CreateFooter()
    footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", PADDING, 4)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, 4)
    footer:SetHeight(FOOTER_HEIGHT - 6)

    local anchor
    for index = #LEGEND, 1, -1 do
        local entry = LEGEND[index]
        local text = Theme.CreateText(footer, "GameFontHighlightSmall", Theme.color.muted)
        text:SetText(entry.text)
        if anchor then
            text:SetPoint("RIGHT", anchor, "LEFT", -14, 0)
        else
            text:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
        end
        local icon = footer:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetTexture(Theme.icon[entry.icon])
        icon:SetPoint("RIGHT", text, "LEFT", -4, 0)
        anchor = icon
    end

    footer.dot = Theme.CreateRect(footer, "ARTWORK", Theme.color.muted)
    footer.dot:SetSize(8, 8)
    footer.dot:SetPoint("LEFT", 2, 0)
    footer.status = Theme.CreateText(footer, "GameFontHighlightSmall", Theme.color.muted)
    footer.status:SetPoint("LEFT", footer.dot, "RIGHT", 6, 0)
    footer.status:SetPoint("RIGHT", anchor, "LEFT", -16, 0)

    footer.statusHit = CreateFrame("Frame", nil, footer)
    footer.statusHit:SetAllPoints(footer.status)
    footer.statusHit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Bonus roll history")
        GameTooltip:AddLine(History.GetStatusText(), 1, 1, 1, true)
        GameTooltip:AddLine(
            "Items you won with a Voidcore are read from the Simulationcraft addon's bonus roll log, because Blizzard's Voidcache tooltip doesn't show them reliably.",
            0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    footer.statusHit:SetScript("OnLeave", GameTooltip_Hide)
end

local function UpdateFooter()
    local state = History.status.state
    local color = (state == "ok" and Theme.color.rolled) or (state == "missing" and Theme.color.avoid) or
                      Theme.color.muted
    footer.dot:SetColorTexture(Theme.Unpack(color))
    footer.status:SetText(History.GetStatusText())
end

-- ── Window ────────────────────────────────────────────────────────────────────

function UI.Refresh()
    if not frame or not frame:IsShown() then
        return
    end
    Pool.BuildSources()
    local source = UI.GetSelectedSource()
    local bucket = source and Pool.GetDefaultBucket(source)
    local specID = UI.GetViewSpecID()

    UpdateHeader(source, bucket, specID)
    UpdateSidebar(source, specID)
    BRH.LootPanel.Update(source, bucket, specID)
    UpdateFooter()
end

local function CreateMainFrame()
    frame = CreateFrame("Frame", "BonusRollHelperFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    Theme.ApplyBackdrop(frame, Theme.color.window, Theme.color.border)

    local point = BRH.db.point
    if point then
        frame:SetPoint(point[1], UIParent, point[2], point[3], point[4])
    else
        frame:SetPoint("CENTER")
    end

    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, relativePoint, x, y = self:GetPoint()
        BRH.db.point = { p, relativePoint, x, y }
    end)
    frame:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
        History.Reload()
        UI.Refresh()
    end)
    frame:SetScript("OnHide", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    end)
    table.insert(UISpecialFrames, "BonusRollHelperFrame")

    CreateHeader()
    CreateSidebar()
    CreateFooter()

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", PADDING * 2 + SIDEBAR_WIDTH, -(HEADER_HEIGHT + PADDING))
    content:SetPoint("BOTTOMRIGHT", -PADDING, FOOTER_HEIGHT + 4)
    BRH.LootPanel.Create(content, WIDTH - SIDEBAR_WIDTH - PADDING * 3)
end

function BRH.ToggleMainFrame()
    if not BRH.char then
        return
    end
    if not frame then
        CreateMainFrame()
    end
    frame:SetShown(not frame:IsShown())
end

function BRH.ShowMainFrame()
    if not BRH.char then
        return
    end
    if not frame then
        CreateMainFrame()
    end
    if frame:IsShown() then
        UI.Refresh()
    else
        frame:Show()
    end
end

-- ── Refresh triggers ──────────────────────────────────────────────────────────

BRH.On("POOL_UPDATED", UI.RequestRefresh)
BRH.On("HISTORY_UPDATED", UI.RequestRefresh)
BRH.On("MARKS_UPDATED", UI.RequestRefresh)
for _, event in ipairs({ "CURRENCY_DISPLAY_UPDATE", "PLAYER_LOOT_SPEC_UPDATED", "PLAYER_SPECIALIZATION_CHANGED",
                         "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED" }) do
    BRH.RegisterEvent(event, UI.RequestRefresh)
end
