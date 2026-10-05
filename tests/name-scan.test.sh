#!/bin/bash
# Tests for tests/lib/name-scan.sh — this project's name scan (wave-27 T3; spec D13,
# AC-6.3, AC-6.4, AC-6.5).
#
# THE SCAN READS WHAT A PUSH WOULD PUBLISH: the files as committed at the head, the commit
# messages in base..head, and the message of an annotated tag at the head. Three sections:
#
#   §PUB    a string planted in a committed file, a commit message or an annotated tag is a
#           hit; one in the dirty working tree only is not read (AC-6.3).
#   §POWER  a list inside any checkout and a missing list are refused, an empty list passes
#           as none, and a clean result requires every entry found in the throwaway commit
#           by the same functions (AC-6.4).
#   §QUIET  on a hit and on a clean run, neither the output nor the record holds any entry
#           (AC-6.5).
#   §PATH   a committed file or directory whose path holds an entry is a hit, named by its
#           position, never by the path (T32 finding 1).
#   §BASE   at a head that carries the newest tag the default base is the tag before it
#           (T32 finding 2).
#   §LIST   a list line is stripped of edge blanks, a CR and a BOM before use (T32 finding 3).
#   §TRACE  an inherited GIT_TRACE* file never receives an entry (T32 finding 4).
#   §BASH32 the whole scan under /bin/bash (3.2) prints the lines the PATH bash prints.
#   §ARGV   no entry is a word of any command line, and git config tracing records none.
#
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"): every
# repository is a real `git init` under a mktemp directory, with real commits, real
# lightweight and annotated tags and a real dirty working tree — nothing is a mock of git.
# The one seam is a `git` shim on PATH that execs the real git and swallows ONE subcommand's
# output; it exists to make a scan site blind on purpose, so the power check has something to
# refuse. The entries are made-up strings; no real list is read. SYNTHESIZED: the strings.
#
# ANTI-VACUITY (declared, per the same file, "Anti-vacuity"): every absence row sits beside a
# positive row on the SAME run and the SAME extractor (the HIT lines of one output); the
# blind-site rows are paired with the same fixture run through a pass-through shim.
#
# Usage: bash tests/name-scan.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

SCAN="${BIONIC_SCRIPTS_DIR}/tests/lib/name-scan.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/name-scan-test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
mkdir -p "$TMP/lists" "$TMP/scratch"

# made-up strings, one per role
E1="zq-alpha-7731"
E2="Quillfeather"
E3="mxv9 plover"
E4="nothere-0000"

setup_section "fixtures"

# the suite's own precondition: the list directory is outside any checkout
expect_false "setup: the list directory is outside every checkout" git -C "$TMP/lists" rev-parse --show-toplevel
[ -r "$SCAN" ] || { echo "FAIL: $SCAN is not readable"; exit 1; }

# fx_repo <dir> — a repository with one commit, tagged v0.1 (lightweight)
fx_repo() {
  mkdir -p "$1" && git -C "$1" init -q --template= && 
  git -C "$1" config commit.gpgsign false && git -C "$1" config tag.gpgsign false &&
  printf 'base\n' > "$1/a.txt" && git -C "$1" add -A && git -C "$1" commit -q -m "first" &&
  git -C "$1" tag v0.1
}
# fx_commit <dir> <message> — commit whatever is staged-able
fx_commit() { git -C "$1" add -A && git -C "$1" commit -q --allow-empty -m "$2"; }
# fx_list <name> <line>... — a list file outside every checkout; prints its path
fx_list() { local f="$TMP/lists/$1"; shift; printf '%s\n' "$@" > "$f"; printf '%s' "$f"; }
# scan <repo> <list> [VAR=val ...] — sets OUT (stdout+stderr) and RC
scan() {
  local repo="$1" list="$2"; shift 2
  OUT="$(cd "$repo" && env -u BIONIC_CHECK_BASE -u BIONIC_CHECK_HEAD "$@" bash "$SCAN" "$list" 2>&1)"; RC=$?
}
hits() { printf '%s\n' "$OUT" | grep '^HIT ' || true; }
# shim <name> <arg> — a git on PATH that swallows every call carrying <arg> as an argument
shim() {
  local d="$TMP/shim-$1"; mkdir -p "$d"
  cat > "$d/git" <<SH
#!/bin/bash
[ -n "\${SHIM_LOG:-}" ] && printf '%s\n' "\$*" >> "\$SHIM_LOG"
for a in "\$@"; do [ "\$a" = "$2" ] && exit \${SHIM_RC:-0}; done
exec $(command -v git) "\$@"
SH
  chmod +x "$d/git"; printf '%s' "$d"
}

