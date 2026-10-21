#!/bin/bash
# tests/close-out-1.test.sh — payload/scripts/close-out.sh, part 1 of 4: sections 0 through E2E.
#
# THE SUITE IS FOUR PARTS (wave-39 T6; D1, D13, REQ-3 AC-3.1). One close-out.test.sh promised more than the
# suite bar, ten minutes of the gate's promise, so it runs as four suites cut at section boundaries. Its
# governing design, its sandbox, and the fixture builders and helpers every part shares are in
# tests/close-out.prelude.sh, sourced below after the framework.
#
# Usage: bash tests/close-out-1.test.sh

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

# 0h–0m — REQ-6 (D5, ADR-032): the census is the REGISTER, never a name.
# `working-branch:`'s shape decides nothing any more; a `## Tasks` row's `worktree`
# cell does. This retires the old `wave/<digits>-<slug>` shape refusal (R6 finding 1
# was the reason the shape existed, and the register has neither of its failure
# modes: no consumer shape is ever refused, and no foreign branch is ever swept in).
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
#
# Critic C4's reproduction: a plan whose `## Tasks` table has NO `worktree` column at
# all (every plan this repository shipped through wave-16; every consumer plan on 1.8.3)
# yields an EMPTY register census, which silently turned `wt_unreached`'s refusal into a
# no-op — the arm's whole job is to refuse, and an empty census means it never can. The
# fix: when the table has no `worktree` column, `wt_unreached` falls back to the census
# every `wt/*` branch this repository holds, announced once on stderr so the fallback is
# never silent either way.

# ROWS_NOWT: hoisted to tests/close-out.prelude.sh (a later part reads it)

# 0o1-0o5: an unmerged wt/01-T1 (git cherry shows a `+` line against the working
# branch) — today (unfixed) this passes silently; the fix must refuse and say so.
P0O="$(mk_census_fixture_nowt p0o "wave/01-x" "$ROWS_NOWT")"; advance_to "$P0O" 8
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

# 0p: a columnless table whose only wt/* branch is fully merged — the fallback still
# fires (announced) but finds nothing to refuse, and the run proceeds.
P0P="$(mk_census_fixture_nowt p0p "wave/01-x" "$ROWS_NOWT")"; advance_to "$P0P" 8
(
  in_fixture "$P0P" || exit 1
  git checkout -q -b wave/01-x
  printf 'work\n' >> file.txt
  git commit -q -am "wave work" >/dev/null 2>&1
  git branch wt/01-T1 wave/01-x
  git checkout -q main
  git merge -q --no-ff -m "merge wave" wave/01-x >/dev/null 2>&1
)
plant_facts "$P0P"
run_close "$P0P" check
expect_eq "0p1: check does not WOULD-REFUSE — the only wt/* branch is fully merged" "no" \
  "$(contains "$CO_OUT" "WOULD REFUSE")"

run_close "$P0P" run
expect_eq "0p3: run proceeds — nothing in the fallback census carries unreached work" "0" "$CO_RC"

# ============================================================
section "0q — C7: the column-less fallback is scoped to wt/<NN>-*, exactly as 1.8.3 was"
# ============================================================
#
# Critic C7's reproduction: the fallback T24 shipped was `git for-each-ref 'refs/heads/wt/*'`
# — every `wt/*` branch this repository holds, unscoped by wave number. On a column-less
# plan (0o/0p's own shape) that means a DIFFERENT wave's leftover branch — one this task's
# wave never spawned and never merged — could trip act 2's refusal, or (on 1.8.3, the
# behaviour this restores) never could. Same fixture as 0p (own tree wt/01-T1 fully
# merged, so nothing of THIS wave's is unreached) plus a foreign wave's leftover
# (`wt/07-z`, cut from main, one unmerged commit — `add_foreign_unreached_branch`, whose
# own contract at :272-275 is that this branch "must never see it: not refused on, not
# deleted"). At 4e2ac66 (unfixed) this WOULD-REFUSEs and `run` refuses rc=2; at 72e07ec
# (1.8.3) and after this fix, `wt/07-z` falls outside `wt/01-*` and is invisible.

