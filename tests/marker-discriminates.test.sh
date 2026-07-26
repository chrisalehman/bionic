#!/usr/bin/env bash
# tests/marker-discriminates.test.sh — behaviour gate for the mutation-and-
# restore harness (plan slice 4/2, spec R2, matrix AC-2).
#
# Sections:
#   1. a pointer whose test passes with the enforcement removed is reported
#      NON-DISCRIMINATING and the run exits non-zero        <- the slice's RED
#   2. a pointer whose test asserts the wall passes         <- the slice's GREEN
#   3. contrast: the same enforcer, two tests, opposite verdicts in one run
#   4. the deny mechanism is mutable too, not just exit 2
#   5. an enforcer with no blocking path is E-NO-MUTATION, not a pass
#   6. an already-failing test is E-BASELINE-RED, not a discrimination verdict
#   7. an unresolvable pointer is E-POINTER-MISSING
#   8. a surface with no WALL/FORM pointer is E-NO-POINTERS — a vacuous green is
#      the failure mode this wave exists to eliminate
#   9. restore proof: the harness reports byte-identity; the real fixture
#      enforcers are byte-identical to a snapshot taken before the first run;
#      the mutation operator demonstrably neuters; and the guard refuses to
#      write anywhere inside the repo at all
#
# Section 9 is the one that matters most. A harness that leaves a mutated
# enforcement path on disk is a catastrophe, not a bug, so restoration is
# asserted against a snapshot taken before the first run — never assumed.
#
# Usage: bash tests/marker-discriminates.test.sh

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS="$REPO/tests/marker-discriminates.sh"
FIX="tests/fixtures/mutation"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  $2"; FAIL=$((FAIL + 1)); }

OUT=""; RC=0
run_h() {  # run_h <surface>... — sets OUT and RC
  OUT="$(cd "$REPO" && bash "$HARNESS" "$@" 2>&1)"; RC=$?
}

expect_rc() { if [ "$RC" -eq "$2" ]; then pass "$1"; else fail "$1" "expected rc=$2 got rc=$RC"; fi; }
expect_out() { case "$OUT" in *"$2"*) pass "$1" ;; *) fail "$1" "missing: $2" ;; esac; }
expect_no_out() { case "$OUT" in *"$2"*) fail "$1" "unexpectedly present: $2" ;; *) pass "$1" ;; esac; }

# ---------- 0: snapshot the real tree before anything runs ----------
# Scoped to the files this suite OWNS. Byte-identity over files it does not own
# is an assertion about other writers, not about the harness: this repo is a
# multi-agent tree and a sibling slice editing hooks/ mid-run would fail it for
# a reason that has nothing to do with mutation. The fixture enforcers below are
# the ones the harness actually mutates, so they exercise exactly the code path
# that could damage a real one — there is no hook-specific branch in it. The
# guard that makes the property structural is asserted separately in 9d.
mkdir -p "$TMP/snapshot"
cp -R "$REPO/tests/fixtures/mutation" "$TMP/snapshot/mutation"

# ---------- 1: non-discriminating pointer (the slice's RED / AC-2) ----------
echo "== 1: a pointer that proves nothing =="

run_h "$FIX/nondiscriminating.md"
expect_rc "nondiscriminating.md exits non-zero" 1
expect_out "violation code E-NONDISCRIMINATING" "E-NONDISCRIMINATING"
expect_out "the useless test is named" "$FIX/gate-weak.test.sh"
expect_out "the enforcement that was removed is named" "$FIX/gate.sh"
expect_out "the claim site is named" "$FIX/nondiscriminating.md:7"
expect_out "the test did NOT go red under mutation" "mutated=GREEN"
expect_out "it is counted as checked but not as discriminating" "pointers=1 discriminating=0"

# ---------- 2: discriminating pointer (the slice's GREEN) ----------
echo "== 2: a pointer that proves the wall =="

run_h "$FIX/discriminating.md"
expect_rc "discriminating.md exits 0" 0
expect_out "verdict is DISCRIMINATES" "DISCRIMINATES"
expect_out "baseline green, mutated red, restored green" "baseline=GREEN mutated=RED restored=GREEN"
expect_out "both blocking paths were neutered" "2 blocking paths neutered"
expect_out "counted as discriminating" "pointers=1 discriminating=1"
expect_no_out "no violations reported" "E-"

# ---------- 3: contrast — same enforcer, opposite verdicts ----------
echo "== 3: same enforcer, two tests, opposite verdicts =="

run_h "$FIX/discriminating.md" "$FIX/nondiscriminating.md"
expect_rc "the run fails because one of the two proves nothing" 1
expect_out "two pointers checked, one discriminates" "pointers=2 discriminating=1"
expect_out "the honest one is still named honest" "DISCRIMINATES"
expect_out "the useless one is still named useless" "E-NONDISCRIMINATING"

