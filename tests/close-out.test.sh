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

# ===== Section 6: the v14 evidence-key contract, gate <-> doctrine =====
#
# Ownership-table row (epic-17 W5 spec, ## Design):
#   close-out evidence keys (v14) | canonical-sdlc-evidence-gate.sh (SSoT)
#   | SKILL.md Step-9 prose + evidence-shapes row | this arm
#
# The gate is the owner: `validate_ship_step` is where the four keys are
# demanded, and everything else is a rendering of it. This arm reads the key
# set OUT of the hook — never a typed literal — so a contract change that
# moves the hook and forgets the doctrine goes red here instead of leaving
# two Step-9 contracts in the corpus, one of which nobody enforces.
#
# Extraction is deliberately narrow: `shape_block delivered` and the trio's
# `for f in ...` loop are the two lines that ARE the demand. A key named only
# in a comment or a fix hint is prose, and prose is what this suite exists to
# distrust.
echo "== Section 6: v14 close-out keys — gate is the owner, doctrine renders it =="
GATE="${BIONIC_HOOKS_DIR}/canonical-sdlc-evidence-gate.sh"

# gate_keys <file>: the four demanded keys, one per line, sorted.
gate_keys() {
  {
    sed -n '/^validate_ship_step()/,/^}/p' "$1" \
      | sed -n 's/^[[:space:]]*shape_block[[:space:]]*//p' | tr ' ' '\n'
    sed -n '/^validate_ship_step()/,/^}/p' "$1" \
      | sed -n 's/^[[:space:]]*for f in \(.*\); do$/\1/p' | tr ' ' '\n'
  } | grep -E '^[a-z-]+$' | sort -u
}

GATE_KEYS="$(gate_keys "$GATE")"
EXPECTED_KEYS="$(printf 'delivered\ndeployed\nmonitored\nverified\n')"
if [ "$GATE_KEYS" = "$EXPECTED_KEYS" ]; then
  pass "evidence gate demands exactly the four v14 close-out keys"
else
  fail "evidence gate's Step-9 key set is not the v14 four" \
    "$(diff <(echo "$EXPECTED_KEYS") <(echo "$GATE_KEYS"))"
fi

# Every key the gate demands is rendered in SKILL.md's Step-9 surfaces. The
# search is scoped to the ## Evidence shapes table row plus the Step-9 section,
# so a key that appears only in some unrelated paragraph does not count.
skill_step9_surface() {
  awk '/^### Step 9 — Close-out/ {f=1} /^## Evidence shapes/ {f=1} f' "$SKILL"
}
S9="$(skill_step9_surface)"
for k in $GATE_KEYS; do
  if echo "$S9" | grep -qF -- "\`${k}:\`"; then
    pass "SKILL.md Step-9 surface renders the gate's '${k}:' key"
  else
    fail "SKILL.md Step-9 surface never names the gate's '${k}:' key"
  fi
done

# The retired v13 keys are gone from the shipped contract text. A doctrine that
# still tells a reader to write `verified-at:` is worse than silence: the gate
# would refuse the commit and the text would be the reason they wrote it.
for dead in 'deploy:' 'verified-at:' 'monitor:'; do
  if echo "$S9" | grep -qF -- "\`${dead}\`"; then
    fail "SKILL.md Step-9 surface still teaches the retired v13 key '${dead}'"
  else
    pass "retired v13 key '${dead}' is gone from SKILL.md's Step-9 surface"
  fi
done

# meta: the extractor discriminates. A doctored hook that drops `delivered`
# from the demand must change the key set this arm reads.
sed 's/^  shape_block delivered$/  : delivered/' "$GATE" > "$TMP/gate-nodelivered.sh"
if [ "$(gate_keys "$TMP/gate-nodelivered.sh")" != "$EXPECTED_KEYS" ]; then
  pass "meta: a gate that stops demanding 'delivered' is detected"
else
  fail "meta: dropping the 'delivered' demand did not move the extracted key set"
fi

# ===== Section 7: deploy_target is n/a by default and never inferred =====
#
# AC-3. The trio above is opt-in only because this is true, so the two arms
# belong in one suite: a Step-0 that quietly infers a live surface from
# "deploy signals" would put every ordinary run back on the hook for a
# release it never performed.
echo "== Section 7: deploy_target defaults n/a, never inferred (AC-3) =="

