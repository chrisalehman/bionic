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

Review is unchanged: structured 5-axis self-review (**always**) plus an **INDEPENDENT** adversarial critic (**mandatory in `autonomous`, `incident-response`, `design-refresh`** — never self-graded). The Verify-gate **auditor** and the Review-gate **critic** are distinct: the auditor falsifies the *evidence*, the critic falsifies the *code* (see Steps 5–6).

**Why lower tiers are proxies (the locator model).** Every tier below the live walk tests a proxy, and each reports PASS at its own blind spot: unit tests pass on mocked seams; hermetic tests pass on fixtures that may not match the real data shape; a ref-walk over a bare canvas drives nothing yet "completes"; a screenshot of a degenerate frame satisfies "something rendered." A higher tier exists precisely to kill the lie the tier below cannot see. Mock-green + real-red is not a contradiction but a **locator** — the bug lives in exactly the layer the proxy elides. The matrix pins each AC to the tier that can actually catch its failure, so no AC is discharged by a proxy that structurally cannot reach its bug.

### Decomposition unit per step

The *slice* (atomic RED→GREEN commit) stays **exclusive to Step 4 Implement**. Other fanned-out steps decompose by their own unit:
- **Step 5 Verify** decomposes by **matrix row** — one unit per acceptance criterion (`5/<AC-id>`), operating over Step 4's slices.
- **Step 6 Review** decomposes by **axis × stance** (shard by subsystem on large diffs).
- **Step 8 Integrate & close** is **atomic** — a single task.

Generalize the `<step>/<unit>:` task-naming so any fanned-out step labels its units: `4/<slice>`, `5/<AC-id>`, `6/<axis-or-stance>`. Step 8 stays one task. See §Task Tracking.

**REQUIRED SUB-SKILLS.** The `needs`-declared skills load only when the step that invokes them is active.

## Load-time Announcement

When this skill is loaded, the **first user-facing action** is to announce the mode in the form:

> **Canonical SDLC engaged — mode: `<mode>`.**

If the mode is not yet declared, announce:

> **Canonical SDLC engaged — mode: pending declaration. Declare one of: `autonomous` (default), `epic-scope`, `incident-response`, `design-refresh`, `spike`.**

No other work proceeds until mode is declared.

## Taxonomy

| Tier | Word | Definition |
|---|---|---|
| 1 | **epic** | Large body of work spanning multiple sessions. |
| 2 | **wave** | One-session chunk of an epic. If it doesn't fit, split into more waves. |
| 3 | **step** | One of the canonical-sdlc steps (0–9) inside a wave. |
| — | *slice* | *Informal.* An atomic implementation commit inside a wave's Step 4. A wave can have 1 or many slices. Slices don't get their own plan files. |

**Naming convention.** Artifacts live in a directory-per-epic layout with zero-padded epic numbers and human-readable slugs. One slug per epic is chosen at epic-scope time and used across `specs/`, `plans/`, and `adrs/`:

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

1. **Epic scoping** — declared via `epic-scope` mode. Runs Steps 1–3 only. Produces `epic.spec.md` + `epic.plan.md`. Carves the work into waves. Does **not** execute Steps 4–9.
2. **Wave execution** — the default. Declared via `autonomous` (default), `incident-response`, `design-refresh`, or `spike`. Runs the full applicable step set for one wave. Each wave re-enters Steps 1–3 at greater depth than the epic plan supplied; **trust but verify** the epic's assumptions, do not re-derive from scratch.

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

**Hard triggers** (any one → invoke):
- User begins a new feature, architectural change, or multi-day effort.
- User asks "what's next?" on an in-progress large-scale effort.
- Session start on a branch that has an active plan file.
- A production incident needs triage, fix, deploy, and postmortem (→ `incident-response`).
- A visual/UX refresh on an existing feature (→ `design-refresh`).

**Soft triggers** (two or more → invoke):
- The effort touches more than one component.
- The effort will ship to users.
- A spec or plan already exists.
- The work requires decisions that future maintainers will need.

## Mode Selector

