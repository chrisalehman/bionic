#!/bin/bash
# tests/run-predicate.test.sh — payload/scripts/lib/run.sh: docs_root, active_plan,
# active_run (L-RUN, wave-bionic-1.4.0-update, spec AC-8; plan design-ledger S1).
#
# WHAT IT OWNS. The "is there a run to protect" predicate: active_run <root> is exit 0 +
# the plan path iff the newest plan (by mtime) under the docs root's plans/incidents trees
# carries a flush-left `## SDLC State` and an open state — `current:` 0-8, or 9 without a
# `- Step 9:` line carrying `delivered:`, or a task-scale `current: T<n>` — and the plan's
# frontmatter carries no `abandoned:` line; else exit 1 and prints nothing. Every always-on
# hook gates its own work behind this one call (ADOPT, Batch 1).
#
# FIXTURES mirror the plan's own SDLC State block shape (wave.plan.md's frontmatter and
# Step lines). The plan-search shape referenced for context is
# hooks/canonical-sdlc-evidence-gate.sh's resolve_docs_root/current-parsing — read for
# shape only, not copied: this library's interface is the simpler, single-purpose one the
# plan states (no fence-awareness, no misplacement sweep), not a restatement of the gate's
# richer parser.
#
# HERMETIC. Every plan is a fixture file under a mktemp sandbox; nothing reads a real
# .bionic tree or a live wave.
#
# Usage: bash tests/run-predicate.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
LIB="$REPO_ROOT/payload/scripts/lib/run.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/run-predicate-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

PASS=0
FAIL=0
TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }
expect_eq()    { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$2], got [$3]"; fi; }
expect_empty() { if [ -z "$2" ]; then ok "$1"; else no "$1" "expected no output, got: $2"; fi; }

# ============================================================
echo "=== R0 — the library exists and parses ==="
# ============================================================
if [ -f "$LIB" ]; then ok "payload/scripts/lib/run.sh is on disk"; else
  no "payload/scripts/lib/run.sh is on disk" "$LIB"
fi
if bash -n "$LIB" 2>"$SANDBOX/.syn"; then ok "the library parses (bash -n)"; else
  no "the library parses (bash -n)" "$(cat "$SANDBOX/.syn")"
fi

# Sourcing prints nothing (plan: "Functions only; sourcing prints nothing.")
SRC_OUT=$(bash -c '. "$1" 2>&1' _ "$LIB")
expect_empty "sourcing the library prints nothing" "$SRC_OUT"

# ---- driven through a child bash that sources the library ----
call_docs_root() {  # <root> -> stdout
  bash -c '. "$1" || exit 1; docs_root "$2"' _ "$LIB" "$1" 2>"$SANDBOX/.err"
}
AR_OUT=""; AR_ST=0
call_active_run() {  # <root> -> sets AR_OUT, AR_ST
  AR_OUT=$(bash -c '. "$1" || exit 1; active_run "$2"' _ "$LIB" "$1" 2>"$SANDBOX/.err")
  AR_ST=$?
}
# call_active_run_pf <root> -> sets AR_OUT, AR_ST, from a child bash with `set -uo
# pipefail` ENABLED IN THAT CHILD. `set -o` options are shell-local, not inherited by a
# nested `bash -c` merely because the parent process has them set (verified: SHELLOPTS
# does not carry pipefail across this bash's own `bash -c` boundary on this machine) — so
# call_active_run above, run under this suite's own top-of-file `set -uo pipefail`,
# NEVER actually exercises active_run under pipefail; every hook that calls this library
# sources it directly in ITS OWN shell, where its own `set -uo pipefail` (dispatch-preflight
# .sh:66 et al.) is genuinely in effect. This helper re-states the option inside the child
# so the R4 fixtures below test the real production condition, not an inherited illusion
# of it (AC-21).
call_active_run_pf() {
  AR_OUT=$(bash -c 'set -uo pipefail; . "$1" || exit 1; active_run "$2"' _ "$LIB" "$1" 2>"$SANDBOX/.err")
  AR_ST=$?
}
AP_OUT=""; AP_ST=0
call_active_plan() {  # <root> -> sets AP_OUT, AP_ST
  AP_OUT=$(bash -c '. "$1" || exit 1; active_plan "$2"' _ "$LIB" "$1" 2>"$SANDBOX/.err")
  AP_ST=$?
}

# ============================================================
echo "=== R1 — docs_root: default and .bionic/config.yaml override ==="
# ============================================================
ROOT1="$SANDBOX/r1"
mkdir -p "$ROOT1/.bionic"
expect_eq "docs_root defaults to <root>/.bionic/docs" "$ROOT1/.bionic/docs" "$(call_docs_root "$ROOT1")"

