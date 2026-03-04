-- Parsec: Window UI
-- Configurable-view windows with per-window view/segment cycling
-- Title bar buttons: Settings, Reset, Announce, View cycle, Segment toggle

local P = Parsec
if not P then return end

table.insert(P._loadedFiles, "window")

P.windows = {}

local MAX_BARS = 20
local UPDATE_INTERVAL = 0.5

-- View cycle order
local VIEW_CYCLE = { "damage", "healing", "effheal", "dps", "hps" }
local VIEW_LABELS = {
    damage  = "Damage",
    healing = "Healing",
    effheal = "Eff. Healing",
    dps     = "DPS",
    hps     = "HPS",
}
local SEGMENT_LABELS = {
    current = "Current",
    overall = "Overall",
}

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

    bar.rank = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.rank:SetPoint("LEFT", bar, "LEFT", 2, 0)
    bar.rank:SetWidth(14)
    bar.rank:SetJustifyH("RIGHT")
    bar.rank:SetTextColor(0.6, 0.6, 0.6)
    bar.rank:SetShadowColor(0, 0, 0, 1)
    bar.rank:SetShadowOffset(1, -1)

    bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.name:SetPoint("LEFT", bar.rank, "RIGHT", 2, 0)
    bar.name:SetJustifyH("LEFT")
    bar.name:SetShadowColor(0, 0, 0, 1)
    bar.name:SetShadowOffset(1, -1)

    bar.value = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.value:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    bar.value:SetJustifyH("RIGHT")
    bar.value:SetTextColor(1, 0.82, 0)
    bar.value:SetShadowColor(0, 0, 0, 1)
    bar.value:SetShadowOffset(1, -1)

    bar.name:SetPoint("RIGHT", bar.value, "LEFT", -4, 0)

    bar:SetScript("OnEnter", function()
        P.ShowBarTooltip(this)
    end)
    bar:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    bar.playerName = nil
    bar.playerData = nil
    bar.viewType = nil

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
-- Tooltip
---------------------------------------------------------------------------

