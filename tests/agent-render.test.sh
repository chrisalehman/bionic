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
#
# THIS SUITE NEVER RUNS THE WRITE PATH AGAINST THE REPO. An earlier draft did, and the
# consequence showed up the first time the arms were mutation-proven: §C reports staleness
# and then §D silently REPAIRS it, so the tree is clean by the time anyone looks and a
# second run is green. A test that repairs what it measures destroys its own evidence. The
# whole write path therefore runs against the same hermetic copy §F mutates — assembled
# here, so §D and §F share one fixture and one copy step.

cp -R "$SRC" "$TMP/agents-src" && cp -R "$OUT" "$TMP/agents"
FIXTURE_RENDER="$TMP/agents-src/render.sh"
FIXTURE_OUT="$TMP/agents"

FP_BEFORE="$(fingerprint "$FIXTURE_OUT")"
RENDER_OUT="$("$FIXTURE_RENDER" 2>&1)"; RENDER_RC=$?
check "$RENDER_RC" "render.sh (write mode) exits clean on a copy of the committed tree" "$RENDER_OUT"
FP_AFTER="$(fingerprint "$FIXTURE_OUT")"
if [ "$FP_BEFORE" = "$FP_AFTER" ]; then
  pass "a re-render leaves every rendered final byte-identical"
else
  fail "a re-render leaves every rendered final byte-identical" "$(diff <(echo "$FP_BEFORE") <(echo "$FP_AFTER"))"
fi

# The repo tree is exactly where it was — the arm above proves the write path is a no-op on
# a matching tree, and this proves the suite itself did not touch the real one.
REPO_FP="$(fingerprint "$OUT")"

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

# Presence of a marker pair says nothing about what is between it. A block emptied of its
# meaning is still present, still non-empty, and — now that there is one source — still
# rendered identically into all six finals; construction propagates a gutted block as
# faithfully as a good one. So each block's load-bearing sentence gets a literal, pinned on
# the SOURCE: one site, and --check carries the bind out to every final.
#
# This is where Section 7's core-sentence pin from agent-roles.test.sh moved to. The
# Step-6 critic that produced that pin had reproduced the failure it guards by inverting
# the sentence in all six files at once; with one source, one pin covers the same ground.
while IFS='|' read -r blockfile label needle; do
  if grep -qF "$needle" "$SRC/blocks/$blockfile.md" 2>/dev/null; then
    pass "$blockfile block states: $label"
  else
    fail "$blockfile block states: $label (missing literal '$needle')"
  fi
done <<'LITERALS'
survival|poll-don't-watch|poll the output file
survival|foreground-first with an explicit generous timeout|600000 ms
survival|the farm-out wall binds the orchestrator, not a dispatched agent|FARM_OUT_ALLOW=1
survival|never end your turn while a command is running|Never end your turn while a command is running
survival|suite output always goes to a file|validate the FILE
report-contract|the proof-or-label rule|carries the command that proves it and that command's output, or the explicit
report-contract|completion is signaled, never inferred|idle is
shared-core|RED before GREEN|never write implementation before a red test
shared-core|completion-by-artifact|that message, not going idle, is what closes the phase
LITERALS

# ============================================================
echo ""
echo "=== F — meta-evidence: --check goes RED in BOTH staleness directions ==="
# ============================================================
#
# Both mutations are planted into the hermetic copy §D assembled; the real agents-src/ and
# agents/ are never touched. render.sh derives its output directory from its own location,
# so the copy runs the production path unaltered.

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

# ============================================================
echo ""
echo "=== G — the checksum manifest is a pipeline OUTPUT, refreshed by every render ==="
# ============================================================
#
# Spec AC-4. payload/integrity/agents.sha256 is what /bionic:doctor compares the user's
# installed role files against, and it is only useful if it is never older than the finals.
# Making it a by-product of the same render that writes those finals is what buys that: one
# command produces both, so "I re-rendered but forgot the manifest" is not a reachable state.
#
# The freshness of the COMMITTED manifest is proven in §C — `--check` covers it — so what
# is proven here is the wiring, on the hermetic copy §F left behind: the write path emits a
# manifest, a source edit propagates into its digests, and a manifest that drifts from the
# finals turns --check red on its own.

REPO_MANIFEST="$REPO/payload/integrity/agents.sha256"
[ -f "$REPO_MANIFEST" ]; check $? "payload/integrity/agents.sha256 exists (the committed manifest)"

