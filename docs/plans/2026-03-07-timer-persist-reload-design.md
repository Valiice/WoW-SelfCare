# Timer Persistence Across /reload

**Date:** 2026-03-07
**Branch:** fix/timer-persist-reload

## Problem

On `/reload`, WoW tears down all in-memory state. `PLAYER_LOGIN` fires and `StartAllTimers()` creates brand-new tickers with the full interval, discarding any progress toward the next alert.

## Solution — Option C: next-due timestamp with sanity check

Store `SelfCareDB.nextDue[key]` (Unix timestamp of when the alert should next fire). On reload, compute remaining time and resume from there. Sanity-check the value before trusting it.

## Decision logic in StartTimer

```
remaining = SelfCareDB.nextDue[key] - time()

nil nextDue          → start full-interval ticker (never fired)
remaining <= 0       → fire immediately, then start full-interval ticker
remaining > interval → start full-interval ticker (stale/corrupt)
otherwise            → C_Timer.After(remaining, fire + start full-interval ticker)
```

## When nextDue is written

Written to `SelfCareDB.nextDue[key]` inside `FireAlert`, only when the alert is actually shown — not when queued. This means `nextDue` reflects when the player last *saw* the alert.

## Files changed

- `src/Core.lua` — add `nextDue = {}` to `DEFAULTS`
- `src/Timers.lua` — `StartTimer` resume logic; `FireAlert` writes `nextDue`

## New tests (6)

1. `nextDue` nil → full interval ticker
2. `nextDue` in future → `C_Timer.After` with correct remaining, then full ticker
3. `nextDue` overdue → fires immediately, full ticker started
4. `nextDue > interval` → full ticker (corrupt value ignored)
5. `nextDue` written to `SelfCareDB` when alert fires
6. `nextDue` not written when alert is queued
