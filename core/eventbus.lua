-- Parsec: Central Event Bus
-- Receives Nampower + SuperWoW events, normalizes, dispatches to modules

local P = Parsec
if not P then return end

table.insert(P._loadedFiles, "eventbus")

P.eventBus = CreateFrame("Frame", "ParsecEventBus")
local bus = P.eventBus

bus.listeners = {}  -- { eventType = { callback1, callback2, ... } }
bus.eventCount = 0
bus.lastEvents = {} -- ring buffer of last N events for debug
bus.lastEventsMax = 50
bus.lastEventsIdx = 0

-- Register a module callback for a specific internal event type
function bus:Register(eventType, callback)
    if not self.listeners[eventType] then
        self.listeners[eventType] = {}
    end
    table.insert(self.listeners[eventType], callback)
end

-- Fire an internal event to all registered listeners
function bus:Fire(eventType, data)
    self.eventCount = self.eventCount + 1

    -- Store in ring buffer for debug
    self.lastEventsIdx = math.mod(self.lastEventsIdx, self.lastEventsMax) + 1
    self.lastEvents[self.lastEventsIdx] = data

    local callbacks = self.listeners[eventType]
    if callbacks then
        for i = 1, table.getn(callbacks) do
            callbacks[i](data)
        end
    end
end

-- Reset counters
function bus:ResetStats()
    self.eventCount = 0
end

-- Internal event types:
-- "DAMAGE"  = { time, source, target, sourceGUID, targetGUID, spellID, spellName, amount, school, crit, isPet, petOwner }
-- "HEAL"    = { time, source, target, sourceGUID, targetGUID, spellID, spellName, amount, school, crit, overheal }
-- "MISS"    = { time, source, target, sourceGUID, targetGUID, spellID, spellName, missType, amount }
-- "DEATH"   = { time, name, guid }
-- "BUFF"    = { time, target, spellID, spellName, gained }
-- "CAST"    = { time, source, target, sourceGUID, targetGUID, spellID, spellName, castType, duration }

---------------------------------------------------------------------------
-- GUID -> Name Resolution
---------------------------------------------------------------------------

P.guidNames = {}

function P.ResolveName(guid)
    if not guid then return nil end

    -- Check cache
    local cached = P.guidNames[guid]
    if cached then return cached end

    -- SuperWoW: UnitName accepts GUIDs directly
    local name = UnitName(guid)
    if name then
        P.guidNames[guid] = name
        return name
    end

    return nil
end

---------------------------------------------------------------------------
-- Hit Info Helpers
---------------------------------------------------------------------------

local MISS_TYPES = {
    [1] = "MISS",
    [2] = "RESIST",
    [3] = "DODGE",
    [4] = "PARRY",
    [5] = "BLOCK",
    [6] = "EVADE",
    [7] = "IMMUNE",
    [8] = "IMMUNE",
    [9] = "DEFLECT",
    [10] = "ABSORB",
    [11] = "REFLECT",
}

-- Check if hitInfo bitmask has critical hit flag (HITINFO_CRITICALHIT = 0x2)
local function IsCritHit(hitInfo)
    if not hitInfo then return false end
    hitInfo = tonumber(hitInfo) or 0
    -- Check bit 1 (0x2) in Lua 5.0 without bit lib
    return math.mod(math.floor(hitInfo / 2), 2) == 1
end

---------------------------------------------------------------------------
-- Nampower Event Handlers (arg layouts from turtle-wow-kb)
---------------------------------------------------------------------------

-- SPELL_DAMAGE_EVENT_SELF / SPELL_DAMAGE_EVENT_OTHER
-- arg1=targetGuid, arg2=casterGuid, arg3=spellId, arg4=amount,
-- arg5=mitigationStr, arg6=hitInfo, arg7=spellSchool, arg8=effectAuraStr
local function OnSpellDamage()
    local casterGuid = arg2
    local targetGuid = arg1
    local spellID = arg3
    local amount = tonumber(arg4) or 0
    local hitInfo = tonumber(arg6) or 0
    local school = tonumber(arg7) or 0

    local source = P.ResolveName(casterGuid) or casterGuid or "?"
    local target = P.ResolveName(targetGuid) or targetGuid or "?"
    local crit = IsCritHit(hitInfo)

    local spellName = "?"
    if spellID and SpellInfo then
        local name = SpellInfo(spellID)
        if name then spellName = name end
    end

    local data = {
        time = GetTime(),
        type = "DAMAGE",
        source = source,
        target = target,
        sourceGUID = casterGuid,
        targetGUID = targetGuid,
        spellID = spellID,
        spellName = spellName,
        amount = amount,
        school = school,
        crit = crit,
        isPet = false,
        petOwner = nil,
    }

    P.Debug("DMG: " .. source .. " -> " .. target ..
            " [" .. spellName .. "] " .. amount ..
            (crit and " CRIT" or ""))

    bus:Fire("DAMAGE", data)
end

