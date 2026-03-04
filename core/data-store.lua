-- Parsec: Data Store
-- Player data accumulators, dual-segment architecture (current + overall)

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
        first_action = 0,
        last_action = 0,
    }
end

local function NewSegment()
    return {
        players = {},
        startTime = GetTime(),
        duration = 0,
    }
end

DS.current = NewSegment()
DS.overall = NewSegment()

---------------------------------------------------------------------------
-- Get or create player entry in a segment
---------------------------------------------------------------------------

function DS:GetPlayer(name, segment)
    local seg = segment or self.current
    if not seg.players[name] then
        seg.players[name] = NewPlayerEntry()
    end
    return seg.players[name]
end

---------------------------------------------------------------------------
-- Internal: apply damage to a single segment
---------------------------------------------------------------------------

local function ApplyDamage(seg, source, spellName, amount, crit)
    local p = seg.players[source]
    if not p then
        p = NewPlayerEntry()
        seg.players[source] = p
    end
    local now = GetTime()

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

---------------------------------------------------------------------------
-- Internal: apply healing to a single segment
---------------------------------------------------------------------------

local function ApplyHeal(seg, source, spellName, amount, overheal, crit)
    local p = seg.players[source]
    if not p then
        p = NewPlayerEntry()
        seg.players[source] = p
    end
    local effective = amount - (overheal or 0)
    local now = GetTime()

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

---------------------------------------------------------------------------
-- Public: Add damage (writes to both segments)
---------------------------------------------------------------------------

function DS:AddDamage(source, target, spellName, amount, crit)
    if not source or not spellName then return end
    ApplyDamage(self.current, source, spellName, amount, crit)
    ApplyDamage(self.overall, source, spellName, amount, crit)
end

---------------------------------------------------------------------------
-- Public: Add healing (writes to both segments)
---------------------------------------------------------------------------

function DS:AddHeal(source, target, spellName, amount, overheal, crit)
    if not source or not spellName then return end
    ApplyHeal(self.current, source, spellName, amount, overheal, crit)
    ApplyHeal(self.overall, source, spellName, amount, overheal, crit)
end

---------------------------------------------------------------------------
-- Get effective duration for a segment
-- Uses combatState timer, falls back to player activity timestamps
-- (handles /reload during combat where combatState resets to 0)
---------------------------------------------------------------------------

function DS:GetDuration(segment)
    local seg = self.current
    if segment == "overall" then seg = self.overall end

    local duration = P.combatState:GetDuration(segment)

    if duration < 1 then
        local minFirst, maxLast
        for name, data in pairs(seg.players) do
            if string.sub(name, 1, 2) ~= "0x" and data.first_action > 0 then
                if not minFirst or data.first_action < minFirst then
                    minFirst = data.first_action
                end
                if data.last_action > 0 and (not maxLast or data.last_action > maxLast) then
                    maxLast = data.last_action
                end
            end
        end
        if minFirst and maxLast then
            duration = maxLast - minFirst
        end
    end
    if duration < 1 then duration = 1 end
    return duration
end

---------------------------------------------------------------------------
-- Get sorted player list for a view
-- viewType: "damage", "healing", "effheal", "drains", "dps", "hps"
-- segment: "current" or "overall" (default: "current")
---------------------------------------------------------------------------

function DS:GetSorted(viewType, segment)
    local seg = self.current
    if segment == "overall" then seg = self.overall end

    local duration = self:GetDuration(segment)

    local sorted = {}
    local raidTotal = 0

    for name, data in pairs(seg.players) do
        -- Skip GUID entries (unresolved names like "0x00000000...")
        if string.sub(name, 1, 2) ~= "0x" then
            local value = 0
            if viewType == "damage" then
                value = data.damage_total
            elseif viewType == "healing" then
                value = data.heal_total
            elseif viewType == "effheal" then
                value = data.heal_effective
            elseif viewType == "dps" then
                local playerDur = data.last_action - data.first_action
                if playerDur < 1 then playerDur = duration end
                value = data.damage_total / playerDur
            elseif viewType == "hps" then
                local playerDur = data.last_action - data.first_action
                if playerDur < 1 then playerDur = duration end
                value = data.heal_effective / playerDur
            end

            -- Include player if they have ANY combat activity
            local hasActivity = data.damage_total > 0 or data.heal_total > 0

            if hasActivity then
                raidTotal = raidTotal + value
                table.insert(sorted, {
                    name = name,
                    value = value,
                    raw = data,
                })
            end
        end
    end

    table.sort(sorted, function(a, b) return a.value > b.value end)

    return sorted, duration, raidTotal
end

---------------------------------------------------------------------------
-- Reset current segment only (called on combat end)
---------------------------------------------------------------------------

function DS:ResetCurrent()
    self.current = NewSegment()
end

---------------------------------------------------------------------------
-- Reset everything (both segments)
---------------------------------------------------------------------------

function DS:ResetAll()
    self.current = NewSegment()
    self.overall = NewSegment()
    if P.combatState then
        P.combatState:Reset()
    end
    P.Print("All data reset.")
end

---------------------------------------------------------------------------
-- Legacy compat: full reset
---------------------------------------------------------------------------

function DS:Reset()
    self:ResetAll()
end
