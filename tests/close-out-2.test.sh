#!/bin/bash
# tests/close-out-2.test.sh — payload/scripts/close-out.sh, part 2 of 4: sections 4f through LANDINGS.
#
# THE SUITE IS FOUR PARTS (wave-39 T6; D1, D13, REQ-3 AC-3.1). One close-out.test.sh promised more than the
# suite bar, ten minutes of the gate's promise, so it runs as four suites cut at section boundaries. Its
# governing design, its sandbox, and the fixture builders and helpers every part shares are in
# tests/close-out.prelude.sh, sourced below after the framework.
#
# Usage: bash tests/close-out-2.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"
. "$(dirname "$0")/lib/roster-row.sh"   # the one roster-row builder (cross-gate S17; wave-30 T23)
. "$(dirname "$0")/close-out.prelude.sh"

# ============================================================
section "4f — REQ-1 (AC-1.1–1.4): the shipped table is found once; the ADR cell is read, not marked"
# ============================================================
# D17 (wave-24 T1). `epic_has_row`, `act_epic` and `presence_missing` each used their own idea
# of "the wave table": a file-wide grep, the FIRST `| wave |` header, any `| wave |` header. A
# planned table (`| wave | … | status |`) above or beside the shipped one made all three disagree.
# One locator now picks the table whose header's first cell is `wave` AND which has a `shipped`
# cell. The helpers below read the fixture with their OWN awk, not the script's.

# table_rows: hoisted to tests/close-out.prelude.sh (a later part reads it)
# rows_with_wave: hoisted to tests/close-out.prelude.sh (a later part reads it)

# epic_planned_first -> an epic with a planned table ABOVE the shipped one. The planned table
# carries a `| 01 |` row (this fixture's own wave number), and a headerless `## Ladder`
# table carries another; neither is the shipped table.
epic_planned_first() {
  cat <<'EPIC78'
---
canonical_sdlc_version: 14
---

# epic-fx

## SDLC State

current: 4

## Waves — planned

| wave | version | slug | brief | status |
|---|---|---|---|---|
| 01 | 0.0.2 | fixture | a planned wave | planned |
| 09 | 0.0.9 | other | another | planned |

## Ladder

| 01 | step | one |
|---|---|---|
| 01 | step | two |

## Waves — shipped

| wave | version | plan | spec / requirements | ADRs | shipped |
|---|---|---|---|---|---|
| 00 | 0.0.1 | `wave-00-seed.plan.md` | — | — | 2026-01-01 |

## Notes

Nothing here.
EPIC78
}

# §78.1 — a `| 01 |` row that is not in the shipped table is not "already listed".
T78="$(mk_fixture t78a)"; advance_to "$T78" 8
epic_planned_first > "$T78/$EPIC_REL"
expect_eq "78.0: the extractor reads the shipped table (wave 00 is one row there)" "1" \
  "$(rows_with_wave "$T78/$EPIC_REL" shipped 00)"
expect_eq "78.0b: …and the planned table (wave 01 is one row there; wave 00 none)" "1/0" \
  "$(rows_with_wave "$T78/$EPIC_REL" planned 01)/$(rows_with_wave "$T78/$EPIC_REL" planned 00)"
expect_eq "78.0c: …and wave 01 is in the shipped table zero times before the run" "0" \
  "$(rows_with_wave "$T78/$EPIC_REL" shipped 01)"
run_close "$T78" check
expect_eq "78.1a: check names an epic-row line" "yes" "$(contains "$CO_OUT" "epic-row: ")"
expect_eq "78.1b: …and does not call wave 01 already listed" "no" "$(contains "$CO_OUT" "already listed")"
run_close "$T78" run
expect_eq "78.1c: run exits 0" "0" "$CO_RC"
expect_eq "78.1d: …the shipped table holds the wave-01 row" "1" "$(rows_with_wave "$T78/$EPIC_REL" shipped 01)"
expect_eq "78.1e: …the epic-row line says appended, not already listed" "yes" \
  "$(contains "$CO_OUT" "epic-row: wave 01 appended to epic.plan.md")"

# §78.2 — the planned table sits first; the row still lands in the shipped one.
T78B="$(mk_fixture t78b)"; advance_to "$T78B" 8
epic_planned_first > "$T78B/$EPIC_REL"
PLANNED_BEFORE="$(table_rows "$T78B/$EPIC_REL" planned)"
SHIPPED_BEFORE="$(table_rows "$T78B/$EPIC_REL" shipped | wc -l | tr -d ' ')"
expect_eq "78.2.0: the planned table has two rows and the shipped one (before) has one" "2/1" \
  "$(printf '%s\n' "$PLANNED_BEFORE" | wc -l | tr -d ' ')/$SHIPPED_BEFORE"
run_close "$T78B" run
expect_eq "78.2a: run exits 0" "0" "$CO_RC"
expect_eq "78.2b: the shipped table's row count rose by exactly one" "$((SHIPPED_BEFORE + 1))" \
  "$(table_rows "$T78B/$EPIC_REL" shipped | wc -l | tr -d ' ')"