section "§PUB — what a push would publish"

# PUB1 a committed file, case-insensitively; the line number is the entry's line in the list
R="$TMP/pub1"; fx_repo "$R"
printf 'x\nsee ZQ-ALPHA-7731 here\n' > "$R/notes.txt"; fx_commit "$R" "add notes"
L="$(fx_list pub1 '# a comment' '' "$E1" "$E4")"
scan "$R" "$L"
expect_status "PUB1: a committed file with an entry exits 1" 1 "$RC"
expect_regex "PUB1: the hit names the entry's line in the list and the file:line" \
  '^HIT entry=3 at file notes\.txt:2$' "$(hits)"
expect_no_regex "PUB1: an entry that is nowhere is not a hit (same output)" 'entry=4' "$(hits)"

# PUB2 a commit message inside base..head, and one before base
R="$TMP/pub2"; fx_repo "$R"
git -C "$R" commit -q --allow-empty -m "old note $E2"
git -C "$R" tag -f v0.2 >/dev/null 2>&1
fx_commit "$R" "later note $E3"
SHA="$(git -C "$R" rev-parse HEAD | cut -c1-12)"
L="$(fx_list pub2 "$E2" "$E3")"
scan "$R" "$L"
expect_status "PUB2: an in-range message exits 1" 1 "$RC"
expect_contains "PUB2: the in-range message is a hit, at its commit" "HIT entry=2 at message $SHA" "$(hits)"
expect_no_regex "PUB2: a message older than the newest tag is not read (same output)" 'entry=1' "$(hits)"

# PUB3 the default base is the newest tag reachable from the head; with no tag, all history
scan "$R" "$L" BIONIC_CHECK_BASE=v0.1
expect_regex "PUB3: an explicit base widens the range, and the older message is a hit" 'entry=1 at message' "$(hits)"
R="$TMP/pub3"; mkdir -p "$R"; git -C "$R" init -q --template=; git -C "$R" config commit.gpgsign false
git -C "$R" commit -q --allow-empty -m "root $E2"
scan "$R" "$(fx_list pub3 "$E2")"
expect_regex "PUB3: with no tag at all, the whole history is in range" 'entry=1 at message' "$(hits)"

# PUB4 an annotated tag at the head, and one elsewhere
R="$TMP/pub4"; fx_repo "$R"
git -C "$R" tag -a v0.1a -m "older $E2" HEAD
fx_commit "$R" "second"
git -C "$R" tag -a v0.2 -m "release $E1"
L="$(fx_list pub4 "$E1" "$E2")"
scan "$R" "$L" BIONIC_CHECK_BASE=v0.1
expect_status "PUB4: an annotated tag at the head exits 1" 1 "$RC"
expect_regex "PUB4: its message is a hit" '^HIT entry=1 at tag-message' "$(hits)"
expect_no_regex "PUB4: a tag message elsewhere is not read (same output)" 'entry=2' "$(hits)"

# PUB5 the dirty working tree is not read
R="$TMP/pub5"; fx_repo "$R"
printf 'committed %s\n' "$E2" > "$R/c.txt"; fx_commit "$R" "add c"
printf 'dirty %s\n' "$E1" >> "$R/a.txt"; printf 'new %s\n' "$E1" > "$R/untracked.txt"
L="$(fx_list pub5 "$E1" "$E2")"
scan "$R" "$L"
expect_regex "PUB5: the committed entry is a hit" '^HIT entry=2 at file c\.txt:1$' "$(hits)"
expect_no_regex "PUB5: an entry only in the working tree is not read (same output)" 'entry=1' "$(hits)"

# PUB6 BIONIC_CHECK_HEAD picks the tree
R="$TMP/pub6"; fx_repo "$R"
printf '%s\n' "$E1" > "$R/b.txt"; fx_commit "$R" "add b"
L="$(fx_list pub6 "$E1")"
scan "$R" "$L"
expect_status "PUB6: at the default head the entry is found" 1 "$RC"
scan "$R" "$L" BIONIC_CHECK_HEAD=HEAD~1
expect_status "PUB6: at the earlier head, whose tree lacks it, the scan is clean" 0 "$RC"

