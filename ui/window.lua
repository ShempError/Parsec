-- Parsec: Window UI
-- Configurable-view windows with per-window view/segment cycling
-- Title bar buttons: Settings, Reset, Announce, View cycle, Segment toggle

local P = Parsec
if not P then return end

table.insert(P._loadedFiles, "window")

P.windows = {}

local MAX_BARS = 20
local UPDATE_INTERVAL = 0.5

---------------------------------------------------------------------------
-- Single shared update timer (instead of per-window OnUpdate)
-- Reduces frame count from N*fps to 1*fps for timer checks
---------------------------------------------------------------------------
local windowUpdateTimer = 0
local windowTimerFrame = CreateFrame("Frame", "ParsecWindowTimer")
windowTimerFrame:SetScript("OnUpdate", function()
    windowUpdateTimer = windowUpdateTimer + arg1
    if windowUpdateTimer >= UPDATE_INTERVAL then
        windowUpdateTimer = 0
        for i = 1, table.getn(P.windows) do
            local w = P.windows[i]
            if w:IsVisible() then
                P.UpdateParsecWindow(w)
            end
        end
    end
end)

-- View cycle order
local VIEW_CYCLE = { "damage", "healing", "effheal", "dps", "hps", "deaths" }
local VIEW_LABELS = {
    damage  = "Damage",
    healing = "Healing",
    effheal = "Eff. Healing",
    dps     = "DPS",
    hps     = "HPS",
    deaths  = "Deaths",
}
local SEGMENT_LABELS = {
    current = "Current",
    overall = "Overall",
}

-- Map each view to the module that must be enabled
local VIEW_MODULE = {
    damage  = "damage",
    dps     = "damage",
    healing = "healing",
    effheal = "healing",
    hps     = "healing",
    deaths  = "deaths",
}

-- Return only views whose module is enabled
local function GetEnabledViews()
    local mods = P.settings and P.settings.modules
    local out = {}
    for i = 1, table.getn(VIEW_CYCLE) do
        local v = VIEW_CYCLE[i]
        local mod = VIEW_MODULE[v]
        if not mods or mods[mod] ~= false then
            table.insert(out, v)
        end
    end
    return out
end

local WINDOW_DEFS = {
    { viewType = "damage",  segment = "current", title = "Damage" },
}

---------------------------------------------------------------------------
-- Bar Creation (settings-driven)
---------------------------------------------------------------------------

local function CreateBar(parent)
    local s = P.settings or {}
    local barH = s.barHeight or 14
    local texIdx = s.barTexture or 1
    local texPath = P.BAR_TEXTURES and P.BAR_TEXTURES[texIdx] or "Interface\\TargetingFrame\\UI-StatusBar"

    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(texPath)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetHeight(barH)
    bar:EnableMouse(true)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetTexture(texPath)
    bar.bg:SetAllPoints(bar)
    bar.bg:SetVertexColor(0.1, 0.1, 0.1, 0.6)

    local shadowA = (s.fontShadow ~= false) and 1 or 0
    local shadowOff = (s.fontShadow ~= false) and 1 or 0
    local outlineFlag = s.fontOutline and "OUTLINE" or ""

    bar.rank = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.rank:SetPoint("LEFT", bar, "LEFT", 2, 0)
    bar.rank:SetWidth(14)
    bar.rank:SetJustifyH("RIGHT")
    bar.rank:SetTextColor(0.6, 0.6, 0.6)
    bar.rank:SetShadowColor(0, 0, 0, shadowA)
    bar.rank:SetShadowOffset(shadowOff, -shadowOff)

    bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.name:SetPoint("LEFT", bar.rank, "RIGHT", 2, 0)
    bar.name:SetJustifyH("LEFT")
    bar.name:SetShadowColor(0, 0, 0, shadowA)
    bar.name:SetShadowOffset(shadowOff, -shadowOff)

    bar.value = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.value:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    bar.value:SetJustifyH("RIGHT")
    bar.value:SetTextColor(1, 0.82, 0)
    bar.value:SetShadowColor(0, 0, 0, shadowA)
    bar.value:SetShadowOffset(shadowOff, -shadowOff)

    -- Apply font outline if enabled
    if outlineFlag ~= "" then
        local fontStrings = { bar.rank, bar.name, bar.value }
        for k = 1, 3 do
            local fontPath, fontSize = fontStrings[k]:GetFont()
            if fontPath then
                fontStrings[k]:SetFont(fontPath, fontSize, outlineFlag)
            end
        end
    end

    bar.name:SetPoint("RIGHT", bar.value, "LEFT", -4, 0)

    bar:SetScript("OnEnter", function()
        P.ShowBarTooltip(this)
    end)
    bar:SetScript("OnLeave", function()
        P.HideBarTooltip()
    end)
    bar:SetScript("OnMouseUp", function()
        if this.viewType == "deaths" and this.playerName then
            if P.ShowDeathRecapForPlayer then
                P.ShowDeathRecapForPlayer(this.playerName, this.segment)
            end
        end
    end)

    bar.playerName = nil
    bar.playerData = nil
    bar.viewType = nil
    bar.segment = nil

    return bar
end

local function GetBar(frame, index)
    local pc = frame.pc
    if not pc.bars[index] then
        pc.bars[index] = CreateBar(frame.container)
    end
    return pc.bars[index]
end

---------------------------------------------------------------------------
-- Custom Tooltip with Spell Bars
---------------------------------------------------------------------------

local TOOLTIP_WIDTH = 270
local TOOLTIP_BAR_HEIGHT = 12
local TOOLTIP_BAR_SPACING = 1
local TOOLTIP_PADDING = 8
local MAX_TOOLTIP_BARS = 10

