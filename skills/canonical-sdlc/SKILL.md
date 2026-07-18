---
name: canonical-sdlc
description: Use when starting a large-scale development effort (new feature, architectural change, multi-day project) or when picking the skill for the current SDLC step. Routes to the canonical skill per step and enforces that every applicable step is walked before completion.
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

## Overview

This skill constrains how large-scale development efforts are executed. The SDLC steps exist because they lead to better outcomes — each step contributes a dimension of fidelity (scope, contract, plan, proof, review, decision record, release discipline) that no other step supplies. Without this skill, Claude truncates the lifecycle on any given effort: individual steps feel skippable in isolation, but the compounding loss of fidelity is invisible mid-effort and surfaces as rework, lost decisions, and features that look complete but aren't production-grade.

**Core principle: NO STEP SKIPPED WITHOUT A DECLARED FAST-PATH. NO COMPLETION WITHOUT EVIDENCE FROM EVERY APPLICABLE STEP.** (formalized below as The Iron Law).

**Layer:** Governance (process constraint). Loads when a large-scale effort begins or when picking the skill for the current step.

**Routing principle — superpowers vs agent-skills.** The two plugins are interleaved because they solve orthogonal problems:

- `superpowers:` owns **discipline anchors** — planning, TDD, debugging, verification, review response, worktree isolation, parallel dispatch. Its rules are calibrated against Claude's known failure modes (fabrication, sycophancy, rationalization).
- `agent-skills:` owns **content rubrics** — spec shape, 5-axis review, 6-lens ideation, domain deep-dives (security, performance, UI). Supplies the *shape* each step's artifact should take.

On overlap, route by kind, not by plugin. On ties, prefer `superpowers:`.

**Tooling principle — CLI-first.** Prefer CLIs over MCP servers. An MCP server is an always-on context tax (its tool schemas load every session); a CLI is pay-per-call (zero cost until invoked). Default to the CLI for any capability a CLI covers; reserve an MCP server only for capabilities no CLI exposes, or for rare deep-inspection calls where the richer interface outweighs the context cost. In this lifecycle the only MCP-coupled work is the **browser tiers (T2/T3) of the Verify gate (Step 5)**: browser *driving* goes through `playwright-cli` (the `browser-verify` skill), and the chrome-devtools MCP is reserved for deep inspection (Lighthouse, performance-trace analysis, heap/CPU profiling, network throttling) that the CLI cannot do.

## Verification model (gate → contract → tier → tool)

Verification in this lifecycle is structured at four levels. Conflating them is what produces redundant or skipped checks.

- **Gate** = the principle being satisfied. Two gates: **Verify** ("does it work?", Step 5) and **Review** ("is it well-made?", Step 6).
- **Contract** = the **Verification Matrix** — one row per acceptance criterion, derived at Step 0, locked at Step 3 approval (§Step 0). The Verify gate discharges the matrix row-by-row; nothing is verified "in general," only against a pre-registered row.
- **Tier** = *how hard the evidence tries to lie*, from browser-verify's **T0–T4 ladder** (T0 static → T1 unit → T2 hermetic → T3 live agent-drive → T4 human walk). browser-verify is the canonical home of the ladder and its "the lie each tier kills" framing — reference it, do not restate it. Each matrix row carries a tier; the **Tier-Discharge Rule** (Step 5) governs how the row is discharged.
- **Tool** = the instrument for a tier, default → escalation. Browser tiers (T2/T3): `playwright-cli` (default, via `browser-verify`) → escalate to the chrome-devtools MCP (`agent-skills:browser-testing-with-devtools`) **ONLY** for deep inspection the CLI can't do (Lighthouse, perf-trace analysis, heap/CPU profiling, network throttling).

Review is unchanged in shape: structured 5-axis self-review (**always**) plus an **INDEPENDENT** adversarial critic (**mandatory at `audited` rigor** — into which `incident-response` floors — never self-graded). The Verify-gate **auditor** (present from `peer-reviewed` up) and the Review-gate **critic** (present at `audited`) are distinct: the auditor falsifies the *evidence*, the critic falsifies the *code* (see Steps 5–6).

**Why lower tiers are proxies (the locator model).** Every tier below the live walk tests a proxy, and each reports PASS at its own blind spot: unit tests pass on mocked seams; hermetic tests pass on fixtures that may not match the real data shape; a ref-walk over a bare canvas drives nothing yet "completes"; a screenshot of a degenerate frame satisfies "something rendered." A higher tier exists precisely to kill the lie the tier below cannot see. Mock-green + real-red is not a contradiction but a **locator** — the bug lives in exactly the layer the proxy elides. The matrix pins each AC to the tier that can actually catch its failure, so no AC is discharged by a proxy that structurally cannot reach its bug.

### Decomposition unit per step

The *slice* (atomic RED→GREEN commit) stays **exclusive to Step 4 Implement**. Other fanned-out steps decompose by their own unit:
- **Step 5 Verify** decomposes by **matrix row** — one unit per acceptance criterion (`5/<AC-id>`), operating over Step 4's slices.
- **Step 6 Review** decomposes by **axis × stance** (shard by subsystem on large diffs).
- **Step 8 Integrate & close** is **atomic** — a single task.

Generalize the `<step>/<unit>:` task-naming so any fanned-out step labels its units: `4/<slice>`, `5/<AC-id>`, `6/<axis-or-stance>`. Step 8 stays one task. See §Task Tracking.

**REQUIRED SUB-SKILLS.** The `needs`-declared skills load only when the step that invokes them is active.

## Load-time Announcement

When this skill is loaded, the **first user-facing action** is to announce the declared **triple** — `<intent> · <rigor> · <scale>` — in the form (D7):

> **Canonical SDLC engaged — `<intent>` · `<rigor>` · `<scale>` (`<consequence summary>`).**

The `<consequence summary>` names what the declared rigor buys at that scale — derive it from the rigor ladder's *what-you-get* column (§Rigor — how hard the evidence tries to lie) plus the scale's artifact story (§Scale — the decomposition unit). Examples:

> **Canonical SDLC engaged — build · peer-reviewed · wave (spec + full matrix + independent auditor + 5-axis review).**
> **Canonical SDLC engaged — bugfix · tested · task (RED repro → GREEN, matrix at tier, self-review — no mandatory critic).**
> **Canonical SDLC engaged — incident-response · audited · wave (adversarial critic + per-step checkpoints + expanded stop-and-wake).**

If the triple is not yet declared, announce that it is pending and enumerate the three axes with their value sets:

> **Canonical SDLC engaged — triple pending declaration. Declare one value per axis:**
> - **intent** — `build` · `bugfix` · `refactor` · `tune` · `spike` · `incident-response`
> - **rigor** — `tested` · `peer-reviewed` · `audited` (defaults per intent; floors may push up — §Rigor floors and lifecycle)
> - **scale** — `task` · `wave` (default) · `epic`

No other work proceeds until the triple is declared. (Step 0 infers the triple silently and presents it for confirmation — declaration is normally a `confirm`, not a from-scratch answer; see Step 0.)

## Taxonomy

| Tier | Word | Definition |
|---|---|---|
| 1 | **epic** | Large body of work spanning multiple sessions. |
| 2 | **wave** | One-session chunk of an epic. If it doesn't fit, split into more waves. |
| 3 | **step** | One of the canonical-sdlc steps (0–9) inside a wave. |
| — | *slice* | *Informal.* An atomic implementation commit inside a wave's Step 4. A wave can have 1 or many slices. Slices don't get their own plan files. |

**Scale IS this taxonomy.** The `scale:` axis (§Scale — the decomposition unit) declares which of these units a run occupies: `scale: epic` = tier 1, `scale: wave` = tier 2. The one addition the axis makes is `scale: task` — a sub-session unit *below* a wave (several per session, no per-task plan file), which the tier table above does not name. `step` and `slice` are never `scale:` values — they are the units *inside* a wave, not a declared run size.

**Naming convention.** Artifacts live in a directory-per-epic layout with zero-padded epic numbers and human-readable slugs. One slug per epic is chosen at epic-scoping time (`scale: epic`) and used across `specs/`, `plans/`, and `adrs/`:

```
<docs-root>/specs/epic-02-v2-product-pass/
  epic.spec.md
  wave-01-checkout-refactor.spec.md

<docs-root>/plans/epic-02-v2-product-pass/
  epic.plan.md
  wave-01-checkout-refactor.plan.md

<docs-root>/adrs/epic-02-v2-product-pass/
  adr-001-<slug>.md
```

- **Epic dir:** `epic-NN-<epic-slug>/` — `NN` is two-digit zero-padded; `<epic-slug>` is kebab-case.
- **Wave file:** `wave-NN-<wave-slug>.<kind>.md` where `<kind>` ∈ {`spec`, `plan`}. ADRs number independently per epic.
- **Epic-level files:** `epic.spec.md`, `epic.plan.md` at the root of the epic dir.

**Incident naming convention.** `incident-response` mode uses a parallel structure rooted at `<docs-root>/incidents/`:

```
<docs-root>/incidents/NNNN-<incident-slug>/
  spec.md      # incident scope, blast radius, closure criteria
  plan.md      # debug + fix plan with ## SDLC State
  rca.md       # postmortem root cause analysis — required artifact
```

`NNNN` is four-digit zero-padded.

**Spike writeup convention.** `spike` mode produces a single file at `<docs-root>/spikes/spike-<slug>-<YYYYMMDD>.md`. No directory, no worktree, no ADR.

Reject deviations from these conventions unless there is a named, recorded reason.

## Epic vs. Wave Execution

The skill runs at two scales:

1. **Epic scoping** — `scale: epic`. Runs Steps 0–3 only. Produces `epic.spec.md` + `epic.plan.md`. Carves the work into waves. Does **not** execute Steps 4–9.
2. **Wave execution** — the default (`scale: wave`). Runs the full applicable step set for one wave under whatever intent the run declares (`build`, `bugfix`, `refactor`, `tune`, `spike`, `incident-response`). Each wave re-enters Steps 1–3 at greater depth than the epic plan supplied; **trust but verify** the epic's assumptions, do not re-derive from scratch.

## The Iron Law

```
NO STEP SKIPPED WITHOUT A DECLARED FAST-PATH.
NO COMPLETION WITHOUT EVIDENCE FROM EVERY APPLICABLE STEP.
```

## Parallel by Default

Every step looks for parallelizable work. If 2+ subtasks have no data dependency,
dispatch subagents in one Agent call batch. Concretely: Step 1 parallel lens
exploration; Step 2 surface specialist + UX critic; Step 3 alternatives in parallel
forks; Step 4 independent slices as parallel implementers; Step 5 parallel by matrix
row (rows share no state); Step 6 the 5 axes plus critic framings in parallel;
Step 7 ADR + RCA drafts.

The default is parallel. Justify sequential. Parallel applies to **independent, stateless** work;
when slices share state (the one local DB, `supabase db reset`, count-based assertions), dispatch
**serially** — one at a time, verify, then the next — regardless of fresh-vs-fork. See
§Model & Token Strategy for which model tier and dispatch mechanism each unit should use.

## Model & Token Strategy

Three objectives, in priority order, govern every dispatch decision: (1) **the orchestrator stays free** — the main thread does coordination and decisions only, heavy lifting goes to subagents, which is what lets the developer steer in real time; (2) **maximize wave/session duration** — main-context growth is the scarce resource, so subagents return summaries, never payloads; (3) **token economy serves 1 and 2** — cheaper tiers are reached **only through subagent dispatch**, a means to those goals, not an end.

**What "heavy lifting" means — and what it never means.** Delegation covers *research, execution, verification, and review* — **never synthesis or judgment**. The orchestrator keeps the work only it should do: Steps 0–3 (scoping, spec, plan), slice decomposition, complexity tagging, and every approval-shaped decision stay on the main thread — the most powerful model — because an orchestrator error wastes every subagent it would dispatch. Within Steps 0–3 only *research* fans out (parallel Explore agents); the spec, plan, and decisions are written in the main thread. The Tier-1 row below encodes exactly this split.

Pin the orchestrator on one strong model for the whole wave. Switching the *main* model mid-wave
invalidates the prompt cache (and a skill cannot enforce a main-model switch anyway) — so the main
model never changes; the tiering lives in *who you dispatch to*, not in re-configuring yourself.
This is the operational form of "guard your context — offload to subagents."

**Aliases, never pinned versions.** Subagent dispatch uses model family aliases — `model: opus`,
`model: sonnet` — which resolve to the top model in that family at dispatch time. The skill never
hardcodes a version; the "currently resolves to" column below is informational and may lag
releases without breaking anything.

**Four tiers by role** (the default plan when `multi_agent: true`):

| Tier | Role | Model spec | Currently resolves to | Dispatch mechanism |
|---|---|---|---|---|
| **1 · Orchestrator** | main thread — runs Steps 1–3 directly, coordinates 4–9 | **best available** (detected at Step 0): Fable @ **high** → else top Opus @ **xhigh** | Fable 5 high / Opus 4.8 xhigh | the main session (human-set at start; **fixed all wave**) |
| **2 · Execution-complex** | slices tagged `complex`, root-cause debugging, Step 6 review (5-axis + adversarial critic) | fresh **`model: opus`** | Opus 4.8 | fresh by default; `fork` only when the unit genuinely needs the inherited conversation/context |
| **3 · Execution-standard** | slices tagged `standard` — well-specified, single-subsystem, tests define done | fresh **`model: sonnet`** | Sonnet 5 | **fresh** (never a fork) |
| **4 · Explore / mechanical / test** | codebase search, fixtures, mechanical edits, test-writing | fresh **`model: sonnet`** | Sonnet 5 | **fresh** (never a fork) |

