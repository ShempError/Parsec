-- Parsec: Death Recap Panel
-- Visual death analysis with event timeline, HP bar, navigation
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

-- ============================================================
-- LAYOUT CONSTANTS
-- ============================================================
D.WIDTH = 520
D.HEIGHT = 440
D.PADDING = 10
D.HEADER_H = 24
D.INFO_H = 28
D.SUBINFO_H = 18
D.HPBAR_H = 20
D.ROW_H = 18
D.VISIBLE_ROWS = 12
D.NAV_H = 24

-- ============================================================
-- COLORS
-- ============================================================
D.BG_MAIN   = { 0.06, 0.06, 0.08, 0.97 }
D.CYAN      = { 0, 0.8, 1 }
D.RED       = { 1, 0.3, 0.3 }
D.GREEN     = { 0.3, 1, 0.3 }
D.YELLOW    = { 1, 0.82, 0 }
D.WHITE     = { 1, 1, 1 }
D.GRAY      = { 0.5, 0.5, 0.5 }
D.KILL_BG   = { 0.4, 0.08, 0.08, 0.6 }
D.HEAL_COLOR = { 0.2, 1, 0.2 }
D.MISS_COLOR = { 0.7, 0.7, 0.7 }

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

    -- Dragging
    f:SetScript("OnMouseDown", function()
        this:StartMoving()
    end)
    f:SetScript("OnMouseUp", function()
        this:StopMovingOrSizing()
    end)

    return f
end

---------------------------------------------------------------------------
-- Header: skull icon + "DEATH RECAP" + close button
---------------------------------------------------------------------------

local function CreateHeader(parent)
    -- Header background
    local hdr = CreateFrame("Frame", nil, parent)
    hdr:SetHeight(D.HEADER_H)
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4)
    hdr:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -4)

    local hdrBg = hdr:CreateTexture(nil, "BACKGROUND")
    hdrBg:SetAllPoints(hdr)
    hdrBg:SetTexture(0.04, 0.04, 0.06, 1)

    -- Skull icon
    local skull = hdr:CreateTexture(nil, "ARTWORK")
    skull:SetWidth(18)
    skull:SetHeight(18)
    skull:SetPoint("LEFT", hdr, "LEFT", 6, 0)
    skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")

    -- Title text
    local title = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", skull, "RIGHT", 6, 0)
    title:SetText("DEATH RECAP")
    title:SetTextColor(D.CYAN[1], D.CYAN[2], D.CYAN[3])

    -- Close button
    local closeBtn = CreateFrame("Button", nil, hdr)
    closeBtn:SetWidth(18)
    closeBtn:SetHeight(18)
    closeBtn:SetPoint("RIGHT", hdr, "RIGHT", -4, 0)
    local closeTex = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeTex:SetAllPoints(closeBtn)
    closeTex:SetText("X")
    closeTex:SetTextColor(0.8, 0.2, 0.2)
    closeBtn:SetScript("OnEnter", function()
        closeTex:SetTextColor(1, 0.4, 0.4)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeTex:SetTextColor(0.8, 0.2, 0.2)
    end)
    closeBtn:SetScript("OnClick", function()
        parent:Hide()
    end)

    return hdr
end

---------------------------------------------------------------------------
-- Player info line: name (class), killed by
---------------------------------------------------------------------------

local function CreateInfoLine(parent, anchor)
    local info = CreateFrame("Frame", nil, parent)
    info:SetHeight(D.INFO_H)
    info:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    info:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)

    -- Player name (left side)
    info.playerName = info:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    info.playerName:SetPoint("LEFT", info, "LEFT", D.PADDING, 2)
    info.playerName:SetJustifyH("LEFT")

    -- Class label (next to name)
    info.classLabel = info:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    info.classLabel:SetPoint("LEFT", info.playerName, "RIGHT", 4, -1)
    info.classLabel:SetJustifyH("LEFT")
    info.classLabel:SetTextColor(D.GRAY[1], D.GRAY[2], D.GRAY[3])

    -- Killed by (right side)
    info.killedBy = info:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    info.killedBy:SetPoint("RIGHT", info, "RIGHT", -D.PADDING, 0)
    info.killedBy:SetJustifyH("RIGHT")

    return info
end

---------------------------------------------------------------------------
-- Subinfo line: timestamp, total damage, duration, overkill
---------------------------------------------------------------------------