# PUB7 a file it cannot read as text is named, an empty file is not
R="$TMP/pub7"; fx_repo "$R"
printf 'bin\0%s\n' "$E1" > "$R/blob.bin"; : > "$R/empty.txt"; printf '%s\n' "$E2" > "$R/t.txt"
fx_commit "$R" "files"
L="$(fx_list pub7 "$E1" "$E2")"
scan "$R" "$L"
expect_regex "PUB7: the text file's entry is a hit" '^HIT entry=2 at file t\.txt:1$' "$(hits)"
expect_contains "PUB7: the binary file is named as unread" "UNREAD blob.bin" "$OUT"
expect_absent "PUB7: an empty file is not named as unread" "UNREAD empty.txt" "$OUT"
expect_no_regex "PUB7: nothing is claimed about the entry in the binary file" 'entry=1' "$(hits)"

section "§POWER — refusals, none, and a clean result that has power"

R="$TMP/pow1"; fx_repo "$R"
printf '%s\n' "$E1" > "$R/b.txt"; fx_commit "$R" "add b"
# POW1 a list inside the scanned checkout, in its subdirectory, and inside another checkout
printf '%s\n' "$E4" > "$R/list.txt"
scan "$R" "$R/list.txt"
expect_status "POW1: a list in the checkout root is refused" 2 "$RC"
mkdir -p "$R/sub/dir"; printf '%s\n' "$E4" > "$R/sub/dir/list.txt"
scan "$R" "$R/sub/dir/list.txt"
expect_status "POW1: a list in a subdirectory of the checkout is refused" 2 "$RC"
O="$TMP/pow1-other"; fx_repo "$O"; printf '%s\n' "$E4" > "$O/list.txt"
scan "$R" "$O/list.txt"
expect_status "POW1: a list inside any other checkout is refused" 2 "$RC"
scan "$R" "$(fx_list pow1 "$E1")"
expect_status "POW1: the same entry in a list outside every checkout is scanned (control)" 1 "$RC"
# POW2 missing list
scan "$R" "$TMP/lists/does-not-exist"
expect_status "POW2: a missing list is refused" 2 "$RC"
OUT="$(cd "$R" && bash "$SCAN" 2>&1)"; RC=$?
expect_status "POW2: no argument is refused" 2 "$RC"
# POW3 an empty list passes as none
: > "$TMP/lists/empty"
scan "$R" "$TMP/lists/empty"
expect_status "POW3: an empty list exits 0" 0 "$RC"
expect_contains "POW3: and prints entries=0" "entries=0" "$OUT"
scan "$R" "$(fx_list pow3c '# only a comment' '')"
expect_status "POW3: a list of comments and blanks is empty too" 0 "$RC"
scan "$R" "$(fx_list pow3d "$E4" "$E3" "# c")"
expect_contains "POW3: a two-entry list reports entries=2 (control)" "entries=2" "$OUT"
expect_status "POW3: and entries found nowhere in the repository exit 0" 0 "$RC"
# POW4 outside a repository
scan "$TMP/scratch" "$(fx_list pow4 "$E1")"
expect_status "POW4: run outside any repository is refused" 2 "$RC"
# POW5 a blind scan site means no power
L="$(fx_list pow5 "$E4" "$E3")"
PASS_SHIM="$(shim pass "--never-an-argument")"
scan "$R" "$L" PATH="$PASS_SHIM:$PATH"
expect_status "POW5: through a pass-through shim the clean scan exits 0 (control)" 0 "$RC"
GREP_BLIND="$(shim grep grep)"
scan "$R" "$L" PATH="$GREP_BLIND:$PATH" SHIM_RC=1
expect_status "POW5: blind file scan — no power, exit 2, not a clean 0" 2 "$RC"
LOG_BLIND="$(shim log log)"
scan "$R" "$L" PATH="$LOG_BLIND:$PATH"
expect_status "POW5: blind message scan — no power, exit 2" 2 "$RC"
TAG_BLIND="$(shim tag --points-at)"
scan "$R" "$L" PATH="$TAG_BLIND:$PATH"
expect_status "POW5: blind tag scan — no power, exit 2" 2 "$RC"
scan "$R" "$(fx_list pow5b "$E1" "$E4")" PATH="$GREP_BLIND:$PATH" SHIM_RC=1
expect_status "POW5: a hit does not outrank a blind scan — exit 2 (the power check runs first)" 2 "$RC"

section "§PATH — a path name is published too (T32 finding 1)"

# made-up strings for the T32 rows
EP="zq-pathname-5512"
ED="Quilldirname-2204"

