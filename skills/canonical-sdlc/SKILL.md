---
name: canonical-sdlc
description: Use when starting a large-scale development effort (new feature, architectural change, multi-day project) or when picking the skill for the current SDLC step. Routes to the canonical skill per step and gates every commit on the current step's evidence.
layer: governance
needs:
  - agent-skills:context-engineering
  - agent-skills:source-driven-development
  - agent-skills:documentation-and-adrs
  - agent-skills:idea-refine
  - agent-skills:spec-driven-development
  - agent-skills:incremental-implementation
  - browser-verify
  - agent-skills:browser-testing-with-devtools
  - agent-skills:code-review-and-quality
  - agent-skills:security-and-hardening
  - agent-skills:performance-optimization
  - agent-skills:git-workflow-and-versioning
  - agent-skills:shipping-and-launch
  - agent-skills:ci-cd-and-automation
  - agent-skills:frontend-ui-engineering
  - superpowers:systematic-debugging
  - superpowers:writing-plans
  - superpowers:executing-plans
  - superpowers:using-git-worktrees
  - superpowers:test-driven-development
  - superpowers:verification-before-completion
  - superpowers:finishing-a-development-branch
  - superpowers:dispatching-parallel-agents
  - shape
  - impeccable
  - polish
  - critique
  - audit
  - harden
  - normalize
loading: deferred
---

# Canonical SDLC

Governs non-trivial engineering work. Every run declares a triple — `<intent> · <rigor> · <scale>` — and walks the applicable steps, leaving evidence a hook can read.

**Only the `## Hooks` section names anything that blocks. Everything else here is judgment, and you own it.**

**Iron law.** No commit without evidence from the current step. The evidence gate reads the plan's `current:` and validates that step's evidence only — it never re-checks earlier steps, so a skipped step is caught by review, not by code.

## Load-time announcement

First user-facing action:

> **Canonical SDLC engaged — `<intent>` · `<rigor>` · `<scale>` (`<what that rigor buys>`).**

Triple not yet declared → say so and list the axes. Invoked as `help` → render the axis tables and stop.

## The triple

**intent** — what the deliverable is.

| Intent | Use when | Evidence delta |
|---|---|---|
| `build` | Capability that did not exist, or capability restored by ADDING machinery/interfaces/config (the machinery test). | RED→GREEN per slice. When the build IS a verification instrument, prove it CATCHES planted failures — a check that never fails is not proven to work. |
| `bugfix` | Restore intended behavior WITHIN the existing design. A repair, not new machinery. | The RED test is the failing repro. |
| `refactor` | Change structure, preserve behavior. Covers upgrades, migrations, removals/deprecations. | `behavior-preservation:` in the Step-5 block; migrations add `compat-matrix:`/`revert-plan:` (or `n/a: not a migration`). Log-only. |
| `tune` | Move a NAMED measurement toward a target. If you cannot name the measurement, it is not tune. | `baseline:`/`target:`/`re-measure:` in the Step-5 block, all three. Log-only. |
| `spike` | Timeboxed research. **Ships no code at any rigor.** | Writeup only at `<docs-root>/spikes/spike-<slug>-<YYYYMMDD>.md`. No plan file, no spec, no ADR, no commits to the integration branch. |
| `incident-response` | A live deployed surface — production or tooling — is broken for its users. The clock matters. | RCA, not ADR. Floors at `audited`. Monitoring-gap closure is part of Ship. |

**rigor** — how hard the evidence tries to lie. Cumulative.

| Rigor | What you get | What you skip |
|---|---|---|
| `tested` | TDD RED→GREEN; matrix discharged at each row's tier; tests floor `pass == total`; 5-axis self-review. | Both independent assurance roles. Self-review only. |
| `peer-reviewed` | + a separate spec, + the INDEPENDENT Step-5 verification auditor on the evidence. At `scale: task` a ledger row must be proof-shaped and, once `done`, name an `auditor` verdict. | The mandatory adversarial critic. |
| `audited` | + the INDEPENDENT Step-6 adversarial critic, per-step checkpoint commits, expanded stop-and-wake. At `scale: task` a `done` row also names a `critic` verdict; at `scale: wave` an audited multi-agent plan must carry a `## Tasks` section at all. | Nothing. |

