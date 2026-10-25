#!/bin/bash
# tests/close-out-3.test.sh — payload/scripts/close-out.sh, part 3 of 4: sections §HAND-HOLDS through §REF.
#
# THE SUITE IS FOUR PARTS (wave-39 T6; D1, D13, REQ-3 AC-3.1). One close-out.test.sh promised more than the
# suite bar, ten minutes of the gate's promise, so it runs as four suites cut at section boundaries. Its
# governing design, its sandbox, and the fixture builders and helpers every part shares are in
# tests/close-out.prelude.sh, sourced below after the framework.
#
# Usage: bash tests/close-out-3.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"
. "$(dirname "$0")/lib/roster-row.sh"   # the one roster-row builder (cross-gate S17; wave-30 T23)
. "$(dirname "$0")/close-out.prelude.sh"

# ============================================================
section "§HAND-HOLDS — wave-35 T12 (REQ-8 AC-8.1, D17): the hand-hold count is folded from the lines the escape-hatch verbs wrote"
# ============================================================
# `landing-report --hand-holds <plan>` adds one line to the report: the uses of the escape-hatch verbs, by kind,
# each counted from the line its verb wrote and from nothing else. A prose line saying `by-hand` counts nothing.
# close-out prints that line on its card and writes it into the continuation under `## Hand-holds`; it reads it
# BEFORE the tmp wipe, because three kinds (amend, hold, extend) live on the roster and act 3 wipes the roster.
#
# THE SOURCES, each in the shape its writer prints (the fixture plants the shape, the roster through the one
# production row writer, the plan's proof lines through lib/proof.sh's own line builders):
#   by-hand        landing record      line/v1|ev=published|…|kind=hand|…            (lib/line.sh)
#   stop-runs      landing record      line/v1|ev=stop-run|…                         (session-poker.sh stop-run; wave-36 T11, D8)
#   declines/lifts fill ledger         fill-ledger/v1|…|state=decline| and |state=lift|   (the verbs; the Stop hook writes ok and hold)
#   amends         roster              distinct (name, amended=<value>) of the run's plan
#   holds          roster              distinct (name, held=<value>)
#   extensions     roster              distinct (name, extended=<value>)
#   waivers        plan                `waived: question=…` under ## SDLC State, and an AC block's `waiver: <who> <date> "<words>"`
#   second-floors  plan                `proved: kind=regression` lines past the first
# A roster row is re-written on every status change and copies `amended=`/`held=`, so a row counts once per value.
# HH_GATE: hoisted to tests/close-out.prelude.sh (a later part reads it)
HH_C="$(printf 'd%.0s' $(seq 40))"
# The report reads from the last build landing, the second build row's at 10:40, so the decline, the lift, the 10:00
# amend and that row's own hand landing fall before the window, and the date-only matrix waiver's day holds that start, so it is unplaced.
HH_WANT="hand-holds: total=6 · by-hand=0 · stop-runs=1 · declines=0 · lifts=0 · amends=1 · holds=1 · extensions=1 · waivers=1 · status-writes=0 · second-regressions=1 · adoptions=0 · fixed=0 · unplaced=1"
HH_ALL="hand-holds: total=11 · by-hand=1 · stop-runs=1 · declines=1 · lifts=1 · amends=2 · holds=1 · extensions=1 · waivers=2 · status-writes=0 · second-regressions=1 · adoptions=0 · fixed=0 · unplaced=0"
# hh_report: hoisted to tests/close-out.prelude.sh (a later part reads it)
# hh_plant <project> -> one use of every verb, and the prose that must count for nothing
hh_plant() {
  local p="$1" plan="$1/$PLAN_REL" rec="$1/.bionic/docs/record/wave-01-fixture" h w
  case "$p" in "$SANDBOX"/*) : ;; *) echo "hh_plant: refusing outside the sandbox: '$p'" >&2; return 1 ;; esac
  mkdir -p "$rec"
  # the landing record: a queue landing, a by-hand landing, and a prose line that says by-hand
  {
    printf 'line/v1|ev=ready|row=T1|name=w-T1|commit=%s|branch=wt/01-T1|tree=%s/.worktrees/01-T1|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T10:00:00Z\n' "$HH_C" "$p"
    printf 'line/v1|ev=published|row=T1|commit=%s|kind=queue|by=-|why=-|at=2026-10-06T10:30:00Z\n' "$HH_C"
    printf 'line/v1|ev=published|row=T2|commit=%s|kind=hand|by=Chris|why=the line was down|at=2026-10-06T10:40:00Z\n' "$HH_C"
    printf 'line/v1|ev=stop-run|request=2156|who=fixture:w-T3|kind=whole|key=tests/run.sh|by=fixture|why=parked behind a dead holder|at=2026-10-06T10:50:00Z\n'
    printf 'note: T3 was landed by-hand outside the line (kind=hand), says this prose line\n'
  } > "$rec/landing-proofs.log"
  # the fill ledger: a decline and its lift (the verbs' shapes), the Stop hook's hold and ok lines, and prose
  {
    printf 'fill-ledger/v1|at=2026-10-06T09:00:00Z|session=fixture|turn=|current=4|state=decline|ceiling=6|width=|open=|free=|ready=T1|launched=|declined=no room|missed=0|idle=|room=|named=T1|declined-on=-\n'
    printf 'fill-ledger/v1|at=2026-10-06T09:10:00Z|session=fixture|turn=|current=4|state=lift|ceiling=6|width=|open=|free=|ready=|launched=|declined=|missed=0|idle=|room=|lifted=T1\n'
    printf 'fill-ledger/v1|at=2026-10-06T09:20:00Z|session=fixture|turn=t1|current=4|state=hold|ceiling=|width=6|open=6|free=0|ready=T1|launched=|declined=|missed=0|idle=|room=0\n'
    printf 'fill-ledger/v1|at=2026-10-06T09:30:00Z|session=fixture|turn=t2|current=4|state=ok|ceiling=|width=6|open=5|free=1|ready=|launched=T1|declined=|missed=0|idle=|room=1\n'
    printf 'the orchestrator wrote state=decline here by hand and nobody counted it\n'
  } > "$rec/fill-ledger.log"
  # the roster: two amends (one row re-written twice), a hold, an extension, and another run's amend
  {
    roster_row_fixture status=identified name=w-a agent_id=aa plan="$plan" amended="2026-10-06T10:00:00Z widen the files"
    roster_row_fixture status=confirmed name=w-a agent_id=aa plan="$plan" amended="2026-10-06T10:00:00Z widen the files"
    roster_row_fixture status=identified name=w-b agent_id=ab plan="$plan" amended="2026-10-06T11:00:00Z add a suite"
    roster_row_fixture status=identified name=w-a agent_id=aa plan="$plan" held="2026-10-06T12:00:00Z waiting on the reader fp=1-2-3"
    roster_row_fixture status=identified name=w-c agent_id=ac plan="$plan" extended="2026-10-06T12:30:00Z more work"
    roster_row_fixture status=identified name=w-z agent_id=az plan="/elsewhere/wave-99-other.plan.md" amended="2026-10-06T13:00:00Z another run's"
  } >> "$p/.bionic/tmp/roster-fixture.state"
  # the plan: a second floor, a waive, a waive-row, and the prose and an old approve regression-2 line that count nothing
  h="$(bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1; proof_last "$2" floor' _ "$REPO_ROOT/payload/scripts/lib" "$plan")"
  expect_nonempty "HH-0a precondition: the fixture plan already holds one floor proof, whose head the second reuses" "$h"
  bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1
    plan="$2"; h="$3"
    proof_add_line "$plan" "$(proof_line regression "$h" 2026-10-06T13:00:00Z record/wave-01-fixture/floor-2.log)" > "$plan.pf" && mv "$plan.pf" "$plan"
    proof_add_line "$plan" "$(proof_waiver_line evidence "$h" "Chris Lehman" 2026-10-06T13:10:00Z "waive it")" > "$plan.pf" && mv "$plan.pf" "$plan"' \
    _ "$REPO_ROOT/payload/scripts/lib" "$plan" "$h"
  w="$(mktemp "$SANDBOX/hh-plan.XXXXXX")"
  awk '
    /^approved-by:/ { print; print "approved: regression-2 by Chris Lehman 2026-10-06T12:00:00Z \"yes\""; next }
    /^- Step 8:/ { print "- T1: landed by-hand (kind=hand) after waived: evidence; approved: regression-2 was discussed"
                   print; next }
    /^## Tasks/ { print "```"; print "proved: kind=regression head=0123456789abcdef at=2026-10-06T14:00:00Z evidence=x"
                  print "approved: regression-2 by Someone 2026-10-06T14:00:00Z \"quoted in a fence\""
                  print "waived: question=adversarial head=0123456789abcdef by Someone 2026-10-06T14:00:00Z \"fenced\""; print "\140\140\140"; print ""; print; next }
    /^  readback:/ && !wr { print; print "  waiver: Chris Lehman 2026-10-06 \"waive the row\" — fixture"
                            print "  waiver: someone said we might waive this later"; wr = 1; next }
    { print }' "$plan" > "$w" && mv "$w" "$plan"
}
PH="$(mk_fixture handholds)"; advance_to "$PH" 8
hh_plant "$PH"
HH_OUT="$(hh_report "$PH" --hand-holds)"
expect_eq "HH-1 landing-report --hand-holds prints the hand-holds line, every kind counted from its own line" "$HH_WANT" \
  "$(printf '%s\n' "$HH_OUT" | grep '^hand-holds: ')"
expect_eq "HH-1b …and a window opening before every line counts every kind from its own line" "$HH_ALL" \
  "$(hh_report "$PH" --hand-holds --since 2026-10-01T00:00:00Z | grep '^hand-holds: ')"
expect_eq "HH-2 …after the landings line, which is the one the default prints" "1/2" \
  "$(printf '%s\n' "$HH_OUT" | grep -c '^landings: ')/$(printf '%s\n' "$HH_OUT" | grep -n '^hand-holds: ' | cut -d: -f1)"
expect_eq "HH-3 the default landing-report prints no hand-holds line (its output stays what it was)" "0" \
  "$(hh_report "$PH" | grep -c '^hand-holds')"
# the same fixture with the verbs' lines removed and the prose kept: nothing is counted
PHP="$(mk_fixture handholds-prose)"; advance_to "$PHP" 8
mkdir -p "$PHP/.bionic/docs/record/wave-01-fixture"
printf 'note: T3 was landed by-hand (kind=hand); its run was stopped (ev=stop-run); the T2 decline was lifted (state=lift); amended= held= extended=\n' > "$PHP/.bionic/docs/record/wave-01-fixture/landing-proofs.log"
cp "$PHP/.bionic/docs/record/wave-01-fixture/landing-proofs.log" "$PHP/.bionic/docs/record/wave-01-fixture/fill-ledger.log"
awk '/^- Step 8:/ { print "- T1: landed by-hand (kind=hand) after waived: evidence; approved: regression-2 was discussed; a second floor"; print; next } { print }' \
  "$PHP/$PLAN_REL" > "$PHP/plan.b" && mv "$PHP/plan.b" "$PHP/$PLAN_REL"
HH_PROSE="$(hh_report "$PHP" --hand-holds)"
expect_eq "HH-4 a run whose only by-hand, stop-run, decline, lift, waiver and approval are prose counts zero in every kind" \
  "hand-holds: total=0 · by-hand=0 · stop-runs=0 · declines=0 · lifts=0 · amends=0 · holds=0 · extensions=0 · waivers=0 · status-writes=0 · second-regressions=0 · adoptions=0 · fixed=0" \
  "$(printf '%s\n' "$HH_PROSE" | grep '^hand-holds: ')"
# the card: check prints the line, run prints it after the wipe took the roster, the continuation carries it
run_close "$PH" check
expect_eq "HH-5 check prints the hand-holds line on the card" "$HH_WANT" "$(printf '%s\n' "$CO_OUT" | grep '^hand-holds: ')"
run_close "$PH" run
expect_eq "HH-6 run exits 0, prints the same line on the card, and the wipe took the roster it read" "0/$HH_WANT/0" \
  "$CO_RC/$(printf '%s\n' "$CO_OUT" | grep '^hand-holds: ')/$(tmp_entries "$PH")"
hh_section() { awk '/^## / { s = ($0 == "## Hand-holds"); next } s && NF && !/^```/ { print }' "$1"; }
expect_eq "HH-7b …and the section sits after ## Landings and before the Resume instruction" "yes" \
  "$(awk '/^## Landings$/ { a = NR } /^## Hand-holds$/ { b = NR } /^## Resume instruction/ { c = NR } END { print (a && b > a && c > b) ? "yes" : "no" }' "$PH/$CONT_REL")"
# wave-36 T11 (D8; REQ-2 AC-2.3): a stop-run is a verb act, counted under its own kind and never as by-hand. A run
# whose only escape hatch is one `ev=stop-run` (stop-run's own line) reads stop-runs=1 · by-hand=0 on close-out's card,
# through close-out.sh's existing landing-report call.
PHS="$(mk_fixture handholds-stoprun)"; advance_to "$PHS" 8
mkdir -p "$PHS/.bionic/docs/record/wave-01-fixture"
{
  printf 'line/v1|ev=ready|row=T1|name=w-T1|commit=%s|branch=wt/01-T1|tree=%s/.worktrees/01-T1|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T10:00:00Z\n' "$HH_C" "$PHS"
  printf 'line/v1|ev=published|row=T1|commit=%s|kind=queue|by=-|why=-|at=2026-10-06T10:30:00Z\n' "$HH_C"
  printf 'line/v1|ev=stop-run|request=2156|who=fixture:w-T1|kind=whole|key=tests/run.sh|by=fixture|why=parked behind a dead holder|at=2026-10-06T10:50:00Z\n'
} > "$PHS/.bionic/docs/record/wave-01-fixture/landing-proofs.log"
expect_eq "HH-13a precondition: the record holds one ev=stop-run line and one published line of kind queue" "1/1" \
  "$(/usr/bin/grep -c '^line/v1|ev=stop-run|' "$PHS/.bionic/docs/record/wave-01-fixture/landing-proofs.log" | tr -d ' ')/$(/usr/bin/grep -c '^line/v1|ev=published|.*|kind=queue|' "$PHS/.bionic/docs/record/wave-01-fixture/landing-proofs.log" | tr -d ' ')"
run_close "$PHS" check
expect_contains "HH-13 AC-2.3 one ev=stop-run reads stop-runs=1 · by-hand=0 on the card, counted in the total" \
  "hand-holds: total=1 · by-hand=0 · stop-runs=1 · declines=0 " "$(printf '%s\n' "$CO_OUT" | grep '^hand-holds: ')"
# T33 (D20, critic-adversarial #5; A-orch-32): an existing continuation.md is merged into, never overwritten. The
# hand-holds line goes under ## Hand-holds (the section appended after ## Deferrals when absent), a line already
# there is never written twice, and the person's own text is untouched. Run twice: the line is there once.
hh_count() { /usr/bin/grep -c '^hand-holds: ' "$1" | tr -d ' '; }
PHE="$(mk_fixture handholds-existing)"; advance_to "$PHE" 8; hh_plant "$PHE"
mkdir -p "$PHE/${CONT_REL%/*}"
printf '# continuation — hand written\n\nmy own note on the close\n\n## Deferrals\n\nnone, said the person\n\n## Resume instruction\n\nedited by a person\n' > "$PHE/$CONT_REL"
HHE_CK0="$(cksum < "$PHE/$CONT_REL")"
run_close "$PHE" check
expect_eq "HH-8a …and writes nothing" "$HHE_CK0" "$(cksum < "$PHE/$CONT_REL")"
run_close "$PHE" run
expect_eq "HH-9c …and the person's Resume instruction is still the last section" "## Resume instruction" \
  "$(/usr/bin/grep '^## ' "$PHE/$CONT_REL" | tail -n 1)"
expect_contains "HH-9d …and run says what it added" "added the ## Hand-holds section" "$CO_OUT"
# a second close-out over what the first left (planted in a fresh fixture: a closed plan refuses a second run)
PHE2="$(mk_fixture handholds-existing2)"; advance_to "$PHE2" 8; hh_plant "$PHE2"
mkdir -p "$PHE2/${CONT_REL%/*}"; cp "$PHE/$CONT_REL" "$PHE2/$CONT_REL"
HHE_CK1="$(cksum < "$PHE2/$CONT_REL")"
run_close "$PHE2" run
expect_absent "HH-10b …and the card reports no add" "added the ## Hand-holds" "$CO_OUT"
# the heading is there and the line is not: the line goes under it, after what the person wrote there
PHE3="$(mk_fixture handholds-existing3)"; advance_to "$PHE3" 8; hh_plant "$PHE3"
mkdir -p "$PHE3/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n## Hand-holds\n\nthe person counted two by hand\n\n## Resume instruction\n\nedited by a person\n' > "$PHE3/$CONT_REL"
run_close "$PHE3" run
expect_eq "HH-11a …and the Resume instruction after it is as it was" "## Resume instruction|edited by a person" \
  "$(awk '/^## Resume instruction$/ { s = 1 } s && NF' "$PHE3/$CONT_REL" | paste -sd'|' -)"
# the heading and the line are both there (as a person typed it, unfenced): nothing is added
PHE4="$(mk_fixture handholds-existing4)"; advance_to "$PHE4" 8; hh_plant "$PHE4"
mkdir -p "$PHE4/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n## Hand-holds\n\n%s\n\n## Governed by\n\ngoverned-by: installed 0.0.0, typed by a person\n\n## Resume instruction\n\nedited by a person\n' "$HH_WANT" > "$PHE4/$CONT_REL"
HHE_CK4="$(cksum < "$PHE4/$CONT_REL")"
run_close "$PHE4" run

# the mutation arms: a continuation template without the section, and a fold that counts a line it should not
HH_MUT="$(mktemp -d "${TMPDIR:-/tmp}/close-out-hh-mut.XXXXXX")"
mkdir -p "$HH_MUT/scripts"; ln -s "$REPO_ROOT/payload/scripts/lib" "$HH_MUT/scripts/lib"
ln -s "$REPO_ROOT/payload/scripts/card.sh" "$HH_MUT/scripts/card.sh"
sed 's/^\$(co_hand_holds_section)$//' "$SCRIPT" > "$HH_MUT/scripts/close-out.sh"
expect_eq "HH-mut0 the doctored copy differs from the script in exactly one line (the doctor took)" "1" \
  "$(diff "$SCRIPT" "$HH_MUT/scripts/close-out.sh" | /usr/bin/grep -c '^>')"
PHM="$(mk_fixture handholds-mut)"; advance_to "$PHM" 8; hh_plant "$PHM"
( cd "$PHM" && HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    BIONIC_GATE_DIR="$HH_GATE" bash "$HH_MUT/scripts/close-out.sh" "$PHM/$PLAN_REL" run ) > "$SANDBOX/hh-mut.out" 2>&1
HH_MRC=$?
rm -rf "$HH_MUT"


# ============================================================
section "§FLOOR-DECLARED (wave-28 T75; REQ-17 AC-17.1, D36): close-out proceeds on a declared floor's log"
# ============================================================
# A project with no tests/*.test.sh roster declares its floor (`floor: true`, a command that passes). The
# floor fact plant_facts wrote is taken out, and the real verbs write it again from the declared floor's own
# run: `regression-run` logs it, `proof-add regression` cites the log, `current 8` moves the plan on the facts, and
# `close-out.sh run` delivers. The fixture's working head holds no tests/ directory (mk_fixture's shape).
PFL="$(mk_fixture floor-declared)"
FL_SID="closeout-floor-1"
sed '/^proved: kind=regression /d' "$PFL/$PLAN_REL" > "$PFL/$PLAN_REL.n" && mv "$PFL/$PLAN_REL.n" "$PFL/$PLAN_REL"
printf 'regression-command: true\n' >> "$PFL/.bionic/config.yaml"
( in_fixture "$PFL" || exit 1; . "$REPO_ROOT/tests/lib/bound-marker.sh"; bound_marker "$PFL" "$FL_SID" "$PFL/$PLAN_REL" )
fl_poke() {  # <verb> [<arg>...] -> FL_RC, FL_OUT: the real poker verb, in the fixture, as this session
  ( in_fixture "$PFL" || exit 9
    HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
      CLAUDE_CODE_SESSION_ID="$FL_SID" bash "$BIONIC_HOOKS_DIR/session-poker.sh" "$@" ) > "$SANDBOX/fl-poker" 2>&1
  FL_RC=$?; FL_OUT="$(cat "$SANDBOX/fl-poker")"
}
FL_H="$(fixture_git "$PFL" rev-parse wave/01-fixture)"
fl_poke regression-run
expect_eq "FL1 regression-run runs the declared floor at the working head (exit 0), its log opening head= dirty=0 and closing rc=0 (wave-36 T35)" \
  "0|head=$FL_H dirty=0|rc=0" \
  "$FL_RC|$(head -n 1 "$PFL/.bionic/docs/record/wave-01-fixture/regression-run-$FL_H.log" 2>/dev/null)|$(tail -n 1 "$PFL/.bionic/docs/record/wave-01-fixture/regression-run-$FL_H.log" 2>/dev/null)"
# THE FLOOR FACT FROM THAT LOG, BY THE PRODUCT'S JUDGE AND WRITER (as plant_facts writes its lines): the judge
# with the plan and the project root, as proof-add calls it, attests the declared log by the run line regression-run
# wrote beside it (wave-37 T4; D7), and proof_add_line places the line.
# proof-add itself is not driven here: its dry commit runs the real gate at current: 4, which this fixture's
# Step-7 plan (no Step 0-6 lines) does not meet for any floor; session-poker §FLOOR-DECLARED drives the verb.
FL_AT="$(bash -c '. "$1/roots.sh" && . "$1/proof.sh" || exit 9
  h="$(proof_attested regression "$2/record/wave-01-fixture/regression-run-$3.log" "$4" "$6" "" "$5")" || { printf "%s" "$h"; exit 1; }
  proof_add_line "$6" "$(proof_line regression "$h" 2026-10-04T13:00:00Z "record/wave-01-fixture/regression-run-$3.log")" > "$6.pf" && mv "$6.pf" "$6" && printf "%s" "$h"' \
  _ "$REPO_ROOT/payload/scripts/lib" "$PFL/.bionic/docs" "$FL_H" "$PFL-wave" "$PFL" "$PFL/$PLAN_REL" 2>&1)"
fl_poke current 8
expect_eq "FL3 current 8 is admitted on the facts (exit 0)" "0|8" "$FL_RC|$(sed -n 's/^current: //p' "$PFL/$PLAN_REL")"
run_close "$PFL" run
expect_eq "FL4 AC-17.1 close-out.sh run delivers on a declared floor's proof (rc 0), the plan closed" "0|1" \
  "$CO_RC|$(run_open_rc "$PFL/$PLAN_REL")"

# A PROJECT WITH NO tests/*.test.sh AND NO floor: CLOSES ITS RUN ON ITS OWN RUNNER'S LOG (wave-36 T35; REQ-7 AC-7.10; D13).
# The floor is a fact: the log the project's own runner left, opening head=<the working head> dirty=0 and ending rc=0,
# is the evidence as it stands, with no config key and no regression-run. The judge and writer are driven as FL2 drives them.
PFN="$(mk_fixture floor-any)"
FN_SID="closeout-floor-2"
sed '/^proved: kind=regression /d' "$PFN/$PLAN_REL" > "$PFN/$PLAN_REL.n" && mv "$PFN/$PLAN_REL.n" "$PFN/$PLAN_REL"
( in_fixture "$PFN" || exit 1; . "$REPO_ROOT/tests/lib/bound-marker.sh"; bound_marker "$PFN" "$FN_SID" "$PFN/$PLAN_REL" )
FN_H="$(fixture_git "$PFN" rev-parse wave/01-fixture)"
mkdir -p "$PFN/.bionic/docs/record/wave-01-fixture"
# THE RUN IS RECORDED (wave-37 T4; D7, ADR-057): the log and its run line, as tests/lib/regression-fixture.sh writes them.
printf '$ pnpm ci:local\n412 passed\n' | regression_fixture "$PFN/$PLAN_REL" "$PFN/.bionic/docs/record/wave-01-fixture/ci.log" "$FN_H" 0 0
FN_AT="$(bash -c '. "$1/roots.sh" && . "$1/proof.sh" || exit 9
  h="$(proof_attested regression "$2/record/wave-01-fixture/ci.log" "$3" "$5" "" "$4")" || { printf "%s" "$h"; exit 1; }
  proof_add_line "$5" "$(proof_line regression "$h" 2026-10-04T13:00:00Z "record/wave-01-fixture/ci.log")" > "$5.pf" && mv "$5.pf" "$5" && printf "%s" "$h"' \
  _ "$REPO_ROOT/payload/scripts/lib" "$PFN/.bionic/docs" "$PFN-wave" "$PFN" "$PFN/$PLAN_REL" 2>&1)"
FN_RC="$( ( in_fixture "$PFN" || exit 9
  HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    CLAUDE_CODE_SESSION_ID="$FN_SID" bash "$BIONIC_HOOKS_DIR/session-poker.sh" current 8 ) > "$SANDBOX/fn-poker" 2>&1; echo $?)"
expect_eq "FL7 AC-7.10 current 8 is admitted on that floor (exit 0)" "0|8" "$FN_RC|$(sed -n 's/^current: //p' "$PFN/$PLAN_REL")"
run_close "$PFN" run
expect_eq "FL8 AC-7.10 close-out.sh run delivers on the project's own runner's log (rc 0), the plan closed" "0|1" \
  "$CO_RC|$(run_open_rc "$PFN/$PLAN_REL")"

section "DEBT-CARD — wave-30 T22 (AC-11.4, AC-11.2; D2, P2): the release card says the run's touches and burns; the continuation carries each unburned item"
# ============================================================
# The run's ledger is `record/<run>/debt.md` (lib/proof.sh `proof_debt_ledger_path`). close-out prints
# `debt: touched <N> · burned <M>`: N the touches summed over every item, M the items burned, never the
# ledger's length. The continuation's ## Deferrals carries one line per unburned item, after the
# deferred: lines, in the form
#
#   debt: <concept> <kind> "<sites>" touches=<N> raised-by=<record> from=<wave name>
#
# fails-when: the card omits the line or prints a count of items; the continuation omits an unburned item.
# FIXTURE FIDELITY: the ledger is planted in the line shape `session-poker.sh debt` writes (session-poker-4
# §DEBT-LEDGER pins the shape against the verb).
# debt_plant: hoisted to tests/close-out.prelude.sh (a later part reads it)
PDB="$(mk_fixture debtcard1)"; advance_to "$PDB" 8
debt_plant "$PDB"
run_close "$PDB" check
expect_eq "DEBT-CARD-1 check exits 0 over a run that keeps a debt ledger" "0" "$CO_RC"
expect_eq "DEBT-CARD-2 …and its card prints the run's touches and burns: 4+1+0 touched, one burned" \
  "debt: touched 5 · burned 1" "$(printf '%s\n' "$CO_OUT" | /usr/bin/grep '^debt: ')"
run_close "$PDB" run
expect_eq "DEBT-CARD-3 run exits 0" "0" "$CO_RC"
expect_eq "DEBT-CARD-4 …and prints the same line once (AC-11.4), not the ledger's three items" \
  "debt: touched 5 · burned 1" "$(printf '%s\n' "$CO_OUT" | /usr/bin/grep '^debt: ')"
expect_nonempty "DEBT-CARD-5 precondition: the extractor finds lines under ## Deferrals" "$(carry_section "$PDB/$CONT_REL")"
expect_eq "DEBT-CARD-6 the continuation carries each unburned item, in ledger order, and not the burned one (AC-11.2)" \
"debt: tree_count duplicate \"lib/a.sh:1, lib/b.sh:2\" touches=4 raised-by=record/wave-01-fixture/critic-structure.md from=$CARRY_W
debt: pair_x unpinned-pair \"lib/d.sh:9\" touches=0 raised-by=record/wave-01-fixture/critic-adversarial.md from=$CARRY_W" \
  "$(carry_section "$PDB/$CONT_REL" | /usr/bin/grep '^debt: ')"
expect_absent "DEBT-CARD-7 …the burned item is not carried" "log_shim" "$(carry_section "$PDB/$CONT_REL")"

# no ledger: the card still says it, at zero (the line is never omitted)
PDN="$(mk_fixture debtcard2)"; advance_to "$PDN" 8
run_close "$PDN" run
expect_eq "DEBT-CARD-8 a run with no ledger exits 0 and its card prints touched 0 · burned 0" \
  "0|debt: touched 0 · burned 0" "$CO_RC|$(printf '%s\n' "$CO_OUT" | /usr/bin/grep '^debt: ')"
expect_nonempty "DEBT-CARD-9 precondition: its continuation has a Deferrals heading to read" "$(/usr/bin/grep '^## Deferrals$' "$PDN/$CONT_REL")"
expect_absent "DEBT-CARD-9b …and carries no debt line" "debt: " "$(carry_section "$PDN/$CONT_REL")"

# an existing continuation with the heading: an unburned item not under it yet is merged in, each once
PDE="$(mk_fixture debtcard3)"; advance_to "$PDE" 8
debt_plant "$PDE"
mkdir -p "$PDE/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\nnone, said the person\n' > "$PDE/$CONT_REL"
run_close "$PDE" run
expect_eq "DEBT-CARD-10 run over a written continuation exits 0" "0" "$CO_RC"

# ============================================================
section "DEBT-RECARRY — wave-30 T23 (A-orch-44; AC-11.2): an inherited debt line the run's ledger does not hold is carried again"
# ============================================================
# A continuation's `debt:` lines reach the next run's ledger only through `debt adopt` (wave-30 T32), and
# `card.sh inherited` withholds them so an adopted item is not written twice (A-T32.2). So an item nobody
# adopted was dropped at the next close-out. Now close-out carries each inherited debt line as written,
# its from= kept, unless the run's ledger holds its concept and kind: then the ledger's own line carries
# it (unburned) or nothing does (burned). fails-when: an unadopted item is dropped, or an adopted one is
# carried twice. FIXTURE FIDELITY: the predecessor's lines are in close-out's own carry shape (the printf
# docs-pins W30-L4b holds), and the ledger is debt_plant's, the shape `session-poker.sh debt` writes.
RC_FROM="from=$CARRY_PREV"
RC_HELD="debt: tree_count duplicate \"lib/a.sh:1, lib/b.sh:2\" touches=2 raised-by=record/$CARRY_PREV/critic-structure.md $RC_FROM"
RC_PAID="debt: log_shim one-case-abstraction \"lib/c.sh:3\" touches=1 raised-by=record/$CARRY_PREV/critic-structure.md $RC_FROM"
RC_LOOSE="debt: orphan_x duplicate \"lib/z.sh:7\" touches=3 raised-by=record/$CARRY_PREV/critic-structure.md $RC_FROM"
PRC="$(mk_fixture debtrecarry1)"; advance_to "$PRC" 8
debt_plant "$PRC"
mkdir -p "$PRC/.bionic/docs/record/$CARRY_PREV"
printf '%s\n' "# continuation — $CARRY_PREV" "" "## Deferrals" "" "$RC_HELD" "$RC_PAID" "$RC_LOOSE" \
  "" "## Resume instruction" "" "nothing" > "$PRC/.bionic/docs/record/$CARRY_PREV/continuation.md"
expect_eq "DEBT-RECARRY-0 precondition: card.sh inherited-debt reads the predecessor's three debt lines, as written" \
"$RC_HELD
$RC_PAID
$RC_LOOSE" "$(bash "$REPO_ROOT/payload/scripts/card.sh" inherited-debt "$PRC/.bionic/docs/plans/epic-fx/wave-01-fixture.requirements.md" 2>/dev/null)"
run_close "$PRC" run
expect_eq "DEBT-RECARRY-1 run exits 0 over a run that inherited three debt lines and keeps a ledger" "0" "$CO_RC"
expect_eq "DEBT-RECARRY-2 the ledger's unburned items, then the inherited line no ledger holds, as written with its from=" \
"debt: tree_count duplicate \"lib/a.sh:1, lib/b.sh:2\" touches=4 raised-by=record/wave-01-fixture/critic-structure.md from=$CARRY_W
debt: pair_x unpinned-pair \"lib/d.sh:9\" touches=0 raised-by=record/wave-01-fixture/critic-adversarial.md from=$CARRY_W
$RC_LOOSE" "$(carry_section "$PRC/$CONT_REL" | /usr/bin/grep '^debt: ')"
expect_absent "DEBT-RECARRY-3 …the inherited line whose concept and kind the ledger holds is not carried twice" \
  "touches=2 raised-by=record/$CARRY_PREV/critic-structure.md" "$(carry_section "$PRC/$CONT_REL")"
expect_absent "DEBT-RECARRY-4 …nor the one the ledger burned" "log_shim" "$(carry_section "$PRC/$CONT_REL")"
# THE RECORD TEMPLATE SAYS REGRESSION (wave-30 T23; AC-4.7, D10): the continuation close-out writes asks the
# orchestrator for the regression's result, in the word the doctrine uses.
# WAVE-33 T8 (D8): the result is no longer asked for, it is written, from the floor's proof line, in the same word.
expect_absent "REG-1b …and never calls it the floor's result" "floor result" "$(cat "$PRC/$CONT_REL" 2>/dev/null)"
# no ledger at all: every inherited debt line is carried, in its order
PRN="$(mk_fixture debtrecarry2)"; advance_to "$PRN" 8
mkdir -p "$PRN/.bionic/docs/record/$CARRY_PREV"
printf '%s\n' "# continuation — $CARRY_PREV" "" "## Deferrals" "" "$RC_HELD" "$RC_LOOSE" \
  "" "## Resume instruction" "" "nothing" > "$PRN/.bionic/docs/record/$CARRY_PREV/continuation.md"
run_close "$PRN" run
expect_eq "DEBT-RECARRY-5 a run with no ledger exits 0 and carries both inherited debt lines, as written" \
  "0|$RC_HELD
$RC_LOOSE" "$CO_RC|$(carry_section "$PRN/$CONT_REL" | /usr/bin/grep '^debt: ')"

# ============================================================
section "DEBT-LINES — wave-36 T13 (D13; REQ-7 AC-7.8; A-orch-1): close-out carries only debt lines that parse, refusing a debt.md line that does not, naming it"
# ============================================================
# The one debt-line grammar is lib/debt.sh `debt_line_ok`, read by `debt add`, by close-out's `co_debts`
# and by card.sh's inherited reader. A debt.md item whose carried line would not parse (A-orch-1: a
# `raised-by` cell holding a space, `assumptions.md A-orch-46`) refuses `run` before its first act and is
# named; `check` says it would refuse. Corrected, the line is carried, and the next run's `card.sh step1`
# over the continuation renders it instead of refusing. fails-when: the continuation carries the
# unparseable line, or the next run's Step-1 card is refused on it.
# FIXTURE FIDELITY: the ledger is debt_plant's, in the shape `session-poker.sh debt` writes, with one
# item's source cell written by hand as wave-35's two hole lines were.
DL_BAD='hole_x | hole | lib/e.sh:5 | raised-by record/wave-01-fixture/assumptions.md A-orch-46 | touches 0 | —'
DL_GOOD='hole_x | hole | lib/e.sh:5 | raised-by record/wave-01-fixture/assumptions.md#A-orch-46 | touches 0 | —'
PDL="$(mk_fixture debtlines1)"; advance_to "$PDL" 8
debt_plant "$PDL"
DL_LED="$PDL/.bionic/docs/record/wave-01-fixture/debt.md"
printf '%s\n' "$DL_BAD" >> "$DL_LED"
run_close "$PDL" check
expect_eq "DEBT-LINES-1 check exits 0 over a ledger with an unparseable line" "0" "$CO_RC"
cp "$PDL/$PLAN_REL" "$SANDBOX/dl-plan-before"
run_close "$PDL" run
expect_eq "DEBT-LINES-2 AC-7.8 run refuses a debt.md line with a space in its source cell (exit 2)" "2" "$CO_RC"
expect_false "DEBT-LINES-2c …and no continuation was written" test -e "$PDL/$CONT_REL"
expect_true "DEBT-LINES-2d …the plan byte-identical, nothing done" cmp -s "$SANDBOX/dl-plan-before" "$PDL/$PLAN_REL"
awk -v bad="$DL_BAD" -v good="$DL_GOOD" '$0 == bad { $0 = good } { print }' "$DL_LED" > "$DL_LED.new" && mv "$DL_LED.new" "$DL_LED"
run_close "$PDL" run
expect_eq "DEBT-LINES-3b the corrected ledger closes (exit 0)" "0" "$CO_RC"
DL_CARRY="debt: hole_x hole \"lib/e.sh:5\" touches=0 raised-by=record/wave-01-fixture/assumptions.md#A-orch-46 from=$CARRY_W"
expect_eq "DEBT-LINES-3c …and the continuation carries the unburned items, the corrected one last" \
"debt: tree_count duplicate \"lib/a.sh:1, lib/b.sh:2\" touches=4 raised-by=record/wave-01-fixture/critic-structure.md from=$CARRY_W
debt: pair_x unpinned-pair \"lib/d.sh:9\" touches=0 raised-by=record/wave-01-fixture/critic-adversarial.md from=$CARRY_W
$DL_CARRY" "$(carry_section "$PDL/$CONT_REL" | /usr/bin/grep '^debt: ')"
# The next run's Step 1: its requirements beside this run's, the continuation the newest other one.
DL_REQ="$PDL/.bionic/docs/specs/epic-fx/wave-02-next.requirements.md"; mkdir -p "${DL_REQ%/*}"
printf '%s\n' '---' 'sdlc-step: 1' 'working-branch: wave/02-next' 'integration-branch: main' 'base-sha: abc1234' '---' '' \
  '# next wave · requirements' '' '## Goal' '' 'Read the debt the predecessor carried.' '' \
  '## Not Doing' '' '- Nothing excluded.' '' '## Requirements and acceptance criteria' '' \
  '### REQ-1 — the one requirement' '' 'The next run reads the debt its predecessor carried.' '' \
  'provenance: user 2026-10-13 "carry it"' \
  '- AC-1.1 the criterion. Fails when: it does not hold.' > "$DL_REQ"
DL_CARD="$(bash "$REPO_ROOT/payload/scripts/card.sh" step1 "$DL_REQ" 2>"$SANDBOX/dl-card.err" 0<&-)"; DL_CRC=$?
expect_eq "DEBT-LINES-4 AC-7.8 the next run's card.sh step1 over the continuation renders (exit 0, nothing refused)" "0|" \
  "$DL_CRC|$(cat "$SANDBOX/dl-card.err")"
# ONE LINE OF COUNTS (wave-38 T17; D5, AC-10.1): the card counts the continuation's deferred and debt lines and
# prints none of them; DEBT-LINES-4's exit 0 is the proof the corrected line parses.
DL_N="$(carry_section "$PDL/$CONT_REL" | /usr/bin/grep -c -e '^deferred: ' -e '^debt: ' | tr -d ' ')"
expect_absent "DEBT-LINES-4c …printing none of them, the corrected debt line included" "hole_x hole" "$DL_CARD"

# ============================================================
section "RUNS — wave-30 T12 (REQ-4 AC-4.6, D7d; D6): the card prints regression-runs, and the Step-8 sweep stops every orphan run"
# ============================================================
#
# THE COUNT IS READ BEFORE THE WIPE TAKES THE ROSTERS: `regression-runs: <n>` is session-poker's
# `regression-runs`, the full-runner runs the rosters record as ended. THE SWEEP: a detached run
# (booked.sh --detach) whose pid is alive and that wrote no end, left by a closing run, is an orphan;
# `run` stops it through `session-poker.sh stop-run` and names it with its last progress line, then
# the wipe takes its files; `check` names it and sends nothing. FIXTURE FIDELITY: the roster row is a
# run record in the shim's shape; the orphan is a stand-in shim (a loop that dies on TERM, under the
# real perl setsid, its pid file and progress line beside its log), because a closing run's orphan is
# a process nobody is waiting on and the sweep reads nothing else of it.
PR="$(mk_fixture pruns)"; advance_to "$PR" 8
PR_RUNS="$PR/.bionic/tmp/runs"; mkdir -p "$PR_RUNS" "$SANDBOX/fake-shim"
roster_row_fixture status=identified session=fixture name=w-reg agent_id=areg \
  "run_log=$PR_RUNS/w-reg-run.sh.log" run_cmd=tests/run.sh run_rc=0 >> "$PR/.bionic/tmp/roster-fixture.state"
printf '#!/bin/bash\nwhile :; do sleep 0.2; done\n' > "$SANDBOX/fake-shim/booked.sh"
PR_LOG="$PR_RUNS/w-orph-o.test.sh.log"; : > "$PR_LOG"
printf '2026-10-08T00:00:02Z\to.test.sh\t§sec-orph\n' > "$PR_LOG.progress.tsv"
perl -MPOSIX -e 'my $l = shift; my $p = fork; exit 0 if $p; POSIX::setsid(); open(my $f, ">", "$l.pid"); print $f "$$\n"; close $f; open(STDIN, "<", "/dev/null"); open(STDOUT, ">>", $l); open(STDERR, ">&", \*STDOUT); exec @ARGV' \
  "$PR_LOG" bash "$SANDBOX/fake-shim/booked.sh" --run-log "$PR_LOG"
i=0; while [ ! -s "$PR_LOG.pid" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
PR_PID="$(cat "$PR_LOG.pid" 2>/dev/null)"
TS_LIVE_PIDS="$TS_LIVE_PIDS ${PR_PID:-}"
expect_true "RUNS.0 precondition: the orphan's shim is alive" kill -0 "${PR_PID:-0}"

run_close "$PR" check
expect_eq "RUNS.1 AC-4.6 check prints the release card's count of full runs, from the run records" "yes" \
  "$(contains "$CO_OUT" "regression-runs: 1")"
expect_eq "RUNS.2b …ending in the run's last progress line" "yes" \
  "$(contains "$(printf '%s\n' "$CO_OUT" | grep '^orphan: ')" "; last progress: 2026-10-08T00:00:02Z o.test.sh §sec-orph")"
expect_true "RUNS.3 …and sends nothing: the orphan is still alive" kill -0 "${PR_PID:-0}"

run_close "$PR" run
expect_eq "RUNS.4 run exits 0" "0" "$CO_RC"
expect_eq "RUNS.5 AC-4.6 run prints the count on the card too" "yes" "$(contains "$CO_OUT" "regression-runs: 1")"
expect_false "RUNS.7 …and the orphan's process is gone" kill -0 "${PR_PID:-0}"
expect_eq "RUNS.8 …and the wipe took its files with the rest of .bionic/tmp" "0" "$(tmp_entries "$PR")"
expect_eq "RUNS.9 one orphan, one line" "1" "$(printf '%s\n' "$CO_OUT" | grep -c '^orphan: ')"

# ============================================================
section "INSERT — wave-33 T8 (REQ-4 AC-4.2, D8): close-out writes the Step-8 line it checks for"
# ============================================================
#
# `run` at `current: 8` with the facts held used to refuse when the plan carried no `- Step 8:` line:
# the writer replaced a line it never inserted, then read back for the line it had not written. Wave-32's
# own close met it. The fixture is the plan the tools leave: `advance_to 8` then the Step-8 line removed.
#
# step_order <plan> -> the step numbers of the `- Step N:` lines of ## SDLC State, in order, space-joined.
step_order() {
  awk '
    /^## / { insdlc = ($0 ~ /^## SDLC State/) }
    insdlc && match($0, /^[[:space:]]*-?[[:space:]]*Step[[:space:]]+[0-9]+[[:space:]]*:/) {
      s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); printf "%s%s", (n++ ? " " : ""), s }
    END { print "" }' "$1"
}
# drop_step_line <project> <N> -> the plan without its `- Step N:` line (continuation lines stay).
drop_step_line() {
  /usr/bin/grep -v "^- Step $2:" "$1/$PLAN_REL" > "$1/plan.tmp" && mv "$1/plan.tmp" "$1/$PLAN_REL"
}
# block_lines <plan> <N> -> how many indented continuation lines follow the `- Step N:` line.
block_lines() {
  awk -v n="$2" '
    $0 ~ "^- Step " n ":" { f = 1; next }
    /^- Step / || /^[^ \t-]/ || /^$/ { f = 0 }
    f && /^  / { c++ }
    END { print c + 0 }' "$1"
}

IA="$(mk_fixture insert-a)"; advance_to "$IA" 8; drop_step_line "$IA" 8
expect_eq "INSERT.0 precondition: the plan reads current: 8, carries a Step-7 line, no Step-8 line and no Step-9 line" "8/7" \
  "$(sed -n 's/^current: //p' "$IA/$PLAN_REL")/$(step_order "$IA/$PLAN_REL")"
IA_SHA="$(sha_of "$IA/$PLAN_REL")"
run_close "$IA" check
expect_eq "INSERT.2 …and check changed not one byte" "$IA_SHA" "$(sha_of "$IA/$PLAN_REL")"
run_close "$IA" run
expect_eq "INSERT.3 AC-4.2 run succeeds on a plan with no Step-8 line (rc 0)" "0" "$CO_RC"
expect_eq "INSERT.4 …the Step-8 line is there, closed, once" "1/yes" \
  "$(step_lines "$IA/$PLAN_REL" 8)/$(grep -qE '^- Step 8: CLOSED [0-9]{4}-' "$IA/$PLAN_REL" && echo yes || echo no)"
expect_eq "INSERT.5 …between the Step-7 line and the Step-9 line, in step order" "7 8 9" "$(step_order "$IA/$PLAN_REL")"
expect_eq "INSERT.7 …the gate dry-run attested it, and the plan reads closed" "yes/1" \
  "$(contains "$CO_OUT" "gate: ok")/$(run_open_rc "$IA/$PLAN_REL")"
expect_eq "INSERT.8 …and the real bash-walls.sh allows the close-out commit" "0" "$(gate_rc "$IA")"

# THE INSERT SITS AFTER THE STEP-7 BLOCK, NOT BETWEEN ITS LINES: a Step-7 line with continuation lines keeps them.
IB="$(mk_fixture insert-b)"; advance_to "$IB" 8; drop_step_line "$IB" 8
awk '{ print } /^- Step 7:/ { print "  adr: none owed"; print "  documented: the fixture has nothing to document" }' "$IB/$PLAN_REL" > "$IB/plan.tmp" && mv "$IB/plan.tmp" "$IB/$PLAN_REL"
expect_eq "INSERT.9 precondition: Step 7 carries two continuation lines" "2" "$(block_lines "$IB/$PLAN_REL" 7)"
run_close "$IB" run
expect_eq "INSERT.10 a plan whose Step-7 block has continuation lines closes (rc 0)" "0" "$CO_RC"
expect_eq "INSERT.11 …the Step-7 block is intact and the Step-8 line follows its last continuation line" "7 8 9/2/yes" \
  "$(step_order "$IB/$PLAN_REL")/$(block_lines "$IB/$PLAN_REL" 7)/$(awk '/^  documented: /{d=NR} /^- Step 8: CLOSED /{s=NR} END{print (d && s == d + 1) ? "yes" : "no"}' "$IB/$PLAN_REL")"

# A PLAN WITH NO STEP LINE AT ALL gets the block at the end of ## SDLC State.
IC="$(mk_fixture insert-c)"; advance_to "$IC" 8; drop_step_line "$IC" 8; drop_step_line "$IC" 7
expect_eq "INSERT.12 precondition: the plan carries no step line" "" "$(step_order "$IC/$PLAN_REL")"
run_close "$IC" run
expect_eq "INSERT.13 a plan with no step line closes too (rc 0), with Step 8 then Step 9" "0/8 9" "$CO_RC/$(step_order "$IC/$PLAN_REL")"

# A REFUSED RUN WRITES NO STEP-8 LINE: the insert is phase 8's, behind the pre-flight (paired with INSERT.3).
ID="$(mk_fixture insert-d)"; advance_to "$ID" 8; drop_step_line "$ID" 8
rm -f "$ID/.bionic/docs/record/generic-evidence.md"
ID_STATE="$(presence_state "$ID")/$(sha_of "$ID/$PLAN_REL")"
run_close "$ID" run
expect_eq "INSERT.14 a run the gate would refuse still refuses (rc 2) and writes no Step-8 line: plan, branch and tmp untouched" "2/$ID_STATE" \
  "$CO_RC/$(presence_state "$ID")/$(sha_of "$ID/$PLAN_REL")"

# THE WALK POINTER, WHERE THE GATE READS IT. The matrix head carries `walk-artifact:` (what matrix-render stubs and
# the walk fills); the walk gate reads the Step-5 block (walls.sh step5_evidence_block). Close-out copies a real
# pointer across when the Step-5 block lacks it, and invents none.
mk_walked() {  # <name> <matrix-head-value|-> -> a fixture at Step 8 that owes a walk
  local p
  p="$(mk_fixture "$1")"; advance_to "$p" 8
  sed 's/^walk: exempt/walk: required/' "$p/$PLAN_REL" > "$p/plan.tmp" && mv "$p/plan.tmp" "$p/$PLAN_REL"
  WA="$2" awk '{ print }
       /^- Step 7:/ { print "- Step 5: verify: the walk was driven" }
       /^stack-health:/ && ENVIRON["WA"] != "-" { print "walk-artifact: " ENVIRON["WA"] }' "$p/$PLAN_REL" > "$p/plan.tmp" && mv "$p/plan.tmp" "$p/$PLAN_REL"
  printf 'Drove the fixture: it started, answered, and stopped.\n' > "$p/.bionic/docs/record/wave-01-fixture/walk.md"
  printf '%s\n' "$p"
}
step5_has_pointer() {  # <plan> -> yes|no: the Step-5 block (line + continuation) carries a walk-artifact: key
  awk '/^- Step 5:/ { f = 1; next } /^- Step / || /^[^ \t-]/ { f = 0 } f && /walk-artifact:/ { c++ } END { print (c ? "yes" : "no") }' "$1"
}
IW="$(mk_walked insert-w "record/wave-01-fixture/walk.md")"
expect_eq "INSERT.15 precondition: the plan owes a walk, the matrix head names it, and the Step-5 block does not" "yes/no" \
  "$(/usr/bin/grep -q '^walk: required' "$IW/$PLAN_REL" && /usr/bin/grep -q '^walk-artifact: record/wave-01-fixture/walk.md' "$IW/$PLAN_REL" && echo yes || echo no)/$(step5_has_pointer "$IW/$PLAN_REL")"
run_close "$IW" run
expect_eq "INSERT.16 AC-4.2 run succeeds, the walk gate reading the pointer close-out wrote into the Step-5 block (rc 0)" "0/yes" \
  "$CO_RC/$(step5_has_pointer "$IW/$PLAN_REL")"
expect_eq "INSERT.17 …as a continuation line of Step 5, naming the same file" "yes" \
  "$(awk '/^- Step 5:/{f=1; next} /^- Step /{f=0} f && /^  walk-artifact: record\/wave-01-fixture\/walk.md$/{c++} END{print (c==1) ? "yes" : "no"}' "$IW/$PLAN_REL")"

IX="$(mk_walked insert-x "-")"
IX_SHA="$(sha_of "$IX/$PLAN_REL")"
run_close "$IX" run
expect_eq "INSERT.18 with no pointer anywhere close-out invents none: the gate's own refusal stands (rc 2), the plan untouched" "2/no/$IX_SHA/yes" \
  "$CO_RC/$(step5_has_pointer "$IX/$PLAN_REL")/$(sha_of "$IX/$PLAN_REL")/$(contains "$CO_OUT" "walk-artifact")"
IY="$(mk_walked insert-y "pending")"
run_close "$IY" run
expect_eq "INSERT.19 …and the matrix head's own stub (pending) is no pointer: refused, nothing written" "2/no" "$CO_RC/$(step5_has_pointer "$IY/$PLAN_REL")"

# ============================================================
section "FILL — wave-33 T8 (REQ-3 AC-3.3, D8): the epic row and the continuation are written whole"
# ============================================================
#
# The epic row's ADR cell was `<fill: ADRs>` when no source named one, and wave-30's still reads so; the
# continuation carried fourteen marks the orchestrator completed by hand (A-orch-50). Close-out now writes every
# field it can derive, refuses the row when the plan says nothing about its ADRs, and leaves a mark only where
# a person must decide, naming each in its output.
fill_marks() { /usr/bin/grep -o '<fill: [^>]*>' "$1" 2>/dev/null; }
OWED_MARKS='<fill: the first decision, or "none">
<fill: what was ruled at this close, or "none">
<fill: version>
<fill: ideas path>
<fill: carry-overs from this wave>'

FA="$(mk_fixture fill-a)"; advance_to "$FA" 8
FA_HEAD="$(fixture_git "$FA" rev-parse wave/01-fixture)"
FA_MAIN="$(fixture_git "$FA" rev-parse --short main)"
run_close "$FA" run
FA_ROW="$(table_rows "$FA/$EPIC_REL" shipped | /usr/bin/grep -E '^\|[[:space:]]*01[[:space:]]*\|')"
FA_CONT="$(cat "$FA/$CONT_REL" 2>/dev/null)"
expect_eq "FILL.2 AC-3.3 the epic row carries no <fill:, and holds the merge commit it names" "no/yes" \
  "$(contains "$FA_ROW" "<fill:")/$(contains "$FA_ROW" "main @ $FA_MAIN")"
expect_eq "FILL.3 …and an ADR cell that says so when the plan says none (adrs: none)" "—" "$(adr_cell "$FA")"
expect_contains "FILL.4 the continuation states the task count from the plan (the two build rows)" "2 tasks, every one RED→GREEN" "$FA_CONT"
expect_contains "FILL.7 …and the commit it closed at, written whole" "main at $FA_MAIN." "$FA_CONT"
expect_absent "FILL.8 no Patrol sentence when no job is known (this session has no transcript) and no mark for it" "Patrol" "$FA_CONT"
OWED_NAMES='the first decision, or "none"; what was ruled at this close, or "none"; version; ideas path; carry-overs from this wave'

# THE ROW IS REFUSED, NOT MARKED, when the plan says nothing about its ADRs.
FB="$(mk_fixture fill-b)"; advance_to "$FB" 8
/usr/bin/grep -v '^adrs:' "$FB/$PLAN_REL" > "$FB/plan.tmp" && mv "$FB/plan.tmp" "$FB/$PLAN_REL"
FB_STATE="$(presence_state "$FB")/$(sha_of "$FB/$PLAN_REL")/$(sha_of "$FB/$EPIC_REL")"
run_close "$FB" check
expect_eq "FILL.12 check says the close would refuse, naming the missing field and the line to write" "yes/yes" \
  "$(contains "$CO_OUT" "presence: WOULD REFUSE")/$(contains "$CO_OUT" "adrs: none")"
run_close "$FB" run
expect_eq "FILL.13 run refuses (rc 2) naming the field, before any act" "2/yes/no" "$CO_RC/$(contains "$CO_OUT" "adrs:")/$(contains "$CO_OUT" "worktree-removed:")"
expect_eq "FILL.14 …branch, tmp, continuation, plan and epic plan untouched" "$FB_STATE" \
  "$(presence_state "$FB")/$(sha_of "$FB/$PLAN_REL")/$(sha_of "$FB/$EPIC_REL")"
# …AND A PLAN THAT SAYS WHICH ADRS (paired with FILL.12–14: the same fixture with the line written closes).
set_plan_keys "$FB" "-" "adrs: adrs/epic-fx/adr-052-the-workhorse.md"
run_close "$FB" run
expect_eq "FILL.15 the same plan with an adrs: line closes (rc 0) and the cell and the continuation name the ADR" "0/052/yes" \
  "$CO_RC/$(adr_cell "$FB")/$(contains "$(cat "$FB/$CONT_REL")" "ADRs: 052.")"

# THE PATROL JOB, from this session's transcript, when it is known: the id the platform minted, still undeleted.
FP="$(mk_fixture fill-p)"; advance_to "$FP" 8
FP_SID="closeout-fill-sid"
mkdir -p "$SB_HOME/.claude/projects/-fixture-fill"
FP_TR="$SB_HOME/.claude/projects/-fixture-fill/$FP_SID.jsonl"
jq -nc '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_cron1",name:"CronCreate",input:{cron:"*/30 * * * *",recurring:true,prompt:"Patrol tick (bionic). Run: bash /abs/hooks/session-poker.sh tick"}}]}}' > "$FP_TR"
jq -nc '{type:"user",isSidechain:false,message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_cron1",content:"Scheduled recurring job pj7c91ab (*/30 * * * *) — Patrol tick"}]}}' >> "$FP_TR"
expect_contains "FILL.16 precondition: the transcript scan yields the Patrol job, kind patrol" "JOB	pj7c91ab	" \
  "$(bash -c '. "$1/roots.sh" && . "$1/patrol.sh" && _patrol_scan "$2" ""' _ "$REPO_ROOT/payload/scripts/lib" "$FP_TR")"
run_close_as "$FP_SID" "$FP" run

# A LANDING REPORT THAT CANNOT BE READ is a sentence, not a mark: the plugin root's poker is a stub that fails.
FQ="$(mk_fixture fill-q)"; advance_to "$FQ" 8
FQ_PLUG="$SANDBOX/fill-q-plugin"
mkdir -p "$FQ_PLUG"
for f in "$REPO_ROOT"/payload/* "$REPO_ROOT"/payload/.claude-plugin; do [ -e "$f" ] && ln -s "$f" "$FQ_PLUG/${f##*/}"; done
rm -f "$FQ_PLUG/hooks"; mkdir -p "$FQ_PLUG/hooks"
for f in "$BIONIC_HOOKS_DIR"/*; do ln -s "$f" "$FQ_PLUG/hooks/${f##*/}"; done
rm -f "$FQ_PLUG/hooks/session-poker.sh"; printf '#!/bin/bash\nexit 1\n' > "$FQ_PLUG/hooks/session-poker.sh"
( in_fixture "$FQ" || exit 9
  HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$FQ_PLUG" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    bash "$SCRIPT" "$FQ/$PLAN_REL" run ) > "$SANDBOX/fq-out" 2>&1
FQ_RC=$?
expect_eq "FILL.18 with a poker that cannot report landings the close still finishes (rc 0)" "0" "$FQ_RC"

# ============================================================
section "§REF — wave-35 T10 (REQ-1 AC-1.7, D10): the facts judge reads the working branch's ref through the one reader; a branch that names no commit stays uncovered"
# ============================================================
# close-out's facts judge (`facts_judge`) hands lib/proof.sh `facts_state` the head of the working branch, and it now
# reads that head through lib/proof.sh `proof_branch_head` (`refs/heads/<branch>`), the reader `current 7`, `current 8`
# and the floor judge share, never a checkout's and never whatever else git would resolve the bare name to. The
# branch name itself is read through lib/run.sh `plan_working_branch` (SDLC State, then frontmatter), so close-out
# has no second reader of it (A-orch-16).
# FIXTURE FIDELITY: mk_fixture's run at Step 8: wave/01-fixture merged into main, every fact planted at its head by
# the product's pair, the branch checked out in `<project>-wave`. Each row then takes away one thing a run that has
# merged takes away: the worktree, the branch, the SDLC-State key.
# fails-when: the judge reads the checkout's head, or a ref other than the branch; a deleted branch reads covered;
# a plan whose working-branch: is in its frontmatter alone is refused for naming none.
ref_head() { fixture_git "$1" rev-parse --verify -q "refs/heads/wave/01-fixture" 2>/dev/null; }
PREF="$(mk_fixture ref-merged)"; advance_to "$PREF" 8
REF_H="$(ref_head "$PREF")"
fixture_git "$PREF" worktree remove --force "$PREF-wave" >/dev/null 2>&1
expect_eq "REF-0 precondition: the branch names a commit, no checkout holds it, and the main checkout is on main" "yes|0|main" \
  "$([ -n "$REF_H" ] && echo yes)|$(fixture_git "$PREF" worktree list --porcelain | grep -c '^branch refs/heads/wave/01-fixture$' | tr -d ' ')|$(fixture_git "$PREF" symbolic-ref --short HEAD)"
run_close "$PREF" check
run_close "$PREF" run
expect_eq "REF-2 …and run closes the plan (rc 0)" "0|1" "$CO_RC|$(run_open_rc "$PREF/$PLAN_REL")"

PREFD="$(mk_fixture ref-deleted)"; advance_to "$PREFD" 8
fixture_git "$PREFD" worktree remove --force "$PREFD-wave" >/dev/null 2>&1
fixture_git "$PREFD" branch -D wave/01-fixture >/dev/null 2>&1
expect_eq "REF-3 precondition: the working branch is deleted (no ref names it)" "" "$(ref_head "$PREFD")"
run_close "$PREFD" check
expect_contains "REF-3b AC-1.7 a deleted branch: check says the facts would be refused" "facts: WOULD REFUSE" "$CO_OUT"
# A TAG OF THE SAME NAME IS NOT THE BRANCH. `git rev-parse <name>` resolves refs/tags/<name> before refs/heads/<name>, so a
# judge that asks git for the bare name reads a tag where the branch is gone; the branch's ref reader does not.
fixture_git "$PREFD" tag wave/01-fixture main >/dev/null 2>&1
expect_nonempty "REF-4 precondition: a tag of the branch's name names a commit" \
  "$(fixture_git "$PREFD" rev-parse --verify -q 'refs/tags/wave/01-fixture^{commit}' 2>/dev/null)"
run_close "$PREFD" check

PREFF="$(mk_fixture ref-frontmatter)"; advance_to "$PREFF" 8
awk '
  NR == 1 && $0 == "---" { print; fm = 1; next }
  fm && $0 == "---" { print "working-branch: wave/01-fixture"; print; fm = 0; next }
  /^## SDLC State/ { s = 1 }
  s && /^working-branch: / { next }
  { print }' "$PREFF/$PLAN_REL" > "$PREFF/$PLAN_REL.wb" && mv "$PREFF/$PLAN_REL.wb" "$PREFF/$PLAN_REL"
run_close "$PREFF" check
expect_absent "REF-5b A-orch-16 close-out reads the branch through the one reader: a frontmatter key is not refused as none" \
  "names no working-branch" "$CO_OUT"

# ============================================================
section "§ORDER — the integrate row publishes the reviews part before the push and the pull request (REQ-15 AC-15.2; the integrate row's own part)"
# ============================================================
# At pr dealing close-out merges nothing and opens nothing: it records, in the continuation's `## Pull request`, the
# acts the integrate row does, in the order it does them: `reviews-part <row>`, then the push, then `gh pr create`. The part
# is first because the push and the pull request carry the branch's tip, and a part rendered after them is on no branch
# the pull request names.
# FIXTURE FIDELITY: mk_task_pr_fixture's task-scale plan (integrate cell `pr`), gaining the integrate row a task plan
# carries at Step 8 (landed, so the rows-landed act has nothing to bind a session for); the continuation is the one the run
# writes.
# fails-when: the continuation names the push or `gh pr create` before `reviews-part <row>`, omits the verb, names another
#   row, or the section stops naming `gh pr create`.
ord_pos() {  # <file> <needle> -> the 1-based line number of the needle's first line in the `## Pull request` section, or empty
  awk -v n="$2" '/^## / { s = ($0 == "## Pull request"); next } s && index($0, n) { print NR; exit }' "$1"
}
PPO="$(mk_task_pr_fixture order-pr "fix/x")"
awk '{ print } /^\| T1 \|/ { print "| T3 | 8 | integrate | open the pull request | orchestrator | — | 10 | AC-1 | none | landed |" }' \
  "$PPO/$PLAN_REL" > "$PPO/$PLAN_REL.o" && mv "$PPO/$PLAN_REL.o" "$PPO/$PLAN_REL"
expect_contains "ORDER-0 precondition: the plan carries the integrate row the section names" "| T3 | 8 | integrate |" "$(cat "$PPO/$PLAN_REL")"
run_close "$PPO" run
expect_eq "ORDER-1 the task-scale run closes" "0" "$CO_RC"
OR_PART="$(ord_pos "$PPO/$CONT_REL" 'session-poker.sh reviews-part T3')"
OR_PUSH="$(ord_pos "$PPO/$CONT_REL" 'git push')"
OR_PR="$(ord_pos "$PPO/$CONT_REL" 'gh pr create --base main --head fix/x')"
expect_nonempty "ORDER-1b precondition: the section names the part, the push and the pull request (positions $OR_PART $OR_PUSH $OR_PR)" "$OR_PART$OR_PUSH$OR_PR"
expect_eq "ORDER-2 the continuation records reviews-part <integrate row> first, then the push, then gh pr create" "yes" \
  "$([ -n "$OR_PART" ] && [ -n "$OR_PUSH" ] && [ -n "$OR_PR" ] && [ "$OR_PART" -lt "$OR_PUSH" ] && [ "$OR_PUSH" -lt "$OR_PR" ] && echo yes || echo no)"
expect_contains "ORDER-3 the push names the working branch" "git push -u origin fix/x" "$(cat "$PPO/$CONT_REL")"
# the plan with no integrate row names no verb to run, and still records the push before the pull request
PPN="$(mk_task_pr_fixture order-pr-norow "fix/x")"
run_close "$PPN" run
expect_absent "ORDER-4 a plan with no integrate row names no reviews-part" "reviews-part" "$(cat "$PPN/$CONT_REL")"
expect_eq "ORDER-4b …and still records the push before gh pr create" "yes" \
  "$(a="$(ord_pos "$PPN/$CONT_REL" 'git push')"; b="$(ord_pos "$PPN/$CONT_REL" 'gh pr create')"; [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && echo yes || echo no)"

# AT MERGE DEALING close-out merges nothing either: its merge act is a readback that the working branch is reachable from the
# integration branch, and the person's merge came first. When close-out itself renders the part (no integrate row did), it
# publishes it BEFORE that readback, so the readback reads the branch the part is on, and holds until that tip is merged.
# FIXTURE FIDELITY: mk_fixture's wave-scale plan (integrate cell `merge`) at Step 8 with the release entry committed on the
# working branch and merged into main, as the release row's landing and the person's merge leave it; the part is not yet
# listed, as a run with no integrate row leaves it.
# fails-when: the reviews line comes after the merge line; the branch is not at the part's commit when the readback reads it;
#   the run closes with the part on no branch main holds; or the second run, after the person merges the published tip,
#   renders a second part.
ord_fixture() {  # <name> -> a wave-scale project at Step 8 whose release entry has no ### The reviews part, merged into main
  local p wt
  p="$(mk_fixture "$1")" && advance_to "$p" 8 || return 1
  wt="$p-wave"
  awk '{ print } /^adrs: none$/ && !d { print "release: 9.9.9"; d = 1 }' "$p/$PLAN_REL" > "$p/$PLAN_REL.r" \
    && mv "$p/$PLAN_REL.r" "$p/$PLAN_REL"
  printf '# Changelog\n\n## 9.9.9 — 2026-10-22\n\nThe prose a person wrote.\n\n### Known limits\n\n- one limit\n' > "$wt/CHANGELOG.md"
  fixture_git "$wt" add CHANGELOG.md && fixture_git "$wt" commit -q -m "the release entry" >/dev/null 2>&1 \
    && fixture_git "$p" merge -q --no-ff -m "merge the release" wave/01-fixture >/dev/null 2>&1 || return 1
  printf '%s\n' "$p"
}
PMO="$(ord_fixture order-merge)"
plant_facts "$PMO"
OM_H="$(fixture_git "$PMO" rev-parse --verify -q refs/heads/wave/01-fixture)"
expect_eq "ORDER-5 precondition: the integration branch holds the working branch's tip, as the person's merge left it" "yes" \
  "$(fixture_git "$PMO" merge-base --is-ancestor wave/01-fixture main && echo yes || echo no)"
run_close "$PMO" run
OM_TIP="$(fixture_git "$PMO" rev-parse --verify -q refs/heads/wave/01-fixture)"
expect_eq "ORDER-6 close-out published a part: the working branch moved past the tip the person merged" "yes" \
  "$([ -n "$OM_TIP" ] && [ "$OM_TIP" != "$OM_H" ] && fixture_git "$PMO" log -1 --format=%an "$OM_TIP" | /usr/bin/grep -qx 'bionic close-out' && echo yes || echo no)"
OM_ACT="$(printf '%s\n' "$CO_OUT" | /usr/bin/grep -c '^merge: ')"
expect_eq "ORDER-7 …so the readback, read on that branch, held: the run did not close, and its merge act never ran" "yes|0" \
  "$([ "$CO_RC" -ne 0 ] && echo yes)|$OM_ACT"
expect_contains "ORDER-7b …saying the working branch is not merged" "is not reachable from" "$CO_OUT"
expect_contains "ORDER-7c …after the reviews line named the published commit" "reviews: " "$CO_OUT"
expect_contains "ORDER-7d …which names the commit the branch is at" "$(printf '%.12s' "$OM_TIP")" "$(printf '%s\n' "$CO_OUT" | /usr/bin/grep '^reviews: ')"
expect_eq "ORDER-8 main does not hold the part until the published tip is merged" "no" \
  "$(fixture_git "$PMO" show main:CHANGELOG.md 2>/dev/null | /usr/bin/grep -q '^### The reviews' && echo yes || echo no)"
fixture_git "$PMO" merge -q --no-ff -m "merge the published part" wave/01-fixture >/dev/null 2>&1
run_close "$PMO" run
expect_eq "ORDER-9 after the person merges the published tip, the run closes and finds the part already listed" "0|yes" \
  "$CO_RC|$(printf '%s\n' "$CO_OUT" | /usr/bin/grep '^reviews: ' | /usr/bin/grep -q 'already lists' && echo yes)"
expect_eq "ORDER-9b …and rendered no second part: the branch is where the first run left it" "$OM_TIP" \
  "$(fixture_git "$PMO" rev-parse --verify -q refs/heads/wave/01-fixture)"

# ============================================================
section "§ADRS — the Step-7 advance renders adrs: from the Step 7 adr: line, and close-out's epic row reads either (REQ-9 AC-9.1)"
# ============================================================
# The document step's pointer is the Step 7 block's `adr:` line (`step-field 7 adr=…`); the epic row reads the plan's
# `adrs:` frontmatter, which no verb wrote, so a plan with the first and not the second was refused its row. `current 7`
# renders `adrs:` from the block when the frontmatter has none (`adrs: none` when the block says n/a), and never
# rewrites one that is there; close-out reads the frontmatter, else the Step 7 `adr:` line. An ADR path with no
# `adr-<n>` gives no number, so the row carries the path as written. FIXTURE FIDELITY: mk_fixture's plan with its
# `adrs:` line taken out and its Step 7 line written as `step-line 7` and `step-field 7 adr=` write it; the advance is
# the real verb, run as a session bound to the plan.
# fails-when: a plan with `adr:` on its Step 7 line and no `adrs:` makes `epic_row_missing` refuse the row.
ad_step7() {  # <project> <adr value> -> the plan without adrs:, its Step 7 line a block carrying adr: <value>
  local plan="$1/$PLAN_REL"
  case "$1" in "$SANDBOX"/*) : ;; *) echo "ad_step7: refusing outside the sandbox: '$1'" >&2; return 1 ;; esac
  AD_V="$2" awk '
    NR == 1 { fm = 1 } fm && NR > 1 && /^---$/ { fm = 0 }
    fm && /^adrs:/ { next }
    /^- Step 7:/ { print "- Step 7: document: the ADR is written"; print "  adr: " ENVIRON["AD_V"]; next }
    { print }' "$plan" > "$plan.a" && mv "$plan.a" "$plan"
}
ad_adrs() { awk 'NR == 1 { fm = 1; next } fm && /^---$/ { exit } fm && /^adrs:/ { sub(/^adrs:[ \t]*/, ""); print }' "$1"; }
ad_poke() {  # <project> <sid> <verb> [<arg>...] -> AD_RC, AD_OUT: the real poker verb, in the fixture, as that session
  local proj="$1" sid="$2"; shift 2
  ( in_fixture "$proj" || exit 9
    HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
      CLAUDE_CODE_SESSION_ID="$sid" bash "$BIONIC_HOOKS_DIR/session-poker.sh" "$@" ) > "$SANDBOX/ad-poker" 2>&1
  AD_RC=$?; AD_OUT="$(cat "$SANDBOX/ad-poker")"
}
ad_bind() { ( in_fixture "$1" || exit 1; . "$REPO_ROOT/tests/lib/bound-marker.sh"; bound_marker "$1" "$2" "$1/$PLAN_REL" ); }
AD_ADR="adrs/epic-fx/adr-061-the-pointer.md"
# close-out reads either: the plan carries the Step 7 adr: line and no adrs:
PAD="$(mk_fixture adrs-either)"; ad_step7 "$PAD" "$AD_ADR"; advance_to "$PAD" 8
expect_eq "AD-0 precondition: the plan carries no adrs: line, and its Step 7 block the adr: line" "|yes" \
  "$(ad_adrs "$PAD/$PLAN_REL")|$(/usr/bin/grep -qxF "  adr: $AD_ADR" "$PAD/$PLAN_REL" && echo yes || echo no)"
