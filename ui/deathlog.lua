-- Parsec: Death Recap Panel v2
-- Split layout: Unit Frame (top) + Interactive Event Log (bottom)
-- Click event rows to inspect HP/resource/buffs/debuffs at that moment
-- WoW 1.12 / Lua 5.0 compliant (D={} single-table pattern)

local P = Parsec
if not P then return end

table.insert(P._loadedFiles, "deathlog")

-- ============================================================
-- D: SINGLE STATE TABLE (avoids 32-upvalue limit)
-- ============================================================
local D = {}
D.frame = nil
D.eventRows = {}
D.scrollOffset = 0
D.currentRecord = nil
D.currentList = {}
D.currentIndex = 1
D.playerFilter = nil
D.segmentFilter = nil
D.selectedEventIdx = nil
D.buffIcons = {}
D.debuffIcons = {}

-- ============================================================
-- LAYOUT CONSTANTS
-- ============================================================
D.WIDTH = 520
D.HEIGHT = 520
D.PADDING = 10
D.HEADER_H = 24
D.BAR_H = 14
D.ROW_H = 20
D.VISIBLE_ROWS = 10
D.NAV_H = 24
D.MAX_BUFFS = 16
D.MAX_DEBUFFS = 16
D.AURA_SIZE = 20
D.AURA_GAP = 2
D.SPELL_ICON_SIZE = 16
D.LEFT_INSET = 50   -- past class icon (10 pad + 32 icon + 8 gap)

-- ============================================================
-- COLORS & LOOKUP TABLES
-- ============================================================
D.BG_MAIN    = { 0.06, 0.06, 0.08, 0.97 }
D.CYAN       = { 0, 0.8, 1 }
D.RED        = { 1, 0.3, 0.3 }
D.GREEN      = { 0.3, 1, 0.3 }
D.YELLOW     = { 1, 0.82, 0 }
D.WHITE      = { 1, 1, 1 }
D.GRAY       = { 0.5, 0.5, 0.5 }
D.KILL_BG    = { 0.4, 0.08, 0.08, 0.6 }
D.HEAL_COLOR = { 0.2, 1, 0.2 }
D.MISS_COLOR = { 0.7, 0.7, 0.7 }
D.SELECT_BG  = { 0, 0.5, 0.7, 0.2 }

D.POWER_COLORS = {
    [0] = { r = 0.0, g = 0.0, b = 1.0 },   -- Mana
    [1] = { r = 1.0, g = 0.0, b = 0.0 },   -- Rage
    [2] = { r = 1.0, g = 0.5, b = 0.25 },  -- Focus
    [3] = { r = 1.0, g = 1.0, b = 0.0 },   -- Energy
}
D.POWER_NAMES = { [0] = "Mana", [1] = "Rage", [2] = "Focus", [3] = "Energy" }

D.CLASS_ICONS = {
    WARRIOR = "Interface\\Icons\\ClassIcon_Warrior",
    PALADIN = "Interface\\Icons\\ClassIcon_Paladin",
    HUNTER  = "Interface\\Icons\\ClassIcon_Hunter",
    ROGUE   = "Interface\\Icons\\ClassIcon_Rogue",
    PRIEST  = "Interface\\Icons\\ClassIcon_Priest",
    SHAMAN  = "Interface\\Icons\\ClassIcon_Shaman",
    MAGE    = "Interface\\Icons\\ClassIcon_Mage",
    WARLOCK = "Interface\\Icons\\ClassIcon_Warlock",
    DRUID   = "Interface\\Icons\\ClassIcon_Druid",
}

D.DEBUFF_COLORS = {
    Magic   = { r = 0.2, g = 0.6, b = 1.0 },
    Curse   = { r = 0.6, g = 0.0, b = 1.0 },
    Disease = { r = 0.6, g = 0.4, b = 0.0 },
    Poison  = { r = 0.0, g = 0.6, b = 0.0 },
}

---------------------------------------------------------------------------
-- Create the main frame
---------------------------------------------------------------------------

