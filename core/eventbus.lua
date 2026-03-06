-- Parsec: Central Event Bus
-- Receives Nampower + SuperWoW events, normalizes, dispatches to modules

local P = Parsec
if not P then return end

table.insert(P._loadedFiles, "eventbus")

P.eventBus = CreateFrame("Frame", "ParsecEventBus")
local bus = P.eventBus

bus.listeners = {}  -- { eventType = { callback1, callback2, ... } }
bus.eventCount = 0
bus._notPetGUIDs = {}  -- negative cache: GUIDs confirmed as NOT pets

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
-- "DRAIN"   = { time, source, target, spellName, amount, resource }
-- "CAST"    = { time, source, target, sourceGUID, targetGUID, spellID, spellName, castType, duration }

---------------------------------------------------------------------------
-- Missed Event Logger
-- Stores CHAT_MSG events we receive but cannot parse (like DPSMate's
-- "Event not parsed yet"). Helps discover new patterns to support.
---------------------------------------------------------------------------

P.missedEvents = {}
local MISSED_MAX = 100
-- Dedup: don't log the same pattern over and over
local missedSeen = {}  -- { [eventName..msg] = true }

local function LogMissedEvent(eventName, msg)
    if not msg then return end
    -- Dedup key: event + first 60 chars of message pattern (strip numbers for grouping)
    local patternKey = eventName .. ":" .. string.gsub(string.sub(msg, 1, 60), "%d+", "#")
    if missedSeen[patternKey] then return end
    missedSeen[patternKey] = true

    local entry = {
        time = date("%H:%M:%S"),
        event = eventName,
        msg = msg,
    }
    table.insert(P.missedEvents, entry)
    if table.getn(P.missedEvents) > MISSED_MAX then
        table.remove(P.missedEvents, 1)
    end

    -- Only show in debug mode, always visible in Options > Debug message log
    P.Debug("|cffff8800[MISSED]|r " .. msg)
end

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
    -- WoW returns "Unknown" for unresolved units — don't cache that
    if name and name ~= "Unknown" and name ~= "Unbekannt" then
        P.guidNames[guid] = name

        -- Also grab class while we have the GUID (SuperWoW supports UnitClass(guid))
        if P.dataStore and not P.dataStore.classes[name] then
            local _, class = UnitClass(guid)
            if class then
                P.dataStore.classes[name] = class
            end
        end

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

-- Spell hitInfo uses SpellHitType enum: SPELL_HIT_TYPE_CRIT = 0x02 (bit 1)
local function IsSpellCrit(hitInfo)
    if not hitInfo then return false end
    hitInfo = tonumber(hitInfo) or 0
    -- Check bit 1 (0x02) in Lua 5.0 without bit lib
    return math.mod(math.floor(hitInfo / 2), 2) == 1
end

-- Melee hitInfo uses HitInfo enum: HITINFO_CRITICALHIT = 0x80 (bit 7)
-- (0x02 is HITINFO_NORMALSWING2, set on almost every normal hit!)
local function IsMeleeCrit(hitInfo)
    if not hitInfo then return false end
    hitInfo = tonumber(hitInfo) or 0
    -- Check bit 7 (0x80 = 128) in Lua 5.0 without bit lib
    return math.mod(math.floor(hitInfo / 128), 2) == 1
end

---------------------------------------------------------------------------
-- Reusable data tables (avoid per-event allocation, reduces GC pressure)
-- Each handler gets its own table that is reset and reused.
---------------------------------------------------------------------------

local _dmgData = {}
local _healData = {}
local _missData = {}
local _buffData = {}
local _castData = {}
local _deathData = {}
local _dmgShieldData = {}
local _petDmgData = {}

