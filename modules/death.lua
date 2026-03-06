-- Parsec: Death Module
-- Tracks damage intake on group members, creates death records on UNIT_DIED
-- Ring buffer per player, HP tracking via SuperWoW UnitHealth(guid)

local P = Parsec
if not P or not P.eventBus then return end

table.insert(P._loadedFiles, "death")

P.deathLog = {}
local DL = P.deathLog

-- Constants
DL.INTAKE_SIZE = 50
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

-- Intake entry pool: recycle evicted ring buffer entries to reduce GC pressure
local _intakePool = {}
local _intakePoolSize = 0
local INTAKE_POOL_MAX = 100

local function RecycleIntakeEntry(entry)
    if not entry or _intakePoolSize >= INTAKE_POOL_MAX then return end
    _intakePoolSize = _intakePoolSize + 1
    _intakePool[_intakePoolSize] = entry
end

local function AcquireIntakeEntry()
    if _intakePoolSize > 0 then
        local entry = _intakePool[_intakePoolSize]
        _intakePool[_intakePoolSize] = nil
        _intakePoolSize = _intakePoolSize - 1
        -- Wipe all fields
        for k in pairs(entry) do entry[k] = nil end
        return entry
    end
    return {}
end

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
    -- Recycle the evicted entry before overwriting
    local old = ib.buffer[ib.idx]
    if old then RecycleIntakeEntry(old) end
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
-- Helpers: Aura Snapshots & Spell Icons
---------------------------------------------------------------------------

