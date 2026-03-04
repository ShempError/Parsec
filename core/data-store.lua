-- Parsec: Data Store
-- Player data accumulators, single accumulating segment

local P = Parsec
if not P then return end

table.insert(P._loadedFiles, "data-store")

P.dataStore = {}
local DS = P.dataStore

DS.classes = {}  -- { [name] = "WARRIOR", ... }

local function NewPlayerEntry()
    return {
        damage_total = 0,
        damage_spells = {},
        heal_total = 0,
        heal_effective = 0,
        heal_overheal = 0,
        heal_spells = {},
        drain_received = 0,
        drain_spells = {},
        first_action = 0,
        last_action = 0,
    }
end

local function NewSegment()
    return {
        players = {},
        startTime = GetTime(),
    }
end

DS.current = NewSegment()

-- Get or create player entry
function DS:GetPlayer(name)
    if not self.current.players[name] then
        self.current.players[name] = NewPlayerEntry()
    end
    return self.current.players[name]
end

-- Add damage for a player
function DS:AddDamage(source, target, spellName, amount, crit)
    if not source or not spellName then return end
    local now = GetTime()

    local p = self:GetPlayer(source)
    p.damage_total = p.damage_total + amount
    if p.first_action == 0 then p.first_action = now end
    p.last_action = now

    if not p.damage_spells[spellName] then
        p.damage_spells[spellName] = { total = 0, hits = 0, crits = 0, min = 999999, max = 0 }
    end
    local sp = p.damage_spells[spellName]
    sp.total = sp.total + amount
    sp.hits = sp.hits + 1
    if crit then sp.crits = sp.crits + 1 end
    if amount < sp.min then sp.min = amount end
    if amount > sp.max then sp.max = amount end
end

-- Add healing for a player
function DS:AddHeal(source, target, spellName, amount, overheal, crit)
    if not source or not spellName then return end
    local effective = amount - (overheal or 0)
    local now = GetTime()

    local p = self:GetPlayer(source)
    p.heal_total = p.heal_total + amount
    p.heal_effective = p.heal_effective + effective
    p.heal_overheal = p.heal_overheal + (overheal or 0)
    if p.first_action == 0 then p.first_action = now end
    p.last_action = now

    if not p.heal_spells[spellName] then
        p.heal_spells[spellName] = { total = 0, effective = 0, overheal = 0, hits = 0, crits = 0 }
    end
    local sp = p.heal_spells[spellName]
    sp.total = sp.total + amount
    sp.effective = sp.effective + effective
    sp.overheal = sp.overheal + (overheal or 0)
    sp.hits = sp.hits + 1
    if crit then sp.crits = sp.crits + 1 end
end

-- Add resource drain received by a player
function DS:AddDrain(target, source, spellName, amount, resource)
    if not target or not spellName then return end
    local now = GetTime()

    local p = self:GetPlayer(target)
    p.drain_received = p.drain_received + amount
    if p.first_action == 0 then p.first_action = now end
    p.last_action = now

    local key = spellName
    if not p.drain_spells[key] then
        p.drain_spells[key] = { total = 0, hits = 0, resource = resource or "Mana", source = source or "?" }
    end
    local sp = p.drain_spells[key]
    sp.total = sp.total + amount
    sp.hits = sp.hits + 1
end

-- Get sorted player list for a view
-- viewType: "damage", "healing", "effheal"
-- Returns: sorted, duration, raidTotal
function DS:GetSorted(viewType)
    local duration = P.combatState:GetDuration()
    if duration < 1 then duration = 1 end

    local sorted = {}
    local raidTotal = 0

    for name, data in pairs(self.current.players) do
        local value = 0
        if viewType == "damage" then
            value = data.damage_total
        elseif viewType == "healing" then
            value = data.heal_total
        elseif viewType == "effheal" then
            value = data.heal_effective
        elseif viewType == "drains" then
            value = data.drain_received
        end

        if value > 0 then
            raidTotal = raidTotal + value
            table.insert(sorted, {
                name = name,
                value = value,
                raw = data,
            })
        end
    end

    table.sort(sorted, function(a, b) return a.value > b.value end)

    return sorted, duration, raidTotal
end

-- Full reset
function DS:Reset()
    self.current = NewSegment()
    if P.combatState then
        P.combatState:Reset()
    end
    P.Print("Data reset.")
end
