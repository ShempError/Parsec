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
function F:CreateCheckbox(parent, label, settingKey, yOffset)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(F.CHECK_SIZE + 2)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)

    -- Checkbox (custom styled)
    local cb = CreateFrame("CheckButton", nil, row)
    cb:SetWidth(F.CHECK_SIZE)
    cb:SetHeight(F.CHECK_SIZE)
    cb:SetPoint("LEFT", row, "LEFT", 0, 0)

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
    thumb:SetWidth(12)
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
    bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    bg:SetTexture(F.DARK[1], F.DARK[2], F.DARK[3], 0.9)

    -- Border edges (matching title bar button style)
    local bTop = btn:CreateTexture(nil, "BORDER")
    bTop:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    bTop:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    bTop:SetHeight(1)
    bTop:SetTexture(0.3, 0.3, 0.3, 0.8)

    local bBot = btn:CreateTexture(nil, "BORDER")
    bBot:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    bBot:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    bBot:SetHeight(1)
    bBot:SetTexture(0.3, 0.3, 0.3, 0.8)

    local bL = btn:CreateTexture(nil, "BORDER")
    bL:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    bL:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    bL:SetWidth(1)
    bL:SetTexture(0.3, 0.3, 0.3, 0.8)

    local bR = btn:CreateTexture(nil, "BORDER")
    bR:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    bR:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    bR:SetWidth(1)
    bR:SetTexture(0.3, 0.3, 0.3, 0.8)

    -- Text
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText(text)
    label:SetTextColor(0.9, 0.9, 0.9)

    -- Hover: cyan border
    btn:SetScript("OnEnter", function()
        label:SetTextColor(1, 1, 1)
        bTop:SetTexture(F.CYAN[1], F.CYAN[2], F.CYAN[3], 0.6)
        bBot:SetTexture(F.CYAN[1], F.CYAN[2], F.CYAN[3], 0.6)
        bL:SetTexture(F.CYAN[1], F.CYAN[2], F.CYAN[3], 0.6)
        bR:SetTexture(F.CYAN[1], F.CYAN[2], F.CYAN[3], 0.6)
    end)
    btn:SetScript("OnLeave", function()
        label:SetTextColor(0.9, 0.9, 0.9)
        bTop:SetTexture(0.3, 0.3, 0.3, 0.8)
        bBot:SetTexture(0.3, 0.3, 0.3, 0.8)
        bL:SetTexture(0.3, 0.3, 0.3, 0.8)
        bR:SetTexture(0.3, 0.3, 0.3, 0.8)
    end)

    btn:SetScript("OnClick", onClick)

    return btn, yOffset + F.BTN_H + F.SPACING
end

