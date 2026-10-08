# Changelog

Earlier releases are recorded as git tags (`v1.4.3` … `v1.8.3`) rather than in this file,
which starts at 1.8.4.

Versioning follows semver from 1.9.0 on:
- **MAJOR** for a change that breaks a documented contract a user or project already relies
  on: a removed verb or field, a `canonical_sdlc_version` bump, an artifact a user must migrate.
- **MINOR** for new capability or a behaviour a user notices, including a newly refused action
  or an upgrade step.
- **PATCH** for a fix within existing behaviour.

## 1.13.0 — 2026-10-07

A row of work now lands by one line, `spawn-worktree.sh ready`, and a person lands one by hand with
`land <tree> --by-hand --reason '<why>'`. Width follows the machine's own load, read at one gate and
bounded by a share you can set. Every review finding is rated by a written scale, and the rating
decides whether it is fixed, deferred or noted. A project can declare its own floor. This is a minor
release: it adds verbs, configuration keys and plan facts, and refuses actions that were not refused
before. Nothing a project already relies on is removed, and `canonical_sdlc_version` stays 14. A run
open at upgrade continues on its 1.12.0 plan with no edit. The landing line has not met a real burst
before this release.

What you will notice:

- **One line lands a row.** `spawn-worktree.sh ready`, said from a row's own tree, builds the row on
  the working branch and on the rows ahead of it, runs the suites the row lands on through the
  gate, and publishes when they are green and the row is first in line. It prints
  `LANDED <row> <commit>`, then the acts still owed, in the order to do them:
  `landed <row> <commit> — owed: complete task <row>, then stop <name>` (exit 0). A red suite returns
  the row, `RED <row> <suite> <log>`, and moves nothing; the log is kept under the record
  directory's `line/`. A row that conflicts with a row ahead is returned with `CONFLICT <row> <files>`,
  a row whose range commits `.bionic` with `GUARD <row> <path> <commit>`, and a row that waits
  for the gate with `WAITING <row> — run again: <the same command>` (exit 75), its place kept.
  `ready --within <seconds>` never starts a suite whose usual time is more than the time left. A
  row proved on the candidate of a row ahead is stopped, rebuilt and proved again when that row is
  returned, so a refused row never holds up or leaks into the rows behind it. No writer runs a
  proof for the landing; `ready` makes its own.
- **A red means what the line can prove.** A suite killed by a signal, unable to start, or ending
  with no verdict line is run again, and a second such run stops `ready` with
  `STALLED <row> <logs>` (exit 70). A red whose failing lines all fail at the accepted head too,
  line for line and counted, is the branch's, not the row's: the row lands, and the tick says
  `standing … at <head>` once. A row that declared `Lands-red: <suite>` lands red on that suite
  alone, printing `DEBT …`; its debt is written before the fast-forward and voided if the
  fast-forward fails. The tick prints each standing red and each stalled entry once, with its logs.
  `ready --within 08` means eight seconds, and a `BIONIC_LINE_POLL` that is no number falls back to
  one second.
- **A hand landing is a person's act, and it is recorded.** `spawn-worktree.sh land <tree>` on its own
  refuses and names both ways to land. `land <tree> --by-hand --reason '<why>'` publishes through
  the line's one lock and records the git user, the time and the reason on the landing record and on
  the row's `- T<n>:` line. A subagent's hand landing is refused by the Bash wall. A plain `git merge`
  of a row's branch into the working branch is counted: the next read of the line marks the row landed
  by git, and a row tree with no commit of its own is not counted as landed by a merge. A publish waits
  (`HELD`) while a suite runs in the checkout that holds the working branch, and stops (`MOVED`) when a
  real checkout moved during the run.
- **The landing writes its own plan row.** A landing sets the row `landed`, adds its step-line text and
  its ledger line, and marks the agent's roster row, in one write of the plan. If the plan changed
  under that write, `ready` prints `PLAN-UNWRITTEN <row> — published <commit>; the plan row is not
  written: run row-landed <row> <commit> <at> from the main thread`. `stop-orders.sh standdown` now
  reports each open row's tree as it stands and lands nothing; `stop-orders.sh stopped <name>`
  closes a landed row and removes its tree when its head is in the landed commit.
- **The share.** `session-poker.sh share` prints the machine's share of its own resources and
  `share <n>` sets it, 1 to 100; 80 is the default. Setup offers to write it, `/bionic:remove` takes
  the file out on a yes, and `/bionic:doctor` reports the share, whether it came from the file or the
  default, and the gate's own row.
- **A plan no longer needs a `parallel-budget:` line, and the probe's number caps nothing.** Step 0's
  probe is an estimate. A `parallel-budget:` line caps writers only when marked `source=user` or
  `source=override`; `session-poker.sh budget writers=<n> '<reply>'` on a plan with no line writes
  `parallel-budget: writers=<n> source=user`. The dispatch wall no longer counts worktrees and no
  longer warns about a plan with no budget line, and the Step 3 card reads writers only from a
  person's cap and says "writers not declared" otherwise. `spawn-worktree.sh create` refuses when free
  disk is under the largest tree.
- **Width comes from the gate.** The Patrol's tick prints one gate line,
  `poker: gate share=<n> used=<n>% load=<1m>/<5m> of <cores> promised=<n> admitted=<n> waiting=<n> room=<yes|no>`,
  and, while memory is over the share, `poker: over share — used=<n>% admitted: <keys>`. The fill asks
  the gate once per ready writer row and stops at its first no; the only cap is a person's. The rung,
  the two holds, the emergency block and the kill floor are gone.
- **Every heavy command asks the gate.** The Bash wall wraps a suite, a build or a drill in
  `booked.sh`, which asks the gate before it runs; a command the gate does not admit in its time
  exits 75 with the line to run again, nothing run, never a kill. A timing check
  (`BIONIC_QUIET=1` or a `# runner: solo` marker) takes the whole machine, and a disturbed passing run
  reports `void`. Doctor shows the gate's row.
- **The Stop wall's owed count reads the gate store once.** It no longer forks a grep per request file
  per writer, so it stays under the Stop hook's timeout however many requests have piled up. Ended
  gate requests older than `BIONIC_GATE_KEEP` seconds (default one day) are removed. A request whose
  holder is gone is no longer counted as running, and the check reads a store of any size.
- **The run prints its own numbers.** `session-poker.sh landing-report [--rows] [<plan>]` prints the
  run's landings by kind, the minutes from each row's first `ready` to its landing (median, p75, max),
  its suite runs by outcome, how long runs waited for the gate and how many were killed. A row's
  runs are counted by the commits that row built, so a row that waited behind another does not show
  the accepted head's run as its own. The tick prints the line above its decision line, on every tick
  that is not `unchanged`; a passing `release-check` prints it with one line per landed row; the
  continuation close-out writes carries a `## Landings` section. A run whose record predates the
  line reads `unmeasured`, not zero. Nothing decides on any of it.
- **Every review finding is rated, and the rating is a rule.** A reader dealt the scale
  (`payload/context/severity.md`, pushed beside the code questions' checks) rates each finding
  S1 to S4 and `on` or `off` by whether a user who follows what the run ships meets it. The table
  decides: an S1, and an S2 a user meets, are fixed; an S2 a user does not meet, and an S3 a user
  meets, are deferred; an S3 a user does not meet, and an S4, are noted. A
  review pushed the scale is registered only when it states `findings: <n>` and one
  `finding: <n> <S1-S4> <on|off> <path>:<line>|- <title>` per finding; its `result:` is the one its
  findings derive, and a written `priority:` that differs from the table is refused. Registering a rated
  review writes a `deferred:` line for each finding the table defers and a `check:` line for each
  finding the reader could not settle; the tick prints `poker: FINDING <record>#<n> <S> <reach>
  <priority> "<title>"` for each. A review from a reader that was not pushed the scale registers as
  in 1.12.0.
- **A deferral is held to its debts.** `session-poker.sh finding-stated '<record>#<n>' '<sentence>'`
  writes a deferred finding's one changelog sentence onto its plan line, and `release-check` prints each
  deferral as `stated` or `unstated` against `CHANGELOG.md`, refusing nothing for it. Close-out carries
  the run's own and inherited deferrals into the continuation under `## Deferrals`, including a
  continuation that already has that section, and the next Step 1 card lists every deferral of the
  newest continuation until the requirements file's `## Inherited deferrals` section disposes of each:
  `adopted: <id> as REQ-<n>`, `again: <id>` or `closed: <id> <reason>`.
- **A finding the reader cannot settle owes a check, and a move is the user's word.**
  `session-poker.sh finding-check <record>#<n> settled <S> <reach> | refuted | unsettled <check record>`
  settles the check an `unsure:` finding owes. A check record sits under the record directory, names
  its writer with `written-by:`, and is refused when that writer is the finding's reviewer or the
  code's writer. `current 8` waits on every open check. A settled check re-rates its finding at every
  read, and the commit wall reads a review's result the way `current 8` does.
  `session-poker.sh finding-move <record>#<n> <defer|fix> '<the user's words>' '<why>'` moves a
  finding across the line, on the main thread only, and only on words the user typed in this session,
  as whole words in a prompt: a pasted block, a tool's result, a teammate's or another session's
  message, a hook's context and the orchestrator's own text are not the user's. A quote is at least
  three words, or the user's whole prompt (a slash command's arguments, for a slash command). An S1
  is never moved to defer.
- **A record path registers one pass.** `proof-add review` refuses a record path a second time for
  another pass, once a check, a deferral or a move is written on it; a second pass is written to a
  new record path. The commit wall derives a reading's result only from Step 6 on and in one pass, so
  a commit at Step 4 no longer pays for every reading (17 seconds with 88 checks before; 0.7 seconds
  now).
- **The reader exam passes a sample only on a declared finding the table sends to fix.** A reader's
  answer to a defect sample must carry a `finding:` line for the key's file at a rating the key
  admits; a description alone is `missed`. A stale sitting is marked `stale:` and a re-sit is owed.
- **Review rigor is `low`, `medium` and `high`.** `low` is `tested`, `medium` is `peer-reviewed`
  and `high` is `audited`: the tool reads either word as the same level, and a file carrying an old word
  is read as it is and never rewritten. A run is announced as `<intent> · <level> rigor · <scale>`
  (for example `build · high rigor · wave`), followed by the line `card.sh rigor` prints, such as
  `review rigor: high (three independent readers)`.
- **A dispatched agent runs a suite through one door.** In a project whose `tests/run.sh` takes
  `--only`, `tests/run.sh --only <suite>[ <suite>…]` runs just the named suites with the full run's
  interpreter pin, environment, walls and one gate ask each, and a dispatched agent's bare
  `bash tests/<suite>.test.sh`, in any form, is refused with one line naming it. The classifier now reads
  a suite run through a `for` or `while` loop, a variable or a binding. A suite run by hand whose
  interpreter pin cannot be built stops with exit 2, naming the pin's path and the reason, where it used
  to run unpinned. The door is the shape from 1.13.0 on: a 1.12.0 wall reads `tests/run.sh --only` as the
  full tree, so until the new plugin is installed a project runs a suite by its file path.
