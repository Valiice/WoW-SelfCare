# Design: All-Classic-Flavors Support

**Date:** 2026-03-25

## Problem

`SelfCare_Vanilla.toc` covers Classic Era (interface `11508`). CurseForge requires a separate TOC file per game flavor — using its prescribed filename suffix — for the addon to appear in flavor-specific searches. BCC Anniversary, WotLK Classic, Cataclysm Classic, and MoP Classic are not currently surfaced.

## Approach

TOC files only. The modern `Settings.*` API is backported to all active Classic servers, and `Settings.lua` already guards the two retail-only globals (`MinimalSliderWithSteppersMixin`, `CreateSettingsButtonInitializer`). No Lua changes are needed.

Note: WoW also supports a single-TOC multi-version format (`## Interface-TBC: ...`), but the separate-file approach is used here for consistency with the existing `SelfCare_Vanilla.toc` and for clearer CurseForge flavor association.

## New Files

| File | Flavor | Interface | Source |
|---|---|---|---|
| `SelfCare_TBC.toc` | BCC Anniversary | `20505` (2.5.5) | CurseForge addon files updated Feb 2026; Warcraft Wiki TOC format page |
| `SelfCare_Wrath.toc` | WotLK Classic | `30403` (3.4.3) | Warcraft Wiki TOC format; 3.4.4/3.4.5 are China-exclusive |
| `SelfCare_Cata.toc` | Cataclysm Classic | `40402` (4.4.2) | Warcraft Wiki Patch 4.4.2; Warcraft Wiki TOC format page |
| `SelfCare_Mists.toc` | MoP Classic | `50503` (5.5.3) | Warcraft Wiki Patch 5.5.3; Warcraft Wiki TOC format page |

Reference: [Warcraft Wiki: TOC format](https://warcraft.wiki.gg/wiki/TOC_format) — documents all flavor suffixes including `_Mists`.

The filename suffix (`_TBC`, `_Wrath`, `_Cata`, `_Mists`) must match the Warcraft Wiki TOC format conventions (also used by CurseForge's packager) exactly — this is what causes CurseForge to associate each TOC with the correct game flavor. A wrong suffix means the file exists but is never associated with the flavor.

Each file is structurally identical to `SelfCare_Vanilla.toc` — same metadata, same source file list — with only `## Interface:` changed to the value above.

Note on MoP interface version: `50503` is the current live patch as of March 2026. If a new MoP patch ships before this is merged, verify the interface number at the TOC format page and update accordingly.

## Files Not Changed

- `SelfCare.toc` (retail)
- `SelfCare_Vanilla.toc` (Classic Era)
- All `src/*.lua` files
- `.pkgmeta` — the ignore list contains no TOC entries, and there are no `move-folders:` or `package-as:` directives, so new root-level TOC files are picked up automatically by the CurseForge packager

## Testing (TDD)

Run tests with: `bash scripts/run-tests.sh --tap` (requires `lua_modules/` from `scripts/install-test-deps.sh`).

Extend the existing `describe("TOC files", ...)` block in `spec/settings_spec.lua` with **two `it()` blocks per new flavor** (eight new tests total), following the same pattern as the existing Vanilla tests.

**Hoist `extractFiles`:** The helper is currently defined inline inside the Vanilla file-list `it()` block. Move it to a `local` defined at the top of the `describe("TOC files", ...)` block, before any `it()` call. The two existing Vanilla `it()` bodies are otherwise unchanged — the Vanilla existence test does not use `extractFiles`, and the Vanilla file-list test simply refers to the now-hoisted local.

The `#retail > 0` guard should be added once, inside `extractFiles`'s caller — assert it immediately after extracting the retail file list (before comparing against any flavor TOC). This ensures all file-list tests (Vanilla and new) share the same non-vacuous baseline. There is no need to add it separately in every `it()` block.

For each new flavor, add:

1. **Existence + interface check** — opens the file, searches for the exact string `"## Interface: XXXXX"` (space after colon, matching the Vanilla test pattern) and asserts it is found.
2. **Source file list check** — calls `extractFiles` on the flavor TOC and asserts `assert.same(retail, flavor)` where `retail` is extracted from `SelfCare.toc` (with `#retail > 0` already asserted).

Tests are written first (red), then the TOC files are added to make them pass (green).

The existing "Classic Era compatibility" tests (`WowStubs_SimulateClassic()`) verify the settings panel builds when `MinimalSliderWithSteppersMixin` and `CreateSettingsButtonInitializer` are nil — the two known guards in `Settings.lua`. No additional flavor-specific simulation is added; there is no evidence of further API differences across the active Classic flavors.

## Out of Scope

- Slash-command-only fallback for flavors without a Settings API
- `WOW_PROJECT_ID` flavor detection or branching
- Changes to `WowStubs_SimulateClassic()` — the existing simulation is sufficient for the known guards
- Metadata consistency tests (Title, Author, Version, X-Curse-Project-ID) across TOC files — the source file list check and manual review are sufficient for this change
- Updating `SelfCare.toc` retail interface version — pre-existing drift, separate concern