printf 'docs-root: .bionic/other-docs\n' > "$ROOT1/.bionic/config.yaml"
expect_eq "docs_root honours a relative docs-root: override" \
  "$ROOT1/.bionic/other-docs" "$(call_docs_root "$ROOT1")"

printf 'docs-root: /elsewhere/docs\n' > "$ROOT1/.bionic/config.yaml"
expect_eq "docs_root honours an absolute docs-root: override" \
  "/elsewhere/docs" "$(call_docs_root "$ROOT1")"
rm -f "$ROOT1/.bionic/config.yaml"

# ============================================================
echo "=== R2 — active_plan / active_run fixtures ==="
# ============================================================
# mk_plan <root> <name under docs/plans> <current-line-body> [extra-lines...]
# Writes a plan with the plan's own frontmatter/SDLC-State shape (wave.plan.md), prints
# its absolute path.
mk_plan() {
  local root="$1" name="$2" current="$3"
  shift 3
  local dir; dir="$root/.bionic/docs/plans"
  mkdir -p "$dir"
  {
    echo "---"
    echo "governing-skill: superpowers:writing-plans"
    echo "sdlc-step: 3"
    echo "---"
    echo
    echo "# fixture plan"
    echo
    echo "## SDLC State"
    echo
    echo "integration-branch: main"
    echo "current: $current"
    for l in "$@"; do echo "$l"; done
  } > "$dir/$name"
  printf '%s/%s\n' "$dir" "$name"
}

# --- current 4 -> active ---
R="$SANDBOX/r2a"; mkdir -p "$R/.bionic"
P=$(mk_plan "$R" "wave.plan.md" "4" "- Step 4: in progress")
call_active_run "$R"
expect_eq "current: 4 -> active_run exits 0" 0 "$AR_ST"
expect_eq "current: 4 -> active_run prints the plan path" "$P" "$AR_OUT"

# --- current 9 without a delivered Step 9 line -> active ---
R="$SANDBOX/r2b"; mkdir -p "$R/.bionic"
P=$(mk_plan "$R" "wave.plan.md" "9" "- Step 9: report drafted, not yet delivered")
call_active_run "$R"
expect_eq "current: 9 without 'delivered:' -> active_run exits 0" 0 "$AR_ST"
expect_eq "current: 9 without 'delivered:' -> prints the plan path" "$P" "$AR_OUT"

# --- current 9 WITH a delivered Step 9 line -> inactive ---
R="$SANDBOX/r2c"; mkdir -p "$R/.bionic"
mk_plan "$R" "wave.plan.md" "9" "- Step 9: report record/x.md, delivered: 2026-09-02" >/dev/null
call_active_run "$R"
expect_eq "current: 9 with 'delivered:' -> active_run exits 1" 1 "$AR_ST"
expect_empty "current: 9 with 'delivered:' -> prints nothing" "$AR_OUT"

# --- frontmatter abandoned: line -> inactive ---
R="$SANDBOX/r2d"; mkdir -p "$R/.bionic/docs/plans"
cat > "$R/.bionic/docs/plans/wave.plan.md" <<'EOF'
---
governing-skill: superpowers:writing-plans
sdlc-step: 3
abandoned: chris 2026-09-02
---

## SDLC State

current: 4
- Step 4: in progress
EOF
call_active_run "$R"
expect_eq "frontmatter abandoned: -> active_run exits 1" 1 "$AR_ST"
expect_empty "frontmatter abandoned: -> prints nothing" "$AR_OUT"

# --- no plans dir -> inactive ---
R="$SANDBOX/r2e"; mkdir -p "$R/.bionic"
call_active_run "$R"
expect_eq "no plans dir -> active_run exits 1" 1 "$AR_ST"
expect_empty "no plans dir -> prints nothing" "$AR_OUT"

# --- task-scale current: T2 -> active ---
R="$SANDBOX/r2f"; mkdir -p "$R/.bionic"
P=$(mk_plan "$R" "task.plan.md" "T2" "- T2: in progress")
call_active_run "$R"
expect_eq "current: T2 -> active_run exits 0" 0 "$AR_ST"
expect_eq "current: T2 -> prints the plan path" "$P" "$AR_OUT"

# --- newest-by-mtime wins over an older closed plan ---
R="$SANDBOX/r2g"; mkdir -p "$R/.bionic"
OLD=$(mk_plan "$R" "old.plan.md" "9" "- Step 9: report record/x.md, delivered: 2026-08-01")
touch -t 202601010000 "$OLD"
NEW=$(mk_plan "$R" "new.plan.md" "4" "- Step 4: in progress")
call_active_plan "$R"
expect_eq "active_plan picks the newest file by mtime" "$NEW" "$AP_OUT"
call_active_run "$R"
expect_eq "newest-by-mtime (open) wins over an older closed plan -> active_run exits 0" 0 "$AR_ST"
expect_eq "…and prints the newer plan's path" "$NEW" "$AR_OUT"

