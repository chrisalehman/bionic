---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 2
epic: epic-23-bionic-tech-debt
wave: wave-39-landing-proof
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
status: Accepted (close-out, 2026-10-19; Proposed at Step 2, 2026-10-18)
created: 2026-10-18
---
# ADR-062 — A review's fixes are inside the review

## Status

**Accepted** (close-out, 2026-10-19; Proposed at Step 2, 2026-10-18). On Chris Lehman's ruling at wave-39 D7 "1". Reverses wave-36 D16 "2" and amends ADR-056's decision text ("a row born of that reading").

## Context

The cover walk held a review-born landing only on the chains of the questions whose findings the row named (`_facts_basis`, payload/scripts/lib/proof.sh:2442-2443; the asker list from `_facts_born_landings`). Wave 36's D16 set it so: "a reviewer who did not ask for a change did not see it". In wave 38 two fix rows landed, one born of an adversarial finding, one of an adversarial and a structure finding; each reviewer then saw the other's fix as unread code, and the final card refused `CARD-EARLY — structure unregistered` until a piece re-read registered the other questions at the head. That re-read was one opus critic, about seven minutes of agent time and eleven and a half minutes of wall clock, and found nothing to fix: two minor findings carried, three notes, two debt lines (record/wave-39-landing-proof/research-review-cover.md §Q3). The doctrine already said the opposite of the judge: "mind checks run once, on the settled whole" (SKILL.md) and "A fix row is never re-read by a fresh pass" (steps/6.md:17). The one-stop rule of 1.21.0 exists to remove exactly the stop the re-read restored.

## Decision

A fix row born of a registered review finding is covered for every review question once it lands green. The provenance guard stays: a marker that names no `of=`, or an `of=` naming a record no registered reading names, owes on every chain, so cover cannot be typed by hand. A row moved to fixed by the user's words is covered the same way. The judge, steps/6.md, SKILL.md and ADR-056 say one rule, pinned by a fixture each, with the planted wave-38 shape (two fix rows born of different questions, every question covered at the head) as the positive and a non-born code commit still owing as the control.

## Consequences

- The final card renders after a round of fix rows with no re-read; the piece scope of `proof-add review` remains for the user's own call and is dispatched by no rule.
- A fix's code is proved by its red-to-green, its landing verdicts and the regression's facts, and read by no reviewer; what wave 38's re-read would have recorded (two S3 carried, two debt lines) goes unrecorded under this rule.
- The fix policy and the fix cap bound what a review may add as rows; they are the limit on how much lands unread.
- Five pins in tests/canonical-sdlc-evidence-gate-2.test.sh §COVER-ASKER flip (CA-1b, CA-1c, CA-2, CA-3, CA-4b) and gain a mutation control that restores the asker match.

## Alternatives rejected

- **Today's rule with the re-read automated** (the tick dispatches a reader for the uncovered questions after each fix batch): every fix read, ten minutes and a reader per batch, and the doctrine line rewritten to say the opposite of what it says.
- **A size cap** (born rows under a few files cover everything, larger ones re-read): two rules for one question, and wave 38's four-file fix would still have forced the re-read.
- **A cap by the fix cap**: identical to the decision, since `task-add` already refuses a born row past the cap.
