#!/bin/bash
set +x +v
# tests/lib/release-check.sh <list path> — this repo's `release-check:` command (wave-31 T1; spec
# D1, REQ-3 AC-3.5). The release gate runs it from the repository being published, from the last
# release to the working head, and refuses the release on a non-zero exit.
#
# FOUR CHECKS, each always run, and the exit is 0 only when all pass:
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
#   4. the landing numbers: the entry's `### The landing numbers` part names the head and the instant it
#      was rendered for (``landing-report --rows` at <40-hex> on <ISO-UTC>:`, the line `release-note`
#      prints), and its fenced block must equal, field for field, what `hooks/session-poker.sh release-note
#      --at <head> --on <instant> <plan>` prints for the plan the Known limits read. `killed=` is the one
#      field not held: it counts the gate's requests, which the gate prunes. A field that differs is ONE
#      line naming the entry's and the report's. A landing in the run's landing record whose commit the
#      checked head holds and the entry's head does not is ONE line naming the row, unless that landing
#      carried the entry (its commit's CHANGELOG.md holds the head line, its first parent's does not): the
#      entry is rendered again after it. An entry naming no head, and no plan naming the release, each
#      pass with one `landing-numbers:` line.
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
# entry_part <changelog text> <version> <part> -> the lines of that entry's `### <part>`, up to the next `### ` or
# `## ` heading.
entry_part() {
  printf '%s\n' "$1" | awk -v v="$2" -v h="### $3" '
    /^## / { inb = (index($0, "## " v " ") == 1); inp = 0; next }
    !inb { next }
    /^### / { t = $0; sub(/[[:space:]]+$/, "", t); inp = (t == h); next }
    inp'
}
# rel_load <check> -> the libraries both plan-reading checks use, loaded; TOP and DROOT set. One refusal line, rc 2.
rel_load() {
  local lib f
  lib="$HERE/../../payload/scripts/lib"
  command -v jq >/dev/null 2>&1 || { echo "release-check: refused — $1 needs jq, to fold as the sentences were written"; return 2; }
  for f in run.sh proof.sh said.sh worktree.sh; do
    # shellcheck source=/dev/null
    [ -f "$lib/$f" ] && . "$lib/$f" >/dev/null 2>&1 || { echo "release-check: refused — $1 cannot load $lib/$f"; return 2; }
  done
  TOP="$(git rev-parse --show-toplevel 2>/dev/null)" && TOP="$(cd "$TOP" && pwd -P)" || {
    echo "release-check: refused — $1 finds no checkout top"; return 2; }
  DROOT="$(docs_root "$TOP")" || DROOT=""
}
rel_plans() {  # <version> -> each run plan under DROOT whose frontmatter says `release: <version>`
  local f
  while IFS= read -r -d '' f; do
    [ "$(plan_frontmatter_get "$f" release 2>/dev/null)" = "$1" ] && printf '%s\n' "$f"
  done < <([ -z "$DROOT" ] || _run_candidates "$DROOT" 2>/dev/null)
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
  local ver="$1" cl="$2" plans plan kl id s r p t st n=0 bad=0
  rel_load "the Known limits check" || return 2
  plans="$(rel_plans "$ver")"
  if [ -z "$plans" ]; then
    echo "known-limits: $ver — no plan under ${DROOT:-$TOP} names release: $ver, so no deferred sentence is held"
    return 0
  fi
  kl="$(said_fold "$(entry_part "$cl" "$ver" 'Known limits')")"
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
# nums_fence <text> -> the lines of the first fence after the line naming the head the numbers were rendered at.
nums_fence() {
  printf '%s\n' "$1" | awk '
    index($0, "`landing-report --rows` at ") == 1 { h = 1; next }
    h && /^```/ { if (f) exit; f = 1; next }
    f'
}
# nums_holds <rev> <line> -> 0 when CHANGELOG.md at <rev> holds <line> whole. grep reads the file to its end: under
# pipefail, a grep that quits at its match kills the writer of a file longer than a pipe's buffer, and the test fails.
nums_holds() {
  git show "$1:CHANGELOG.md" 2>/dev/null | /usr/bin/grep -xF -- "$2" >/dev/null
}
nums_check() {  # <version> <changelog text> -> one line per disagreement and per later landing, else one landing-numbers: line
  local ver="$1" cl="$2" hl at on plan said rep h12 row c bad=0
  hl="$(entry_part "$cl" "$ver" 'The landing numbers' | /usr/bin/grep -E -m 1 '^`landing-report --rows` at [0-9a-f]{40} on [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z:$')"
  at="${hl#* at }"; at="${at%% *}"; on="${hl##* on }"; on="${on%:}"
  if [ -z "$hl" ]; then
    echo "landing-numbers: $ver — the entry names no head its numbers were rendered at, so none is held to the report"
    return 0
  fi
  rel_load "the landing numbers check" || return 2
  plan="$(rel_plans "$ver" | head -n 1)"
  if [ -z "$plan" ]; then
    echo "landing-numbers: $ver — no plan under ${DROOT:-$TOP} names release: $ver, so its numbers are not held to the report"
    return 0
  fi
  h12="${at:0:12}"
  rep="$(bash "$HERE/../../hooks/session-poker.sh" release-note --at "$at" --on "$on" "$plan" 2>&1)" || {
    echo "release-check: refused — release-note cannot render the landing report at $h12: $(printf '%s\n' "$rep" | head -n 1)"; return 2; }
  said="$(nums_fence "$(entry_part "$cl" "$ver" 'The landing numbers')")"
  rep="$(nums_fence "$rep")"
  # Field for field, line by line: the first field of a line that differs is that line's one finding.
  if [ "$said" != "$rep" ]; then
    awk -v ver="$ver" -v h="$h12" '
      FILENAME == ARGV[1] { e[++ne] = $0; next }
      { r[++nr] = $0 }
      END {
        if (ne != nr) { printf "release-check: the landing numbers of %s hold %d lines where the landing report at %s holds %d\n", ver, ne, h, nr; exit 1 }
        for (i = 1; i <= ne; i++) {
          n = split(e[i], a, " "); m = split(r[i], b, " "); if (m > n) n = m
          for (k = 1; k <= n; k++) {
            if (a[k] == b[k] || (a[k] ~ /^killed=/ && b[k] ~ /^killed=/)) continue
            printf "release-check: the landing numbers of %s say %s where the landing report at %s says %s\n", ver, (a[k] == "" ? "nothing" : a[k]), h, (b[k] == "" ? "nothing" : b[k])
            bad = 1; break
          }
        }
        exit bad
      }' <(printf '%s\n' "$said") <(printf '%s\n' "$rep") || bad=1
  fi
  # A landing the checked head holds and the entry's head does not came after the entry, unless it carried it.
  while IFS='|' read -r row c; do
    git merge-base --is-ancestor "$c" "$head" 2>/dev/null || continue
    ! git merge-base --is-ancestor "$c" "$at" 2>/dev/null || continue
    if nums_holds "$c" "$hl" && ! nums_holds "$c^1" "$hl"; then continue; fi
    echo "release-check: the landing numbers of $ver are at $h12, and $row landed after them at ${c:0:12}; render them again with release-note"
    bad=1
  done < <(awk -F'|' '$1 == "line/v1" && $2 == "ev=published" { r = c = ""
      for (k = 3; k <= NF; k++) { if (index($k, "row=") == 1) r = substr($k, 5); if (index($k, "commit=") == 1) c = substr($k, 8) }
      if (r != "" && c != "") print r "|" c }' "$(_wt_proofs_path "$TOP" "$plan")" 2>/dev/null)
  [ "$bad" -ne 0 ] || echo "landing-numbers: $ver agrees with the landing report at $h12"
  return "$bad"
}
# The libraries they source are written for callers without `set -u`, so each plan-reading check runs in a subshell
# without it; its lines pass through and its status is read.
if [ -n "$chg_version" ]; then
  for chk in lim_check nums_check; do
    ( set +u; "$chk" "$chg_version" "$changelog" ); rc=$?
    case "$rc" in
      0) : ;;
      1) [ "$status" -ne 0 ] || status=1 ;;
      *) refusals=1 ;;
    esac
  done
fi

# ---- the name scan ---------------------------------------------------------------------------
bash "$HERE/name-scan.sh" "$list" || { rc=$?; [ "$status" -ne 0 ] || status="$rc"; }

[ "$refusals" -eq 0 ] || [ "$status" -ne 0 ] || status=2
exit "$status"
