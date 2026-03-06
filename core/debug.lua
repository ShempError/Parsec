-- Parsec: Debug System
-- Event dumping, stats, diagnostics

local P = Parsec
if not P then return end

table.insert(P._loadedFiles, "debug")

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
    end

    -- Memory usage
    local mem = gcinfo()
    P.Print("Addon memory: " .. string.format("%.0f", mem) .. " KB")
end

-- Show missed/unparsed events (replaces removed ring buffer)
function P.ShowMissedEvents(count)
    count = count or 20
    P.Print("--- Last " .. count .. " Missed Events ---")
    local total = table.getn(P.missedEvents)
    if total == 0 then
        P.Print("No missed events recorded.")
        return
    end
    local start = total - count + 1
    if start < 1 then start = 1 end
    for i = start, total do
        local e = P.missedEvents[i]
        P.Print(e.time .. " [" .. e.event .. "] " .. e.msg)
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
