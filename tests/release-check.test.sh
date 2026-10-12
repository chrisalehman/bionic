#!/bin/bash
# Tests for tests/lib/release-check.sh — this repo's `release-check:` command (wave-31 T1; spec
# D1, REQ-3 AC-3.5).
#
# THE CONTRACT THE DELETED PIN SUITE HELD THAT NO OTHER SUITE HOLDS: the CHANGELOG's newest
# heading equals `.version` in payload/.claude-plugin/plugin.json. The release check runs the
# name scan AND that pair, both read from the tree at BIONIC_CHECK_HEAD (default HEAD) with
# `git show`, so a check run in a dirty working tree judges what a push would publish.
#
#   §VERSION-PAIR   an agreeing pair passes; a doctored CHANGELOG heading and a doctored
#                   plugin.json version each fail with ONE line naming both versions; the check
#                   reads the HEAD tree, never the working files; BIONIC_CHECK_HEAD picks the tree.
#   §REFUSE         no list path, and a pair that cannot be read, are one-line refusals.
#   §SCAN           the name scan still runs under it: a listed entry planted in a committed
#                   file fails the check, beside the clean run on the same repository.
#   §STRIKE         the 1.17.0 block against the strike list of ten (wave-34 REQ-6, AC-6.1, AC-6.2,
#                   AC-1.5): each of the ten 1.16.0 Known limits is struck with a record or carried
#                   with a sentence that says why, no other 1.16.0 bullet vanishes, the count of
#                   unstruck bullets is stated beside 1.16.0's 20 and equals the bullets counted,
#                   and the narrowed per-tree-marker limit names no launcher. Read from the
#                   repository's own CHANGELOG.md; each rule has a doctored copy that goes red.
#
# FIXTURE FIDELITY: every repository is a real `git init` under a mktemp directory with real
# commits; nothing is a mock of git. The list file lives outside every checkout and holds one
# made-up entry. The real tree is never written; §STRIKE reads its CHANGELOG.md and writes only
# doctored copies under the scratch directory. SYNTHESIZED: the versions and the entry.
#
# Usage: bash tests/release-check.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

CHECK="${BIONIC_SCRIPTS_DIR}/tests/lib/release-check.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/release-check-test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
mkdir -p "$TMP/lists"

ENTRY="zq-alpha-7731"
LIST="$TMP/lists/names.list"
printf '%s\n' "$ENTRY" > "$LIST"

setup_section "fixtures"

[ -r "$CHECK" ] || { echo "FAIL: $CHECK is not readable"; exit 1; }
expect_false "setup: the list directory is outside every checkout" git -C "$TMP/lists" rev-parse --show-toplevel

# fx_changelog <version> — a CHANGELOG whose newest heading is <version>, older one below it
fx_changelog() {
  printf '# Changelog\n\n## %s — 2026-01-02\n\n- a change\n\n## 0.0.1 — 2026-01-01\n\n- first\n' "$1"
}
# fx_plugin <version>
fx_plugin() { printf '{\n  "name": "fixture",\n  "version": "%s"\n}\n' "$1"; }
# fx_repo <dir> <changelog version> <plugin version> — a committed pair
fx_repo() {
  mkdir -p "$1/payload/.claude-plugin" &&
  git -C "$1" init -q --template= &&
  git -C "$1" config commit.gpgsign false &&
  fx_changelog "$2" > "$1/CHANGELOG.md" && fx_plugin "$3" > "$1/payload/.claude-plugin/plugin.json" &&
  printf 'base\n' > "$1/a.txt" &&
  git -C "$1" add -A && git -C "$1" commit -q -m "first"
}
# run_check <repo> [args...] — sets OUT (stdout+stderr) and RC; the list is the default argument
run_check() {
  local repo="$1"; shift
  [ "$#" -gt 0 ] || set -- "$LIST"
  OUT="$(cd "$repo" && env -u BIONIC_CHECK_BASE -u BIONIC_CHECK_HEAD bash "$CHECK" "$@" 2>&1)"; RC=$?
}
# lines_of <text> — the number of lines the check itself printed (its `release-check:` lines);
# the name scan's own output, which rides along on stdout, is not counted
lines_of() { printf '%s\n' "$1" | awk '/^release-check:/ { n++ } END { print n + 0 }'; }

