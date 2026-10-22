#!/bin/bash
# Tests for the four run states the sitrep card is read in, each reached by playing a small run forward through the
# real commands (tests/lib/rehearsal.sh `rehearse`), never by writing a state's files.
#
#   §FAILED-REVIEW    the build landed, a whole review registered failing and close-out refused at Step 8: the sheet
#                     owes the waiver and the held merge
#   §RELEASE-WAITING  the release approval card rendered and waiting on its reply: the sheet owes what the card put
#   §STOP-RULE        a stop-rule decision put with a row reading its approval: the sheet owes the decision
#   §CLEAN            mid-build, nothing owed: the sheet says so
#   §TRUE             across the four: the person accepting the release reads a pace taken in minutes, a close that
#                     is not weeks out, a held task naming what it waits on, and a card head with no invented wave
#   §FACTS            across the four: three goals declared, met, not met and not measured; a close at 1× under three
#                     landings; a review counted once by its latest result; the suites and the whole run named; a
#                     held task naming every read it waits on
#
# EACH SECTION, ONE SHAPE. The sandbox's own `hooks/session-poker.sh sitrep <plan>` prints the sheet, whose `ask:`
# lines are exactly the state's asks; a judgment written from the sheet, answering every open ask, renders through
# `sitrep card` (rc 0, every line at most 100 columns); a judgment that drops one is refused (rc 1, stdout empty). The
# clean state has no ask to drop, so its refusal is a judgment naming an ask the register lacks, the same floor read
# from the other side.
#
# FIXTURE FIDELITY: the sandbox is tests/lib/door.sh's, a real repository carrying the plugin's hooks and scripts, a
# plan in its Step-3 shape and the release check's closure. Every later state is a command's: the poker's verbs,
# the door's landing, the sweeper's ack, close-out. What `rehearse` writes by hand is what a run's people and agents
# write by hand: the plan's prose, a review's record, a row's code, a criterion's evidence. Each command it runs is
# logged beside the sandbox (`rehearsal.log`), and each section reads the commands its state turns on from that log.
#
# ANTI-VACUITY: a state that cannot be reached stops its section before the sheet is read, asserting the failure.
# Every empty read (no ask, no wide line, an empty stdout) stands beside a non-empty read through the same reader in
# the same section.
#
# Usage: bash tests/rehearsal.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
RH_LOADED=0
# shellcheck source=/dev/null
. "$(dirname "$0")/lib/rehearsal.sh" && RH_LOADED=1
[ -n "${WORLD_ROOT:-}" ] || . "$(dirname "$0")/lib/world.sh"
# shellcheck source=/dev/null
. "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/width.sh"

