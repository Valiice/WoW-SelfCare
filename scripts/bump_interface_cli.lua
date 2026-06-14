-- =============================================================================
-- scripts/bump_interface_cli.lua
-- Thin I/O wrapper around scripts/interface_bump.lua.
--
-- Usage:
--   lua scripts/bump_interface_cli.lua <live-versions-file> <base-version> <toc> [<toc> ...]
--
-- <live-versions-file> contains "<product> <version>" lines (jq output).
-- <base-version> is the current released version (X.Y.Z), supplied by the
-- caller from the latest git tag — NOT read from the TOC, which can drift from
-- the real release history.
-- On a change: rewrites the affected TOCs' interface lines, sets ## Version:
-- to bump_patch(<base-version>) across ALL given TOCs, and prints the new
-- version (e.g. "1.5.2"). On no change: prints "NO_CHANGE". Exits 0 in both.
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

local live_file = assert(arg[1], "usage: bump_interface_cli.lua <live-file> <base-version> <toc>...")
local base_version = arg[2]
if not M.is_valid_version(base_version) then
    io.stderr:write("ERROR: base version must be X.Y.Z (got: " .. tostring(base_version) .. ")\n")
    os.exit(1)
end
local toc_paths = {}
for i = 3, #arg do toc_paths[#toc_paths + 1] = arg[i] end
assert(#toc_paths > 0, "no TOC files given")

-- Parse live versions.
local live = M.parse_live(read_file(live_file))

-- Defensive: a healthy fetch always includes retail ("wow"). 120000+ guards
-- against a junk/empty source slipping through to a release.
local has_retail = false
for _, iface in ipairs(live) do
    if M.major_of(iface) >= 12 then has_retail = true end
end
if not has_retail then
    io.stderr:write("ERROR: no retail (major>=12) interface in live data; refusing to act\n")
    os.exit(1)
end

-- Read current TOC interface numbers.
local toc_text = {}     -- path -> content
local current = {}
for _, path in ipairs(toc_paths) do
    local content = read_file(path)
    toc_text[path] = content
    local iface = M.read_interface(content)
    if iface then
        current[#current + 1] = { file = path, interface = iface }
    end
end

local bumps = M.plan_bumps(current, live)
if #bumps == 0 then
    print("NO_CHANGE")
    os.exit(0)
end

-- Apply interface bumps.
for _, b in ipairs(bumps) do
    toc_text[b.file] = M.set_interface_line(toc_text[b.file], b.to)
    io.stderr:write(string.format("bump %s: %d -> %d\n", b.file, b.from, b.to))
end

-- Patch-bump version across ALL TOCs, based on the caller-supplied base
-- version (the latest git tag), so the result always advances past the real
-- latest release regardless of what the TOC ## Version: line currently says.
local new_version = assert(M.bump_patch(base_version), "unparseable base version: " .. base_version)
for _, path in ipairs(toc_paths) do
    toc_text[path] = M.set_version_line(toc_text[path], new_version)
end

-- Write everything back.
for path, content in pairs(toc_text) do
    write_file(path, content)
end

print(new_version)
