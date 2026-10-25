#!/bin/bash
# Tests for the door: a landing pushed through the real hand door of a repository that carries the declared release
# check's whole closure, judged by that repository's own copy of the check (tests/lib/door.sh).
#
#   §LAND    a library row and then the release row land by hand. The release row carries the CHANGELOG entry
#            whose landing numbers `release-note` rendered and plugin.json at the version, so it is the carrier
#            the check must exempt: the landing publishes, the second run of the check passes and the plan row is
#            written, both runs are the judge's copy in a landing tree, and the release-check verb at the landed head says the
#            numbers agree. The same landings under a copy whose carrier test quits at its match (`grep -qxF`)
#            leave the plan unwritten and the verb red; with a CHANGELOG that fits a pipe's buffer the same mutant
#            passes, so the size of the real file is what these rows exercise.
#   §JUDGE   the judge is the release base, the plan's `base-sha:` in a fixture with no tag. The target moves past it
#            with a copy of the check that marks its runs, and a piece rewrites the check to exit 0 and plants a listed
#            name. The door refuses the piece, the release-check verb refuses the person's merge of it, and the hand
#            scan refuses that merge's mark: each run is the judge's copy in a landing tree, never the target's or the
#            head's, and each names the judge. With the runner pointed at the head, the piece publishes; the three
#            call one runner, which alone runs the declared command.
#   §DECLARED the check's files are `release-check-files:`: a piece changing a declared file the check never loads
#            lands, and its line and the release approval card name the file; a piece changing an undeclared file
#            lands named by neither. Of the closure's functions only the intersection is named in the tree.
#   §COPY-4  a check declared by the main checkout's absolute path, no checkout holding the branch: a piece that
#            rewrites the check lands, and every run of the check is the judge's copy in a landing tree, the absolute
#            word read inside it.
#   §INFO    the target's committed check carries a bug and a piece fixes it: the piece lands by hand, both runs the
#            judge's copy, its plan line names the judge and the check file it changes, and the release approval
#            card names that file.
#   §JUDGED  the same fix merged by a person and marked with `row-landed --by-hand`: the scan runs the judge's copy,
#            and the row's line names the judge and the check file the landing changes.
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

