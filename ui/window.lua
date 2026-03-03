-- Parsec: Window UI
-- Bar display, sorting, view switching, tooltips

local P = Parsec
if not P then return end

table.insert(P._loadedFiles, "window")

-- Window state
local W = {}
P.window = W

W.viewType = "damage"      -- damage, dps, healing, hps
W.segment = "current"      -- current, overall, or history index
W.bars = {}                -- created bar frames
W.maxBars = 20
W.barHeight = 14
W.barSpacing = 1
W.updateInterval = 0.5
W.updateTimer = 0
W.scrollOffset = 0

-- View labels
local VIEW_LABELS = {
    damage = "Damage",
    dps = "DPS",
    healing = "Healing",
    hps = "HPS",
}

---------------------------------------------------------------------------
-- Bar Management
---------------------------------------------------------------------------

local function CreateBar(parent, index)
    local bar = CreateFrame("StatusBar", "ParsecBar" .. index, parent)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetHeight(W.barHeight)
    bar:EnableMouse(true)

    -- Background
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar.bg:SetAllPoints(bar)
    bar.bg:SetVertexColor(0.1, 0.1, 0.1, 0.6)

    -- Rank number
    bar.rank = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.rank:SetPoint("LEFT", bar, "LEFT", 2, 0)
    bar.rank:SetWidth(14)
    bar.rank:SetJustifyH("RIGHT")
    bar.rank:SetTextColor(0.6, 0.6, 0.6)

    -- Name text
    bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.name:SetPoint("LEFT", bar.rank, "RIGHT", 2, 0)
    bar.name:SetJustifyH("LEFT")

    -- Value text
    bar.value = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.value:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    bar.value:SetJustifyH("RIGHT")
    bar.value:SetTextColor(1, 1, 1)

    -- Set name width (needs to leave room for value)
    bar.name:SetPoint("RIGHT", bar.value, "LEFT", -4, 0)

    -- Tooltip on hover
    bar:SetScript("OnEnter", function()
        P.ShowBarTooltip(bar)
    end)
    bar:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    bar.index = index
    bar.playerName = nil
    bar.playerData = nil

    return bar
end

local function GetBar(index)
    if not W.bars[index] then
        W.bars[index] = CreateBar(ParsecBarContainer, index)
    end
    return W.bars[index]
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

function P.ShowBarTooltip(bar)
    if not bar.playerName or not bar.playerData then return end
    local data = bar.playerData
    local name = bar.playerName

    GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    -- Header: player name with class color
    local cc = P.GetClassColor(name)
    GameTooltip:AddLine(name, cc.r, cc.g, cc.b)

    local ds = P.dataStore
    local seg = P.GetActiveSegment()
    local _, duration = ds:GetSorted(W.viewType, seg)

    if W.viewType == "damage" or W.viewType == "dps" then
        -- Total damage
        GameTooltip:AddDoubleLine("Total Damage:", P.FormatNumber(data.damage_total), 1, 0.82, 0, 1, 1, 1)
        local playerDur = data.last_action - data.first_action
        if playerDur < 1 then playerDur = duration end
        GameTooltip:AddDoubleLine("DPS:", string.format("%.1f", data.damage_total / playerDur), 1, 0.82, 0, 1, 1, 1)
        GameTooltip:AddLine(" ")

        -- Per-spell breakdown (sorted by total)
        local spells = {}
        for spellName, sp in pairs(data.damage_spells) do
            table.insert(spells, { name = spellName, data = sp })
        end
        table.sort(spells, function(a, b) return a.data.total > b.data.total end)

        for i = 1, math.min(table.getn(spells), 10) do
            local sp = spells[i]
            local pct = P.FormatPct(sp.data.total, data.damage_total)
            local avg = 0
            if sp.data.hits > 0 then avg = sp.data.total / sp.data.hits end
            local critPct = ""
            if sp.data.hits > 0 then
                critPct = string.format(" (%.0f%% crit)", (sp.data.crits / sp.data.hits) * 100)
            end
            GameTooltip:AddDoubleLine(
                sp.name .. critPct,
                P.FormatNumber(sp.data.total) .. " - " .. pct,
                1, 1, 1,
                0.8, 0.8, 0.8
            )
        end
    else
        -- Healing view
        GameTooltip:AddDoubleLine("Total Healing:", P.FormatNumber(data.heal_total), 0.2, 1, 0.2, 1, 1, 1)
        GameTooltip:AddDoubleLine("Effective:", P.FormatNumber(data.heal_effective), 0.2, 1, 0.2, 1, 1, 1)
        GameTooltip:AddDoubleLine("Overhealing:", P.FormatNumber(data.heal_overheal) .. " (" .. P.FormatPct(data.heal_overheal, data.heal_total) .. ")", 1, 0.5, 0, 1, 1, 1)
        local playerDur = data.last_action - data.first_action
        if playerDur < 1 then playerDur = duration end
        GameTooltip:AddDoubleLine("HPS:", string.format("%.1f", data.heal_effective / playerDur), 0.2, 1, 0.2, 1, 1, 1)
        GameTooltip:AddLine(" ")

        -- Per-spell breakdown
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
                1, 1, 1,
                0.8, 0.8, 0.8
            )
        end
    end

    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Segment Selection
---------------------------------------------------------------------------

function P.GetActiveSegment()
    if W.segment == "current" then
        return P.dataStore.current
    elseif W.segment == "overall" then
        return P.dataStore.overall
    else
        -- Numeric = history index
        local idx = tonumber(W.segment)
        if idx and P.dataStore.history[idx] then
            return P.dataStore.history[idx]
        end
        return P.dataStore.current
    end
end

