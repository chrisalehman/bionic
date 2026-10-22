#!/bin/bash
# Tests for the sitrep card: `payload/scripts/card.sh sitrep` and `sitrep-check`, and the verb that draws it,
# `hooks/session-poker.sh sitrep card [<plan>]`.
#
# THE CARD IS DRAWN, NEVER WRITTEN. The verb gathers the fact sheet; the model writes only the judgment, tagged lines
# on stdin (call:, grade:, point:, ask <key>:, ask +:, close:); card.sh lays out the seven sections from both, then
# holds the rendered text to the card's shape before it prints a byte. A card that drops an open ask, names an ask the
# register lacks, says "reader", runs a line past 100 columns, leaves a row with no bullet or icon, puts a step row
# above its own tasks, or gives an open task no row or two is refused: every reason on stderr, nothing on stdout, rc 1.
#
#   §SECTIONS  seven sections in order, every row bulleted or iconed, the Task list collapsed by rule, no options
#   §CALL      the clean card's call names no ask and Blocked on you is one row; the owed card's call names one
#   §FLOOR     an open ask key the judgment leaves out refuses the card
#   §SHAPE     a 101-column line, a step row above its tasks, an open task twice or not at all: each refused
#   §WORDS     "reader", "reading" and their kin, or "unmeasured", in the judgment refuse the card, each word with its rule
#   §REFUSE    a refused card prints nothing on stdout, every reason on stderr
#   §JUDGMENT  the judgment's own floors: one grade A to F, one to five points, a call, one close, known tags
#   §HEAD      the head names the wave only when the run has one
#   §VERB      the verb draws the card from the run's own sheet, and settles a decision the ledger ruled first
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
metric.completed: 5 of 10 tasks (50%)
metric.pace: 5 tasks in 3 h 50 min; the plan allowed 3 h 10 min for them
metric.correctness: 1 test red; no reviews yet; 0 open findings
metric.waste: 2 tasks dropped; 0 of 25 suite runs discarded; 60 minutes idle
metric.goals: 0 of 3 met; 3 not measured yet
goal: name=owed status=not measured measure=the user says what they owe — not measured
close.predicted: 8:40 PM
close.forecast: 6:50 PM
close.basis: 300 min of work left
review: question=evidence scope=whole result=running at=- open-findings=0 record=-'
SC_ASKS='ask: key=decide:D3 holds=the merge title=D3 · waive or fix raised=1:00 PM
ask: key=approve:release holds=T47 title=approval: release raised=1:05 PM'
SC_OWED="$SC_BASE
$SC_ASKS"
SC_CLEAN="$SC_BASE"

SC_J_OWED='call: Rule on D3: the merge waits on it, and nothing else is left to build.
grade: B
point: The last build task is running; once it lands, the regression runs, about 25 minutes.
point: The run is 1 h 50 min over plan, mostly the test cull.
ask decide:D3: D3 · waive the failed review or fix first — recommend waive
ask approve:release: approval of release 1.24.0 — recommend approve once the regression is green
close: Depends on the regression passing first time; a red adds a fix task, about 45 minutes.'
SC_J_CLEAN='call: Nothing is owed: let T40 land, then fix the width pins.
grade: B
point: The last build task is running; once it lands, the regression runs, about 25 minutes.
close: Depends on the regression passing first time; a red adds a fix task, about 45 minutes.'

SC_WANT_OWED='Sitrep · bionic 1.24.0 · wave 41 · Tuesday 2:40 PM

  Call to action
    • Rule on D3: the merge waits on it, and nothing else is left to build.

  Task list
    ✅ 0: Configure
    ✅ 1: Scope
    ✅ 2: Design
    ✅ 3: Plan — 2 tasks
    ✅ 4/3–4/13: 3 tasks finished
    ⬜ 4/40: a check rewrite never passes unjudged — running
    ⬜ 4/7: the width pins — red
    ⬜ 4/8: the skill texts — held on D3
    ⬜ 5/41: the whole regression at the build head
    ⬜ 6: Review
    ⬜ 7: Document
    ⬜ 8/47: merge into main — waits on the release card
    ⬜ 9: Close-out

  Metrics
    • Completed: 5 of 10 tasks (50%)
    • Pace: 5 tasks in 3 h 50 min; the plan allowed 3 h 10 min for them
    • Correctness: 1 test red; no reviews yet; 0 open findings
    • Waste: 2 tasks dropped; 0 of 25 suite runs discarded; 60 minutes idle
    • Goals: 0 of 3 met; 3 not measured yet

  Assessment: B
    • The last build task is running; once it lands, the regression runs, about 25 minutes.
    • The run is 1 h 50 min over plan, mostly the test cull.

  Blocked on you
    • D3 · waive the failed review or fix first — holds the merge — recommend waive
    • approval of release 1.24.0 — holds T47 — recommend approve once the regression is green

  Predicted close
    • 8:40 PM, against a 6:50 PM forecast
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

