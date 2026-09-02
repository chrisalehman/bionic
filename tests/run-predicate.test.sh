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
echo
echo "=== run-predicate: $PASS/$TOTAL passed ==="
[ "$FAIL" -eq 0 ] || echo "FAILURES: $FAIL"
[ "$FAIL" -eq 0 ]