Declare the mode at entry. The mode determines which steps apply. **`autonomous` is the default** — any other mode is an explicit declaration.

| Mode | When | Steps applied |
|---|---|---|
| `autonomous` (default) | Any wave-level build, fix, refactor, or user-facing work | 0–9; Step 6 Review's adversarial critic **mandatory**; per-step checkpoint commits (commit rhythm); full stop-and-wake list |
| `epic-scope` | Beginning a new epic; no implementation yet; needs carving into waves | 0–3 only; produces `epic.spec.md` + `epic.plan.md`. Short-circuits before Step 4. |
| `incident-response` | Live or recent production incident needing detection confirmation, diagnosis, fix, deploy, monitoring gap closure, and postmortem RCA | Triage-compressed 1 → 2–4 → **5 Verify** → **6 Review** → **Step 7 produces RCA** (not ADR) → **8 Integrate & close** → **Step 9 includes monitoring verification + gap closure** |
| `design-refresh` | Visual/UX refresh on an existing feature; no behavior change | `shape` prepended to Step 1; Step 2 = visual acceptance criteria; Step 4 uses `impeccable` + `polish` family; Step 5 Verify heavily weighted; Step 6 Review = 5 code axes only (design quality is evaluated in the Step 4 critique loop) |
| `spike` | Timeboxed research or prototype; **no code ships** | Prereqs → woven source-driven → brief writeup at `<docs-root>/spikes/`. No worktree, no ADR, no commits to integration branch. |

Mode declaration is reviewable. A feature disguised as a different mode to skip steps is drift with a label.

### `autonomous` mode in particular (the default)

This is the default because Bionic philosophy is "operate autonomously." The mode assumes no human is watching Steps 4–9 in real time, and tightens evidence discipline accordingly: the Step 6 adversarial critic becomes **mandatory**, per-step checkpoint commits fire (the commit rhythm), and the stop-and-wake list expands (see the Mode Selector row).

**Autonomous does NOT mean "skip Step 1 Q&A."** The autonomous span is **Steps 4–9**. The user-engagement sequence is:

| Step | Engagement |
|---|---|
| 1. Ideate | **Interactive Q&A with the user.** Extensive back-and-forth on scope, non-goals, alternatives. |
| 2. Spec | **Semi-interactive.** Translate Step 1 into a testable contract. Surface remaining ambiguities as Wake Notes; otherwise proceed. |
| 3. Plan | **Autonomous write → one approval checkpoint.** Claude writes the plan; user reviews and approves before Step 4 begins. |
| 4–9 | **Fully autonomous** within the stop-and-wake rules. |

Skipping Step 1 Q&A to "save time" is the single highest-risk move.

**Step → governing-skill mapping:**

**Tier** = default dispatch target (see §Model & Token Strategy): **O** = orchestrator (main
thread) · **E** = execution (fresh `model: opus` or `model: sonnet`, routed by the slice's
`complexity:` tag; fork only if context-heavy) · **X** = explore/mechanical/test (fresh
`model: sonnet`). Default hint only; the Strategy section governs.

| Step | Tier | Governing skill | On-demand sub-skills |
|---|---|---|---|
| 0 Configure | O | `canonical-sdlc` + `agent-skills:context-engineering` | — |
| 1 Ideate | O | `agent-skills:idea-refine` | — |
| 2 Spec | O | `agent-skills:spec-driven-development` | — |
| 3 Plan | O | `superpowers:writing-plans` | — |
| 4 Implement | E + X | `agent-skills:incremental-implementation` | `superpowers:test-driven-development` (every slice); `superpowers:executing-plans`; `agent-skills:source-driven-development`; `superpowers:systematic-debugging`; `agent-skills:documentation-and-adrs`; `superpowers:using-git-worktrees` (if `use_worktree`) |
| 5 Verify (gate) | X → O | `superpowers:verification-before-completion` | tests/build modality: the suite · browser modality: `browser-verify` (drives `playwright-cli`) → escalate `agent-skills:browser-testing-with-devtools` (deep inspection only); `agent-skills:frontend-ui-engineering` pre-verify |
| 6 Review (gate) | E | `agent-skills:code-review-and-quality` | adversarial stance: independent subagent dispatch (MANDATORY autonomous/incident/design-refresh); `agent-skills:security-and-hardening` (security flag); `agent-skills:performance-optimization` (perf flag) |
| 7 Document | O / E | `agent-skills:documentation-and-adrs` | — |
| 8 Integrate & close | O / X | `superpowers:finishing-a-development-branch` | `canonical-sdlc` (cleanup half) |
| 9 Ship | E / O | `agent-skills:shipping-and-launch` | `agent-skills:ci-cd-and-automation` (new pipelines only) |
| — Commit rhythm (cross-cutting) | O | `agent-skills:git-workflow-and-versioning` | fires per step, not at a position |

