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
#   §ENTRY-1.18.0   the 1.18.0 block against wave-35's REQ-9 (AC-9.2) and REQ-3 (AC-3.2): the block
#                   is byte-for-byte as released (wave-36 AC-8.4: it is corrected in the 1.19.0 entry,
#                   never edited); the catalogue table has one row for each of the twelve items and
#                   the three "also" items, each citing a record; the floor rule, the pass removal's
#                   why, the deleted timed cases and the correction of the 1.17.0 default line are each
#                   named; the stated count of Known limits equals the bullets counted; and the 1.17.0
#                   block is byte-for-byte as released; the also-3 cell carries a verdict, not "pending
#                   T17". Each rule has a doctored copy that goes red, except the newest-heading rule.
#   §CORR           the 1.19.0 entry against wave-36's REQ-8 and REQ-9 (AC-8.1, AC-8.3, AC-8.4, AC-9.1,
#                   AC-9.2): the block exists at its own heading, dated; the Corrections
#                   section names the two refusals 1.18.0 introduced, the text-only floor arm, D22's two
#                   deferred sentences and the corrected fix count; Known limits carries every `deferred:`
#                   stated sentence of the bound plan; Migration names every row that added a refusal; every
#                   build row names its record; the 1.18.0 block is as released; help.md and version.md
#                   read the version and `render.sh --check` is green. Each rule has a doctored copy.
#   §ADR            ADR-053's front-matter status is Superseded and names ADR-054, ADR-054's is Accepted
#                   (wave-35 AC-3.2) and names ADR-056 as its amendment, ADR-055 and ADR-056 are Accepted
#                   (wave-36 D14), read from the docs tree when its files exist. With none of them the
#                   section prints one skipped line and passes. A doctored copy of each goes red.
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
# The 1.18.0 block as released: its cksum at 3287c6a7, the commit before wave-36 (AC-8.4: the 1.19.0 entry
# corrects it and the block itself is never edited).
BLOCK_1180_CKSUM="2015167781 19033"
# The catalogue's rows by their first cell: items 1 to 12 of the charter and its three "also" items
ENTRY_ROWS="1 2 3 4 5 6 7 8 9 10 11 12 also-1 also-2 also-3"

