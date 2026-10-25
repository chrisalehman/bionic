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
# ADR-073 — Consent guards a live run

## Status

**Proposed** (Step 7, 2026-10-24). On Chris Lehman's ruling D5 (wave-45 design-ledger Δ6, 2026-10-24 2:31 PM PDT: "D5 1"). It narrows the wave-36 ruling r1791954201-85499 and the consent boundary of ADR-003 and does not replace either.

## Context

ADR-003 made engagement the single switch: a bionic hook acts only for a session that invoked canonical-sdlc. The wave-36 ruling r1791954201-85499 (`record/wave-36-zero-machine-errors/assumptions.md` A-T14-6) carried that to the plan verbs: engagement is the consent boundary for every one of them, and a session that wants to amend a closed run re-engages and binds it. That left a delivered run unable to take its merge record or its continuation marks from the session that lands it. The merge record and the marks are the last facts a run learns, after the session that built it may have ended, and a session that never engaged could not write them.

## Decision

Engagement is the consent boundary for a run that is still moving. A delivered run accepts its merge record (`step-field 8 --plan`) and its continuation marks (`continuation-fill --plan`) from any session that names the plan by `--plan`, and from nowhere else. Every other verb keeps the boundary: a delivered plan named by `--plan` on any other step or verb, and a live plan named so at Step 8, still print NOT-ENGAGED from an unengaged session.

## Consequences

- T9 implements the narrowing. `plan_delivered` judges a plan delivered from the named file alone: closed, not abandoned, with a Step 9 `delivered:` line. `plan_verb_open … delivered-ok` and `continuation-fill` then open it with no engagement asked, and `step-field` takes `--plan` anywhere after the step number. `epic-row` keeps the engagement ask on a delivered plan, because the narrowed boundary names two facts and nothing else.
- A fresh continuation holds exactly five person-owned marks, and all five fill from an unengaged session to zero, so the close's last paperwork costs no re-engagement.
- T13 sets the order at pr dealing, the reviews part, then the push, then the pull request. The merge a delivered run waits on is therefore of a branch that already carries its reviews, and the merge record written afterwards is the `step-field 8 --plan` call this decision admits.
- Consent is not widened for a live run. A session that does not name a delivered plan by `--plan` gains nothing.
