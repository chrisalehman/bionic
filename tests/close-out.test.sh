#!/usr/bin/env bash
# tests/close-out.test.sh — the v14 close-out evidence-key contract, read out of
# the evidence gate itself.
#
# The gate is the owner: `validate_ship_step` is where the keys are demanded,
# and everything else is a rendering of it. What survives here reads the demand
# OUT of the hook — never a typed doctrine literal — plus the mutation proof
# that the extractor discriminates, and the gate's own predicate for "no live
# surface named".
#
# (epic-18 W1: the TERMDISP byte-identity batteries, the third-copy literal
# count, and the gate<->doctrine text agreements were deleted — their subject
# was rendered sentences in SKILL.md / operational-rules.md, so their only
# failure mode was "the words changed". The T4 user-confirmed discharge is
# proved behaviourally in tests/canonical-sdlc-evidence-gate.test.sh Section 30.)
#
# Usage: bash tests/close-out.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  $2"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ===== Section 6: v14 close-out keys — the gate is the owner =====
#
# Extraction is deliberately narrow: `shape_block delivered` and the trio's
# `for f in ...` loop are the two lines that ARE the demand. A key named only
# in a comment or a fix hint is prose, and prose is what this suite distrusts.
echo "== Section 6: v14 close-out keys demanded by the evidence gate =="
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

# meta: the extractor discriminates. A doctored hook that drops `delivered`
# from the demand must change the key set this arm reads.
sed 's/^  shape_block delivered$/  : delivered/' "$GATE" > "$TMP/gate-nodelivered.sh"
if [ "$(gate_keys "$TMP/gate-nodelivered.sh")" != "$EXPECTED_KEYS" ]; then
  pass "meta: a gate that stops demanding 'delivered' is detected"
else
  fail "meta: dropping the 'delivered' demand did not move the extracted key set"
fi

# ===== Section 7: deploy_target — what the gate reads as "unnamed" (AC-3) =====
echo "== Section 7: the gate's deploy_target predicate =="
if grep -qE '^[[:space:]]*""\|none\|n/a\|n/a:\*\)[[:space:]]*return 1' "$GATE"; then
  pass "the gate reads absent/none/n-a as 'no live surface named'"
else
  fail "the gate's deploy_target_named predicate does not read absent/none/n-a as unnamed"
fi

# ---------- summary ----------
echo "──────────────────────────────────────────────"
echo "close-out: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
