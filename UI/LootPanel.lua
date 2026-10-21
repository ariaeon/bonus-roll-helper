-- Bonus Roll Helper: right-hand panel – odds card and loot tiles for the
-- selected boss/dungeon, difficulty and spec.
--
-- Tile language:
--   colour (left bar + border) = what you want: gold wishlist, red avoid
--   badge on the icon          = what you have: backpack looted, tick bonus-rolled
--   bonus-rolled items are faded and listed separately (out of the pool)
local _, BRH = ...

local Theme = BRH.Theme
local Pool = BRH.Pool
local History = BRH.History
local Odds = BRH.Odds

local LootPanel = {}
BRH.LootPanel = LootPanel

local CARD_HEIGHT = 148
local TILE_HEIGHT = 48
local TILE_GAP = 6
local SECTION_HEIGHT = 28
local SCROLL_GUTTER = 22

local card, scroll, emptyText
local tileWidth
local tiles, sectionLabels = {}, {}
local current = {} -- source, bucket, specID of the last update

-- ── Item data ─────────────────────────────────────────────────────────────────

local requested = {}

local function RequestItem(itemID)
    if requested[itemID] then
        return
    end
    requested[itemID] = true
    Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
        BRH.UI.RequestRefresh()
    end)
end

-- Returns name, link, quality, icon (falls back to Encounter Journal data).
local function GetItemDisplay(item)
    local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(item.link or item.itemID)
    if not name then
        RequestItem(item.itemID)
    end
    return name or item.name or ("Item " .. item.itemID), item.link or link, quality or item.quality,
        icon or item.icon or C_Item.GetItemIconByID(item.itemID)
end

