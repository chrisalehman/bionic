#!/bin/bash
# VERSION COMPARE — L-DETECT/4.2 (spec AC-19).
#
# WHAT THIS SUITE OWNS. `payload/scripts/lib/detect.sh`'s `version_compare`, a
# semver-shaped three-int ordering primitive, and the one caller it feeds:
# `detect_plugin_latest`'s installed-vs-marketplace compare, which used to be
# STRING inequality (`[ "$installed" = "$latest" ]` → current, else lag
# unconditionally) — so an installed build NEWER than the marketplace's cached
# clone read as "behind" it. `detect_plugin_latest` now reports a third state,
# `ahead`, for exactly that case.
#
# NOT `detect_registry_sha_lag`. That function compares git commit SHAs for a
# directory-source feed and has no version field to order — it keeps its
# existing states (match/lag/not-in-repo/unknown) unchanged. Only the git-feed,
# marketplace-clone compare in `detect_plugin_latest` gains `ahead`.
#
# WHAT THIS SUITE DOES NOT OWN. How doctor.sh RENDERS an `ahead` row — that is
# a later task in this wave (the DOCTOR task); this suite only pins the
# library-level state, not doctor's presentation of it.
#
# HERMETIC, DIRECT-SOURCED (same posture as tests/detect-probes.test.sh):
# no network, no live ~/.claude. `version_compare` is a pure function, called
# through a `bash -c '. "$1"; shift; "$@"'` subshell so it never pollutes this
# suite's own environment. `detect_plugin_latest` is driven against fixture
# BIONIC_PLUGIN_ROOT / BIONIC_KNOWN_MARKETPLACES_FILE trees, never the real
# machine's.
#
# Usage: bash tests/version-compare.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
DETECT_SH="${REPO}/payload/scripts/lib/detect.sh"

command -v jq >/dev/null 2>&1 || { echo "version-compare.test.sh: jq is required"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

sourced() {  # <fn> [args...] — run one detect.sh function in a clean subshell
  bash -c '. "$1"; shift; "$@"' _ "$DETECT_SH" "$@" 2>/dev/null
}

section "Section 1: version_compare — semver ordering, not string inequality"

if bash -n "$DETECT_SH" >/dev/null 2>&1; then ok "0: detect.sh passes bash -n"; else no "0: detect.sh passes bash -n"; fi

expect_eq "1: 1.4.0 vs 1.3.2 -> ahead"    "ahead"   "$(sourced version_compare 1.4.0 1.3.2)"
expect_eq "2: 1.3.2 vs 1.3.2 -> current"  "current" "$(sourced version_compare 1.3.2 1.3.2)"
expect_eq "3: 1.3.1 vs 1.3.2 -> lag"      "lag"     "$(sourced version_compare 1.3.1 1.3.2)"
expect_eq "4: 1.10.0 vs 1.9.0 -> ahead (numeric, not lexical)" \
  "ahead" "$(sourced version_compare 1.10.0 1.9.0)"
expect_eq "5: 1.9.0 vs 1.10.0 -> lag (the reverse of 4)" \
  "lag" "$(sourced version_compare 1.9.0 1.10.0)"
expect_eq "6: a prerelease suffix compares by its release numbers" \
  "lag" "$(sourced version_compare 9.9.9-rc.1 10.0.0)"

finish