# ============================================================
section "§SECTIONS: seven sections in order, every row bulleted or iconed, the Task list collapsed by rule, no options"
# ============================================================
# fails-when: a section is missing or out of order, a bare row, a step row above its tasks, or options print.
sc_card "$SC_OWED" "$SC_J_OWED"
expect_eq "SE1 the owed fixture renders (exit 0, nothing on stderr)" "0|" "$SC_RC|$SC_ERR"
expect_eq "SE2 …the whole card, as the user approved its layout" "$SC_WANT_OWED" "$SC_OUT"
expect_eq "SE3 the head, then the six labelled sections in their order" \
  "Call to action|Task list|Metrics|Assessment: B|Blocked on you|Predicted close" "$(sc_labels "$SC_OUT")"
expect_eq "SE4 every row under a section opens on a bullet or an icon (SE3 read the labels from the same card)" "" \
  "$(printf '%s\n' "$SC_OUT" | awk 'NR > 1 && /^    / && !/^    (• |✅ |⬜ )/')"
expect_eq "SE5 a finished step is one row, the task count after it when it had tasks" "    ✅ 0: Configure|    ✅ 3: Plan — 2 tasks" \
  "$(sc_under "$SC_OUT" "Task list" | /usr/bin/grep -E '^    ✅ [03]: ' | paste -sd'|' -)"
expect_eq "SE6 a running step's finished tasks are one row with a range label, its open tasks one row each" \
  "    ✅ 4/3–4/13: 3 tasks finished|    ⬜ 4/40: a check rewrite never passes unjudged — running|    ⬜ 4/7: the width pins — red|    ⬜ 4/8: the skill texts — held on D3" \
  "$(sc_under "$SC_OUT" "Task list" | /usr/bin/grep -F '4/' | paste -sd'|' -)"
expect_eq "SE6b …and no step row for the running step (SE6 read its tasks from the same list)" "" \
  "$(sc_under "$SC_OUT" "Task list" | /usr/bin/grep -E '^    (✅|⬜) 4: ')"
SC_ONE="$(printf '%s\n' "$SC_OWED" | /usr/bin/grep -v -E '^task: id=T(13|4) ')"
sc_card "$SC_ONE" "$SC_J_OWED"
expect_eq "SE7 a single finished task in a running step prints as its own row" "0|    ✅ 4/3: The register" \
  "$SC_RC|$(sc_under "$SC_OUT" "Task list" | /usr/bin/grep -F '✅ 4/')"
SC_J_OPT="$(printf '%s\n' "$SC_J_OWED" | sed 's/^ask decide:D3: .*/ask decide:D3: D3 · 1. waive the failed review 2. fix first — recommend 1/')"
sc_card "$SC_OWED" "$SC_J_OPT"
expect_eq "SE8 an ask written as numbered options refuses the card: exit 1, nothing printed" "1|" "$SC_RC|$SC_OUT"
expect_contains "SE8b …saying the card never prints a decision's options" "options" "$SC_ERR"
expect_absent "SE8c the approved card prints no numbered option (SE2 read the whole card)" "1. waive" "$SC_WANT_OWED"