# dl_judge_at <root> — the plan's release base moved to the working branch's head, so the copy committed there judges.
dl_judge_at() {
  local p="$1/$DOOR_PLAN_REL"
  _door_inside "$1" && sed -i.orig "s/^base-sha: .*/base-sha: $(dl_head "$1")/" "$p" && rm -f "$p.orig"
}
# dl_seen_judge <root> -> `<runs> <judged>`: the sentinel's lines, and of them the runs made in a landing tree under
# <root> by the copy that tree holds, unmarked (a target or a fix copy marks its runs after the script).
dl_seen_judge() {
  door_seen | awk -v r="$1/.bionic/tmp/landing/" '
    { n++ }
    index($0, "pwd=" r) == 1 { t = substr($0, 5); sub(/ .*$/, "", t)
      if (t ~ /\/[0-9]+$/ && $0 == "pwd=" t " script=" t "/tests/lib/release-check.sh") k++ }
    END { print n + 0, k + 0 }'
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
expect_eq "(l4c) each line names the judge, and the library row's the file of the check it changes" \
  "judged-by=${DL_H0:0:12}|judged-by=${DL_H0:0:12} changed-here=payload/scripts/lib/said.sh" \
  "$(dl_plan_line "$DL" T2 | /usr/bin/grep -o 'judged-by=.*$')|$(dl_plan_line "$DL" T1 | /usr/bin/grep -o 'judged-by=.*$')"
DL_SEEN="$(door_seen)"
expect_eq "(l5) the check ran twice, before the fast-forward and at row-landed" "2" \
  "$(printf '%s\n' "$DL_SEEN" | /usr/bin/grep -c '^pwd=')"
expect_eq "(l5b) …both times the judge's copy, in a landing tree" "2 2" "$(dl_seen_judge "$DL")"
door_run "$DL" bash "$DOOR_POKER" release-check
expect_eq "(l6) session-poker.sh release-check at the landed head exits 0" "0" "$DOOR_RC"
DL_LOG="$DL/.bionic/docs/record/wave-x/release-check-$DL_H2.log"
expect_contains "(l7) …its log is the landed head's, with rc 0" "head=$DL_H2 rc=0" "$(cat "$DL_LOG" 2>/dev/null)"
expect_contains "(l7b) …and the landing numbers agree with the report" \
  "landing-numbers: $DOOR_VERSION agrees with the landing report at ${DL_H1:0:12}" "$(cat "$DL_LOG" 2>/dev/null)"
expect_contains "(l7c) …and the name scan is clean over the release range" "hits=0" "$(cat "$DL_LOG" 2>/dev/null)"
expect_eq "(l7d) …the verb's run is the judge's copy too" "3 3" "$(dl_seen_judge "$DL")"

# The carrier test planted back as `grep -qxF`: on the real changelog the reader quits at line 13 of a file far
# past a pipe's buffer, the writer dies of SIGPIPE, and pipefail makes the test false.
read -r DM DM_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/mutant")
EOF
dl_mutant "$DM" && dl_judge_at "$DM"
expect_eq "(lm0) MUTANT precondition: the committed check's carrier test is the quitting reader" "1" \
  "$(git -C "$DM" show HEAD:tests/lib/release-check.sh | /usr/bin/grep -c 'grep -qxF -- "\$2"$')"
dl_lib_row "$DM"
DM_H1="$(dl_head "$DM")"
dl_release_row "$DM"
DM_OUT="$DOOR_OUT"; DM_H2="$(dl_head "$DM")"
expect_eq "(lm1) MUTANT the mutant ran: the plan's base is the mutant, and both runs are its copy in a landing tree" \
  "$(git -C "$DM" rev-parse "$DM_H1^1" 2>/dev/null) 2 2" "$(sed -n 's/^base-sha: //p' "$DM/$DOOR_PLAN_REL") $(dl_seen_judge "$DM")"
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
  && mv "$DS/CHANGELOG.small" "$DS/CHANGELOG.md" && dl_commit "$DS" "a changelog of a few lines" && dl_judge_at "$DS"
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
section "§JUDGE: the verb, the door and the hand scan judge with the release base's copy, never the target's or the head's"

# The fixture has no tag, so its release base is the plan's `base-sha:`, the copy's first head: that commit's check
# is the judge. The target then commits a copy that marks its runs `copy=target`, so a run of it is told apart.
DL_LIBDIR="$BIONIC_SCRIPTS_DIR/payload/scripts/lib"
# dl_target_copy <root> — the target's check marks its runs, committed past the judge.
dl_target_copy() {
  local c="$1/tests/lib/release-check.sh"
  _door_inside "$1" && sed -i.orig '2s/script=%s\\n/script=%s copy=target\\n/' "$c" && rm -f "$c.orig" \
    && dl_commit "$1" "the target's copy marks its runs"
}
# dl_copy_piece <root> -> DL_PC: the row T1's tree, its check rewritten to pass and the listed name committed.
dl_copy_piece() {
  DL_PC="$(door_piece "$1" T1)" || return 1
  printf '#!/bin/bash\nexit 0\n' > "$DL_PC/tests/lib/release-check.sh"
  printf 'see %s\n' "$DOOR_NAME" > "$DL_PC/planted.txt"
  dl_commit "$DL_PC" "plant the name and tidy the check"
}
read -r DC DC_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/judge")
EOF
dl_target_copy "$DC"; DC_H1="$(dl_head "$DC")"
dl_copy_piece "$DC"
door_run "$DC" env BIONIC_CHECK_HEAD=HEAD bash "$DL_PC/tests/lib/release-check.sh" "$DL_LIST"
expect_eq "(c0) precondition: the piece's own copy passes, the target's marks its runs, and the plan's base is the judge" \
  "0 1 $DC_H0" "$DOOR_RC $(git -C "$DC" show "$DC_H1:tests/lib/release-check.sh" | /usr/bin/grep -c 'copy=target') $(sed -n 's/^base-sha: //p' "$DC/$DOOR_PLAN_REL")"
DC_BLOB="$(git -C "$DL_PC" rev-parse HEAD:planted.txt | cut -c1-12)"

# The door.
: > "$DOOR_SEEN"
door_land "$DC" "$DL_PC"
DC_OUT="$DOOR_OUT"
expect_eq "(c1) the door: land --by-hand is refused (exit 2) and the working branch does not move" "2 $DC_H1" \
  "$DOOR_RC $(dl_head "$DC")"
expect_contains "(c1b) …by the declared check" \
  "REFUSED reason=check-failed why=release-check rc=1 branch=wt/T1 base=$DC_H1" "$DC_OUT"
expect_contains "(c1c) …naming the judge" "judged-by=${DC_H0:0:12}" "$DC_OUT"
expect_contains "(c2) …which names the planted blob" "HIT entry=1 at blob $DC_BLOB line 1" "$DC_OUT"
expect_absent "(c2b) …and prints no listed name" "$DOOR_NAME" "$DC_OUT"
expect_eq "(c3) the record holds T1's ready line and no published one" "1 0" \
  "$(dl_record "$DC" | /usr/bin/grep -c '^line/v1|ev=ready|row=T1|') $(dl_record "$DC" | /usr/bin/grep -c '^line/v1|ev=published|row=T1|')"
expect_eq "(c4) the check ran once, the judge's copy in a landing tree" "1 1" "$(dl_seen_judge "$DC")"
expect_absent "(c4b) …never the target's copy" "copy=target" "$(door_seen)"

# The verb, at the person's git merge of the piece.
_door_inside "$DC" && git -C "$DC" merge --no-ff -q -m "merge wt/T1 by hand" wt/T1 >/dev/null 2>&1
DC_M="$(dl_head "$DC")"
expect_eq "(c5-0) precondition: the person's merge puts the piece's exit 0 on the working head" "1" \
  "$(git -C "$DC" show "$DC_M:tests/lib/release-check.sh" 2>/dev/null | /usr/bin/grep -cx 'exit 0')"
: > "$DOOR_SEEN"
door_run "$DC" bash "$DOOR_POKER" release-check
DC_LOG="$(cat "$DC/.bionic/docs/record/wave-x/release-check-$DC_M.log" 2>/dev/null)"
expect_eq "(c5) the verb: release-check at the working head exits 1" "1" "$DOOR_RC"
expect_contains "(c5b) …its log names the judge" "judged-by=$DC_H0 (base-sha $DC_H0)" "$DC_LOG"
expect_contains "(c5c) …and the planted blob" "HIT entry=1 at blob $DC_BLOB line 1" "$DC_LOG"
expect_eq "(c5d) …the one run the judge's copy in a landing tree" "1 1" "$(dl_seen_judge "$DC")"

# The hand scan, at the person's mark of the same merge.
: > "$DOOR_SEEN"
door_run "$DC" bash "$DOOR_POKER" row-landed T1 "$DC_M" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --by-hand door "the piece merged by a person"
expect_eq "(c6) the hand scan: row-landed --by-hand of the merge is refused (exit 1)" "1" "$DOOR_RC"
expect_contains "(c6b) …naming the judge" "judged-by=${DC_H0:0:12}" "$DOOR_OUT"
expect_contains "(c6c) …and the planted blob" "HIT entry=1 at blob $DC_BLOB line 1" "$DOOR_OUT"
expect_contains "(c6d) …the plan's T1 line is as it was" "- T1: active" "$(dl_plan_line "$DC" T1)"
expect_absent "(c6e) …not landed" "landed-by-hand:" "$(dl_plan_line "$DC" T1)"
expect_eq "(c6f) …the one run the judge's copy in a landing tree" "1 1" "$(dl_seen_judge "$DC")"

# The door's land, in a process of its own, so one function can be replaced in it.
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
$(door_copy "$DW" "$WORLD_ROOT/judge-driver")
EOF
dl_target_copy "$DD"; DD_H1="$(dl_head "$DD")"
dl_copy_piece "$DD"
: > "$DOOR_SEEN"
door_run "$DD" bash "$DL_DRIVER" "$DL_LIBDIR" "$DL_PC" "door fixture"
expect_eq "(cd1) the driver, unmutated, is refused as the door is: exit 2, the branch unmoved, the judge's copy" \
  "2 $DD_H1 1 1" "$DOOR_RC $(dl_head "$DD") $(dl_seen_judge "$DD")"
: > "$DOOR_SEEN"
door_run "$DD" env DOOR_MUTANT_FN=worktree_check_run 'DOOR_MUTANT=s|"${judge}^{commit}"|"${head}^{commit}"|' \
  bash "$DL_DRIVER" "$DL_LIBDIR" "$DL_PC" "door fixture"
expect_eq "(cdm) MUTANT the runner's judge made the head: the piece's copy judges, and the landing publishes (exit 0)" "0" "$DOOR_RC"
expect_eq "(cdm-b) MUTANT …the working branch now holds the planted blob" "$DC_BLOB" \
  "$(git -C "$DD" rev-parse "$(dl_head "$DD"):planted.txt" 2>/dev/null | cut -c1-12)"
expect_eq "(cdm-c) MUTANT …the door's run was the piece's copy: the one judge's run seen is the hand scan's, unmutated, after the publish" \
  "1 1" "$(dl_seen_judge "$DD")"
expect_contains "(cdm-d) MUTANT …which refuses the plan line the publish left owed" "PLAN-UNWRITTEN T1" "$DOOR_OUT"

# One runner: of the four files that run the check, only the runner execs the declared command.
DL_EXECS="$(cd "$BIONIC_SCRIPTS_DIR" && /usr/bin/grep -nE 'exec ("\$@"|\$[A-Za-z_]+) </dev/null' hooks/poker/proof.sh hooks/poker/line.sh payload/scripts/lib/line.sh payload/scripts/lib/worktree.sh)"
expect_eq "(c7) one exec of the declared command, in lib/worktree.sh" "1 1" \
  "$(printf '%s\n' "$DL_EXECS" | /usr/bin/grep -c .) $(printf '%s\n' "$DL_EXECS" | /usr/bin/grep -c '^payload/scripts/lib/worktree.sh:')"
DL_RUNNER_AT="$(awk '/^worktree_check_run\(\) *\{/ { s = NR } s && /^\}/ { print s, NR; exit }' "$DL_LIBDIR/worktree.sh")"
DL_EXEC_AT="$(printf '%s\n' "$DL_EXECS" | cut -d: -f2)"
dl_inside_runner() { [ -n "$DL_RUNNER_AT" ] && [ "${DL_EXEC_AT:-0}" -gt "${DL_RUNNER_AT% *}" ] && [ "${DL_EXEC_AT:-0}" -lt "${DL_RUNNER_AT#* }" ]; }
expect_true "(c7b) …inside worktree_check_run (lines ${DL_RUNNER_AT:-none}, the exec at ${DL_EXEC_AT:-none})" dl_inside_runner
for DL_F in hooks/poker/proof.sh hooks/poker/line.sh payload/scripts/lib/worktree.sh; do
  expect_true "(c7c) $DL_F calls the runner" /usr/bin/grep -q 'worktree_check_run ' "$BIONIC_SCRIPTS_DIR/$DL_F"
done

# ---------------------------------------------------------------------------------------------------------------
section "§DECLARED: the check's files are the declared list; a landing names the ones it changes, and no other"

# The fixture declares `release-check-files:` as bionic does (tests/lib/door.sh). payload/scripts/lib/session.sh is
# declared by a glob and loaded by no file of the check; payload/scripts/doctor.sh lies outside every glob.
# dl_declared <dir> <path> -> DQ, DQ_H0 a copy of its own, and after a landing by hand of the row T1's tree with one
# line added to <path>: DQ_OUT the landing's output, DQ_LINE the judged-by field of T1's line, DQ_CARD the release
# approval card.
dl_declared() {
  local p
  read -r DQ DQ_H0 <<EOF2
$(door_copy "$DW" "$WORLD_ROOT/$1")
EOF2
  p="$(door_piece "$DQ" T1)" || return 1
  printf 'door_noted() { :; }\n' >> "$p/$2"
  dl_commit "$p" "the piece: $2" || return 1
  door_land "$DQ" "$p"; DQ_OUT="$DOOR_OUT"
  DQ_LINE="$(dl_plan_line "$DQ" T1 | /usr/bin/grep -o 'judged-by=.*$')"
  door_run "$DQ" bash "$DOOR_POKER" release-approval --preview; DQ_CARD="$DOOR_OUT"
}
expect_contains "(d0) precondition: the fixture declares the check's files by glob" \
  "payload/scripts/lib/*.sh" "$(sed -n 's/^release-check-files: //p' "$DW/.bionic/config.yaml" 2>/dev/null)"

dl_declared declared payload/scripts/lib/session.sh
expect_contains "(d1) a piece that changes a declared file the check never loads lands by hand" \
  "LANDED branch=wt/T1 onto=wave/x" "$DQ_OUT"
expect_eq "(d2) …its line names the judge and the declared file it changes" \
  "judged-by=${DQ_H0:0:12} changed-here=payload/scripts/lib/session.sh" "$DQ_LINE"
expect_eq "(d3) …and the release approval card names it as a change to the release check" \
  "- This release changes the release check: payload/scripts/lib/session.sh." \
  "$(printf '%s\n' "$DQ_CARD" | /usr/bin/grep 'changes the release check')"

dl_declared undeclared payload/scripts/doctor.sh
expect_contains "(d4) CONTROL a piece that changes a file no glob declares lands by hand" \
  "LANDED branch=wt/T1 onto=wave/x" "$DQ_OUT"
expect_eq "(d4b) CONTROL …its line names the judge alone" "judged-by=${DQ_H0:0:12}" "$DQ_LINE"
expect_contains "(d4c) CONTROL …the release approval card renders" "Bottom line" "$DQ_CARD"
expect_absent "(d4d) CONTROL …and says nothing of the check" "changes the release check" "$DQ_CARD"

# What decides the check's files is the declaration alone: of the five functions that read the check's own loads to
# find them, the one that meets the declaration with the range is all that stands, and the three readers call it.
DL_FNS="$(cd "$BIONIC_SCRIPTS_DIR" && /usr/bin/grep -rhoE '_wt_(check_(closure|loads|judge|beside)|repo_paths)' payload hooks tests | sort -u)"
expect_eq "(d5) of the closure's functions only the intersection is named in payload/, hooks/ and tests/" "_wt_check_judge" "$DL_FNS"
for DL_F in hooks/poker/line.sh hooks/poker/plan.sh; do
  expect_true "(d5b) $DL_F reads what a range changes of the check's files through the intersection" \
    /usr/bin/grep -q '_wt_check_judge "' "$BIONIC_SCRIPTS_DIR/$DL_F"
done

# ---------------------------------------------------------------------------------------------------------------
section "§COPY-4: a check declared by the main checkout's absolute path is run as the judge holds it"

# The declaration is read from the main checkout, and the door runs it in a landing tree pointed at the judge: an
# absolute word under the main checkout names the file the judge's tree holds at that path.
read -r DQ DQ_H0 <<EOF2
$(door_copy "$DW" "$WORLD_ROOT/copy4-tree")
EOF2
DL_QP="$(door_piece "$DQ" T1)" && printf '#!/bin/bash\nexit 0\n' > "$DL_QP/tests/lib/release-check.sh" \
  && dl_commit "$DL_QP" "the piece: rewrite"
dl_check "$DQ" "$DQ_H0" "$(git -C "$DL_QP" rev-parse HEAD)"; DQ_RC="$DOOR_RC"
_door_inside "$DQ" && sed -i.orig "s|^release-check: bash tests/|release-check: bash $DQ/tests/|" "$DQ/.bionic/config.yaml" \
  && rm -f "$DQ/.bionic/config.yaml.orig" && git -C "$DQ" checkout --quiet --detach
: > "$DOOR_SEEN"
expect_eq "(c4-1-0) precondition: the check is declared by absolute path, no checkout holds the working branch, and the target copy passes over the piece" \
  "1 1 0" "$(/usr/bin/grep -c "^release-check: bash $DQ/tests/lib/release-check.sh " "$DQ/.bionic/config.yaml") $( (. "$DL_LIBDIR/worktree.sh" >/dev/null 2>&1; worktree_checkout_of "$DQ" wave/x >/dev/null; echo $?) ) $DQ_RC"
door_land "$DQ" "$DL_QP"
DQ_SEEN="$(door_seen)"
expect_eq "(c4-1a) land --by-hand of the rewrite, declared by absolute path, from a landing tree: lands (exit 0)" "0" "$DOOR_RC"
expect_contains "(c4-1b) …LANDED onto the working branch" "LANDED branch=wt/T1 onto=wave/x" "$DOOR_OUT"
expect_eq "(c4-1c) each run of the check (the door's, the scan's) is the judge's copy in a landing tree: the absolute word is read inside it" \
  "2 2" "$(dl_seen_judge "$DQ")"
expect_absent "(c4-1d) …never the main checkout's working copy the word names" " script=$DQ/tests/lib/release-check.sh" "$DQ_SEEN"

# ---------------------------------------------------------------------------------------------------------------
section "§INFO: a landing that changes the check lands; its line and the release approval card name what it changes"

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
$(door_copy "$DW" "$WORLD_ROOT/info")
EOF
dl_named "$DN"
expect_eq "(n0) precondition: the piece's copy carries the fix's mark, the target's the bug" "1 1" \
  "$(/usr/bin/grep -c 'copy=fix' "$DL_NP/tests/lib/release-check.sh") $(/usr/bin/grep -cx 'exit 3' "$DN/tests/lib/release-check.sh")"
: > "$DOOR_SEEN"
DN_P="$(git -C "$DL_NP" rev-parse HEAD)"
door_land "$DN" "$DL_NP"
DN_OUT="$DOOR_OUT"; DN_H="$(dl_head "$DN")"
expect_eq "(n1) land --by-hand of the fix to the check lands (exit 0), the working branch at a merge of the fix" \
  "0 $DN_P" "$DOOR_RC $(git -C "$DN" rev-parse "$DN_H^2" 2>/dev/null)"
expect_contains "(n1b) …LANDED onto the working branch" "LANDED branch=wt/T1 onto=wave/x" "$DN_OUT"
expect_absent "(n1c) …refused by nothing" "REFUSED reason=" "$DN_OUT"
expect_contains "(n2) T1's line names the judge and the file of the check the landing changes" \
  "judged-by=${DN_H0:0:12} changed-here=tests/lib/release-check.sh" "$(dl_plan_line "$DN" T1)"
expect_eq "(n3) both runs, the door's and the scan's, are the judge's copy" "2 2" "$(dl_seen_judge "$DN")"
expect_absent "(n3b) …never the target's bug nor the fix's mark" "copy=fix" "$(door_seen)"
door_run "$DN" bash "$DOOR_POKER" release-approval --preview
DN_CARD="$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -F 'changes the release check')"
expect_nonempty "(n4-0) the release approval card has its check line" "$DN_CARD"
expect_contains "(n4) …naming the check's file the release changes" "tests/lib/release-check.sh" "$DN_CARD"

# ---------------------------------------------------------------------------------------------------------------
section "§JUDGED: the fix merged by a person and marked by hand is judged by the release base's copy, and its line says so"

read -r DN DN_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/judged")
EOF
dl_named "$DN"
: > "$DOOR_SEEN"
_door_inside "$DN" && git -C "$DN" merge --no-ff -q -m "merge wt/T1 by hand" wt/T1 >/dev/null 2>&1
DN_M="$(dl_head "$DN")"
DN_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
expect_eq "(j0) precondition: the person's merge holds the fix on the working branch" "$DL_NH1 $(git -C "$DL_NP" rev-parse HEAD)" \
  "$(git -C "$DN" rev-parse "$DN_M^1" "$DN_M^2" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
door_run "$DN" bash "$DOOR_POKER" row-landed T1 "$DN_M" "$DN_AT" --by-hand door "a fix to the check lands by a person"
expect_eq "(j1) row-landed --by-hand of the merged fix exits 0" "0" "$DOOR_RC"
expect_contains "(j2) T1's line is landed by hand and names the judge and the check file the landing changes" \
  "landed-by-hand: door $DN_AT \"a fix to the check lands by a person\" judged-by=${DN_H0:0:12} changed-here=tests/lib/release-check.sh" \
  "$(dl_plan_line "$DN" T1)"
expect_eq "(j3) …and the scan's one run is the judge's copy" "1 1" "$(dl_seen_judge "$DN")"
expect_absent "(j3b) …never the landed copy, the fix's mark" "copy=fix" "$(door_seen)"

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
expect_eq "(h2) the check ran once, the judge's copy in a landing tree" "1 1" "$(dl_seen_judge "$DH")"
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
expect_eq "(ra1e) …and the check that refused is the judge's copy in a landing tree, run once" "1 1" "$(dl_seen_judge "$DA")"

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

# ---------------------------------------------------------------------------------------------------------------
section "§DIRTIED: a release check that dirties the tree it is handed, planted at the release base, is refused check-dirtied"

# The check runs as the release base holds it, so the dirtying copy is committed on the working branch and the plan's
# base-sha moved onto it: a copy planted in the piece alone is never the copy that runs. The planted copy keeps the
# fixture's sentinel line, then writes one line into the checkout it is handed (BIONIC_CHECK_TREE) and passes. The door
# hands it the piece; the release-check verb hands it the working checkout.
# fails-when: the door lands the piece; the door refuses it on anything but check-dirtied; the verb's run at the head
# says no check-dirtied; with the door's dirtied arm cut out the piece is still refused (the row would pin nothing).
dl_dirty_base() {  # <root> -> the dirtying check committed on the working branch, and the plan's base-sha moved onto it
  local c="$1/tests/lib/release-check.sh"
  _door_inside "$1" || return 1
  { sed -n 1,2p "$c"; cat <<'DIRTY'
printf 'dirt\n' >> "$BIONIC_CHECK_TREE/CHANGELOG.md"
exit 0
DIRTY
  } > "$c.new" && mv "$c.new" "$c" && dl_commit "$1" "the check writes into the tree it is handed" && dl_judge_at "$1"
}
dl_dirty_piece() {  # <root> -> DL_PD: the row T1's tree, one library line committed
  DL_PD="$(door_piece "$1" T1)" || return 1
  printf 'door_dirtied() { :; }\n' >> "$DL_PD/payload/scripts/lib/said.sh"
  dl_commit "$DL_PD" "a library change under the dirtying check"
}
read -r DX DX_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/dirtied")
EOF
dl_dirty_base "$DX"; DX_H1="$(dl_head "$DX")"
expect_eq "(d0) precondition: the dirtying copy is at the working head, and the plan's base-sha names that head" \
  "1 $DX_H1" "$(git -C "$DX" show "$DX_H1:tests/lib/release-check.sh" 2>/dev/null | /usr/bin/grep -c 'BIONIC_CHECK_TREE/CHANGELOG.md') $(sed -n 's/^base-sha: //p' "$DX/$DOOR_PLAN_REL")"
dl_dirty_piece "$DX"
: > "$DOOR_SEEN"
door_land "$DX" "$DL_PD"
DX_OUT="$DOOR_OUT"
expect_eq "(d1) the door: land --by-hand is refused (exit 2) and the working branch does not move" "2 $DX_H1" \
  "$DOOR_RC $(dl_head "$DX")"
expect_contains "(d1b) …check-dirtied, by the declared check" "REFUSED reason=check-dirtied why=release-check" "$DX_OUT"
expect_contains "(d1c) …naming the piece's file it changed" "piece_paths=CHANGELOG.md" "$DX_OUT"
expect_contains "(d1d) …and the judge, the release base" "judged-by=${DX_H1:0:12}" "$DX_OUT"
expect_eq "(d2) the plant lands nowhere: the record holds T1's ready line and no published one" "1 0" \
  "$(dl_record "$DX" | /usr/bin/grep -c '^line/v1|ev=ready|row=T1|') $(dl_record "$DX" | /usr/bin/grep -c '^line/v1|ev=published|row=T1|')"
expect_eq "(d3) the check ran once, the judge's copy in a landing tree" "1 1" "$(dl_seen_judge "$DX")"

# The same plant with the door's dirtied arm cut out, in a copy of its own: the refusal above is that arm's.
read -r DY DY_H0 <<EOF
$(door_copy "$DW" "$WORLD_ROOT/dirtied-mutant")
EOF
dl_dirty_base "$DY"; DY_H1="$(dl_head "$DY")"
dl_dirty_piece "$DY"
door_run "$DY" env 'DOOR_MUTANT=s|if \[ -n "$left" \]; then|if false; then|' bash "$DL_DRIVER" "$DL_LIBDIR" "$DL_PD" "door fixture"
expect_eq "(dm) MUTANT the door's dirtied arm cut out: the plant is not refused check-dirtied, and the branch moves" \
  "0 yes" "$(printf '%s\n' "$DOOR_OUT" | /usr/bin/grep -c 'reason=check-dirtied') $([ "$(dl_head "$DY")" != "$DY_H1" ] && echo yes)"
[ "$(dl_head "$DY")" != "$DY_H1" ] || printf '      the mutant said: %s\n' "$DOOR_OUT"

# The verb's own arm: the release-check verb at a head past the base hands the check the working checkout.
_door_inside "$DX" && printf 'past the base\n' > "$DX/notes.txt" && dl_commit "$DX" "a commit past the release base"
DX_H2="$(dl_head "$DX")"
door_run "$DX" bash "$DOOR_POKER" release-check
DX_LOG="$(cat "$DX/.bionic/docs/record/wave-x/release-check-$DX_H2.log" 2>/dev/null)"
expect_eq "(d4) the verb: release-check at the working head is refused (exit 1)" "1" "$DOOR_RC"
expect_contains "(d4b) …check-dirtied, naming the checkout it changed" \
  "REFUSED — check-dirtied: the declared release-check (bash tests/lib/release-check.sh" "$DOOR_OUT"
expect_contains "(d4c) …its log says what the check left" "check-dirtied: the check left tracked files changed in $DX" "$DX_LOG"
expect_contains "(d4d) …and a failing check fact is written at that head" "head=$DX_H2" \
  "$(/usr/bin/grep '^proved: kind=check ' "$DX/$DOOR_PLAN_REL" | /usr/bin/grep 'result=fail')"
_door_inside "$DX" && git -C "$DX" checkout -q -- CHANGELOG.md

finish
