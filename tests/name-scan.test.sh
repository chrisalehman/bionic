#!/bin/bash
# Tests for tests/lib/name-scan.sh — this project's name scan (wave-27 T3; spec D13 as amended,
# AC-6.3, AC-6.4, AC-6.5).
#
# THE SCAN READS WHAT A PUSH WOULD PUBLISH: every blob and path at the head, every blob and path
# the range introduces, each range commit's message, author and committer, and every tag that
# points into the range. A hit is located by numbers and object ids only. Sections:
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
#   §LIST   a list line is stripped of edge blanks, a CR and a BOM before use (T32 finding 3,
#           T52 finding 9), and of every Unicode space perl's \s knows (T61 note).
#   §TRACE  an inherited GIT_TRACE* file never receives an entry (T32 finding 4, T52 finding 11).
#   §BASH32 the whole scan under /bin/bash (3.2) prints the lines the PATH bash prints.
#   §ARGV   no entry is a word of any command line, and git config tracing records none.
#   §BYTES  a binary blob, a `-diff`/`binary` file and a symlink's target are read; an object
#           that cannot be read is a refusal (T52 finding 1).
#   §RANGE  a blob or path only inside the range, each commit's author and committer, and every
#           tag name and message pointing into the range are read (T52 finding 2).
#   §SEP    a path or message holding a control byte, a newline, a tab or a colon is read whole,
#           located, and never printed (T52 findings 3, 4).
#   §CASE   a non-ASCII entry is found in any case under any caller's locale, and never printed;
#           no UTF-8 locale with a non-ASCII entry is a refusal (T52 finding 5).
#   §XTRACE `bash -x` on the scan prints no entry (T52 finding 6).
#   §CEIL   the caller's git discovery variables cannot let a list inside a checkout through
#           (T52 finding 10).
#   §SITES  the power check plants every entry at every site; each site blinded on a doctored
#           copy refuses the run (T52, the power check).
#   §COST   one pass for the whole list, and a 500-entry clean scan of this repository inside
#           its time ceiling (T52 finding 13); 20,000 matching lines in one blob inside 5
#           seconds (T56 N8).
#   §WRAP   between two words of an entry: horizontal white space on one line, or ONE line break
#           with white space, at most 24 symbols and at most three tags on each side; never
#           none, never a blank line, never symbols on one line (T56 B1, T61 B1).
#   §PUSHED the objects a push sends: a commit or blob "fixed" by `git replace` is read as the
#           original, and a nested tag's inner message is read (T56 N1, N3).
#   §PERLDB a caller's perl debugger or module variables print no entry, each of the five with
#           a row a copy that keeps it fails (T56 N4, T61 S2).
#   §INERT  the locale pick and the BASH_ENV unset each have a row that fails without them
#           (T56 N6, N7).
#   §SIGNAL TERM and HUP at a random moment leave no temporary tree (T61 note).
#
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"): every
# repository is a real `git init` under a mktemp directory, with real commits, real
# lightweight and annotated tags, real symlinks, binary files and a real dirty working tree —
# nothing is a mock of git. Two seams: a `git` shim on PATH that execs the real git and
# swallows ONE subcommand's output (it makes a scan site blind on purpose, so the power check
# has something to refuse), and a `locale` shim that reports no UTF-8 locale. §SITES and
# §TRACE run doctored COPIES of the scan in a temp directory, never the tracked file. §COST
# reads this repository itself, read-only. The entries are made-up strings; no real list is
# read. SYNTHESIZED: the strings.
#
# ANTI-VACUITY (declared, per the same file, "Anti-vacuity"): every absence row sits beside a
# positive row on the SAME run and the SAME extractor (the HIT lines of one output); the
# blind-site rows are paired with the same fixture run through a pass-through shim or the
# undoctored copy, and every doctored copy is shown to differ from the scan and to parse.
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
# scanx <script> <repo> <list> [VAR=val ...] — sets OUT (stdout+stderr) and RC
scanx() {
  local script="$1" repo="$2" list="$3"; shift 3
  OUT="$(cd "$repo" && env -u BIONIC_CHECK_BASE -u BIONIC_CHECK_HEAD "$@" bash "$script" "$list" 2>&1)"; RC=$?
}
# scan <repo> <list> [VAR=val ...] — the tracked scan
scan() { scanx "$SCAN" "$@"; }
hits() { printf '%s\n' "$OUT" | grep '^HIT ' || true; }
# s12 <repo> <rev> — the first 12 hex digits of an object id
s12() { git -C "$1" rev-parse "$2" | cut -c1-12; }
# pos_of <repo> <substring> — the 1-based position, in `git ls-tree -r -z --name-only HEAD`
# order, of the first path holding <substring> as committed (records split on NUL)
pos_of() {
  local p n=0
  while IFS= read -r -d '' p; do
    n=$((n + 1)); case "$p" in *"$2"*) printf '%s' "$n"; return 0 ;; esac
  done < <(git -C "$1" ls-tree -r -z --name-only HEAD)
}
# count_in <text> <needle> — lines of <text> holding <needle>, case-insensitively
count_in() { printf '%s\n' "$1" | grep -c -i -F -- "$2" || true; }
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
# doctor <name> <from> <to> — a copy of the scan with the first literal <from> replaced by <to>
# (cut and joined by hand: a pattern substitution's replacement keeps its quotes in some bashes);
# prints its path
doctor() { doctor_from "$SCAN" "$@"; }
# doctor_from <source> <name> <from> <to> — the same, from another (already doctored) copy
doctor_from() {
  local f="$TMP/doctored/$2.sh" src; mkdir -p "$TMP/doctored"
  src="$(cat "$1")"; shift
  case "$src" in *"$2"*) src="${src%%"$2"*}$3${src#*"$2"}" ;; esac
  printf '%s\n' "$src" > "$f"; printf '%s' "$f"
}

section "§PUB — what a push would publish"

# PUB1 a committed file, case-insensitively; the line number is the entry's line in the list
R="$TMP/pub1"; fx_repo "$R"
printf 'x\nsee ZQ-ALPHA-7731 here\n' > "$R/notes.txt"; fx_commit "$R" "add notes"
L="$(fx_list pub1 '# a comment' '' "$E1" "$E4")"
scan "$R" "$L"
expect_status "PUB1: a committed file with an entry exits 1" 1 "$RC"
expect_eq "PUB1: the hit names the entry's line in the list and the blob and line" \
  "HIT entry=3 at blob $(s12 "$R" HEAD:notes.txt) line 2" "$(hits)"
expect_no_regex "PUB1: an entry that is nowhere is not a hit (same output)" 'entry=4' "$(hits)"

# PUB2 a commit message inside base..head, and one before base
R="$TMP/pub2"; fx_repo "$R"
git -C "$R" commit -q --allow-empty -m "old note $E2"
git -C "$R" tag -f v0.2 >/dev/null 2>&1
fx_commit "$R" "later note $E3"
SHA="$(s12 "$R" HEAD)"
L="$(fx_list pub2 "$E2" "$E3")"
scan "$R" "$L"
expect_status "PUB2: an in-range message exits 1" 1 "$RC"
expect_contains "PUB2: the in-range message is a hit, at its commit" "HIT entry=2 at commit $SHA message" "$(hits)"
expect_no_regex "PUB2: a message older than the newest tag is not read (same output)" 'entry=1' "$(hits)"

# PUB3 the default base is the newest tag reachable from the head; with no tag, all history
scan "$R" "$L" BIONIC_CHECK_BASE=v0.1
expect_regex "PUB3: an explicit base widens the range, and the older message is a hit" 'entry=1 at commit [0-9a-f]{12} message' "$(hits)"
R="$TMP/pub3"; mkdir -p "$R"; git -C "$R" init -q --template=; git -C "$R" config commit.gpgsign false
git -C "$R" commit -q --allow-empty -m "root $E2"
scan "$R" "$(fx_list pub3 "$E2")"
expect_regex "PUB3: with no tag at all, the whole history is in range" 'entry=1 at commit [0-9a-f]{12} message' "$(hits)"

# PUB4 an annotated tag at the head, and one elsewhere
R="$TMP/pub4"; fx_repo "$R"
git -C "$R" tag -a v0.1a -m "older $E2" HEAD
fx_commit "$R" "second"
git -C "$R" tag -a v0.2 -m "release $E1"
L="$(fx_list pub4 "$E1" "$E2")"
scan "$R" "$L" BIONIC_CHECK_BASE=v0.1
expect_status "PUB4: an annotated tag at the head exits 1" 1 "$RC"
expect_eq "PUB4: its message is a hit, at the tag object" "HIT entry=1 at tag $(s12 "$R" v0.2)" "$(hits)"
expect_no_regex "PUB4: a tag message outside the range is not read (same output)" 'entry=2' "$(hits)"

# PUB5 the dirty working tree is not read
R="$TMP/pub5"; fx_repo "$R"
printf 'committed %s\n' "$E2" > "$R/c.txt"; fx_commit "$R" "add c"
printf 'dirty %s\n' "$E1" >> "$R/a.txt"; printf 'new %s\n' "$E1" > "$R/untracked.txt"
L="$(fx_list pub5 "$E1" "$E2")"
scan "$R" "$L"
expect_eq "PUB5: the committed entry is a hit" "HIT entry=2 at blob $(s12 "$R" HEAD:c.txt) line 1" "$(hits)"
expect_no_regex "PUB5: an entry only in the working tree is not read (same output)" 'entry=1' "$(hits)"

