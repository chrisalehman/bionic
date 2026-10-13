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
#   §ENTRY-1.18.0   the 1.18.0 block against wave-35's REQ-9 (AC-9.2) and REQ-3 (AC-3.2): the newest
#                   heading is 1.18.0; the catalogue table has one row for each of the twelve items and
#                   the three "also" items, each citing a record; the floor rule, the pass removal's
#                   why, the deleted timed cases and the correction of the 1.17.0 default line are each
#                   named; the stated count of Known limits equals the bullets counted; and the 1.17.0
#                   block is byte-for-byte as released; the also-3 cell carries a verdict, not "pending
#                   T17". Each rule has a doctored copy that goes red, except the newest-heading rule.
#   §ADR            ADR-053's front-matter status is Superseded and names ADR-054, ADR-054's is Accepted
#                   (wave-35 AC-3.2), read from the docs tree when its two files exist. With neither
#                   file the section prints one skipped line and passes. A doctored copy of each goes red.
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

section "§ENTRY-1.18.0 — the 1.18.0 block names each fix (REQ-9 AC-9.2, REQ-3 AC-3.2)"

# cl_block <file> <version> — the block's lines, heading included, up to the next `## ` heading
cl_block() {
  awk -v v="$2" '/^## / { inb = (index($0, "## " v " ") == 1) } inb' "$1"
}
# cl_cksum — the cksum of stdin, trailing blanks trimmed
cl_cksum() { cksum | sed 's/[[:space:]]*$//'; }
# The 1.17.0 block as released: its cksum at c83de86d, the commit before this wave. A deliberate later
# edit of that block updates this pair; an accidental one goes red.
BLOCK_1170_CKSUM="1817012127 27102"
# The catalogue's rows by their first cell: items 1 to 12 of the charter and its three "also" items
ENTRY_ROWS="1 2 3 4 5 6 7 8 9 10 11 12 also-1 also-2 also-3"

# entry_check <file> — one `entry:` line per broken rule; no output when the block keeps them all
entry_check() {
  local f="$1" blk row n stated actual
  blk="$(cl_block "$f" 1.18.0)"
  [ -n "$blk" ] || { echo "entry: no 1.18.0 block"; return 0; }
  [ "$(grep -m 1 '^## ' "$f" | sed -n 's/^## \([0-9.]*\) .*/\1/p')" = "1.18.0" ] ||
    echo "entry: the newest heading is not 1.18.0"
  for row in $ENTRY_ROWS; do
    n="$(printf '%s\n' "$blk" | grep -c -E "^\| $row \|" || true)"
    if [ "$n" != 1 ]; then
      echo "entry: catalogue item $row is on $n rows, not one"
    else
      printf '%s\n' "$blk" | grep -E "^\| $row \|" | grep -q -E '`[A-Za-z0-9._-]+\.(md|log)(:[0-9]+)?`' ||
        echo "entry: catalogue item $row cites no record"
    fi
  done
  for row in 'proof-add inherited' 'approve regression-2' 'current 7' 'floor-run'; do
    printf '%s\n' "$blk" | grep -q -F -- "$row" || echo "entry: the floor rule does not name $row"
  done
  for row in 'ADR-053' 'ADR-054' 'Superseded' 'T16-pass-measure.md'; do
    printf '%s\n' "$blk" | grep -q -F -- "$row" || echo "entry: the pass removal does not name $row"
  done
  for row in 'hook-timeout a1, a2, b, c and g' 'session-start 16.8 and 16.2'; do
    printf '%s\n' "$blk" | grep -q -F -- "$row" || echo "entry: the deleted timed cases do not name $row"
  done
  printf '%s\n' "$blk" | grep -q -F 'the 1.17.0 block'"'"'s `background-pass` default line' ||
    echo "entry: the 1.17.0 background-pass default line is not corrected"
  stated="$(printf '%s\n' "$blk" | tr '\n' ' ' | sed -n 's/.*The count of Known limits in this block is \([0-9][0-9]*\)\..*/\1/p')"
  actual="$(printf '%s\n' "$blk" | grep -c -E '^- Known limit' || true)"
  if [ -z "$stated" ]; then
    echo "entry: the count of Known limits is not stated"
  elif [ "$stated" != "$actual" ]; then
    echo "entry: the count says $stated and the block holds $actual"
  fi
  row="$(printf '%s\n' "$blk" | grep -E '^\| also-3 \|' || true)"
  case "$row" in *'pending T17'*) echo "entry: catalogue item also-3 still reads pending T17" ;; esac
  for n in T28 T29; do
    case "$row" in *"$n"*) ;; *) echo "entry: catalogue item also-3 does not name its fix $n" ;; esac
  done
  [ "$(cl_block "$f" 1.17.0 | cl_cksum)" = "$BLOCK_1170_CKSUM" ] ||
    echo "entry: the 1.17.0 block is not as released"
  return 0
}