local function CreateSubInfoLine(parent, anchor)
    local sub = CreateFrame("Frame", nil, parent)
    sub:SetHeight(D.SUBINFO_H)
    sub:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
    sub:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, 0)

    sub.text = sub:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub.text:SetPoint("LEFT", sub, "LEFT", D.PADDING, 0)
    sub.text:SetJustifyH("LEFT")
    sub.text:SetTextColor(D.GRAY[1], D.GRAY[2], D.GRAY[3])

    return sub
end

---------------------------------------------------------------------------
-- HP bar: green/yellow/red gradient based on HP%
---------------------------------------------------------------------------

local function CreateHPBar(parent, anchor)
    local wrapper = CreateFrame("Frame", nil, parent)
    wrapper:SetHeight(D.HPBAR_H + 4)
    wrapper:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    wrapper:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)

    local bar = CreateFrame("StatusBar", nil, wrapper)
    bar:SetHeight(D.HPBAR_H)
    bar:SetPoint("TOPLEFT", wrapper, "TOPLEFT", D.PADDING, -2)
    bar:SetPoint("TOPRIGHT", wrapper, "TOPRIGHT", -D.PADDING, -2)
    bar:SetStatusBarTexture("Interface\\AddOns\\Parsec\\textures\\bar-smooth")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:SetStatusBarColor(0.2, 0.8, 0.2)

    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints(bar)
    barBg:SetTexture(0.12, 0.12, 0.12, 0.8)

    -- HP text overlay
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.text:SetTextColor(1, 1, 1)
    bar.text:SetShadowColor(0, 0, 0, 1)
    bar.text:SetShadowOffset(1, -1)

    wrapper.bar = bar
    return wrapper
end

---------------------------------------------------------------------------
-- Section header: "LAST EVENTS"
---------------------------------------------------------------------------

local function CreateSectionLabel(parent, anchor, text)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", D.PADDING, -4)
    lbl:SetText(text)
    lbl:SetTextColor(D.CYAN[1], D.CYAN[2], D.CYAN[3])
    return lbl
end

---------------------------------------------------------------------------
-- Event row: time | school color | spell (source) | amount | crit/miss
---------------------------------------------------------------------------

