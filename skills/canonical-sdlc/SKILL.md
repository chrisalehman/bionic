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
  - superpowers:requesting-code-review
  - superpowers:receiving-code-review
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

**Core principle: NO STEP SKIPPED WITHOUT A DECLARED FAST-PATH. NO COMPLETION WITHOUT EVIDENCE FROM EVERY APPLICABLE STEP.**

Violating the letter of this process is violating the spirit of this process.

**Layer:** Governance (process constraint). Loads when a large-scale effort begins or when picking the skill for the current step.

**Routing principle — superpowers vs agent-skills.** The two plugins are interleaved because they solve orthogonal problems:

- `superpowers:` owns **discipline anchors** — planning, TDD, debugging, verification, review response, worktree isolation, parallel dispatch. Its rules are calibrated against Claude's known failure modes (fabrication, sycophancy, rationalization).
- `agent-skills:` owns **content rubrics** — spec shape, 5-axis review, 6-lens ideation, domain deep-dives (security, performance, UI). Supplies the *shape* each step's artifact should take.

On overlap, route by kind, not by plugin. On ties, prefer `superpowers:`.

**REQUIRED SUB-SKILLS** (declared in `needs`):
- Operational and technique skills listed in the frontmatter. Load each only when the step that invokes it is active.

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
| 3 | **step** | One of the 14 canonical-sdlc steps (0–14) inside a wave. |
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

1. **Epic scoping** — declared via `epic-scope` mode. Runs Steps 1–3 only. Produces `epic.spec.md` + `epic.plan.md`. Carves the work into waves. Does **not** execute Steps 4–14.
2. **Wave execution** — the default. Declared via `autonomous` (default), `incident-response`, `design-refresh`, or `spike`. Runs the full applicable step set for one wave. Each wave re-enters Steps 1–3 at greater depth than the epic plan supplied; **trust but verify** the epic's assumptions, do not re-derive from scratch.

## The Iron Law

```
NO STEP SKIPPED WITHOUT A DECLARED FAST-PATH.
NO COMPLETION WITHOUT EVIDENCE FROM EVERY APPLICABLE STEP.
```

## Parallel by Default

Every step in canonical-sdlc looks for parallelizable work. If 2+ subtasks have no
data dependency, dispatch subagents in one Agent call batch. Reserve single-thread
execution for genuinely sequential work or when shared-state coordination cost
exceeds parallel speedup.

Concretely:
- Step 1 ideate: parallel-dispatch lens exploration (multiple Explore agents)
- Step 2 spec: surface_type specialist + user-experience critic in parallel
- Step 3 plan: research alternatives in parallel forks; converge in main thread
- Step 4 implement: if slices are independent, parallel implementer agents
- Step 5 browser verify + Step 6 verify done: parallel
- Step 7 review: 5-axis parallel (current behavior); extend with Step 8 critics
- Step 9 document: ADR draft + RCA draft (if applicable) in parallel

The default is parallel. Justify sequential.

## Task Tracking (mandatory)

Every canonical-sdlc run maintains a TaskCreate list with this naming convention:
- `<step>: <description>` for single-step work (e.g., `3: Write plan.md`)
- `<step>/<slice>: <description>` for sliced work (e.g., `4/2: implement evaluator predicate`)

Rules:
- Create the task list at end of Step 0 with one task per planned step (0–14).
- At Step 3 (Plan), expand Step 4 (Implement) into one task per slice.
- Mark a task `in_progress` when starting it; `completed` immediately when done. Never batch completions.
- When a sub-agent finishes, the main thread updates the corresponding task.
- Step 13 (post-merge cleanup) verifies all tasks are `completed` before merge.

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
| `autonomous` (default) | Any wave-level build, fix, refactor, or user-facing work | 0–14; Step 8 adversarial critic **mandatory**; per-step checkpoint commits; full stop-and-wake list |
| `epic-scope` | Beginning a new epic; no implementation yet; needs carving into waves | 0–3 only; produces `epic.spec.md` + `epic.plan.md`. Short-circuits before Step 4. |
| `incident-response` | Live or recent production incident needing detection confirmation, diagnosis, fix, deploy, monitoring gap closure, and postmortem RCA | Triage-compressed 1 → 2–8 → **Step 9 produces RCA** (not ADR) → 10 → 11 (waivable for hotfix with user approval) → 12–13 → **Step 14 includes monitoring verification + gap closure** |
| `design-refresh` | Visual/UX refresh on an existing feature; no behavior change | `shape` prepended to Step 1; Step 2 = visual acceptance criteria; Step 4 uses `impeccable` + `polish` family; Step 5 heavily weighted; Step 7 adds a design-quality axis |
| `spike` | Timeboxed research or prototype; **no code ships** | Prereqs → woven source-driven → brief writeup at `<docs-root>/spikes/`. No worktree, no ADR, no commits to integration branch. |

