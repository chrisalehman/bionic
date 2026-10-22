#!/bin/bash
# Tests for the sitrep card: `payload/scripts/card.sh sitrep` and `sitrep-check`, and the verb that draws it,
# `hooks/session-poker.sh sitrep card [<plan>]`.
#
# THE MODEL WRITES EVERY ROW; THE MACHINE SUPPLIES THE FACTS AND CHECKS. The verb gathers the fact sheet; the model
# writes the judgment, tagged lines on stdin (call:, task:, metric:, grade:, point:, ask <key>:, ask +:, close:);
# card.sh draws the head, the seven sections, the bullets and each task row's icon, capitalizes each row's first
# letter, then holds the judgment to the sheet and the drawn text to the card's shape before it prints a byte. A card
# that drops a step, an open task, a metric, the predicted close or an open ask, names a label or a key the sheet
# lacks, states a metric number its own lines do not measure or a goal count the goal: lines do not hold, says nothing
# is owed while an ask is open, writes an open task landed or a done one waiting, leaves out a task an ask holds, says
# "reader", runs a line past 100 columns or puts a step row above its own tasks is refused: every reason on stderr,
# nothing on stdout, rc 1.
#
#   §SECTIONS  seven sections in order, every row bulleted or iconed, each row's first letter capitalized, no options
#   §CALL      the clean card's Blocked on you is one row; a call is words, and needs no ask's key or id; with an ask
#              open it never says nothing is owed, and with none open it names no key
#   §FLOOR     an open ask the judgment leaves out, answers twice or names without the tasks it holds refuses the card
#   §ROWS      the Task list covers every step in the sheet's order, by labels the sheet holds, its icons drawn from the
#              sheet, each task's row in words its state allows; the five metrics in order, their numbers their own
#              lines' measured values, the Goals counts the goal: lines'; the predicted close in a close row
#   §SHAPE     a 101-column line, a step row above its tasks, an open task twice or not at all: each refused
#   §WORDS     "reader", "reading" and their kin, or "unmeasured", in the judgment refuse the card, each word with its rule
#   §REFUSE    a refused card prints nothing on stdout, every reason on stderr
#   §JUDGMENT  the judgment's own floors: one grade A to F, one to five points, a call, one to three closes, known tags
#   §HEAD      the head names the wave only when the run has one
#   §VERB      the verb draws the card from the sheet the judgment was written from, under 10 minutes old, its asks
#              read fresh, and settles a decision the ledger ruled first
#   §SKILL     the skill writes the tags the verb takes and shows only what the verb printed, in one fenced block
#
# HERMETIC. card.sh is fed fixture sheets in the verb's own `sheet/v1` shape (the verb's sheet is proved to parse
# the same way in §VERB); the verb runs in one temp repository with a pinned clock and zone, its own gate store and
# pinned machine probes, as tests/sitrep.test.sh runs it.
#
# ANTI-VACUITY. Every refusal stands beside the same card passing with the one fact moved back; every planted
# fault is read by the same check that passes the unplanted card in the same call.
#
# Usage: bash tests/sitrep-card.test.sh

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
SC_ASKS='ask: key=decide:D3 holds=4/8 title=D3 · waive or fix raised=1:00 PM
ask: key=approve:release holds=8/47 title=approval: release raised=1:05 PM'
SC_OWED="$SC_BASE
$SC_ASKS"
SC_CLEAN="$SC_BASE"

# The judgment writes every row. Some rows open on a lower-case word, as a model writes them, so the card's
# capitals are the renderer's.
SC_J_TASKS='task: 0: Configure
task: 1: Scope
task: 2: Design
task: 3: Plan, its two tasks landed
task: 4/3–4/4: the register and the release card landed
task: 4/13: the stragglers landed
task: 4/40: a check rewrite never passes unjudged, running
task: 4/7: the width pins, red
task: 4/8: the skill texts, waiting on your ruling on D3
task: 5/41: the whole regression at the build head, after the build
task: 6: Review
task: 7: Document
task: 8/47: merge into main, waiting on your approval of the release
task: 9: Close-out'
SC_J_METRICS='metric: Completed: 5 tasks landed, 190 of 520 sized minutes, 37%; 5 left, 330 minutes.
metric: Pace: 37% of the work landed in 60% of the forecast time.
metric: Correctness: 12 suites run, 11 green and 1 red; 1 review running; 0 open findings.
metric: Waste: 2 tasks dropped; 0 of 25 suite runs thrown away; 60 minutes waiting on you.
metric: Goals: 0 of 1 met; 1 not measured yet.'
SC_J_OWED="call: rule on D3: the skill texts and the merge wait on it.
$SC_J_TASKS
$SC_J_METRICS
grade: B
point: the last build task is running; once it lands, the regression runs, about 25 minutes.
point: The run is 1 h 50 min over plan, mostly the test cull.
ask decide:D3: D3 · waive the failed review or fix first; it holds 4/8 — recommend waive
ask approve:release: approve release 1.24.0; it holds 8/47 — recommend approve once the regression is green
close: 8:40 PM, against the 6:50 PM forecast.
close: depends on the regression passing first time; a red adds a fix task, about 45 minutes."
SC_J_CLEAN="call: Nothing is owed: let 4/40 land, then fix the width pins.
$SC_J_TASKS
$SC_J_METRICS
grade: B
point: The last build task is running; once it lands, the regression runs, about 25 minutes.
close: 8:40 PM, if the regression passes first time."