**scale** — the decomposition unit.

| Scale | Steps | Artifacts | Branch |
|---|---|---|---|
| `task` | Full set, compressed. Several per session. | ONE session plan with a `## Tasks` ledger; no per-task plan or spec. | The session's branch. |
| `wave` | Full set (0–9). Default. | One wave spec + plan; slices inside Step 4. | Wave branch off the epic integration branch; merges back at Step 8. |
| `epic` | 0–3 only. | `epic.spec.md` + `epic.plan.md`; carves waves. Does NOT run 4–9. | Owns `epic/NN-<slug>`; merges to mainline once, at close. |

**Barred cells:** `bugfix × epic`, `spike × epic`, `incident-response × epic`. A barred triple means the intent or the scale is misjudged.

**Rigor floors.** Default is scale-keyed: at `task`, `bugfix`→tested and `build`/`refactor`/`tune`→peer-reviewed; at `wave` and above, `audited`. Effective rigor is the MAX of the default and four floors — intent (`incident-response` floors at `audited`, `spike` is CAPPED at `tested`), flag (security-touching or privacy/vulnerable-population work floors at `audited`), project (`rigor-floor:` in `.bionic/config.yaml`), epic (`rigor-floor:` in epic frontmatter). Floors only push UP. Provisional at Step 0, locked at Step 3. Upgrades are free; downgrades go through the Waiver Protocol. Nothing enforces the floors — the only check that reads them is log-only.

Do not carve a sensitive concern into a tiny unflagged wave to dodge a floor. The wave that owns the integration point carries the flag floor.

## Artifact layout

```
<docs-root>/specs/epic-NN-<slug>/{epic.spec.md, wave-NN-<slug>.spec.md}
<docs-root>/plans/epic-NN-<slug>/{epic.plan.md, wave-NN-<slug>.plan.md}
<docs-root>/adrs/epic-NN-<slug>/adr-NNN-<slug>.md
<docs-root>/incidents/NNNN-<slug>/{spec.md, plan.md, rca.md}
<docs-root>/spikes/spike-<slug>-<YYYYMMDD>.md
.bionic/tmp/                      # ephemera only, gitignored, wiped at Step 8
```

Every artifact carries frontmatter with `governing-skill:`, `sdlc-step:`, `intent:`/`rigor:`/`scale:`, `canonical_sdlc_version: 12`, the 5 discriminator flags, the 2 opt-in flags, and `model_plan:`. A missing one blocks the write. Artifacts never declare `mode:`.

**12 is the only supported version.** Any other value — an older number, an empty value, a typo — blocks at both hooks. There is one contract; an artifact either meets it or does not write. A run that predates it is brought forward to 12, not exempted.

## Steps

| Step | Governing skill | Gate |
|---|---|---|
| 0 Configure | `canonical-sdlc` | Frontmatter complete, matrix derived, user confirmed, task list created |
| 1 Ideate | `agent-skills:idea-refine` | Refined idea + explicit "Not Doing" + alternatives lens cites prior art |
| 2 Spec | `agent-skills:spec-driven-development` | Every requirement has an acceptance criterion |
| 3 Plan | `superpowers:writing-plans` | No placeholders; `integration-branch:` present; matrix locked; slices tagged; user approved |
| 4 Implement | `agent-skills:incremental-implementation` | Every slice RED before GREEN; assumptions logged |
| 5 Verify | `superpowers:verification-before-completion` | Tests floor green; every matrix row discharged at tier or waived; auditor CONFIRMED |
| 6 Review | `agent-skills:code-review-and-quality` | Every axis has a verdict; independent critic attached |
| 7 Document | `agent-skills:documentation-and-adrs` | Every decision at medium significance or above is recorded |
| 8 Integrate | `superpowers:finishing-a-development-branch` | Wave reachable from the integration branch; worktree removed; tmp wiped |
| 9 Ship | `agent-skills:shipping-and-launch` | Checklist + rollback; `continuation.md` written |

