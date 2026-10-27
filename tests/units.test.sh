#!/bin/bash
# tests/units.test.sh — payload/scripts/lib/units.sh: THE ONE READER OF `## Tasks`
# (epic-23 wave-11-lean-spine, REQ-1e; AC-1e.1/1e.2; spec Design §1 "Task", §2 D3/D7).
#
# WHAT IT OWNS. The contract three callers bind to after T8 — the evidence gate's ledger
# checks and its prototype check, the tick's FILL, and the governing-skill Step-3 wall — so
# that none of them carries a parser of its own. The questions, one per section:
#
#   §1 units_rows <plan>          the thirteen fields, in the FIXED order, whatever order the
#                                 table's columns are written in; the `worktree` cell (slot 11)
#                                 and the `base` cell (slot 12) are OPTIONAL, a table without the
#                                 column is valid and reads it empty, and `base` is a commit id
#                                 when it holds one
#   §2 header names               reversed columns give identical output
#   §3 the ## Tasks section       is read, and nothing else
#   §4 units_ready <plan> <step>  which rows at that step may be dispatched now
#   §5 units_validate <plan>      the live table is the clean case
#   §6 units_validate <plan>      one line per broken invariant, naming the id and the rule
#   §7 units_validate <plan>      a missing column is a violation of the table, not of a row
#   §8 the differential           the old fill derivation and units_ready answer the same
#   §9 a markdown-escaped pipe    in a cell
#   §ORDER   build, regression, review, release: units_validate refuses any other order naming the
#            rows; units_order reads it
#   §POST    a review row after a landed release is admitted when it reads only approval:plan, head
#            and the rows landed past the release
#   §AFTER-PUBLISH  after the release is the record's publish order: a step-4 fix row published past the release
#            is read as a piece; the record's order reversed refuses; no record falls back to the plan's order
#   §JUDGE   covered at the last green whole run's head; past it each commit owes its row's suites,
#            never a second whole run
#   §WALK    the regression walk excuses a real release merge whose check passed, as the judge's
#            cover reads it
#   §SECOND  regression-run at a head past the plan's whole run refuses a second whole run in one
#            line with nothing run, and at the head the whole run read it does not refuse
#   §STEP-FIELD  units_step_field reads the first key line of the block units_step_fields writes
#   §DEBT    a review-born row inside fix-policy: is exempt from fix-cap:, a promoted or carried one counts;
#            task-add's cap refusal, its fourth-fix refusal and its count line each go red when removed
#
# WHY HEADER-KEYED IS THE WHOLE POINT (AC-1e.2, measure §4.3). Before this library two
# readers in hooks/canonical-sdlc-evidence-gate.sh took `id`/`rigor`/`status` as awk fields
# `$2`/`$4`/`$6` of a five-column table. The ten-column table this wave ships puts `agent`
# at `$6` and `kind` at `$4`, so both readers would have read an agent name as a status and
# refused every row — on this wave's own plan, at its own next commit. A reader keyed on
# the header CELL TEXT cannot be broken by inserting, moving or renaming a column it does
# not read, which is what makes the schema an ordinary edit again. §2 is that assertion:
# the same rows with every column REVERSED must produce a byte-identical TSV.
#
# FIXTURE PROVENANCE — NOT HAND-TYPED (fixture fidelity). The table in `tasks_table` below
# was spliced verbatim out of this wave's own live plan,
# `.bionic/docs/plans/epic-23-bionic-tech-debt/wave-11-lean-spine.plan.md`, at the `## Tasks`
# heading, at commit 1f48673 — header, separator and all 22 data rows, byte for byte. The
# plan tree is gitignored and absent from a worktree, so the specimen has to live in the
# suite; copying it by hand is how a fixture comes to test its own typing instead of the
# reader. Every other fixture here is built FROM that one by a name-blind transform (§2
# reverses cell order; §3 wraps it in decoys) or is a small purpose-built table (§4, §5).
#
# THE REVERSAL IS NAME-BLIND, DELIBERATELY (§2). A permuter that re-ordered columns BY NAME
# would be a second implementation of the thing under test, and a shared misreading of a
# header cell would cancel out and show green. Reversing the cells of every row of the table
# — header, separator and data alike — cannot know what any column is called, so the two
# sides of the §2 comparison have no common machinery at all.
#
# HERMETIC. Every fixture is a file under one mktemp sandbox; nothing reads the repository's
# own plans, no hook runs, and the library is sourced in a CHILD shell per call so no row can
# be answered by a function an earlier row left defined in this one.
# §WALK alone is live tier: it reads this repository's own release merges, read-only, and skips
# by version and hash a merge the history does not hold.
#
# Usage: bash tests/units.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
LIB="$REPO_ROOT/payload/scripts/lib/units.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/units-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

# call <fn> <args...> — the library in a child shell. Prints the function's stdout; its exit
# status is left in CALL_RC. A missing or unparsable library yields empty output and a
# non-zero CALL_RC, which is what makes the RED run of this suite red for the right reason
# rather than killing it.
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

# ============================================================
setup_section "0s — the fixtures"
# ============================================================

