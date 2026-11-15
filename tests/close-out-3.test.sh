#!/bin/bash
# tests/close-out-3.test.sh — payload/scripts/close-out.sh, part 3 of 6: sections §HAND-HOLDS through DEBT-LINES.
#
# THE SUITE IS SIX PARTS: one close-out.test.sh outran the suite bar, so it runs as parts cut at section boundaries,
# and the two longest were cut again by the seconds of one run: RUNS through §REG left this part for close-out-6.
# Its design, sandbox, fixture builders and helpers are in tests/close-out.prelude.sh, sourced below after the framework.
#
# Usage: bash tests/close-out-3.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"
. "$(dirname "$0")/lib/roster-row.sh"   # the one roster-row builder
. "$(dirname "$0")/close-out.prelude.sh"

# ============================================================
section "§HAND-HOLDS — wave-35 T12 (REQ-8 AC-8.1, D17): the hand-hold count is folded from the lines the escape-hatch verbs wrote"
# ============================================================
# close-out prints the `landing-report --hand-holds` line on its card and writes it into the continuation under `## Hand-holds`.
# Each kind is counted from the line its verb wrote, the fixture plants each in its writer's shape (an amend, a hold, an
# extension and an adoption as the hand event in the run's log, the proofs, the waiver and the approval through
# lib/proof.sh's writers), and a prose line saying `by-hand` counts nothing. A roster row's `amended=`, `held=`,
# `extended=` or `adopted_from=` with no event beside it is no act, and the tmp wipe that takes the rosters takes nothing
# the line counts.
# HH_GATE: hoisted to tests/close-out.prelude.sh (a later part reads it)
HH_C="$(printf 'd%.0s' $(seq 40))"
# The report reads from the last build landing, the second build row's at 10:40, so the decline, the lift, the 10:00
# amend and that row's own hand landing fall before the window, and the date-only matrix waiver's day holds that start, so it is unplaced.
HH_WANT="hand-holds: total=7 · by-hand=0 · stop-runs=1 · declines=0 · lifts=0 · amends=1 · holds=1 · extensions=1 · waivers=1 · status-writes=0 · second-regressions=1 · adoptions=1 · fixed=0 · needs-you=0 · unplaced=1"
HH_ALL="hand-holds: total=12 · by-hand=1 · stop-runs=1 · declines=1 · lifts=1 · amends=2 · holds=1 · extensions=1 · waivers=2 · status-writes=0 · second-regressions=1 · adoptions=1 · fixed=0 · needs-you=0 · unplaced=0"
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
  # the run's log: two amends, a hold, an extension and an adoption, each the hand event its verb wrote
  {
    printf 'run/v1|ev=hand|by=fixture|name=w-a|what=amend|why=widen the files|at=2026-10-06T10:00:00Z\n'
    printf 'run/v1|ev=hand|by=fixture|name=w-b|what=amend|why=add a suite|at=2026-10-06T11:00:00Z\n'
    printf 'run/v1|ev=hand|agent=ad|by=fixture|from=old-sid|name=w-d|what=adopt|why=the session was cleared|at=2026-10-06T11:30:00Z\n'
    printf 'run/v1|ev=hand|by=fixture|name=w-a|what=hold|why=waiting on the reader|at=2026-10-06T12:00:00Z\n'
    printf 'run/v1|ev=hand|by=fixture|name=w-c|what=extend|why=more work|at=2026-10-06T12:30:00Z\n'
  } >> "$rec/run.log"
  # the roster: the audit keys of each kind on rows no event stands beside, inside the window, so they count nothing
  {
    roster_row_fixture status=identified name=w-x agent_id=ax plan="$plan" amended="2026-10-06T12:40:00Z widen the files"
    roster_row_fixture status=identified name=w-x agent_id=ax plan="$plan" held="2026-10-06T12:40:00Z waiting fp=1-2-3"
    roster_row_fixture status=identified name=w-x agent_id=ax plan="$plan" extended="2026-10-06T12:40:00Z more work"
    roster_row_fixture status=identified name=w-y agent_id=ay source=adopted adopted_from=old-sid plan="$plan"
  } >> "$p/.bionic/tmp/roster-fixture.state"
  # the run's log: a second floor, a waiver of a question and an approval of a second regression, each by its writer, and
  # a criterion block's waiver as a run brought forward carries it, a hand act placed by its day alone
  h="$(bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1; proof_last "$2" floor' _ "$REPO_ROOT/payload/scripts/lib" "$plan")"
  expect_nonempty "HH-0a precondition: the fixture run already holds one floor proof, whose head the second reuses" "$h"
  bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1
    LOG_AT=2026-10-06T12:00:00Z proof_approval_event "$2" regression-2 "by=Chris Lehman" said=yes \
      && LOG_AT=2026-10-06T13:00:00Z proof_event "$2" kind=regression "head=$3" evidence=record/wave-01-fixture/floor-2.log \
      && LOG_AT=2026-10-06T13:10:00Z proof_waiver_event "$2" question=evidence "head=$3" "by=Chris Lehman" "said=waive it"' \
    _ "$REPO_ROOT/payload/scripts/lib" "$plan" "$h" || echo "hh_plant: a writer refused an event in '$p'" >&2
  printf 'run/v1|ev=hand|ac=AC-1|what=waive-row|by=Chris Lehman|said=waive the row|at=2026-10-06\n' >> "$rec/run.log"
  # the plan: prose naming each kind, and fenced lines of an older plan's shape, which count nothing
  w="$(mktemp "$SANDBOX/hh-plan.XXXXXX")"
  awk '
    /^## Tasks/ { print "- T1: landed by-hand (kind=hand) after waived: evidence; approved: regression-2 was discussed"
                  print "  waiver: someone said we might waive this later"; print ""
                  print "```"; print "proved: kind=regression head=0123456789abcdef at=2026-10-06T14:00:00Z evidence=x"
                  print "approved: regression-2 by Someone 2026-10-06T14:00:00Z \"quoted in a fence\""
                  print "waived: question=adversarial head=0123456789abcdef by Someone 2026-10-06T14:00:00Z \"fenced\""; print "\140\140\140"; print ""; print; next }
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
PHP="$(CO_PLAN_AT=14 mk_fixture handholds-prose)"; advance_to "$PHP" 8
mkdir -p "$PHP/.bionic/docs/record/wave-01-fixture"
printf 'note: T3 was landed by-hand (kind=hand); its run was stopped (ev=stop-run); the T2 decline was lifted (state=lift); amended= held= extended=\n' > "$PHP/.bionic/docs/record/wave-01-fixture/landing-proofs.log"
cp "$PHP/.bionic/docs/record/wave-01-fixture/landing-proofs.log" "$PHP/.bionic/docs/record/wave-01-fixture/fill-ledger.log"
awk '/^- Step 8:/ { print "- T1: landed by-hand (kind=hand) after waived: evidence; approved: regression-2 was discussed; a second floor"; print; next } { print }' \
  "$PHP/$PLAN_REL" > "$PHP/plan.b" && mv "$PHP/plan.b" "$PHP/$PLAN_REL"
