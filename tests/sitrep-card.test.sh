#!/bin/bash
# Tests for the sitrep card: `payload/scripts/card.sh sitrep` and `sitrep-check`, and the verb that draws it,
# `hooks/session-poker.sh sitrep card [<plan>]`.
#
# CODE DRAWS THE FACTS, THE MODEL WRITES THE JUDGMENT, THE CHECK DECIDES THE TRUTH. The verb gathers the fact sheet;
# card.sh draws every row that is a fact from it: the head, the Task list from the step: and task: lines, the
# five-line Metrics table from the measured values, Blocked on you from the asks that block the user (or None and the
# nearest event), one counted line for the asks that wait on events, and the predicted close with its basis. The model
# writes seven lines on stdin: purpose:, call:, grade:, one to three point:, ask <key>: for an ask that waits on the
# user, and close:. The check refuses only what would make the card false, a number no sheet value holds or one set
# beside another value's word, a state the sheet denies, a refused word, a missing purpose, call, grade or close, and
# a tag outside the seven, every reason at once on stderr with nothing on stdout, rc 1. It repairs everything else:
# a long line folds, a fourth point is kept with a note, an ask the judgment leaves out is drawn as the ask alone.
#
#   §MOCKUP    the flock-app-shaped sheet and a seven-line judgment draw the approved mock-up's shape, under 40 rows
#   §SECTIONS  seven sections in order, every row bulleted, iconed or a Metrics row, each model row capitalized
#   §DRAWN     every step and task row drawn from the sheet's own records; a task: or metric: line is refused by name
#   §TABLE     the Metrics are five lines, every number a measured value of its own line, the pace comparison first
#   §COUNTED   the asks that wait on events are one counted line under the Assessment, by kind, never a row each
#   §TAGS      the seven tags draw; a foreign tag is refused by name, a missing one is named; a fourth point is kept
#   §PURPOSE   the purpose is the Assessment's first row, required, and its numbers are checked
#   §CALL      a call saying nothing is owed stands while every ask waits on an event, and refuses over a blocking one
#   §BLOCKS    Blocked on you lists the asks that wait on the user and hold something, else None naming the next event
#   §BIND      every number in a judgment line is a sheet value, bound to the word beside it by word and by place
#   §SHAPE     the drawn card's own shape: width, a step row above its tasks, an open task twice or missing
#   §WORDS     "reader", "reading" and their kin, or "unmeasured", in the judgment refuse the card
#   §REASONS   a refusal names every reason at once, nothing on stdout
#   §HEAD      the head names the wave only when the run has one
#   §VERB      the verb draws the card from the sheet the judgment was written from, under 10 minutes old, its asks
#              read fresh, and settles a decision the ledger ruled first
#   §SKILL     the skill writes the tags the verb takes and shows only what the verb printed, in one fenced block
#   §ONE-READER the goal's status, the task's title and the goal's measure are each one function the sheet and the
#              cards call: a plant in that one reading moves both surfaces together
#
# HERMETIC. card.sh is fed fixture sheets in the verb's own `sheet/v1` shape, one of them a sheet the verb saved for
# a real run, copied whole; the verb runs in one temp repository with a pinned clock and zone, its own gate store and
# pinned machine probes, as tests/sitrep.test.sh runs it.
#
# ANTI-VACUITY. Every refusal stands beside the same card passing with the one fact moved back; every planted
# fault is read by the same check that passes the unplanted card in the same call.
#
# Usage: bash tests/sitrep-card.test.sh
#
# pins: payload/scripts/card.sh payload/scripts/lib/width.sh hooks/poker/sitrep.sh skills/sitrep/SKILL.md

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
CARD_SH="${REPO}/payload/scripts/card.sh"
POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"
WIDTH_SH="${REPO}/payload/scripts/lib/width.sh"
# shellcheck source=/dev/null
. "$WIDTH_SH"

TMPROOT="$(mktemp -d)"
cleanup() { chmod -R u+rwX "$TMPROOT" 2>/dev/null; rm -rf "$TMPROOT"; }
trap cleanup EXIT

# ---------- the fixture sheets ----------
SC_BASE='sheet/v1 — facts for the model; the user sees the card, never this sheet
run.release: 1.24.0
run.name: wave-41-sample
run.wave: 41
run.now: Tuesday 2:40 PM
run.step: 4
run.project: bionic
run.started: 8:10 AM
run.last-landing: T13 at 2:31 PM
step: n=0 name=Configure state=done tasks=0
step: n=1 name=Scope state=done tasks=0
step: n=2 name=Design state=done tasks=0
step: n=3 name=Plan state=done tasks=2
step: n=4 name=Implement state=running tasks=6
step: n=5 name=Verify state=pending tasks=1
step: n=6 name=Review state=pending tasks=0
step: n=7 name=Document state=pending tasks=0
step: n=8 name=Integrate state=pending tasks=1
step: n=9 name=Close-out state=pending tasks=0
task: id=T1 step=3 state=done desc=Lock the plan note=landed 9:00 AM
task: id=T2 step=3 state=done desc=Lock the matrix note=landed 9:10 AM
task: id=T3 step=4 state=done desc=The register note=landed 10:00 AM
task: id=T13 step=4 state=done desc=The stragglers note=landed 11:00 AM
task: id=T4 step=4 state=done desc=The release card note=landed 12:00 PM
task: id=T40 step=4 state=running desc=a check rewrite never passes unjudged note=running
task: id=T7 step=4 state=failed desc=the width pins note=red
task: id=T8 step=4 state=held desc=the skill texts note=held on D3
task: id=T41 step=5 state=pending desc=the whole regression at the build head note=-
task: id=T47 step=8 state=pending desc=merge into main note=waits on the release card
clock.now: 2:40 PM — when this sheet was printed · unit: local time · source: the verb'"'"'s clock
clock.approved: 8:20 AM — when you approved the plan at Step 3 · unit: local time · source: the plan'"'"'s approved-by: line
clock.forecast: 10 h 30 min, ends 6:50 PM — how long the plan said the run would take, and when that ends · unit: wall-clock hours, local time · source: the plan'"'"'s forecast: plus clock.approved
clock.elapsed: 6 h 20 min — wall clock since the approval · unit: h min · source: clock.now less clock.approved
clock.elapsed-share: 60% — the forecast used so far · unit: % of clock.forecast · source: clock.elapsed over the forecast'"'"'s hours
work.planned: 10 tasks, 520 min — the tasks in the plan at the approval · unit: count, sized minutes · source: the Tasks rows whose own line names no joining after the approval
work.added: 2 tasks, 60 min — the tasks added since the approval · unit: count, sized minutes · source: the Tasks rows whose own line says task-add added them after the approval
work.dropped: 2 tasks, 60 min — the tasks dropped · unit: count, sized minutes · source: the rows with status dropped
work.landed: 5 tasks, 190 of 520 min, 37% — the tasks landed · unit: count, sized minutes of the live work'"'"'s sized minutes, % of them · source: the rows with status landed
work.left: 5 tasks, 330 min — the tasks neither landed nor dropped · unit: count, sized minutes · source: the remaining rows
work.width: median 2, peak 3 — how many tasks ran at once, launch to landing or to now · unit: tasks, the median over the minutes any task ran and the peak · source: the rosters'"'"' launches and the landing record'"'"'s landed: lines
work.task-time: 5 tasks, 228 min against 190 sized min — the landed tasks'"'"' own time, launch to landing, against their size · unit: minutes against sized minutes · source: the rosters'"'"' first launch of each row and the landing record'"'"'s landed: lines
pace.time-used: 60% — the share of the forecast time used, as clock.elapsed-share · unit: % · source: clock.elapsed over the forecast'"'"'s hours
pace.work-landed: 37% — the share of the live work landed, as in work.landed · unit: % of the live work'"'"'s sized minutes · source: work.landed
close.chain: 4/40 → 5/41 → 8/47, 300 min — the longest run of tasks left that must go one after another · unit: task labels, sized minutes · source: the open rows'"'"' reads
close.predicted: 8:40 PM — when the run is expected to end · unit: local time · basis: clock.now plus close.chain scaled by the 5 landed tasks'"'"' own time over their size, 228 min over 190 sized min
close.unscaled: 7:40 PM — the same, with no scaling · unit: local time · source: clock.now plus close.chain'"'"'s sized minutes
close.waits-on-you: yes: decide:D3 and approve:release — whether the prediction assumes you answer now · unit: yes or no, and which asks · source: the open asks that hold a task on close.chain, the release or the merge
tests.suites-run: 12: 11 green, 1 red — the suites run this wave, each by its last run · unit: count run: count green, count red · source: the landing record'"'"'s verdicts
tests.suites-total: 120 — the suites in the project · unit: count · source: the project'"'"'s tests/*.test.sh, every suite tests/run.sh runs
tests.whole-run: not run yet — the whole regression · unit: not run (and why), or green or red at a commit · source: the plan'"'"'s regression: and its proof
reviews: 0 passed, 0 failed, 1 running — the reviews, each question and scope once by its latest result · unit: count passed, failed, running · source: the review proofs and the review tasks in flight
findings.open: 0 — the review findings not yet closed · unit: count · source: the review records
waste.dropped: 2 tasks, 60 min — the tasks dropped, as work.dropped · unit: count, sized minutes · source: the rows with status dropped
waste.runs-discarded: 0 of 25 — the suite runs thrown away · unit: count of all suite runs · source: the landing record and the gate
waste.ready-unstarted: 0 min — the minutes a ready task sat while the machine had room · unit: minutes · source: the fill record
waste.waiting-on-you: 60 min: decide:D3 — the minutes a task waited on an ask, overlaps counted once · unit: minutes, and which asks · source: the register'"'"'s opened and closed times
goal: name=owed status=not measured measure=the user says what they owe — not measured
review: question=evidence scope=whole result=running at=- open-findings=0 record=-'
# Each ask line ends on the field the register derives last: whom or what it waits on.
SC_ASKS='ask: key=decide:D3 holds=4/8 title=D3 · waive or fix raised=1:00 PM blocks=yes waits=user
ask: key=approve:release holds=8/47 title=approval: release raised=1:05 PM blocks=yes waits=user'
SC_OWED="$SC_BASE
$SC_ASKS"
SC_CLEAN="$SC_BASE"

# The seven lines. Some open on a lower-case word, as a model writes them, so the card's capitals are the renderer's.
SC_J_OWED='purpose: the run lets the user see what they owe; on course, 0 of 1 goals met.
call: rule on D3: the skill texts and the merge wait on it.
grade: B
point: the last build task is running; once it lands, the regression runs.
point: 11 suites green and 1 red; the red one is the width pins.
ask decide:D3: D3 · waive the failed review or fix first; it holds 4/8 — recommend waive
ask approve:release: approve release 1.24.0; it holds 8/47 — recommend approve once the regression is green
close: depends on the regression passing first time.'
SC_J_CLEAN='purpose: the run lets the user see what they owe; on course.
call: Nothing is owed: let 4/40 land, then fix the width pins.
grade: B
point: The last build task is running; once it lands, the regression runs.
close: if the regression passes first time.'

SC_WANT_OWED='Sitrep · bionic 1.24.0 · wave 41 · Tuesday 2:40 PM

  Call to action
    • Rule on D3: the skill texts and the merge wait on it.

  Task list
    ✅ 0: Configure
    ✅ 1: Scope
    ✅ 2: Design
    ✅ 3: Plan
    ✅ 4/3–4/4: The register and the release card
    ✅ 4/13: The stragglers, landed 11:00 AM
    ⬜ 4/40: A check rewrite never passes unjudged, running
    ⬜ 4/7: The width pins, red
    ⬜ 4/8: The skill texts, held on D3
    ⬜ 5/41: The whole regression at the build head
    ⬜ 6: Review
    ⬜ 7: Document
    ⬜ 8/47: Merge into main, waits on the release card
    ⬜ 9: Close-out

  Metrics
    Completed    5 tasks · 190 of 520 sized min · 37%                   5 left · 330 min
    Pace         37% of the work in 60% of the forecast time            2 tasks added since approval
    Correctness  11 suites green, 1 red · 0 reviews passed, 0 failed, 1 running   0 findings open
    Waste        2 tasks dropped, 60 min · 0 of 25 runs discarded       60 min waiting on you
    Goals        owed not measured

  Assessment: B
    • Purpose: the run lets the user see what they owe; on course, 0 of 1 goals met.
    • The last build task is running; once it lands, the regression runs.
    • 11 suites green and 1 red; the red one is the width pins.

  Blocked on you
    • D3 · waive the failed review or fix first; it holds 4/8 — recommend waive
    • Approve release 1.24.0; it holds 8/47 — recommend approve once the regression is green

  Predicted close
    • 8:40 PM, against the forecast end of 6:50 PM.
    • The chain left is 4/40 → 5/41 → 8/47, 300 min, at the pace of the landed tasks.
    • Depends on the regression passing first time.'

