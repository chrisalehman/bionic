#!/bin/bash
# tests/asks.test.sh — THE RUN'S ONE REGISTER OF ASKS (payload/scripts/lib/owed.sh).
#
# WHAT IT HOLDS. An ask is something the person owes a run, and it belongs to the run, not to the session that
# raised it: every session acting for the run writes it to `<docs>/record/<run>/asks.state`, every reader reads it
# there, and answering it once closes it for every session. An ask raised with no run stays in its session's file.
# The miss this suite was opened on: the close-out preflight refused a merge on a failing review and opened the
# waiver under a stand-in session (`closeout-preflight-<pid>`) whose file nothing that reads the run ever read, so
# the run's page said nothing was owed while the merge waited on a waiver.
#
# §ONE-REGISTER  a close-out preflight's `waive:` reaches the plan's register; a bound session reads it as its own;
#                closed in one session, closed for all; an ask with no run, or under a name that is no plan, stays
#                with its session
# §HELD          a close-out refused at Step 8 holds the merge, `hold:merge`, titled `merge held: <what holds it>` in a
#                person's words, the refusal its reply, from `run` and from `check` alike; a refusal before Step 8
#                holds nothing; the run that delivers closes it
# §HELD-FILL     while `hold:merge` is open the tick offers no FILL naming the integrate row, says `WAIT T<n> — hold:merge
#                open: <title>` for it, and the stop wall ends the turn; with the hold closed the same fixture offers it,
#                says no hold and the wall refuses (the differential control)
# §FAILED        `proof-add review … result=fail` opens `waive:<question>` at once; a passing reading of it closes it
# §FLAG          a review whose result is `flag` opens no `waive:`, recorded by the verb or met by the preflight (a finding of it
#                fixed by a landed row); the same projects with a failing reading newest open it (the differential control)
# §STOP          `decisions put D<n>` opens `decide:D<n>`, the ledger's ruling closes it; a deferral no person ruled
#                (the reader's rating, carried by the orchestrator's choice) opens `carry:<record>#<n>` at `disposition`
# §OPENED        a closed ask keeps its open line's instant as `opened=`, so the minutes it stood open can be counted
# §BORN-CLOSES   a fix born of a failing review's finding lands by `ready` at Step 8 and its green landing closes
#                `waive:<question>`, with no step advance; a landing after which the review still derives fail leaves it open
# §WAITS         `ask_waits_on` says `user` for every kind the user owes and for an unanswered waiver or finding, and
#                `event <what>` for a waiver answered no, a finding answered carry, a carry and a delivery; a held merge
#                waits on what its waivers wait on
# §ANSWER        `owed_answer` stores the answer on the open ask and leaves it open; a re-open keeps it, a fresh open has
#                none; the landing of the row a finding was carried to closes it; a finding moved fixed closes at once
#
# FIXTURE FIDELITY. The project is close-out's own (tests/close-out.prelude.sh, read by name): a git project at
# Step 8 whose newest structure reading fails, as close-out-1's E2E fixture plants it, and the preflight is the one
# `close-out.sh check` runs. The register is read through `owed_list_plan`, the reader the run's pages read.
#
# ANTI-VACUITY. Each absence is read through an extractor that, in the same fixture, returns the item it should:
# the list of session files holds the unbound session's file, and the register's open list holds a second ask.
#
# Usage: bash tests/asks.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"
S31_STOP_HOOK="${BIONIC_HOOKS_DIR}/stop.sh"
. "$(dirname "$0")/session-poker.prelude.sh"

command -v jq >/dev/null 2>&1 || { echo "asks: jq absent — suite cannot run"; exit 1; }

AS_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"