SC_WANT_OWED='Sitrep · bionic 1.24.0 · wave 41 · Tuesday 2:40 PM

  Call to action
    • Rule on D3: the skill texts and the merge wait on it.

  Task list
    ✅ 0: Configure
    ✅ 1: Scope
    ✅ 2: Design
    ✅ 3: Plan, its two tasks landed
    ✅ 4/3–4/4: The register and the release card landed
    ✅ 4/13: The stragglers landed
    ⬜ 4/40: A check rewrite never passes unjudged, running
    ⬜ 4/7: The width pins, red
    ⬜ 4/8: The skill texts, waiting on your ruling on D3
    ⬜ 5/41: The whole regression at the build head, after the build
    ⬜ 6: Review
    ⬜ 7: Document
    ⬜ 8/47: Merge into main, waiting on your approval of the release
    ⬜ 9: Close-out

  Metrics
    • Completed: 5 tasks landed, 190 of 520 sized minutes, 37%; 5 left, 330 minutes.
    • Pace: 37% of the work landed in 60% of the forecast time.
    • Correctness: 12 suites run, 11 green and 1 red; 1 review running; 0 open findings.
    • Waste: 2 tasks dropped; 0 of 25 suite runs thrown away; 60 minutes waiting on you.
    • Goals: 0 of 1 met; 1 not measured yet.

  Assessment: B
    • The last build task is running; once it lands, the regression runs, about 25 minutes.
    • The run is 1 h 50 min over plan, mostly the test cull.

  Blocked on you
    • D3 · waive the failed review or fix first; it holds 4/8 — recommend waive
    • Approve release 1.24.0; it holds 8/47 — recommend approve once the regression is green

  Predicted close
    • 8:40 PM, against the 6:50 PM forecast.
    • Depends on the regression passing first time; a red adds a fix task, about 45 minutes.'

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
sc_under() {  # <card> <section label> -> the rows under it, up to the blank line that ends it
  printf '%s\n' "$1" | awk -v h="  $2" '$0 == h || (h == "  Assessment" && index($0, "  Assessment: ") == 1) { f = 1; next } f && $0 == "" { exit } f { print }'
}
sc_labels() { printf '%s\n' "$1" | sed -n 's/^  \([^ ].*\)$/\1/p' | paste -sd'|' -; }   # <card> -> its section labels
sc_wide() {  # <text> -> each line wider than BIONIC_LINE_WIDTH columns, as `<columns>: <line>`
  local l
  while IFS= read -r l; do
    _bionic_cols_into "$l"
    [ "$BIONIC_COLS" -le "$BIONIC_LINE_WIDTH" ] || printf '%s: %s\n' "$BIONIC_COLS" "$l"
  done <<< "$1"
}
sc_judge_without() { printf '%s\n' "$1" | /usr/bin/grep -v -F -- "$2"; }   # <judgment> <text> -> the judgment, the lines holding it cut
sc_judge_swap() {  # <judgment> <line> <line> -> the judgment with the two whole lines traded places
  printf '%s\n' "$1" | awk -v a="$2" -v b="$3" '$0 == a { print b; next } $0 == b { print a; next } { print }'
}
sc_row() { printf '%s\n' "$1" | /usr/bin/grep -F -- "$2"; }   # <card> <text> -> the card's lines holding the text

# ============================================================
section "§SECTIONS: seven sections in order, every row bulleted or iconed, each row's first letter capitalized, no options"
# ============================================================
# fails-when: a section is missing or out of order, a bare row, a row left on a lower-case letter, or options print.
sc_card "$SC_OWED" "$SC_J_OWED"
expect_eq "SE1 the owed fixture renders (exit 0, nothing on stderr)" "0|" "$SC_RC|$SC_ERR"
expect_eq "SE2 …the whole card: the judgment's rows under the renderer's head, labels, bullets and icons" "$SC_WANT_OWED" "$SC_OUT"
expect_eq "SE3 the head, then the six labelled sections in their order" \
  "Call to action|Task list|Metrics|Assessment: B|Blocked on you|Predicted close" "$(sc_labels "$SC_OUT")"
expect_eq "SE4 every row under a section opens on a bullet or an icon (SE3 read the labels from the same card)" "" \
  "$(printf '%s\n' "$SC_OUT" | awk 'NR > 1 && /^    / && !/^    (• |✅ |⬜ )/')"
expect_eq "SE5 a row the judgment opened on a lower-case letter prints capitalized: the call, a task's text, a point, an ask, a close" \
  "    • Rule on D3: the skill texts and the merge wait on it.|    ✅ 4/13: The stragglers landed|    • The last build task is running; once it lands, the regression runs, about 25 minutes.|    • Approve release 1.24.0; it holds 8/47 — recommend approve once the regression is green|    • Depends on the regression passing first time; a red adds a fix task, about 45 minutes." \
  "$(sc_row "$SC_OUT" 'Rule on D3')|$(sc_row "$SC_OUT" '4/13: ')|$(sc_row "$SC_OUT" 'last build task')|$(sc_row "$SC_OUT" 'release 1.24.0;')|$(sc_row "$SC_OUT" 'regression passing')"
expect_eq "SE5b …and a row opening on a capital or a digit prints as written (SE5 read the same card)" \
  "    • D3 · waive the failed review or fix first; it holds 4/8 — recommend waive|    • 8:40 PM, against the 6:50 PM forecast." \
  "$(sc_row "$SC_OUT" 'D3 · waive')|$(sc_row "$SC_OUT" '8:40 PM, against')"
SC_J_OPT="$(printf '%s\n' "$SC_J_OWED" | sed 's/^ask decide:D3: .*/ask decide:D3: D3 · 1. waive the failed review 2. fix first; it holds 4\/8 — recommend 1/')"
sc_card "$SC_OWED" "$SC_J_OPT"
expect_eq "SE8 an ask written as numbered options refuses the card: exit 1, nothing printed" "1|" "$SC_RC|$SC_OUT"
expect_contains "SE8b …saying the card never prints a decision's options" "options" "$SC_ERR"
expect_absent "SE8c the approved card prints no numbered option (SE2 read the whole card)" "1. waive" "$SC_WANT_OWED"

# ============================================================
section "§CALL: the clean card's Blocked on you is one row; a call is words, needs no key, and never says nothing is owed while an ask is"
# ============================================================
# fails-when: the clean card shows an ask, or a call written in words is refused for naming no key.
sc_card "$SC_CLEAN" "$SC_J_CLEAN"
expect_eq "CA1 the clean fixture renders (exit 0, nothing on stderr)" "0|" "$SC_RC|$SC_ERR"
expect_eq "CA2 …Blocked on you is the one row saying nothing is owed" "    • Nothing: no decision or action is owed right now." \
  "$(sc_under "$SC_OUT" "Blocked on you")"
expect_eq "CA3 …and the call names no ask key or id of the owed fixture (CA2 read the same card)" "" \
  "$(sc_under "$SC_OUT" "Call to action" | /usr/bin/grep -E 'D3|release|decide:|approve:')"
SC_J_WORDS="$(printf '%s\n' "$SC_J_OWED" | sed 's/^call: .*/call: Say whether the failed review may be waived; the merge waits on it./')"
sc_card "$SC_OWED" "$SC_J_WORDS"
expect_eq "CA4 with asks open, a call naming the first ask in words, by no key or id, prints (exit 0, nothing on stderr)" "0|" "$SC_RC|$SC_ERR"
expect_eq "CA4b …its row as written (CA4 rendered it)" "    • Say whether the failed review may be waived; the merge waits on it." \
  "$(sc_under "$SC_OUT" "Call to action")"
# fails-when: with asks open, a call saying nothing is owed prints; with none open, a call naming a register key prints.
SC_J_NOTHING="$(printf '%s\n' "$SC_J_OWED" | sed 's/^call: .*/call: Nothing is owed: go for a walk, the run finishes itself./')"
sc_card "$SC_OWED" "$SC_J_NOTHING"
expect_eq "CA5 with decide:D3 and approve:release open, a call saying nothing is owed refuses the card: exit 1, nothing printed" "1|" "$SC_RC|$SC_OUT"
expect_eq "CA5b …in one line naming the call rule and both open asks" "1" \
  "$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -F 'call:' | /usr/bin/grep -F 'nothing is owed' | /usr/bin/grep -F 'decide:D3' | /usr/bin/grep -cF 'approve:release')"
