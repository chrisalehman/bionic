#!/bin/bash
set +x +v
# tests/lib/release-check.sh <list path> — this repo's `release-check:` command (wave-31 T1; spec
# D1, REQ-3 AC-3.5). The release gate runs it from the repository being published, from the last
# release to the working head, and refuses the release on a non-zero exit.
#
# SIX CHECKS, each always run, and the exit is 0 only when all pass:
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
#      `docs_root` of the project: BIONIC_CHECK_PROJECT when set, else this checkout's top). Every OPEN deferral of that plan (lib/proof.sh
#      `proof_findings_owed` rating it `defer`, the reader close-out's continuation carries by) that
#      states its sentence (lib/proof.sh `proof_finding_stated`, the move's `stated=` field, unescaped) must stand
#      under the entry's `### Known limits`, both sides folded by lib/said.sh `said_fold`, the one
#      fold the sentence was written through. A missing one is ONE line naming the finding and the
#      sentence, and exit 1. An open deferral rated `defer` that states none, or a `-` for one (the form a
#      carried unstated deferral is written in), is ONE line naming the finding, and exit 1: no sentence is
#      no limit to carry, for a release at or past LIM_RULE_FROM only: an earlier release's unstated deferral is
#      passed over, its known-limits line unchanged. The plan is read from the working files: `.bionic/` is ignored, so the
#      head's tree holds no plan to read. No plan naming the release (a closed run is archived), and
#      a plan with no stated deferral, each pass with one `known-limits:` line saying so; a pass with
#      sentences held says how many, in one such line.
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
#   5. the cap on tests: the non-whitespace characters of the tracked `*.sh` files under tests/ against those
#      everywhere else, in the tree at BIONIC_CHECK_HEAD, never the working files, so joining lines changes no reading.
#      Tests may be 1.25 times the code, the code counted as the largest of the head's, BIONIC_CHECK_BASE's and
#      BIONIC_CHECK_RELEASE's (the last release, which the runner exports), so code deleted since the base takes no
#      room. A pass prints `test-ratio: <tests>/<code> chars · limit <n> · room <n>`,
#      the line the release approval page and the situation report read; a head past the limit prints the same line
#      after `release-check: ` and exits 1. A head with no shell file outside tests/ has nothing to count against: ONE
#      line and exit 2, never a pass. A head over the limit is admitted when its tests are at or under the base's. A
#      symlink is not counted, so a directory reached through one counts once. One `git ls-tree` and one `git cat-file
#      --batch` read the head: a `git show` per file would cost a minute where this costs a second.
#   6. the copies: payload/scripts/one-reader-check.sh beside this file's tests/lib/, so the copy the judge holds, run
#      over the tree at BIONIC_CHECK_HEAD written out with `git archive`, never the working files. Each refusal it prints
#      is ONE line after `release-check: ` and the exit is 1: a second parser of a plan or a log, a second writer of a
#      plan, a copied loader, whatever its REFUSING list names. A pass prints its counts on one `one-reader:` line. A
#      head holding no hooks/ and payload/scripts/ has no copy to count, and passes with one `one-reader:` line saying
#      so; a head that cannot be written out, or a judge with no copy check, is ONE line and exit 2.
#
# On a mismatch it prints ONE line naming both versions and exits 1. A missing list path, a list
# that is not a file, and a pair that cannot be read (no release heading, no `.version`, a path
# the head does not hold) are each ONE line and a non-zero exit (2 for a refusal).
#
# COUNT MODE: `release-check.sh --count <rev>` prints `<tests> <code>`, the two numbers check 5 reads, for the tree at
# <rev>, and stops before any check runs. It exits with the count's own status: 1 for a name that is no tree, 2 for a tree
# with no shell file outside tests/, 3 for blobs that cannot be read; no revision named is a refusal, 2.
#
# bash 3.2 (ADR-001). Not part of the shipped plugin.
unset BASH_ENV ENV
set -u -o pipefail