# PATH1 a file NAMED after an entry, contents clean: a hit that names the path's position
R="$TMP/path1"; fx_repo "$R"
printf 'plain\n' > "$R/b.txt"; mkdir -p "$R/docs"; printf 'plain\n' > "$R/docs/$EP-notes.md"
printf 'plain\n' > "$R/z.txt"; fx_commit "$R" "add files"
L="$(fx_list path1 "$EP")"
scan "$R" "$L"
WANT="$(git -C "$R" ls-tree -r --name-only HEAD | grep -n -i -F -- "$EP" | cut -d: -f1)"
expect_nonempty "PATH1: the fixture's path sits at a position in tree order (extractor non-empty)" "$WANT"
expect_status "PATH1: a file named after an entry, contents clean, exits 1" 1 "$RC"
expect_eq "PATH1: the hit names the path by its position in git ls-tree order" "HIT entry=1 at path #$WANT" "$(hits)"
expect_absent "PATH1: neither the entry nor the path is in the output" "$EP" "$OUT"
expect_absent "PATH1: nor the path's other half" "notes.md" "$OUT"

# PATH2 a DIRECTORY named after an entry, case-insensitively
R="$TMP/path2"; fx_repo "$R"
mkdir -p "$R/$(printf '%s' "$ED" | tr 'A-Z' 'a-z')/inner"; printf 'plain\n' > "$R/$(printf '%s' "$ED" | tr 'A-Z' 'a-z')/inner/f.txt"
printf 'plain\n' > "$R/other.txt"; fx_commit "$R" "add dir"
L="$(fx_list path2 "$ED" "$EP")"
scan "$R" "$L"
expect_status "PATH2: a directory named after an entry exits 1" 1 "$RC"
expect_regex "PATH2: the hit is the directory's file, entry 1, by position" '^HIT entry=1 at path #[0-9]+$' "$(hits)"
expect_no_regex "PATH2: an entry in no path is not a hit (same output)" 'entry=2' "$(hits)"
expect_absent "PATH2: the directory name is not printed" "inner" "$OUT"

# PATH3 only the committed tree is read: an untracked file named after an entry is not a hit
R="$TMP/path3"; fx_repo "$R"
printf 'plain\n' > "$R/$EP.txt"; fx_commit "$R" "add named"
printf 'plain\n' > "$R/$ED.txt"
L="$(fx_list path3 "$EP" "$ED")"
scan "$R" "$L"
expect_regex "PATH3: the committed path is a hit" '^HIT entry=1 at path #[0-9]+$' "$(hits)"
expect_no_regex "PATH3: a path only in the working tree is not read (same output)" 'entry=2' "$(hits)"

# PATH4 the power check plants an entry in a file NAME; a path scan that cannot find it refuses
R="$TMP/path4"; fx_repo "$R"
L="$(fx_list path4 "$E4" "$E3")"
LS_BLIND="$(shim lstree ls-tree)"
scan "$R" "$L" PATH="$PASS_SHIM:$PATH"
expect_status "PATH4: through a pass-through shim the clean scan exits 0 (control)" 0 "$RC"
scan "$R" "$L" PATH="$LS_BLIND:$PATH"
expect_status "PATH4: blind path scan — no power, exit 2, not a clean 0" 2 "$RC"
expect_contains "PATH4: and the refusal names the paths scan" "the paths scan" "$OUT"

section "§BASE — the default base at a tagged head (T32 finding 2)"

EB="zq-rangemsg-9034"; EO="Quilloldmsg-6618"
# BASE1 head carries the newest tag (annotated) and there is an earlier one: the range is prev..head
R="$TMP/base1"; fx_repo "$R"
git -C "$R" commit -q --allow-empty -m "before the previous tag $EO"
git -C "$R" tag -a v1.9.0 -m "previous"
fx_commit "$R" "inside the release $EB"
fx_commit "$R" "more"
git -C "$R" tag -a v2.0.0 -m "release"
PREV="$(git -C "$R" rev-parse --short=12 'v1.9.0^{commit}')"
SHA="$(git -C "$R" rev-parse HEAD~1 | cut -c1-12)"
L="$(fx_list base1 "$EB" "$EO")"
scan "$R" "$L"
expect_status "BASE1: a message between the previous tag and a tagged head exits 1" 1 "$RC"
expect_contains "BASE1: the in-release message is a hit, at its commit" "HIT entry=1 at message $SHA" "$(hits)"
expect_no_regex "BASE1: a message before the previous tag is not read (same output)" 'entry=2' "$(hits)"
expect_contains "BASE1: the tally's base is the previous tag" "base=$PREV" "$OUT"

