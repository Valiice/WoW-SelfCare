# Timer Persistence Across /reload Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Persist timer progress across `/reload` by saving a next-due timestamp to `SelfCareDB` and resuming from it on startup.

**Architecture:** Store `SelfCareDB.nextDue[alertKey]` (Unix timestamp) when an alert fires. On `StartTimer`, compute `remaining = nextDue - time()` and apply sanity checks before deciding whether to resume or start fresh.

**Tech Stack:** Lua 5.1, WoW API (`time()`, `C_Timer`), busted test framework

**Working directory:** `B:\Downloads\Coding\WoW-SelfCare\.worktrees\fix\timer-persist-reload`

**Run tests with:** `bash scripts/run-tests.sh --tap`

---

### Task 1: Stub `time()` in test infrastructure

The addon calls WoW's global `time()`. Tests need to control it for deterministic results.

**Files:**
- Modify: `spec/stubs/wow_api.lua`

**Step 1: Add controllable `time()` stub and reset helper**

In `spec/stubs/wow_api.lua`, add after the `_inCombat`/`_inCutscene`/`_isAFK` state vars:

```lua
_G._now = 1000  -- controllable fake timestamp

function time()
    return _G._now
end
```

In `WowStubs_Reset()`, add:
```lua
rawset(_G, "_now", 1000)
```

**Step 2: Run existing tests to verify nothing broke**

```
bash scripts/run-tests.sh --tap
```
Expected: all 79 tests pass

**Step 3: Commit**

```bash
git add spec/stubs/wow_api.lua
git commit -m "Add controllable time() stub to test infrastructure"
```

---

### Task 2: Add `nextDue` to DEFAULTS

`SelfCareDB.nextDue` must always exist as an empty table so `StartTimer` can safely read from it on first load.

**Files:**
- Modify: `src/Core.lua`
- Modify: `spec/core_spec.lua` (add test)

**Step 1: Write the failing test**

In `spec/core_spec.lua`, inside the `ApplyDefaults` describe block, add:

```lua
it("initialises nextDue as an empty table", function()
    SelfCare.ApplyDefaults()
    assert.is_table(SelfCareDB.nextDue)
end)
```

**Step 2: Run to verify it fails**

```
bash scripts/run-tests.sh --tap
```
Expected: 1 failure — `SelfCareDB.nextDue` is nil

**Step 3: Add `nextDue` to DEFAULTS in `src/Core.lua`**

In the `DEFAULTS` table, after `alertSound`:
```lua
nextDue           = {},              -- next-due Unix timestamps keyed by alert key
```

**Step 4: Run tests — verify pass**

```
bash scripts/run-tests.sh --tap
```
Expected: all 80 tests pass

**Step 5: Commit**

```bash
git add src/Core.lua spec/core_spec.lua
git commit -m "Add nextDue table to SelfCareDB defaults"
```

---

### Task 3: Write `nextDue` when an alert fires

When `FireAlert` actually shows an alert (not when it queues it), save the next-due timestamp.

**Files:**
- Modify: `src/Timers.lua`
- Modify: `spec/timers_spec.lua`

**Step 1: Write the two failing tests**

In `spec/timers_spec.lua`, add a new `describe("nextDue persistence")` block inside the top-level `describe("Timers")`:

```lua
describe("nextDue persistence", function()
    it("writes nextDue to SelfCareDB when alert fires", function()
        _G._now = 5000
        local alert = SelfCare.FindAlertByKey("hydrate")
        SelfCare.StartTimer(alert)
        C_Timer.GetTickers()[1]:Fire()

        local expected = 5000 + SelfCareDB.hydrateInterval
        assert.equal(expected, SelfCareDB.nextDue["hydrate"])
    end)

    it("does not write nextDue when alert is queued (combat)", function()
        _G._inCombat = true
        SelfCareDB.disableInCombat = true
        local alert = SelfCare.FindAlertByKey("hydrate")
        SelfCare.StartTimer(alert)
        C_Timer.GetTickers()[1]:Fire()

        assert.is_nil(SelfCareDB.nextDue["hydrate"])
    end)
end)
```

**Step 2: Run to verify they fail**

```
bash scripts/run-tests.sh --tap
```
Expected: 2 failures

**Step 3: Update `FireAlert` in `src/Timers.lua`**

`FireAlert` currently ends with `SelfCare.ShowNotif(alert)`. Change it to:

```lua
local function FireAlert(alert)
    if IsBlocked() then
        for _, v in ipairs(pendingAlerts) do
            if v.key == alert.key then return end
        end
        table.insert(pendingAlerts, alert)
        return
    end
    local intervalKey = SelfCare.IntervalKey(alert)
    SelfCareDB.nextDue[alert.key] = time() + SelfCareDB[intervalKey]
    SelfCare.ShowNotif(alert)
end
```

**Step 4: Run tests — verify pass**

```
bash scripts/run-tests.sh --tap
```
Expected: all 82 tests pass