# The close-out fixture's builders, read by name out of tests/close-out.prelude.sh, so this suite holds no second
# copy of the fixture and a builder that changes there changes here.
CO_TESTS="$(dirname "$0")/close-out.prelude.sh"
as_import_fn() {  # <name> [<file>] -> the function, defined here, read out of close-out.prelude.sh, else out of <file>
  local body
  body="$(awk -v n="$1" 'index($0, n "() {") == 1 { p = 1 } p { print } p && /^}/ { exit }' "${2:-$CO_TESTS}")"
  if [ -z "$body" ]; then echo "as_import_fn: no $1 in ${2:-$CO_TESTS}" >&2; return 1; fi
  eval "$body"
}
REPO_ROOT="$BIONIC_SCRIPTS_DIR"
SCRIPT="$REPO_ROOT/payload/scripts/close-out.sh"
PLAN_REL=".bionic/docs/plans/epic-fx/wave-01-fixture.plan.md"
UNITS_LIB="$REPO_ROOT/payload/scripts/lib/units.sh"
SANDBOX="$(cd "$(mktemp -d "$TMPROOT/co.XXXXXX")" && pwd -P)"
SB_HOME="$SANDBOX/home"; mkdir -p "$SB_HOME/.claude"
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid

# as_owed <root> <sid> <function> [args...] -> what owed.sh answers for that session, with run.sh and binding.sh
# loaded as a hook has them.
as_owed() {
  local root="$1" sid="$2"; shift 2
  OWED_ROOT="$root" OWED_SID="$sid" bash -c '. "$1/run.sh" && . "$1/binding.sh" && . "$1/owed.sh" && shift && "$@"' \
    _ "$AS_LIB" "$@" 2>/dev/null
}
# as_register <root> <plan> -> the keys of the open asks the plan's register holds, one line, space-separated.
as_register() {
  bash -c '. "$1/run.sh" && . "$1/binding.sh" && . "$1/owed.sh" && owed_list_plan "$2" "$3"' _ "$AS_LIB" "$2" "$1" 2>/dev/null \
    | cut -f1 | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
}
as_tmp_owed() { ( cd "$1/.bionic/tmp" && ls owed-*.state 2>/dev/null ) | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'; }

# ============================================================
section "§ONE-REGISTER: a close-out preflight's waiver is the run's ask; closed in one session, closed for all"
# ============================================================
# fails-when: the waiver the preflight opens is missing from the plan's register, or stays open for the run after
# a session bound to it answers.
AS_MISSING=""
for _f in in_fixture fixture_git fixture_plan_text fixture_epic_text plant_facts mk_fixture advance_to run_close_as; do
  as_import_fn "$_f" || AS_MISSING="$AS_MISSING $_f"
done
expect_eq "ONE-0 close-out.prelude.sh's fixture builders were all read out of it" "" "$AS_MISSING"

AS_SIDA="as-closeout-session-a1a1a1a1"   # runs close-out, bound to nothing, as the orchestrator's helper call does
AS_SIDB="as-bound-session-b2b2b2b2"      # bound to the run: answers the ask
AS_SIDC="as-bound-session-c3c3c3c3"      # bound to the run: reads it
AS_SIDD="as-free-session-d4d4d4d4"       # no run at all
AS_SIDE="as-copy-session-e5e5e5e5"       # bound to a name that is no plan: a plan verb's scratch copy

PA="$(mk_fixture as-one)"; advance_to "$PA" 8
PA_PLAN="$PA/$PLAN_REL"
PA_REG="$PA/.bionic/docs/record/wave-01-fixture/asks.state"
bash -c '. "$1/proof.sh" && proof_add_line "$2" "$(proof_line review "$3" 2026-10-04T13:00:00Z record/wave-01-fixture/structure-fail.md structure w-read fail piece)"' \
  _ "$AS_LIB" "$PA_PLAN" "$(fixture_git "$PA" rev-parse wave/01-fixture)" > "$PA_PLAN.n" && mv "$PA_PLAN.n" "$PA_PLAN"
rm -f "$PA"/.bionic/tmp/owed-*.state

# An ask with no run open stays with its session.
as_owed "$PA" "$AS_SIDD" owed_open gate:free "gate act: free" "poker: GATE free" >/dev/null

run_close_as "$AS_SIDA" "$PA" check
expect_contains "ONE-1 precondition: check names the failing structure reading the merge would refuse on" \
  "$(printf 'review\tstructure\tbionic:critic\tpiece\tfailing')" "$CO_OUT"
expect_eq "ONE-2 the preflight's waiver is an open ask in the plan's register (owed_list_plan), beside the merge it holds" \
  "hold:merge waive:structure" "$(as_register "$PA" "$PA_PLAN")"
expect_contains "ONE-2b …filed at record/<run>/asks.state, carrying the refusal the commit gate printed" \
  "|key=waive:structure|state=open|" "$(cat "$PA_REG" 2>/dev/null)"
expect_eq "ONE-3 only the run-less session has a session file: no stand-in close-out session holds an ask" \
  "owed-$AS_SIDD.state" "$(as_tmp_owed "$PA")"
expect_contains "ONE-3b …and that file holds the run-less ask" "|key=gate:free|state=open|" \
  "$(cat "$PA/.bionic/tmp/owed-$AS_SIDD.state" 2>/dev/null)"

bound_marker "$PA" "$AS_SIDB" "$PA_PLAN"
bound_marker "$PA" "$AS_SIDC" "$PA_PLAN"
expect_eq "ONE-4 a session bound to the run reads the preflight's waiver as its own open ask (owed_list)" \
  "hold:merge waive:structure" "$(as_owed "$PA" "$AS_SIDC" owed_list | cut -f1 | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
as_owed "$PA" "$AS_SIDB" owed_open approve:release "approval: release" "poker: approve the release" >/dev/null
expect_eq "ONE-5 precondition: a second session's ask joins the same register" \
  "approve:release hold:merge waive:structure" "$(as_register "$PA" "$PA_PLAN")"
as_owed "$PA" "$AS_SIDB" owed_close waive:structure waive >/dev/null
expect_eq "ONE-6 answered in one session, the waiver is closed for the run; the other asks stay open" \
  "approve:release hold:merge" "$(as_register "$PA" "$PA_PLAN")"
expect_eq "ONE-6b …and for every session bound to it" \
  "approve:release hold:merge" "$(as_owed "$PA" "$AS_SIDC" owed_list | cut -f1 | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
expect_contains "ONE-6c …the register records who closed it" "|key=waive:structure|state=closed|by=waive|" \
  "$(cat "$PA_REG" 2>/dev/null)"
as_owed "$PA" "$AS_SIDC" owed_close approve:release approve >/dev/null
expect_eq "ONE-6d …and a third session's answer closes the second" "hold:merge" "$(as_register "$PA" "$PA_PLAN")"

# A scratch copy's name ends past `.plan.md`: it names no run, so its session keeps its own file and no record
# directory is made for the copy.
AS_COPY="$PA/.bionic/docs/plans/epic-fx/.wave-01-fixture.plan.md.preflight.4242"
cp "$PA_PLAN" "$AS_COPY"
bound_marker "$PA" "$AS_SIDE" "$AS_COPY"
as_owed "$PA" "$AS_SIDE" owed_open gate:copy "gate act: copy" "poker: GATE copy" >/dev/null
expect_contains "ONE-7 a session bound to a name that is no plan keeps its ask in its own file" \
  "|key=gate:copy|state=open|" "$(cat "$PA/.bionic/tmp/owed-$AS_SIDE.state" 2>/dev/null)"
expect_eq "ONE-7b …and the record holds the run's directory alone" "generic-evidence.md wave-01-fixture" \
  "$(ls -A "$PA/.bionic/docs/record" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
rm -f "$AS_COPY"

# as_ask <root> <plan> <key> <field 2-4> -> that field of the plan's open ask on <key> (2 sent, 3 title, 4 reply)
as_ask() {
  bash -c '. "$1/run.sh" && . "$1/binding.sh" && . "$1/owed.sh" && owed_list_plan "$2" "$3"' _ "$AS_LIB" "$2" "$1" 2>/dev/null \
    | awk -F'\t' -v k="$3" -v f="$4" '$1 == k { print $f; exit }'
}
# as_reading <project> <at> <record> <result> -> a structure reading of the working head planted in the plan, as
# close-out-1's E2E plants one
as_reading() {
  local plan="$1/$PLAN_REL"
  bash -c '. "$1/proof.sh" && proof_add_line "$2" "$(proof_line review "$3" "$4" "$5" structure w-read "$6" piece)"' \
    _ "$AS_LIB" "$plan" "$(fixture_git "$1" rev-parse wave/01-fixture)" "$2" "$3" "$4" > "$plan.n" && mv "$plan.n" "$plan"
}
as_refusal() { printf '%s\n' "$CO_OUT" | sed -n 's/^bionic: close-out refused — //p' | tail -1; }
as_has() { case "$1" in *"$2"*) echo yes ;; esac; }  # <haystack> <needle> -> yes when it holds it

# ============================================================
section "§HELD: a close-out refused at Step 8 holds the merge on the run's register, titled what holds it, the refusal its reply; the run that delivers closes it"
# ============================================================
# fails-when: a refused close-out leaves no held merge on the sheet (the plan's register, read by owed_list_plan).
# A refusal before Step 8 is a run not yet at its merge, so it holds nothing: the same fixture, advanced, then holds.
PH="$(mk_fixture as-held)"
PH_PLAN="$PH/$PLAN_REL"
as_reading "$PH" 2026-10-04T13:00:00Z record/wave-01-fixture/structure-fail.md fail
run_close_as "$AS_SIDA" "$PH" run
expect_eq "HELD-0 precondition: at Step 7 run refuses on the step (rc 2)" "2|yes" \
  "$CO_RC|$(as_has "$(as_refusal)" 'current: 7')"
expect_eq "HELD-0b …and holds nothing: the run is not at its merge" "" "$(as_register "$PH" "$PH_PLAN")"
advance_to "$PH" 8
run_close_as "$AS_SIDA" "$PH" run
PH_WHY="$(as_refusal)"
expect_eq "HELD-1 at Step 8 run refuses on the failing reading (rc 2), naming a reason" "2|yes" "$CO_RC|$([ -n "$PH_WHY" ] && echo yes)"
expect_eq "HELD-2 the refusal opens hold:merge on the plan's register (HELD-0b read the same extractor empty)" \
  "hold:merge" "$(as_register "$PH" "$PH_PLAN")"
PH_TITLE="$(as_ask "$PH" "$PH_PLAN" hold:merge 3)"
expect_eq "HELD-3 …its title the reason in product words: what holds the merge, not the refusal" \
  "merge held: the structure review failed" "$PH_TITLE"
expect_eq "HELD-3c …no hash, no function, no instruction in it: the refusal names all three, the title none" \
  "yes|yes|yes||||" \
  "$([ -n "$(printf '%s' "$PH_WHY" | /usr/bin/grep -oE '[0-9a-f]{40}')" ] && echo yes)|$(as_has "$PH_WHY" facts_state)|$(as_has "$PH_WHY" proof-add)|$(printf '%s' "$PH_TITLE" | /usr/bin/grep -oE '[0-9a-f]{7,}')|$(as_has "$PH_TITLE" facts_state)|$(as_has "$PH_TITLE" proof-add)|$(as_has "$PH_TITLE" 'nothing was done')"
expect_eq "HELD-3b …its reply the refusal's whole line" "bionic: close-out refused — $PH_WHY" "$(as_ask "$PH" "$PH_PLAN" hold:merge 4)"
run_close_as "$AS_SIDA" "$PH" run
expect_eq "HELD-4 refused again for the same reason: one ask, the title unchanged" "hold:merge|$PH_TITLE" \
  "$(as_register "$PH" "$PH_PLAN")|$(as_ask "$PH" "$PH_PLAN" hold:merge 3)"

PK="$(mk_fixture as-held-check)"; advance_to "$PK" 8
PK_PLAN="$PK/$PLAN_REL"
as_reading "$PK" 2026-10-04T13:00:00Z record/wave-01-fixture/structure-fail.md fail
run_close_as "$AS_SIDA" "$PK" check
PK_WHY="$(printf '%s\n' "$CO_OUT" | /usr/bin/grep -m1 'WOULD REFUSE')"
expect_eq "HELD-5 check at Step 8 reports a refusal (rc 0, a WOULD REFUSE line)" "0|yes" "$CO_RC|$([ -n "$PK_WHY" ] && echo yes)"
expect_eq "HELD-6 …and holds the merge, its title what the first refusal check reports holds it" \
  "hold:merge|merge held: the structure review failed" \
  "$(as_register "$PK" "$PK_PLAN" | tr ' ' '\n' | /usr/bin/grep -x hold:merge)|$(as_ask "$PK" "$PK_PLAN" hold:merge 3)"
expect_eq "HELD-6b …its reply that refusal, as check printed it" "close-out check: ${PK_WHY#"${PK_WHY%%[! ]*}"}" \
  "$(as_ask "$PK" "$PK_PLAN" hold:merge 4)"

# The reading is read again and passes: the next run delivers, and the merge it held is closed for the run.
as_reading "$PH" 2026-10-04T14:00:00Z record/wave-01-fixture/structure-pass.md pass
run_close_as "$AS_SIDA" "$PH" run
expect_eq "HELD-7 precondition: the reading passing, run delivers (rc 0)" "0" "$CO_RC"
[ "$CO_RC" = 0 ] || printf '      close-out said: %s\n' "$(printf '%s\n' "$CO_OUT" | tail -5)"
PH_REG="$PH/.bionic/docs/record/wave-01-fixture/asks.state"
expect_contains "HELD-8 the delivering run closes hold:merge on the register" "|key=hold:merge|state=closed|by=close-out delivered|" \
  "$(cat "$PH_REG" 2>/dev/null)"
expect_absent "HELD-8b …and no line of the register leaves it open after that (HELD-2 read it open)" \
  "|key=hold:merge|state=open|" "$(cat "$PH_REG" 2>/dev/null)"

# ---------- a run of the poker's own verbs, for the openers below ----------
# FIXTURE FIDELITY: session-poker-3 §FACT's shape, the plan bound to this session (s42_plan), its working branch
# checked out in a linked worktree with real commits, roster rows from the production writer with questions= appended.
AS_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
RF="$(make_repo as-verbs)"; ( cd "$RF" && git commit -q --allow-empty -m init )
git -C "$RF" config user.name "Dana Fixture"
RF_B="$(git -C "$RF" rev-parse HEAD)"
PF="$(s42_plan "$RF" 4 "  worktree: .worktrees/01-fixture
  base-sha: ${RF_B:0:8}
  branch: wave/01-fixture")"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$PF" > "$PF.tmp" && mv "$PF.tmp" "$PF"
s42_builds_landed "$PF"
( cd "$RF" && git add -f "$PF" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$RF/.worktrees/01-fixture" "$RF_B" ) >/dev/null 2>&1
RF_WT="$RF/.worktrees/01-fixture"
RF_C1="$(s57_commit "$RF_WT" lib/a.sh C1)"
RF_DIR="$RF/.bionic/docs/record/wave-01-fixture"; mkdir -p "$RF_DIR"
RF_REG="$RF_DIR/asks.state"
new_roster "$RF"
roster_row_fixture session="$SID" name=implementor agent_id=a-implementor subagent_type=implementor >> "$(roster_of "$RF")"
printf '%s|questions=evidence\n' "$(roster_row_fixture session="$SID" name=w-aud agent_id=a-w-aud subagent_type=bionic:auditor \
  files=.bionic/docs/record/wave-01-fixture/ev-fail.md,.bionic/docs/record/wave-01-fixture/ev-pass.md,.bionic/docs/record/wave-01-fixture/ev-flag.md,.bionic/docs/record/wave-01-fixture/ev-flag-fail.md,.bionic/docs/record/wave-01-fixture/ev-flag-pass.md)" >> "$(roster_of "$RF")"
as_rec() {  # <file> <head> <result> -> an evidence piece reading over base..<head>
  printf '# reading\n\nreviewed: %s..%s\nquestion: evidence\nresult: %s\nscope: piece\n\nwhat the reader found\n' \
    "${RF_B:0:10}" "$2" "$3" > "$RF_DIR/$1"
}
expect_regex "AS-0 precondition: the working branch's head is C1, a 40-hex commit" '^[0-9a-f]{40}$' "$RF_C1"

# ============================================================
section "§HELD-FILL: while hold:merge is open on the run's register the tick offers no FILL naming the integrate row and the stop wall ends the turn; with the hold closed the same fixture offers it and the wall refuses"
# ============================================================
# The register is the run's: a merge held by a refused close-out is not a row to dispatch, so readiness reads it
# (lib/fill.sh through lib/owed.sh `owed_list_plan`) and the tick and the wall, which ask the one library, agree.
# Only the integrate row is held; a work row ready beside it is offered whatever the register holds.
# FIXTURE FIDELITY: session-poker-5 §STEP's shape (s47_plan's reads table, the shipped tick and hooks/stop.sh), the plan
# at current: 8 with a ready integrate row; the hold is opened and closed by owed.sh's own writers on the run's register.
# The tick says why the row waits: `WAIT T<n> — hold:merge open: <the ask's title>`, through `fill_merge_hold`.
# fails-when: the tick prints FILL T1 while the hold is open, the wall refuses the turn that left it, the hold held a
# work row, closing it leaves the integrate row unoffered, or the tick names no hold on the row it holds back (or still
# names one after the hold closes).
HF="$(make_repo heldfill)"; new_roster "$HF"
HF_P="$(s47_plan "$HF" 8 \
  "| T1 | 8 | integrate | the merge | orchestrator | — | 10 | REQ-x | — | pending | approval:plan |")"
awk '!d && /^current:/ { print "current: 8"; d = 1; next } { print }' "$HF_P" > "$HF_P.t" && mv "$HF_P.t" "$HF_P"
hf_fill() { printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL T'; }
hf_wait() { printf '%s\n' "$OUT" | /usr/bin/grep '^poker: WAIT T1 — hold:merge open'; }
hf_tick() { forget_digest "$HF"; poke_pressure "$HF" 8192 1.0 tick; }
hf_wall() { s31_stop "$HF" "$(s31_transcript "$HF" "carry on")"; s31_decision; }
hf_hold() { OWED_PLAN="$HF_P" as_owed "$HF" hf-sid owed_open hold:merge "merge held: the structure review failed" "bionic: close-out refused"; }
hf_release() { OWED_PLAN="$HF_P" as_owed "$HF" hf-sid owed_close hold:merge "close-out delivered"; }
hf_tick
expect_eq "HF-0 the control: with no hold the tick over the Step-8 table exits 0 and offers the integrate row" "0|poker: FILL T1" "$RC|$(hf_fill)"
expect_eq "HF-0b …and the wall refuses the turn that left it" "block" "$(hf_wall)"
hf_hold
expect_eq "HF-1 precondition: the run's register holds hold:merge open" "hold:merge" "$(as_register "$HF" "$HF_P")"
hf_tick
expect_eq "HF-2 AC-8.1 with the hold open the tick exits 0 and offers no FILL naming the integrate row" "0|" "$RC|$(hf_fill)"
expect_eq "HF-2b …and its WAIT line names the held merge and what holds it" \
  "poker: WAIT T1 — hold:merge open: merge held: the structure review failed" "$(hf_wait)"
expect_eq "HF-3 …and the stop wall's answer is clean" "" "$(hf_wall)"
hf_release
hf_tick
expect_eq "HF-4 the hold closed, the same fixture offers the integrate row again" "poker: FILL T1" "$(hf_fill)"
expect_eq "HF-4c …and its WAIT line about the hold is gone (HF-2b's extractor)" "" "$(hf_wait)"
expect_eq "HF-4b …and the wall refuses again" "block" "$(hf_wall)"
# Only the integrate row is held: a work row ready under the same open hold is offered, and the wall refuses its turn.
HW="$(make_repo heldwork)"; new_roster "$HW"
HW_P="$(s47_plan "$HW" 8 "| T1 | 4 | build | a work row | implementor | — | 10 | REQ-x | payload/a.sh | pending | |")"
OWED_PLAN="$HW_P" as_owed "$HW" hw-sid owed_open hold:merge "merge held: the structure review failed" "bionic: close-out refused"
expect_eq "HF-5 precondition: the hold is open on the second run's register" "hold:merge" "$(as_register "$HW" "$HW_P")"
forget_digest "$HW"; poke_pressure "$HW" 8192 1.0 tick
expect_eq "HF-5b the hold open, the tick still offers the ready work row" "poker: FILL T1" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL T')"
s31_stop "$HW" "$(s31_transcript "$HW" "carry on")"
expect_eq "HF-5c …and the wall refuses the turn that left it" "block" "$(s31_decision)"

# ============================================================
section "§FAILED: a failing reading recorded opens the waiver at once; a passing reading of the question closes it"
# ============================================================
# fails-when: the register lacks waive:<question> until an advance or a commit is refused. No advance and no commit
# is asked between the proof and the read below.
as_rec ev-fail.md "$RF_C1" fail
poke "$RF" proof-add review record/wave-01-fixture/ev-fail.md --question evidence --reader w-aud
expect_eq "FL-0 precondition: proof-add registers the failing reading (exit 0)" "0" "$RC"
[ "$RC" = 0 ] || printf '      proof-add said: %s\n' "$OUT"
expect_eq "FL-1 the waiver is an open ask on the run's register at once" "waive:evidence" "$(as_register "$RF" "$PF")"
expect_eq "FL-1b …titled as the judge titles it, its reply naming the reading and what it asks" \
  "waiver: evidence|yesyes" \
  "$(as_ask "$RF" "$PF" waive:evidence 3)|$(as_has "$(as_ask "$RF" "$PF" waive:evidence 4)" ev-fail.md)$(as_has "$(as_ask "$RF" "$PF" waive:evidence 4)" 'waive evidence')"
RF_C2="$(s57_commit "$RF_WT" lib/a.sh C2)"
as_rec ev-pass.md "$RF_C2" pass
poke "$RF" proof-add review record/wave-01-fixture/ev-pass.md --question evidence --reader w-aud
expect_eq "FL-2 precondition: a passing reading of the same question registers (exit 0)" "0" "$RC"
[ "$RC" = 0 ] || printf '      proof-add said: %s\n' "$OUT"
expect_eq "FL-3 …and closes the waiver for the run (FL-1 read the same extractor holding it)" "" "$(as_register "$RF" "$PF")"
expect_contains "FL-3b …the register says a passing reading closed it" "|key=waive:evidence|state=closed|by=passing reading|" \
  "$(cat "$RF_REG" 2>/dev/null)"

# ============================================================
section "§FLAG: a review whose result is flag opens no waiver, recorded or through the preflight; a failing one does"
# ============================================================
# A flag answers a question and is never read as failed. Recorded, the verb opens an ask only for a fail. Through the
# preflight, a flag whose finding a landed row fixed is settled by the run's landing record, which the preflight copy
# reads through the origin its marker names, so the gate never meets a failing reading and stages no ask.
# FIXTURE FIDELITY: the verb half is §FAILED's project and records (the verb dry-commits and writes the plan); the preflight
# half is close-out-4's flag_fixture, read out of that suite by name (the Step-8 project, the review flag over a record
# with a fixed finding and a note, the landed row's green verdict in the run's landing record), and the preflight is the
# one `close-out.sh check` runs.
# ANTI-VACUITY: in each half the same fixture, a failing reading made newest, opens `waive:evidence` or `waive:structure`
# and the register reader returns it, so the empty register before it is that reader's honest answer.
# fails-when: hooks/poker/proof.sh poker_verb_proof_add opens the waiver for any result but pass, so a recorded flag
# opens the ask (FLAG-2).
RF_C3="$(s57_commit "$RF_WT" lib/a.sh C3)"
as_rec ev-flag.md "$RF_C3" flag
poke "$RF" proof-add review record/wave-01-fixture/ev-flag.md --question evidence --reader w-aud
expect_eq "FLAG-1 precondition: proof-add registers the flag reading (exit 0)" "0" "$RC"
[ "$RC" = 0 ] || printf '      proof-add said: %s\n' "$OUT"
expect_eq "FLAG-2 a recorded flag opens no ask: the register holds no waive:evidence" "" "$(as_register "$RF" "$PF")"
RF_C4="$(s57_commit "$RF_WT" lib/a.sh C4)"
as_rec ev-flag-fail.md "$RF_C4" fail
poke "$RF" proof-add review record/wave-01-fixture/ev-flag-fail.md --question evidence --reader w-aud
expect_eq "FLAG-3 the same project, a failing reading recorded after it: the register holds the waiver" "waive:evidence" \
  "$(as_register "$RF" "$PF")"
RF_C5="$(s57_commit "$RF_WT" lib/a.sh C5)"
as_rec ev-flag-pass.md "$RF_C5" pass
poke "$RF" proof-add review record/wave-01-fixture/ev-flag-pass.md --question evidence --reader w-aud
expect_eq "FLAG-3a precondition: the passing reading registers (exit 0)" "0" "$RC"
[ "$RC" = 0 ] || printf '      proof-add said: %s\n' "$OUT"
expect_eq "FLAG-3b …and a passing reading closes it again, so the sections below meet the register as they did" "" \
  "$(as_register "$RF" "$PF")"
as_import_fn flag_fixture "$(dirname "$0")/close-out-4.test.sh" || echo "FLAG-0 flag_fixture not read out of close-out-4.test.sh"
PG="$(flag_fixture as-flag)"
PG_PLAN="$PG/$PLAN_REL"
rm -f "$PG"/.bionic/tmp/owed-*.state
run_close_as "$AS_SIDA" "$PG" check
expect_eq "FLAG-4 precondition: check asked the gate twice, the plan as it stands and the preflight (two gate lines)" "2" \
  "$(printf '%s\n' "$CO_OUT" | /usr/bin/grep -c '^gate: ')"
expect_eq "FLAG-5 through the preflight a flag opens no ask: no waive:structure, and no hold on the merge" "" "$(as_register "$PG" "$PG_PLAN")"
bash -c '. "$1/proof.sh" && proof_add_line "$2" "$(proof_line review "$3" 2026-10-22T11:00:00Z record/wave-01-fixture/structure-fail.md structure w-read fail piece)"' \
  _ "$AS_LIB" "$PG_PLAN" "$(fixture_git "$PG" rev-parse wave/01-fixture)" > "$PG_PLAN.n" && mv "$PG_PLAN.n" "$PG_PLAN"
run_close_as "$AS_SIDA" "$PG" check
expect_eq "FLAG-6 the same project with a failing reading newest: the register holds the waiver, beside the merge it holds" \
  "hold:merge waive:structure" "$(as_register "$PG" "$PG_PLAN")"

# ============================================================
section "§STOP: a decision put opens its ask and its ruling closes it; a carry the orchestrator chose opens an ask"
# ============================================================
# fails-when: `decisions put` or a deferred disposition writes no ask on the register.
RF_LED="$RF_DIR/design-ledger.md"
poke "$RF" decisions put D5 'stop the run: three fixes on one component'
expect_eq "ST-0 precondition: decisions put exits 0 on the bound run" "0" "$RC"
expect_eq "ST-1 the put opens decide:D5 on the run's register" "decide:D5" "$(as_register "$RF" "$PF")"
expect_eq "ST-1b …titled as the page owes a decision, its reply carrying the decision's own words" \
  "reply to D5|yes" \
  "$(as_ask "$RF" "$PF" decide:D5 3)|$(as_has "$(as_ask "$RF" "$PF" decide:D5 4)" 'D5 · stop the run: three fixes on one component: ')"
printf '\n## Δ9 — D5 ruled "1" (Dana Fixture 2026-10-21): stop the run: three fixes on one component\n' >> "$RF_LED"
poke "$RF" decisions put D6 'a second decision'
expect_eq "ST-2 D5 ruled in the ledger: the next decisions call closes its ask; D6's is open (ST-1 read D5 open)" \
  "decide:D6" "$(as_register "$RF" "$PF")"
expect_contains "ST-2b …the register says the ruling closed it" "|key=decide:D5|state=closed|by=ruled|" "$(cat "$RF_REG" 2>/dev/null)"
printf '\n## Δ10 — D6 ruled "2" (Dana Fixture 2026-10-21): a second decision\n' >> "$RF_LED"
poke "$RF" decisions
expect_eq "ST-2c the register read closes a ruled decision too" "0|" "$RC|$(as_register "$RF" "$PF")"

# A reader's S2 off finding is deferred by the severity table, a carry no person ruled; the disposition opens it.
RF_CR="record/wave-01-fixture/adv-carry.md"
printf '# reading\n\nreviewed: %s..%s\nquestion: adversarial\nresult: flag\nscope: piece\nfindings: 1\nfinding: 1 S2 off - a side path broken\n' \
  "${RF_B:0:10}" "$RF_C1" > "$RF/.bionic/docs/$RF_CR"
RF_PL="$(bash -c '. "$1/proof.sh" && proof_line review "$2" 2026-10-21T12:00:00Z "$3" adversarial w-crit flag piece' _ "$AS_LIB" "$RF_C1" "$RF_CR")"
RF_PL="$RF_PL" RF_CR="$RF_CR" awk '{ print } /^current: / && !p { print ENVIRON["RF_PL"]; print "deferred: " ENVIRON["RF_CR"] "#1 S2 off \"a side path broken\""; p = 1 }' \
  "$PF" > "$PF.tmp" && mv "$PF.tmp" "$PF"
poke "$RF" disposition
expect_contains "ST-3 precondition: the disposition reads the finding deferred" "state=deferred" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep "finding $RF_CR#1 ")"
expect_eq "ST-4 …and opens carry:<record>#<n> on the run's register" "carry:record:wave-01-fixture:adv-carry.md:1" \
  "$(as_register "$RF" "$PF")"
expect_contains "ST-4b …its reply naming the finding" "$RF_CR#1" "$(as_ask "$RF" "$PF" carry:record:wave-01-fixture:adv-carry.md:1 4)"
POKE_BOUND="$AS_BOUND_WAS"

# ============================================================
section "§OPENED: a closed ask keeps the instant it was opened, so the minutes it held a task can be counted"
# ============================================================
# fails-when: owed_close writes the closed line without the open line's instant.
AO="$(cd "$(mktemp -d "$TMPROOT/ao.XXXXXX")" && pwd -P)"; mkdir -p "$AO/.bionic/tmp"
AO_F="$AO/.bionic/tmp/owed-ao-sid.state"
as_owed "$AO" ao-sid owed_open approve:design "approval: design" "poker: WAIT T9 — approval:design"
AO_AT="$(sed -n 's/^owed\/v1|key=approve:design|state=open|.*|at=\([^|]*\)|title=.*/\1/p' "$AO_F" 2>/dev/null)"
expect_nonempty "OP-0 precondition: the open line carries the instant it was opened" "$AO_AT"
as_owed "$AO" ao-sid owed_close approve:design approve
expect_contains "OP-1 the closed line carries opened=, the open line's instant" \
  "|key=approve:design|state=closed|by=approve|at=" "$(cat "$AO_F" 2>/dev/null)"
expect_eq "OP-1b …its value the open line's at=" "$AO_AT" \
  "$(sed -n 's/^owed\/v1|key=approve:design|state=closed|.*|opened=\([^|]*\).*/\1/p' "$AO_F" 2>/dev/null)"

# ============================================================
section "§BORN-CLOSES: a born fix's green landing at Step 8 closes the review's waiver; a review still failing keeps it open"
# ============================================================
# FIXTURE FIDELITY: the landing line's model world (tests/lib/world.sh), built by the landing-line prelude's own
# `ll_world` and `ll_launch`, read by name, so this suite holds no second copy of it. The plan reads `current: 8` with a
# failing structure reading newest; T1's `- T1:` line carries the born marker `task-add --born` writes for finding 1.
# The ask is opened as the failing registration opens it (§FAILED drives the verb); the landing is the writer's `ready`.
# The control world differs in one fact: its record holds a second finding to fix that no row answers, so after the
# same landing the review still derives fail.
# ANTI-VACUITY: each world's register reads waive:structure open before the landing, through the extractor read after it.
# fails-when: lib/line.sh `line_publish` leaves the register alone after a born row's landing (BC-2, BC-2b), or closes
# the ask while the review still derives fail (BC-4).
. "$(dirname "$0")/lib/world.sh"
as_import_fn ll_world "$(dirname "$0")/landing-line.prelude.sh" || echo "BC-0 ll_world not read out of landing-line.prelude.sh"
as_import_fn ll_launch "$(dirname "$0")/landing-line.prelude.sh" || echo "BC-0 ll_launch not read out of landing-line.prelude.sh"
ll_plan() { printf '%s/.bionic/docs/plans/epic-x/wave-x.plan.md' "$1"; }
bc_world() {  # <findings to fix: 1 | 2> -> a world at current 8 whose register holds waive:structure open
  local r p h b n="$1"
  r="$(ll_world)" || return 1
  ll_launch "$r" T1 a.test.sh
  p="$(ll_plan "$r")"; h="$(git -C "$r" rev-parse wave/x)"; b="$(git -C "$r" rev-parse main)"
  mkdir -p "$r/.bionic/docs/record/wave-x"
  { printf 'reviewed: %s..%s\nquestion: structure\nresult: fail\nscope: piece\n\nfindings: %s\n' "$b" "$h" "$n"
    printf 'finding: 1 S1 off T1.txt:1 the row is wrong\nshown: 1 cat T1.txt\n'
    [ "$n" = 1 ] || printf 'finding: 2 S1 off T2.txt:1 the other row is wrong\nshown: 2 cat T2.txt\n'; } > "$r/.bionic/docs/record/wave-x/rev.md"
  BC_H="$h" BC_B="$b" awk '
    /^working-branch: / && !fm { fm = 1; print; print "rigor: single"; print "scale: task"; print "base-sha: " ENVIRON["BC_B"]; next }
    /^current: 4$/ { print "current: 8"; print "proved: kind=review head=" ENVIRON["BC_H"] " at=2026-10-20T00:00:00Z evidence=record/wave-x/rev.md question=structure reader=w-rev result=fail scope=piece"; next }
    /^- T1: active$/ { print "- T1: active — added by task-add at 2026-10-20T00:00:00Z born: review S1 off of=record/wave-x/rev.md#1"; next }
    { print }' "$p" > "$p.n" && mv "$p.n" "$p"
  OWED_ROOT="$r" OWED_SID="$WORLD_SID" OWED_PLAN="$p" bash -c '. "$1/run.sh" && . "$1/binding.sh" && . "$1/owed.sh" && owed_open waive:structure "waiver: structure" "waive structure"' \
    _ "$AS_LIB" 2>/dev/null
  printf '%s' "$r"
}
bc_ready() {  # <root> -> BC_OUT, BC_RC: T1's ready, from its tree, as the world's session
  BC_OUT="$( cd "$1/.worktrees/T1" && CLAUDE_CODE_SESSION_ID="$WORLD_SID" bash "$BIONIC_SCRIPTS_DIR/payload/scripts/spawn-worktree.sh" ready 2>&1 )"; BC_RC=$?
}
BC="$(bc_world 1)"; BC_P="$(ll_plan "$BC")"
expect_eq "BC-0 precondition: at current 8 the register holds waive:structure open" "8|waive:structure" \
  "$(sed -n 's/^current: //p' "$BC_P")|$(as_register "$BC" "$BC_P")"
bc_ready "$BC"
expect_eq "BC-1 the born row lands by ready (exit 0)" "0" "$BC_RC"
[ "$BC_RC" = 0 ] || printf '      ready said: %s\n' "$BC_OUT"
expect_eq "BC-2 …and its green landing closes waive:structure: the register holds no open ask (BC-0 read it open)" "" \
  "$(as_register "$BC" "$BC_P")"
expect_contains "BC-2b …closed by the landing" "|key=waive:structure|state=closed|by=landing T1|" \
  "$(cat "$BC/.bionic/docs/record/wave-x/asks.state" 2>/dev/null)"
expect_eq "BC-2c …with no step advance" "8" "$(sed -n 's/^current: //p' "$BC_P")"
BC2="$(bc_world 2)"; BC2_P="$(ll_plan "$BC2")"
expect_eq "BC-3 precondition: the control world's register holds waive:structure open" "waive:structure" "$(as_register "$BC2" "$BC2_P")"
bc_ready "$BC2"
expect_eq "BC-3b the same born row lands in the control world (exit 0)" "0" "$BC_RC"
expect_eq "BC-4 …and with the review still deriving fail (finding 2 unanswered) waive:structure stays open" "waive:structure" \
  "$(as_register "$BC2" "$BC2_P")"


# ============================================================
section "§WAITS: one function says what each ask waits on, the user or an event, from its kind and its answer"
# ============================================================
# FIXTURE FIDELITY: a session store written by owed.sh's own writers, one open ask of each kind the run raises, two
# waivers and three findings of which the answered ones were answered through `owed_answer`, as the verbs answer them.
# ANTI-VACUITY: every key reads through the same call; the kinds that wait on the user stand beside the answered ones
# that read an event, and `owed_answer_of` returns the stored answer before an unanswered key reads none through it.
# fails-when: lib/owed.sh `ask_waits_on` reads a waiver answered no as `user` (WA-3), or a finding answered carry as
# `user` (WA-5), or any kind that waits on the user as an event.
AW="$(cd "$(mktemp -d "$TMPROOT/aw.XXXXXX")" && pwd -P)"; mkdir -p "$AW/.bionic/tmp"
aw() { as_owed "$AW" aw-sid "$@"; }
for _k in decide:D3 decide:goal:speed approve:step2 approve:merge gate:abc123 ruling:r1 row:AC-1.1 waive-row:AC-1.2 \
  waive:structure waive:adversarial finding:rec:a.md:1 finding:rec:a.md:2 finding:rec:a.md:3 carry:rec:a.md:4 \
  delivered:wave-x zz:odd; do
  aw owed_open "$_k" "fixture: $_k" "poker: fixture $_k" >/dev/null
done
aw owed_answer waive:adversarial no "review adversarial re-run"; AW_RC1=$?
aw owed_answer finding:rec:a.md:2 carry "T9 lands"; AW_RC2=$?
aw owed_answer finding:rec:a.md:3 carry; AW_RC3=$?
expect_eq "WA-0 precondition: every ask is open in the store and the three answers were taken (rc 0 each)" "16|0 0 0" \
  "$(aw owed_list | wc -l | tr -d ' ')|$AW_RC1 $AW_RC2 $AW_RC3"
expect_eq "WA-0b …the answered waiver's answer reads back through owed_answer_of" "no|review adversarial re-run" \
  "$(aw owed_answer_of waive:adversarial | awk -F'\t' '{ print $1 "|" $3 }')"
expect_eq "WA-0c …and the unanswered waiver reads none through the same call" "" "$(aw owed_answer_of waive:structure)"
AW_USER=""
for _k in decide:D3 decide:goal:speed approve:step2 approve:merge approve:D3 gate:abc123 ruling:r1 row:AC-1.1 waive-row:AC-1.2 \
  waive:structure finding:rec:a.md:1 zz:odd; do
  AW_USER="$AW_USER $_k=$(aw ask_waits_on "$_k")"
done
expect_eq "WA-1 a decision, a goal declared missed, an approval, a gate, a ruling, a matrix ruling, an unanswered waiver, an unanswered finding and an unknown kind wait on the user" \
  " decide:D3=user decide:goal:speed=user approve:step2=user approve:merge=user approve:D3=user gate:abc123=user ruling:r1=user row:AC-1.1=user waive-row:AC-1.2=user waive:structure=user finding:rec:a.md:1=user zz:odd=user" \
  "$AW_USER"
expect_eq "WA-2 …each on one line, the word alone" "1" "$(aw ask_waits_on waive:structure | wc -l | tr -d ' ')"
expect_eq "WA-3 a waiver answered no waits on its review's next run" "event review adversarial re-run" "$(aw ask_waits_on waive:adversarial)"
expect_eq "WA-4 a finding answered carry with its row named waits on that row's landing" "event T9 lands" "$(aw ask_waits_on finding:rec:a.md:2)"
expect_eq "WA-5 a finding answered carry with no row named waits on the release card" "event release card" "$(aw ask_waits_on finding:rec:a.md:3)"
expect_eq "WA-6 a carry the run chose waits on the release card" "event release card" "$(aw ask_waits_on carry:rec:a.md:4)"
expect_eq "WA-7 a delivery waits on the close-out" "event close-out" "$(aw ask_waits_on delivered:wave-x)"
# hold:merge waits on the waivers that hold the merge: the user while one is unanswered or none is open, else their event.
AH="$(cd "$(mktemp -d "$TMPROOT/ah.XXXXXX")" && pwd -P)"; mkdir -p "$AH/.bionic/tmp"
ah() { as_owed "$AH" ah-sid "$@"; }
ah owed_open hold:merge "merge held: a failing review" "bionic: close-out refused" >/dev/null
expect_eq "WA-8 a merge held with no waiver open waits on the user" "user" "$(ah ask_waits_on hold:merge)"
ah owed_open waive:structure "waiver: structure" "waive structure" >/dev/null
ah owed_answer waive:structure no "review structure re-run"
expect_eq "WA-9 a merge held by one waiver answered no waits on that review's next run" "event review structure re-run" \
  "$(ah ask_waits_on hold:merge)"
ah owed_open waive:evidence "waiver: evidence" "waive evidence" >/dev/null
expect_eq "WA-10 …and on the user once a second waiver holding it is unanswered" "user" "$(ah ask_waits_on hold:merge)"
ah owed_answer waive:evidence no "review evidence re-run"
expect_eq "WA-11 …and on both reviews once both are answered no" "event review structure re-run, review evidence re-run" \
  "$(ah ask_waits_on hold:merge)"

# ============================================================
section "§ANSWER: the register stores the answer on the open ask without closing it; the ask closes at its event"
# ============================================================
# FIXTURE FIDELITY: the answer is written through `owed_answer`, the one writer the verbs call; the landing is the
# writer's own `ready` in §BORN-CLOSES's model world (`bc_world`), and `to=fixed` is `finding-move` run as the poker
# runs it on §STOP's project.
# ANTI-VACUITY: each absence is read through the extractor that, in the same fixture, first returned the item open or
# the answer stored; the landing closes one carried finding and leaves the two whose events have not come.
# fails-when: lib/owed.sh `owed_answer` closes the ask or drops its answer on a re-open (AN-2, AN-4); lib/line.sh's
# landing arm leaves a finding carried to the landed row open (AN-9) or closes one carried to another row (AN-10);
# hooks/poker/proof.sh stops closing a finding moved fixed at once (AN-12), or `carried` closes the finding at once, drops
# its answer or its row-named event, or accepts a row the table lacks (AN-13, AN-14).
AA="$(cd "$(mktemp -d "$TMPROOT/aa.XXXXXX")" && pwd -P)"; mkdir -p "$AA/.bionic/tmp"
AA_F="$AA/.bionic/tmp/owed-aa-sid.state"
aa() { as_owed "$AA" aa-sid "$@"; }
aa owed_open waive:structure "waiver: structure" "waive structure" >/dev/null
aa owed_answer waive:structure no "review structure re-run"; AA_RC=$?
expect_eq "AN-1 the answer is taken (rc 0) and reads back: the word, the instant it was given, the event" \
  "0|no|yes|review structure re-run" \
  "$AA_RC|$(aa owed_answer_of waive:structure | awk -F'\t' '{ print $1 "|" ($2 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$/ ? "yes" : "no") "|" $3 }')"
expect_eq "AN-2 …and the ask stays open" "waive:structure" "$(aa owed_list | cut -f1)"
expect_contains "AN-2b …the open line carries answer= answered= event=" "|state=open|" \
  "$(/usr/bin/grep -F '|answer=no|answered=' "$AA_F" | /usr/bin/grep -F '|event=review structure re-run')"
expect_eq "AN-3 owed_list keeps its four tab columns for an answered ask" "4" "$(aa owed_list | awk -F'\t' '{ print NF }' | LC_ALL=C sort -u)"
aa owed_open waive:structure "waiver: structure" "waive structure" >/dev/null
expect_eq "AN-4 a re-open of the open ask, as a failing pass makes, keeps its answer" "no" "$(aa owed_answer_of waive:structure | cut -f1)"
aa owed_open finding:rec:b.md:1 "Finding S2 needs a ruling" "rule it" >/dev/null
aa owed_answer finding:rec:b.md:1 carry
aa owed_answer finding:rec:b.md:1 carry "T4 lands"
expect_eq "AN-5 the last answer on a key wins" "carry|T4 lands" "$(aa owed_answer_of finding:rec:b.md:1 | awk -F'\t' '{ print $1 "|" $3 }')"
cp "$AA_F" "$TMPROOT/aa-before"
aa owed_answer gate:never no; AA_RC=$?
expect_eq "AN-6 an answer to a key that is not open is refused (rc 1) and the store is byte-identical" "1|same" \
  "$AA_RC|$(cmp -s "$TMPROOT/aa-before" "$AA_F" && echo same || echo changed)"
aa owed_close waive:structure waive >/dev/null
aa owed_open waive:structure "waiver: structure" "waive structure" >/dev/null
expect_eq "AN-7 a fresh open after a close starts with no answer (AN-4 read the answer through the same call)" "waive:structure|" \
  "$(aa owed_list | cut -f1 | /usr/bin/grep -x waive:structure)|$(aa owed_answer_of waive:structure)"
# The landing of the row a finding was carried to closes it; the findings carried elsewhere stay open.
AL="$(bc_world 1)"; AL_P="$(ll_plan "$AL")"
al() { OWED_ROOT="$AL" OWED_SID="$WORLD_SID" OWED_PLAN="$AL_P" bash -c '. "$1/run.sh" && . "$1/binding.sh" && . "$1/owed.sh" && shift && "$@"' _ "$AS_LIB" "$@" 2>/dev/null; }
for _k in finding:rec:x.md:1 finding:rec:x.md:2 finding:rec:x.md:3; do al owed_open "$_k" "Finding S2 needs a ruling" "rule it" >/dev/null; done
al owed_answer finding:rec:x.md:1 carry "T1 lands"
al owed_answer finding:rec:x.md:2 carry "T7 lands"
al owed_answer finding:rec:x.md:3 carry
expect_eq "AN-8 precondition: the run's register holds the three findings open, read through the plan's register" \
  "finding:rec:x.md:1 finding:rec:x.md:2 finding:rec:x.md:3 waive:structure" "$(as_register "$AL" "$AL_P")"
expect_eq "AN-8b …the one carried to T1 waits on T1's landing, read through the plan and root" "event T1 lands" \
  "$(bash -c '. "$1/run.sh" && . "$1/binding.sh" && . "$1/owed.sh" && ask_waits_on finding:rec:x.md:1 "$2" "$3"' _ "$AS_LIB" "$AL_P" "$AL" 2>/dev/null)"
bc_ready "$AL"
expect_eq "AN-9 T1 lands by ready (exit 0)" "0" "$BC_RC"
[ "$BC_RC" = 0 ] || printf '      ready said: %s\n' "$BC_OUT"
expect_contains "AN-9b …and its landing closes the finding carried to it" "|key=finding:rec:x.md:1|state=closed|by=landing T1|" \
  "$(cat "$AL/.bionic/docs/record/wave-x/asks.state" 2>/dev/null)"
expect_eq "AN-10 …the finding carried to T7 and the one waiting on the release card stay open (AN-8 read all three open)" \
  "finding:rec:x.md:2 finding:rec:x.md:3" "$(as_register "$AL" "$AL_P")"
# A finding moved fixed by a row is answered by that row, and closes at once, answered or not.
POKE_BOUND=180
RF_FK="$(printf 'finding:%s' "$(printf '%s' "$RF_CR#1" | LC_ALL=C tr -c 'A-Za-z0-9._-' ':')")"
OWED_PLAN="$PF" as_owed "$RF" "$SID" owed_open "$RF_FK" "Finding S2 needs a ruling" "rule it" >/dev/null
OWED_PLAN="$PF" as_owed "$RF" "$SID" owed_answer "$RF_FK" carry
expect_contains "AN-11 precondition: the finding is open on the run's register, answered carry" "$RF_FK" "$(as_register "$RF" "$PF")"
poke "$RF" finding-move "$RF_CR#1" fixed T2
expect_eq "AN-12 finding-move … fixed T2 exits 0" "0" "$RC"
[ "$RC" = 0 ] || printf '      finding-move said: %s\n' "$OUT"
expect_contains "AN-12b …and closes the finding at once" "|key=$RF_FK|state=closed|by=finding-move fixed T2|" "$(cat "$RF_REG" 2>/dev/null)"
# A finding carried to a row by the verb is answered carry with the row named, and stays open: the row landing closes it.
printf 'finding: 2 S2 off - another side path broken\n' >> "$RF/.bionic/docs/$RF_CR"
sed 's/^findings: 1$/findings: 2/' "$RF/.bionic/docs/$RF_CR" > "$RF/.bionic/docs/$RF_CR.tmp" && mv "$RF/.bionic/docs/$RF_CR.tmp" "$RF/.bionic/docs/$RF_CR"
RF_FK2="$(printf 'finding:%s' "$(printf '%s' "$RF_CR#2" | LC_ALL=C tr -c 'A-Za-z0-9._-' ':')")"
OWED_PLAN="$PF" as_owed "$RF" "$SID" owed_open "$RF_FK2" "Finding S2 needs a ruling" "rule it" >/dev/null
expect_contains "AN-13 precondition: the second finding is open on the run's register" "$RF_FK2" "$(as_register "$RF" "$PF")"
cp "$PF" "$TMPROOT/an-plan-before"; cp "$RF_REG" "$TMPROOT/an-reg-before"
poke "$RF" finding-move "$RF_CR#2" carried T99
expect_eq "AN-14 finding-move … carried T99, a row the table lacks, is refused (exit 1) and plan and register are byte-identical" "1|same|same" \
  "$RC|$(cmp -s "$TMPROOT/an-plan-before" "$PF" && echo same || echo changed)|$(cmp -s "$TMPROOT/an-reg-before" "$RF_REG" && echo same || echo changed)"
poke "$RF" finding-move "$RF_CR#2" carried T2
expect_eq "AN-13 finding-move … carried T2 exits 0" "0" "$RC"
[ "$RC" = 0 ] || printf '      finding-move said: %s\n' "$OUT"
expect_eq "AN-13 …the register holds the finding open, answered carry, its event naming the row" "carry|T2 lands|open" \
  "$(OWED_PLAN="$PF" as_owed "$RF" "$SID" owed_answer_of "$RF_FK2" | awk -F'\t' '{ print $1 "|" $3 }')|$(as_register "$RF" "$PF" | tr ' ' '\n' | /usr/bin/grep -qxF "$RF_FK2" && echo open || echo gone)"
expect_contains "AN-13b …and the plan carries its moved: line naming the row" "moved: $RF_CR#2 to=carried row=T2 by=Dana Fixture at=" "$(cat "$PF")"
POKE_BOUND="$AS_BOUND_WAS"

finish