-- Hidden tooltip for buff/debuff name scanning
local scanTip = CreateFrame("GameTooltip", "ParsecAuraScanTip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function ScanBuffName(unit, index, isBuff)
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    if isBuff then
        scanTip:SetUnitBuff(unit, index)
    else
        scanTip:SetUnitDebuff(unit, index)
    end
    local line1 = getglobal("ParsecAuraScanTipTextLeft1")
    return line1 and line1:GetText() or nil
end

local function SnapshotAuras(unit)
    local buffs, debuffs = {}, {}
    if not unit then return buffs, debuffs end
    for i = 1, 32 do
        local tex, stacks, debuffType, auraID = UnitBuff(unit, i)
        if not tex then break end
        local name = ScanBuffName(unit, i, true)
        table.insert(buffs, { texture = tex, stacks = stacks or 0, auraID = auraID, name = name })
    end
    for i = 1, 64 do
        local tex, stacks, debuffType, auraID = UnitDebuff(unit, i)
        if not tex then break end
        local name = ScanBuffName(unit, i, false)
        table.insert(debuffs, { texture = tex, stacks = stacks or 0, debuffType = debuffType, auraID = auraID, name = name })
    end
    return buffs, debuffs
end

-- Throttled aura cache: reuse snapshots within TTL to avoid per-event re-scanning
local auraCache = {}  -- { [unit] = { time=T, buffs={...}, debuffs={...} } }
local AURA_CACHE_TTL = 2  -- seconds

-- Shallow-copy an array (entries are shared, but the array itself is independent)
local function ShallowCopyArray(src)
    local copy = {}
    for i = 1, table.getn(src) do copy[i] = src[i] end
    return copy
end

local function GetCachedAuras(unit)
    if not unit then return {}, {} end
    local now = GetTime()
    local cached = auraCache[unit]
    if cached and (now - cached.time) < AURA_CACHE_TTL then
        -- Return shallow copies so intake entries don't share the same array ref
        return ShallowCopyArray(cached.buffs), ShallowCopyArray(cached.debuffs)
    end
    local buffs, debuffs = SnapshotAuras(unit)
    auraCache[unit] = { time = now, buffs = buffs, debuffs = debuffs }
    -- First caller after cache miss gets its own copy too
    return ShallowCopyArray(buffs), ShallowCopyArray(debuffs)
end

DL.HEAL_FALLBACK_ICON = "Interface\\Icons\\Spell_Holy_LesserHeal"

-- Delegate icon/name resolution to shared consumables module (core/consumables.lua)
function DL.GetSpellIcon(spellID)
    if P.consumables then return P.consumables:GetIcon(spellID) end
    return nil
end

function DL.GetConsumableName(spellID)
    if P.consumables then return P.consumables:GetName(spellID) end
    return nil
end

-- Short-lived cache for raid target lookups (avoid 40+ UnitName calls per event)
local _raidTargetCache = {}   -- { [sourceName] = { time=T, idx=N|nil } }
local RAID_TARGET_CACHE_TTL = 0.5  -- seconds

local function FindSourceRaidTarget(sourceName)
    if not sourceName or not GetRaidTargetIndex then return nil end

    local now = GetTime()
    local cached = _raidTargetCache[sourceName]
    if cached and (now - cached.time) < RAID_TARGET_CACHE_TTL then
        return cached.idx
    end

    local idx = nil
    if UnitName("target") == sourceName then
        idx = GetRaidTargetIndex("target")
    elseif UnitName("targettarget") == sourceName then
        idx = GetRaidTargetIndex("targettarget")
    else
        local n = GetNumRaidMembers()
        if n > 0 then
            for i = 1, n do
                if UnitName("raid" .. i .. "target") == sourceName then
                    idx = GetRaidTargetIndex("raid" .. i .. "target")
                    break
                end
            end
        else
            for i = 1, 4 do
                if UnitName("party" .. i .. "target") == sourceName then
                    idx = GetRaidTargetIndex("party" .. i .. "target")
                    break
                end
            end
        end
    end

    _raidTargetCache[sourceName] = { time = now, idx = idx }
    return idx
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

    -- Resource + aura snapshot
    local unit = P.FindUnitByName(data.target)
    local manaAfter, manaMax, powerType
    if unit then
        manaAfter = UnitMana(unit)
        manaMax = UnitManaMax(unit)
        powerType = UnitPowerType(unit)
    elseif data.targetGUID then
        manaAfter = UnitMana(data.targetGUID)
        manaMax = UnitManaMax(data.targetGUID)
    end
    local buffs, debuffs = GetCachedAuras(unit)

    local raidTarget = FindSourceRaidTarget(data.source)

    local e = AcquireIntakeEntry()
    e.time = data.time or GetTime()
    e.etype = "DAMAGE"
    e.source = data.source or "?"
    e.spell = data.spellName or "Melee"
    e.spellID = data.spellID
    e.amount = data.amount or 0
    e.school = data.school or 0
    e.crit = data.crit or false
    e.hpAfter = hpAfter
    e.hpMax = hpMax
    e.overkill = 0
    e.manaAfter = manaAfter
    e.manaMax = manaMax
    e.powerType = powerType
    e.buffs = buffs
    e.debuffs = debuffs
    e.raidTarget = raidTarget
    PushIntake(data.target, e)
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

    -- Resource + aura snapshot
    local unit = P.FindUnitByName(data.target)
    local manaAfter, manaMax, powerType
    if unit then
        manaAfter = UnitMana(unit)
        manaMax = UnitManaMax(unit)
        powerType = UnitPowerType(unit)
    elseif data.targetGUID then
        manaAfter = UnitMana(data.targetGUID)
        manaMax = UnitManaMax(data.targetGUID)
    end
    local buffs, debuffs = GetCachedAuras(unit)

    local raidTarget = FindSourceRaidTarget(data.source)

    local e = AcquireIntakeEntry()
    e.time = data.time or GetTime()
    e.etype = "HEAL"
    e.source = data.source or "?"
    e.spell = data.spellName or "Heal"
    e.spellID = data.spellID
    e.amount = data.amount or 0
    e.school = data.school or 0
    e.crit = data.crit or false
    e.hpAfter = hpAfter
    e.hpMax = hpMax
    e.overkill = 0
    e.manaAfter = manaAfter
    e.manaMax = manaMax
    e.powerType = powerType
    e.buffs = buffs
    e.debuffs = debuffs
    e.raidTarget = raidTarget
    PushIntake(data.target, e)
end

local function OnMissIntake(data)
    if P.settings.modules and not P.settings.modules.deaths then return end
    if not data.target then return end
    local isPlayer = (data.target == UnitName("player"))
    if not isPlayer and not P.IsGroupMember(data.target) then return end

    -- Resource + aura snapshot
    local unit = P.FindUnitByName(data.target)
    local manaAfter, manaMax, powerType
    if unit then
        manaAfter = UnitMana(unit)
        manaMax = UnitManaMax(unit)
        powerType = UnitPowerType(unit)
    elseif data.targetGUID then
        manaAfter = UnitMana(data.targetGUID)
        manaMax = UnitManaMax(data.targetGUID)
    end
    local buffs, debuffs = GetCachedAuras(unit)

    local raidTarget = FindSourceRaidTarget(data.source)

    local e = AcquireIntakeEntry()
    e.time = data.time or GetTime()
    e.etype = "MISS"
    e.source = data.source or "?"
    e.spell = data.spellName or "Melee"
    e.spellID = data.spellID
    e.amount = 0
    e.school = data.school or 0
    e.crit = false
    e.overkill = 0
    e.missType = data.missType or "MISS"
    e.manaAfter = manaAfter
    e.manaMax = manaMax
    e.powerType = powerType
    e.buffs = buffs
    e.debuffs = debuffs
    e.raidTarget = raidTarget
    PushIntake(data.target, e)
end

local function OnOutgoingDamage(data)
    if P.settings.modules and not P.settings.modules.deaths then return end
    -- Track outgoing damage FROM group members (to show in their death timeline)
    if not data.source then return end
    local isPlayer = (data.source == UnitName("player"))
    if not isPlayer and not P.IsGroupMember(data.source) then return end

    -- Don't record self-damage as outgoing (already tracked as incoming)
    if data.source == data.target then return end

    -- HP/resource snapshot of the SOURCE (the player who dealt the damage)
    local unit = P.FindUnitByName(data.source)
    local hpAfter, hpMax, manaAfter, manaMax, powerType
    if unit then
        hpAfter = UnitHealth(unit)
        hpMax = UnitHealthMax(unit)
        manaAfter = UnitMana(unit)
        manaMax = UnitManaMax(unit)
        powerType = UnitPowerType(unit)
    elseif data.sourceGUID then
        hpAfter = UnitHealth(data.sourceGUID)
        hpMax = UnitHealthMax(data.sourceGUID)
        manaAfter = UnitMana(data.sourceGUID)
        manaMax = UnitManaMax(data.sourceGUID)
    end
    local buffs, debuffs = GetCachedAuras(unit)

    local raidTarget = FindSourceRaidTarget(data.target)

    local e = AcquireIntakeEntry()
    e.time = data.time or GetTime()
    e.etype = "OUTGOING"
    e.source = data.source
    e.target = data.target or "?"
    e.spell = data.spellName or "Melee"
    e.spellID = data.spellID
    e.amount = data.amount or 0
    e.school = data.school or 0
    e.crit = data.crit or false
    e.hpAfter = hpAfter
    e.hpMax = hpMax
    e.overkill = 0
    e.manaAfter = manaAfter
    e.manaMax = manaMax
    e.powerType = powerType
    e.buffs = buffs
    e.debuffs = debuffs
    e.raidTarget = raidTarget
    PushIntake(data.source, e)
end

local function OnBuffIntake(data)
    if P.settings.modules and not P.settings.modules.deaths then return end
    -- Only track buff gains (not removals) on group members
    if not data.gained then return end
    if not data.target then return end
    local isPlayer = (data.target == UnitName("player"))
    if not isPlayer and not P.IsGroupMember(data.target) then return end

    -- HP/resource snapshot
    local unit = P.FindUnitByName(data.target)
    local hpAfter, hpMax, manaAfter, manaMax, powerType
    if unit then
        hpAfter = UnitHealth(unit)
        hpMax = UnitHealthMax(unit)
        manaAfter = UnitMana(unit)
        manaMax = UnitManaMax(unit)
        powerType = UnitPowerType(unit)
    end
    local buffs, debuffs = GetCachedAuras(unit)

    local e = AcquireIntakeEntry()
    e.time = data.time or GetTime()
    e.etype = "BUFF"
    e.source = data.target  -- self-cast
    e.spell = data.spellName or "Buff"
    e.spellID = data.spellID
    e.amount = 0
    e.school = 0
    e.crit = false
    e.hpAfter = hpAfter
    e.hpMax = hpMax
    e.overkill = 0
    e.manaAfter = manaAfter
    e.manaMax = manaMax
    e.powerType = powerType
    e.buffs = buffs
    e.debuffs = debuffs
    PushIntake(data.target, e)
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

    -- Class + powerType lookup
    local class = P.dataStore and P.dataStore.classes and P.dataStore.classes[data.name]
    local deathUnit = P.FindUnitByName(data.name)
    if not class and deathUnit then
        local _, uClass = UnitClass(deathUnit)
        if uClass then class = uClass end
    end

    -- PowerType: try unit query first, fallback to last event
    local powerType = nil
    if deathUnit then
        powerType = UnitPowerType(deathUnit)
    end
    if not powerType then
        for i = table.getn(events), 1, -1 do
            if events[i].powerType then
                powerType = events[i].powerType
                break
            end
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
        powerType = powerType,
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

    -- Chat notification (filtered by context: own, party, raid)
    if P.settings.deathNotify then
        local isOwn = (data.name == UnitName("player"))
        local inRaid = (GetNumRaidMembers() > 0)
        local inParty = (not inRaid) and (GetNumPartyMembers() > 0)
        local shouldNotify = false
        if isOwn and P.settings.deathNotifyOwn then
            shouldNotify = true
        elseif inRaid and P.settings.deathNotifyRaid then
            shouldNotify = true
        elseif inParty and P.settings.deathNotifyParty then
            shouldNotify = true
        end
        if shouldNotify then
            local schoolColors = P.SCHOOL_COLORS or {}
            local sc = schoolColors[killSchool] or { r = 1, g = 0.3, b = 0.3 }
            local colorHex = string.format("%02x%02x%02x",
                sc.r * 255, sc.g * 255, sc.b * 255)
            P.Print(data.name .. " killed by |cff" .. colorHex ..
                killSpell .. "|r (" .. killedBy .. ") - " ..
                P.FormatNumber(killAmount) .. " dmg")
        end
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
    auraCache = {}  -- free aura snapshot memory
    _raidTargetCache = {}
end

function DL:ResetAll()
    self.current = {}
    self.overall = {}
    self.counts.current = {}
    self.counts.overall = {}
    self:ClearIntake()
    auraCache = {}  -- free aura snapshot memory
    _raidTargetCache = {}
end

function DL:ClearIntake()
    self.intake = {}
    _intakePool = {}
    _intakePoolSize = 0
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
P.eventBus:Register("DAMAGE", OnOutgoingDamage)
P.eventBus:Register("HEAL", OnHealIntake)
P.eventBus:Register("MISS", OnMissIntake)
P.eventBus:Register("BUFF", OnBuffIntake)
P.eventBus:Register("DEATH", OnDeath)
