#!/bin/bash
# Tests for the four run states the sitrep card is read in, each reached by playing a small run forward through the
# real commands (tests/lib/rehearsal.sh `rehearse`), never by writing a state's files.
#
#   §FAILED-REVIEW    the build landed, a whole review registered failing and close-out refused at Step 8: the sheet
#                     owes the waiver and the held merge
#   §RELEASE-WAITING  the release approval card rendered and waiting on its reply: the sheet owes what the card put
#   §STOP-RULE        a stop-rule decision put with a row reading its approval: the sheet owes the decision
#   §CLEAN            mid-build, nothing owed: the sheet says so
#
# EACH SECTION, ONE SHAPE. The sandbox's own `hooks/session-poker.sh sitrep <plan>` prints the sheet, whose `ask:`
# lines are exactly the state's asks; a judgment naming every open ask renders through `sitrep card` (rc 0, every
# line at most 100 columns); a judgment that drops one is refused (rc 1, stdout empty). The clean state has no ask to
# drop, so its refusal is a judgment naming an ask the register lacks, the same floor read from the other side.
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
# rt_judgment <ask key…> -> a judgment naming each key, its call naming the first by its id
rt_judgment() {
  local k
  if [ "$#" -gt 0 ]; then printf 'call: Answer %s: the run waits on it.\n' "${1#*:}"
  else printf 'call: Nothing is owed: let the build land.\n'; fi
  printf 'grade: B\npoint: The run moved through its own commands to this state.\n'
  for k in "$@"; do printf 'ask %s: %s — recommend the default\n' "$k" "$k"; done
  printf 'close: Depends on the next command landing first time.\n'
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
  # shellcheck disable=SC2086  # one word per key
  j="$(rt_judgment $asks)"
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
  rt_sheet_and_card FR "hold:merge waive:structure" "hold:merge>T4 waive:structure>T4" waive:structure
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
  rt_sheet_and_card RW "approve:merge approve:release" "approve:merge>T4 approve:release>T4" approve:release
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
  rt_sheet_and_card SR "decide:D1" "decide:D1>T2" decide:D1
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

finish