local function ResetTable(t)
    t.time = nil; t.type = nil; t.source = nil; t.target = nil
    t.sourceGUID = nil; t.targetGUID = nil; t.spellID = nil; t.spellName = nil
    t.amount = nil; t.school = nil; t.crit = nil; t.periodic = nil
    t.isPet = nil; t.petOwner = nil; t.overheal = nil
    t.missType = nil; t.gained = nil; t.castType = nil; t.duration = nil
    t.name = nil; t.guid = nil
    return t
end

---------------------------------------------------------------------------
-- Spell Name Cache (avoid repeated SpellInfo string allocations)
---------------------------------------------------------------------------

local spellNameCache = {}
local function CachedSpellName(spellID)
    if not spellID then return "?" end
    local cached = spellNameCache[spellID]
    if cached then return cached end
    if SpellInfo then
        local name = SpellInfo(spellID)
        if name then
            spellNameCache[spellID] = name
            return name
        end
    end
    return "?"
end

---------------------------------------------------------------------------
-- Pet Owner Mapping (petGUID -> ownerName)
---------------------------------------------------------------------------

P.petOwners = {}
P.totemCastLog = {}  -- array of { caster=name, spell=spellName, time=T, totemGuid=nil }

function P.ScanGroupPets()
    -- Don't wipe! Merge new entries to keep previously discovered pet mappings
    if not UnitGUID then return end

    -- Player's own pet
    local petGUID = UnitGUID("pet")
    if petGUID then
        local ownerName = UnitName("player")
        if ownerName then
            P.petOwners[petGUID] = ownerName
        end
    end

    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i = 1, numRaid do
            local pGUID = UnitGUID("raidpet" .. i)
            if pGUID then
                local oName = UnitName("raid" .. i)
                if oName then
                    P.petOwners[pGUID] = oName
                end
            end
        end
    else
        local numParty = GetNumPartyMembers()
        for i = 1, numParty do
            local pGUID = UnitGUID("partypet" .. i)
            if pGUID then
                local oName = UnitName("party" .. i)
                if oName then
                    P.petOwners[pGUID] = oName
                end
            end
        end
    end
end

