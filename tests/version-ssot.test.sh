#!/bin/bash
# VERSION SSOT — epic-17 wave-02 slice S4 (spec AC-5, AC-6).
#
# WHAT THE MODEL IS. plugin.json is the single version owner for bionic's own
# public semver. Third-party dependency range constraints do NOT live here as
# of epic-17 W3 S3 (AC-8) — the CLI cannot resolve them against a
# same-marketplace dependency declaration, so they live only in
# payload/scripts/lib/deps.sh's table; see arm (c)'s re-derivation note below.
# The marketplace entry deliberately ABSTAINS from carrying its own `version`
# (verified precedence:
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
#   (c) [RE-DERIVED epic-17 W3 S3, AC-8] no entry in plugin.json's
#       `dependencies` array carries a `version` field. What this arm pinned
#       before: the reverse — every entry carried its OWN semver-range
#       `version`, the W2 model where plugin.json was sole owner of both the
#       public version AND every dependency's constraint (ADR-002 point 2).
#       AC-8 supersedes that: the CLI cannot resolve a same-marketplace,
#       version-constrained dependency (probe-ac6-marketplace-entry.md,
#       reproduced on a fresh scratch config against a confirmed-existing
#       upstream tag), so the constraint now lives ONLY in
#       payload/scripts/lib/deps.sh's table, and plugin.json's dependencies
#       must be constraint-free. The table-to-manifest agreement pin (that the
#       table's rows are correctly rendered, sans constraint) lives in
#       tests/plugin-lib.test.sh, Group 18 — this arm only proves the negative
#       shape, paired with arm (b) above.
#   (d) the bridge pair: hooks/canonical-sdlc-evidence-gate.sh and
#       hooks/canonical-sdlc-governing-skill.sh equality-check the same
#       SUPPORTED_SDLC_VERSION; that value is pinned against plugin.json's
#       major version as the literal pair 14 <-> 1. The pair moves only by a
#       conscious edit to this file, never silently. Moved 13 -> 14 on
#       2026-08-19 (epic-17 W5, close-out contract v14) with the major left at
#       0: the bridge rule reads contract-bump => major-bump, and pre-1.0 is
#       exactly where that rule has nothing to say — every 0.x release is
#       already licensed to break. Major moved 0 -> 1 on 2026-08-21 (the
#       publish package, plugin.json 0.1.0 -> 1.0.0) with the contract held at
#       14: the rule binds from here — the next contract bump is a major bump.
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
echo "=== Arm (c): dependencies carry NO version field (S3: constraint lives only in deps.sh, AC-8) ==="

DEP_VERSION_REPORT="$(python3 -c "
import json
d = json.load(open('$PLUGIN_JSON'))
deps = d.get('dependencies', [])
bad = [dep.get('name','?') for dep in deps if 'version' in dep]
print('%d|%s' % (len(deps), ','.join(bad)))
" 2>/dev/null)"
expect_eq "(c) both dependencies are present and NEITHER carries a version field" \
  "2|" "$DEP_VERSION_REPORT"

echo ""
echo "=== Arm (d): bridge pair SUPPORTED_SDLC_VERSION <-> plugin major, pinned 14 <-> 0 ==="

EVIDENCE_GATE_VERSION="$(grep -oE '^SUPPORTED_SDLC_VERSION=[0-9]+' "$EVIDENCE_GATE_HOOK" 2>/dev/null | head -1 | cut -d= -f2)"
GOVERNING_SKILL_VERSION="$(grep -oE '^SUPPORTED_SDLC_VERSION=[0-9]+' "$GOVERNING_SKILL_HOOK" 2>/dev/null | head -1 | cut -d= -f2)"
expect_eq "(d) evidence-gate SUPPORTED_SDLC_VERSION equals governing-skill's" \
  "$GOVERNING_SKILL_VERSION" "$EVIDENCE_GATE_VERSION"
expect_eq "(d) SUPPORTED_SDLC_VERSION is pinned at 14" "14" "$EVIDENCE_GATE_VERSION"

PLUGIN_MAJOR="${PLUGIN_VERSION%%.*}"
expect_eq "(d) plugin.json major version is pinned at 1 (paired with SUPPORTED_SDLC_VERSION 14)" \
  "1" "$PLUGIN_MAJOR"

# ARM (e) IS GONE (epic-18 T13). It pinned the permission-profile template's two
# version copies to plugin.json's. bionic no longer ships a managed allow-list at
# all, so that rendering surface no longer exists and plugin.json has one fewer
# site to stay agreed with. The remaining sites are the arms above.

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