**Orchestrator = best available, detected at Step 0.** Orchestrator errors are the most expensive
tokens in the system — a bad decomposition or wrong plan wastes every subagent it dispatches —
while the orchestrator itself is a minority of wave spend (execution subagents carry the volume;
the pinned main thread is mostly cache reads). So the orchestrator gets the highest tier
available, at the effort that tier needs: **Fable at `high`** (its per-effort capability clears
Opus-at-xhigh on coordination work; xhigh on Fable buys diminishing returns there) or **top Opus
at `xhigh`**. At Step 0, read the session model from your own system prompt and derive the
orchestrator line of `model_plan` from it. If the session model is below the Opus tier, warn and
recommend switching via `/model` before the wave starts — still the user's call, fixed once
confirmed.

**Slice complexity routing (the execution split).** The top Sonnet is near-Opus on well-specified
coding work at a fraction of the price — the bulk of execution volume belongs there. At Step 3,
every Step 4 slice gets a `complexity:` tag in the plan; the tag routes the dispatch:

- **`complex` → Tier 2 (fresh `model: opus`)** if ANY of: touches more than one subsystem;
  unresolved design or architecture decisions inside the slice; ambiguous spec surface;
  security-sensitive; expected root-cause debugging of unfamiliar internals.
- **`standard` → Tier 3 (fresh `model: sonnet`)** when the slice is well-specified,
  single-subsystem, and its tests define done.
- **When uncertain, tag `complex`.** The savings come from clear-cut standard slices, not from
  optimistic tagging — a misrouted complex slice costs more in rework than Sonnet saves.

**Escalation ladder.** If a `standard` slice fails its gate **twice**, re-dispatch it as a fresh
`model: opus` agent carrying the failure context — never a third retry on the same tier. These
failures still count toward the three-fail rule (§Escalation Protocol).

**Verification is never cheaper than authorship.** Step 6's 5-axis review and adversarial critic
dispatch at Tier 2 (fresh `model: opus`) regardless of which tier wrote the code — Sonnet-written
slices get Opus review. The savings live in writing, not judging. The critic additionally remains
independent of whoever wrote the code (see Step 6).

**Fresh by default, fork by exception — the cost rule.** A subagent spends tokens on two axes:
*context* (the input it carries) and *effort* (the thinking it does). A **fork** is expensive on
both — it inherits the entire main-thread conversation (re-paying full context on every dispatch)
*and* the orchestrator's xhigh effort. A **fresh** subagent is cheap on both — only the brief you
hand it, the model you pick, and the harness-default (sub-xhigh) effort. Critically, **a fresh
subagent preserves the main thread's longevity exactly as well as a fork** — only its final
summary returns to the main context. So for the goal of keeping the orchestrator alive, fresh
*dominates* fork: same upside, a fraction of the spend.

- **Dispatch nearly everything, fresh-first.** Under `multi_agent: true`, push almost every
  substantive Step 4+ unit — even vanilla ones — to a **fresh** subagent. Inline only
  truly-trivial one-line edits where even dispatch overhead exceeds the benefit.
- **Fork only** when hand-feeding the needed context to a fresh agent would cost more than the
  fork's inheritance overhead — i.e. genuinely context-heavy reasoning that depends on the
  accumulated conversation. **Never fork a vanilla or mechanical task** — that is the most
  expensive way to do the cheapest work. **Never fork to get a cheaper model** — forks ignore
  `model` and inherit the orchestrator's (a Fable-orchestrator's forks are Fable, not Opus).
- **Under a Fable orchestrator the fork bar rises.** Fable forks pay roughly 2× Opus per token
  AND re-pay the entire main-thread context on every dispatch. Prefer hand-feeding context to a
  fresh `model: opus` agent even in borderline cases.
- **Serial when slices share state** (see Parallel by Default above).

**Effort is a main-thread-only dial.** There is no reasoning-effort parameter on the Agent tool.
Set effort on the main session (`/model`); you cannot request "Opus high" for a subagent. Tier the
*model* and the *mechanism*, never assume a selectable execution effort below the main thread.
Forks inherit the orchestrator's effort; fresh subagents run at their model's harness default.

**`multi_agent: false`** — everything runs on the main orchestrator, no dispatch (Tiers 2–4 N/A).
The main model is the detected session model (`main=<detected>` in `model_plan`); **dial-down is
offered at Step 0** since there is nothing to offload to.

**Verification carries over from the multi-agent memory** (`feedback_multi_agent_fork_orchestration`):
verify each dispatched unit's commit *fileset* (`git show --stat` + `git status --short` for
orphans), not just that tests are green; and the Step 6 adversarial critic must be **independent
of whoever wrote the code** — never accept a subagent's self-graded review.

## Task Tracking (mandatory)

Every canonical-sdlc run maintains a TaskCreate list with this naming convention:
- `<step>: <description>` for single-step work (e.g., `3: Write plan.md`)
- `<step>/<unit>: <description>` for any fanned-out step, where `<unit>` is that step's decomposition unit (see §Decomposition unit per step): `4/<slice>` (e.g., `4/2: implement evaluator predicate`), `5/<modality-or-case>` (e.g., `5/browser-golden-path`), `6/<axis-or-stance>` (e.g., `6/architecture`, `6/critic`).

Rules:
- Create the task list at end of Step 0 with one task per planned step (0–9).
- At Step 3 (Plan), expand Step 4 (Implement) into one task per slice.
- Fan out Steps 5 and 6 into their units when they are dispatched in parallel; Step 8 (Integrate & close) stays a single atomic task.
- Mark a task `in_progress` when starting it; `completed` immediately when done. Never batch completions.
- When a sub-agent finishes, the main thread updates the corresponding task.
- Step 8 (Integrate & close) verifies all tasks are `completed` before merge.

**Golden rule of display.** The task list is a signal surface, not a narration log:

- **No filler.** No explanatory or decorative entries that carry no state — every task is a real unit of work with a real status.
- **Naming convention always.** Every entry follows `<step>: <description>` / `<step>/<unit>: <description>` — no freeform titles.
- **The current step's slices take primary billing.** While a fanned-out step has pending units (in-progress or to-do), its `<step>/<unit>` tasks are the foreground of the list; subsequent steps remain collapsed as single `N:` entries. A step expands into units only when it becomes current (Step 4's slices are the one exception — they expand at Step 3, because the plan defines them).

This is non-negotiable. The list is the visible progress surface for the user.

## Non-Negotiable: TDD

`superpowers:test-driven-development` fires on every step that produces or modifies code. No fast-path skips it. No "it's a small change" justification. Tests that pass are the canonical evidence of fidelity to outcome.

## When to Use

**canonical-sdlc is the entry point for ALL non-trivial engineering work — not just large efforts.** Universal entry: the question at the door is no longer *whether* to engage the lifecycle but *which triple* to run it at. A one-line bugfix runs the same lifecycle a multi-session epic does — at `tested · task`, where the ceremony collapses to minutes (RED repro → GREEN → self-review), not at `peer-reviewed · wave`. The `tested` rigor and `task` scale exist precisely so small work pays minutes, not ceremony: no per-task plan file, no spec, no mandatory critic — just the TDD floor and a one-line ledger entry.

**Out of scope — the one boundary.** Work with **no behavior or verification surface** stays outside the lifecycle: docs-only prose changes and chores are not lifecycle-governed (there is no docs/chore intent — ratified Not-Doing; §Classification rules rule 6). Standalone skills (`humanizer`, a prose linter, a formatter) cover that work directly. Everything with code-bearing behavior to verify enters here and picks a triple.

Triggers are re-keyed from *whether to engage* to *which triple*:

**Hard triggers** (any one → engage; the triple is inferred at Step 0):
- A new feature, architectural change, or multi-day effort → usually `build`, scale `wave`/`epic`.
- "What's next?" on an in-progress effort → resume at the active plan's triple.
- Session start on a branch with an active plan file → adopt that plan's triple.
- A divergence-from-intended-behavior fix → `bugfix`, scale `task` or `wave`.
- A behavior-preserving restructure/upgrade/migration/removal → `refactor`.
- A named-measurement improvement (latency, bundle size, UX quality) → `tune`.
- A production/tooling incident to triage, fix, deploy, postmortem → `incident-response` (floors at `audited`).

**Soft triggers** (two or more → lean toward a heavier rigor/scale, not toward *whether* to engage):
- The effort touches more than one component → lean `wave`+, `complex` slices.
- The effort will ship to users → lean `peer-reviewed`+.
- A spec or plan already exists → adopt its scale.
- The work requires decisions future maintainers will need → lean `peer-reviewed`+ (durable decision trail).

Intent, rigor, and scale value sets and their inference live in §The Three Axes and Step 0's classification sub-step; this section only decides that the door is open and hints at where the triple lands.

## The Three Axes

v11 replaces the single `mode` with three orthogonal axes. Every run declares exactly **one triple** — `<intent> · <rigor> · <scale>` — at Step 0. **Intent** is the kind of work (what the deliverable is); **rigor** is how hard the evidence tries to lie (how well-made); **scale** is the decomposition unit (how much work, one session or many). The axes are independent: any intent can run at any rigor (subject to the floors below) and at any valid scale (§Intent × scale validity). Intent declaration is reviewable — a run mislabelled to dodge steps is drift with a label. The v≤10 mode names survive only as legacy vocabulary (see the grandfathering section).

### Intent — the kind of work

| Intent | Description | Use when | Evidence-shape delta |
|---|---|---|---|
| `build` | New capability, or capability restored by ADDING new machinery/interfaces/config (the machinery test, S1). Covers user-facing features AND internal/infrastructure work. The spec describes NEW behavior. | The deliverable is behavior that did not exist in the design before — a new feature, tool, or substrate, or a capability re-established by building new machinery rather than repairing existing code. | Standard RED→GREEN per slice. **Meta-evidence rule for instrument-type work:** when the build IS a verification instrument (a test harness, a gate, a check), its capability evidence must prove the instrument CATCHES planted failures, not merely that it runs green — a check that never fails is not proven to work. |
| `bugfix` | Restore intended behavior WITHIN the existing design (S1) — a repair, not new machinery. The spec describes RESTORED behavior. | A divergence from intended behavior is fixable inside the current design; no new interface or substrate is introduced. | RED test is the failing repro; GREEN is the repro passing. Default rigor is lighter at `task` scale (see defaults). |
| `refactor` | Change structure without changing behavior. Explicitly covers upgrades, migrations, AND removals/deprecations of redundant capability. The observable contract is preserved; the code, dependency, or surface underneath it changes. | Restructuring, upgrading a dependency, migrating to a new API, or removing/deprecating capability now redundant. | Behavior-preservation evidence — the existing suite stays green across the change ("all existing tests still pass" is the spec). Full refactor/upgrade evidence keys land in a later wave. |
| `tune` | Move a NAMED measured quantity toward a target (S2) — performance, size, UX quality, cost. Absorbs the former UX-refresh lifecycle as its UX flavor (§Legacy modes). Requires a measurement loop; if you cannot name the measurement, it is not tune. | The goal is a better value on a metric you can baseline and re-measure — latency, bundle size, a design/heuristic score — routed to the domain skill (`impeccable` / `security-and-hardening` / `performance-optimization`). | **baseline → target → re-measure** — record the starting value, the target, and the re-measured value. This shape applies at EVERY rigor; rigor sets how hard the measurement is defended, not whether it exists. |
| `spike` | Timeboxed research or prototype. **Ships no code at any rigor.** The deliverable is a finding, not a shipped change. | A question must be answered by building throwaway code or investigating, and nothing from the spike is meant to reach the integration branch. | Writeup only — no plan file, no ADR, no commits to the integration branch (D3). If the finding is worth shipping, that shipping is a SEPARATE run under a shipping intent (§Classification rules). |
| `incident-response` | Any LIVE DEPLOYED surface broken for its users — production OR tooling (S3). The clock matters. The outcome is a closed incident with documented prevention. | A released, in-use surface (a production service or a shipped dev tool) is broken for the people who depend on it and the fix is time-pressured. | RCA, not ADR (backward-facing postmortem). Full `audited` rigor is the intent floor (below). Monitoring-gap closure is part of Ship. |

### Rigor — how hard the evidence tries to lie

Cumulative: each tier includes everything below it. TDD is non-negotiable at every tier.

| Rigor | The claim | What you get | What you skip | Use when |
|---|---|---|---|---|
| `tested` | "It provably works." | TDD RED→GREEN on every code change; the Verify gate discharges the Verification Matrix at each row's contracted tier; the tests floor (`pass == total`); structured 5-axis Step-6 self-review. | ALL independent assurance roles — both the independent Step-5 Verification Auditor AND the mandatory Step-6 adversarial critic. Self-review only. | The cheap floor for well-scoped work — `task`-scale bugfixes, spikes. |
| `peer-reviewed` | "It works and it's well-made." | Everything in `tested`, plus a separate spec, the full Verification Matrix per AC discharged by the INDEPENDENT Step-5 Verification Auditor on the evidence, and the structured 5-axis Step-6 review. **No adversarial critic** — that role is `audited`'s. | The mandatory independent adversarial critic (Step 6) and the durable third-party decision trail. | The default for `build`, `refactor`, `tune`, and `wave`-scale `bugfix` — anything that ships to users or sets structure. |
| `audited` | "A third party tried to break it, and the decision trail survives me." | Everything in `peer-reviewed`, plus the mandatory INDEPENDENT adversarial critic (Step-6 stance 2), per-step checkpoint commits, and the expanded stop-and-wake list (§Escalation Protocol) — adversarial verification plus unattended discipline. The decision trail is durable and reviewable, outliving the author. | Nothing — this is the top tier. | The intent floor for `incident-response`; any security/privacy-flagged or otherwise floor-raised work (§Rigor floors and lifecycle). |

