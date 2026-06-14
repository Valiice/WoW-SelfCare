-- =============================================================================
-- scripts/interface_bump.lua
-- Pure logic for detecting and planning WoW TOC interface-version bumps.
-- No file or network I/O lives here so it can be unit-tested with busted.
-- =============================================================================

local M = {}

-- Live WoW products whose latest build feeds a TOC. PTR/beta/test products
-- (wowt, wowxptr, wowz, wow_beta, wow_classic_ptr, ...) are deliberately absent.
M.WHITELIST = {
    wow = true,             -- Retail (Mainline)
    wow_classic = true,     -- current Classic progression (MoP today)
    wow_anniversary = true, -- Anniversary progression (TBC today; advances over time)
    wow_classic_era = true, -- Classic Era
}

-- "12.0.5.67823" -> 120005  (major*10000 + minor*100 + patch)
function M.compute_interface(version)
    if type(version) ~= "string" then return nil end
    local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)")
    if not major then return nil end
    return tonumber(major) * 10000 + tonumber(minor) * 100 + tonumber(patch)
end

-- 120005 -> 12
function M.major_of(interface)
    return math.floor(interface / 10000)
end

-- "1.0.0" -> "1.0.1"
function M.bump_patch(version)
    local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)$")
    return string.format("%d.%d.%d", tonumber(major), tonumber(minor), tonumber(patch) + 1)
end

function M.read_interface(toc_text)
    local n = toc_text:match("##%s*Interface:%s*(%d+)")
    return n and tonumber(n) or nil
end

function M.read_version(toc_text)
    return toc_text:match("##%s*Version:%s*([^\r\n]+)")
end

function M.set_interface_line(toc_text, new_interface)
    return (toc_text:gsub("(##%s*Interface:%s*)%d+", "%1" .. new_interface, 1))
end

function M.set_version_line(toc_text, new_version)
    return (toc_text:gsub("(##%s*Version:%s*)[^\r\n]+", "%1" .. new_version, 1))
end

return M
