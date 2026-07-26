# Canonical SDLC

Bionic's flagship engineering pattern: a 10-step software development lifecycle that runs autonomously for hours and produces an auditable record at the end.

This is the human-facing reference. The skill prose Claude reads at runtime is in [`SKILL.md`](SKILL.md) — same directory.

> **TL;DR.** A skill enforces 10 flat steps (0–9) organized around **two gates** — Verify (Step 5, "does it work?") and Review (Step 6, "is it well-made?") — plus a cross-cutting **commit rhythm** that fires per step rather than at a numbered position. **v11 (current)** replaces the single `mode:` with an orthogonal **`intent · rigor · scale` triple** declared per run: intent ∈ `build`/`bugfix`/`refactor`/`tune`/`spike`/`incident-response`; rigor ∈ `tested`/`peer-reviewed`/`audited`; scale ∈ `task`/`wave` (default)/`epic`. `mode:` is **v≤10 legacy vocabulary**, grandfathered forever and never retrofitted. Plan frontmatter is the single source of truth: `governing-skill`, the `intent`/`rigor`/`scale` triple, `sdlc-step`, `canonical_sdlc_version`, five discriminator flags, two opt-in flags, and a `model_plan` line. State lives in a `## SDLC State` section, one evidence line per step (or per ledger task at `scale: task`). Two hooks back the skill, **unchanged in role**: `governing-skill` validates plan/spec/ADR frontmatter on write (v11: triple presence + whole-value enums, a `mode:` line blocked, barred intent×scale cells blocked), and `evidence-gate` blocks commits whose current-step evidence line is missing or placeholder. Dispatch and model tiering are governed by prose, not a hook.

---

## Contents