sc_card "$SC_CLEAN" "$(printf '%s\n' "$SC_J_NOTHING" | /usr/bin/grep -v '^ask ')"
expect_eq "CA5c control: the same call over the clean sheet, no ask open, prints (exit 0, nothing on stderr)" "0|" "$SC_RC|$SC_ERR"
for c in 'Nothing for you to do; let 4/40 land.' 'No decision is needed now.' 'Nothing waits on you: let the build finish.' 'Nothing: no decision or action is owed right now.'; do
  sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | awk -v c="call: $c" '/^call: / { print c; next } { print }')"
  expect_eq "CA5d \"$c\" as the call with asks open refuses the card" "1|1" \
    "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -F 'call:' | /usr/bin/grep -cF 'decide:D3')"
done
sc_card "$SC_CLEAN" "$(printf '%s\n' "$SC_J_CLEAN" | sed 's/^call: .*/call: Let 4\/40 land; approve:release comes after the regression./')"
expect_eq "CA6 with no ask open, a call naming a register key refuses the card: exit 1, nothing printed" "1|" "$SC_RC|$SC_OUT"
expect_eq "CA6b …in one line naming the key" "1" "$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -F 'call:' | /usr/bin/grep -cF 'approve:release')"
sc_card "$SC_CLEAN" "$(printf '%s\n' "$SC_J_CLEAN" | sed 's/^call: .*/call: Let 4\/40 land by 4:10 PM; the release approval comes after the regression./')"
expect_eq "CA6c control: the call in words, with a clock in it, prints (exit 0, nothing on stderr)" "0|" "$SC_RC|$SC_ERR"

# ============================================================
section "§FLOOR: an open ask left out, answered twice or named without the tasks it holds refuses the card"
# ============================================================
# fails-when: the card prints.
sc_card "$SC_OWED" "$(sc_judge_without "$SC_J_OWED" 'ask approve:release:')"
expect_eq "FL1 the judgment leaves out the open ask approve:release: exit 1, stdout empty" "1|" "$SC_RC|$SC_OUT"
expect_contains "FL1b …naming the key it dropped" "approve:release" "$SC_ERR"
sc_card "$SC_OWED" "$SC_J_OWED
ask hold:merge: the merge is held — recommend release it"
expect_eq "FL2 an ask line naming a key the register lacks: exit 1, stdout empty" "1|" "$SC_RC|$SC_OUT"
expect_contains "FL2b …naming the key" "hold:merge" "$SC_ERR"
sc_card "$SC_OWED" "$SC_J_OWED
ask +: the operator owes a gate act outside the run"
expect_eq "FL3 an ask the register lacks, added with ask +:, prints under Blocked on you, capitalized" \
  "0|    • The operator owes a gate act outside the run" \
  "$SC_RC|$(sc_under "$SC_OUT" "Blocked on you" | tail -1)"
sc_card "$SC_OWED" "$(sc_judge_without "$SC_J_OWED" 'ask decide:D3:')
ask decide:D3: D3 · waive or fix; it holds 4/8"
expect_eq "FL4 an ask line with no recommended answer refuses the card" "1|" "$SC_RC|$SC_OUT"
expect_contains "FL4b …saying what is missing" "recommend" "$SC_ERR"
SC_J_ONE="$(sc_judge_without "$(sc_judge_without "$SC_J_OWED" 'ask decide:D3:')" 'ask approve:release:')
ask decide:D3, approve:release: waive the failed review and ship; it frees 4/8 and 8/47 — recommend waive, then approve"
sc_card "$SC_OWED" "$SC_J_ONE"
expect_eq "FL5 one ask row answering two open keys that are one decision prints (exit 0, nothing on stderr)" "0|" "$SC_RC|$SC_ERR"
expect_eq "FL5b …as one row under Blocked on you (FL5 rendered it)" \
  "    • Waive the failed review and ship; it frees 4/8 and 8/47 — recommend waive, then approve" \
  "$(sc_under "$SC_OUT" "Blocked on you")"
sc_card "$SC_OWED" "$SC_J_OWED
ask decide:D3, approve:release: waive the failed review and ship; it frees 4/8 and 8/47 — recommend waive"
expect_eq "FL6 a key answered by two ask rows refuses the card" "1|" "$SC_RC|$SC_OUT"
expect_contains "FL6b …naming the key" "decide:D3" "$SC_ERR"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^ask decide:D3: .*/ask decide:D3: D3 · waive the failed review or fix first — recommend waive/')"
expect_eq "FL7 an ask row that leaves out the task its key holds refuses the card" "1|" "$SC_RC|$SC_OUT"
expect_eq "FL7b …naming the ask and the task's label" "yes|yes" \
  "$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -F 'decide:D3' | /usr/bin/grep -qF '4/8' && echo yes)|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qF 'holds' && echo yes)"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^ask decide:D3: D3 · waive the failed review or fix first; it holds 4\/8/ask decide:D3: D3 · waive the failed review or fix first; it holds 4\/80/')"
expect_eq "FL7c …and a longer label is not the task's: 4/80 does not name 4/8" "1|" "$SC_RC|$SC_OUT"

# ============================================================
section "§ROWS: the Task list covers every step in the sheet's order by labels the sheet holds; each task row true to its state; five metrics, their own lines' numbers; the close"
# ============================================================
# fails-when: a judgment that drops a step, names a label the sheet lacks, runs the steps out of order, drops or
# reorders a metric, states a number the sheet does not hold, or leaves out the predicted close prints its card; or
# a task row's icon is not the sheet's.
sc_card "$SC_OWED" "$(sc_judge_without "$SC_J_OWED" 'task: 6: Review')"
expect_eq "RO1 a step with no row on the Task list refuses the card: exit 1, stdout empty" "1|" "$SC_RC|$SC_OUT"
expect_contains "RO1b …naming the step" "step 6" "$SC_ERR"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^task: 4\/13: .*/&\
task: 4\/99: a task nobody planned/')"
expect_eq "RO2 a task label the sheet does not hold refuses the card" "1|" "$SC_RC|$SC_OUT"
expect_contains "RO2b …naming the label" "4/99" "$SC_ERR"
sc_card "$SC_OWED" "$SC_J_OWED
task: 12: More work"
expect_eq "RO2c a step the sheet does not hold refuses the card, naming it" "1|yes" \
  "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qF '12' && echo yes)"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^task: 4\/3–4\/4: /task: 4\/3–5\/41: /')"
expect_eq "RO2d a range across two steps refuses the card, naming it" "1|yes" \
  "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qF '4/3–5/41' && echo yes)"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^task: 6: Review$/task: 6:/')"