# BASE2 a lightweight tag at the head, a lightweight tag before it: the same
R="$TMP/base2"; fx_repo "$R"
fx_commit "$R" "in range $EB"
git -C "$R" tag v0.2
L="$(fx_list base2 "$EB")"
scan "$R" "$L"
expect_status "BASE2: lightweight tags — the message after v0.1 and under a tagged v0.2 head is found" 1 "$RC"

# BASE3 the only tag there is sits at the head: the range is the whole history
R="$TMP/base3"; mkdir -p "$R"; git -C "$R" init -q --template=; git -C "$R" config commit.gpgsign false
git -C "$R" commit -q --allow-empty -m "root $EB"
git -C "$R" commit -q --allow-empty -m "second"
git -C "$R" tag v1.0.0
L="$(fx_list base3 "$EB")"
scan "$R" "$L"
expect_status "BASE3: the only tag at the head — the whole history is read, exit 1" 1 "$RC"
expect_regex "BASE3: the root message is a hit" 'entry=1 at message' "$(hits)"
expect_contains "BASE3: and the tally has no base" "base=none" "$OUT"

# BASE4 two tags at the head: both are skipped, the one before them is the base
R="$TMP/base4"; fx_repo "$R"
fx_commit "$R" "in range $EB"
git -C "$R" tag v0.2; git -C "$R" tag -a v0.2-rc -m "rc"
L="$(fx_list base4 "$EB" "$EO")"
scan "$R" "$L"
expect_regex "BASE4: with two tags at the head the earlier release is the base, the message is a hit" 'entry=1 at message' "$(hits)"
expect_contains "BASE4: base is v0.1's commit" "base=$(git -C "$R" rev-parse --short=12 'v0.1^{commit}')" "$OUT"

# BASE5 BIONIC_CHECK_BASE still wins at a tagged head
R="$TMP/base1"
FIRST="$(git -C "$R" rev-list --max-parents=0 HEAD)"
scan "$R" "$(fx_list base5 "$EO")" BIONIC_CHECK_BASE="$FIRST"
expect_regex "BASE5: an explicit base wider than the previous tag reads the older message" 'entry=1 at message' "$(hits)"
scan "$R" "$(fx_list base5b "$EO")"
expect_status "BASE5: the same entry with the default base is clean (differential)" 0 "$RC"

section "§LIST — a list line is read as the scan will use it (T32 finding 3)"

