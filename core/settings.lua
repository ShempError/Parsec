-- Parsec: Settings
-- Centralized settings management via ParsecCharDB

local P = Parsec
if not P then return end

table.insert(P._loadedFiles, "settings")

---------------------------------------------------------------------------
-- Defaults
---------------------------------------------------------------------------

P.DEFAULTS = {
    autoShow     = false,
    autoHide     = false,
    lockWindows  = false,
    showMinimap  = true,
    bgOpacity    = 0.8,
    mergePets    = true,
    trackAll     = false,
    barHeight    = 14,
    barSpacing   = 1,
    barTexture   = 1,
    fontShadow   = true,
    fontOutline  = false,
    pastelColors = false,
    showBackdrop = true,
}

P.settings = {}

---------------------------------------------------------------------------
-- Bar Textures
---------------------------------------------------------------------------

P.BAR_TEXTURES = {
    "Interface\\AddOns\\Parsec\\textures\\bar-solid",
    "Interface\\AddOns\\Parsec\\textures\\bar-gradient",
    "Interface\\AddOns\\Parsec\\textures\\bar-striped",
    "Interface\\AddOns\\Parsec\\textures\\bar-glossy",
    "Interface\\AddOns\\Parsec\\textures\\bar-smooth",
    "Interface\\AddOns\\Parsec\\textures\\bar-flat",
    "Interface\\AddOns\\Parsec\\textures\\bar-ember",
    "Interface\\AddOns\\Parsec\\textures\\bar-rain",
}

P.BAR_TEXTURE_NAMES = {
    "Solid",
    "Gradient",
    "Striped",
    "Glossy",
    "Smooth",
    "Flat",
    "Ember",
    "Rain",
}

---------------------------------------------------------------------------
-- Pastel Class Colors (softer versions of standard)
---------------------------------------------------------------------------

P.CLASS_COLORS_PASTEL = {
    WARRIOR     = { r = 0.78, g = 0.61, b = 0.43 },
    PALADIN     = { r = 0.96, g = 0.55, b = 0.73 },
    HUNTER      = { r = 0.67, g = 0.83, b = 0.45 },
    ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },
    PRIEST      = { r = 0.90, g = 0.90, b = 0.90 },
    SHAMAN      = { r = 0.36, g = 0.54, b = 0.96 },
    MAGE        = { r = 0.56, g = 0.78, b = 0.96 },
    WARLOCK     = { r = 0.68, g = 0.58, b = 0.86 },
    DRUID       = { r = 1.00, g = 0.68, b = 0.46 },
}

---------------------------------------------------------------------------
-- Get class color (respects pastelColors setting)
---------------------------------------------------------------------------

function P.GetClassColor(name)
    local class = P.dataStore and P.dataStore.classes and P.dataStore.classes[name]

    -- Fallback: try UnitClass for group members not yet cached
    if not class and name then
        local units = { "player", "target", "party1", "party2", "party3", "party4" }
        for i = 1, table.getn(units) do
            if UnitName(units[i]) == name then
                local _, uClass = UnitClass(units[i])
                if uClass then
                    class = uClass
                    if P.dataStore and P.dataStore.classes then
                        P.dataStore.classes[name] = class
                    end
                end
                break
            end
        end
    end

    if not class then
        return P.HashColor(name)
    end
    if P.settings.pastelColors and P.CLASS_COLORS_PASTEL[class] then
        return P.CLASS_COLORS_PASTEL[class]
    end
    return P.CLASS_COLORS[class] or P.HashColor(name)
end

---------------------------------------------------------------------------
-- Load: merge saved settings with defaults
---------------------------------------------------------------------------

function P.LoadSettings()
    if not ParsecCharDB then
        ParsecCharDB = {}
    end
    if not ParsecCharDB.settings then
        ParsecCharDB.settings = {}
    end

    -- Copy defaults, then overlay saved values
    for k, v in pairs(P.DEFAULTS) do
        if ParsecCharDB.settings[k] ~= nil then
            P.settings[k] = ParsecCharDB.settings[k]
        else
            P.settings[k] = v
        end
    end

    -- Migrate fontShadow: number (brief v0.3.x) -> boolean
    if type(P.settings.fontShadow) == "number" then
        P.settings.fontShadow = P.settings.fontShadow > 0
    end
end

---------------------------------------------------------------------------
-- Save: write current settings to SavedVariables
---------------------------------------------------------------------------

function P.SaveSettings()
    if not ParsecCharDB then
        ParsecCharDB = {}
    end
    ParsecCharDB.settings = {}
    for k, v in pairs(P.settings) do
        ParsecCharDB.settings[k] = v
    end
end

---------------------------------------------------------------------------
-- Apply: enforce all settings on live UI
---------------------------------------------------------------------------

function P.ApplySettings()
    local s = P.settings
    local numWin = table.getn(P.windows)

    for i = 1, numWin do
        local f = P.windows[i]

        -- Lock windows
        f:SetMovable(not s.lockWindows)

        -- Background opacity + backdrop visibility
        if s.showBackdrop then
            f:SetBackdropColor(1, 1, 1, s.bgOpacity)
            f:SetBackdropBorderColor(1, 1, 1, s.bgOpacity)
        else
            f:SetBackdropColor(0, 0, 0, 0)
            f:SetBackdropBorderColor(0, 0, 0, 0)
        end

        -- Bar texture + height + spacing + font shadow
        if f.pc and f.pc.bars then
            local texPath = P.BAR_TEXTURES[s.barTexture] or P.BAR_TEXTURES[1]
            local shadowA = s.fontShadow and 1 or 0
            local shadowOff = s.fontShadow and 1 or 0
            local outlineFlag = s.fontOutline and "OUTLINE" or ""
            for j = 1, table.getn(f.pc.bars) do
                local bar = f.pc.bars[j]
                bar:SetStatusBarTexture(texPath)
                if bar.bg then bar.bg:SetTexture(texPath) end
                bar:SetHeight(s.barHeight)
                -- Font outline + shadow on all three FontStrings
                local fontStrings = { bar.rank, bar.name, bar.value }
                for k = 1, 3 do
                    local fs = fontStrings[k]
                    if fs then
                        local fontPath, fontSize = fs:GetFont()
                        if fontPath then
                            fs:SetFont(fontPath, fontSize, outlineFlag)
                        end
                        fs:SetShadowColor(0, 0, 0, shadowA)
                        fs:SetShadowOffset(shadowOff, -shadowOff)
                    end
                end
            end
        end
    end

    -- Minimap button visibility
    if ParsecMinimapButton then
        if s.showMinimap then
            ParsecMinimapButton:Show()
        else
            ParsecMinimapButton:Hide()
        end
    end

    -- Force window update to refresh colors
    if P.UpdateAllWindows then
        P.UpdateAllWindows()
    end

    -- Refresh options texture preview (if visible)
    if P._refreshTexturePreview then
        P._refreshTexturePreview()
    end
end
