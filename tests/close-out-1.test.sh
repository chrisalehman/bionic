#!/bin/bash
# tests/close-out-1.test.sh — payload/scripts/close-out.sh, part 1 of 4: sections 0 through E2E.
#
# Four parts, so each stays under the suite bar; the sandbox, design and shared builders are in tests/close-out.prelude.sh.

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"
. "$(dirname "$0")/lib/roster-row.sh"   # the one roster-row builder (cross-gate S17; wave-30 T23)
. "$(dirname "$0")/close-out.prelude.sh"

# ============================================================
section "0 — the script exists, parses, and refuses an unusable call"
# ============================================================

expect_eq "0a: close-out.sh is on disk" "yes" "$([ -r "$SCRIPT" ] && echo yes || echo no)"
expect_eq "0b: close-out.sh parses" "yes" \
  "$(bash -n "$SCRIPT" 2>/dev/null && echo yes || echo no)"

# The guard that keeps this suite's own git commands inside the sandbox, asserted rather
# than assumed — it is the one helper here whose failure is invisible in the results.
expect_eq "0e: the sandbox guard refuses an EMPTY fixture path" "1" \
  "$( ( in_fixture "" ) >/dev/null 2>&1; echo $? )"
expect_eq "0f: …and one outside the sandbox (this repository)" "1" \
  "$( ( in_fixture "$REPO_ROOT" ) >/dev/null 2>&1; echo $? )"
expect_eq "0g: …while a real fixture path is entered" "0" \
  "$( ( in_fixture "$SB_HOME" ) >/dev/null 2>&1; echo $? )"

P0="$(mk_fixture p0)"; advance_to "$P0" 8
run_close "$P0" "fly"
expect_eq "0c: an unknown verb exits 2" "2" "$CO_RC"
expect_eq "0d: …and says which verbs there are" "yes" "$(contains "$CO_OUT" "check")"

# The census is the register: a `## Tasks` row's `worktree` cell names a tree, `working-branch:`'s shape decides nothing.
ROWS04="| T1 | 4 | build | fixture writer one | implementor | — | 10 | AC-1 | file.txt | active | 04-T1 |
| T2 | 4 | build | fixture writer two | implementor | — | 10 | AC-1 | file.txt | active | 04-T2 |"

P0H="$(mk_census_fixture p0h "w51/04-fixit" "$ROWS04")"; advance_to "$P0H" 8
mk_census_branch "$P0H" wt/04-T1
mk_census_branch "$P0H" wt/04-T2
mk_census_branch "$P0H" wt/99-x   # a foreign branch — no row of this plan names it
run_close "$P0H" check
expect_eq "0h: a w51-shaped working-branch is no longer refused in preflight" "0" "$CO_RC"
expect_eq "0i: …the census names exactly the registered trees, in table order" "yes" \
  "$(contains "$CO_OUT" "worktree-removed: wt/04-T1 wt/04-T2 (2 registered trees)")"
expect_eq "0j: …never the foreign, unregistered wt/99-x" "no" "$(contains "$CO_OUT" "wt/99-x")"

# working-branch: main is now an ordinary value — it decided nothing before this
# wave read it for anything but the merge act, and it decides nothing extra now.
P0K="$(mk_census_fixture p0k "main" "$ROWS04")"; advance_to "$P0K" 8
mk_census_branch "$P0K" wt/04-T1
mk_census_branch "$P0K" wt/04-T2
run_close "$P0K" check
expect_eq "0k: working-branch: main is accepted, not refused" "0" "$CO_RC"
expect_eq "0k2: …and still censuses its registered trees" "yes" \
  "$(contains "$CO_OUT" "worktree-removed: wt/04-T1 wt/04-T2 (2 registered trees)")"

# A plan whose `## Tasks` table names no tree: an EMPTY census is the conservative
# failure, and `check`/`run` both proceed rather than refusing.
ROWS_EMPTY="| T1 | 4 | build | fixture writer one | implementor | — | 10 | AC-1 | file.txt | active | — |"
P0L="$(mk_census_fixture p0l "wave/01-fixture" "$ROWS_EMPTY")"; advance_to "$P0L" 8
run_close "$P0L" check
expect_eq "0l: a plan with no filled worktree cell does not refuse" "0" "$CO_RC"
expect_eq "0m: …and says so by name, not silently" "yes" \
  "$(contains "$CO_OUT" "census: no registered trees")"

# ============================================================
section "0o — C4: no worktree column at all falls back to the pre-wave glob census"
# ============================================================
# A table with no `worktree` column has an empty register, so `wt_unreached` falls back to the `wt/*` glob, announced,
# and an unmerged wt/01-T1 is refused by name.
# ROWS_NOWT: hoisted to tests/close-out.prelude.sh (a later part reads it)
P0O="$(CO_PLAN_AT=14 mk_census_fixture_nowt p0o "wave/01-x" "$ROWS_NOWT")"; advance_to "$P0O" 8
(
  in_fixture "$P0O" || exit 1
  git checkout -q -b wave/01-x
  printf 'work\n' >> file.txt
  git commit -q -am "wave work" >/dev/null 2>&1
  git checkout -q -b wt/01-T1 wave/01-x
  printf 'never landed\n' >> file.txt
  git commit -q -am "unreached" >/dev/null 2>&1
  git checkout -q main
  git merge -q --no-ff -m "merge wave" wave/01-x >/dev/null 2>&1
)
run_close "$P0O" check
expect_eq "0o1: check WOULD REFUSE naming wt/01-T1 though the register census is empty" "yes" \
  "$(contains "$CO_OUT" "WOULD REFUSE")"
expect_eq "0o2: …naming the branch" "yes" "$(contains "$CO_OUT" "wt/01-T1")"

run_close "$P0O" run
expect_eq "0o4: run refuses — the fallback census carries unreached work" "2" "$CO_RC"
expect_eq "0o5: …naming wt/01-T1" "yes" "$(contains "$CO_OUT" "wt/01-T1")"
expect_eq "0o5b: …the branch survives (nothing was deleted, nothing else was done)" "yes" \
  "$(branch_exists "$P0O" "wt/01-T1")"

