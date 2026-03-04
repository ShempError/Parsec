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
local VIEW_CYCLE = { "damage", "healing", "dps", "hps" }
local VIEW_LABELS = {
    damage  = "Damage",
    healing = "Healing",
    dps     = "DPS",
    hps     = "HPS",
}
local SEGMENT_LABELS = {
    current = "Current",
    overall = "Overall",
}

local WINDOW_DEFS = {
    { viewType = "damage",  segment = "current", title = "Damage" },
    { viewType = "healing", segment = "current", title = "Healing" },
    { viewType = "dps",     segment = "current", title = "DPS" },
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
    bar.value:SetTextColor(1, 1, 1)
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
-- Title bar icon button helper
---------------------------------------------------------------------------

local function CreateTitleButton(parent, iconPath, tooltip, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(14)
    btn:SetHeight(14)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetTexture(iconPath)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(btn)
    hl:SetTexture(1, 1, 1, 0.2)

    local capturedTip = tooltip
    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(capturedTip, 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", onClick)

    return btn
end

---------------------------------------------------------------------------
-- Cycle view type for a window
---------------------------------------------------------------------------

local function CycleView(frame)
    local pc = frame.pc
    local cur = pc.viewType
    local nextIdx = 1
    for i = 1, table.getn(VIEW_CYCLE) do
        if VIEW_CYCLE[i] == cur then
            nextIdx = i + 1
            if nextIdx > table.getn(VIEW_CYCLE) then nextIdx = 1 end
            break
        end
    end
    pc.viewType = VIEW_CYCLE[nextIdx]
    pc.scrollOffset = 0
    P.UpdateWindowTitle(frame)
    P.UpdateParsecWindow(frame)
end

---------------------------------------------------------------------------
-- Toggle segment for a window
---------------------------------------------------------------------------

local function ToggleSegment(frame)
    local pc = frame.pc
    if pc.segment == "current" then
        pc.segment = "overall"
    else
        pc.segment = "current"
    end
    pc.scrollOffset = 0
    P.UpdateWindowTitle(frame)
    P.UpdateParsecWindow(frame)
end

---------------------------------------------------------------------------
-- Update window title text
---------------------------------------------------------------------------

function P.UpdateWindowTitle(frame)
    local pc = frame.pc
    if not pc then return end
    local viewLabel = VIEW_LABELS[pc.viewType] or pc.viewType
    local segLabel = SEGMENT_LABELS[pc.segment] or pc.segment
    local duration = P.combatState:GetDuration(pc.segment)
    local durText = P.FormatDuration(duration)
    frame.titleText:SetText(viewLabel .. " (" .. segLabel .. ") " .. durText)
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
    totalBar:SetStatusBarColor(0.4, 0.4, 0.4, 0.85)
    totalBar:SetValue(1)
    totalBar.rank:SetText("")
    totalBar.name:SetText("Total")
    totalBar.name:SetTextColor(1, 1, 1)

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
        bar:SetStatusBarColor(cc.r, cc.g, cc.b, 0.85)

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

function P.Announce(frame)
    if not frame or not frame.pc then return end
    local pc = frame.pc
    local ds = P.dataStore
    if not ds then return end

    local sorted, duration, raidTotal = ds:GetSorted(pc.viewType, pc.segment)
    if table.getn(sorted) == 0 then
        P.Print("Nothing to announce.")
        return
    end

    -- Determine channel
    local channel = nil
    if GetNumRaidMembers() > 0 then
        channel = "RAID"
    elseif GetNumPartyMembers() > 0 then
        channel = "PARTY"
    else
        channel = "SAY"
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
end

function P.ShowAllWindows()
    for i = 1, table.getn(P.windows) do
        P.windows[i]:Show()
        P.UpdateParsecWindow(P.windows[i])
    end
end

function P.HideAllWindows()
    for i = 1, table.getn(P.windows) do
        P.windows[i]:Hide()
    end
end

---------------------------------------------------------------------------
-- Create all windows
---------------------------------------------------------------------------

local TEX_PATH = "Interface\\AddOns\\Parsec\\textures\\"

local numWindows = table.getn(WINDOW_DEFS)
for idx = 1, numWindows do
    local def = WINDOW_DEFS[idx]

    local f = CreateFrame("Frame", "ParsecWin" .. idx, UIParent)
    f:SetWidth(220)
    f:SetHeight(200)
    f:SetPoint("CENTER", UIParent, "CENTER", (idx - (numWindows + 1) / 2) * 230, 0)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.8)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetToplevel(true)
    f:SetMinResize(150, 80)
    f:SetMaxResize(400, 600)
    f:Hide()

    -- Capture loop variable for closures
    local capturedDef = def

    f.pc = {
        viewType = def.viewType,
        segment = def.segment or "current",
        title = def.title,
        bars = {},
        scrollOffset = 0,
        updateTimer = 0,
    }

    -- Title bar background (banner-style)
    f.titleBG = f:CreateTexture(nil, "ARTWORK")
    f.titleBG:SetTexture(TEX_PATH .. "banner")
    f.titleBG:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    f.titleBG:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    f.titleBG:SetHeight(20)

    -- Title text
    f.titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.titleText:SetPoint("LEFT", f.titleBG, "LEFT", 4, 0)
    f.titleText:SetTextColor(0, 0.8, 1)
    f.titleText:SetText(def.title .. " (Current) [0.0s]")

    -- Title bar buttons (right-aligned, 14x14 each)
    -- Close button (custom, not UIPanelCloseButton)
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetWidth(14)
    closeBtn:SetHeight(14)
    closeBtn:SetPoint("RIGHT", f.titleBG, "RIGHT", -2, 0)
    local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeTxt:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    closeTxt:SetText("X")
    closeTxt:SetTextColor(0.6, 0.6, 0.6)
    closeBtn:SetScript("OnEnter", function()
        closeTxt:SetTextColor(1, 0.3, 0.3)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeTxt:SetTextColor(0.6, 0.6, 0.6)
    end)
    closeBtn:SetScript("OnClick", function()
        this:GetParent():Hide()
    end)

    -- Segment toggle button
    local segBtn = CreateTitleButton(f, TEX_PATH .. "icon-segment-current", "Toggle: Current / Overall", function()
        ToggleSegment(this:GetParent())
    end)
    segBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)

    -- View cycle button
    local viewBtn = CreateTitleButton(f, TEX_PATH .. "icon-view-damage", "Cycle view: Damage > Healing > DPS > HPS", function()
        CycleView(this:GetParent())
    end)
    viewBtn:SetPoint("RIGHT", segBtn, "LEFT", -2, 0)

    -- Announce button
    local annBtn = CreateTitleButton(f, TEX_PATH .. "icon-announce", "Announce to chat", function()
        P.Announce(this:GetParent())
    end)
    annBtn:SetPoint("RIGHT", viewBtn, "LEFT", -2, 0)

    -- Reset button
    local rstBtn = CreateTitleButton(f, TEX_PATH .. "icon-reset", "Reset all data", function()
        P.ResetData()
    end)
    rstBtn:SetPoint("RIGHT", annBtn, "LEFT", -2, 0)

    -- Settings button
    local optBtn = CreateTitleButton(f, TEX_PATH .. "icon-settings", "Open options", function()
        P.ToggleOptions()
    end)
    optBtn:SetPoint("RIGHT", rstBtn, "LEFT", -2, 0)

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
    end)

    -- Drag to move
    f:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" and not (P.settings and P.settings.lockWindows) then
            this:StartMoving()
        end
    end)
    f:SetScript("OnMouseUp", function()
        this:StopMovingOrSizing()
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
end
