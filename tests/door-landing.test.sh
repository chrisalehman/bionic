#!/bin/bash
# Tests for the door: a landing pushed through the real hand door of a repository that carries the declared release
# check's whole closure, judged by that repository's own copy of the check (tests/lib/door.sh).
#
#   §LAND    a library row and then the release row land by hand. The release row carries the CHANGELOG entry
#            whose landing numbers `release-note` rendered and plugin.json at the version, so it is the carrier
#            the check must exempt: the landing publishes, the second run of the check passes and the plan row is
#            written, both runs are the fixture's copy, and the release-check verb at the landed head says the
#            numbers agree. The same landings under a copy whose carrier test quits at its match (`grep -qxF`)
#            leave the plan unwritten and the verb red; with a CHANGELOG that fits a pipe's buffer the same mutant
#            passes, so the size of the real file is what these rows exercise.
#   §COPY    a piece that rewrites tests/lib/release-check.sh to exit 0 and commits a listed name is refused
#            `check-failed` and nothing is merged, and the one run of the check is the target checkout's copy. A
#            driver that lands as the verb does refuses the same; with the door's check moved into the writer's
#            tree the target's copy never runs, and with the closure test gone as well the same piece publishes, so
#            these rows can fail.
#   §COPY-2  a piece that replaces the check with `exit 0`, or adds one comment line to it, and plants nothing: the
#            target's copy passes over its range, and the door still refuses it with judged-by and changed-here and
#            the person's route, nothing merged, the target's copy the one run. A piece that changes one code file
#            outside the closure lands, beside it, and so does one that changes a closure member outside the
#            directory of the declared script (payload/scripts/lib/said.sh): the arm reaches the check, not the code
#            it loads.
#   §COPY-3  the same pieces under a check declared by absolute path under the checkout: the closure reads that word as
#            the repository path it names, so the rewrite is refused as §COPY-2 refuses it and a code-only piece
#            lands; an absolute word outside the checkout (a prefix sibling, a path that only ends like a held one)
#            names no member.
#   §COPY-4  every word of the closure is read against the roots of the repository by one normalizer: a check declared
#            by the main checkout's absolute path and run from a landing tree (no checkout holds the branch), one
#            declared with `/./` or `//` in its path, and one whose helper beside it is sourced by absolute path: a
#            piece that rewrites the check, or the helper alone, is refused by name. A code-only piece from the
#            landing tree lands, and a word that leaves the root by `..`, or lies beside it, names no member.
#   §NAMED   the target's committed check carries a bug and a piece fixes it: the hand door refuses the fix with
#            `judged-by=target script=<path>@<accepted head> changed-here=<path>`, says a fix to the check cannot
#            pass its own door and names the person's route. With the arm deleted the refusal carries no field;
#            with the change read over the writer's head instead of the candidate, changed-here names a file the
#            candidate does not change.
#   §JUDGED  the same fix merged by a person and marked with `row-landed --by-hand`: the scan runs the landed copy
#            and the row's line says so, `judged-by=candidate`, where §LAND's release row, which changes no file
#            the check loads, says `judged-by=target`.
#   §HAND    a piece that plants a listed name and leaves the check alone is refused by `land --by-hand`, with no
#            changed-here; with the check's call deleted from the publish path, the same piece publishes.
#   §COVER   the release row, a doc row at step 7, lands with the release and a template outside the release set:
#            it publishes, and its landing prints the judge's cover over its own candidate naming the template. A
#            release whose every path is in the set lands with the cover read as release; the build row, none.
#   §RERENDER a fix row lands by hand past the landed release row: the line commits the refreshed landing numbers
#            on the working branch as its own commit, so the release check at the new head passes and the block
#            equals what `release-note` renders for the head and instant it names. With the renderer refusing
#            the plan, the landing is refused in the renderer's words and the branch does not move. While the
#            release row is open, a landing leaves CHANGELOG.md as it was.
#   §RATIO   the cap on tests at the door. On the fixture, whose shell lines under tests/ and elsewhere are measured and
#            printed first, a piece adding more test lines than the code has room for is refused `check-failed` with
#            the `test-ratio` line and nothing is published; the same piece with fewer test lines lands, beside it.
#   §RATIO-2 a fixture whose accepted head is already over the cap: the piece that cuts the test lines back under it is
#            admitted, and the declared check at the landed head prints the ratio.
#
# FIXTURE FIDELITY: every repository is a real `git init` under the world directory with real commits; the door is
# the tree under test's spawn-worktree.sh and session-poker.sh, run from the fixture with every variable that names
# the tree under test unset. Mutants are seds on a COPY of the fixture, committed there as its accepted head, or a
# sed over one function in a driver's own process; the tracked files are never written. SYNTHESIZED: the version,
# the listed name, the rows, and the template §COVER lands outside the release set.
#
# ANTI-VACUITY: with no fixture built the suite stops before its first section, having asserted nothing, which
# finish fails, so no row stands on an empty root (and no git command runs from the tree under test). Each sentinel read that expects nothing sits beside a
# read of the same file in the same fixture that expects a line; each mutant row first proves the mutant ran.
#
# Usage: bash tests/door-landing.test.sh
#
# pins: tests/lib/door.sh tests/lib/release-check.sh tests/lib/name-scan.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
DL_LOADED=0
# shellcheck source=/dev/null
. "$(dirname "$0")/lib/door.sh" && DL_LOADED=1
[ -n "${WORLD_ROOT:-}" ] || . "$(dirname "$0")/lib/world.sh"

setup_section "the door fixture, built once"

DW=""; DW_HEAD=""
DL_T0="$(date +%s)"
if [ "$DL_LOADED" = 1 ]; then read -r DW DW_HEAD <<EOF
$(door_world "$WORLD_ROOT/door")
EOF
fi
DL_BUILD=$(( $(date +%s) - DL_T0 ))
echo "door_world: built in ${DL_BUILD} s at ${DW:-<nothing>}"
if [ "$DL_LOADED" != 1 ] || [ -z "$DW" ] || [ ! -d "$DW/.git" ]; then
  finish
fi

dl_record() { cat "$1/.bionic/docs/record/wave-x/landing-proofs.log" 2>/dev/null; }   # <root>
dl_head() { git -C "$1" rev-parse --verify -q refs/heads/wave/x; }   # <root>
dl_plan_line() { /usr/bin/grep -E "^- $2:" "$1/$DOOR_PLAN_REL" 2>/dev/null; }   # <root> <row> -> its `- T<n>:` line
dl_commit() { _door_inside "$1" && git -C "$1" add -A >/dev/null 2>&1 && git -C "$1" commit --quiet -m "$2"; }   # <tree> <message>
# dl_lib_row <root> -> the library row T1 landed by hand: one commit to a file the check's closure holds.
dl_lib_row() {
  local p t0="$SECONDS"
  p="$(door_piece "$1" T1)" || return 1
  printf 'door_landed() { :; }\n' >> "$p/payload/scripts/lib/said.sh"
  dl_commit "$p" "a library change" && door_land "$1" "$p"
  echo "door: T1 landed by hand in $((SECONDS - t0)) s (rc ${DOOR_RC})"
}
# dl_release_row <root> -> DL_P2 the release row's tree, its release committed and landed by hand, the sentinel
# emptied first so it holds this landing's runs alone.
dl_release_row() {
  DL_P2="$(door_piece "$1" T2)" && door_release "$1" "$DL_P2" >/dev/null || return 1
  DL_P2_HEAD="$(git -C "$DL_P2" rev-parse HEAD)"
  : > "$DOOR_SEEN"
  local t0="$SECONDS"
  door_land "$1" "$DL_P2"
  echo "door: T2 landed by hand in $((SECONDS - t0)) s (rc ${DOOR_RC})"
}
# dl_mutant <root> — the carrier test planted back as a reader that quits at its match, committed as the head.
# dl_check <root> <base> <head> -> DOOR_OUT, DOOR_RC: the declared check run as the verb runs it, from the root,
# over <base>..<head>. The verb's own run is §LAND's; its report after a pass folds the whole changelog and costs a
# minute and more, so the mutant and the control read the check alone.
dl_check() {
  door_run "$1" env BIONIC_CHECK_BASE="$2" BIONIC_CHECK_HEAD="$3" BIONIC_CHECK_TREE="$1" bash tests/lib/release-check.sh "$DL_LIST"
}
dl_mutant() {
  _door_inside "$1" || return 1
  sed -i.orig 's|/usr/bin/grep -xF -- "\$2" >/dev/null|/usr/bin/grep -qxF -- "$2"|' "$1/tests/lib/release-check.sh" \
    && rm -f "$1/tests/lib/release-check.sh.orig" && dl_commit "$1" "the carrier test quits at its match"
}