expect_eq "78.2c: …the planned table is unchanged" "$PLANNED_BEFORE" "$(table_rows "$T78B/$EPIC_REL" planned)"
expect_eq "78.2d: …and the row sits after the existing shipped row (appended, not inserted above it)" "00 01" \
  "$(table_rows "$T78B/$EPIC_REL" shipped | sed -E 's/^\|[[:space:]]*([0-9]+)[[:space:]]*\|.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
run_close "$T78B" run
expect_eq "78.2e: a second run adds no second row (reader and writer agree on the table)" "1" \
  "$(rows_with_wave "$T78B/$EPIC_REL" shipped 01)"

# §78.3 — an epic whose only `| wave |` table is the planned one has nowhere to put the row.
T78C="$(mk_fixture t78c)"; advance_to "$T78C" 8
epic_planned_first | awk '
  /^## Waves — shipped/ { skip = 1 }
  /^## Notes/ { skip = 0 }
  !skip { print }
' > "$T78C/epic.tmp" && mv "$T78C/epic.tmp" "$T78C/$EPIC_REL"
expect_eq "78.3.0: the fixture has a planned table and no shipped one" "1/0" \
  "$(rows_with_wave "$T78C/$EPIC_REL" planned 09)/$(table_rows "$T78C/$EPIC_REL" shipped | wc -l | tr -d ' ')"
PRE_C="$(presence_state "$T78C")"; PLAN_C_SHA="$(sha_of "$T78C/$PLAN_REL")"; EPIC_C_SHA="$(sha_of "$T78C/$EPIC_REL")"
# wave-38 T15 (AC-4.4): the shipped table is added beside the planned one, never refused, and the planned one keeps its rows.
run_close "$T78C" check
expect_eq "78.3a: check no longer refuses for the missing shipped table" "no" \
  "$(contains "$CO_OUT" "presence: WOULD REFUSE — no | wave | table with a shipped column")"
run_close "$T78C" run
expect_eq "78.3b: run closes rc 0" "0" "$CO_RC"
expect_eq "78.3c: …the epic plan now has a shipped table holding the wave 01 row" "1" "$(rows_with_wave "$T78C/$EPIC_REL" shipped 01)"
expect_eq "78.3d: …and the planned table keeps its rows as they were (its own wave 09 and wave 01 rows, no second 01)" "1/1" \
  "$(rows_with_wave "$T78C/$EPIC_REL" planned 09)/$(rows_with_wave "$T78C/$EPIC_REL" planned 01)"
expect_eq "78.3e: …the plan reads closed" "1" "$(run_open_rc "$T78C/$PLAN_REL")"

# ---------- §86: the ADR cell reads the spec's `adrs:` line ----------

# adr_cell: hoisted to tests/close-out.prelude.sh (a later part reads it)
# set_plan_keys: hoisted to tests/close-out.prelude.sh (a later part reads it)
# mk_spec <project> <adrs-line|-> -> writes the spec the plan names, with or without `adrs:`.
mk_spec() {
  mkdir -p "$1/.bionic/docs/specs/epic-fx"
  {
    printf -- '---\nsdlc-step: 2\n'
    [ "$2" = "-" ] || printf '%s\n' "$2"
    printf -- '---\n\n# fixture spec\n'
  } > "$1/.bionic/docs/specs/epic-fx/wave-01-fixture.spec.md"
}
SPEC_KEY="spec: specs/epic-fx/wave-01-fixture.spec.md"

T86="$(mk_fixture t86a)"; advance_to "$T86" 8
set_plan_keys "$T86" "$SPEC_KEY" "-"
mk_spec "$T86" "adrs: adrs/epic-fx/adr-040-first-thing.md · adrs/epic-fx/adr-041-second-thing.md"
run_close "$T86" run
expect_eq "86.0: run exits 0" "0" "$CO_RC"
expect_eq "86.1: the ADRs cell reads the spec's two ADRs, numbers joined by a comma" "040, 041" "$(adr_cell "$T86")"

T86B="$(mk_fixture t86b)"; advance_to "$T86B" 8
set_plan_keys "$T86B" "$SPEC_KEY" "-"
mk_spec "$T86B" "-"
/usr/bin/grep -v '^adrs:' "$T86B/$PLAN_REL" > "$T86B/plan.tmp" && mv "$T86B/plan.tmp" "$T86B/$PLAN_REL"
PRE_86B="$(presence_state "$T86B")/$(sha_of "$T86B/$PLAN_REL")/$(sha_of "$T86B/$EPIC_REL")"
run_close "$T86B" run
# WAVE-33 T8 (D8; AC-3.3): a wave with no adrs: in spec or plan used to keep `<fill: ADRs>` in the cell
# and exit 0; the epic row is now written whole, so close-out refuses, naming the field, before any act.
expect_eq "86.2a: a wave with no adrs: in spec or plan is refused (rc 2), naming the field" "2/yes" \
  "$CO_RC/$(contains "$CO_OUT" "adrs:")"