P0Q="$(mk_census_fixture_nowt p0q "wave/01-x" "$ROWS_NOWT")"; advance_to "$P0Q" 8
(
  in_fixture "$P0Q" || exit 1
  git checkout -q -b wave/01-x
  printf 'work\n' >> file.txt
  git commit -q -am "wave work" >/dev/null 2>&1
  git branch wt/01-T1 wave/01-x
  git checkout -q main
  git merge -q --no-ff -m "merge wave" wave/01-x >/dev/null 2>&1
)
add_foreign_unreached_branch "$P0Q"
plant_facts "$P0Q"
run_close "$P0Q" check
expect_eq "0q1: check does not WOULD-REFUSE over a foreign wt/07-z (out of wt/01-* scope)" "no" \
  "$(contains "$CO_OUT" "WOULD REFUSE")"
expect_eq "0q2: …never naming the foreign branch" "no" "$(contains "$CO_OUT" "wt/07-z")"

run_close "$P0Q" run
expect_eq "0q4: run does not refuse on the foreign branch" "0" "$CO_RC"
expect_eq "0q5: …wt/07-z survives — a foreign wave's tree is not this run's to judge" "yes" \
  "$(branch_exists "$P0Q" "wt/07-z")"

# ============================================================
section "0r — C7: a column-less WAVE-scale plan whose working-branch is not wave/<digits>-<slug> shaped refuses, as 1.8.3 did"
# ============================================================
#
# 1.8.3 derived its ENTIRE census (there was no register) from `working-branch:`'s shape
# and refused outright — before act 1, for both `check` and `run` — when no wave number
# could be read off it (`git show 72e07ec:payload/scripts/close-out.sh:242-245`). ADR-032
# retired that refusal for the register path (a `worktree` column names its own trees, no
# wave number needed), but a column-less plan has no register to fall back on — it is
# exactly 1.8.3's shape, and it must refuse exactly as 1.8.3 did rather than silently
# reach for an unscoped repo-wide census (C7's own finding). That refusal is kept for a
# `scale: wave` plan (this fixture's own scale — every fixture here is wave-scale); a
# task-scale plan has no wave number to want, and §ANY-BRANCH below pins it closing.

P0R="$(mk_census_fixture_nowt p0r "topic/not-a-wave-branch" "$ROWS_NOWT")"; advance_to "$P0R" 8
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
#
# A small late fix lives on a branch like `fixit/x`, never `wave/<digits>-<slug>`. A task-
# scale plan owns no wave, so there is no `wt/<NN>-*` to census and no wave number to
# refuse for lacking: the shape refusal is a wave-scale rule only. `wt_unreached` finds no
# branch to report and says nothing about a `wt/-*` glob.

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

# THE INTEGRATE ACT IS THE SCALE'S CELL (wave-38 T16; D25, AC-5.1). The task row's branch cell is
# `any` and its integrate cell `pr`: a task-scale plan on `fix/x`, NOT merged, closes; close-out
# merges nothing, prints the `gh pr create` command for the working branch against the
# integration branch and records it in the continuation. It never runs it. The wave-scale pair
# (0r above) still refuses a branch outside its `wave/<NN>-<slug>` cell.
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
HO_REL="$(sed -n 's/^handoff: \(.*\) written .*$/\1/p' "$P1/$PLAN_REL" | head -1)"
expect_eq "1r2: …under the file's kind line" "bionic-handoff/v1" "$(sed -n 1p "$P1/$HO_REL" 2>/dev/null)"
expect_eq "1r3: …whose last line is the one door, naming the file" "/bionic:canonical-sdlc $HO_REL" "$(tail -1 "$P1/$HO_REL" 2>/dev/null)"
expect_eq "1r4: …and the plan's ## Handoff points to the run's file in the handoffs folder" "yes" \
  "$([[ "$HO_REL" == .bionic/docs/record/handoffs/*-wave-01-fixture.md ]] && echo yes || echo "no: $HO_REL")"
expect_eq "1s: …and the open-run resume point is gone from the plan" "no" \
  "$(contains "$(cat "$P1/$PLAN_REL")" "the tail has not run")"

