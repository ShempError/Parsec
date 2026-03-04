-- Parsec: Drains Module
-- Tracks resource drains (Mana Drain, etc.) received by group members

local P = Parsec
if not P then return end

table.insert(P._loadedFiles, "drains")

local function OnDrain(data)
    if not P.dataStore then return end

    -- Only track during combat
    if P.combatState and not P.combatState:InCombat() then return end

    -- Only track drains on group members
    if not P.IsGroupMember(data.target) then return end

    P.dataStore:AddDrain(data.target, data.source, data.spellName, data.amount, data.resource)
end

P.eventBus:Subscribe("DRAIN", OnDrain)