# THE FLOCK-APP SHEET: the run whose 63-row card the mock-up replaced. 17 open tasks, 54 added since the approval,
# 14 asks that wait on landings (8 carried findings and 6 rulings given, one of them the refused waiver of the three
# failed reviews, which holds the merge), none waiting on the user.
SC_FLOCK_ASKS='ask: key=waive:review holds=8/26 title=the waiver of the three failed reviews raised=4:10 PM blocks=no waits=event T86 lands
ask: key=finding:F1 holds=nothing title=Finding S2 carried to T86 raised=4:12 PM blocks=no waits=event T86 lands
ask: key=finding:F2 holds=nothing title=Finding S2 carried to T86 raised=4:12 PM blocks=no waits=event T86 lands
ask: key=finding:F3 holds=nothing title=Finding S3 carried to T86 raised=4:12 PM blocks=no waits=event T86 lands
ask: key=finding:F4 holds=nothing title=Finding S3 carried to T86 raised=4:12 PM blocks=no waits=event T86 lands
ask: key=finding:F5 holds=nothing title=Finding S3 carried to T83 raised=4:13 PM blocks=no waits=event T83 lands
ask: key=finding:F6 holds=nothing title=Finding S3 carried to T83 raised=4:13 PM blocks=no waits=event T83 lands
ask: key=finding:F7 holds=nothing title=Finding S4 carried to T83 raised=4:13 PM blocks=no waits=event T83 lands
ask: key=finding:F8 holds=nothing title=Finding S4 carried to T83 raised=4:13 PM blocks=no waits=event T83 lands
ask: key=waive-row:AC-3.2 holds=nothing title=row waiver AC-3.2 raised=5:01 PM blocks=no waits=event T83 lands
ask: key=waive-row:AC-4.1 holds=nothing title=row waiver AC-4.1 raised=5:01 PM blocks=no waits=event T83 lands
ask: key=row:AC-5.2 holds=nothing title=matrix ruling AC-5.2 raised=5:02 PM blocks=no waits=event T86 lands
ask: key=row:AC-6.1 holds=nothing title=matrix ruling AC-6.1 raised=5:02 PM blocks=no waits=event T86 lands
ask: key=row:AC-7.3 holds=nothing title=matrix ruling AC-7.3 raised=5:02 PM blocks=no waits=event T86 lands'
SC_FLOCK='sheet/v1 — facts for the model; the user sees the card, never this sheet
run.release: -
run.name: wave-02-flock
run.wave: 2
run.now: Friday 10:49 PM
run.step: 5
run.project: flock-app
run.started: 4:30 PM Thursday
run.last-landing: T81 at 10:31 PM
step: n=0 name=Configure state=done tasks=0
step: n=1 name=Scope state=done tasks=0
step: n=2 name=Design state=done tasks=0
step: n=3 name=Plan state=done tasks=2
step: n=4 name=Implement state=running tasks=1
step: n=5 name=Verify state=running tasks=15
step: n=6 name=Review state=running tasks=5
step: n=7 name=Document state=pending tasks=1
step: n=8 name=Integrate state=pending tasks=1
step: n=9 name=Close-out state=pending tasks=1
task: id=T1 step=3 state=done desc=Lock the plan note=landed 4:50 PM Thursday
task: id=T2 step=3 state=done desc=Lock the matrix note=landed 5:05 PM Thursday
task: id=T28 step=5 state=done desc=The walk note=landed 9:10 AM
task: id=T40 step=5 state=done desc=proofs note=landed 11:20 AM
task: id=T52 step=5 state=done desc=floors note=landed 2:05 PM
task: id=T29 step=6 state=done desc=The critic reviews note=landed 3:30 PM
task: id=T66 step=5 state=done desc=baselines note=landed 6:40 PM
task: id=T73 step=6 state=done desc=the auditor reviews note=landed 8:15 PM
task: id=T81 step=5 state=done desc=three releases note=landed 10:31 PM
task: id=T83 step=4 state=running desc=The contradictions and sign-up labels note=building
task: id=T84 step=5 state=pending desc=Browser proofs of T82 and T83 on main note=waits on T83
task: id=T85 step=5 state=pending desc=The release to preview note=waits on T84
task: id=T12 step=5 state=pending desc=Your read of the landing note=waits on T85
task: id=T20 step=5 state=pending desc=Your read of the pages and studio note=waits on T85
task: id=T24 step=5 state=pending desc=Your walk of the door and signed-in screens note=waits on T85
task: id=T87 step=5 state=pending desc=The floor after the release note=waits on T85
task: id=T25 step=5 state=pending desc=The soak and your cold-client walk note=waits on T31
task: id=T88 step=5 state=pending desc=The phone proofs note=waits on T85
task: id=T89 step=5 state=pending desc=The accessibility floor note=waits on T85
task: id=T90 step=5 state=pending desc=The cold-cache baseline note=waits on T85
task: id=T86 step=6 state=pending desc=The reviews once more note=waits on T85
task: id=T93 step=6 state=pending desc=The adversarial review once more note=waits on T85
task: id=T94 step=6 state=pending desc=The evidence review once more note=waits on T85
task: id=T31 step=7 state=pending desc=ADRs amended, criteria restated note=waits on T86 and T87
task: id=T26 step=8 state=pending desc=The close merge to master note=waits on T25
task: id=T32 step=9 state=pending desc=Close-out and the continuation note=waits on T26
clock.now: 10:49 PM — when this sheet was printed · unit: local time · source: the verb'"'"'s clock
clock.approved: 4:34 PM Thursday — when you approved the plan at Step 3 · unit: local time · source: the plan'"'"'s approved-by: line
clock.forecast: 97 h, ends 5:34 PM Monday — how long the plan said the run would take, and when that ends · unit: wall-clock hours, local time · source: the plan'"'"'s forecast: plus clock.approved
clock.elapsed: 30 h 15 min — wall clock since the approval · unit: h min · source: clock.now less clock.approved
clock.elapsed-share: 31% — the forecast used so far · unit: % of clock.forecast · source: clock.elapsed over the forecast'"'"'s hours
work.planned: 24 tasks, 2820 min — the tasks in the plan at the approval · unit: count, sized minutes · source: the Tasks rows whose own line names no joining after the approval
work.added: 54 tasks, 4785 min — the tasks added since the approval · unit: count, sized minutes · source: the Tasks rows whose own line says task-add added them after the approval
work.dropped: 2 tasks, 390 min — the tasks dropped · unit: count, sized minutes · source: the rows with status dropped
work.landed: 59 tasks, 6310 of 7215 min, 87% — the tasks landed · unit: count, sized minutes of the live work'"'"'s sized minutes, % of them · source: the rows with status landed
work.left: 17 tasks, 905 min — the tasks neither landed nor dropped · unit: count, sized minutes · source: the remaining rows
work.width: median 2, peak 4 — how many tasks ran at once, launch to landing or to now · unit: tasks, the median over the minutes any task ran and the peak · source: the rosters'"'"' launches and the landing record'"'"'s landed: lines
work.task-time: 59 tasks, 5980 min against 6310 sized min — the landed tasks'"'"' own time, launch to landing, against their size · unit: minutes against sized minutes · source: the rosters'"'"' first launch of each row and the landing record'"'"'s landed: lines
pace.time-used: 31% — the share of the forecast time used, as clock.elapsed-share · unit: % · source: clock.elapsed over the forecast'"'"'s hours
pace.work-landed: 87% — the share of the live work landed, as in work.landed · unit: % of the live work'"'"'s sized minutes · source: work.landed
close.chain: 4/83 → 5/84 → 5/85 → 5/87 → 7/31 → 5/25 → 8/26, 545 min — the longest run of tasks left that must go one after another · unit: task labels, sized minutes · source: the open rows'"'"' reads
close.predicted: 6:13 AM tomorrow — when the run is expected to end · unit: local time · basis: clock.now plus close.chain scaled by the 59 landed tasks'"'"' own time over their size, 5980 min over 6310 sized min
close.unscaled: 6:40 AM tomorrow — the same, with no scaling · unit: local time · source: clock.now plus close.chain'"'"'s sized minutes
close.waits-on-you: no — whether the prediction assumes you answer now · unit: yes or no, and which asks · source: the open asks that hold a task on close.chain, the release or the merge
tests.suites-run: 4: 4 green, 0 red — the suites run this wave, each by its last run · unit: count run: count green, count red · source: the landing record'"'"'s verdicts
tests.suites-total: 212 — the suites in the project · unit: count · source: the project'"'"'s tests/*.test.sh, every suite tests/run.sh runs
tests.whole-run: green at 1a2b3c4d — the whole regression · unit: not run (and why), or green or red at a commit · source: the plan'"'"'s regression: and its proof
reviews: 4 passed, 2 failed, 0 running — the reviews, each question and scope once by its latest result · unit: count passed, failed, running · source: the review proofs and the review tasks in flight
findings.open: 8 — the review findings not yet closed · unit: count · source: the review records
waste.dropped: 2 tasks, 390 min — the tasks dropped, as work.dropped · unit: count, sized minutes · source: the rows with status dropped
waste.runs-discarded: 0 of 61 — the suite runs thrown away · unit: count of all suite runs · source: the landing record and the gate
waste.ready-unstarted: 0 min — the minutes a ready task sat while the machine had room · unit: minutes · source: the fill record
waste.waiting-on-you: 935 min: decide:D2 — the minutes a task waited on an ask, overlaps counted once · unit: minutes, and which asks · source: the register'"'"'s opened and closed times
goal: name=sign-up status=on course measure=2 of 3 criteria discharged — open: REQ-3
goal: name=reach status=on course measure=1 of 2 criteria discharged — open: REQ-2
goal: name=pages status=on course measure=3 of 5 criteria discharged — open: REQ-4, REQ-5
goal: name=studio status=on course measure=1 of 4 criteria discharged — open: REQ-6, REQ-7 and 1 more
'"$SC_FLOCK_ASKS"'
review: question=structure scope=whole result=fail at=4:10 PM open-findings=4 record=record/wave-02-flock/critic-structure.md'
SC_J_FLOCK='purpose: members sign up and reach each other on master, every page verified by eye. On course: nothing missed, every goal waiting on your reads and the final reviews.
call: Nothing tonight. The merge waits on T86, the re-review after the next release, not on you.
grade: B
point: The build is nearly done and far ahead of its clock; the 54 added tasks are yours, not slip.
point: One task is live; the proofs, release, reviews and floor are queued behind it and none needs you.
point: 4 suites green, 0 red; the 2 failed reviews are re-read at T86.
close: It holds if T83 lands in one pass, T86 passes, and you walk the soak when T25 is ready.'
SC_WANT_FLOCK='Sitrep · flock-app · wave 2 · Friday 10:49 PM

  Call to action
    • Nothing tonight. The merge waits on T86, the re-review after the next release, not on you.

  Task list
    ✅ 0: Configure
    ✅ 1: Scope
    ✅ 2: Design
    ✅ 3: Plan
    ⬜ 4/83: The contradictions and sign-up labels, building
    ✅ 5/28–5/81: The walk, proofs, floors, baselines and three releases
    ⬜ 5/84: Browser proofs of T82 and T83 on main, waits on T83
    ⬜ 5/85: The release to preview, waits on T84
    ⬜ 5/12: Your read of the landing, waits on T85
    ⬜ 5/20: Your read of the pages and studio, waits on T85
    ⬜ 5/24: Your walk of the door and signed-in screens, waits on T85
    ⬜ 5/87: The floor after the release, waits on T85
    ⬜ 5/25: The soak and your cold-client walk, waits on T31
    ⬜ 5/88: The phone proofs, waits on T85
    ⬜ 5/89: The accessibility floor, waits on T85
    ⬜ 5/90: The cold-cache baseline, waits on T85
    ✅ 6/29–6/73: The critic reviews and the auditor reviews
    ⬜ 6/86: The reviews once more, waits on T85
    ⬜ 6/93: The adversarial review once more, waits on T85
    ⬜ 6/94: The evidence review once more, waits on T85
    ⬜ 7/31: ADRs amended, criteria restated, waits on T86 and T87
    ⬜ 8/26: The close merge to master, waits on T25
    ⬜ 9/32: Close-out and the continuation, waits on T26

  Metrics
    Completed    59 tasks · 6310 of 7215 sized min · 87%               17 left · 905 min
    Pace         87% of the work in 31% of the forecast time           54 tasks added since approval
    Correctness  4 suites green, 0 red · 4 reviews passed, 2 failed, 0 running   8 findings open
    Waste        2 tasks dropped, 390 min · 0 of 61 runs discarded     935 min waiting on you
    Goals        sign-up on course, 2 of 3, REQ-3 open · reach on course, 1 of 2, REQ-2 open · pages
                 on course, 3 of 5, REQ-4, REQ-5 open · studio on course, 1 of 4, REQ-6, REQ-7 open
                 and 1 more

  Assessment: B
    • Purpose: members sign up and reach each other on master, every page verified by eye. On
      course: nothing missed, every goal waiting on your reads and the final reviews.
    • The build is nearly done and far ahead of its clock; the 54 added tasks are yours, not slip.
    • One task is live; the proofs, release, reviews and floor are queued behind it and none needs
      you.
    • 4 suites green, 0 red; the 2 failed reviews are re-read at T86.
    • 14 items wait on landings, not on you: 8 carried findings, 6 rulings given

  Blocked on you
    • None. The waiver of the three failed reviews waits on an event, T86 lands.

  Predicted close
    • 6:13 AM tomorrow, against the forecast end of 5:34 PM Monday.
    • The chain left is 4/83 → 5/84 → 5/85 → 5/87 → 7/31 → 5/25 → 8/26, 545 min, at the pace of the
      landed tasks.
    • It holds if T83 lands in one pass, T86 passes, and you walk the soak when T25 is ready.'