PLAN1="$(cat "$P1/$PLAN_REL")"
expect_eq "1t: the Step-8 line is CLOSED with a timestamp" "yes" \
  "$(grep -qE '^- Step 8: CLOSED [0-9]{4}-[0-9]{2}-[0-9]{2}T' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1u: …merge: on its own continuation line, never semicolon-joined" "yes" \
  "$(grep -qE '^  merge: ' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1v: …worktree-removed: on its own line" "yes" \
  "$(grep -qE '^  worktree-removed: ' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1w: …cleanup: done" "yes" \
  "$(grep -qE '^  cleanup: done' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1x: …tmp-wiped: on its own line" "yes" \
  "$(grep -qE '^  tmp-wiped: ' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1y: …tasks-completed: on its own line" "yes" \
  "$(grep -qE '^  tasks-completed: ' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1aa: the Step-9 line carries delivered: INLINE, the shape run.sh greps for" "yes" \
  "$(grep -qE '^[[:space:]]*-?[[:space:]]*Step 9:.*delivered:' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1ab: …with archived: on its own continuation line" "yes" \
  "$(grep -qE '^  archived: ' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1ac: …and current: advanced to 9" "yes" \
  "$(grep -qE '^current: 9$' <<< "$PLAN1" && echo yes || echo no)"
expect_eq "1ad: the (pending) placeholders are gone" "no" "$(contains "$PLAN1" "Step 8: (pending)")"

expect_eq "1ae: run_open now reads the plan as CLOSED" "1" "$(run_open_rc "$P1/$PLAN_REL")"
expect_eq "1af: the script's own gate dry-run reported ok" "yes" "$(contains "$CO_OUT" "gate: ok")"
expect_eq "1ag: AC-4.1 — the real bash-walls.sh allows the close-out commit" "0" "$(gate_rc "$P1")"
expect_eq "1ah: act 7 — archived: passes archive_run's line through" "yes" \
  "$(contains "$CO_OUT" "archived: bionic: archive")"
expect_eq "1ai: …and the run directory stayed, the epic being open" "yes" \
  "$([ -f "$P1/$PLAN_REL" ] && echo yes || echo no)"

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

# 2j–2o — REQ-6 (D5, ADR-032): the census is MEMBERSHIP BY RECORD. A DIFFERENT
# wave's leftover branch (`wt/07-z`, carrying a commit `main` never took) is outside
# that record entirely — no row of this plan names it — so `run` must not refuse on
# it or delete it, and `check`'s report line must name only the registered tree this
# plan actually holds (`wt/01-x`; `wt/01-y`'s row is registered too, but that branch
# does not exist yet in this fixture).
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
# THE PAIR THAT MAKES 1af/1ag NON-VACUOUS. A gate that allowed everything would report
# `gate: ok` after `run` for no reason at all. Here the SAME gate, on the SAME fixture,
# with only the Step-8 block missing, says it would refuse — so the two readings together
# say the gate is reading this plan and discriminating on what the script wrote into it.
expect_eq "4f: the plan is untouched" "$PLAN4_SHA" "$(sha_of "$P4/$PLAN_REL")"
expect_eq "4g: the epic plan is untouched" "$EPIC4_SHA" "$(sha_of "$P4/$EPIC_REL")"
expect_eq "4h: no continuation was written" "no" \
  "$([ -f "$P4/$CONT_REL" ] && echo yes || echo no)"
expect_eq "4i: .bionic/tmp/ still holds its three entries" "3" "$(tmp_entries "$P4")"
expect_eq "4j: wt/01-x still exists" "yes" "$(branch_exists "$P4" "wt/01-x")"

# ============================================================
section "4c — critic3 P-1 (T17): run asks the gate first; check and run agree"
# ============================================================
# `run` used to perform acts 1–6 (branch sweep, tmp wipe, continuation, epic row) and only
# then ask the gate, so a refusal the Step-8 block cannot clear left a half-closed run: the
# branches and this session's tmp state gone, the continuation and epic row written. And
# `check` printed one sentence for every refusal ("the Step-8 block run writes is what
# clears it"), so it could not say which outcome `run` would reach. Now both verbs write
# phase 8's block into a scratch copy of the plan, bind a synthetic marker to the copy,
# and ask the real gate; `run` touches nothing until that pre-flight passes.
P18="$(mk_fixture p18)"; advance_to "$P18" 8
rm -f "$P18/.bionic/docs/record/generic-evidence.md"
PLAN18_SHA="$(sha_of "$P18/$PLAN_REL")"
EPIC18_SHA="$(sha_of "$P18/$EPIC_REL")"
run_close "$P18" check
expect_eq "4r: check on the evidence-missing plan exits 0" "0" "$CO_RC"
expect_eq "4t: …never the old sentence that promised the Step-8 block would clear it" "no" \
  "$(contains "$CO_OUT" "is what clears it")"
