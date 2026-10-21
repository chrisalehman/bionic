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
# ADR-068 — A test earns its place by a stated criterion, and the tree may not outgrow the code

## Status

**Accepted** (close-out, 2026-10-21; Proposed at Step 2, 2026-10-20). On Chris Lehman's rulings D3, D5, D6 and D12 (wave-41 design-ledger Δ8, Δ11, Δ12, Δ26).

## Context

The test tree reached 180,000 lines against 95,000 lines of code before wave 40 cut it by shape: a 1,000-line cap per suite and a sweep of sentence, count and document checks. The sweep deleted the only tests that pinned the door's check and the quitting-grep lint, which is how two of wave 41's three S1 defects got through, and it deleted two suites on a wrong premise, the privacy scan's and the doctor's, which test no part of the index they were named for. At 1.23.0 the tree stands at 90,377 lines of test shell against 95,208 of code shell.

## Decision

A test is kept or deleted by a named verdict from a written rubric, never by shape. The criterion: a check earns its place only if it can fail in a way nothing already run catches. The rubric names five verdicts with their tests: keep, with the planted defect that turns the section red and that no other section catches; cull as duplicate, when a named section goes red on the same defect; cull as prose pin, when the assertion reads a sentence's wording where a field, an exit code or an id carries the fact; cull as tally, when it asserts a count that drifts with the tree; cull as vacuous, when the fixture never reaches the assertion. A census reads every section of every suite against the rubric, by several readers calibrated on the same suites first, and the cull deletes by the census; a section whose planted defect names a door refusal, a lint or a check pin is never culled. The two suites deleted on the wrong premise come back. And the tree may not outgrow the code: shell lines under tests/ may not exceed shell lines elsewhere, counted over tracked files at the landing's head, and the door's declared check refuses a landing that would cross it.

## Consequences

- A deletion carries its reason; the next cull starts from the census, not from a regex.
- The rubric lives with the tests, and a reader applies it the same way as the last one.
- Every landing that adds tests must stand under the ratio; the first cull makes the room.
- The door's pins and the lints are named as such in the census and cannot be culled by it.
- The privacy scan and the doctor's facts are tested again.