HH_PROSE="$(hh_report "$PHP" --hand-holds)"
expect_eq "HH-4 a run whose only by-hand, stop-run, decline, lift, waiver and approval are prose counts zero in every kind" \
  "hand-holds: total=0 · by-hand=0 · stop-runs=0 · declines=0 · lifts=0 · amends=0 · holds=0 · extensions=0 · waivers=0 · status-writes=0 · second-regressions=0 · adoptions=0 · fixed=0 · needs-you=0" \
  "$(printf '%s\n' "$HH_PROSE" | grep '^hand-holds: ')"
# the card: check prints the line, run prints it after the wipe took the roster, the continuation carries it
run_close "$PH" check
expect_eq "HH-5 check prints the hand-holds line on the card" "$HH_WANT" "$(printf '%s\n' "$CO_OUT" | grep '^hand-holds: ')"
run_close "$PH" run
expect_eq "HH-6 run exits 0, prints the same line on the card, and the wipe took the roster it read" "0/$HH_WANT/0" \
  "$CO_RC/$(printf '%s\n' "$CO_OUT" | grep '^hand-holds: ')/$(tmp_entries "$PH")"
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
expect_eq "HH-10b …run exits 0, its card prints the line and reports no add" "0|yes|no" \
  "$CO_RC|$(contains "$CO_OUT" "hand-holds: total=")|$(contains "$CO_OUT" "added the ## Hand-holds")"
