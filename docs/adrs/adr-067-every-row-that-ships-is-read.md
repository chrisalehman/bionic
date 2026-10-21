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
# ADR-067 — Every row that ships is read, and a judge is never changed by what it judges without a person

## Status

**Accepted** (close-out, 2026-10-21; Proposed at Step 2, 2026-10-20). On Chris Lehman's rulings D2, D4, D10 and D11 (wave-41 design-ledger Δ4, Δ7, Δ23, Δ24). Extends ADR-064 (a rule is enforced at one door) and ADR-065 (a landing proves its own change).

## Context

Wave 40 landed two fixes after its release row. The plan refuses a review row after the release row, so neither could be read; the orchestrator typed six waivers by hand, one set sixteen seconds before the card rendered, and a hand commit re-rendered the release note's numbers the fixes had made stale. The same wave met the door's rule that a landing is judged by the target's copy of the declared check: a fix to the check itself could not pass its own door, and it was merged by hand outside the door with no rule saying so. The tests that had pinned that rule were deleted by the line cap, and no test anywhere pushed a landing through the real door with the project's declared check.

## Decision

A fix landed after the release is read like any other code: a review row that reads only post-release rows is admitted after the release row, the two readers read the fix as a piece, and the card waits for them. When the line publishes a row past a landed release row, it re-renders the release note's numbers at the new head as part of that landing, before the post-landing check; no person commits them. The door keeps judging every landing with the target's copy of the check; a landing that changes the check which judges it is refused with the fact named, `judged-by=target`, the script and base it ran as, `changed-here=` the path the landing changes, and the by-hand route a person takes; the hand landing records which copy judged it. The door is tested through the door: one fixture library builds a repository that carries the check's whole closure committed at its accepted head, declares the check by relative path and carries the real changelog; a landing suite lands rows through the real hand door and the line, a card suite carries a run through the verbs to the end state and renders the real card, and a cover suite reads the judge over the project's real release merges, pinned by hash.

## Consequences

- No waiver is a default; a waiver is the user's act on the card.
- A post-release fix costs two piece reads, minutes each, and no hand act.
- The release note's numbers are a function of the record at every landing that moves them.
- A check fix is the one landing a person makes, and the refusal says so in words; the record says which copy judged.
- A rule that passes in a writer's tree and fails in the door is caught by a fixture that runs the door: the three wave-40 defects re-planted each turn a named assertion red.
