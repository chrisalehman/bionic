# Changelog

Earlier releases are recorded as git tags (`v1.4.3` … `v1.8.3`) rather than in this file,
which starts at 1.8.4.

Versioning follows semver from 1.9.0 on:
- **MAJOR** for a `canonical_sdlc_version` bump or an artifact a user must migrate.
- **MINOR** for new capability.
- **PATCH** for a fix, including deleting a check or verb that was itself the defect.

## 1.25.0 — 2026-10-21

This is the sitrep owes release. The sitrep tells the user what they owe. It is a card drawn by the one card
renderer, the same one the Step 0 to 3 cards use (D1), and the release approval card moved onto that renderer too
(Δ2). The verb gives facts and no page: `sitrep` prints a fact sheet of measurements, each naming what it measures, its
unit and its source (D7), and the model writes every row of the card from it (D1, reopened as Δ17). The Metrics are
numbers and the Assessment is judgment: a grade by pace, weighed against six questions (D2). Code checks what must
never be wrong against the sheet the judgment was written from: every ask, step and open task is on the card, no number
is one the sheet lacks, no line is wider than 100 columns, and the sheet is under ten minutes old (Δ19). Every ask
belongs to the run, in one register that every session of the run writes and reads, so a card drawn by any session shows
every ask; the 8:14 AM page that said "Nothing" over a held merge cannot recur (D3, ADR-069). The four run states a
person can owe something in (a failed review, a release card waiting on its reply, an open stop-rule question, and
nothing owed) are rehearsed with the real tool in a sandbox, and their cards are kept (D5). The words are one
vocabulary on every surface the user reads: "review", never "reading" or "reader", and a goal nobody measures is "not
measured". This is a minor release by the policy above: the register, the rehearsal and the card check are new
capability, and no verb is removed. `canonical_sdlc_version` stays 14.

**Migration.** Rows that changed what a script may meet:
- T1: an ask of a run lives in `record/<run>/asks.state`, one register per run, in the line format of the session
  store (`owed/v1`). A session bound to a run writes and reads it, close-out's stand-in sessions included; read it
  through `owed_file`, never through `owed-<sid>.state` by path. With no run open an ask stays in the session's own
  store. Asks raised before 1.25.0 are not moved into a register.
- T22: the handoff's State writes `written:` as a local 12-hour clock time (`3:00 PM`) and an `instant: <ISO>` line
  beside it. The STALE reader takes `instant:` first and falls back to an ISO `written:`, so a handoff written at
  1.24.x still reads.
- T24: `sitrep card` takes the judgment as rows: `call:`, `task: <label>: <text>`, `metric: <Label>: <text>`,
  `grade:`, `point:`, `ask <key>[, <key>]: <text>`, and one to three `close:` rows. It draws only from the sheet that
  `sitrep` last saved under `.bionic/tmp`, and refuses when that sheet is ten minutes old or more; the asks it checks
  are read fresh. A card that fails a check prints its reasons and none of itself.
- T25: the sheet's `metric.*` lines are gone. The measured lines of the sheet's definitions page replace them (see
  `sheet-definitions.md`): clock, work, pace and close, correctness, waste, goals and asks.

### Asks belong to the run (D3, ADR-069)

- T1 (`T1-register.md`): the register, and the release approval card offering a waiver for every ask recorded for the
  run, not only the caller's session.
- T2 (`T2-asks-raised.md`): every ask is recorded when it is raised. A refused close-out holds the merge as an ask with
  its reason; a failed review is an ask from the moment its result is recorded; a stop-rule call and a carried gap have
  verbs; a decision's wait line names every row, merge or release held on it.
- T13 (`T13-stragglers.md`): the readers and suites that went to the session file by path now go through the register.

### The sitrep is a card of measurements and judgment (D1, D2, D7, Δ17, Δ19)

- T3 (`T3-fact-sheet.md`): the verb prints a fact sheet, local 12-hour times throughout; the Score indicators, the
  reading rows and the grade verb are deleted with their writers and tests.
- T5 (`T5-sitrep-card.md`): the seven-section card and its check at the shared 100 columns: Call to action, Task list,
  Metrics, `Assessment: <grade>`, Blocked on you, Predicted close.
- T4 (`T4-release-card.md`): the release approval card is drawn by `card.sh release` on the same renderer, and says
  when the release changed the release check. The verb's own page renderer is deleted.
- T24 (`T24-model-rows.md`): the model writes every row; code draws the bullets and icons, capitalizes each row, and
  refuses a card that drops an ask, step or open task, or prints a number the sheet does not hold. The card is checked
  against the sheet the judgment was written from.
- T25 (`T25-measurements.md`): the sheet as measurements to the definitions page.
- T14, T18, T19, T20, T23 (`T14-sheet-fixes.md`, `T18-card-defects.md`, `T19-holds-labels.md`,
  `T20-runs-read-true.md`, `T23-sheet-facts.md`): defects found by using the card. Pace counts the run's landed tasks;
  a task row is one line; a held task is named by its label and by everything it waits on; no pace from under three
  landings scales the close; a goal the sitrep cannot measure says so.
- T22 (`T22-handoff-head.md`): the handoff head counts the sheet's open tasks and writes its clock in local time.

### The four run states, rehearsed (D5)

- T7 (`T7-rehearsal.md`): `tests/rehearsal.test.sh` plays a small run forward in a sandbox through the real commands
  to a failed review, a release card waiting on its reply, an open stop-rule question, and nothing owed, and draws each
  state's sheet and card.

### One vocabulary (REQ-9)

- T15 (`T15-vocabulary.md`), T16 (`T16-skill.md`), T17 (`T17-reworded-readers.md`) and T21 (`T21-walk-findings.md`):
  "review" and "not measured" on the skill texts, the release card, the handoff's head and the Patrol's status line,
  with a lint over those surfaces and their sources under agents-src/; the sitrep skill tells the model to record an
  ask before it puts it to the user in chat; the card's word check refuses "reading", "reader" and "unmeasured".

### The release

- T10 (`T10-release.md`): this entry, plugin.json 1.25.0, the help and version pages rendered by
  `agents-src/render.sh`, `rendered.sha256` refreshed, and ADR-069.

### The readings

- The walk (`walk.md`, T8): the card and the verbs used as a user would, whose findings T21 fixed.

### The landing numbers

`landing-report --rows` at 35c7ec6eae8ac88643accd3ed00e852e8e8cc516 on 2026-10-22T04:06:02Z:

```
landings: queue=18 hand=0 git=0 · ready-to-landed median=5.6m p75=9.2m max=22.4m · runs: green=78 red=4 none=0 discarded=0 red-then-green=0 run=231 reused=0 absent=0 · waited median=21s · killed=0
T1 queue ready=2026-10-21T19:21:16Z landed=2026-10-21T19:26:23Z minutes=5.1 runs=4 waited=18s wait=0.3 prove=4.8 rework=0.0 width=3
  asks.test.sh green promised=4s actual=7s ratio=1.75
  release-approval.test.sh green promised=283s actual=287s ratio=1.01
  notify.test.sh green promised=57s actual=68s ratio=1.19
  stop.test.sh green promised=37s actual=39s ratio=1.05
T4 queue ready=2026-10-21T19:23:51Z landed=2026-10-21T19:31:31Z minutes=7.7 runs=2 waited=170s wait=2.8 prove=4.8 rework=0.0 width=4
  card.test.sh green promised=11s actual=11s ratio=1.00
  release-approval.test.sh green promised=295s actual=289s ratio=0.98
T13 queue ready=2026-10-21T19:56:19Z landed=2026-10-21T20:00:44Z minutes=4.4 runs=7 waited=53s wait=0.9 prove=3.5 rework=0.0 width=2
  sitrep.test.sh green promised=129s actual=148s ratio=1.15
  session-poker-4.test.sh green promised=98s actual=109s ratio=1.11
  session-poker-5.test.sh green promised=88s actual=104s ratio=1.18
  handoff-file.test.sh green promised=44s actual=49s ratio=1.11
  bash-walls.test.sh green promised=23s actual=24s ratio=1.04
  patrol-stale.test.sh green promised=2s actual=3s ratio=1.50
  shell-lint.test.sh red promised=30s actual=34s ratio=1.13
T2 queue ready=2026-10-21T20:37:30Z landed=2026-10-21T20:43:00Z minutes=5.5 runs=6 waited=20s wait=0.3 prove=4.8 rework=0.4 width=3
  asks.test.sh green promised=14s actual=23s ratio=1.64
  sitrep.test.sh green promised=99s actual=149s ratio=1.51
  close-out-4.test.sh green promised=210s actual=285s ratio=1.36
  session-poker-3.test.sh green promised=71s actual=87s ratio=1.23
  session-poker-4.test.sh green promised=94s actual=106s ratio=1.13
  session-poker-5.test.sh green promised=100s actual=102s ratio=1.02
T3 queue ready=2026-10-21T20:42:32Z landed=2026-10-21T21:04:58Z minutes=22.4 runs=6 waited=45s wait=0.8 prove=6.3 rework=15.4 width=4
  sitrep.test.sh green promised=88s actual=112s ratio=1.27
  session-poker-2.test.sh green promised=51s actual=102s ratio=2.00
  session-poker-5.test.sh green promised=81s actual=103s ratio=1.27
  handoff-file.test.sh green promised=38s actual=63s ratio=1.66
  release-approval.test.sh green promised=298s actual=310s ratio=1.04
  close-out-4.test.sh green promised=285s actual=259s ratio=0.91
T15 queue ready=2026-10-21T21:45:01Z landed=2026-10-21T21:46:29Z minutes=1.5 runs=3 waited=20s wait=0.3 prove=1.1 rework=0.0 width=2
  words.test.sh green promised=4s actual=5s ratio=1.25
  shell-lint.test.sh red promised=32s actual=33s ratio=1.03
  render.test.sh green promised=17s actual=16s ratio=0.94
T5 queue ready=2026-10-21T21:56:46Z landed=2026-10-21T22:10:12Z minutes=13.4 runs=11 waited=20s wait=0.3 prove=13.1 rework=0.0 width=3
  sitrep-card.test.sh green promised=8s actual=10s ratio=1.25
  card.test.sh green promised=11s actual=14s ratio=1.27
  handoff-file.test.sh green promised=59s actual=65s ratio=1.10
  width.test.sh green promised=1s actual=1s ratio=1.00
  release-approval.test.sh red promised=274s actual=368s ratio=1.34
  close-out-4.test.sh green promised=256s actual=327s ratio=1.28
  door-card.test.sh green promised=187s actual=298s ratio=1.59
  landing-line-1.test.sh green promised=287s actual=313s ratio=1.09
  session-poker-4.test.sh green promised=106s actual=101s ratio=0.95
  sitrep.test.sh green promised=97s actual=85s ratio=0.88
  shell-lint.test.sh red promised=32s actual=31s ratio=0.97
T14 queue ready=2026-10-21T22:20:37Z landed=2026-10-21T22:25:57Z minutes=5.3 runs=4 waited=21s wait=0.3 prove=5.0 rework=0.0 width=4
  sitrep.test.sh green promised=62s actual=111s ratio=1.79
  handoff-file.test.sh green promised=65s actual=70s ratio=1.08
  shell-lint.test.sh green promised=25s actual=40s ratio=1.60
  close-out-4.test.sh green promised=281s actual=298s ratio=1.06
T17 queue ready=2026-10-21T22:32:13Z landed=2026-10-21T22:37:57Z minutes=5.7 runs=5 waited=19s wait=0.3 prove=5.4 rework=0.0 width=4
  release-approval.test.sh green promised=159s actual=324s ratio=2.04
  bash-walls-egd.test.sh green promised=22s actual=47s ratio=2.14
  notify.test.sh green promised=54s actual=80s ratio=1.48
  session-poker-4.test.sh green promised=71s actual=109s ratio=1.54
  asks.test.sh green promised=23s actual=21s ratio=0.91
T18 queue ready=2026-10-21T22:58:40Z landed=2026-10-21T23:00:45Z minutes=2.1 runs=4 waited=21s wait=0.3 prove=1.7 rework=0.0 width=3
  sitrep-card.test.sh green promised=9s actual=10s ratio=1.11
  sitrep.test.sh green promised=97s actual=103s ratio=1.06
  card.test.sh green promised=12s actual=15s ratio=1.25
  shell-lint.test.sh green promised=32s actual=34s ratio=1.06
T16 queue ready=2026-10-21T23:00:27Z landed=2026-10-21T23:02:52Z minutes=2.4 runs=6 waited=39s wait=0.7 prove=1.8 rework=0.0 width=3
  words.test.sh green promised=8s actual=9s ratio=1.12
  sitrep.test.sh green promised=103s actual=105s ratio=1.02
  sitrep-card.test.sh green promised=10s actual=11s ratio=1.10
  render.test.sh green promised=16s actual=18s ratio=1.12
  shell-lint.test.sh green promised=34s actual=36s ratio=1.06
  card.test.sh green promised=15s actual=15s ratio=1.00
T7 queue ready=2026-10-21T23:05:35Z landed=2026-10-21T23:14:41Z minutes=9.1 runs=2 waited=20s wait=0.3 prove=8.8 rework=0.0 width=3
  rehearsal.test.sh green promised=537s actual=526s ratio=0.98
  shell-lint.test.sh green promised=22s actual=34s ratio=1.55
T19 queue ready=2026-10-21T23:11:53Z landed=2026-10-21T23:16:35Z minutes=4.7 runs=3 waited=188s wait=3.1 prove=1.6 rework=0.0 width=4
  sitrep.test.sh green promised=79s actual=93s ratio=1.18
  sitrep-card.test.sh green promised=9s actual=10s ratio=1.11
  shell-lint.test.sh green promised=26s actual=32s ratio=1.23
T21 queue ready=2026-10-22T00:02:47Z landed=2026-10-22T00:08:41Z minutes=5.9 runs=5 waited=20s wait=0.3 prove=5.6 rework=0.0 width=4
  sitrep-card.test.sh green promised=9s actual=15s ratio=1.67
  asks.test.sh green promised=16s actual=27s ratio=1.69
  release-approval.test.sh green promised=262s actual=332s ratio=1.27
  close-out-4.test.sh green promised=243s actual=308s ratio=1.27
  shell-lint.test.sh green promised=32s actual=38s ratio=1.19
T20 queue ready=2026-10-22T00:06:46Z landed=2026-10-22T00:17:43Z minutes=10.9 runs=4 waited=137s wait=2.3 prove=8.7 rework=0.0 width=4
  rehearsal.test.sh green promised=538s actual=520s ratio=0.97
  sitrep.test.sh green promised=92s actual=102s ratio=1.11
  sitrep-card.test.sh green promised=12s actual=13s ratio=1.08
  shell-lint.test.sh green promised=36s actual=35s ratio=0.97
T22 queue ready=2026-10-22T00:44:24Z landed=2026-10-22T00:46:23Z minutes=2.0 runs=3 waited=21s wait=0.3 prove=1.6 rework=0.0 width=4
  handoff-file.test.sh green promised=40s actual=54s ratio=1.35
  sitrep.test.sh green promised=59s actual=97s ratio=1.64
  shell-lint.test.sh green promised=21s actual=33s ratio=1.57
T23 queue ready=2026-10-22T01:55:47Z landed=2026-10-22T02:04:59Z minutes=9.2 runs=3 waited=20s wait=0.3 prove=8.9 rework=0.0 width=4
  sitrep.test.sh green promised=69s actual=110s ratio=1.59
  rehearsal.test.sh green promised=332s actual=530s ratio=1.60
  handoff-file.test.sh green promised=34s actual=56s ratio=1.65
T24 queue ready=2026-10-22T03:24:14Z landed=2026-10-22T03:33:26Z minutes=9.2 runs=4 waited=20s wait=0.3 prove=8.9 rework=0.0 width=4
  sitrep-card.test.sh green promised=21s actual=27s ratio=1.29
  card.test.sh green promised=11s actual=15s ratio=1.36
  rehearsal.test.sh green promised=505s actual=530s ratio=1.05
  words.test.sh green promised=8s actual=12s ratio=1.50
```

## 1.24.0 — 2026-10-21

This is the run closes itself release. After the last build row lands, a run reaches its release approval card
without a person: no ready row is held on the user, every gate before the card holds machine facts only, and the card
is the one place the user rules on evidence and approves the release and the merge (D1, D8, ADR-066). A fix landed
after the release is read like any other code, and the line renders the release numbers again at that landing (D2,
D11). The door refuses a change to the check that judges it, and a test tree larger than the code (D4, D6, ADR-067).
The 1,034 sections of the test tree were read against a written rubric and 194 culled, the two suites that were
deleted in error came back, and a test now earns its place only by a stated criterion (D3, D5, D12, ADR-068). The
decline verb is deleted (D9). The sitrep says when the run closes as a forecast or a floor, prints one line per task,
always has a best guess, and grades the requirements' own themes as its goals (D13 to D18). A quitting-reader lint
guards the check, a dead Patrol clock is one line, and the handoff ends on one line. This is a minor release by the
policy above: the door fixture suites, the cap on tests and the census are new capability, and the decline verb is
removed. `canonical_sdlc_version` stays 14.

**Migration.** Rows that changed what a script of yours may meet:
- T1: `session-poker.sh decline` is gone, with its lapse and its standing line. A row is ready only once the run is at
  step 4, and a wait is a fact of the plan: a dependency, a read of an unruled decision (`task-set <id>
  reads+=approval:D<n>`), or an open `order`. The wall's gap refusal names those three forms. Old ledgers still read
  as history.
- T4: the `review-results` verb is `release-approval`. The old word still runs, prints the new name once, and reads
  pages written under either name.
- T13: `regression-run` refuses a second whole run past the first, and the `proof-add` refusal no longer offers one. A
  head past the whole run is proved by its landings' own green verdicts.
- T19, T43: from 1.24.0 on, a deferral the policy defers must carry a stated sentence. The release check refuses
  one with none, or with a dash, in one line naming the finding. A release before 1.24.0 is passed over as before.
- T20: the stop hook's dead-clock refusal is one line, `bionic: stop refused — Patrol dead (CronList; CronCreate if
  absent; arm)`. The explanation is `session-poker.sh patrol --explain`.
- T26: the release check prints `test-ratio: <tests>/<code>`, shell lines under tests/ against shell lines elsewhere
  at the head, and refuses a head where tests exceed code. A head with no shell outside tests/ is a refusal, never a
  pass. The release approval card and the sitrep print the same line.
- T10: a landing past the release renders its numbers again. The line adds a commit, `line: release numbers <row>`,
  that replaces the entry's `### The landing numbers` part, and the `published` event gains `numbers=<sha>`.
- T15, T48: the door's refusal of a landing whose range changes the release check names its judge:
  `judged-by=target script=<path>@<base12> changed-here=<path>`. For a release check named relative to the project,
  as bionic's own is, a change to the check's own files is refused whatever the check answers. It lands by hand, through `row-landed <row> <merge> <at> --by-hand`, and that line
  records `judged-by=candidate`.
- T36: a wave or epic requirements document groups its REQs under theme sections, three to six of them. The
  governing-skill hook refuses a REQ under no theme, and the sitrep and the card grade one goal row per theme.
- T39: `handoff` prints the resume line alone. The `handoff — written to <path>` line is gone.
- T5: `tests/shell-lint.test.sh` holds two agreement checks. An ADR's `status:` line must open with the word its
  `## Status` section opens with, and a suite's header list of sections must equal the sections of its body.
- T18: a writer piped into `grep -q`, `grep -m` or an early-exit `awk` in a file under `set -o pipefail` is refused by
  the lint over hooks/, payload/scripts/ and the two files of the release check. Each allowed site is a line of
  `tests/lib/quitting-readers.allow` with its reason.

### The run closes itself (D1, D2, D8, D9, D11, ADR-066, ADR-067)

- T1 (`T1-decline.md`): the decline verb, its ledger reader and lapse, the tick's standing line and the stop wall's
  `fill-declined:` scan are deleted. A ready row is dispatched or made not ready.
- T6 (`T6-ruled.md`) and T7 (`T7-card-ruled.md`): one predicate, `matrix_row_ruled`, read by the commit wall, the
  judge and the card. Every row has a verdict by Step 6, and a ruling is demanded only at the merge advance. The card
  lists no row the user already confirmed, and `confirm-row <AC> '<reply>'` writes the attributed confirmation.
- T37 (`T37-notify.md`) and T38 (`T38-pending-confirm.md`): the gate-move fixtures follow the ruling demand to step 8,
  and a `user-confirmed: pending` stub holds nothing before the merge advance.
- T8 (`T8-pages.md`): the sitrep and the resume recap read open decisions and landed readings through one reader, a
  decision is owed once, and the title reads `step 4 of 9 · work at step 5 (…)` when the work is ahead of the
  counter.
- T9 (`T9-post-release.md`) and T10 (`T10-rerender.md`): a review row that reads only rows after the release is
  admitted, the card waits for it, and the line renders the release numbers again at a landing past the release.
- T11 (`T11-window.md`): the hand-holds count is measured from the last build landing to the card.
- T42 (`T42-holder.md`): the gate's live-holder rule holds under the runner's `IFS`.

### Rules tested where they run (D4, D7, D10, ADR-067)

- T14 (`T14-door.md`): `tests/lib/door.sh` builds one fixture of the door's whole closure, and
  `tests/door-landing.test.sh` lands rows through it by hand and by the line.
- T15 (`T15-judged.md`) and T48 (`T48-judge-always.md`): the refusal names the copy that judged. T48 closes the
  critic's one S1: a rewrite of the check that the target's copy passes was admitted, and is now refused with the hand
  route.
- T16 (`T16-door-card.md`): `tests/door-card.test.sh` carries a run to its end state with the verbs alone and renders
  the card.
- T17 (`T17-cover.md`): `tests/door-cover.test.sh` reads the judge's cover over the real 1.21.0, 1.22.0 and 1.23.0
  merges, which keep their rewritten hashes (D7).
- T18 (`T18-lint.md`) and T3 (`T3-bind.md`): the quitting-reader lint and its allow file, `observe.sh` reading its
  process listing to the end, and the bind path's session reader reading to the end, tested on a plan with 3,000
  session lines.

### The small test debts (D3)

- T2 (`T2-suites.md`): the privacy scan's suite and the doctor's come back from the carry tag, each header naming only
  the sections its body has.
- T12 (`T12-order.md`): the three order refusals are asserted by row id.
- T13 (`T13-whole-run.md`): the one-whole-run rule is a fact the suites hold.
- T19 (`T19-deferral.md`) and T43 (`T43-rule-floor.md`): a deferral without a sentence refuses the release, from
  1.24.0 on.
- T5 (`T5-agreement.md`): the two agreement checks, and ADR-062's two status words made one.

### Tests earn their place (D5, D6, D12, ADR-068)

- T21 (`T21-rubric.md`): `tests/RUBRIC.md` names five verdicts, each with its test and calibration examples.
- T22 (`T22-census.md`): `tests/CENSUS.md` gives every section of every suite one verdict, read by calibrated
  readers.
- T23 (`T23-cull-a.md`), T24 (`T24-cull-b.md`), T25 (`T25-cull-c.md`): 192 of the 194 culled sections deleted at
  whole-section boundaries. The other two are kept as lints.
- T26 (`T26-ratio.md`): the cap. At the build head the tests hold 89,269 shell lines against 96,187 elsewhere.

### The pages (D13 to D18)

- T33 (`T33-close.md`): the Bottom line prints the close once, as a floor or a likely clock with whose pace it is,
  never now. The pace is dispatched-to-landed time, and `sitrep --basis` prints the arithmetic.
- T34 (`T34-tasklist.md`): every Task list line is one line, the name clipped at a word with `…`.
- T35 (`T35-guess.md`): the schedule always has a best guess, graded against the forecast end.
- T36 (`T36-goals.md`) and T40 (`T40-one-reader.md`): the goals are the requirements' themes, read by one reader.
- T4 (`T4-rename.md`): the card is the release approval card in code and in words.
- T20 (`T20-patrol.md`): the dead Patrol clock is one line and one sentence to the user.
- T39 (`T39-handoff-line.md`) and T46 (`T46-close-out-pointer.md`): the handoff ends on its resume line, and
  close-out reads the handoff pointer.
- T41 (`T41-revive.md`) and T47 (`T47-floor-sweep.md`): the revive suite follows the one-line reason, and the close
  sentence says "earliest instant" so the floor sweep finds nothing.

### The release (D8)

- T30 (`T30-release.md`): this entry, plugin.json 1.24.0, the help and version pages rendered by
  `agents-src/render.sh`, `rendered.sha256` refreshed, ADR-066, ADR-067 and ADR-068 accepted and promoted to
  docs/adrs/, and release-check.test.sh §REL-1.24.0 pinning the entry's rows and its Known limits.

### How this run landed (ADR-067)

Thirty-eight rows landed through the line and five by hand. T26 and T43 changed the release check itself, so the line
refused them by design (D4) and the orchestrator landed them by hand on the candidate's own green suites. T27, T44 and
T45 wrote only their records.

### The readings

- The walk (`walk.md`, T44): the pages and the verbs used as a user would, at the build head.
- The regression (`T27-regression.md`, T27): one whole run at 00943de4, 117 suites green and 1 red. The red,
  regression-rename, was turned green by T47.
- The matrix (`T45-matrix-fill.md`, T45): filled from the landed records.
- The critic (`critic-adversarial.md`, `critic-structure.md`, T29): one S1, fixed by T48, and three S3 findings
  deferred, below. The structure reading flagged two duplicated readers and the census counts.
- The auditor (`auditor-evidence.md`, T28): 68 rows confirmed, two refuted and three unverifiable. Each of those five
  reaches the release approval card as a decision.

### The landing numbers

`landing-report --rows` at 4822ef014852afadaa2501ff43e0d88ba77cd487 on 2026-10-21T16:42:58Z:

