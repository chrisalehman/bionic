#!/bin/bash
# tests/units.test.sh — payload/scripts/lib/units.sh: THE ONE READER OF `## Tasks`
#
# WHAT IT OWNS. The contract three callers bind to after T8 — the evidence gate's ledger
# checks and its prototype check, the tick's FILL, and the governing-skill Step-3 wall — so
# that none of them carries a parser of its own. The questions, one per section:
#
#   §1 units_rows <plan>          the thirteen fields, in the FIXED order, whatever order the table's columns are written in;
#                                 the `worktree` (11) and `base` (12) cells are OPTIONAL, absent reading empty, `base` a commit id
#   §2 header names               reversed columns give identical output
#   §3 the ## Tasks section       is read, and nothing else
#   §4 units_ready <plan> <step>  which rows at that step may be dispatched now
#   §6 units_validate <plan>      one line per broken invariant, naming the id and the rule
#   §7 units_validate <plan>      a missing column is a violation of the table, not of a row
#   §9 a markdown-escaped pipe    in a cell
#   §ORDER   build, regression, review, release: units_validate refuses any other order naming the rows; units_order reads it
#   §AFTER-PUBLISH  after the release is the record's publish order: a step-4 fix row published past the release
#            is read as a piece; the record's order reversed refuses; no record falls back to the plan's order
#   §JUDGE   covered at the last green whole run's head; past it each commit owes its row's suites, never a second whole run
#   §WALK    the regression walk excuses a real release merge whose check passed, as the judge's cover reads it
#   §SECOND  regression-run at a head past the plan's whole run refuses a second whole run in one line with nothing run,
#            and at the head the whole run read it does not refuse
#   §DEBT    a review-born row inside fix-policy: is exempt from fix-cap:, a promoted or carried one counts;
#            task-add's cap refusal, its fourth-fix refusal and its count line each go red when removed
#   §ASK     a row edited by hand reads as lib/plan-read.sh's row reads it; a floor row whose review proof stands at
#            an older head is ready only when the judge reads the reviews covered; the fix policy is the header's
#   §LIVE    a launch the run's log holds reads active under its name and is not ready; a dry copy reads its plan's run
#   §BORN    a row's born event, one per row, is read by the fix-cap's count, the findings and the marks; a marker in
#            the page's text is none
#   §BACK    a launch taken back by one function: a cancel for a launch in the log
#   §TREE    a row's tree and base read from the newest tree event in the log
#   §LEDGER  a landed row with no line asked of the reader: admitted when it answers landed
#   §DROP    a drop in the run's log reads dropped to the reader and the fill at 15, launched or not; a wait on it is met
#   §UNTIMED a dispatch or a tree line with no instant: the reader's dispatched and tree, never the fill's launch or tree
#   §NAMED   a task at 15 names in its deps the approval it waits on; the fill takes every wait from plan_read_waits
#   §ORDER-15  the order and its post-release exception hold at 15, a row's state the run's, the exception's waits the reader's
#   §DEPS-15   a row at 15 waits by its deps and kind alone: no step hold; a questions tag judged
#
# WHY HEADER-KEYED IS THE WHOLE POINT is lib/units.sh's own header. §2 is its assertion: the same rows with every
# column REVERSED must produce a byte-identical TSV.
#
# FIXTURE PROVENANCE — NOT HAND-TYPED (fixture fidelity). The table in `tasks_table` below
# was spliced verbatim out of this wave's own live plan,
# `.bionic/docs/plans/epic-23-bionic-tech-debt/wave-11-lean-spine.plan.md`, at the `## Tasks`
# heading, at commit 1f48673 — header, separator and all 22 data rows, in table order — and
# then cut to the nine cells of a page at 15: each row's agent and status cells are gone, since
# a row's state and its agent are events in the run's log, and its artifact cell reads `—`. The
# plan tree is gitignored and absent from a worktree, so the specimen has to live in the
# suite; copying it by hand is how a fixture comes to test its own typing instead of the
# reader. Every other fixture here is built FROM that one by a name-blind transform (§2
# reverses cell order; §3 wraps it in decoys) or is a small purpose-built table (§4).
#
# THE REVERSAL IS NAME-BLIND, DELIBERATELY (§2). A permuter that re-ordered columns BY NAME would be a second
# implementation of the thing under test, and a shared misreading of a header cell would cancel out and show green.
# Reversing the cells of every row — header, separator and data alike — cannot know what any column is called, so
# the two sides of the §2 comparison have no common machinery at all.
#
# HERMETIC. Every fixture is a file under one mktemp sandbox; nothing reads the repository's own plans, no hook runs,
# and the library is sourced in a CHILD shell per call so no row is answered by a function an earlier row left defined.
# §WALK alone is live tier: it reads this repository's own release merges, read-only, and skips one its history lacks.
#
# Usage: bash tests/units.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
LIB="$REPO_ROOT/payload/scripts/lib/units.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/units-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

# call <fn> <args...> — the library in a child shell. Prints the function's stdout; its exit status is left in CALL_RC.
# A missing or unparsable library yields empty output and a non-zero CALL_RC, which is what makes the RED run of this
# suite red for the right reason rather than killing it.
CALL_RC=0
call() {
  local fn="$1" out; shift
  out="$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; fn="$2"; shift 2; "$fn" "$@"' \
         _ "$LIB" "$fn" "$@" 2>"$SANDBOX/.err")"
  CALL_RC=$?
  printf '%s' "$out"
}

# call_rc <fn> <args...> — the status alone, for the rows that are about exit codes.
call_rc() { call "$@" >/dev/null; printf '%s' "$CALL_RC"; }

# nlines <string> — 0 for the empty string, which `wc -l` cannot say and `grep -c` will not.
nlines() { [ -z "$1" ] && { printf '0'; return; }; printf '%s\n' "$1" | wc -l | tr -d ' '; }

setup_section "0s — the fixtures"