#### Autonomous Friction Protocol

When autonomous-mode work hits friction, **diagnose before escalating**. Friction is either:

- **Diagnostic friction** — direction is clear, code misbehaves (test fails, behavior diverges from spec, surprise output). → MAP first.
- **Decision friction** — the direction itself is in question (which approach, which abstraction, which scope). → Surface via User Decision Protocol.

For diagnostic friction in autonomous mode:

1. **Load `map-instrument-narrow` immediately** and dispatch it to a **fresh subagent carrying the verbatim Rigor Mandate** (Subagent Dispatch Convention point 8). Do not write speculative fix code first. Speculative-fix-before-instrumentation regresses pass rates more often than it improves them.
2. **No fix code** until NARROW phase yields a named root cause with data evidence.
3. **Three-fail rule applies AFTER one full MAP-INSTRUMENT-NARROW pass**, not before. If a complete pass does not yield a clean root cause, loop back to MAP (your architectural model was incomplete) — do not throw speculative fixes.
4. **After root cause is known**, the *bubble-up vs. proceed-directly* judgment is a separate decision per the User Decision Protocol. Diagnosis ≠ permission to fix in scope; trivial fixes proceed, scope-expanding fixes surface.
5. **Recurse on layered root causes.** A pass yields a *confirmed* root cause plus, often, deeper or sibling causes (see `map-instrument-narrow` → **Recursive Root-Cause Detection**). The orchestrator owns the **root-cause tree** — record it in the plan's `## Assumptions` / RCA section — and dispatches a **fresh subagent per open candidate**: serial for a chain of blockages, depth-first for nested causes, each carrying the same Rigor Mandate and a clean context (never reuse the contaminated one). Bound recursion at `max_depth: 4`; when a deeper cause expands scope beyond the wave, stop and surface the tree via the User Decision Protocol. A wave's diagnosis is complete only when every tree node is `confirmed` or explicitly deferred.

**Anti-pattern:** "I'll try one thing first, then instrument if it doesn't work." That "one thing" mutates state. Subsequent instrumentation captures post-attempt state, not the original bug. **MAP before any state change.**

This protocol is load-bearing for every autonomous wave. It is not optional.

### `epic-scope` mode in particular

`epic-scope` only runs Steps 0–3, producing the epic-level spec and plan. After `epic-scope` completes, each wave is a separate subsequent invocation — typically `autonomous`.

| Step | Governing skill |
|---|---|
| 0. Configure | `canonical-sdlc` + `agent-skills:context-engineering` |
| 1. Ideate | `agent-skills:idea-refine` |
| 2. Spec | `agent-skills:spec-driven-development` (produces `epic.spec.md`) |
| 3. Plan | `superpowers:writing-plans` (produces `epic.plan.md`; carves waves; declares `integration-branch:`) |
| 4–9 | **N/A** — `epic-scope` stops here. |

### `incident-response` mode in particular

`incident-response` is the mode for production incidents. The outcome is a **closed incident with documented prevention**.