# THE SPECIMEN, verbatim from the live plan (see FIXTURE PROVENANCE above).
cat > "$SANDBOX/tasks-table.md" <<'TASKS_TABLE_EOF'
| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 3 | doc | Plan, Tasks and matrix written; Step-3 card approved | orchestrator | — | 30m | all | plan | landed |
| T2 | 4 | build | 1d: `disable-model-invocation: true` on the five command templates; re-render; frontmatter pin | orchestrator | T1 | 15m | REQ-1d | agents-src/templates/commands/*.tmpl, payload/commands/*.md, payload/integrity/rendered.sha256, tests/docs-pins.test.sh | landed |
| T3 | 4 | build | 1c-a: survival renders once to payload/context/survival.md; auditor mandate moved the same way; role templates ≤5 KB with a one-line pointer; §5 writer rules as defaults; PIPESTATUS fixed; six pins re-pointed | senior-implementor | T1 | 60m | REQ-1c | agents-src/blocks/survival.md, agents-src/templates/*.md.tmpl, agents-src/render.sh, agents/*.md, payload/context/survival.md, tests/docs-pins.test.sh, tests/render.test.sh, payload/integrity/rendered.sha256 | landed |
| T4 | 4 | build | 1c-b: SubagentStart hook injects survival for bionic:* agents, self-attributed first line; stdout-equals-file pin | implementor | T3 | 45m | REQ-1c | hooks/execution-recorder.sh, tests/execution-recorder.test.sh | landed |
| T5 | 4 | build | 1b: core + steps/0–9 + dispatch.md from the template; render.sh unit rows; 168 pins re-pointed, 4 structural ones rewritten; prune to caps; session-start pointer line | senior-implementor | T1 | 120m | REQ-1b | agents-src/templates/skills/canonical-sdlc/, agents-src/render.sh, skills/canonical-sdlc/, tests/docs-pins.test.sh, tests/render.test.sh, payload/integrity/rendered.sha256, hooks/session-start.sh | landed |
| T6 | 4 | build | 1a: three prose surfaces re-pointed to record/ paths; evidence-gate fixtures (path-cited ≤40 KB passes; empty evidence value fails) | implementor | T3, T5 | 45m | REQ-1a | agents-src/blocks/critic-template.md, agents-src/templates/senior-implementor.md.tmpl, agents-src/templates/skills/canonical-sdlc/steps/, tests/canonical-sdlc-evidence-gate.test.sh | active |
| T7 | 4 | build | 1e-a: lib/units.sh (units_rows, units_ready, units_validate) TDD from tests/units.test.sh; domain dictionary entry | senior-implementor | T1 | 60m | REQ-1e | payload/scripts/lib/units.sh, tests/units.test.sh, design/domain-dictionary.md | active |
| T8 | 4 | build | 1e-b: callers onto units.sh (gate ledger checks + prototype check, tick FILL, governing-skill Step-3 wall); the retired word becomes task; fixtures migrated; differential vs old parsers on the specimen plan | senior-implementor | T7 | 120m | REQ-1e | hooks/canonical-sdlc-evidence-gate.sh, hooks/session-poker.sh, hooks/canonical-sdlc-governing-skill.sh, hooks/dispatch-preflight.sh, tests/canonical-sdlc-evidence-gate.test.sh, tests/session-poker.test.sh, tests/canonical-sdlc-governing-skill.test.sh, tests/docs-pins.test.sh, agents-src/ | pending |
| T9 | 4 | build | 1f-a: delete hooks/stop-check.sh and every reference; remove the seven dead functions | implementor | T8 | 30m | REQ-1f | hooks/stop-check.sh, hooks/stop-guard.sh, payload/scripts/lib/, tests/ | pending |
| T10 | 4 | build | 1f-b: lib/context.sh with bionic_context; fifteen hooks call it; no-inline-sequence pin | senior-implementor | T9 | 90m | REQ-1f | payload/scripts/lib/context.sh, hooks/*.sh, tests/cross-gate-agreement.test.sh | pending |
| T11 | 4 | build | 1f-c: loader block ≤95 lines in loader.sh's heredoc and all 21 hooks; §N.1 pin and mutation arm green | senior-implementor | T10 | 60m | REQ-1f | payload/scripts/lib/loader.sh, hooks/*.sh, tests/cross-gate-agreement.test.sh | pending |
| T12 | 4 | build | 1f-d: context-spend suite first (RED); lib/stop.sh four functions; hooks/stop.sh on Stop + SubagentStop with fold; differential vs the four originals; hooks.json ≤12 command objects | senior-implementor | T11 | 150m | REQ-1f | payload/scripts/lib/stop.sh, hooks/stop.sh, hooks/hooks.json, hooks/context-spend.sh, hooks/landing-gate.sh, hooks/patrol-duties-gate.sh, hooks/patrol-revive.sh, tests/stop.test.sh, tests/context-spend.test.sh, tests/ | pending |
| T13 | 5 | verify | Walk: an agent that has not read the ACs drives the candidate by plugin-dir in a throwaway project and narrates; record/wave-11-lean-spine/walk.md | researcher | T2, T4, T5, T6, T8, T12, T22 | 30m | all | record/wave-11-lean-spine/walk.md | pending |
| T14 | 5 | test | Tests floor: bash tests/run.sh in the wave worktree; census commands re-run; evidence/floor.md | test-runner | T2, T4, T5, T6, T8, T12, T22 | 40m | all | record/wave-11-lean-spine/evidence/floor.md | pending |
| T15 | 5 | verify | Discharge the matrix: 22 static pins, 12 hermetic rows, 6 live drives; one evidence file per AC | orchestrator | T13, T14 | 90m | all | record/wave-11-lean-spine/evidence/ | pending |
| T16 | 5 | verify | Auditor on the REQ-1e and REQ-1f rows (double) and the wave verdict | auditor | T15 | 45m | REQ-1e, REQ-1f | record/wave-11-lean-spine/auditor.md | pending |
| T17 | 6 | review | Six-axis self-review, one reviewer per axis in parallel at exec-complex | orchestrator | T16 | 45m | all | record/wave-11-lean-spine/review/ | pending |
| T18 | 6 | review | Critic on T7–T12 (double rows) | critic | T17 | 45m | REQ-1e, REQ-1f | record/wave-11-lean-spine/critic.md | pending |
| T19 | 7 | doc | ADRs 001–004; spec adrs: pointer | orchestrator | T18 | 30m | D1, D3, D4, D5 | adrs/epic-23-bionic-tech-debt/ | pending |
| T20 | 8 | integrate | Wake Note, then attended no-ff merge to main; writer worktrees and the wave worktree removed; tmp ephemera wiped | orchestrator | T19 | 20m | all | none | pending |
| T22 | 4 | build | 1g: fix the doctor/setup agreement on the `motion` row so DS.2a/2c/9/11 pass on this machine; honour the 2026-08-22 ruling | senior-implementor | T1 | 60m | REQ-1g | payload/scripts/lib/deps.sh, payload/scripts/doctor.sh, payload/scripts/setup.sh, tests/cross-gate-agreement.test.sh | landed |
| T21 | 9 | close | Close-out report with dispositions; continuation.md; archive_run; Patrol CronDelete + disarm | orchestrator | T20 | 30m | all | record/wave-11-lean-spine/closeout-report.md | pending |
TASKS_TABLE_EOF

# live.md — the specimen in the shape a plan actually presents it: frontmatter, the SDLC
# state section, the table under its own heading, and a following `## Verification Matrix`
# that the reader must stop at.
{
  printf -- '---\ncurrent: 4\nwave: wave-11-lean-spine\n---\n\n'
  printf -- '## SDLC State\n\n- Step 4: in flight\n\n'
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
  printf -- '---\ncurrent: 4\n---\n\n## Tasks\n\n'
  cat "$SANDBOX/tasks-table-reversed.md"
  printf -- '\n## Verification Matrix\n'
} > "$SANDBOX/reordered.md"

# decoys.md — a table under the RETIRED section heading BEFORE the real one, and a fenced
# example table AFTER it. Neither is the plan's schedule; a reader that keyed on header
# names alone, or that ignored fences, would take one of them for the table. The heading
# literal below is the retired word, kept on purpose: this fixture is what proves the
# reader refuses it.  # retired: slice
{
  printf -- '---\ncurrent: 4\n---\n\n'
  printf -- '## Slices (machine-readable)\n\n'  # retired: slice
  printf -- '| id | deps | complexity | status |\n|---|---|---|---|\n'
  printf -- '| S1 | — | complex | landed |\n| S2 | S1 | standard | pending |\n\n'
  printf -- '## Tasks\n\n'
  cat "$SANDBOX/tasks-table.md"
  printf -- '\n## Notes\n\nThe schema, for a reader:\n\n```\n'
  printf -- '| id | step | kind | task | agent | deps | size | serves | Files | status |\n'
  printf -- '|---|---|---|---|---|---|---|---|---|---|\n'
  printf -- '| T99 | 4 | build | example row | implementor | — | 1m | none | none | pending |\n'
  printf -- '```\n'
} > "$SANDBOX/decoys.md"

# ready-a.md — one step, one blocked row. T2 landed; T4 depends on T3, which is pending.
cat > "$SANDBOX/ready-a.md" <<'READY_A_EOF'
---
current: 4
---

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 3 | doc | plan written | orchestrator | — | 30m | all | plan | landed |
| T2 | 4 | build | already landed | implementor | T1 | 15m | REQ-x | a.sh | landed |
| T3 | 4 | build | free to go | implementor | T1 | 15m | REQ-x | b.sh | pending |
| T4 | 4 | build | blocked behind T3 | implementor | T3 | 15m | REQ-x | c.sh | pending |
| T5 | 4 | build | free to go | implementor | T2 | 15m | REQ-x | d.sh | pending |
READY_A_EOF

# ready-b.md — every Step-4 row landed, three Step-5 rows, written OUT OF ID ORDER so that
# "table order" is a different answer from "sorted by id". T6 names a dependency the table
# does not carry.
cat > "$SANDBOX/ready-b.md" <<'READY_B_EOF'
---
current: 5
---

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 3 | doc | plan written | orchestrator | — | 30m | all | plan | landed |
| T2 | 4 | build | landed | implementor | T1 | 15m | REQ-x | a.sh | landed |
| T3 | 4 | build | landed | implementor | T1 | 15m | REQ-x | b.sh | landed |
| T7 | 5 | verify | the walk | researcher | T2, T3 | 30m | all | walk.md | pending |
| T6 | 5 | verify | names a dep nobody defines | researcher | T2, T3, T9 | 30m | all | x.md | pending |
| T5 | 5 | test | the floor | test-runner | T2, T3 | 40m | all | floor.md | pending |
READY_B_EOF

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
| T5 | 4 | build | a status nobody defines | implementor | — | 15m | REQ-x | f.sh | done |
| T6 | 4 | build | a dep naming no row | implementor | T99 | 15m | REQ-x | g.sh | pending |
| T7 | 6 | review | reaches only T1 | critic | T1 | 15m | REQ-x | h.sh | pending |
BROKEN_EOF

# missing-column.md — the ten-column schema with `step` deleted. AC-1e.5's third case.
cat > "$SANDBOX/missing-column.md" <<'MISSING_EOF'
---
current: 4
---

## Tasks

| id | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|
| T1 | build | no step column anywhere | implementor | — | 15m | REQ-x | a.sh | pending |
MISSING_EOF

# no-table.md — a plan with no `## Tasks` at all.
printf -- '---\ncurrent: 4\n---\n\n## SDLC State\n\n- Step 4: in flight\n' > "$SANDBOX/no-table.md"

ROWS_LIVE="$(call units_rows "$SANDBOX/live.md")"

# ============================================================
section "1 — units_rows: the live table, thirteen fields per row, in the fixed order"
# ============================================================

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

# THE COLLISION measure §4.3 names, asserted field by field. In the shipped five-column
# table `$6` was the status; here it is the agent, and a positional reader reads
# `implementor` as a status and refuses the row.
T2_LINE="$(printf '%s\n' "$ROWS_LIVE" | awk -F'\t' '$1 == "T2"')"
expect_eq "T2 field 5 is the agent, not the status" "orchestrator" \
  "$(printf '%s\n' "$T2_LINE" | cut -f5)"
expect_eq "T2 field 6 is deps"   "T1"     "$(printf '%s\n' "$T2_LINE" | cut -f6)"
expect_eq "T2 field 10 is status" "landed" "$(printf '%s\n' "$T2_LINE" | cut -f10)"
expect_eq "T2 field 2 is the step" "4"     "$(printf '%s\n' "$T2_LINE" | cut -f2)"
expect_eq "T2 field 3 is the kind" "build" "$(printf '%s\n' "$T2_LINE" | cut -f3)"

# `Files` is read case-insensitively on the header cell — it is the one capitalised header
# in the shipped table, and a case-sensitive reader drops the column silently.
expect_contains "T2 field 9 is the Files cell, matched case-insensitively on the header" \
  "payload/integrity/rendered.sha256" "$(printf '%s\n' "$T2_LINE" | cut -f9)"

# A MULTI-ID DEPS CELL survives whole; splitting is units_ready's job, not units_rows'.
expect_eq "T13's deps cell comes through unsplit" "T2, T4, T5, T6, T8, T12, T22" \
  "$(printf '%s\n' "$ROWS_LIVE" | awk -F'\t' '$1 == "T13"' | cut -f6)"

expect_eq "T7's status is read from the last column" "active" \
  "$(printf '%s\n' "$ROWS_LIVE" | awk -F'\t' '$1 == "T7"' | cut -f10)"

# TABLE ORDER, NOT ID ORDER. The live plan carries T22 before T21; a reader that sorted
# would answer the dispatch question in an order the orchestrator did not choose.
expect_eq "rows come out in TABLE order — T22 is 21st and T21 is 22nd" "T22 T21" \
  "$(printf '%s\n' "$ROWS_LIVE" | sed -n '21p;22p' | cut -f1 | tr '\n' ' ' | sed 's/ $//')"

# The separator row and the trailing prose are not rows.
expect_eq "no separator or prose line is emitted as a row" "" \
  "$(printf '%s\n' "$ROWS_LIVE" | awk -F'\t' '$1 ~ /^[-: ]*$/ || $1 ~ /Parallel/')"

# ============================================================
section "2 — units_rows is keyed on header NAMES: reversed columns, identical output (AC-1e.2)"
# ============================================================

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
# through this library. One ledger shape deleted that reader and that table: a task-scale plan
# carries the one `## Tasks` table, whose slot 3 is `kind`. The retired table below still parses
# by its header — its id and status read by name — and its `rigor` column now reaches no slot.
cat > "$SANDBOX/task-scale-ledger.md" <<'TASK_SCALE_EOF'
---
scale: task
current: T2
---

## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | bugfix | single | fix the frontmatter parser | done |
| T2 | refactor | double | extract the ledger helper | active |
| T3 | refactor |  | inherits the frontmatter rigor | pending |
TASK_SCALE_EOF

ROWS_TASK_SCALE="$(call units_rows "$SANDBOX/task-scale-ledger.md")"
expect_eq "the five-column task-scale ledger yields its three rows" "3" "$(nlines "$ROWS_TASK_SCALE")"
expect_eq "…id from slot 1 and status from slot 10, by header name" \
  "T1 done
T2 active
T3 pending" \
  "$(printf '%s\n' "$ROWS_TASK_SCALE" | awk -F'\t' '{ print $1, $10 }')"
expect_eq "…and its rigor column reaches no slot: slot 3 reads empty on every row" \
  "[][][]" \
  "$(printf '%s\n' "$ROWS_TASK_SCALE" | awk -F'\t' '{ printf "[%s]", $3 }')"
expect_eq "units_field takes the row's id and status by name" "T2 active" \
  "$(bash -c '. "$1" >/dev/null 2>&1 || exit 127
     row="$(units_rows "$2" | sed -n 2p)"
     printf "%s %s" "$(units_field "$row" id)" "$(units_field "$row" status)"' \
     _ "$LIB" "$SANDBOX/task-scale-ledger.md")"
expect_eq "…and refuses rigor, a name the contract no longer carries (rc 1)" "1" \
  "$(bash -c '. "$1" >/dev/null 2>&1 || exit 127
     row="$(units_rows "$2" | sed -n 2p)"
     units_field "$row" rigor >/dev/null; echo $?' \
     _ "$LIB" "$SANDBOX/task-scale-ledger.md")"
expect_eq "…and refuses a column name the contract does not carry" "1" \
  "$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; units_field "x" intent' _ "$LIB" >/dev/null 2>&1; echo $?)"
expect_eq "an empty cell reads empty, not as the cell after it" "" \
  "$(printf '%s\n' "$ROWS_TASK_SCALE" | sed -n 3p | awk -F'\t' '{ print $3 }')"

# ============================================================
section "3 — units_rows reads the ## Tasks section and nothing else"
# ============================================================

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

# ============================================================
section "4 — units_ready: pending and every dep landed; the step is a label (wave-20 Δ1)"
# ============================================================
#
# RE-AUTHORED FOR wave-20 REQ-5 (Δ1, ADR-036). Through 1.8.6 the step argument FILTERED: a
# row was ready only at its own step. Readiness is now the prerequisite graph — a work row is
# ready when it is pending and every prerequisite has landed, whatever its step — so the
# argument no longer filters a work row. It still decides the gate-act rows (§17).

expect_eq "step 4: a row whose dep is still pending is not ready, and its siblings are" \
  "$(printf 'T3\nT5')" "$(call units_ready "$SANDBOX/ready-a.md" 4)"
expect_eq "…so T4, blocked behind pending T3, is absent" "" \
  "$(call units_ready "$SANDBOX/ready-a.md" 4 | grep -x T4)"
expect_eq "…and T2, already landed, is not offered again" "" \
  "$(call units_ready "$SANDBOX/ready-a.md" 4 | grep -x T2)"
expect_eq "…and asked at step 3 the same rows are ready: the argument is not a filter (Δ1)" \
  "$(printf 'T3\nT5')" "$(call units_ready "$SANDBOX/ready-a.md" 3)"

expect_eq "step 5 with every Step-4 row landed: the ready rows, in TABLE order" \
  "$(printf 'T7\nT5')" "$(call units_ready "$SANDBOX/ready-b.md" 5)"
expect_eq "…a dep naming an id the table does not carry is never ready" "" \
  "$(call units_ready "$SANDBOX/ready-b.md" 5 | grep -x T6)"
expect_eq "…asked at step 4 the Step-5 rows are still ready: their deps landed (Δ1)" \
  "$(printf 'T7\nT5')" "$(call units_ready "$SANDBOX/ready-b.md" 4)"
expect_eq "…and at step 9 too: no work row waits for the run to reach its step" \
  "$(printf 'T7\nT5')" "$(call units_ready "$SANDBOX/ready-b.md" 9)"

# A `—` deps cell names no dependency; so do `-` and an empty cell.
cat > "$SANDBOX/ready-dashes.md" <<'DASH_EOF'
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | em dash | implementor | — | 1m | x | a | pending |
| T2 | 4 | build | hyphen | implementor | - | 1m | x | b | pending |
| T3 | 4 | build | empty |  implementor |  | 1m | x | c | pending |
DASH_EOF
expect_eq "an em dash, a hyphen and an empty cell all mean no dependency" \
  "$(printf 'T1\nT2\nT3')" "$(call units_ready "$SANDBOX/ready-dashes.md" 4)"

# ============================================================
section "5 — units_validate: the live table is the clean case"
# ============================================================

VAL_LIVE="$(call units_validate "$SANDBOX/live.md")"
expect_eq "the live table breaks no invariant — zero lines" "0" "$(nlines "$VAL_LIVE")"
expect_eq "…and exits 0" "0" "$(call_rc units_validate "$SANDBOX/live.md")"

# ============================================================
section "6 — units_validate: one line per broken invariant, naming the id and the rule"
# ============================================================

VAL_BAD="$(call units_validate "$SANDBOX/broken.md")"

# SIX INVARIANTS ARE BROKEN, one row each. T7, a Step-6 row reaching only T1, used to be the
# seventh — "every Step-5+ row depends transitively on every Step-4 row" — and that rule is
# gone (wave-26 T2, D2): a row waits for what it reads, never for every build row. So every
# line names one of the six offending rows, and T7 draws none.
expect_eq "every violation line names one of the six offending rows" "" \
  "$(printf '%s\n' "$VAL_BAD" | grep -vE '^(T1|X1|T3|T4|T5|T6): ')"
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

# ============================================================
section "7 — units_validate: a missing column is a violation of the table, not of a row"
# ============================================================

VAL_MISSING="$(call units_validate "$SANDBOX/missing-column.md")"
expect_contains "a schema with no step column is refused, naming the column" \
  "## Tasks: missing column step" "$VAL_MISSING"
expect_eq "…and exits 1" "1" "$(call_rc units_validate "$SANDBOX/missing-column.md")"
expect_eq "a plan with no ## Tasks section at all is refused" "1" \
  "$(call_rc units_validate "$SANDBOX/no-table.md")"
expect_contains "…naming the absent section" "## Tasks" "$(call units_validate "$SANDBOX/no-table.md")"

# ============================================================
section "8 — the differential: the OLD FILL derivation and units_ready answer the same"
# ============================================================
#
# WHAT THIS PROVES, and why a refactor needs it. REQ-1e deleted `slice_table` and
# `slice_ready` from hooks/session-poker.sh and pointed the tick at `units_ready`. A
# refactor that changes the answer is not a refactor, and "the suite is still green" does
# not say that: the suite's own FILL fixtures were migrated in the same commit. So the OLD
# derivation is kept HERE, lifted byte-for-byte out of hooks/session-poker.sh at 1f48673
# (`git show 1f48673:hooks/session-poker.sh`), and run beside the new one over the same
# tables. A diff of the two answers is the claim.
#
# TWO SPECIMENS, for the two things that could have moved:
#   - THE 1.4.0 SPECIMEN (tests/fixtures/migration/wave-1.4.0-slices.md, the retired
#     four-column shape) against a ten-column twin carrying the same ids, deps and
#     statuses. This is the MIGRATION claim: the same schedule, written the new way,
#     dispatches the same batch.
#   - THIS WAVE'S OWN TEN-COLUMN TABLE. Here the two readers are asked DIFFERENT
#     questions on purpose — the old one has no step to scope by — so the identity is
#     between the old answer and the UNION of `units_ready` over Steps 3-9. That union is
#     the whole of what the old reader could say; the per-step split is what REQ-1e added.
#
# NOT VACUOUS. The 1.4.0 specimen lands every row, so its final state has an EMPTY ready
# set and "both agree" would be true of two broken readers. The configurations below
# rewind it: config k is the first k ids `landed` and the rest `pending`, which walks the
# plan back along its own timeline, and the run asserts that at least one configuration
# produced a non-empty answer before it believes any of the equalities.

# The OLD derivation, VERBATIM. Do not repair, reformat or improve anything between the
# markers: its value is that it is the code that shipped, and an edit here would turn the
# differential into a comparison of two things this wave wrote.
cat > "$SANDBOX/old-fill.sh" <<'OLD_FILL_EOF'
# --- lifted verbatim from hooks/session-poker.sh at 1f48673 ---
normalize_newlines() {
  awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$1"
}

slice_table() {  # <plan> -> id<TAB>deps<TAB>status, one per row
  normalize_newlines "$1" 2>/dev/null | awk '
    function trim(v) { sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v); return v }
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    !intable {
      if ($0 !~ /^[[:space:]]*\|/) next
      n = split($0, c, "|")
      idc = 0; depc = 0; stc = 0
      for (i = 1; i <= n; i++) {
        t = trim(c[i])
        if (t == "id") idc = i
        else if (t == "deps") depc = i
        else if (t == "status") stc = i
      }
      if (idc && depc && stc) intable = 1
      next
    }
    {
      if ($0 !~ /^[[:space:]]*\|/) exit
      n = split($0, c, "|")
      id = trim(c[idc])
      # The |---|---| separator row, and any row whose id cell is empty or punctuation.
      if (id == "" || id ~ /^[-: ]+$/) next
      printf "%s\t%s\t%s\n", id, trim(c[depc]), trim(c[stc])
    }'
}

slice_ready() {  # <table> -> the ready ids, one per line, in table order
  # ONE PASS TO REMEMBER, one to decide, over the same stream: a dependency may be named
  # before or after the row that depends on it, so nothing can be answered until the whole
  # table has been read. Table order is preserved by indexing on NR.
  printf '%s\n' "$1" | awk -F'\t' '
    $1 == "" { next }
    { n = n + 1; id[n] = $1; dep[n] = $2; st[$1] = $3 }
    END {
      for (i = 1; i <= n; i++) {
        if (st[id[i]] != "pending") continue
        deps = dep[i]
        gsub(/[[:space:]]/, "", deps)
        # A cell with no alphanumeric character names no dependency: the empty cell, the
        # hyphen and the em dash the plan actually uses are all spelled this one way, and
        # matching the dash byte-for-byte would put a Unicode literal in a bash 3.2 awk
        # program for no gain.
        if (deps !~ /[A-Za-z0-9]/) { print id[i]; continue }
        m = split(deps, d, ",")
        ready = 1
        for (j = 1; j <= m; j++) {
          if (d[j] == "" || d[j] !~ /[A-Za-z0-9]/) continue
          if (st[d[j]] != "landed") { ready = 0; break }
        }
        if (ready) print id[i]
      }
    }'
}
# --- end of the lifted text ---
OLD_FILL_EOF

# old_ready <plan file> -> the ids the RETIRED derivation would have filled, one per line.
old_ready() {
  bash -c '. "$1" >/dev/null 2>&1 || exit 127; slice_ready "$(slice_table "$2")"' \
    _ "$SANDBOX/old-fill.sh" "$1"
}

# new_ready <plan file> <step> -> the same question asked of the shipped library.
new_ready() { call units_ready "$1" "$2"; }

# sorted <string> -> the set, one per line, in a canonical order. The two readers are
# required to agree on WHICH ids, and both already preserve table order; sorting here keeps
# a future ordering change from reading as a membership difference.
sorted() { [ -z "$1" ] && return 0; printf '%s\n' "$1" | sort; }

# ---------- specimen A: the 1.4.0 schedule, old shape and new ----------

DIFF_IDS="$(awk -F'|' '/^\| [A-Z]/ { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2 }' \
  "$REPO_ROOT/tests/fixtures/migration/wave-1.4.0-slices.md")"
DIFF_DEPS_OF() {  # <id> -> that row's deps cell, verbatim
  awk -F'|' -v want="$1" '
    /^\| [A-Z]/ {
      id = $2; gsub(/^[ \t]+|[ \t]+$/, "", id)
      if (id == want) { d = $3; gsub(/^[ \t]+|[ \t]+$/, "", d); print d; exit }
    }' "$REPO_ROOT/tests/fixtures/migration/wave-1.4.0-slices.md"
}

# write_pair <k> — the first k ids landed, the rest pending, written twice: once in the
# retired four-column shape the old reader was built for, once in the ten-column schema.
write_pair() {
  local k="$1" i=0 id deps st
  {
    printf -- '## Slices\n\n| id | deps | complexity | status |\n|---|---|---|---|\n'  # retired: slice
    i=0
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      i=$((i + 1)); st=pending; [ "$i" -le "$k" ] && st=landed
      printf -- '| %s | %s | complex | %s |\n' "$id" "$(DIFF_DEPS_OF "$id")" "$st"
    done <<DIFF_IDS_EOF
$DIFF_IDS
DIFF_IDS_EOF
  } > "$SANDBOX/diff-old-$k.md"
  {
    printf -- '---\ncurrent: 4\n---\n\n## Tasks\n\n'
    printf -- '| id | step | kind | task | agent | deps | size | serves | Files | status |\n'
    printf -- '|---|---|---|---|---|---|---|---|---|---|\n'
    i=0
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      i=$((i + 1)); st=pending; [ "$i" -le "$k" ] && st=landed
      printf -- '| %s | 4 | build | a row | implementor | %s | 15m | REQ-x | a.sh | %s |\n' \
        "$id" "$(DIFF_DEPS_OF "$id")" "$st"
    done <<DIFF_IDS_EOF2
$DIFF_IDS
DIFF_IDS_EOF2
  } > "$SANDBOX/diff-new-$k.md"
}

DIFF_MISMATCH=""
DIFF_NONEMPTY=0
DIFF_K=0
while [ "$DIFF_K" -le 19 ]; do
  write_pair "$DIFF_K"
  DIFF_A="$(sorted "$(old_ready "$SANDBOX/diff-old-$DIFF_K.md")")"
  DIFF_B="$(sorted "$(new_ready "$SANDBOX/diff-new-$DIFF_K.md" 4)")"
  [ -n "$DIFF_A" ] && DIFF_NONEMPTY=$((DIFF_NONEMPTY + 1))
  if [ "$DIFF_A" != "$DIFF_B" ]; then
    DIFF_MISMATCH="${DIFF_MISMATCH}config ${DIFF_K}: old=[${DIFF_A}] new=[${DIFF_B}]
"
  fi
  DIFF_K=$((DIFF_K + 1))
done

expect_eq "twenty configurations of the 1.4.0 schedule: the two readers never disagree" \
  "" "$DIFF_MISMATCH"
expect_eq "…and the comparison had something to compare (configurations with a ready row)" \
  "yes" "$([ "$DIFF_NONEMPTY" -ge 10 ] && echo yes || echo no)"

# THE POWER CHECK the equality above needs. Two readers that both answered nothing would
# satisfy it. Doctor ONE cell of one configuration — a dependency that has not landed — and
# the old reader's answer must change; that is the comparison having teeth.
write_pair 6
DIFF_BASE="$(sorted "$(old_ready "$SANDBOX/diff-old-6.md")")"
expect_contains "config 6 has ADOPT ready — every one of its five dependencies has landed" \
  "ADOPT" "$DIFF_BASE"
# Rewind ONE of those five. ADOPT must leave the answer, and nothing else may move.
sed 's/^| L-ROOT | — | complex | landed |$/| L-ROOT | — | complex | pending |/' \
  "$SANDBOX/diff-old-6.md" > "$SANDBOX/diff-old-6-doctored.md"
sed 's/^| L-ROOT | 4 | build | a row | implementor | — | 15m | REQ-x | a.sh | landed |$/| L-ROOT | 4 | build | a row | implementor | — | 15m | REQ-x | a.sh | pending |/' \
  "$SANDBOX/diff-new-6.md" > "$SANDBOX/diff-new-6-doctored.md"
DIFF_DOC_OLD="$(sorted "$(old_ready "$SANDBOX/diff-old-6-doctored.md")")"
expect_eq "an unlanded dependency drops ADOPT from the OLD answer, so the equality is not vacuous" \
  "no" "$([ "$DIFF_BASE" = "$DIFF_DOC_OLD" ] && echo yes || echo no)"
expect_absent "…ADOPT is the row that left" "ADOPT" "$DIFF_DOC_OLD"
expect_eq "…and the shipped library moved with it, not against it" \
  "$DIFF_DOC_OLD" "$(sorted "$(new_ready "$SANDBOX/diff-new-6-doctored.md" 4)")"

# ---------- specimen B: this wave's own ten-column table ----------
#
# The old reader takes `id`, `deps` and `status` off this table by header NAME and ignores
# every other column, `step` included — so its answer is the union of what `units_ready`
# says at each step, and nothing else.
# wave_at <pending id>... — this wave's table VERBATIM, with the named ids `pending` and
# every other row `landed`. Only the status cell moves; the ten columns, the ids, the deps
# and the step cells are the plan's own. The snapshot's own statuses leave nothing ready
# (the rows behind the pending ones are `active`), and a differential between two empty
# answers measures nothing — so the schedule is driven to states that have work in them.
wave_at() {
  local want=" $* "
  {
    printf -- '---\ncurrent: 4\n---\n\n## Tasks\n\n'
    awk -F'|' -v want="$want" '
      function trim(v) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); return v }
      /^\|[ \t]*T[0-9]+[ \t]*\|/ {
        id = trim($2)
        st = (index(want, " " id " ") > 0) ? "pending" : "landed"
        sub(/\|[^|]*\|$/, "| " st " |")
        print
        next
      }
      { print }
    ' "$SANDBOX/tasks-table.md"
  } > "$SANDBOX/diff-wave.md"
}

# union_ready — units_ready asked once per step, 3 through 9, folded into one set. That is
# the whole of what the old reader could ever have said about this table, since it has no
# step to scope by.
union_ready() {
  local u="" st
  for st in 3 4 5 6 7 8 9; do
    u="${u}$(new_ready "$SANDBOX/diff-wave.md" "$st")
"
  done
  # `sort -u`, NOT `sort` (wave-20 Δ1): the per-step answers were disjoint while the step
  # filtered, and now a work row is ready at every step, so the union is a set of repeats.
  printf '%s' "$u" | grep -v '^$' | sort -u || true
}

# Three states of the wave's own schedule: one with work at a single step, one with work at
# two steps at once (which is where the old reader and a per-step reader must differ), and
# the snapshot's own all-but-one state.
WAVE_MISMATCH=""
WAVE_STATES="T10 T13 T14|T10|T13 T17"
OLD_IFS="$IFS"; IFS='|'
for WAVE_STATE in $WAVE_STATES; do
  IFS="$OLD_IFS"
  wave_at $WAVE_STATE
  WAVE_UNION="$(union_ready)"
  WAVE_OLD="$(sorted "$(old_ready "$SANDBOX/diff-wave.md")")"
  if [ "$WAVE_OLD" != "$WAVE_UNION" ]; then
    WAVE_MISMATCH="${WAVE_MISMATCH}pending=[${WAVE_STATE}] old=[${WAVE_OLD}] union=[${WAVE_UNION}]
"
  fi
  IFS='|'
done
IFS="$OLD_IFS"

expect_eq "on this wave's own table the old answer is the union of units_ready over Steps 3-9" \
  "" "$WAVE_MISMATCH"

# NOT VACUOUS, and then THE ONE PLACE THEY MUST DIFFER — the reason REQ-1e made the change.
# With a Step-4 row and a Step-5 row both ready, the old reader names both; asked about one
# step, the new reader names only that step's.
wave_at T10 T13 T14
WAVE_UNION="$(union_ready)"
WAVE_OLD="$(sorted "$(old_ready "$SANDBOX/diff-wave.md")")"
expect_eq "…with T10 (step 4), T13 and T14 (step 5) all ready at once" \
  "T10
T13
T14" "$WAVE_UNION"
# RE-AUTHORED FOR wave-20 REQ-5 (Δ1, Δ6; ADR-036). Through 1.8.6 the per-step split was the
# point of this row: asked about Step 4, units_ready named only T10. Readiness is now the
# prerequisite graph, so for WORK rows the answer at any step IS the old whole-table answer.
expect_eq "asked at Step 4, units_ready names every work row whose deps landed, whatever its step (Δ1)" \
  "T10
T13
T14" "$(sorted "$(new_ready "$SANDBOX/diff-wave.md" 4)")"
expect_eq "…which is exactly the old whole-table reader's answer" \
  "$WAVE_OLD" "$(sorted "$(new_ready "$SANDBOX/diff-wave.md" 4)")"
# THE ONE PLACE THEY STILL DIFFER (Δ6): a gate act. T20 is the Step-8 `integrate` row; its
# real prerequisite is a gate passing, so it waits for `current:` to reach Step 8 even when
# its deps have landed. The old reader, which had no step, would have named it at Step 4.
wave_at T20
expect_contains "the old reader names the Step-8 integrate row whose deps landed" "T20" \
  "$(old_ready "$SANDBOX/diff-wave.md")"
expect_absent "…units_ready at Step 4 does not: a gate act waits for its step (Δ6)" "T20" \
  "$(new_ready "$SANDBOX/diff-wave.md" 4)"
expect_eq "…and at Step 8 it does" "T20" "$(new_ready "$SANDBOX/diff-wave.md" 8)"

# ============================================================
section "9 — a markdown-escaped pipe in a cell (the critic's Issue 1)"
# ============================================================
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
# TWO FIXTURES, and the second is the critic's own control. A purpose-built table isolates
# the shift; the derived one puts the live plan's actual row back and asks the scheduler
# the question the wave asked it.

cat > "$SANDBOX/escaped-cell.md" <<'ESCAPED_EOF'
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the five PreToolUse\|Bash walls fold into one process | senior-implementor | — | 90m | REQ-1f | payload/scripts/lib/walls.sh | landed |
| T2 | 4 | build | matches \|first\| and \|second\| both | implementor | T1 | 10m | REQ-1f | hooks/a.sh | landed |
| T3 | 5 | verify | plain prose, no escape anywhere | test-runner | T1, T2 | 20m | all | record/x.md | pending |
ESCAPED_EOF

ROWS_ESC="$(call units_rows "$SANDBOX/escaped-cell.md")"

expect_eq "three data rows, escapes and all" "3" "$(nlines "$ROWS_ESC")"
expect_eq "every row still carries exactly thirteen fields" "3" \
  "$(printf '%s\n' "$ROWS_ESC" | awk -F'\t' 'NF == 13 { n++ } END { print n + 0 }')"

# THE WHOLE ROW, field by field. The shift this section exists for moves every cell AFTER
# the escape, so asserting the escaped cell alone would pass on a reader that recovered the
# text and lost the columns.
ESC_T1="$(printf '%s\n' "$ROWS_ESC" | awk -F'\t' '$1 == "T1"')"
expect_eq "…and field 5 is still the agent"  "senior-implementor" "$(printf '%s\n' "$ESC_T1" | cut -f5)"
expect_eq "…and field 6 is still deps"       "—"                  "$(printf '%s\n' "$ESC_T1" | cut -f6)"
expect_eq "…and field 7 is still size"       "90m"                "$(printf '%s\n' "$ESC_T1" | cut -f7)"
expect_eq "…and field 8 is still serves"     "REQ-1f"             "$(printf '%s\n' "$ESC_T1" | cut -f8)"
expect_eq "…and field 9 is still Files"      "payload/scripts/lib/walls.sh" \
  "$(printf '%s\n' "$ESC_T1" | cut -f9)"
expect_eq "…and field 10 is still the status" "landed"            "$(printf '%s\n' "$ESC_T1" | cut -f10)"

# TWO ESCAPES IN ONE CELL, and the restore is per-occurrence rather than per-cell.
ESC_T2="$(printf '%s\n' "$ROWS_ESC" | awk -F'\t' '$1 == "T2"')"
expect_eq "a cell carrying two escaped pipes reads back with both" \
  "matches |first| and |second| both" "$(printf '%s\n' "$ESC_T2" | cut -f4)"
expect_eq "…and its status is still the status" "landed" "$(printf '%s\n' "$ESC_T2" | cut -f10)"

# THE TWO VERBS, which is where the shift was actually costing the wave.
expect_eq "units_validate finds no violation in a table whose only oddity is the escape" \
  "" "$(call units_validate "$SANDBOX/escaped-cell.md")"
expect_eq "…and exits 0" "0" "$(call_rc units_validate "$SANDBOX/escaped-cell.md")"
expect_eq "units_ready can still schedule the Step-5 row behind those two" \
  "T3" "$(call units_ready "$SANDBOX/escaped-cell.md" 5)"

# ── the critic's control, on this wave's own schedule ────────────────────────
#
# THE SPECIMEN PREDATES T23 (it was spliced at 1f48673). The row below is the live plan's
# own, reproduced verbatim — the plan tree is gitignored and absent from a worktree, so it
# cannot be read here without breaking hermeticity. The transform then extends T13's and
# T14's deps cells the way the live plan does and lands every row but those two, which is
# the state the tick was asked about when it answered nothing.
T23_ROW='| T23 | 4 | build | 1f-e: the five PreToolUse\|Bash walls fold by the same bionic_fold into one process (hooks/bash-walls.sh); differential vs the five originals incl. stdout JSON merge; hooks.json 16 → 12 (AC-1f.5) | senior-implementor | T12 | 90m | REQ-1f | payload/scripts/lib/walls.sh, hooks/bash-walls.sh, hooks/hooks.json | landed |'

# THE ROW TRAVELS BY FILE, NEVER BY `awk -v`. An assignment on the command line is scanned
# for escape sequences, so `\|` reaches the program as a bare `|` and the fixture would lose
# the very byte it exists to carry. (Measured on darwin 25.6.0: the first draft of this
# fixture read back `PreToolUse|Bash` and the RED run passed the wrong assertion.)
printf '%s\n' "$T23_ROW" > "$SANDBOX/t23-row.md"

{
  printf -- '---\ncurrent: 5\n---\n\n## Tasks\n\n'
  awk '
    FNR == NR { t23 = $0; next }
    /^\|[ \t]*T[0-9]+[ \t]*\|/ {
      st = ($0 ~ /^\|[ \t]*T1[34][ \t]*\|/) ? "| pending |" : "| landed |"
      sub(/\| T2, T4, T5, T6, T8, T12, T22 \|/, "| T2, T4, T5, T6, T8, T12, T22, T23 |")
      sub(/\|[^|]*\|$/, st)
      print
      if ($0 ~ /^\|[ \t]*T12[ \t]*\|/) print t23
      next
    }
    { print }
  ' "$SANDBOX/t23-row.md" "$SANDBOX/tasks-table.md"
  printf -- '\n## Verification Matrix\n'
} > "$SANDBOX/escaped-live.md"

# THE CONTROL IS THE SAME FILE WITH THE ESCAPE SPENT — one hyphen where the backslash-pipe
# was, nothing else touched. Two answers that differ can only differ because of it.
awk '{ gsub(/\\[|]/, "-"); print }' "$SANDBOX/escaped-live.md" > "$SANDBOX/escaped-live-control.md"


READY_ESC="$(call units_ready "$SANDBOX/escaped-live.md" 5)"
READY_CTL="$(call units_ready "$SANDBOX/escaped-live-control.md" 5)"

expect_eq "on the wave's own schedule the control schedules T13 and T14 at Step 5" \
  "$(printf 'T13\nT14')" "$READY_CTL"
expect_eq "…and the escape changes NOTHING about that answer" "$READY_CTL" "$READY_ESC"
expect_eq "units_validate clears the escaped schedule too" "" \
  "$(call units_validate "$SANDBOX/escaped-live.md")"

# T23's own row, which is the one the shift mangled: its agent was read as its deps and its
# Files as its status.
ESC_T23="$(call units_rows "$SANDBOX/escaped-live.md" | awk -F'\t' '$1 == "T23"')"
expect_eq "T23's agent is the agent"   "senior-implementor" "$(printf '%s\n' "$ESC_T23" | cut -f5)"
expect_eq "T23's deps is the deps"     "T12"                "$(printf '%s\n' "$ESC_T23" | cut -f6)"
expect_eq "T23's status is the status" "landed"             "$(printf '%s\n' "$ESC_T23" | cut -f10)"
expect_contains "T23's task cell keeps its pipe" "PreToolUse|Bash" \
  "$(printf '%s\n' "$ESC_T23" | cut -f4)"

# ============================================================

section "§ORDER — build, regression, review, release: units_validate refuses any other order naming the rows; units_order reads it"
# A pair out of order is refused when neither row is dropped and one is open; landed history is not judged.
OR_P="$SANDBOX/order.plan.md"
or_plan() {  # <row>... -> OR_P: a reads table holding a landed build row and the rows given
  { printf -- '---\ncurrent: 4\n---\n\n## SDLC State\n\ncurrent: 4\napproved-by: fixture 2026-10-12T00:00Z "approved"\n\n## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | status | reads |\n|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | a | implementor | — | 30 | REQ-1 | lib/a.sh | landed | |\n'
    printf '%s\n' "$@"; } > "$OR_P"
}
OR_REG='| T5 | 5 | test | the whole regression | test-runner | — | 90 | REQ-1 | .bionic/docs/record/w/T5.md | pending | approval:plan, head |'
OR_REV='| T6 | 6 | review | the critic | critic | — | 60 | REQ-1 | .bionic/docs/record/w/T6.md | pending | approval:plan, head |'
OR_REL='| T7 | 7 | doc | the release | implementor | — | 30 | REQ-1 | CHANGELOG.md | pending | approval:plan, head |'
or_plan "$OR_REG" "$OR_REV" "$OR_REL"
expect_eq "ORD-1 control: regression at 5, review at 6, release at 7: no violation (rc 0)" "|0" "$(call units_validate "$OR_P")|$(call_rc units_validate "$OR_P")"
expect_eq "ORD-1b …and units_order names the regression row" "T5|0" "$(call units_order "$OR_P")|$(call_rc units_order "$OR_P")"
or_plan "$OR_REV" "$OR_REL" "${OR_REG/| 5 | test |/| 7 | test |}"
OR_REGLINE='T5: the regression row comes after the review row T6; the order is build, regression, review, release: put T5 at step 5, ahead of T6'
expect_eq "ORD-2 the regression after the release (the old order): refused with rc 1, one line naming T5 and the first row it follows, T6" \
  "$OR_REGLINE|1" "$(call units_validate "$OR_P")|$(call_rc units_validate "$OR_P")"
expect_eq "ORD-2b …and units_order reads no order" "|1" "$(call units_order "$OR_P")|$(call_rc units_order "$OR_P")"
or_plan "$OR_REV" "${OR_REG/| 5 | test |/| 6 | test |}" "$OR_REL"
expect_eq "ORD-3 the regression at the review's step, after it in the table: refused with rc 1, one line naming T5 and T6" \
  "$OR_REGLINE|1" "$(call units_validate "$OR_P")|$(call_rc units_validate "$OR_P")"
or_plan "$OR_REG" "$OR_REL" "${OR_REV/| 6 | review |/| 7 | review |}"
expect_eq "ORD-4 the release ahead of a review row: refused with rc 1, one line naming T7 and T6" \
  "T7: the release row comes ahead of the review row T6; the order is build, regression, review, release: put T7 at step 7, after T6|1" \
  "$(call units_validate "$OR_P")|$(call_rc units_validate "$OR_P")"
or_plan "$OR_REV" "$OR_REL" "${OR_REG/| 5 | test |/| 7 | test |}"
sed 's/ pending | approval/ landed | approval/' "$OR_P" > "$OR_P.x" && mv "$OR_P.x" "$OR_P"
expect_eq "ORD-5 the ORD-2 plan with every row landed: history is not judged (rc 0)" "|0" "$(call units_validate "$OR_P")|$(call_rc units_validate "$OR_P")"
or_plan "$OR_REG" "$OR_REL"
expect_eq "ORD-6 no review row: the regression ahead of the release validates, and is the order" "|T5" "$(call units_validate "$OR_P")|$(call units_order "$OR_P")"
or_plan "$OR_REG" "$OR_REV"
expect_eq "ORD-7 no release row: no order to read (rc 1)" "|1" "$(call units_order "$OR_P")|$(call_rc units_order "$OR_P")"


section "§POST — a review row after a landed release is admitted when it reads only approval:plan, head and the rows landed past the release"
# The fix that lands after the release is read as a piece, so its reader row stands after the release row. It is
# admitted only when the release row has landed and the reader names nothing written before the release; while the
# release is open the order text refuses it as before. Each case projects the row the way task-add does
# (units_add_row, then units_validate on the projection).
PO_P="$SANDBOX/post.plan.md"
po_plan() {  # <release status> -> PO_P: build, regression, review and release rows, and a build row landed past the release
  { printf -- '---\ncurrent: 7\n---\n\n## SDLC State\n\ncurrent: 7\napproved-by: fixture 2026-10-12T00:00Z "approved"\n\n## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | status | reads |\n|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | a | implementor | — | 30 | REQ-1 | lib/a.sh, .bionic/docs/record/w/T1.md | landed | |\n'
    printf '| T5 | 5 | test | the whole regression | test-runner | — | 90 | REQ-1 | .bionic/docs/record/w/T5.md | landed | approval:plan, head |\n'
    printf '| T6 | 6 | review | the critic | critic | — | 60 | REQ-1 | .bionic/docs/record/w/T6.md | landed | approval:plan, head |\n'
    printf '| T7 | 7 | doc | the release | implementor | — | 30 | REQ-1 | CHANGELOG.md | %s | approval:plan, head |\n' "$1"
    printf '| T8 | 7 | build | the fix after the release | implementor | — | 30 | REQ-1 | lib/b.sh, .bionic/docs/record/w/T8.md | landed | approval:plan |\n'
  } > "$PO_P"
}
po_add() {  # <reads> -> PO_P with the review row T9 added past the release, as task-add projects it
  call units_add_row "$PO_P" T9 7 review "the critic reads the fix as a piece" critic — 20 REQ-1 \
    .bionic/docs/record/w/T9-adversarial.md "$1" > "$PO_P.new" && mv "$PO_P.new" "$PO_P"
}
PO_ORD='T7: the release row comes ahead of the review row T9; the order is build, regression, review, release: put T7 at step 7, after T9'
po_plan landed; po_add 'approval:plan, head, .bionic/docs/record/w/T8.md'
expect_eq "POST-0 precondition: the projection carries T9 after the release row T7 and the fix row T8" "T7 T8 T9" \
  "$(call units_rows "$PO_P" | awk -F'\t' '$2 == 7 { printf "%s%s", (n++ ? " " : ""), $1 }')"
expect_eq "POST-1 the release landed and T9 reads approval:plan, head and the fix row's record: admitted (no line, rc 0)" "|0" \
  "$(call units_validate "$PO_P")|$(call_rc units_validate "$PO_P")"
po_plan pending; po_add 'approval:plan, head, .bionic/docs/record/w/T8.md'
expect_eq "POST-2 the same reader while the release row is open: refused with the order text (rc 1)" "$PO_ORD|1" \
  "$(call units_validate "$PO_P")|$(call_rc units_validate "$PO_P")"
po_plan landed; po_add 'approval:plan, head, .bionic/docs/record/w/T1.md'
expect_eq "POST-3 the release landed and T9 reads a row written before it: refused with the order text (rc 1)" "$PO_ORD|1" \
  "$(call units_validate "$PO_P")|$(call_rc units_validate "$PO_P")"
po_plan landed; po_add 'approval:plan, head'
expect_eq "POST-4 the release landed and T9 names no row it reads: refused with the order text, a whole read stays ahead of the release (rc 1)" "$PO_ORD|1" \
  "$(call units_validate "$PO_P")|$(call_rc units_validate "$PO_P")"
po_plan landed; po_add 'approval:plan, head, .bionic/docs/record/w/T8.md, .bionic/docs/record/w/T6.md'
expect_eq "POST-5 the release landed and T9 reads the fix and a pre-release reading: refused with the order text (rc 1)" "$PO_ORD|1" \
  "$(call units_validate "$PO_P")|$(call_rc units_validate "$PO_P")"

section "§AFTER-PUBLISH — after the release is the order the landing record published in, not the plan's step and table position"
# A fix row born at step 4 stands ahead of the release row in the plan's order and publishes after it. The reader
# rule and the release card both ask whether what a review row reads was written after the release, and the numbers
# re-renderer answers by the record's publish order, so the one question has one answer: the record's order, with
# the plan's order only where no record names the release row. The plan sits in a repository of its own so the
# record is found by the plan's name, the way every other reader finds it.
AP_REPO="$SANDBOX/ap-repo"
git init -q "$AP_REPO" && mkdir -p "$AP_REPO/.bionic/docs/plans" "$AP_REPO/.bionic/docs/record/ap"
AP_P="$AP_REPO/.bionic/docs/plans/ap.plan.md"
AP_REC="$AP_REPO/.bionic/docs/record/ap/landing-proofs.log"
AP_H="$(printf '%040d' 1)"
ap_plan() {  # <fix row status> -> AP_P: the POST fixture with the fix row T8 born at step 4, after the release row in the table
  { printf -- '---\ncurrent: 7\n---\n\n## SDLC State\n\ncurrent: 7\napproved-by: fixture 2026-10-12T00:00Z "approved"\n\n## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | status | reads |\n|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | a | implementor | — | 30 | REQ-1 | lib/a.sh, .bionic/docs/record/w/T1.md | landed | |\n'
    printf '| T5 | 5 | test | the whole regression | test-runner | — | 90 | REQ-1 | .bionic/docs/record/w/T5.md | landed | approval:plan, head |\n'
    printf '| T6 | 6 | review | the critic | critic | — | 60 | REQ-1 | .bionic/docs/record/w/T6.md | landed | approval:plan, head |\n'
    printf '| T7 | 7 | doc | the release | implementor | — | 30 | REQ-1 | CHANGELOG.md | landed | approval:plan, head |\n'
    printf '| T8 | 4 | build | the fix born at step 4 | implementor | — | 30 | REQ-1 | lib/b.sh, .bionic/docs/record/w/T8.md | %s | approval:plan |\n' "$1"
  } > "$AP_P"
  call units_add_row "$AP_P" T9 7 review "the critic reads the fix as a piece" critic — 20 REQ-1 \
    .bionic/docs/record/w/T9-adversarial.md 'approval:plan, head, .bionic/docs/record/w/T8.md' > "$AP_P.new" && mv "$AP_P.new" "$AP_P"
}
ap_pub() {  # <row>... -> AP_REC: a published event for each row, in the order given
  : > "$AP_REC"
  local r
  for r in "$@"; do printf 'line/v1|ev=published|row=%s|commit=%s|kind=queue|by=-|why=-|at=2026-10-12T00:00:00Z\n' "$r" "$AP_H" >> "$AP_REC"; done
}
ap_state() { printf '%s|%s|%s' "$(call units_validate "$AP_P")" "$(call_rc units_validate "$AP_P")" "$(call units_post_readers "$AP_P")"; }
AP_T9="$(printf 'T9\tpending\tunread')"

ap_plan landed; ap_pub T1 T5 T6 T7 T8
expect_eq "AP-0 precondition: the record holds both the release row T7 and the fix row T8, T7 first" "T7 T8" \
  "$(awk -F'|' '{ for (i = 1; i <= NF; i++) if ($i ~ /^row=T[78]$/) printf "%s%s", (n++ ? " " : ""), substr($i, 5) }' "$AP_REC")"
expect_eq "AP-1 the fix row published after the release: T9 reading its record is admitted (no line, rc 0) and listed for the card" \
  "|0|$AP_T9" "$(ap_state)"
ap_pub T1 T5 T6 T8 T7
expect_eq "AP-2 the same plan with the record's order reversed, the fix published before the release: refused with the order text, nothing listed" \
  "$PO_ORD|1|" "$(ap_state)"
rm -f "$AP_REC"
expect_eq "AP-3 the same plan with no landing record: plan order decides, and the step-4 fix row is not past the release (refused, nothing listed)" \
  "$PO_ORD|1|" "$(ap_state)"
ap_plan pending; ap_pub T1 T5 T6 T7
expect_eq "AP-4 the fix row open and unpublished, the release published: it will publish past the release, so T9 is admitted and listed" \
  "|0|$AP_T9" "$(ap_state)"
ap_plan landed; : > "$AP_REC"
for r in T1 T5 T6 T7 T8; do printf 'landed: row=%s branch=b head=%s merge=%s at=2026-10-12T00:00:00Z\n' "$r" "$AP_H" "$AP_H" >> "$AP_REC"; done
expect_eq "AP-5 a record of landed: headers alone is read in its order too: T8 after T7 is admitted" "|0|$AP_T9" "$(ap_state)"
ap_plan landed; : > "$AP_REC"
for r in T1 T5 T6 T8 T7; do printf 'landed: row=%s branch=b head=%s merge=%s at=2026-10-12T00:00:00Z\n' "$r" "$AP_H" "$AP_H" >> "$AP_REC"; done
expect_eq "AP-5b …and with those headers reversed the differential control refuses" "$PO_ORD|1|" "$(ap_state)"

# A PLAN VERB'S DRY COPY NAMES NO RECORD, so the origin plan is the second operand: the record is read from the plan the
# copy was made from, and the copy is judged as the plan is. The copy sits beside the plan under the name a verb gives it.
AP_COPY="$AP_P.task-add-dry.4242"
ap_copy_state() { printf '%s|%s|%s' "$(call units_validate "$AP_COPY" "$1")" "$(call_rc units_validate "$AP_COPY" "$1")" \
  "$(call units_post_readers "$AP_COPY" "$1")"; }
ap_plan landed; ap_pub T1 T5 T6 T7 T8; cp "$AP_P" "$AP_COPY"
expect_eq "AP-6 the copy of a plan whose record published the fix row after the release, judged with the plan as origin: admitted and listed as the plan is" \
  "$(ap_state)" "$(ap_copy_state "$AP_P")"
expect_eq "AP-6b …and that answer is an admission, so the equality above is not two refusals" "|0|$AP_T9" "$(ap_copy_state "$AP_P")"
expect_eq "AP-7 the control: the same copy with no origin names no record and is refused by plan order, nothing listed" "$PO_ORD|1|" "$(ap_copy_state "")"
ap_pub T1 T5 T6 T8 T7
expect_eq "AP-8 the copy with the origin whose record published the fix row BEFORE the release: refused with the order text, as the plan is" \
  "$PO_ORD|1|" "$(ap_copy_state "$AP_P")"
rm -f "$AP_COPY"

section "§JUDGE — covered at the last green whole run's head; past it each commit owes its row's suites, never a second whole run"
# ============================================================

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
printf -- '---\ncurrent: 5\n---\n\n## SDLC State\n\nproved: kind=regression head=%s at=2026-01-01T00:00:00Z evidence=whole.log\n' \
  "$JH" > "$SANDBOX/judge-plan.md"
judge() { bash -c '. "$1" >/dev/null 2>&1 || exit 127; _proof_floor_judge "$2" "$3" "$4"' _ "$PROOF_LIB" "$SANDBOX/judge-plan.md" "$JR" "$1"; }
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
printf -- '---\ncurrent: 7\n---\n\n## SDLC State\n\nproved: kind=check head=%s at=2026-01-01T00:00:00Z evidence=check.log\n' "$RH" > "$RR/plan.md"
bash -c '. "$1" && . "$2" || exit 1; for s in $(_proof_release_readers); do line_event "$3" verdict row=T8 "commit=$4" "suite=$s" result=green log=- admitted=- width=-; done' _ "$LINE_LIB" "$PROOF_LIB" "$RR/plan.md" "$RH"
cover() { bash -c '. "$1" >/dev/null 2>&1 || exit 127; facts_cover "$2" "$3" "$4"; echo "rc=$?"' _ "$PROOF_LIB" "$RR/plan.md" "$RB" "$RH"; }
expect_eq "a release commit with the check suite and a promoted ADR, a check and its readers green at it: release" "$(printf 'cover %s release\nrc=0' "$RH")" "$(cover)"

section "§WALK — the regression walk excuses a real release merge whose check passed, as the judge's cover reads it"
# ============================================================

# A path's place in the release set is asked apart from its place in the docs: CHANGELOG.md is in both, and a release
# merge whose every path is in the set is excused by the check that passed at it, never sent to a landing row. Live
# tier, read-only: this repository's own release merges, pinned by hash, skipped by version and hash when absent.
# Without the check line the same merge is named as not proved, so the excuse is the check's.
WK_PASS="$SANDBOX/walk-pass.md"; WK_NONE="$SANDBOX/walk-none.md"
printf -- '---\ncurrent: 5\n---\n\n## SDLC State\n\n' > "$WK_NONE"
cp "$WK_NONE" "$WK_PASS"
walk() { bash -c '. "$1" >/dev/null 2>&1 || exit 127; _proof_past_f "$2" "$3" "$4^1" "$4" ""; echo "rc=$?"' _ "$PROOF_LIB" "$1" "$REPO_ROOT" "$2" </dev/null; }
expect_eq "WALK-0 the release commit built above, CHANGELOG.md among its paths, a check passing at it: excused (rc 0)" "rc=0" \
  "$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; _proof_past_f "$2" "$3" "$4" "$5" ""; echo "rc=$?"' _ "$PROOF_LIB" "$RR/plan.md" "$RR" "$RB" "$RH" </dev/null)"
WK_N=0
while read -r v m; do
  if ! git -C "$REPO_ROOT" cat-file -e "$m^{commit}" 2>/dev/null || ! git -C "$REPO_ROOT" cat-file -e "$m^1^{commit}" 2>/dev/null; then
    echo "SKIP: WALK $v merge ${m:0:12}: the merge $m or its first parent is absent from this repository"; continue
  fi
  WK_N=$((WK_N + 1))
  printf 'proved: kind=check head=%s at=2026-10-20T00:00:00Z evidence=check-%s.log\n' "$m" "$v" >> "$WK_PASS"
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
# ============================================================

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
{ printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: double\nscale: wave\n---\n# plan\n\n'
  printf '## SDLC State\n\ncurrent: 5\nworking-branch: wave/01-second\nintegration-branch: main\n'; } > "$SEC_PLAN"
bound_marker "$SEC" "$SEC_SID" "$SEC_PLAN" >/dev/null 2>&1 || :
sec_poke() {  # -> SEC_OUT (stdout and stderr), SEC_RC: regression-run [flags…] as the bound session, in the repository
  SEC_RC=0
  SEC_OUT="$(cd "$SEC" && env CLAUDE_CODE_SESSION_ID="$SEC_SID" HOME="$SEC_ROOT/home" CLAUDE_CONFIG_DIR="$SEC_ROOT/config" \
    BIONIC_GATE_DIR="$SEC_ROOT/gate" bash "${BIONIC_HOOKS_DIR}/session-poker.sh" regression-run "$@" 2>&1)" || SEC_RC=$?
}
sec_ran() { [ -e "$SEC_ROOT/ran" ] && printf yes || printf no; }
sec_logs() { find "$SEC/.bionic/docs/$SEC_REL" -name 'regression-run-*.log' | wc -l | tr -d ' '; }
sec_rec() { bash -c '. "$1/payload/scripts/lib/line.sh" >/dev/null 2>&1 && line_record "$2"' _ "$BIONIC_SCRIPTS_DIR" "$SEC_PLAN"; }
sec_runline() { /usr/bin/grep -F "|ev=run|log=$SEC_REL/$1|" "$(sec_rec)" 2>/dev/null || :; }   # <log name> -> its run line
printf 'all green\n' | regression_fixture "$SEC_PLAN" "$SEC/.bionic/docs/$SEC_REL/regression-run-$SEC_H.log" "$SEC_H" 0 0
expect_eq "SEC-0 precondition: the record holds a whole run at H, clean, and no run has started" "1|no|1" \
  "$(/usr/bin/grep -c "^line/v1|ev=run|log=$SEC_REL/regression-run-$SEC_H.log|head=$SEC_H|dirty=0|" "$(sec_rec)" 2>/dev/null || :)|$(sec_ran)|$(sec_logs)"

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


# ============================================================
section "§STEP-FIELD — units_step_field reads the block units_step_fields writes: the first key line, fences skipped"
# ============================================================
# The Step-7 advance and close-out's epic row both read the Step 7 block's `adr:` pointer; this is their one reader,
# beside the writer, reading the block the writer writes. FIXTURE FIDELITY: a planted plan whose Step 7 block is
# written by `units_step_fields` itself, with a fenced decoy block above and a second `adr:` line under the first.
# fails-when: the reader reads the fenced decoy, the second line, another step's block, or calls a missing key found.
SF_PLAN="$SANDBOX/step-field.plan.md"
printf '# plan\n\n## SDLC State\n\ncurrent: 7\n```\n- Step 7: a fenced example\n  adr: fenced.md\n```\n- Step 7: n/a: no ADR owed here\n- Step 8: merge: main @ 0123abc\n  cleanup: n/a\n\n## Tasks\n' > "$SF_PLAN"
sf_lib() { bash -c '. "$1" || exit 9; shift; "$@"' _ "$LIB" "$@"; }
sf_lib units_step_fields "$SF_PLAN" 7 "adr=adrs/epic-x/adr-061-the-pointer.md" > "$SF_PLAN.w" && mv "$SF_PLAN.w" "$SF_PLAN"
printf '%s\n' "$(awk '{ print } /^  adr: adrs/ { print "  adr: second.md" }' "$SF_PLAN")" > "$SF_PLAN.w" && mv "$SF_PLAN.w" "$SF_PLAN"
expect_contains "SF-0 precondition: the writer put the adr: line under the Step 7 line" \
  "- Step 7: n/a: no ADR owed here
  adr: adrs/epic-x/adr-061-the-pointer.md" "$(cat "$SF_PLAN")"
sf_get() { SF_OUT="$(sf_lib units_step_field "$@")"; SF_RC=$?; }
sf_get "$SF_PLAN" 7 adr
expect_eq "SF-1 the first adr: line of the Step 7 block, not the fenced decoy's or the second (exit 0)" \
  "0|adrs/epic-x/adr-061-the-pointer.md" "$SF_RC|$SF_OUT"
sf_get "$SF_PLAN" 7 n/a
expect_eq "SF-2 a key the step line itself opens with is read from the step line" "0|no ADR owed here" "$SF_RC|$SF_OUT"
sf_get "$SF_PLAN" 8 cleanup
expect_eq "SF-3 another step's block is its own: Step 8's cleanup:" "0|n/a" "$SF_RC|$SF_OUT"
sf_get "$SF_PLAN" 8 adr
expect_eq "SF-4 a key the block does not carry: exit 2, nothing printed" "2|" "$SF_RC|$SF_OUT"
sf_get "$SF_PLAN" 5 adr
expect_eq "SF-5 a step with no line: exit 1, nothing printed" "1|" "$SF_RC|$SF_OUT"


# ============================================================
section "§DEBT — the review-born count: exempt under fix-policy: or counted, and the three task-add rules each held by a row a removal turns red"
# ============================================================
# A review-born row rated inside fix-policy: is exempt from fix-cap:; one the person promoted from outside it, or one
# born of a finding in another plan's record directory, counts. `units_born_counted` is the one reader of that test,
# and the landing line and task-add read it. The rows below pin the reader, the landing line's count, and the three
# rules task-add holds on a born row: the cap refusal, the fourth fix on one file, and the count its line prints.
# FIXTURE FIDELITY: planted plans in the shape s34's fixture writes (tests/session-poker.prelude.sh), the born markers
# in the shapes `task-add --born` writes them, the readings in `proof-add review`'s shape; every task-add is the real
# verb, run as a session bound to the plan through the product's own binder, against the shipped tree and against a
# copy of it with one rule removed (hooks/ beside scripts/, the tree's own scripts and library linked in, as
# session-poker-5's §CHECK mutant is built).
# fails-when: the reader calls an exempt row counted or a promoted or carried one exempt; the landing line prints one
# total; the cap refusal, the fourth-fix refusal or the count on task-add's line is removed and no row here goes red.
DB_SID="6e5d4c3b-2a1f-4e0d-9c8b-7a6f5e4d3c2b"
DB_ROOT="$SANDBOX/debt"; mkdir -p "$DB_ROOT/home" "$DB_ROOT/config/bionic" "$DB_ROOT/gate" "$DB_ROOT/no-plugins"
DB_OWN="record/wave-01-debt"; DB_CARRIED="record/wave-00-prior"
db_plan() {  # <repo> <fix-cap> <tasks rows> <ledger lines> [<frontmatter line>] -> the plan path, bound to DB_SID
  local f="$1/.bionic/docs/plans/epic-99-fixture/wave-01-debt.plan.md" h
  mkdir -p "${f%/*}" "$1/.bionic/docs/specs/epic-99-fixture" "$1/.bionic/docs/$DB_OWN" "$1/.bionic/docs/$DB_CARRIED"
  printf '# requirements\n' > "$1/.bionic/docs/specs/epic-99-fixture/wave-01-debt.requirements.md"
  printf '# spec\n' > "$1/.bionic/docs/specs/epic-99-fixture/wave-01-debt.spec.md"
  h="$(git -C "$1" rev-parse HEAD 2>/dev/null)"
  printf 'reviewed: %s..%s\nquestion: adversarial\nresult: fail\nscope: piece\n\nfindings: 2\nfinding: 1 S2 on lib/c1.sh:1 the first carried defect\nfinding: 2 S2 on lib/c2.sh:1 the second carried defect\nshown: 1 cat lib/c1.sh\nshown: 2 cat lib/c2.sh\n' \
    "$h" "$h" > "$1/.bionic/docs/$DB_CARRIED/critic.md"
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: bugfix\n'
    printf 'rigor: double\nfix-cap: %s\n%sscale: wave\nmulti_agent: true\nuse_worktree: true\nhas_ui: false\n' "$2" "${5:+$5
}"
    printf 'walk: exempt\ndeploy_target: n/a\n'
    printf 'parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=user\n---\n\n'
    printf '# fixture wave\n\n## SDLC State\n\ncurrent: 4\n'
    printf 'approved-by: fixture 2026-09-23T00:00Z "approved"\n'
    printf 'proved: kind=review head=%s at=2026-10-20T00:00:00Z evidence=%s/critic.md question=adversarial reader=w-adv result=fail scope=piece\n\n' "$h" "$DB_CARRIED"
    printf -- '- Step 1: requirements: specs/epic-99-fixture/wave-01-debt.requirements.md\n'
    printf -- '- Step 2: spec: specs/epic-99-fixture/wave-01-debt.spec.md\n'
    printf -- '- Step 3: plan: plans/epic-99-fixture/wave-01-debt.plan.md\n'
    printf -- '- Step 4: opened\n  worktree: .worktrees/01-debt\n  base-sha: abc1234\n  branch: wave/01-debt\n'
    printf -- '- T1: landed at record/T1.md\n- T2: dispatched to w-T2\n%s- T5: pending dispatch — .worktrees/01-T5\n\n' "${4:+$4
}"
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | the first build | implementor | — | 30 | REQ-1 | a.sh | — | — | landed |\n'
    printf '| T2 | 4 | build | the second build | implementor | — | 30 | REQ-1 | b.sh | 01-T2 | abc1234 | active |\n'
    printf '%s' "${3:+$3
}"
    printf '| T5 | 5 | verify | the floor | test-runner | T1, T2 | 30 | REQ-1 | — | — | — | pending |\n\n'
  } > "$f"
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
db_row() { printf '| %s | 4 | build | fix %s | implementor | — | 30 | REQ-1 | %s | — | — | pending |' "$1" "$1" "$2"; }   # <id> <files>
db_led() { printf -- '- %s: pending dispatch — added by task-add at 2026-10-20T00:00:00Z born: %s' "$1" "$2"; }   # <id> <marker>
db_poke() {  # <poker> <repo> <id> <files> <born> -> DB_OUT, DB_RC: task-add of a step-4 build row as DB_SID
  DB_RC=0
  DB_OUT="$(cd "$2" && env CLAUDE_CODE_SESSION_ID="$DB_SID" HOME="$DB_ROOT/home" CLAUDE_CONFIG_DIR="$DB_ROOT/config" \
    BIONIC_GATE_DIR="$DB_ROOT/gate" BIONIC_PLUGINS_DIR="$DB_ROOT/no-plugins" \
    bash "$1" task-add "$3" 4 build "Fix $3. The defect is gone." bionic:implementor '—' 30 REQ-1 "$4" --born "$5" 2>&1)" || DB_RC=$?
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
    "1|"*"task-add refused — review-born rows: 1 of cap 1 are counted (0 exempt under fix-policy: S1,S2-on); this finding goes to the review findings disposition, or the person raises the cap: set fix-cap=2 at the card."*) echo green ;;
    "0|"*) [ -n "$(/usr/bin/grep '^- T6: ' "$p")" ] && echo "red: admitted" || echo "red: exit 0 with no row" ;;
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
    "0|"*) [ -n "$(/usr/bin/grep '^- T7: ' "$p")" ] && echo "red: admitted" || echo "red: exit 0 with no row" ;;
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

# ============================================================
finish
