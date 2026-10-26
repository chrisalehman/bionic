# How version 14 brought plans in flight forward

Research ticket [chrisalehman/bionic#46](https://github.com/chrisalehman/bionic/issues/46), a
wayfinder for the 1.30.0 charter. Written 2026-10-26 on branch `research/version-14-migration`.

**Question.** The charter (`.bionic/docs/ideas/bionic-1.30.0-charter.md:166-167`) says that when
`canonical_sdlc_version` moves to 15, "runs in flight are brought forward, not exempted, as 14
was". How did the 13 → 14 move do that, by what mechanism, and what pins the version today?

**Inputs.** This worktree at `050fa567e` (main, 1.29.0). `CHANGELOG.md`, `hooks/`,
`payload/scripts/lib/`, `skills/canonical-sdlc/`, `tests/`, and git history back to the first
version tag. The live plans under `.bionic/docs/plans/` were read read-only. Absence claims use
`/usr/bin/grep`. Two refusals were driven against the real hooks (§5).

## Summary

**The 13 → 14 move brought a plan in flight forward by one hand edit of its frontmatter line,
`canonical_sdlc_version: 13` → `14`, forced by both gates refusing the plan at any other value.
There was no verb, no hook arm and no script that rewrote a plan; the refusal was the mechanism,
and the one line of guidance was the skill's sentence "A run that predates it is brought forward
to 14, not exempted."** That is what "as 14 was" refers to.

- **Release.** Commit `7e052690c` (2026-08-19, epic-17 wave-05, "the close-out contract at v14")
  bumped `SUPPORTED_SDLC_VERSION` 13 → 14 in both hooks and every rendering in the same commit.
  It shipped in bionic 1.3.2 (tag `v1.3.2`, 2026-08-30, the repository's first version tag).
  **The CHANGELOG has no entry for it**: the file begins at 1.8.4 (2026-09-20, `CHANGELOG.md:6129`)
  and never names 1.3.2. The four "Upgrade, for a plan already in flight" sections the ticket
  names (1.11.0 to 1.14.0) all say `canonical_sdlc_version` **stays 14**; none is the bump. They
  are the pattern for migrations *within* 14, and they show the same shape: a hand edit (or no
  edit) named in one line, enforced by a refusal on the plan's next write or commit.
- **What a 13 plan had to do.** Change the one frontmatter digit. The 14 contract changed only
  Step 9's evidence shape (`delivered:` always; `deployed:`/`verified:`/`monitored:` only when
  `deploy_target` names a live surface) and made `deploy_target` default to `n/a`; a plan below
  Step 9 owed nothing else, and the commit's own message says "v13 plans now block, no
  grandfathering, no version ladder" (operational-rules bullet added in `7e052690c`).
- **Pattern across bumps.** 11 → 12 (`ef1824369`, 2026-07-26) *deleted* the version ladder that
  had grandfathered older plans ("ten versions in three months, none ever removed"; ~360 lines
  protecting two live pre-v11 plans). From then on each bump, 12 → 13 (`9a501e986`, 2026-08-02)
  and 13 → 14 (`7e052690c`), was "one supported version, no grandfathering": the plan in flight
  edits its digit. Before v12, bumps *did* exempt runs in flight, by keeping an arm per version.
- **Where the version is pinned today.** One constant in each gate: `hooks/canonical-sdlc-governing-skill.sh:53`
  (write side) and `payload/scripts/lib/walls.sh:2433` (commit side, run by `hooks/bash-walls.sh`).
  Renderings: `skills/canonical-sdlc/SKILL.md:150,152`, `operational-rules.md:23`, the two SVGs,
  the template `agents-src/templates/skills/canonical-sdlc/SKILL.md.tmpl:150,152`. The agreement
  pin is `tests/cross-gate-agreement.prelude.sh:987-992` (§V, with a mutation arm). The only
  *writer* is Step 0, by hand: no script stamps the key (§4).
- **What a refusal says.** Write side: `bionic: write refused — this artifact declares an
  unsupported version (set the supported version)`, detail `declares canonical_sdlc_version:
  '13'` … `Fix: set 'canonical_sdlc_version: 14' — the only supported version.` Commit side:
  the same with `commit refused — this plan declares an unsupported sdlc version`. Both exit 2.
  Captured live in §5.
- **Two gaps worth knowing before 15.** (a) The commit-side version refusal has had **no test
  since 2026-10-19**: commit `5947e68af` ("every test suite capped at 1000 lines") deleted the
  `bad_version` loop from `tests/canonical-sdlc-evidence-gate.test.sh` (old lines 1694-1698) and
  re-homed it nowhere; `walls.sh:2432` still cites that suite as its wall. The write-side loop
  survives at `tests/canonical-sdlc-governing-skill.test.sh:415-424`. (b) Since 1.8.4 a second,
  *body-level* bring-forward exists: `plan_bring_forward` (`walls.sh:894`) lists every pre-14
  shape fault of a plan whose digit already says 14. It is a predicate that prints and never
  rewrites; it fires only on wave/epic plans at `rigor: double`, `multi_agent: true`.

## 1. The release that moved 13 → 14

| fact | evidence |
|---|---|
| The bump commit | `7e052690c4f1a19e5046cfc0e9b561e0b48de8e1`, 2026-08-19 14:35 -0700, "feat(epic-17-w5 4/2): the close-out contract at v14 — delivered always, the deploy trio only when a target is named". Message: "SUPPORTED_SDLC_VERSION 13 -> 14 in both hooks, with every rendering surface moving in the same commit … RED: … 285 arms across 8 suites on the version flip." |
| Files it touched | `hooks/canonical-sdlc-evidence-gate.sh`, `hooks/canonical-sdlc-governing-skill.sh`, `skills/canonical-sdlc/SKILL.md`, `operational-rules.md`, `diagrams/hook-chain.svg`, `diagrams/lifecycle.svg`, 15 test files. **No script, no verb, no migration tool, no CHANGELOG.** |
| The hook diff | `canonical-sdlc-governing-skill.sh`: comment example `canonical_sdlc_version: 13` → `14`; missing-frontmatter hint `13` → `14`; `SUPPORTED_SDLC_VERSION=13` → `14` above `if [ "$SDLC_VERSION" != "$SUPPORTED_SDLC_VERSION" ]; then echo "BLOCKED: …"`. |
| The skill diff | `SKILL.md`: the frontmatter paragraph's `canonical_sdlc_version: 13` → `14`; Step 0 flag inference: `deploy_target` "**defaults to `n/a` and is never inferred**"; Step 9: "**Where the run ends.** Every close-out records `delivered:`"; evidence-shapes row 9: `delivered:` always; plus `deployed:`, `verified:`, `monitored:` exactly when `deploy_target` names a live surface. |
| The rules diff | `operational-rules.md`: new bullet "**v14 is the ONLY supported version (2026-08-19, epic-17 wave-05 — the close-out contract).** All backward compatibility is deleted again: v13 plans now block, no grandfathering, no version ladder. Both hooks check `SUPPORTED_SDLC_VERSION=14`. **One contract change over v13, and it is Step 9's evidence shape.** … Everything else in the contract is IDENTICAL to v13's … no new frontmatter fields." The frontmatter example `13` → `14`. |
| The supported-version sentence | Left stale at "13" by `7e052690c`; corrected to "**14 is the only supported version.** … A run that predates it is brought forward to 14, not exempted." by `3d3a3de07` (2026-08-27, "version-prose rot"). The sentence itself was born at 12 → 13: `9f4b10fd9` (2026-08-02) changed "brought forward to 12" to "brought forward to 13". Today: `skills/canonical-sdlc/SKILL.md:152`, template `:152`. |
| Release carrying it | First tag containing `7e052690c` is `v1.3.2` (2026-08-30, "bionic 1.3.2 — ten dogfood defects from epic-20 W1"). `git tag --list 'v*' \| sort -V` begins at `v1.3.2`. |
| CHANGELOG | Begins at `## 1.8.4 — 2026-09-20` (`CHANGELOG.md:6129`); `/usr/bin/grep -n "1\.3\.2" CHANGELOG.md` is empty. Every version line in the file reads "`canonical_sdlc_version` stays 14" (`:29, :315, :646, :889, :1238, :1441, :1846, :2110, :2419, :2696, :2859, :3072, :3268, :3576, :3857, :4091, :4236, :4463, :4991, :5298`). The release rule at `CHANGELOG.md:7`: "**MAJOR** for a `canonical_sdlc_version` bump or an artifact a user must migrate." |

## 2. What the upgrade did to a 13 plan

**One hand edit, forced by refusal.** The evidence is negative and positive:

- Nothing rewrote the plan. The bump commit's file list (§1) has no script. `/usr/bin/grep -rn
  "canonical_sdlc_version" payload/scripts` hits only `walls.sh` (readers, §4); no verb under
  `hooks/poker/` or `payload/scripts/` writes the key. `plan_bring_forward` did not exist until
  2026-09-19 (§6), and even it never writes.
- The refusal names the edit. Both gates print `Fix: set 'canonical_sdlc_version: 14' — the only
  supported version.` (`hooks/canonical-sdlc-governing-skill.sh:1025`, `walls.sh:2438`); the hint
  interpolates the constant rather than a literal (`516b87200`, 2026-09-06, D-2).
- The contract asked nothing more of a plan below Step 9. `7e052690c`'s rules bullet: "no new
  frontmatter fields"; the change is Step 9's evidence shape and a Step 0 default. A plan's
  existing `deploy_target: none` kept meaning "no trio owed" (the trio is owed "exactly when
  `deploy_target` names a live surface"); a plan reaching Step 9 after the bump wrote
  `delivered:` in the new shape because the gate's row-9 arm asked for it.
- The doctrine sentence: "A run that predates it is brought forward to 14, not exempted."
  (`SKILL.md:152`). The plan of the wave that made the bump was itself in flight at 13
  ("Judgment calls logged as plan assumptions A13-A18"); its commits passed the gate after the
  flip, which the gate only allows at 14. That plan is not in the live tree (only `epic-23-*` and
  `epic-99-t3` under `.bionic/docs/plans/`), so its edit cannot be shown; the mechanism can.

**Live state.** Read-only: all 62 `*.plan.md` under `.bionic/docs/plans/` carry
`canonical_sdlc_version: 14`; none carries another value (`/usr/bin/grep -rn --include='*.plan.md'
"canonical_sdlc_version:" … | grep -v ": 14$'` is empty apart from prose in two plan bodies).

## 3. The pattern, from every bump

| bump | commit, date | runs in flight | words |
|---|---|---|---|
| ≤ 11 (ladder) | before `ef1824369` | **exempted**: an arm per version, "never retrofit onto an older plan" | `ef1824369` message: "20 conditional sites, ten versions in three months, none ever removed … Roughly 360 lines of version machinery were protecting two live pre-v11 plans. Eight of the ten supported versions guarded nothing." A fall-through `exit 0` "let a v12 plan commit entirely ungated." |
| 11 → 12 | `ef1824369`, 2026-07-26 | brought forward: ladder deleted, "Legacy-version tests, fixtures and helpers deleted rather than inverted" | "exactly one supported version. Anything else blocks at both hooks with a message naming the value found". Rules bullet (later text): "v12 … All backward compatibility was deleted: no grandfathering, no version ladder, no per-version shape tables." |
| 12 → 13 | `9a501e986`, 2026-08-02 | brought forward | "v12 retired to historical record and no grandfathering. Moved every rendering site: both hooks' pin + comments, tests/scripts.test.sh's pin-sync assertions, both hook test suites' fixtures … SKILL.md's frontmatter contract line, operational-rules.md's frontmatter example plus a new v13 history entry, and the hook-chain diagram's three version callouts." Same day, `9f4b10fd9` wrote "brought forward to 13, not exempted". |
| 13 → 14 | `7e052690c`, 2026-08-19 | brought forward | "v13 plans now block, no grandfathering, no version ladder" (§1). |

**Within 14, the CHANGELOG's four "Upgrade, for a plan already in flight" sections** (the ones the
ticket names) keep the same shape, a hand edit or no edit named in one line, enforced by a refusal:

| entry | line | what a plan in flight does |
|---|---|---|
| 1.14.0 — 2026-10-09 | `CHANGELOG.md:4226`, section `:4386` | **The only in-14 migration that edits a plan.** `:4236-4238`: "The migration is one edit per plan, below. `canonical_sdlc_version` stays 14. A plan open at upgrade is refused on its next write until its `rigor:` line is edited." `:4240`: `low`/`tested` → `single`; `medium`/`high`/`peer-reviewed`/`audited` → `double`; `bionic:reviewer` retired. `:4386-4396`: edit `rigor:` and the ledger rigor cells; add `regression-runs: 0` before `regression-runs --write`; a brief for `bionic:reviewer` names `bionic:critic`. The release calls itself minor against the repository's own MAJOR rule "on the maintainer's ruling" (`:4234-4235`). This is the line `payload/scripts/lib/run.sh:1061-1062` means: "a word before 1.14.0 is refused like any other bad value, and a project migrates its files by the CHANGELOG's one line." |
| 1.13.0 — 2026-10-07 | `:4456`, section `:4752` | No edit. `:4463-4464`: "A run open at upgrade continues on its 1.12.0 plan with no edit." `:4752-4760`: `ready` ignores stamps; a row dispatched under 1.12.0 has no `lands_on=` and is landed by hand; the next writer brief needs a `Lands-on:` line. Fixture: `tests/fixtures/upgrade-1.12.0/install.sh` plants "a run open at upgrade" (wave-28 T21), its plan at `canonical_sdlc_version: 14`. |
| 1.12.0 — 2026-10-06 | `:4970`, section `:5190` | No edit until Step 6. `:5192-5196`: "An open plan needs no edit until its Step 6. There it meets the readings … Give the plan a `base-sha:` that is a commit if it has none, or its first reading of each question is refused." |
| 1.11.0 — 2026-10-04 | `:5290`, section `:5461` | One edit past Step 4. `:5296-5298`: "asks one upgrade step of a plan already past Step 4". `:5463-5465`: add `head: <sha>` to the Step-5 evidence before the next commit judged against it. |
| 1.8.8 — 2026-10-01 | `:5977-5979` | "Migration for plans in flight: from 1.8.8 a task row's agent cell is the roster name … and a row still carrying a role is refused by the gate as naming no launched agent." |

