---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 7
epic: epic-23-bionic-tech-debt
wave: wave-51-gaps-closed
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
status: Proposed (Step 7, 2026-11-20)
created: 2026-11-19
---
# ADR-080 — The watch costs no turn

## Status

**Proposed** (Step 7, 2026-11-20). Written as built, then checked against the settled head of wave 51 and against what its walks drove. It rests on the person's rulings in wave 51's log, D4 and D12 (2026-11-18). It also rests on D9, the orchestrator's call to prototype the wake first (record/wave-51-gaps-closed/prototype-wake.md), and on the design's defaults D27 to D31 and D33, approved at the design card.

It supersedes the timed prompt of 2.0.0, the Patrol, which ran the tick on a clock through the session's scheduled jobs. It amends ADR-078's rule that whether a thing is alive is a rule about its process, by adding two such things: the watch and a running tick.

## Context

In 2.0.0 a timed prompt kept a run's session moving. Every twenty minutes the platform's scheduler typed a prompt into the session. The model took a turn, ran the tick, and acted on what the tick printed or said nothing. Each of those turns used the person's window and the person's spend, whether or not anything had changed. The clock kept firing while the run waited only on the person, who was away. The dispatch wall and the turn-end wall judged whether the session was watched by the age of the prompt's marker file, so a file's existence stood in for the fact.

The cost was in the carrier, not in the tick. The prototype of the wake (D9) measured four carriers on the installed platform:
- a background task, the Monitor tool and a plugin monitor each cost a model turn when they end, even on a clean exit;
- a hook registered to wake asynchronously sat ten minutes with no model request;
- that hook woke the session two to four seconds after a planted change;
- it ended with nothing shown on a normal exit, a kill and a timeout.

## Decision

**The run is watched by a shell process the platform starts on its own hooks; it runs the tick with no model, wakes the model only when the tick names an act, and ends itself when only the person can move the run.**

1. The watcher is `hooks/watch.sh`, registered in the plugin's own `hooks/hooks.json` on the turn end and on session start (sources startup, clear, resume and compact) (D12).
   - It is registered as a hook that can wake, with a time limit of one day. The platform starts it and does not wait for it.
   - It wakes the model by exiting with the wake code, with its one line on stderr as the model's message. Exit 0, a kill and the time limit end it with nothing shown.
   - It is the only process that exits with the wake code.
2. At most one watcher runs per session. Its record, `watch-<session>.state` in the project's tmp folder, is the lock: a second watcher, from the next turn end, finds the first alive and ends at once without a word. A session bionic never engaged gets no watcher and no record.
3. Each pass is one run of the whole tick with no model (`session-poker.sh tick --watch`). It lands rows, writes orders, opens asks and writes its digest, so every wall reads what it decided. The pass reads the tick's print and exits quiet, wake, rest or refused. A wake carries one ASCII line of at most 120 characters, naming the act and its subjects. An unchanged print wakes nothing, and a refused pass never wakes.
4. The kinds that wake are those that ask for an act of the model or of the person:
   - a denied reserved request;
   - a needed restart;
   - a goal;
   - a duplicate session;
   - a row gone;
   - an agent that reported or is quiet past its cadence or its duration;
   - a stand-down;
   - a row not landed;
   - a ready row with room;
   - a reconcile;
   - a bound plan that cannot be read;
   - a refused interval;
   - the merge of the run's pull request.

   Advice, what the tick did itself, and the quiet lines wake nothing.
5. A pass runs every five minutes by default. `watch-interval:` in `.bionic/config.yaml` sets it, and a value above twenty minutes is refused by a wake that names the fix (D33). The watcher sleeps the interval after each pass ends.
6. The watch rests when the run waits only on the person (D4). That holds when all of these do:
   - the tick decided nothing;
   - no row on the roster is open;
   - nothing is ready or filled;
   - no detached run is alive;
   - the run is not delivered;
   - its plan can be read;
   - no pull request is open;
   - at least one ask is open, and every open ask waits on the person.

   The watcher then exits silently. A run whose pull request is open does not rest: each pass fetches and stays quiet until the merge can be reached (D27).
7. The turn-end hook says the rest once, `bionic watch: stopped - waiting on you; your reply starts it again`, as a message the platform shows as one grey line under the reply. It has no error look and costs no model turn (D30). The end of the turn that the person's reply starts begins the next watcher, and nothing is typed to restore the watch.
8. A cause is told once for three kinds: a row quiet past its cadence or past its duration, a row gone, and the restart. A row quiet past its cadence is keyed by when it went quiet, so a row that writes and goes quiet again is a new cause. The causes told are kept on the watch record and carried across watchers, so a print that is in full because something else moved does not name them again. A row dispatched after the newest answer of the agent panel is not judged gone against that answer.
9. Near the end of its day, while an agent is out or the pull request is watched, the watcher wakes once so the turn's end starts a fresh one (D33). Otherwise it rests at its limit.
10. Whether the watch is alive is its record's process, judged by the one alive rule (D28).
    - The dispatch wall admits a dispatch while the watch is alive or rested on purpose, since the turn's end starts it again. It also admits one in the turn that engaged the session, whose end starts the first watch.
    - It refuses when a turn has ended since the session engaged and no watch record exists, or when the record says watching and its process is dead (D31).
    - The turn-end hook says a dead watcher once, in one line, and its end starts another.
    - A tick records its own process too, so a second tick of the session exits at once.
