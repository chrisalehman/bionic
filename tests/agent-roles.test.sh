#!/usr/bin/env bash
# tests/agent-roles.test.sh — content + mandate-identity gate for agents/*.md role files.
#
# Sections (plan Task 4/1 Step 1):
#   1. six role files exist
#   2. frontmatter: name / model∈set / effort∈set, exact per-file values
#   3. disallowedTools present on researcher/auditor/critic/test-runner, absent on both implementors
#   4. mandate byte-diff: SKILL.md auditor+critic blockquotes == role-file MANDATE marker blocks
#   5. shared-core drift: SHARED-CORE blocks byte-identical across the two implementor files
#   6. meta-evidence: planted one-byte drift makes 4 & 5 go RED (both directions for the mandate)
#
# Meta-evidence never mutates the real files — it plants drift into temp copies.
# Harness idiom mirrors hooks/*.test.sh: PASS/FAIL counters, nonzero exit on any fail.
#
# Usage: bash tests/agent-roles.test.sh

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
AGENTS="$REPO/agents"
SKILL="$REPO/skills/canonical-sdlc/SKILL.md"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  $2"; FAIL=$((FAIL + 1)); }

AUDITOR_ANCHOR='^#### Auditor — the Step-5 exit gate'
CRITIC_ANCHOR='Prompt template:'

# ---------- extraction (symmetric on both sides: strip leading ws, keep '> ') ----------

# skill_blockquote <file> <anchor-regex>: first '> ' blockquote line after the anchor.
skill_blockquote() {
  awk -v a="$2" '$0 ~ a {f=1; next} f && /^[[:space:]]*> / {sub(/^[[:space:]]*/,""); print; exit}' "$1"
}

# marker_block <file> <begin-substr> <end-substr>: lines between the markers, ws-stripped.
marker_block() {
  awk -v b="$2" -v e="$3" '
    index($0,b) {f=1; next}
    index($0,e) {f=0}
    f {sub(/^[[:space:]]*/,""); print}
  ' "$1"
}

# fm_value <file> <key>: value of a frontmatter key (between the first two --- fences).
fm_value() {
  awk -v k="$2" '/^---$/{d++; next} d==1 && $0 ~ "^"k":" {sub("^"k":[[:space:]]*",""); print; exit}' "$1"
}

# ---------- checks (take file args so meta-evidence can point them at temp copies) ----------

# mandate_matches <skillfile> <anchor> <rolefile> <begin> <end>: skill blockquote == role marker block.
mandate_matches() {
  diff <(skill_blockquote "$1" "$2") <(marker_block "$3" "$4" "$5") >/dev/null 2>&1
}

# sharedcore_matches <file1> <file2>: SHARED-CORE blocks byte-identical.
sharedcore_matches() {
  diff <(marker_block "$1" SHARED-CORE-BEGIN SHARED-CORE-END) \
       <(marker_block "$2" SHARED-CORE-BEGIN SHARED-CORE-END) >/dev/null 2>&1
}

# ---------- drift planters (write a mutated copy; never touch the source) ----------

# plant_blockquote_drift <in> <out> <begin> <end>: append a byte to the '> ' line inside a marker block.
plant_blockquote_drift() {
  awk -v b="$3" -v e="$4" '
    index($0,b) {inb=1; print; next}
    index($0,e) {inb=0; print; next}
    inb && /^[[:space:]]*> / {print $0 "X"; next}
    {print}
  ' "$1" > "$2"
}

# plant_skill_drift <in> <out> <anchor>: append a byte to the first '> ' line after the anchor.
plant_skill_drift() {
  awk -v a="$3" '
    f && !done && /^[[:space:]]*> / {print $0 "X"; done=1; next}
    $0 ~ a {f=1}
    {print}
  ' "$1" > "$2"
}

# plant_block_content_drift <in> <out> <begin> <end>: append a byte to the first non-blank line in a block.
plant_block_content_drift() {
  awk -v b="$3" -v e="$4" '
    index($0,b) {inb=1; print; next}
    index($0,e) {inb=0; print; next}
    inb && !done && NF {print $0 "X"; done=1; next}
    {print}
  ' "$1" > "$2"
}

FILES="implementor senior-implementor researcher auditor critic test-runner"