-- ============================================================
-- WIDGET: Texture Picker (Prev/Next + full-width preview)
-- ============================================================
function F:CreateTexturePicker(parent, label, settingKey, yOffset)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
    lbl:SetText(label)
    lbl:SetTextColor(1, 1, 1)

    yOffset = yOffset + 14

    -- Layout: [Prev 20] [4] [Name 80 fixed] [4] [Next 20] [8] [Preview->RIGHT]
    local NAME_W = 80

    -- Container row (stretches full width)
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

    -- Fixed-width name container (prevents layout shift)
    local nameFrame = CreateFrame("Frame", nil, row)
    nameFrame:SetWidth(NAME_W)
    nameFrame:SetHeight(20)
    nameFrame:SetPoint("LEFT", prev, "RIGHT", 4, 0)

    local nameText = nameFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("CENTER", nameFrame, "CENTER", 0, 0)
    nameText:SetTextColor(1, 1, 1)

    -- Next button (anchored to fixed-width nameFrame — never shifts)
    local nextBtn = CreateFrame("Button", nil, row)
    nextBtn:SetWidth(20)
    nextBtn:SetHeight(20)
    nextBtn:SetPoint("LEFT", nameFrame, "RIGHT", 4, 0)
    local nextText = nextBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nextText:SetPoint("CENTER", nextBtn, "CENTER", 0, 0)
    nextText:SetText(">")
    nextText:SetTextColor(F.CYAN[1], F.CYAN[2], F.CYAN[3])
    local nextBG = nextBtn:CreateTexture(nil, "BACKGROUND")
    nextBG:SetAllPoints(nextBtn)
    nextBG:SetTexture(F.DARK[1], F.DARK[2], F.DARK[3], 0.8)

    -- Preview bar (stretches from next button to right edge)
    local previewBar = CreateFrame("StatusBar", nil, row)
    previewBar:SetHeight(16)
    previewBar:SetPoint("LEFT", nextBtn, "RIGHT", 8, 0)
    previewBar:SetPoint("RIGHT", row, "RIGHT", -80, 0)
    previewBar:SetMinMaxValues(0, 1)
    previewBar:SetValue(1)

    local previewBG = previewBar:CreateTexture(nil, "BACKGROUND")
    previewBG:SetAllPoints(previewBar)
    previewBG:SetTexture(0.1, 0.1, 0.1, 0.6)

    -- Preview bar FontStrings (mimics real bar layout)
    local pvName = previewBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pvName:SetPoint("LEFT", previewBar, "LEFT", 4, 0)
    pvName:SetJustifyH("LEFT")

    local pvValue = previewBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pvValue:SetPoint("RIGHT", previewBar, "RIGHT", -4, 0)
    pvValue:SetJustifyH("RIGHT")
    pvValue:SetTextColor(1, 0.82, 0)
    pvValue:SetText("1,234")

    pvName:SetPoint("RIGHT", pvValue, "LEFT", -4, 0)

    -- Capture for closure
    local capturedKey = settingKey
    local capturedName = nameText
    local capturedPreview = previewBar
    local capturedPvName = pvName
    local capturedPvValue = pvValue

    local function UpdateDisplay()
        local s = P.settings
        local idx = s[capturedKey] or 1
        local texPath = P.BAR_TEXTURES[idx] or P.BAR_TEXTURES[1]
        local texName = P.BAR_TEXTURE_NAMES[idx] or "?"
        capturedName:SetText(texName)
        capturedPreview:SetStatusBarTexture(texPath)

        -- Class color from current player
        local playerName = UnitName("player") or "Player"
        local cc = P.GetClassColor(playerName)
        if cc then
            capturedPreview:SetStatusBarColor(cc.r, cc.g, cc.b)
        end
        capturedPvName:SetText(playerName)

        -- Apply font shadow + outline to preview FontStrings
        local shadowA = s.fontShadow and 1 or 0
        local shadowOff = s.fontShadow and 1 or 0
        local outlineFlag = s.fontOutline and "OUTLINE" or ""
        local fontStrings = { capturedPvName, capturedPvValue }
        for k = 1, 2 do
            local fs = fontStrings[k]
            local fontPath, fontSize = fs:GetFont()
            if fontPath then
                fs:SetFont(fontPath, fontSize, outlineFlag)
            end
            fs:SetShadowColor(0, 0, 0, shadowA)
            fs:SetShadowOffset(shadowOff, -shadowOff)
        end
    end

    -- Register callback so ApplySettings can refresh preview
    P._refreshTexturePreview = UpdateDisplay

    prev:SetScript("OnClick", function()
        local idx = P.settings[capturedKey] or 1
        idx = idx - 1
        if idx < 1 then idx = table.getn(P.BAR_TEXTURES) end
        P.settings[capturedKey] = idx
        P.SaveSettings()
        P.ApplySettings()
        UpdateDisplay()
    end)

    nextBtn:SetScript("OnClick", function()
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
        bgFile = "Interface\\AddOns\\Parsec\\textures\\window-bg",
        edgeFile = "Interface\\AddOns\\Parsec\\textures\\window-border",
        tile = true, tileSize = 128, edgeSize = 16,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(1, 1, 1, self.BG_MAIN[4])
    f:SetBackdropBorderColor(1, 1, 1, 1)
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
        { name = "Bars",       icon = self.ICONS.general },
        { name = "Window",     icon = self.ICONS.windows },
        { name = "Automation", icon = self.ICONS.automation },
        { name = "Modules",    icon = self.ICONS.general },
        { name = "Channels",   icon = self.ICONS.general },
        { name = "Deaths",     icon = self.ICONS.general },
        { name = "About",      icon = self.ICONS.about },
        { name = "Debug",      icon = self.ICONS.about },
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

    if idx == 1 then self:BuildBarsPanel(panel, idx)
    elseif idx == 2 then self:BuildWindowPanel(panel, idx)
    elseif idx == 3 then self:BuildAutomationPanel(panel, idx)
    elseif idx == 4 then self:BuildModulesPanel(panel, idx)
    elseif idx == 5 then self:BuildChannelsPanel(panel, idx)
    elseif idx == 6 then self:BuildDeathsPanel(panel, idx)
    elseif idx == 7 then self:BuildAboutPanel(panel, idx)
    elseif idx == 8 then self:BuildDebugPanel(panel, idx)
    end
end

-- ============================================================
-- BARS PANEL (barHeight, barSpacing, barTexture, mergePets)
-- ============================================================
function F:BuildBarsPanel(panel, idx)
    local y = self.PADDING
    local ctrls = self.panels[idx].controls

    y = self:CreateSectionHeader(panel, "Bar Appearance", y)

    local sl1, y1 = self:CreateSlider(panel, "Bar Height:", "barHeight", 8, 24, 1, y, false)
    ctrls.barHeight = sl1
    y = y1

    local sl2, y2 = self:CreateSlider(panel, "Bar Spacing:", "barSpacing", 0, 4, 1, y, false)
    ctrls.barSpacing = sl2
    y = y2

    y = y + 2

    local tp1, y3 = self:CreateTexturePicker(panel, "Bar Texture:", "barTexture", y)
    ctrls.barTexture = tp1
    y = y3

    y = y + 2

    local cb1, y4 = self:CreateCheckbox(panel, "Font Shadow", "fontShadow", y)
    ctrls.fontShadow = cb1.checkbox
    y = y4

    local cb3, y6 = self:CreateCheckbox(panel, "Font Outline", "fontOutline", y)
    ctrls.fontOutline = cb3.checkbox
    y = y6

    y = y + 4
    y = self:CreateSectionHeader(panel, "Data", y)

    local cb2, y5 = self:CreateCheckbox(panel, "Merge pet damage with owner", "mergePets", y)
    ctrls.mergePets = cb2.checkbox
    y = y5
end

-- ============================================================
-- WINDOW PANEL (bgOpacity, showBackdrop, lockWindows, Reset buttons)
-- ============================================================
function F:BuildWindowPanel(panel, idx)
    local y = self.PADDING
    local ctrls = self.panels[idx].controls

    y = self:CreateSectionHeader(panel, "Window Settings", y)

    local cb1, y1 = self:CreateCheckbox(panel, "Show window backdrop", "showBackdrop", y)
    ctrls.showBackdrop = cb1.checkbox
    y = y1

    local cb2, y2 = self:CreateCheckbox(panel, "Lock window positions", "lockWindows", y)
    ctrls.lockWindows = cb2.checkbox
    y = y2

    local cb_cycle, y_cycle = self:CreateCheckbox(panel, "Click title to cycle metric", "clickToCycleView", y)
    ctrls.clickToCycleView = cb_cycle.checkbox
    y = y_cycle

    local sl1, y3 = self:CreateSlider(panel, "Background Opacity:", "bgOpacity", 0.3, 1.0, 0.05, y, true)
    ctrls.bgOpacity = sl1
    y = y3

    local sl_tt, y_tt = self:CreateSlider(panel, "Tooltip Opacity:", "tooltipOpacity", 0.3, 1.0, 0.05, y, true)
    ctrls.tooltipOpacity = sl_tt
    y = y_tt

    y = y + 4
    y = self:CreateSectionHeader(panel, "Actions", y)

    local _, y4 = self:CreateSmallButton(panel, "Reset Positions", 130, y, function()
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
    y = y4

    local _, y5 = self:CreateSmallButton(panel, "Reset All Data", 130, y, function()
        if P.dataStore then
            P.dataStore:ResetAll()
        end
    end)
    y = y5

    local _, y6 = self:CreateSmallButton(panel, "Reset Current Segment", 150, y, function()
        if P.dataStore then
            P.dataStore:ResetCurrent()
            P.Print("Current segment reset.")
        end
    end)
    y = y6
end

-- ============================================================
-- AUTOMATION PANEL
-- ============================================================
function F:BuildAutomationPanel(panel, idx)
    local y = self.PADDING
    local ctrls = self.panels[idx].controls

    y = self:CreateSectionHeader(panel, "Combat Automation", y)

    local cb1, y1 = self:CreateCheckbox(panel, "Auto-show windows on combat start", "autoShow", y)
    ctrls.autoShow = cb1.checkbox
    y = y1

    local cb2, y2 = self:CreateCheckbox(panel, "Auto-hide windows after combat", "autoHide", y)
    ctrls.autoHide = cb2.checkbox
    y = y2

    y = y + 8
    y = self:CreateSectionHeader(panel, "UI Elements", y)

    local cb3, y3 = self:CreateCheckbox(panel, "Show minimap button", "showMinimap", y)
    ctrls.showMinimap = cb3.checkbox
    y = y3

    local cb4, y4 = self:CreateCheckbox(panel, "Track all units (not just group)", "trackAll", y)
    ctrls.trackAll = cb4.checkbox
    y = y4

    y = y + 8
    y = self:CreateSectionHeader(panel, "Fight History", y)

    local sl1, y5 = self:CreateSlider(panel, "Max Saved Fights:", "historyLimit", 1, 25, 1, y, false)
    ctrls.historyLimit = sl1
    y = y5

    local btnClear, y6 = self:CreateSmallButton(panel, "Clear History", 90, y, function()
        if P.dataStore then
            P.dataStore:ClearHistory()
        end
    end)
    y = y6
end

-- ============================================================
-- CHANNELS PANEL (announce channel selection with chat colors)
-- ============================================================

-- Standard channels (always shown)
F.STANDARD_CHANNELS = {
    { key = "SAY",           label = "Say (/s)",             chatType = "SAY" },
    { key = "PARTY",         label = "Party (/p)",           chatType = "PARTY" },
    { key = "GUILD",         label = "Guild (/g)",           chatType = "GUILD" },
    { key = "RAID",          label = "Raid (/raid)",         chatType = "RAID" },
    { key = "BATTLEGROUND",  label = "Battleground (/bg)",   chatType = "BATTLEGROUND" },
}

-- Dynamic channel rows (for cleanup/rebuild)
F.channelRows = {}
F.channelsPanel = nil
F.channelsYStart = 0

function F:BuildChannelsPanel(panel, idx)
    local y = self.PADDING
    y = self:CreateSectionHeader(panel, "Standard Channels", y)

    self.channelsPanel = panel
    self.channelsYStart = y

    -- Standard channel checkboxes
    for i = 1, table.getn(self.STANDARD_CHANNELS) do
        local ch = self.STANDARD_CHANNELS[i]
        y = self:CreateChannelRow(panel, ch.key, ch.label, ch.chatType, y)
    end

    -- Separator + Custom channels header
    y = y + 4
    self.customChannelsHeaderY = y
    y = self:CreateSectionHeader(panel, "Custom Channels", y)
    self.customChannelsStartY = y

    -- Container for dynamic custom channel rows
    self.customChannelsContainer = CreateFrame("Frame", nil, panel)
    self.customChannelsContainer:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -y)
    self.customChannelsContainer:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -y)
    self.customChannelsContainer:SetHeight(200)

    -- Build custom channel rows
    self:RebuildCustomChannelRows()