local tooltipFrame = CreateFrame("Frame", "ParsecBarTooltip", UIParent)
tooltipFrame:SetBackdrop({
    bgFile = "Interface\\AddOns\\Parsec\\textures\\window-bg",
    edgeFile = "Interface\\AddOns\\Parsec\\textures\\window-border",
    tile = true, tileSize = 128, edgeSize = 16,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
tooltipFrame:SetBackdropColor(1, 1, 1, 0.92)
tooltipFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
tooltipFrame:SetFrameStrata("TOOLTIP")
tooltipFrame:SetWidth(TOOLTIP_WIDTH)
tooltipFrame:Hide()

tooltipFrame.title = tooltipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
tooltipFrame.title:SetPoint("TOPLEFT", tooltipFrame, "TOPLEFT", TOOLTIP_PADDING, -TOOLTIP_PADDING)
tooltipFrame.title:SetPoint("RIGHT", tooltipFrame, "RIGHT", -TOOLTIP_PADDING, 0)
tooltipFrame.title:SetJustifyH("LEFT")

tooltipFrame.infoLines = {}
for iLine = 1, 4 do
    local left = tooltipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    left:SetJustifyH("LEFT")
    local right = tooltipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    right:SetJustifyH("RIGHT")
    right:SetTextColor(1, 1, 1)
    tooltipFrame.infoLines[iLine] = { left = left, right = right }
end

tooltipFrame.separator = tooltipFrame:CreateTexture(nil, "ARTWORK")
tooltipFrame.separator:SetTexture(1, 1, 1, 0.15)
tooltipFrame.separator:SetHeight(1)

tooltipFrame.spellBars = {}
for iBar = 1, MAX_TOOLTIP_BARS do
    local sbar = CreateFrame("StatusBar", nil, tooltipFrame)
    sbar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    sbar:SetMinMaxValues(0, 1)
    sbar:SetHeight(TOOLTIP_BAR_HEIGHT)

    sbar.bg = sbar:CreateTexture(nil, "BACKGROUND")
    sbar.bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    sbar.bg:SetAllPoints(sbar)
    sbar.bg:SetVertexColor(0.1, 0.1, 0.1, 0.6)

    sbar.name = sbar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sbar.name:SetPoint("LEFT", sbar, "LEFT", 2, 0)
    sbar.name:SetJustifyH("LEFT")
    sbar.name:SetShadowColor(0, 0, 0, 1)
    sbar.name:SetShadowOffset(1, -1)

    sbar.crit = sbar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sbar.crit:SetJustifyH("RIGHT")
    sbar.crit:SetTextColor(1, 1, 0)
    sbar.crit:SetShadowColor(0, 0, 0, 1)
    sbar.crit:SetShadowOffset(1, -1)
    sbar.crit:SetWidth(32)

    sbar.value = sbar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sbar.value:SetPoint("RIGHT", sbar, "RIGHT", -2, 0)
    sbar.value:SetJustifyH("RIGHT")
    sbar.value:SetTextColor(1, 0.82, 0)
    sbar.value:SetShadowColor(0, 0, 0, 1)
    sbar.value:SetShadowOffset(1, -1)

    sbar.crit:SetPoint("RIGHT", sbar, "RIGHT", -82, 0)
    sbar.name:SetPoint("RIGHT", sbar.crit, "LEFT", -2, 0)

    tooltipFrame.spellBars[iBar] = sbar
end

function P.HideBarTooltip()
    tooltipFrame:Hide()
    GameTooltip:Hide()
end

function P.ShowBarTooltip(bar)
    if not bar.playerName then return end

    -- Deaths view: show last death info in GameTooltip
    if bar.viewType == "deaths" then
        local name = bar.playerName
        local DL = P.deathLog
        if not DL then return end
        local segment = bar.segment or "current"
        local count = DL:GetDeathCount(name, segment)
        local deaths = DL:GetDeathsForPlayer(name, segment)

        GameTooltip:SetOwner(bar, "ANCHOR_CURSOR")
        local cc = P.GetClassColor(name)
        GameTooltip:AddLine(name, cc.r, cc.g, cc.b)
        GameTooltip:AddLine(count .. (count == 1 and " death" or " deaths"), 1, 1, 1)
        if table.getn(deaths) > 0 then
            local last = deaths[1]
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Last death:", 1, 0.82, 0)
            GameTooltip:AddLine(last.killSpell .. " (" .. last.killedBy .. ")", 1, 0.3, 0.3)
            GameTooltip:AddLine(P.FormatNumber(last.killAmount) .. " damage", 0.8, 0.8, 0.8)
            if last.timeFmt then
                GameTooltip:AddLine("at " .. last.timeFmt, 0.6, 0.6, 0.6)
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to open Death Recap", 0, 0.8, 1)
        GameTooltip:Show()
        return
    end

    if not bar.playerData then return end
    local data = bar.playerData
    local name = bar.playerName
    local vt = bar.viewType

    local cc = P.GetClassColor(name)
    local s = P.settings or {}
    local texIdx = s.barTexture or 1
    local texPath = P.BAR_TEXTURES and P.BAR_TEXTURES[texIdx]
        or "Interface\\TargetingFrame\\UI-StatusBar"

    -- Position tooltip at cursor
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    cx = cx / scale
    cy = cy / scale
    tooltipFrame:ClearAllPoints()
    tooltipFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx + 16, cy + 8)

    -- Title: player name in class color
    tooltipFrame.title:SetText(name)
    tooltipFrame.title:SetTextColor(cc.r, cc.g, cc.b)

    local yOff = -(TOOLTIP_PADDING + 16)

    -- Gather info + spells
    local segment = bar.segment or "overall"
    local duration = P.combatState:GetDuration(segment)
    if duration < 1 then duration = 1 end

    local infoCount = 0
    local spells = {}
    local totalValue = 0
    local isDmg = (vt == "damage" or vt == "dps")

    local playerDur = data.last_action - data.first_action
    if playerDur < 1 then playerDur = duration end

    if isDmg then
        infoCount = 2
        tooltipFrame.infoLines[1].left:SetText("Total Damage:")
        tooltipFrame.infoLines[1].left:SetTextColor(1, 0.82, 0)
        tooltipFrame.infoLines[1].right:SetText(P.FormatNumber(data.damage_total))
        tooltipFrame.infoLines[2].left:SetText("DPS:")
        tooltipFrame.infoLines[2].left:SetTextColor(1, 0.82, 0)
        tooltipFrame.infoLines[2].right:SetText(
            string.format("%.1f", data.damage_total / playerDur))

        totalValue = data.damage_total
        for key, sp in pairs(data.damage_spells) do
            table.insert(spells, { name = sp.name or key, data = sp })
        end
        table.sort(spells, function(a, b) return a.data.total > b.data.total end)
    else
        infoCount = 3
        tooltipFrame.infoLines[1].left:SetText("Total Healing:")
        tooltipFrame.infoLines[1].left:SetTextColor(0.2, 1, 0.2)
        tooltipFrame.infoLines[1].right:SetText(P.FormatNumber(data.heal_total))
        tooltipFrame.infoLines[2].left:SetText("Effective:")
        tooltipFrame.infoLines[2].left:SetTextColor(0.2, 1, 0.2)
        tooltipFrame.infoLines[2].right:SetText(P.FormatNumber(data.heal_effective))

        if data.heal_total > 0 then
            infoCount = 4
            tooltipFrame.infoLines[3].left:SetText("Overhealing:")
            tooltipFrame.infoLines[3].left:SetTextColor(1, 0.5, 0)
            tooltipFrame.infoLines[3].right:SetText(
                P.FormatNumber(data.heal_overheal)
                .. " (" .. P.FormatPct(data.heal_overheal, data.heal_total) .. ")")
            tooltipFrame.infoLines[4].left:SetText("HPS:")
            tooltipFrame.infoLines[4].left:SetTextColor(0.2, 1, 0.2)
            tooltipFrame.infoLines[4].right:SetText(
                string.format("%.1f", data.heal_effective / playerDur))
        else
            tooltipFrame.infoLines[3].left:SetText("HPS:")
            tooltipFrame.infoLines[3].left:SetTextColor(0.2, 1, 0.2)
            tooltipFrame.infoLines[3].right:SetText(
                string.format("%.1f", data.heal_effective / playerDur))
        end

        totalValue = data.heal_effective
        for key, sp in pairs(data.heal_spells) do
            table.insert(spells, { name = sp.name or key, data = sp })
        end
        table.sort(spells, function(a, b)
            return a.data.effective > b.data.effective
        end)
    end

    -- Layout info lines
    for k = 1, 4 do
        local line = tooltipFrame.infoLines[k]
        if k <= infoCount then
            line.left:ClearAllPoints()
            line.left:SetPoint("TOPLEFT", tooltipFrame, "TOPLEFT",
                TOOLTIP_PADDING, yOff)
            line.right:ClearAllPoints()
            line.right:SetPoint("TOPRIGHT", tooltipFrame, "TOPRIGHT",
                -TOOLTIP_PADDING, yOff)
            line.left:Show()
            line.right:Show()
            yOff = yOff - 14
        else
            line.left:Hide()
            line.right:Hide()
        end
    end

    -- Separator
    yOff = yOff - 4
    tooltipFrame.separator:ClearAllPoints()
    tooltipFrame.separator:SetPoint("TOPLEFT", tooltipFrame, "TOPLEFT",
        TOOLTIP_PADDING, yOff)
    tooltipFrame.separator:SetPoint("RIGHT", tooltipFrame, "RIGHT",
        -TOOLTIP_PADDING, 0)
    tooltipFrame.separator:Show()
    yOff = yOff - 6

    -- Spell bars
    local numSpells = math.min(table.getn(spells), MAX_TOOLTIP_BARS)
    local topSpellValue = 0
    if numSpells > 0 then
        topSpellValue = isDmg and spells[1].data.total
            or spells[1].data.effective
    end

    local barW = TOOLTIP_WIDTH - (TOOLTIP_PADDING * 2)

    for k = 1, MAX_TOOLTIP_BARS do
        local sbar = tooltipFrame.spellBars[k]
        if k <= numSpells then
            local sp = spells[k]
            local spValue = isDmg and sp.data.total or sp.data.effective

            local pct = 0
            if topSpellValue > 0 then pct = spValue / topSpellValue end

            sbar:ClearAllPoints()
            sbar:SetPoint("TOPLEFT", tooltipFrame, "TOPLEFT",
                TOOLTIP_PADDING, yOff)
            sbar:SetWidth(barW)
            sbar:SetStatusBarTexture(texPath)
            sbar.bg:SetTexture(texPath)
            sbar:SetStatusBarColor(cc.r * 0.7, cc.g * 0.7, cc.b * 0.7, 0.9)
            sbar:SetValue(pct)

            -- Spell name (clean, no annotations)
            sbar.name:SetText(sp.name)
            sbar.name:SetTextColor(1, 1, 1)

            -- Crit column (exclude periodic ticks — they can never crit)
            local critText = ""
            local directHits = (sp.data.hits or 0) - (sp.data.ticks or 0)
            if directHits > 0 and sp.data.crits then
                critText = string.format("%.0f%%", (sp.data.crits / directHits) * 100)
            end
            sbar.crit:SetText(critText)
            sbar.crit:SetTextColor(1, 1, 0)

            -- Value + percentage of total
            local pctStr = ""
            if totalValue > 0 then
                pctStr = " " .. P.FormatPct(spValue, totalValue)
            end
            sbar.value:SetText(P.FormatNumber(spValue) .. pctStr)

            sbar:Show()
            yOff = yOff - (TOOLTIP_BAR_HEIGHT + TOOLTIP_BAR_SPACING)
        else
            sbar:Hide()
        end
    end

    -- Apply tooltip opacity from settings
    local ttAlpha = P.settings.tooltipOpacity or 0.92
    tooltipFrame:SetBackdropColor(1, 1, 1, ttAlpha)
    tooltipFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, ttAlpha)

    -- Set final height
    tooltipFrame:SetHeight(-(yOff) + TOOLTIP_PADDING)
    tooltipFrame:Show()
