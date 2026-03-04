-- Parsec: Options Panel (pfUI/TargetRadar-style sidebar)
-- Dark theme, widget factories, lazy panel loading
-- WoW 1.12 / Lua 5.0 compliant (F={} single-table pattern)

local P = Parsec
if not P then return end

table.insert(P._loadedFiles, "options")

-- ============================================================
-- F: SINGLE STATE TABLE (avoids 32-upvalue limit)
-- ============================================================
local F = {}
F.frame = nil
F.sidebar = nil
F.contentArea = nil
F.panels = {}
F.activeCategory = 0
F.sidebarButtons = {}

-- ============================================================
-- LAYOUT CONSTANTS
-- ============================================================
F.PANEL_W = 460
F.PANEL_H = 380
F.SIDEBAR_W = 90
F.BANNER_H = 52
F.PADDING = 10
F.SPACING = 6
F.CHECK_SIZE = 18
F.SLIDER_H = 14
F.BTN_H = 20

-- ============================================================
-- COLORS
-- ============================================================
F.BG_MAIN   = { 0.06, 0.06, 0.08, 0.97 }
F.BG_SIDE   = { 0.04, 0.04, 0.06, 1.0 }
F.BG_ACTIVE = { 0.00, 0.20, 0.35, 1.0 }
F.CYAN      = { 0, 0.8, 1 }
F.WHITE     = { 1, 1, 1 }
F.GRAY      = { 0.5, 0.5, 0.5 }
F.DARK      = { 0.08, 0.08, 0.12 }

-- ============================================================
-- ICON PATHS
-- ============================================================
F.ICONS = {
    eye       = "Interface\\AddOns\\Parsec\\textures\\icon-eye",
    eyeClosed = "Interface\\AddOns\\Parsec\\textures\\icon-eye-closed",
    lock      = "Interface\\AddOns\\Parsec\\textures\\icon-lock",
    minimap   = "Interface\\AddOns\\Parsec\\textures\\icon-minimap",
    merge     = "Interface\\AddOns\\Parsec\\textures\\icon-merge",
    group     = "Interface\\AddOns\\Parsec\\textures\\icon-group",
    palette   = "Interface\\AddOns\\Parsec\\textures\\icon-palette",
    backdrop  = "Interface\\AddOns\\Parsec\\textures\\icon-backdrop",
    general   = "Interface\\AddOns\\Parsec\\textures\\icon-general",
    windows   = "Interface\\AddOns\\Parsec\\textures\\icon-windows",
    automation= "Interface\\AddOns\\Parsec\\textures\\icon-automation",
    about     = "Interface\\AddOns\\Parsec\\textures\\icon-about",
}

-- ============================================================
-- WIDGET: Section Header
-- ============================================================
function F:CreateSectionHeader(parent, text, yOffset)
    -- Cyan line
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)
    line:SetTexture(F.CYAN[1], F.CYAN[2], F.CYAN[3], 0.4)

    -- Label
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -(yOffset + 4))
    label:SetText("|cff00ccff" .. text .. "|r")

    return yOffset + 18
end