# --- the extractors are not vacuous: the 1.17.0 block is found and is the pinned one
expect_nonempty "(e0) the 1.17.0 block is found" "$(cl_block "$CL" 1.17.0)"
expect_eq "(e0) …and its cksum is the pinned one" "$BLOCK_1170_CKSUM" "$(cl_block "$CL" 1.17.0 | cl_cksum)"

# --- the repository's own block keeps every rule
OUT="$(entry_check "$CL")"
expect_eq "(e1) the repository's CHANGELOG keeps every rule of the 1.18.0 entry" "" "$OUT"
expect_eq "(e1) …and the catalogue row pattern finds item 1 once, so (e1) read a real table" "1" "$(cl_block "$CL" 1.18.0 | grep -c -E '^\| 1 \|')"

# --- doctored copies: each rule has one that goes red, named by its rule
doctor dropitem sed '/^| 7 |/d'
expect_contains "(e2a) a catalogue without item 7: red, naming 7" "entry: catalogue item 7 is on 0 rows" "$(entry_check "$TMP/doctored.dropitem")"
doctor norecord sed '/^| 4 |/s/`[A-Za-z0-9._-]*\.md`/X/g'
expect_contains "(e2b) a catalogue row that cites no record: red, naming 4" "entry: catalogue item 4 cites no record" "$(entry_check "$TMP/doctored.norecord")"
doctor nofloor sed 's/approve regression-2/approve something/g'
expect_contains "(e2c) a floor rule that does not name approve regression-2: red" "entry: the floor rule does not name approve regression-2" "$(entry_check "$TMP/doctored.nofloor")"
doctor nowhy sed 's/T16-pass-measure\.md/the-measure/g'
expect_contains "(e2d) a pass removal that cites no measurement: red" "entry: the pass removal does not name T16-pass-measure.md" "$(entry_check "$TMP/doctored.nowhy")"
doctor nocases sed 's/session-start 16\.8 and 16\.2/session-start cases/g'
expect_contains "(e2e) deleted timed cases not named: red" "entry: the deleted timed cases do not name session-start 16.8 and 16.2" "$(entry_check "$TMP/doctored.nocases")"
doctor nocount sed 's/The count of Known limits in this block is/The Known limits here number/'
expect_contains "(e2f) a block with no stated count: red" "entry: the count of Known limits is not stated" "$(entry_check "$TMP/doctored.nocount")"
doctor wrongcount sed 's/The count of Known limits in this block is [0-9]*\./The count of Known limits in this block is 99./'
expect_contains "(e2g) a stated count that is not the bullets counted: red" "entry: the count says 99" "$(entry_check "$TMP/doctored.wrongcount")"
doctor edit1170 awk '{ print } /^## 1\.17\.0 — /{ print "" }'
expect_contains "(e2h) a touched 1.17.0 block: red" "entry: the 1.17.0 block is not as released" "$(entry_check "$TMP/doctored.edit1170")"
doctor oldfirst sed 's/^## 1\.18\.0 — /## 1.17.9 — /'
expect_contains "(e2i) a block whose heading is not 1.18.0: red, no 1.18.0 block" "entry: no 1.18.0 block" "$(entry_check "$TMP/doctored.oldfirst")"

doctor stale3 sed '/^| also-3 |/s/T28/pending T17/g'
expect_contains "(e2j) an also-3 cell that reads pending T17 again: red" "entry: catalogue item also-3 still reads pending T17" "$(entry_check "$TMP/doctored.stale3")"
doctor nofix3 sed '/^| also-3 |/s/T29/T2x/g'
expect_contains "(e2k) an also-3 cell that does not name T29: red" "entry: catalogue item also-3 does not name its fix T29" "$(entry_check "$TMP/doctored.nofix3")"
expect_eq "(e2k) …and the also-3 row pattern finds the cell once, so (e1) read a real row" "1" "$(cl_block "$CL" 1.18.0 | grep -c -E '^\| also-3 \|')"

section "§ADR — ADR-053 is Superseded naming ADR-054 and ADR-054 is Accepted (AC-3.2)"

ADR_DIR="${BIONIC_ADR_DIR:-${BIONIC_SCRIPTS_DIR}/.bionic/docs/adrs/epic-23-bionic-tech-debt}"
# adr_status <file> — the front matter's `status:` line, nothing from the body
adr_status() { awk 'NR == 1 && $0 == "---" { fm = 1; next } fm && $0 == "---" { exit } fm && /^status:/ { print; exit }' "$1"; }
# adr_check <dir> — one `adr:` line per broken rule; a directory with neither file prints one `skipped:` line
adr_check() {
  local d="$1" f53 f54 s53 s54
  f53="$(ls "$d"/adr-053-*.md 2>/dev/null | head -n 1)"
  f54="$(ls "$d"/adr-054-*.md 2>/dev/null | head -n 1)"
  if [ -z "$f53" ] && [ -z "$f54" ]; then
    echo "skipped: no ADR files at $d"
    return 0
  fi
  [ -n "$f53" ] || echo "adr: no ADR-053 file at $d"
  [ -n "$f54" ] || echo "adr: no ADR-054 file at $d"
  if [ -n "$f53" ]; then
    s53="$(adr_status "$f53")"
    case "$s53" in "status: Superseded"*) ;; *) echo "adr: ADR-053's status is not Superseded: ${s53:-(no status line)}" ;; esac
    case "$s53" in *[Aa][Dd][Rr]-054*) ;; *) echo "adr: ADR-053's status does not name ADR-054: ${s53:-(no status line)}" ;; esac
  fi
  if [ -n "$f54" ]; then
    s54="$(adr_status "$f54")"
    case "$s54" in "status: Accepted"*) ;; *) echo "adr: ADR-054's status is not Accepted: ${s54:-(no status line)}" ;; esac
  fi
  return 0
}

