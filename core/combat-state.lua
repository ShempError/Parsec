-- Parsec: Combat State Machine
-- Tracks combat start/end, accumulated duration (no auto-reset)

local P = Parsec
if not P then return end

table.insert(P._loadedFiles, "combat-state")

P.combatState = {}
local CS = P.combatState

CS.state = "IDLE"           -- IDLE, COMBAT, POST_COMBAT
CS.combatStart = 0
CS.combatEnd = 0
CS.combatDuration = 0       -- Current fight duration
CS.overallDuration = 0      -- Accumulated combat time (across all fights)
CS.postCombatTimeout = 3
CS.postCombatTimer = 0

CS.timerFrame = CreateFrame("Frame", "ParsecCombatTimer")
CS.timerFrame:Hide()

function CS:OnCombatStart()
    if self.state == "POST_COMBAT" then
        P.Debug("Combat RESUME (was post-combat)")
    else
        P.Debug("Combat START")
        -- Auto-show windows on fresh combat start
        if P.settings and P.settings.autoShow and P.ShowAllWindows then
            P.ShowAllWindows()
        end
    end

    self.state = "COMBAT"
    if self.combatStart == 0 then
        self.combatStart = GetTime()
    end
    self.timerFrame:Show()
end

function CS:OnCombatEnd()
    if self.state ~= "COMBAT" then return end
    P.Debug("Combat END -- post-combat (" .. self.postCombatTimeout .. "s)")
    self.state = "POST_COMBAT"
    self.postCombatTimer = self.postCombatTimeout
    self.combatEnd = GetTime()
end

function CS:FinalizeSegment()
    P.Debug("Segment done -- total: " .. string.format("%.1f", self.overallDuration) .. "s")
    self.state = "IDLE"
    self.timerFrame:Hide()

    -- Save to history BEFORE resetting duration
    local savedDuration = self.combatDuration
    if P.dataStore then
        P.dataStore:SaveCurrentToHistory(savedDuration)
        P.dataStore:ResetCurrent()
    end

    -- Clear intake buffers (death log) for next combat
    if P.deathLog then
        P.deathLog:ClearIntake()
    end

    self.combatStart = 0
    self.combatEnd = 0
    self.combatDuration = 0

    -- Auto-hide windows after combat ends
    if P.settings and P.settings.autoHide and P.HideAllWindows then
        P.HideAllWindows()
    end
end

function CS:GetDuration(segment)
    if segment == "current" then
        return self.combatDuration
    end
    return self.overallDuration
end

function CS:InCombat()
    return self.state == "COMBAT" or self.state == "POST_COMBAT"
end

function CS:Reset()
    self.state = "IDLE"
    self.timerFrame:Hide()
    self.combatStart = 0
    self.combatEnd = 0
    self.combatDuration = 0
    self.overallDuration = 0
end

-- OnUpdate: track duration + post-combat timeout
CS.timerFrame:SetScript("OnUpdate", function()
    local dt = arg1 or 0.016
    local cs = P.combatState

    if cs.state == "COMBAT" then
        cs.combatDuration = GetTime() - cs.combatStart
        cs.overallDuration = cs.overallDuration + dt

    elseif cs.state == "POST_COMBAT" then
        cs.postCombatTimer = cs.postCombatTimer - dt
        if cs.postCombatTimer <= 0 then
            cs:FinalizeSegment()
        end
    end
end)