-- ============================================================
-- WIDGET: Checkbox with icon
-- ============================================================
function F:CreateCheckbox(parent, label, iconKey, settingKey, yOffset)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(F.CHECK_SIZE + 2)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)

    -- Icon (16x16)
    if iconKey and F.ICONS[iconKey] then
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(16)
        icon:SetHeight(16)
        icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        icon:SetTexture(F.ICONS[iconKey])
    end

    -- Checkbox (custom styled)
    local cb = CreateFrame("CheckButton", nil, row)
    cb:SetWidth(F.CHECK_SIZE)
    cb:SetHeight(F.CHECK_SIZE)
    cb:SetPoint("LEFT", row, "LEFT", 20, 0)

    -- Checkbox background
    local cbBG = cb:CreateTexture(nil, "BACKGROUND")
    cbBG:SetAllPoints(cb)
    cbBG:SetTexture(F.DARK[1], F.DARK[2], F.DARK[3], 0.8)

    -- Checkbox border
    local cbBorder = cb:CreateTexture(nil, "BORDER")
    cbBorder:SetWidth(F.CHECK_SIZE + 2)
    cbBorder:SetHeight(F.CHECK_SIZE + 2)
    cbBorder:SetPoint("CENTER", cb, "CENTER", 0, 0)
    cbBorder:SetTexture(0.3, 0.3, 0.3, 1)
    cb:SetNormalTexture(cbBorder)

    -- Check mark (cyan square when checked)
    local checkTex = cb:CreateTexture(nil, "OVERLAY")
    checkTex:SetWidth(F.CHECK_SIZE - 6)
    checkTex:SetHeight(F.CHECK_SIZE - 6)
    checkTex:SetPoint("CENTER", cb, "CENTER", 0, 0)
    checkTex:SetTexture(F.CYAN[1], F.CYAN[2], F.CYAN[3], 1)
    cb:SetCheckedTexture(checkTex)

    -- Highlight
    local hlTex = cb:CreateTexture(nil, "HIGHLIGHT")
    hlTex:SetAllPoints(cb)
    hlTex:SetTexture(1, 1, 1, 0.1)
    cb:SetHighlightTexture(hlTex)

    -- Label text
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    text:SetText(label)
    text:SetTextColor(1, 1, 1)

    -- Click handler for the whole row
    local capturedKey = settingKey
    local capturedCb = cb
    row:SetScript("OnClick", function()
        local checked = not capturedCb:GetChecked()
        if checked then capturedCb:SetChecked(1) else capturedCb:SetChecked(nil) end
        P.settings[capturedKey] = checked
        P.SaveSettings()
        P.ApplySettings()
    end)

    cb:SetScript("OnClick", function()
        local checked = (this:GetChecked() == 1)
        P.settings[capturedKey] = checked
        P.SaveSettings()
        P.ApplySettings()
    end)

    cb.settingKey = capturedKey
    row.checkbox = cb

    return row, yOffset + F.CHECK_SIZE + F.SPACING
end

-- ============================================================
-- WIDGET: Slider
-- ============================================================
function F:CreateSlider(parent, label, settingKey, minVal, maxVal, step, yOffset, isPercent)
    -- Label
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
    lbl:SetText(label)
    lbl:SetTextColor(1, 1, 1)

    -- Value display
    local valText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valText:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)
    valText:SetTextColor(F.CYAN[1], F.CYAN[2], F.CYAN[3])

    yOffset = yOffset + 14

    -- Slider frame
    local slider = CreateFrame("Slider", "ParsecOpt_" .. settingKey, parent)
    slider:SetWidth(1)  -- will stretch via anchoring
    slider:SetHeight(F.SLIDER_H)
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -yOffset)
    slider:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -yOffset)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:EnableMouse(true)
    slider:SetOrientation("HORIZONTAL")

    -- Track background
    local trackBG = slider:CreateTexture(nil, "BACKGROUND")
    trackBG:SetAllPoints(slider)
    trackBG:SetTexture(F.DARK[1], F.DARK[2], F.DARK[3], 0.8)

    -- Track border
    local trackBorder = slider:CreateTexture(nil, "BORDER")
    trackBorder:SetPoint("TOPLEFT", slider, "TOPLEFT", -1, 1)
    trackBorder:SetPoint("BOTTOMRIGHT", slider, "BOTTOMRIGHT", 1, -1)
    trackBorder:SetTexture(0.25, 0.25, 0.25, 1)

    -- Thumb texture
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(10)
    thumb:SetHeight(F.SLIDER_H + 4)
    thumb:SetTexture(F.CYAN[1], F.CYAN[2], F.CYAN[3], 0.8)
    slider:SetThumbTexture(thumb)

    -- Capture for closure
    local capturedKey = settingKey
    local capturedPct = isPercent
    local capturedValText = valText

    slider:SetScript("OnValueChanged", function()
        local val = this:GetValue()
        P.settings[capturedKey] = val
        if capturedPct then
            capturedValText:SetText(string.format("%.0f%%", val * 100))
        else
            capturedValText:SetText(string.format("%.0f", val))
        end
        P.SaveSettings()
        P.ApplySettings()
    end)

    slider.settingKey = capturedKey
    slider.valueText = valText
    slider.isPercent = isPercent

    return slider, yOffset + F.SLIDER_H + F.SPACING + 4
