-- Parsec: Window UI
-- 3 fixed-view windows: Damage, Healing, Effective Healing
-- All frames created in Lua (no XML dependency)

local P = Parsec
if not P then return end

table.insert(P._loadedFiles, "window")

P.windows = {}

local BAR_HEIGHT = 14
local BAR_SPACING = 1
local MAX_BARS = 20
local UPDATE_INTERVAL = 0.5

local WINDOW_DEFS = {
    { viewType = "damage",  title = "Damage" },
    { viewType = "healing", title = "Healing" },
    { viewType = "effheal", title = "Eff. Healing" },
}

---------------------------------------------------------------------------
-- Bar Creation
---------------------------------------------------------------------------

local function CreateBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetHeight(BAR_HEIGHT)
    bar:EnableMouse(true)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar.bg:SetAllPoints(bar)
    bar.bg:SetVertexColor(0.1, 0.1, 0.1, 0.6)

    bar.rank = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.rank:SetPoint("LEFT", bar, "LEFT", 2, 0)
    bar.rank:SetWidth(14)
    bar.rank:SetJustifyH("RIGHT")
    bar.rank:SetTextColor(0.6, 0.6, 0.6)

    bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.name:SetPoint("LEFT", bar.rank, "RIGHT", 2, 0)
    bar.name:SetJustifyH("LEFT")

    bar.value = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.value:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    bar.value:SetJustifyH("RIGHT")
    bar.value:SetTextColor(1, 1, 1)

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

    local duration = P.combatState:GetDuration()
    if duration < 1 then duration = 1 end

    if vt == "damage" then
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
        -- healing or effheal
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
-- Update a single window
---------------------------------------------------------------------------

function P.UpdateParsecWindow(frame)
    if not frame or not frame:IsVisible() then return end
    local pc = frame.pc
    if not pc then return end
    local ds = P.dataStore
    if not ds then return end

    local sorted, duration, raidTotal = ds:GetSorted(pc.viewType)

    -- Update title with duration
    local durText = P.FormatDuration(duration)
    frame.titleText:SetText(pc.title .. " " .. durText)

    local totalEntries = table.getn(sorted)

    -- Top value for bar fill (relative to #1 player)
    local topValue = 0
    if totalEntries > 0 then
        topValue = sorted[1].value
    end

    local visibleBars = 0
    local yOffset = 0

    -- Total bar (always slot 1)
    local totalBar = GetBar(frame, 1)
    totalBar:ClearAllPoints()
    totalBar:SetPoint("TOPLEFT", frame.container, "TOPLEFT", 0, 0)
    totalBar:SetPoint("RIGHT", frame.container, "RIGHT", 0, 0)
    totalBar:SetStatusBarColor(0.4, 0.4, 0.4, 0.85)
    totalBar:SetValue(1)
    totalBar.rank:SetText("")
    totalBar.name:SetText("Total")
    totalBar.name:SetTextColor(1, 1, 1)
    totalBar.value:SetText(P.FormatNumber(raidTotal))
    totalBar.playerName = nil
    totalBar.playerData = nil
    totalBar:Show()
    visibleBars = 1
    yOffset = BAR_HEIGHT + BAR_SPACING

    -- Calculate how many bars fit in the container
    local containerH = frame.container:GetHeight()
    local maxVisible = math.floor((containerH - yOffset) / (BAR_HEIGHT + BAR_SPACING))
    if maxVisible < 0 then maxVisible = 0 end

    -- Player bars
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

        local cc = P.GetClassColor(entry.name)
        bar:SetStatusBarColor(cc.r, cc.g, cc.b, 0.85)

        local pct = 0
        if topValue > 0 then pct = entry.value / topValue end
        bar:SetValue(pct)

        bar.rank:SetText(entryIdx)
        bar.name:SetText(entry.name)
        bar.name:SetTextColor(cc.r, cc.g, cc.b)

        -- Value + percentage of raid total
        local pctOfTotal = ""
        if raidTotal > 0 then
            pctOfTotal = " (" .. string.format("%.1f%%", (entry.value / raidTotal) * 100) .. ")"
        end
        bar.value:SetText(P.FormatNumber(entry.value) .. pctOfTotal)

        bar.playerName = entry.name
        bar.playerData = entry.raw
        bar.viewType = pc.viewType

        bar:Show()
        yOffset = yOffset + BAR_HEIGHT + BAR_SPACING
    end

    -- Hide unused bars
    for i = visibleBars + 1, table.getn(pc.bars) do
        if pc.bars[i] then
            pc.bars[i]:Hide()
        end
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
-- Window resize handler
---------------------------------------------------------------------------

function P.OnWindowResize(frame)
    if not frame then return end
    local w = frame:GetWidth()
    local h = frame:GetHeight()
    frame.titleBG:SetWidth(w - 8)
    frame.container:SetWidth(w - 8)
    frame.container:SetHeight(h - 28)
    P.UpdateParsecWindow(frame)
end

---------------------------------------------------------------------------
-- Reset data
---------------------------------------------------------------------------

function P.ResetData()
    if P.dataStore then
        P.dataStore:Reset()
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
-- Create all 3 windows
---------------------------------------------------------------------------

for idx = 1, table.getn(WINDOW_DEFS) do
    local def = WINDOW_DEFS[idx]

    local f = CreateFrame("Frame", "ParsecWin" .. idx, UIParent)
    f:SetWidth(220)
    f:SetHeight(200)
    f:SetPoint("CENTER", UIParent, "CENTER", (idx - 2) * 230, 0)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
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

    -- Store window data on frame (avoids upvalue capture in closures)
    f.pc = {
        viewType = def.viewType,
        title = def.title,
        bars = {},
        scrollOffset = 0,
        updateTimer = 0,
    }

    -- Title bar background
    f.titleBG = f:CreateTexture(nil, "BACKGROUND")
    f.titleBG:SetTexture(0.1, 0.1, 0.1, 0.8)
    f.titleBG:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    f.titleBG:SetHeight(20)
    f.titleBG:SetWidth(212)

    -- Title text
    f.titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.titleText:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -7)
    f.titleText:SetTextColor(0, 0.8, 1)
    f.titleText:SetText(def.title .. " [0.0s]")

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetWidth(20)
    close:SetHeight(20)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        this:GetParent():Hide()
    end)

    -- Reset button (small "R")
    local resetBtn = CreateFrame("Button", nil, f)
    resetBtn:SetWidth(16)
    resetBtn:SetHeight(16)
    resetBtn:SetPoint("RIGHT", close, "LEFT", 0, 0)
    local resetBG = resetBtn:CreateTexture(nil, "BACKGROUND")
    resetBG:SetTexture(0.2, 0.2, 0.2, 0.6)
    resetBG:SetAllPoints(resetBtn)
    local resetHL = resetBtn:CreateTexture(nil, "HIGHLIGHT")
    resetHL:SetTexture(0.4, 0.4, 0.4, 0.4)
    resetHL:SetAllPoints(resetBtn)
    local resetText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetText:SetPoint("CENTER", resetBtn, "CENTER", 0, 0)
    resetText:SetText("R")
    resetText:SetTextColor(1, 0.3, 0.3)
    resetBtn:SetScript("OnClick", function()
        P.ResetData()
    end)
    resetBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Reset all data")
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

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
    gripTex:SetTexture("Interface\\AddOns\\Parsec\\textures\\ResizeGrip")
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
        if arg1 == "LeftButton" then
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
