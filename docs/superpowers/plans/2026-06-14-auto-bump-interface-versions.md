# Auto-bump TOC Interface Versions + Auto-release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A daily GitHub Actions workflow that detects new live WoW interface versions from wago.tools, bumps the matching TOC files forward, and ships a CurseForge release with zero manual steps on the happy path.

**Architecture:** A pure, unit-tested Lua module (`scripts/interface_bump.lua`) holds all decision logic — parsing versions, computing interface numbers, matching live products to TOCs by major version, and forward-only bump planning. A thin CLI wrapper (`scripts/bump_interface_cli.lua`) does file I/O. A new workflow (`bump-interface.yml`) fetches data, runs the CLI, and on any change commits to `master` + pushes a `vX.Y.Z` tag (via a PAT) which triggers the existing, unchanged `release.yml`.

**Tech Stack:** Lua 5.1, busted (existing test harness), GitHub Actions, `jq` (preinstalled on ubuntu runners), `curl`, `BigWigsMods/packager` (existing).

**Design reference:** `docs/superpowers/specs/2026-06-14-auto-bump-interface-versions-design.md`

---

## File Structure

- **Create** `scripts/interface_bump.lua` — pure module (no I/O). All logic + the live-product whitelist. Returns a module table.
- **Create** `scripts/bump_interface_cli.lua` — CLI entrypoint. Reads the jq-extracted live versions file + TOC paths from argv, calls the module, writes files, prints the new version or `NO_CHANGE`.
- **Create** `spec/interface_bump_spec.lua` — busted unit tests for the pure module.
- **Create** `.github/workflows/bump-interface.yml` — daily cron + manual workflow.
- **Modify** none. `release.yml` is reused unchanged.

### Module API (`scripts/interface_bump.lua`)

All functions are pure (no file/network I/O):

- `M.WHITELIST` — set of live product names: `wow`, `wow_classic`, `wow_anniversary`, `wow_classic_era`.
- `M.compute_interface(version)` → number | nil. `"12.0.5.67823"` → `120005`. Uses first three dotted segments: `major*10000 + minor*100 + patch`. Returns nil if unparseable.
- `M.major_of(interface)` → number. `120005` → `12` (i.e. `math.floor(interface / 10000)`).
- `M.bump_patch(version)` → string. `"1.0.0"` → `"1.0.1"` (increments the third segment).
- `M.parse_live(text)` → list of interface numbers. Input is newline-separated `"<product> <version>"` lines (jq output). Keeps only whitelisted products with a parseable version.
- `M.read_interface(toc_text)` → number | nil. Extracts the `## Interface:` value.
- `M.read_version(toc_text)` → string | nil. Extracts the `## Version:` value.
- `M.set_interface_line(toc_text, new_interface)` → string. Returns toc_text with its `## Interface:` line rewritten.
- `M.set_version_line(toc_text, new_version)` → string. Returns toc_text with its `## Version:` line rewritten.
- `M.plan_bumps(current, live)` → list of `{file, from, to}`. `current` is a list of `{file, interface}`; `live` is a list of interface numbers. For each current TOC, find the **max** live interface sharing the same major version; if it is strictly greater than the TOC's current interface, emit a bump.

---

## Task 1: Pure module — version math

**Files:**
- Create: `scripts/interface_bump.lua`
- Test: `spec/interface_bump_spec.lua`

- [ ] **Step 1: Write the failing test**

Create `spec/interface_bump_spec.lua`:

```lua
-- =============================================================================
-- spec/interface_bump_spec.lua
-- Unit tests for scripts/interface_bump.lua (pure interface-version logic).
-- =============================================================================

local bump = dofile("scripts/interface_bump.lua")

describe("interface_bump", function()

    describe("compute_interface", function()
        it("converts a 4-segment version string to an interface number", function()
            assert.equal(120005, bump.compute_interface("12.0.5.67823"))
            assert.equal(50504, bump.compute_interface("5.5.4.68077"))
            assert.equal(20505, bump.compute_interface("2.5.5.68101"))
            assert.equal(11508, bump.compute_interface("1.15.8.67156"))
        end)

        it("returns nil for unparseable input", function()
            assert.is_nil(bump.compute_interface("not-a-version"))
            assert.is_nil(bump.compute_interface(""))
        end)
    end)

    describe("major_of", function()
        it("extracts the major version from an interface number", function()
            assert.equal(12, bump.major_of(120005))
            assert.equal(5, bump.major_of(50504))
            assert.equal(2, bump.major_of(20505))
            assert.equal(1, bump.major_of(11508))
        end)
    end)

    describe("bump_patch", function()
        it("increments the patch segment", function()
            assert.equal("1.0.1", bump.bump_patch("1.0.0"))
            assert.equal("1.0.10", bump.bump_patch("1.0.9"))
            assert.equal("2.3.5", bump.bump_patch("2.3.4"))
        end)
    end)

end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/run-tests.sh --tap spec/interface_bump_spec.lua`
Expected: FAIL — `cannot open scripts/interface_bump.lua` / dofile error.

- [ ] **Step 3: Write minimal implementation**

Create `scripts/interface_bump.lua`:

```lua
-- =============================================================================
-- scripts/interface_bump.lua
-- Pure logic for detecting and planning WoW TOC interface-version bumps.
-- No file or network I/O lives here so it can be unit-tested with busted.
-- =============================================================================

local M = {}

-- Live WoW products whose latest build feeds a TOC. PTR/beta/test products
-- (wowt, wowxptr, wowz, wow_beta, wow_classic_ptr, ...) are deliberately absent.
M.WHITELIST = {
    wow = true,             -- Retail (Mainline)
    wow_classic = true,     -- current Classic progression (MoP today)
    wow_anniversary = true, -- Anniversary progression (TBC today; advances over time)
    wow_classic_era = true, -- Classic Era
}

-- "12.0.5.67823" -> 120005  (major*10000 + minor*100 + patch)
function M.compute_interface(version)
    if type(version) ~= "string" then return nil end
    local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)")
    if not major then return nil end
    return tonumber(major) * 10000 + tonumber(minor) * 100 + tonumber(patch)
end

-- 120005 -> 12
function M.major_of(interface)
    return math.floor(interface / 10000)
end

-- "1.0.0" -> "1.0.1"
function M.bump_patch(version)
    local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)$")
    return string.format("%d.%d.%d", tonumber(major), tonumber(minor), tonumber(patch) + 1)
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/run-tests.sh --tap spec/interface_bump_spec.lua`
Expected: PASS (all version-math tests green).

- [ ] **Step 5: Commit**

```bash
git add scripts/interface_bump.lua spec/interface_bump_spec.lua
git commit -m "feat: add interface-version math (compute/major/bump)"
```

---

## Task 2: Pure module — TOC text accessors

**Files:**
- Modify: `scripts/interface_bump.lua`
- Test: `spec/interface_bump_spec.lua`

- [ ] **Step 1: Write the failing test**

Add inside the top-level `describe("interface_bump", ...)` block in `spec/interface_bump_spec.lua`:

```lua
    local SAMPLE_TOC = table.concat({
        "## Interface: 120001",
        "## Title: SelfCare",
        "## Version: 1.0.0",
        "## SavedVariables: SelfCareDB",
        "",
        "src/Core.lua",
    }, "\n")

    describe("read_interface / read_version", function()
        it("reads the interface number", function()
            assert.equal(120001, bump.read_interface(SAMPLE_TOC))
        end)
        it("reads the version string", function()
            assert.equal("1.0.0", bump.read_version(SAMPLE_TOC))
        end)
    end)

    describe("set_interface_line / set_version_line", function()
        it("rewrites only the interface line", function()
            local out = bump.set_interface_line(SAMPLE_TOC, 120005)
            assert.equal(120005, bump.read_interface(out))
            assert.equal("1.0.0", bump.read_version(out))      -- untouched
            assert.is_truthy(out:find("## Title: SelfCare", 1, true))
        end)
        it("rewrites only the version line", function()
            local out = bump.set_version_line(SAMPLE_TOC, "1.0.1")
            assert.equal("1.0.1", bump.read_version(out))
            assert.equal(120001, bump.read_interface(out))     -- untouched
        end)
    end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/run-tests.sh --tap spec/interface_bump_spec.lua`
