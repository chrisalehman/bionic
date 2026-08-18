#!/usr/bin/env bash
# tests/agent-render.test.sh — the agent-file RENDER PIPELINE (epic-17 W4 S2, spec AC-2/AC-3).
#
# WHAT THIS REPLACES. Until this wave the six role files under agents/ each carried their
# own hand-maintained copy of the shared duty blocks, and the suite defended them PAIRWISE:
# "senior-implementor's SHARED-CORE must byte-match implementor's", "all six REPORT-CONTRACT
# blocks must byte-match auditor's". That is identity by ENFORCEMENT — N-1 diffs, growing
# quadratically with every new shared block, and green only until someone edits five of six.
#
# D1 (design ledger, Chris 2026-08-18) replaces it with identity by CONSTRUCTION: one file
# per shared block under agents-src/blocks/, six templates under agents-src/templates/, and
# agents-src/render.sh producing the committed finals. Two copies of a block cannot disagree
# because there is only one copy. What CAN go wrong is staleness — a final edited directly,
# or a source edited without re-rendering — and that whole class collapses into ONE arm:
# `render.sh --check`, which re-renders from source and diffs against what is committed.
#
# POWER OF THE ONE ARM (§E). A regenerate-and-diff arm that never goes red proves nothing,
# so §E plants both staleness directions into a hermetic COPY of the tree and requires
# --check to fail on each: (1) a direct edit to a rendered output, (2) an edit to a block
# source with no re-render. The copy is a full agents-src/ + agents/ pair in a temp dir, and
# render.sh resolves its output directory from its own location, so the copy exercises the
# production code path with no seam substituting the value under test.
#
# WHAT STAYS IN agent-roles.test.sh. Frontmatter, disallowedTools, and the SKILL.md↔role-file
# MANDATE/AXIS agreement pins. Those compare a role file against a DIFFERENT surface, so
# construction cannot make them true; only the role-file↔role-file pairwise arms retire here.
#
# Usage: bash tests/agent-render.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
SRC="$REPO/agents-src"
OUT="$REPO/agents"
RENDER="$SRC/render.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  $2"; FAIL=$((FAIL + 1)); }
check() { if [ "$1" = 0 ]; then pass "$2"; else fail "$2" "${3:-}"; fi; }

ROLES="auditor critic implementor researcher senior-implementor test-runner"
BLOCKS="report-contract shared-core survival"

# marker_block <file> <NAME>: the lines between <!-- NAME-BEGIN --> and <!-- NAME-END -->.
marker_block() {
  awk -v b="$2-BEGIN" -v e="$2-END" '
    index($0,b) {f=1; next}
    index($0,e) {f=0}
    f {print}
  ' "$1"
}

# fingerprint <dir>: content digest of every file under <dir>, path-sorted.
fingerprint() {
  find "$1" -type f 2>/dev/null | sort | while IFS= read -r f; do
    printf '%s  %s\n' "$(shasum -a 256 "$f" | awk '{print $1}')" "${f#$1/}"
  done
}

# ============================================================
echo ""
echo "=== A — the pipeline exists, and lives OUTSIDE the payload subtree ==="
# ============================================================

[ -f "$RENDER" ]; check $? "agents-src/render.sh exists"
[ -x "$RENDER" ]; check $? "agents-src/render.sh is executable"

for b in $BLOCKS; do
  [ -s "$SRC/blocks/$b.md" ]; check $? "agents-src/blocks/$b.md exists and is non-empty"
done

for r in $ROLES; do
  [ -s "$SRC/templates/$r.md.tmpl" ]; check $? "agents-src/templates/$r.md.tmpl exists and is non-empty"
done

# Six templates and no more: a seventh template with no rendered final would render into a
# role file nothing tests, and a rendered final with no template is unreachable by --check.
TMPL_COUNT="$(find "$SRC/templates" -name '*.md.tmpl' -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$TMPL_COUNT" = 6 ]; then
  pass "exactly six templates (found $TMPL_COUNT)"
