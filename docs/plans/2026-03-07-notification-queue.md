# Notification Queue Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Queue overlapping alerts so each one is shown sequentially instead of the second overwriting the first.

**Architecture:** Add a file-local `notifQueue` table to `Notifications.lua`. `ShowNotif` pushes to the queue when the frame is already visible. The 0.31s hide-timer callback in `HideNotif` checks the queue after hiding and auto-shows the next entry.

**Tech Stack:** Lua 5.1, WoW API (`C_Timer`), busted test framework

**Working directory:** `B:\Downloads\Coding\WoW-SelfCare\.worktrees\feature\notification-queue`

**Run tests with:** `bash scripts/run-tests.sh --tap` (from that directory)

---

### Task 1: Update existing test + add new failing tests

One existing test asserts the old overwrite behavior and must be updated. Then add 4 new tests for queue behavior — all should fail before implementation.

**Files:**
- Modify: `spec/notifications_spec.lua`

**Step 1: Replace the overwrite test with the new queue behavior test**

Find and replace the test `"cancels any pending dismiss timer before showing a new notif"` (inside `describe("ShowNotif")`) with:

```lua
it("queues second alert instead of overwriting when frame is visible", function()
    SelfCare.ShowNotif(makeAlert("hydrate", "Drink water!"))
    local firstDismissTimer = C_Timer.GetTimers()[1]

    -- Show another while frame is visible — should queue, not overwrite
    SelfCare.ShowNotif(makeAlert("posture", "Check posture!"))

    -- Dismiss timer for first alert should NOT have been cancelled
    assert.is_false(firstDismissTimer.cancelled)
    -- Only one fade-in (second was queued, not shown)
    assert.equal(1, #fadeInCalls)
end)
```

**Step 2: Add 4 new tests**

Add a new `describe("notification queue")` block after the `describe("hint text")` block (before the final `end)` of the outer describe):

```lua
describe("notification queue", function()
    it("shows queued alert after manual HideNotif", function()
        SelfCare.ShowNotif(makeAlert("hydrate"))
        SelfCare.ShowNotif(makeAlert("posture"))  -- queued

        -- Only one shown so far
        assert.equal(1, #fadeInCalls)

        -- Hide the first
        SelfCare.HideNotif()
        -- Fire the 0.31s hide timer — should trigger next queued alert
        local timers = C_Timer.GetTimers()
        timers[#timers]:Fire()

        -- Second alert now shown
        assert.equal(2, #fadeInCalls)
    end)

    it("shows queued alert after auto-dismiss fires", function()
        SelfCare.ShowNotif(makeAlert("hydrate"))
        SelfCare.ShowNotif(makeAlert("posture"))  -- queued

        -- Fire auto-dismiss timer (first timer created = dismiss timer)
        local dismissTimer = C_Timer.GetTimers()[1]
        dismissTimer:Fire()  -- calls HideNotif internally

        -- Fire the 0.31s hide timer
        local timers = C_Timer.GetTimers()
        timers[#timers]:Fire()

        assert.equal(2, #fadeInCalls)
    end)

    it("shows alerts in FIFO order", function()
        SelfCare.ShowNotif(makeAlert("hydrate",  "First"))   -- shows now
        SelfCare.ShowNotif(makeAlert("posture",  "Second"))  -- queued
        SelfCare.ShowNotif(makeAlert("break",    "Third"))   -- queued

        assert.equal(1, #fadeInCalls)

        -- Dismiss first → Second shows
        SelfCare.HideNotif()
        C_Timer.GetTimers()[#C_Timer.GetTimers()]:Fire()
        assert.equal(2, #fadeInCalls)

        -- Dismiss second → Third shows
        SelfCare.HideNotif()
        C_Timer.GetTimers()[#C_Timer.GetTimers()]:Fire()
        assert.equal(3, #fadeInCalls)
    end)

    it("does not show queued alert if queue is empty after hide", function()
        SelfCare.ShowNotif(makeAlert("hydrate"))
        -- No second alert queued

        SelfCare.HideNotif()
        local countBefore = #fadeInCalls
        C_Timer.GetTimers()[#C_Timer.GetTimers()]:Fire()

        -- No additional fade-in
        assert.equal(countBefore, #fadeInCalls)
    end)
end)
```

