-- =============================================================================
-- Init.lua
-- Addon frame, event wiring, slash command, TestAlert, and global
-- backwards-compatibility aliases for macros / other addons.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Local helpers for /selfcare debug and ResetTimers
-- ---------------------------------------------------------------------------
local function FormatInterval(s)
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    if h > 0 then
        return string.format("%dh %dm", h, m)
    elseif m > 0 then
        return string.format("%d min", m)
    else
        return string.format("%ds", s)
    end
end

local function FormatRemaining(s)
    if s <= 0 then return "overdue" end
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sec = s % 60
    if h > 0 then
        return string.format("%dh %dm", h, m)
    elseif m > 0 then
        return string.format("%dm %ds", m, sec)
    else
        return string.format("%ds", sec)
    end
end

-- ---------------------------------------------------------------------------
-- Event handling
-- ---------------------------------------------------------------------------
local addonFrame = CreateFrame("Frame", "SelfCareAddonFrame", UIParent)

addonFrame:RegisterEvent("ADDON_LOADED")
addonFrame:RegisterEvent("PLAYER_LOGIN")
addonFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- combat ends
addonFrame:RegisterEvent("CINEMATIC_STOP")         -- in-game cutscenes end
addonFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")  -- AFK state changes

addonFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "SelfCare" then
        SelfCare.ApplyDefaults()
        SelfCare.BuildSettingsPanel()

    elseif event == "PLAYER_LOGIN" then
        SelfCare.UpdateAFKState()
        SelfCare.StartAllTimers()

    elseif event == "PLAYER_REGEN_ENABLED" or event == "CINEMATIC_STOP" then
        SelfCare.FlushPending()

    elseif event == "PLAYER_FLAGS_CHANGED" then
        SelfCare.UpdateAFKState()
        SelfCare.FlushPending()
    end
end)

-- ---------------------------------------------------------------------------
-- Slash command:  /selfcare          → open settings
--                /selfcare test      → fire all alerts immediately
-- ---------------------------------------------------------------------------
SLASH_SELFCARE1 = "/selfcare"
SlashCmdList["SELFCARE"] = function(msg)
    local cmd = msg and msg:lower():match("^%s*(.-)%s*$") or ""

    if cmd == "test" then
        SelfCare.TestAllAlerts()
        return
    end

    if cmd == "reset" then
        SelfCare.ResetTimers()
        return
    end

    if cmd == "debug" then
        SelfCare.PrintDebug()
        return
    end

    if InCombatLockdown() then
        SelfCare.Print("Cannot open settings during combat.")
        return
    end

    if SelfCare.Category then
        Settings.OpenToCategory(SelfCare.Category.ID)
    else
        SelfCare.Print("Settings panel not yet initialized.")
    end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Print a debug snapshot of all timer states to chat.
function SelfCare.PrintDebug()
    SelfCare.Print("SelfCare Debug:")
    for _, alert in ipairs(SelfCare.ALERTS) do
        local enabledKey  = SelfCare.EnabledKey(alert)
        local intervalKey = SelfCare.IntervalKey(alert)
        if not SelfCareDB[enabledKey] then
            SelfCare.Print(string.format("  %s — [disabled]", alert.key))
        else
            local interval = SelfCareDB[intervalKey]
            local nextDue  = SelfCareDB.nextDue and SelfCareDB.nextDue[alert.key]
            if not nextDue then
                SelfCare.Print(string.format("  %s — [pending first fire]  [%s interval]",
                    alert.key, FormatInterval(interval)))
            else
                local remaining = nextDue - time()
                SelfCare.Print(string.format("  %s — due %s (in %s)  [%s interval]",
                    alert.key, date("%H:%M:%S", nextDue),
                    FormatRemaining(remaining), FormatInterval(interval)))
            end
        end
    end
end

--- Restart all timers from now and print a debug snapshot.
--- Called by the Settings panel Reset Timers button and /selfcare reset.
function SelfCare.ResetTimers()
    SelfCare.RestartTimers()
    SelfCare.PrintDebug()
end

--- Fire all alert notifications immediately (for testing / preview).
function SelfCare.TestAllAlerts()
    for _, alert in ipairs(SelfCare.ALERTS) do
        SelfCare.ShowNotif(alert)
    end
end

--- Wipe SelfCareDB entirely and restore factory defaults.
--- Called by the Settings panel's Defaults button.
function SelfCare.ResetToDefaults()
    for k in pairs(SelfCareDB) do
        SelfCareDB[k] = nil
    end
    SelfCare.ApplyDefaults()
    SelfCare.RestartTimers()
    SelfCare.Print("Settings reset to defaults.")
end

--- Immediately show a test notification for a given alert key.
function SelfCare.TestAlert(alertKey)
    local alert = SelfCare.FindAlertByKey(alertKey)
    if alert then
        SelfCare.ShowNotif(alert)
    else
        SelfCare.Print(string.format(
            "Unknown alert key '%s'. Use: hydrate, posture, break", alertKey))
    end
end

-- ---------------------------------------------------------------------------
-- Backwards-compatibility aliases (macros / external addons)
-- ---------------------------------------------------------------------------
SelfCare_ShowNotif     = SelfCare.ShowNotif
SelfCare_HideNotif     = SelfCare.HideNotif
SelfCare_RestartTimers = SelfCare.RestartTimers
SelfCare_TestAlert     = SelfCare.TestAlert