# ============================================================
section "§CALL: the clean card's call names no ask and Blocked on you has one row; the owed card's call names one"
# ============================================================
# fails-when: the clean card shows an ask, or the owed call names none.
sc_card "$SC_CLEAN" "$SC_J_CLEAN"
expect_eq "CA1 the clean fixture renders (exit 0, nothing on stderr)" "0|" "$SC_RC|$SC_ERR"
expect_eq "CA2 …Blocked on you is the one row saying nothing is owed" "    • Nothing: no decision or action is owed right now." \
  "$(sc_under "$SC_OUT" "Blocked on you")"
expect_eq "CA3 …and the call names no ask key or id of the owed fixture (CA2 read the same card)" "" \
  "$(sc_under "$SC_OUT" "Call to action" | /usr/bin/grep -E 'D3|release|decide:|approve:')"
sc_card "$SC_OWED" "$SC_J_OWED"
expect_contains "CA4 the owed card's call names an open ask, D3" "D3" "$(sc_under "$SC_OUT" "Call to action")"
SC_J_NONAME="$(printf '%s\n' "$SC_J_OWED" | sed 's/^call: .*/call: Keep building; the regression is next./')"
sc_card "$SC_OWED" "$SC_J_NONAME"
expect_eq "CA5 with asks open, a call naming none of them refuses the card: exit 1, nothing printed" "1|" "$SC_RC|$SC_OUT"
expect_contains "CA5b …naming the asks it could have named" "D3" "$SC_ERR"
SC_J_REL="$(printf '%s\n' "$SC_J_OWED" | sed 's/^call: .*/call: Approve the release once the regression is green./')"
sc_card "$SC_OWED" "$SC_J_REL"
expect_eq "CA6 a call naming the other ask by its id (approve:release names release) passes" "0|" "$SC_RC|$SC_ERR"
SC_J_D30="$(printf '%s\n' "$SC_J_OWED" | sed 's/^call: .*/call: Rule on D30 when it comes./')"
sc_card "$SC_OWED" "$SC_J_D30"
expect_eq "CA7 an id inside a longer word names nothing: D30 is not D3" "1|" "$SC_RC|$SC_OUT"

# ============================================================
section "§FLOOR: judgment that drops an open ask refuses the card"
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
expect_eq "FL3 an ask the register lacks, added with ask +:, prints under Blocked on you" \
  "0|    • the operator owes a gate act outside the run" \
  "$SC_RC|$(sc_under "$SC_OUT" "Blocked on you" | tail -1)"
sc_card "$SC_OWED" "$(sc_judge_without "$SC_J_OWED" 'ask decide:D3:' | sed 's/^call: .*/call: Approve the release./')
ask decide:D3: D3 · waive or fix"
expect_eq "FL4 an ask line with no recommended answer refuses the card" "1|" "$SC_RC|$SC_OUT"
expect_contains "FL4b …saying what is missing" "recommend" "$SC_ERR"

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
sc_check "$SC_OWED" "$(printf '%s\n' "$SC_WANT_OWED" | awk '/^    ✅ 4\/3–4\/13/ { print "    ⬜ 4: Implement" } { print }')"
expect_eq "SH2 a step row above its own tasks is refused" "1" "$SC_RC"
expect_contains "SH2b …naming the step" "4: " "$SC_ERR"
SC_DONE4="$(printf '%s\n' "$SC_OWED" | sed 's/^step: n=4 name=Implement state=running/step: n=4 name=Implement state=done/')"
sc_card "$SC_DONE4" "$SC_J_OWED"
expect_eq "SH2c a step the run has finished that still holds open tasks is drawn as a running step: the card prints (exit 0), no step row for 4, its open tasks on their own rows" "0|0|1|1" \
  "$SC_RC|$(printf '%s\n' "$SC_OUT" | /usr/bin/grep -c '^    [✅⬜] 4: ')|$(printf '%s\n' "$SC_OUT" | /usr/bin/grep -c '^    ⬜ 4/40: ')|$(printf '%s\n' "$SC_OUT" | /usr/bin/grep -c '^    ✅ 4/3–4/13: 3 tasks finished$')"
SC_PASSED="$(printf '%s\n' "$SC_OWED" | sed -e 's/^\(step: n=[4567] name=[A-Za-z]* state=\)[a-z]*/\1done/')"
expect_eq "SH2d precondition: the fixture is at a later step, steps 4 to 7 done, with 5/41 still pending" "4|1" \
  "$(printf '%s\n' "$SC_PASSED" | /usr/bin/grep -c '^step: n=[4567] .* state=done')|$(printf '%s\n' "$SC_PASSED" | /usr/bin/grep -c '^task: id=T41 step=5 state=pending')"
