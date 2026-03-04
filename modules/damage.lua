-- Parsec: Damage Module
-- Wires DAMAGE events from eventbus to data store

local P = Parsec
if not P or not P.eventBus then return end

table.insert(P._loadedFiles, "damage")

local function OnDamage(data)
    if not P.dataStore then return end

    local source = data.source
    -- Attribute pet damage to owner
    if data.isPet and data.petOwner then
        source = data.petOwner
    elseif not P.IsGroupMember(source) and data.sourceGUID then
        -- Fallback: source not in group, try pet lookup (may have been missed earlier)
        local owner = P.GetPetOwnerByGUID(data.sourceGUID)
        if owner then
            source = owner
        end
    end

    -- Only record damage from group members (filters NPCs + enemy faction)
    if not P.IsGroupMember(source) then return end

    -- Filter friendly fire: skip damage where target is also a group member
    -- (e.g. Plague Effect debuff ticking on raid members)
    if data.target and P.IsGroupMember(data.target) then return end

    P.dataStore:AddDamage(source, data.target, data.spellName, data.amount, data.crit)
end

-- Register with event bus
P.eventBus:Register("DAMAGE", OnDamage)