| Step | Governing skill | Notes |
|---|---|---|
| 0. Configure | `canonical-sdlc` + `agent-skills:context-engineering` | — |
| 1. Triage (compressed Ideate) | `agent-skills:idea-refine` (compressed to triage) | — |
| 2. Spec (repro + closure criteria) | `agent-skills:spec-driven-development` (writes `incidents/NNNN-<slug>/spec.md`) | — |
| 3. Plan (debug + fix) | `superpowers:writing-plans` (writes `plan.md`; integration branch is typically `main` or `hotfix/<id>`) | — |
| 4. Diagnose + Implement | `superpowers:systematic-debugging` → `agent-skills:incremental-implementation` | failing test = incident repro |
| 5. Verify (gate) | `superpowers:verification-before-completion` | tests/build modality always; browser modality via `browser-verify`/`playwright-cli` (N/A if non-UI) → deep-debug `agent-skills:browser-testing-with-devtools` |
| 6. Review (gate) | `agent-skills:code-review-and-quality` + adversarial critic (**MANDATORY**) | critic framing: "does the fix mask a deeper issue?" |
| 7. **RCA (not ADR)** | `canonical-sdlc` (writes `rca.md`) | — |
| 8. Integrate & close | `superpowers:finishing-a-development-branch` (merge to declared integration branch) + `canonical-sdlc` (cleanup) | — |
| 9. Ship + Monitor + Close gap | `agent-skills:shipping-and-launch` (deploy → monitor through ≥1 cycle → close monitoring gap) | — |

**RCA required shape** (`incidents/NNNN-<slug>/rca.md`): summary, timeline, root cause, contributing factors, the fix, prevention (each measure links a commit/ticket), and monitoring-gap analysis. Full section-by-section shape and rules: see the canonical-sdlc README (`## RCA shape`).

**Incident-specific stop-and-wake:** halt if the fix might mask a deeper issue, root cause is not yet established, or blast radius is larger than scoped.

### `design-refresh` mode in particular

`design-refresh` wraps impeccable's native design lifecycle (`shape → craft → polish → critique`) inside the canonical-sdlc shell. **Behavior does not change.**

| Step | Governing skill | Notes |
|---|---|---|
| 0. Configure | `canonical-sdlc` + `agent-skills:context-engineering` | `teach-impeccable` if `.impeccable.md` missing |
| 1. Ideate | **`shape`** | — |
| 2. Spec | `agent-skills:spec-driven-development` | — |
| 3. Plan | `superpowers:writing-plans` | — |
| 4. Implement (**loop**) | **`impeccable`** (`/impeccable craft`) | (a) craft → (b) polish + harden + normalize → (c) critique. Iterate. |
| 5. Verify (gate, **heavily weighted**) | `superpowers:verification-before-completion`; browser modality `browser-verify`/`playwright-cli` + **`audit`** | browser evidence per state; `audit` scored technical-quality report; deep-debug → `agent-skills:browser-testing-with-devtools` |
| 6. Review (gate, **5 code axes only**) | `agent-skills:code-review-and-quality` + adversarial critic | design quality evaluated in Step 4 critique loop; critic framing: "find visual regressions and a11y failures" |
| 7. Document decisions | `agent-skills:documentation-and-adrs` | — |
| 8. Integrate & close | `superpowers:finishing-a-development-branch` + `canonical-sdlc` (cleanup) | — |
| 9. Ship | `agent-skills:shipping-and-launch` | **`extract`** (if reusable patterns) |

**Step 4 loop structure:** (a) build → `/impeccable craft` (skips shape; loads references from the brief); (b) polish + harden + normalize; (c) critique (scored eval); (d) iterate — if critique flags issues, classify and loop.

**Step 4 loop exit gate:**
- Critique's Nielsen heuristic scores ≥ 3/4 on all 10 heuristics.
- Cognitive load score ≤ 1.
- AI slop verdict: passes.
- Polish checklist complete.

### `spike` mode in particular

**Constraints:**
- **No worktree.** Research happens on a scratch branch or uncommitted.
- **No ADR, no plan file, no spec.**
- **No commits to the integration branch.**
- If a spike reveals the work is worth shipping, **declare a new mode** and re-enter at Step 1.

| Step | Governing skill |
|---|---|
| 0. Configure | `canonical-sdlc` + `agent-skills:context-engineering` |
| — Research | `agent-skills:source-driven-development` (woven, on-demand) |
| — Writeup | informal — writes `<docs-root>/spikes/spike-<slug>-<YYYYMMDD>.md` |

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

