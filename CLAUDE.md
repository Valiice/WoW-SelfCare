# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SelfCare is a World of Warcraft retail addon (targeting WoW 11.x / The War Within) that reminds players to hydrate, check posture, and take breaks at configurable intervals. Inspired by the [FFXIV SelfCare plugin](https://github.com/chirpxiv/selfcare).

## Architecture

Multi-file Lua addon with a TOC file. No build step required.

**File structure:**
- `SelfCare.toc` — addon manifest
- `src/Core.lua` — namespace, DEFAULTS, ALERTS tables, ApplyDefaults
- `src/Notifications.lua` — notification frame, ShowNotif/HideNotif
- `src/Timers.lua` — timer engine, combat/cutscene deferral
- `src/Settings.lua` — Settings API panel
- `src/Init.lua` — event handler, slash command, public API

**Key sections (numbered in comments within each file):**
1. `DEFAULTS` table — all intervals stored in seconds, sliders show minutes
2. `ALERTS` table — drives timer setup, display, and settings panel generation
3. Runtime state — timer handles, pending alert queue, frame references
4. `ApplyDefaults()` — merges SavedVariables over defaults on load
5. Notification frame — single reused Button frame with fade in/out
6. Timer engine — `C_Timer.NewTicker` per alert, combat/cutscene deferral via `pendingAlerts` queue
7. Event handler — ADDON_LOADED, PLAYER_LOGIN, PLAYER_REGEN_ENABLED, CINEMATIC_STOP
8. Settings panel — post-11.0.2 Settings API (`RegisterAddOnSetting` with `variableKey + variableTbl` signature)
9. Slash command — `/selfcare` opens settings, `/selfcare test` fires all alerts, `/selfcare debug` prints timer snapshot to chat
10. Public API — `SelfCare_RestartTimers()`, `SelfCare_TestAlert(key)`

**SavedVariables:** `SelfCareDB` (registered in TOC)

## WoW API Notes

- Uses **post-11.0.2 Settings API** signature: `Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, type, name, default)` with `setting:SetValueChangedCallback(fn)`. The 10.x signature had a different argument order.
- Interval sliders use `Settings.RegisterProxySetting` for seconds-to-minutes conversion.
- Timers use `C_Timer.NewTicker` (repeating), not chained `NewTimer` calls.
- TOC `## Interface: 110100` targets 11.1.0. Update when Blizzard bumps the interface version.

## Testing

**Unit tests (primary):** BDD-style specs with busted, 112 tests across `spec/`:

```bash
bash scripts/run-tests.sh --tap
```

Run `scripts/install-test-deps.sh` once first to install busted into `lua_modules/` (Windows workaround for LuaRocks 2.x).

**Smoke test (no dependencies):**

```
"C:\Program Files (x86)\Lua\5.1\lua.exe" test_stub.lua
```

When adding new WoW API calls, add corresponding stubs in `spec/stubs/wow_api.lua`.

## Installation (in WoW)

Copy the entire repo folder (containing `SelfCare.toc` and `src/`) to `_retail_\Interface\AddOns\SelfCare\`.