local function CreateMainFrame()
    local f = CreateFrame("Frame", "ParsecDeathRecapPanel", UIParent)
    f:SetWidth(D.WIDTH)
    f:SetHeight(D.HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    f:SetBackdrop({
        bgFile = "Interface\\AddOns\\Parsec\\textures\\window-bg",
        edgeFile = "Interface\\AddOns\\Parsec\\textures\\window-border",
        tile = true, tileSize = 128, edgeSize = 16,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(1, 1, 1, D.BG_MAIN[4])
    f:SetBackdropBorderColor(1, 1, 1, 1)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()

    table.insert(UISpecialFrames, "ParsecDeathRecapPanel")

    f:SetScript("OnMouseDown", function() this:StartMoving() end)
    f:SetScript("OnMouseUp", function() this:StopMovingOrSizing() end)

    return f
end

---------------------------------------------------------------------------
-- Header: skull icon + "DEATH RECAP" + close button
---------------------------------------------------------------------------

local function CreateHeader(parent)
    local hdr = CreateFrame("Frame", nil, parent)
    hdr:SetHeight(D.HEADER_H)
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4)
    hdr:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -4)

    local bg = hdr:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(hdr)
    bg:SetTexture(0.04, 0.04, 0.06, 1)

    local skull = hdr:CreateTexture(nil, "ARTWORK")
    skull:SetWidth(18)
    skull:SetHeight(18)
    skull:SetPoint("LEFT", hdr, "LEFT", 6, 0)
    skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")

    local title = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", skull, "RIGHT", 6, 0)
    title:SetText("DEATH RECAP")
    title:SetTextColor(D.CYAN[1], D.CYAN[2], D.CYAN[3])

    local closeBtn = CreateFrame("Button", nil, hdr)
    closeBtn:SetWidth(18)
    closeBtn:SetHeight(18)
    closeBtn:SetPoint("RIGHT", hdr, "RIGHT", -4, 0)
    local closeTex = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeTex:SetAllPoints(closeBtn)
    closeTex:SetText("X")
    closeTex:SetTextColor(0.8, 0.2, 0.2)
    closeBtn:SetScript("OnEnter", function() closeTex:SetTextColor(1, 0.4, 0.4) end)
    closeBtn:SetScript("OnLeave", function() closeTex:SetTextColor(0.8, 0.2, 0.2) end)
    closeBtn:SetScript("OnClick", function() parent:Hide() end)

    return hdr
end

---------------------------------------------------------------------------
-- Unit Frame: class icon, name, HP bar, resource bar, auras, kill info
---------------------------------------------------------------------------

local function CreateUnitFrame(parent, anchor)
    local uf = CreateFrame("Frame", nil, parent)
    uf:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    uf:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    uf:SetHeight(164)

    -- Class icon (32x32)
    uf.classIcon = uf:CreateTexture(nil, "ARTWORK")
    uf.classIcon:SetWidth(32)
    uf.classIcon:SetHeight(32)
    uf.classIcon:SetPoint("TOPLEFT", uf, "TOPLEFT", D.PADDING, -6)

    -- Player name (class colored)
    uf.nameText = uf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    uf.nameText:SetPoint("TOPLEFT", uf.classIcon, "TOPRIGHT", 8, -2)
    uf.nameText:SetJustifyH("LEFT")

    -- Class label (gray)
    uf.classLabel = uf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    uf.classLabel:SetPoint("LEFT", uf.nameText, "RIGHT", 4, -1)
    uf.classLabel:SetTextColor(D.GRAY[1], D.GRAY[2], D.GRAY[3])

    -- HP Bar
    uf.hpBar = CreateFrame("StatusBar", nil, uf)
    uf.hpBar:SetHeight(D.BAR_H)
    uf.hpBar:SetPoint("TOPLEFT", uf, "TOPLEFT", D.LEFT_INSET, -40)
    uf.hpBar:SetPoint("RIGHT", uf, "RIGHT", -D.PADDING, 0)
    uf.hpBar:SetStatusBarTexture("Interface\\AddOns\\Parsec\\textures\\bar-smooth")
    uf.hpBar:SetMinMaxValues(0, 1)
    uf.hpBar:SetValue(1)
    uf.hpBar:SetStatusBarColor(0.2, 0.8, 0.2)

    local hpBg = uf.hpBar:CreateTexture(nil, "BACKGROUND")
    hpBg:SetAllPoints(uf.hpBar)
    hpBg:SetTexture(0.12, 0.12, 0.12, 0.8)

    uf.hpText = uf.hpBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    uf.hpText:SetPoint("CENTER", uf.hpBar, "CENTER", 0, 0)
    uf.hpText:SetTextColor(1, 1, 1)
    uf.hpText:SetShadowColor(0, 0, 0, 1)
    uf.hpText:SetShadowOffset(1, -1)

    -- Resource Bar (below HP)
    uf.resBar = CreateFrame("StatusBar", nil, uf)
    uf.resBar:SetHeight(D.BAR_H)
    uf.resBar:SetPoint("TOPLEFT", uf.hpBar, "BOTTOMLEFT", 0, -2)
    uf.resBar:SetPoint("RIGHT", uf.hpBar, "RIGHT", 0, 0)
    uf.resBar:SetStatusBarTexture("Interface\\AddOns\\Parsec\\textures\\bar-smooth")
    uf.resBar:SetMinMaxValues(0, 1)
    uf.resBar:SetValue(0)
    uf.resBar:SetStatusBarColor(0, 0, 1)

    local resBg = uf.resBar:CreateTexture(nil, "BACKGROUND")
    resBg:SetAllPoints(uf.resBar)
    resBg:SetTexture(0.12, 0.12, 0.12, 0.8)

    uf.resText = uf.resBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    uf.resText:SetPoint("CENTER", uf.resBar, "CENTER", 0, 0)
    uf.resText:SetTextColor(1, 1, 1)
    uf.resText:SetShadowColor(0, 0, 0, 1)
    uf.resText:SetShadowOffset(1, -1)

    -- Buff row
    uf.buffRow = CreateFrame("Frame", nil, uf)
    uf.buffRow:SetHeight(D.AURA_SIZE)
    uf.buffRow:SetPoint("TOPLEFT", uf.resBar, "BOTTOMLEFT", 0, -6)
    uf.buffRow:SetPoint("RIGHT", uf, "RIGHT", -D.PADDING, 0)

    for i = 1, D.MAX_BUFFS do
        local icon = CreateFrame("Frame", nil, uf.buffRow)
        icon:SetWidth(D.AURA_SIZE)
        icon:SetHeight(D.AURA_SIZE)
        icon:SetPoint("LEFT", uf.buffRow, "LEFT", (i - 1) * (D.AURA_SIZE + D.AURA_GAP), 0)

        icon.tex = icon:CreateTexture(nil, "ARTWORK")
        icon.tex:SetAllPoints(icon)

        icon.stackText = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        icon.stackText:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
        icon.stackText:SetTextColor(1, 1, 1)
        icon.stackText:SetShadowColor(0, 0, 0, 1)
        icon.stackText:SetShadowOffset(1, -1)

        icon.auraID = nil
        icon.stackCount = 0
        icon:EnableMouse(true)
        icon:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            if this.auraID and SpellInfo then
                local name, rank = SpellInfo(this.auraID)
                GameTooltip:AddLine(name or "Unknown", 1, 1, 1)
                if rank and rank ~= "" then
                    GameTooltip:AddLine(rank, 0.7, 0.7, 0.7)
                end
            else
                GameTooltip:AddLine("Unknown Buff", 0.7, 0.7, 0.7)
            end
            if this.stackCount and this.stackCount > 1 then
                GameTooltip:AddLine(this.stackCount .. " stacks", 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        icon:Hide()
        D.buffIcons[i] = icon
    end

    -- Debuff row
    uf.debuffRow = CreateFrame("Frame", nil, uf)
    uf.debuffRow:SetHeight(D.AURA_SIZE)
    uf.debuffRow:SetPoint("TOPLEFT", uf.buffRow, "BOTTOMLEFT", 0, -D.AURA_GAP)
    uf.debuffRow:SetPoint("RIGHT", uf, "RIGHT", -D.PADDING, 0)

    for i = 1, D.MAX_DEBUFFS do
        local icon = CreateFrame("Frame", nil, uf.debuffRow)
        icon:SetWidth(D.AURA_SIZE)
        icon:SetHeight(D.AURA_SIZE)
        icon:SetPoint("LEFT", uf.debuffRow, "LEFT", (i - 1) * (D.AURA_SIZE + D.AURA_GAP), 0)

        -- Border texture (colored by debuff type)
        icon.border = icon:CreateTexture(nil, "BORDER")
        icon.border:SetAllPoints(icon)
        icon.border:SetTexture(0.8, 0, 0, 0.8)

        -- Icon texture (inset 1px for border visibility)
        icon.tex = icon:CreateTexture(nil, "ARTWORK")
        icon.tex:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
        icon.tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)

        icon.stackText = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        icon.stackText:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
        icon.stackText:SetTextColor(1, 1, 1)
        icon.stackText:SetShadowColor(0, 0, 0, 1)
        icon.stackText:SetShadowOffset(1, -1)

        icon.auraID = nil
        icon.stackCount = 0
        icon.debuffType = nil
        icon:EnableMouse(true)
        icon:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            if this.auraID and SpellInfo then
                local name, rank = SpellInfo(this.auraID)
                GameTooltip:AddLine(name or "Unknown", 1, 1, 1)
                if rank and rank ~= "" then
                    GameTooltip:AddLine(rank, 0.7, 0.7, 0.7)
                end
            else
                GameTooltip:AddLine("Unknown Debuff", 0.7, 0.7, 0.7)
            end
            if this.debuffType then
                GameTooltip:AddLine(this.debuffType, 0.6, 0.6, 0.6)
            end
            if this.stackCount and this.stackCount > 1 then
                GameTooltip:AddLine(this.stackCount .. " stacks", 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        icon:Hide()
        D.debuffIcons[i] = icon
    end

    -- Kill info line
    uf.killInfo = uf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    uf.killInfo:SetPoint("TOPLEFT", uf.debuffRow, "BOTTOMLEFT", 0, -6)
    uf.killInfo:SetPoint("RIGHT", uf, "RIGHT", -D.PADDING, 0)
    uf.killInfo:SetJustifyH("LEFT")

    -- Subinfo line
    uf.subInfo = uf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    uf.subInfo:SetPoint("TOPLEFT", uf.killInfo, "BOTTOMLEFT", 0, -2)
    uf.subInfo:SetJustifyH("LEFT")
    uf.subInfo:SetTextColor(D.GRAY[1], D.GRAY[2], D.GRAY[3])

    return uf
end

---------------------------------------------------------------------------
-- Separator: "EVENTS (click to inspect)"
---------------------------------------------------------------------------

local function CreateSeparator(parent, anchor)
    local sep = CreateFrame("Frame", nil, parent)
    sep:SetHeight(18)
    sep:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    sep:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)

    local bg = sep:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(sep)
    bg:SetTexture(0.04, 0.04, 0.06, 1)

    local txt = sep:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("LEFT", sep, "LEFT", D.PADDING, 0)
    txt:SetText("EVENTS (click to inspect)")
    txt:SetTextColor(D.CYAN[1], D.CYAN[2], D.CYAN[3])

    return sep
end

---------------------------------------------------------------------------
-- Event row: time | spell icon | spell (source) | amount | crit/miss
---------------------------------------------------------------------------

local function CreateEventRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(D.ROW_H)
    row:EnableMouse(true)
    row:EnableMouseWheel(true)

    -- Kill highlight background
    row.killBg = row:CreateTexture(nil, "BACKGROUND")
    row.killBg:SetAllPoints(row)
    row.killBg:SetTexture(0, 0, 0, 0)

    -- Selection highlight (above kill bg)
    row.selectBg = row:CreateTexture(nil, "BORDER")
    row.selectBg:SetAllPoints(row)
    row.selectBg:SetTexture(0, 0, 0, 0)

    -- Time offset
    row.timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.timeText:SetPoint("LEFT", row, "LEFT", D.PADDING, 0)
    row.timeText:SetWidth(42)
    row.timeText:SetJustifyH("RIGHT")
    row.timeText:SetTextColor(D.GRAY[1], D.GRAY[2], D.GRAY[3])

    -- Spell icon (16x16)
    row.spellIcon = row:CreateTexture(nil, "ARTWORK")
    row.spellIcon:SetWidth(D.SPELL_ICON_SIZE)
    row.spellIcon:SetHeight(D.SPELL_ICON_SIZE)
    row.spellIcon:SetPoint("LEFT", row.timeText, "RIGHT", 6, 0)

    -- Spell name + source
    row.spellText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.spellText:SetPoint("LEFT", row.spellIcon, "RIGHT", 4, 0)
    row.spellText:SetJustifyH("LEFT")
    row.spellText:SetTextColor(1, 1, 1)

    -- Crit/miss label (right side)
    row.flagText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.flagText:SetPoint("RIGHT", row, "RIGHT", -D.PADDING, 0)
    row.flagText:SetWidth(36)
    row.flagText:SetJustifyH("RIGHT")

    -- Amount (left of flag)
    row.amountText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.amountText:SetPoint("RIGHT", row.flagText, "LEFT", -4, 0)
    row.amountText:SetWidth(60)
    row.amountText:SetJustifyH("RIGHT")

    -- Limit spell text width
    row.spellText:SetPoint("RIGHT", row.amountText, "LEFT", -4, 0)

    -- State for click handling
    row.eventIndex = 0
    row.isKill = false

    -- Click handler
    row:SetScript("OnMouseUp", function()
        if arg1 == "LeftButton" and this.eventIndex > 0 then
            D:SelectEvent(this.eventIndex)
        end
    end)

    -- Hover highlight
    row:SetScript("OnEnter", function()
        if this.eventIndex > 0 and this.eventIndex ~= D.selectedEventIdx then
            this.selectBg:SetTexture(D.SELECT_BG[1], D.SELECT_BG[2], D.SELECT_BG[3], 0.1)
        end
    end)
    row:SetScript("OnLeave", function()
        if this.eventIndex ~= D.selectedEventIdx then
            this.selectBg:SetTexture(0, 0, 0, 0)
        end
    end)

    -- Scroll passthrough
    row:SetScript("OnMouseWheel", function()
        D:ScrollEvents(arg1)
    end)

    row:Hide()
    return row
end

---------------------------------------------------------------------------
-- Navigation bar: [<< Prev] Death X / Y [Next >>]
---------------------------------------------------------------------------

local function CreateNavBar(parent)
    local nav = CreateFrame("Frame", nil, parent)
    nav:SetHeight(D.NAV_H)
    nav:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 4, 4)
    nav:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, 4)

    local bg = nav:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(nav)
    bg:SetTexture(0.04, 0.04, 0.06, 1)

    -- Prev button
    local prevBtn = CreateFrame("Button", nil, nav)
    prevBtn:SetWidth(60)
    prevBtn:SetHeight(18)
    prevBtn:SetPoint("LEFT", nav, "LEFT", D.PADDING, 0)
    local prevTex = prevBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    prevTex:SetAllPoints(prevBtn)
    prevTex:SetText("<< Prev")
    prevTex:SetTextColor(D.CYAN[1], D.CYAN[2], D.CYAN[3])
    prevBtn:SetScript("OnEnter", function() prevTex:SetTextColor(1, 1, 1) end)
    prevBtn:SetScript("OnLeave", function() prevTex:SetTextColor(D.CYAN[1], D.CYAN[2], D.CYAN[3]) end)
    prevBtn:SetScript("OnClick", function() D:NavigatePrev() end)

    -- Next button
    local nextBtn = CreateFrame("Button", nil, nav)
    nextBtn:SetWidth(60)
    nextBtn:SetHeight(18)
    nextBtn:SetPoint("RIGHT", nav, "RIGHT", -D.PADDING, 0)
    local nextTex = nextBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nextTex:SetAllPoints(nextBtn)
    nextTex:SetText("Next >>")
    nextTex:SetTextColor(D.CYAN[1], D.CYAN[2], D.CYAN[3])
    nextBtn:SetScript("OnEnter", function() nextTex:SetTextColor(1, 1, 1) end)
    nextBtn:SetScript("OnLeave", function() nextTex:SetTextColor(D.CYAN[1], D.CYAN[2], D.CYAN[3]) end)
    nextBtn:SetScript("OnClick", function() D:NavigateNext() end)

    -- Counter
    nav.counter = nav:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nav.counter:SetPoint("CENTER", nav, "CENTER", 0, 0)
    nav.counter:SetTextColor(D.GRAY[1], D.GRAY[2], D.GRAY[3])

    return nav