expect_eq "RO2e a task row with a label and no text refuses the card" "1|" "$SC_RC|$SC_OUT"
sc_card "$SC_OWED" "$(sc_judge_swap "$SC_J_OWED" 'task: 6: Review' 'task: 7: Document')"
expect_eq "RO3 rows out of the sheet's step order refuse the card" "1|" "$SC_RC|$SC_OUT"
expect_contains "RO3b …saying the Task list runs in the sheet's step order" "order" "$SC_ERR"
SC_J_RANGE="$(printf '%s\n' "$SC_J_OWED" | sed -e 's/^task: 4\/3–4\/4: .*/task: 4\/3–4\/13: three landed, two still open/' -e '/^task: 4\/13: /d')"
sc_card "$SC_OWED" "$SC_J_RANGE"
expect_eq "RO4 a range holding an open task prints (exit 0) with the open icon; the range of finished tasks has the done icon (SE2)" \
  "0|    ⬜ 4/3–4/13: Three landed, two still open|    ✅ 4/3–4/4: The register and the release card landed" \
  "$SC_RC|$(sc_row "$SC_OUT" '4/3–4/13: ')|$(sc_row "$SC_WANT_OWED" '4/3–4/4: ')"
SC_DONE4="$(printf '%s\n' "$SC_OWED" | sed 's/^step: n=4 name=Implement state=running/step: n=4 name=Implement state=done/')"
sc_card "$SC_DONE4" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^task: 4\/8: .*/&\
task: 4: Implement, called done with three tasks open/')"
expect_eq "RO4b a step the sheet calls done that holds an open task prints with the open icon, a done step with none with the done icon" \
  "0|    ⬜ 4: Implement, called done with three tasks open|    ✅ 3: Plan, its two tasks landed" \
  "$SC_RC|$(sc_row "$SC_OUT" ' 4: Implement')|$(sc_row "$SC_OUT" ' 3: Plan')"
sc_card "$SC_OWED" "$(sc_judge_without "$SC_J_OWED" 'metric: Waste: ')"
expect_eq "RO5 a judgment with four metrics refuses the card, naming the one missing" "1|yes" \
  "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qF 'Waste' && echo yes)"
sc_card "$SC_OWED" "$(sc_judge_swap "$SC_J_OWED" "$(sc_row "$SC_J_OWED" 'metric: Pace: ')" "$(sc_row "$SC_J_OWED" 'metric: Correctness: ')")"
expect_eq "RO5b the five metrics out of their order refuse the card" "1|" "$SC_RC|$SC_OUT"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^metric: Pace: /metric: Speed: /')"
expect_eq "RO5c a metric with a label the card does not know refuses it, naming the label" "1|yes" \
  "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qF 'Speed' && echo yes)"
sc_card "$SC_OWED" "$SC_J_OWED
metric: Goals: 1 not measured yet."
expect_eq "RO5d a metric written twice refuses the card" "1|" "$SC_RC|$SC_OUT"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^metric: Completed: 5 tasks landed, 190 of 520 sized minutes, 37%;/metric: Completed: 5 tasks landed, 190 of 520 sized minutes, 51%;/')"
expect_eq "RO6 a metric number the sheet does not hold refuses the card, naming the number and the metric" "1|yes" \
  "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -F 'Completed' | /usr/bin/grep -qF '51' && echo yes)"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^metric: Pace: 37% of the work landed in 60% of the forecast time\./metric: Pace: 5 tasks landed by 5:46 PM./')"
expect_eq "RO6b a clock in a metric is two numbers: 5 is the sheet's, 46 is not, and the card is refused naming 46" "1|yes" \
  "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -F 'Pace' | /usr/bin/grep -qF '46' && echo yes)"
# A metric's numbers are its own lines' measured values, so a number another line holds vouches for nothing.
# fails-when: a metric row prints stating a number the sheet holds only on a clock, a date, a unit's words or another
# metric's lines, or a goal count the goal: lines do not add up to.
sc_m_numbers() {  # <judgment> <metric label> -> each run of digits that metric's row states, in its order
  printf '%s\n' "$1" | sed -n "s/^metric: $2: //p" | /usr/bin/grep -oE '[0-9]+' | paste -sd' ' -
}
expect_eq "RO6c precondition: 2, 40 and 60 are numbers the owed sheet holds (the clock 2:40 PM, work.added, pace.time-used)" "yes|yes|yes" \
  "$(printf '%s\n' "$SC_OWED" | /usr/bin/grep -q '^clock.now: 2:40 PM' && echo yes)|$(printf '%s\n' "$SC_OWED" | /usr/bin/grep -q '^work.added: 2 tasks' && echo yes)|$(printf '%s\n' "$SC_OWED" | /usr/bin/grep -q '^pace.time-used: 60%' && echo yes)"
SC_J_TWO="$(printf '%s\n' "$SC_J_OWED" | sed 's/^metric: Completed: 5 tasks landed,/metric: Completed: 2 tasks landed,/')"
expect_eq "RO6d precondition: the planted Completed row says 2 tasks landed" "2 190 520 37 5 330" "$(sc_m_numbers "$SC_J_TWO" Completed)"
sc_card "$SC_OWED" "$SC_J_TWO"
expect_eq "RO6e a Completed row saying 2 tasks landed where work.landed says 5 refuses the card, naming Completed and 2" "1||1" \
  "$SC_RC|$SC_OUT|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -F 'metric Completed: says 2,' | /usr/bin/grep -cF 'work.landed')"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^metric: Pace: 37% of the work landed/metric: Pace: 40% of the work landed/')"
expect_eq "RO6f a Pace row giving the clock's 40 minutes as a percentage refuses the card, naming Pace and 40" "1||1" \
  "$SC_RC|$SC_OUT|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -cF 'metric Pace: says 40,')"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^metric: Completed: 5 tasks landed, 190 of 520 sized minutes, 37%;/metric: Completed: 5 tasks landed, 190 of 520 sized minutes, 60%;/')"
expect_eq "RO6g a Completed row giving Pace's 60% (pace.time-used) for its own 37% refuses the card, naming Completed and 60" "1||1" \
  "$SC_RC|$SC_OUT|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -cF 'metric Completed: says 60,')"
SC_GOALS3="$(printf '%s\n' "$SC_OWED" | awk '/^goal: / { print "goal: name=shown status=met measure=the user said what they owe — met"
  print "goal: name=asks status=not met measure=the record says an ask is missing — not met"
  print "goal: name=walked status=not measured measure=the walk record — not measured"; next } { print }')"
