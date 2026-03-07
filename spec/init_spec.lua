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