end

-- ============================================================
-- WIDGET: Small Button
-- ============================================================
function F:CreateSmallButton(parent, text, width, yOffset, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(width)
    btn:SetHeight(F.BTN_H)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)

    -- BG
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(btn)
    bg:SetTexture(F.DARK[1], F.DARK[2], F.DARK[3], 0.9)

    -- Border
    local border = btn:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    border:SetTexture(0.3, 0.3, 0.3, 1)

    -- Text
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText(text)
    label:SetTextColor(1, 1, 1)

    -- Highlight
    btn:SetScript("OnEnter", function()
        bg:SetTexture(F.CYAN[1] * 0.2, F.CYAN[2] * 0.2, F.CYAN[3] * 0.2, 0.9)
    end)
    btn:SetScript("OnLeave", function()
        bg:SetTexture(F.DARK[1], F.DARK[2], F.DARK[3], 0.9)
    end)

    btn:SetScript("OnClick", onClick)

    return btn, yOffset + F.BTN_H + F.SPACING
end

-- ============================================================
-- WIDGET: Texture Picker (Prev/Next)
-- ============================================================
function F:CreateTexturePicker(parent, label, settingKey, yOffset)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
    lbl:SetText(label)
    lbl:SetTextColor(1, 1, 1)

    yOffset = yOffset + 14

    -- Container row
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)

    -- Prev button
    local prev = CreateFrame("Button", nil, row)
    prev:SetWidth(20)
    prev:SetHeight(20)
    prev:SetPoint("LEFT", row, "LEFT", 0, 0)
    local prevText = prev:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    prevText:SetPoint("CENTER", prev, "CENTER", 0, 0)
    prevText:SetText("<")
    prevText:SetTextColor(F.CYAN[1], F.CYAN[2], F.CYAN[3])
    local prevBG = prev:CreateTexture(nil, "BACKGROUND")
    prevBG:SetAllPoints(prev)
    prevBG:SetTexture(F.DARK[1], F.DARK[2], F.DARK[3], 0.8)

    -- Name label
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    nameText:SetTextColor(1, 1, 1)

    -- Next button
    local next = CreateFrame("Button", nil, row)
    next:SetWidth(20)
    next:SetHeight(20)
    next:SetPoint("LEFT", nameText, "RIGHT", 6, 0)
    local nextText = next:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nextText:SetPoint("CENTER", next, "CENTER", 0, 0)
    nextText:SetText(">")
    nextText:SetTextColor(F.CYAN[1], F.CYAN[2], F.CYAN[3])
    local nextBG = next:CreateTexture(nil, "BACKGROUND")
    nextBG:SetAllPoints(next)
    nextBG:SetTexture(F.DARK[1], F.DARK[2], F.DARK[3], 0.8)

    -- Preview bar
    local previewBar = CreateFrame("StatusBar", nil, row)
    previewBar:SetWidth(120)
    previewBar:SetHeight(14)
    previewBar:SetPoint("LEFT", next, "RIGHT", 8, 0)
    previewBar:SetMinMaxValues(0, 1)
    previewBar:SetValue(0.7)
    previewBar:SetStatusBarColor(F.CYAN[1], F.CYAN[2], F.CYAN[3])

    local previewBG = previewBar:CreateTexture(nil, "BACKGROUND")
    previewBG:SetAllPoints(previewBar)
    previewBG:SetTexture(0.1, 0.1, 0.1, 1)

    -- Capture for closure
    local capturedKey = settingKey
    local capturedName = nameText
    local capturedPreview = previewBar

    local function UpdateDisplay()
        local idx = P.settings[capturedKey] or 1
        local texPath = P.BAR_TEXTURES[idx] or P.BAR_TEXTURES[1]
        local texName = P.BAR_TEXTURE_NAMES[idx] or "?"
        capturedName:SetText(texName)
        capturedPreview:SetStatusBarTexture(texPath)
    end

    prev:SetScript("OnClick", function()
        local idx = P.settings[capturedKey] or 1
        idx = idx - 1
        if idx < 1 then idx = table.getn(P.BAR_TEXTURES) end
        P.settings[capturedKey] = idx
        P.SaveSettings()
        P.ApplySettings()
        UpdateDisplay()
    end)

    next:SetScript("OnClick", function()
        local idx = P.settings[capturedKey] or 1
        idx = idx + 1
        if idx > table.getn(P.BAR_TEXTURES) then idx = 1 end
        P.settings[capturedKey] = idx
        P.SaveSettings()
        P.ApplySettings()
        UpdateDisplay()
    end)

    row.UpdateDisplay = UpdateDisplay

    return row, yOffset + 24 + F.SPACING