-- Check if a GUID belongs to a pet/totem and return ownerName or nil
-- Uses multiple fallback methods for reliable attribution in raids
function P.GetPetOwnerByGUID(guid)
    if not guid then return nil end

    -- 1. Check cache first
    local cached = P.petOwners[guid]
    if cached then return cached end

    -- 1b. Negative cache (confirmed non-pets, skip expensive scans)
    if bus._notPetGUIDs[guid] then return nil end

    -- 2. Get creature name via SuperWoW (server-side, works at any range)
    local creatureName = UnitName(guid)
    if not creatureName or creatureName == "Unknown" or creatureName == "Unbekannt" then
        return nil
    end

    -- If it's already a group member name, it's a player not a pet
    if P.IsGroupMember(creatureName) then return nil end

    -- 3. Check totem cast log (populated by SPELL_GO tracking)
    -- FIFO: oldest unassigned cast matched first (first placed = first to attack)
    -- Fuzzy match: creature name may include rank that SpellInfo omits
    local totemOwner = nil
    local creatureLower = string.lower(creatureName)
    for i = 1, table.getn(P.totemCastLog) do
        local entry = P.totemCastLog[i]
        if not entry.totemGuid then
            local spellLower = string.lower(entry.spell)
            if creatureLower == spellLower
                or string.find(creatureLower, spellLower, 1, true)
                or string.find(spellLower, creatureLower, 1, true) then
                totemOwner = entry.caster
                entry.totemGuid = guid
                break
            end
        end
    end
    if totemOwner then
        P.petOwners[guid] = totemOwner
        P.Debug("Totem->Owner: " .. creatureName .. " -> " .. totemOwner)
        return totemOwner
    end

    -- 4. Direct raidpet/partypet GUID scan
    if UnitGUID then
        local petGUID = UnitGUID("pet")
        if petGUID and petGUID == guid then
            local ownerName = UnitName("player")
            if ownerName then
                P.petOwners[guid] = ownerName
                return ownerName
            end
        end

        local numRaid = GetNumRaidMembers()
        if numRaid > 0 then
            for i = 1, numRaid do
                local pGUID = UnitGUID("raidpet" .. i)
                if pGUID and pGUID == guid then
                    local oName = UnitName("raid" .. i)
                    if oName and oName ~= "Unknown" and oName ~= "Unbekannt" then
                        P.petOwners[guid] = oName
                        P.Debug("Pet GUID match: " .. creatureName .. " -> " .. oName)
                        return oName
                    end
                end
            end
        else
            for i = 1, GetNumPartyMembers() do
                local pGUID = UnitGUID("partypet" .. i)
                if pGUID and pGUID == guid then
                    local oName = UnitName("party" .. i)
                    if oName and oName ~= "Unknown" and oName ~= "Unbekannt" then
                        P.petOwners[guid] = oName
                        return oName
                    end
                end
            end
        end

        -- 5. Raidpet name scan (fallback when GUID match fails)
        if numRaid > 0 then
            for i = 1, numRaid do
                local rpName = UnitName("raidpet" .. i)
                if rpName and rpName == creatureName then
                    local oName = UnitName("raid" .. i)
                    if oName and oName ~= "Unknown" and oName ~= "Unbekannt" then
                        P.petOwners[guid] = oName
                        P.Debug("Pet name match: " .. creatureName .. " -> " .. oName)
                        return oName
                    end
                end
            end
        else
            for i = 1, GetNumPartyMembers() do
                local ppName = UnitName("partypet" .. i)
                if ppName and ppName == creatureName then
                    local oName = UnitName("party" .. i)
                    if oName and oName ~= "Unknown" and oName ~= "Unbekannt" then
                        P.petOwners[guid] = oName
                        P.Debug("Pet name match: " .. creatureName .. " -> " .. oName)
                        return oName
                    end
                end
            end
        end
    end

    -- 6. Class-based fallback (when raidpet scan fails due to range)
    if not P.dataStore then return nil end
    local lowerName = string.lower(creatureName)
    local isTotem = string.find(lowerName, "totem")

    if isTotem then
        -- Totem -> find Shamans in group
        local shamans = {}
        for name, class in pairs(P.dataStore.classes) do
            if class == "SHAMAN" and P.IsGroupMember(name) then
                table.insert(shamans, name)
            end
        end
        if table.getn(shamans) == 1 then
            P.petOwners[guid] = shamans[1]
            P.Debug("Totem->Shaman: " .. creatureName .. " -> " .. shamans[1])
            return shamans[1]
        end
        -- Multiple shamans: can't disambiguate without SPELL_GO data
    else
        -- Pet -> check creature type via SuperWoW (accepts GUIDs)
        local cType = UnitCreatureType and UnitCreatureType(guid)
        local cFamily = UnitCreatureFamily and UnitCreatureFamily(guid)

        if cType == "Beast" or cType == "Wildtier" or cType == "Bestie" or cFamily then
            -- Likely a Hunter pet (Beast family)
            local hunters = {}
            for name, class in pairs(P.dataStore.classes) do
                if class == "HUNTER" and P.IsGroupMember(name) then
                    table.insert(hunters, name)
                end
            end
            if table.getn(hunters) == 1 then
                P.petOwners[guid] = hunters[1]
                P.Debug("Pet->Hunter: " .. creatureName .. " -> " .. hunters[1])
                return hunters[1]
            end
        end

        if cType == "Demon" or cType == "Daemon" or cType == "Dämon" then
            -- Warlock pet
            local warlocks = {}
            for name, class in pairs(P.dataStore.classes) do
                if class == "WARLOCK" and P.IsGroupMember(name) then
                    table.insert(warlocks, name)
                end
            end
            if table.getn(warlocks) == 1 then
                P.petOwners[guid] = warlocks[1]
                P.Debug("Pet->Warlock: " .. creatureName .. " -> " .. warlocks[1])
                return warlocks[1]
            end
        end
    end

    -- Cache as non-pet to avoid repeated expensive scans
    bus._notPetGUIDs[guid] = true
    return nil
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
    local crit = IsSpellCrit(hitInfo)

    -- Periodic damage (DoT ticks) has hitInfo == 0 because it originates
    -- from SMSG_PERIODICAURALOG (no SpellHitType flags).
    -- Direct spell hits always have SPELL_HIT_TYPE_UNK1 (0x01) set.
    local periodic = (hitInfo == 0)

    local spellName = CachedSpellName(spellID)

    local petOwner = P.GetPetOwnerByGUID(casterGuid)

    -- Skip own-pet damage from _OTHER events (CHAT_MSG handles it more reliably)
    if petOwner and petOwner == UnitName("player") and event == "SPELL_DAMAGE_EVENT_OTHER" then
        return
    end

    local data = ResetTable(_dmgData)
    data.time = GetTime()
    data.type = "DAMAGE"
    data.source = source
    data.target = target
    data.sourceGUID = casterGuid
    data.targetGUID = targetGuid
    data.spellID = spellID
    data.spellName = spellName
    data.amount = amount
    data.school = school
    data.crit = crit
    data.periodic = periodic
    data.isPet = (petOwner ~= nil)
    data.petOwner = petOwner

    -- Only log pet attributions (not every damage event)
    if petOwner and P.debugMode then
        P.Debug("PET DMG: " .. source .. " -> " .. target ..
                " [" .. spellName .. "] " .. amount .. " (owner:" .. petOwner .. ")")
    end

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
    local crit = IsMeleeCrit(hitInfo)
    local petOwner = P.GetPetOwnerByGUID(attackerGuid)

    -- Skip own-pet melee from _OTHER events (CHAT_MSG handles it)
    if petOwner and petOwner == UnitName("player") and event == "AUTO_ATTACK_OTHER" then
        return
    end

    local data = ResetTable(_dmgData)
    data.time = GetTime()
    data.type = "DAMAGE"
    data.source = source
    data.target = target
    data.sourceGUID = attackerGuid
    data.targetGUID = targetGuid
    data.spellID = 0
    data.spellName = "Auto Attack"
    data.amount = amount
    data.school = 0
    data.crit = crit
    data.isPet = (petOwner ~= nil)
    data.petOwner = petOwner

    -- Only log pet attributions
    if petOwner and P.debugMode then
        P.Debug("PET MELEE: " .. source .. " -> " .. target ..
                " " .. amount .. " (owner:" .. petOwner .. ")")
    end

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
    local periodic = (arg6 == 1 or arg6 == true)

    local source = P.ResolveName(casterGuid) or casterGuid or "?"
    local target = P.ResolveName(targetGuid) or targetGuid or "?"

    local spellName = CachedSpellName(spellID)

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

    local data = ResetTable(_healData)
    data.time = GetTime()
    data.type = "HEAL"
    data.source = source
    data.target = target
    data.sourceGUID = casterGuid
    data.targetGUID = targetGuid
    data.spellID = spellID
    data.spellName = spellName
    data.amount = amount
    data.school = 0
    data.crit = crit
    data.periodic = periodic
    data.overheal = overheal

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

    local spellName = CachedSpellName(spellID)

    local data = ResetTable(_missData)
    data.time = GetTime()
    data.type = "MISS"
    data.source = source
    data.target = target
    data.sourceGUID = casterGuid
    data.targetGUID = targetGuid
    data.spellID = spellID
    data.spellName = spellName
    data.missType = missType
    data.amount = 0

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

    local spellName = CachedSpellName(spellID)

    local data = ResetTable(_buffData)
    data.time = GetTime()
    data.type = "BUFF"
    data.target = target
    data.spellID = spellID
    data.spellName = spellName
    data.gained = (state == 0)
    bus:Fire("BUFF", data)
