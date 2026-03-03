-- Parsec: Bootstrap
-- Addon initialization, dependency checks, slash commands, CVar setup

local P = Parsec
if not P then
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[Parsec] FATAL: Parsec global is nil in bootstrap.lua! Earlier file failed to load.|r")
    end
    return
end

table.insert(P._loadedFiles, "bootstrap")

---------------------------------------------------------------------------
-- Dependency Check
---------------------------------------------------------------------------

local function CheckDependencies()
    local ok = true

    -- Check SuperWoW (SpellInfo is a good indicator)
    if not SpellInfo then
        P.Print("|cffff4444SuperWoW not detected!|r Parsec requires SuperWoW to function.")
        ok = false
    end

    -- Check Nampower (GetNampowerVersion exists when loaded)
    if not GetNampowerVersion then
        P.Print("|cffff4444Nampower not detected!|r Parsec requires Nampower to function.")
        ok = false
    end

    return ok
end

---------------------------------------------------------------------------
-- Enable Nampower CVars
---------------------------------------------------------------------------

local function SetupCVars()
    if not SetCVar then return end

    -- Only CVars that are disabled by default and needed by Parsec
    -- Spell damage + miss + buff events are always active (no CVar needed)
    local cvars = {
        "NP_EnableAutoAttackEvents",
        "NP_EnableSpellHealEvents",
    }

    local enabled = 0
    for i = 1, table.getn(cvars) do
        local current = GetCVar(cvars[i])
        if current ~= nil then
            if current ~= "1" then
                SetCVar(cvars[i], "1")
                P.Debug("Enabled CVar: " .. cvars[i])
            end
            enabled = enabled + 1
        end
    end

    if enabled > 0 then
        P.Debug("Nampower CVars OK (" .. enabled .. "/" .. table.getn(cvars) .. ")")
    end
end

---------------------------------------------------------------------------
-- Slash Commands
---------------------------------------------------------------------------

SLASH_PARSEC1 = "/parsec"
SLASH_PARSEC2 = "/pc"

SlashCmdList["PARSEC"] = function(msg)
    -- Use Parsec global directly (not upvalue P) for resilience
    local pp = Parsec
    if not pp then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[Parsec] Addon not loaded properly. Check for errors above.|r")
        end
        return
    end

    msg = string.lower(msg or "")

    if msg == "" or msg == "toggle" then
        pp.ToggleWindow()

    elseif msg == "show" then
        if ParsecWindow then
            ParsecWindow:Show()
            pp.UpdateWindow()
        end

    elseif msg == "hide" then
        if ParsecWindow then
            ParsecWindow:Hide()
        end

    elseif msg == "reset" then
        if pp.dataStore then
            pp.dataStore:Reset()
            pp.UpdateWindow()
        end

    elseif msg == "debug" then
        pp.ToggleDebug()

    elseif msg == "stats" then
        pp.ShowStats()

    elseif msg == "diag" then
        -- Diagnostic: show which files loaded
        pp.Print("--- Load Diagnostics ---")
        pp.Print("Loaded files: " .. table.concat(pp._loadedFiles, ", "))
        pp.Print("ParsecWindow: " .. (ParsecWindow and "OK" or "|cffff4444NIL|r"))
        pp.Print("eventBus: " .. (pp.eventBus and "OK" or "|cffff4444NIL|r"))
        pp.Print("combatState: " .. (pp.combatState and "OK" or "|cffff4444NIL|r"))
        pp.Print("dataStore: " .. (pp.dataStore and "OK" or "|cffff4444NIL|r"))
        pp.Print("window: " .. (pp.window and "OK" or "|cffff4444NIL|r"))

    elseif string.sub(msg, 1, 6) == "events" then
        local count = tonumber(string.sub(msg, 8)) or 10
        pp.ShowEvents(count)

    elseif msg == "damage" or msg == "dmg" then
        pp.window.viewType = "damage"
        pp.UpdateWindow()

    elseif msg == "dps" then
        pp.window.viewType = "dps"
        pp.UpdateWindow()

    elseif msg == "healing" or msg == "heal" then
        pp.window.viewType = "healing"
        pp.UpdateWindow()

    elseif msg == "hps" then
        pp.window.viewType = "hps"
        pp.UpdateWindow()

    elseif msg == "dump" then
        pp.DumpArgs("ManualDump")

    elseif msg == "help" then
        pp.Print("--- Parsec Commands ---")
        pp.Print("/parsec - Toggle window")
        pp.Print("/parsec reset - Reset all data")
        pp.Print("/parsec debug - Toggle debug output")
        pp.Print("/parsec stats - Show statistics")
        pp.Print("/parsec diag - Load diagnostics")
        pp.Print("/parsec events [n] - Show last N events")
        pp.Print("/parsec dmg|dps|heal|hps - Switch view")
        pp.Print("/parsec dump - Dump current event args")
        pp.Print("Right-click title = cycle view")
        pp.Print("Middle-click title = cycle segment")
        pp.Print("Scroll wheel = scroll bars")
    else
        pp.Print("Unknown command: " .. msg .. " (try /parsec help)")
    end
end

---------------------------------------------------------------------------
-- Initialization
---------------------------------------------------------------------------

local initFrame = CreateFrame("Frame", "ParsecInit")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function()
    initFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")

    -- Use Parsec global directly
    local pp = Parsec
    if not pp then return end

    pp.Print("v" .. pp.VERSION .. " loaded.")
    pp.Print("Files: " .. table.concat(pp._loadedFiles, ", "))

    -- Check dependencies
    local depsOK = CheckDependencies()
    if depsOK then
        pp.Print("|cff00ff00SuperWoW + Nampower detected.|r")
    end

    -- Setup Nampower CVars
    SetupCVars()

    -- Initial class scan
    pp.ScanGroupClasses()

    -- Show window by default
    if ParsecWindow then
        ParsecWindow:Show()
        pp.UpdateWindow()
    else
        pp.Print("|cffff4444ParsecWindow frame not created! Check window.xml|r")
    end
end)