end

---------------------------------------------------------------------------
-- Build the full panel
---------------------------------------------------------------------------

local function BuildPanel()
    if D.frame then return end

    D.frame = CreateMainFrame()
    D.header = CreateHeader(D.frame)
    D.unitFrame = CreateUnitFrame(D.frame, D.header)
    D.separator = CreateSeparator(D.frame, D.unitFrame)

    -- Event rows container
    D.eventContainer = CreateFrame("Frame", nil, D.frame)
    D.eventContainer:SetPoint("TOPLEFT", D.separator, "BOTTOMLEFT", 0, -2)
    D.eventContainer:SetPoint("RIGHT", D.frame, "RIGHT", -4, 0)
    D.eventContainer:SetHeight(D.VISIBLE_ROWS * D.ROW_H)

    for i = 1, D.VISIBLE_ROWS do
        local row = CreateEventRow(D.eventContainer, i)
        row:SetPoint("TOPLEFT", D.eventContainer, "TOPLEFT", 0, -((i - 1) * D.ROW_H))
        row:SetPoint("RIGHT", D.eventContainer, "RIGHT", 0, 0)
        D.eventRows[i] = row
    end

    -- Mousewheel on container and main frame
    D.eventContainer:EnableMouseWheel(true)
    D.eventContainer:SetScript("OnMouseWheel", function() D:ScrollEvents(arg1) end)
    D.frame:EnableMouseWheel(true)
    D.frame:SetScript("OnMouseWheel", function() D:ScrollEvents(arg1) end)

    D.navBar = CreateNavBar(D.frame)
    D:ApplyOpacity()