# ---------------------------------------------------------------------------------------------------------------
section "§LAND: the release row lands by hand with the real changelog, and the check passes at the landed head"

# The list the world's declaration names: dl_check and §COPY run the check with it, as the declaration does.
DL_DECL="$(sed -n 's/^release-check: //p' "$DW/.bionic/config.yaml" 2>/dev/null)"
DL_LIST="${DL_DECL##* }"

read -r DL DL_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/land")
EOF
dl_lib_row "$DL"
expect_eq "(l0) precondition: the library row T1 lands by hand first, so the record holds a landing" "0" "$DOOR_RC"
DL_H1="$(dl_head "$DL")"
dl_release_row "$DL"
DL_OUT="$DOOR_OUT"; DL_RC="$DOOR_RC"; DL_H2="$(dl_head "$DL")"
expect_eq "(l1) land --by-hand of the release row exits 0" "0" "$DL_RC"
expect_contains "(l1b) …LANDED onto the working branch" "LANDED branch=wt/T2 onto=wave/x" "$DL_OUT"
expect_eq "(l2) the working branch moved to a merge of the release row's head onto the head before it" \
  "$DL_H1 $DL_P2_HEAD" "$(git -C "$DL" rev-parse "$DL_H2^1" "$DL_H2^2" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
expect_contains "(l3) the record holds the release row's published landing, by hand" \
  "line/v1|ev=published|row=T2|commit=$DL_H2|kind=hand|" "$(dl_record "$DL")"
expect_contains "(l4) the check's second run passed: the plan's T2 line is written landed by hand" \
  "landed-by-hand:" "$(dl_plan_line "$DL" T2)"
expect_absent "(l4b) …and the door printed no unwritten plan" "PLAN-UNWRITTEN" "$DL_OUT"
expect_eq "(l4c) the scan's copy is on each line: the release row changes nothing the check loads, the library row does" \
  "judged-by=target judged-by=candidate" \
  "$(dl_plan_line "$DL" T2 | /usr/bin/grep -o 'judged-by=[a-z]*$') $(dl_plan_line "$DL" T1 | /usr/bin/grep -o 'judged-by=[a-z]*$')"
DL_SEEN="$(door_seen)"
expect_eq "(l5) the check ran twice, before the fast-forward and at row-landed" "2" \
  "$(printf '%s\n' "$DL_SEEN" | /usr/bin/grep -c '^pwd=')"
expect_eq "(l5b) …both times the fixture's copy, in the fixture's checkout" \
  "pwd=$DL script=$DL/tests/lib/release-check.sh" "$(printf '%s\n' "$DL_SEEN" | sort -u)"
door_run "$DL" bash "$DOOR_POKER" release-check
expect_eq "(l6) session-poker.sh release-check at the landed head exits 0" "0" "$DOOR_RC"
DL_LOG="$DL/.bionic/docs/record/wave-x/release-check-$DL_H2.log"
expect_contains "(l7) …its log is the landed head's, with rc 0" "head=$DL_H2 rc=0" "$(cat "$DL_LOG" 2>/dev/null)"
expect_contains "(l7b) …and the landing numbers agree with the report" \
  "landing-numbers: $DOOR_VERSION agrees with the landing report at ${DL_H1:0:12}" "$(cat "$DL_LOG" 2>/dev/null)"
expect_contains "(l7c) …and the name scan is clean over the release range" "hits=0" "$(cat "$DL_LOG" 2>/dev/null)"
expect_eq "(l7d) …the verb's run is the fixture's copy too" "3 1" \
  "$(door_seen | /usr/bin/grep -c "^pwd=$DL script=$DL/tests/lib/release-check.sh\$") $(door_seen | sort -u | /usr/bin/grep -c .)"

# The carrier test planted back as `grep -qxF`: on the real changelog the reader quits at line 13 of a file far
# past a pipe's buffer, the writer dies of SIGPIPE, and pipefail makes the test false.
read -r DM DM_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/mutant")
EOF
dl_mutant "$DM"
expect_eq "(lm0) MUTANT precondition: the committed check's carrier test is the quitting reader" "1" \
  "$(git -C "$DM" show HEAD:tests/lib/release-check.sh | /usr/bin/grep -c 'grep -qxF -- "\$2"$')"
dl_lib_row "$DM"
DM_H1="$(dl_head "$DM")"
dl_release_row "$DM"
DM_OUT="$DOOR_OUT"; DM_H2="$(dl_head "$DM")"
expect_eq "(lm1) MUTANT the mutant ran: both runs are the mutant fixture's copy" \
  "pwd=$DM script=$DM/tests/lib/release-check.sh" "$(door_seen | sort -u)"
expect_contains "(lm2) MUTANT the second run refuses the carrier as a landing after the numbers" \
  "T2 landed after them at ${DM_H2:0:12}" "$DM_OUT"
expect_contains "(lm2b) MUTANT …and the plan row is not written" "PLAN-UNWRITTEN T2" "$DM_OUT"
expect_contains "(lm2c) MUTANT …T1's line, written by the same reader, is landed by hand" \
  "landed-by-hand:" "$(dl_plan_line "$DM" T1)"
expect_absent "(lm2d) MUTANT …T2's is not" "landed-by-hand:" "$(dl_plan_line "$DM" T2)"
dl_check "$DM" "$DM_H0" "$DM_H2"
expect_eq "(lm3) MUTANT the declared check at the landed head is red" "1" "$DOOR_RC"
expect_contains "(lm3b) MUTANT …naming the carrier" "T2 landed after them at ${DM_H2:0:12}" "$DOOR_OUT"

# The same mutant with a CHANGELOG that fits one pipe write: the reader takes the whole file before it quits.
read -r DS DS_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/small")
EOF
dl_mutant "$DS"
# One awk, no pipe into a reader that stops early: under pipefail that is the failure this control measures.
awk '/^## [0-9]/ { n++ } n < 2 && NR <= 40 { print }' "$DS/CHANGELOG.md" > "$DS/CHANGELOG.small" \
  && mv "$DS/CHANGELOG.small" "$DS/CHANGELOG.md" && dl_commit "$DS" "a changelog of a few lines"
DS_SIZE="$(git -C "$DS" cat-file -s HEAD:CHANGELOG.md 2>/dev/null || echo 0)"
expect_true "(ls0) CONTROL precondition: the small changelog fits a pipe's buffer (${DS_SIZE} bytes)" \
  [ "$DS_SIZE" -gt 0 -a "$DS_SIZE" -lt 65536 ]
dl_lib_row "$DS"
dl_release_row "$DS"
expect_contains "(ls1) CONTROL the same mutant passes the carrier when the changelog is small: T2 is written landed" \
  "landed-by-hand:" "$(dl_plan_line "$DS" T2)"
dl_check "$DS" "$DS_H0" "$(dl_head "$DS")"
expect_eq "(ls2) CONTROL …and the declared check at the landed head is green, so the red above is the file's size" "0" \
  "$DOOR_RC"
expect_contains "(ls2b) CONTROL …its numbers agreeing" "landing-numbers: $DOOR_VERSION agrees" "$DOOR_OUT"

# ---------------------------------------------------------------------------------------------------------------
section "§COPY: a piece that rewrites the check is judged by the target's copy and refused"