# rt_state <state> -> RT_RC, RT_PLAN, RT_ROOT, RT_LOG of `rehearse <state>` into its own directory under WORLD_ROOT
rt_state() {
  RT_RC=0; RT_PLAN=""; RT_ROOT=""; RT_LOG="$WORLD_ROOT/$1/rehearsal.log"
  if [ "$RH_LOADED" = 1 ]; then
    RT_PLAN="$(rehearse "$1" "$WORLD_ROOT/$1" 2> "$WORLD_ROOT/$1.err")" || RT_RC=$?
  else
    RT_RC=127
  fi
  RT_ROOT="${RT_PLAN%/.bionic/docs/plans/*}"
  [ "$RT_RC" = 0 ] || { printf '    rehearse %s said:\n' "$1"; sed 's/^/    | /' "$WORLD_ROOT/$1.err" 2>/dev/null | tail -25; }
}
# rt_poker <args…> [stdin] -> RT_OUT, RT_ERR, RT_PRC of the sandbox's own poker, run from its root as the bound session
rt_poker() {
  RT_PRC=0
  ( cd "$RT_ROOT" && exec env CLAUDE_CODE_SESSION_ID="$WORLD_SID" bash "$RT_ROOT/hooks/session-poker.sh" "$@" ) \
    > "$WORLD_ROOT/rt.out" 2> "$WORLD_ROOT/rt.err" || RT_PRC=$?
  RT_OUT="$(cat "$WORLD_ROOT/rt.out")"; RT_ERR="$(cat "$WORLD_ROOT/rt.err")"
}
rt_asks() { printf '%s\n' "$1" | sed -n 's/^ask: key=\([^ ]*\) .*/\1/p' | LC_ALL=C sort | paste -sd' ' -; }   # <sheet>
# <sheet> -> each ask as <key>><what it holds>, sorted, space-joined
rt_holds() { printf '%s\n' "$1" | sed -n 's/^ask: key=\([^ ]*\) holds=\(.*\) title=.*/\1>\2/p' | LC_ALL=C sort | paste -sd' ' -; }
rt_ran() { /usr/bin/grep -c -F -- "$1" "$RT_LOG" 2>/dev/null; }   # <command text> -> how many logged commands hold it
# rt_m <sheet> <key> -> a measured line's value alone, the part before its ` — `
rt_m() { printf '%s\n' "$1" | awk -v k="$2: " 'index($0, k) == 1 { v = substr($0, length(k) + 1); i = index(v, " — "); print (i ? substr(v, 1, i - 1) : v); exit }'; }   # <sheet> <key>
# rt_judgment <sheet> -> a judgment in the card's grammar written from the sheet: a row for each task, or for its step
# when it has none, in the sheet's order; the five metrics from the sheet's measurements, each the value before its
# ` — `; every open ask answered, naming what it holds; the predicted close
rt_judgment() {
  printf '%s\n' "$1" | awk '
    function val(f, nxt,   s, r, e) {
      s = index($0, " " f "="); if (!s) return ""
      r = substr($0, s + length(f) + 2)
      if (nxt != "") { e = index(r, " " nxt "="); if (e) r = substr(r, 1, e - 1) }
      return r
    }
    /^step: / { $0 = " " substr($0, 7); ns++; sn[ns] = val("n", "name"); nm[ns] = val("name", "state"); known[sn[ns]] = 1; next }
    /^task: / { $0 = " " substr($0, 7); nt++; ts[nt] = val("step", "state"); id = val("id", "step"); sub(/^T/, "", id); tl[nt] = ts[nt] "/" id; td[nt] = val("desc", "note"); next }
    /^goal: / { $0 = " " substr($0, 7); gl = gl (gl == "" ? "" : ", ") val("name", "status") " " val("status", "measure"); next }
    /^[a-z][a-z.-]*: / && index($0, " — ") { k = substr($0, 1, index($0, ": ") - 1); v = substr($0, index($0, ": ") + 2); mv[k] = substr(v, 1, index(v, " — ") - 1) }
    /^close\.predicted: / { pr = mv["close.predicted"]; next }
    /^ask: / { $0 = " " substr($0, 6); na++; ak[na] = val("key", "holds"); ah[na] = val("holds", "title"); next }
    END {
      if (na) print "call: Answer what the run waits on, below."; else print "call: Nothing is owed: let the build land."
      for (i = 1; i <= ns; i++) {
        has = 0
        for (j = 1; j <= nt; j++) if (ts[j] == sn[i]) { has = 1; print "task: " tl[j] ": " td[j] }
        if (!has) print "task: " sn[i] ": " nm[i]
      }
      for (j = 1; j <= nt; j++) if (!(ts[j] in known)) print "task: " tl[j] ": " td[j]
      print "metric: Completed: " mv["work.landed"] " landed; " mv["work.left"] " left."
      print "metric: Pace: " mv["pace.work-landed"] " of the work landed in " mv["pace.time-used"] " of the forecast time."
      print "metric: Correctness: suites run " mv["tests.suites-run"] "; reviews " mv["reviews"] "; " mv["findings.open"] " open findings."
      w = mv["waste.waiting-on-you"]; sub(/:.*/, "", w)
      print "metric: Waste: " mv["waste.runs-discarded"] " suite runs thrown away; " w " waiting on you."
      print "metric: Goals: " ((gl == "") ? "none declared" : gl) "."
      print "grade: B"; print "point: The run moved through its own commands to this state."
      for (i = 1; i <= na; i++) print "ask " ak[i] ": The ask that holds " ah[i] " — recommend the default"
      print "close: " ((pr == "" || pr == "-") ? "No close predicted yet" : pr) ", if the next command lands first time."
    }'
}
rt_wide() {  # <text> -> each line wider than BIONIC_LINE_WIDTH columns, as `<columns>: <line>`
  local l
  while IFS= read -r l; do
    _bionic_cols_into "$l"
    [ "$BIONIC_COLS" -le "$BIONIC_LINE_WIDTH" ] || printf '%s: %s\n' "$BIONIC_COLS" "$l"
  done <<< "$1"
}
# rt_sheet_and_card <label> <want asks> <want holds> <drop key|""> -> the sheet, the card and the refusal of one state
rt_sheet_and_card() {
  local lb="$1" want="$2" holds="$3" drop="$4" asks j
  rt_poker sitrep "$RT_PLAN"
  expect_eq "$lb-2 the sandbox's poker prints the sheet (exit 0)" "0|yes" \
    "$RT_PRC|$(printf '%s\n' "$RT_OUT" | head -1 | /usr/bin/grep -q '^sheet/v1' && echo yes)"
  asks="$(rt_asks "$RT_OUT")"
  expect_eq "$lb-3 the sheet's ask: lines are exactly the state's asks" "$want" "$asks"
  [ -z "$want" ] || expect_eq "$lb-3a …each holding the row that reads it" "$holds" "$(rt_holds "$RT_OUT")"
  [ -n "$want" ] || expect_eq "$lb-3b …the same sheet read line by line: its tasks are there, and no ask: line" "yes|0" \
    "$([ "$(printf '%s\n' "$RT_OUT" | /usr/bin/grep -c '^task: ')" -ge 1 ] && echo yes)|$(printf '%s\n' "$RT_OUT" | /usr/bin/grep -c '^ask: ')"
  j="$(rt_judgment "$RT_OUT")"
  rt_poker sitrep card "$RT_PLAN" <<< "$j"
  expect_eq "$lb-4 a judgment naming every open ask renders the card (exit 0, nothing on stderr)" "0|" "$RT_PRC|$RT_ERR"
  expect_eq "$lb-4b …the card's head and its Blocked on you section" "yes|yes" \
    "$(printf '%s\n' "$RT_OUT" | head -1 | /usr/bin/grep -q '^Sitrep · ' && echo yes)|$(printf '%s\n' "$RT_OUT" | /usr/bin/grep -qx '  Blocked on you' && echo yes)"
  expect_eq "$lb-5 every line of the card is at most $BIONIC_LINE_WIDTH columns (it has $(printf '%s\n' "$RT_OUT" | wc -l | tr -d ' ') lines)" \
    "" "$(rt_wide "$RT_OUT")"
  if [ -n "$drop" ]; then
    rt_poker sitrep card "$RT_PLAN" <<< "$(printf '%s\n' "$j" | /usr/bin/grep -v -F "ask $drop: ")"
    expect_eq "$lb-6 a judgment that drops $drop is refused: exit 1, stdout empty" "1|" "$RT_PRC|$RT_OUT"
  else
    rt_poker sitrep card "$RT_PLAN" <<< "$(printf '%s\nask decide:D9: a decision nobody put — recommend 1\n' "$j")"
    expect_eq "$lb-6 a judgment naming an ask the register lacks is refused: exit 1, stdout empty" "1|" "$RT_PRC|$RT_OUT"
  fi
  expect_contains "$lb-6b …the reason naming the key on stderr" "${drop:-decide:D9}" "$RT_ERR"
}