# ============================================================
echo "=== R3 — the plan-search DEPTH BOUND is 2, and it is the fleet's only one ==="
# ============================================================
#
# THE BOUND IS A CONTRACT, not an implementation detail, and it is pinned here because this
# library is now the ONE reader of "which *.md answers for this run" (POKER/2, ratified
# 2026-09-03: the tick's private copy is deleted and every hook asks this function). Two
# depths were live during the wave — the five hand-copies and the evidence gate walked 2,
# which is the bionic layout's own depth (`plans/<epic>/<wave>.plan.md`), and L-RUN shipped
# 3 — and tests/cross-gate-agreement.test.sh §S.3d PINNED the disagreement rather than
# papering over it. Unification resolves it AT 2: the gate's descend-2 read is the one held
# body-for-body by §S, deeper files under `plans/` are notes and scratch rather than plans,
# and a bound nobody can state from the layout is a bound that drifts again.
#
# BOTH DIRECTIONS, because the shallow half alone would pass on a library that had no bound
# at all: depth 2 is FOUND, depth 3 is NOT.
R="$SANDBOX/r3a"; mkdir -p "$R/.bionic/docs/plans/epic-99"
P2="$R/.bionic/docs/plans/epic-99/wave-01.plan.md"
{ echo "# fixture plan"; echo; echo "## SDLC State"; echo; echo "current: 4"; } > "$P2"
call_active_plan "$R"
expect_eq "a plan at depth 2 (plans/<epic>/<wave>.md) is found" "$P2" "$AP_OUT"

R="$SANDBOX/r3b"; mkdir -p "$R/.bionic/docs/plans/epic-99/sub"
P3="$R/.bionic/docs/plans/epic-99/sub/wave-01.plan.md"
{ echo "# fixture plan"; echo; echo "## SDLC State"; echo; echo "current: 4"; } > "$P3"
call_active_plan "$R"
expect_eq "a plan at depth 3 is OUT of the bound -> active_plan exits 1" 1 "$AP_ST"
expect_empty "…and prints nothing" "$AP_OUT"
call_active_run "$R"
expect_eq "…so active_run does not see it either" 1 "$AR_ST"

# The bound is on the SEARCH, not on the docs root: the same file one level shallower is
# found, so R3b measures the depth and not some other property of the fixture.
mv "$R/.bionic/docs/plans/epic-99/sub/wave-01.plan.md" "$R/.bionic/docs/plans/epic-99/"
call_active_plan "$R"
expect_eq "…while the same file at depth 2 is found (the fixture measures depth)" \
  "$R/.bionic/docs/plans/epic-99/wave-01.plan.md" "$AP_OUT"

# ============================================================
echo
echo "=== R4 — SIGPIPE-under-pipefail does not flip a >64 KB plan's verdict (AC-21) ==="
# ============================================================
#
# WHY THIS SECTION EXISTS AND R0-R3 DID NOT CATCH IT (research-refusal.md VERDICT,
# 2026-09-03). `active_run` decides Step 9 by `_run_lines "$plan" | grep -qE
# '…delivered:'`. `grep -q`/`-m1` exit at their FIRST match; the awk feeding them is
# still writing when a match sits well before end-of-file, awk takes SIGPIPE and reports
# 141, and this whole suite runs under `set -uo pipefail` (line 24) — same as every hook
# that calls this library — so the PIPELINE's status becomes 141, not the grep's own 0.
# `if pipeline; then return 1; fi` reads that as false: a CLOSED run (current: 9,
# `delivered:` present) falls through to the Step-9-open arm and reads OPEN. Every fixture
# in R0-R3 is a handful of lines, so `awk` always finishes writing before `grep` even
# looks — too small to reach the SIGPIPE window at all. This section is the one place in
# the suite where the fixture is deliberately padded PAST that window, on this shell's own
# options, so a regression here is caught by size rather than only by content.
#
# THE MEASURED THRESHOLD (research-refusal.md INSTRUMENT §threshold table, this machine):
# 16 167 bytes never flips, 20 214 bytes flips 5/5. 64 KB is the plan's own AC-21 floor —
# comfortably past the measured knee — so every fixture below pads to that literal target,
# and each one asserts its own size to keep the premise visible if the target ever drifts.

mk_filler() {  # <min-bytes> -> that many-or-more bytes of inert filler lines on stdout
  local target="$1" n=0
  while [ "$n" -lt "$target" ]; do
    echo "filler filler filler filler filler filler filler filler filler filler"
    n=$((n + 72))
  done
}
FILLER_TARGET=70000   # > 64 KB (65536) with margin

