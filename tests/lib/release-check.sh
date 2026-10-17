#!/bin/bash
set +x +v
# tests/lib/release-check.sh <list path> — this repo's `release-check:` command (wave-31 T1; spec
# D1, REQ-3 AC-3.5). The release gate runs it from the repository being published, from the last
# release to the working head, and refuses the release on a non-zero exit.
#
# THREE CHECKS, each always run, and the exit is 0 only when all pass:
#
#   1. the name scan (tests/lib/name-scan.sh <list path>, same working directory, same
#      environment: BIONIC_CHECK_BASE and BIONIC_CHECK_HEAD are the scan's own). Its output is
#      passed through unchanged.
#   2. the version pair: the newest `## <version> — <date>` heading in CHANGELOG.md equals
#      `.version` in payload/.claude-plugin/plugin.json. Both are read from the tree at
#      BIONIC_CHECK_HEAD (default HEAD) with `git show`, as the scan reads, so the answer is what
#      a push would publish and never what the working files say. This is the one contract the
#      retired pin suite held that no other suite holds.
#   3. the Known limits (wave-38 T20; REQ-11 AC-11.4, L8): the release being shipped is the newest
#      heading the pair reads, and its plan is the run whose frontmatter says `release: <version>`,
#      found by the walk every reader of a project's runs uses (lib/run.sh `_run_candidates` under
#      `docs_root` of this checkout's top). Every OPEN deferral of that plan (lib/proof.sh
#      `proof_findings_owed` rating it `defer`, the reader close-out's continuation carries by) that
#      states its sentence (the ` stated="…"` field `finding-stated` writes, unescaped) must stand
#      under the entry's `### Known limits`, both sides folded by lib/said.sh `said_fold`, the one
#      fold the sentence was written through. A missing one is ONE line naming the finding and the
#      sentence, and exit 1. The plan is read from the working files: `.bionic/` is ignored, so the
#      head's tree holds no plan to read. No plan naming the release (a closed run is archived), and
#      a plan with no stated deferral, each pass with one `known-limits:` line saying so; a pass with
#      sentences held says how many, in one such line. Generalised from the §CORR rule of
#      tests/release-check.test.sh, which held one release to one plan by hand.
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

# ---- the Known limits of the release being shipped -------------------------------------------
# lim_section <changelog text> <version> -> the lines of that entry's `### Known limits` part, up to the next
# `### ` or `## ` heading.
lim_section() {
  printf '%s\n' "$1" | awk -v v="$2" '
    /^## / { inb = (index($0, "## " v " ") == 1); inp = 0; next }
    !inb { next }
    /^### / { inp = ($0 ~ /^### Known limits[[:space:]]*$/); next }
    inp'
}
# lim_sentence <plan> <record>#<n> -> the stated sentence of the first `deferred:` line of `## SDLC State`
# naming it, unescaped; nothing when the line states none.
lim_sentence() {
  awk -v id="$2" '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && /^deferred:[ \t]/ { split($0, f, /[ \t]+/); if (f[2] == id) { print; exit } }' "$1" \
    | sed -n 's/^.* stated="\(.*\)"[[:space:]]*$/\1/p' | sed -e 's/\\\(.\)/\1/g'
}
lim_check() {  # <version> <changelog text> -> one line per omission, or one known-limits: line; exit 1 on an omission
  local ver="$1" cl="$2" lib top droot f plans="" plan kl id s r p t st n=0 bad=0
  lib="$HERE/../../payload/scripts/lib"
  command -v jq >/dev/null 2>&1 || { echo "release-check: refused — the Known limits check needs jq, to fold as the sentences were written"; return 2; }
  for f in run.sh proof.sh said.sh; do
    # shellcheck source=/dev/null
    [ -f "$lib/$f" ] && . "$lib/$f" >/dev/null 2>&1 || { echo "release-check: refused — the Known limits check cannot load $lib/$f"; return 2; }
  done
  top="$(git rev-parse --show-toplevel 2>/dev/null)" && top="$(cd "$top" && pwd -P)" || {
    echo "release-check: refused — the Known limits check finds no checkout top"; return 2; }
  droot="$(docs_root "$top")" || droot=""
  while IFS= read -r -d '' f; do
    [ "$(plan_frontmatter_get "$f" release 2>/dev/null)" = "$ver" ] && plans="${plans}${f}
"
  done < <([ -z "$droot" ] || _run_candidates "$droot" 2>/dev/null)
  if [ -z "$plans" ]; then
    echo "known-limits: $ver — no plan under ${droot:-$top} names release: $ver, so no deferred sentence is held"
    return 0
  fi
  kl="$(said_fold "$(lim_section "$cl" "$ver")")"
  while IFS= read -r plan; do
    [ -n "$plan" ] || continue
    n=0
    while read -r id s r p t; do
      [ "$p" = defer ] || continue
      st="$(said_fold "$(lim_sentence "$plan" "$id")")"
      [ -n "$st" ] || continue
      n=$((n + 1))
      case "$kl" in *"$st"*) continue ;; esac
      echo "release-check: Known limits of $ver omit the deferred sentence of $id: $st"
      bad=1
    done < <(proof_findings_owed "$plan" 2>/dev/null)
    if [ "$n" -eq 0 ]; then echo "known-limits: $ver — $plan states no deferred sentence"
    elif [ "$bad" -eq 0 ]; then echo "known-limits: $ver carries the $n deferred sentences of $plan"; fi
  done <<LIM_PLANS
$plans
LIM_PLANS
  return "$bad"
}
# The libraries it sources are written for callers without `set -u`, so the check runs in a subshell
# without it; its lines pass through and its status is read.
if [ -n "$chg_version" ]; then
  ( set +u; lim_check "$chg_version" "$changelog" ); rc=$?
  case "$rc" in
    0) : ;;
    1) [ "$status" -ne 0 ] || status=1 ;;
    *) refusals=1 ;;
  esac
fi

# ---- the name scan ---------------------------------------------------------------------------
bash "$HERE/name-scan.sh" "$list" || { rc=$?; [ "$status" -ne 0 ] || status="$rc"; }

[ "$refusals" -eq 0 ] || [ "$status" -ne 0 ] || status=2
exit "$status"
