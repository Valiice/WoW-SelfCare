# Notification Queue Design

**Date:** 2026-03-07

## Problem

When two alerts fire simultaneously (e.g. posture at 30 min and hydrate at 60 min both due at the 60-minute mark), the second `ShowNotif` call immediately overwrites the first. The player only sees one alert.

## Solution — Sequential queue in Notifications.lua

A file-local `notifQueue` table holds alerts waiting to be displayed. `ShowNotif` checks whether the frame is currently visible — if yes, it pushes to the queue instead of overwriting. `HideNotif` already has a single exit point (the 0.31s `notifHideTimer` callback that calls `notifFrame:Hide()`). After hiding, it checks `notifQueue` and calls `ShowNotif` on the next entry if one exists.

## Data flow

```
ShowNotif(alert)
  └─ frame visible? → table.insert(notifQueue, alert)   [queue, return]
  └─ frame hidden?  → show immediately (existing logic)

HideNotif() → fade out → 0.31s timer → notifFrame:Hide()
  └─ notifQueue non-empty? → ShowNotif(table.remove(notifQueue, 1))
```

## Files changed

- `src/Notifications.lua` only — add `notifQueue`, update `ShowNotif` and the hide-timer callback in `HideNotif`

## Existing test that changes behavior

`"cancels any pending dismiss timer before showing a new notif"` tested the old overwrite behavior. With the queue, a second `ShowNotif` while the frame is showing does NOT cancel the current dismiss timer — it queues. This test must be updated to assert the new behavior.

## New tests (4)

1. Second `ShowNotif` while frame is visible queues the alert (frame text unchanged, dismiss timer not cancelled)
2. Queued alert shows automatically after `HideNotif` completes (hide timer fires)
3. Queued alert shows automatically after auto-dismiss fires
4. Multiple queued alerts show in FIFO order
