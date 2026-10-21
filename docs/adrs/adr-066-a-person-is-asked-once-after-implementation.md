---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 2
epic: epic-23-bionic-tech-debt
wave: wave-41-run-closes-itself
intent: build
rigor: double
scale: wave
canonical_sdlc_version: 14
surface_type: cli-plugin
language: bash
has_ui: false
multi_agent: true
deploy_target: n/a
cleanup_on_finish: true
use_worktree: false
model_plan: orchestrator=claude-fable-5-1; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-high; auditor=opus-high; critic=opus-high
status: Accepted (close-out, 2026-10-21; Proposed at Step 2, 2026-10-20)
created: 2026-10-20
---
# ADR-066 — A person is asked once after implementation

## Status

**Accepted** (close-out, 2026-10-21; Proposed at Step 2, 2026-10-20). On Chris Lehman's rulings D1, D8 and D9 (wave-41 design-ledger Δ6, Δ18, Δ20).

## Context

The run's five designed human stops are the four cards before code and the final card. In practice a sixth had grown: the commit wall's matrix arm refused the advance from verifying to reviewing until every unproved evidence row was confirmed or waived, and only a person can waive. The release approval card then put the same rows to the person after the release. In wave 40 the counter stuck at step 5 while the step-7 release row ran, the orchestrator put three decisions early that the card carried anyway, and it declined the release row four times on a typed reason that named the user. Twenty of the wave's 120 hand-holds were declines, every one a wait the plan could have carried as a fact.

## Decision

After implementation a person is asked once, at the release approval card, before the merge. Every gate between implementation and the card holds machine facts: the advance from verifying to reviewing demands that every evidence row has a verdict, from the auditor or a user-confirmation line present, never a ruling; the advance to the merge demands that every row is ruled, confirmed, waived or user-confirmed, and the card is the one writer of those rulings. One predicate, shared by the wall, the judge and the card, says whether a row is ruled. A reading's result is told and its decision put the moment it lands, as a non-blocking put with its wait line, and no row is ever held on an open decision. Nothing typed can hold a ready row: the decline verb is deleted, and a row that should wait is made not ready by a fact in the plan, a dependency, a read of a ruling, or an order in the user's words.

## Consequences

- The step counter follows the work, and the sitrep's predicted close holds once the last build row lands.
- A refuted row reaches the release unruled; the card lists it with its default, the merge refuses until it is ruled, and a "fix" ruling runs the post-release path (ADR-067).
- An early ask is a put, never a hold: the sitrep and the resume recap show every open decision with what waiting costs.
- The "declines" class of hand-holds is zero by construction; the measure from the last build landing to the card counts hand landings, waivers and amendments only.
- A wait has one spelling, in the plan; the stop wall's refusal names the three forms.
