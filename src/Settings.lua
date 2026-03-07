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
    -- Helper: enable/disable an initializer. SetEnabled may not exist in all
    -- WoW versions; fall back to setting data.enabled directly (same effect).
    -- -----------------------------------------------------------------------
    local function SetInitEnabled(initializer, enabled)
        if not initializer then return end
        if initializer.SetEnabled then
            initializer:SetEnabled(enabled)
        elseif initializer.data then
            initializer.data.enabled = enabled
        end
    end

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

        local initializer = Settings.CreateSlider(category, setting, sliderOptions, tooltip)
        return initializer
    end

    -- -----------------------------------------------------------------------
    -- GLOBAL OPTIONS
    -- -----------------------------------------------------------------------

    -- Alert sound dropdown
    local soundSetting = Settings.RegisterAddOnSetting(
        category,
        "SelfCare_alertSound",
        "alertSound",
        SelfCareDB,
        Settings.VarType.Number,
        "Alert sound",
        DEFAULTS.alertSound
    )
    soundSetting:SetValueChangedCallback(function(_, newValue)
        if newValue ~= 0 then
            PlaySound(newValue, "SFX")
        end
    end)
    local function GetSoundOptions()
        local container = Settings.CreateControlTextContainer()
        for _, entry in ipairs(SelfCare.SOUNDS) do
            container:Add(entry[2], entry[1])
        end
        return container:GetData()
    end
    Settings.CreateDropdown(category, soundSetting, GetSoundOptions,
        "Sound to play when a reminder pops up. Set to None to disable alert sounds.")

    MakeCheckbox("disableInCombat",   "Disable during combat",
        "Timers keep running during combat. Alerts that fire while in combat are queued "
        .. "and shown immediately when combat ends.")

    MakeCheckbox("disableInCutscene", "Disable during cutscenes",
        "Hold alerts during in-game cinematics.")

    MakeCheckbox("disableWhenAFK",    "Pause during AFK",
        "Alerts that fire while you are AFK are queued and shown when you return.")

    MakeCheckbox("printToChat",       "Print reminders to chat",
        "Also print the reminder message to your chat box.")

    -- Forward ref so the callback can reach the delay slider initializer
    local delayInitializer

    MakeCheckbox("autoDismiss", "Auto-dismiss",
        "Automatically hide the notification after the delay below. Click always dismisses.",
        function(_, value)
            SetInitEnabled(delayInitializer, value)
        end
    )

    local delaySettingObj = Settings.RegisterAddOnSetting(
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
    delayInitializer = Settings.CreateSlider(category, delaySettingObj, delayOptions,
        "How many seconds before the notification disappears automatically.")
    SetInitEnabled(delayInitializer, SelfCareDB.autoDismiss)  -- grey out on load if off

    -- -----------------------------------------------------------------------
    -- PER-ALERT OPTIONS
    -- -----------------------------------------------------------------------
    for _, alert in ipairs(SelfCare.ALERTS) do
        local intervalInitializer  -- forward ref so checkbox callback can reach it

        MakeCheckbox(
            SelfCare.EnabledKey(alert),
            "Enable " .. alert.label .. " reminder",
            "Toggle the " .. alert.label:lower() .. " timer on or off.",
            function(_, value)
                SelfCare.StartTimer(alert)
                SetInitEnabled(intervalInitializer, value)
            end
        )

        intervalInitializer = MakeIntervalSlider(
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
        SetInitEnabled(intervalInitializer, SelfCareDB[SelfCare.EnabledKey(alert)])  -- grey out if disabled on load
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