Committing is a cross-cutting rhythm (~once per step), not a numbered step. Update `## SDLC State` **before staging** — the gate reads the file, not the diff. Do not add a `commit:` field; the SHA lives in git.

**Engagement:** Step 1 is interactive Q&A and is never skipped. Step 2 is semi-interactive. Step 3 ends at one approval checkpoint. Steps 4–9 are unattended within the stop-and-wake rules.

**Per-intent deltas.** `bugfix`: Step 4's failing test is the repro. `refactor`: the Step-2 spec is "behavior preserved"; a new acceptance criterion means reclassify as `build`. `tune`: Step 1 routes to the domain skill (`impeccable` for UX, `security-and-hardening`, `performance-optimization`) and Step 5 is the baseline→target→re-measure loop. `spike`: no plan file at all. `incident-response`: Step 1 compresses to triage, and triage asks first whether service can be restored NOW — if a revert restores it, revert and verify before debugging anything; Step 7 is an RCA (summary, timeline, root cause, contributing factors, the fix, prevention with commit links, monitoring-gap analysis); Step 9 is deploy with rollback → monitor ≥1 cycle → close the monitoring gap or prove there is none.

`scale: epic` short-circuits any intent after Step 3.

### Step 0 — Configure

1. **Pre-flight.** `.bionic/` exists; `docs-root:` read from `.bionic/config.yaml` (default `.bionic/docs`) with `{specs,plans,adrs,incidents}/` present; `mkdir -p .bionic/tmp/`; both hooks installed and executable (if not, warn and record in `## Assumptions`).
2. **Classify the triple silently.** Infer from the request's verbs and named artifacts. Do NOT interrogate. Interview by exception only, 1–3 questions, on exactly three conditions: a genuine intent collision the classification rules do not resolve (the standing gray zones are **mechanism-swap** and **reference-content**); a suspected but unconfirmed security/privacy surface; or a scale that could be one session or several.
3. **Infer the flags.** `language` from repo files; `surface_type`/`has_ui` from the request; `multi_agent` defaults **true** (infer `false` only when there is genuinely nothing to offload — never key it off an installed plugin catalog, which silently disables the dispatched-task ledger guard); `deploy_target` from deploy signals; `cleanup_on_finish` true; `use_worktree` false; `integration_branch` from the epic plan, else the current mainline, else `main` — print it as `unknown` rather than dropping it; `model_plan` from `multi_agent` and the detected session model.
4. **Derive the Verification Matrix.** One row per acceptance criterion. Tier defaults: user-visible behavior → **T3**; engine-divergent → **T2 both engines** plus **T3** for the user-visible AC; pure substrate with no runtime surface → **T1/T2** with a one-line justification; perceptual fidelity → **T3**, T4 available; docs → **T0/none**.
5. **Present the confirmation display in full, in the layout below.** Every section, every flag, every inference rationale, every matrix row, the `integration-branch:` line. Never elide, sample, summarize, defer, or restate it as prose — the user is approving exactly what they can see, and an abbreviated display invalidates the confirmation. Print every matrix row even past 12 ACs; a matrix is precisely what must not be sampled. An unknown value prints as `unknown` rather than dropping its line.