# ============================================================
section "0r — C7: a column-less WAVE-scale plan whose working-branch is not wave/<digits>-<slug> shaped refuses, as 1.8.3 did"
# ============================================================
# A column-less wave-scale plan reads its census's wave number off `working-branch:`, so a branch with none refuses
# before act 1 rather than reach for an unscoped census; a task-scale plan wants none (§ANY-BRANCH).
P0R="$(CO_PLAN_AT=14 mk_census_fixture_nowt p0r "topic/not-a-wave-branch" "$ROWS_NOWT")"; advance_to "$P0R" 8
run_close "$P0R" check
expect_eq "0r1: check refuses (1.8.3 refused before act 1, for either verb)" "2" "$CO_RC"

run_close "$P0R" run
expect_eq "0r3: run refuses identically" "2" "$CO_RC"

# A table WITH the worktree column never derives a wave number at all — the register
# names its own trees — so the same non-wave-shaped working-branch is untouched there.
ROWS_WT_SHAPED="| T1 | 4 | build | fixture writer one | implementor | — | 10 | AC-1 | file.txt | active | 01-T1 |"
P0S="$(mk_census_fixture p0s "topic/not-a-wave-branch" "$ROWS_WT_SHAPED")"; advance_to "$P0S" 8
run_close "$P0S" check
expect_eq "0s1: a registered table with the same branch shape is never refused for it" "0" "$CO_RC"

# ============================================================
section "ANY-BRANCH — T11 (AC-9.2): a column-less TASK-scale plan closes on any working-branch"
# ============================================================
# A task-scale plan owns no wave, so no `wt/<NN>-*` census and no wave number to refuse for lacking.
mk_task_scale_fixture() {
  local name="$1" working="$2" p
  p="$(mk_census_fixture_nowt "$name" "$working" "$ROWS_NOWT")"; advance_to "$p" 8
  sed -i.bak 's/^scale: wave$/scale: task/' "$p/$PLAN_REL" && rm -f "$p/$PLAN_REL.bak"
  (
    in_fixture "$p" || exit 1
    git checkout -q -b "$working"
    printf 'late fix\n' >> file.txt
    git commit -q -am "late fix" >/dev/null 2>&1
    git checkout -q main
    git merge -q --no-ff -m "merge fix" "$working" >/dev/null 2>&1
  )
  plant_facts "$p"
  printf '%s\n' "$p"
}

PAB="$(mk_task_scale_fixture pab "fixit/x")"
expect_eq "AB0: the fixture really is task-scale (so a pass here is not the wave refusal's absence)" "yes" \
  "$(grep -q '^scale: task$' "$PAB/$PLAN_REL" && echo yes || echo no)"
run_close "$PAB" check
expect_eq "AB1: check on fixit/x is not refused" "0" "$CO_RC"
expect_eq "AB2: …prints no shape refusal" "no" "$(contains "$CO_OUT" "shaped")"
expect_eq "AB3: …and announces no wt/-* census fallback" "no" "$(contains "$CO_OUT" "wt/-*")"
run_close "$PAB" run
expect_eq "AB4: run on fixit/x closes with rc 0" "0" "$CO_RC"
expect_eq "AB5: …prints no shape refusal" "no" "$(contains "$CO_OUT" "shaped")"

# The integrate act is the scale's cell: at task scale, `pr`, so an unmerged fix/x closes, merging nothing, and the
# `gh pr create` command is printed and recorded, never run.
# mk_task_pr_fixture: hoisted to tests/close-out.prelude.sh (a later part reads it)
PPR="$(mk_task_pr_fixture ppr "fix/x")"
PPR_MAIN="$(git -C "$PPR" rev-parse main)"
expect_eq "PR0: the fixture's fix/x is not reachable from main (so the PR act is what passes)" "no" \
  "$(git -C "$PPR" merge-base --is-ancestor fix/x main && echo yes || echo no)"
run_close "$PPR" check
expect_eq "PR1: check on an unmerged task-scale fix/x is not refused" "0" "$CO_RC"
run_close "$PPR" run
expect_eq "PR3: run closes with rc 0" "0" "$CO_RC"
expect_eq "PR4: …prints the command" "yes" "$(contains "$CO_OUT" "gh pr create --base main --head fix/x")"
expect_eq "PR5: …records it in the continuation" "yes" \
  "$(grep -qF 'gh pr create --base main --head fix/x' "$PPR/$CONT_REL" 2>/dev/null && echo yes || echo no)"
expect_eq "PR6: …and merges nothing: main is where it was" "$PPR_MAIN" "$(git -C "$PPR" rev-parse main)"

# ============================================================
section "1 — AC-4.1: run performs the tail and the gate allows the commit"
# ============================================================

P1="$(mk_fixture p1)"; advance_to "$P1" 8
expect_eq "1.0: the fixture starts with three entries under .bionic/tmp/" "3" "$(tmp_entries "$P1")"
P1_SUM0="$(sha_of "$P1/$PLAN_REL")"
run_close "$P1" run

expect_eq "1a: run exits 0" "0" "$CO_RC"
expect_eq "1b: act 1 — merge: reports the ancestry readback" "yes" \
  "$(contains "$CO_OUT" "merge: wave/01-fixture @ ")"
expect_eq "1c: …naming the integration branch it is reachable from" "yes" \
  "$(contains "$CO_OUT" "reachable from main @ ")"
expect_eq "1d: act 2 — worktree-removed: names the branch it deleted" "yes" \
  "$(contains "$CO_OUT" "worktree-removed: wt/01-x")"
expect_eq "1e: …and wt/01-x is actually gone" "no" "$(branch_exists "$P1" "wt/01-x")"
expect_eq "1f: act 3 — tmp-wiped: counts what it removed" "yes" \
  "$(contains "$CO_OUT" "tmp-wiped: 3 entries")"
expect_eq "1g: …and .bionic/tmp/ is empty afterwards (REQ-1: this fixture's ids read as dead, so nothing is spared — §tmp-spares below covers a live one)" "0" "$(tmp_entries "$P1")"
expect_eq "1i: act 5 — continuation: names the file it wrote" "yes" \
  "$(contains "$CO_OUT" "continuation: ")"
expect_eq "1j: …and the file is there, non-empty" "yes" \
  "$([ -s "$P1/$CONT_REL" ] && echo yes || echo no)"
expect_eq "1k: …in the 1.7.1 shape — the five headings" "yes" \
  "$(contains "$(cat "$P1/$CONT_REL")" "## Resume instruction")"