run_close "$PAD" run
expect_eq "AD-1 close-out reads the Step 7 adr: line: run exits 0 and the epic row's ADR cell names its number" "0|061" "$CO_RC|$(adr_cell "$PAD")"
[ "$CO_RC" = 0 ] || printf '%s\n' "$CO_OUT" | /usr/bin/grep -i 'adrs\|refuse' | head -4 | sed 's/^/    | /'
# the advance renders the line, from a session bound to the plan
AD_SID="closeout-adrs-sid"
PAV="$(mk_fixture adrs-advance)"; ad_step7 "$PAV" "$AD_ADR"; advance_to "$PAV" 6; ad_bind "$PAV" "$AD_SID"
ad_poke "$PAV" "$AD_SID" current 7
expect_eq "AD-2 current 7 renders adrs: from the Step 7 adr: line: rc 0, current: 7, the frontmatter names the ADR" \
  "0|7|$AD_ADR" "$AD_RC|$(sed -n 's/^current: //p' "$PAV/$PLAN_REL")|$(ad_adrs "$PAV/$PLAN_REL")"
[ "$AD_RC" = 0 ] || printf '%s\n' "$AD_OUT" | tail -6 | sed 's/^/    | /'
expect_contains "AD-2b …and says what it rendered" "adrs: $AD_ADR" "$AD_OUT"
advance_to "$PAV" 8
run_close "$PAV" run
expect_eq "AD-3 the rendered line closes the run: rc 0 and the epic row names 061" "0|061" "$CO_RC|$(adr_cell "$PAV")"
# an ADR named by a path with no adr-<n>: the line is rendered, and the row carries the path
PAP="$(mk_fixture adrs-path)"; ad_step7 "$PAP" "record/wave-01-fixture/adr.md"; advance_to "$PAP" 6; ad_bind "$PAP" "$AD_SID"
ad_poke "$PAP" "$AD_SID" current 7
expect_eq "AD-4 a path with no adr-<n> is rendered as written" "0|record/wave-01-fixture/adr.md" "$AD_RC|$(ad_adrs "$PAP/$PLAN_REL")"
advance_to "$PAP" 8
run_close "$PAP" run
expect_eq "AD-5 …and the epic row is written, its ADR cell the path, never refused" "0|record/wave-01-fixture/adr.md" "$CO_RC|$(adr_cell "$PAP")"
# a Step 7 that says n/a renders adrs: none; an adrs: line already there is never rewritten
PAN="$(mk_fixture adrs-na)"; advance_to "$PAN" 6; ad_bind "$PAN" "$AD_SID"
awk 'NR == 1 { fm = 1 } fm && NR > 1 && /^---$/ { fm = 0 } fm && /^adrs:/ { next }
  /^- Step 7:/ { print "- Step 7: document: no ADR"; print "  n/a: no ADR owed by a fixture"; next } { print }' \
  "$PAN/$PLAN_REL" > "$PAN/plan.tmp" && mv "$PAN/plan.tmp" "$PAN/$PLAN_REL"
ad_poke "$PAN" "$AD_SID" current 7
expect_eq "AD-6 a Step 7 line that says n/a renders adrs: none" "0|none" "$AD_RC|$(ad_adrs "$PAN/$PLAN_REL")"
[ "$AD_RC" = 0 ] || printf '%s\n' "$AD_OUT" | tail -6 | sed 's/^/    | /'
PAK="$(mk_fixture adrs-kept)"; ad_step7 "$PAK" "$AD_ADR"; advance_to "$PAK" 6; ad_bind "$PAK" "$AD_SID"
set_plan_keys "$PAK" "-" "adrs: adrs/epic-fx/adr-060-written-by-hand.md"
ad_poke "$PAK" "$AD_SID" current 7
expect_eq "AD-7 an adrs: line the plan carries is kept as written" "0|adrs/epic-fx/adr-060-written-by-hand.md" "$AD_RC|$(ad_adrs "$PAK/$PLAN_REL")"

finish