# PUB6 BIONIC_CHECK_HEAD picks the tree
R="$TMP/pub6"; fx_repo "$R"
printf '%s\n' "$E1" > "$R/b.txt"; fx_commit "$R" "add b"
L="$(fx_list pub6 "$E1")"
scan "$R" "$L"
expect_status "PUB6: at the default head the entry is found" 1 "$RC"
scan "$R" "$L" BIONIC_CHECK_HEAD=HEAD~1
expect_status "PUB6: at the earlier head, whose tree lacks it, the scan is clean" 0 "$RC"

# PUB7 a binary file is read like any other, and an empty file is no hit
R="$TMP/pub7"; fx_repo "$R"
printf 'bin\0%s\n' "$E1" > "$R/blob.bin"; : > "$R/empty.txt"; printf '%s\n' "$E2" > "$R/t.txt"
fx_commit "$R" "files"
L="$(fx_list pub7 "$E1" "$E2")"
scan "$R" "$L"
expect_contains "PUB7: the text file's entry is a hit" "HIT entry=2 at blob $(s12 "$R" HEAD:t.txt) line 1" "$(hits)"
expect_contains "PUB7: the binary file's entry is a hit too" "HIT entry=1 at blob $(s12 "$R" HEAD:blob.bin) line 1" "$(hits)"
expect_absent "PUB7: no file is set aside as unread" "UNREAD" "$OUT"
expect_contains "PUB7: (same run) the tally is printed" "entries=2 hits=2" "$OUT"

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
# POW5 a blind git call means no power: each shim swallows one of the scan's git calls
L="$(fx_list pow5 "$E4" "$E3")"
PASS_SHIM="$(shim pass "--never-an-argument")"
scan "$R" "$L" PATH="$PASS_SHIM:$PATH"
expect_status "POW5: through a pass-through shim the clean scan exits 0 (control)" 0 "$RC"
CAT_BLIND="$(shim catfile cat-file)"
scan "$R" "$L" PATH="$CAT_BLIND:$PATH"
expect_status "POW5: blind object reader (cat-file) — exit 2, not a clean 0" 2 "$RC"
LOG_BLIND="$(shim log log)"
scan "$R" "$L" PATH="$LOG_BLIND:$PATH"
expect_status "POW5: blind range path reader (log) — no power, exit 2" 2 "$RC"
REV_BLIND="$(shim revlist rev-list)"
scan "$R" "$L" PATH="$REV_BLIND:$PATH"
expect_status "POW5: blind range object list (rev-list) — no power, exit 2" 2 "$RC"
REF_BLIND="$(shim refs for-each-ref)"
scan "$R" "$L" PATH="$REF_BLIND:$PATH"
expect_status "POW5: blind tag list (for-each-ref) — no power, exit 2" 2 "$RC"
scan "$R" "$(fx_list pow5b "$E1" "$E4")" PATH="$CAT_BLIND:$PATH" SHIM_RC=1
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

# PATH4 the power check plants an entry in a file NAME; a path list that cannot find it refuses
R="$TMP/path4"; fx_repo "$R"
L="$(fx_list path4 "$E4" "$E3")"
LS_BLIND="$(shim lstree --name-only)"
scan "$R" "$L" PATH="$PASS_SHIM:$PATH"
expect_status "PATH4: through a pass-through shim the clean scan exits 0 (control)" 0 "$RC"
scan "$R" "$L" PATH="$LS_BLIND:$PATH"
expect_status "PATH4: blind path list — no power, exit 2, not a clean 0" 2 "$RC"
expect_contains "PATH4: and the refusal names the path name site" "at its path name" "$OUT"

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
SHA="$(s12 "$R" HEAD~1)"
L="$(fx_list base1 "$EB" "$EO")"
scan "$R" "$L"
expect_status "BASE1: a message between the previous tag and a tagged head exits 1" 1 "$RC"
expect_contains "BASE1: the in-release message is a hit, at its commit" "HIT entry=1 at commit $SHA message" "$(hits)"
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
expect_regex "BASE3: the root message is a hit" 'entry=1 at commit [0-9a-f]{12} message' "$(hits)"
expect_contains "BASE3: and the tally has no base" "base=none" "$OUT"

# BASE4 two tags at the head: both are skipped, the one before them is the base
R="$TMP/base4"; fx_repo "$R"
fx_commit "$R" "in range $EB"
git -C "$R" tag v0.2; git -C "$R" tag -a v0.2-rc -m "rc"
L="$(fx_list base4 "$EB" "$EO")"
scan "$R" "$L"
expect_regex "BASE4: with two tags at the head the earlier release is the base, the message is a hit" 'entry=1 at commit [0-9a-f]{12} message' "$(hits)"
expect_contains "BASE4: base is v0.1's commit" "base=$(git -C "$R" rev-parse --short=12 'v0.1^{commit}')" "$OUT"

# BASE5 BIONIC_CHECK_BASE still wins at a tagged head
R="$TMP/base1"
FIRST="$(git -C "$R" rev-list --max-parents=0 HEAD)"
scan "$R" "$(fx_list base5 "$EO")" BIONIC_CHECK_BASE="$FIRST"
expect_regex "BASE5: an explicit base wider than the previous tag reads the older message" 'entry=1 at commit [0-9a-f]{12} message' "$(hits)"
scan "$R" "$(fx_list base5b "$EO")"
expect_status "BASE5: the same entry with the default base is clean (differential)" 0 "$RC"

section "§LIST — a list line is read as the scan will use it (T32 finding 3, T52 finding 9)"