So the evidence-backed statement of "as 14 was": **the bump names the edit in one line and both
gates refuse the plan until the edit is made; nothing rewrites a plan for the user, and nothing
carries an old plan on an old arm.** The spike's option 2 for 15 (`.bionic/docs/spikes/spike-kernel-map-20261026.md:317`,
"`migrate <plan>` … runs at the next tick of a run in flight, so nothing is exempted, as 14 was
not") would be the first bump with a rewriting verb; 14 had none.

## 4. Every reader and writer of `canonical_sdlc_version`

`/usr/bin/grep -rn "canonical_sdlc_version\|SUPPORTED_SDLC_VERSION" --exclude=CHANGELOG.md --exclude-dir=.git .`,
plus `/usr/bin/grep -Rn` (symlink-following) over `skills/canonical-sdlc/steps`, `payload/context`,
`payload/commands`, `agents-src`. Tests are listed by role only.

**Writers.** None in code. The key is written by Step 0 by hand: `hooks/canonical-sdlc-governing-skill.sh:1005`
("`canonical_sdlc_version`, which Step 0 stamps on every canonical-sdlc artifact"), `.claude/rules/hook-authoring.md:144-145`
("canonical-sdlc uses `canonical_sdlc_version:`, set by Step 0"), and the frontmatter contract
`skills/canonical-sdlc/SKILL.md:150`. No step file under `skills/canonical-sdlc/steps/` names the
key; no verb under `hooks/poker/` or `payload/scripts/` writes it. Fixture writers in tests
(`tests/lib/plan-fixture.sh`, `tests/canonical-sdlc-governing-skill.test.sh:241` `build_plan`,
`tests/canonical-sdlc-evidence-gate.prelude.sh:433,458,568,619,659`, `tests/bash-walls.prelude.sh:36,191`,
`tests/fixtures/upgrade-1.12.0/wave-x.plan.md:8`) write `14` literally.

