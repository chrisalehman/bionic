#!/bin/bash
# tests/runner-width.test.sh — tests/run.sh takes its job width from the machine's own
# pressure rung (wave-roster-lifecycle S9, spec AC-15, R4).
#
# WHAT CHANGED. `JOBS="${BIONIC_TEST_JOBS:-8}"` — a literal a caller had to notice and set —
# became `pressure_sample` then `JOBS="$(pressure_level "${BIONIC_TEST_JOBS_CEILING:-8}")"`:
# one fresh reading, then the median-smoothed rung over resources.sh's ring, read against a
# ceiling. `BIONIC_TEST_JOBS` is retired as an input; a caller who still sets it is told once,
# on stderr, and ignored.
#
# THE ONLY SAFE WAY TO DRIVE THIS is `tests/run.sh --dry-run` (added by this same slice):
# it computes JOBS exactly as a real invocation would — sampling the ring, reading the
# rung — and prints it, without launching the 40-plus-suite roster a real run would. Every
# case below drives the REAL runner script this way; nothing here reimplements the width
# computation.
#
# FIXTURE DISCIPLINE (Fail-closed constants idiom, resources.sh:154). `BIONIC_PRESSURE_RING`
# always points under this suite's own mktemp root — never the real
# `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/pressure.ring` — and `BIONIC_NOW_EPOCH` pins the
# clock so every ring line this suite writes lands inside the smoothing window regardless of
# wall-clock time. `BIONIC_PROBE_FREE_PCT` / `BIONIC_PROBE_SWAP_PCT` / `BIONIC_PROBE_LOAD_1M`
# pin the reading `tests/run.sh`'s OWN internal `pressure_sample` call takes, so the fresh
# line it appends agrees with the band the pre-seeded ring already carries — a case is not
# left to the real, unpinned state of the machine running this suite.
#
# Usage: bash tests/runner-width.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

RUN="${BIONIC_SCRIPTS_DIR}/tests/run.sh"

PASS=0; FAIL=0; TOTAL=0
ok()  { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
bad() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }
expect_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }
expect_contains() { if grep -qF -- "$2" <<<"$3"; then ok "$1"; else bad "$1" "missing: $2"; fi; }
expect_absent()   { if grep -qF -- "$2" <<<"$3"; then bad "$1" "unexpectedly present: $2"; else ok "$1"; fi; }

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/runner-width-test.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT

NOW=1700000000

# ring_of <path> <epoch> <sample>... — rewrite a ring with one line per sample, all at <epoch>
ring_of() {
  local path="$1" t="$2"; shift 2
  mkdir -p "$(dirname "$path")"
  : > "$path"
  local s
  for s in "$@"; do printf '%s|%s\n' "$t" "$s" >> "$path"; done
}

# dry_run <ring> <probe-sample> [ceiling-env-assignment]
# Runs the REAL tests/run.sh --dry-run with the ring, clock and probe pinned so its own
# internal pressure_sample call agrees with the band the pre-seeded ring already carries.
DRY_OUT=""; DRY_ERR=""; DRY_ST=0
dry_run() {
  local ring="$1" sample="$2" ceiling_env="${3:-}"
  local f s l c
  IFS='|' read -r f s l c <<<"$sample"
  DRY_OUT=$(cd "$BIONIC_SCRIPTS_DIR" && \
    env BIONIC_PRESSURE_RING="$ring" BIONIC_NOW_EPOCH="$NOW" \
        BIONIC_PROBE_FREE_PCT="$f" BIONIC_PROBE_SWAP_PCT="$s" BIONIC_PROBE_LOAD_1M="$l" \
        ${ceiling_env:+BIONIC_TEST_JOBS_CEILING="$ceiling_env"} \
        bash "$RUN" --dry-run 2>"$TMPROOT/.err")
  DRY_ST=$?
  DRY_ERR=$(cat "$TMPROOT/.err")
}

# The plan's band table (S7/§I), reused verbatim: free|swap|load|cores.
S_CLEAR='44|69|1.6|8'
S_CRIT='10|50|1|8'

echo "=== Section 1: --dry-run prints JOBS=<n> and exits before any suite runs ==="

# (a) a critical ring at ceiling 8 -> the quartered rung, 2.
RING_A="$TMPROOT/a/pressure.ring"
ring_of "$RING_A" "$NOW" "$S_CRIT" "$S_CRIT"
dry_run "$RING_A" "$S_CRIT" 8
expect_eq   "1a a critical ring at ceiling 8 prints JOBS=2" "0" "$DRY_ST"
expect_contains "1a …exactly that line" "JOBS=2" "$DRY_OUT"