# ============================================================
section "§FAILED-REVIEW: the build landed, a whole review failed, close-out refused at Step 8"
# ============================================================
# fails-when: the state is not reached through the commands, its sheet lacks the waiver or the held merge, or the
# card drawn from it fails its check.
rt_state failed-review
expect_eq "FR-1 rehearse reaches the state and prints the sandbox's plan (exit 0)" "0|yes" \
  "$RT_RC|$([ -f "$RT_PLAN" ] && echo yes)"
if [ "$RT_RC" = 0 ]; then
  expect_eq "FR-1b …through the door's landing, a failing review registered by its verb, and close-out refused" \
    "yes|yes|yes" "$([ "$(rt_ran 'spawn-worktree.sh land')" -ge 1 ] && echo yes)|$([ "$(rt_ran 'proof-add review')" -ge 1 ] && echo yes)|$([ "$(rt_ran 'close-out.sh')" -ge 1 ] && echo yes)"
  rt_sheet_and_card FR "hold:merge waive:structure" "hold:merge>8/4 waive:structure>8/4" waive:structure
fi

# ============================================================
section "§RELEASE-WAITING: the release approval card rendered and waiting on its reply"
# ============================================================
# fails-when: the state is not reached through the commands, its sheet lacks the release approval, or the card drawn
# from it fails its check.
rt_state release-waiting
expect_eq "RW-1 rehearse reaches the state and prints the sandbox's plan (exit 0)" "0|yes" \
  "$RT_RC|$([ -f "$RT_PLAN" ] && echo yes)"