local function JoinParts(...)
    local parts = {}
    for index = 1, select("#", ...) do
        local part = select(index, ...)
        if part and part ~= "" then
            parts[#parts + 1] = part
        end
    end
    return table.concat(parts, " · ")
end

local function RolledText(entry)
    if entry.manual then
        return "Bonus-rolled (marked by hand)"
    end
    local spec = entry.specID and BRH.GetSpecInfo(entry.specID)
    local when = entry.ts and date("%d %b", entry.ts)
    return JoinParts("Bonus-rolled" .. (when and (" on " .. when) or ""), spec and ("as " .. spec.name))
end

-- ── Odds card ─────────────────────────────────────────────────────────────────

local STATS = {
    { key = "wish", label = "WISHLIST", color = "wish" },
    { key = "avoid", label = "AVOID", color = "avoid" },
    { key = "dupe", label = "LOOTED · DUPLICATE", color = "looted" },
    { key = "other", label = "OTHER", color = "other" }
}

local function CreateCard(parent, width)
    card = Theme.CreatePanel(parent, Theme.color.panel)
    card:SetPoint("TOPLEFT")
    card:SetSize(width, CARD_HEIGHT)

    card.title = Theme.CreateText(card, "GameFontHighlightLarge")
    card.title:SetPoint("TOPLEFT", 14, -12)
    card.title:SetPoint("RIGHT", card, "RIGHT", -160, 0)

    card.subtitle = Theme.CreateText(card, "GameFontHighlightSmall", Theme.color.muted)
    card.subtitle:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -5)
    card.subtitle:SetPoint("RIGHT", card, "RIGHT", -160, 0)

    card.badge = Theme.CreatePanel(card)
    card.badge:SetSize(136, 28)
    card.badge:SetPoint("TOPRIGHT", -14, -12)
    card.badge.text = Theme.CreateText(card.badge, "GameFontNormal", nil, "CENTER")
    card.badge.text:SetPoint("CENTER")

    card.bar = Theme.CreateStackBar(card, width - 28, 10)
    card.bar:SetPoint("TOPLEFT", 14, -58)

    card.stats = {}
    local columnWidth = (width - 28) / #STATS
    for index, def in ipairs(STATS) do
        local stat = CreateFrame("Frame", nil, card)
        stat:SetSize(columnWidth, 38)
        stat:SetPoint("TOPLEFT", card.bar, "BOTTOMLEFT", (index - 1) * columnWidth, -9)
        stat.swatch = Theme.CreateRect(stat, "ARTWORK", Theme.color[def.color])
        stat.swatch:SetSize(8, 8)
        stat.swatch:SetPoint("TOPLEFT", 0, -2)
        stat.label = Theme.CreateText(stat, "GameFontHighlightSmall", Theme.color.muted)
        stat.label:SetPoint("LEFT", stat.swatch, "RIGHT", 5, 0)
        stat.label:SetText(def.label)
        Theme.SetFontSize(stat.label, 10)
        stat.value = Theme.CreateText(stat, "GameFontHighlightLarge")
        stat.value:SetPoint("TOPLEFT", stat.swatch, "BOTTOMLEFT", 0, -5)
        stat.count = Theme.CreateText(stat, "GameFontHighlightSmall", Theme.color.muted)
        stat.count:SetPoint("BOTTOMLEFT", stat.value, "BOTTOMRIGHT", 6, 1)
        card.stats[def.key] = stat
    end

    card.info = Theme.CreateText(card, "GameFontHighlightSmall", Theme.color.muted)
    card.info:SetPoint("BOTTOMLEFT", 14, 13)
    card.info:SetPoint("RIGHT", card, "RIGHT", -214, 0)

    card.specButton = Theme.CreateButton(card, "", 190, 22)
    card.specButton:SetPoint("BOTTOMRIGHT", -14, 9)
    card.specButton:SetScript("OnClick", function(self)
        if self.action then
            self.action()
        end
    end)
    card.specButton:HookScript("OnEnter", function(self)
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tooltip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    card.specButton:HookScript("OnLeave", GameTooltip_Hide)
end

local function SetBadge(verdictKey, text)
    local color = verdictKey and Odds.VERDICTS[verdictKey].color or Theme.color.muted
    card.badge:SetBackdropColor(color[1], color[2], color[3], 0.16)
    card.badge:SetBackdropBorderColor(color[1], color[2], color[3], 0.9)
    card.badge.text:SetText(text)
    card.badge.text:SetTextColor(color[1], color[2], color[3])
end

local function UpdateSpecButton(source, bucket, specID, odds)
    local button = card.specButton
    button.action, button.tooltip = nil, nil
    local lootSpecID = BRH.GetLootSpecID()
    local viewed = BRH.GetSpecInfo(specID)

    if specID ~= lootSpecID and viewed then
        button.label:SetText("Make " .. viewed.name .. " my loot spec")
        button.tooltip = "Voidcores roll on your loot specialization. You are viewing " .. viewed.name ..
                             ", but your loot spec is different."
        button.action = function()
            BRH.SetLootSpec(specID)
        end
        button:Show()
        return
    end

    local best = Odds.BestSpec(source, bucket)
    if best and odds and best.spec.specID ~= specID and best.odds.pWish > odds.pWish then
        button.label:SetText("Better: " .. best.spec.name .. " " .. BRH.Percent(best.odds.pWish))
        button.tooltip = best.spec.name .. " has a " .. BRH.Percent(best.odds.pWish) ..
                             " chance at a wishlist item here. Click to view it."
        button.action = function()
            BRH.UI.SetViewSpec(best.spec.specID)
        end
        button:Show()
        return
    end
    button:Hide()
end

local function UpdateCard(source, bucket, specID, odds)
    local spec = BRH.GetSpecInfo(specID)
    local lootSpecID = BRH.GetLootSpecID()
    card.title:SetText(source.name)
    card.subtitle:SetText(JoinParts(source.kind == "raid" and source.instanceName or nil,
        Pool.BucketLabel(source, bucket),
        spec and (spec.name .. (specID == lootSpecID and " (your loot spec)" or " loot")) or nil))

    if not odds then
        SetBadge(nil, "Loading…")
        card.bar:SetSegments({})
        for _, def in ipairs(STATS) do
            card.stats[def.key].value:SetText("–")
            card.stats[def.key].count:SetText("")
        end
        card.info:SetText(Pool.IsBlocked() and "Close the Adventure Guide to finish loading this loot." or
                              "Reading loot from the Adventure Guide…")
        card.specButton:Hide()
        return
    end

    local verdict = Odds.VERDICTS[odds.verdict]
    SetBadge(odds.verdict, verdict.label)
    card.bar:SetSegments({
        { odds.pWish, Theme.color.wish },
        { odds.pDupe, Theme.color.looted },
        { odds.pOther, Theme.color.other },
        { odds.pAvoid, Theme.color.avoid }
    })
    local fractions = {
        wish = odds.pWish,
        avoid = odds.pAvoid,
        dupe = odds.pDupe,
        other = odds.pOther
    }
    for _, def in ipairs(STATS) do
        local stat = card.stats[def.key]
        stat.value:SetText(odds.remaining > 0 and BRH.Percent(fractions[def.key]) or "–")
        stat.count:SetText(string.format("%d of %d", odds[def.key], odds.remaining))
    end

    local info
    if odds.total == 0 then
        info = "This spec gets nothing from a Voidcore here."
    elseif odds.refilled then
        info = string.format("You won all %d items – the pool refills on your next roll.", odds.total)
    else
        info = string.format("%d of %d items left in the pool", odds.remaining, odds.total)
        if odds.rolled > 0 then
            info = info .. string.format(" · %d bonus-rolled", odds.rolled)
        end
        if odds.expectedRolls then
            info = info .. string.format(" · ~%.1f rolls per wishlist item", odds.expectedRolls)
        end
    end
    card.info:SetText(info)
    UpdateSpecButton(source, bucket, specID, odds)
end

-- ── Loot tiles ────────────────────────────────────────────────────────────────

local function ShowTileTooltip(tile)
    GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
    if tile.link then
        GameTooltip:SetHyperlink(tile.link)
    else
        GameTooltip:SetItemByID(tile.itemID)
    end
    GameTooltip:AddLine(" ")
    local mark = History.GetMark(tile.itemID)
    if mark == "wish" then
        GameTooltip:AddLine("On your wishlist", Theme.Unpack(Theme.color.wish))
    elseif mark == "avoid" then
        GameTooltip:AddLine("On your avoid list", Theme.Unpack(Theme.color.avoid))
    end
    if tile.rolledEntry then
        GameTooltip:AddLine(RolledText(tile.rolledEntry), Theme.Unpack(Theme.color.rolled))
        GameTooltip:AddLine("Out of this pool until the pool refills.", Theme.Unpack(Theme.color.muted))
    elseif History.IsLooted(tile.itemID) then
        GameTooltip:AddLine("Looted – you already have this item", Theme.Unpack(Theme.color.looted))
        GameTooltip:AddLine("Still in the pool: a Voidcore can give it to you again.", Theme.Unpack(Theme.color.muted))
    end
    GameTooltip:AddLine("Left-click: wishlist   Right-click: more options", Theme.Unpack(Theme.color.muted))
    GameTooltip:Show()
end

local function ShowTileMenu(tile)
    local itemID = tile.itemID
    local source, bucket = current.source, current.bucket
    local rolledEntry = tile.rolledEntry
    MenuUtil.CreateContextMenu(tile, function(_, root)
        root:CreateTitle(tile.name:GetText() or "")
        root:CreateCheckbox("Wishlist", function()
            return History.GetMark(itemID) == "wish"
        end, function()
            History.ToggleMark(itemID, "wish")
        end)
        root:CreateCheckbox("Avoid", function()
            return History.GetMark(itemID) == "avoid"
        end, function()
            History.ToggleMark(itemID, "avoid")
        end)
        root:CreateDivider()
        root:CreateCheckbox("Looted (I have this item)", function()
            return History.IsLooted(itemID)
        end, function()
            History.SetLooted(itemID, not History.IsLooted(itemID))
        end)
        if rolledEntry and not rolledEntry.manual then
            root:CreateTitle("Bonus-rolled (from Simulationcraft)")
        else
            root:CreateCheckbox("Bonus-rolled on " .. Pool.ShortBucketLabel(source.kind, bucket), function()
                return History.IsManualRolled(source, bucket, itemID)
            end, function()
                History.SetManualRolled(source, bucket, itemID, not History.IsManualRolled(source, bucket, itemID))
            end)
        end
    end)
end

local function CreateTile(parent)
    local tile = CreateFrame("Button", nil, parent, "BackdropTemplate")
    tile:SetSize(tileWidth, TILE_HEIGHT)
    Theme.ApplyBackdrop(tile, Theme.color.raised, Theme.color.border)
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    tile.accent = tile:CreateTexture(nil, "ARTWORK")
    tile.accent:SetPoint("TOPLEFT", 1, -1)
    tile.accent:SetPoint("BOTTOMLEFT", 1, 1)
    tile.accent:SetWidth(3)

    tile.iconFrame = Theme.CreatePanel(tile, Theme.color.track)
    tile.iconFrame:SetSize(38, 38)
    tile.iconFrame:SetPoint("LEFT", 10, 0)
    tile.icon = tile.iconFrame:CreateTexture(nil, "ARTWORK")
    tile.icon:SetPoint("TOPLEFT", 1, -1)
    tile.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    tile.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tile.badge = tile.iconFrame:CreateTexture(nil, "OVERLAY")
    tile.badge:SetSize(18, 18)
    tile.badge:SetPoint("BOTTOMRIGHT", 5, -5)

    tile.avoidToggle = Theme.CreateIconToggle(tile, Theme.icon.avoid, 18)
    tile.avoidToggle:SetPoint("RIGHT", -10, 0)
    tile.avoidToggle.tooltip = "Avoid"
    tile.avoidToggle:SetScript("OnClick", function()
        History.ToggleMark(tile.itemID, "avoid")
    end)
    tile.wishToggle = Theme.CreateIconToggle(tile, Theme.icon.wish, 18)
    tile.wishToggle:SetPoint("RIGHT", tile.avoidToggle, "LEFT", -6, 0)
    tile.wishToggle.tooltip = "Wishlist"
    tile.wishToggle:SetScript("OnClick", function()
        History.ToggleMark(tile.itemID, "wish")
    end)

    tile.name = Theme.CreateText(tile, "GameFontNormal")
    tile.name:SetPoint("TOPLEFT", tile.iconFrame, "TOPRIGHT", 9, -3)
    tile.name:SetPoint("RIGHT", tile.wishToggle, "LEFT", -8, 0)
    tile.detail = Theme.CreateText(tile, "GameFontHighlightSmall", Theme.color.muted)
    tile.detail:SetPoint("BOTTOMLEFT", tile.iconFrame, "BOTTOMRIGHT", 9, 3)
    tile.detail:SetPoint("RIGHT", tile.wishToggle, "LEFT", -8, 0)

    local highlight = tile:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.04)

    tile:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            ShowTileMenu(self)
        elseif (IsShiftKeyDown() or IsControlKeyDown()) and self.link then
            HandleModifiedItemClick(self.link)
        else
            History.ToggleMark(self.itemID, "wish")
        end
    end)
    tile:SetScript("OnEnter", ShowTileTooltip)
    tile:SetScript("OnLeave", GameTooltip_Hide)
    return tile
