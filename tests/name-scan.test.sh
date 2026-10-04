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