# entry_check <file> — one `entry:` line per broken rule; no output when the block keeps them all
entry_check() {
  local f="$1" blk row n stated actual
  blk="$(cl_block "$f" 1.18.0)"
  [ -n "$blk" ] || { echo "entry: no 1.18.0 block"; return 0; }
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
  printf '%s\n' "$blk" | grep -q -E 'pending T[0-9]' && echo "entry: the 1.18.0 block still carries a pending T marker"
  for n in T31 T32 T33 T34; do
    # the bullet "- <n> (…" runs to the next bullet or heading; its record is a `<n>-….md` name
    printf '%s\n' "$blk" | awk -v n="$n" '
      /^- |^#/ { f = (index($0, "- " n " (") == 1) }
      f && index($0, "`" n "-") && /\.md`/ { ok = 1 }
      END { exit !ok }' || echo "entry: the fix row $n names no record"
  done
  [ "$(cl_block "$f" 1.17.0 | cl_cksum)" = "$BLOCK_1170_CKSUM" ] ||
    echo "entry: the 1.17.0 block is not as released"
  [ "$(cl_block "$f" 1.18.0 | cl_cksum)" = "$BLOCK_1180_CKSUM" ] ||
    echo "entry: the 1.18.0 block is not as released"
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
doctor edit1180 awk '{ print } /^## 1\.18\.0 — /{ print "" }'
expect_contains "(e2h) a touched 1.18.0 block: red" "entry: the 1.18.0 block is not as released" "$(entry_check "$TMP/doctored.edit1180")"
doctor oldfirst sed 's/^## 1\.18\.0 — /## 1.17.9 — /'
expect_contains "(e2i) a block whose heading is not 1.18.0: red, no 1.18.0 block" "entry: no 1.18.0 block" "$(entry_check "$TMP/doctored.oldfirst")"

doctor stale3 sed '/^| also-3 |/s/T28/pending T17/g'
expect_contains "(e2j) an also-3 cell that reads pending T17 again: red" "entry: catalogue item also-3 still reads pending T17" "$(entry_check "$TMP/doctored.stale3")"
doctor nofix3 sed '/^| also-3 |/s/T29/T2x/g'
expect_contains "(e2k) an also-3 cell that does not name T29: red" "entry: catalogue item also-3 does not name its fix T29" "$(entry_check "$TMP/doctored.nofix3")"
doctor pend sed 's/^- T33 (.*$/- T33, `pending T33`: the continuation merge./'
expect_contains "(e2l) a fix row that reads pending T33 again: red" "entry: the 1.18.0 block still carries a pending T marker" "$(entry_check "$TMP/doctored.pend")"
doctor norec sed 's/`T32-floor-run-dirty\.md`/the record/g'
expect_contains "(e2m) a fix row T32 that names no record: red" "entry: the fix row T32 names no record" "$(entry_check "$TMP/doctored.norec")"
expect_eq "(e2m) …and the fix-row pattern finds T32 once, so (e1) read a real row" "1" "$(cl_block "$CL" 1.18.0 | grep -c -E '^- T32 \(')"
expect_eq "(e2k) …and the also-3 row pattern finds the cell once, so (e1) read a real row" "1" "$(cl_block "$CL" 1.18.0 | grep -c -E '^\| also-3 \|')"

section "§CORR — the 1.19.0 entry names the run and corrects 1.18.0 (REQ-8 AC-8.1, AC-8.3, AC-8.4; REQ-9 AC-9.1, AC-9.2)"

PLAN_36="${BIONIC_SCRIPTS_DIR}/.bionic/docs/plans/epic-23-bionic-tech-debt/wave-36-zero-machine-errors.plan.md"
PLUGIN_JSON="${BIONIC_SCRIPTS_DIR}/payload/.claude-plugin/plugin.json"
# Every landed build row of the run and the record that proves it; the entry names each record
ROWS_1190="T1:T1-run-on-branch.md T2:T2-restart-truth.md T3:T3-placement.md T4:T4-jurisdiction.md
T5:T5-reads-index.md T6:T6-pinned-text.md T7:T7-cover-judge.md T8:T8-fixed-move.md T9:T9-run-sessions.md
T10:T10-closure-and-markers.md T11:T11-gate-lifecycle.md T12:T12-branch-reads.md T13:T13-debt-grammar.md
T14:T14-close-out-state.md T15:T15-doctrine.md T24:T24-block-heading.md T25:T25-callers.md
T27:T27-consumers.md T28:T28-verbs-ask-the-judge.md T29:T29-launch-arm-and-adopt.md
T30:T30-start-hook-bash5.md T31:T31-fix-seen-by-asker.md T32:T32-one-width-fact.md T33:T33-said-no-pipe.md
T34:T34-taking-lock-stale.md T35:T35-floor-is-a-fact.md T36:T36-stop-wall-pins.md T37:T37-shell-lint-reds.md
T38:T38-one-roster-reader.md T39:T39-sp2-pins.md T40:T40-tick-asks-once.md T41:T41-task-set-files.md
T42:T42-born-floor-backed.md T43:T43-two-cd-chain.md T44:T44-walk-pointer.md T47:T47-adopt-lands-on-whole.md"
# The rows that added a refusal; the Migration paragraph names each (AC-9.2)
MIG_ROWS="T4 T7 T8 T13 T14 T25 T27 T31 T32 T35 T42"
# D22's two deferred sentences, as wave-35's continuation states them and 1.18.0's Known limits omitted them
D22_A='`task-add --born` still admits a finding the person moved to defer when its reader'"'"'s rating is inside the fix policy; the guard reads a move to fix, not a move to defer.'
D22_B='a dead session'"'"'s open row whose files are already sweepable still holds its plan row, and the refusal'"'"'s remedy (`adopt`) lists nothing for that session; `session-poker.sh sweep` clears it.'
# The text-only floor arm's sentence (A-orch-50)
TEXT_ONLY='from Step 7 the commit wall refuses a plan that claims a regression and carries no `proved: kind=floor` line, and it reads text only, so a floor line that owes suites passes it and the judge holds them at `current 7` and `current 8`.'

# cl_part <file> <version> <heading> — the lines of the block's `### <heading>` part, up to the next `### ` or `## `
cl_part() {
  awk -v v="$2" -v h="### $3" '
    /^## / { inb = (index($0, "## " v " ") == 1); inp = 0; next }
    !inb { next }
    /^### / { inp = (index($0, h) == 1); next }
    inp' "$1"
}
# cl_lead <file> <version> — the block's lines before its first `### ` part (lead and Migration)
cl_lead() {
  awk -v v="$2" '
    /^## / { inb = (index($0, "## " v " ") == 1); inp = 0; if (inb) print; next }
    !inb { next }
    /^### / { inp = 1 }
    !inp' "$1"
}
# flat — stdin on one line, white space squeezed, so a wrapped sentence compares as written
flat() { tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g'; }
# has <text> <phrase> — 0 when the phrase is in the text, white space squeezed on both sides
has() { local t p; t="$(printf '%s' "$1" | flat)"; p="$(printf '%s' "$2" | flat)"; case "$t" in *"$p"*) return 0 ;; esac; return 1; }
# plan_deferred — the stated sentence of each `deferred:` line of the bound plan, one per line
plan_deferred() { sed -n 's/^deferred: .* stated="\(.*\)"[[:space:]]*$/\1/p' "$1"; }

# corr_check <file> <plugin.json> <plan> — one `corr:` line per broken rule; no output when all hold
corr_check() {
  local f="$1" pj="$2" plan="$3" blk cor lim mig lead s n pair row rec cnt stated actual t13 t13hit
  blk="$(cl_block "$f" 1.19.0)"
  [ -n "$blk" ] || { echo "corr: no 1.19.0 block"; return 0; }
  printf '%s\n' "$blk" | grep -q -E '^## 1\.19\.0 — 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]$' || echo "corr: the 1.19.0 heading carries no date"
  lead="$(cl_lead "$f" 1.19.0)"
  for s in 'zero machine errors' 'D7' 'D14'; do
    has "$lead" "$s" || echo "corr: the lead does not name $s"
  done
  mig="$(printf '%s\n' "$lead" | awk '/^\*\*Migration\.\*\*/ { m = 1 } m')"
  [ -n "$mig" ] || echo "corr: no Migration paragraph"
  for s in $MIG_ROWS; do
    printf '%s\n' "$mig" | grep -q -w -- "$s" || echo "corr: Migration does not name $s"
  done
  # T13's bullet names the refusal of the two verbs that apply the debt grammar to a carried line (D14; AC-9.2)
  t13="$(printf '%s\n' "$mig" | awk '/^- T13:/ { p = 1; print; next } p && /^- / { p = 0 } p')"
  t13hit="$(printf '%s\n' "$t13" | flat | awk '{ n = split($0, a, /\. /); for (i = 1; i <= n; i++) print a[i] }' \
    | grep -F -- 'debt adopt' | grep -F -- 'Step-1 card' | grep -F -- 'refuse' | grep -F -- 'prose site' \
    | grep -F -- 'unlisted kind' | grep -F -- '1.18.0' || true)"
  [ -n "$t13hit" ] || echo "corr: the T13 Migration bullet does not say debt adopt and the Step-1 card refuse a prose site or an unlisted kind"
  cor="$(cl_part "$f" 1.19.0 'Corrections to 1.18.0')"
  [ -n "$cor" ] || echo "corr: no Corrections to 1.18.0 section"
  has "$cor" '`T31-verify-gate.md`' && has "$cor" 'no floor proof line' || echo "corr: Corrections does not name T31's floor-proof refusal"
  has "$cor" '`T32-floor-run-dirty.md`' && has "$cor" 'dirty checkout' || echo "corr: Corrections does not name T32's dirty-checkout refusal"
  has "$cor" 'A-orch-50' && has "$cor" 'text-only' || echo "corr: Corrections does not name the text-only floor arm"
  has "$cor" 'D22' || echo "corr: Corrections does not name D22's two deferred sentences"
  has "$cor" 'three fixes' && has "$cor" 'T34' && has "$cor" 'A-orch-48' || echo "corr: Corrections does not correct the count of fixes the review ordered"
  lim="$(cl_part "$f" 1.19.0 'Known limits')"
  [ -n "$lim" ] || echo "corr: no Known limits section"
  has "$lim" "$TEXT_ONLY" || echo "corr: Known limits does not carry the text-only floor arm"
  has "$lim" "$D22_A" || echo "corr: Known limits does not carry D22's first deferred sentence"
  has "$lim" "$D22_B" || echo "corr: Known limits does not carry D22's second deferred sentence"
  if [ -r "$plan" ]; then
    cnt=0
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      cnt=$((cnt + 1))
      has "$lim" "$s" || echo "corr: Known limits lacks the deferred sentence: $s"
    done <<EOT
$(plan_deferred "$plan")
EOT
    [ "$cnt" -gt 0 ] || echo "corr: the plan holds no deferred sentence to pin"
  fi
  stated="$(printf '%s\n' "$lim" | flat | sed -n 's/.*The count of Known limits in this block is \([0-9][0-9]*\)\..*/\1/p')"
  actual="$(printf '%s\n' "$lim" | grep -c -E '^- Known limit' || true)"
  if [ -z "$stated" ]; then echo "corr: the count of Known limits is not stated"
  elif [ "$stated" != "$actual" ]; then echo "corr: the count says $stated and Known limits holds $actual"; fi
  for pair in $ROWS_1190; do
    row="${pair%%:*}"; rec="${pair#*:}"
    printf '%s\n' "$blk" | grep -q -F -- '`'"$rec"'`' || echo "corr: the entry names no record for $row ($rec)"
  done
  has "$blk" 'T33, T36, T37, T38, T39 and T40' && has "$blk" '`born: floor`' || echo "corr: the entry does not name the six rows born: floor"
  [ "$(cl_block "$f" 1.18.0 | cl_cksum)" = "$BLOCK_1180_CKSUM" ] || echo "corr: the 1.18.0 block is not as released"
  return 0
}
# pair_check <file> <plugin.json> — one `corr:` line when plugin.json does not read the newest heading (the live pair,
# whichever release is newest; the 1.19.0 rules above hold that block at its own heading)
pair_check() {
  local ver pv
  ver="$(grep -m 1 '^## ' "$1" | sed -n 's/^## \([0-9.]*\) .*/\1/p')"
  pv="$(jq -r '.version // empty' "$2" 2>/dev/null)"
  [ -n "$ver" ] && [ "$pv" = "$ver" ] || echo "corr: plugin.json reads ${pv:-nothing}, not the newest heading ${ver:-none}"
}
# help_check — the rendered pages read the plugin's version and are the pages render.sh renders
help_check() {
  local ver pg
  ver="$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)"
  for pg in help version; do
    grep -q -F -- "bionic $ver (installed)" "${BIONIC_SCRIPTS_DIR}/payload/commands/$pg.md" || echo "corr: payload/commands/$pg.md does not read bionic $ver (installed)"
  done
  bash "${BIONIC_SCRIPTS_DIR}/agents-src/render.sh" --check >/dev/null 2>&1 || echo "corr: render.sh --check is not green"
}

# --- the extractors are not vacuous
expect_nonempty "(c0) the 1.19.0 block is found" "$(cl_block "$CL" 1.19.0)"
expect_nonempty "(c0) …and its Corrections part" "$(cl_part "$CL" 1.19.0 'Corrections to 1.18.0')"
expect_nonempty "(c0) …and its Known limits part" "$(cl_part "$CL" 1.19.0 'Known limits')"
expect_nonempty "(c0) …and its Migration paragraph" "$(cl_lead "$CL" 1.19.0 | awk '/^\*\*Migration\.\*\*/ { m = 1 } m')"
expect_eq "(c0) …and the 1.18.0 block is the pinned one" "$BLOCK_1180_CKSUM" "$(cl_block "$CL" 1.18.0 | cl_cksum)"
if [ -r "$PLAN_36" ]; then
  expect_eq "(c0) the bound plan's deferred lines each yield a stated sentence" "$(grep -c '^deferred: ' "$PLAN_36")" "$(plan_deferred "$PLAN_36" | grep -c .)"
  expect_nonempty "(c0) …and the plan holds at least one" "$(plan_deferred "$PLAN_36")"
else
  ok "(c0) skipped: no plan file at $PLAN_36, so the deferred sentences are not pinned"
fi
expect_eq "(c0) the table of build rows holds 36 rows" "36" "$(printf '%s\n' $ROWS_1190 | grep -c .)"

# --- the repository's own entry keeps every rule
expect_eq "(c1) the repository's 1.19.0 entry keeps every rule" "" "$(corr_check "$CL" "$PLUGIN_JSON" "$PLAN_36")"
expect_eq "(c1) …and the rendered pages read plugin.json's version and are the rendered pages" "" "$(help_check)"
expect_nonempty "(c1) …and the newest CHANGELOG heading is found" "$(grep -m 1 '^## ' "$CL" | sed -n 's/^## \([0-9.]*\) .*/\1/p')"
expect_eq "(c1) …and plugin.json reads the newest CHANGELOG heading (AC-9.1, AC-10.1)" "" "$(pair_check "$CL" "$PLUGIN_JSON")"

# --- doctored copies: each rule has one that goes red, named by its rule
cor_check() { corr_check "$1" "$PLUGIN_JSON" "$PLAN_36"; }
doctor c_no119 sed 's/^## 1\.19\.0 — /## 1.18.9 — /'
expect_contains "(c2a) no 1.19.0 block: red" "corr: no 1.19.0 block" "$(cor_check "$TMP/doctored.c_no119")"
doctor c_nocor sed 's/^### Corrections to 1\.18\.0/### Notes/'
expect_contains "(c2b) a block with no Corrections section: red" "corr: no Corrections to 1.18.0 section" "$(cor_check "$TMP/doctored.c_nocor")"
doctor c_t31 sed 's/T31-verify-gate\.md/the-record/g'
expect_contains "(c2c) Corrections that does not name T31's refusal record: red" "corr: Corrections does not name T31's floor-proof refusal" "$(cor_check "$TMP/doctored.c_t31")"
doctor c_t32 perl -0pe 's/dirty\s+checkout/dirty tree/g'
expect_contains "(c2d) Corrections that does not say dirty checkout: red" "corr: Corrections does not name T32's dirty-checkout refusal" "$(cor_check "$TMP/doctored.c_t32")"
doctor c_textonly sed 's/text-only/wall-only/g'
expect_contains "(c2e) Corrections that does not say text-only: red" "corr: Corrections does not name the text-only floor arm" "$(cor_check "$TMP/doctored.c_textonly")"
doctor c_d22 sed 's/D22/D2x/g'
expect_contains "(c2f) Corrections that does not name D22: red" "corr: Corrections does not name D22's two deferred sentences" "$(cor_check "$TMP/doctored.c_d22")"
doctor c_count sed 's/three fixes/four fixes/g'
expect_contains "(c2g) a fix count left at four: red" "corr: Corrections does not correct the count of fixes the review ordered" "$(cor_check "$TMP/doctored.c_count")"
doctor c_d22a sed 's/still admits a finding the person moved to defer/admits a finding/'
expect_contains "(c2h) Known limits without D22's first sentence: red" "corr: Known limits does not carry D22's first deferred sentence" "$(cor_check "$TMP/doctored.c_d22a")"
doctor c_d22b sed 's/lists nothing for that session/lists nothing/'
expect_contains "(c2i) Known limits without D22's second sentence: red" "corr: Known limits does not carry D22's second deferred sentence" "$(cor_check "$TMP/doctored.c_d22b")"
doctor c_floorarm sed 's/it reads text only/it reads the tree/'
expect_contains "(c2j) Known limits without the text-only arm: red" "corr: Known limits does not carry the text-only floor arm" "$(cor_check "$TMP/doctored.c_floorarm")"
if [ -r "$PLAN_36" ]; then
  FIRST_DEFERRED="$(plan_deferred "$PLAN_36" | head -n 1)"
  expect_nonempty "(c2k) setup: the first deferred sentence was read" "$FIRST_DEFERRED"
  doctor c_deferred env FD="$FIRST_DEFERRED" perl -pe 'BEGIN { $s = $ENV{FD} } $i = index($_, substr($s, 0, 30)); substr($_, $i, 30) = "X" x 30 if $i >= 0'
  expect_contains "(c2k) Known limits that lost a deferred sentence: red, naming it" "corr: Known limits lacks the deferred sentence: $FIRST_DEFERRED" "$(cor_check "$TMP/doctored.c_deferred")"
fi
doctor c_klcount sed 's/The count of Known limits in this block is [0-9]*\./The count of Known limits in this block is 99./'
expect_contains "(c2l) a stated count that is not the bullets counted: red" "corr: the count says 99" "$(cor_check "$TMP/doctored.c_klcount")"
doctor c_klnone sed 's/The count of Known limits in this block is/The Known limits here number/'
expect_contains "(c2m) no stated count: red" "corr: the count of Known limits is not stated" "$(cor_check "$TMP/doctored.c_klnone")"
doctor c_mig awk '/^\*\*Migration\.\*\*/ { m = 1 } m && /^### / { m = 0 } m { gsub(/T35/, "Tnn") } { print }'
expect_contains "(c2n) a Migration paragraph that does not name T35: red" "corr: Migration does not name T35" "$(cor_check "$TMP/doctored.c_mig")"
doctor c_t13 sed 's/`debt adopt` and the Step-1 card now refuse/the card now refuses/'
expect_contains "(c2n2) a T13 bullet that does not name debt adopt and the Step-1 card refusal: red" "corr: the T13 Migration bullet does not say debt adopt and the Step-1 card refuse" "$(cor_check "$TMP/doctored.c_t13")"
doctor c_rec sed 's/`T27-consumers\.md`/the record/g'
expect_contains "(c2o) a build row with no record named: red" "corr: the entry names no record for T27" "$(cor_check "$TMP/doctored.c_rec")"
doctor c_born sed 's/T33, T36, T37, T38, T39 and T40/the six rows/'
expect_contains "(c2p) the born: floor rows not named: red" "corr: the entry does not name the six rows born: floor" "$(cor_check "$TMP/doctored.c_born")"
doctor c_edit1180 awk '{ print } /^## 1\.18\.0 — /{ print "" }'
expect_contains "(c2q) a touched 1.18.0 block: red" "corr: the 1.18.0 block is not as released" "$(cor_check "$TMP/doctored.c_edit1180")"
printf '{\n  "name": "bionic",\n  "version": "1.18.0"\n}\n' > "$TMP/plugin.old.json"
expect_contains "(c2r) a plugin.json that still reads 1.18.0: red, naming both versions" "corr: plugin.json reads 1.18.0, not the newest heading $(grep -m 1 '^## ' "$CL" | sed -n 's/^## \([0-9.]*\) .*/\1/p')" "$(pair_check "$CL" "$TMP/plugin.old.json")"
doctor c_nodate sed 's/^## 1\.19\.0 — .*/## 1.19.0 —/'
expect_contains "(c2s) a 1.19.0 heading with no date: red" "corr: the 1.19.0 heading carries no date" "$(cor_check "$TMP/doctored.c_nodate")"

section "§ADR — ADR-053 is Superseded naming ADR-054, ADR-054 is Accepted and amended by ADR-056, ADR-055 and ADR-056 are Accepted (AC-3.2; wave-36 D14)"

ADR_DIR="${BIONIC_ADR_DIR:-${BIONIC_SCRIPTS_DIR}/.bionic/docs/adrs/epic-23-bionic-tech-debt}"
# adr_status <file> — the front matter's `status:` line, nothing from the body
adr_status() { awk 'NR == 1 && $0 == "---" { fm = 1; next } fm && $0 == "---" { exit } fm && /^status:/ { print; exit }' "$1"; }
# adr_check <dir> — one `adr:` line per broken rule; a directory with neither file prints one `skipped:` line
adr_check() {
  local d="$1" f53 f54 f55 f56 s53 s54 s55 s56
  f53="$(ls "$d"/adr-053-*.md 2>/dev/null | head -n 1)"
  f54="$(ls "$d"/adr-054-*.md 2>/dev/null | head -n 1)"
  f55="$(ls "$d"/adr-055-*.md 2>/dev/null | head -n 1)"
  f56="$(ls "$d"/adr-056-*.md 2>/dev/null | head -n 1)"
  if [ -z "$f53" ] && [ -z "$f54" ] && [ -z "$f55" ] && [ -z "$f56" ]; then
    echo "skipped: no ADR files at $d"
    return 0
  fi
  [ -n "$f53" ] || echo "adr: no ADR-053 file at $d"
  [ -n "$f54" ] || echo "adr: no ADR-054 file at $d"
  [ -n "$f55" ] || echo "adr: no ADR-055 file at $d"
  [ -n "$f56" ] || echo "adr: no ADR-056 file at $d"
  if [ -n "$f53" ]; then
    s53="$(adr_status "$f53")"
    case "$s53" in "status: Superseded"*) ;; *) echo "adr: ADR-053's status is not Superseded: ${s53:-(no status line)}" ;; esac
    case "$s53" in *[Aa][Dd][Rr]-054*) ;; *) echo "adr: ADR-053's status does not name ADR-054: ${s53:-(no status line)}" ;; esac
  fi
  if [ -n "$f54" ]; then
    s54="$(adr_status "$f54")"
    case "$s54" in "status: Accepted"*) ;; *) echo "adr: ADR-054's status is not Accepted: ${s54:-(no status line)}" ;; esac
    case "$s54" in *[Aa][Dd][Rr]-056*) ;; *) echo "adr: ADR-054's status does not name ADR-056 as its amendment: ${s54:-(no status line)}" ;; esac
  fi
  if [ -n "$f55" ]; then
    s55="$(adr_status "$f55")"
    case "$s55" in "status: Accepted"*) ;; *) echo "adr: ADR-055's status is not Accepted: ${s55:-(no status line)}" ;; esac
  fi
  if [ -n "$f56" ]; then
    s56="$(adr_status "$f56")"
    case "$s56" in "status: Accepted"*) ;; *) echo "adr: ADR-056's status is not Accepted: ${s56:-(no status line)}" ;; esac
  fi
  return 0
}