end

---------------------------------------------------------------------------
-- Shared state for dropdown menus
---------------------------------------------------------------------------

local TEX_PATH = "Interface\\AddOns\\Parsec\\textures\\"
P._windowCounter = 0
local menuTargetFrame = nil

---------------------------------------------------------------------------
-- Main menu dropdown (View, Segment, New Window, Reset, Options, Close)
---------------------------------------------------------------------------

local function InitMainMenu()
    if not menuTargetFrame then return end
    local targetFrame = menuTargetFrame
    local pc = targetFrame.pc
    if not pc then return end

    local info

    -- View section
    info = {}
    info.text = "View"
    info.isTitle = true
    UIDropDownMenu_AddButton(info)

    local enabledViews = GetEnabledViews()
    for i = 1, table.getn(enabledViews) do
        local capturedView = enabledViews[i]
        info = {}
        info.text = VIEW_LABELS[capturedView]
        info.checked = (pc.viewType == capturedView)
        info.func = function()
            pc.viewType = capturedView
            pc.scrollOffset = 0
            P.UpdateWindowTitle(targetFrame)
            P.UpdateParsecWindow(targetFrame)
            P.SaveWindowState()
        end
        UIDropDownMenu_AddButton(info)
    end

    -- Segment section
    info = {}
    info.text = "Segment"
    info.isTitle = true
    UIDropDownMenu_AddButton(info)

    local segments = { "current", "overall" }
    for i = 1, 2 do
        local capturedSeg = segments[i]
        info = {}
        info.text = SEGMENT_LABELS[capturedSeg]
        info.checked = (pc.segment == capturedSeg)
        info.func = function()
            pc.segment = capturedSeg
            pc.scrollOffset = 0
            P.UpdateWindowTitle(targetFrame)
            P.UpdateParsecWindow(targetFrame)
            P.SaveWindowState()
        end
        UIDropDownMenu_AddButton(info)
    end

    -- History entries
    local ds = P.dataStore
    local histCount = ds and ds:GetHistoryCount() or 0
    if histCount > 0 then
        info = {}
        info.text = "History"
        info.isTitle = true
        UIDropDownMenu_AddButton(info)
        for hi = 1, histCount do
            local capturedIdx = hi
            info = {}
            info.text = "[H" .. hi .. "] " .. (ds:GetHistoryLabel(hi) or "")
            info.checked = (type(pc.segment) == "number" and pc.segment == capturedIdx)
            info.func = function()
                pc.segment = capturedIdx
                pc.scrollOffset = 0
                P.UpdateWindowTitle(targetFrame)
                P.UpdateParsecWindow(targetFrame)
                P.SaveWindowState()
            end
            UIDropDownMenu_AddButton(info)
        end
    end

    -- Separator
    info = {}
    info.text = ""
    info.disabled = true
    UIDropDownMenu_AddButton(info)

    -- New Window
    info = {}
    info.text = "New Window"
    info.func = function()
        local f = P.CreateWindow("damage", "current")
        if f then
            f:Show()
            P.UpdateParsecWindow(f)
            P.SaveWindowState()
        end
    end
    UIDropDownMenu_AddButton(info)

    -- Reset
    info = {}
    info.text = "Reset All"
    info.func = function()
        P.ResetData()
    end
    UIDropDownMenu_AddButton(info)

    -- Death Recap
    info = {}
    info.text = "Death Recap"
    info.func = function()
        if P.ShowDeathRecap then
            P.ShowDeathRecap()
        end
    end
    UIDropDownMenu_AddButton(info)

    -- Options
    info = {}
    info.text = "Options"
    info.func = function()
        P.ToggleOptions()
    end
    UIDropDownMenu_AddButton(info)

    -- Close Window (only if more than 1)
    if table.getn(P.windows) > 1 then
        info = {}
        info.text = "|cffff4444Close Window|r"
        info.func = function()
            P.RemoveWindow(targetFrame)
        end
        UIDropDownMenu_AddButton(info)
    end