expect_eq "1l: …and it leaves the orchestrator's unknowns marked" "yes" \
  "$(contains "$(cat "$P1/$CONT_REL")" "<fill")"
expect_eq "1m: act 6 — epic-row: reports the row" "yes" "$(contains "$CO_OUT" "epic-row: ")"
expect_eq "1p: act 8 — patrol: names CronDelete and the disarm verb" "yes" \
  "$(contains "$CO_OUT" "patrol: CronDelete")"
expect_eq "1q: …and the disarm command" "yes" \
  "$(contains "$CO_OUT" "session-poker.sh disarm")"
HO_REL="$(bash "$REPO_ROOT/payload/scripts/reader.sh" "$P1/$PLAN_REL" handoff 2>/dev/null | sed -n 's/^path=//p')"
expect_eq "1r2: …under the file's kind line" "bionic-handoff/v1" "$(sed -n 1p "$P1/$HO_REL" 2>/dev/null)"
expect_eq "1r3: …whose last line is the one door, naming the file" "/bionic:canonical-sdlc $HO_REL" "$(tail -1 "$P1/$HO_REL" 2>/dev/null)"
expect_eq "1r4: …and the run's log names the run's file in the handoffs folder" "yes" \
  "$([[ "$HO_REL" == .bionic/docs/record/handoffs/*-wave-01-fixture.md ]] && echo yes || echo "no: $HO_REL")"
expect_eq "1ae: run_open now reads the plan as CLOSED" "1" "$(run_open_rc "$P1/$PLAN_REL")"
expect_eq "1af: the script's own gate dry-run reported ok" "yes" "$(contains "$CO_OUT" "gate: ok")"
expect_eq "1ag: AC-4.1 — the real bash-walls.sh allows the close-out commit" "0" "$(gate_rc "$P1")"
expect_eq "1ah: act 7 — archived: passes archive_run's line through" "yes" \
  "$(contains "$CO_OUT" "archived: bionic: archive")"
expect_eq "1ai: …and the run directory stayed, the epic being open" "yes" \
  "$([ -f "$P1/$PLAN_REL" ] && echo yes || echo no)"

# THE CLOSE WRITES EVENTS. What step 8 cleaned and the delivery are fields of the step's events, and the plan's text is
# the person's: its sum is the one it had before the close. The step answer is read twice: on the run's log as it stood
# at the close's step 8, and whole after the close.
expect_eq "1aj: the close writes nothing into the plan: its sum is the same before and after" "$P1_SUM0" "$(sha_of "$P1/$PLAN_REL")"
P1_S8="$(co_step_answer "$P1" 8)"
expect_eq "1ak: the step answer at the close's step 8 carries what it cleaned" "n=8|done|yes|yes|state=open" \
  "$(printf '%s\n' "$P1_S8" | sed -n 1p)|$(printf '%s\n' "$P1_S8" | sed -n 's/^cleanup=//p')|$(contains "$P1_S8" "tmp-wiped=3 entries under ")|$(contains "$P1_S8" "tasks-completed=$TASKS_WORDS")|$(printf '%s\n' "$P1_S8" | tail -1)"
P1_S9="$(co_step_answer "$P1")"
expect_eq "1al: …and after the close it carries the delivery and the archive's line, the run delivered" "n=9|yes|yes|state=delivered" \
  "$(printf '%s\n' "$P1_S9" | sed -n 1p)|$(contains "$P1_S9" "delivered=")|$(contains "$P1_S9" "archived=bionic: archive")|$(printf '%s\n' "$P1_S9" | tail -1)"

