#!/bin/bash
set +x +v
# tests/lib/release-check.sh <list path> — this repo's `release-check:` command (wave-31 T1; spec
# D1, REQ-3 AC-3.5). The release gate runs it from the repository being published, from the last
# release to the working head, and refuses the release on a non-zero exit.
#
# TWO CHECKS, both always run, and the exit is 0 only when both pass:
#
#   1. the name scan (tests/lib/name-scan.sh <list path>, same working directory, same
#      environment: BIONIC_CHECK_BASE and BIONIC_CHECK_HEAD are the scan's own). Its output is
#      passed through unchanged.
#   2. the version pair: the newest `## <version> — <date>` heading in CHANGELOG.md equals
#      `.version` in payload/.claude-plugin/plugin.json. Both are read from the tree at
#      BIONIC_CHECK_HEAD (default HEAD) with `git show`, as the scan reads, so the answer is what
#      a push would publish and never what the working files say. This is the one contract the
#      retired pin suite held that no other suite holds.
#
# On a mismatch it prints ONE line naming both versions and exits 1. A missing list path, a list
# that is not a file, and a pair that cannot be read (no release heading, no `.version`, a path
# the head does not hold) are each ONE line and a non-zero exit (2 for a refusal).
#
# bash 3.2 (ADR-001). Not part of the shipped plugin.
unset BASH_ENV ENV
set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)" || exit 2
refusals=0
status=0

list="${1:-}"
if [ -z "$list" ]; then
  echo "release-check: refused — usage: release-check.sh <list path>" >&2
  exit 2
fi
if [ ! -f "$list" ]; then
  echo "release-check: refused — the list path is not a file" >&2
  exit 2
fi

head="${BIONIC_CHECK_HEAD:-HEAD}"

# ---- the version pair, from the tree at the head --------------------------------------------
changelog="$(git show "$head:CHANGELOG.md" 2>/dev/null)" || changelog=""
plugin="$(git show "$head:payload/.claude-plugin/plugin.json" 2>/dev/null)" || plugin=""

chg_version="$(printf '%s\n' "$changelog" | sed -n 's/^## \([0-9][0-9.]*[0-9]\)[[:space:]].*/\1/p' | head -n 1)"
plugin_version="$(printf '%s' "$plugin" | jq -r '.version // empty' 2>/dev/null)" || plugin_version=""

if [ -z "$chg_version" ]; then
  echo "release-check: refused — no release heading in CHANGELOG.md at $head"
  refusals=1
elif [ -z "$plugin_version" ]; then
  echo "release-check: refused — no version in payload/.claude-plugin/plugin.json at $head"
  refusals=1
elif [ "$chg_version" != "$plugin_version" ]; then
  echo "release-check: version mismatch — CHANGELOG.md says $chg_version, plugin.json says $plugin_version"
  status=1
fi

# ---- the name scan ---------------------------------------------------------------------------
bash "$HERE/name-scan.sh" "$list" || { rc=$?; [ "$status" -ne 0 ] || status="$rc"; }

[ "$refusals" -eq 0 ] || [ "$status" -ne 0 ] || status=2
exit "$status"
