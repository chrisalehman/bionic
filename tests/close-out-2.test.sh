#!/bin/bash
# tests/close-out-2.test.sh — payload/scripts/close-out.sh, part 2 of 6: sections 4f, §5, LANDINGS and CLOSED.
#
# THE SUITE IS SIX PARTS: one close-out.test.sh outran the suite bar, so it runs as parts cut at section boundaries,
# and the two longest were cut again by the seconds of one run: CARRY left this part for close-out-5.
# Its design, sandbox, fixture builders and helpers are in tests/close-out.prelude.sh, sourced below after the framework.
#
# Usage: bash tests/close-out-2.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"
. "$(dirname "$0")/lib/roster-row.sh"   # the one roster-row builder
. "$(dirname "$0")/close-out.prelude.sh"

# ============================================================
section "4f — REQ-1 (AC-1.1–1.4): the close prints the epic's row and writes no epic plan; the ADR cell is read, not marked"
# ============================================================
# The close prints the wave's row for the orchestrator's edit and writes no plan: each fixture epic plan's checksum is the
# same after a close as before it, and the row is read from the output. A planned table (`| wave | … | status |`) above or
# beside the shipped one is the fixture's trap; the helpers read the fixture with their OWN awk, not the script's.

# table_rows: hoisted to tests/close-out.prelude.sh (a later part reads it)
# rows_with_wave: hoisted to tests/close-out.prelude.sh (a later part reads it)
# printed_row -> the row the last close printed for the epic plan; printed_adr_cell -> its ADRs cell, trimmed.
printed_row() { printf '%s\n' "$CO_OUT" | sed -n 's/^epic-row: //p'; }
printed_adr_cell() { printed_row | awk -F'|' '{ c = $6; gsub(/^[ \t]+|[ \t]+$/, "", c); print c }'; }

# epic_planned_first -> an epic with a planned table ABOVE the shipped one; the planned table carries a `| 01 |` row (this
# fixture's own wave number), which is no row of the shipped table.
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

## Waves — shipped

| wave | version | plan | spec / requirements | ADRs | shipped |
|---|---|---|---|---|---|
| 00 | 0.0.1 | `wave-00-seed.plan.md` | — | — | 2026-01-01 |
EPIC78
}

# row_whole <project> -> yes when the last close printed the row whole: the cells of a wave with no release and no ADR,
# then a shipped cell of the close's own date and the integration head (the date is read apart: it is the close's second)
row_whole() {
  case "$(printed_row)" in '| 01 | — | `wave-01-fixture.plan.md` | `wave-01-fixture.spec.md`, `.requirements.md` | — | '*", main @ $(fixture_git "$1" rev-parse --short main) |") echo yes ;; *) echo no ;; esac
}

# §78.1 — a `| 01 |` row in the planned table only is no reason to print nothing; neither table is written, and a second close prints no second row.
T78="$(mk_fixture t78a)"; advance_to "$T78" 8
epic_planned_first > "$T78/$EPIC_REL"
EPIC_SUM78="$(sha_of "$T78/$EPIC_REL")"
expect_eq "78.0: the extractor reads both tables: wave 00 is one shipped row and no planned one, wave 01 one planned row and no shipped one" "1/0/1/0" \
  "$(rows_with_wave "$T78/$EPIC_REL" shipped 00)/$(rows_with_wave "$T78/$EPIC_REL" planned 00)/$(rows_with_wave "$T78/$EPIC_REL" planned 01)/$(rows_with_wave "$T78/$EPIC_REL" shipped 01)"
run_close "$T78" check
expect_eq "78.1a: check prints the row, and does not call wave 01 already listed" "yes/no" \
  "$(contains "$CO_OUT" "epic-row: | 01 | ")/$(contains "$CO_OUT" "already listed")"
run_close "$T78" run
expect_eq "78.1d: run exits 0, the epic plan's checksum is what it was, and the shipped table holds no wave-01 row" "0/$EPIC_SUM78/0" \
  "$CO_RC/$(sha_of "$T78/$EPIC_REL")/$(rows_with_wave "$T78/$EPIC_REL" shipped 01)"