# A SAVED SHEET: one the verb saved for a delivered run at 10:51 PM on its last day, copied whole.
sc_w43() {  # -> the saved sheet of a delivered run, whole
  cat <<'W43'
sheet/v1 — facts for the model; the user sees the card, never this sheet
run.release: 1.26.0
run.name: wave-43-no-hand-hold
run.wave: 43
run.now: Friday 10:51 PM
run.step: 9
run.project: bionic
run.started: 6:55 AM 2026-10-22
run.last-landing: T21 at 6:13 PM 2026-10-22
step: n=0 name=Configure state=done tasks=0
step: n=1 name=Scope state=done tasks=0
step: n=2 name=Design state=done tasks=0
step: n=3 name=Plan state=done tasks=0
step: n=4 name=Implement state=done tasks=28
step: n=5 name=Verify state=done tasks=2
step: n=6 name=Review state=done tasks=2
step: n=7 name=Document state=done tasks=1
step: n=8 name=Integrate state=done tasks=1
step: n=9 name=Close-out state=done tasks=1
task: id=T1 step=4 state=done desc=The replay note=landed 10:23 AM 2026-10-22
task: id=T11 step=4 state=done desc=The close says less, the skill texts, and the entry's reviews rendered note=landed 10:47 AM 2026-10-22
task: id=T7 step=4 state=done desc=The tick never offers a held merge note=landed 10:49 AM 2026-10-22
task: id=T10 step=4 state=done desc=A suite declares its pins; the brief names them; the dead index goes note=landed 11:29 AM 2026-10-22
task: id=T2 step=4 state=done desc=The one runner at the release base note=landed 11:40 AM 2026-10-22 by hand
task: id=T5 step=4 state=done desc=One record for one plan, and the census note=landed 11:52 AM 2026-10-22
task: id=T12 step=4 state=done desc="After the release" is publish order note=landed 12:05 PM 2026-10-22
task: id=T13 step=4 state=done desc=The test cap compares with the base note=landed 12:07 PM 2026-10-22
task: id=T15 step=4 state=done desc=Theme 7 note=landed 12:45 PM 2026-10-22
task: id=T3 step=4 state=done desc=The declared list, and the closure deleted with its tests note=landed 12:53 PM 2026-10-22
task: id=T4 step=4 state=done desc=A born fix lands at step 8 and closes the review's ask note=landed 12:59 PM 2026-10-22
task: id=T24 step=4 state=done desc=The replay reads the entry, and its lint note=landed 1:22 PM 2026-10-22
task: id=T8 step=4 state=done desc=The verbs write their cells note=landed 1:45 PM 2026-10-22
task: id=T6 step=4 state=done desc=A hand landing records its suites, and the hand scan call tidied note=landed 1:52 PM 2026-10-22
task: id=T25 step=4 state=done desc=The dispatch text names pins, and one stale comment note=landed 2:03 PM 2026-10-22
task: id=T23 step=4 state=done desc=The release approval settles a stale approval note=landed 2:09 PM 2026-10-22
task: id=T14 step=4 state=done desc=Theme 7 note=landed 2:10 PM 2026-10-22
task: id=T26 step=4 state=done desc=The gate hands the origin record to the reader rule note=landed 2:16 PM 2026-10-22
task: id=T9 step=4 state=done desc=The four Patrol readers read the scale cell, and the tick names a held merge note=landed 2:23 PM 2026-10-22
task: id=T22 step=4 state=done desc=Theme 7 note=landed 2:43 PM 2026-10-22
task: id=T16 step=5 state=done desc=The walk and the matrix note=landed 3:26 PM 2026-10-22
task: id=T17 step=5 state=done desc=The regression, once after the build note=landed 3:26 PM 2026-10-22
task: id=T19 step=7 state=done desc=The release row note=landed 3:31 PM 2026-10-22
task: id=T18 step=6 state=done desc=The critic's review of the whole note=landed 3:34 PM 2026-10-22
task: id=T28 step=4 state=done desc=A review row keeps the records its brief names note=landed 3:45 PM 2026-10-22
task: id=T29 step=4 state=done desc=The door-card mutant parses after the stale settle note=landed 3:51 PM 2026-10-22
task: id=T27 step=4 state=done desc=The replay logs its own part note=landed 4:00 PM 2026-10-22
task: id=T34 step=4 state=done desc=Blocked on you lists only what blocks you note=landed 4:23 PM 2026-10-22
task: id=T31 step=4 state=done desc=close-out spells no old token note=landed 4:35 PM 2026-10-22
task: id=T32 step=4 state=done desc=The rehearsal reads the new close basis note=landed 4:36 PM 2026-10-22
task: id=T33 step=4 state=done desc=The reviews part reaches main note=landed 5:19 PM 2026-10-22
task: id=T36 step=4 state=done desc=A ruling ask holds its row note=landed 5:23 PM 2026-10-22
task: id=T20 step=8 state=done desc=Open the pull request from wave/43-no-hand-hold to main on the release approval card's word note=landed 6:12 PM 2026-10-22
task: id=T21 step=9 state=done desc=Close-out note=landed 6:13 PM 2026-10-22
task: id=T35 step=6 state=pending desc=The critic reads the two landings that owe cover note=waits on head: the head past the review proof at 8d99ee4ab90d is not known here
clock.now: 10:51 PM — when this sheet was printed · unit: local time · source: the verb's clock
clock.approved: 9:38 AM 2026-10-22 — when you approved the plan at Step 3 · unit: local time · source: the plan's approved-by: line
clock.forecast: 12 h, ends 9:38 PM 2026-10-22 — how long the plan said the run would take, and when that ends · unit: wall-clock hours, local time · source: the plan's forecast: plus clock.approved
clock.elapsed: 37 h 13 min — wall clock since the approval · unit: h min · source: clock.now less clock.approved
clock.elapsed-share: 310% — the forecast used so far · unit: % of clock.forecast · source: clock.elapsed over the forecast's hours
work.planned: 25 tasks, 1420 min — the tasks in the plan at the approval · unit: count, sized minutes · source: the Tasks rows whose own line names no joining after the approval
work.added: 11 tasks, 375 min — the tasks added since the approval · unit: count, sized minutes · source: the Tasks rows whose own line says task-add added them, or a split made them, after the approval
work.dropped: 1 task, 15 min — the tasks dropped · unit: count, sized minutes · source: the rows with status dropped
work.landed: 34 tasks, 1740 of 1780 min, 98% — the tasks landed · unit: count, sized minutes of the live work's sized minutes, % of them · source: the rows with status landed
work.left: 1 task, 40 min — the tasks neither landed nor dropped · unit: count, sized minutes · source: the remaining rows
work.width: not measured: no launch of this plan on the rosters — how many tasks ran at once, launch to landing or to now · unit: tasks, the median over the minutes any task ran and the peak · source: the rosters' launches and the landing record's landed: lines
work.task-time: 0 tasks: none of the 34 landed has both a launch and a landing on record — the landed tasks' own time, launch to landing, against their size · unit: minutes against sized minutes · source: the rosters' first launch of each row and the landing record's landed: lines
pace.time-used: 310% — the share of the forecast time used, as clock.elapsed-share · unit: % · source: clock.elapsed over the forecast's hours
pace.work-landed: 98% — the share of the live work landed, as in work.landed · unit: % of the live work's sized minutes · source: work.landed
close.chain: 6/35, 40 min — the longest run of tasks left that must go one after another · unit: task labels, sized minutes · source: the open rows' reads, a verify row ahead of the integrate row
close.predicted: 6:13 PM 2026-10-22 — when the run is expected to end · unit: local time · basis: delivered at 6:13 PM 2026-10-22; nothing is left to forecast
close.unscaled: - — the same, with no scaling · unit: local time · source: clock.now plus the same spans, every task at its sized minutes
close.waits-on-you: no — whether the prediction assumes you answer now · unit: yes or no, and which asks · source: the open asks that hold a task on close.chain or the longest-running task, the release or the merge
tests.suites-run: 30: 30 green, 0 red — the suites run this wave, each by its last run · unit: count run: count green, count red · source: the landing record's verdicts
tests.suites-total: 126 — the suites in the project · unit: count · source: the project's tests/*.test.sh, every suite tests/run.sh runs
tests.whole-run: green at 29cfb97b — the whole regression · unit: not run (and why), or green or red at a commit · source: the plan's regression: and its proof
reviews: 2 passed, 4 failed, 0 running — the reviews, each question and scope once by its latest result · unit: count passed, failed, running · source: the review proofs and the review tasks in flight
findings.open: 4 — the review findings not yet closed · unit: count · source: the review records
waste.dropped: 1 task, 15 min — the tasks dropped, as work.dropped · unit: count, sized minutes · source: the rows with status dropped
waste.runs-discarded: 3 of 100 — the suite runs thrown away · unit: count of all suite runs · source: the landing record and the gate
waste.ready-unstarted: 0 min — the minutes a ready task sat while the machine had room · unit: minutes · source: the fill record
waste.waiting-on-you: 328 min: approve:step0, approve:step1, approve:step2, approve:step3, waive:evidence, waive:adversarial — the minutes a task waited on an ask, overlaps counted once · unit: minutes, and which asks · source: the register's opened and closed times
goal: name=replay status=met measure=4 of 4 criteria discharged — none open
goal: name=judge status=met measure=3 of 3 criteria discharged — none open
goal: name=verbs status=met measure=2 of 2 criteria discharged — none open
ask: key=finding:record:wave-43-no-hand-hold:critic-evidence.md:3 holds=nothing title=Finding S2 needs a ruling raised=3:34 PM 2026-10-22 blocks=no
ask: key=finding:record:wave-43-no-hand-hold:critic-evidence.md:4 holds=nothing title=Finding S2 needs a ruling raised=3:34 PM 2026-10-22 blocks=no
ask: key=finding:record:wave-43-no-hand-hold:critic-adversarial.md:1 holds=nothing title=Finding S2 needs a ruling raised=3:34 PM 2026-10-22 blocks=no
ask: key=finding:record:wave-43-no-hand-hold:critic-adversarial.md:3 holds=nothing title=Finding S2 needs a ruling raised=3:34 PM 2026-10-22 blocks=no
review: question=evidence scope=whole result=fail at=3:34 PM 2026-10-22 open-findings=2 record=record/wave-43-no-hand-hold/critic-evidence.md
review: question=adversarial scope=whole result=fail at=3:34 PM 2026-10-22 open-findings=2 record=record/wave-43-no-hand-hold/critic-adversarial.md
review: question=structure scope=whole result=flag at=3:34 PM 2026-10-22 open-findings=0 record=record/wave-43-no-hand-hold/critic-structure.md
review: question=evidence scope=piece result=fail at=5:00 PM 2026-10-22 open-findings=0 record=record/wave-43-no-hand-hold/critic-evidence-2.md
review: question=adversarial scope=piece result=fail at=5:00 PM 2026-10-22 open-findings=0 record=record/wave-43-no-hand-hold/critic-adversarial-2.md
review: question=structure scope=piece result=flag at=5:00 PM 2026-10-22 open-findings=0 record=record/wave-43-no-hand-hold/critic-structure-2.md
W43
}
SC_W43="$(sc_w43)"
SC_J_W43='purpose: the run lands the close replay; all 3 goals met.
call: Say whether the four carried findings may close; the run is delivered.
grade: B
point: 34 tasks landed and 1 is left, the critic read of the two landings.
close: It holds once 6/35 has a head to read.'

# sc_card <sheet> <judgment> -> SC_RC, SC_OUT, SC_ERR of `card.sh sitrep <sheet file>` with the judgment on stdin
sc_card() {
  printf '%s\n' "$1" > "$TMPROOT/sheet"
  SC_RC=0
  printf '%s\n' "$2" | bash "$CARD_SH" sitrep "$TMPROOT/sheet" > "$TMPROOT/sc.out" 2> "$TMPROOT/sc.err" || SC_RC=$?
  SC_OUT="$(cat "$TMPROOT/sc.out")"; SC_ERR="$(cat "$TMPROOT/sc.err")"
}
# sc_check <sheet> <card text> -> SC_RC, SC_OUT, SC_ERR of `card.sh sitrep-check <sheet file>` with the card on stdin
sc_check() {
  printf '%s\n' "$1" > "$TMPROOT/sheet"
  SC_RC=0
  printf '%s\n' "$2" | bash "$CARD_SH" sitrep-check "$TMPROOT/sheet" > "$TMPROOT/sc.out" 2> "$TMPROOT/sc.err" || SC_RC=$?
  SC_OUT="$(cat "$TMPROOT/sc.out")"; SC_ERR="$(cat "$TMPROOT/sc.err")"
}
sc_under() {  # <card> <section label> -> the lines under it, up to the blank line that ends it
  printf '%s\n' "$1" | awk -v h="  $2" '$0 == h || (h == "  Assessment" && index($0, "  Assessment: ") == 1) { f = 1; next } f && $0 == "" { exit } f { print }'
}
sc_rows() {  # <card> <section label> -> the rows under it, a folded row joined onto one line
  sc_under "$1" "$2" | awk '/^    [^ ]/ { if (r != "") print r; r = $0; next } /^     / { sub(/^ +/, ""); r = r " " $0 } END { if (r != "") print r }'
}
sc_labels() { printf '%s\n' "$1" | sed -n 's/^  \([^ ].*\)$/\1/p' | paste -sd'|' -; }   # <card> -> its section labels
sc_nrows() { printf '%s\n' "$1" | /usr/bin/grep -c '^    [^ ]'; }   # <card> -> how many rows it draws, a folded row once
sc_wide() {  # <text> -> each line wider than BIONIC_LINE_WIDTH columns, as `<columns>: <line>`
  local l
  while IFS= read -r l; do
    _bionic_cols_into "$l"
    [ "$BIONIC_COLS" -le "$BIONIC_LINE_WIDTH" ] || printf '%s: %s\n' "$BIONIC_COLS" "$l"
  done <<< "$1"
}
sc_judge_without() { printf '%s\n' "$1" | /usr/bin/grep -v -F -- "$2"; }   # <judgment> <text> -> the judgment, the lines holding it cut
sc_row() { printf '%s\n' "$1" | /usr/bin/grep -F -- "$2"; }   # <card> <text> -> the card's lines holding the text
sc_why() { printf '%s\n' "$SC_ERR" | /usr/bin/grep -F 'refused:' | /usr/bin/grep -F -- "$1" | /usr/bin/grep -cF -- "${2:-$1}"; }   # <text> [<text>] -> refusal lines holding both

# ============================================================
section "§MOCKUP: the flock-app-shaped sheet and a seven-line judgment draw the approved mock-up's shape, under 40 rows"
# ============================================================
# FIXTURE FIDELITY: the sheet is in the verb's own grammar, its ask lines ending on the waits field; its numbers agree
# with each other (59 landed and 17 left of 76 live tasks, 6310 and 905 of 7215 sized minutes).
# fails-when: the judgment is refused, a register item is drawn as a row, the merge reads blocked, Blocked on you
# names no event, the card is 40 rows or more, or any drawn line differs from the approved shape.
expect_eq "MK0 precondition: the flock sheet holds 17 open tasks, 14 asks waiting on events, the refused waiver holding the merge and 54 added tasks" \
  "17|14|1|1" \
  "$(printf '%s\n' "$SC_FLOCK" | /usr/bin/grep '^task: ' | /usr/bin/grep -vc ' state=done ')|$(printf '%s\n' "$SC_FLOCK" | /usr/bin/grep '^ask: ' | /usr/bin/grep -c ' waits=event ')|$(printf '%s\n' "$SC_FLOCK" | /usr/bin/grep -c '^ask: key=waive:review holds=8/26 .* blocks=no waits=event T86 lands$')|$(printf '%s\n' "$SC_FLOCK" | /usr/bin/grep -c '^work.added: 54 tasks')"
expect_eq "MK0b precondition: the judgment is seven lines, purpose first, no task: or metric: line" "7|purpose|0" \
  "$(printf '%s\n' "$SC_J_FLOCK" | /usr/bin/grep -c .)|$(printf '%s\n' "$SC_J_FLOCK" | head -1 | cut -d: -f1)|$(printf '%s\n' "$SC_J_FLOCK" | /usr/bin/grep -cE '^(task|metric):')"
sc_card "$SC_FLOCK" "$SC_J_FLOCK"
SC_FLOCK_CARD="$SC_OUT"
expect_eq "MK1 the flock card renders (exit 0, nothing on stderr)" "0|" "$SC_RC|$SC_ERR"
expect_eq "MK2 …line for line the approved shape: the drawn facts and the seven lines" "$SC_WANT_FLOCK" "$SC_FLOCK_CARD"
expect_eq "MK3 …the head and the six sections in order" \
  "Call to action|Task list|Metrics|Assessment: B|Blocked on you|Predicted close" "$(sc_labels "$SC_FLOCK_CARD")"
expect_eq "MK4 …one call row, five Metrics rows, the purpose, three points and one counted line, one Blocked row, three close rows" \
  "1|5|5|1|3" \
  "$(sc_rows "$SC_FLOCK_CARD" "Call to action" | /usr/bin/grep -c .)|$(sc_rows "$SC_FLOCK_CARD" "Metrics" | /usr/bin/grep -c .)|$(sc_rows "$SC_FLOCK_CARD" "Assessment" | /usr/bin/grep -c .)|$(sc_rows "$SC_FLOCK_CARD" "Blocked on you" | /usr/bin/grep -c .)|$(sc_rows "$SC_FLOCK_CARD" "Predicted close" | /usr/bin/grep -c .)"
expect_eq "MK5 …under 40 rows (MK2 read the same card)" "yes" "$([ "$(sc_nrows "$SC_FLOCK_CARD")" -lt 40 ] && echo yes)"
SC_FLOCK_TITLES="$(printf '%s\n' "$SC_FLOCK_ASKS" | sed -n 's/^ask: .* title=\(.*\) raised=.*$/\1/p' | sort -u)"
expect_eq "MK6 precondition: the extractor reads the 14 asks' titles (10 distinct)" "10" "$(printf '%s\n' "$SC_FLOCK_TITLES" | /usr/bin/grep -c .)"
SC_HIT=""
while IFS= read -r t; do [ -z "$t" ] || ! printf '%s\n' "$SC_FLOCK_CARD" | /usr/bin/grep -qiF -- "$t" || SC_HIT="$SC_HIT|$t"; done <<< "$(printf '%s\n' "$SC_FLOCK_TITLES" | /usr/bin/grep -v 'waiver of the three')"
expect_empty "MK6b …and no register item that waits on an event is drawn as a row of its own" "$SC_HIT"
expect_eq "MK7 the merge is not blocked: Blocked on you is None, naming the event the waiver waits on" \
  "    • None. The waiver of the three failed reviews waits on an event, T86 lands." "$(sc_rows "$SC_FLOCK_CARD" "Blocked on you")"