STEP0="$(awk '/^### Step 0 — Configure/ {f=1} /^### Step 1/ {f=0} f' "$SKILL")"
if [ -n "$STEP0" ]; then
  pass "SKILL.md Step 0 section extracted"
else
  fail "SKILL.md Step 0 section not found — the anchors moved"
fi

if echo "$STEP0" | grep -qi 'never inferred'; then
  pass "Step 0 says deploy_target is never inferred"
else
  fail "Step 0 does not say deploy_target is never inferred"
fi

if echo "$STEP0" | grep -qF 'from deploy signals`'; then
  fail "Step 0 still infers deploy_target 'from deploy signals'"
else
  pass "the retired 'from deploy signals' inference is gone from Step 0"
fi

# The confirmation display is the surface the user approves from, so it carries
# the rule too — an `[inferred: ...]` annotation on that line would tell the
# user the agent derived a value it is forbidden to derive.
DISPLAY_LINE="$(echo "$STEP0" | grep -E '^[[:space:]]*deploy_target:' | head -1)"
if [ -n "$DISPLAY_LINE" ]; then
  pass "Step-0 confirmation display carries a deploy_target line"
else
  fail "Step-0 confirmation display has no deploy_target line"
fi
if echo "$DISPLAY_LINE" | grep -q '\[inferred:'; then
  fail "the confirmation display still annotates deploy_target as '[inferred: ...]'"
else
  pass "the confirmation display no longer annotates deploy_target as inferred"
fi

# The gate's own predicate agrees on what "not named" means: absent, none, n/a.
if grep -qE '^[[:space:]]*""\|none\|n/a\|n/a:\*\)[[:space:]]*return 1' "$GATE"; then
  pass "the gate reads absent/none/n-a as 'no live surface named'"
else
  fail "the gate's deploy_target_named predicate does not read absent/none/n-a as unnamed"
fi

# ===== Section 8: the T4 user-confirmed discharge — gate <-> doctrine =====
#
# Ownership-table row (epic-17 W5 spec, ## Design; declared by 4/3's A22 and
# left unbuilt — W5 audit F-4):
#   T4 user-confirmed discharge | canonical-sdlc-evidence-gate.sh (SSoT)
#   | SKILL.md #### Waiver Protocol | this arm
#
# WHAT CHANGED AND WHY IT NEEDS A PIN. 4/3 moved an AUTHORITY contract: what
# discharges a matrix row. Before it, a legitimately user-confirmed T4 row had
# exactly one way past the CONFIRMED wall — the Waiver Protocol, which recorded
# a waiver where nothing had been waived, so the row read forever as a criterion
# that was let go. After it, a T4 block carrying a well-formed
# `user-confirmed: <user> <date> <what>` discharges on that value alone.
#
# That contract now lives in two places: the branch in the hook that lets the
# row through, and the paragraph in SKILL.md that tells an agent how to write
# one. Neither is derivable from the other, and a drift between them is
# expensive in a specific way — an agent reading stale doctrine either reaches
# for a waiver it does not need (re-creating the exact defect 4/3 fixed) or
# writes a shape the gate refuses. Section 6 pins the Step-9 evidence keys this
# same way, off this same hook; this row is its sibling and belongs beside it.
#
# EXTRACTION, not transcription. Key and tier are read OUT of the hook's own
# source — the grep pattern that recognises the key, and the branch condition
# that gates the discharge. A typed literal here would pin this suite to the
# contract as it stood the day it was written, which is the failure this row
# exists to prevent.
echo "== Section 8: T4 user-confirmed discharge — gate is the owner, doctrine renders it =="

# uc_key <gate>: the evidence key the gate recognises, read off the pattern in
# user_confirmed_value() rather than typed.
uc_key() {
  sed -n '/^user_confirmed_value()/,/^}/p' "$1" \
    | sed -nE "s/.*grep -E .\^\[\[:space:\]\]\*([a-z][a-z-]*)\[\[:space:\]\]\*:.*/\1/p" \
    | head -1
}

# uc_tier <gate>: the tier the discharge branch is conditioned on, read off the
# branch itself — the one line that IS the authority change.
uc_tier() {
  grep -E 'user_confirmed_form_ok "\$block_txt"' "$1" \
    | sed -nE 's/.*"\$tier" = "(T[0-9])".*/\1/p' | head -1
}