```
═══ Plan Configuration — confirm before Step 1 ═══
environment:
  bionic-root:  <abs path>/.bionic                   [verified | MISSING]
  docs-root:    .bionic/docs                         [default | from config.yaml]
  bionic-tmp:   <abs path>/.bionic/tmp               [ready]
  hooks:        evidence-gate, governing-skill       [installed+executable | <what is wrong>]

slug: <wave-NN-slug | epic-NN-slug | incident-NNNN-slug>

Triple:                          [the run's shaping decision]
  intent:  <value>               [inferred: <rationale — cite the machinery test for build/bugfix>]
  rigor:   <value>               [inferred: <rationale — name the binding floor>]
  scale:   <value>               [inferred: <rationale — why not the neighbouring scales>]

  barred-cell check: <cell> is barred; <this cell> PERMITTED
  floor derivation:  scale default <v> · intent floor <v> · flag floor <v> · project floor <v>
                     · epic floor <v> → effective <v> = MAX

integration-branch: <name>       [<source: epic plan | current mainline | main> — Step 8 merges here]

Discriminator flags:
  surface_type:    <value>      [inferred: <evidence>]
  language:        <value>      [inferred: <evidence>]
  has_ui:          <value>      [inferred: <evidence>]
  multi_agent:     <value>      [inferred: <evidence>]
  deploy_target:   <value>      [inferred: <evidence>]

Opt-in flags:
  cleanup_on_finish: <value>    [<consequence at Step 8>]
  use_worktree:      <value>    [<why isolation is or is not needed>]

Model plan:                      [multi_agent=<value> → <tiered dispatch | single-thread>]
  orchestrator:       <detected session model>   [main thread, fixed all wave]
  implementor:        <model>    [standard slices]
  senior-implementor: <model>    [complex slices, root-cause debugging]
  researcher:         <model>    [exploration]
  test-runner:        <model>    [mechanical + test execution]
  auditor:            <model>    [Step 5 — fresh, independent, never the implementer]
  critic:             <model>    [Step 6 — fresh, independent, never the author]

Verification Matrix:            [locked at Step 3 approval — every row shown, never sampled]
  stack-health: <PENDING — taken at Step 5 | snapshot | n/a: reason>
  | AC   | tier | status  | evidence | auditor |
  | AC-1 | <T>  | pending | see AC-1 |         |  [<tier rationale> — <criterion in one line>]
  | AC-2 | <T>  | pending | see AC-2 |         |  [<tier rationale> — <criterion in one line>]

  live-tier count: <n> of <total> rows require T3
  at-risk rows:    <AC-id (why it may end up blocked)> | none
  slices carrying NO ROW: <slice + why it produces a determination, not behaviour> | none

Reply "confirm" to accept, or specify overrides:
  e.g. "set use_worktree=true, set verify(AC-2)=T2, then confirm"
  Reply "explain" (or "explain <axis>") for a plain-language guide to these choices.
```

   **This layout is literal, and it is deliberately not marked unenforced.** No hook can check it — the display is conversational, never a file — so the template *is* the whole enforcement. A previous version expressed it as descriptive prose, which read as decoration and was deleted in an instruction-surface cut; the run then drifted into free-form summaries that satisfied nobody. Keep it as a block.
6. **Block until explicit confirmation.** No timeout, no implicit acceptance.
7. **Create the task list immediately on approval** — one task per planned step, `0:` marked completed. Nothing runs in between.

**Task-list format — blessed, and it binds across every step, not just Step 0.**

- **Chronological order of execution.** The list reads top to bottom as the work will actually happen.
- **Format A — `<task>: <short desc>`** (e.g. `3: Plan — lock slices and matrix`).
- **Format B — `<task>/<slice>: <short desc>`**, only where slices are involved (e.g. `4/2: fix the window conversion`).
- **A takes precedence over B when slices are present**: the step's own entry is DROPPED and its slices stand in its place. Never print `4: Implement` above `4/1: …` — display space is precious and the parent line is duplicative. It is also a line that can never complete until all its slices do, so it carries no signal.
- **Short descriptions.** The subject is a signal, not a summary — detail belongs in the task body or the plan.
- **No filler.** Every entry is a real unit of work with a real status; nothing decorative, nothing that carries no state.
- **No freeform titles.** An entry without a `<task>:` or `<task>/<slice>:` prefix is malformed.
- Mark `in_progress` on starting and `completed` the moment it is done — never batch completions. When a subagent finishes, the orchestrator updates the entry; dispatched work is ledgered in the plan, never as a bare task.