expect_eq "86.2b: …no placeholder was written: the epic table carries no wave 01 row, and nothing else changed" "0/yes" \
  "$(adr_cell "$T86B" | wc -l | tr -d ' ')/$([ "$PRE_86B" = "$(presence_state "$T86B")/$(sha_of "$T86B/$PLAN_REL")/$(sha_of "$T86B/$EPIC_REL")" ] && echo yes || echo no)"

T86C="$(mk_fixture t86c)"; advance_to "$T86C" 8
set_plan_keys "$T86C" "$SPEC_KEY" "adrs: adrs/epic-fx/adr-039-from-the-plan.md"
mk_spec "$T86C" "-"
run_close "$T86C" run
expect_eq "86.3: a spec without adrs: falls back to the plan's adrs:" "039" "$(adr_cell "$T86C")"

T86D="$(mk_fixture t86d)"; advance_to "$T86D" 8
set_plan_keys "$T86D" "-" "adrs: adrs/epic-fx/adr-038-from-the-plan.md"
run_close "$T86D" run
expect_eq "86.4: a plan whose spec file is not on disk falls back to the plan's adrs:" "038" "$(adr_cell "$T86D")"

# ============================================================
section "5 — REQ-1 (AC-1.1–1.3): a close-out spares a live neighbour's session state"
# ============================================================
#
# TWO SESSIONS SHARE ONE ROOT. A closes over its own run (session A, identified to
# close-out.sh by CLAUDE_CODE_SESSION_ID, the way the real CLI always sets it); B is a
# DIFFERENT, still-running session with its own five session-keyed files here — the shape
# AC-1.1's provenance names verbatim (`engaged-`, `roster-`, `patrol-`, `preflight-` and
# `sweeper-`). "Live" is proven the same way tests/session-sweep.test.sh:79 proves it: a
# real process (`sleep`, backgrounded) this machine's own `kill -0` will find, named in a
# session file under the sandboxed claude-home `HOME` (`$SB_HOME`) already resolves to.

TS_SID_A="closeout-suite-session-a1a1a1a1"
TS_SID_B="closeout-suite-session-b2b2b2b2"

# ---------- AC-1.1 / AC-1.2: B is live, and is spared; A and the unkeyed/dead entries
# ---------- are removed, with the tmp-wiped: line naming both counts.

P5="$(mk_fixture p5)"; advance_to "$P5" 8
plant_tmp_session "$P5" "$TS_SID_A"
plant_tmp_session "$P5" "$TS_SID_B"

sleep 3600 &
TS_B_PID=$!
TS_LIVE_PIDS="${TS_LIVE_PIDS} ${TS_B_PID}"
mkdir -p "$SB_HOME/.claude/sessions"
jq -nc --arg sid "$TS_SID_B" --argjson pid "$TS_B_PID" --arg cwd "$P5" \
  '{sessionId:$sid,pid:$pid,cwd:$cwd}' > "$SB_HOME/.claude/sessions/${TS_SID_B}.json"

# baseline 3 (mk_fixture) + A's 5 + B's 5.
expect_eq "5.0: the fixture starts with 13 entries under .bionic/tmp/ (3 baseline + 5 A + 5 B)" \
  "13" "$(tmp_entries "$P5")"

run_close_as "$TS_SID_A" "$P5" run
expect_eq "5.1: run (as A, with B live) exits 0" "0" "$CO_RC"

for c in engaged roster patrol preflight sweeper; do
  expect_eq "5.2 ($c): B's $c-keyed file survives A's close-out" "yes" \
    "$(tmp_file_exists "$P5" "$c" "$TS_SID_B")"
done
for c in engaged roster patrol preflight sweeper; do
  expect_eq "5.3 ($c): A's own $c-keyed file is removed" "no" \
    "$(tmp_file_exists "$P5" "$c" "$TS_SID_A")"
done
# the baseline's unkeyed scratch.txt and its "fixture"-sid files (dead — no live session
# named "fixture" was ever registered) go with A's own state.
expect_eq "5.4: only B's 5 spared files remain under .bionic/tmp/" "5" "$(tmp_entries "$P5")"
expect_eq "5.5: tmp-wiped: names the total scanned" "yes" \
  "$(contains "$CO_OUT" "tmp-wiped: 13 entries under")"
expect_eq "5.6: …and the removed/spared/kept counts (7 removed: A's 4 + the 3 baseline; 5 spared: B's; 1 kept: A's engaged marker, removed as the last act, wave-36 T14)" \
  "yes" "$(contains "$CO_OUT" "7 removed, 5 spared for a live neighbour session, 1 kept")"

# ---------- AC-1.3: a same-shaped neighbour whose session is DEAD is not spared — the
# ---------- sweeper's verdict (patrol_dead_sessions), not mere sparing-by-default, decides.

TS_SID_D="closeout-suite-session-d4d4d4d4"
P6="$(mk_fixture p6)"; advance_to "$P6" 8
plant_tmp_session "$P6" "$TS_SID_A"
plant_tmp_session "$P6" "$TS_SID_D"
# TS_SID_D is never registered in $SB_HOME/.claude/sessions/ — it reads dead by
# construction, the same as the baseline fixture's "fixture" sid above.