# dl_copy_piece <root> -> DL_PC: the row T1's tree, its check rewritten to pass and the listed name committed.
dl_copy_piece() {
  DL_PC="$(door_piece "$1" T1)" || return 1
  printf '#!/bin/bash\nexit 0\n' > "$DL_PC/tests/lib/release-check.sh"
  printf 'see %s\n' "$DOOR_NAME" > "$DL_PC/planted.txt"
  dl_commit "$DL_PC" "plant the name and tidy the check"
}
read -r DC DC_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/copy")
EOF
dl_copy_piece "$DC"
door_run "$DC" env BIONIC_CHECK_HEAD=HEAD bash "$DL_PC/tests/lib/release-check.sh" "$DL_LIST"
expect_eq "(c0) precondition: the piece's own copy passes, so a landing it judged would publish" "0" "$DOOR_RC"
DC_BLOB="$(git -C "$DL_PC" rev-parse HEAD:planted.txt | cut -c1-12)"
: > "$DOOR_SEEN"
door_land "$DC" "$DL_PC"
DC_OUT="$DOOR_OUT"
expect_eq "(c1) land --by-hand is refused (exit 2) and the working branch does not move" "2 $DC_H0" \
  "$DOOR_RC $(dl_head "$DC")"
expect_contains "(c1b) …by the declared check" \
  "REFUSED reason=check-failed why=release-check rc=1 branch=wt/T1 base=$DC_H0" "$DC_OUT"
expect_contains "(c2) …which names the planted blob" "HIT entry=1 at blob $DC_BLOB line 1" "$DC_OUT"
expect_absent "(c2b) …and prints no listed name" "$DOOR_NAME" "$DC_OUT"
expect_eq "(c3) the record holds T1's ready line and no published one" "1 0" \
  "$(dl_record "$DC" | /usr/bin/grep -c '^line/v1|ev=ready|row=T1|') $(dl_record "$DC" | /usr/bin/grep -c '^line/v1|ev=published|row=T1|')"
DC_SEEN="$(door_seen)"
expect_eq "(c4) the check ran once, as the target checkout holds it: the recorded pwd -P is the fixture's root" \
  "pwd=$DC script=$DC/tests/lib/release-check.sh" "$DC_SEEN"
expect_absent "(c4b) …never in the piece's tree" "$DL_PC" "$DC_SEEN"
expect_absent "(c4c) …nor the tree under test's" "$BIONIC_SCRIPTS_DIR" "$DC_SEEN"

# The verb's own land, in a process of its own, so one function can be replaced in it.
DL_DRIVER="$WORLD_ROOT/door-driver.sh"
cat > "$DL_DRIVER" <<'DRIVER'
#!/bin/bash
# <lib dir> <tree> <why>: `land <tree> --by-hand` as spawn-worktree.sh's land calls it. DOOR_MUTANT, when set, is a
# sed over DOOR_MUTANT_FN (by default _wt_release_check); a sed that changes nothing exits 98, so a mutant row never
# stands on the real function.
. "$1/worktree.sh" && . "$1/session.sh" && . "$1/line.sh" || exit 99
if [ -n "${DOOR_MUTANT:-}" ]; then
  fn="${DOOR_MUTANT_FN:-_wt_release_check}"
  m="$(declare -f "$fn" | sed "$DOOR_MUTANT")"
  [ "$m" != "$(declare -f "$fn")" ] || exit 98
  eval "$m"
fi
line_land_by_hand "$2" "$(worktree_root "$2")" "$(session_id)" "$3"
DRIVER
read -r DD DD_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/driver")
EOF
dl_copy_piece "$DD"
: > "$DOOR_SEEN"
door_run "$DD" bash "$DL_DRIVER" "$BIONIC_SCRIPTS_DIR/payload/scripts/lib" "$DL_PC" "door fixture"
expect_eq "(cd1) the driver, unmutated, is refused as the verb is: exit 2, the branch unmoved" "2 $DD_H0" \
  "$DOOR_RC $(dl_head "$DD")"
expect_eq "(cd1b) …and the check it ran is the target's" "pwd=$DD script=$DD/tests/lib/release-check.sh" "$(door_seen)"
: > "$DOOR_SEEN"
door_run "$DD" env 'DOOR_MUTANT=s|cd "$co"|cd "$wt_abs"|' \
  bash "$DL_DRIVER" "$BIONIC_SCRIPTS_DIR/payload/scripts/lib" "$DL_PC" "door fixture"
expect_contains "(cdm) MUTANT the check run in the writer tree: the mutant ran, refused by the closure test alone" \
  "REFUSED reason=check-failed why=release-check rc=0 branch=wt/T1" "$DOOR_OUT"
expect_eq "(cdm-a) MUTANT …and the copy the target holds never ran, so (c4) and (cd1b) read a run that is not there" "" "$(door_seen)"
: > "$DOOR_SEEN"
door_run "$DD" env 'DOOR_MUTANT=s|cd "$co"|cd "$wt_abs"|; s|_wt_check_judge "$co"|false "$co"|' \
  bash "$DL_DRIVER" "$BIONIC_SCRIPTS_DIR/payload/scripts/lib" "$DL_PC" "door fixture"
expect_eq "(cdm-b) MUTANT with the closure test gone as well, the copy in the piece judges and the landing publishes" "0" \
  "$DOOR_RC"
expect_eq "(cdm-c) MUTANT …the working branch now holds the planted blob" "$DC_BLOB" \
  "$(git -C "$DD" rev-parse "$(dl_head "$DD"):planted.txt" 2>/dev/null | cut -c1-12)"
expect_eq "(cdm-d) MUTANT …and the copy the target holds never ran" "" "$(door_seen)"

# ---------------------------------------------------------------------------------------------------------------
section "§COPY-2: a piece that changes the check and plants nothing is judged by the copy the target holds and refused"

# The target's copy passes over these ranges, so only the closure test can refuse them: the check that ran is not the
# check the candidate carries, and a passing run of the old copy says nothing of the new one.
DL_LIBDIR="$BIONIC_SCRIPTS_DIR/payload/scripts/lib"
DL_CODE=payload/scripts/lib/notify.sh
DL_LIB=payload/scripts/lib/said.sh
# dl_copy2 <dir> <what> -> DQ, DQ_H0 a copy of its own, DL_QP the row T1's tree with <what> done and committed, the
# target's own copy then run over the candidate's range (DQ_RC), and the sentinel emptied for the landing alone.
dl_copy2() {
  read -r DQ DQ_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/$1")
EOF
  DL_QP="$(door_piece "$DQ" T1)" || return 1
  case "$2" in
    rewrite) printf '#!/bin/bash\nexit 0\n' > "$DL_QP/tests/lib/release-check.sh" ;;
    comment) printf '# a note on the check\n' >> "$DL_QP/tests/lib/release-check.sh" ;;
    code) printf 'door_noted() { :; }\n' >> "$DL_QP/$DL_CODE" ;;
    library) printf 'door_landed() { :; }\n' >> "$DL_QP/$DL_LIB" ;;
  esac
  dl_commit "$DL_QP" "the piece: $2" || return 1
  dl_check "$DQ" "$DQ_H0" "$(git -C "$DL_QP" rev-parse HEAD)"; DQ_RC="$DOOR_RC"
  : > "$DOOR_SEEN"
}
# dl_judged <label> <root> <head0>: the refusal rows a piece that changes the check meets, with the target's copy
# passing, read from DOOR_OUT and DOOR_RC.
dl_judged() {
  expect_eq "($1a) land --by-hand is refused (exit 2) and the working branch does not move" "2 $3" "$DOOR_RC $(dl_head "$2")"
  expect_contains "($1b) …by the declared check, whose run passed" \
    "REFUSED reason=check-failed why=release-check rc=0 branch=wt/T1 base=$3" "$DOOR_OUT"
  expect_contains "($1c) …naming the judge at the accepted head and the one file of it this landing changes" \
    "judged-by=target script=tests/lib/release-check.sh@${3:0:12} changed-here=tests/lib/release-check.sh —" "$DOOR_OUT"
  expect_contains "($1d) …and the route a person takes" \
    "merge wt/T1 into wave/x with git, then session-poker.sh row-landed T1 <merge> <at> --by-hand" "$DOOR_OUT"
  expect_eq "($1e) the record holds a ready line for T1 and no published one" "1 0" \
    "$(dl_record "$2" | /usr/bin/grep -c '^line/v1|ev=ready|row=T1|') $(dl_record "$2" | /usr/bin/grep -c '^line/v1|ev=published|row=T1|')"
  expect_eq "($1f) the check ran once, the copy the target holds, in the target checkout" \
    "pwd=$2 script=$2/tests/lib/release-check.sh" "$(door_seen)"
}

