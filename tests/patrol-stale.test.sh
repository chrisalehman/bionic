#!/bin/bash
# PATROL STALENESS CONSTANT — L-DETECT/4.5 (spec AC-22).
#
# WHAT THIS SUITE OWNS. `payload/scripts/lib/patrol.sh`'s `PATROL_STALE_
# MULTIPLIER` — "the stamp is stale past twice the poker interval" as one
# exported constant instead of an inline literal, and `patrol_stamp_state`'s
# own reader of it. `session-poker.sh` and `hooks/dispatch-preflight.sh` carry
# the SAME "twice the interval" arithmetic today; switching those two readers
# to this constant is other slices' work, out of scope here (this slice's
# brief names them explicitly as not-touched) — this suite pins only the one
# reader this slice owns.
#
# SOURCED, DIRECTLY (patrol.sh's own header: "Sourced, never executed" — no
# top-level code runs on source, only assignments and function definitions,
# so this is safe the same way tests/detect-probes.test.sh sources detect.sh).
#
# Usage: bash tests/patrol-stale.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PATROL_SH="${REPO}/payload/scripts/lib/patrol.sh"

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }

expect_true() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
expect_true "payload/scripts/lib/patrol.sh exists" test -f "$PATROL_SH"
expect_true "patrol.sh passes bash -n" bash -n "$PATROL_SH"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO_FIX="$TMP/repo"
mkdir -p "$REPO_FIX"

sourced() {  # <fn-or-expr...> — run against a clean copy of patrol.sh's globals
  bash -c '. "$1"; shift; "$@"' _ "$PATROL_SH" "$@" 2>/dev/null
}

echo ""
echo "=== Section 1: the constant is exported and equals 2 ==="

expect_eq "1: PATROL_STALE_MULTIPLIER is exported" \
  "PATROL_STALE_MULTIPLIER" \
  "$(bash -c '. "$1"; declare -p PATROL_STALE_MULTIPLIER 2>/dev/null | grep -oE "^declare -x PATROL_STALE_MULTIPLIER" | sed "s/declare -x //"' _ "$PATROL_SH")"

expect_eq "2: PATROL_STALE_MULTIPLIER equals 2" \
  "2" "$(bash -c '. "$1"; printf "%s" "$PATROL_STALE_MULTIPLIER"' _ "$PATROL_SH")"

echo ""
echo "=== Section 2: patrol_stamp_state's limit follows the constant ==="

# No hooks/session-poker.sh beside this fixture repo, so patrol_interval falls
# back to its own last-resort default (1800s, "30m") — the same fixture
# doctor-patrol.test.sh's header already documents as "30m default → a 3600s
# limit". This suite does not hardcode 3600: it reads limit=<n> back and
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
expect_eq "5: with the real last-resort default and the real multiplier, limit is 3600" \
  "3600" "$LIMIT"

echo ""
echo "=== Section 3: registration ==="

if grep -q 'run "patrol-stale.test.sh" bash tests/patrol-stale.test.sh' "${BIONIC_SCRIPTS_DIR}/tests/run.sh"; then
  ok "6: tests/run.sh names patrol-stale.test.sh"
else
  no "6: tests/run.sh names patrol-stale.test.sh"
fi

echo ""
echo "========================================"
echo "patrol-stale: $PASS/$TOTAL passed"
echo "========================================"

[ "$FAIL" -eq 0 ] || exit 1