```
landings: queue=40 hand=6 git=0 · ready-to-landed median=4.0m p75=6.8m max=24.2m · runs: green=184 red=8 none=1 discarded=6 red-then-green=0 run=427 reused=0 absent=0 · waited median=18s · killed=11
T6 queue ready=2026-10-21T01:09:41Z landed=2026-10-21T01:11:12Z minutes=1.5 runs=3 waited=19s wait=0.3 prove=0.9 rework=0.2 width=2
  bash-walls.test.sh green promised=21s actual=22s ratio=1.05
  canonical-sdlc-evidence-gate-2.test.sh green promised=51s actual=55s ratio=1.08
  units.test.sh green promised=9s actual=13s ratio=1.44
T21 queue ready=2026-10-21T01:21:13Z landed=2026-10-21T01:21:26Z minutes=0.2 runs=0 waited=13s wait=0.2 prove=0.0 rework=0.0 width=-
T14 queue ready=2026-10-21T01:28:07Z landed=2026-10-21T01:30:30Z minutes=2.4 runs=1 waited=13s wait=0.2 prove=2.2 rework=0.0 width=4
  door-landing.test.sh green promised=115s actual=130s ratio=1.13
T4 queue ready=2026-10-21T01:28:14Z landed=2026-10-21T01:41:27Z minutes=13.2 runs=6 waited=235s wait=3.9 prove=9.3 rework=0.0 width=4
  release-approval.test.sh green promised=189s actual=288s ratio=1.52
  close-out-1.test.sh green promised=179s actual=320s ratio=1.79
  close-out-2.test.sh green promised=144s actual=321s ratio=2.23
  close-out-3.test.sh green promised=134s actual=316s ratio=2.36
  close-out-4.test.sh green promised=224s actual=235s ratio=1.05
  sitrep.test.sh green promised=85s actual=75s ratio=0.88
T8 queue ready=2026-10-21T01:55:39Z landed=2026-10-21T02:00:06Z minutes=4.5 runs=2 waited=155s wait=2.6 prove=1.9 rework=0.0 width=1
  sitrep.test.sh green promised=92s actual=111s ratio=1.21
  session-poker-4.test.sh red promised=74s actual=105s ratio=1.42
T7 queue ready=2026-10-21T02:21:37Z landed=2026-10-21T02:26:47Z minutes=5.2 runs=2 waited=16s wait=0.3 prove=4.0 rework=0.9 width=4
  release-approval.test.sh green promised=211s actual=237s ratio=1.12
  bash-walls.test.sh green promised=17s actual=20s ratio=1.18
T9 queue ready=2026-10-21T02:34:56Z landed=2026-10-21T02:38:58Z minutes=4.0 runs=2 waited=13s wait=0.2 prove=3.8 rework=0.0 width=4
  units.test.sh green promised=5s actual=10s ratio=2.00
  release-approval.test.sh green promised=102s actual=228s ratio=2.24
T22 queue ready=2026-10-21T02:46:54Z landed=2026-10-21T02:47:18Z minutes=0.4 runs=1 waited=11s wait=0.2 prove=0.2 rework=0.0 width=4
  shell-lint.test.sh green promised=12s actual=12s ratio=1.00
T17 queue ready=2026-10-21T03:03:03Z landed=2026-10-21T03:03:29Z minutes=0.4 runs=2 waited=13s wait=0.2 prove=0.2 rework=0.0 width=3
  door-cover.test.sh green promised=2s actual=3s ratio=1.50
  units.test.sh green promised=11s actual=11s ratio=1.00
T15 queue ready=2026-10-21T03:12:24Z landed=2026-10-21T03:15:46Z minutes=3.4 runs=2 waited=15s wait=0.2 prove=3.1 rework=0.0 width=3
  door-landing.test.sh green promised=102s actual=186s ratio=1.82
  worktree.test.sh green promised=30s actual=43s ratio=1.43
T23 queue ready=2026-10-21T03:36:02Z landed=2026-10-21T03:50:30Z minutes=14.5 runs=28 waited=17s wait=0.3 prove=14.2 rework=0.0 width=3
  shell-lint.test.sh red promised=12s actual=16s ratio=1.33
  agent-context-guard.test.sh green promised=16s actual=8s ratio=0.50
  archive.test.sh green promised=3s actual=1s ratio=0.33
  background-suite-guard.test.sh green promised=49s actual=27s ratio=0.55
  bash-walls.test.sh green promised=12s actual=18s ratio=1.50
  binding.test.sh green promised=5s actual=4s ratio=0.80
  booked.test.sh green promised=16s actual=25s ratio=1.56
  canonical-sdlc-evidence-gate.test.sh green promised=18s actual=14s ratio=0.78
  close-out-1.test.sh green promised=297s actual=261s ratio=0.88
  close-out-4.test.sh green promised=236s actual=278s ratio=1.18
  cmd-class.test.sh green promised=14s actual=9s ratio=0.64
  commands.test.sh green promised=3s actual=1s ratio=0.33
  context-spend.test.sh green promised=8s actual=7s ratio=0.88
  context.test.sh green promised=4s actual=5s ratio=1.25
  cross-gate-agreement-1.test.sh green promised=307s actual=38s ratio=0.12
  cross-gate-agreement-2.test.sh green promised=15s actual=8s ratio=0.53
  decision-skill.test.sh green promised=1s actual=1s ratio=1.00
  detect-probes.test.sh green promised=18s actual=16s ratio=0.89
  detect.test.sh green promised=4s actual=2s ratio=0.50
  dispatch-preflight-2.test.sh green promised=178s actual=36s ratio=0.20
  dispatch-preflight-4b.test.sh green promised=267s actual=199s ratio=0.75
  dispatch-preflight.test.sh green promised=59s actual=42s ratio=0.71
  doctor-patrol.test.sh green promised=116s actual=49s ratio=0.42
  doctor-restart.test.sh green promised=233s actual=209s ratio=0.90
  doctor-version.test.sh green promised=118s actual=76s ratio=0.64
  doctor-walls.test.sh green promised=63s actual=41s ratio=0.65
  doctor.test.sh green promised=20s actual=6s ratio=0.30
  door-landing.test.sh green promised=175s actual=176s ratio=1.01
T11 queue ready=2026-10-21T03:42:21Z landed=2026-10-21T04:00:12Z minutes=17.9 runs=2 waited=500s wait=8.3 prove=9.0 rework=0.5 width=4
  landing-line-1.test.sh green promised=329s actual=292s ratio=0.89
  release-approval.test.sh green promised=260s actual=248s ratio=0.95
T24 queue ready=2026-10-21T04:03:07Z landed=2026-10-21T04:17:57Z minutes=14.8 runs=28 waited=35s wait=0.6 prove=8.2 rework=6.0 width=1
  engage.test.sh green promised=21s actual=22s ratio=1.05
  execution-recorder.test.sh green promised=127s actual=7s ratio=0.06
  fail-direction-table.test.sh green promised=25s actual=18s ratio=0.72
  farm-out-reminder.test.sh green promised=35s actual=27s ratio=0.77
  fold.test.sh green promised=2s actual=3s ratio=1.50
  framework.test.sh green promised=47s actual=8s ratio=0.17
  git-argv.test.sh green promised=22s actual=17s ratio=0.77
  grant.test.sh green promised=23s actual=15s ratio=0.65
  handoff-file.test.sh green promised=39s actual=47s ratio=1.21
  hook-adoption.test.sh green promised=10s actual=7s ratio=0.70
  hook-latency.test.sh green promised=19s actual=15s ratio=0.79
  hook-timeout.test.sh green promised=244s actual=265s ratio=1.09
  interpreter-pin.test.sh green promised=70s actual=6s ratio=0.09
  jit.test.sh green promised=2s actual=2s ratio=1.00
  landing-gate.test.sh green promised=36s actual=12s ratio=0.33
  landing-line-1.test.sh green promised=314s actual=323s ratio=1.03
  landing-line-2.test.sh green promised=175s actual=178s ratio=1.02
  live-agents.test.sh green promised=10s actual=5s ratio=0.50
  notify.test.sh red promised=73s actual=69s ratio=0.95
  patrol-duties-gate.test.sh green promised=428s actual=44s ratio=0.10
  patrol-revive.test.sh green promised=40s actual=18s ratio=0.45
  patrol-stale.test.sh green promised=3s actual=3s ratio=1.00
  permission-answer.test.sh green promised=60s actual=50s ratio=0.83
  permission-effects.test.sh green promised=11s actual=7s ratio=0.64
  placement.test.sh green promised=1s actual=3s ratio=3.00
  preflight-probe.test.sh green promised=19s actual=15s ratio=0.79
  principles-item.test.sh green promised=97s actual=76s ratio=0.78
  protect-main.test.sh green promised=38s actual=7s ratio=0.18
T25 queue ready=2026-10-21T04:40:21Z landed=2026-10-21T04:50:13Z minutes=9.9 runs=26 waited=28s wait=0.5 prove=9.4 rework=0.0 width=4
  shell-lint.test.sh green promised=16s actual=18s ratio=1.12
  rc-item-1.test.sh green promised=132s actual=138s ratio=1.05
  rc-item-2.test.sh green promised=272s actual=307s ratio=1.13
  regression-rename.test.sh green promised=14s actual=18s ratio=1.29
  release-check.test.sh green promised=37s actual=44s ratio=1.19
  render.test.sh green promised=21s actual=16s ratio=0.76
  root.test.sh green promised=6s actual=4s ratio=0.67
  roots.test.sh green promised=9s actual=11s ratio=1.22
  roster.test.sh green promised=3s actual=3s ratio=1.00
  run-predicate.test.sh green promised=8s actual=5s ratio=0.62
  runner-roster.test.sh green promised=52s actual=24s ratio=0.46
  runner-width.test.sh green promised=9s actual=12s ratio=1.33
  scale-profile.test.sh green promised=17s actual=15s ratio=0.88
  seam-resolution.test.sh green promised=2s actual=6s ratio=3.00
  session-poker-5.test.sh green promised=72s actual=81s ratio=1.12
  session-start.test.sh green promised=105s actual=21s ratio=0.20
  session-sweep.test.sh green promised=40s actual=24s ratio=0.60
  session.test.sh green promised=4s actual=1s ratio=0.25
  sitrep.test.sh green promised=109s actual=101s ratio=0.93
  spawn-worktree.test.sh green promised=114s actual=73s ratio=0.64
  stop-guard.test.sh green promised=81s actual=11s ratio=0.14
  stop.test.sh green promised=89s actual=31s ratio=0.35
  units.test.sh green promised=12s actual=14s ratio=1.17
  version-compare.test.sh green promised=2s actual=1s ratio=0.50
  width.test.sh green promised=2s actual=1s ratio=0.50
  worktree.test.sh green promised=44s actual=37s ratio=0.84
T36 queue ready=2026-10-21T04:44:14Z landed=2026-10-21T04:52:07Z minutes=7.9 runs=3 waited=375s wait=6.2 prove=1.6 rework=0.0 width=4
  canonical-sdlc-governing-skill.test.sh green promised=25s actual=32s ratio=1.28
  sitrep.test.sh green promised=83s actual=97s ratio=1.17
  shell-lint.test.sh green promised=12s actual=16s ratio=1.33
T33 queue ready=2026-10-21T04:46:33Z landed=2026-10-21T04:56:40Z minutes=10.1 runs=2 waited=349s wait=5.8 prove=1.7 rework=2.6 width=4
  sitrep.test.sh green promised=61s actual=102s ratio=1.67
  shell-lint.test.sh green promised=11s actual=16s ratio=1.45
T34 queue ready=2026-10-21T05:12:44Z landed=2026-10-21T05:21:02Z minutes=8.3 runs=5 waited=19s wait=0.3 prove=5.3 rework=2.7 width=4
  sitrep.test.sh red promised=63s actual=109s ratio=1.73
  shell-lint.test.sh green promised=12s actual=16s ratio=1.33
  sitrep.test.sh none promised=109s actual=103s ratio=0.94
  shell-lint.test.sh green promised=13s actual=15s ratio=1.15
  sitrep.test.sh green promised=105s actual=103s ratio=0.98
T2 queue ready=2026-10-21T05:18:25Z landed=2026-10-21T05:23:04Z minutes=4.7 runs=3 waited=174s wait=2.9 prove=1.8 rework=0.0 width=3
  name-scan.test.sh green promised=116s actual=104s ratio=0.90
  doctor-reads.test.sh green promised=64s actual=71s ratio=1.11
  shell-lint.test.sh green promised=13s actual=17s ratio=1.31
T1 queue ready=2026-10-21T05:37:38Z landed=2026-10-21T05:41:28Z minutes=3.8 runs=5 waited=20s wait=0.3 prove=2.7 rework=0.8 width=3
  stop.test.sh red promised=18s actual=33s ratio=1.83
  session-poker-5.test.sh red promised=69s actual=91s ratio=1.32
  patrol-duties-gate.test.sh green promised=26s actual=43s ratio=1.65
  render.test.sh green promised=16s actual=18s ratio=1.12
  shell-lint.test.sh green promised=17s actual=18s ratio=1.06
T10 queue ready=2026-10-21T05:54:58Z landed=2026-10-21T05:58:50Z minutes=3.9 runs=2 waited=17s wait=0.3 prove=3.6 rework=0.0 width=2
  door-landing.test.sh green promised=220s actual=214s ratio=0.97
  shell-lint.test.sh green promised=14s actual=17s ratio=1.21
T18 queue ready=2026-10-21T05:57:07Z landed=2026-10-21T05:59:33Z minutes=2.4 runs=1 waited=120s wait=2.0 prove=0.4 rework=0.0 width=3
  shell-lint.test.sh green promised=23s actual=26s ratio=1.13
T20 queue ready=2026-10-21T06:16:30Z landed=2026-10-21T06:19:38Z minutes=3.1 runs=4 waited=128s wait=2.1 prove=1.0 rework=0.0 width=3
  stop.test.sh red promised=32s actual=31s ratio=0.97
  patrol-stale.test.sh green promised=2s actual=2s ratio=1.00
  render.test.sh green promised=17s actual=17s ratio=1.00
  shell-lint.test.sh green promised=27s actual=27s ratio=1.00
T16 queue ready=2026-10-21T06:18:06Z landed=2026-10-21T06:24:31Z minutes=6.4 runs=3 waited=111s wait=1.9 prove=4.6 rework=0.0 width=3
  door-card.test.sh green promised=235s actual=245s ratio=1.04
  release-approval.test.sh green promised=260s actual=272s ratio=1.05
  shell-lint.test.sh green promised=27s actual=31s ratio=1.15
T35 queue ready=2026-10-21T06:27:43Z landed=2026-10-21T06:29:59Z minutes=2.3 runs=2 waited=17s wait=0.3 prove=2.0 rework=0.0 width=4
  sitrep.test.sh green promised=74s actual=118s ratio=1.59
  shell-lint.test.sh green promised=17s actual=28s ratio=1.65
T5 queue ready=2026-10-21T06:39:17Z landed=2026-10-21T06:40:17Z minutes=1.0 runs=2 waited=18s wait=0.3 prove=0.7 rework=0.0 width=2
  shell-lint.test.sh green promised=31s actual=33s ratio=1.06
  release-check.test.sh green promised=45s actual=42s ratio=0.93
T13 queue ready=2026-10-21T06:41:46Z landed=2026-10-21T06:46:29Z minutes=4.7 runs=6 waited=20s wait=0.3 prove=1.9 rework=2.5 width=2
  canonical-sdlc-evidence-gate-2.test.sh green promised=48s actual=54s ratio=1.12
  units.test.sh green promised=14s actual=16s ratio=1.14
  shell-lint.test.sh red promised=33s actual=35s ratio=1.06
  canonical-sdlc-evidence-gate-2.test.sh green promised=54s actual=58s ratio=1.07
  units.test.sh green promised=16s actual=15s ratio=0.94
  shell-lint.test.sh green promised=35s actual=34s ratio=0.97
T42 queue ready=2026-10-21T07:06:38Z landed=2026-10-21T07:08:25Z minutes=1.8 runs=3 waited=18s wait=0.3 prove=1.5 rework=0.0 width=3
  stop.test.sh green promised=30s actual=37s ratio=1.23
  session-poker-5.test.sh green promised=80s actual=88s ratio=1.10
  shell-lint.test.sh green promised=33s actual=34s ratio=1.03
T12 queue ready=2026-10-21T07:15:52Z landed=2026-10-21T07:17:09Z minutes=1.3 runs=3 waited=18s wait=0.3 prove=1.0 rework=0.0 width=2
  units.test.sh green promised=15s actual=15s ratio=1.00
  canonical-sdlc-evidence-gate-2.test.sh green promised=50s actual=58s ratio=1.16
  shell-lint.test.sh green promised=34s actual=35s ratio=1.03
T19 queue ready=2026-10-21T07:20:34Z landed=2026-10-21T07:21:36Z minutes=1.0 runs=2 waited=17s wait=0.3 prove=0.8 rework=0.0 width=3
  release-check.test.sh green promised=47s actual=44s ratio=0.94
  shell-lint.test.sh green promised=35s actual=32s ratio=0.91
T43 hand ready=- landed=2026-10-21T07:58:27Z minutes=- runs=2 waited=- wait=- prove=- rework=- width=-
  release-check.test.sh green promised=40s actual=50s ratio=1.25
  shell-lint.test.sh green promised=23s actual=30s ratio=1.30
T37 queue ready=2026-10-21T07:36:55Z landed=2026-10-21T08:01:05Z minutes=24.2 runs=6 waited=1247s wait=20.8 prove=3.4 rework=0.0 width=4
  notify.test.sh green promised=64s actual=68s ratio=1.06
  session-poker-4.test.sh green promised=86s actual=101s ratio=1.17
  shell-lint.test.sh green promised=36s actual=34s ratio=0.94
  notify.test.sh green promised=37s actual=70s ratio=1.89
  session-poker-4.test.sh green promised=54s actual=98s ratio=1.81
  shell-lint.test.sh green promised=18s actual=38s ratio=2.11
T38 queue ready=2026-10-21T07:40:37Z landed=2026-10-21T08:01:59Z minutes=21.4 runs=12 waited=1192s wait=19.9 prove=1.2 rework=0.3 width=3
  bash-walls.test.sh discarded promised=19s actual=- ratio=-
  canonical-sdlc-evidence-gate.test.sh discarded promised=13s actual=- ratio=-
  shell-lint.test.sh discarded promised=27s actual=- ratio=-
  bash-walls.test.sh green promised=18s actual=23s ratio=1.28
  canonical-sdlc-evidence-gate.test.sh green promised=13s actual=14s ratio=1.08
  shell-lint.test.sh green promised=25s actual=32s ratio=1.28
  bash-walls.test.sh discarded promised=13s actual=- ratio=-
  canonical-sdlc-evidence-gate.test.sh discarded promised=8s actual=- ratio=-
  shell-lint.test.sh discarded promised=18s actual=- ratio=-
  bash-walls.test.sh green promised=20s actual=23s ratio=1.15
  canonical-sdlc-evidence-gate.test.sh green promised=14s actual=14s ratio=1.00
  shell-lint.test.sh green promised=38s actual=33s ratio=0.87
T3 queue ready=2026-10-21T08:08:37Z landed=2026-10-21T08:09:27Z minutes=0.8 runs=2 waited=18s wait=0.3 prove=0.5 rework=0.0 width=2
  binding.test.sh green promised=3s actual=4s ratio=1.33
  shell-lint.test.sh green promised=31s actual=32s ratio=1.03
T26 hand ready=- landed=2026-10-21T08:12:57Z minutes=- runs=10 waited=- wait=- prove=- rework=- width=-
  release-check.test.sh green promised=47s actual=58s ratio=1.23
  door-landing.test.sh green promised=213s actual=277s ratio=1.30
  release-approval.test.sh green promised=278s actual=315s ratio=1.13
  sitrep.test.sh green promised=129s actual=157s ratio=1.22
  shell-lint.test.sh green promised=35s actual=36s ratio=1.03
  release-check.test.sh green promised=57s actual=68s ratio=1.19
  door-landing.test.sh green promised=277s actual=266s ratio=0.96
  release-approval.test.sh green promised=273s actual=312s ratio=1.14
  sitrep.test.sh green promised=145s actual=160s ratio=1.10
  shell-lint.test.sh green promised=34s actual=34s ratio=1.00
T41 queue ready=2026-10-21T08:13:17Z landed=2026-10-21T08:14:06Z minutes=0.8 runs=2 waited=16s wait=0.3 prove=0.6 rework=0.0 width=4
  patrol-revive.test.sh green promised=13s actual=17s ratio=1.31
  shell-lint.test.sh green promised=28s actual=31s ratio=1.11
T39 queue ready=2026-10-21T08:17:49Z landed=2026-10-21T08:18:51Z minutes=1.0 runs=2 waited=18s wait=0.3 prove=0.7 rework=0.0 width=3
  handoff-file.test.sh green promised=42s actual=44s ratio=1.05
  shell-lint.test.sh green promised=31s actual=33s ratio=1.06
T40 queue ready=2026-10-21T08:28:03Z landed=2026-10-21T08:33:18Z minutes=5.2 runs=2 waited=17s wait=0.3 prove=5.0 rework=0.0 width=3
  landing-line-1.test.sh green promised=254s actual=297s ratio=1.17
  sitrep.test.sh green promised=110s actual=139s ratio=1.26
T46 queue ready=2026-10-21T08:33:35Z landed=2026-10-21T08:37:56Z minutes=4.3 runs=2 waited=17s wait=0.3 prove=4.1 rework=0.0 width=4
  close-out-4.test.sh green promised=269s actual=244s ratio=0.91
  shell-lint.test.sh green promised=33s actual=31s ratio=0.94
T44 hand ready=- landed=2026-10-21T08:55:00Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T27 hand ready=- landed=2026-10-21T09:25:37Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T47 queue ready=2026-10-21T09:31:56Z landed=2026-10-21T09:34:17Z minutes=2.4 runs=3 waited=20s wait=0.3 prove=2.0 rework=0.0 width=4
  regression-rename.test.sh green promised=13s actual=15s ratio=1.15
  sitrep.test.sh green promised=117s actual=119s ratio=1.02
  shell-lint.test.sh green promised=19s actual=33s ratio=1.74
T45 hand ready=- landed=2026-10-21T09:50:14Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T48 queue ready=2026-10-21T10:15:28Z landed=2026-10-21T10:20:09Z minutes=4.7 runs=2 waited=18s wait=0.3 prove=4.4 rework=0.0 width=4
  door-landing.test.sh green promised=168s actual=263s ratio=1.57
  shell-lint.test.sh green promised=24s actual=31s ratio=1.29
T30 queue ready=2026-10-21T10:59:30Z landed=2026-10-21T11:00:59Z minutes=1.5 runs=1 waited=16s wait=0.3 prove=1.0 rework=0.2 width=4
  release-check.test.sh green promised=58s actual=58s ratio=1.00
T51 queue ready=2026-10-21T13:29:52Z landed=2026-10-21T13:35:01Z minutes=5.2 runs=2 waited=16s wait=0.3 prove=4.9 rework=0.0 width=4
  door-landing.test.sh green promised=165s actual=292s ratio=1.77
  shell-lint.test.sh green promised=23s actual=33s ratio=1.43
T53 hand ready=- landed=2026-10-21T16:16:58Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
```

### Known limits

- A fix row landed after the release is read only when it sits at step 7 or later in the plan, though the line
  re-renders the release numbers for a fix row at any step; a fix row born at step 4 has its numbers refreshed and its
  reader row refused. (`critic-adversarial.md#2`)
- The release approval card prints a pending or overdue requirements theme as ❔ where the situation report prints ➖ or
  ✖️ for the same goal. (`critic-adversarial.md#3`)
- The release approval card does not say when the release range changed the door's own check: neither the release
  check's check-changed line nor a landing's judged-by=candidate mark has a reader on the card.
  (`critic-adversarial.md#4`)
- A landing that changes a library the release check sources (payload/scripts/lib, hooks/poker) is refused only when
  the accepted head's copy of the check fails over it. A change that keeps that copy passing lands through the door
  and is recorded by the release check's check-changed line (`T48-judge-always.md`).
- A release check named by full path is only partly guarded. Named through a symlink or in another letter case, it
  has no closure, so a landing that rewrites it is judged only by whether the old copy passes. Run from a landing tree,
  it runs the main checkout's working copy, while the refusal says the accepted head's copy ran. Name the release
  check relative to the project, as bionic's own is, and neither applies. (`critic-adversarial-4.md#1`, `#2`)

## 1.23.0 — 2026-10-20

This is the small files, plain words release. The 15,715-line core script is now a dispatcher and seven parts, one
concern each (D11, ADR-063). A row proves its own change with its own suites, the whole regression runs once after the
build, and a head past it is proved by its landings' own green verdicts, never by a second whole run (D15, D16, D19).
The reads index that keyed proofs by what a suite read is deleted outright (D18), and the test suites were cut from
171,255 lines to 81,361, none over 1,000, with 1,341 sentence, count and document checks removed (D17). The sitrep and
the final card now answer in plain language what is done, what is next, what the user owes and when the run closes
(D6, D7, D8). A handoff is one self-contained document any session can write and any session can resume, with a run
bound or none (D9, D10). An order is the user's words, recorded by a verb and enforced where suites start (D3). A
comment never names a wave, task, criterion, decision or record path, and a lint refuses one on both landing doors
(D4, D14). This is a minor release by the policy above: the pages, the handoff document, the order verb, the lint,
the promote and release-note verbs are new capability; the index, the `standing-orders:` key and `card.sh final` are
removed. `canonical_sdlc_version` stays 14.

**Migration.** Rows that changed what a script of yours may meet:
- T29, T55: `standing-orders:` in `.bionic/config.yaml` is no longer read, and the bash walls no longer enforce it.
  The user says the order in the conversation and the orchestrator records it with `order '<words>'` and lifts it
  with `order lift`. While it stands, tests/run.sh and the landing line refuse with the user's words and run nothing.
- T23, T24: `card.sh final` is deleted. The final card is the review results page, `session-poker.sh review-results`
  (`--preview` renders it and records nothing). `reply` takes `all default`, `all recommended`, or a sequence of
  numbered choices, and a bad item refuses the whole reply. The page offers no regression waiver.
- T45: the reads index is deleted. A suite's `reads` lines are no longer read, a verdict is keyed by the commit it ran
  at, and `ready` reuses and skips nothing. The suites reads-hash, suite-reads, name-scan and doctor-reads are deleted.
- T16, T18: the order is build, regression, review, release, approval, merge. In a plan with a reads column,
  `task-add` refuses a regression row placed after a review or release row. An `approved:` line carries
  `head=<40-hex>`, and `current 8` is admitted only at the head the user approved for release.
- T14, T57: `spawn-worktree.sh land --by-hand` takes `--suites`, `--green-at` and `--log`, all three or none, and
  records the suites as green verdicts at that commit. It runs nothing, and it refuses a candidate the comment lint
  refuses, with a `LINT` line.
- T25, T47, T54: a handoff is written to `.bionic/docs/record/handoffs/<date>-<slug>.md`, with or without a bound
  run. close-out writes the new document and keeps every line of an old-shape handoff file.
- T28: `docs-tracked:` names where durable records go, `docs/` when absent, and `session-poker.sh promote
  <adr|design|requirement> <source>` copies one there. A plan, a log or a handoff is refused.
- T19: `session-poker.sh release-note` prints an entry's landing numbers, and the release check holds an entry that
  names its head to the landing report at that head.
- T14: a landing has no width of its own. The line asks the gate before each suite.
- T17: a Lands-on command is held to the 600-second suite bar, as a suite is.
- T22: `decisions put D<n> '<what is decided>'` writes the put to the design ledger with its wait line.
- T31: `step-field 5 auditor=<name>` is accepted at Step 5 alone, and `Deliverable-waiver: none` is read as no waiver.

### The core script is eight files (D11, ADR-063)

- T1 (`T1-split.md`): hooks/session-poker.sh keeps the loader, the parse case, the shared helpers and the plan
  transaction, and loads seven parts under hooks/poker/: judge, line, proof, roster, tick, sitrep and plan. No two
  parts call each other both ways, and the two real dependencies are declared loads.
- T2 (`T2-folds.md`): 25 readers of the landing record now go through `line_kv`, and four readers of the integration
  branch through `plan_integration_branch`.
- T3 (`T3-edges.md`): the two scan edges were cut with byte-identical output. They dropped no pair, and the index
  they served was deleted afterwards (D18).

### One whole run, and a landing proves its own change (D13, D15, D16, D17, D18, D19, ADR-065)

ADR-065 records the rule and is Proposed. It supersedes ADR-061 and amends ADR-063: the parts are kept, the
declarations and the reach by file are not. D5's suite count and D12's reach by file went with the index (D18).
- T45 (`T45-index-deleted.md`): the index, the owed-set walk, the reads-keyed reuse and skip, and every `reads`
  declaration are deleted, 4,709 lines. The judge holds a head covered when it is the head of the last green whole
  run.
- T16 (`T16-order.md`): the step order and its validator. The judge holds a head past the last green whole run
  covered when each later commit is excused or is a landing whose row's suites are green at it, and each red that
  run left has a later green. D19 made that the criterion.
- T51 (`T51-fix-proof-add.md`) and T52 (`T52-fix-hand-suites.md`): `proof-add regression` and the hand door agree
  with the judge on that rule.
- T18 (`T18-release-order.md`): the approved head, read by one reader, `proof_approved_head`.
- T14 (`T14-no-width.md`): no width constant, and a hand landing records the writer's verdicts and runs nothing.
- T17 (`T17-command-bar.md`): a Lands-on command is keyed by its gate key and held to the bar.
- T43 (`T43-cull-1.md`): every suite capped at 1,000 lines at whole-section boundaries, 89,894 lines deleted.
- T44 (`T44-cull-3.md`): 1,341 checks that quoted a sentence, counted lines or read a document deleted across 95
  suites.
- T32 (`T32-measure-1.md`): the promised total leaves out a suite the row removed.
- T33 (`T33-measure-2.md`): a finding's disposition says when the regression fixed it.

### The sitrep page and the review results page (D6, D7, D8)

- T21 (`T21-sitrep.md`): the sitrep is the accepted page. The Bottom line comes first, with what you owe, what is
  next, what is done and when it closes. Then the task list, the Score with one line per indicator, and Blocked on
  you. Every line is folded at 92 columns.
- T20 (`T20-goals.md`): the plan's `goals:` are read by one reader and printed on both pages, and the first miss is
  put as a decision.
- T22 (`T22-rounds.md`): decisions are counted in rounds, and a put prints what waiting on it costs.
- T23 (`T23-review-results.md`) and T24 (`T24-reply.md`): the review results page and the one reply that orders
  several acts in sequence. A finding reaches the user as a decision only as a missed criterion or when the
  orchestrator recommends against the policy (D7).
- T56 (`T56-fix-page-judge.md`): the review results page asks the judge for the regression verdict.
- T59 (`T59-fix-sitrep-page.md`): nine defects the user found reading the live page, among them the wait clause in
  words, the percent on the title line in place of the Completion section, and killed runs counted as waste.
- T62 (`T62-fix-owed-decision.md`): an open decision is owed by the user on the Bottom line, under Blocked on you and
  in the one-line form.

### The handoff document (D2, D9, D10)

- T25 (`T25-handoff.md`): `/bionic:handoff` writes one document, with or without a run, to an ignored folder. It has a
  four-line Summary, the Goal in the person's words, State as computed facts, Findings with their sources, Decisions,
  Ruled out, Open, Suggested skills, Next with the first command and Resume as its last line. Resume engages the
  session quietly.
- T47 (`T47-fix-close-out.md`) and T54 (`T54-fix-closeout-oldshape.md`): close-out writes the new document and carries
  every line of an old-shape file into it.

### Orders are the user's words (D3, ADR-064)

- T29 (`T29-orders.md`): the `order` verb, the one reader `gate_order`, and the runner's refusal. The config key, its
  wall and its suite are deleted.
- T55 (`T55-fix-line-order.md`): the landing line reads the order before it starts a suite.

### The comment rule and its lint (D4, D14, ADR-064)

- T26 (`T26-rule.md`): one block, rendered into every place a comment is written. A comment states the reason and the
  invariant, and cites a tracked path under `docs/` when it needs a document.
- T27 (`T27-lint.md`): the landing line refuses a candidate whose added comment lines name a run's history. It judges
  the lines a landing adds, never the tree it inherits.
- T57 (`T57-fix-hand-lint.md`): the hand door runs the same lint, and the six comment lines the wave landed by hand
  are rewritten.
- T53 (`T53-fix-cap-lint.md`): the lint and the hand landing's candidate each get one behaviour check.

### Durable records have a tracked home (D1)

- T28 (`T28-promote.md`): `docs-tracked:` and the promote verb. ADR-056 is amended as ADR-062 requires.
- T38 (`T38-release.md`): ADR-056, ADR-062, ADR-063 and ADR-064 are promoted to docs/adrs/. ADR-063 and ADR-064
  are accepted at this release, ADR-063 amended by ADR-065. ADR-061 is superseded by ADR-065, which stays Proposed.

### Wave 39's leftovers (D3)

- T30 (`T30-leftovers.md`): the five wrong sentences of the 1.22.0 entry are corrected, the prelude binds its marker,
  and the closed form owes no pull request for a branch that was merged and deleted.
- T31 (`T31-verb-gaps.md`): the five verb gaps met at wave 39's close.

### The release (D16)

- T38 (`T38-release.md`): this entry, plugin.json 1.23.0, the help and version pages rendered by
  `agents-src/render.sh`, `rendered.sha256` refreshed, and release-check.test.sh §REL-1.23.0 pinning the version, the
  head this entry's numbers name and the promoted records.

### How this run landed (D15)

On the user's word, "we do not need to do excessive proving of every suite. That is the entire point of this wave.
Land these by hand", a writer ran only the suites that pin its own change, RED then GREEN, and the orchestrator landed
the tree by hand on the report. The landing report below counts forty-one rows landed by hand and three through
the line. The whole regression after the build is the proof for everything else (D16).

### The readings

- The walk (`walk.md`, T34): the pages and a landing used as a user would, from the main checkout and a spawned tree.
- The regression (`T39-regression.md`, T39): one whole run at f7205ad6, 2:20 to 2:39 AM PDT, 101 of 113 suites green
  and 12 red. Each red was turned green by a fix row with its own suites, T46 to T52.
- The matrix (`T35-matrix-fill.md`, T35): filled from the landed records at 48e47cc5.
- The auditor's first reading (`auditor-evidence.md`, T36): five rows refuted, fixed by T58
  (`T58-fix-evidence-misses.md`).
- The critic's first reading (`critic-adversarial.md`, `critic-structure.md`, T37): two S1 and two S2 findings, fixed
  by T54 to T57; four S3 findings deferred, below.
- The second readings, on the fix rows (`critic-adversarial-2.md`, `critic-structure-2.md`, T61, and
  `critic-adversarial-3.md`, `critic-structure-3.md`, T63): five S3 findings deferred, below, and S4 notes.
- The auditor's second reading on the whole (`auditor-evidence-2.md`, T60): 66 rows confirmed, 3 refuted and 3
  unverifiable. The user confirmed both reader tests (D21), waived AC-5.1 and AC-7.1 with their fixes carried (D20),
  and waived AC-16.3 and AC-17.3 on the amended criterion and this row's promotion (D22). Its open findings are under
  Known limits.

### The landing numbers

`landing-report --rows` at c8a022d5ba618bb5f82ee02f30b4500b4b18c9fd on 2026-10-20T18:39:49Z:

```
landings: queue=3 hand=41 git=0 · ready-to-landed median=5.0m p75=11.7m max=18.4m · runs: green=59 red=0 none=0 discarded=0 red-then-green=0 run=257 reused=0 absent=0 · waited median=15s · killed=2
T1 hand ready=- landed=2026-10-20T03:54:44Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T27 hand ready=- landed=2026-10-20T03:57:02Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T26 hand ready=- landed=2026-10-20T03:57:49Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T30 hand ready=- landed=2026-10-20T03:58:32Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T3 hand ready=- landed=2026-10-20T04:34:49Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T21 hand ready=- landed=2026-10-20T04:49:05Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T18 hand ready=- landed=2026-10-20T05:03:48Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T43 hand ready=- landed=2026-10-20T05:15:15Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T45 hand ready=- landed=2026-10-20T06:11:34Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T23 hand ready=- landed=2026-10-20T06:32:06Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T25 hand ready=- landed=2026-10-20T06:40:04Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T16 hand ready=- landed=2026-10-20T06:53:33Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T14 hand ready=- landed=2026-10-20T06:56:26Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T29 hand ready=- landed=2026-10-20T07:14:32Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T20 hand ready=- landed=2026-10-20T07:23:55Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T31 hand ready=- landed=2026-10-20T07:26:20Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T19 hand ready=- landed=2026-10-20T07:53:25Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T28 hand ready=- landed=2026-10-20T07:54:46Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T2 hand ready=- landed=2026-10-20T08:01:29Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T22 hand ready=- landed=2026-10-20T08:08:18Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T32 queue ready=2026-10-20T08:14:56Z landed=2026-10-20T08:19:59Z minutes=5.0 runs=1 waited=15s wait=0.2 prove=4.6 rework=0.2 width=3
  landing-line-1.test.sh green promised=282s actual=273s ratio=0.97
T33 queue ready=2026-10-20T08:30:03Z landed=2026-10-20T08:31:41Z minutes=1.6 runs=1 waited=11s wait=0.2 prove=1.4 rework=0.0 width=3
  session-poker-4.test.sh green promised=74s actual=87s ratio=1.18
T24 hand ready=- landed=2026-10-20T08:31:51Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T17 hand ready=- landed=2026-10-20T08:34:07Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T44 hand ready=- landed=2026-10-20T09:17:48Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T34 queue ready=2026-10-20T09:21:17Z landed=2026-10-20T09:39:42Z minutes=18.4 runs=1 waited=1101s wait=18.4 prove=0.1 rework=0.0 width=1
  time.test.sh green promised=3s actual=3s ratio=1.00
T49 hand ready=- landed=2026-10-20T10:05:50Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T50 hand ready=- landed=2026-10-20T10:14:04Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T47 hand ready=- landed=2026-10-20T10:27:19Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T46 hand ready=- landed=2026-10-20T10:27:40Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T51 hand ready=- landed=2026-10-20T10:32:28Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T52 hand ready=- landed=2026-10-20T10:41:36Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T48 hand ready=- landed=2026-10-20T10:49:43Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T53 hand ready=- landed=2026-10-20T11:55:09Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T54 hand ready=- landed=2026-10-20T12:28:10Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T56 hand ready=- landed=2026-10-20T12:41:27Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T55 hand ready=- landed=2026-10-20T12:43:45Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T57 hand ready=- landed=2026-10-20T12:52:25Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T59 hand ready=- landed=2026-10-20T13:36:39Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T58 hand ready=- landed=2026-10-20T13:41:02Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T62 hand ready=- landed=2026-10-20T16:43:23Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T38 hand ready=- landed=2026-10-20T18:04:06Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T65 hand ready=- landed=2026-10-20T18:19:27Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T66 hand ready=- landed=2026-10-20T18:39:15Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
```

The three line landings are T32 and T33, the two one-file rows, at 5.0 and 1.6 minutes, and T34 at 18.4 minutes, of
which 18.4 were spent waiting for the gate. Every other row landed by hand and carries no ready time.

### Standing reds

The whole run at f7205ad6 left 12 red suites, each turned green by a fix row's own suites. No second whole run was
made past it: under D19 a head past it is proved by its landings' own green verdicts.

### Known limits

- the hand door accepts any ancestor of the row head as the commit the suites were green at, but the judge reads a
  verdict only at the merge or the row head, so a landing it accepts can later be refused as unproved
  (`critic-adversarial.md#5`).
- the review results page counts dropped rows as tasks not landed (36 of 53 now), where the sitrep leaves them out, so
  the two pages disagree on how much is left (`critic-adversarial.md#6`).
- the tests goal reads reached on wall time alone, so both pages show it met by a red whole run at a head nobody
  approved (`critic-adversarial.md#7`).
- the count of tasks has two owners, the review results page counting dropped rows and the sitrep
  (hooks/poker/sitrep.sh:803) leaving them out, and the pages disagree (`critic-structure.md#2`).