- **Announce the mode** per the Load-time Announcement section.
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

**Action:** Six sub-steps:

1. **Pre-flight environment check.**
   - **(a) Bionic root.** Check `<project>/.bionic/` exists. If absent, ask to create.
   - **(b) Docs root.** Read `<project>/.bionic/config.yaml`'s `docs-root:`; default `.bionic/docs`. Ensure `{specs,plans,adrs,incidents}/` exist.
   - **(c) Ephemeral workspace.** `mkdir -p <project>/.bionic/tmp/`.
   - **(d) Hook installation.** Verify `~/.claude/hooks/canonical-sdlc-{evidence-gate,governing-skill}.sh` are present and executable. If any are missing, warn and record an `## Assumptions` entry.

2. **Infer recommended values** from available context.

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
   | `model_plan` | Derived from `multi_agent` and the **detected session model** (see §Model & Token Strategy). `true` → `orchestrator=<detected>; exec-complex=opus-fresh; exec-standard=sonnet-fresh; explore=sonnet-fresh`. `false` → `main=<detected>` (dial-down offered). Surfaced for confirmation; **hook-enforced for v4+** autonomous plans. |

3. **Derive the Verification Matrix.** One row per acceptance criterion (from the Step 2 spec; a wave planned before its spec is final reconciles rows against the spec at Step 2). Each row gets a tier from browser-verify's T0–T4 ladder by these **inference defaults**:
   - user-visible behavior change → **T3**;
   - engine/rendering-divergent behavior → **T2 (both engines)** for the divergence AND **T3** for the user-visible AC;
   - pure substrate/internal, no runtime surface → **T1/T2** with a one-line justification;
   - perceptual/design fidelity → **T3** (cold client), **T4** available;
   - docs/ADR ACs → **T0/none**.

   Store it as a top-level `## Verification Matrix` plan section (**not** inside `## SDLC State`), row schema `| AC | tier | status | evidence | auditor |`, status starting `pending`. **Grammar:** exactly five cells per row; **no literal `|` inside a cell** (a sheared row blocks loudly). Skeleton:

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

4. **Present the confirmation display — in full, always.** The display below is a mandatory, untruncatable artifact: every section, every flag, every line, every inference rationale, **and every matrix row**, rendered as one block in the conversation. Never elide, summarize, sample ("key flags: …"), or defer any portion of it — an abbreviated display invalidates the confirmation, because the user is approving exactly what they can see. The matrix block is rendered IN FULL under the same rule — **even past 12 ACs, print every row** (a matrix is exactly what must not be sampled). If a value is unknown, print the line with the value marked `unknown` rather than dropping the line. The `integration-branch:` line is load-bearing — Step 8 merges every wave into it; a display missing this line is an invalid confirmation, exactly like a missing flag.

   ```
   ═══ Plan Configuration — confirm before Step 1 ═══
   environment:
     bionic-root:  /Users/me/proj/.bionic               [verified]
     docs-root:    .bionic/docs                         [default]
     bionic-tmp:   /Users/me/proj/.bionic/tmp           [ready]
     hooks:        evidence-gate, governing-skill       [all installed]

   slug: <inferred-from-conversation>
   mode: autonomous
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

5. **Block until explicit confirmation.** No timeout, no implicit acceptance.

6. **Task-list creation is the immediate next action after approval.** The instant confirmation arrives — before any Step 1 work — run this fixed sequence:
   1. **Announce it:** "Step 0 confirmed — creating the task list."
   2. **Create the full TaskCreate list:** tasks `0:`, `1:`, ..., `9:`, one per planned step. Mark `0:` `completed` immediately.
   3. **Then transition to Step 1** (idea-refine).

   Nothing else runs between approval and list creation.

**Override DSL grammar.** The user's reply is parsed against:

```
reply        := overrides? "confirm"
overrides    := override ("," override)* ","?
override     := "set" flag "=" value
              | "set" "verify" "(" AC-id ")" "=" tier
              | "change" flag "to" value
