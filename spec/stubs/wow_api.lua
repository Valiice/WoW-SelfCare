-- =============================================================================
-- spec/stubs/wow_api.lua
-- WoW API global stubs for busted unit tests.
-- Set all globals before dofile()-ing any src/ files.
--
-- Key design: C_Timer captures callbacks so tests can fire them manually.
-- InCombatLockdown and MovieFrame.IsShown() are controllable via helpers.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- State control helpers (tests set these to simulate game state)
-- ---------------------------------------------------------------------------
_G._inCombat    = false
_G._inCutscene  = false
_G._isAFK       = false
_G._now         = 1000  -- controllable fake timestamp

function time()
    return _G._now
end

function InCombatLockdown()
    return _G._inCombat
end

function UnitIsAFK(unit)
    return _G._isAFK
end

-- ---------------------------------------------------------------------------
-- Fake frame factory
-- ---------------------------------------------------------------------------
local function MakeFakeFrame(frameType, name, parent)
    local scripts = {}
    local shown   = false
    local alpha   = 1

    local f = {
        _type = frameType or "Frame",
        _name = name,
        SetSize              = function() end,
        SetPoint             = function() end,
        SetFrameStrata       = function() end,
        SetFrameLevel        = function() end,
        EnableMouse          = function() end,
        SetMovable           = function() end,
        RegisterForDrag      = function() end,
        StartMoving          = function() end,
        StopMovingOrSizing   = function() end,
        GetPoint             = function() return "CENTER", nil, "CENTER", 0, 0 end,
        SetScript            = function(self, event, fn) scripts[event] = fn end,
        GetScript            = function(self, event) return scripts[event] end,
        RegisterEvent        = function() end,
        UnregisterEvent      = function() end,
        Show                 = function(self) shown = true end,
        Hide                 = function(self) shown = false end,
        IsShown              = function(self) return shown end,
        SetAlpha             = function(self, a) alpha = a end,
        GetAlpha             = function(self) return alpha end,
        CreateFontString     = function(self)
            return {
                SetAllPoints  = function() end,
                SetJustifyH   = function() end,
                SetJustifyV   = function() end,
                SetWordWrap   = function() end,
                SetTextColor  = function() end,
                SetText       = function(self, t) self._text = t end,
                GetText       = function(self) return self._text end,
                SetPoint      = function() end,
            }
        end,
        -- Fire an OnEvent script (test helper)
        _FireEvent = function(self, event, ...)
            if scripts["OnEvent"] then
                scripts["OnEvent"](self, event, ...)
            end
        end,
    }
    return f
end

-- ---------------------------------------------------------------------------
-- WoW globals
-- ---------------------------------------------------------------------------
function CreateFrame(frameType, name, parent, template)
    local frame = MakeFakeFrame(frameType, name, parent)
    if name then _G[name] = frame end
    return frame
end

UIParent = MakeFakeFrame("Frame", "UIParent")

MovieFrame = MakeFakeFrame("Frame", "MovieFrame")
-- Tests set _inCutscene; override IsShown to read it
MovieFrame.IsShown = function() return _G._inCutscene end

function PlaySound(id, channel)
    -- no-op by default; tests can override
end

local _cvars = {}
function GetCVar(key)
    return _cvars[key] or "1"
end
function SetCVar(key, value)
    _cvars[key] = tostring(value)
end

function UIFrameFadeIn(frame, duration, startAlpha, endAlpha)
    if frame then frame:SetAlpha(endAlpha or 1) end
end

function UIFrameFadeOut(frame, duration, startAlpha, endAlpha)
    if frame then frame:SetAlpha(endAlpha or 0) end
end

-- ---------------------------------------------------------------------------
-- C_Timer — captures callbacks so tests can fire them manually
-- ---------------------------------------------------------------------------
local _tickers     = {}
local _timers      = {}
local _afterTimers = {}

