# All-Classic-Flavors Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add CurseForge-compatible TOC files for BCC Anniversary, WotLK Classic, Cataclysm Classic, and MoP Classic so the addon appears in all flavor-specific searches.

**Architecture:** Four new TOC files (`SelfCare_TBC.toc`, `SelfCare_Wrath.toc`, `SelfCare_Cata.toc`, `SelfCare_Mists.toc`), each identical to `SelfCare_Vanilla.toc` except for `## Interface:`. Eight new tests in `spec/settings_spec.lua` (two per flavor). No Lua changes.

**Tech Stack:** Lua 5.1, busted (test framework), WoW TOC format

---

## File Map

| Action | File | Purpose |
|---|---|---|
| Modify | `spec/settings_spec.lua` | Hoist `extractFiles`, add 8 new tests (2 per flavor) |
| Create | `SelfCare_TBC.toc` | CurseForge BCC Anniversary flavor |
| Create | `SelfCare_Wrath.toc` | CurseForge WotLK Classic flavor |
| Create | `SelfCare_Cata.toc` | CurseForge Cataclysm Classic flavor |
| Create | `SelfCare_Mists.toc` | CurseForge MoP Classic flavor |

---

## Task 1: Create feature branch

**Files:** none

- [ ] **Step 1: Create and switch to feature branch**

```bash
git checkout -b feat/all-classic-flavors
```

Expected: `Switched to a new branch 'feat/all-classic-flavors'`

---

## Task 2: Write failing tests

**Files:**
- Modify: `spec/settings_spec.lua` (the `describe("TOC files", ...)` block, currently lines 72–96)

The current `describe("TOC files", ...)` block has `extractFiles` defined inline inside one `it()`. Hoist it to a shared local, add `#retail > 0` guard to the Vanilla file-list test, then add eight new `it()` blocks.

Replace the entire `describe("TOC files", ...)` block with:

```lua
    describe("TOC files", function()
        local function extractFiles(path)
            local files = {}
            for line in io.lines(path) do
                if not line:match("^##") and not line:match("^%s*$") then
                    table.insert(files, line:match("^%s*(.-)%s*$"))
                end
            end
            return files
        end

        it("SelfCare_Vanilla.toc exists and declares Classic Era interface", function()
            local f = io.open("SelfCare_Vanilla.toc", "r")
            assert.is_not_nil(f, "SelfCare_Vanilla.toc must exist")
            local content = f:read("*a")
            f:close()
            assert.truthy(content:find("## Interface: 11508"),
                "Must declare Interface: 11508 for Classic Era 1.15.8")
        end)

        it("SelfCare_Vanilla.toc lists the same source files as SelfCare.toc", function()
            local retail = extractFiles("SelfCare.toc")
            assert.is_true(#retail > 0, "SelfCare.toc must have source files")
            local classic = extractFiles("SelfCare_Vanilla.toc")
            assert.same(retail, classic)
        end)

        it("SelfCare_TBC.toc exists and declares TBC Classic interface", function()
            local f = io.open("SelfCare_TBC.toc", "r")
            assert.is_not_nil(f, "SelfCare_TBC.toc must exist")
            local content = f:read("*a")
            f:close()
            assert.truthy(content:find("## Interface: 20505"),
                "Must declare Interface: 20505 for TBC Classic 2.5.5")
        end)

        it("SelfCare_TBC.toc lists the same source files as SelfCare.toc", function()
            local retail = extractFiles("SelfCare.toc")
            assert.is_true(#retail > 0, "SelfCare.toc must have source files")
            local tbc = extractFiles("SelfCare_TBC.toc")
            assert.same(retail, tbc)
        end)

        it("SelfCare_Wrath.toc exists and declares WotLK Classic interface", function()
            local f = io.open("SelfCare_Wrath.toc", "r")
            assert.is_not_nil(f, "SelfCare_Wrath.toc must exist")
            local content = f:read("*a")
            f:close()
            assert.truthy(content:find("## Interface: 30403"),
                "Must declare Interface: 30403 for WotLK Classic 3.4.3")
        end)

        it("SelfCare_Wrath.toc lists the same source files as SelfCare.toc", function()
            local retail = extractFiles("SelfCare.toc")
            assert.is_true(#retail > 0, "SelfCare.toc must have source files")
            local wrath = extractFiles("SelfCare_Wrath.toc")
            assert.same(retail, wrath)
        end)

        it("SelfCare_Cata.toc exists and declares Cataclysm Classic interface", function()
            local f = io.open("SelfCare_Cata.toc", "r")
            assert.is_not_nil(f, "SelfCare_Cata.toc must exist")
            local content = f:read("*a")
            f:close()
            assert.truthy(content:find("## Interface: 40402"),
                "Must declare Interface: 40402 for Cataclysm Classic 4.4.2")
        end)

        it("SelfCare_Cata.toc lists the same source files as SelfCare.toc", function()
            local retail = extractFiles("SelfCare.toc")
            assert.is_true(#retail > 0, "SelfCare.toc must have source files")
            local cata = extractFiles("SelfCare_Cata.toc")
            assert.same(retail, cata)
        end)

        it("SelfCare_Mists.toc exists and declares MoP Classic interface", function()
            local f = io.open("SelfCare_Mists.toc", "r")
            assert.is_not_nil(f, "SelfCare_Mists.toc must exist")
            local content = f:read("*a")
            f:close()
            assert.truthy(content:find("## Interface: 50503"),
                "Must declare Interface: 50503 for MoP Classic 5.5.3")
        end)

        it("SelfCare_Mists.toc lists the same source files as SelfCare.toc", function()
            local retail = extractFiles("SelfCare.toc")
            assert.is_true(#retail > 0, "SelfCare.toc must have source files")
            local mists = extractFiles("SelfCare_Mists.toc")
            assert.same(retail, mists)
        end)
    end)
```