end

-- ============================================================
-- MAIN FRAME
-- ============================================================
function F:CreateMainFrame()
    if self.frame then return end

    local f = CreateFrame("Frame", "ParsecOptionsPanel", UIParent)
    f:SetWidth(self.PANEL_W)
    f:SetHeight(self.PANEL_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(self.BG_MAIN[1], self.BG_MAIN[2], self.BG_MAIN[3], self.BG_MAIN[4])
    f:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()

    table.insert(UISpecialFrames, "ParsecOptionsPanel")

    -- Drag to move
    f:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then this:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function()
        this:StopMovingOrSizing()
    end)

    self.frame = f

    -- Banner
    self:CreateBanner()

    -- Close button
    self:CreateCloseButton()

    -- Sidebar
    self:CreateSidebar()

    -- Content area
    self:CreateContentArea()

    -- Show first category
    self:SelectCategory(1)
end

-- ============================================================
-- BANNER
-- ============================================================
function F:CreateBanner()
    local f = self.frame

    local banner = f:CreateTexture(nil, "ARTWORK")
    banner:SetTexture("Interface\\AddOns\\Parsec\\textures\\banner")
    banner:SetHeight(self.BANNER_H)
    banner:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    banner:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", banner, "TOP", 0, -8)
    title:SetText("PARSEC")
    title:SetTextColor(0, 0.8, 1)

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -2)
    sub:SetText("Damage Meter")
    sub:SetTextColor(0.7, 0.7, 0.7)

    local ver = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ver:SetPoint("BOTTOMRIGHT", banner, "BOTTOMRIGHT", -6, 4)
    ver:SetText("v" .. P.VERSION)
    ver:SetTextColor(0.4, 0.4, 0.4)

    self.bannerFrame = banner
end

-- ============================================================
-- CLOSE BUTTON
-- ============================================================
function F:CreateCloseButton()
    local btn = CreateFrame("Button", nil, self.frame)
    btn:SetWidth(18)
    btn:SetHeight(18)
    btn:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -6, -6)

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    text:SetText("X")
    text:SetTextColor(0.6, 0.6, 0.6)

    btn:SetScript("OnEnter", function()
        text:SetTextColor(1, 0.3, 0.3)
    end)
    btn:SetScript("OnLeave", function()
        text:SetTextColor(0.6, 0.6, 0.6)
    end)
    btn:SetScript("OnClick", function()
        F.frame:Hide()
    end)
end

