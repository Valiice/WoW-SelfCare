#!/usr/bin/env bash
# =============================================================================
# scripts/install-test-deps.sh
# Manually installs busted and its pure-Lua dependencies into lua_modules/
# for Windows environments where LuaRocks 2.0.x (bundled with choco lua) is
# too old to install busted automatically.
#
# Run once from the repo root:
#   bash scripts/install-test-deps.sh
#
# Then run tests with:
#   bash scripts/run-tests.sh
# =============================================================================

set -e

DEST="lua_modules"
mkdir -p "$DEST"

echo "==> Downloading busted 2.3.0..."
curl -sL "https://github.com/lunarmodules/busted/archive/refs/tags/v2.3.0.tar.gz" | tar -xz -C /tmp
cp -r /tmp/busted-2.3.0/busted "$DEST/"
cp /tmp/busted-2.3.0/busted.lua "$DEST/"
cp /tmp/busted-2.3.0/bin/busted "$DEST/busted_runner"

echo "==> Downloading luassert 1.9.0..."
curl -sL "https://github.com/lunarmodules/luassert/archive/refs/tags/v1.9.0.tar.gz" | tar -xz -C /tmp
mkdir -p "$DEST/luassert/formatters" "$DEST/luassert/languages" "$DEST/luassert/matchers"
cp /tmp/luassert-1.9.0/src/*.lua "$DEST/luassert/"
cp /tmp/luassert-1.9.0/src/formatters/*.lua "$DEST/luassert/formatters/" 2>/dev/null || true
cp /tmp/luassert-1.9.0/src/languages/*.lua  "$DEST/luassert/languages/"  2>/dev/null || true
cp /tmp/luassert-1.9.0/src/matchers/*.lua   "$DEST/luassert/matchers/"   2>/dev/null || true

echo "==> Downloading say 1.4.1..."
curl -sL "https://github.com/lunarmodules/say/archive/refs/tags/v1.4.1.tar.gz" | tar -xz -C /tmp
cp -r /tmp/say-1.4.1/src/say "$DEST/"

echo "==> Downloading penlight 1.15.0..."
curl -sL "https://github.com/lunarmodules/Penlight/archive/refs/tags/1.15.0.tar.gz" | tar -xz -C /tmp
cp -r /tmp/Penlight-1.15.0/lua/pl "$DEST/"

echo "==> Downloading mediator_lua..."
curl -sL "https://github.com/Olivine-Labs/mediator_lua/archive/refs/heads/master.tar.gz" | tar -xz -C /tmp
cp /tmp/mediator_lua-master/src/mediator.lua "$DEST/"

echo "==> Downloading dkjson 2.8..."
curl -sL "https://github.com/LuaDist/dkjson/archive/refs/heads/master.tar.gz" | tar -xz -C /tmp
cp /tmp/dkjson-master/dkjson.lua "$DEST/"

echo "==> Creating stubs for C-extension deps (lua-term, luasystem)..."

cat > "$DEST/system.lua" << 'EOF'
-- Minimal stub for luasystem (gettime/monotime/sleep used by busted)
local M = {}
function M.gettime()  return os.time() end
function M.monotime() return os.time() end
function M.sleep(s)   end
return M
EOF

mkdir -p "$DEST/term"
cat > "$DEST/term.lua" << 'EOF'
-- Minimal stub for lua-term (isatty used by busted runner)
local M = {}
function M.isatty(f) return false end
M.colors = setmetatable({}, { __index = function() return function(s) return s end end })
return M
EOF
cat > "$DEST/term/colors.lua" << 'EOF'
return setmetatable({}, { __index = function() return function(s) return s end end })
EOF

echo ""
echo "Done! lua_modules/ is ready."
echo "Run tests with:  bash scripts/run-tests.sh"