section "§VERSION-PAIR — the newest CHANGELOG heading equals plugin.json's version, read from the HEAD tree"

R="$TMP/agree"; fx_repo "$R" 2.3.4 2.3.4
run_check "$R"
expect_status "(i) an agreeing pair, a clean scan: the check passes" 0 "$RC"

R="$TMP/chg"; fx_repo "$R" 2.3.4 2.3.4
fx_changelog 2.3.5 > "$R/CHANGELOG.md"; git -C "$R" commit -q -am "doctor the heading"
run_check "$R"
expect_status "(ii) a doctored CHANGELOG heading: the check fails" 1 "$RC"
expect_contains "(ii) …and the line names the CHANGELOG's version" "2.3.5" "$OUT"
expect_contains "(ii) …and the line names the plugin's version" "2.3.4" "$OUT"
expect_eq "(ii) …in one line" "1" "$(lines_of "$OUT")"

R="$TMP/plg"; fx_repo "$R" 2.3.4 2.3.4
fx_plugin 2.3.9 > "$R/payload/.claude-plugin/plugin.json"; git -C "$R" commit -q -am "doctor the version"
run_check "$R"
expect_status "(iii) a doctored plugin.json version: the check fails" 1 "$RC"
expect_contains "(iii) …and the line names the plugin's version" "2.3.9" "$OUT"
expect_contains "(iii) …and the CHANGELOG's" "2.3.4" "$OUT"
expect_eq "(iii) …in one line" "1" "$(lines_of "$OUT")"

# (iv) the HEAD tree, not the working file: the working CHANGELOG disagrees, nothing is committed.
R="$TMP/dirty"; fx_repo "$R" 2.3.4 2.3.4
run_check "$R"
expect_status "(iv) setup: the clean repository passes" 0 "$RC"
CLEAN_OUT="$OUT"
fx_changelog 7.7.7 > "$R/CHANGELOG.md"
expect_contains "(iv) setup: the working CHANGELOG really does disagree with the committed one" \
  "7.7.7" "$(cat "$R/CHANGELOG.md")"
expect_nonempty "(iv) setup: the repository really is dirty" "$(git -C "$R" status --porcelain)"
run_check "$R"
expect_status "(iv) a working CHANGELOG edited and not committed: the check still passes (HEAD is read)" 0 "$RC"
expect_eq "(iv) …and prints what the clean run of the same repository printed" "$CLEAN_OUT" "$OUT"

# BIONIC_CHECK_HEAD picks the tree: the bad commit is HEAD, the good one is HEAD~1.
R="$TMP/pick"; fx_repo "$R" 2.3.4 2.3.4
fx_changelog 2.3.5 > "$R/CHANGELOG.md"; git -C "$R" commit -q -am "doctor the heading"
run_check "$R"
expect_status "(v) the doctored HEAD fails" 1 "$RC"
OUT="$(cd "$R" && env -u BIONIC_CHECK_BASE BIONIC_CHECK_HEAD='HEAD~1' bash "$CHECK" "$LIST" 2>&1)"; RC=$?
expect_status "(v) …and BIONIC_CHECK_HEAD=HEAD~1 reads the agreeing tree and passes" 0 "$RC"

section "§REFUSE — no list path, and a pair that cannot be read, are one-line refusals"

R="$TMP/refuse"; fx_repo "$R" 2.3.4 2.3.4
OUT="$(cd "$R" && env -u BIONIC_CHECK_BASE -u BIONIC_CHECK_HEAD bash "$CHECK" 2>&1)"; RC=$?
expect_ne "(a) no list path: non-zero" "0" "$RC"
expect_eq "(a) …in one line" "1" "$(lines_of "$OUT")"
run_check "$R" "$TMP/lists/does-not-exist.list"
expect_ne "(b) a list path that is not there: non-zero" "0" "$RC"
expect_eq "(b) …in one line" "1" "$(lines_of "$OUT")"

