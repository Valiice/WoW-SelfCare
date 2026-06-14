-- =============================================================================
-- scripts/set_version_cli.lua
-- Sets an explicit ## Version: across the given TOC files (manual override).
--
-- Usage:
--   lua scripts/set_version_cli.lua <version> <toc> [<toc> ...]
--
-- Validates <version> is X.Y.Z, writes it verbatim into every TOC's
-- ## Version: line, and prints the version. Exits non-zero on bad input.
-- =============================================================================

local M = dofile("scripts/interface_bump.lua")

local function read_file(path)
    local f = assert(io.open(path, "rb"), "cannot read " .. path)
    local content = f:read("*a")
    f:close()
    return content
end

local function write_file(path, content)
    local f = assert(io.open(path, "wb"), "cannot write " .. path)
    f:write(content)
    f:close()
end

local version = arg[1]
if not M.is_valid_version(version) then
    io.stderr:write("ERROR: version must be X.Y.Z (got: " .. tostring(version) .. ")\n")
    os.exit(1)
end

local toc_paths = {}
for i = 2, #arg do toc_paths[#toc_paths + 1] = arg[i] end
assert(#toc_paths > 0, "no TOC files given")

for _, path in ipairs(toc_paths) do
    local content = read_file(path)
    write_file(path, M.set_version_line(content, version))
end

print(version)