expect_eq "78.1e: …the output holds the row whole, once, and one line saying the edit is the orchestrator's" "yes/1/1" \
  "$(row_whole "$T78")/$(printed_row | wc -l | tr -d ' ')/$(printf '%s\n' "$CO_OUT" | /usr/bin/grep -c '^epic-edit: .*writes no plan')"
run_close "$T78" run
expect_eq "78.2e: a second run prints no second row and leaves the epic plan as it was" "0/$EPIC_SUM78" "$(printed_row | wc -l | tr -d ' ')/$(sha_of "$T78/$EPIC_REL")"

# §78.3 — an epic whose only `| wave |` table is the planned one: the close prints the table's header beside the row.
T78C="$(mk_fixture t78c)"; advance_to "$T78C" 8
epic_planned_first | awk '/^## Waves — shipped/ { exit } { print }' > "$T78C/$EPIC_REL"
EPIC_C_SHA="$(sha_of "$T78C/$EPIC_REL")"
run_close "$T78C" run
expect_eq "78.3b: run closes rc 0, the plan reads closed, and the epic plan is what it was" "0|1|$EPIC_C_SHA" \
  "$CO_RC|$(run_open_rc "$T78C/$PLAN_REL")|$(sha_of "$T78C/$EPIC_REL")"
expect_eq "78.3e: …the output holds the row, and the header of the table to add it to" "yes/yes" \
  "$(row_whole "$T78C")/$(contains "$CO_OUT" "| wave | version | plan | spec / requirements | ADRs | shipped |")"

# §78.4 — a wave closes under an epic already at 15, which the act brought forward and no rewrite of its header did.
T78D="$(mk_fixture t78d)"; advance_to "$T78D" 8
bash "$REPO_ROOT/payload/scripts/bring-forward.sh" "$T78D/$EPIC_REL" >/dev/null 2>&1; ACT_RC=$?
EPIC_SUM78D="$(sha_of "$T78D/$EPIC_REL")"
run_close "$T78D" run
expect_eq "78.4a: the act carries the epic (rc 0); the close under it exits 0, prints the wave's row once, leaves the epic plan as it was, and the epic's page reads 15" "0|0|1|$EPIC_SUM78D|15" \
  "$ACT_RC|$CO_RC|$(printed_row | wc -l | tr -d ' ')|$(sha_of "$T78D/$EPIC_REL")|$(sed -n 's/^canonical_sdlc_version: //p' "$T78D/$EPIC_REL")"
EPIC_STEP="$(bash "$REPO_ROOT/payload/scripts/reader.sh" "$T78D/$EPIC_REL" step 2>&1)"
expect_eq "78.4b: …and the reader reads the epic open at the step it held" "yes|yes" "$(contains "$EPIC_STEP" "n=4")|$(contains "$EPIC_STEP" "state=open")"

# ---------- §86: the ADR cell reads the spec's `adrs:` line ----------

# adr_cell: hoisted to tests/close-out.prelude.sh (a later part reads it); this part reads the cell from the printed row
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
expect_eq "86.1: the ADRs cell reads the spec's two ADRs, numbers joined by a comma" "040, 041" "$(printed_adr_cell)"

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
  "$(printed_row | wc -l | tr -d ' ')/$([ "$PRE_86B" = "$(presence_state "$T86B")/$(sha_of "$T86B/$PLAN_REL")/$(sha_of "$T86B/$EPIC_REL")" ] && echo yes || echo no)"

T86C="$(mk_fixture t86c)"; advance_to "$T86C" 8
set_plan_keys "$T86C" "$SPEC_KEY" "adrs: adrs/epic-fx/adr-039-from-the-plan.md"
mk_spec "$T86C" "-"
run_close "$T86C" run
expect_eq "86.3: a spec without adrs: falls back to the plan's adrs:" "039" "$(printed_adr_cell)"

T86D="$(mk_fixture t86d)"; advance_to "$T86D" 8
set_plan_keys "$T86D" "-" "adrs: adrs/epic-fx/adr-038-from-the-plan.md"
run_close "$T86D" run
expect_eq "86.4: a plan whose spec file is not on disk falls back to the plan's adrs:" "038" "$(printed_adr_cell)"

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
expect_nonempty "LAND-3 precondition: the extractor finds lines under the heading" "$(land_section "$PLD/$CONT_REL")"
expect_eq "LAND-5 …and the heading sits after ## Deferrals and before the Resume instruction" "yes" \
  "$(awk '/^## Deferrals$/ { a = NR } /^## Landings$/ { b = NR } /^## Resume instruction/ { c = NR } END { print (a && b > a && c > b) ? "yes" : "no" }' "$PLD/$CONT_REL")"