# ===== Section 1: six role files exist =====
echo "== Section 1: files exist =="
for r in $FILES; do
  if [ -f "$AGENTS/$r.md" ]; then pass "agents/$r.md exists"; else fail "agents/$r.md missing"; fi
done

# ===== Section 2: frontmatter name / model / effort =====
echo "== Section 2: frontmatter =="
MODELS_OK="sonnet opus haiku fable inherit"
EFFORT_OK="low medium high xhigh max"
in_set() { case " $1 " in *" $2 "*) return 0;; esac; return 1; }

# expected: file|model|effort
EXPECT="implementor|sonnet|high
senior-implementor|opus|high
researcher|sonnet|medium
auditor|opus|high
critic|opus|high
test-runner|sonnet|low"

while IFS='|' read -r r m e; do
  f="$AGENTS/$r.md"
  [ -f "$f" ] || { fail "$r.md missing (frontmatter skipped)"; continue; }
  name="$(fm_value "$f" name)"
  model="$(fm_value "$f" model)"
  effort="$(fm_value "$f" effort)"
  [ "$name" = "$r" ] && pass "$r: name=$name" || fail "$r: name=$name (want $r)"
  if in_set "$MODELS_OK" "$model"; then pass "$r: model in set ($model)"; else fail "$r: model '$model' not in {$MODELS_OK}"; fi
  if in_set "$EFFORT_OK" "$effort"; then pass "$r: effort in set ($effort)"; else fail "$r: effort '$effort' not in {$EFFORT_OK}"; fi
  [ "$model" = "$m" ] && pass "$r: model=$m" || fail "$r: model=$model (want $m)"
  [ "$effort" = "$e" ] && pass "$r: effort=$e" || fail "$r: effort=$effort (want $e)"
done <<< "$EXPECT"

# ===== Section 3: disallowedTools presence/absence =====
echo "== Section 3: disallowedTools =="
DENY_EXPECT="researcher auditor critic test-runner"
NODENY_EXPECT="implementor senior-implementor"
for r in $DENY_EXPECT; do
  v="$(fm_value "$AGENTS/$r.md" disallowedTools)"
  if echo "$v" | grep -q 'Write' && echo "$v" | grep -q 'Edit' && echo "$v" | grep -q 'NotebookEdit'; then
    pass "$r: disallowedTools present ($v)"
  else
    fail "$r: disallowedTools missing/incomplete ('$v')"
  fi
done
for r in $NODENY_EXPECT; do
  v="$(fm_value "$AGENTS/$r.md" disallowedTools)"
  if [ -z "$v" ]; then pass "$r: no disallowedTools (inherits all)"; else fail "$r: unexpected disallowedTools ('$v')"; fi
done

# test-runner: tee-to-log duty (results always land in a log the orchestrator/user can tail)
if grep -q 'tee' "$AGENTS/test-runner.md" && grep -q 'log path' "$AGENTS/test-runner.md"; then
  pass "test-runner: tee-to-log duty present (names the log path in reports)"
else
  fail "test-runner: tee-to-log duty missing"
fi

# ===== Section 4: mandate byte-diff =====
echo "== Section 4: mandate byte-identity =="
if [ -n "$(skill_blockquote "$SKILL" "$AUDITOR_ANCHOR")" ]; then pass "SKILL auditor blockquote extracted"; else fail "SKILL auditor blockquote empty"; fi
if [ -n "$(skill_blockquote "$SKILL" "$CRITIC_ANCHOR")" ]; then pass "SKILL critic blockquote extracted"; else fail "SKILL critic blockquote empty"; fi
if mandate_matches "$SKILL" "$AUDITOR_ANCHOR" "$AGENTS/auditor.md" MANDATE-BEGIN MANDATE-END; then
  pass "auditor.md mandate == SKILL.md auditor blockquote"
else
  fail "auditor.md mandate drifted from SKILL.md" "$(diff <(skill_blockquote "$SKILL" "$AUDITOR_ANCHOR") <(marker_block "$AGENTS/auditor.md" MANDATE-BEGIN MANDATE-END))"
fi
if mandate_matches "$SKILL" "$CRITIC_ANCHOR" "$AGENTS/critic.md" MANDATE-BEGIN MANDATE-END; then
  pass "critic.md mandate == SKILL.md critic blockquote"
