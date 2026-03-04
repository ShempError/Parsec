-- Parsec: Energize Module
-- Tracks mana gains (Mana Spring, Innervate, JoW procs, etc.) received by group members

local P = Parsec
if not P then return end

table.insert(P._loadedFiles, "energize")

local function OnEnergize(data)
    if not P.dataStore then return end

    -- Only track during combat
    if P.combatState and not P.combatState:InCombat() then return end

    -- Only track mana gains on group members
    if not P.IsGroupMember(data.target) then return end

    P.dataStore:AddManaGain(data.target, data.source, data.spellName, data.amount)
end

P.eventBus:Register("ENERGIZE", OnEnergize)