if [ "$RT_RC" = 0 ]; then
  expect_eq "RW-1b …through the door's landing, the regression run and the release approval card's own verb" \
    "yes|yes|yes" "$([ "$(rt_ran 'spawn-worktree.sh land')" -ge 1 ] && echo yes)|$([ "$(rt_ran 'regression-run')" -ge 1 ] && echo yes)|$([ "$(rt_ran 'release-approval')" -ge 1 ] && echo yes)"
  rt_sheet_and_card RW "approve:merge approve:release" "approve:merge>8/4 approve:release>8/4" approve:release
fi

# ============================================================
section "§STOP-RULE: a stop-rule decision put, and a row waiting on it"
# ============================================================
# fails-when: the state is not reached through the commands, its sheet lacks the decision, or the card drawn from it
# fails its check.
rt_state stop-rule
expect_eq "SR-1 rehearse reaches the state and prints the sandbox's plan (exit 0)" "0|yes" \
  "$RT_RC|$([ -f "$RT_PLAN" ] && echo yes)"
if [ "$RT_RC" = 0 ]; then
  expect_eq "SR-1b …through decisions put and the row's reads set by task-set" "yes|yes" \
    "$([ "$(rt_ran 'decisions put D1')" -ge 1 ] && echo yes)|$([ "$(rt_ran 'reads+=approval:D1')" -ge 1 ] && echo yes)"
  rt_sheet_and_card SR "decide:D1" "decide:D1>4/2" decide:D1
fi

# ============================================================
section "§CLEAN: mid-build, nothing owed"
# ============================================================
# fails-when: the state is not reached through the commands, its sheet shows an ask, or the card drawn from it fails
# its check.
rt_state clean
expect_eq "CL-1 rehearse reaches the state and prints the sandbox's plan (exit 0)" "0|yes" \
  "$RT_RC|$([ -f "$RT_PLAN" ] && echo yes)"
if [ "$RT_RC" = 0 ]; then
  expect_eq "CL-1b …through the door's landing of one build row, the other still building" "yes" \
    "$([ "$(rt_ran 'spawn-worktree.sh land')" -ge 1 ] && echo yes)"
  rt_sheet_and_card CL "" "" ""
fi


# ============================================================
section "§TRUE: the four sheets read true to the person who accepts the release on them"
# ============================================================
# FIXTURE FIDELITY: the sandboxes of the four sections above, read again with their own poker. The rehearsal's plan
# is approved when the rehearsal starts, as a person approves it at Step 3 just before the build.
# fails-when: the plan carries an approval from weeks before the run, so the pace reads hundreds of hours and the
# close lands weeks out; a task held on a decision says it is building; the head names a wave the plan lacks.
rt_elapsed_min() {  # <sheet> -> the minutes clock.elapsed says have passed since the approval, nothing when it names none
  rt_m "$1" clock.elapsed | /usr/bin/grep -E '^[0-9]' \
    | awk '{ m = 0; for (i = 2; i <= NF; i++) { if ($i == "h") m += $(i - 1) * 60; if ($i == "min") m += $(i - 1) } print m }'
}
rt_taskline() { printf '%s\n' "$1" | /usr/bin/grep "^task: id=$2 "; }   # <sheet> <id> -> its task line
for TR_ST in failed-review release-waiting stop-rule clean; do
  RT_ROOT="$WORLD_ROOT/$TR_ST/project"; RT_PLAN="$RT_ROOT/$DOOR_PLAN_REL"
  if [ ! -f "$RT_PLAN" ]; then
    expect_eq "TR-0 $TR_ST: the sandbox of its section is there to be read again" "yes" "no"
    continue
  fi
  rt_poker sitrep "$RT_PLAN"
  TR_SHEET="$RT_OUT"
  TR_MIN="$(rt_elapsed_min "$TR_SHEET")"
  expect_eq "TR-1 $TR_ST: the sheet's clock names the time since the approval, and it is under an hour (it says $TR_MIN min)" "yes" \
    "$([ -n "$TR_MIN" ] && [ "$TR_MIN" -lt 60 ] && echo yes)"
  expect_eq "TR-2 $TR_ST: the predicted close and the forecast name no day, so neither is weeks out" "" \
    "$(printf '%s\n' "$TR_SHEET" | /usr/bin/grep -E '^(close\.predicted|clock\.forecast): ' | /usr/bin/grep -E '[0-9]{4}-[0-9]{2}-[0-9]{2}')"
  expect_eq "TR-3 $TR_ST: no task held on you says it is building or gives no note" "" \
    "$(printf '%s\n' "$TR_SHEET" | /usr/bin/grep '^task: .* state=held ' | /usr/bin/grep -vE 'note=waits on ')"
  rt_poker sitrep card "$RT_PLAN" <<< "$(rt_judgment "$TR_SHEET")"
  expect_eq "TR-4 $TR_ST: the plan has no wave number, and the card's head leaves the wave out (exit 0)" \
    "run.wave: -|0|Sitrep · project 99.0.0" \
    "$(printf '%s\n' "$TR_SHEET" | /usr/bin/grep '^run\.wave: ')|$RT_PRC|$(printf '%s\n' "$RT_OUT" | head -1 | sed 's/ · [A-Za-z]* [0-9:]* [AP]M$//')"
