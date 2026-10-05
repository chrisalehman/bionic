#!/bin/bash
# ONE STALENESS ARITHMETIC FOR THE PATROL STAMP — the FIRE WINDOW (epic-23 wave-16
# REQ-11, AC-11.1/11.2; ADR-028).
#
# WHAT THIS SUITE OWNS, AND WHAT CHANGED. It used to own a constant:
# `payload/scripts/lib/patrol.sh`'s `PATROL_STALE_MULTIPLIER`, "the stamp is stale
# past twice the poker interval" held in one exported name instead of an inline
# literal at three sites. That judgment call is retired. A session cron fires only
# while the session is IDLE, so a stamp older than any multiple of the interval says
# one of two things and the arithmetic could not tell them apart: the job is gone, or
# the orchestrator has been working. On 2026-09-15 a death notice blocked a healthy
# session on a 2459s stamp against a 2400s limit because its orchestrator was busy.
#
# WHAT REPLACED IT. `patrol_fire_window` — the interval plus the scheduler's jitter,
# which the CronCreate contract bounds at a tenth of the period — is the longest idle
# span in which the cron is GUARANTEED one opportunity to fire, and it is the ONE
# threshold in the payload. Past it a stamp is worth READING THE TRANSCRIPT about and
# is not, on its own, a verdict: `patrol_verdict` answers that, over idle gaps.
# Wave-15 moved the two BLOCKING readers (the stop library's revive notice, the
# dispatch wall's staleness half) onto the pair; wave-16 moved the two REPORTING
# readers — `patrol_stamp_state`, which is doctor's reading, and the session-start
# banner — and deleted the constant behind them.
#
# SO THE ROWS BELOW PIN THE NEW TRUTH: the constant has no definition and no reader,
# every reader of "how stale is stale" calls the library's predicate, and the fire
# window's arithmetic is written exactly once.
#
# SOURCED, DIRECTLY (patrol.sh's own header: "Sourced, never executed" — no
# top-level code runs on source, only assignments and function definitions,
# so this is safe the same way tests/detect-probes.test.sh sources detect.sh).
#
# Usage: bash tests/patrol-stale.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PATROL_SH="${REPO}/payload/scripts/lib/patrol.sh"

# expect_eq, expect_true are the framework's (tests/lib/assert.sh) — identical
# semantics to the private definitions this suite carried (S7, AC-12).
expect_true "payload/scripts/lib/patrol.sh exists" test -f "$PATROL_SH"
expect_true "patrol.sh passes bash -n" bash -n "$PATROL_SH"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO_FIX="$TMP/repo"
mkdir -p "$REPO_FIX"

sourced() {  # <fn-or-expr...> — run against a clean copy of patrol.sh's globals
  bash -c '. "$1"; shift; "$@"' _ "$PATROL_SH" "$@" 2>/dev/null
}

section "Section 1: the multiplier is gone, and the predicate that replaced it works"

# THE RETIREMENT IS COMPLETE AT THIS HEAD (epic-23 wave-16, T9 commit 33d3d12, re-authored
# here by T22). This section used to pin the opposite: the export OUTLIVED its last reader by
# one task, deliberately, because deleting the definition before the readers moved would have
# left a head reading an unset name under `set -u` (A-orch-6, A-orch-12). Both halves have
# landed now — T8 moved the last stamp-grading readers onto `patrol_verdict`, T9 deleted the
# `export` line — so the state this section must assert has INVERTED, and rows 1 and 1b say
# so. The rows below were measured green in a tree that still carried the export (T8's 18/18,
# per A-orch-6's own revert), which is why their staleness only surfaced at the wave head's
# floor; the pins follow the code rather than the order the tasks were written in.
SP="${BIONIC_HOOKS_DIR}/session-poker.sh"
DP="${BIONIC_HOOKS_DIR}/dispatch-preflight.sh"
SS="${BIONIC_HOOKS_DIR}/session-start.sh"
DOC="${REPO}/payload/scripts/doctor.sh"
STOP_SH="${REPO}/payload/scripts/lib/stop.sh"

