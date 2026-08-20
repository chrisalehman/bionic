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

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
SKILL="${BIONIC_SKILLS_DIR}/canonical-sdlc/SKILL.md"
RULES="${BIONIC_SKILLS_DIR}/canonical-sdlc/operational-rules.md"
README="${REPO}/README.md"

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
  "ratifies the frame"
  "as a named delta the turn it lands"
  # The Step-0 flag and the op-rules waiver are ONE waiver with two renderings,
  # not two discharge paths. Both files must carry the phrase that says so, or
  # a cold agent can read `design-interview: false` as discharging the
  # quote-in-assumptions obligation on its own (Step-6 review FLAG 1).
  "standing Step-0 form"
)

for pin in "${AGREEMENT_PINS[@]}"; do
  expect_pin_in_file "agreement pin in SKILL.md: '${pin}'" "$pin" "$SKILL"
  expect_pin_in_file "agreement pin in operational-rules.md: '${pin}'" "$pin" "$RULES"
done

# Count-scoped agreement pins: operational-rules.md repeats each of these
# phrases a second time in a worked example, after the normative bullet that
# introduces it. A presence-only pin on that side cannot tell "normative
# bullet deleted, worked-example copy survives" from "both survive" — either
# way the phrase is still present at least once. Requiring >= 2 here forces
# deletion of the normative occurrence to go red even while the worked example
# keeps the phrase alive (Step-5 audit Hole finding, wave-03-interview-protocol
# remediation). The SKILL.md side stays a plain presence pin — it only has the
# phrase once.
AGREEMENT_PINS_COUNT_SCOPED=(
  "Design intuition"
  "Requirements served"
  "full Technical Design Document"
)

for pin in "${AGREEMENT_PINS_COUNT_SCOPED[@]}"; do
  expect_pin_in_file "agreement pin in SKILL.md: '${pin}'" "$pin" "$SKILL"
  expect_pin_count_in_file "agreement pin in operational-rules.md: '${pin}' appears >= 2x (normative bullet + worked example)" \
    "$pin" "$RULES" 2
done

# ============================================================
# SECTION 2: SKILL.md-only pins
# ============================================================

echo ""
echo "=== Section 2: SKILL.md-only pins ==="

expect_pin_in_file "SKILL.md pin: 'one decision per turn'" "one decision per turn" "$SKILL"
expect_pin_in_file "SKILL.md pin: 'surfaced at ratification'" "surfaced at ratification" "$SKILL"
expect_pin_in_file "SKILL.md pin: \"before the spec's first Write\"" "before the spec's first Write" "$SKILL"
expect_pin_in_file "SKILL.md pin: 'Derivation heuristics live in'" "Derivation heuristics live in" "$SKILL"

# Two line-anchored pins replace the old count>=2 check on the bare substring
# 'design-interview:' (Step-5 remediation wave-03-interview-protocol). A bare
# count passes as long as SOME mentions of the substring survive anywhere in
# the file — it cannot tell that the two load-bearing sites specifically, the
# confirmation-display template line and the flag-definition paragraph
# opener, are the ones still present. Pinning each site by its own unique
# literal closes that hole.
expect_pin_in_file "SKILL.md pin: display-template line '  design-interview: <true | false>'" \
  "  design-interview: <true | false>" "$SKILL"

expect_pin_in_file "SKILL.md pin: flag paragraph opener '**The \`design-interview:\` flag.**'" \
  '**The `design-interview:` flag.**' "$SKILL"

# Third rendering of the flag's semantics: the §Artifact layout frontmatter
# contract, which is where the key is declared optional. It was edited by this
# wave and the two site pins above do not reach it — deleting this clause left
# the suite green while the contract silently lost "not required to write"
# (Step-6 review FLAG 3b).
expect_pin_in_file "SKILL.md pin: frontmatter-contract clause naming the flag" \
  "Step 0's \`design-interview:\` value beside it" "$SKILL"

# Critic Issue 1 (Step-6 remediation): pin the obligation itself, not just the
# label, so deleting the "not a second way to discharge" sentence — the exact
# span the critic reproduced — goes RED even while the flag paragraph's
# opener and display-template line survive untouched.
expect_pin_in_file "SKILL.md pin: 'not a second way to discharge'" \
  "not a second way to discharge" "$SKILL"

