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

DL.MELEE_ICON = "Interface\\Icons\\INV_Sword_04"
DL.HEAL_FALLBACK_ICON = "Interface\\Icons\\Spell_Holy_LesserHeal"

-- Consumable spellID -> itemID mapping (from classicdb.ch + scanner)
-- GetItemInfo(itemID) provides both the correct icon and full item name at runtime
-- SpellInfo often returns wrong/fallback icons for consumable use-effects
DL.consumableBySpellID = {
    -- Healing Potions (spellID verified via database.turtlecraft.gg)
    [439]   = 118,         -- Minor Healing Potion
    [440]   = 858,         -- Lesser Healing Potion
    [441]   = 929,         -- Healing Potion
    [2024]  = 1710,        -- Greater Healing Potion
    [4042]  = 3928,        -- Superior Healing Potion
    [17534] = 13446,       -- Major Healing Potion

    -- Mana Potions
    [437]   = 2455,        -- Minor Mana Potion
    [438]   = 3385,        -- Lesser Mana Potion
    [2023]  = 3827,        -- Mana Potion
    [11903] = 6149,        -- Greater Mana Potion
    [17530] = 13443,       -- Superior Mana Potion
    [17531] = 13444,       -- Major Mana Potion

    -- Rejuvenation Potions
    [2370]  = 2456,        -- Minor Rejuvenation Potion
    [22729] = 18253,       -- Major Rejuvenation Potion

    -- Troll's Blood Potions (Regeneration)
    [3219]  = 3382,        -- Weak Troll's Blood Potion
    [3222]  = 3388,        -- Strong Troll's Blood Potion
    [3223]  = 3826,        -- Mighty Troll's Blood Potion
    [24361] = 20004,       -- Major Troll's Blood Potion

    -- Rage Potions
    [6612]  = 5631,        -- Rage Potion
    [6613]  = 5633,        -- Great Rage Potion
    [17528] = 13442,       -- Mighty Rage Potion

    -- Healthstones (Warlock)
    [6262]  = 5512,        -- Minor Healthstone
    [6263]  = 5511,        -- Lesser Healthstone
    [5720]  = 5509,        -- Healthstone
    [5723]  = 5510,        -- Greater Healthstone
    [11732] = 9421,        -- Major Healthstone
    -- Improved Healthstones
    [23468] = 19004,       -- Minor Healthstone (Improved)
    [23469] = 19005,       -- Minor Healthstone (Improved 2)
    [23470] = 19006,       -- Lesser Healthstone (Improved)
    [23471] = 19007,       -- Lesser Healthstone (Improved 2)
    [23472] = 19008,       -- Healthstone (Improved)
    [23473] = 19009,       -- Healthstone (Improved 2)
    [23474] = 19010,       -- Greater Healthstone (Improved)
    [23475] = 19011,       -- Greater Healthstone (Improved 2)
    [23476] = 19012,       -- Major Healthstone (Improved)
    [23477] = 19013,       -- Major Healthstone (Improved 2)

    -- Felwood consumables
    [15700] = 11951,       -- Whipper Root Tuber
    [15701] = 11952,       -- Night Dragon's Breath

    -- Protection Potions (lesser)
    [2380]  = 3384,        -- Minor Magic Resistance Potion
    [7242]  = 6048,        -- Shadow Protection Potion
    [7233]  = 6049,        -- Fire Protection Potion
    [7239]  = 6050,        -- Frost Protection Potion
    [7245]  = 6051,        -- Holy Protection Potion
    [7254]  = 6052,        -- Nature Protection Potion
    [11364] = 9036,        -- Magic Resistance Potion
    [4941]  = 4623,        -- Lesser Stoneshield Potion
    -- Protection Potions (greater)
    [17540] = 13455,       -- Greater Stoneshield Potion
    [17543] = 13457,       -- Greater Fire Protection Potion
    [17544] = 13456,       -- Greater Frost Protection Potion
    [17546] = 13458,       -- Greater Nature Protection Potion
    [17548] = 13459,       -- Greater Shadow Protection Potion
    [17549] = 13461,       -- Greater Arcane Protection Potion

    -- Utility Potions
    [3169]  = 3387,        -- Limited Invulnerability Potion
    [6615]  = 5634,        -- Free Action Potion
    [24364] = 20008,       -- Living Action Potion
    [11359] = 9030,        -- Restorative Potion
    [15822] = 12190,       -- Dreamless Sleep Potion
    [24360] = 20002,       -- Greater Dreamless Sleep Potion
    [2379]  = 2459,        -- Swiftness Potion
    [3680]  = 3823,        -- Lesser Invisibility Potion
    [11392] = 9172,        -- Invisibility Potion
    [7840]  = 6372,        -- Swim Speed Potion
    [11387] = 9144,        -- Wildvine Potion
    [24363] = 20007,       -- Mageblood Potion

    -- Flasks
    [17626] = 13510,       -- Flask of the Titans
    [17627] = 13511,       -- Flask of Distilled Wisdom
    [17628] = 13512,       -- Flask of Supreme Power
    [17629] = 13513,       -- Flask of Chromatic Resistance
    [17624] = 13506,       -- Flask of Petrification

    -- Elixirs (Battle)
    [2367]  = 2454,        -- Elixir of Lion's Strength
    [2374]  = 2457,        -- Elixir of Minor Agility
    [3164]  = 3391,        -- Elixir of Ogre's Strength
    [3160]  = 3390,        -- Elixir of Lesser Agility
    [3166]  = 3383,        -- Elixir of Wisdom
    [7844]  = 6373,        -- Elixir of Firepower
    [8212]  = 6662,        -- Elixir of Giant Growth
    [11328] = 8949,        -- Elixir of Agility
    [11390] = 9155,        -- Arcane Elixir
    [11396] = 9179,        -- Elixir of Greater Intellect
    [11405] = 9206,        -- Elixir of Giants
    [11406] = 9224,        -- Elixir of Demonslaying
    [17535] = 13447,       -- Elixir of the Sages
    [17537] = 13453,       -- Elixir of Brute Force
    [17538] = 13452,       -- Elixir of the Mongoose
    [17539] = 13454,       -- Greater Arcane Elixir
    [26276] = 21546,       -- Elixir of Greater Firepower
    [11474] = 9264,        -- Elixir of Shadow Power
    [21920] = 17708,       -- Elixir of Frost Power

    -- Elixirs (Guardian)
    [673]   = 5997,        -- Elixir of Minor Defense
    [2378]  = 2458,        -- Elixir of Minor Fortitude
    [3220]  = 3389,        -- Elixir of Defense
    [3593]  = 3825,        -- Elixir of Fortitude
    [11334] = 9187,        -- Elixir of Greater Agility
    [11348] = 13445,       -- Elixir of Superior Defense
    [11349] = 8951,        -- Elixir of Greater Defense
    [11371] = 9088,        -- Gift of Arthas
    [26677] = 3386,        -- Elixir of Poison Resistance

    -- Juju
    [16321] = 12459,       -- Juju Escape
    [16322] = 12450,       -- Juju Flurry
    [16323] = 12451,       -- Juju Power
    [16325] = 12457,       -- Juju Chill
    [16326] = 12455,       -- Juju Ember
    [16327] = 12458,       -- Juju Guile
    [16329] = 12460,       -- Juju Might

    -- Runes
    [16666] = 12662,       -- Demonic Rune
    [27869] = 20520,       -- Dark Rune

    -- Food / Drink
    [25804] = 21151,       -- Rumsey Rum Black Label

    -- Bandages (Use-spellID, NOT craft-spellID!)
    [746]   = 1251,        -- Linen Bandage
    [1159]  = 2581,        -- Heavy Linen Bandage
    [3267]  = 3530,        -- Wool Bandage
    [3268]  = 3531,        -- Heavy Wool Bandage
    [7926]  = 6450,        -- Silk Bandage
    [7927]  = 6451,        -- Heavy Silk Bandage
    [10838] = 8544,        -- Mageweave Bandage
    [10839] = 8545,        -- Heavy Mageweave Bandage
    [18608] = 14529,       -- Runecloth Bandage
    [18610] = 14530,       -- Heavy Runecloth Bandage
    [30020] = 23684,       -- Crystal Infused Bandage
    -- BG Bandages
    [23696] = 19307,       -- Alterac Heavy Runecloth Bandage
    [23567] = 19066,       -- Warsong Gulch Runecloth Bandage

    -- Elixirs (Utility/Detection)
    [7178]  = 5996,        -- Elixir of Water Breathing
    [6512]  = 3828,        -- Elixir of Detect Lesser Invisibility
    [11389] = 9154,        -- Elixir of Detect Undead
    [11403] = 9197,        -- Elixir of Dream Vision
    [11407] = 9233,        -- Elixir of Detect Demon
    [12608] = 10592,       -- Catseye Elixir

    -- Other
    [3592]  = 2633,        -- Jungle Remedy
    [17038] = 12820,       -- Winterfall Firewater

    -- TurtleWoW custom
    [19398] = 61675,       -- Nordanaar Herbal Tea
}