end

function F:CreateChannelRow(parent, chKey, label, chatType, yOffset)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(self.CHECK_SIZE + 2)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)

    -- Checkbox
    local cb = CreateFrame("CheckButton", nil, row)
    cb:SetWidth(self.CHECK_SIZE)
    cb:SetHeight(self.CHECK_SIZE)
    cb:SetPoint("LEFT", row, "LEFT", 0, 0)

    local cbBG = cb:CreateTexture(nil, "BACKGROUND")
    cbBG:SetAllPoints(cb)
    cbBG:SetTexture(self.DARK[1], self.DARK[2], self.DARK[3], 0.8)

    local cbBorder = cb:CreateTexture(nil, "BORDER")
    cbBorder:SetWidth(self.CHECK_SIZE + 2)
    cbBorder:SetHeight(self.CHECK_SIZE + 2)
    cbBorder:SetPoint("CENTER", cb, "CENTER", 0, 0)
    cbBorder:SetTexture(0.3, 0.3, 0.3, 1)
    cb:SetNormalTexture(cbBorder)

    local checkTex = cb:CreateTexture(nil, "OVERLAY")
    checkTex:SetWidth(self.CHECK_SIZE - 6)
    checkTex:SetHeight(self.CHECK_SIZE - 6)
    checkTex:SetPoint("CENTER", cb, "CENTER", 0, 0)
    checkTex:SetTexture(self.CYAN[1], self.CYAN[2], self.CYAN[3], 1)
    cb:SetCheckedTexture(checkTex)

    local hlTex = cb:CreateTexture(nil, "HIGHLIGHT")
    hlTex:SetAllPoints(cb)
    hlTex:SetTexture(1, 1, 1, 0.1)
    cb:SetHighlightTexture(hlTex)

    -- Channel color from ChatTypeInfo
    local cr, cg, cb2 = 1, 1, 1
    if ChatTypeInfo and ChatTypeInfo[chatType] then
        cr = ChatTypeInfo[chatType].r or 1
        cg = ChatTypeInfo[chatType].g or 1
        cb2 = ChatTypeInfo[chatType].b or 1
    end

    -- Color swatch (small square showing channel color)
    local swatch = row:CreateTexture(nil, "ARTWORK")
    swatch:SetWidth(12)
    swatch:SetHeight(12)
    swatch:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    swatch:SetTexture(cr, cg, cb2, 1)

    -- Label text in channel color
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    text:SetText(label)
    text:SetTextColor(cr, cg, cb2)

    -- State from settings
    local ec = P.settings.enabledChannels or {}
    if ec[chKey] then cb:SetChecked(1) else cb:SetChecked(nil) end

    -- Click handlers
    local capturedKey = chKey
    local capturedCb = cb
    row:SetScript("OnClick", function()
        local checked = not capturedCb:GetChecked()
        if checked then capturedCb:SetChecked(1) else capturedCb:SetChecked(nil) end
        if not P.settings.enabledChannels then P.settings.enabledChannels = {} end
        P.settings.enabledChannels[capturedKey] = checked
        P.SaveSettings()
    end)

    cb:SetScript("OnClick", function()
        local checked = (this:GetChecked() == 1)
        if not P.settings.enabledChannels then P.settings.enabledChannels = {} end
        P.settings.enabledChannels[capturedKey] = checked
        P.SaveSettings()
    end)

    return yOffset + self.CHECK_SIZE + self.SPACING
