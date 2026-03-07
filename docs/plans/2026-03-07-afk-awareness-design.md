# AFK Awareness Design

**Date:** 2026-03-07

## Problem

Timers keep ticking while the player is AFK. Alerts that fire during AFK pop up either unnoticed or all at once on return, which is disruptive and unhelpful.

## Solution

Treat AFK as a third "blocked" state alongside combat and cutscene. Alerts that fire while AFK are queued and shown when the player returns — exactly how combat deferral already works.

## Changes

### `src/Core.lua`
Add `disableWhenAFK = true` to `DEFAULTS`.

### `src/Timers.lua`
Add `IsAFK()` check to `IsBlocked()`:
```lua
if SelfCareDB.disableWhenAFK and IsAFK() then return true end
```

### `src/Init.lua`
Register `PLAYER_FLAGS_CHANGED` event. In the handler, call `FlushPending()` when the player is no longer AFK (i.e. `not IsAFK()`). Mirrors the existing `PLAYER_REGEN_ENABLED` pattern.

### `src/Settings.lua`
Add a "Pause during AFK" checkbox using the existing `MakeCheckbox` helper, grouped with the combat/cutscene checkboxes.

## Testing
- Add `IsAFK` stub to `spec/stubs/wow_api.lua` and `test_stub.lua`
- Add `PLAYER_FLAGS_CHANGED` to event stubs
- Add `disableWhenAFK` DB check in `test_stub.lua`
- Add unit tests in `spec/timers_spec.lua`: queues during AFK, flushes on un-AFK
- Smoke test passes
