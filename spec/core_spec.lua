-- =============================================================================
-- spec/core_spec.lua
-- Unit tests for src/Core.lua: DEFAULTS, ALERTS, ApplyDefaults, helpers.
-- =============================================================================

dofile("spec/stubs/wow_api.lua")
dofile("spec/helpers/load_addon.lua")

describe("Core", function()

    before_each(function()
        WowStubs_Reset()
        C_Timer.Reset()
        LoadAddon()
    end)

    -- -------------------------------------------------------------------------
    describe("DEFAULTS", function()
        it("contains all expected keys", function()
            local d = SelfCare.DEFAULTS
            assert.is_not_nil(d.hydrateEnabled)
            assert.is_not_nil(d.hydrateInterval)
            assert.is_not_nil(d.postureEnabled)
            assert.is_not_nil(d.postureInterval)
            assert.is_not_nil(d.breakEnabled)
            assert.is_not_nil(d.breakInterval)
            assert.is_not_nil(d.disableInCombat)
            assert.is_not_nil(d.disableInCutscene)
            assert.is_not_nil(d.printToChat)
            assert.is_not_nil(d.autoDismiss)
            assert.is_not_nil(d.dismissDelay)
            assert.is_not_nil(d.alertSound)
        end)

        it("defaults alertSound to 808", function()
            assert.equal(808, SelfCare.DEFAULTS.alertSound)
        end)

        it("stores intervals in seconds", function()
            assert.equal(3600, SelfCare.DEFAULTS.hydrateInterval)   -- 60 min
            assert.equal(1800, SelfCare.DEFAULTS.postureInterval)   -- 30 min
            assert.equal(8400, SelfCare.DEFAULTS.breakInterval)     -- 140 min
        end)

        it("has sensible dismiss defaults", function()
            assert.is_true(SelfCare.DEFAULTS.autoDismiss)
            assert.equal(10, SelfCare.DEFAULTS.dismissDelay)
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("ALERTS", function()
        it("has exactly three entries", function()
            assert.equal(3, #SelfCare.ALERTS)
        end)

        it("each entry has key, label, and message", function()
            for _, alert in ipairs(SelfCare.ALERTS) do
                assert.is_string(alert.key)
                assert.is_string(alert.label)
                assert.is_string(alert.message)
                assert.truthy(#alert.key > 0)
                assert.truthy(#alert.message > 0)
            end
        end)

        it("keys are hydrate, posture, break in order", function()
            assert.equal("hydrate", SelfCare.ALERTS[1].key)
            assert.equal("posture", SelfCare.ALERTS[2].key)
            assert.equal("break",   SelfCare.ALERTS[3].key)
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("SOUNDS", function()
        it("is a non-empty table", function()
            assert.is_table(SelfCare.SOUNDS)
            assert.truthy(#SelfCare.SOUNDS > 0)
        end)

        it("each entry has a non-empty string label and a number soundID", function()
            for i, entry in ipairs(SelfCare.SOUNDS) do
                assert.is_string(entry[1],
                    "SOUNDS[" .. i .. "] label should be a string")
                assert.truthy(#entry[1] > 0,
                    "SOUNDS[" .. i .. "] label should not be empty")
                assert.is_number(entry[2],
                    "SOUNDS[" .. i .. "] soundID should be a number")
            end
        end)

        it("first entry is None with soundID 0", function()
            assert.equal("None", SelfCare.SOUNDS[1][1])
            assert.equal(0, SelfCare.SOUNDS[1][2])
        end)

        it("contains the default sound ID 808", function()
            local found = false
            for _, entry in ipairs(SelfCare.SOUNDS) do
                if entry[2] == 808 then found = true end
            end
            assert.is_true(found, "SOUNDS should contain soundID 808")
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("ApplyDefaults", function()
        it("populates an empty SelfCareDB with all DEFAULTS", function()
            -- Use WowStubs_SetDB to write directly to _G (bypasses busted setfenv)
            WowStubs_SetDB({})
            SelfCare.ApplyDefaults()
            for k, v in pairs(SelfCare.DEFAULTS) do
                assert.equal(v, SelfCareDB[k],
                    "SelfCareDB." .. k .. " not set correctly")
            end
        end)

        it("does not overwrite existing values", function()
            WowStubs_SetDB({ hydrateEnabled = false, hydrateInterval = 999 })
            SelfCare.ApplyDefaults()
            assert.equal(false, SelfCareDB.hydrateEnabled)
            assert.equal(999,   SelfCareDB.hydrateInterval)
        end)

        it("fills in only the missing keys when DB is partially populated", function()
            WowStubs_SetDB({ hydrateEnabled = false })
            SelfCare.ApplyDefaults()
            -- Non-overwritten keys get defaults
            assert.equal(SelfCare.DEFAULTS.postureEnabled,  SelfCareDB.postureEnabled)
            assert.equal(SelfCare.DEFAULTS.postureInterval, SelfCareDB.postureInterval)
            -- Pre-existing value preserved
            assert.equal(false, SelfCareDB.hydrateEnabled)
        end)

        it("handles nil SelfCareDB by creating it", function()
            -- SelfCareDB is already nil from WowStubs_Reset in before_each
            SelfCare.ApplyDefaults()
            assert.is_table(SelfCareDB)
            assert.equal(SelfCare.DEFAULTS.hydrateInterval, SelfCareDB.hydrateInterval)
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("FindAlertByKey", function()
        it("returns the correct alert for a valid key", function()
            local alert = SelfCare.FindAlertByKey("hydrate")
            assert.is_not_nil(alert)
            assert.equal("hydrate", alert.key)
        end)

        it("returns nil for an unknown key", function()
            assert.is_nil(SelfCare.FindAlertByKey("nonexistent"))
        end)

        it("returns nil for empty string", function()
            assert.is_nil(SelfCare.FindAlertByKey(""))
        end)

        it("finds all three defined keys", function()
            assert.is_not_nil(SelfCare.FindAlertByKey("hydrate"))
            assert.is_not_nil(SelfCare.FindAlertByKey("posture"))
            assert.is_not_nil(SelfCare.FindAlertByKey("break"))
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("EnabledKey / IntervalKey", function()
        it("EnabledKey appends 'Enabled' to alert.key", function()
            local alert = { key = "hydrate" }
            assert.equal("hydrateEnabled", SelfCare.EnabledKey(alert))
        end)

        it("IntervalKey appends 'Interval' to alert.key", function()
            local alert = { key = "posture" }
            assert.equal("postureInterval", SelfCare.IntervalKey(alert))
        end)

        it("EnabledKey matches DEFAULTS key for all alerts", function()
            for _, alert in ipairs(SelfCare.ALERTS) do
                local k = SelfCare.EnabledKey(alert)
                assert.is_not_nil(SelfCare.DEFAULTS[k],
                    "DEFAULTS missing key: " .. k)
            end
        end)

        it("IntervalKey matches DEFAULTS key for all alerts", function()
            for _, alert in ipairs(SelfCare.ALERTS) do
                local k = SelfCare.IntervalKey(alert)
                assert.is_not_nil(SelfCare.DEFAULTS[k],
                    "DEFAULTS missing key: " .. k)
            end
        end)
    end)

end)