# --- Step 9 delivered:, filler AFTER the state block, > 64 KB -> CLOSED ---
R="$SANDBOX/r4a"; mkdir -p "$R/.bionic/docs/plans"
F="$R/.bionic/docs/plans/wave.plan.md"
{
  echo "---"
  echo "governing-skill: superpowers:writing-plans"
  echo "sdlc-step: 9"
  echo "---"
  echo
  echo "# fixture plan"
  echo
  echo "## SDLC State"
  echo
  echo "integration-branch: main"
  echo "current: 9"
  echo "- Step 9: report record/x.md, delivered: 2026-09-02"
  echo
  echo "## Notes"
  echo
  mk_filler "$FILLER_TARGET"
} > "$F"
SZ=$(wc -c < "$F" | tr -d '[:space:]')
expect_eq "r4a fixture is actually past 64 KB (size=$SZ)" "yes" "$([ "$SZ" -gt 65536 ] && echo yes || echo no)"
call_active_run_pf "$R"
expect_eq "Step 9 delivered:, filler AFTER state, >64 KB -> active_run exits 1 (closed)" 1 "$AR_ST"
expect_empty "…and prints nothing" "$AR_OUT"

# --- Step 9 delivered:, filler BEFORE the state block, > 64 KB -> CLOSED ---
R="$SANDBOX/r4b"; mkdir -p "$R/.bionic/docs/plans"
F="$R/.bionic/docs/plans/wave.plan.md"
{
  echo "---"
  echo "governing-skill: superpowers:writing-plans"
  echo "sdlc-step: 9"
  echo "---"
  echo
  echo "# fixture plan"
  echo
  echo "## Notes"
  echo
  mk_filler "$FILLER_TARGET"
  echo
  echo "## SDLC State"
  echo
  echo "integration-branch: main"
  echo "current: 9"
  echo "- Step 9: report record/x.md, delivered: 2026-09-02"
} > "$F"
SZ=$(wc -c < "$F" | tr -d '[:space:]')
expect_eq "r4b fixture is actually past 64 KB (size=$SZ)" "yes" "$([ "$SZ" -gt 65536 ] && echo yes || echo no)"
call_active_run_pf "$R"
expect_eq "Step 9 delivered:, filler BEFORE state, >64 KB -> active_run exits 1 (closed)" 1 "$AR_ST"
expect_empty "…and prints nothing" "$AR_OUT"

# --- paired positive: current: 4, > 64 KB -> stays OPEN ---
R="$SANDBOX/r4c"; mkdir -p "$R/.bionic/docs/plans"
F="$R/.bionic/docs/plans/wave.plan.md"
{
  echo "---"
  echo "governing-skill: superpowers:writing-plans"
  echo "sdlc-step: 4"
  echo "---"
  echo
  echo "# fixture plan"
  echo
  echo "## SDLC State"
  echo
  echo "integration-branch: main"
  echo "current: 4"
  echo "- Step 4: in progress"
  echo
  echo "## Notes"
  echo
  mk_filler "$FILLER_TARGET"
} > "$F"
SZ=$(wc -c < "$F" | tr -d '[:space:]')
expect_eq "r4c fixture is actually past 64 KB (size=$SZ)" "yes" "$([ "$SZ" -gt 65536 ] && echo yes || echo no)"
call_active_run_pf "$R"
expect_eq "current: 4, >64 KB -> active_run exits 0 (open, paired positive)" 0 "$AR_ST"
expect_eq "…and prints the plan path" "$F" "$AR_OUT"

# --- paired positive: frontmatter abandoned:, > 64 KB -> CLOSED ---
R="$SANDBOX/r4d"; mkdir -p "$R/.bionic/docs/plans"
F="$R/.bionic/docs/plans/wave.plan.md"
{
  echo "---"
  echo "governing-skill: superpowers:writing-plans"
  echo "sdlc-step: 4"
  echo "abandoned: chris 2026-09-03"
  echo "---"
  echo
  echo "# fixture plan"
  echo
  echo "## SDLC State"
  echo
  echo "integration-branch: main"
  echo "current: 4"
  echo "- Step 4: in progress"
  echo
  echo "## Notes"
  echo
  mk_filler "$FILLER_TARGET"
} > "$F"
SZ=$(wc -c < "$F" | tr -d '[:space:]')
expect_eq "r4d fixture is actually past 64 KB (size=$SZ)" "yes" "$([ "$SZ" -gt 65536 ] && echo yes || echo no)"
call_active_run_pf "$R"
expect_eq "frontmatter abandoned:, >64 KB -> active_run exits 1 (closed, paired positive)" 1 "$AR_ST"
expect_empty "…and prints nothing" "$AR_OUT"

# ============================================================
echo
echo "=== run-predicate: $PASS/$TOTAL passed ==="
[ "$FAIL" -eq 0 ] || echo "FAILURES: $FAIL"
[ "$FAIL" -eq 0 ]