- a reached goal closes its decision only on the ticking session's own ledger, so the comments decision opened by an
  earlier session stays open after the goal reads reached, and the resume recap still lists it while the sitrep says
  you owe nothing (`critic-adversarial-2.md#1`).
- the waste line adds the gate's killed requests to the landing verdicts, so a run the carrier stopped counts twice
  (once as its discarded verdict, once as its killed request) and the base mixes every suite run under the root with
  landing verdicts (`critic-adversarial-2.md#2`).
- the line reads the user's order once per pass, before the drain, so a pass already past that check still starts its
  remaining suites and the red judge's run at the head while the order stands (`critic-adversarial-2.md#3`).
- the open decision joins the owed set on the page alone, so the resume recap of the same run still prints 'open: none
  — no decision is open' and 'owed now: nothing waits on you' while a decision is put and unruled
  (`critic-adversarial-3.md#1`).
- a decision a row waits on is owed twice, as the tick's approve:D<n> and the page's decide:D<n>, so You owe counts
  two for one reply (`critic-adversarial-3.md#2`).
- The plan validator has no check showing it refuses out-of-order rows; the rule holds, the check is written back next
  wave. AC-7.1 is waived at D20 (`auditor-evidence-2.md#2`).
- proof-add's refusal past the whole run still offers to run the whole at the head, the second whole run D16 and D19
  rule out (`auditor-evidence-2.md`, finding 1). AC-5.1 is waived and the fix carried to the next wave (D20).
- ADR-064 still says the comment lint runs at the landing line. The lint now runs at both landing doors, one function
  with one test, and the criterion was amended to say so after T57 (A-orch-D19.1).
- The tests goal's 45 minutes was read as the whole run's wall time, 1,159 seconds, where the summed suite time is
  7,422 seconds (`auditor-evidence-2.md`, finding 10).
- The debt ledger still names hooks/session-poker.sh lines past its new end (`critic-adversarial.md`, finding 8), and
  the structure readings added fourteen debt lines, among them two owners of the task count, of the run's owed set and
  of the approved-head rule.
- `_line_promise_total` still leaves a Lands-on command out of the printed promised total (A-T17.4).
- The cull left five doctored copies in release-check.test.sh that are built and never read
  (`critic-adversarial.md`, finding 12).

## 1.22.0 — 2026-10-19

This is the landing proof release: a verdict is a fact about what its suite read, keyed by the hash of those files, so
a landing reuses a green it already holds, skips a suite whose reads the diff does not meet, and the regression's judge
owes only the suites whose key moved (D5, ADR-061). A suite narrows what it reads by one declared line beside its
anchors (D6), no suite promises more than ten minutes on the gate (D1), the promise is scaled by load (D11), and the
15-minute landing bar is on the sitrep and the scorecard (D12, D25). A fix row born of a review finding is covered for
every review question once it lands (D7, ADR-062). This release reverses 1.21.0's fold (T17) of the Step-0 card into the
requirements card, on the user's word at D3: "I didn't want to eliminate step 0 configuration card. That's different
than requirements. It doesn't make sense to combine them." A clean run again has five human stops: the configuration
card, the requirements card, the design card, the plan card and the final card (D3, D4, D23). The typed and config
spellings of `floor` that 1.21.0 kept as aliases are removed, as 1.21.0 promised, and the spellings a delivered plan
already holds still read (D2). Thirty-eight build rows landed: eight through the line and thirty by hand, one before the
run's operating rules and twenty-nine under them (D26, D27). The one-file median that was this release's headline
number was measured after this entry was first written: the two one-file fix rows, T47 and T48, landed through the
line and took 58.4 minutes median against the 15-minute bar, a miss carried to the next charter; the numbers are
below. This is a minor
release by the policy above: the proof fact, the narrowing, the skip, the suite bar, the promise with load, the
`Re-executes:` landing and the restored Step-0 card are new capability, and the aliases go as 1.21.0 said they would.
`canonical_sdlc_version` stays 14.

**Migration.** Rename one key: `rigor-floor:` in `.bionic/config.yaml` or an epic plan's frontmatter is now refused,
naming `rigor-minimum:`, as this repository's own config was renamed (T18). Rows that changed what a script of yours
may meet:
- T18: the aliases 1.21.0 kept are removed. `floor-run`, `proof-add floor`, `--born floor:`, `proof:floor` typed in a
  reads argument, the `floor:` config key, a `floor-run-<sha>.log` whole-run log and `rigor-floor:` are each refused,
  nothing written, naming `regression-run`, `proof-add regression`, `--born regression:`, `proof:regression`,
  `regression-command:`, `regression-run-<sha>.log` and `rigor-minimum:`. `kind=floor`, `born: floor`, `of=floor` and
  `proof:floor` in a plan's reads cell still read, silently.
- T26: Step 0 puts its own card again. `card.sh step0 <plan>` renders the 1.20.0 shape and ends on the configuration
  question, and `card.sh step1` prints no Configuration section.
- T39: `ready` refuses a Lands-on suite whose gate promise is over 600 seconds with `too-long <suite> <s>s — split it`,
  exit 1, nothing run.
- T6, T35 to T38: close-out.test.sh is close-out-1 to close-out-4; landing-line, cross-gate-agreement and rc-item are
  `-1` and `-2`, and dispatch-preflight-4 is `-4a` and `-4b`, each part over a `<suite>.prelude.sh`. The old names are
  gone.
- T3, T43: a suite may declare `reads <file> fn <name>`, `reads <file> section <label>` or `reads <file> verb <name>`;
  a name the finder cannot locate at the tree is refused at index time, naming the line.
- T8: every verdict carries `promised=` and `actual=`, and `ready` prints `promised <t>s of <w>s`. T2: the landings line
  carries `reused=<n> absent=<n>` after `run=`, a zero included.
- T9: the schedule mark reads the plan's `forecast: <n>h` key; with none it prints ❔ beside the 15-minute bar.
- T10, T13: `row-landed --by-hand` writes `ev=published kind=hand`, which `landing-report` counts, and runs the release
  check over the accepted range; a hit is refused unless a passing `kind=check` proof stands at or past the commit.
- T20, T21: Lands-on admits a backticked command named under `Re-executes:`, judged by its exit code, and the budget
  wall admits a wrapper whose inner run is declared there.
- T25: the judge's refusal, the tick's wait reason and `regression-run`'s refusal each end on
  `waive regression '<reply>'`, and the final card offers the waiver only when the owed set is not empty.

### A proof is keyed by what it read (D5, D8, D9, D10, ADR-061)

ADR-061 records the rule: a proof is keyed by its inputs, never by a commit. It is Proposed until close-out.

- T1 (`T1-proof-fact.md`): `reads_hash <suite> <commit>` hashes the sorted path-and-blob lines of the suite's read set,
  closed over the scripts it runs and the libraries they load, with the suite file and its prelude; a suite the index
  cannot derive keys as `tree:<hash>`.
- T40 (`T40-one-key.md`): the narrowing moved from line.sh into `reads_hashes`, the one derivation the landing, the owed
  set and the regression facts read, and `reads_index_closed` was built for the judge.
- T2 (`T2-reuse.md`): the drain reuses a matching verdict and starts no runner; a carrier sent back to wait rebuilds
  and runs each suite once.
- T4 (`T4-skip.md`): `ready` skips a suite whose key equals the accepted head's with a green there, printing
  `skip <suite> reads=<h> (head)` and `suites <n> of <m>`.
- T24 (`T24-owed.md`): `proof_owed_suites <head>` is the suites whose key changed since the last whole run with no
  green at the new key, and the judge owes that set in place of a changed code file.
- T25 (`T25-owed-words.md`): the owed set is on every surface: the judge's refusal, the tick's wait reason and
  `regression-run`'s refusal end on `waive regression '<reply>'`, the final card shows the waiver only with a non-empty
  owed set, and a `waived: question=regression` line closes it through `current 8`.
- T45 (`T45-pc-owed.md`): dispatch-preflight's §PC pins the owed-set rule after an outside merge (a standing red that
  T24's hand landing left).