-- ============================================================
-- SIDEBAR
-- ============================================================
function F:CreateSidebar()
    local f = self.frame
    local topY = -(4 + self.BANNER_H)

    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetWidth(self.SIDEBAR_W)
    sidebar:SetPoint("TOPLEFT", f, "TOPLEFT", 4, topY)
    sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 4)

    local bg = sidebar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(sidebar)
    bg:SetTexture(self.BG_SIDE[1], self.BG_SIDE[2], self.BG_SIDE[3], self.BG_SIDE[4])

    self.sidebar = sidebar

    -- Category definitions
    local categories = {
        { name = "General",    icon = self.ICONS.general },
        { name = "Windows",    icon = self.ICONS.windows },
        { name = "Automation", icon = self.ICONS.automation },
        { name = "About",      icon = self.ICONS.about },
    }

    local btnH = 28
    local yOff = 4

    for i = 1, table.getn(categories) do
        local cat = categories[i]
        local capturedIdx = i

        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetWidth(self.SIDEBAR_W - 4)
        btn:SetHeight(btnH)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 2, -yOff)

        -- Background
        local btnBG = btn:CreateTexture(nil, "BACKGROUND")
        btnBG:SetAllPoints(btn)
        btnBG:SetTexture(0, 0, 0, 0)

        -- Icon
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(16)
        icon:SetHeight(16)
        icon:SetPoint("LEFT", btn, "LEFT", 6, 0)
        icon:SetTexture(cat.icon)

        -- Label
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        label:SetText(cat.name)
        label:SetTextColor(0.7, 0.7, 0.7)

        -- Left accent (cyan, visible when active)
        local accent = btn:CreateTexture(nil, "OVERLAY")
        accent:SetWidth(2)
        accent:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        accent:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        accent:SetTexture(self.CYAN[1], self.CYAN[2], self.CYAN[3], 1)
        accent:Hide()

        btn.bg = btnBG
        btn.label = label
        btn.accent = accent

        btn:SetScript("OnClick", function()
            F:SelectCategory(capturedIdx)
        end)
        btn:SetScript("OnEnter", function()
            if F.activeCategory ~= capturedIdx then
                btnBG:SetTexture(1, 1, 1, 0.05)
            end
        end)
        btn:SetScript("OnLeave", function()
            if F.activeCategory ~= capturedIdx then
                btnBG:SetTexture(0, 0, 0, 0)
            end
        end)

        self.sidebarButtons[i] = btn

        -- Panel definition
        self.panels[i] = {
            label = cat.name,
            built = false,
            contentFrame = nil,
        }

        yOff = yOff + btnH + 2
    end
end

-- ============================================================
-- CONTENT AREA
-- ============================================================
function F:CreateContentArea()
    local f = self.frame
    local topY = -(4 + self.BANNER_H)
    local leftX = 4 + self.SIDEBAR_W + 2

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", leftX, topY)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)

    local bg = content:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(content)
    bg:SetTexture(self.BG_MAIN[1], self.BG_MAIN[2], self.BG_MAIN[3], 0.5)

    self.contentArea = content
end

-- ============================================================
-- CATEGORY SELECTION
-- ============================================================
function F:SelectCategory(idx)
    if self.activeCategory == idx then return end

    -- Deactivate old
    for i = 1, table.getn(self.sidebarButtons) do
        local btn = self.sidebarButtons[i]
        btn.bg:SetTexture(0, 0, 0, 0)
        btn.label:SetTextColor(0.7, 0.7, 0.7)
        btn.accent:Hide()
        if self.panels[i].contentFrame then
            self.panels[i].contentFrame:Hide()
        end
    end

    -- Activate new
    self.activeCategory = idx
    local btn = self.sidebarButtons[idx]
    btn.bg:SetTexture(self.BG_ACTIVE[1], self.BG_ACTIVE[2], self.BG_ACTIVE[3], self.BG_ACTIVE[4])
    btn.label:SetTextColor(1, 1, 1)
    btn.accent:Show()

    -- Lazy build panel
    if not self.panels[idx].built then
        self:BuildPanel(idx)
        self.panels[idx].built = true
    end

    if self.panels[idx].contentFrame then
        self.panels[idx].contentFrame:Show()
    end

    self:RefreshPanel(idx)