The list is the user's visible progress surface. Nothing enforces this — no hook can read a task list — so the format is the whole discipline.

**Override DSL.** `set <axis|flag>=<value>` and `set verify(<AC>)=<tier>`, comma-separated, ending in `confirm`. `explain [axis]` renders the axis tables and never counts as confirmation; a free-text question about the display is treated as `explain`, never as a parse error. A rigor override BELOW a derivable floor is refused by this skill (name the binding floor and keep the floor value) — no code refuses it. A barred intent × scale cell is rejected.

**Evidence:** `Step 0: configured at <ISO> via <reply>; model_plan=<tiers>; integration-branch=<name>`

### Step 3 — Plan shape

Two sections are required in every plan file.

`## SDLC State` opens with `integration-branch:`, the triple, and `current: <N>` — the hook greps `^current:` and blocks every commit if it is missing or malformed. Write `current:`, never `current-step:`. Then one `Step N: <evidence>` line per step; bump `current:` and replace the line in place when advancing.

```
## SDLC State

integration-branch: <name>
intent: <intent>
rigor: <rigor>
scale: <scale>
current: <N>

- Step 0: <evidence>
- Step 1: (pending)
```

**Task-scale variant.** `current: T<n>`, one `- T<n>: <evidence>` line per task, backed by a `## Tasks` table with columns `| id | intent | rigor | description | status |`, `id` matching `^T[0-9]+$` and status in `pending|active|done|dropped`. A row's rigor cell may RAISE that task above the frontmatter default; lowering it is a downgrade that blocks unless the evidence line carries a `waiver:` marker. Dispatched work is ledgered by the orchestrator, never by the subagent.

`## Assumptions` is seeded from Step 1's "Not Doing" plus spec ambiguities; Step 4 appends inline, before the commit that resolves each one.

Tag every Step-4 slice `complexity: standard | complex`. When uncertain, tag `complex`.

**Wave shape locks at approval.** Mid-wave discoveries go to `## Assumptions` as W+1 candidates — they do not reshape the current wave. Two exceptions: a discovery that makes the wave structurally impossible (surface a Wake Note and halt — the answer is "this wave cannot ship," not "ship a different wave"), and one-line trivial corrections.

### Step 5 — Verify

The gate discharges the matrix row by row; the unit is the matrix row (`5/<AC-id>`).

**Tests floor, always:** run every applicable suite and the build, record `cmd:`/`pass:`/`total:`/`output:`, `pass == total`. No `n/a`.

"Every applicable suite" is a **discovered** set, not whatever the default command runs. Check `package.json`, `Makefile`, CI config, test-runner configs, and test directories for suites the default runner omits — a hand-listed runner that silently drops a suite reports green over untested code. When a change touches code with existing tests, triage each affected test as UPDATE / ADD / REMOVE / OK before implementing, not after.

**Matrix section** carries a `stack-health:` line (a before/after snapshot bracketing the walk, or `n/a: <reason>` — bare `n/a` blocks), the tier table `| AC | tier | status | evidence | auditor |` with exactly five cells per row, no literal `|` inside a cell, tier in `T0`–`T4`, status in `pending|blocked|discharged|waived`, and one evidence block per AC. Reading the stack-health snapshot is human judgment; nothing compares before against after.

**The T0–T4 ladder.** Each tier is defined by which lie it makes impossible.

| Tier | Name | Proves | The false green it kills |
|---|---|---|---|
| **T0** | Static | compiles / builds / lints | type & build breaks |
| **T1** | Unit | logic at mocked seams | wrong logic |
| **T2** | Hermetic | real browser + real engine over a **declared-fidelity fixture** | integration breaks — *only if the fixture matches the real data shape* |
| **T3** | Live agent-drive | the **declared real surface**, real data, cold client, trusted input, feature-scoped semantic readback | every proxy: wrong surface, stale artifact, synthetic data, warm caches |
| **T4** | Human walk | the user's own hands and eyes | perceptual / judgment gaps automation can't close |