### Scale — the decomposition unit

| Scale | Steps | Decomposition & artifacts | Branch / merge |
|---|---|---|---|
| `epic` | 0–3 only (short-circuits before Step 4). | Carves the work into waves; produces `epic.spec.md` + `epic.plan.md`. Does NOT execute Steps 4–9. | Owns the integration branch `epic/NN-<slug>`; every wave merges there; the epic merges to mainline ONCE, at close. |
| `wave` (default) | The full applicable step set (0–9). | The default scale; one wave spec + plan; slices inside Step 4. Re-enters Steps 1–3 at greater depth than the epic plan — trust but verify. | Wave branch off the epic integration branch; merges back there at Step 8. |
| `task` | The full step set, compressed — a sub-session unit. | MULTIPLE per session. ONE session-level plan carries a `## Tasks` ledger with one `## SDLC State` evidence line per task — NO per-task plan or spec files. Ledger hook-addressing is documented here, enforced in a subsequent hook revision. | Shares the session's branch; no per-task branch. |

**Spike artifact shape (any scale).** When intent is `spike`, there is NO plan file at all — the sole artifact is the writeup at `<docs-root>/spikes/` (D3). Universal entry means universal *routing*, not universal paperwork.

## Classification rules

Intent is DECLARED and reviewable; a mislabelled run is drift with a label. These rules make the declaration mechanical.

1. **One intent per run.** Mixed-kind work splits into several runs — never average two kinds into one label. `scale: task` explicitly allows several runs per session, each with its own intent, so splitting is cheap.
2. **Dominant deliverable, not motivation.** Classify by what the run DELIVERS, not why it was undertaken. The `build`-vs-`bugfix` discriminator is the **machinery test (S1):** capability restored by ADDING new machinery/interfaces/config = `build`; a fix within the existing design = `bugfix`. Field-failure motivation does not make new machinery a bugfix.
3. **Spike-then-ship = two runs, and this splitting takes precedence over incidental-fix folding (S4).** A finding from a spike re-enters as a SEPARATE run under a shipping intent. When a shippable fix is discovered DURING a spike, the split wins over rule 4 — the fix is its own run, never folded into the spike (which ships no code).
4. **Incidental corrections otherwise stay in their host run.** Small corrections encountered while doing the run's dominant work (a one-line typo fix in a touched file) ship inline, not as a separate run — except where rule 3 applies.
5. **Removal/deprecation → `refactor`.** Removing or deprecating redundant capability is a refactor, not a build or a bugfix.
6. **Docs-only work is outside canonical-sdlc.** Pure documentation/prose changes are not lifecycle-governed — there is no docs/chore intent (ratified Not-Doing). Universal entry covers non-trivial code-bearing work.
7. **Planning-only runs take the scoped work's intent at `epic` scale.** An epic-scoping run is `scale: epic` of its eventual intent (usually `build`), not an intent of its own.

**Known gray zones — expected intent collisions.** Two boundary cases recur and do NOT resolve mechanically; both route to Step 0's **interview-by-exception** (wired in a later slice) rather than a silent default:

- **mechanism-swap** — capability is preserved but the mechanism observably changes (a transport swap, a trigger swap). Sits between `build` and `refactor`.
- **reference-content** — skill prose / recipes versus enforced machinery. Enforced artifacts (hooks, keys, schemas) classify cleanly as `build`; reference prose leans toward out-of-scope docs. Sits between `build` and docs-outside-lifecycle.

When a run hits either, do not guess — ask the one-question interview at Step 0.

## Rigor floors and lifecycle

**Default rigor by intent** (provisional at Step 0):

| Intent | Default rigor |
|---|---|
| `build` | `peer-reviewed` |
| `bugfix` | `tested` at `task` scale; `peer-reviewed` at `wave`+ |
| `refactor` | `peer-reviewed` |
| `tune` | `peer-reviewed` |
| `spike` | `tested` (capped — no code ships at any rigor) |
| `incident-response` | `audited` (intent floor) |

**Four floor sources.** Effective rigor = the MAX across all four; a floor can only push rigor UP, never down (override upward-only):

- **Intent floor** — from the intent itself: `incident-response` floors at `audited`; `spike` is CAPPED at `tested` (it ships no code, so higher rigor buys nothing).
- **Flag floor** — security-touching work or privacy/vulnerable-population triggers: either category alone floors at `audited`. Evaluate what the work **touches and induces**, not what it renders: handling a credential, a PII field, or a vulnerable-population surface raises the floor even when the visible output looks benign.
- **Project floor** — a `rigor-floor:` key in `.bionic/config.yaml` sets a repo-wide minimum.
- **Epic floor** — a `rigor-floor:` line in epic frontmatter sets an epic-wide minimum. Use `rigor-floor:`, never `rigor:` — an epic declares a floor, not a fixed rigor.

**Anti-flag-laundering guard.** Do not carve a sensitive concern into a tiny unflagged wave to dodge the floor. Carve waves along sensitivity boundaries, and the wave that OWNS the integration point (where the sensitive path is wired) carries the flag floor — you cannot launder a security-touching integration into a benign-looking slice.

**Lifecycle.** Rigor is **provisional** at Step 0 (defaulted from the table above), **locked** at Step 3 approval. The model may propose a different rigor, but only INSIDE the reviewed plan with a one-line rationale — never a silent change. **Mid-wave UPGRADES are free** and are recorded in `## SDLC State`. **DOWNGRADES are user decisions** via the existing **Waiver Protocol** (§Step 5) — there is no parallel downgrade mechanism.

**Flags stay orthogonal to rigor (D5).** `use_worktree` and `multi_agent` are NEVER bound by rigor. Inference defaults may correlate (audited work often wants isolation), but there is no binding rule and no hook check — rigor sets evidence strength, flags set execution mechanics.

## Intent × scale validity

|  | `task` | `wave` | `epic` |
|---|---|---|---|
| `build` | valid | valid | valid |
| `bugfix` | valid | valid | **barred** |
| `refactor` | valid | valid | valid |
| `tune` | valid | valid | valid |
| `spike` | valid | valid | **barred** |
| `incident-response` | valid | valid | **barred** |

**Barred cells (D4):**

- `bugfix × epic` — a bugfix that needs multi-session decomposition is a misclassified `refactor` or `build`; a genuine bugfix fits within a wave.
- `spike × epic` — spikes are timeboxed; an epic-scale investigation is not a spike.
- `incident-response × epic` — incidents are clock-driven; you do not scope an incident across multiple sessions.

## Step → governing-skill mapping