dl_copy2 copy2-rewrite rewrite
expect_eq "(c2-1-0) precondition: the copy the target holds passes over the range of the piece that replaces it with exit 0" \
  "0 1" "$DQ_RC $(git -C "$DL_QP" show HEAD:tests/lib/release-check.sh | /usr/bin/grep -cx 'exit 0')"
door_land "$DQ" "$DL_QP"
dl_judged c2-1 "$DQ" "$DQ_H0"
expect_eq "(c2-1g) the working head still carries the check the target held, its sentinel line after the shebang" "1" \
  "$(git -C "$DQ" show "$(dl_head "$DQ"):tests/lib/release-check.sh" | /usr/bin/grep -c 'DOOR_SEEN')"

dl_copy2 copy2-comment comment
expect_eq "(c2-2-0) precondition: the copy the target holds passes over the range of the piece that adds one comment line to it" \
  "0 1" "$DQ_RC $(git -C "$DQ" diff --numstat "$DQ_H0" "$(git -C "$DL_QP" rev-parse HEAD)" -- tests/lib/release-check.sh | awk '{ print $1 }')"
door_land "$DQ" "$DL_QP"
dl_judged c2-2 "$DQ" "$DQ_H0"

dl_copy2 copy2-code code
DQ_CL="$( (. "$DL_LIBDIR/worktree.sh" >/dev/null 2>&1; _wt_check_closure "$DQ" "$DQ_H0" "$DL_DECL") )"
expect_contains "(c2-3-0) CONTROL precondition: the closure read at the accepted head holds the check" \
  "tests/lib/release-check.sh" "$DQ_CL"
expect_absent "(c2-3-0b) CONTROL …and not the code file the piece changes" "$DL_CODE" "$DQ_CL"
expect_eq "(c2-3-0c) CONTROL …over whose range the copy the target holds passes" "0" "$DQ_RC"
door_land "$DQ" "$DL_QP"
expect_eq "(c2-3) CONTROL the piece that changes one code file and no member of the closure lands by hand (exit 0)" \
  "0" "$DOOR_RC"
expect_contains "(c2-3b) CONTROL …LANDED onto the working branch" "LANDED branch=wt/T1 onto=wave/x" "$DOOR_OUT"
expect_absent "(c2-3c) CONTROL …with no judged-by refusal" "changed-here=" "$DOOR_OUT"

# The edge on the other side: project code the check loads, outside the directory of the declared script, keeps the
# plain arms, so a piece that changes it lands while the copy the target holds passes.
dl_copy2 copy2-library library
DQ_CL="$( (. "$DL_LIBDIR/worktree.sh" >/dev/null 2>&1; _wt_check_closure "$DQ" "$DQ_H0" "$DL_DECL") )"
expect_eq "(c2-4-0) precondition: the closure holds the library file the piece changes, and the check passes over its range" \
  "1 0" "$(printf '%s\n' "$DQ_CL" | /usr/bin/grep -cxF "$DL_LIB") $DQ_RC"
door_land "$DQ" "$DL_QP"
expect_eq "(c2-4) a piece that changes a closure member outside the directory of the check lands by hand (exit 0)" \
  "0" "$DOOR_RC"
expect_contains "(c2-4b) …LANDED onto the working branch" "LANDED branch=wt/T1 onto=wave/x" "$DOOR_OUT"
expect_absent "(c2-4c) …with no judged-by refusal" "changed-here=" "$DOOR_OUT"

# ---------------------------------------------------------------------------------------------------------------
section "§COPY-3: a check declared by absolute path has the same closure as one declared relative"

# The door runs the declaration in the target checkout, so an absolute path under that checkout names the same file
# as the relative one, and the always-refuse arm must judge it.
dl_abs() { printf 'release-check: bash %s %s\n' "$2" "$DL_LIST" > "$1/.bionic/config.yaml"; }   # <root> <script word>

dl_copy2 copy3-rewrite rewrite
dl_abs "$DQ" "$DQ/tests/lib/release-check.sh"
DQ_CL="$( (. "$DL_LIBDIR/worktree.sh" >/dev/null 2>&1; _wt_check_closure "$DQ" "$DQ_H0" "bash $DQ/tests/lib/release-check.sh $DL_LIST") )"
expect_eq "(c3-1-0) precondition: the closure of the absolute declaration holds the check, as the relative one does, and the target's copy passes over the piece" \
  "1 0" "$(printf '%s\n' "$DQ_CL" | /usr/bin/grep -cxF tests/lib/release-check.sh) $DQ_RC"
door_land "$DQ" "$DL_QP"
dl_judged c3-1 "$DQ" "$DQ_H0"

dl_copy2 copy3-code code
dl_abs "$DQ" "$DQ/tests/lib/release-check.sh"
door_land "$DQ" "$DL_QP"
expect_eq "(c3-2) CONTROL the same absolute declaration and a piece that changes one code file: lands by hand (exit 0)" \
  "0" "$DOOR_RC"
expect_contains "(c3-2b) CONTROL …LANDED onto the working branch" "LANDED branch=wt/T1 onto=wave/x" "$DOOR_OUT"
expect_absent "(c3-2c) CONTROL …with no judged-by refusal" "changed-here=" "$DOOR_OUT"

# A word outside the checkout names no member: one that only shares the checkout name as a prefix (the fixture's own
# list is such a sibling), one whose tail repeats a path the commit holds, and one before the real script.
dl_c3_closure() { ( . "$DL_LIBDIR/worktree.sh" >/dev/null 2>&1; _wt_check_closure "$DQ" "$DQ_H0" "$1"; echo "rc=$?" ); }   # <declaration>
DQ_IN="$(dl_c3_closure "bash $DQ/tests/lib/release-check.sh $DL_LIST")"
expect_contains "(c3-3-0) CONTROL precondition: the closure of the declaration inside the checkout holds the check" \
  "tests/lib/release-check.sh" "$DQ_IN"
DQ_OUT="$(dl_c3_closure "bash ${DQ}-names.list")"
expect_eq "(c3-3a) a declaration whose absolute word shares only the checkout's name as a prefix names no member (rc 1)" "rc=1" "$DQ_OUT"
DQ_OUT="$(dl_c3_closure "bash /nonexistent-c3/tests/lib/release-check.sh")"
expect_eq "(c3-3b) a declaration whose absolute word outside the checkout ends in a path the commit holds names no member (rc 1)" \
  "rc=1" "$DQ_OUT"
DQ_OUT="$(dl_c3_closure "bash /nonexistent-c3/x.sh tests/lib/release-check.sh")"
expect_eq "(c3-3c) …and it is skipped, not the end of the declaration: a relative script after it is the member" \
  "tests/lib/release-check.sh rc=0" "$(printf '%s\n' "$DQ_OUT" | /usr/bin/grep -xF -e tests/lib/release-check.sh -e rc=0 | paste -sd' ' -)"

# ---------------------------------------------------------------------------------------------------------------
section "§COPY-4: every word of the closure is read against the roots of the repository by one normalizer"

# The declaration is read from the main checkout, and the door runs it in the checkout that holds the branch or, when
# none does, in a landing tree pointed at the accepted head: an absolute word under the main checkout names the same
# file from either. The file a word names is a member whatever its spelling, and so is a file a member sources by
# absolute path; a word outside every root names none.
dl_detach() { _door_inside "$1" && git -C "$1" checkout --quiet --detach; }   # <root>: no checkout holds wave/x
dl_c4_closure() { ( . "$DL_LIBDIR/worktree.sh" >/dev/null 2>&1; _wt_check_closure "$1" "$DQ_H0" "$2"; echo "rc=$?" ); }   # <run dir> <declaration>

dl_copy2 copy4-tree rewrite
dl_abs "$DQ" "$DQ/tests/lib/release-check.sh"
dl_detach "$DQ"
expect_eq "(c4-1-0) precondition: no checkout holds the working branch, and the target copy passes over the piece" \
  "1 0" "$( (. "$DL_LIBDIR/worktree.sh" >/dev/null 2>&1; worktree_checkout_of "$DQ" wave/x >/dev/null; echo $?) ) $DQ_RC"
