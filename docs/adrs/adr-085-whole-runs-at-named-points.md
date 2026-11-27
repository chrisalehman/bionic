---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 2
epic: epic-23-bionic-tech-debt
wave: wave-53-one-home
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
status: Proposed (Step 7, 2026-11-27)
created: 2026-11-22
---
# ADR-085 — Whole runs at named points

## Status

**Proposed** (Step 7, 2026-11-27). Drafted with the spec of wave 53 on 2026-11-22, before the build. Checked here against the settled head of the run, `5074682017bb`, and its two reviews. It amends ADR-065 in one respect, named under Decision.

## Context

ADR-065 set the landing method on 2026-10-19: each row runs the suites its brief names, and one run of every suite after the build finds the rest. The person rejected a second whole run, continuous runs, runs on spare capacity and the index of tests to files that night.

Wave 52 showed what the method costs on a long build. Eight suites stood red for hours because no row's landing set held them, and one was a defect a person met for about 20 hours. They were found by the one whole run and traced among 70 rows.

Wave 53 is larger and is mostly changes to the core libraries. The research measured a landing that derives its suites from the files it changed. The core libraries load one another, so a change to one reaches 55 to 125 of the 138 suites, and such a landing is nearly a whole run. The person ruled D3 on 2026-11-22: "D3: 3".

## Decision

A plan may name points in its build where every suite is run. A plan that names none runs as ADR-065 set it.

- A point is a test row of the plan, the kind the end-of-build run already has, whose task cell carries the tag ` · point`. Only a test row at Step 5 or earlier may carry it; the validator refuses it anywhere else. A point waits on the rows its deps cell names and on the plan's approval, never on every code row. The release order never takes a point for the regression row. A row that must not start before the point names it in its own deps.
- A point's run is `session-poker.sh regression-run --point <row>`. Its log is `point-run-<row>-<head>.log`, never a whole run's, and `proof-add point <log>` records it as a proof of its own kind. It is never the proof of the settled head: the run after the last build row is still owed there, and `proof-add regression` refuses a point's log.
- The refusals of a whole run while the build is open ask only the point's own rows. A whole run already running at the gate still refuses, and the full-pass refusal is not asked, since a point lands on its own run.
- The tick starts the first ready point that has no proof, and lands an open point whose proof stands, red or green. A red point's suites are owed to fix rows, never to the point. A fix row is born by the path a red of the end-of-build run takes (`task-add <id> --born regression:<suite>`, for a suite the point's proof owes), and its birth names the point and the rows it follows.

This amends ADR-065's "one whole run, never a second" for a plan that names points. Everything else of that night stands: no continuous run, no run on spare capacity, no index of tests to files.

## Consequences

- A break is found at the end of the set of rows that made it, and traced among those rows.
- The machine's gate admits a whole run only alone, so the build stands still while a point's run goes. On this run the first point took 3,862 s, about 64 minutes, for 138 suites. A plan pays that once per point, and sets how many it names.
- The plan's reader of waits, the release order, the validator, the scheduler's read of what holds a whole run, the whole-run verb, the proof verb and the tick each learn the mark. The gate does not. It admits a point's run as it admits any whole run, alone.
- A plan written before this release names no point and is read as before.

## What the build taught

- **The release that brings the mark cannot use it on itself.** The installed 2.2.0 tool read a marked row as a plain test row. Its tick would not start a point, and its write hook refused a point's id in a later row's deps, reading a test row in deps as a read cycle. So on this run the orchestrator started each point's run with the working branch's own copy of the tool. The rows behind each point waited on a placeholder token, replaced with no dependency once the point landed. The fix rows were added by hand. In 2.3.0 the validator admits a later row that names a point in its deps.
- **Both points found breaks, and the end-of-build run found none.** The first point, after the loader's sweep, ran 136 suites green and 2 red, and two fix rows cleared them. The second, after batch 1, ran 129 green and 11 red, and six fix rows cleared them. The whole run at the settled head `5074682017bb` ran 142 suites, all green.
- **The point's own machinery broke twice, and the points showed it.** The second point's log held one byte that is not a character, and the proof's reader stopped at it in a UTF-8 locale. It read the run as red with no suite named until it was run under `LC_ALL=C`. That reader is fixed in this release. Separately, the tick's detached run of a point sometimes left no proof. It inherited the tick's hold directory, and the tick removed that directory when it ended. The detach path now drops the hold before it starts the command.

## Alternatives rejected

- A landing that derives its suites from the files it changed: for a core library it is a whole run at every landing, about 35 minutes where a landing takes 4 to 10, and it needs the index the person deleted.
- The method unchanged: a build of about 100 rows learns at its end which row broke what.
- A new kind of row: about ten readers branch on a row's kind, and the kind the end-of-build run has already fits.
- A line in the plan's header naming the rows a run follows: it gives the point no state and no row for a later row to wait on, so writers would start and then stall at the gate for the length of the run.