expect_eq "4u: …and leaves no scratch copy beside the plan" "0" \
  "$(find "$P18/.bionic/docs/plans" -name '*preflight*' | wc -l | tr -d ' ')"

run_close "$P18" run
expect_eq "4v: run on the same plan refuses rc 2" "2" "$CO_RC"
expect_eq "4x: …before the first act: no merge: line was reported" "no" "$(contains "$CO_OUT" "merge: ")"
expect_eq "4y: …wt/01-x is still there" "yes" "$(branch_exists "$P18" "wt/01-x")"
expect_eq "4z: ….bionic/tmp/ still holds its three entries" "3" "$(tmp_entries "$P18")"
expect_eq "4aa: …no continuation was written" "no" \
  "$([ -f "$P18/$CONT_REL" ] && echo yes || echo no)"
expect_eq "4ab: …the epic plan is byte-for-byte what it was (no row for wave 01)" "$EPIC18_SHA" \
  "$(sha_of "$P18/$EPIC_REL")"
expect_eq "4ac: …the plan is byte-for-byte what it was (the block went into the copy only)" "$PLAN18_SHA" \
  "$(sha_of "$P18/$PLAN_REL")"
expect_eq "4ad: …and no scratch copy is left beside the plan" "0" \
  "$(find "$P18/.bionic/docs/plans" -name '*preflight*' | wc -l | tr -d ' ')"

# The control: the same fixture with its evidence. check says the gate allows the plan run
# would write, and run then performs the tail as §1 does.
P19="$(mk_fixture p19)"; advance_to "$P19" 8
run_close "$P19" check
run_close "$P19" run
expect_eq "4af: …and run on it exits 0" "0" "$CO_RC"
expect_eq "4ah: …and the attestation after the Step-8 block, as before" "yes" "$(contains "$CO_OUT" "gate: ok")"

# ============================================================
section "4d — critic3 P-3 (T17): run refuses unless the plan reads current: 8"
# ============================================================
# Nothing read `current:` before phase 9 wrote `current: 9`, so the dry-run judged whatever
# step the plan named and the refusal blamed the blocks run wrote. A plan below Step 8 is
# refused by name, before anything is touched; check reports the same verdict.
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
section "4e — critic4 Q-1 (T19), wave-27 T4 (D14, B2): the Step 9 line is close-out's to write; the wave table is still a presence check"
# ============================================================
# `run` used to delete branches, wipe tmp and write the continuation and epic row, and only
# then refuse for a plan with no `- Step 9:` line or an epic plan with no `| wave |` table.
# T19 made both presence checks before the first act. Since wave-27 T4 the first one is
# gone: `step-line 9` is refused by the poker as close-out's to write, so a plan reaches
# close-out with no Step 9 line, and close-out writes it. It is written with phase 8's block
# and never earlier, so a refusal still leaves the plan byte-for-byte as it was.
# presence_state: hoisted to tests/close-out.prelude.sh (a later part reads it)
# step_lines: hoisted to tests/close-out.prelude.sh (a later part reads it)
TA="$(mk_fixture t19a)"; advance_to "$TA" 8
expect_eq "q1.0: the fixture carries its Step-8 line (the counter reads this plan)" "1" "$(step_lines "$TA/$PLAN_REL" 8)"
expect_eq "q1.0b: …and no Step 9 line: nothing planted it" "0" "$(step_lines "$TA/$PLAN_REL" 9)"
run_close "$TA" check
expect_eq "q1.1b: …it says run writes it" "yes" "$(contains "$CO_OUT" 'run writes `- Step 9: (pending)`')"
run_close "$TA" run
expect_eq "q1.2: run on a plan with no Step 9 line closes rc 0" "0" "$CO_RC"
expect_eq "q1.3: …and the plan carries exactly one Step 9 line" "1" "$(step_lines "$TA/$PLAN_REL" 9)"
expect_eq "q1.4: …which is the delivered line" "yes" \
  "$(grep -qE '^- Step 9: delivered: ' "$TA/$PLAN_REL" && echo yes || echo no)"
