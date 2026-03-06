-- =============================================================================
-- spec/helpers/load_addon.lua
-- Loads src/*.lua in TOC order into the current Lua environment.
-- Call after WowStubs_Reset() to get a clean addon state.
--
-- Usage in specs:
--   require("spec.helpers.load_addon")
--   -- then LoadAddon() in before_each
-- =============================================================================

-- Resolve the repo root relative to this helper file.
-- busted is typically run from the repo root, so we just use relative paths.
local SRC_FILES = {
    "src/Core.lua",
    "src/Notifications.lua",
    "src/Timers.lua",
    "src/Settings.lua",
    "src/Init.lua",
}

--- Load all addon source files in TOC order.
--- Errors if any file fails to load.
--- Returns the SelfCare namespace table.
function LoadAddon()
    for _, path in ipairs(SRC_FILES) do
        local ok, err = pcall(dofile, path)
        if not ok then
            error("Failed to load " .. path .. ":\n" .. tostring(err), 2)
        end
    end
    return SelfCare
end