EL="zq-trail-8821"; EM="mxv9 plover"
R="$TMP/list1"; fx_repo "$R"
printf 'see %s.\nand %s.\n' "$EL" "$EM" > "$R/notes.txt"; fx_commit "$R" "add notes"
NB="$(s12 "$R" HEAD:notes.txt)"
# lraw <name> <printf format> — a list file written with printf escapes; prints its path
lraw() { local f="$TMP/lists/$1"; printf "$2" "$EL" > "$f"; printf '%s' "$f"; }
scan "$R" "$(lraw lst0 '%s\n')"
expect_status "LIST: the clean line is a hit (control)" 1 "$RC"
expect_contains "LIST: and counts one entry" "entries=1" "$OUT"
for v in 'trailing space|%s \n' 'trailing tab|%s\t\n' 'trailing spaces and tab|%s \t \n' 'CR LF|%s\r\n' 'trailing space then CR LF|%s \r\n' 'BOM|\357\273\277%s\n' 'BOM and CR LF|\357\273\277%s\r\n' 'no final newline, trailing space|%s ' 'leading spaces|  %s\n' 'leading tab|\t%s\n' 'leading and trailing blanks|  \t%s \t\n'; do
  scan "$R" "$(lraw lstv "${v#*|}")"
  expect_eq "LIST: ${v%%|*} — read as the entry and found" "HIT entry=1 at blob $NB line 1" "$(hits)"
  expect_contains "LIST: ${v%%|*} — one entry" "entries=1" "$OUT"
done
# an entry with an inner space keeps it
scan "$R" "$(fx_list lst1 "$EM ")"
expect_eq "LIST: an entry with an inner space and a trailing space is found" "HIT entry=1 at blob $NB line 2" "$(hits)"
# a LEADING blank is stripped as a trailing one is (T52 finding 9): `<sp><sp>entry` is `entry`
EV="zq-lead-3390"
printf 'x%s\n' "$EV" > "$R/lead.txt"; fx_commit "$R" "add lead"
scan "$R" "$(fx_list lst2 "  $EV")"
expect_status "LIST: a list line with two leading spaces is read as the entry — found inside 'x<entry>'" 1 "$RC"
expect_eq "LIST: (same run) the hit is the file that has no space before it" "HIT entry=1 at blob $(s12 "$R" HEAD:lead.txt) line 1" "$(hits)"
expect_contains "LIST: (same run) one entry" "entries=1" "$OUT"
# blank-after-stripping lines are skipped and still counted
printf ' \n\t\n\r\n%s \n' "$EL" > "$TMP/lists/lst3"
scan "$R" "$TMP/lists/lst3"
expect_eq "LIST: lines blank after stripping are skipped but counted — the entry is line 4" "HIT entry=4 at blob $NB line 1" "$(hits)"
expect_contains "LIST: and they are not entries" "entries=1" "$OUT"
printf ' \n\t\n\r\n\357\273\277\n' > "$TMP/lists/lst4"
scan "$R" "$TMP/lists/lst4"
expect_status "LIST: a list of only blank lines exits 0" 0 "$RC"
expect_contains "LIST: and prints entries=0" "entries=0" "$OUT"
printf '\357\273\277# a comment\n%s\n' "$EL" > "$TMP/lists/lst5"
scan "$R" "$TMP/lists/lst5"
expect_eq "LIST: a comment behind a BOM is skipped and counted — the entry is line 2" "HIT entry=2 at blob $NB line 1" "$(hits)"
expect_contains "LIST: one entry" "entries=1" "$OUT"
# a list line is trimmed of every Unicode space at both ends (T61 note): an entry never begins
# with an empty word, so it is found at the very start of a text
NBSP=$'\302\240'
R="$TMP/list2"; fx_repo "$R"
printf 'mxv9 plover opens this file\n' > "$R/start.txt"; fx_commit "$R" "add start"
SB="$(s12 "$R" HEAD:start.txt)"
scan "$R" "$(fx_list lst6 "${NBSP}mxv9 plover${NBSP}")"
expect_eq "LIST: <NBSP>entry<NBSP> is the entry — found at the very start of a text" "HIT entry=1 at blob $SB line 1" "$(hits)"
expect_contains "LIST: (same run) one entry" "entries=1" "$OUT"
# every character perl's \s matches (but the newline a list line cannot hold), at both ends of
# its own list line: each line is the entry, found at the very start of the text
SPACES="$(perl -CS -Mfeature=unicode_strings -e 'for (0 .. 0x3000) { my $c = chr; print $c if $c =~ /\s/ && $c ne "\n" }')"
expect_true "LIST: perl's \\s set holds NBSP and U+3000 (extractor non-empty)" \
  perl -CSA -e 'exit(($ARGV[0] =~ /\x{a0}/ && $ARGV[0] =~ /\x{3000}/) ? 0 : 1)' "$SPACES"
perl -CSA -e 'my $s = shift; print "${_}mxv9 plover${_}\n" for split //, $s' "$SPACES" > "$TMP/lists/lst7"
NSP="$(wc -l < "$TMP/lists/lst7" | tr -d ' ')"
scan "$R" "$TMP/lists/lst7"
expect_contains "LIST: one line per white space character, each an entry" "entries=$NSP " "$OUT"
expect_eq "LIST: every one of the $NSP lines is found at the very start of the text" \
  "$NSP" "$(hits | grep -c " at blob $SB line 1\$")"
# a line of nothing but Unicode spaces is blank: skipped, counted, never an empty entry
printf '%s\n%s\n' "$NBSP$NBSP" "mxv9 plover" > "$TMP/lists/lst8"
scan "$R" "$TMP/lists/lst8"
expect_eq "LIST: a line of NBSP alone is skipped but counted — the entry is line 2" "HIT entry=2 at blob $SB line 1" "$(hits)"
expect_contains "LIST: (same run) it is not an entry" "entries=1 " "$OUT"

section "§TRACE — an inherited git trace file does not record an entry (T32 finding 4, T52 finding 11)"

R="$TMP/trace1"; fx_repo "$R"
printf '%s\n' "$E1" > "$R/b.txt"; fx_commit "$R" "add b"
L="$(fx_list trace1 "$E1")"
mkdir -p "$TMP/trace"
# control: the trace mechanism records the entry when git is called directly with the variable set
GIT_TRACE="$TMP/trace/ctl" git -C "$R" grep -n -i -F -e "$E1" HEAD >/dev/null 2>&1
expect_true "TRACE: control — a direct git call with GIT_TRACE set records the entry" grep -q -F -- "$E1" "$TMP/trace/ctl"
TRACES=(GIT_TRACE="$TMP/trace/t1" GIT_TRACE2="$TMP/trace/t2" GIT_TRACE2_EVENT="$TMP/trace/t3" GIT_TRACE2_PERF="$TMP/trace/t4" GIT_TRACE_PACKET="$TMP/trace/t5" GIT_TRACE_SETUP="$TMP/trace/t6" GIT_TRACE_REFS="$TMP/trace/t7")
scan "$R" "$L" "${TRACES[@]}"
expect_status "TRACE: the run still finds the hit" 1 "$RC"
expect_eq "TRACE: and prints it (positive on the same run)" "HIT entry=1 at blob $(s12 "$R" HEAD:b.txt) line 1" "$(hits)"
TRACED="$(cat "$TMP"/trace/t[1-7] 2>/dev/null | grep -c -i -F -- "$E1" || true)"
expect_eq "TRACE: no trace file the run was pointed at holds the entry" "0" "$TRACED"
# the row has teeth: the same run through a copy with the unset loop removed writes the entry
# to the ref trace (the power check plants every entry in a tag name)
NOUNSET="$(doctor nounset 'for v in $(compgen -e); do case "$v" in GIT_TRACE*) unset "$v" ;; esac; done' ':')"
expect_false "TRACE: the doctored copy differs from the scan" cmp -s "$SCAN" "$NOUNSET"
rm -f "$TMP"/trace/t[1-7]
scanx "$NOUNSET" "$R" "$L" "${TRACES[@]}"
expect_eq "TRACE: the doctored copy still runs and finds the hit (positive)" "HIT entry=1 at blob $(s12 "$R" HEAD:b.txt) line 1" "$(hits)"
TRACED="$(cat "$TMP"/trace/t[1-7] 2>/dev/null | grep -c -i -F -- "$E1" || true)"
expect_ne "TRACE: without the unset loop a trace file DOES hold the entry (the row can fail)" "0" "$TRACED"

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
SHA="$(s12 "$R" HEAD)"
WANT="$(git -C "$R" ls-tree -r --name-only HEAD | grep -n -i -F -- "$B2" | cut -d: -f1)"
expect_nonempty "BASH32: the fixture's directory path sits at a position in tree order (extractor non-empty)" "$WANT"
scan "$R" "$TMP/lists/b32"
OUT_DEFAULT="$OUT"
expect_status "BASH32: under the PATH bash the fixture is a hit run (control)" 1 "$RC"
if [ -x /bin/bash ]; then
  OUT="$(cd "$R" && env -u BIONIC_CHECK_BASE -u BIONIC_CHECK_HEAD /bin/bash "$SCAN" "$TMP/lists/b32" 2>&1)"; RC=$?
  expect_status "BASH32: /bin/bash — the run exits 1" 1 "$RC"
  expect_contains "BASH32: /bin/bash — a content hit, through a BOM, CR LF and trailing-blank line" "HIT entry=1 at blob $(s12 "$R" HEAD:notes.txt) line 1" "$(hits)"
  expect_contains "BASH32: /bin/bash — a path hit" "HIT entry=2 at path #$WANT" "$(hits)"
  expect_contains "BASH32: /bin/bash — a message hit at a tagged head (range is v1.9.0..head)" "HIT entry=3 at commit $SHA message" "$(hits)"
  expect_contains "BASH32: /bin/bash — a tag-message hit" "HIT entry=4 at tag $(s12 "$R" v2.0.0)" "$(hits)"
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
argv_shim "$TMP/argv-shim" "$ALOG" git grep awk sed tr cut dirname mktemp rm cat head tail wc sort uniq touch env perl locale mkdir
# control: the shim records a pattern given the way the old scan gave it
PATH="$TMP/argv-shim:$PATH" git -C "$R" grep -n -F -e "$A1" HEAD >/dev/null 2>&1
expect_true "ARGV: control — the shim log records an entry passed as a word" grep -q -F -- "$A1" "$ALOG"
: > "$ALOG"
scan "$R" "$L"
BASE_OUT="$OUT"
expect_status "ARGV: without the shims the run is a hit run" 1 "$RC"
expect_contains "ARGV: content hit" "HIT entry=1 at blob $(s12 "$R" HEAD:c.txt) line 2" "$BASE_OUT"
expect_regex "ARGV: path hit" 'HIT entry=2 at path #[0-9]+' "$BASE_OUT"
expect_contains "ARGV: message hit" "HIT entry=3 at commit $(s12 "$R" HEAD) message" "$BASE_OUT"
expect_contains "ARGV: tag-message hit" "HIT entry=3 at tag $(s12 "$R" v0.2)" "$BASE_OUT"
scan "$R" "$L" PATH="$TMP/argv-shim:$PATH"
expect_eq "ARGV: through the logging shims the output is unchanged" "$BASE_OUT" "$OUT"
expect_contains "ARGV: the shims saw the scan's git calls (positive on the same log)" "cat-file" "$(cat "$ALOG")"
expect_contains "ARGV: and its matcher" "perl" "$(cat "$ALOG")"
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

section "§BYTES — every blob is read as bytes (T52 finding 1)"

EY="zq-bytes-4471"
# BYT1 a PNG-like blob holding the entry after a NUL; the line is newlines before the match + 1
R="$TMP/byt1"; fx_repo "$R"
printf '\211PNG\r\n\032\n\0\0%s\0tail\n' "$EY" > "$R/img.png"; fx_commit "$R" "add image"
L="$(fx_list byt1 "$EY")"
scan "$R" "$L"
expect_status "BYT1: a binary blob holding an entry exits 1" 1 "$RC"
expect_eq "BYT1: the hit is the blob, on line 3 (two newlines precede the match)" "HIT entry=1 at blob $(s12 "$R" HEAD:img.png) line 3" "$(hits)"
# BYT2 a file marked -diff, and one marked binary, in .gitattributes
R="$TMP/byt2"; fx_repo "$R"
printf '*.dat -diff\n*.raw binary\n' > "$R/.gitattributes"
printf 'see %s here\n' "$EY" > "$R/secret.dat"; printf 'plain\nsee %s\n' "$E1" > "$R/other.raw"
fx_commit "$R" "attrs"
L="$(fx_list byt2 "$EY" "$E1")"
scan "$R" "$L"
expect_status "BYT2: files marked -diff and binary exit 1" 1 "$RC"
expect_contains "BYT2: the -diff file is a hit" "HIT entry=1 at blob $(s12 "$R" HEAD:secret.dat) line 1" "$(hits)"
expect_contains "BYT2: the binary-marked file is a hit" "HIT entry=2 at blob $(s12 "$R" HEAD:other.raw) line 2" "$(hits)"
# BYT3 a symlink whose target holds the entry
R="$TMP/byt3"; fx_repo "$R"
ln -s "../$EY/x" "$R/link"; fx_commit "$R" "add link"
L="$(fx_list byt3 "$EY")"
scan "$R" "$L"
expect_status "BYT3: a symlink whose target holds an entry exits 1" 1 "$RC"
expect_eq "BYT3: the hit is the link's blob" "HIT entry=1 at blob $(s12 "$R" HEAD:link) line 1" "$(hits)"
# BYT4 an object the scan cannot read is a refusal, never a clean 0
R="$TMP/byt4"; fx_repo "$R"
printf 'plain\n' > "$R/gone.txt"; fx_commit "$R" "add"
L="$(fx_list byt4 "$E4")"
scan "$R" "$L"
expect_status "BYT4: before the object is removed the clean scan exits 0 (control)" 0 "$RC"
OID="$(git -C "$R" rev-parse HEAD:gone.txt)"
rm -f "$R/.git/objects/${OID:0:2}/${OID:2}"
expect_false "BYT4: the blob is gone from the object store (fixture)" git -C "$R" cat-file -e "$OID"
scan "$R" "$L"
expect_status "BYT4: a blob the range introduces that cannot be read refuses the run, exit 2" 2 "$RC"
expect_contains "BYT4: the refusal says the scan could not read what the push publishes" "could not read everything" "$OUT"
# the same blob reached through the head's tree alone (an empty range): the matcher names it
scan "$R" "$L" BIONIC_CHECK_BASE=HEAD
expect_status "BYT4: a blob at the head that cannot be read refuses the run, exit 2" 2 "$RC"
expect_contains "BYT4: the refusal names the object by its id" "object ${OID:0:12} cannot be read" "$OUT"

section "§RANGE — every object, person and tag the push publishes (T52 finding 2)"

# RNG1 a file added in commit 2 of the range and deleted in commit 3: its blob is still sent
EG="zq-gone-6402"
R="$TMP/rng1"; fx_repo "$R"
printf '%s\n' "$EG" > "$R/notes.txt"; fx_commit "$R" "add notes"
GONE="$(s12 "$R" HEAD:notes.txt)"
git -C "$R" rm -q notes.txt; fx_commit "$R" "remove notes"
L="$(fx_list rng1 "$EG")"
scan "$R" "$L"
expect_status "RNG1: a blob added and deleted inside the range exits 1" 1 "$RC"
expect_eq "RNG1: the hit is the deleted blob" "HIT entry=1 at blob $GONE line 1" "$(hits)"
# RNG2 a PATH that exists only inside the range
EGP="zq-gonepath-7720"
R="$TMP/rng2"; fx_repo "$R"
printf 'plain\n' > "$R/$EGP.txt"; fx_commit "$R" "add named"
ADDED="$(s12 "$R" HEAD)"
git -C "$R" rm -q "$EGP.txt"; fx_commit "$R" "remove named"
L="$(fx_list rng2 "$EGP")"
scan "$R" "$L"
expect_status "RNG2: a path added and deleted inside the range exits 1" 1 "$RC"
expect_eq "RNG2: the hit is the path in the commit that added it" "HIT entry=1 at path in commit $ADDED" "$(hits)"
expect_absent "RNG2: the path is not printed" ".txt" "$OUT"
# RNG3 a commit's author name and email, and one before the base that is not read
EA="zqauthor-5521"; EAO="zqoldauthor-1187"
R="$TMP/rng3"; fx_repo "$R"
GIT_AUTHOR_NAME="Zqoldauthor-1187" git -C "$R" commit -q --allow-empty -m "before"
git -C "$R" tag v0.2
GIT_AUTHOR_NAME="Zqauthor-5521 Dev" GIT_AUTHOR_EMAIL="dev@zqauthor-5521.invalid" git -C "$R" commit -q --allow-empty -m "by someone"
L="$(fx_list rng3 "$EA" "$EAO")"
scan "$R" "$L"
expect_status "RNG3: an author holding an entry exits 1" 1 "$RC"
expect_eq "RNG3: name and email in one author give ONE author line" "HIT entry=1 at commit $(s12 "$R" HEAD) author" "$(hits)"
expect_no_regex "RNG3: an author before the base is not read (same output)" 'entry=2' "$(hits)"
# RNG4 a committer's email only
EC="zqcommit-6610"
R="$TMP/rng4"; fx_repo "$R"
GIT_COMMITTER_EMAIL="ci@zqcommit-6610.invalid" git -C "$R" commit -q --allow-empty -m "landed"
L="$(fx_list rng4 "$EC")"
scan "$R" "$L"
expect_eq "RNG4: a committer email holding an entry is a committer hit" "HIT entry=1 at commit $(s12 "$R" HEAD) committer" "$(hits)"
# RNG5 a lightweight tag NAMED after an entry on the head
ET="zq-tagname-3301"
R="$TMP/rng5"; fx_repo "$R"
fx_commit "$R" "release"
git -C "$R" tag "$ET-rc1"
L="$(fx_list rng5 "$ET")"
scan "$R" "$L"
expect_status "RNG5: a tag named after an entry exits 1" 1 "$RC"
expect_eq "RNG5: the hit is the tag, by its commit" "HIT entry=1 at tag $(s12 "$R" HEAD)" "$(hits)"
expect_absent "RNG5: the tag name is not printed" "rc1" "$OUT"
# RNG6 an annotated tag inside the range, not at the head, and one before the range
ETM="zq-tagmsg-2275"
R="$TMP/rng6"; fx_repo "$R"
git -C "$R" tag -a v0.1-old -m "old $E2" v0.1
fx_commit "$R" "mid"
git -C "$R" tag -a mid-1 -m "mid $ETM"
fx_commit "$R" "head"
L="$(fx_list rng6 "$ETM" "$E2")"
scan "$R" "$L" BIONIC_CHECK_BASE=v0.1
expect_eq "RNG6: an annotated tag on a commit inside the range is read" "HIT entry=1 at tag $(s12 "$R" mid-1)" "$(hits)"
expect_no_regex "RNG6: a tag on the base is not (same output)" 'entry=2' "$(hits)"

section "§SEP — no byte a path or message can hold splits a record (T52 findings 3, 4)"

S1="zq-soh-1101"; S2="zq-newline-2202"; S3="zq-tab-3303"; S4="zq-colon-4404"
R="$TMP/sep1"; fx_repo "$R"
printf 'see %s\n' "$S1" > "$R/$(printf 'x\001%s.txt' "$S1")"
printf 'plain\n' > "$R/$(printf 'n\n%s.txt' "$S2")"
printf 'plain\n' > "$R/$(printf 't\t%s.txt' "$S3")"
printf 'plain\n' > "$R/$(printf 'c:%s.txt' "$S4")"
fx_commit "$R" "odd names"
L="$(fx_list sep1 "$S1" "$S2" "$S3" "$S4")"
scan "$R" "$L"
expect_status "SEP1: paths holding SOH, newline, tab and colon exit 1" 1 "$RC"
k=0
for e in "$S1" "$S2" "$S3" "$S4"; do
  k=$((k + 1))
  P="$(pos_of "$R" "$e")"
  expect_nonempty "SEP1: entry $k's path sits at a position in tree order (extractor non-empty)" "$P"
  expect_contains "SEP1: entry $k is a hit at its path's position" "HIT entry=$k at path #$P" "$(hits)"
  expect_eq "SEP1: the scan's whole output holds entry $k zero times" "0" "$(count_in "$OUT" "$e")"
done
expect_contains "SEP1: the SOH file's contents are a hit, at its blob" "HIT entry=1 at blob $(git -C "$R" ls-tree -r HEAD | awk -v e="$S1" 'index($0, e) { print substr($3, 1, 12) }') line 1" "$(hits)"
expect_eq "SEP1: five hits in all (one per path, one content), none split" "5" "$(hits | grep -c '^HIT ')"
expect_absent "SEP1: no part of any path is printed" ".txt" "$OUT"
# SEP2 a commit message holding a SOH byte before the entry
SM="zq-sohmsg-5505"
R="$TMP/sep2"; fx_repo "$R"
git -C "$R" commit -q --allow-empty --cleanup=verbatim -m "$(printf 'fix\001 %s leak' "$SM")"
L="$(fx_list sep2 "$SM")"
scan "$R" "$L"
expect_status "SEP2: a message with SOH before the entry exits 1" 1 "$RC"
expect_eq "SEP2: the hit is the commit's message" "HIT entry=1 at commit $(s12 "$R" HEAD) message" "$(hits)"
expect_absent "SEP2: the subject is not printed" "leak" "$OUT"

section "§CASE — the scan decides the locale, and folds case for any letter (T52 finding 5)"

OU=$'\303\226'; ou=$'\303\266'   # O and o with diaeresis, as UTF-8 bytes
EU="zq${ou}rbix-8812"            # the list entry, lower case
R="$TMP/case1"; fx_repo "$R"
# the file under the upper-case directory holds the entry too: its content hit must not name the path
mkdir -p "$R/ZQ${OU}RBIX-8812-dir"; printf '%s\n' "$EU" > "$R/ZQ${OU}RBIX-8812-dir/x.txt"; fx_commit "$R" "upper dir"
L="$(fx_list case1 "$EU")"
P="$(pos_of "$R" "ZQ${OU}RBIX")"
expect_nonempty "CASE1: the upper-case path sits at a position in tree order (extractor non-empty)" "$P"
XB="$(git -C "$R" ls-tree -r HEAD | awk '/x\.txt/ { print substr($3, 1, 12) }')"
expect_nonempty "CASE1: the file's blob id (extractor non-empty)" "$XB"
for loc in C en_US.UTF-8; do
  scan "$R" "$L" LC_ALL="$loc"
  expect_status "CASE1: caller LC_ALL=$loc — an upper-case non-ASCII path exits 1" 1 "$RC"
  expect_contains "CASE1: caller LC_ALL=$loc — the hit is the path's position" "HIT entry=1 at path #$P" "$(hits)"
  expect_contains "CASE1: caller LC_ALL=$loc — and the file's contents, by blob" "HIT entry=1 at blob $XB line 1" "$(hits)"
  expect_absent "CASE1: caller LC_ALL=$loc — the path is not printed" "RBIX" "$OUT"
  expect_absent "CASE1: caller LC_ALL=$loc — nor the entry" "rbix" "$OUT"
done
# CASE2 contents and a message in another case, under a C caller
R="$TMP/case2"; fx_repo "$R"
printf 'see ZQ%sRBIX-8812 here\n' "$OU" > "$R/n.txt"; fx_commit "$R" "$(printf 'mention ZQ%sRBIX-8812' "$OU")"
scan "$R" "$(fx_list case2 "$EU")" LC_ALL=C
expect_contains "CASE2: caller LC_ALL=C — upper-case non-ASCII contents are a hit" "HIT entry=1 at blob $(s12 "$R" HEAD:n.txt) line 1" "$(hits)"
expect_contains "CASE2: caller LC_ALL=C — and the message" "HIT entry=1 at commit $(s12 "$R" HEAD) message" "$(hits)"
# CASE3 no UTF-8 locale on the machine: the matcher folds without one, so a non-ASCII entry is
# scanned and found, not refused (T56 N6: the refusal refused a run that works)
NOLOC="$TMP/shim-nolocale"; mkdir -p "$NOLOC"
printf '#!/bin/bash\ncase "${1:-}" in -a) printf "C\\nPOSIX\\n" ;; *) echo US-ASCII ;; esac\n' > "$NOLOC/locale"; chmod +x "$NOLOC/locale"
scan "$R" "$(fx_list case3 "$EU")" PATH="$NOLOC:$PATH"
expect_status "CASE3: no UTF-8 locale and a non-ASCII entry — scanned, and the upper-case contents found, exit 1" 1 "$RC"
expect_contains "CASE3: (same run) the hit is the upper-case contents, by blob" "HIT entry=1 at blob $(s12 "$R" HEAD:n.txt) line 1" "$(hits)"
expect_absent "CASE3: (same run) the entry is not printed" "rbix" "$OUT"
printf 'see %s\n' "$E1" > "$R/m.txt"; fx_commit "$R" "ascii"
scan "$R" "$(fx_list case3b "$E1")" PATH="$NOLOC:$PATH"
expect_status "CASE3: the same machine with an ASCII-only list runs, and finds (control)" 1 "$RC"

section "§XTRACE — a caller's trace prints no entry (T52 finding 6)"

EX="zq-xtrace-9093"
R="$TMP/xt1"; fx_repo "$R"
printf '%s\n' "$EX" > "$R/b.txt"; fx_commit "$R" "add b"
L="$(fx_list xt1 "$EX")"
OUT="$(cd "$R" && env -u BIONIC_CHECK_BASE -u BIONIC_CHECK_HEAD bash -x "$SCAN" "$L" 2>&1)"; RC=$?
expect_status "XTRACE: bash -x — the run still exits 1" 1 "$RC"
expect_contains "XTRACE: bash -x — it prints the hit (positive on the same output)" "HIT entry=1 at blob" "$OUT"
expect_eq "XTRACE: bash -x — stdout and stderr hold the entry zero times" "0" "$(count_in "$OUT" "$EX")"

section "§CEIL — a caller's discovery variables cannot pass a list inside a checkout (T52 finding 10)"

R="$TMP/ceil1"; fx_repo "$R"
mkdir -p "$R/sub/dir"; printf '%s\n' "$E4" > "$R/sub/dir/list.txt"
scan "$R" "$R/sub/dir/list.txt" GIT_CEILING_DIRECTORIES="$R"
expect_status "CEIL: GIT_CEILING_DIRECTORIES set to the checkout — the list inside it is still refused" 2 "$RC"
expect_contains "CEIL: and the refusal says where the list is" "inside a git checkout" "$OUT"
scan "$R" "$(fx_list ceil1 "$E4")" GIT_CEILING_DIRECTORIES="$R"
expect_status "CEIL: the same variable with a list outside every checkout runs clean (control)" 0 "$RC"

section "§SITES — the power check plants every entry at every site (T52 power check)"

# a clean fixture, so a doctored copy's refusal is the power check's and nothing else's
R="$TMP/sites"; fx_repo "$R"
L="$(fx_list sites "$E4" "$E3")"
CTRL="$(doctor control 'no such span' 'no such span')"
scanx "$CTRL" "$R" "$L"
expect_status "SITES: the undoctored copy, run from the same place, is clean (control)" 0 "$RC"
# site|from|to — each blinds ONE site; the refusal must name that site
while IFS='|' read -r site from to; do
  [ -n "$site" ] || continue
  D="$(doctor "blind-${site// /-}" "$from" "$to")"
  expect_false "SITES: $site — the doctored copy differs from the scan" cmp -s "$SCAN" "$D"
  expect_true "SITES: $site — the doctored copy parses" bash -n "$D"
  scanx "$D" "$R" "$L"
  expect_status "SITES: $site blinded — no power, exit 2, not a clean 0" 2 "$RC"
  expect_contains "SITES: $site blinded — the refusal names the site" "at its $site in the throwaway" "$OUT"
done <<'SITES'
text blob|look($d, "blob $sha", 1); }|look($d, "blob $sha", 1) if $d =~ /\0/; }
binary blob|look($d, "blob $sha", 1); }|look($d, "blob $sha", 1) if $d !~ /\0/; }
symlink target|$2 == "blob" { print $3 }|$2 == "blob" && $1 != "120000" { print $3 }
path name|look($p, "path #$n", 0);|look("", "path #$n", 0);
range-only path|look($p, "path in commit $c", 0);|look("", "path in commit $c", 0);
range-only blob|--filter=object:type=blob|--filter=blob:none
message|look($msg, "commit $sha message", 0);|look("", "commit $sha message", 0);
author name|look($name, "commit $sha $who", 0);|look($name, "commit $sha $who", 0) if $who ne "author";
author email|look($mail, "commit $sha $who", 0);|look($mail, "commit $sha $who", 0) if $who ne "author";
committer name|look($name, "commit $sha $who", 0);|look($name, "commit $sha $who", 0) if $who ne "committer";
committer email|look($mail, "commit $sha $who", 0);|look($mail, "commit $sha $who", 0) if $who ne "committer";
tag name|look($ref, "tag $s", 0);|look("", "tag $s", 0);
tag message|look($msg, "tag $sha", 0);|look("", "tag $sha", 0);
wrapped text|join $ws, map|join " ", map
text blob|(?<ws>\h++|(?<ws>(?!)
wrapped text|my $run = qr{\h*+(?:$sym\h*+){0,24}};|my $run = qr{(?:$sym){0,24}};
wrapped text|(?>$side)\R$side|(?>$side)\n$side
symbol-wrapped text|my $sym = qr{(?!$tag)[^\p{L}\p{Nd}\s]};|my $sym = qr{(?!)};
tag-wrapped text|my $tag = qr{<[^<>\v]{0,200}+>};|my $tag = qr{(?!)};
SITES

section "§COST — one pass for the whole list, inside the time ceiling (T52 finding 13)"

# the number of processes a scan starts does not grow with the list: one pass per site
R="$TMP/cost1"; fx_repo "$R"
printf 'plain\n' > "$R/b.txt"; fx_commit "$R" "more"
CLOG="$TMP/cost.log"
cshim="$TMP/count-shim"; mkdir -p "$cshim"
for n in git perl; do
  printf '#!/bin/bash\necho %s >> "%s"\nexec "%s" "$@"\n' "$n" "$CLOG" "$(type -P "$n")" > "$cshim/$n"; chmod +x "$cshim/$n"
done
: > "$CLOG"; scan "$R" "$(fx_list cost1 "$E4")" PATH="$cshim:$PATH"
ONE="$(wc -l < "$CLOG" | tr -d ' ')"
expect_status "COST: a one-entry list scans clean through the counting shim (control)" 0 "$RC"
expect_ne "COST: the counting shim saw the scan's calls (positive)" "0" "$ONE"
: > "$CLOG"; scan "$R" "$(fx_list cost6 "$E4" "$E3" "zq-c3-1" "zq-c4-2" "zq-c5-3" "zq-c6-4")" PATH="$cshim:$PATH"
expect_eq "COST: a six-entry list starts exactly as many git and perl processes as a one-entry list" "$ONE" "$(wc -l < "$CLOG" | tr -d ' ')"
expect_eq "COST: and runs the matcher twice (the power check and the scan), whatever the list's length" "2" "$(grep -c '^perl$' "$CLOG")"
# a clean 500-entry scan of this repository, read-only, under the 20-second ceiling
if git -C "$BIONIC_SCRIPTS_DIR" rev-parse --verify -q HEAD >/dev/null 2>&1; then
  i=0; : > "$TMP/lists/cost500"
  # entries of two and three words (T61 note), so the bound times the wrap construction
  while [ "$i" -lt 500 ]; do
    if [ $((i % 2)) -eq 0 ]; then printf 'zqtm%04d xvq\n' "$i"; else printf 'zqtm%04d xvq yqj%03d\n' "$i" "$i"; fi >> "$TMP/lists/cost500"
    i=$((i + 1))
  done
  expect_eq "COST: (fixture) half the 500 entries have three words" "250" "$(grep -c '^zqtm[0-9]* xvq yqj' "$TMP/lists/cost500")"
  T0="$(date +%s)"
  scan "$BIONIC_SCRIPTS_DIR" "$TMP/lists/cost500"
  EL_S=$(( $(date +%s) - T0 ))
  echo "COST: a clean 500-entry scan of this repository took ${EL_S}s"
  expect_status "COST: the 500-entry scan of this repository is clean" 0 "$RC"
  expect_contains "COST: (same run) it read 500 entries" "entries=500 hits=0" "$OUT"
  expect_true "COST: and took at most 20 seconds (took ${EL_S}s)" [ "$EL_S" -le 20 ]
else
  echo "SKIP: $BIONIC_SCRIPTS_DIR is not a git checkout; the 500-entry timing row did not run"
fi
# a hit's line is counted on from the previous hit (T56 N8): 20,000 matching lines in one blob,
# a two-word entry on each, inside 5 seconds measured here
EN="mxv9 plover"
R="$TMP/cost20k"; fx_repo "$R"
yes "see $EN here" | head -n 20000 > "$R/many.txt"; fx_commit "$R" "many"
expect_eq "COST: the fixture blob has 20,000 lines (fixture)" "20000" "$(wc -l < "$R/many.txt" | tr -d ' ')"
T0="$(date +%s)"
scan "$R" "$(fx_list cost20k "$EN")"
EL_S=$(( $(date +%s) - T0 ))
echo "COST: a scan with 20,000 matching lines took ${EL_S}s"
expect_status "COST: 20,000 matching lines — exit 1" 1 "$RC"
expect_eq "COST: (same run) one hit per line" "20000" "$(hits | grep -c '^HIT ')"
expect_contains "COST: (same run) the last hit names line 20000" "HIT entry=1 at blob $(s12 "$R" HEAD:many.txt) line 20000" "$(hits)"
expect_true "COST: and took under 5 seconds (took ${EL_S}s)" [ "$EL_S" -lt 5 ]
# the wrap construction cannot backtrack without bound (T61 B1): a megabyte of `-`, of `<`, of
# `"`, and of lines that are blanks and one symbol, the entry's first word every 64 characters
# so the construction is tried there each time, each a clean scan inside 5 seconds measured here
R="$TMP/costmb"; fx_repo "$R"
perl -e 'my $u = "mxv9" . ("-" x 60); print $u x 16384' > "$R/dash.txt"
perl -e 'my $u = "mxv9" . ("<" x 60); print $u x 16384' > "$R/lt.txt"
perl -e 'my $u = "mxv9" . ("\"" x 60); print $u x 16384' > "$R/quote.txt"
perl -e 'my $u = "mxv9\n" . ("     ;     \n" x 5); print $u x 16384' > "$R/blank.txt"
fx_commit "$R" "a megabyte each"
for f in dash.txt lt.txt quote.txt blank.txt; do
  expect_true "COST: (fixture) $f is at least a megabyte" [ "$(wc -c < "$R/$f" | tr -d ' ')" -ge 1048576 ]
done
T0="$(date +%s)"
scan "$R" "$(fx_list costmb "$E3")"
EL_S=$(( $(date +%s) - T0 ))
echo "COST: a scan of four megabytes of punctuation and blank lines took ${EL_S}s"
expect_status "COST: the megabytes of punctuation scan clean" 0 "$RC"
expect_contains "COST: (same run) one entry read, no hit" "entries=1 hits=0" "$OUT"
expect_true "COST: and took under 5 seconds (took ${EL_S}s)" [ "$EL_S" -lt 5 ]
# a list line that opens with a Unicode space, over a text of 200 KB of blanks (T61 note: an
# entry that began with an empty word cost 100 seconds on 50 KB)
R="$TMP/cost200k"; fx_repo "$R"
perl -e 'print "mxv9 plover\n", " \xc2\xa0" x 70000, "see mxv9 plover\n"' > "$R/blanks.txt"
fx_commit "$R" "blanks"
expect_true "COST: (fixture) the blank text is over 200 KB" [ "$(wc -c < "$R/blanks.txt" | tr -d ' ')" -ge 204800 ]
L="$(fx_list cost200k "${NBSP}mxv9 plover")"
T0="$(date +%s)"
# a hard ceiling: the scan runs in its own process group, killed whole after 20 seconds (a
# quadratic scan would otherwise hold the suite for many minutes)
OUT="$(cd "$R" && perl -e 'setpgrp(0, 0); $SIG{ALRM} = sub { kill "KILL", -$$ }; alarm 20; system @ARGV; exit($? >> 8)' \
  env -u BIONIC_CHECK_BASE -u BIONIC_CHECK_HEAD bash "$SCAN" "$L" 2>&1)"; RC=$?
EL_S=$(( $(date +%s) - T0 ))
echo "COST: a scan of 200 KB of blanks with a list line opening on NBSP took ${EL_S}s"
expect_status "COST: the blank text with a list line opening on NBSP — exit 1" 1 "$RC"
expect_contains "COST: (same run) the entry at the very start of the blank text is found" "HIT entry=1 at blob $(s12 "$R" HEAD:blanks.txt) line 1" "$(hits)"
expect_contains "COST: (same run) and the one after the 200 KB of blanks" "HIT entry=1 at blob $(s12 "$R" HEAD:blanks.txt) line 2" "$(hits)"
expect_true "COST: and took under 5 seconds (took ${EL_S}s)" [ "$EL_S" -lt 5 ]

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
expect_contains "QUIET1: including a hit in a path that carries an entry, by position" "HIT entry=2 at path #" "$(hits)"
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

# QUIET4 git's own complaints name what it read: a ref git calls broken is named in its warning
EK="zq-brokenref-8150"
R="$TMP/q4"; fx_repo "$R"
mkdir -p "$R/.git/refs/tags"; git -C "$R" rev-parse HEAD > "$R/.git/refs/tags/$EK..x"
L="$(fx_list q4 "$EK")"
scan "$R" "$L"
expect_contains "QUIET4: a repository holding a broken ref name scans (positive on the same output)" "entries=1" "$OUT"
expect_eq "QUIET4: and git's warning about it does not reach the output" "0" "$(count_in "$OUT" "$EK")"
LOUD="$(doctor loudrefs "refs/tags \\
    2>/dev/null >" "refs/tags \\
    >")"
expect_false "QUIET4: the doctored copy (git's stderr let through) differs from the scan" cmp -s "$SCAN" "$LOUD"
scanx "$LOUD" "$R" "$L"
expect_contains "QUIET4: the doctored copy still runs (positive)" "entries=1" "$OUT"
expect_ne "QUIET4: and with git's stderr let through the ref name DOES leak (the row can fail)" "0" "$(count_in "$OUT" "$EK")"

section "§WRAP — white space inside an entry is any run of white space (T56 B1)"

# one file per form, so each hit names its own blob; E3 is the two-word entry `mxv9 plover`,
# EW1 a one-word entry, EW2 an entry with regex metacharacters and a space
EW1="zq-wrap-6630"; EW2="zq.v+ (1)"
R="$TMP/wrap1"; fx_repo "$R"
W="$R/w"; mkdir -p "$W"
printf 'The scan was\nwritten for the mxv9\nplover project.\n' > "$W/md.md"
printf 'see mxv9  plover here\n' > "$W/two-spaces.txt"
printf 'see mxv9\tplover here\n' > "$W/tab.txt"
printf 'see the mxv9\r\nplover case\r\n' > "$W/crlf.txt"
printf '# written for the mxv9\n# plover project\n' > "$W/hash.sh"
printf '// the mxv9\n// plover case\n' > "$W/slashes.c"
printf '/// the mxv9\n/// plover case\n' > "$W/doc-slashes.rs"
printf '/*\n * the mxv9\n * plover case\n */\n' > "$W/block.c"
printf '> the mxv9\n> plover case\n' > "$W/quote.md"
printf -- '-- mxv9\n-- plover\n' > "$W/dashes.sql"
printf '; the mxv9\n; plover case\n' > "$W/semi.ini"
printf 'see mxv9plover here\n' > "$W/run-together.txt"
printf 'see mxv9 # plover here\n' > "$W/leader-one-line.txt"
printf 'see mxv9\n\n\nplover here\n' > "$W/blank-lines.txt"
printf 'see ZQ-WRAP-6630 here\nand zq-wrap\n6630 there\n' > "$W/one-word.txt"
printf 'see ZQ.V+\n(1) here\n' > "$W/meta.txt"
printf 'see zqXvv (1) here\n' > "$W/meta-not.txt"
# T61 B1: at the one line break, each side may hold horizontal white space, at most 24 symbols
# and at most three tags, in any mix: the three forms of review pass 37, then the rest
printf 'echo "the mxv9 " \\\n     "plover case"\n' > "$W/sh-args.sh"
printf '<text x="60" y="412">the mxv9</text>\n  <text x="60" y="430" class="s">plover case</text>\n' > "$W/text.svg"
printf '@@ -1,2 +1,4 @@\n+# the mxv9\n+# plover case\n' > "$W/change.patch"
printf '["mxv9",\n "plover"]\n' > "$W/array.json"
printf '<p>mxv9<br/>\nplover</p>\n' > "$W/br.html"
printf '## the mxv9\n## plover\n' > "$W/hash2.md"
printf '>> mxv9\n>> plover\n' > "$W/quote2.md"
printf ';; mxv9\n;; plover\n' > "$W/semi2.el"
printf 'see mxv9\302\240plover here\n' > "$W/nbsp.txt"
printf 'mxv9 %s\nplover\n' "$(printf '%024d' 0 | tr 0 '-')" > "$W/sym24.txt"
printf 'x mxv9<a><b><c>\n<d><e><f>plover\n' > "$W/tags3.html"
printf 'zqtri\nwenlo daspy\n' > "$W/tri-gap1.txt"
printf 'zqtri wenlo\n# daspy\n' > "$W/tri-gap2.txt"
printf 'zqtri "\n" wenlo</b>\n  <b>daspy\n' > "$W/tri-both.txt"
# not found: symbols between two words on ONE line, a blank line, symbols over the bound, a
# letter at the break, four tags on one side
printf 'see mxv9, plover here\n' > "$W/comma-one-line.txt"
printf 'see mxv9 - plover here\n' > "$W/dash-one-line.txt"
printf 'mxv9 %s\nplover\n' "$(printf '%025d' 0 | tr 0 '-')" > "$W/sym25.txt"
printf 'see mxv9\nx plover\n' > "$W/letter.txt"
printf 'x mxv9<a><b><c><d>\nplover\n' > "$W/tags4.html"
git -C "$R" add -A
git -C "$R" commit -q -m "$(printf 'docs: where the scan came from\n\nIt was first written for the mxv9\nplover project.')"
L="$(fx_list wrap1 "$E3" "$EW1" "$EW2" "zqtri wenlo daspy")"
scan "$R" "$L"
expect_status "WRAP: a tree and a commit body holding the wrapped entry exit 1" 1 "$RC"
wb() { s12 "$R" "HEAD:w/$1"; }
for f in 'md.md|2' 'two-spaces.txt|1' 'tab.txt|1' 'crlf.txt|1' 'hash.sh|1' 'slashes.c|1' 'doc-slashes.rs|1' 'block.c|2' 'quote.md|1' 'dashes.sql|1' 'semi.ini|1' \
  'sh-args.sh|1' 'text.svg|1' 'change.patch|2' 'array.json|1' 'br.html|1' 'hash2.md|1' 'quote2.md|1' 'semi2.el|1' 'nbsp.txt|1' 'sym24.txt|1' 'tags3.html|1'; do
  expect_eq "WRAP: ${f%%|*} — the entry is found once, on the line its match starts on" \
    "HIT entry=1 at blob $(wb "${f%%|*}") line ${f#*|}" "$(hits | grep -F "blob $(wb "${f%%|*}") ")"
done
for f in tri-gap1.txt tri-gap2.txt tri-both.txt; do
  expect_eq "WRAP: $f — a three-word entry wrapped at one gap or both is found once, on line 1" \
    "HIT entry=4 at blob $(wb "$f") line 1" "$(hits | grep -F "blob $(wb "$f") ")"
done
expect_contains "WRAP: a commit body wrapped between the words is a hit" "HIT entry=1 at commit $(s12 "$R" HEAD) message" "$(hits)"
for f in run-together.txt leader-one-line.txt blank-lines.txt meta-not.txt comma-one-line.txt dash-one-line.txt sym25.txt letter.txt tags4.html; do
  expect_nonempty "WRAP: $f has a blob id (extractor non-empty)" "$(wb "$f")"
  expect_no_regex "WRAP: $f — not a hit (same output)" "blob $(wb "$f")" "$(hits)"
done
expect_eq "WRAP: a one-word entry matches exactly as before — its one-line form only" \
  "HIT entry=2 at blob $(wb one-word.txt) line 1" "$(hits | grep -F "blob $(wb one-word.txt) ")"
expect_eq "WRAP: an entry with regex metacharacters is literal, and wraps at its space" \
  "HIT entry=3 at blob $(wb meta.txt) line 1" "$(hits | grep -F "blob $(wb meta.txt) ")"
expect_eq "WRAP: the scan's whole output holds the two-word entry's words zero times" "0" "$(count_in "$OUT" plover)"
# the not-found forms alone scan clean (rc=0), and one wrapped form added to them is a hit
R2="$TMP/wrap2"; fx_repo "$R2"; mkdir -p "$R2/w"
for f in run-together.txt leader-one-line.txt comma-one-line.txt dash-one-line.txt blank-lines.txt sym25.txt letter.txt tags4.html; do
  cp "$W/$f" "$R2/w/$f"
done
fx_commit "$R2" "the forms that are not a wrap"
scan "$R2" "$(fx_list wrap2 "$E3")"
expect_status "WRAP: the forms that are not a wrap, alone — exit 0" 0 "$RC"
expect_contains "WRAP: (same run) one entry read, no hit" "entries=1 hits=0" "$OUT"
cp "$W/sh-args.sh" "$R2/w/sh-args.sh"; fx_commit "$R2" "one wrap"
scan "$R2" "$(fx_list wrap2b "$E3")"
expect_eq "WRAP: the same tree plus one wrapped form — that one blob is the only hit (control)" \
  "HIT entry=1 at blob $(s12 "$R2" HEAD:w/sh-args.sh) line 1" "$(hits)"

section "§PUSHED — the objects a push sends, not a local replacement (T56 N1, N3)"

ER="zq-replaced-4410"
# PSH1 a commit whose message holds the entry, replaced locally by a clean one
R="$TMP/psh1"; fx_repo "$R"
printf 'y\n' > "$R/f.txt"; fx_commit "$R" "fix for $ER"
ORIG="$(git -C "$R" rev-parse HEAD)"
NEWC="$(git -C "$R" cat-file commit HEAD | sed "s/fix for $ER/fix/" | git -C "$R" hash-object -t commit -w --stdin)"
git -C "$R" replace "$ORIG" "$NEWC"
expect_eq "PSH1: the fixture's log shows the replacement (fixture)" "fix" "$(git -C "$R" log -1 --format=%s)"
scan "$R" "$(fx_list psh1 "$ER")"
expect_status "PSH1: a commit message replaced by a clean one is read as the push sends it — exit 1" 1 "$RC"
expect_eq "PSH1: the hit is the original commit's message" "HIT entry=1 at commit ${ORIG:0:12} message" "$(hits)"
# PSH2 a blob holding the entry, replaced locally by a clean one
R="$TMP/psh2"; fx_repo "$R"
printf 'see %s\n' "$ER" > "$R/g.txt"; fx_commit "$R" "add g"
OB="$(git -C "$R" rev-parse HEAD:g.txt)"
git -C "$R" replace "$OB" "$(printf 'clean\n' | git -C "$R" hash-object -w --stdin)"
expect_eq "PSH2: the fixture reads the replacement (fixture)" "clean" "$(git -C "$R" cat-file -p HEAD:g.txt)"
scan "$R" "$(fx_list psh2 "$ER")"
expect_status "PSH2: a blob replaced by a clean one is read as the push sends it — exit 1" 1 "$RC"
expect_eq "PSH2: the hit is the original blob" "HIT entry=1 at blob ${OB:0:12} line 1" "$(hits)"
# PSH3 tag A annotated on tag B annotated on a commit, the entry only in B's message, B's ref gone
ETN="zq-innertag-5182"
R="$TMP/psh3"; fx_repo "$R"
fx_commit "$R" "mid"
git -C "$R" tag -a inner -m "inner $ETN"
INNER="$(s12 "$R" inner)"
git -C "$R" -c advice.nestedTag=false tag -a outer -m "outer" inner
git -C "$R" tag -d inner >/dev/null
expect_eq "PSH3: the outer tag names the inner tag object (fixture)" "tag" "$(git -C "$R" cat-file -p outer | sed -n 's/^type //p')"
scan "$R" "$(fx_list psh3 "$ETN")" BIONIC_CHECK_BASE=v0.1
expect_status "PSH3: a nested tag's inner message is read — exit 1" 1 "$RC"
expect_eq "PSH3: the hit is the inner tag object" "HIT entry=1 at tag $INNER" "$(hits)"

section "§PERLDB — a caller's perl debugger prints no entry (T56 N4)"

EPD="zq-perldb-7314"
R="$TMP/perldb"; fx_repo "$R"
printf '%s\n' "$EPD" > "$R/b.txt"; fx_commit "$R" "add b"
scan "$R" "$(fx_list perldb "$EPD")" PERL5OPT=-d PERLDB_OPTS='NonStop=1 frame=6 LineInfo=/dev/stderr'
expect_status "PERLDB: with the debugger in the caller's environment the run still exits 1" 1 "$RC"
expect_eq "PERLDB: (same run) it prints the hit" "HIT entry=1 at blob $(s12 "$R" HEAD:b.txt) line 1" "$(hits)"
expect_eq "PERLDB: (same run) stdout and stderr hold the entry zero times" "0" "$(count_in "$OUT" "$EPD")"
# each of the five variables the scan unsets has its own row (T61 S2), red on a copy that keeps
# it: a module directory whose strict.pm prints the matcher's list file (its first argument) to
# stderr, and a debugger hook that does the same
HM="$TMP/hostile-lib"; mkdir -p "$HM"
cat > "$HM/strict.pm" <<'PM'
package strict;
sub import { if (@ARGV && open(my $h, "<", $ARGV[0])) { local $/; my $d = <$h>; $d =~ tr/\0/\n/; print STDERR "HOSTILE $d\n" } }
sub unimport {}
1;
PM
DBHOOK='BEGIN { if (@ARGV && open(my $h, "<", $ARGV[0])) { local $/; my $d = <$h>; $d =~ tr/\0/\n/; print STDERR "HOSTILE $d" } } sub DB::DB {}'
UNSET='unset PERL5OPT PERL5LIB PERLLIB PERL5DB PERLDB_OPTS'
# var|the env the row sets|the unset on the copy that must leak (PERL5DB and PERLDB_OPTS act only
# under -d, which reaches the matcher through PERL5OPT alone: their copies keep PERL5OPT too)
while IFS='|' read -r var keep mark; do
  case "$var" in
    PERL5OPT) set -- PERL5OPT="-I$HM -Mstrict" ;;
    PERL5LIB) set -- PERL5LIB="$HM" ;;
    PERLLIB) set -- PERLLIB="$HM" ;;
    PERL5DB) set -- PERL5OPT=-d PERL5DB="$DBHOOK" ;;
    PERLDB_OPTS) set -- PERL5OPT=-d PERLDB_OPTS='NonStop=1 frame=6 LineInfo=/dev/stderr' ;;
  esac
  scan "$R" "$(fx_list "pv-$var" "$EPD")" "$@"
  expect_eq "PERLDB: $var set by the caller — the scan still prints the hit" "HIT entry=1 at blob $(s12 "$R" HEAD:b.txt) line 1" "$(hits)"
  expect_eq "PERLDB: $var — (same run) stdout and stderr hold the entry zero times" "0" "$(count_in "$OUT" "$EPD")"
  D="$(doctor "keep-$var" "$UNSET" "$keep")"
  expect_false "PERLDB: $var — the copy that keeps it differs from the scan" cmp -s "$SCAN" "$D"
  scanx "$D" "$R" "$(fx_list "pvk-$var" "$EPD")" "$@"
  expect_contains "PERLDB: $var — the copy that keeps it ran what the variable names (positive)" "$mark" "$OUT"
  expect_ne "PERLDB: $var — and the copy that keeps it prints the entry (the row can fail)" "0" "$(count_in "$OUT" "$EPD")"