# THE SPECIMEN, the live plan's rows cut to nine cells (see FIXTURE PROVENANCE above).
cat > "$SANDBOX/tasks-table.md" <<'TASKS_TABLE_EOF'
| id | step | kind | task | deps | size | serves | Files | artifact |
|---|---|---|---|---|---|---|---|---|
| T1 | 3 | doc | Plan, Tasks and matrix written; Step-3 card approved | — | 30m | all | plan | — |
| T2 | 4 | build | 1d: `disable-model-invocation: true` on the five command templates; re-render; frontmatter pin | T1 | 15m | REQ-1d | agents-src/templates/commands/*.tmpl, payload/commands/*.md, payload/integrity/rendered.sha256, tests/docs-pins.test.sh | — |
| T3 | 4 | build | 1c-a: survival renders once to payload/context/survival.md; auditor mandate moved the same way; role templates ≤5 KB with a one-line pointer; §5 writer rules as defaults; PIPESTATUS fixed; six pins re-pointed | T1 | 60m | REQ-1c | agents-src/blocks/survival.md, agents-src/templates/*.md.tmpl, agents-src/render.sh, agents/*.md, payload/context/survival.md, tests/docs-pins.test.sh, tests/render.test.sh, payload/integrity/rendered.sha256 | — |
| T4 | 4 | build | 1c-b: SubagentStart hook injects survival for bionic:* agents, self-attributed first line; stdout-equals-file pin | T3 | 45m | REQ-1c | hooks/execution-recorder.sh, tests/execution-recorder.test.sh | — |
| T5 | 4 | build | 1b: core + steps/0–9 + dispatch.md from the template; render.sh unit rows; 168 pins re-pointed, 4 structural ones rewritten; prune to caps; session-start pointer line | T1 | 120m | REQ-1b | agents-src/templates/skills/canonical-sdlc/, agents-src/render.sh, skills/canonical-sdlc/, tests/docs-pins.test.sh, tests/render.test.sh, payload/integrity/rendered.sha256, hooks/session-start.sh | — |
| T6 | 4 | build | 1a: three prose surfaces re-pointed to record/ paths; evidence-gate fixtures (path-cited ≤40 KB passes; empty evidence value fails) | T3, T5 | 45m | REQ-1a | agents-src/blocks/critic-template.md, agents-src/templates/senior-implementor.md.tmpl, agents-src/templates/skills/canonical-sdlc/steps/, tests/canonical-sdlc-evidence-gate.test.sh | — |
| T7 | 4 | build | 1e-a: lib/units.sh (units_rows, units_ready, units_validate) TDD from tests/units.test.sh; domain dictionary entry | T1 | 60m | REQ-1e | payload/scripts/lib/units.sh, tests/units.test.sh, design/domain-dictionary.md | — |
| T8 | 4 | build | 1e-b: callers onto units.sh (gate ledger checks + prototype check, tick FILL, governing-skill Step-3 wall); the retired word becomes task; fixtures migrated; differential vs old parsers on the specimen plan | T7 | 120m | REQ-1e | hooks/canonical-sdlc-evidence-gate.sh, hooks/session-poker.sh, hooks/canonical-sdlc-governing-skill.sh, hooks/dispatch-preflight.sh, tests/canonical-sdlc-evidence-gate.test.sh, tests/session-poker.test.sh, tests/canonical-sdlc-governing-skill.test.sh, tests/docs-pins.test.sh, agents-src/ | — |
| T9 | 4 | build | 1f-a: delete hooks/stop-check.sh and every reference; remove the seven dead functions | T8 | 30m | REQ-1f | hooks/stop-check.sh, payload/scripts/lib/, tests/ | — |
| T10 | 4 | build | 1f-b: lib/context.sh with bionic_context; fifteen hooks call it; no-inline-sequence pin | T9 | 90m | REQ-1f | payload/scripts/lib/context.sh, hooks/*.sh, tests/cross-gate-agreement.test.sh | — |
| T11 | 4 | build | 1f-c: loader block ≤95 lines in loader.sh's heredoc and all 21 hooks; §N.1 pin and mutation arm green | T10 | 60m | REQ-1f | payload/scripts/lib/loader.sh, hooks/*.sh, tests/cross-gate-agreement.test.sh | — |
| T12 | 4 | build | 1f-d: context-spend suite first (RED); lib/stop.sh four functions; hooks/stop.sh on Stop + SubagentStop with fold; differential vs the four originals; hooks.json ≤12 command objects | T11 | 150m | REQ-1f | payload/scripts/lib/stop.sh, hooks/stop.sh, hooks/hooks.json, hooks/context-spend.sh, hooks/landing-gate.sh, hooks/patrol-duties-gate.sh, hooks/patrol-revive.sh, tests/stop.test.sh, tests/context-spend.test.sh, tests/ | — |
| T13 | 5 | verify | Walk: an agent that has not read the ACs drives the candidate by plugin-dir in a throwaway project and narrates; record/wave-11-lean-spine/walk.md | T2, T4, T5, T6, T8, T12, T22 | 30m | all | record/wave-11-lean-spine/walk.md | — |
| T14 | 5 | test | Tests floor: bash tests/run.sh in the wave worktree; census commands re-run; evidence/floor.md | T2, T4, T5, T6, T8, T12, T22 | 40m | all | record/wave-11-lean-spine/evidence/floor.md | — |
| T15 | 5 | verify | Discharge the matrix: 22 static pins, 12 hermetic rows, 6 live drives; one evidence file per AC | T13, T14 | 90m | all | record/wave-11-lean-spine/evidence/ | — |
| T16 | 5 | verify | Auditor on the REQ-1e and REQ-1f rows (double) and the wave verdict | T15 | 45m | REQ-1e, REQ-1f | record/wave-11-lean-spine/auditor.md | — |
| T17 | 6 | review | Six-axis self-review, one reviewer per axis in parallel at exec-complex | T16 | 45m | all | record/wave-11-lean-spine/review/ | — |
| T18 | 6 | review | Critic on T7–T12 (double rows) | T17 | 45m | REQ-1e, REQ-1f | record/wave-11-lean-spine/critic.md | — |
| T19 | 7 | doc | ADRs 001–004; spec adrs: pointer | T18 | 30m | D1, D3, D4, D5 | adrs/epic-23-bionic-tech-debt/ | — |
| T20 | 8 | integrate | Wake Note, then attended no-ff merge to main; writer worktrees and the wave worktree removed; tmp ephemera wiped | T19 | 20m | all | none | — |
| T22 | 4 | build | 1g: fix the doctor/setup agreement on the `motion` row so DS.2a/2c/9/11 pass on this machine; honour the 2026-08-22 ruling | T1 | 60m | REQ-1g | payload/scripts/lib/deps.sh, payload/scripts/doctor.sh, payload/scripts/setup.sh, tests/cross-gate-agreement.test.sh | — |
| T21 | 9 | close | Close-out report with dispositions; continuation.md; archive_run; Patrol CronDelete + disarm | T20 | 30m | all | record/wave-11-lean-spine/closeout-report.md | — |
TASKS_TABLE_EOF

# live.md — the specimen in the shape a page at 15 presents it: its header with the version
# line, the table under its own heading, and a following `## Verification Matrix` that the
# reader must stop at.
{
  printf -- '---\ncanonical_sdlc_version: 15\n---\n\n'
  printf -- '## Tasks\n\n'
  cat "$SANDBOX/tasks-table.md"
  printf -- '\nParallel width: 15 writers budgeted.\n\n'
  printf -- '## Verification Matrix\n\n| AC | Criterion |\n|---|---|\n| AC-1e.1 | id | 4 | x |\n'
} > "$SANDBOX/live.md"

# reordered.md — THE SAME ROWS, EVERY COLUMN REVERSED. Name-blind: the transform reverses
# the cells of every row of the table and knows nothing about what any column is called.
reverse_cells() {
  awk '
    /^[[:space:]]*\|/ {
      n = split($0, c, "|")
      out = "|"
      for (i = n - 1; i >= 2; i--) out = out c[i] "|"
      print out
      next
    }
    { print }
  ' "$1"
}
reverse_cells "$SANDBOX/tasks-table.md" > "$SANDBOX/tasks-table-reversed.md"
{
  printf -- '---\ncanonical_sdlc_version: 15\n---\n\n## Tasks\n\n'
  cat "$SANDBOX/tasks-table-reversed.md"
  printf -- '\n## Verification Matrix\n'
} > "$SANDBOX/reordered.md"

# decoys.md — a table under the RETIRED section heading BEFORE the real one, and a fenced
# example table AFTER it. Neither is the plan's schedule; a reader that keyed on header
# names alone, or that ignored fences, would take one of them for the table. The heading
# literal below is the retired word, kept on purpose: this fixture is what proves the
# reader refuses it.  # retired: slice
{
  printf -- '---\ncanonical_sdlc_version: 15\n---\n\n'
  printf -- '## Slices (machine-readable)\n\n'  # retired: slice
  printf -- '| id | deps | complexity | status |\n|---|---|---|---|\n'
  printf -- '| S1 | — | complex | landed |\n| S2 | S1 | standard | pending |\n\n'
  printf -- '## Tasks\n\n'
  cat "$SANDBOX/tasks-table.md"
  printf -- '\n## Notes\n\nThe schema, for a reader:\n\n```\n'
  printf -- '| id | step | kind | task | deps | size | serves | Files | artifact |\n'
  printf -- '|---|---|---|---|---|---|---|---|---|\n'
  printf -- '| T99 | 4 | build | example row | — | 1m | none | none | — |\n'
  printf -- '```\n'
} > "$SANDBOX/decoys.md"

# ready-a — one step, one blocked row, a page at 15 with the plan's approval in its log. T2 landed; T4 depends on T3,
# which is pending.
R4A="$(plan_fixture --current 4 "$SANDBOX/ready/plans/e/ready-a.plan.md" task \
  '| T1 | 3 | doc | plan written | orchestrator | — | — | 30m | all | plan | — | — | landed |' \
  '| T2 | 4 | build | already landed | implementor | T1 | — | 15m | REQ-x | a.sh | — | — | landed |' \
  '| T3 | 4 | build | free to go | implementor | T1 | — | 15m | REQ-x | b.sh | — | — | pending |' \
  '| T4 | 4 | build | blocked behind T3 | implementor | T3 | — | 15m | REQ-x | c.sh | — | — | pending |' \
  '| T5 | 4 | build | free to go | implementor | T2 | — | 15m | REQ-x | d.sh | — | — | pending |')"

# ready-b — every Step-4 row landed, three Step-5 rows, written OUT OF ID ORDER so that "table order" is a different
# answer from "sorted by id". T6 names a dependency the table does not carry.
R4B="$(plan_fixture --current 5 "$SANDBOX/ready/plans/e/ready-b.plan.md" task \
  '| T1 | 3 | doc | plan written | orchestrator | — | — | 30m | all | plan | — | — | landed |' \
  '| T2 | 4 | build | landed | implementor | T1 | — | 15m | REQ-x | a.sh | — | — | landed |' \
  '| T3 | 4 | build | landed | implementor | T1 | — | 15m | REQ-x | b.sh | — | — | landed |' \
  '| T7 | 5 | verify | the walk | researcher | T2, T3 | — | 30m | all | walk.md | — | — | pending |' \
  '| T6 | 5 | verify | names a dep nobody defines | researcher | T2, T3, T9 | — | 30m | all | x.md | — | — | pending |' \
  '| T5 | 5 | test | the floor | test-runner | T2, T3 | — | 40m | all | floor.md | — | — | pending |')"

# broken.md — one row per invariant, each breaking exactly one. T7 is a Step-6 row whose
# transitive closure is {T1}, so it reaches no other Step-4 row.
cat > "$SANDBOX/broken.md" <<'BROKEN_EOF'
---
current: 4
---

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the good row | implementor | — | 15m | REQ-x | a.sh | pending |
| T1 | 4 | build | the same id again | implementor | — | 15m | REQ-x | b.sh | pending |
| X1 | 4 | build | an id of the wrong shape | implementor | — | 15m | REQ-x | c.sh | pending |
| T3 | 2 | build | a step below the range | implementor | — | 15m | REQ-x | d.sh | pending |
| T4 | 4 | slice | the retired word as a kind | implementor | — | 15m | REQ-x | e.sh | pending |  # retired: slice
| T6 | 4 | build | a dep naming no row | implementor | T99 | 15m | REQ-x | g.sh | pending |
| T7 | 6 | review | reaches only T1 | critic | T1 | 15m | REQ-x | h.sh | pending |
BROKEN_EOF

# missing-column.md — a page at 15 whose nine-cell schema has `step` deleted. AC-1e.5's third case.
cat > "$SANDBOX/missing-column.md" <<'MISSING_EOF'
---
canonical_sdlc_version: 15
---

## Tasks

| id | kind | task | deps | size | serves | Files | artifact |
|---|---|---|---|---|---|---|---|
| T1 | build | no step column anywhere | — | 15m | REQ-x | a.sh | — |
MISSING_EOF

# no-table.md — a page at 15 with no `## Tasks` at all.
printf -- '---\ncanonical_sdlc_version: 15\n---\n\n## Notes\n\n- Step 4: in flight\n' > "$SANDBOX/no-table.md"

ROWS_LIVE="$(call units_rows "$SANDBOX/live.md")"

section "1 — units_rows: the live table, thirteen fields per row, in the fixed order"

expect_eq "the live specimen yields one line per data row (22)" "22" "$(nlines "$ROWS_LIVE")"

# TWELVE SINCE wave-17 REQ-2 (eleven since wave-14 REQ-2, ten before that) — and the
# specimen carries neither the `worktree` nor the `base` column, so every one of the 22 lines
# ends in two EMPTY fields rather than stopping at ten. A record whose width depended on which
# columns the table happened to carry would put every caller back to counting cells, which is
# the whole of what this reader exists to stop.
expect_eq "every line carries exactly thirteen tab-separated fields" "22" \
  "$(printf '%s\n' "$ROWS_LIVE" | awk -F'\t' 'NF == 13 { n++ } END { print n + 0 }')"

# THE FIRST ROW, WHOLE. Written out by hand from the plan, which is the point: a row asserted
# against a value the reader itself produced would pass on any consistent misreading.
T2_LINE="$(printf '%s\n' "$ROWS_LIVE" | awk -F'\t' '$1 == "T2"')"
expect_eq "T2 field 6 is deps"   "T1"     "$(printf '%s\n' "$T2_LINE" | cut -f6)"
expect_eq "T2 field 2 is the step" "4"     "$(printf '%s\n' "$T2_LINE" | cut -f2)"
expect_eq "T2 field 3 is the kind" "build" "$(printf '%s\n' "$T2_LINE" | cut -f3)"

# `Files` is read case-insensitively on the header cell — it is the one capitalised header
# in the shipped table, and a case-sensitive reader drops the column silently.
expect_contains "T2 field 9 is the Files cell, matched case-insensitively on the header" \
  "payload/integrity/rendered.sha256" "$(printf '%s\n' "$T2_LINE" | cut -f9)"

# A MULTI-ID DEPS CELL survives whole; splitting is units_ready's job, not units_rows'.
expect_eq "T13's deps cell comes through unsplit" "T2, T4, T5, T6, T8, T12, T22" \
  "$(printf '%s\n' "$ROWS_LIVE" | awk -F'\t' '$1 == "T13"' | cut -f6)"

# TABLE ORDER, NOT ID ORDER. The live plan carries T22 before T21; a reader that sorted
# would answer the dispatch question in an order the orchestrator did not choose.
expect_eq "rows come out in TABLE order — T22 is 21st and T21 is 22nd" "T22 T21" \
  "$(printf '%s\n' "$ROWS_LIVE" | sed -n '21p;22p' | cut -f1 | tr '\n' ' ' | sed 's/ $//')"

# The separator row and the trailing prose are not rows.
expect_eq "no separator or prose line is emitted as a row" "" \
  "$(printf '%s\n' "$ROWS_LIVE" | awk -F'\t' '$1 ~ /^[-: ]*$/ || $1 ~ /Parallel/')"

section "2 — units_rows is keyed on header NAMES: reversed columns, identical output (AC-1e.2)"

# THE FIXTURE REALLY IS REORDERED — the positive control, without which the equality below
# would pass just as loudly on two copies of the same file.
expect_eq "…so the two table files are not the same bytes" "differ" \
  "$(cmp -s "$SANDBOX/tasks-table.md" "$SANDBOX/tasks-table-reversed.md" && echo same || echo differ)"

ROWS_REORDERED="$(call units_rows "$SANDBOX/reordered.md")"
expect_eq "…and the comparison is over 22 real rows, not two empty strings" "22" \
  "$(nlines "$ROWS_REORDERED")"
expect_eq "reversing every column changes not one byte of the TSV" "$ROWS_LIVE" "$ROWS_REORDERED"

# ---------- slot 3 has one name, `kind` (wave-31 T24; REQ-1, D2; A-39 retired) ----------
#
# THE ALIAS IS GONE WITH ITS READER. Slot 3 answered to `rigor` too (A-39) so the evidence
# gate's `validate_task_ledger` could read the retired five-column task ledger's rigor cell
# through this library. One ledger shape deleted that reader and that table: every plan
# carries the one `## Tasks` table, whose slot 3 is `kind`. The page below is that table's nine
# cells, its fields taken by name, and `rigor` is a name the contract no longer answers to.
cat > "$SANDBOX/kind-slot.md" <<'KIND_SLOT_EOF'
---
canonical_sdlc_version: 15
---

## Tasks

| id | step | kind | task | deps | size | serves | Files | artifact |
|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | fix the frontmatter parser | — | 30m | REQ-1 | a.sh | — |
| T2 | 4 | test | extract the ledger helper | T1 | 30m | REQ-1 | b.sh | — |
| T3 | 4 | build | two empty cells |  |  | REQ-1 | c.sh | — |
KIND_SLOT_EOF

ROWS_KIND="$(call units_rows "$SANDBOX/kind-slot.md")"
expect_eq "the nine-cell page yields its three rows" "3" "$(nlines "$ROWS_KIND")"
expect_eq "units_field takes the row's id and kind by name" "T2 test" \
  "$(bash -c '. "$1" >/dev/null 2>&1 || exit 127
     row="$(units_rows "$2" | sed -n 2p)"
     printf "%s %s" "$(units_field "$row" id)" "$(units_field "$row" kind)"' \
     _ "$LIB" "$SANDBOX/kind-slot.md")"
expect_eq "…and refuses rigor, a name the contract no longer carries (rc 1)" "1" \
  "$(bash -c '. "$1" >/dev/null 2>&1 || exit 127
     row="$(units_rows "$2" | sed -n 2p)"
     units_field "$row" rigor >/dev/null; echo $?' \
     _ "$LIB" "$SANDBOX/kind-slot.md")"
expect_eq "…and refuses a column name the contract does not carry" "1" \
  "$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; units_field "x" intent' _ "$LIB" >/dev/null 2>&1; echo $?)"
expect_eq "an empty cell reads empty, not as the cell after it: T3's deps and size, then its serves" "[][][REQ-1]" \
  "$(printf '%s\n' "$ROWS_KIND" | sed -n 3p | awk -F'\t' '{ printf "[%s][%s][%s]", $6, $7, $8 }')"

section "3 — units_rows reads the ## Tasks section and nothing else"

ROWS_DECOYS="$(call units_rows "$SANDBOX/decoys.md")"
expect_eq "…over 22 real rows, not two empty strings" "22" "$(nlines "$ROWS_DECOYS")"
expect_eq "a retired ## Slices table in the same file is ignored" "$ROWS_LIVE" "$ROWS_DECOYS"  # retired: slice
expect_eq "…so no S-row reaches the output" "" \
  "$(printf '%s\n' "$ROWS_DECOYS" | awk -F'\t' '$1 ~ /^S[0-9]/')"
expect_eq "…and the fenced example row is documentation, not a row" "" \
  "$(printf '%s\n' "$ROWS_DECOYS" | awk -F'\t' '$1 == "T99"')"

expect_eq "a plan with no ## Tasks section yields no rows" "" \
  "$(call units_rows "$SANDBOX/no-table.md")"
expect_eq "…and says so with a non-zero status" "1" "$(call_rc units_rows "$SANDBOX/no-table.md")"
expect_eq "a plan that has the table exits 0" "0" "$(call_rc units_rows "$SANDBOX/live.md")"

section "4 — units_ready: pending and every dep landed; the step is a label (wave-20 Δ1)"
#
# Readiness is the prerequisite graph — a work row is
# ready when it is pending and every prerequisite has landed, whatever its step — so the
# argument no longer filters a work row. It still decides the gate-act rows (§17).

expect_eq "step 4: a row whose dep is still pending is not ready, and its siblings are" \
  "$(printf 'T3\nT5')" "$(call units_ready "$R4A" 4)"
expect_eq "…so T4, blocked behind pending T3, is absent" "" \
  "$(call units_ready "$R4A" 4 | grep -x T4)"
expect_eq "…and T2, already landed, is not offered again" "" \
  "$(call units_ready "$R4A" 4 | grep -x T2)"
expect_eq "…and asked at step 3 the same rows are ready: the argument is not a filter (Δ1)" \
  "$(printf 'T3\nT5')" "$(call units_ready "$R4A" 3)"

expect_eq "step 5 with every Step-4 row landed: the ready rows, in TABLE order" \
  "$(printf 'T7\nT5')" "$(call units_ready "$R4B" 5)"
expect_eq "…a dep naming an id the table does not carry is never ready" "" \
  "$(call units_ready "$R4B" 5 | grep -x T6)"
expect_eq "…asked at step 4 the Step-5 rows are still ready: their deps landed (Δ1)" \
  "$(printf 'T7\nT5')" "$(call units_ready "$R4B" 4)"
expect_eq "…and at step 9 too: no work row waits for the run to reach its step" \
  "$(printf 'T7\nT5')" "$(call units_ready "$R4B" 9)"

# A `—` deps cell names no dependency; so do `-` and an empty cell.
R4D="$(plan_fixture --current 4 "$SANDBOX/ready/plans/e/ready-dashes.plan.md" task \
  '| T1 | 4 | build | em dash | implementor | — | — | 1m | x | a | — | — | pending |' \
  '| T2 | 4 | build | hyphen | implementor | - | — | 1m | x | b | — | — | pending |' \
  '| T3 | 4 | build | empty | implementor |  | — | 1m | x | c | — | — | pending |')"
expect_eq "an em dash, a hyphen and an empty cell all mean no dependency" \
  "$(printf 'T1\nT2\nT3')" "$(call units_ready "$R4D" 4)"
# A GATE ACT WAITS FOR ITS STEP: the close row, its dep landed, is held below step 9 and ready at it.
R4G="$(plan_fixture --current 4 "$SANDBOX/ready/plans/e/ready-gate.plan.md" task \
  '| T1 | 4 | build | landed | implementor | — | — | 15m | REQ-x | a.sh | — | — | landed |' \
  '| T20 | 9 | close | the close | orchestrator | T1 | — | 15m | REQ-x | .bionic/docs/record/e/T20.md | — | — | pending |')"
expect_eq "a gate act whose deps landed is held for its step at Step 4 and ready at Step 9" \
  "T20: step 9 close row waits for current: 9||T20" "$(call units_held "$R4G" 4)|$(call units_ready "$R4G" 4)|$(call units_ready "$R4G" 9)"

section "6 — units_validate: one line per broken invariant, naming the id and the rule"

VAL_BAD="$(call units_validate "$SANDBOX/broken.md")"

# FIVE INVARIANTS ARE BROKEN, one row each. T7, a Step-6 row reaching only T1, used to be the
# seventh — "every Step-5+ row depends transitively on every Step-4 row" — and that rule is
# gone (wave-26 T2, D2): a row waits for what it reads, never for every build row. So every
# line names one of the five offending rows, and T7 draws none.
expect_eq "every violation line names one of the five offending rows" "" \
  "$(printf '%s\n' "$VAL_BAD" | grep -vE '^(T1|X1|T3|T4|T6): ')"
expect_eq "…and exits 1" "1" "$(call_rc units_validate "$SANDBOX/broken.md")"

expect_contains "an id used twice is named once, as a duplicate" \
  "T1: duplicate id" "$VAL_BAD"
expect_contains "an id of the wrong shape names the shape it must match" \
  "X1: id does not match ^T[0-9]+\$" "$VAL_BAD"
expect_contains "a step outside 3-9 names the step and the range" \
  "T3: step 2 is outside 3-9" "$VAL_BAD"
# THE STEP-6 ROW THAT REACHES ONLY T1 IS NOT ACCUSED (wave-26 T2, D2). Beside the six lines
# above, which prove the extractor reads this output, no line begins with T7.
expect_eq "a Step-6 row that reaches one Step-4 row of five draws no violation" "" \
  "$(printf '%s\n' "$VAL_BAD" | grep '^T7: ')"

# PAIRED POSITIVE. The good row is in the same table and is not accused of anything.
expect_eq "the one well-formed row draws no violation of its own" "0" \
  "$(printf '%s\n' "$VAL_BAD" | grep -c '^T1: [^d]' | tr -d ' ')"

section "7 — units_validate: a missing column is a violation of the table, not of a row"

VAL_MISSING="$(call units_validate "$SANDBOX/missing-column.md")"
expect_contains "a schema with no step column is refused, naming the column" \
  "## Tasks: missing column step" "$VAL_MISSING"
expect_eq "…and exits 1" "1" "$(call_rc units_validate "$SANDBOX/missing-column.md")"
expect_eq "a plan with no ## Tasks section at all is refused" "1" \
  "$(call_rc units_validate "$SANDBOX/no-table.md")"
expect_contains "…naming the absent section" "## Tasks" "$(call units_validate "$SANDBOX/no-table.md")"

section "9 — a markdown-escaped pipe in a cell (the critic's Issue 1)"
#
# `\|` IS THE ONE ESCAPE A GFM TABLE CELL DEFINES, and it is a raw `|` to `split()`. A
# reader that splits the record as written opens an extra field at the escape and reads
# every cell after it one slot early — the `agent` cell as `deps`, the `Files` cell as
# `status` — which is silent, because a shifted row is still a row.
#
# THIS IS NOT HYPOTHETICAL. This wave's own plan carries one, in T23's `task` cell
# (`the five PreToolUse\|Bash walls fold by …`), and with it in place `units_ready` could
# name nothing at Step 5 and `units_validate` reported two violations against cells that
# are correct. The docblock's old claim — "a cell never contains a literal `|`, so there
# is no escaping to undo" — was true of the RAW byte and false of the table.
#
# TWO FIXTURES, and the second is the critic's own control. A purpose-built page at 15 isolates
# the shift, with escapes in a task cell and in a Files cell after one; the derived one puts the
# live plan's actual row back and asks the validator of it.
#
# The purpose-built page holds its approval and both landings in its log, beside the same page with the escapes spent.
ES15="$SANDBOX/esc/plans/e/esc.plan.md"; mkdir -p "${ES15%/*}" "$SANDBOX/esc/record/esc" "$SANDBOX/esc/record/esc-control"
{ printf -- '---\ncanonical_sdlc_version: 15\n---\n\n## Tasks\n\n| id | step | kind | task | deps | size | serves | Files | artifact |\n|---|---|---|---|---|---|---|---|---|\n'
  printf '%s\n' '| T1 | 4 | build | the five PreToolUse\|Bash walls fold into one process | — | 90m | REQ-1f | payload/scripts/lib/walls.sh | — |' \
    '| T2 | 4 | build | matches \|first\| and \|second\| both | T1 | 10m | REQ-1f | hooks/a\|b.sh | — |' '| T3 | 5 | verify | plain prose, no escape anywhere | T1, T2 | 20m | all | record/x.md | — |'
} > "$ES15"
awk '{ gsub(/\\[|]/, "-"); print }' "$ES15" > "${ES15%/*}/esc-control.plan.md"
printf 'run/v1|ev=%s|at=2026-10-20T00:00:0%sZ\n' 'step|n=5' 1 'approval|key=step3|by=me|said=approved' 2 'published|row=T1' 3 'published|row=T2' 4 \
  | tee "$SANDBOX/esc/record/esc-control/run.log" > "$SANDBOX/esc/record/esc/run.log"

ROWS_ESC="$(call units_rows "$ES15")"

expect_eq "three data rows, escapes and all" "3" "$(nlines "$ROWS_ESC")"
expect_eq "every row still carries exactly thirteen fields" "3" \
  "$(printf '%s\n' "$ROWS_ESC" | awk -F'\t' 'NF == 13 { n++ } END { print n + 0 }')"

# THE WHOLE ROW, field by field. The shift this section exists for moves every cell AFTER
# the escape, so asserting the escaped cell alone would pass on a reader that recovered the
# text and lost the columns.
ESC_T1="$(printf '%s\n' "$ROWS_ESC" | awk -F'\t' '$1 == "T1"')"
expect_eq "…and field 6 is still deps"       "—"                  "$(printf '%s\n' "$ESC_T1" | cut -f6)"
expect_eq "…and field 7 is still size"       "90m"                "$(printf '%s\n' "$ESC_T1" | cut -f7)"
expect_eq "…and field 8 is still serves"     "REQ-1f"             "$(printf '%s\n' "$ESC_T1" | cut -f8)"
expect_eq "…and field 9 is still Files"      "payload/scripts/lib/walls.sh" \
  "$(printf '%s\n' "$ESC_T1" | cut -f9)"

# TWO ESCAPES IN ONE CELL, and the restore is per-occurrence rather than per-cell.
ESC_T2="$(printf '%s\n' "$ROWS_ESC" | awk -F'\t' '$1 == "T2"')"
expect_eq "a cell carrying two escaped pipes reads back with both" \
  "matches |first| and |second| both" "$(printf '%s\n' "$ESC_T2" | cut -f4)"
expect_eq "…and the Files cell after it keeps its own escape" "hooks/a|b.sh" "$(printf '%s\n' "$ESC_T2" | cut -f9)"

# THE TWO VERBS, which is where the shift was actually costing the wave.
expect_eq "units_validate finds no violation in a table whose only oddity is the escape" \
  "" "$(call units_validate "$ES15")"
expect_eq "…and exits 0" "0" "$(call_rc units_validate "$ES15")"
expect_eq "units_ready can still schedule the Step-5 row behind those two, on a page at 15" "T3" "$(call units_ready "$ES15" 5)"
expect_eq "…and the escape changes NOTHING about that answer: the same page with the escapes spent schedules the same" \
  "$(call units_ready "$ES15" 5)" "$(call units_ready "${ES15%/*}/esc-control.plan.md" 5)"

# ── the critic's control, on this wave's own schedule ────────────────────────
#
# THE SPECIMEN PREDATES T23 (it was spliced at 1f48673). The row below is the live plan's
# own, cut to nine cells as the specimen is — the plan tree is gitignored and absent from a
# worktree, so it cannot be read here without breaking hermeticity. The transform then
# extends T13's and T14's deps cells the way the live plan does, and the page's log lands
# every row but those two, which is the state the tick was asked about when it answered
# nothing. While its step-3 doc row is open, that row waits on the head and every build row
# waits on it, so the same page with an empty log is a read cycle.
T23_ROW='| T23 | 4 | build | 1f-e: the five PreToolUse\|Bash walls fold by the same bionic_fold into one process (hooks/bash-walls.sh); differential vs the five originals incl. stdout JSON merge; hooks.json 16 → 12 (AC-1f.5) | T12 | 90m | REQ-1f | payload/scripts/lib/walls.sh, hooks/bash-walls.sh, hooks/hooks.json | — |'

# THE ROW TRAVELS BY FILE, NEVER BY `awk -v`. An assignment on the command line is scanned
# for escape sequences, so `\|` reaches the program as a bare `|` and the fixture would lose
# the very byte it exists to carry. (Measured on darwin 25.6.0: the first draft of this
# fixture read back `PreToolUse|Bash` and the RED run passed the wrong assertion.)
printf '%s\n' "$T23_ROW" > "$SANDBOX/t23-row.md"

EL="$SANDBOX/esc/plans/e/esc-live.plan.md"; mkdir -p "$SANDBOX/esc/record/esc-live"
{
  printf -- '---\ncanonical_sdlc_version: 15\n---\n\n## Tasks\n\n'
  awk '
    FNR == NR { t23 = $0; next }
    /^\|[ \t]*T[0-9]+[ \t]*\|/ {
      sub(/\| T2, T4, T5, T6, T8, T12, T22 \|/, "| T2, T4, T5, T6, T8, T12, T22, T23 |")
      print
      if ($0 ~ /^\|[ \t]*T12[ \t]*\|/) print t23
      next
    }
    { print }
  ' "$SANDBOX/t23-row.md" "$SANDBOX/tasks-table.md"
  printf -- '\n## Verification Matrix\n'
} > "$EL"
awk -F'|' '/^\| T[0-9]+ / { r = $2; gsub(/ /, "", r); if (r != "T13" && r != "T14") printf "run/v1|ev=published|row=%s|commit=c|by=w|at=2026-10-20T00:00:00Z\n", r }' \
  "$EL" > "$SANDBOX/esc/record/esc-live/run.log"

expect_eq "units_validate clears the escaped schedule too" "" \
  "$(call units_validate "$EL")"

# T23's own row, which is the one the shift mangled: a cell after the escape was read one slot early.
ESC_T23="$(call units_rows "$EL" | awk -F'\t' '$1 == "T23"')"
expect_eq "T23's deps is the deps"     "T12"                "$(printf '%s\n' "$ESC_T23" | cut -f6)"
expect_contains "T23's task cell keeps its pipe" "PreToolUse|Bash" \
  "$(printf '%s\n' "$ESC_T23" | cut -f4)"


section "§ORDER — build, regression, review, release: units_validate refuses any other order naming the rows; units_order reads it"
# A pair out of order is refused when neither row is dropped and one is open; landed history is not judged. Each page is
# at 15, its rows' nine cells written by o5 and the run's log beside it by o5log.
O5="$SANDBOX/docs/plans/e/o5.plan.md"; O5_LOG="$SANDBOX/docs/record/o5/run.log"; mkdir -p "${O5%/*}" "${O5_LOG%/*}"
o5() { printf -- '---\ncanonical_sdlc_version: 15\n---\n## Tasks\n| id | step | kind | task | deps | size | serves | files | artifact |\n|---|---|---|---|---|---|---|---|---|\n' > "$O5"; printf '| %s | %s | %s | t | %s | 30m | R | %s | — |\n' "$@" >> "$O5"; }   # <id step kind deps files>...
o5log() { printf 'run/v1|ev=%s|at=2026-11-01T00:00:00Z\n' 'step|n=7' "$@" > "$O5_LOG"; }   # <event>... -> the run's log
ov() { call units_validate "$O5" > "$SANDBOX/.ov"; printf '%s|%s' "$(cat "$SANDBOX/.ov")" "$CALL_RC"; }
O5_REG="T5 5 test — r/T5.md"; O5_REV="T6 6 review — r/T6.md"; O5_REL="T7 7 doc — CHANGELOG.md"
OR_REGLINE='T5: the regression row comes after the review row T6; the order is build, regression, review, release: put T5 at step 5, ahead of T6'
# shellcheck disable=SC2086
o5 $O5_REG $O5_REV $O5_REL; o5log
expect_eq "ORD-1b units_order names the regression row of the ordered page" "T5|0" "$(call units_order "$O5")|$(call_rc units_order "$O5")"
# shellcheck disable=SC2086
o5 $O5_REV $O5_REL ${O5_REG/ 5 / 7 }
expect_eq "ORD-2b the regression after the review: units_order reads no order" "|1" "$(call units_order "$O5")|$(call_rc units_order "$O5")"
# shellcheck disable=SC2086
o5 $O5_REG $O5_REL
expect_eq "ORD-6 no review row: the regression ahead of the release validates, and is the order" "|0|T5" "$(ov)|$(call units_order "$O5")"
# shellcheck disable=SC2086
o5 $O5_REG $O5_REV
expect_eq "ORD-7 no release row: no order to read (rc 1)" "|1" "$(call units_order "$O5")|$(call_rc units_order "$O5")"

section "§AFTER-PUBLISH — after the release is the order the landing record published in, not the plan's step and table position"
# A fix row born at step 4 stands ahead of the release row in the plan's order and publishes after it. The reader
# rule and the release card both ask whether what a review row reads was written after the release, and the numbers
# re-renderer answers by the record's publish order, so the one question has one answer: the record's order, with
# the plan's order only where no record names the release row. The plan sits in a repository of its own so the
# record is found by the plan's name, the way every other reader finds it.
AP_REPO="$SANDBOX/ap-repo"
git init -q "$AP_REPO" && mkdir -p "$AP_REPO/.bionic/docs/plans" "$AP_REPO/.bionic/docs/record/ap"
AP_P="$AP_REPO/.bionic/docs/plans/ap.plan.md"
AP_H="$(printf '%040d' 1)"
ap_state() { printf '%s|%s|%s' "$(call units_validate "$AP_P")" "$(call_rc units_validate "$AP_P")" "$(call units_post_readers "$AP_P")"; }
AP_T9="$(printf 'T9\tpending\tunread')"
PO_ORD='T7: the release row comes ahead of the review row T9; the order is build, regression, review, release: put T7 at step 7, after T9'

# AT 15 the page holds each row's nine cells, T9 waiting in its deps on the fix row, and the run's log its step, its
# approval and a published event for each row landed, in the order they landed.
AP_LOG="$AP_REPO/.bionic/docs/record/ap/run.log"
ap15() {  # <published row>... -> AP_P at 15, and its log
  local r
  { printf -- '---\ncanonical_sdlc_version: 15\n---\n\n## Tasks\n\n| id | step | kind | task | deps | size | serves | Files | artifact |\n|---|---|---|---|---|---|---|---|---|\n'
    printf '| %s | %s | %s | t | %s | 30 | REQ-1 | %s | — |\n' T1 4 build — 'lib/a.sh, .bionic/docs/record/w/T1.md' T5 5 test — .bionic/docs/record/w/T5.md \
      T6 6 review — .bionic/docs/record/w/T6.md T7 7 doc — CHANGELOG.md T8 4 build — 'lib/b.sh, .bionic/docs/record/w/T8.md' \
      T9 7 review T8 .bionic/docs/record/w/T9-adversarial.md; } > "$AP_P"
  printf 'run/v1|ev=%s|at=2026-10-12T00:00:00Z\n' 'step|n=7' 'approval|key=step3|by=fixture|said=approved' > "$AP_LOG"
  for r in "$@"; do printf 'run/v1|ev=published|row=%s|commit=%s|kind=queue|by=-|why=-|at=2026-10-12T00:00:00Z\n' "$r" "$AP_H"; done >> "$AP_LOG"
}

ap15 T1 T5 T6 T7 T8
expect_eq "AP-0 precondition: the log holds both the release row T7 and the fix row T8, T7 first" "T7 T8" \
  "$(awk -F'|' '{ for (i = 1; i <= NF; i++) if ($i ~ /^row=T[78]$/) printf "%s%s", (n++ ? " " : ""), substr($i, 5) }' "$AP_LOG")"
expect_eq "AP-1 the fix row published after the release: T9 reading its record is admitted (no line, rc 0) and listed for the card" \
  "|0|$AP_T9" "$(ap_state)"
ap15 T1 T5 T6 T8 T7
expect_eq "AP-2 the same plan with the log's order reversed, the fix published before the release: refused with the order text, nothing listed" \
  "$PO_ORD|1|" "$(ap_state)"
ap15
expect_eq "AP-3 the same plan with no landing in its log: plan order decides, and the step-4 fix row is not past the release (refused, nothing listed)" \
  "$PO_ORD|1|" "$(ap_state)"
ap15 T1 T5 T6 T7
expect_eq "AP-4 the fix row open and unpublished, the release published: it will publish past the release, so T9 is admitted and listed" \
  "|0|$AP_T9" "$(ap_state)"

# A PLAN VERB'S DRY COPY NAMES NO RECORD, so the origin plan is the second operand: the record is read from the plan the
# copy was made from, and the copy is judged as the plan is. The copy sits beside the plan under the name a verb gives it.
AP_COPY="$AP_P.task-add-dry.4242"
ap_copy_state() { printf '%s|%s|%s' "$(call units_validate "$AP_COPY" "$1")" "$(call_rc units_validate "$AP_COPY" "$1")" \
  "$(call units_post_readers "$AP_COPY" "$1")"; }
ap15 T1 T5 T6 T7 T8; cp "$AP_P" "$AP_COPY"
expect_eq "AP-6 the copy of a plan whose record published the fix row after the release, judged with the plan as origin: admitted and listed as the plan is" \
  "$(ap_state)" "$(ap_copy_state "$AP_P")"
expect_eq "AP-6b …and that answer is an admission, so the equality above is not two refusals" "|0|$AP_T9" "$(ap_copy_state "$AP_P")"
expect_eq "AP-7 the control: the same copy with no origin names no record and is refused by plan order, nothing listed" "$PO_ORD|1|" "$(ap_copy_state "")"
ap15 T1 T5 T6 T8 T7
expect_eq "AP-8 the copy with the origin whose record published the fix row BEFORE the release: refused with the order text, as the plan is" \
  "$PO_ORD|1|" "$(ap_copy_state "$AP_P")"
rm -f "$AP_COPY"

section "§JUDGE — covered at the last green whole run's head; past it each commit owes its row's suites, never a second whole run"

# At the last green whole run's head the judge holds the head covered; past it, a commit no landing proves is named,
# and no whole run is asked. A verdict is keyed by the commit it ran at, so a key of any other kind proves nothing.
PROOF_LIB="$REPO_ROOT/payload/scripts/lib/proof.sh"
LINE_LIB="$REPO_ROOT/payload/scripts/lib/line.sh"
JR="$SANDBOX/judge-repo"
git init -q "$JR" && git -C "$JR" config user.email t@example.com && git -C "$JR" config user.name t
printf 'a\n' > "$JR/a.sh"; git -C "$JR" add a.sh; git -C "$JR" commit -qm H
JH="$(git -C "$JR" rev-parse HEAD)"
printf 'b\n' > "$JR/b.sh"; git -C "$JR" add b.sh; git -C "$JR" commit -qm H1
JH1="$(git -C "$JR" rev-parse HEAD)"
git -C "$JR" commit -q --allow-empty -m H2
JH2="$(git -C "$JR" rev-parse HEAD)"
JP="$(plan_fixture --current 5 "$SANDBOX/judge/plans/judge.plan.md" task)"
printf 'run/v1|ev=proof|kind=regression|head=%s|evidence=whole.log|at=2026-10-20T00:00:00Z\n' "$JH" >> "$(plan_fixture_log "$JP")"
judge() { bash -c '. "$1" >/dev/null 2>&1 || exit 127; _proof_floor_judge "$2" "$3" "$4"' _ "$PROOF_LIB" "$JP" "$JR" "$1"; }
unproved() { printf 'uncovered\tcommit %.12s (no landing row) is not proved: no run of its row\047s suites is recorded at it' "$1"; }

expect_eq "the fixture's three heads are three commits" "3" \
  "$(printf '%s\n%s\n%s\n' "$JH" "$JH1" "$JH2" | sort -u | grep -c '^[0-9a-f]\{40\}$' | tr -d ' ')"
expect_eq "head H, the last green whole run's head: covered" "covered" "$(judge "$JH")"
expect_eq "head H+1, a commit no landing proves: named, and no whole run asked" "$(unproved "$JH1")" "$(judge "$JH1")"
expect_eq "H+2 changed no file, so the judge names H+1 still" "$(unproved "$JH1")" "$(judge "$JH2")"

# A verdict proves its suite at the commit it ran at; a reads key is not a commit and proves nothing.
printf 'line/v1|ev=verdict|row=T1|commit=%s|suite=a.test.sh|result=green|log=a.log|admitted=-|width=1|reads=%s|at=2026-01-01T00:00:00Z\n' \
  "$JH1" "$(printf '%064d' 7)" > "$SANDBOX/judge-rec.log"
proved() { bash -c '. "$1" >/dev/null 2>&1 || exit 127; _line_proved "$2" a.test.sh "$3"; echo "rc=$?"' _ "$LINE_LIB" "$SANDBOX/judge-rec.log" "$1"; }
expect_eq "a verdict at a commit proves its suite at that commit" "$(printf '%s\nrc=0' "$JH1")" "$(proved "$JH1")"
expect_eq "…and a reads key in its place is refused" "rc=1" "$(proved "reads=$(printf '%064d' 7)")"

# A release row's commit is excused by its check and its readers green at it: the check suite and the promoted ADRs are its own files.
RR="$SANDBOX/release-repo"
git init -q "$RR" && git -C "$RR" config user.email t@example.com && git -C "$RR" config user.name t
printf 'a\n' > "$RR/a.sh"; git -C "$RR" add a.sh; git -C "$RR" commit -qm base; RB="$(git -C "$RR" rev-parse HEAD)"
mkdir -p "$RR/payload/.claude-plugin" "$RR/payload/commands" "$RR/payload/integrity" "$RR/tests" "$RR/docs/adrs"
for f in CHANGELOG.md payload/.claude-plugin/plugin.json payload/commands/help.md payload/integrity/rendered.sha256 \
  tests/release-check.test.sh docs/adrs/adr-001-a.md; do printf 'x\n' > "$RR/$f"; done
git -C "$RR" add -A; git -C "$RR" commit -qm release; RH="$(git -C "$RR" rev-parse HEAD)"
RP="$(plan_fixture --current 7 "$RR/.bionic/docs/plans/release.plan.md" task)"
printf 'run/v1|ev=proof|kind=check|head=%s|evidence=check.log|at=2026-10-20T00:00:00Z\n' "$RH" >> "$(plan_fixture_log "$RP")"
bash -c '. "$1" && . "$2" || exit 1; for s in $(_proof_release_readers); do line_event "$3" verdict row=T8 "commit=$4" "suite=$s" result=green log=- admitted=- width=-; done' _ "$LINE_LIB" "$PROOF_LIB" "$RP" "$RH"
cover() { bash -c '. "$1" >/dev/null 2>&1 || exit 127; facts_cover "$2" "$3" "$4"; echo "rc=$?"' _ "$PROOF_LIB" "$RP" "$RB" "$RH"; }
expect_eq "a release commit with the check suite and a promoted ADR, a check and its readers green at it: release" "$(printf 'cover %s release\nrc=0' "$RH")" "$(cover)"

section "§WALK — the regression walk excuses a real release merge whose check passed, as the judge's cover reads it"

# A path's place in the release set is asked apart from its place in the docs: CHANGELOG.md is in both, and a release
# merge whose every path is in the set is excused by the check that passed at it, never sent to a landing row. Live
# tier, read-only: this repository's own release merges, pinned by hash, skipped by version and hash when absent.
# Without the check line the same merge is named as not proved, so the excuse is the check's.
WK_NONE="$(plan_fixture --current 5 "$SANDBOX/walk/plans/walk-none.plan.md" task)"
WK_PASS="$(plan_fixture --current 5 "$SANDBOX/walk/plans/walk-pass.plan.md" task)"
walk() { bash -c '. "$1" >/dev/null 2>&1 || exit 127; _proof_past_f "$2" "$3" "$4^1" "$4" ""; echo "rc=$?"' _ "$PROOF_LIB" "$1" "$REPO_ROOT" "$2" </dev/null; }
expect_eq "WALK-0 the release commit built above, CHANGELOG.md among its paths, a check passing at it: excused (rc 0)" "rc=0" \
  "$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; _proof_past_f "$2" "$3" "$4" "$5" ""; echo "rc=$?"' _ "$PROOF_LIB" "$RP" "$RR" "$RB" "$RH" </dev/null)"
WK_N=0
while read -r v m; do
  if ! git -C "$REPO_ROOT" cat-file -e "$m^{commit}" 2>/dev/null || ! git -C "$REPO_ROOT" cat-file -e "$m^1^{commit}" 2>/dev/null; then
    echo "SKIP: WALK $v merge ${m:0:12}: the merge $m or its first parent is absent from this repository"; continue
  fi
  WK_N=$((WK_N + 1))
  printf 'run/v1|ev=proof|kind=check|head=%s|evidence=check-%s.log|at=2026-10-20T00:00:0%sZ\n' "$m" "$v" "$WK_N" >> "$(plan_fixture_log "$WK_PASS")"
  expect_eq "WALK-$WK_N the $v merge ${m:0:12} with no check and no landing row: the walk names it not proved (rc 1)" \
    "$(printf 'commit %.12s (no landing row) is not proved: no run of its row\047s suites is recorded at it\nrc=1' "$m")" \
    "$(walk "$WK_NONE" "$m")"
  expect_eq "WALK-${WK_N}b …with a check passing at it: excused, nothing printed (rc 0)" "rc=0" "$(walk "$WK_PASS" "$m")"
done <<EOF
1.23.0 f75f8bbc7cd78a963f6b9f922bb2fd1af2933335
1.22.0 1c451183069a6c78a53d57135f36b7bb1a2b2d1e
1.21.0 7d5a0f719fbbf106226a41cf93c17f1d0355ee12
EOF

section "§SECOND — regression-run at a head past the plan's whole run runs it again, and at the head the run read too"

# FIXTURE FIDELITY: one real repository on its working branch; the plan bound to a session through the product's own
# binder; the whole run recorded through the product's own writers (tests/lib/regression-fixture.sh); the verb is
# session-poker.sh run as that session. The project's regression is a command that writes a marker file, so a run
# that started leaves proof of it and a refusal leaves none. fails-when: a head past the recorded whole run is
# refused a run of the declared regression, or the head the whole run read is.
SEC_SID="5d4c3b2a-1f0e-4d9c-8b7a-6f5e4d3c2b1a"
SEC_ROOT="$SANDBOX/second"; mkdir -p "$SEC_ROOT"; SEC="$SEC_ROOT/repo"
SEC_PLAN="$SEC/.bionic/docs/plans/epic-99-fixture/wave-01-second.plan.md"; SEC_REL="record/wave-01-second"
mkdir -p "$SEC/.bionic/tmp" "${SEC_PLAN%/*}" "$SEC/.bionic/docs/$SEC_REL"
sec_git() { git -C "$SEC" -c user.email=dana@fixture.test "$@"; }
sec_git init -q; sec_git config user.name "Dana Fixture"; sec_git checkout -q -b wave/01-second
printf '.bionic/\n' > "$SEC/.gitignore"; printf 'one\n' > "$SEC/a.sh"
printf 'regression-command: touch %s/ran\n' "$SEC_ROOT" > "$SEC/.bionic/config.yaml"
sec_git add -A; sec_git commit -qm base; SEC_H="$(sec_git rev-parse HEAD)"
printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 15\nintent: build\nrigor: double\nscale: wave\nworking-branch: wave/01-second\nintegration-branch: main\n---\n# plan\n' > "$SEC_PLAN"
printf 'run/v1|ev=step|n=5|at=2026-10-20T00:00:00Z\n' > "$SEC/.bionic/docs/$SEC_REL/run.log"
bound_marker "$SEC" "$SEC_SID" "$SEC_PLAN" >/dev/null 2>&1 || :
sec_poke() {  # -> SEC_OUT (stdout and stderr), SEC_RC: regression-run [flags…] as the bound session, in the repository
  SEC_RC=0
  SEC_OUT="$(cd "$SEC" && env CLAUDE_CODE_SESSION_ID="$SEC_SID" HOME="$SEC_ROOT/home" CLAUDE_CONFIG_DIR="$SEC_ROOT/config" \
    BIONIC_GATE_DIR="$SEC_ROOT/gate" bash "${BIONIC_HOOKS_DIR}/session-poker.sh" regression-run "$@" 2>&1)" || SEC_RC=$?
}
sec_ran() { [ -e "$SEC_ROOT/ran" ] && printf yes || printf no; }
sec_logs() { find "$SEC/.bionic/docs/$SEC_REL" -name 'regression-run-*.log' | wc -l | tr -d ' '; }
sec_rec() { bash -c '. "$1/payload/scripts/lib/line.sh" >/dev/null 2>&1 && line_record "$2"' _ "$BIONIC_SCRIPTS_DIR" "$SEC_PLAN"; }
sec_runline() { cat "$(sec_rec)" 2>/dev/null | /usr/bin/grep -F "|ev=run|log=$SEC_REL/$1|" || :; }   # <log name> -> its run line in the run's log
printf 'all green\n' | regression_fixture "$SEC_PLAN" "$SEC/.bionic/docs/$SEC_REL/regression-run-$SEC_H.log" "$SEC_H" 0 0
expect_eq "SEC-0 precondition: the record holds a whole run at H, clean, and no run has started" "1|no|1" \
  "$(sec_runline "regression-run-$SEC_H.log" | /usr/bin/grep -c "^run/v1|ev=run|log=$SEC_REL/regression-run-$SEC_H.log|head=$SEC_H|dirty=0|")|$(sec_ran)|$(sec_logs)"

# SEC-2 first, at the head the whole run read: this arm does not refuse it, so the declared regression starts.
sec_poke
expect_eq "SEC-2 the working head is H, the head the whole run read: not refused by this arm — the regression starts (exit 0, marker written)" \
  "0|yes" "$SEC_RC|$(sec_ran)"
expect_contains "SEC-2b …and its run line names the starter, the orchestrator by default" "|starter=orchestrator|at=" \
  "$(sec_runline "regression-run-$SEC_H-2.log")"
rm -f "$SEC_ROOT/ran"
printf 'two\n' > "$SEC/a.sh"; sec_git commit -qam 'a fix row lands'; SEC_H1="$(sec_git rev-parse HEAD)"
SEC_N="$(sec_logs)"
sec_poke --starter someone
expect_eq "SEC-3 --starter that is none of the three: refused (exit 1), nothing ran, no log" "1|no|$SEC_N" "$SEC_RC|$(sec_ran)|$(sec_logs)"
expect_contains "SEC-3b …naming the three starters" "none of the three starters: tick, orchestrator or person" "$SEC_OUT"
sec_poke --starter person
expect_eq "SEC-4 --starter person with no --reason: refused (exit 1), nothing ran, no log" "1|no|$SEC_N" "$SEC_RC|$(sec_ran)|$(sec_logs)"
expect_contains "SEC-4b …asking for the reason" "--starter person needs --reason" "$SEC_OUT"
sec_poke --starter person --reason 'the user asked for a second run'
expect_eq "SEC-1 the working head is H+1, past the whole run at H: the regression runs (exit 0, marker written, one more log)" \
  "0|yes|$((SEC_N + 1))" "$SEC_RC|$(sec_ran)|$(sec_logs)"
expect_contains "SEC-1b …and the verb reports the run at H+1, with its log" \
  "regression-run — head=$SEC_H1 dirty=0 rc=0 evidence=$SEC_REL/regression-run-$SEC_H1.log" "$SEC_OUT"
expect_absent "SEC-1c …and no refusal names the whole run at H" "runs once" "$SEC_OUT"
expect_contains "SEC-1d …and its run line names the person as its starter, with the reason" \
  "|starter=person|reason=the user asked for a second run|at=" "$(sec_runline "regression-run-$SEC_H1.log")"


section "§DEBT — the review-born count: exempt under fix-policy: or counted, and the three task-add rules each held by a row a removal turns red"
# A review-born row rated inside fix-policy: is exempt from fix-cap:; one the person promoted from outside it, or one
# born of a finding in another plan's record directory, counts. `units_born_counted` is the one reader of that test,
# and the landing line and task-add read it. The rows below pin the reader, the landing line's count, and the three
# rules task-add holds on a born row: the cap refusal, the fourth fix on one file, and the count its line prints.
# FIXTURE FIDELITY: planted plans at 15, the page's nine cells and the run's log, the born events as `task-add --born`
# writes them, the reading as `proof-add review`'s event; every task-add is the real
# verb, run as a session bound to the plan through the product's own binder, against the shipped tree and against a
# copy of it with one rule removed (hooks/ beside scripts/, the tree's own scripts and library linked in, as
# session-poker-5's §CHECK mutant is built).
# fails-when: the reader calls an exempt row counted or a promoted or carried one exempt; the landing line prints one
# total; the cap refusal, the fourth-fix refusal or the count on task-add's line is removed and no row here goes red.
DB_SID="6e5d4c3b-2a1f-4e0d-9c8b-7a6f5e4d3c2b"
DB_ROOT="$SANDBOX/debt"; mkdir -p "$DB_ROOT/home" "$DB_ROOT/config/bionic" "$DB_ROOT/gate" "$DB_ROOT/no-plugins"
DB_OWN="record/wave-01-debt"; DB_CARRIED="record/wave-00-prior"
db_plan() {  # <repo> <fix-cap> <tasks rows> <born events> [<header line>] -> the plan path at 15, bound to DB_SID
  # Its log: the steps to 4, the approval, the carried review, T1 landed, T2 active in its tree, then each born event.
  local f="$1/.bionic/docs/plans/epic-99-fixture/wave-01-debt.plan.md" h e n=0
  mkdir -p "${f%/*}" "$1/.bionic/docs/specs/epic-99-fixture" "$1/.bionic/docs/$DB_OWN" "$1/.bionic/docs/$DB_CARRIED"
  printf '# requirements\n' > "$1/.bionic/docs/specs/epic-99-fixture/wave-01-debt.requirements.md"
  printf '# spec\n' > "$1/.bionic/docs/specs/epic-99-fixture/wave-01-debt.spec.md"
  h="$(git -C "$1" rev-parse HEAD 2>/dev/null)"
  printf 'reviewed: %s..%s\nquestion: adversarial\nresult: fail\nscope: piece\n\nfindings: 2\nfinding: 1 S2 on lib/c1.sh:1 the first carried defect\nfinding: 2 S2 on lib/c2.sh:1 the second carried defect\nshown: 1 cat lib/c1.sh\nshown: 2 cat lib/c2.sh\n' \
    "$h" "$h" > "$1/.bionic/docs/$DB_CARRIED/critic.md"
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 15\nintent: bugfix\n'
    printf 'rigor: double\nfix-cap: %s\n%sscale: wave\nmulti_agent: true\nuse_worktree: true\nhas_ui: false\n' "$2" "${5:+$5
}"
    printf 'walk: exempt\ndeploy_target: n/a\nworking-branch: wave/01-debt\nbase-sha: abc1234\n'
    printf 'parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=user\n---\n\n# fixture wave\n\n## Tasks\n\n'
    printf '| id | step | kind | task | deps | size | serves | Files | artifact |\n|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | the first build | — | 30 | REQ-1 | a.sh | — |\n| T2 | 4 | build | the second build | — | 30 | REQ-1 | b.sh | — |\n'
    printf '%s' "${3:+$3
}"
    printf '| T5 | 5 | verify | the floor | T1, T2 | 30 | REQ-1 | — | — |\n\n'
  } > "$f"
  { printf '%s\n' 'step|n=1' 'step|n=2' 'step|n=3' 'step|n=4' 'approval|key=step3|by=fixture|said=approved' \
      "proof|kind=review|head=$h|evidence=$DB_CARRIED/critic.md|question=adversarial|reader=w-adv|result=fail|scope=piece" \
      'dispatch|row=T1|name=implementor' 'published|row=T1' 'dispatch|row=T2|name=w-T2' 'tree|row=T2|path=.worktrees/01-T2'
    [ -z "$4" ] || printf '%s\n' "$4"
  } | while IFS= read -r e; do n=$((n + 1)); printf 'run/v1|ev=%s|at=2026-10-20T00:00:%02dZ\n' "$e" "$n"; done > "$1/.bionic/docs/$DB_OWN/run.log"
  bound_marker "$1" "$DB_SID" "$f" >/dev/null 2>&1 || :
  printf '%s' "$f"
}
db_repo() {  # <label> -> a fresh repository with one commit, engaged by DB_SID
  local r="$DB_ROOT/$1"
  rm -rf "$r"; mkdir -p "$r/.bionic/tmp"
  git -C "$r" init -q; git -C "$r" -c user.email=dana@fixture.test -c user.name="Dana Fixture" commit -q --allow-empty -m init
  : > "$r/.bionic/tmp/engaged-$DB_SID.state"
  printf '%s' "$r"
}
db_row() { printf '| %s | 4 | build | fix %s | — | 30 | REQ-1 | %s | — |' "$1" "$1" "$2"; }   # <id> <files>
db_led() {  # <id> <marker> -> the row's born event as task-add --born writes it (lib/units.sh `units_born_event`)
  local r="${2%% of=*}" f="" m=""; [ "$r" = "$2" ] || { f="${2#* of=}"; f="${f%% *}"; }
  case "$2" in *' promoted') m='|promoted=yes' ;; esac
  printf 'born|row=%s|reason=%s%s%s' "$1" "$r" "${f:+|finding=$f}" "$m"
}
db_poke() {  # <poker> <repo> <id> <files> <born> -> DB_OUT, DB_RC: the step-4 build row an edit adds, then task-add of it as DB_SID
  local p; p="$(sed -n 's/^plan=//p' "$2/.bionic/tmp/engaged-$DB_SID.state")"; DB_RC=0
  awk -v r="| $3 | 4 | build | Fix $3. The defect is gone. · born: review | — | 30 | REQ-1 | $4 | — |" '/^\| T5 \| 5 \|/ { sub(/T1, T2/, "&, " id) } { print } /^\| T5 \| 5 \|/ { print r }' id="$3" "$p" > "$p.t" && mv "$p.t" "$p"
  DB_OUT="$(cd "$2" && env CLAUDE_CODE_SESSION_ID="$DB_SID" HOME="$DB_ROOT/home" CLAUDE_CONFIG_DIR="$DB_ROOT/config" \
    BIONIC_GATE_DIR="$DB_ROOT/gate" BIONIC_PLUGINS_DIR="$DB_ROOT/no-plugins" bash "$1" task-add "$3" --born "$5" 2>&1)" || DB_RC=$?
}
db_lib() { bash -c '. "$1/units.sh" >/dev/null 2>&1 && . "$1/run.sh" >/dev/null 2>&1 || exit 9; shift; "$@"' _ "$REPO_ROOT/payload/scripts/lib" "$@"; }

# ---------- the reader: exempt or counted, per row ----------
DBR="$(db_repo reader)"
DB_ROWS="$(db_row T3 lib/x.sh)
$(db_row T4 lib/y.sh)
$(db_row T6 lib/z.sh)
$(db_row T7 lib/w.sh)
$(db_row T8 lib/v.sh)"
DB_LEDS="$(db_led T3 'review S2 on')
$(db_led T4 "review S3 on of=$DB_OWN/rev.md#1 promoted")
$(db_led T6 "review S2 on of=$DB_CARRIED/critic.md#1")
$(db_led T7 "review S1 off of=$DB_OWN/rev.md#2")
$(db_led T8 'regression a.test.sh of=floor')"
PDR="$(db_plan "$DBR" 2 "$DB_ROWS" "$DB_LEDS")"
expect_eq "DEBT-1 units_born_counted: the policy's own rows exempt, the promoted and the carried rows counted, the regression-born row absent" \
  "T3	S2 on	exempt
T4	S3 on	counted
T6	S2 on	counted
T7	S1 off	exempt" "$(db_lib units_born_counted "$PDR")"
expect_eq "DEBT-1b …and units_born, which the fourth-fix rule reads, still names every review-born row with its Files" \
  "T3	S2 on	lib/x.sh
T4	S3 on	lib/y.sh
T6	S2 on	lib/z.sh
T7	S1 off	lib/w.sh" "$(db_lib units_born "$PDR")"
PDR1="$(db_plan "$DBR" 2 "$DB_ROWS" "$DB_LEDS" 'fix-policy: S1')"
expect_eq "DEBT-2 the policy is the plan's own: at fix-policy: S1 the S2 on row is counted, the S1 off row still exempt" \
  "T3	S2 on	counted
T4	S3 on	counted
T6	S2 on	counted
T7	S1 off	exempt" "$(db_lib units_born_counted "$PDR1")"
PDR="$(db_plan "$DBR" 2 "$DB_ROWS" "$DB_LEDS")"
expect_eq "DEBT-3 the landing line prints the counted rows against the cap, the exempt ones beside" \
  "review-born rows: 2 of cap 2 (2 exempt)" \
  "$(bash -c '. "$1/line.sh" >/dev/null 2>&1 || exit 9; _line_review_born "$2"' _ "$REPO_ROOT/payload/scripts/lib" "$PDR")"

# ---------- the three rules on task-add, each against the shipped tree and a copy with it removed ----------
DB_POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"
db_cap() {  # <poker> -> green when a counted row past fix-cap: 1 is refused naming the count and its exit
  local r p
  r="$(db_repo cap)"
  p="$(db_plan "$r" 1 "$(db_row T3 lib/c1.sh)" "$(db_led T3 "review S2 on of=$DB_CARRIED/critic.md#1")")"
  db_poke "$1" "$r" T6 lib/c2.sh "$DB_CARRIED/critic.md#2"
  case "$DB_RC|$DB_OUT" in
    "1|"*"task-add refused — review-born rows: 1 of cap 1 are counted (0 exempt under fix-policy: S1,S2-on); T6 stands in the plan unborn, the person's to remove; this finding goes to the review findings disposition, or the person raises the cap: set fix-cap=2 at the card."*) echo green ;;
    "0|"*) echo "red: admitted" ;;
    *) echo "red: $DB_RC" ;;
  esac
}
db_file() {  # <poker> -> green when a fourth review-born row on one file is refused
  local r p
  r="$(db_repo file)"
  p="$(db_plan "$r" 9 "$(db_row T3 lib/x.sh)
$(db_row T4 lib/x.sh)
$(db_row T6 lib/x.sh)" "$(db_led T3 'review S2 on')
$(db_led T4 'review S2 on')
$(db_led T6 'review S2 on')")"
  db_poke "$1" "$r" T7 lib/x.sh 'review S2 on'
  case "$DB_RC|$DB_OUT" in
    "1|"*"task-add refused — a fourth fix on lib/x.sh: T3, T4, T6 already fix it"*) echo green ;;
    "0|"*) echo "red: admitted" ;;
    *) echo "red: $DB_RC" ;;
  esac
}
db_count() {  # <poker> -> green when task-add's line says the row was exempt, and a counted one its count
  local r p a b
  r="$(db_repo count)"
  p="$(db_plan "$r" 2 "" "")"
  db_poke "$1" "$r" T6 lib/e.sh 'review S2 on'; a="$DB_RC|$(printf '%s\n' "$DB_OUT" | /usr/bin/grep 'is review-born')"
  db_poke "$1" "$r" T7 lib/c1.sh "$DB_CARRIED/critic.md#1"; b="$DB_RC|$(printf '%s\n' "$DB_OUT" | /usr/bin/grep 'is review-born')"
  case "$a" in "0|"*" · exempt under fix-policy: S1,S2-on") : ;; "0|"*) echo "red: no exempt"; return ;; *) echo "red: $a"; return ;; esac
  case "$b" in "0|"*" · counted 1 of 2") echo green ;; "0|"*) echo "red: no count" ;; *) echo "red: $b" ;; esac
}
expect_eq "DEBT-4 the cap: a counted row past fix-cap: 1 is refused, naming the count and its exit" "green" "$(db_cap "$DB_POKER")"
expect_eq "DEBT-5 the fourth fix on one file is refused" "green" "$(db_file "$DB_POKER")"
expect_eq "DEBT-6 task-add's line says which count it applied: exempt under the policy, or counted <n> of <cap>" "green" "$(db_count "$DB_POKER")"

db_mutant() {  # <name> <ERE of the line to remove> -> the mutant poker's path; `<name>.n` holds the count removed
  local m="$DB_ROOT/mut-$1" s
  # From empty: a link made over an existing link to a directory would land inside the tree it points at.
  rm -rf "$m"; mkdir -p "$m/hooks" "$m/scripts"
  for s in "$REPO_ROOT/payload/scripts"/*; do ln -s "$s" "$m/scripts/$(basename "$s")"; done
  for s in "${BIONIC_HOOKS_DIR}"/*; do
    case "$(basename "$s")" in session-poker.sh|poker) continue ;; esac
    ln -s "$s" "$m/hooks/$(basename "$s")"
  done
  cp "$DB_POKER" "$m/hooks/session-poker.sh"; cp -R "${BIONIC_HOOKS_DIR}/poker" "$m/hooks/poker"
  # The line and, for a refusal, the `exit 1` under it become `:`, so the verb goes on past the rule and nothing else changes.
  awk -v re="$2" 'skip && /^[[:space:]]*exit 1[[:space:]]*$/ { print ":"; skip = 0; next } { skip = 0 }
    $0 ~ re { print ":"; n++; skip = 1; next } { print } END { print n + 0 > "/dev/stderr" }' \
    "${BIONIC_HOOKS_DIR}/poker/plan.sh" > "$m/hooks/poker/plan.sh" 2> "$DB_ROOT/mut-$1.n"
  printf '%s' "$m/hooks/session-poker.sh"
}
db_mut_ok() {  # <name> <mutant> -> `1 0 differs` when one line was removed, the copy parses, and it is not the shipped file
  printf '%s %s %s' "$(cat "$DB_ROOT/mut-$1.n")" "$(bash -n "${2%/session-poker.sh}/poker/plan.sh" >/dev/null 2>&1; echo "$?")" \
    "$(cmp -s "${2%/session-poker.sh}/poker/plan.sh" "${BIONIC_HOOKS_DIR}/poker/plan.sh" && echo same || echo differs)"
}
DBM_CAP="$(db_mutant cap 'die "task-add refused — review-born rows: ')"
expect_eq "DEBT-7 precondition: the cap mutant removes the one cap refusal, parses, and differs" "1 0 differs" "$(db_mut_ok cap "$DBM_CAP")"
expect_eq "DEBT-7b with the cap refusal removed, DEBT-4's check goes red: the counted row past the cap is admitted" "red: admitted" "$(db_cap "$DBM_CAP")"
DBM_FILE="$(db_mutant file 'die "task-add refused — a fourth fix on ')"
expect_eq "DEBT-8 precondition: the fourth-fix mutant removes the one refusal, parses, and differs" "1 0 differs" "$(db_mut_ok file "$DBM_FILE")"
expect_eq "DEBT-8b with the fourth-fix refusal removed, DEBT-5's check goes red: the fourth row on lib/x.sh is admitted" "red: admitted" "$(db_file "$DBM_FILE")"
DBM_COUNT="$(db_mutant count 'say "task-add — [$]TA_ID is review-born ')"
expect_eq "DEBT-9 precondition: the count mutant removes the one line, parses, and differs" "1 0 differs" "$(db_mut_ok count "$DBM_COUNT")"
expect_eq "DEBT-9b with the count line removed, DEBT-6's check goes red: the row lands and its line says no count" "red: no exempt" "$(db_count "$DBM_COUNT")"

section "§ASK — the units readers ask the plan's one parser: a row edited by hand reads as the reader's row, and a proof wait still asks the judge"
#
# A ROW EDITED BY HAND. A later edit changes only T2: its deps cell becomes T1, and a tab pasted from an editor
# stays in its task cell. A record split on that tab reads every later cell one slot late, so deps answered the
# slot before it; read through lib/plan-read.sh, the cell is the one the reader's `row` reads.
AK_P="$SANDBOX/ask.plan.md"
ak_plan() {  # <T2 task cell> <T2 deps cell> -> a page at 15
  printf -- '---\ncanonical_sdlc_version: 15\n---\n\n## Tasks\n\n| id | step | kind | task | deps | size | serves | Files | artifact |\n|---|---|---|---|---|---|---|---|---|\n'
  printf '| T1 | 4 | build | one | — | 30m | R | a.sh | — |\n| T2 | 4 | build | %s | %s | 30m | R | b.sh | — |\n' "$1" "$2"
}
ak_t2() { call units_rows "$AK_P" | awk -F'\t' '$1 == "T2"'; }
ak_plan two — > "$AK_P"
expect_eq "ASK-1 before the edit, units_field T2 deps reads no dependency" "—" "$(call units_field "$(ak_t2)" deps)"
ak_plan "$(printf 'two\tpasted')" T1 > "$AK_P"
expect_eq "ASK-2 after the edit, units_field T2 deps answers the edit, as the reader's row reads it" "T1 T1" \
  "$(call units_field "$(ak_t2)" deps) $(bash -c '. "$1" && plan_read_row "$2" Tasks id T2' _ "${LIB%/*}/plan-read.sh" "$AK_P" | sed -n 's/^deps=//p')"
#
# A PROOF WAIT ASKS THE JUDGE. The floor row reads proof:review by its kind default; the review proof stands at
# an older head, and the rows the reads name have landed. Ready only when the judge reads the reviews covered.
# At 15: nine cells, T2 waiting on T1 by its id; the step, the approval, both landings and the review proof in the log.
AK_J="$SANDBOX/ask/plans/ask-judge.plan.md"; mkdir -p "${AK_J%/*}" "$SANDBOX/ask/record/ask-judge"
{ printf -- '---\ncanonical_sdlc_version: 15\n---\n\n## Tasks\n\n| id | step | kind | task | deps | size | serves | Files | artifact |\n'
  printf '|---|---|---|---|---|---|---|---|---|\n| T1 | 4 | build | b | — | 30m | R | src/a.sh | — |\n'
  printf '| T2 | 6 | review | r | T1 | 30m | R | .bionic/docs/record/w/r.md | — |\n| T3 | 6 | test | the floor | — | 30m | R | .bionic/docs/record/w/f.md | — |\n'
} > "$AK_J"
printf 'run/v1|ev=%s|at=2026-10-20T00:00:0%sZ\n' 'step|n=6' 1 'approval|key=step3|by=me|said=approved' 2 'published|row=T1' 3 'published|row=T2' 4 \
  "proof|kind=review|head=$(printf 'a%.0s' {1..40})|question=adversarial|result=pass|scope=piece" 5 > "$SANDBOX/ask/record/ask-judge/run.log"
ak_ready() { ( export UNITS_READINGS_STATE="$1"; call units_ready "$AK_J" 6 ); }
expect_eq "ASK-3 the floor row with the reviews covered at the head is ready; past the proof at an older head it is not" "T3|" \
  "$(ak_ready covered)|$(ak_ready 'review adversarial critic piece uncovered')"
# THE FIX POLICY IS THE HEADER'S: a `fix-policy:` line in the page's text below it is no policy, so the default stands.
printf -- '---\nrigor: double\n---\n\n# p\n\nfix-policy: S1\n' > "$AK_P"
expect_eq "ASK-4 a fix-policy: line below the header is not the plan's policy: the default answers" "S1,S2-on" \
  "$(bash -c '. "$1/units.sh" && . "$1/run.sh" && units_fix_policy "$2"' _ "${LIB%/*}" "$AK_P" 2>/dev/null)"

section "§LIVE — a row's state and agent are the run's: a launch in the log, on the plan and its dry copy"
LV_P="$SANDBOX/docs/plans/e/w.plan.md"; LV_LOG="$SANDBOX/docs/record/w/run.log"; mkdir -p "${LV_P%/*}" "${LV_LOG%/*}"
{ printf -- '---\ncanonical_sdlc_version: 15\n---\n\n## Tasks\n\n| id | step | kind | task | deps | size | serves | Files | artifact |\n|---|---|---|---|---|---|---|---|---|\n'
  printf '| T1 | 4 | build | one | — | 30m | R | a.sh | — |\n| T2 | 4 | build | two | — | 30m | R | b.sh | — |\n'; } > "$LV_P"
lv() { call units_rows "${2:-$LV_P}" | awk -F'\t' -v r="$1" '$1 == r { print $10 "/" $5 }'; }
lv_log() { bash -c '. "$1/log.sh" && RUN_LOG="$2" log_append "${@:3}"' _ "${LIB%/*}" "$LV_LOG" "$@"; }
# The run's step and approval, and T1's launch under a1, stand in the log before T2's launch.
printf 'run/v1|ev=%s|at=2026-11-01T00:00:0%s\n' 'step|n=4' 1Z 'approval|key=step3|by=me' 2Z > "$LV_LOG"
lv_log dispatch row=T1 name=a1 brief=b sum=s
lv_log dispatch row=T2 name=w-T2 brief=b sum=s
cp "$LV_P" "$LV_P.dry.1"
expect_eq "LIVE-2 a launch in the log reads active under its name, on the plan and its dry copy, and is not ready" \
  "active/w-T2 active/w-T2 active/a1|" "$(lv T2) $(lv T2 "$LV_P.dry.1") $(lv T1)|$(call units_ready "$LV_P" 4)"
call units_dispatch_back "$LV_P" T2 w-T2

section "§BORN — a row's birth is one born event in the run's log, and a marker in the page's text is none"
lv_ev() { bash -c '. "$1/reader.sh" && reader_facts "$2"' _ "${LIB%/*}" "$LV_P" | grep -c "^run/v1|ev=$1|.*row=$2|"; }
call units_born_event "$LV_P" T2 "review S1 on" "record/w/r.md#1"; BN_RC=$CALL_RC
call units_born_event "$LV_P" T1
expect_eq "BORN-1 the writer appends one born event per row, the reader lists each once" "0 1 1" "$BN_RC $(lv_ev born T2) $(lv_ev born T1)"
expect_eq "BORN-2 the cap's count, the findings and the marks read the review-born row from the log; the plain one is none of them" \
  "T2	S1 on	b.sh|T2	pending	record/w/r.md#1|T2	review	S1 on" \
  "$(call units_born "$LV_P")|$(call units_born_findings "$LV_P")|$(call units_born_marks "$LV_P")"
printf '\n## SDLC State\n\n- T1: born: review S2 on of=record/w/r.md#2\n' >> "$LV_P"
expect_eq "BORN-3 a born marker in the page's text, with no born event, is no born row: the born rows are the log's alone" \
  "T2	review	S1 on|T2	pending	record/w/r.md#1" "$(call units_born_marks "$LV_P")|$(call units_born_findings "$LV_P")"
sed -i.bak '/^## SDLC State$/,$d' "$LV_P"

section "§BACK — a launch taken back is the log's cancel, the plan untouched"
lv_log dispatch row=T2 name=w-T2b brief=b sum=s; BK_SUM="$(cksum < "$LV_P")"
call units_row_back "$LV_P" T2
expect_eq "BACK-1 a launch in the log returns to pending by one cancel, the plan untouched" "pending/ 1 same" \
  "$(lv T2) $(grep -c '|ev=cancel|of=dispatch|row=T2|name=w-T2b|' "$LV_LOG") $([ "$(cksum < "$LV_P")" = "$BK_SUM" ] && echo same)"

section "§TREE — a row's tree and base are the run's: the newest tree event in the log"
TV_P="$SANDBOX/docs/plans/e/t.plan.md"; LV_LOG="$SANDBOX/docs/record/t/run.log"; mkdir -p "${LV_LOG%/*}"
{ printf -- '---\ncanonical_sdlc_version: 15\n---\n\n## Tasks\n\n| id | step | kind | task | deps | size | serves | Files | artifact |\n|---|---|---|---|---|---|---|---|---|\n'
  printf '| T1 | 4 | build | one | — | 30m | R | a.sh | — |\n| T2 | 4 | build | two | — | 30m | R | b.sh | — |\n'; } > "$TV_P"
tv() { call units_rows "$TV_P" | awk -F'\t' -v r="$1" '$1 == r { print $10 "/" $5 "/" $11 "/" $12 }'; }
lv_log dispatch row=T1 name=a1 brief=b sum=s
lv_log tree row=T1 path=.worktrees/t1 branch=wt/t1 base=1111aaaa by=a1
TV_SUM="$(cksum < "$TV_P")"
lv_log tree row=T2 path=.worktrees/t2 branch=wt/t2 base=2222bbbbccccdddd by=w-T2
expect_eq "TREE-1 a tree in the log fills the row's tree and base, its state untouched, beside a launched row's own" \
  "pending//.worktrees/t2/2222bbbb active/a1/.worktrees/t1/1111aaaa" "$(tv T2) $(tv T1)"
lv_log dispatch row=T2 name=w-T2 brief=b sum=s
lv_log tree row=T2 path=.worktrees/t2b branch=wt/t2b base=3333eeee by=w-T2
expect_eq "TREE-2 with its launch it reads active under its name in its newest tree, and the plan is unchanged" \
  "active/w-T2/.worktrees/t2b/3333eeee same" "$(tv T2) $([ "$(cksum < "$TV_P")" = "$TV_SUM" ] && echo same)"

section "§LEDGER — a landed row with no line of its own is the reader's to answer: admitted when it answers landed"
LV_LOG="$SANDBOX/docs/record/w/run.log"; call units_dispatch_back "$LV_P" T1 a1; lv_log published row=T2 commit=abcdef1 by=w-T2b
expect_eq "LEDGER-1 T2 landed by its event, with no line in the plan, owes nothing: the reader answers landed" "landed|" "$(lv T2 | cut -d/ -f1)|$(call units_findings "$LV_P")"

section "§DROP — a drop in the run's log is the row's one answer at 15: dropped for the reader and the fill, holding no slot, a wait on it met"
DP="$SANDBOX/docs/plans/e/d.plan.md"; LV_LOG="$SANDBOX/docs/record/d/run.log"; mkdir -p "${LV_LOG%/*}"; dq() { bash -c '. "$1/reader.sh" && reader_main "$2" "${@:3}"' _ "${LIB%/*}" "$DP" "$@"; }
printf -- '---\ncanonical_sdlc_version: 15\n---\n## Tasks\n| id | step | kind | task | deps | size | serves | files | artifact |\n|---|---|---|---|---|---|---|---|---|\n%s\n%s\n%s\n' '| T1 | 4 | build | one | — | 30m | R | a.sh | — |' '| T2 | 4 | build | two | T1 | 30m | R | b.sh | — |' '| T3 | 4 | build | three | — | 30m | R | c.sh | — |' > "$DP"
printf 'run/v1|ev=%s|at=2026-11-01T00:00:0%s\n' 'step|n=4' 1Z 'approval|key=step3|by=me' 2Z 'dispatch|row=T3|name=w-T3|brief=b|sum=s' 3Z 'drop|row=T1|why=no longer owed' 4Z 'drop|row=T3|why=no longer owed' 5Z > "$LV_LOG"
expect_eq "DROP-1 T1 and T3, one of them launched, read dropped by the reader and the fill; T2's wait on T1 is met, the only row ready" \
  "state=dropped state=dropped dropped/ dropped/w-T3|T2|ready=T2" "$(dq status T1 | head -1) $(dq status T3 | head -1) $(lv T1 "$DP") $(lv T3 "$DP")|$(call units_ready "$DP" 4)|$(dq stop | grep '^ready=')"
call units_drop_event "$DP" T2 'the person said so'; DP_RC=$CALL_RC; call units_drop_event "$DP" T2 'a|b'
expect_eq "DROP-2 the one writer appends the person's words, and refuses words holding a bar" "0 2 1 state=dropped" "$DP_RC $CALL_RC $(grep -c '|ev=drop|row=T2|why=the person said so|at=' "$LV_LOG") $(dq status T2 | head -1)"

section "§UNTIMED — a dispatch with no instant, in the one row fold: the reader's dispatched while no other fact of its row stands, never the fill's launch"
printf 'run/v1|ev=%s\n' 'step|n=4|at=2026-11-01T00:00:01Z' 'published|row=T2|commit=c2|by=w|at=2026-11-01T00:00:02Z' 'dispatch|row=T1|name=a1|brief=b|sum=s' 'dispatch|row=T2|name=a2|brief=b|sum=s' > "$LV_LOG"
expect_eq "UNTIMED-1 alone it reads dispatched and after a landing landed, and the fill holds neither launched" "state=dispatched state=landed pending/ landed/" "$(dq status T1 | head -1) $(dq status T2 | head -1) $(lv T1 "$DP") $(lv T2 "$DP")"
printf 'run/v1|ev=%s\n' 'tree|row=T1|path=/x/t1|branch=wt/t1|base=aaaaaaaaaaaa' 'tree|row=T2|path=/x/t2|branch=wt/t2|base=bbbbbbbbbbbb|at=2026-11-01T00:00:03Z' >> "$LV_LOG"
expect_eq "UNTIMED-2 a tree line with no instant is the reader's tree and never the fill's; one with its instant is both" "tree=/x/t1 tree=/x/t2 T1:/ T2:/x/t2/bbbbbbbb" \
  "$(dq status T1 | grep '^tree=') $(dq status T2 | grep '^tree=') $(call units_rows "$DP" | awk -F'\t' '$1 == "T1" || $1 == "T2" { printf "%s%s:%s/%s", s, $1, $11, $12; s = " " }')"

section "§NAMED — a task at 15 names in its deps the approval it waits on: admitted, held until it stands, its name the one approve takes"
sed 's/| T1 | 30m/| T1, approval:D7 | 30m/' "$DP" > "$DP.n"; mv "$DP.n" "$DP"; sed 's/approval:D7/aproval:D7/' "$DP" > "$DP.bad"; printf 'run/v1|ev=%s|at=2026-11-01T00:00:0%s\n' 'step|n=4' 1Z 'approval|key=step3|by=me' 2Z 'published|row=T1|commit=c1|by=w' 3Z > "$LV_LOG"
expect_eq "NAMED-1 the wait is admitted; a misspelled one is refused, naming it" "|T2: dep aproval:D7 names no row in the table" "$(call units_validate "$DP")|$(call units_validate "$DP.bad")"
NM_A="$(call units_ready "$DP" 4)|$(dq stop | grep '^ready=')|$(call units_approval_names "$DP" | paste -sd' ' -)"; printf 'run/v1|ev=approval|key=D7|by=me|at=2026-11-01T00:00:04Z\n' >> "$LV_LOG"
expect_eq "NAMED-2 the fill and the reader hold T2 while D7 is absent and ready it once it stands; D7 is the name approve takes" "T3|ready=T3|D7 plan T2 T3|ready=T2 T3" "$NM_A $(call units_ready "$DP" 4 | paste -sd' ' -)|$(dq stop | grep '^ready=')"
expect_eq "NAMED-7 asked for one task, its names alone; a plan it cannot read is a failure it returns, where the whole list answers nothing" "D7 plan|1|0" "$(call units_approval_names "$DP" T2 | paste -sd' ' -)|$(call_rc units_approval_names "$DP.none" T2)|$(call_rc units_approval_names "$DP.none")"
printf 'run/v1|ev=%s|at=2026-11-01T00:00:0%s\n' 'step|n=2' 1Z 'approval|key=step3|by=me' 2Z > "$LV_LOG"
expect_eq "NAMED-4 every task waits on the plan's approval by its kind: with the run at step 2, the fill offers none at step 4, as the reader offers none" "|ready=" "$(call units_ready "$DP" 4)|$(dq stop | grep '^ready=')"
RP="$SANDBOX/docs/plans/e/r.plan.md"; LV_LOG="$SANDBOX/docs/record/r/run.log"; mkdir -p "${LV_LOG%/*}"; rw() { call units_waiting "$RP" 8 | awk -F'\t' '$2 ~ /^approval:/ { print $1 " " $2 }'; }
sed 's/| T2 | 4 | build | two | T1, approval:D7 |/| T2 | 8 | integrate | two | approval:release |/' "$DP" > "$RP"; printf 'run/v1|ev=%s|at=2026-11-01T00:00:0%s\n' 'step|n=8' 1Z 'approval|key=step3|by=me' 2Z 'published|row=T1|commit=c1|by=w' 3Z > "$LV_LOG"; RW_A="$(rw)"; sed -i.bak 's/| approval:release |/| — |/' "$RP"
expect_eq "NAMED-6 with no release row an integrate task waits on the release approval it names, never on the one its kind implies" "T2 approval:release|" "$RW_A|$(rw)"
expect_eq "NAMED-3 the stop wall's edit that makes a row wait names the deps cell and a row's id at 15" "deps RID" "$(bash -c '. "$1/stop.sh" && stop_wait_cell "$2"' _ "${LIB%/*}" "$DP")"

section "§ORDER-15 — the order and its exception past the release: a row is open unless the run's log lands or drops it, and the fix read as a piece is the reader's waits"
# shellcheck disable=SC2086
o5 $O5_REG $O5_REV $O5_REL; o5log
expect_eq "ORD15-1 control: regression at 5, review at 6, release at 7, all open: admitted (rc 0)" "|0" "$(ov)"
# shellcheck disable=SC2086
o5 $O5_REV $O5_REL ${O5_REG/ 5 / 7 }; O5_A="$(ov)"; o5log 'published|row=T5|commit=c1|by=w' 'published|row=T6|commit=c2|by=w' 'published|row=T7|commit=c3|by=w'; O5_B="$(ov)"; o5log 'drop|row=T5|why=not owed'
expect_eq "ORD15-2 the regression after the review: refused with the order's own words (rc 1); every row landed, or the regression dropped: not judged" "$OR_REGLINE|1 |0 |0" "$O5_A $O5_B $(ov)"
# shellcheck disable=SC2086
o5 $O5_REG $O5_REL ${O5_REV/ 6 / 7 }; o5log
expect_eq "ORD15-3 the release ahead of a review: refused with the order's own words (rc 1)" \
  "T7: the release row comes ahead of the review row T6; the order is build, regression, review, release: put T7 at step 7, after T6|1" "$(ov)"
# shellcheck disable=SC2086
o5 T1 4 build — a.sh $O5_REG $O5_REV $O5_REL T8 7 build — b.sh T9 7 review T8 r/T9.md; o5log 'published|row=T1|commit=c1|by=w' 'published|row=T5|commit=c2|by=w' 'published|row=T6|commit=c3|by=w'
O5_A="$(ov)"; printf 'run/v1|ev=published|row=T7|commit=c4|by=w|at=2026-11-01T00:00:01Z\n' >> "$O5_LOG"; O5_B="$(ov)"; sed -i.bak 's/| review | t | T8 |/| review | t | T1 |/' "$O5"
expect_eq "ORD15-4 a review past the release waiting on the fix T8: refused while the release is open, admitted once the log lands it, refused when it waits on T1 written before it" \
  "$PO_ORD|1 |0 $PO_ORD|1" "$O5_A $O5_B $(ov)"
# shellcheck disable=SC2086
o5 $O5_REV ${O5_REG/ 5 / 6 } $O5_REL; o5log
expect_eq "ORD15-6 the regression at the review's step, after it in the table: refused with the order's own words (rc 1)" "$OR_REGLINE|1" "$(ov)"
# shellcheck disable=SC2086
o5 T1 4 build — a.sh $O5_REG $O5_REV $O5_REL T8 7 build — b.sh T9 7 review — r/T9.md
o5log 'published|row=T1|commit=c1|by=w' 'published|row=T5|commit=c2|by=w' 'published|row=T6|commit=c3|by=w' 'published|row=T7|commit=c4|by=w'; O5_A="$(ov)"
# shellcheck disable=SC2086
o5 T1 4 build — a.sh $O5_REG $O5_REV $O5_REL T8 7 build — b.sh T9 7 review 'T8, T6' r/T9.md
expect_eq "ORD15-7 the release landed, a review past it that names no row it waits on, or the fix and a reading written before the release: refused each (rc 1)" \
  "$PO_ORD|1 $PO_ORD|1" "$O5_A $(ov)"
# shellcheck disable=SC2086
o5 T1 4 build — a.sh $O5_REG $O5_REV $O5_REL T8 7 build — b.sh T9 7 review T8 r/T9.md; O5_A="$(call units_post_readers "$O5")"; sed -i.bak 's/| review | t | T8 |/| review | t | T1 |/' "$O5"
expect_eq "ORD15-5 the card's question at 15, as release-approval's §POST asks it at 14: the review past the landed release waiting on the fix is named, open and unread; waiting on T1 it is not" \
  "T9	pending	unread|" "$O5_A|$(call units_post_readers "$O5")"

section "§DEPS-15 — a row at 15 waits by its deps and its kind's default alone: no step hold, the release approval once, the questions tag judged at the write"
W5="$SANDBOX/docs/plans/e/w5.plan.md"; mkdir -p "$SANDBOX/docs/record/w5"
W5_ROWS=(T2 4 build two T3 b.sh T3 4 build three — c.sh T12 4 build late — e.sh T5 5 test reg — r/T5.md T6 6 review 'rev · questions: evidence' — r/T6.md T9 7 doc rel — CHANGELOG.md T10 8 integrate merge approval:release r/T10.md)
printf -- '---\ncanonical_sdlc_version: 15\n---\n## Tasks\n| id | step | kind | task | deps | size | serves | files | artifact |\n|---|---|---|---|---|---|---|---|---|\n' > "$W5"; printf '| %s | %s | %s | %s | %s | 30m | R | %s | — |\n' "${W5_ROWS[@]}" >> "$W5"
printf 'run/v1|ev=%s|at=2026-11-01T00:00:0%s\n' 'step|n=6' 1Z 'approval|key=step3|by=me' 2Z > "$SANDBOX/docs/record/w5/run.log"
w9() { printf '%s %s' "$(call units_waiting "$1" 6 | awk -F'\t' '$1 == "T9" { print $2 }' | sort -u | paste -sd' ' -)" "$(call plan_read_waits "$1" T9 | awk -F'\t' '$2 == "wait" { print $3 }' | paste -sd' ' -)"; }
expect_eq "DEPS-2 the release text at 15 waits on what it reads and on no step, for the fill and the reader" \
  "head approval:plan" "$(w9 "$W5")"
expect_eq "DEPS-4 an integrate row at 15 whose deps name the release approval waits on it once" \
  "proof:regression,proof:review,head,approval:release" "$(call plan_read_waits "$W5" T10 | head -1 | cut -f4)"
DQ_TAIL="which is no list of questions: each one of evidence adversarial structure, once, comma-separated with no space"; DQ_OUT="$(call units_validate "$W5"; printf '|%s' "$CALL_RC")"
for v in 's/: evidence |/: evidense |/' 's/: evidence |/: |/' 's/: evidence |/: evidence,evidence |/' 's/| three |/| three · questions: structure |/'; do sed "$v" "$W5" > "$W5.v"; DQ_OUT="$DQ_OUT $(call units_validate "$W5.v")"; done
expect_eq "DEPS-5 at 15 the validator holds the questions tag to the verb's rule: a word outside the set, an empty tag, a question twice, a tag on a row no review" \
  "|0 T6: task declares questions: evidense, $DQ_TAIL T6: task declares questions: (empty), $DQ_TAIL T6: task declares questions: evidence,evidence, $DQ_TAIL T3: task declares questions: structure; only a review row is dealt questions" "$DQ_OUT"

finish