- T46 (`T46-owed-closed.md`): the judge joins a changed path to suites through the closed index, so every suite whose
  key moved is owed (critic-adversarial #1, S2, fixed in the wave).
- T19 (`T19-fixed-by-regression.md`): a finding counts fixed by a row with no verdict events when a green regression
  stands at a descendant of its landing; a suite the row removed is `result=absent` and not owed.

### A suite narrows its reads by one declared line (D6)

- T3 (`T3-narrowing.md`): `reads <file> fn <name>` and `reads <file> section <label>`, read by the anchor awk.
- T43 (`T43-verb-kind.md`): `reads <file> verb <name>`, every case arm whose label is the verb.
- T41 (`T41-declarations-a.md`), T42 (`T42-declarations-b.md`) and T44 (`T44-declarations-by-verb.md`): the suites
  that read hooks/session-poker.sh declare the verbs and functions they drive. T5 was split into T41 and T42. The
  hook's whole-file readers went from 55 at the base to 34.

### No suite is longer than a landing window (D1, D13)

- T6 (`T6-bar-and-split.md`): `LINE_SUITE_BAR=600`, and close-out.test.sh split in four over a prelude.
- T7 (`T7-splits.md`) was split into T35 (`T35-landing-line-split.md`), T36 (`T36-cross-gate-split.md`), T37
  (`T37-dp4-split.md`) and T38 (`T38-rc-item-split.md`), each suite in two over a prelude.
- T39 (`T39-too-long.md`): the refusal went live once every suite was under the bar; timing.tsv names the eight parts.
  The largest promise at 4edbbc04 is 521 seconds, over 117 suites (`logs/T28-promises.log`).

### The promise and the bars on the page (D11, D12, D25)

- T8 (`T8-promise.md`): the gate's promise is the median scaled by load now over load then, clamped and bounded by the
  largest kept, and `ready` waits a suite that cannot fit.
- T9 (`T9-bars.md`): `LINE_LANDING_BAR=15`, and the schedule mark grades rows landed per hour since the Step-3 approval
  against the pace the plan needs to close on its forecast. D25 amends wave 38's D10 and D12: three indicators stay,
  and the schedule one changes its basis to something the run cannot set for itself.

### A review's fixes are inside the review (D7, ADR-062)

- T15 (`T15-cover.md`): a fix row born of a registered review finding is covered for every review question once it
  lands; a marker naming no registered reading still owes on every chain. This reverses wave 36's D16; ADR-062 is
  Proposed until close-out.

### The Step-0 card is its own stop again (D3, D4, D23)

- T26 (`T26-step0-card.md`): `card.sh step0` returns in the 1.20.0 shape, `card.sh step1` drops its Configuration
  section, and SKILL.md, steps/0.md and steps/1.md say five human stops. ADR-059 is amended in place. D4 shipped it in
  this release rather than in a 1.21.1. This run's own Step-0 card was put by hand in the 1.20.0 shape (A-orch-1).

### The floor aliases go (D2)

- T18 (`T18-aliases.md`): `lib/alias.sh` holds two tables, the plan-read rows read silently and the typed and config
  rows refused at their one seam each; this repository's `rigor-floor:` became `rigor-minimum:`.

### The hand landing is recorded, timed and scanned (D14)

- T10 (`T10-sitrep-shapes.md`): the Situation times every landed shape, lists the run in execution order with steps 0
  to 3, and `row-landed --by-hand` writes `ev=published kind=hand`.
- T13 (`T13-hand-scan.md`): `row-landed --by-hand` runs the release check over the accepted range, and a hit names its
  commit, path and the rewrite line.

### A landing may re-execute a command (D19, D20)

- T20 (`T20-reexec-landing.md`): a backticked `Re-executes:` command lands with verdict events, green on exit 0.
- T21 (`T21-wrapper.md`): the budget wall admits a wrapper whose inner run is declared, and refuses an undeclared one
  naming its target.

### The run's surfaces tell the truth (D15, D16, D21, D22)

- T11 (`T11-register.md`): the decisions register reads amended, ratified, final, a qualifier and the `ruled:` heading.
- T12 (`T12-model.md`): a dispatch that names no model journals the role file's `model-effort`.
- T22 (`T22-quiet.md`): the quiet check reads the landing carrier and the gate's open request before the mtimes, so a
  writer blocked in `ready` is active.
- T23 (`T23-brief.md`): the brief unions the reads index into `Suites:` and `Lands-on:` whatever the plan row's cell.

### Five readers folded (D18)

- T16 (`T16-folds-a.md`): one reader of the integration branch for close-out and the handoff verb, and one of the
  handoff pointer.
- T17 (`T17-folds-b.md`): one `iso_epoch`, one landing-key alphabet and one named-field reader of the landing record.
  Five debt lines are burned (`debt list`, AC-12.2).

### The launchers reset signals (D17)

- T14 (`T14-signals.md`): `regression-run`, tests/run.sh and `booked.sh --detach` reset HUP, INT and QUIT through perl
  before starting.

### The release (D24)

- T32 (`T32-release.md`): this entry, plugin.json 1.22.0, the help and version pages rendered by
  `agents-src/render.sh`, `rendered.sha256` refreshed, and release-check.test.sh §REL-1.22.0 pinning the alias removal,
  the reversal and this entry's parts.

### How this run landed (D26, D27)

D26 and D27 are not product decisions. They are this run's operating rules, and they changed how rows landed, not what
bionic does. D26 landed a row that changes how landings work by hand on its in-tree greens, the row after it through
the line being the proof. D27 extended that to any row whose line landing would exceed 30 minutes, the whole regression
at Step 6 covering the merged head once. Twenty-nine rows landed under them (T6 landed by hand before them, A-orch-7).
Four of those hand landings each left a red that a later landing found and fixed: T24 left dispatch-preflight §PC
(fixed by T45), T40 left framework §21 (fixed by T41), T22 left the shell-lint clock ledger (fixed by T25), and T20
left a reads-hash anchor (fixed by T17) (A-orch-28, A-orch-71). T26's writer was stopped and its record written by the
orchestrator (A-orch-36).

### The readings

- The walk (`walk.md`, T27): eight scenes, no criterion named; its observations are below.
- The matrix (`T28-matrix-fill.md`, T28): 45 of 49 rows discharged; AC-13.2, AC-19.1 and AC-20.3 wait for this row
  and AC-11.3 for ADR-062 at close-out.
- The auditor (`auditor-evidence.md`, T29): REFUTED, with 37 confirmed, 5 refuted and 7 unverifiable, on three gaps of
  substance: the owed set proven only for direct readers (REQ-18, fixed by T46), the regression fix only for the
  `landed:` header (REQ-14) and the one-file median unmeasured then (REQ-5); T47 and T48 measured it afterwards, at
  58.4 minutes against the 15-minute bar, a miss carried to the next charter. Three refuted cells were given their
  replacement evidence (A-orch-77).
- The critic (`critic-adversarial.md`, `critic-structure.md`, T30): four adversarial findings, one S2 fixed by T46, two
  S3 deferred and one S4 note; one structure finding, the same defect, fixed by T46, and one debt line.
- The regression (T31): one whole run at 44666977, running as this entry was written; its result is under Standing
  reds.

### The landing numbers

`landing-report --rows` at 44666977 (`logs/T28-landing-report-rows.log` holds the same numbers at 4edbbc04, before
T46's hand landing):

```
landings: queue=6 hand=30 git=0 · ready-to-landed median=119.6m p75=176.4m max=278.1m · runs: green=557 red=3 none=1 discarded=10 red-then-green=0 run=346 reused=8 absent=0 · waited median=949s · killed=19
T3 queue ready=2026-10-18T16:57:44Z landed=2026-10-18T19:04:34Z minutes=126.8 runs=109 waited=391s wait=6.5 prove=120.3 rework=0.0 width=4
T1 queue ready=2026-10-18T17:51:46Z landed=2026-10-18T22:29:53Z minutes=278.1 runs=205 waited=4711s wait=78.5 prove=173.2 rework=26.4 width=4
T4 queue ready=2026-10-18T23:24:11Z landed=2026-10-19T01:16:37Z minutes=112.4 runs=40 waited=1492s wait=24.9 prove=87.6 rework=0.0 width=3
T8 queue ready=2026-10-19T00:30:43Z landed=2026-10-19T03:43:42Z minutes=193.0 runs=71 waited=5451s wait=90.8 prove=102.1 rework=0.0 width=4
T9 queue ready=2026-10-19T04:45:25Z landed=2026-10-19T06:21:32Z minutes=96.1 runs=70 waited=290s wait=4.8 prove=91.3 rework=0.0 width=3
T2 queue ready=2026-10-19T06:23:24Z landed=2026-10-19T07:58:31Z minutes=95.1 runs=62 waited=405s wait=6.8 prove=88.4 rework=0.0 width=2
```

| | wave 38 | wave 39 |
|---|---|---|
| ready-to-landed median | 303.9 m | 119.6 m |
| p75 | 449.9 m | 176.4 m |
| max | 1763.2 m (T8) | 278.1 m (T1) |
| min | 43.0 m (T36) | 95.1 m (T2) |

Wave 39's numbers are over the six multi-file build rows it landed through the line before the one-file fixes; its
thirty hand landings carry no ready time. `reused=8` is
T2's landing: eight suites skipped on T9's greens, `suites 62 of 70`, the first narrowed landing (A-orch-34,
A-orch-38). T9 before it ran 70 of 70 with nothing reused, because the night's hand landings had moved every key
(A-orch-33). The one-file median was measured afterwards: the two one-file fix rows, T47 and T48, landed through the line
at 58.2 and 58.5 minutes, a median of 58.4 against the 15-minute bar, so AC-5.3 is a miss by measurement, about four
times the bar, carried to the next charter (`T28-matrix-fill.md`).

The scorecard at the same head, `landing-report --scorecard`:

```
human stops (autonomous half): 0 · target 1
agent minutes after the final reply: unverified · target 0
widest landing ready→landed: T1 278.1 min · target < 15
human-wait minutes: unverified · no target (the user's)
✖️ schedule — 40 of 44 landed in 21h, pace needs 38 · median ready→landed 119.6m over the 15m bar
✖️ correctness — 3 red, all returned, 2 open S1/S2
✅ waste 2% discarded · 0% idle-width
```

### Standing reds

The whole regression (T31) ran at 44666977 on 2026-10-19 from 5:59 to 6:45 AM PDT: 115 of 117 suites green, two red,
both left by hand landings. `regression-rename.test.sh` (§AS-1, §AL-2: the retired token `floor` at
hooks/session-poker.sh:5199, written by T25 after T18 removed the alias) is fixed by T47, landed through the line at
39288958. `refuse.test.sh` (§INV: the file-scope refusal T20 added at hooks/dispatch-preflight.sh:3027 had no bullet in
tests/fixtures/refusal-inventory.md) is fixed by T48, landed through the line at 3d9b9b77. Each fix row ran its red
suite red, then green, and the line ran the suites that read the changed file (62 of 63 for T47, 5 of 5 for T48). No
red stands at the release head. A second whole run at 4dfc59df, approved by the user, was 117 of 117 green (11:46 AM to
12:30 PM PDT).

### Known limits

- a fix row marked by row-landed --by-hand alone is never fixed by a green regression: T10 writes ev=published kind=hand, and T19's arm reads only landed: headers (`critic-adversarial.md#2`). Land a review-born fix row with
  `spawn-worktree.sh land <tree> --by-hand`, which writes the header.
- AC-14.1's fixture plants only a landed: header, so a row marked by row-landed --by-hand, the shape 28 of 35 rows took,
  is never shown fixed by a green regression (`auditor-evidence.md`, finding 2; REQ-14).
- a Lands-on command (T20) is never held to the suite bar (T39): the merge-holds test reads the command as a file the
  candidate lacks and skips it (`critic-adversarial.md#3`). Behind the holds test, `_line_too_long` also keys a
  command's promise by the suite-name reader and reads 0; `_line_gate_key` is the right call (A-orch-69).
- ready's promised total (T8) still adds the promise of a suite the row removed, which the carrier records absent and
  never runs (T6) (`critic-adversarial.md#4`, A-orch-67). No suite starts short, because waits are per suite.
- AC-5.3's number, the one-file fix rows' median, was measured on T47 and T48, the two one-file fix rows that landed
  through the line: 58.4 minutes against the 15-minute bar, a miss carried to the next charter (`auditor-evidence-2.md`,
  finding 3; REQ-5). The six multi-file build rows before them took 95.1 to 278.1 minutes.
- AC-2.4 was observed live on T47: ready printed `suites 62 of 63` for a one-line session-poker.sh change, against the
  criterion's 55, a miss carried to the next charter (`auditor-evidence-2.md`, finding 4).
- AC-8.1 is confirmed, and the evidence is in the wave's record:
  `regression-run-44666977dd5b15448379f0b367d9388fdeb54e08.log`, T31's whole run, reads `head=44666977… dirty=0` on its
  first line and `dispatch-preflight-2.test.sh ✓ PASS` on line 34, and T12's commits are ancestors of that head
  (`auditor-evidence-2.md`, the AC-8.1 row).
- A hand landing behind a line entry rebuilds its candidate on every 0.2-second poll while the entry ahead has not
  published: behind T9 it minted 1,298 candidates in 16 minutes, each a git merge (A-orch-25). `_line_hand` should
  rebuild only when the base moved, as `_line_carry` does.
- A hand landing runs none of its row's Lands-on suites, so four of this run's left a red that a later landing found
  (A-orch-71). The whole regression is the only reading of the merged head.
- A one-line change to lib/proof.sh now owes 117 suites, and the judge's walk takes 52 seconds cold (A-orch-79).
  Fixtures that assert a short owed set may read red under the wider set.
- Six sites read a landing-record field outside line.sh's reader: `fv` in `landing_evidence` beside `line_kv`, and
  positional readers in proof.sh, session-poker.sh's `row-landed` and line.sh (`critic-structure.md`, debt
  `landing-record-reader`), with `_line_count_git` and the tick's landing ETA (A-orch-72).
- T25's concerns (A-orch-68): close-out-1 1ag and close-out-3 INSERT.8 assert on an unbound marker and prove nothing;
  dispatch-preflight's second-regression refusal and close-out's WOULD REFUSE print no waiver; the tick does not name
  the owed set.
- card.sh and walls.sh keep three more readers of the integration branch, and session-start keeps its own handoff
  pointer reader (A-orch-57). The sweeper keeps its own `iso_epoch` by design, and suites that copy the hook resolve the
  main checkout's libraries mid-wave (A-orch-72).
- A row the regression fixed still reads `landed green at <commit>` in its disposition (A-orch-66).
- payload/context/severity.md keeps the sentence D7 replaced, and ADR-056's decision text is unamended until ADR-062 is
  Accepted (A-orch-59).
- The floor allow-list shrank by one line only, to 27, because every pattern still admits lines the tree needs
  (A-orch-44). The heredoc readers at anchors.sh and assert.sh are carried (A-orch-22b).
- tests/dispatch-preflight.prelude.sh still says four shards, and about 100 comment lines name
  cross-gate-agreement.test.sh by its old name (A-orch-46, A-orch-47).
- The walk's observations (`walk.md`, A-orch-74): the sitrep printed no Landings block and a stale Bottom line with
  `approve:step1` still under Blockers; the Step-1 card prints empty Requirements and Not Doing headings;
  `landing-report --rows` shows reuse only as `reused=8` in its header, and T2's row omits its eight reused suites;
  the owed set at a docs-only commit prints `*` while no regression fact exists; the commit wall gave two contradictory
  `git -C` refusals on one command; the brief verb rewrites everything above `## Judgment`.

Of 1.21.0's twenty-one Known limits, seven are closed and fourteen are carried:
- ~~The gathered landing by hand skipped the release-name scan~~: closed by T13 (`T13-hand-scan.md`).
- ~~A whole run launched with HUP, INT and QUIT ignored paints the signal suites red~~: closed by T14
  (`T14-signals.md`).
- ~~A single suite near a writer's 30-minute Bash ceiling cannot land through `ready`~~: closed by T6 and T35 to T39;
  no suite promises over 600 seconds (`T39-too-long.md`).
- ~~Situation shows the landing time only for a bare `landed <sha> <ISO>` line~~: closed by T10
  (`T10-sitrep-shapes.md`).
- ~~A test-runner dispatch that names no model journals an empty `model=`~~: closed by T12 (`T12-model.md`). The
  auditor could not verify the cell's log (finding 6 above).
- ~~The decisions register reads `ruled`, `re-ruled` and `withdrawn` only~~: closed by T11 (`T11-register.md`).
- ~~`landing-report` reads `hand=0` though fourteen rows landed by hand~~: closed by T10; this run's report reads
  `hand=30`.
- Carried, narrowed: every landing missed the target again, now 15 minutes; the promise is scaled by load (T8), and the
  gap a `WAITING` exit leaves for a younger landing (A-orch-62 of 1.21.0) is not addressed.
- Carried, narrowed: of T37's three concerns, the handoff verb's own integration-branch reader is folded by T16; the
  `archive-on-close: false` plan and the third close-out run carry.
- Carried, narrowed: a regression proof behind the head offers the waiver only when the owed set is not empty (T25),
  where a review reading behind the head stays `CARD-EARLY`.
- Carried, narrowed: of the seven debt lines 1.21.0 added, T16 and T17 burned five (`iso-to-epoch`,
  `handoff-pointer-reader`, `landing-key-alphabet`, `landing-record-grammar`, `integration-branch-reader`), and
  `approval-names` and `closed-form-instant` stand (`logs/T28-debt-list.log`).
- Carried as they stood, not re-triaged: resume arms the Patrol whatever the scale; a standing order `refuse: suite` lets `ready` and
  `regression-run` through; the forecast divides by the admitted-run count; the closed form reads `co_pr_owed` after
  the close; a red-check `CARD-EARLY` names the check's first line; the walk's six observations of 1.21.0; the stop
  count reads `approved:` lines only; the release row lands after the readers; Blockers is not pinned for `finding:`
  and `gate:` items; the tolerance marks' colours are the emoji font's.

## 1.21.0 — 2026-10-18

This is the one-stop release: on a clean run the user is asked four things, the requirements card, the design card,
the plan card and one final card before the merge, and everything else reaches them as a default they can override
(D17, ADR-059). The final card is rendered by the tool from the record and refuses itself while a reader is open
(D19, D20), and a release commit is covered by its own check (D18). The situation report is one renderer behind
three surfaces, `/bionic:sitrep`, the handoff head and the tick (D8 to D14, D29 to D31). The handoff file is the store
and `/bionic:canonical-sdlc <handoff.md>` is the one door back in (D4, D23, D24). The gate is the one owner of
capacity, and every landing asks it for its width (D21, D22, ADR-060). Scale is a profile row (D25), close-out parks,
scores and asks nothing (D26), standing orders live in the config (REQ-7), and the test runner runs on Haiku at high
effort (REQ-8). This release reverses 1.14.0's promise that the regression's verbs and keys keep their spelling until bionic2: T8 renamed them to
`regression-run`, `proof-add regression`, `regression-command:` and `proof:regression`, and each old spelling,
`floor-run`, `proof-add floor`, `floor:` and `proof:floor`, is kept as an alias that works until 1.22.0 and prints one
`deprecated:` line when a person types it (D6, `T8-rename.md`). Twenty-nine build rows landed, eight of them fix rows:
three born of the red regression, two born of the review and three born of the run's own landings and rulings. The
regression ran once, at d3c4ed2e, and was red on 12 of 108 suites (`regression-run-d3c4ed2e4cd06db412f1acaa18a800111af36844.log`);
each of the twelve went green in a later landing, so the settled head is covered by rule (`T27-regression.md`,
`A-orch-74`). Every landing missed the 30-minute target, and the numbers are below. This is a minor release by the
policy above: the final card, the sitrep, the handoff file, the scale profile, standing orders and the gate's width are
new capability, and the renamed tokens keep their old spellings as aliases. `canonical_sdlc_version` stays 14.

**Migration.** No artifact needs migrating. Old plans, config keys and reads cells still read. Rows that changed what a
script of yours may meet:
- T8: `floor-run`, `proof-add floor`, `floor:` and `rigor-floor:` in `.bionic/config.yaml`, `proof:floor` in a reads
  cell, `kind=floor` and `born: floor` each still work and print `deprecated: <old> is <new>; the old spelling works
  until 1.22.0` once per process when typed or read from config. Rename `floor:` to `regression-command:` and
  `rigor-floor:` to `rigor-minimum:` in `.bionic/config.yaml` before 1.22.0.
- T13: there is no `/bionic:resume`; resume with `/bionic:canonical-sdlc <path to handoff.md>`, the last line the
  handoff file prints.
- T12: the plan's `## Handoff` section is one pointer line, `handoff: <path> written <local time>`; the handoff itself
  is `record/<wave>/handoff.md`.
- T17: no Step-0 card is put. Configuration is the first section of the requirements card.
- T16: a `scale: task` run arms no Patrol, takes single rigor unless flagged, three writers, no regression, any branch,
  and integrates by a pull request.
- T18: an item of `standing-orders:` in `.bionic/config.yaml` that ends `| refuse: <class>` refuses commands of that
  class on every thread.
- T20: a `- session:` line under `## SDLC State` counts as a witness only when a binding act wrote it; a hand-added
  line naming another session is refused, naming the missing binding act.
- T21: a `Kind: prototype` dispatch is admitted before plan approval when every Files path is under `record/` or the
  declared throwaway tree, and refused on any tracked path.
- T1: `current <N> --check` is new for N from 5 to 8; any other step or a misplaced `--check` is a usage error, exit 2.

### The final card is the one stop (D17, D19, D20, ADR-059)

ADR-059 records the four human stops.

- T1 (`T1-check.md`): `session-poker.sh current <N> --check` runs the advance's dry commit and judge, writes nothing
  and exits as the advance would.
- T3 (`T3-final-card.md`): `card.sh final <plan>` renders the decision shape from the owed ledger, the matrix and the
  findings disposition, every default shown and option 1 accepting them all, and refuses `CARD-EARLY — <reason>` on an
  open reader, an unregistered reading or a red check; `session-poker.sh reply '<text>'` replays one reply into
  approve, waive, waive-row, waive regression and finding-move with the user's words.
- T36 (`T36-waiver.md`): the card asks the regression in waive mode where it offers the waiver, so a red check on the
  regression renders the waiver option instead of `CARD-EARLY` (critic-adversarial #1, S2 on).
- T17 (`T17-config.md`): the requirements card opens on Configuration with the scale recommendation in two sentences,
  and its Inherited block is one line of counts (D5).

### A release commit is covered by its own check (D18)

- T2 (`T2-cover.md`): a commit whose every path is in the release set (CHANGELOG.md, plugin.json,
  `payload/commands/*.md`, `rendered.sha256`) is covered by a passing `kind=check` proof at that head; a merge whose
  tree equals its first parent's is proved by that parent; `waive regression '<reply>'` and `waive all '<reply>'` write
  the user's word once.
- T22 (`T22-release.md`): this entry, plugin.json 1.21.0, the help and version pages rendered by
  `agents-src/render.sh`, `rendered.sha256` refreshed, and release-check.test.sh §REVERSE pinning the reversal
  sentence above (AC-9.5).

### The situation report (D8, D9, D10, D11, D12, D13, D14, D29, D30, D31)

- T10 (`T10-sitrep.md`): `session-poker.sh sitrep [--line]` prints Situation (every row, contiguous, with its state
  mark and local landing time), Assessment (schedule, correctness and waste, each with its number), Blockers and
  Forecast (percent landed and a closing time from measured pace, the user's waits stated apart); `sitrep bottom-line`
  records the judgment items to `record/<wave>/sitrep.log`.
- T11 (`T11-sitrep-skill.md`): `/bionic:sitrep` runs the verb, fills Bottom line and Diagnosis, alters no rendered
  line and records the items; the tick prints the one-line form.
- T35 (`T35-marks.md`): each Assessment line opens on a tolerance mark, ✅ within the bar · ➖ near it · ✖️ over it ·
  ❔ not measurable, and the thresholds print once, under the block (D29, D31).

### The handoff file and the one door (D3, D4, D23, D24)

- T12 (`T12-handoff.md`): `handoff [path]` writes `record/<wave>/handoff.md`, kind line first, the sitrep head, the
  machine lines, the five human lines carried when absent, and the literal next command; a delivered plan gets the
  closed form instead of a refusal.
- T13 (`T13-door.md`): `/bionic:canonical-sdlc <handoff.md>` binds, arms, adopts and prints the recap from the file;
  the `/bionic:handoff` skill; `decisions [--all]` lists the design ledgers' rulings by run.
- T14 (`T14-adopted.md`): `stopped` finds an adopted row's landed mark on every roster of the project (L12, D2).
- T37 (`T37-handoff-closed.md`): the closed handoff form has one writer, close-out, and the verb reads it, so a parked
  or pull-request run reads PARKED or "to be pulled", never "merged" (critic-adversarial #2, critic-structure #1).

### Close-out parks, tolerates and scores (D3, D26)

- T15 (`T15-closeout.md`): a plan with a Wake Note or a `parked:` line closes without the merge act; prose debt lines
  are skipped with a note and a missing epic table is added (D3); the continuation carries the four-line scorecard
  and the three indicators beneath it; close-out asks nothing.

### Scale is a profile row (D25)

- T16 (`T16-scale.md`): `lib/scale.sh` holds one row per scale (patrol, rigor default, writer cap, regression default,
  branch pattern, integrate act, reader dealing), the five readers take their cell from it, and SKILL.md's scale table
  is pinned to it.

### The gate owns capacity (D21, D22, D27, ADR-060)

ADR-060 records the one width rule.

- T5 (`T5-gate.md`): `gate_width_ask <landing>` answers how many runners a landing may start now, the oldest active
  landing first; the per-run promise is the measured suite cost; a killed waiter keeps its number.
- T6 (`T6-drain.md`): the drain asks the gate before each pass and as each run ends and launches exactly that many.
- T7 (`T7-orders.md`): the tick offers ready rows longest chain first and prints `SPLIT <id> — <reason>` when width
  idles; `landing-report` splits wait, prove and rework.
- T30 (`T30-oldest.md`): the oldest landing keeps its place across the gaps between its runs.
- T31 (`T31-waits.md`): a suite's promise is robust to one contended run, a dead landing request is ended, and
  `ready` prints why it waits on every `WAITING` exit.
- D27 (`A-orch-14`): a finished writer holding for its landing turn stays on the panel.

### Standing orders (REQ-7)

- T18 (`T18-orders.md`): `standing-orders:` in `.bionic/config.yaml` is printed at session start and in the resume
  recap, and an item ending `| refuse: <class>` is enforced by the bash walls.

### The test runner on Haiku (REQ-8)

- T4 (`T4-runner.md`): the test-runner role reads `model: haiku`, `effort: high`, and its roster row journals the
  model the call names.

### "Floor" leaves what bionic says (D6)

- T8 (`T8-rename.md`): one alias map, `lib/alias.sh`, renames the regression's machine tokens at one seam each and
  keeps every old spelling for one release.
- T9 (`T9-words.md`): every message, usage line, card line and doctrine sentence says regression or rigor minimum; a
  static pin greps the user-facing trees against `tests/fixtures/floor-allowlist.txt`.
- T33 (`T33-words.md`): the rename's residue after the gathered merge, the name scan's signal case and two
  cross-gate pins (born of the regression).

### Inherited leftovers (D1, D2, D5)

- T19 (`T19-rules.md`): a decline `--on <row>` holds until that row lands (L5); `suites` and `lands-on` are optional
  columns of the units contract (L7); the slug reader's dry-copy arm is removed (L11).
- T20 (`T20-witness.md`): a witness is a binding act (L6), and `tests/lib/release-check.sh` holds the shipped
  release's Known limits to every stated deferral of its plan (L8).

### A prototype dispatch the wall admits (D16)

- T21 (`T21-prototype.md`): the dispatch wall admits a confined `Kind: prototype` dispatch before approval, and one
  agreement test pins the step files' promised dispatches to the wall's admitted set (REQ-13).

### The gathered landing and its fix rows (D28)

D28 option 3 gathered fourteen built rows (T3, T7, T9, T11 to T21) into one candidate, fast-forwarded onto the wave
branch at d3c4ed2e and proved by one whole regression run there (`A-orch-64`, `A-orch-67`). That run was red on 12
suites, and three fix rows took them:

- T32 (`T32-reconcile.md`): the merge's stray conflict markers and the session-poker pins two rows moved at once.
- T33 (`T33-words.md`): the rename residue, above.
- T34 (`T34-fixes.md`): refusal sites without inventory bullets, the 1.18.0 and 1.19.0 entry rules, and the units,
  worktree and slots pins; it also removed a private project name from tests/dispatch-preflight-5.test.sh (A-T34-6).

### The frame (D7, D15)

D7, the sitrep taken verbatim from the notes, was withdrawn on the user's word, and the report was designed from first
principles (D8 onward). D15 set the walk order of the strategic cards. The design ledger, `design-ledger.md`, holds
every ruling with the user's words.

### The readings

- The walk (`walk.md`, T23): bionic used as a user would on this branch, with six observations, below.
- The matrix (`T24-matrix-fill.md`, T24): 48 of 52 rows discharged from landed records; AC-1.5 and AC-6.6 wait for
  close-out, and AC-9.5 and AC-12.1 for this row.
- The auditor (`auditor-evidence.md`, T25): REFUTED, with 39 confirmed, 10 refuted and 3 unverifiable.
- The critic (`critic-adversarial.md`, `critic-structure.md`, T26): six adversarial findings, two S2 fixed by T36 and
  T37, three S3 deferred, one S4 note; one structure finding, fixed by T37. The piece reading of T36 and T37
  (`critic-adversarial-2.md`, `critic-structure-2.md`) flagged two S3 findings, deferred, and three S4 notes.
- The regression (`T27-regression.md`, T27): covered by rule at the settled head; the verb refused a second whole run.

### The landing numbers

`landing-report --rows` at the wave's head 74a11248 (`logs/T22-landing-report-rows.log`). T1, T2, T4, T5, T6, T8 and T10
landed on the drain at width 7, before T30 made the gate's answer the width; T30 onward ran at the width the gate gave.
T7, T19, T20 and T21 read `git` because they landed in the gathered candidate:

```
landings: queue=15 hand=0 git=4 · ready-to-landed median=303.9m p75=449.9m max=1763.2m · runs: green=1607 red=35 none=1 discarded=87 red-then-green=0 run=355 · waited median=5888s · killed=46
T1 queue ready=2026-10-16T05:35:07Z landed=2026-10-16T09:08:37Z minutes=213.5 runs=49 waited=- wait=- prove=- rework=0.0 width=7
T10 queue ready=2026-10-16T06:04:50Z landed=2026-10-16T13:06:02Z minutes=421.2 runs=90 waited=- wait=- prove=- rework=17.9 width=7
T2 queue ready=2026-10-16T11:07:31Z landed=2026-10-16T19:06:02Z minutes=478.5 runs=152 waited=- wait=- prove=- rework=2.3 width=7
T4 queue ready=2026-10-16T04:54:43Z landed=2026-10-17T03:50:19Z minutes=1375.6 runs=270 waited=- wait=- prove=- rework=476.5 width=7
T5 queue ready=2026-10-16T10:27:40Z landed=2026-10-17T07:36:24Z minutes=1268.7 runs=254 waited=- wait=- prove=- rework=27.6 width=7
T8 queue ready=2026-10-16T07:28:01Z landed=2026-10-17T12:51:14Z minutes=1763.2 runs=257 waited=- wait=- prove=- rework=1119.2 width=7
T6 queue ready=2026-10-17T12:52:21Z landed=2026-10-17T14:20:49Z minutes=88.5 runs=47 waited=- wait=- prove=- rework=6.2 width=7
T30 queue ready=2026-10-17T14:30:17Z landed=2026-10-17T19:34:12Z minutes=303.9 runs=47 waited=12921s wait=215.3 prove=88.6 rework=0.0 width=4
T31 queue ready=2026-10-17T15:49:55Z landed=2026-10-17T21:21:06Z minutes=331.2 runs=121 waited=8123s wait=135.4 prove=191.8 rework=4.0 width=4
T20 git ready=- landed=2026-10-17T22:57:22Z minutes=- runs=13 waited=- wait=- prove=- rework=- width=-
T21 git ready=- landed=2026-10-17T22:57:22Z minutes=- runs=7 waited=- wait=- prove=- rework=- width=-
T19 git ready=- landed=2026-10-17T22:57:22Z minutes=- runs=11 waited=- wait=- prove=- rework=- width=-
T7 git ready=- landed=2026-10-17T22:57:22Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-
T34 queue ready=2026-10-17T22:57:56Z landed=2026-10-18T02:04:55Z minutes=187.0 runs=56 waited=5824s wait=97.1 prove=89.9 rework=0.0 width=4
T33 queue ready=2026-10-17T23:35:59Z landed=2026-10-18T03:13:15Z minutes=217.3 runs=49 waited=8905s wait=148.4 prove=68.8 rework=0.0 width=4
T32 queue ready=2026-10-17T22:57:22Z landed=2026-10-18T05:09:19Z minutes=371.9 runs=124 waited=326s wait=5.4 prove=156.2 rework=210.3 width=1
T35 queue ready=2026-10-18T02:52:28Z landed=2026-10-18T06:19:30Z minutes=207.0 runs=100 waited=5952s wait=99.2 prove=107.2 rework=0.6 width=4
T36 queue ready=2026-10-18T06:50:09Z landed=2026-10-18T07:33:06Z minutes=43.0 runs=23 waited=59s wait=1.0 prove=42.0 rework=0.0 width=4
T37 queue ready=2026-10-18T08:18:24Z landed=2026-10-18T09:23:36Z minutes=65.2 runs=60 waited=68s wait=1.1 prove=64.1 rework=0.0 width=4
```

| | wave 37 | wave 38 |
|---|---|---|
| ready-to-landed median | 206.3 m | 303.9 m |
| p75 | 262.8 m | 449.9 m |
| max | 490.6 m | 1763.2 m (T8) |
| min | 86.9 m (T19) | 43.0 m (T36) |

The scorecard (D26) at the same head, `landing-report --scorecard` (`logs/T22-scorecard.log`):

```
human stops (autonomous half): 0 · target 1
agent minutes after the final reply: unverified · target 0
widest landing ready→landed: T8 1763.2 min · target < 30
human-wait minutes: unverified · no target (the user's)
✖️ schedule 5.07× — median ready→landed 303.9m over median declared 60m
➖ correctness — 35 red, all returned, no open S1/S2
➖ waste 5% discarded · 0% idle-width
```

The two unverified lines are read at close-out, after the final reply. The stop count reads `approved:` lines only, so
it does not see the rulings D28 to D31 the user gave mid-run (Known limits below). T8's 1763.2 minutes are 1119.2 of
rework; the two landings after the readings, T36 and T37, took 43.0 and 65.2 minutes at width 4.

### Standing reds

The release check from 433f7134 to the head is red on two historical blobs of tests/dispatch-preflight-5.test.sh
that carry a private project name; the current file is clean. Row T38 runs the check again after the user rules on
the history, and this release is not published until it passes.

### Known limits

- resume arms the Patrol and tells the model to create its cron job whatever the scale, though T13's row says 'arm per
  the scale profile' (`critic-adversarial.md#3`). Delete the cron job by hand on a task-scale run.
- a standing order 'refuse: suite' lets spawn-worktree.sh ready and session-poker.sh regression-run through, the two
  ways the run actually starts suites (`critic-adversarial.md#4`). Tell the orchestrator in words.
- the forecast divides the remaining critical path by the machine's admitted-run count, so it moves earlier by the
  number of runs admitted (`critic-adversarial.md#5`). The basis line prints the width it divided by.
- a regression proof that is merely behind the head now settles into a 'waive regression' default on the final card,
  where a review reading behind the head stays CARD-EARLY (`critic-adversarial-2.md#1`). Withhold the waiver to have
  the regression run.
- the verb's closed form reads co_pr_owed after the close, so a squash-merged or locally deleted task branch is written
  'to be pulled into' the integration branch for good (`critic-adversarial-2.md#2`).
- A red-check `CARD-EARLY` names the check's first line, `current 7 --check: would refuse`, not the wall that refused;
  run the check again to read it (`critic-adversarial.md#6`).
- Every landing of this wave missed the 30-minute target: the widest, T8, took 1763.2 minutes and the narrowest, T36,
  43.0 (AC-6.6). A `ready --within` that exits `WAITING` leaves a gap in which a younger landing is admitted and rebuilt
  for nothing (`A-orch-62`), and the suite promise is under-calibrated against measured load, so builders starve a
  landing (`A-orch-63`).
- The gathered landing by hand (D28) skipped the release-name scan that `ready` runs, so a private name reached the
  branch at d3c4ed2e (`A-orch-71`); `land --by-hand` should run the same check. The name left the current file in T34,
  but two historical blobs keep it, and this entry's own check is red on them until the user rules on the history
  (`A-orch-78`, row T38).
- A whole run launched with HUP, INT and QUIT ignored paints the signal suites red; the runner should reset the three
  signals before starting its workers (`A-orch-69`).
- A single suite near a writer's 30-minute Bash ceiling cannot land through `ready`: close-out.test.sh's promise
  reached 1706 seconds under load (`A-orch-73`). It should be split, or run detached and followed across calls.
- The walk's six observations (`A-orch-75`, `walk.md`): version.sh prints the commit the session loaded, not the head;
  `CARD-EARLY` names only the first open reader, and `card.sh early` exits 1 like `final`; Bottom line `(line n)`
  citations drift when the Bottom line changes length; the tick listed T23 among the writers of `proof:regression` and
  printed `SPLIT` beside `room=yes`; the header comment of session-poker.sh still says floor-run; a read-only row cannot
  land through `ready` from the main checkout, and the route, `session-poker.sh deliver <id>`, was named in no brief.
- T37's three concerns (`A-orch-77`): the handoff verb's open form keeps its own integration-branch reader beside
  close-out's; a plan closed with `archive-on-close: false` and archived later cannot be bound by the verb, and its
  closed file names the old path; close-out.test.sh ran three times in T37 where the brief allowed two.
- The stop count on the scorecard reads `approved:` lines only, so it misses the rulings D28 to D31 the user gave after
  the plan card, and no defect row counts them (auditor I1).
- The release row lands after the readers, so AC-9.5 and AC-12.1 were not read in the auditor's one pass (auditor I4).
- Situation shows the landing time only for a bare `landed <sha> <ISO>` line, so rows whose line carries a `reason:`
  or `landed-by-hand:` show none: 16 of this run's 27 landed rows at the reading (auditor I6).
- A test-runner dispatch that names no model journals an empty `model=`, because the role file's default is not read
  into the roster, and Step 0's `test-runner=haiku-high` is unpinned (auditor I8).
- Blockers is not pinned for `finding:` and `gate:` items; a renderer that dropped them would stay green (auditor I9).
- The decisions register reads `ruled`, `re-ruled` and `withdrawn` only, so this run's D30 amendments and every D31
  line are missing from `decisions` and from the resume recap (auditor I10).
- `landing-report` reads `hand=0` though fourteen rows landed by hand, and T7, T19, T20 and T21 read as `git` landings
  (auditor I14).
- The tolerance marks' colours are the emoji font's and cannot be tinted on the page (D31).
- Seven new debt lines are on the ledger (`debt.md`), and the advisories' named sites in session-poker.sh, card.sh and
  the changelog readers were not burned (`A-orch-72`, `A-orch-76`, `A-orch-79`).

## 1.20.0 — 2026-10-15

This is the landing pace release: the serial landing loop is replaced by a drain that proves a row's suites side by
side, at most J at a time, J the floor's own width rule on spare capacity (D3). The six places where a
reader told the machine something false are fixed once, each at the layer it lives in: what a suite reads (D4), what
a floor proof cites (D7), whose words count (D9), what a row owes (D10), which fields a roster carries (D11) and which
directory a plan owns (D12). The refusal that hid its basis now prints it (D8). Two idle-slot defects the wave found
in its own run, a decline that held a free slot and a landing wait that held a writer's turn, were ruled into the wave
at Step 4 (D13). Verdict sharing across landings was measured and withdrawn (D5), and no suite was split (D6). Eleven
build rows landed. The floor, the wave's whole regression run, ran at b775aaa4 (100 of 100 suites green,
`floor-run-b775aaa46a6c8e15f342e84f7757aad73046d650.log` in the wave's record) and owes nothing. The landing target
was missed by every landing, and the numbers are below. This is a minor release by the policy above: the drain, the
`cover` verb, the `ev=run` line and the new `landing-report --rows` fields are new capability.
`canonical_sdlc_version` stays 14.

**Migration.** No artifact needs migrating and no setup step changes. Four rows added or widened a refusal that a
script of yours may have met. T3: a brief's `Lands-on:` that was complete at 1.19.0 can now be refused by the
dispatch wall, which prints the missing suites and the whole line to paste, because the reads index names more suites
per file (a library row averages 46.2 suites, up from 25.9). T4: `proof-add floor` refuses a floor log that no
`ev=run` line in the plan's landing record names, and a log whose hash, head or exit moved since its run; run
`floor-run` (or the detached runner) again and cite the log it writes, and a log written by hand has no path to a
proof. T5: `finding-move`, `waive-row` and `rule --words` read the words of a recorded session only when this project
witnesses it, a transcript under this project's encoded directory and a `loaded-<sid>.state` under this root, and the
refusal names the session and the missing witness. T6: `task-set files=` refuses a Files value that leaves a record
row with no artifact, naming `artifact=<path>` as the remedy.

### The drain (D3)

- T1 (`T1-landing-drain.md`): a landing runs at most J suites at once, each runner filing its own `landing` ask, with
  one landing tree per candidate and the red judge's head run in the next tree, and every verdict line carries
  `width=<J>` after `log=`.
- T9 (`T9-report-split.md`): `landing-report --rows` prints `wait=`, `prove=`, `line=` and `width=` for each row, read
  from the landing record alone.

### The map is complete and keeps its reach (D4)

- T3 (`T3-map-rules.md`): a prelude or test library a suite sources is scanned as the suite's own text, and a line
  that walks a directory reads every tracked file under it; `brief` and the dispatch wall read one `reads_suites`.

### Verdict sharing is not built (D5)

- REQ-2 is withdrawn on the measurement (29 of 633 wave-36 verdicts shareable, each a stale-green risk); the direction
  is kept in `design-ledger.md` and nothing ships.

### No suite is split (D6)

- AC-1.4: the floor ran with per-suite timing, `record/wave-37-landing-pace/timing.tsv` holds the 100 durations, and
  no suite was split because the longest, close-out at 963 s, is under the 30-minute target on its own; the five
  longest are close-out (963 s), rc-item (909 s), cross-gate-agreement (854 s), dispatch-preflight-4 (838 s) and
  worktree (836 s).

### The landing record holds the run (D7, ADR-057)

ADR-057 is Accepted.

- T4 (`T4-run-line.md`): `floor-run` and the detached runner write `line/v1|ev=run|log=|head=|dirty=|rc=|sha256=|at=`
  to the landing record, `proof-add floor` cites a log only with a run line that matches it on head, exit and hash,
  and the proof line ends with the run it read.

### The refusal prints the basis (D8)

- T8 (`T8-basis-line.md`): each `uncovered` line `current 7` refuses with ends in `ask: session-poker.sh cover <q>
  <a>..<b>` and prints that range's `cover <sha> <basis>` lines, and the new read-only `cover` verb prints the same.

### The project witnesses a session (D9, ADR-058)

ADR-058 is Accepted.

- T5 (`T5-words-witness.md`): a session's typed words count only when its transcript lies under this project's encoded
  directory and its load record exists under this root; `project_slug` is the one encoder, and the start hook records
  the start directory as `cwd=` in the load record.

### The row's own record is its artifact (D10)

- T6 (`T6-brief-artifact.md`): `brief` and `task-set files=` read one rule, the `artifact` cell, else the Files entry
  named `<row>.md` or `<row>-*`, else the first record entry, and the plan template header gains the optional
  `suites`, `lands-on` and `artifact` columns.

### List fields are a set, named once (D11)

- T7 (`T7-list-fields.md`): `ROSTER_LIST_FIELDS` names the six list fields once, both `clean()` copies test
  membership in it, `adopt` carries `questions=` and `claims=` byte for byte, and a census arm is red on a
  `roster_row` key that is in neither the list set nor the scalar set.

### One plan slug (D12)

- T2 (`T2-dry-copy-slug.md`): `proof_plan_slug` is the one slug reader and maps a plan verb's dry copy to its origin
  under `proof_debt_origin`'s three-part guard, so `current 6` sees a finding moved to fixed on the copy.

### The two idle-slot defects (D13)

- T18 (`T18-decline-reopens.md`): a standing fill decline answers its rows only while the gate reads `room=no` or no
  writer slot is free, and with room and a slot the tick records it `lapsed` and offers the rows again.
- T19 (`T19-bounded-ready.md`): the dispatch doctrine and the brief scaffold say a writer lands by `ready --within
  <seconds>` in the foreground, and `WAITING` keeps its place; the rule lives once, and the doctrine set is 29 bytes under the base.

### The landing numbers

`landing-report --rows` at the wave's head (every landing the wave made, ready to landed, as the landing record has it).
Rows T1 and T3 to T8 are the serial rows, landed under the old loop; T19, T2, T9 and T18 are the drain rows. A row's
`waited=` is the gate's total over every ask of its runs, so it can exceed the row's own minutes:

```
landings: queue=11 hand=0 git=0 · ready-to-landed median=206.3m p75=262.8m max=490.6m · runs: green=672 red=2 none=0 discarded=25 red-then-green=0 run=35 · waited median=12s · killed=26
T6 queue ready=2026-10-15T05:28:15Z landed=2026-10-15T08:54:34Z minutes=206.3 runs=46 waited=3329s wait=0.0 prove=206.0 line=0.3 width=-
T3 queue ready=2026-10-15T05:32:46Z landed=2026-10-15T09:02:27Z minutes=209.7 runs=50 waited=3543s wait=0.0 prove=209.4 line=0.2 width=-
T7 queue ready=2026-10-15T06:01:34Z landed=2026-10-15T09:25:16Z minutes=203.7 runs=57 waited=3231s wait=0.0 prove=203.4 line=0.3 width=-
T4 queue ready=2026-10-15T07:58:00Z landed=2026-10-15T12:39:00Z minutes=281.0 runs=78 waited=44s wait=73.3 prove=207.5 line=0.2 width=-
T5 queue ready=2026-10-15T06:50:58Z landed=2026-10-15T12:39:13Z minutes=348.2 runs=86 waited=1784s wait=0.0 prove=345.7 line=2.5 width=-
T8 queue ready=2026-10-15T12:26:55Z landed=2026-10-15T14:46:13Z minutes=139.3 runs=51 waited=197s wait=12.3 prove=126.7 line=0.3 width=-
T1 queue ready=2026-10-15T06:56:00Z landed=2026-10-15T15:06:33Z minutes=490.6 runs=75 waited=306s wait=135.3 prove=355.0 line=0.3 width=-
T19 queue ready=2026-10-15T14:04:17Z landed=2026-10-15T15:31:13Z minutes=86.9 runs=23 waited=439s wait=0.0 prove=86.6 line=0.3 width=7
T2 queue ready=2026-10-15T15:55:49Z landed=2026-10-15T18:27:43Z minutes=151.9 runs=71 waited=44947s wait=0.0 prove=151.4 line=0.5 width=7
T9 queue ready=2026-10-15T16:04:56Z landed=2026-10-15T19:04:45Z minutes=179.8 runs=99 waited=49429s wait=0.0 prove=179.6 line=0.2 width=7
T18 queue ready=2026-10-15T16:09:05Z landed=2026-10-15T20:13:35Z minutes=244.5 runs=63 waited=9266s wait=10.6 prove=233.7 line=0.2 width=7
```

| | wave 36 | wave 37 |
|---|---|---|
| ready-to-landed median | 29.4 m | 206.3 m |
| p75 | 107.4 m | 262.8 m |
| max | 170.8 m | 490.6 m (T1, serial) |
| the floor's wall time | 2206 s at width 7 | 2183 s at width 7 |

The wave's landings were slower than wave 36's, not faster: the serial rows have a median of 209.7 minutes and the
drain rows 165.9 minutes, and every landing missed AC-1.2's 30-minute target. The widest landing, T2 (71 suites), took
151.9 minutes at width 7 (wait 0.0, prove 151.4, line 0.5); the longest drain landing, T18, took 244.5 (wait 10.6,
prove 233.7, line 0.2), and the longest landing of the wave was T1's, the last serial one, at 490.6 (wait 135.3, prove
355.0, line 0.3). The target is a tune number, not a gate; the miss and its causes are the first Known limits below
(`A-orch-28` in `assumptions.md`). The floor's whole run took 2183 seconds for 14816 seconds of suite work, against
2206 seconds for 14959 at wave 36's floor, so the same suites finish in the same wall time at the same width.

### Standing reds

None. The floor is 100 of 100 and no row is born of it.

### Known limits

- Every landing of this wave missed AC-1.2's 30-minute target. T2, the widest, took 151.9 minutes at width 7 under
  three-way contention among the drains of T2, T9 and T18, and T18 alone proved 59 suites in 48 minutes once the
  others had drained (`A-orch-28`, `A-orch-21`).
- The drain's J is the share's width, not the machine's spare capacity, so three drains at once saturate the gate by
  design (`critic-adversarial.md#5`).
- `landing-report`'s wait and prove split books the gate's queue time inside `prove=`, so a starved row reads as slow
  proving (auditor AC-1.3, `critic-adversarial.md#4`).
- A review row's `suites` cell renders only on a plan whose Tasks header carries the `suites` column, so a plan
  written before 1.20.0 has no cell to render it from (auditor AC-7.3, `A-orch-29`).
- The slug reader's dry-copy arm has no caller in production code, only in the fixtures that plant one (auditor AC-9.2,
  `critic-adversarial.md#10`).
- A library sourced only by another library is still unmapped: `line.sh` sources `worktree.sh`, `slots.sh` and
  `suite.sh`, and the reads index does not follow that second hop (`A-orch-10`). The floor stays the catch-all.
- `run.sh` reaches all 100 suites, because `tests/lib/assert.sh` and `tests/lib/resolve-roots.sh` spell a bare `run.sh`
  in case patterns and the first rule reads a bare name as every file of that basename (`A-orch-10`).
- A regression run outside `floor-run` and the detached runner, and so outside the landing record, has no path to a
  floor proof (D7, ADR-057).
- Verdict sharing across landings is withdrawn and not built (D5; `design-ledger.md`).
- The doctrine pick leaves three options unbuilt: no width ceiling, no finer map (the fan-out stays: every hook
  sources every wanted library at load), and no out-of-order publish, so the first landing in line publishes first.
- The stop wall reads a lapsed decline one tick late: it reads the lapse line the tick wrote, so between room
  appearing and the next tick it still treats the decline as standing (`A-orch-19`, `T18-decline-reopens.md`).
- A bounded `ready` that returns `WAITING` asks the gate again on re-entry and is the youngest in its turn order, so
  it can starve behind an older drain, and a killed waiter re-enters the line youngest; the ask of a dead carrier
  stays in the gate's store (`A-orch-23`, `A-orch-21`).


## 1.19.0 — 2026-10-14

This is the zero machine errors release: the 1.18.0 run's census of 32 open machine errors
(`record/wave-35-no-workarounds/machine-census.md`) is worked down to eight root causes, D7 to D14, and each is fixed
once, at the layer it lives in. Every fix has one shape: a fact that had several readers with several answers, or
none, now has one owner that every consumer asks. Where a command runs, what a suite reads, which sessions a run has
had, what a branch's head is, what governs a session, whether a review still covers, and how a gate request ends are
each one reader now. The ledger verbs read the branch and lose nothing, the 1.18.0 release text is corrected below,
and the run ran on its own branch from Step 4 on. Thirty-six build rows landed. The census rows no row touched are
debt-class and are carried in the wave's continuation, not here. The walk and the reviews of the settled whole found
four more fixes (T42, T43, T44 and T47), and they landed. This is a minor release by the policy above: the placement
reader, the reads index, the judge's cover rule and the new verbs are new capability. `canonical_sdlc_version` stays
14. This run's whole run, the floor, ran at d81d2c91 (99 of 100 suites green,
`floor-run-d81d2c91673c649c4190c53e364778e38f26e1f0.log` in the wave's record) and owed one suite; the row born of it
is named under the standing reds below.

**Migration.** A person who runs bionic's own checkout runs `/bionic:setup` once, to take the new shell function (T1);
everyone else needs nothing. Eleven rows added or changed a refusal that a script of yours may have met, and the
behaviours around them changed too.

- T1: the `claude()` line setup writes adds `--plugin-dir <checkout>/payload` when the working directory is inside a
  git checkout whose `plugin.json` names bionic, and nothing elsewhere. `doctor` reads the 1.18.0 two-line body as
  stale and says so. `version` and `doctor` print `(in place) · <commit> · <root>` for a session that runs a checkout
  (`T1-run-on-branch.md`).
- T4 and T25: a commit whose directory the shell cannot place is refused, naming the segment as typed, and is never
  judged against the run's plan. That is a `cd` through an unpinned variable, in a subshell or under an `if`. A commit
  placed outside the project root and outside every tree the roster knows is exempt, so a read-only agent commits in
  its scratch repository. The "two directories" refusal is gone (`T4-jurisdiction.md`, `T25-callers.md`).
- T7 and T31: the judge reads cover from what a commit changed. A whole reading no longer covers whatever its head
  names, a commit that touches `tests/run.sh` or `tests/lib/` is code, and a review-born fix row covers only the
  question whose reading bore it. A question can read `uncovered` where 1.18.0 read it covered (`T7-cover-judge.md`,
  `T31-fix-seen-by-asker.md`).
- T8: `task-add --born` refuses a finding whose newest move is `defer`, quoting the move; a later move to fix lifts
  it. `finding-move <record>#<n> fixed <row>` refuses a row the plan's Tasks table does not carry
  (`T8-fixed-move.md`).
- T13: `debt add` reads any record with grammar-true `debt:` lines and no longer needs a `reviewed:` line. It refuses
  a line that does not parse and writes nothing. Any `debt` verb that names no plan, in a session bound to none,
  refuses and names `bind`. close-out `run` refuses a `debt.md` line that fails the grammar before its first act,
  naming the line. `debt adopt` and the Step-1 card now refuse a carried `debt:` line with a prose site or an unlisted
  kind, which 1.18.0 accepted, and `debt adopt` then adopts none of the continuation; the refusal names the line, and
  the remedy is the T13 grammar, one concept, one kind and one `<path>:<line>` site per line (`T13-debt-grammar.md`).
- T14: close-out lands the plan's open integrate and close rows itself, and refuses before its first act when it has
  such rows to land and no session is bound to the plan. `task-set --reason '<why>'` is accepted on a delivered plan
  and refuses a reason that carries `|`, a tab or a line break (`T14-close-out-state.md`).
- T27: the dispatch wall refuses a `Lands-on:` that omits a suite the reads index names for the brief's Files, and
  `none <reason>` for such a row. It prints the missing suites and the whole line to paste (`T27-consumers.md`).
- T32: the stop wall refuses with one line that names every ready row while a writer slot is free; one decline answers
  all of them. Before this it named only as many rows as there were free slots (`T32-one-width-fact.md`).
- T35: `floor-attestation:` is removed, and `proof-add floor` and `floor-run` refuse a config that carries it; delete
  the line and cite the regression's log. A floor log is read in one grammar: its first line is `head=<40-hex>
  dirty=0` and its last line is `rc=<n>`. A log with no closing `rc=` line is refused. `floor-run`'s own log moved to
  that shape, so one written by 1.18.0 does not pass: run `floor-run` again. `proof-add floor` takes several logs of
  one head (`T35-floor-is-a-fact.md`).
- T42: `task-add --born floor:<suite>` is refused unless the newest floor proof owes that suite or the landing record
  holds an `ev=standing` event for it at a commit on the working branch; the refusal names both facts
  (`T42-born-floor-backed.md`).
- T9 and T11: `rule` and `finding-move` read the user's words across every session the plan records, and name the
  sessions they read when they refuse. `stop-run` takes a gate request id or a holder's name as well as a detached run
  (`T9-run-sessions.md`, `T11-gate-lifecycle.md`).

### A session in a checkout runs the checkout (D7, ADR-055)

The tool that governs a bionic run and the tool the run is building are one thing. ADR-055 is Accepted.

- T1 (`T1-run-on-branch.md`): the session-start hook writes `.bionic/tmp/loaded-<sid>.state` (the loaded root, its
  commit, the start time and one sha256 per hook, skill, agent and command file), and the verdict `version` and
  `doctor` print reads a live session's record before the registry.
- T30 (`T30-start-hook-bash5.md`): the hook indexed an unset array under `set -u`, which bash 4 and 5 refuse, so no
  load record was written. Found by T2 mid-build; the array is initialised.
- T2 (`T2-restart-truth.md`): "restart needed" is a content fact. `doctor` re-hashes the recorded set in the recorded
  root and names each class whose hash moved, and prints nothing for an mtime-only change. close-out writes one
  `governed-by: <root> <commit> from <ISO>` line per root to the card and the continuation.

### The gate ends what it cannot resume (D8)

- T11 (`T11-gate-lifecycle.md`): a never-admitted request whose holder is dead is ended (`rc=gone`) and the ask gets a
  fresh one. `stop-run` ends a request, terminates the holder's process group and writes `ev=stop-run` to the landing
  record, and the hand-hold count shows it under its own kind. This ends the 1.18.0 Known limit that the gate resumed
  such a request under its old kind.
- T34 (`T34-taking-lock-stale.md`): a claim in progress is stale in five seconds. The gate's steal made its token
  inside the lock, which reset the lock's age, so it never stole a lock with no pid at any age.

### The judge holds one cover rule (D9, ADR-056)

ADR-056 is Accepted, and it amends ADR-054's cover term.

- T7 (`T7-cover-judge.md`): every reading is covered to its head, and a later commit extends it when every path it
  touched is prose or it is the landing of a row born of a reading or of the floor. Each commit the judge reads prints
  `cover <sha> prose|born-review|born-floor|owes`.
- T31 (`T31-fix-seen-by-asker.md`): a review-born landing holds only on the chain of the question whose reading bore
  the row.
- T28 (`T28-verbs-ask-the-judge.md`): `proof-add review` loses the build-rows hold and registers at the reading's
  head. A review row is ready again only when the judge reads a question `uncovered`. `task-add --born floor:<suite>`
  writes the marker.
- T40 (`T40-tick-asks-once.md`): one tick walked the commits three times; it asks the judge once.
- T42 (`T42-born-floor-backed.md`): the marker names its red. Six rows of this run (T33, T36, T37, T38, T39 and T40)
  carry `born: floor`, and no floor proof stood in the plan when they were added. They stand as landed, and the verb
  refuses an unbacked marker from now on.

### The run records its sessions, and verbs read the run (D10)

- T9 (`T9-run-sessions.md`): binding appends `- session: <sid> bound <ISO> by <act>` to the plan, and the user's words
  are read across every recorded session.
- T29 (`T29-launch-arm-and-adopt.md`): the commit gate's launch arm reads every roster whose `plan=` is this plan and
  the Dispatch ledger, and `adopt` carries active reader rows as it carries writer rows.
- T10 (`T10-closure-and-markers.md`): a task line keeps every ` <key>: ` marker when its text is rewritten, and one
  closure rule serves the dispatch hold and `adopt`; a dead session's row whose files are sweepable is closed and the
  hold's remedy names `sweep`.
- T47 (`T47-adopt-lands-on-whole.md`): `adopt` cut every adopted row's `lands_on=` at 400 characters, so a long
  landing set was lost. It keeps the whole set.

### One placement reader (D11)

- T3 (`T3-placement.md`): `cmd_place` reads where a command runs from the parsed segments, in one pass, so its cost is
  the segment count and never the text's length.
- T4 (`T4-jurisdiction.md`): the evidence gate asks it before the role arm, and `engage.sh --root <dir>` engages that
  root.
- T25 (`T25-callers.md`): the shim's stamp, the gate's tree and the evidence gate's commit reader are its callers; the
  raw-text clauses are deleted.
- T43 (`T43-two-cd-chain.md`): the walk found `cd A && cd B && git commit` placed at B by one caller and as moving by
  the other. Both place it alike.

### One file-to-suite fact (D12)

- T5 (`T5-reads-index.md`): `anchors.sh reads_index` prints the suites that read each file, from the suites' own text.
- T27 (`T27-consumers.md`): `brief`, the dispatch wall's Lands-on arm and the cover rule read it.
- T6 (`T6-pinned-text.md`): `refuse` §INV keys a refusal site by `file:function`, so a reworded line stays green and a
  moved call goes red.

### Ledger verbs tell the truth and read the branch (D13)

- T12 (`T12-branch-reads.md`): a failed launch sync leaves a log and the tick prints it once. `proof-add`, `waive` and
  `deliver` read the branch's ref, which ends the 1.18.0 Known limit that they read a checkout's head. One plan-line
  reader serves the judge and the wall.
- T13 (`T13-debt-grammar.md`) and T14 (`T14-close-out-state.md`): one debt-line grammar; close-out lands the rows its
  merge lands, merges a line into a fenced section, and clears the engaged marker last.
- T24 (`T24-block-heading.md`): one AC-block heading matcher, so a block `matrix-render` wrote is found by the verbs.
- T32 (`T32-one-width-fact.md`), T41 (`T41-task-set-files.md`) and T44 (`T44-walk-pointer.md`): the stop wall's
  refusal names every ready row once; a pending row's Files cell is corrected by `task-set`; the walk pointer has one
  writer.
- T35 (`T35-floor-is-a-fact.md`): the floor is the log of a run, in one grammar, and no person's word.

### Standing reds the landings found

Each landing ran its own suites, so the reds it caused in suites outside them were found by the next landing. Each is
repaired at its site: T33 (`T33-said-no-pipe.md`), T36 (`T36-stop-wall-pins.md`), T37 (`T37-shell-lint-reds.md`), T38
(`T38-one-roster-reader.md`) and T39 (`T39-sp2-pins.md`). The reads index (D12) is what now routes a later row to the
suites that read its files.

The run's whole run owed one suite, `session-start.test.sh`. Its §16.4 failed under load in the whole run and passed
alone at the same head: the suite's own `has` and `hasnt` helpers pipe a 61 KB report into `grep -q` under `set -o
pipefail`, the shape T33 repaired in `said.sh`. T48 (`T48-stamps-under-load.md`) is the row born of it, marked `born:
floor`, and a later green of that suite by a landing closes the floor.

### The doctrine and this release (D14)

T15 (`T15-doctrine.md`): the three loaded sentences that still stated the old floor rule state ADR-054's. ADR-055 and
ADR-056 are Accepted, and ADR-054 is amended by ADR-056.

### Corrections to 1.18.0

The 1.18.0 block above is untouched; release-check §ENTRY-1.18.0 holds its checksum. Four things in it were wrong or
silent, and this section states them.

- **Two refusals 1.18.0 introduced and its Migration list omitted.** From Step 7 the commit wall refuses a plan that
  claims a regression and carries no floor proof line (T31 of that run, `T31-verify-gate.md`), and `floor-run` refuses
  a dirty checkout before it runs, naming the first five paths (T32 of that run, `T32-floor-run-dirty.md`). The part
  headed "Fixes the review ordered" describes them, but a script's author reads Migration, and its Migration said
  "None is required". The same row also dropped Step 5's demand for the floor keys, which Migration did not list
  either.
- **The text-only floor arm.** The Step 7 refusal above reads text only (A-orch-50): it sees that a floor line is
  absent, never whether that floor is covered, owed or uncovered. That is by design, since ADR-054 puts the verdict
  with the judge and the commit wall reads no git (`T12-branch-reads.md`, section C27). It is stated under Known
  limits.
- **D22's two deferred sentences.** The 1.18.0 run deferred six findings and its Known limits carried four of them.
  The other two are stated below, and both are closed in this release, by T8 and by T10.
- **The count of fixes.** "The four fixes the review ordered" and the part headed "Fixes the review ordered" count
  T34. The review ordered three fixes, T31, T32 and T33. T34 was raised by the orchestrator (A-orch-48), not by the
  review (wave-35 `critic-adversarial-3.md` finding 6). The three omitted limits bring 1.18.0's twelve to fifteen.

### Known limits

Carried to the next release, with the limits 1.18.0 left out. The count of Known limits in this block is 9. The first
seven are carried and the last two are closed in this release.

- Known limit: The judge prints each commit cover basis only through facts_cover, which no verb, wall, tick or card
  calls yet; the basis is read in tests and by hand. (`critic-adversarial.md#2`)
- Known limit: The reads index misses a suite that reads a library by glob or through the test prelude, so a pin in
  such a suite can still go red at a later landing rather than at the row that caused it. (`critic-adversarial.md#3`)
- Known limit: A row touching a widely read library lands on 44 to 71 of the suites, and a landing can take two hours
  on an 8-core machine; no width ceiling exists yet. (`critic-adversarial.md#4`)
- Known limit: The words that authorize a finding move are read from the transcripts of every session the plan
  records, in any project directory, not only this one. (`critic-adversarial.md#5`)
- Known limit: The floor proof accepts any log whose first head= line and last rc=0 line fit the grammar, including
  one no runner wrote; the grammar is the one the synth-vision filing asked for. (`critic-adversarial.md#6`)
- Known limit: The brief verb takes the first record path on a row Files line as its Expected artifact, so a row
  naming another record first needs that line corrected by hand. (`critic-adversarial.md#7`)
- Known limit: from Step 7 the commit wall refuses a plan that claims a regression and carries no `proved: kind=floor`
  line, and it reads text only, so a floor line that owes suites passes it and the judge holds them at `current 7` and
  `current 8`. (A-orch-50, `T12-branch-reads.md`)
- Known limit, closed by T8: `task-add --born` still admits a finding the person moved to defer when its reader's
  rating is inside the fix policy; the guard reads a move to fix, not a move to defer. (omitted from 1.18.0; wave-35
  `critic-adversarial-3.md#1`)
- Known limit, closed by T10: a dead session's open row whose files are already sweepable still holds its plan row,
  and the refusal's remedy (`adopt`) lists nothing for that session; `session-poker.sh sweep` clears it. (omitted from
  1.18.0; wave-35 `critic-adversarial-3.md#2`)

The twelve Known limits of 1.18.0 are carried as they stood and were not re-triaged here, except three this release
ends: `proof-add`, `waive` and `deliver` read a checkout's head (T12), the gate resumed a dead holder's request under
its old kind (T11), and the cover rule read every path under `tests/` as non-code, which now holds for every path but
`tests/run.sh` and `tests/lib/` (T7).

## 1.18.0 — 2026-10-12

A wave now owes one whole run of the tests, after its review, and the machine counts what changed since that
run instead of asking for a second one. The background pass built in 1.17.0 is removed, because it sat on the
critical path at a fixed width of 2 and took 22% of the wall on its own, and 28% with the red fix it caused.
The solo, quiet and VOID machinery is gone and the timed cases that had no deterministic form are deleted;
27 cases the clock census names still gate on the clock and are deferred, each with the change that retires it.
Twenty-four rows landed: the twelve walls and plan-machinery faults of the 1.17.0 run's catalogue, the anchors
every mutation test stands on, the hand-hold count, the step doctrine, the decision brief, the two-writers
fault the run found in its own tick (a fill that offered a row another session held, and a launch sync that
aborted on an empty ledger), and the four fixes the review ordered. This is a minor release by the policy
above: the floor judge, the anchor index and the new verbs are new capability.
`canonical_sdlc_version` stays 14. This run's own floor is Step 6's last act and is recorded in the wave's
record, not here, because the release text is written before it.

**Migration.** None is required. Nine behaviours changed that a script of yours may have leaned on.

- The pass is gone. `ready` prints no `pass:` line and starts nothing. `spawn-worktree.sh pass`, the gate's
  `pass` request kind (`gate_ask pass` exits 2), `booked.sh --no-follow` and the tick's `ev=pass` read are
  deleted. A `background-pass:` line left in `.bionic/config.yaml` is read by nothing (`T1-pass-removed.md`).
- Nothing waits for a quiet machine. The `# runner: solo` marker is not read, `tests/run.sh` prints no `Void:`
  line and never re-runs a red suite, and `booked.sh --quiet` exits 2 as usage. `BIONIC_QUIET` is read by
  nothing, so a script that sets it is ignored and gets no exit 2 (`T2-no-solo-void.md`).
- A red whole run is a floor candidate. The judge accepts it, lists each red suite as owed, and closes a suite
  on one later green run of it by a landing. `session-poker.sh proof-add inherited <suite>` records a red that
  is red at the base commit too (`T9-floor-judge.md`).
- `current 7` runs the judge `current 8` runs, at the head the working branch's ref names, and refuses in its
  words. `floor-run` in a project with no `floor:` runs `tests/run.sh` whole (`T10-step-verb.md`).
- `approval:release` is read by the integrate row of a plan that carries a release row, and the Step-7 doc row
  is ready at `approval:plan, head`. `approve release` records it there (`T5-row-reads.md`).
- The commit wall's jurisdiction ends at the engaged repository. An outside commit preceded by `ln`, `mkdir`,
  `cp`, `mv`, `rm`, `touch`, `printf` or `echo` is exempt. An outside commit the wall cannot place is refused
  with the split named, and is never judged against the run's plan (`T4-wall-jurisdiction.md`).
- A run the wall cannot place leaves no stamp. After a `cd`, `pushd` or `popd` it could not follow, the shim
  prints `not counted` and proves nothing. A suite's key in every record is its file name (`T6-placed-stamp.md`).
- Three verbs and a section are new: `session-poker.sh anchors check` and `anchors index`, `decline lift`, and
  `landing-report --hand-holds`. A mutation test declares its anchor with the `anchor file`, `anchor fn` or
  `anchor insert` shape, and `ready` refuses a landing whose anchor has moved (`T3-anchors.md`, `T8-plan-machinery.md`,
  `T12-hand-holds.md`).
- No row that another session's roster holds open is offered or launched. The tick's fill leaves out a row open
  on any roster under `.bionic/tmp`, this session's included, and prints `poker: WAIT <row> — <writer> open on
  roster <session>`. A dispatch of a writer onto such a row is refused, naming the writer and its session; before
  this it was admitted, including under the same name (`T28-fill-reads-rosters.md`).

### The catalogue of twelve

Each row is a fault of the 1.17.0 run, the fix, and the record that proves it. The "also" rows are the three
loose ends the charter listed beside the twelve.

| item | what refused or misled | the fix | record |
|---|---|---|---|
| 1 | `approval:release` sat on the doc row, so the release text gated the reviews | the integrate row reads it, the doc row is ready at `approval:plan, head`, and the validator's refusal and `task-add`'s retry are deleted; units §RELEASE-READ was 7 red and is green | `T5-row-reads.md` |
| 2 | the facts judge read the checkout's branch, so after the merge it read the floor as uncovered at an empty range | every head is read from the branch's ref by one function; a deleted branch is refused as naming no commit; close-out takes the same reader | `T7-one-branch-reader.md`, `T10-step-verb.md` |
| 3 | a whole run by a test-runner needed `Suites: tests/run.sh`, and `floor-run` refused a project with no `floor:` | `floor-run` runs `tests/run.sh` whole and accepts its log red or green; the wall's full-tree refusal prints that line and the wall admits it as printed (dispatch-preflight-4 RM.3 to RM.5) | `T10-step-verb.md` |
| 4 | the commit wall judged a scratch repository's commit against the session's bound plan | the jurisdiction ends at the engaged repository; bash-walls-egd §JURIS holds 92 assertions | `T4-wall-jurisdiction.md` |
| 5 | `ready` labelled code drift `cause=environment`: a red writer-tree run was stamped clean at the main head, and a path-qualified suite did not meet the file-name key | a run the wall could not place leaves no stamp; one suite grammar and one key, the file name, in the cause and the floor judge; bash-walls §W10 and landing-line §CAUSE-TREE and §KEY | `T6-placed-stamp.md` |
| 6 | one scratch mutant script was admitted and the next refused | a script's every suite line is claimed, to depth 2, and the refusal names the command that ran the suite; bash-walls §SCRIPT-CLAIM 15 rows, cmd-class §SCRIPT 17 | `T4-wall-jurisdiction.md` |
| 7 | the tick's "unchanged" short-circuit skipped the backstop's re-check until `arm` | an unchanged tick prints every `NOT-LANDED` line above `unchanged since`; session-poker-4 §HOLD-RIDES | `T5-row-reads.md` |
| 8 | a reinstall did not refresh a running session's loaded skills, and nothing said so | `doctor` compares each live session's start with the newest hook, skill and agent file and names it, and every tick prints its own session's line; doctor-restart was 12 of 21 (its test 4 and §FILES) and is green | `T5-row-reads.md` |
| 9 | a read of a record path no row's Files names was silently met, and a hand-hold needed `decline --on` | the validator refuses such a read, naming the token and the writer row (units §RECORD-READ); `decline lift` ends a decline; hand-holds are counted from the verbs' lines | `T8-plan-machinery.md`, `T12-hand-holds.md` |
| 10 | `brief` derived `Suites: none` for a row whose Files name no test, and left a reader's artifact to be invented | `brief` reads the anchor index at the working head, else leaves the orchestrator's slot; a verify, test or review row gets `<record>/<row>.md` (session-poker-3 §BRIEF-SUITES) | `T8-plan-machinery.md` |
| 11 | `matrix-render` wrote the Approach as provenance, `current N` read like a malformed plan, the Step-2 card rendered an empty table in silence, a decline outlived its lifting | provenance and criterion text come from the requirements file; the refusal ends on one `poker: missing:` line; the card exits 64 on an untagged bullet or an ADR line with no `(D<n>)` group; `decline lift` | `T8-plan-machinery.md` |
| 12 | mutation anchors on source and comment text drifted silently, and three rows broke anchors in suites they never ran | one anchor helper, a checker (`MOVED`, `NONLITERAL`) that `ready` runs, and an index the floor judge and `brief` read; the index named 2 files and now names 42 after the legacy calls were converted | `T3-anchors.md`, `T23-legacy-anchors.md` |
| also-1 | two readers of the working branch | one reader, `plan_working_branch`, behind every surface; the `bound-row-read` and `row-writer-lookup` debt lines burned there | `T7-one-branch-reader.md` |
| also-2 | the re-mark's liveness check and plan-cell read | a dispatch that would re-mark a tree whose row still has a live writer is refused, naming the row, the writer and the tree (dispatch-preflight-4 RMK.9 to RMK.11) | `T7-one-branch-reader.md` |
| also-3 | two writers on one row report, unreproduced | reproduced with a real launch carrying an agent id: the fill read plan status alone, so a row open on another session's roster was offered. Fixed by T28 (the fill and the dispatch wall read every roster `adopt` reads) and T29 (launch-sync on an empty ledger, an abort under bash 5.x) | `two-writers.md`, `T28-fill-reads-rosters.md`, `T29-launch-sync-empty-ledger.md` |

The four fixes of the 1.16.0 field report's items 7 to 10 are rows 11 and 9 above: `matrix-render` (item 7),
the `current N` refusal (item 8), the Step-2 card (item 9) and `decline lift` (item 10), all in
`T8-plan-machinery.md`.

### The floor

The floor is one whole run plus the greens of what changed since it (ADR-054, `adr-054-the-floor-is-one-whole-run-plus-the-greens-of-what-changed.md`).

- One whole run at a commit F, green or red, is the candidate. Each suite red in it is owed.
- A later green run of an owed suite by a landing closes it. No second whole run is asked for a red a fix row
  covers.
- A fix row covers its change when every code file it touched is declared by a suite it ran, read from the anchor
  index. A file no ran suite declares owes a second whole run, or the user's `approve regression-2`. Each
  second whole run and each `regression-2` is counted in the hand-hold section.
- A commit that touches only non-code paths inherits the standing of its parent.
- A suite red at the head and at the base commit is inherited debt, recorded by `proof-add inherited`. A suite
  green at the base is a regression, and the verb refuses it as such.
- The floor is Step 6's last act. `current 7` demands it and refuses with the owed suite or the unproved commit
  named, and the release text no longer waits on it. Records: `T9-floor-judge.md`, `T10-step-verb.md`,
  `T13-doctrine.md`.

### The background pass is removed, and why

ADR-053, background work takes only spare capacity, is Superseded by ADR-054; ADR-054 is Accepted. The pass
was built to find reds earlier, and on its first run it found the floor no sooner. `T16-pass-measure.md` of
the 1.17.0 run measured it: both passes ran at width 2, fixed at their ask and never widened, each for about
62 minutes, against 33 to 34 minutes for a whole run at width 7. They began after the last code row, on the
critical path, and with the red fix they were 28% of a wall of about 573 minutes. Deleted: the `pass` request
kind, the per-branch lock, the detached start in `ready`, `spawn-worktree.sh pass`, the tick's read, the
`background-pass` switch and their tests (gate §PASS, landing-line §PASS, session-poker-4 §PASS, evidence-gate
§FLOOR). The ancestor pin the pass kept alive moved to evidence-gate-2 §ANCESTOR (`T1-pass-removed.md`). The
pass is recoverable from the v1.17.0 tag if a project with a long suite ever asks.

The 1.17.0 block is untouched. This entry corrects the 1.17.0 block's `background-pass` default line, "on unless
the config says off", which no longer holds: nothing reads the key. Six of its Known limits end with the
mechanism they described (the fixed width, the wait during a pass, memory under a pass, the pass told nothing,
VOID under a quota and the runner's behaviour under a pass). The rest are carried as they stood and were not
re-triaged here.

### Fewer cases pass or fail by the clock

The solo marker, the settle wait, VOID, the retry of a red suite and `--quiet` are deleted from the runner, the
booked shim, the gate's wrap and the resource reader (`T2-no-solo-void.md`; runner-width §NO-VOID and §NO-RETRY
were 17 red of 55). The suites that used them assert counts where they asserted seconds: hook-timeout,
bash-walls-egd and session-start (`T11-no-clock.md`). A census of 46 files lists 100 clock lines and 194 sleep
lines and names 27 deferred cases, each with its trigger and deterministic form (`clock-census.md`); shell-lint
§CLOCK holds every case file at or under its ledger.

Deleted because they had no deterministic form: hook-timeout a1, a2, b, c and g, the self-checks that timed one
`${v/…}`, `${v//…}` or awk operation against 2 s, and session-start 16.8 and 16.2, the advisory rows that
printed seconds. A count cannot see a single slow operation, and a clock is not evidence.

The converted rows found three walks in the shipped hooks that grew with their input in shell steps. All three
are fixed:

- `git-argv.sh` rebuilt an argument rest one word at a time. A 200 KB quote-dense command took 247 s, against
  the hook's 10 s registration, so the wall failed open. It now takes 20 s.
- The commit gate's later-`cd` scan walked every heredoc line. It now walks only the segments that can open a
  `cd` or end the scan, and its count is flat in the input.
- `session-start` forked once per predecessor roster, from a `$(printf '\t')` in a `while` condition.

One cost remains and is carried below.

### The decision brief and the doctrine

The decision skill's Altitude section opens on the act: reframe at a conceptual level in plain language, name the
one thing the options differ on as a contrast, cut detail before sentences, and only then write the four labels.
decision-skill §CLIMB pins it against five doctored copies. Three fresh headless sessions on the door-pool
scenario wrote briefs with no identifiers in the Goal or Options, and each Goal named live against stored; the
first rewrite failed that half of the live check and the second commit is the fix it found (`T24-brief-climbs.md`,
`T24-altitude-live.md`). The step doctrine now says Step 5 owes each row's evidence and Step 6 ends on the floor,
and the order of operations is pinned by render §DOCTRINE and §ORDER (`T13-doctrine.md`). The two standing reds
the first landings found, a refusal inventory missing two bullets and a close-out fixture line, are green
(`T25-standing-reds.md`).

### Fixes the review ordered

Findings of the whole-run reading were ruled fixed in this wave (D20, `critic-adversarial.md`). Each is a row, and
each row's record is named beside it.

- T31 (`T31-verify-gate.md`): the Verify gate no longer demands the floor keys at Step 5, because the judge at
  `current 7` does; from Step 7 the commit wall refuses a plan that claims a regression and carries no floor proof
  line; the doctrine row and the preflight refusal say the floor is demanded at Step 7; and the commit wall's
  jurisdiction `.git` check compares case-insensitively.
- T32 (`T32-floor-run-dirty.md`): `floor-run` refuses a dirty tree before it runs, naming the first five paths, so
  the first whole run is spent only on a clean tree; `help` lists `decline lift`, and the verb listing names
  `decline lift` and `proof-add inherited`.
- T33 (`T33-continuation-merge.md`): an existing `continuation.md` gains the inherited-debt lines and the hand-hold
  count, merged under their headings, never twice and never over the person's text.
- T34 (`T34-born-honors-move.md`): `task-add --born` admits a finding the person moved to fix, whatever its
  reader's rating, and refuses an unmoved finding outside the fix policy with the remedy, so the instruction the
  disposition verb prints for a moved finding is true.

### Known limits

Carried to the next release. The count of Known limits in this block is 12.

- Known limit: a suite whose worker dies by a signal makes `xargs` abandon the rest of the batch's launches.
  It was true of every non-solo suite before this release; the solo drain had hidden it for the one fixture that
  kills its worker, which now waits for its siblings (`T2-no-solo-void.md`).
- Known limit: the doctor's restart read costs 0.42 s on every tick, and its fix line is cut at 80 columns
  (`T5-row-reads.md`).
- Known limit: a quote-dense command of 200 KB still costs the bash wall 20 s under bash 3.2, past the hook's
  10 s registration, so it fails open. The cause is four reads of the whole command by one awk program, about
  3.3 s each, flat in input size, so no count row can see it. The fix reads the segments once per hook and is a
  design change for 1.19.0 (`T11-no-clock.md`). hook-timeout takes about 4.5 minutes.
- Known limit: close-out.test.sh line 2181 holds the same literal three-backtick print that line 2183 did, and
  is hidden from the refusal-inventory scan only because its pattern carries an unquoted `#`
  (`T25-standing-reds.md`).
- Known limit: the anchor index names only suites that declare a shaped anchor. Ten legacy calls remain: two in
  cross-gate-agreement whose text is the live version pin, and eight in framework that test the old helper.
  A fix row whose code file is in no index line owes a second whole run (`T23-legacy-anchors.md`).
- Known limit: `proof-add`, `waive` and `deliver` still read the head of a checkout, not the branch's ref. After
  the merge, with no checkout holding the branch, they refuse where the judge would answer. Ruled at D20 for
  the next wave (`T10-step-verb.md`, `critic-adversarial.md` finding 6).
- Known limit: `floor-run` starts the run in the working checkout, so an agent running it asks the gate as main
  unless that checkout carries a writer marker (`T10-step-verb.md`).
- Known limit: three orchestrator hand-holds of this run, the observed park of a solo suite, the parked shim processes the orchestrator ended and the ruling that deleted the solo marker (A-orch-9, A-orch-10 and A-orch-11 of this wave), are not in the hand-hold count, because the
  count is of lines the verbs wrote and no verb wrote them. They came from the installed 1.17.0 gate, which still
  read the solo marker this release deletes (`T12-hand-holds.md`).
- Known limit: a declared test runner for Jest and other suites in `Suites:` and `Lands-on:` (field report item 6)
  is not built. 1.19.0, unless the other project is waiting; any suite derivation built here keys on a declared
  suite, not a `.test.sh` suffix, so it widens without a rewrite.
- Known limit: `approve regression-2` waives the cover rule for the whole plan, with no bound on which commits or
  how many second whole runs it excuses. Ruled at D20 to carry (`critic-adversarial.md` finding 1).
- Known limit: the cover rule reads every path under `tests/` as non-code, so a change to the runner or the test
  framework is proved by its own row's suites alone and owes no second whole run. Ruled at D20 to carry
  (`critic-adversarial.md` finding 7).
- Known limit: the gate resumes a never-admitted request whose holder is dead under its old kind. Older than this
  release; ruled at D20 for the next wave (`critic-structure.md` finding 1).

## 1.17.0 — 2026-10-12

A landing now starts the full test pass itself, in the room the machine has spare, and the gate learns whose
suite a command is from the tree it starts in. Thirteen rows landed: the identity rule, one reader of busy,
the backstop that holds a ruling, every ask of the person owed and sent at least once, the three
field-report fixes for agents and for another project's layout, the background pass and the tick that reads
it, hot helpers that fork nothing, a shorter RC5 drive, and the decision skill at design altitude. The floor
was found by the pass itself: the first pass was red at 743a37c6, the second was green at c15a7e40 and
became the floor proof. Of the ten 1.16.0 Known limits the release was held to, seven are struck with a
record and three are carried with the sentence that says why. This is a minor release by the policy above:
the pass, the marker and the new verbs are new capability. `canonical_sdlc_version` stays 14.

**Migration.** None is required. Five behaviours changed that a script of yours may have leaned on, and one
field is named dead.

- A writer's tree carries its name. `spawn-worktree.sh create … --for <name>` writes
  `<git-dir>/bionic-agent`, and the gate reads it when no `BIONIC_GATE_AGENT` is set. A tree made by 1.16.0
  has none: a suite started in it asks as the main thread. `spawn-worktree.sh mark <tree> --for <name>`
  writes the marker of an existing linked tree and refuses the main checkout (`T2-identity-from-place.md`).
- No command is rewritten to carry a name. The 1.16.0 rewrite of a budgeted agent's script start, and of
  every command in bypass mode, to `export BIONIC_GATE_AGENT=<row>; <command>` is deleted; a command the
  claims do not read passes untouched in every mode (`T2-identity-from-place.md`).
- Each landing may start a background pass. It is on unless `.bionic/config.yaml` says `background-pass:
  off` or the plan says `regression: no`, and a project with neither a `floor:` command nor a `tests/run.sh`
  at the landed head gets none. With it off, a whole run holds the machine alone as at 1.16.0
  (`T9-pass.md`).
- `ruling-ack` is refused unless the caller is the ruling's own writer, alone in its call. The main thread
  and another writer are refused and the ruling stays unread (`T5-owed-asks.md`).
- `adopt` prints two new words, UNCONFIRMED and IDLE, and reads RUNNING only from evidence: a fresh answer
  that lists the agent as not idle, or transcript growth across two reads a cadence apart. LANDED needs the
  deliverable and the agent's report. The handoff prints `safe to exit:` and `safe to /clear:` lines
  (`T6-agents-true.md`).
- `impact-command:` in `.bionic/config.yaml` is dead. It has not been read since 1.14.1, which deleted the
  impact map; a project whose writers ran jest, or any runner that is not a `*.test.sh` file, still declares
  `Suites: none` with `Re-executes:` and `Lands-on: none`, and `ready` proves nothing for it. Accepting
  other suite files was asked for in the field report (item 6) and is not built here; this line only says
  the field is dead (`inbound/bionic-1.16.0-w1-feedback-20261011.md`).

What you will notice:

- **A suite started in a writer's tree asks as that writer, from any launcher, in every mode.** The gate
  reads the marker of the tree the ask is made in, and one `git rev-parse` per ask answers who asks, which
  project's roster applies and the request's tree. Both carries are deleted, with `_bsg_carry`,
  `_bsg_stage_carry` and `_bsg_bypass`. gate M.1 to M.9 were red on the unchanged code
  (`T2-red-gate-spawn.log`) and are green (`T2-green1.log`); bash-walls §CARRY-EVERY runs each row once per
  permission mode (`T2-red-walls.log`). The walk ran an off-budget suite from a marked tree through a
  foreign launcher and it was refused, exit 75, nothing run; the same suite from the main checkout ran
  (`T18-walk.md` section 1). Record: `T2-identity-from-place.md`.
- **One reader of busy.** Under a CPU quota the settle, the void check and the pressure ring now read the
  cgroup's own use, as the gate does; they read the host's load against the quota's cores. A cold ring waits
  one sample. Record: `T3-busy-one-reader.md`.
- **The backstop holds a ruling and pages once.** The tick's backstop reads a writer's rulings without
  marking them shown, lands nothing while one is unread, says `NOT-LANDED <row>` with the ids on every tick,
  and opens one owed item per ruling, closed where the ruling is read. At 1.16.0 `deliver`'s guard stamped
  the ruling shown when it refused, so the next tick landed over it. Record: `T4-backstop-pages.md`.
- **Every ask of the person is owed, and a notice is sent at least once.** The commit wall's question and
  matrix-row waiver refusals open `waive:` and `waive-row:` items; `waive-row` and `waive` close them and
  the question's `finding:` items; the texts of `owed.sh`, `notify.sh`, `card.sh`, `stop.sh` and
  `close-out.sh` say "at least once", because a send that times out late is sent again on the next Stop and
  the recipient may see it twice. `doctor.sh` names a topic in `cron.env` with no channel file: `nothing is
  sent`. Record: `T5-owed-asks.md`.
- **What bionic says about agents is true.** `adopt` judges liveness from evidence, the handoff says whether
  it is safe to exit or clear and reads live agents from the newest answer, and an ack or a human-ordered
  stop crosses sessions. Record: `T6-agents-true.md`.
- **The walls take another project's layout.** `ready` finds a `Lands-on:` suite under any directory of the
  landing tree, where it ran `tests/<name>` and stalled with exit 70, and the gate admits a suite run by
  path against the budget that recorded its file name. Record: `T7-another-layout.md`.
- **The gate admits a background pass into spare room.** A new request kind, `pass`, is asked once, ranked
  after all work, and skipped with no wait when the room under the share, less a reserve of 2 cores for a
  landing, is under 2 cores. A whole request that waits stops a pass that is running. Work and landings are
  admitted beside it. gate §PASS was red on the unchanged code, 25 rows (`T8-red-gate.log`), then green
  (`T8-green-gate.log`), with a hand whole run holding the machine alone as before (slots Q1, Q2;
  `T8-green-slots.log`). Record: `T8-pass-admission.md`.
- **A landing starts the pass, and the tick reads it.** After a landing `ready` prints `pass: started at
  <head> pid=<pid> log=<log>` and runs the project's regression at the landed head in a tree of its own, one
  pass per branch. A red pass is one tick note naming its suites and head and opens nothing for the person;
  a green pass writes the floor proof for that head, and a pass is the floor like a hand whole run. The
  second-run rule (`approve regression-2`) still governs a hand run. Record: `T9-pass.md`; measured in the
  passes below.
- **The hot helpers fork nothing.** `_wt_field`, `line_field` (three copies, now one body), `clean`,
  `parse_seconds`, `verdict_row`'s trim, `frontmatter_get`, `units_field`, `_eg_row_for_worktree`,
  `is_placeholder_value` and `_eg_body` do their text work in bash 3.2 builtins. A fuzz of old against new
  on both bashes and both locales found 0 differences in 46,024 cases; every helper has a mutant that an
  existing pin catches, and two pins were added where none did. `_git_argv_expand_at` was left. The profile
  that named them is `fork-profile.md` (T10). Records: `T11-fork-free.md`, `fork-profile.md`.
- **RC5's drive is shorter in the suite's own copy.** dispatch-preflight-4 §RECORDER shortens the deadline
  in the copy of the hook it already runs. The shipped constant is byte-identical. Record:
  `T12-rc5-copy.md`.
- **The decision skill frames at design altitude.** The heading is `**D<n> · Step <s>**`, numbered in one
  sequence; the Goal is one sentence; small decisions may share a turn and a momentous one goes alone; the
  skill names concepts, not mechanisms, and carries three worked pairs. The skill grew 4,221 to 9,352 bytes
  under a 10,000-byte cap, and the loaded doctrine ended 2 bytes smaller (`T1-decision-altitude.md`). Run
  live on the fixture of this wave's own D5, both sessions under the shipped skill wrote a Goal and Options
  with 0 backticks, paths, row and criterion names; the control under the old skill wrote 28 backticks, 3
  paths, 4 row names. The shipped skill's first worked pair is that same decision, so the held-out decision
  (one sample per arm) is the fairer reading: 0 against 18 backticks and 2 criterion names
  (`altitude-live.md`).
- **The evidence gaps are closed.** This run's own D1 to D3 are the live Step-1 interview under the decision
  skill (`interview-live.md`). Wave-33's AC-9.3 now names its static re-check, and no eval of either wave
  names a release-check section that does not exist. Wave-33's AC-2.3 is amended: the Patrol's non-GATE
  NOTIFY lines are the orchestrator's to act on and open no owed item (`T15-evidence-gaps.md`).
- **Two stale mutation anchors were re-anchored, and nothing else moved.** landing-line (r6em-pre) and
  (r6em) after T4 moved the launch-row read into `line_row_writer` (`T25-r6em-anchor.md`); runner-roster
  11.15, 11.18 and 11.19 and spawn-worktree (up3-pre) and (up3) after T9 and T4 re-spelled the lines they
  mutate (`T26-pass-reds.md`). The first pass found them one landing after they landed, which is what it
  is for.

- **The review's fixes.** A `Lands-on:` suite declared at a path is run at exactly that path, never a
  same-named `tests/<name>` (`T27-declared-path.md`; the critic's S2). A writer dispatched into a tree a row
  already recorded re-marks it for the new name, so it asks the gate as itself (`T28-remark.md`). A dispatch after a
  handoff was written marks the handoff itself stale: its safe-to-exit lines name the later dispatch
  (`T29-handoff-stale.md`).

### The floor, the passes and the walk

The floor is the background pass at c15a7e40: 92 gating suites passed and 0 failed in 3,728 s of wall at
width 2, with 7,333 s of work (`pass-c15a7e40de6c.log:112`), and the three suites a pass marks VOID
(bash-walls-egd, hook-timeout and session-start, which a pass runs unsettled) passed in one `--only` run, 3
of 3 (`T13-floor.md`, `T13-void-solo.log`). The first pass, at 743a37c6, failed 2 of 92: runner-roster and
spawn-worktree, both stale mutation anchors (`pass-743a37c6f56f.log:926`, `T26-pass-reds.md`).

**The passes, measured on this run** (`T16-pass-measure.md`). Both passes ran at width 2, fixed at their ask
and never widened, and each took about 62 minutes (3,726 s and 3,730 s). They sat on the critical path: each
began after the last code row, when nothing was left to run beside it, and with the red fix they were 28% of
a wall of about 573 minutes (the person's Steps 0 to 3, 33%; the build, 35%; the floor's read, 3%). Four
asks were made while a pass ran, all from the walk's scratch project, and the longest wait was 5 s. Live
load decided it, load of which the pass's own cores were part; the pass's promise did not. So "never makes a
writer or a landing wait" holds for the promise and misses by 5 s through live load; no writer of this run
asked during a pass. Memory at width 2 stayed at 43 to 46% of 8 GiB at the sampled moments, and widths 3 to
5 never ran. Landings took 149.5 minutes over 13 rows against wave-33's 226.4 over 27, and the gate wait was
13.0% of landing time against 20.7% (`T16-pass-measure.md`, addendum).

The walk drove the installed build on scratch projects: a marked tree and a foreign launcher, a ruling held
at the backstop, the owed ledger through a stubbed channel, and a landing that started a pass. Four of its
five steps passed (the third on the branch with no notification channel, where nothing could be delivered).
Step 4 was partial: both landings printed the pass line and started the pass detached, and the gate skipped
both for lack of room beside this repository's own pass, so no scratch pass ran and no tick read its result;
the tick's reading of a pass is shown on this run itself, which read the red pass and the green one
(`T18-walk.md`, `walk.md`).

### The tune numbers

Each tune row's measurement before and after, on this machine (8 cores), at load 1.4 to 1.8, the before side
being T10's code re-run beside the after code. T10's profile set each row's recoverable share as its target
(the tick 54%, the commit-path hook 37%, ready under 15%); the tick and the hook fell by less, and the
numbers are the record. A tune target never blocks a wave.

| measure | before | after | logs |
|---|---|---|---|
| wall hook on `git commit` (T11) | 0.79 s, 515 forks | 0.62 s (−22%), 289 forks | `T17-tune-after.md`, `fork-profile/after-c15a7e40/measure.log` |
| wall hook on `ls` (T11) | 0.08 s, 30 forks | 0.08 s, 30 forks | the same |
| Patrol tick (T11) | 3.11 s, 3,181 forks | 1.83 s (−41%), 1,104 forks | the same |
| `ready` on a fixture landing (T11) | 4.12 s, 437 forks | 4.07 s (−1%), 402 forks | `fork-profile/after-c15a7e40/measure-ready.log` |
| RC5's drive (T12) | 24 s | 11 s | `T12-red.log:962`, `T12-mutant.log:969` |
| dispatch-preflight-4, section-stamp span (T12) | 810 s at width 7 | 392 s at width 2 (−52%) | `wave-33-workhorse/regression-1aacdc03-progress.tsv`, `pass-c15a7e40/main-cmd-2.log.progress.tsv` |
| the whole run | 2,037 s wall, 13,019 s work, width 7 (1aacdc03) | 3,728 s wall, 7,333 s work, width 2 (c15a7e40) | `wave-33-workhorse/regression-1aacdc03.log:106`, `pass-c15a7e40de6c.log:112` |

The tick's own numbers, 5.03 s to 2.98 s, were T11's, taken at higher load (`T11-fork-free.md`); the table
carries the interleaved re-measure. The dispatch-preflight-4 drop is mostly width, not code: the 40 suites
that took 60 s or more before all fell to 0.46 to 0.89 of their span, with a median of 0.58, and
dispatch-preflight-4's 0.48 is at the low end of that band. Work fell 44% but the wall rose 83%, because the
only after-run is the pass at width 2; a width-7 after-wall does not exist, since the dispatch wall refuses
a hand run on a head the pass already proved. The 900 s target for a whole run is missed (limit 10 below).

### The assertion account

Expected values changed by ordered behaviour changes, each listed old to new in its record. No assertion was
deleted, loosened or skipped, and no timing bound was raised.

| record | what changed |
|---|---|
| `T1-decision-altitude.md` | decision-skill 6 ("one decision per interview turn") now pins the batching rule; 19's size cap 5,000 to 10,000 bytes; 26 follows the core's new sentence |
| `T2-identity-from-place.md` | the carry rows (bash-walls SB.2c, SB.2d, SB.3b, SB.5c, SB.10, CE.1c, CE.2, CE.4c, CE.7 to CE.7d; cmd-class AC-16 and AC-24; background-suite-guard B1g2, B1g3, W4a; hook-latency 11a) now pin no rewrite; CE.7c inverts: the residual is a suite started outside the writer's tree |
| `T5-owed-asks.md` | bash-walls W15.9 (a writer's `ruling-ack` admitted) is now W15.9f with the precondition W15.9 and the refusals W15.9a to W15.9e; doctor's notify row names the notify item |
| `T6-agents-true.md` | session-poker §8: a fresh progress file or transcript with no confirmation reads UNCONFIRMED, not RUNNING (four pins); LANDED needs the report |
| `T11-fork-free.md` | cross-gate-agreement §O's mutation needle follows the rewritten `line_field` body |
| `T25-r6em-anchor.md`, `T26-pass-reds.md` | the mutation anchors of landing-line r6em, runner-roster 11.15 to 11.19 and spawn-worktree up3 follow the lines T4 and T9 moved; every expected value unchanged |
| `T3-busy-one-reader.md`, `T4-backstop-pages.md`, `T7-another-layout.md`, `T8-pass-admission.md`, `T9-pass.md`, `T12-rc5-copy.md` | new rows only |

**Records of the decisions.** ADR-053, background work takes only spare capacity, is Accepted. ADR-052 is
read against this run: of its five consequences, one held, three were amended and one was refuted (the marks
are in the ADR).

### The strike list of ten

Chris Lehman fixed the release criterion at D1: the ten 1.16.0 Known limits below, each struck with its
proof or carried with the sentence that says why. Each is numbered as the requirements number it. Seven are
struck (2 to 8); three are carried (1, 9, 10). The count of the others is reported, never a target.

Known limits, carried to the next release. The count is the `- Known limit` bullets that are not struck:
23 here, against 20 in the 1.16.0 block (13 carried from it: the ten that were not on the list, as
they stood, and three of the ten, restated; 10 new). No 1.16.0 bullet vanished: each is struck below or
carried here:

- Known limit: the 1.13.0 limits stand as written there, as triaged in `limits-1.13.0-triage.md`: 66 still
  true, 5 closed (32, 33, 46, 49, 60), none fixed. Sixty-three are carried by the next wave's charter;
  36 and 37 sit in `ideas/wave-run-scorecard-charter.md` and 70 in `ideas/wave-roster-lifecycle.md`.
- Known limit: the auditor is not pushed the severity scale, so its `result` follows its verdicts, not the
  scale; readers holding a code question, and the exam's readers, grade by the scale (Known limit 71 of
  1.13.0, restated).
- Known limit: an evidence verdict's `result` moves with rigor (Known limit 74 of 1.13.0, restated). At
  `single` the critic holds `evidence` with the severity scale, and a REFUTED rated S3 or S4 registers
  `flag`. At `double` the auditor holds it without the scale, so the same REFUTED registers `fail`.
- Known limit: the tick does not name a starved queue and does not require an answer per held row. A held
  row is answered by `task-set`, `task-split` or `decline --on`.
- Known limit: a dead session's roster is pruned, so a whole run it launched stops counting toward the
  second-run rule. The durable twin is the `proved:` line of kind `floor` for a green run.
- (9) Known limit, carried: a writer's suite asks the gate per suite, and a hand-started whole run is
  promised the width and holds the machine alone, so a writer's ask waits behind it on a machine with no
  room beside it. Carried because it was not measured behind a hand whole run. The background run the 1.16.0
  limit asked for is built as a pass that takes only spare room, and measured behind a pass the longest wait
  of any ask was 5 s (`T16-pass-measure.md` section 2).
- (10) Known limit, carried: the 15-minute target for a whole run is missed. The only after-wall is the
  green pass's, 3,728 s at width 2 with 7,333 s of work against the 1aacdc03 run's 2,037 s and 13,019 s at
  width 7 (`pass-c15a7e40de6c.log:112`, `T17-tune-after.md`). Carried because no width-7 after-wall exists,
  the dispatch wall refusing a hand run on a proved head, and the work alone puts a width-7 wall at 1,048 s
  or more with perfect packing, at least 148 s over the 900 s target.
- Known limit: Linux was not used. The cgroup quota read, the `cksum` project key (assumed CRC from its
  documentation), `set -m` in the suite primitive, and `cmd_case_blind`, `real_path` and the case folding of
  command paths were run on macOS only. Their case-exact and quota arms are proved by planted probes, not by
  a Linux host (`T1-typical-cost.md`, `T2-suite-primitive.md`, `T3-budget-at-ask.md`).
- (1) Known limit, carried: a suite started outside the writer's own tree asks as main. The gate learns who
  asks from the tree the ask is made in, so a suite a writer starts in its own tree asks as that writer from
  any launcher in any mode, and no command is rewritten (gate M.1 to M.9, bash-walls CE.1 to CE.7c;
  `T2-red-gate-spawn.log`, `T2-green1.log`, `T2-red-walls.log`; `T18-walk.md` section 1). Carried because
  identity comes from the place a command starts in: a writer that starts a suite in the main checkout is,
  to the gate, the main thread (`T2-identity-from-place.md`).
- Known limit: `bash TESTS/RUN.SH`, and a link to the runner not named `run.sh`, exit 2 for everyone with
  nothing run: the interpreter seam re-runs any script whose basename is not `run.sh`, and the runner
  rejects the paths it is handed. That is the safe direction, pinned by gate.test.sh CA.8
  (`T3-budget-at-ask.md`).
- Known limit: the dispatch wall does not refuse a nested dispatch. A dispatched writer dispatched four
  read-only researchers of its own and nothing refused it (`assumptions.md` A-orch-46). Next wave.
- Known limit: a whole run's width after a short wait may lag. The ring medians over 300 s, so a wait shorter
  than about 150 s can still read busy samples. The fixture rewrites the ring; a live short wait was not
  measured (`T5-width-after-grant.md`, `assumptions.md` A-T5-4).
- Known limit: two suites backgrounded from one script share one gate admission, because the holder is the
  script's `$$`. Two `gate_ask`s from sibling subshells both returned request 1; as separate processes they
  returned 1 and 2 (`walk.md` sections 6 and 8).
- Known limit, new: a background pass is fixed at the width the machine had room for at its ask and never
  widens as the machine goes idle. Both passes of this run ran at width 2 for about 62 minutes, began after
  the last code row and, with the red fix, were 28% of the wall (`T16-pass-measure.md` section 4). Until a
  pass can widen, expect the pass rather than the build to bound the wall.
- Known limit, new: "never makes a writer or a landing wait" holds for the pass's promise and misses through
  live load. The longest wait during a pass was 5 s, a scratch writer's work ask decided by live load of
  which the pass's own cores were part; no writer of this run asked during a pass (`T16-pass-measure.md`
  section 2).
- Known limit, new: memory under a pass was sampled at six moments at width 2 (43 to 46% of 8 GiB); widths 3
  to 5 never ran and the peak between samples is not recorded (`unverified`; `T16-pass-measure.md` section
  3).
- Known limit, new: no notification channel exists on the machine this run ran on (`doctor` reports it; the
  channel file is absent), so no owed send of this run reached the person. Every send in the records went to
  a stubbed `curl`; a delivery to a real service was not seen (`unverified`; `T18-walk.md`,
  `T5-owed-asks.md`).
- Known limit, new: `tests/timing.tsv` is an order key, not a forecast. It is rewritten from the green pass,
  which writes no runner timing, so each suite's seconds are its first-to-last section-stamp span: a lower
  bound, taken at width 2 beside other work (`timing-c15a7e40.tsv`, `T17-tune-after.md`).
- Known limit, new: under a cgroup quota a highly parallel solo suite may read as disturbed and come back
  VOID. The void check models the run's own share as the one-minute load's decay and reads the cgroup's rate
  over a longer interval; no test covers it (`unverified`; `T3-busy-one-reader.md`).
- Known limit, new: the runner's behaviour under a pass admission, its width from the promise and its solo
  suites marked VOID, has no pinned test row. It is shown by a scratch run and by both passes
  (`T9-runsh-pass.log`, `pass-c15a7e40de6c.log`, three VOID).

- Known limit, new: a background pass that the gate skips, or that a whole-machine ask stops, is told
  nothing after `ready` printed `pass: started`; the tick reads a skipped or stopped pass and says nothing,
  so after the last landing no pass may come and nothing says so (`critic-adversarial.md` finding 2,
  deferred by Chris Lehman at D26).
- Known limit, new: an ask with no agent name that ends on the lineage or resume path makes one more `git`
  call than in 1.16.0; a typical ask costs the same (`T2-identity-from-place.md` A-T2-4; waived at D25).
- Known limit, new: a re-dispatch re-marks the tree its plan row's `worktree` cell names, so a row given a
  fresh tree while its cell still names the old one re-marks the old tree too (`T28-remark.md`).

Known limits, struck:

- (2) Known limit, struck: under a cgroup CPU quota the settle wait, the void check and the pressure rung
  that sets a whole run's width read the host's load against the quota's cores. They now read the cgroup's
  own CPU use through one reader beside the gate's, so an idle container on a busy host settles and keeps
  its width, and a busy container still reads busy. resources BUSY.17 to BUSY.27 were red on the unchanged
  code, 373 of 379 passed (`T3-red-resources.log`), then green (`T3-green-resources.log`), and each reader
  has a mutant that goes red (`T3-mutant-settle-host.log`, `T3-mutant-ring-host.log`,
  `T3-mutant-cold-calm.log`). Proved with a planted cgroup root, not on a Linux host: the Linux bullet above
  stands (`T3-busy-one-reader.md`).
- (3) Known limit, struck: the tick's backstop `deliver` against an unread ruling was untested, and driven
  it landed the row over the ruling. The backstop now refuses without marking, names the ids, holds on every
  tick and opens one owed item. session-poker-4 DR-5 to DR-6h and inbox g6 to g8 and §ROOT, red then green
  (`T4-red-session-poker-4.log`, `T4-green-session-poker-4.log`, `T4-red-inbox.log`, `T4-green-inbox.log`),
  two mutants (`T4-mutant-marking.log`, `T4-mutant-closers.log`), and the walk: tick 1 printed NOT-LANDED
  and the row stayed active (`T18-walk.md` section 2; `T4-backstop-pages.md`).
- (4) Known limit, struck: two asks of the person opened no owed item, and waiving a question left its
  `finding:` items open. The commit wall's question and matrix-row waiver refusals now open `waive:` and
  `waive-row:` items from the hook that calls the wall, `waive-row` and `waive` close them, and `waive`
  closes the question's `finding:` items. notify §ASKS and bash-walls, red then green (`T5-red-notify.log`,
  `T5-green-notify.log`, `T5-red-bash-walls.log`, `T5-green-bash-walls.log`), a mutant per opener and closer
  (`T5-owed-asks.md`).
- (5) Known limit, struck: `ruling-ack` run with no agent identity acknowledged a writer's ruling. The wall
  refuses it unless the caller is the ruling's writer, alone in its call; the ruling stays unread.
  bash-walls W15.9 to W15.9f (`T5-red-bash-walls.log`, `T5-green-bash-walls.log`; `T5-owed-asks.md`).
- (6) Known limit, struck: the RC5 deadline had no knob, so each drive slept 24 s. dispatch-preflight-4
  §RECORDER now shortens it in the copy of the hook the suite already runs, 22 to 8 s, and the shipped
  constant is byte-identical, so no production surface gained a knob. RC5's drive took 24 s and now takes 11
  s; the planted overrun still fails (`T12-red.log`, `T12-green.log`, `T12-mutant.log`; `T12-rc5-copy.md`).
- (7) Known limit, struck: slots K6.1, K6.3 and K6.5 stood red under the installed 1.15.0 `line.sh`. This
  run landed under the installed 1.16.0, and slots was green at T8's landing through `ready`
  (`landing-proofs.log:60`) and in both passes (`pass-743a37c6f56f.log:578`, `pass-c15a7e40de6c.log:95`).
- (8) Known limit, struck: `tests/timing.tsv` held the seconds of one whole run, at 88b0f1ec. It is
  rewritten from the green pass at c15a7e40: 95 rows, the same suites, a header naming the head
  (`timing-c15a7e40.tsv`, `T17-tune-after.md`). What the new seconds are is the new limit above.

## 1.16.0 — 2026-10-11

The gate stops forecasting, the plan lands itself, and the person is told. Eleven decisions are built, and
the debt the last three waves left is burned. The gate now assumes one core a command and remembers only
how long a command took. A suite at a landing keeps its traps, its store and its admission. The suite
budget is enforced where a suite starts. A row delivers its own record, a ruling reaches a writer in the
call after it is given, and what the person owes is kept in one ledger and sent once. A finding is an
identity, and a fix closes it. Every decision put to the user takes one shape, through one skill. This is a
minor release by the policy above: the new verbs, the ledger, the sender and the skill are new capability.
`canonical_sdlc_version` stays 14.

**Migration.** None is required. Five behaviours changed that a script of yours may have leaned on.

- The gate's cost files. A 1.15.0 store holds `cost/<key>` files of four-field lines, some ending `:whole`.
  The gate now writes `cost/<project>%<key>` files of `<seconds>:<epoch>` lines and keeps three. It reads
  an old unkeyed file for its seconds only, when the key has no keyed file, and never writes one. Nothing
  needs doing, and an old file may be deleted (`T1-typical-cost.md`).
- `setup.sh --only=` and `remove.sh --only=` with an empty value are refused with exit 2, as a bare
  `--only` is. At 1.15.0 `remove.sh --only=` ran the whole pass (`T4-empty-flag.md`).
- `session-poker.sh decline --on <path>` is refused and records nothing; a decline names a row. The refusal
  prints the call that succeeds (`T7-verbs.md`).
- A wave that shipped no ADR must say `adrs: none` in its plan or spec, or `close-out.sh` refuses and names
  the gap (`T8-close-out.md`).
- A budgeted agent's call that starts a script is rewritten to `export BIONIC_GATE_AGENT=<its row>; <the
  command>`, so a runner inside the script asks the gate as that agent (`T3-budget-at-ask.md`). When the
  session runs in bypass mode, every command of a budgeted agent is rewritten the same way
  (`T36-carry.md`).

What you will notice:

- **The gate promises one core a command.** A command that declares no width is promised 1 core, a whole run
  is promised the width, and no cores or memory are read from any recorded run. The cost the gate remembers
  is how long a command took, kept per project: a worktree shares its repository's durations. The landing's
  time limit reads those durations from the landing tree. The cores a process may use are bounded by the
  host's cgroup CPU quota where one is set. Two new commands on a machine with room now run side by side,
  where at 1.15.0 the second waited on a promise taken from an unrelated run. Record:
  `T1-typical-cost.md`.
- **A whole run reads its width after its admission is granted.** The run that waited behind a busy machine
  now spreads over the quiet machine it was admitted to, and the `Wall:` line carries that width. Record:
  `T5-width-after-grant.md`.
- **A suite at a landing keeps its traps, its store and its admission.** `ready` starts the runner and the
  suite as jobs of their own through one plugin library, so INT and QUIT start at their defaults, the gate
  store is not the suite's, and the suite's `BIONIC_GATE_ADMIT` is the landing's own admission. A standing
  red now records `cause=environment` or `cause=code` and the run that disagrees with it, and the floor
  judge does not count an environment red. Record: `T2-suite-primitive.md`.
- **The suite budget is enforced where a suite starts.** An agent's off-budget suite, or a whole run without
  `run.sh` on its row, is refused at the gate's ask: exit 75, one line, nothing filed, and `tests/run.sh`
  reports it as `REFUSED`. A script that runs a suite is read and admitted, and the `unverified script`
  refusal is retired. Links to the runner or a suite are resolved before they are compared, and the
  comparison folds case where the filesystem folds it. Record: `T3-budget-at-ask.md`.
- **An empty `--only=` is refused.** In `setup.sh` and `remove.sh`, with the bare flag's own message. Record:
  `T4-empty-flag.md`.
- **Every row lands itself.** A record row's last act is `session-poker.sh deliver <row>`: it checks the
  row's artifact (and a review row's registered reading) and lands the row at the working head with the
  artifact in its ledger line. The tick lands a finished row whose agent ended without delivering, and
  reports one whose artifact is absent. A landing replaces the `pending dispatch` lead, where it appended.
  Record: `T6-deliver.md`.
- **The orchestrator's hand edits have verbs.** `matrix-set`, `waive-row` (held to the user's typed words),
  `step-field 5 walk-artifact`, `tasks-prose`, many-row `task-set`, `epic-row` and `continuation-fill`. Every
  plan-verb refusal prints `poker: next call:` with the call that succeeds. Record: `T7-verbs.md`.
- **`brief <row>` renders a dispatch brief from its plan row** and the shipped scaffold into
  `record/<wave>/briefs/<row>.md`; the dispatch preflight accepts it. Record: `T9-brief.md`.
- **Close-out writes the lines it checks.** It inserts the Step-8 line and the walk pointer when they are
  absent, writes the epic row and the continuation whole, and prints the five marks only a person can fill.
  Record: `T8-close-out.md`.
- **A ruling reaches a writer in its next call and is held at the commit.** `rule <writer> '<text>'`
  records it; a hook on every tool result pushes it to that writer once; `ruling-ack <id>` acknowledges it.
  A writer's `git commit` and `ready` are refused, carrying the ruling, until it is shown. The hook's fast
  path forks nothing. Whether the pushed text reaches a teammate running in the same process was not
  measured, and no live session was driven (`unverified`); the guard does not depend on it. Records:
  `T10-rulings.md`, `walk.md` section 2.
- **What the person owes is one ledger, and one sender sends it.** Approvals, gate acts and a delivery are
  items in `.bionic/tmp/owed-<session>.state`; each is sent once through the channel `notify.sh` reads, and
  closed by the act that answers it. With no channel declared, nothing is written outside the ledger.
  `setup.sh` offers the channel (`<claude home>/bionic/notify`, with one test notification), `doctor.sh`
  reports it read-only, `close-out.sh` sends the delivery once, and `remove.sh` takes the file out. Every send in the records went to a stubbed `curl`; a delivery to a real service was not seen (`unverified`). Records: `T11-owed-notify.md`,
  `T12-setup-doctor.md`, `T15-code-debt.md`, `walk.md` sections 5 and 7.
- **A finding is an identity, and a fix closes it.** `task-add --born <record>#<n>` names the findings a row
  answers; a question's reading drops a finding once its fix row has landed green, and an open S1 or S2
  keeps it failing. `session-poker.sh disposition` lists every finding with its rating, state and the
  ruling it needs, and records the person's `fix` or `defer`. "Fixed" means landed green, not that the fix's
  own RED was read. Record: `T13-findings.md`.
- **One skill shapes every decision put to the user.** `/bionic:decision` takes Goal, Options,
  Recommendation, Significance and a last reply line, with the forms and the altitude the skill states. The
  core gains one paragraph and the loaded doctrine ends 448 bytes smaller than it began. The first live
  check failed: two sessions answered in free prose (`T19-decision-live.md`). `session-start.sh` now
  prints one standing line to every session and the skill's description names the which-option case; two
  of two live sessions then answered in the shape. The two changes landed together, so the live runs do not
  say which one did the work (`T27-decision-reach.md`). Records: `T14-decision.md`, `T16-doctrine-debt.md`.
- **The doctrine debt is burned and the axis is a question.** The four doctrine debt pairs are one site or a
  pinned agreement, and the readers' `user-facing` axis is asked as "will a user experience it, including
  its consequence? yes or no". Record: `T16-doctrine-debt.md`.
- **The code debt is burned, and the walls are fixed where the wave found them.** `bionic_trunc` walks a
  character once, the bounded wait is one library (`tests/lib/wait.sh`), the regression setting has one
  reader (`plan_regression`), and `units_unlined` is deleted. A subagent may not call `rule`, `matrix-set`,
  `waive-row`, `tasks-prose`, `epic-row`, `continuation-fill` or `disposition`, and `deliver` is only for
  the row its caller's roster names. The doctrine-growth wall measures a merge in a row's tree against
  `MERGE_HEAD`, so a row is not charged for growth another row already landed. All nine ledgered debt lines
  are burned (`debt.md`). Record: `T15-code-debt.md`.
- **The record is made true.** The epic plan's shipped and planned tables match the waves' own records, and
  each of the 71 Known limits of 1.13.0 is read against the code: 66 still true, 5 closed, none fixed.
  Record: `T17-record.md`, `limits-1.13.0-triage.md`.
- **slots' wait rows keep testing a wait under one core a command.** B2 and K5 make the second command wait
  with a live busy reading of 7.0 cores; every expected value is unchanged. Record: `T28-slots.md`.
- **A container with a CPU limit on a busy host has room.** Where a cgroup CPU quota bounds the cores, the
  gate counted the container's cores but read the host's load average, so a 2-CPU container on a 64-core
  host at load 10 reported no room with nothing admitted, waiting or owed. It now reads the container's own
  CPU use from its cgroup (`cpu.stat`, or `cpuacct` on cgroup v1), and an unreadable file reads 0, never
  full. A host with no quota behaves as before. The container path was proved with a planted cgroup root, not
  on a Linux host (`unverified`; see the Linux limit below). Record: `T33-container.md`.
- **`deliver` refuses while the writer has a ruling unread.** A row's delivery now takes the same look the
  commit and `ready` take: an unread ruling for the row's writer is shown, stamped, and the call exits 2
  with the ruling ids in the refusal. The next `deliver` lands the row. Record: `T34-guards.md`.
- **A failed notification is retried.** When the channel fails, the owed item stays unsent and the next Stop
  sends it, where an earlier build of this release marked it sent and lost it. A caller killed mid-send
  leaves the mark, so an item is still never sent twice. Record: `T34-guards.md`.
- **A named approval or a waiver the person must give opens an owed item.** A row waiting on `approval:<name>`,
  at the tick and at the dispatch wall, opens `approve:<name>`, and a failing review question opens
  `waive:<question>`; the `approve` and `waive` verbs close them, and the person is sent each once. Record:
  `T35-owed-sources.md`.
- **In bypass mode a budgeted agent's run from any launcher is held to its budget.** The agent's name now
  rides on every command it runs, so a suite started through awk, python, node or `source` asks the gate as
  that agent and is refused at the ask when it is off budget. Outside bypass mode only a script start
  carries the name, because Claude Code checks permission rules against the rewritten command (see the
  restated limit below). Record: `T36-carry.md`.

### The floor and the walk

The whole run at 8832e4e6, the head with every build row on it, passed 87 suites and failed 8 of 95, in 1,979
s of wall at width 7 (`regression.md`, `regression-8832e4e6.log`). The log has no `waits for its turn`
line. The eight were pins that later rows had moved, one size cap and one expected stdout: mutation anchors
that no longer matched `proof.sh` or `run.sh` (bash-walls-egd, session-poker-3 63e0c and 63e10, runner-roster
OA.14), two private copies in `gate.test.sh` and `cmd-class.test.sh` (seam-resolution, cross-gate-agreement
S17), session-poker-3 69e4 (a verb list that lacked the three verbs T7 added; the log filed it under
session-poker-4), execution-recorder PC-b0 (the structure checks file was 5,110 bytes against its 5,000 cap, a
real defect), hook-adoption (the standing decision line now reaches a session with a malformed or empty
id, so those two rows expect that line alone), and session-poker-4 MP-m2. Fix row T29 changed test files only:
it moved each anchor to the shipped line with its mutant still biting, took the private copies to the shared
helpers, and put the three verbs in the list (`T29-pins.md`). Fix row T30 cut three repeated clauses from
the structure checks, 5,110 to 4,959 bytes with every check kept, changed the two session-start rows, and
found MP-m2's premise wrong: the refusal already built its number from the constant, and the grep had
matched a comment, which it reworded (`T30-floor.md`). Each suite was green through the door at its row's
landing. Four review fix rows, T33 to T36, landed after that run; each had its own suites green through
the door at its landing (`T33-container.md`, `T34-guards.md`, `T35-owed-sources.md`, `T36-carry.md`). No
whole run cited here was taken after them.

The walk drove the wave head's own verbs, hooks and libraries on a scratch world: the brief, a ruling pushed
and held at the commit, `deliver`, `matrix-set` and `waive-row`, the owed ledger through a stubbed channel,
two unfamiliar commands at the gate, and `setup.sh --only`, `--list` and the notify item (`walk.md`). It drove each verb to the result its record states. Its section 8 lists what it noticed; three notes became Known limits below, and the
smaller ones (a brief whose two artifact lines use different roots, raw epoch seconds in `rulings`, four
`matrix-set` refusals that name the problem and print no call, a one-item setup run that truncates the path
it declared) change no decision and are not listed again.

**The assertion account.** Expected values changed by ordered behaviour changes, each in its record's table,
and one set of rows was deleted with the mechanism it tested.

| record | what changed |
|---|---|
| `T1-typical-cost.md` | the expected values in its table moved to the one-core and durations-only rules; nine rows (D.17, D.18, CO.4 to CO.8, I.8, I.9) were deleted with the peak sampling, the cores-over-machine test and the idle-gate clause they tested; seven suites were given room the gate no longer rations, with expected values unchanged |
| `T3-budget-at-ask.md` | the `unverified script` refusals became admitted `script` claims (SB.2, SB.3, SB.5, §SCRIPT-TEXT); B15f now pins the case-blind refusal and keeps the case-exact answer beside it |
| `T7-verbs.md` | session-poker-2 16d6 to 16d8 pin the refusal of `decline --on` a file |
| `T8-close-out.md` | 86.2a/b and REG-1 pin a refusal and a derived sentence where they pinned a `<fill:` mark; 4k to 4n changed their fixture and kept their expected values |
| `T13-findings.md`, `T28-slots.md`, `T4-empty-flag.md` | new rows only, or fixtures only; expected values unchanged |
| `T34-guards.md` | notify A5e asserted that a failed send was not retried (3 calls); it now asserts the retry (4), with A5f to A5j and K1 to K3 beside it |
| `T33-container.md`, `T36-carry.md` | gate H.10's mutation anchor follows the line it mutates; cmd-class AC-24 (twice) and AC-16 now assert the carried command exactly, with stderr empty and stdout only the rewrite |

Known limits, carried to the next release. The count is the `- Known limit` bullets that are not struck: 20 here, against 18 carried in the 1.15.0 block (its 19th bullet was struck). The block stood at 17 before the four review fix rows; those rows and the critic's re-read of them left three more limits that a user of any project can meet, and they are counted. The count does not fall below 1.15.0's:

- Known limit: the 1.13.0 limits stand as written there, as triaged in `limits-1.13.0-triage.md`: 66 still
  true, 5 closed (32, 33, 46, 49, 60), none fixed. Sixty-three are carried by the next wave's charter;
  36 and 37 sit in `ideas/wave-run-scorecard-charter.md` and 70 in `ideas/wave-roster-lifecycle.md`.
- Known limit: the auditor is not pushed the severity scale, so its `result` follows its verdicts, not the
  scale; readers holding a code question, and the exam's readers, grade by the scale (Known limit 71 of
  1.13.0, restated).