Mode declaration is reviewable. A feature disguised as a different mode to skip steps is drift with a label.

### `autonomous` mode in particular (the default)

This is the default because Bionic philosophy is "operate autonomously." The mode assumes no human is watching Steps 4–14 in real time, and tightens evidence discipline accordingly:

- **Step 8 adversarial critic is mandatory.**
- **Per-step checkpoint commits.**
- **Expanded stop-and-wake list.**

**Autonomous does NOT mean "skip Step 1 Q&A."** The autonomous span is **Steps 4–14**. The user-engagement sequence is:

| Step | Engagement |
|---|---|
| 1. Ideate | **Interactive Q&A with the user.** Extensive back-and-forth on scope, non-goals, alternatives. |
| 2. Spec | **Semi-interactive.** Translate Step 1 into a testable contract. Surface remaining ambiguities as Wake Notes; otherwise proceed. |
| 3. Plan | **Autonomous write → one approval checkpoint.** Claude writes the plan; user reviews and approves before Step 4 begins. |
| 4–14 | **Fully autonomous** within the stop-and-wake rules. |

Skipping Step 1 Q&A to "save time" is the single highest-risk move.

**Step → governing-skill mapping:**

| Step | Governing skill | On-demand sub-skills within the step |
|---|---|---|
| 0. Configure | `canonical-sdlc` + `agent-skills:context-engineering` | — |
| 1. Ideate | `agent-skills:idea-refine` | — |
| 2. Spec | `agent-skills:spec-driven-development` | — |
| 3. Plan | `superpowers:writing-plans` | — |
| 4. Implement | `agent-skills:incremental-implementation` | `superpowers:test-driven-development` (every slice); `superpowers:executing-plans` (if plan exists); `agent-skills:source-driven-development` (unfamiliar APIs); `superpowers:systematic-debugging` (surprises); `agent-skills:documentation-and-adrs` (inline ADR capture); `superpowers:using-git-worktrees` (only if `use_worktree: true`) |
| 5. Browser verify | `agent-skills:browser-testing-with-devtools` | `agent-skills:frontend-ui-engineering` (production UI hardening pre-verify) |
| 6. Verify done | `superpowers:verification-before-completion` | — |
| 7. Self-review | `agent-skills:code-review-and-quality` | `agent-skills:security-and-hardening` (if security axis flags); `agent-skills:performance-optimization` (if performance axis flags) |
| 8. Adversarial critic | subagent dispatch (**MANDATORY**) | — |
| 9. Document decisions | `agent-skills:documentation-and-adrs` | — |
| 10. Commit (**per-step checkpoint**) | `agent-skills:git-workflow-and-versioning` | — |
| 11. External review | `superpowers:requesting-code-review` | `superpowers:receiving-code-review` on receipt |
| 12. Finish branch | `superpowers:finishing-a-development-branch` | — |
| 13. Post-merge cleanup | `canonical-sdlc` | — |
| 14. Ship | `agent-skills:shipping-and-launch` | `agent-skills:ci-cd-and-automation` (new pipelines only) |

#### Autonomous Friction Protocol

When autonomous-mode work hits friction, **diagnose before escalating**. Friction is either:

- **Diagnostic friction** — direction is clear, code misbehaves (test fails, behavior diverges from spec, surprise output). → MAP first.
- **Decision friction** — the direction itself is in question (which approach, which abstraction, which scope). → Surface via User Decision Protocol.

For diagnostic friction in autonomous mode:

1. **Load `map-instrument-narrow` immediately.** Do not write speculative fix code first. Speculative-fix-before-instrumentation regresses pass rates more often than it improves them.
2. **No fix code** until NARROW phase yields a named root cause with data evidence.
3. **Three-fail rule applies AFTER one full MAP-INSTRUMENT-NARROW pass**, not before. If a complete pass does not yield a clean root cause, loop back to MAP (your architectural model was incomplete) — do not throw speculative fixes.
4. **After root cause is known**, the *bubble-up vs. proceed-directly* judgment is a separate decision per the User Decision Protocol. Diagnosis ≠ permission to fix in scope; trivial fixes proceed, scope-expanding fixes surface.

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
| 4–14 | **N/A** — `epic-scope` stops here. |

### `incident-response` mode in particular

`incident-response` is the mode for production incidents. The outcome is a **closed incident with documented prevention**.