# ============================================================
section "§SECTIONS: seven sections in order, every row bulleted, iconed or a Metrics row, each model row capitalized"
# ============================================================
# fails-when: a section is missing or out of order, a bare row, or a row the model opened lower case prints so.
sc_card "$SC_OWED" "$SC_J_OWED"
expect_eq "SE1 the owed fixture renders (exit 0, nothing on stderr)" "0|" "$SC_RC|$SC_ERR"
expect_eq "SE2 …the whole card: the drawn facts and the judgment under the renderer's head, labels, bullets and icons" "$SC_WANT_OWED" "$SC_OUT"
expect_eq "SE3 the head, then the six labelled sections in their order" \
  "Call to action|Task list|Metrics|Assessment: B|Blocked on you|Predicted close" "$(sc_labels "$SC_OUT")"
expect_eq "SE4 every row outside the Metrics opens on a bullet or an icon (SE3 read the labels from the same card)" "" \
  "$(printf '%s\n' "$SC_OUT" | awk '/^  Metrics$/ { m = 1; next } /^  [^ ]/ { m = 0 } !m && NR > 1 && /^    [^ ]/ && !/^    (• |✅ |⬜ )/')"
expect_eq "SE4b …and every Metrics row opens on its label" "Completed|Pace|Correctness|Waste|Goals" \
  "$(sc_rows "$SC_OUT" "Metrics" | awk '{ print $1 }' | paste -sd'|' -)"
expect_eq "SE5 a row the judgment opened on a lower-case letter prints capitalized: the call, a point, an ask, a close" \
  "    • Rule on D3: the skill texts and the merge wait on it.|    • The last build task is running; once it lands, the regression runs.|    • Approve release 1.24.0; it holds 8/47 — recommend approve once the regression is green|    • Depends on the regression passing first time." \
  "$(sc_row "$SC_OUT" 'Rule on D3')|$(sc_row "$SC_OUT" 'last build task')|$(sc_row "$SC_OUT" 'release 1.24.0;')|$(sc_row "$SC_OUT" 'regression passing')"
expect_eq "SE5b …and a row opening on a capital or a digit prints as written (SE5 read the same card)" \
  "    • D3 · waive the failed review or fix first; it holds 4/8 — recommend waive|    • 11 suites green and 1 red; the red one is the width pins." \
  "$(sc_row "$SC_OUT" 'D3 · waive')|$(sc_row "$SC_OUT" '11 suites green and')"

# ============================================================
section "§DRAWN: every step and task row is drawn from the sheet's own records, and a task: or metric: line is refused by name"
# ============================================================
# The Task list is the sheet's: a done step with no open task is its step row; an open task is a row of its own, its
# description and its note; the done tasks of an open step fold into ranges that hold no open task's number.
# fails-when: a step or an open task has no row, a row's words differ from the sheet's desc and note, a range spans an
# open task, a step called done that holds an open task hides it, or a task: or metric: line draws a card.
sc_card "$SC_W43" "$SC_J_W43"
expect_eq "DR1 the saved wave-43 sheet and a seven-line judgment render (exit 0, nothing on stderr)" "0|" "$SC_RC|$SC_ERR"
expect_eq "DR1b …its Task list: each done step its row, the review step holding its open task drawn as its tasks" \
  "    ✅ 0: Configure|    ✅ 1: Scope|    ✅ 2: Design|    ✅ 3: Plan|    ✅ 4: Implement|    ✅ 5: Verify|    ✅ 6/18: The critic's review of the whole, landed 3:34 PM 2026-10-22|    ⬜ 6/35: The critic reads the two landings that owe cover, waits on head: the head past the review proof at 8d99ee4ab90d is not known here|    ✅ 7: Document|    ✅ 8: Integrate|    ✅ 9: Close-out" \
  "$(sc_rows "$SC_OUT" "Task list" | paste -sd'|' -)"
expect_empty "DR1c …the long open row folded under its text, every line within the width (DR1b read the same card)" "$(sc_wide "$SC_OUT")"
sc_open_rows() {  # <sheet> -> the row each open task should draw, `<step>/<n>: <desc>[, <note>]`, from the sheet's task: lines
  printf '%s\n' "$1" | awk 'index($0, "task: ") == 1 && $0 !~ / state=done / {
    id = $0; sub(/^task: id=T?/, "", id); sub(/ .*$/, "", id)
    st = $0; sub(/^.* step=/, "", st); sub(/ .*$/, "", st)
    d = $0; sub(/^.* desc=/, "", d); sub(/ note=.*$/, "", d)
    n = $0; sub(/^.* note=/, "", n)
    print st "/" id ": " toupper(substr(d, 1, 1)) substr(d, 2) ((n == "-" || n == "") ? "" : ", " n) }'
}
expect_eq "DR2 precondition: the extractor reads the owed sheet's five open tasks" "5" "$(sc_open_rows "$SC_OWED" | /usr/bin/grep -c .)"
sc_card "$SC_OWED" "$SC_J_OWED"
SC_MISS=""
while IFS= read -r r; do [ "$(sc_rows "$SC_OUT" "Task list" | /usr/bin/grep -cxF -- "    ⬜ $r")" = 1 ] || SC_MISS="$SC_MISS|$r"; done <<< "$(sc_open_rows "$SC_OWED")"
expect_empty "DR2b every open task is one row, its words the sheet's desc and note, drawn as written there" "$SC_MISS"
expect_eq "DR3 the done tasks of the running step fold into ranges around its open tasks: 4/3 and 4/4, then 4/13 on its own, since 4/7 and 4/8 are open" \
  "    ✅ 4/3–4/4: The register and the release card|    ✅ 4/13: The stragglers, landed 11:00 AM" \
  "$(sc_rows "$SC_OUT" "Task list" | /usr/bin/grep -F '✅ 4/' | paste -sd'|' -)"
SC_DONE4="$(printf '%s\n' "$SC_OWED" | sed 's/^step: n=4 name=Implement state=running/step: n=4 name=Implement state=done/')"
sc_card "$SC_DONE4" "$SC_J_OWED"
expect_eq "DR4 a step the sheet calls done that holds open tasks draws them, never a done step row over them" "0|0|3" \
  "$SC_RC|$(sc_rows "$SC_OUT" "Task list" | /usr/bin/grep -c ' 4: ')|$(sc_rows "$SC_OUT" "Task list" | /usr/bin/grep -c '⬜ 4/')"
sc_card "$SC_OWED" "$SC_J_OWED
task: 4/40: a check rewrite never passes unjudged, running"
expect_eq "DR5 a judgment with a task: line refuses the card: exit 1, nothing printed" "1|" "$SC_RC|$SC_OUT"
expect_eq "DR5b …in one line naming the tag" "1" "$(sc_why 'tag the card does not know, task:')"
sc_card "$SC_OWED" "$SC_J_OWED
metric: Pace: 37% of the work landed in 60% of the forecast time."
expect_eq "DR6 a judgment with a metric: line refuses the card, naming the tag" "1||1" "$SC_RC|$SC_OUT|$(sc_why 'tag the card does not know, metric:')"

# ============================================================
section "§TABLE: the Metrics are five lines, every number a measured value of its own line, the pace comparison first"
# ============================================================
# fails-when: a Metrics row holds a number its own sheet lines do not, the five are not five or out of order, the Pace
# row opens on anything but the comparison, a row is prose, or the Goals row counts goals by status instead of stating
# each theme's criteria discharged and open REQs.
sc_card "$SC_OWED" "$SC_J_OWED"
SC_TABLE="$(sc_rows "$SC_OUT" "Metrics")"
expect_eq "TB1 five rows, Completed, Pace, Correctness, Waste, Goals, in that order" "Completed|Pace|Correctness|Waste|Goals" \
  "$(printf '%s\n' "$SC_TABLE" | awk '{ print $1 }' | paste -sd'|' -)"
sc_mvalues() {  # <sheet> <key>... -> each run of digits in those lines' measured values, one per line
  local s="$1"; shift
  for k in "$@"; do printf '%s\n' "$s" | sed -n "s/^$k: //p" | awk '{ i = index($0, " — "); print (i ? substr($0, 1, i - 1) : $0) }'; done \
    | /usr/bin/grep -oE '[0-9]+'
}
sc_unheld() {  # <sheet> <row> <key>... -> each number of the row its own lines do not hold
  local s="$1" r="$2" n; shift 2
  for n in $(printf '%s\n' "$r" | /usr/bin/grep -oE '[0-9]+'); do sc_mvalues "$s" "$@" | /usr/bin/grep -qx "$n" || printf '%s ' "$n"; done
}
expect_eq "TB2 precondition: the extractor reads the Completed lines' numbers" "5 190 520 37 5 330" "$(sc_mvalues "$SC_OWED" work.landed work.left | paste -sd' ' -)"
expect_eq "TB2b every number of every row is a measured value of the row's own lines" "||||" \
  "$(sc_unheld "$SC_OWED" "$(sc_row "$SC_TABLE" 'Completed')" work.landed work.left)|$(sc_unheld "$SC_OWED" "$(sc_row "$SC_TABLE" 'Pace')" pace.work-landed pace.time-used work.added)|$(sc_unheld "$SC_OWED" "$(sc_row "$SC_TABLE" 'Correctness')" tests.suites-run reviews findings.open)|$(sc_unheld "$SC_OWED" "$(sc_row "$SC_TABLE" 'Waste')" waste.dropped waste.runs-discarded waste.waiting-on-you)|$(sc_row "$SC_TABLE" 'Goals' | /usr/bin/grep -oE '[0-9]+' | paste -sd' ' - | sed 's/^0 1 1$//')"
expect_eq "TB3 the Pace row opens on the comparison: the work landed against the forecast time used" \
  "Pace         37% of the work in 60% of the forecast time" "$(sc_row "$SC_TABLE" 'Pace' | sed -E 's/^    //; s/^(Pace +.*[^ ]) {3,}.*$/\1/')"
expect_empty "TB4 no row is prose: no clause end inside the table (TB1 read the same rows)" \
  "$(printf '%s\n' "$SC_TABLE" | /usr/bin/grep -E '[.;!?]( |$)')"
sc_card "$SC_FLOCK" "$SC_J_FLOCK"
expect_eq "TB5 the table moves with the sheet: the flock sheet's Goals row states each theme's criteria discharged and open REQs" \
  "0|sign-up on course, 2 of 3, REQ-3 open · reach on course, 1 of 2, REQ-2 open · pages on course, 3 of 5, REQ-4, REQ-5 open · studio on course, 1 of 4, REQ-6, REQ-7 open and 1 more" \
  "$SC_RC|$(sc_row "$(sc_rows "$SC_OUT" "Metrics")" 'Goals' | sed 's/^    Goals *//')"
sc_card "$(printf '%s\n' "$SC_OWED" | sed 's/^findings.open: 0 /findings.open: 3 /')" "$SC_J_OWED"
expect_eq "TB6 a moved sheet value moves its cell: findings.open at 3 draws 3 findings open" "0|1" \
  "$SC_RC|$(sc_rows "$SC_OUT" "Metrics" | /usr/bin/grep -c '3 findings open$')"
SC_W43G="$(printf '%s\n' "$SC_W43" | awk '
  index($0, "goal: name=judge ") == 1 { print "goal: name=judge status=on course measure=1 of 2 criteria discharged — open: REQ-4"; next }
  index($0, "goal: name=verbs ") == 1 { print "goal: name=verbs status=on course measure=2 of 5 criteria discharged, 1 waived — open: REQ-5, REQ-6 and 2 more"; next }
  { print }')"
sc_card "$SC_W43G" "$SC_J_W43"
SC_GOALROW="$(sc_row "$(sc_rows "$SC_OUT" "Metrics")" 'Goals' | sed 's/^    Goals *//')"
expect_eq "TB7 the wave-43 sheet's Goals row reads each theme in order: its standing, its k of n and the REQs it has open, no count by status" \
  "0|replay met, 4 of 4 · judge on course, 1 of 2, REQ-4 open · verbs on course, 2 of 5, REQ-5, REQ-6 open and 2 more" "$SC_RC|$SC_GOALROW"
sc_goal_entries() {  # <sheet> -> `<name> <status>, <k> of <n>` for each goal: line holding a count, one per line
  printf '%s\n' "$1" | awk 'index($0, "goal: name=") == 1 && match($0, / status=[a-z ]+ measure=[0-9]+ of [0-9]+ criteria/) {
    nm = substr($0, 12, RSTART - 12); r = substr($0, RSTART + 8, RLENGTH - 8); sub(/ measure=.*$/, "", r)
    m = substr($0, RSTART, RLENGTH); sub(/^.* measure=/, "", m); split(m, h, " "); print nm " " r ", " h[1] " of " h[3] }'
}
expect_eq "TB7a precondition: the extractor reads the wave-43 sheet's three themes with their standing" \
  "replay met, 4 of 4|judge on course, 1 of 2|verbs on course, 2 of 5" "$(sc_goal_entries "$SC_W43G" | paste -sd'|' -)"
SC_MISS=""
while IFS= read -r e; do printf '%s\n' "$SC_GOALROW" | /usr/bin/grep -qF -- "$e" || SC_MISS="$SC_MISS|$e"; done <<< "$(sc_goal_entries "$SC_W43G")"
expect_eq "TB7a each theme's standing word is drawn beside its count, as the sheet's status reads" "" "$SC_MISS"
expect_empty "TB7a2 …and no status-count phrase (a moved status moves no count)" "$(printf '%s\n' "$SC_GOALROW" | /usr/bin/grep -E '[0-9]+ of [0-9]+ (met|on course)|[0-9] (met|on course)')"
SC_W43N="$(printf '%s\n' "$SC_W43G" | awk '{ print } index($0, "goal: name=verbs ") == 1 { print "goal: name=gate status=not met measure=1 of 3 criteria discharged — open: REQ-8" }')"
sc_card "$SC_W43N" "$(printf '%s\n' "$SC_J_W43" | sed 's/^purpose: .*/purpose: the run lands the close replay./')"
SC_GOALROWN="$(sc_row "$(sc_rows "$SC_OUT" "Metrics")" 'Goals' | sed 's/^    Goals *//')"
expect_eq "TB7d a theme at status not met draws its standing, a missed criterion open: gate not met, 1 of 3, REQ-8 open" \
  "0|1" "$SC_RC|$(printf '%s\n' "$SC_GOALROWN" | /usr/bin/grep -cF 'gate not met, 1 of 3, REQ-8 open')"
expect_eq "TB7d2 …after the three themes of TB7, in the sheet order" \
  "replay met, 4 of 4 · judge on course, 1 of 2, REQ-4 open · verbs on course, 2 of 5, REQ-5, REQ-6 open and 2 more · gate not met, 1 of 3, REQ-8 open" "$SC_GOALROWN"
