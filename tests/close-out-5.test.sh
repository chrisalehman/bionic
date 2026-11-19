#!/bin/bash
# tests/close-out-5.test.sh — payload/scripts/close-out.sh, part 5 of 6: the CARRY section alone.
#
# THE SUITE IS SIX PARTS: one close-out.test.sh outran the suite bar, so it runs as parts cut at section boundaries,
# and the two longest were cut again by the seconds of one run: CARRY left close-out-2 for this part.
# Its design, sandbox, fixture builders and helpers are in tests/close-out.prelude.sh, sourced below after the framework.
#
# Usage: bash tests/close-out-5.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"
. "$(dirname "$0")/lib/roster-row.sh"   # the one roster-row builder
. "$(dirname "$0")/close-out.prelude.sh"

section "CARRY — wave-28 T17 (AC-8.7, D21): close-out writes every open deferral, with its sentence, under ## Deferrals of the continuation"
# ============================================================
# A deferral is held to its debts: an older plan carries one `deferred:` line per finding the table
# defers, its sentence as ` stated="<sentence>"` (a run now writes both as finding events), and
# close-out carries each into the continuation, in the one form the next wave's Step 1 card reads:
#
#   deferred: <record>#<n> <S> <reach> "<title>" stated="<sentence|->" from=<wave name>
#
# in the plan's order, `-` for a deferral with no sentence, a `"` or a `\` in a sentence written
# `\"` and `\\` as the plan holds it. The heading is written whether or not there is anything under
# it, so a continuation that reports no deferral differs from one written before the heading existed.
# CARRY_REC: hoisted to tests/close-out.prelude.sh (a later part reads it)
# carry_plant: hoisted to tests/close-out.prelude.sh (a later part reads it)
# carry_section: hoisted to tests/close-out.prelude.sh (a later part reads it)
# CARRY_W: hoisted to tests/close-out.prelude.sh (a later part reads it)
CARRY_Q1='Said \"go\" \\ now | here'   # the sentence: Said "go" \ now | here, as the plan holds it
PC="$(mk_fixture carry1)"; advance_to "$PC" 8
carry_plant "$PC" \
  "deferred: $CARRY_REC#2 S3 on \"second, written first\" stated=\"The second sentence.\"" \
  "deferred: $CARRY_REC#1 S2 off \"first, unstated\"" \
  "deferred: $CARRY_REC#3 S2 off \"third, quoted\" stated=\"$CARRY_Q1\""
expect_eq "CARRY-0 precondition: the run's log carries three deferral events, one with its sentence" "3 1" \
  "$(awk 'index($0, "|ev=finding|") && index($0, "|to=deferred|") { d++; if (index($0, "|stated=")) s++ } END { print d + 0, s + 0 }' "$PC/$LOG_REL")"
run_close "$PC" run
expect_eq "CARRY-1 run exits 0 over a run carrying deferrals (the gate and the parsers admit it)" "0" "$CO_RC"
expect_nonempty "CARRY-3 precondition: the extractor finds lines under the heading" "$(carry_section "$PC/$CONT_REL")"
expect_eq "CARRY-5 …and the heading comes after the template's Next wave section and before the Resume instruction" "yes" \
  "$(awk '/^## Next wave/ { a = NR } /^## Deferrals$/ { b = NR } /^## Resume instruction/ { c = NR } END { print (a && b > a && c > b) ? "yes" : "no" }' "$PC/$CONT_REL")"
expect_eq "CARRY-6 the plan close-out closed still reads closed (run_open says 1)" "1" "$(run_open_rc "$PC/$PLAN_REL")"

# none: the heading and nothing under it
PN="$(mk_fixture carry2)"; advance_to "$PN" 8
run_close "$PN" run
expect_eq "CARRY-7 a run with no deferral exits 0" "0" "$CO_RC"

