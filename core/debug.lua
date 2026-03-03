-- Parsec: Debug System
-- Event dumping, stats, diagnostics

local P = Parsec

P.debugMode = false

-- Toggle debug mode
function P.ToggleDebug()
    P.debugMode = not P.debugMode
    P.Print("Debug mode: " .. (P.debugMode and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

-- Show event statistics
function P.ShowStats()
    local bus = P.eventBus
    P.Print("--- Parsec Stats ---")
    P.Print("Events processed: " .. bus.eventCount)
    P.Print("Debug mode: " .. (P.debugMode and "ON" or "OFF"))

    if P.combatState then
        P.Print("Combat state: " .. P.combatState.state)
        if P.combatState:InCombat() then
            P.Print("Duration: " .. P.FormatTime(P.combatState:GetDuration()))
        end
        P.Print("Overall time: " .. P.FormatTime(P.combatState.overallDuration))
    end

    if P.dataStore then
        local numCurrent = 0
        for _ in pairs(P.dataStore.current.players) do numCurrent = numCurrent + 1 end
        local numOverall = 0
        for _ in pairs(P.dataStore.overall.players) do numOverall = numOverall + 1 end
        P.Print("Players (current): " .. numCurrent)
        P.Print("Players (overall): " .. numOverall)
        P.Print("History segments: " .. table.getn(P.dataStore.history))
    end

    -- Memory usage
    local mem = gcinfo()
    P.Print("Addon memory: " .. string.format("%.0f", mem) .. " KB")
end

-- Show last N events from ring buffer
function P.ShowEvents(count)
    local bus = P.eventBus
    count = count or 10
    P.Print("--- Last " .. count .. " Events ---")

    local idx = bus.lastEventsIdx
    local max = bus.lastEventsMax
    local shown = 0

    for i = 0, max - 1 do
        if shown >= count then break end
        local pos = ((idx - 1 - i) % max) + 1
        local ev = bus.lastEvents[pos]
        if ev then
            local line = (ev.type or "?") .. ": "
            if ev.source then line = line .. ev.source end
            if ev.target then line = line .. " -> " .. ev.target end
            if ev.spellName then line = line .. " [" .. ev.spellName .. "]" end
            if ev.amount then line = line .. " " .. ev.amount end
            P.Print(line)
            shown = shown + 1
        end
    end

    if shown == 0 then
        P.Print("No events recorded yet.")
    end
end

-- Dump raw arg values for event discovery
function P.DumpArgs(label)
    local parts = { label or "ARGS:" }
    for i = 1, 20 do
        local a = getglobal("arg" .. i)
        if a ~= nil then
            table.insert(parts, "arg" .. i .. "=" .. tostring(a))
        end
    end
    P.Print(table.concat(parts, " | "))
end