run_close_as "$TS_SID_A" "$P6" run
expect_eq "5.7: run (as A, with D dead) exits 0" "0" "$CO_RC"
for c in engaged roster patrol preflight sweeper; do
  expect_eq "5.8 ($c): D's dead $c-keyed file is removed, not spared" "no" \
    "$(tmp_file_exists "$P6" "$c" "$TS_SID_D")"
done
expect_eq "5.9: .bionic/tmp/ is empty afterwards — nothing here is live" "0" "$(tmp_entries "$P6")"

# ---------- wave-25 T15: the workspace record (`workspaces-<sid>.state`, written by
# ---------- spawn-worktree.sh create) and the gate file (`gate-<sid>.state`, written by
# ---------- hooks/permission-answer.sh) are session-keyed too. B (still live from above)
# ---------- keeps both through A's close-out; A's own and dead D's go.

P7="$(mk_fixture p7)"; advance_to "$P7" 8
for c in workspaces gate; do
  for s in "$TS_SID_A" "$TS_SID_B" "$TS_SID_D"; do
    printf '%s state for %s\n' "$c" "$s" > "$P7/.bionic/tmp/$c-$s.state"
  done
done
run_close_as "$TS_SID_A" "$P7" run
expect_eq "5.10: run (as A, with B live and D dead, workspaces and gate files only) exits 0" "0" "$CO_RC"
for c in workspaces gate; do
  expect_eq "5.11 ($c): live B's $c file survives A's close-out" "yes" \
    "$(tmp_file_exists "$P7" "$c" "$TS_SID_B")"
  expect_eq "5.12 ($c): A's own $c file is removed" "no" \
    "$(tmp_file_exists "$P7" "$c" "$TS_SID_A")"
  expect_eq "5.13 ($c): dead D's $c file is removed" "no" \
    "$(tmp_file_exists "$P7" "$c" "$TS_SID_D")"
done
expect_eq "5.14: only B's 2 spared files remain under .bionic/tmp/" "2" "$(tmp_entries "$P7")"

section "CARRY — wave-28 T17 (AC-8.7, D21): close-out writes every open deferral, with its sentence, under ## Deferrals of the continuation"
# ============================================================
# A deferral is held to its debts: the plan carries one `deferred:` line per finding the table
# defers (`session-poker.sh proof-add` writes it; `finding-stated` adds ` stated="<sentence>"`), and
# close-out carries each into the continuation, in the one form the next wave's Step 1 card reads:
#
#   deferred: <record>#<n> <S> <reach> "<title>" stated="<sentence|->" from=<wave name>
#
# in the plan's order, `-` for a deferral with no sentence, a `"` or a `\` in a sentence written
# `\"` and `\\` as the plan holds it. A `check:` line is a check owed, not a deferral, and is not
# carried. The heading is written whether or not there is anything under it, so a continuation
# that reports no deferral differs from one written before the heading existed.
# CARRY_REC: hoisted to tests/close-out.prelude.sh (a later part reads it)
# carry_plant: hoisted to tests/close-out.prelude.sh (a later part reads it)
# carry_section: hoisted to tests/close-out.prelude.sh (a later part reads it)
# CARRY_W: hoisted to tests/close-out.prelude.sh (a later part reads it)
CARRY_Q1='Said \"go\" \\ now | here'   # the sentence: Said "go" \ now | here, as the plan holds it
PC="$(mk_fixture carry1)"; advance_to "$PC" 8
carry_plant "$PC" \
  "deferred: $CARRY_REC#2 S3 on \"second, written first\" stated=\"The second sentence.\"" \
  "deferred: $CARRY_REC#1 S2 off \"first, unstated\"" \
  "check: $CARRY_REC#4 S1 off \"a settled check, not a deferral\" settled=S2:off by=record/wave-01-fixture/chk.md" \
  "deferred: $CARRY_REC#3 S2 off \"third, quoted\" stated=\"$CARRY_Q1\""
# The check: line is SETTLED (wave-28 T14, ruling A-orch-165): since T41 an open check holds the step, so
# the fixture settles it, in the form the retired finding-check wrote (settled= and by=; wave-31 T32 removed
# the verb and the hold, and an old line binds nothing), at a rating the table defers (S2 off).
expect_eq "CARRY-0 precondition: the plan carries three deferred: lines and one check: line inside its SDLC State" "3 1" \
  "$(awk '/^## /{ s = ($0 ~ /^## SDLC State/) } s && /^deferred: /{ d++ } s && /^check: /{ c++ } END { print d + 0, c + 0 }' "$PC/$PLAN_REL")"
run_close "$PC" run
expect_eq "CARRY-1 run exits 0 over a plan carrying deferred: and check: lines (the gate and the parsers admit it)" "0" "$CO_RC"
expect_eq "CARRY-2 the continuation carries the heading ## Deferrals exactly once, flush left" "1" \
  "$(/usr/bin/grep -c '^## Deferrals$' "$PC/$CONT_REL" | tr -d ' ')"
