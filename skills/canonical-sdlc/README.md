# Canonical SDLC

Bionic's flagship engineering pattern: an 11-step software development lifecycle that runs autonomously for hours and produces an auditable record at the end.

This is the human-facing reference. The skill prose Claude reads at runtime is in [`SKILL.md`](SKILL.md) — same directory.

> **TL;DR.** A skill enforces 11 flat steps (0–10) organized around **two gates** — Verify (Step 5, "does it work?") and Review (Step 6, "is it well-made?") — plus a cross-cutting **commit rhythm** that fires per step rather than at a numbered position. Plan frontmatter is the single source of truth: `governing-skill`, `mode`, `sdlc-step`, `canonical_sdlc_version`, five discriminator flags, two opt-in flags, and a `model_plan` line. State lives in a `## SDLC State` section, one evidence line per step. Two hooks back the skill: `governing-skill` validates plan/spec/ADR frontmatter on write, and `evidence-gate` blocks commits whose current-step evidence line is missing or placeholder. Five modes: `autonomous` (default), `epic-scope`, `incident-response`, `design-refresh`, `spike`. Dispatch and model tiering are governed by prose, not a hook.

---

## Contents

- [Why this exists](#why-this-exists)
- [The 11-step lifecycle](#the-11-step-lifecycle)
- [Modes](#modes)
- [Plan frontmatter contract](#plan-frontmatter-contract)
- [SDLC State and the evidence model](#sdlc-state-and-the-evidence-model)
- [Handoff tier](#handoff-tier)
- [The two hooks](#the-two-hooks)
- [Model and token strategy](#model-and-token-strategy)
- [Versioning and backward-compat](#versioning-and-backward-compat)
- [Configuration: the Step-0 wizard](#configuration-the-step-0-wizard)
- [Quick reference](#quick-reference)
- [Pointers](#pointers)

---

## Why this exists

Most "AI does the SDLC" demos collapse the lifecycle: a brainstorm becomes code in one shot, with the spec implied, the plan unwritten, the review skipped, the audit trail missing. That works on toy problems and fails on anything wave-sized — multi-day work that touches multiple files, ships to users, and accumulates decisions a future maintainer needs.

Canonical SDLC is the constraint that forces the lifecycle to stay intact. Each of the 11 steps contributes a dimension of fidelity — scope, contract, plan, isolation, proof, review, decision record, release discipline — that no other step supplies. Without enforcement, individual steps feel skippable in isolation, but the compounding loss of fidelity is invisible mid-effort and surfaces later as rework.

The skill plus two hooks make the lifecycle non-skippable. The plan file is the single source of truth: configuration lives in YAML frontmatter, evidence lives in the `## SDLC State` section, and decisions live in ADRs (or RCAs for incidents). Every commit must show evidence for the current step. Every plan/spec/ADR must declare the skill that produced it.

The autonomous span is **Steps 4–10** — Claude walks away to build for hours and returns with merged code. Steps 1–3 (Ideate, Spec, Plan) are interactive: that's where wrong assumptions get caught cheaply. Step 3 ends with an explicit user approval before autonomous execution begins.

### The Iron Law

```
NO STEP SKIPPED WITHOUT A DECLARED FAST-PATH.
NO COMPLETION WITHOUT EVIDENCE FROM EVERY APPLICABLE STEP.
```

Violating the letter of this process is violating the spirit of this process.

---

## The 11-step lifecycle

Eleven flat steps, numbered 0–10. No interstitials, no sub-steps, no hidden stations — the number you see is the number that runs. The lifecycle is organized around **two gates** — **Verify** (Step 5, "does it work?") and **Review** (Step 6, "is it well-made?") — each decomposed by modality or stance rather than by extra numbered steps.

| Step | Name | Governing skill | Tier | Purpose |
|---|---|---|---|---|
| 0 | Configure | `canonical-sdlc` + `agent-skills:context-engineering` | O | Set every plan-shaping flag with explicit user confirmation |
| 1 | Ideate | `agent-skills:idea-refine` | O | Pin scope + non-goals (6-lens refinement + "Not Doing" list) |
| 2 | Spec | `agent-skills:spec-driven-development` | O | Testable contract with acceptance criteria |
| 3 | Plan | `superpowers:writing-plans` | O | Execution contract (`## SDLC State` + `## Assumptions`); approval checkpoint before Step 4 |
| 4 | Implement | `agent-skills:incremental-implementation` | E + X | Thin vertical slices, RED→GREEN per slice |
| 5 | Verify (gate) | `superpowers:verification-before-completion`; browser modality `browser-verify` (drives `playwright-cli`; chrome-devtools MCP reserved for deep inspection) | X→O | "Does it work?" — tests/build always; real-browser behavior when UI/user-visible |
| 6 | Review (gate) | `agent-skills:code-review-and-quality` | E | "Is it well-made?" — 5-axis self-review (always) + adversarial critic (mandatory autonomous/incident/design-refresh) |
| 7 | Document decisions | `agent-skills:documentation-and-adrs` | O / E | ADR (or RCA for incidents) |
| 8 | External review | `superpowers:requesting-code-review` | O | PR / review request; receipt governed by `superpowers:receiving-code-review` |
| 9 | Integrate & close | `superpowers:finishing-a-development-branch` + `canonical-sdlc` | O / X | Merge into integration branch + remove worktree (finish half), then wipe `.bionic/tmp/`, assert task-list integrity, strip handoff (cleanup half) |
| 10 | Ship | `agent-skills:shipping-and-launch` | E / O | Production gate; emit `continuation.md` |
| — | Commit rhythm (cross-cutting) | `agent-skills:git-workflow-and-versioning` | O | Not a numbered step — a per-step checkpoint-commit rhythm that fires throughout |

**Tier key.** Each step has a default dispatch target (the strategy below governs; the tier is a hint):

- **O — orchestrator.** The main thread. Runs Steps 1–3 directly and coordinates the rest.
- **E — execution.** A fresh subagent routed by the slice's `complexity:` tag — `complex` → `model: opus`, `standard` → `model: sonnet`; fork only when the unit genuinely needs the inherited conversation.
- **X — explore / mechanical / test.** A fresh `model: sonnet` subagent — search, fixtures, mechanical edits, test-writing.

### The approval checkpoint

The end of Step 3 is the "walk away" boundary. After the plan is complete, Claude presents a summary (framing, options to approve / request revisions / halt, why-it-matters) and **only begins Step 4 on explicit approval**.

Wave scope locks at approval. Mid-wave discoveries — architectural gaps, related bugs, audit findings — get logged to `## Assumptions` as candidates for the next wave; they do not reshape the current wave. Two exceptions: a discovery that makes the current wave structurally impossible is surfaced as a Wake Note and halts; a trivial one-line correction in a touched file ships inline. Step 6 (Review)'s adversarial-critic stance checks for unjustified mid-wave scope drift.

### Autonomous does not mean "skip Step 1 Q&A"

The autonomous span is Steps 4–10. The user-engagement sequence is:

| Step | Engagement |
|---|---|
| 1. Ideate | **Interactive Q&A.** Extensive back-and-forth on scope, non-goals, alternatives. Mandatory in every mode. |
| 2. Spec | **Semi-interactive.** Translate Step 1 into a testable contract; surface remaining ambiguities as Wake Notes, else proceed. |
| 3. Plan | **Autonomous write → one approval checkpoint.** Claude writes the plan; the user approves before Step 4. |
| 4–10 | **Fully autonomous**, within the stop-and-wake rules. |

Skipping Step 1 Q&A to "save time" is the single highest-risk move.

---

## Modes

Declare the mode at entry. **`autonomous` is the default** — any other mode is an explicit declaration. The mode determines which steps apply, the governing-skill substitutions, and the default flag values.

| Mode | When | Step shape |
|---|---|---|
| **`autonomous`** (default) | Any wave-level build, fix, refactor, or user-facing work | Steps 0–10; Step 6 (Review)'s adversarial-critic stance **mandatory**; per-step checkpoint commits (commit rhythm); full stop-and-wake list |
| **`epic-scope`** | Beginning a new epic; no implementation yet; needs carving into waves | Steps 0–3 **only** → produces `epic.spec.md` + `epic.plan.md`. Short-circuits before Step 4. |
| **`incident-response`** | Live or recent production incident | Steps 0–10, compressed: Step 1 = triage; Step 7 produces an **RCA** (not an ADR); Step 8 is **waivable** for hotfixes (retrospective review within 24h); Step 10 expands to deploy + monitor ≥1 cycle + close the monitoring gap |
| **`design-refresh`** | Visual/UX refresh on an existing feature; no behavior change | Step 1 → `shape`; Step 4 → an `impeccable` craft→polish→critique loop with a measurable exit gate; Step 5 (Verify) heavily weighted + `audit`; Step 6 (Review) reviews the 5 code axes only (design quality was scored in the Step 4 loop); Step 10 → `extract` for reusable patterns |
| **`spike`** | Timeboxed research or prototype; **no code ships** | Step 0 + woven research + a writeup at `<docs-root>/spikes/`. No worktree, no ADR, no commits to the integration branch. If a spike reveals shippable work, declare a new mode and re-enter at Step 1. |

Mode declaration is reviewable. A wave-sized feature disguised as a `spike` to skip the lifecycle is drift with a label; the declaration must match the actual work.

---

## Plan frontmatter contract

Plans declare every plan-shaping flag in YAML frontmatter. Step 0 (the wizard) writes this; the `governing-skill` hook enforces its presence on writes; the `evidence-gate` hook reads it on every commit.

### Identity block (example, v5 autonomous)

```yaml
---
governing-skill: superpowers:writing-plans
sdlc-step: 3
epic: epic-02-v2-product-pass
wave: wave-01-checkout-refactor
mode: autonomous
canonical_sdlc_version: 5
---
```

For incident-response artifacts, use `incident: NNNN-<slug>` instead of `epic`/`wave`.

| Field | Values | Purpose |
|---|---|---|
| `governing-skill` | A skill ID (`superpowers:writing-plans`, `agent-skills:idea-refine`, `canonical-sdlc`, …) | Names the skill that produced this artifact. Different artifacts carry different governing skills (Step 1 → `idea-refine`; Step 3 → `writing-plans`; Step 7 RCA → `canonical-sdlc`). |
| `sdlc-step` | `0..10` | The step that produced this artifact. The evidence-gate hook reads `current:` in `## SDLC State`, not this field, to pick the step to validate. |
| `mode` | `autonomous` \| `epic-scope` \| `incident-response` \| `design-refresh` \| `spike` | Determines applicable steps, governing-skill substitutions, and default flag values. |
| `canonical_sdlc_version` | `1`/`2` (legacy) \| `3` \| `4` \| `5` (current) | Routes the hooks. See [Versioning](#versioning-and-backward-compat). |
| `epic` / `wave` / `incident` | Identifier matching the enclosing directory | `epic-NN-<slug>` / `wave-NN-<slug>` for epic-tree work; `NNNN-<slug>` for incidents. |

### Discriminator flags (5 — required on v3/v4/v5 autonomous plans)

| Flag | Values | Default |
|---|---|---|
| `surface_type` | `api` \| `graphql` \| `ui` \| `iac` \| `ml` \| `realtime` \| `mobile` \| `system` \| `none` | inferred |
| `language` | `typescript` \| `javascript` \| `rust` \| `go` \| `python` \| … \| `none` | inferred |
| `has_ui` | bool | inferred |
| `multi_agent` | bool | **`true`** |
| `deploy_target` | `k8s` \| `vercel` \| `custom` \| `migration` \| `none` | inferred |

### Opt-in flags (2 — required on v3/v4/v5 autonomous plans)

| Flag | Default | What it does |
|---|---|---|
| `cleanup_on_finish` | `true` | When `true`, the cleanup half of Step 9 (Integrate & close) runs after the merge half: wipes `.bionic/tmp/`, asserts task-list integrity, strips leftover handoff files. |
| `use_worktree` | `false` | When `true`, Step 4 creates a git worktree at `.worktrees/<slug>` and records `worktree:`/`base-sha:`/`branch:` in its evidence line. |

### `model_plan` (required on v4 and v5 autonomous plans)

A single-line record of the confirmed model tiers, derived from `multi_agent` and the detected session model at Step 0 and surfaced for explicit confirmation:

```yaml
model_plan: orchestrator=fable-5-high; exec-complex=opus-fresh; exec-standard=sonnet-fresh; explore=sonnet-fresh
```

For `canonical_sdlc_version: 4` and `5` autonomous plans the governing-skill hook **requires** `model_plan` — a missing value blocks the write (exit 2). v3 plans keep the prior contract (no `model_plan`). `model_plan` changes no per-step evidence shape; it records intent only.

---

## SDLC State and the evidence model

Configuration lives in frontmatter; **live state lives in a `## SDLC State` section** in the plan body:

```markdown
## SDLC State
mode: autonomous
integration-branch: main
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
Step 8: (pending)     # External review
Step 9: (pending)     # Integrate & close
Step 10: (pending)    # Ship
```

`current: N` names the active step. When advancing, **replace `Step N: (pending)` in-place** — never append. (`Phase N:` is accepted as a legacy alias for `Step N:`.) The `## Assumptions` section sits alongside it, seeded from Step 1's "Not Doing" list plus spec ambiguities, and appended inline during Step 4.

### Two evidence tiers

Evidence falls into exactly two tiers:

| Tier | Always present? | Enforced by |
|---|---|---|
| **Verification** | Yes — mandatory | `canonical-sdlc-evidence-gate.sh` (presence + per-step shape on v3/v4/v5) |
| **Handoff** | Only when a plan spans sessions | Skill prose + the Stop-hook checkpoint |

There is no third "narrative" tier. Decision-point prose to the user is governed instead by the **User Decision Protocol**: frame the decision at the highest useful level of abstraction, offer numbered options each with a one-line rationale, state significance in one sentence, and keep the whole thing under ~200 words. If stating the question needs a filename or line number, the abstraction level is wrong — climb a rung and rewrite.

### Per-step evidence shape (v5)

The evidence-gate hook checks the current step's line against this table on every `git commit`:

| Step | Required under `Step N:` | Notes |
|---|---|---|
| 0 | `prereqs: ok` (or the configured line) | presence |
| 1 | pointer to the ideate body | pointer-only |
| 2 | pointer to the spec body | pointer-only |
| 3 | pointer to the plan body | pointer-only |
| 4 | pointer to the slice list; **or** `worktree:`/`base-sha:`/`branch:` when `use_worktree: true` | pointer-only at the hook |
| 5 Verify | `cmd:`, `pass:`, `total:`, `output:` (`pass == total`) **AND** `devtools-trace: <path>` **OR** `n/a: <reason>` | tests/build modality always; browser modality is a trace or `n/a` |
| 6 Review | pointer to the 5-axis review body + critic findings | pointer-only |
| 7 Document | `adr: <path>` **OR** `rca: <path>` **OR** `n/a: <reason>` | |
| 8 External review | `pr: <url>` **OR** `n/a: <reason>` | |
| 9 Integrate & close | `merge:`, `worktree-removed:` **AND** (`cleanup:`, `tmp-wiped:`, `tasks-completed:` **OR** `cleanup: n/a`) | finish half + cleanup half in one atomic step |
| 10 Ship | `deploy:`, `verified-at:`, `monitor:` **OR** `n/a: <reason>` | `n/a` valid only when `deploy_target: none` |

Steps 1, 2, 3, 4, and 6 are pointer-only at the hook level — the hook checks that a non-placeholder pointer exists, not its contents. Multi-field steps use YAML-style indented keys under `Step N:`:

```
Step 5:
  cmd: bash test.sh
  pass: 332
  total: 332
  output: <docs-root>/plans/<slug>.plan.md#step-5
  devtools-trace: .bionic/tmp/devtools-trace-golden.json
```

The gate blocks (exit 2) when the current step's evidence line is missing, empty, or a placeholder token (`todo`, `pending`, `inprogress`, `xxx`, `tbd`, `placeholder`).

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

**Strip:** a plan that opens and closes within one session never gets a handoff; Step 9's cleanup half strips a leftover handoff on merge.

---

## The two hooks

Two independent hooks gate two different tool events. Each reads the active plan independently — there is no shared state, no dispatch routing, no rules JSON.

### `canonical-sdlc-governing-skill.sh` — `PreToolUse | Write, Edit`

Fires on writes to `*.plan.md`, `*.spec.md`, `adr-*.md`, and `continuation*.md` under the docs root. Requires non-empty `governing-skill:` frontmatter on every such artifact.

Flag enforcement is version-routed:
- **v3 autonomous plans** — also requires the 5 discriminator flags + 2 opt-in flags.
- **v4 and v5 autonomous plans** — same, plus a non-empty `model_plan`.
- **v1/v2 plans** — grandfathered; only the `governing-skill:` field is checked, no flag enforcement.
- **Unsupported version** — exit 2.

### `canonical-sdlc-evidence-gate.sh` — `PreToolUse | Bash`

Fires on `git commit`. Locates the newest plan, reads its `## SDLC State`, finds `current: N`, and blocks the commit if step `N`'s evidence line is missing, empty, or a placeholder.

Shape enforcement is version-routed:
- **v3/v4 plans** — run the v3 per-step shape table (v4 shares v3's table; pre-collapse step numbering).
- **v5 plans** — run the v5 per-step shape table above (the gate-collapsed 0–10 shape).
- **v1/v2 plans** — presence-only by default.

---

## Model and token strategy

canonical-sdlc pins the orchestrator on one strong model for the whole wave and reaches the cheaper tiers **only through subagent dispatch**. The reasoning is mechanical: switching the main model mid-wave invalidates the prompt cache (and a skill cannot enforce a main-model switch anyway), so the main model is fixed and the tiering lives in *who you dispatch to*.

Dispatch uses model family **aliases** (`model: opus`, `model: sonnet`) that resolve to the top model in each family at dispatch time — the skill never hardcodes a version, so it self-upgrades on every model release. The "currently resolves to" column is informational.

Four tiers by role (the default plan when `multi_agent: true`):

| Tier | Role | Model spec | Currently resolves to | Dispatch mechanism |
|---|---|---|---|---|
| **1 · Orchestrator** | main thread — runs Steps 1–3 directly, coordinates 4–10 | best available (detected at Step 0): Fable @ high → else top Opus @ xhigh | Fable 5 high / Opus 4.8 xhigh | the main session, fixed all wave |
| **2 · Execution-complex** | slices tagged `complex`, root-cause debugging, Step 6 review (5-axis + adversarial critic) | fresh `model: opus` | Opus 4.8 | fresh by default; `fork` only when the unit genuinely needs the inherited context |
| **3 · Execution-standard** | slices tagged `standard` — well-specified, single-subsystem, tests define done | fresh `model: sonnet` | Sonnet 5 | **fresh** (never a fork) |
| **4 · Explore / mechanical / test** | codebase search, fixtures, mechanical edits, test-writing | fresh `model: sonnet` | Sonnet 5 | **fresh** (never a fork) |

**Why the orchestrator gets the best model.** Orchestrator errors are the most expensive tokens in the system — a bad decomposition wastes every subagent it dispatches — while the orchestrator is a minority of wave spend (execution carries the volume; the pinned main thread is mostly cache reads). Fable runs at `high`, not `xhigh`: its per-effort capability clears Opus-at-xhigh on coordination work, and xhigh buys diminishing returns there.

**Slice complexity routing.** At Step 3 every Step 4 slice gets a `complexity: standard | complex` tag in the plan, which routes its dispatch. Complex if any of: touches more than one subsystem, unresolved design decisions inside the slice, ambiguous spec surface, security-sensitive, expected root-cause debugging. When uncertain, tag `complex` — a misrouted slice costs more in rework than Sonnet saves. Opt out at Step 0 with `set exec-standard=opus` (shorthand: `set execution=opus-only`).

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
| `5` | **Current** | v4 set: 5 discriminators + 2 opt-in flags + required `model_plan` | v5 per-step shape table (the gate-collapsed 0–10 shape) |

Legacy plans (v1/v2) run grandfathered indefinitely: the governing-skill hook checks only `governing-skill:`, and the evidence gate uses presence-only. v3 plans remain enforced under the prior 5 + 2 contract. v4 and v5 require `model_plan`. v3/v4 plans run the v3 per-step shape table (v4 shares v3's); v5 plans run the v5 shape table.

---

## Configuration: the Step-0 wizard

Step 0 is mandatory for new plans (`canonical_sdlc_version: 5`). It sets every plan-shaping flag deliberately, with explicit user confirmation, in four sub-steps:

1. **Pre-flight environment check** — verify `.bionic/` root, resolve the docs root (`<project>/.bionic/config.yaml`'s `docs-root:`, default `.bionic/docs`), ensure `{specs,plans,adrs,incidents}/` exist, `mkdir -p .bionic/tmp/`, and verify both hooks are installed and executable.
2. **Infer recommended values** — from repo files (`tsconfig.json` → `typescript`, `Cargo.toml` → `rust`, …) and conversation keywords (surface type, deploy target, UI).
3. **Present the confirmation display** — flags, model plan, environment status, each with its inference rationale.
4. **Block until explicit confirmation** — no timeout, no implicit acceptance. After confirmation, create the TaskCreate list (`0:`…`10:`).

### The confirmation display

```
═══ Plan Configuration — confirm before Step 1 ═══
environment:
  bionic-root:  /Users/me/proj/.bionic       [verified]
  docs-root:    .bionic/docs                 [default]
  bionic-tmp:   /Users/me/proj/.bionic/tmp   [ready]
  hooks:        evidence-gate, governing-skill  [all installed]

slug: <inferred-from-conversation>
mode: autonomous

Discriminator flags:
  surface_type:    api          [inferred: "REST endpoint" in convo]
  language:        typescript   [inferred: tsconfig.json]
  has_ui:          false        [no UI mentioned]
  multi_agent:     true         [default — parallel-dispatch fit]
  deploy_target:   none         [no deploy signal]

Opt-in flags:
  cleanup_on_finish: true       [Step 9 (cleanup half) wipes .bionic/tmp/ on close]
  use_worktree:      false      [work on current branch]

Model plan:                      [multi_agent=true → tiered dispatch]
  orchestrator:  fable-5 high    [detected session model; main thread, fixed all wave]
  exec-complex:  opus            [fresh model:opus — slices tagged complex, debugging, Step 6 review]
  exec-standard: sonnet          [fresh model:sonnet — slices tagged standard]
  explore/test:  sonnet          [fresh model:sonnet — search, mechanical, tests]

Reply "confirm" to accept, or specify overrides:
  e.g. "set use_worktree=true, set exec-standard=opus, then confirm"
```

### Override DSL

The reply is parsed against a small grammar:

```
reply     := overrides? "confirm"
overrides := override ("," override)* ","?
override  := "set" flag "=" value  |  "change" flag "to" value
```

Accepted: `confirm`; `set use_worktree=true, confirm`; `set surface_type=graphql, set language=python, confirm`. Model-plan keys are valid targets: `set orchestrator=fable-high, confirm` (multi_agent=true), or `set main_model=sonnet, confirm` (multi_agent=false dial-down). On accept, the final values are written into frontmatter literally — every flag as an explicit `<key>: <value>` line, plus `model_plan`.

**Mid-plan reconfiguration:** edit the frontmatter directly; the new value takes effect on the next hook read.

---

## Quick reference

| Step | Gate | Evidence |
|---|---|---|
| 0. Configure | Frontmatter has `canonical_sdlc_version: 5` + 5 discriminator + 2 opt-in flags + `model_plan`; user confirmed; TaskCreate list created | Confirmation line in `## SDLC State` |
| 1. Ideate | Refined idea + "Not Doing" list; alternatives lens cites prior artifacts | Pointer to ideate body in spec |
| 2. Spec | Every requirement has an acceptance criterion | Pointer to spec doc |
| 3. Plan | No placeholders; `integration-branch:` declared; Step 4 expanded into slice tasks; approval | Pointer to plan body |
| 4. Implement | Every slice has a test that was RED first; worktree created if `use_worktree: true` | Slice-list pointer; worktree fields when applicable |
| 5. Verify (gate) | Tests/build pass (`pass == total`); browser modality proven (trace) or `n/a:` | `cmd:`/`pass:`/`total:`/`output:` **and** `devtools-trace:` or `n/a:` |
| 6. Review (gate) | Every one of the 5 axes has a verdict; adversarial critic attached (mandatory in `autonomous`, `incident-response`, `design-refresh`) | Pointer to 5-axis review body + critic findings |
| 7. Document decisions | Every significant decision has a record | `adr:` / `rca:` / `n/a:` |
| 8. External review | Review request open | `pr:` or `n/a:` (waivable for incident hotfix) |
| 9. Integrate & close | Wave merged into the declared `integration-branch`; worktree removed; `.bionic/tmp/` wiped; all tasks completed; `cleaned:` stamped | `merge:`/`worktree-removed:` **and** `cleanup:`/`tmp-wiped:`/`tasks-completed:` or `cleanup: n/a` |
| 10. Ship | Checklist complete; rollback documented; `continuation.md` written; gap closed (incident) | `deploy:`/`verified-at:`/`monitor:` or `n/a:` |
| — Commit rhythm | Cross-cutting; per-step checkpoint commit (not a numbered step) | Atomic commits; scope matches spec |

---

## Pointers

| Resource | Path |
|---|---|
| Skill prose (Claude reads at runtime) | [`SKILL.md`](SKILL.md) |
| Evidence-gate hook | [`canonical-sdlc-evidence-gate.sh`](../../hooks/canonical-sdlc-evidence-gate.sh) |
| Governing-skill hook | [`canonical-sdlc-governing-skill.sh`](../../hooks/canonical-sdlc-governing-skill.sh) |
| Diagram sources | [`diagrams/`](diagrams/) |