EL="zq-trail-8821"; EM="mxv9 plover"
R="$TMP/list1"; fx_repo "$R"
printf 'see %s.\nand %s.\n' "$EL" "$EM" > "$R/notes.txt"; fx_commit "$R" "add notes"
# lraw <name> <printf format> — a list file written with printf escapes; prints its path
lraw() { local f="$TMP/lists/$1"; printf "$2" "$EL" > "$f"; printf '%s' "$f"; }
scan "$R" "$(lraw lst0 '%s\n')"
expect_status "LIST: the clean line is a hit (control)" 1 "$RC"
expect_contains "LIST: and counts one entry" "entries=1" "$OUT"
for v in 'trailing space|%s \n' 'trailing tab|%s\t\n' 'trailing spaces and tab|%s \t \n' 'CR LF|%s\r\n' 'trailing space then CR LF|%s \r\n' 'BOM|\357\273\277%s\n' 'BOM and CR LF|\357\273\277%s\r\n' 'no final newline, trailing space|%s '; do
  scan "$R" "$(lraw lstv "${v#*|}")"
  expect_regex "LIST: ${v%%|*} — read as the entry and found" '^HIT entry=1 at file notes\.txt:1$' "$(hits)"
  expect_contains "LIST: ${v%%|*} — one entry" "entries=1" "$OUT"
done
# an entry with an inner space keeps it; a leading space is part of the entry
scan "$R" "$(fx_list lst1 "$EM ")"
expect_regex "LIST: an entry with an inner space and a trailing space is found" '^HIT entry=1 at file notes\.txt:2$' "$(hits)"
EV="zq-lead-3390"
printf 'x%s\n' "$EV" > "$R/lead.txt"; fx_commit "$R" "add lead"
scan "$R" "$(fx_list lst2 " $EV")"
expect_status "LIST: a LEADING space stays part of the entry — no match against 'x<entry>', and the power check passes" 0 "$RC"
expect_contains "LIST: (same run) the entry was read" "entries=1" "$OUT"
printf 'x %s\n' "$EV" > "$R/lead2.txt"; fx_commit "$R" "add lead2"
scan "$R" "$(fx_list lst2b " $EV")"
expect_regex "LIST: and with a file that has the space before it, the entry is a hit" '^HIT entry=1 at file lead2\.txt:1$' "$(hits)"
# blank-after-stripping lines are skipped and still counted
printf ' \n\t\n\r\n%s \n' "$EL" > "$TMP/lists/lst3"
scan "$R" "$TMP/lists/lst3"
expect_regex "LIST: lines blank after stripping are skipped but counted — the entry is line 4" '^HIT entry=4 at file notes\.txt:1$' "$(hits)"
expect_contains "LIST: and they are not entries" "entries=1" "$OUT"
printf ' \n\t\n\r\n\357\273\277\n' > "$TMP/lists/lst4"
scan "$R" "$TMP/lists/lst4"
expect_status "LIST: a list of only blank lines exits 0" 0 "$RC"
expect_contains "LIST: and prints entries=0" "entries=0" "$OUT"
printf '\357\273\277# a comment\n%s\n' "$EL" > "$TMP/lists/lst5"
scan "$R" "$TMP/lists/lst5"
expect_regex "LIST: a comment behind a BOM is skipped and counted — the entry is line 2" '^HIT entry=2 at file notes\.txt:1$' "$(hits)"
expect_contains "LIST: one entry" "entries=1" "$OUT"

section "§TRACE — an inherited git trace file does not record an entry (T32 finding 4)"

R="$TMP/trace1"; fx_repo "$R"
printf '%s\n' "$E1" > "$R/b.txt"; fx_commit "$R" "add b"
L="$(fx_list trace1 "$E1")"
mkdir -p "$TMP/trace"
# control: the trace mechanism records the entry when git is called directly with the variable set
GIT_TRACE="$TMP/trace/ctl" git -C "$R" grep -n -i -F -e "$E1" HEAD >/dev/null 2>&1
expect_true "TRACE: control — a direct git call with GIT_TRACE set records the entry" grep -q -F -- "$E1" "$TMP/trace/ctl"
scan "$R" "$L" GIT_TRACE="$TMP/trace/t1" GIT_TRACE2="$TMP/trace/t2" GIT_TRACE2_EVENT="$TMP/trace/t3" GIT_TRACE2_PERF="$TMP/trace/t4" GIT_TRACE_PACKET="$TMP/trace/t5" GIT_TRACE_SETUP="$TMP/trace/t6"
expect_status "TRACE: the run still finds the hit" 1 "$RC"
expect_regex "TRACE: and prints it (positive on the same run)" '^HIT entry=1 at file b\.txt:1$' "$(hits)"
TRACED="$(cat "$TMP"/trace/t[1-6] 2>/dev/null | grep -c -i -F -- "$E1" || true)"
expect_eq "TRACE: no trace file the run was pointed at holds the entry" "0" "$TRACED"

section "§BASH32 — the whole scan under /bin/bash, the plugin's interpreter (T32 round 2)"

# the suite itself runs under whatever `bash` is first on PATH; the scan is run under /bin/bash
# (3.2 on macOS) and its lines must be the same ones
B1="zq-b32text-2290"; B2="zq-b32dir-4417"; B3="zq-b32msg-6021"; B4="zq-b32tag-1180"
R="$TMP/b32"; fx_repo "$R"
git -C "$R" tag -a v1.9.0 -m "previous"
mkdir -p "$R/$B2"; printf 'plain\n' > "$R/$B2/f.txt"; printf 'see %s.\nmore\n' "$B1" > "$R/notes.txt"
fx_commit "$R" "release $B3"
git -C "$R" tag -a v2.0.0 -m "release $B4"
printf '\357\273\277%s \r\n%s\r\n%s \t\n%s\n' "$B1" "$B2" "$B3" "$B4" > "$TMP/lists/b32"
SHA="$(git -C "$R" rev-parse HEAD | cut -c1-12)"
WANT="$(git -C "$R" ls-tree -r --name-only HEAD | grep -n -i -F -- "$B2" | cut -d: -f1)"
expect_nonempty "BASH32: the fixture's directory path sits at a position in tree order (extractor non-empty)" "$WANT"
scan "$R" "$TMP/lists/b32"
OUT_DEFAULT="$OUT"
expect_status "BASH32: under the PATH bash the fixture is a hit run (control)" 1 "$RC"
if [ -x /bin/bash ]; then
  OUT="$(cd "$R" && env -u BIONIC_CHECK_BASE -u BIONIC_CHECK_HEAD /bin/bash "$SCAN" "$TMP/lists/b32" 2>&1)"; RC=$?
  expect_status "BASH32: /bin/bash — the run exits 1" 1 "$RC"
  expect_eq "BASH32: /bin/bash — a content hit, through a BOM, CR LF and trailing-blank line" "HIT entry=1 at file notes.txt:1" "$(hits | sed -n 1p)"
  expect_contains "BASH32: /bin/bash — a path hit" "HIT entry=2 at path #$WANT" "$(hits)"
  expect_contains "BASH32: /bin/bash — a message hit at a tagged head (range is v1.9.0..head)" "HIT entry=3 at message $SHA" "$(hits)"
  expect_contains "BASH32: /bin/bash — a tag-message hit" "HIT entry=4 at tag-message" "$(hits)"
  expect_contains "BASH32: /bin/bash — four entries read" "entries=4 hits=4" "$OUT"
  expect_eq "BASH32: /bin/bash prints exactly what the PATH bash prints (the whole output)" "$OUT_DEFAULT" "$OUT"
else
  echo "SKIP: /bin/bash is absent on this machine; the BASH32 rows did not run"
fi

section "§ARGV — no list entry is a word of any command line the scan runs (T32 round 2)"

A1="zq-argv-content-3318"; A2="Quillargvpath-7742"; A3="zq-argv-msg-5509"
R="$TMP/argv1"; fx_repo "$R"
mkdir -p "$R/docs"; printf 'plain\n' > "$R/docs/$(printf '%s' "$A2" | tr 'A-Z' 'a-z').md"
printf 'x\nsee %s\n' "$A1" > "$R/c.txt"
fx_commit "$R" "release $A3"
git -C "$R" tag -a v0.2 -m "release $A3"
L="$(fx_list argv1 "$A1" "$A2" "$A3")"
# argv_shim <dir> <log> <tool>... — each tool logs its whole argv, one word a line, then execs the real one
argv_shim() {
  local d="$1" log="$2" n real; shift 2
  mkdir -p "$d"
  for n in "$@"; do
    real="$(type -P "$n")" || continue
    printf '#!/bin/bash\nprintf "%%s\\n" "%s" "$@" >> "%s"\nexec "%s" "$@"\n' "$n" "$log" "$real" > "$d/$n"
    chmod +x "$d/$n"
  done
}
ALOG="$TMP/argv.log"; : > "$ALOG"
argv_shim "$TMP/argv-shim" "$ALOG" git grep awk sed tr cut dirname mktemp rm cat head tail wc sort uniq touch env
# control: the shim records a pattern given the way the old scan gave it
PATH="$TMP/argv-shim:$PATH" git -C "$R" grep -n -F -e "$A1" HEAD >/dev/null 2>&1
expect_true "ARGV: control — the shim log records an entry passed as a word" grep -q -F -- "$A1" "$ALOG"
: > "$ALOG"
scan "$R" "$L"
BASE_OUT="$OUT"
expect_status "ARGV: without the shims the run is a hit run" 1 "$RC"
expect_contains "ARGV: content hit" "HIT entry=1 at file c.txt:2" "$BASE_OUT"
expect_regex "ARGV: path hit" 'HIT entry=2 at path #[0-9]+' "$BASE_OUT"
expect_contains "ARGV: message hit" "HIT entry=3 at message" "$BASE_OUT"
expect_contains "ARGV: tag-message hit" "HIT entry=3 at tag-message" "$BASE_OUT"
scan "$R" "$L" PATH="$TMP/argv-shim:$PATH"
expect_eq "ARGV: through the logging shims the output is unchanged" "$BASE_OUT" "$OUT"
expect_contains "ARGV: the shims saw the scan's git calls (positive on the same log)" "ls-tree" "$(cat "$ALOG")"
expect_contains "ARGV: and its awk calls" "awk" "$(cat "$ALOG")"
for e in "$A1" "$A2" "$A3"; do
  expect_eq "ARGV: the argv log holds no trace of the entry on its list line $(printf '%s\n' "$A1" "$A2" "$A3" | grep -n -F -x -- "$e" | cut -d: -f1)" "0" "$(grep -c -i -F -- "$e" "$ALOG")"
done

# git CONFIG can trace too: trace2.eventTarget records every git argv. Git honours that key only
# from protected config (system, global), so the fixture is a global config file (measured: the
# same key through GIT_CONFIG_COUNT/KEY/VALUE writes nothing).
CT="$TMP/trace/cfg"; rm -f "$CT"
printf '[trace2]\n\teventTarget = %s\n' "$CT" > "$TMP/trace/gitconfig"
GIT_CONFIG_GLOBAL="$TMP/trace/gitconfig" git -C "$R" grep -n -F -e "$A1" HEAD >/dev/null 2>&1
expect_true "ARGV: control — a global-config trace target records an entry passed as a word" grep -q -F -- "$A1" "$CT"
rm -f "$CT"
scan "$R" "$L" GIT_CONFIG_GLOBAL="$TMP/trace/gitconfig"
expect_eq "ARGV: with a config trace target the output is unchanged" "$BASE_OUT" "$OUT"
expect_true "ARGV: the scan's own git calls were traced (positive on the same file)" grep -q -F '"event":"start"' "$CT"
for e in "$A1" "$A2" "$A3"; do
  expect_eq "ARGV: the config trace file holds no trace of entry '${e:0:6}…'" "0" "$(grep -c -i -F -- "$e" "$CT")"
done

section "§QUIET — no entry is printed or recorded"

R="$TMP/q1"; fx_repo "$R"
printf '%s\n' "$E1" > "$R/b.txt"; printf '%s\n' "$E2" > "$R/Quillfeather-notes.txt"
fx_commit "$R" "mention $E3"
printf 'bin\0\n' > "$R/blob.bin"; git -C "$R" add -A; git -C "$R" commit -q -m "bin"
git -C "$R" tag -a v0.2 -m "tag $E4"
L="$(fx_list q1 "$E1" "$E2" "$E3" "$E4" "$E4-clean")"
no_entry() { # <msg> <text> — none of the entries, in any case, occurs in <text>
  local msg="$1" text="$2" e bad=""
  for e in "$E1" "$E2" "$E3" "$E4"; do
    printf '%s' "$text" | grep -q -i -F -- "$e" && bad="$bad|$e"
  done
  expect_empty "$msg" "$bad"
}
SLOG="$TMP/shim.log"; : > "$SLOG"
LOGSHIM="$(shim log --never-an-argument)"
scan "$R" "$L" BIONIC_CHECK_BASE=v0.1 PATH="$LOGSHIM:$PATH" TMPDIR="$TMP/scratch" SHIM_LOG="$SLOG"
expect_status "QUIET1: the hit run exits 1" 1 "$RC"
expect_regex "QUIET1: it prints hit lines (positive on the same output)" '^HIT entry=[0-9]+ at ' "$(hits)"
expect_contains "QUIET1: including a hit in a path that carries an entry, with the path withheld" "HIT entry=2 at file" "$(hits)"
no_entry "QUIET1: nothing printed holds an entry, even where the path itself does" "$OUT"
expect_contains "QUIET1: the throwaway repository was built under TMPDIR (control)" "$TMP/scratch/" "$(cat "$SLOG")"
expect_empty "QUIET1: and nothing is left behind in TMPDIR" "$(ls -A "$TMP/scratch")"
expect_empty "QUIET1: the scanned repository's working tree is unchanged" "$(git -C "$R" status --porcelain)"

R="$TMP/q2"; fx_repo "$R"
L="$(fx_list q2 "$E1" "$E2" "$E3" "$E4")"
scan "$R" "$L" TMPDIR="$TMP/scratch"
expect_status "QUIET2: the clean run exits 0" 0 "$RC"
expect_contains "QUIET2: it prints its tally (positive on the same output)" "entries=4" "$OUT"
no_entry "QUIET2: nothing printed holds an entry" "$OUT"
expect_empty "QUIET2: nothing is left behind in TMPDIR" "$(ls -A "$TMP/scratch")"

scan "$R" "$TMP/lists/nope-$E1"
expect_nonempty "QUIET3: a refusal says something (positive)" "$OUT"
printf '%s\n' "$E1" > "$R/inside.txt"
scan "$R" "$R/inside.txt"
expect_status "QUIET3: the inside-checkout refusal is a refusal" 2 "$RC"
expect_nonempty "QUIET3: it says something (positive)" "$OUT"
no_entry "QUIET3: and the list's contents are not in it" "$OUT"

finish