function P.ShowBarTooltip(bar)
    if not bar.playerName or not bar.playerData then return end
    local data = bar.playerData
    local name = bar.playerName
    local vt = bar.viewType

    GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    local cc = P.GetClassColor(name)
    GameTooltip:AddLine(name, cc.r, cc.g, cc.b)

    local segment = bar.segment or "overall"
    local duration = P.combatState:GetDuration(segment)
    if duration < 1 then duration = 1 end

    if vt == "damage" or vt == "dps" then
        GameTooltip:AddDoubleLine("Total Damage:", P.FormatNumber(data.damage_total), 1, 0.82, 0, 1, 1, 1)
        local playerDur = data.last_action - data.first_action
        if playerDur < 1 then playerDur = duration end
        GameTooltip:AddDoubleLine("DPS:", string.format("%.1f", data.damage_total / playerDur), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddLine(" ")

        local spells = {}
        for spellName, sp in pairs(data.damage_spells) do
            table.insert(spells, { name = spellName, data = sp })
        end
        table.sort(spells, function(a, b) return a.data.total > b.data.total end)

        for i = 1, math.min(table.getn(spells), 10) do
            local sp = spells[i]
            local pct = P.FormatPct(sp.data.total, data.damage_total)
            local critPct = ""
            if sp.data.hits > 0 then
                critPct = string.format(" (%.0f%% crit)", (sp.data.crits / sp.data.hits) * 100)
            end
            GameTooltip:AddDoubleLine(
                sp.name .. critPct,
                P.FormatNumber(sp.data.total) .. " - " .. pct,
                1, 1, 1, 0.8, 0.8, 0.8
            )
        end
    else
        GameTooltip:AddDoubleLine("Total Healing:", P.FormatNumber(data.heal_total), 0.2, 1, 0.2, 1, 1, 1)
        GameTooltip:AddDoubleLine("Effective:", P.FormatNumber(data.heal_effective), 0.2, 1, 0.2, 1, 1, 1)
        if data.heal_total > 0 then
            GameTooltip:AddDoubleLine("Overhealing:",
                P.FormatNumber(data.heal_overheal) .. " (" .. P.FormatPct(data.heal_overheal, data.heal_total) .. ")",
                1, 0.5, 0, 1, 1, 1)
        end
        local playerDur = data.last_action - data.first_action
        if playerDur < 1 then playerDur = duration end
        GameTooltip:AddDoubleLine("HPS:", string.format("%.1f", data.heal_effective / playerDur), 0.2, 1, 0.2, 1, 1, 1)
        GameTooltip:AddLine(" ")

        local spells = {}
        for spellName, sp in pairs(data.heal_spells) do
            table.insert(spells, { name = spellName, data = sp })
        end
        table.sort(spells, function(a, b) return a.data.effective > b.data.effective end)

        for i = 1, math.min(table.getn(spells), 10) do
            local sp = spells[i]
            local pct = P.FormatPct(sp.data.effective, data.heal_effective)
            local ohPct = ""
            if sp.data.total > 0 then
                ohPct = string.format(" (%.0f%% OH)", (sp.data.overheal / sp.data.total) * 100)
            end
            GameTooltip:AddDoubleLine(
                sp.name .. ohPct,
                P.FormatNumber(sp.data.effective) .. " - " .. pct,
                1, 1, 1, 0.8, 0.8, 0.8
            )
        end
    end

    GameTooltip:Show()
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

    for i = 1, table.getn(VIEW_CYCLE) do
        local capturedView = VIEW_CYCLE[i]
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

local function InitAnnounceMenu()
    if not menuTargetFrame then return end
    local targetFrame = menuTargetFrame

    local channels = {
        { label = "Say (/s)", ch = "SAY" },
        { label = "Party (/p)", ch = "PARTY" },
        { label = "Raid (/raid)", ch = "RAID" },
        { label = "Battleground (/bg)", ch = "BATTLEGROUND" },
    }

    for i = 1, table.getn(channels) do
        local capturedCh = channels[i].ch
        local info = {}
        info.text = channels[i].label
        info.func = function()
            P.AnnounceToChannel(targetFrame, capturedCh)
        end
        UIDropDownMenu_AddButton(info)
    end
end

-- Shared dropdown frames (context menu style, no visible button)
local mainMenu = CreateFrame("Frame", "ParsecMainMenu")
mainMenu.displayMode = "MENU"
mainMenu.initialize = InitMainMenu

local announceMenu = CreateFrame("Frame", "ParsecAnnounceMenu")
announceMenu.displayMode = "MENU"
announceMenu.initialize = InitAnnounceMenu

---------------------------------------------------------------------------
-- Text button helper for title bar
---------------------------------------------------------------------------

local function CreateTitleBarButton(parent, text, tooltip, width, hoverColor, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(14)
    btn:SetWidth(width)

    -- Dark background
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(0.08, 0.08, 0.12, 0.9)
    bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn.bg = bg

    -- Border textures (1px edges)
    local borderTop = btn:CreateTexture(nil, "BORDER")
    borderTop:SetTexture(0.3, 0.3, 0.3, 0.8)
    borderTop:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    borderTop:SetHeight(1)
    btn.borderTop = borderTop

    local borderBot = btn:CreateTexture(nil, "BORDER")
    borderBot:SetTexture(0.3, 0.3, 0.3, 0.8)
    borderBot:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    borderBot:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    borderBot:SetHeight(1)
    btn.borderBot = borderBot

    local borderL = btn:CreateTexture(nil, "BORDER")
    borderL:SetTexture(0.3, 0.3, 0.3, 0.8)
    borderL:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    borderL:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    borderL:SetWidth(1)
    btn.borderL = borderL

    local borderR = btn:CreateTexture(nil, "BORDER")
    borderR:SetTexture(0.3, 0.3, 0.3, 0.8)
    borderR:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    borderR:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    borderR:SetWidth(1)
    btn.borderR = borderR

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText(text)
    label:SetTextColor(0.7, 0.7, 0.7)
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
    btn.label = label

    local capturedTip = tooltip
    local hR = hoverColor and hoverColor.r or 0
    local hG = hoverColor and hoverColor.g or 0.8
    local hB = hoverColor and hoverColor.b or 1
    btn:SetScript("OnEnter", function()
        label:SetTextColor(1, 1, 1)
        this.borderTop:SetTexture(hR, hG, hB, 0.6)
        this.borderBot:SetTexture(hR, hG, hB, 0.6)
        this.borderL:SetTexture(hR, hG, hB, 0.6)
        this.borderR:SetTexture(hR, hG, hB, 0.6)
        if capturedTip then
            GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(capturedTip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        label:SetTextColor(0.7, 0.7, 0.7)
        this.borderTop:SetTexture(0.3, 0.3, 0.3, 0.8)
        this.borderBot:SetTexture(0.3, 0.3, 0.3, 0.8)
        this.borderL:SetTexture(0.3, 0.3, 0.3, 0.8)
        this.borderR:SetTexture(0.3, 0.3, 0.3, 0.8)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", onClick)

    return btn
end

---------------------------------------------------------------------------
-- Update window title text
---------------------------------------------------------------------------

local SEGMENT_INDICATORS = {
    current = "|cff00ccff[C]|r",
    overall = "|cffffff00[O]|r",
}

function P.UpdateWindowTitle(frame)
    local pc = frame.pc
    if not pc then return end
    local viewLabel = VIEW_LABELS[pc.viewType] or pc.viewType
    local segInd = SEGMENT_INDICATORS[pc.segment] or pc.segment
    local duration = 0
    if P.dataStore then
        duration = P.dataStore:GetDuration(pc.segment)
    end
    local durText = P.FormatDuration(duration)
    frame.titleText:SetText(segInd .. " " .. viewLabel .. " " .. durText)
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

    -- Format total value based on view type
    if pc.viewType == "dps" or pc.viewType == "hps" then
        totalBar.value:SetText(string.format("%.1f", raidTotal))
    else
        totalBar.value:SetText(P.FormatNumber(raidTotal))
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

        local pctOfTotal = ""
        if raidTotal > 0 then
            pctOfTotal = " (" .. string.format("%.1f%%", (entry.value / raidTotal) * 100) .. ")"
        end

        if pc.viewType == "dps" or pc.viewType == "hps" then
            bar.value:SetText(string.format("%.1f", entry.value) .. pctOfTotal)
        else
            bar.value:SetText(P.FormatNumber(entry.value) .. pctOfTotal)
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

function P.AnnounceToChannel(frame, channel)
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
    local segLabel = SEGMENT_LABELS[pc.segment] or pc.segment
    local durText = P.FormatDuration(duration)

    SendChatMessage("[Parsec] " .. viewLabel .. " (" .. segLabel .. ") " .. durText, channel)

    local count = math.min(table.getn(sorted), 5)
    for i = 1, count do
        local entry = sorted[i]
        local pctStr = ""
        if raidTotal > 0 then
            pctStr = string.format(" (%.1f%%)", (entry.value / raidTotal) * 100)
        end
        local valStr
        if pc.viewType == "dps" or pc.viewType == "hps" then
            valStr = string.format("%.1f", entry.value)
        else
            valStr = P.FormatNumber(entry.value)
        end
        SendChatMessage(i .. ". " .. entry.name .. " - " .. valStr .. pctStr, channel)
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

    -- Title text
    f.titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.titleText:SetPoint("LEFT", f.titleBG, "LEFT", 4, 0)
    f.titleText:SetPoint("RIGHT", menuBtn, "LEFT", -4, 0)
    f.titleText:SetTextColor(0, 0.8, 1)
    f.titleText:SetJustifyH("LEFT")

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

    -- OnUpdate for live refresh
    f:SetScript("OnUpdate", function()
        local dt = arg1 or 0.016
        this.pc.updateTimer = this.pc.updateTimer + dt
        if this.pc.updateTimer >= UPDATE_INTERVAL then
            this.pc.updateTimer = 0
            P.UpdateParsecWindow(this)
        end
    end)

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
            table.insert(saved, {
                viewType = pc.viewType,
                segment = pc.segment,
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