expect_eq "q1.5: …written after the Step-8 block" "yes" \
  "$(awk '/^- Step 8: CLOSED /{s8=NR} /^- Step 9: delivered: /{s9=NR} END{print (s8 && s9 > s8) ? "yes" : "no"}' "$TA/$PLAN_REL")"

# A refusal on a plan with no Step 9 line writes no Step 9 line: the evidence file is gone,
# so the pre-flight refuses, and the plan is byte-for-byte what it was.
TD="$(mk_fixture t19d)"; advance_to "$TD" 8
rm -f "$TD/.bionic/docs/record/generic-evidence.md"
PRE_D="$(presence_state "$TD")"; PLAN_D_SHA="$(sha_of "$TD/$PLAN_REL")"
run_close "$TD" run
expect_eq "q1.6: a refused run on a plan with no Step 9 line exits 2" "2" "$CO_RC"
expect_eq "q1.6b: …the plan is byte-identical (no Step 9 line was written early)" "$PLAN_D_SHA" "$(sha_of "$TD/$PLAN_REL")"
expect_eq "q1.6c: …branch, tmp, continuation, current: and epic row untouched" "$PRE_D" "$(presence_state "$TD")"

# A plan written before T4, carrying a `- Step 9: (pending)` line by hand, still closes with
# one Step 9 line: close-out replaces the line it finds and adds none.
TE="$(mk_fixture t19e)"; advance_to "$TE" 8
awk '{ print } /^- Step 8: \(pending\)$/ { print "- Step 9: (pending)" }' "$TE/$PLAN_REL" > "$TE/plan.tmp" \
  && mv "$TE/plan.tmp" "$TE/$PLAN_REL"
expect_eq "q1.6d: precondition: the older plan carries its hand-written Step 9 line" "1" "$(step_lines "$TE/$PLAN_REL" 9)"
run_close "$TE" run
expect_eq "q1.6e: …it closes rc 0" "0" "$CO_RC"
expect_eq "q1.6f: …with exactly one Step 9 line, the delivered one" "1/yes" \
  "$(step_lines "$TE/$PLAN_REL" 9)/$(grep -qE '^- Step 9: delivered: ' "$TE/$PLAN_REL" && echo yes || echo no)"

TB="$(mk_fixture t19b)"; advance_to "$TB" 8
printf -- '---\ncanonical_sdlc_version: 14\n---\n\n# epic-fx\n\n## SDLC State\n\ncurrent: 4\n\n## Notes\n\nNo waves table yet.\n' > "$TB/$EPIC_REL"
PRE_B="$(presence_state "$TB")"; PLAN_B_SHA="$(sha_of "$TB/$PLAN_REL")"; EPIC_B_SHA="$(sha_of "$TB/$EPIC_REL")"
# wave-38 T15 (AC-4.4; D17): a missing shipped table is added, header first, never refused.
run_close "$TB" check
expect_eq "q1.7: check no longer refuses the missing wave table" "no" "$(contains "$CO_OUT" "WOULD REFUSE — no | wave | table")"
run_close "$TB" run
expect_eq "q1.8: run on an epic plan with no wave table closes rc 0" "0" "$CO_RC"
expect_eq "q1.11: …the row after the header and its rule line" "yes" \
  "$(awk '/^\| wave \| version /{h=NR} /^\|---\|/{if(h&&!r)r=NR} /^\| 01 \|/{w=NR} END{print (h && r == h + 1 && w > r) ? "yes" : "no"}' "$TB/$EPIC_REL")"

TC="$(mk_fixture t19c)"; advance_to "$TC" 8
run_close "$TC" check
expect_eq "q1.13: check on the valid fixture names no missing line" "no" "$(contains "$CO_OUT" "WOULD REFUSE — no ")"
run_close "$TC" run
expect_eq "q1.14: run on the valid fixture still succeeds" "0" "$CO_RC"

