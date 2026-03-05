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
D.MAX_BUFF_ICONS = 32   -- matches TurtleWoW buff limit, wraps into 2 rows
D.MAX_DEBUFF_ICONS = 32 -- display limit for debuffs (TW allows 64, overflow for rest)
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
D.BUFF_COLOR = { 1, 0.82, 0 }  -- gold for self-casts/buffs
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

D.SCHOOL_NAMES = {
    [0] = "Physical", [1] = "Holy", [2] = "Fire",
    [3] = "Nature", [4] = "Frost", [5] = "Shadow", [6] = "Arcane",
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

    D.AURA_PER_ROW = math.floor((D.WIDTH - 2 * D.PADDING) / (D.AURA_SIZE + D.AURA_GAP))

    for i = 1, D.MAX_BUFF_ICONS do
        local icon = CreateFrame("Frame", nil, uf.buffRow)
        icon:SetWidth(D.AURA_SIZE)
        icon:SetHeight(D.AURA_SIZE)
        local col = math.mod(i - 1, D.AURA_PER_ROW)
        local row = math.floor((i - 1) / D.AURA_PER_ROW)
        icon:SetPoint("TOPLEFT", uf.buffRow, "TOPLEFT", col * (D.AURA_SIZE + D.AURA_GAP), -row * (D.AURA_SIZE + D.AURA_GAP))

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
            GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
            D:AddSpellInfoLines(this.auraID, "Unknown Buff")
            if this.stackCount and this.stackCount > 1 then
                GameTooltip:AddLine(this.stackCount .. " stacks", 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        icon:Hide()
        D.buffIcons[i] = icon
    end

    -- Buff overflow indicator
    D.buffOverflow = CreateFrame("Frame", nil, uf.buffRow)
    D.buffOverflow:SetWidth(30)
    D.buffOverflow:SetHeight(D.AURA_SIZE)
    D.buffOverflow:EnableMouse(true)
    D.buffOverflow.text = D.buffOverflow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    D.buffOverflow.text:SetPoint("LEFT", D.buffOverflow, "LEFT", 2, 0)
    D.buffOverflow.text:SetTextColor(0.7, 0.7, 0.7)
    D.buffOverflow.text:SetShadowColor(0, 0, 0, 1)
    D.buffOverflow.text:SetShadowOffset(1, -1)
    D.buffOverflow.hiddenBuffs = {}
    D.buffOverflow:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
        GameTooltip:AddLine("Hidden Buffs", 1, 0.82, 0)
        local hidden = D.buffOverflow.hiddenBuffs
        for i = 1, table.getn(hidden) do
            local b = hidden[i]
            local name = "Unknown"
            if b.auraID and SpellInfo then
                local n = SpellInfo(b.auraID)
                if n then name = n end
            end
            local stackStr = ""
            if b.stacks and b.stacks > 1 then stackStr = " (" .. b.stacks .. ")" end
            GameTooltip:AddLine(name .. stackStr, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    D.buffOverflow:SetScript("OnLeave", function() GameTooltip:Hide() end)
    D.buffOverflow:Hide()

    -- Debuff row
    uf.debuffRow = CreateFrame("Frame", nil, uf)
    uf.debuffRow:SetHeight(D.AURA_SIZE)
    uf.debuffRow:SetPoint("TOPLEFT", uf.buffRow, "BOTTOMLEFT", 0, -D.AURA_GAP)
    uf.debuffRow:SetPoint("RIGHT", uf, "RIGHT", -D.PADDING, 0)

    for i = 1, D.MAX_DEBUFF_ICONS do
        local icon = CreateFrame("Frame", nil, uf.debuffRow)
        icon:SetWidth(D.AURA_SIZE)
        icon:SetHeight(D.AURA_SIZE)
        local col = math.mod(i - 1, D.AURA_PER_ROW)
        local row = math.floor((i - 1) / D.AURA_PER_ROW)
        icon:SetPoint("TOPLEFT", uf.debuffRow, "TOPLEFT", col * (D.AURA_SIZE + D.AURA_GAP), -row * (D.AURA_SIZE + D.AURA_GAP))

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
            GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
            D:AddSpellInfoLines(this.auraID, "Unknown Debuff")
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

    -- Debuff overflow indicator
    D.debuffOverflow = CreateFrame("Frame", nil, uf.debuffRow)
    D.debuffOverflow:SetWidth(30)
    D.debuffOverflow:SetHeight(D.AURA_SIZE)
    D.debuffOverflow:EnableMouse(true)
    D.debuffOverflow.text = D.debuffOverflow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    D.debuffOverflow.text:SetPoint("LEFT", D.debuffOverflow, "LEFT", 2, 0)
    D.debuffOverflow.text:SetTextColor(0.7, 0.7, 0.7)
    D.debuffOverflow.text:SetShadowColor(0, 0, 0, 1)
    D.debuffOverflow.text:SetShadowOffset(1, -1)
    D.debuffOverflow.hiddenDebuffs = {}
    D.debuffOverflow:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
        GameTooltip:AddLine("Hidden Debuffs", 1, 0, 0)
        local hidden = D.debuffOverflow.hiddenDebuffs
        for i = 1, table.getn(hidden) do
            local db = hidden[i]
            local name = "Unknown"
            if db.auraID and SpellInfo then
                local n = SpellInfo(db.auraID)
                if n then name = n end
            end
            local stackStr = ""
            if db.stacks and db.stacks > 1 then stackStr = " (" .. db.stacks .. ")" end
            local suffix = ""
            if db.debuffType then suffix = " [" .. db.debuffType .. "]" end
            GameTooltip:AddLine(name .. stackStr .. suffix, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    D.debuffOverflow:SetScript("OnLeave", function() GameTooltip:Hide() end)
    D.debuffOverflow:Hide()

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
    row.spellIcon:SetPoint("LEFT", row.timeText, "RIGHT", 4, 0)

    -- Raid target icon (14x14, fixed column between spell icon and spell text)
    row.raidIcon = row:CreateTexture(nil, "OVERLAY")
    row.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    row.raidIcon:SetWidth(14)
    row.raidIcon:SetHeight(14)
    row.raidIcon:SetPoint("LEFT", row.spellIcon, "RIGHT", 3, 0)
    row.raidIcon:Hide()

    -- Spell name + source (fixed anchor: always 21px past spell icon = 3+14+4 for marker column)
    row.spellText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.spellText:SetPoint("LEFT", row.spellIcon, "RIGHT", 21, 0)
    row.spellText:SetJustifyH("LEFT")
    row.spellText:SetTextColor(1, 1, 1)

    -- Mini HP/Resource bars (rightmost column, 40x6 each, stacked)
    local BAR_W, BAR_H_MINI = 40, 6
    row.hpBar = CreateFrame("StatusBar", nil, row)
    row.hpBar:SetWidth(BAR_W)
    row.hpBar:SetHeight(BAR_H_MINI)
    row.hpBar:SetPoint("TOPRIGHT", row, "TOPRIGHT", -D.PADDING, -2)
    row.hpBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.hpBar:SetStatusBarColor(0.1, 0.9, 0.1)
    row.hpBar:SetMinMaxValues(0, 1)
    row.hpBarBg = row.hpBar:CreateTexture(nil, "BACKGROUND")
    row.hpBarBg:SetAllPoints(row.hpBar)
    row.hpBarBg:SetTexture(0.15, 0.15, 0.15, 0.8)

    row.mpBar = CreateFrame("StatusBar", nil, row)
    row.mpBar:SetWidth(BAR_W)
    row.mpBar:SetHeight(BAR_H_MINI)
    row.mpBar:SetPoint("TOP", row.hpBar, "BOTTOM", 0, -1)
    row.mpBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.mpBar:SetStatusBarColor(0.0, 0.0, 1.0)
    row.mpBar:SetMinMaxValues(0, 1)
    row.mpBarBg = row.mpBar:CreateTexture(nil, "BACKGROUND")
    row.mpBarBg:SetAllPoints(row.mpBar)
    row.mpBarBg:SetTexture(0.15, 0.15, 0.15, 0.8)

    -- Tooltip hover frame over both bars
    row.barHover = CreateFrame("Frame", nil, row)
    row.barHover:SetPoint("TOPLEFT", row.hpBar, "TOPLEFT", 0, 0)
    row.barHover:SetPoint("BOTTOMRIGHT", row.mpBar, "BOTTOMRIGHT", 0, 0)
    row.barHover:EnableMouse(true)
    row.barHover:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        local hp = this:GetParent()._barHP or 0
        local hpM = this:GetParent()._barHPMax or 1
        local mp = this:GetParent()._barMP or 0
        local mpM = this:GetParent()._barMPMax or 1
        local pn = this:GetParent()._barPowerName or "Mana"
        local pct = (hpM > 0) and math.floor(hp / hpM * 100) or 0
        GameTooltip:AddLine("HP: " .. P.FormatNumber(hp) .. " / " .. P.FormatNumber(hpM) .. " (" .. pct .. "%)", 0.1, 0.9, 0.1)
        if mpM > 0 then
            local mpPct = math.floor(mp / mpM * 100)
            GameTooltip:AddLine(pn .. ": " .. P.FormatNumber(mp) .. " / " .. P.FormatNumber(mpM) .. " (" .. mpPct .. "%)", 0.6, 0.6, 1)
        end
        GameTooltip:Show()
    end)
    row.barHover:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Crit/miss label (left of bars)
    row.flagText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.flagText:SetPoint("RIGHT", row.hpBar, "LEFT", -4, 0)
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

    -- Hover highlight + tooltip
    row.eventData = nil
    row:SetScript("OnEnter", function()
        if this.eventIndex > 0 then
            if this.eventIndex ~= D.selectedEventIdx then
                this.selectBg:SetTexture(D.SELECT_BG[1], D.SELECT_BG[2], D.SELECT_BG[3], 0.1)
            end
            if this.eventData then
                D:ShowEventTooltip(this, this.eventData)
            end
        end
    end)
    row:SetScript("OnLeave", function()
        if this.eventIndex ~= D.selectedEventIdx then
            this.selectBg:SetTexture(0, 0, 0, 0)
        end
        GameTooltip:Hide()
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
    local buffCount = table.getn(buffs)
    local displayBuffs = buffCount
    if displayBuffs > D.MAX_BUFF_ICONS then displayBuffs = D.MAX_BUFF_ICONS end
    local buffVisRows = (displayBuffs > 0) and (math.floor((displayBuffs - 1) / D.AURA_PER_ROW) + 1) or 1
    self.unitFrame.buffRow:SetHeight(buffVisRows * D.AURA_SIZE + math.max(0, buffVisRows - 1) * D.AURA_GAP)
    for i = 1, D.MAX_BUFF_ICONS do
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

    -- Buff overflow
    if buffCount > D.MAX_BUFF_ICONS then
        local overflow = buffCount - D.MAX_BUFF_ICONS
        D.buffOverflow.text:SetText("+" .. overflow)
        -- Position after last visible icon on the last row
        local lastCol = math.mod(displayBuffs, D.AURA_PER_ROW)
        local lastRow = math.floor((displayBuffs - 1) / D.AURA_PER_ROW)
        D.buffOverflow:ClearAllPoints()
        D.buffOverflow:SetPoint("TOPLEFT", uf.buffRow, "TOPLEFT", lastCol * (D.AURA_SIZE + D.AURA_GAP), -lastRow * (D.AURA_SIZE + D.AURA_GAP))
        local hidden = {}
        for i = D.MAX_BUFF_ICONS + 1, buffCount do
            table.insert(hidden, buffs[i])
        end
        D.buffOverflow.hiddenBuffs = hidden
        D.buffOverflow:Show()
    else
        D.buffOverflow:Hide()
    end

    -- Debuff icons
    local debuffs = e.debuffs or {}
    local debuffCount = table.getn(debuffs)
    local displayDebuffs = debuffCount
    if displayDebuffs > D.MAX_DEBUFF_ICONS then displayDebuffs = D.MAX_DEBUFF_ICONS end
    local debuffVisRows = (displayDebuffs > 0) and (math.floor((displayDebuffs - 1) / D.AURA_PER_ROW) + 1) or 1
    self.unitFrame.debuffRow:SetHeight(debuffVisRows * D.AURA_SIZE + math.max(0, debuffVisRows - 1) * D.AURA_GAP)
    for i = 1, D.MAX_DEBUFF_ICONS do
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

    -- Debuff overflow
    if debuffCount > D.MAX_DEBUFF_ICONS then
        local overflow = debuffCount - D.MAX_DEBUFF_ICONS
        D.debuffOverflow.text:SetText("+" .. overflow)
        local lastCol = math.mod(displayDebuffs, D.AURA_PER_ROW)
        local lastRow = math.floor((displayDebuffs - 1) / D.AURA_PER_ROW)
        D.debuffOverflow:ClearAllPoints()
        D.debuffOverflow:SetPoint("TOPLEFT", uf.debuffRow, "TOPLEFT", lastCol * (D.AURA_SIZE + D.AURA_GAP), -lastRow * (D.AURA_SIZE + D.AURA_GAP))
        local hidden = {}
        for i = D.MAX_DEBUFF_ICONS + 1, debuffCount do
            table.insert(hidden, debuffs[i])
        end
        D.debuffOverflow.hiddenDebuffs = hidden
        D.debuffOverflow:Show()
    else
        D.debuffOverflow:Hide()
    end
end

---------------------------------------------------------------------------
-- Shared: add native-style spell info lines to GameTooltip
-- Used by event row tooltips AND buff/debuff icon tooltips
---------------------------------------------------------------------------

function D:AddSpellInfoLines(spellID, fallbackName)
    local spellName = fallbackName or "Unknown"
    local spellRank, spellRange, spellManaCost, spellDesc = nil, nil, nil, nil

    if spellID and spellID > 0 then
        -- SpellInfo (SuperWoW): name, rank, texture, minRange, maxRange
        if SpellInfo then
            local siName, siRank, siTex, siMinR, siMaxR = SpellInfo(spellID)
            if siName then spellName = siName end
            if siRank and siRank ~= "" then spellRank = siRank end
            if siMaxR and siMaxR > 0 then
                spellRange = siMaxR .. " yd range"
            end
        end
        -- GetSpellRec (Nampower): full DBC record for mana cost, description, etc.
        if GetSpellRec then
            local ok, rec = pcall(GetSpellRec, spellID)
            if ok and rec then
                if rec.manaCost and rec.manaCost > 0 then
                    local ptName = "Mana"
                    if rec.powerType == 1 then ptName = "Rage"
                    elseif rec.powerType == 3 then ptName = "Energy"
                    end
                    spellManaCost = rec.manaCost .. " " .. ptName
                end
                if rec.name and rec.name ~= "" then spellName = rec.name end
                if rec.rank and rec.rank ~= "" then spellRank = rec.rank end
                if rec.description and rec.description ~= "" then
                    spellDesc = rec.description
                    -- Resolve $s1/$s2/$s3 placeholders from effectBasePoints table
                    local ebp = rec.effectBasePoints
                    local eds = rec.effectDieSides
                    if ebp then
                        for i = 1, 3 do
                            local base = ebp[i]
                            if base then
                                local minVal = base + 1  -- DBC stores base-1
                                if minVal < 0 then minVal = math.abs(minVal) end
                                local dieVal = eds and eds[i] or 0
                                if dieVal and dieVal > 0 then
                                    local maxVal = base + dieVal
                                    if maxVal < 0 then maxVal = math.abs(maxVal) end
                                    spellDesc = string.gsub(spellDesc, "%$s" .. i, minVal .. " to " .. maxVal)
                                else
                                    spellDesc = string.gsub(spellDesc, "%$s" .. i, tostring(minVal))
                                end
                            end
                        end
                    end
                    -- Resolve $d (duration)
                    if string.find(spellDesc, "%$d") and GetSpellDuration then
                        local durMs = GetSpellDuration(spellID)
                        if durMs and durMs > 0 then
                            local durSec = math.floor(durMs / 1000)
                            if durSec >= 60 then
                                local mins = math.floor(durSec / 60)
                                spellDesc = string.gsub(spellDesc, "%$d", mins .. " min")
                            else
                                spellDesc = string.gsub(spellDesc, "%$d", durSec .. " sec")
                            end
                        end
                    end
                    -- Resolve $o1 (total periodic = base * ticks)
                    if string.find(spellDesc, "%$o") and ebp then
                        local amp = rec.effectAmplitude
                        for i = 1, 3 do
                            local val = ebp[i]
                            if val then
                                val = val + 1
                                if val < 0 then val = math.abs(val) end
                                -- total = base * (duration / amplitude) roughly
                                local totalVal = val
                                if amp and amp[i] and amp[i] > 0 and GetSpellDuration then
                                    local durMs = GetSpellDuration(spellID)
                                    if durMs and durMs > 0 then
                                        totalVal = math.floor(val * (durMs / amp[i]))
                                    end
                                end
                                spellDesc = string.gsub(spellDesc, "%$o" .. i, tostring(totalVal))
                            end
                        end
                    end
                    -- Resolve $t1 (tick interval in seconds)
                    if string.find(spellDesc, "%$t") then
                        local amp = rec.effectAmplitude
                        if amp then
                            for i = 1, 3 do
                                if amp[i] and amp[i] > 0 then
                                    local tickSec = math.floor(amp[i] / 1000)
                                    spellDesc = string.gsub(spellDesc, "%$t" .. i, tostring(tickSec))
                                end
                            end
                        end
                    end
                    -- Strip remaining unresolved placeholders
                    spellDesc = string.gsub(spellDesc, "%$%a[%d]*", "")
                    spellDesc = string.gsub(spellDesc, "  +", " ")
                    -- Skip if still has $ or too short to be useful
                    if string.find(spellDesc, "%$") or string.len(spellDesc) < 5 then
                        spellDesc = nil
                    end
                end
            end
        end
    end

    GameTooltip:AddLine(spellName, 1, 1, 1)
    if spellRank then GameTooltip:AddLine(spellRank, 0.5, 0.5, 0.5) end
    if spellManaCost then GameTooltip:AddLine(spellManaCost, 0.6, 0.8, 1.0) end
    if spellRange then GameTooltip:AddLine(spellRange, 0.6, 0.8, 1.0) end
    if spellDesc then GameTooltip:AddLine(spellDesc, 1.0, 0.82, 0, 1) end
end

---------------------------------------------------------------------------
-- Spell tooltip on event row hover
---------------------------------------------------------------------------

function D:ShowEventTooltip(frame, e)
    GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")

    D:AddSpellInfoLines(e.spellID, e.spell)

    -- Separator before death recap info
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("-- Death Recap --", D.CYAN[1], D.CYAN[2], D.CYAN[3])

    -- Source + raid target
    if e.source and e.source ~= "?" then
        local srcLine = e.source
        if e.raidTarget and e.raidTarget >= 1 and e.raidTarget <= 8 then
            local rtNames = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
            srcLine = srcLine .. " {" .. rtNames[e.raidTarget] .. "}"
        end
        GameTooltip:AddLine(srcLine, 0.7, 0.7, 0.7)
    end

    -- Amount + school
    local schoolColors = P.SCHOOL_COLORS or {}
    local sc = schoolColors[e.school] or { r = 0.8, g = 0.8, b = 0.8 }
    local schoolName = D.SCHOOL_NAMES[e.school] or "Physical"
    if e.etype == "DAMAGE" then
        local text = P.FormatNumber(e.amount) .. " " .. schoolName .. " damage"
        if e.crit then text = text .. " (Critical)" end
        GameTooltip:AddLine(text, sc.r, sc.g, sc.b)
        if e.overkill and e.overkill > 0 then
            GameTooltip:AddLine("Overkill: " .. P.FormatNumber(e.overkill), 0.8, 0.3, 0.3)
        end
    elseif e.etype == "HEAL" then
        local text = "+" .. P.FormatNumber(e.amount) .. " " .. schoolName .. " healing"
        if e.crit then text = text .. " (Critical)" end
        GameTooltip:AddLine(text, 0.2, 1, 0.2)
    elseif e.etype == "MISS" then
        GameTooltip:AddLine(e.missType or "MISS", 0.7, 0.7, 0.7)
    elseif e.etype == "BUFF" then
        GameTooltip:AddLine("Buff gained", D.BUFF_COLOR[1], D.BUFF_COLOR[2], D.BUFF_COLOR[3])
    end

    -- HP status
    if e.hpAfter and e.hpMax and e.hpMax > 0 then
        local pct = math.floor(e.hpAfter / e.hpMax * 100)
        GameTooltip:AddLine("HP: " .. P.FormatNumber(e.hpAfter) .. " / " .. P.FormatNumber(e.hpMax) .. " (" .. pct .. "%)", 0.6, 0.6, 0.6)
    end

    GameTooltip:Show()
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

            -- Store event data for tooltip
            row.eventData = e

            -- Spell icon: try cached spellIcon, then SpellInfo lookup, then color fallback
            local spellTex = e.spellIcon or (DL and DL.GetSpellIcon(e.spellID) or nil)
            if spellTex then
                row.spellIcon:SetTexture(spellTex)
                row.spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else
                local ssc = schoolColors[e.school] or { r = 0.8, g = 0.8, b = 0.8 }
                if e.etype == "HEAL" then
                    row.spellIcon:SetTexture(D.HEAL_COLOR[1], D.HEAL_COLOR[2], D.HEAL_COLOR[3], 1)
                elseif e.etype == "MISS" then
                    row.spellIcon:SetTexture(D.MISS_COLOR[1], D.MISS_COLOR[2], D.MISS_COLOR[3], 1)
                elseif e.etype == "BUFF" then
                    row.spellIcon:SetTexture(D.BUFF_COLOR[1], D.BUFF_COLOR[2], D.BUFF_COLOR[3], 1)
                else
                    row.spellIcon:SetTexture(ssc.r, ssc.g, ssc.b, 1)
                end
                row.spellIcon:SetTexCoord(0, 1, 0, 1)
            end

            -- Raid target icon (fixed column, use WoW API for atlas texture)
            if e.raidTarget and e.raidTarget >= 1 and e.raidTarget <= 8 then
                SetRaidTargetIconTexture(row.raidIcon, e.raidTarget)
                row.raidIcon:Show()
            else
                row.raidIcon:Hide()
            end

            -- Spell name + source
            local spellSource = e.spell
            if e.etype ~= "BUFF" and e.source and e.source ~= "?" then
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
            elseif e.etype == "BUFF" then
                row.amountText:SetText("")
                row.amountText:SetTextColor(D.BUFF_COLOR[1], D.BUFF_COLOR[2], D.BUFF_COLOR[3])
                row.spellText:SetTextColor(D.BUFF_COLOR[1], D.BUFF_COLOR[2], D.BUFF_COLOR[3])
            else
                row.amountText:SetText(P.FormatNumber(e.amount))
                row.amountText:SetTextColor(1, 1, 1)
                row.spellText:SetTextColor(1, 1, 1)
            end

            -- Flag text
            if e.etype == "MISS" then
                row.flagText:SetText(e.missType or "MISS")
                row.flagText:SetTextColor(D.MISS_COLOR[1], D.MISS_COLOR[2], D.MISS_COLOR[3])
            elseif e.etype == "BUFF" then
                row.flagText:SetText("BUFF")
                row.flagText:SetTextColor(D.BUFF_COLOR[1], D.BUFF_COLOR[2], D.BUFF_COLOR[3])
            elseif e.crit then
                row.flagText:SetText("CRIT")
                row.flagText:SetTextColor(1, 0.5, 0)
            else
                row.flagText:SetText("")
            end

            -- Mini HP/Resource bars
            local hpA = e.hpAfter or 0
            local hpM = e.hpMax or 1
            if hpM > 0 then
                row.hpBar:SetMinMaxValues(0, hpM)
                row.hpBar:SetValue(hpA)
                -- Color: green→yellow→red based on %
                local pct = hpA / hpM
                if pct > 0.5 then
                    row.hpBar:SetStatusBarColor(0.1, 0.9, 0.1)
                elseif pct > 0.25 then
                    row.hpBar:SetStatusBarColor(0.9, 0.9, 0.1)
                else
                    row.hpBar:SetStatusBarColor(0.9, 0.1, 0.1)
                end
            else
                row.hpBar:SetMinMaxValues(0, 1)
                row.hpBar:SetValue(0)
            end

            local mpA = e.manaAfter or 0
            local mpM = e.manaMax or 0
            local pt = e.powerType or 0
            if mpM > 0 then
                row.mpBar:SetMinMaxValues(0, mpM)
                row.mpBar:SetValue(mpA)
                local pc = D.POWER_COLORS[pt] or D.POWER_COLORS[0]
                row.mpBar:SetStatusBarColor(pc.r, pc.g, pc.b)
                row.mpBar:Show()
            else
                row.mpBar:Hide()
            end

            -- Store values for tooltip
            row._barHP = hpA
            row._barHPMax = hpM
            row._barMP = mpA
            row._barMPMax = mpM
            row._barPowerName = D.POWER_NAMES[pt] or "Mana"

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
            row.eventData = nil
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