else
  fail "exactly six templates (found $TMPL_COUNT)"
fi
OUT_COUNT="$(find "$OUT" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$OUT_COUNT" = 6 ]; then
  pass "exactly six rendered finals (found $OUT_COUNT)"
else
  fail "exactly six rendered finals (found $OUT_COUNT)"
fi

# The sources are repo-side only. The payload suite owns the shipping proof; this is the
# layout half of the same invariant, stated where the pipeline is defined.
if [ -e "$REPO/payload/agents-src" ]; then
  fail "agents-src/ has no counterpart inside payload/ (found payload/agents-src)"
else
  pass "agents-src/ has no counterpart inside payload/"
fi

# ============================================================
echo ""
echo "=== B — every rendered final announces that it is generated ==="
# ============================================================
#
# The header is the only thing standing between a passer-by and a hand-edit that --check
# will later reject in a commit they do not own.

for r in $ROLES; do
  if grep -qF "GENERATED FILE — DO NOT EDIT" "$OUT/$r.md" 2>/dev/null; then
    pass "agents/$r.md carries the GENERATED header"
  else
    fail "agents/$r.md carries the GENERATED header"
  fi
  if grep -qF "agents-src/templates/$r.md.tmpl" "$OUT/$r.md" 2>/dev/null; then
    pass "agents/$r.md's header names its own template"
  else
    fail "agents/$r.md's header names its own template"
  fi
done

# The header must not displace the frontmatter: Claude Code reads the role's name/model/
# effort from a fence that has to start on line 1.
for r in $ROLES; do
  if [ "$(head -1 "$OUT/$r.md" 2>/dev/null)" = "---" ]; then
    pass "agents/$r.md still opens with the frontmatter fence"
  else
    fail "agents/$r.md still opens with the frontmatter fence (line 1: '$(head -1 "$OUT/$r.md" 2>/dev/null)')"
  fi
done

# ============================================================
echo ""
echo "=== C — the committed finals ARE the render of the committed sources ==="
# ============================================================
#
# The whole staleness class, in one command, against the real tree — no fixture, no seam.

CHECK_OUT="$("$RENDER" --check 2>&1)"; CHECK_RC=$?
check "$CHECK_RC" "render.sh --check is green on the committed tree" "$CHECK_OUT"

# ============================================================
echo ""
echo "=== D — rendering is deterministic: a re-render changes nothing ==="
# ============================================================
#
# --check compares; this proves the WRITE path agrees with it, so `render.sh` after an
# innocent re-run never produces a diff someone has to explain.

FP_BEFORE="$(fingerprint "$OUT")"
RENDER_OUT="$("$RENDER" 2>&1)"; RENDER_RC=$?
check "$RENDER_RC" "render.sh (write mode) exits clean on the committed tree" "$RENDER_OUT"
FP_AFTER="$(fingerprint "$OUT")"
if [ "$FP_BEFORE" = "$FP_AFTER" ]; then
  pass "a re-render leaves every rendered final byte-identical"
else
  fail "a re-render leaves every rendered final byte-identical" "$(diff <(echo "$FP_BEFORE") <(echo "$FP_AFTER"))"
fi

# ============================================================
echo ""
echo "=== E — block presence in the rendered finals (spec AC-3, block half) ==="
# ============================================================
#
# Construction guarantees the six copies AGREE; it does not guarantee they are THERE. A
# template that loses its INJECT directive renders happily and --check stays green, because
# output and source still agree — they agree on a file with the block missing. This is the
# arm that sees that.

for r in $ROLES; do
  if [ -n "$(marker_block "$OUT/$r.md" SURVIVAL)" ]; then
    pass "agents/$r.md: SURVIVAL block present and non-empty"
  else
    fail "agents/$r.md: SURVIVAL block present and non-empty"
  fi
  if [ -n "$(marker_block "$OUT/$r.md" REPORT-CONTRACT)" ]; then
    pass "agents/$r.md: REPORT-CONTRACT block present and non-empty"
  else
    fail "agents/$r.md: REPORT-CONTRACT block present and non-empty"
  fi