- **The interpreter pin is judged along its whole path.** The pin is refused under a directory another
  user can write, replace or add entries to (including by a macOS or Linux ACL), under a parent
  that group or others can write and that has no sticky bit, through a directory owned by another user,
  or at a pin root another user planted, even one swapped for a link while it was built. A temp
  directory or any directory on the path that does not exist, a relative root or a relative
  `TMPDIR` is refused; the refusal says to set `TMPDIR`. The pin builds again inside an unprivileged
  user namespace (bubblewrap, a Nix sandbox, `unshare -U`), where a host `/tmp` bound into the sandbox is
  still refused because the sandbox's tmpfs root reads as the user. A root that vanished between two
  checks is refused, and the pin's entry on `PATH` is physical.
- **A brief names its row and its suites.** The brief scaffold carries `Row: <id>` and
  `Lands-on: <suite>[, <suite>]` (or `Lands-on: none <reason>`), and `Expected artifact:` takes a bare
  file name. A dispatch is bound to one row: the row its `Row:` names, else the row its agent name
  matches; a `Row:` that names a different row than the name matches is refused, and so is a name that
  matches more than one row with no `Row:` to say which. `ready` proves a row on the suites the walls
  read for it, so a row widened by `amend` lands on the widened set and a run adopted after `/clear`
  lands by `ready`; `run.sh` in a suite list is refused naming its key.
- **A dispatching turn keeps the task list honest.** A turn that dispatches plan rows must set each
  dispatched row's task entry in progress before it ends; the turn-end wall counts those updates
  against the rows the turn launched and refuses the turn once when there are fewer.
- **A dispatch the roster cannot record is refused, and an agent the roster never saw can be stopped.**
  An unwritable roster, a roster path that is a link, a launch row that does not build, and a
  dispatch wall that has not finished 3 seconds before the harness would cancel it each refuse the
  dispatch instead of admitting it; the stop guard refuses a stop it has not finished judging 3
  seconds before its own timeout. `stop-orders.sh unrostered <name> '<why>'` is the orchestrator's one
  word for a listed agent the roster never saw: honoured once, written to the roster as a closed row,
  and only for a name no roster of the project (this session's, a predecessor's, a dead session's)
  holds. A read-only role launched from inside an agent prints
  `bionic: dispatch admitted without a roster row — …`: it never had a row, and now says so.
- **A project declares its own floor.** A project declares its floor with `floor: <command>` in
  `.bionic/config.yaml`; `floor-run` runs it and `proof-add floor` accepts its log; `floor-attestation: user`
  accepts the user's attestation record; a project with neither keeps the `tests/run.sh` rule. The log
  `floor-run` writes opens with `head=<40-hex> dirty=<n> rc=<n>`, and `proof-add floor` judges it by that
  line alone: the head is the working head, the tree was clean, the floor passed. An attestation record is
  any file under `record/` holding a flush-left `head=<40-hex> dirty=0` line naming the working head and a
  `floor-attested-by: <who> <when> <what ran>` line. The tool checks the contract, not the runner's output.
  `floor-run` writes no plan and no proof, so a dispatched writer may run it.
- **Step evidence is written by a verb.** `session-poker.sh step-field <N> <key>=<value>` writes or
  replaces one field of a step's evidence block (`head`, `cmd`, `pass`, `total`, `output`, `merge`,
  `worktree-removed`, `adr`, `share`) through the plan transaction, and `current 4` on a wave plan
  records `share: <n>`. `finding-check` finds the code's writer by the `Files:` matcher and counts
  every agent the row carried.
- **Setup and remove keep a record of what they install.** Setup, and a route's mid-session offer,
  write each tool they install to `~/.claude/bionic/installed` (name, kind, time, bionic version).
  `/bionic:remove` offers to remove a tool that record names and removes it on a yes; a tool with no
  line is still named with its by-hand command and left alone. A recorded Playwright browser or pnpm
  store entry is named as bionic's but left in place, because other projects share the cache.
  `/bionic:doctor` has an INSTALL RECORD section listing what bionic installed; a name bionic no
  longer knows reads `unknown`. This retires the limit 1.12.0 listed on the missing record: a tool
  installed before this release has no line, so remove keeps naming it for removal by hand.
- **Guards.** The `.bionic` landing guard's fix now ends "say ready again" and says nothing of
  stamps; for a submodule link under `.bionic` it names the commit that added the link, and its fix
  takes the link out of the index. A shell script's `case` arm with no opening paren inside `$( … )`
  and bash 3.2's two heredoc hazards are found by a new suite, `tests/shell-lint.test.sh`, which also
  loads every library under `/bin/bash`. The doctrine is rewritten for one landing line, one gate and
  one door.
- **The test runner runs on the latest Sonnet.** The `test-runner` role runs on the latest Sonnet
  (it was Haiku), effort unchanged. Its reports are relied on for the floor, and Haiku's were not
  reliable enough.
- **For contributors.** The three slowest suites were timed alone and one cut landed, about 2% of the
  slowest; the target of a third off each missed, and the measured costs lie in the hook and door
  drives the rows run, recorded with their numbers for the next release.

Newly refused:

The refusals of the poker's, the stop script's and the worktree script's verbs name a path, a head or a
record, and run past 100 columns; the walls, the Stop wall, the dispatch wall and the stop guard keep
the first line of a refusal to 100.

- `spawn-worktree.sh land <tree>` on its own:
  `land: the line lands a row with "ready"; a person lands one with "land <tree> --by-hand --reason '<why>'"`.
- A hand landing with no reason, or a reason holding a `|` or a line break:
  `spawn-worktree: REFUSED reason=no-reason path=<tree> — a hand landing says why: land <tree> --by-hand --reason '<why>'`,
  `spawn-worktree: REFUSED reason=reason-unwritable path=<tree> — the reason holds a | or a line break; say it on one line without |`.
- `ready` from a place that is not a row's tree, on a detached head, or for a row with no launch line or no
  suites to run:
  `spawn-worktree: REFUSED reason=not-a-tree path=<cwd> — run ready from the row's own tree`,
  `spawn-worktree: REFUSED reason=no-launch-row row=<row> roster=<path> — ready reads the row's suites off its launch line`,
  `spawn-worktree: REFUSED reason=no-lands-on row=<row> name=<name> <key>=<value> — no suite to run; land <tree> --by-hand --reason '<why>'`.
- A landing that cannot be recorded, or whose fast-forward fails:
  `spawn-worktree: REFUSED reason=record-unwritable why=proofs-unwritable path=<rec> branch=<b> — the landing record cannot be written, so nothing is published; make it writable, say ready again`,
  `spawn-worktree: REFUSED reason=publish-failed row=<r> branch=<b> candidate=<c> checkout=<co|<none>> — the fast-forward did not go through and nothing is published; say ready again`,
  and, for a declared red's debt that cannot be written,
  `spawn-worktree: REFUSED reason=debt-unwritten why=proofs-unwritable suite=<s> path=<rec> row=<row> — the declared red's debt cannot be written to the landing record (<saw>), so nothing is published; make it writable, say ready again`.
- A row that does not merge onto what is ahead of it, or that left the line:
  `spawn-worktree: REFUSED reason=conflict branch=<b> onto=<o> files=<f,…> — the row does not merge onto what is ahead of it; merge <onto> into the tree, land again`,
  `spawn-worktree: REFUSED reason=not-in-line branch=<b> — the row left the line before its publish (git log <onto>)`.
- A landing whose range adds `.bionic`:
  `spawn-worktree: REFUSED reason=bionic-committed path=<p> commit=<12-hex> branch=<b> onto=<o> fix='git -C <tree> <remedy>, say ready again' — a committed .bionic, merged, replaces the project's .bionic directory; nothing is merged, the tree is kept`.
- `spawn-worktree.sh create` when free disk is under the largest tree:
  `spawn-worktree: FAIL reason=disk-low free_kb=<n> largest_tree_kb=<n>`.
- A writer dispatch that binds a plan row and names no suites to land on, a `Lands-on:` with no reason,
  a suite outside `Suites:`, or a `Row:` naming no plan row:
  `bionic: dispatch refused — the brief has no Lands-on: line (add Lands-on: <suites> or none <why>)`,
  `bionic: dispatch refused — Lands-on: none gives no reason (write the reason after none)`,
  `bionic: dispatch refused — Lands-on: <suite> is outside Suites: (name a suite the row runs)`,
  `bionic: dispatch refused — Row: <id> names no plan row (name a ## Tasks row id)`.
- A `Row:` that names another row than the agent's name matches, and a name that matches more than one row
  with no `Row:`:
  `bionic: dispatch refused — Row: <id> is not the name's row <id> (rename or drop Row:)`,
  `bionic: dispatch refused — the name matches rows <id>, <id> (add Row: <id>)`.
- A dispatch the roster cannot carry:
  `bionic: dispatch refused — the roster cannot be written (make it writable)`,
  `bionic: dispatch refused — the roster path is a symbolic link (remove the link)`,
  `bionic: dispatch refused — the launch row did not build (run /bionic:doctor)`,
  `bionic: dispatch refused — the wall ran out of time (dispatch again)`.
- A stop the guard cannot finish or record:
  `bionic: stop refused — the stop guard did not finish in 7 s (stop again)`,
  `bionic: stop refused — the stop could not be recorded (make the roster writable)`;
  `stop-orders.sh unrostered` for a name some roster of the project holds, or a reason carrying a `|` or
  a line break:
  `stop-orders: REFUSED — <name> is on roster <id>'s row <status>.`,
  `stop-orders: REFUSED — the reason holds a | or a line break; say it in one plain line.`
- A dispatched agent's bare suite run, in a project whose `tests/run.sh` takes `--only`:
  `bionic: suite-run refused — use tests/run.sh --only <suite file> (one door)`; and the interpreter pin,
  by hand: `resolve-roots.sh: no interpreter pin at <root> — <why>; remove <root> or set TMPDIR, then run again`.
- The end of a turn that dispatched plan rows while fewer of their task entries were set in progress:
  `bionic: stop refused — a dispatched row's entry is not in progress (TaskUpdate each to in_progress)`.
- A review pushed the severity scale, registered with `proof-add review`: the reading is refused, and the
  plan unchanged, when it carries no `findings:` line, gives a count that is not the number of
  `finding:` lines, rates a finding outside S1 to S4 or a reach other than `on` or `off`, names no
  `<path>:<line>` or `-`, sends a finding to fix without a `shown:` command or an `unsure:` line, writes
  a `priority:` the table does not give, or says a `result:` its findings do not derive; each line
  begins `REFUSED — the reading <record> …` and says what to write. For `structure`, a `check:` that answers
  FAIL beside no finding to fix, and a finding to fix beside no FAIL check, are refused the same way.
  A record path registered again for another pass:
  `poker: REFUSED — <record> is already registered at <12 hex>, not <12 hex>: write the pass to a new record path. The plan is unchanged.`