end

-- SuperWoW: UNIT_CASTEVENT
-- arg1=casterGUID, arg2=targetGUID, arg3=castType, arg4=spellID, arg5=duration(ms)
local function OnUnitCastEvent()
    local data = ResetTable(_castData)
    data.time = GetTime()
    data.type = "CAST"
    data.sourceGUID = arg1
    data.targetGUID = arg2
    data.castType = arg3
    data.spellID = arg4
    data.duration = arg5
    data.source = P.ResolveName(arg1) or "?"
    data.target = P.ResolveName(arg2) or "?"
    data.spellName = CachedSpellName(arg4)

    bus:Fire("CAST", data)
end

-- SPELL_GO_SELF / SPELL_GO_OTHER — track totem casts for owner attribution
-- arg1=itemId, arg2=spellId, arg3=casterGuid, arg4=targetGuid, arg5=castFlags
local function OnSpellGo()
    local spellId = arg2
    local casterGuid = arg3
    if not spellId or not casterGuid then return end

    local casterName = P.ResolveName(casterGuid)
    if not casterName or not P.IsGroupMember(casterName) then return end

    local spellName = CachedSpellName(spellId)
    if spellName ~= "?" and string.find(string.lower(spellName), "totem") then
        table.insert(P.totemCastLog, {
            caster = casterName,
            spell = spellName,
            time = GetTime(),
            totemGuid = nil,
        })
        P.Debug("Totem cast queued: " .. spellName .. " by " .. casterName)
        -- Prune entries older than 5 minutes (throttled: every 30s)
        local now = GetTime()
        if now - (bus._lastTotemPrune or 0) > 30 then
            bus._lastTotemPrune = now
            local writeIdx = 0
            for i = 1, table.getn(P.totemCastLog) do
                if now - P.totemCastLog[i].time < 300 then
                    writeIdx = writeIdx + 1
                    P.totemCastLog[writeIdx] = P.totemCastLog[i]
                end
            end
            -- Nil out trailing stale entries
            for i = writeIdx + 1, table.getn(P.totemCastLog) do
                P.totemCastLog[i] = nil
            end
        end
    end