| Step | Governing skill | Notes |
|---|---|---|
| 0. Configure | `canonical-sdlc` + `agent-skills:context-engineering` | — |
| 1. Triage (compressed Ideate) | `agent-skills:idea-refine` (compressed to triage) | — |
| 2. Spec (repro + closure criteria) | `agent-skills:spec-driven-development` (writes `incidents/NNNN-<slug>/spec.md`) | — |
| 3. Plan (debug + fix) | `superpowers:writing-plans` (writes `plan.md`; integration branch is typically `main` or `hotfix/<id>`) | — |
| 4. Diagnose + Implement | `superpowers:systematic-debugging` → `agent-skills:incremental-implementation` | failing test = incident repro |
| 5. Browser verify | `agent-skills:browser-testing-with-devtools` (N/A if non-UI) | — |
| 6. Verify done | `superpowers:verification-before-completion` | — |
| 7. Self-review | `agent-skills:code-review-and-quality` | — |
| 8. Adversarial critic | subagent dispatch (**MANDATORY**) | "does the fix mask a deeper issue?" |
| 9. **RCA (not ADR)** | `canonical-sdlc` (writes `rca.md`) | — |
| 10. Commit | `agent-skills:git-workflow-and-versioning` | — |
| 11. External review | `superpowers:requesting-code-review` | **WAIVABLE** for hotfixes with user approval; retrospective review within 24 hours |
| 12. Finish branch | `superpowers:finishing-a-development-branch` (merge to declared integration branch) | — |
| 13. Post-merge cleanup | `canonical-sdlc` | — |
| 14. Ship + Monitor + Close gap | `agent-skills:shipping-and-launch` (deploy → monitor through ≥1 cycle → close monitoring gap) | — |

**RCA required shape** (`incidents/NNNN-<slug>/rca.md`):
- **Summary** — one paragraph: what happened, impact, duration.
- **Timeline** — detection → mitigation → fix deployed, with timestamps.
- **Root cause** — the single underlying technical cause, stated plainly.
- **Contributing factors** — conditions that turned the root cause into an incident.
- **The fix** — what was changed, link to commit(s).
- **Prevention** — concrete measures. Each measure must link to a commit or ticket.
- **Monitoring gap analysis** — either "monitoring caught this at <timestamp>, no gap" with link, OR a description of the gap and a link to the commit that closed it.

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
| 5. Browser verify | `agent-skills:browser-testing-with-devtools` + **`audit`** | — |
| 6. Verify done | `superpowers:verification-before-completion` | — |
| 7. Self-review | `agent-skills:code-review-and-quality` (5 code axes only) | design quality evaluated in Step 4 critique loop |
| 8. Adversarial critic | subagent dispatch | "find visual regressions and a11y failures" |
| 9. Document decisions | `agent-skills:documentation-and-adrs` | — |
| 10. Commit | `agent-skills:git-workflow-and-versioning` | — |
| 11. External review | `superpowers:requesting-code-review` | — |
| 12. Finish branch | `superpowers:finishing-a-development-branch` | — |
| 13. Post-merge cleanup | `canonical-sdlc` | — |
| 14. Ship | `agent-skills:shipping-and-launch` | **`extract`** (if reusable patterns) |

**Step 4 loop structure:**

```
Step 4 (Implement) loop:
  (a) Build    → /impeccable craft
                 (skips shape; loads references from brief)
  (b) Polish   → polish + harden + normalize
  (c) Critique → critique (scored eval)
  (d) Iterate  → If critique flags issues, classify and loop.
```

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

This replaces the prior `narrative_verbose` tier. Verbose narrative was never the solution; framing was.

## Ephemeral Workspace (`.bionic/tmp/`)

All interim files the skill writes for itself live in `.bionic/tmp/` (gitignored):
- `continuation-checkpoint.md`, `handoff-*.md` (session-boundary snapshots)
- `evidence-*.png`, `devtools-trace-*.json`, perf snapshots, screenshots
- `wake-note-draft-*.md`, decision-scratch files

Step 0 pre-flight ensures `.bionic/tmp/` exists. Step 13 wipes the directory on merge
(when `cleanup_on_finish: true`, the default).

Plan and spec files (canonical artifacts) still live under `<docs-root>/{plans,specs,adrs,incidents}/`. Only ephemera goes in `.bionic/tmp/`.

## Always-On Prerequisites

These load at session start, not as numbered steps:

**Session-resume protocol — runs FIRST.** If a plan file with `governing-skill: canonical-sdlc` and `sdlc-step: < 14` exists, treat it as the active plan. Read in this order: frontmatter → `## Handoff` (if present) → `## SDLC State`. Use the handoff's `Resume point` as the literal next action. The handoff is authoritative.

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

Mandatory for new plans (`canonical_sdlc_version: 3`). Legacy plans (`canonical_sdlc_version: 1` or `2`) are grandfathered.

**Goal:** Set every plan-shaping flag in plan frontmatter deliberately, with explicit user confirmation.

**Action:** Four sub-steps:

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

