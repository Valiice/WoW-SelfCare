# SelfCare

A World of Warcraft addon that gently reminds you to hydrate, check your posture, and take breaks while gaming. Inspired by the [FFXIV SelfCare plugin](https://github.com/chirpxiv/selfcare).

## Features

- **Three configurable reminders:**
  - Hydrate (default: every 60 minutes)
  - Posture check (default: every 30 minutes)
  - Break (default: every 140 minutes)
- **Minimal notification style** — clean centered text overlay, no flashy borders or icons
- **Combat & cutscene awareness** — alerts are queued and shown after combat/cutscenes end
- **Fully configurable** via the WoW Interface Options panel (Esc > Options > AddOns > SelfCare)
- **Click to dismiss** or auto-dismiss after a timer (your choice)
- Optional chat messages

## Installation

1. Download or clone this repository
2. Copy the `SelfCare.lua` and `SelfCare.toc` files into:
   ```
   World of Warcraft\_retail_\Interface\AddOns\SelfCare\
   ```
3. Restart WoW or `/reload` if already in-game

## Usage

| Command | What it does |
|---|---|
| `/selfcare` | Opens the settings panel |
| `/selfcare test` | Fires all three alerts immediately |
| `/run SelfCare_TestAlert("hydrate")` | Test a specific alert |
| `/run SelfCare_RestartTimers()` | Restart all timers (useful after manual DB edits) |

## Settings

All settings are accessible from the in-game Interface Options panel:

- **Global:** Disable during combat, disable during cutscenes, print to chat, click-to-dismiss vs auto-dismiss
- **Per-alert:** Enable/disable each reminder, adjust interval from 5 to 300 minutes

## Requirements

- WoW Retail 11.x (The War Within)
- Interface version: 110100

## Development

You can test the addon offline without WoW using Lua 5.1:

```bash
# Install Lua (Windows, via Chocolatey)
choco install lua

# Run the test suite
"C:\Program Files (x86)\Lua\5.1\lua.exe" test_stub.lua
```

The test stub mocks the WoW API and verifies that the addon loads correctly, events fire properly, and all defaults are applied.

## License

MIT
