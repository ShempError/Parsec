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

    elseif msg == "history" then
        local ds = pp.dataStore
        if not ds then pp.Print("No dataStore!"); return end
        local count = ds:GetHistoryCount()
        if count == 0 then
            pp.Print("No fights saved.")
        else
            pp.Print("--- Fight History (" .. count .. "/" .. (pp.settings.historyLimit or 10) .. ") ---")
            for i = 1, count do
                local label = ds:GetHistoryLabel(i) or "?"
                pp.Print("  [H" .. i .. "] " .. label)
            end
        end

    elseif msg == "fake" then
        -- Toggle fake data for screenshots (Horde only, no Paladins)
        local ds = pp.dataStore
        if not ds then pp.Print("No dataStore!"); return end

        -- If fake data is active, clear it
        if pp._fakeDataActive then
            ds:ResetAll()
            pp._fakeDataActive = false
            pp.Print("|cffff4444Fake data cleared.|r")
            pp.UpdateAllWindows()
            return
        end

        ds:ResetAll()
        local now = GetTime()
        local fightDur = 47  -- 47 second fight

        -- Include the player's own character
        local playerName = UnitName("player")
        local _, playerClass = UnitClass("player")
        if playerName and playerClass then
            ds.classes[playerName] = playerClass
        end

        -- Class assignments
        ds.classes["Grommash"]   = "WARRIOR"
        ds.classes["Zuljin"]     = "HUNTER"
        ds.classes["Raksha"]     = "ROGUE"
        ds.classes["Vexoria"]    = "MAGE"
        ds.classes["Shadowveil"] = "WARLOCK"
        ds.classes["Earthcall"]  = "SHAMAN"
        ds.classes["Thornhide"]  = "DRUID"
        ds.classes["Rotfang"]    = "PRIEST"
        ds.classes["Krag"]       = "WARRIOR"
        ds.classes["Hexweaver"]  = "SHAMAN"

        -- Helper: inject player data directly into both segments
        local function Inject(name, dmg, healTotal, healEff, spells, healSpells)
            for _, seg in pairs({ ds.current, ds.overall }) do
                local p = ds:GetPlayer(name, seg)
                p.damage_total = dmg
                p.heal_total = healTotal
                p.heal_effective = healEff
                p.heal_overheal = healTotal - healEff
                p.first_action = now - fightDur
                p.last_action = now
                if spells then
                    for spName, sp in pairs(spells) do
                        p.damage_spells[spName] = sp
                    end
                end
                if healSpells then
                    for spName, sp in pairs(healSpells) do
                        p.heal_spells[spName] = sp
                    end
                end
            end
        end

        -- DPS players (damage focused)
        Inject("Vexoria", 48720, 0, 0, {
            ["Frostbolt"]     = { total = 28200, hits = 18, crits = 5, min = 1180, max = 2100 },
            ["Cone of Cold"]  = { total = 11400, hits = 8, crits = 2, min = 1050, max = 1780 },
            ["Arcane Missiles"] = { total = 9120, hits = 12, crits = 3, min = 580, max = 920 },
        })
        Inject("Grommash", 42150, 0, 0, {
            ["Mortal Strike"]  = { total = 19800, hits = 14, crits = 4, min = 1080, max = 1820 },
            ["Whirlwind"]      = { total = 13200, hits = 11, crits = 3, min = 900, max = 1450 },
            ["Execute"]        = { total = 9150, hits = 4, crits = 2, min = 1800, max = 2700 },
        })
        Inject("Shadowveil", 38940, 0, 0, {
            ["Shadow Bolt"]    = { total = 24600, hits = 16, crits = 5, min = 1100, max = 2050 },
            ["Corruption"]     = { total = 8900, hits = 22, crits = 0, min = 350, max = 450 },
            ["Immolate"]       = { total = 5440, hits = 10, crits = 2, min = 420, max = 680 },
        })
        Inject("Raksha", 36780, 0, 0, {
            ["Sinister Strike"] = { total = 16500, hits = 20, crits = 6, min = 580, max = 1100 },
            ["Eviscerate"]      = { total = 12800, hits = 6, crits = 3, min = 1600, max = 2800 },
            ["Blade Flurry"]    = { total = 7480, hits = 14, crits = 4, min = 380, max = 680 },
        })
        Inject("Zuljin", 31200, 0, 0, {
            ["Auto Shot"]      = { total = 14400, hits = 24, crits = 6, min = 420, max = 780 },
            ["Aimed Shot"]     = { total = 9800, hits = 5, crits = 2, min = 1500, max = 2400 },
            ["Multi-Shot"]     = { total = 7000, hits = 8, crits = 2, min = 680, max = 1050 },
        })
        Inject("Krag", 18400, 0, 0, {
            ["Sunder Armor"]   = { total = 5200, hits = 16, crits = 0, min = 280, max = 380 },
            ["Heroic Strike"]  = { total = 8600, hits = 10, crits = 3, min = 650, max = 1100 },
            ["Revenge"]        = { total = 4600, hits = 12, crits = 2, min = 300, max = 480 },
        })

        -- Healers (some damage too)
        Inject("Earthcall", 3200, 52400, 41920, {
            ["Lightning Shield"] = { total = 3200, hits = 8, crits = 0, min = 350, max = 450 },
        }, {
            ["Chain Heal"]     = { total = 32400, effective = 25920, overheal = 6480, hits = 12, crits = 3 },
            ["Healing Wave"]   = { total = 15200, effective = 12160, overheal = 3040, hits = 6, crits = 1 },
            ["Lesser Healing Wave"] = { total = 4800, effective = 3840, overheal = 960, hits = 4, crits = 1 },
        })
        Inject("Rotfang", 1800, 44800, 38080,  {
            ["Shadow Word: Pain"] = { total = 1800, hits = 6, crits = 0, min = 250, max = 350 },
        }, {
            ["Greater Heal"]   = { total = 22400, effective = 19040, overheal = 3360, hits = 8, crits = 2 },
            ["Prayer of Healing"] = { total = 14800, effective = 12580, overheal = 2220, hits = 5, crits = 1 },
            ["Renew"]          = { total = 7600, effective = 6460, overheal = 1140, hits = 10, crits = 0 },
        })
        Inject("Thornhide", 5600, 36200, 25340, {
            ["Moonfire"]       = { total = 3200, hits = 6, crits = 1, min = 380, max = 620 },
            ["Wrath"]          = { total = 2400, hits = 3, crits = 1, min = 650, max = 950 },
        }, {
            ["Rejuvenation"]   = { total = 18600, effective = 13020, overheal = 5580, hits = 15, crits = 0 },
            ["Regrowth"]       = { total = 12400, effective = 8680, overheal = 3720, hits = 6, crits = 2 },
            ["Healing Touch"]  = { total = 5200, effective = 3640, overheal = 1560, hits = 2, crits = 1 },
        })
        Inject("Hexweaver", 4100, 28600, 20020, {
            ["Earth Shock"]    = { total = 4100, hits = 5, crits = 1, min = 620, max = 980 },
        }, {
            ["Chain Heal"]     = { total = 18200, effective = 12740, overheal = 5460, hits = 7, crits = 1 },
            ["Healing Wave"]   = { total = 10400, effective = 7280, overheal = 3120, hits = 4, crits = 1 },
        })

        -- Inject player's own character
        if playerName then
            Inject(playerName, 38940, 0, 0, {
                ["Shadow Bolt"]    = { total = 24600, hits = 16, crits = 5, min = 1100, max = 1900 },
                ["Corruption"]     = { total = 8900, hits = 12, crits = 0, min = 680, max = 780 },
                ["Immolate"]       = { total = 5440, hits = 7, crits = 2, min = 620, max = 920 },
            })
        end

        -- Set combat duration on both segments
        ds.current.startTime = now - fightDur
        ds.current.duration = fightDur
        ds.overall.startTime = now - fightDur
        ds.overall.duration = fightDur
        pp.combatState.startTime = now - fightDur
        pp.combatState.overallStart = now - fightDur

        -- Inject 3 fake history segments
        if ds.SaveCurrentToHistory then
            -- Save current as first history entry
            ds:SaveCurrentToHistory(fightDur)

            -- Create 2 more varied history entries by temporarily modifying current data
            local origPlayers = ds.current.players

            -- Helper to scale player data for history
            local function ScalePlayers(orig, factor)
                local scaled = {}
                for pName, d in pairs(orig) do
                    scaled[pName] = {
                        damage_total = math.floor(d.damage_total * factor),
                        heal_total = math.floor(d.heal_total * factor),
                        heal_effective = math.floor((d.heal_effective or 0) * factor),
                        heal_overheal = math.floor((d.heal_overheal or 0) * factor),
                        first_action = d.first_action,
                        last_action = d.last_action,
                        damage_spells = d.damage_spells or {},
                        heal_spells = d.heal_spells or {},
                    }
                end
                return scaled
            end

            -- History 2: shorter fight (~70% of current)
            ds.current.players = ScalePlayers(origPlayers, 0.7)
            ds.current.startTime = now - fightDur - 300
            ds:SaveCurrentToHistory(math.floor(fightDur * 0.6))

            -- History 3: even shorter fight (~40% of current)
            ds.current.players = ScalePlayers(origPlayers, 0.4)
            ds.current.startTime = now - fightDur - 600
            ds:SaveCurrentToHistory(math.floor(fightDur * 0.3))

            -- Restore original current data
            ds.current.players = origPlayers
            ds.current.startTime = now - fightDur
        end

        pp._fakeDataActive = true
        pp.Print("|cff00ff00Fake data injected!|r 10 players, " .. fightDur .. "s fight, 3 history segments. Type /parsec fake again to clear.")
        pp.UpdateAllWindows()

    elseif msg == "help" then
        pp.Print("--- Parsec Commands ---")
        pp.Print("/parsec - Toggle all windows")
        pp.Print("/parsec show - Show all windows")
        pp.Print("/parsec hide - Hide all windows")
        pp.Print("/parsec reset - Reset all data")
        pp.Print("/parsec resetcurrent - Reset current segment only")
        pp.Print("/parsec options - Open options panel")
        pp.Print("/parsec minimap - Toggle minimap button")
        pp.Print("/parsec history - Show saved fight history")
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