# an existing continuation is never overwritten: a missing heading is appended, a present one is left
PE="$(mk_fixture carry3)"; advance_to "$PE" 8
carry_plant "$PE" "deferred: $CARRY_REC#1 S2 off \"kept\" stated=\"A kept sentence.\""
mkdir -p "$PE/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Resume instruction\n\nedited by a person\n' > "$PE/$CONT_REL"
run_close "$PE" run
expect_eq "CARRY-9 a continuation that exists without the heading: run exits 0" "0" "$CO_RC"
expect_eq "CARRY-11 …and the deferral is appended under a ## Deferrals heading" \
  "deferred: $CARRY_REC#1 S2 off \"kept\" stated=\"A kept sentence.\" from=$CARRY_W" "$(carry_section "$PE/$CONT_REL")"
PH="$(mk_fixture carry4)"; advance_to "$PH" 8
carry_plant "$PH" "deferred: $CARRY_REC#1 S2 off \"not carried over a written heading\" stated=\"A sentence.\""
mkdir -p "$PH/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\nnone, said the person\n' > "$PH/$CONT_REL"
run_close "$PH" run
expect_eq "CARRY-12 a continuation that already carries the heading: run exits 0" "0" "$CO_RC"
# wave-28 T50 (A-orch-74) supersedes A-T17.6's "with the heading, never touched": the merge adds the run's
# own line it lacks under the heading, after the line a person wrote there, which stays

# check never writes it, and names what run would carry
PK="$(mk_fixture carry5)"; advance_to "$PK" 8
carry_plant "$PK" "deferred: $CARRY_REC#1 S2 off \"checked\""
run_close "$PK" check
expect_eq "CARRY-14 check exits 0 and writes no continuation" "0|no" \
  "$CO_RC|$([ -e "$PK/$CONT_REL" ] && echo yes || echo no)"

# the mutation arm: a doctored copy of close-out.sh with the heading dropped from the template
CARRY_MUT="$(mktemp -d "${TMPDIR:-/tmp}/close-out-carry-mut.XXXXXX")"
mkdir -p "$CARRY_MUT/scripts"; ln -s "$REPO_ROOT/payload/scripts/lib" "$CARRY_MUT/scripts/lib"
ln -s "$REPO_ROOT/payload/scripts/card.sh" "$CARRY_MUT/scripts/card.sh"   # close-out reads the inherited deferrals through it (T43)
sed "s/printf '## Deferrals/printf '## Carried over/" "$SCRIPT" > "$CARRY_MUT/scripts/close-out.sh"
expect_eq "CARRY-mut0 the doctored copy differs from the script in exactly one line (the doctor took)" "1" \
  "$(diff "$SCRIPT" "$CARRY_MUT/scripts/close-out.sh" | /usr/bin/grep -c '^>')"
PM="$(mk_fixture carry6)"; advance_to "$PM" 8
carry_plant "$PM" "deferred: $CARRY_REC#1 S2 off \"mutant\" stated=\"A sentence.\""
( cd "$PM" && HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    bash "$CARRY_MUT/scripts/close-out.sh" "$PM/$PLAN_REL" run ) > "$SANDBOX/carry-mut.out" 2>&1
CARRY_MRC=$?
expect_eq "CARRY-mut1 the doctored run still closes and writes its continuation (the mutant runs)" "0|yes" \
  "$CARRY_MRC|$([ -s "$PM/$CONT_REL" ] && echo yes || echo no)"
rm -rf "$CARRY_MUT"