-- AUTO_ATTACK_SELF / AUTO_ATTACK_OTHER
-- arg1=attackerGuid, arg2=targetGuid, arg3=totalDamage,
-- arg4=hitInfo, arg5=victimState, arg6=subDamageCount,
-- arg7=blockedAmount, arg8=totalAbsorb, arg9=totalResist
local function OnAutoAttack()
    local attackerGuid = arg1
    local targetGuid = arg2
    local amount = tonumber(arg3) or 0
    local hitInfo = tonumber(arg4) or 0

    local source = P.ResolveName(attackerGuid) or attackerGuid or "?"
    local target = P.ResolveName(targetGuid) or targetGuid or "?"
    local crit = IsCritHit(hitInfo)

    local data = {
        time = GetTime(),
        type = "DAMAGE",
        source = source,
        target = target,
        sourceGUID = attackerGuid,
        targetGUID = targetGuid,
        spellID = 0,
        spellName = "Auto Attack",
        amount = amount,
        school = 0,
        crit = crit,
        isPet = false,
        petOwner = nil,
    }

    P.Debug("MELEE: " .. source .. " -> " .. target ..
            " " .. amount .. (crit and " CRIT" or ""))

    bus:Fire("DAMAGE", data)
end

-- SPELL_HEAL_BY_SELF / SPELL_HEAL_ON_SELF / SPELL_HEAL_BY_OTHER
-- arg1=targetGuid, arg2=casterGuid, arg3=spellId, arg4=amount,
-- arg5=critical (boolean), arg6=periodic (boolean)
local function OnSpellHeal()
    local targetGuid = arg1
    local casterGuid = arg2
    local spellID = arg3
    local amount = tonumber(arg4) or 0
    local crit = (arg5 == 1 or arg5 == true)

    local source = P.ResolveName(casterGuid) or casterGuid or "?"
    local target = P.ResolveName(targetGuid) or targetGuid or "?"

    local spellName = "?"
    if spellID and SpellInfo then
        local name = SpellInfo(spellID)
        if name then spellName = name end
    end

    -- Overheal: check target health via SuperWoW GUID support
    local overheal = 0
    if targetGuid then
        local hp = UnitHealth(targetGuid)
        local hpMax = UnitHealthMax(targetGuid)
        if hp and hpMax and hpMax > 0 then
            local deficit = hpMax - hp
            if amount > deficit and deficit >= 0 then
                overheal = amount - deficit
            end
        end
    end

    local data = {
        time = GetTime(),
        type = "HEAL",
        source = source,
        target = target,
        sourceGUID = casterGuid,
        targetGUID = targetGuid,
        spellID = spellID,
        spellName = spellName,
        amount = amount,
        school = 0,
        crit = crit,
        overheal = overheal,
    }

    P.Debug("HEAL: " .. source .. " -> " .. target ..
            " [" .. spellName .. "] " .. amount ..
            (overheal > 0 and (" OH:" .. overheal) or ""))

    bus:Fire("HEAL", data)
end

-- SPELL_MISS_SELF / SPELL_MISS_OTHER
-- arg1=casterGuid, arg2=targetGuid, arg3=spellId, arg4=missInfo
local function OnSpellMiss()
    local casterGuid = arg1
    local targetGuid = arg2
    local spellID = arg3
    local missInfo = tonumber(arg4) or 0

    local source = P.ResolveName(casterGuid) or casterGuid or "?"
    local target = P.ResolveName(targetGuid) or targetGuid or "?"
    local missType = MISS_TYPES[missInfo] or "MISS"

    local spellName = "?"
    if spellID and SpellInfo then
        local name = SpellInfo(spellID)
        if name then spellName = name end
    end

    local data = {
        time = GetTime(),
        type = "MISS",
        source = source,
        target = target,
        sourceGUID = casterGuid,
        targetGUID = targetGuid,
        spellID = spellID,
        spellName = spellName,
        missType = missType,
        amount = 0,
    }

    P.Debug("MISS: " .. source .. " -> " .. target ..
            " [" .. spellName .. "] " .. missType)

    bus:Fire("MISS", data)
end

-- BUFF_ADDED_* / BUFF_REMOVED_*
-- arg1=guid, arg2=luaSlot, arg3=spellId, arg4=stackCount,
-- arg5=auraLevel, arg6=auraSlot, arg7=state (0=added, 1=removed, 2=modified)
local function OnBuffChanged()
    local guid = arg1
    local spellID = arg3
    local state = tonumber(arg7) or 0

    local target = P.ResolveName(guid) or guid or "?"

    local spellName = "?"
    if spellID and SpellInfo then
        local name = SpellInfo(spellID)
        if name then spellName = name end
    end

    local data = {
        time = GetTime(),
        type = "BUFF",
        target = target,
        spellID = spellID,
        spellName = spellName,
        gained = (state == 0),
    }
    bus:Fire("BUFF", data)
end

