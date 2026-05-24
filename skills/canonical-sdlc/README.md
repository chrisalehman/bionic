# Canonical SDLC

Bionic's flagship engineering pattern: a 15-step (0–14) autonomous software development lifecycle that runs unattended for hours and produces an auditable record at the end.

This is the human-facing reference. The skill prose Claude reads at runtime is in [`SKILL.md`](SKILL.md) — same directory.

> **TL;DR.** A skill enforces 15 contiguous steps (0. Configure → 14. Ship). Two hooks back the skill: `governing-skill` validates plan frontmatter on every write; `evidence-gate` blocks commits without per-step evidence. Plan frontmatter is single source of truth — `mode`, `sdlc-step`, 5 discriminator flags, 2 opt-in flags. Five modes: `autonomous` (default), `epic-scope`, `incident-response`, `design-refresh`, `spike`. Autonomous mode pairs with `map-instrument-narrow` via the Autonomous Friction Protocol — diagnostic friction loads MAP first, before any speculative fix.

---

## Contents

- [Why this exists](#why-this-exists)
- [A real plan walkthrough](#a-real-plan-walkthrough)
- [Diagrams](#diagrams)
- [Configuration deep-dive](#configuration-deep-dive)
- [Mode comparison](#mode-comparison)
- [Comparison vs alternatives](#comparison-vs-alternatives)
- [Pointers](#pointers)

---

## Why this exists

Most "AI does the SDLC" demos collapse the lifecycle: a brainstorm becomes code in one shot, with the spec implied, the plan unwritten, the review skipped, the audit trail missing. That works on toy problems and fails on anything wave-sized — multi-day work that touches multiple files, ships to users, and accumulates decisions a future maintainer needs.

Canonical SDLC is the constraint that forces the lifecycle to stay intact. Each of the 15 steps contributes a dimension of fidelity — scope, contract, plan, proof, review, decision record, release discipline — that no other step supplies. Without enforcement, individual steps feel skippable in isolation, but the compounding loss of fidelity is invisible mid-effort and surfaces later as rework.

The skill plus two hooks make the lifecycle non-skippable. The plan file is the single source of truth: state lives in YAML frontmatter, evidence lives in the `## SDLC State` section, and decisions live in ADRs (or RCAs for incidents). Every commit must show evidence for the current step. Every plan/spec/ADR must declare the skill that produced it.

The autonomous span is **Steps 4–14** — Claude walks away to build for hours and returns with merged code. Steps 1–3 (Ideate, Spec, Plan) are interactive: that's where wrong assumptions get caught cheaply. Step 3 ends with an explicit user approval before autonomous execution begins.

---

## A real plan walkthrough

This is the shape of an actual canonical-sdlc v3 plan. The example is invented — a hypothetical "add rate-limiting to the auth API" wave — but every line matches the real schema and would pass the actual hooks.

### The plan file

`docs/bionic/plans/epic-04-auth-hardening/wave-02-rate-limit.plan.md`:

```markdown
---
governing-skill: superpowers:writing-plans
sdlc-step: 5
canonical_sdlc_version: 3
mode: autonomous
epic: epic-04-auth-hardening
wave: wave-02-rate-limit

# Discriminators (drive specialist selection per step)
surface_type: api
language: typescript
has_ui: false
multi_agent: false
deploy_target: vercel

# Opt-in flags
cleanup_on_finish: true
use_worktree: true

# Audit
created: 2026-05-03
cleaned: null
---

# Wave 2 — Token-bucket rate limit on /auth/login

## SDLC State
mode: autonomous
integration-branch: main
current: 5

Step 0: configured at 2026-05-03T14:22Z via "set deploy_target=vercel, set use_worktree=true, confirm"
Step 1: docs/bionic/specs/epic-04-auth-hardening/wave-02-rate-limit.spec.md#phase-1
Step 2: docs/bionic/specs/epic-04-auth-hardening/wave-02-rate-limit.spec.md#phase-2
Step 3: #plan-body
Step 4:
  worktree: .worktrees/wave-02-rate-limit
  base-sha: a1b2c3d
  branch: wave-02-rate-limit
Step 5: (pending)
Step 6: (pending)
Step 7: (pending)
Step 8: (pending)
Step 9: (pending)
Step 10: (pending)
Step 11: (pending)
Step 12: (pending)
Step 13: (pending)
Step 14: (pending)

## Assumptions
- Token bucket sized for 5 logins/min/IP — matches existing /auth/signup limit
- Redis already provisioned for session storage; reuse for rate-limit counters
- Failure mode on Redis outage: fail open (log warning), not fail closed (block all logins)

## Plan body
... ordered step list, critical files list ...
```

The frontmatter declares everything that drives behavior. The `## SDLC State` section records evidence as steps progress — `(pending)` placeholders are blocked from commit by the evidence-gate hook, so each step's line is updated **before** the commit lands.

### What each hook checks at each step

| Step transition | Tool call that fires | Hook | What gets validated |
|---|---|---|---|
| Plan write at Step 3 | `Write` of `wave-02-rate-limit.plan.md` | `governing-skill` | Frontmatter has `governing-skill: superpowers:writing-plans`, `canonical_sdlc_version: 3`, `mode: autonomous`, all 5 discriminator flags, both opt-in flags |
| Step 6 commit | `Bash` running `git commit -m "test: rate-limit suite passes 47/47"` | `evidence-gate` | Plan's `## SDLC State` `Step 6:` block has `cmd:`, `pass: 47`, `total: 47`, `output: ...`; `pass == total` |
| Step 8 critic commit | `Bash` running `git commit -m "test: critic clean"` | `evidence-gate` | `Step 8:` block has critic-report pointer or `Findings: none` |
| Step 12 finish-branch commit | `Bash` running `git commit -m "chore: merge wave-02 into main"` | `evidence-gate` | `Step 12:` block has `merge:`, `worktree-removed:` |
| Plan write at Step 13 cleanup | `Write` of cleaned-up plan | `governing-skill` | Same v3 schema check, plus `cleaned: 2026-05-03` set; cleanup commit subject matches `chore(plan): post-merge cleanup of <slug>` |
| Step 14 ship | `Bash` running `git commit -m "feat(auth): rate-limit on login"` | `evidence-gate` | `Step 14:` block has `deploy: vercel`, `verified-at: ...`, `monitor: ...` |

The hooks compose without coordinating: governing-skill gates every plan write, evidence-gate gates every git commit. Each hook reads the same plan frontmatter independently — there's no shared state between them.

### Multi-session handoff

When a session ends mid-plan (`Stop` event fires while `current < 14`), the skill writes a `## Handoff` section to the plan body before the session terminates:

```markdown
## Handoff
<!-- Always preserved. Updated at session end. -->

### Resume point
step: 5
sub-task: "implement Redis token-bucket adapter; tests RED at slot 3/8"
worktree: .worktrees/wave-02-rate-limit
branch: wave-02-rate-limit
last-commit: e4f5g6h
session-count: 2

### Decisions ratified this session
<!-- max 5 bullets. RESET each session. -->
- Token bucket impl uses Redis SETEX + Lua script for atomicity
- Fail-open behavior on Redis outage logged as audit event

### Tried and rejected
<!-- max 5; persists across sessions. -->
- In-memory fallback per-instance — rejected (load balancer breaks counting)

### Discovered surprises
<!-- max 5; persists across sessions. -->
- Existing /auth/signup rate-limit uses different counter shape; can't reuse adapter directly

### Open blockers
- step 6 blocked on staging Redis access (ticket OPS-441)

### Resume protocol
Read this handoff, then frontmatter, then `## SDLC State`. Continue at step 5 sub-task above. Run `bash test.sh` to confirm baseline before resuming.
```

Per-field caps prevent unbounded growth. The handoff is **rewritten in place** every session — never appended. A 3-session plan has the same handoff size as a 1-session plan. When the wave finishes single-session (or finishes a multi-session run within the resumed session), Step 13 cleanup strips the handoff because it's no longer needed for resume.

Handoff is its own evidence tier, structurally separated from per-step evidence. A multi-session plan always gets a handoff regardless of which other flags are set.

---

## Diagrams

### The 14-step lifecycle (with mode-keyed branches)

![Canonical SDLC lifecycle](diagrams/lifecycle.png)

> **Note:** the lifecycle diagram pre-dates the v3 renumber and still labels three of the steps with their legacy v2 interstitial numbers (`Step 0.5`, `Step 8b`, `Step 12.5`). The current SKILL.md has those folded into a contiguous 0–14 numbering. Diagram regen is tracked separately.

The autonomous mode walks all 15 steps (0. Configure → 14. Ship). The Approval Checkpoint between Step 3 and Step 4 is the "walk away" boundary — after that, Claude runs unattended through Step 14.

Mode-keyed divergences:
- **`epic-scope`** terminates after Step 3 — the output is `epic.spec.md` + `epic.plan.md` carving the work into waves; no implementation yet.
- **`incident-response`** substitutes RCA for ADR at Step 9, allows Step 11 to be waived for hotfixes (with retrospective review within 24 hours), and expands Step 14 to deploy + monitor + close monitoring gap.
- **`design-refresh`** swaps Step 1's governing skill from `idea-refine` to `shape`; Step 4 becomes a `craft → polish → critique` loop with a measurable exit gate; Step 5 is heavily weighted with audit reports.
- **`spike`** bypasses the lifecycle — output is a writeup at `docs/bionic/spikes/`. No worktree, no ADR, no commits to integration. If a spike reveals shippable work, declare a new mode and re-enter at Step 1.

### How the two hooks compose

![Hook chain](diagrams/hook-chain.png)

> **Note:** this diagram also pre-dates v3 and depicts the deleted `dispatch-gate` hook alongside the two current hooks. v3 ships with `governing-skill` + `evidence-gate` only.

Two independent hooks gate two different tool events. Each reads the active plan's frontmatter independently — there's no shared state. The data dependencies:

- **Plan frontmatter** fans out to both hooks. `governing-skill` checks the schema on every plan/spec/ADR write; `evidence-gate` reads `sdlc-step` + `deploy_target` to know which evidence shape to validate.
- **`## SDLC State`** feeds only `evidence-gate`. The hook scans newest-mtime plans under `docs/bionic/plans/` and `docs/bionic/incidents/` to find the active one.

Both hooks hard-block by default. There is no per-plan way to disable them — if you need to write past a check, fix the frontmatter or evidence.

---

## Configuration deep-dive

Every behavior in canonical-sdlc is configurable through plan frontmatter. The configuration story is the reason the system can be calibrated for a specific project's reality.

### The plan frontmatter contract

Plans declare every plan-shaping flag in YAML frontmatter. Step 0 (the wizard) writes this; the governing-skill hook enforces presence on writes; the evidence-gate hook reads it on every commit.

**Identity (required):**

| Field | Values | Purpose |
|---|---|---|
| `governing-skill` | A skill ID like `canonical-sdlc`, `superpowers:writing-plans`, `agent-skills:idea-refine` | Names the skill that produced the artifact. Different artifacts use different governing skills (Step 1 spec → `idea-refine`; Step 3 plan → `writing-plans`; Step 9 RCA → `canonical-sdlc`). |
| `mode` | `autonomous` (default) \| `epic-scope` \| `incident-response` \| `design-refresh` \| `spike` | Determines which steps apply, default flag values, and step substitutions. |
| `sdlc-step` | `0..14` | Current step. The evidence-gate hook reads this to know which step's evidence line to validate. Update **before** the commit that closes the step. |
| `canonical_sdlc_version` | `3` (current) \| `1` \| `2` (legacy, grandfathered) | Routes the hooks: v1/v2 plans take the legacy presence-only path; v3 plans get full schema enforcement. |
| `epic` / `wave` / `incident` | Identifier matching the enclosing directory | Cross-reference. `epic-NN-<slug>` and `wave-NN-<slug>` for epic-tree work; `NNNN-<slug>` for incidents. |

**Discriminator flags (required for v3 autonomous; drive specialist selection):**

| Flag | Values | Drives |
|---|---|---|
| `surface_type` | `api` \| `graphql` \| `ui` \| `system` \| `realtime` \| `mobile` \| `ml` \| `iac` \| `none` | Step 2 spec specialist; Step 4 implementer dispatch hints; Step 5 browser-verify weighting |
| `language` | `rust` \| `typescript` \| `javascript` \| `go` \| `python` \| `java` \| `csharp` \| `cpp` \| `php` \| `swift` \| `kotlin` \| `sql` \| `other` \| `none` | Step 4 language specialist hint |
| `has_ui` | bool | Step 5 (browser-verify becomes mandatory not n/a); Step 7 (frontend-ui-engineering escalation) |
| `multi_agent` | bool | Step 4 (parallel implementer dispatch); Step 10 (multi-commit coordination) |
| `deploy_target` | `none` \| `k8s` \| `vercel` \| `custom` \| `migration` | Step 14 deploy specialist set |

**Opt-in flags (required for v3 autonomous; per-plan rollout control):**

| Flag | Default | What it does |
|---|---|---|
| `cleanup_on_finish` | `true` | When `true`, Step 13 runs after Step 12's merge: wipes `.bionic/tmp/`, asserts TaskCreate list integrity, strips leftover handoff files, sets `cleaned: <date>` |
| `use_worktree` | `false` | When `true`, Step 4 creates a git worktree at `.worktrees/<slug>` off the current branch before the first slice. When `false`, work proceeds on the current branch. |

**Audit:**

| Field | Purpose |
|---|---|
| `created` | Plan creation date (ISO) |
| `cleaned` | Set by Step 13 when cleanup runs (idempotency marker) |
| `session-count` | Incremented at session resume; reset to 1 on creation. Drives Step 13 handoff-fate decision. |

### Mid-plan reconfiguration

To change a flag mid-plan, edit the plan frontmatter directly. The new value takes effect on the next hook read. There is no separate config file to update, no restart, no cache.

### Legacy plan handling

Plans with `canonical_sdlc_version: 1` or `2` are grandfathered. The governing-skill hook checks only the `governing-skill:` field for legacy plans, and evidence-gate uses the pre-v3 presence-only path. Legacy plans run forever in their original mode (or until you choose to manually rewrite the frontmatter to v3 schema).

---

## Mode comparison

The five modes determine which steps apply and how each step is governed. Most differences cluster at Steps 1, 4, 9, 11, 14.

| Step | `autonomous` (default) | `epic-scope` | `incident-response` | `design-refresh` | `spike` |
|---|---|---|---|---|---|
| 0. Configure | ✓ required | ✓ required | ✓ required | ✓ required | ✓ lightweight |
| 1. Ideate | `idea-refine` (interactive Q&A) | `idea-refine` (interactive Q&A) | `idea-refine` compressed → triage | `shape` (design brief) | woven `source-driven-development` |
| 2. Spec | testable contract | `epic.spec.md` | `spec.md`: repro + closure criteria | visual acceptance criteria | — |
| 3. Plan | `epic-NN-<slug>/wave-NN-<slug>.plan.md` | `epic.plan.md` (carves waves) | incident `plan.md` | wave `.plan.md` | — |
| **3 → 4** | **Approval Checkpoint (walk-away boundary)** | terminates here | Approval Checkpoint | Approval Checkpoint | — |
| 4. Implement | `incremental-implementation` + TDD; worktree if `use_worktree: true` | N/A | systematic-debugging → fix; failing test = repro | `impeccable` `craft → polish → critique` loop | informal research |
| 5. Browser verify | UI flows or N/A | N/A | UI flows or N/A | heavily weighted; per-state evidence + `audit` | — |
| 6. Verify done | `verification-before-completion` | N/A | `verification-before-completion` | `verification-before-completion` | — |
| 7. Self-review | 5-axis review | N/A | 5-axis | 5 code axes only | — |
| 8. Adversarial critic | **mandatory** | N/A | mandatory; framed for "fix masks deeper issue" | mandatory; framed for visual regressions + a11y | optional |
| 9. Document | ADR | N/A | **RCA (not ADR)** | ADR | — |
| 10. Commit | per-step checkpoint | N/A | per-step checkpoint | per-step checkpoint | no commits to integration |
| 11. External review | required | N/A | **waivable** for hotfix; retro within 24h | required | — |
| 12. Finish branch | merge to integration; remove worktree if any | N/A | merge | merge | — |
| 13. Post-merge cleanup | runs when `cleanup_on_finish: true` | N/A | runs | runs | — |
| 14. Ship | checklist + rollback + `continuation.md` | N/A | deploy + monitor + close gap | + optional `extract` for design-system patterns | writeup at `docs/bionic/spikes/` |

Default flag values per mode:

| Mode | `cleanup_on_finish` | `use_worktree` | Step 8 mandatory? |
|---|---|---|---|
| `autonomous` | `true` | `false` | yes |
| `epic-scope` | `true` | `false` | N/A (no code) |
| `incident-response` | `true` | `false` | yes |
| `design-refresh` | `true` | `false` | yes |
| `spike` | `false` | `false` | optional |

Mode declaration is reviewable. A wave-sized feature disguised as a `spike` to skip the lifecycle is drift with a label; the declaration must match the actual work.

### Autonomous Friction Protocol (the bridge to `map-instrument-narrow`)

In `autonomous` mode, diagnostic friction (tests failing, behavior diverging) loads `map-instrument-narrow` immediately — before any speculative fix. Decision friction (ambiguity, blocked-on-judgment) surfaces via User Decision Protocol. The three-fail rule resets only after a completed MAP-INSTRUMENT-NARROW pass yields a root cause; it does not reset on additional speculative fixes.

See SKILL.md `### Autonomous Friction Protocol` for the full rule. The bridge is reciprocal: `map-instrument-narrow`'s `## Invocation` section names this protocol as a canonical entry path.

---

## Comparison vs alternatives

|  | Canonical SDLC | superpowers SDLC | Raw `agent-skills` | No skill |
|---|---|---|---|---|
| **Lifecycle enforcement** | 15 contiguous steps, hook-enforced | 7 skills, soft chained | None — content rubrics only | None |
| **State persistence** | Plan frontmatter + `## SDLC State` + `## Handoff` | Plan files; no state schema | None | None |
| **Audit trail** | Per-step checkpoint commits + ADRs/RCAs | Optional; at user discretion | None | None |
| **Multi-session resume** | `## Handoff` schema + `continuation.md` | Manual | Manual | Manual |
| **Configurability** | ~7 plan flags (5 discriminators + 2 opt-in) | None | None | N/A |
| **Mode polymorphism** | 5 modes (autonomous, epic-scope, incident-response, design-refresh, spike) | None | None | N/A |
| **External enforcement** | 2 hooks (governing-skill, evidence-gate) | None | None | None |
| **Diagnostic-friction discipline** | Autonomous Friction Protocol → `map-instrument-narrow` bridge | Manual recall | Manual | Manual |
| **Cost** | ~5–15 commits per wave; 7 frontmatter fields to maintain | Lighter; no audit trail | None — picked à la carte | None |
| **When to use** | Wave-sized work that ships to users; epics; production incidents; design refreshes | One-off changes; small features | Specific content needs (5-axis review, 6-lens ideation) | Throwaway scripts, exploration |

The three are not mutually exclusive. `canonical-sdlc` calls into both `superpowers:` and `agent-skills:` skills for individual steps — `superpowers:writing-plans` governs Step 3, `agent-skills:idea-refine` governs Step 1, `agent-skills:code-review-and-quality` governs Step 7, etc. The flagship pattern is the *enforcement shell*, not a replacement for either plugin.

For one-off changes (typo fix, single-file refactor), use `superpowers:writing-plans` directly without invoking canonical-sdlc — the audit trail isn't worth the overhead.

---

## Pointers

| Resource | Path |
|---|---|
| Skill prose (Claude reads at runtime) | [`SKILL.md`](SKILL.md) |
| Lifecycle diagram source | [`diagrams/lifecycle.excalidraw`](diagrams/lifecycle.excalidraw) |
| Hook-chain diagram source | [`diagrams/hook-chain.excalidraw`](diagrams/hook-chain.excalidraw) |
| Hooks (in-tree source) | [`canonical-sdlc-evidence-gate.sh`](../../hooks/canonical-sdlc-evidence-gate.sh), [`canonical-sdlc-governing-skill.sh`](../../hooks/canonical-sdlc-governing-skill.sh) |
| Bridge target — diagnostic friction discipline | [`../map-instrument-narrow/SKILL.md`](../map-instrument-narrow/SKILL.md) |