C_Timer = {
    NewTicker = function(interval, fn)
        local t = {
            interval  = interval,
            fn        = fn,
            cancelled = false,
            Cancel    = function(self) self.cancelled = true end,
            Fire      = function(self)
                if not self.cancelled then fn() end
            end,
        }
        table.insert(_tickers, t)
        return t
    end,

    NewTimer = function(delay, fn)
        local t = {
            delay     = delay,
            fn        = fn,
            cancelled = false,
            Cancel    = function(self) self.cancelled = true end,
            Fire      = function(self)
                if not self.cancelled then fn() end
            end,
        }
        table.insert(_timers, t)
        return t
    end,

    -- C_Timer.After: deferred one-shot; stored separately so GetTimers() stays
    -- clean for tests that index into it by position.
    After = function(delay, fn)
        local t = {
            delay     = delay,
            fn        = fn,
            cancelled = false,
            Cancel    = function(self) self.cancelled = true end,
            Fire      = function(self) if not self.cancelled then fn() end end,
        }
        table.insert(_afterTimers, t)
        return t
    end,

    -- Test helpers
    GetTickers     = function() return _tickers     end,
    GetTimers      = function() return _timers      end,
    GetAfterTimers = function() return _afterTimers end,

    -- Call between tests to clear captured handles
    Reset = function()
        _tickers     = {}
        _timers      = {}
        _afterTimers = {}
    end,
}

-- ---------------------------------------------------------------------------
-- Settings API (post-11.0.2)
-- ---------------------------------------------------------------------------
Settings = {
    VarType = { Boolean = 1, Number = 2, String = 3 },

    RegisterVerticalLayoutCategory = function(name)
        local layout = {
            AddInitializer = function(self, initializer) return initializer end,
        }
        return { name = name }, layout
    end,

    RegisterAddOnSetting = function(category, variable, variableKey, variableTbl, varType, displayName, default)
        return {
            SetValueChangedCallback = function(self, fn)
                self._onChange = fn
            end,
        }
    end,

    RegisterProxySetting = function(category, variable, varType, displayName, default, getter, setter)
        return {
            SetValueChangedCallback = function(self, fn) end,
        }
    end,

    CreateCheckbox    = function() end,
    CreateDropdown    = function() end,
    CreateSlider      = function() end,
    CreateControlTextContainer = function()
        local items = {}
        return {
            Add = function(self, value, label) table.insert(items, { value = value, label = label }) end,
            GetData = function(self) return items end,
        }
    end,
    CreateSliderOptions = function(min, max, step)
        return {
            SetLabelFormatter = function() end,
        }
    end,
    CreateSectionHeader = function() end,
    RegisterAddOnCategory = function() end,
    OpenToCategory    = function() end,
}

MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }

function CreateSettingsButtonInitializer(labelText, buttonText, onClick, tooltip, enabled)
    return { labelText = labelText, buttonText = buttonText }
end

function CreateSettingsListSectionHeaderInitializer(text)
    return { text = text }
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
SlashCmdList = SlashCmdList or {}

-- ---------------------------------------------------------------------------
-- Reset helper — call in before_each to get a clean slate.
-- All writes use rawset(_G) so they bypass busted's setfenv sandbox and
-- reach the real _G that the addon functions also use.
-- ---------------------------------------------------------------------------
function WowStubs_Reset()
    rawset(_G, "_inCombat",        false)
    rawset(_G, "_inCutscene",      false)
    rawset(_G, "_isAFK",           false)
    rawset(_G, "_now",             1000)
    rawset(_G, "SelfCareDB",       nil)
    rawset(_G, "SelfCare",         nil)
    rawset(_G, "SlashCmdList",     {})
    rawset(_G, "SelfCareAddonFrame", nil)
    _cvars = {}
    C_Timer.Reset()
end

--- Set SelfCareDB to a specific value from within a test body.
--- Must bypass busted's setfenv sandbox so the addon code sees the same table.
function WowStubs_SetDB(value)
    rawset(_G, "SelfCareDB", value)
end