R="$TMP/nohead"; fx_repo "$R" 2.3.4 2.3.4
printf '# Changelog\n\nno release heading here\n' > "$R/CHANGELOG.md"; git -C "$R" commit -q -am "no heading"
run_check "$R"
expect_ne "(c) a CHANGELOG with no release heading: non-zero" "0" "$RC"
expect_eq "(c) …in one line" "1" "$(lines_of "$OUT")"

R="$TMP/nover"; fx_repo "$R" 2.3.4 2.3.4
printf '{ "name": "fixture" }\n' > "$R/payload/.claude-plugin/plugin.json"; git -C "$R" commit -q -am "no version"
run_check "$R"
expect_ne "(d) a plugin.json with no version: non-zero" "0" "$RC"
expect_eq "(d) …in one line" "1" "$(lines_of "$OUT")"

section "§SCAN — the name scan still runs under the release check"

R="$TMP/scan"; fx_repo "$R" 2.3.4 2.3.4
run_check "$R"
expect_status "(e) setup: the clean repository passes" 0 "$RC"
printf 'a line holding %s in the middle\n' "$ENTRY" > "$R/b.txt"; git -C "$R" add -A; git -C "$R" commit -q -m "plant"
run_check "$R"
expect_status "(e) a listed entry planted in a committed file: the check fails" 1 "$RC"
expect_contains "(e) …and the scan's hit line is in the output" "HIT entry=1" "$OUT"
expect_absent "(e) …and the entry itself is never printed" "$ENTRY" "$OUT"

section "§STRIKE — the 1.17.0 block against the strike list of ten (AC-6.1, AC-6.2, AC-1.5)"

# THE GRAMMAR. A Known limit is a bullet that begins `- Known limit` (a 1.16.0 bullet carried as it
# stood) or `- (<n>) Known limit` (one of the ten, numbered as AC-6.1 numbers them). A struck one
# reads `, struck:` after the words and cites a record file in backticks (.md, .log or .tsv). A
# carried one of the ten reads `, carried:` and gives its reason with the word "because". Every
# bullet that is not struck is counted, and the count is stated as `<n> here, against <m>`.
CL="${BIONIC_SCRIPTS_DIR}/CHANGELOG.md"
# The first words of each of the ten, as the 1.16.0 block writes them (one phrase per limit)
TEN_1="outside bypass mode, a runner in another language"
TEN_2="under a cgroup CPU quota the gate's room is right"
TEN_3="the tick's backstop \`deliver\` against an unread ruling is untested"
TEN_4="two asks of the person still open no owed item"
TEN_5="\`ruling-ack\` run with no agent identity"
TEN_6="the RC5 deadline in dispatch-preflight-4"
TEN_7="\`ready\` runs the installed plugin's \`line.sh\`"
TEN_8="\`tests/timing.tsv\` holds the seconds of one whole run"
TEN_9="a writer's suite asks the gate per suite"
TEN_10="the 15-minute target for a whole run is missed"

# cl_bullets <file> <version> — one line per bullet of the <version> block; continuation lines are
# joined and whitespace is squeezed, so a wrapped bullet compares as one line
cl_bullets() {
  awk -v v="$2" '
    function flush() { if (b != "") { gsub(/[ \t]+/, " ", b); print b; b = "" } }
    /^## / { flush(); inb = (index($0, "## " v " ") == 1); next }
    !inb { next }
    /^- / { flush(); b = $0; next }
    /^[ \t]+[^ \t]/ { if (b != "") b = b " " $0; next }
    { flush() }
    END { flush() }
  ' "$1"
}
# cl_unstruck — the Known limit bullets on stdin that are not struck
cl_unstruck() {
  grep -E '^- (\([0-9]+\) )?Known limit' | grep -v -E '^- (\([0-9]+\) )?Known limit, struck'
}
# cl_has <phrase> — the number of lines on stdin holding the fixed phrase
cl_has() { grep -c -F -- "$1"; }

