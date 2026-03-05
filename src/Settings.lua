-- =============================================================================
-- Settings.lua
-- Post-11.0.2 Settings API panel. Builds once on ADDON_LOADED.
-- SelfCareCategory is private to this file; the handle is also exposed as
-- SelfCare.Category so Init.lua can read its ID for OpenToCategory.
-- =============================================================================

function SelfCare.BuildSettingsPanel()
    if SelfCare.Category then return end  -- already built

    local category, layout = Settings.RegisterVerticalLayoutCategory("SelfCare")
    local DEFAULTS = SelfCare.DEFAULTS

    -- -----------------------------------------------------------------------
    -- Helper: checkbox backed directly by SelfCareDB[varKey]
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
    -- Helper: slider backed by a proxy (seconds <-> minutes conversion)
    -- -----------------------------------------------------------------------
    local function MakeIntervalSlider(varKey, displayName, tooltip, onChanged)
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
    MakeCheckbox("disableInCombat",   "Disable during combat",
        "Hold alerts while you are in combat and show them after combat ends.")

    MakeCheckbox("disableInCutscene", "Disable during cutscenes",
        "Hold alerts during in-game cinematics.")

    MakeCheckbox("printToChat",       "Print reminders to chat",
        "Also print the reminder message to your chat box.")

    MakeCheckbox("dismissOnClick",    "Click to dismiss (uncheck = auto-dismiss)",
        "If checked, the alert frame stays until you click it. "
        .. "If unchecked, it auto-dismisses after the configured delay.")

    local delaySetting = Settings.RegisterAddOnSetting(
        category,
        "SelfCare_dismissDelay",
        "dismissDelay",
        SelfCareDB,
        Settings.VarType.Number,
        "Auto-dismiss delay (seconds)",
        DEFAULTS.dismissDelay
    )
    local delayOptions = Settings.CreateSliderOptions(3, 60, 1)
    delayOptions:SetLabelFormatter(
        MinimalSliderWithSteppersMixin.Label.Right,
        function(value) return value .. "s" end
    )
    Settings.CreateSlider(category, delaySetting, delayOptions,
        "How many seconds before the alert disappears (when click-to-dismiss is off).")

    -- -----------------------------------------------------------------------
    -- PER-ALERT OPTIONS
    -- -----------------------------------------------------------------------
    for _, alert in ipairs(SelfCare.ALERTS) do
        MakeCheckbox(
            SelfCare.EnabledKey(alert),
            "Enable " .. alert.label .. " reminder",
            "Toggle the " .. alert.label:lower() .. " timer on or off.",
            function(setting, value)
                SelfCare.StartTimer(alert)
            end
        )

        MakeIntervalSlider(
            SelfCare.IntervalKey(alert),
            alert.label .. " interval (minutes)",
            string.format(
                "How often (in minutes) to show the %s reminder. Current message: \"%s\"",
                alert.label:lower(), alert.message
            ),
            function(minutes)
                SelfCare.StartTimer(alert)
            end
        )
    end

    -- -----------------------------------------------------------------------
    -- TEST BUTTON  (CreateSettingsButtonInitializer is a Blizzard global)
    -- Args: labelText, buttonText, onClick, tooltipText, isEnabled
    -- -----------------------------------------------------------------------
    layout:AddInitializer(CreateSettingsButtonInitializer(
        "Preview your reminders",
        "Test All Alerts",
        SelfCare.TestAllAlerts,
        "Fire all three reminders immediately to preview how they look.",
        true
    ))

    -- Register and expose the category
    Settings.RegisterAddOnCategory(category)
    SelfCare.Category = category
end
