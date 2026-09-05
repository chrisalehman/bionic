# tests/lib/assert.sh — the shared assertion helper and helper-presence guard
# (wave-roster-lifecycle S11, spec AC-24/AC-25).
#
#     . "$(dirname "$0")/lib/assert.sh"      # from tests/*.test.sh, after resolve-roots.sh
#
# WHAT IT OWNS. `expect_eq`, in the one shape every suite that already defines it
# uses verbatim (tests/cross-gate-agreement.test.sh:97, tests/docs-pins.test.sh:53,
# tests/seam-resolution.test.sh:61, tests/dispatch-preflight.test.sh:48) — a straight
# string compare recorded through PASS/FAIL/TOTAL. And `require_helpers`, the guard
# r24e's own defect asks for (research-code-map §6.2): a suite that runs under
# `set -uo pipefail` with no `-e` loses a call to an undefined assertion helper to a
# silent `command not found` on stderr — the row asserts nothing and the suite's own
# pass/total never notices. `require_helpers` turns that into a loud `exit 1`, naming
# every missing name, before the first assertion runs.
#
# COUNTERS AND ok/no ARE DEFINE-ONCE. Every suite in this tree already carries its
# own verbatim `PASS=0; FAIL=0; TOTAL=0` plus `ok()`/`no()` (identical in shape
# everywhere this file is sourced). Redefining them unconditionally here would risk
# resetting counts that earlier assertions in the same file already added to, if a
# suite ever sources this after some of its own assertions have run — so they are
# supplied ONLY when the suite does not already define them. `expect_eq` and
# `require_helpers` are always defined by this file: they are new names, and every
# suite that already had its own `expect_eq` (dispatch-preflight) defines it in this
# exact shape, so a later definition here changes nothing observable.

if ! declare -p PASS >/dev/null 2>&1; then PASS=0; fi
if ! declare -p FAIL >/dev/null 2>&1; then FAIL=0; fi
if ! declare -p TOTAL >/dev/null 2>&1; then TOTAL=0; fi

if ! type -t ok >/dev/null 2>&1; then
  ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
fi
if ! type -t no >/dev/null 2>&1; then
  no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }
fi

# expect_eq <label> <expected> <actual>
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }

# require_helpers <name>... -> exit 1, naming every undefined one, if any name
# passed is not a defined shell function. Call this once, near the top of a suite,
# after every assertion helper it uses has been defined or sourced — a suite this
# guards can no longer lose an assertion to silence the way r24e did.
require_helpers() {
  local missing="" name
  for name in "$@"; do
    type -t "$name" >/dev/null 2>&1 || missing="$missing $name"
  done
  if [ -n "$missing" ]; then
    echo "require_helpers: undefined:$missing" >&2
    exit 1
  fi
}
