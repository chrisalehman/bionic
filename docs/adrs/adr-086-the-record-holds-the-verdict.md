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
# ADR-086 — The record holds the verdict

## Status

**Proposed** (Step 7, 2026-11-27). Drafted with the spec of wave 53 on 2026-11-22, before the build. Checked here against the settled head of the run, `5074682017bb`, its two reviews and its walk.

## Context

Claude Code shows the person a failed command whenever a shell command a session runs exits non-zero. The person reads that as a real problem and ruled on 2026-11-22: "I don't like seeing errors in the console", then D1, "include the tool's own exit codes in scope too".

The tool used exit codes as answers. A landing that must wait exited 75, a tick that names an agent exited 1, a check that says "not yet" exited 1. The tool also treats an exit as a verdict: the wrapper that runs a suite stamps the command's exit into the run's record, and a zero there is read as that suite green at that head.

Of wave 52's 122 failed commands, none was a command of the tool giving an ordinary answer. They were the model's own checks, test runs that were meant to fail, refusals and real failures.

## Decision

An exit code says one thing: whether the command did its work. What the work found is in the record and in what the command printed.

- A command that answers waiting, busy, nothing to do, not yet, or "no" to what it was asked exits 0, and its print stays as it was. Ten such answers changed, each listed in the 2.3.0 entry of `CHANGELOG.md` with what a caller reads instead. The list of ordinary answers is one table, `BIONIC_ORDINARY_TABLE` in `payload/scripts/lib/refuse.sh`. Every exit site maps its code through `refuse_ordinary_exit`, at the place the command exits, so a function's own return code is unchanged for a caller in the same shell.
- A command exits non-zero when something is wrong: a row returned for a red suite or a conflict, a stall, a refusal of what the caller gave it, a check that found a fault, a process that could not run.
- The wrapper stamps the suite's own result in the run's record, whatever it returns to the console. The stamp, the log's `rc=` line, the roster's `run_rc=` and the run line keep the command's own code.
- A run meant to fail is declared by the assignment `BIONIC_EXPECT=red` at the head of the suite command. The Bash wall reads it and hands the wrapper `--expect red`. The wrapper then exits 0 when the suite failed and 1 when it passed, and says which on one line. It inverts only when every suite segment of the command carries the word. Codes that are no verdict on a suite (2, 70, 71, 75, 124, 126, 127, and 128 and above) pass through unchanged.
- A command that ran nothing because the gate did not admit it exits 0. It says so by one line in a note file the caller names in `BIONIC_NOT_ADMITTED`. The two callers that had only the code, the tick's detached whole run and the wrapper's stamp, read that note, and the record writes 75 for a run that did not run.
- The watcher's wake keeps its code. It is a hook's exit to the platform, the one code the platform wakes a session on, and no session types it.
- Failed commands are counted by kind from the sessions' and agents' transcripts when the scorecard is drawn. One table of eight kinds, `SITREP_RED_TABLE` in `hooks/poker/sitrep.sh`, classes them, and the first matching row wins. It reads the ordinary answers from `BIONIC_ORDINARY_TABLE` and does not copy them.

## Consequences

- A script that branches on the old codes of these commands breaks. The release entry carries an upgrade note naming each one.
- A session can no longer take exit 0 to mean a suite passed. The print says what happened, and a landing proves itself by its own run of the suites, so a misreading cannot land a failure.
- The judge's closing line `judged <N> exit <rc>` keeps its code, so a caller that needs the step's verdict reads it in the words.
- The count depends on the platform's transcript format, as the reader of the person's typed words already does. A compound command is classed by its last segment, because the transcript does not say which part set the exit. One pass over this run's 138 transcripts, 213 MB, took about 3.0 s and is not cached, so the scorecard went from 5.7 s to 8.7 s.

## What the build taught

- **A newer door under an older wrapper can read green over nothing.** From the moment the working branch's suite door exited 0 for a run the gate did not admit, the installed 2.2.0 wrapper, which makes no note, could stamp such a run `rc=0`. Every proof stamped after that change had to be checked for a suite's own result lines, not only the stamp. The audit of the whole did that: all 560 landing verdicts and all 410 writer stamps of a suite run after the change hold the suite's own result, so none stands without a run behind it. The 2.3.0 wrapper writes and reads the note, so the gap lasts only while an older tool runs a newer door.
- **The rule cost words on the loaded pages.** The pages teach `BIONIC_EXPECT=red` and that a check expecting no match ends with `|| true`. To keep the pages every session loads at net zero, eight reason clauses were cut from the dispatch page and the blocks the role files are rendered from. Some named a model's default failure mode, such as a chain that goes on after a failed `cd`. The project's own rule for instruction files calls such sentences triggers, not elaboration. The person ruled that they go back before the release.
- **The count on this run's own sessions:** 304 failed commands. Refusal 75, killed 6, meant-to-fail 0, red-suite 96, ordinary 23, check 27, not-run 11, other 66. The 23 ordinary ones come from the installed 2.2.0 tool, which still exited non-zero for those answers. Meant-to-fail counts a declared run whose suite passed. A declared run that failed as declared exits 0 and is no failed command.
- **The walk met the meant-to-fail word and not the waiting answer.** Both writers in the walk ran a failing first run with the word. The wrapper printed `failed as declared (rc=1, kept in the record) — exit 0`, and every record kept 1. No landing in the walk had to wait for room, so the exit 0 of a waiting `ready` is held by the hermetic checks alone. Its count of 0 ordinary failed commands is no proof either, since a walk that met no ordinary answer reads 0 with or without the change. The walk also showed the count's edge. A stalled `ready` (exit 70) that the writer closes with `; echo "rc=$?"` leaves no failed command, because the Bash tool saw none.

## Alternatives rejected

- Two forms of each command, one that exits 0 for a session and one that keeps the code for a script: two contracts for one answer, which is the kind of copy this release removes.
- The answer as the first word of every print: most commands already print a stable word somewhere, and moving it would change prints for no reader.
- The callers reading the "not admitted" answer from each command's prose: each print words it differently, and one note file is one channel to read.
- The codes kept and the pages given a wrapper line: every page has to carry it, a session can still type the bare command, and the record would stamp the wrapper's zero as green.
- Counting failed commands in a hook: the hook the tool has is never told of a failed command, and the platform's event for it is unproven for a plugin and inside a dispatched agent.
- The rule for the model's own checks in the installed working principles: ruled out by the person as D4.
