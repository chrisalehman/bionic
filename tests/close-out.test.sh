#!/usr/bin/env bash
# tests/close-out.test.sh — agreement pin for the terminal-disposition rule
# (epic-17 wave-04 slice S7, spec AC-5 / epic AC-11).
#
# Ownership-table row this pin serves:
#   terminal-disposition rule | SKILL.md Step-9 section | operational-rules.md
#   close-out section | normative-literal pin across both
#
# Mechanism mirrors the SHARED-CORE precedent in tests/agent-roles.test.sh: both
# surfaces carry the SAME <!-- TERMDISP-BEGIN/END --> marker pair around a
# byte-identical blockquote, diffed rather than eyeballed. A second battery
# count-scopes a distinctive substring of that literal across every tracked
# file under skills/ and agents/ so a third, unpinned copy (pasted into a role
# file, say) trips the suite instead of drifting silently.
#
# Usage: bash tests/close-out.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
SKILL="${BIONIC_SKILLS_DIR}/canonical-sdlc/SKILL.md"
RULES="${BIONIC_SKILLS_DIR}/canonical-sdlc/operational-rules.md"

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  $2"; FAIL=$((FAIL + 1)); }

# marker_block <file> <begin-substr> <end-substr>: lines between the markers,
# leading-whitespace-stripped (identical helper to agent-roles.test.sh's).
marker_block() {
  awk -v b="$2" -v e="$3" '
    index($0,b) {f=1; next}
    index($0,e) {f=0}
    f {sub(/^[[:space:]]*/,""); print}
  ' "$1"
}

# termdisp_matches <skillfile> <rulesfile>: TERMDISP blocks byte-identical.
termdisp_matches() {
  diff <(marker_block "$1" TERMDISP-BEGIN TERMDISP-END) \
       <(marker_block "$2" TERMDISP-BEGIN TERMDISP-END) >/dev/null 2>&1
}

