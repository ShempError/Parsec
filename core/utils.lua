-- Parsec: Shared utilities
-- Class colors, formatting, helpers

---------------------------------------------------------------------------
-- Nampower v3.0.0 compat: UnitGUID was renamed to GetUnitGUID
---------------------------------------------------------------------------
if not UnitGUID and GetUnitGUID then
    UnitGUID = GetUnitGUID
end

Parsec = {}
local P = Parsec

P.VERSION = "0.5.3.3"
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

-- Message log buffer for debug panel (copy-paste)
P.messageLog = {}
P.MESSAGE_LOG_MAX = 500

local function StripColors(str)
    if not str then return "" end
    str = string.gsub(str, "|c%x%x%x%x%x%x%x%x", "")
    str = string.gsub(str, "|r", "")
    return str
end

-- Print to default chat frame + log buffer
function P.Print(msg)
    local text = msg or "nil"
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[Parsec]|r " .. text)
    end
    table.insert(P.messageLog, StripColors(text))
    if table.getn(P.messageLog) > P.MESSAGE_LOG_MAX then
        table.remove(P.messageLog, 1)
    end
end

-- Debug message: only logged when debug mode on (avoids string alloc in hot path)
function P.Debug(msg)
    if not P.debugMode then return end
    local text = msg or "nil"
    table.insert(P.messageLog, "[DBG] " .. StripColors(text))
    if table.getn(P.messageLog) > P.MESSAGE_LOG_MAX then
        table.remove(P.messageLog, 1)
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[Parsec]|r |cff888888" .. text .. "|r")
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
            -- Cache GUID -> name for raid members
            if UnitGUID then
                local unit = "raid" .. i
                local guid = UnitGUID(unit)
                if guid and name and P.guidNames then
                    P.guidNames[guid] = name
                end
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
                -- Cache GUID -> name for party members
                if UnitGUID then
                    local guid = UnitGUID(unit)
                    if guid and P.guidNames then
                        P.guidNames[guid] = name
                    end
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
        -- Cache player GUID
        if UnitGUID and P.guidNames then
            local playerGUID = UnitGUID("player")
            if playerGUID then
                P.guidNames[playerGUID] = playerName
            end
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
    if not name then return false end
    if P.groupMembers[name] then return true end
    -- Fallback: always consider the player a group member
    if name == UnitName("player") then return true end
    return false
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