done <<'VARS'
PERL5OPT|unset PERL5LIB PERLLIB PERL5DB PERLDB_OPTS|HOSTILE
PERL5LIB|unset PERL5OPT PERLLIB PERL5DB PERLDB_OPTS|HOSTILE
PERLLIB|unset PERL5OPT PERL5LIB PERL5DB PERLDB_OPTS|HOSTILE
PERL5DB|unset PERL5LIB PERLLIB PERLDB_OPTS|HOSTILE
PERLDB_OPTS|unset PERL5LIB PERLLIB PERL5DB|entries=1
VARS

section "§INERT — the locale pick and the BASH_ENV unset each do something (T56 N6, N7)"

# INERT1 the locale pick lets the power check's upper-case plant prove the fold of a non-ASCII
# letter: a matcher that folds ASCII only is refused for a non-ASCII entry
R="$TMP/inert1"; fx_repo "$R"
ASCIIFOLD="$(doctor asciifold 'sub fold { fc(Encode::decode("UTF-8", $_[0])) }' 'sub fold { lc($_[0]) }')"
expect_false "INERT1: the ASCII-fold copy differs from the scan" cmp -s "$SCAN" "$ASCIIFOLD"
expect_true "INERT1: the ASCII-fold copy parses" bash -n "$ASCIIFOLD"
scanx "$ASCIIFOLD" "$R" "$(fx_list inert1a "$E1")"
expect_status "INERT1: the ASCII-fold copy with an ASCII list runs clean (control)" 0 "$RC"
scanx "$ASCIIFOLD" "$R" "$(fx_list inert1 "$EU")"
expect_status "INERT1: the ASCII-fold copy with a non-ASCII entry — no power, exit 2" 2 "$RC"
expect_contains "INERT1: the refusal names the upper-case plant" "at its text blob in the throwaway" "$OUT"
NOPICK="$(doctor_from "$ASCIIFOLD" nopick 'export LC_ALL="$utf8"' ':')"
expect_false "INERT1: the copy without the pick differs from the ASCII-fold copy" cmp -s "$ASCIIFOLD" "$NOPICK"
scanx "$NOPICK" "$R" "$(fx_list inert1b "$EU")"
expect_status "INERT1: without the locale pick the same blind matcher passes the power check (the row can fail)" 0 "$RC"
# INERT2 a caller's BASH_ENV does not reach a bash the scan starts (a git wrapper on PATH)
R="$TMP/inert2"; fx_repo "$R"
printf '%s\n' "$E1" > "$R/b.txt"; fx_commit "$R" "add b"
# the BASH_ENV file logs each bash that reads it: the scan's own interpreter reads it before
# line 1 (A-T52.8), so the log holds exactly one line when no bash the scan starts reads it
BENV="$TMP/bashenv-ran.log"
printf 'echo ran >> "%s"\n' "$BENV" > "$TMP/bashenv.sh"
BLOG="$TMP/bashenv-shim.log"; : > "$BLOG"; : > "$BENV"
WRAPGIT="$(shim bashenv --never-an-argument)"
scan "$R" "$(fx_list inert2 "$E1")" PATH="$WRAPGIT:$PATH" BASH_ENV="$TMP/bashenv.sh" SHIM_LOG="$BLOG"
expect_status "INERT2: a caller's BASH_ENV and a bash git wrapper — the scan runs, exit 1" 1 "$RC"
expect_eq "INERT2: (same run) it prints the hit" "HIT entry=1 at blob $(s12 "$R" HEAD:b.txt) line 1" "$(hits)"
expect_nonempty "INERT2: (same run) the git calls went through the bash wrapper" "$(cat "$BLOG")"
expect_eq "INERT2: (same run) BASH_ENV was read once, by the scan's own bash, never by the wrapper" "1" "$(wc -l < "$BENV" | tr -d ' ')"
NOBASHENV="$(doctor nobashenv 'unset BASH_ENV ENV' ':')"
expect_false "INERT2: the copy without the unset differs from the scan" cmp -s "$SCAN" "$NOBASHENV"
: > "$BENV"
scanx "$NOBASHENV" "$R" "$(fx_list inert2b "$E1")" PATH="$WRAPGIT:$PATH" BASH_ENV="$TMP/bashenv.sh"
expect_status "INERT2: the copy without the unset still runs (positive)" 1 "$RC"
expect_ne "INERT2: and without the unset every bash wrapper reads BASH_ENV (the row can fail)" "1" "$(wc -l < "$BENV" | tr -d ' ')"