-- SuperWoW: UNIT_CASTEVENT
-- arg1=casterGUID, arg2=targetGUID, arg3=castType, arg4=spellID, arg5=duration(ms)
local function OnUnitCastEvent()
    local data = {
        time = GetTime(),
        type = "CAST",
        sourceGUID = arg1,
        targetGUID = arg2,
        castType = arg3,
        spellID = arg4,
        duration = arg5,
        source = P.ResolveName(arg1) or "?",
        target = P.ResolveName(arg2) or "?",
        spellName = "?",
    }

    if data.spellID and SpellInfo then
        local name = SpellInfo(data.spellID)
        if name then
            data.spellName = name
        end
    end

    bus:Fire("CAST", data)
end

-- UNIT_DIED (Nampower: arg1=guid)
local function OnUnitDied()
    local guid = arg1
    local name = P.ResolveName(guid) or "?"

    local data = {
        time = GetTime(),
        type = "DEATH",
        name = name,
        guid = guid,
    }

    P.Debug("DEATH: " .. name)
    bus:Fire("DEATH", data)
end

---------------------------------------------------------------------------
-- Find unit ID by name (backward compat, used by some overheal calcs)
---------------------------------------------------------------------------
function P.FindUnitByName(name)
    if not name then return nil end
    if UnitName("player") == name then return "player" end
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i = 1, numRaid do
            if UnitName("raid" .. i) == name then
                return "raid" .. i
            end
        end
    else
        local numParty = GetNumPartyMembers()
        for i = 1, numParty do
            if UnitName("party" .. i) == name then
                return "party" .. i
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Register WoW events
---------------------------------------------------------------------------

-- Nampower damage events (always active, no CVar needed)
bus:RegisterEvent("SPELL_DAMAGE_EVENT_SELF")
bus:RegisterEvent("SPELL_DAMAGE_EVENT_OTHER")

-- Nampower auto attack events (require NP_EnableAutoAttackEvents CVar)
bus:RegisterEvent("AUTO_ATTACK_SELF")
bus:RegisterEvent("AUTO_ATTACK_OTHER")

-- Nampower heal events (require NP_EnableSpellHealEvents CVar)
bus:RegisterEvent("SPELL_HEAL_BY_SELF")
bus:RegisterEvent("SPELL_HEAL_ON_SELF")
bus:RegisterEvent("SPELL_HEAL_BY_OTHER")
bus:RegisterEvent("SPELL_HEAL_ON_OTHER")

-- Nampower miss events
bus:RegisterEvent("SPELL_MISS_SELF")
bus:RegisterEvent("SPELL_MISS_OTHER")

-- Buff events (always active, no CVar needed)
bus:RegisterEvent("BUFF_ADDED_SELF")
bus:RegisterEvent("BUFF_ADDED_OTHER")
bus:RegisterEvent("BUFF_REMOVED_SELF")
bus:RegisterEvent("BUFF_REMOVED_OTHER")

-- SuperWoW events
bus:RegisterEvent("UNIT_CASTEVENT")
bus:RegisterEvent("UNIT_DIED")

-- Group roster events (for class scanning)
bus:RegisterEvent("RAID_ROSTER_UPDATE")
bus:RegisterEvent("PARTY_MEMBERS_CHANGED")
bus:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Combat state events (forwarded to combat-state module)
bus:RegisterEvent("PLAYER_REGEN_DISABLED")
bus:RegisterEvent("PLAYER_REGEN_ENABLED")

bus:SetScript("OnEvent", function()
    -- Raw arg dump when debug mode is on
    if P.debugMode then
        P.DumpArgs(event)
    end

    -- Nampower damage
    if event == "SPELL_DAMAGE_EVENT_SELF" or event == "SPELL_DAMAGE_EVENT_OTHER" then
        OnSpellDamage()
    elseif event == "AUTO_ATTACK_SELF" or event == "AUTO_ATTACK_OTHER" then
        OnAutoAttack()

    -- Nampower healing
    elseif event == "SPELL_HEAL_BY_SELF" or event == "SPELL_HEAL_ON_SELF"
        or event == "SPELL_HEAL_BY_OTHER" or event == "SPELL_HEAL_ON_OTHER" then
        OnSpellHeal()

    -- Nampower miss
    elseif event == "SPELL_MISS_SELF" or event == "SPELL_MISS_OTHER" then
        OnSpellMiss()

    -- Buff tracking
    elseif event == "BUFF_ADDED_SELF" or event == "BUFF_ADDED_OTHER"
        or event == "BUFF_REMOVED_SELF" or event == "BUFF_REMOVED_OTHER" then
        OnBuffChanged()

    -- SuperWoW
    elseif event == "UNIT_CASTEVENT" then
        OnUnitCastEvent()
    elseif event == "UNIT_DIED" then
        OnUnitDied()

    -- Group updates
    elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED"
        or event == "PLAYER_ENTERING_WORLD" then
        P.ScanGroupClasses()

    -- Combat state (forwarded)
    elseif event == "PLAYER_REGEN_DISABLED" then
        if P.combatState then P.combatState:OnCombatStart() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if P.combatState then P.combatState:OnCombatEnd() end
    end
end)