end

---------------------------------------------------------------------------
-- Apply opacity setting
---------------------------------------------------------------------------

function D:ApplyOpacity()
    if not self.frame then return end
    local alpha = P.settings.deathRecapOpacity or 0.95
    self.frame:SetAlpha(alpha)
end

---------------------------------------------------------------------------
-- Update Unit Frame: HP/resource/buffs/debuffs for selected event
---------------------------------------------------------------------------

function D:UpdateUnitFrame()
    local record = self.currentRecord
    if not record or not self.unitFrame then return end
    local events = record.events or {}
    local numEvents = table.getn(events)

    local idx = self.selectedEventIdx
    if not idx or idx < 1 or idx > numEvents then
        idx = numEvents
        self.selectedEventIdx = idx
    end

    local e = events[idx]
    if not e then return end

    -- HP bar
    local hp = e.hpAfter or 0
    local hpMax = e.hpMax or record.hpMax or 0
    if hpMax > 0 then
        local pct = hp / hpMax
        if pct > 1 then pct = 1 end
        if pct < 0 then pct = 0 end
        self.unitFrame.hpBar:SetValue(pct)
        local r, g
        if pct > 0.5 then
            r = 2 * (1 - pct)
            g = 1
        else
            r = 1
            g = 2 * pct
        end
        self.unitFrame.hpBar:SetStatusBarColor(r, g, 0.1)
        self.unitFrame.hpText:SetText(P.FormatNumber(hp) .. " / " .. P.FormatNumber(hpMax))
    else
        self.unitFrame.hpBar:SetValue(0)
        self.unitFrame.hpBar:SetStatusBarColor(0.3, 0.3, 0.3)
        self.unitFrame.hpText:SetText("HP unknown")
    end

    -- Resource bar
    local mana = e.manaAfter
    local manaMax = e.manaMax
    local pt = e.powerType or record.powerType
    if mana and manaMax and manaMax > 0 then
        local pct = mana / manaMax
        if pct > 1 then pct = 1 end
        if pct < 0 then pct = 0 end
        self.unitFrame.resBar:SetValue(pct)
        local pc = D.POWER_COLORS[pt] or D.POWER_COLORS[0]
        self.unitFrame.resBar:SetStatusBarColor(pc.r, pc.g, pc.b)
        local pname = D.POWER_NAMES[pt] or "Mana"
        self.unitFrame.resText:SetText(P.FormatNumber(mana) .. " / " .. P.FormatNumber(manaMax) .. " " .. pname)
    else
        self.unitFrame.resBar:SetValue(0)
        self.unitFrame.resBar:SetStatusBarColor(0.3, 0.3, 0.3)
        self.unitFrame.resText:SetText("")
    end

    -- Buff icons
    local buffs = e.buffs or {}
    for i = 1, D.MAX_BUFFS do
        local icon = D.buffIcons[i]
        local b = buffs[i]
        if b and b.texture then
            icon.tex:SetTexture(b.texture)
            icon.auraID = b.auraID
            icon.stackCount = b.stacks or 0
            if b.stacks and b.stacks > 1 then
                icon.stackText:SetText(b.stacks)
                icon.stackText:Show()
            else
                icon.stackText:Hide()
            end
            icon:Show()
        else
            icon:Hide()
        end
    end

    -- Debuff icons
    local debuffs = e.debuffs or {}
    for i = 1, D.MAX_DEBUFFS do
        local icon = D.debuffIcons[i]
        local db = debuffs[i]
        if db and db.texture then
            icon.tex:SetTexture(db.texture)
            icon.auraID = db.auraID
            icon.stackCount = db.stacks or 0
            icon.debuffType = db.debuffType

            -- Color border by debuff type
            local dc = D.DEBUFF_COLORS[db.debuffType]
            if dc then
                icon.border:SetTexture(dc.r, dc.g, dc.b, 0.8)
            else
                icon.border:SetTexture(0.8, 0, 0, 0.8)
            end

            if db.stacks and db.stacks > 1 then
                icon.stackText:SetText(db.stacks)
                icon.stackText:Show()
            else
                icon.stackText:Hide()
            end
            icon:Show()
        else
            icon:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Populate the panel with a death record