end

local function UpdateTile(tile, item, rolledEntry)
    local name, link, quality, icon = GetItemDisplay(item)
    local mark = History.GetMark(item.itemID)
    local looted = History.IsLooted(item.itemID)
    local r, g, b = BRH.QualityColor(quality)

    tile.itemID = item.itemID
    tile.link = link
    tile.rolledEntry = rolledEntry

    tile.icon:SetTexture(icon)
    tile.icon:SetDesaturated(rolledEntry ~= nil)
    if mark == "avoid" and not rolledEntry then
        tile.icon:SetVertexColor(1, 0.6, 0.6)
    else
        tile.icon:SetVertexColor(1, 1, 1)
    end
    tile.iconFrame:SetBackdropBorderColor(r, g, b, 1)
    tile.name:SetText(name)
    tile.name:SetTextColor(r, g, b)

    -- Colour = what you want.
    local markColor = (mark == "wish" and Theme.color.wish) or (mark == "avoid" and Theme.color.avoid)
    if markColor then
        tile.accent:SetColorTexture(Theme.Unpack(markColor))
        tile.accent:Show()
        tile:SetBackdropBorderColor(markColor[1], markColor[2], markColor[3], 0.7)
    else
        tile.accent:Hide()
        tile:SetBackdropBorderColor(Theme.Unpack(Theme.color.border))
    end
    tile.wishToggle:SetActive(mark == "wish")
    tile.avoidToggle:SetActive(mark == "avoid")

    -- Badge = what you have.
    local slotText = JoinParts(item.slot, item.armorType)
    if rolledEntry then
        tile.badge:SetTexture(Theme.icon.rolled)
        tile.badge:Show()
        tile.detail:SetText(Theme.Colorize(RolledText(rolledEntry), Theme.color.rolled))
    elseif looted then
        tile.badge:SetTexture(Theme.icon.looted)
        tile.badge:Show()
        tile.detail:SetText(JoinParts(Theme.Colorize("Looted", Theme.color.looted), slotText))
    else
        tile.badge:Hide()
        tile.detail:SetText(slotText)
    end
    tile:SetAlpha(rolledEntry and 0.55 or 1)