# A fresh copy: §F's last mutation deliberately left the fixture broken.
rm -rf "$TMP/m"; mkdir -p "$TMP/m"
cp -R "$SRC" "$TMP/m/agents-src" && cp -R "$OUT" "$TMP/m/agents"
M_RENDER="$TMP/m/agents-src/render.sh"
M_MANIFEST="$TMP/m/payload/integrity/agents.sha256"

"$M_RENDER" >/dev/null 2>&1
[ -f "$M_MANIFEST" ]; check $? "a write-mode render emits the manifest, creating its directory if needed"

if [ -f "$M_MANIFEST" ]; then
  M_ROWS="$(grep -v '^#' "$M_MANIFEST" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')"
  if [ "$M_ROWS" = 6 ]; then
    pass "the rendered manifest carries one row per rendered final (6)"
  else
    fail "the rendered manifest carries one row per rendered final (6)" "found $M_ROWS"
  fi

  # Every digest is the digest of the file the same render just wrote.
  M_BAD=""
  while IFS= read -r row; do
    case "$row" in ''|'#'*) continue ;; esac
    w="$(echo "$row" | awk '{print $1}')"; p="$(echo "$row" | awk '{print $2}')"
    g="$(shasum -a 256 "$TMP/m/$p" 2>/dev/null | awk '{print $1}')"
    [ "$g" = "$w" ] || M_BAD="${M_BAD}${p} "
  done < "$M_MANIFEST"
  if [ -z "$M_BAD" ]; then
    pass "every rendered digest matches the final the same render wrote"
  else
    fail "every rendered digest matches the final the same render wrote" "$M_BAD"
  fi

  # G1 — the manifest FOLLOWS the sources. A block edit changes six finals, so it must
  # change six digests; a manifest written once and never refreshed passes every arm above
  # and still ships stale, which is the whole failure this wiring exists to prevent.
  M_BEFORE="$(cat "$M_MANIFEST")"
  printf '%s\n' "- A rule the manifest has never heard of." >> "$TMP/m/agents-src/blocks/survival.md"
  "$M_RENDER" >/dev/null 2>&1
  M_AFTER="$(cat "$M_MANIFEST")"
  if [ "$M_BEFORE" != "$M_AFTER" ]; then
    pass "meta: a block-source edit propagates into the manifest's digests"
  else
    fail "meta: a block-source edit propagates into the manifest's digests"
  fi

  # G2 — a manifest that drifts from the finals is staleness, and --check is the one command
  # that reports the whole staleness class. Corrupting a digest with the finals untouched is
  # the direction §F cannot reach.
  "$M_RENDER" --check >/dev/null 2>&1
  check $? "meta: the re-rendered fixture is green before the manifest is corrupted"
  # Zeroed digests, comment rows preserved — a substitution that cannot accidentally be a
  # no-op the way "change the first character" is when the digest already starts with it.
  awk '/^#/ || NF == 0 { print; next }
       { printf "%064d  %s\n", 0, $2 }' "$M_MANIFEST" > "$M_MANIFEST.tmp" \
    && mv "$M_MANIFEST.tmp" "$M_MANIFEST"
  if ! "$M_RENDER" --check >/dev/null 2>&1; then
    pass "meta: a corrupted manifest turns --check RED with the finals untouched"
  else
    fail "meta: a corrupted manifest turns --check RED with the finals untouched"
  fi
  "$M_RENDER" >/dev/null 2>&1
  "$M_RENDER" --check >/dev/null 2>&1
  check $? "meta: re-rendering repairs the manifest and returns the fixture to green"
fi

# ============================================================
echo ""
echo "=== H — the suite itself changed nothing under agents/ ==="
# ============================================================
#
# The wall behind §D's rule. Everything above that could write ran against $TMP; if a
# future arm reaches for the real tree "just to re-render", this is what catches it, and
# the reason it matters is that such an arm would repair the staleness §C exists to report.

if [ "$REPO_FP" = "$(fingerprint "$OUT")" ]; then
  pass "agents/ is byte-identical to how this suite found it"
else
  fail "agents/ is byte-identical to how this suite found it" "$(diff <(echo "$REPO_FP") <(fingerprint "$OUT"))"
fi

