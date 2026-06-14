-- =============================================================================
-- spec/interface_bump_spec.lua
-- Unit tests for scripts/interface_bump.lua (pure interface-version logic).
-- =============================================================================

local bump = dofile("scripts/interface_bump.lua")

describe("interface_bump", function()

    describe("compute_interface", function()
        it("converts a 4-segment version string to an interface number", function()
            assert.equal(120005, bump.compute_interface("12.0.5.67823"))
            assert.equal(50504, bump.compute_interface("5.5.4.68077"))
            assert.equal(20505, bump.compute_interface("2.5.5.68101"))
            assert.equal(11508, bump.compute_interface("1.15.8.67156"))
        end)

        it("returns nil for unparseable input", function()
            assert.is_nil(bump.compute_interface("not-a-version"))
            assert.is_nil(bump.compute_interface(""))
        end)
    end)

    describe("major_of", function()
        it("extracts the major version from an interface number", function()
            assert.equal(12, bump.major_of(120005))
            assert.equal(5, bump.major_of(50504))
            assert.equal(2, bump.major_of(20505))
            assert.equal(1, bump.major_of(11508))
        end)
    end)

    describe("bump_patch", function()
        it("increments the patch segment", function()
            assert.equal("1.0.1", bump.bump_patch("1.0.0"))
            assert.equal("1.0.10", bump.bump_patch("1.0.9"))
            assert.equal("2.3.5", bump.bump_patch("2.3.4"))
        end)
    end)

    local SAMPLE_TOC = table.concat({
        "## Interface: 120001",
        "## Title: SelfCare",
        "## Version: 1.0.0",
        "## SavedVariables: SelfCareDB",
        "",
        "src/Core.lua",
    }, "\n")

    describe("read_interface / read_version", function()
        it("reads the interface number", function()
            assert.equal(120001, bump.read_interface(SAMPLE_TOC))
        end)
        it("reads the version string", function()
            assert.equal("1.0.0", bump.read_version(SAMPLE_TOC))
        end)
    end)

    describe("set_interface_line / set_version_line", function()
        it("rewrites only the interface line", function()
            local out = bump.set_interface_line(SAMPLE_TOC, 120005)
            assert.equal(120005, bump.read_interface(out))
            assert.equal("1.0.0", bump.read_version(out))      -- untouched
            assert.is_truthy(out:find("## Title: SelfCare", 1, true))
        end)
        it("rewrites only the version line", function()
            local out = bump.set_version_line(SAMPLE_TOC, "1.0.1")
            assert.equal("1.0.1", bump.read_version(out))
            assert.equal(120001, bump.read_interface(out))     -- untouched
        end)
    end)

    describe("parse_live", function()
        local LIVE_TEXT = table.concat({
            "wow 12.0.5.67823",
            "wow_classic 5.5.4.68077",
            "wow_anniversary 2.5.5.68101",
            "wow_classic_era 1.15.8.67156",
            "wowxptr 12.0.7.67808",        -- PTR: must be ignored
            "wow_classic_beta 5.5.9.99999", -- beta: must be ignored
        }, "\n")

        it("keeps only whitelisted products as interface numbers", function()
            local live = bump.parse_live(LIVE_TEXT)
            table.sort(live)
            assert.same({ 11508, 20505, 50504, 120005 }, live)
        end)

        it("ignores blank lines and malformed entries", function()
            local live = bump.parse_live("\nwow 12.0.5.1\n\ngarbage\nwow bad-version\n")
            assert.same({ 120005 }, live)
        end)
    end)

end)
