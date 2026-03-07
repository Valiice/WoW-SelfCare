# Debug Command and Defaults Reset Design

**Goal:** Add `/selfcare debug` snapshot command and make the Defaults button fully wipe SelfCareDB.

**Architecture:** Two small, independent changes — one new slash subcommand in Init.lua, one revert callback hook in Settings.lua.

---

## Feature 1: `/selfcare debug` snapshot

**Command:** `/selfcare debug`

**Output (printed to chat):**
```
SelfCare Debug:
  hydrate — due 19:27:58 (in 4m 12s)  [5 min interval]
  posture — due 19:26:27 (in 2m 41s)  [5 min interval]
  break   — due 21:07:15 (in 1h 40m)  [2h 20m interval]
```

**Rules:**
- If `nextDue` is nil for an alert → show `[pending first fire]`
- If the alert is disabled → show `[disabled]`
- "in X" is calculated as `nextDue - time()`, formatted as `Xm Ys` or `Xh Ym`
- Uses `SelfCare.Print()` for each line (same prefix as all other chat output)

**File:** `src/Init.lua` — add `elseif cmd == "debug"` branch in `SlashCmdList["SELFCARE"]`

---

## Feature 2: Defaults button wipes full DB

**Trigger:** Built-in WoW Settings "Defaults" button on the SelfCare panel.

**Hook:** `category:SetRevertCallback(fn)` called in `BuildSettingsPanel()` after the category is created.

**Callback behaviour:**
1. Wipe `SelfCareDB` to `{}`
2. Call `SelfCare.ApplyDefaults()` — repopulates all keys from `DEFAULTS`
3. Call `SelfCare.RestartTimers()` — starts fresh full-interval tickers, clears `nextDue`

**Effect:** Clears `nextDue`, `notifPos`, stale `dismissOnClick`, and resets every setting to its factory default. Timers restart immediately from zero.

**File:** `src/Settings.lua` — add `category:SetRevertCallback(...)` after `Settings.RegisterAddOnCategory(category)`