One base step→skill table governs every run; per-intent deltas below name only what changes. The **Tier** column is the default dispatch target (§Model & Token Strategy): **O** = orchestrator (main thread) · **E** = execution (fresh `model: opus`/`model: sonnet`, routed by the slice's `complexity:` tag; fork only if context-heavy) · **X** = explore/mechanical/test (fresh `model: sonnet`). Default hint only; the Strategy section governs.

| Step | Tier | Governing skill | On-demand sub-skills |
|---|---|---|---|
| 0 Configure | O | `canonical-sdlc` + `agent-skills:context-engineering` | — |
| 1 Ideate | O | `agent-skills:idea-refine` | — |
| 2 Spec | O | `agent-skills:spec-driven-development` | — |
| 3 Plan | O | `superpowers:writing-plans` | — |
| 4 Implement | E + X | `agent-skills:incremental-implementation` | `superpowers:test-driven-development` (every slice); `superpowers:executing-plans`; `agent-skills:source-driven-development`; `superpowers:systematic-debugging`; `agent-skills:documentation-and-adrs`; `superpowers:using-git-worktrees` (if `use_worktree`) |
| 5 Verify (gate) | X → O | `superpowers:verification-before-completion` | tests/build modality: the suite · browser modality: `browser-verify` (drives `playwright-cli`) → escalate `agent-skills:browser-testing-with-devtools` (deep inspection only); `agent-skills:frontend-ui-engineering` pre-verify |
| 6 Review (gate) | E | `agent-skills:code-review-and-quality` | 5-axis self-review (always); adversarial critic via independent subagent dispatch — **MANDATORY at `audited` rigor** (§Step 6); `agent-skills:security-and-hardening` (security flag); `agent-skills:performance-optimization` (perf flag) |
| 7 Document | O / E | `agent-skills:documentation-and-adrs` | RCA shape for `incident-response` (§Per-intent deltas) |
| 8 Integrate & close | O / X | `superpowers:finishing-a-development-branch` | `canonical-sdlc` (cleanup half) |
| 9 Ship | E / O | `agent-skills:shipping-and-launch` | `agent-skills:ci-cd-and-automation` (new pipelines only) |
| — Commit rhythm (cross-cutting) | O | `agent-skills:git-workflow-and-versioning` | fires per step, not at a position |

**Engagement sequence — Step 1 Q&A is never skipped.** Unattended execution is the **Steps 4–9 span**, not the whole lifecycle; skipping Step 1 Q&A to "save time" is the single highest-risk move. The user-engagement shape is fixed for every run:

| Step | Engagement |
|---|---|
| 1. Ideate | **Interactive Q&A with the user.** Extensive back-and-forth on scope, non-goals, alternatives. |
| 2. Spec | **Semi-interactive.** Translate Step 1 into a testable contract. Surface remaining ambiguities as Wake Notes; otherwise proceed. |
| 3. Plan | **Write → one approval checkpoint.** Claude writes the plan; user reviews and approves before Step 4 begins. |
| 4–9 | **Unattended** within the stop-and-wake rules (expanded at `audited` rigor — §Escalation Protocol). |

### Per-intent deltas

Each intent runs the base table above; only the rows named below change. `scale: epic` short-circuits any intent after Step 3 (§Scale — the decomposition unit): it produces `epic.spec.md` + `epic.plan.md`, carves waves, owns the `epic/NN-<slug>` integration branch, and does not run Steps 4–9 — each wave is then a separate subsequent run.

- **`build`** — base table as-is. When the build IS a verification instrument (a test harness, a gate, a check), its Step-5 capability evidence must prove the instrument CATCHES planted failures, not merely that it runs green (the meta-evidence rule, §Intent — the kind of work).
- **`bugfix`** — Step 4's failing test IS the repro: RED = the reproduction of the divergence, GREEN = the repro passing.
- **`refactor`** — the Step-2 spec is "behavior preserved" (the existing suite stays green across the change); migrations additionally carry a compatibility matrix and a revert plan. Full refactor/upgrade evidence keys ship in a later version. A new acceptance criterion means the work is no longer behavior-preserving ⇒ reclassify as `build`.
- **`tune`** — Step 1 routes to the **domain skill**: `impeccable` for UX, `agent-skills:security-and-hardening` for hardening, `agent-skills:performance-optimization` for latency/size/cost. Step 5 is **heavily weighted at every rigor** — the **baseline → target → re-measure** shape is the verification (record starting value, target, re-measured value).
- **`spike`** — **no plan file**; the sole artifact is the writeup at `<docs-root>/spikes/spike-<slug>-<YYYYMMDD>.md` (D3). Research runs on a scratch branch or uncommitted; **no worktree, no ADR, no spec, no commits to the integration branch**. If the finding turns out shippable, that is a SEPARATE run — re-enter under a shipping intent at Step 1 (§Classification rules rule 3).
- **`incident-response`** — Step 1 compresses to **triage** (confirm the incident is real, scope blast radius, assign severity); Step 4's failing test = the incident repro; Step 6's critic framing is "does the fix mask a deeper issue?"; Step 7 is an **RCA, not an ADR** (backward-facing postmortem — shape below); Step 9 = deploy with rollback → monitor ≥1 cycle → close the monitoring gap (or declare "no gap" with evidence). Rigor floors at `audited`, so the adversarial critic and expanded stop-and-wake are always on.

**`tune` UX flavor (absorbs the former UX-refresh lifecycle).** When `tune` targets UX, Step 1's domain skill is `impeccable` (`shape` for ideation) and Step 4 runs impeccable's native loop: (a) `/impeccable craft` → (b) polish + harden + normalize → (c) critique (scored eval) → (d) iterate. **Loop exit gate:** critique's Nielsen heuristic scores ≥ 3/4 on all 10 heuristics; cognitive-load score ≤ 1; AI-slop verdict passes; polish checklist complete. Step 5 adds an `audit` scored technical-quality report with T3 browser evidence per state (`agent-skills:frontend-ui-engineering` pre-verify); Step 6 reviews the **5 code axes only** (design quality was already evaluated in the Step-4 critique loop); Step 9 invokes `extract` if reusable patterns emerged. Behavior is unchanged from the v≤10 UX-refresh mode — only its home moved (§Legacy modes).

**RCA required shape** (`incidents/NNNN-<slug>/rca.md`): summary, timeline, root cause, contributing factors, the fix, prevention (each measure links a commit/ticket), and monitoring-gap analysis. Full section-by-section shape and rules: the canonical-sdlc README (`## RCA shape`). Incident-specific stop-and-wake triggers live under §Escalation Protocol.

## Autonomous Friction Protocol

When unattended Steps 4–9 hit friction, **diagnose before escalating**. Friction is either:

- **Diagnostic friction** — direction is clear, code misbehaves (test fails, behavior diverges from spec, surprise output). → MAP first.
- **Decision friction** — the direction itself is in question (which approach, which abstraction, which scope). → Surface via User Decision Protocol.

For diagnostic friction:

1. **Load `map-instrument-narrow` immediately** and dispatch it to a **fresh subagent carrying the verbatim Rigor Mandate** (Subagent Dispatch Convention point 8). Do not write speculative fix code first. Speculative-fix-before-instrumentation regresses pass rates more often than it improves them.
2. **No fix code** until NARROW phase yields a named root cause with data evidence.
3. **Three-fail rule applies AFTER one full MAP-INSTRUMENT-NARROW pass**, not before. If a complete pass does not yield a clean root cause, loop back to MAP (your architectural model was incomplete) — do not throw speculative fixes.
4. **After root cause is known**, the *bubble-up vs. proceed-directly* judgment is a separate decision per the User Decision Protocol. Diagnosis ≠ permission to fix in scope; trivial fixes proceed, scope-expanding fixes surface.
5. **Recurse on layered root causes.** A pass yields a *confirmed* root cause plus, often, deeper or sibling causes (see `map-instrument-narrow` → **Recursive Root-Cause Detection**). The orchestrator owns the **root-cause tree** — record it in the plan's `## Assumptions` / RCA section — and dispatches a **fresh subagent per open candidate**: serial for a chain of blockages, depth-first for nested causes, each carrying the same Rigor Mandate and a clean context (never reuse the contaminated one). Bound recursion at `max_depth: 4`; when a deeper cause expands scope beyond the wave, stop and surface the tree via the User Decision Protocol. A wave's diagnosis is complete only when every tree node is `confirmed` or explicitly deferred.

**Anti-pattern:** "I'll try one thing first, then instrument if it doesn't work." That "one thing" mutates state. Subsequent instrumentation captures post-attempt state, not the original bug. **MAP before any state change.**

This protocol is load-bearing for every unattended wave. It is not optional.

## User Decision Protocol

Every user-facing decision point (Step 1 Q&A, Step 3 approval, every Wake Note, every stop-and-wake halt) follows this protocol. No exceptions.

**Frame at the highest useful level of abstraction.** Ask the conceptual question, not the implementation question. If asking "should we use option A or B" requires the user to understand the entire codebase, the abstraction level is wrong — climb up until the choice is stark.

**Always offer numbered recommendations (1, 2, 3 or A, B, C).** Even if you favor one, list 2–3 viable choices. Include a one-line rationale per option.

**Explain significance, briefly.** One sentence on what hinges on the choice — what downstream decisions, costs, or constraints compound from it.

**Radical brevity.** No preamble. No restatement. No trailing summary. The minimum prose required to make a quality decision. Aim for ≤200 words total per decision point including options.

**Format template:**

> [Single-sentence framing of the decision at conceptual level.]
>
> **Options:**
> 1. **<Name>** — <rationale>. <one-line tradeoff>.
> 2. **<Name>** — <rationale>. <one-line tradeoff>.
> 3. **<Name>** (Recommended) — <rationale>. <one-line tradeoff>.
>
> **Why it matters:** <one sentence on downstream impact>.

**Pre-send gate — check before emitting any decision-point output.** If ANY of these is true, the abstraction level is wrong. Climb one rung and rewrite before sending:

- [ ] Stating the question requires a filename, function name, or line number → climb to the conceptual choice the file represents.
- [ ] Rationale per option exceeds ~25 words → you are explaining implementation, not framing the choice. Cut to the load-bearing distinction.
- [ ] The user could not make the choice without reading the codebase first → climb until the choice is stark.
- [ ] You are about to retry the same abstraction level the user already asked you to reframe → mandatory one-rung climb, no exceptions.

**Significance tier.** For any decision that crosses a wave boundary or sets a precedent, state the tier explicitly:
- *trivial* — local; reversible without cost.
- *medium* — wave-scoped; reversible with rework.
- *momentous* — cross-wave; sets a precedent; reversal is expensive.

## Ephemeral Workspace (`.bionic/tmp/`)

All interim files the skill writes for itself live in `.bionic/tmp/` (gitignored):
- `continuation-checkpoint.md`, `handoff-*.md` (session-boundary snapshots)
- `evidence-*.png`, `devtools-trace-*.json`, perf snapshots, screenshots
- `wake-note-draft-*.md`, decision-scratch files

Step 0 pre-flight ensures `.bionic/tmp/` exists. Step 8 (Integrate & close, cleanup half) wipes the directory on merge
(when `cleanup_on_finish: true`, the default).

Plan and spec files (canonical artifacts) still live under `<docs-root>/{plans,specs,adrs,incidents}/`. Only ephemera goes in `.bionic/tmp/`.

## Always-On Prerequisites

These load at session start, not as numbered steps:

**Session-resume protocol — runs FIRST.** If a plan file with `governing-skill: canonical-sdlc` and `sdlc-step: < 10` exists, treat it as the active plan. Read in this order: frontmatter → `## Handoff` (if present) → `## SDLC State`. Use the handoff's `Resume point` as the literal next action. The handoff is authoritative.

**Session-entry grounding gate — enumerate before declaring active artifact.** Operating against the wrong plan/wave/branch is a top-cost session failure. Before declaring the active artifact:

1. `git log -10 --oneline` — what's the recent commit shape?
2. `ls <docs-root>/plans/**/*.plan.md` AND `ls .bionic/tmp/continuation-checkpoint.md` AND `ls **/continuation.md` — what plan-class artifacts exist?
3. Current branch name and any handoff files at canonical paths.
4. Read `INDEX.md` + `context.md` + every linked file.
5. **Name the active artifact explicitly** before declaring mode/wave. If the inferred active artifact contradicts the user's stated intent, HALT and surface via User Decision Protocol. Do not auto-resolve.

- **Announce the triple** per the Load-time Announcement section.
- `agent-skills:context-engineering` — load the right files before work begins.
- **Memory sweep — recursive.** Read `.bionic/memory/INDEX.md`, `context.md`, AND every file they link to. INDEX.md is an *index*, not the whole notebook.

## Woven-In Practices

Fire on-trigger, not at a fixed step:
- `agent-skills:source-driven-development` — whenever touching an unfamiliar API.
- `agent-skills:documentation-and-adrs` — inline capture during plan or implement.
- `superpowers:systematic-debugging` — whenever a test fails or behavior surprises.

## Steps

Each step has: **goal** · **action** · **completion gate** · **evidence artifact**.

### Step 0 — Configure (entry-gate confirmation phase)

Mandatory for new plans (`canonical_sdlc_version: 10`, current). `3`–`9` are prior-but-enforced (v3 requires the 5 + 2 flag set; v4 added `model_plan`, carried unchanged through v9; v10 adds the Verification Matrix); `1`/`2` are grandfathered (no flag enforcement).

**Goal:** Set every plan-shaping flag in plan frontmatter deliberately, with explicit user confirmation, and derive the Verification Matrix the wave will discharge.

**Action:** Seven sub-steps:

1. **Pre-flight environment check.**
   - **(a) Bionic root.** Check `<project>/.bionic/` exists. If absent, ask to create.
   - **(b) Docs root.** Read `<project>/.bionic/config.yaml`'s `docs-root:`; default `.bionic/docs`. Ensure `{specs,plans,adrs,incidents}/` exist.
   - **(c) Ephemeral workspace.** `mkdir -p <project>/.bionic/tmp/`.
   - **(d) Hook installation.** Verify `~/.claude/hooks/canonical-sdlc-{evidence-gate,governing-skill}.sh` are present and executable. If any are missing, warn and record an `## Assumptions` entry.

2. **Classify the triple — `<intent> · <rigor> · <scale>` — silently, then interview only by exception.** The triple is the run's most fundamental shaping decision (§The Three Axes); infer it before the discriminator flags, because intent seeds several flag and matrix-tier defaults. Inference signals per axis:

   | Axis | Inference signals |
   |---|---|
   | **intent** | Read the verbs and named artifacts in the request. New capability / new machinery (the machinery test, §Classification rules) → `build`; a divergence-from-intended-behavior to repair → `bugfix`; a behavior-preserving restructure, dependency upgrade, API migration, or removal/deprecation → `refactor`; a named-measurement improvement (latency, bundle size, a design/heuristic score) → `tune`; understanding-as-deliverable (a throwaway probe, a research question) → `spike`; a live deployed surface broken for its users with the clock running → `incident-response`. |
   | **rigor** | Start from the **default-rigor-by-intent** table (§Rigor floors and lifecycle), then take the **MAX** with every derivable floor (intent floor, flag floor, project floor, epic floor). A floor only pushes rigor UP. The inferred value is **provisional** — it locks at Step 3. |
   | **scale** | A sub-session unit, one of several this session → `task`; one full session → `wave` (default); spans multiple sessions and carves into waves → `epic`. Check the **intent × scale validity** matrix (§Intent × scale validity): a barred cell (`bugfix`/`spike`/`incident-response` × `epic`) means the intent or the scale is misjudged — re-derive, do not declare a barred triple. |

   **Silent inference is the default path.** Do NOT interrogate the user for the triple; infer it, then surface it in the confirmation display (sub-step 5) with a per-line rationale, exactly as the discriminator flags are surfaced. The user confirms or overrides via the DSL — the triple is normally a `confirm`, not an answered questionnaire.

   **Interview by exception — ONLY.** Fire **1–3 targeted questions** at Step 0 on **exactly** these three conditions, and no others:
   - **(a) Intent collision** — two intents are genuinely plausible and §Classification rules does not resolve it. The two **standing gray zones** named there are the canonical cases: **mechanism-swap** (capability preserved but the mechanism observably changes — sits between `build` and `refactor`) and **reference-content** (skill prose/recipes versus enforced machinery — sits between `build` and out-of-scope docs). Name the two candidate intents in the question; never silently pick one.
   - **(b) Suspected-but-unconfirmed floor trigger** — the request has a *possible* security / privacy / vulnerable-population surface (a flag-floor trigger) that the request itself does not confirm. Ask whether that sensitive surface is in scope, because a yes raises the rigor floor to `audited`.
   - **(c) Unclear scale** — the work could be one session or several, and the boundary is not derivable from the request.

   There is **no interview mode.** These are surgical, single-purpose questions fired inline at Step 0. Deep requirements elicitation — the 6-lens back-and-forth — stays at **Step 1 (Ideate)**; Step 0's interview-by-exception never expands into it. (D5: the discriminator flags stay orthogonal to the triple — inference for the two may correlate, but no rule binds a flag to an axis value and no hook checks the pairing.)

3. **Infer recommended values** from available context.

   | Flag | Inference signals |
   |---|---|
   | `language` | Repo files: `package.json` / `tsconfig.json` → `typescript`/`javascript`; `Cargo.toml` → `rust`; `go.mod` → `go`; `pyproject.toml` → `python`; etc. Default `none`. |
   | `surface_type` | Keywords: "REST endpoint" / "HTTP API" → `api`; "GraphQL" → `graphql`; "dashboard" / "page" / "component" → `ui`; "Terraform" → `iac`; "ML" / "training" → `ml`; "WebSocket" / "realtime" → `realtime`; "iOS" / "Android" → `mobile`; otherwise `system` or `none`. |
   | `has_ui` | true if "UI" / "dashboard" / "page" / "component" appears. |
   | `multi_agent` | Heuristic: more than 3 voltagent specialties match across phases. |
   | `deploy_target` | "k8s" → `k8s`; "Vercel" → `vercel`; "deploy" → `custom`; "migration" → `migration`; none → `none`. |
   | `cleanup_on_finish` | Default `true`. |
   | `use_worktree` | Default `false`. Set true on explicit user override or when user says "isolate". |
   | `integration_branch` | Wave under an existing epic → copy from the epic plan's `integration-branch:`. Standalone → current git branch if it is a mainline (`main`/`master`/`develop`); otherwise default `main`. `incident-response` → `main` or `hotfix/<id>`. If genuinely undeterminable, print the line with value `unknown` — never drop it. |
   | `model_plan` | Derived from `multi_agent` and the **detected session model** (see §Model & Token Strategy). `true` → `orchestrator=<detected>; exec-complex=opus-fresh; exec-standard=sonnet-fresh; explore=sonnet-fresh`. `false` → `main=<detected>` (dial-down offered). Surfaced for confirmation; **hook-enforced for v4+** plans (§Legacy modes covers the v≤10 mode gating). |

4. **Derive the Verification Matrix.** One row per acceptance criterion (from the Step 2 spec; a wave planned before its spec is final reconciles rows against the spec at Step 2). Each row gets a tier from browser-verify's T0–T4 ladder by these **inference defaults**:
   - user-visible behavior change → **T3**;
   - engine/rendering-divergent behavior → **T2 (both engines)** for the divergence AND **T3** for the user-visible AC;
   - pure substrate/internal, no runtime surface → **T1/T2** with a one-line justification;
   - perceptual/design fidelity → **T3** (cold client), **T4** available;
   - docs/ADR ACs → **T0/none**.

   Store it as a top-level `## Verification Matrix` plan section (**not** inside `## SDLC State`), row schema `| AC | tier | status | evidence | auditor |`, status starting `pending`. **Grammar:** exactly five cells per row; **no literal `|` inside a cell** (a sheared row blocks loudly); status is one of `pending|blocked|discharged|waived` (hook-enforced enum — the cell carries gate semantics, §Step 5). Skeleton:

   ```
   ## Verification Matrix

   stack-health: <before/after snapshot, no delta>   # or n/a: <reason> — once per walk session

   | AC | tier | status | evidence | auditor |
   |---|---|---|---|---|
   | AC-1 | T3 | pending | see AC-1 | |
   | AC-2 | T1 | pending | see AC-2 | |

   AC-1:
     tier-run: <declared real surface URL + the AC's own interaction>
     fresh: <origin A: proof; origin B: proof — every origin in the AC's serving path>
     cold-client: <fresh profile / incognito context — how it was made cold>
     contact: <the AC's own interaction changed app state — observed delta>
     readback: <the AC's semantic value via page-scope eval>
   AC-2:
     tier-run: <suite command>
     readback: <asserted value / pass count>
   ```

   **T4 rows** are explicitly-scheduled human-walk rows, discharged by recorded user confirmation (§Step 5). **Lock semantics:** the matrix locks at Step 3 approval; after lock, tier *upgrades* are free, while *downgrades*, self-`n/a` on a live tier, and closure over a non-CONFIRMED row are only via the **Waiver Protocol** (§Step 5). Mid-wave new ACs go to `## Assumptions` as W+1 candidates — never into the locked matrix.

5. **Present the confirmation display — in full, always.** The display below is a mandatory, untruncatable artifact: every section, every flag, every line, every inference rationale, **and every matrix row**, rendered as one block in the conversation. Never elide, summarize, sample ("key flags: …"), or defer any portion of it — an abbreviated display invalidates the confirmation, because the user is approving exactly what they can see. The matrix block is rendered IN FULL under the same rule — **even past 12 ACs, print every row** (a matrix is exactly what must not be sampled). If a value is unknown, print the line with the value marked `unknown` rather than dropping the line. The `integration-branch:` line is load-bearing — Step 8 merges every wave into it; a display missing this line is an invalid confirmation, exactly like a missing flag.

   ```
   ═══ Plan Configuration — confirm before Step 1 ═══
   environment:
     bionic-root:  /Users/me/proj/.bionic               [verified]
     docs-root:    .bionic/docs                         [default]
     bionic-tmp:   /Users/me/proj/.bionic/tmp           [ready]
     hooks:        evidence-gate, governing-skill       [all installed]

   slug: <inferred-from-conversation>

   Triple:                          [the run's shaping decision — see §The Three Axes]
     intent:  build                 [inferred: request adds new machinery — machinery test]
     rigor:   peer-reviewed         [inferred: build default; no floor raises it — §Rigor floors]
     scale:   wave                  [inferred: one-session chunk, not multi-session]

   integration-branch: main         [inferred: current branch — Step 8 merges every wave here]

   Discriminator flags:
     surface_type:    api          [inferred: "REST endpoint" in convo]
     language:        typescript   [inferred: tsconfig.json]
     has_ui:          false        [no UI mentioned]
     multi_agent:     true         [default — parallel-dispatch fit; see feedback_default_multi_agent_true]
     deploy_target:   none         [no deploy signal]

   Opt-in flags:
     cleanup_on_finish: true       [Step 8 wipes .bionic/tmp/ on close]
     use_worktree:      false      [no isolated worktree — work on current branch]

   Model plan:                      [multi_agent=true → tiered dispatch]
     orchestrator:  fable-5 high    [detected session model; main thread, fixed all wave]
     exec-complex:  opus            [fresh model:opus — slices tagged complex, debugging, Step 6 review]
     exec-standard: sonnet          [fresh model:sonnet — slices tagged standard]
     explore/test:  sonnet          [fresh model:sonnet — search, mechanical, tests]
     # aliases resolve to the top model per family at dispatch time
     # multi_agent=false → single-thread: "main: <detected>" (dial-down offered)
     # Fable orchestrator → forks are Fable at ~2× Opus: fork bar rises; prefer fresh model:opus

   Verification Matrix:            [locked at Step 3 approval — every row shown, never sampled]
     stack-health: <once-per-walk-session snapshot, or n/a: reason>
     | AC   | tier | status  | evidence | auditor |
     | AC-1 | T3   | pending | see AC-1 |         |   [inferred: user-visible behavior → T3]
     | AC-2 | T1   | pending | see AC-2 |         |   [inferred: pure logic → T1]

   Reply "confirm" to accept, or specify overrides:
     e.g. "set use_worktree=true, set exec-standard=opus, set verify(AC-2)=T2, then confirm"
   ```

6. **Block until explicit confirmation.** No timeout, no implicit acceptance.

7. **Task-list creation is the immediate next action after approval.** The instant confirmation arrives — before any Step 1 work — run this fixed sequence:
   1. **Announce it:** "Step 0 confirmed — creating the task list."
   2. **Create the full TaskCreate list:** tasks `0:`, `1:`, ..., `9:`, one per planned step. Mark `0:` `completed` immediately.
   3. **Then transition to Step 1** (idea-refine).

   Nothing else runs between approval and list creation.

**Override DSL grammar.** The user's reply is parsed against:

```
reply        := overrides? "confirm"
overrides    := override ("," override)* ","?
override     := "set" axis "=" axis-value
              | "set" flag "=" value
              | "set" "verify" "(" AC-id ")" "=" tier
              | "change" flag "to" value
axis         := "intent" | "rigor" | "scale"
axis-value   := intent-value | rigor-value | scale-value
intent-value := "build" | "bugfix" | "refactor" | "tune" | "spike" | "incident-response"
rigor-value  := "tested" | "peer-reviewed" | "audited"
scale-value  := "task" | "wave" | "epic"
```

Accepted: `confirm`; `set use_worktree=true, confirm`; `set surface_type=graphql, set language=python, confirm`; `set integration-branch=develop, confirm`. **Triple override:** `set intent=refactor, set rigor=audited, confirm` reclassifies the run before Step 1; `set scale=epic, confirm` switches to epic-scoping. **Floors are upward-only — a rigor override BELOW a derivable floor is rejected at Step 0** (e.g. `set rigor=tested` on `incident-response`, whose intent floor is `audited`, or on any security/privacy-flagged work): warn, name the binding floor, and keep the floor value. An upward rigor override (`set rigor=audited` on a `build`) is always accepted. An override that names a **barred** intent × scale cell (§Intent × scale validity) is rejected with the reason. **Matrix tier override:** `set verify(AC-B2.1)=T2, confirm` retiers a matrix row before lock. Model-plan keys are valid override targets: `set orchestrator=fable-high, confirm` (multi_agent=true); `set exec-standard=opus, confirm` (route standard slices to opus too — equivalent to disabling complexity routing); `set exec-complex=sonnet, confirm` (accepted but discouraged; warn before applying); `set execution=opus-only, confirm` (shorthand for `exec-standard=opus`); `set main_model=sonnet, confirm` (multi_agent=false dial-down).

On accept, write final values into plan frontmatter literally — every flag as an explicit `<key>: <value>` line. The plan carries `canonical_sdlc_version: 10` plus all 5 discriminator flags, 2 opt-in flags, and a single-line `model_plan:` recording the confirmed tiers (e.g. `model_plan: orchestrator=fable-5-high; exec-complex=opus-fresh; exec-standard=sonnet-fresh; explore=sonnet-fresh`). The confirmed `integration-branch` and the derived `## Verification Matrix` are carried forward: when the plan file is written at Step 3, its `## SDLC State` section opens with the Step-0-confirmed `integration-branch: <name>` line, and the plan body carries the locked `## Verification Matrix` section. For v4 and later plans the governing-skill hook **requires** `model_plan`; for v10 it additionally requires the `## Verification Matrix` section at `sdlc-step ≥ 3` — a missing value blocks the write (exit 2).

**Two-layer enforcement.** Layer 1 (soft): SKILL.md mandates Step 0 — do not proceed without explicit user confirmation. Layer 2 (hard, `canonical-sdlc-governing-skill.sh`, on `PreToolUse|Write,Edit`): for v4+ plans, a missing flag / `model_plan` / (v10) matrix section → exit 2.

**Mid-plan reconfiguration.** Edit plan frontmatter directly; the new value takes effect immediately on next hook read.

**Legacy plan handling.** `canonical_sdlc_version: 1`/`2` are grandfathered (no flag enforcement); `3`–`9` stay enforced under their own shape tables (§Versioning). **DO NOT retrofit a newer version's requirements into an older plan** — an in-flight plan would start blocking mid-wave. This covers every universal-key addition (v7 `bundle-fresh:`, v8 `drive-check:`, v9 `stack-health:`) **and the v10 Verification Matrix**: never add a matrix to a v9-or-earlier plan.

**Gate:** Plan frontmatter contains `canonical_sdlc_version: 10` plus all 5 discriminator flags, 2 opt-in flags, and `model_plan`; the derived `## Verification Matrix` exists. The confirmation display included the `integration-branch:` line and every matrix row. User reply ended with `confirm` or `confirmed`.

**Evidence:** A line in `## SDLC State`: `Step 0: configured at <ISO-timestamp> via <reply-summary>; model_plan=<confirmed tiers>; integration-branch=<name>`.

### Step 1 — Ideate (`agent-skills:idea-refine`)
- **Goal:** Pin scope and non-goals before they get encoded as requirements.
- **Action:** Run the 6-lens refinement + "Not Doing" list. Always prefer `idea-refine` over `superpowers:brainstorming`.
- **Engagement:** Interactive Q&A with the user. **Mandatory for every run, every intent.** Every decision point follows the **User Decision Protocol**. The alternatives lens must check:
  1. Existing design docs (`.bionic/memory/*.md` including every file linked from `INDEX.md`).
  2. Prior plans and specs in `<docs-root>/plans/` and `<docs-root>/specs/` — walk every epic directory.
  3. Prior ADRs under `<docs-root>/adrs/`.
  4. Prior incidents and RCAs under `<docs-root>/incidents/`.
  5. In wave mode: the epic plan and spec for the current epic. Trust but verify.
- **Parallelization:** dispatch parallel Explore agents for distinct lenses when 2+ are independent.
- **Intent substitutions:**
  - `tune` (UX flavor): governing skill becomes **`shape`** (not `idea-refine`).
  - `incident-response`: compress to triage — confirm incident reality, scope blast radius, assign severity.
- **Gate:** Refined idea statement + explicit "Not Doing" list + alternatives lens cites prior design artifacts.
- **Evidence:** Artifacts captured in the spec file.

### Step 2 — Spec (`agent-skills:spec-driven-development`)
- **Goal:** Convert the refined idea into a testable contract.
- **Action:** Write requirements + acceptance criteria.
- **Parallelization:** surface_type specialist + user-experience critic in parallel.
- **Gate:** Every requirement has an acceptance criterion.
- **Evidence:** Spec doc at `<docs-root>/specs/epic-NN-<slug>/wave-NN-<slug>.spec.md` (wave); `epic.spec.md` (`scale: epic`); `incidents/NNNN-<slug>/spec.md` (incident).
- **Intent substitutions:**
  - `tune` (UX flavor): spec is **visual** (tokens, contrast, focus, interaction, responsive) plus "all existing tests still pass."
  - `incident-response`: spec is repro + blast radius + closure criteria.

### Step 3 — Plan (`superpowers:writing-plans`)
- **Goal:** Produce the execution contract that survives compaction.
- **Action:** Write an ordered, verifiable step list with no placeholders. Every plan file must contain two structured sections:
  - `## SDLC State` — opens with three literal keys: `integration-branch: <name>`, `mode: <mode>`, and `current: <N>` (the current step number — the evidence-gate hook greps `^current:` and blocks every commit if the line is missing or non-numeric; do NOT write `current-step:` or any other variant). Then one `Step N: <evidence>` line per step. **When advancing, bump `current:` and replace `Step N: (pending)` in-place.** Copyable skeleton:

    ```
    ## SDLC State

    integration-branch: <name>
    mode: <mode>
    current: <N>

    - Step 0: <evidence>
    - Step 1: (pending)
    - Step 2: (pending)
    ...
    - Step 9: (pending)
    ```
  - `## Assumptions` — seeded from Step 1 "Not Doing" plus spec ambiguities. Step 4 appends inline.
- **Expand TaskCreate list.** After the plan is written, expand Step 4 (Implement) into one TaskCreate task per slice (`4/1:`, `4/2:`, …).
- **Tag every slice's complexity.** Each Step 4 slice in the plan carries a `complexity: standard | complex` tag — this routes the slice's execution dispatch (see §Model & Token Strategy, Slice complexity routing). When uncertain, tag `complex`.
- **Integration-branch declaration — confirmed once at Step 0, stick to it.** Declared in `## SDLC State` via an `integration-branch: <name>` line, copied from the value confirmed in the Step 0 display. If the plan somehow reaches Step 3 without a confirmed value (legacy plan, resumed session), resolve it now:
  - `scale: epic`: ask the user. Record in the epic plan. Waves inherit.
  - Wave under an existing epic: copy from epic plan.
  - Standalone wave (no epic): ask. Default offer: `main`.
  - `incident-response`: typically `main` or `hotfix/<id>` — ask explicitly.
- **Parallelization:** research alternatives in parallel forks; converge in main thread.
- **Gate:** Plan passes writing-plans' "no placeholders" check + has both sections + `integration-branch:` line + explicit user approval (see Approval Checkpoint).
- **Evidence:** Plan file at canonical path.

#### Approval Checkpoint (end of Step 3)

This is the "walk away" boundary. After the plan is complete, present a summary using the **User Decision Protocol**: framing, options (approve / request revisions / halt), why-it-matters. Only on explicit approval does Step 4 begin.

**Wave shape locks at approval.** Once the user approves the Step 3 plan, wave scope is locked. Mid-wave discoveries (architectural gaps, related bugs, audit findings) get logged to `## Assumptions` as W+1 candidates — they do NOT reshape the current wave.

- **Exception 1:** if the discovery makes the current wave structurally impossible, surface as a Wake Note and halt. The response is "this wave cannot ship," not "ship a different wave."
- **Exception 2:** trivial corrections (one-line typo fix in a touched file) ship inline.
- **Step 6 Review's adversarial critic checks** for mid-wave scope drift not justified by an `## Assumptions` row.

### Step 4 — Implement (`agent-skills:incremental-implementation`)
- **Worktree (only if `use_worktree: true`).** At the start of Step 4, before the first slice, create a git worktree at `.worktrees/<slug>` off the current branch. Record `worktree:`, `base-sha:`, `branch:` in the Step 4 evidence line. When `use_worktree: false` (default), work proceeds on the current branch.
- **Goal:** Build in thin vertical slices with per-slice proof.
- **Non-negotiable rhythm:** `superpowers:test-driven-development` — RED → GREEN → commit, per slice.
- **Wrapper:** `superpowers:executing-plans` if a plan file exists.
- **Woven:** source-driven on unfamiliar APIs; systematic-debugging on surprises; inline ADR capture on decisions.
- **Parallelization:** if slices are independent (no shared state), dispatch parallel implementer agents.
- **Dispatch by complexity tag:** `standard` slices → fresh `model: sonnet`; `complex` slices → fresh `model: opus`. If a `standard` slice fails its gate twice, re-dispatch it fresh `model: opus` with the failure context (see §Model & Token Strategy, Escalation ladder).
- **Task tracking:** mark `4/<slice>: <description>` `in_progress` at slice start; `completed` immediately on slice merge.
- **Intent substitutions:**
  - `tune` (UX flavor): governing skill is **`impeccable`**, invoked as `/impeccable craft`. Step 4 runs as a loop: craft → polish/harden/normalize → critique → iterate.
  - `incident-response`: the failing test must be the **incident repro**.
- **Assumption-log update:** whenever a decision resolves ambiguity, append a one-line entry to `## Assumptions` **before the commit**.
- **Gate:** Every slice has a passing test that was RED before implementation; new assumptions logged.
- **Evidence:** Commit history shows RED→GREEN transitions; `## Assumptions` reflects novel decisions. When `use_worktree: true`: also `worktree:`, `base-sha:`, `branch:` fields.

### Step 5 — Verify (gate: "does it work?") (`superpowers:verification-before-completion`)

The Verify gate discharges the **Verification Matrix** (§Step 0) row by row. The unit of work is the **matrix row** — one per acceptance criterion (`5/<AC-id>`), operating over Step 4's slices. A row is *discharged* when its tier's evidence is recorded and the independent auditor CONFIRMS it; otherwise it stays `pending`, `blocked`, or `waived`.

- **Goal:** Every matrix row discharged (or waived); evidence before assertions.
- **Tests/build floor (always):** run all applicable suites and the build; record `cmd:`/`pass:`/`total:`/`output:` in the Step-5 block, `pass == total` required. This is the floor — no `n/a`. It lives in `## SDLC State` alongside the `auditor:` pointer; the per-row tier evidence lives in the `## Verification Matrix` section.

**Per-tier required evidence keys** (THE canonical table — the hooks mirror it and comment-point here; change this table first, R27). Each non-waived row's `<AC-id>:` block under the matrix carries exactly these keys:

| Tier | Required keys in the AC block |
|---|---|
| T0, T1 | `tier-run`, `readback` |
| T2 | `tier-run`, `readback`, `fixture-fidelity` |
| T3 | `tier-run`, `fresh`, `cold-client`, `contact`, `readback` |
| T4 | `user-confirmed` |

**The Tier-Discharge Rule.** Evidence at a lower tier never discharges a higher-tier row. Evidence at a higher tier discharges lower-tier rows for the same AC.

This replaces the old suite-credit escape: a green suite (T1) can never stand in for a T3 row — a suite run cannot honestly produce a T3 row's `fresh`/`cold-client`/`contact` fields, so the hook blocks the row on the missing keys and the auditor targets any fabrication.

**T3 validity — the five ways a live observation lies.** A T3 row's `fresh`/`cold-client`/`contact`/`readback` fields carry browser-verify's five T3 validity conditions: artifact per-origin freshness across the AC's serving path; a cold client; feature-scoped contact with the AC's own interaction (undrivable → the row is **blocked**, loud, never silently skipped); semantic readback via page-scope eval, never pixels; and the once-per-session runtime stack-health below. browser-verify is the canonical home — see it for the full conditions; do not restate them here.

**stack-health — once per walk session.** The `## Verification Matrix` section opens with a `stack-health: <before/after snapshot, no delta>` line (or `n/a: <reason>` when no long-running serve is observed), bracketing the whole walk — same value contract as v9. Any restart/crash delta is a blocking finding until run to ground.

**T4 discharge.** A T4 row is discharged by recorded user confirmation — `user-confirmed: <user> <date> <what was walked>`. Agents never self-confirm a T4 row.

**False-green rule (structured).** On discovering any test that passed over broken code, the gate cannot close until (1) the finding is logged as a `false-green: <test — what it lied about>` entry in the matrix section AND (2) it carries a paired `rewritten: <commit/test ref>` proving the test now goes RED on the broken code. A logged-but-unfixed false-green is a blocking defect (hook-enforced).

**Vocabulary rule.** Say "delivered/fixed/verified" only at the row's contracted tier. Below tier, the only honest phrasing is "implemented, verification pending."

**Mid-discharge commits (v10.1).** A commit made *while* Step 5 is in flight — a corrective fix found during the walk — has an honest home at `current: 5`: rows still `pending` or `blocked` are exempt from their per-tier keys, and the Step-5 `auditor:` pointer is required only once every row is discharged or waived (the auditor is the exit gate; it cannot have run mid-walk). The full contract — per-tier keys plus CONFIRMED on every non-waived row — bites on the 5→6 advance, where the hook re-validates the matrix as a prefix check. **Never regress `current:` to dodge a gate** — a plan that says `current: 4` while Verify work is underway misstates the step and silently drops the tests floor. Because `pending`/`blocked`/`waived` now carry gate semantics, the status cell is enum-checked: `pending|blocked|discharged|waived`, nothing else.

#### Auditor — the Step-5 exit gate

Step 5 does not close until an **Independent Verification Auditor** has ruled on every row. The auditor is a **fresh, independent** exec-complex agent (`model: opus`+) — **never** the implementer, **never** a fork of the orchestrator (a fork inherits the very context whose evidence is under audit). Its dispatch carries this mandate **verbatim** (Subagent Dispatch Convention point 9):

> Your job is to falsify this wave's verification evidence, not to review its code. You have the Verification Matrix, the per-row evidence, and repo access. For every row: (1) confirm the evidence was produced at the declared tier — a T3 row must cite the declared real surface, its per-origin freshness proofs, a cold client, and a feature-scoped semantic readback; (2) for T2 rows, demand the fixture-fidelity declaration and check the fixture can structurally reach the failure the AC guards; (3) re-execute at least one evidence command per tier used (cap 3 total) and compare outputs. Verdict per row: CONFIRMED / REFUTED / UNVERIFIABLE. "The evidence is plausible" is not a verdict. Agreement without re-execution is not acceptable output.

**Bounds:** the auditor audits the *evidence*, not the wave — it does not re-verify the feature, re-run the whole suite, or review code. Re-execution is one command per tier used, capped at 3 total. One auditor, one pass. Verdicts are recorded in the matrix `auditor` column. Any **REFUTED** or **UNVERIFIABLE** row blocks Step-5 closure absent a waiver; the hook enforces CONFIRMED-or-waived on every non-waived row once `current > 5`. The auditor is **distinct from the Step 6 critic** — the auditor falsifies the *evidence*, the critic falsifies the *code*. Both are kept.

#### Waiver Protocol

Three moves are user decisions, never an agent's: a tier **downgrade**, an **`n/a` on a live tier (T3/T4)**, and **closing over a non-CONFIRMED row**. Each goes through the **User Decision Protocol** and is recorded in the row as `waiver: <user> <date> <one-line reason>` (in the evidence cell or the AC block). A waived row is exempt from its per-tier evidence and from the CONFIRMED requirement. **Agents never self-write `n/a` on a live-tier field** — that is a downgrade, which is a waiver, which is the user's call.

**Evidence** (v10 form). The Step-5 block in `## SDLC State`:

```
Step 5:
  cmd: bash test.sh
  pass: 332
  total: 332
  output: <plan>#step-5
  auditor: 3 rows CONFIRMED — report .bionic/tmp/audit.md
```

plus the discharged `## Verification Matrix` section (stack-health line + per-AC tier blocks + `auditor` column). The full auditor report is ephemeral (`.bionic/tmp/`); the per-row verdicts persist in the matrix.

**Intent weight.** `tune` (UX flavor): **heavily weighted** — T3 browser evidence per state + an `audit` scored technical-quality report; use `impeccable` in Step 4 and `agent-skills:frontend-ui-engineering` pre-verify.

### Step 6 — Review (gate: "is it well-made?") (`agent-skills:code-review-and-quality`)

The Review gate proves the change is well-made, by stance (see §Verification model). Decompose by **axis × stance**; shard by subsystem on large diffs.

**Stance 1 — structured 5-axis self-review (always).**
- **Axes:** correctness, readability, architecture, security, performance. Every axis gets an explicit PASS / FLAG / FAIL verdict.
- **Reviewer tier:** all review agents (both stances) dispatch at Tier 2 (fresh `model: opus`) regardless of which tier wrote the code — verification is never cheaper than authorship.
- **Architecture-axis closure check:** for each new primitive/substrate added in this wave, trace user input → new code; also confirm the Step-5 T3 readback reached the same code (see Step 5). If the chain breaks (no callsite reaches the new code), the substrate is dead and the architecture axis is FAIL.
- **Parallelization:** all 5 axes run in parallel.
- **Escalations:** security axis flags → `agent-skills:security-and-hardening`. Performance axis flags → `agent-skills:performance-optimization`.
- **Intent substitution:** `tune` (UX flavor) — review the **5 code axes only**. Design quality was already evaluated in Step 4's critique loop.

**Stance 2 — adversarial critic.**
- **Mandatory at:** `audited` rigor — into which `incident-response` floors, and to which any security/privacy-flagged work is raised. **Optional below** `audited` (`tested`/`peer-reviewed`) — a run may still add it voluntarily. Not run at `scale: epic` (there is no Step 6).
- **INDEPENDENCE is non-negotiable:** the critic must be an **independent agent** — never the agent that wrote the code, never a self-graded review.
- **Distinct from the Step-5 auditor:** the critic falsifies the *code* (this diff, this design); the Step-5 auditor falsifies the *evidence* (did the matrix rows verify at their tiers). Both run; neither substitutes for the other.
- **Goal:** Catch what self-review missed. Fresh context, red-team framing.
- **Action:** Dispatch a fresh-context subagent with the plan, the diff, and the Stance 1 self-review notes. Prompt template:

  > _Your job is to find what went wrong in this change. You have the spec, the plan, the diff, and the 5-axis self-review notes. Read them and try to falsify the claim that this is ready to merge. Look specifically for: silent wrong assumptions not logged in the `## Assumptions` section, scope creep beyond the spec, missing edge cases, fabricated evidence, and cross-cutting concerns a single-axis review would miss. Output either: at least one specific, reproducible issue, or an explicit "no issues found" followed by the three strongest falsification attempts you made and why each failed. Confirmation-seeking agreement is not acceptable output._

  - **Incident-response framing:** verify fix does not mask a deeper issue; monitoring gap analysis is honest.
  - **Design-refresh framing:** find visual regressions and a11y failures.
- **Parallelization:** dispatch 2+ critics with different framings in parallel.
- **Gate:** Both stances complete — every axis has a verdict, and the critic output is attached. Sycophantic output is **not** evidence.
- **Evidence:** Pointer to the 5-axis review body + the critic findings (specific issues raised or specific falsification attempts).

### Step 7 — Document decisions (`agent-skills:documentation-and-adrs`) — checkpoint
- **Goal:** Forcing function. Catch decisions that weren't captured inline during Steps 3 and 4.
- **ADRs attach to decision SIGNIFICANCE, never to rigor.** Use the User Decision Protocol's significance tiers (§User Decision Protocol): a **momentous** decision (cross-wave, sets a precedent, expensive to reverse) gets an ADR at ANY rigor — even `tested`; a **medium** decision (wave-scoped, reversible with rework) gets one when it will shape later waves; a **trivial** decision gets none at any rigor. The rigor ladder carries **no ADR row** — rigor sets evidence strength, significance sets the decision trail. (`audited`'s "durable decision trail" is the discipline of *recording* momentous decisions, not an extra ADR quota keyed to rigor.)
- **Action (all intents except `incident-response`):** Review plan and implementation commits; verify every decision at or above **medium** significance has an ADR.
- **Action (`incident-response`):** **write the RCA** (postmortem, not ADR — see RCA shape in §Per-intent deltas).
- **Parallelization:** ADR draft + RCA draft (if applicable) in parallel.
- **Gate:** Every decision at or above medium significance has a written record.
- **Evidence:** ADR file(s) at canonical path, or `rca.md` for `incident-response`.