# THE ARCHIVE IS A FIELD OF THE DELIVERY'S STEP, WRITTEN WHERE THE RUN'S LOG IS. With no open sibling the plan moves out of
# the project and its record stays: the project's log gains the delivery restated with the archive's line, at the
# delivery's own second, and the archive gains no record. The three readers of when the run was delivered (the handoff
# file the close wrote, closed-form, the landing report's window) read one instant, the plan put back where its record is.
PA="$(mk_fixture p-arch)"; advance_to "$PA" 8; rm -f "$PA/$EPIC_REL"
run_close "$PA" run
PA_MOVED="$(find "$SANDBOX/p-arch-archive" -name "${PLAN_REL##*/}" -type f 2>/dev/null | head -1)"
expect_eq "1am: the close archives: rc 0, the plan in the archive and gone from the project" "0|yes|no" \
  "$CO_RC|$([ -n "$PA_MOVED" ] && echo yes || echo no)|$([ -f "$PA/$PLAN_REL" ] && echo yes || echo no)"
expect_eq "1an: the project's log holds the archive's field on the delivery's step, and the archive holds no record" "yes|yes|0" \
  "$(contains "$(co_step_answer "$PA" 9)" "archived=bionic: archived ")|$(contains "$(co_step_answer "$PA" 9)" "delivered=")|$(find "$SANDBOX/p-arch-archive" -type d -name record | grep -c .)"
mkdir -p "$PA/${PLAN_REL%/*}"; cp "$PA_MOVED" "$PA/$PLAN_REL"
PA_HO="$(sed -n 's/^resume point: NONE — DELIVERED at \([^;]*\);.*/\1/p' "$PA"/.bionic/docs/record/handoffs/*-wave-01-fixture.md 2>/dev/null | head -1)"
run_close "$PA" closed-form
PA_CF="$(printf '%s\n' "$CO_OUT" | sed -n 's/^resume point: NONE — DELIVERED at \([^;]*\);.*/\1/p')"
PA_HH="$(hh_report "$PA" --hand-holds | sed -n 's/^hand-holds window: .*until \([^ ]*\) (delivered:).*/\1/p')"
expect_regex "1ao: the handoff file names the delivery's instant to the second" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$PA_HO"
expect_eq "1ap: …and closed-form and the landing report's window read that one instant" "$PA_HO|$PA_HO" \
  "$PA_CF|$(printf '%s' "$PA_HH" | sed -E 's/^([0-9-]+T[0-9]{2}:[0-9]{2})Z$/\1:00Z/')"
pa_step() { bash -c '. "$1/run.sh" && . "$1/proof.sh" && proof_step_event "$2" 9 delivered=x' _ "$REPO_ROOT/payload/scripts/lib" "$1" >/dev/null 2>&1; echo $?; }
expect_eq "1ar: the step's writer takes a run's log that is there, and refuses one that is not, making no directory" "0|2|no" \
  "$(pa_step "$PA/$LOG_REL")|$(pa_step "$SANDBOX/p-none/record/w/run.log")|$([ -d "$SANDBOX/p-none" ] && echo yes || echo no)"

# A SECOND CLOSE KEEPS THE STEP 8 THAT STANDS. A close whose attestation was refused left its step 8 in the log with what
# it cleaned, the run open at 8; the close run again delivers on that step and appends no emptier one over it.
PS="$(mk_fixture p-again)"
printf 'run/v1|ev=step|n=8|cleanup=done|tmp-wiped=7 entries under the first close|tasks-completed=%s|at=2026-10-04T12:30:00Z\n' "$TASKS_WORDS" >> "$PS/$LOG_REL"
run_close "$PS" run
expect_eq "1aq: the second close delivers on the step 8 that stood, its wipe kept: one step 8 in the log" "0|yes|1|n=9" \
  "$CO_RC|$(contains "$(co_step_answer "$PS" 8)" "tmp-wiped=7 entries under the first close")|$(grep -c '|ev=step|n=8|' "$PS/$LOG_REL")|$(co_step_answer "$PS" | sed -n 1p)"

# ============================================================
section "2 — AC-4.3: an unreached wt/* branch refuses by name and nothing else happens"
# ============================================================

P2="$(mk_fixture p2)"; advance_to "$P2" 8
add_unreached_branch "$P2"
PLAN_BEFORE="$(sha_of "$P2/$PLAN_REL")"
run_close "$P2" run

expect_eq "2a: the run exits 2" "2" "$CO_RC"
expect_eq "2b: …and the refusal names the branch that is not reachable" "yes" \
  "$(contains "$CO_OUT" "wt/01-y")"
expect_eq "2c: …wt/01-y survives" "yes" "$(branch_exists "$P2" "wt/01-y")"
expect_eq "2d: …and so does wt/01-x — a refusal deletes nothing at all" "yes" \
  "$(branch_exists "$P2" "wt/01-x")"
expect_eq "2e: …the tmp wipe never ran" "3" "$(tmp_entries "$P2")"
expect_eq "2f: …no continuation was written" "no" \
  "$([ -f "$P2/$CONT_REL" ] && echo yes || echo no)"
expect_eq "2g: …and the plan is byte-for-byte what it was" "$PLAN_BEFORE" \
  "$(sha_of "$P2/$PLAN_REL")"

# The same fixture with the offending branch gone: the reachable one is deleted.
fixture_git "$P2" branch -D wt/01-y >/dev/null 2>&1
run_close "$P2" run
expect_eq "2h: with wt/01-y gone the run exits 0" "0" "$CO_RC"
expect_eq "2i: …and the fully reachable wt/01-x is deleted" "no" "$(branch_exists "$P2" "wt/01-x")"

# Membership by record: another wave's unmerged wt/07-z is named by no row, so it is neither refused on nor deleted,
# and check names only the registered tree that exists (wt/01-x; wt/01-y's branch is not made here).
P2F="$(mk_fixture p2f)"; advance_to "$P2F" 8
add_foreign_unreached_branch "$P2F"
run_close "$P2F" check
expect_eq "2j: check does not refuse over a foreign wt/07-z" "0" "$CO_RC"
expect_eq "2k: …and the census line names exactly the one registered tree in reach" "yes" \
  "$(contains "$CO_OUT" "worktree-removed: wt/01-x (1 registered tree)")"
expect_eq "2l: …never naming the foreign branch" "no" "$(contains "$CO_OUT" "wt/07-z")"

run_close "$P2F" run
expect_eq "2m: run does not refuse on the foreign branch either" "0" "$CO_RC"
expect_eq "2n: …wt/07-z survives — a foreign wave's tree is not this run's to judge" "yes" \
  "$(branch_exists "$P2F" "wt/07-z")"
expect_eq "2o: …while this wave's own wt/01-x is still deleted as before" "no" \
  "$(branch_exists "$P2F" "wt/01-x")"

# ============================================================
section "4 — check is a diagnosis: it reports and changes nothing"
# ============================================================

P4="$(mk_fixture p4)"; advance_to "$P4" 8
PLAN4_SHA="$(sha_of "$P4/$PLAN_REL")"
EPIC4_SHA="$(sha_of "$P4/$EPIC_REL")"
run_close "$P4" check

expect_eq "4a: check exits 0" "0" "$CO_RC"
expect_eq "4b: …reports the merge it would attest" "yes" "$(contains "$CO_OUT" "merge:")"
expect_eq "4c: …reports the branches it would delete" "yes" \
  "$(contains "$CO_OUT" "worktree-removed:")"
expect_eq "4d: …reports what the tmp wipe would take" "yes" \
  "$(contains "$CO_OUT" "tmp-wiped: 3 entries")"
expect_eq "4f: the plan is untouched" "$PLAN4_SHA" "$(sha_of "$P4/$PLAN_REL")"
expect_eq "4g: the epic plan is untouched" "$EPIC4_SHA" "$(sha_of "$P4/$EPIC_REL")"
expect_eq "4h: no continuation was written" "no" \
  "$([ -f "$P4/$CONT_REL" ] && echo yes || echo no)"
expect_eq "4i: .bionic/tmp/ still holds its three entries" "3" "$(tmp_entries "$P4")"
expect_eq "4j: wt/01-x still exists" "yes" "$(branch_exists "$P4" "wt/01-x")"

# ============================================================
section "4c — critic3 P-1 (T17): run asks the gate first; check and run agree"
# ============================================================
# Both verbs ask the real gate first, the close's facts pending, so a refusal leaves no half-closed run.
P18="$(mk_fixture p18)"; advance_to "$P18" 8
rm -f "$P18/.bionic/docs/record/generic-evidence.md"
PLAN18_SHA="$(sha_of "$P18/$PLAN_REL")"
EPIC18_SHA="$(sha_of "$P18/$EPIC_REL")"
run_close "$P18" check
expect_eq "4r: check on the evidence-missing plan exits 0" "0" "$CO_RC"
expect_eq "4t: …never the old sentence that promised the Step-8 block would clear it" "no" \
  "$(contains "$CO_OUT" "is what clears it")"

run_close "$P18" run
expect_eq "4v: run on the same plan refuses rc 2" "2" "$CO_RC"
expect_eq "4x: …before the first act: no merge: line was reported" "no" "$(contains "$CO_OUT" "merge: ")"
expect_eq "4y: …wt/01-x is still there" "yes" "$(branch_exists "$P18" "wt/01-x")"
expect_eq "4z: ….bionic/tmp/ still holds its three entries" "3" "$(tmp_entries "$P18")"
expect_eq "4aa: …no continuation was written" "no" \
  "$([ -f "$P18/$CONT_REL" ] && echo yes || echo no)"
expect_eq "4ab: …the epic plan is byte-for-byte what it was (no row for wave 01)" "$EPIC18_SHA" \
  "$(sha_of "$P18/$EPIC_REL")"
expect_eq "4ac: …the plan is byte-for-byte what it was" "$PLAN18_SHA" "$(sha_of "$P18/$PLAN_REL")"

# The control: the same fixture with its evidence. check says the gate allows the plan run
# would write, and run then performs the tail as §1 does.
P19="$(mk_fixture p19)"; advance_to "$P19" 8
run_close "$P19" run
expect_eq "4af: …and run on it exits 0" "0" "$CO_RC"
expect_eq "4ah: …and the attestation after step 8's event, as before" "yes" "$(contains "$CO_OUT" "gate: ok")"

# ============================================================
section "4d — critic3 P-3 (T17): run refuses unless the plan reads current: 8"
# ============================================================
# A plan below Step 8 is refused by name, before anything is touched.
for _co_cur in 7 4; do
  P20="$(mk_fixture "p20-$_co_cur")"
  advance_to "$P20" "$_co_cur"
  PLAN20_SHA="$(sha_of "$P20/$PLAN_REL")"
  EPIC20_SHA="$(sha_of "$P20/$EPIC_REL")"
  run_close "$P20" check
  run_close "$P20" run
  expect_eq "4aj.$_co_cur: run at current $_co_cur refuses rc 2" "2" "$CO_RC"
  expect_eq "4al.$_co_cur: …wt/01-x is still there" "yes" "$(branch_exists "$P20" "wt/01-x")"
  expect_eq "4am.$_co_cur: ….bionic/tmp/ still holds its three entries" "3" "$(tmp_entries "$P20")"
  expect_eq "4an.$_co_cur: …no continuation was written" "no" \
    "$([ -f "$P20/$CONT_REL" ] && echo yes || echo no)"
  expect_eq "4ao.$_co_cur: …the epic plan is unchanged" "$EPIC20_SHA" "$(sha_of "$P20/$EPIC_REL")"
  expect_eq "4ap.$_co_cur: …and the plan is unchanged (no Step-8 block written)" "$PLAN20_SHA" \
    "$(sha_of "$P20/$PLAN_REL")"
done

# ============================================================
section "VER — wave-27 T4 (AC-7.2, D14, B3): the released version is the run's, never the tool's"
# ============================================================
# The tool's version attests; the release written is the plan's `release:`, and none when it names none.
TOOLV="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_ROOT/payload/.claude-plugin/plugin.json" | head -1)"
RELV="7.7.7-fixture"
expect_nonempty "VER0: the tool's version reads from its manifest" "$TOOLV"
expect_ne "VER0b: …and differs from the release the fixture names" "$RELV" "$TOOLV"