SC_NM="$(printf '%s\n' "$SC_OWED" | sed 's/^goal: .*/goal: name=run status=not met measure=24 of 25 criteria discharged — open: REQ-9/')"
SC_OC="$(printf '%s\n' "$SC_OWED" | sed 's/^goal: .*/goal: name=run status=on course measure=24 of 25 criteria discharged — open: REQ-9/')"
sc_card "$SC_NM" "$SC_J_OWED"; SC_ROWNM="$(sc_row "$(sc_rows "$SC_OUT" "Metrics")" 'Goals' | sed 's/^    Goals *//')"; SC_RCNM="$SC_RC"
sc_card "$SC_OC" "$SC_J_OWED"; SC_ROWOC="$(sc_row "$(sc_rows "$SC_OUT" "Metrics")" 'Goals' | sed 's/^    Goals *//')"
expect_eq "TB7e a not met theme and an on course theme at the same k of n draw differently, each its own standing" \
  "0|0|run not met, 24 of 25, REQ-9 open|run on course, 24 of 25, REQ-9 open" "$SC_RCNM|$SC_RC|$SC_ROWNM|$SC_ROWOC"
sc_card "$SC_OWED" "$SC_J_OWED"
expect_eq "TB7b a theme with no k of n in its measure prints its status word" "0|owed not measured" \
  "$SC_RC|$(sc_row "$(sc_rows "$SC_OUT" "Metrics")" 'Goals' | sed 's/^    Goals *//')"
sc_card "$(printf '%s\n' "$SC_OWED" | /usr/bin/grep -v '^goal: ')" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^purpose: .*/purpose: the run lets the user see what they owe./')"
expect_eq "TB7c a sheet with no goal: line prints no goals on the row" "0|no goals" \
  "$SC_RC|$(sc_row "$(sc_rows "$SC_OUT" "Metrics")" 'Goals' | sed 's/^    Goals *//')"

# ============================================================
section "§COUNTED: the asks that wait on events are one counted line under the Assessment, by kind, never a row each"
# ============================================================
# fails-when: an ask that waits on an event is drawn as its own row, the count or a kind is wrong, the line leaves the
# Assessment, or a user-waiting ask is counted in it.
expect_eq "CO1 one line, the Assessment's last, counting the 14 asks by kind" \
  "    • 14 items wait on landings, not on you: 8 carried findings, 6 rulings given" \
  "$(sc_rows "$SC_FLOCK_CARD" "Assessment" | tail -1)"
expect_eq "CO1b …and nowhere else on the card (MK2 read the same card)" "1" "$(printf '%s\n' "$SC_FLOCK_CARD" | /usr/bin/grep -c 'wait on landings')"
SC_FLOCK_USER="$(printf '%s\n' "$SC_FLOCK" | sed 's/^\(ask: key=waive:review .*\) blocks=no waits=event T86 lands$/\1 blocks=yes waits=user/')"
expect_eq "CO2 precondition: the planted sheet has the waiver unanswered, waiting on the user and holding the merge" "1" \
  "$(printf '%s\n' "$SC_FLOCK_USER" | /usr/bin/grep -c '^ask: key=waive:review holds=8/26 .* blocks=yes waits=user$')"
sc_card "$SC_FLOCK_USER" "$(printf '%s\n' "$SC_J_FLOCK" | sed 's/^call: .*/call: Rule on the waiver of the three failed reviews; the merge waits on it./')"
expect_eq "CO2b the user-waiting ask leaves the count: 13 items, 8 carried findings and 5 rulings given" \
  "0|    • 13 items wait on landings, not on you: 8 carried findings, 5 rulings given" "$SC_RC|$(sc_rows "$SC_OUT" "Assessment" | tail -1)"
sc_card "$(printf '%s\n' "$SC_FLOCK" | sed 's/waits=event T83 lands$/waits=event review structure re-run/')" "$SC_J_FLOCK"
expect_eq "CO3 when some event is no landing the line says events" "0|    • 14 items wait on events, not on you: 8 carried findings, 6 rulings given" \
  "$SC_RC|$(sc_rows "$SC_OUT" "Assessment" | tail -1)"
sc_card "$SC_OWED" "$SC_J_OWED"
expect_eq "CO4 a sheet with no ask waiting on an event draws no counted line (SE2 holds the whole card)" "0|0" \
  "$SC_RC|$(printf '%s\n' "$SC_OUT" | /usr/bin/grep -c 'not on you:')"

# ============================================================
section "§TAGS: the seven tags draw; a foreign tag is refused by name, a missing one is named; a fourth point is kept"
# ============================================================
# fails-when: a judgment holding a tag outside the seven draws, a missing purpose, call, grade or close is refused
# without its name or draws, a fourth point is refused or dropped, or a judgment with no point is refused.
sc_card "$SC_OWED" "$SC_J_OWED"
expect_eq "TA1 control: purpose, call, grade, two points, two ask lines and a close draw (exit 0, nothing on stderr)" "0|" "$SC_RC|$SC_ERR"
for t in purpose call grade close; do
  sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | /usr/bin/grep -v "^$t: ")"
  expect_eq "TA2 a judgment with no $t: line refuses the card, naming it: exit 1, nothing printed" "1||1" "$SC_RC|$SC_OUT|$(sc_why "no $t: line")"
done
for t in 'verdict: fine' 'ask +: the operator owes a gate act outside the run' 'Bottom line: ship it'; do
  sc_card "$SC_OWED" "$SC_J_OWED
$t"
  expect_eq "TA3 \"${t%%:*}:\" is no tag of the seven: refused, naming it" "1||1" "$SC_RC|$SC_OUT|$(sc_why "tag the card does not know, ${t%%:*}:")"
done
sc_card "$SC_OWED" "$SC_J_OWED
grade: C"
expect_eq "TA4 two grades refuse the card" "1|1" "$SC_RC|$(sc_why 'grade: lines')"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^grade: B/grade: B+/')"
expect_eq "TA4b a grade outside A to F refuses it" "1|1" "$SC_RC|$(sc_why 'not one of A to F')"
expect_eq "TA4c each grade A to F draws" "0 0 0 0 0 0" \
  "$(for g in A B C D E F; do sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed "s/^grade: B/grade: $g/")"; printf '%s ' "$SC_RC"; done | sed 's/ $//')"
sc_card "$SC_OWED" "$SC_J_OWED
point: the release card is drafted.
point: the cull is done."
expect_eq "TA5 a fourth point is kept: the card draws (exit 0) all four, with a note on stderr" "0|4|1" \
  "$SC_RC|$(sc_rows "$SC_OUT" "Assessment" | /usr/bin/grep -vc 'Purpose:')|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -F 'sitrep note:' | /usr/bin/grep -cF 'three points')"
sc_card "$SC_OWED" "$(sc_judge_without "$SC_J_OWED" 'point: ')"
expect_eq "TA6 a judgment with no point draws: the purpose alone under the grade" "0|    • Purpose: the run lets the user see what they owe; on course, 0 of 1 goals met." \
  "$SC_RC|$(sc_rows "$SC_OUT" "Assessment")"

# ============================================================
section "§PURPOSE: the purpose is the Assessment's first row, required, and its numbers are checked"
# ============================================================
# fails-when: a card draws without a purpose, a purpose claiming a count the sheet lacks draws, or a true purpose is
# drawn anywhere but first under the grade.
sc_card "$SC_OWED" "$(sc_judge_without "$SC_J_OWED" 'purpose: ')"
expect_eq "PU1 a judgment with no purpose refuses the card, naming it: exit 1, nothing printed" "1||1" "$SC_RC|$SC_OUT|$(sc_why 'no purpose: line')"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^purpose: .*/purpose: the run lets the user see what they owe; on course, 3 of 4 goals met./')"
expect_eq "PU2 a purpose claiming 3 of 4 goals met over a sheet with 0 of 1 refuses the card, naming the number" "1||yes" \
  "$SC_RC|$SC_OUT|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -F 'purpose:' | /usr/bin/grep -qF 'says 3' && echo yes)"
sc_card "$SC_OWED" "$SC_J_OWED"
expect_eq "PU3 control: the true purpose draws first under the grade" "    • Purpose: the run lets the user see what they owe; on course, 0 of 1 goals met." \
  "$(sc_rows "$SC_OUT" "Assessment" | head -1)"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | awk '/^purpose: / { p = $0; next } { print } END { print p }')"
expect_eq "PU4 …wherever the line stands in the judgment" "0|    • Purpose: the run lets the user see what they owe; on course, 0 of 1 goals met." \
  "$SC_RC|$(sc_rows "$SC_OUT" "Assessment" | head -1)"

# ============================================================
section "§CALL: a call saying nothing is owed stands while every ask waits on an event, and refuses over a blocking one"
# ============================================================
# fails-when: the check refuses "nothing tonight" over the refused waiver, admits it over the unanswered one, or
# admits any plain nothing-owed wording while an ask that waits on the user blocks.
sc_card "$SC_FLOCK" "$SC_J_FLOCK"
expect_eq "CA1 over the refused waiver, waiting on T86, \"Nothing tonight\" stands (exit 0, nothing on stderr)" "0|" "$SC_RC|$SC_ERR"
sc_card "$SC_FLOCK_USER" "$SC_J_FLOCK"
expect_eq "CA2 over the same waiver unanswered, waiting on the user and holding the merge, it refuses the card" "1|" "$SC_RC|$SC_OUT"
expect_eq "CA2b …in one line naming the call rule and the blocking ask" "1" "$(sc_why 'nothing is owed' 'waive:review')"
for c in 'Nothing is owed: go for a walk.' 'Nothing for you to do; let 4/40 land.' 'No decision is needed now.' 'Nothing waits on you: let the build finish.' 'Nothing tonight.'; do
  sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | awk -v c="call: $c" '/^call: / { print c; next } { print }')"
  expect_eq "CA3 \"$c\" as the call with decide:D3 and approve:release blocking refuses the card, naming both" "1|1" \
    "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -F 'call:' | /usr/bin/grep -F 'decide:D3' | /usr/bin/grep -cF 'approve:release')"
done
sc_card "$SC_CLEAN" "$SC_J_CLEAN"
expect_eq "CA4 control: the same words over a sheet with no ask open draw (exit 0, nothing on stderr)" "0|" "$SC_RC|$SC_ERR"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^call: .*/call: Say whether the failed review may be waived; the merge waits on it./')"
expect_eq "CA5 a call naming the first blocking ask in words, no key, draws as written" "0|    • Say whether the failed review may be waived; the merge waits on it." \
  "$SC_RC|$(sc_rows "$SC_OUT" "Call to action")"

# ============================================================
section "§BLOCKS: Blocked on you lists the asks that wait on the user and hold something, else None naming the next event"
# ============================================================
# fails-when: an ask waiting on an event is drawn under Blocked on you, None is drawn while a user-waiting ask holds
# something, None names no event, an unanswered user-waiting ask is dropped or refused, an ask that holds nothing is
# drawn under Blocked on you, or the card infers blocking from what an ask holds.
expect_contains "BL1 over the refused waiver Blocked on you is None, naming T86, the event it waits on (MK7)" "T86 lands" "$(sc_rows "$SC_FLOCK_CARD" "Blocked on you")"
sc_card "$SC_FLOCK_USER" "$(printf '%s\n' "$SC_J_FLOCK" | sed 's/^call: .*/call: Rule on the waiver of the three failed reviews; the merge waits on it./')"
expect_eq "BL2 the unanswered waiver, no ask line written for it, is drawn under Blocked on you as the ask alone, with what it holds" \
  "0|    • The waiver of the three failed reviews · holds 8/26" "$SC_RC|$(sc_rows "$SC_OUT" "Blocked on you")"
sc_card "$SC_FLOCK_USER" "$(printf '%s\n' "$SC_J_FLOCK" | sed 's/^call: .*/call: Rule on the waiver of the three failed reviews; the merge waits on it./')
ask waive:review: the three failed reviews; it holds 8/26 — recommend refuse until T86"
expect_eq "BL3 …and with an ask line, the line as written" "0|    • The three failed reviews; it holds 8/26 — recommend refuse until T86" \
  "$SC_RC|$(sc_rows "$SC_OUT" "Blocked on you")"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^ask decide:D3: .*/ask decide:D3: D3 · waive the failed review or fix first — recommend waive/')"
expect_eq "BL4 an ask row that leaves out the task its ask holds draws, the holds added to it" \
  "0|    • D3 · waive the failed review or fix first — recommend waive · holds 4/8" "$SC_RC|$(sc_rows "$SC_OUT" "Blocked on you" | head -1)"
SC_UNHELD="$SC_BASE
ask: key=decide:goal:replay holds=nothing title=Goal missed: replay raised=1:00 PM blocks=no waits=user"
sc_card "$SC_UNHELD" "$SC_J_CLEAN"
expect_eq "BL5 a user-waiting ask that holds nothing is not under Blocked on you: None, and it is the Assessment's last row" \
  "0|    • None. The run waits on an event, 4/40 lands.|    • Open, blocking nothing: Goal missed: replay" \
  "$SC_RC|$(sc_rows "$SC_OUT" "Blocked on you")|$(sc_rows "$SC_OUT" "Assessment" | tail -1)"
sc_card "$(printf '%s\n' "$SC_UNHELD" | sed 's/ holds=nothing / holds=4\/8 /; s/ waits=user$//; s/ blocks=no$//')" "$SC_J_CLEAN"
expect_eq "BL6 the card reads the sheet's blocks field and never infers it from holds: an ask holding 4/8 with no blocks field blocks nothing" \
  "0|    • None. The run waits on an event, 4/40 lands." "$SC_RC|$(sc_rows "$SC_OUT" "Blocked on you")"
expect_eq "BL6b …and an ask line with no waits field waits on the user, so it is drawn, not counted (BL6 read the same card)" "1|0" \
  "$(sc_rows "$SC_OUT" "Assessment" | /usr/bin/grep -c 'Open, blocking nothing: Goal missed: replay · holds 4/8')|$(printf '%s\n' "$SC_OUT" | /usr/bin/grep -c 'not on you:')"
sc_card "$SC_FLOCK" "$SC_J_FLOCK
ask finding:F1: the finding is carried — recommend leave it"
expect_eq "BL7 an ask line on an ask that waits on an event is not drawn: the card draws (exit 0) with a note naming it" "0|0|1" \
  "$SC_RC|$(printf '%s\n' "$SC_OUT" | /usr/bin/grep -c 'the finding is carried')|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -F 'sitrep note:' | /usr/bin/grep -cF 'finding:F1')"
sc_card "$SC_OWED" "$SC_J_OWED
ask hold:merge: the merge is held — recommend release it"
expect_eq "BL8 an ask line naming a key the register lacks refuses the card, naming the key" "1||1" "$SC_RC|$SC_OUT|$(sc_why 'hold:merge' 'register lacks')"
sc_card "$SC_OWED" "$(sc_judge_without "$SC_J_OWED" 'ask approve:release:')"
expect_eq "BL9 a blocking ask the judgment leaves out is drawn as the ask alone, never refused" "0|    • Approval: release · holds 8/47" \
  "$SC_RC|$(sc_rows "$SC_OUT" "Blocked on you" | tail -1)"