```

Accepted: `confirm`; `set use_worktree=true, confirm`; `set surface_type=graphql, set language=python, confirm`; `set integration-branch=develop, confirm`. **Matrix tier override:** `set verify(AC-B2.1)=T2, confirm` retiers a matrix row before lock. Model-plan keys are valid override targets: `set orchestrator=fable-high, confirm` (multi_agent=true); `set exec-standard=opus, confirm` (route standard slices to opus too — equivalent to disabling complexity routing); `set exec-complex=sonnet, confirm` (accepted but discouraged; warn before applying); `set execution=opus-only, confirm` (shorthand for `exec-standard=opus`); `set main_model=sonnet, confirm` (multi_agent=false dial-down).

On accept, write final values into plan frontmatter literally — every flag as an explicit `<key>: <value>` line. The plan carries `canonical_sdlc_version: 10` plus all 5 discriminator flags, 2 opt-in flags, and a single-line `model_plan:` recording the confirmed tiers (e.g. `model_plan: orchestrator=fable-5-high; exec-complex=opus-fresh; exec-standard=sonnet-fresh; explore=sonnet-fresh`). The confirmed `integration-branch` and the derived `## Verification Matrix` are carried forward: when the plan file is written at Step 3, its `## SDLC State` section opens with the Step-0-confirmed `integration-branch: <name>` line, and the plan body carries the locked `## Verification Matrix` section. For v4 and later autonomous plans the governing-skill hook **requires** `model_plan`; for v10 it additionally requires the `## Verification Matrix` section at `sdlc-step ≥ 3` — a missing value blocks the write (exit 2).

**Two-layer enforcement.** Layer 1 (soft): SKILL.md mandates Step 0 — do not proceed without explicit user confirmation. Layer 2 (hard, `canonical-sdlc-governing-skill.sh`, on `PreToolUse|Write,Edit`): for v4+ autonomous plans, a missing flag / `model_plan` / (v10) matrix section → exit 2.

**Mid-plan reconfiguration.** Edit plan frontmatter directly; the new value takes effect immediately on next hook read.

**Legacy plan handling.** `canonical_sdlc_version: 1`/`2` are grandfathered (no flag enforcement); `3`–`9` stay enforced under their own shape tables (§Versioning). **DO NOT retrofit a newer version's requirements into an older plan** — an in-flight plan would start blocking mid-wave. This covers every universal-key addition (v7 `bundle-fresh:`, v8 `drive-check:`, v9 `stack-health:`) **and the v10 Verification Matrix**: never add a matrix to a v9-or-earlier plan.

**Gate:** Plan frontmatter contains `canonical_sdlc_version: 10` plus all 5 discriminator flags, 2 opt-in flags, and `model_plan`; the derived `## Verification Matrix` exists. The confirmation display included the `integration-branch:` line and every matrix row. User reply ended with `confirm` or `confirmed`.

**Evidence:** A line in `## SDLC State`: `Step 0: configured at <ISO-timestamp> via <reply-summary>; model_plan=<confirmed tiers>; integration-branch=<name>`.

### Step 1 — Ideate (`agent-skills:idea-refine`)
- **Goal:** Pin scope and non-goals before they get encoded as requirements.
- **Action:** Run the 6-lens refinement + "Not Doing" list. Always prefer `idea-refine` over `superpowers:brainstorming`.
- **Engagement:** Interactive Q&A with the user. **Mandatory in every mode.** Every decision point follows the **User Decision Protocol**. The alternatives lens must check:
  1. Existing design docs (`.bionic/memory/*.md` including every file linked from `INDEX.md`).
  2. Prior plans and specs in `<docs-root>/plans/` and `<docs-root>/specs/` — walk every epic directory.
  3. Prior ADRs under `<docs-root>/adrs/`.
  4. Prior incidents and RCAs under `<docs-root>/incidents/`.
  5. In wave mode: the epic plan and spec for the current epic. Trust but verify.