expect_eq "RO6h precondition: the three-goal sheet holds one goal of each status, and 3 elsewhere (tests.suites-run, the D3 key)" "3|1|1|1|yes" \
  "$(printf '%s\n' "$SC_GOALS3" | /usr/bin/grep -c '^goal: ')|$(printf '%s\n' "$SC_GOALS3" | /usr/bin/grep -c ' status=met ')|$(printf '%s\n' "$SC_GOALS3" | /usr/bin/grep -c ' status=not met ')|$(printf '%s\n' "$SC_GOALS3" | /usr/bin/grep -c ' status=not measured ')|$(printf '%s\n' "$SC_GOALS3" | /usr/bin/grep -q 'decide:D3' && echo yes)"
sc_card "$SC_GOALS3" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^metric: Goals: .*/metric: Goals: 1 of 3 met; 1 not met; 1 not measured yet./')"
expect_eq "RO6i control: a Goals row counting the goal: lines as they are prints (exit 0, nothing on stderr)" "0|" "$SC_RC|$SC_ERR"
sc_card "$SC_GOALS3" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^metric: Goals: .*/metric: Goals: 3 of 3 met./')"
expect_eq "RO6j a Goals row saying 3 of 3 met where 1 is refuses the card, naming Goals, 3 and the 1 met" "1||1" \
  "$SC_RC|$SC_OUT|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -F 'metric Goals: says 3 met' | /usr/bin/grep -cF 'hold 1 met')"
sc_card "$SC_GOALS3" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^metric: Goals: .*/metric: Goals: 1 of 3 met; 2 not met./')"
expect_eq "RO6k a Goals row giving 2 not met where 1 is refuses the card" "1|" "$SC_RC|$SC_OUT"
sc_card "$SC_GOALS3" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^metric: Goals: .*/metric: Goals: 1 of 4 met./')"
expect_eq "RO6l a Goals row giving 4 goals where the sheet has 3 refuses the card" "1|" "$SC_RC|$SC_OUT"
sc_card "$SC_OWED" "$(sc_judge_without "$SC_J_OWED" 'close: 8:40 PM')"
expect_eq "RO7 a judgment whose close rows leave out the sheet's predicted close refuses the card, naming it" "1|yes" \
  "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qF '8:40 PM' && echo yes)"
sc_card "$(printf '%s\n' "$SC_OWED" | sed 's/^close.predicted: .*/close.predicted: -/')" "$(sc_judge_without "$SC_J_OWED" 'close: 8:40 PM')"
expect_eq "RO7b a sheet that predicts no close asks no time of the close rows: the card prints" "0|" "$SC_RC|$SC_ERR"
expect_eq "RO7c precondition: the planted close names its measure and basis after its value" "yes" \
  "$(printf '%s\n' "$SC_OWED" | /usr/bin/grep -q '^close.predicted: 8:40 PM — when the run is expected to end · unit: local time · basis: ' && echo yes)"
sc_card "$SC_OWED" "$SC_J_OWED"
expect_eq "RO7d …and the close rows name the time alone, the value before the measure's words: the card prints" "0|" "$SC_RC|$SC_ERR"
# A task row says what its task's state is: an open task never landed, a finished one never waits.
# fails-when: a row for a held, running, failed or pending task prints saying landed, done, finished, merged or green,
# or a row for a done task prints saying building, waiting, held or running.
SC_J_HELD="$(printf '%s\n' "$SC_J_OWED" | sed 's/^task: 4\/8: .*/task: 4\/8: the skill texts, landed and green/')"
sc_card "$SC_OWED" "$SC_J_HELD"
expect_eq "RO8 a row saying the held 4/8 landed and green refuses the card: exit 1, nothing printed" "1|" "$SC_RC|$SC_OUT"
expect_eq "RO8b …in one line naming the row, its state and the word" "1" \
  "$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -F 'task row 4/8:' | /usr/bin/grep -F 'held' | /usr/bin/grep -cF '"landed"')"
for p in '4/40|a check rewrite, done' '4/7|the width pins, finished' '5/41|the whole regression, green' '8/47|merge into main, merged'; do
  sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | awk -v l="${p%%|*}" -v t="${p#*|}" 'index($0, "task: " l ": ") == 1 { print "task: " l ": " t; next } { print }')"
  expect_eq "RO8c the open task ${p%%|*} written as \"${p#*|}\" refuses the card, naming the row" "1|1" \
    "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -cF "task row ${p%%|*}:")"
done
for p in '4/13|the stragglers, still running' '4/13|the stragglers, waiting on you' '4/13|the stragglers, building' '4/13|the stragglers, held on D3'; do
  sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | awk -v l="${p%%|*}" -v t="${p#*|}" 'index($0, "task: " l ": ") == 1 { print "task: " l ": " t; next } { print }')"
  expect_eq "RO8d the done task 4/13 written as \"${p#*|}\" refuses the card, naming the row" "1|1" \
    "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -cF 'task row 4/13:')"
done
SC_GREENDESC="$(printf '%s\n' "$SC_OWED" | sed 's/^task: id=T41 step=5 state=pending desc=the whole regression at the build head /task: id=T41 step=5 state=pending desc=the whole regression green at the build head /')"
expect_eq "RO8e precondition: the pending T41's own description holds green" "1" "$(printf '%s\n' "$SC_GREENDESC" | /usr/bin/grep -c 'state=pending desc=the whole regression green')"
sc_card "$SC_GREENDESC" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^task: 5\/41: .*/task: 5\/41: The whole regression green at the build head, not landed yet/')"
expect_eq "RO8f control: a row copying its task's own description, and saying not landed, prints (exit 0, nothing on stderr)" "0|" "$SC_RC|$SC_ERR"
sc_card "$SC_OWED" "$SC_J_RANGE"
expect_eq "RO8g control: a range holding open tasks may say some landed, and a step row may say done (RO4, RO4b): the range prints" "0|" "$SC_RC|$SC_ERR"

# ============================================================
section "§SHAPE: a 101-column line, a step row above its tasks, an open task twice or missing — each planted fault is refused"
# ============================================================
# fails-when: any planted fault prints.
sc_check "$SC_OWED" "$SC_WANT_OWED"
expect_eq "SH0 control: the approved card passes the check (exit 0, nothing said)" "0||" "$SC_RC|$SC_OUT|$SC_ERR"
SC_PAD="    • $(printf 'x%.0s' $(seq 95))"
expect_eq "SH1 precondition: the planted line is 101 columns" "101" "$(bionic_cols "$SC_PAD")"
sc_check "$SC_OWED" "$(printf '%s\n' "$SC_WANT_OWED" | awk -v p="$SC_PAD" '{ print } /^  Metrics$/ { print p }')"
expect_eq "SH1b a 101-column row is refused" "1" "$SC_RC"
expect_contains "SH1c …naming its width" "101 columns" "$SC_ERR"
sc_card "$SC_OWED" "$SC_J_OWED
point: $(printf 'y%.0s' $(seq 100))"
expect_eq "SH1d a judgment word wider than the card prints whole, so the verb's own check refuses it: nothing printed" \
  "1|" "$SC_RC|$SC_OUT"