end

-- CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF / _ON_OTHERS
-- Handles reflected damage (Thorns, Retribution Aura, Fire Shield, etc.)
-- These are NOT covered by Nampower structured events.
-- English client format:
--   Self:  "You reflect 21 Holy damage to Obsidian Nullifier."
--   Other: "Aquilla reflects 21 Holy damage to Obsidian Nullifier."
local SCHOOL_NAME_TO_NUM = {
    ["Physical"] = 0, ["Holy"] = 1, ["Fire"] = 2,
    ["Nature"] = 3, ["Frost"] = 4, ["Shadow"] = 5, ["Arcane"] = 6,
}

local function OnDamageShield()
    local msg = arg1
    if not msg then return end

    local source, amountStr, schoolName, target

    -- Self: "You reflect 21 Holy damage to Obsidian Nullifier."
    local _, _, a, s, t = string.find(msg, "You reflect (%d+) (%a+) damage to (.+)%.")
    if a then
        source = UnitName("player")
        amountStr = a
        schoolName = s
        target = t
    else
        -- Other: "Aquilla reflects 21 Holy damage to Obsidian Nullifier."
        local _, _, src, a2, s2, t2 = string.find(msg, "(.+) reflects (%d+) (%a+) damage to (.+)%.")
        if a2 then
            source = src
            amountStr = a2
            schoolName = s2
            target = t2
        end
    end

    if not source or not amountStr then
        -- Try resist pattern: "X's Spell was resisted by Target."
        -- Also comes through DAMAGESHIELDS channel (e.g. Lightning Strike triggers shield)
        local _, _, rSource, rSpell, rTarget = string.find(msg, "(.+)'s (.+) was resisted by (.+)%.")
        if rSource then
            local data = ResetTable(_dmgShieldData)
            data.time = GetTime()
            data.type = "MISS"
            data.source = rSource
            data.target = rTarget
            data.spellID = 0
            data.spellName = rSpell
            data.missType = "RESIST"
            data.amount = 0
            bus:Fire("MISS", data)
            return
        end

        LogMissedEvent(event, msg)
        return
    end

    local amount = tonumber(amountStr) or 0
    if amount <= 0 then return end

    local data = ResetTable(_dmgShieldData)
    data.time = GetTime()
    data.type = "DAMAGE"
    data.source = source
    data.target = target or "?"
    data.spellID = 0
    data.spellName = "Reflection"
    data.amount = amount
    data.school = SCHOOL_NAME_TO_NUM[schoolName] or 0
    data.crit = false
    data.isPet = false

    bus:Fire("DAMAGE", data)