- Known limit: an evidence verdict's `result` moves with rigor (Known limit 74 of 1.13.0, restated). At
  `single` the critic holds `evidence` with the severity scale, and a REFUTED rated S3 or S4 registers
  `flag`. At `double` the auditor holds it without the scale, so the same REFUTED registers `fail`.
- Known limit: the tick does not name a starved queue and does not require an answer per held row. A held
  row is answered by `task-set`, `task-split` or `decline --on`.
- Known limit: a dead session's roster is pruned, so a whole run it launched stops counting toward the
  second-run rule. The durable twin is the `proved:` line of kind `floor` for a green run.
- Known limit: the RC5 deadline in dispatch-preflight-4 §RECORDER is the constant `DP_DEADLINE_S=22`
  (`hooks/dispatch-preflight.sh:306`) with no environment knob, so each drive sleeps 24 s. A knob would
  change RC5's literal bound, which is the user's word.
- Known limit, narrowed: a writer's suite asks the gate per suite. Under one core a command, writers' suites
  run side by side, but a whole run is promised the width, so a writer's ask still waits behind a whole run
  on a machine with no room beside it. No wait was measured in this wave (`unverified`). The background
  whole run at every landing is the next wave's build.
- Known limit: the 15-minute target for a whole run is missed. The whole run at 8832e4e6 took 32m59s for 95
  suites, against 31m36s for 92 at 1.15.0 (`regression.md`); no row of this wave was a speed row, and why the
  run is two minutes longer was not analysed. Carried.
