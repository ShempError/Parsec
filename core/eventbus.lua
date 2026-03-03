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
    self.lastEventsIdx = (self.lastEventsIdx % self.lastEventsMax) + 1
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
-- Nampower Event Handlers
---------------------------------------------------------------------------

-- Helper: extract common spell damage fields from Nampower event args
-- Nampower events pass data through arg1..argN globals
-- We need to figure out the exact arg layout from KB docs

-- SPELL_DAMAGE_EVENT_SELF / SPELL_DAMAGE_EVENT_OTHER
local function OnSpellDamage()
    -- Nampower SPELL_DAMAGE_EVENT args (from KB):
    -- We need to discover exact arg layout. For now use a safe approach
    -- and log everything in debug mode for discovery
    local data = {
        time = GetTime(),
        type = "DAMAGE",
        source = arg1 or "?",
        target = arg2 or "?",
        sourceGUID = arg3,
        targetGUID = arg4,
        spellID = arg5,
        spellName = arg6 or "?",
        amount = tonumber(arg7) or 0,
        school = tonumber(arg8) or 0,
        crit = (arg9 == 1 or arg9 == true),
    }

    -- Try to get spell name from SpellInfo if we have ID
    if data.spellID and SpellInfo then
        local name = SpellInfo(data.spellID)
        if name then
            data.spellName = name
        end
    end

    -- Pet owner detection
    data.isPet = false
    data.petOwner = nil
    if data.source then
        local owner = P.GetPetOwner(data.source)
        if owner then
            data.isPet = true
            data.petOwner = owner
        end
    end

    P.Debug("DMG: " .. (data.source or "?") .. " -> " .. (data.target or "?") ..
            " [" .. (data.spellName or "?") .. "] " .. data.amount ..
            (data.crit and " CRIT" or ""))

    bus:Fire("DAMAGE", data)
end

-- AUTO_ATTACK_SELF / AUTO_ATTACK_OTHER
local function OnAutoAttack()
    local data = {
        time = GetTime(),
        type = "DAMAGE",
        source = arg1 or "?",
        target = arg2 or "?",
        sourceGUID = arg3,
        targetGUID = arg4,
        spellID = 0,
        spellName = "Auto Attack",
        amount = tonumber(arg5) or 0,
        school = 0,
        crit = (arg6 == 1 or arg6 == true),
    }

    data.isPet = false
    data.petOwner = nil
    if data.source then
        local owner = P.GetPetOwner(data.source)
        if owner then
            data.isPet = true
            data.petOwner = owner
        end
    end

    P.Debug("MELEE: " .. (data.source or "?") .. " -> " .. (data.target or "?") ..
            " " .. data.amount .. (data.crit and " CRIT" or ""))

    bus:Fire("DAMAGE", data)
end

-- SPELL_HEAL_*
local function OnSpellHeal()
    local data = {
        time = GetTime(),
        type = "HEAL",
        source = arg1 or "?",
        target = arg2 or "?",
        sourceGUID = arg3,
        targetGUID = arg4,
        spellID = arg5,
        spellName = arg6 or "?",
        amount = tonumber(arg7) or 0,
        school = tonumber(arg8) or 0,
        crit = (arg9 == 1 or arg9 == true),
        overheal = 0,
    }

    if data.spellID and SpellInfo then
        local name = SpellInfo(data.spellID)
        if name then
            data.spellName = name
        end
    end

    -- Calculate overheal if target is in our group
    local targetUnit = P.FindUnitByName(data.target)
    if targetUnit then
        local hp = UnitHealth(targetUnit)
        local hpMax = UnitHealthMax(targetUnit)
        if hp and hpMax and hpMax > 0 then
            local deficit = hpMax - hp
            if data.amount > deficit then
                data.overheal = data.amount - deficit
            end
        end
    end

    P.Debug("HEAL: " .. (data.source or "?") .. " -> " .. (data.target or "?") ..
            " [" .. (data.spellName or "?") .. "] " .. data.amount ..
            (data.overheal > 0 and (" OH:" .. data.overheal) or ""))

    bus:Fire("HEAL", data)
end

-- SPELL_MISS_*
local function OnSpellMiss()
    local data = {
        time = GetTime(),
        type = "MISS",
        source = arg1 or "?",
        target = arg2 or "?",
        sourceGUID = arg3,
        targetGUID = arg4,
        spellID = arg5,
        spellName = arg6 or "?",
        missType = arg7 or "MISS",
        amount = tonumber(arg8) or 0,
    }

    if data.spellID and SpellInfo then
        local name = SpellInfo(data.spellID)
        if name then
            data.spellName = name
        end
    end

    P.Debug("MISS: " .. (data.source or "?") .. " -> " .. (data.target or "?") ..
            " [" .. (data.spellName or "?") .. "] " .. (data.missType or "?"))

    bus:Fire("MISS", data)
end

-- BUFF_ADDED_* / BUFF_REMOVED_*
local function OnBuffAdded()
    local data = {
        time = GetTime(),
        type = "BUFF",
        target = arg1 or "?",
        spellID = arg2,
        spellName = arg3 or "?",
        gained = true,
    }
    bus:Fire("BUFF", data)
end

local function OnBuffRemoved()
    local data = {
        time = GetTime(),
        type = "BUFF",
        target = arg1 or "?",
        spellID = arg2,
        spellName = arg3 or "?",
        gained = false,
    }
    bus:Fire("BUFF", data)
end

-- SuperWoW: UNIT_CASTEVENT
local function OnUnitCastEvent()
    local data = {
        time = GetTime(),
        type = "CAST",
        sourceGUID = arg1,
        targetGUID = arg2,
        castType = arg3,    -- START, CAST, FAIL, CHANNEL, MAINHAND, OFFHAND
        spellID = arg4,
        duration = arg5,    -- cast duration in ms
        source = "?",
        target = "?",
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

-- SuperWoW: UNIT_DIED
local function OnUnitDied()
    local data = {
        time = GetTime(),
        type = "DEATH",
        name = arg1 or "?",
        guid = arg2,
    }

    P.Debug("DEATH: " .. (data.name or "?"))
    bus:Fire("DEATH", data)
end

---------------------------------------------------------------------------
-- Find unit ID by name (for overheal calculation)
---------------------------------------------------------------------------
function P.FindUnitByName(name)
    if not name then return nil end

    -- Check player
    if UnitName("player") == name then return "player" end

    -- Check raid
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i = 1, numRaid do
            if UnitName("raid" .. i) == name then
                return "raid" .. i
            end
        end
    else
        -- Check party
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

-- Nampower events
bus:RegisterEvent("SPELL_DAMAGE_EVENT_SELF")
bus:RegisterEvent("SPELL_DAMAGE_EVENT_OTHER")
bus:RegisterEvent("AUTO_ATTACK_SELF")
bus:RegisterEvent("AUTO_ATTACK_OTHER")
bus:RegisterEvent("SPELL_HEAL_BY_SELF")
bus:RegisterEvent("SPELL_HEAL_ON_SELF")
bus:RegisterEvent("SPELL_HEAL_BY_OTHER")
bus:RegisterEvent("SPELL_HEAL_ON_OTHER")
bus:RegisterEvent("SPELL_MISS_SELF")
bus:RegisterEvent("SPELL_MISS_OTHER")
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
    elseif event == "BUFF_ADDED_SELF" or event == "BUFF_ADDED_OTHER" then
        OnBuffAdded()
    elseif event == "BUFF_REMOVED_SELF" or event == "BUFF_REMOVED_OTHER" then
        OnBuffRemoved()

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