**Readers that refuse.**

| site | what it does |
|---|---|
| `hooks/canonical-sdlc-governing-skill.sh:53` | `SUPPORTED_SDLC_VERSION=14`, "ONE supported version … bound here, before the first place that quotes it" (`[WALL: tests/canonical-sdlc-governing-skill.test.sh]`). |
| `…governing-skill.sh:928` | discriminator: a file under the docs root is a canonical artifact when its frontmatter carries `canonical_sdlc_version:` or `governing-skill: canonical-sdlc` (`:921-928`, `:1001-1006`, `:1835`). |
| `…governing-skill.sh:976` | the missing-frontmatter hint prints `canonical_sdlc_version: ${SUPPORTED_SDLC_VERSION}`. |
| `…governing-skill.sh:1016-1026` | `SDLC_VERSION=$(yaml_get canonical_sdlc_version)`; `!=` the constant → `refuse exit2 write "this artifact declares an unsupported version" "set the supported version"` with detail naming the value found, the path, and `Fix: set 'canonical_sdlc_version: 14'`. |
| `…governing-skill.sh:1437-1460` | the body-level arm: `plan_bring_forward` over a temp copy of the posted content; fires → `refuse exit2 write "this plan's body is not at contract version 14" "bring the plan forward"`. |
| `payload/scripts/lib/walls.sh:2433` | `SUPPORTED_SDLC_VERSION=14`, "Symmetric with the governing-skill hook" (`[WALL: tests/canonical-sdlc-evidence-gate.test.sh]`, see §7a). Runs inside `wall_evidence_gate` behind `hooks/bash-walls.sh` (`88bbcd8d4`, 2026-09-12 folded the evidence gate into one PreToolUse\|Bash process). |
| `walls.sh:2421` | `SDLC_VERSION=$(frontmatter_get canonical_sdlc_version)`. |
| `walls.sh:2435-2439` | `!=` → `refuse exit2 commit "this plan declares an unsupported sdlc version" "set the supported version"`; detail `canonical-sdlc evidence-gate: plan declares canonical_sdlc_version: '<v>'. Plan: <path> Fix: set 'canonical_sdlc_version: 14' — the only supported version.` Inventory row: `tests/fixtures/refusal-inventory.md:34`. |
| `walls.sh:2307, :2342` | the misplaced-plan arm: a `*.plan.md` outside the docs root whose *leading* frontmatter declares `canonical_sdlc_version:` is "a plan sits outside the docs root". |
| `walls.sh:3758-3768` | the body-level arm at commit: `plan_bring_forward "$PLAN"` fires → `refuse exit2 commit "this plan's body is not at contract version 14" "bring the plan forward"`. |