# A READER, NOT A MENTION. Comment lines are excluded because this library and the stop
# library both narrate the retirement in prose, and a row that counted narration would be a
# row against the history rather than against the code.
stale_lines() {  # <file> -> the number of non-comment lines naming the constant
  local n
  n="$(grep -cE '^[[:space:]]*[^#[:space:]].*PATROL_STALE_MULTIPLIER' "$1" 2>/dev/null || true)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

# THE LIBRARY HOLDS NEITHER THE DEFINITION NOR A READER: the name is gone from this file
# entirely, narration included, and the export line in particular is gone.
expect_eq "1: the library names the constant on no non-comment line at all" "0" \
  "$(stale_lines "$PATROL_SH")"
expect_eq "1b: …and the export line itself is gone, not merely unread" "0" \
  "$(grep -c '^export PATROL_STALE_MULTIPLIER=' "$PATROL_SH" || true)"

# THE POSITIVE THAT KEEPS THAT ABSENCE FROM BEING VACUOUS. An absence row passes over a file
# that was emptied, renamed or broken as readily as over one that was correctly retired, so
# the two rows above are paired with the thing that REPLACED the constant — and paired by
# EXERCISING it, not by grepping for its name, because a grep would pass on a definition that
# no longer runs. `patrol_fire_window` is the arithmetic the multiplier used to carry and
# `patrol_verdict` is the predicate that reads it; both are called here against a clean
# sourced copy of the library under test. 1c drives the window on a real interval and checks
# it against the formula's own terms rather than a number typed here; 1d drives the verdict
# on a stamp path that does not exist, which is the one branch that needs no fixture, and
# reads back the record shape every caller parses.
PS_IV=1200
expect_eq "1c: …because patrol_fire_window computes that window instead, and runs" \
  "$(( PS_IV + PS_IV / 10 ))" "$(sourced patrol_fire_window "$PS_IV")"
expect_eq "1d: …and patrol_verdict runs and answers in the record shape its callers read" \
  "yes" \
  "$(printf '%s' "$(sourced patrol_verdict "$TMP/no-such-stamp" "$TMP/no-such-transcript" "$PS_IV")" \
     | grep -qE '^verdict=[a-z]+\|ref=[0-9]+\|gap=[0-9]+\|window=[0-9]+\|reason=' && echo yes || echo no)"

# AND EVERY READER THAT GRADES A STAMP IS OFF IT. Four files, one row each side of the
# blocking/reporting divide: the doctor's reading and the banner moved at wave-16, the
# dispatch wall and the stop library at wave-15.
expect_eq "2: the doctor's page does not multiply the interval" "0" "$(stale_lines "$DOC")"
expect_eq "3: nor does the session-start banner" "0" "$(stale_lines "$SS")"
expect_eq "3b: nor the dispatch wall, nor the stop library" "0" \
  "$(( $(stale_lines "$DP") + $(stale_lines "$STOP_SH") ))"

section "Section 2: patrol_stamp_state measures against the fire window"

# No hooks/session-poker.sh beside this fixture repo, so patrol_interval falls
# back to its own last-resort default (1200s, PATROL_INTERVAL_LAST_RESORT) —
# matching the poker's own 20m default. The rows read `interval=` and `limit=`
# back out of the record and compare the second against the LIBRARY's own
# `patrol_fire_window`, so a change to either the default or the window's
# arithmetic is still caught in agreement rather than against a number typed here.
STAMP_OUT="$(sourced patrol_stamp_state "$REPO_FIX" "fixture-session")"
SECS="$(printf '%s' "$STAMP_OUT" | sed -n 's/.*interval=\([0-9]*\).*/\1/p')"
LIMIT="$(printf '%s' "$STAMP_OUT" | sed -n 's/.*limit=\([0-9]*\).*/\1/p')"
WINDOW="$(sourced patrol_fire_window "$SECS")"

case "$SECS" in
  ''|*[!0-9]*) no "4: patrol_stamp_state's interval field is a number" "got: $STAMP_OUT" ;;
  *) ok "4: patrol_stamp_state's interval field is a number" ;;