done
RT_ROOT="$WORLD_ROOT/stop-rule/project"; RT_PLAN="$RT_ROOT/$DOOR_PLAN_REL"
if [ -f "$RT_PLAN" ]; then
  rt_poker sitrep "$RT_PLAN"
  expect_eq "TR-5 stop-rule: T2 reads the decision and is held, and its note names the decision, not building" \
    "state=held|note=waits on your approval of D1" \
    "$(rt_taskline "$RT_OUT" T2 | /usr/bin/grep -o 'state=[a-z]*')|$(rt_taskline "$RT_OUT" T2 | /usr/bin/grep -o 'note=.*$')"
  expect_eq "TR-5b …and T1, landed, says when (TR-5 read the same sheet)" "yes" \
    "$(rt_taskline "$RT_OUT" T1 | /usr/bin/grep -q 'state=done .* note=landed ' && echo yes)"
fi

# ============================================================
section "§FACTS: the four sheets' facts read true: every line a measurement naming what it measures, its unit and its source; every goal the plan declares, a close not scaled by fewer than three landed tasks, a review counted once by its latest result, the suites and the whole run named, every read a held task waits on"
# ============================================================
# FIXTURE FIDELITY: the sandboxes of the four sections above, read again with their own poker. The rehearsal's plan
# declares three goals measured by records: one it writes passing, one failing, one it never writes.
# fails-when: a measured line is missing or names no measure, unit and source; a metric. line prints; a sheet draws no
# goal, or a goal reads another status; the close is scaled by one or two landed tasks; a review that passed and then
# failed counts as both; a note counts the reads it leaves out.
RT_MEASURED="clock.now clock.approved clock.forecast clock.elapsed clock.elapsed-share work.planned work.added work.dropped work.landed work.left work.width work.task-time pace.time-used pace.work-landed close.chain close.predicted close.unscaled close.waits-on-you tests.suites-run tests.suites-total tests.whole-run reviews findings.open waste.dropped waste.runs-discarded waste.ready-unstarted waste.waiting-on-you"
rt_unlabelled() {  # <sheet> -> each measured key with no line, or whose line names no measure, unit and source (or basis)
  local k l
  for k in $RT_MEASURED; do
    l="$(printf '%s\n' "$1" | /usr/bin/grep -F "$k: " | head -1)"
    case "$l" in "$k: "?*' — '?*' · unit: '*' · source: '?*|"$k: "?*' — '?*' · unit: '*' · basis: '?*) ;; *) printf '%s ' "$k" ;; esac
  done
}
rt_goal_lines() { printf '%s\n' "$1" | sed -n 's/^goal: name=\([^ ]*\) status=\(.*\) measure=.*/\1=\2/p' | paste -sd'|' -; }   # <sheet>
for TR_ST in failed-review release-waiting stop-rule clean; do
  RT_ROOT="$WORLD_ROOT/$TR_ST/project"; RT_PLAN="$RT_ROOT/$DOOR_PLAN_REL"
  if [ ! -f "$RT_PLAN" ]; then
    expect_eq "FA-0 $TR_ST: the sandbox of its section is there to be read again" "yes" "no"
    continue
  fi
  rt_poker sitrep "$RT_PLAN"
  TR_SHEET="$RT_OUT"
  expect_eq "FA-0b $TR_ST: every measured line is there and names what it measures, its unit and its source; no metric. line" "|0|yes" \
    "$(rt_unlabelled "$TR_SHEET")|$(printf '%s\n' "$TR_SHEET" | /usr/bin/grep -c '^metric\.')|$(printf '%s\n' "$TR_SHEET" | /usr/bin/grep -q '^clock\.now: ' && echo yes)"
  expect_eq "FA-1 $TR_ST: the sheet's goal: lines, one per declared goal, met, not met and not measured" \
    "shown=met|asks=not met|walked=not measured" "$(rt_goal_lines "$TR_SHEET")"
  TR_N="$(rt_m "$TR_SHEET" work.task-time | sed -n 's/^\([0-9][0-9]*\) tasks*[,:].*/\1/p')"
  expect_eq "FA-2 $TR_ST: $TR_N landed task(s) with a launch, under 3: the close is the chain at 1×, unscaled, and the basis says so" "yes|yes|yes" \
    "$([ -n "$TR_N" ] && [ "$TR_N" -lt 3 ] && echo yes)|$([ "$(rt_m "$TR_SHEET" close.predicted)" = "$(rt_m "$TR_SHEET" close.unscaled)" ] && echo yes)|$(printf '%s\n' "$TR_SHEET" | /usr/bin/grep '^close\.predicted: ' | /usr/bin/grep -q 'basis: clock.now plus close.chain at 1×: .*under 3' && echo yes)"
  expect_eq "FA-2b $TR_ST: pace states two shares of one unit, the work landed and the forecast time used" "yes|yes" \
    "$(rt_m "$TR_SHEET" pace.work-landed | /usr/bin/grep -qE '^[0-9]+%$' && echo yes)|$(rt_m "$TR_SHEET" pace.time-used | /usr/bin/grep -qE '^[0-9]+%$' && echo yes)"
  expect_eq "FA-3 $TR_ST: correctness names the suites run by their last run and the whole run" "yes|yes" \
    "$(rt_m "$TR_SHEET" tests.suites-run | /usr/bin/grep -qE '^[0-9]+: [0-9]+ green, [0-9]+ red$' && echo yes)|$(rt_m "$TR_SHEET" tests.whole-run | /usr/bin/grep -qE '^(not run yet|green at [0-9a-f]{8}|red at [0-9a-f]{8})$' && echo yes)"
  expect_eq "FA-4 $TR_ST: no task's note counts what it leaves out (FA-1 read the same sheet)" "0" \
    "$(printf '%s\n' "$TR_SHEET" | /usr/bin/grep '^task: ' | /usr/bin/grep -cE ' note=.* \+[0-9]+$')"
