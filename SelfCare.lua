-- =============================================================================
-- SelfCare.lua
-- A WoW retail addon that reminds you to hydrate, fix your posture, and take
-- breaks at configurable intervals, inspired by the FFXIV plugin of the same name.
--
-- API target: WoW 11.x (The War Within)
-- Settings API: post-11.0.2 signature (RegisterAddOnSetting with variableKey + variableTbl)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. DEFAULT CONFIGURATION
--    All times stored in SECONDS in the DB. Sliders show MINUTES.
-- ---------------------------------------------------------------------------
local DEFAULTS = {
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
    dismissOnClick    = true,        -- true = click to dismiss; false = auto-dismiss after 10s
    dismissDelay      = 10,          -- seconds before auto-dismiss (when dismissOnClick = false)
}

-- ---------------------------------------------------------------------------
-- 2. ALERT DEFINITIONS
--    Drives timer setup, display, and settings panel generation.
-- ---------------------------------------------------------------------------
local ALERTS = {
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
-- 3. RUNTIME STATE
-- ---------------------------------------------------------------------------
local timers          = {}   -- active C_Timer handles, keyed by alert.key
local pendingAlerts   = {}   -- alerts queued while in combat / cutscene
local notifFrame      = nil  -- the single reusable notification frame
local notifDismissTimer = nil -- auto-dismiss timer handle
local SelfCareCategory = nil  -- Settings panel category handle

-- ---------------------------------------------------------------------------
-- 4. HELPER: Merge saved DB over defaults (non-destructive)
-- ---------------------------------------------------------------------------
local function ApplyDefaults()
    if not SelfCareDB then SelfCareDB = {} end
    for k, v in pairs(DEFAULTS) do
        if SelfCareDB[k] == nil then
            SelfCareDB[k] = v
        end
    end
end

-- ---------------------------------------------------------------------------
-- 5. NOTIFICATION FRAME
--    One shared frame, updated per alert. Fades in/out nicely.
-- ---------------------------------------------------------------------------
local function BuildNotifFrame()
    if notifFrame then return end

    -- A simple clickable frame — just floating text, no border or background,
    -- matching the minimal style of the original FFXIV plugin.
    local f = CreateFrame("Button", "SelfCareNotifFrame", UIParent)
    f:SetSize(400, 60)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(100)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)

    -- Main reminder text — large, centered, white
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    text:SetAllPoints(f)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(true)
    text:SetTextColor(1, 1, 1, 1)
    f.text = text

    -- Subtle "click to dismiss" hint below the main text
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", text, "BOTTOM", 0, -4)
    hint:SetText("Click to dismiss")
    f.hint = hint

    -- Click to dismiss
    f:SetScript("OnClick", function()
        if SelfCareDB.dismissOnClick then
            SelfCare_HideNotif()
        end
    end)

    f:Hide()
    notifFrame = f
end

function SelfCare_ShowNotif(alert)
    BuildNotifFrame()
    if notifDismissTimer then
        notifDismissTimer:Cancel()
        notifDismissTimer = nil
    end

    notifFrame.text:SetText(alert.message)

    if SelfCareDB.dismissOnClick then
        notifFrame.hint:SetText("Click to dismiss")
    else
        notifFrame.hint:SetText(string.format("Dismisses in %ds", SelfCareDB.dismissDelay))
    end

    notifFrame:Show()
    notifFrame:SetAlpha(0)
    UIFrameFadeIn(notifFrame, 0.4, 0, 1)

    -- Optional chat print
    if SelfCareDB.printToChat then
        print(string.format("|cff66ccff[SelfCare]|r %s", alert.message))
    end

    -- Play a pleasant UI sound
    PlaySound(808)

    -- Auto-dismiss if configured
    if not SelfCareDB.dismissOnClick then
        notifDismissTimer = C_Timer.NewTimer(SelfCareDB.dismissDelay, function()
            SelfCare_HideNotif()
        end)
    end
end

function SelfCare_HideNotif()
    if notifFrame and notifFrame:IsShown() then
        UIFrameFadeOut(notifFrame, 0.3, 1, 0)
        C_Timer.NewTimer(0.31, function()
            if notifFrame then notifFrame:Hide() end
        end)
    end
    if notifDismissTimer then
        notifDismissTimer:Cancel()
        notifDismissTimer = nil
    end
end