- [Why this exists](#why-this-exists)
- [The 10-step lifecycle](#the-10-step-lifecycle)
- [The axis model (and legacy modes)](#the-axis-model-and-legacy-modes)
- [Plan frontmatter contract](#plan-frontmatter-contract)
- [SDLC State and the evidence model](#sdlc-state-and-the-evidence-model)
- [Verification Matrix: a worked example](#verification-matrix-a-worked-example)
- [Handoff tier](#handoff-tier)
- [The two hooks](#the-two-hooks)
- [Model and token strategy](#model-and-token-strategy)
- [Versioning and backward-compat](#versioning-and-backward-compat)
- [RCA shape](#rca-shape)
- [Configuration: the Step-0 wizard](#configuration-the-step-0-wizard)
- [Quick reference](#quick-reference)
- [Pointers](#pointers)

---

## Why this exists

Most "AI does the SDLC" demos collapse the lifecycle: a brainstorm becomes code in one shot, with the spec implied, the plan unwritten, the review skipped, the audit trail missing. That works on toy problems and fails on anything wave-sized — multi-day work that touches multiple files, ships to users, and accumulates decisions a future maintainer needs.

Canonical SDLC is the constraint that forces the lifecycle to stay intact. Each of the 10 steps contributes a dimension of fidelity — scope, contract, plan, isolation, proof, review, decision record, release discipline — that no other step supplies. Without enforcement, individual steps feel skippable in isolation, but the compounding loss of fidelity is invisible mid-effort and surfaces later as rework.

The skill mandates the full step set; the two hooks make the *evidence* non-skippable at the granularity they check — a write without declared frontmatter, a commit without the current step's evidence. The plan file is the single source of truth: configuration lives in YAML frontmatter, evidence lives in the `## SDLC State` section, and decisions live in ADRs (or RCAs for incidents). Every commit must show evidence for the current step. Every plan/spec/ADR must declare the skill that produced it.

The autonomous span is **Steps 4–9** — Claude walks away to build for hours and returns with merged code. Steps 1–3 (Ideate, Spec, Plan) are interactive: that's where wrong assumptions get caught cheaply. Step 3 ends with an explicit user approval before autonomous execution begins.

### The Iron Law

```
NO STEP SKIPPED WITHOUT A DECLARED FAST-PATH.
NO COMMIT WITHOUT EVIDENCE FROM THE CURRENT STEP.
```

Violating the letter of this process is violating the spirit of this process.

**What enforces this, precisely.** The evidence gate is incremental, not holistic. At each commit it reads the plan's `current: N` and validates the evidence line for **that step only** — it never re-validates steps 0..N-1, and nothing re-checks the full set at completion. The sole cumulative contract is the `## Verification Matrix`, a prefix re-validated at every step from 6 on. Walking every applicable step is the discipline the per-commit check serves, not a property any code proves: an abandoned step is caught by review, not by the harness.

---

## The 10-step lifecycle

Ten flat steps, numbered 0–9. No interstitials, no sub-steps, no hidden stations — the number you see is the number that runs. The lifecycle is organized around **two gates** — **Verify** (Step 5, "does it work?") and **Review** (Step 6, "is it well-made?") — each decomposed by modality or stance rather than by extra numbered steps.

| Step | Name | Governing skill | Tier | Purpose |
|---|---|---|---|---|
| 0 | Configure | `canonical-sdlc` + `agent-skills:context-engineering` | O | Set every plan-shaping flag with explicit user confirmation |
| 1 | Ideate | `agent-skills:idea-refine` | O | Pin scope + non-goals (6-lens refinement + "Not Doing" list) |
| 2 | Spec | `agent-skills:spec-driven-development` | O | Testable contract with acceptance criteria |
| 3 | Plan | `superpowers:writing-plans` | O | Execution contract (`## SDLC State` + `## Assumptions`); approval checkpoint before Step 4 |
| 4 | Implement | `agent-skills:incremental-implementation` | E + X | Thin vertical slices, RED→GREEN per slice |
| 5 | Verify (gate) | `superpowers:verification-before-completion`; browser modality `browser-verify` (drives `playwright-cli`; chrome-devtools MCP reserved for deep inspection) | X→O | "Does it work?" — tests/build always; real-browser behavior when UI/user-visible |
| 6 | Review (gate) | `agent-skills:code-review-and-quality` | E | "Is it well-made?" — 5-axis self-review (always) + adversarial critic (mandatory at `audited` rigor — into which `incident-response` floors) |
| 7 | Document decisions | `agent-skills:documentation-and-adrs` | O / E | ADR (or RCA for incidents) |
| 8 | Integrate & close | `superpowers:finishing-a-development-branch` + `canonical-sdlc` | O / X | Merge into integration branch + remove worktree (finish half), then wipe `.bionic/tmp/`, assert task-list integrity, strip handoff (cleanup half) |
| 9 | Ship | `agent-skills:shipping-and-launch` | E / O | Production gate; emit `continuation.md` |
| — | Commit rhythm (cross-cutting) | `agent-skills:git-workflow-and-versioning` | O | Not a numbered step — a per-step checkpoint-commit rhythm that fires throughout |

**Tier key.** Each step has a default dispatch target (the strategy below governs; the tier is a hint):

- **O — orchestrator.** The main thread. Runs Steps 1–3 directly and coordinates the rest.
- **E — execution.** A fresh subagent routed by the slice's `complexity:` tag to an installed role via `subagent_type` — `complex` → `senior-implementor` (`model: opus`), `standard` → `implementor` (`model: sonnet`); fork only when the unit genuinely needs the inherited conversation.
- **X — explore / mechanical / test.** A fresh `model: sonnet` subagent — search, fixtures, mechanical edits, test-writing.

### The approval checkpoint

The end of Step 3 is the "walk away" boundary. After the plan is complete, Claude presents a summary (framing, options to approve / request revisions / halt, why-it-matters) and **only begins Step 4 on explicit approval**.

Wave scope locks at approval. Mid-wave discoveries — architectural gaps, related bugs, audit findings — get logged to `## Assumptions` as candidates for the next wave; they do not reshape the current wave. Two exceptions: a discovery that makes the current wave structurally impossible is surfaced as a Wake Note and halts; a trivial one-line correction in a touched file ships inline. Step 6 (Review)'s adversarial-critic stance checks for unjustified mid-wave scope drift.

### Autonomous does not mean "skip Step 1 Q&A"

The autonomous span is Steps 4–9. The user-engagement sequence is:

| Step | Engagement |
|---|---|
| 1. Ideate | **Interactive Q&A.** Extensive back-and-forth on scope, non-goals, alternatives. Mandatory for every run, every intent. |
| 2. Spec | **Semi-interactive.** Translate Step 1 into a testable contract; surface remaining ambiguities as Wake Notes, else proceed. |
| 3. Plan | **Autonomous write → one approval checkpoint.** Claude writes the plan; the user approves before Step 4. |
| 4–9 | **Fully autonomous**, within the stop-and-wake rules. |

Skipping Step 1 Q&A to "save time" is the single highest-risk move.

---

## The axis model (and legacy modes)

**v11 (current) replaces the single `mode:` with three orthogonal axes.** Every run declares exactly **one triple** — `<intent> · <rigor> · <scale>` — at Step 0. The axes are independent: any intent runs at any rigor (subject to floors) and any valid scale. **Intent** is the kind of work, **rigor** is how hard the evidence tries to lie, **scale** is the decomposition unit. Intent declaration is reviewable — a run mislabelled to dodge steps is drift with a label.

This section summarizes the axes and points at the normative definitions; the **canonical value definitions, evidence-shape deltas, and inference signals live in SKILL.md — [§The Three Axes](SKILL.md), [§Rigor floors and lifecycle](SKILL.md), and [§Intent × scale validity](SKILL.md).** This README documents deltas and summaries only — it does not fork the normative tables.

### Intent — the kind of work (one line each)

- **`build`** — new capability, or capability restored by ADDING machinery/interfaces/config (the machinery test). Covers features AND internal/infra work. Standard RED→GREEN.
- **`bugfix`** — restore intended behavior WITHIN the existing design; RED = failing repro, GREEN = repro passing.
- **`refactor`** — change structure without changing behavior (incl. upgrades, migrations, removals); evidence is behavior-preservation.
- **`tune`** — move a NAMED measured quantity toward a target (perf, size, UX quality); baseline → target → re-measure. Absorbs the former UX-refresh lifecycle as its UX flavor.
- **`spike`** — timeboxed research/prototype; **ships no code at any rigor**; the artifact is a writeup, no plan file.
- **`incident-response`** — a live deployed surface (production OR tooling) broken for its users; RCA not ADR; floors at `audited`.

### Rigor — how hard the evidence tries to lie (cumulative; one line each)

- **`tested`** — "it provably works": TDD RED→GREEN, matrix discharged at tier, tests floor, 5-axis self-review. **No** independent auditor or critic — self-review only. At task scale, a ledger row's evidence needs only a non-placeholder `- T<n>:` line.
- **`peer-reviewed`** — "works and well-made": adds a separate spec and the INDEPENDENT Step-5 Verification Auditor on the evidence. **No** adversarial critic. At task scale, a ledger row's evidence must additionally be proof-shaped (a digit + a command token) and, once `done`, name an `auditor` verdict.
- **`audited`** — "a third party tried to break it, and the trail survives me": adds the mandatory INDEPENDENT Step-6 adversarial critic, per-step checkpoint commits, and the expanded stop-and-wake list. Top tier. At task scale, a `done` ledger row additionally names a `critic` verdict; at wave scale, an audited multi-agent plan must carry a `## Tasks` dispatched-task ledger section at all (D7 presence).

### Scale — the decomposition unit (one line each)

- **`task`** — a sub-session unit; MULTIPLE per session; one session-level plan with a `## Tasks` ledger (one `## SDLC State` line per task), **no per-task plan/spec files**. The ledger's evidence-gate enforcement is **blocking**, rigor-keyed to each row's own effective rigor (§Task-scale ledger enforcement below).
- **`wave`** (default) — the full step set 0–9; one wave spec + plan; slices inside Step 4.
- **`epic`** — Steps 0–3 only (short-circuits before Step 4); carves waves; owns the `epic/NN-<slug>` integration branch.

### Scale-keyed rigor defaults (D11) and floors

Default rigor is **scale-keyed** (provisional at Step 0, locked at Step 3): `audited` is the default at **wave scale and above**; the **task** lane keeps the lighter `tested`/`peer-reviewed` defaults (bugfix/spike → `tested`; build/refactor/tune → `peer-reviewed`; incident-response floors at `audited` everywhere). Effective rigor is the **MAX across four floor sources** — intent floor, flag floor (security/privacy/vulnerable-population → `audited`), project floor (`.bionic/config.yaml`), epic floor (epic frontmatter `rigor-floor:`) — a floor only pushes rigor **UP**, never down (upward-only). Full mechanics: [SKILL.md §Rigor floors and lifecycle](SKILL.md).

### Barred intent × scale cells (D4)

`bugfix × epic`, `spike × epic`, and `incident-response × epic` are **barred** — a bugfix needing multi-session decomposition is a misclassified refactor/build; spikes and incidents are timeboxed/clock-driven, not epic-scoped. The governing-skill hook blocks a barred triple on v11 artifacts.

### Legacy modes (v≤10 vocabulary only)

Before v11 the skill ran on a single `mode:` axis with five values. **These names are v≤10 vocabulary only; v11 plans never declare `mode:`.** The table below is the legacy→triple mapping for reading old plans; the canonical mapping with its notes lives at [SKILL.md §Legacy modes (v≤10)](SKILL.md).

| v≤10 `mode:` | v11 triple (nearest equivalent) |
|---|---|
| `autonomous` | `build` · `audited` · `wave` (literally the v11 wave default under D11) |
| `epic-scope` | `<intent>` · — · `epic` (scale-only; rigor set by the eventual intent) |
| `incident-response` | `incident-response` · `audited` · `wave` (survives as an intent; the mode's discipline is now the `audited` floor) |
| `design-refresh` | `tune` · `peer-reviewed` · `wave` (UX flavor; the impeccable loop is unchanged) |
| `spike` | `spike` · `tested` · `wave`/`task` (survives as an intent; capped at `tested`) |

v≤10 plans keep their `mode:` line and their v≤10 hooks/shape-tables forever — see [Versioning](#versioning-and-backward-compat) for the grandfathering rule.

---

## Plan frontmatter contract

Plans declare every plan-shaping flag in YAML frontmatter. Step 0 (the wizard) writes this; the `governing-skill` hook enforces its presence on writes; the `evidence-gate` hook reads it on every commit.

### Identity block

**v11 (current)** — declares the `intent`/`rigor`/`scale` triple; **no `mode:` line**:

```yaml
---
governing-skill: superpowers:writing-plans
sdlc-step: 3
epic: epic-02-v2-product-pass
wave: wave-01-checkout-refactor
intent: build
rigor: audited
scale: wave
canonical_sdlc_version: 11
---
```

**v10 (prior, autonomous)** — same identity fields but keyed on the legacy `mode:`:

```yaml
---
governing-skill: superpowers:writing-plans
sdlc-step: 3
epic: epic-02-v2-product-pass
wave: wave-01-checkout-refactor
mode: autonomous
canonical_sdlc_version: 10
---
```

A **v11 artifact must NOT carry a `mode:` line** — the two vocabularies are mutually exclusive, and the governing-skill hook blocks a `mode:` line on a v11 artifact as a split-brain guard (exit 2). Conversely, a v≤10 plan keeps `mode:` and never gains the triple. For incident-response artifacts, use `incident: NNNN-<slug>` instead of `epic`/`wave`.

| Field | Values | Purpose |
|---|---|---|
| `governing-skill` | A skill ID (`superpowers:writing-plans`, `agent-skills:idea-refine`, `canonical-sdlc`, …) | Names the skill that produced this artifact. Different artifacts carry different governing skills (Step 1 → `idea-refine`; Step 3 → `writing-plans`; Step 7 RCA → `canonical-sdlc`). |
| `sdlc-step` | `0..10` | The step that produced this artifact. The evidence-gate hook reads `current:` in `## SDLC State`, not this field, to pick the step to validate. |
| `intent` (v11) | `build` \| `bugfix` \| `refactor` \| `tune` \| `spike` \| `incident-response` | The kind of work. Whole-value enum, hook-checked. Seeds governing-skill substitutions and default flags. |
| `rigor` (v11) | `tested` \| `peer-reviewed` \| `audited` | How hard the evidence tries to lie. Provisional at Step 0, locked at Step 3; floors push it up only. |
| `scale` (v11) | `task` \| `wave` \| `epic` | The decomposition unit. `task` uses a `## Tasks` ledger; `epic` short-circuits after Step 3. Barred against some intents (§validity). |
| `mode` (**v≤10 only**) | `autonomous` \| `epic-scope` \| `incident-response` \| `design-refresh` \| `spike` | **Legacy vocabulary — not written on v11 plans.** Determined applicable steps, governing-skill substitutions, and default flag values under v≤10. See [The axis model (and legacy modes)](#the-axis-model-and-legacy-modes). |
| `canonical_sdlc_version` | `1`/`2` (legacy) \| `3` \| `4` \| `5` \| `6` \| `7` \| `8` \| `9` \| `10` (prior) \| `11` (current) | Routes the hooks. See [Versioning](#versioning-and-backward-compat). |
| `epic` / `wave` / `incident` | Identifier matching the enclosing directory | `epic-NN-<slug>` / `wave-NN-<slug>` for epic-tree work; `NNNN-<slug>` for incidents. |

> **Universal structural contract (v11, D13).** On v10 the 5 discriminator flags + 2 opt-in flags + `model_plan` + the `## Verification Matrix` (at `sdlc-step ≥ 3`) were required only on the `autonomous` mode. **v11 re-keys this off the triple's presence, not a mode value: the same structural contract applies to EVERY v11 artifact regardless of intent** — a `bugfix`, a `refactor`, a `tune`, all carry the full flag set + `model_plan` + matrix. There is no `mode:` short-circuit to exempt a plan.

### Discriminator flags (5 — required on v3–v10 autonomous plans **and all v11 plans**)

| Flag | Values | Default |
|---|---|---|
| `surface_type` | `api` \| `graphql` \| `ui` \| `iac` \| `ml` \| `realtime` \| `mobile` \| `system` \| `none` | inferred |
| `language` | `typescript` \| `javascript` \| `rust` \| `go` \| `python` \| … \| `none` | inferred |
| `has_ui` | bool | inferred |
| `multi_agent` | bool | **`true`** |
| `deploy_target` | `k8s` \| `vercel` \| `custom` \| `migration` \| `none` | inferred |

### Opt-in flags (2 — required on v3–v10 autonomous plans **and all v11 plans**)

| Flag | Default | What it does |
|---|---|---|
| `cleanup_on_finish` | `true` | When `true`, the cleanup half of Step 8 (Integrate & close) runs after the merge half: wipes `.bionic/tmp/`, asserts task-list integrity, strips leftover handoff files. |
| `use_worktree` | `false` | When `true`, Step 4 creates a git worktree at `.worktrees/<slug>` and records `worktree:`/`base-sha:`/`branch:` in its evidence line. |

### `model_plan` (required on v4–v10 autonomous plans **and all v11 plans**)

A single-line record of the confirmed model tiers, derived from `multi_agent` and the detected session model at Step 0 and surfaced for explicit confirmation:

```yaml
model_plan: orchestrator=fable-5-high; exec-complex=opus-fresh; exec-standard=sonnet-fresh; explore=sonnet-fresh
```

For `canonical_sdlc_version: 4` through `10` autonomous plans the governing-skill hook **requires** `model_plan` — a missing value blocks the write (exit 2). On **v11** the requirement is universal (D13): every v11 plan carries `model_plan` regardless of intent, with no mode short-circuit. v3 plans keep the prior contract (no `model_plan`). `model_plan` changes no per-step evidence shape; it records intent only.

---

## SDLC State and the evidence model

Configuration lives in frontmatter; **live state lives in a `## SDLC State` section** in the plan body:

```markdown
## SDLC State
integration-branch: main
intent: build
rigor: audited
scale: wave
current: 4

Step 0: configured at 2026-05-03T14:22Z via "set deploy_target=vercel, confirm"; model_plan=orchestrator=fable-5-high; exec-complex=opus-fresh; exec-standard=sonnet-fresh; explore=sonnet-fresh
Step 1: docs-root/specs/epic-02/wave-01.spec.md#ideate
Step 2: docs-root/specs/epic-02/wave-01.spec.md#requirements
Step 3: #plan-body
Step 4:
  worktree: .worktrees/wave-01
  base-sha: a1b2c3d
  branch: wave-01
Step 5: (pending)     # Verify (gate)
Step 6: (pending)     # Review (gate)
Step 7: (pending)     # Document decisions
Step 8: (pending)     # Integrate & close
Step 9: (pending)     # Ship
```

On v11, `## SDLC State` opens with `integration-branch:` and the `intent`/`rigor`/`scale` triple, then `current:` (a v≤10 plan opens with `mode:` here instead). `current: N` names the active step. When advancing, **replace `Step N: (pending)` in-place** — never append. (`Phase N:` is accepted as a legacy alias for `Step N:`.) At **`scale: task`** the section instead addresses a ledger task — `current: T<n>` plus one `- T<n>: <evidence>` line per task, backed by a `## Tasks` registration table (see [Task-scale addressing](#task-scale-addressing-v11)). The `## Assumptions` section sits alongside it, seeded from Step 1's "Not Doing" list plus spec ambiguities, and appended inline during Step 4.

### Two evidence tiers

Evidence falls into exactly two tiers:

| Tier | Always present? | Enforced by |
|---|---|---|
| **Verification** | Yes — mandatory | `canonical-sdlc-evidence-gate.sh` (presence + per-step shape on v3–v11; v11 wave/epic shares the v10 shape) |
| **Handoff** | Only when a plan spans sessions | Skill prose + the Stop-hook checkpoint |

There is no third "narrative" tier. Decision-point prose to the user is governed instead by the **User Decision Protocol**: frame the decision at the highest useful level of abstraction, offer numbered options each with a one-line rationale, state significance in one sentence, and keep the whole thing under ~200 words. If stating the question needs a filename or line number, the abstraction level is wrong — climb a rung and rewrite.

### Per-step evidence shape — the v10 table (current, shared by v11 wave/epic)

**v11 wave- and epic-scale plans run the v10 per-step table below unchanged** — same per-step fields, same `## Verification Matrix` validation. v11 re-keys the *gate* off the triple, not the evidence shape; the per-step shapes are identical. `scale: task` plans instead run the [task-scale ledger enforcement](#task-scale-ledger-enforcement-v11) below — now **blocking**, rigor-keyed, tightened in place under the same `canonical_sdlc_version: 11` (no `v12`). Audited multi-agent waves additionally carry [D7 dispatched-task ledger presence](#d7-dispatched-task-ledger-presence-wave-scale), and [intent-conditional Step-5 keys](#intent-conditional-step-5-keys-v11) round out the v11 additions.

`canonical_sdlc_version: 10` replaces the flat, ever-growing universal-key stack (`devtools-trace:` / `bundle-fresh:` / `drive-check:` / `stack-health:`) with a **pre-registered Verification Matrix**: one row per acceptance criterion, derived at Step 0 from the spec, locked at Step 3 approval, and discharged row-by-row at Step 5. The Step-5 block in `## SDLC State` shrinks to the tests floor plus one pointer:

```
Step 5:
  cmd: bash test.sh
  pass: 332
  total: 332
  output: <plan>#step-5
  auditor: 3 rows CONFIRMED — report .bionic/tmp/audit.md
```

The per-row evidence lives in a separate top-level `## Verification Matrix` plan section — see [Verification Matrix: a worked example](#verification-matrix-a-worked-example) for the full shape. The v10 per-step table:

| Step | Required fields under `Step N:` | Notes |
|---|---|---|
| 0 | `prereqs: ok` | smoke |
| 1, 2, 3 | pointer | presence-only |
| 4 | pointer; also `worktree:`/`base-sha:`/`branch:` when `use_worktree: true` | presence-only |
| 5 Verify | `cmd:`/`pass:`/`total:`/`output:` (`pass == total`) **AND** a valid `## Verification Matrix` section **AND** — once no row is `pending`/`blocked` — a non-empty `auditor:` pointer | tests floor lives in `## SDLC State`; per-row tier evidence lives in the matrix section; mid-discharge relaxation is v10.1 (below) |
| 6 Review | pointer to 5-axis body + critic findings | the matrix is re-validated here as a prefix check — a `REFUTED` row blocks the commit |
| 7 Document | `adr:` **OR** `rca:` **OR** `n/a:` | |
| 8 Integrate & close | `merge:`, `worktree-removed:` **AND** (`cleanup:`, `tmp-wiped:`, `tasks-completed:` **OR** `cleanup: n/a`) | |
| 9 Ship | `deploy:`, `verified-at:`, `monitor:` **OR** `n/a:` | `n/a` valid only when `deploy_target: none` |

**Per-tier required evidence keys** — each non-waived matrix row's `<AC-id>:` block carries exactly these keys, keyed off the row's tier (browser-verify's T0–T4 ladder; T0/T1 unit-and-below, T2 hermetic, T3 live agent-drive, T4 human walk):

| Tier | Required keys in the AC block |
|---|---|
| T0, T1 | `tier-run`, `readback` |
| T2 | `tier-run`, `readback`, `fixture-fidelity` |
| T3 | `tier-run`, `fresh`, `cold-client`, `contact`, `readback` |
| T4 | `user-confirmed` |

**The Tier-Discharge Rule:**

> Evidence at a lower tier never discharges a higher-tier row. Evidence at a higher tier discharges lower-tier rows for the same AC.

A green suite (T1) can never stand in for a T3 row — a suite run cannot honestly produce a T3 row's `fresh`/`cold-client`/`contact` fields, so the hook blocks on the missing keys rather than accepting suite-credit.

**Independent Verification Auditor.** Step 5 does not close until a fresh, independent exec-complex agent (never the implementer, never a fork) has ruled CONFIRMED / REFUTED / UNVERIFIABLE on every row, re-executing at least one evidence command per tier used (cap 3). Verdicts land in the matrix's `auditor` column. The auditor falsifies the wave's **evidence**; this is distinct from the Step 6 critic, who falsifies the wave's **code** — both run, neither substitutes for the other.

**Waiver Protocol.** Three moves are user decisions only, never an agent's: a tier downgrade, a self-written `n/a` on a live tier (T3/T4), and closing over a non-`CONFIRMED` row. Each is recorded on the row as `waiver: <user> <date> <one-line reason>`, which exempts that row from its per-tier keys and from the CONFIRMED requirement.

**False-green pairing.** A `false-green: <test — what it lied about>` entry in the matrix section does not close the gate on its own — it must carry a paired `rewritten: <commit/test ref>` proving the test now goes RED on the broken code. A logged-but-unfixed false-green is a blocking defect.

**Mid-discharge commits (v10.1).** As shipped, v10 demanded the *full* matrix on every commit at `current: 5`, so a corrective commit made mid-walk — the common case; Verify exists to find bugs — had no honest home, and the observed workaround was regressing `current:` to 4 (which misstates the step and silently drops the tests floor). v10.1 completes the gate's own pattern: at `current: 5`, rows with status `pending` or `blocked` skip the per-tier key check, and the `auditor:` pointer is required only once every row is discharged or waived — the auditor is the exit gate and cannot have run mid-walk. The full contract (per-tier keys + `CONFIRMED` on every non-waived row) bites on the 5→6 advance via the 6..9 prefix check, exactly as the `CONFIRMED` rule always did. Because the status cell now carries gate semantics, it is enum-checked: `pending|blocked|discharged|waived`, anything else blocks. Nothing previously shippable is blocked and nothing previously blocked at closure is admitted — the relaxation applies only *inside* Step 5, where the old behavior forced dishonest state instead of preventing it.

**Key-family consolidation.** v7–v9 each added one flat universal Step-5 key on its own failure axis — `bundle-fresh:` (artifact), `drive-check:` (contact), `stack-health:` (runtime) — and the design review that closed that series recorded a binding threshold: a *fifth* universal key would force prose-side consolidation into one structured contract rather than another bullet. v10 is that consolidation, taken pre-emptively instead of waiting for a fifth flat key: the artifact and contact axes fold into each T3 row's own `fresh`/`contact` fields (scoped to that AC's actual serving path and interaction, not a wave-wide proof), and the runtime axis survives unchanged as the matrix's once-per-session `stack-health:` line. Net effect: proof that used to be one-size-fits-all is now per-AC and per-tier, with no growth in universal keys.

**Reopened-wave upgrade path (v9→v10).** The no-retrofit rule (below) has one narrow exception: a plan reopened with exactly Steps 5–9 remaining may bump `canonical_sdlc_version` to `10` by (1) the version-number change, (2) a user-approved `## Verification Matrix` covering only the reopened ACs, and (3) leaving Steps 0–4 evidence untouched under v9 rules. A plan still executing Steps 0–4 stays on its original version — declare v10 fresh at Step 0 instead.

#### Task-scale ledger enforcement (v11)

A `scale: task` plan addresses a ledger **task**, not a numbered step. `## SDLC State` opens with `current: T<n>` and carries one `- T<n>: <evidence>` line per task (the full step set compressed into one line), backed by a `## Tasks` registration table (`| id | intent | rigor | description | status |`, `status ∈ pending|active|done|dropped`, `id` matching `^T[0-9]+$`). Frontmatter `intent:`/`rigor:` are session defaults; ledger cells may raise a task's rigor above the default — lowering it below the default is a DOWNGRADE that blocks (exit 2) unless the task's `- T<n>:` evidence line carries a `waiver:` marker (Waiver Protocol, the same floor model as run-rigor). An empty cell inherits the frontmatter value, and a cell naming anything outside `tested|peer-reviewed|audited` is a blocking malformation on ANY row, at ANY status, regardless of frontmatter rigor.

The evidence-gate hook **accepts `current: T<n>`** on v11 task-scale plans without blocking (a false block here would be a defect), then **blocks**, rigor-keyed to each row's own effective rigor, in three cumulative lanes:

- **tested (floor, every row).** The addressed unit (`current: T<n>`) must have a row in `## Tasks` and a non-placeholder `- T<n>:` evidence line. Nothing else — the cheap lane stays one honest line.
- **peer-reviewed.** The evidence line must be **proof-shaped** — contains at least one digit AND at least one command token (a backtick, a `/`-bearing path, or a whole-word runner from a small fixed set) — plus, on `done` rows, names an `auditor` verdict.
- **audited.** `done` rows additionally name a `critic` verdict.

These lanes apply to the addressed unit always, and to any OTHER `done` row that already carries real (non-empty, non-placeholder) evidence — a false-done claim at peer-reviewed-or-higher rigor blocks even off the addressed row. The remaining ledger-shape checks on non-addressed rows — a missing `## Tasks` section, an invalid status cell, or an active/done row with no evidence line at all — stay **log-only** below frontmatter `rigor: audited`; at `rigor: audited` they become **blocking** too. Canonical skeleton: [SKILL.md §Step 3](SKILL.md); canonical contract: [SKILL.md §Evidence — v11 shape table](SKILL.md).

#### D7 dispatched-task ledger presence (wave scale)

An `audited`, `multi_agent: true` plan at `scale: wave` must carry a `## Tasks` section — the dispatched-task ledger's home (§Task Tracking, SKILL.md) — or the evidence-gate hook blocks the commit. An empty section is fine (a `none dispatched` line documents zero rows). Any rows present validate at the **tested-floor shape only** — status enum + evidence-line presence + the placeholder ban — not the proof-shape/auditor/critic lanes above, because the wave's own Step-5 auditor and Step-6 critic are the assurance roles at wave scale. `scale: epic` is excluded — an epic dispatches research, not task-shaped units.

#### Intent-conditional Step-5 keys (v11)

Beyond the universal Step-5 tests floor, two intents carry additional Step-5 keys — conditional per-intent keys, **not** members of the universal key family:

| Intent | Additional Step-5 keys | Notes |
|---|---|---|
| `refactor` | `behavior-preservation:` (required); migrations/upgrades additionally `compat-matrix:`/`revert-plan:` — or `n/a: not a migration` when the refactor isn't one | the "behavior preserved" spec is the existing suite staying green across the change; `compat-matrix:`/`revert-plan:` are present-but-may-be-empty for a non-migration via the `n/a` escape |
| `tune` | `baseline:`/`target:`/`re-measure:` (all three required) | record the starting value, the target declared before tuning, and the re-measured value on the same instrument; applies at every rigor |

**Enforcement is log-only (D14, check-ids `refactor-evidence` and `tune-evidence`):** each finding appends one line to `.bionic/memory/sdlc-v11-audit.md` + stderr, then exits 0 — it never blocks. Promotion to blocking is a later user decision made from that audit data. Canonical definitions: [SKILL.md §The Three Axes](SKILL.md) (intent deltas) and [§Evidence — v11 shape table](SKILL.md).

### Per-step evidence shape — v9 and earlier (kept as-shipped, never retrofitted)

Plans at `canonical_sdlc_version: 9` (and the version ladder below it) keep running their own shape table exactly as it shipped — the evidence-gate hook never retrofits a newer version's requirements onto an older plan; an in-flight plan would start blocking mid-wave. The evidence-gate hook checks the current step's line against this table on every `git commit`:

| Step | Required under `Step N:` | Notes |
|---|---|---|
| 0 | `prereqs: ok` (or the configured line) | presence |
| 1 | pointer to the ideate body | pointer-only |
| 2 | pointer to the spec body | pointer-only |
| 3 | pointer to the plan body | pointer-only |
| 4 | pointer to the slice list; **or** `worktree:`/`base-sha:`/`branch:` when `use_worktree: true` | pointer-only at the hook |
| 5 Verify | `cmd:`, `pass:`, `total:`, `output:` (`pass == total`) **AND** `devtools-trace: <path>` **OR** `n/a: <reason>` **AND** `bundle-fresh: <proof>` **OR** `bundle-fresh: n/a: <reason>` **AND** `drive-check: <observed delta>` **OR** `drive-check: suite: <named test — what it asserts>` **OR** `drive-check: n/a: <reason>` **AND** `stack-health: <before/after snapshot, no delta>` **OR** `stack-health: n/a: <reason>` | tests/build modality always; browser modality is a trace or `n/a`; bundle freshness is proof or n/a-with-reason; drive-check is delta, suite-credit, or n/a-with-reason; stack-health is a no-delta snapshot or n/a-with-reason |
| 6 Review | pointer to the 5-axis review body + critic findings | pointer-only |
| 7 Document | `adr: <path>` **OR** `rca: <path>` **OR** `n/a: <reason>` | |
| 8 Integrate & close | `merge:`, `worktree-removed:` **AND** (`cleanup:`, `tmp-wiped:`, `tasks-completed:` **OR** `cleanup: n/a`) | finish half + cleanup half in one atomic step |
| 9 Ship | `deploy:`, `verified-at:`, `monitor:` **OR** `n/a: <reason>` | `n/a` valid only when `deploy_target: none` |

Steps 1, 2, 3, 4, and 6 are pointer-only at the hook level — the hook checks that a non-placeholder pointer exists, not its contents. Multi-field steps use YAML-style indented keys under `Step N:`:

```
Step 5:
  cmd: bash test.sh
  pass: 332
  total: 332
  output: <docs-root>/plans/<slug>.plan.md#step-5
  devtools-trace: .bionic/tmp/devtools-trace-golden.json
  bundle-fresh: FRESH — canary token-9f3a round-tripped to dist/main.js in 4.2s
  drive-check: drag moved app value 3 → 7 via eval readback
  stack-health: restarts 0 → 0, no crash/OOM state change
```

The `bundle-fresh:` value is the pasted output line of the project's freshness tool — typically a canary round-trip (a unique token written into a dev-only source file, polled for in the served artifact, then restored) proving the serve reflects the working tree, not a stale watcher. The hook validates presence and the placeholder ban, not the format — the format is project-specific by design.

The `drive-check:` value is the observed state delta from one trusted interaction, read back semantically (`drive-check: <observed delta>`), a named suite test that makes the same real contact (`drive-check: suite: <named test — what it asserts>`), or `n/a: <reason>` when no browser modality applies. Like `bundle-fresh:`, the hook validates presence and the placeholder ban only — the semantics live in skill prose.

The `stack-health:` value is the before/after snapshot of the serving stack's runtime-integrity indicators — process/container restart counts, crash/OOM last-state — showing no change across the walk (`stack-health: <before/after snapshot, no delta>`), or `n/a: <reason>` when no long-running serve is observed. The snapshot command is project-specific like the freshness tool; the hook validates presence and the placeholder ban only. It catches restart/crash-shaped degradation — a crash-restart mid-walk that can swallow the exact bug being probed while the app returns looking healthy — not degradation in general.

The gate blocks (exit 2) when the current step's evidence line is missing, empty, or a placeholder token (`todo`, `pending`, `inprogress`, `xxx`, `tbd`, `placeholder`).

---

## Verification Matrix: a worked example

A generic UI wave — a "saved-views panel" feature, standing in for any project's real work — with six ACs spanning four tiers plus one waiver. This is the exact shape the evidence-gate hook validates (`validate_matrix_v10`): a `stack-health:` line, a 5-column table (`AC | tier | status | evidence | auditor`, no literal `|` inside a cell), and one indented per-AC evidence block per non-waived row. **This example remains valid unchanged for v11 wave-scale plans** — v11 shares the v10 `## Verification Matrix` shape, so no v11 rewrite of the example is needed.

```
## Verification Matrix

stack-health: process restarts 0 → 0 across walk; no crash/OOM state change

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |
| AC-2 | T3 | waived | waiver: dana 2026-07-16 staging origin down; retest next wave | waived |
| AC-3 | T2 | discharged | see AC-3 | CONFIRMED |
| AC-4 | T1 | discharged | see AC-4 | CONFIRMED |
| AC-5 | T0 | discharged | see AC-5 | CONFIRMED |
| AC-6 | T4 | discharged | see AC-6 | CONFIRMED |

AC-1:
  tier-run: https://app.example/saved-views — opened the panel from the real nav entry
  fresh: app origin rebuilt token-7c2a; CDN-fronted asset origin purged
  cold-client: fresh incognito profile, no service-worker or HTTP cache
  contact: clicked "Saved Views" — panel closed → open
  readback: panel.visible === true via page-scope eval
AC-3:
  tier-run: playwright hermetic run over saved-views-list.fixture.json
  readback: rendered rows === 5, sort order matches fixture
  fixture-fidelity: derived from a captured production saved-views payload, 2026-07-12
AC-4:
  tier-run: bash test.sh — sort/filter comparator unit suite
  readback: 18/18 asserted
AC-5:
  tier-run: pnpm build && tsc
  readback: 0 type errors
AC-6:
  user-confirmed: dana 2026-07-16 walked the panel at 3 breakpoints against the design spec
```

Reading the rows: **AC-1** (T3) is a real user-visible flow, so it carries all five live-tier fields — a suite run could never honestly produce `fresh`/`cold-client`/`contact` for it (the Tier-Discharge Rule). **AC-2** (T3) is legitimately blocked this wave by a staging outage; rather than self-write `n/a` on a live-tier field, it goes through the Waiver Protocol and is recorded `waiver: <user> <date> <reason>` — exempt from its per-tier keys and from needing a `CONFIRMED` auditor verdict. **AC-3** (T2) declares its fixture's provenance so the auditor can check the fixture structurally reaches the failure the AC guards. **AC-4** (T1) and **AC-5** (T0) are substrate-only, so `tier-run` + `readback` is the whole contract. **AC-6** (T4) is a scheduled human walk, discharged by a recorded `user-confirmed:` field — never self-confirmed by an agent. Every non-waived row's `auditor` cell reads `CONFIRMED`, meaning the Independent Verification Auditor re-executed at least one evidence command per tier used and could not falsify the row; a single `REFUTED` or `UNVERIFIABLE` cell would block Step-5 closure absent a waiver.

---

## Handoff tier

Multi-session plans need fidelity across context resets. The handoff is its own evidence tier, structurally separate from verification, and **always preserved when a plan spans sessions** — independent of any flag.

A `## Handoff` section is added to the plan body with per-field caps that prevent unbounded growth:

```markdown
## Handoff
<!-- Always preserved. Updated at session end. Rewritten in place — never appended. -->

### Resume point
step: 4
sub-task: "implement predicate evaluator"
worktree: .worktrees/dispatch-hardening
branch: dispatch-hardening
last-commit: abc1234
session-count: 2

### Decisions ratified this session   <!-- max 5; RESET each session -->
### Tried and rejected                <!-- max 5; "approach → reason"; PERSISTS -->
### Discovered surprises              <!-- max 5; things code won't reveal; PERSISTS -->
### Open blockers                     <!-- max 5; each blocks a specific step -->
### Uncommitted work                  <!-- file + state, max 10 -->
### Resume protocol                   <!-- one paragraph, literal next instructions -->
```

`Decisions ratified this session` resets each session; everything else persists, capped per field. The handoff is **rewritten in place** on every trigger, never appended — a 3-session plan carries the same handoff size as a 1-session plan.

**Triggers:** session end mid-plan (`Stop` event with `sdlc-step: < 10`), context-compaction risk (~90% utilization), or an explicit user checkpoint.

**Strip:** a plan that opens and closes within one session never gets a handoff; Step 8's cleanup half strips a leftover handoff on merge.

---

## The two hooks

Two independent hooks gate two different tool events. Each reads the active plan independently — there is no shared state, no dispatch routing, no rules JSON.

### `canonical-sdlc-governing-skill.sh` — `PreToolUse | Write, Edit`

Fires on writes to `*.plan.md`, `*.spec.md`, `adr-*.md`, and `continuation*.md` under the docs root. Requires non-empty `governing-skill:` frontmatter on every such artifact.

Flag enforcement is version-routed:
- **v11 plans (current)** — the triple's presence is the gate, with **no `mode:` short-circuit (D13)**. On any v11 artifact the hook **blocks (exit 2)** on: a `mode:` line (split-brain guard), a missing or non-enum (non-whole-value) `intent:`/`rigor:`/`scale:`, a **barred** intent × scale cell (§validity), a missing discriminator/opt-in flag or `model_plan`, and — on `*.plan.md` at `sdlc-step ≥ 3` — a missing `## Verification Matrix` section. This **universal structural contract** applies regardless of intent (no `autonomous`-only gating). The hook additionally runs **log-only floor-consistency checks** (intent floor, spike cap, project floor, epic floor → one line to `.bionic/memory/sdlc-v11-audit.md` + stderr, exit 0 — never blocks).
- **v3 autonomous plans** — also requires the 5 discriminator flags + 2 opt-in flags.
- **v4 through v10 autonomous plans** — same, plus a non-empty `model_plan`.
- **v10 autonomous plans additionally** — once `sdlc-step ≥ 3`, requires a `## Verification Matrix` section in the artifact body; a `*.plan.md` at `sdlc-step: 3`+ with no matrix section blocks the write (exit 2, message names the missing section). This is the mechanism behind the "matrix locks at Step 3 approval" rule — the hook, not just the skill prose, makes a matrix-less v10 plan unwritable past that point. (v3–v10 flag/`model_plan`/matrix enforcement gates on the legacy `mode:` value; v11 re-keys it onto the triple.)
- **v1/v2 plans** — grandfathered; only the `governing-skill:` field is checked, no flag enforcement.
- **Unsupported version** — exit 2.

### `canonical-sdlc-evidence-gate.sh` — `PreToolUse | Bash`

Fires on `git commit`. Locates the newest plan, reads its `## SDLC State`, finds `current: N`, and blocks the commit if step `N`'s evidence line is missing, empty, or a placeholder.

Shape enforcement is version-routed:
- **v11 plans (current)** — wave/epic plans carry the **v10 shape table and `## Verification Matrix` validation unchanged** (v11 re-keys the gate off the triple, not the evidence shape). `scale: task` plans instead run the **rigor-keyed ledger contract**: the hook **accepts `current: T<n>`** without blocking (a false block there is a defect), then **blocks** on the addressed unit's tested-floor presence check and its own effective-rigor lanes — proof-shape (a digit + a command token) at `peer-reviewed`/`audited`, an `auditor` token on `done` rows at `peer-reviewed`/`audited`, a `critic` token on `done` rows at `audited` — and an off-enum (unresolvable) rigor cell blocks on ANY row, at ANY status, unconditionally. The ledger-shape checks on non-addressed rows (missing `## Tasks`, bad status enum, an active/done row with no evidence) stay **log-only** unless frontmatter is `rigor: audited`, where they become **blocking** too. Separately, an `audited`, `multi_agent: true` plan at `scale: wave` must carry a `## Tasks` section at all — **D7 presence** — or the commit blocks; an empty section is fine, and any present rows validate at tested-floor shape only; `scale: epic` is excluded. What stays **log-only**: the **epic merge-target** check, and the **intent-scoped Step-5 keys** — check-id `refactor-evidence` (`behavior-preservation:` present; `compat-matrix:`/`revert-plan:` present-but-may-be-empty, with an `n/a: not a migration` escape) and check-id `tune-evidence` (`baseline:`/`target:`/`re-measure:` present) — each finding appends one line to `.bionic/memory/sdlc-v11-audit.md` + stderr and exits 0. Promotion of the remaining log-only checks to blocking is a later user decision from the audit data.
- **v3/v4 plans** — run the v3 per-step shape table (v4 shares v3's table; pre-collapse step numbering).
- **v5 plans** — run the v5 per-step shape table (the gate-collapsed 0–10 shape, with an external-review step).
- **v6 plans** — run the v6 per-step shape table (v5 minus external review; 0–9).
- **v7 plans** — run the v7 per-step shape table (v6 plus the universal Step-5 `bundle-fresh:` key).
- **v8 plans** — run the v8 per-step shape table (v7 plus the universal Step-5 `drive-check:` key).
- **v9 plans** — run the v9 per-step shape table above (v8 plus the universal Step-5 `stack-health:` key).
- **v10 plans** — run the v10 per-step shape table (tests floor + `auditor:` pointer, replacing the flat universal-key stack with a discharged `## Verification Matrix` section: per-tier keys, status enum, waiver/`CONFIRMED` discipline, `false-green:`/`rewritten:` pairing). Validated at `current: 5` (the Verify-gate check, with the v10.1 mid-discharge relaxation for `pending`/`blocked` rows) and re-validated as a prefix check for `current: 6..9` — so a `REFUTED` auditor verdict discovered after Step 5 still blocks every later commit.
- **v1/v2 plans** — presence-only by default.

---

## Model and token strategy

canonical-sdlc pins the orchestrator on one strong model for the whole wave and reaches the cheaper tiers **only through subagent dispatch**. The reasoning is mechanical: switching the main model mid-wave invalidates the prompt cache (and a skill cannot enforce a main-model switch anyway), so the main model is fixed and the tiering lives in *who you dispatch to*.

Dispatch uses model family **aliases** (`model: opus`, `model: sonnet`) that resolve to the top model in each family at dispatch time — the skill never hardcodes a version, so it self-upgrades on every model release. The "currently resolves to" column is informational.

Four tiers by role (the default plan when `multi_agent: true`):

| Tier | Role | Model spec | Currently resolves to | Dispatch mechanism |
|---|---|---|---|---|
| **1 · Orchestrator** | main thread — runs Steps 1–3 directly, coordinates 4–9 | best available (detected at Step 0): Fable @ high → else top Opus @ xhigh | Fable 5 high / Opus 4.8 xhigh | the main session, fixed all wave |
| **2 · Execution-complex** | slices tagged `complex`, root-cause debugging, Step 6 review (5-axis + adversarial critic) | fresh `model: opus` | Opus 4.8 | fresh by default; `fork` only when the unit genuinely needs the inherited context |
| **3 · Execution-standard** | slices tagged `standard` — well-specified, single-subsystem, tests define done | fresh `model: sonnet` | Sonnet 5 | **fresh** (never a fork) |
| **4 · Explore / mechanical / test** | codebase search, fixtures, mechanical edits, test-writing | fresh `model: sonnet` | Sonnet 5 | **fresh** (never a fork) |

**Why the orchestrator gets the best model.** Orchestrator errors are the most expensive tokens in the system — a bad decomposition wastes every subagent it dispatches — while the orchestrator is a minority of wave spend (execution carries the volume; the pinned main thread is mostly cache reads). Fable runs at `high`, not `xhigh`: its per-effort capability clears Opus-at-xhigh on coordination work, and xhigh buys diminishing returns there.

**Slice complexity routing.** At Step 3 every Step 4 slice gets a `complexity: standard | complex` tag in the plan, which routes its dispatch **by `subagent_type` to an installed role** — `standard` → `implementor` (`model: sonnet`), `complex` → `senior-implementor` (`model: opus`); the role file, not a per-dispatch model argument, pins the model. Complex if any of: touches more than one subsystem, unresolved design decisions inside the slice, ambiguous spec surface, security-sensitive, expected root-cause debugging. When uncertain, tag `complex` — a misrouted slice costs more in rework than Sonnet saves. Opt out at Step 0 with `set exec-standard=opus` (shorthand: `set execution=opus-only`).

**Escalation ladder.** A `standard` slice that fails its gate twice re-dispatches as a fresh `model: opus` agent carrying the failure context — never a third retry on the same tier. That Opus attempt is the third and final try before the three-fail rule fires.

**Verification is never cheaper than authorship.** Step 6's 5-axis review and adversarial critic dispatch at Tier 2 (fresh `model: opus`) regardless of which tier wrote the code — Sonnet-written slices get Opus review.

**Why fresh-by-default beats fork-everything.** Pushing work to subagents keeps the main thread's token count flat, which is what extends a session before a handoff is needed. The instinct to *fork* everything achieves that — but a fork inherits the entire main-thread conversation (re-paying full context every dispatch) *and* the orchestrator's effort, making it the most expensive subagent available. A **fresh** subagent preserves the main thread's longevity exactly as well (only its summary returns to main) while carrying only the brief you hand it, at the model and harness-default effort you pick. So fresh *dominates* fork for anything that doesn't genuinely need the inherited context. Fork is the exception — reserved for context-heavy reasoning; never for vanilla/mechanical work, and never to get a cheaper model (forks ignore `model` and inherit the orchestrator's). **Under a Fable orchestrator the fork bar rises further:** Fable forks cost roughly 2× an Opus fork per token, so prefer hand-feeding context to a fresh `model: opus` agent even in borderline cases.

**Serial when slices share state.** Parallel dispatch applies to independent, stateless work. When slices share state — the one local DB, a `supabase db reset`, count-based assertions — dispatch serially: one at a time, verify, then the next, regardless of fresh-vs-fork.

**Effort is a main-thread-only dial.** There is no reasoning-effort parameter on the Agent tool — you set effort on the main session, and you cannot request "Opus high" for a subagent. The dispatch layer tiers the *model* and the *mechanism* (fresh vs fork), not effort. Forks inherit the orchestrator's effort; fresh subagents run at their model's harness default.

**`multi_agent: false`** collapses this to a single thread (no dispatch). The main model is the detected session model (`main=<detected>` in `model_plan`) and can be dialed down at Step 0, since there is nothing to offload to.

**Verification carries over.** Verify each dispatched unit's commit *fileset* (`git show --stat` plus `git status --short` for orphans), not just that tests are green; and the Step 6 (Review) adversarial critic must be **independent of whoever wrote the code** — never accept a subagent's self-graded review.

---

## Versioning and backward-compat

`canonical_sdlc_version` routes both hooks:

| Version | Status | Flag enforcement | Evidence shape |
|---|---|---|---|
| `1` / `2` | Legacy, grandfathered | None (only `governing-skill:` checked) | Presence-only (or the v2 shape if a `v2`-shaped plan declares it) |
| `3` | Prior, still enforced | 5 discriminators + 2 opt-in flags | v3 per-step shape table (pre-collapse step numbering) |
| `4` | Prior, still enforced | v3 set + required `model_plan` | v3 per-step shape table (v4 shares v3's — `model_plan` adds no evidence shape) |
| `5` | Prior, still enforced | v4 set: 5 discriminators + 2 opt-in flags + required `model_plan` | v5 per-step shape table (the gate-collapsed 0–10 shape, with an `8 External review` step) |
| `6` | Prior, still enforced | v4 set: 5 discriminators + 2 opt-in flags + required `model_plan` | v6 per-step shape table (v5 minus the external-review step: 0–9; external review dropped) |
| `7` | Prior, still enforced | v4 set: 5 discriminators + 2 opt-in flags + required `model_plan` | v7 per-step shape table (v6 plus the universal Step-5 `bundle-fresh:` key) |
| `8` | Prior, still enforced | v4 set: 5 discriminators + 2 opt-in flags + required `model_plan` | v8 per-step shape table (v7 plus the universal Step-5 `drive-check:` key) |
| `9` | Prior, still enforced | v4 set: 5 discriminators + 2 opt-in flags + required `model_plan` | v9 per-step shape table (v8 plus the universal Step-5 `stack-health:` key) |
| `10` | Prior, still enforced | v4 set: 5 discriminators + 2 opt-in flags + required `model_plan`, plus a required `## Verification Matrix` section once `sdlc-step ≥ 3` — gated on the legacy `mode:` value | v10 per-step shape table — replaces the flat universal-key stack with a pre-registered, per-AC `## Verification Matrix` (tier-discharge, per-tier evidence keys, independent auditor, Waiver Protocol) |
| `11` | **Current** | The `intent · rigor · scale` triple replaces `mode:`; the v10 structural contract (5 discriminators + 2 opt-in + `model_plan` + matrix at `sdlc-step ≥ 3`) becomes **universal** across every intent (D13) — no `mode:` short-circuit; the governing-skill hook blocks a `mode:` line, a non-enum triple, and barred intent × scale cells | v10 shape table + matrix **unchanged** on wave/epic plans; adds `scale: task` ledger addressing (`current: T<n>`), **blocking and rigor-keyed** — three cumulative lanes on the addressed row (tested floor; peer-reviewed proof-shape + `auditor` token; audited + `critic` token), plan-level ledger-shape strictness once frontmatter is `rigor: audited`, and D7 dispatched-task ledger presence on audited multi-agent waves — tightened in place, no `v12`; the epic merge-target check and the intent-scoped Step-5 keys (`refactor`/`tune`) remain **log-only** (append to `.bionic/memory/sdlc-v11-audit.md`, never block) |

Legacy plans (v1/v2) run grandfathered indefinitely: the governing-skill hook checks only `governing-skill:`, and the evidence gate uses presence-only. v3 plans remain enforced under the prior 5 + 2 contract. v4 through v11 require `model_plan`. v3/v4 plans run the v3 per-step shape table (v4 shares v3's); v5 plans run the v5 shape table; v6 plans run the v6 shape table; v7 plans run the v7 shape table; v8 plans run the v8 shape table; v9 plans run the v9 shape table; v10 and v11 wave/epic plans run the v10 shape table (see [Verification Matrix: a worked example](#verification-matrix-a-worked-example)). **Never retrofit a newer version's requirements onto an older plan** — an in-flight plan would start blocking mid-wave; this covers every universal-key addition (v7 `bundle-fresh:`, v8 `drive-check:`, v9 `stack-health:`), the v10 Verification Matrix, and the v11 axis triple alike. **v≤10 plans keep their `mode:` vocabulary forever** — a `mode:`-declared plan is never retrofitted to the triple, and the governing-skill hook keeps enforcing its `mode:`-gated flag contract unchanged. The one sanctioned mid-life version bump is the reopened-wave upgrade path (v9→v10; see the v10 evidence-shape section above).

### Why the ladder looks like this

Each version bump exists because something broke or a threshold was crossed — not because a version number felt stale:

- **v5** added a gate-collapsed 0–10 shape with an `8 External review` step; **v6** dropped it again (external review folded into the Step 6 adversarial critic) — the two versions bracket a reversed experiment, not a straight-line addition.
- **v7, v8, v9** each added exactly one universal Step-5 proof key, one failure axis at a time: `bundle-fresh:` (artifact — is the serve actually built from this working tree), `drive-check:` (contact — did a trusted interaction actually touch the app), `stack-health:` (runtime — did the serving stack survive the walk without a masking restart). Every key was proof-or-`n/a`, placeholder-banned, project-specific in format.
- **A recorded design threshold** marked where this ladder was heading: a *fifth* universal Step-5 key would force prose-side consolidation into one structured contract rather than another flat bullet.
- **v10** is that consolidation, triggered pre-emptively rather than by shipping a fifth key. The flat four-key stack (`devtools-trace:`/`bundle-fresh:`/`drive-check:`/`stack-health:`) is retired for new plans in favor of the pre-registered Verification Matrix — one row per AC, tiered T0–T4, discharged by an independent auditor rather than self-graded. v9-and-earlier plans are unaffected; the retrofit ban means they keep running their original tables for the rest of their life.
- **v10.1** is a hook revision, not a new plan version — `canonical_sdlc_version` stays `10`. It fixes an enforcement-shape bug found by v10's first consumer: the Verify gate demanded the fully-discharged matrix on every commit *at* `current: 5`, leaving mid-walk corrective commits no honest home (the observed workaround was regressing `current:` to 4). v10.1 lets `pending`/`blocked` rows defer their per-tier keys — and the `auditor:` pointer — until closure, moves the full bite to the 5→6 advance (where the `CONFIRMED` rule already lived), and enum-checks the now-load-bearing status cell.
- **v11** splits the single `mode` axis into the orthogonal `intent · rigor · scale` triple. `mode` conflated three independent questions — what kind of work, how rigorous, how big — so a `spike` couldn't be `audited` and an `autonomous` build couldn't drop to a task-sized lane; the triple lets each vary independently (subject to the floors). The v10 evidence machinery is retained wholesale — the shape table and matrix are unchanged on wave/epic plans — because the axis split is a *classification* change, not an evidence-shape change. v11's new judgment surfaces (task-ledger addressing, epic merge-target, and the intent-scoped `refactor`/`tune` Step-5 keys) shipped **log-only** at first, appending to `.bionic/memory/sdlc-v11-audit.md` and never blocking — the same "kept because it caught something" discipline the ladder runs on. The task-ledger checks have since been tightened **in place, under the same `canonical_sdlc_version: 11`** (no `v12`): ledger-row evidence is now **blocking and rigor-keyed** (§Task-scale ledger enforcement), and an audited multi-agent wave must carry its dispatched-task ledger section at all (D7 presence). The epic merge-target check and the intent-scoped Step-5 keys remain log-only, promoted only if the audit data one day earns it.

### Pilot and sunset (v10)

> **Pilot:** the first consumer is a reopened wave using the upgrade path; the orchestrator records the overhead delta (wall-clock + agent-runs attributable to matrix + auditor). **Sunset:** any v10 element that has caught nothing across 5 waves and carries nonzero per-wave cost is a demotion candidate at the next version review.

This is the same discipline v10 itself imposes on evidence — a mechanism is kept because it caught something, not because it shipped once.

---

## RCA shape

The `incident-response` intent's Step 7 produces `incidents/NNNN-<slug>/rca.md` instead of an ADR — a postmortem, backward-facing where an ADR is forward-facing. The full required shape, section by section:

- **Summary** — one paragraph: what happened, impact, duration.
- **Timeline** — detection → mitigation → fix deployed, with timestamps.
- **Root cause** — the single underlying technical cause, stated plainly. Not a list of contributing factors; the one thing that, absent, the incident would not have happened.
- **Contributing factors** — the conditions that turned the root cause into an actual incident (a root cause without contributing factors usually means the analysis stopped one layer too early).
- **The fix** — what was changed, with a link to the commit(s).
- **Prevention** — concrete measures. Each measure must link to a commit or a ticket — "we'll be more careful" is not a prevention measure.
- **Monitoring gap analysis** — either "monitoring caught this at `<timestamp>`, no gap" with a link to the alert/dashboard, OR a description of the gap and a link to the commit that closed it. The default assumption is a gap exists; "no gap" must be proven, not assumed.

An RCA missing any of these seven sections is incomplete regardless of how thorough the prose reads — the shape itself is the checklist.

---

## Configuration: the Step-0 wizard

Step 0 is mandatory for new plans (`canonical_sdlc_version: 11`, current). It sets every plan-shaping flag deliberately, with explicit user confirmation, in seven sub-steps:

1. **Pre-flight environment check** — verify `.bionic/` root, resolve the docs root (`<project>/.bionic/config.yaml`'s `docs-root:`, default `.bionic/docs`), ensure `{specs,plans,adrs,incidents}/` exist, `mkdir -p .bionic/tmp/`, and verify both hooks are installed and executable.
2. **Classify the triple** — infer `<intent> · <rigor> · <scale>` **silently** from the request's verbs and named artifacts (intent), the scale-keyed default plus every derivable floor (rigor, max-wins), and the session-size signal (scale), then surface it in the confirmation display for a `confirm`-or-override. **Interview only by exception** — fire 1–3 targeted questions only on an intent collision (the standing gray zones: mechanism-swap, reference-content), a suspected-but-unconfirmed floor trigger, or genuinely unclear scale. There is no interview mode; deep requirements elicitation stays at Step 1. Canonical: [SKILL.md §Step 0](SKILL.md).
3. **Infer recommended values** — from repo files (`tsconfig.json` → `typescript`, `Cargo.toml` → `rust`, …) and conversation keywords (surface type, deploy target, UI). This includes the integration branch: waves inherit it from the epic plan; standalone plans default to the current mainline branch or `main`.
4. **Derive the Verification Matrix** — one row per acceptance criterion from the spec, tiered by the inference defaults (user-visible change → T3; engine-divergent → T2-both-engines + T3; pure substrate → T1/T2 with a one-line justification; perceptual/design fidelity → T3 cold-client, T4 available; docs/ADR → T0/none). Stored as `pending` rows; locks at Step 3 approval.
5. **Present the confirmation display** — the triple, flags, model plan, environment status, integration branch, and **every matrix row**, each with its inference rationale. The `integration-branch:` line and the matrix block are both load-bearing (Step 8 merges every wave into the former; the latter is what Step 5 discharges) and must never be dropped from the display, even past 12 ACs.
6. **Block until explicit confirmation** — no timeout, no implicit acceptance. The confirmation display must always render **in full** — never elided, summarized, or truncated; the user approves exactly what they can see. A matrix tier can be overridden inline (`set verify(AC-2)=T2, confirm`) before it locks.
7. **Task-list creation is the immediate next action after approval** — announce it, create the full TaskCreate list (`0:`…`9:`), mark `0:` completed, then transition to Step 1. Nothing else runs in between.

### The confirmation display

```
═══ Plan Configuration — confirm before Step 1 ═══
environment:
  bionic-root:  /Users/me/proj/.bionic       [verified]
  docs-root:    .bionic/docs                 [default]
  bionic-tmp:   /Users/me/proj/.bionic/tmp   [ready]
  hooks:        evidence-gate, governing-skill  [all installed]

slug: <inferred-from-conversation>

Triple:                          [the run's shaping decision — see the axis model]
  intent:  build                 [inferred: request adds new machinery — machinery test]
  rigor:   audited               [inferred: wave-scale default (D11); no floor raises it]
  scale:   wave                  [inferred: one-session chunk, not multi-session]

integration-branch: main         [inferred: current branch — Step 8 merges every wave here]

Discriminator flags:
  surface_type:    api          [inferred: "REST endpoint" in convo]
  language:        typescript   [inferred: tsconfig.json]
  has_ui:          false        [no UI mentioned]
  multi_agent:     true         [default — parallel-dispatch fit]
  deploy_target:   none         [no deploy signal]

Opt-in flags:
  cleanup_on_finish: true       [Step 8 (cleanup half) wipes .bionic/tmp/ on close]
  use_worktree:      false      [work on current branch]

Model plan:                      [multi_agent=true → tiered dispatch]
  orchestrator:  fable-5 high    [detected session model; main thread, fixed all wave]
  exec-complex:  opus            [fresh model:opus — slices tagged complex, debugging, Step 6 review]
  exec-standard: sonnet          [fresh model:sonnet — slices tagged standard]
  explore/test:  sonnet          [fresh model:sonnet — search, mechanical, tests]

Verification Matrix:            [locked at Step 3 approval — every row shown, never sampled]
  stack-health: <once-per-walk-session snapshot, or n/a: reason>
  | AC   | tier | status  | evidence | auditor |
  | AC-1 | T3   | pending | see AC-1 |         |   [inferred: user-visible behavior → T3]
  | AC-2 | T1   | pending | see AC-2 |         |   [inferred: pure logic → T1]

Reply "confirm" to accept, or specify overrides:
  e.g. "set use_worktree=true, set exec-standard=opus, set verify(AC-2)=T2, then confirm"
```

### Override DSL

The reply is parsed against a small grammar:

```
reply        := overrides? "confirm"
overrides    := override ("," override)* ","?
override     := "set" axis "=" axis-value
              | "set" flag "=" value
              | "set" "verify" "(" AC-id ")" "=" tier
              | "change" flag "to" value
axis         := "intent" | "rigor" | "scale"
```

Accepted: `confirm`; `set use_worktree=true, confirm`; `set surface_type=graphql, set language=python, confirm`; `set integration-branch=develop, confirm`. **Triple override:** `set intent=refactor, set rigor=audited, confirm` reclassifies before Step 1; `set scale=epic, confirm` switches to epic-scoping. **Floors are upward-only** — a `rigor` override *below* a derivable floor (e.g. `set rigor=tested` on `incident-response`, whose intent floor is `audited`) is refused **by the skill, not by the harness**: warn, name the binding floor, keep the floor value. No code rejects a sub-floor value; the only check that reads rigor floors, `canonical-sdlc-governing-skill.sh`'s floor-consistency check, is log-only (D14) — it records the inconsistency and allows the write. An upward override is always accepted. An override naming a **barred** intent × scale cell is rejected with the reason. Model-plan keys are valid targets: `set orchestrator=fable-high, confirm` (multi_agent=true), or `set main_model=sonnet, confirm` (multi_agent=false dial-down). **Matrix tier override:** `set verify(AC-B2.1)=T2, confirm` retiers a matrix row before it locks. On accept, the final values are written into frontmatter literally — every flag as an explicit `<key>: <value>` line, plus the `intent:`/`rigor:`/`scale:` triple and `model_plan`; the locked `## Verification Matrix` section is written into the plan body at Step 3.

**Mid-plan reconfiguration:** edit the frontmatter directly; the new value takes effect on the next hook read.

### The quick-reference card (explain / help)

Canonical card — rendered verbatim by `explain` and by a bare `help` invocation; content mirrors the axis tables and must be updated with them.

```
── canonical-sdlc quick reference ──

Reply "confirm" to accept the inferred triple, or override any axis first
(examples at the bottom). One value per axis:

intent — what kind of work is this?
  build              new capability, or capability restored by adding new machinery
  bugfix             restore intended behavior within the existing design
  refactor           change structure, preserve behavior (upgrades, migrations, removals)
  tune               move a NAMED measurement toward a target (latency, size, a UX score)
  spike              timeboxed research or prototype — ships no code; the writeup is the deliverable
  incident-response  a live deployed surface is broken for its users; the clock matters

rigor — how hard should the evidence try to lie? (each tier includes the ones below)
  tested         TDD on every change + the Verification Matrix + structured self-review
  peer-reviewed  adds a separate spec + an independent auditor who tries to falsify your evidence
  audited        adds an independent adversarial critic who tries to break the code itself

scale — how much work?
  task   sub-session unit, several per session — ledger line, no per-task plan file
  wave   one session (the default)
  epic   multi-session — scoping run only (Steps 0–3), carves the work into waves

Floors push rigor UP, never down: incident-response and security/privacy-touching
work floor at audited; a project or epic can declare its own rigor-floor. spike is
capped at tested (it ships no code).

Override examples:
  set intent=refactor, confirm
  set rigor=audited, set scale=task, confirm
  set verify(AC-2)=T2, confirm
```

---

## Quick reference

| Step | Gate | Evidence |
|---|---|---|
| 0. Configure | Frontmatter has `canonical_sdlc_version: 11` + the `intent`/`rigor`/`scale` triple + 5 discriminator + 2 opt-in flags + `model_plan`; `## Verification Matrix` derived; user confirmed; TaskCreate list created | Confirmation line in `## SDLC State` |
| 1. Ideate | Refined idea + "Not Doing" list; alternatives lens cites prior artifacts | Pointer to ideate body in spec |
| 2. Spec | Every requirement has an acceptance criterion | Pointer to spec doc |
| 3. Plan | No placeholders; `integration-branch:` declared; matrix locked; Step 4 expanded into slice tasks; approval | Pointer to plan body |
| 4. Implement | Every slice has a test that was RED first; worktree created if `use_worktree: true` | Slice-list pointer; worktree fields when applicable |
| 5. Verify (gate) | Tests/build pass (`pass == total`); every matrix row discharged at its tier or waived; independent auditor `CONFIRMED` on every non-waived row | `cmd:`/`pass:`/`total:`/`output:` **and** `auditor:` pointer **and** a discharged `## Verification Matrix` (v9-and-earlier plans keep their flat `devtools-trace:`/`bundle-fresh:`/`drive-check:`/`stack-health:` keys instead — see [Versioning](#versioning-and-backward-compat)) |
| 6. Review (gate) | Every one of the 5 axes has a verdict; adversarial critic attached (mandatory at `audited` rigor — into which `incident-response` floors) | Pointer to 5-axis review body + critic findings |
| 7. Document decisions | Every significant decision has a record | `adr:` / `rca:` / `n/a:` |
| 8. Integrate & close | Wave merged into the declared `integration-branch`; worktree removed; `.bionic/tmp/` wiped; all tasks completed; `cleaned:` stamped | `merge:`/`worktree-removed:` **and** `cleanup:`/`tmp-wiped:`/`tasks-completed:` or `cleanup: n/a` |
| 9. Ship | Checklist complete; rollback documented; `continuation.md` written; gap closed (incident) | `deploy:`/`verified-at:`/`monitor:` or `n/a:` |
| — Commit rhythm | Cross-cutting; per-step checkpoint commit (not a numbered step) | Atomic commits; scope matches spec |

---

## Pointers

| Resource | Path |
|---|---|
| Skill prose (Claude reads at runtime) | [`SKILL.md`](SKILL.md) |
| Evidence-gate hook | [`canonical-sdlc-evidence-gate.sh`](../../hooks/canonical-sdlc-evidence-gate.sh) |
| Governing-skill hook | [`canonical-sdlc-governing-skill.sh`](../../hooks/canonical-sdlc-governing-skill.sh) |
| Diagram sources | [`diagrams/`](diagrams/) |