section "§SIGNAL — TERM and HUP at any moment leave no temporary tree (T61 note)"

# fifty runs per signal, each killed after a random delay inside one measured run's length; the
# temp root is the run's own TMPDIR, read after the killed scan has exited
R="$TMP/sig1"; fx_repo "$R"
printf 'see %s\n' "$E3" > "$R/s.txt"; fx_commit "$R" "add s"
L="$(fx_list sig1 "$E3")"
ST="$TMP/sigtmp"; mkdir -p "$ST"
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
T0="$(now)"; scan "$R" "$L" TMPDIR="$ST"; T1="$(now)"
expect_status "SIGNAL: an unkilled run is a hit run (control)" 1 "$RC"
expect_empty "SIGNAL: and leaves nothing under its TMPDIR (control)" "$(ls -A "$ST")"
for sig in TERM HUP; do
  killed=0; left=0
  for k in $(seq 1 50); do
    d="$(perl -e 'printf "%.3f", rand($ARGV[0] - $ARGV[1])' "$T1" "$T0")"
    ( cd "$R" && TMPDIR="$ST" exec bash "$SCAN" "$L" >/dev/null 2>&1 ) & p=$!
    sleep "$d"; kill -"$sig" "$p" 2>/dev/null; wait "$p"; rc=$?
    [ "$rc" -gt 128 ] && killed=$((killed + 1))
    sleep 0.2
    if [ -n "$(ls -A "$ST")" ]; then left=$((left + 1)); rm -rf "${ST:?}"/*; fi
  done
  echo "SIGNAL: $sig — 50 runs, $killed ended by the signal, $left left a tree"
  expect_ne "SIGNAL: $sig — some of the 50 runs ended by the signal (positive)" "0" "$killed"
  expect_eq "SIGNAL: $sig — no run of the 50 left a tree under its TMPDIR" "0" "$left"
done

finish
