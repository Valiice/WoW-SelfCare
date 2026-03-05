-- =============================================================================
-- test_stub.lua
-- Stubs for WoW API so we can load SelfCare.lua in a plain Lua 5.1 interpreter.
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

function PlaySound(id)
    LOG("PlaySound: " .. tostring(id))
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
        return { name = name }
    end,

    RegisterAddOnSetting = function(category, variable, variableKey, variableTbl, varType, displayName, default)
        LOG("RegisterAddOnSetting: " .. tostring(variable) .. " = " .. tostring(displayName))
        settingsRegistered[variable] = true
        return {
            SetValueChangedCallback = function(self, fn)
                LOG("  -> SetValueChangedCallback registered for " .. tostring(variable))
            end,
        }
    end,

    RegisterProxySetting = function(category, variable, varType, displayName, default, getter, setter)
        LOG("RegisterProxySetting: " .. tostring(variable) .. " = " .. tostring(displayName))
        settingsRegistered[variable] = true
        return {
            SetValueChangedCallback = function(self, fn) end,
        }
    end,

    CreateCheckbox = function(category, setting, tooltip)
        LOG("CreateCheckbox")
    end,

    CreateSlider = function(category, setting, options, tooltip)
        LOG("CreateSlider")
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

-- ---------------------------------------------------------------------------
-- Slash command stubs
-- ---------------------------------------------------------------------------
SlashCmdList = SlashCmdList or {}

-- ---------------------------------------------------------------------------
-- Load the addon
-- ---------------------------------------------------------------------------
print("=== Loading SelfCare.lua ===")
local ok, err = pcall(dofile, "SelfCare.lua")

if not ok then
    print("\n*** LOAD ERROR ***")
    print(err)
    os.exit(1)
end

print("=== Load OK ===\n")

-- ---------------------------------------------------------------------------
-- Simulate ADDON_LOADED event
-- ---------------------------------------------------------------------------
print("--- Simulating ADDON_LOADED ---")
local addonFrame = SelfCareAddonFrame
if addonFrame and addonFrame._FireEvent then
    addonFrame:_FireEvent("ADDON_LOADED", "SelfCare")
else
    print("WARNING: Could not find SelfCareAddonFrame")
end

-- ---------------------------------------------------------------------------
-- Simulate PLAYER_LOGIN (starts timers)
-- ---------------------------------------------------------------------------
print("--- Simulating PLAYER_LOGIN ---")
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
    {"dismissOnClick",  true},
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

print(string.format("\n=== RESULT: %s ===", fail == 0 and "ALL TESTS PASSED" or (fail .. " FAILURES")))