# ============================================================
section "VER — wave-27 T4 (AC-7.2, D14, B3): the released version is the run's, never the tool's"
# ============================================================
# `VERSION` is the INSTALLED bionic's (`plugin_root`'s plugin.json). It is what attests, and
# it used to be what the delivered line, the epic row and the continuation header called the
# release too — wave-26 corrected two of them by hand. The release is the plan's own
# `release:` field now, and with no field no version is written. The tool here is THIS
# checkout's payload (run_close pins BIONIC_PLUGIN_ROOT), read the way co_version reads it.
TOOLV="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_ROOT/payload/.claude-plugin/plugin.json" | head -1)"
RELV="7.7.7-fixture"
expect_nonempty "VER0: the tool's version reads from its manifest" "$TOOLV"
expect_ne "VER0b: …and differs from the release the fixture names" "$RELV" "$TOOLV"

# epic_version_cell <project> -> the version cell of the epic's wave-01 row, trimmed.
epic_version_cell() {
  grep '^| 01 |' "$1/$EPIC_REL" | head -1 | awk -F'|' '{ v = $3; gsub(/^[ \t]+|[ \t]+$/, "", v); print v }'
}
# delivered_line <project> -> the plan's Step 9 delivered line.
delivered_line() { grep -m1 '^- Step 9: delivered: ' "$1/$PLAN_REL"; }

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
# The target, AC-7.1: no hand edit. The real `session-poker.sh current 8` moves the plan,
# then `close-out.sh run` delivers. The session is bound to the plan the way engagement binds
# it (tests/lib/bound-marker.sh, the one bound-marker builder).
#
# RE-AUTHORED BY wave-27 T14 from T4's pin of the refusal (A-T4.1). The verb no longer
# dry-commits the plan at Step 8, where the gate asked for the Step-8 block only close-out
# writes; it asks lib/proof.sh `facts_state` at the working head instead (D3). `mk_fixture`
# holds what a run at Step 7 owes there (`plant_facts`: at `rigor: single`, `scale: wave`, the
# floor and the critic's three questions at piece scope and two at whole scope), so `current 8`
# moves the plan and `close-out.sh run` then delivers, with no hand edit.
PE="$(mk_fixture e2e)"
E2E_SID="closeout-e2e-1"
expect_eq "E2E0: precondition: the fixture is at current: 7 with no Step 8 block written and no Step 9 line" "7/0" \
  "$(sed -n 's/^current: //p' "$PE/$PLAN_REL")/$(step_lines "$PE/$PLAN_REL" 9)"
expect_eq "E2E0c: precondition: …and a base-sha naming a commit at or before the readings' head" "yes" \
  "$(b="$(sed -n 's/^base-sha: //p' "$PE/$PLAN_REL")"; [ -n "$b" ] && fixture_git "$PE" merge-base --is-ancestor "$b" wave/01-fixture && echo yes || echo no)"
( in_fixture "$PE" || exit 1; . "$REPO_ROOT/tests/lib/bound-marker.sh"; bound_marker "$PE" "$E2E_SID" "$PE/$PLAN_REL" )
( in_fixture "$PE" || exit 9
  HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    CLAUDE_CODE_SESSION_ID="$E2E_SID" bash "$BIONIC_HOOKS_DIR/session-poker.sh" current 8 ) > "$SANDBOX/e2e-poker" 2>&1
E2E_POKER_RC=$?
E2E_POKER_OUT="$(cat "$SANDBOX/e2e-poker")"
expect_eq "E2E1: AC-7.1 the real current 8 is admitted on the facts (exit 0)" "0" "$E2E_POKER_RC"
expect_eq "E2E3: …and the plan reads current: 8" "8" "$(sed -n 's/^current: //p' "$PE/$PLAN_REL")"
run_close "$PE" run
expect_eq "E2E4: AC-7.1 then close-out.sh run delivers (rc 0)" "0" "$CO_RC"
expect_eq "E2E5: …the plan carries the delivered line" "yes" "$( [ -n "$(delivered_line "$PE")" ] && echo yes || echo no)"
expect_eq "E2E6: …and reads closed" "1" "$(run_open_rc "$PE/$PLAN_REL")"