- `session-poker.sh finding-check`: refused, with the plan unchanged, for a check the plan does not owe, a
  check already settled, a check record that is missing, a link, outside the record directory, with no
  `written-by:` or written by the finding's reviewer or the code's writer; and `current 8`:
  `REFUSED — current: 8 waits on each check a finding owes; these check: lines are open (no settled=, no refuted):`.
- `session-poker.sh finding-move`: refused, with the plan unchanged, for a finding the plan does not register,
  a finding its check refuted, an S1 moved to defer, a repository with no `git user.name`, a session whose
  transcript cannot be read, and words that stand in no prompt the user typed in this session:
  `REFUSED — the words "<words>" stand in no prompt the user typed in this session; a move is the user's own word, quoted from a prompt they typed. The plan is unchanged.`
  and a quote too short to be a decision:
  `poker: REFUSED — the words "<words>" are too short to be the user's decision; quote at least 3 of their words, or their whole prompt. The plan is unchanged.`
- `session-poker.sh floor-run` for a project that declares no `floor:`, for a plan whose working branch no
  checkout holds, and for a floor that moved the working checkout while it ran; `proof-add floor` for a log
  whose head is not the working head, whose tree was dirty, whose floor did not pass, or whose first line
  is not the line `floor-run` writes, for an attestation that names no head or no `floor-attested-by:`
  line, and for a `floor-attestation:` value other than `user`:
  `poker: REFUSED — this project declares no floor: in .bionic/config.yaml; its floor is tests/run.sh, whose log proof-add floor reads. Nothing was run.`,
  `poker: REFUSED — the floor (<cmd>) moved the working checkout <co> while it ran (head <a> to <b>, dirty=<x> to dirty=<y>); no log was written. Put back what it changed and run floor-run again.`,
  `poker: REFUSED — the run in <ev> read head <sha12>, but the working branch is at <head12>; run it again on <head12> and cite that log. The plan is unchanged.`,
  `poker: REFUSED — the floor in <ev> did not pass (rc=<n>); fix it, run floor-run again and cite that log. The plan is unchanged.`
- `session-poker.sh step-field` for a value with a line break, a key outside the nine, a step with no line, a
  Step 9 block, or a step line that itself carries the key:
  `poker: REFUSED — a step field is one line, and the value has a line break; the plan is unchanged.`,
  `poker: REFUSED — '<key>' is not a step field; the plan is unchanged.`,
  `poker: REFUSED — the plan has no Step <N> line; step-line writes it first. The plan is unchanged.`,
  `poker: REFUSED — the Step 9a block is close-out's to write (scripts/close-out.sh).`
- `session-poker.sh share` with a value that is not a whole number from 1 to 100:
  `poker: REFUSED — share <value> is not a whole number from 1 to 100; the share is unchanged.`
- `session-poker.sh finding-stated` with a sentence that is blank or a `<record>#<n>` that is not one is a
  usage error; `close-out` over a continuation whose inherited deferrals cannot be read:
  `could not read the deferrals this run inherited (card.sh inherited) — no continuation written`.
- `card.sh step1` when a disposal names a deferral the newest continuation does not carry:
  `card.sh: step1 refused — a disposal names a deferral the newest continuation does not carry`.

Upgrade, for a plan already in flight:

- Upgrade the plugin and keep working. A run open at upgrade keeps its plan as written: nothing is
  edited, a tree holding a stamp is landed by `ready`, which ignores stamps, and the plan's bytes
  outside a row's own lines are unchanged by `ready`, a tick or a hand landing.
- A row dispatched under 1.12.0 carries no `lands_on=` on its launch line. `ready` for it refuses
  `no-lands-on`, naming the hand landing, and the dispatch wall refuses the next unlabelled writer brief
  that binds a row, naming the line to add: its next writer dispatch that binds a row needs a
  `Lands-on:` line.
- A plan written under 1.12.0 with a `source=probe` budget line keeps working; the line caps nothing,
  and a `source=user` or `source=override` line still does.
- The Patrol prompt stays at version 6; there is nothing to re-arm.
- You may set a share (`session-poker.sh share <n>`) and declare a floor in `.bionic/config.yaml`.

Fixes:

- A request the gate lists as `killed` includes one that ended on a signal exit over 128 (such as the
  143 of a rollover kill), matching what the landing report counts.
- A red whose failing lines all fail at the accepted head is compared line for line and counted, not
  as a set.
- A suite run from the main checkout as `cd <tree> || exit 1; …` records the tree it runs in, so it no
  longer makes the main checkout look busy to `land`.
- The interpreter pin no longer refuses a shared sticky `/tmp` on a Linux host with `getfacl`, where
  every hand-run suite and `tests/run.sh` exited 2.

Known limits, carried to the next release:

- Known limit: `lib/gate.sh` and `close-out.sh` each define a function named `gate_ask` with different
  arguments; no shipped path loads both in one shell, and the next wave renames one.
- Known limit: a whole-machine run asked of the gate is passed by every later ask while anything is
  admitted, so on a busy machine it may wait a long time; the previous quiet marker drained the machine
  first.
- Known limit: a hand landing that waits behind another row rebuilds its candidate every fifth of a
  second and records each rebuild; a long wait writes many lines.
- Known limit: when no landing tree is free, a publish runs the project's release check in the main
  checkout rather than in a tree pointed at the accepted head.
- Known limit: after a timed-out ask, an agent that asks again for the same command may resume the newer
  of two waiting places and leave the older one behind.
- Known limit: when two sessions dispatch a reader of the same name, the registration may read the other
  session's roster row to decide whether finding lines are required.
- Known limit: a structure record with a doubt (FLAG) and no finding meets two refusals that disagree on
  the result to write; write `pass` and no FLAG, or a finding for the doubt.
- Known limit: when a reader's start could not be matched to one roster row and the plugin lacked one of
  its context files, the roster row may record that file as pushed although it was not.
- Known limit: a structure reader whose finding to fix sits under no check's failing case is refused at
  registration; answer FAIL on the nearest check.
- Known limit: a structure check the text itself answers FLAG, with no finding written, is refused at
  registration; write the doubt as a finding.
- Known limit: a row proved on top of an unaccepted row ahead is returned red when the row ahead's own
  change caused the failure.
- Known limit: the `WAITING` line's run-again command must be run from the row's own tree.
- Known limit: a suite killed by `--kill-after` or a signal is recorded as that suite's cost — the
  truncated run's seconds, not a full run's — until the next complete run replaces it.
- Known limit: `release-check` prints its deferral stated/unstated lines only when the project declares a
  `release-check:` command; a project without one sees no line.
- Known limit: the Step 1 card tells the run's own continuation from its predecessor's by the
  requirements file's name (`<wave slug>.requirements.md`); a requirements file named otherwise can make
  the card read the run's own continuation as the predecessor and list no inherited deferral.
- Known limit: the Step 1 card takes the newest continuation under `record/` as the predecessor even when
  it carries no `## Deferrals` section — a continuation written before its run's close-out, or left by an
  abandoned run — and then lists no inherited deferral.
- Known limit: the tick's told memory for standing reds and stalled entries
  (`.bionic/tmp/line-told-<session>.state`) is not among the session-state classes the Patrol's sweep and
  dead-session walk know, so it is never swept.
- Known limit: when close-out cannot read the deferrals a run inherited, `run` refuses after its worktrees
  are removed and its tmp wiped, and `check` exits 2 instead of reporting the refusal it would make.