### Step 8 — Integrate & close (`superpowers:finishing-a-development-branch` + `canonical-sdlc`)

Merges the wave onto the integration branch (the **finish** half) then wipes the ephemeral workspace and asserts task-list integrity (the **cleanup** half). This is an **atomic** step — a single task, not fanned out.

**Finish half** (`superpowers:finishing-a-development-branch`):
- **Goal:** Close the branch cleanly. Every wave's commits must exist on the declared integration branch.
- **Action:** Merge the wave branch into the integration branch (local merge; pushing is the user's gate). Remove the worktree if one was created.
- **Default is merge.** Parking only permitted via an explicit `## Wake Note`.
- **Finish gate:** `git merge-base --is-ancestor <wave-tip> <integration-branch>` exits 0; worktree (if any) removed.

**Cleanup half** (`canonical-sdlc`) — runs **after the merge commit, before Step 9**. Fires when frontmatter declares `cleanup_on_finish: true` (the default).

- **When `cleanup_on_finish: false`:** the cleanup half is skipped. Record `cleanup: n/a: cleanup_on_finish=false` and proceed to Step 9.
- **When `cleanup_on_finish: true`** — execute:
  1. **Idempotency check.** Read frontmatter `cleaned:` field. If already set, record `cleanup: n/a: already cleaned <date>` and skip the rest of the cleanup half.
  2. **Wipe `.bionic/tmp/`.** `rm -rf <project>/.bionic/tmp/*`. The directory itself stays.
  3. **Assert TaskCreate list integrity.** Verify zero non-completed tasks. Fail loud if any task remains `in_progress` or `pending`: do not advance to Step 9 until either the task is completed or explicitly cancelled by the user.
  4. **Strip leftover continuation/handoff files.** Any `continuation-checkpoint.md` or `handoff-*.md` left in `<docs-root>/plans/<epic>/` (legacy locations) is removed — checkpoints live in `.bionic/tmp/` going forward.
  5. **Update frontmatter.** Set `cleaned: <today-ISO-date>`.

- **Gate:** wave merged into the declared integration branch and worktree (if any) removed; AND (`cleanup_on_finish: true`) frontmatter has `cleaned: <today>`, `.bionic/tmp/` is empty, all TaskCreate tasks `completed` — OR (`cleanup_on_finish: false`) `cleanup: n/a`.
- **Evidence:**

  ```
  Step 8:
    merge: <merge-sha>
    worktree-removed: yes        # or n/a when no worktree was used
    cleanup: ok                  # or n/a (cleanup_on_finish=false / already cleaned)
    tmp-wiped: yes
    tasks-completed: <count>/<count>
  ```

  When `cleanup_on_finish: false`, the block carries `merge:`, `worktree-removed:`, and `cleanup: n/a` only.

### Step 9 — Ship (`agent-skills:shipping-and-launch`)
- **Goal:** Production gate with pre-launch checklist, monitoring, rollback.
- **Action:** Run checklist; configure CI/CD if new pipelines needed. **Before declaring the wave complete**, emit `<docs-root>/plans/epic-NN-<slug>/continuation.md` summarizing wave, next wave, and open carry-overs.
- **Intent substitution (`tune`, UX flavor):** invoke **`extract`** if reusable patterns introduced.
- **Intent substitution (`incident-response`):** Step 9 expands to:
  1. Deploy with rollback plan.
  2. Monitor the indicator metric/alert through ≥1 cycle.
  3. Close the monitoring gap (or declare "no gap" with evidence).
  4. Emit `continuation.md` at incident dir only if follow-on work surfaces.
- **Gate:** Checklist complete; rollback plan documented; `continuation.md` written. For `incident-response`: fix monitored stuck; gap closed or absent.
- **Evidence:** Deployment record + rollback doc + monitoring dashboard link + `continuation.md` path.

## Commit rhythm (cross-cutting)

Committing is **not a numbered step** — it is a cross-cutting rhythm that fires per step (~once per step), never a single deferred "commit step." Governed by `agent-skills:git-workflow-and-versioning`. The evidence-gate hook enforces it on every `git commit`, blocking (exit 2) if the current step's evidence is missing — the rhythm and the gate are one mechanism. **Update `## SDLC State` before staging** (both the `current: <N>` line and the current step's evidence line), and carry the "THINGS I DIDN'T TOUCH" summary in the commit body.