end

function F:RebuildCustomChannelRows()
    -- Clear old dynamic rows
    for i = 1, table.getn(self.channelRows) do
        self.channelRows[i]:Hide()
    end
    self.channelRows = {}

    if not self.customChannelsContainer then return end
    local container = self.customChannelsContainer

    local y = 0
    local found = false

    -- GetChannelList returns: id1, name1, id2, name2, ...
    if GetChannelList then
        local chList = { GetChannelList() }
        for i = 1, table.getn(chList), 2 do
            local chId = chList[i]
            local chName = chList[i + 1]
            if chName then
                found = true
                local chKey = "CHANNEL_" .. chName

                local row = CreateFrame("Button", nil, container)
                row:SetHeight(self.CHECK_SIZE + 2)
                row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -y)
                row:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -y)

                -- Checkbox
                local cb = CreateFrame("CheckButton", nil, row)
                cb:SetWidth(self.CHECK_SIZE)
                cb:SetHeight(self.CHECK_SIZE)
                cb:SetPoint("LEFT", row, "LEFT", 0, 0)

                local cbBG = cb:CreateTexture(nil, "BACKGROUND")
                cbBG:SetAllPoints(cb)
                cbBG:SetTexture(self.DARK[1], self.DARK[2], self.DARK[3], 0.8)

                local cbBorder = cb:CreateTexture(nil, "BORDER")
                cbBorder:SetWidth(self.CHECK_SIZE + 2)
                cbBorder:SetHeight(self.CHECK_SIZE + 2)
                cbBorder:SetPoint("CENTER", cb, "CENTER", 0, 0)
                cbBorder:SetTexture(0.3, 0.3, 0.3, 1)
                cb:SetNormalTexture(cbBorder)

                local checkTex = cb:CreateTexture(nil, "OVERLAY")
                checkTex:SetWidth(self.CHECK_SIZE - 6)
                checkTex:SetHeight(self.CHECK_SIZE - 6)
                checkTex:SetPoint("CENTER", cb, "CENTER", 0, 0)
                checkTex:SetTexture(self.CYAN[1], self.CYAN[2], self.CYAN[3], 1)
                cb:SetCheckedTexture(checkTex)

                -- Channel color (per-channel: CHANNEL1, CHANNEL2, etc.)
                local chatType = "CHANNEL" .. chId
                local cr, cg, cb2 = 1, 0.75, 0.75
                if ChatTypeInfo and ChatTypeInfo[chatType] then
                    cr = ChatTypeInfo[chatType].r or cr
                    cg = ChatTypeInfo[chatType].g or cg
                    cb2 = ChatTypeInfo[chatType].b or cb2
                elseif ChatTypeInfo and ChatTypeInfo["CHANNEL"] then
                    cr = ChatTypeInfo["CHANNEL"].r or cr
                    cg = ChatTypeInfo["CHANNEL"].g or cg
                    cb2 = ChatTypeInfo["CHANNEL"].b or cb2
                end

                local swatch = row:CreateTexture(nil, "ARTWORK")
                swatch:SetWidth(12)
                swatch:SetHeight(12)
                swatch:SetPoint("LEFT", cb, "RIGHT", 6, 0)
                swatch:SetTexture(cr, cg, cb2, 1)

                local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                text:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
                text:SetText(chName .. " (/" .. chId .. ")")
                text:SetTextColor(cr, cg, cb2)

                -- State
                local ec = P.settings.enabledChannels or {}
                if ec[chKey] then cb:SetChecked(1) else cb:SetChecked(nil) end

                local capturedKey = chKey
                local capturedCb = cb
                row:SetScript("OnClick", function()
                    local checked = not capturedCb:GetChecked()
                    if checked then capturedCb:SetChecked(1) else capturedCb:SetChecked(nil) end
                    if not P.settings.enabledChannels then P.settings.enabledChannels = {} end
                    P.settings.enabledChannels[capturedKey] = checked
                    P.SaveSettings()
                end)

                cb:SetScript("OnClick", function()
                    local checked = (this:GetChecked() == 1)
                    if not P.settings.enabledChannels then P.settings.enabledChannels = {} end
                    P.settings.enabledChannels[capturedKey] = checked
                    P.SaveSettings()
                end)

                table.insert(self.channelRows, row)
                y = y + self.CHECK_SIZE + self.SPACING
            end
        end
    end

    if not found then
        local hint = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("TOPLEFT", container, "TOPLEFT", 4, 0)
        hint:SetText("|cff666666No custom channels joined|r")
        -- Wrap in a frame so we can hide it on rebuild
        local hintFrame = CreateFrame("Frame", nil, container)
        hintFrame:SetHeight(16)
        hintFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        hintFrame:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
        hint:SetParent(hintFrame)
        hint:SetPoint("LEFT", hintFrame, "LEFT", 4, 0)
        table.insert(self.channelRows, hintFrame)
    end
