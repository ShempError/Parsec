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
        "NP_EnableSpellGoEvents",  -- for totem ownership tracking
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
        pp.ShowAllWindows()

    elseif msg == "hide" then
        pp.HideAllWindows()

    elseif msg == "reset" or msg == "resetall" then
        if pp.dataStore then
            pp.dataStore:ResetAll()
        end

    elseif msg == "resetcurrent" then
        if pp.dataStore then
            pp.dataStore:ResetCurrent()
            pp.Print("Current segment reset.")
        end

    elseif msg == "debug" then
        pp.ToggleDebug()

    elseif msg == "verbose" then
        pp.verboseMode = not pp.verboseMode
        pp.Print("Verbose mode: " .. (pp.verboseMode and "|cff00ff00ON|r (raw event args)" or "|cffff4444OFF|r"))

    elseif msg == "pets" then
        -- Show current pet owner cache
        pp.Print("--- Pet Owner Cache ---")
        local count = 0
        for guid, owner in pairs(pp.petOwners) do
            local petName = UnitName and UnitName(guid) or guid
            pp.Print("  " .. (petName or guid) .. " -> " .. owner)
            count = count + 1
        end
        pp.Print("--- Totem Cast Log ---")
        for i = 1, table.getn(pp.totemCastLog) do
            local entry = pp.totemCastLog[i]
            pp.Print("  " .. (entry.caster or "?") .. " cast " .. (entry.spell or "?") .. (entry.totemGuid and (" -> " .. entry.totemGuid) or ""))
            count = count + 1
        end
        pp.Print("Total cached: " .. count)

    elseif msg == "missed" then
        -- Show unhandled/missed CHAT_MSG events
        local missed = pp.missedEvents or {}
        local count = table.getn(missed)
        if count == 0 then
            pp.Print("No missed events recorded.")
        else
            pp.Print("--- Missed Events (" .. count .. ") ---")
            for i = 1, count do
                local e = missed[i]
                pp.Print("|cffff8800" .. e.time .. "|r [" .. e.event .. "] " .. e.msg)
            end
            pp.Print("Copy these to help add new parsers!")
        end

    elseif msg == "stats" then
        pp.ShowStats()

    elseif msg == "diag" then
        -- Diagnostic: show which files loaded
        pp.Print("--- Load Diagnostics ---")
        pp.Print("Loaded files: " .. table.concat(pp._loadedFiles, ", "))
        pp.Print("Windows: " .. table.getn(pp.windows) .. " created")
        pp.Print("eventBus: " .. (pp.eventBus and "OK" or "|cffff4444NIL|r"))
        pp.Print("combatState: " .. (pp.combatState and "OK" or "|cffff4444NIL|r"))
        pp.Print("dataStore: " .. (pp.dataStore and "OK" or "|cffff4444NIL|r"))
        pp.Print("groupMembers: " .. (pp.groupMembers and "OK" or "|cffff4444NIL|r"))

    elseif string.sub(msg, 1, 6) == "events" then
        local count = tonumber(string.sub(msg, 8)) or 10
        pp.ShowEvents(count)

    elseif msg == "dump" then
        pp.DumpArgs("ManualDump")

    elseif msg == "options" or msg == "opt" or msg == "config" then
        pp.ToggleOptions()

    elseif msg == "minimap" then
        if ParsecMinimapButton then
            if ParsecMinimapButton:IsVisible() then
                ParsecMinimapButton:Hide()
                pp.Print("Minimap button |cffff4444hidden|r.")
            else
                ParsecMinimapButton:Show()
                pp.Print("Minimap button |cff00ff00shown|r.")
            end
        end

    elseif msg == "help" then
        pp.Print("--- Parsec Commands ---")
        pp.Print("/parsec - Toggle all windows")
        pp.Print("/parsec show - Show all windows")
        pp.Print("/parsec hide - Hide all windows")
        pp.Print("/parsec reset - Reset all data")
        pp.Print("/parsec resetcurrent - Reset current segment only")
        pp.Print("/parsec options - Open options panel")
        pp.Print("/parsec minimap - Toggle minimap button")
        pp.Print("/parsec debug - Toggle debug (pet attribution only)")
        pp.Print("/parsec verbose - Toggle verbose (raw event args)")
        pp.Print("/parsec pets - Show pet/totem owner cache")
        pp.Print("/parsec missed - Show unhandled CHAT_MSG events")
        pp.Print("/parsec stats - Show statistics")
        pp.Print("/parsec diag - Load diagnostics")
        pp.Print("/parsec events [n] - Show last N events")
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

    -- Load settings from SavedVariables
    pp.LoadSettings()

    pp.Print("v" .. pp.VERSION .. " loaded.")
    pp.Print("Files: " .. table.concat(pp._loadedFiles, ", "))

    -- Check dependencies
    local depsOK = CheckDependencies()
    if depsOK then
        pp.Print("|cff00ff00SuperWoW + Nampower detected.|r")
    end

    -- Setup Nampower CVars
    SetupCVars()

    -- Seed player GUID into name cache (UnitName(playerGUID) can fail)
    if UnitGUID then
        local playerGUID = UnitGUID("player")
        local playerName = UnitName("player")
        if playerGUID and playerName then
            pp.guidNames[playerGUID] = playerName
            pp.Debug("Seeded player GUID: " .. playerName)
        end
    end

    -- Initial class + pet + group member scan
    pp.ScanGroupClasses()
    pp.ScanGroupPets()
    pp.ScanGroupMembers()

    -- Create windows from saved state (must happen here, not at file load time,
    -- because P.Print doesn't work before PLAYER_ENTERING_WORLD)
    pp.LoadWindowState()

    -- Apply settings (opacity, lock, minimap visibility)
    pp.ApplySettings()

    if table.getn(pp.windows) == 0 then
        pp.Print("|cffff4444No windows created! Check window.lua|r")
    end
end)