# ---------- 4: the deny mechanism ----------
echo "== 4: permissionDecision deny is mutable too =="

run_h "$FIX/deny.md"
expect_rc "deny-enforced wall verifies" 0
expect_out "the deny payload is a blocking path" "1 blocking path neutered"
expect_out "the deny test discriminates" "DISCRIMINATES"

# ---------- 5: nothing to mutate ----------
echo "== 5: an enforcer with no blocking path =="

run_h "$FIX/noblock.md"
expect_rc "no blocking path exits non-zero" 1
expect_out "violation code E-NO-MUTATION" "E-NO-MUTATION"
expect_no_out "it is not miscalled non-discriminating" "E-NONDISCRIMINATING"

# ---------- 6: already-red baseline ----------
echo "== 6: an already-failing test =="

run_h "$FIX/baseline-red.md"
expect_rc "a red baseline exits non-zero" 1
expect_out "violation code E-BASELINE-RED" "E-BASELINE-RED"
expect_no_out "red-always is not reported as red-under-mutation" "DISCRIMINATES"

# ---------- 7: unresolvable pointer ----------
echo "== 7: a pointer that does not resolve =="

run_h "$FIX/pointer-gone.md"
expect_rc "a missing test exits non-zero" 1
expect_out "violation code E-POINTER-MISSING" "E-POINTER-MISSING"

# ---------- 8: nothing to prove is not a pass ----------
echo "== 8: a surface with no WALL/FORM pointer =="

run_h "$FIX/no-pointers.md"
expect_rc "an empty pointer set exits non-zero" 1
expect_out "violation code E-NO-POINTERS" "E-NO-POINTERS"

# ---------- 9: restore proof ----------
echo "== 9: restore is asserted, not assumed =="

# 9a: the harness says so itself, per enforcer.
run_h "$FIX/discriminating.md"
expect_out "9a: the harness asserts byte-identity after restore" "bytes=identical"
expect_out "9a: and re-runs the test green after restoring" "restored=GREEN"

# 9b: the real tree is byte-identical to the pre-run snapshot. Every run above
# has already happened at this point, including the ones that ended in failure.
if diff -r "$TMP/snapshot/mutation" "$REPO/tests/fixtures/mutation" >"$TMP/diff-fix" 2>&1; then
  pass "9b: real fixture enforcers are byte-identical after every run"
else
  fail "9b: real fixture enforcers are byte-identical after every run" "$(cat "$TMP/diff-fix")"
fi

# 9c: the mutation really is a mutation — the harness's own operator, applied to
# a throwaway copy, must change gate.sh and must take gate.test.sh red. Without
# this, "mutated=RED" could come from anything.
cp -R "$REPO/tests/fixtures/mutation" "$TMP/opcheck"
if (cd "$REPO" && MARKER_MUTATE_ONLY=1 bash "$HARNESS" "$TMP/opcheck/gate.sh" >/dev/null 2>&1); then
  if diff -q "$REPO/tests/fixtures/mutation/gate.sh" "$TMP/opcheck/gate.sh" >/dev/null 2>&1; then
    fail "9c: the mutation operator actually changes the enforcer" "gate.sh unchanged"
  else
    pass "9c: the mutation operator actually changes the enforcer"
  fi
  if bash "$TMP/opcheck/gate.test.sh" >/dev/null 2>&1; then
    fail "9c: the neutered enforcer no longer walls" "gate.test.sh still passed"
  else
    pass "9c: the neutered enforcer no longer walls"
  fi
  case "$(cat "$TMP/opcheck/gate.sh")" in
    *"exit 2"*) fail "9c: no exit 2 survives the mutation" "an exit 2 remains" ;;
    *) pass "9c: no exit 2 survives the mutation" ;;
  esac
else
  fail "9c: mutate-only mode runs" "MARKER_MUTATE_ONLY run exited non-zero"
fi

# 9d: the structural guard. The operator refuses any in-repo path outright, so
# the only way a real enforcement path could be neutered is through a bug the
# guard would have to be missing entirely for. Aimed at a fixture rather than at
# hooks/protect-main.sh on purpose: if the guard were ever inverted, this test
# must not be the thing that neuters a real wall.
before="$(cat "$REPO/$FIX/gate.sh")"
OUT="$(cd "$REPO" && MARKER_MUTATE_ONLY=1 bash "$HARNESS" "$FIX/gate.sh" 2>&1)"; RC=$?
expect_rc "9d: the operator refuses an in-repo path" 1
expect_out "9d: and says which path it refused" "refusing to neuter a path inside the repo"
if [ "$before" = "$(cat "$REPO/$FIX/gate.sh")" ]; then
  pass "9d: the refused file is unchanged"
else
  fail "9d: the refused file is unchanged" "gate.sh was written"
fi

echo
echo "Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