# ratio_count <rev> -> `<tests> <code>`, the non-whitespace characters of the shell files of the tree at <rev>, on
# stdout, status 0; status 1 when the tree cannot be read, 2 when it holds no shell file outside tests/, 3 when its
# blobs cannot be read. Characters, not lines, so joining lines changes no reading. Every blob rides one
# `git cat-file --batch` whose header is its size and its side; the size says where its content ends, so no line of
# content is ever read as a header. LC_ALL=C counts bytes, so a file that is not valid text is still read whole.
ratio_count() {
  local rev="$1" lst
  # One line per counted blob, its object and its side: T for a path under tests/, C for any other; links, trees and submodules are not blobs of text.
  lst="$(git ls-tree -r -z "$rev" 2>/dev/null | tr '\0' '\n' | LC_ALL=C awk -F'\t' '
    { split($1, m, " "); p = substr($0, length($1) + 2)
      if (m[2] == "blob" && m[1] != "120000" && p ~ /\.sh$/) print m[3] (index(p, "tests/") == 1 ? " T" : " C") }')" || lst=""
  if [ -z "$lst" ] && ! git rev-parse --verify -q "$rev^{tree}" >/dev/null 2>&1; then
    return 1
  fi
  case "$lst" in *' C'|*' C'$'\n'*) ;; *) return 2 ;; esac
  printf '%s\n' "$lst" | git cat-file --batch='%(objectsize) %(rest)' 2>/dev/null | LC_ALL=C awk '
    left <= 0 { if ($2 != "T" && $2 != "C") { bad = 1; next } left = $1 + 1; k = $2; next }
    { left -= length($0) + 1; gsub(/[[:space:]]/, ""); n[k] += length($0) }
    END { if (bad || left > 0) exit 1; printf "%d %d\n", n["T"], n["C"] }' || return 3
}

if [ "${1:-}" = --count ]; then
  [ -n "${2:-}" ] || { echo "release-check: refused — usage: release-check.sh --count <rev>" >&2; exit 2; }
  ratio_count "$2"; exit $?
