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
#            tree, the same piece publishes, so these rows can fail.
#
# FIXTURE FIDELITY: every repository is a real `git init` under the world directory with real commits; the door is
# the tree under test's spawn-worktree.sh and session-poker.sh, run from the fixture with every variable that names
# the tree under test unset. Mutants are seds on a COPY of the fixture, committed there as its accepted head, or a
# sed over one function in a driver's own process; the tracked files are never written. SYNTHESIZED: the version,
# the listed name and the rows.
#
# ANTI-VACUITY: with no fixture built the suite stops before its first section, having asserted nothing, which
# finish fails, so no row stands on an empty root (and no git command runs from the tree under test). Each sentinel read that expects nothing sits beside a
# read of the same file in the same fixture that expects a line; each mutant row first proves the mutant ran.
#
# Usage: bash tests/door-landing.test.sh

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
# sed over _wt_release_check; a sed that changes nothing exits 98, so a mutant row never stands on the real function.
. "$1/worktree.sh" && . "$1/session.sh" && . "$1/line.sh" || exit 99
if [ -n "${DOOR_MUTANT:-}" ]; then
  m="$(declare -f _wt_release_check | sed "$DOOR_MUTANT")"
  [ "$m" != "$(declare -f _wt_release_check)" ] || exit 98
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
expect_eq "(cdm) MUTANT the check run in the writer's tree: the piece's copy judges, and the landing publishes" "0" \
  "$DOOR_RC"
expect_eq "(cdm-b) MUTANT …the working branch now holds the planted blob" "$DC_BLOB" \
  "$(git -C "$DD" rev-parse "$(dl_head "$DD"):planted.txt" 2>/dev/null | cut -c1-12)"
expect_eq "(cdm-c) MUTANT …and the target's copy never ran" "" "$(door_seen)"

finish