sc_check "$SC_OWED" "$(printf '%s\n' "$SC_WANT_OWED" | awk '/^    ✅ 4\/3–4\/4/ { print "    ⬜ 4: Implement" } { print }')"
expect_eq "SH2 a step row above its own tasks is refused" "1" "$SC_RC"
expect_contains "SH2b …naming the step" "4: " "$SC_ERR"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^task: 4\/3–4\/4: .*/task: 4: Implement, three tasks open\
&/')"
expect_eq "SH2c …and a judgment that writes one is refused the same way: exit 1, nothing printed" "1|yes" \
  "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qF 'sits above its own task' && echo yes)"
sc_check "$SC_OWED" "$(printf '%s\n' "$SC_WANT_OWED" | awk '{ print } /^    ⬜ 4\/40:/ { print }')"
expect_eq "SH3 an open task on two rows is refused" "1" "$SC_RC"
expect_contains "SH3b …naming the task" "4/40" "$SC_ERR"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | awk '{ print } /^task: 4\/40: /')"
expect_eq "SH3c a judgment writing an open task twice is refused" "1|" "$SC_RC|$SC_OUT"
sc_check "$SC_OWED" "$(printf '%s\n' "$SC_WANT_OWED" | /usr/bin/grep -v '^    ⬜ 4/7:')"
expect_eq "SH4 an open task with no row is refused" "1" "$SC_RC"
expect_contains "SH4b …naming the task" "4/7" "$SC_ERR"
sc_card "$SC_OWED" "$(sc_judge_without "$SC_J_OWED" 'task: 4/7: ')"
expect_eq "SH4c a judgment leaving an open task out is refused, naming it" "1|yes" \
  "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qF '4/7' && echo yes)"
sc_check "$SC_OWED" "$(printf '%s\n' "$SC_WANT_OWED" | sed 's/^    • Completed: /    Completed: /')"
expect_eq "SH5 a row with no bullet or icon is refused" "1" "$SC_RC"
expect_contains "SH5b …quoting it" "Completed: 5 tasks landed" "$SC_ERR"
sc_check "$SC_OWED" "$(printf '%s\n' "$SC_WANT_OWED" | awk '/^  Metrics$/ { m = 1 } m && /^$/ { m = 0; next } !m')"
expect_eq "SH6 a section missing is refused" "1" "$SC_RC"
expect_contains "SH6b …naming the section" "Metrics" "$SC_ERR"
sc_card "$SC_OWED" "$SC_J_OWED
point: $(printf 'word %.0s' $(seq 40))end"
SC_WRAP="$SC_OUT"
expect_eq "SH7 a long point folds, its continuation hung under its text, and the card passes" "0" "$SC_RC"
expect_eq "SH7b …every line within the width (SH7 rendered it)" "" "$(sc_wide "$SC_WRAP")"
expect_nonempty "SH7c …the continuation opens six spaces in, under the bullet's text" \
  "$(printf '%s\n' "$SC_WRAP" | /usr/bin/grep -E '^      word ')"

# A task row is one line: the model writes it short. A row too long for the width folds, and the check refuses it.
SC_LONG="open the pull request from wave/42-sitrep-owes to main on the release approval card's word and wait for the merge"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed "s|^task: 4/40: .*|task: 4/40: $SC_LONG|")"
expect_eq "SH8 a task row too long for the width refuses the card: exit 1, nothing printed" "1|" "$SC_RC|$SC_OUT"
expect_contains "SH8b …saying the row spans two lines" "spans two lines" "$SC_ERR"
SC_WRAPPED="$(printf '%s\n' "$SC_WANT_OWED" | awk 'index($0, "    ⬜ 4/40: ") == 1 { i = index($0, ", running"); print substr($0, 1, i - 1); print "       " substr($0, i + 2); next } { print }')"
expect_eq "SH9a precondition: the planted card has the 4/40 row on two lines, one line more than the card" "yes" \
  "$([ "$(printf '%s\n' "$SC_WRAPPED" | wc -l)" -eq $(( $(printf '%s\n' "$SC_WANT_OWED" | wc -l) + 1 )) ] && echo yes)"
sc_check "$SC_OWED" "$SC_WRAPPED"
expect_eq "SH9b a task row continued on a second line is refused" "1" "$SC_RC"
expect_contains "SH9c …saying the row spans two lines" "spans two lines" "$SC_ERR"
SC_WRAPPED2="$(printf '%s\n' "$SC_WANT_OWED" | awk '$0 == "    ✅ 3: Plan, its two tasks landed" { print "    ✅ 3: Plan,"; print "       its two tasks landed"; next } { print }')"
expect_eq "SH9d precondition: the planted card has the 3 row on two lines" "1" "$(printf '%s\n' "$SC_WRAPPED2" | /usr/bin/grep -cx '       its two tasks landed')"
sc_check "$SC_OWED" "$SC_WRAPPED2"
expect_eq "SH9e a finished row continued on a second line is refused too" "1" "$SC_RC"

# ============================================================
section "§WORDS: \"reader\", \"reading\" or \"unmeasured\" in the judgment refuses the card, on any row the judgment writes"
# ============================================================
# fails-when: the card prints "reader" or "no reader for".
for w in 'the reader saw it' 'two readers agree' 'the readings hold' 'a reading of the run' 'the reading is late' 'no reader for the goal' 'The Reader says so'; do
  sc_card "$SC_OWED" "$SC_J_OWED
point: $w"
  expect_eq "WO1 \"$w\" in a point refuses the card: exit 1, nothing printed" "1|" "$SC_RC|$SC_OUT"
done
expect_contains "WO1b …saying the card says review" "review" "$SC_ERR"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^close: depends.*/close: no reader for the close yet/')"
expect_eq "WO2 the word in the close refuses it too" "1|" "$SC_RC|$SC_OUT"
sc_card "$SC_OWED" "$SC_J_OWED
point: I read the sheet; the spreadsheet and the readiness review agree."
expect_eq "WO3 control: read, spreadsheet and readiness are other words, and the card prints" "0|" "$SC_RC|$SC_ERR"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^metric: Goals: .*/metric: Goals: 0 of 1 met; 1 unmeasured./')"
expect_eq "WO4 \"unmeasured\" in the Goals row refuses the card" "1|yes" \
  "$SC_RC|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qF 'not measured' && echo yes)"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^task: 6: Review$/task: 6: Review, no reader yet/')"
expect_eq "WO4b \"reader\" in a task row refuses it too" "1|" "$SC_RC|$SC_OUT"
# fails-when: "reading" with no article before it, or "unmeasured", prints on the card.
for w in 'The structure reading has not run yet.' 'Readings differ.' 'Goals are unmeasured.'; do
  sc_card "$SC_OWED" "$SC_J_OWED