**Readers that render.** `skills/canonical-sdlc/SKILL.md:150` (contract line) and `:152`
("14 is the only supported version … brought forward to 14, not exempted"); the template
`agents-src/templates/skills/canonical-sdlc/SKILL.md.tmpl:150,152`; `SKILL.md:225` (what the
governing-skill hook blocks); `operational-rules.md:23` (frontmatter example), `:129` (the
one-definition table: "version pin value | `payload/scripts/lib/walls.sh`'s `SUPPORTED_SDLC_VERSION` …
`tests/cross-gate-agreement-1.test.sh` §V pins the renderings against the gate's value, with a
mutation arm"), `:137`; `diagrams/hook-chain.svg:184,207,231` (three `class="version-pin"` chips,
`canonical_sdlc_version == 14` ×2, `: 14 is the only value either hook accepts`), `diagrams/lifecycle.svg:9`
(title rendering); `.claude/rules/hook-authoring.md:144-150` (states the mechanism and, by two
corrections, deliberately no digit); `payload/scripts/lib/run.sh:1061-1062` (the rigor-word rule,
"a project migrates its files by the CHANGELOG's one line"); `docs/designs/*.spec.md:14`,
`docs/requirements/*.requirements.md:14`, `docs/adrs/adr-0{56,62,63,64,66,67,68,69,70,71,72,73,74}-*.md:9`
(artifacts carrying `14`).