end

---------------------------------------------------------------------------
-- Announce channel dropdown (Say, Party, Raid, BG)
---------------------------------------------------------------------------

local function GetChatColor(chatType)
    if ChatTypeInfo and ChatTypeInfo[chatType] then
        return ChatTypeInfo[chatType].r or 1, ChatTypeInfo[chatType].g or 1, ChatTypeInfo[chatType].b or 1
    end
    return 1, 1, 1
end

local function ColorText(text, r, g, b)
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) .. text .. "|r"
end

local function InitAnnounceMenu()
    if not menuTargetFrame then return end
    local targetFrame = menuTargetFrame
    local ec = P.settings.enabledChannels or {}

    -- Standard channels (only enabled ones)
    local channels = {
        { label = "Say (/s)",             ch = "SAY",           chatType = "SAY" },
        { label = "Party (/p)",           ch = "PARTY",         chatType = "PARTY" },
        { label = "Guild (/g)",           ch = "GUILD",         chatType = "GUILD" },
        { label = "Raid (/raid)",         ch = "RAID",          chatType = "RAID" },
        { label = "Battleground (/bg)",   ch = "BATTLEGROUND",  chatType = "BATTLEGROUND" },
    }

    for i = 1, table.getn(channels) do
        if ec[channels[i].ch] then
            local capturedCh = channels[i].ch
            local r, g, b = GetChatColor(channels[i].chatType)
            local info = {}
            info.text = ColorText(channels[i].label, r, g, b)
            info.notCheckable = 1
            info.func = function()
                P.AnnounceToChannel(targetFrame, capturedCh)
            end
            UIDropDownMenu_AddButton(info)
        end
    end

    -- Custom channels (only enabled + currently joined)
    if GetChannelList then
        local chList = { GetChannelList() }
        for i = 1, table.getn(chList), 2 do
            local chId = chList[i]
            local chName = chList[i + 1]
            if chName and ec["CHANNEL_" .. chName] then
                local capturedId = chId
                local chatType = "CHANNEL" .. chId
                local r, g, b = GetChatColor(chatType)
                if r == 1 and g == 1 and b == 1 then
                    r, g, b = GetChatColor("CHANNEL")
                end
                local info = {}
                info.text = ColorText(chName .. " (/" .. chId .. ")", r, g, b)
                info.notCheckable = 1
                info.func = function()
                    P.AnnounceToChannel(targetFrame, "CHANNEL", capturedId)
                end
                UIDropDownMenu_AddButton(info)
            end
        end
    end
end

-- Segment dropdown init (for right-click on [C]/[O] button)
local segmentMenuTarget = nil