# fx_adr <file> <status line> — an ADR whose front matter carries <status line>, the body a Status paragraph
fx_adr() {
  printf -- '---\nwave: wave-35-no-workarounds\n%s\ncreated: 2026-10-11\n---\n# ADR\n\n## Status\n\n**Accepted** in the body, which no rule reads.\n' "$2" > "$1"
}
S53='status: Superseded (Step 7, 2026-10-12, 1.18.0) by adr-054-the-floor-is-one-whole-run-plus-the-greens-of-what-changed.md'
S54='status: Accepted (Step 7, 2026-10-12, 1.18.0), amended by adr-056-cover-is-a-fact-of-the-tree.md (Step 7, 2026-10-14, 1.19.0)'
S55='status: Accepted (Step 7, 2026-10-14, 1.19.0)'
# adr_world <dir> <053 status> <054 status> [<055 status> [<056 status>]] — a directory holding the four fixture ADRs
adr_world() {
  mkdir -p "$1" && fx_adr "$1/adr-053-background-work-takes-only-spare-capacity.md" "$2" &&
  fx_adr "$1/adr-054-the-floor-is-one-whole-run-plus-the-greens-of-what-changed.md" "$3" &&
  fx_adr "$1/adr-055-a-run-is-governed-by-its-launch.md" "${4:-$S55}" &&
  fx_adr "$1/adr-056-cover-is-a-fact-of-the-tree.md" "${5:-$S55}"
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
adr_world "$TMP/adr-n56" "$S53" 'status: Accepted (Step 7, 2026-10-12, 1.18.0)'
expect_contains "(a4g) ADR-054 Accepted and not naming ADR-056: red" "adr: ADR-054's status does not name ADR-056 as its amendment" "$(adr_check "$TMP/adr-n56")"
adr_world "$TMP/adr-p55" "$S53" "$S54" 'status: Proposed (Step 2, 2026-10-13, 1.19.0)'
expect_contains "(a4h) ADR-055 reading Proposed: red, not Accepted" "adr: ADR-055's status is not Accepted" "$(adr_check "$TMP/adr-p55")"
adr_world "$TMP/adr-p56" "$S53" "$S54" "$S55" 'status: Proposed (Step 2, 2026-10-13, 1.19.0)'
expect_contains "(a4i) ADR-056 reading Proposed: red, not Accepted" "adr: ADR-056's status is not Accepted" "$(adr_check "$TMP/adr-p56")"
adr_world "$TMP/adr-no55" "$S53" "$S54"; rm "$TMP/adr-no55"/adr-055-*.md
expect_contains "(a4j) ADR-055's file absent beside the others: red, named" "adr: no ADR-055 file at $TMP/adr-no55" "$(adr_check "$TMP/adr-no55")"

section "§REL-1.20.0 — the 1.20.0 entry names each landed row's record, the landing numbers and the Known limits (wave-37 AC-10.1, AC-10.2, AC-1.4)"

# Every landed build row of wave 37 and the record that proves it; the entry names each
ROWS_1200="T1:T1-landing-drain.md T2:T2-dry-copy-slug.md T3:T3-map-rules.md T4:T4-run-line.md T5:T5-words-witness.md
T6:T6-brief-artifact.md T7:T7-list-fields.md T8:T8-basis-line.md T9:T9-report-split.md T18:T18-decline-reopens.md
T19:T19-bounded-ready.md"

# rel_check <file> — one `rel:` line per broken rule; no output when all hold
rel_check() {
  local f="$1" blk lim land pair row rec s
  blk="$(cl_block "$f" 1.20.0)"
  [ -n "$blk" ] || { echo "rel: no 1.20.0 block"; return 0; }
  printf '%s\n' "$blk" | grep -q -E '^## 1\.20\.0 — 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]$' || echo "rel: the 1.20.0 heading carries no date"
  for pair in $ROWS_1200; do
    row="${pair%%:*}"; rec="${pair#*:}"
    printf '%s\n' "$blk" | grep -q -F -- '`'"$rec"'`' || echo "rel: the entry names no record for $row ($rec)"
  done
  for s in D3 D4 D5 D6 D7 D8 D9 D10 D11 D12 D13; do
    printf '%s\n' "$blk" | grep -q -E "^### .*\($s[,)]" || echo "rel: no section for $s"
  done
  has "$blk" 'timing.tsv' && has "$blk" 'no suite was split' || echo "rel: the entry does not cite timing.tsv with no suite split (AC-1.4)"
  land="$(cl_part "$f" 1.20.0 'The landing numbers')"
  [ -n "$land" ] || echo "rel: no landing numbers section"
  has "$land" 'median=' && has "$land" 'wait=' && has "$land" 'prove=' && has "$land" 'width=' || echo "rel: the landing numbers carry no median, wait, prove and width"
  has "$land" '29.4' && has "$land" '107.4' && has "$land" '170.8' || echo "rel: the landing numbers do not stand beside wave 36's"
  lim="$(cl_part "$f" 1.20.0 'Known limits')"
  [ -n "$lim" ] || echo "rel: no Known limits section"
  has "$blk" '**Migration.**' || echo "rel: no Migration paragraph"
}
expect_nonempty "(r0) the 1.20.0 block is found" "$(cl_block "$CL" 1.20.0)"
expect_nonempty "(r0) …and its landing numbers part" "$(cl_part "$CL" 1.20.0 'The landing numbers')"
expect_nonempty "(r0) …and its Known limits part" "$(cl_part "$CL" 1.20.0 'Known limits')"
expect_eq "(r1) the repository's 1.20.0 entry keeps every rule" "" "$(rel_check "$CL")"
doctor r_norec sed 's/`T18-decline-reopens\.md`/the record/g'
expect_contains "(r2a) a row with no record named: red" "rel: the entry names no record for T18" "$(rel_check "$TMP/doctored.r_norec")"
doctor r_nolim sed 's/^### Known limits$/### Notes/'
expect_contains "(r2b) no Known limits section: red" "rel: no Known limits section" "$(rel_check "$TMP/doctored.r_nolim")"
doctor r_nonum sed 's/^### The landing numbers$/### Numbers/'
expect_contains "(r2c) no landing numbers section: red" "rel: no landing numbers section" "$(rel_check "$TMP/doctored.r_nonum")"
doctor r_nowave36 sed 's/170\.8 m/gone/'
expect_contains "(r2d) a landing table with no wave 36 max: red" "rel: the landing numbers do not stand beside wave 36's" "$(rel_check "$TMP/doctored.r_nowave36")"
doctor r_nod7 sed 's/^### The landing record holds the run (D7, ADR-057)$/### The run/'
expect_contains "(r2e) no D7 section: red" "rel: no section for D7" "$(rel_check "$TMP/doctored.r_nod7")"
doctor r_nodate sed 's/^## 1\.20\.0 — .*/## 1.20.0 —/'
expect_contains "(r2f) a 1.20.0 heading with no date: red" "rel: the 1.20.0 heading carries no date" "$(rel_check "$TMP/doctored.r_nodate")"

finish