-- ---------------------------------------------------------------------------
-- 6. TIMER ENGINE
--    Starts a repeating C_Timer for a given alert. Respects combat / cutscene
--    lockouts by queuing the alert and deferring it to when the coast is clear.
-- ---------------------------------------------------------------------------
local function IsBlocked()
    if SelfCareDB.disableInCombat   and InCombatLockdown()             then return true end
    if SelfCareDB.disableInCutscene and (MovieFrame and MovieFrame:IsShown()) then return true end
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
    SelfCare_ShowNotif(alert)
end

local function StartTimer(alert)
    -- Cancel any existing timer for this alert
    if timers[alert.key] then
        timers[alert.key]:Cancel()
        timers[alert.key] = nil
    end

    local enabledKey  = alert.key .. "Enabled"
    local intervalKey = alert.key .. "Interval"

    if not SelfCareDB[enabledKey] then return end

    local interval = SelfCareDB[intervalKey]
    if not interval or interval <= 0 then return end

    timers[alert.key] = C_Timer.NewTicker(interval, function()
        FireAlert(alert)
    end)
end

local function StartAllTimers()
    for _, alert in ipairs(ALERTS) do
        StartTimer(alert)
    end
end

local function StopAllTimers()
    for key, timer in pairs(timers) do
        timer:Cancel()
        timers[key] = nil
    end
end

-- ---------------------------------------------------------------------------
-- 7. MAIN ADDON FRAME  (event handling)
-- ---------------------------------------------------------------------------
local addonFrame = CreateFrame("Frame", "SelfCareAddonFrame", UIParent)

addonFrame:RegisterEvent("ADDON_LOADED")
addonFrame:RegisterEvent("PLAYER_LOGIN")
addonFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- combat ends
addonFrame:RegisterEvent("CINEMATIC_STOP")         -- in-game cutscenes end
addonFrame:RegisterEvent("PLAY_MOVIE")             -- movie starts (for edge-case detection)

addonFrame:SetScript("OnEvent", function(self, event, arg1)

    if event == "ADDON_LOADED" and arg1 == "SelfCare" then
        ApplyDefaults()
        SelfCare_BuildSettingsPanel()

    elseif event == "PLAYER_LOGIN" then
        StartAllTimers()

    elseif event == "PLAYER_REGEN_ENABLED" or event == "CINEMATIC_STOP" then
        -- Flush any pending alerts now that we're out of a blocked state
        if not IsBlocked() and #pendingAlerts > 0 then
            local toFire = pendingAlerts
            pendingAlerts = {}
            for _, alert in ipairs(toFire) do
                SelfCare_ShowNotif(alert)
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- 8. SETTINGS PANEL  (post-11.0.2 API)
--
--    API shape as of 11.0.2:
--      Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl,
--                                    variableType, name, defaultValue)
--      setting:SetValueChangedCallback(fn)    -- fn(setting, value)
--      Settings.CreateCheckbox(category, setting, tooltip)
--      Settings.CreateSlider(category, setting, options, tooltip)
--      Settings.RegisterVerticalLayoutCategory(name)
--      Settings.RegisterAddOnCategory(category)
--      Settings.OpenToCategory(category)
-- ---------------------------------------------------------------------------