Expected: FAIL — `attempt to call field 'read_interface' (a nil value)`.

- [ ] **Step 3: Write minimal implementation**

Add to `scripts/interface_bump.lua` before `return M`:

```lua
function M.read_interface(toc_text)
    local n = toc_text:match("##%s*Interface:%s*(%d+)")
    return n and tonumber(n) or nil
end

function M.read_version(toc_text)
    return toc_text:match("##%s*Version:%s*([^\r\n]+)")
end

function M.set_interface_line(toc_text, new_interface)
    return (toc_text:gsub("(##%s*Interface:%s*)%d+", "%1" .. new_interface, 1))
end

function M.set_version_line(toc_text, new_version)
    return (toc_text:gsub("(##%s*Version:%s*)[^\r\n]+", "%1" .. new_version, 1))
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/run-tests.sh --tap spec/interface_bump_spec.lua`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/interface_bump.lua spec/interface_bump_spec.lua
git commit -m "feat: add TOC interface/version line accessors"
```

---

## Task 3: Pure module — parse_live (whitelist filter)

**Files:**
- Modify: `scripts/interface_bump.lua`
- Test: `spec/interface_bump_spec.lua`

- [ ] **Step 1: Write the failing test**

Add inside the top-level describe block:

```lua
    describe("parse_live", function()
        local LIVE_TEXT = table.concat({
            "wow 12.0.5.67823",
            "wow_classic 5.5.4.68077",
            "wow_anniversary 2.5.5.68101",
            "wow_classic_era 1.15.8.67156",
            "wowxptr 12.0.7.67808",        -- PTR: must be ignored
            "wow_classic_beta 5.5.9.99999", -- beta: must be ignored
        }, "\n")

        it("keeps only whitelisted products as interface numbers", function()
            local live = bump.parse_live(LIVE_TEXT)
            table.sort(live)
            assert.same({ 11508, 20505, 50504, 120005 }, live)
        end)

        it("ignores blank lines and malformed entries", function()
            local live = bump.parse_live("\nwow 12.0.5.1\n\ngarbage\nwow bad-version\n")
            assert.same({ 120005 }, live)
        end)
    end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/run-tests.sh --tap spec/interface_bump_spec.lua`
Expected: FAIL — `attempt to call field 'parse_live' (a nil value)`.

- [ ] **Step 3: Write minimal implementation**

Add to `scripts/interface_bump.lua` before `return M`:

```lua
function M.parse_live(text)
    local result = {}
    for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        local product, version = line:match("^(%S+)%s+(%S+)$")
        if product and M.WHITELIST[product] then
            local iface = M.compute_interface(version)
            if iface then result[#result + 1] = iface end
        end
    end
    return result
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/run-tests.sh --tap spec/interface_bump_spec.lua`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/interface_bump.lua spec/interface_bump_spec.lua
git commit -m "feat: parse live versions with product whitelist"
```

---

## Task 4: Pure module — plan_bumps (major-match, forward-only)

**Files:**
- Modify: `scripts/interface_bump.lua`
- Test: `spec/interface_bump_spec.lua`

- [ ] **Step 1: Write the failing test**

Add inside the top-level describe block:

```lua
    describe("plan_bumps", function()
        -- Mirrors the real repo state on 2026-06-14.
        local CURRENT = {
            { file = "SelfCare.toc",         interface = 120001 }, -- retail, stale
            { file = "SelfCare_Mists.toc",   interface = 50503  }, -- MoP, stale
            { file = "SelfCare_TBC.toc",     interface = 20505  }, -- TBC, current
            { file = "SelfCare_Vanilla.toc", interface = 11508  }, -- Era, current
            { file = "SelfCare_Wrath.toc",   interface = 30403  }, -- no live major-3 product
            { file = "SelfCare_Cata.toc",    interface = 40402  }, -- no live major-4 product
        }
        local LIVE = { 120005, 50504, 20505, 11508 }

        it("bumps only stale TOCs whose major matches a live product", function()
            local bumps = bump.plan_bumps(CURRENT, LIVE)
            local by_file = {}
            for _, b in ipairs(bumps) do by_file[b.file] = b.to end
            assert.equal(120005, by_file["SelfCare.toc"])
            assert.equal(50504, by_file["SelfCare_Mists.toc"])
            assert.is_nil(by_file["SelfCare_TBC.toc"])     -- already current
            assert.is_nil(by_file["SelfCare_Vanilla.toc"]) -- already current
            assert.is_nil(by_file["SelfCare_Wrath.toc"])   -- frozen, no live major 3
            assert.is_nil(by_file["SelfCare_Cata.toc"])    -- frozen, no live major 4
            assert.equal(2, #bumps)
        end)

        it("never downgrades (forward-only)", function()
            local current = { { file = "X.toc", interface = 120009 } }
            assert.same({}, bump.plan_bumps(current, { 120005 }))
        end)

        it("picks the max live interface when several share a major", function()
            local current = { { file = "X.toc", interface = 120001 } }
            local bumps = bump.plan_bumps(current, { 120003, 120005, 120002 })
            assert.equal(1, #bumps)
            assert.equal(120005, bumps[1].to)
        end)
    end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/run-tests.sh --tap spec/interface_bump_spec.lua`
Expected: FAIL — `attempt to call field 'plan_bumps' (a nil value)`.

- [ ] **Step 3: Write minimal implementation**

Add to `scripts/interface_bump.lua` before `return M`:

```lua
function M.plan_bumps(current, live)
    -- Highest live interface per major version.
    local best_by_major = {}
    for _, iface in ipairs(live) do
        local maj = M.major_of(iface)
        if not best_by_major[maj] or iface > best_by_major[maj] then
            best_by_major[maj] = iface
        end
    end

    local bumps = {}
    for _, toc in ipairs(current) do
        local target = best_by_major[M.major_of(toc.interface)]
        if target and target > toc.interface then
            bumps[#bumps + 1] = { file = toc.file, from = toc.interface, to = target }
        end
    end
    return bumps
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/run-tests.sh --tap spec/interface_bump_spec.lua`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/interface_bump.lua spec/interface_bump_spec.lua
git commit -m "feat: plan forward-only interface bumps by major version"
```

---

## Task 5: CLI wrapper (file I/O)

**Files:**
- Create: `scripts/bump_interface_cli.lua`

This wrapper has no busted test (it is thin I/O glue over the tested module); it is exercised manually in Step 3 and by the workflow.

- [ ] **Step 1: Write the implementation**

Create `scripts/bump_interface_cli.lua`:

```lua
-- =============================================================================
-- scripts/bump_interface_cli.lua
-- Thin I/O wrapper around scripts/interface_bump.lua.
--
-- Usage:
--   lua scripts/bump_interface_cli.lua <live-versions-file> <toc> [<toc> ...]
--
-- <live-versions-file> contains "<product> <version>" lines (jq output).
-- On a change: rewrites the affected TOCs' interface lines, patch-bumps the
-- version across ALL given TOCs, and prints the new version (e.g. "1.0.1").
-- On no change: prints "NO_CHANGE". Exits 0 in both cases.
-- =============================================================================

local M = dofile("scripts/interface_bump.lua")

local function read_file(path)
    local f = assert(io.open(path, "rb"), "cannot read " .. path)
    local content = f:read("*a")
    f:close()
    return content
end

local function write_file(path, content)
    local f = assert(io.open(path, "wb"), "cannot write " .. path)
    f:write(content)
    f:close()
end

local live_file = assert(arg[1], "usage: bump_interface_cli.lua <live-file> <toc>...")
local toc_paths = {}
for i = 2, #arg do toc_paths[#toc_paths + 1] = arg[i] end
assert(#toc_paths > 0, "no TOC files given")

-- Parse live versions.
local live = M.parse_live(read_file(live_file))

-- Defensive: a healthy fetch always includes retail ("wow"). 120000+ guards
-- against a junk/empty source slipping through to a release.
local has_retail = false
for _, iface in ipairs(live) do
    if M.major_of(iface) >= 12 then has_retail = true end
end
if not has_retail then
    io.stderr:write("ERROR: no retail (major>=12) interface in live data; refusing to act\n")
    os.exit(1)
end

-- Read current TOC interface numbers.
local toc_text = {}     -- path -> content
local current = {}
for _, path in ipairs(toc_paths) do
    local content = read_file(path)
    toc_text[path] = content
    local iface = M.read_interface(content)
    if iface then
        current[#current + 1] = { file = path, interface = iface }
    end
end

local bumps = M.plan_bumps(current, live)
if #bumps == 0 then
    print("NO_CHANGE")
    os.exit(0)
end

-- Apply interface bumps.
for _, b in ipairs(bumps) do
    toc_text[b.file] = M.set_interface_line(toc_text[b.file], b.to)
    io.stderr:write(string.format("bump %s: %d -> %d\n", b.file, b.from, b.to))
end

-- Patch-bump version across ALL TOCs (source of truth = first TOC).
local old_version = assert(M.read_version(toc_text[toc_paths[1]]), "no ## Version in " .. toc_paths[1])
local new_version = M.bump_patch(old_version)
for _, path in ipairs(toc_paths) do
    toc_text[path] = M.set_version_line(toc_text[path], new_version)
end

-- Write everything back.
for path, content in pairs(toc_text) do
    write_file(path, content)
end

print(new_version)
```

- [ ] **Step 2: Run it to verify NO_CHANGE on already-current input**

```bash
printf 'wow 12.0.1.1\nwow_classic 5.5.3.1\nwow_anniversary 2.5.5.1\nwow_classic_era 1.15.8.1\n' > /tmp/live.txt
"C:/Program Files (x86)/Lua/5.1/lua.exe" scripts/bump_interface_cli.lua /tmp/live.txt SelfCare.toc SelfCare_Mists.toc SelfCare_TBC.toc SelfCare_Vanilla.toc SelfCare_Wrath.toc SelfCare_Cata.toc
```

Expected: prints `NO_CHANGE` (retail live 12.0.1 == current 120001), no files modified. Confirm with `git status` (clean).

- [ ] **Step 3: Run it to verify a real bump (then discard changes)**

```bash
printf 'wow 12.0.5.1\nwow_classic 5.5.4.1\nwow_anniversary 2.5.5.1\nwow_classic_era 1.15.8.1\n' > /tmp/live.txt
"C:/Program Files (x86)/Lua/5.1/lua.exe" scripts/bump_interface_cli.lua /tmp/live.txt SelfCare.toc SelfCare_Mists.toc SelfCare_TBC.toc SelfCare_Vanilla.toc SelfCare_Wrath.toc SelfCare_Cata.toc
```

Expected: prints `1.0.1`; stderr shows `bump SelfCare.toc: 120001 -> 120005` and `bump SelfCare_Mists.toc: 50503 -> 50504`. Verify with `git diff` that retail+Mists interface lines changed and ALL six TOCs' version went to `1.0.1`. Then revert:

```bash
git checkout -- SelfCare.toc SelfCare_Mists.toc SelfCare_TBC.toc SelfCare_Vanilla.toc SelfCare_Cata.toc SelfCare_Wrath.toc
```

- [ ] **Step 4: Commit**

```bash
git add scripts/bump_interface_cli.lua
git commit -m "feat: add CLI wrapper for interface bumping"
```

---

## Task 6: Prerequisite — create the release PAT secret

A tag pushed by the default `GITHUB_TOKEN` does **not** trigger other workflows (GitHub's anti-recursion rule), so `release.yml` would not fire. The bump workflow therefore pushes using a fine-grained Personal Access Token stored as a secret. This is a one-time manual setup.

- [ ] **Step 1: Create a fine-grained PAT**

On GitHub: Settings → Developer settings → Fine-grained personal access tokens → Generate new token.
- Repository access: only `Valiice/WoW-SelfCare` (the addon repo).
- Permissions → Repository → **Contents: Read and write**.
- Set an expiry and a calendar reminder to rotate it.

- [ ] **Step 2: Add it as a repo secret**

Repo → Settings → Secrets and variables → Actions → New repository secret.
- Name: `RELEASE_PAT`
- Value: the token from Step 1.

- [ ] **Step 3: Confirm master allows the push**

If branch protection is enabled on `master`, ensure the PAT's account can push (or that the protection allows it). For a solo repo with no protection, nothing to do.

(No commit — this is GitHub configuration, not repo content.)

---

## Task 7: The bump-interface workflow

**Files:**
- Create: `.github/workflows/bump-interface.yml`

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/bump-interface.yml`:

```yaml
name: Bump interface versions

on:
  schedule:
    - cron: '0 8 * * *'   # daily at 08:00 UTC
  workflow_dispatch:

permissions:
  contents: write

jobs:
  bump:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          # PAT so the pushed tag triggers release.yml (GITHUB_TOKEN would not).
          token: ${{ secrets.RELEASE_PAT }}

      - name: Set up Lua
        uses: hishamhm/gh-actions-lua@master
        with:
          luaVersion: "5.1"

      - name: Fetch live build versions
        run: |
          # --fail: non-zero exit on HTTP error -> job fails (ship nothing).
          curl --fail --silent --show-error --location \
            "https://wago.tools/api/builds" -o builds.json
          # Latest (first) version per product -> "<product> <version>" lines.
          jq -r 'to_entries[] | "\(.key) \(.value[0].version)"' builds.json > live.txt
          echo "--- live.txt ---"
          cat live.txt

      - name: Compute bumps
        id: bump
        run: |
          NEW_VERSION=$(lua scripts/bump_interface_cli.lua live.txt SelfCare*.toc)
          echo "version=$NEW_VERSION" >> "$GITHUB_OUTPUT"
          echo "Result: $NEW_VERSION"

      - name: Commit, tag and push
        if: steps.bump.outputs.version != 'NO_CHANGE'
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add SelfCare*.toc
          git commit -m "chore: bump interface versions (v${{ steps.bump.outputs.version }})"
          git tag "v${{ steps.bump.outputs.version }}"
          git push origin HEAD --follow-tags
```

- [ ] **Step 2: Validate YAML syntax locally**

```bash
"C:/Program Files (x86)/Lua/5.1/lua.exe" -e "print('yaml has no lua linter; visually confirm indentation')"
```

Then eyeball: two-space indentation, `on.schedule.cron` quoted, `if:` on the commit step compares against the string `'NO_CHANGE'`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/bump-interface.yml
git commit -m "ci: add daily interface-version bump workflow"
```

---

## Task 8: Documentation note

**Files:**
- Modify: `CLAUDE.md` (the "## WoW API Notes" or a new "## Versioning" section)

- [ ] **Step 1: Add a versioning note**

Add this section to `CLAUDE.md` after the "## WoW API Notes" section:

```markdown
## Interface Version Maintenance

Interface versions are bumped automatically. `.github/workflows/bump-interface.yml`
runs daily, reads the latest live build per flavor from `https://wago.tools/api/builds`,
and bumps any TOC whose major version matches a live product and is behind
(forward-only; PTR/beta excluded). On a change it patch-bumps `## Version:` across
all TOCs, commits to `master`, and pushes a `vX.Y.Z` tag that triggers `release.yml`.

The pushed tag uses the `RELEASE_PAT` secret (a fine-grained PAT with Contents:
write) because a tag pushed by the default `GITHUB_TOKEN` would not trigger
`release.yml`. Logic lives in `scripts/interface_bump.lua` (pure, unit-tested in
`spec/interface_bump_spec.lua`); `scripts/bump_interface_cli.lua` is the I/O wrapper.

Flavors with no currently-live game build (e.g. Wrath, Cata today) stay frozen at
their last interface number until a live progression (`wow_anniversary`) advances
to match their major version.
```

- [ ] **Step 2: Run the full test suite to confirm nothing regressed**

Run: `bash scripts/run-tests.sh --tap`
Expected: all specs PASS (the original 112 + the new interface_bump tests).

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document automatic interface-version bumping"
```

---

## Task 9: Final verification

- [ ] **Step 1: Confirm `.pkgmeta` already excludes the new dev files**

`scripts/` and `spec/` are already under `ignore:` in `.pkgmeta`, and `docs/` too,
so the new module, CLI, and tests will not be bundled into the CurseForge zip.
`.github` is also ignored. Read `.pkgmeta` and confirm — no change expected.

- [ ] **Step 2: Confirm the full suite is green**

Run: `bash scripts/run-tests.sh --tap`
Expected: all PASS.

- [ ] **Step 3: (After merge to master) trigger a manual dry run**

Once this branch is merged to `master` and `RELEASE_PAT` is set, manually run the
workflow: GitHub → Actions → "Bump interface versions" → Run workflow. Because
retail is currently stale (`120001` vs live `120005`), expect it to bump retail +
Mists, push `v1.0.1`, and trigger `release.yml`. Watch the Actions tab to confirm
the release packages and uploads.

---

## Self-Review

**Spec coverage:**
- Data source (wago.tools, grouped JSON, first entry newest) → Tasks 3, 7. ✓
- Interface formula → Task 1. ✓
- Live-product whitelist → Task 3 (`M.WHITELIST`). ✓
- Major-match + forward-only → Task 4. ✓
- New `bump-interface.yml` (daily + dispatch, whitelist, find-by-major, bump, version sync, commit, tag) → Tasks 5, 7. ✓
- Reuse `release.yml` unchanged → Task 7 (tag trigger via PAT). ✓ The spec's "push tag → triggers release.yml" is preserved; the PAT (Task 6) is the mechanism that makes it actually fire, documented as a refinement.
- Fail-loud on source error → Task 7 (`curl --fail`, jq parse) + Task 5 (retail-present guard). ✓
- Idempotent (no change → no release) → Task 5 (`NO_CHANGE`) + Task 7 (`if:` guard). ✓
- Safety guards table → distributed across Tasks 3/4/5/7. ✓
- Testing (fixture-driven unit tests) → Tasks 1–4 use inline tables/strings instead of fixture files (simpler, same coverage: stale retail, current Era, frozen Wrath, forward-only, PTR ignored). ✓
- Edge cases (two products same major → max; major matches no TOC → untouched; version drift → resync) → Tasks 4 + 5. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✓

**Type consistency:** `compute_interface`, `major_of`, `bump_patch`, `parse_live`, `read_interface`, `read_version`, `set_interface_line`, `set_version_line`, `plan_bumps` are named identically across the module definition, tests, and CLI. Bump records use `{file, from, to}` consistently. ✓