end

-- UNIT_DIED (Nampower: arg1=guid)
local function OnUnitDied()
    local guid = arg1
    local name = P.ResolveName(guid) or "?"

    local data = ResetTable(_deathData)
    data.time = GetTime()
    data.type = "DEATH"
    data.name = name
    data.guid = guid

    bus:Fire("DEATH", data)
end

---------------------------------------------------------------------------
-- CHAT_MSG Pet Damage Handlers (reliable own-pet/totem damage tracking)
-- These always fire for the player's own pets regardless of range,
-- unlike Nampower _OTHER events which are range-limited.
---------------------------------------------------------------------------

local function OnPetSpellDamage()
    local msg = arg1
    if not msg then return end

    local pet, spell, target, amountStr, schoolName, isCrit

    -- Crit: "Your <pet>'s <spell> crits <target> for <amount> <school> damage"
    local _, _, p, s, t, a, sc = string.find(msg, "Your (.+)'s (.+) crits (.+) for (%d+) (%a+) damage")
    if a then
        pet, spell, target, amountStr, schoolName, isCrit = p, s, t, a, sc, true
    else
        -- Hit: "Your <pet>'s <spell> hits <target> for <amount> <school> damage"
        local _, _, p2, s2, t2, a2, sc2 = string.find(msg, "Your (.+)'s (.+) hits (.+) for (%d+) (%a+) damage")
        if a2 then
            pet, spell, target, amountStr, schoolName, isCrit = p2, s2, t2, a2, sc2, false
        end
    end

    if not amountStr then
        -- Absorb/resist/immune -- no damage, skip silently
        return
    end

    local amount = tonumber(amountStr) or 0
    if amount <= 0 then return end

    local playerName = UnitName("player")
    local data = ResetTable(_petDmgData)
    data.time = GetTime()
    data.type = "DAMAGE"
    data.source = playerName
    data.target = target or "?"
    data.spellID = 0
    data.spellName = spell
    data.amount = amount
    data.school = SCHOOL_NAME_TO_NUM[schoolName] or 0
    data.crit = isCrit
    data.periodic = false
    data.isPet = true
    data.petOwner = playerName
    bus:Fire("DAMAGE", data)
end

local function OnPetMeleeDamage()
    local msg = arg1
    if not msg then return end

    local target, amountStr, isCrit

    -- Crit: "Your <pet> crits <target> for <amount>."
    -- Anchor with trailing %." to prevent partial matches on substring overlaps
    local _, _, p, t, a = string.find(msg, "Your (.+) crits (.+) for (%d+)%.")
    if a then
        target, amountStr, isCrit = t, a, true
    else
        -- Hit: "Your <pet> hits <target> for <amount>."
        local _, _, p2, t2, a2 = string.find(msg, "Your (.+) hits (.+) for (%d+)%.")
        if a2 then
            target, amountStr, isCrit = t2, a2, false
        end
    end

    if not amountStr then return end

    local amount = tonumber(amountStr) or 0
    if amount <= 0 then return end

    local playerName = UnitName("player")
    local data = ResetTable(_petDmgData)
    data.time = GetTime()
    data.type = "DAMAGE"
    data.source = playerName
    data.target = target or "?"
    data.spellID = 0
    data.spellName = "Auto Attack"
    data.amount = amount
    data.school = 0
    data.crit = isCrit
    data.periodic = false
    data.isPet = true
    data.petOwner = playerName
    bus:Fire("DAMAGE", data)