end

-- Wishlist first, then neutral, then looted, then avoid; journal order within.
local function SortRank(item)
    local mark = History.GetMark(item.itemID)
    if mark == "wish" then
        return 1
    elseif mark == "avoid" then
        return 4
    elseif History.IsLooted(item.itemID) then
        return 3
    end
    return 2
end

local function SortItems(items)
    local rank, order = {}, {}
    for index, item in ipairs(items) do
        rank[item] = SortRank(item)
        order[item] = index
    end
    table.sort(items, function(a, b)
        if rank[a] ~= rank[b] then
            return rank[a] < rank[b]
        end
        return order[a] < order[b]
    end)
end

local function AcquireSectionLabel(index)
    local label = sectionLabels[index]
    if not label then
        label = Theme.CreateText(scroll.child, "GameFontNormalSmall", Theme.color.muted)
        sectionLabels[index] = label
    end
    label:Show()
    return label
end

local function AcquireTile(index)
    local tile = tiles[index]
    if not tile then
        tile = CreateTile(scroll.child)
        tiles[index] = tile
    end
    tile:Show()
    return tile
end

-- ── Public ────────────────────────────────────────────────────────────────────

function LootPanel.Create(parent, width)
    CreateCard(parent, width)

    local gridWidth = width - SCROLL_GUTTER
    tileWidth = math.floor((gridWidth - TILE_GAP) / 2)

    scroll = Theme.CreateScrollArea(parent, gridWidth)
    scroll:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -SCROLL_GUTTER, 0)

    emptyText = Theme.CreateText(parent, "GameFontHighlight", Theme.color.muted, "CENTER")
    emptyText:SetPoint("TOP", scroll, "TOP", 0, -40)
    emptyText:SetWidth(gridWidth - 40)
    emptyText:SetWordWrap(true)
