-- =============================================================================
-- Init.lua
-- Addon frame, event wiring, slash command, TestAlert, and global
-- backwards-compatibility aliases for macros / other addons.
-- =============================================================================

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
        SelfCare.StartAllTimers()

    elseif event == "PLAYER_REGEN_ENABLED" or event == "CINEMATIC_STOP" then
        SelfCare.FlushPending()

    elseif event == "PLAYER_FLAGS_CHANGED" then
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

    if SelfCare.Category then
        Settings.OpenToCategory(SelfCare.Category.ID)
    else
        SelfCare.Print("Settings panel not yet initialized.")
    end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Fire all alert notifications immediately (for testing / preview).
function SelfCare.TestAllAlerts()
    for _, alert in ipairs(SelfCare.ALERTS) do
        SelfCare.ShowNotif(alert)
    end
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