sc_card "$SC_PASSED" "$SC_J_OWED"
expect_eq "SH2e a passed step with an open task draws no step row above it: the card prints, 5/41 on its own row, no row for step 5, and the finished steps without tasks stay one row" "0|1|0|1" \
  "$SC_RC|$(printf '%s\n' "$SC_OUT" | /usr/bin/grep -c '^    ⬜ 5/41: ')|$(printf '%s\n' "$SC_OUT" | /usr/bin/grep -c '^    [✅⬜] 5: ')|$(printf '%s\n' "$SC_OUT" | /usr/bin/grep -c '^    ✅ 6: Review$')"
sc_check "$SC_OWED" "$(printf '%s\n' "$SC_WANT_OWED" | awk '{ print } /^    ⬜ 4\/40:/ { print }')"
expect_eq "SH3 an open task on two rows is refused" "1" "$SC_RC"
expect_contains "SH3b …naming the task" "4/40" "$SC_ERR"
sc_card "$(printf '%s\n' "$SC_OWED" | awk '{ print } /^task: id=T40 /')" "$SC_J_OWED"
expect_eq "SH3c a sheet listing an open task twice draws two rows, and the card is refused" "1|" "$SC_RC|$SC_OUT"
sc_check "$SC_OWED" "$(printf '%s\n' "$SC_WANT_OWED" | /usr/bin/grep -v '^    ⬜ 4/7:')"
expect_eq "SH4 an open task with no row is refused" "1" "$SC_RC"
expect_contains "SH4b …naming the task" "4/7" "$SC_ERR"
sc_check "$SC_OWED" "$(printf '%s\n' "$SC_WANT_OWED" | sed 's/^    • Completed: /    Completed: /')"
expect_eq "SH5 a row with no bullet or icon is refused" "1" "$SC_RC"
expect_contains "SH5b …quoting it" "Completed: 5 of 10" "$SC_ERR"
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

# A task row is one line. Its description is cut at a word and ends in "…" so the label, the glyph and the note print
# whole; the check refuses a row that spans two lines.
SC_LONG="Open the pull request from wave/42-sitrep-owes to main on the release approval card's word and wait for the merge"
SC_LONGSHEET="$(printf '%s\n' "$SC_OWED" | sed "s|desc=a check rewrite never passes unjudged|desc=$SC_LONG|")"
sc_card "$SC_LONGSHEET" "$SC_J_OWED"
SC_LONGCARD="$SC_OUT"
SC_ROW="$(printf '%s\n' "$SC_LONGCARD" | /usr/bin/grep -F '    ⬜ 4/40: ')"
expect_eq "SH8 a task description too long for its row: the card passes (exit 0), the open task on exactly one row" "0|1" \
  "$SC_RC|$(printf '%s\n' "$SC_LONGCARD" | /usr/bin/grep -c '^    ⬜ 4/40: ')"
expect_eq "SH8b …the line after it is the next task's own row, not a continuation" "    ⬜ 4/7: the width pins — red" \
  "$(printf '%s\n' "$SC_LONGCARD" | awk 'f { print; exit } index($0, "    ⬜ 4/40: ") == 1 { f = 1 }')"
expect_eq "SH8c …the description ends in an ellipsis before the note, which prints whole" "yes" \
  "$([ "${SC_ROW%… — running}" != "$SC_ROW" ] && echo yes)"