end

local function OnPetPeriodicDamage()
    local msg = arg1
    if not msg then return end

    -- Pet periodic: "<target> suffers <amount> <school> damage from your <pet>'s <spell>."
    local _, _, target, amountStr, schoolName, pet, spell =
        string.find(msg, "(.+) suffers (%d+) (%a+) damage from your (.+)'s (.+)%.")
    if not amountStr then return end  -- not a pet periodic, skip

    local amount = tonumber(amountStr) or 0
    if amount <= 0 then return end

    local playerName = UnitName("player")
    local data = ResetTable(_petDmgData)
    data.time = GetTime()
    data.type = "DAMAGE"
    data.source = playerName
    data.target = target or "?"
    data.spellID = 0
    data.spellName = spell
    data.amount = amount
    data.school = SCHOOL_NAME_TO_NUM[schoolName] or 0
    data.crit = false
    data.periodic = true
    data.isPet = true
    data.petOwner = playerName
    bus:Fire("DAMAGE", data)
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
-- Periodic pet scanning (raidpet units are range-limited, so we rescan often)
-- Only runs when in a group (raid or party) to avoid wasting frames solo.
local petScanTimer = 0
local PET_SCAN_INTERVAL = 3  -- seconds
bus:SetScript("OnUpdate", function()
    if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then return end
    petScanTimer = petScanTimer + arg1
    if petScanTimer >= PET_SCAN_INTERVAL then
        petScanTimer = 0
        P.ScanGroupPets()
    end
end)

-- Register WoW events
---------------------------------------------------------------------------

-- Nampower damage events (always active, no CVar needed)
bus:RegisterEvent("SPELL_DAMAGE_EVENT_SELF")
bus:RegisterEvent("SPELL_DAMAGE_EVENT_OTHER")

-- Nampower auto attack events (require NP_EnableAutoAttackEvents CVar)
bus:RegisterEvent("AUTO_ATTACK_SELF")
bus:RegisterEvent("AUTO_ATTACK_OTHER")

-- Nampower spell go events (require NP_EnableSpellGoEvents CVar) — for totem tracking
bus:RegisterEvent("SPELL_GO_SELF")
bus:RegisterEvent("SPELL_GO_OTHER")

-- Nampower heal events (require NP_EnableSpellHealEvents CVar)
-- Only BY variants needed: BY_SELF covers all player heals, BY_OTHER covers all other heals
-- ON_SELF/ON_OTHER would double-count (same heal fires both BY and ON perspectives)
bus:RegisterEvent("SPELL_HEAL_BY_SELF")
bus:RegisterEvent("SPELL_HEAL_BY_OTHER")

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

-- Pet changes (summon/dismiss/swap)
bus:RegisterEvent("UNIT_PET")

-- Damage shield events (Thorns, Retribution Aura, etc. — not in Nampower)
bus:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF")
bus:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS")

-- CHAT_MSG pet/totem damage (reliable own-pet tracking, not range-limited)
bus:RegisterEvent("CHAT_MSG_SPELL_PET_DAMAGE")
bus:RegisterEvent("CHAT_MSG_COMBAT_PET_HITS")
bus:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")

-- Combat state events (forwarded to combat-state module)
bus:RegisterEvent("PLAYER_REGEN_DISABLED")
bus:RegisterEvent("PLAYER_REGEN_ENABLED")

-- Seed player GUID from _SELF events (most reliable method)
local function SeedPlayerGUID(guid)
    if not guid then return end
    if P.guidNames[guid] then return end  -- already known
    local playerName = UnitName("player")
    if playerName then
        P.guidNames[guid] = playerName
        P.Debug("Seeded player GUID from _SELF event: " .. playerName)
        -- Also seed class
        if P.dataStore and not P.dataStore.classes[playerName] then
            local _, class = UnitClass("player")
            if class then
                P.dataStore.classes[playerName] = class
            end
        end
    end