3. **Present the confirmation display:**

   ```
   ═══ Plan Configuration — confirm before Step 1 ═══
   environment:
     bionic-root:  /Users/me/proj/.bionic               [verified]
     docs-root:    .bionic/docs                         [default]
     bionic-tmp:   /Users/me/proj/.bionic/tmp           [ready]
     hooks:        evidence-gate, governing-skill       [all installed]

   slug: <inferred-from-conversation>
   mode: autonomous

   Discriminator flags:
     surface_type:    api          [inferred: "REST endpoint" in convo]
     language:        typescript   [inferred: tsconfig.json]
     has_ui:          false        [no UI mentioned]
     multi_agent:     false        [single SDLC plan]
     deploy_target:   none         [no deploy signal]

   Opt-in flags:
     cleanup_on_finish: true       [Step 13 wipes .bionic/tmp/ on close]
     use_worktree:      false      [no isolated worktree — work on current branch]

   Reply "confirm" to accept, or specify overrides:
     e.g. "set use_worktree=true, then confirm"
   ```

4. **Block until explicit confirmation.** No timeout, no implicit acceptance.

5. **Create TaskCreate list.** After confirmation, create a TaskCreate list with tasks `0:`, `1:`, ..., `14:` shape, one per planned step. Mark step 0 `completed` immediately.

**Override DSL grammar.** The user's reply is parsed against:

```
reply        := overrides? "confirm"
overrides    := override ("," override)* ","?
override     := "set" flag "=" value
              | "change" flag "to" value
```

Accepted: `confirm`; `set use_worktree=true, confirm`; `set surface_type=graphql, set language=python, confirm`.

On accept, write final values into plan frontmatter literally — every flag as an explicit `<key>: <value>` line. The plan carries `canonical_sdlc_version: 3` plus all 5 discriminator flags and 2 opt-in flags.

**Two-layer enforcement.**

- **Layer 1 — Soft (this skill).** SKILL.md mandates Step 0. Do not proceed past Step 0 without explicit user confirmation.
- **Layer 2 — Hard (`canonical-sdlc-governing-skill.sh`).** Runs on `PreToolUse|Write,Edit` of any canonical-sdlc plan/spec/adr file. For `canonical_sdlc_version: 3` + `mode: autonomous`, requires all 5 discriminator flags + 2 opt-in flags. Missing any → exit 2.

**Mid-plan reconfiguration.** Edit plan frontmatter directly; the new value takes effect immediately on next hook read.

**Legacy plan handling.** Plans with `canonical_sdlc_version: 1` or `2` are grandfathered — Step 0 v3 enforcement skipped.

**Gate:** Plan frontmatter contains `canonical_sdlc_version: 3` plus all 5 discriminator and 2 opt-in flags. User reply ended with `confirm` or `confirmed`.

**Evidence:** A line in `## SDLC State`: `Step 0: configured at <ISO-timestamp> via <reply-summary>`.

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
  - `## SDLC State` — mode, **integration branch**, current step, one line per step. **When advancing, replace `Step N: (pending)` in-place.**
  - `## Assumptions` — seeded from Step 1 "Not Doing" plus spec ambiguities. Step 4 appends inline.
- **Expand TaskCreate list.** After the plan is written, expand Step 4 (Implement) into one TaskCreate task per slice (`4/1:`, `4/2:`, …).
- **Integration-branch declaration — ask once, stick to it.** Declared in `## SDLC State` via an `integration-branch: <name>` line.
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
- **Step 8 critic checks** for mid-wave scope drift not justified by an `## Assumptions` row.

### Step 4 — Implement (`agent-skills:incremental-implementation`)
- **Worktree (only if `use_worktree: true`).** At the start of Step 4, before the first slice, create a git worktree at `.worktrees/<slug>` off the current branch. Record `worktree:`, `base-sha:`, `branch:` in the Step 4 evidence line. When `use_worktree: false` (default), work proceeds on the current branch.
- **Goal:** Build in thin vertical slices with per-slice proof.
- **Non-negotiable rhythm:** `superpowers:test-driven-development` — RED → GREEN → commit, per slice.
- **Wrapper:** `superpowers:executing-plans` if a plan file exists.
- **Woven:** source-driven on unfamiliar APIs; systematic-debugging on surprises; inline ADR capture on decisions.
- **Parallelization:** if slices are independent (no shared state), dispatch parallel implementer agents.
- **Task tracking:** mark `4/N: <description>` `in_progress` at slice start; `completed` immediately on slice merge.
- **Mode substitutions:**
  - `design-refresh`: governing skill is **`impeccable`**, invoked as `/impeccable craft`. Step 4 runs as a loop: craft → polish/harden/normalize → critique → iterate.
  - `incident-response`: the failing test must be the **incident repro**.