**Step 3: Run tests — verify exactly 5 failures**

```
bash scripts/run-tests.sh --tap
```

Expected: 5 failures (1 updated test + 4 new tests). All other 85 tests pass.

**Step 4: Commit the failing tests**

```bash
git add spec/notifications_spec.lua
git commit -m "Add failing tests for notification queue behavior"
```

---

### Task 2: Implement the notification queue

**Files:**
- Modify: `src/Notifications.lua`

**Step 1: Add `notifQueue` file-local**

After the existing file-local declarations at the top of `src/Notifications.lua`:
```lua
local notifFrame           -- the shared Button frame
local notifDismissTimer    -- auto-dismiss timer handle
local notifHideTimer       -- the 0.31s fade-then-hide timer
local notifCountdownTicker -- 1s ticker for live countdown display
```

Add:
```lua
local notifQueue = {}      -- alerts waiting to display
```

**Step 2: Update `ShowNotif` to queue when frame is visible**

At the very start of `SelfCare.ShowNotif(alert)`, after `BuildNotifFrame()`, add:

```lua
if notifFrame:IsShown() then
    table.insert(notifQueue, alert)
    return
end
```

The full updated `ShowNotif` should look like:

```lua
function SelfCare.ShowNotif(alert)
    BuildNotifFrame()

    if notifFrame:IsShown() then
        table.insert(notifQueue, alert)
        return
    end

    if notifHideTimer       then notifHideTimer:Cancel();       notifHideTimer       = nil end
    if notifDismissTimer    then notifDismissTimer:Cancel();    notifDismissTimer    = nil end
    if notifCountdownTicker then notifCountdownTicker:Cancel(); notifCountdownTicker = nil end

    notifFrame.text:SetText(alert.message)

    notifFrame:Show()
    notifFrame:SetAlpha(0)
    UIFrameFadeIn(notifFrame, 0.4, 0, 1)

    if SelfCareDB.printToChat then
        SelfCare.Print(alert.message)
    end

    local soundID = SelfCareDB.alertSound or 808
    if soundID ~= 0 then
        PlaySound(soundID, "SFX")
    end

    if SelfCareDB.autoDismiss then
        local remaining = SelfCareDB.dismissDelay
        notifFrame.hint:SetText(string.format("Dismisses in %ds", remaining))
        notifCountdownTicker = C_Timer.NewTicker(1, function()
            remaining = remaining - 1
            if remaining > 0 then
                notifFrame.hint:SetText(string.format("Dismisses in %ds", remaining))
            end
        end)
        notifDismissTimer = C_Timer.NewTimer(SelfCareDB.dismissDelay, function()
            SelfCare.HideNotif()
        end)
    else
        notifFrame.hint:SetText("Click to dismiss")
    end
end
```

**Step 3: Update the hide-timer callback in `HideNotif` to dequeue**

In `SelfCare.HideNotif()`, find the `notifHideTimer = C_Timer.NewTimer(0.31, function()` callback and update it to show the next queued alert:

```lua
notifHideTimer = C_Timer.NewTimer(0.31, function()
    notifFrame:Hide()
    notifHideTimer = nil
    if #notifQueue > 0 then
        SelfCare.ShowNotif(table.remove(notifQueue, 1))
    end
end)
```

**Step 4: Run all tests — verify all 91 pass**

```
bash scripts/run-tests.sh --tap
```

Expected: all 91 tests pass (86 existing + 5 new/updated)

**Step 5: Commit**

```bash
git add src/Notifications.lua
git commit -m "Queue overlapping alerts and show them sequentially"
```

---

### Task 3: Sync to WoW AddOns and verify

**Step 1: Copy updated file**

```bash
cp src/Notifications.lua \
  "D:/Games/World of Warcraft/_retail_/Interface/AddOns/SelfCare/src/"
```

**Step 2: Final test run**

```
bash scripts/run-tests.sh --tap
```

Expected: all 91 tests pass

**Step 3: In-game verify**

- Use `/selfcare test` — all 3 alerts should appear one after another, not overlap
- Click to dismiss each one, verify next appears

**Step 4: Commit**

```bash
git add src/Notifications.lua
git commit -m "Sync Notifications.lua to WoW AddOns"
```