function SelfCare_BuildSettingsPanel()
    if SelfCareCategory then return end  -- already built

    -- Create the vertical-layout category (appears in Esc > Interface > AddOns)
    local category = Settings.RegisterVerticalLayoutCategory("SelfCare")

    -- -----------------------------------------------------------------------
    -- Helper: make a checkbox backed directly by SelfCareDB[variableKey]
    -- -----------------------------------------------------------------------
    local function MakeCheckbox(varKey, displayName, tooltip, onChanged)
        local setting = Settings.RegisterAddOnSetting(
            category,
            "SelfCare_" .. varKey,  -- globally unique variable name
            varKey,                  -- key within variableTbl
            SelfCareDB,              -- the table to read/write
            Settings.VarType.Boolean,
            displayName,
            DEFAULTS[varKey]
        )
        if onChanged then
            setting:SetValueChangedCallback(onChanged)
        end
        Settings.CreateCheckbox(category, setting, tooltip)
        return setting
    end

    -- -----------------------------------------------------------------------
    -- Helper: make a slider backed by a proxy (seconds <-> minutes conversion)
    -- -----------------------------------------------------------------------
    local function MakeIntervalSlider(varKey, displayName, tooltip, onChanged)
        -- Proxy: UI shows minutes; DB stores seconds
        local function GetValue()
            return math.floor((SelfCareDB[varKey] or DEFAULTS[varKey]) / 60)
        end
        local function SetValue(minutes)
            SelfCareDB[varKey] = minutes * 60
            if onChanged then onChanged(minutes) end
        end

        local setting = Settings.RegisterProxySetting(
            category,
            "SelfCare_" .. varKey,   -- unique variable name
            Settings.VarType.Number,
            displayName,
            math.floor(DEFAULTS[varKey] / 60),
            GetValue,
            SetValue
        )

        local sliderOptions = Settings.CreateSliderOptions(5, 300, 5)
        sliderOptions:SetLabelFormatter(
            MinimalSliderWithSteppersMixin.Label.Right,
            function(value)
                if value >= 60 then
                    return string.format("%dh %dm", math.floor(value / 60), value % 60)
                end
                return value .. " min"
            end
        )

        Settings.CreateSlider(category, setting, sliderOptions, tooltip)
        return setting
    end

    -- -----------------------------------------------------------------------
    -- GLOBAL OPTIONS
    -- -----------------------------------------------------------------------
    Settings.CreateSectionHeader(category, "Global Options")

    MakeCheckbox("disableInCombat",   "Disable during combat",
        "Hold alerts while you are in combat and show them after combat ends.")

    MakeCheckbox("disableInCutscene", "Disable during cutscenes",
        "Hold alerts during in-game cinematics.")

    MakeCheckbox("printToChat",       "Print reminders to chat",
        "Also print the reminder message to your chat box.")

    MakeCheckbox("dismissOnClick",    "Click to dismiss (uncheck = auto-dismiss)",
        "If checked, the alert frame stays until you click it. "
        .. "If unchecked, it auto-dismisses after the configured delay.")

    -- -----------------------------------------------------------------------
    -- PER-ALERT OPTIONS
    -- -----------------------------------------------------------------------
    for _, alert in ipairs(ALERTS) do
        local key = alert.key

        Settings.CreateSectionHeader(category, alert.label)

        -- Enable/disable checkbox
        MakeCheckbox(
            key .. "Enabled",
            "Enable " .. alert.label .. " reminder",
            "Toggle the " .. alert.label:lower() .. " timer on or off.",
            function(setting, value)
                StartTimer(alert)
            end
        )

        -- Interval slider (minutes)
        MakeIntervalSlider(
            key .. "Interval",
            alert.label .. " interval (minutes)",
            string.format(
                "How often (in minutes) to show the %s reminder. Current message: \"%s\"",
                alert.label:lower(), alert.message
            ),
            function(minutes)
                StartTimer(alert)
            end
        )
    end

    -- Register and cache the category
    Settings.RegisterAddOnCategory(category)
    SelfCareCategory = category
end

-- ---------------------------------------------------------------------------
-- 9. SLASH COMMAND
-- ---------------------------------------------------------------------------
SLASH_SELFCARE1 = "/selfcare"
SlashCmdList["SELFCARE"] = function(msg)
    local cmd = msg and msg:lower():match("^%s*(.-)%s*$") or ""

    if cmd == "test" then
        -- Fire all three alerts immediately for testing
        for _, alert in ipairs(ALERTS) do
            SelfCare_ShowNotif(alert)
        end
        return
    end

    -- Default: open the settings panel
    if SelfCareCategory then
        Settings.OpenToCategory(SelfCareCategory)
    else
        print("|cff66ccff[SelfCare]|r Settings panel not yet initialized.")
    end
end

-- ---------------------------------------------------------------------------
-- 10. PUBLIC CONVENIENCE FUNCTIONS (useful for macros / other addons)
-- ---------------------------------------------------------------------------

--- Restart all active timers (e.g., call after manually editing SelfCareDB).
function SelfCare_RestartTimers()
    StopAllTimers()
    StartAllTimers()
    print("|cff66ccff[SelfCare]|r Timers restarted.")
end

--- Immediately show a test notification for a given alert key ("hydrate", "posture", "break").
function SelfCare_TestAlert(alertKey)
    for _, alert in ipairs(ALERTS) do
        if alert.key == alertKey then
            SelfCare_ShowNotif(alert)
            return
        end
    end
    print(string.format("|cff66ccff[SelfCare]|r Unknown alert key '%s'. Use: hydrate, posture, break", alertKey))
end