---------------------------------------------------------------------------

function D:DisplayRecord(record)
    if not record then return end
    self.currentRecord = record
    self.scrollOffset = 0

    BuildPanel()

    -- Player name + class
    local cc = P.GetClassColor(record.name)
    self.unitFrame.nameText:SetText(record.name)
    self.unitFrame.nameText:SetTextColor(cc.r, cc.g, cc.b)

    local classDisplay = record.class or "UNKNOWN"
    classDisplay = string.upper(string.sub(classDisplay, 1, 1)) ..
        string.lower(string.sub(classDisplay, 2))
    self.unitFrame.classLabel:SetText("(" .. classDisplay .. ")")

    -- Class icon
    local iconPath = D.CLASS_ICONS[string.upper(record.class or "")]
    if iconPath then
        self.unitFrame.classIcon:SetTexture(iconPath)
    else
        self.unitFrame.classIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- Kill info line
    local schoolColors = P.SCHOOL_COLORS or {}
    local sc = schoolColors[record.killSchool] or { r = 1, g = 0.3, b = 0.3 }
    local killHex = string.format("%02x%02x%02x", sc.r * 255, sc.g * 255, sc.b * 255)
    local killText = "Killed by: |cff" .. killHex .. record.killSpell .. "|r (" .. record.killedBy .. ")"
    if record.overkill and record.overkill > 0 then
        killText = killText .. "  |cffcc4444Overkill: " .. P.FormatNumber(record.overkill) .. "|r"
    end
    self.unitFrame.killInfo:SetText(killText)

    -- Subinfo
    local parts = {}
    if record.timeFmt then
        table.insert(parts, record.timeFmt)
    end
    table.insert(parts, P.FormatNumber(record.totalDmg) .. " dmg in " ..
        string.format("%.1fs", record.duration))
    local subText = ""
    for i = 1, table.getn(parts) do
        if i > 1 then subText = subText .. "  |cff444444||  " end
        subText = subText .. "|cff888888" .. parts[i] .. "|r"
    end
    self.unitFrame.subInfo:SetText(subText)

    -- Default selection: killing blow (last damage event)
    local events = record.events or {}
    local numEvents = table.getn(events)
    self.selectedEventIdx = numEvents  -- fallback to last
    for i = numEvents, 1, -1 do
        if events[i].etype == "DAMAGE" and events[i].amount > 0 then
            self.selectedEventIdx = i
            break
        end
    end

    -- Auto-scroll to show selected event
    local maxScroll = numEvents - D.VISIBLE_ROWS
    if maxScroll < 0 then maxScroll = 0 end
    self.scrollOffset = maxScroll

    -- Update all sections
    self:UpdateUnitFrame()
    self:UpdateEventRows()
    self:UpdateNav()

    self.frame:Show()