- Known limit: `/bionic:doctor`'s gate row samples the gate, which takes the gate's lock and may write
  the store (an idle marker, or the end of a dead holder's request) — the same writes the next gate call
  would make.
- Known limit: the writers a session has launched but not yet asked the gate for are counted by that
  session alone; two sessions on one machine can each offer into the same room.
- Known limit: `standdown` reports a landed row's tree as standing only when the tree is at the
  conventional path (`.worktrees/<lower-cased name>`); a tree at another path is still found and removed
  by `stopped`.
- Known limit: the `PLAN-UNWRITTEN` line after a hand landing names the `row-landed` call without its
  `--by-hand <who> <why>` part; add it by hand so the plan keeps the hand landing's text.
- Known limit: when the plan changes under `row-landed`'s write, the write is refused once and not
  retried; `ready` prints `PLAN-UNWRITTEN` and the `row-landed` call to run from the main thread.
- Known limit: the reader exam's scorer reads a record's `result:` line as written on a clean sample,
  where the registering verb derives it from the findings.
- Known limit: a sitting marked `stale:` is pinned as it stands, including any `missed` line it
  carried.
- Known limit: the admit-not-require sample admits a finding on two files only; a finding placed on the
  evidence, the test or `-` scores missed.
- Known limit: the exam's briefs ask a reader to read the shipped scale and checks files from the plugin
  copy by path; a session that cannot read outside its project needs them inlined.
- Known limit: a suite run by `source tests/<suite>.test.sh` or `. tests/<suite>.test.sh` from a
  dispatched agent passes the Bash wall with no refusal, wrap or stamp; only the spellings the classifier
  reads meet the door.
- Known limit: the suite shim decides the gate request's tree and the stamp's tree separately — a command
  that opens with `cd <row tree>` and passes no `--stamp-dir` records the request against the row tree
  and the stamp against the tree it was started from; the doctrine's form always passes `--stamp-dir`, so
  a writer following rule 5 never meets it.
- Known limit: the brief's bare-file-name rule can read a word of prose with a dot — `i.e.`, `e.g.`,
  `Node.js`, or a file the brief only mentions — as a second deliverable and refuse the dispatch as naming
  several paths; write the deliverable as the one path and keep such words off the `Expected artifact:`
  line.
- Known limit: the interpreter pin's ACL reader on Linux (`getfacl -p`) is proved through a stub only; on
  a real Linux host it is unverified.
- Known limit: a successor instance with no `row=` label and no ledger or Tasks cell naming it is not
  counted as the code's writer.
- Known limit: the task list's dispatch-turn duty counts only a main-thread `TaskUpdate` set to
  in_progress; a session without the task tools is refused once on every turn that dispatches a plan row,
  and the plan-ledger write the refresh duty accepts as its fallback does not satisfy the dispatch duty —
  stop again to proceed.
- Known limit: the suites that drive the real runner (`runner-width` §2b, `interpreter-pin`, `framework`)
  ask the machine's real gate store, leaving test requests and test-only cost keys in
  `~/.claude/bionic/gate/`; after a run, a command the gate has never seen may read a near-zero cost from
  those keys instead of running alone — delete the store's `cost/` test keys, or run the suites with
  `BIONIC_GATE_DIR` pointed at a throwaway store.
- Known limit: a `moved:` line written by hand on the plan, with words nobody typed, is honoured by every
  read exactly as a line the verb wrote; the proof of the user's word is made when `finding-move` writes
  the line, not when the line is read.
- Known limit: the landings figures count only landings the line recorded as events; a run whose record
  predates the line, or straddles it, prints its later landings as the run's.
- Known limit: the landings line's `red-then-green` figure counts a flake the line does not yet record — a
  red re-run green on the same candidate — and reads 0 until the line records one (a red is judged, not
  re-run); the figure's definition or removal is the next wave's.
- Known limit: when a hand `git merge` of a row is counted while the row's own suite is still running, the
  landings line counts the accepted head's run too (red=2 where the truth is 1).
- Known limit: the landings line's gate figures count requests still in the store; a run longer than
  `BIONIC_GATE_KEEP` (default one day) prints the last day's.
- Known limit: a reused agent name whose earlier instance is still listed can be read by `ready` as the
  current row; give each instance its own name (`<name>-b`), as the dispatch doctrine says.
- Known limit: the move's proof counts words as space-separated runs of letters, digits, `_`, `-` and
  apostrophes; in a script written without spaces, quote the whole prompt — a script-aware count is the
  next wave's.
- Known limit: a request file edited by hand to a non-decimal `admitted=` aborts `gate_end` with the lock
  held; the gate never writes one — the next wave reads it through `_gate_num`.
- Known limit: the dispatch wall and the launch record match an agent name by two rules that agree on
  every name the Agent tool accepts; a name with a comma or a leading `-`, which the tool refuses, would be
  read differently by the two.
- Known limit: a hook that outruns its timeout under load is cancelled by the harness and the action is
  admitted unjudged; the dispatch wall and the stop guard now refuse at a deadline instead, the other
  hooks do not yet.
- Known limit: the deadline of the dispatch wall and of the stop guard is a trap that bash runs only after a
  running `$( … )` returns, so a slow substitution can outlast the registration and be cancelled and
  admitted as before.
- Known limit: when the dispatch wall's deadline fires while it waits on a project's impact command, the
  command keeps running with no bound and leaves its temp file in `TMPDIR`.
- Known limit: a request number is reused after the gate prunes a gone request, so an orphaned waiter may
  admit a newcomer's request, which then waits for ever; interrupt the waiter.
- Known limit: a declared debt (`Lands-red:`) survives `adopt` but not a later `hold` or `amend` of the
  adopted row; re-declare it by `amend` after such a copy.
- Known limit: when a project's impact command hangs, the dispatch wall may report its own deadline
  instead of the impact command's; declare `Suites:` to bypass the command.
- Known limit: an agent whose only roster row sits in a symlinked or unreadable roster file can be
  stopped as unrostered.
- Known limit: a name that a swept-not-yet roster holds as closed cannot be stopped as unrostered; use
  `stop-orders.sh order` or wait for the sweep.
- Known limit: a pin root carrying a C1 control byte (0x80–0x9f) is printed raw in the seam's reason line;
  it is refused all the same.
- Known limit: a pasted block that never closes leaves its text counted as the user's words.
- Known limit: `deferral_fold` returns nothing without jq.
- Known limit: a pasted block containing a `</pasted_content …>` close inside its text is cut at that
  inner close; the remainder counts as typed.
- Known limit: quote the user's words without the typographic quotes that surround them; a `’` inside a
  word (`don’t`) is fine.
- Known limit: a suite call that carries any command between its `cd` and the suite may be stamped
  against the main checkout; keep the call in rule 5's bare shape and read the stamp.
- Known limit: under `claude -p` in auto mode the CLI's own classifier can deny the Patrol's recurring
  `CronCreate` as unauthorized persistence, so no clock is armed until you approve the job; the session
  reports that the Patrol is not running and asks you to.
- Known limit: the `.bionic` landing guard folds ASCII case only; a spelling of the name that a disk
  resolves to the same directory by another Unicode fold is not recognised. On the APFS volume probed,
  the ASCII case variants were the only spellings that resolved to the same directory, so the limit
  matters on a filesystem that folds more.
- Known limit: a row whose Files cell marks a path unmergeable (`path!`) is not found as that path's
  writer by `finding-check`; a check it writes on its own code is admitted — the orchestrator refuses such a
  check by hand.
- Known limit: `floor-run`'s refusal for a session bound to no run borrows the plan verbs' wording and says
  it "writes the plan"; `floor-run` writes no plan.
- Known limit: a floor command that exits 2 shares the poker's usage-error code; the log's `rc=` is the
  fact.
- Known limit: a floor declared with `floor:` or attested with `floor-attestation: user` proves the floor as
  a whole; a `Lands-red:` debt a row declared for one suite is cleared by it although that suite never ran.
- Known limit: the attestation record is the user's own word: the tool checks its two lines and the head,
  never who wrote `floor-attested-by:`.
- Known limit: `config_value` reads a `floor:` key wherever it stands in `.bionic/config.yaml`, an indented
  one under another mapping included, and keeps a trailing `# comment` in the value — write the key
  flush-left with no comment.
- Known limit: a plain `git merge` of a row is counted as a `published kind=git` landing only when the
  next `ready` runs, and its landed time is that act's time, not the merge's; a hand landing by
  `row-landed --by-hand` is counted at once.
- Known limit: a `fail` reading holds the step advance from `current 6` on, not at `current 5`; and a
  later `pass` reading registered over an empty range (the same commit at both ends) releases the hold
  although it covers no fix — the orchestrator, who registers readings, must register the pass over the
  range that holds the fix.
- Known limit: under `claude -p` the prompt's transcript entry carries no `origin`, so `user_said` finds
  no words the user typed and `finding-move` is refused; make a move in an interactive session.

One rule for landing: a row lands by `ready`, which proves it on the line itself; a person lands one
by hand and says why.

## 1.12.0 — 2026-10-06

**Upgrade before you run `/bionic:setup` or `/bionic:remove` again.** In 1.11.0, setup and
remove can delete lines of your shell rc that are not bionic's, in six ways. 1.12.0 fixes all
six, and 1.11.x gets no patch. From 1.12.0 no door removes a line of your rc that stands outside
a pair of bionic's markers; a marked block is removed as one unit only when its body is byte for
byte one bionic wrote. Bionic's `claude()` block now opens with
`unalias claude 2>/dev/null || true`. An alias named `claude` above the block, bionic's own
retired line or yours, made every shell start print a syntax error at the function's line: under
zsh nothing of the rc after that line ran, and bash defined no function and ran the lines that
follow. An existing install whose block holds exactly an earlier body of bionic's is offered the
`claude()` item again at its next setup, and taking it rewrites the block where it stands. A block
you changed is never rewritten.

Every run that ships code is now read by an independent reader, at every rigor. The rigor sets
how many readers there are, not which questions are asked: each run answers the same three
reading questions, `evidence` (is the proof real), `adversarial` (try to break it) and `structure`
(reuse, one site per concept, the five SOLID principles), and each answer is a recorded fact that
the gates read. A release also owes any check its project declares, and setup offers a short set
of working principles. This is a minor release: it adds a role, verbs, a configuration key and a
plan field, refuses actions that were not refused before, and asks the upgrade step above. Nothing
a project already relies on is removed, and `canonical_sdlc_version` stays 14.

What you will notice:

- **Rigor is the number of readers.** At `tested` one critic answers all three questions; at
  `peer-reviewed` an auditor answers `evidence` and a critic answers `adversarial` and
  `structure`; at `audited` an auditor, a critic and a reviewer take one question each. At
  `scale: wave` the two code questions are also read once over the whole run, after its last build
  piece lands. A reader's brief carries a `Questions:` line naming the set its rigor deals it, and
  the checks for each question (`payload/context/checks-<question>.md`) are pushed to the reader
  at start; a brief carries no checks of its own.
- **A new role, `bionic:reviewer`,** answers `structure`. It answers each check PASS, FLAG, FAIL or
  `n/a` with a reason. Writers search for an existing site before they add one and say so on a
  `reuse:` line, and the Step-2 ownership table may carry a `reuses` column, which the Step-2 card
  prints.
- **A reading is a fact.** A reader's record holds one pass, with flush-left `reviewed: <a>..<b>`,
  `question:`, `result: <pass|flag|fail>` and `scope: <piece|whole>` lines, and a `check:` line per
  check for `structure`. `session-poker.sh proof-add review <record> --question <q> --reader <name>`
  registers it, spelled `record/…` from the docs root or as an absolute path, and writes
  `question=`, `reader=`, `result=` and `scope=` on the proof line. The reader must be the one
  dealt that question, and the record must be named on its roster row. `session-poker.sh waive
  <question> '<reply>'` records your waiver of a question, your reply quoted. A proof line without
  the new fields reads as it did.
- **Each question has its own chain.** A review row may read `live:head:<q>[+<q>]`, so it is
  offered as soon as work lands past the last reading of its own questions, and the tick's
  `RANGE` line names that range. A plain `live:head` row reads as in 1.11.0.
- **From Step 6 the gates read the readings.** The commit gate wants, for each question the
  rigor deals, a reading whose newest is not `result=fail`, or a newer waiver, and no declared red
  still owed. `current 8`, `close-out` and the integrate row ask one judge, which also wants each
  owed reading to cover the working head, the floor run and, when the project declares one, a
  passing release check at that head. A task row no longer closes on the word `critic` alone.
- **A release owes the checks your project declares.** `release-check: <command>` in
  `.bionic/config.yaml` declares one. `session-poker.sh release-check` runs it in the working
  checkout over the range since the nearest release tag (else the plan's `base-sha:`), with
  `BIONIC_CHECK_BASE` and `BIONIC_CHECK_HEAD` set, keeps its log under `record/`, and writes a
  `kind=check` fact, with `result=fail` when the command fails. `land` runs the same check over
  each landing's range and hands it `BIONIC_CHECK_TREE`, the piece's checkout. A project that
  declares nothing runs nothing and is asked nothing.
- **Close-out writes its own Step 9 line,** and the plan's optional `release:` field
  (`release: <version>` in its frontmatter) is the version written on the delivered line, the epic
  row and the continuation header. With no field no version is written; the tool's own version
  stays on `attested-by:`.
- **Work that is red by design can land, and the release waits for it.** A writer's brief may
  declare `Lands-red: <name>.test.sh until <ext:slug|approval:name>` with `Red-evidence: <path
  under record/>`. `land` then admits that one suite red, and writes the debt to the run's landing
  record before the merge; a merge that fails or is undone voids it. The debt is covered only by a
  green floor or task proof dated after the red landing (and after the approval, for
  `approval:`). While it is owed, the commit gate refuses from Step 6, and `current` refuses to
  close Step 5 or later, as a real commit at that step would be refused.
- **Each landing keeps the proof it read.** With a bound plan, `land` appends a
  `landed: row=… branch=… head=… merge=… at=…` header and the stamp lines it judged to
  `record/<plan>/landing-proofs.log`, in one write, before it removes the tree. No path of `land`
  removes or truncates that record.
- **A tree's record link stays out of your commits.** `spawn-worktree.sh create` adds `/.bionic`
  to the repository's `.git/info/exclude`, never to your `.gitignore`, so `git add -A` in a tree
  no longer stages the `.bionic` link it plants.
- **Setup offers working principles.** `/bionic:setup` offers a short, general set of working
  principles as one item, shows you the file and the whole text, and on your yes writes it between
  `bionic:principles` markers into your global `CLAUDE.md`. Doctor reports the block as present,
  absent, edited or malformed and changes nothing. Setup never replaces a block you edited without
  showing the difference and asking. Remove takes the block out by its markers, and deletes the file
  only when it holds nothing else.
- **Your shell rc: the markers are the whole rule.** Bionic's retired bare alias line is no longer
  removed by any door: setup, remove and doctor name it by line number, as bionic's old line
  outside its markers, for you to delete. A retired block is removed wherever it stands, unless the
  rc would not parse without it, as checked by the rc's own shell on a private copy; nothing in the
  rc is run. A block whose body you changed is left whole and named "changed since bionic wrote
  it", the `claude()` block included, by every door. A file that holds a NUL byte, cannot be
  read, or is a dangling link is named and never written. A CR LF rc keeps its CRs, and an rc with
  no final newline gets none.
- **The `claude()` block** in your rc now opens with `unalias claude 2>/dev/null || true`, as the
  upgrade note says. An alias of your own named `claude`, defined above bionic's block, stops having
  effect while the block is there. An alias defined below the block still wins. A block holding
  an earlier body of bionic's is rewritten where it stands, so your lines below it stay below. A
  `claude()` block you changed is never rewritten: it is left and named by its lines, and a block
  holding bionic's lines beside your own reads as already in. For a changed block setup asks
  nothing and writes nothing; it prints `bionic's block, left: lines A to B of <rc>`, then
  `it changed since bionic wrote it, so bionic leaves it as it is; bionic's lines are:` with the
  two lines for you to copy, and its summary says
  `edit lines A to B of <rc> by hand — bionic's block, changed since bionic wrote it`. Doctor shows
  a neutral row with no route to setup:
  `– claude() shell proxy  changed  lines A to B of <rc> — edit it by hand`. Remove, on both
  doors, under `--only` and under `--all`, leaves a changed block too: it asks nothing, keeps the
  block off `--all`'s page and names it, after the page's items under `--all`,
  `lines A to B of <rc> are bionic's claude() block, changed since bionic wrote it:` with
  `it is left as it is — edit it by hand` on the next line. It takes the block out only when its
  body is byte for byte one bionic wrote, or empty, and says before it asks that the block holds
  only bionic's lines.
- **Each dispatched agent has a scratch directory of its own,**
  `.bionic/tmp/scratch/<session>/<name>/`, named at start. Its start push is one string per file,
  each held under 9,500 characters so the harness never cuts it to a preview.
- **A `Files:` entry is a path or a refusal, never dropped.** A file at the repository root is
  spelled `./NAME`. Quotes, brackets or a trailing `;` around a path are read as the path, and a
  note goes after a trailing `#`. An entry that is not a path is refused with the spelling that is
  accepted.
- **An agent start that cannot be placed is not stuck.** A start is joined to its launch by its
  type when its id and name miss. An agent whose start could not be placed is refused a suite with
  a `session-poker.sh amend <agent id> --suites+ <suite> --reason '<why>'` line that runs as
  printed, and `amend` now takes an agent id. A start that comes late, after a permission prompt
  answered more than five minutes after the dispatch, is still placed on its launch, and is no
  longer placed on another late launch. The Patrol names a reader that started without its checks.
- **A wall is answered by a verb, not a line in your reply.**
  `session-poker.sh decline <id>[,<id>] '<reason>'` records why ready rows wait, in the run's fill
  ledger, which the turn-end wall and the tick read, and the fill refusal prints that command.
  `session-poker.sh budget writers=<n> '<reply>'` records your writer cap once in the plan, with
  your name; it only lowers the cap in force. The Patrol prompt moves to version 6. A turn that
  still writes the old `fill-declined:` line is not refused for it.
- **The task list is rebuilt at plan approval.** The doctrine says how, and the tick asks for it
  with `poker: RECONCILE — the plan moved from approval into Step 4 since the last tick: …` or
  `poker: RECONCILE — the ## Tasks table grew since the last tick: …`.
- **A suite's wait for a place fits its call.** `booked.sh --max-wait <s>` caps the wait, and the
  wall sets it from the call's stated timeout, less ten seconds. `BIONIC_SLOT_HELD=1` with no place
  named no longer lets a whole-machine run start beside another holder. A whole-machine suite that cannot
  settle runs once unbooked and reports `void`, whoever runs it, as the full runner does.
- **Refusals keep their words.** A refusal's first line over 100 columns has its fact cut to fit,
  ending in `…`. Every refusal prints, even when the temp directory is missing or cannot be
  written, and the evidence gate no longer writes files to stage its refusal.
- **The doctrine is rewritten inside its byte caps.** It states the three questions and the rigor
  table once, and says what each reader's walls accept.
- **Remove no longer uninstalls any tool.** `/bionic:remove` names each declared tool it finds,
  with the command to remove it by hand, and leaves it in place, from the plugin, per item and under
  `--all`: bionic keeps no record yet of what it installed, and it removes nothing it cannot prove
  is its own. The summary lists those tools under `left for you to remove by hand:`. A plugin
  bionic's own catalog installed is still offered, and removed on your yes.

Newly refused:

- A reader dispatch (`bionic:auditor`, `bionic:critic`, `bionic:reviewer`) with no `Questions:`
  line: `bionic: dispatch refused — bionic:<role> names no Questions: line (add the Questions: line)`.
- A `Questions:` set the plan's rigor does not deal that reader:
  `bionic: dispatch refused — <rigor> deals bionic:<role>: <set> (use that set)`; a reader the rigor
  deals nothing: `bionic: dispatch refused — <rigor> deals bionic:<role>: nothing (dispatch its holder)`;
  an unknown word: `bionic: dispatch refused — unknown question: <word> (use evidence/adversarial/structure)`;
  the line given twice: `bionic: dispatch refused — bionic:<role> has <n> Questions: lines (keep one Questions: line)`.
- A reader dealt more questions than its `Files:` line names records under `record/`:
  `bionic: dispatch refused — dealt <n> questions, names <m> records (one Files: record per question)`.
- A reader dealt `evidence` that declares more than three runs, its `Suites:` and its counted
  `Re-executes:` runs together:
  `bionic: dispatch refused — the total of <n> runs exceeds the 3-run cap (declare three at most)`;
  or one that declares nothing to run:
  `bionic: dispatch refused — the <role> declares nothing to re-execute (name one suite or run)`.
  Any `&`, `<(`, `>(` or line break in a declared command makes it a run, and file housekeeping
  alone is not one.
- A reader that named only a run and no suite, running a suite:
  `bionic: suite-run refused — allowed: none (run only the budgeted suites)`.
- A dispatched agent's suite when no suite set is recorded for it:
  `bionic: suite-run refused — no suite set is recorded for this agent (send main the suites you need)`.
- A `Files:` entry that is not a path: `bionic: dispatch refused — Files: names <e>, not a path (spell it ./<e>)`
  for a bare root file, and `bionic: dispatch refused — Files: <e> is not a path (drop it)` otherwise.
- A commit from Step 6 on while a question the rigor deals has no reading, or its newest failed
  with no newer waiver: `bionic: commit refused — a reading question is unanswered (record or waive each reading)`;
  and while a declared red is owed: `bionic: commit refused — a declared red is still owed (record a green run once cleared)`.
  When the gate's own check was killed or could not hand its refusal back, the commit is still
  refused: `bionic: commit refused — the evidence gate could not stage its refusal on its pipe (commit again)`.
- `current 8` while a fact the run owes does not hold at the working head:
  `poker: REFUSED — current: 8 is admitted only when every fact the run owes holds at the working head <head>, and these do not (facts_state):`,
  then each owed line. Close-out the same:
  `bionic: close-out refused — the facts the run owes do not all hold at the working head <head> (facts_state); record each with proof-add, or have the user waive a question — nothing was done`.
- `proof-add review` with `--question` for a record that is not one pass by the reader dealt that
  question, is named by another reader's row, says `scope: whole` while build rows are open or
  without reading from the plan's base, or for a plan with no `base-sha:` that is a commit. Each
  line names what to add or fix, and the plan is unchanged.
- A brief's `Lands-red:` line naming no blocker
  (`bionic: dispatch refused — Lands-red: names no blocker token (use ext:<slug> or approval:<name>)`),
  with no evidence (`bionic: dispatch refused — Lands-red: with no Red-evidence: line (add the Red-evidence: line)`),
  on a suite the row does not run
  (`bionic: dispatch refused — Lands-red: <suite> is outside Suites: (name a suite the row runs)`),
  given twice (`bionic: dispatch refused — the brief has <n> Lands-red: lines (keep one Lands-red: line)`),
  naming the full-suite runner
  (`bionic: dispatch refused — Lands-red: names the full-suite runner (name one <name>.test.sh)`),
  waiting on an approval the integrate row reads or no row reads
  (`bionic: dispatch refused — approval:<name> is read at integration (pick an earlier token)`,
  `bionic: dispatch refused — approval:<name> is read by no row (name one a row reads)`), or with
  evidence outside the record root
  (`bionic: dispatch refused — Red-evidence: is not under record/ (put the file under record/)`).
- `spawn-worktree.sh land` when the declared check fails over the landing's range
  (`reason=check-failed why=release-check`), when the check moved the target's head or left a
  tracked file changed (`reason=check-dirtied`), when the landing record cannot be written
  (`reason=record-unwritable why=proofs-unwritable`, before the merge), and when a declared red's
  debt cannot be written (`reason=debt-unwritten`). The full-suite runner is never honoured as a
  declared red.
- `spawn-worktree.sh land`, and the stand-down's landing, for a range that adds `.bionic` or any
  path under it, or changes what kind of thing `.bionic` is, `.bionic` in any spelling of case; a
  change to, or deletion of, a path the target already tracks there lands; nothing merges:
  `spawn-worktree: REFUSED reason=bionic-committed path=<path> commit=<commit> branch=<branch> onto=<onto> fix='git -C <tree> rm -r --cached .bionic, commit, say ready again' — a committed .bionic, merged, replaces the project's .bionic directory; nothing is merged, the tree is kept`.
  For a path added under a `.bionic` directory the target tracks, the fix takes that path alone out
  of the index and keeps the file: `fix='git -C <tree> rm --cached <path>, move <path> out of the
  tree, commit, say ready again'`.
- `session-poker.sh release-check` on a checkout with uncommitted changes, with no start for the
  release range or an empty one, and from a dispatched agent; `session-poker.sh proof-add check`
  (only `release-check` writes a check fact). A failing check prints its output and its log path.
- `session-poker.sh budget` above the cap in force
  (`poker: REFUSED — writers=<n> is above the cap in force (<cap>): budget only lowers it.`), and
  `decline` for a row that is not ready, with a blank reason, or with the placeholder the refusal
  prints in place of a reason.
- `session-poker.sh amend` that would change nothing.
- A shell rc or `CLAUDE.md` that holds a NUL byte, under setup, remove and doctor:
  `<path> is not text: it holds a NUL byte`.

Upgrade, for a plan already in flight:

- Upgrade the plugin before you run setup or remove again (the note at the top), and take the
  `claude()` item if setup offers it.
- An open plan needs no edit until its Step 6. There it meets the readings: dispatch each reader
  with its `Questions:` line, register each reading with `proof-add review … --question <q>
  --reader <name>`, or record your waiver with `waive`. Give the plan a `base-sha:` that is a commit
  if it has none, or its first reading of each question is refused.
- Re-arm the Patrol when the tick asks.
- You may add `release: <version>` to the plan's frontmatter, and `release-check:` to
  `.bionic/config.yaml`. You no longer write a Step 9 line by hand.

Fixes:

- `BIONIC_SLOT_HELD=1` with no place, the shim's wait, and a whole-machine suite run by a writer
  now behave as the booking bullet above says; these were three of 1.11.0's known limits.
- A commit refused by the evidence gate always prints its own reason, even when a hook killed
  earlier left a `bionic-gate-<pid>` entry in the temp directory. Such an entry left by 1.11.0 is
  inert now and can be deleted.

Known limits, carried to the next release:

- No door removes a line of your rc that stands outside a pair of bionic's markers, the retired
  bare alias included: it stays until you delete it, and doctor goes on naming it by line number.
- An intact block you moved to stand right after your own line ending in `&&`, `||`, `|` or a
  backslash, after a zsh short loop head (`for i (…)`, `repeat N`) with no body, or inside your own
  here-document or string, is removed if the result still parses, and your surrounding code then
  reads differently.
- The `claude()` block's first line does not help where the block has been moved inside your own
  `if` or function, where `unalias` is itself aliased, or under bash where `claude` is a readonly
  function: the start-up error stays, as it did with the old body.
- A `claude()` block you changed is removed by no door: it is yours to edit by hand. While an
  alias named `claude` stands above it, every shell start keeps printing the error until you do,
  unless the block still holds bionic's `unalias` line above its `claude()` line.
- Nothing judges a `git merge` you type by hand into the integration branch. The documented
  merge comes after `current 8` has asked the judge, and close-out asks it again after any merge.
- An rc whose every line ends in CRLF is read as holding no block, and setup appends a second one;
  convert the file to LF line ends first. This is older than this release.
- Retired in 1.13.0: bionic now keeps a record of what it installed, and remove acts on it (see that
  entry). A tool installed before that release has no line and is named for removal by hand.
- The standalone remove (the script run alone, with no `lib/` beside it) cannot read the tool
  table: its `--all`, when nothing else of bionic's is left, calls a machine with tools on it
  "already clean", and an `--all` you decline names no tool. Run `/bionic:remove` from the plugin
  and answer per item to see the by-hand list.
- A read-only rc that holds bionic's retired environment block, with a declared tool present and
  nothing else of bionic's left, makes `--all` count "1 skipped by you" for a question nobody could
  answer; nothing is lost, and the block is yours to delete by hand.
- A lone `excalidraw-venv.lock.sha256` with no venv beside it, which is what deleting the venv by
  hand leaves, reads "(not installed) — already clean" while the file stays; delete it with
  `rm ~/.local/share/bionic/excalidraw-venv.lock.sha256` (under `$XDG_DATA_HOME` if you set it).
- When SHELL is neither zsh nor bash, the plugin's remove asks about bionic's claude() block and
  then cannot rewrite the rc, while the standalone remove removes it; no line is lost either way.
- The verbs only the main session may run are guarded by a reader of the command's text, so a
  path to the hook held in a shell variable steps round that guard.
- The landing record is not for a network filesystem: its one-write append assumes a local disk.
- The landing record is believed as it is read: a record made unreadable, a landing killed between
  git's publish and its exit, or a disk filling at one instant can hide a declared debt. The commit
  gate's debt check is coarser than the judge's, as `operational-rules.md` says, and integration
  waits on the judge: `close-out check` can print "gate: ok" beside the judge's "WOULD REFUSE"
  while a declared debt is open. The judge's line is the one that holds, and `close-out run`
  refuses.
- Two landings started into one checkout at the same moment can leave that checkout dirty or both
  be refused; nothing is lost. Land one tree at a time. The repair is `git -C <checkout> reset
  --hard` (or removing the one untracked file), then land again. This is older than this release.
- A tree branched before its target stopped tracking `.bionic` is refused until it merges the
  target, as the refusal's fix says.
- Session start's sweep of dead sessions slows when many of them each left start files behind
  (the sweep matches those files per session); a later release indexes them once. The sweep stops at
  10 seconds, which is also the SessionStart hook's timeout, so a sweep that reaches its bound takes
  the whole hook past the CLI's limit: the session loses its start page rather than starting late.
- The dispatch wall can count as a reader's record a path the fact verb then refuses: a path at
  the system's length limit, one that holds a space, or one that opens with two slashes. The verb's
  refusal names it.
- A reader whose start could not be placed is held to three suites and runs only when that start
  recorded its role; with no candidate launch, or candidates all dealt the same questions, it is
  counted as a writer until it is placed.
- A late start that arrives while a fresh launch of its type is waiting is joined to that fresh
  launch.
- This repository's own release check, a scan for names of other projects, has open items for its
  next revision, and an entry of four or more words costs steeply (about 18 s for four words over a
  megabyte).
- Names of other projects in comments and test identifiers are gone from the tree at this release.
  Older versions of those files, in the history and in the tags of 1.11.0 and earlier, still carry
  them.
- Carried to the next release: a suite call's stated `--max-wait` is not clamped to the longest
  wait the harness grants, so a wait above that limit can be cut short by the harness rather than
  by bionic; and a `BIONIC_SLOT_PLACE` named by another live process is trusted. Neither loses a
  result: a cut-short run is reported as such.
- Carried to the next release: a suite run through a `for` loop over test files, or by
  `bash "$f"` with the script in a variable, is not recognised as a suite run, so the reader's
  suite cap and the budget arm do not see it. The cap is enforced on commands written plainly, as
  the doctrine asks.
- The limits listed for 1.11.0 still hold, but for the three on booking, which 1.12.0 closes as
  far as the limit above on `--max-wait` says, and those listed for 1.10.0 and 1.9.0 stand as
  1.11.0 left them.

One rule for review (ADR-044): rigor is the number of independent minds. Every run that ships code
is read for the same three questions; the rigor decides how many readers share them; each answer is
a fact a gate reads; and a release waits for the checks its project declares.

## 1.11.0 — 2026-10-04

A run that does each necessary thing once, and as many things at once as the machine carries.
Work now starts when what it reads exists, not when a step number allows it; the full suite runs
once, on the head being released; the design is approved once; and a suite run books a place on
the machine as it starts instead of being counted when an agent is handed out. This is a minor
release: it adds verbs, an optional plan column and behaviour you will notice, refuses some actions
that were not refused before, and asks one upgrade step of a plan already past Step 4. Nothing a
project already relies on is removed, and `canonical_sdlc_version` stays 14.

What you will notice:

- **Work starts when what it reads exists.** A plan's `## Tasks` table may carry an optional
  `reads` column, found by its header name anywhere in the header. A row lists what it must have
  before it is ready, comma-separated: a path in the `Files` grammar, `head`, `record`,
  `proof:<kind>`, `approval:<name>` or `ext:<slug>`, and `live:<artifact>` for a read that is
  satisfied by what exists now. An empty cell takes the kind's default: build `approval:plan`;
  verify and doc `approval:plan, head`; review `approval:plan, live:head`; integrate
  `proof:floor, proof:review, head`, so integrate also waits for any open build. A document row at
  Step 7 or later is the release and must name the approval it waits for (`approval:release`, or
  `approval:plan` for a document that needs no release): the validator refuses it otherwise, and it
  is never offered before that approval exists. The edges between rows are computed from these cells and never
  written: in a table with `reads`, the `deps` cell holds only `ext:` tokens. The rule that every
  verify, review and doc row waits for every build row is gone, so a review that reads only the diff
  no longer waits for verification. Two rows that write one file run side by side and reconcile on
  landing; a `Files` entry ending in `!` marks a file that cannot be merged, and a second writer of
  it waits for the first to land. `task-add` takes the cell as an optional last operand, and
  `task-set <id> reads=<…>` sets it on a row later; a `reads` operand for a table with no `reads`
  column is refused, with a line that says so. A table without the column reads each `deps` id as
  "wait for that task to land", as before, and a build added mid-run still holds the full run, as in
  1.10.0.
- **Your approvals are the only step barriers.** No row is ready until the plan's `approved-by:`
  line exists. Any other approval a row reads, such as `approval:release`, is recorded with
  `session-poker.sh approve <name> '<reply>'`, your reply quoted verbatim, as an
  `approved: <name> by <who> <ISO-UTC> "<reply>"` line under `## SDLC State`. Only the
  orchestrator can run it, and it refuses a name no open row reads, a second recording of one name,
  and `plan`, which is the `approved-by:` line.
- **The Patrol says why each row waits.** For every pending row it did not offer, the tick prints
  `poker: WAIT <id> — <reason>`: the unmet read and the row that writes it, the `ext:` token, or the
  approval. `poker: CHAIN <id>→<id>… (<n> min)` names the longest remaining chain, and
  `poker: RANGE <id> <range>` names the commits an offered review reads. With every agent busy and
  nothing ready it prints `poker: WAITING — <n> running, nothing ready`, and a turn that sees only
  that line, or `unchanged`, owes nothing more. A task-list refresh is owed only when a row's status
  or the ready set changed, and the tick says so on a `poker: RECONCILE` line. A read-only row (a
  review, a research pass) no longer takes a writer place. A fill or stand-down decline stands until
  the set it answered changes. The first tick of a run, before anything is dispatched, names the
  ready work and prints the same lines, and when it names work it ends in `FILL`, as every later
  tick does. The Patrol prompt moves to version 5, and a Patrol started with an older prompt is told
  once to re-arm.
- **A launch moves its own plan row.** When bionic records the launch of a named agent, it sets that
  agent's plan row `active` and adds the row's dispatch-ledger line itself, one write for a batch of
  launches. The doctrine no longer asks for `task-set` and `ledger-add` by hand at dispatch.
- **Reviews follow the build.** A review row with the default `live:head` read is offered as soon as
  landed work exists past the last review proof and no review is open, and it reads only that
  difference. Recording the review with `session-poker.sh proof-add review <record>` returns the row
  to pending, so the next landing offers a review of the new difference alone. A final review that
  reads the settled `head` covers problems across tasks. `proof-add review` refuses a record whose
  `reviewed: <a>..<b>` range starts at no commit, starts at a commit that is not on the history of
  its end, or starts past the last review proof (or, for the first review, past the plan's base), so
  that what landed in between is unread; each line names the range to read instead. When a review
  is idle, with nothing landed past its proof, it no longer holds integrate back.
- **A proof names the head it read, and the full suite runs once.**
  `session-poker.sh proof-add <floor|review|task> <evidence under record/>` writes
  `proved: kind=<kind> head=<40-hex> at=<ISO-UTC> evidence=<path>` under `## SDLC State`. The head
  is the one the evidence names, a run log's `head=` header or the end of a review's
  `reviewed: <a>..<b>` line, and is never typed. Step 5 runs the full suite once, on the head being
  released, and records it with `proof-add floor <log>`. After that a later change is proved by the
  suites your file-to-suite map (`impact-command:` in `.bionic/config.yaml`) names for it, and a
  full-run dispatch goes ahead only when the change cannot be bounded: a commit from outside the
  run, a changed file the map answers with every suite or with none, a change to the full-suite
  runner or the shared test library, or no floor proof yet. Integration waits for that run: while
  the change past the last floor proof cannot be bounded, the integrate row is not ready, and the
  tick's `WAIT` line gives the reason and asks for a full run on the head, recorded with
  `proof-add floor`. A project with no `impact-command:` gets every full run it asks for, as before,
  and its integration waits for a full run on the head whenever anything changed past the last one.
  The `regression-cause:` line is no longer asked for or read.
- **A task lands on its own green run.** `spawn-worktree.sh land` no longer needs a full run. It
  reads the stamps the booking shim (next bullet) leaves in the tree's own git directory, and refuses
  a tree whose stamped suite run was at another head, on a dirty tree, or red, and a tree that
  lacks a landed commit touching a file it also changed; a tree that lacks only commits to other
  files lands. After the merge it checks that neither branch moved and that the merge is its own.
  If one did move, it undoes only the merge it made and keeps the tree. If it cannot prove the merge
  is its own, it undoes nothing. Either way the refusal says where the checkout stood.
- **A red suite stays red at the land.** A stamp names the suites its command ran. The land takes
  the newest stamp of every suite at the tree's head, and each must be green on a clean tree, so a
  red suite followed by another suite's green run is refused, and the refusal names the suite
  (`suite=<name>`). A suite that never got to run (no place, stopped at its limit, signalled while
  it waited) stamps the end it reached, so the land refuses the tree until that suite is run green.
- **A suite run books a place on the machine.** The Bash wall runs every suite-class command, on any
  thread, through `scripts/booked.sh`. The shim takes one of N machine-wide places (the store is
  `~/.claude/bionic/slots`, or `BIONIC_SLOTS_DIR`; N is the suite count bionic's machine probe gives,
  or `BIONIC_SLOTS_N`). When none is free it waits and names the holders, and it gives up after
  `BIONIC_SLOTS_MAX_WAIT` with exit 69. It stamps the head, the dirty count and the exit code, and
  releases the place on every exit. The stamp goes into the git directory of the tree the suite ran
  in when the command leads with a literal `cd <tree>`, which is how a task tree is run from the
  main checkout (the wall passes the shim `--stamp-dir <tree>`); any other command is stamped where
  the call started. A run inside a booked run books nothing. A timing check
  (`BIONIC_QUIET=1`, or `# runner: solo` in a suite's first 30 lines) takes the whole machine,
  starts on a settled load, and is retried up to twice and reported `void` when the load rose; a
  void over a failing run is still a failure. Dispatch no longer counts suite runs when it hands an
  agent out, and a read-only agent asks for no worktree. A wrapped suite runs in a child shell, so
  its `cd`, aliases and functions do not carry to the next call; prefix `BIONIC_SLOT_HELD=1` to run
  one exactly as typed, unbooked and unstamped.
- **A short command stays on your thread.** The farm-out wall lets a suite- or build-class command
  run on the orchestrator's thread when the Bash call's own `timeout` is at most the short limit:
  120000 ms by default, `farm-out-short-ms:` in `.bionic/config.yaml`, where `0` turns the pass off.
  A short suite needs at least 6000 ms and is stopped at the limit, the wait for a place included,
  with a line that says it belongs in a subagent (exit 124); a short build runs as typed. A longer
  or untimed command is refused as before, and the refusal's first fix is now the timeout. The
  advisory printed for every `npx` and `uvx` one-liner is retired.
- **The design is approved once.** The interview closes on the Step-2 card, whose approval is the
  one approval of the design. It opens with the Goal, Approach and "Worth your eye" (each call with
  its risk), prints each decision's label once, names the spec, every ADR, the design ledger and the
  requirements by path, and shows the ownership table only on `show ownership`
  (`card.sh step2 <spec> ownership`, and `card.sh step2 <spec> evals <REQ-id>` for one
  requirement). The Step-3 card approves the plan and the matrix only: it cites the design by path,
  lists each task with the requirements it serves, and shows the longest chain with its minutes and
  the peak width where the eval counts and the purpose used to be.
- **Each thing is ordered once.** The auditor runs one pass. One reviewer takes all six review axes,
  and a security or performance flag adds one reviewer each. The critic no longer carries the
  reviewer's duplication axis or the auditor's evidence check. The doctrine no longer orders a skill
  re-invocation on resume, a hand dry-run before a step advance, or a reconcile at every turn end.
  Step 3 tells the planner to split the longest chain where it can, and names the five events that
  cause a re-plan: a finding, a red test, an approved scope change, a task overrunning its size, and
  a report that names follow-up work. A re-plan is done with `task-add` and `task-set`.
- **Shorter evidence and briefs.** A report may cite the path of a saved log in place of pasted
  output. A brief's progress-file and cadence lines are marked as needed only for tasks of 15
  minutes or more. The doctrine shows the one-line landed-task evidence line the commit gate
  accepts, and the Step-0 template no longer repeats `parallel-budget` or `integration-branch`. The
  suite capture shape is now
  `set -o pipefail; <command> 2>&1 | tee "$LOG"; rc=$?; echo "rc=$rc" >> "$LOG"; exit $rc`, so the
  command exits with the suite's own code, which is what `land` reads from the stamp.
- **The run reports its idle time.** `session-poker.sh fill-report` adds `idle minutes:` (minutes a
  ready row waited while there was room for it) and `peak width:`, both from times the fill ledger
  and the roster wrote, never from plan text.

Newly refused:

- A commit judged against Step-5 evidence that carries no `head:` line, or a `head:` that is not a
  commit, or one the release head does not contain. The fix is `head: <sha>`, the commit the tests
  floor ran on.
- A full-run dispatch on a head that already has a floor proof (`head <sha> is already proved`:
  run nothing); after a bounded change (`bounded: <suites>`: the refusal prints the `Suites:` line
  to dispatch instead); and while a row the floor waits on is not landed and writes tracked files
  (`rows write tracked files: <ids>`: land them, then dispatch it).
- A writer dispatch for a row that reads an approval nobody gave (`row <id> waits for
  approval:<name>`). Once you have replied, `session-poker.sh approve <name> '<reply>'` records it.
- `spawn-worktree.sh land`, with these reason words and fixes: `not-current` (merge the branch it
  lands onto into the tree, re-run its suites, land again); `stale-proof why=head|dirty|red|unreadable`
  (re-run the tree's suites at its head, land again); `onto-moved`, `branch-moved` and `onto-switched`
  (the merge is undone and the tree kept; land again); `merge-unproven` and `onto-detached` (nothing
  is undone; the line says what to check out). An undo that could not finish says `undo=failed` and
  prints the step to take by hand.
- A writer dispatch when the plan's approval cannot be read, because the library that reads it
  cannot be loaded (`the approval reader lib/fill.sh cannot be loaded`). Reinstall the plugin.
- A turn end, once, when the launch record could not write a launch into the plan ("a launch is not
  recorded in the plan": run the commands `session-poker.sh launch-sync` prints), and when a ready
  read-only row has room to run.
- In a table with a `reads` column: a task id in `deps`, a cycle of reads, an open document row at
  Step 7 or later that reads no approval (the line names the fix: `approval:release`, or
  `approval:plan` for a document that needs no release), and a `reads` operand to `task-add` on a
  table that has no such column.
- `session-poker.sh proof-add review` for a record whose `reviewed: <a>..<b>` range starts at no
  commit, at a commit that is not on the history of `<b>`, or past the last review proof so that
  what landed in between is unread. The line names the range to review.
- A land of a tree whose newest stamp of any suite at its head is red, is dirty, or is the end of a
  suite that never ran; the refusal names the suite.
- `session-poker.sh approve` and `proof-add` from a subagent: like the other plan verbs, they are the
  orchestrator's. `proof-add` also refuses evidence that is a symbolic link, is outside `record/`, or
  does not exist.

Upgrade, for a plan already in flight:

- Before the plan's next commit that is judged against Step-5 evidence, add `head: <sha>` to that
  evidence: the commit its tests floor ran on. After the full run, record it with
  `session-poker.sh proof-add floor <log>`, or every later full run is still admitted.
- Re-arm the Patrol when the tick asks.
- You may leave alone: a `## Tasks` table without `reads` (its `deps` keep their meaning), any
  `regression-cause:` lines (no longer read), and the `suites=` field of `parallel-budget:`.

Fixes:

- A refused `spawn-worktree.sh land` no longer removes the tree's `.bionic` link before it refuses
  (the limit 1.9.0 carried); the link is dropped just before the tree is removed.
- Close-out accepts a task-scale plan on a branch of any shape, such as `fixit/x`; every other scale
  keeps the `wave/<digits>-<slug>` rule.
- `land`'s busy-suite check matches a running test runner, even behind combined shell options, and
  no longer a command whose text merely mentions it.
- A suite on a new line after a command chain no longer passes the farm-out wall unseen.
- Creating a task tree no longer leaves the main checkout reading as dirty. When nothing ignores the
  tree's parent directory, `spawn-worktree.sh create` writes it into the repository's local,
  untracked exclude file (`.git/info/exclude`), once; it never edits `.gitignore` or a tracked
  file. A full run could not be recorded as the floor while the checkout read as dirty. `remove`
  leaves that one line, which hides a directory that is empty or gone.
- A bounded probe looks ten times in its first second instead of once, so a probe that answers at
  once no longer costs a second of every doctor run and session start.

Known limits, carried to the next release:

- A suite command that swallows its own exit code (one ending in `; echo done`, or `|| true`) exits
  0, so its stamp records a pass and `land` lets the tree through. Use the capture shape above.
  Two suites in one command have one exit code between them: non-zero marks both red, and in
  `a; b` the code of `a` is lost.
- A green full run does not clear an earlier red stamp of a single suite; that suite must be run
  green by itself. A runner command is named by its own text, so `pytest` and `pytest -q` are two
  suites, and only a re-run spelled the same way clears its red. A command the wall cannot name (its
  text holds a `$`, or runs past 100 characters) or whose suites are joined by anything but `&&`
  (`a || b`, `a; b`, a pipe) stamps no suite, and such a stamp, red or dirty at the head, is cleared
  only by a new commit and a re-run.
- A `cd` the wall cannot read as a literal (a variable, `pushd`, a subshell or a pipe ahead of the
  suite) stamps the checkout the call started in, and a run under `BIONIC_SLOT_HELD=1` stamps
  nothing, so both leave the task tree without a stamp. `land` reads a tree with no stamp as a tree
  where no suite ran, and lands it.
- A suite that was red at an older head and never run again at the tree's head is not seen by the
  land, which reads the stamps at the head.
- A row that reads something it did not declare can start too early. Its work may be wasted, but it
  cannot land wrongly, because the land checks the combined state.
- `proof-add floor` accepts only a log in the shape bionic's own test runner writes (a
  `head=<sha> dirty=<n>` header, a `Gating: <n> passed, <m> failed` verdict) from a whole run of
  `tests/*.test.sh`, and it refuses a run when a suite file there is gitignored. Without a floor
  proof, every full run is admitted.
- "The full suite runs once" takes effect only where the project's runner writes the log header the
  proof verb reads and the project names an `impact-command:` in `.bionic/config.yaml`; elsewhere
  every full run is admitted, and integration waits for a full run on the head whenever anything
  changed past the last one, which costs time and never a missed run.
- A change that merges a branch which was deleted afterwards reads as part of the run, so it is
  bounded where it should not be. Any tag inside the proved range draws a full run.
- The ready set reads a bulleted `- approved-by:` line as the plan's approval, and the commit gate
  does not. Write the line unbulleted.
- A tick digest written by hand under the project's state can make the turn-end wall skip a review
  it owes.
- An agent name freed and dispatched again within the same minute as its earlier ledger line can be
  read as already recorded, so its row is not set `active`.
- `land`'s busy-suite check does not see a test runner whose path holds a space.
- When the newest stamp of a suite is a passing run reported `void`, or the end of a suite that
  never got to run, `land` refuses it as `why=red` and says "make the suites green": the refusal is
  right, and its words are not.
- `BIONIC_SLOT_HELD=1` with no place lets a whole-machine timing run start while another agent
  holds a place. (Fixed in 1.12.0 for a run that names no place.)
- The shim may wait for a place longer than the Bash call's own timeout, which moves the call to
  the background on a busy machine. (Fixed in 1.12.0: the wait is capped from the call's stated
  timeout.)
- A suite marked `# runner: solo`, run by a writer on a machine that never settles, exits 69 where
  the full runner would run it once and report it `void`. (Fixed in 1.12.0: the writer runs it once
  and reports it `void` too.)
- A review row that is idle at a run's end stays pending, on the WAIT and CHAIN lines, until you set
  it landed or dropped.
- The full-suite runner must be dispatched in the background, as every dispatch must. Dispatched in
  the foreground, its own full run is refused with "no set was recorded for this agent", because a
  launch is recorded only when the dispatch call returns; 1.10.0 behaves the same.
- Each Bash call forks one more process than in 1.10.0, each tick and each turn end spends about
  0.4 s recording launches, and the plan-row verbs take 0.75 to 0.87 s on a loaded machine
  against a one-second budget; `proof-add review` takes 48 to 99 ms more for its range check.
- The limits listed for 1.10.0 still hold, and of those listed for 1.9.0 only the one about a
  refused land is closed.

One rule for what may start (ADR-043): work is scheduled by what it reads, and a proof names the
code state it read. A unit is ready when what it reads exists; your approval is an input only your
reply writes; what is unproved is the difference since the head a proof names; capacity is booked
when it is used; and tasks that share a file run side by side and reconcile on landing.

## 1.10.0 — 2026-10-04

A run that is never left waiting on a dialog. In a session engaged with a bionic run, in bypass and
auto mode, bionic now answers Claude Code's permission question itself: yes when everything the
call writes or deletes is inside the asking agent's own workspace, no with a line that fixes it
otherwise, and no for anything kept for you, which reaches you once through the Patrol. This is a
minor release: it adds a capability and refuses some actions that were not refused before, and
nothing a project already relies on is removed.

What you will notice:

- **bionic answers the permission question in an engaged run, in bypass and auto mode.** Where
  Claude Code would put a "may I run this?" dialog in front of you, bionic answers it, so a lead
  or an agent working while you are away is not stopped until you come back. A yes covers that
  one call. A no is a message the agent reads: it says what bionic could not place, names the
  workspace, and gives one next step, and the agent carries on. Once a session is engaged, in
  either mode, a failure inside bionic answers no and says what failed; it never answers yes.
- **What is allowed: work inside the asker's own workspace.** The lead may write and delete in
  the run's checkout, the worktrees this session created, the session scratch directory, and the
  run's record directory and plan files. An agent given a worktree may write and delete in its
  own tree and the scratch, and write, but not delete, in the run's record directory. A read-only
  agent may write and delete in the scratch, and write its declared report when that report lies
  in the record directory or the scratch. A plain read is allowed unless it reaches a credential
  store. Paths are compared after links and `..` are resolved, so a link that leads out of the
  workspace does not count as inside it. No one deletes a workspace's root itself (the asker's
  tree, the checkout, the scratch). When a run works in the project's main checkout, that checkout
  does not grant the project's shared `.bionic`, `.worktrees` and `.git` directories, and bionic's
  own state files are in no workspace.
- **What is denied, with a fix.** Anything bionic cannot show to be inside the workspace: a
  target outside it, a target it cannot read (a variable, a glob, code handed to an interpreter
  such as `python3 -c`), a command over 64 KB, or one with more than 200 targets. The fix is one
  step the asker can follow: put the commands in a script file in the scratch directory and run
  it with `bash`, write the file under the workspace instead, or leave the file and ask the lead
  (you, when the asker is the lead) to remove it.
- **What is kept for you.** Everything that leaves the machine (`git push`; `gh pr`, `issue`,
  `release`, `repo` and `api`; `npm`, `pnpm` or `yarn publish`; `cargo publish`; `gem push`;
  `twine upload`), credentials (`gh auth`, `npm login`, `security`, and the common credential
  stores), production infrastructure (`terraform`, `kubectl`, `vercel`, `aws`, `gcloud`, `az`) and
  those tools' billing commands are never allowed by bionic. The denial names the category and
  offers no workaround. bionic records the request, and the lead's Patrol tick prints it once as
  a `poker: GATE <asker> — <category>: <command>` line, so the lead raises it with you once,
  through your own notify channel. bionic sends no notification itself. The Patrol prompt moves
  to version 3, and a Patrol started with the older prompt is told once to re-arm.
- **It works inside Claude Code's permissions, never around them.** bionic answers only what
  Claude Code asks, and only in bypass and auto mode, the two modes in which you have told Claude
  Code not to ask. In default, accept-edits and plan mode bionic answers nothing and the dialog
  reaches you exactly as in 1.9.0, because the mode is your answer to how much you want to be
  asked. Your permission mode, your own allow, ask and deny rules, and every call Claude Code
  settles itself are untouched; an answer persists nothing and writes no setting. A session that
  has not engaged a run gets the stock dialog as before, and a tool whose job is to ask you
  something (a question, a plan approval) is never answered by bionic.
- **Every answer is logged.** One line per answer goes to `permission-answers.log` in the
  project's log directory under your home (`~/.claude/logs/<project>-<checksum>/`, beside the
  audit log): the time, the session, who asked, the tool, the decision, the reason, and the first
  120 characters of the command or path. An allow that cannot be written to the log becomes a
  denial. `/bionic:doctor` gains a `permission answers` row that says on or off and names the
  log's path, and its walls count includes the new hook.
- **One switch, declared on the Step-0 card.** The card gains a `permissions` line, `answered
  from the run's workspace | off`, and approving the card is the consent.
  `permission-answers: false` in `.bionic/config.yaml` turns answering off. Only that literal value
  does; any other value, or no key, leaves it on.
- **A worktree is recorded for the agent it was made for.**
  `spawn-worktree.sh create <base-sha> <branch-name> [worktree-parent-dir] [--for <name>]` records
  the new tree as that agent's workspace, and the dispatch rules tell the dispatcher to pass the
  name it gives the agent. A named create with no session to record into is refused before any
  tree is made. An agent with no recorded tree, or one dispatched without a name, is answered as a
  read-only agent.
- **Command words are read the way the machine resolves them.** On macOS's case-blind filesystem
  `RM`, `SUDO` and `GH` run rm, sudo and gh, so the walls and the permission answers now read every
  command name they recognise in any letter case, as 1.9.0 did for `git` alone. A word that is
  only a shell builtin or keyword (`exec`, `eval`, `cd`, `source`) keeps its case, because the
  shell runs nothing for `EXEC`: `EXEC git push` pushes nothing, and is not read as a push.

Newly refused, when Claude Code asks about them in bypass or auto mode:

- A command that makes a link (`ln`) is denied with a fix, and so is every write, delete and read
  after a `cp` or `mv` in the same command, `mv a b && echo x > log` included. What was copied or
  moved may be a link, and bionic resolves paths before the command runs, so it cannot tell where
  a later path leads. Two calls, or a script file, do the same work.
- A credential store is refused through any path that reaches it: `~/.ssh`, `~/.aws`,
  `~/.config/gh`, `~/.gnupg`, `~/.config/gcloud`, `~/.azure`, `~/.kube/config`,
  `~/.docker/config.json`, `~/.cargo/credentials.toml`, and `.netrc`, `.npmrc`, `.pypirc`,
  `.git-credentials` and `.env` files, whether named directly, through a link or a `..`, in any
  letter case, as the source of a copy, or inside a recursive read of your home directory, of a
  directory in it that holds a store, or of `/`. This holds for the Read tool as well as for Bash.
- A recorded worktree counts as an agent's workspace only when git lists it as a linked worktree
  of the repository. A line in the workspace record that names any other directory, the main
  checkout or a directory above it among them, is skipped.

Fixes:

- Reading every command name in any letter case closes two ways past the walls: a subagent's
  `BASH session-poker.sh amend …` reached the amend, and `ENV -C <repo> git commit` skipped the
  commit gate.
- The two new per-session files, the workspace record and the gate requests, are swept with the
  rest of a session's state.

Known limits, carried to the next release:

- bionic reads only the call it is asked about. A command it denied, written into a script file
  as the fix says and run with `bash`, runs without bionic reading what the script does.
- In bypass and auto modes Claude Code can draw its stock dialog for a fraction of a second while
  the answer is worked out; the answer replaces it.
- In auto mode Claude Code refuses a background teammate's command itself, before any question,
  so bionic is never asked.
- In bypass mode Claude Code asks nothing for an ordinary command with literal paths, so bionic is
  consulted only for the shapes Claude Code still asks about, such as a script whose target is a
  variable.
- Every asker shares the session's one scratch directory, so an agent may write and delete another
  agent's scripts there.
- A reserved denial tells the asker to report it to the lead, even when the asker is the lead.
- The memory-store wall compares the path's letter case, so a capitalised spelling of the store's
  path passes it on a case-blind filesystem.
- A recursive read of a project tree that holds a `.env` file is allowed; only a recursive read of
  your home directory's stores, or of `/`, is refused.
- Answers are measured for subagents and in-process teammates; teammates in split panes are not
  measured. When Claude Code's question carries no scratch path, as in one headless shape, the
  scratch is not part of any workspace.
- The limits listed for 1.9.0 still hold; none was worked on in this release.

One rule for every answer (ADR-042): a run's authority is a chain of grants. You grant the run by
approving it, the run grants each agent a workspace, and no grant is wider than its parent. A guard
fails closed by direction: a yes needs the path exactly as recorded, a no matches every spelling
that could reach the protected place, and the only error left is refusing something harmless.

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