- **Assumption-log update:** whenever a decision resolves ambiguity, append a one-line entry to `## Assumptions` **before the commit**.
- **Gate:** Every slice has a passing test that was RED before implementation; new assumptions logged.
- **Evidence:** Commit history shows RED→GREEN transitions; `## Assumptions` reflects novel decisions. When `use_worktree: true`: also `worktree:`, `base-sha:`, `branch:` fields.

### Step 5 — Browser verify (`agent-skills:browser-testing-with-devtools`)
- **Goal:** Real-browser evidence for UI/frontend work.
- **Action:** Run flows in a real browser via DevTools MCP.
- **Parallelization:** Step 5 + Step 6 can run in parallel.
- **Gate:** Golden path + at least one edge case verified (or `n/a: <reason>` for non-UI work).
- **Evidence:** DevTools transcript or screenshot (written to `.bionic/tmp/devtools-trace-*.json` if interim).
- **Mode weight:**
  - `design-refresh`: heavily weighted. Browser evidence per state + **`audit`** scored technical-quality report.
- **UI/UX substitution:** use `impeccable` in Step 4 and `agent-skills:frontend-ui-engineering` pre-verify.

### Step 6 — Verify done (`superpowers:verification-before-completion`)
- **Goal:** Evidence before assertions.
- **Action:** Run all applicable test suites; paste output.
- **Gate:** All tests pass; output is pasted or linked.
- **Evidence:** Command output in conversation or commit trailer.

### Step 7 — Self-review (`agent-skills:code-review-and-quality`)
- **Goal:** 5-axis review — correctness, readability, architecture, security, performance.
- **Parallelization:** all 5 axes run in parallel (current behavior).
- **Gate:** Every axis has an explicit verdict.
- **Evidence:** Review notes.
- **Escalations:** Security axis flags → `agent-skills:security-and-hardening`. Performance axis flags → `agent-skills:performance-optimization`.
- **Mode substitution:** `design-refresh` — review the **5 code axes only**. Design quality was already evaluated in Step 4's critique loop.

### Step 8 — Adversarial critic
- **Mandatory in:** `autonomous`, `incident-response`, `design-refresh`.
- **Optional in:** `spike`. N/A in `epic-scope`.
- **Goal:** Catch what self-review missed. Fresh context, red-team framing.
- **Action:** Dispatch a fresh-context subagent with the plan, the diff, and the Step 7 self-review notes. Prompt template:

  > _Your job is to find what went wrong in this change. You have the spec, the plan, the diff, and the Step 7 self-review notes. Read them and try to falsify the claim that this is ready to merge. Look specifically for: silent wrong assumptions not logged in the `## Assumptions` section, scope creep beyond the spec, missing edge cases, fabricated evidence, and cross-cutting concerns a single-axis review would miss. Output either: at least one specific, reproducible issue, or an explicit "no issues found" followed by the three strongest falsification attempts you made and why each failed. Confirmation-seeking agreement is not acceptable output._

  - **Incident-response framing:** verify fix does not mask a deeper issue; monitoring gap analysis is honest.
  - **Design-refresh framing:** find visual regressions and a11y failures.
- **Parallelization:** dispatch 2+ critics with different framings in parallel.
- **Gate:** Critic output attached. Sycophantic output is **not** evidence.
- **Evidence:** Critic report with either specific issues raised or specific falsification attempts.

### Step 9 — Document decisions (`agent-skills:documentation-and-adrs`) — checkpoint
- **Goal:** Forcing function. Catch decisions that weren't captured inline during Steps 3 and 4.
- **Action (`autonomous`, `epic-scope`, `design-refresh`):** Review plan and implementation commits; verify every significant decision has an ADR.
- **Action (`incident-response`):** **write the RCA** (postmortem, not ADR — see RCA shape above).
- **Parallelization:** ADR draft + RCA draft (if applicable) in parallel.
- **Gate:** Every flagged decision has a written record before commit.
- **Evidence:** ADR file(s) at canonical path, or `rca.md` for incident-response.

### Step 10 — Commit (`agent-skills:git-workflow-and-versioning`)
- **Goal:** Atomic commits with clean history.
- **Action:** Stage scoped files; write commit body with "THINGS I DIDN'T TOUCH" summary. Update `## SDLC State` before staging.
- **Rhythm:** **Per-step checkpoint commits.** One commit per completed step.
- **Gate:** Commit is atomic; scope matches the Step 2 spec.
- **Evidence:** Commit SHA + commit body.

### Step 11 — Request external review (`superpowers:requesting-code-review`)
- **Goal:** Surface issues self-review can't catch.
- **Action:** Open PR or review request; on receipt, `superpowers:receiving-code-review` governs response.
- **Gate:** Review request is open.
- **Evidence:** PR link.
- **Mode substitution:** `incident-response` — waivable for hotfixes with user approval; retrospective review within 24 hours. Record waiver in `rca.md`.