end

---------------------------------------------------------------------------
-- Update event rows (with scroll offset + selection)
---------------------------------------------------------------------------

function D:UpdateEventRows()
    local record = self.currentRecord
    if not record then return end

    local events = record.events or {}
    local numEvents = table.getn(events)
    local deathTime = events[numEvents] and events[numEvents].time or record.time

    -- Find killing blow index
    local killIdx = -1
    for i = numEvents, 1, -1 do
        if events[i].etype == "DAMAGE" and events[i].amount > 0 then
            killIdx = i
            break
        end
    end

    -- Clamp scroll offset
    local maxScroll = numEvents - D.VISIBLE_ROWS
    if maxScroll < 0 then maxScroll = 0 end
    if self.scrollOffset > maxScroll then self.scrollOffset = maxScroll end
    if self.scrollOffset < 0 then self.scrollOffset = 0 end

    local schoolColors = P.SCHOOL_COLORS or {}
    local DL = P.deathLog

    for i = 1, D.VISIBLE_ROWS do
        local row = self.eventRows[i]
        local eIdx = i + self.scrollOffset
        if eIdx <= numEvents then
            local e = events[eIdx]

            -- Time offset relative to death
            local offset = e.time - deathTime
            if offset >= 0 then
                row.timeText:SetText("0.0s")
            else
                row.timeText:SetText(string.format("%.1fs", offset))
            end

            -- Spell icon
            local spellTex = DL and DL.GetSpellIcon(e.spellID) or nil
            if spellTex then
                row.spellIcon:SetTexture(spellTex)
                row.spellIcon:SetTexCoord(0, 1, 0, 1)
            else
                local ssc = schoolColors[e.school] or { r = 0.8, g = 0.8, b = 0.8 }
                if e.etype == "HEAL" then
                    row.spellIcon:SetTexture(D.HEAL_COLOR[1], D.HEAL_COLOR[2], D.HEAL_COLOR[3], 1)
                elseif e.etype == "MISS" then
                    row.spellIcon:SetTexture(D.MISS_COLOR[1], D.MISS_COLOR[2], D.MISS_COLOR[3], 1)
                else
                    row.spellIcon:SetTexture(ssc.r, ssc.g, ssc.b, 1)
                end
            end

            -- Spell name + source
            local spellSource = e.spell
            if e.source and e.source ~= "?" then
                spellSource = spellSource .. " (" .. e.source .. ")"
            end
            row.spellText:SetText(spellSource)

            -- Amount + colors
            if e.etype == "HEAL" then
                row.amountText:SetText("+" .. P.FormatNumber(e.amount))
                row.amountText:SetTextColor(D.HEAL_COLOR[1], D.HEAL_COLOR[2], D.HEAL_COLOR[3])
                row.spellText:SetTextColor(D.HEAL_COLOR[1], D.HEAL_COLOR[2], D.HEAL_COLOR[3])
            elseif e.etype == "MISS" then
                row.amountText:SetText("")
                row.amountText:SetTextColor(D.MISS_COLOR[1], D.MISS_COLOR[2], D.MISS_COLOR[3])
                row.spellText:SetTextColor(D.MISS_COLOR[1], D.MISS_COLOR[2], D.MISS_COLOR[3])
            else
                row.amountText:SetText(P.FormatNumber(e.amount))
                row.amountText:SetTextColor(1, 1, 1)
                row.spellText:SetTextColor(1, 1, 1)
            end

            -- Flag text
            if e.etype == "MISS" then
                row.flagText:SetText(e.missType or "MISS")
                row.flagText:SetTextColor(D.MISS_COLOR[1], D.MISS_COLOR[2], D.MISS_COLOR[3])
            elseif e.crit then
                row.flagText:SetText("CRIT")
                row.flagText:SetTextColor(1, 0.5, 0)
            else
                row.flagText:SetText("")
            end

            -- Killing blow highlight
            if eIdx == killIdx then
                row.killBg:SetTexture(D.KILL_BG[1], D.KILL_BG[2], D.KILL_BG[3], D.KILL_BG[4])
                row.amountText:SetTextColor(1, 0.2, 0.2)
                row.isKill = true
            else
                row.killBg:SetTexture(0, 0, 0, 0)
                row.isKill = false
            end

            -- Selection highlight
            if eIdx == self.selectedEventIdx then
                row.selectBg:SetTexture(D.SELECT_BG[1], D.SELECT_BG[2], D.SELECT_BG[3], D.SELECT_BG[4])
            else
                row.selectBg:SetTexture(0, 0, 0, 0)
            end

            row.eventIndex = eIdx
            row:Show()
        else
            row.eventIndex = 0
            row:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Select an event (click handler)