# THE SAME FUNCTION REFUSES IN CLOSE-OUT (D3). A fixture whose structure reading is the newest and
# fails: `check` says it would refuse, naming the failing line, and `run` refuses with nothing done.
PF="$(mk_fixture e2e-fail)"; advance_to "$PF" 8
bash -c '. "$1/proof.sh" && proof_add_line "$2" "$(proof_line review "$3" 2026-10-04T13:00:00Z record/wave-01-fixture/structure-fail.md structure w-read fail piece)"' \
  _ "$REPO_ROOT/payload/scripts/lib" "$PF/$PLAN_REL" "$(fixture_git "$PF" rev-parse wave/01-fixture)" > "$PF/$PLAN_REL.n" \
  && mv "$PF/$PLAN_REL.n" "$PF/$PLAN_REL"
run_close "$PF" check
expect_eq "E2E8: …naming the failing reading and its evidence" "yes" \
  "$(contains "$CO_OUT" "$(printf 'review\tstructure\tbionic:critic\tpiece\tfailing\trecord/wave-01-fixture/structure-fail.md')")"
PF_SHA="$(sha_of "$PF/$PLAN_REL")"
run_close "$PF" run
expect_eq "E2E9: run refuses (rc 2)" "2" "$CO_RC"
expect_eq "E2E11: …the plan untouched and wt/01-x still standing (nothing was done)" "$PF_SHA/yes" \
  "$(sha_of "$PF/$PLAN_REL")/$(branch_exists "$PF" wt/01-x)"
PG="$(mk_fixture e2e-holds)"; advance_to "$PG" 8
run_close "$PG" check

# A RELEASE THAT WOULD SPLIT A CELL (A-orch-28): a `|` in `release:` is refused before any act.
PR="$(mk_fixture e2e-pipe)"; advance_to "$PR" 8
sed 's/^archive-root: /release: 1.2|3\narchive-root: /' "$PR/$PLAN_REL" > "$PR/$PLAN_REL.n" && mv "$PR/$PLAN_REL.n" "$PR/$PLAN_REL"
PR_SHA="$(sha_of "$PR/$PLAN_REL")"
run_close "$PR" run
expect_eq "E2E14: A-orch-28 run refuses a release holding a | (rc 2)" "2" "$CO_RC"
expect_eq "E2E16: …the plan untouched and wt/01-x still standing" "$PR_SHA/yes" "$(sha_of "$PR/$PLAN_REL")/$(branch_exists "$PR" wt/01-x)"

# ============================================================
section "BRANCH-AGREE — wave-39 T16 (D18; AC-12.1): one reader of the integration branch; close-out's check and closed-form name one branch"
# ============================================================
# Two orders stood: close-out's check and run read ## SDLC State alone and refused a plan whose frontmatter alone named
# the branch, its closed-form fell back to the frontmatter, and the handoff verb read the frontmatter first
# (critic-structure-2; debt integration-branch-reader). D18 rules ## SDLC State first, the frontmatter as the fallback,
# and lib/plan.sh `plan_integration_branch` is that one reader. Here close-out's two doors are asked on one plan: `check`
# (its merge verdict) and `closed-form` (the branch line), then card.sh's Step-0 card and the gate's merge-target check. handoff-file.test.sh §BRANCH-AGREE asks the handoff verb and
# close-out on one plan in the verb's own world: this fixture is close-out's, and the verb's dry commit through the
# real gate is judged there at a worktree row's Step 4, a plan shape this suite does not build.
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
PBA="$(mk_fixture branch-agree)"
fixture_git "$PBA" branch trunk "$(fixture_git "$PBA" rev-list --max-parents=0 main)"
ba_fm "$PBA" trunk
expect_eq "BA0 precondition: ## SDLC State names main and the frontmatter trunk, both branches" "main|trunk|yes|yes" \
  "$(sed -n '/^## SDLC State/,/^## /s/^integration-branch: //p' "$PBA/$PLAN_REL")|$(sed -n '2s/^integration-branch: //p' "$PBA/$PLAN_REL")|$(branch_exists "$PBA" main)|$(branch_exists "$PBA" trunk)"
