-- Parsec: Damage Module
-- Wires DAMAGE events from eventbus to data store

local P = Parsec

local function OnDamage(data)
    if not P.dataStore then return end

    local source = data.source
    -- Attribute pet damage to owner
    if data.isPet and data.petOwner then
        source = data.petOwner
    end

    P.dataStore:AddDamage(source, data.target, data.spellName, data.amount, data.crit)
end

-- Register with event bus
P.eventBus:Register("DAMAGE", OnDamage)
