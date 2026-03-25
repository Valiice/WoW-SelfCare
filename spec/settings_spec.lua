-- =============================================================================
-- spec/settings_spec.lua
-- Unit tests for src/Settings.lua: panel construction, Classic Era compat.
-- =============================================================================

dofile("spec/stubs/wow_api.lua")
dofile("spec/helpers/load_addon.lua")

describe("Settings", function()

    before_each(function()
        WowStubs_Reset()
        C_Timer.Reset()
        LoadAddon()
        SelfCare.ApplyDefaults()
    end)

    describe("BuildSettingsPanel", function()
        it("creates SelfCare.Category on first call", function()
            SelfCare.Category = nil
            SelfCare.BuildSettingsPanel()
            assert.is_not_nil(SelfCare.Category)
        end)

        it("is idempotent — second call does not overwrite Category", function()
            SelfCare.Category = nil
            SelfCare.BuildSettingsPanel()
            local first = SelfCare.Category
            SelfCare.BuildSettingsPanel()
            assert.equal(first, SelfCare.Category)
        end)

        it("calls Settings.RegisterAddOnCategory", function()
            local called = false
            local orig = Settings.RegisterAddOnCategory
            Settings.RegisterAddOnCategory = function(cat)
                called = true
                return orig(cat)
            end
            SelfCare.Category = nil
            SelfCare.BuildSettingsPanel()
            assert.is_true(called)
        end)
    end)

    describe("Classic Era compatibility", function()
        before_each(function()
            WowStubs_Reset()
            C_Timer.Reset()
            -- Load addon first (needs retail globals), then simulate Classic
            LoadAddon()
            SelfCare.ApplyDefaults()
            WowStubs_SimulateClassic()
            SelfCare.Category = nil  -- force rebuild
        end)

        it("builds settings panel when MinimalSliderWithSteppersMixin is nil", function()
            assert.has_no.errors(function()
                SelfCare.BuildSettingsPanel()
            end)
            assert.is_not_nil(SelfCare.Category)
        end)

        it("builds settings panel when CreateSettingsButtonInitializer is nil", function()
            assert.has_no.errors(function()
                SelfCare.BuildSettingsPanel()
            end)
            assert.is_not_nil(SelfCare.Category)
        end)
    end)

    describe("TOC files", function()
        it("SelfCare_Vanilla.toc exists and declares Classic Era interface", function()
            local f = io.open("SelfCare_Vanilla.toc", "r")
            assert.is_not_nil(f, "SelfCare_Vanilla.toc must exist")
            local content = f:read("*a")
            f:close()
            assert.truthy(content:find("## Interface: 11508"),
                "Must declare Interface: 11508 for Classic Era 1.15.8")
        end)

        it("SelfCare_Vanilla.toc lists the same source files as SelfCare.toc", function()
            local function extractFiles(path)
                local files = {}
                for line in io.lines(path) do
                    if not line:match("^##") and not line:match("^%s*$") then
                        table.insert(files, line:match("^%s*(.-)%s*$"))
                    end
                end
                return files
            end
            local retail  = extractFiles("SelfCare.toc")
            local classic = extractFiles("SelfCare_Vanilla.toc")
            assert.same(retail, classic)
        end)
    end)
end)
