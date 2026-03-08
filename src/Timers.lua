-- =============================================================================
-- Timers.lua
-- Repeating C_Timer per alert. Respects combat / cutscene lockouts by queuing
-- the alert and deferring it until the coast is clear. Private state lives in
-- file-level locals.
-- =============================================================================

local timers        = {}  -- active C_Timer handles, keyed by alert.key
local pendingAlerts = {}  -- alerts queued while in combat / cutscene
local lastFired     = {}  -- last fire timestamp per alert key (in-memory, resets on reload)
local playerIsAFK   = false  -- cached; updated via SelfCare.UpdateAFKState()

local function CancelTimer(key)
    if timers[key] then
        timers[key]:Cancel()
        timers[key] = nil
    end
end

local function IsBlocked()
    if SelfCareDB.disableInCombat   and InCombatLockdown()                      then return true end
    if SelfCareDB.disableInCutscene and (MovieFrame and MovieFrame:IsShown())    then return true end
    if SelfCareDB.disableWhenAFK    and playerIsAFK                               then return true end
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
    local intervalKey = SelfCare.IntervalKey(alert)
    local interval    = SelfCareDB[intervalKey]
    -- Guard: skip if we fired recently (within half an interval).
    -- Uses a file-local table so both fresh-start fires and mid-cycle duplicates
    -- are caught even when SelfCareDB.nextDue is nil (e.g., after RestartTimers).
    local now  = time()
    local last = lastFired[alert.key]
    if last and (now - last) < (interval / 2) then return end
    lastFired[alert.key]          = now
    SelfCareDB.nextDue[alert.key] = now + interval
    SelfCare.ShowNotif(alert)
end

function SelfCare.StartTimer(alert)
    CancelTimer(alert.key)

    local enabledKey  = SelfCare.EnabledKey(alert)
    local intervalKey = SelfCare.IntervalKey(alert)

    if not SelfCareDB[enabledKey] then return end

    local interval = SelfCareDB[intervalKey]
    if not interval or interval <= 0 then return end

    local nextDue   = SelfCareDB.nextDue[alert.key]
    local remaining = nextDue and (nextDue - time())

    local key = alert.key  -- capture for closures

    -- Corrupt / missing timestamp → start fresh
    if not remaining or remaining > interval then
        SelfCareDB.nextDue[key] = time() + interval
        local handle
        handle = C_Timer.NewTicker(interval, function()
            if timers[key] ~= handle then return end  -- stale: superseded by Cancel+restart
            FireAlert(alert)
        end)
        timers[key] = handle
        return
    end

    -- Overdue → fire immediately, then resume normal cadence
    if remaining <= 0 then
        FireAlert(alert)
        local handle
        handle = C_Timer.NewTicker(interval, function()
            if timers[key] ~= handle then return end
            FireAlert(alert)
        end)
        timers[key] = handle
        return
    end

    -- Partial interval remaining → one-shot delay, then normal ticker
    local handle
    handle = C_Timer.After(remaining, function()
        if timers[key] ~= handle then return end  -- stale: superseded by Cancel+restart
        local ticker
        ticker = C_Timer.NewTicker(interval, function()
            if timers[key] ~= ticker then return end
            FireAlert(alert)
        end)
        timers[key] = ticker
        FireAlert(alert)
    end)
    timers[key] = handle
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

--- Update the cached AFK state. Call from PLAYER_FLAGS_CHANGED to avoid
--- calling UnitIsAFK() inside combat-transition callbacks, which can return
--- a tainted "secret boolean" that WoW blocks from boolean evaluation.
function SelfCare.UpdateAFKState()
    local afk = UnitIsAFK("player")
    -- Use equality comparisons (not a boolean test) to produce a clean Lua
    -- boolean. Handles both real WoW (nil = not AFK, true = AFK) and the
    -- test stub (false = not AFK, true = AFK).
    playerIsAFK = (afk ~= nil and afk ~= false)
end

--- Show any queued alerts now that we are out of a blocked state.
--- The original ticker keeps running — cadence is not disturbed by combat/AFK/cutscene.
function SelfCare.FlushPending()
    if not IsBlocked() and #pendingAlerts > 0 then
        local toFire = pendingAlerts
        pendingAlerts = {}
        for _, alert in ipairs(toFire) do
            FireAlert(alert)
        end
    end
end

--- Stop and restart all timers (e.g., after manually editing SelfCareDB).
function SelfCare.RestartTimers()
    SelfCare.StopAllTimers()
    SelfCareDB.nextDue = {}  -- clear so settings changes start fresh, not mid-old-cycle
    pendingAlerts      = {}  -- discard stale queued alerts; fresh start
    SelfCare.StartAllTimers()
    SelfCare.Print("Timers restarted.")
end