door_land "$DQ" "$DL_QP"
expect_eq "(c4-1a) land --by-hand of the rewrite, judged from a landing tree, is refused (exit 2) and the branch does not move" \
  "2 $DQ_H0" "$DOOR_RC $(dl_head "$DQ")"
expect_contains "(c4-1b) …by the declared check, whose run passed" \
  "REFUSED reason=check-failed why=release-check rc=0 branch=wt/T1 base=$DQ_H0" "$DOOR_OUT"
expect_contains "(c4-1c) …naming the judge by its repository path and the one file of it this landing changes" \
  "judged-by=target script=tests/lib/release-check.sh@${DQ_H0:0:12} changed-here=tests/lib/release-check.sh —" "$DOOR_OUT"
DQ_SEEN="$(door_seen)"
expect_eq "(c4-1d) the check ran once, from a landing tree under the root" \
  "1 1" "$(printf '%s\n' "$DQ_SEEN" | /usr/bin/grep -c .) $(printf '%s\n' "$DQ_SEEN" | /usr/bin/grep -c "^pwd=$DQ/.bionic/tmp/landing/[0-9]* ")"
expect_contains "(c4-1e) …and the copy it ran is the one the absolute word names, the main checkout copy" \
  " script=$DQ/tests/lib/release-check.sh" "$DQ_SEEN"

dl_copy2 copy4-dot rewrite
dl_abs "$DQ" "$DQ/./tests/lib/release-check.sh"
door_land "$DQ" "$DL_QP"
dl_judged c4-2 "$DQ" "$DQ_H0"

dl_copy2 copy4-slash rewrite
dl_abs "$DQ" "$DQ//tests/lib/release-check.sh"
door_land "$DQ" "$DL_QP"
dl_judged c4-2s "$DQ" "$DQ_H0"

# The target check sources a helper beside it by absolute path; the piece changes the helper alone.
read -r DQ DQ_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/copy4-load")
EOF
DL_HELP=tests/lib/door-helper.sh
printf 'door_helped() { :; }\n' > "$DQ/$DL_HELP"
awk -v h="$DQ/$DL_HELP" 'NR == 2 { print; print ". \"" h "\""; next } { print }' "$DQ/tests/lib/release-check.sh" \
  > "$DQ/tests/lib/release-check.sh.new" && mv "$DQ/tests/lib/release-check.sh.new" "$DQ/tests/lib/release-check.sh" \
  && chmod +x "$DQ/tests/lib/release-check.sh" && dl_commit "$DQ" "the check sources a helper by absolute path"
DQ_H0="$(dl_head "$DQ")"
DL_QP="$(door_piece "$DQ" T1)"
printf '# a note on the helper\n' >> "$DL_QP/$DL_HELP"
dl_commit "$DL_QP" "the piece: the helper alone"
dl_check "$DQ" "$DQ_H0" "$(git -C "$DL_QP" rev-parse HEAD)"; DQ_RC="$DOOR_RC"
expect_eq "(c4-3-0) precondition: the target check sources the helper by absolute path, the piece changes the helper alone, and the target copy passes over it" \
  "1 $DL_HELP 0" "$(git -C "$DQ" show "$DQ_H0:tests/lib/release-check.sh" | /usr/bin/grep -cxF ". \"$DQ/$DL_HELP\"") $(git -C "$DQ" diff --name-only "$DQ_H0" "$(git -C "$DL_QP" rev-parse HEAD)") $DQ_RC"
: > "$DOOR_SEEN"
door_land "$DQ" "$DL_QP"
expect_eq "(c4-3a) land --by-hand of the helper change is refused (exit 2) and the working branch does not move" \
  "2 $DQ_H0" "$DOOR_RC $(dl_head "$DQ")"
expect_contains "(c4-3b) …by the declared check, whose run passed" \
  "REFUSED reason=check-failed why=release-check rc=0 branch=wt/T1 base=$DQ_H0" "$DOOR_OUT"
expect_contains "(c4-3c) …naming the helper as the file of the judge this landing changes" \
  "judged-by=target script=tests/lib/release-check.sh@${DQ_H0:0:12} changed-here=$DL_HELP —" "$DOOR_OUT"
expect_eq "(c4-3d) the check ran once, the copy the target holds, in the target checkout" \
  "pwd=$DQ script=$DQ/tests/lib/release-check.sh" "$(door_seen)"

dl_copy2 copy4-code code
dl_abs "$DQ" "$DQ/tests/lib/release-check.sh"
dl_detach "$DQ"
door_land "$DQ" "$DL_QP"
expect_eq "(c4-4a) CONTROL the absolute declaration from a landing tree and a piece that changes one code file: lands by hand (exit 0)" \
  "0" "$DOOR_RC"
expect_contains "(c4-4b) CONTROL …LANDED onto the working branch" "LANDED branch=wt/T1 onto=wave/x" "$DOOR_OUT"
expect_absent "(c4-4c) CONTROL …with no judged-by refusal" "changed-here=" "$DOOR_OUT"
DQ_LT="$(cd "$DQ/.bionic/tmp/landing" 2>/dev/null && for t in */; do [ -e "$t.git" ] && { printf '%s' "$PWD/${t%/}"; break; }; done)"
DQ_IN="$(dl_c4_closure "$DQ_LT" "bash $DQ/tests/lib/release-check.sh $DL_LIST")"
expect_contains "(c4-4d-0) CONTROL precondition: run from the landing tree the door used, the closure of the word under the main root holds the check" \
  "tests/lib/release-check.sh" "$DQ_IN"
expect_eq "(c4-4d) CONTROL …while a word that leaves the root by .. names no member (rc 1)" \
  "rc=1" "$(dl_c4_closure "$DQ_LT" "bash $DQ/../elsewhere/tests/lib/release-check.sh")"
expect_eq "(c4-4e) CONTROL …and so does a list beside the root, outside every root (rc 1)" \
  "rc=1" "$(dl_c4_closure "$DQ_LT" "bash ${DQ}-names.list")"

# ---------------------------------------------------------------------------------------------------------------
section "§NAMED: a landing that changes the check which judges it is refused naming the judge, the change and the route"

# dl_named <root> -> DL_NP, the row T1's tree, and DL_NH1, the accepted head. The target's committed check carries a
# bug (it exits 3 after the sentinel); T1 restores the check and marks its own sentinel line `copy=fix`; then a
# person's commit to the name scan moves the accepted head past T1's base, so the writer's head and the candidate
# disagree on that one file.
dl_named() {
  local c="$1/tests/lib/release-check.sh"
  _door_inside "$1" || return 1
  awk 'NR == 2 { print; print "exit 3"; next } { print }' "$c" > "$c.bug" && mv "$c.bug" "$c" \
    && dl_commit "$1" "the check carries a bug" || return 1
  DL_NP="$(door_piece "$1" T1)" || return 1
  git -C "$1" show "$DW_HEAD:tests/lib/release-check.sh" | sed '2s/script=%s\\n/script=%s copy=fix\\n/' \
    > "$DL_NP/tests/lib/release-check.sh" && dl_commit "$DL_NP" "the check's bug fixed" || return 1
  printf '# a note\n' >> "$1/tests/lib/name-scan.sh" && dl_commit "$1" "a note in the name scan" || return 1
  DL_NH1="$(dl_head "$1")"
}
read -r DN DN_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/named")
EOF
dl_named "$DN"
DN_JUDGE="judged-by=target script=tests/lib/release-check.sh@${DL_NH1:0:12} changed-here=tests/lib/release-check.sh —"
expect_eq "(n0) precondition: the piece's copy carries the fix's mark, the target's the bug" "1 1" \
  "$(/usr/bin/grep -c 'copy=fix' "$DL_NP/tests/lib/release-check.sh") $(/usr/bin/grep -cx 'exit 3' "$DN/tests/lib/release-check.sh")"
