-- Parsec: Death Module
-- Tracks damage intake on group members, creates death records on UNIT_DIED
-- Ring buffer per player, HP tracking via SuperWoW UnitHealth(guid)

local P = Parsec
if not P or not P.eventBus then return end

table.insert(P._loadedFiles, "death")

P.deathLog = {}
local DL = P.deathLog

-- Constants
DL.INTAKE_SIZE = 30
DL.MAX_RECORDS = 100

-- Data stores
DL.intake = {}
DL.current = {}
DL.overall = {}
DL.counts = {
    current = {},
    overall = {},
}

---------------------------------------------------------------------------
-- Ring Buffer Operations
---------------------------------------------------------------------------

local function GetOrCreateIntake(name)
    if not DL.intake[name] then
        DL.intake[name] = {
            buffer = {},
            maxSize = DL.INTAKE_SIZE,
            idx = 0,
            count = 0,
        }
    end
    return DL.intake[name]
end

local function PushIntake(name, entry)
    local ib = GetOrCreateIntake(name)
    ib.idx = math.mod(ib.idx, ib.maxSize) + 1
    ib.buffer[ib.idx] = entry
    if ib.count < ib.maxSize then
        ib.count = ib.count + 1
    end
end

local function FreezeIntake(name)
    local ib = DL.intake[name]
    if not ib or ib.count == 0 then return {} end

    -- Extract ordered array (oldest first)
    local result = {}
    local start = ib.idx - ib.count + 1
    if start < 1 then start = start + ib.maxSize end

    for i = 0, ib.count - 1 do
        local pos = math.mod(start + i - 1, ib.maxSize) + 1
        if ib.buffer[pos] then
            table.insert(result, ib.buffer[pos])
        end
    end

    -- Clear buffer for next life
    ib.buffer = {}
    ib.idx = 0
    ib.count = 0

    return result
end

---------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------

local function OnDamageIntake(data)
    if P.settings.modules and not P.settings.modules.deaths then return end
    -- REVERSE of damage.lua: only track damage WHERE target IS a group member
    if not data.target then return end
    -- Include player + group members
    local isPlayer = (data.target == UnitName("player"))
    if not isPlayer and not P.IsGroupMember(data.target) then return end

    local hpAfter, hpMax
    if data.targetGUID then
        hpAfter = UnitHealth(data.targetGUID)
        hpMax = UnitHealthMax(data.targetGUID)
    end

    PushIntake(data.target, {
        time = data.time or GetTime(),
        etype = "DAMAGE",
        source = data.source or "?",
        spell = data.spellName or "Melee",
        spellID = data.spellID,
        amount = data.amount or 0,
        school = data.school or 0,
        crit = data.crit or false,
        hpAfter = hpAfter,
        hpMax = hpMax,
        overkill = 0,
        missType = nil,
    })
end

local function OnHealIntake(data)
    if P.settings.modules and not P.settings.modules.deaths then return end
    -- Track heals received by group members (for timeline context)
    if not data.target then return end
    local isPlayer = (data.target == UnitName("player"))
    if not isPlayer and not P.IsGroupMember(data.target) then return end

    local hpAfter, hpMax
    if data.targetGUID then
        hpAfter = UnitHealth(data.targetGUID)
        hpMax = UnitHealthMax(data.targetGUID)
    end

    PushIntake(data.target, {
        time = data.time or GetTime(),
        etype = "HEAL",
        source = data.source or "?",
        spell = data.spellName or "Heal",
        spellID = data.spellID,
        amount = data.amount or 0,
        school = data.school or 0,
        crit = data.crit or false,
        hpAfter = hpAfter,
        hpMax = hpMax,
        overkill = 0,
        missType = nil,
    })
end

local function OnMissIntake(data)
    if P.settings.modules and not P.settings.modules.deaths then return end
    if not data.target then return end
    local isPlayer = (data.target == UnitName("player"))
    if not isPlayer and not P.IsGroupMember(data.target) then return end

    PushIntake(data.target, {
        time = data.time or GetTime(),
        etype = "MISS",
        source = data.source or "?",
        spell = data.spellName or "Melee",
        spellID = data.spellID,
        amount = 0,
        school = data.school or 0,
        crit = false,
        hpAfter = nil,
        hpMax = nil,
        overkill = 0,
        missType = data.missType or "MISS",
    })
end