# plant_block_content_drift <in> <out> <begin> <end>: append a byte to the
# first non-blank line inside a marker block (identical helper to
# agent-roles.test.sh's — never touches the source, writes a temp copy).
plant_block_content_drift() {
  awk -v b="$3" -v e="$4" '
    index($0,b) {inb=1; print; next}
    index($0,e) {inb=0; print; next}
    inb && !done && NF {print $0 "X"; done=1; next}
    {print}
  ' "$1" > "$2"
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ===== Section 1: presence =====
echo "== Section 1: TERMDISP block present on both surfaces =="
if [ -n "$(marker_block "$SKILL" TERMDISP-BEGIN TERMDISP-END)" ]; then
  pass "SKILL.md TERMDISP block non-empty"
else
  fail "SKILL.md TERMDISP block missing/empty"
fi
if [ -n "$(marker_block "$RULES" TERMDISP-BEGIN TERMDISP-END)" ]; then
  pass "operational-rules.md TERMDISP block non-empty"
else
  fail "operational-rules.md TERMDISP block missing/empty"
fi

# ===== Section 2: the vacuous-match hazard, demonstrated hermetically =====
# Two surfaces with NO marker block at all must not let the byte-identity half
# "pass" — `diff` on two EMPTY extractions reports identical (exit 0), so a
# rewrite that dropped Section 1's presence gate and kept only
# termdisp_matches would let "both surfaces deleted" slip through green.
# Absence is SYNTHESIZED here (marker-stripped copies), not read from git
# history: an earlier version anchored this on `git show HEAD:` being
# pre-slice, which is true exactly once — the arm went permanently red the
# moment the slice merged (RED evidence is perishable; mutation proof, in
# Section 3, is the durable discriminator).
echo "== Section 2: vacuous-match hazard on two absent blocks (synthesized) =="
BARE_SKILL="$TMP/bare-SKILL.md"
BARE_RULES="$TMP/bare-operational-rules.md"
if sed '/TERMDISP-BEGIN/,/TERMDISP-END/d' "$SKILL" > "$BARE_SKILL" \
   && sed '/TERMDISP-BEGIN/,/TERMDISP-END/d' "$RULES" > "$BARE_RULES"; then
  if [ -z "$(marker_block "$BARE_SKILL" TERMDISP-BEGIN TERMDISP-END)" ] \
     && [ -z "$(marker_block "$BARE_RULES" TERMDISP-BEGIN TERMDISP-END)" ]; then
    pass "meta: stripped copies carry no TERMDISP block on either surface (absence synthesized)"
  else
    fail "meta: marker strip failed — synthesized-absence precondition invalid"
  fi
  if termdisp_matches "$BARE_SKILL" "$BARE_RULES"; then
    pass "meta: confirms the vacuous-match hazard on two absent blocks — presence (Section 1) is what actually reds out, not byte-identity"
  else
    fail "meta: unexpected — two empty marker_block extractions diffed as non-identical"
  fi
else
  fail "meta: could not read HEAD copies of SKILL.md / operational-rules.md" "$(git -C "$REPO" show HEAD:skills/canonical-sdlc/SKILL.md 2>&1 | head -5)"
fi

# ===== Section 3: GREEN — byte-identity on the current tree =====
echo "== Section 3: byte-identity on the current tree =="
if termdisp_matches "$SKILL" "$RULES"; then
  pass "TERMDISP block byte-identical: SKILL.md Step 9 == operational-rules.md close-out"
else
  fail "TERMDISP block drifted between SKILL.md and operational-rules.md" \
    "$(diff <(marker_block "$SKILL" TERMDISP-BEGIN TERMDISP-END) <(marker_block "$RULES" TERMDISP-BEGIN TERMDISP-END))"
fi

# ===== Section 4: mutation-proof (planted drift must go RED, both directions) =====
echo "== Section 4: mutation-proof =="
plant_block_content_drift "$RULES" "$TMP/rules-drift.md" TERMDISP-BEGIN TERMDISP-END
if ! termdisp_matches "$SKILL" "$TMP/rules-drift.md"; then
  pass "meta: operational-rules.md-side literal drift detected"
else
  fail "meta: operational-rules.md-side literal drift NOT detected"
fi

plant_block_content_drift "$SKILL" "$TMP/skill-drift.md" TERMDISP-BEGIN TERMDISP-END
if ! termdisp_matches "$TMP/skill-drift.md" "$RULES"; then
  pass "meta: SKILL.md-side literal drift detected"
else
  fail "meta: SKILL.md-side literal drift NOT detected"
fi

# The two checks above prove the discriminator on TEMP COPIES only; confirm the
# real files on disk were never touched (restore-proof, not just "we didn't
# call Write on them").
if termdisp_matches "$SKILL" "$RULES"; then
  pass "meta: real files still agree after mutation-proof (temp copies only were perturbed)"
else
  fail "meta: real files disagree after mutation-proof — a temp-copy helper touched the source"
fi

# ===== Section 5: count-scoped third-copy guard =====
echo "== Section 5: no third, unpinned copy under skills/ or agents/ =="
# Distinctive substring of the normative literal — specific enough that an
# accidental paste elsewhere in a rendering surface is exactly what this
# battery exists to catch, rather than any incidental reuse of a common word.
LITERAL='Abolish "continuation candidate."'
cd "$REPO"
FILES="$(git ls-files 'skills/*' 'agents/*')"
COUNT=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  n="$(grep -cF -- "$LITERAL" "$f" 2>/dev/null || true)"
  COUNT=$((COUNT + ${n:-0}))
done <<< "$FILES"
if [ "$COUNT" -eq 2 ]; then
  pass "terminal-disposition literal appears exactly 2x under skills/+agents/ (the two designated homes)"
else
  fail "terminal-disposition literal appears ${COUNT}x under skills/+agents/ (want exactly 2 — a stray copy or a missing one)"
fi

# meta: planting a third copy (a temp file OUTSIDE the tracked tree cannot be
# used here — git ls-files only sees tracked paths, so the guard is proven by
# reasoning over the count itself: 0 would mean both homes lost the literal,
# 1 would mean one home lost it, >2 would mean a stray copy landed in a
# tracked skills/ or agents/ file. Each of those is a distinct, non-2 count,
# so the single equality check above discriminates all three failure shapes.

# ---------- summary ----------
echo "──────────────────────────────────────────────"
echo "close-out: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