# ============================================================
# CARRY, continued — wave-28 T43 (AC-8.10, D21): what the run inherited and did not settle is carried
# ============================================================
# The run's requirements file disposes of the deferrals the newest continuation under the docs root
# carries (never the run's own; A-orch-64), under
# `## Inherited deferrals`: `adopted: <id> as REQ-<n>`, `again: <id>`, `closed: <id> <reason>`.
# Close-out writes, after this run's own lines, every inherited line deferred again and every one the
# requirements file did not dispose of, each as the old continuation wrote it, its `from=` kept. An
# adopted or a closed one is not carried. The reading is card.sh's (`card.sh inherited <plan>`), the
# one the Step 1 card listed them from.
# CARRY_PREV: hoisted to tests/close-out.prelude.sh (a later part reads it)
CARRY_PR="record/$CARRY_PREV/read-adversarial-p2.md"
CARRY_P1="deferred: $CARRY_PR#1 S2 off \"deferred again\" stated=\"Kept \\\"as is\\\".\" from=$CARRY_PREV"
CARRY_P2="deferred: $CARRY_PR#2 S3 on \"left undisposed\" stated=\"-\" from=$CARRY_PREV"
CARRY_P3="deferred: $CARRY_PR#3 S3 on \"adopted\" stated=\"-\" from=$CARRY_PREV"
CARRY_P4="deferred: $CARRY_PR#4 S2 off \"closed\" stated=\"-\" from=$CARRY_PREV"
# carry_prev <project> -> the predecessor's continuation, carrying the four lines above under
# ## Deferrals: the only continuation under the docs root until close-out writes this run's own
carry_prev() {
  local proj="$1"
  case "$proj" in "$SANDBOX"/*) : ;; *) echo "carry_prev: refusing outside the sandbox: '$proj'" >&2; return 1 ;; esac
  mkdir -p "$proj/.bionic/docs/record/$CARRY_PREV"
  printf '%s\n' "# continuation — $CARRY_PREV" "" "## Deferrals" "" "$CARRY_P1" "$CARRY_P2" "$CARRY_P3" "$CARRY_P4" \
    "" "## Resume instruction" "" "nothing" > "$proj/.bionic/docs/record/$CARRY_PREV/continuation.md"
}
# carry_req <project> <line>... -> the plan names a requirements file whose ## Inherited deferrals holds the lines
carry_req() {
  local proj="$1" plan="$1/$PLAN_REL" rel="specs/epic-fx/wave-01-fixture.requirements.md"; shift
  case "$proj" in "$SANDBOX"/*) : ;; *) echo "carry_req: refusing outside the sandbox: '$proj'" >&2; return 1 ;; esac
  mkdir -p "$proj/.bionic/docs/specs/epic-fx"
  { printf '# fixture requirements\n\n## Goal\n\nThe fixture.\n\n## Inherited deferrals\n\n'; printf '%s\n' "$@"; } \
    > "$proj/.bionic/docs/$rel"
  sed "s#^walk: exempt\$#&\\
requirements: $rel#" "$plan" > "$plan.req" && mv "$plan.req" "$plan"
  seal_fixture "$plan" "$proj/$LOG_REL"
}
PI="$(mk_fixture carry7)"; advance_to "$PI" 8
carry_prev "$PI"
carry_req "$PI" "again: $CARRY_PR#1" "adopted: $CARRY_PR#3 as REQ-1" "closed: $CARRY_PR#4 fixed in passing"
carry_plant "$PI" "deferred: $CARRY_REC#1 S2 off \"this run's own\""
run_close "$PI" run
expect_eq "CARRY-16 run exits 0 over a run that inherited four deferrals" "0" "$CO_RC"
expect_nonempty "CARRY-17 precondition: the extractor finds lines under the heading" "$(carry_section "$PI/$CONT_REL")"
expect_eq "CARRY-18 this run's own line first, then the one deferred again and the undisposed one, as written, from= kept" \
"deferred: $CARRY_REC#1 S2 off \"this run's own\" stated=\"-\" from=$CARRY_W
$CARRY_P1
$CARRY_P2" "$(carry_section "$PI/$CONT_REL")"
expect_absent "CARRY-19 …the adopted one is not carried" "\"adopted\"" "$(carry_section "$PI/$CONT_REL")"
expect_absent "CARRY-19a …nor the closed one" "\"closed\"" "$(carry_section "$PI/$CONT_REL")"

# a run whose plan names no requirements file disposed of nothing: every inherited line is carried
PJ="$(mk_fixture carry8)"; advance_to "$PJ" 8
carry_prev "$PJ"
run_close "$PJ" run
expect_eq "CARRY-20 no requirements file: run exits 0 and carries all four inherited lines, in their order" \
  "0|$CARRY_P1
$CARRY_P2
$CARRY_P3
$CARRY_P4" "$CO_RC|$(carry_section "$PJ/$CONT_REL")"

# an existing continuation without the heading gets the carried lines in the appended section too; it
# is the newest continuation under the docs root, and it is this run's own, so it is not the predecessor
PL="$(mk_fixture carry9)"; advance_to "$PL" 8
carry_prev "$PL"
carry_req "$PL" "again: $CARRY_PR#1" "adopted: $CARRY_PR#2 as REQ-1" "closed: $CARRY_PR#3 done" "closed: $CARRY_PR#4 done"
mkdir -p "$PL/${CONT_REL%/*}"
printf '# continuation — hand written\n' > "$PL/$CONT_REL"
run_close "$PL" run
expect_eq "CARRY-21 an existing continuation without the heading: the again line is appended under it" \
  "0|$CARRY_P1" "$CO_RC|$(carry_section "$PL/$CONT_REL")"

# check says what run will do (read-structure-p15 #2): over an existing continuation with no heading,
# check names the append, and run then performs it; over one with the heading, both leave it
PV="$(mk_fixture carry11)"; advance_to "$PV" 8
carry_plant "$PV" "deferred: $CARRY_REC#1 S2 off \"appended\""
mkdir -p "$PV/${CONT_REL%/*}"
printf '# continuation — hand written\n' > "$PV/$CONT_REL"
run_close "$PV" check
run_close "$PV" run
PW="$(mk_fixture carry12)"; advance_to "$PW" 8
mkdir -p "$PW/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n' > "$PW/$CONT_REL"
run_close "$PW" check
expect_absent "CARRY-22d …and names no append" "appends the ## Deferrals" "$CO_OUT"

# a ## Deferrals inside a code fence of an existing continuation is an example, not the section: the
# section is still appended (read-adversarial-p15 #4)
PF="$(mk_fixture carry13)"; advance_to "$PF" 8
carry_plant "$PF" "deferred: $CARRY_REC#1 S2 off \"behind a fence\""
mkdir -p "$PF/${CONT_REL%/*}"
printf '# continuation — hand written\n\n```\n## Deferrals\n\ndeferred: an example of the form\n```\n' > "$PF/$CONT_REL"
run_close "$PF" run
carry_section_unfenced() { awk '/^```/ { f = !f; next } f { next } /^## / { s = ($0 == "## Deferrals"); next } s && NF { print }' "$1"; }
expect_eq "CARRY-23 an existing continuation whose only ## Deferrals is fenced: run appends the section, its deferral under it" \
  "0|deferred: $CARRY_REC#1 S2 off \"behind a fence\" stated=\"-\" from=$CARRY_W" "$CO_RC|$(carry_section_unfenced "$PF/$CONT_REL")"

# a continuation written by hand BEFORE Step 9 with the heading and this run's own line under it (the
# shape steps/9.md invites) still gets what the run inherited and did not settle (wave-28 T50, AC-8.10;
# read-adversarial-p16 #1): close-out merges, each line written once, the missing ones at the end of the
# section; check names what run will add, and says "left as it stands" only when nothing would be added
CARRY_OWN="deferred: $CARRY_REC#1 S2 off \"this run's own\" stated=\"-\" from=$CARRY_W"
PX="$(mk_fixture carry14)"; advance_to "$PX" 8
carry_prev "$PX"
carry_req "$PX" "adopted: $CARRY_PR#3 as REQ-1" "closed: $CARRY_PR#4 fixed in passing"
carry_plant "$PX" "deferred: $CARRY_REC#1 S2 off \"this run's own\""
mkdir -p "$PX/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Chris decides\n\n1. none\n\n## Deferrals\n\n%s\n\n## Resume instruction\n\nNothing to resume.\n' \
  "$CARRY_OWN" > "$PX/$CONT_REL"
expect_eq "CARRY-24 precondition: the hand-written continuation holds the heading and this run's own line, and nothing carried" \
  "$CARRY_OWN" "$(carry_section "$PX/$CONT_REL")"
CARRY_CK0="$(cksum < "$PX/$CONT_REL")"
run_close "$PX" check
expect_eq "CARRY-25a …and check writes nothing" "$CARRY_CK0" "$(cksum < "$PX/$CONT_REL")"
run_close "$PX" run
expect_eq "CARRY-26 run exits 0, and the section holds this run's own line first, then the two the run inherited and did not dispose of" \
  "0|$CARRY_OWN
$CARRY_P1
$CARRY_P2" "$CO_RC|$(carry_section "$PX/$CONT_REL")"
expect_eq "CARRY-26b …the hand-written text around the section is kept, byte for byte" \
  "# continuation — hand written||## Chris decides||1. none||" "$(sed -n '1p;2p;3p;4p;5p;6p' "$PX/$CONT_REL" | tr '\n' '|')"
expect_eq "CARRY-26c …and the section is followed by a blank line and the next heading as it was" \
  "|## Resume instruction||Nothing to resume." "$(tail -4 "$PX/$CONT_REL" | tr '\n' '|' | sed 's/|$//')"
# a second close-out over what the first left adds nothing: the continuation the first run wrote is
# planted in a fresh fixture at the same step (a closed plan refuses a second run outright)
PX2="$(mk_fixture carry17)"; advance_to "$PX2" 8
carry_prev "$PX2"
carry_req "$PX2" "adopted: $CARRY_PR#3 as REQ-1" "closed: $CARRY_PR#4 fixed in passing"
carry_plant "$PX2" "deferred: $CARRY_REC#1 S2 off \"this run's own\""
mkdir -p "$PX2/${CONT_REL%/*}"; cp "$PX/$CONT_REL" "$PX2/$CONT_REL"
CARRY_CK1="$(cksum < "$PX2/$CONT_REL")"
run_close "$PX2" check
expect_absent "CARRY-27b …and names no add" "run adds" "$CO_OUT"
run_close "$PX2" run
expect_eq "CARRY-27c run exits 0 and the continuation is byte for byte what the first run left" "0|$CARRY_CK1" \
  "$CO_RC|$(cksum < "$PX2/$CONT_REL")"
expect_absent "CARRY-27d …with no line reported added" "deferred line" "$CO_OUT"

# a line already under the heading, byte for byte, is not written twice; the one missing is added alone
PY="$(mk_fixture carry15)"; advance_to "$PY" 8
carry_prev "$PY"
carry_req "$PY" "adopted: $CARRY_PR#3 as REQ-1" "closed: $CARRY_PR#4 fixed in passing"
mkdir -p "$PY/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n%s\n' "$CARRY_P2" > "$PY/$CONT_REL"
run_close "$PY" check
run_close "$PY" run
expect_eq "CARRY-28a run adds the missing one after the one that was there, and the one that was there once" \
  "0|$CARRY_P2
$CARRY_P1" "$CO_RC|$(carry_section "$PY/$CONT_REL")"

# a heading with nothing under it, then the next heading: the lines go under it, a blank line between
PZ="$(mk_fixture carry16)"; advance_to "$PZ" 8
carry_prev "$PZ"
carry_req "$PZ" "again: $CARRY_PR#1" "adopted: $CARRY_PR#2 as REQ-1" "closed: $CARRY_PR#3 done" "closed: $CARRY_PR#4 done"
mkdir -p "$PZ/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n## Resume instruction\n\nNothing.\n' > "$PZ/$CONT_REL"
run_close "$PZ" run
CARRY_VER="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_ROOT/payload/.claude-plugin/plugin.json" | head -1)"
expect_eq "CARRY-29 an empty section followed by a heading: the carried line goes under it, the layout kept (T33: and the Hand-holds section the close now merges in, after it, a blank line either side; wave-36 T2: then the Governed by section, its installed line with no load record)" \
  "0|# continuation — hand written||## Deferrals||$CARRY_P1||## Hand-holds||"'```'"|hand-holds: …|"'```'"||## Governed by||"'```'"|governed-by: installed $CARRY_VER|"'```'"||## Resume instruction||Nothing.|" \
  "$CO_RC|$(sc_strip "$PZ/$CONT_REL" | sed 's/^hand-holds: .*/hand-holds: …/' | tr '\n' '|')"

# the mutation arm: a doctored copy of close-out.sh that carries nothing it inherited
CARRY_MUT="$(mktemp -d "${TMPDIR:-/tmp}/close-out-inherit-mut.XXXXXX")"
mkdir -p "$CARRY_MUT/scripts"; ln -s "$REPO_ROOT/payload/scripts/lib" "$CARRY_MUT/scripts/lib"
ln -s "$REPO_ROOT/payload/scripts/card.sh" "$CARRY_MUT/scripts/card.sh"
sed 's/\$1 == "again" || \$1 == "open"/$1 == "none"/' "$SCRIPT" > "$CARRY_MUT/scripts/close-out.sh"
expect_eq "CARRY-mut3 the doctored copy differs from the script in exactly one line (the doctor took)" "1" \
  "$(diff "$SCRIPT" "$CARRY_MUT/scripts/close-out.sh" | /usr/bin/grep -c '^>')"
PQ="$(mk_fixture carry10)"; advance_to "$PQ" 8
carry_prev "$PQ"
carry_req "$PQ" "again: $CARRY_PR#1"
( cd "$PQ" && HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    bash "$CARRY_MUT/scripts/close-out.sh" "$PQ/$PLAN_REL" run ) > "$SANDBOX/carry-mut.out" 2>&1
CARRY_MRC=$?
rm -rf "$CARRY_MUT"

# the merge's mutation arm (T50): a doctored copy of close-out.sh whose merge writes nothing
CARRY_MUT="$(mktemp -d "${TMPDIR:-/tmp}/close-out-merge-mut.XXXXXX")"
mkdir -p "$CARRY_MUT/scripts"; ln -s "$REPO_ROOT/payload/scripts/lib" "$CARRY_MUT/scripts/lib"
ln -s "$REPO_ROOT/payload/scripts/card.sh" "$CARRY_MUT/scripts/card.sh"
sed 's/^      co_cont_write "## Deferrals" "\$missing" lines$/      :/' "$SCRIPT" > "$CARRY_MUT/scripts/close-out.sh"
expect_eq "CARRY-mut6 the doctored copy differs from the script in exactly one line (the doctor took)" "1" \
  "$(diff "$SCRIPT" "$CARRY_MUT/scripts/close-out.sh" | /usr/bin/grep -c '^>')"
PR="$(mk_fixture carry18)"; advance_to "$PR" 8
carry_prev "$PR"
carry_req "$PR" "adopted: $CARRY_PR#3 as REQ-1" "closed: $CARRY_PR#4 fixed in passing"
carry_plant "$PR" "deferred: $CARRY_REC#1 S2 off \"this run's own\""
mkdir -p "$PR/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n%s\n' "$CARRY_OWN" > "$PR/$CONT_REL"
( cd "$PR" && HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    bash "$CARRY_MUT/scripts/close-out.sh" "$PR/$PLAN_REL" run ) > "$SANDBOX/carry-mut.out" 2>&1
CARRY_MRC=$?
expect_eq "CARRY-mut7 the doctored run still closes, and the hand-written continuation keeps its own line (the mutant runs)" "0|$CARRY_OWN" \
  "$CARRY_MRC|$(carry_section "$PR/$CONT_REL")"
rm -rf "$CARRY_MUT"

finish