local function CreateEventRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(D.ROW_H)

    -- Highlight background (for killing blow)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetTexture(D.KILL_BG[1], D.KILL_BG[2], D.KILL_BG[3], 0)

    -- Time offset
    row.timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.timeText:SetPoint("LEFT", row, "LEFT", D.PADDING, 0)
    row.timeText:SetWidth(42)
    row.timeText:SetJustifyH("RIGHT")
    row.timeText:SetTextColor(D.GRAY[1], D.GRAY[2], D.GRAY[3])

    -- School color square
    row.schoolIcon = row:CreateTexture(nil, "ARTWORK")
    row.schoolIcon:SetWidth(10)
    row.schoolIcon:SetHeight(10)
    row.schoolIcon:SetPoint("LEFT", row.timeText, "RIGHT", 6, 0)
    row.schoolIcon:SetTexture(1, 1, 1, 1)

    -- Spell name + source
    row.spellText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.spellText:SetPoint("LEFT", row.schoolIcon, "RIGHT", 4, 0)
    row.spellText:SetJustifyH("LEFT")
    row.spellText:SetTextColor(1, 1, 1)

    -- Crit/miss label (right side)
    row.flagText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.flagText:SetPoint("RIGHT", row, "RIGHT", -D.PADDING, 0)
    row.flagText:SetWidth(36)
    row.flagText:SetJustifyH("RIGHT")
    row.flagText:SetTextColor(1, 0.5, 0)

    -- Amount (left of flag)
    row.amountText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.amountText:SetPoint("RIGHT", row.flagText, "LEFT", -4, 0)
    row.amountText:SetWidth(60)
    row.amountText:SetJustifyH("RIGHT")
    row.amountText:SetTextColor(1, 1, 1)

    -- Limit spell text width so it does not overlap amount
    row.spellText:SetPoint("RIGHT", row.amountText, "LEFT", -4, 0)

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

    local navBg = nav:CreateTexture(nil, "BACKGROUND")
    navBg:SetAllPoints(nav)
    navBg:SetTexture(0.04, 0.04, 0.06, 1)

    -- Prev button
    local prevBtn = CreateFrame("Button", nil, nav)
    prevBtn:SetWidth(60)
    prevBtn:SetHeight(18)
    prevBtn:SetPoint("LEFT", nav, "LEFT", D.PADDING, 0)
    local prevTex = prevBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    prevTex:SetAllPoints(prevBtn)
    prevTex:SetText("<< Prev")
    prevTex:SetTextColor(D.CYAN[1], D.CYAN[2], D.CYAN[3])
    prevBtn:SetScript("OnEnter", function()
        prevTex:SetTextColor(1, 1, 1)
    end)
    prevBtn:SetScript("OnLeave", function()
        prevTex:SetTextColor(D.CYAN[1], D.CYAN[2], D.CYAN[3])
    end)
    prevBtn:SetScript("OnClick", function()
        D:NavigatePrev()
    end)
    nav.prevBtn = prevBtn

    -- Next button
    local nextBtn = CreateFrame("Button", nil, nav)
    nextBtn:SetWidth(60)
    nextBtn:SetHeight(18)
    nextBtn:SetPoint("RIGHT", nav, "RIGHT", -D.PADDING, 0)
    local nextTex = nextBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nextTex:SetAllPoints(nextBtn)
    nextTex:SetText("Next >>")
    nextTex:SetTextColor(D.CYAN[1], D.CYAN[2], D.CYAN[3])
    nextBtn:SetScript("OnEnter", function()
        nextTex:SetTextColor(1, 1, 1)
    end)
    nextBtn:SetScript("OnLeave", function()
        nextTex:SetTextColor(D.CYAN[1], D.CYAN[2], D.CYAN[3])
    end)
    nextBtn:SetScript("OnClick", function()
        D:NavigateNext()
    end)
    nav.nextBtn = nextBtn

    -- Counter label (center)
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
    D.infoLine = CreateInfoLine(D.frame, D.header)
    D.subInfo = CreateSubInfoLine(D.frame, D.infoLine)
    D.hpBar = CreateHPBar(D.frame, D.subInfo)
    D.sectionLabel = CreateSectionLabel(D.frame, D.hpBar, "LAST EVENTS")

    -- Event rows container
    D.eventContainer = CreateFrame("Frame", nil, D.frame)
    D.eventContainer:SetPoint("TOPLEFT", D.sectionLabel, "BOTTOMLEFT", -D.PADDING, -4)
    D.eventContainer:SetPoint("RIGHT", D.frame, "RIGHT", -4, 0)
    D.eventContainer:SetHeight(D.VISIBLE_ROWS * D.ROW_H)

    -- Create event rows
    for i = 1, D.VISIBLE_ROWS do
        local row = CreateEventRow(D.eventContainer, i)
        row:SetPoint("TOPLEFT", D.eventContainer, "TOPLEFT", 0, -((i - 1) * D.ROW_H))
        row:SetPoint("RIGHT", D.eventContainer, "RIGHT", 0, 0)
        D.eventRows[i] = row
    end

    -- Mousewheel scroll on event container
    D.eventContainer:EnableMouseWheel(true)
    D.eventContainer:SetScript("OnMouseWheel", function()
        D:ScrollEvents(arg1)
    end)

    -- Also enable mousewheel on the main frame for convenience
    D.frame:EnableMouseWheel(true)
    D.frame:SetScript("OnMouseWheel", function()
        D:ScrollEvents(arg1)
    end)

    D.navBar = CreateNavBar(D.frame)

    -- Apply opacity
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
-- Populate the panel with a death record
---------------------------------------------------------------------------

