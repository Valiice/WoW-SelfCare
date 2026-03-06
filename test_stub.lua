-- =============================================================================
-- test_stub.lua
-- Stubs for WoW API so we can load the SelfCare addon files in a plain
-- Lua 5.1 interpreter.
-- Run: lua test_stub.lua
-- =============================================================================

-- Track what happened during loading for verification
local log = {}
local function LOG(msg) log[#log+1] = msg end

-- ---------------------------------------------------------------------------
-- Fake frame objects
-- ---------------------------------------------------------------------------
local function MakeFakeFrame(frameType, name, parent)
    local scripts = {}
    local points = {}
    local shown = false
    local alpha = 1
    local f = {
        _type = frameType or "Frame",
        _name = name,
        SetSize = function(self, w, h) end,
        SetPoint = function(self, ...) end,
        SetFrameStrata = function(self, s) end,
        SetFrameLevel = function(self, l) end,
        EnableMouse = function(self, b) end,
        SetMovable = function(self, b) end,
        RegisterForDrag = function(self, btn) end,
        StartMoving = function(self) end,
        StopMovingOrSizing = function(self) end,
        SetScript = function(self, event, fn) scripts[event] = fn end,
        GetScript = function(self, event) return scripts[event] end,
        RegisterEvent = function(self, event) LOG("RegisterEvent: " .. event) end,
        UnregisterEvent = function(self, event) end,
        Show = function(self) shown = true end,
        Hide = function(self) shown = false end,
        IsShown = function(self) return shown end,
        SetAlpha = function(self, a) alpha = a end,
        GetAlpha = function(self) return alpha end,
        CreateFontString = function(self, name, layer, template)
            return {
                SetAllPoints = function() end,
                SetJustifyH = function() end,
                SetJustifyV = function() end,
                SetWordWrap = function() end,
                SetTextColor = function() end,
                SetText = function(self, t) LOG("SetText: " .. tostring(t)) end,
                SetPoint = function() end,
            }
        end,
        -- Fire a script handler (for testing)
        _FireEvent = function(self, event, ...)
            if scripts["OnEvent"] then
                scripts["OnEvent"](self, event, ...)
            end
        end,
    }
    return f
end

-- ---------------------------------------------------------------------------
-- WoW Global API stubs
-- ---------------------------------------------------------------------------
function CreateFrame(frameType, name, parent, template)
    LOG("CreateFrame: " .. tostring(frameType) .. " / " .. tostring(name))
    local frame = MakeFakeFrame(frameType, name, parent)
    -- WoW sets named frames as globals
    if name then
        _G[name] = frame
    end
    return frame
end

UIParent = MakeFakeFrame("Frame", "UIParent")

function InCombatLockdown() return false end

function PlaySound(id, channel)
    LOG("PlaySound: " .. tostring(id) .. " / " .. tostring(channel))
end

local _cvars = {}
function GetCVar(key)
    return _cvars[key] or "1"
end
function SetCVar(key, value)
    LOG("SetCVar: " .. tostring(key) .. " = " .. tostring(value))
    _cvars[key] = tostring(value)
end

function UIFrameFadeIn(frame, duration, startAlpha, endAlpha)
    LOG("UIFrameFadeIn")
    if frame then frame:SetAlpha(endAlpha or 1) end
end

function UIFrameFadeOut(frame, duration, startAlpha, endAlpha)
    LOG("UIFrameFadeOut")
    if frame then frame:SetAlpha(endAlpha or 0) end
end

MovieFrame = MakeFakeFrame("Frame", "MovieFrame")

-- ---------------------------------------------------------------------------
-- C_Timer stub — records calls but doesn't actually tick
-- ---------------------------------------------------------------------------
local timerCount = 0
C_Timer = {
    NewTicker = function(interval, fn)
        timerCount = timerCount + 1
        local id = timerCount
        LOG(string.format("C_Timer.NewTicker: interval=%ds (id=%d)", interval, id))
        return { Cancel = function() LOG("Timer " .. id .. " cancelled") end }
    end,
    NewTimer = function(delay, fn)
        timerCount = timerCount + 1
        local id = timerCount
        LOG(string.format("C_Timer.NewTimer: delay=%.2fs (id=%d)", delay, id))
        return { Cancel = function() LOG("Timer " .. id .. " cancelled") end }
    end,
}

-- ---------------------------------------------------------------------------
-- Settings API stub (post-11.0.2)
-- ---------------------------------------------------------------------------
local settingsRegistered = {}

Settings = {
    VarType = { Boolean = 1, Number = 2, String = 3 },

    RegisterVerticalLayoutCategory = function(name)
        LOG("Settings.RegisterVerticalLayoutCategory: " .. name)
        local layout = {
            AddInitializer = function(self, initializer)
                LOG("Layout:AddInitializer")
                return initializer
            end,
        }
        local cat = { name = name }
        return cat, layout
    end,

    RegisterAddOnSetting = function(category, variable, variableKey, variableTbl, varType, displayName, default)
        LOG("RegisterAddOnSetting: " .. tostring(variable) .. " = " .. tostring(displayName))
        settingsRegistered[variable] = true
        return {
            SetValueChangedCallback = function(self, fn)
                LOG("  -> SetValueChangedCallback registered for " .. tostring(variable))
            end,
            SetEnabled = function(self, enabled)
                LOG("  -> SetEnabled(" .. tostring(enabled) .. ") for " .. tostring(variable))
            end,
        }
    end,

    RegisterProxySetting = function(category, variable, varType, displayName, default, getter, setter)
        LOG("RegisterProxySetting: " .. tostring(variable) .. " = " .. tostring(displayName))
        settingsRegistered[variable] = true
        return {
            SetValueChangedCallback = function(self, fn) end,
            SetEnabled = function(self, enabled)
                LOG("  -> SetEnabled(" .. tostring(enabled) .. ") for " .. tostring(variable))
            end,
        }
    end,

    CreateCheckbox = function(category, setting, tooltip)
        LOG("CreateCheckbox")
        local variable = setting and setting.variable or "?"
        return {
            SetEnabled = function(self, enabled)
                LOG("  -> Initializer:SetEnabled(" .. tostring(enabled) .. ") for " .. tostring(variable))
            end,
        }
    end,

    CreateDropdown = function(category, setting, optionsGenerator, tooltip)
        LOG("CreateDropdown")
    end,

    CreateControlTextContainer = function()
        local items = {}
        return {
            Add = function(self, value, label)
                table.insert(items, { value = value, label = label })
            end,
            GetData = function(self) return items end,
        }
    end,

    CreateSlider = function(category, setting, options, tooltip)
        LOG("CreateSlider")
        local variable = setting and setting.variable or "?"
        return {
            SetEnabled = function(self, enabled)
                LOG("  -> Initializer:SetEnabled(" .. tostring(enabled) .. ") for " .. tostring(variable))
            end,
        }
    end,

    CreateSliderOptions = function(min, max, step)
        return {
            SetLabelFormatter = function(self, labelType, fn) end,
        }
    end,

    CreateSectionHeader = function(category, text)
        LOG("CreateSectionHeader: " .. tostring(text))
    end,

    RegisterAddOnCategory = function(category)
        LOG("Settings.RegisterAddOnCategory")
    end,

    OpenToCategory = function(category)
        LOG("Settings.OpenToCategory")
    end,
}

MinimalSliderWithSteppersMixin = {
    Label = { Right = 1 }
}

-- Blizzard global — creates a layout-compatible button element initializer
function CreateSettingsButtonInitializer(labelText, buttonText, onClick, tooltip, enabled)
    LOG("CreateSettingsButtonInitializer: " .. tostring(buttonText))
    return { labelText = labelText, buttonText = buttonText }
end

function CreateSettingsListSectionHeaderInitializer(text)
    LOG("CreateSettingsListSectionHeaderInitializer: " .. tostring(text))
    return { text = text }
end

-- ---------------------------------------------------------------------------
-- Slash command stubs
-- ---------------------------------------------------------------------------
SlashCmdList = SlashCmdList or {}

-- ---------------------------------------------------------------------------
-- Load addon files in TOC order
-- ---------------------------------------------------------------------------
local addonFiles = {
    "src/Core.lua",
    "src/Notifications.lua",
    "src/Timers.lua",
    "src/Settings.lua",
    "src/Init.lua",
}

for _, filename in ipairs(addonFiles) do
    print("=== Loading " .. filename .. " ===")
    local ok, err = pcall(dofile, filename)
    if not ok then
        print("\n*** LOAD ERROR in " .. filename .. " ***")
        print(err)
        os.exit(1)
    end
    print("=== " .. filename .. " OK ===\n")
end

-- ---------------------------------------------------------------------------
-- Namespace integrity check
-- ---------------------------------------------------------------------------
print("--- Namespace integrity check ---")
local expectedKeys = {
    "DEFAULTS", "ALERTS", "SOUNDS",
    "Print", "ApplyDefaults", "FindAlertByKey", "EnabledKey", "IntervalKey",
    "ShowNotif", "HideNotif",
    "StartTimer", "StartAllTimers", "StopAllTimers", "FlushPending", "RestartTimers",
    "BuildSettingsPanel", "Category",
    "TestAlert", "TestAllAlerts",
}
local nsFail = 0
for _, k in ipairs(expectedKeys) do
    -- Category is set during BuildSettingsPanel (after ADDON_LOADED), skip here
    if k ~= "Category" and SelfCare[k] == nil then
        print("  MISSING: SelfCare." .. k)
        nsFail = nsFail + 1
    end
end
if nsFail == 0 then
    print("  All namespace keys present.")
else
    print(string.format("  %d missing key(s).", nsFail))
    os.exit(1)
end

-- ---------------------------------------------------------------------------
-- Simulate ADDON_LOADED event
-- ---------------------------------------------------------------------------
print("\n--- Simulating ADDON_LOADED ---")
local addonFrame = SelfCareAddonFrame
if addonFrame and addonFrame._FireEvent then
    addonFrame:_FireEvent("ADDON_LOADED", "SelfCare")
else
    print("WARNING: Could not find SelfCareAddonFrame")
end

-- After ADDON_LOADED, SelfCare.Category should be set
if SelfCare.Category == nil then
    print("FAIL: SelfCare.Category is nil after BuildSettingsPanel")
    os.exit(1)
end
print("  SelfCare.Category set OK")

-- ---------------------------------------------------------------------------
-- Simulate PLAYER_LOGIN (starts timers)
-- ---------------------------------------------------------------------------
print("\n--- Simulating PLAYER_LOGIN ---")
if addonFrame and addonFrame._FireEvent then
    addonFrame:_FireEvent("PLAYER_LOGIN")
end

-- ---------------------------------------------------------------------------
-- Test slash command
-- ---------------------------------------------------------------------------
print("\n--- Testing /selfcare test ---")
if SlashCmdList["SELFCARE"] then
    SlashCmdList["SELFCARE"]("test")
else
    print("WARNING: Slash command not registered")
end

-- ---------------------------------------------------------------------------
-- Test individual alert
-- ---------------------------------------------------------------------------
print("\n--- Testing SelfCare_TestAlert('hydrate') ---")
if SelfCare_TestAlert then
    SelfCare_TestAlert("hydrate")
end

print("\n--- Testing SelfCare_TestAlert('invalid') ---")
if SelfCare_TestAlert then
    SelfCare_TestAlert("invalid")
end

-- ---------------------------------------------------------------------------
-- Backwards-compat alias assertions
-- ---------------------------------------------------------------------------
print("\n--- Backwards-compat alias checks ---")
local aliases = {
    "SelfCare_ShowNotif",
    "SelfCare_HideNotif",
    "SelfCare_RestartTimers",
    "SelfCare_TestAlert",
}
local aliasFail = 0
for _, name in ipairs(aliases) do
    if _G[name] == nil then
        print("  MISSING global alias: " .. name)
        aliasFail = aliasFail + 1
    end
end
if aliasFail == 0 then
    print("  All global aliases present.")
end

-- ---------------------------------------------------------------------------
-- Verify DB defaults were applied
-- ---------------------------------------------------------------------------
print("\n--- Checking SelfCareDB ---")
local checks = {
    {"hydrateEnabled",  true},
    {"hydrateInterval", 3600},
    {"postureEnabled",  true},
    {"postureInterval", 1800},
    {"breakEnabled",    true},
    {"breakInterval",   8400},
    {"disableInCombat", true},
    {"printToChat",     true},
    {"autoDismiss",     true},
    {"alertSound",      808},
    {"alertVolume",     100},
}

local pass = 0
local fail = 0
for _, check in ipairs(checks) do
    local key, expected = check[1], check[2]
    local actual = SelfCareDB[key]
    if actual == expected then
        pass = pass + 1
    else
        fail = fail + 1
        print(string.format("  FAIL: SelfCareDB.%s = %s (expected %s)", key, tostring(actual), tostring(expected)))
    end
end
print(string.format("  DB checks: %d passed, %d failed", pass, fail))

-- ---------------------------------------------------------------------------
-- Print full event log
-- ---------------------------------------------------------------------------
print("\n--- Full event log ---")
for i, msg in ipairs(log) do
    print(string.format("  [%02d] %s", i, msg))
end

local totalFail = fail + aliasFail + nsFail
print(string.format("\n=== RESULT: %s ===", totalFail == 0 and "ALL TESTS PASSED" or (totalFail .. " FAILURES")))
if totalFail > 0 then os.exit(1) end