point: $w"
  expect_eq "WO5 \"$w\" in a point refuses the card: exit 1, nothing printed" "1|" "$SC_RC|$SC_OUT"
done
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^call: rule on D3:/call: Rule on D3 before the reading:/')"
expect_eq "WO6 \"reading\" in the call refuses it too" "1|" "$SC_RC|$SC_OUT"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^close: depends/close: Goals stay unmeasured; depends/')"
expect_eq "WO7 \"unmeasured\" in the close refuses it too" "1|" "$SC_RC|$SC_OUT"
sc_card "$SC_OWED" "$SC_J_OWED
point: The structure reading has not run; readers are idle and goals are unmeasured."
expect_eq "WO8 one line with three refused words names each, and each with its own rule" \
  "1|reading:review|readers:review|unmeasured:not measured" \
  "$SC_RC|$(printf '%s\n' "$SC_ERR" | sed -n 's/^.*refused: the judgment says "\([a-z]*\)" .*: the card says \(.*\)$/\1:\2/p' | sed 's/:a goal nobody measures is /:/' | paste -sd'|' -)"
sc_card "$SC_OWED" "$SC_J_OWED
point: Goals are not yet measured; the structure review has not run."
expect_eq "WO9 control: \"not measured\" and \"review\" are the card's words, and the card prints" "0|" "$SC_RC|$SC_ERR"
expect_nonempty "WO9b …on stdout" "$SC_OUT"

# ============================================================
section "§REFUSE: a refused card leaves stdout empty and says every reason on stderr"
# ============================================================
# fails-when: a refused card prints.
sc_card "$SC_OWED" "$(sc_judge_without "$SC_J_OWED" 'ask decide:D3:' | sed 's/^grade: B/grade: G/')
point: the reader said so"
expect_eq "RE1 three faults at once: exit 1, nothing on stdout" "1|" "$SC_RC|$SC_OUT"
expect_eq "RE2 …every reason on stderr, one line each: the dropped ask, the grade and the word" "yes|yes|yes" \
  "$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qF 'decide:D3' && echo yes)|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qF "'G'" && echo yes)|$(printf '%s\n' "$SC_ERR" | /usr/bin/grep -qi 'reader' && echo yes)"
sc_card "$SC_OWED" "$SC_J_OWED"
expect_eq "RE3 control: the judgment with the three faults moved back prints the card, nothing on stderr" "0|" "$SC_RC|$SC_ERR"
expect_nonempty "RE3b …on stdout" "$SC_OUT"

# ============================================================
section "§JUDGMENT: one grade A to F, one to five points, at least one call, one to three closes, and only the tags the card knows"
# ============================================================
# fails-when: a judgment outside its floors prints a card.
sc_j() { sc_card "$SC_OWED" "$1"; printf '%s|%s' "$SC_RC" "$SC_OUT"; }   # <judgment> -> `<rc>|<stdout>`
sc_jrc() { sc_card "$SC_OWED" "$1"; printf '%s' "$SC_RC"; }                  # <judgment> -> its exit code alone
expect_eq "JU1 no grade line" "1|" "$(sc_j "$(sc_judge_without "$SC_J_OWED" 'grade: ')")"
expect_eq "JU2 a grade outside A to F" "1|" "$(sc_j "$(printf '%s\n' "$SC_J_OWED" | sed 's/^grade: B/grade: B+/')")"
expect_eq "JU3 two grade lines" "1|" "$(sc_j "$SC_J_OWED
grade: C")"
expect_eq "JU4 no point" "1|" "$(sc_j "$(sc_judge_without "$SC_J_OWED" 'point: ')")"
expect_eq "JU5 six points" "1|" "$(sc_j "$SC_J_OWED
point: three
point: four
point: five
point: six")"
expect_eq "JU5b control: five points print" "0" "$(sc_jrc "$SC_J_OWED
point: three
point: four
point: five")"
expect_eq "JU6 no call" "1|" "$(sc_j "$(sc_judge_without "$SC_J_OWED" 'call: ')")"
expect_eq "JU7 no close" "1|" "$(sc_j "$(sc_judge_without "$SC_J_OWED" 'close: ')")"
expect_eq "JU8 four close lines" "1|" "$(sc_j "$SC_J_OWED
close: and something else
close: and a third thing")"
expect_eq "JU8b control: three close lines print" "0" "$(sc_jrc "$SC_J_OWED
close: and something else")"
expect_eq "JU9 a tag the card does not know" "1|" "$(sc_j "$SC_J_OWED
verdict: fine")"
expect_eq "JU10 two ask lines for one key" "1|" "$(sc_j "$SC_J_OWED
ask decide:D3: D3 again; it holds 4/8 — recommend fix")"
expect_eq "JU11 each grade A to F prints" "0 0 0 0 0 0" \
  "$(for g in A B C D E F; do sc_jrc "$(printf '%s\n' "$SC_J_OWED" | sed "s/^grade: B/grade: $g/")"; echo; done | paste -sd' ' -)"

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
SV_J="call: approve the release once 4/2 lands.
task: 0: Configure
task: 1: Scope
task: 2: Design
task: 3: Plan
task: 4/1: the first row landed
task: 4/2: the second row, building
task: 5: Verify
task: 6: Review
task: 7: Document
task: 8/3: merge it, waiting on your approval of the release
task: 9: Close-out
metric: Completed: $(sv_m work.landed)
metric: Pace: $(sv_m pace.work-landed) of the work landed in $(sv_m pace.time-used) of the forecast time
metric: Correctness: $(sv_m tests.suites-run)
metric: Waste: $(sv_m waste.runs-discarded) suite runs discarded
metric: Goals: as the goal lines say
grade: C
point: One task is in flight and nothing is red.
ask approve:release: the release approval, which holds 8/3 — recommend approve once 4/2 lands
close: $(sv_m close.predicted), if 4/2 lands first time."
expect_nonempty "VE2c precondition: the verb's sheet predicts a close the judgment copies" "$(sv_fact close.predicted)"
sv_run card "$SV_P" <<< "$SV_J"
expect_eq "VE3 sitrep card prints the card (exit 0, nothing on stderr)" "0|" "$SV_RC|$SV_ERR"
expect_eq "VE3b …its head from the run's own sheet" "Sitrep · $(basename "$SV_R") 9.9.0 · wave 2 · Tuesday 3:00 PM" "$(printf '%s\n' "$SV_OUT" | head -1)"
expect_eq "VE3c …the verb's card is the renderer's over the same sheet and judgment, byte for byte" \
  "$(printf '%s\n' "$SV_J" | bash "$CARD_SH" sitrep "$TMPROOT/verb-sheet")" "$SV_OUT"
