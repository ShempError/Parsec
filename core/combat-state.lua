-- Parsec: Combat State Machine
-- Tracks combat start/end, encounter duration, segment management

local P = Parsec

P.combatState = {}
local CS = P.combatState

CS.state = "IDLE"           -- IDLE, COMBAT, POST_COMBAT
CS.combatStart = 0          -- GetTime() of combat start
CS.combatEnd = 0            -- GetTime() of combat end
CS.combatDuration = 0       -- Seconds in combat (current segment)
CS.overallDuration = 0      -- Seconds in combat (overall)
CS.postCombatTimeout = 3    -- Seconds to wait after REGEN_ENABLED before going IDLE
CS.postCombatTimer = 0
CS.segmentName = "Current"

-- Timer frame for post-combat timeout and duration tracking
CS.timerFrame = CreateFrame("Frame", "ParsecCombatTimer")
CS.timerFrame:Hide()

function CS:OnCombatStart()
    if self.state == "IDLE" then
        -- New combat segment
        P.Debug("Combat START -- new segment")
        if P.dataStore then
            P.dataStore:NewSegment()
        end
    elseif self.state == "POST_COMBAT" then
        -- Re-entered combat before timeout, continue same segment
        P.Debug("Combat RESUME (was post-combat)")
    end

    self.state = "COMBAT"
    if self.combatStart == 0 then
        self.combatStart = GetTime()
    end
    self.timerFrame:Show()
end

function CS:OnCombatEnd()
    if self.state ~= "COMBAT" then return end
    P.Debug("Combat END -- entering post-combat (" .. self.postCombatTimeout .. "s timeout)")
    self.state = "POST_COMBAT"
    self.postCombatTimer = self.postCombatTimeout
    self.combatEnd = GetTime()
end

function CS:FinalizeSegment()
    P.Debug("Segment FINALIZED -- duration: " .. string.format("%.1f", self.combatDuration) .. "s")
    self.state = "IDLE"
    self.timerFrame:Hide()

    -- Finalize segment in data store
    if P.dataStore then
        P.dataStore:FinalizeSegment(self.combatDuration)
    end

    self.combatStart = 0
    self.combatEnd = 0
    self.combatDuration = 0
end

function CS:GetDuration()
    if self.state == "COMBAT" then
        return GetTime() - self.combatStart
    elseif self.state == "POST_COMBAT" then
        return self.combatEnd - self.combatStart
    end
    return self.combatDuration
end

function CS:InCombat()
    return self.state == "COMBAT" or self.state == "POST_COMBAT"
end

-- OnUpdate: track duration + post-combat timeout
local elapsed_acc = 0
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
