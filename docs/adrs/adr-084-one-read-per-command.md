---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 7
epic: epic-23-bionic-tech-debt
wave: wave-52-driven-with-less
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
status: Proposed (Step 7, 2026-11-22)
created: 2026-11-20
---
# ADR-084 — One read per command

## Status

**Proposed** (Step 7, 2026-11-22). Drafted with the spec of wave 52, before the build, and checked here against the settled head of the run, `6d523e840da4`, the times measured on the copy of wave 50's record, and the reviews.

## Context

On a copy of wave 50's record (a log of 11,868 lines, a plan of 1.6 MB), at 2.1.0, the research timed the release card's preview at 526 s, one tick with the integrate row open at 458 s, one checked step advance at 79 s, and the commit wall at 53 s. The baseline the build was measured against, one run of each at 2.1.0's head with another suite on the machine, read 481.19 s, 454.33 s, 82.57 s and 55.62 s. The platform cancels the commit wall at its 10-second limit and admits the commit unjudged.

The necessary reading is about 1.5 seconds: one fold of the log 0.66 s, one parse of the plan 0.07 s, one read of its table under a second. The rest is repetition. The ledger check asks the status of each of 232 rows separately, and each ask parses the whole plan again: 44 to 49 s a pass, and a card runs two passes. The run's facts are asked four times at one head in one card, and inside each ask the log is folded 46 times. A card runs two whole gate passes for two steps.

The person ruled on 2026-11-20: one bound of 10 seconds for every command waited on (D1), held as a criterion, so that a miss holds the release unless the person waives that command by name (D2).

## Decision

**Within one command, each thing is read once.** One command is one process tree that holds one directory of its own: a verb of the session script, the commit wall, or the close's check. In it the run's log is folded once, and the folded facts are written as files into that directory. Every reader in every process of the command reads them by path. The plan is parsed once, and the status of every row is answered in one pass over the facts. Each answer that depends only on the plan, the facts and fixed commits is computed once for its key and served after that from the same directory. One gate pass serves every step a card asks about, with only the step-keyed checks run per step.

**The key is summed once, and moves only when the log may have.** The facts' key is the log's checksum together with a sum of the reader's libraries. The log is summed at the command's first ask, at the first ask after the command itself appends, and at the entry of each judgment. An ask between those compares one line of the directory with the key its shell holds, starts no process and sums nothing. The libraries are summed once a process, and a process whose libraries differ from those that made the fold folds for itself. The directory is removed when the command ends, so a decision never reads a file kept from an earlier command. A command bionic does not own is started with no hold: the test runner, the landing's suites and the project's release check.

**One change of behaviour follows.** A line written to the log from outside the command, such as another session's stop event during a tick, is seen at the command's own next append or at its next judgment, not at its next ask. A judgment still folds the log as it stands when it begins. The release notes tell a person upgrading.

**Counts pin it, and a clock confirms it.** The libraries count their whole-log reads, folds, sums, plan parses, status passes, facts answers, derived answers and gate passes when asked to. A suite holds each command to its count on a fixture of two sizes, where the counts must be equal. The bound itself is timed once for the release: the median of three runs on the copy of wave 50's record, on a quiet machine.

**The watcher's pass asks one question.** While a pull request is open the pass reads the request's state, and runs the tick only when what the tick reads has changed.

## Consequences

- The commit wall folds once where it folded five times, and took 5.61 s, inside its registration, so a commit on a large record is judged.
- The six slow commands take from a seventeenth to about a tenth of their 2.1.0 time, and seven commands are still over the bound. Medians of three: `resume` 43.31 s, the watcher's first pass 33.79 s, the tick 32.42 s, the release card's preview 29.02 s, the close's check 19.31 s, `ready` before its suites 16.45 s, the situation report 11.63 s. The person waived each of them by name (D36, "D36: 1"). The watcher's later passes take 1.84 s. What the seven spend their 11.63 to 43.31 seconds on, by function, was not profiled again.
- A change that reads twice turns a suite red without a clock.
- Nothing is kept between commands, so nothing has to be invalidated.
- The key covers the reader's libraries, not the code that derives an answer from the facts. A process from another copy that shares the reader's libraries is served this copy's derived answers. The only route left to that is a project's declared regression command, which is still started holding the hold, as is the whole run the tick starts by itself. Both are stated in the release's Known limits.

## Alternatives considered

- A kept fold on disk: it exists, every turn's stop event evicts it, and the cost was never one fold but hundreds inside one command.
- The folded facts handed to each child as a string: the first build did this, and a command still sent them 21 to 125 times. Files read by path cost no process and no copy.
- A resident process that holds the run's state: a new lifecycle to manage, for reads that cost a second and a half.
- Two bounds, or targets recorded and carried: put to the person and not chosen. 2.1.0 recorded four targets and missed all four.