end

-- ============================================================
-- PANEL BUILDERS
-- ============================================================
function F:BuildPanel(idx)
    local panel = CreateFrame("Frame", nil, self.contentArea)
    panel:SetAllPoints(self.contentArea)
    self.panels[idx].contentFrame = panel
    self.panels[idx].controls = {}

    if idx == 1 then self:BuildGeneralPanel(panel, idx)
    elseif idx == 2 then self:BuildWindowsPanel(panel, idx)
    elseif idx == 3 then self:BuildAutomationPanel(panel, idx)
    elseif idx == 4 then self:BuildAboutPanel(panel, idx)
    end
end

-- ============================================================
-- GENERAL PANEL
-- ============================================================
function F:BuildGeneralPanel(panel, idx)
    local y = self.PADDING
    local ctrls = self.panels[idx].controls

    y = self:CreateSectionHeader(panel, "Tracking", y)

    local cb1, y1 = self:CreateCheckbox(panel, "Merge pet damage with owner", "merge", "mergePets", y)
    ctrls.mergePets = cb1.checkbox
    y = y1

    local cb2, y2 = self:CreateCheckbox(panel, "Track all units (not just group)", "group", "trackAll", y)
    ctrls.trackAll = cb2.checkbox
    y = y2

    y = y + 4
    y = self:CreateSectionHeader(panel, "Appearance", y)

    local cb3, y3 = self:CreateCheckbox(panel, "Use pastel class colors", "palette", "pastelColors", y)
    ctrls.pastelColors = cb3.checkbox
    y = y3

    local cb4, y4 = self:CreateCheckbox(panel, "Show window backdrop", "backdrop", "showBackdrop", y)
    ctrls.showBackdrop = cb4.checkbox
    y = y4

    y = y + 4

    local sl1, y5 = self:CreateSlider(panel, "Bar Height:", "barHeight", 8, 24, 1, y, false)
    ctrls.barHeight = sl1
    y = y5

    local sl2, y6 = self:CreateSlider(panel, "Bar Spacing:", "barSpacing", 0, 4, 1, y, false)
    ctrls.barSpacing = sl2
    y = y6

    local sl3, y7 = self:CreateSlider(panel, "Window Opacity:", "bgOpacity", 0.3, 1.0, 0.05, y, true)
    ctrls.bgOpacity = sl3
    y = y7

    y = y + 2

    local tp1, y8 = self:CreateTexturePicker(panel, "Bar Texture:", "barTexture", y)
    ctrls.barTexture = tp1
    y = y8
end

-- ============================================================
-- WINDOWS PANEL
-- ============================================================
function F:BuildWindowsPanel(panel, idx)
    local y = self.PADDING
    local ctrls = self.panels[idx].controls

    y = self:CreateSectionHeader(panel, "Window Options", y)

    local cb1, y1 = self:CreateCheckbox(panel, "Lock window positions", "lock", "lockWindows", y)
    ctrls.lockWindows = cb1.checkbox
    y = y1

    y = y + 8
    y = self:CreateSectionHeader(panel, "Actions", y)

    local _, y2 = self:CreateSmallButton(panel, "Reset Positions", 130, y, function()
        local numWin = table.getn(P.windows)
        for i = 1, numWin do
            local w = P.windows[i]
            w:ClearAllPoints()
            w:SetPoint("CENTER", UIParent, "CENTER", (i - (numWin + 1) / 2) * 230, 0)
            w:SetWidth(220)
            w:SetHeight(200)
            if P.OnWindowResize then P.OnWindowResize(w) end
        end
        P.Print("Window positions reset.")
    end)
    y = y2

    local _, y3 = self:CreateSmallButton(panel, "Reset All Data", 130, y, function()
        if P.dataStore then
            P.dataStore:ResetAll()
        end
    end)
    y = y3

    local _, y4 = self:CreateSmallButton(panel, "Reset Current Segment", 150, y, function()
        if P.dataStore then
            P.dataStore:ResetCurrent()
            P.Print("Current segment reset.")
        end
    end)
    y = y4