- **Guardrail — no per-step `commit:` evidence field.** Do NOT add a `commit:` SHA to `## SDLC State`. The hook gates the current step's *existing* evidence on commit; a redundant `commit:` field would be self-referential and adds nothing. The commit SHA lives in git, not the evidence block.

## Constraints

- **TDD is non-negotiable** on any code-producing step.
- **Intent declaration is reviewable.** A wrong intent is drift with a label.
- **Every step produces an artifact that outlives the conversation.**
- **Evidence must be pasted or linked**, not claimed.
- **Escalation deep dives are conditional**, not routine.
- **Spike code never ships.**

## Governing-Skill Declaration

Every canonical-sdlc artifact carries frontmatter declaring the skill that governs its production.

**Required frontmatter** on every `*.plan.md`, `*.spec.md`, `adr-*.md`, `continuation*.md`, `epic.plan.md`, `epic.spec.md`, `rca.md`, and incident-response `spec.md`/`plan.md`:

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

The example shows the current (v10) shape. v11 plans will drop `mode:` for the `intent:`/`rigor:`/`scale:` triple once hook support lands (wave 2 of the axis transition); v≤10 plans carry a `mode:` line and keep it forever (§Legacy modes (v≤10)). For `incident-response` artifacts, use `incident: NNNN-<slug>` instead of `epic`/`wave`. Full field definitions live in the README frontmatter table; the two load-bearing specials are `governing-skill` — the skill declared after the producing step's heading (Step 1 → `agent-skills:idea-refine`; Step 3 → `superpowers:writing-plans`; Step 7 RCA → `canonical-sdlc`; `tune` UX flavor overrides Step 1 → `shape`, Step 4 → `impeccable`) — and `sdlc-step`, that step's number (`0` for `scale: epic` artifacts, `10` for `continuation.md`).