: > "$DOOR_SEEN"
door_land "$DN" "$DL_NP"
DN_OUT="$DOOR_OUT"
expect_eq "(n1) land --by-hand of the fix is refused (exit 2) and the working branch does not move" "2 $DL_NH1" \
  "$DOOR_RC $(dl_head "$DN")"
expect_contains "(n1b) …by the declared check, over the accepted head" \
  "REFUSED reason=check-failed why=release-check rc=3 branch=wt/T1 base=$DL_NH1" "$DN_OUT"
expect_contains "(n2) …naming the judge, its copy at the accepted head, and the one file of it this landing changes" \
  "$DN_JUDGE" "$DN_OUT"
expect_contains "(n3) …saying a fix to the check cannot pass its own door" "a fix to the check cannot pass its own door" \
  "$DN_OUT"
expect_contains "(n4) …and naming the route a person takes" \
  "merge wt/T1 into wave/x with git, then session-poker.sh row-landed T1 <merge> <at> --by-hand" "$DN_OUT"
expect_eq "(n5) the one run of the check is the target's copy, without the fix's mark" \
  "pwd=$DN script=$DN/tests/lib/release-check.sh" "$(door_seen)"

: > "$DOOR_SEEN"
door_run "$DN" env 'DOOR_MUTANT=s|_wt_check_judge "$co"|false "$co"|' bash "$DL_DRIVER" "$DL_LIBDIR" "$DL_NP" "door fixture"
expect_eq "(nm1) MUTANT the arm deleted: the mutant ran, refused by the target's copy as before" \
  "2 pwd=$DN script=$DN/tests/lib/release-check.sh" "$DOOR_RC $(door_seen)"
expect_contains "(nm1b) MUTANT …its refusal is the check's" "REFUSED reason=check-failed why=release-check rc=3" "$DOOR_OUT"
expect_absent "(nm1c) MUTANT …and carries no judged-by field" "judged-by=" "$DOOR_OUT"
door_run "$DN" env 'DOOR_MUTANT=s|_wt_check_judge "$co" "$onto_head" "$head"|_wt_check_judge "$co" "$onto_head" "$(git -C "$wt_abs" rev-parse HEAD)"|' \
  bash "$DL_DRIVER" "$DL_LIBDIR" "$DL_NP" "door fixture"
expect_contains "(nm2) MUTANT the change read over the writer's head: changed-here names the person's note as well" \
  "changed-here=tests/lib/name-scan.sh,tests/lib/release-check.sh —" "$DOOR_OUT"
expect_absent "(nm2b) MUTANT …so the line (n2) reads is not there" "$DN_JUDGE" "$DOOR_OUT"

# ---------------------------------------------------------------------------------------------------------------
section "§JUDGED: the fix merged by a person and marked by hand records on its line which copy judged it"

: > "$DOOR_SEEN"
git -C "$DN" merge --no-ff -q -m "merge wt/T1 by hand" wt/T1 >/dev/null 2>&1
DN_M="$(dl_head "$DN")"
DN_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
expect_eq "(j0) precondition: the person's merge holds the fix on the working branch" "$DL_NH1 $(git -C "$DL_NP" rev-parse HEAD)" \
  "$(git -C "$DN" rev-parse "$DN_M^1" "$DN_M^2" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
door_run "$DN" bash "$DOOR_POKER" row-landed T1 "$DN_M" "$DN_AT" --by-hand door "a fix to the check lands by a person"
expect_eq "(j1) row-landed --by-hand of the merged fix exits 0" "0" "$DOOR_RC"
expect_contains "(j2) T1's line is landed by hand and names the copy that judged it: the landed one, the candidate's" \
  "landed-by-hand: door $DN_AT \"a fix to the check lands by a person\" judged-by=candidate" "$(dl_plan_line "$DN" T1)"
expect_eq "(j3) …and the scan's one run is that copy, the fix's mark, in the fixture's checkout" \
  "pwd=$DN script=$DN/tests/lib/release-check.sh copy=fix" "$(door_seen)"

# ---------------------------------------------------------------------------------------------------------------
section "§HAND: the hand route meets the check: a planted name is refused, and without the check's call it publishes"

read -r DH DH_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/hand")
EOF
DL_HP="$(door_piece "$DH" T1)"
printf 'see %s\n' "$DOOR_NAME" > "$DL_HP/planted.txt" && dl_commit "$DL_HP" "plant the name"
DH_BLOB="$(git -C "$DL_HP" rev-parse HEAD:planted.txt | cut -c1-12)"
: > "$DOOR_SEEN"
door_land "$DH" "$DL_HP"
expect_eq "(h1) land --by-hand of a planted name is refused (exit 2) and the working branch does not move" "2 $DH_H0" \
  "$DOOR_RC $(dl_head "$DH")"
expect_contains "(h1b) …check-failed, naming the planted blob" "HIT entry=1 at blob $DH_BLOB line 1" "$DOOR_OUT"
expect_contains "(h1c) …by the declared check" "REFUSED reason=check-failed why=release-check rc=1 branch=wt/T1" "$DOOR_OUT"
expect_absent "(h1d) …which this landing leaves alone, so no changed-here" "changed-here=" "$DOOR_OUT"
expect_eq "(h2) the check ran, the target's copy" "pwd=$DH script=$DH/tests/lib/release-check.sh" "$(door_seen)"
: > "$DOOR_SEEN"
door_run "$DH" env DOOR_MUTANT_FN=line_publish 'DOOR_MUTANT=s|_wt_release_check "$root"|: "$root"|' \
  bash "$DL_DRIVER" "$DL_LIBDIR" "$DL_HP" "door fixture"
DH_OUT="$DOOR_OUT"
expect_eq "(hm1) MUTANT the check's call deleted from the publish path: the working branch holds the planted blob" \
  "$DH_BLOB" "$(git -C "$DH" rev-parse "$(dl_head "$DH"):planted.txt" 2>/dev/null | cut -c1-12)"
expect_contains "(hm1b) MUTANT …published by hand" "line/v1|ev=published|row=T1|commit=$(dl_head "$DH")|kind=hand|" \
  "$(dl_record "$DH")"
expect_absent "(hm1c) MUTANT …with no refusal by the door's check" "REFUSED reason=check-failed" "$DH_OUT"

# ---------------------------------------------------------------------------------------------------------------
section "§COVER: the release row's landing reads the judge's cover over its own candidate and names a path outside the set"

# dl_cover_world <dir> -> DV, the root of a copy whose T2 is the release row (a doc row at step 7, the plan's own
# reading of it), with the library row T1 landed ahead of it; DV_T1_OUT, what T1's landing printed.
dl_cover_world() {
  read -r DV DV_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/$1")
EOF
  sed -i.orig 's/^| T2 | 4 | doc |/| T2 | 7 | doc |/' "$DV/$DOOR_PLAN_REL" && rm -f "$DV/$DOOR_PLAN_REL.orig"
  dl_lib_row "$DV"; DV_T1_RC="$DOOR_RC"; DV_T1_OUT="$DOOR_OUT"
}
DL_TMPL=agents-src/templates/commands/help.md.tmpl
dl_cover_world cover-out
expect_eq "(v0) precondition: T2 is a doc row at step 7, the release row, and T1 landed ahead of it" "1 0" \
  "$(/usr/bin/grep -c '^| T2 | 7 | doc |' "$DV/$DOOR_PLAN_REL") $DV_T1_RC"
DL_P2="$(door_piece "$DV" T2)" && door_release "$DV" "$DL_P2" >/dev/null
mkdir -p "$DL_P2/${DL_TMPL%/*}" && printf 'the help page, before it is rendered\n' > "$DL_P2/$DL_TMPL"
dl_commit "$DL_P2" "the help page's template"
door_land "$DV" "$DL_P2"
DV_OUT="$DOOR_OUT"; DV_H="$(dl_head "$DV")"
expect_eq "(v1) the release row carrying a template outside the release set lands by hand (exit 0)" "0" "$DOOR_RC"
expect_contains "(v1b) …onto the working branch" "LANDED branch=wt/T2 onto=wave/x" "$DV_OUT"
expect_contains "(v2) …and its landing names the path outside the set, read over its own candidate, the landed merge" \
  "COVER T2 $DV_H owes outside=$DL_TMPL" "$DV_OUT"