fi

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
# The first release the unstated-deferral refusal applies to. Releases before it shipped under the older rule,
# which let a deferral go unstated, so theirs are passed over: not counted, not refused. From this release on an
# unstated or dashed defer deferral refuses the release. A stated deferral is held to Known limits at every release.
LIM_RULE_FROM=1.24.0
# lim_version_at_least <a> <b> -> exit 0 when dotted version <a> is at or past <b>, compared part by part as
# integers (1.9.9 is below 1.24.0, which a string compare gets wrong); a missing part reads as 0.
lim_version_at_least() {
  local a="$1" b="$2" x y
  while [ -n "$a$b" ]; do
    x="${a%%.*}"; y="${b%%.*}"
    case "$a" in *.*) a="${a#*.}" ;; *) a="" ;; esac
    case "$b" in *.*) b="${b#*.}" ;; *) b="" ;; esac
    x="${x%%[!0-9]*}"; y="${y%%[!0-9]*}"
    x=$((10#${x:-0})); y=$((10#${y:-0}))
    [ "$x" -gt "$y" ] && return 0
    [ "$x" -lt "$y" ] && return 1
  done
  return 0
}
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
  for f in run.sh proof.sh said.sh worktree.sh line.sh; do
    # shellcheck source=/dev/null
    [ -f "$lib/$f" ] && . "$lib/$f" >/dev/null 2>&1 || { echo "release-check: refused — $1 cannot load $lib/$f"; return 2; }
  done
  # The project is BIONIC_CHECK_PROJECT when the runner names it: the check then runs in a landing tree at the
  # release base, which holds no plan and no record of its own. Unset, it is this checkout's top.
  TOP="${BIONIC_CHECK_PROJECT:-}"
  [ -n "$TOP" ] || TOP="$(git rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$TOP" ] && TOP="$(cd "$TOP" && pwd -P)" || {
    echo "release-check: refused — $1 finds no checkout top"; return 2; }
  DROOT="$(docs_root "$TOP")" || DROOT=""
}
rel_plans() {  # <version> -> each run plan under DROOT whose frontmatter says `release: <version>`
  local f
  while IFS= read -r -d '' f; do
    [ "$(plan_frontmatter_get "$f" release 2>/dev/null)" = "$1" ] && printf '%s\n' "$f"
  done < <([ -z "$DROOT" ] || _run_candidates "$DROOT" 2>/dev/null)
}
lim_check() {  # <version> <changelog text> -> one line per omission, or one known-limits: line; exit 1 on an omission
  local ver="$1" cl="$2" plans plan kl id s r p t st n=0 un=0 bad=0
  rel_load "the Known limits check" || return 2
  plans="$(rel_plans "$ver")"
  if [ -z "$plans" ]; then
    echo "known-limits: $ver — no plan under ${DROOT:-$TOP} names release: $ver, so no deferred sentence is held"
    return 0
  fi
  kl="$(said_fold "$(entry_part "$cl" "$ver" 'Known limits')")"
  while IFS= read -r plan; do
    [ -n "$plan" ] || continue
    n=0 un=0
    while read -r id s r p t; do
      [ "$p" = defer ] || continue
      st="$(said_fold "$(proof_finding_stated "$plan" "$id")")"
      # Before the floor an unstated deferral, or a dash for one, is passed over as the older rule passed it.
      if ! lim_version_at_least "$ver" "$LIM_RULE_FROM"; then
        { [ -z "$st" ] || [ "$st" = - ]; } && continue
      fi
      # A deferral with no sentence, or a dash where it would stand, leaves nothing for Known limits to carry.
      if [ -z "$st" ] || [ "$st" = - ]; then
        echo "release-check: $ver defers $id with no stated sentence; state it or fix it"
        un=$((un + 1)); bad=1
        continue
      fi
      n=$((n + 1))
      case "$kl" in *"$st"*) continue ;; esac
      echo "release-check: Known limits of $ver omit the deferred sentence of $id: $st"
      bad=1
    done < <(proof_findings_owed "$plan" 2>/dev/null)
    if [ "$n" -eq 0 ] && [ "$un" -eq 0 ]; then echo "known-limits: $ver — $plan states no deferred sentence"
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
  rep="$(cd "$TOP" && bash "$HERE/../../hooks/session-poker.sh" release-note --at "$at" --on "$on" "$plan" 2>&1)" || {
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
  done < <(rec="$(_wt_proofs_path "$TOP" "$plan")" && line_lines "$rec" 2>/dev/null \
    | awk -F'|' '($1 == "line/v1" || $1 == "run/v1") && $2 == "ev=published" { r = c = ""
      for (k = 3; k <= NF; k++) { if (index($k, "row=") == 1) r = substr($k, 5); if (index($k, "commit=") == 1) c = substr($k, 8) }
      if (r != "" && c != "") print r "|" c }')
  [ "$bad" -ne 0 ] || echo "landing-numbers: $ver agrees with the landing report at $h12"
  return "$bad"
}
# ratio_check -> `test-ratio: <tests>/<code> chars · limit <n> · room <n>` on a pass; the same line after
# `release-check: ` and exit 1 when the tests pass the limit; one line and exit 2 when the head cannot be read or holds
# no shell code outside tests/. The limit is 1.25 times the largest of the head's code, BIONIC_CHECK_BASE's and, when it
# names a commit, BIONIC_CHECK_RELEASE's, rounded down, so code deleted since the base takes no room. A landing's base
# is the target's head before it, so the release's count is what keeps a deletion landed earlier in the release from
# lowering the limit at the landing after. A head over the limit is admitted when its tests are at or under
# the base's: the cap cannot be met in one landing by a repository already over it, and the landing to refuse is the
# one that grows the tests. A base that cannot be read compares nothing, so the head alone is judged.
ratio_check() {
  local t c rc t0="" c0=0 base="${BIONIC_CHECK_BASE:-}" rel="${BIONIC_CHECK_RELEASE:-}" bc lim reading
  c="$(ratio_count "$head")"; rc=$?
  case "$rc" in
    0) : ;;
    1) echo "release-check: refused — test-ratio cannot read the tree at $head"; return 2 ;;
    2) echo "release-check: refused — test-ratio finds no shell file outside tests/ at $head, so there is no code to count tests against"; return 2 ;;
    *) echo "release-check: refused — test-ratio cannot read the shell files at $head"; return 2 ;;
  esac
  t="${c% *}"; c="${c#* }"
  if [ -n "$base" ] && bc="$(ratio_count "$base")"; then
    t0="${bc% *}"; c0="${bc#* }"
  fi
  if [ -n "$rel" ] && bc="$(ratio_count "$rel")" && [ "${bc#* }" -gt "$c0" ]; then
    c0="${bc#* }"
  fi
  lim=$(( (c > c0 ? c : c0) * 5 / 4 ))
  reading="test-ratio: $t/$c chars · limit $lim · room $(( lim - t ))"
  if [ "$t" -gt "$lim" ] && ! { [ -n "$t0" ] && [ "$t" -le "$t0" ]; }; then
    echo "release-check: $reading — tests pass 1.25 times the code at $head"
    return 1
  fi
  echo "$reading"
}
# fold_rc <rc> -> a check's status read into the exit: 0 passes, 1 fails the release, anything else is a refusal.
fold_rc() {
  case "$1" in
    0) : ;;
    1) [ "$status" -ne 0 ] || status=1 ;;
    *) refusals=1 ;;
  esac
}
# The libraries they source are written for callers without `set -u`, so each plan-reading check runs in a subshell
# without it; its lines pass through and its status is read.
if [ -n "$chg_version" ]; then
  for chk in lim_check nums_check; do
    ( set +u; "$chk" "$chg_version" "$changelog" ); fold_rc $?
  done
