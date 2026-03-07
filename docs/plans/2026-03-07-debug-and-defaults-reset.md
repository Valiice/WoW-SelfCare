# Debug Command and Defaults Reset Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `/selfcare debug` snapshot command and make the Defaults button fully wipe SelfCareDB back to factory state.

**Architecture:** Two independent changes — a new slash subcommand in Init.lua that prints per-alert due times, and a revert callback hooked into the Settings category that wipes SelfCareDB in-place and restarts all timers. A shared `SelfCare.ResetToDefaults()` function is exposed so it can be both tested directly and called from the Settings hook.

**Tech Stack:** Lua 5.1, WoW 11.x Settings API, busted test framework.

---

### Task 1: Add `date` stub and `SetRevertCallback` support to wow_api.lua

These are prerequisite stub additions needed before writing tests for the new features.

**Files:**
- Modify: `spec/stubs/wow_api.lua`

**Step 1: Write the failing test**

In `spec/init_spec.lua`, add inside the `describe("slash command")` block (needs ADDON_LOADED in before_each which is already there):

```lua
it("/selfcare debug does not error when nextDue is nil", function()
    SelfCareDB.nextDue = {}
    assert.has_no.errors(function()
        SlashCmdList["SELFCARE"]("debug")
    end)
end)
```

**Step 2: Run test to verify it fails**

```
bash scripts/run-tests.sh --tap
```

Expected: FAIL — `attempt to call global 'date' (a nil value)`

**Step 3: Add `date` stub to wow_api.lua**

At the top of `spec/stubs/wow_api.lua`, after the `_G._now` line, add:

```lua
-- WoW exposes date() as a global (same signature as os.date)
date = os.date
```

Also update `Settings.RegisterVerticalLayoutCategory` to support `SetRevertCallback` (needed for Task 4 tests). Replace the existing function:

```lua
RegisterVerticalLayoutCategory = function(name)
    local layout = {
        AddInitializer = function(self, initializer) return initializer end,
    }
    local category = {
        name = name,
        SetRevertCallback = function(self, fn)
            self._revertCallback = fn
        end,
        -- Test helper: trigger the revert as if user clicked Defaults
        _TriggerRevert = function(self)
            if self._revertCallback then self._revertCallback() end
        end,
    }
    return category, layout
end,
```

**Step 4: Run tests to verify they pass**

```
bash scripts/run-tests.sh --tap
```

Expected: PASS — all existing tests still green.

**Step 5: Commit**

```bash
git add spec/stubs/wow_api.lua
git commit -m "Add date stub and SetRevertCallback support to wow_api stub"
```

---

### Task 2: `/selfcare debug` command

**Files:**
- Modify: `src/Init.lua:38-52` (slash command handler)
- Test: `spec/init_spec.lua` (add inside `describe("slash command")`)

**Step 1: Write the failing tests**

Add a new `describe("debug command")` block inside `describe("slash command")` in `spec/init_spec.lua`:

```lua
describe("debug command", function()
    before_each(function()
        SelfCareAddonFrame:_FireEvent("ADDON_LOADED", "SelfCare")
        SelfCare.ApplyDefaults()
    end)

    it("prints a header line", function()
        local lines = {}
        SelfCare.Print = function(msg) table.insert(lines, msg) end
        SlashCmdList["SELFCARE"]("debug")
        assert.truthy(lines[1]:find("Debug"))
    end)

    it("prints one line per alert", function()
        local lines = {}
        SelfCare.Print = function(msg) table.insert(lines, msg) end
        SelfCareDB.nextDue = { hydrate = 2000, posture = 2000, ["break"] = 2000 }
        SlashCmdList["SELFCARE"]("debug")
        -- 1 header + 3 alert lines = 4
        assert.equal(4, #lines)
    end)

    it("shows [disabled] for a disabled alert", function()
        local lines = {}
        SelfCare.Print = function(msg) table.insert(lines, msg) end
        SelfCareDB.hydrateEnabled = false
        SelfCareDB.nextDue = {}
        SlashCmdList["SELFCARE"]("debug")
        local found = false
        for _, l in ipairs(lines) do
            if l:find("hydrate") and l:find("disabled") then found = true end
        end
        assert.is_true(found)
    end)

    it("shows [pending first fire] when nextDue is nil for that alert", function()
        local lines = {}
        SelfCare.Print = function(msg) table.insert(lines, msg) end
        SelfCareDB.nextDue = {}
        SlashCmdList["SELFCARE"]("debug")
        local found = false
        for _, l in ipairs(lines) do
            if l:find("hydrate") and l:find("pending") then found = true end
        end
        assert.is_true(found)
    end)

    it("shows due time and interval when nextDue is set", function()
        local lines = {}
        SelfCare.Print = function(msg) table.insert(lines, msg) end
        _G._now = 1000
        SelfCareDB.nextDue = { hydrate = 1300 }  -- 300s in the future
        SlashCmdList["SELFCARE"]("debug")
        local found = false
        for _, l in ipairs(lines) do
            if l:find("hydrate") and l:find("due") then found = true end
        end
        assert.is_true(found)
    end)
end)
```

**Step 2: Run tests to verify they fail**

```
bash scripts/run-tests.sh --tap
```

Expected: FAIL — `debug` command not yet implemented, falls through to settings open.

**Step 3: Implement the debug command in Init.lua**

Add two local helper functions at the top of `src/Init.lua`, before the addonFrame line:

```lua
local function FormatInterval(s)
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    if h > 0 then
        return string.format("%dh %dm", h, m)
    else
        return m .. " min"
    end
end

local function FormatRemaining(s)
    if s <= 0 then return "overdue" end
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sec = s % 60
    if h > 0 then
        return string.format("%dh %dm", h, m)
    elseif m > 0 then
        return string.format("%dm %ds", m, sec)
    else
        return string.format("%ds", sec)
    end
end
```

Then add the `debug` branch in `SlashCmdList["SELFCARE"]`, after the `test` branch and before the settings open:

```lua
if cmd == "debug" then
    SelfCare.Print("SelfCare Debug:")
    for _, alert in ipairs(SelfCare.ALERTS) do
        local enabledKey  = SelfCare.EnabledKey(alert)
        local intervalKey = SelfCare.IntervalKey(alert)
        if not SelfCareDB[enabledKey] then
            SelfCare.Print(string.format("  %s — [disabled]", alert.key))
        else
            local interval = SelfCareDB[intervalKey]
            local nextDue  = SelfCareDB.nextDue and SelfCareDB.nextDue[alert.key]
            if not nextDue then
                SelfCare.Print(string.format("  %s — [pending first fire]  [%s interval]",
                    alert.key, FormatInterval(interval)))
            else
                local remaining = nextDue - time()
                SelfCare.Print(string.format("  %s — due %s (in %s)  [%s interval]",
                    alert.key, date("%H:%M:%S", nextDue),
                    FormatRemaining(remaining), FormatInterval(interval)))
            end
        end
    end
    return
end
```

**Step 4: Run tests to verify they pass**

```
bash scripts/run-tests.sh --tap
```

Expected: PASS — all new debug tests green, no regressions.

**Step 5: Commit**

```bash
git add src/Init.lua spec/init_spec.lua
git commit -m "Add /selfcare debug snapshot command"
```

---

### Task 3: `SelfCare.ResetToDefaults()` + Defaults button hook

**Files:**
- Modify: `src/Init.lua` (add `SelfCare.ResetToDefaults`)
- Modify: `src/Settings.lua:196-198` (hook `SetRevertCallback`)
- Test: `spec/init_spec.lua` (add `describe("ResetToDefaults")`)

**Step 1: Write the failing tests**

Add a new `describe("ResetToDefaults")` block at the bottom of `spec/init_spec.lua`, before the closing `end`:

```lua
describe("ResetToDefaults", function()
    before_each(function()
        SelfCareAddonFrame:_FireEvent("ADDON_LOADED", "SelfCare")
        SelfCare.ApplyDefaults()
    end)

    it("wipes nextDue", function()
        SelfCareDB.nextDue = { hydrate = 9999, posture = 9999 }
        SelfCare.ResetToDefaults()
        assert.same({}, SelfCareDB.nextDue)
    end)

    it("wipes notifPos", function()
        SelfCareDB.notifPos = { "CENTER", "CENTER", 0, 100 }
        SelfCare.ResetToDefaults()
        assert.is_nil(SelfCareDB.notifPos)
    end)

    it("wipes stale keys like dismissOnClick", function()
        SelfCareDB.dismissOnClick = true
        SelfCare.ResetToDefaults()
        assert.is_nil(SelfCareDB.dismissOnClick)
    end)

    it("restores default values", function()
        SelfCareDB.hydrateInterval = 9999
        SelfCare.ResetToDefaults()
        assert.equal(SelfCare.DEFAULTS.hydrateInterval, SelfCareDB.hydrateInterval)
    end)

    it("calls RestartTimers", function()
        local called = false
        SelfCare.RestartTimers = function() called = true end
        SelfCare.ResetToDefaults()
        assert.is_true(called)
    end)

    it("is triggered by the Settings Defaults button", function()
        local called = false
        SelfCare.ResetToDefaults = function() called = true end
        SelfCare.Category:_TriggerRevert()
        assert.is_true(called)
    end)
end)
```

**Step 2: Run tests to verify they fail**

```
bash scripts/run-tests.sh --tap
```

Expected: FAIL — `SelfCare.ResetToDefaults` is nil, `_TriggerRevert` finds no callback.

**Step 3: Implement `SelfCare.ResetToDefaults` in Init.lua**

Add after `SelfCare.TestAlert` in `src/Init.lua`:

```lua
--- Wipe SelfCareDB entirely and restore factory defaults.
--- Called by the Settings panel's Defaults button.
function SelfCare.ResetToDefaults()
    for k in pairs(SelfCareDB) do
        SelfCareDB[k] = nil
    end
    SelfCare.ApplyDefaults()
    SelfCare.RestartTimers()
    SelfCare.Print("Settings reset to defaults.")
end
```

**Step 4: Hook `SetRevertCallback` in Settings.lua**

After `Settings.RegisterAddOnCategory(category)` at line 197 of `src/Settings.lua`, add:

```lua
category:SetRevertCallback(SelfCare.ResetToDefaults)
```

**Step 5: Run tests to verify they pass**

```
bash scripts/run-tests.sh --tap
```

Expected: PASS — all ResetToDefaults tests green, no regressions.

**Step 6: Commit**

```bash
git add src/Init.lua src/Settings.lua spec/init_spec.lua
git commit -m "Add ResetToDefaults and hook Settings Defaults button"
```

---

### Task 4: Copy to WoW AddOns folder and open PR

**Step 1: Copy changed files**

```bash
cp src/Init.lua "D:/Games/World of Warcraft/_retail_/Interface/AddOns/SelfCare/src/Init.lua"
cp src/Settings.lua "D:/Games/World of Warcraft/_retail_/Interface/AddOns/SelfCare/src/Settings.lua"
```

**Step 2: Open PR**

```bash
git push origin HEAD
gh pr create --title "Add /selfcare debug command and full DB reset on Defaults" --body "..."
```
