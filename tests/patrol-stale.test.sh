#!/bin/bash
# PATROL STALENESS CONSTANT — L-DETECT/4.5 (spec AC-22).
#
# WHAT THIS SUITE OWNS. `payload/scripts/lib/patrol.sh`'s `PATROL_STALE_
# MULTIPLIER` — "the stamp is stale past twice the poker interval" as one
# exported constant instead of an inline literal, and `patrol_stamp_state`'s
# own reader of it. `hooks/session-poker.sh` switched its own
# copy of that arithmetic to this constant at task POKER (1.6, spec AC-22),
# and Section 4 below holds the two together; `hooks/dispatch-preflight.sh`
# still carries the literal the constant was extracted from, and its switch
# belongs to task ADOPT. Section 4 asserts agreement on the VALUE rather than
# on a spelling, so it holds before that switch and after it, unedited.
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

section "Section 1: the constant is exported and equals 2"

expect_eq "1: PATROL_STALE_MULTIPLIER is exported" \
  "PATROL_STALE_MULTIPLIER" \
  "$(bash -c '. "$1"; declare -p PATROL_STALE_MULTIPLIER 2>/dev/null | grep -oE "^declare -x PATROL_STALE_MULTIPLIER" | sed "s/declare -x //"' _ "$PATROL_SH")"

expect_eq "2: PATROL_STALE_MULTIPLIER equals 2" \
  "2" "$(bash -c '. "$1"; printf "%s" "$PATROL_STALE_MULTIPLIER"' _ "$PATROL_SH")"

section "Section 2: patrol_stamp_state's limit follows the constant"

# No hooks/session-poker.sh beside this fixture repo, so patrol_interval falls
# back to its own last-resort default (1200s, PATROL_INTERVAL_LAST_RESORT,
# lib/patrol.sh:56) — matching the poker's own 20m default (S10 disposition of
# S8's finding #1: the two had drifted apart when S8 moved only the poker's
# own default to 20m). Where the poker IS reachable the default is 20m
# and the limit 2400s, which is what doctor-patrol.test.sh's header documents.
# This suite does not hardcode either number: it reads limit=<n> back and
# checks it equals secs * PATROL_STALE_MULTIPLIER, so a change to either the
# last-resort default or the multiplier is still caught in agreement.
STAMP_OUT="$(sourced patrol_stamp_state "$REPO_FIX" "fixture-session")"
SECS="$(printf '%s' "$STAMP_OUT" | sed -n 's/.*interval=\([0-9]*\).*/\1/p')"
LIMIT="$(printf '%s' "$STAMP_OUT" | sed -n 's/.*limit=\([0-9]*\).*/\1/p')"
MULT="$(bash -c '. "$1"; printf "%s" "$PATROL_STALE_MULTIPLIER"' _ "$PATROL_SH")"

case "$SECS" in
  ''|*[!0-9]*) no "3: patrol_stamp_state's interval field is a number" "got: $STAMP_OUT" ;;
  *) ok "3: patrol_stamp_state's interval field is a number" ;;
esac
expect_eq "4: limit = interval * PATROL_STALE_MULTIPLIER" \
  "$((SECS * MULT))" "$LIMIT"
expect_eq "5: with the real last-resort default and the real multiplier, limit is 2400" \
  "2400" "$LIMIT"

section "Section 4: the constant's readers agree (spec AC-22; epic-23 wave-15 REQ-1)"
#
# THE THIRD READER IS GONE, AND THAT IS THE POINT (amended at wave-15 T1, ADR-028). This
# section read three: `patrol_stamp_state` (Section 2), the poker's `adopt` liveness
# window, and the dispatch wall's Patrol-stamp staleness arm — the last of which it read
# leniently, in "whichever spelling the wall actually uses", against the day the wall would
# adopt the constant.
#
# The wall did not adopt it; the wall stopped asking the question. Staleness there is no
# longer a multiple of the interval at all: a session cron fires only while the session is
# idle, so age past a threshold could not distinguish a dead job from a busy orchestrator,
# and the wall now calls `patrol_verdict` — an idle-time predicate over the transcript —
# whose own threshold is one FIRE WINDOW (interval plus a tenth for jitter), computed once
# in `patrol_fire_window`. So the rows below assert what is true now: two readers of the
# constant, and a wall that reads neither the constant nor a literal of its own.
#
# PATROL_STALE_MULTIPLIER ITSELF STAYS, with two readers and no third. Sections 1 and 2
# above are untouched.
SP="${BIONIC_HOOKS_DIR}/session-poker.sh"
DP="${BIONIC_HOOKS_DIR}/dispatch-preflight.sh"

expect_eq "7: the poker's liveness window reads the constant, not its own literal" "yes" \
  "$(grep -qF 'CAD_S * PATROL_STALE_MULTIPLIER' "$SP" && echo yes || echo no)"
expect_eq "8: …and it loads the library that owns the constant" "yes" \
  "$(grep -qF 'BIONIC_LIB/patrol.sh' "$SP" && echo yes || echo no)"

# THE WALL NO LONGER MULTIPLIES ANYTHING. Both spellings the old row accepted are absent:
# the constant, and a literal in its place.
expect_eq "9: the dispatch wall no longer measures staleness with a multiplier" "0" \
  "$(grep -cE 'PATROL_INTERVAL[[:space:]]*\*[[:space:]]*[A-Za-z_0-9]+' "$DP" || true)"
# …because it asks the predicate instead. Paired with 9, so the absence above rests on a
# file this suite can prove it read.
expect_eq "10: …it calls patrol_verdict, which owns the threshold" "yes" \
  "$(grep -qF 'patrol_verdict' "$DP" && echo yes || echo no)"
expect_eq "11: …and the fire window is computed in the library, once" "1" \
  "$(grep -c 'iv / 10' "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/patrol.sh" || true)"

finish