esac
expect_eq "5: limit = patrol_fire_window(interval)" "$WINDOW" "$LIMIT"
expect_eq "6: with the real last-resort default, that limit is 1320 and not 2400" \
  "1320" "$LIMIT"

section "Section 3: every reader of \"how stale is stale\" calls the predicate"
#
# FOUR READERS, ONE PREDICATE. Two BLOCK — the stop library's revive notice and the
# dispatch wall's staleness half, moved at wave-15 — and two REPORT: this library's own
# `patrol_stamp_state` (doctor's reading) and the session-start banner, moved here. The rows
# assert the CALL rather than a spelling of the arithmetic, which is what makes them hold
# whatever the window's number becomes.
# COUNTED AS A CALL, NEVER AS A MENTION: this file DEFINES `patrol_verdict`, so a bare
# containment row here would pass on the definition alone and prove nothing about the
# reading. `$(patrol_verdict ` is the call, and `patrol_stamp_state` is its one site.
expect_eq "7: the doctor's reading asks the predicate" "1" \
  "$(grep -c '\$(patrol_verdict ' "$PATROL_SH" || true)"
expect_eq "8: …and it thresholds on the library's fire window" "yes" \
  "$(grep -qF 'patrol_fire_window' "$PATROL_SH" && echo yes || echo no)"
expect_eq "9: the session-start banner asks the same predicate" "yes" \
  "$(grep -qF 'patrol_verdict' "$SS" && echo yes || echo no)"
expect_eq "10: …and takes its threshold from the same function" "yes" \
  "$(grep -qF 'patrol_fire_window' "$SS" && echo yes || echo no)"

# THE WALL NO LONGER MULTIPLIES ANYTHING. Both spellings the old row accepted are absent:
# the constant, and a literal in its place.
expect_eq "11: the dispatch wall no longer measures staleness with a multiplier" "0" \
  "$(grep -cE 'PATROL_INTERVAL[[:space:]]*\*[[:space:]]*[A-Za-z_0-9]+' "$DP" || true)"
# …because it asks the predicate instead. Paired with 11, so the absence above rests on a
# file this suite can prove it read.
expect_eq "12: …it calls patrol_verdict, which owns the threshold" "yes" \
  "$(grep -qF 'patrol_verdict' "$DP" && echo yes || echo no)"
expect_eq "13: …and the fire window is computed in the library, once" "1" \
  "$(grep -c 'iv / 10' "$PATROL_SH" || true)"
# AND NO READER RECOMPUTES IT. The banner and doctor are in this row now beside the two
# walls: a reader that spelled `+ iv / 10` again would be the old literal under a new name.
# `/ 10` AND NOT A DIGIT AFTER IT: `_rs_started_ms / 1000` in doctor.sh is a millisecond
# conversion, and a substring match counted it as a second copy of the jitter arithmetic.
expect_eq "14: …and no reader of it recomputes the jitter" "0" \
  "$(( $(grep -cE '/ 10([^0-9]|$)' "${REPO}/payload/scripts/lib/stop.sh" || true) \
     + $(grep -cE '/ 10([^0-9]|$)' "$DP" || true) \
     + $(grep -cE '/ 10([^0-9]|$)' "$SS" || true) \
     + $(grep -cE '/ 10([^0-9]|$)' "$DOC" || true) ))"

section "Section 4: one owner rule for every class: the name up to its first dot (wave-27 T68; review pass 47 S1, A-orch-137)"