- **Parallelization:** dispatch parallel Explore agents for distinct lenses when 2+ are independent.
- **Mode substitutions:**
  - `design-refresh`: governing skill becomes **`shape`** (not `idea-refine`).
  - `incident-response`: compress to triage — confirm incident reality, scope blast radius, assign severity.
- **Gate:** Refined idea statement + explicit "Not Doing" list + alternatives lens cites prior design artifacts.
- **Evidence:** Artifacts captured in the spec file.

### Step 2 — Spec (`agent-skills:spec-driven-development`)
- **Goal:** Convert the refined idea into a testable contract.
- **Action:** Write requirements + acceptance criteria.
- **Parallelization:** surface_type specialist + user-experience critic in parallel.
- **Gate:** Every requirement has an acceptance criterion.
- **Evidence:** Spec doc at `<docs-root>/specs/epic-NN-<slug>/wave-NN-<slug>.spec.md` (wave); `epic.spec.md` (epic-scope); `incidents/NNNN-<slug>/spec.md` (incident).
- **Mode substitutions:**
  - `design-refresh`: spec is **visual** (tokens, contrast, focus, interaction, responsive) plus "all existing tests still pass."
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
  - `epic-scope`: ask the user. Record in the epic plan. Waves inherit.
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
- **Mode substitutions:**
  - `design-refresh`: governing skill is **`impeccable`**, invoked as `/impeccable craft`. Step 4 runs as a loop: craft → polish/harden/normalize → critique → iterate.
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

**Mode weight.** `design-refresh`: **heavily weighted** — T3 browser evidence per state + an `audit` scored technical-quality report; use `impeccable` in Step 4 and `agent-skills:frontend-ui-engineering` pre-verify.

### Step 6 — Review (gate: "is it well-made?") (`agent-skills:code-review-and-quality`)

The Review gate proves the change is well-made, by stance (see §Verification model). Decompose by **axis × stance**; shard by subsystem on large diffs.

**Stance 1 — structured 5-axis self-review (always).**
- **Axes:** correctness, readability, architecture, security, performance. Every axis gets an explicit PASS / FLAG / FAIL verdict.
- **Reviewer tier:** all review agents (both stances) dispatch at Tier 2 (fresh `model: opus`) regardless of which tier wrote the code — verification is never cheaper than authorship.
- **Architecture-axis closure check:** for each new primitive/substrate added in this wave, trace user input → new code; also confirm the Step-5 T3 readback reached the same code (see Step 5). If the chain breaks (no callsite reaches the new code), the substrate is dead and the architecture axis is FAIL.
- **Parallelization:** all 5 axes run in parallel.
- **Escalations:** security axis flags → `agent-skills:security-and-hardening`. Performance axis flags → `agent-skills:performance-optimization`.
- **Mode substitution:** `design-refresh` — review the **5 code axes only**. Design quality was already evaluated in Step 4's critique loop.

**Stance 2 — adversarial critic.**
- **Mandatory in:** `autonomous`, `incident-response`, `design-refresh`. **Optional in:** `spike`. N/A in `epic-scope`.
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
- **Action (`autonomous`, `epic-scope`, `design-refresh`):** Review plan and implementation commits; verify every significant decision has an ADR.
- **Action (`incident-response`):** **write the RCA** (postmortem, not ADR — see RCA shape above).
- **Parallelization:** ADR draft + RCA draft (if applicable) in parallel.
- **Gate:** Every flagged decision has a written record.
- **Evidence:** ADR file(s) at canonical path, or `rca.md` for incident-response.

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
- **Mode substitution (`design-refresh`):** invoke **`extract`** if reusable patterns introduced.
- **Mode substitution (`incident-response`):** Step 9 expands to:
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
- **Mode declaration is reviewable.** A wrong mode is drift with a label.
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

For incident-response artifacts, use `incident: NNNN-<slug>` instead of `epic`/`wave`. Full field definitions live in the README frontmatter table; the two load-bearing specials are `governing-skill` — the skill declared after the producing step's heading (Step 1 → `agent-skills:idea-refine`; Step 3 → `superpowers:writing-plans`; Step 7 RCA → `canonical-sdlc`; `design-refresh` overrides Step 1 → `shape`, Step 4 → `impeccable`) — and `sdlc-step`, that step's number (`0` for epic-scope artifacts, `10` for `continuation.md`).