# the heading is there and the line is not: the line goes under it, after what the person wrote there
PHE3="$(mk_fixture handholds-existing3)"; advance_to "$PHE3" 8; hh_plant "$PHE3"
mkdir -p "$PHE3/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n## Hand-holds\n\nthe person counted two by hand\n\n## Resume instruction\n\nedited by a person\n' > "$PHE3/$CONT_REL"
run_close "$PHE3" run
expect_eq "HH-11a …run exits 0, and the Resume instruction after it is as it was" "0|## Resume instruction|edited by a person" \
  "$CO_RC|$(awk '/^## Resume instruction$/ { s = 1 } s && NF' "$PHE3/$CONT_REL" | paste -sd'|' -)"
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
sed '/|ev=proof|kind=regression|/d' "$PFL/$LOG_REL" > "$PFL/$LOG_REL.n" && mv "$PFL/$LOG_REL.n" "$PFL/$LOG_REL"
printf 'regression-command: true\n' >> "$PFL/.bionic/config.yaml"
( in_fixture "$PFL" || exit 1; . "$REPO_ROOT/tests/lib/bound-marker.sh"; bound_marker "$PFL" "$FL_SID" "$PFL/$PLAN_REL" )
fl_poke() {  # <verb> [<arg>...] -> FL_RC, FL_OUT: the real poker verb, in the fixture, as this session
  ( in_fixture "$PFL" || exit 9
    HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" BIONIC_PROBE_CORES=8 BIONIC_PROBE_USED_PCT=30 BIONIC_PROBE_BUSY_CORES=1.0 BIONIC_PROBE_BUSY_CORES_5M=1.0 BIONIC_PROBE_LOAD_1M=1.0 BIONIC_PROBE_FREE_PCT=60 BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_SWAP_PCT=0 \
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
# wrote beside it, and proof_event appends the proof to the run's log.
# proof-add itself is not driven here: its dry commit runs the real gate at current: 4, which this fixture's
# Step-7 plan (no Step 0-6 lines) does not meet for any floor; session-poker §FLOOR-DECLARED drives the verb.
FL_AT="$(bash -c '. "$1/roots.sh" && . "$1/proof.sh" || exit 9
  h="$(proof_attested regression "$2/record/wave-01-fixture/regression-run-$3.log" "$4" "$6" "" "$5")" || { printf "%s" "$h"; exit 1; }
  LOG_AT=2026-10-04T13:00:00Z proof_event "$6" kind=regression "head=$h" "evidence=record/wave-01-fixture/regression-run-$3.log" && printf "%s" "$h"' \
  _ "$REPO_ROOT/payload/scripts/lib" "$PFL/.bionic/docs" "$FL_H" "$PFL-wave" "$PFL" "$PFL/$PLAN_REL" 2>&1)"
fl_poke current 8
expect_eq "FL3 current 8 is admitted on the facts (exit 0)" "0|n=8" "$FL_RC|$(bash "$REPO_ROOT/payload/scripts/reader.sh" "$PFL/$PLAN_REL" step | head -1)"
run_close "$PFL" run
expect_eq "FL4 AC-17.1 close-out.sh run delivers on a declared floor's proof (rc 0), the plan closed" "0|1" \
  "$CO_RC|$(run_open_rc "$PFL/$PLAN_REL")"

# A PROJECT WITH NO tests/*.test.sh AND NO floor: CLOSES ITS RUN ON ITS OWN RUNNER'S LOG (wave-36 T35; REQ-7 AC-7.10; D13).
# The floor is a fact: the log the project's own runner left, opening head=<the working head> dirty=0 and ending rc=0,
# is the evidence as it stands, with no config key and no regression-run. The judge and writer are driven as FL2 drives them.
PFN="$(mk_fixture floor-any)"
FN_SID="closeout-floor-2"
sed '/|ev=proof|kind=regression|/d' "$PFN/$LOG_REL" > "$PFN/$LOG_REL.n" && mv "$PFN/$LOG_REL.n" "$PFN/$LOG_REL"
( in_fixture "$PFN" || exit 1; . "$REPO_ROOT/tests/lib/bound-marker.sh"; bound_marker "$PFN" "$FN_SID" "$PFN/$PLAN_REL" )
FN_H="$(fixture_git "$PFN" rev-parse wave/01-fixture)"
mkdir -p "$PFN/.bionic/docs/record/wave-01-fixture"
# THE RUN IS RECORDED (wave-37 T4; D7, ADR-057): the log and its run line, as tests/lib/regression-fixture.sh writes them.
printf '$ pnpm ci:local\n412 passed\n' | regression_fixture "$PFN/$PLAN_REL" "$PFN/.bionic/docs/record/wave-01-fixture/ci.log" "$FN_H" 0 0
FN_AT="$(bash -c '. "$1/roots.sh" && . "$1/proof.sh" || exit 9
  h="$(proof_attested regression "$2/record/wave-01-fixture/ci.log" "$3" "$5" "" "$4")" || { printf "%s" "$h"; exit 1; }
  LOG_AT=2026-10-04T13:00:00Z proof_event "$5" kind=regression "head=$h" evidence=record/wave-01-fixture/ci.log && printf "%s" "$h"' \
  _ "$REPO_ROOT/payload/scripts/lib" "$PFN/.bionic/docs" "$PFN-wave" "$PFN" "$PFN/$PLAN_REL" 2>&1)"
FN_RC="$( ( in_fixture "$PFN" || exit 9
  HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    CLAUDE_CODE_SESSION_ID="$FN_SID" bash "$BIONIC_HOOKS_DIR/session-poker.sh" current 8 ) > "$SANDBOX/fn-poker" 2>&1; echo $?)"
expect_eq "FL7 AC-7.10 current 8 is admitted on that floor (exit 0)" "0|n=8" "$FN_RC|$(bash "$REPO_ROOT/payload/scripts/reader.sh" "$PFN/$PLAN_REL" step | head -1)"
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

finish