# ============================================================
section "§BIND: every number in a judgment line is a sheet value, bound to the word beside it by word and by place"
# ============================================================
# A number in a judgment line is held by some measured value of the sheet; one set before a word the sheet sets
# beside its own numbers is that number; and the line whose word stands beside it holds it. Task labels, ids, clocks
# and versions are no counts and are never bound.
# fails-when: "1 green and 11 red" over "11 green, 1 red" draws, a number no sheet value holds draws, a goal count
# another status holds draws, two numbers traded between their words draw, a long point is refused for its length,
# or a label, id, clock or version is refused, or a theme's true count is refused, or one off by one or set beside another
# theme's name draws.
expect_eq "BI0 precondition: the owed sheet holds 11 green and 1 red on one line" "1" "$(printf '%s\n' "$SC_OWED" | /usr/bin/grep -c '^tests.suites-run: 12: 11 green, 1 red ')"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^point: 11 suites green and 1 red;/point: 1 green and 11 red;/')"
expect_eq "BI1 a point saying 1 green and 11 red refuses the card: exit 1, nothing printed" "1|" "$SC_RC|$SC_OUT"
expect_eq "BI1b …naming each number beside its word" "1|1" "$(sc_why 'says 1 beside "green"')|$(sc_why 'says 11 beside "red"')"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^point: 11 suites green and 1 red;/point: 11 green and 1 red;/')"
expect_eq "BI1c control: the same point in the sheet's order draws" "0|" "$SC_RC|$SC_ERR"
sc_card "$SC_OWED" "$SC_J_OWED
point: 57 suites ran today."
expect_eq "BI2 a number no sheet value holds refuses the card, naming it" "1|1" "$SC_RC|$(sc_why 'says 57')"
sc_card "$SC_OWED" "$SC_J_OWED
point: 60% of the work landed in 37% of the forecast time."
expect_eq "BI3 two sheet numbers traded between their words refuse the card, naming the one set beside the wrong word" "1|1" \
  "$SC_RC|$(sc_why 'says 60 beside')"
sc_card "$SC_OWED" "$SC_J_OWED
point: 37% of the work landed in 60% of the forecast time."
expect_eq "BI3b control: each in its place draws" "0|" "$SC_RC|$SC_ERR"
sc_card "$SC_FLOCK" "$(printf '%s\n' "$SC_J_FLOCK" | sed 's/the 54 added tasks/the 55 added tasks/')"
expect_eq "BI4 a point giving 55 added tasks over work.added 54 refuses the card" "1|1" "$SC_RC|$(sc_why 'says 55')"
sc_card "$SC_FLOCK" "$(printf '%s\n' "$SC_J_FLOCK" | sed 's/^point: 4 suites green, 0 red;/point: 0 suites green, 4 red;/')"
expect_eq "BI4b …and the flock point with its suite counts traded refuses it" "1|1" "$SC_RC|$(sc_why 'beside "green"')"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^call: .*/call: Let 4\/40 land by 4:10 PM; T47 merges 1.24.0 after the regression on 2026-10-06./')"
expect_eq "BI5 a task label, an id, a clock, a version and a date are no counts: the call draws" "0|" "$SC_RC|$SC_ERR"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^close: .*/close: depends on the regression passing first time, the 7 suites left green./')"
expect_eq "BI6 the close line is bound too: 7, a number no sheet value holds, refuses it" "1|1" "$SC_RC|$(sc_why 'close:' 'says 7')"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^ask decide:D3: D3 · /ask decide:D3: D3 · 9 suites wait; /')"
expect_eq "BI6b …and an ask line" "1|1" "$SC_RC|$(sc_why 'decide:D3' 'says 9')"
SC_LONGP="the build runs on, $(printf 'and on %.0s' $(seq 20))until the last task lands"
expect_eq "BI7 precondition: the planted point is over 160 columns" "yes" "$([ "$(bionic_cols "$SC_LONGP")" -gt 160 ] && echo yes)"
sc_card "$SC_OWED" "$SC_J_OWED
point: $SC_LONGP"
expect_eq "BI7b a long point folds under its text and the card draws: never refused for its length" "0|" "$SC_RC|$SC_ERR"
expect_empty "BI7c …every line within the width (BI7b drew it)" "$(sc_wide "$SC_OUT")"
expect_eq "BI7d …its words all kept" "• The build runs on, $(printf 'and on %.0s' $(seq 20))until the last task lands" \
  "$(sc_rows "$SC_OUT" "Assessment" | /usr/bin/grep -F 'build runs on' | sed 's/^    //')"
sc_card "$SC_OWED" "$SC_J_OWED
point: $(printf 'y%.0s' $(seq 120))"
expect_eq "BI7e a word wider than the card is broken and drawn, never refused" "0||" "$SC_RC|$SC_ERR|$(sc_wide "$SC_OUT")"
# A task the sheet holds open is never called landed; one it holds done is never called running.
sc_card "$SC_OWED" "$SC_J_OWED
point: 4/8 landed this morning."
expect_eq "BI8 a point calling the held 4/8 landed refuses the card, naming the label and its state" "1|1" "$SC_RC|$(sc_why '4/8' 'held')"
sc_card "$SC_OWED" "$SC_J_OWED
point: T13 is still running."
expect_eq "BI8b a point calling the done T13 running refuses it" "1|1" "$SC_RC|$(sc_why 'T13' 'done')"
sc_card "$SC_OWED" "$SC_J_OWED
point: 4/8 has not landed; T13 landed at noon."
expect_eq "BI8c control: an open task not landed and a done one landed draw" "0|" "$SC_RC|$SC_ERR"
# A theme's count is a sheet value bound to the theme's name and to the words criteria and discharged.
SC_ONE="$(printf '%s\n' "$SC_OWED" | sed 's/^goal: .*/goal: name=run status=on course measure=24 of 25 criteria discharged — open: REQ-3/')"
SC_J_ONE="$(printf '%s\n' "$SC_J_OWED" | sed 's/^purpose: .*/purpose: the run lets the user see what they owe; PURPOSE_COUNT./')"
sc_purpose() { printf '%s\n' "$SC_J_ONE" | sed "s/PURPOSE_COUNT/$1/"; }   # <text> -> the judgment with that text ending the purpose
sc_card "$SC_ONE" "$(sc_purpose '24 of 25 criteria discharged')"
expect_eq "BI9 the true per-theme count in the purpose draws: 24 of 25 criteria discharged over a theme measuring it" "0|" "$SC_RC|$SC_ERR"
expect_eq "BI9a …and the purpose row says it" "    • Purpose: the run lets the user see what they owe; 24 of 25 criteria discharged." \
  "$(sc_rows "$SC_OUT" "Assessment" | head -1)"
sc_card "$SC_ONE" "$(sc_purpose '25 of 25 criteria discharged')"
expect_eq "BI9b a count off by one is refused, naming the number: 25 of 25 over 24 of 25" "1||1" "$SC_RC|$SC_OUT|$(sc_why 'purpose:' 'says 25 of 25')"
sc_card "$SC_ONE" "$(sc_purpose '24 of 26 criteria discharged')"
expect_eq "BI9b2 …a total no theme holds is named too: 24 of 26" "1|1" "$SC_RC|$(sc_why 'purpose:' 'says 26')"
sc_card "$SC_FLOCK" "$(printf '%s\n' "$SC_J_FLOCK" | sed 's/^purpose: .*/purpose: members sign up and reach each other; reach has 1 of 2 criteria discharged, sign-up 2 of 3./')"
expect_eq "BI9c control: each theme's count beside its own name draws" "0|" "$SC_RC|$SC_ERR"
sc_card "$SC_FLOCK" "$(printf '%s\n' "$SC_J_FLOCK" | sed 's/^purpose: .*/purpose: members sign up and reach each other; reach has 2 of 3 criteria discharged./')"
expect_eq "BI9d a count bound to another theme's name is refused: reach holds 1 of 2, and 2 of 3 is sign-up's" "1||1" \
  "$SC_RC|$SC_OUT|$(sc_why 'purpose:' 'says 2 of 3')"
sc_card "$SC_OWED" "$(sc_purpose '24 of 25 criteria discharged')"
expect_eq "BI9e a sheet whose goal measures no count refuses the same purpose: nothing holds 24" "1|1" "$SC_RC|$(sc_why 'purpose:' 'says 24')"
sc_card "$SC_ONE" "$(sc_purpose '3 of 4 goals met')"
expect_eq "BI9f a goals count still comes from the status counts: 3 of 4 goals met over one goal on course is refused" "1|1" "$SC_RC|$(sc_why 'purpose:' 'says 3')"

# ============================================================
section "§SHAPE: the drawn card's own shape: width, a step row above its tasks, an open task twice or missing"
# ============================================================
# The renderer draws the card, and the same check holds any card handed to it whole (`sitrep-check`).
# fails-when: any planted fault prints, or the drawn card fails its own check.
sc_check "$SC_OWED" "$SC_WANT_OWED"
expect_eq "SH0 control: the approved card passes the check (exit 0, nothing said)" "0||" "$SC_RC|$SC_OUT|$SC_ERR"
sc_check "$SC_FLOCK" "$SC_WANT_FLOCK"
expect_eq "SH0b …and the flock card" "0||" "$SC_RC|$SC_OUT|$SC_ERR"
SC_PAD="    • $(printf 'x%.0s' $(seq 95))"
expect_eq "SH1 precondition: the planted line is 101 columns" "101" "$(bionic_cols "$SC_PAD")"
sc_check "$SC_OWED" "$(printf '%s\n' "$SC_WANT_OWED" | awk -v p="$SC_PAD" '{ print } /^  Call to action$/ { print p }')"
expect_eq "SH1b a 101-column row is refused, naming its width" "1|yes" "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qF '101 columns' && echo yes)"
sc_check "$SC_OWED" "$(printf '%s\n' "$SC_WANT_OWED" | awk '/^    ✅ 4\/3–4\/4/ { print "    ⬜ 4: Implement" } { print }')"
expect_eq "SH2 a step row above its own tasks is refused, naming the step" "1|yes" "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qF 'sits above its own task' && echo yes)"
sc_check "$SC_OWED" "$(printf '%s\n' "$SC_WANT_OWED" | awk '{ print } /^    ⬜ 4\/40:/ { print }')"
expect_eq "SH3 an open task on two rows is refused, naming it" "1|yes" "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qF '4/40' && echo yes)"
sc_check "$SC_OWED" "$(printf '%s\n' "$SC_WANT_OWED" | /usr/bin/grep -v '^    ⬜ 4/7:')"
expect_eq "SH4 an open task with no row is refused, naming it" "1|yes" "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qF '4/7' && echo yes)"
sc_check "$SC_OWED" "$(printf '%s\n' "$SC_WANT_OWED" | sed 's/^    • Rule on D3/    Rule on D3/')"
expect_eq "SH5 a row outside the Metrics with no bullet or icon is refused, quoting it" "1|yes" "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qF 'Rule on D3' && echo yes)"
sc_check "$SC_OWED" "$(printf '%s\n' "$SC_WANT_OWED" | awk '/^  Metrics$/ { m = 1 } m && /^$/ { m = 0; next } !m')"
expect_eq "SH6 a section missing is refused, naming it" "1|yes" "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qF 'Metrics' && echo yes)"
SC_WRAPPED="$(printf '%s\n' "$SC_WANT_OWED" | awk 'index($0, "    ⬜ 4/40: ") == 1 { i = index($0, ", running"); print substr($0, 1, i); print "       " substr($0, i + 2); next } { print }')"
expect_eq "SH7 precondition: the planted card has the 4/40 row on two lines" "1" "$(printf '%s\n' "$SC_WRAPPED" | /usr/bin/grep -cx '       running')"
sc_check "$SC_OWED" "$SC_WRAPPED"
expect_eq "SH7b a task row folded under its text passes: the renderer folds a long row, and the row still counts once" "0|" "$SC_RC|$SC_ERR"

# ============================================================
section "§WORDS: \"reader\", \"reading\" or \"unmeasured\" in the judgment refuses the card, on any line the model writes"
# ============================================================
# fails-when: the card prints "reader", "reading" or "unmeasured" from any judgment line.
for w in 'the reader saw it' 'two readers agree' 'the readings hold' 'a reading of the run' 'The Reader says so' 'Goals are unmeasured.'; do
  sc_card "$SC_OWED" "$SC_J_OWED
point: $w"
  expect_eq "WO1 \"$w\" in a point refuses the card: exit 1, nothing printed" "1|" "$SC_RC|$SC_OUT"
done
for t in purpose call close; do
  sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed "s/^$t: /$t: before the reading, /")"
  expect_eq "WO2 \"reading\" in the $t refuses it too" "1|1" "$SC_RC|$(sc_why '"reading"')"
done
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^ask decide:D3: D3 · /ask decide:D3: D3 · no reader yet; /')"
expect_eq "WO2b …and in an ask line" "1|1" "$SC_RC|$(sc_why '"reader"')"
sc_card "$SC_OWED" "$SC_J_OWED
point: The structure reading has not run; readers are idle and goals are unmeasured."
expect_eq "WO3 one line with three refused words names each, each with its own rule" \
  "1|reading:review|readers:review|unmeasured:not measured" \
  "$SC_RC|$(printf '%s\n' "$SC_ERR" | sed -n 's/^.*refused: the judgment says "\([a-z]*\)" .*: the card says \(.*\)$/\1:\2/p' | sed 's/:a goal nobody measures is /:/' | paste -sd'|' -)"
sc_card "$SC_OWED" "$SC_J_OWED
point: I read the sheet; the spreadsheet and the readiness review agree; goals are not yet measured."
expect_eq "WO4 control: read, spreadsheet, readiness and not measured are other words, and the card prints" "0|" "$SC_RC|$SC_ERR"

# ============================================================
section "§REASONS: a refusal names every reason at once, nothing on stdout"
# ============================================================
# fails-when: a refused card prints, or a reason the first refusal could have named waits for a second run.
sc_card "$SC_OWED" "$(sc_judge_without "$SC_J_OWED" 'purpose: ')
point: 57 suites ran today.
metric: Pace: fine."
expect_eq "RE1 three faults at once, no purpose, a number no value holds and a foreign tag: exit 1, nothing on stdout" "1|" "$SC_RC|$SC_OUT"
expect_eq "RE2 …every reason on stderr in the one refusal" "1|1|1" "$(sc_why 'no purpose: line')|$(sc_why 'says 57')|$(sc_why 'metric:')"
sc_card "$SC_OWED" "$SC_J_OWED"
expect_eq "RE3 control: the judgment with the three faults moved back prints the card, nothing on stderr" "0|" "$SC_RC|$SC_ERR"
expect_nonempty "RE3b …on stdout" "$SC_OUT"

# ============================================================
section "§HEAD: the head names the wave only when the run has one"
# ============================================================
# fails-when: a run whose plan carries no wave number prints "wave -" in its head, or a numbered run loses its wave.
sc_card "$SC_OWED" "$SC_J_OWED"
expect_eq "HD1 a numbered run keeps its wave in the head" "Sitrep · bionic 1.24.0 · wave 41 · Tuesday 2:40 PM" \
  "$(printf '%s\n' "$SC_OUT" | head -1)"