end

function F:RefreshChannelsPanel()
    if self.customChannelsContainer then
        self:RebuildCustomChannelRows()
    end
end

-- ============================================================
-- MODULES PANEL (enable/disable tracking modules)
-- ============================================================
function F:BuildModulesPanel(panel, idx)
    local y = self.PADDING
    y = self:CreateSectionHeader(panel, "Tracking Modules", y)

    local modules = {
        { key = "damage",  label = "Damage / DPS" },
        { key = "healing", label = "Healing / HPS" },
        { key = "deaths",  label = "Deaths" },
    }

    for i = 1, table.getn(modules) do
        local mod = modules[i]
        local capturedKey = mod.key

        local row = CreateFrame("Button", nil, panel)
        row:SetHeight(self.CHECK_SIZE + 2)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -y)

        local cb = CreateFrame("CheckButton", nil, row)
        cb:SetWidth(self.CHECK_SIZE)
        cb:SetHeight(self.CHECK_SIZE)
        cb:SetPoint("LEFT", row, "LEFT", 0, 0)

        local cbBG = cb:CreateTexture(nil, "BACKGROUND")
        cbBG:SetAllPoints(cb)
        cbBG:SetTexture(self.DARK[1], self.DARK[2], self.DARK[3], 0.8)

        local cbBorder = cb:CreateTexture(nil, "BORDER")
        cbBorder:SetWidth(self.CHECK_SIZE + 2)
        cbBorder:SetHeight(self.CHECK_SIZE + 2)
        cbBorder:SetPoint("CENTER", cb, "CENTER", 0, 0)
        cbBorder:SetTexture(0.3, 0.3, 0.3, 1)
        cb:SetNormalTexture(cbBorder)

        local checkTex = cb:CreateTexture(nil, "OVERLAY")
        checkTex:SetWidth(self.CHECK_SIZE - 6)
        checkTex:SetHeight(self.CHECK_SIZE - 6)
        checkTex:SetPoint("CENTER", cb, "CENTER", 0, 0)
        checkTex:SetTexture(self.CYAN[1], self.CYAN[2], self.CYAN[3], 1)
        cb:SetCheckedTexture(checkTex)

        local hlTex = cb:CreateTexture(nil, "HIGHLIGHT")
        hlTex:SetAllPoints(cb)
        hlTex:SetTexture(1, 1, 1, 0.1)
        cb:SetHighlightTexture(hlTex)

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        text:SetText(mod.label)
        text:SetTextColor(1, 1, 1)

        -- Init from nested setting
        if P.settings.modules and P.settings.modules[capturedKey] then
            cb:SetChecked(1)
        else
            cb:SetChecked(nil)
        end

        local capturedCb = cb
        row:SetScript("OnClick", function()
            local checked = not capturedCb:GetChecked()
            if checked then capturedCb:SetChecked(1) else capturedCb:SetChecked(nil) end
            if not P.settings.modules then P.settings.modules = {} end
            P.settings.modules[capturedKey] = checked
            P.SaveSettings()
            P.ApplySettings()
        end)

        cb:SetScript("OnClick", function()
            local checked = (this:GetChecked() == 1)
            if not P.settings.modules then P.settings.modules = {} end
            P.settings.modules[capturedKey] = checked
            P.SaveSettings()
            P.ApplySettings()
        end)

        y = y + self.CHECK_SIZE + self.SPACING
    end

    -- Info text
    y = y + 8
    local info = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    info:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -y)
    info:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -self.PADDING, -y)
    info:SetJustifyH("LEFT")
    info:SetText("Disabled modules stop tracking data and hide their views from the cycle menu.")
    info:SetTextColor(0.6, 0.6, 0.6)