# strike_check <file> — one `strike:` line per broken rule; no output when the block keeps them all
strike_check() {
  local f="$1" b16 b17 u16 u17 n i phrase item line stated stated_here stated_old actual16 actual17 hit
  b16="$(cl_bullets "$f" 1.16.0)"; b17="$(cl_bullets "$f" 1.17.0)"
  u16="$(printf '%s\n' "$b16" | cl_unstruck)"; u17="$(printf '%s\n' "$b17" | cl_unstruck)"
  [ -n "$b17" ] || { echo "strike: no 1.17.0 block with bullets"; return 0; }
  i=1
  while [ "$i" -le 10 ]; do
    item="$(printf '%s\n' "$b17" | grep -E "^- \($i\) Known limit" || true)"
    n="$(printf '%s' "$item" | grep -c . || true)"
    if [ "$n" != 1 ]; then
      echo "strike: ($i) is on $n bullets of the 1.17.0 block, not one"
    else
      case "$item" in
        "- ($i) Known limit, struck:"*)
          printf '%s' "$item" | grep -q -E '`[^`]*\.(md|log|tsv)(:[0-9]+)?`' ||
            echo "strike: ($i) is struck and cites no record" ;;
        "- ($i) Known limit, carried:"*)
          printf '%s' "$item" | grep -q -F 'because' ||
            echo "strike: ($i) is carried and says no reason (because)" ;;
        *) echo "strike: ($i) is neither struck nor carried" ;;
      esac
    fi
    i=$((i + 1))
  done
  # every other unstruck 1.16.0 bullet is carried as it stood
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    hit=0; i=1
    while [ "$i" -le 10 ]; do
      eval "phrase=\$TEN_$i"
      case "$line" in *"$phrase"*) hit=1 ;; esac
      i=$((i + 1))
    done
    [ "$hit" = 1 ] && continue
    printf '%s\n' "$b17" | grep -q -F -x -- "$line" ||
      echo "strike: a 1.16.0 bullet vanished: ${line:0:70}"
  done < <(printf '%s\n' "$u16")
  # the count is stated beside 1.16.0's, and both are the bullets counted
  actual16="$(printf '%s\n' "$u16" | grep -c . || true)"
  actual17="$(printf '%s\n' "$u17" | grep -c . || true)"
  stated="$(awk -v v=1.17.0 '/^## / { inb = (index($0, "## " v " ") == 1); next } inb' "$f" | tr '\n' ' ' |
    sed -n 's/.*count is the `- Known limit` bullets that are not struck: \([0-9][0-9]*\) here, against \([0-9][0-9]*\).*/\1 \2/p')"
  if [ -z "$stated" ]; then
    echo "strike: the count of unstruck bullets is not stated beside 1.16.0's"
  else
    stated_here="${stated% *}"; stated_old="${stated#* }"
    [ "$stated_here" = "$actual17" ] || echo "strike: the count says $stated_here and the block holds $actual17"
    [ "$stated_old" = "$actual16" ] || echo "strike: the count says 1.16.0 had $stated_old and its block holds $actual16"
  fi
  # AC-1.5: the narrowed limit names the residual and no launcher
  item="$(printf '%s\n' "$b17" | grep -E '^- \(1\) Known limit' || true)"
  printf '%s' "$item" | grep -q -F "outside the writer's own tree asks as main" ||
    echo "strike: (1) does not say a suite started outside the writer's own tree asks as main"
  if printf '%s' "$item" | grep -q -i -E 'python|node|awk'; then
    echo "strike: (1) still names a launcher"
  fi
  return 0
}

# --- the extractors are not vacuous: they find what the rules are about
B16="$(cl_bullets "$CL" 1.16.0 | cl_unstruck)"
expect_eq "(s0) the 1.16.0 block holds 20 unstruck Known limit bullets" "20" "$(printf '%s\n' "$B16" | grep -c .)"
i=1
while [ "$i" -le 10 ]; do
  eval "phrase=\$TEN_$i"
  expect_eq "(s0) the 1.16.0 block names limit ($i) on exactly one unstruck bullet" "1" "$(printf '%s\n' "$B16" | cl_has "$phrase")"
  i=$((i + 1))
done
B17="$(cl_bullets "$CL" 1.17.0)"
expect_nonempty "(s1) the 1.17.0 block has bullets" "$B17"
i=1
while [ "$i" -le 10 ]; do
  expect_eq "(s1) the 1.17.0 block holds limit ($i) on one bullet" "1" "$(printf '%s\n' "$B17" | grep -c -E "^- \($i\) Known limit")"
  i=$((i + 1))