# The attributed literal is the only trace a human made the waiver call — pin
# it directly so a rewrite that drops attribution while keeping the flag
# paragraph's other clauses intact still goes RED.
expect_pin_in_file "SKILL.md pin: attributed literal 'design-interview: false <user> <date>'" \
  "design-interview: false <user> <date>" "$SKILL"

# ============================================================
# SECTION 3: operational-rules.md-only pins
# ============================================================

echo ""
echo "=== Section 3: operational-rules.md-only pins ==="

# Critic Issue 1 (Step-6 remediation): op-rules' own statement that the
# standing Step-0 form does not discharge the waiver obligation on its own —
# the Step-0 flag and the op-rules waiver paragraph are one waiver with two
# renderings, not two discharge paths.
expect_pin_in_file "operational-rules.md pin: 'does not replace it'" \
  "does not replace it" "$RULES"

expect_pin_in_file "operational-rules.md pin: 'standalone design doc'" "standalone design doc" "$RULES"
expect_pin_in_file "operational-rules.md pin: 'C4'" "C4" "$RULES"
expect_pin_in_file "operational-rules.md pin: 'suggested default'" "suggested default" "$RULES"

# ============================================================
# SECTION 4: step renames — "Ideate" retired, "1 Scope" / "2 Design" pinned
# ============================================================

echo ""
echo "=== Section 4: step renames ==="

expect_pin_in_file "SKILL.md pin: steps table row '| 1 Scope |'" "| 1 Scope |" "$SKILL"
expect_pin_in_file "SKILL.md pin: steps table row '2 Design'" "2 Design" "$SKILL"

# README.md renders the full step-name sequence and is the one live agreement
# pair for this concept — the absence checks below guard files that render no
# step names at all. Without this pin a README revert to "ideate → spec" leaves
# the suite green while the two surfaces disagree (Step-6 review FLAG 3).
#
# The separator changed at wave-06 S13 (arrows → a prose list) when the README was
# rewritten; the step NAMES and their order are what this pin was ever about, and
# the needle still fails on the "ideate"/"spec" revert it was written to catch.
expect_pin_in_file "README.md pin: lifecycle line carries 'scope, design'" \
  "scope, design" "$README"

# expect_zero_occurrences_in_file <label> <needle> <file>
# Fixed-string absence check. On failure, names every offending file:line so
# a RED run points straight at the leftover text.
expect_zero_occurrences_in_file() {
  local label="$1" needle="$2" file="$3"
  local hits
  TOTAL=$((TOTAL + 1))
  if [ ! -f "$file" ]; then
    echo "PASS: $label (file absent)"
    PASS=$((PASS + 1))
    return
  fi
  hits="$(grep -nF -- "$needle" "$file" 2>/dev/null || true)"
  if [ -z "$hits" ]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    while IFS= read -r hitline; do
      echo "  ${file}:${hitline}"
    done <<< "$hits"
    FAIL=$((FAIL + 1))
  fi
}

expect_zero_occurrences_in_file "'Ideate' retired from SKILL.md" "Ideate" "$SKILL"
expect_zero_occurrences_in_file "'Ideate' retired from operational-rules.md" "Ideate" "$RULES"

AGENTS_DIR="${REPO}/agents"
if [ -d "$AGENTS_DIR" ]; then
  for f in "$AGENTS_DIR"/*; do
    [ -f "$f" ] || continue
    expect_zero_occurrences_in_file "'Ideate' retired from ${f#$REPO/}" "Ideate" "$f"
  done
else
  TOTAL=$((TOTAL + 1))
  echo "FAIL: agents/ directory not found at $AGENTS_DIR"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# SECTION 5: lifecycle diagram pins
# ============================================================

echo ""
echo "=== Section 5: lifecycle diagram pins — MOVED (epic-17 W4 S8) ==="

# This section used to pin three literals against diagrams/lifecycle.excalidraw:
# the '1\nScope' and '2\nDesign' step labels and the 'Lifecycle (v13)' title.
# That file no longer exists. The diagram is now a composed SVG that is its own
# sole source (spec AC-6 / design D4), and the same three claims are pinned far
# harder in tests/diagrams.test.sh: the step labels against SKILL.md's whole
# ## Steps table rather than two hand-picked rows, and the title's version
# against the hooks' SUPPORTED_SDLC_VERSION rather than a typed literal that
# would need editing on every contract bump.
#
# Nothing is asserted here. Re-adding a diagram pin to THIS suite would give the
# concept two owners — exactly the duplication the diagram suite was written to
# resolve. The pointer stays because a reader who remembers Section 5 needs to
# find where it went.

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