**Step 5: Commit**

```bash
git add src/Timers.lua spec/timers_spec.lua
git commit -m "Write nextDue timestamp to SelfCareDB when alert fires"
```

---

### Task 4: Resume from `nextDue` in `StartTimer`

On reload, instead of always starting a full-interval ticker, check `nextDue` and resume.

**Files:**
- Modify: `src/Timers.lua`
- Modify: `spec/timers_spec.lua`

**Step 1: Write the four failing tests**

Add these inside the existing `describe("nextDue persistence")` block:

```lua
it("starts full-interval ticker when nextDue is nil (never fired)", function()
    SelfCareDB.nextDue["hydrate"] = nil
    SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))

    -- No After timer, one full-interval ticker
    assert.equal(0, #C_Timer.GetAfterTimers())
    assert.equal(1, #C_Timer.GetTickers())
    assert.equal(SelfCareDB.hydrateInterval, C_Timer.GetTickers()[1].interval)
end)

it("uses C_Timer.After with remaining time when nextDue is in the future", function()
    _G._now = 1000
    SelfCareDB.nextDue["hydrate"] = 1000 + 300  -- 300 seconds remaining
    SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))

    -- Should use After(300, ...), no full ticker yet
    assert.equal(1, #C_Timer.GetAfterTimers())
    assert.equal(300, C_Timer.GetAfterTimers()[1].delay)
    assert.equal(0, #C_Timer.GetTickers())
end)

it("fires immediately and starts full ticker when nextDue is overdue", function()
    _G._now = 2000
    SelfCareDB.nextDue["hydrate"] = 1000  -- 1000 seconds in the past
    SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))

    -- Should fire immediately (After with delay <= 0 handled as instant)
    -- and queue a full-interval ticker
    assert.equal(1, #showNotifCalls)
    assert.equal(1, #C_Timer.GetTickers())
    assert.equal(SelfCareDB.hydrateInterval, C_Timer.GetTickers()[1].interval)
end)

it("starts fresh full ticker when nextDue is corrupt (> interval)", function()
    _G._now = 1000
    -- nextDue impossibly far in the future
    SelfCareDB.nextDue["hydrate"] = 1000 + SelfCareDB.hydrateInterval + 999
    SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))

    assert.equal(0, #C_Timer.GetAfterTimers())
    assert.equal(1, #C_Timer.GetTickers())
    assert.equal(SelfCareDB.hydrateInterval, C_Timer.GetTickers()[1].interval)
end)
```

**Step 2: Run to verify they fail**

```
bash scripts/run-tests.sh --tap
```
Expected: 4 failures

**Step 3: Rewrite `StartTimer` in `src/Timers.lua`**

Replace the current `SelfCare.StartTimer` with:

```lua
function SelfCare.StartTimer(alert)
    CancelTimer(alert.key)

    local enabledKey  = SelfCare.EnabledKey(alert)
    local intervalKey = SelfCare.IntervalKey(alert)

    if not SelfCareDB[enabledKey] then return end

    local interval = SelfCareDB[intervalKey]
    if not interval or interval <= 0 then return end

    local nextDue   = SelfCareDB.nextDue[alert.key]
    local remaining = nextDue and (nextDue - time())

    -- Corrupt / missing timestamp → start fresh
    if not remaining or remaining > interval then
        timers[alert.key] = C_Timer.NewTicker(interval, function()
            FireAlert(alert)
        end)
        return
    end

    -- Overdue → fire immediately, then resume normal cadence
    if remaining <= 0 then
        FireAlert(alert)
        timers[alert.key] = C_Timer.NewTicker(interval, function()
            FireAlert(alert)
        end)
        return
    end

    -- Partial interval remaining → one-shot delay, then normal ticker
    C_Timer.After(remaining, function()
        FireAlert(alert)
        timers[alert.key] = C_Timer.NewTicker(interval, function()
            FireAlert(alert)
        end)
    end)
end
```

**Step 4: Run tests — verify all pass**

```
bash scripts/run-tests.sh --tap
```
Expected: all 86 tests pass

**Step 5: Commit**

```bash
git add src/Timers.lua spec/timers_spec.lua
git commit -m "Resume timers from nextDue timestamp after /reload"
```

---

### Task 5: Sync to WoW AddOns and verify

**Step 1: Copy updated files to WoW**

```bash
cp src/Core.lua src/Timers.lua \
  "D:/Games/World of Warcraft/_retail_/Interface/AddOns/SelfCare/src/"
```

**Step 2: In-game verify**
- `/reload` a few times — timers should not reset
- `/selfcare test` — all three alerts should still appear

**Step 3: Final test run**

```
bash scripts/run-tests.sh --tap
```
Expected: all 86 tests pass

**Step 4: Final commit**

```bash
git add src/Core.lua src/Timers.lua spec/timers_spec.lua spec/core_spec.lua spec/stubs/wow_api.lua
git commit -m "Persist timer progress across /reload via nextDue timestamps"
```