### Transition discipline

When advancing from one step to the next, announce explicitly:

> _**Advancing to Step N — &lt;title&gt;** (governing skill: `<skill-id>`). Loading now._

Then invoke `Skill` to load the governing skill.

## Legacy modes (v≤10)

Before v11, this skill ran on a single `mode:` axis with five values. Those names are **v≤10 vocabulary only** — v11 replaces them with the intent × rigor × scale triple. Each legacy mode maps to its nearest axis triple:

| v≤10 `mode:` | v11 triple (nearest equivalent) | Notes |
|---|---|---|
| `autonomous` | `build` · `audited` · `wave` | The `audited` mapping reflects what v≤10 `autonomous` behavior corresponded to — mandatory adversarial critic, per-step checkpoint commits, expanded stop-and-wake. **v11 defaults `build` to `peer-reviewed`**; the `audited` mapping is the behavioral equivalent, not the new default. |
| `epic-scope` | `<intent>` · — · `epic` | Scale-only; rigor is set by the eventual intent. Runs Steps 0–3. |
| `incident-response` | `incident-response` · `audited` · `wave` | Survives as an intent value; the mode's discipline is now the `audited` intent floor. |
| `design-refresh` | `tune` · `peer-reviewed` · `wave` (UX flavor) | Folded into `tune`; the impeccable `shape → craft → polish → critique` loop is unchanged (§Per-intent deltas). |
| `spike` | `spike` · `tested` · `wave`/`task` | Survives as an intent value; capped at `tested` (no code ships at any rigor). |

**Grandfathering rules:**

- **v≤10 plans keep their `mode:` vocabulary forever.** They are never retrofitted to the axis model; a v≤10 plan's `mode:` line stays valid and the v≤10 hooks and shape-tables keep enforcing it unchanged.
- **v11 plans never declare `mode:`.** They declare `intent:` / `rigor:` / `scale:` instead (frontmatter fields + hook parsing land in wave 2). The v≤10 flag / `model_plan` / matrix enforcement that gated on the legacy `mode:` value is documented in the v10 shape table (§Evidence) — wave 2 re-keys the hooks to the triple.
- **Not-Doing (D6): no per-intent dispatch-rules files.** v11 does NOT add per-intent rules files — this kills the five phantom per-mode dispatch files carried since v2. The single universal `.bionic/sdlc-dispatch-rules.json` remains the only dispatch-rules file; intent routing lives in SKILL.md's prose tables (§Step → governing-skill mapping, §Per-intent deltas), never in per-intent JSON.

## Evidence (two tiers)

Two evidence tiers: **Verification** (always mandatory; shape-checked by `canonical-sdlc-evidence-gate.sh` on v3–v10 plans) and **Handoff** (only when a plan spans sessions; skill prose + Stop-hook checkpoint). Decision-point prose to the user is the **User Decision Protocol** above, not a tier.

### Verification tier — mandatory, shape-checked

Every step has an evidence artifact recorded under `Step N:` in `## SDLC State`. The evidence-gate hook enforces presence on every `git commit`, plus a per-version **shape table** on the multi-field steps. `canonical_sdlc_version: 10` uses the **v10 table below**; versions `1`–`9` keep their own tables (the full version ladder — v3 through v9, each adding one universal Step-5 key — is documented in the README). **Never retrofit an older plan to a newer table.**

**v10 shape table:**

| Step | Required fields under `Step N:` | Notes |
|------|---------------------------------|-------|
| 0 | `prereqs: ok` | smoke |
| 1, 2, 3 | pointer | presence-only |
| 4 | pointer; also `worktree:`/`base-sha:`/`branch:` when `use_worktree: true` | presence-only |
| 5 Verify | `cmd:`/`pass:`/`total:`/`output:` (pass==total) AND a valid `## Verification Matrix` section (below) AND — once no row is `pending`/`blocked` — a non-empty `auditor:` pointer | tests floor lives in `## SDLC State`; per-row tier evidence lives in the matrix section; mid-discharge relaxation per v10.1 (§Step 5) |
| 6 Review | pointer to 5-axis body + critic findings | matrix re-validated here as a prefix check — a REFUTED row blocks the commit |
| 7 Document | `adr:` OR `rca:` OR `n/a:` | — |
| 8 Integrate & close | `merge:`, `worktree-removed:` AND (`cleanup:`, `tmp-wiped:`, `tasks-completed:` OR `cleanup: n/a`) | — |
| 9 Ship | `deploy:`, `verified-at:`, `monitor:` OR `n/a:` | n/a only when `deploy_target: none` |

Pointer steps in v10: 1, 2, 3, 4 — presence-only. Step 6 is deliberately **not** a pointer step, so a post-Verify commit re-runs the matrix prefix check.

**`## Verification Matrix` validation** fires at `current: 5` (via the Verify gate) and `current: 6..9` (as a prefix check). The hook checks the `stack-health:` line, the tier table's grammar (T0–T4, five cells, no literal `|`, status enum `pending|blocked|discharged|waived`), each non-waived row's per-tier keys (§Step 5) with the placeholder and live-tier-`n/a` bans, the `false-green:`/`rewritten:` pairing, and — once `current > 5` — a `CONFIRMED` auditor cell on every non-waived row. A `waiver:` entry (evidence cell or AC block) exempts its row. **v10.1:** at `current: 5` only, `pending`/`blocked` rows skip the per-tier key check (their contract bites at the 5→6 advance), and the `auditor:` pointer is demanded only when no such row remains.

**Block format** (v10). The Step-5 block in `## SDLC State`:

```
Step 5:
  cmd: bash test.sh
  pass: 332
  total: 332
  output: <docs-root>/plans/<slug>.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/tmp/audit.md
```

The discharged `## Verification Matrix` section lives elsewhere in the plan body — see §Step 0 for its skeleton.

**Reopened-wave upgrade path (v9→v10).** The no-retrofit rule has one narrow exception: a *reopened* plan whose remaining steps are exactly 5–9 may bump v9→v10 by (1) changing `canonical_sdlc_version` to `10`, (2) adding a user-approved `## Verification Matrix` covering only the reopened ACs, and (3) leaving its Steps 0–4 evidence untouched under v9 rules. This is the only sanctioned mid-life version bump; a plan still executing Steps 0–4 stays on its original version.

### Handoff tier — multi-session contract

Multi-session plans need fidelity across context resets. Handoff is its own tier, always preserved when a plan spans sessions.

#### Handoff section schema

A `## Handoff` section in the plan body. Per-field caps prevent unbounded growth:

