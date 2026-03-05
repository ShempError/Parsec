-- Parsec: Healing Module
-- Wires HEAL events from eventbus to data store

local P = Parsec
if not P or not P.eventBus then return end

table.insert(P._loadedFiles, "healing")

local function OnHeal(data)
    if not P.dataStore then return end
    if P.settings.modules and not P.settings.modules.healing then return end

    -- Only record healing during combat (like DPSMate)
    if P.combatState and not P.combatState:InCombat() then return end

    -- Only record healing from group members (unless trackAll is on)
    if not P.settings.trackAll and not P.IsGroupMember(data.source) then return end

    P.dataStore:AddHeal(data.source, data.target, data.spellName, data.amount, data.overheal, data.crit, data.periodic)
end

-- Register with event bus
P.eventBus:Register("HEAL", OnHeal)