# epic_version_cell <project> -> the version cell of the epic's wave-01 row, trimmed.
epic_version_cell() {
  grep '^| 01 |' "$1/$EPIC_REL" | head -1 | awk -F'|' '{ v = $3; gsub(/^[ \t]+|[ \t]+$/, "", v); print v }'
}
# delivered_line <project> -> the words the run's step 9 carries as delivered.
delivered_line() { co_step_answer "$1" | sed -n 's/^delivered=//p'; }

PV1="$(mk_fixture ver1)"; advance_to "$PV1" 8
awk -v r="$RELV" '{ print } /^walk: exempt$/ { print "release: " r }' "$PV1/$PLAN_REL" > "$PV1/plan.tmp" \
  && mv "$PV1/plan.tmp" "$PV1/$PLAN_REL"
run_close "$PV1" run
expect_eq "VER2: run with release: closes rc 0" "0" "$CO_RC"
DL1="$(delivered_line "$PV1")"
expect_nonempty "VER3: the delivered line is there to read" "$DL1"
expect_eq "VER4: …it carries the plan's release after the slug" "yes" "$(contains "$DL1" "wave-01-fixture $RELV — ")"
expect_eq "VER5: …and not the tool's version" "no" "$(contains "$DL1" "$TOOLV")"
expect_eq "VER6: the epic row's version cell is the plan's release" "$RELV" "$(epic_version_cell "$PV1")"
expect_eq "VER7: the continuation header carries the release" "yes" "$(contains "$(head -1 "$PV1/$CONT_REL")" "$RELV")"
expect_eq "VER8: …and not the tool's version" "no" "$(contains "$(head -1 "$PV1/$CONT_REL")" "$TOOLV")"

PV2="$(mk_fixture ver2)"; advance_to "$PV2" 8
run_close "$PV2" run
expect_eq "VER11: run with no release: closes rc 0" "0" "$CO_RC"
DL2="$(delivered_line "$PV2")"
expect_nonempty "VER12: the delivered line is there to read" "$DL2"
expect_eq "VER13: …it writes no version: the slug runs straight into the dash" "yes" "$(contains "$DL2" "wave-01-fixture — ")"
expect_eq "VER14: …and never the tool's" "no" "$(contains "$DL2" "$TOOLV")"
expect_eq "VER15: the epic row is there, with no version in its cell" "—" "$(epic_version_cell "$PV2")"
expect_eq "VER16: the continuation header names the wave" "yes" "$(contains "$(head -1 "$PV2/$CONT_REL")" "wave-01-fixture")"
expect_eq "VER17: …with no version in it" "no" "$(contains "$(head -1 "$PV2/$CONT_REL")" "$TOOLV")"

# ============================================================
section "E2E — wave-27 T4 (AC-7.1 close-out half, D14, B1): from Step 7 with no Step 9 line, the tools close the run"
# ============================================================
# No hand edit: the real `current 8`, admitted on the facts `plant_facts` holds, then `close-out.sh run` delivers.
PE="$(mk_fixture e2e)"
E2E_SID="closeout-e2e-1"
expect_eq "E2E0: precondition: the run stands at step 7 with no step 8 or 9 event" "n=7/0" \
  "$(co_step_answer "$PE" | head -1)/$(grep -c '|ev=step|n=[89]|' "$PE/$LOG_REL")"