-- Fallback: spell name -> itemID (only for spells with unknown spellID)
DL.consumableByName = {
}

DL.spellIconCache = {}
DL.consumableNameCache = {}  -- [spellID] = full item name (e.g. "Nordanaar Herbal Tea")

-- Resolve consumable itemID: check spellID first (exact), then spell name (fallback)
local function ResolveConsumableItemID(spellID, spellName)
    if spellID and DL.consumableBySpellID[spellID] then
        return DL.consumableBySpellID[spellID]
    end
    if spellName and DL.consumableByName[spellName] then
        return DL.consumableByName[spellName]
    end
    return nil
end

function DL.GetSpellIcon(spellID)
    if not spellID then return nil end
    if spellID == 0 then return DL.MELEE_ICON end
    if DL.spellIconCache[spellID] then return DL.spellIconCache[spellID] end
    local name, tex
    if SpellInfo then
        local n, rank, t = SpellInfo(spellID)
        name = n
        tex = t
    end
    -- Check consumable mapping FIRST (SpellInfo often returns wrong fallback icon)
    local itemID = ResolveConsumableItemID(spellID, name)
    if itemID and GetItemInfo then
        local itemName, _, _, _, _, _, _, _, itemTex = GetItemInfo(itemID)
        if itemTex then
            DL.spellIconCache[spellID] = itemTex
            if itemName then
                DL.consumableNameCache[spellID] = itemName
            end
            return itemTex
        end
    end
    -- Fallback: use SpellInfo texture
    if tex then
        DL.spellIconCache[spellID] = tex
        return tex
    end
    return nil