- Known limit: `tests/timing.tsv` holds the seconds of one whole run, at 88b0f1ec, taken under the machine's
  load then; this release adds three rows from the first green runs of decision-skill, inbox and notify. It
  is an order key, not a forecast. The run at 8832e4e6 left `regression-8832e4e6-timing.tsv`; the table was
  not rewritten from it.
- Known limit: `ready` runs the installed plugin's `line.sh`, so every landing of this wave ran the 1.15.0
  landing, and slots K6.1, K6.3 and K6.5 (the INT and QUIT trap controls) stand red in that environment
  until a build that carries `lib/suite.sh` is installed. They are green at a fixture landing
  (`landing-line.test.sh` sig6) and through the door (`T28-green-slots.log`). The floor judge reads them as
  a cause-less standing red until a newer green slots run exists (`T2-suite-primitive.md`).
- Known limit: Linux was not used. The cgroup quota read, the `cksum` project key (assumed CRC from its
  documentation), `set -m` in the suite primitive, and `cmd_case_blind`, `real_path` and the case folding of
  command paths were run on macOS only. Their case-exact and quota arms are proved by planted probes, not by
  a Linux host (`T1-typical-cost.md`, `T2-suite-primitive.md`, `T3-budget-at-ask.md`).
- Known limit, narrowed: outside bypass mode, a runner in another language asks as main. A budgeted agent's
  suite started through python, node, awk, `source` or an out-of-tree script asks the gate as the main
  thread, unbudgeted, unless the agent runs with `permission_mode: bypassPermissions`. Carrying the agent's
  name on every command there would make Claude Code check permission rules against the rewritten command
  and prompt where the original was allowed. A script start is still carried in every mode. An agent that
  types `BIONIC_GATE_AGENT=` itself names its own who. Pinned by bash-walls CE.7c, with CE.1 the bypass-mode
  arm (`T36-green2.log`, `T36-carry.md`, `T3-budget-at-ask.md`). The next wave's first gate item is a
  per-tree marker, `<git-dir>/bionic-agent` holding the row name, which the gate would read when no name is
  set: no command is rewritten, so it closes the launchers in every mode, and it would still leave a suite
  started outside the agent's own tree (`T36-carry.md`, `assumptions.md` A-orch-148).