---------------------------------------------------------------------------
-- Update Display
---------------------------------------------------------------------------

function P.UpdateWindow()
    if not ParsecWindow or not ParsecWindow:IsVisible() then return end
    local ds = P.dataStore
    if not ds then return end

    local seg = P.GetActiveSegment()
    local sorted, duration = ds:GetSorted(W.viewType, seg)

    -- Update title
    local viewLabel = VIEW_LABELS[W.viewType] or "Damage"
    ParsecWindowTitle:SetText("Parsec - " .. viewLabel)

    -- Update segment label
    ParsecWindowSegment:SetText(seg.name or "Current")

    -- Calculate bar dimensions
    local containerWidth = ParsecBarContainer:GetWidth()
    local totalEntries = table.getn(sorted)

    -- Total value for percentage bars
    local totalValue = 0
    if totalEntries > 0 then
        totalValue = sorted[1].value  -- top player = 100%
    end

    -- Layout bars
    local visibleBars = 0
    for i = 1, math.min(totalEntries, W.maxBars) do
        local entry = sorted[i + W.scrollOffset]
        if not entry then break end

        visibleBars = visibleBars + 1
        local bar = GetBar(visibleBars)

        -- Position
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", ParsecBarContainer, "TOPLEFT", 0, -((visibleBars - 1) * (W.barHeight + W.barSpacing)))
        bar:SetPoint("RIGHT", ParsecBarContainer, "RIGHT", 0, 0)

        -- Color from class
        local cc = P.GetClassColor(entry.name)
        bar:SetStatusBarColor(cc.r, cc.g, cc.b, 0.85)

        -- Fill percentage (relative to top player)
        local pct = 0
        if totalValue > 0 then pct = entry.value / totalValue end
        bar:SetValue(pct)

        -- Rank
        bar.rank:SetText(i + W.scrollOffset)

        -- Name
        bar.name:SetText(entry.name)
        bar.name:SetTextColor(cc.r, cc.g, cc.b)

        -- Value text
        local valueText = ""
        if W.viewType == "damage" then
            valueText = P.FormatNumber(entry.value)
        elseif W.viewType == "dps" then
            valueText = string.format("%.1f", entry.value)
        elseif W.viewType == "healing" then
            valueText = P.FormatNumber(entry.value)
        elseif W.viewType == "hps" then
            valueText = string.format("%.1f", entry.value)
        end
        bar.value:SetText(valueText)

        -- Store reference for tooltip
        bar.playerName = entry.name
        bar.playerData = entry.raw

        bar:Show()
    end

    -- Hide unused bars
    for i = visibleBars + 1, table.getn(W.bars) do
        if W.bars[i] then
            W.bars[i]:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- View / Segment Cycling
---------------------------------------------------------------------------

function P.CycleView()
    local views = { "damage", "dps", "healing", "hps" }
    for i = 1, table.getn(views) do
        if views[i] == W.viewType then
            W.viewType = views[(i % table.getn(views)) + 1]
            P.UpdateWindow()
            return
        end
    end
    W.viewType = "damage"
    P.UpdateWindow()
end

function P.CycleSegment()
    if W.segment == "current" then
        W.segment = "overall"
    elseif W.segment == "overall" then
        if table.getn(P.dataStore.history) > 0 then
            W.segment = "1"
        else
            W.segment = "current"
        end
    else
        local idx = (tonumber(W.segment) or 0) + 1
        if idx > table.getn(P.dataStore.history) then
            W.segment = "current"
        else
            W.segment = tostring(idx)
        end
    end
    P.UpdateWindow()
end

---------------------------------------------------------------------------
-- Window Resize Handler
---------------------------------------------------------------------------

function P.OnWindowResize()
    if not ParsecWindow then return end
    -- Recalculate bar container size
    local w = ParsecWindow:GetWidth()
    local h = ParsecWindow:GetHeight()
    ParsecBarContainer:SetWidth(w - 8)
    ParsecBarContainer:SetHeight(h - 28)
    ParsecWindowTitleBG:SetWidth(w - 8)
    P.UpdateWindow()
end

---------------------------------------------------------------------------
-- Toggle / Show / Hide
---------------------------------------------------------------------------

function P.ToggleWindow()
    if not ParsecWindow then
        P.Print("|cffff4444ParsecWindow frame not found!|r")
        return
    end
    if ParsecWindow:IsVisible() then
        ParsecWindow:Hide()
    else
        ParsecWindow:Show()
        P.UpdateWindow()
    end
end

---------------------------------------------------------------------------
-- OnUpdate Timer for Live Refresh
---------------------------------------------------------------------------

if ParsecWindow then
    ParsecWindow:SetScript("OnUpdate", function()
        local dt = arg1 or 0.016
        W.updateTimer = W.updateTimer + dt
        if W.updateTimer >= W.updateInterval then
            W.updateTimer = 0
            P.UpdateWindow()
        end
    end)

    -- Title bar right-click = cycle view, middle-click = cycle segment
    ParsecWindow:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then
            ParsecWindow:StartMoving()
        elseif arg1 == "RightButton" then
            P.CycleView()
        elseif arg1 == "MiddleButton" then
            P.CycleSegment()
        end
    end)

    -- Scroll wheel = scroll bar list
    ParsecWindow:EnableMouseWheel(true)
    ParsecWindow:SetScript("OnMouseWheel", function()
        -- arg1: 1 = up, -1 = down
        W.scrollOffset = W.scrollOffset - (arg1 or 0)
        if W.scrollOffset < 0 then W.scrollOffset = 0 end
        P.UpdateWindow()
    end)

    -- Set resize bounds
    ParsecWindow:SetMinResize(150, 80)
    ParsecWindow:SetMaxResize(400, 600)
end
