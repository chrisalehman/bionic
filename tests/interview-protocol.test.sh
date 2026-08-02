#!/bin/bash
# Pin/agreement suite for canonical-sdlc's mandatory design-interview protocol
# (epic-14 wave-03). Pins exact phrases that slices 4/2 and 4/3 introduce into
# skills/canonical-sdlc/SKILL.md and skills/canonical-sdlc/operational-rules.md.
#
# This suite is written BEFORE those slices land, so it is expected to FAIL now
# (RED evidence) and turn green only once 4/2 and 4/3 have written the pinned
# text.
#
# Usage: bash tests/interview-protocol.test.sh

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="${REPO}/skills/canonical-sdlc/SKILL.md"
RULES="${REPO}/skills/canonical-sdlc/operational-rules.md"

PASS=0
FAIL=0
TOTAL=0

# ---------- helpers ----------

# expect_pin_in_file <label> <needle> <file>
# Fixed-string (grep -F) presence check. Names the missing string and file on
# failure so a RED run is self-explanatory.
expect_pin_in_file() {
  local label="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$file" 2>/dev/null; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (missing '$needle' in $file)"
    FAIL=$((FAIL + 1))
  fi
}

# expect_pin_count_in_file <label> <needle> <file> <min_count>
expect_pin_count_in_file() {
  local label="$1" needle="$2" file="$3" min_count="$4"
  local actual
  TOTAL=$((TOTAL + 1))
  actual="$(grep -cF -- "$needle" "$file" 2>/dev/null || true)"
  actual="${actual:-0}"
  if [ "$actual" -ge "$min_count" ]; then
    echo "PASS: $label (found ${actual}x)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (found ${actual}x, need >= ${min_count}, needle='$needle', file=$file)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================
# SECTION 1: Agreement pins — must appear in BOTH SKILL.md and
# operational-rules.md
# ============================================================

echo ""
echo "=== Section 1: Agreement pins (SKILL.md AND operational-rules.md) ==="

AGREEMENT_PINS=(
  "Design intuition"
  "Requirements served"
  "full Technical Design Document"
)

for pin in "${AGREEMENT_PINS[@]}"; do
  expect_pin_in_file "agreement pin in SKILL.md: '${pin}'" "$pin" "$SKILL"
  expect_pin_in_file "agreement pin in operational-rules.md: '${pin}'" "$pin" "$RULES"
done

# ============================================================
# SECTION 2: SKILL.md-only pins
# ============================================================

echo ""
echo "=== Section 2: SKILL.md-only pins ==="

expect_pin_in_file "SKILL.md pin: 'one decision per turn'" "one decision per turn" "$SKILL"
expect_pin_in_file "SKILL.md pin: 'surfaced at ratification'" "surfaced at ratification" "$SKILL"
expect_pin_in_file "SKILL.md pin: \"before the spec's first Write\"" "before the spec's first Write" "$SKILL"

# 'design-interview:' must appear at least twice — once in the Step-0 prose,
# once in the confirmation-display template block.
expect_pin_count_in_file "SKILL.md pin: 'design-interview:' appears >= 2x (Step-0 prose + confirmation template)" \
  "design-interview:" "$SKILL" 2

# ============================================================
# SECTION 3: operational-rules.md-only pins
# ============================================================

echo ""
echo "=== Section 3: operational-rules.md-only pins ==="

expect_pin_in_file "operational-rules.md pin: 'standalone design doc'" "standalone design doc" "$RULES"
expect_pin_in_file "operational-rules.md pin: 'C4'" "C4" "$RULES"
expect_pin_in_file "operational-rules.md pin: 'suggested default'" "suggested default" "$RULES"

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
