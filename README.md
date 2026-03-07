# SelfCare

A World of Warcraft addon that gently reminds you to hydrate, check your posture, and take breaks while gaming. Inspired by the [FFXIV SelfCare plugin](https://github.com/chirpxiv/selfcare).

## Features

- **Three configurable reminders:**
  - Hydrate (default: every 60 minutes)
  - Posture check (default: every 30 minutes)
  - Break (default: every 140 minutes)
- **Minimal notification style** — clean centered text overlay, no flashy borders or icons
- **Combat, cutscene & AFK awareness** — alerts are queued and shown when you return
- **Fully configurable** via the WoW Interface Options panel (Esc > Options > AddOns > SelfCare)
- **Click to dismiss** or auto-dismiss after a timer (your choice)
- Optional chat messages

## Installation

**From CurseForge:** Install via the CurseForge app (recommended).

**Manually:**
1. Download the latest release zip from the [Releases](../../releases) page
2. Extract the `SelfCare` folder into:
   ```
   World of Warcraft\_retail_\Interface\AddOns\
   ```
3. Restart WoW or `/reload` if already in-game

## Usage

| Command | What it does |
|---|---|
| `/selfcare` | Opens the settings panel |
| `/selfcare test` | Fires all three alerts immediately |
| `/selfcare debug` | Prints timer status to chat (due time, interval, disabled/pending per alert) |
| `/run SelfCare_TestAlert("hydrate")` | Test a specific alert |
| `/run SelfCare_RestartTimers()` | Restart all timers (useful after manual DB edits) |

## Settings

All settings are accessible from the in-game Interface Options panel:

- **Global:** Disable during combat, cutscenes, or AFK; print to chat; auto-dismiss delay; alert sound
- **Reset to Defaults** button — fully wipes saved state and restarts all timers fresh
- **Per-alert:** Enable/disable each reminder, adjust interval from 5 to 300 minutes

## Requirements

- WoW Retail 11.x / The War Within
- Interface version: 120001

## Development

### Smoke test (fast, no dependencies)

```bash
# Install Lua 5.1 (Windows, via Chocolatey)
choco install lua

# Run the smoke test — loads all files, fires events, checks DB defaults
"C:\Program Files (x86)\Lua\5.1\lua.exe" test_stub.lua
```

### Unit tests with busted

Full BDD-style tests with mocks and spies live in `spec/`.

**Linux / macOS (LuaRocks 3.x):**

```bash
luarocks install busted
busted                  # TAP output (configured in .busted)
```

**Windows (Lua 5.1 via Chocolatey, LuaRocks 2.x):**

The choco `lua` package ships LuaRocks 2.0.x which is too old for busted.
Use the provided helper scripts instead:

```bash
# One-time setup: downloads deps into lua_modules/
bash scripts/install-test-deps.sh

# Run all tests
bash scripts/run-tests.sh

# TAP output
bash scripts/run-tests.sh --tap
```

Tests are organised as:

| File | What it covers |
|------|---------------|
| `spec/core_spec.lua` | DEFAULTS, ALERTS, ApplyDefaults, FindAlertByKey, key helpers |
| `spec/timers_spec.lua` | Timer creation, combat/cutscene deferral, FlushPending, RestartTimers |
| `spec/notifications_spec.lua` | ShowNotif/HideNotif, sound, chat print, auto-dismiss timer |
| `spec/init_spec.lua` | ADDON_LOADED → PLAYER_LOGIN event flow, slash commands, TestAlert |

### Continuous Integration

GitHub Actions runs on every push and pull request to `master`:
- Lua syntax lint on all `.lua` files
- Full `busted` test suite
- `test_stub.lua` smoke test

## License

MIT
