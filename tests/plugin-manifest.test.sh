#!/bin/bash
# Tests for the bionic plugin manifest, marketplace manifest, and LICENSE.
# Epic-17 wave-01 slice S1. Asserts:
#   - payload/.claude-plugin/plugin.json exists, is valid JSON, name=bionic, semver
#     version, license MIT, non-empty dependencies array
#   - .claude-plugin/marketplace.json exists, is valid JSON, carries a bionic
#     plugin entry sourcing the payload subtree; every plugin.json dependency
#     is declared under bionic's own marketplace (same-marketplace, epic-17
#     W3 S3 AC-7/AC-8) and no allowCrossMarketplaceDependenciesOn field
#     survives now that nothing crosses marketplaces
#   - LICENSE exists at repo root and contains "MIT License"
#
# S6 amendment (payload boundary): the plugin manifest moved from the repo root to
# payload/, and the marketplace entry's source moved with it. The repo root stays the
# MARKETPLACE root (it holds .claude-plugin/marketplace.json); the payload subtree is the
# PLUGIN root. Rationale and the measurements behind it: tests/plugin-payload.test.sh.
#
# Usage: bash tests/plugin-manifest.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PLUGIN_JSON="${REPO}/payload/.claude-plugin/plugin.json"
MARKETPLACE_JSON="${REPO}/.claude-plugin/marketplace.json"
LICENSE_FILE="${REPO}/LICENSE"

PASS=0
FAIL=0
TOTAL=0

# ---------- helpers ----------

expect_true() {
  local label="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    FAIL=$((FAIL + 1))
  fi
}

expect_eq() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (expected='$expected' actual='$actual')"
    FAIL=$((FAIL + 1))
  fi
}

expect_contains() {
  local label="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF "$needle"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (expected to contain '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================
# SECTION 1: payload/.claude-plugin/plugin.json
# ============================================================

echo ""
echo "=== Section 1: payload/.claude-plugin/plugin.json ==="

expect_true "plugin.json exists" test -f "$PLUGIN_JSON"

if [ -f "$PLUGIN_JSON" ]; then
  expect_true "plugin.json is valid JSON" python3 -c "import json; json.load(open('$PLUGIN_JSON'))"

  PLUGIN_NAME="$(python3 -c "import json; print(json.load(open('$PLUGIN_JSON')).get('name',''))" 2>/dev/null)"
  expect_eq "plugin.json name is bionic" "bionic" "$PLUGIN_NAME"

  PLUGIN_VERSION="$(python3 -c "import json; print(json.load(open('$PLUGIN_JSON')).get('version',''))" 2>/dev/null)"
  expect_true "plugin.json version is semver" bash -c "echo '$PLUGIN_VERSION' | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'"

  PLUGIN_LICENSE="$(python3 -c "import json; print(json.load(open('$PLUGIN_JSON')).get('license',''))" 2>/dev/null)"
  expect_eq "plugin.json license is MIT" "MIT" "$PLUGIN_LICENSE"

  DEPS_COUNT="$(python3 -c "import json; print(len(json.load(open('$PLUGIN_JSON')).get('dependencies', [])))" 2>/dev/null)"
  expect_true "plugin.json dependencies array is non-empty" bash -c "[ '${DEPS_COUNT:-0}' -gt 0 ]"
else
  echo "SKIP: remaining Section 1 checks (plugin.json missing)"
fi

# ============================================================
# SECTION 2: .claude-plugin/marketplace.json
# ============================================================

echo ""
echo "=== Section 2: .claude-plugin/marketplace.json ==="

expect_true "marketplace.json exists" test -f "$MARKETPLACE_JSON"

if [ -f "$MARKETPLACE_JSON" ]; then
  expect_true "marketplace.json is valid JSON" python3 -c "import json; json.load(open('$MARKETPLACE_JSON'))"

  HAS_BIONIC_ENTRY="$(python3 -c "
import json
d = json.load(open('$MARKETPLACE_JSON'))
plugins = d.get('plugins', [])
found = False
for p in plugins:
    if p.get('name') == 'bionic':
        src = p.get('source', '')
        if src == './payload':
            found = True
        elif isinstance(src, dict) and src.get('source') == './payload':
            found = True
print('yes' if found else 'no')
" 2>/dev/null)"
  expect_eq "marketplace.json carries a bionic plugin entry sourcing ./payload" "yes" "$HAS_BIONIC_ENTRY"

  if [ -f "$PLUGIN_JSON" ]; then
    # RE-DERIVED (epic-17 W3 S3, AC-7/AC-8). What Section 2 pinned before: an
    # equality check that allowCrossMarketplaceDependenciesOn named EXACTLY
    # the marketplaces plugin.json's dependencies pointed at (F6,
    # review-6axis.md) — the W2 model, where both deps were declared under
    # marketplaces OTHER than bionic's own (claude-plugins-official,
    # addy-agent-skills), so an explicit cross-marketplace trust grant was a
    # real security boundary. S3 re-points both deps at marketplace "bionic"
    # — the SAME marketplace that contains the requesting plugin — because a
    # same-marketplace, unconstrained dependency is what the probe proved
    # actually installs cleanly (record/epic-17-w3/probe-ac6-marketplace-
    # entry.md); "cross-marketplace" no longer describes any declared
    # dependency. What this pins NOW: no dependency names a marketplace other
    # than "bionic" (the same-marketplace invariant AC-7 requires), and
    # marketplace.json carries no allowCrossMarketplaceDependenciesOn field at
    # all — a trust grant left in a public artifact for a mechanism no
    # shipped dependency uses is the same residual-trust defect F6 named,
    # just with the allow-set now empty by construction instead of drifted.
    NON_BIONIC_MARKETPLACES="$(python3 -c "
import json
plugin = json.load(open('$PLUGIN_JSON'))
deps = plugin.get('dependencies', [])
named = sorted({dep['marketplace'] for dep in deps
                if isinstance(dep, dict) and dep.get('marketplace') and dep['marketplace'] != 'bionic'})
print(','.join(named))
" 2>/dev/null)"
    expect_eq "every plugin.json dependency is declared under bionic's own marketplace (no cross-marketplace deps)" \
      "" "$NON_BIONIC_MARKETPLACES"

    HAS_ALLOWLIST="$(python3 -c "
import json
d = json.load(open('$MARKETPLACE_JSON'))
print('yes' if 'allowCrossMarketplaceDependenciesOn' in d else 'no')
" 2>/dev/null)"
    expect_eq "marketplace.json carries no allowCrossMarketplaceDependenciesOn field (no cross-marketplace deps to grant)" \
      "no" "$HAS_ALLOWLIST"
  fi
else
  echo "SKIP: remaining Section 2 checks (marketplace.json missing)"
fi

# ============================================================
# SECTION 3: LICENSE
# ============================================================

echo ""
echo "=== Section 3: LICENSE ==="

expect_true "LICENSE exists at repo root" test -f "$LICENSE_FILE"

if [ -f "$LICENSE_FILE" ]; then
  LICENSE_TEXT="$(cat "$LICENSE_FILE")"
  expect_contains "LICENSE contains MIT License" "MIT License" "$LICENSE_TEXT"
fi

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
