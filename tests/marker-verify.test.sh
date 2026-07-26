#!/usr/bin/env bash
# tests/marker-verify.test.sh — behaviour gate for tests/marker-verify.sh.
#
# Sections (plan slice 4/1, spec R1/R3, matrix AC-1/AC-3):
#   1. unmarked normative statement -> non-zero, and the statement is NAMED
#   2. false binding claim (WALL naming a hook with no blocking path) -> non-zero
#   3. unclaimed blocking path (the two-way check) -> non-zero, both mechanisms
#   4. pointer hygiene: missing / absent / unexpected test pointers
#   5. unit granularity: list items, fences, a marker line above a blockquote
#   6. per-class totals are reported
#   7. meta-evidence: deleting a marker from a temp COPY of a passing fixture
#      makes it go RED, and the original still passes afterwards
#
# Section 7 is the durable form of the RED evidence. A green suite records that
# a fixture passes, never that it discriminates — mutation-and-restore on a
# working copy is what proves the fixture would catch the defect. Real fixtures
# are never mutated in place.
#
# Usage: bash tests/marker-verify.test.sh

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY="$REPO/tests/marker-verify.sh"
FIX="tests/fixtures/markers"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  $2"; FAIL=$((FAIL + 1)); }

OUT=""; RC=0
run_verify() {  # run_verify <path>... — sets OUT and RC
  OUT="$(cd "$REPO" && bash "$VERIFY" "$@" 2>&1)"; RC=$?
}

expect_rc() {  # expect_rc <label> <expected-rc>
  if [ "$RC" -eq "$2" ]; then pass "$1"; else fail "$1" "expected rc=$2 got rc=$RC"; fi
}

expect_out() {  # expect_out <label> <needle>
  case "$OUT" in
    *"$2"*) pass "$1" ;;
    *) fail "$1" "missing: $2" ;;
  esac
}

expect_no_out() {  # expect_no_out <label> <needle>
  case "$OUT" in
    *"$2"*) fail "$1" "unexpectedly present: $2" ;;
    *) pass "$1" ;;
  esac
}

# ---------- 1: unmarked normative statement (RED 1 / AC-1) ----------
echo "== 1: unmarked normative statement =="

run_verify "$FIX/unmarked.md"
expect_rc "unmarked.md exits non-zero" 1
expect_out "violation code E-UNMARKED" "E-UNMARKED"
expect_out "violation names the file:line" "$FIX/unmarked.md:5"
expect_out "violation quotes the offending statement" "dispatch a slice without a red test"
expect_out "summary counts the unmarked statement" "unmarked=1"
expect_no_out "the non-normative line is not reported" "binds nothing"

run_verify "$FIX/marked.md"
expect_rc "marked.md exits 0" 0
expect_out "marked.md still counts the statement" "normative=1"
expect_out "marked.md reports zero unmarked" "unmarked=0"
expect_out "marked.md classes it UNENFORCED" "UNENFORCED=1"

# ---------- 2: false binding claim (RED 2 / AC-3) ----------
echo "== 2: false binding claim =="

run_verify "$FIX/false-claim.md"
expect_rc "false-claim.md exits non-zero" 1
expect_out "violation code E-NO-BLOCKING" "E-NO-BLOCKING"
expect_out "violation names the enforcer it could not corroborate" "$FIX/no-block.sh"
expect_no_out "the pointer itself resolved (not a missing-file failure)" "E-POINTER-MISSING"

run_verify "$FIX/true-claim.md"
expect_rc "true-claim.md exits 0" 0
expect_out "true-claim.md classes it WALL" "WALL=1"

# ---------- 3: unclaimed blocking path — the two-way check (RED 3 / AC-3) ----------
echo "== 3: unclaimed blocking path =="

run_verify "$FIX/unclaimed-block.sh"
expect_rc "unclaimed-block.sh exits non-zero" 1
expect_out "violation code E-UNCLAIMED-BLOCK" "E-UNCLAIMED-BLOCK"
expect_out "violation names the blocking line" "$FIX/unclaimed-block.sh:5"
expect_out "the blocking site is counted" "sites=1"