11. A turn-end refusal whose fix is the agent's goes out on the quiet channel as one fixed line, `bionic: a duty is owed; run session-poker.sh duty`, and `session-poker.sh duty` prints the whole reason (D29). A refusal whose fix is the person's keeps its channel, and wins when both arise at one turn end.
12. The timed prompt is deleted (D12), and nothing on a clock replaces it. Deleted with it:
    - its verbs, `prompt`, `arm` and `disarm`;
    - its marker and stamp;
    - the turn-end duty to run a tick, and the duty to list the scheduled jobs first;
    - every line of resume, the handoff, session start, the doctor and close-out that named it.

## Alternatives rejected

- **A background task, the Monitor tool or a plugin monitor as the watcher** (D12): the prototype showed each costs a model turn when it ends.
- **The timed prompt with a self-stop** (D12 option 2): it keeps a turn every twenty minutes while agents work. The design's Risks named it as the fallback if the hook could not register through the plugin's own file. The prototype on a scratch plugin showed that it can.
- **Both together** (D12 option 3): it keeps the noise to guard against a death the watch record already shows.
- **Stopping the watch after an idle hour** (the first form of D4): it costs an hour of turns nobody reads, where this design ends the watch as soon as only the person can move the run.
- **A hook on the person's prompt to restart the watch**: a new event, not proved able to wake, and the turn-end hook already runs at the end of the person's turn.

## Consequences

- A run that only waits puts nothing in the window and spends no model turn. A wake costs one turn, and only when the tick has named an act.
- The walk drove this at wave 51's head 358a2df9f, in two fresh sessions that loaded the checkout's hooks through a plugin folder of links:
  - **An hour of work.** With a writer at work for an hour, the session took no model turn. One watcher process held the record throughout.
  - **A rest on the person.** With the run waiting only on the person, the watch rested within two minutes of the turn end. In the next thirty minutes no watcher process was seen and no turn was taken.
  - **The reply.** The turn end after the person's reply started a watcher, which woke the session with a ready row. A dispatch was then admitted with nothing typed to restore the watch. The first two attempts were refused for their brief, not for the watch.
  - **The duty line.** A turn-end duty showed as one grey line with no error look.
  - **How a wake is drawn.** It showed as one line of hook feedback, and the model received its line as a hook's blocking error.
- The tick still costs the machine what it cost. A pass takes as long as a tick, and the watcher's period is the pass's own length plus the interval. On the copy of wave 50's record:
  - one tick with the integrate row open took 342.9 s at the release head, against a target of 120 s;
  - a tick over an unchanged digest cost as much, 343.5 s;
  - every timing target of the wave was missed (record/wave-51-gaps-closed/speed-after.md).

  On a copy of wave 51's own log a tick took 12.4 to 12.6 s.
- The dispatch wall, the turn-end wall, session start and the doctor read one record about the watch. Whether a session is watched is a process, not the age of a file.
- A session takes its hooks when it starts. One running at the upgrade keeps the 2.0.0 hooks until it is exited and started again; a `/clear` is not a restart. Until then a dispatch is refused as never watched, and the refusal names the command that starts a watcher by hand. A watcher started by hand through the shell's background mode is not the hook's carrier: each of its ends costs a turn.
- A scheduled job left from 2.0.0 fires a prompt whose verbs answer `unknown verb`; the person deletes it once.
- The turn-end duty still binds once: the agent is refused once and the next end of that turn passes.
- The tick runs in the hook's environment, which carries the project's root and the plugin's root. A whole regression the tick starts hands both to the project's regression command. This repository's runner and the plugin's suite library drop them; a project's own command does not.

## What it does not do

- Only three kinds of wake are said once: a row quiet past its cadence or its duration, a row gone, and the restart. The gate's, the fill's, the stand-down's and the others are named again on every full print. A print is in full whenever anything the tick hashes moves, the machine's load among them.
- Every stand-down wake says `met: TaskStop it, or keep it up with the hold verb`. It says this also for a writer whose work is not done, and for a stand-down made for the machine's load, which the hold verb refuses.
- A wake is not silent in the window. The platform shows one line of hook feedback for it, and the model receives the wake line as a hook's error. How a turn that the agent starts for itself is drawn is unchanged.
- The stop line was not seen in a live session. At the turn end where the walk's session came to rest, nothing was shown and the turn-end hook had no output, and the walk did not record which rest the watcher had read. The suite holds the line. At a later turn end in that session with a ready row, the turn-end duty the other session showed was not shown, and why was not read.
- The walk drove a session past an hour, on session start and turn end. These were not driven:
  - a full day under the time limit;
  - a plugin loaded from the plugin cache;
  - a session whose plugin root is the checkout itself;
  - the start sources clear, resume and compact;
  - a `/clear`;
  - a watcher inside a dispatched agent.
- A `/clear` writes a load record that reads as a fresh load in a process that reloaded nothing. So the restart line and the restart wake both go quiet at the first clear after a hook change.
- At its day's end the watcher counts an agent on the roster and an open pull request as still out. A detached run with no roster row open is not counted, so the watcher can rest at its limit with that run still going.
- A run delivered but still engaged wakes no model, and its watcher passes quietly until its day ends.
- A tick run by hand between two passes writes the digest the next pass compares against.
- It does not change the tick's own cost, which is a gate pass and more. While a pull request is open, each pass is a whole tick, and its cost grows with the run's record. The next costs of a gate pass are named in the 2.1.0 entry and were not cut.