- Known limit: `bash TESTS/RUN.SH`, and a link to the runner not named `run.sh`, exit 2 for everyone with
  nothing run: the interpreter seam re-runs any script whose basename is not `run.sh`, and the runner
  rejects the paths it is handed. That is the safe direction, pinned by gate.test.sh CA.8
  (`T3-budget-at-ask.md`).
- Known limit: the dispatch wall does not refuse a nested dispatch. A dispatched writer dispatched four
  read-only researchers of its own and nothing refused it (`assumptions.md` A-orch-46). Next wave.
- Known limit: a whole run's width after a short wait may lag. The ring medians over 300 s, so a wait shorter
  than about 150 s can still read busy samples. The fixture rewrites the ring; a live short wait was not
  measured (`T5-width-after-grant.md`, `assumptions.md` A-T5-4).
- Known limit: two suites backgrounded from one script share one gate admission, because the holder is the
  script's `$$`. Two `gate_ask`s from sibling subshells both returned request 1; as separate processes they
  returned 1 and 2 (`walk.md` sections 6 and 8).
- Known limit: `ruling-ack` run with no agent identity acknowledges a writer's ruling (`walk.md` section 8).
- Known limit: the tick's backstop `deliver` against an unread ruling is untested. The tick runs `deliver`
  for a finished row whose agent ended without it, and the refusal line it prints carries the ruling ids,
  but no test drives that path (`unverified`; `T34-guards.md`).
- Known limit: two asks of the person still open no owed item. The commit wall's question and matrix-row
  waiver asks, and `waive-row`, print from `walls.sh` and the ledger does not hear them (`unverified` as a
  source); and waiving a question closes `waive:<question>` but not the `finding:<id>` items
  `disposition` opened for its findings, which stay open, sent once and never re-sent, until a ruling
  closes them (`T35-owed-sources.md`).
- Known limit: under a cgroup CPU quota the gate's room is right (T33), but the settle wait
  (`resources_settled`, `resources_undisturbed`) and the pressure rung that sets a whole run's width still
  read the host's load average against the quota's cores (`resources.sh` §settle). On an idle container on a
  busy host a solo suite waits its 1200 s and comes back VOID, and a whole run is cut to half width. Found by
  the critic's re-read (`critic-adversarial-2.md`, new 1, S3) after the review-born rows were spent; the
  next wave's first gate item, beside the per-tree marker. Not run on Linux.

Known limits, struck:

- Known limit, struck: a capitalised spelling of a suite file or of `tests/run.sh` passed the budget wall on
  a case-insensitive filesystem. The comparison now folds where the filesystem folds, and `bash
  tests/GAMMA.TEST.SH` is refused as gamma.test.sh. Proved by cmd-class §CASE-FOLD and gate §CASE, red then
  green (`T3-red-cmd-class.log`, `T3-green-cmd-class.log`, `T3-red-gate.log`, `T3-green-gate.log`), and by
  background-suite-guard B15f (`T3-red-background-suite-guard.log`, `T3-green-background-suite-guard.log`).
  The literal `TESTS/RUN.SH` and Linux are carried above.
- Known limit, struck: `ready` held a `landing` admission but did not export it as `BIONIC_GATE_ADMIT`. The
  suite now starts through `bionic_suite_start --admit <id>` (`line.sh` `_line_runner`), and
  landing-line (sig7) reads the suite's `BIONIC_GATE_ADMIT` as the landing's own request of kind landing
  (`T2-green-landing-line.log`). No suite that drives the real runner has yet run under the new `ready`;
  that is the K6 line above.
- Known limit, struck: the gate's cost accounting was narrowed, not closed. It promised each owed writer the
  largest cost on record. The gate now promises 1 core to every command that declares no width and keeps
  only durations, per project (`gate.sh` `_gate_cores_for`). gate §ONE-CORE, §SIDE-BY-SIDE and §DURATIONS
  red then green (`T1-red-2.log`, `T1-green-5.log`).
- Known limit, struck: `units_unlined` had no caller and one test pin. Both are deleted (T15, 4d3d0dce); a
  search of `hooks`, `payload`, `tests`, `agents-src` and `skills` finds no hit (`T15-code-debt.md`).
- Known limit, struck: `setup --only=` with an empty value ran the whole pass. loader §E, 87 of 96 passed
  and 9 failed on the unchanged scripts (`T4-red.log`), green after (`T4-green.log`).
- Known limit, struck: a whole run fixed its width from the pressure ring before it waited for its
  admission. It now reads after the grant: runner-roster WG.9 read 1 where 7 was expected, then 7
  (`T5-red-runner-roster.log`, `T5-green-runner-roster.log`). The lag after a short wait is carried above.
- Known limit, struck: the four debt lines from the structure critic. `width.sh` walks a UTF-8 character
  once (units DBC-1 to DBC-1c, `T15-red-units.log`); a bounded wait-until is one library, with all four
  suites on it (name-scan, slots and worktree by T15, green in the whole run `regression-8832e4e6.log`; gate.test.sh by T29, `T29-pins.md`); the share × cores ÷ 100 room has one site, `_gate_share_cores` (T1,
  gate §SHARE-ROOM SR.1 to SR.4); and the run-end re-read has an agreement check over `run_read` and
  `booked_follow` (session-poker-2 56k to 56k8, `T15-green-poker2-worktree-3.log`).
- Known limit, struck: rc-item reached the network. Each yes-answered `setup --all` door cloned humanizer
  from GitHub because `/usr/bin/git` was on the suite's PATH. The suite now puts a git stub first on its
  PATH that rewrites a github.com clone to a local fixture repository. A process sampler saw 118 `git
  clone` of the GitHub URL and 1,044 `git-remote-https` samples before, and 0 `git-remote-https` samples
  after, every clone local (`T31-red-rc-item-net.log`, `T31-green-rc-item-net.log`; `T31-limits.md`).
- Known limit, struck: a ruling acknowledged before its push was still pushed once, and the pending flag
  kept that writer's calls on the hook's slow path until then (`walk.md` section 2). The push hook now
  skips a ruling that carries a `shown=` stamp, and one function settles the pending flag on each push
  and each stamp. inbox §ACK was 62 of 67 on the unchanged code (the acknowledged ruling pushed with
  "acknowledge with:", the flag still up), then green (`T31-red-inbox.log`, `T31-green-inbox.log`;
  `T31-limits.md`).

## 1.15.0 — 2026-10-11

A whole regression run now holds the machine once and runs at the width the share allows, and the hot
sections that filled it are cut where they cost. The whole run at 88b0f1ec took 31m36s for 92 suites,
against 42m43s for wave-31's green run: 11m07s less. The target was 15 minutes. It is missed by 16m36s
and carried to the next release, not moved. This is a minor release by the policy above: the one
admission and the `Wall:` line are new capability, and nothing a user must migrate changed.
`canonical_sdlc_version` stays 14.

**Migration.** None is required. One note for a gate store written before this release. A cost line that
a `whole` request writes now ends `:whole`, and the two readers that turn a cost line into a stranger's
charge skip marked lines (the entry below says why). A line written before this release has no marker, so
it is still read as it was at 1.14.1: the solo suites of 1.14.1 asked `whole <suite>` and left unmarked
lines under their own keys, and a store that a pre-release build of this wave touched may hold a
`tests%run.sh` line of about 7 cores over about 1,900 s. Each key keeps three lines, so an unmarked line
leaves after three newer runs of its key (`assumptions.md` A-T26-3), and nothing needs doing. To clear one
at once, delete the key's file under the gate store's `cost/` directory (a `/` in the key is written `%`
in the file name) and the key re-measures on its next run. This machine's two `tests%run.sh` lines were
pruned by hand on 2026-10-11 (`gate-cost-tests-run.sh-pruned.txt`). Whether any solo suite's unmarked line
on a 1.14.1 store is high enough to matter was not measured (`unverified`).

What you will notice:

- **A whole run holds the machine alone.** `tests/run.sh` with no `--only` asks the gate for one `whole`
  admission, keyed `tests/run.sh`, and every worker inherits it. A landing started in another session
  while a whole run is going waits for it, where before the two interleaved. `--only` and `--serial`
  still ask per suite. Record: `T2-one-admission.md`.
- **The width is the share's room, in one formula.** `gate_width` is floor(share × cores ÷ 100), read by
  the runner and by `--dry-run`'s `JOBS=` line. It is 7 at share 92 on 8 cores. The runner keeps one
  fallback of 8, for a tree without the gate library (`tests/run.sh:512`, the old default); with the
  library present the width is the gate's. Record: `T2-one-admission.md`.
- **The tail prints the run's wall.** A whole run ends with
  `Wall: <s>s · work <s>s · width <n> · last <suite>` after the `Gating:` line, which is byte-identical.
  A `--only` run prints none. Record: `T2-one-admission.md`, `walk.md`.
- **The gate believes by ancestry and learns no impossible cost.** An ask whose holder is the asking
  process or one of its ancestors is believed without an id in the environment. A run that ended in the
  second it was admitted, or that claims more cores than the machine has, writes no cost line, so a
  fixture under a planted clock cannot poison a promise. A run at exactly the core count still writes.
  Records: `T1-leak.md`, `T19-cost-guard.md`.
- **A whole run's cost is nobody's promise but its own.** The run's own admission ends with a cost line
  for key `tests/run.sh`: about 7 cores over about 1,896 s. The gate promised that line to every key with
  no cost of its own and charged it to each writer an owed slot was held for, so one whole run made every
  new suite file wait for an empty machine. A whole request's cost line now ends `:whole`. The never-seen
  key's fallback promise and `gate_room`'s largest-on-record skip marked lines, and a key's own promise
  still reads its own lines, marked or not. Work and landing lines are byte-identical to before. A store
  whose only lines are marked answers a never-seen key as a store with no cost, which is the old rule.
  Record: `T26-whole-cost.md`.
- **A nested runner's request stays out of the real store.** runner-roster's §9(d) nested fixture is
  handed a scratch store. At 1.14.1 it filed a request in the real one that the store could never
  admit. The walk added one request per door run and none from the nested runs. Records:
  `T1-leak.md`, `walk.md`.
- **Two older races are closed in their suites.** session-poker's `run_read` re-reads a run's end file
  once before it says LOST, so a run whose shim wrote its end between the two reads is FINISHED with its
  code, as `booked_follow` already did. cross-gate-agreement §RG and slots B4b.1 stopped meeting a
  saturated machine at a wrong assumption. Records: `T22-run-read.md`, `T21-fixtures.md`.

### Wall time

Three whole runs and the baseline, each quoted from the run's own log.

| run | head | result | wall | record |
|---|---|---|---|---|
| wave-31's green run, per-suite admission | 95fcc048 | 92 suites green | 42m43s (2563 s) | `record/wave-31-task-scale-fixit/regression-final-2.txt` |
| width 8, one admission, no cuts | b7b5bdbe | `Gating: 91 passed, 1 failed`, rc=1 | batch done at +33m04s, then a 20-minute wedge in runner-roster §9(d); 2923 s | `record/wave-32-floor-wall-time/baseline-b7b5bdbe.log`, `-wall.txt` |
| first run after every lever | baae082d | `Gating: 89 passed, 3 failed`, rc=1 | 1940 s | `run-after-D1-baae082d.log`, `run-after-D1.md` |
| the floor run | 88b0f1ec | `Gating: 92 passed, 0 failed`, rc=0 | 1896 s (31m36s) | `regression-final-88b0f1ec.log`, `regression-final.md` |

The two Wall lines, verbatim:

```
Wall: 1940s · work 12219s · width 7 · last bash-walls-egd.test.sh
Wall: 1896s · work 12037s · width 7 · last bash-walls-egd.test.sh
```

The release's before is 2563 s and its after is 1896 s. The run at baae082d went red on three suites:
cross-gate-agreement §RG (the runner's width cap met a fixture that planted share 80), session-poker-2
§56e and §56f (the `run_read` race), and slots B4b.1 (a reap race). T21 and T22 fixed them, and the run
at 88b0f1ec is green. Mean CPU idle in that run was 12% over 193 samples
(`regression-final-88b0f1ec-cpu.txt`). The 15-minute target was not reached. The work divided by the width is 1720 s (28m40s), so the
remaining gap is work, not packing. The suites still over 750 s in the run are rc-item, worktree,
cross-gate-agreement and dispatch-preflight-4.

Per lever. The two figures in an arrow come from different kinds of run. "Run" is the suite's wall in
the width-8 profile run at b7b5bdbe, which ran under load and wedged for twenty minutes in
runner-roster §9(d) after its batch. "Now" is the suite's own solo run through the one door, taken when
its row landed. The paired figure, base and head solo on one machine state, is in brackets where the
row measured one, and it is the honest gain. The source is `T9-shards.md`. No whole run was taken per
lever: the plan took the width-8 run as D1's figure and then one run after every lever, and that run,
at baae082d, already holds T1 to T9, T19 and T20. So no lever has a whole-run figure of its own, and an
arrow overstates its lever by the load its "run" figure was under. The like-for-like check is the five
hot suites (rc-item, refuse, worktree, cross-gate-agreement, dispatch-preflight), summed: in whole runs
4,420 s at b7b5bdbe and 2,883 s at 88b0f1ec, and solo 2,897 s and 1,888 s (`auditor-evidence.md`
AC-3.1).

| lever | change | run → now | record |
|---|---|---|---|
| one admission and the width (T2) | one `whole` request, `gate_width` | batch of 92 suites, 83 `waits for its turn` lines and about 5 running at once in wave-31, now width 7 and no `waits for its turn` line in the log | `T2-one-admission.md`, `regression-final.md` |
| the gate (T1, T19) | belief by ancestry; no zero-second or impossible-cost line; §9(d) off the real store | runner-roster 1,392 s → 176 s (T2 206 → 176) | `T1-leak.md`, `T19-cost-guard.md` |
| `bionic_trunc` in one pass (T3) | the cut counts columns by piece, same bytes over 3,038 differential cases | refuse 862 s → 8 s [479 → 8]; width 222 s → 2 s | `T3-trunc.md` |
| `budget_roster_counts` in one pass (T4) | one awk over the roster | dispatch-preflight 739 s → 227 s [506 → 227]; §budget-markers-pipe 213 s → 2 s | `T4-roster-counts.md` |
| fresh-home §Group 16 (T5) | a bash 3.2 substitution of 260 s becomes one awk pass | fresh-home 600 s → 68 s [325 → 68]; Group 16 281 s → 24 s | `T5-group16.md` |
| setup flag lexing (T6) | `setup.sh` reads its flags before it loads a library | `setup.sh --help` 0.26 s → 0.00 s; rc-item did not move from this cut (603 s → 632 s, noise) | `T6-doors.md` |
| sleeps become waits (T7) | fixed sleeps wait on their condition | worktree 861 s → 577 s [803 → 577]; name-scan 487 s → 257 s [322 → 257]; cross-gate-agreement and dispatch-preflight-4 unchanged within noise | `T7-waits.md` |
| `detect_bounded`'s first tenth (T20) | four short sleeps before the 0.1 s tenths | 0.116 s → 0.026 s per bounded call; rc-item 1,092 s → 544 s, the paired share of that is unverified | `T20-detect.md` |

Suite count before and after: 92 and 92. No suite was split. The shard table in the plan lists the 20
suites over 300 s, and the longest, canonical-sdlc-evidence-gate at 598 s, is under the 680 s bound that
would demand a split; the choice was the user's (option 1). `tests/timing.tsv` now carries one row for
each of the 92 suites, where it had 91 and no row for release-check. T9 wrote it from the rows' solo
records. T24 (77d1a332) rewrote it from the whole run at 88b0f1ec, `regression-final-88b0f1ec-timing.tsv`,
byte for byte, with awk and not with `--write-timing`, which rewrites only from its own run and takes
no file (`assumptions.md` A-T24-1). The longest-first order moved at 68 of the 92 positions. rc-item is
first at 942 s, where it had been third. Records: `T9-shards.md`, `T24-timing.md`.

**The assertion account.** No assertion was deleted, none was skipped, no timing bound was raised, and
no change was made for speed. Sixteen `expect_` expected values changed, and one of them is wider than
before. The diff from b7b5bdbe removes fifteen `expect_` lines, and a sixteenth changes on a
continuation line (`auditor-evidence.md` AC-3.3). Counts of lines starting with `expect_`, at b7b5bdbe
and at 468777de:

| suites | base → head |
|---|---|
| name-scan, worktree, cross-gate-agreement, dispatch-preflight-4, framework, slots, rc-item | 280, 944, 1277, 732, 281, 268, 483: equal |
| session-poker-2 | 708 → 710 (T22's two pins, 56j4 and 56j5) |
| new pins from a RED test | detect-probes +5, dispatch-preflight +12, fresh-home +4, gate +41, runner-roster +30, runner-width +8, width +7 |

The sixteen, by what each does to its claim:

- **Inverted by design, four.** runner-roster ASK.2, ASK.3, ASK.11 and SCRUB.4 pinned one request per
  suite and none keyed by the runner. They now pin one request for the run, keyed by the runner, and
  none keyed by a suite. That is what D1 reverses (`assumptions.md` A-orch-8).
- **Same claim, key moved, ten.** runner-roster ASK.5, ASK.6 and §11 rows 11.2, 11.7, 11.12, 11.13,
  11.22, 11.38, 11.39 and 11.41 pinned that a suite ran under the admission it inherited. They still do,
  with the run's request where the suite's was. 11.39 changes on a continuation line, not on a line
  that starts with `expect_`, which is why a count of removed lines reads fifteen.
- **Retired, one.** ASK.4 counted three distinct holder pids for three suites. With no per-suite ask
  there are no distinct holders, so it now pins that all three ran under the one request. No
  runner-roster row says the suites run in separate workers at once.
- **Widened, one.** slots B4b.1 read the raw request file and passed only while the killed shim's
  request was unended. It now reads the gate's own view, `killed`, which `gate_list` prints both for a
  dead holder not yet reaped and for a request the sampler reaped (ended, rc 137). So it passes in
  both orders of the reap race, and a state the old pin rejected now passes. The race is real
  (`research-red3.md`), and the change was made for it and not for speed. T24 renamed the label to say
  so (`T21-fixtures.md`, `T24-timing.md`). B4b.2 to B4b.4 still pin the reclaim, and gate.test.sh
  §REAPED pins the reap.

The ceiling watcher in runner-roster (11.49 to 11.54b) now stamps when the run's request is admitted and
its first batch suite starts; its bounds are unchanged. cross-gate-agreement §RG plants share 100 for
the runner it drives and keeps its three expected values.
The loader suite gained 66 lines of `eq`, `ok` and `no` checks, which `expect_` counts do not see.

### After the floor

The floor is the whole run at 88b0f1ec plus the suites each later row ran. Four fix rows came after it,
and no whole run was taken again. The landing commits are on the wave branch, and the proofs are in
`landing-proofs.log` and `line/`.

| row | change | landed | proved by |
|---|---|---|---|
| T23 | rc-item's bare `sleep 1` before an observable condition becomes a bounded wait | 55802ff7 | rc-item, green (`line/T23-rc-item-55802ff76b97.log`) |
| T24 | the timing table from the whole run; B4b.1 named for what it asserts | 77d1a332 | runner-roster, green (`line/T24-runner-roster-77d1a332c4a1.log`); slots, the standing K6.1, K6.3 and K6.5 red of the landing environment (`line/T24-slots-77d1a332c4a1.log`), green through the door (`T24-green-slots.log`) |
| T26 | a whole run's cost line is marked `:whole` (above) | 468777de | gate and runner-roster, green (`line/T26-gate-468777dea7f4.log`, `line/T26-runner-roster-468777dea7f4.log`) |
| T25 | the version pages rendered, this entry corrected | this commit | render and release-check, green through the door (`T25-green.log`) |

The version pages, `help.md` and `version.md`, still read 1.14.1 at 9305c4f5, where the release bump had
changed `plugin.json` alone. `render.sh --check` was stale there and is clean after T25
(`T25-render-check-red.log`, `T25-render-check.log`).

Known limits, carried to the next release:

- Known limit: the 1.13.0 limits that this entry does not restate stand as written there.
- Known limit: a capitalised spelling of a suite file or of `tests/run.sh` passes the budget wall on a
  case-insensitive filesystem. `bash TESTS/GAMMA.TEST.SH` opens the real file, its text runs no suite,
  and an off-budget run is admitted. `is_runner` in `cmd-class.sh` compares case-exactly. Nothing this
  wave touched it (`record/wave-31-task-scale-fixit/assumptions.md` A-orch-70).
- Known limit, struck: `runner-roster` hung when run alone through the shim (A-orch-82 of wave-31). T1
  removed the mechanism: the nested fixture's request no longer reaches the real store, and the gate
  believes a nested run by ancestry. The suite ran alone through the shim green at b1ebbb04 (`Gating: 1
  passed, 0 failed`, rc=0, `T9-runner-roster.log`) and again in the walk (152 s, rc=0,
  `walk-only-runner-roster.log`).
- Known limit: the auditor is not pushed the severity scale, so its `result` follows its verdicts, not
  the scale; readers holding a code question, and the exam's readers, grade by the scale (Known limit 71
  of 1.13.0, restated).
- Known limit: `ready` holds a `landing` admission while it proves a row but does not export it as
  `BIONIC_GATE_ADMIT` (Known limit 72 of 1.13.0). The ancestry belief of this release should cover a
  suite that drives the real runner under `ready`, since the `ready` process is its ancestor. No run in
  this wave drove such a suite under `ready` to prove it, so the limit stands.
- Known limit: an evidence verdict's `result` moves with rigor (Known limit 74 of 1.13.0, restated). At
  `single` the critic holds `evidence` with the severity scale, and a REFUTED rated S3 or S4 registers
  `flag`. At `double` the auditor holds it without the scale, so the same REFUTED registers `fail`.
- Known limit: the tick does not name a starved queue and does not require an answer per held row. A
  held row is answered by `task-set`, `task-split` or `decline --on`.
- Known limit: a dead session's roster is pruned, so a whole run it launched stops counting toward the
  second-run rule. The durable twin is the `proved:` line of kind `floor` for a green run.
- Known limit: the gate's cost accounting is narrowed, not closed. This release stops it learning a
  zero-second cost (T1) or a cost over the machine's core count (T19), and a whole request's line no
  longer reaches a stranger (T26). It still promises each owed writer the largest cost on record, a
  whole line excepted, and there is no per-key promise for a brief's own suites. A hand-pruned record
  re-measures on its next run.
- Known limit: `units_unlined` has no caller in code and keeps one test pin (`tests/units.test.sh`
  17d.15); it is dead code to delete in the next release.
- Known limit: the RC5 deadline in dispatch-preflight-4 §RECORDER is the constant `DP_DEADLINE_S=22` with
  no environment knob, so each drive sleeps 24 s. A knob would save about 20 s a drive and change RC5's
  literal bound, which is the user's word (`assumptions.md` A-orch-19).
- Known limit: rc-item reaches the network. Each yes-answered `setup --all` door clones humanizer from
  GitHub, 0.73 s measured, because `/usr/bin/git` is on the suite's PATH. A git stub on the sandbox PATH
  belongs to rc-item's fixtures (`T6-doors.md`, "rc-item reaches the network").
- Known limit: `setup --only=` with an empty value runs the whole pass, where a bare `--only` is refused
  (`assumptions.md` A-T6-4).
- Known limit: a writer's suite still asks the gate per suite, so a writer's run queues behind the whole
  run and behind other writers. Every T4 run waited 2 to 25 minutes (`assumptions.md` A-orch-22). The
  background whole run at every landing is the next wave's build.
- Known limit: the 15-minute target for a whole run is missed by 16m36s, carried.
- Known limit: `tests/timing.tsv` holds the seconds of one whole run, at 88b0f1ec, taken under the
  machine's load then (rc-item 942 s). A solo suite is faster than its row (rc-item solo is 513 to
  544 s). The table is an order key, not a forecast. It was written by awk from the run's timing file
  and not by `--write-timing` (`assumptions.md` A-T24-1).
- Known limit: the landing's own proof environment cannot pass slots K6.1, K6.3 and K6.5 (the
  "unwrapped" INT and QUIT trap controls). They were recorded as a standing red at c79553c4 and baae082d
  (`landing-proofs.log` lines 70 to 72, `line/T21-slots-*.log`), while the suite is green through the
  door and in the whole run (`assumptions.md` A-orch-32).
- Known limit: a whole run fixes its width from the pressure ring before it waits for its admission
  (`tests/run.sh:517`, the ask at `:911`). A run that waited on a busy machine keeps the busy width after
  the machine goes quiet. Run it again. Deferred (critic, adversarial S3).
- Known limit, debt to burn when the code is touched, four lines from the structure critic:
  `width.sh` walks one UTF-8 character three times (`:151`, `:236`, `:252`); a bounded wait-until is
  written three ways in name-scan, slots and worktree beside gate.test.sh's `wait_for`; the share ×
  cores ÷ 100 room is computed at three sites in `gate.sh` (`:180`, `:471`, `:711`) with no test that
  moves them together; and the rule that a dead run is LOST only after one more read of its end file
  lives in `run_read` and in `booked_follow`, and no test drives both over the same race.

## 1.14.1 — 2026-10-10

The floor is now a record of runs, and the regression is a setting. A release's floor is one whole green
run at a commit on the branch plus every later commit proved by the suites its row ran, read from the
records the runs left; nothing predicts a suite set any more. The file-to-suite map that 1.14.0 shipped
is deleted, because it was measured unsound. A plan has one ledger shape: the task-scale shape is
refused. Step 0 asks whether the plan owes a regression at all. Five process checks, the pin suite, the
repository's own CLAUDE.md and 73,883 bytes of the loaded doctrine are gone. This is a patch release by the
policy above: each removal deletes a check or verb that was itself the defect. It also adds the
`regression` verb and key, the landing's evidence writer, the detached run's ceiling and the net-zero
rule. `canonical_sdlc_version` stays 14. The detached run's ceiling, the landing's evidence cells and the
walk as use have met no project but this repository's own release.

**Migration (one ledger shape).** A plan in the retired task-scale shape (`current: T<n>`, the
`id | intent | rigor | description | status | worktree` ledger) is refused on its next `launch-sync`, not
skipped: rewrite it in the one ledger shape the wave and epic plans use, with a numeric `current:` step.
A `later-changes:` block in a plan is no longer read; delete it. A plan with no `regression:` key reads
`regression: yes`. An `impact-command:` line in `.bionic/config.yaml` is no longer read; delete it. A
matrix block that still carries the five retired keys beside `evidence:` is admitted, not refused.

What you will notice:

- **One ledger shape, and a refusal for the old one.** `current:` is a step number at every scale. A plan
  in the task-scale shape now meets this line on stderr, with exit 1, where 1.14.0 skipped it in silence:

  ```
  NOT-RECORDED — current: <value> is not numeric; a plan in the retired task-scale shape is refused, not skipped
  ```

  An empty `current:` stays silent. The task-scale arms are deleted from the ledger writer, the
  ready set, the card and the evidence gate (the task-scale validator and its three rigor lanes among
  them). A plan open at `current: T<n>` stays open, so the launch-sync, the stop wall and the tick name
  it and refuse it. The reason is in
  `.bionic/docs/adrs/epic-23-bionic-tech-debt/adr-050-the-floor-is-a-record-of-runs-and-the-regression-is-a-setting.md`.
  Records: `T5-one-shape.md`, `T24-one-shape-gate.md`.
- **The floor is a record of runs.** A build row runs the suites its brief names. After the last build
  row lands, one whole run, when the plan's `regression:` is `yes`. A fix row runs the red suites plus its
  own. The floor is one whole green run at a commit on the branch plus every later commit proved by the
  suites its row named, and a second whole run needs the user's word:
  `session-poker.sh approve regression-2`. A run at an ancestor of the working head proves the floor when
  every later commit on the branch is proved by a record of the suites it owed, and `proof-add floor`
  otherwise names the first commit it cannot prove and the suites it lacks there. The `later-changes:`
  attestation block and the full-run-owed rules are removed with the bounded arm they served. The dispatch
  wall refuses a whole run in four cases: the plan declares `regression: no`, a row the regression waits on
  still writes tracked files, the head is already proved, and a whole run was already launched on the plan
  without the second-run approval. Records: `T3-floor.md`, `T26-floor-wall.md`.