run_verify "$FIX/claimed-block.sh"
expect_rc "claimed-block.sh exits 0" 0
expect_out "claimed site counted" "sites=1"
expect_out "no site left unclaimed" "unclaimed=0"

run_verify "$FIX/deny-unclaimed.sh"
expect_rc "deny mechanism: exits non-zero" 1
expect_out "deny mechanism is seen as blocking" "E-UNCLAIMED-BLOCK"
expect_out "deny mechanism named" "mechanism=deny"

run_verify "$FIX/comment-only.sh"
expect_rc "exit 2 inside a COMMENT is not enforcement" 0
expect_out "comment-only hook has zero blocking sites" "sites=0"

# ---------- 4: pointer hygiene ----------
echo "== 4: pointer hygiene =="

run_verify "$FIX/pointer-missing.md"
expect_rc "unresolvable pointer exits non-zero" 1
expect_out "violation code E-POINTER-MISSING" "E-POINTER-MISSING"

run_verify "$FIX/pointer-absent.md"
expect_rc "WALL without a pointer exits non-zero" 1
expect_out "violation code E-MISSING-POINTER" "E-MISSING-POINTER"

run_verify "$FIX/pointer-unexpected.md"
expect_rc "UNENFORCED carrying a pointer exits non-zero" 1
expect_out "violation code E-UNEXPECTED-POINTER" "E-UNEXPECTED-POINTER"

# ---------- 5: unit granularity ----------
echo "== 5: unit granularity =="

run_verify "$FIX/list-units.md"
expect_rc "a marker on one list item does not cover its sibling" 1
expect_out "the unmarked sibling is named" "$FIX/list-units.md:4"
expect_out "exactly one statement is unmarked" "unmarked=1"

run_verify "$FIX/fenced.md"
expect_rc "fenced code is not scanned" 0
expect_out "only the prose statement is counted" "normative=1"

run_verify "$FIX/blockquote.md"
expect_rc "a marker line directly above a quote covers it" 0

# ---------- 6: per-class totals ----------
echo "== 6: per-class totals =="

run_verify "$FIX/four-classes.md"
expect_rc "all four classes verify clean" 0
expect_out "WALL counted" "WALL=1"
expect_out "FORM counted" "FORM=1"
expect_out "INSTRUMENT counted" "INSTRUMENT=1"
expect_out "UNENFORCED counted" "UNENFORCED=1"
expect_out "four normative statements counted" "normative=4"

# ---------- 7: meta-evidence — mutation and restore ----------
echo "== 7: meta-evidence (mutation and restore) =="

# The fixtures are copied into $TMP and mutated THERE. Pointers inside the
# fixtures are repo-relative, so the copies are placed at the same repo-relative
# path inside a throwaway tree that symlinks back to the real repo for lookups.
mut_dir="$TMP/mut"
mkdir -p "$mut_dir/$FIX"

# 7a: strip the marker from a passing prose fixture -> must go RED
sed 's/ \[UNENFORCED\]//' "$REPO/$FIX/marked.md" > "$mut_dir/$FIX/marked.md"
OUT="$(cd "$REPO" && bash "$VERIFY" "$mut_dir/$FIX/marked.md" 2>&1)"; RC=$?
expect_rc "7a: marked.md without its marker goes RED" 1
expect_out "7a: the mutation is reported as unmarked" "E-UNMARKED"

# 7b: strip the marker from a passing hook fixture -> the blocking path unclaims
sed 's/ \[WALL: [^]]*\]//' "$REPO/$FIX/claimed-block.sh" > "$mut_dir/$FIX/claimed-block.sh"
OUT="$(cd "$REPO" && bash "$VERIFY" "$mut_dir/$FIX/claimed-block.sh" 2>&1)"; RC=$?
expect_rc "7b: claimed-block.sh without its marker goes RED" 1
expect_out "7b: the blocking path is reported unclaimed" "E-UNCLAIMED-BLOCK"

# 7c: restore is asserted, not assumed — the real fixtures still pass
run_verify "$FIX/marked.md" "$FIX/claimed-block.sh"
expect_rc "7c: unmutated fixtures still pass after mutation" 0

echo
echo "Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