end

-- ============================================================
-- DEATHS PANEL (deathAutoPopup, deathNotify, deathRecapOpacity)
-- ============================================================
function F:BuildDeathsPanel(panel, idx)
    local y = self.PADDING
    local ctrls = self.panels[idx].controls

    y = self:CreateSectionHeader(panel, "Death Recap", y)

    local cb1, y1 = self:CreateCheckbox(panel, "Auto-popup on own death", "deathAutoPopup", y)
    ctrls.deathAutoPopup = cb1
    y = y1

    local cb2, y2 = self:CreateCheckbox(panel, "Chat notifications on group deaths", "deathNotify", y)
    ctrls.deathNotify = cb2
    y = y2

    y = y + 4

    local sl1, y3 = self:CreateSlider(panel, "Recap Panel Opacity:", "deathRecapOpacity", 0.3, 1.0, 0.05, y, true)
    ctrls.deathRecapOpacity = sl1
    y = y3

    y = y + 10
    y = self:CreateSectionHeader(panel, "Actions", y)

    local btn1, y4 = self:CreateSmallButton(panel, "Open Death Recap", 130, y, function()
        if P.ShowDeathRecap then
            P.ShowDeathRecap()
        end
    end)
    y = y4

    y = y + 4

    local btn2, y5 = self:CreateSmallButton(panel, "Clear Death Log", 130, y, function()
        if P.deathLog then
            P.deathLog:ResetAll()
            P.Print("Death log cleared.")
        end
    end)
    y = y5
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
        "  /parsec stats - Statistics",
        "  /parsec history - Saved fights",
        "  /parsec fake - Test data",
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
-- DEBUG PANEL (message log for copy-paste)
-- ============================================================
function F:BuildDebugPanel(panel, idx)
    local y = self.PADDING
    local ctrls = self.panels[idx].controls

    y = self:CreateSectionHeader(panel, "Message Log", y)

    -- Button row
    local btnW = 70
    local btnSpacing = 6

    local btnSelect, y1 = self:CreateSmallButton(panel, "Select All", btnW, y, function()
        if F.debugEditBox then
            F.debugEditBox:SetFocus()
            F.debugEditBox:HighlightText()
        end
    end)
    y1 = y  -- keep same y, place buttons horizontally

    local btnClear = CreateFrame("Button", nil, panel)
    btnClear:SetWidth(btnW)
    btnClear:SetHeight(self.BTN_H)
    btnClear:SetPoint("LEFT", btnSelect, "RIGHT", btnSpacing, 0)

    -- BG + border for Clear button (matching CreateSmallButton style)
    local clBG = btnClear:CreateTexture(nil, "BACKGROUND")
    clBG:SetPoint("TOPLEFT", btnClear, "TOPLEFT", 1, -1)
    clBG:SetPoint("BOTTOMRIGHT", btnClear, "BOTTOMRIGHT", -1, 1)
    clBG:SetTexture(self.DARK[1], self.DARK[2], self.DARK[3], 0.9)
    local clT = btnClear:CreateTexture(nil, "BORDER")
    clT:SetPoint("TOPLEFT", btnClear, "TOPLEFT", 0, 0)
    clT:SetPoint("TOPRIGHT", btnClear, "TOPRIGHT", 0, 0)
    clT:SetHeight(1)
    clT:SetTexture(0.3, 0.3, 0.3, 0.8)
    local clB = btnClear:CreateTexture(nil, "BORDER")
    clB:SetPoint("BOTTOMLEFT", btnClear, "BOTTOMLEFT", 0, 0)
    clB:SetPoint("BOTTOMRIGHT", btnClear, "BOTTOMRIGHT", 0, 0)
    clB:SetHeight(1)
    clB:SetTexture(0.3, 0.3, 0.3, 0.8)
    local clL = btnClear:CreateTexture(nil, "BORDER")
    clL:SetPoint("TOPLEFT", btnClear, "TOPLEFT", 0, 0)
    clL:SetPoint("BOTTOMLEFT", btnClear, "BOTTOMLEFT", 0, 0)
    clL:SetWidth(1)
    clL:SetTexture(0.3, 0.3, 0.3, 0.8)
    local clR = btnClear:CreateTexture(nil, "BORDER")
    clR:SetPoint("TOPRIGHT", btnClear, "TOPRIGHT", 0, 0)
    clR:SetPoint("BOTTOMRIGHT", btnClear, "BOTTOMRIGHT", 0, 0)
    clR:SetWidth(1)
    clR:SetTexture(0.3, 0.3, 0.3, 0.8)
    local clLabel = btnClear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clLabel:SetPoint("CENTER", btnClear, "CENTER", 0, 0)
    clLabel:SetText("Clear")
    clLabel:SetTextColor(0.9, 0.9, 0.9)
    btnClear:SetScript("OnEnter", function()
        clLabel:SetTextColor(1, 1, 1)
        clT:SetTexture(F.CYAN[1], F.CYAN[2], F.CYAN[3], 0.6)
        clB:SetTexture(F.CYAN[1], F.CYAN[2], F.CYAN[3], 0.6)
        clL:SetTexture(F.CYAN[1], F.CYAN[2], F.CYAN[3], 0.6)
        clR:SetTexture(F.CYAN[1], F.CYAN[2], F.CYAN[3], 0.6)
    end)
    btnClear:SetScript("OnLeave", function()
        clLabel:SetTextColor(0.9, 0.9, 0.9)
        clT:SetTexture(0.3, 0.3, 0.3, 0.8)
        clB:SetTexture(0.3, 0.3, 0.3, 0.8)
        clL:SetTexture(0.3, 0.3, 0.3, 0.8)
        clR:SetTexture(0.3, 0.3, 0.3, 0.8)
    end)
    btnClear:SetScript("OnClick", function()
        P.messageLog = {}
        F:RefreshDebugLog()
    end)

    local btnRefresh = CreateFrame("Button", nil, panel)
    btnRefresh:SetWidth(btnW)
    btnRefresh:SetHeight(self.BTN_H)
    btnRefresh:SetPoint("LEFT", btnClear, "RIGHT", btnSpacing, 0)

    -- BG + border for Refresh button
    local rfBG = btnRefresh:CreateTexture(nil, "BACKGROUND")
    rfBG:SetPoint("TOPLEFT", btnRefresh, "TOPLEFT", 1, -1)
    rfBG:SetPoint("BOTTOMRIGHT", btnRefresh, "BOTTOMRIGHT", -1, 1)
    rfBG:SetTexture(self.DARK[1], self.DARK[2], self.DARK[3], 0.9)
    local rfT = btnRefresh:CreateTexture(nil, "BORDER")
    rfT:SetPoint("TOPLEFT", btnRefresh, "TOPLEFT", 0, 0)
    rfT:SetPoint("TOPRIGHT", btnRefresh, "TOPRIGHT", 0, 0)
    rfT:SetHeight(1)
    rfT:SetTexture(0.3, 0.3, 0.3, 0.8)
    local rfB = btnRefresh:CreateTexture(nil, "BORDER")
    rfB:SetPoint("BOTTOMLEFT", btnRefresh, "BOTTOMLEFT", 0, 0)
    rfB:SetPoint("BOTTOMRIGHT", btnRefresh, "BOTTOMRIGHT", 0, 0)
    rfB:SetHeight(1)
    rfB:SetTexture(0.3, 0.3, 0.3, 0.8)
    local rfL = btnRefresh:CreateTexture(nil, "BORDER")
    rfL:SetPoint("TOPLEFT", btnRefresh, "TOPLEFT", 0, 0)
    rfL:SetPoint("BOTTOMLEFT", btnRefresh, "BOTTOMLEFT", 0, 0)
    rfL:SetWidth(1)
    rfL:SetTexture(0.3, 0.3, 0.3, 0.8)
    local rfR = btnRefresh:CreateTexture(nil, "BORDER")
    rfR:SetPoint("TOPRIGHT", btnRefresh, "TOPRIGHT", 0, 0)
    rfR:SetPoint("BOTTOMRIGHT", btnRefresh, "BOTTOMRIGHT", 0, 0)
    rfR:SetWidth(1)
    rfR:SetTexture(0.3, 0.3, 0.3, 0.8)
    local rfLabel = btnRefresh:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rfLabel:SetPoint("CENTER", btnRefresh, "CENTER", 0, 0)
    rfLabel:SetText("Refresh")
    rfLabel:SetTextColor(0.9, 0.9, 0.9)
    btnRefresh:SetScript("OnEnter", function()
        rfLabel:SetTextColor(1, 1, 1)
        rfT:SetTexture(F.CYAN[1], F.CYAN[2], F.CYAN[3], 0.6)
        rfB:SetTexture(F.CYAN[1], F.CYAN[2], F.CYAN[3], 0.6)
        rfL:SetTexture(F.CYAN[1], F.CYAN[2], F.CYAN[3], 0.6)
        rfR:SetTexture(F.CYAN[1], F.CYAN[2], F.CYAN[3], 0.6)
    end)
    btnRefresh:SetScript("OnLeave", function()
        rfLabel:SetTextColor(0.9, 0.9, 0.9)
        rfT:SetTexture(0.3, 0.3, 0.3, 0.8)
        rfB:SetTexture(0.3, 0.3, 0.3, 0.8)
        rfL:SetTexture(0.3, 0.3, 0.3, 0.8)
        rfR:SetTexture(0.3, 0.3, 0.3, 0.8)
    end)
    btnRefresh:SetScript("OnClick", function()
        F:RefreshDebugLog()
    end)

    -- Hint text
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("LEFT", btnRefresh, "RIGHT", btnSpacing + 2, 0)
    hint:SetText("|cff888888Ctrl+A, Ctrl+C to copy|r")

    y = y + self.BTN_H + self.SPACING + 2

    -- ScrollFrame for the log
    local scrollFrame = CreateFrame("ScrollFrame", "ParsecDebugScroll", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -y)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 0)

    -- Dark background behind scroll area
    local scrollBG = panel:CreateTexture(nil, "BACKGROUND")
    scrollBG:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", -2, 2)
    scrollBG:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    scrollBG:SetTexture(0.03, 0.03, 0.05, 0.9)

    -- EditBox as scroll child
    local editBox = CreateFrame("EditBox", "ParsecDebugEditBox", scrollFrame)
    editBox:SetWidth(scrollFrame:GetWidth() or 320)
    editBox:SetFontObject(GameFontNormalSmall)
    editBox:SetTextColor(0.8, 0.8, 0.8)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetMaxLetters(99999)
    editBox:SetText("")
    editBox:SetScript("OnEscapePressed", function()
        this:ClearFocus()
    end)

    scrollFrame:SetScrollChild(editBox)
    self.debugEditBox = editBox
    self.debugScrollFrame = scrollFrame
end

function F:RefreshDebugLog()
    if not self.debugEditBox then return end

    local log = P.messageLog
    local text = ""
    for i = 1, table.getn(log) do
        if i > 1 then text = text .. "\n" end
        text = text .. log[i]
    end

    -- Force width from scroll frame (may have been 0 at creation)
    local sw = self.debugScrollFrame:GetWidth()
    if sw and sw > 50 then
        self.debugEditBox:SetWidth(sw - 4)
    end

    self.debugEditBox:SetText(text)

    -- Adjust height for scroll
    local numLines = table.getn(log)
    local lineH = 14
    local h = numLines * lineH
    if h < 100 then h = 100 end
    self.debugEditBox:SetHeight(h)

    -- Scroll to bottom
    if self.debugScrollFrame then
        self.debugScrollFrame:UpdateScrollChildRect()
        local maxScroll = self.debugScrollFrame:GetVerticalScrollRange()
        if maxScroll and maxScroll > 0 then
            self.debugScrollFrame:SetVerticalScroll(maxScroll)
        end
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

    -- Channels panel: rebuild dynamic rows
    if idx == 4 then
        self:RefreshChannelsPanel()
    end

    -- Debug log
    if idx == 8 then
        self:RefreshDebugLog()
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