- **The regression is a Step-0 setting.** Step 0 prints a `regression` line beside rigor and scale, with
  the scale's default (`yes` at wave, `no` at task and epic). The verb
  `session-poker.sh regression <yes|no> '<reply>'` writes `regression:` and, when the value differs from
  the default, `regression-override:`. At `regression: no` the Step-5 block carries one line in place of
  `cmd`, `pass`, `total`, `output` and `head`, and no run is owed:
  `regression: no (Step 0, <user>) — <where it runs>`. An absent key, or any value but `no`, reads `yes`.
  Records: `T4-regression-setting.md`, `T28-regression-card.md`.
- **The impact map is deleted.** `tests/lib/impact.sh`, `tests/impact.test.sh`, the `impact-command:`
  read, the derivation and its time bound, the landing's background warm and the amend verb's derived arm
  are gone. A writer's budget is the suites its brief names, and a brief that names only `Files:` is
  refused with `add Suites: or Re-executes:`. The 1.14.0 entry said the planted-edit proof reddened 2
  suites the map never named for a change to a tests/lib helper; the measured number is 29
  (`record/wave-30-efficiency/T39-planted-edits.log:59`, `red_outside=29`). Records: `T2-map-deleted.md`,
  `T23-map-landing-side.md`.
- **The regression counter reads the command.** `session-poker.sh regression-runs` counts a finished run
  as whole when the command it ran is a whole run of the runner, by one classifier shared with the budget,
  and no longer by the basename of a log. Record: `T21-counter.md`.
- **A landing writes its criteria's evidence.** When `row-landed` records a row, each acceptance
  criterion the row serves gets an `evidence:` pointer to the green log of the suite its `eval:` names, under
  `record/<plan>/line/`, in the same swap, and the poker says `evidence: <n> cell(s) written by landing`.
  A hand landing has no verdict and writes nothing. Record: `T22-landing-evidence.md`.
- **The budget reads what runs.** `amend --reexec+` takes a command quoted in backticks without keeping
  the backticks. A script a shell runs is read for the commands in it, so `bash red.sh` that runs `jest` is
  refused naming `jest`, and a script whose text cannot say what runs is refused as unverified. A writer
  may widen its own row with `amend --files+`. Record: `T11-budget.md`.
- **A detached run has a ceiling.** A detached run the gate has not admitted within
  `BIONIC_SETTLE_MAX_WAIT` (1200 s unless set) ends with exit 75 and the line `booked: the gate did not
  admit this command within <n>s`, and `session-poker.sh wait` prints that line. Record:
  `T12-detach-ceiling.md`.
- **Setup asks only what changes something.** The default share is 92, and setup no longer asks about it.
  Setup brings bionic's working-principles span up to date without asking, names the update in its
  summary, and leaves your own text outside the markers. Record: `T10-setup.md`.
- **One pointer per matrix row.** A matrix row owes `evidence:` and nothing else, and a T4 row adds
  `user-confirmed:`. The five older keys are no longer demanded. Record: `T6-matrix-keys.md`.
- **Five process checks are gone, and the stop guard records instead of denying.** The `unsure:` finding
  line (a fix finding needs `shown:`), the SDLC-State `check:` line with the `finding-check` verb (now the
  usage error `unknown verb`), the Step-8 `cur8_checks`, and the Patrol's `tasklist` and `entry` duties
  are removed. A reader's rating is final. The stop guard no longer denies a stop of a live writer: it
  records `reason=unmet: …` on the writer's roster row and allows it. Revert-and-watch is removed from the
  evidence checks, the test-runner role and Step 5. The reader exam is `tests/exam/reader-exam.sh`, run by
  name, and is no longer a suite of `tests/run.sh`. Records: `T7-process-checks.md`,
  `T31-exam-move.md`, `T33-exam-harness.md`, `T35-exam-table.md`.
- **The walk is use.** Before any row discharges, an agent that has not read the criteria spends about
  fifteen minutes using the shipped plugin as a user would. A process fact, that a step was walked or a
  reader dispatched, is never a T4 row. Record: `T8-walk.md`.
- **No pins.** `tests/docs-pins.test.sh` (7,077 lines) is deleted, and so is the repository's `CLAUDE.md`,
  whose rulings are now in `skills/canonical-sdlc/operational-rules.md`. The release check is the name scan
  plus one contract that no other suite held: the newest heading of this file equals the plugin's
  `.version`. Record: `T1-no-pins.md`.
- **The doctrine is net zero, and the loaded set shrank.** The loaded set is `SKILL.md`, `steps/*.md`,
  `dispatch.md`, `operational-rules.md`, `agents/*.md` and `payload/context/*.md`. A commit that grows it
  is refused, naming the delta and the files, unless the committing row reads `approval:doctrine-growth`
  and the plan carries `approved: doctrine-growth`; a shrink passes silently. The loaded set is 186,087 B
  in 25 files, from 259,970 B at 1.14.0 (by `wc -c` and by the wall's own reader, which agree).
  `operational-rules.md` is 23,759 B, from 95,285 B. The version history it carried is this
  file's. Records: `T9-net-zero.md`, `T30-net-zero-wall.md`,
  `T14-prune.md`.
- **Leftovers.** `perl` is a listed dependency (README and the dependency list), the finding line reads
  `<path>:<line>`, and the floor wait text speaks the floor rule's words. The doctor suites stub `perl`.
  Records: `T13-leftovers.md`, `T34-doctor-perl.md`.
- **Wall time.** Before this release the pin suite's row was 196 s of the run
  (`eeca80e1:tests/timing.tsv:24`; the row left the tree with the suite), and the one full regression took
  46 minutes at width 8 (1.14.0's entry). After it, the one full regression took 42m43s wall clock for 92
  suites at 95fcc048.

Five limits listed under 1.14.0 are retired and do not carry: the impact map's unsoundness, the
task-scale plans, the opt-in planted-edit section, the detached run's missing ceiling and the landing's
background warm.

Known limits, carried to the next release:

- Known limit: the 1.13.0 limits that this entry does not restate stand as written there.
- Known limit: the auditor is not pushed the severity scale, so its `result` follows its verdicts, not
  the scale; readers holding a code question, and the exam's readers, grade by the scale (Known limit 71
  of 1.13.0, restated).
- Known limit: `ready` holds a `landing` admission while it proves a row but does not export it as
  `BIONIC_GATE_ADMIT`, so a suite that drives the real runner under `ready` asks the gate again, and that
  nested ask has no bound (Known limit 72 of 1.13.0). Pointing the gate store at a throwaway directory
  does not work around it: in an empty store the nested ask waits on the unfinished landing admission,
  which waits on it, and exits 75. Land such a row by hand with `land <tree> --by-hand --reason '<why>'`,
  or prove it with `BIONIC_GATE_ADMIT` exported from the landing admission or one seeded cost record in
  the store.
- Known limit: an evidence verdict's `result` moves with rigor (Known limit 74 of 1.13.0). At `single` the
  critic holds `evidence` with the severity scale: a REFUTED rated S3 or S4 registers `flag`, and so does
  an S2-off REFUTED. At `double` the auditor holds `evidence` without the scale, so the same REFUTED
  registers `fail`; the auditor limit above is the reason.
- Known limit: the tick does not name a starved queue (pending rows, room at the gate and nothing ready
  for two ticks) and does not require an answer per held row. A held row is answered by `task-set`,
  `task-split` or `decline --on`.
- Known limit: a dead session's roster is pruned, so a whole run it launched stops counting toward the
  second-run rule. The durable twin is the `proved:` line of kind `floor` for a green run; a red whole run
  by a dead session is the case lost (a 1.15.0 note).
- Known limit: the gate's cost accounting reads the shell's cumulative `times` at run end and promises
  each owed writer the largest cost on record, so one-to-five-second suites claimed 10 to 27 cores and
  held the fill at two or three writers on an 8-core machine. Records were pruned by hand and re-measure
  on their next run (a 1.15.0 fix, beside a per-key promise for a brief's own suites).
- Known limit: `units_unlined` has no caller in code and keeps one test pin (`tests/units.test.sh`
  17d.15); it is dead code to delete in 1.15.0.

## 1.14.0 — 2026-10-09

Review is now one decision. Rigor is the count of independent readers, `single` or `double`, and it
sets who reads, when, which findings become fix rows without asking, and how many rows review may
make on its own. Step 6 ends in one review findings disposition, where you rule the set of findings
the readers rated. The full regression runs once per release head, in a process a `/clear` cannot
kill, and a later head is accepted when the impact map bounds the change. Landings by `ready` took a
median of 9 minutes from the first `ready` to the landing, and the one full regression took 46 minutes
at width 8, against a target of 25 that this release does not meet. This is a minor release: the repository's own rule would read a renamed axis
that a plan must migrate as a major one, and the release is cut as 1.14.0 on the maintainer's ruling.
The migration is one edit per plan, below. `canonical_sdlc_version` stays 14. A plan open at upgrade is
refused on its next write until its `rigor:` line is edited. The detached run and the shorter landing
proof have met no project but this repository's own release.

**Migration (rigor and the structure reader).** `rigor:` takes `single` or `double`: `low` and `tested` become `single`; `medium`, `high`, `peer-reviewed` and `audited` become `double`. `bionic:reviewer` is retired: a brief that names it is refused, and structure is read by `bionic:critic`, which holds `structure` at both levels. Open plans migrate by editing the `rigor:` line and the rigor cells of the ledger.

What you will notice:

- **Rigor is `single` or `double`, and it sets four things.** `single` is one independent reader: the
  critic holds `evidence`, `adversarial` and `structure`. `double` is two: the auditor takes `evidence`
  and the critic the other two. Step 0 writes three header fields beside `rigor:` and prints them under
  Run: `review-cadence:` (`once`), `fix-policy:` (`S1,S2-on`) and `fix-cap:` (2 at `single`, 10% of the
  plan's rows at `double`). Each is the user's to set, and a plan that carries none of them takes the
  level's default. The card prints `review rigor: single (one independent mind)` or
  `review rigor: double (two independent minds)`, and `rigor-floor:` in `.bionic/config.yaml` takes the
  same two words. The six older words are removed, with no alias, from the enum, the doctrine, the role
  files and the tests. The reason is in
  `.bionic/docs/adrs/epic-23-bionic-tech-debt/adr-049-review-is-a-decision.md`.
- **The structure reader is retired as a role.** The role file and its template are gone, and the
  roster in `/bionic:help` and the README no longer lists it. The critic holds `structure`. In
  `checks-structure.md`, `reuse` and `one-site` stay checks that must be answered; `single-job`,
  `open-closed`, `substitution`, `narrow-interface` and `dependency-direction` become findings the reader
  may raise, beside a new one for an abstraction, parameter or indirection with one case or one caller.
- **A finding is classed by when it is paid for.** Harm is paid by the user now and is rated S1 to S4 as
  before. Evidence is paid by the claim now. Debt is paid by the next change that touches it, and is
  rated by kind (`duplicate`, `unpinned-pair` or `one-case-abstraction`) and the concept it names, never
  by severity: `debt: <kind> <concept> <path>:<line>[, <path>:<line>…]`. A debt finding is never fixed now
  and never merely noted; its disposition is burn-when-touched.
- **Review is one reading and one disposition.** The readers are dispatched once, when the last build
  row has landed and the regression and the walk are on disk, and each reads the settled whole. The
  orchestrator brings every finding to you with its rating and a recommendation (fix now, Known limit or
  next wave), and you rule the set. A row exists only from that ruling, recorded on the row with your
  attribution. The one row the orchestrator may make alone is an in-diff finding inside `fix-policy:` and
  under `fix-cap:`, marked `born: review S<n> <reach>`, and it says so in the disposition. Three stop
  rules hold whatever the policy says: a finding in code the run did not change is a next-wave item unless
  it is S1; three fixes on one component stop the run; a fix row is never re-read by a fresh pass. Only
  the reader that found a finding rates it: no agent, the orchestrator included, moves a rating in either
  direction, and your re-rating is recorded with your name. The landing report prints
  `review-born rows: <n> of cap <m>`. This closes the open question in ADR-047 decision 5, and ADR-047
  carries the amendment.
- **The checks files gained four clauses, and the reader exam four samples.** `checks-adversarial.md`
  asks what untrusted input reaches the change, what it can expose, whether it fails closed and what a
  missing dependency or an inconsistent install leaves behind, and points at the project's Known limits.
  `checks-evidence.md` asks, per row, whether a changed condition has a test that fails when it is wrong.
  The exam gained one sample for each of those clauses and one for over-engineering; the dealing is the
  critic on all three questions and the auditor on `evidence`. The exam's own sittings keep that name.
- **A docs-only landing owes no reading.** A commit whose diff touches only `CHANGELOG.md`, `README.md`,
  `CLAUDE.md`, `.bionic/` or `.claude/rules/` is not asked for piece coverage. A commit that mixes one of
  those with any other file still is, and `skills/` and `agents/` prose is never docs-only because agents
  execute it.
- **A run is an object, and it survives a `/clear`.** The Bash wall starts a suite-class command through
  `booked.sh --detach`, which forks the whole run into a session of its own. It prints
  `booked: started pid=<pid> log=<abs path>.log run=<id>`, writes `<log>.pid`, and ends the log with
  `rc=<n>` on every exit. A second attempt writes `…-2.log` and never truncates the first.
  `session-poker.sh wait <name|run id> [--for <s>]` waits on a run and exits with its code; it is
  re-entrant, so a second wait after the first was killed finds the same run and never starts it again.
  `stop-run <name|run id> [--report-only]` sends TERM to the run's process group and KILL to any group
  below it still alive after five seconds. A run whose pid is gone and which wrote no end is `LOST`
  (exit 70), never a timeout, and the test-runner role reads exit 137 as a kill unless the elapsed time
  reached the declared limit. `adopt` prints each adopted row's run as `RUNNING pid=… elapsed=…`,
  `FINISHED rc=…` or `LOST`. A run shows its progress while it runs: `tests/lib/assert.sh` appends one
  line per section to `<log>.progress.tsv`, `wait` prints the last one at each poll, and the tick's
  `RUNNING` line carries it. Close-out reports a detached run still alive as `orphan:`, and stops it
  when it writes.
- **The regression runs once.** `regression-runs: <n>` in the plan header is counted from the run
  records whose command is the full runner, never typed; `session-poker.sh regression-runs [--write]`
  prints the count and writes it, and the tick and the release card print it. A verify or test row may
  not drop `head` from its `reads` cell, so the regression waits for every open row that writes code. The
  timing checks that must run alone moved to a suite marked `# runner: solo`, and `tests/run.sh` hands
  each suite an environment without `BIONIC_GATE_DIR`, so a suite no longer inherits the store of the
  runner that started it.
- **A proof is a fact about code.** `proof-add floor` accepts a run whose head is an ancestor of the
  working head when the map bounds the change since, and when every suite the map names has a green stamp
  at the working head with `rc=0` and `dirty=0`. A change the map cannot bound, or answers with the whole
  roster, owes a full run on the new head; a moved head alone does not.
- **Locating is not reading.** The two lines in `tests/lib/resolve-roots.sh` that locate the hooks and
  skills directories carry `# impact: locates`, and the impact map no longer expands them to every file
  beneath. `hooks/session-poker.sh` now answers the suites that source, copy, pin or name it (54 of the
  85 suites then in the roster) where it answered all of them. A file nothing names answers none, and none is read as a full run. A planted-edit sweep in
  `tests/impact.test.sh` plants one edit in every file under `hooks/` and `skills/` and requires a suite
  the map names to go red.
- **A landing proves in minutes.** `dispatch-preflight`, `session-poker` and
  `canonical-sdlc-evidence-gate` are each split by section into suites with a sibling prelude, with no
  check lost. `tests/run.sh` orders the roster longest first from `tests/timing.tsv`; a full run rewrites
  that table only with `--write-timing`, so a default full run leaves the tree clean and its stamp reads
  `dirty=0`. After a landing moves a checkout, `ready` warms the project's impact cache in the
  background, so the first dispatch after a landing does not pay for a cold derivation.
- **Step 3 renders the matrix, and Step 5 fills values.** `session-poker.sh matrix-render` writes the
  plan's acceptance blocks from `## Eval design`, each key its tier owes set to `pending`, and adds the
  keys a block lacks without rewriting a value. `stack-health:` and the matrix-level `walk-artifact:` lose
  their exemption: a placeholder is refused at Step 5 once no row is open. `session-poker.sh discharge
  <AC-id>` writes the auditor cell as the bare token `CONFIRMED`.
- **The handoff is written by a verb.** `session-poker.sh handoff` rewrites `## Handoff` in place from the
  plan and the machine (the heads, the open rows, the live agents with their run state, the last proof and
  `date -u`), carrying the lines a person wrote by hand. It is never appended and never written by hand.
- **A dependency is doubted where it is written, and a row can be split.** `task-add` and `task-set`
  print `suspect: <id> reads <dep>, shares no file — loosen it: … task-set <id> reads=…` for a
  declaration whose rows share no file, and accept the row; the tick's `WAIT` line carries the same
  clause. The `CHAIN` line names the best row to split as `SPLIT? <id> — <n> min, <k> files, <m> rows wait
  on it`. `session-poker.sh task-split <id> -- <id>:<task>:<size>:<Files>…` drops a pending row with
  `split-into:`, adds its children with a partition of its Files, re-points every row that waited on it,
  and writes the ledger line, as one validated transaction. `decline <ids> '<reason>' --on <row|file>`
  records what a hand hold waits on and prints the `task-set` line that makes it a table fact.
- **Debt is a ledger, burned when touched.** `session-poker.sh debt add <reading record>` writes each
  debt line of a reading into `record/<run>/debt.md`, one line per item:
  `concept | kind | sites | raised-by <record> | touches N | burned <row> | —`. `debt touched`, `debt burn`
  and `debt list` keep it, and `debt adopt <continuation>` writes a previous run's carried items into this
  run's ledger with their touches kept. When a writer's `Files:` covers a site of an unburned item, the
  dispatch wall prints `debt: <concept> <kind> touches <N> — burn it in this row or say why not` and
  counts the touch. `ready` prints `debt: burned <n>, touched <m>` between `LANDED` and the owed line,
  and the release card prints `debt: touched <n> · burned <m>`, never the length of the ledger. Close-out
  carries each unburned item into the continuation as
  `debt: <concept> <kind> "<sites>" touches=<n> raised-by=<record> from=<wave>`, and the next run's Step 1
  card lists it under Inherited deferrals.
- **"Floor" is now "regression" in what bionic says.** The doctrine (SKILL.md, steps/5.md, dispatch.md, operational-rules.md, the role files, browser-verify), the tick's and the walls' messages, the Step-3 card and the continuation template call the full test run the regression. The verbs and keys keep their spelling until bionic2: `proof-add floor`, `floor-run`, `floor:` and `floor-attestation:` in `.bionic/config.yaml`, and `proof:floor` in a reads cell. Nothing a user types or a file carries changes.

  Newly worded (no new refusal): `poker: WAIT <id> — proof:floor: the head moved past the regression proof at <head> …`; the evidence gate's `bionic: commit refused — the release head does not contain head: (run the regression on that head)`; the dispatch wall's `head <sha> is already proved (keep the regression proof; run nothing)`.

  Known limit: a few code comments outside the shipped doctrine still say floor for the full run (lib/worktree.sh, lib/fill.sh, lib/brief.sh, scripts/spawn-worktree.sh); no message does.
- **For contributors.** The execution recorder's two stale pins follow the wall's `--detach` arm and the
  cap the context files now carry. The shard suites keep their check counts, and the roster has 94 suites.

Newly refused:

- A plan or spec whose `rigor:` is any of the six older words, or any other word:
  `bionic: write refused — that rigor is not single or double (pick an allowed rigor)`.
- A header field outside its vocabulary:
  `bionic: write refused — a fix-policy word is no rating (S1,S1-on,S1-off,S2,S2-on,S2-off,S3,S4)`,
  `bionic: write refused — this fix-policy names no rating (S1,S1-on,S1-off,S2,S2-on,S2-off,S3,S4)`,
  `bionic: write refused — that review-cadence is not once (use once)`,
  `bionic: write refused — that fix-cap is no count (a whole number, or a percent)`.
- A brief that names the retired role:
  `bionic: dispatch refused — bionic:reviewer is retired (1.14.0) (dispatch bionic:critic)`.
- A fourth fix on one component, and a review-born row outside the fix policy or over the cap, which
  `task-add --born 'review S<n> <on|off>'` refuses with the plan unchanged:
  `poker: task-add refused — a fourth fix on <path>: <rows> already fix it; stop the run (AC-10.2)`.
- A verify or test row whose `reads` cell drops `head`, refused by the evidence gate's ledger check:
  `<id>: reads <cell> drops head; a <verify|test> row must read head (its default approval:plan, head waits on every open row that writes code)`.
- `proof-add floor` for a run whose head is an ancestor of the working head when the change since is
  bounded but a suite the map names has no green run at the working head:
  `the run in <ev> read head <sha12>, and <n commits> landed since, to the working head <sha12>; the map bounds the change to <suites>, and no green run at <sha12> is recorded for: <suites>. Run each of those suites on <sha12>, then proof-add floor again`.
- `task-split` on a row that is not pending:
  `poker: REFUSED — <id> is <status>; task-split rewrites a pending row only. The plan is unchanged.`
- A reading's debt line that carries a severity or reach, a kind off the table, no site, or a site that is
  not `<path>:<line>`: `the reading <record> rates its debt line (<line>) with '<token>', and debt is rated by kind and concept, never by severity or reach; write debt: <kind> <concept> <path>:<line>[, <path>:<line>]`.
- Step 1 over a newest continuation whose `debt:` line does not parse:
  `card.sh: step1 refused — the newest continuation carries a debt: line that does not parse`.
- `tests/run.sh --write-timing` with `--only` or `--dry-run`:
  `tests/run.sh: --write-timing needs a full run; it is refused with --only and with --dry-run`.

Upgrade, for a plan already in flight:

- Edit the plan's `rigor:` line to `single` or `double` by the migration above, and its ledger rigor
  cells with it. A plan without `review-cadence:`, `fix-policy:` or `fix-cap:` is admitted and takes the
  level's defaults. `regression-runs --write` refuses a plan with no `regression-runs:` line in its header, so add
  `regression-runs: 0` first.
- A brief written for `bionic:reviewer` names `bionic:critic` instead, and its `Questions:` line is the
  set the plan's rigor deals the critic.
- Nothing is renamed in a file you carry: `floor:` and `floor-attestation:` in `.bionic/config.yaml`,
  `proof-add floor` and `floor-run` keep their spelling.
- The Patrol prompt stays at version 6; there is nothing to re-arm.

Fixes:

- The first dispatch after a landing is no longer refused for a cold derivation. The dispatch wall's
  bound on the project's impact command is 20 seconds, its registration 25 and its own deadline 22 (they
  were 10, 15 and 12), because a cold derivation took 8.5 to 10.3 seconds on an idle machine and more
  under load; `ready` also warms the cache after a landing moves a checkout.
- `proof-add floor`'s refusal is no longer cut at 400 characters, which had dropped the list of suites it
  asks you to run.
- A suite run by `tests/run.sh` no longer inherits `BIONIC_GATE_DIR`, so a runner started under a leaked
  store no longer reports a stale timing bound as a failure.
- A full run leaves `tests/timing.tsv` as it found it unless `--write-timing` is given, so its stamp
  reads `dirty=0` and `proof-add floor` accepts it.
- The finding and debt line grammars in `payload/context/severity.md` and `steps/6.md` state the
  `<path>:<line>|-` alternation as a choice with an example. A reader that copied it whole wrote a line
  the parser refused, and the exam scored that as a miss.

Known limits, carried to the next release:

- Known limit: the impact map is measured unsound. The planted-edit proof (tests/impact.test.sh §F,
  made real in this release) reddened suites the map never named on every class it reached before
  the release: 2 for a hook, 15 for a payload library, 2 for a tests/lib helper
  (record/wave-30-efficiency/T39-planted-edits.log). Until the map's edges are fixed (1.14.1), a
  bounded proof on the map is not to be relied on: the release floor is the full run, and a writer's
  landing proves only the suites it ran. The map still widens a writer's budget.
- Known limit: task-scale plans (`current: T<n>`, the `id | intent | rigor | description | status |
  worktree` ledger) are not recorded by `launch-sync`, refused by `task-set` and `ledger-add`, and
  misread by the tick's ready set; the hand workaround and the fix are in
  ideas/task-scale-launch-sync-and-ledger.md (1.14.1).
- Known limit: the 1.13.0 limits that this entry does not restate stand as written there.
- Known limit: the auditor is not pushed the severity scale, so its `result` follows its verdicts, not
  the scale; readers holding a code question, and the exam's readers, grade by the scale (Known limit 71
  of 1.13.0, restated).
- Known limit: `ready` holds a `landing` admission while it proves a row but does not export it as
  `BIONIC_GATE_ADMIT`, so a suite that drives the real runner under `ready` asks the gate again, and that
  nested ask has no bound (Known limit 72 of 1.13.0, its workaround corrected). Pointing the gate store at
  a throwaway directory does not work around it: in an empty store the nested ask waits on the unfinished
  landing admission, which waits on it, and exits 75. Land such a row by hand with
  `land <tree> --by-hand --reason '<why>'`, or prove it with `BIONIC_GATE_ADMIT` exported from the landing
  admission or one seeded cost record in the store.
- Known limit: an evidence verdict's `result` moves with rigor (Known limit 74 of 1.13.0, with its missing
  clause). At `single` the critic holds `evidence` with the severity scale: a REFUTED rated S3 or S4
  registers `flag`, and so does an S2-off REFUTED. At `double` the auditor holds `evidence` without the
  scale, so the same REFUTED registers `fail`; the auditor limit above is the reason.
- Known limit: `tests/impact.test.sh` §F, which is opt-in and outside the gating roster, proves nothing
  at this release. Its roster read matches no line of `tests/run.sh` because the runner derives its roster
  from the tests directory, so it reports `roster: 0 suites` and its complement never runs for any file
  class. Its plant of `tests/run.sh` also fails, because the witness it names stays green. The gating
  sweep in the same suite is the proof of the map; §F is not.
- Known limit: a detached run whose command waits on a gate that never admits has no ceiling of its own.
  The caller's timeout, `wait --for` and `stop-run` are the bounds.
- Known limit: the background warm that `ready` starts after a landing has no ceiling, so a hung impact
  command leaves a background process behind; and it is live only once the installed plugin carries it, so
  the landing that ships it does not warm.
- Known limit: the tick does not name a starved queue (pending rows, room at the gate and nothing ready
  for two ticks) and does not require an answer per held row. One earlier run's record showed no such turn
  in 573 turn ends, so it was not built; a held row is answered by `task-set`, `task-split` or
  `decline --on`.

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
- **The evidence checks ask for finding lines.** The evidence checks file asks for finding lines and
  grades `result` by the severity scale when the scale is pushed with the checks, as the other two
  checks files do.
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
  `spawn-worktree: REFUSED reason=no-launch-row row=<row> roster=<path> — ready reads the row's suites off the roster row the walls read`,
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
  begins `poker: REFUSED — the reading <record> …` and says what to write. For `structure`, a `check:` that answers
  FAIL beside no finding to fix, and a finding to fix beside no FAIL check, are refused the same way.
  A record path registered again for another pass:
  `poker: REFUSED — <record> is already registered at <12 hex>, not <12 hex>: write the pass to a new record path. The plan is unchanged.`
- `session-poker.sh finding-check`: refused, with the plan unchanged, for a check the plan does not owe, a
  check already settled, a check record that is missing, a link, outside the record directory, with no
  `written-by:` or written by the finding's reviewer or the code's writer; and `current 8`:
  `poker: REFUSED — current: 8 waits on each check a finding owes; these check: lines are open (no settled=, no refuted):`.
- `session-poker.sh finding-move`: refused, with the plan unchanged, for a finding the plan does not register,
  a finding its check refuted, an S1 moved to defer, a repository with no `git user.name`, a session whose
  transcript cannot be read, and words that stand in no prompt the user typed in this session:
  `poker: REFUSED — the words "<words>" stand in no prompt the user typed in this session; a move is the user's own word, quoted from a prompt they typed. The plan is unchanged.`
  and a quote too short to be a decision:
  `poker: REFUSED — the words "<words>" are too short to be the user's decision; quote at least 3 of their words, or their whole prompt. The plan is unchanged.`
- `session-poker.sh floor-run` for a project that declares no `floor:`, for a plan whose working branch no
  checkout holds, and for a floor that moved the working checkout while it ran; `proof-add floor` for a log
  whose head is not the working head, whose tree was dirty, whose floor did not pass, or whose first line
  is not the line `floor-run` writes, for an attestation that names no head or no `floor-attested-by:`
  line, and for a `floor-attestation:` value other than `user`:
  `poker: REFUSED — this project declares no floor: in .bionic/config.yaml; its floor is tests/run.sh, whose log proof-add floor reads. Nothing was run.`,
  `poker: REFUSED — the floor (<cmd>) moved the working checkout <co> while it ran (<what moved>); no log was written. Put back what it changed and run floor-run again.`,
  `poker: REFUSED — the run in <ev> read head <sha12>, but the working branch is at <head12>; run it again on <head12> and cite that log. The plan is unchanged.`,
  `poker: REFUSED — the floor in <ev> did not pass (rc=<n>); fix it, run floor-run again and cite that log. The plan is unchanged.`
- `session-poker.sh step-field` for a value with a line break, a key outside the nine, a step with no line, a
  Step 9 block, or a step line that itself carries the key:
  `poker: REFUSED — a step field is one line, and the value has a line break; the plan is unchanged.`,
  `poker: REFUSED — '<key>' is not a step field; the plan is unchanged.`,
  `poker: REFUSED — the plan has no Step <N> line; step-line writes it first. The plan is unchanged.`,
  `poker: REFUSED — the Step 9 block is close-out's to write (scripts/close-out.sh).`
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
- The stop guard reads a long roster in one pass; on a roster of hundreds of rows it used to run past its
  own deadline and refuse every stop with `stop again`.

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
- Known limit: the admit-not-require sample's key admits a finding on the defect's two files or on the
  matrix row the verdict refutes; a finding placed on the evidence file, the test or `-` scores missed.
- Known limit: the exam's briefs ask a reader to read the scale and checks files from the plugin copy by
  path, outside its project; a session that cannot read outside its project needs them inlined — at
  wave-28's sitting every headless reader could.
- Known limit: a suite run by `source tests/<suite>.test.sh` or `. tests/<suite>.test.sh` from a
  dispatched agent passes the Bash wall with no refusal, wrap or stamp; only the spellings the classifier
  reads meet the door.
- Known limit: the suite shim decides the gate request's tree and the stamp's tree separately — a command
  that opens with `cd <row tree>` and passes no `--stamp-dir` records the request against the row tree
  and the stamp against the tree it was started from; the doctrine's form always passes `--stamp-dir`, so
  a writer following the doctrine's suite-call form never meets it.
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
- Known limit: a suite call that carries a `$( )`, a pipe, a `&`, a backquote or a subshell between its
  `cd` and the suite may be stamped against the main checkout, and so may the `> "$LOG"` redirect form, a
  `cd "$VAR"`, a `cd` behind `||`, and a variable assigned in the call and used in the suite segment; keep
  the call in the doctrine's suite-call form
  (`cd <tree> || exit 1; LOG=…; bash tests/run.sh --only <suite> 2>&1 | tee "$LOG"`) and read the stamp.
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
- Known limit: a writer dispatched in the foreground cannot land through `ready` while it runs — its
  plan row's worktree cell is filled only when the dispatch call returns, so `ready` falls back to the
  branch name; dispatch writers in the background, as the doctrine says.
- Known limit: after a foreground writer's landing, the owed `TaskStop` finds the agent already
  completed, so the stop guard never fires and the tick keeps its row open (`stand-down deferred`) until
  the roster is swept; a background writer is stopped as the owed line says.
- Known limit: the auditor is not pushed the severity scale, so its `result` follows its verdicts, not the
  scale; readers holding a code question, and the exam's readers, grade by the scale.
- Known limit: `ready` holds a `landing` admission while it proves a row but does not export it as
  `BIONIC_GATE_ADMIT`, so a suite that drives the real runner under `ready` asks the gate again, and
  that nested ask has no bound; a row whose suites drive the runner is proved with the gate store
  pointed at a throwaway directory.
- Known limit: `ready` proves a row with `exec bash tests/<suite>` — the bash on PATH, not the
  interpreter pin the floor runs under — so a row can land green under `ready` and go red on the
  floor; the floor is the judge.
- Known limit: an evidence verdict's `result` moves with rigor: at `low` the critic holds `evidence`
  with the severity scale and a REFUTED rated S3 or S4 registers `flag`; at `medium` and `high` the
  auditor holds `evidence` without the scale and the same REFUTED registers `fail`.

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