A lower tier passing while a higher one fails is a **locator, not a contradiction** — the bug lives in exactly the layer the lower tier elides.

**T2 fixture-fidelity.** A T2 row declares its fixture's provenance in one line: derived from, or validated against, a real captured artifact of the data the AC concerns. A fixture that cannot structurally reach the failure the AC guards is a proxy regardless of its RED→GREEN history — undeclared, a T2 row is a T1 row wearing a browser.

**Per-tier required keys** — the canonical table; the hooks mirror it, so change this first.

| Tier | Required keys in the AC block |
|---|---|
| T0, T1 | `tier-run`, `readback` |
| T2 | `tier-run`, `readback`, `fixture-fidelity` |
| T3 | `tier-run`, `fresh`, `cold-client`, `contact`, `readback` |
| T4 | `user-confirmed` |

**Tier-Discharge Rule.** Lower-tier evidence never discharges a higher-tier row; higher-tier evidence discharges lower-tier rows for the same AC. A green suite can never stand in for a T3 row — a suite run cannot honestly produce `fresh`/`cold-client`/`contact`. T3's validity conditions live in `browser-verify`; do not restate them. An undrivable T3 row is **blocked**, loudly, never silently skipped. T4 rows are discharged by `user-confirmed: <user> <date> <what was walked>` — agents never self-confirm one.

**False-green rule.** On finding any test that passed over broken code, the gate cannot close until the matrix carries `false-green: <test — what it lied about>` AND a paired `rewritten: <ref>` proving the test now goes RED.

**Vocabulary.** Say "delivered/fixed/verified" only at the row's contracted tier. Below tier the honest phrasing is "implemented, verification pending."

**Mid-discharge commits.** At `current: 5`, rows still `pending`/`blocked` are exempt from per-tier keys and the `auditor:` pointer is required only once none remain. The full contract bites on the 5→6 advance, where the matrix is re-validated as a prefix check at every step from 6 on. **Never regress `current:` to dodge a gate.**

#### Auditor — the Step-5 exit gate

A **fresh, independent** exec-complex agent (`subagent_type: auditor`) — never the implementer, never a fork of the orchestrator, whose context is the thing under audit. Dispatch carries this mandate **verbatim**; a paraphrase is a weakened auditor:

> Your job is to falsify this wave's verification evidence, not to review its code. You have the Verification Matrix, the per-row evidence, and repo access. For every row: (1) confirm the evidence was produced at the declared tier — a T3 row must cite the declared real surface, its per-origin freshness proofs, a cold client, and a feature-scoped semantic readback; (2) for T2 rows, demand the fixture-fidelity declaration and check the fixture can structurally reach the failure the AC guards; (3) re-execute at least one evidence command per tier used (cap 3 total) and compare outputs. Verdict per row: CONFIRMED / REFUTED / UNVERIFIABLE. "The evidence is plausible" is not a verdict. Agreement without re-execution is not acceptable output.

Bounds: audits the evidence, not the wave. One auditor, one pass, ≤3 re-executions. Verdicts land in the matrix `auditor` column. Any REFUTED or UNVERIFIABLE row blocks closure absent a waiver.

#### Waiver Protocol

Three moves are the user's, never an agent's: a tier **downgrade**, an **`n/a` on a live tier (T3/T4)**, and **closing over a non-CONFIRMED row**. Each is recorded as `waiver: <user> <date> <reason>` in the row. A waived row is exempt from its per-tier keys and from CONFIRMED. Agents never self-write `n/a` on a live-tier field.

Note the hole: the hook checks only that the token `waiver` is present — not who, when, or why. And retyping a tier cell from T3 to T2 is a downgrade no hook sees.

### Step 6 — Review

**Stance 1 — 5-axis self-review, always.** Correctness, readability, architecture, security, performance; every axis gets an explicit PASS / FLAG / FAIL. Run the axes in parallel. All review agents dispatch at exec-complex regardless of who wrote the code — verification is never cheaper than authorship. Security flags escalate to `agent-skills:security-and-hardening`; performance flags to `agent-skills:performance-optimization`.