expect_absent "(v2b) …while T1, a build row, landed in the same fixture with no cover line" "COVER " "$DV_T1_OUT"

dl_cover_world cover-in
DL_P2="$(door_piece "$DV" T2)" && door_release "$DV" "$DL_P2" >/dev/null
door_land "$DV" "$DL_P2"
expect_eq "(v3) CONTROL the release row whose every path is in the set lands by hand (exit 0)" "0" "$DOOR_RC"
expect_contains "(v3b) CONTROL …and its landing reads the cover over its candidate as release" \
  "COVER T2 $(dl_head "$DV") release" "$DOOR_OUT"


# ---------------------------------------------------------------------------------------------------------------
section "§RERENDER: a row landing past the landed release has its release numbers rendered and committed by the line"

# dl_rr_world <dir> -> DR, DR_H0: a copy whose T2 is the release row (a doc row at step 7) and whose plan gains the
# fix row T3, one code file; with RR_RELEASE=1, T1 and then the release row T2 land by hand first (DR_T1_RC, DR_T2_RC,
# DR_H2 the head after the release).
dl_rr_world() {
  read -r DR DR_H0 <<EOF2
$(door_copy "$DW" "$WORLD_ROOT/$1")
EOF2
  awk '{ sub(/^\| T2 \| 4 \| doc \|/, "| T2 | 7 | doc |"); print }
    /^\| T2 \| 7 \| doc \|/ { print "| T3 | 4 | build | a fix after the release | dw-T3 | — | | 10 | REQ-1 | fix.sh | .worktrees/T3 | | active |" }
    /^- T2: active$/ { print "- T3: active" }' "$DR/$DOOR_PLAN_REL" > "$DR/$DOOR_PLAN_REL.new" \
    && mv "$DR/$DOOR_PLAN_REL.new" "$DR/$DOOR_PLAN_REL"
  DR_T1_RC=-; DR_T2_RC=-; DR_H2="$DR_H0"
  [ "${RR_RELEASE:-0}" = 1 ] || return 0
  dl_lib_row "$DR"; DR_T1_RC="$DOOR_RC"
  dl_release_row "$DR"; DR_T2_RC="$DOOR_RC"; DR_H2="$(dl_head "$DR")"
}
# dl_fix_row <root> -> DL_P3, the fix row T3's tree, one code file committed (DL_P3_HEAD), landed by hand.
dl_fix_row() {
  DL_P3="$(door_piece "$1" T3)" || return 1
  printf 'door_fixed() { :; }\n' > "$DL_P3/fix.sh" && dl_commit "$DL_P3" "the fix after the release" || return 1
  DL_P3_HEAD="$(git -C "$DL_P3" rev-parse HEAD)"
  door_land "$1" "$DL_P3"
}
# dl_numbers <root> <rev> -> the release entry part `### The landing numbers` of CHANGELOG.md at <rev>, its heading
# included, up to the next heading of another name.
dl_numbers() {
  git -C "$1" show "$2:CHANGELOG.md" 2>/dev/null | awk -v v="## $DOOR_VERSION " '
    /^## / { inb = (index($0, v) == 1); inp = 0 }
    inb && /^### / { t = $0; sub(/[[:space:]]+$/, "", t); inp = (t == "### The landing numbers") }
    inb && inp'
}
dl_published() { dl_record "$1" | /usr/bin/grep -F "line/v1|ev=published|row=$2|"; }   # <root> <row>

RR_RELEASE=1 dl_rr_world rerender
expect_eq "(rr0) precondition: T2 is the release row and the plan holds T3; T1 and the release row landed by hand" \
  "1 1 0 0" "$(/usr/bin/grep -c '^| T2 | 7 | doc |' "$DR/$DOOR_PLAN_REL") $(/usr/bin/grep -c '^| T3 | 4 | build |' "$DR/$DOOR_PLAN_REL") $DR_T1_RC $DR_T2_RC"
DR_OLD="$(dl_numbers "$DR" "$DR_H2")"
expect_contains "(rr0b) precondition: the release head carries numbers rendered at the head before it" \
  "\`landing-report --rows\` at $(git -C "$DR" rev-parse "$DR_H2^1") on " "$DR_OLD"
dl_fix_row "$DR"
DR_OUT="$DOOR_OUT"; DR_RC="$DOOR_RC"; DR_H3="$(dl_head "$DR")"
DR_C3="$(git -C "$DR" rev-parse --verify -q "$DR_H3^1" 2>/dev/null)"
expect_eq "(rr1) the fix row lands by hand past the release (exit 0)" "0" "$DR_RC"
expect_contains "(rr1b) …onto the working branch" "LANDED branch=wt/T3 onto=wave/x" "$DR_OUT"
expect_eq "(rr1c) the head is one commit on the published candidate, the merge of the fix onto the release head" \
  "$DR_H2 $DL_P3_HEAD" "$(git -C "$DR" rev-parse "$DR_C3^1" "$DR_C3^2" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
DR_PUB="$(dl_published "$DR" T3)"
expect_contains "(rr1d) the record publishes the candidate" "line/v1|ev=published|row=T3|commit=$DR_C3|kind=hand|" "$DR_PUB"
expect_contains "(rr1e) …and names the numbers commit the line made" "|numbers=$DR_H3|" "$DR_PUB"
dl_check "$DR" "$DR_H0" "$DR_H3"
expect_eq "(rr2) the declared release check at the new head exits 0" "0" "$DOOR_RC"
expect_contains "(rr2b) …its numbers agree with the report at the published candidate" \
  "landing-numbers: $DOOR_VERSION agrees with the landing report at ${DR_C3:0:12}" "$DOOR_OUT"
expect_absent "(rr2c) …and no row landed after them" "landed after them" "$DOOR_OUT"
expect_contains "(rr2d) the post-landing scan passed: the plan line of T3 is written landed by hand" \
  "landed-by-hand:" "$(dl_plan_line "$DR" T3)"
expect_absent "(rr2e) …and the door printed no unwritten plan" "PLAN-UNWRITTEN" "$DR_OUT"
DR_NEW="$(dl_numbers "$DR" "$DR_H3")"
DR_ON="$(printf '%s\n' "$DR_NEW" | sed -n 's/^`landing-report --rows` at [0-9a-f]* on \([0-9TZ:-]*\):$/\1/p')"
expect_contains "(rr3) the block at the working head names the published candidate" \
  "\`landing-report --rows\` at $DR_C3 on $DR_ON:" "$DR_NEW"
door_run "$DR" bash "$DOOR_POKER" release-note --at "$DR_C3" --on "${DR_ON:-none}" "$DR/$DOOR_PLAN_REL"
expect_eq "(rr3b) …and equals what release-note renders for that head and instant" "$DOOR_OUT" "$DR_NEW"
expect_ne "(rr3c) …which is not the block the release carried" "$DR_OLD" "$DR_NEW"
expect_eq "(rr4) the commit that wrote it is the line one: its author and its message" \
  "bionic line <line@bionic.invalid>|line: release numbers T3" "$(git -C "$DR" log -1 --format='%an <%ae>|%s' "$DR_H3")"
expect_eq "(rr4b) …and it changes CHANGELOG.md alone" "CHANGELOG.md" \
  "$(git -C "$DR" diff-tree --no-commit-id --name-only -r "$DR_H3")"
expect_eq "(rr4c) of the commits the landing brought, the line one is the only one to touch CHANGELOG.md" \
  "line: release numbers T3" "$(git -C "$DR" log --format=%s "$DR_H2..$DR_H3" -- CHANGELOG.md)"
expect_eq "(rr4d) …the piece wrote none of it" "" "$(git -C "$DR" log --format=%s "$DR_H2..$DL_P3_HEAD" -- CHANGELOG.md)"

# The renderer made to fail: the bound plan is a link, which release-note refuses to read as a plan.
RR_RELEASE=1 dl_rr_world rerender-fail
mv "$DR/$DOOR_PLAN_REL" "${DR}/${DOOR_PLAN_REL%.plan.md}.real.md" \
  && ln -s "$(basename "${DOOR_PLAN_REL%.plan.md}").real.md" "$DR/$DOOR_PLAN_REL"