done

for r in implementor senior-implementor; do
  if [ -n "$(marker_block "$OUT/$r.md" SHARED-CORE)" ]; then
    pass "agents/$r.md: SHARED-CORE block present and non-empty"
  else
    fail "agents/$r.md: SHARED-CORE block present and non-empty"
  fi
done

# Presence of a marker pair says nothing about what is between it — six blocks emptied of
# meaning in unison are present, non-empty and mutually identical. The survival block exists
# to carry four specific survival rules; each gets a literal, on the block SOURCE (one site,
# and --check propagates the bind to all six finals).
SURVIVAL_SRC="$SRC/blocks/survival.md"
while IFS='|' read -r label needle; do
  if grep -qF "$needle" "$SURVIVAL_SRC" 2>/dev/null; then
    pass "survival block states: $label"
  else
    fail "survival block states: $label (missing literal '$needle')"
  fi
done <<'LITERALS'
poll-don't-watch|poll the output file
foreground-first with an explicit generous timeout|600000 ms
the farm-out wall binds the orchestrator, not a dispatched agent|FARM_OUT_ALLOW=1
never end your turn while a command is running|Never end your turn while a command is running
suite output always goes to a file|validate the FILE
LITERALS

# ============================================================
echo ""
echo "=== F — meta-evidence: --check goes RED in BOTH staleness directions ==="
# ============================================================
#
# Both mutations are planted into a hermetic copy of the tree; the real agents-src/ and
# agents/ are never touched. render.sh derives its output directory from its own location,
# so the copy runs the production path unaltered.

cp -R "$SRC" "$TMP/agents-src" && cp -R "$OUT" "$TMP/agents"
FIXTURE_RENDER="$TMP/agents-src/render.sh"

BASE_OUT="$("$FIXTURE_RENDER" --check 2>&1)"; BASE_RC=$?
check "$BASE_RC" "meta: the untouched fixture copy is green (the mutations below are what turn it red)" "$BASE_OUT"

# F1 — direct edit to a rendered output. The classic "I'll just fix it in the file".
printf '%s\n' "A line nobody rendered." >> "$TMP/agents/implementor.md"
if ! "$FIXTURE_RENDER" --check >/dev/null 2>&1; then
  pass "meta: a direct edit to a rendered final turns --check RED"
else
  fail "meta: a direct edit to a rendered final turns --check RED"
fi
cp "$OUT/implementor.md" "$TMP/agents/implementor.md"
"$FIXTURE_RENDER" --check >/dev/null 2>&1
check $? "meta: restoring the final returns the fixture to green"

# F2 — edit to a block source with no re-render. The staleness the pairwise arms could
# never see: every final still agrees with every other final, and all six are stale.
printf '%s\n' "- A rule the finals have never heard of." >> "$TMP/agents-src/blocks/survival.md"
if ! "$FIXTURE_RENDER" --check >/dev/null 2>&1; then
  pass "meta: a block-source edit with no re-render turns --check RED"
else
  fail "meta: a block-source edit with no re-render turns --check RED"
fi
# ...and re-rendering is what clears it — the repair the header instructs, demonstrated.
"$FIXTURE_RENDER" >/dev/null 2>&1
"$FIXTURE_RENDER" --check >/dev/null 2>&1
check $? "meta: re-rendering after the source edit returns the fixture to green"

# F3 — the render must FAIL LOUDLY on a missing source rather than emitting a role file
# with a hole in it. A silent skip would render a survival-less agent and stay green.
rm -f "$TMP/agents-src/blocks/survival.md"
if ! "$FIXTURE_RENDER" >/dev/null 2>&1; then
  pass "meta: a missing block source makes render.sh exit nonzero"
else
  fail "meta: a missing block source makes render.sh exit nonzero"
fi

# ---------- summary ----------
echo ""
echo "──────────────────────────────────────────────"
echo "agent-render: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
