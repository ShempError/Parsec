-- Parsec: Consumable SpellID -> ItemID Mappings
-- Shared lookup table for resolving consumable use-effect spellIDs to their source itemIDs.
-- GetItemInfo(itemID) provides both the correct icon and full item name at runtime,
-- while SpellInfo often returns wrong/fallback icons for consumable use-effects.
--
-- Verified against classicdb.ch and database.turtlecraft.gg (2026-03-05).
-- IMPORTANT: Use the USE-spell ID (the buff/effect spell), NOT the craft-spell ID.

local P = Parsec
if not P then return end

table.insert(P._loadedFiles, "consumables")

P.consumables = {}
local C = P.consumables

---------------------------------------------------------------------------
-- SpellID -> ItemID mapping table
---------------------------------------------------------------------------

C.bySpellID = {
    -- Healing Potions
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

    -- Elixirs (Utility/Detection)
    [7178]  = 5996,        -- Elixir of Water Breathing
    [6512]  = 3828,        -- Elixir of Detect Lesser Invisibility
    [11389] = 9154,        -- Elixir of Detect Undead
    [11403] = 9197,        -- Elixir of Dream Vision
    [11407] = 9233,        -- Elixir of Detect Demon
    [12608] = 10592,       -- Catseye Elixir

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
    [22790] = 18284,       -- Kreeg's Stout Beatdown (+25 spirit, -5 int)

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

    -- Other
    [3592]  = 2633,        -- Jungle Remedy
    [17038] = 12820,       -- Winterfall Firewater

    -- TurtleWoW custom
    [19398] = 61675,       -- Nordanaar Herbal Tea
    -- TurtleWoW custom elixirs
    [45427] = 61224,       -- Dreamshard Elixir (+2% spell crit, +15 SP, +15 healing)
    [45489] = 61423,       -- Dreamtonic (+35 spell damage)
    -- TurtleWoW custom food (Well Fed buffs)
    [57043] = 60977,       -- Danonzo's Tel'Abim Delight (+22 spell damage)
    [57045] = 60978,       -- Danonzo's Tel'Abim Medley (+2% haste)
    [57055] = 60976,       -- Danonzo's Tel'Abim Surprise (+45 ranged AP)
    [46084] = 53015,       -- Gurubashi Gumbo (+10 sta, -3% crit/dot taken)
    [49552] = 83309,       -- Empowering Herbal Salad (+24 healing)
    [45624] = 84040,       -- Le Fishe Au Chocolat (+1% dodge, +4 defense)
    -- TurtleWoW custom drinks
    [57106] = 61174,       -- Medivh's Merlot (+25 stamina)
    [57107] = 61175,       -- Medivh's Merlot Blue (+15 intellect)
}

-- Fallback: spell name -> itemID (for spells with unknown spellID)
C.byName = {}

---------------------------------------------------------------------------
-- Lookup: resolve spellID/spellName to itemID
---------------------------------------------------------------------------

function C:Resolve(spellID, spellName)
    if spellID and self.bySpellID[spellID] then
        return self.bySpellID[spellID]
    end
    if spellName and self.byName[spellName] then
        return self.byName[spellName]
    end
    return nil
end

---------------------------------------------------------------------------
-- Icon + Name resolution (with caching)
---------------------------------------------------------------------------

C.iconCache = {}   -- [spellID] = texturePath
C.nameCache = {}   -- [spellID] = full item name

local MELEE_ICON = "Interface\\Icons\\INV_Sword_04"

function C:GetIcon(spellID)
    if not spellID then return nil end
    if spellID == 0 then return MELEE_ICON end
    if self.iconCache[spellID] then return self.iconCache[spellID] end

    local name, tex
    if SpellInfo then
        local n, rank, t = SpellInfo(spellID)
        name = n
        tex = t
    end

    -- Check consumable mapping FIRST (SpellInfo often returns wrong fallback icon)
    local itemID = self:Resolve(spellID, name)
    if itemID and GetItemInfo then
        local itemName, _, _, _, _, _, _, _, itemTex = GetItemInfo(itemID)
        if itemTex then
            self.iconCache[spellID] = itemTex
            if itemName then
                self.nameCache[spellID] = itemName
            end
            return itemTex
        end
    end

    -- Fallback: use SpellInfo texture
    if tex then
        self.iconCache[spellID] = tex
        return tex
    end
    return nil
end

-- Returns full item name for consumables, or nil for regular spells
function C:GetName(spellID)
    if not spellID then return nil end
    return self.nameCache[spellID]
end
