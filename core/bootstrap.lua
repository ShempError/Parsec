-- Parsec: Bootstrap
-- Addon initialization, dependency checks, slash commands, CVar setup

local P = Parsec

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

    -- Check Nampower (check for known CVar)
    if GetCVar and GetCVar("NP_EnableSpellDamageEvents") == nil then
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

    local cvars = {
        "NP_EnableSpellDamageEvents",
        "NP_EnableAutoAttackEvents",
        "NP_EnableSpellMissEvents",
        "NP_EnableSpellHealEvents",
        "NP_EnableBuffEvents",
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
    msg = string.lower(msg or "")

    if msg == "" or msg == "toggle" then
        P.ToggleWindow()

    elseif msg == "show" then
        ParsecWindow:Show()
        P.UpdateWindow()

    elseif msg == "hide" then
        ParsecWindow:Hide()

    elseif msg == "reset" then
        P.dataStore:Reset()
        P.UpdateWindow()

    elseif msg == "debug" then
        P.ToggleDebug()

    elseif msg == "stats" then
        P.ShowStats()

    elseif string.sub(msg, 1, 6) == "events" then
        local count = tonumber(string.sub(msg, 8)) or 10
        P.ShowEvents(count)

    elseif msg == "damage" or msg == "dmg" then
        P.window.viewType = "damage"
        P.UpdateWindow()

    elseif msg == "dps" then
        P.window.viewType = "dps"
        P.UpdateWindow()

    elseif msg == "healing" or msg == "heal" then
        P.window.viewType = "healing"
        P.UpdateWindow()

    elseif msg == "hps" then
        P.window.viewType = "hps"
        P.UpdateWindow()

    elseif msg == "dump" then
        P.DumpArgs("ManualDump")

    elseif msg == "help" then
        P.Print("--- Parsec Commands ---")
        P.Print("/parsec - Toggle window")
        P.Print("/parsec reset - Reset all data")
        P.Print("/parsec debug - Toggle debug output")
        P.Print("/parsec stats - Show statistics")
        P.Print("/parsec events [n] - Show last N events")
        P.Print("/parsec dmg|dps|heal|hps - Switch view")
        P.Print("/parsec dump - Dump current event args")
        P.Print("Right-click title = cycle view")
        P.Print("Middle-click title = cycle segment")
        P.Print("Scroll wheel = scroll bars")
    else
        P.Print("Unknown command: " .. msg .. " (try /parsec help)")
    end
end

---------------------------------------------------------------------------
-- Initialization
---------------------------------------------------------------------------

local initFrame = CreateFrame("Frame", "ParsecInit")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function()
    initFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")

    P.Print("v" .. P.VERSION .. " loaded.")

    -- Check dependencies
    local depsOK = CheckDependencies()
    if depsOK then
        P.Print("|cff00ff00SuperWoW + Nampower detected.|r")
    end

    -- Setup Nampower CVars
    SetupCVars()

    -- Initial class scan
    P.ScanGroupClasses()

    -- Show window by default
    ParsecWindow:Show()
    P.UpdateWindow()
end)