expect_eq "E2E0c: precondition: …and a base-sha naming a commit at or before the readings' head" "yes" \
  "$(b="$(sed -n 's/^base-sha: //p' "$PE/$PLAN_REL")"; [ -n "$b" ] && fixture_git "$PE" merge-base --is-ancestor "$b" wave/01-fixture && echo yes || echo no)"
( in_fixture "$PE" || exit 1; . "$REPO_ROOT/tests/lib/bound-marker.sh"; bound_marker "$PE" "$E2E_SID" "$PE/$PLAN_REL" ); PE_SUM="$(sha_of "$PE/$PLAN_REL")"
# The advance's step event is stamped past any minute close-out writes on its Step lines (the log's clock seam, LOG_AT),
# as an advance and a close in one minute are: the closed run must read delivered all the same.
( in_fixture "$PE" || exit 9
  HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" LOG_AT=2099-01-01T00:00:59Z \
    CLAUDE_CODE_SESSION_ID="$E2E_SID" bash "$BIONIC_HOOKS_DIR/session-poker.sh" current 8 ) > "$SANDBOX/e2e-poker" 2>&1
E2E_POKER_RC=$?
E2E_POKER_OUT="$(cat "$SANDBOX/e2e-poker")"
expect_eq "E2E1: AC-7.1 the real current 8 is admitted on the facts (exit 0)" "0" "$E2E_POKER_RC"
expect_eq "E2E3: …and the run stands at step 8, its plan unwritten" "n=8|$PE_SUM" "$(bash "$REPO_ROOT/payload/scripts/reader.sh" "$PE/$PLAN_REL" step | head -1)|$(sha_of "$PE/$PLAN_REL")"
run_close "$PE" run
expect_eq "E2E4: AC-7.1 then close-out.sh run delivers (rc 0)" "0" "$CO_RC"
expect_eq "E2E5: …the run's step carries the delivery" "yes" "$( [ -n "$(delivered_line "$PE")" ] && echo yes || echo no)"
expect_eq "E2E6: …and reads closed, delivered at step 9 though the log's step 8 is stamped later than the close's lines" "1|n=9" \
  "$(run_open_rc "$PE/$PLAN_REL")|$(bash "$REPO_ROOT/payload/scripts/reader.sh" "$PE/$PLAN_REL" step | head -1)"

# THE SAME FUNCTION REFUSES IN CLOSE-OUT (D3). A fixture whose structure reading is the newest and
# fails: `check` says it would refuse, naming the failing line, and `run` refuses with nothing done.
PF="$(mk_fixture e2e-fail)"; advance_to "$PF" 8
bash -c '. "$1/proof.sh" && LOG_AT=2026-10-04T13:00:00Z proof_event "$2" kind=review "head=$3" evidence=record/wave-01-fixture/structure-fail.md \
  question=structure reader=w-read result=fail scope=piece' _ "$REPO_ROOT/payload/scripts/lib" "$PF/$PLAN_REL" "$(fixture_git "$PF" rev-parse wave/01-fixture)"
run_close "$PF" check
expect_eq "E2E8: …naming the failing reading and its evidence" "yes" \
  "$(contains "$CO_OUT" "$(printf 'review\tstructure\tbionic:critic\tpiece\tfailing\trecord/wave-01-fixture/structure-fail.md')")"
PF_SHA="$(sha_of "$PF/$PLAN_REL")"
run_close "$PF" run
expect_eq "E2E9: run refuses (rc 2)" "2" "$CO_RC"
expect_eq "E2E11: …the plan untouched and wt/01-x still standing (nothing was done)" "$PF_SHA/yes" \
  "$(sha_of "$PF/$PLAN_REL")/$(branch_exists "$PF" wt/01-x)"

# A RELEASE THAT WOULD SPLIT A CELL (A-orch-28): a `|` in `release:` is refused before any act.
PR="$(mk_fixture e2e-pipe)"; advance_to "$PR" 8
sed 's/^archive-root: /release: 1.2|3\narchive-root: /' "$PR/$PLAN_REL" > "$PR/$PLAN_REL.n" && mv "$PR/$PLAN_REL.n" "$PR/$PLAN_REL"
PR_SHA="$(sha_of "$PR/$PLAN_REL")"
run_close "$PR" run
expect_eq "E2E14: A-orch-28 run refuses a release holding a | (rc 2)" "2" "$CO_RC"
expect_eq "E2E16: …the plan untouched and wt/01-x still standing" "$PR_SHA/yes" "$(sha_of "$PR/$PLAN_REL")/$(branch_exists "$PR" wt/01-x)"
# THE CLOSE THAT DELIVERS RELEASES THE MERGE IT HELD: the refusal above held the merge on the run's register, and once the
# release is written whole the delivering close closes that ask.
co_hold_state() {  # <project> -> open|closed, the state of the run's latest hold:merge round; nothing when none
  bash -c '. "$1/run.sh" && . "$1/owed.sh" && owed_rounds hold:merge "$2" "$3"' _ "$REPO_ROOT/payload/scripts/lib" "$1/$PLAN_REL" "$1" 2>/dev/null \
    | tail -1 | cut -f3
}
expect_eq "E2E17: the refused close holds the merge on the run's register" "open" "$(co_hold_state "$PR")"
sed 's/^release: 1\.2|3$/release: 1.2.3/' "$PR/$PLAN_REL" > "$PR/$PLAN_REL.n" && mv "$PR/$PLAN_REL.n" "$PR/$PLAN_REL"
run_close "$PR" run
expect_eq "E2E18: …and the close that delivers releases it" "0|closed" "$CO_RC|$(co_hold_state "$PR")"

# ============================================================
section "BRANCH-AGREE — wave-39 T16 (D18; AC-12.1): one reader of the integration branch; close-out's check and closed-form name one branch"
# ============================================================
# One reader, lib/plan.sh `plan_integration_branch`: ## SDLC State first, the frontmatter as the fallback, asked of
# close-out's check and closed-form, the Step-0 card and the gate on one plan (handoff-file.test.sh asks the verb's).
# FIXTURE FIDELITY: mk_fixture's plan at Step 7, as a run that has not closed holds it (check reads it as a diagnosis,
# its step refusal one line among the rest), naming `integration-branch: main` under ## SDLC State as Step 0 writes
# it, with the frontmatter key a Step-0 plan also carries; `trunk` is a real branch at the seed, so both values name
# branches and only the order decides.
# fails-when: a door names the frontmatter's branch while ## SDLC State names another, or refuses a plan whose
# frontmatter alone names it.
ba_fm() {  # <project> <value> -> the plan's frontmatter carries integration-branch: <value>
  awk -v v="$2" 'NR == 1 && $0 == "---" { print; print "integration-branch: " v; next } { print }' "$1/$PLAN_REL" \
    > "$1/$PLAN_REL.ba" && mv "$1/$PLAN_REL.ba" "$1/$PLAN_REL"
}
ba_doors() {  # <project> -> BA_CHECK, BA_CLOSED: the branch close-out's check and closed-form name
  run_close "$1" check
  BA_CHECK="$(printf '%s\n' "$CO_OUT" | sed -n 's/^merge: .* from \([^ ]*\) @ .*$/\1/p')"
  run_close "$1" closed-form
  BA_CLOSED="$(printf '%s\n' "$CO_OUT" | sed -n 's/^branch: .* into \([^ ]*\)\.$/\1/p')"
}
PBA="$(CO_PLAN_AT=14 mk_fixture branch-agree)"
fixture_git "$PBA" branch trunk "$(fixture_git "$PBA" rev-list --max-parents=0 main)"
ba_fm "$PBA" trunk
expect_eq "BA0 precondition: ## SDLC State names main and the frontmatter trunk, both branches" "main|trunk|yes|yes" \
  "$(sed -n '/^## SDLC State/,/^## /s/^integration-branch: //p' "$PBA/$PLAN_REL")|$(sed -n '2s/^integration-branch: //p' "$PBA/$PLAN_REL")|$(branch_exists "$PBA" main)|$(branch_exists "$PBA" trunk)"
ba_doors "$PBA"
expect_eq "BA1 close-out check and closed-form name one branch, ## SDLC State's" "main|main" "$BA_CHECK|$BA_CLOSED"
# The card's Step-0 branch block reads the same reader. The card needs a ## Goal.
ba_card() {  # <project> -> the integration branch card.sh step0 prints for the plan, a ## Goal added first
  awk '/^## SDLC State/ && !g { print "## Goal"; print ""; print "A fixture goal."; print ""; g = 1 } { print }' "$1/$PLAN_REL" \
    > "$1/$PLAN_REL.g" && mv "$1/$PLAN_REL.g" "$1/$PLAN_REL"
  bash "$REPO_ROOT/payload/scripts/card.sh" step0 "$1/$PLAN_REL" 2>/dev/null | sed -n 's/^    integration  *\([^ ]*\) .*/\1/p'
}
expect_eq "BA3 the card names ## SDLC State's branch too" "main" "$(ba_card "$PBA")"

PBF="$(CO_PLAN_AT=14 mk_fixture branch-agree-fm)"
awk '/^## SDLC State/ { s = 1 } /^## Tasks/ { s = 0 } !(s && /^integration-branch:/)' "$PBF/$PLAN_REL" > "$PBF/$PLAN_REL.ba" \
  && mv "$PBF/$PLAN_REL.ba" "$PBF/$PLAN_REL"
ba_fm "$PBF" main
ba_doors "$PBF"
expect_eq "BA2b check and closed-form both name the frontmatter's branch, the fallback (check prints its merge verdict only past its refusal)" \
  "main|main" "$BA_CHECK|$BA_CLOSED"
expect_eq "BA4 the card reads the frontmatter's branch too when ## SDLC State names none" "main" "$(ba_card "$PBF")"
# The gate's merge-target check reads the plan's branch and its epic's through the same reader, at Step 8, on a plan
# and an epic at 15, each naming its branch in its header; it logs a finding when the two differ and never refuses.
# fails-when: the check is not asked of a page at 15, or asks some reader other than the plan's and the epic's headers.
ba_gate() {  # <project> <epic's branch> -> <plan version>|<gate audit lines for the plan, yes or no>|<merge-target finding>
  local e="$1/.bionic/docs/plans/epic-fx/epic.plan.md" a
  awk -v b="$2" 'NR == 1 && $0 == "---" { print; print "integration-branch: " b; next }
    /^canonical_sdlc_version: / { print "canonical_sdlc_version: 15"; next }
    /^## / { s = ($0 == "## SDLC State") } !s' "$e" > "$e.b" && mv "$e.b" "$e"
  awk 'NR == 1 && $0 == "---" { print; print "epic: epic-fx"; next } { print }' "$1/$PLAN_REL" > "$1/$PLAN_REL.e" \
    && mv "$1/$PLAN_REL.e" "$1/$PLAN_REL"
  advance_to "$1" 8; gate_rc "$1" >/dev/null
  a="$(cat "$SB_HOME"/.claude/logs/*/sdlc-audit.md 2>/dev/null | grep -F "($1/$PLAN_REL)")"
  printf '%s|%s|%s\n' "$(sed -n 's/^canonical_sdlc_version: //p' "$1/$PLAN_REL")" \
    "$(printf '%s\n' "$a" | grep -q 'evidence-gate ' && echo yes || echo no)" \
    "$(printf '%s\n' "$a" | sed -n "s/.* merge-target: \(plan integration-branch .*\) (.*/\1/p" | tail -1)"
}
expect_eq "BA6 a plan at 15 and its epic naming one branch: the gate reads them at Step 8 and logs no merge-target finding" \
  "15|yes|" "$(ba_gate "$(mk_fixture branch-agree-gate)" main)"
expect_eq "BA7 …naming two, it logs the finding with both" \
  "15|yes|plan integration-branch 'main' != epic 'epic-fx' integration-branch 'trunk'" "$(ba_gate "$(mk_fixture branch-differ-gate)" trunk)"
# One reader: a grep of hooks/ and payload/scripts/, copied with one planted reader, finds the plant and lib/plan.sh's
# two lines that ask the plan parser, and no other line naming the key outside a comment or a sentence a refusal prints.
BAT="$SANDBOX/ba-tree"; mkdir -p "$BAT/payload"; cp -R "$BIONIC_HOOKS_DIR" "$BAT/hooks"; cp -R "$REPO_ROOT/payload/scripts" "$BAT/payload/scripts"
printf '%s\n' 'v="$(plan_frontmatter_get "$p" integration-branch)"' > "$BAT/hooks/planted.sh"
expect_eq "BA5 the grep finds the planted reader and lib/plan.sh's, nothing else" "hooks/planted.sh:1 payload/scripts/lib/plan.sh:2" \
  "$( (cd "$BAT" && /usr/bin/grep -rn 'integration-branch' hooks payload) | /usr/bin/grep -vE '^[^:]+:[0-9]+:[[:space:]]*#|(die|usage|_co_refuse|log_finding)( [a-z-]+)? "' \
     | cut -d: -f1 | uniq -c | awk '{ print $2 ":" $1 }' | LC_ALL=C sort | paste -sd' ' -)"

# ============================================================
section "DEPLOY — a run that names a deploy target is delivered only with what was deployed, verified and monitored"
# ============================================================
dp_fixture() {  # <name> <deploy target> -> a fixture at step 8 whose plan names that target
  local p; p="$(mk_fixture "$1")"; advance_to "$p" 8
  sed "s|^deploy_target: n/a\$|deploy_target: $2|" "$p/$PLAN_REL" > "$p/$PLAN_REL.d" && mv "$p/$PLAN_REL.d" "$p/$PLAN_REL"
  printf '%s\n' "$p"
}
dp_close() {  # <project> <verb> [<option> <value>]... -> CO_OUT and CO_RC, as run_close with the options after the verb
  local proj="$1" verb="$2" f="$SANDBOX/co-out"; shift 2
  ( in_fixture "$proj" || exit 9
    HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
      bash "$SCRIPT" "$proj/$PLAN_REL" "$verb" "$@" ) > "$f" 2>&1
  CO_RC=$?; CO_OUT="$(cat "$f")"; rm -f "$f"
}
dp_events() { awk -F'|' '{ print $2 }' "$1/$LOG_REL" | LC_ALL=C sort -u | paste -sd' ' -; }
DP_GIVE=(--deployed "build 7 to vercel production" --verified "the smoke walk passed on the live URL" --monitored "uptime pages on a 5xx")
PDN="$(dp_fixture dp-none "vercel production")"
expect_eq "DP0: the fixture's plan names its target" "vercel production" "$(sed -n 's/^deploy_target: //p' "$PDN/$PLAN_REL")"
PDN_SUM="$(sha_of "$PDN/$PLAN_REL")"
dp_close "$PDN" check
expect_eq "DP3: check says the close would refuse, naming the three options, and changes nothing" "0|yes|yes|yes|yes|$PDN_SUM|3" \
  "$CO_RC|$(contains "$CO_OUT" "deploy: WOULD REFUSE")|$(contains "$CO_OUT" "--deployed '<")|$(contains "$CO_OUT" "--verified '<")|$(contains "$CO_OUT" "--monitored '<")|$(sha_of "$PDN/$PLAN_REL")|$(tmp_entries "$PDN")"
run_close "$PDN" run
expect_eq "DP1: given none of the three, the close refuses and the run stays open at 8" "2|n=8|state=open" \
  "$CO_RC|$(co_step_answer "$PDN" | sed -n 1p)|$(co_step_answer "$PDN" | tail -1)"
expect_eq "DP2: …before its first act, naming each option: no merge line, wt/01-x and the tmp entries stand" "yes|yes|yes|no|yes|3" \
  "$(contains "$CO_OUT" "--deployed '<")|$(contains "$CO_OUT" "--verified '<")|$(contains "$CO_OUT" "--monitored '<")|$(contains "$CO_OUT" "merge: ")|$(branch_exists "$PDN" wt/01-x)|$(tmp_entries "$PDN")"
dp_close "$PDN" run --deployed TBD --verified " " --monitored "uptime pages on a 5xx"
expect_eq "DP4: a placeholder the gate bans and an empty word are refused by name, the given one is not" "2|yes|yes|no" \
  "$CO_RC|$(contains "$CO_OUT" "deployed, whose 'TBD' is a placeholder")|$(contains "$CO_OUT" "verified (--verified")|$(contains "$CO_OUT" "monitored (--monitored")"
dp_close "$PDN" run "${DP_GIVE[@]}"
DP_A="$(co_step_answer "$PDN")"
expect_eq "DP5: given, the three stand on the delivery's step after the whole close, the archive's restatement kept them" "0|yes|yes|yes|yes|state=delivered" \
  "$CO_RC|$(contains "$DP_A" "deployed=build 7 to vercel production")|$(contains "$DP_A" "verified=the smoke walk passed on the live URL")|$(contains "$DP_A" "monitored=uptime pages on a 5xx")|$(contains "$DP_A" "archived=bionic: archive")|$(printf '%s\n' "$DP_A" | tail -1)"
expect_eq "DP6: …and both of the delivery's events carry them, the first the one that delivers" "2|2" \
  "$(grep -c '|ev=step|n=9|' "$PDN/$LOG_REL")|$(grep '|ev=step|n=9|' "$PDN/$LOG_REL" | grep -c '|deployed=build 7 to vercel production|verified=the smoke walk passed on the live URL|monitored=uptime pages on a 5xx|')"
PDO="$(mk_fixture dp-off)"; advance_to "$PDO" 8
dp_close "$PDO" run --deployed "build 7"
expect_eq "DP7: a run naming no target is refused the words, with nothing done" "2|yes|yes|n=8" \
  "$CO_RC|$(contains "$CO_OUT" "names no deploy target")|$(branch_exists "$PDO" wt/01-x)|$(co_step_answer "$PDO" | sed -n 1p)"
dp_close "$PDO" check
DP_CK="$CO_OUT"
run_close "$PDO" run
expect_eq "DP8: …given none, check owes none and run closes as before, no deploy on its step" "yes|0|yes|no" \
  "$(contains "$DP_CK" "deploy: none owed")|$CO_RC|$(contains "$(co_step_answer "$PDO")" "delivered=")|$(contains "$(co_step_answer "$PDO")" "deployed=")"
expect_eq "DP9: the deploy writes no new event type: both closes leave the same set" "$(dp_events "$PDO")" "$(dp_events "$PDN")"
expect_nonempty "DP9b: …and the set is read" "$(dp_events "$PDN")"

finish