**Architecture-axis closure check:** for each new primitive added this wave, trace user input → new code, and confirm the Step-5 T3 readback reached the same code. No callsite reaching it means the substrate is dead and the axis is FAIL.

**Stance 2 — adversarial critic.** Mandatory at `audited`. Must be an **independent** agent (`subagent_type: critic`) — never the author, never self-graded. Distinct from the Step-5 auditor: the critic falsifies the *code*, the auditor falsifies the *evidence*. Prompt template:

> _Your job is to find what went wrong in this change. You have the spec, the plan, the diff, and the 5-axis self-review notes. Read them and try to falsify the claim that this is ready to merge. Look specifically for: silent wrong assumptions not logged in the `## Assumptions` section, scope creep beyond the spec, missing edge cases, fabricated evidence, and cross-cutting concerns a single-axis review would miss. Output either: at least one specific, reproducible issue, or an explicit "no issues found" followed by the three strongest falsification attempts you made and why each failed. Confirmation-seeking agreement is not acceptable output._

Incident framing: does the fix mask a deeper issue, and is the monitoring-gap analysis honest. Sycophantic output is not evidence.

### Step 7 — Document

ADRs attach to decision **significance**, not to rigor: momentous (cross-wave, sets a precedent, expensive to reverse) gets one at any rigor; medium gets one when it will shape later waves; trivial gets none. `incident-response` writes the RCA instead.

### Step 8 — Integrate & close