end

-- Returns full item name for consumables, or nil for regular spells
function DL.GetConsumableName(spellID)
    if not spellID then return nil end
    return DL.consumableNameCache[spellID]
end

local function FindSourceRaidTarget(sourceName)
    if not sourceName or not GetRaidTargetIndex then return nil end
    if UnitName("target") == sourceName then return GetRaidTargetIndex("target") end
    if UnitName("targettarget") == sourceName then return GetRaidTargetIndex("targettarget") end
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do
            if UnitName("raid" .. i .. "target") == sourceName then
                return GetRaidTargetIndex("raid" .. i .. "target")
            end
        end
    else
        for i = 1, 4 do
            if UnitName("party" .. i .. "target") == sourceName then
                return GetRaidTargetIndex("party" .. i .. "target")
            end
        end
    end
    return nil
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
    local buffs, debuffs = SnapshotAuras(unit)

    local raidTarget = FindSourceRaidTarget(data.source)

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
        manaAfter = manaAfter,
        manaMax = manaMax,
        powerType = powerType,
        buffs = buffs,
        debuffs = debuffs,
        raidTarget = raidTarget,
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
    local buffs, debuffs = SnapshotAuras(unit)

    local raidTarget = FindSourceRaidTarget(data.source)

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
        manaAfter = manaAfter,
        manaMax = manaMax,
        powerType = powerType,
        buffs = buffs,
        debuffs = debuffs,
        raidTarget = raidTarget,
    })
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
    local buffs, debuffs = SnapshotAuras(unit)

    local raidTarget = FindSourceRaidTarget(data.source)

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
        manaAfter = manaAfter,
        manaMax = manaMax,
        powerType = powerType,
        buffs = buffs,
        debuffs = debuffs,
        raidTarget = raidTarget,
    })
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
    local buffs, debuffs = SnapshotAuras(unit)

    local raidTarget = FindSourceRaidTarget(data.target)

    PushIntake(data.source, {
        time = data.time or GetTime(),
        etype = "OUTGOING",
        source = data.source,
        target = data.target or "?",
        spell = data.spellName or "Melee",
        spellID = data.spellID,
        amount = data.amount or 0,
        school = data.school or 0,
        crit = data.crit or false,
        hpAfter = hpAfter,
        hpMax = hpMax,
        overkill = 0,
        missType = nil,
        manaAfter = manaAfter,
        manaMax = manaMax,
        powerType = powerType,
        buffs = buffs,
        debuffs = debuffs,
        raidTarget = raidTarget,
    })
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
    local buffs, debuffs = SnapshotAuras(unit)

    PushIntake(data.target, {
        time = data.time or GetTime(),
        etype = "BUFF",
        source = data.target,  -- self-cast
        spell = data.spellName or "Buff",
        spellID = data.spellID,
        amount = 0,
        school = 0,
        crit = false,
        hpAfter = hpAfter,
        hpMax = hpMax,
        overkill = 0,
        missType = nil,
        manaAfter = manaAfter,
        manaMax = manaMax,
        powerType = powerType,
        buffs = buffs,
        debuffs = debuffs,
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
P.eventBus:Register("DAMAGE", OnOutgoingDamage)
P.eventBus:Register("HEAL", OnHealIntake)
P.eventBus:Register("MISS", OnMissIntake)
P.eventBus:Register("BUFF", OnBuffIntake)
P.eventBus:Register("DEATH", OnDeath)