done

# --- the repository's own block keeps every rule
OUT="$(strike_check "$CL")"
expect_eq "(s2) the repository's CHANGELOG keeps all ten, the carried bullets and the count" "" "$OUT"

# --- doctored copies: each rule has one that goes red, named by its rule
# drop_bullet <regex> — stdin without the 1.17.0 bullet that begins <regex> (its wrapped lines too)
drop_bullet() {
  RE="$1" awk '
    /^## / { in17 = (index($0, "## 1.17.0 ") == 1) }
    skip && /^[ \t]+[^ \t]/ { next }
    { skip = 0 }
    in17 && $0 ~ ENVIRON["RE"] { skip = 1; next }
    { print }
  '
}
# edit_bullet <regex> <awk statement on $0> — the statement applied to the 1.17.0 bullet that begins <regex> and its wrapped lines
edit_bullet() {
  RE="$1" awk '
    /^## / { in17 = (index($0, "## 1.17.0 ") == 1) }
    inb && /^[ \t]+[^ \t]/ { '"$2"'; print; next }
    { inb = 0 }
    in17 && $0 ~ ENVIRON["RE"] { inb = 1; '"$2"' }
    { print }
  '
}
# doctor <name> <command…> — the CHANGELOG through <command>, to \$TMP/doctored.<name>, proved different
doctor() {
  local name="$1"; shift
  "$@" < "$CL" > "$TMP/doctored.$name"
  expect_false "(s3) setup: the $name copy differs from the CHANGELOG" cmp -s "$CL" "$TMP/doctored.$name"
}

doctor drop4 drop_bullet '^- \(4\) Known limit'
expect_contains "(s3a) a block without limit (4): red, naming (4)" "strike: (4) is on 0 bullets" "$(strike_check "$TMP/doctored.drop4")"

doctor nocite edit_bullet '^- \(3\) Known limit' 'gsub(/`[^`]*\.(md|log|tsv)(:[0-9]+)?`/, "X")'
expect_contains "(s3b) a struck limit that cites no record: red, naming (3)" "strike: (3) is struck and cites no record" "$(strike_check "$TMP/doctored.nocite")"

doctor noreason edit_bullet '^- \(10\) Known limit' 'gsub(/because/, "since")'
expect_contains "(s3c) a carried limit that says no reason: red, naming (10)" "strike: (10) is carried and says no reason" "$(strike_check "$TMP/doctored.noreason")"

doctor vanish drop_bullet '^- Known limit: Linux was not used'
expect_contains "(s3d) a dropped 1.16.0 bullet: red, as vanished" "strike: a 1.16.0 bullet vanished: - Known limit: Linux was not used" "$(strike_check "$TMP/doctored.vanish")"
expect_contains "(s3d) …and the stated count no longer equals the bullets counted" "strike: the count says" "$(strike_check "$TMP/doctored.vanish")"

doctor oldcount perl -0777 -pe 's/(not struck:\s+\d+ here, against )20/${1}18/'
expect_contains "(s3e) a count stated against the wrong 1.16.0 figure: red" "strike: the count says 1.16.0 had 18 and its block holds 20" "$(strike_check "$TMP/doctored.oldcount")"

doctor nocount sed 's/count is the `- Known limit` bullets/count is the bullets/'
expect_contains "(s3f) a block with no stated count: red" "strike: the count of unstruck bullets is not stated" "$(strike_check "$TMP/doctored.nocount")"

doctor launcher edit_bullet '^- \(1\) Known limit' 'sub(/outside the writer/, "outside the writer (python, node, awk)")'
expect_contains "(s3g) the narrowed limit naming a launcher again: red" "strike: (1) still names a launcher" "$(strike_check "$TMP/doctored.launcher")"

doctor blur edit_bullet '^- \(2\) Known limit, struck' 'sub(/Known limit, struck/, "Known limit")'
expect_contains "(s3h) a limit neither struck nor carried: red, naming (2)" "strike: (2) is neither struck nor carried" "$(strike_check "$TMP/doctored.blur")"

finish