expect_nonempty "CARRY-3 precondition: the extractor finds lines under the heading" "$(carry_section "$PC/$CONT_REL")"
expect_eq "CARRY-4 …one line per open deferral, in the plan's order, in the fixed form (a check: line is not carried)" \
"deferred: $CARRY_REC#2 S3 on \"second, written first\" stated=\"The second sentence.\" from=$CARRY_W
deferred: $CARRY_REC#1 S2 off \"first, unstated\" stated=\"-\" from=$CARRY_W
deferred: $CARRY_REC#3 S2 off \"third, quoted\" stated=\"$CARRY_Q1\" from=$CARRY_W" \
  "$(carry_section "$PC/$CONT_REL")"
expect_eq "CARRY-5 …and the heading comes after the template's Next wave section and before the Resume instruction" "yes" \
  "$(awk '/^## Next wave/ { a = NR } /^## Deferrals$/ { b = NR } /^## Resume instruction/ { c = NR } END { print (a && b > a && c > b) ? "yes" : "no" }' "$PC/$CONT_REL")"
expect_eq "CARRY-6 the plan close-out closed still reads closed (run_open says 1)" "1" "$(run_open_rc "$PC/$PLAN_REL")"

# none: the heading and nothing under it
PN="$(mk_fixture carry2)"; advance_to "$PN" 8
run_close "$PN" run
expect_eq "CARRY-7 a run with no deferral exits 0" "0" "$CO_RC"
expect_eq "CARRY-8 …and writes the heading ## Deferrals once, with nothing under it" "1|0" \
  "$(/usr/bin/grep -c '^## Deferrals$' "$PN/$CONT_REL" | tr -d ' ')|$(carry_section "$PN/$CONT_REL" | wc -l | tr -d ' ')"

# an existing continuation is never overwritten: a missing heading is appended, a present one is left
PE="$(mk_fixture carry3)"; advance_to "$PE" 8
carry_plant "$PE" "deferred: $CARRY_REC#1 S2 off \"kept\" stated=\"A kept sentence.\""
mkdir -p "$PE/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Resume instruction\n\nedited by a person\n' > "$PE/$CONT_REL"
run_close "$PE" run
expect_eq "CARRY-9 a continuation that exists without the heading: run exits 0" "0" "$CO_RC"
expect_eq "CARRY-10 …its own text is kept, byte for byte, at the top" "# continuation — hand written

## Resume instruction

edited by a person" "$(head -5 "$PE/$CONT_REL")"
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
expect_eq "CARRY-13 …the line a person wrote stays, and the run's own deferral it lacked is added under it" \
  "none, said the person
deferred: $CARRY_REC#1 S2 off \"not carried over a written heading\" stated=\"A sentence.\" from=$CARRY_W" \
  "$(carry_section "$PH/$CONT_REL")"

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
expect_eq "CARRY-mut2 …and the doctored continuation has no ## Deferrals heading, so CARRY-2 and CARRY-4 go red on it" "0|0" \
  "$(/usr/bin/grep -c '^## Deferrals$' "$PM/$CONT_REL" | tr -d ' ')|$(carry_section "$PM/$CONT_REL" | wc -l | tr -d ' ')"
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
}
PI="$(mk_fixture carry7)"; advance_to "$PI" 8
carry_prev "$PI"
carry_req "$PI" "again: $CARRY_PR#1" "adopted: $CARRY_PR#3 as REQ-1" "closed: $CARRY_PR#4 fixed in passing"
carry_plant "$PI" "deferred: $CARRY_REC#1 S2 off \"this run's own\""
expect_eq "CARRY-15 precondition: the predecessor's continuation carries four lines, the plan names its requirements file, which holds three disposals" \
  "4|1|3" "$(carry_section "$PI/.bionic/docs/record/$CARRY_PREV/continuation.md" | wc -l | tr -d ' ')|$(/usr/bin/grep -c '^requirements: ' "$PI/$PLAN_REL" | tr -d ' ')|$(/usr/bin/grep -cE '^(again|adopted|closed): ' "$PI/.bionic/docs/specs/epic-fx/wave-01-fixture.requirements.md" | tr -d ' ')"
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
expect_contains "CARRY-22 check over an existing continuation without the heading names the append run will make" \
  "continuation: ${CONT_REL#.bionic/docs/} already written — run appends the ## Deferrals section" "$CO_OUT"
expect_eq "CARRY-22a …and writes nothing" "0" "$(carry_section "$PV/$CONT_REL" | wc -l | tr -d ' ')"
run_close "$PV" run
expect_contains "CARRY-22b …then run appends it, as check said" \
  "continuation: ${CONT_REL#.bionic/docs/} already written — left as it stands, with the ## Deferrals section appended" "$CO_OUT"