---------------------------------------------------------------------------

function D:SelectEvent(eventIdx)
    self.selectedEventIdx = eventIdx
    self:UpdateUnitFrame()
    self:UpdateEventRows()
end

---------------------------------------------------------------------------
-- Scroll events
---------------------------------------------------------------------------

function D:ScrollEvents(direction)
    if not self.currentRecord then return end
    self.scrollOffset = self.scrollOffset - direction
    self:UpdateEventRows()
end

---------------------------------------------------------------------------
-- Navigation: prev/next death
---------------------------------------------------------------------------

function D:NavigatePrev()
    if self.currentIndex < table.getn(self.currentList) then
        self.currentIndex = self.currentIndex + 1
        self:DisplayRecord(self.currentList[self.currentIndex])
    end
end

function D:NavigateNext()
    if self.currentIndex > 1 then
        self.currentIndex = self.currentIndex - 1
        self:DisplayRecord(self.currentList[self.currentIndex])
    end
end

function D:UpdateNav()
    if not self.navBar then return end
    local total = table.getn(self.currentList)
    if total == 0 then
        self.navBar.counter:SetText("No deaths recorded")
        return
    end
    self.navBar.counter:SetText("Death " .. self.currentIndex .. " / " .. total)
end

---------------------------------------------------------------------------
-- Public API: Show death recap
---------------------------------------------------------------------------