local function GetPlayerSegmentValue(ds, viewType, segment)
    if not ds then return 0 end
    local playerName = UnitName("player")
    if not playerName then return 0 end

    local seg
    if segment == "overall" then
        seg = ds.overall
    elseif type(segment) == "number" then
        local entry = ds.history[segment]
        if not entry then return 0 end
        seg = entry.segment
    else
        seg = ds.current
    end

    local data = seg and seg.players and seg.players[playerName]
    if not data then return 0 end

    local duration = ds:GetDuration(segment)
    if duration < 1 then duration = 1 end
    local playerDur = (data.last_action or 0) - (data.first_action or 0)
    if playerDur < 1 then playerDur = duration end

    if viewType == "damage" then
        return data.damage_total or 0
    elseif viewType == "dps" then
        return (data.damage_total or 0) / playerDur
    elseif viewType == "healing" then
        return data.heal_total or 0
    elseif viewType == "hps" then
        return (data.heal_effective or 0) / playerDur
    elseif viewType == "effheal" then
        return data.heal_effective or 0
    end
    return 0
end

local function InitSegmentMenu()
    if not segmentMenuTarget then return end
    local targetFrame = segmentMenuTarget
    local pc = targetFrame.pc
    if not pc then return end
    local ds = P.dataStore
    local vt = pc.viewType or "damage"
    local isRate = (vt == "dps" or vt == "hps")
    local info

    local function FmtVal(val)
        if val <= 0 then return "" end
        if isRate then
            return "  |cffffffff" .. string.format("%.1f", val) .. "|r"
        end
        return "  |cffffffff" .. P.FormatNumber(val) .. "|r"
    end

    -- Current / Overall
    local segments = { "current", "overall" }
    for i = 1, 2 do
        local capturedSeg = segments[i]
        local total = GetPlayerSegmentValue(ds, vt, capturedSeg)
        local suffix = FmtVal(total)
        info = {}
        info.text = SEGMENT_LABELS[capturedSeg] .. suffix
        info.checked = (pc.segment == capturedSeg)
        info.func = function()
            pc.segment = capturedSeg
            pc.scrollOffset = 0
            P.UpdateWindowTitle(targetFrame)
            P.UpdateParsecWindow(targetFrame)
            P.SaveWindowState()
        end
        UIDropDownMenu_AddButton(info)
    end

    -- History entries
    local histCount = ds and ds:GetHistoryCount() or 0
    if histCount > 0 then
        info = {}
        info.text = "History"
        info.isTitle = true
        UIDropDownMenu_AddButton(info)
        for hi = 1, histCount do
            local capturedIdx = hi
            local total = GetPlayerSegmentValue(ds, vt, hi)
            local suffix = FmtVal(total)
            info = {}
            info.text = "[H" .. hi .. "] " .. (ds:GetHistoryLabel(hi) or "") .. suffix
            info.checked = (type(pc.segment) == "number" and pc.segment == capturedIdx)
            info.func = function()
                pc.segment = capturedIdx
                pc.scrollOffset = 0
                P.UpdateWindowTitle(targetFrame)
                P.UpdateParsecWindow(targetFrame)
                P.SaveWindowState()
            end
            UIDropDownMenu_AddButton(info)
        end
    end
end

-- Shared dropdown frames (context menu style, no visible button)
local mainMenu = CreateFrame("Frame", "ParsecMainMenu")
mainMenu.displayMode = "MENU"
mainMenu.initialize = InitMainMenu

local announceMenu = CreateFrame("Frame", "ParsecAnnounceMenu")
announceMenu.displayMode = "MENU"
announceMenu.initialize = InitAnnounceMenu

local segmentMenu = CreateFrame("Frame", "ParsecSegmentMenu")
segmentMenu.displayMode = "MENU"
segmentMenu.initialize = InitSegmentMenu

---------------------------------------------------------------------------
-- Text button helper for title bar
---------------------------------------------------------------------------

