#!/usr/bin/env bash
# =============================================================================
# scripts/run-tests.sh
# Run the full test suite on Windows (Lua 5.1 via choco) using the local
# lua_modules/ dependency tree set up by install-test-deps.sh.
#
# Usage:
#   bash scripts/run-tests.sh           # all tests
#   bash scripts/run-tests.sh --tap     # TAP output for CI-style output
#   bash scripts/run-tests.sh spec/core_spec.lua   # single spec file
# =============================================================================

LUA="${LUA:-C:/Program Files (x86)/Lua/5.1/lua.exe}"
RUNNER="lua_modules/busted_runner"

if [ ! -f "$RUNNER" ]; then
    echo "ERROR: lua_modules/ not found. Run: bash scripts/install-test-deps.sh"
    exit 1
fi

DEFAULT_PATH=$("$LUA" -e "print(package.path)" 2>&1)
export LUA_PATH="./lua_modules/?.lua;./lua_modules/?/init.lua;./lua_modules/luassert/?.lua;$DEFAULT_PATH"

OUTPUT="utfTerminal"
ARGS=()
for arg in "$@"; do
    if [ "$arg" = "--tap" ]; then
        OUTPUT="TAP"
    else
        ARGS+=("$arg")
    fi
done

"$LUA" "$RUNNER" --output="$OUTPUT" "${ARGS[@]}"