### Step 12 — Finish branch (`superpowers:finishing-a-development-branch`)
- **Goal:** Close the branch cleanly. Every wave's commits must exist on the declared integration branch.
- **Action:** Merge the wave branch into the integration branch (local merge; pushing is the user's gate). Remove the worktree if one was created.
- **Default is merge.** Parking only permitted via an explicit `## Wake Note`.
- **Gate:** `git merge-base --is-ancestor <wave-tip> <integration-branch>` exits 0; worktree (if any) removed.
- **Evidence:** Merge SHA in `## SDLC State`; `git log --oneline <integration-branch>` showing the merge.

### Step 13 — Post-merge cleanup

Runs **after Step 12's merge commit, before Step 14**. Fires when frontmatter declares `cleanup_on_finish: true` (the default).

**Goal:** Wipe the ephemeral workspace, assert task-list integrity, strip leftover handoff files.

**When `cleanup_on_finish: false`:** Step 13 is skipped. Record `Step 13: n/a: cleanup_on_finish=false` and proceed to Step 14.

**When `cleanup_on_finish: true`** — execute:

1. **Idempotency check.** Read frontmatter `cleaned:` field. If already set, record `Step 13: n/a: already cleaned <date>` and stop.
2. **Wipe `.bionic/tmp/`.** `rm -rf <project>/.bionic/tmp/*`. The directory itself stays.
3. **Assert TaskCreate list integrity.** Verify zero non-completed tasks. Fail loud if any task remains `in_progress` or `pending`: do not advance to Step 14 until either the task is completed or explicitly cancelled by the user.
4. **Strip leftover continuation/handoff files.** Any `continuation-checkpoint.md` or `handoff-*.md` left in `<docs-root>/plans/<epic>/` (legacy locations) is removed — checkpoints live in `.bionic/tmp/` going forward.
5. **Update frontmatter.** Set `cleaned: <today-ISO-date>`.
6. **Append Step 13 evidence:**

   ```
   Step 13:
     cleanup: ok
     tmp-wiped: yes
     tasks-completed: <count>/<count>
   ```

7. **Commit the cleanup** with message `chore(plan): post-merge cleanup of <plan-slug>`.

**Gate:** Frontmatter has `cleaned: <today>`. `.bionic/tmp/` is empty. All TaskCreate tasks `completed`.

**Evidence:** The Step 13 row itself; cleanup commit SHA.

### Step 14 — Ship (`agent-skills:shipping-and-launch`)
- **Goal:** Production gate with pre-launch checklist, monitoring, rollback.
- **Action:** Run checklist; configure CI/CD if new pipelines needed. **Before declaring the wave complete**, emit `<docs-root>/plans/epic-NN-<slug>/continuation.md` summarizing wave, next wave, and open carry-overs.
- **Mode substitution (`design-refresh`):** invoke **`extract`** if reusable patterns introduced.
- **Mode substitution (`incident-response`):** Step 14 expands to:
  1. Deploy with rollback plan.
  2. Monitor the indicator metric/alert through ≥1 cycle.
  3. Close the monitoring gap (or declare "no gap" with evidence).
  4. Emit `continuation.md` at incident dir only if follow-on work surfaces.
- **Gate:** Checklist complete; rollback plan documented; `continuation.md` written. For `incident-response`: fix monitored stuck; gap closed or absent.
- **Evidence:** Deployment record + rollback doc + monitoring dashboard link + `continuation.md` path.

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
canonical_sdlc_version: 3
---
```

For incident-response artifacts, use `incident: NNNN-<slug>` instead of `epic`/`wave`.

Field definitions:
- `governing-skill` — the skill declared after the step's heading (Step 1 → `agent-skills:idea-refine`; Step 3 → `superpowers:writing-plans`; Step 9 ADR → `agent-skills:documentation-and-adrs`; Step 9 RCA → `canonical-sdlc`; `continuation*.md` → `canonical-sdlc`). Mode overrides: `design-refresh` Step 1 → `shape` and Step 4 → `impeccable`.
- `sdlc-step` — the step that produced this artifact. `0` for epic-scope artifacts. `14` for `continuation.md`.
- `epic` — `epic-NN-<slug>` matching the directory.
- `incident` — `NNNN-<slug>` for incident-response.
- `wave` — wave identifier; omit for epic-level and continuation.
- `mode` — canonical-sdlc mode at declaration time.

### Transition discipline

When advancing from one step to the next, announce explicitly:

> _**Advancing to Step N — &lt;title&gt;** (governing skill: `<skill-id>`). Loading now._

Then invoke `Skill` to load the governing skill.

## Evidence (two tiers)

Evidence falls into two tiers. Each tier has different rules for when it's written, who consumes it, and whether the hook enforces shape.

| Tier | Always present? | Controlled by | Enforced by |
|---|---|---|---|
| **Verification** | Yes — mandatory | (no flag) | `canonical-sdlc-evidence-gate.sh` (presence + shape on v3 plans) |
| **Handoff** | Only when plan spans sessions | (no flag — session-end trigger) | Skill prose + Stop-hook checkpoint |

For decision-point prose to the user, see the **User Decision Protocol** section above — that replaces the prior narrative tier.

### Verification tier — mandatory, shape-checked

Every step has an evidence artifact recorded under `Step N:` in `## SDLC State`. The evidence-gate hook enforces presence on every `git commit`.

For plans with `canonical_sdlc_version: 3`, the hook also enforces the per-step **shape table**:

| Step | Required fields under `Step N:` | Notes |
|------|---------------------------------|-------|
| 0 | `prereqs: ok` (or the configured line) | Smoke-test |
| 1 | Pointer to `## Phase 1` body (6-lenses + Q&A + Not Doing) | Pointer-only |
| 2 | Pointer to spec body containing `R1..RN` acceptance criteria | At least 3 R-rows |
| 3 | Pointer to plan body containing ordered step list + critical-files list | — |
| 4 | Pointer to slice list (`abc1234 RED test`, `def5678 GREEN passing`); also `worktree:`, `base-sha:`, `branch:` when `use_worktree: true` | At least 1 slice |
| 5 | `devtools-trace: <path>` OR `n/a: <reason>` | — |
| 6 | `cmd:`, `pass:`, `total:`, `output:` | `pass == total` required |
| 7 | Pointer to 5-axis review body | All 5 axes; PASS / FLAG / FAIL each |
| 8 | Pointer to critic findings table (or `Findings: none`) | — |
| 9 | `adr: <path>` OR `rca: <path>` OR `n/a: <reason>` | — |
| 10 | `commit:`, `subject:`, `files:` | — |
| 11 | `pr: <url>` OR `n/a: <reason>` | — |
| 12 | `merge:`, `worktree-removed:` | `worktree-removed: n/a` valid when no worktree was used |
| 13 | `cleanup:`, `tmp-wiped:`, `tasks-completed:` OR `n/a: cleanup_on_finish=false` | — |
| 14 | `deploy:`, `verified-at:`, `monitor:` OR `n/a: <reason>` | `n/a` only valid when `deploy_target: none` |

Pointer steps (1, 2, 3, 4, 7, 8) are presence-only at the hook level.

**Block format.** Multi-field steps use YAML-style indented keys under `Step N:`:

```
Step 6:
  cmd: bash test.sh
  pass: 332
  total: 332
  output: <docs-root>/plans/<slug>.plan.md#step-6
```

**Backwards compatibility.** Plans with `canonical_sdlc_version: 1` or `2` use their original shape table. v3 enforcement gates only on the v3 marker.

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

Three trigger conditions:

1. **Session end mid-plan.** `Stop` event with `sdlc-step: < 14`.
2. **Context-compaction risk.** When utilization approaches the threshold (~90%).
3. **Explicit user trigger** (e.g., a `/checkpoint` command).

The skill **rewrites the section in place** each trigger. Never appends. Handoff is bounded.

#### Persistence model

**Session-scoped** (reset each session): `Decisions ratified this session`.

**Cross-session** (persist; capped per-field): `Resume point`, `Tried and rejected`, `Discovered surprises`, `Open blockers`, `Uncommitted work`, `Resume protocol`.

#### When handoff is NOT written

Single-session plans never get a handoff section. Step 13 strips the handoff if the plan opened and closed within one session.

## Continuation Artifacts

Long-running epics span sessions. Continuation artifacts make session handoff automatic.

**End-of-wave (`continuation.md`).** Step 14 emits `<docs-root>/plans/epic-NN-<slug>/continuation.md` summarizing:
- Wave just completed (id, scope, outcome).
- Integration branch + merge SHA. Next wave branches from this same integration branch at or after this SHA.
- Next wave (id, scope, entry step = 1).
- Open decisions or carry-overs from `## Assumptions`.

Frontmatter: `governing-skill: canonical-sdlc`, `sdlc-step: 14`, no `wave` field.

**Mid-wave checkpoint (`.bionic/tmp/continuation-checkpoint.md`).** The Stop hook detects an active canonical-sdlc run and autosaves a checkpoint to `.bionic/tmp/` capturing:
- Current SDLC State snapshot.
- In-flight work.
- Next recommended action on resume.

Zero user interaction. The next session reads it if present and resumes from the recorded state. Step 13's `.bionic/tmp/` wipe clears this on merge.

## Evidence Gate Hook

Bionic installs `canonical-sdlc-evidence-gate.sh` as a `PreToolUse|Bash` hook. On `git commit`, the hook locates the most recent plan, reads `## SDLC State`, and **blocks the commit (exit 2) if the current step's evidence artifact is missing or unreadable**.

For `canonical_sdlc_version: 3` plans, the hook validates the per-step shape table above. For v1/v2 plans, it uses the original shape table.

## Governing-Skill Hook

Bionic installs `canonical-sdlc-governing-skill.sh` as a `PreToolUse|Write,Edit` hook. It blocks writes to any canonical-sdlc artifact lacking `governing-skill:` frontmatter, and on `canonical_sdlc_version: 3` autonomous plans validates the 5 discriminator + 2 opt-in flag set.

## Subagent Dispatch Convention

Every subagent invoked during a canonical-sdlc step must receive a prompt prefix containing:

1. **Current step** — number, name, sub-skill invoked.
2. **Mode** — the declared canonical-sdlc mode.
3. **Scope constraint** — what this agent may touch; what it must not.
4. **Artifact expected** — the evidence shape required for the step gate.
5. **Exit condition** — when to stop and report. Includes: "do not pivot approach; surface blockers to the main thread."
6. **Step-specific duties.** For Step 4 (implement) dispatches: *"Append a one-line entry to the plan file's `## Assumptions` section before your final commit whenever a decision resolves ambiguity. No silent choices."*

This prevents subagent wander.

## Escalation Protocol

**Three-fail rule.** If the same step fails to produce valid evidence three times in a row:

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
| "This decision is minor, it doesn't need an ADR" | "Minor" is judged from inside the context. Step 9 is the forcing function. |
| "Self-review passed, external review is redundant" | Different classes of issues. |
| "The code works, that's enough evidence" | "Works on my machine" isn't evidence. |
| "The user is in a hurry, I should skip steps" | Declare a fast-path explicitly or walk the full path. |
| "This is just a bugfix; `autonomous` is overkill" | A bugfix is still a code change. |
| "This is just a refactor; no spec needed" | "All existing tests still pass" is the spec. |
| "I can skip browser verify, the unit tests cover it" | Unit tests don't catch visual regressions, focus traps, or contrast failures. |
| "I'm confident in my self-review; the adversarial critic is overkill" | Self-review is bounded by what you thought to check. |
| "The assumption was obvious; no need to log it" | "Obvious" is judged from inside the moment. Log it. |
| "I can update `## SDLC State` after the commit" | Then the evidence gate hook will block the commit. |
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
- Reaching Step 14 with no artifact from Step 3.
- Committing without `## SDLC State` updated for the current step.
- `autonomous` mode without `## Assumptions` seeded at plan time.
- Adversarial critic output that is pure agreement.
- Dispatching a subagent without the current-step + mode + scope-constraint prefix.
- Improvising past a stop-and-wake trigger.
- Step 12 closing without the wave's commits reachable from the integration branch.
- Declaring a plan without an `integration-branch:` line.
- Asking the user a wall-of-text question instead of following the **User Decision Protocol**.
- Skipping the TaskCreate list or batching task completions at the end.
- Single-threading a step where 2+ subtasks are clearly independent.

## Quick Reference

| Step | Gate | Evidence |
|---|---|---|
| 0. Configure | Frontmatter has `canonical_sdlc_version: 3` + 5 discriminator + 2 opt-in flags; user confirmed; TaskCreate list created | Confirmation row in `## SDLC State` |
| 1. Ideate | Refined idea + "Not Doing" list | Artifacts in spec; `shape` output if `design-refresh`; triage notes if `incident-response` |
| 2. Spec | Every req has acceptance criterion | Spec doc |
| 3. Plan | No placeholders; `integration-branch:` declared; Step 4 expanded into slice tasks | Plan file |
| 4. Implement | Every slice has a passing test that was RED first; worktree created if `use_worktree: true` | Commit history with RED→GREEN; worktree fields when applicable |
| 5. Browser verify | Golden path + edge case (or N/A) | DevTools transcript |
| 6. Verify done | All tests pass | Command output |
| 7. Self-review | Every axis has verdict | Review notes |
| 8. Adversarial critic | Specific issues raised or specific falsification attempts | Critic report (mandatory in `autonomous`, `incident-response`, `design-refresh`) |
| 9. Document decisions | Every significant decision has a record | ADR file(s); or `rca.md` for `incident-response` |
| 10. Commit | Atomic, scope matches spec, per-step checkpoint | Commit SHA + body |
| 11. External review | Review request open | PR link (waivable for incident hotfix) |
| 12. Finish branch | Wave merged into declared `integration-branch`; worktree (if any) removed | Merge SHA |
| 13. Post-merge cleanup | `.bionic/tmp/` wiped; all TaskCreate tasks completed; `cleaned:` stamped | Cleanup row + commit SHA |
| 14. Ship | Checklist complete, rollback documented; fix monitored stuck + gap closed (`incident-response`) | Deployment record; monitoring evidence |