end

function LootPanel.Update(source, bucket, specID)
    current.source, current.bucket, current.specID = source, bucket, specID

    for _, tile in ipairs(tiles) do
        tile:Hide()
    end
    for _, label in ipairs(sectionLabels) do
        label:Hide()
    end
    emptyText:Hide()

    if not source or not specID then
        card:Hide()
        emptyText:SetText("Pick a specialization to see Voidcore loot.")
        emptyText:Show()
        return
    end
    card:Show()

    local pool = Pool.GetPool(source, bucket, specID)
    local odds = pool and Odds.Compute(source, bucket, specID)
    UpdateCard(source, bucket, specID, odds)

    if not pool then
        return
    end
    if #pool == 0 then
        local spec = BRH.GetSpecInfo(specID)
        emptyText:SetText("No Voidcore loot for " .. (spec and spec.name or "this spec") .. " here.")
        emptyText:Show()
        scroll.child:SetHeight(1)
        return
    end

    local rolled = History.GetRolledSet(source, bucket)
    local inPool, outOfPool = {}, {}
    for _, item in ipairs(pool) do
        if rolled[item.itemID] and not odds.refilled then
            outOfPool[#outOfPool + 1] = item
        else
            inPool[#inPool + 1] = item
        end
    end
    SortItems(inPool)

    local y, tileIndex, labelIndex = 0, 0, 0
    local function LayoutSection(title, items, rolledSet)
        if #items == 0 then
            return
        end
        labelIndex = labelIndex + 1
        local label = AcquireSectionLabel(labelIndex)
        label:ClearAllPoints()
        label:SetPoint("BOTTOMLEFT", scroll.child, "TOPLEFT", 2, -(y + SECTION_HEIGHT - 8))
        label:SetText(string.format("%s  (%d)", title, #items))
        y = y + SECTION_HEIGHT
        for index, item in ipairs(items) do
            tileIndex = tileIndex + 1
            local tile = AcquireTile(tileIndex)
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", scroll.child, "TOPLEFT", column * (tileWidth + TILE_GAP),
                -(y + row * (TILE_HEIGHT + TILE_GAP)))
            UpdateTile(tile, item, rolledSet and rolledSet[item.itemID])
        end
        y = y + math.ceil(#items / 2) * (TILE_HEIGHT + TILE_GAP)
    end

    LayoutSection("IN THE VOIDCORE POOL", inPool, nil)
    LayoutSection("BONUS-ROLLED · OUT OF THE POOL", outOfPool, rolled)
    scroll.child:SetHeight(math.max(y, 1))
end