end

-- ============================================================
-- AUTOMATION PANEL
-- ============================================================
function F:BuildAutomationPanel(panel, idx)
    local y = self.PADDING
    local ctrls = self.panels[idx].controls

    y = self:CreateSectionHeader(panel, "Combat Automation", y)

    local cb1, y1 = self:CreateCheckbox(panel, "Auto-show windows on combat start", "eye", "autoShow", y)
    ctrls.autoShow = cb1.checkbox
    y = y1

    local cb2, y2 = self:CreateCheckbox(panel, "Auto-hide windows after combat", "eyeClosed", "autoHide", y)
    ctrls.autoHide = cb2.checkbox
    y = y2

    y = y + 8
    y = self:CreateSectionHeader(panel, "UI Elements", y)

    local cb3, y3 = self:CreateCheckbox(panel, "Show minimap button", "minimap", "showMinimap", y)
    ctrls.showMinimap = cb3.checkbox
    y = y3
end

-- ============================================================
-- ABOUT PANEL
-- ============================================================
function F:BuildAboutPanel(panel, idx)
    local y = self.PADDING

    y = self:CreateSectionHeader(panel, "Parsec Damage Meter", y)

    local lines = {
        "|cff00ccffVersion:|r " .. P.VERSION,
        "|cff00ccffAuthor:|r Shemp",
        "|cff00ccffRequires:|r SuperWoW + Nampower",
        "",
        "|cff00ccffSlash Commands:|r",
        "  /parsec - Toggle windows",
        "  /parsec show / hide",
        "  /parsec reset - Reset all data",
        "  /parsec options - This panel",
        "  /parsec minimap - Toggle minimap",
        "  /parsec debug - Debug mode",
        "  /parsec pets - Pet owner cache",
        "  /parsec drains - Drain summary",
        "  /parsec stats - Statistics",
        "  /parsec help - All commands",
    }

    for i = 1, table.getn(lines) do
        local text = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -y)
        text:SetText(lines[i])
        text:SetTextColor(0.8, 0.8, 0.8)
        y = y + 14
    end
end

-- ============================================================
-- REFRESH (update controls from current settings)
-- ============================================================
function F:RefreshPanel(idx)
    local panel = self.panels[idx]
    if not panel or not panel.controls then return end
    local ctrls = panel.controls
    local s = P.settings

    -- Checkboxes
    for key, cb in pairs(ctrls) do
        if cb and cb.SetChecked then
            if s[key] then cb:SetChecked(1) else cb:SetChecked(nil) end
        end
    end

    -- Sliders
    for key, sl in pairs(ctrls) do
        if sl and sl.SetValue and sl.settingKey then
            local val = s[sl.settingKey]
            if val then
                sl:SetValue(val)
                if sl.valueText then
                    if sl.isPercent then
                        sl.valueText:SetText(string.format("%.0f%%", val * 100))
                    else
                        sl.valueText:SetText(string.format("%.0f", val))
                    end
                end
            end
        end
    end

    -- Texture picker
    if ctrls.barTexture and ctrls.barTexture.UpdateDisplay then
        ctrls.barTexture.UpdateDisplay()
    end
end

-- ============================================================
-- PUBLIC API
-- ============================================================
function P.ToggleOptions()
    F:CreateMainFrame()
    if F.frame:IsVisible() then
        F.frame:Hide()
    else
        -- Refresh active panel
        if F.activeCategory > 0 then
            F:RefreshPanel(F.activeCategory)
        end
        F.frame:Show()
    end
end

function P.ShowOptions()
    F:CreateMainFrame()
    if F.activeCategory > 0 then
        F:RefreshPanel(F.activeCategory)
    end
    F.frame:Show()
end

function P.HideOptions()
    if F.frame then F.frame:Hide() end
end