Atomic, one task. Merge the wave into the declared integration branch (local merge; pushing is the user's gate) and remove the worktree. Default is merge — parking requires an explicit `## Wake Note`. Then, when `cleanup_on_finish: true`: skip if frontmatter already has `cleaned:`; wipe `.bionic/tmp/*`; assert zero non-completed tasks; strip stray `continuation-checkpoint.md`/`handoff-*.md`; set `cleaned: <today>`.

## Evidence shapes

One evidence artifact per step under `Step N:` in `## SDLC State`. The gate validates the current step only.

| Step | Required fields |
|---|---|
| 0 | `prereqs: ok` |
| 1, 2, 3 | pointer (presence only) |
| 4 | pointer; plus `worktree:`/`base-sha:`/`branch:` when `use_worktree: true` |
| 5 | `cmd:`/`pass:`/`total:`/`output:` with `pass == total`, a valid `## Verification Matrix`, and — once no row is `pending`/`blocked` — a non-empty `auditor:` |
| 6 | pointer to the 5-axis body + critic findings; matrix re-validated here |
| 7 | `adr:` OR `rca:` OR `n/a:` |
| 8 | `merge:`, `worktree-removed:`, and (`cleanup:`, `tmp-wiped:`, `tasks-completed:` OR `cleanup: n/a`) |
| 9 | `deploy:`, `verified-at:`, `monitor:` OR `n/a:` (only when `deploy_target: none`) |

**Placeholder ban.** These exact values are rejected anywhere evidence is required: `todo`, `pending`, `in progress`, `inprogress`, `xxx`, `tbd`, `placeholder`.

**Handoff.** A plan spanning sessions carries a `## Handoff` section — resume point (step, sub-task, branch, last commit), decisions ratified this session (reset each time), tried-and-rejected and discovered surprises (persist), open blockers, uncommitted work, and a literal resume instruction. Rewritten in place, never appended. Nothing writes or checks it. At Step 9 write `continuation.md` — wave completed, integration branch + merge SHA, next wave, open carry-overs.

## Hooks

**`canonical-sdlc-evidence-gate.sh`** (`PreToolUse|Bash`) fires only on a real `git commit` segment. It finds the newest `*.md` under the plan dirs, and if it has a `## SDLC State` section, validates the current step's evidence, the matrix, and the task ledger. Log-only (never blocks): the epic merge-target check, and the `refactor`/`tune` intent-scoped Step-5 keys.

**`canonical-sdlc-governing-skill.sh`** (`PreToolUse|Write,Edit`) blocks any artifact under `<docs-root>/{specs,plans,adrs,incidents}/` lacking `governing-skill:` frontmatter, and blocks a `mode:` line, a missing or non-enum triple, a barred cell, a missing flag or `model_plan`, or a missing `## Verification Matrix` at `sdlc-step ≥ 3`. Floor-consistency checks are log-only.

**Known holes — do not mistake these for enforcement.** The governing-skill hook validates `Write` content but not `Edit` content, so one valid write covers every later edit. Flag *values* are never checked, only presence. The evidence gate reads the plan file's text, so an `Edit` that writes evidence for tests never run passes unseen. Proof-shape is a heuristic: a digit plus a `/` satisfies it.

## Dispatch

The orchestrator stays free: it keeps Steps 0–3, slice decomposition, and every approval-shaped decision, and offloads research, execution, verification, and review. Subagents return summaries, never payloads.

Roles, by `subagent_type`: `researcher` and `test-runner` for exploration and mechanical work; `implementor` for `standard` slices; `senior-implementor` for `complex` slices and root-cause debugging; `auditor` for Step 5; `critic` for Step 6. Each role file carries its own invariant duties and model default — the dispatch prompt carries only the five things the role file cannot know: current step, the triple, scope constraint, expected artifact, exit condition.

**Fresh by default; fork only** when hand-feeding context would cost more than the fork's inheritance — a fork re-pays the whole main-thread context AND the orchestrator's effort, and ignores `model`. Never fork a mechanical task, and never fork to reach a cheaper model. **Dispatch is always background when `multi_agent: true`** — attended or not. A synchronous dispatch freezes the session, and a user who cannot type cannot steer. Serialize dependent units by dispatching the next one on the previous one's completion notification, never by blocking. Synchronous main-thread execution exists only under `multi_agent: false`, where there are no subagents at all.

**Parallel by default, justify sequential** — but dispatch serially when units share state (one local DB, a shared reset, count-based assertions).

**Ledger the dispatch, not the return.** Write the unit's row the moment you dispatch it, status `active`. An outstanding agent has to exist as a row you can be blocked on, not as something you intend to remember — a dispatch held only in working memory is lost the moment the conversation turns, which is the normal case, not the exception. The row is also what lets you answer "what's still running" without guessing.

On the completion notification: verify the named artifact exists before believing the report, then update the row. **An idle notification is not a report** — nudge for the artifact, never read silence as success. Nudges are capped; a genuinely wedged agent is killed and re-dispatched, and every kill is reported to the user, never absorbed silently. Recorded evidence: of three agents that went idle without delivering, two were nudged and **both had already completed their work correctly** — kill-on-silence would have destroyed finished work.

Before ending a turn, reconcile: every `active` row either has a verified result or is named to the user as still running.

## Escalation

**Diagnostic friction** (direction clear, code misbehaves) → load `map-instrument-narrow` in a fresh subagent carrying its Rigor Mandate verbatim, and write no fix code until NARROW names a root cause with data. "I'll try one thing first" mutates the state you were about to instrument. Recurse on layered causes, depth ≤4.

**Decision friction** (the direction itself is in question) → stop and surface it. The framing rules live in the global config, not here.

**Three-fail rule.** Three failures to produce valid evidence for one step: if diagnostic, run a full MAP-INSTRUMENT-NARROW pass (the counter resets on a completed pass, not on more speculative fixes); if decision-related, stop and surface. A `standard` slice that fails twice re-dispatches once as `senior-implementor` — that is the third try, not a fourth.

**Stop and wake** for: an ambiguous spec needing a judgment call, new external-API auth, anything affecting billing, destructive migrations, secrets or production infrastructure, and anything the user's own config marks as requiring approval. Append a `## Wake Note` and do not proceed past it.

## Diagrams

`diagrams/lifecycle.png` — the 10 steps, the two gates, and the commit rhythm. `diagrams/hook-chain.png` — which hook fires on which tool event, and which arms block versus log. Sources are the paired `.excalidraw` files.
