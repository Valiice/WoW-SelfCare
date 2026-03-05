-- =============================================================================
-- Core.lua
-- Namespace, defaults, alert definitions, and shared helpers.
-- =============================================================================

SelfCare = SelfCare or {}

-- ---------------------------------------------------------------------------
-- 1. DEFAULT CONFIGURATION
--    All times stored in SECONDS in the DB. Sliders show MINUTES.
-- ---------------------------------------------------------------------------
SelfCare.DEFAULTS = {
    -- Hydrate reminder
    hydrateEnabled  = true,
    hydrateInterval = 60 * 60,       -- 60 minutes

    -- Posture reminder
    postureEnabled  = true,
    postureInterval = 30 * 60,       -- 30 minutes

    -- Break reminder
    breakEnabled    = true,
    breakInterval   = 140 * 60,      -- 140 minutes (2h 20m)

    -- Global toggles
    disableInCombat   = true,
    disableInCutscene = true,
    printToChat       = true,
    autoDismiss       = true,        -- true = auto-dismiss after dismissDelay seconds; click always dismisses
    dismissDelay      = 10,          -- seconds before auto-dismiss (when autoDismiss = true)
}

-- ---------------------------------------------------------------------------
-- 2. ALERT DEFINITIONS
--    Drives timer setup, display, and settings panel generation.
-- ---------------------------------------------------------------------------
SelfCare.ALERTS = {
    {
        key     = "hydrate",
        label   = "Hydrate",
        message = "Remember to hydrate!",
    },
    {
        key     = "posture",
        label   = "Posture",
        message = "Remember to check your posture!",
    },
    {
        key     = "break",
        label   = "Break",
        message = "It's time to take a break!",
    },
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Print a message to chat with the SelfCare prefix.
function SelfCare.Print(msg)
    print(string.format("|cff66ccff[SelfCare]|r %s", msg))
end

--- Merge SavedVariables over defaults (non-destructive).
function SelfCare.ApplyDefaults()
    if not SelfCareDB then SelfCareDB = {} end
    for k, v in pairs(SelfCare.DEFAULTS) do
        if SelfCareDB[k] == nil then
            SelfCareDB[k] = v
        end
    end
end

--- Return the ALERTS entry whose key matches, or nil.
function SelfCare.FindAlertByKey(key)
    for _, a in ipairs(SelfCare.ALERTS) do
        if a.key == key then return a end
    end
    return nil
end

--- Return the SelfCareDB key that stores whether this alert is enabled.
function SelfCare.EnabledKey(alert)
    return alert.key .. "Enabled"
end

--- Return the SelfCareDB key that stores this alert's interval (seconds).
function SelfCare.IntervalKey(alert)
    return alert.key .. "Interval"
end