# no record, and the plan lands T1 and T2: landings stand that no line measured, so the unmeasured line
PLZ="$(mk_fixture landings2)"; advance_to "$PLZ" 8
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PLZ" run
expect_eq "LAND-7 a run whose plan lands rows and holds no landing record exits 0, its continuation the unmeasured line and no row" \
  "0|landings: unmeasured — the landing record holds no line/v1 events" \
  "$CO_RC|$(land_section "$PLZ/$CONT_REL")"
# an existing continuation is never overwritten: no section is added to it
PLE="$(mk_fixture landings3)"; advance_to "$PLE" 8
land_plant "$PLE"
mkdir -p "$PLE/${CONT_REL%/*}"
printf '# continuation — hand written\n\n## Deferrals\n\n## Resume instruction\n\nedited by a person\n' > "$PLE/$CONT_REL"
BIONIC_GATE_DIR="$LAND_GATE" run_close "$PLE" run
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
rm -rf "$LAND_UMUT"

# ============================================================
section "CLOSED — the closed form says merged into after a merge, and to be pulled into only while a pull request is owed"
# ============================================================
# `co_into` told how the working branch reaches the integration branch from `co_pr_owed`, which read "not an ancestor" as
# "owed" even when the branch was gone: a pull request merged and its branch deleted left the closed form saying
# "to be pulled into" for good. The branch line is read by `closed-form`, the door the handoff verb prints.
# FIXTURE FIDELITY: mk_fixture's wave-scale run, its wave branch merged into main as close-out leaves it; and
# mk_task_pr_fixture's task-scale run, whose pull request is owed until its branch is merged into main by the real git
# merge, then deleted by the real git branch -d. closed-form is the real close-out.sh verb, read-only.
# fails-when: a merged branch is called "to be pulled", or an unmerged pull-request branch is called "merged".
cf_branch() {  # <project> -> the branch: line close-out's closed-form prints
  run_close "$1" closed-form
  printf '%s\n' "$CO_OUT" | /usr/bin/grep -m1 '^branch: '
}
PCW="$(mk_fixture closed-wave)"
expect_eq "CLOSED-0 precondition: the wave branch is merged into main" "yes" \
  "$(git -C "$PCW" merge-base --is-ancestor wave/01-fixture main && echo yes || echo no)"
expect_eq "CLOSED-1 a merged wave: the closed form says merged into main" "branch: wave/01-fixture merged into main." "$(cf_branch "$PCW")"
PCP="$(mk_task_pr_fixture closed-pr "fix/x")"
expect_eq "CLOSED-2 precondition: the pull-request branch is not merged" "no" \
  "$(git -C "$PCP" merge-base --is-ancestor fix/x main && echo yes || echo no)"
git -C "$PCP" merge -q --no-edit fix/x >/dev/null 2>&1
expect_eq "CLOSED-4 precondition: the real merge put the branch into main" "yes" \
  "$(git -C "$PCP" merge-base --is-ancestor fix/x main && echo yes || echo no)"
expect_eq "CLOSED-5 after the pull request merges, the closed form says merged into main" "branch: fix/x merged into main." "$(cf_branch "$PCP")"
PCP_WT="$(git -C "$PCP" worktree list --porcelain | awk '/^worktree /{ w = substr($0, 10) } $0 == "branch refs/heads/fix/x" { print w }')"
[ -z "$PCP_WT" ] || git -C "$PCP_WT" checkout -q --detach
git -C "$PCP" branch -q -d fix/x
expect_eq "CLOSED-6 precondition: the merged branch is deleted" "no" "$(git -C "$PCP" rev-parse --verify -q fix/x >/dev/null && echo yes || echo no)"
expect_eq "CLOSED-7 …and a deleted merged branch still says merged into main, never to be pulled" "branch: fix/x merged into main." "$(cf_branch "$PCP")"

finish
