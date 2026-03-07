# AFK Awareness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Queue alerts that fire while the player is AFK and show them when they return, exactly like the existing combat deferral.

**Architecture:** AFK is a third "blocked" state in `IsBlocked()` alongside combat and cutscene. `PLAYER_FLAGS_CHANGED` fires when AFK status changes; we call `FlushPending()` there (it self-checks `IsBlocked()` so it's safe to call on any flag change). A new `disableWhenAFK` default and checkbox in settings control the behaviour.

**Tech Stack:** Lua 5.1, WoW 11.x API (`IsAFK`, `PLAYER_FLAGS_CHANGED`), busted for unit tests.

**Worktree:** `B:\Downloads\Coding\WoW-SelfCare\.worktrees\feature-afk-awareness`

---

### Task 1: Add `IsAFK` stub to test files

**Files:**
- Modify: `spec/stubs/wow_api.lua`
- Modify: `test_stub.lua`

**Step 1: Add `IsAFK` state + function to `spec/stubs/wow_api.lua`**

After the `_G._inCutscene = false` line (line 14), add:
```lua
_G._isAFK       = false
```

After `function InCombatLockdown()` block (around line 18), add:
```lua
function IsAFK()
    return _G._isAFK
end
```

In `WowStubs_Reset()`, after `rawset(_G, "_inCutscene", false)`, add:
```lua
rawset(_G, "_isAFK",        false)
```

**Step 2: Add `IsAFK` stub to `test_stub.lua`**

After `function InCombatLockdown() return false end` (line 77), add:
```lua
function IsAFK() return false end
```

**Step 3: Run smoke test to confirm it still passes**
```
"C:\Program Files (x86)\Lua\5.1\lua.exe" test_stub.lua
```
Expected: `=== RESULT: ALL TESTS PASSED ===`

**Step 4: Run unit tests to confirm baseline unchanged**
```
bash scripts/run-tests.sh --tap
```
Expected: `1..69` with no failures.

**Step 5: Commit**
```bash
git add spec/stubs/wow_api.lua test_stub.lua
git commit -m "Add IsAFK stub to test files"
```

---

### Task 2: Add `disableWhenAFK` default + failing unit tests

**Files:**
- Modify: `src/Core.lua`
- Modify: `spec/timers_spec.lua`

**Step 1: Add `disableWhenAFK` to DEFAULTS in `src/Core.lua`**

After `disableInCutscene = true,` (line 47), add:
```lua
    disableWhenAFK    = true,
```

**Step 2: Add failing AFK tests to `spec/timers_spec.lua`**

After the `"queues during cutscene..."` it block (around line 173), add a new describe block:

```lua
    -- -------------------------------------------------------------------------
    describe("AFK deferral", function()
        it("queues alert when AFK and disableWhenAFK is true", function()
            _G._isAFK = true
            SelfCareDB.disableWhenAFK = true

            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            C_Timer.GetTickers()[1]:Fire()

            assert.equal(0, #showNotifCalls)
        end)

        it("fires immediately when disableWhenAFK is false, even if AFK", function()
            _G._isAFK = true
            SelfCareDB.disableWhenAFK = false

            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            C_Timer.GetTickers()[1]:Fire()

            assert.equal(1, #showNotifCalls)
        end)

        it("flushes queued alerts when un-AFK", function()
            _G._isAFK = true
            SelfCareDB.disableWhenAFK = true

            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            C_Timer.GetTickers()[1]:Fire()
            assert.equal(0, #showNotifCalls)

            _G._isAFK = false
            SelfCare.FlushPending()
            assert.equal(1, #showNotifCalls)
        end)
    end)
```

**Step 3: Run tests — confirm the 3 new tests FAIL**
```
bash scripts/run-tests.sh --tap
```
Expected: 3 `not ok` lines for the AFK tests (IsBlocked doesn't check AFK yet).

**Step 4: Commit the failing tests + default**
```bash
git add src/Core.lua spec/timers_spec.lua
git commit -m "Add disableWhenAFK default and failing AFK deferral tests"
```

---

### Task 3: Implement AFK check in `IsBlocked()`

**Files:**
- Modify: `src/Timers.lua`

**Step 1: Add `IsAFK()` to `IsBlocked()` in `src/Timers.lua`**

After the `disableInCutscene` line (line 20), add:
```lua
    if SelfCareDB.disableWhenAFK    and IsAFK()                                then return true end
```

The full `IsBlocked` should now read:
```lua
local function IsBlocked()
    if SelfCareDB.disableInCombat   and InCombatLockdown()                      then return true end
    if SelfCareDB.disableInCutscene and (MovieFrame and MovieFrame:IsShown())    then return true end
    if SelfCareDB.disableWhenAFK    and IsAFK()                                  then return true end
    return false
end
```

**Step 2: Run unit tests — confirm the 3 AFK tests now PASS**
```
bash scripts/run-tests.sh --tap
```
Expected: `1..72` with no failures.

**Step 3: Run smoke test**
```
"C:\Program Files (x86)\Lua\5.1\lua.exe" test_stub.lua
```
Expected: `=== RESULT: ALL TESTS PASSED ===`

**Step 4: Commit**
```bash
git add src/Timers.lua
git commit -m "Add AFK check to IsBlocked() in timer engine"
```

---

### Task 4: Register `PLAYER_FLAGS_CHANGED` event in `Init.lua`

**Files:**
- Modify: `src/Init.lua`

**Step 1: Register the event**

After `addonFrame:RegisterEvent("CINEMATIC_STOP")` (line 15), add:
```lua
addonFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")  -- AFK state changes
```

**Step 2: Handle the event**

In the `OnEvent` handler, add a new branch after the `CINEMATIC_STOP` branch (around line 25):
```lua
    elseif event == "PLAYER_FLAGS_CHANGED" then
        SelfCare.FlushPending()
```

`FlushPending` already calls `IsBlocked()` internally — it only flushes if no blocked state is active, so calling it on every flag change is safe.

**Step 3: Add `PLAYER_FLAGS_CHANGED` to the event stub in `test_stub.lua`**

In `test_stub.lua`, `RegisterEvent` just logs — no stub needed. But add a test for Init that the event is registered. Actually, the existing Init tests cover event registration indirectly. Just run tests.

**Step 4: Run smoke test and unit tests**
```
"C:\Program Files (x86)\Lua\5.1\lua.exe" test_stub.lua
bash scripts/run-tests.sh --tap
```
Expected: smoke passes, `1..72` no failures.

**Step 5: Commit**
```bash
git add src/Init.lua
git commit -m "Register PLAYER_FLAGS_CHANGED to flush pending on un-AFK"
```

---

### Task 5: Add `disableWhenAFK` DB check + settings checkbox

**Files:**
- Modify: `test_stub.lua`
- Modify: `src/Settings.lua`

**Step 1: Add `disableWhenAFK` to DB checks in `test_stub.lua`**

In the `checks` table (around line 360), after `{"disableInCutscene", ...}` or near the other disable checks, add:
```lua
    {"disableWhenAFK",  true},
```

**Step 2: Run smoke test to confirm DB check passes**
```
"C:\Program Files (x86)\Lua\5.1\lua.exe" test_stub.lua
```
Expected: `=== RESULT: ALL TESTS PASSED ===`

**Step 3: Add "Pause during AFK" checkbox in `src/Settings.lua`**

After the `MakeCheckbox("disableInCutscene", ...)` block, add:
```lua
    MakeCheckbox("disableWhenAFK",    "Pause during AFK",
        "Alerts that fire while you are AFK are queued and shown when you return.")
```

**Step 4: Run all tests one final time**
```
"C:\Program Files (x86)\Lua\5.1\lua.exe" test_stub.lua
bash scripts/run-tests.sh --tap
```
Expected: smoke passes, `1..72` no failures.

**Step 5: Commit**
```bash
git add test_stub.lua src/Settings.lua
git commit -m "Add disableWhenAFK DB check and settings checkbox"
```

---

## Verification Checklist

After all tasks complete:
- [ ] Smoke test passes
- [ ] 72 unit tests pass (69 original + 3 new AFK tests)
- [ ] `src/Core.lua` has `disableWhenAFK = true` in DEFAULTS
- [ ] `src/Timers.lua` `IsBlocked()` checks `IsAFK()`
- [ ] `src/Init.lua` registers `PLAYER_FLAGS_CHANGED`
- [ ] `src/Settings.lua` has "Pause during AFK" checkbox
