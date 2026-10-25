---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 7
epic: epic-23-bionic-tech-debt
wave: wave-45-whole-run
intent: build
rigor: single
scale: task
canonical_sdlc_version: 14
surface_type: cli-plugin
language: bash
has_ui: false
multi_agent: true
deploy_target: n/a
cleanup_on_finish: true
use_worktree: false
walk: required
design-interview: true
model_plan: orchestrator=claude-fable-5-1; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-high; auditor=opus-high; critic=opus-high
status: Proposed (Step 7, 2026-10-24)
created: 2026-10-24
---
# ADR-072 — A landing settles what it proves

## Status

**Proposed** (Step 7, 2026-10-24). On Chris Lehman's ruling D2 (wave-45 design-ledger Δ3, 2026-10-24 2:21 PM PDT: "D2 Option 1").

## Context

The 1.26.0 and 1.27.0 close replays showed a landing that settles half of what it proves. A landing filled the evidence of its own row and left the rest to a person: the findings it fixed were moved by `finding-move` after it landed, the matrix status cells were set by `matrix-set`, and the suite verdicts were written by hand. This run met the same shape in its own build: 22 of its matrix rows read `pending` after their tasks had landed, because the landing's evidence reader keyed a log by the suite's bare name and the eval cells spell `tests/<suite>.test.sh`. Each was discharged by `matrix-set` afterwards (A-orch.38). The hand-holds measure counts a run's hand edits as the cost of the landing, so a landing that settles half of what it proves charges the run for the other half.

## Decision

A landing settles everything it proves in one act, and the act that learns a fact writes every cell the fact fills. Before it publishes, the landing computes the whole list of what it proves and writes it together: the findings it was born for (`units_born_findings`), the findings at the same `at=<path:line>` in other records at the review's head, the findings carried to it (`_line_carried_close`), its matrix status cell (`matrix_row_cell`) and its suite verdicts (`_line_hand_verdicts`). `finding-move`, `matrix-set` and `discharge` remain as a person's corrections, and each refuses a cell the landing settled, naming it. The rule binds every later write of the wave: a verb that learns a fact writes each cell that fact fills, and no second verb is left to copy it.

## Consequences

- T6 builds the settlement. `line_settle` writes the list into the landing's copy of the plan before the swap, `row-landed` calls it before it publishes and `land --by-hand` writes its verdicts before its publish, and the landing record gains `ev=settled|row|commit|findings|cells`.
- A correction stays possible and stays visible. T31 counts a status written by `matrix-set` in the hand-holds line as `status-writes=<n>`, so a cell set by hand after a landing is a cost the measure reads, not a silent repair.
- The close follows the same rule. T33 (D29) has close-out settle the live hand-holds row from its own last reading, through the matrix writers it now reaches in `lib/units.sh`, so the one row that cannot be written by a landing is written by the act that learns its value.
- A cell the landing did not settle keeps the old path: the separate verbs write it, and the hand-holds measure counts that write.