**The pin.** `tests/cross-gate-agreement.prelude.sh:987-992` §V: `v_hook_val` reads
`^SUPPORTED_SDLC_VERSION=` out of the gate as origin and holds the governing-skill hook and the
SVG chips to it, with a mutation arm and a control. Record of how it got there (wave-08
plugin-only, R6): `.bionic/docs/record/wave-01-plugin-only/s03-version-constant.md` (read-only):
"planted a Write declaring `canonical_sdlc_version: 13` against the real hook; the Fix line names
the live value (14) and never echoes the doctored 13 back". The operational-rules version-history
bullets (v14, v13, v12 …) were dropped at `1b97a2d38` (2026-10-10, T14 pass 1, "the sections
nothing cites"), so today's prose history of the bump is this note and git.

## 5. What a refusal says, driven live

Both runs used the suites' own fixture builders against the hooks in this worktree
(`hooks/canonical-sdlc-governing-skill.sh` and `hooks/bash-walls.sh` → `walls.sh`), in sandbox
projects, engaged, with a plan at `canonical_sdlc_version: 13`. Scripts were in the scratchpad;
nothing was written to the repository.

Write side (`tests/canonical-sdlc-governing-skill.test.sh` prelude, `run_write … "$(build_plan version=13)"`):

```
exit=2
bionic: write refused — this artifact declares an unsupported version (set the supported version)

canonical-sdlc artifact 'v13.plan.md' declares canonical_sdlc_version: '13'.
Path: /private/var/folders/…/.bionic/docs/plans/epic-01-demo/v13.plan.md
Fix: set 'canonical_sdlc_version: 14' — the only supported version.
```

Commit side (`tests/canonical-sdlc-evidence-gate.prelude.sh`, `write_plan` at 13, `run_hook "$h" 'git commit -m "x"'`):

```
exit=2
bionic: commit refused — this plan declares an unsupported sdlc version (set the supported version)

canonical-sdlc evidence-gate: plan declares canonical_sdlc_version: '13'.
Plan: /private/var/folders/…/.bionic/docs/plans/active.md
Fix: set 'canonical_sdlc_version: 14' — the only supported version.
```

The write-side loop in the suite drives `13 12 11 9 2 99 "" banana 12.0 v12` and an absent line
(`tests/canonical-sdlc-governing-skill.test.sh:415-426`); every value exits 2 and names the value
found. The same loop existed on the commit side from `ef1824369` until `5947e68af` (§7a).

## 6. The body-level bring-forward (after 14, inside 14)

Not part of the 13 → 14 move, but it is what "bring the plan forward" means in today's refusals:

- `payload/scripts/lib/walls.sh:823-1010` `plan_bring_forward <plan>`: "every version-14 shape
  fault, in one pass" (spec D8; REQ-3, AC-3.1). It "VALIDATES THE TARGET SHAPE, NOT THE CURRENT
  ONE, and it is a PREDICATE: it prints, it never refuses" (`:834-836`). Trigger, both together
  (`:838-843`): the `## Tasks` table is missing a required column, and at least one version-14
  key the plan owes at its `current:` step is absent (`requirements:` from step 2, `approved-by:`
  and `fails-when:` from step 4). Lane guard (`:848-852`): wave/epic, `rigor: double`,
  `multi_agent: true`; below that it is silent. It derives the step from the body's `current:`
  (`:860-872`, wave-16 T25), normalizes CRLF and a BOM first (`:915-935`).
- Landed `f7ec7f6bf` (2026-09-19, "one bring-forward refusal over the version-14 target shape")
  and `76494c5c0` (2026-09-20, CRLF); recorded in `CHANGELOG.md:6137` (1.8.4 REQ-5, "Plan-authoring
  refusals name the cell and the shape") and `:6143` (REQ-11, "A BOM-prefixed plan gets the same
  loud fault list as its LF twin"); first version tag containing the first commit is `v1.8.3`.
- Callers: `hooks/canonical-sdlc-governing-skill.sh:1441-1460` at Write/Edit and `walls.sh:3763-3768`
  at commit, "render the identical list". The refusal: "this plan's body is not at contract
  version 14 (bring the plan forward)", detail "repair every line above in one pass — each is a
  separate arm that would otherwise refuse the next commit in turn".

## 7. Observations for the 15 planner

a. **The commit-side version refusal is unpinned.** `5947e68af` (2026-10-19, "T43: every test
   suite capped at 1000 lines") removed `for bad_version in 13 12 11 9 2 99 "" banana 12.0 v12`
   from `tests/canonical-sdlc-evidence-gate.test.sh` (old `:1694-1698`); `/usr/bin/grep -rn
   bad_version tests/` finds only the governing-skill suite, and `/usr/bin/grep -rln "unsupported
   sdlc"` finds only the refusal inventory. `walls.sh:2432` still reads `[WALL:
   tests/canonical-sdlc-evidence-gate.test.sh]`. §V pins the *constant's value* across surfaces,
   not that the commit gate refuses on it. The live run in §5 shows the arm works today.
b. **No release text records the bump.** A reader of `CHANGELOG.md` sees only "stays 14" twenty
   times; the move itself is in `7e052690c`'s message, `operational-rules.md`'s deleted v14
   bullet, and `SKILL.md:152`. The charter's rule for 15 (`CHANGELOG.md:7`, MAJOR) was written
   after 14, in a file that did not exist at 14.
c. **"As 14 was" means refusal plus one hand edit, not a migration verb.** If 15 ships `migrate`
   (spike `:317`), it is the first bump with a rewriter; the thing 14 pins down is only the
   negative half: no arm for the old version, no `exit 0` fall-through (`ef1824369`), the refusal
   names the value found and the fix, and the constant lives in one place per gate with §V over
   the renderings.
d. **The hand edit has precedent at both grains.** Frontmatter digit (every bump since v12);
   a frontmatter word plus ledger cells (1.14.0 `rigor:`, `CHANGELOG.md:4386-4390`); a body line
   (1.11.0 `head:`, `:5463-5465`); or none (1.13.0, 1.12.0 until Step 6). In every case the
   enforcement is "refused on its next write/commit until edited", and the words are in the
   release entry's "Upgrade, for a plan already in flight" section.

## Method

`gh issue view 46`; `/usr/bin/grep -n` over `CHANGELOG.md` for the version lines and the four
upgrade sections; `git log -S` / `-G'SUPPORTED_SDLC_VERSION='` over `hooks/` to list every bump
(`ef1824369`, `9a501e986`, `7e052690c`, `516b87200`, `88bbcd8d4`); `git show` of each bump and
of the sentence commits (`9f4b10fd9`, `3d3a3de07`); `git tag --contains` for the release;
`/usr/bin/grep -rn` and `-Rn` for readers and writers; the two refusal drives of §5; read-only
reads of `.bionic/docs/plans/`, the charter, the spike and the wave-08 S03 record.