ba_doors "$PBA"
expect_eq "BA1 close-out check and closed-form name one branch, ## SDLC State's" "main|main" "$BA_CHECK|$BA_CLOSED"
# The card's Step-0 branch block and the gate's epic merge-target check read the same reader. The card needs a ## Goal;
# the gate reads at Step 8 against an epic naming trunk, and names the plan's branch in its finding when the two differ.
ba_card() {  # <project> -> the integration branch card.sh step0 prints for the plan, a ## Goal added first
  awk '/^## SDLC State/ && !g { print "## Goal"; print ""; print "A fixture goal."; print ""; g = 1 } { print }' "$1/$PLAN_REL" \
    > "$1/$PLAN_REL.g" && mv "$1/$PLAN_REL.g" "$1/$PLAN_REL"
  bash "$REPO_ROOT/payload/scripts/card.sh" step0 "$1/$PLAN_REL" 2>/dev/null | sed -n 's/^    integration  *\([^ ]*\) .*/\1/p'
}
ba_gate() {  # <project> -> the plan's branch the gate's merge-target finding names, at Step 8, its epic naming trunk
  local e="$1/.bionic/docs/plans/epic-fx/epic.plan.md"
  sed 's/^current: 4$/&\
integration-branch: trunk/' "$e" > "$e.b" && mv "$e.b" "$e"
  awk 'NR == 1 && $0 == "---" { print; print "epic: epic-fx"; next } { print }' "$1/$PLAN_REL" > "$1/$PLAN_REL.e" \
    && mv "$1/$PLAN_REL.e" "$1/$PLAN_REL"
  advance_to "$1" 8; gate_rc "$1" >/dev/null
  cat "$SB_HOME"/.claude/logs/*/sdlc-audit.md 2>/dev/null | grep -F "($1/$PLAN_REL)" \
    | sed -n "s/.* merge-target: plan integration-branch '\([^']*\)' != epic .*/\1/p" | tail -1
}
expect_eq "BA3 the card and the gate name ## SDLC State's branch too" "main|main" "$(ba_card "$PBA")|$(ba_gate "$PBA")"

PBF="$(mk_fixture branch-agree-fm)"
awk '/^## SDLC State/ { s = 1 } /^## Tasks/ { s = 0 } !(s && /^integration-branch:/)' "$PBF/$PLAN_REL" > "$PBF/$PLAN_REL.ba" \
  && mv "$PBF/$PLAN_REL.ba" "$PBF/$PLAN_REL"
ba_fm "$PBF" main
ba_doors "$PBF"
expect_eq "BA2b check and closed-form both name the frontmatter's branch, the fallback (check prints its merge verdict only past its refusal)" \
  "main|main" "$BA_CHECK|$BA_CLOSED"
expect_eq "BA4 the card and the gate read the frontmatter's branch too when ## SDLC State names none" "main|main" \
  "$(ba_card "$PBF")|$(ba_gate "$PBF")"
# One reader: a grep of hooks/ and payload/scripts/, copied with one planted reader, finds the plant and lib/plan.sh's
# two awk programs, and no other line naming the key outside a comment or a sentence a refusal prints.
BAT="$SANDBOX/ba-tree"; mkdir -p "$BAT/payload"; cp -R "$BIONIC_HOOKS_DIR" "$BAT/hooks"; cp -R "$REPO_ROOT/payload/scripts" "$BAT/payload/scripts"
printf '%s\n' 'v="$(plan_frontmatter_get "$p" integration-branch)"' > "$BAT/hooks/planted.sh"
expect_eq "BA5 the grep finds the planted reader and lib/plan.sh's, nothing else" "hooks/planted.sh:1 payload/scripts/lib/plan.sh:4" \
  "$( (cd "$BAT" && /usr/bin/grep -rn 'integration-branch' hooks payload) | /usr/bin/grep -vE '^[^:]+:[0-9]+:[[:space:]]*#|(die|usage|_co_refuse|log_finding)( [a-z-]+)? "' \
     | cut -d: -f1 | uniq -c | awk '{ print $2 ":" $1 }' | LC_ALL=C sort | paste -sd' ' -)"

finish
