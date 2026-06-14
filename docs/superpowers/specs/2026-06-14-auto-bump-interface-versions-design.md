# Auto-bump TOC interface versions + auto-release

**Date:** 2026-06-14
**Status:** Approved (design)

## Problem

SelfCare ships six TOC files, each pinned to one WoW flavor via its `## Interface:`
number. Those numbers must track the latest live game patch per flavor or the
addon shows as out-of-date on CurseForge. Today they are edited by hand across up
to six files every patch — easy to forget. (At time of writing, `SelfCare.toc`
was already stale: `120001` vs live retail `120005`.)

The release pipeline already auto-maps each TOC's interface number to the correct
CurseForge game version via `BigWigsMods/packager`, so the *only* recurring chore
is keeping those interface numbers current.

## Goal

A scheduled, hands-off pipeline that detects new live interface versions, bumps
the affected TOC files, and ships a release — with no manual step on the happy
path, and no possibility of shipping a wrong version.

## Non-goals

- Bumping TOCs for flavors with no currently-live game build (Wrath, Cata today).
  These stay frozen at their last live interface number until a live product
  matches their major version again.
- Changing how releases are packaged/uploaded. The existing `release.yml` is
  reused unchanged.
- Tracking PTR/beta/test builds.

## Data source

`https://wago.tools/api/builds` — returns a JSON object grouped by product:
`{"wow":[{version, created_at, ...}, ...], "wow_classic":[...], ...}`. The first
entry per product array is the most recent build. Version strings look like
`12.0.5.67823`; the first three dotted segments are the patch version.

Chosen over Blizzard's first-party TACT endpoints (custom port 1119 + BPSV text,
brittle in CI) and the CurseForge versions API (needs a key, reports only which
versions exist on CF rather than the latest live patch).

### Interface number formula

`interface = major*10000 + minor*100 + patch`

Examples: `12.0.5 → 120005`, `5.5.4 → 50504`, `2.5.5 → 20505`, `1.15.8 → 11508`.

### Live-product whitelist

Only these products are consulted (everything else — `wowt`, `wowxptr`, `wowz`,
`wowlivetest`, `wow_beta`, `wow_classic_beta`, `wow_classic_ptr`,
`wow_classic_era_ptr`, `wow_classic_titan` — is ignored):

- `wow` — Retail (Mainline)
- `wow_classic` — current Classic progression (MoP, 5.5.x today)
- `wow_anniversary` — Anniversary progression (TBC, 2.5.x today; advances over time)
- `wow_classic_era` — Classic Era (1.15.x)

A whitelist (not a blacklist) guarantees a newly-introduced beta/test product can
never accidentally ship.

## Flavor mapping: major-version match, forward-only

Product names are **not** hardcoded to TOC files, because `wow_anniversary` is a
moving progression (TBC → Wrath → Cata over time). Instead:

For each whitelisted product's latest interface number `N` (major `M`):
1. Find the repo TOC whose **current** interface number has the same major `M`.
2. If found **and** `N > current`, rewrite that TOC's `## Interface:` line to `N`.
3. Otherwise leave it untouched.

Consequences (all desired):
- When Anniversary rolls from TBC (major 2) to Wrath (major 3), it automatically
  begins feeding `SelfCare_Wrath.toc`; `SelfCare_TBC.toc` keeps its last value.
- Flavors with no matching live product (Wrath/Cata today) stay frozen.
- Forward-only means a TOC is never downgraded.

## Workflows

### New: `.github/workflows/bump-interface.yml`

Triggers: `schedule` (daily cron) + `workflow_dispatch` (manual).
Permissions: `contents: write`.

Steps:
1. Fetch `https://wago.tools/api/builds`. **On any fetch/parse failure, fail the
   job (non-zero exit).** No commit, no release — the run goes red and GitHub
   emails the failure. Never guess.
2. For each whitelisted product, compute its latest interface number.
3. Apply the major-match / forward-only rule against each TOC's current
   `## Interface:` line.
4. If no TOC changed: exit 0 (no-op; the common daily case).
5. If at least one TOC changed:
   - Patch-bump `## Version:` across **all** TOCs in sync (e.g. `1.0.0 → 1.0.1`),
     reading the current version from a TOC and incrementing the patch component.
   - Commit all changes to `master` as the `github-actions[bot]` identity.
   - Create and push tag `vX.Y.Z` (the new version).

### Existing: `release.yml` (unchanged)

The pushed `vX.Y.Z` tag fires the existing release workflow: smoke test + busted
tests run first, then `BigWigsMods/packager` packages all flavors and uploads to
CurseForge. Every auto-release is therefore test-gated.

## Safety guards (summary)

| Guard | Prevents |
|---|---|
| Live-product whitelist | Shipping PTR/beta/test interface numbers |
| Forward-only bump | Downgrading a TOC |
| Major-version match | Cross-contaminating one flavor's TOC with another's number |
| Inherited test gate | Packaging a broken build |
| Idempotent (no change → no tag) | Spurious/empty releases |
| Fail-loud on source error | Acting on missing or junk data |

## Edge cases

- **Two live products share a major version** with one TOC: not the case today;
  if it ever happens, the larger interface wins (forward-only applied per product
  in sequence yields the max).
- **A live product's major matches no TOC** (e.g. a brand-new expansion): no file
  is touched; a human adds the new TOC. Logged for visibility.
- **Version line drift between TOCs:** the bump reads one TOC's version as the
  source of truth and writes the incremented value to all, re-syncing them.
- **Branch protection on master:** direct bot push must be permitted (chosen
  flow is direct commit to master, not a PR).

## Testing

- A self-contained script (Lua or shell) that does the detection/mapping is
  unit-testable: feed it a fixture `builds.json` + a set of current interface
  numbers, assert the computed bumps. Cover: stale retail, current Era, frozen
  Wrath (no match), forward-only (live < current → no change), PTR product
  ignored.
- Keep the fixture under `spec/` (already ignored in `.pkgmeta`).
