-- Parsec: Shared utilities
-- Class colors, formatting, helpers

Parsec = {}
local P = Parsec

P.VERSION = "0.1.0"
P._loadedFiles = { "utils" }

-- Class colors (same as RAID_CLASS_COLORS but guaranteed available)
P.CLASS_COLORS = {
    ["WARRIOR"]     = { r = 0.78, g = 0.61, b = 0.43 },
    ["MAGE"]        = { r = 0.41, g = 0.80, b = 0.94 },
    ["ROGUE"]       = { r = 1.00, g = 0.96, b = 0.41 },
    ["DRUID"]       = { r = 1.00, g = 0.49, b = 0.04 },
    ["HUNTER"]      = { r = 0.67, g = 0.83, b = 0.45 },
    ["SHAMAN"]      = { r = 0.00, g = 0.44, b = 0.87 },
    ["PRIEST"]      = { r = 1.00, g = 1.00, b = 1.00 },
    ["WARLOCK"]     = { r = 0.58, g = 0.51, b = 0.79 },
    ["PALADIN"]     = { r = 0.96, g = 0.55, b = 0.73 },
}

P.CLASS_COLORS_UNKNOWN = { r = 0.6, g = 0.6, b = 0.6 }

-- Damage school colors
P.SCHOOL_COLORS = {
    [0] = { r = 1.0, g = 1.0, b = 0.0 },  -- Physical
    [1] = { r = 1.0, g = 0.9, b = 0.5 },  -- Holy
    [2] = { r = 1.0, g = 0.5, b = 0.0 },  -- Fire
    [3] = { r = 0.3, g = 1.0, b = 0.3 },  -- Nature
    [4] = { r = 0.5, g = 0.8, b = 1.0 },  -- Frost
    [5] = { r = 0.6, g = 0.3, b = 0.8 },  -- Shadow
    [6] = { r = 1.0, g = 0.5, b = 1.0 },  -- Arcane
}

-- Format large numbers: 1234567 -> "1.23M", 12345 -> "12.3k"
function P.FormatNumber(n)
    if not n then return "0" end
    return string.format("%d", n)
end

-- Format time: 65.3 -> "1:05"
function P.FormatTime(seconds)
    if not seconds or seconds <= 0 then return "0:00" end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds - m * 60)
    return string.format("%d:%02d", m, s)
end

-- Format percentage
function P.FormatPct(value, total)
    if not total or total == 0 then return "0%" end
    return string.format("%.1f%%", (value / total) * 100)
end

-- Get class color for a player name
function P.GetClassColor(name)
    local class = P.dataStore and P.dataStore.classes[name]
    if class and P.CLASS_COLORS[class] then
        return P.CLASS_COLORS[class]
    end
    return P.CLASS_COLORS_UNKNOWN
end

-- Deterministic color from string hash (for unknown classes)
function P.HashColor(name)
    if not name then return P.CLASS_COLORS_UNKNOWN end
    local hash = 0
    for i = 1, string.len(name) do
        hash = hash + string.byte(name, i) * (i * 17)
    end
    local r = math.mod(hash, 255) / 255
    local g = math.mod(hash * 7, 255) / 255
    local b = math.mod(hash * 13, 255) / 255
    -- Brighten: ensure minimum brightness
    local minBright = 0.3
    r = minBright + r * (1 - minBright)
    g = minBright + g * (1 - minBright)
    b = minBright + b * (1 - minBright)
    return { r = r, g = g, b = b }
end

-- Print to default chat frame
function P.Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[Parsec]|r " .. (msg or "nil"))
    end
end

-- Print debug message (only when debug mode on)
function P.Debug(msg)
    if P.debugMode then
        P.Print("|cff888888" .. (msg or "nil") .. "|r")
    end
end

-- Scan raid/party for player classes
function P.ScanGroupClasses()
    if not P.dataStore then return end
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()

    if numRaid > 0 then
        for i = 1, numRaid do
            local name, _, _, _, _, class = GetRaidRosterInfo(i)
            if name and class then
                P.dataStore.classes[name] = string.upper(class)
            end
        end
    elseif numParty > 0 then
        for i = 1, numParty do
            local unit = "party" .. i
            local name = UnitName(unit)
            if name then
                local _, class = UnitClass(unit)
                if class then
                    P.dataStore.classes[name] = class
                end
            end
        end
    end

    -- Always add self
    local playerName = UnitName("player")
    if playerName then
        local _, playerClass = UnitClass("player")
        if playerClass then
            P.dataStore.classes[playerName] = playerClass
        end
    end
end

-- Resolve pet owner name via SuperWoW
function P.GetPetOwner(petName)
    if not petName then return nil end
    -- SuperWoW adds "(OwnerName)" to pet names
    local owner = string.gfind(petName, "%((.+)%)")()
    return owner
end

-- Group member tracking (for NPC/faction filtering)
P.groupMembers = {}

function P.ScanGroupMembers()
    P.groupMembers = {}
    local playerName = UnitName("player")
    if playerName then
        P.groupMembers[playerName] = true
    end
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i = 1, numRaid do
            local name = GetRaidRosterInfo(i)
            if name then
                P.groupMembers[name] = true
            end
        end
    else
        local numParty = GetNumPartyMembers()
        for i = 1, numParty do
            local name = UnitName("party" .. i)
            if name then
                P.groupMembers[name] = true
            end
        end
    end
end

function P.IsGroupMember(name)
    return P.groupMembers[name] == true
end

-- Format duration for title bar: [24.0s] or [1:24]
function P.FormatDuration(seconds)
    if not seconds or seconds <= 0 then return "[0.0s]" end
    if seconds < 60 then
        return "[" .. string.format("%.1f", seconds) .. "s]"
    else
        local m = math.floor(seconds / 60)
        local s = math.floor(seconds - m * 60)
        return "[" .. string.format("%d:%02d", m, s) .. "]"
    end
end
