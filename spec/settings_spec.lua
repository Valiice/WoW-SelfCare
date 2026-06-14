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
        local function extractFiles(path)
            local files = {}
            for line in io.lines(path) do
                if not line:match("^##") and not line:match("^%s*$") then
                    table.insert(files, line:match("^%s*(.-)%s*$"))
                end
            end
            return files
        end

        it("SelfCare_Vanilla.toc exists and declares Classic Era interface", function()
            local f = io.open("SelfCare_Vanilla.toc", "r")
            assert.is_not_nil(f, "SelfCare_Vanilla.toc must exist")
            local content = f:read("*a")
            f:close()
            local iface = tonumber(content:match("## Interface: (%d+)"))
            assert.is_not_nil(iface, "SelfCare_Vanilla.toc must declare a ## Interface: line")
            assert.equal(1, math.floor(iface / 10000),
                "Classic Era interface must be major version 1 (got " .. tostring(iface) .. ")")
        end)

        it("SelfCare_Vanilla.toc lists the same source files as SelfCare.toc", function()
            local retail  = extractFiles("SelfCare.toc")
            assert.is_true(#retail > 0, "SelfCare.toc must have source files")
            local classic = extractFiles("SelfCare_Vanilla.toc")
            assert.same(retail, classic)
        end)

        it("SelfCare_TBC.toc exists and declares TBC Classic interface", function()
            local f = io.open("SelfCare_TBC.toc", "r")
            assert.is_not_nil(f, "SelfCare_TBC.toc must exist")
            local content = f:read("*a")
            f:close()
            local iface = tonumber(content:match("## Interface: (%d+)"))
            assert.is_not_nil(iface, "SelfCare_TBC.toc must declare a ## Interface: line")
            assert.equal(2, math.floor(iface / 10000),
                "TBC Classic interface must be major version 2 (got " .. tostring(iface) .. ")")
        end)

        it("SelfCare_TBC.toc lists the same source files as SelfCare.toc", function()
            local retail = extractFiles("SelfCare.toc")
            assert.is_true(#retail > 0, "SelfCare.toc must have source files")
            local tbc = extractFiles("SelfCare_TBC.toc")
            assert.same(retail, tbc)
        end)

        it("SelfCare_Wrath.toc exists and declares WotLK Classic interface", function()
            local f = io.open("SelfCare_Wrath.toc", "r")
            assert.is_not_nil(f, "SelfCare_Wrath.toc must exist")
            local content = f:read("*a")
            f:close()
            local iface = tonumber(content:match("## Interface: (%d+)"))
            assert.is_not_nil(iface, "SelfCare_Wrath.toc must declare a ## Interface: line")
            assert.equal(3, math.floor(iface / 10000),
                "WotLK Classic interface must be major version 3 (got " .. tostring(iface) .. ")")
        end)

        it("SelfCare_Wrath.toc lists the same source files as SelfCare.toc", function()
            local retail = extractFiles("SelfCare.toc")
            assert.is_true(#retail > 0, "SelfCare.toc must have source files")
            local wrath = extractFiles("SelfCare_Wrath.toc")
            assert.same(retail, wrath)
        end)

        it("SelfCare_Cata.toc exists and declares Cataclysm Classic interface", function()
            local f = io.open("SelfCare_Cata.toc", "r")
            assert.is_not_nil(f, "SelfCare_Cata.toc must exist")
            local content = f:read("*a")
            f:close()
            local iface = tonumber(content:match("## Interface: (%d+)"))
            assert.is_not_nil(iface, "SelfCare_Cata.toc must declare a ## Interface: line")
            assert.equal(4, math.floor(iface / 10000),
                "Cataclysm Classic interface must be major version 4 (got " .. tostring(iface) .. ")")
        end)

        it("SelfCare_Cata.toc lists the same source files as SelfCare.toc", function()
            local retail = extractFiles("SelfCare.toc")
            assert.is_true(#retail > 0, "SelfCare.toc must have source files")
            local cata = extractFiles("SelfCare_Cata.toc")
            assert.same(retail, cata)
        end)

        it("SelfCare_Mists.toc exists and declares MoP Classic interface", function()
            local f = io.open("SelfCare_Mists.toc", "r")
            assert.is_not_nil(f, "SelfCare_Mists.toc must exist")
            local content = f:read("*a")
            f:close()
            local iface = tonumber(content:match("## Interface: (%d+)"))
            assert.is_not_nil(iface, "SelfCare_Mists.toc must declare a ## Interface: line")
            assert.equal(5, math.floor(iface / 10000),
                "MoP Classic interface must be major version 5 (got " .. tostring(iface) .. ")")
        end)

        it("SelfCare_Mists.toc lists the same source files as SelfCare.toc", function()
            local retail = extractFiles("SelfCare.toc")
            assert.is_true(#retail > 0, "SelfCare.toc must have source files")
            local mists = extractFiles("SelfCare_Mists.toc")
            assert.same(retail, mists)
        end)
    end)
end)