# uc_form_needs_date <gate>: does the form check demand a YYYY-MM-DD?
uc_form_needs_date() {
  sed -n '/^user_confirmed_form_ok()/,/^}/p' "$1" \
    | grep -q '\[0-9\]{4}-\[0-9\]{2}-\[0-9\]{2}'
}

# uc_form_needs_user <gate>: does a leading name token precede that date?
uc_form_needs_user() {
  sed -n '/^user_confirmed_form_ok()/,/^}/p' "$1" \
    | grep -q '\^\[A-Za-z\]\[A-Za-z0-9._-\]\*\[\[:space:\]\]+\[0-9\]{4}'
}

# waiver_protocol <skill>: the #### Waiver Protocol section body. Bounded to that
# section on purpose — "no waiver" said anywhere else in a 900-line SKILL.md is
# not this contract being stated.
waiver_protocol() {
  awk '/^#### Waiver Protocol/{f=1; next} f && /^#+ /{exit} f' "$1"
}

# uc_contract_agrees <gate> <skill>: 0 when every fact the gate enforces about the
# T4 discharge is stated in the Waiver Protocol section. Written as one predicate
# so the meta battery below can re-run the WHOLE agreement against doctored
# copies of either side.
uc_contract_agrees() {
  local g="$1" sk="$2" key tier doc
  key="$(uc_key "$g")"
  tier="$(uc_tier "$g")"
  if [ -z "$key" ] || [ -z "$tier" ]; then
    echo "gate: could not read the discharge contract (key='${key}' tier='${tier}')" >&2; return 1
  fi
  doc="$(waiver_protocol "$sk")"
  if [ -z "$doc" ]; then echo "doctrine: #### Waiver Protocol section not found" >&2; return 1; fi

  # the key, rendered in the gate's own attributed order
  if ! grep -qF -- "\`${key}: <user> <date>" <<< "$doc"; then
    echo "doctrine never renders '${key}: <user> <date> ...'" >&2; return 1
  fi
  # the tier the branch is gated on
  if ! grep -qw -- "$tier" <<< "$doc"; then
    echo "doctrine never names tier ${tier}" >&2; return 1
  fi
  # the two shape demands, each asserted only because the gate makes it
  if uc_form_needs_date "$g" && ! grep -qF -- '<date>' <<< "$doc"; then
    echo "gate demands a YYYY-MM-DD; doctrine's placeholder carries no <date>" >&2; return 1
  fi
  if uc_form_needs_user "$g" && ! grep -qF -- '<user>' <<< "$doc"; then
    echo "gate demands a leading name token; doctrine's placeholder carries no <user>" >&2; return 1
  fi
  # what the branch DOES: past the wall without a waiver and without a verdict
  if ! grep -qF -- 'no waiver' <<< "$doc"; then
    echo "doctrine does not state that the T4 discharge needs no waiver" >&2; return 1
  fi
  if ! grep -qF -- 'no auditor verdict' <<< "$doc"; then
    echo "doctrine does not state that the T4 discharge needs no auditor verdict" >&2; return 1
  fi
  return 0
}

UC_KEY="$(uc_key "$GATE")"
UC_TIER="$(uc_tier "$GATE")"

if [ -n "$UC_KEY" ] && [ -n "$UC_TIER" ]; then
  pass "gate's discharge contract is readable: key '${UC_KEY}:' on tier ${UC_TIER}"
else
  fail "gate's discharge contract is not readable" "key='${UC_KEY}' tier='${UC_TIER}'"
fi

if uc_contract_agrees "$GATE" "$SKILL" 2>/dev/null; then
  pass "SKILL.md's Waiver Protocol states the same T4 discharge contract the gate enforces"
else
  fail "SKILL.md's Waiver Protocol and the evidence gate disagree on the T4 discharge" \
    "$(uc_contract_agrees "$GATE" "$SKILL" 2>&1)"
fi

# The negative half. 4/3's fix is only worth anything if the doctrine stops
# telling readers to waive a T4 row; a Waiver Protocol that lists the discharge
# AND still counts it among the user-only waiver moves is two contracts.
WP="$(waiver_protocol "$SKILL")"
if grep -qF -- 'needs no waiver' <<< "$WP"; then
  pass "Waiver Protocol says a user-confirmed T4 row needs no waiver"