function D:DisplayRecord(record)
    if not record then return end
    self.currentRecord = record
    self.scrollOffset = 0

    BuildPanel()

    -- Player name + class
    local cc = P.GetClassColor(record.name)
    self.infoLine.playerName:SetText(record.name)
    self.infoLine.playerName:SetTextColor(cc.r, cc.g, cc.b)

    local classDisplay = record.class or "UNKNOWN"
    -- Capitalize first letter only
    classDisplay = string.upper(string.sub(classDisplay, 1, 1)) ..
        string.lower(string.sub(classDisplay, 2))
    self.infoLine.classLabel:SetText("(" .. classDisplay .. ")")

    -- Killed by: school-colored spell
    local schoolColors = P.SCHOOL_COLORS or {}
    local sc = schoolColors[record.killSchool] or { r = 1, g = 0.3, b = 0.3 }
    local killText = "Killed by: |cff" ..
        string.format("%02x%02x%02x", sc.r * 255, sc.g * 255, sc.b * 255) ..
        record.killSpell .. "|r (" .. record.killedBy .. ")"
    self.infoLine.killedBy:SetText(killText)

    -- Subinfo: timestamp, damage, duration, overkill
    local parts = {}
    if record.timeFmt then
        table.insert(parts, record.timeFmt)
    end
    table.insert(parts, P.FormatNumber(record.totalDmg) .. " dmg in " ..
        string.format("%.1fs", record.duration))
    if record.overkill and record.overkill > 0 then
        table.insert(parts, "Overkill: " .. P.FormatNumber(record.overkill))
    end
    local subText = ""
    for i = 1, table.getn(parts) do
        if i > 1 then subText = subText .. "  |cff444444||  " end
        subText = subText .. "|cff888888" .. parts[i] .. "|r"
    end
    self.subInfo.text:SetText(subText)

    -- HP bar: estimate HP before killing blow
    local hpMax = record.hpMax or 0
    local hpBefore = 0
    local events = record.events or {}

    -- Find HP before killing blow from second-to-last damage event
    for i = table.getn(events), 1, -1 do
        local e = events[i]
        if e.etype == "DAMAGE" and e.amount > 0 then
            -- This is the killing blow, look at previous event hpAfter
            if i > 1 then
                local prev = events[i - 1]
                if prev.hpAfter and prev.hpAfter > 0 then
                    hpBefore = prev.hpAfter
                end
            end
            break
        end
    end

    if hpMax > 0 then
        local pct = hpBefore / hpMax
        if pct > 1 then pct = 1 end
        if pct < 0 then pct = 0 end
        self.hpBar.bar:SetValue(pct)
        -- Color: green > yellow > red
        local r, g
        if pct > 0.5 then
            r = 2 * (1 - pct)
            g = 1
        else
            r = 1
            g = 2 * pct
        end
        self.hpBar.bar:SetStatusBarColor(r, g, 0.1)
        self.hpBar.bar.text:SetText(P.FormatNumber(hpBefore) .. " / " ..
            P.FormatNumber(hpMax) .. " before killing blow")
    else
        self.hpBar.bar:SetValue(0)
        self.hpBar.bar.text:SetText("HP unknown")
    end

    -- Populate event rows
    self:UpdateEventRows()

    -- Update navigation
    self:UpdateNav()

    -- Show
    self.frame:Show()
end

---------------------------------------------------------------------------
-- Update event rows (with scroll offset)
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

            -- School color square
            local sc = schoolColors[e.school] or { r = 0.8, g = 0.8, b = 0.8 }
            if e.etype == "HEAL" then
                row.schoolIcon:SetTexture(D.HEAL_COLOR[1], D.HEAL_COLOR[2], D.HEAL_COLOR[3], 1)
            elseif e.etype == "MISS" then
                row.schoolIcon:SetTexture(D.MISS_COLOR[1], D.MISS_COLOR[2], D.MISS_COLOR[3], 1)
            else
                row.schoolIcon:SetTexture(sc.r, sc.g, sc.b, 1)
            end

            -- Spell name + source
            local spellSource = e.spell
            if e.source and e.source ~= "?" then
                spellSource = spellSource .. " (" .. e.source .. ")"
            end
            row.spellText:SetText(spellSource)

            -- Amount
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

            -- Flag text (CRIT / miss type)
            if e.etype == "MISS" then
                local missLabel = e.missType or "MISS"
                row.flagText:SetText(missLabel)
                row.flagText:SetTextColor(D.MISS_COLOR[1], D.MISS_COLOR[2], D.MISS_COLOR[3])
            elseif e.crit then
                row.flagText:SetText("CRIT")
                row.flagText:SetTextColor(1, 0.5, 0)
            else
                row.flagText:SetText("")
            end

            -- Killing blow highlight
            if eIdx == killIdx then
                row.bg:SetTexture(D.KILL_BG[1], D.KILL_BG[2], D.KILL_BG[3], D.KILL_BG[4])
                row.amountText:SetTextColor(1, 0.2, 0.2)
            else
                row.bg:SetTexture(0, 0, 0, 0)
            end

            row:Show()
        else
            row:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Scroll events
---------------------------------------------------------------------------

function D:ScrollEvents(direction)
    if not self.currentRecord then return end
    -- direction: 1 = up (scroll back), -1 = down (scroll forward)
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
    -- Deaths are newest-first, so index 1 = most recent
    -- Display as "Death X of Y" where X counts from newest
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

    -- Show all deaths (no player filter)
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

    -- Find this record in the death log to enable navigation
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