PW="$(mk_fixture carry12)"; advance_to "$PW" 8
mkdir -p "$PW/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n' > "$PW/$CONT_REL"
run_close "$PW" check
expect_contains "CARRY-22c over a continuation that carries the heading, check says it is left as it stands" \
  "continuation: ${CONT_REL#.bionic/docs/} already written — left as it stands" "$CO_OUT"
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
expect_eq "CARRY-23a …and the fenced example is kept as it was" "1" \
  "$(/usr/bin/grep -c '^deferred: an example of the form$' "$PF/$CONT_REL" | tr -d ' ')"

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
expect_contains "CARRY-25 check over a continuation with the heading names the 2 lines run will add, by id" \
  "continuation: ${CONT_REL#.bionic/docs/} already written — run adds 2 deferred lines under ## Deferrals: $CARRY_PR#1 $CARRY_PR#2" "$CO_OUT"
expect_eq "CARRY-25a …and check writes nothing" "$CARRY_CK0" "$(cksum < "$PX/$CONT_REL")"
run_close "$PX" run
expect_eq "CARRY-26 run exits 0, and the section holds this run's own line first, then the two the run inherited and did not dispose of" \
  "0|$CARRY_OWN
$CARRY_P1
$CARRY_P2" "$CO_RC|$(carry_section "$PX/$CONT_REL")"
expect_contains "CARRY-26a …and run says it added them" \
  "continuation: ${CONT_REL#.bionic/docs/} already written — left as it stands, with 2 deferred lines added under ## Deferrals" "$CO_OUT"
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
expect_eq "CARRY-27 precondition: the planted continuation is the first run's, with its three lines under the heading" "3" \
  "$(carry_section "$PX2/$CONT_REL" | wc -l | tr -d ' ')"
run_close "$PX2" check
expect_contains "CARRY-27a check over it names none: left as it stands" \
  "continuation: ${CONT_REL#.bionic/docs/} already written — left as it stands" "$CO_OUT"
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
expect_contains "CARRY-28 check names only the one line that is not there" \
  "run adds 1 deferred line under ## Deferrals: $CARRY_PR#1" "$CO_OUT"
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
  "0|# continuation — hand written||## Deferrals||$CARRY_P1||## Hand-holds||"'```'"|hand-holds: total=0 · by-hand=0 · stop-runs=0 · declines=0 · lifts=0 · amends=0 · holds=0 · extensions=0 · waivers=0 · regression-2=0 · second-regressions=0 · adoptions=0 · fixed=0|"'```'"||## Governed by||"'```'"|governed-by: installed $CARRY_VER|"'```'"||## Resume instruction||Nothing.|" \
  "$CO_RC|$(sc_strip "$PZ/$CONT_REL" | tr '\n' '|')"
expect_eq "CARRY-29b …and the ## Scorecard section is added once, after ## Governed by (wave-38 T15)" "1|yes" \
  "$(/usr/bin/grep -c '^## Scorecard$' "$PZ/$CONT_REL" | tr -d ' ')|$(awk '/^## Governed by$/ { a = NR } /^## Scorecard$/ { b = NR } /^## Resume instruction$/ { c = NR } END { print (a && b > a && c > b) ? "yes" : "no" }' "$PZ/$CONT_REL")"

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
expect_eq "CARRY-mut4 the doctored run still closes and writes its continuation's heading (the mutant runs)" "0|1" \
  "$CARRY_MRC|$(/usr/bin/grep -c '^## Deferrals$' "$PQ/$CONT_REL" | tr -d ' ')"
expect_eq "CARRY-mut5 …and carries neither the again line nor the undisposed ones, so CARRY-18 and CARRY-20 go red on it" "0" \
  "$(carry_section "$PQ/$CONT_REL" | wc -l | tr -d ' ')"
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
expect_eq "CARRY-mut8 …and adds nothing carried, so CARRY-26 and CARRY-28a go red on it" "1" \
  "$(carry_section "$PR/$CONT_REL" | wc -l | tr -d ' ')"
rm -rf "$CARRY_MUT"