SC_CUT="${SC_ROW#    ⬜ 4/40: }"; SC_CUT="${SC_CUT%… — running}"
expect_eq "SH8d …cut at a word: what is left is the description's start, not empty, and the next character is a space" "yes|yes" \
  "$([ -n "$SC_CUT" ] && [ "${SC_LONG:0:${#SC_CUT}}" = "$SC_CUT" ] && echo yes)|$([ "${SC_LONG:${#SC_CUT}:1}" = " " ] && echo yes)"
SC_NEXTW="${SC_LONG:$((${#SC_CUT} + 1))}"; SC_NEXTW="${SC_NEXTW%% *}"
_bionic_cols_into "    ⬜ 4/40: $SC_CUT ${SC_NEXTW}… — running"
expect_eq "SH8e …and not cut short: the next word would not have fitted in $BIONIC_LINE_WIDTH columns" "yes" \
  "$([ "$BIONIC_COLS" -gt "$BIONIC_LINE_WIDTH" ] && echo yes)"
expect_eq "SH8f …every line of the card is within the width" "" "$(sc_wide "$SC_LONGCARD")"
sc_check "$SC_LONGSHEET" "$SC_LONGCARD"
expect_eq "SH9 control: that card passes the check (exit 0, nothing said)" "0||" "$SC_RC|$SC_OUT|$SC_ERR"
SC_WRAPPED="$(printf '%s\n' "$SC_LONGCARD" | awk 'index($0, "    ⬜ 4/40: ") == 1 { i = index($0, " — running"); print substr($0, 1, i - 1); print "       " substr($0, i + 1); next } { print }')"
expect_eq "SH9a precondition: the planted card has the 4/40 row on two lines, one line more than the card" "yes" \
  "$([ "$(printf '%s\n' "$SC_WRAPPED" | wc -l)" -eq $(( $(printf '%s\n' "$SC_LONGCARD" | wc -l) + 1 )) ] && echo yes)"
sc_check "$SC_LONGSHEET" "$SC_WRAPPED"
expect_eq "SH9b a task row continued on a second line is refused" "1" "$SC_RC"
expect_contains "SH9c …saying the row spans two lines" "spans two lines" "$SC_ERR"
SC_WRAPPED2="$(printf '%s\n' "$SC_WANT_OWED" | awk '$0 == "    ✅ 3: Plan — 2 tasks" { print "    ✅ 3: Plan"; print "       — 2 tasks"; next } { print }')"
sc_check "$SC_OWED" "$SC_WRAPPED2"
expect_eq "SH9d a finished row continued on a second line is refused too" "1" "$SC_RC"
SC_LONGDONE="$(printf '%s\n' "$SC_OWED" | sed -e "s|^task: id=T13 step=4 state=done|task: id=T13 step=4 state=running|" -e "s|^task: id=T4 step=4 state=done|task: id=T4 step=4 state=running|" -e "s|desc=The register|desc=$SC_LONG $SC_LONG|")"
sc_card "$SC_LONGDONE" "$SC_J_OWED"
expect_eq "SH10 a finished task's row, alone in its step, is one line too: within the width, ending in an ellipsis" "0||yes" \
  "$SC_RC|$(sc_wide "$SC_OUT")|$(printf '%s\n' "$SC_OUT" | /usr/bin/grep -F '    ✅ 4/3: ' | /usr/bin/grep -c '…$' | sed 's/^1$/yes/')"

# ============================================================
section "§WORDS: \"reader\", \"reading\" or \"unmeasured\" in the judgment refuses the card; an unmeasured goal prints \"not measured\""
# ============================================================
# fails-when: the card prints "reader" or "no reader for".
for w in 'the reader saw it' 'two readers agree' 'the readings hold' 'a reading of the run' 'the reading is late' 'no reader for the goal' 'The Reader says so'; do
  sc_card "$SC_OWED" "$SC_J_OWED
point: $w"
  expect_eq "WO1 \"$w\" in a point refuses the card: exit 1, nothing printed" "1|" "$SC_RC|$SC_OUT"
done
expect_contains "WO1b …saying the card says review" "review" "$SC_ERR"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^close: .*/close: no reader for the close yet/')"
expect_eq "WO2 the word in the close refuses it too" "1|" "$SC_RC|$SC_OUT"
sc_card "$SC_OWED" "$SC_J_OWED
point: I read the sheet; the spreadsheet and the readiness review agree."
expect_eq "WO3 control: read, spreadsheet and readiness are other words, and the card prints" "0|" "$SC_RC|$SC_ERR"
expect_eq "WO4 a goal nobody measures says not measured on the card" "    • Goals: 0 of 3 met; 3 not measured yet" \
  "$(sc_under "$SC_OUT" Metrics | /usr/bin/grep -F 'Goals: ')"
expect_absent "WO4b …and the card says no reader (WO4 read the same card)" "reader" "$SC_OUT"
# fails-when: "reading" with no article before it, or "unmeasured", prints on the card.
for w in 'The structure reading has not run yet.' 'Readings differ.' 'Goals are unmeasured.'; do
  sc_card "$SC_OWED" "$SC_J_OWED
point: $w"
  expect_eq "WO5 \"$w\" in a point refuses the card: exit 1, nothing printed" "1|" "$SC_RC|$SC_OUT"
done
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^call: Rule on D3:/call: Rule on D3 before the reading:/')"
expect_eq "WO6 \"reading\" in the call refuses it too" "1|" "$SC_RC|$SC_OUT"
sc_card "$SC_OWED" "$(printf '%s\n' "$SC_J_OWED" | sed 's/^close: Depends/close: Goals stay unmeasured; depends/')"
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
section "§JUDGMENT: one grade A to F, one to five points, at least one call, one close, and only the tags the card knows"
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
expect_eq "JU8 two close lines" "1|" "$(sc_j "$SC_J_OWED
close: and something else")"
expect_eq "JU9 a tag the card does not know" "1|" "$(sc_j "$SC_J_OWED
verdict: fine")"
expect_eq "JU10 two ask lines for one key" "1|" "$(sc_j "$SC_J_OWED
ask decide:D3: D3 again — recommend fix")"
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
sv_run() {  # <args after `sitrep`…> [stdin from the caller] -> SV_RC, SV_OUT, SV_ERR
  SV_RC=0
  ( cd "$SV_R" && exec env CLAUDE_CODE_SESSION_ID="$SV_SID" BIONIC_NOW_EPOCH="$SV_NOW" BIONIC_GATE_DIR="$SV_GATE" \
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
SV_J='call: Approve the release once T2 lands.
grade: C
point: One task is in flight and nothing is red.
ask approve:release: the release approval — recommend approve once T2 lands
close: Depends on T2 landing first time.'
sv_run card "$SV_P" <<< "$SV_J"
expect_eq "VE3 sitrep card prints the card (exit 0, nothing on stderr)" "0|" "$SV_RC|$SV_ERR"
expect_eq "VE3b …its head from the run's own sheet" "Sitrep · $(basename "$SV_R") 9.9.0 · wave 2 · Tuesday 3:00 PM" "$(printf '%s\n' "$SV_OUT" | head -1)"
expect_eq "VE3c …the verb's card is the renderer's over the same sheet and judgment, byte for byte" \
  "$(printf '%s\n' "$SV_J" | bash "$CARD_SH" sitrep "$TMPROOT/verb-sheet")" "$SV_OUT"
expect_eq "VE3d …its tasks from the sheet, each open one on its own row" "    ✅ 4/1: The first row|    ⬜ 4/2: The second row — building|    ⬜ 8/3: Merge it — waits on your approval of release" \
  "$(sc_under "$SV_OUT" "Task list" | /usr/bin/grep -F '/' | paste -sd'|' -)"
expect_eq "VE4 a goal nobody measures reads not measured on the card's Goals row" "    • Goals: 0 of 1 met; 1 not measured yet" \
  "$(sc_under "$SV_OUT" Metrics | /usr/bin/grep -F 'Goals: ')"
expect_absent "VE4b …and the card says no reader (VE4 read the same card)" "reader" "$SV_OUT"
sv_run card "$SV_P" <<< "$(sc_judge_without "$SV_J" 'ask approve:release:')"
expect_eq "VE5 the verb refuses a judgment that drops the open ask: exit 1, stdout empty" "1|" "$SV_RC|$SV_OUT"
expect_contains "VE5b …the renderer's reason reaching stderr" "approve:release" "$SV_ERR"
sv_run card --line "$SV_P" <<< "$SV_J"
expect_eq "VE6 card with --line is a usage error (2)" "2" "$SV_RC"

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
  "call:|grade:|point:|ask <key>:|ask +:|close:" "$(printf '%s\n' "$SK_TAGS" | paste -sd'|' -)"
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