SC_NOWAVE="$(printf '%s\n' "$SC_OWED" | sed 's/^run.wave: 41$/run.wave: -/')"
expect_eq "HD1a precondition: the sheet carries no wave number" "run.wave: -" "$(printf '%s\n' "$SC_NOWAVE" | /usr/bin/grep '^run.wave: ')"
sc_card "$SC_NOWAVE" "$SC_J_OWED"
expect_eq "HD2 a run with no wave number: the card prints (exit 0) and its head leaves the wave out" \
  "0|Sitrep · bionic 1.24.0 · Tuesday 2:40 PM" "$SC_RC|$(printf '%s\n' "$SC_OUT" | head -1)"
sc_check "$SC_NOWAVE" "$SC_OUT"
expect_eq "HD2b …and the check passes that card (exit 0, nothing said)" "0||" "$SC_RC|$SC_OUT|$SC_ERR"
expect_eq "HD3 a run with no release leaves it out too (MK2): the flock head" "Sitrep · flock-app · wave 2 · Friday 10:49 PM" "$(printf '%s\n' "$SC_FLOCK_CARD" | head -1)"

# ============================================================
section "§VERB: sitrep card draws the run's own sheet and the judgment through card.sh, and settles a ruled decision first"
# ============================================================
# fails-when: the verb prints a card the renderer refused, draws from another sheet than the run's, or shows a decision
# the ledger ruled as owed while its ask stays open on the register.
export BIONIC_PLUGINS_DIR="$TMPROOT/no-plugins"; mkdir -p "$BIONIC_PLUGINS_DIR"
export BIONIC_PRESSURE_RING="$TMPROOT/pressure.ring"
export BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 BIONIC_PROBE_FREE_PCT=60 BIONIC_PROBE_SWAP_PCT=0
export BIONIC_PROBE_CORES=8 BIONIC_PROBE_USED_PCT=30 BIONIC_PROBE_BUSY_CORES=1.0 BIONIC_PROBE_BUSY_CORES_5M=1.0
export CLAUDE_CONFIG_DIR="$TMPROOT/config"; mkdir -p "$CLAUDE_CONFIG_DIR/bionic"; printf '80\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
export TZ=America/Los_Angeles
SV_SID="5c1e7a2b-3d4f-4e8a-9b6c-1f2e3d4c5b6a"
SV_NOW=1791324000     # 2026-10-06T22:00:00Z = 3:00 PM PDT
SV_R="$TMPROOT/verb"; SV_D="$SV_R/.bionic/docs/record/wave-02-fx"; SV_P="$SV_R/.bionic/docs/plans/epic-01-fx/wave-02-fx.plan.md"
SV_GATE="$TMPROOT/gate"; mkdir -p "$SV_GATE/requests" "$SV_GATE/cost" "$SV_D" "${SV_P%/*}" "$SV_R/.bionic/tmp"
( cd "$SV_R" && git init -q . )
SV_ROW() { printf '| %s | %s | build | %s · complexity: standard | — | — | %s | 30 | REQ-1 | lib/%s.sh | — | — | %s | — | — | — |\n' "$1" "$2" "$3" "$4" "$1" "$5"; }
{
  printf -- '---\nwave: wave-02-fx\nrelease: 9.9.0\nworking-branch: wave/02-fx\nintegration-branch: main\nforecast: 8h\n'
  printf 'goals: owed · the user says what they owe (record/owed-test.md)\n---\n# fixture plan\n\n## SDLC State\n\n'
  printf 'approved-by: fixture 2026-10-06T16:00:00Z "approved"\ncurrent: 4\n\n- Step 4: implementation opened\n'
  printf -- '- T1: landed %s 2026-10-06T18:00:00Z — .worktrees/02-T1\n' "$(printf 'c%.0s' $(seq 40))"
  printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | reads | size | serves | Files | worktree | base | status | suites | lands-on | artifact |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n'
  SV_ROW T1 4 "The first row" — landed
  SV_ROW T2 4 "The second row" — active
  SV_ROW T3 8 "Merge it" "approval:release" pending
  printf '\n## Not Doing\n\n- nothing\n'
} > "$SV_P"
SV_REG="$(bash -c '. "$1" && owed_register "$2" "$3"' _ "${REPO}/payload/scripts/lib/owed.sh" "$SV_R" "$SV_P")"
{
  printf 'owed/v1|key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T3 — approval:release\n'
  printf 'owed/v1|key=decide:D5|state=open|sent=-|at=2026-10-06T20:01:00Z|title=reply to D5|reply=D5 · the width: reply with the option number.\n'
} > "$SV_REG"
printf '# Design ledger — wave-02-fx\n\n## Δ0 — D5 put (orchestrator 2026-10-06 1:00 PM PDT): the width\n\nNothing waits on it.\n## Δ1 — D5 ruled "1" (Fixture Person 2026-10-06): the width\n' > "$SV_D/design-ledger.md"
sv_run() {  # <args after `sitrep`…> [stdin from the caller] -> SV_RC, SV_OUT, SV_ERR; the clock is SV_AT, else SV_NOW
  SV_RC=0
  ( cd "$SV_R" && exec env CLAUDE_CODE_SESSION_ID="$SV_SID" BIONIC_NOW_EPOCH="${SV_AT:-$SV_NOW}" BIONIC_GATE_DIR="$SV_GATE" \
      bash "$POKER" sitrep "$@" ) > "$TMPROOT/sv.out" 2> "$TMPROOT/sv.err" || SV_RC=$?
  SV_OUT="$(cat "$TMPROOT/sv.out")"; SV_ERR="$(cat "$TMPROOT/sv.err")"
}
expect_contains "VE0 precondition: the register holds D5 open before any read" "|key=decide:D5|state=open|" "$(cat "$SV_REG")"
sv_run "$SV_P" < /dev/null
expect_eq "VE1 the sheet prints (exit 0) and holds the open approval as an ask, naming the task it holds by its card label" "0|ask: key=approve:release holds=8/3" \
  "$SV_RC|$(printf '%s\n' "$SV_OUT" | /usr/bin/grep -o '^ask: key=approve:release holds=8/3')"
expect_contains "VE2 the sheet settled the register against the ledger: D5, ruled there, is closed on it" \
  "|key=decide:D5|state=closed|" "$(cat "$SV_REG")"
expect_absent "VE2b …and the sheet shows no D5 (VE1 read the asks of the same sheet)" "decide:D5" "$SV_OUT"
printf '%s\n' "$SV_OUT" > "$TMPROOT/verb-sheet"
sv_fact() { sed -n "s/^$1: //p" "$TMPROOT/verb-sheet"; }   # <key> -> the verb sheet's value for it
sv_m() { sv_fact "$1" | awk '{ i = index($0, " — "); print (i ? substr($0, 1, i - 1) : $0) }'; }   # <key> -> its measurement alone
SV_J="purpose: the fixture plan ships its rows; on course.
call: approve the release once 4/2 lands.
grade: C
point: One task is in flight and nothing is red.
ask approve:release: the release approval, which holds 8/3 — recommend approve once 4/2 lands
close: if 4/2 lands first time."
expect_nonempty "VE2c precondition: the verb's sheet predicts a close the card draws" "$(sv_fact close.predicted)"
sv_run card "$SV_P" <<< "$SV_J"
expect_eq "VE3 sitrep card prints the card (exit 0, nothing on stderr)" "0|" "$SV_RC|$SV_ERR"
expect_eq "VE3b …its head from the run's own sheet" "Sitrep · $(basename "$SV_R") 9.9.0 · wave 2 · Tuesday 3:00 PM" "$(printf '%s\n' "$SV_OUT" | head -1)"
expect_eq "VE3c …the verb's card is the renderer's over the same sheet and judgment, byte for byte" \
  "$(printf '%s\n' "$SV_J" | bash "$CARD_SH" sitrep "$TMPROOT/verb-sheet")" "$SV_OUT"
expect_eq "VE3d …each task row drawn from the run's own sheet: the landed task done, the building and the held ones open" \
  "    ✅ 4/1: The first row|    ⬜ 4/2: The second row|    ⬜ 8/3: Merge it" \
  "$(sc_rows "$SV_OUT" "Task list" | /usr/bin/grep -F '/' | sed 's/,.*//' | paste -sd'|' -)"
expect_eq "VE3e …and the predicted close its first close row, the sheet's own time" "    • $(sv_m close.predicted)" \
  "$(sc_rows "$SV_OUT" "Predicted close" | head -1 | sed 's/[,.].*//')"
sv_run card "$SV_P" <<< "$SV_J
point: 777 suites ran."
expect_eq "VE4 the verb refuses a point with a number the run's sheet does not hold: exit 1, stdout empty, naming 777" "1||yes" \
  "$SV_RC|$SV_OUT|$(printf '%s\n' "$SV_ERR" | /usr/bin/grep -qF '777' && echo yes)"
sv_run card "$SV_P" <<< "$(sc_judge_without "$SV_J" 'purpose:')"
expect_eq "VE5 the verb refuses a judgment with no purpose: exit 1, stdout empty" "1|" "$SV_RC|$SV_OUT"
expect_contains "VE5b …the renderer's reason reaching stderr" "no purpose: line" "$SV_ERR"
sv_run card --line "$SV_P" <<< "$SV_J"
expect_eq "VE6 card with --line is a usage error (2)" "2" "$SV_RC"

# THE SHEET THE JUDGMENT WAS WRITTEN FROM. The card is checked against the sheet `sitrep` printed and saved, while it is
# under 10 minutes old, so a clock that moves while the model writes never refuses a true judgment; the asks are read
# fresh, so an ask opened since is on the card.
# fails-when: the card verb recomputes the sheet (a judgment true at 3:00 PM is drawn with 3:02 PM facts), draws from
# a sheet 10 minutes old or none, or takes the asks from the saved sheet.
SV_SAVED="$SV_R/.bionic/tmp/sitrep/wave-02-fx.sheet"
sv_run "$SV_P" < /dev/null
expect_eq "VE7 sitrep saves the sheet it prints, byte for byte, beside its stamp" "0|yes|yes" \
  "$SV_RC|$([ -f "$SV_SAVED" ] && [ "$(cat "$SV_SAVED")" = "$SV_OUT" ] && echo yes)|$([ -f "$SV_SAVED.at" ] && echo yes)"
SV_AT=$((SV_NOW + 120)) sv_run "$SV_P" < /dev/null
SV_LATER="$SV_OUT"
sv_run "$SV_P" < /dev/null
expect_eq "VE8 precondition: two minutes on, the run's sheet predicts another close than the saved one" "yes|yes" \
  "$([ -n "$(sv_fact close.predicted)" ] && echo yes)|$(printf '%s\n' "$SV_LATER" | /usr/bin/grep -q "^close.predicted: " && ! printf '%s\n' "$SV_LATER" | /usr/bin/grep -qxF "close.predicted: $(sv_fact close.predicted)" && echo yes)"
SV_AT=$((SV_NOW + 120)) sv_run card "$SV_P" <<< "$SV_J"
expect_eq "VE8b the judgment written from the saved sheet prints its card two minutes later (exit 0, nothing on stderr)" "0|" "$SV_RC|$SV_ERR"
expect_eq "VE8c …its head the saved sheet's clock, 3:00 PM, and its close the saved sheet's" \
  "Sitrep · $(basename "$SV_R") 9.9.0 · wave 2 · Tuesday 3:00 PM|    • $(sv_m close.predicted)" \
  "$(printf '%s\n' "$SV_OUT" | head -1)|$(sc_rows "$SV_OUT" "Predicted close" | head -1 | sed 's/[,.].*//')"
SV_AT=$((SV_NOW + 660)) sv_run card "$SV_P" <<< "$SV_J"
expect_eq "VE9 a saved sheet 11 minutes old refuses the card: exit 1, stdout empty" "1|" "$SV_RC|$SV_OUT"
expect_contains "VE9b …in one line naming its age" "the sheet you wrote from is 11 min old: run sitrep again" "$SV_ERR"
SV_AT=$((SV_NOW + 540)) sv_run card "$SV_P" <<< "$SV_J"
expect_eq "VE9c control: at 9 minutes old it prints (exit 0)" "0" "$SV_RC"
mv "$SV_SAVED" "$SV_SAVED.away"
sv_run card "$SV_P" <<< "$SV_J"
expect_eq "VE9d no saved sheet refuses the card, saying so" "1||yes" \
  "$SV_RC|$SV_OUT|$(printf '%s\n' "$SV_ERR" | /usr/bin/grep -qF 'the sheet you wrote from is missing: run sitrep again' && echo yes)"
mv "$SV_SAVED.away" "$SV_SAVED"
cp "$SV_SAVED.at" "$TMPROOT/stamp"; printf '%s\t%s\n' "$SV_NOW" "$SV_R/.bionic/docs/plans/epic-01-fx/other.plan.md" > "$SV_SAVED.at"
sv_run card "$SV_P" <<< "$SV_J"
expect_eq "VE9e a saved sheet of another plan is no sheet of this one: refused" "1|" "$SV_RC|$SV_OUT"
cp "$TMPROOT/stamp" "$SV_SAVED.at"
printf 'owed/v1|key=approve:merge|state=open|sent=-|at=2026-10-06T22:01:00Z|title=approval: merge|reply=poker: WAIT — approval:merge\n' >> "$SV_REG"
SV_AT=$((SV_NOW + 60)) sv_run card "$SV_P" <<< "$SV_J"
expect_eq "VE10 an ask opened after the sheet was saved is on the card: no task reads it, so it is drawn alone under the Assessment" \
  "0|    • Open, blocking nothing: Approval: merge|" \
  "$SV_RC|$(sc_rows "$SV_OUT" "Assessment" | /usr/bin/grep -F 'merge')|$(sc_rows "$SV_OUT" "Blocked on you" | /usr/bin/grep -F 'merge')"
SV_AT=$((SV_NOW + 60)) sv_run card "$SV_P" <<< "$SV_J
ask approve:merge: approve the merge into main — recommend approve once 4/2 lands"
expect_eq "VE10b …and a judgment answering it draws the row as the model wrote it, in the same place" \
  "0|    • Open, blocking nothing: approve the merge into main — recommend approve once 4/2 lands" \
  "$SV_RC|$(sc_rows "$SV_OUT" "Assessment" | /usr/bin/grep -F 'merge into main')"
expect_eq "VE10c …while the release approval, which holds the merge task, stays under Blocked on you (VE10b read the same card)" "1" \
  "$(sc_rows "$SV_OUT" "Blocked on you" | /usr/bin/grep -c 'release approval')"
