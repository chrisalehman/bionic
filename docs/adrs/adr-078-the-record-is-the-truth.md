---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 7
epic: epic-23-bionic-tech-debt
wave: wave-50-one-log
intent: build
rigor: double
scale: wave
canonical_sdlc_version: 15
surface_type: cli-plugin
language: bash
has_ui: false
multi_agent: true
deploy_target: n/a
cleanup_on_finish: true
use_worktree: false
walk: required
design-interview: true
model_plan: orchestrator=claude-fable-5-2; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-high; auditor=opus-high; critic=opus-high
status: Proposed (Step 7, 2026-11-16)
created: 2026-11-09
---
# ADR-078 — The record is the truth

## Status

**Proposed** (Step 7, 2026-11-16), drafted at Step 2 on 2026-11-09. On Chris Lehman's rulings: D1 of the kernel charter (2026-10-26), D2 to D20 of the kernel map (GitHub issues 38 to 40, 2026-10-26 and 27), D1 to D12 of wave 50 (record/wave-50-one-log/design-ledger.md, 2026-11-09), and the cut, D44, D48 and D49 (2026-11-15): 2.0.0 reads a run at version 15 and nothing older. It supersedes ADR-002 (the tick reads the plan), ADR-027 (the task table as the unit register), ADR-032 (the task row as the tree's record) and ADR-035 (the budget the plan carries). It amends ADR-029 and ADR-038 (the brief is a rendered file the dispatch names, not a scaffold pasted into a prompt), and the twenty the map's research marked amended, each by the one clause that named a plan line or a hook arm as a fact's home.

## Context

Through version 14 a run's facts lived in its Markdown plan and in several record files, and many places in the tool each parsed them for themselves. The kernel spike counted 142 facts, 59 of them read by two or more grammars, and 105 recorded disagreements between two readers of one fact in four runs. Twenty of the fifty tasks born mid-run in those waves existed to repair one. Each repair added a reader. The two facts that already had one writer and one reader, the landing record and the asks register, never disagreed.

## Decision

**Every act of a run is written once, to one log; one reader answers every question from it; the plan holds only what a person wrote.**

1. The log is `record/<wave>/run.log`, one per plan, append-only, written by one appender in one line shape, `run/v1|ev=<event type>|<key>=<value>|…|at=<UTC seconds>`. The event types are a closed list: the 28 ruled on the map, `hand` (D8 of wave 50), and `drop`, a row's work no longer owed, carrying the person's words. A correction is a later line or a `cancel`, never an edit.
2. The reader is one program answering a closed list of named questions, by exit code, `key=value` lines or log-shaped lines. It is the only parser of the log and of the plan's authored parts. Every card, report, brief and gate asks it. A question is added only with a row of the replay bed.
3. A version-15 plan is its header, Goal, Problem, Design, Eval design and Tasks, with a section per task for what a person has to say about it (D9). No verb writes it. The verification matrix, the state section and the handoff section do not exist; each view of them is a screen.
4. No fact is written in two places at any commit (D2). The order this wave followed (D6): readers first, with the reader translating old-format runs as it read; then each family of facts moved to the log and lost its old home in the same landing; then the flip to version 15, after which the translation was deleted (D48).
5. A version applies to the plan of an open run and to nothing else (D11). 2.0.0 reads a run at version 15 and nothing older (D44, D48, D49): a plan at version 14 is a document that no gate judges as a run, a run begun under 1.30.0 is finished under 1.30.0, and older work comes forward as text a person or a model reads. The act that brought a version-14 run forward, keeping the old plan and record beside the new and naming every fact it could not translate, was built in this wave, used on its own run, and removed before the release; no act that brings a run forward ships.
6. An act taken by hand to keep a run going is an event that says what it was and what the interface lacked (D8). The count of such acts is a reader's answer, and each kind is carried to the next charter as a defect.
7. Whether a session, an agent or a run is alive is one rule about its process (D10), never the age or existence of a file.

## Consequences

- A screen cannot disagree with another screen, because neither works a fact out.
- The commands and hook arms that kept copies in agreement have no job; the spike estimated a quarter of the shell and of the tests. Measured by `payload/scripts/readings.sh` at 1.30.0 (7a9633486) and at the head this record was proposed on (97e71dac5): the poker's verbs fell from 68 to 39, the registered hook scripts from 11 to 9, the files that parse a plan or a log outside the reader from 24 to 0, the shell outside tests from 101,513 lines to 92,849 and the tests from 102,161 to 92,885.
- The plan is readable by a person and is no longer the tool's database, so the tool's state is not in a file a person edits.
- A run in flight at 1.30.0 is finished under 1.30.0: 2.0.0 does not read it and ships no act that carries it forward. This is the first release that reads no run of the release before it.
- The log is local and archived with the run (map D3), so a run's history is not in git; what a later reader needs is rendered once into the release entry.

## What it does not do

- It does not change the ten steps, the stops, the triple or the review rigor.
- It does not change the runtime (ADR-006 stands) or the docs home.
- It does not put session bookkeeping (ticks, the armed stamp, stop orders, rosters) in the log.