expect_eq "VE3d …each task row's icon from the run's own sheet: the landed task done, the building and the held ones open" \
  "    ✅ 4/1: The first row landed|    ⬜ 4/2: The second row, building|    ⬜ 8/3: Merge it, waiting on your approval of the release" \
  "$(sc_under "$SV_OUT" "Task list" | /usr/bin/grep -F '/' | paste -sd'|' -)"
sv_run card "$SV_P" <<< "$(printf '%s\n' "$SV_J" | sed 's/^metric: Completed: .*/metric: Completed: 2 of 3 tasks landed, 67%./')"
expect_eq "VE4 the verb refuses a Completed row the run's sheet does not hold: exit 1, stdout empty, naming 67" "1||yes" \
  "$SV_RC|$SV_OUT|$(printf '%s\n' "$SV_ERR" | /usr/bin/grep -qF '67' && echo yes)"
sv_run card "$SV_P" <<< "$(sc_judge_without "$SV_J" 'ask approve:release:')"
expect_eq "VE5 the verb refuses a judgment that drops the open ask: exit 1, stdout empty" "1|" "$SV_RC|$SV_OUT"
expect_contains "VE5b …the renderer's reason reaching stderr" "approve:release" "$SV_ERR"
sv_run card --line "$SV_P" <<< "$SV_J"
expect_eq "VE6 card with --line is a usage error (2)" "2" "$SV_RC"

# THE SHEET THE JUDGMENT WAS WRITTEN FROM. The card is checked against the sheet `sitrep` printed and saved, while it is
# under 10 minutes old, so a clock that moves while the model writes never refuses a true judgment; the asks are read
# fresh, so an ask opened since is still owed.
# fails-when: the card verb recomputes the sheet (a judgment true at 3:00 PM is refused at 3:02 PM), draws from a sheet
# 10 minutes old or none, or takes the asks from the saved sheet.
SV_SAVED="$SV_R/.bionic/tmp/sitrep/wave-02-fx.sheet"
sv_run "$SV_P" < /dev/null
expect_eq "VE7 sitrep saves the sheet it prints, byte for byte, beside its stamp" "0|yes|yes" \
  "$SV_RC|$([ -f "$SV_SAVED" ] && [ "$(cat "$SV_SAVED")" = "$SV_OUT" ] && echo yes)|$([ -f "$SV_SAVED.at" ] && echo yes)"
SV_AT=$((SV_NOW + 120)) sv_run "$SV_P" < /dev/null
SV_LATER="$SV_OUT"
sv_run "$SV_P" < /dev/null
expect_eq "VE8 precondition: two minutes on, the run's sheet predicts another close than the judgment copied" "yes|yes" \
  "$([ -n "$(sv_fact close.predicted)" ] && echo yes)|$(printf '%s\n' "$SV_LATER" | /usr/bin/grep -q "^close.predicted: " && ! printf '%s\n' "$SV_LATER" | /usr/bin/grep -qxF "close.predicted: $(sv_fact close.predicted)" && echo yes)"
SV_AT=$((SV_NOW + 120)) sv_run card "$SV_P" <<< "$SV_J"
expect_eq "VE8b the judgment written from the saved sheet prints its card two minutes later (exit 0, nothing on stderr)" "0|" "$SV_RC|$SV_ERR"
expect_eq "VE8c …its head the saved sheet's clock, 3:00 PM" "Sitrep · $(basename "$SV_R") 9.9.0 · wave 2 · Tuesday 3:00 PM" \
  "$(printf '%s\n' "$SV_OUT" | head -1)"
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
expect_eq "VE10 an ask opened after the sheet was saved is owed: the judgment written before it is refused" "1||yes" \
  "$SV_RC|$SV_OUT|$(printf '%s\n' "$SV_ERR" | /usr/bin/grep -qF 'approve:merge' && echo yes)"
SV_AT=$((SV_NOW + 60)) sv_run card "$SV_P" <<< "$SV_J
ask approve:merge: approve the merge into main — recommend approve once 4/2 lands"
expect_eq "VE10b …and a judgment answering it prints, the new ask under Blocked on you" "0|    • Approve the merge into main — recommend approve once 4/2 lands" \
  "$SV_RC|$(sc_under "$SV_OUT" "Blocked on you" | /usr/bin/grep -F 'merge into main')"

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
sk_unshown() {  # <skill file> -> each line that shows the card yet lets other text through: not exactly as printed, or not one fence
  awk '{ l = tolower($0) } l ~ /(^|[^a-z])shows?([^a-z]|$)/ && l ~ /card/ && l !~ /never/ && l !~ /description:/ \
    && (l !~ /exactly as printed/ || l !~ /one fenced code block/ || l !~ /nothing after/) { print }' "$1"
}
SK_TAGS="$(sk_tags)"
expect_eq "SK0 the verb names the tags it takes (the extractor reads card.sh's own refusal)" \
  "call:|task:|metric:|grade:|point:|ask <key>:|ask +:|close:" "$(printf '%s\n' "$SK_TAGS" | paste -sd'|' -)"
SK_MISS=""
while IFS= read -r t; do /usr/bin/grep -qF -- "\`$t" "$SK_SKILL" || SK_MISS="$SK_MISS $t"; done <<< "$SK_TAGS"
expect_empty "SK1 the skill names every tag the verb takes, each in code (SK0 read them)" "$SK_MISS"
expect_eq "SK2 the skill shows the card exactly as printed, inside one fenced code block, nothing after it" "1" \
  "$(/usr/bin/grep -i 'card' "$SK_SKILL" | /usr/bin/grep -i 'exactly as printed' | /usr/bin/grep -i 'one fenced code block' | /usr/bin/grep -ci 'nothing after')"
expect_empty "SK2b …and no other line shows the card some other way (SK2 read the same file)" "$(sk_unshown "$SK_SKILL")"
expect_eq "SK3 rc 1: the skill fixes the judgment and runs it again, never shows a refused card, never writes one by hand" "1" \
  "$(/usr/bin/grep -F 'rc 1' "$SK_SKILL" | /usr/bin/grep -i 'never show a refused card' | /usr/bin/grep -ci 'never write a card by hand')"
cp "$SK_SKILL" "$TMPROOT/sk-plant.md"; printf '%s\n' 'Show the card to the user in your own words.' >> "$TMPROOT/sk-plant.md"
expect_eq "SK4 a planted paraphrase of the card is found" "Show the card to the user in your own words." "$(sk_unshown "$TMPROOT/sk-plant.md")"
sed 's/`ask +:`/the extra ask tag/g' "$SK_SKILL" > "$TMPROOT/sk-plant.md"
SK_MISS=""
while IFS= read -r t; do /usr/bin/grep -qF -- "\`$t" "$TMPROOT/sk-plant.md" || SK_MISS="$SK_MISS $t"; done <<< "$SK_TAGS"
expect_eq "SK5 a copy with one tag left out is found" " ask +:" "$SK_MISS"

finish