else
  fail "Waiver Protocol never says a user-confirmed T4 row needs no waiver"
fi
if grep -qF -- 'unattributed' <<< "$WP"; then
  pass "…and that an unattributed or agent-written claim is not one (the form check's whole point)"
else
  fail "Waiver Protocol does not distinguish an unattributed/agent-written claim"
fi

# ----- meta: the agreement discriminates, proven on doctored copies -----
# Same discipline as Section 4: the sources are never touched, and each doctored
# copy moves ONE side of the contract.

# 8-meta-a. gate-side key rename — the hook starts reading a different key.
sed 's/user-confirmed\[\[:space:\]\]\*:/user-verified[[:space:]]*:/' "$GATE" > "$TMP/gate-key-renamed.sh"
if [ "$(uc_key "$TMP/gate-key-renamed.sh")" != "$UC_KEY" ] \
   && ! uc_contract_agrees "$TMP/gate-key-renamed.sh" "$SKILL" 2>/dev/null; then
  pass "meta: a gate-side rename of the evidence key is detected"
else
  fail "meta: renaming the gate's evidence key did not break the agreement"
fi

# 8-meta-b. gate-side tier move — the discharge is re-aimed at another tier.
sed 's/elif \[ "$tier" = "T4" \] \&\& user_confirmed_form_ok/elif [ "$tier" = "T3" ] \&\& user_confirmed_form_ok/' \
  "$GATE" > "$TMP/gate-tier-moved.sh"
if [ "$(uc_tier "$TMP/gate-tier-moved.sh")" = "T3" ]; then
  pass "meta: the tier extractor follows the branch when it moves (T4 -> T3)"
else
  fail "meta: the tier extractor did not follow a moved discharge branch" \
    "read '$(uc_tier "$TMP/gate-tier-moved.sh")'"
fi

# 8-meta-c. gate-side relaxation — the form check stops demanding a date, and the
# doctrine that still promises one is now over-specified relative to the gate.
# The arm here is the extractor's own discrimination: a relaxed gate must read
# as relaxed, or the conditional assertions above are vacuous.
sed 's/\[0-9\]{4}-\[0-9\]{2}-\[0-9\]{2}/[0-9]+/' "$GATE" > "$TMP/gate-nodate.sh"
if ! uc_form_needs_date "$TMP/gate-nodate.sh"; then
  pass "meta: a gate that stops demanding YYYY-MM-DD reads as relaxed"
else
  fail "meta: the date demand is not actually read out of the gate"
fi

# 8-meta-d. doctrine-side drift — the Waiver Protocol loses the discharge
# paragraph and goes back to teaching the waiver. This is the regression that
# actually costs: an agent reads it, waives a row nothing waived, and the matrix
# records a criterion as let go.
grep -vF -- 'needs no waiver' "$SKILL" > "$TMP/skill-uc-dropped.md"
if ! uc_contract_agrees "$GATE" "$TMP/skill-uc-dropped.md" 2>/dev/null; then
  pass "meta: doctrine losing the waiver-free discharge is detected"
else
  fail "meta: doctrine losing the waiver-free discharge was NOT detected"
fi

# 8-meta-e. doctrine-side shape drift — the placeholder drops the date, so an
# agent writing what the doctrine shows would be refused by the gate.
sed 's/`user-confirmed: <user> <date> <what they confirmed>`/`user-confirmed: <user> <what they confirmed>`/g' \
  "$SKILL" > "$TMP/skill-uc-nodate.md"
if ! uc_contract_agrees "$GATE" "$TMP/skill-uc-nodate.md" 2>/dev/null; then
  pass "meta: doctrine dropping <date> from the rendered form is detected"
else
  fail "meta: doctrine dropping <date> from the rendered form was NOT detected"
fi

# and the sources are untouched by all of the above
if uc_contract_agrees "$GATE" "$SKILL" 2>/dev/null; then
  pass "meta: gate and SKILL.md still agree after the mutation battery (temp copies only)"
else
  fail "meta: a mutation helper touched a source file"
fi

# ---------- summary ----------
echo "──────────────────────────────────────────────"
echo "close-out: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