# THE RULING ASK, END TO END: the tick opens ruling:<id> when a row holds until its writer reads a ruling, its reply
# naming the row. The verb reads that row as held, so the card draws the ask under Blocked on you.
# fails-when: the ruling ask reads holds=nothing, so it is drawn under the Assessment with Blocked on you holding
# only the release approval.
printf 'owed/v1|key=ruling:r9|state=open|sent=-|at=2026-10-06T22:02:00Z|title=ruling unread: T2|reply=poker: NOT-LANDED T2 — w-T2 ended (MET) with an orchestrator ruling unread (r9); the row holds until a writer reads it: re-dispatch the row, or drop it\n' >> "$SV_REG"
SV_AT=$((SV_NOW + 120)) sv_run "$SV_P" < /dev/null
printf '%s\n' "$SV_OUT" > "$TMPROOT/verb-sheet"
expect_eq "VE10d the verb's sheet reads the ruling ask as holding the row its reply names (4/2), blocking" "ask: key=ruling:r9 holds=4/2 title=ruling unread: T2 raised=3:02 PM blocks=yes waits=user" \
  "$(sv_fact ask | /usr/bin/grep '^key=ruling:r9 ' | sed 's/^/ask: /')"
SV_JR="$(printf '%s\n' "$SV_J" | sed -e 's/^call: .*/call: Re-dispatch 4\/2 or drop it: its ruling is unread./')
ask approve:merge: approve the merge into main — recommend approve once 4/2 lands
ask ruling:r9: the ruling on 4/2 is unread and the row holds — recommend re-dispatch"
SV_AT=$((SV_NOW + 120)) sv_run card "$SV_P" <<< "$SV_JR"
expect_eq "VE10e the call, in words that owe something, prints, the ruling ask under Blocked on you and not under the Assessment" \
  "0|1|0" \
  "$SV_RC|$(sc_rows "$SV_OUT" "Blocked on you" | /usr/bin/grep -c 'ruling on 4/2 is unread')|$(sc_rows "$SV_OUT" "Assessment" | /usr/bin/grep -c 'ruling on 4/2 is unread')"

# ============================================================
section "§SKILL: the skill writes the judgment in the tags the verb takes and shows only what the verb printed, in one fenced block"
# ============================================================
# FIXTURE FIDELITY: the shipped skill text read in place; the tags are the ones card.sh says it takes in its own
# refusal of an unknown tag; each plant is a scratch copy of the skill with one line moved.
# fails-when: the skill shows text the verb did not print (a paraphrase, a card written by hand, a refused card), or
# names a judgment tag the verb refuses, or leaves one out.
SK_SKILL="${BIONIC_SKILLS_DIR}/sitrep/SKILL.md"
sk_tags() {  # -> each judgment tag card.sh takes, one per line, read from its refusal of an unknown tag
  sc_card "$SC_OWED" "$SC_J_OWED
verdict: fine"
  printf '%s\n' "$SC_ERR" | sed -n 's/.*it takes \(.*\)$/\1/p' | head -1 | sed 's/ and /, /' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | /usr/bin/grep .
}
sk_missing() {  # <skill file> -> each tag the verb takes that the file does not name in code
  local t
  while IFS= read -r t; do /usr/bin/grep -qF -- "\`$t" "$1" || printf ' %s' "$t"; done <<< "$SK_TAGS"
}
sk_unshown() {  # <skill file> -> each line that shows the card yet lets other text through: not exactly as printed, or not one fence
  awk '{ l = tolower($0) } l ~ /(^|[^a-z])shows?([^a-z]|$)/ && l ~ /card/ && l !~ /never/ && l !~ /description:/ \
    && (l !~ /exactly as printed/ || l !~ /one fenced code block/ || l !~ /nothing after/) { print }' "$1"
}
SK_TAGS="$(sk_tags)"
expect_eq "SK0 the verb names the seven tags it takes (the extractor reads card.sh's own refusal)" \
  "purpose:|call:|grade:|point:|ask <key>:|close:" "$(printf '%s\n' "$SK_TAGS" | paste -sd'|' -)"
expect_empty "SK1 the skill names every tag the verb takes, each in code (SK0 read them)" "$(sk_missing "$SK_SKILL")"
expect_eq "SK2 the skill shows the card exactly as printed, inside one fenced code block, nothing after it" "1" \
  "$(/usr/bin/grep -i 'card' "$SK_SKILL" | /usr/bin/grep -i 'exactly as printed' | /usr/bin/grep -i 'one fenced code block' | /usr/bin/grep -ci 'nothing after')"
expect_empty "SK2b …and no other line shows the card some other way (SK2 read the same file)" "$(sk_unshown "$SK_SKILL")"
expect_eq "SK3 rc 1: the skill fixes the judgment and runs it again, never shows a refused card, never writes one by hand" "1" \
  "$(/usr/bin/grep -F 'rc 1' "$SK_SKILL" | /usr/bin/grep -i 'never show a refused card' | /usr/bin/grep -ci 'never write a card by hand')"
cp "$SK_SKILL" "$TMPROOT/sk-plant.md"; printf '%s\n' 'Show the card to the user in your own words.' >> "$TMPROOT/sk-plant.md"
expect_eq "SK4 a planted paraphrase of the card is found" "Show the card to the user in your own words." "$(sk_unshown "$TMPROOT/sk-plant.md")"
sed 's/`call:`/the call tag/g' "$SK_SKILL" > "$TMPROOT/sk-plant.md"
expect_eq "SK5 a copy with call: left out is found missing it, beside what the shipped text misses (nothing, by SK1)" " call:" \
  "$(comm -13 <(sk_missing "$SK_SKILL" | tr ' ' '\n' | /usr/bin/grep . | sort) <(sk_missing "$TMPROOT/sk-plant.md" | tr ' ' '\n' | /usr/bin/grep . | sort) | sed 's/^/ /' | paste -sd'\0' -)"

# ============================================================
section "§ONE-READER: the goal's status, the task's title and the goal's measure are each one function the sheet and the cards call"
# ============================================================
# FIXTURE FIDELITY: one run of the verbs' own shapes: a wave plan approved at Step 3 whose requirements give it two
# themes and whose matrix discharges one of the first theme's two criteria and the second theme's one, so the second
# goal reads met. T1's cell opens on a title with a colon in it, the shape the plan card and the sheet once cut two
# ways. The surfaces are the real verbs: `sitrep` for the sheet, `sitrep card` for the sitrep card, `card.sh step3`
# for the plan's card. The plants are a copy of the tree with the one reading of a fact changed: both surfaces must
# move with it, so a surface that keeps its own copy reads apart from the sheet and the row reddens.
# ANTI-VACUITY: each plant's sed is proven to change the copy; each fact is read on the shipped tree first through the
# extractor read after the plant, and the status row's control world, the goal not met, draws the ask the row then
# finds gone.
# fails-when: hooks/poker/sitrep.sh cuts a task's title by a rule of its own (OR-1), the card verb or card.sh reads
# whether a goal is met by a word of its own (OR-3), or card.sh parses the goal's measure by a grammar of its own (OR-5).
OR_R="$TMPROOT/one-reader"; OR_D="$OR_R/.bionic/docs/record/wave-02-fx"; OR_P="$OR_R/.bionic/docs/plans/epic-01-fx/wave-02-fx.plan.md"
OR_Q="$OR_R/.bionic/docs/specs/epic-01-fx/wave-02-fx.requirements.md"
mkdir -p "$OR_D" "${OR_P%/*}" "${OR_Q%/*}" "$OR_R/.bionic/tmp"; ( cd "$OR_R" && git init -q . ); : > "$OR_D/landing-proofs.log"
or_plan() {  # <AC-2.1 status> -> the plan, its second theme met when AC-2.1 is discharged
  {
    printf -- '---\nwave: wave-02-fx\nrelease: 9.9.0\nscale: wave\nworking-branch: wave/02-fx\nintegration-branch: main\nforecast: 8h\n---\n'
    printf '# fixture plan\n\n## Goal\n\nThe fixture ships.\n\n## SDLC State\n\napproved-by: fixture 2026-10-06T16:00:00Z "approved"\ncurrent: 4\n\n- Step 4: implementation opened\n'
    printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | reads | size | serves | Files | worktree | base | status | suites | lands-on | artifact |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | The release row: 1.27.0. It names the release it cuts · complexity: standard | — | — | — | 30 | REQ-1 | lib/t1.sh | — | — | active | — | — | — |\n'
    printf '| T2 | 4 | build | The second row. It does the second thing · complexity: standard | — | — | — | 30 | REQ-2 | lib/t2.sh | — | — | pending | — | — | — |\n'
    printf '\n## Verification Matrix\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
    printf '| AC-1.1 | T2 | discharged | pending | — |\n| AC-1.2 | T2 | pending | pending | — |\n| AC-2.1 | T2 | %s | pending | — |\n' "$1"
    printf '\n## Not Doing\n\n- nothing\n'
  } > "$OR_P"
}
{
  printf -- '---\nscale: wave\n---\n# fixture requirements\n\n## Goal\n\nThe fixture ships.\n'
  printf '\n## The run closes itself\n\nThe run reaches its card without a person.\n'
  printf '\n### REQ-1 — one\n\n- AC-1.1 a. Fails when: b.\n- AC-1.2 a. Fails when: b.\n'
  printf '\n## The pages\n\nThe pages say what the run knows.\n\n### REQ-2 — two\n\n- AC-2.1 a. Fails when: b.\n'
  printf '\n## Not Doing\n\n- nothing\n'
} > "$OR_Q"
or_plan discharged
OR_REG="$(bash -c '. "$1" && owed_register "$2" "$3"' _ "${REPO}/payload/scripts/lib/owed.sh" "$OR_R" "$OR_P")"
or_ask() {  # -> the register holding one open ask: the second goal's decision, as the tick opens it on a first miss
  mkdir -p "${OR_REG%/*}"
  printf 'owed/v1|key=decide:goal:the-pages|state=open|sent=-|at=2026-10-06T20:00:00Z|title=goal decision: The pages|reply=poker: the goal The pages missed\n' > "$OR_REG"
}
OR_J="purpose: The fixture plan ships its rows; on course.
call: Let 4/1 land.
grade: C
point: One task is in flight and nothing is red.
close: If 4/1 lands first time."
or_run() {  # <hooks dir> -> OR_SHEET, OR_CARD, OR_STEP3: the three surfaces from the tree whose hooks are given
  local h="$1"
  OR_SHEET="$( cd "$OR_R" && env CLAUDE_CODE_SESSION_ID="$SV_SID" BIONIC_NOW_EPOCH="$SV_NOW" BIONIC_GATE_DIR="$SV_GATE" bash "$h/session-poker.sh" sitrep "$OR_P" 2>/dev/null )"
  OR_CARD="$( cd "$OR_R" && env CLAUDE_CODE_SESSION_ID="$SV_SID" BIONIC_NOW_EPOCH="$SV_NOW" BIONIC_GATE_DIR="$SV_GATE" bash "$h/session-poker.sh" sitrep card "$OR_P" <<< "$OR_J" 2>/dev/null )"
  OR_STEP3="$(bash "$h/../payload/scripts/card.sh" step3 "$OR_P" 2>/dev/null)"
}
or_desc() { printf '%s\n' "$OR_SHEET" | sed -n "s/^task: id=$1 step=[^ ]* state=[^ ]* desc=\(.*\) note=.*/\1/p"; }   # <id> -> the sheet's title of it
or_title() { printf '%s\n' "$OR_STEP3" | awk -v id="$1" '$1 == id { sub(/^ *[^ ]+ +/, ""); sub(/  +.*$/, ""); print; exit }'; }   # <id> -> the plan card's
or_goals() { printf '%s\n' "$OR_CARD" | awk '$1 == "Goals" { sub(/^ *Goals +/, ""); print; exit }'; }   # -> the sitrep card's Goals cell
or_goal_ask() { printf '%s\n' "$OR_SHEET" | /usr/bin/grep -c '^ask: key=decide:goal:the-pages '; printf '%s\n' "$OR_CARD" | /usr/bin/grep -ci 'goal decision: the pages'; }
OR_T="$TMPROOT/or-mut"; mkdir -p "$OR_T/payload"
cp -R "$BIONIC_HOOKS_DIR" "$OR_T/hooks" && cp -R "${REPO}/payload/scripts" "$OR_T/payload/scripts"
OR_LIBF="$OR_T/payload/scripts/lib/plan.sh"; OR_LIB_ORIG="$TMPROOT/or-plan.orig"; cp "$OR_LIBF" "$OR_LIB_ORIG"
or_plant() { sed "$1" "$OR_LIB_ORIG" > "$OR_LIBF"; ! cmp -s "$OR_LIB_ORIG" "$OR_LIBF"; }   # <sed> -> the copy's lib/plan.sh so edited; rc 1 when it changed nothing

# the task's title: the sheet and the plan's card cut the cell one way
or_plan discharged; : > "$OR_REG"; or_run "$BIONIC_HOOKS_DIR"
expect_eq "OR-0 precondition: the sheet, the sitrep card and the plan's card each print, T1's title read on both" "yes|yes|yes" \
  "$([ -n "$(or_desc T1)" ] && echo yes)|$([ -n "$(or_goals)" ] && echo yes)|$([ -n "$(or_title T1)" ] && echo yes)"
expect_eq "OR-1 a title holding a colon is one title on the sheet and on the plan's card" \
  "The release row: 1.27.0|The release row: 1.27.0" "$(or_desc T1)|$(or_title T1)"
expect_eq "OR-1b …as is a plain one (the extractors read both rows)" "The second row|The second row" "$(or_desc T2)|$(or_title T2)"

# the goal's status: the sheet drops the decision of a met goal, and so does the card, whatever the met word reads
or_plan pending; or_ask; or_run "$BIONIC_HOOKS_DIR"
expect_eq "OR-2 control: with the second goal not met its decision is an ask on the sheet and drawn on the card" "1|1" "$(or_goal_ask | paste -sd'|' -)"
or_plan discharged; or_ask; or_run "$BIONIC_HOOKS_DIR"
expect_eq "OR-2b …met, the sheet owes it not and the card draws it not (OR-2 read both through the same call)" "0|0" "$(or_goal_ask | paste -sd'|' -)"
or_plant "s/reached) printf 'met\\\\n'/reached) printf 'achieved\\\\n'/"; OR_PL=$?
or_plan discharged; or_ask; or_run "$OR_T/hooks"
expect_eq "OR-3 the one status reading planted to call a met goal achieved: the sheet says so, and the card still drops its decision with the sheet" \
  "0|name=The pages status=achieved|0|0" "$OR_PL|$(printf '%s\n' "$OR_SHEET" | /usr/bin/grep -o 'name=The pages status=achieved')|$(or_goal_ask | paste -sd'|' -)"

# the goal's measure: the sheet's words and the card's counts are one grammar
: > "$OR_REG"; or_run "$BIONIC_HOOKS_DIR"
expect_eq "OR-4 precondition: the card's Goals cell carries each theme's counts from the sheet's measure" \
  "The run closes itself on course, 1 of 2, REQ-1 open · The pages met, 1 of 1" "$(or_goals)"
or_plant 's/criteria discharged/criteria done/g'; OR_PL=$?
or_run "$OR_T/hooks"
expect_eq "OR-5 the one measure grammar planted to say criteria done: the sheet says so, and the card still reads its counts" \
  "0|1 of 2 criteria done|The run closes itself on course, 1 of 2, REQ-1 open · The pages met, 1 of 1" \
  "$OR_PL|$(printf '%s\n' "$OR_SHEET" | /usr/bin/grep -o '1 of 2 criteria done' | head -1)|$(or_goals)"

finish