function P.ShowDeathRecap()
    local DL = P.deathLog
    if not DL then return end

    local record = DL:GetLatestDeath()
    if not record then
        P.Print("No deaths recorded.")
        return
    end

    local segment = "current"
    local deaths = DL:GetDeaths(segment)
    if table.getn(deaths) == 0 then
        deaths = DL:GetDeaths("overall")
        segment = "overall"
    end

    D.currentList = deaths
    D.currentIndex = 1
    D.playerFilter = nil
    D.segmentFilter = segment
    D:DisplayRecord(deaths[1])
end

function P.ShowDeathRecapForPlayer(name, segment)
    local DL = P.deathLog
    if not DL then return end

    local seg = segment or "current"
    local deaths = DL:GetDeathsForPlayer(name, seg)
    if table.getn(deaths) == 0 then
        deaths = DL:GetDeathsForPlayer(name, "overall")
        seg = "overall"
    end
    if table.getn(deaths) == 0 then
        P.Print("No deaths recorded for " .. (name or "?") .. ".")
        return
    end

    D.currentList = deaths
    D.currentIndex = 1
    D.playerFilter = name
    D.segmentFilter = seg
    D:DisplayRecord(deaths[1])
end

function P.ShowDeathRecapForRecord(record)
    if not record then return end

    local DL = P.deathLog
    if DL then
        local deaths = DL:GetDeathsForPlayer(record.name, "current")
        if table.getn(deaths) == 0 then
            deaths = DL:GetDeathsForPlayer(record.name, "overall")
        end
        if table.getn(deaths) > 0 then
            D.currentList = deaths
            D.currentIndex = 1
            D.playerFilter = record.name
        else
            D.currentList = { record }
            D.currentIndex = 1
            D.playerFilter = record.name
        end
    else
        D.currentList = { record }
        D.currentIndex = 1
    end

    D:DisplayRecord(record)
end
