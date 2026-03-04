-- Parsec: Minimap Button
-- Draggable minimap icon for toggling windows
-- Left-click: toggle windows | Right-drag: reposition

local P = Parsec
if not P then return end

table.insert(P._loadedFiles, "minimap-button")

local DEFAULT_ANGLE = 225  -- degrees, positions button at bottom-left
local RADIUS = 80          -- distance from minimap center

---------------------------------------------------------------------------
-- Create Button
---------------------------------------------------------------------------

local button = CreateFrame("Button", "ParsecMinimapButton", Minimap)
button:SetWidth(31)
button:SetHeight(31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)

-- Icon (custom Parsec texture)
local icon = button:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\AddOns\\Parsec\\textures\\icon")
icon:SetWidth(20)
icon:SetHeight(20)
icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)

-- Standard minimap button border
local border = button:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetWidth(56)
border:SetHeight(56)
border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

-- Highlight
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

---------------------------------------------------------------------------
-- Positioning
---------------------------------------------------------------------------

local function SetButtonPosition(angleDeg)
    local angleRad = math.rad(angleDeg)
    local x = RADIUS * math.cos(angleRad)
    local y = RADIUS * math.sin(angleRad)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Apply default position immediately
button.angle = DEFAULT_ANGLE
SetButtonPosition(DEFAULT_ANGLE)

---------------------------------------------------------------------------
-- Dragging (right-button drag to reposition)
---------------------------------------------------------------------------

button:RegisterForDrag("RightButton")
button.isDragging = false

button:SetScript("OnDragStart", function()
    this.isDragging = true
end)

button:SetScript("OnDragStop", function()
    this.isDragging = false
    -- Save final angle
    if ParsecCharDB then
        ParsecCharDB.minimapAngle = this.angle
    end
end)

button:SetScript("OnUpdate", function()
    if not this.isDragging then return end
    local mx, my = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    mx = mx / scale
    my = my / scale
    local cx, cy = Minimap:GetCenter()
    local angle = math.deg(math.atan2(my - cy, mx - cx))
    this.angle = angle
    SetButtonPosition(angle)
end)

---------------------------------------------------------------------------
-- Click: toggle windows
---------------------------------------------------------------------------

button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

button:SetScript("OnClick", function()
    if arg1 == "LeftButton" then
        P.ToggleWindow()
    elseif arg1 == "RightButton" then
        P.ToggleOptions()
    end
end)

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

button:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:AddLine("Parsec - Damage Meter")
    GameTooltip:AddLine("|cff00ccffLeft-Click:|r Toggle windows", 1, 1, 1)
    GameTooltip:AddLine("|cff00ccffRight-Click:|r Options", 1, 1, 1)
    GameTooltip:AddLine("|cff00ccffRight-Drag:|r Move button", 1, 1, 1)
    GameTooltip:Show()
end)

button:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

---------------------------------------------------------------------------
-- Load saved position on login
---------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("VARIABLES_LOADED")
loader:SetScript("OnEvent", function()
    loader:UnregisterEvent("VARIABLES_LOADED")
    if not ParsecCharDB then
        ParsecCharDB = {}
    end
    if ParsecCharDB.minimapAngle then
        button.angle = ParsecCharDB.minimapAngle
        SetButtonPosition(ParsecCharDB.minimapAngle)
    end
end)

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function P.ShowMinimapButton()
    button:Show()
end

function P.HideMinimapButton()
    button:Hide()
end