```markdown
## Handoff
<!-- Always preserved. Updated at session end. -->

### Resume point
step: 4
sub-task: "implement predicate evaluator"
worktree: .worktrees/dispatch-hardening
branch: dispatch-hardening
last-commit: abc1234
session-count: 2

### Decisions ratified this session
<!-- max 5 bullets, ≤120 chars each. RESET each session. -->
- Step 0 confirmation uses single AskUserQuestion + DSL override

### Tried and rejected
<!-- max 5; "approach → reason rejected" form, ≤200 chars each. PERSISTS. -->
- Sidecar JSON for last_dispatched — reintroduces dual-source state

### Discovered surprises
<!-- max 5, ≤200 chars. Things future-you wouldn't infer from code. PERSISTS. -->

### Open blockers
<!-- max 5; each blocks specific step -->

### Uncommitted work
<!-- file + state, max 10 -->

### Resume protocol
<!-- one paragraph, ≤300 chars. Literal first instructions for next session. -->
```

#### Triggers — when handoff is written

Three triggers: session end mid-plan (`Stop` with `sdlc-step: < 10`); context-compaction risk (~90% utilization); or explicit user trigger (`/checkpoint`). The skill **rewrites the section in place** each time — never appends; handoff is bounded. Persistence is marked inline in the template (`RESET each session` vs `PERSISTS`).

#### When handoff is NOT written

Single-session plans never get a handoff section. Step 8 (cleanup half) strips the handoff if the plan opened and closed within one session.

## Continuation Artifacts

Long-running epics span sessions. Continuation artifacts make session handoff automatic.

**End-of-wave (`continuation.md`).** Step 9 emits `<docs-root>/plans/epic-NN-<slug>/continuation.md` summarizing:
- Wave just completed (id, scope, outcome).
- Integration branch + merge SHA. Next wave branches from this same integration branch at or after this SHA.
- Next wave (id, scope, entry step = 1).
- Open decisions or carry-overs from `## Assumptions`.

Frontmatter: `governing-skill: canonical-sdlc`, `sdlc-step: 10`, no `wave` field.

**Mid-wave checkpoint (`.bionic/tmp/continuation-checkpoint.md`).** The Stop hook detects an active canonical-sdlc run and autosaves a checkpoint to `.bionic/tmp/` capturing:
- Current SDLC State snapshot.
- In-flight work.
- Next recommended action on resume.

Zero user interaction. The next session reads it if present and resumes from the recorded state. Step 8's `.bionic/tmp/` wipe (cleanup half) clears this on merge.

## Hooks

Two `PreToolUse` hooks enforce the contract (full mechanism in the README):

- **`canonical-sdlc-evidence-gate.sh`** (`Bash`) — on `git commit`, blocks (exit 2) if the current step's evidence is missing or unreadable. For `canonical_sdlc_version: 10` it validates the v10 shape table and the `## Verification Matrix` (per-tier keys, waiver/CONFIRMED discipline); v1–v9 plans use their own tables, never retrofitted.
- **`canonical-sdlc-governing-skill.sh`** (`Write,Edit`) — blocks any artifact lacking `governing-skill:` frontmatter; on v4+ plans validates the 5 discriminator + 2 opt-in flags + `model_plan`; on **v10** plans additionally requires a `## Verification Matrix` section at `sdlc-step ≥ 3`. (In v≤10 this gating keyed on the legacy `mode:` value — §Legacy modes; wave 2 re-keys the hooks to the triple.)

## Subagent Dispatch Convention

Every subagent invoked during a canonical-sdlc step must receive a prompt prefix containing:

1. **Current step** — number, name, sub-skill invoked.
2. **Triple** — the declared `<intent> · <rigor> · <scale>`.
3. **Scope constraint** — what this agent may touch; what it must not.
4. **Artifact expected** — the evidence shape required for the step gate.
5. **Exit condition** — when to stop and report. Includes: "do not pivot approach; surface blockers to the main thread."
6. **Step-specific duties.** For Step 4 (implement) dispatches: *"Append a one-line entry to the plan file's `## Assumptions` section before your final commit whenever a decision resolves ambiguity. No silent choices."*
7. **Model & dispatch tier** (see §Model & Token Strategy). Default to a **fresh** subagent: mechanical / search / test-writing → fresh `model: sonnet`; implementation slices → fresh `model: sonnet` or `model: opus` per the slice's `complexity:` tag; root-cause debugging and Step 6 review → fresh `model: opus`. Use a **`fork`** only when the unit genuinely needs the inherited conversation/context — never to save effort (forks inherit the orchestrator's effort) and never to get a cheaper model (forks ignore `model`; under a Fable orchestrator a fork costs ~2× an Opus fork). Never switch the *main* model to run sub-work.
8. **Diagnostic-friction discipline (hardcoded).** Any dispatch that loads `map-instrument-narrow` — a Step 4/5 subagent that hit a bug, or a dedicated root-cause investigation — MUST include this directive **verbatim** in the subagent prompt:

   > Execute map-instrument-narrow with exquisite rigor and discipline. Absolutely no corner-cutting. Walk every phase gate in order — MAP → INSTRUMENT → NARROW — and write each phase's artifact before advancing past its gate. No fix code, and no "let me just try one thing first." No ad-hoc, trial-and-error theory-hopping: the data names the root cause, not your hunches. NO FIX CODE WITHOUT DATA. NO INSTRUMENTATION WITHOUT ARCHITECTURE.

   This is not paraphrasable and not optional. The canonical copy lives in `map-instrument-narrow`'s **Rigor Mandate** and in `.bionic/sdlc-dispatch-rules.json` (`diagnostic_friction.directive`); inject that exact string. Omitting it is the single most common cause of debugging that spins through ad-hoc theories instead of converging on the root cause.
9. **Auditor mandate (hardcoded).** Any Step-5 Independent Verification Auditor dispatch MUST include the Auditor Mandate **verbatim** in the subagent prompt (the canonical copy is the blockquote in §Step 5). Like point 8's Rigor Mandate, it is not paraphrasable and not optional — a paraphrased mandate is a weakened auditor.

This prevents subagent wander.

## Escalation Protocol

**Three-fail rule.** If the same step fails to produce valid evidence three times in a row:

> Interplay with the model-tier escalation ladder: a `standard` slice that fails twice on `model: sonnet` re-dispatches on `model: opus` (§Model & Token Strategy) — that Opus attempt is the third and final try before this rule fires. Tier escalation happens *within* the three-fail budget, not in addition to it.

1. **If failures are diagnostic** (tests failing, behavior diverging, surprise output) — invoke the **Autonomous Friction Protocol** (§Autonomous Friction Protocol). The three-fail counter resets after a completed MAP-INSTRUMENT-NARROW pass yields a root cause; it does NOT reset on additional speculative fixes.
2. **If failures are decision-related** (ambiguity, blocked-on-judgment, unclear requirement) — Stop. Do not attempt a fourth time. Surface to the user via **User Decision Protocol**: framing, options for unblocking, why-it-matters.
3. Wait for direction.

**Stop-and-wake list** (active for every unattended wave; expanded at `audited` rigor):

- Ambiguous spec requiring a judgment call.
- New external-API authentication setup.
- Configuration change that affects billing.
- Destructive database migration.
- Changes to secrets, API keys, or production infrastructure.
- Any action the user's `CLAUDE.md` marks as requiring approval.

**Incident-response additions:**
- The fix might mask a deeper issue.
- Root cause is not yet established.
- Blast radius is larger than initially scoped.

**On halt:** append a `## Wake Note` section to the plan file. The Wake Note follows the **User Decision Protocol** format — framing, numbered options, why-it-matters. Do not proceed past the block.

## Sub-Skill Loading

Do not preload sub-skills. Load each when you reach the step that invokes it. Release focus on a sub-skill's rules when you leave that step. Depth limit: 3 layers.

## Common Rationalizations

| Excuse | Reality |
|---|---|
| "This task is simple, I can skip the spec" | Simplicity is a claim, not a fact. If it's truly simple, the spec is 3 lines and costs nothing. |
| "The plan is obvious, I'll hold it in my head" | Plan files survive context compaction; mental plans don't. |
| "I can decide the approach as I implement" | Implementation-time decisions are un-reviewable and un-recorded. |
| "TDD is overkill for this change" | TDD is non-negotiable. |
| "I already know this API, source-driven-development is unnecessary" | Training data is stale. |
| "This decision is minor, it doesn't need an ADR" | "Minor" is judged from inside the context. Step 7 is the forcing function. |
| "The code works, that's enough evidence" | "Works on my machine" isn't evidence. |
| "The user is in a hurry, I should skip steps" | Declare a fast-path explicitly or walk the full path. |
| "I'll call this a refactor to skip the spec" | Intent is declared and reviewable — a wrong-intent label is drift with a label. `refactor` still owes its "behavior preserved" spec; no intent is spec-free. |
| "`tested` is fine for this auth change" | The flag floor forbids it — a security/privacy surface floors at `audited`. Floors are max-wins and upward-only; you cannot shop rigor below a derivable floor. |
| "It's really one big task, not a wave" | Scale-inflation (or deflation) dodges the matrix; the Step-3 checkpoint catches it. Declare the honest scale. |
| "The Step-0 interview is overkill; I'll just guess the intent" | The gray-zone collisions (mechanism-swap, reference-content) are exactly what the exception interview exists for — guessing is silent misclassification. |
| "The matrix tier is too strict for this AC" | Downgrading a tier is a user decision via the Waiver Protocol, recorded in the row — never a self-service call at Verify time. |
| "The auditor is overkill, my evidence is obviously fine" | Self-graded evidence is the exact root cause the auditor exists to kill. "Obviously fine" is the claim it falsifies. |
| "I'm confident in my self-review; the adversarial critic is overkill" | Self-review is bounded by what you thought to check. |
| "The assumption was obvious; no need to log it" | "Obvious" is judged from inside the moment. Log it. |
| "I can update `## SDLC State` after the commit" | The commit rhythm requires the current step's evidence line in place *before* staging — the evidence gate hook blocks the commit otherwise. |
| "An RCA is the same as an ADR" | ADRs are forward-facing; RCAs are backward-facing. |
| "Monitoring already exists; I don't need to check it" | Default assumption is a gap exists; prove "no gap" with evidence. |
| "Spike code is good, let's just ship it" | Re-enter a ship-capable mode at Step 1. |
| "Just send the user a paragraph asking what to do" | Use the User Decision Protocol. Numbered options + rationale + why-it-matters. No walls of text. |
| "Parallel dispatch is overhead for a small task" | The default is parallel. Justify sequential. |

## Red Flags — STOP and Correct

- Claiming a step is "done" without pasting or linking its evidence artifact.
- Skipping the load-time triple announcement.
- Declaring an intent that doesn't match the actual work.
- Skipping TDD on a code-producing step.
- Implementing before a plan file exists (any wave mode).
- Writing an ADR or RCA post-commit "as a follow-up."
- Producing an incident-response artifact labeled "ADR" when it should be an RCA.
- Closing an incident without a monitoring gap analysis.
- Shipping spike code.
- Reaching Step 9 with no artifact from Step 3.
- Committing without `## SDLC State` updated for the current step.
- A wave reaching Step 4 without `## Assumptions` seeded at plan time.
- Adversarial critic output that is pure agreement.
- Dispatching a subagent without the current-step + triple + scope-constraint prefix.
- Improvising past a stop-and-wake trigger.
- Step 8 closing without the wave's commits reachable from the integration branch.
- Declaring a plan without an `integration-branch:` line.
- Presenting a Step 0 confirmation display without the `integration-branch:` line.
- Asking the user a wall-of-text question instead of following the **User Decision Protocol**.
- Skipping the TaskCreate list or batching task completions at the end.
- Single-threading a step where 2+ subtasks are clearly independent.
- Closing Step 5 without an independent auditor report.
- A self-written `n/a` on a live-tier (T3/T4) matrix row (that is a Waiver Protocol decision, the user's call).
- A RED fixture that cannot structurally reach the failure it guards (a proxy regardless of RED→GREEN history).
- Claiming "delivered/fixed/verified" below the row's contracted tier.

## Quick Reference

| Step | Gate | Evidence |
|---|---|---|
| 0. Configure | v10 frontmatter (5 discriminator + 2 opt-in + `model_plan`) + `## Verification Matrix` derived; `integration-branch:` shown; user confirmed; task list created | `Step 0:` confirmation row |
| 1. Ideate | Refined idea + "Not Doing" list | Artifacts in spec |
| 2. Spec | Every requirement has an acceptance criterion | Spec doc |
| 3. Plan | No placeholders; `integration-branch:` + matrix locked; Step 4 expanded into slices | Plan file |
| 4. Implement | Every slice RED-first green; worktree if `use_worktree` | RED→GREEN commits |
| 5. Verify (gate) | Tests floor (`pass == total`); every matrix row discharged at its tier or waived; auditor CONFIRMED | `cmd:`/`pass:`/`total:`/`output:` + `auditor:` + discharged `## Verification Matrix` |
| 6. Review (gate) | Every axis has a verdict; independent critic attached | 5-axis body + critic findings |
| 7. Document | Every significant decision recorded | ADR(s); `rca.md` for `incident-response` |
| 8. Integrate & close | Wave merged into `integration-branch`; worktree removed; tmp wiped; tasks completed | `merge:`/`worktree-removed:` + cleanup fields |
| 9. Ship | Checklist + rollback; monitored, gap closed (`incident-response`) | Deployment + monitoring evidence |
| — Commit rhythm | Per-step commit; `## SDLC State` updated before staging | Commit in git (no `commit:` field) |