local function CreateTitleBarButton(parent, text, tooltip, width, hoverColor, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(14)
    btn:SetWidth(width)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText(text)
    label:SetTextColor(0, 0.8, 1)
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
    btn.label = label

    local capturedTip = tooltip
    btn:SetScript("OnEnter", function()
        label:SetTextColor(0.5, 0.9, 1)
        if capturedTip then
            GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(capturedTip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        label:SetTextColor(0, 0.8, 1)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", onClick)

    return btn
end

---------------------------------------------------------------------------
-- Update window title text
---------------------------------------------------------------------------

local SEGMENT_TEXTS = {
    current = "[C]",
    overall = "[O]",
}
local SEGMENT_COLORS = {
    current = { r = 0, g = 0.8, b = 1 },
    overall = { r = 1, g = 1, b = 0 },
}
local HISTORY_COLOR = { r = 1, g = 0.6, b = 0 }

function P.UpdateWindowTitle(frame)
    local pc = frame.pc
    if not pc then return end
    local viewLabel = VIEW_LABELS[pc.viewType] or pc.viewType
    local duration = 0
    if P.dataStore then
        duration = P.dataStore:GetDuration(pc.segment)
    end
    local durText = P.FormatDuration(duration)

    -- Segment button text + color
    local segText, sc
    if type(pc.segment) == "number" then
        segText = "[H" .. pc.segment .. "]"
        sc = HISTORY_COLOR
    else
        segText = SEGMENT_TEXTS[pc.segment] or "[?]"
        sc = SEGMENT_COLORS[pc.segment]
    end
    frame.segBtn.label:SetText(segText)
    if sc then
        frame.segBtn.label:SetTextColor(sc.r, sc.g, sc.b)
    end
    local segW = frame.segBtn.label:GetStringWidth()
    frame.segBtn:SetWidth((segW and segW > 0) and (segW + 4) or 24)

    -- View label text
    frame.viewBtn.label:SetText(viewLabel)
    local viewW = frame.viewBtn.label:GetStringWidth()
    frame.viewBtn:SetWidth((viewW and viewW > 0) and (viewW + 4) or 50)

    -- Duration text
    frame.durText:SetText(durText)
end

---------------------------------------------------------------------------
-- Update a single window
---------------------------------------------------------------------------

function P.UpdateParsecWindow(frame)
    if not frame or not frame:IsVisible() then return end
    local pc = frame.pc
    if not pc then return end
    local ds = P.dataStore
    if not ds then return end

    local s = P.settings or {}
    local barH = s.barHeight or 14
    local barSpc = s.barSpacing or 1

    local sorted, duration, raidTotal = ds:GetSorted(pc.viewType, pc.segment)

    -- Update title
    P.UpdateWindowTitle(frame)

    local totalEntries = table.getn(sorted)
    local topValue = 0
    if totalEntries > 0 then topValue = sorted[1].value end

    local visibleBars = 0
    local yOffset = 0

    -- Total bar (always slot 1)
    local totalBar = GetBar(frame, 1)
    totalBar:ClearAllPoints()
    totalBar:SetPoint("TOPLEFT", frame.container, "TOPLEFT", 0, 0)
    totalBar:SetPoint("RIGHT", frame.container, "RIGHT", 0, 0)
    totalBar:SetHeight(barH)
    totalBar:SetStatusBarColor(0.25, 0.25, 0.3, 1)
    totalBar:SetValue(1)
    totalBar.bg:SetVertexColor(0.08, 0.08, 0.1, 0.8)
    totalBar.rank:SetText("")
    totalBar.name:SetText("Total")
    totalBar.name:SetTextColor(0.85, 0.85, 0.85)

    -- Format total value based on view type (cached to avoid string allocation)
    if frame._cTotalVal ~= raidTotal or frame._cTotalView ~= pc.viewType then
        frame._cTotalVal = raidTotal
        frame._cTotalView = pc.viewType
        if pc.viewType == "deaths" then
            totalBar.value:SetText(string.format("%.0f", raidTotal))
        elseif pc.viewType == "dps" or pc.viewType == "hps" then
            totalBar.value:SetText(string.format("%.1f", raidTotal))
        else
            totalBar.value:SetText(P.FormatNumber(raidTotal))
        end
    end
    totalBar.playerName = nil
    totalBar.playerData = nil
    totalBar:Show()
    visibleBars = 1
    yOffset = barH + barSpc

    local containerH = frame.container:GetHeight()
    local maxVisible = math.floor((containerH - yOffset) / (barH + barSpc))
    if maxVisible < 0 then maxVisible = 0 end

    for i = 1, math.min(totalEntries, maxVisible) do
        local entryIdx = i + pc.scrollOffset
        if entryIdx > totalEntries then break end
        local entry = sorted[entryIdx]
        if not entry then break end

        visibleBars = visibleBars + 1
        local bar = GetBar(frame, visibleBars)

        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", frame.container, "TOPLEFT", 0, -yOffset)
        bar:SetPoint("RIGHT", frame.container, "RIGHT", 0, 0)
        bar:SetHeight(barH)

        local cc = P.GetClassColor(entry.name)
        bar:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
        bar.bg:SetVertexColor(cc.r * 0.15, cc.g * 0.15, cc.b * 0.15, 0.8)

        local pct = 0
        if topValue > 0 then pct = entry.value / topValue end
        bar:SetValue(pct)

        bar.rank:SetText(entryIdx)
        bar.name:SetText(entry.name)
        bar.name:SetTextColor(1, 1, 1)

        -- Cache bar text — skip string formatting when value unchanged
        if bar._cName ~= entry.name or bar._cValue ~= entry.value or bar._cTotal ~= raidTotal or bar._cView ~= pc.viewType then
            bar._cName = entry.name
            bar._cValue = entry.value
            bar._cTotal = raidTotal
            bar._cView = pc.viewType

            local pctOfTotal = ""
            if raidTotal > 0 then
                pctOfTotal = " (" .. string.format("%.1f%%", (entry.value / raidTotal) * 100) .. ")"
            end

            if pc.viewType == "deaths" then
                bar.value:SetText(string.format("%.0f", entry.value))
            elseif pc.viewType == "dps" or pc.viewType == "hps" then
                bar.value:SetText(string.format("%.1f", entry.value) .. pctOfTotal)
            else
                bar.value:SetText(P.FormatNumber(entry.value) .. pctOfTotal)
            end
        end

        bar.playerName = entry.name
        bar.playerData = entry.raw
        bar.viewType = pc.viewType
        bar.segment = pc.segment

        bar:Show()
        yOffset = yOffset + barH + barSpc
    end

    for i = visibleBars + 1, table.getn(pc.bars) do
        if pc.bars[i] then pc.bars[i]:Hide() end
    end
end

---------------------------------------------------------------------------
-- Update all windows
---------------------------------------------------------------------------

function P.UpdateAllWindows()
    for i = 1, table.getn(P.windows) do
        P.UpdateParsecWindow(P.windows[i])
    end
end

---------------------------------------------------------------------------
-- Announce to chat
---------------------------------------------------------------------------

function P.AnnounceToChannel(frame, channel, channelId)
    if not frame or not frame.pc then return end
    if not channel then return end
    local pc = frame.pc
    local ds = P.dataStore
    if not ds then return end

    local sorted, duration, raidTotal = ds:GetSorted(pc.viewType, pc.segment)
    if table.getn(sorted) == 0 then
        P.Print("Nothing to announce.")
        return
    end

    local viewLabel = VIEW_LABELS[pc.viewType] or pc.viewType
    local segLabel
    if type(pc.segment) == "number" then
        segLabel = "H" .. pc.segment .. " " .. (ds:GetHistoryLabel(pc.segment) or "")
    else
        segLabel = SEGMENT_LABELS[pc.segment] or pc.segment
    end
    local durText = P.FormatDuration(duration)

    -- channelId is used for custom channels (SendChatMessage 4th arg)
    local lang = nil
    SendChatMessage("[Parsec] " .. viewLabel .. " (" .. segLabel .. ") " .. durText, channel, lang, channelId)

    local count = math.min(table.getn(sorted), 5)
    for i = 1, count do
        local entry = sorted[i]
        local pctStr = ""
        if raidTotal > 0 then
            pctStr = string.format(" (%.1f%%)", (entry.value / raidTotal) * 100)
        end
        local valStr
        if pc.viewType == "deaths" then
            valStr = string.format("%.0f", entry.value)
            pctStr = ""
        elseif pc.viewType == "dps" or pc.viewType == "hps" then
            valStr = string.format("%.1f", entry.value)
        else
            valStr = P.FormatNumber(entry.value)
        end
        SendChatMessage(i .. ". " .. entry.name .. " - " .. valStr .. pctStr, channel, lang, channelId)
    end
end

-- Auto-detect channel wrapper (for slash command usage)
function P.Announce(frame)
    local channel = "SAY"
    if GetNumRaidMembers() > 0 then
        channel = "RAID"
    elseif GetNumPartyMembers() > 0 then
        channel = "PARTY"
    end
    P.AnnounceToChannel(frame, channel)
end

---------------------------------------------------------------------------
-- Window resize handler
---------------------------------------------------------------------------

function P.OnWindowResize(frame)
    if not frame then return end
    local w = frame:GetWidth()
    local h = frame:GetHeight()
    frame.container:SetWidth(w - 8)
    frame.container:SetHeight(h - 28)
    P.UpdateParsecWindow(frame)
end

---------------------------------------------------------------------------
-- Reset data
---------------------------------------------------------------------------

function P.ResetData()
    if P.dataStore then
        P.dataStore:ResetAll()
    end
    P.UpdateAllWindows()
end

---------------------------------------------------------------------------
-- Toggle / Show / Hide
---------------------------------------------------------------------------

function P.ToggleWindow()
    if table.getn(P.windows) == 0 then
        P.Print("|cffff4444No windows created!|r")
        return
    end
    local visible = P.windows[1]:IsVisible()
    for i = 1, table.getn(P.windows) do
        if visible then
            P.windows[i]:Hide()
        else
            P.windows[i]:Show()
            P.UpdateParsecWindow(P.windows[i])
        end
    end
    P.SaveWindowState()
end

function P.ShowAllWindows()
    for i = 1, table.getn(P.windows) do
        P.windows[i]:Show()
        P.UpdateParsecWindow(P.windows[i])
    end
    P.SaveWindowState()
end

function P.HideAllWindows()
    for i = 1, table.getn(P.windows) do
        P.windows[i]:Hide()
    end
    P.SaveWindowState()
end

---------------------------------------------------------------------------
-- Create a new window
---------------------------------------------------------------------------

function P.CreateWindow(viewType, segment)
    P._windowCounter = P._windowCounter + 1
    local idx = P._windowCounter

    local f = CreateFrame("Frame", "ParsecWin" .. idx, UIParent)
    f:SetWidth(220)
    f:SetHeight(200)
    local numWin = table.getn(P.windows)
    f:SetPoint("CENTER", UIParent, "CENTER", numWin * 20, numWin * -20)
    f:SetBackdrop({
        bgFile = TEX_PATH .. "window-bg",
        edgeFile = TEX_PATH .. "window-border",
        tile = true, tileSize = 128, edgeSize = 16,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(1, 1, 1, 0.8)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetToplevel(true)
    f:SetMinResize(150, 80)
    f:SetMaxResize(400, 600)
    f:Hide()

    f.pc = {
        viewType = viewType or "damage",
        segment = segment or "current",
        bars = {},
        scrollOffset = 0,
        updateTimer = 0,
    }

    -- Title bar background
    f.titleBG = f:CreateTexture(nil, "ARTWORK")
    f.titleBG:SetTexture(TEX_PATH .. "banner")
    f.titleBG:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    f.titleBG:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    f.titleBG:SetHeight(20)

    -- Close button [X] (right-most, red hover)
    local closeBtn = CreateTitleBarButton(f, "X", nil, 16,
        { r = 1, g = 0.3, b = 0.3 },
        function() this:GetParent():Hide(); P.SaveWindowState() end)
    closeBtn:SetPoint("RIGHT", f.titleBG, "RIGHT", -2, 0)

    -- Announce button [>>] (left of close, cyan hover)
    local annBtn = CreateTitleBarButton(f, ">>", "Announce to chat", 20,
        { r = 0, g = 0.8, b = 1 },
        function()
            menuTargetFrame = this:GetParent()
            ToggleDropDownMenu(1, nil, announceMenu, "cursor", 0, 0)
        end)
    annBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)

    -- Menu button [Menu] (left of announce, cyan hover)
    local menuBtn = CreateTitleBarButton(f, "Menu", "View, Segment, Options", 36,
        { r = 0, g = 0.8, b = 1 },
        function()
            menuTargetFrame = this:GetParent()
            ToggleDropDownMenu(1, nil, mainMenu, "cursor", 0, 0)
        end)
    menuBtn:SetPoint("RIGHT", annBtn, "LEFT", -2, 0)

    -- Segment indicator [O]/[C] — click to toggle
    local segBtn = CreateFrame("Button", nil, f)
    segBtn:SetHeight(20)
    segBtn:SetWidth(24)
    segBtn:SetPoint("LEFT", f.titleBG, "LEFT", 2, 0)
    local segLabel = segBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    segLabel:SetPoint("CENTER", segBtn, "CENTER", 0, 0)
    segLabel:SetShadowColor(0, 0, 0, 1)
    segLabel:SetShadowOffset(1, -1)
    segBtn.label = segLabel
    segBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    segBtn:SetScript("OnClick", function()
        local f = this:GetParent()
        local pc = f.pc
        if arg1 == "RightButton" then
            segmentMenuTarget = f
            ToggleDropDownMenu(1, nil, segmentMenu, "cursor", 0, 0)
            return
        end
        if pc.segment == "current" then
            pc.segment = "overall"
        else
            pc.segment = "current"
        end
        pc.scrollOffset = 0
        P.UpdateWindowTitle(f)
        P.UpdateParsecWindow(f)
        P.SaveWindowState()
    end)
    segBtn:SetScript("OnEnter", function()
        this.label:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
        local pc = this:GetParent().pc
        if type(pc.segment) == "number" then
            local ds = P.dataStore
            local label = ds and ds:GetHistoryLabel(pc.segment) or ("Fight " .. pc.segment)
            GameTooltip:AddLine("History: " .. label, 1, 0.6, 0)
        else
            GameTooltip:AddLine("[O]verall / [C]urrent", 1, 1, 1)
        end
        local ds = P.dataStore
        local histCount = ds and ds:GetHistoryCount() or 0
        GameTooltip:AddLine("Click to cycle", 0.7, 0.7, 0.7)
        if histCount > 0 then
            GameTooltip:AddLine("Right-click: select segment (" .. histCount .. " saved)", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    segBtn:SetScript("OnLeave", function()
        P.UpdateWindowTitle(this:GetParent())
        GameTooltip:Hide()
    end)
    f.segBtn = segBtn

    -- View label (Damage/Healing/...) — click to cycle metric
    local viewBtn = CreateFrame("Button", nil, f)
    viewBtn:SetHeight(20)
    viewBtn:SetWidth(50)
    viewBtn:SetPoint("LEFT", segBtn, "RIGHT", 0, 0)
    local viewLabel = viewBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    viewLabel:SetPoint("LEFT", viewBtn, "LEFT", 0, 0)
    viewLabel:SetJustifyH("LEFT")
    viewLabel:SetTextColor(0, 0.8, 1)
    viewLabel:SetShadowColor(0, 0, 0, 1)
    viewLabel:SetShadowOffset(1, -1)
    viewBtn.label = viewLabel
    viewBtn:SetScript("OnClick", function()
        if not (P.settings and P.settings.clickToCycleView) then return end
        local pc = this:GetParent().pc
        local enabled = GetEnabledViews()
        if table.getn(enabled) == 0 then return end
        local currentIdx = 0
        for i = 1, table.getn(enabled) do
            if enabled[i] == pc.viewType then
                currentIdx = i
                break
            end
        end
        local nextIdx = currentIdx + 1
        if nextIdx > table.getn(enabled) then nextIdx = 1 end
        pc.viewType = enabled[nextIdx]
        pc.scrollOffset = 0
        P.UpdateWindowTitle(this:GetParent())
        P.UpdateParsecWindow(this:GetParent())
        P.SaveWindowState()
    end)
    viewBtn:SetScript("OnEnter", function()
        if P.settings and P.settings.clickToCycleView then
            this.label:SetTextColor(1, 1, 1)
            GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
            GameTooltip:AddLine("Click to cycle metric", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    viewBtn:SetScript("OnLeave", function()
        this.label:SetTextColor(0, 0.8, 1)
        GameTooltip:Hide()
    end)
    f.viewBtn = viewBtn

    -- Duration text
    f.durText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.durText:SetPoint("LEFT", viewBtn, "RIGHT", 2, 0)
    f.durText:SetPoint("RIGHT", menuBtn, "LEFT", -4, 0)
    f.durText:SetTextColor(0, 0.8, 1)
    f.durText:SetJustifyH("LEFT")
    f.durText:SetShadowColor(0, 0, 0, 1)
    f.durText:SetShadowOffset(1, -1)

    -- Bar container
    f.container = CreateFrame("Frame", nil, f)
    f.container:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -24)
    f.container:SetWidth(212)
    f.container:SetHeight(172)

    -- Resize grip
    local grip = CreateFrame("Frame", nil, f)
    grip:SetWidth(16)
    grip:SetHeight(16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    grip:EnableMouse(true)
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetTexture(TEX_PATH .. "ResizeGrip")
    gripTex:SetAllPoints(grip)
    grip:SetScript("OnMouseDown", function()
        this:GetParent():StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        local parent = this:GetParent()
        parent:StopMovingOrSizing()
        P.OnWindowResize(parent)
        P.SaveWindowState()
    end)

    -- Drag to move
    f:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" and not (P.settings and P.settings.lockWindows) then
            this:StartMoving()
        end
    end)
    f:SetScript("OnMouseUp", function()
        this:StopMovingOrSizing()
        P.SaveWindowState()
    end)

    -- Size changed
    f:SetScript("OnSizeChanged", function()
        P.OnWindowResize(this)
    end)

    -- Scroll wheel
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function()
        this.pc.scrollOffset = this.pc.scrollOffset - (arg1 or 0)
        if this.pc.scrollOffset < 0 then this.pc.scrollOffset = 0 end
        P.UpdateParsecWindow(this)
    end)

    -- Live refresh handled by shared ParsecWindowTimer (no per-window OnUpdate)

    table.insert(P.windows, f)
    P.UpdateWindowTitle(f)
    return f
end

---------------------------------------------------------------------------
-- Remove a window (permanently)
---------------------------------------------------------------------------

function P.RemoveWindow(frame)
    if not frame then return end
    if table.getn(P.windows) <= 1 then
        frame:Hide()
        return
    end
    for i = 1, table.getn(P.windows) do
        if P.windows[i] == frame then
            table.remove(P.windows, i)
            break
        end
    end
    frame:Hide()
    P.SaveWindowState()
end

---------------------------------------------------------------------------
-- Window State Persistence
---------------------------------------------------------------------------

function P.SaveWindowState()
    if not ParsecCharDB then ParsecCharDB = {} end
    local saved = {}
    for i = 1, table.getn(P.windows) do
        local f = P.windows[i]
        local pc = f.pc
        if pc then
            local point, relativeTo, relativePoint, xOfs, yOfs = f:GetPoint(1)
            -- History segments don't survive reload, save as "current"
            local savedSegment = pc.segment
            if type(savedSegment) == "number" then
                savedSegment = "current"
            end
            table.insert(saved, {
                viewType = pc.viewType,
                segment = savedSegment,
                width = f:GetWidth(),
                height = f:GetHeight(),
                point = point,
                relativePoint = relativePoint,
                x = xOfs,
                y = yOfs,
                visible = f:IsVisible() and true or false,
            })
        end
    end
    ParsecCharDB.windows = saved
end

function P.LoadWindowState()
    if not ParsecCharDB or not ParsecCharDB.windows
        or table.getn(ParsecCharDB.windows) == 0 then
        -- No saved state: create defaults and show them
        for i = 1, table.getn(WINDOW_DEFS) do
            local f = P.CreateWindow(WINDOW_DEFS[i].viewType, WINDOW_DEFS[i].segment)
            if f then f:Show() end
        end
        P.SaveWindowState()
        return
    end

    for i = 1, table.getn(ParsecCharDB.windows) do
        local ws = ParsecCharDB.windows[i]
        local f = P.CreateWindow(ws.viewType, ws.segment)
        if f then
            f:ClearAllPoints()
            f:SetWidth(ws.width or 220)
            f:SetHeight(ws.height or 200)
            f:SetPoint(ws.point or "CENTER", UIParent,
                       ws.relativePoint or "CENTER",
                       ws.x or 0, ws.y or 0)
            P.OnWindowResize(f)
            if ws.visible then
                f:Show()
            end
        end
    end
end

---------------------------------------------------------------------------
-- LoadWindowState is called from bootstrap.lua after PLAYER_ENTERING_WORLD
-- (P.Print does not work during file load time)
---------------------------------------------------------------------------
