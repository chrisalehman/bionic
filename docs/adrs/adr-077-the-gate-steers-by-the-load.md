---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 7
epic: epic-23-bionic-tech-debt
wave: wave-49-what-a-run-costs
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
walk: required
design-interview: true
model_plan: orchestrator=claude-fable-5-1; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-high; auditor=opus-high; critic=opus-high
status: Proposed (Step 7, 2026-11-06)
created: 2026-11-06
---
# ADR-077 — The gate steers by the load

## Status

**Proposed** (Step 7, 2026-11-06). On Chris Lehman's rulings D2 to D13 (wave-49 design-ledger, 2026-11-06). It amends three earlier sentences. ADR-051's "a `whole` admission runs alone, so landings wait for the run" holds for `whole` alone: a browser or compile run is alone by arithmetic, not by kind, and is owed its measured cost, never a quiet machine. ADR-060's "the per-run core promise is the measured suite cost" is a prior now, replaced by the key's own measurement once one exists. Wave-33 D4's "no cores or memory are read from recorded runs" holds for memory only: cores are read from recorded runs.

## Context

A user project's wave of 2026-11-06 drove an 8-core machine to a 1-minute load of 17 to 34 for eleven minutes (issue #51). Three writers typed browser test runs into Bash; the wall books only suite-class commands, so the gate never saw them. Had it seen them it would have promised each 1.61 cores and admitted the first at any load, since its processor rule binds only while something is already admitted. Its room reading, meanwhile, counted running work twice, idling writers on a free machine on another day. The share kept nothing for the person.

The owner's principle, stated at the design frame: constants are fine before there is data, but "the system needs to be able to detect when resources are getting over-taxed, and self-regulate", dialling writers down if it has overcommitted the run.

## Decision

**The gate is a closed loop over the measured load, and promises only bridge the measurement's lag.**

1. A booked run promises its best available estimate of its cores. Once its key has a measurement, that is the cores its own past runs measured: `gate_end` writes them from `times` in the holder's shell as the cost line's fourth field, and the gate reads them by the robust rule the seconds use. Before a measurement, the prior is the class's. A suite or other work request is promised the suite constant. A whole run, and a browser or compile run before its key has a measurement, is promised the room free at admission, max(1, floor(lim − busy − faded)), and not the width: with the lone admission gone, a full-width promise waits for an idle machine. The test runner sizes its jobs from the admitted promise, and `gate_width` stays the share's room for the budget and the dry run (D13, amending D4). A measured promise is bounded by the same free room and is never less than one core, so a key measured past the line can still be admitted. The gate's own polls are not charged to the run: a baseline `times` read at admission is subtracted at the end.
2. A promise counts in full at admission and fades linearly to nothing over the load window, at admission, at the room and at the width ask alike, so a run is counted once: by its promise until the load reading can see it, by the reading after. An unknown busy reading counts every promise whole.
3. The processor limit binds whether or not anything is admitted. Load from work the gate never saw holds new admissions, the width ask answers 0 on load, and the oldest waiter is admitted first when the load falls.
4. The share's cores are the share less a reserve for the person, default one core, computed at one site, `_gate_share_cores`. The `share` verb prints and sets it.
5. When the 5-minute load exceeds the share's cores and the room is closed, the run stands down its newest unlanded writer, one per Patrol tick, and re-offers the row when room returns. An admitted run is never ended for load.
6. The wall books browser and compile commands as it books suites, and the shim carries their class to the gate with `--class`. No new kind: `whole` stays the test runner's.

## Consequences

- The overload of issue #51 cannot recur in that form: the three runs are booked, the first is admitted on the room free at that moment, and the next two wait on it and on the measured load.
- A warm browser run that measures one core is charged one core next time, so a wave is not held to the worst case forever.
- The dial-down acts at the Patrol's cadence; it is the backstop behind booking and the load wait.
- Three earlier rulings are amended as the Status says; nothing else of ADR-051, ADR-060 or wave-33 moves.
- The rows that built it: T1 the reserve, T4 the classes in the classifier and the wall, T6 the `share` verb's reserve, T8 the status line, T16 the runner's width reading the reserve, T7 the stand-down, T15 the close's one eval (close-criterion-eval burned), T2 the fade and the removal of the lone guard, T3 the measured cores and the free room as the prior, T5 the shim's class, T17 the bound on a measured promise and the baseline for the polls (reserve-rule and robust-pick burned), T18 and T19 the fixtures re-pinned to the new law, T20 the unknown-busy pin and the `set -u` guard in the faded sum.

## What it does not do

- It caps no count of agents, reads no memory per run, forecasts no cost from a command's name, and leaves a project's test layout, the clock rules of wave 35 and Lighthouse's own flags alone.
- The browser key is the command's first 60 characters, so a `cd <tree> ||` prefix fills it and every heavy command of one tree shares a cost line. Deferred.
- The linear fade under-counts a fresh run against the 1-minute load average, which is exponential: through the second minute it counts 63 to 87 percent. Deferred.
- The dial-down stops a writer whose detached runs and waiting asks live on, so the load may not fall on the stop. Deferred.
- A browser or compile run typed on the orchestrator's thread is booked and followed in the foreground, where a suite of that length is farmed out. Deferred.