fi
# The cap reads the head's tree alone, so it runs whatever the release heading says.
( set +u; ratio_check ); fold_rc $?

# copies_check -> the judge's copy check over the head's tree; 0 passes, 1 a refused copy, 2 not run. Run in a subshell,
# so its scratch tree goes with it.
copies_check() {
  local orc="$HERE/../../payload/scripts/one-reader-check.sh" t out rc
  if ! git cat-file -e "$head:hooks" 2>/dev/null || ! git cat-file -e "$head:payload/scripts" 2>/dev/null; then
    echo "one-reader: $head holds no hooks/ and payload/scripts/, so no copy to count"; return 0
  fi
  [ -f "$orc" ] || { echo "release-check: refused — the judge holds no copy check at $orc"; return 2; }
  t="$(mktemp -d "${TMPDIR:-/tmp}/release-check-copies.XXXXXX")" || { echo "release-check: refused — no scratch directory for the copy check"; return 2; }
  trap 'rm -rf "$t"' EXIT
  mkdir "$t/tree" && git archive "$head" | tar -x -C "$t/tree" \
    || { echo "release-check: refused — the tree at $head cannot be written out for the copy check"; return 2; }
  out="$(bash "$orc" "$t/tree" 2>"$t/err")"; rc=$?
  case "$rc" in
    0) printf '%s\n' "$out" | awk -F= 'NF == 2 && $1 ~ /^[a-z_]+$/ && $2 ~ /^[0-9]+$/ { s = s (s == "" ? "" : " ") $0 } END { print "one-reader: " s }' ;;
    1) sed 's/^/release-check: /' "$t/err" ;;
    *) echo "release-check: refused — the copy check could not read the tree at $head: $(tr '\n' ' ' < "$t/err")" ;;
  esac
  return "$rc"
}
( set +u; copies_check ); fold_rc $?

# ---- the name scan ---------------------------------------------------------------------------
bash "$HERE/name-scan.sh" "$list" || { rc=$?; [ "$status" -ne 0 ] || status="$rc"; }

[ "$refusals" -eq 0 ] || [ "$status" -ne 0 ] || status=2
exit "$status"
