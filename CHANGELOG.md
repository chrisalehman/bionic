# Changelog

Earlier releases are recorded as git tags (`v1.4.3` … `v1.8.3`) rather than in this file,
which starts at 1.8.4.

Versioning follows semver from 1.9.0 on:
- **MAJOR** for a change that breaks a documented contract a user or project already relies
  on: a removed verb or field, a `canonical_sdlc_version` bump, an artifact a user must migrate.
- **MINOR** for new capability or a behaviour a user notices, including a newly refused action
  or an upgrade step.
- **PATCH** for a fix within existing behaviour.

## 1.9.0 — 2026-10-03

A quieter terminal that is right the first time. The Patrol asks a question once and then keeps
quiet until something changes, the hooks answer large commands well inside their time limit, and
when bionic does refuse an action it prints the line that fixes it. This is a minor release: it
adds verbs and one newly refused action (writing Claude Code's memory store), and nothing a
project already relies on is removed.

What you will notice:

- **A quieter Patrol, and `hold`.** When you decide an idle agent should keep running, say so
  once: `session-poker.sh hold <name> <reason>` records the decision on the agent's roster row.
  While nothing about that agent changes, the tick writes no stop order and prints one
  `held <name> since <at> — <reason>` line instead. A new message from the agent, a rewritten
  deliverable or a relaunch cancels the hold on its own. A `fill-declined:` answer now stands
  until a new task becomes ready or the plan's step moves, and the tick prints the standing
  answer. Both kinds of decline need a reason. A tick with nothing new prints a single
  `unchanged since <at>` line and owes no task-list refresh, a stand-down shows in the band as
  `STANDDOWN` rather than QUIET, and a Patrol started with an older prompt is told once to
  re-arm. Only the orchestrator can hold: a subagent's `hold` is refused.
- **Done means the agent said so.** An agent is counted finished only when its deliverable exists
  AND it has signalled completion since launch: a message that names the deliverable, a completed
  task notification, or the `Done marker:` file its brief names. A mid-task question no longer
  gets an agent stopped because its output file already exists. Briefs gain an optional
  `Done marker:` line for agents that report by file.
- **Hooks no longer time out on large commands.** The Bash and governing-skill hooks now read a
  command once, in one pass, instead of re-scanning it per check. Commands of 64 KB (long
  heredocs, quoted `python3 -c` bodies, a command behind a `cd`) are judged in under two seconds
  under both macOS `/bin/bash` 3.2 and current bash, where some used to run past the hook's limit
  and pass unchecked. A timed suite (`tests/hook-timeout.test.sh`) holds that line
  under both shells. The impact check the dispatch wall runs now skips nested worktrees and
  `.bionic`, so it answers in seconds at a project root holding several worktrees.
- **Every refusal prints a fix you can paste.** Each refusal site in the Bash walls, the stop
  wall, the dispatch wall and the stop guard (99 of them, listed in
  `tests/fixtures/refusal-inventory.md`) ends with the command or line that resolves it, or says
  why there is none. A landing
  refused for touching a file outside the brief prints the `amend … --files+` line, quoted so it
  survives a path with spaces, and a refused dispatch names its real cause once, with the roster
  rows it counted and the command that closes each.
- **The memory-store wall.** In a session engaged with a bionic run, writing into Claude Code's
  per-project memory store (`<claude home>/projects/*/memory/`) is refused, whether by Write, Edit
  or a shell redirect, `tee`, `sed -i`, `cp`/`mv`, `touch`, `mkdir` or `ln`, under every spelling
  of the home directory. The refusal says where that content belongs instead: the run's
  assumptions file or a rule proposal. Reading, listing and deleting still pass, and a session
  not engaged with a run is never refused.
- **Plan rows by command.** Five new `session-poker.sh` verbs edit the plan in place through the
  same safe write the task-add verb uses: `task-set <id> <column>=<value>…` changes those cells
  only, `step-line <N> <text> [--append]` writes a step's evidence line, `current <N>` moves the
  plan's step (and refuses 9, naming close-out), and `ledger-add` and `ledger-set` add and amend
  dispatch-ledger rows. A bad column, id or value, or an edit that raced another, is refused with
  the plan untouched. The canonical-sdlc step files now name these verbs where they used to
  describe a hand edit.
- **The brief advisory.** A dispatch brief whose body tells the agent to run a suite its
  `Suites:` and `Re-executes:` lines do not declare, or to edit a path outside its `Files:` line,
  draws an advisory naming the line to add. It never blocks the dispatch. Text inside
  `Read first:`, a code block or a "never" line is not read as an instruction.
- **A truthful version line.** On a plugin installed from GitHub, where the plugin directory has
  no `.git`, `/bionic:version` and doctor's header now print the commit recorded by Claude Code's
  plugin registry and say `github feed`, where they used to print `unknown` or call it another
  checkout. With no commit recorded the answer is `unknown`, never a guess.

Fixes:

- Fewer false refusals. Read-only agents (researcher, test-runner, auditor, critic) no longer
  count against the writer budget, and every test-runner counts against the suite budget. Not
  read as backgrounded: `a & b & wait`. Not read as a suite run: `tests/run.sh --dry-run`, `-h`,
  `--help` or `--list`, a glued input redirect from a suite file, or a script named `run.sh`
  outside the project's `tests/`. A `&&` inside a quoted commit message or notification command
  no longer draws the chain note, and stopping a background shell by its id passes the stop guard.
- The suite budget reads a `for` loop over a literal word list, and a variable holding a whole
  suite name, as the suites they run, so the right loop passes and the wrong one is refused by
  name.
- Bionic's dispatch rules reach a named teammate at start, as they already reached a subagent,
  and every role file carries the suite-spelling rule inline.
- The stop wall counts open writers the same way the tick and the dispatch wall do.
- Close-out writes an epic's wave row only into the shipped-waves table, even when the planned
  table above it lists the same wave (the limit 1.8.10 carried), and fills the row's ADR cell from
  the wave spec.
- `ledger-add` checks its id as well as its values, so an id carrying a newline can no longer
  write a forged plan line, and the plan-row verbs accept plain ASCII ids only, under any locale;
  a hold with a blank reason is refused; the fix lines this release touched print the plugin path
  quoted.
- The doctor-reads suite no longer depends on the `claude` and `npm` found on the runner's PATH.
- The Bash walls read `git` in any letter case. On macOS's case-blind filesystem `GIT push origin
  main` runs git, and it used to pass the protected-branch wall, the commit gate and the read-only
  role check unseen; `GIT`, `Git` and `/usr/bin/GIT` are now read exactly as `git`.

Known limits, carried to the next release:

- The memory-store wall does not see every way to write a file: `rsync`, `dd of=`, `tar x -C`, a
  symlinked path, process substitution, `cd -` into the store, and a write from inside an
  interpreter such as `python3 -c` all pass. When `BIONIC_CLAUDE_HOME` and `CLAUDE_CONFIG_DIR`
  name different homes, only the one that takes precedence is guarded.
- A very large command (about 200 KB), quoted or not, can still take over ten seconds through the
  Bash hook under `/bin/bash` 3.2, past the hook's limit, so the walls do not judge it. Commands up
  to 64 KB are inside the limit on the shapes the timed suite holds.
- Five older fix lines (in the stop wall, the stop guard and the dispatch wall) still print the
  plugin path unquoted, so they break when pasted from a plugin path containing a space.
- `bash run.sh` after a `cd` still reads as the full suite run.
- A `Done marker:` file must be strictly newer than the agent's launch, while a completion message
  sent in the same second counts.
- A refused `spawn-worktree.sh land` can remove the worktree's `.bionic` link before it refuses.
- Verification Matrix rows and Step-5 floor fields have no verbs yet and are still edited by hand.

One rule for a Patrol answer (ADR-041): an answer stands until the facts it answered change, the
tick prints every answer it honours, and an agent is done only when it says so. It amends
ADR-036's one-turn decline and reverses ADR-037's rejection of a decline kept on disk, because the
tick now reports what it holds.

## 1.8.10 — 2026-10-03

A session bound to no plan is now told so and left alone by every gate that acts on a plan,
engagement never hands a session a run another live session holds, and bionic owns the switch
that keeps Claude Code's auto-memory off: nothing bionic ships or commits cites a memory note
as the reason for a rule.

- REQ-1: An unbound session's `fallback <plan>` is announced and never acted on. Eight
  consumers print the one advisory `run_unbound_advisory` builds in `payload/scripts/lib/run.sh`,
  once per process, and take their `none` path: context-spend, the landing guard, the
  patrol-duties gate, the fill gate and patrol-revive in `payload/scripts/lib/stop.sh`, the
  dispatch wall in `hooks/dispatch-preflight.sh`, the commit gate in `walls.sh`, and the Patrol
  tick, which now names no FILL row from another session's plan. A writer dispatched from an
  unbound session is refused with `this session is bound to no run`; read-only roles pass, and
  a root with no open run is judged as in 1.8.9. The poker's other verbs and the
  governing-skill hook are unchanged. Tests: `tests/stop.test.sh` §UB (two plans, two sessions:
  the unbound one exits clean, the bound one is still refused `not launched: T5`),
  `tests/cross-gate-agreement.test.sh` §UB (seven gate arms, advisories byte-equal, and UB.8
  for the tick against its bound control), `tests/docs-pins.test.sh` §UB; the suites whose
  fixtures leaned on `fallback` now bind through `tests/lib/bound-marker.sh`.
- REQ-1, engagement: A session auto-binds only at its first engagement, and never to a run
  another live session is bound to. Such a session is written unbound and told why on the
  model's channel (`hookSpecificOutput.additionalContext`), naming the holder; a re-engagement
  keeps whatever binding the marker has, so a session left unbound binds by hand
  (`session-poker.sh bind`) or by writing its own plan. One behaviour changes for every session:
  one whose first engagement found zero or several live runs stays unbound when the root later
  drops to one. On resume and compaction, session-start's one-run line for an engaged unbound
  session gives the bind command and, when a live session holds the run, names it first
  (`hooks/engage.sh`, `bind_holders` in `payload/scripts/lib/binding.sh`,
  `hooks/session-start.sh`; `tests/engage.test.sh` E12–E13, `tests/session-start.test.sh`
  §15.6–15.12).
- REQ-1, close-out: `close-out.sh` binds its synthetic session to the plan being closed, so its
  gate dry-run judges that plan instead of passing an unbound commit, and `run` dry-runs after
  the Step-8 block is written and before `current: 9` and `delivered:`, so the gate reads an
  open plan's evidence. `run` now asks that gate, the census and the merge check BEFORE its first
  destructive act, and refuses before touching anything when the plan has no `Step 9:` line in
  `## SDLC State` or the epic plan has no `| wave |` table; `check` prints each as a `presence:`
  line beside the gate's own. A refusal exits 2 with branch, tmp, continuation and `current:`
  unchanged (`tests/close-out.test.sh` 4e, 4k–4q, 4u–4x and 4e q1.1–q1.14). Known, carried to
  the next wave's first row: the "epic already lists this wave" exemption matches a `| NN |` row
  in any table of `epic.plan.md`, so a wave listed only in the planned table closes without its
  shipped row being written (quiet omission, nothing destroyed; present since before 1.8.9).
- REQ-2: `CLAUDE_CODE_DISABLE_AUTO_MEMORY` joins `ENV_KEYS` in `payload/scripts/lib/env.sh`
  with default `1`, so setup writes it into the user `settings.json` `env` object and remove
  deletes it. A lower settings scope can still set it back; doctor says so. `remove.sh`'s
  `RM_ENV_KEYS` is pinned byte-equal to `ENV_KEYS` (`tests/env.test.sh` Group 1), and `env`,
  `fresh-home`, `doctor-reads` §18 and `command-relay` now encode four keys.
- REQ-3: Doctor's rows about this project now print under a `PROJECT` header, and among them is
  the new `auto-memory` row (`detect_auto_memory` in `detect.sh`, the row in `checks.sh`). It
  reads ✗ when the project's `.claude/settings.local.json` or `.claude/settings.json` sets the
  key to a value the CLI reads as memory on (anything but `1`, `true`, `yes` or `on`, case and
  surrounding spaces ignored), or when `~/.claude/projects/<slug>/memory/` holds files. Its hint
  names the file and key or the directory to clear by hand, never `→ /bionic:setup`. Its ✓ says
  what it checked: no override in project settings, no memory files under the slug. Managed
  settings, `--settings` and the launch environment are outside what it reads. The key unwritten
  shows on the ordinary `env:CLAUDE_CODE_DISABLE_AUTO_MEMORY` row (`tests/detect-probes.test.sh`
  Group 6e and its value cases, `tests/doctor-reads.test.sh` §20, and §DS DS.2a and DS.10b in
  the agreement suite).
- REQ-4: A reason cited from one site is written at that site (`units.sh`, `stop.sh`,
  `session-poker.sh`); a reason cited from many lives in one file, the new "Fixture fidelity"
  and "Anti-vacuity" rules in `.claude/rules/test-harness.md`, and the task-tools census in
  `env.sh`. `operational-rules.md` and `agent-discipline.md` read as decided, the four rules
  files' provenance lines cite ADR-002 rather than `.bionic/memory/`, and `remove.sh` no longer
  says `.bionic/` holds memory. `tests/docs-pins.test.sh` §RH pins each landing three ways (live,
  carried phrase removed, retired phrase planted), and a grep for a memory citation over
  everything bionic ships or commits prints nothing. The landed rules themselves are pinned:
  `tests/docs-pins.test.sh` §D2 reads each 1.8.10 landing in the repo `CLAUDE.md`, the
  `.claude/rules/` files, the orchestrator-dispatch block and the test-runner template, and goes
  red when one is removed.
- REQ-5: The store's 215 notes were triaged, and the 49 owned by a repo file met a wall-first
  bar: 34 landed as text plus the card's decision-format rule (repo `CLAUDE.md`, three
  `.claude/rules/` files, the new `.claude/rules/plan-authoring.md`, the orchestrator-dispatch
  block, the test-runner template), 5 were already said, 2 were declined (one because the role
  files' byte cap left no room), and the 8 a hook can enforce are carried over as six walls to
  build. Always-loaded bytes read 61,089 against 59,984 at 1.8.9, with the six role files at
  26,205 of 26,400 (61,087 at the final head). The 33 notes owned by the user's global CLAUDE.md
  are proposed text, applied only by the user.

One rule for what a session knows (ADR-040): four channels, each reviewed before it loads, and
no fifth; a lesson becomes a hook when one can enforce it, committed text when only a person
can, or nothing. The design named six acting gates; the build found the commit gate as the
seventh (Δ1), review found the Patrol tick as the eighth (Δ2), and the critic found close-out's
dry-run (Δ3) and engagement's sole-run bind (Δ4, Δ5); doctrine now says a first engagement
binds a sole live run no live session holds (Δ6).

## 1.8.9 — 2026-10-01

A contract widened with `amend` or `extend` is now the contract every wall reads, on a
teammate's roster as on an async one, and every `Re-executes:` line of a brief counts.

- REQ-1: The row `amend` or `extend` writes now carries the agent's latest identified self:
  its `status=`, `agent_id=` and `teammate_id=` come from the name's latest row that carries
  an id within the same dispatch cycle, so a teammate whose latest row is the recorder's
  id-less `confirmed` row is no longer widened invisibly. The suite-budget wall's pick for an
  id is one function, `roster_row_for_id` in `payload/scripts/lib/roster.sh`, called by the
  budget and commit-role arms in `walls.sh`, and `poker: amended` checks itself against it:
  the success line prints only when the wall's pick is the new row, otherwise one line names
  the row the wall reads and the verb exits 1; before the agent is identified it says the
  walls read the row once the agent is. The six comments that stated the old premise cite
  the one rule. Agreement tests: `tests/cross-gate-agreement.test.sh` §AM1–AM4 and AM6
  (amend, then the budget arm, a restart, the stop wall, `observe` and the tick fed one roster),
  `tests/roster.test.sh` R11–R12 and `tests/session-poker.test.sh` §29–§30.
- REQ-1, restarts: A restart after the orchestrator has acked a landing now re-identifies
  from the id's latest started row, so the amended run survives it, and keeps the teammate's
  `teammate_id` when that row has none (`hooks/execution-recorder.sh`; §AM5 and AM5b and the
  recorder suite's restart-after-ack cases). A plain restart's `duplicate-start` row copies
  the amended row as before. This closes the carry-over for async agents too.
- REQ-2: Dispatch lifts the union of every `Re-executes:` line's runs onto the roster row,
  de-duplicated in order, and the three-run cap counts across lines. A line inside a ``` or
  ~~~ fence (only its own character closes it) or an indented code block is an example and is
  not lifted. In a brief whose fences do not balance, or whose every `Re-executes:` line sits
  in a code block, every such line is read as a declaration, so a fenced example may lift
  beside the real runs. That trade is accepted: an over-admitted run shows on the roster row
  and can refuse the brief, while a dropped real run shows nowhere. A single multi-run line
  reads as in 1.8.8 (`payload/scripts/lib/brief.sh` `allhits`; the brief-lib cases in
  `tests/dispatch-preflight.test.sh`).
- REQ-3: A brief with runs, no `Suites:` and no impact command configured is refused with
  the fix `Suites: none beside Re-executes:`, 98 columns so the refusal fits its own cap, on the one-line refusal and first among the
  Fix blocks; a brief with no runs is refused as in 1.8.8 (`brief.sh`; the one-fault and
  two-fault gate cases in `tests/dispatch-preflight.test.sh`).
- REQ-4: When a declared run is too long for the budget refusal's line, the count reads
  `N declared run(s) (printed below)`, not `N run(s)`; the full command still prints after
  `On the budget:`, and a refusal whose run fits is unchanged (`walls.sh` `_budget_wire_list`;
  `tests/bash-walls.test.sh` §15).

One rule for a successor row (ADR-039): the identity is cycle-scoped, so a re-dispatched
name never inherits the previous agent's id (Δ1), and the recorder changes one line where
the design had left it untouched (D4 Δ2), because the `identified` successor was skipped by
the restart-after-ack name join.

## 1.8.8 — 2026-10-01

- REQ-1: The cron-ritual stop gate now blocks once and is discharged by the next
  `CronList`, whichever side of a `CronCreate` it falls on: a `CronCreate` with no
  `CronList` since the latest clear or resume marker still blocks, and the refusal's third
  step says `CronCreate` is needed only if the list left the session with no Patrol job of
  its own. The ritual text is one sentence true on the first Stop and on every later one.
  The skill's fresh-run arming instruction names `CronList` before `CronCreate`, in
  `dispatch.md` and its source block, and so does dispatch preflight's never-armed fix text.
- REQ-2: `session-start` now prints one `re-arm:` line on every engaged start, with or
  without predecessor state, whose tick and arm commands carry the hook's own resolved
  directory, so the root a session bakes into its Patrol is the root its hooks run from.
  `dispatch.md` directs the model to that line for `<plugin-root>` and no longer directs a
  registry read, and `/bionic:doctor` reports, naming both paths, when the registry root's
  `session-poker.sh` differs from the running hook root's.
- REQ-3: A `deps` cell may carry an external prerequisite token `ext:<slug>` beside task
  ids, and the plan validator admits it, refusing any token with a blank inside it. A
  pending row with an unsatisfied token is not in the ready set, so the fill wall passes a
  turn with a free slot and such a row without a decline line, and the tick names every
  held row on a `poker: HELD <id> ext:<slug>` line of its own. Removing the token returns
  the row to the ready set on the next read, and a decline line lasts one turn. The tick
  reads the plan table once per tick instead of four times.
- REQ-4: One library reader now produces every ledger finding — a status outside the
  scale's enum, a terminal row with no evidence line, an active row whose agent matches no
  roster row — and the tick prints each as a `poker: LEDGER <id> <finding>` line, before a
  subagent's commit finds it. The tick prints the HELD and LEDGER report in every state
  that decides a tick, once, including the disarm tick and the no-fill arms. The commit
  gate reads the roster, so an active row whose agent cell names a roster row commits with
  no `- T<n>:` line, and with no roster an agent-named row still needs one. The skill says
  task-scale ledgers have no write-time check.
- REQ-5: `adopt` now prints, per adopted row, one `budget:` line giving its suites and
  runs, or `none`. A suite-run refusal names the verb that widens the budget, `session-poker.sh
  amend <name> --reexec+ '<cmd>' --reason <why>`, using `--suites+ <suite>` when the
  refused command is a suite file, with the row name quoted as the roster carries it, so
  the line can be pasted as it stands. A row widened by `amend --reexec+` admits the named
  run on its next attempt.
- REQ-6: A `Re-executes:` run carrying an unfilled placeholder glued into a path is now
  refused as an unfilled placeholder, never as a redirection, and a brief whose only
  instrument was refused at the lift is refused for that instrument, never for having no
  `Files:` and no `Suites:`. The scaffold's `Files:` comment says a read-only brief omits
  it and keeps its other fields.
- REQ-7: A CI or PR wait is now a backgrounded command with a declared `Subprocess claim:
  <process pattern>`, named in the skill's Liveness paragraph and carried as an optional
  scaffold line. An undelivered row with a backdated transcript and a live claimed process
  ticks QUIET rather than NOTIFY, while a dead claim still notifies.
- REQ-8: The farm-out chain exemption now reads read-only chains as cheap and write chains
  as not. A chain of `git fetch`, `git rev-parse`, `date`, `gh pr view` and the like draws
  no nudge, while a chain that ends in `rm`, `mv`, `cp`, `mkdir` or `touch`, a `gh` verb
  other than `view` or `list`, or a non-GET `gh api` does. Each chain is split at every
  unquoted `|`, `;` and `&` and each command judged on its own, a redirect or pipe that
  writes a file counts as a write, and `sort` or `uniq` with an output flag or extra
  operands is not an observation.
- REQ-9: A commit refusal whose refused command also edits the bound plan now leads with a
  line saying so, because the gate read the plan at call start and the edit is not yet
  there; a commit whose command does not name the plan carries no such line. The line leads
  in every arm of the gate, not only the matrix arm.

Two views of one scaffold (ADR-038): the six role files now carry a reader view of the
brief scaffold, one clause per label, while `dispatch.md` and `SKILL.md` carry the author
template, and the two label sets are pinned equal. The role files shrink from 27060 to
26040 B under the unchanged 26400 B cap.

Migration for plans in flight: from 1.8.8 a task row's agent cell is the roster name the
dispatch gave the agent, not the role, and a row still carrying a role is refused by the
gate as naming no launched agent.

## 1.8.7 — 2026-09-24

- REQ-1: A task branch now lands onto the branch the bound plan names as its working
  branch, in whichever checkout has that branch checked out, whatever branch the main
  checkout happens to be on; a land with no bound plan, no readable working branch, or a
  working branch checked out nowhere is refused by name and merges nothing, and
  `stop-orders.sh standdown` lands through the same path, naming what it merged into.
  The busy check that holds a land back now reads where a suite is actually running —
  the process, not which session started it — so a land is no longer refused by an
  unrelated session's activity, and is no longer waved through by a suite the landing
  session itself is running.
- REQ-2: The commit gate now refuses a commit in a session bound to a plan that exists
  but cannot be read, naming the path; a bound plan that no longer exists still reads as
  closed, as before. The stop wall, dispatch preflight, the tick and the governing-skill
  hook all give an unreadable bound plan this same answer, instead of the "no open run"
  or "bound plan closed" some of them used to report for it.
- REQ-3: The evidence gate now reads `env`-prefixed git invocations, including `env -C
  <dir>` and `env --chdir=<dir>`, as the commit they perform, judged exactly as the
  un-prefixed form is. The read-only role arm refuses every git subcommand that creates
  a commit or moves a branch onto one, in every spelling the gate reads, while a writer
  role's ordinary merges are unaffected.
- REQ-4: A main-thread verb can now amend a live row's files, suites and re-execute
  budget, recording who changed it, when and why beside the row, and both the stop wall
  and the budget wall read the amended contract from then on; the verb refuses a call
  made from inside a subagent, an unknown name, or a closed row, and never touches the
  row's launch time, status or agent id. A message sent to a writer whose row already
  reports done puts that row back in flight, so the tick no longer stands it down before
  it reports again. A follow-up's reply closes the row on either reply shape the agent
  may send, and never reopens a row that was already acknowledged or stopped. `extend`'s
  reason is stored as plain data and no longer changes what any process-liveness check
  matches, and a stand-down deferred on a stale panel now names every row it deferred.
- REQ-5: Once a plan is past its Step-3 approval, a task is ready the moment it is
  pending and every prerequisite has landed, whatever step it belongs to; the tick's
  fill duty and the stop wall's fill duty both read this one ready set. The plan
  validator now requires every row at Step 5 or later to depend, directly or
  transitively, on every Step-4 row, reporting one line per offending row. A
  documentation row at Step 7 or later now waits for its own step to open — the release
  row can no longer be filled early, during Verify — and a main-thread verb adds a new
  row to the task table together with its evidence line and its prerequisites in a
  single act. Every turn of an engaged run appends one line to a fill ledger recording
  the free slots, the ready task ids, the agents actually launched, and any withheld or
  declined task with its reason; a report can read that ledger back as
  missed-opportunity minutes, and a fill refusal now states its counts and names the
  specific rows it could not launch.
- REQ-6: `session-poker.sh prompt` now prints the canonical Patrol prompt carrying both
  the marker and the tick command, and the session-start guidance points to it. A
  Patrol-marker turn that never ran the tick is refused once, naming the tick command,
  and Patrol's health is now judged by its last tick rather than its last marker turn,
  so a clock that fires without ticking reads as dead to both the death notice and the
  dispatch arming wall.
- REQ-7: A budgeted suite command is now admitted the same way whether or not it is
  followed by an output redirection or a `tee`, for every runner and for budgets
  declared only under a re-executes line. The cap of three re-executions now applies to
  the auditor role alone, with every other role bounded only by the field's own length
  limit, and every suite-wall refusal now suggests only spellings the wall itself
  admits, so running a refusal's own suggested remedy is no longer refused in turn.
- REQ-8: `stop-check.sh` and the stop guard now read the newest of an adopted agent's
  candidate transcripts — the launcher's and every adopter's — the same file the tick
  reads, so an adopted agent whose adopter holds the fresher copy is no longer reported
  idle against a frozen launcher transcript. After an adoption and a resume by name, the
  tick's liveness for that row now follows the file the agent is actually writing.
- REQ-9: Before Step-3 approval, only the read-only roles may dispatch; every other type
  — including a fork, a general-purpose agent, a bare `claude` invocation, or any
  unrecognized type — takes the writer path and is refused. A dispatch made from inside
  a subagent writes no row to the orchestrator's own roster, and delegation is one level
  deep: a nested dispatch may only launch a read-only role, a read-only role can never
  call the Agent tool itself, and a nested read-only helper remains bound by the commit
  wall even when it holds no roster row of its own. A dispatch refused for a missing
  scaffold now says plainly that the wall reads only the prompt text, and that the
  brief's scaffold must be copied into it.
- REQ-10: Dispatch preflight, the sweeper and the stop wall now close a name through one
  shared predicate — an acknowledgment later than the row's launch — instead of
  disagreeing on a MET marker without an ack. The governing-skill hook, the stop wall,
  the tick and dispatch preflight all read the writer budget through that same one
  strict reader, which refuses a `parallel-budget:` line whose `writers=` value is not a
  plain positive integer where the plan is read, rather than guessing at it downstream,
  and preflight prints the named backstop when a live plan carries no budget line at
  all. A restarted agent now re-occupies its existing slot without resetting the
  contract's original launch time, so occupancy and liveness checks see one continuous
  history across the restart instead of a fresh one.

## 1.8.6 — 2026-09-23

- REQ-1: A stop closes its own roster row — the tick acks a MET row once a fresh panel
  shows its agent gone, `stop-orders.sh stopped <name>` closes a row through the same
  sweeper path, and `standdown` drops a row only when it is acked and gone from a fresh
  panel; an abandoned tree still stands.
- REQ-2: `adopt` and the tick read an adopted agent's transcript against this session's
  own subagents dir first, falling back to the launching session's; the adopt report
  says the same.
- REQ-3: The writer budget is a measurement every plan carries — a `*.plan.md` Write
  without a readable `parallel-budget: writers=N` is refused where the plan is written,
  per Chris's Option 3 ruling.
- REQ-4: The stop wall's fill arm honours a tick's `fill withheld — HOLD` or
  `… EMERGENCY` line, anchored at line start; every other tick turn is judged against
  the wall's own ready set.
- REQ-5: The tick and the stop wall count occupancy from one source — every roster row
  of this session not yet acked; a gone UNMET row is named `poker: GONE <name>`.
- REQ-6: `current:` is read by one delegating body, and a Stop parses the ledger and the
  task table once each instead of twice.
- REQ-7: Every dispatch-preflight refusal takes the same exit status regardless of how
  many faults a brief carries.
- REQ-8: A read-only role's `git commit` — test-runner, researcher, auditor, or critic —
  is refused by name; other roles are untouched.
- REQ-9: The evidence gate's jurisdiction ends at the engaged repository — a scratch or
  nested-repo commit is admitted, judged only against an exact allow-list of placeable
  `-C`/`cd` shapes, with quote- and backslash-split spellings still caught.
- REQ-10: The impact command maps a template edit to its rendered file's suites, so a
  shared-block change reaches every consumer.
- REQ-11/REQ-12: The Step-3 plan template renders one `- T<n>:` evidence stub per task
  row, and its scaffold text is trimmed to what the card actually emits.
- REQ-13: §S13.4 distinguishes a row-assembling file from a presence test, and anchors
  every docs-pins doctoring site added since.

## 1.8.5 — 2026-09-22

- REQ-1: `done` is the one terminal word at every scale; the rigor-lane verdict arms are
  step-gated (numeric `current:` ≥ 6), so a finished task-scale row is not refused for
  verdicts that cannot exist yet.
- REQ-2: The PostToolUse bind arm names every exit, resolves the plan against the session's
  own root, and `bind_plan` names which refusal fired.
- REQ-3: Readiness is computed once, in `lib/fill.sh`, and read by the tick, the stop
  library's fill duty and the card; a turn past Step 3 that ends with a fillable gap is
  refused once, tick or no tick.
- REQ-4: The card reads `scale:`; a task-scale ledger renders under its own headings, the
  floor line comes from `impact-command:`, `step2` accepts a task-scale plan, and batch
  widths are printed per dependency depth.
- REQ-5: Step 0's budget recipe is the two-call form the library implements.
- REQ-6: The brief scaffold's `Suites:` line says which shapes count.
- REQ-7: A quoted pipe in a declared run is an argument, not plumbing; the roster stores
  `re_executes` percent-encoded and every reader decodes once.
- REQ-8: An over-cap `Re-executes:` brief is refused naming the dropped run.
- REQ-9: A matrix `evidence:` cell tolerates a trailing ` — <note>`.
- REQ-10: `session-poker.sh extend <name> <reason>` re-opens a MET roster row.
- REQ-11: A substituted step is not a pointer step: a commit from a task row's tree is judged
  by that row's arms whatever `use_worktree` says; the task-scale subject fork.

### Fixes found in verification

- T8/§S13.4: `extend`'s presence tests no longer spell the row-writer's literal.
- Floor: `steps/5.md` names `jit_check` and `jit_offer` again after the byte trim.
- Walk §14: `extend` decodes the copied `re_executes` before the row writer encodes it.
- R1/C2: the stop wall's fill width is the rung the tick reads, not the declared ceiling.
- R9: an unengaged session's plan-shaped Write journals nothing under `$HOME`.
- R15: four meanings the byte trim lost are back, paid inside the same surfaces.
- C1: `_EG_SUBSTITUTED` is set on both substitution forks, so the `use_worktree: false` twin
  refuses at `current: 5` what the `true` fixture refuses.

## 1.8.4 — 2026-09-20

- REQ-1: An active task's commit is never refused by the run's floor.
- REQ-2: The landing gate charges a writer tree only with its own edits.
- REQ-3: A compound that changes directory before its commit is judged where the commit
  lands, or refused for it.
- REQ-4: A tree of another repository is exempt from this run's step arms, with the reason
  printed.
- REQ-5: Plan-authoring refusals name the cell and the shape.
- REQ-6: Close-out accepts the plan's own working-branch shape.
- REQ-7: The brief scaffold teaches the span rule the parser applies.
- REQ-8: A dropped `Suites:` token is never silent.
- REQ-9: The floor streams each suite's verdict as it lands.
- REQ-10: Advisory readings are reported apart from the gating tally.
- REQ-11: A BOM-prefixed plan gets the same loud fault list as its LF twin.

### Fixes found in verification

- R1: A trailing `#` comment on a `Suites:` line no longer triggers a dispatch refusal for
  a dropped token.
- C1: The commit-subject fork no longer raises the judged step for an `active` row below
  step 4.
- C3: A command that names one directory twice before its commit is now refused for that
  shape instead of being judged at the wrong one.
- C4: Close-out's worktree census now falls back to the tracked-branch glob when a plan's
  `## Tasks` table carries no `worktree` column, so a plan written before this wave keeps
  its unmerged-work refusal.
- R6: `units_validate`'s docblock was reconciled with its own body.
- R7: The row-invalid refusal now names all twelve columns instead of ten.
- R8: The two test sections that shared the number 13 were renumbered.

### Known carry-overs

See `.bionic/docs/ideas/next-wave-after-184.md`.