### Transition discipline

When advancing from one step to the next, announce explicitly:

> _**Advancing to Step N — &lt;title&gt;** (governing skill: `<skill-id>`). Loading now._

Then invoke `Skill` to load the governing skill.

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
| 5 Verify | `cmd:`/`pass:`/`total:`/`output:` (pass==total) AND a non-empty `auditor:` pointer AND a valid `## Verification Matrix` section (below) | tests floor + auditor pointer live in `## SDLC State`; per-row tier evidence lives in the matrix section |
| 6 Review | pointer to 5-axis body + critic findings | matrix re-validated here as a prefix check — a REFUTED row blocks the commit |
| 7 Document | `adr:` OR `rca:` OR `n/a:` | — |
| 8 Integrate & close | `merge:`, `worktree-removed:` AND (`cleanup:`, `tmp-wiped:`, `tasks-completed:` OR `cleanup: n/a`) | — |
| 9 Ship | `deploy:`, `verified-at:`, `monitor:` OR `n/a:` | n/a only when `deploy_target: none` |

Pointer steps in v10: 1, 2, 3, 4 — presence-only. Step 6 is deliberately **not** a pointer step, so a post-Verify commit re-runs the matrix prefix check.

**`## Verification Matrix` validation** fires at `current: 5` (via the Verify gate) and `current: 6..9` (as a prefix check). The hook checks the `stack-health:` line, the tier table's grammar (T0–T4, five cells, no literal `|`), each non-waived row's per-tier keys (§Step 5) with the placeholder and live-tier-`n/a` bans, the `false-green:`/`rewritten:` pairing, and — once `current > 5` — a `CONFIRMED` auditor cell on every non-waived row. A `waiver:` entry (evidence cell or AC block) exempts its row.

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
- **`canonical-sdlc-governing-skill.sh`** (`Write,Edit`) — blocks any artifact lacking `governing-skill:` frontmatter; on v4+ autonomous plans validates the 5 discriminator + 2 opt-in flags + `model_plan`; on **v10** autonomous plans additionally requires a `## Verification Matrix` section at `sdlc-step ≥ 3`.

## Subagent Dispatch Convention

Every subagent invoked during a canonical-sdlc step must receive a prompt prefix containing:

1. **Current step** — number, name, sub-skill invoked.
2. **Mode** — the declared canonical-sdlc mode.
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

1. **If failures are diagnostic** (tests failing, behavior diverging, surprise output) — invoke the **Autonomous Friction Protocol** (see autonomous-mode section). The three-fail counter resets after a completed MAP-INSTRUMENT-NARROW pass yields a root cause; it does NOT reset on additional speculative fixes.
2. **If failures are decision-related** (ambiguity, blocked-on-judgment, unclear requirement) — Stop. Do not attempt a fourth time. Surface to the user via **User Decision Protocol**: framing, options for unblocking, why-it-matters.
3. Wait for direction.

**Stop-and-wake list** (active in `autonomous`):

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
| "This is just a bugfix; `autonomous` is overkill" | A bugfix is still a code change. |
| "This is just a refactor; no spec needed" | "All existing tests still pass" is the spec. |
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
- Skipping the load-time mode announcement.
- Declaring a mode that doesn't match the actual work.
- Skipping TDD on a code-producing step.
- Implementing before a plan file exists (any wave mode).
- Writing an ADR or RCA post-commit "as a follow-up."
- Producing an incident-response artifact labeled "ADR" when it should be an RCA.
- Closing an incident without a monitoring gap analysis.
- Shipping spike code.
- Reaching Step 9 with no artifact from Step 3.
- Committing without `## SDLC State` updated for the current step.
- `autonomous` mode without `## Assumptions` seeded at plan time.
- Adversarial critic output that is pure agreement.
- Dispatching a subagent without the current-step + mode + scope-constraint prefix.
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