# ============================================================
echo ""
echo "=== H — the absorbed survival rules live in exactly ONE place ==="
# ============================================================
#
# S3's prune. Foreground-first and poll-don't-watch reached a dispatched agent only through
# `.claude/rules/agent-discipline.md` — a repo-local, pay-per-read channel. They now ship
# inside every role file via blocks/survival.md, so the rules-file copies are duplicates, and
# a duplicate is a drift source: the two texts already disagreed on the watcher's name
# ("a Monitor" vs "a watcher") before this wave.
#
# The arm binds BOTH directions, because a prune has two failure modes. Under-pruning leaves
# the duplicate standing (§H1). OVER-pruning is the quieter one: the foreground-first bullet
# also carried the `claims=` declaration duty, which survival.md does NOT absorb — it is
# addressed to the orchestrator writing a brief, not to the agent reading a role file — so
# deleting that bullet whole would silently drop a live rule (§H2).

RULES="$REPO/.claude/rules/agent-discipline.md"
SURVIVAL="$SRC/blocks/survival.md"

# flat <file>: the file as one whitespace-normalized line. Every span below is prose inside a
# hard-wrapped markdown bullet, so a line-oriented grep pins the WRAP as much as the words —
# rewrapping a paragraph would fail an arm whose rule never changed, and (worse) re-wrapping a
# duplicate would satisfy an absence arm that should still be red. Normalizing first makes
# these pins guard the sentence rather than the line break it happens to sit across.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }

RULES_FLAT="$(flat "$RULES")"
SURVIVAL_FLAT="$(flat "$SURVIVAL")"

[ -f "$RULES" ]; check $? ".claude/rules/agent-discipline.md is present (committed by S4)"

# H1 — absorbed: present in the block source, gone from the rules file.
# Spans, not headings: each literal is a piece of the obligation itself, so a reworded
# heading cannot satisfy the pin and a surviving paragraph cannot hide under a renamed one.
while IFS='|' read -r label absorbed_span rules_span; do
  [ -z "$label" ] && continue
  if printf '%s' "$SURVIVAL_FLAT" | grep -qF "$absorbed_span"; then
    pass "absorbed ($label): the rule is in blocks/survival.md"
  else
    fail "absorbed ($label): the rule is in blocks/survival.md" "missing span: $absorbed_span"
  fi
  if printf '%s' "$RULES_FLAT" | grep -qF "$rules_span"; then
    fail "absorbed ($label): the duplicate is gone from agent-discipline.md" \
         "still present: $rules_span"
  else
    pass "absorbed ($label): the duplicate is gone from agent-discipline.md"
  fi
done <<'ABSORBED'
foreground-first|runs in the FOREGROUND|A command with a known bound under 10 minutes runs FOREGROUND
timeout-ceiling|not a ceiling|2-minute default is a default, not a ceiling
poll-don't-watch|a foreground command that outlives roughly 120 seconds|Poll-don't-watch when the tool auto-backgrounds you
lost-wake|the wake is the thing that gets lost|the wake is what gets lost
ABSORBED

# H2 — NOT absorbed: these must survive the prune. survival.md is addressed to a dispatched
# agent; these three spans are addressed to whoever writes the brief, so they have no home in
# a role file and the rules file is still their only one.
while IFS='|' read -r label span; do
  [ -z "$label" ] && continue
  if printf '%s' "$RULES_FLAT" | grep -qF "$span"; then
    pass "kept ($label): survives the prune in agent-discipline.md"
  else
    fail "kept ($label): survives the prune in agent-discipline.md" "over-pruned, missing: $span"
  fi
  if printf '%s' "$SURVIVAL_FLAT" | grep -qF "$span"; then
    fail "kept ($label): stays OUT of the shipped block" "leaked into survival.md: $span"
  else
    pass "kept ($label): stays OUT of the shipped block"
  fi
done <<'KEPT'
claims-declaration|`claims=` process pattern
roster-verdict|STILL-LIVE instead of UNMET
advisory-only|This channel is advisory only
KEPT

# H3 — the tombstone. A prune that leaves no forwarding address makes the next reader think
# the rule was repealed rather than moved, so the pointer is part of the deliverable.
if printf '%s' "$RULES_FLAT" | grep -qF 'agents-src/blocks/survival.md'; then
  pass "tombstone: agent-discipline.md names the block source as the content's new home"
else
  fail "tombstone: agent-discipline.md names the block source as the content's new home"
fi

# ---------- summary ----------
echo ""
echo "──────────────────────────────────────────────"
echo "agent-render: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
