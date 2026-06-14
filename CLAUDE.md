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
9. Slash command — `/selfcare` opens settings, `/selfcare test` fires all alerts, `/selfcare reset` restarts all timers from now, `/selfcare debug` prints timer snapshot to chat
10. Public API — `SelfCare_RestartTimers()`, `SelfCare_TestAlert(key)`

**SavedVariables:** `SelfCareDB` (registered in TOC)

## WoW API Notes

- Uses **post-11.0.2 Settings API** signature: `Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, type, name, default)` with `setting:SetValueChangedCallback(fn)`. The 10.x signature had a different argument order.
- Interval sliders use `Settings.RegisterProxySetting` for seconds-to-minutes conversion.
- Timers use `C_Timer.NewTicker` (repeating), not chained `NewTimer` calls.
- TOC `## Interface: 110100` targets 11.1.0. Update when Blizzard bumps the interface version.

## Interface Version Maintenance

Interface versions are bumped automatically. `.github/workflows/bump-interface.yml`
runs daily (and on manual `workflow_dispatch` — dispatch it from `master`), reads
the latest live build per flavor from `https://wago.tools/api/builds`, and bumps any
TOC whose major version matches a live product and is behind (forward-only; PTR/beta
excluded via a product whitelist). On a change it patch-bumps `## Version:` across all
TOCs, commits to `master`, and pushes a `vX.Y.Z` tag that triggers `release.yml`.

The pushed tag uses the `RELEASE_PAT` secret because a tag pushed by the default
`GITHUB_TOKEN` would not trigger `release.yml`. `RELEASE_PAT` can be a fine-grained PAT
(Contents: write, this repo only) or a classic PAT (`repo`, or `public_repo` if the
repo is public). Logic lives in `scripts/interface_bump.lua` (pure, unit-tested in
`spec/interface_bump_spec.lua`); `scripts/bump_interface_cli.lua` is the I/O wrapper.

For a **manual** release at a chosen version (e.g. a feature bump `1.0.x` → `1.1.0`),
run `.github/workflows/set-version.yml` (Actions → "Set version and release" → Run
workflow, from `master`) and type the full `X.Y.Z`. It writes that version verbatim
into all TOCs (`scripts/set_version_cli.lua`), commits, tags, and triggers `release.yml`.
The daily auto-bump then continues patch-bumping from whatever you set.

Flavors with no currently-live game build (e.g. Wrath, Cata today) stay frozen at their
last interface number until a live progression (`wow_anniversary`) advances to match
their major version.

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

## CurseForge Packaging

The `.pkgmeta` file controls what gets included in the CurseForge release zip. Any file or folder that shouldn't be bundled (dev tooling, docs, CI config, etc.) must be listed under `ignore:` in `.pkgmeta`.
