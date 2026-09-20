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

section "Section 1: the multiplier has no reader left in this payload"

# THE LINE ITSELF OUTLIVES ITS LAST READER BY ONE TASK, and that is deliberate. Every reader
# that graded a Patrol STAMP is off it (Section 3 below names them); the one line anywhere
# that still uses the name multiplies a ROW's declared CADENCE in the poker's `adopt` window
# — a different question — and wave-16 REQ-10 moves that onto `observe_class` and deletes the
# export with it. Deleting the definition first would leave a head reading an unset name
# under `set -u`, so this suite pins what is true at every head: no READER among the files
# that grade a stamp. The tree-wide absence of the name is the wave head's own pin, in
# tests/cross-gate-agreement.test.sh §PV, where both halves have landed.
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

# THE LIBRARY HOLDS THE DEFINITION AND NOTHING ELSE: one non-comment line, and it is the
# export. Paired, so "no reader here" cannot pass by the name having vanished early — which
# is the state this section must NOT assert, because the deletion belongs to the task that
# removes the last reader.
expect_eq "1: the library names the constant on exactly one non-comment line" "1" \
  "$(stale_lines "$PATROL_SH")"
expect_eq "1b: …and that line is the export itself, not a reader" "1" \
  "$(grep -c '^export PATROL_STALE_MULTIPLIER=' "$PATROL_SH" || true)"

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

finish