else
  fail "critic.md mandate drifted from SKILL.md" "$(diff <(skill_blockquote "$SKILL" "$CRITIC_ANCHOR") <(marker_block "$AGENTS/critic.md" MANDATE-BEGIN MANDATE-END))"
fi

# ===== Section 5: shared-core drift =====
echo "== Section 5: shared implementor core =="
if [ -n "$(marker_block "$AGENTS/implementor.md" SHARED-CORE-BEGIN SHARED-CORE-END)" ]; then
  pass "implementor.md shared-core block non-empty"
else
  fail "implementor.md shared-core block empty"
fi
if sharedcore_matches "$AGENTS/implementor.md" "$AGENTS/senior-implementor.md"; then
  pass "shared-core byte-identical across both implementor files"
else
  fail "shared-core drifted between implementor files" "$(diff <(marker_block "$AGENTS/implementor.md" SHARED-CORE-BEGIN SHARED-CORE-END) <(marker_block "$AGENTS/senior-implementor.md" SHARED-CORE-BEGIN SHARED-CORE-END))"
fi

# ===== Section 6: meta-evidence (planted drift must go RED, both directions) =====
echo "== Section 6: meta-evidence =="
# 6a. role-side mandate drift (auditor role file copy drifted)
plant_blockquote_drift "$AGENTS/auditor.md" "$TMP/auditor-drift.md" MANDATE-BEGIN MANDATE-END
if ! mandate_matches "$SKILL" "$AUDITOR_ANCHOR" "$TMP/auditor-drift.md" MANDATE-BEGIN MANDATE-END; then
  pass "meta: role-side auditor mandate drift detected"
else
  fail "meta: role-side auditor mandate drift NOT detected"
fi
# 6b. SKILL-side mandate drift (canonical copy moved)
plant_skill_drift "$SKILL" "$TMP/skill-drift.md" "$AUDITOR_ANCHOR"
if ! mandate_matches "$TMP/skill-drift.md" "$AUDITOR_ANCHOR" "$AGENTS/auditor.md" MANDATE-BEGIN MANDATE-END; then
  pass "meta: SKILL-side auditor mandate drift detected"
else
  fail "meta: SKILL-side auditor mandate drift NOT detected"
fi
# 6c. role-side critic mandate drift
plant_blockquote_drift "$AGENTS/critic.md" "$TMP/critic-drift.md" MANDATE-BEGIN MANDATE-END
if ! mandate_matches "$SKILL" "$CRITIC_ANCHOR" "$TMP/critic-drift.md" MANDATE-BEGIN MANDATE-END; then
  pass "meta: role-side critic mandate drift detected"
else
  fail "meta: role-side critic mandate drift NOT detected"
fi
# 6c2. SKILL-side critic mandate drift (canonical copy moved)
plant_skill_drift "$SKILL" "$TMP/skill-drift-critic.md" "$CRITIC_ANCHOR"
if ! mandate_matches "$TMP/skill-drift-critic.md" "$CRITIC_ANCHOR" "$AGENTS/critic.md" MANDATE-BEGIN MANDATE-END; then
  pass "meta: SKILL-side critic mandate drift detected"
else
  fail "meta: SKILL-side critic mandate drift NOT detected"
fi
# 6d. shared-core drift (one block drifted)
plant_block_content_drift "$AGENTS/implementor.md" "$TMP/impl-drift.md" SHARED-CORE-BEGIN SHARED-CORE-END
if ! sharedcore_matches "$TMP/impl-drift.md" "$AGENTS/senior-implementor.md"; then
  pass "meta: shared-core drift detected"
else
  fail "meta: shared-core drift NOT detected"
fi

# ===== Section 7: dispatch convention — background always under multi_agent (W+1-1, C9) =====
echo "== Section 7: dispatch convention background-always =="
if ! grep -qiE "critical-path" "$SKILL" && ! grep -qiE "synchronously" "$SKILL"; then
  pass "SKILL.md: old 'critical-path work synchronously' phrasing removed"
else
  fail "SKILL.md: old 'critical-path work synchronously' phrasing still present"
fi
if grep -q "background subagents" "$SKILL" && grep -q "completion notification" "$SKILL"; then
  pass "SKILL.md: new background-dispatch/completion-notification rule present"
else
  fail "SKILL.md: new background-dispatch/completion-notification rule missing"
fi

# ---------- summary ----------
echo "──────────────────────────────────────────────"
echo "agent-roles: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
