-- Parsec: Data Store
-- Player registry, per-player accumulators, segment management

local P = Parsec

P.dataStore = {}
local DS = P.dataStore

DS.classes = {}  -- { [name] = "WARRIOR", ... }

-- Segment structure:
-- segment.players[name] = {
--   damage_total = 0,
--   damage_spells = { [spellName] = { total=0, hits=0, crits=0, min=999999, max=0 } },
--   heal_total = 0,
--   heal_effective = 0,
--   heal_overheal = 0,
--   heal_spells = { [spellName] = { total=0, effective=0, overheal=0, hits=0, crits=0 } },
--   combat_time = 0,
--   first_action = 0,
--   last_action = 0,
-- }

local function NewPlayerEntry()
    return {
        damage_total = 0,
        damage_spells = {},
        heal_total = 0,
        heal_effective = 0,
        heal_overheal = 0,
        heal_spells = {},
        combat_time = 0,
        first_action = 0,
        last_action = 0,
    }
end

local function NewSegment()
    return {
        players = {},
        startTime = GetTime(),
        endTime = 0,
        duration = 0,
        name = "Current",
        primaryTarget = nil,
        targetDamage = {},  -- { [targetName] = totalDamage } for naming
    }
end

DS.current = NewSegment()
DS.overall = NewSegment()
DS.overall.name = "Overall"
DS.history = {}  -- completed segments
DS.maxHistory = 10

-- Get or create player entry in a segment
function DS:GetPlayer(segment, name)
    if not segment.players[name] then
        segment.players[name] = NewPlayerEntry()
    end
    return segment.players[name]
end

-- Add damage for a player
function DS:AddDamage(source, target, spellName, amount, crit)
    if not source or not spellName then return end
    local now = GetTime()

    -- Current segment
    local p = self:GetPlayer(self.current, source)
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

    -- Track target for segment naming
    if target then
        self.current.targetDamage[target] = (self.current.targetDamage[target] or 0) + amount
    end

    -- Overall segment
    local po = self:GetPlayer(self.overall, source)
    po.damage_total = po.damage_total + amount
    if po.first_action == 0 then po.first_action = now end
    po.last_action = now

    if not po.damage_spells[spellName] then
        po.damage_spells[spellName] = { total = 0, hits = 0, crits = 0, min = 999999, max = 0 }
    end
    local spo = po.damage_spells[spellName]
    spo.total = spo.total + amount
    spo.hits = spo.hits + 1
    if crit then spo.crits = spo.crits + 1 end
    if amount < spo.min then spo.min = amount end
    if amount > spo.max then spo.max = amount end
end

-- Add healing for a player
function DS:AddHeal(source, target, spellName, amount, overheal, crit)
    if not source or not spellName then return end
    local effective = amount - (overheal or 0)
    local now = GetTime()

    -- Current segment
    local p = self:GetPlayer(self.current, source)
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

    -- Overall segment
    local po = self:GetPlayer(self.overall, source)
    po.heal_total = po.heal_total + amount
    po.heal_effective = po.heal_effective + effective
    po.heal_overheal = po.heal_overheal + (overheal or 0)
    if po.first_action == 0 then po.first_action = now end
    po.last_action = now

    if not po.heal_spells[spellName] then
        po.heal_spells[spellName] = { total = 0, effective = 0, overheal = 0, hits = 0, crits = 0 }
    end
    local spo = po.heal_spells[spellName]
    spo.total = spo.total + amount
    spo.effective = spo.effective + effective
    spo.overheal = spo.overheal + (overheal or 0)
    spo.hits = spo.hits + 1
    if crit then spo.crits = spo.crits + 1 end
end

-- Start new combat segment
function DS:NewSegment()
    self.current = NewSegment()
end

-- Finalize current segment (combat ended)
function DS:FinalizeSegment(duration)
    self.current.endTime = GetTime()
    self.current.duration = duration

    -- Name the segment by most-damaged target
    local maxDmg = 0
    local maxTarget = "Unknown"
    for target, dmg in pairs(self.current.targetDamage) do
        if dmg > maxDmg then
            maxDmg = dmg
            maxTarget = target
        end
    end
    self.current.name = maxTarget

    -- Store in history (push, pop oldest if full)
    table.insert(self.history, 1, self.current)
    if table.getn(self.history) > self.maxHistory then
        table.remove(self.history)
    end

    P.Debug("Segment saved: " .. self.current.name .. " (" .. P.FormatTime(duration) .. ")")
end

-- Get sorted player list for a view
-- viewType: "damage", "dps", "healing", "hps"
-- segment: self.current or self.overall
function DS:GetSorted(viewType, segment)
    if not segment then segment = self.current end
    local duration = 1

    if segment == self.current then
        duration = P.combatState:GetDuration()
        if duration < 1 then duration = 1 end
    elseif segment == self.overall then
        duration = P.combatState.overallDuration
        if duration < 1 then duration = 1 end
    else
        duration = segment.duration
        if duration < 1 then duration = 1 end
    end

    local sorted = {}
    for name, data in pairs(segment.players) do
        local value = 0
        if viewType == "damage" then
            value = data.damage_total
        elseif viewType == "dps" then
            local playerDuration = data.last_action - data.first_action
            if playerDuration < 1 then playerDuration = duration end
            value = data.damage_total / playerDuration
        elseif viewType == "healing" then
            value = data.heal_effective
        elseif viewType == "hps" then
            local playerDuration = data.last_action - data.first_action
            if playerDuration < 1 then playerDuration = duration end
            value = data.heal_effective / playerDuration
        end

        if value > 0 then
            table.insert(sorted, {
                name = name,
                value = value,
                raw = data,
            })
        end
    end

    -- Sort descending by value
    table.sort(sorted, function(a, b)
        return a.value > b.value
    end)

    return sorted, duration
end

-- Full reset
function DS:Reset()
    self.current = NewSegment()
    self.overall = NewSegment()
    self.overall.name = "Overall"
    self.history = {}
    P.combatState.overallDuration = 0
    P.Print("Data reset.")
end