# THE PER-START CLOCK FILE IS A CLASS (start-clock-<sid>.<agent id>.state). A session id holds no
# dot (lib/context.sh), an agent id may, so for every class a file's owner is the name after
# `<class>-` up to its first dot. patrol.sh reads it so (the sweep and doctor), and close-out's
# wipe (Step 8) reads it so: the classes come from PATROL_STATE_CLASSES, never from this file.
# fails-when: a class's files parse to another owner than before, the clock class is not a class,
# or close-out reads a clock file's owner as `<sid>.<id>` and spares it for ever.
CO_SH="${REPO}/payload/scripts/close-out.sh"
OW_SID="1a2b3c4d-1111-4e05-9f21-7d0c5a8e6b44"
OW_CLASSES="$(sed -n 's/^PATROL_STATE_CLASSES="\(.*\)"$/\1/p' "$PATROL_SH")"
expect_nonempty "OW0 PATROL_STATE_CLASSES is read off patrol.sh (the extractor works)" "$OW_CLASSES"
expect_contains "OW1 start-clock is one of the classes" " start-clock " " $OW_CLASSES "
OW_CO_FN="$(sed -n '/^_co_tmp_owner() {/,/^}/p' "$CO_SH")"
expect_nonempty "OW2 close-out's owner reader is read off close-out.sh (the extractor works)" "$OW_CO_FN"
OW_BAD_P=""; OW_BAD_C=""; OW_SEEN=0
for _ow_c in $OW_CLASSES; do
  for _ow_n in "$_ow_c-$OW_SID.state" "$_ow_c-$OW_SID.state.armed" "$_ow_c-$OW_SID.a1b2c3d4.state" "$_ow_c-$OW_SID.a.b@c.state"; do
    rm -rf "$REPO_FIX/.bionic"; mkdir -p "$REPO_FIX/.bionic/tmp"; : > "$REPO_FIX/.bionic/tmp/$_ow_n"
    _ow_p="$(sourced patrol_state_session_ids "$REPO_FIX")"
    _ow_o="$(bash -c 'PATROL_STATE_CLASSES="$1"; PATROL_STATE_ARMED_SUFFIX=.armed; eval "$2"; _co_tmp_owner "$3"' _ \
      "$OW_CLASSES" "$OW_CO_FN" "$_ow_n")"
    [ "$_ow_p" = "$OW_SID" ] || OW_BAD_P="$OW_BAD_P $_ow_n=[$_ow_p]"
    [ "$_ow_o" = "$OW_SID" ] || OW_BAD_C="$OW_BAD_C $_ow_n=[$_ow_o]"
    OW_SEEN=$((OW_SEEN + 1))
  done
done
expect_eq "OW3 every class's file, a per-start one too, parses to its session in patrol.sh" "" "$OW_BAD_P"
expect_eq "OW4 …and in close-out's wipe" "" "$OW_BAD_C"
expect_eq "OW5 …over four names for each class (the loop ran)" "$(( $(printf '%s\n' $OW_CLASSES | grep -c .) * 4 ))" "$OW_SEEN"
rm -rf "$REPO_FIX/.bionic"; mkdir -p "$REPO_FIX/.bionic/tmp"
: > "$REPO_FIX/.bionic/tmp/start-clock-$OW_SID.a1b2.state"; : > "$REPO_FIX/.bionic/tmp/start-clock-$OW_SID.a9.state"
: > "$REPO_FIX/.bionic/tmp/roster-$OW_SID.state"; : > "$REPO_FIX/.bionic/tmp/start-clock-other.a1.state"
expect_eq "OW6 one session's files are its exact names and its per-start clock files" \
  "roster-$OW_SID.state start-clock-$OW_SID.a1b2.state start-clock-$OW_SID.a9.state" \
  "$(sourced patrol_session_state_files "$REPO_FIX" "$OW_SID" | sed 's|.*/||' | sort | tr '\n' ' ' | sed 's/ $//')"
mkdir "$REPO_FIX/.bionic/tmp/start-clock-$OW_SID.adir.state"
ln -s "$TMP/nowhere" "$REPO_FIX/.bionic/tmp/start-clock-$OW_SID.alink.state"
expect_eq "OW7 a directory or a link with a clock file's name is not one of them" \
  "roster-$OW_SID.state start-clock-$OW_SID.a1b2.state start-clock-$OW_SID.a9.state" \
  "$(sourced patrol_session_state_files "$REPO_FIX" "$OW_SID" | sed 's|.*/||' | sort | tr '\n' ' ' | sed 's/ $//')"

finish