done
RT_ROOT="$WORLD_ROOT/failed-review/project"; RT_PLAN="$RT_ROOT/$DOOR_PLAN_REL"
if [ -f "$RT_PLAN" ]; then
  rt_poker sitrep "$RT_PLAN"
  expect_eq "FA-5 failed-review: the structure review of the whole passed, then failed: it counts once, failed, beside the four that passed" \
    "2|4 passed, 1 failed, 0 running" \
    "$(printf '%s\n' "$RT_OUT" | /usr/bin/grep -c '^review: question=structure scope=whole ')|$(rt_m "$RT_OUT" reviews)"
fi
RT_ROOT="$WORLD_ROOT/release-waiting/project"; RT_PLAN="$RT_ROOT/$DOOR_PLAN_REL"
if [ -f "$RT_PLAN" ]; then
  rt_poker sitrep "$RT_PLAN"
  expect_eq "FA-6 release-waiting: the merge row names every read it waits on, in words: its step and both approvals" \
    "note=waits on step 8, your approval of the release and your approval of the merge" \
    "$(rt_taskline "$RT_OUT" T4 | /usr/bin/grep -o 'note=.*$')"
  expect_eq "FA-6b …and the whole run the regression row ran is green at its head" "yes" \
    "$(rt_m "$RT_OUT" tests.whole-run | /usr/bin/grep -qE '^green at [0-9a-f]{8}$' && echo yes)"
fi

finish
