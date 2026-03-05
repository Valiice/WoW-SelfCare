-- =============================================================================
-- Timers.lua
-- Repeating C_Timer per alert. Respects combat / cutscene lockouts by queuing
-- the alert and deferring it until the coast is clear. Private state lives in
-- file-level locals.
-- =============================================================================

local timers        = {}  -- active C_Timer handles, keyed by alert.key
local pendingAlerts = {}  -- alerts queued while in combat / cutscene

local function CancelTimer(key)
    if timers[key] then
        timers[key]:Cancel()
        timers[key] = nil
    end
end

local function IsBlocked()
    if SelfCareDB.disableInCombat   and InCombatLockdown()                      then return true end
    if SelfCareDB.disableInCutscene and (MovieFrame and MovieFrame:IsShown())    then return true end
    return false
end

local function FireAlert(alert)
    if IsBlocked() then
        -- Queue for later; avoid duplicates
        for _, v in ipairs(pendingAlerts) do
            if v.key == alert.key then return end
        end
        table.insert(pendingAlerts, alert)
        return
    end
    SelfCare.ShowNotif(alert)
end

function SelfCare.StartTimer(alert)
    CancelTimer(alert.key)

    local enabledKey  = SelfCare.EnabledKey(alert)
    local intervalKey = SelfCare.IntervalKey(alert)

    if not SelfCareDB[enabledKey] then return end

    local interval = SelfCareDB[intervalKey]
    if not interval or interval <= 0 then return end

    timers[alert.key] = C_Timer.NewTicker(interval, function()
        FireAlert(alert)
    end)
end

function SelfCare.StartAllTimers()
    for _, alert in ipairs(SelfCare.ALERTS) do
        SelfCare.StartTimer(alert)
    end
end

function SelfCare.StopAllTimers()
    for key in pairs(timers) do
        CancelTimer(key)
    end
end

--- Show any queued alerts now that we are out of a blocked state.
function SelfCare.FlushPending()
    if not IsBlocked() and #pendingAlerts > 0 then
        local toFire = pendingAlerts
        pendingAlerts = {}
        for _, alert in ipairs(toFire) do
            SelfCare.ShowNotif(alert)
        end
    end
end

--- Stop and restart all timers (e.g., after manually editing SelfCareDB).
function SelfCare.RestartTimers()
    SelfCare.StopAllTimers()
    SelfCare.StartAllTimers()
    SelfCare.Print("Timers restarted.")
end