# (b) a clear ring at ceiling 8 -> the full ceiling, 8.
RING_B="$TMPROOT/b/pressure.ring"
ring_of "$RING_B" "$NOW" "$S_CLEAR" "$S_CLEAR"
dry_run "$RING_B" "$S_CLEAR" 8
expect_contains "1b a clear ring at ceiling 8 prints JOBS=8" "JOBS=8" "$DRY_OUT"

# (c) no BIONIC_TEST_JOBS_CEILING at all -> the old default of 8 is the ceiling.
RING_C="$TMPROOT/c/pressure.ring"
ring_of "$RING_C" "$NOW" "$S_CLEAR" "$S_CLEAR"
dry_run "$RING_C" "$S_CLEAR"
expect_contains "1c no ceiling var: the default ceiling is 8" "JOBS=8" "$DRY_OUT"
# Sharper than (c) alone: a critical ring with no ceiling var quarters exactly 8, not some
# other unstated default.
RING_C2="$TMPROOT/c2/pressure.ring"
ring_of "$RING_C2" "$NOW" "$S_CRIT" "$S_CRIT"
dry_run "$RING_C2" "$S_CRIT"
expect_contains "1c …confirmed against a critical ring too (quarters 8, not another default)" \
  "JOBS=2" "$DRY_OUT"

echo
echo "=== Section 2: the run appends one sample to the ring ==="

RING_D="$TMPROOT/d/pressure.ring"
ring_of "$RING_D" "$NOW" "$S_CLEAR" "$S_CLEAR"
BEFORE_LINES=$(wc -l < "$RING_D" | tr -d ' ')
dry_run "$RING_D" "$S_CLEAR" 8
AFTER_LINES=$(wc -l < "$RING_D" | tr -d ' ')
expect_eq "2 the ring gained exactly one line" "$((BEFORE_LINES + 1))" "$AFTER_LINES"

echo
echo "=== Section 3: BIONIC_TEST_JOBS is retired ==="

RING_E="$TMPROOT/e/pressure.ring"
ring_of "$RING_E" "$NOW" "$S_CLEAR"
DRY_OUT=""; DRY_ERR=""
DRY_OUT=$(cd "$BIONIC_SCRIPTS_DIR" && \
  env BIONIC_PRESSURE_RING="$RING_E" BIONIC_NOW_EPOCH="$NOW" \
      BIONIC_PROBE_FREE_PCT=44 BIONIC_PROBE_SWAP_PCT=69 BIONIC_PROBE_LOAD_1M=1.6 \
      BIONIC_TEST_JOBS=4 BIONIC_TEST_JOBS_CEILING=8 \
      bash "$RUN" --dry-run 2>"$TMPROOT/.err3")
DRY_ERR=$(cat "$TMPROOT/.err3")
expect_contains "3a a caller who still sets BIONIC_TEST_JOBS is told once, on stderr" \
  "BIONIC_TEST_JOBS is retired" "$DRY_ERR"
expect_contains "3b …and the value is ignored: width still comes from the rung (clear -> 8, not 4)" \
  "JOBS=8" "$DRY_OUT"

# A caller who never set it at all gets no notice.
RING_F="$TMPROOT/f/pressure.ring"
ring_of "$RING_F" "$NOW" "$S_CLEAR"
dry_run "$RING_F" "$S_CLEAR" 8
expect_absent "3c no notice when BIONIC_TEST_JOBS was never set" "BIONIC_TEST_JOBS is retired" "$DRY_ERR"

echo
echo "=== Section 4: registration (hook-authoring convention) ==="

# THE SUITE IS REGISTERED. tests/*.test.sh is NOT globbed by the runner — an unregistered
# suite is a silent false green (pattern: tests/patrol-duties-gate.test.sh Group 24).
if grep -q 'run "runner-width.test.sh" bash tests/runner-width.test.sh' \
     "${BIONIC_SCRIPTS_DIR}/tests/run.sh"; then
  ok "4 tests/run.sh names runner-width.test.sh"
else
  bad "4 tests/run.sh does not name this suite — it would never run"
fi

echo
echo "──────────────────────────────────────────────"
echo "runner-width.test.sh: ${PASS}/${TOTAL} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