- [ ] **Step 2: Run tests — expect 8 failures**

```bash
bash scripts/run-tests.sh --tap
```

Expected: 8 new failures like `SelfCare_TBC.toc must exist` etc. All pre-existing tests still pass.

---

## Task 3: Create the four TOC files

**Files:**
- Create: `SelfCare_TBC.toc`
- Create: `SelfCare_Wrath.toc`
- Create: `SelfCare_Cata.toc`
- Create: `SelfCare_Mists.toc`

Each is identical to `SelfCare_Vanilla.toc` with only `## Interface:` changed.

- [ ] **Step 1: Create `SelfCare_TBC.toc`**

```
## Interface: 20505
## Title: SelfCare
## Notes: Reminds you to hydrate, check your posture, and take breaks.
## Author: ValentinClaes
## Version: 1.0.0
## SavedVariables: SelfCareDB
## X-Curse-Project-ID: 1478575

src/Core.lua
src/Notifications.lua
src/Timers.lua
src/Settings.lua
src/Init.lua
```

- [ ] **Step 2: Create `SelfCare_Wrath.toc`**

Same as above with `## Interface: 30403`.

- [ ] **Step 3: Create `SelfCare_Cata.toc`**

Same as above with `## Interface: 40402`.

- [ ] **Step 4: Create `SelfCare_Mists.toc`**

Same as above with `## Interface: 50503`.

- [ ] **Step 5: Run tests — all should pass**

```bash
bash scripts/run-tests.sh --tap
```

Expected: all tests pass, total count increases by 8 (from 112 to 120).

---

## Task 4: Commit and push

- [ ] **Step 1: Commit with /quick-commit**

Stage and commit: `spec/settings_spec.lua`, `SelfCare_TBC.toc`, `SelfCare_Wrath.toc`, `SelfCare_Cata.toc`, `SelfCare_Mists.toc`, `docs/superpowers/specs/2026-03-25-all-classic-flavors-design.md`, `docs/superpowers/plans/2026-03-25-all-classic-flavors.md`

Use `/quick-commit`.

- [ ] **Step 2: Push branch and open PR**

```bash
git push -u origin feat/all-classic-flavors
```

Then open a PR targeting `master`.
