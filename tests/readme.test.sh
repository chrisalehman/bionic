#!/bin/bash
# tests/readme.test.sh — the end-user README install section (epic-17
# wave-06-ux-cleanup slice S8; spec AC-4).
#
# Pins README.md's "## Installation (30-second setup)" section to the
# ratified reference shape (mattpocock/skills, record/epic-17-w6/step1-scope.md
# item 2): exactly two `claude plugin` command lines (marketplace add, install),
# the in-session twin `/plugin install bionic`, the `claude plugin list`
# troubleshooting fallback, and zero mechanism words (lane, 3a, 3b, register,
# registry, hook — AC-4's banned list).
#
# ASSERTION-HELPER RACE (tests/assert-helper-race.test.sh): no `... | grep -q`
# pipelines below. The install section is extracted to a scratch FILE and
# every check greps that file directly, never a pipe.
#
# HERMETIC. No network. Reads README.md only.
#
# Usage: bash tests/readme.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
README="${REPO}/README.md"

PASS=0
FAIL=0
TOTAL=0

# ---------- helpers ----------

expect_true() {
  local label="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    FAIL=$((FAIL + 1))
  fi
}

expect_eq() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (expected='$expected' actual='$actual')"
    FAIL=$((FAIL + 1))
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SECTION="$TMP/install-section.md"

# ============================================================
# README.md install section
# ============================================================

echo ""
echo "=== README.md install section ==="

expect_true "README.md exists" test -f "$README"

if [ -f "$README" ]; then
  expect_true "carries the '## Installation (30-second setup)' heading" \
    grep -qF "## Installation (30-second setup)" "$README"

  # Extract the section body: everything after the heading line up to (but
  # not including) the next "## " heading, or EOF.
  awk '
    /^## Installation \(30-second setup\)/ { found=1; next }
    found && /^## / { exit }
    found { print }
  ' "$README" >"$SECTION"

  expect_true "install section is non-empty" test -s "$SECTION"

  if [ -s "$SECTION" ]; then
    CLAUDE_PLUGIN_LINES="$(grep -cE '^claude plugin ' "$SECTION" 2>/dev/null || true)"
    expect_eq "exactly two 'claude plugin' command lines" "2" "${CLAUDE_PLUGIN_LINES:-0}"

    expect_true "contains 'claude plugin list' (troubleshooting fallback)" \
      grep -qF "claude plugin list" "$SECTION"

    expect_true "contains '/plugin install bionic' (in-session twin)" \
      grep -qF "/plugin install bionic" "$SECTION"

    for token in lane 3a 3b register registry hook; do
      expect_true "no banned token '${token}'" bash -c "! grep -qiF -- '${token}' '${SECTION}'"
    done
  else
    echo "SKIP: remaining checks (install section missing or empty)"
  fi
fi

# ============================================================
# Results
# ============================================================

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
