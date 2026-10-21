-- Bonus Roll Helper: flat dark theme and small widget builders.
local _, BRH = ...

local Theme = {}
BRH.Theme = Theme

local WHITE = "Interface\\Buttons\\WHITE8X8"

Theme.color = {
    window = { 0.050, 0.050, 0.068, 0.97 },
    panel = { 0.082, 0.082, 0.108, 1 },
    raised = { 0.115, 0.115, 0.150, 1 },
    border = { 0.20, 0.20, 0.26, 1 },
    accent = { 0.69, 0.40, 1.00, 1 },
    selected = { 0.30, 0.17, 0.46, 1 },
    text = { 0.93, 0.93, 0.96, 1 },
    muted = { 0.56, 0.56, 0.63, 1 },
    track = { 0.03, 0.03, 0.04, 1 },
    -- Item states
    wish = { 1.00, 0.80, 0.18, 1 },
    avoid = { 0.95, 0.30, 0.30, 1 },
    looted = { 0.30, 0.68, 1.00, 1 },
    rolled = { 0.40, 0.85, 0.45, 1 },
    other = { 0.34, 0.34, 0.42, 1 }
}

-- State icons: raid target star / cross for wishlist / avoid, a backpack for
-- looted, the ready-check tick for bonus-rolled.
Theme.icon = {
    wish = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
    avoid = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
    looted = "Interface\\Buttons\\Button-Backpack-Up",
    rolled = "Interface\\RaidFrame\\ReadyCheck-Ready",
    addon = "Interface\\Icons\\INV_Enchant_VoidSphere"
}

function Theme.Unpack(color, alpha)
    return color[1], color[2], color[3], alpha or color[4] or 1
end

function Theme.Hex(color)
    return string.format("ff%02x%02x%02x", math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5),
        math.floor(color[3] * 255 + 0.5))
end

function Theme.Colorize(text, color)
    return "|c" .. Theme.Hex(color) .. text .. "|r"
end

function Theme.ApplyBackdrop(frame, background, border)
    frame:SetBackdrop({
        bgFile = WHITE,
        edgeFile = WHITE,
        edgeSize = 1
    })
    frame:SetBackdropColor(Theme.Unpack(background or Theme.color.panel))
    frame:SetBackdropBorderColor(Theme.Unpack(border or Theme.color.border))
end

function Theme.CreatePanel(parent, background, border)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Theme.ApplyBackdrop(panel, background, border)
    return panel
end

function Theme.CreateText(parent, fontObject, color, justify)
    local text = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlight")
    if color then
        text:SetTextColor(Theme.Unpack(color))
    end
    text:SetJustifyH(justify or "LEFT")
    text:SetWordWrap(false)
    return text
end

function Theme.SetFontSize(text, size)
    local font, _, flags = text:GetFont()
    if font then
        text:SetFont(font, size, flags)
    end
end

function Theme.CreateRect(parent, layer, color)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    texture:SetColorTexture(Theme.Unpack(color))
    return texture
end

-- Horizontal bar split into coloured segments.
-- bar:SetSegments({ { fraction, color }, ... })
function Theme.CreateStackBar(parent, width, height)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width, height)
    bar.track = Theme.CreateRect(bar, "BACKGROUND", Theme.color.track)
    bar.track:SetAllPoints()
    bar.segments = {}

    function bar:SetSegments(values)
        local total = self:GetWidth()
        local x = 0
        for index, value in ipairs(values) do
            local segment = self.segments[index]
            if not segment then
                segment = self:CreateTexture(nil, "ARTWORK")
                self.segments[index] = segment
            end
            local w = math.min(math.floor(total * value[1] + 0.5), total - x)
            if w > 0 then
                segment:ClearAllPoints()
                segment:SetPoint("TOPLEFT", x, 0)
                segment:SetPoint("BOTTOMLEFT", x, 0)
                segment:SetWidth(w)
                segment:SetColorTexture(Theme.Unpack(value[2]))
                segment:Show()
                x = x + w
            else
                segment:Hide()
            end
        end
        for index = #values + 1, #self.segments do
            self.segments[index]:Hide()
        end
    end

    return bar
end

-- Flat button with an optional "selected" state.
function Theme.CreateButton(parent, label, width, height)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, height)
    Theme.ApplyBackdrop(button, Theme.color.raised, Theme.color.border)
    button.label = Theme.CreateText(button, "GameFontHighlightSmall", nil, "CENTER")
    button.label:SetPoint("CENTER")
    button.label:SetText(label)

    function button:Refresh()
        local hovered = self:IsMouseOver() and self:IsEnabled()
        self:SetBackdropColor(Theme.Unpack(self.selected and Theme.color.selected or Theme.color.raised))
        self:SetBackdropBorderColor(Theme.Unpack((self.selected or hovered) and Theme.color.accent or
                                                     Theme.color.border))
        self.label:SetTextColor(Theme.Unpack(self:IsEnabled() and Theme.color.text or Theme.color.muted))
    end

    function button:SetSelected(selected)
        self.selected = selected
        self:Refresh()
    end

    button:HookScript("OnEnter", button.Refresh)
    button:HookScript("OnLeave", button.Refresh)
    button:HookScript("OnEnable", button.Refresh)
    button:HookScript("OnDisable", button.Refresh)
    button:Refresh()
    return button
end

-- Small icon toggle (wishlist star / avoid cross on loot tiles).
function Theme.CreateIconToggle(parent, texture, size)
    local toggle = CreateFrame("Button", nil, parent)
    toggle:SetSize(size, size)
    toggle.icon = toggle:CreateTexture(nil, "ARTWORK")
    toggle.icon:SetAllPoints()
    toggle.icon:SetTexture(texture)

    function toggle:SetActive(active)
        self.active = active
        self.icon:SetDesaturated(not active)
        self.icon:SetAlpha(active and 1 or 0.22)
    end

    toggle:SetScript("OnEnter", function(self)
        if not self.active then
            self.icon:SetAlpha(0.7)
        end
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tooltip)
            GameTooltip:Show()
        end
    end)
    toggle:SetScript("OnLeave", function(self)
        self:SetActive(self.active)
        GameTooltip:Hide()
    end)
    toggle:SetActive(false)
    return toggle
end

-- Scroll area using Blizzard's ScrollFrameTemplate (MinimalScrollBar).
-- The scroll bar sits in a ~20px gutter to the right of the given width.
function Theme.CreateScrollArea(parent, width)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width, 1)
    scroll:SetScrollChild(child)
    if not scroll:GetScript("OnMouseWheel") then
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local range = self:GetVerticalScrollRange()
            local value = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40))
            self:SetVerticalScroll(value)
        end)
    end
    scroll.child = child
    return scroll
end
