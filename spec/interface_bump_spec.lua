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

end)
