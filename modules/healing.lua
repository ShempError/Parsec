-- Parsec: Healing Module
-- Wires HEAL events from eventbus to data store

local P = Parsec

local function OnHeal(data)
    if not P.dataStore then return end
    P.dataStore:AddHeal(data.source, data.target, data.spellName, data.amount, data.overheal, data.crit)
end

-- Register with event bus
P.eventBus:Register("HEAL", OnHeal)
