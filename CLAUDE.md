# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SelfCare is a World of Warcraft retail addon (targeting WoW 11.x / The War Within) that reminds players to hydrate, check posture, and take breaks at configurable intervals. Inspired by the [FFXIV SelfCare plugin](https://github.com/chirpxiv/selfcare).

## Architecture

Single-file Lua addon (`SelfCare.lua`) with a TOC file. No build step required.

**Key sections in SelfCare.lua (numbered in comments):**
1. `DEFAULTS` table — all intervals stored in seconds, sliders show minutes
2. `ALERTS` table — drives timer setup, display, and settings panel generation
3. Runtime state — timer handles, pending alert queue, frame references
4. `ApplyDefaults()` — merges SavedVariables over defaults on load
5. Notification frame — single reused Button frame with fade in/out
6. Timer engine — `C_Timer.NewTicker` per alert, combat/cutscene deferral via `pendingAlerts` queue
7. Event handler — ADDON_LOADED, PLAYER_LOGIN, PLAYER_REGEN_ENABLED, CINEMATIC_STOP
8. Settings panel — post-11.0.2 Settings API (`RegisterAddOnSetting` with `variableKey + variableTbl` signature)
9. Slash command — `/selfcare` opens settings, `/selfcare test` fires all alerts
10. Public API — `SelfCare_RestartTimers()`, `SelfCare_TestAlert(key)`

**SavedVariables:** `SelfCareDB` (registered in TOC)

## WoW API Notes

- Uses **post-11.0.2 Settings API** signature: `Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, type, name, default)` with `setting:SetValueChangedCallback(fn)`. The 10.x signature had a different argument order.
- Interval sliders use `Settings.RegisterProxySetting` for seconds-to-minutes conversion.
- Timers use `C_Timer.NewTicker` (repeating), not chained `NewTimer` calls.
- TOC `## Interface: 110100` targets 11.1.0. Update when Blizzard bumps the interface version.

## Testing

Run offline tests with Lua 5.1 (installed via `choco install lua`):

```
cd C:\Coding\WoW-SelfCare
"C:\Program Files (x86)\Lua\5.1\lua.exe" test_stub.lua
```

`test_stub.lua` stubs the WoW API (CreateFrame, C_Timer, Settings, etc.) and:
- Loads `SelfCare.lua` and checks for syntax/runtime errors
- Simulates ADDON_LOADED and PLAYER_LOGIN events
- Fires `/selfcare test` and individual `SelfCare_TestAlert()` calls
- Verifies all `SelfCareDB` defaults are applied correctly

When adding new WoW API calls to `SelfCare.lua`, add corresponding stubs in `test_stub.lua`.

## Installation (in WoW)

Copy `SelfCare.toc` and `SelfCare.lua` to `_retail_\Interface\AddOns\SelfCare\`.