# fx_adr <file> <status line> — an ADR whose front matter carries <status line>, the body a Status paragraph
fx_adr() {
  printf -- '---\nwave: wave-35-no-workarounds\n%s\ncreated: 2026-10-11\n---\n# ADR\n\n## Status\n\n**Accepted** in the body, which no rule reads.\n' "$2" > "$1"
}
S53='status: Superseded (Step 7, 2026-10-12, 1.18.0) by adr-054-the-floor-is-one-whole-run-plus-the-greens-of-what-changed.md'
S54='status: Accepted (Step 7, 2026-10-12, 1.18.0)'
# adr_world <dir> <053 status> <054 status> — a directory holding the two fixture ADRs
adr_world() {
  mkdir -p "$1" && fx_adr "$1/adr-053-background-work-takes-only-spare-capacity.md" "$2" &&
  fx_adr "$1/adr-054-the-floor-is-one-whole-run-plus-the-greens-of-what-changed.md" "$3"
}

# --- the extractor is not vacuous: it returns the status line of a fixture, front matter only
adr_world "$TMP/adr-ok" "$S53" "$S54"
expect_eq "(a0) the extractor returns ADR-053's front-matter status line, not the body" "$S53" "$(adr_status "$TMP/adr-ok"/adr-053-*.md)"
expect_eq "(a0) …and ADR-054's" "$S54" "$(adr_status "$TMP/adr-ok"/adr-054-*.md)"

# --- the fixture pair keeps every rule; the repository's own pair does when its files exist
expect_eq "(a1) a pair of Superseded-naming-ADR-054 and Accepted: no line" "" "$(adr_check "$TMP/adr-ok")"
OUT="$(adr_check "$ADR_DIR")"
case "$OUT" in
  skipped:*) ok "(a2) $OUT" ;;
  *) expect_eq "(a2) the repository's ADR-053 and ADR-054 keep every rule" "" "$OUT"
     expect_nonempty "(a2) …and the repository's ADR-053 status line was read" "$(adr_status "$ADR_DIR"/adr-053-*.md)" ;;
esac

# --- no ADR file in the directory: one skipped line, and the section passes
mkdir -p "$TMP/adr-none"
OUT="$(adr_check "$TMP/adr-none")"
expect_eq "(a3) a directory with neither ADR file: the one skipped line" "skipped: no ADR files at $TMP/adr-none" "$OUT"
expect_eq "(a3) …and only one line" "1" "$(printf '%s\n' "$OUT" | grep -c .)"

# --- doctored copies: each rule has one that goes red, named by its rule
adr_world "$TMP/adr-a53" 'status: Accepted (Step 7, 2026-10-12, 1.18.0)' "$S54"
expect_contains "(a4a) ADR-053 reading Accepted: red, not Superseded" "adr: ADR-053's status is not Superseded" "$(adr_check "$TMP/adr-a53")"
adr_world "$TMP/adr-n53" 'status: Superseded (Step 7, 2026-10-12, 1.18.0)' "$S54"
expect_contains "(a4b) ADR-053 Superseded and naming no ADR-054: red" "adr: ADR-053's status does not name ADR-054" "$(adr_check "$TMP/adr-n53")"
adr_world "$TMP/adr-p54" "$S53" 'status: Proposed'
expect_contains "(a4c) ADR-054 reading Proposed: red, not Accepted" "adr: ADR-054's status is not Accepted" "$(adr_check "$TMP/adr-p54")"
adr_world "$TMP/adr-s54" "$S53" 'status: Superseded (Step 7) by adr-055-x.md'
expect_contains "(a4d) ADR-054 reading Superseded: red, not Accepted" "adr: ADR-054's status is not Accepted" "$(adr_check "$TMP/adr-s54")"
adr_world "$TMP/adr-half" "$S53" "$S54"; rm "$TMP/adr-half"/adr-054-*.md
expect_contains "(a4e) ADR-054's file absent beside ADR-053's: red, named" "adr: no ADR-054 file at $TMP/adr-half" "$(adr_check "$TMP/adr-half")"
adr_world "$TMP/adr-body" "$S53" "$S54"; sed -i.bak 's/^status:.*//' "$TMP/adr-body"/adr-054-*.md; rm -f "$TMP/adr-body"/*.bak
expect_contains "(a4f) ADR-054 with no status line in its front matter: red" "adr: ADR-054's status is not Accepted" "$(adr_check "$TMP/adr-body")"

finish