expect_eq "(rr5) precondition: T1 and the release row landed, and the bound plan is now a link" "0 0 yes" \
  "$DR_T1_RC $DR_T2_RC $([ -L "$DR/$DOOR_PLAN_REL" ] && [ -f "$DR/$DOOR_PLAN_REL" ] && echo yes)"
dl_fix_row "$DR"
expect_eq "(rr5b) the fix row past the release is refused (exit 2) and the working branch does not move" "2 $DR_H2" \
  "$DOOR_RC $(dl_head "$DR")"
expect_contains "(rr5c) …in the words of the renderer" "no plan file at" "$DOOR_OUT"
expect_contains "(rr5d) …named as the numbers refusal" "REFUSED reason=numbers-unrendered row=T3" "$DOOR_OUT"
expect_contains "(rr5e) the record holds the fix row ready" "line/v1|ev=ready|row=T3|" "$(dl_record "$DR")"
expect_eq "(rr5f) …and never published" "" "$(dl_published "$DR" T3)"

# The release row still open: a landing changes nothing in CHANGELOG.md.
dl_rr_world rerender-open
dl_fix_row "$DR"
DR_H3="$(dl_head "$DR")"
expect_eq "(rr6) with the release row open, the fix row lands by hand (exit 0) as the merge of its head" "0 $DL_P3_HEAD" \
  "$DOOR_RC $(git -C "$DR" rev-parse "$DR_H3^2" 2>/dev/null)"
DR_B0="$(git -C "$DR" rev-parse "$DR_H0:CHANGELOG.md" 2>/dev/null)"
expect_true "(rr6b) CHANGELOG.md is read at the head before the landing" [ -n "$DR_B0" ]
expect_eq "(rr6c) …and the head after it carries the same file" "$DR_B0" "$(git -C "$DR" rev-parse "$DR_H3:CHANGELOG.md" 2>/dev/null)"
DR_PUB="$(dl_published "$DR" T3)"
expect_contains "(rr6d) the record publishes the landing at the head" "line/v1|ev=published|row=T3|commit=$DR_H3|" "$DR_PUB"
expect_absent "(rr6e) …with no numbers commit" "numbers=" "$DR_PUB"

# ---------------------------------------------------------------------------------------------------------------
section "§RATIO: a landing that pushes tests past code is refused at the door; one under the cap lands beside it"

# dl_counts <check output> -> `<tests> <code>` from the check's one ratio line, a pass's or a refusal's; nothing when it has none.
dl_counts() { printf '%s\n' "$1" | sed -n 's/^.*test-ratio:\{0,1\} \([0-9][0-9]*\)\/\([0-9][0-9]*\).*$/\1 \2/p' | head -n 1; }
# dl_lines <n> -> n lines of shell, one colon each.
dl_lines() { awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) print ":" }'; }
# dl_ratio_piece <root> <test lines> -> DL_PR the row T1's tree: a tests/big.test.sh of that many lines and ten lines
# of code appended to a library file, committed.
dl_ratio_piece() {
  DL_PR="$(door_piece "$1" T1)" || return 1
  mkdir -p "$DL_PR/tests" && dl_lines "$2" > "$DL_PR/tests/big.test.sh" || return 1
  dl_lines 10 >> "$DL_PR/payload/scripts/lib/said.sh"
  dl_commit "$DL_PR" "a test file and ten lines of code"
}

read -r DA DA_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/ratio-over")
EOF
dl_check "$DA" "$DA_H0" "$DA_H0"
DA_COUNTS="$(dl_counts "$DOOR_OUT")"
DA_T="${DA_COUNTS% *}"; DA_C="${DA_COUNTS#* }"
echo "door fixture shell lines at its accepted head: tests ${DA_T:-?} against code ${DA_C:-?}"
expect_regex "(ra0) precondition: the fixture's check reads its counts" '^[0-9]+ [0-9]+$' "$DA_COUNTS"
expect_true "(ra0b) …and the fixture has room for more tests: ${DA_T:-?} under ${DA_C:-?}" [ "${DA_T:-1}" -lt "${DA_C:-0}" ]
DA_ROOM=$(( ${DA_C:-0} - ${DA_T:-0} ))
dl_ratio_piece "$DA" "$(( DA_ROOM + 2000 ))"
: > "$DOOR_SEEN"
door_land "$DA" "$DL_PR"
DA_OUT="$DOOR_OUT"
DA_NEWT=$(( ${DA_T:-0} + DA_ROOM + 2000 )); DA_NEWC=$(( ${DA_C:-0} + 10 ))
expect_eq "(ra1) a piece adding more test lines than the code has room for is refused (exit 2); the working branch does not move" \
  "2 $DA_H0" "$DOOR_RC $(dl_head "$DA")"
expect_contains "(ra1b) …check-failed, by the declared check" "REFUSED reason=check-failed why=release-check rc=1 branch=wt/T1" "$DA_OUT"
expect_contains "(ra1c) …with the test-ratio line naming both counts" "test-ratio $DA_NEWT/$DA_NEWC — tests exceed code at " "$DA_OUT"
expect_eq "(ra1d) …nothing is published: the working head has no tests/big.test.sh and the record no published line" \
  "gone 0" "$(git -C "$DA" cat-file -e "$(dl_head "$DA"):tests/big.test.sh" 2>/dev/null && echo here || echo gone) $(dl_record "$DA" | /usr/bin/grep -c 'ev=published|row=T1|')"
expect_eq "(ra1e) …and the check that refused is the target's copy, run once" "pwd=$DA script=$DA/tests/lib/release-check.sh" "$(door_seen)"

# The same piece under the cap, in a copy of its own: the refusal above is the count, not the file.
read -r DK DK_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/ratio-under")
EOF
dl_ratio_piece "$DK" 1000
door_land "$DK" "$DL_PR"
expect_eq "(ra2) CONTROL the piece with 1000 test lines lands by hand (exit 0)" "0" "$DOOR_RC"
expect_contains "(ra2b) CONTROL …LANDED onto the working branch" "LANDED branch=wt/T1 onto=wave/x" "$DOOR_OUT"
expect_absent "(ra2c) CONTROL …with no ratio refusal" "tests exceed code" "$DOOR_OUT"

# ---------------------------------------------------------------------------------------------------------------
section "§RATIO-2: a landing that cuts test lines is admitted, and the ratio prints"

# A fixture whose accepted head is over the cap (the big file committed on the working branch), and a piece that cuts it.
read -r DC DC_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/ratio-cut")
EOF
mkdir -p "$DC/tests" && dl_lines "$(( DA_ROOM + 2000 ))" > "$DC/tests/big.test.sh" && dl_commit "$DC" "tests past the cap"
DC_H1="$(dl_head "$DC")"
dl_check "$DC" "$DC_H0" "$DC_H1"
expect_eq "(rb0) precondition: the accepted head is over the cap, the declared check refusing it (exit 1)" "1" "$DOOR_RC"
expect_contains "(rb0b) …with the test-ratio line" "test-ratio $(( DA_T + DA_ROOM + 2000 ))/$DA_C — tests exceed code at $DC_H1" "$DOOR_OUT"
DL_PC="$(door_piece "$DC" T1)" && git -C "$DL_PC" rm -q tests/big.test.sh && dl_commit "$DL_PC" "cut the tests"
door_land "$DC" "$DL_PC"
DC_OUT="$DOOR_OUT"; DC_H2="$(dl_head "$DC")"
expect_eq "(rb1) the piece that cuts the test lines under the cap lands by hand (exit 0) and moves the working branch" \
  "0 yes" "$DOOR_RC $([ "$DC_H2" != "$DC_H1" ] && echo yes)"
expect_contains "(rb1b) …LANDED onto the working branch" "LANDED branch=wt/T1 onto=wave/x" "$DC_OUT"
expect_absent "(rb1c) …with no ratio refusal" "tests exceed code" "$DC_OUT"
dl_check "$DC" "$DC_H0" "$DC_H2"
expect_contains "(rb2) the declared check at the landed head prints the ratio, the fixture's own again" "test-ratio: $DA_T/$DA_C" "$DOOR_OUT"

finish
