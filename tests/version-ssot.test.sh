#!/bin/bash
# VERSION SSOT — epic-17 wave-02 slice S4 (spec AC-5, AC-6).
#
# WHAT THE MODEL IS. plugin.json is the single version owner: public semver +
# dependency range constraints in one manifest. The marketplace entry
# deliberately ABSTAINS from carrying its own `version` (verified precedence:
# plugin.json is checked FIRST in the CLI's version-resolution chain, so an
# entry copy would be shadowed redundancy — record/epic-17-w2/
# marketplace-schema-probe.md). SUPPORTED_SDLC_VERSION is a SEPARATE
# artifact-format contract, joined to the plugin's semver major by a one-way
# bridge rule (contract-bump => major-bump), not by being the same number.
#
# THE FOUR ARMS THIS SUITE PROVES:
#   (a) payload/.claude-plugin/plugin.json `version` is well-formed semver.
#   (b) the bionic entry in .claude-plugin/marketplace.json carries NO
#       `version` field (the paired negative to (a); the document-root
#       `version` in marketplace.json is a DIFFERENT concept and is never
#       touched or asserted here).
#   (c) every entry in plugin.json's `dependencies` array carries a `version`
#       field holding a semver range.
#   (d) the bridge pair: hooks/canonical-sdlc-evidence-gate.sh and
#       hooks/canonical-sdlc-governing-skill.sh equality-check the same
#       SUPPORTED_SDLC_VERSION; that value is pinned against plugin.json's
#       major version as the literal pair 13 <-> 0. The pair moves only by a
#       conscious edit to this file, never silently.
#
# HERMETIC. Reads plugin.json, marketplace.json and the two hook files by
# path; no network, no install, no mutation of the repo tree.
#
# Usage: bash tests/version-ssot.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PLUGIN_JSON="${REPO}/payload/.claude-plugin/plugin.json"
MARKETPLACE_JSON="${REPO}/.claude-plugin/marketplace.json"
EVIDENCE_GATE_HOOK="${BIONIC_HOOKS_DIR}/canonical-sdlc-evidence-gate.sh"
GOVERNING_SKILL_HOOK="${BIONIC_HOOKS_DIR}/canonical-sdlc-governing-skill.sh"

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }
expect_true() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi
}

echo "=== Arm (a): plugin.json version is well-formed semver ==="

PLUGIN_VERSION="$(python3 -c "import json; print(json.load(open('$PLUGIN_JSON')).get('version',''))" 2>/dev/null)"
expect_true "(a) plugin.json version matches ^[0-9]+\.[0-9]+\.[0-9]+\$" \
  bash -c "echo '$PLUGIN_VERSION' | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\$'"

echo ""
echo "=== Arm (b): marketplace.json bionic entry carries NO version field ==="

BIONIC_ENTRY_HAS_VERSION="$(python3 -c "
import json
d = json.load(open('$MARKETPLACE_JSON'))
for p in d.get('plugins', []):
    if p.get('name') == 'bionic':
        print('yes' if 'version' in p else 'no')
        break
else:
    print('MISSING-ENTRY')
" 2>/dev/null)"
expect_eq "(b) marketplace.json bionic entry has no version field" "no" "$BIONIC_ENTRY_HAS_VERSION"

echo ""
echo "=== Arm (c): every dependencies entry carries a semver version constraint ==="

DEP_VERSION_REPORT="$(python3 -c "
import json, re
d = json.load(open('$PLUGIN_JSON'))
deps = d.get('dependencies', [])
pattern = re.compile(r'^~?\^?[0-9]')
bad = []
for dep in deps:
    name = dep.get('name', '?')
    v = dep.get('version')
    if not v or not pattern.match(v):
        bad.append(name)
print(','.join(bad))
" 2>/dev/null)"
expect_eq "(c) every dependencies entry carries a version field matching ^~?\\\^?[0-9]" "" "$DEP_VERSION_REPORT"

echo ""
echo "=== Arm (d): bridge pair SUPPORTED_SDLC_VERSION <-> plugin major, pinned 13 <-> 0 ==="

EVIDENCE_GATE_VERSION="$(grep -oE '^SUPPORTED_SDLC_VERSION=[0-9]+' "$EVIDENCE_GATE_HOOK" 2>/dev/null | head -1 | cut -d= -f2)"
GOVERNING_SKILL_VERSION="$(grep -oE '^SUPPORTED_SDLC_VERSION=[0-9]+' "$GOVERNING_SKILL_HOOK" 2>/dev/null | head -1 | cut -d= -f2)"
expect_eq "(d) evidence-gate SUPPORTED_SDLC_VERSION equals governing-skill's" \
  "$GOVERNING_SKILL_VERSION" "$EVIDENCE_GATE_VERSION"
expect_eq "(d) SUPPORTED_SDLC_VERSION is pinned at 13" "13" "$EVIDENCE_GATE_VERSION"

PLUGIN_MAJOR="${PLUGIN_VERSION%%.*}"
expect_eq "(d) plugin.json major version is pinned at 0 (paired with SUPPORTED_SDLC_VERSION 13)" \
  "0" "$PLUGIN_MAJOR"

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