local function OnDeath(data)
    if P.settings.modules and not P.settings.modules.deaths then return end
    if not data.name then return end
    local isPlayer = (data.name == UnitName("player"))
    if not isPlayer and not P.IsGroupMember(data.name) then return end

    local events = FreezeIntake(data.name)

    -- Find killing blow (last DAMAGE entry with amount > 0)
    local killedBy = "Unknown"
    local killSpell = "Unknown"
    local killAmount = 0
    local killSchool = 0
    local killCrit = false
    local hpMax = 0
    local overkill = 0

    for i = table.getn(events), 1, -1 do
        local e = events[i]
        if e.etype == "DAMAGE" and e.amount > 0 then
            killedBy = e.source
            killSpell = e.spell
            killAmount = e.amount
            killSchool = e.school or 0
            killCrit = e.crit or false
            if e.hpMax and e.hpMax > 0 then hpMax = e.hpMax end
            -- Overkill: if we have hpAfter from the previous event, we can estimate
            if i > 1 then
                local prev = events[i - 1]
                if prev.hpAfter and prev.hpAfter > 0 then
                    overkill = e.amount - prev.hpAfter
                    if overkill < 0 then overkill = 0 end
                end
            end
            e.overkill = overkill
            break
        end
    end

    -- If hpMax still 0, try to find it from any event
    if hpMax == 0 then
        for i = table.getn(events), 1, -1 do
            if events[i].hpMax and events[i].hpMax > 0 then
                hpMax = events[i].hpMax
                break
            end
        end
    end

    -- Also try direct query (may still work briefly after death)
    if hpMax == 0 and data.guid then
        local qMax = UnitHealthMax(data.guid)
        if qMax and qMax > 0 then hpMax = qMax end
    end

    -- Total damage/healing taken
    local totalDmg = 0
    local totalHeal = 0
    for i = 1, table.getn(events) do
        local e = events[i]
        if e.etype == "DAMAGE" then
            totalDmg = totalDmg + (e.amount or 0)
        elseif e.etype == "HEAL" then
            totalHeal = totalHeal + (e.amount or 0)
        end
    end

    -- Duration of intake window
    local duration = 0
    local numEvents = table.getn(events)
    if numEvents >= 2 then
        duration = events[numEvents].time - events[1].time
    end

    -- Class lookup
    local class = P.dataStore and P.dataStore.classes and P.dataStore.classes[data.name]
    if not class and data.name then
        local unit = P.FindUnitByName(data.name)
        if unit then
            local _, uClass = UnitClass(unit)
            if uClass then class = uClass end
        end
    end

    local record = {
        name = data.name,
        class = class or "UNKNOWN",
        time = data.time or GetTime(),
        timeFmt = date("%H:%M:%S"),
        killedBy = killedBy,
        killSpell = killSpell,
        killAmount = killAmount,
        killSchool = killSchool,
        killCrit = killCrit,
        hpMax = hpMax,
        overkill = overkill,
        events = events,
        totalDmg = totalDmg,
        totalHeal = totalHeal,
        duration = duration,
    }

    -- Insert newest first
    table.insert(DL.current, 1, record)
    table.insert(DL.overall, 1, record)

    -- Trim
    while table.getn(DL.current) > DL.MAX_RECORDS do
        table.remove(DL.current)
    end
    while table.getn(DL.overall) > DL.MAX_RECORDS do
        table.remove(DL.overall)
    end

    -- Update counts
    DL.counts.current[data.name] = (DL.counts.current[data.name] or 0) + 1
    DL.counts.overall[data.name] = (DL.counts.overall[data.name] or 0) + 1

    -- Chat notification
    if P.settings.deathNotify then
        local schoolColors = P.SCHOOL_COLORS or {}
        local sc = schoolColors[killSchool] or { r = 1, g = 0.3, b = 0.3 }
        local colorHex = string.format("%02x%02x%02x",
            sc.r * 255, sc.g * 255, sc.b * 255)
        P.Print(data.name .. " killed by |cff" .. colorHex ..
            killSpell .. "|r (" .. killedBy .. ") - " ..
            P.FormatNumber(killAmount) .. " dmg")
    end

    -- Auto-popup for own death
    if data.name == UnitName("player") and P.settings.deathAutoPopup then
        if P.ShowDeathRecapForRecord then
            P.ShowDeathRecapForRecord(record)
        end
    end

    P.Debug("Death recorded: " .. data.name .. " by " ..
        killedBy .. " (" .. killSpell .. " " .. killAmount .. ")")
end

---------------------------------------------------------------------------
-- Reset Functions
---------------------------------------------------------------------------

function DL:ResetCurrent()
    self.current = {}
    self.counts.current = {}
end

function DL:ResetAll()
    self.current = {}
    self.overall = {}
    self.counts.current = {}
    self.counts.overall = {}
    self:ClearIntake()
end

function DL:ClearIntake()
    self.intake = {}
end

---------------------------------------------------------------------------
-- Query Functions (for UI)
---------------------------------------------------------------------------

function DL:GetDeaths(segment)
    if segment == "overall" then return self.overall end
    return self.current
end

function DL:GetDeathsForPlayer(name, segment)
    local deaths = self:GetDeaths(segment)
    local result = {}
    for i = 1, table.getn(deaths) do
        if deaths[i].name == name then
            table.insert(result, deaths[i])
        end
    end
    return result
end

function DL:GetLatestDeath()
    if table.getn(self.current) > 0 then return self.current[1] end
    if table.getn(self.overall) > 0 then return self.overall[1] end
    return nil
end

function DL:GetDeathCount(name, segment)
    local ct = self.counts.current
    if segment == "overall" then ct = self.counts.overall end
    return ct[name] or 0
end

---------------------------------------------------------------------------
-- Fake Data Support
---------------------------------------------------------------------------

function DL:AddFakeDeaths(deathList)
    for i = 1, table.getn(deathList) do
        local d = deathList[i]
        table.insert(self.current, 1, d)
        table.insert(self.overall, 1, d)
        self.counts.current[d.name] = (self.counts.current[d.name] or 0) + 1
        self.counts.overall[d.name] = (self.counts.overall[d.name] or 0) + 1
    end
end

---------------------------------------------------------------------------
-- Register with event bus
---------------------------------------------------------------------------

P.eventBus:Register("DAMAGE", OnDamageIntake)
P.eventBus:Register("HEAL", OnHealIntake)
P.eventBus:Register("MISS", OnMissIntake)
P.eventBus:Register("DEATH", OnDeath)
