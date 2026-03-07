-- =============================================================================
-- spec/init_spec.lua
-- Integration tests for src/Init.lua: event flow, slash command, TestAlert.
-- =============================================================================

dofile("spec/stubs/wow_api.lua")
dofile("spec/helpers/load_addon.lua")

describe("Init", function()

    before_each(function()
        WowStubs_Reset()
        C_Timer.Reset()
        LoadAddon()
        -- Note: LoadAddon() runs Init.lua which fires CreateFrame at module level,
        -- so SelfCareAddonFrame is available after loading.
    end)

    -- -------------------------------------------------------------------------
    describe("ADDON_LOADED event", function()
        it("calls ApplyDefaults", function()
            local called = false
            local orig = SelfCare.ApplyDefaults
            SelfCare.ApplyDefaults = function(...)
                called = true
                return orig(...)
            end

            SelfCareAddonFrame:_FireEvent("ADDON_LOADED", "SelfCare")
            assert.is_true(called)
        end)

        it("calls BuildSettingsPanel", function()
            local called = false
            local orig = SelfCare.BuildSettingsPanel
            SelfCare.BuildSettingsPanel = function(...)
                called = true
                return orig(...)
            end

            SelfCareAddonFrame:_FireEvent("ADDON_LOADED", "SelfCare")
            assert.is_true(called)
        end)

        it("sets SelfCare.Category after ADDON_LOADED", function()
            SelfCareAddonFrame:_FireEvent("ADDON_LOADED", "SelfCare")
            assert.is_not_nil(SelfCare.Category)
        end)

        it("ignores ADDON_LOADED for other addons", function()
            local called = false
            SelfCare.ApplyDefaults = function() called = true end

            SelfCareAddonFrame:_FireEvent("ADDON_LOADED", "SomeOtherAddon")
            assert.is_false(called)
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("PLAYER_LOGIN event", function()
        it("calls StartAllTimers", function()
            -- First fire ADDON_LOADED so SelfCareDB is set up
            SelfCareAddonFrame:_FireEvent("ADDON_LOADED", "SelfCare")

            local called = false
            SelfCare.StartAllTimers = function() called = true end

            SelfCareAddonFrame:_FireEvent("PLAYER_LOGIN")
            assert.is_true(called)
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("PLAYER_REGEN_ENABLED event (combat ends)", function()
        it("calls FlushPending", function()
            local called = false
            SelfCare.FlushPending = function() called = true end

            SelfCareAddonFrame:_FireEvent("PLAYER_REGEN_ENABLED")
            assert.is_true(called)
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("CINEMATIC_STOP event", function()
        it("calls FlushPending", function()
            local called = false
            SelfCare.FlushPending = function() called = true end

            SelfCareAddonFrame:_FireEvent("CINEMATIC_STOP")
            assert.is_true(called)
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("slash command", function()
        before_each(function()
            -- ADDON_LOADED must fire first to set up SelfCare.Category
            SelfCareAddonFrame:_FireEvent("ADDON_LOADED", "SelfCare")
        end)

        it("/selfcare opens Settings.OpenToCategory", function()
            local opened = false
            Settings.OpenToCategory = function(id) opened = true end

            SlashCmdList["SELFCARE"]("")
            assert.is_true(opened)
        end)

        it("/selfcare test calls TestAllAlerts", function()
            local called = false
            SelfCare.TestAllAlerts = function() called = true end

            SlashCmdList["SELFCARE"]("test")
            assert.is_true(called)
        end)

        it("/selfcare test is case-insensitive", function()
            local called = false
            SelfCare.TestAllAlerts = function() called = true end

            SlashCmdList["SELFCARE"]("TEST")
            assert.is_true(called)
        end)

        it("/selfcare test trims surrounding whitespace", function()
            local called = false
            SelfCare.TestAllAlerts = function() called = true end

            SlashCmdList["SELFCARE"]("  test  ")
            assert.is_true(called)
        end)

    -- -------------------------------------------------------------------------
    describe("debug command", function()
        before_each(function()
            SelfCare.ApplyDefaults()
        end)

        it("prints a header line", function()
            local lines = {}
            SelfCare.Print = function(msg) table.insert(lines, msg) end
            SelfCareDB.nextDue = {}
            SlashCmdList["SELFCARE"]("debug")
            assert.truthy(lines[1] and lines[1]:find("Debug"))
        end)

        it("prints one line per alert plus header", function()
            local lines = {}
            SelfCare.Print = function(msg) table.insert(lines, msg) end
            SelfCareDB.nextDue = { hydrate = 2000, posture = 2000, ["break"] = 2000 }
            SlashCmdList["SELFCARE"]("debug")
            -- 1 header + N alert lines
            assert.equal(1 + #SelfCare.ALERTS, #lines)
        end)

        it("shows [disabled] for a disabled alert", function()
            local lines = {}
            SelfCare.Print = function(msg) table.insert(lines, msg) end
            SelfCareDB.hydrateEnabled = false
            SelfCareDB.nextDue = {}
            SlashCmdList["SELFCARE"]("debug")
            local found = false
            for _, l in ipairs(lines) do
                if l:find("hydrate") and l:find("disabled") then found = true end
            end
            assert.is_true(found)
        end)

        it("shows pending first fire when nextDue missing for alert", function()
            local lines = {}
            SelfCare.Print = function(msg) table.insert(lines, msg) end
            SelfCareDB.nextDue = {}
            SlashCmdList["SELFCARE"]("debug")
            local found = false
            for _, l in ipairs(lines) do
                if l:find("hydrate") and l:find("pending") then found = true end
            end
            assert.is_true(found)
        end)

        it("shows due time when nextDue is set", function()
            local lines = {}
            SelfCare.Print = function(msg) table.insert(lines, msg) end
            _G._now = 1000
            SelfCareDB.nextDue = { hydrate = 1300 }
            SlashCmdList["SELFCARE"]("debug")
            local found = false
            for _, l in ipairs(lines) do
                if l:find("hydrate") and l:find("due") and l:find("5m 0s") then found = true end
            end
            assert.is_true(found)
        end)
    end)

    end)

    -- -------------------------------------------------------------------------
    describe("TestAlert", function()
        before_each(function()
            SelfCareAddonFrame:_FireEvent("ADDON_LOADED", "SelfCare")
        end)

        it("shows notification for valid key", function()
            local shown = nil
            SelfCare.ShowNotif = function(alert) shown = alert end

            SelfCare.TestAlert("hydrate")
            assert.is_not_nil(shown)
            assert.equal("hydrate", shown.key)
        end)

        it("prints error message for invalid key without crashing", function()
            local printed = nil
            local origPrint = SelfCare.Print
            SelfCare.Print = function(msg) printed = msg end

            assert.has_no.errors(function()
                SelfCare.TestAlert("invalidkey")
            end)
            assert.is_not_nil(printed)
            assert.truthy(printed:find("invalidkey"))
        end)

        it("global alias SelfCare_TestAlert works", function()
            local shown = nil
            SelfCare.ShowNotif = function(alert) shown = alert end

            SelfCare_TestAlert("posture")
            assert.is_not_nil(shown)
            assert.equal("posture", shown.key)
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("TestAllAlerts", function()
        before_each(function()
            SelfCareAddonFrame:_FireEvent("ADDON_LOADED", "SelfCare")
        end)

        it("calls ShowNotif for every alert", function()
            local shown = {}
            SelfCare.ShowNotif = function(alert) table.insert(shown, alert.key) end

            SelfCare.TestAllAlerts()
            assert.equal(#SelfCare.ALERTS, #shown)
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("format helpers (via debug output)", function()
        before_each(function()
            SelfCareAddonFrame:_FireEvent("ADDON_LOADED", "SelfCare")
            SelfCare.ApplyDefaults()
        end)

        local function debugLines()
            local lines = {}
            SelfCare.Print = function(msg) table.insert(lines, msg) end
            return lines
        end

        local function hydrateLineWith(nextDue, now)
            _G._now = now or 1000
            SelfCareDB.nextDue = { hydrate = nextDue }
            local lines = debugLines()
            SlashCmdList["SELFCARE"]("debug")
            for _, l in ipairs(lines) do
                if l:find("hydrate") then return l end
            end
        end

        -- FormatInterval via the interval label
        it("FormatInterval shows minutes for sub-hour intervals", function()
            SelfCareDB.hydrateInterval = 300  -- 5 min
            SelfCareDB.nextDue = {}
            local lines = debugLines()
            SlashCmdList["SELFCARE"]("debug")
            local found = false
            for _, l in ipairs(lines) do
                if l:find("hydrate") and l:find("5 min") then found = true end
            end
            assert.is_true(found)
        end)

        it("FormatInterval shows hours for >= 60 min intervals", function()
            SelfCareDB.hydrateInterval = 7200  -- 2h
            SelfCareDB.nextDue = {}
            local lines = debugLines()
            SlashCmdList["SELFCARE"]("debug")
            local found = false
            for _, l in ipairs(lines) do
                if l:find("hydrate") and l:find("2h") then found = true end
            end
            assert.is_true(found)
        end)

        -- FormatRemaining boundary cases
        it("FormatRemaining shows overdue when remaining <= 0", function()
            local line = hydrateLineWith(500, 1000)  -- nextDue in past
            assert.truthy(line and line:find("overdue"))
        end)

        it("FormatRemaining shows seconds only for < 60s remaining", function()
            local line = hydrateLineWith(1059, 1000)  -- 59s remaining
            assert.truthy(line and line:find("59s"))
        end)

        it("FormatRemaining shows minutes and seconds for < 1h remaining", function()
            local line = hydrateLineWith(1060, 1000)  -- 60s = 1m 0s remaining
            assert.truthy(line and line:find("1m 0s"))
        end)

        it("FormatRemaining shows hours and minutes for >= 1h remaining", function()
            local line = hydrateLineWith(4600, 1000)  -- 3600s = 1h 0m remaining
            assert.truthy(line and line:find("1h 0m"))
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("backwards-compatibility globals", function()
        it("SelfCare_ShowNotif is set", function()
            assert.is_function(SelfCare_ShowNotif)
        end)

        it("SelfCare_HideNotif is set", function()
            assert.is_function(SelfCare_HideNotif)
        end)

        it("SelfCare_RestartTimers is set", function()
            assert.is_function(SelfCare_RestartTimers)
        end)

        it("SelfCare_TestAlert is set", function()
            assert.is_function(SelfCare_TestAlert)
        end)
    end)

end)