# ============================================================
section "LANDINGS — wave-28 T14 (AC-4.5, D18): close-out's continuation prints the run's numbers with each landed row"
# ============================================================
# A continuation close-out writes from its template carries `## Landings`: the report's line and one
# line per landed row (`session-poker.sh landing-report --rows <plan>`), read from the run's landing
# record and the gate's requests and only printed. The plan is NAMED to the report, never resolved
# through the session: act 3 has wiped the session's binding before the continuation is written.
# FIXTURE FIDELITY: the events are PLANTED in the Interfaces table's `line/v1` shape, which
# lib/line.sh writes; the gate store is the sandbox's own, empty. Each row line carries the admission split, wait,
# prove and rework, and the width (wave-38 T7, AC-6.4; wave-37 T9, AC-11.3): the report reads them from this record
# alone, the verdict's `admitted=` (lib/line.sh, 1.21.0) the start of its admitted run, and the block fences the rows whole.
# LAND_GATE: hoisted to tests/close-out.prelude.sh (a later part reads it)
# LAND_C: hoisted to tests/close-out.prelude.sh (a later part reads it)
# land_section <continuation> -> what stands under `## Landings`, up to the next `## `, fences and blank
# lines dropped; nothing when there is no such heading.
land_section() { awk '/^## / { s = ($0 == "## Landings"); next } s && NF && !/^```/ { print }' "$1"; }
land_plant() {  # <project> -> a ready and a queue landing for T1, a git landing for T2
  local rec="$1/.bionic/docs/record/wave-01-fixture/landing-proofs.log"
  case "$1" in "$SANDBOX"/*) : ;; *) echo "land_plant: refusing outside the sandbox: '$1'" >&2; return 1 ;; esac
  mkdir -p "${rec%/*}"
  printf 'line/v1|ev=ready|row=T1|name=w-T1|commit=%s|branch=wt/01-T1|tree=%s/.worktrees/01-T1|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T10:00:00Z\n' "$LAND_C" "$1" >> "$rec"
  printf 'line/v1|ev=candidate|row=T1|base=%s|commit=%s|tree=%s/.bionic/tmp/landing/1|at=2026-10-06T10:02:00Z\n' "$LAND_C" "$LAND_C" "$1" >> "$rec"
  printf 'line/v1|ev=verdict|row=T1|commit=%s|suite=a.test.sh|result=green|log=/rec/a.log|admitted=1791281100|width=2|at=2026-10-06T10:20:00Z\n' "$LAND_C" >> "$rec"
  printf 'line/v1|ev=published|row=T1|commit=%s|kind=queue|by=-|why=-|at=2026-10-06T10:30:00Z\n' "$LAND_C" >> "$rec"
  printf 'line/v1|ev=published|row=T2|commit=%s|kind=git|by=-|why=-|at=2026-10-06T10:40:00Z\n' "$LAND_C" >> "$rec"
}
PLD="$(mk_fixture landings1)"; advance_to "$PLD" 8
land_plant "$PLD"
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PLD" run
expect_eq "LAND-1 run exits 0 over a run whose landing record holds two landings" "0" "$CO_RC"
expect_eq "LAND-2 the continuation carries the heading ## Landings exactly once" "1" \
  "$(/usr/bin/grep -c '^## Landings$' "$PLD/$CONT_REL" | tr -d ' ')"
expect_nonempty "LAND-3 precondition: the extractor finds lines under the heading" "$(land_section "$PLD/$CONT_REL")"
expect_eq "LAND-4 …the report's line, then a line per landed row, as landing-report --rows prints them" \
"landings: queue=1 hand=0 git=1 · ready-to-landed median=30.0m p75=30.0m max=30.0m · runs: green=1 red=0 none=0 discarded=0 red-then-green=0 run=0 reused=0 absent=0 · waited median=900s · killed=0
T1 queue ready=2026-10-06T10:00:00Z landed=2026-10-06T10:30:00Z minutes=30.0 runs=1 waited=900s wait=15.0 prove=15.0 rework=0.0 width=2
T2 git ready=- landed=2026-10-06T10:40:00Z minutes=- runs=0 waited=- wait=- prove=- rework=- width=-" \
  "$(land_section "$PLD/$CONT_REL")"
expect_eq "LAND-5 …and the heading sits after ## Deferrals and before the Resume instruction" "yes" \
  "$(awk '/^## Deferrals$/ { a = NR } /^## Landings$/ { b = NR } /^## Resume instruction/ { c = NR } END { print (a && b > a && c > b) ? "yes" : "no" }' "$PLD/$CONT_REL")"
expect_eq "LAND-6 …and the Deferrals section above it still ends at its own heading (nothing of the report under it)" "0" \
  "$(awk '/^## / { s = ($0 == "## Deferrals"); next } s && /^landings: /' "$PLD/$CONT_REL" | wc -l | tr -d ' ')"
# no record: the line with zeros
PLZ="$(mk_fixture landings2)"; advance_to "$PLZ" 8
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PLZ" run
expect_eq "LAND-7 a run with no landing record exits 0 and its continuation carries the line with zeros, and no row" \
  "0|landings: queue=0 hand=0 git=0 · ready-to-landed median=0.0m p75=0.0m max=0.0m · runs: green=0 red=0 none=0 discarded=0 red-then-green=0 run=0 reused=0 absent=0 · waited median=0s · killed=0" \
  "$CO_RC|$(land_section "$PLZ/$CONT_REL")"
# an existing continuation is never overwritten: no section is added to it
PLE="$(mk_fixture landings3)"; advance_to "$PLE" 8
land_plant "$PLE"
mkdir -p "$PLE/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n## Resume instruction\n\nedited by a person\n' > "$PLE/$CONT_REL"
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PLE" run
expect_eq "LAND-8 a continuation written before close-out keeps its bytes: run exits 0 and adds no ## Landings" "0|0" \
  "$CO_RC|$(/usr/bin/grep -c '^## Landings$' "$PLE/$CONT_REL" | tr -d ' ')"
expect_eq "LAND-8b …control: the same continuation keeps its own line" "1" "$(/usr/bin/grep -c '^edited by a person$' "$PLE/$CONT_REL" | tr -d ' ')"
# the mutation arm: a doctored copy whose template drops the section
LAND_MUT="$(mktemp -d "${TMPDIR:-/tmp}/close-out-land-mut.XXXXXX")"
mkdir -p "$LAND_MUT/scripts"; ln -s "$REPO_ROOT/payload/scripts/lib" "$LAND_MUT/scripts/lib"
ln -s "$REPO_ROOT/payload/scripts/card.sh" "$LAND_MUT/scripts/card.sh"
sed 's/^\$(co_landings_section)$//' "$SCRIPT" > "$LAND_MUT/scripts/close-out.sh"
expect_eq "LAND-mut0 the doctored copy differs from the script in exactly one line (the doctor took)" "1" \
  "$(diff "$SCRIPT" "$LAND_MUT/scripts/close-out.sh" | /usr/bin/grep -c '^>')"
PLM="$(mk_fixture landings4)"; advance_to "$PLM" 8
land_plant "$PLM"
( cd "$PLM" && HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    BIONIC_GATE_DIR="$LAND_GATE" bash "$LAND_MUT/scripts/close-out.sh" "$PLM/$PLAN_REL" run ) > "$SANDBOX/land-mut.out" 2>&1
LAND_MRC=$?
expect_eq "LAND-mut1 the doctored run still closes and writes its continuation (the mutant runs)" "0|1" \
  "$LAND_MRC|$(/usr/bin/grep -c '^## Deferrals$' "$PLM/$CONT_REL" | tr -d ' ')"
expect_eq "LAND-mut2 …and carries no ## Landings, so LAND-2 and LAND-4 go red on it" "0" \
  "$(/usr/bin/grep -c '^## Landings$' "$PLM/$CONT_REL" | tr -d ' ')"
rm -rf "$LAND_MUT"

# ---- wave-28 T62 (AC-4.6, D18): a run open across the upgrade holds `landed:` lines and no line/v1 event ----
# The report says so (`landings: unmeasured`) where it once printed zeros; the continuation's section is
# that one line, with no fence and no row.
PLU="$(mk_fixture landings5)"; advance_to "$PLU" 8
LAND_UREC="$PLU/.bionic/docs/record/wave-01-fixture/landing-proofs.log"
mkdir -p "${LAND_UREC%/*}"
printf 'landed: row=T1 branch=wt/01-T1 head=%s merge=%s at=2026-10-06T10:10:00Z\nstamp/v1|head=%s|dirty=0|rc=0|at=2026-10-06T10:09:00Z|suites=a.test.sh\n' \
  "$LAND_C" "$LAND_C" "$LAND_C" > "$LAND_UREC"
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PLU" run
expect_eq "LAND-9 a record of landed lines and no line/v1 event: run exits 0 and ## Landings is the one unmeasured line" \
  "0|landings: unmeasured — the landing record holds no line/v1 events" "$CO_RC|$(land_section "$PLU/$CONT_REL")"
expect_eq "LAND-9b …under no fence, and with no zeros anywhere in the continuation" "0|0" \
  "$(awk '/^## / { s = ($0 == "## Landings"); next } s && /^```/' "$PLU/$CONT_REL" | wc -l | tr -d ' ')|$(/usr/bin/grep -c '^landings: queue=0 ' "$PLU/$CONT_REL" | tr -d ' ')"
# the mutation arm: the unfenced branch never taken, so the section is fenced again
LAND_UMUT="$(mktemp -d "${TMPDIR:-/tmp}/close-out-unm-mut.XXXXXX")"
mkdir -p "$LAND_UMUT/scripts"; ln -s "$REPO_ROOT/payload/scripts/lib" "$LAND_UMUT/scripts/lib"
ln -s "$REPO_ROOT/payload/scripts/card.sh" "$LAND_UMUT/scripts/card.sh"
sed 's/^      "landings: unmeasured "\*)/      "landings: never "*)/' "$SCRIPT" > "$LAND_UMUT/scripts/close-out.sh"
expect_eq "LAND-mut3 the doctored copy differs from the script in exactly one line (the doctor took)" "1" \
  "$(diff "$SCRIPT" "$LAND_UMUT/scripts/close-out.sh" | /usr/bin/grep -c '^>')"
PLV="$(mk_fixture landings6)"; advance_to "$PLV" 8
mkdir -p "$PLV/.bionic/docs/record/wave-01-fixture"; cp "$LAND_UREC" "$PLV/.bionic/docs/record/wave-01-fixture/landing-proofs.log"
( cd "$PLV" && HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$REPO_ROOT/payload" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    BIONIC_GATE_DIR="$LAND_GATE" bash "$LAND_UMUT/scripts/close-out.sh" "$PLV/$PLAN_REL" run ) > "$SANDBOX/land-umut.out" 2>&1
LAND_UMRC=$?
expect_eq "LAND-mut4 the doctored run still closes and fences the line (two fence lines), which LAND-9b forbids" "0|2" \
  "$LAND_UMRC|$(awk '/^## / { s = ($0 == "## Landings"); next } s && /^```/' "$PLV/$CONT_REL" | wc -l | tr -d ' ')"
rm -rf "$LAND_UMUT"

finish
