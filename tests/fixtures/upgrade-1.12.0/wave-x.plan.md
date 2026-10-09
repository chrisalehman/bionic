---
governing-skill: superpowers:writing-plans
sdlc-step: 3
epic: epic-x
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
use_worktree: true
walk: required
design-interview: false
model_plan: orchestrator=model-a; implementor=model-b; researcher=model-c; test-runner=model-d; auditor=model-c; critic=model-c
parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=probe
archive-root: /archive/fixture
requirements: specs/epic-x/wave-x.requirements.md
spec: specs/epic-x/wave-x.spec.md
working-branch: wave/x
integration-branch: main
base-sha: 0000000
release: 1.12.0
created: 2026-01-01
---
# fixture 1.12.0 — a plan as that release wrote it (tests/fixtures/upgrade-1.12.0)

## Goal

A throwaway plan in the shape bionic 1.12.0 wrote: the budget line the probe wrote, rows with no
landing label, and a Step 4 under way. Every word is invented; the file carries the shape only.

## SDLC State

integration-branch: main
working-branch: wave/x
base: main @ 0000000
intent: build
rigor: double
scale: wave
approved-by: fixture 2026-01-01T00:00Z "approved"
current: 4

- Step 0: configured at 2026-01-01T00:00Z via fixture "approved"; parallel-budget=writers=8 suites=4 worktrees=32 test_jobs=8 source=probe
- Step 1: requirements: specs/epic-x/wave-x.requirements.md; approved by fixture 2026-01-01 "approved"
- Step 2: spec: specs/epic-x/wave-x.spec.md (D1–D2); adr: adrs/epic-x/adr-001-fixture.md (Proposed); design ledger record/wave-x/design-ledger.md; card approved by fixture 2026-01-01 "approved"
- Step 3: plan: plans/epic-x/wave-x.plan.md; 2 rows
- Step 4: opened 2026-01-01T00:10Z on wave/x in the main checkout; writers in .worktrees/T<n> on wt/T<n>
  worktree: .
  base-sha: 0000000
  branch: wave/x
- T1: active
- T2: active

## Tasks

| id | step | kind | task | agent | deps | reads | size | serves | Files | worktree | base | status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | row one | wx-T1 | — | | 10 | REQ-1 | T1.txt | .worktrees/T1 | | active |
| T2 | 4 | build | row two | wx-T2 | — | | 10 | REQ-1 | T2.txt | .worktrees/T2 | | active |

## Dispatch ledger

| id | agent | dispatched | expected | artifact | landed | notes |
|---|---|---|---|---|---|---|
| T1 | implementor (wx-T1) | 2026-09-02T00:00Z | 45 min | .bionic/docs/record/wave-x/T1-one.md | | .worktrees/T1 |
| T2 | implementor (wx-T2) | 2026-09-02T00:00Z | 45 min | .bionic/docs/record/wave-x/T2-two.md | | .worktrees/T2 |