end

bus:SetScript("OnEvent", function()
    -- Raw arg dump only in verbose mode (/parsec verbose)
    if P.verboseMode then
        P.DumpArgs(event)
    end

    -- Seed player GUID from _SELF events before processing
    if event == "SPELL_DAMAGE_EVENT_SELF" then
        SeedPlayerGUID(arg2)  -- arg2 = casterGuid = player
    elseif event == "AUTO_ATTACK_SELF" then
        SeedPlayerGUID(arg1)  -- arg1 = attackerGuid = player
    elseif event == "SPELL_MISS_SELF" then
        SeedPlayerGUID(arg1)  -- arg1 = casterGuid = player
    elseif event == "SPELL_HEAL_BY_SELF" then
        SeedPlayerGUID(arg2)  -- arg2 = casterGuid = player
    end

    -- Nampower damage
    if event == "SPELL_DAMAGE_EVENT_SELF" or event == "SPELL_DAMAGE_EVENT_OTHER" then
        OnSpellDamage()
    elseif event == "AUTO_ATTACK_SELF" or event == "AUTO_ATTACK_OTHER" then
        OnAutoAttack()

    -- Nampower healing
    elseif event == "SPELL_HEAL_BY_SELF" or event == "SPELL_HEAL_BY_OTHER" then
        OnSpellHeal()

    -- Nampower spell go (totem tracking)
    elseif event == "SPELL_GO_SELF" or event == "SPELL_GO_OTHER" then
        OnSpellGo()

    -- Nampower miss
    elseif event == "SPELL_MISS_SELF" or event == "SPELL_MISS_OTHER" then
        OnSpellMiss()

    -- Buff tracking
    elseif event == "BUFF_ADDED_SELF" or event == "BUFF_ADDED_OTHER"
        or event == "BUFF_REMOVED_SELF" or event == "BUFF_REMOVED_OTHER" then
        OnBuffChanged()

    -- Damage shields (Thorns, Retribution Aura, etc.)
    elseif event == "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF"
        or event == "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS" then
        OnDamageShield()

    -- CHAT_MSG pet/totem damage (reliable own-pet tracking)
    elseif event == "CHAT_MSG_SPELL_PET_DAMAGE" then
        OnPetSpellDamage()
    elseif event == "CHAT_MSG_COMBAT_PET_HITS" then
        OnPetMeleeDamage()
    elseif event == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE" then
        OnPetPeriodicDamage()

    -- SuperWoW
    elseif event == "UNIT_CASTEVENT" then
        OnUnitCastEvent()
    elseif event == "UNIT_DIED" then
        OnUnitDied()

    -- Group updates
    elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED"
        or event == "PLAYER_ENTERING_WORLD" then
        P.ScanGroupClasses()
        P.ScanGroupPets()
        P.ScanGroupMembers()
        -- After /reload during combat, PLAYER_REGEN_DISABLED won't re-fire.
        -- Detect and sync combat state so duration tracking works correctly.
        if event == "PLAYER_ENTERING_WORLD" and UnitAffectingCombat("player") then
            if P.combatState and P.combatState.state == "IDLE" then
                P.combatState:OnCombatStart()
            end
        end

    -- Pet summon/dismiss/swap
    elseif event == "UNIT_PET" then
        P.ScanGroupPets()

    -- Combat state (forwarded, also rescan pets on combat start)
    elseif event == "PLAYER_REGEN_DISABLED" then
        P.ScanGroupPets()
        if P.combatState then P.combatState:OnCombatStart() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if P.combatState then P.combatState:OnCombatEnd() end
        -- Clean up negative pet cache (allows re-evaluation next combat)
        bus._notPetGUIDs = {}
    end
end)
