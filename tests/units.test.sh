#!/bin/bash
# tests/units.test.sh — payload/scripts/lib/units.sh: THE ONE READER OF `## Tasks`
# (epic-23 wave-11-lean-spine, REQ-1e; AC-1e.1/1e.2; spec Design §1 "Task", §2 D3/D7).
#
# WHAT IT OWNS. The contract three callers bind to after T8 — the evidence gate's ledger
# checks and its prototype check, the tick's FILL, and the governing-skill Step-3 wall — so
# that none of them carries a parser of its own. Three questions, one per function:
#
#   §1 units_rows <plan>          the thirteen fields, in the FIXED order, whatever order the
#                                 table's columns are written in
#   §10 the `worktree` cell        slot 11, OPTIONAL: a table without the column is valid
#                                 and reads it empty (wave-14 REQ-2, ADR-027)
#   §13 the `base` cell            slot 12, OPTIONAL, and a commit id when it holds one
#                                 (wave-17 REQ-2, ADR-032)
#   §4 units_ready <plan> <step>  which rows at that step may be dispatched now
#   §5 units_validate <plan>      which of the Task invariants the table breaks
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
#
# Usage: bash tests/units.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"

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
section "0 — the library is on disk, parses, sources silently, and defines the three verbs"
# ============================================================

expect_eq "units.sh is on disk" "yes" "$([ -r "$LIB" ] && echo yes || echo no)"
expect_eq "units.sh parses" "yes" "$(bash -n "$LIB" 2>/dev/null && echo yes || echo no)"

for _fn in units_rows units_ready units_validate; do
  expect_eq "sourcing units.sh defines $_fn" "yes" \
    "$(bash -c '. "$1" >/dev/null 2>&1 || exit 1; declare -F "$2" >/dev/null 2>&1 && echo yes || echo no' _ "$LIB" "$_fn")"
done

# SOURCED, NEVER EXECUTED. A library that printed on the way in would corrupt every caller
# that reads a verb's output through a command substitution — which is all three of them.
expect_eq "sourcing units.sh prints nothing on stdout" "" "$(bash -c '. "$1"' _ "$LIB" 2>/dev/null)"
expect_eq "…and nothing on stderr" "" "$(bash -c '. "$1"' _ "$LIB" 2>&1 >/dev/null)"

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
expect_eq "T1 renders id·step·kind·task·agent·deps·size·serves·Files·status·worktree·base in that order" \
  "$(printf 'T1\t3\tdoc\tPlan, Tasks and matrix written; Step-3 card approved\torchestrator\t—\t30m\tall\tplan\tlanded\t\t\t')" \
  "$(printf '%s\n' "$ROWS_LIVE" | sed -n '1p')"

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
expect_eq "the reversed fixture's header starts at status and ends at id" \
  "| status | Files | serves | size | deps | agent | task | kind | step | id |" \
  "$(sed -n '1p' "$SANDBOX/tasks-table-reversed.md")"
expect_eq "…so the two table files are not the same bytes" "differ" \
  "$(cmp -s "$SANDBOX/tasks-table.md" "$SANDBOX/tasks-table-reversed.md" && echo same || echo differ)"
expect_eq "…and the reversal kept every line" \
  "$(wc -l < "$SANDBOX/tasks-table.md" | tr -d ' ')" \
  "$(wc -l < "$SANDBOX/tasks-table-reversed.md" | tr -d ' ')"

ROWS_REORDERED="$(call units_rows "$SANDBOX/reordered.md")"
expect_eq "…and the comparison is over 22 real rows, not two empty strings" "22" \
  "$(nlines "$ROWS_REORDERED")"
expect_eq "reversing every column changes not one byte of the TSV" "$ROWS_LIVE" "$ROWS_REORDERED"

# ---------- slot 3 answers to two names: `kind` and `rigor` (A-39) ----------
#
# THE ONE ALIAS, and the whole of why it exists. Slot 3 is the row's CLASSIFICATION cell.
# The wave-scale table spells it `kind`; the task-scale registration ledger the evidence
# gate has read since D12 — `| id | intent | rigor | description | status |` — spells the
# same slot `rigor`, and REQ-1e does not widen that table. Without the alias
# `validate_task_ledger` would have to keep a second `## Tasks` parser alive for one cell,
# which is the whole of what AC-1e.1 forbids. Ruled A-39, 2026-09-12.
#
# NO TABLE CARRIES BOTH SPELLINGS, and the header scan takes the first cell to match, so
# the alias cannot shadow a real `kind` column.
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
expect_eq "…and the rigor cell reaches slot 3, which the wave schema calls kind" \
  "[single][double][]" \
  "$(printf '%s\n' "$ROWS_TASK_SCALE" | awk -F'\t' '{ printf "[%s]", $3 }')"
expect_eq "units_field takes that cell by either name" "double double" \
  "$(bash -c '. "$1" >/dev/null 2>&1 || exit 127
     row="$(units_rows "$2" | sed -n 2p)"
     printf "%s %s" "$(units_field "$row" rigor)" "$(units_field "$row" kind)"' \
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
expect_contains "a kind outside the eight names the kind and the vocabulary" \
  "T4: kind slice is not one of build test verify review doc integrate close prototype" "$VAL_BAD"  # retired: slice
expect_contains "a status outside the four names the status and the vocabulary" \
  "T5: status done is not one of pending active landed dropped" "$VAL_BAD"
expect_contains "a dep naming no row names the dep" \
  "T6: dep T99 names no row in the table" "$VAL_BAD"
# THE STEP-6 ROW THAT REACHES ONLY T1 IS NOT ACCUSED (wave-26 T2, D2). Beside the six lines
# above, which prove the extractor reads this output, no line begins with T7.
expect_eq "a Step-6 row that reaches one Step-4 row of five draws no violation" "" \
  "$(printf '%s\n' "$VAL_BAD" | grep '^T7: ')"

# PAIRED POSITIVE. The good row is in the same table and is not accused of anything.
expect_eq "the one well-formed row draws no violation of its own" "0" \
  "$(printf '%s\n' "$VAL_BAD" | grep -c '^T1: [^d]' | tr -d ' ')"

# ============================================================
section "6b — the every-build-row rule is gone: a later row waits for what it reads (wave-26 T2, D2)"
# ============================================================
#
# Through 1.10 the validator refused any Step-5+ row that did not depend, transitively, on
# every Step-4 row, and `units_add_row` threaded each new Step-4 id into the rows that owed it
# (research R3 B4, B6). That rule is removed: a verify or final-review row waits for the build
# through its `head` read, and a review that reads only the diff waits for nobody. The table
# below is the one that rule used to refuse — T5 reaches T2 and not T3.

cat > "$SANDBOX/leak.md" <<'LEAK_EOF'
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 3 | doc | plan written | orchestrator | — | 30m | all | plan | landed |
| T2 | 4 | build | first | implementor | T1 | 15m | REQ-x | a.sh | landed |
| T3 | 4 | build | second | implementor | T1 | 15m | REQ-x | b.sh | landed |
| T4 | 5 | verify | reaches both Step-4 rows | researcher | T2, T3 | 30m | all | w.md | pending |
| T5 | 5 | test | reaches only T2 | test-runner | T2 | 40m | all | f.md | pending |
LEAK_EOF

expect_eq "6b.1 a Step-5 row that reaches one Step-4 row of two validates clean (rc 0)" "0" \
  "$(call_rc units_validate "$SANDBOX/leak.md")"
# THE EXTRACTOR READS THIS FIXTURE: one real fault planted in the same table is named, and
# still nothing accuses T5 of the edge it does not carry.
sed 's/| T5 | 5 | test | reaches only T2 | test-runner | T2 |/| T5 | 5 | test | reaches only T2 | test-runner | T2, T99 |/' \
  "$SANDBOX/leak.md" > "$SANDBOX/leak-t99.md"
expect_eq "6b.2 …while a planted dep on a missing row is the one line printed" \
  "T5: dep T99 names no row in the table" "$(call units_validate "$SANDBOX/leak-t99.md")"

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
expect_eq "the migration fixture carries the specimen's nineteen rows" "19" "$(nlines "$DIFF_IDS")"

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
expect_eq "the escaped cell reads back with a LITERAL pipe, the escape undone" \
  "the five PreToolUse|Bash walls fold into one process" "$(printf '%s\n' "$ESC_T1" | cut -f4)"
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

expect_eq "the fixture really does carry one escaped pipe, and the control none" "1 0" \
  "$(printf '%s %s' \
      "$(grep -c '\\[|]' "$SANDBOX/escaped-live.md" | tr -d ' ')" \
      "$(grep -c '\\[|]' "$SANDBOX/escaped-live-control.md" | tr -d ' ')")"

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
section "9b — a RAW pipe in a cell is NAMED, once, and the shifted row is not accused of the shift"
# ============================================================
#
# §9 is about `\|`, the escape a writer got right. This section is about the one they did
# not: a RAW `|` typed into a cell. `esc()` folds only the escaped form, so a raw pipe stays
# an ordinary separator — it opens a field the header does not have and every cell after it
# is read one slot early. What came back before this section existed was three violations
# against cells that were correct, and no mention of the pipe at all (measured at c0e2c18,
# record/wave-15-fixit-182/step1-research-rows.md Row 8):
#
#   T2: status b.sh is not one of pending active landed dropped
#   T2: dep pipe names no row in the table
#   T2: step 5 does not depend transitively on step-4 row T1
#
# THE ROW BELOW IS THAT MEASUREMENT'S OWN ROW, byte for byte. One line must come back, it must
# name the pipe and the repair, and none of those three may survive beside it — a reader who
# acts on any of them edits a cell that was never wrong.
#
# THE TWO NUMBERS ARE `|`-DELIMITED FIELD COUNTS, both sides taken the same way (the split
# arity less the trailing empty field), so they are one greater than the cells a human counts.
# What a reader acts on is that the first exceeds the second; the fixture pins the arithmetic
# so it cannot drift between the library and the two gates that print its line.

cat > "$SANDBOX/raw-pipe.md" <<'RAW_PIPE_EOF'
---
current: 4
---

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | do a | implementor | — | 30m | REQ-1 | a.sh | landed |
| T2 | 5 | verify | do b | a raw | pipe | T1 | S | REQ-1 | b.sh | pending |
RAW_PIPE_EOF

VAL_RAW="$(call units_validate "$SANDBOX/raw-pipe.md")"

expect_eq "the shifted row draws exactly one violation" "1" "$(nlines "$VAL_RAW")"
expect_eq "…and it names the row, both counts, the pipe and the repair" \
  'T2: 12 cells for 11 columns — a raw | inside a cell? escape it as \|' "$VAL_RAW"
expect_eq "…and units_validate still exits 1" "1" "$(call_rc units_validate "$SANDBOX/raw-pipe.md")"
expect_eq "none of the three misleading lines the shift used to produce survives" "0" \
  "$(printf '%s\n' "$VAL_RAW" | grep -cE 'is not one of|names no row|does not depend' | tr -d ' ')"

# SUPPRESSION IS PER ROW, not per table. A second row breaking an ordinary invariant must
# still be named, or the single line would have been bought by saying less.
cat > "$SANDBOX/raw-pipe-mixed.md" <<'RAW_MIXED_EOF'
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | do a | implementor | — | 30m | REQ-1 | a.sh | landed |
| T2 | 4 | build | do b | a raw | pipe | T1 | S | REQ-1 | b.sh | pending |
| T3 | 4 | build | do c | implementor | — | 10m | REQ-1 | c.sh | doing |
RAW_MIXED_EOF

VAL_MIXED="$(call units_validate "$SANDBOX/raw-pipe-mixed.md")"
expect_eq "a shifted row and a bad status in one table yield exactly two lines" "2" \
  "$(nlines "$VAL_MIXED")"
expect_contains "…the shifted row named once, for the pipe" \
  "T2: 12 cells for 11 columns" "$VAL_MIXED"
expect_contains "…and the row that is merely wrong still named for its own fault" \
  "T3: status doing is not one of" "$VAL_MIXED"

# THE DISCRIMINATOR: FEWER cells is NOT this fault. A short row is a row with empty cells,
# which the per-column rules already name accurately; only a row WIDER than the header can be
# carrying a raw pipe, and printing the advice for a short row would be a guess.
cat > "$SANDBOX/short-row.md" <<'SHORT_EOF'
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | do a | implementor | — | 30m | REQ-1 | a.sh | landed |
| T2 | 4 | build | truncated |
SHORT_EOF

VAL_SHORT="$(call units_validate "$SANDBOX/short-row.md")"
expect_eq "a row SHORTER than the header draws no raw-pipe line" "0" \
  "$(printf '%s\n' "$VAL_SHORT" | grep -c 'a raw' | tr -d ' ')"
expect_contains "…and is named by the ordinary rules instead" \
  "T2: status (empty) is not one of" "$VAL_SHORT"

# THE ESCAPE IS STILL THE ESCAPE (AC-8.3). §9's fixture carries three escaped pipes under the
# same header: the fold happens BEFORE the count, so not one of them may look like this fault.
expect_eq "the escaped form draws no raw-pipe line" "" \
  "$(call units_validate "$SANDBOX/escaped-cell.md" | grep 'a raw' || true)"

# THE FOLD RUNS BEFORE THE COUNT ON THE SAME ROW, which a second fixture cannot show: a cell
# carrying BOTH an escape and a raw pipe must be named for the raw one exactly once. If the
# count were taken on the unfolded record the escape would inflate it, and the advice would be
# "escape it" about a pipe that already is.
cat > "$SANDBOX/raw-and-escaped.md" <<'BOTH_EOF'
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | a \| b and a raw | pipe | implementor | — | 30m | REQ-1 | a.sh | landed |
BOTH_EOF

VAL_BOTH="$(call units_validate "$SANDBOX/raw-and-escaped.md")"
expect_eq "a row carrying an escape AND a raw pipe is named once, for the raw one" \
  'T1: 12 cells for 11 columns — a raw | inside a cell? escape it as \|' "$VAL_BOTH"

# units_rows IS UNTOUCHED BY THE RULE. The shifted row is still emitted with its twelve
# fields: the violation is advice to whoever wrote the plan, not a reason to hide a row from
# the schedulers that can still read most of it.
ROWS_RAW="$(call units_rows "$SANDBOX/raw-pipe.md")"
expect_eq "both rows still come through units_rows" "2" "$(nlines "$ROWS_RAW")"
expect_eq "…each carrying thirteen fields" "2" \
  "$(printf '%s\n' "$ROWS_RAW" | awk -F'\t' 'NF == 13 { n++ } END { print n + 0 }')"

# ============================================================
section "10 — the worktree cell: slot 11, header-keyed, and OPTIONAL (wave-14 REQ-2, ADR-027)"
# ============================================================
#
# WHY THE COLUMN EXISTS. ADR-027 makes the `## Tasks` table the register of in-flight units:
# the dispatcher writes the tree it created into the row, and the evidence gate reads the row
# back to judge a worktree commit at that row's step. This library is the only reader, so the
# cell is a slot here or it is a second parser somewhere else.
#
# OPTIONAL, AND THAT IS A RULE, NOT AN OMISSION. Every plan written before this wave — and
# every solo-writer plan after it — carries no `worktree` column, and none of them becomes
# invalid for it. An absent column reads as an empty cell on every row and raises NO
# `missing column` violation, which is the one place slot 11 differs from the ten required
# slots §7 covers.

cat > "$SANDBOX/worktree-column.md" <<'WT_COL_EOF'
---
current: 4
---

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the build in its own tree | senior-implementor | — | 60m | REQ-2 | a.sh | 14-T1 | landed |
| T2 | 4 | build | the build that has no tree yet | implementor | T1 | 30m | REQ-2 | b.sh | — | pending |
| T3 | 6 | review | the review | critic | T1, T2 | 30m | REQ-2 | c.sh | 14-T3 | pending |

## Verification Matrix
WT_COL_EOF

ROWS_WT="$(call units_rows "$SANDBOX/worktree-column.md")"

expect_eq "the widened table yields one line per data row (3)" "3" "$(nlines "$ROWS_WT")"
expect_eq "…each carrying thirteen fields" "3" \
  "$(printf '%s\n' "$ROWS_WT" | awk -F'\t' 'NF == 13 { n++ } END { print n + 0 }')"

# THE CELL ITSELF, through the accessor the gate uses — never by number.
expect_eq "units_field reads T1's worktree cell by name" "14-T1" \
  "$(call units_field "$(printf '%s\n' "$ROWS_WT" | sed -n 1p)" worktree)"
expect_eq "…and T3's" "14-T3" \
  "$(call units_field "$(printf '%s\n' "$ROWS_WT" | sed -n 3p)" worktree)"

# THE DISCRIMINATOR. The column sits BETWEEN `Files` and `status`, which is where this
# wave's own plan carries it: a reader that took `status` positionally now reads `14-T1`
# as a status and refuses every row. Slot 10 must still be the status cell.
expect_eq "inserting the column ahead of status does not shift status" "landed" \
  "$(call units_field "$(printf '%s\n' "$ROWS_WT" | sed -n 1p)" status)"
expect_eq "…nor Files" "a.sh" \
  "$(call units_field "$(printf '%s\n' "$ROWS_WT" | sed -n 1p)" Files)"

# A row whose tree is an em dash is a row with NO tree — the same "none" spelling `deps`
# uses — and it comes through as the literal cell, not as an error.
#
# THE ROW IS `pending`, AND THAT IS load-BEARING SINCE WAVE-17 (REQ-1, AC-1.2, ADR-032): a
# row with no tree yet is a row nobody is working in. §12 is where the `active` twin of this
# exact row becomes a fault, and this fixture is its silent control — so the clean-validate
# assertion below asserts the rule discriminates, not that the rule is absent.
expect_eq "a row with no tree yet reads its cell literally" "—" \
  "$(call units_field "$(printf '%s\n' "$ROWS_WT" | sed -n 2p)" worktree)"

expect_eq "the widened table breaks no invariant" "" \
  "$(call units_validate "$SANDBOX/worktree-column.md")"
expect_eq "…and exits 0" "0" "$(call_rc units_validate "$SANDBOX/worktree-column.md")"

# ---------- the column is OPTIONAL: the live specimen carries none ----------
#
# §7's `missing column` rule holds for the ten required slots and must NOT reach this one.
# The live specimen is the proof: 22 rows, no `worktree` header cell, and a clean validate
# (§5 already asserts the clean part — this asserts that widening the contract did not
# quietly make every pre-wave plan invalid).
expect_eq "a table with no worktree column raises no missing-column violation" "" \
  "$(call units_validate "$SANDBOX/live.md" | grep 'worktree' || true)"
expect_eq "…and its rows read the absent cell as empty" "" \
  "$(call units_field "$(printf '%s\n' "$ROWS_LIVE" | sed -n 1p)" worktree)"
expect_eq "…while a REQUIRED column absent is still a violation (the rule discriminates)" \
  "## Tasks: missing column step" \
  "$(call units_validate "$SANDBOX/missing-column.md" | grep 'missing column')"

# ---------- header-keyed, proved the same name-blind way §2 proves it ----------
reverse_cells "$SANDBOX/worktree-column.md" > "$SANDBOX/worktree-column-reversed.md"
expect_eq "the reversed widened fixture's header starts at status and ends at id" \
  "| status | worktree | Files | serves | size | deps | agent | task | kind | step | id |" \
  "$(grep -n '^| status' "$SANDBOX/worktree-column-reversed.md" | head -1 | cut -d: -f2-)"
expect_eq "reversing every column of the widened table changes not one byte of the TSV" \
  "$ROWS_WT" "$(call units_rows "$SANDBOX/worktree-column-reversed.md")"

# ============================================================
section "11 — units_has_column: the header's own answer (wave-16 REQ-3, AC-3.2)"
# ============================================================
#
# WHY A FOURTH VERB. The evidence gate's worktree lead-in ("no ## Tasks row names worktree
# <tree>") fires whenever no row's `worktree` cell matches the tree it is committing from —
# and an ABSENT `worktree` column reads every row's cell as empty, so a pre-14 table gets
# the register's lead-in when what it actually has is a table that never claimed to track
# trees (research R2 row 6a). The gate cannot tell those apart from `units_rows` alone:
# slot 11 is optional, so it is deliberately absent from the missing-column set §10 pins.
# This verb answers the one question that discriminates, off the same single parse.
#
# fails-when: a table carrying the column answers no, or a table without it answers yes.

expect_eq "11.1 a table that carries the worktree column answers yes" "0" \
  "$(call_rc units_has_column "$SANDBOX/worktree-column.md" worktree)"
expect_eq "11.2 …and the live specimen, which omits it, answers no" "1" \
  "$(call_rc units_has_column "$SANDBOX/live.md" worktree)"
# THE REQUIRED COLUMNS TOO, so the verb is not a worktree special case: the same question
# asked of `step` discriminates the fixture §10 uses for the missing-column rule.
expect_eq "11.3 a required column the header carries answers yes" "0" \
  "$(call_rc units_has_column "$SANDBOX/live.md" id)"
expect_eq "11.4 …and one it does not answers no" "1" \
  "$(call_rc units_has_column "$SANDBOX/missing-column.md" step)"
# NO TABLE IS NOT A COLUMN. The verb answers about a header, and a file with no `## Tasks`
# table has none — same non-zero `_units_read` gives `units_rows`, never a crash.
expect_eq "11.5 a file with no ## Tasks table answers no" "1" \
  "$(call_rc units_has_column "$SANDBOX/no-table.md" worktree)"
# AND IT IS HEADER-KEYED, not positional: the reversed widened fixture still carries the
# column and still says so.
expect_eq "11.6 reversing every column does not change the answer" "0" \
  "$(call_rc units_has_column "$SANDBOX/worktree-column-reversed.md" worktree)"


# ============================================================
section "12 — an ACTIVE row names its tree, or the table is wrong (wave-17 REQ-1, AC-1.2, ADR-032)"
# ============================================================
#
# THE REGISTER WAS UNFED, AND NOTHING SAID SO. The evidence gate resolves a worktree commit
# to the `## Tasks` row that names the tree, and every row of every plan this repo shipped
# through wave-16 carried `—` in that cell (research R1, "The one fact"): the arm was not
# broken, it was never reached, and the only symptom was a run whose `current:` had to be
# regressed by hand to land a writer's commit. ADR-032 makes the row the tree's record, and a
# record that does not record is a shape fault — caught where the plan is written, not one
# round trip later at the writer's commit.
#
# THE RULE IS THREE-WAY, and all three ways are asserted here because only the set of them is
# the rule:
#   active + no cell, in a table WITH the column  → a fault naming the id;
#   pending + no cell                             → silent (a row nobody is working in);
#   any status, in a table WITHOUT the column     → silent (a plan that never tracked trees).
# The third is the one that decides whether this arm can ship at all: `units_field` reads an
# absent column as an empty cell on every row, so an arm that skipped `units_has_column`
# would refuse every pre-wave-14 and every solo-writer plan in existence.
#
# fails-when: the active row draws no line, or the pending row / the column-less table draws
# one.

cat > "$SANDBOX/active-no-tree.md" <<'ACT_EOF'
---
current: 4
---

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the build in its own tree | senior-implementor | — | 60m | REQ-1 | a.sh | 17-T1 | active |
| T2 | 4 | build | the build whose tree the row forgot | implementor | — | 30m | REQ-1 | b.sh | — | active |
| T3 | 4 | build | the build dispatched with no cell at all | implementor | — | 30m | REQ-1 | c.sh |  | active |
| T4 | 4 | build | the build not dispatched yet | implementor | — | 30m | REQ-1 | d.sh | — | pending |
| T5 | 4 | build | the build that landed and was torn down | implementor | — | 30m | REQ-1 | e.sh | — | landed |
| T6 | 6 | review | the review | critic | T1, T2, T3, T4, T5 | 30m | REQ-1 | f.sh | — | pending |

## Verification Matrix
ACT_EOF

VAL_ACT="$(call units_validate "$SANDBOX/active-no-tree.md")"

expect_eq "12.1 an active row whose cell is an em dash is named" "1" \
  "$(printf '%s\n' "$VAL_ACT" | grep -c '^T2: active row names no worktree' | tr -d ' ')"
expect_eq "12.2 …and an active row whose cell is empty is named the same way" "1" \
  "$(printf '%s\n' "$VAL_ACT" | grep -c '^T3: active row names no worktree' | tr -d ' ')"
expect_eq "12.3 the active row that DOES name its tree draws nothing" "0" \
  "$(printf '%s\n' "$VAL_ACT" | grep -c '^T1:' | tr -d ' ')"
# THE TWO SILENT STATUSES, asserted BY ID rather than by counting lines: a rule that fired on
# every empty cell would still pass a total-count assertion if the active rows were absent.
expect_eq "12.4 a pending row with no tree is not a fault" "0" \
  "$(printf '%s\n' "$VAL_ACT" | grep -c '^T4:' | tr -d ' ')"
expect_eq "12.5 …nor is a landed one whose tree is gone" "0" \
  "$(printf '%s\n' "$VAL_ACT" | grep -c '^T5:' | tr -d ' ')"
expect_eq "12.6 the table breaks this invariant twice and no other" "2" "$(nlines "$VAL_ACT")"
expect_eq "12.7 …and units_validate exits 1 for it" "1" \
  "$(call_rc units_validate "$SANDBOX/active-no-tree.md")"

# ONLY A ROW THAT WRITES THE HEAD OWES A TREE (wave-26 T32). A verify, review or doc row whose
# Files cell names nothing outside the docs root (or nothing at all) commits nothing a gate must
# attribute; it runs active with an empty worktree cell. The predicate is the scheduler's
# `writes_head`, asked of the same cell; a row naming one tracked file keeps the refusal.
cat > "$SANDBOX/active-docs-only.md" <<'ACD_EOF'
---
current: 5
---

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 5 | verify | the floor, writing its record | test-runner | — | 30m | REQ-1 | .bionic/docs/record/w/floor.txt | — | active |
| T2 | 6 | review | the review, writing nothing | critic | — | 30m | REQ-1 | — | — | active |
| T3 | 5 | verify | the floor that also edits a test | test-runner | — | 30m | REQ-1 | .bionic/docs/record/w/f.txt, tests/x.test.sh | — | active |
ACD_EOF
VAL_ACD="$(call units_validate "$SANDBOX/active-docs-only.md")"
expect_eq "12.8 an active row whose Files are all under the docs root owes no tree" "0" \
  "$(printf '%s\n' "$VAL_ACD" | grep -c '^T1: active row names no worktree' | tr -d ' ')"
expect_eq "12.9 …nor does one whose Files cell names no path" "0" \
  "$(printf '%s\n' "$VAL_ACD" | grep -c '^T2: active row names no worktree' | tr -d ' ')"
expect_eq "12.10 …while a row naming one tracked file beside them is still refused" "1" \
  "$(printf '%s\n' "$VAL_ACD" | grep -c '^T3: active row names no worktree' | tr -d ' ')"

# ---------- the column-less table: the arm must not reach it ----------
#
# The same rows, one column narrower. Every `worktree` cell now reads empty for the reason
# §10 gives — slot 11 of a header that has no slot 11 — and the rule must stay silent, or
# every plan written before wave-14 becomes invalid on the day this ships.
cat > "$SANDBOX/active-no-column.md" <<'ACC_EOF'
---
current: 4
---

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the build | senior-implementor | — | 60m | REQ-1 | a.sh | active |
| T2 | 4 | build | the other build | implementor | — | 30m | REQ-1 | b.sh | active |
| T6 | 6 | review | the review | critic | T1, T2 | 30m | REQ-1 | f.sh | pending |

## Verification Matrix
ACC_EOF

expect_eq "12.8 a table with no worktree column raises no worktree fault, whatever the status" "" \
  "$(call units_validate "$SANDBOX/active-no-column.md")"
expect_eq "12.9 …and exits 0" "0" "$(call_rc units_validate "$SANDBOX/active-no-column.md")"
# AND THE DISCRIMINATOR IS THE HEADER, not the fixture: the same two active rows, in a table
# that carries the column, are two faults (12.1/12.2 above prove the positive half).
expect_eq "12.10 units_has_column is what tells the two fixtures apart" "0 1" \
  "$(printf '%s %s' "$(call_rc units_has_column "$SANDBOX/active-no-tree.md" worktree)" \
     "$(call_rc units_has_column "$SANDBOX/active-no-column.md" worktree)")"

# ============================================================
section "14 — a mid-run build row owes no edge to any later row (wave-26 T2, D2; was wave-17 REQ-5)"
# ============================================================
#
# This section used to pin the transitive arm's full report — one Step-5 row threaded to one
# of four Step-4 rows named all three it missed. The arm is gone with its rule (D2): the same
# table is a valid table, because the floor row's wait is its `head` read in a reads table, or
# its own deps ids in a table without one, and nothing else.

cat > "$SANDBOX/three-missing.md" <<'THREE_EOF'
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 3 | doc | plan written | orchestrator | — | 30m | all | plan | landed |
| T2 | 4 | build | first | implementor | T1 | 15m | REQ-x | a.sh | landed |
| T3 | 4 | build | second | implementor | T1 | 15m | REQ-x | b.sh | landed |
| T4 | 4 | build | third | implementor | T1 | 15m | REQ-x | c.sh | landed |
| T5 | 4 | build | fourth | implementor | T1 | 15m | REQ-x | d.sh | pending |
| T9 | 5 | test | the floor, threaded to one build row of four | test-runner | T2 | 40m | all | f.md | pending |
THREE_EOF

expect_eq "14.1 a Step-5 row threaded to one Step-4 row of four validates clean (rc 0)" "0" \
  "$(call_rc units_validate "$SANDBOX/three-missing.md")"
expect_eq "14.2 …and it is ready on its own deps: T2 landed, the open T5 is not its prerequisite" "yes" \
  "$(call units_ready "$SANDBOX/three-missing.md" 5 | grep -qx T9 && echo yes || echo no)"
expect_eq "14.3 …beside T5, the open build row, which is ready too" "yes" \
  "$(call units_ready "$SANDBOX/three-missing.md" 5 | grep -qx T5 && echo yes || echo no)"
# THE OLD MESSAGE IS GONE FROM THE LIBRARY, and so is the program that computed it: neither the
# transitive arm's words nor `_units_graph_awk` survive in units.sh (the shipped file is read,
# and its own `units_validate` definition proves the read found the file).
expect_eq "14.4 units.sh still defines units_validate (the read below found the library)" "1" \
  "$(/usr/bin/grep -c '^units_validate() {' "$LIB" | tr -d ' ')"
expect_eq "14.5 …and carries neither the transitive arm's words nor its graph program" "0 0" \
  "$(/usr/bin/grep -c 'step-4 prerequisite' "$LIB" | tr -d ' ') $(/usr/bin/grep -c '_units_graph_awk' "$LIB" | tr -d ' ')"

# ============================================================
section "13 — the base cell: slot 12, OPTIONAL, and a commit id when it holds one (wave-17 REQ-2, AC-2.1, ADR-032)"
# ============================================================
#
# WHY THE COLUMN EXISTS. `spawn-worktree.sh` prints the commit it cut a tree from
# (`base=<sha>` on its contract line) and, through wave-16, nothing wrote that anywhere: the
# landing gate reconstructed the tree's origin by merge-basing against a BRANCH NAME, which is
# right only while the tree was cut from that branch's own history (research R1 A2). ADR-032
# makes the row the tree's record, and this is the origin half of it — declared in the same
# edit as the `worktree` cell, read by the landing gate as the diff base.
#
# WHAT IS VALIDATED, AND WHAT IS NOT. The SHAPE of the cell, here, at the write: 7 to 40 hex
# characters, the range `git rev-parse` itself takes. Whether the repository HOLDS that commit
# is not asked — this library is a pure function of a file, no plan reader forks git, and the
# landing gate that does fork git announces the fallback when the id resolves to nothing.
#
# THE RULE IS FOUR-WAY, and all four are asserted because only the set of them is the rule:
#   a 7-hex or 40-hex cell        -> silent, whatever the status;
#   an em dash / an empty cell    -> silent (declaring no origin is legal);
#   a cell that is not hex, or is -> a fault naming the id and the cell;
#     shorter than 7 / longer than 40
#   a table with no base column   -> silent (every plan written before this wave).
#
# fails-when: a junk cell draws no line, or a legal cell / a column-less table draws one.

cat > "$SANDBOX/base-column.md" <<'BASE_EOF'
---
current: 4
---

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the build whose row records its origin | senior-implementor | — | 60m | REQ-2 | a.sh | 17-T1 | 73a05e0 | active |
| T2 | 4 | build | the build that declares no origin | implementor | — | 30m | REQ-2 | b.sh | 17-T2 | — | active |
| T3 | 4 | build | the build whose origin cell is a branch | implementor | — | 30m | REQ-2 | c.sh | 17-T3 | wave/17-fixit | active |
| T4 | 4 | build | the build whose origin is a full sha | implementor | — | 30m | REQ-2 | d.sh | 17-T4 | 73a05e0c0b37191bdc67ed3ad56f3a6fa16e5d3a | active |
| T5 | 4 | build | the build whose origin is a character short | implementor | — | 30m | REQ-2 | e.sh | 17-T5 | 73a05e | active |
| T6 | 4 | build | the build whose origin is a character long | implementor | — | 30m | REQ-2 | f.sh | 17-T6 | 73a05e0c0b37191bdc67ed3ad56f3a6fa16e5d3ab | active |
| T7 | 4 | build | the build with no origin cell at all | implementor | — | 30m | REQ-2 | g.sh | 17-T7 |  | active |
| T8 | 4 | build | the build whose origin is upper-cased | implementor | — | 30m | REQ-2 | h.sh | 17-T8 | 73A05E0 | active |
| T9 | 6 | review | the review | critic | T1, T2, T3, T4, T5, T6, T7, T8 | 30m | REQ-2 | i.sh | — | — | pending |

## Verification Matrix
BASE_EOF

ROWS_BASE="$(call units_rows "$SANDBOX/base-column.md")"
VAL_BASE="$(call units_validate "$SANDBOX/base-column.md")"

# ---------- the cell comes through, by name, without shifting its neighbours ----------
expect_eq "the twelve-column table yields one line per data row (9)" "9" "$(nlines "$ROWS_BASE")"
expect_eq "units_field reads T1's base cell by name" "73a05e0" \
  "$(call units_field "$(printf '%s\n' "$ROWS_BASE" | sed -n 1p)" base)"
expect_eq "…and T4's, a full forty" "73a05e0c0b37191bdc67ed3ad56f3a6fa16e5d3a" \
  "$(call units_field "$(printf '%s\n' "$ROWS_BASE" | sed -n 4p)" base)"
# THE DISCRIMINATOR, the same one §10 makes for slot 11: the column sits between `worktree`
# and `status`, which is where this wave's own plan carries it. A reader that took `status`
# positionally now reads a sha as a status and refuses every row.
expect_eq "inserting the column ahead of status does not shift status" "active" \
  "$(call units_field "$(printf '%s\n' "$ROWS_BASE" | sed -n 1p)" status)"
expect_eq "…nor the worktree cell beside it" "17-T1" \
  "$(call units_field "$(printf '%s\n' "$ROWS_BASE" | sed -n 1p)" worktree)"
# A row that declares no origin reads its cell literally, exactly as the worktree cell does.
expect_eq "a row that declares no origin reads its cell literally" "—" \
  "$(call units_field "$(printf '%s\n' "$ROWS_BASE" | sed -n 2p)" base)"

# ---------- the shape rule ----------
expect_eq "13.1 a cell that is not hex at all is named" "1" \
  "$(printf '%s\n' "$VAL_BASE" | grep -c '^T3: base wave/17-fixit is not a commit id' | tr -d ' ')"
expect_eq "13.2 …a cell one character short of seven is named" "1" \
  "$(printf '%s\n' "$VAL_BASE" | grep -c '^T5: base 73a05e is not a commit id' | tr -d ' ')"
expect_eq "13.3 …and one character past forty" "1" \
  "$(printf '%s\n' "$VAL_BASE" | grep -c '^T6: base 73a05e0c0b37191bdc67ed3ad56f3a6fa16e5d3ab is not a commit id' | tr -d ' ')"
# THE LEGAL CELLS, ASSERTED BY ID rather than by counting lines: a rule that fired on every
# non-empty cell would still satisfy a total-count assertion if the junk rows were absent.
expect_eq "13.4 a seven-hex cell draws nothing" "0" \
  "$(printf '%s\n' "$VAL_BASE" | grep -c '^T1:' | tr -d ' ')"
expect_eq "13.5 …nor does a full forty" "0" \
  "$(printf '%s\n' "$VAL_BASE" | grep -c '^T4:' | tr -d ' ')"
expect_eq "13.6 …nor an em dash, which is how a row declares no origin" "0" \
  "$(printf '%s\n' "$VAL_BASE" | grep -c '^T2:' | tr -d ' ')"
expect_eq "13.7 …nor an empty cell, the same fact spelled differently" "0" \
  "$(printf '%s\n' "$VAL_BASE" | grep -c '^T7:' | tr -d ' ')"
# UPPER CASE IS A COMMIT ID: `git rev-parse` and `git merge-base` both take one (measured),
# so the cell the landing gate will hand to git is legal and this arm must not refuse it.
expect_eq "13.8 …nor an upper-cased sha, which git itself resolves" "0" \
  "$(printf '%s\n' "$VAL_BASE" | grep -c '^T8:' | tr -d ' ')"
expect_eq "13.9 the table breaks this invariant three times and no other" "3" "$(nlines "$VAL_BASE")"
expect_eq "13.10 …and units_validate exits 1 for it" "1" \
  "$(call_rc units_validate "$SANDBOX/base-column.md")"

# ---------- the column is OPTIONAL: no table written before this wave carries it ----------
#
# §7's `missing column` rule stops at the ten required slots and must not reach this one, for
# the reason §10 gives for slot 11: an absent optional column reads as an empty cell on every
# row, and a rule that fired there would invalidate every plan in existence.
expect_eq "13.11 a table with no base column raises no missing-column violation" "" \
  "$(call units_validate "$SANDBOX/live.md" | grep 'base' || true)"
expect_eq "13.12 …and its rows read the absent cell as empty" "" \
  "$(call units_field "$(printf '%s\n' "$ROWS_LIVE" | sed -n 1p)" base)"
expect_eq "13.13 …and the wave-14 fixture, which carries worktree but no base, still validates clean" "" \
  "$(call units_validate "$SANDBOX/worktree-column.md")"

# ---------- units_has_column answers for it, and the answer is the header's ----------
expect_eq "13.14 a table that carries the base column answers yes" "0" \
  "$(call_rc units_has_column "$SANDBOX/base-column.md" base)"
expect_eq "13.15 …and the wave-14 fixture, which carries only worktree, answers no" "1" \
  "$(call_rc units_has_column "$SANDBOX/worktree-column.md" base)"

# ---------- header-keyed, proved the name-blind way §2 and §10 prove it ----------
reverse_cells "$SANDBOX/base-column.md" > "$SANDBOX/base-column-reversed.md"
expect_eq "13.16 reversing every column of the twelve-column table changes not one byte of the TSV" \
  "$ROWS_BASE" "$(call units_rows "$SANDBOX/base-column-reversed.md")"
expect_eq "13.17 …and it reports the same three faults, in the same words" \
  "$VAL_BASE" "$(call units_validate "$SANDBOX/base-column-reversed.md")"

# ============================================================
section "16 — units_memoised: one parse answers every verb, for the length of one command (wave-19 REQ-6, D7)"
#
# THE FILL DUTY ASKS THE TABLE THREE QUESTIONS — has it a `step` column, has it an `id`
# column, which rows are ready — and each verb used to parse the file again. `units_memoised
# <plan> <command…>` reads it once and every verb the command reaches answers <plan> from that
# read. THE MEMO IS SCOPED TO THE COMMAND, not the process: a caller that edits a plan and
# reads it back (close-out, a suite reusing one fixture path) must never see a stale table,
# so the rows below rewrite the file INSIDE the command and prove the verbs still answer the
# first read, then read it again AFTER the command and prove the edit is seen.
cat > "$SANDBOX/memo.md" <<'MEMO_EOF'
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the landed row | implementor | — | 30m | REQ-x | a.sh | landed |
| T2 | 4 | build | the ready row | implementor | T1 | 30m | REQ-x | b.sh | pending |
MEMO_EOF
# 16.9-16.12 ask the header of an untouched copy: 16.1's command rewrites memo.md on purpose.
cp "$SANDBOX/memo.md" "$SANDBOX/memo-cols.md"
MEMO_OUT="$(bash -c '
  . "$1" >/dev/null 2>&1 || exit 127
  plan="$2"
  inner() {
    # The file changes under the command: no table header, no rows.
    printf "## Tasks\n\nnothing here\n" > "$plan"
    printf "in-rows=%s\n" "$(units_rows "$plan" | cut -f1 | tr "\n" ,)"
    units_has_column "$plan" step && printf "in-step=yes\n" || printf "in-step=no\n"
    printf "in-ready=%s\n" "$(units_ready "$plan" 4)"
  }
  units_memoised "$plan" inner
  printf "after-rc=%s\n" "$?"
  units_has_column "$plan" step && printf "after-step=yes\n" || printf "after-step=no\n"
  printf "after-rows=%s\n" "$(units_rows "$plan" | cut -f1 | tr "\n" ,)"
' _ "$LIB" "$SANDBOX/memo.md" 2>&1)"
expect_contains "16.1 inside the command, units_rows answers the first read" "in-rows=T1,T2," "$MEMO_OUT"
expect_contains "16.2 …units_has_column too" "in-step=yes" "$MEMO_OUT"
expect_contains "16.3 …and units_ready" "in-ready=T2" "$MEMO_OUT"
expect_contains "16.4 the command's own status is the helper's" "after-rc=0" "$MEMO_OUT"
expect_contains "16.5 after the command, the edited file is read fresh" "after-step=no" "$MEMO_OUT"
expect_eq "16.6 …by every verb (the table is gone, so no rows)" "after-rows=" "$(printf '%s\n' "$MEMO_OUT" | tail -1)"

# A different plan asked inside the command is read on its own, never answered from the memo.
MEMO_OTHER="$(bash -c '
  . "$1" >/dev/null 2>&1 || exit 127
  units_memoised "$2" units_rows "$3"
' _ "$LIB" "$SANDBOX/memo.md" "$SANDBOX/memo-cols.md" 2>&1 | cut -f1 | tr '\n' ,)"
expect_eq "16.7 a verb asked about another plan inside the command reads that plan" \
  "T1,T2," "$MEMO_OTHER"

# A plan with no table is memoised as "no table": every verb still answers exit 1 inside.
printf '## Not tasks\n' > "$SANDBOX/memo-none.md"
expect_eq "16.8 no table inside the command is still no table (units_rows exits 1)" "1" \
  "$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; units_memoised "$2" units_rows "$2"; printf %s $?' \
     _ "$LIB" "$SANDBOX/memo-none.md" 2>/dev/null | tail -c 1)"

# THE HEADER QUESTION IS WORD-EXACT, memo or not: `status` is not found inside `worktree`, a
# needle carrying a space names no column, and an empty needle matches nothing.
expect_eq "16.9 units_has_column status on a table with status" "0" "$(call_rc units_has_column "$SANDBOX/memo-cols.md" status)"
expect_eq "16.10 …worktree is not found inside another word" "1" "$(call_rc units_has_column "$SANDBOX/memo-cols.md" worktree)"
expect_eq "16.11 …a needle with a space names no column" "1" "$(call_rc units_has_column "$SANDBOX/memo-cols.md" 'id step')"
expect_eq "16.12 …an empty needle matches nothing" "1" "$(call_rc units_has_column "$SANDBOX/memo-cols.md" '')"

# ============================================================
section "17 — wave-20 REQ-5: readiness is the graph, the validator speaks per row, the row-add projector (AC-5.1, AC-5.2, AC-5.3)"
# ============================================================
#
# AC-5.1 fails-when: "at current: 5 a pending Step-6 row with landed prerequisites is absent
# from the ready set while a slot is free, an integrate row at Step 8 is present, or …". The
# fixture is research D1 §1's own shape, widened by the two gate-act kinds (Δ6) and a
# pending Step-3 prototype row (Δ1's "whatever its step" reaches it too).
cat > "$SANDBOX/graph.md" <<'GRAPH_EOF'
---
current: 5
---

## SDLC State

current: 5

- Step 5: in flight

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | landed | implementor | — | 30m | REQ-x | a.sh | landed |
| T2 | 4 | build | landed | implementor | — | 30m | REQ-x | b.sh | landed |
| T3 | 5 | verify | the floor, in flight | test-runner | T1, T2 | 30m | REQ-x | — | active |
| T4 | 6 | review | the review whose deps landed | critic | T1, T2 | 30m | REQ-x | — | pending |
| T5 | 7 | doc | behind the active floor | implementor | T3 | 30m | REQ-x | — | pending |
| T6 | 4 | build | a Step-4 row added late | implementor | — | 30m | REQ-x | c.sh | pending |
| T7 | 8 | integrate | the merge, deps landed | implementor | T1, T2 | 30m | REQ-x | — | pending |
| T8 | 9 | close | the close-out, deps landed | implementor | T1 | 30m | REQ-x | — | pending |
| T9 | 3 | prototype | an unfinished prototype | implementor | — | 30m | REQ-x | — | pending |
GRAPH_EOF

expect_eq "17.1 AC-5.1 at current: 5 the Step-6 row with landed deps is ready, with the late Step-4 row and the prototype" \
  "$(printf 'T4\nT6\nT9')" "$(call units_ready "$SANDBOX/graph.md" 5)"
expect_eq "17.2 …the Step-7 row behind an ACTIVE dep is not" "" \
  "$(call units_ready "$SANDBOX/graph.md" 5 | grep -x T5)"
expect_eq "17.3 AC-5.1 …the Step-8 integrate row is NOT ready at current: 5 though its deps landed (Δ6)" "" \
  "$(call units_ready "$SANDBOX/graph.md" 5 | grep -x T7)"
expect_eq "17.4 …nor the Step-9 close row" "" \
  "$(call units_ready "$SANDBOX/graph.md" 5 | grep -x T8)"
expect_eq "17.5 at current: 8 the integrate row joins the work rows; the close row still waits" \
  "$(printf 'T4\nT6\nT7\nT9')" "$(call units_ready "$SANDBOX/graph.md" 8)"
expect_eq "17.6 at current: 9 a gate act whose step the run has REACHED stays ready (reached, not equal)" \
  "$(printf 'T4\nT6\nT7\nT8\nT9')" "$(call units_ready "$SANDBOX/graph.md" 9)"
expect_eq "17.7 …and the argument is still checked: a word is a caller fault" "2" \
  "$(call_rc units_ready "$SANDBOX/graph.md" five)"

# THROUGH THE FILL. `fill_ready_set` is what the tick prints from and the stop wall refuses
# from (ADR-033), so AC-5.1 is asked of it too: rung 8, one slot occupied.
FILL_LIB="$REPO_ROOT/payload/scripts/lib/fill.sh"
# THE FILL IS LIVE ON THE PLAN'S APPROVAL (wave-26 T13; D3): these fixtures ask readiness, not
# the gate, so each is asked through a copy that carries an `approved-by:` line under its
# `current:` in `## SDLC State`.
fill_call() {
  local p="$1"; shift
  awk '{ print } /^## SDLC State/ { s = 1 } s && !d && /^current:/ { print "approved-by: fixture 2026-10-04T00:00Z \"approved\""; d = 1 }' \
    "$p" > "$p.approved"
  bash -c '. "$1" >/dev/null 2>&1 || exit 127; shift; fill_ready_set "$@"' _ "$FILL_LIB" "$p.approved" "$@" 2>/dev/null
}
expect_eq "17.8 AC-5.1 fill_ready_set at current: 5, rung 8, one open: the Step-6 row is in the set, the integrate row is not" \
  "$(printf 'T4\nT6\nT9')" "$(fill_call "$SANDBOX/graph.md" 8 1)"
# THE APPROVAL GATE STILL HOLDS, AND IT IS THE LINE (wave-26 T13; D3): the same plan at
# current: 5 without its `approved-by:` fills nothing, and at current: 3 with it fills.
expect_eq "17.9 …and the approval gate still holds: without approved-by: nothing fills at current: 5" "" \
  "$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; shift; fill_ready_set "$@"' _ "$FILL_LIB" "$SANDBOX/graph.md" 8 0 2>/dev/null)"
sed 's/^current: 5$/current: 3/' "$SANDBOX/graph.md" > "$SANDBOX/graph-at-3.md"
expect_eq "17.9b …while the approved plan at current: 3 fills (the gate is the approval, not the step)" \
  "$(printf 'T4\nT6\nT9')" "$(fill_call "$SANDBOX/graph-at-3.md" 8 1)"

# ---------- AC-5.2 (wave-20), RETIRED BY wave-26 T2 (D2) ----------
#
# FORTY STEP-4 ROWS AND ONE STEP-6 ROW that reaches only the first. wave-20 made this print one
# line instead of thirty-nine; wave-26 removed the rule it printed, so the table is valid and
# the review is ready on its one landed prerequisite.
{
  printf -- '## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | status |\n'
  printf -- '|---|---|---|---|---|---|---|---|---|---|\n'
  i=1
  while [ "$i" -le 40 ]; do
    printf '| T%s | 4 | build | row %s | implementor | — | 30m | REQ-x | f%s.sh | landed |\n' "$i" "$i" "$i"
    i=$((i + 1))
  done
  printf '| T41 | 6 | review | the review that reads one build | critic | T1 | 30m | REQ-x | — | pending |\n'
} > "$SANDBOX/forty.md"
expect_eq "17.10 a Step-6 row over forty Step-4 rows, depending on one, validates clean" "0" \
  "$(call_rc units_validate "$SANDBOX/forty.md")"
expect_eq "17.11 …and is ready" "T41" "$(call units_ready "$SANDBOX/forty.md" 5)"

# A LATE STEP-4 ROW HOLDS ONLY WHAT READS IT. T11 is added mid-run; the chain T90 → T91 → T92
# names T1 and each other. None of them waits for T11, and the table is valid.
cat > "$SANDBOX/added11.md" <<'ADDED_EOF'
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the planned build | implementor | — | 30m | REQ-x | a.sh | landed |
| T11 | 4 | build | the fixup added mid-run | implementor | — | 30m | REQ-x | b.sh | pending |
| T90 | 5 | verify | the floor | test-runner | T1 | 30m | REQ-x | — | pending |
| T91 | 6 | review | after the floor | critic | T90 | 30m | REQ-x | — | pending |
| T92 | 7 | doc | after the review | implementor | T91 | 30m | REQ-x | — | pending |
ADDED_EOF
expect_eq "17.14 a late Step-4 row that no row names leaves the table valid" "0" \
  "$(call_rc units_validate "$SANDBOX/added11.md")"
expect_eq "17.15 …the late row and the floor are both ready; the chain behind the floor waits for it" \
  "$(printf 'T11\nT90')" "$(call units_ready "$SANDBOX/added11.md" 5)"
expect_eq "17.16 …and the chain's waits are its own deps, in units_edges" "yes yes" \
  "$(E="$(call units_edges "$SANDBOX/added11.md")"; printf '%s %s' \
     "$(printf '%s\n' "$E" | grep -qxF "T90$(printf '\t')T91$(printf '\t')T90" && echo yes || echo no)" \
     "$(printf '%s\n' "$E" | grep -qxF "T91$(printf '\t')T92$(printf '\t')T91" && echo yes || echo no)")"
expect_eq "17.17 …with no edge out of the late row T11" "" \
  "$(call units_edges "$SANDBOX/added11.md" | awk -F'\t' '$1 == "T11"')"

# ---------- AC-5.3: units_add_row, the pure projector under `task-add` ----------
#
# `units_add_row <plan> <id> <step> <kind> <task> <agent> <deps> <size> <serves> <Files> [<reads>]`
# prints the WHOLE plan with the row added: the row as the last table row, status `pending`,
# and its `- <id>:` line under `## SDLC State`. It writes nothing. This table has no reads column, so a
# Step-4 row is threaded into the open frontier rows as 1.10 did (wave-26 T62; critic 2 K2-F1):
# with no head read, those deps are what holds the floor.
cat > "$SANDBOX/add.md" <<'ADD_EOF'
---
current: 5
---

# a plan

## SDLC State

current: 5

- Step 4: opened
  worktree: .worktrees/wave
- Step 5: in flight
- T1: landed at record/T1.md
- T3: dispatched to w-T3
  base: abc1234
- T4: pending dispatch — .worktrees/T4

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the build \| with a pipe | implementor | — | 30m | REQ-x | a.sh | — | — | landed |
| T3 | 5 | verify | the floor | test-runner | T1 | 30m | REQ-x | — | 20-T3 | abc1234 | active |
| T4 | 6 | review | after the floor | critic | T3 | 30m | REQ-x | — | — | — | pending |
| T5 | 7 | doc | a landed doc | implementor | T1 | 30m | REQ-x | — | — | — | landed |

## Verification Matrix

| AC | tier |
|---|---|
ADD_EOF
ADD_SUM_BEFORE="$(cksum < "$SANDBOX/add.md")"
ADD_OUT="$(call units_add_row "$SANDBOX/add.md" T6 4 build 'the fixup' 'bionic:implementor' '—' 30 REQ-5 'b.sh, c.sh')"
ADD_RC="$(call_rc units_add_row "$SANDBOX/add.md" T6 4 build 'the fixup' 'bionic:implementor' '—' 30 REQ-5 'b.sh, c.sh')"
printf '%s\n' "$ADD_OUT" > "$SANDBOX/add-projected.md"
expect_eq "17.22 AC-5.3 the projector exits 0" "0" "$ADD_RC"
expect_eq "17.23 …and writes nothing: the plan is byte-identical" "$ADD_SUM_BEFORE" "$(cksum < "$SANDBOX/add.md")"
expect_eq "17.24 …the new row is the table's last row, pending, header-keyed (worktree and base empty)" \
  "| T6 | 4 | build | the fixup | bionic:implementor | — | 30 | REQ-5 | b.sh, c.sh | — | — | pending |" \
  "$(printf '%s\n' "$ADD_OUT" | grep '^| T' | tail -1)"
expect_eq "17.25 …its - T6: line sits after the last - T<n>: line and its continuation" \
  "  base: abc1234|- T4: pending dispatch — .worktrees/T4|- T6: pending dispatch — added by task-add" \
  "$(printf '%s\n' "$ADD_OUT" | grep -B2 '^- T6:' | sed -E 's/ at [0-9TZ:-]+$//' | tr '\n' '|' | sed 's/|$//')"
expect_contains "17.26 …the Step-4 id is threaded into the frontier Step-5 row T3 (K2-F1: a table without reads)" \
  "| T3 | 5 | verify | the floor | test-runner | T1, T6 |" "$ADD_OUT"
expect_contains "17.27 …but not into T4, which reaches it through T3" \
  "| T4 | 6 | review | after the floor | critic | T3 |" "$ADD_OUT"
expect_contains "17.27b …nor into the landed T5" \
  "| T5 | 7 | doc | a landed doc | implementor | T1 |" "$ADD_OUT"
# THE reads OPERAND (optional, eleventh): placed by the header like every cell, and dropped
# without a word by a table that carries no reads column — exactly as an unread column is.
cat > "$SANDBOX/add-reads.md" <<'ADDR_EOF'
## SDLC State

current: 4
approved-by: fixture 2026-10-03T00:00Z "approved"

- T1: landed at record/T1.md

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | reads | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the build | implementor | — | 30 | REQ-x | lib/a.sh |  | landed |
ADDR_EOF
expect_contains "17.28 the reads operand lands in the reads column of a reads table" \
  "| T2 | 4 | build | reads a.sh | implementor | — | 30 | REQ-5 | lib/b.sh | lib/a.sh, approval:plan | pending |" \
  "$(call units_add_row "$SANDBOX/add-reads.md" T2 4 build 'reads a.sh' implementor '—' 30 REQ-5 'lib/b.sh' 'lib/a.sh, approval:plan')"
expect_contains "17.29 …and an escaped pipe in another row's cell survives the rewrite" \
  'the build \| with a pipe' "$ADD_OUT"
expect_eq "17.30 …and the projection validates clean" "0" "$(call_rc units_validate "$SANDBOX/add-projected.md")"

# A LATER-STEP ROW THREADS NOTHING, in either table shape (1.10 threaded only a Step-4 row).
ADD_OUT6="$(call units_add_row "$SANDBOX/add.md" T7 6 review 'a second review' critic 'T3' 30 REQ-5 '—')"
expect_eq "17.31 a Step-6 row threads nothing: every other row is byte-identical" \
  "$(grep '^| T[0-9]' "$SANDBOX/add.md")" "$(printf '%s\n' "$ADD_OUT6" | grep '^| T[0-9]' | grep -v '^| T7 ')"
expect_eq "17.32 a plan with no ## Tasks table is not projected (exit 1…)" "1" \
  "$(call_rc units_add_row "$SANDBOX/no-table.md" T1 4 build x implementor — 1 x x)"
expect_eq "17.33 …and nothing is printed" "" \
  "$(call units_add_row "$SANDBOX/no-table.md" T1 4 build x implementor — 1 x x)"



# ============================================================
section "17b — wave-20 T10b: the release waits for its step (critic C3, Δ6), author text reaches the row byte for byte (review R6)"
# ============================================================
#
# C3: at current: 5 the Step-7 release row, kind `doc`, was READY the moment its Step-5
# dependency landed — the stop wall then pressed for the release before any auditor or critic
# verdict, which is the case Δ6 rejected literal Δ1 for. The accepted reading: a gate act waits
# for its step. The release is the Document step's gate act, so a `doc` row at Step 7 or later
# joins `integrate` and `close`; every other row ahead of `current:` stays ready (D5 part 1).
cat > "$SANDBOX/held.md" <<'HELD_EOF'
---
current: 5
---

## SDLC State

current: 5

- Step 5: in flight

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | landed | implementor | — | 30m | REQ-x | a.sh | landed |
| T2 | 5 | verify | the live bed, landed | implementor | T1 | 30m | REQ-x | — | landed |
| T3 | 7 | doc | Release 1.8.7 | implementor | T2 | 30m | REQ-x | — | pending |
| T4 | 6 | review | the review, deps landed | critic | T1 | 30m | REQ-x | — | pending |
| T5 | 8 | integrate | the merge, deps landed | implementor | T2 | 30m | REQ-x | — | pending |
| T6 | 7 | doc | a second doc row behind a pending review | implementor | T4 | 30m | REQ-x | — | pending |
HELD_EOF
sed 's/^current: 5$/current: 7/' "$SANDBOX/held.md" > "$SANDBOX/held-at-7.md"

expect_eq "17b.1 C3 at current: 5 the landed-dep Step-7 doc row (the release) is NOT ready; the Step-6 review is" \
  "T4" "$(call units_ready "$SANDBOX/held.md" 5)"
expect_eq "17b.2 …at current: 6 it still waits" "T4" "$(call units_ready "$SANDBOX/held.md" 6)"
expect_eq "17b.3 …at current: 7 the release joins the ready set (the integrate row still waits)" \
  "$(printf 'T3\nT4')" "$(call units_ready "$SANDBOX/held-at-7.md" 7)"
expect_eq "17b.4 through the fill: fill_ready_set at current: 5, rung 8, none open, omits the release" \
  "T4" "$(fill_call "$SANDBOX/held.md" 8 0)"

# THE WORK ROWS AHEAD OF current: ARE UNTOUCHED (D5 part 1). A Step-4 build row whose deps
# landed is ready at current: 3 as before; so is a Step-6 review at current: 5 (17b.1).
cat > "$SANDBOX/ahead.md" <<'AHEAD_EOF'
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 3 | prototype | landed | implementor | — | 30m | REQ-x | — | landed |
| T2 | 4 | build | ahead of current: 3 | implementor | T1 | 30m | REQ-x | a.sh | pending |
| T3 | 6 | doc | a Step-6 doc row, not the release | implementor | T1 | 30m | REQ-x | — | pending |
AHEAD_EOF
expect_eq "17b.5 a Step-4 build row ahead of current: 3 with landed deps is still ready, and a Step-6 doc row too" \
  "$(printf 'T2\nT3')" "$(call units_ready "$SANDBOX/ahead.md" 3)"

# THE HOLD IS NAMED, ONE LINE PER ROW (`units_held <plan> <step>`): a row that would be ready
# but for its step. A row still waiting on a dependency is not a hold — it is not ready for a
# reason the graph already states — so T6 is not named.
expect_eq "17b.6 units_held at current: 5 names the release and the integrate row, in table order" \
  "$(printf 'T3: step 7 doc row waits for current: 7\nT5: step 8 integrate row waits for current: 8')" \
  "$(call units_held "$SANDBOX/held.md" 5)"
expect_eq "17b.7 …at current: 7 only the integrate row is still held" \
  "T5: step 8 integrate row waits for current: 8" "$(call units_held "$SANDBOX/held-at-7.md" 7)"
expect_eq "17b.8 …a caller fault is still exit 2" "2" "$(call_rc units_held "$SANDBOX/held.md" five)"
expect_eq "17b.9 a hold is not a broken invariant: the validator admits the plan" "0" \
  "$(call_rc units_validate "$SANDBOX/held.md")"

# R6: author text reached awk through -v, which interprets backslash escapes, so
# `C:\new\table` became `C:<newline>ew<tab>able`. Every operand now reaches the program
# through ENVIRON. An author's own `\|` is already the one GFM cell escape and stays as it
# was typed; a raw `|` is still escaped (17b.11).
R6_OUT="$(call units_add_row "$SANDBOX/add.md" T8 6 review 'match C:\new\table and a\|b' 'bionic:critic' 'T3' 30 'costs $5 \t' 'x\y.sh')"
expect_eq "17b.10 R6 a backslash, an author-escaped \\| and a \$ survive byte for byte into the row" \
  '| T8 | 6 | review | match C:\new\table and a\|b | bionic:critic | T3 | 30 | costs $5 \t | x\y.sh | — | — | pending |' \
  "$(printf '%s\n' "$R6_OUT" | grep '^| T8 ')"
R6_OUT4="$(call units_add_row "$SANDBOX/add.md" T9 4 build 'raw a|b and \n' 'bionic:implementor' '—' 30 REQ-5 'b.sh')"
expect_eq "17b.11 …and through a Step-4 add as well" \
  '| T9 | 4 | build | raw a\|b and \n | bionic:implementor | — | 30 | REQ-5 | b.sh | — | — | pending |' \
  "$(printf '%s\n' "$R6_OUT4" | grep '^| T9 ')"
expect_contains "17b.12 …and threads the Step-5 row as 1.10 did, this table having no reads column (K2-F1)" \
  "| T3 | 5 | verify | the floor | test-runner | T1, T9 |" "$R6_OUT4"
printf '%s\n' "$R6_OUT" > "$SANDBOX/r6-projected.md"
expect_eq "17b.13 …and the projection validates clean" "0" "$(call_rc units_validate "$SANDBOX/r6-projected.md")"


# ============================================================
section "17c — wave-21 T4: an external wait is a declared prerequisite, ext:<slug> (REQ-3, AC-3.1, AC-3.2, AC-3.4; D3, ADR-037 decision 2)"
# ============================================================
#
# A ROW WAITING ON CI, A RIG OR A TRIAGE HAD NO LEGAL WAY TO SAY SO (triage-A §F.3): `pending`
# made it ready, `active`/`dropped` were false, and the stop wall refused every turn that did
# not dispatch it or decline it again. The prerequisite now carries the wait: a deps token
# `ext:<slug>` beside the task ids. Nothing mechanical satisfies it; its owner removes it.
#
# T2 is the held row (a landed task dep plus the token); T3 is the ordinary ready row; T5
# carries a token AND an unlanded task dep, so the graph already says why it waits and the
# held report does not name it (the 17b.6 rule). T4 is the Step-5 row behind all of them.
cat > "$SANDBOX/ext.md" <<'EXT_EOF'
---
current: 4
---

## SDLC State

current: 4

- Step 4: in flight

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | landed | implementor | — | 30m | REQ-x | a.sh | landed |
| T2 | 4 | build | waits on CI | implementor | T1, ext:ci-ce9520e | 30m | REQ-x | b.sh | pending |
| T3 | 4 | build | ordinary, ready | implementor | T1 | 30m | REQ-x | c.sh | pending |
| T5 | 4 | build | waits on T2 and a rig | implementor | T2, ext:rig.mac_2 | 30m | REQ-x | d.sh | pending |
| T4 | 5 | verify | the floor | test-runner | T1, T2, T3, T5 | 30m | REQ-x | — | pending |
EXT_EOF

# AC-3.1: the validator admits the token and still refuses an unknown task id.
expect_eq "17c.1 AC-3.1 units_validate admits deps 'T1, ext:ci-ce9520e' (rc 0)" "0" \
  "$(call_rc units_validate "$SANDBOX/ext.md")"
expect_eq "17c.2 …and prints nothing" "" "$(call units_validate "$SANDBOX/ext.md")"
sed 's/| T1, ext:ci-ce9520e |/| T1, ext:ci-ce9520e, T99 |/' "$SANDBOX/ext.md" > "$SANDBOX/ext-t99.md"
expect_eq "17c.3 AC-3.1 …beside an unknown task id T99 the row is still refused, naming T99 alone" \
  "T2: dep T99 names no row in the table" "$(call units_validate "$SANDBOX/ext-t99.md")"
# THE TOKEN HAS A SHAPE: `ext:` and a slug that starts alphanumeric. A bare `ext:` or a slug
# that opens on punctuation is not a declaration, and is refused the way any unknown id is.
sed 's/| T1, ext:ci-ce9520e |/| T1, ext: |/' "$SANDBOX/ext.md" > "$SANDBOX/ext-bare.md"
expect_eq "17c.4 a bare 'ext:' is refused as a dep naming no row" \
  "T2: dep ext: names no row in the table" "$(call units_validate "$SANDBOX/ext-bare.md")"
sed 's/| T1, ext:ci-ce9520e |/| T1, ext:-ci |/' "$SANDBOX/ext.md" > "$SANDBOX/ext-punct.md"
expect_eq "17c.5 …and so is 'ext:-ci' (the slug opens on punctuation)" \
  "T2: dep ext:-ci names no row in the table" "$(call units_validate "$SANDBOX/ext-punct.md")"
sed 's/| T1, ext:ci-ce9520e |/| T1, EXT:ci |/' "$SANDBOX/ext.md" > "$SANDBOX/ext-upper.md"
expect_eq "17c.6 …and so is 'EXT:ci' (the prefix is lower-case, exactly)" \
  "T2: dep EXT:ci names no row in the table" "$(call units_validate "$SANDBOX/ext-upper.md")"
# A SPACE INSIDE A TOKEN IS NOT SQUASHED INTO ONE (wave-21 T13; walk-3b45d05 item 10). The
# deps cell used to lose every blank before it was split, so `ext:ci green` was admitted and
# held as `ext:cigreen`, a token nobody wrote. Blanks around a token are the cell's padding;
# a blank inside one makes it no token, and it is refused naming what the author wrote.
sed 's/| T1, ext:ci-ce9520e |/| T1, ext:ci green |/' "$SANDBOX/ext.md" > "$SANDBOX/ext-space.md"
expect_eq "17c.6b a slug with a space inside is refused, naming the token as written" \
  "T2: dep ext:ci green names no row in the table" "$(call units_validate "$SANDBOX/ext-space.md")"
sed 's/| T1, ext:ci-ce9520e |/|  T1 ,  ext:ci-ce9520e  |/' "$SANDBOX/ext.md" > "$SANDBOX/ext-pad.md"
expect_eq "17c.6d …while blanks AROUND each token are padding: the padded cell still validates clean" \
  "0" "$(call_rc units_validate "$SANDBOX/ext-pad.md")"
sed 's/| T1, ext:ci-ce9520e |/| T 1, ext:ci-ce9520e |/' "$SANDBOX/ext.md" > "$SANDBOX/ext-tid.md"
expect_eq "17c.6e …and a task id with a space inside is refused the same way" \
  "T2: dep T 1 names no row in the table" "$(call units_validate "$SANDBOX/ext-tid.md")"

# AC-3.2 (hermetic twin): the held row is not in the ready set. units_ready is UNCHANGED for
# this — an ext: token never equals `landed` — and this pins that it stays so.
expect_eq "17c.7 AC-3.2 units_ready at current: 4 omits the ext:-held T2 (and T5, behind T2); T3 is ready" \
  "T3" "$(call units_ready "$SANDBOX/ext.md" 4)"
expect_eq "17c.8 AC-3.2 …through the fill: fill_ready_set at rung 8, none open, omits T2" \
  "T3" "$(fill_call "$SANDBOX/ext.md" 8 0)"
# THE HELD REPORT NAMES IT, beside the step-held lines: `<id>: held by ext:<slug>`. T5 is not
# named: its unlanded task dep T2 already says why it waits.
expect_eq "17c.9 units_held names the ext:-held row and its token, and not T5" \
  "T2: held by ext:ci-ce9520e" "$(call units_held "$SANDBOX/ext.md" 4)"

# AC-3.4: removing the token returns the row to ready — the one declaration that clears it.
sed 's/| T1, ext:ci-ce9520e |/| T1 |/' "$SANDBOX/ext.md" > "$SANDBOX/ext-cleared.md"
expect_eq "17c.10 AC-3.4 with the token removed, units_ready names T2 again (table order)" \
  "$(printf 'T2\nT3')" "$(call units_ready "$SANDBOX/ext-cleared.md" 4)"
expect_eq "17c.11 AC-3.4 …and units_held no longer names it" "" "$(call units_held "$SANDBOX/ext-cleared.md" 4)"

# TWO TOKENS ON ONE ROW ARE ONE LINE, both named in cell order; a token on a step-held gate
# act names both holds, the step line first (the order 17b.6 already prints in).
sed 's/| T1, ext:ci-ce9520e |/| ext:ci-ce9520e, T1, ext:rig-2 |/' "$SANDBOX/ext.md" > "$SANDBOX/ext-two.md"
expect_eq "17c.12 two tokens on one row: one held line naming both, in cell order" \
  "T2: held by ext:ci-ce9520e ext:rig-2" "$(call units_held "$SANDBOX/ext-two.md" 4)"
expect_eq "17c.13 …and the plan still validates clean" "0" "$(call_rc units_validate "$SANDBOX/ext-two.md")"
cat > "$SANDBOX/ext-gate.md" <<'EXTG_EOF'
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | landed | implementor | — | 30m | REQ-x | a.sh | landed |
| T2 | 8 | integrate | the merge, waits for its step and for CI | implementor | T1, ext:ci-main | 30m | REQ-x | — | pending |
EXTG_EOF
expect_eq "17c.14 a step-held gate act with a token: the step line, then the ext line" \
  "$(printf 'T2: step 8 integrate row waits for current: 8\nT2: held by ext:ci-main')" \
  "$(call units_held "$SANDBOX/ext-gate.md" 5)"
expect_eq "17c.15 …at its step the step hold lifts and the ext hold stays; it is still not ready" \
  "T2: held by ext:ci-main" "$(call units_held "$SANDBOX/ext-gate.md" 8)"
expect_eq "17c.16 …units_ready at its step still omits it" "" "$(call units_ready "$SANDBOX/ext-gate.md" 8)"


# ============================================================
section "17d — wave-21 T5: one ledger reader, units_findings (REQ-4, AC-4.1, AC-4.3; D4, ADR-037 decision 3)"
# ============================================================
#
# THREE FINDINGS AND NO MORE: `status <id> <value>` (a status outside the enum),
# `evidence <id>` (a `landed` row with no `- T<n>:` line under
# `## SDLC State`), `launch <id> <agent>` (an `active` row whose agent cell names no `name=`
# on the roster). An empty or em-dash agent cell is SELF-OWNED and never a finding. With no
# roster to read (an empty argument, a missing file, a symlink) no `launch` finding is
# computed and an agent-named `active` row falls back to today's rule: it owes its line.
cat > "$SANDBOX/ledger.md" <<'LEDGER_EOF'
---
scale: wave
---

## SDLC State

current: 4

- T1: bash suite 9/9 green
  T9:
- T11: dispatched to w-T11

```
- T2: a fenced example is documentation, not a line
```

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | landed with its line | w-T1 | — | 30m | REQ-x | a.sh | landed |
| T2 | 4 | build | landed, its only line fenced | w-T2 | — | 30m | REQ-x | b.sh | landed |
| T3 | 4 | build | a status off the enum | w-T3 | — | 30m | REQ-x | c.sh | doing |
| T4 | 4 | build | active, launched | w-T4 | — | 30m | REQ-x | d.sh | active |
| T5 | 4 | build | active, agent cell names no roster row | bionic:implementor | — | 30m | REQ-x | e.sh | active |
| T6 | 4 | build | active, self-owned by an em dash | — | — | 30m | REQ-x | f.sh | active |
| T7 | 4 | build | active, self-owned by an empty cell |  | — | 30m | REQ-x | g.sh | active |
| T8 | 4 | build | pending, no line owed | w-T8 | — | 30m | REQ-x | h.sh | pending |
| T9 | 4 | build | landed, its line empty | w-T9 | — | 30m | REQ-x | i.sh | landed |
| T10 | 4 | build | landed, only T1's line (T1 never matches T10) | w-T10 | — | 30m | REQ-x | j.sh | landed |
| T11 | 4 | build | dropped | w-T11 | — | 30m | REQ-x | k.sh | dropped |
LEDGER_EOF
# The roster through the fleet's own builders (tests/lib/roster-row.sh, swept-marker.sh): two
# launch rows, and a landing-swept marker whose name= must NOT count as a launch.
{
  roster_header
  roster_row_fixture status=identified session=s name=w-T4 agent_id=a4
  roster_row_fixture status=intended session=s name=w-T9x agent_id=
} > "$SANDBOX/ledger.roster"
swept_marker_write "$SANDBOX/ledger.roster" 2026-10-01T00:00:00Z s bionic:implementor a5 MET
expect_eq "17d.1 AC-4.1 the three kinds, table order: evidence, status, launch — and no finding for the launched, self-owned, pending or dropped rows" \
  "$(printf 'evidence T2\nstatus T3 doing\nlaunch T5 bionic:implementor\nevidence T9\nevidence T10')" \
  "$(call units_findings "$SANDBOX/ledger.md" "$SANDBOX/ledger.roster")"
expect_eq "17d.2 …and the verb exits 1 when it printed a finding" "1" \
  "$(call_rc units_findings "$SANDBOX/ledger.md" "$SANDBOX/ledger.roster")"
# A landing-swept line carrying name= is not a roster row: only `roster-state/` rows launch.
expect_contains "17d.3 a name= on a landing-swept line launches nobody" "launch T5 bionic:implementor" \
  "$(call units_findings "$SANDBOX/ledger.md" "$SANDBOX/ledger.roster")"

# NO ROSTER TO READ: the agent-named active rows owe their line again (spec assumption 1);
# the self-owned rows still owe nothing.
S17D_FALLBACK="$(printf 'evidence T2\nstatus T3 doing\nevidence T4\nevidence T5\nevidence T9\nevidence T10')"
expect_eq "17d.4 AC-4.3 with no roster argument, an agent-named active row falls back to the line rule" \
  "$S17D_FALLBACK" "$(call units_findings "$SANDBOX/ledger.md" "")"
expect_eq "17d.5 …and a roster path that names no file reads the same as none" \
  "$S17D_FALLBACK" "$(call units_findings "$SANDBOX/ledger.md" "$SANDBOX/no-such.roster")"
ln -s "$SANDBOX/ledger.roster" "$SANDBOX/ledger-link.roster"
expect_eq "17d.6 …and so does a symlinked roster (the fleet never follows one)" \
  "$S17D_FALLBACK" "$(call units_findings "$SANDBOX/ledger.md" "$SANDBOX/ledger-link.roster")"
expect_absent "17d.7 AC-4.3 the self-owned rows are never a finding, roster or none" "T6" \
  "$(call units_findings "$SANDBOX/ledger.md" "")$(call units_findings "$SANDBOX/ledger.md" "$SANDBOX/ledger.roster")"
expect_absent "17d.8 …the empty-cell one included" "T7" \
  "$(call units_findings "$SANDBOX/ledger.md" "")$(call units_findings "$SANDBOX/ledger.md" "$SANDBOX/ledger.roster")"

# THE CLEAN LEDGER: every terminal row carries its line, every active row is launched or
# self-owned. Nothing printed, exit 0.
cat > "$SANDBOX/ledger-clean.md" <<'LEDGERC_EOF'
## SDLC State

current: 4

- T1: bash suite 9/9 green

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | landed with its line | w-T1 | — | 30m | REQ-x | a.sh | landed |
| T4 | 4 | build | active, launched, no line | w-T4 | — | 30m | REQ-x | d.sh | active |
| T6 | 4 | build | active, self-owned, no line | — | — | 30m | REQ-x | f.sh | active |
| T8 | 4 | build | pending, no line | w-T8 | T1 | 30m | REQ-x | h.sh | pending |
LEDGERC_EOF
expect_eq "17d.9 a clean ledger prints nothing" "" "$(call units_findings "$SANDBOX/ledger-clean.md" "$SANDBOX/ledger.roster")"
expect_eq "17d.10 …and exits 0" "0" "$(call_rc units_findings "$SANDBOX/ledger-clean.md" "$SANDBOX/ledger.roster")"

# ONE ENUM AT EVERY SCALE (wave-31 T5; D2). A table in the retired six-column task shape is judged
# by the one enum: its `done` is a status finding, and `landed` owes its line as anywhere.
cat > "$SANDBOX/ledger-task.md" <<'LEDGERT_EOF'
## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | build | single | done with its line | done |
| T2 | build | single | done, no line | done |
| T3 | build | single | landed, no line | landed |
| T4 | build | single | active, self-owned | active |

## SDLC State

scale: task
current: 4

- T1: bash suite 5/5 green
LEDGERT_EOF
expect_eq "17d.11 D2 one enum: the retired done is a status finding, landed owes its line, an active self-owned row nothing" \
  "$(printf 'status T1 done\nstatus T2 done\nevidence T3')" "$(call units_findings "$SANDBOX/ledger-task.md" "")"
expect_eq "17d.12 …the same with a roster" \
  "$(printf 'status T1 done\nstatus T2 done\nevidence T3')" "$(call units_findings "$SANDBOX/ledger-task.md" "$SANDBOX/ledger.roster")"

# AN EMPTY STATUS CELL is named, the way the validator names it.
sed 's/| d.sh | active |/| d.sh |  |/' "$SANDBOX/ledger-clean.md" > "$SANDBOX/ledger-empty-status.md"
expect_eq "17d.13 an empty status cell is a status finding spelled (empty)" "status T4 (empty)" \
  "$(call units_findings "$SANDBOX/ledger-empty-status.md" "$SANDBOX/ledger.roster")"
expect_eq "17d.14 no table, no findings, exit 0" "0" "$(call_rc units_findings "$SANDBOX/no-such.md" "")"

# THE LOOKUP THE GATE'S ADDRESSED-UNIT ARM COUNTS (it moved here from walls.sh's
# missing_evidence_ids): every T-row with no non-empty `- T<n>:` line, whatever its status.
expect_eq "17d.15 units_unlined names every T-row short of a line, table order, the fenced and empty ones included" \
  "$(printf 'T2\nT3\nT4\nT5\nT6\nT7\nT8\nT9\nT10')" "$(call units_unlined "$SANDBOX/ledger.md")"
# CR-ONLY INPUT (the gate's 19j-cr pin): the reader translates line endings itself.
tr '\n' '\r' < "$SANDBOX/ledger-task.md" > "$SANDBOX/ledger-task-cr.md"
expect_eq "17d.16 a CR-only plan reads the same" \
  "$(printf 'status T1 done\nstatus T2 done\nevidence T3')" "$(call units_findings "$SANDBOX/ledger-task-cr.md" "")"

# ============================================================
section "READS — wave-26 T2: a row declares what it reads; an empty cell takes its kind default (REQ-5, AC-5.1; D1)"
# ============================================================
#
# `reads` is an OPTIONAL thirteenth slot, keyed by header name like every other: a table that
# carries it schedules each row by what the row reads, a table without it keeps reading `deps`
# ids as "wait for that task to land". An empty `reads` cell is never "nothing" — it is the
# row's kind default: build `approval:plan`, verify `approval:plan, head`, review
# `approval:plan, live:head`, doc `approval:plan, head`, integrate `proof:floor, proof:review`,
# close the integrate row's merge. A settled read waits for every open writer of what it names;
# `head` is written by every open row with a path outside `.bionic/`.
TAB="$(printf '\t')"
# has_line <text> <line> -> yes when <line> is one whole line of <text>.
has_line() { if printf '%s\n' "$1" | grep -qxF -- "$2"; then printf yes; else printf no; fi; }

# A FLOOR PROOF STANDS ONLY WHILE THE PASS DOES (wave-26 T64; REQ-3 AC-3.4). A settled
# `proof:floor` read with no open writer is satisfied when lib/proof.sh `proof_state` answers
# `covered` for the plan's working branch (wave-31 T25), so a row that means "the floor is proved"
# needs a floor proof naming a REAL head the working branch is at: a fake hex is no commit, and
# the read now waits. FLOOR_REPO is that repository, on `wave/99-fixture` with one commit, and
# floor_at_head copies a plan into it with its floor proof moved to that head and the branch named.
FLOOR_REPO="$SANDBOX/floor-repo"
mkdir -p "$FLOOR_REPO"
git -C "$FLOOR_REPO" init -q 2>/dev/null
git -C "$FLOOR_REPO" checkout -q -b wave/99-fixture 2>/dev/null
git -C "$FLOOR_REPO" -c user.name=fixture -c user.email=fixture@example.invalid commit -q --allow-empty -m base 2>/dev/null
FLOOR_H="$(git -C "$FLOOR_REPO" rev-parse HEAD 2>/dev/null)"
floor_at_head() {  # <plan> <copy under FLOOR_REPO>
  awk -v h="$FLOOR_H" '
    /^proved: kind=floor / { sub(/head=[0-9a-f]+/, "head=" h) }
    { print }
    /^## SDLC State/ && !w { print ""; print "working-branch: wave/99-fixture"; w = 1 }' "$1" > "$2"
}
expect_regex "FLOOR_REPO precondition: the fixture repository has a 40-hex head" '^[0-9a-f]{40}$' "$FLOOR_H"

cat > "$SANDBOX/reads.md" <<'READS_EOF'
---
current: 4
---

## SDLC State

current: 4
approved-by: fixture 2026-10-03T00:00Z "approved"

- Step 4: in flight

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | reads | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | a build, reads empty | implementor | — | 30 | REQ-x | lib/a.sh, tests/a.test.sh |  | pending |
| T2 | 5 | verify | the walk, reads empty | researcher | — | 30 | REQ-x | .bionic/docs/record/w/walk.md | — | pending |
| T3 | 6 | review | the review, reads empty | critic | — | 30 | REQ-x | .bionic/docs/record/w/review.md |  | pending |
| T4 | 4 | build | reads a file T1 writes | implementor | — | 30 | REQ-x | lib/b.sh | lib/a.sh | pending |
| T5 | 4 | build | reads a file no open row writes | implementor | — | 30 | REQ-x | lib/c.sh | lib/old.sh, approval:plan | pending |
| T6 | 4 | build | reads a directory T1 writes into | implementor | — | 30 | REQ-x | lib/d.sh | lib/ | pending |
READS_EOF

ROWS_READS="$(call units_rows "$SANDBOX/reads.md")"
expect_eq "READS.1 the header carries the optional reads column" "0" \
  "$(call_rc units_has_column "$SANDBOX/reads.md" reads)"
expect_eq "READS.1b …and a table written without it does not" "1" \
  "$(call_rc units_has_column "$SANDBOX/live.md" reads)"
expect_eq "READS.2 units_field reads the reads cell by name" "lib/old.sh, approval:plan" \
  "$(call units_field "$(printf '%s\n' "$ROWS_READS" | awk -F'\t' '$1 == "T5"')" reads)"
expect_eq "READS.2b …and the record keeps its fixed slots: status is still field 10" "pending" \
  "$(printf '%s\n' "$ROWS_READS" | awk -F'\t' '$1 == "T5"' | cut -f10)"
expect_eq "READS.3 the reads table validates clean" "0" "$(call_rc units_validate "$SANDBOX/reads.md")"

READY_READS="$(call units_ready "$SANDBOX/reads.md" 4)"
WAIT_READS="$(call units_waiting "$SANDBOX/reads.md" 4)"
expect_eq "READS.4 an empty build cell takes approval:plan: T1 is ready on the approved plan" "yes" \
  "$(has_line "$READY_READS" T1)"
expect_eq "READS.5 an empty verify cell takes approval:plan, head: T2 waits for T1, an open writer outside .bionic/" \
  "yes" "$(has_line "$WAIT_READS" "T2${TAB}head${TAB}T1${TAB}pending")"
expect_eq "READS.5b …so T2 is not ready" "no" "$(has_line "$READY_READS" T2)"
# A REVIEW FOLLOWS THE BUILD (wave-26 T14; D10): live:head is ready once landed work exists that
# no review has read. Nothing has landed in this table, so the review waits for the first landing
# and says so; LIVE.8 is the same row ready once a build lands.
expect_eq "READS.6 an empty review cell takes live:head: with nothing landed T3 waits for the first landing" "yes no" \
  "$(printf '%s %s' "$(has_line "$WAIT_READS" "T3${TAB}live:head: nothing has landed yet${TAB}-${TAB}-")" \
     "$(has_line "$READY_READS" T3)")"
expect_eq "READS.7 a path read waits for the open row whose Files cover it" "yes" \
  "$(has_line "$WAIT_READS" "T4${TAB}lib/a.sh${TAB}T1${TAB}pending")"
expect_eq "READS.7b …and T4 is not ready" "no" "$(has_line "$READY_READS" T4)"
expect_eq "READS.8 a path no open row writes is satisfied: T5 is ready" "yes" "$(has_line "$READY_READS" T5)"
expect_eq "READS.9 coverage is not string equality: a directory read waits for a file written inside it" \
  "yes" "$(has_line "$WAIT_READS" "T6${TAB}lib/${TAB}T1${TAB}pending")"
expect_eq "READS.9b …and a row is never its own writer: T6 writes lib/d.sh and is not named against itself" "no" \
  "$(has_line "$WAIT_READS" "T6${TAB}lib/${TAB}T6${TAB}pending")"

# THE WRITER LANDS, OR IS DROPPED: either satisfies the read. Through 1.10 a dependency on a
# dropped row was never satisfied, so its dependents waited for ever (A-T2 log).
sed 's/| lib\/a.sh, tests\/a.test.sh |  | pending |/| lib\/a.sh, tests\/a.test.sh |  | landed |/' \
  "$SANDBOX/reads.md" > "$SANDBOX/reads-landed.md"
sed 's/| lib\/a.sh, tests\/a.test.sh |  | pending |/| lib\/a.sh, tests\/a.test.sh |  | dropped |/' \
  "$SANDBOX/reads.md" > "$SANDBOX/reads-dropped.md"
expect_eq "READS.10 once T1 lands, T4's read is satisfied" "yes" \
  "$(has_line "$(call units_ready "$SANDBOX/reads-landed.md" 4)" T4)"
expect_eq "READS.10b …and a dropped writer satisfies it too" "yes" \
  "$(has_line "$(call units_ready "$SANDBOX/reads-dropped.md" 4)" T4)"

# NO APPROVAL LINE, NOTHING THAT READS approval:plan IS READY — the default is an input, not
# "nothing": a row whose empty cell meant nothing would be ready here.
grep -v '^approved-by:' "$SANDBOX/reads.md" > "$SANDBOX/reads-unapproved.md"
WAIT_UNAPP="$(call units_waiting "$SANDBOX/reads-unapproved.md" 4)"
expect_eq "READS.11 without approved-by: the empty build cell waits on approval:plan, written by nobody in the table" \
  "yes" "$(has_line "$WAIT_UNAPP" "T1${TAB}approval:plan${TAB}-${TAB}-")"
expect_eq "READS.11b …and so does the empty review cell" "yes" \
  "$(has_line "$WAIT_UNAPP" "T3${TAB}approval:plan${TAB}-${TAB}-")"
expect_eq "READS.11c …and neither is ready" "no no" \
  "$(R="$(call units_ready "$SANDBOX/reads-unapproved.md" 4)"; printf '%s %s' "$(has_line "$R" T1)" "$(has_line "$R" T3)")"

# A TABLE WITH reads REFUSES A TASK ID IN deps (AC-5.1 fails-when: "the validator accepts
# deps: T3 beside a reads column"). ext:<slug> stays legal there (§EXT).
sed 's/^| T4 | 4 | build | reads a file T1 writes | implementor | — |/| T4 | 4 | build | reads a file T1 writes | implementor | T1 |/' \
  "$SANDBOX/reads.md" > "$SANDBOX/reads-deps-id.md"
VAL_DEPS_ID="$(call units_validate "$SANDBOX/reads-deps-id.md")"
expect_contains "READS.12 a task id in deps beside a reads column is refused, naming the row and the id" \
  "T4: dep T1 is not ext:<slug>" "$VAL_DEPS_ID"
expect_eq "READS.12b …and the verb exits 1" "1" "$(call_rc units_validate "$SANDBOX/reads-deps-id.md")"

# A READ NAMES SOMETHING: a path in the Files grammar or a named artifact. A token that names
# neither is refused at the write, and never read as satisfied.
for _bad in nonsense proof:bogus foo:bar 'lib/a b.sh'; do
  sed "s#| lib/old.sh, approval:plan |#| lib/old.sh, $_bad |#" "$SANDBOX/reads.md" > "$SANDBOX/reads-bad.md"
  expect_contains "READS.13 a read naming no artifact is refused: '$_bad'" \
    "T5: read $_bad names no artifact" "$(call units_validate "$SANDBOX/reads-bad.md")"
  expect_eq "READS.13b …and the row is not ready on it: '$_bad'" "no" \
    "$(has_line "$(call units_ready "$SANDBOX/reads-bad.md" 4)" T5)"
done
# proof:check (wave-27 T16; D12): the release's declared check is a fact the validator admits as a
# read, and the row waits on it until a `proved: kind=check` line exists.
sed "s#| lib/old.sh, approval:plan |#| lib/old.sh, proof:check |#" "$SANDBOX/reads.md" > "$SANDBOX/reads-check.md"
expect_eq "READS.13c proof:check is a read the validator admits" "0" "$(call_rc units_validate "$SANDBOX/reads-check.md")"
expect_eq "READS.13e …and T5 waits on it while no check fact exists" "yes" \
  "$(has_line "$(call units_waiting "$SANDBOX/reads-check.md" 4)" "T5${TAB}proof:check${TAB}-${TAB}-")"
awk '{ print } /^approved-by: / { print "proved: kind=check head=0123456789abcdef0123456789abcdef01234567 at=2026-10-04T00:00:00Z evidence=record/w/release-check.log" }' \
  "$SANDBOX/reads-check.md" > "$SANDBOX/reads-checked.md"
expect_eq "READS.13f …and is ready once one does" "yes" "$(has_line "$(call units_ready "$SANDBOX/reads-checked.md" 4)" T5)"

# A TABLE WITHOUT reads STILL PARSES, and a deps id still means "wait for that task to land".
# Nothing defaults there: a verify row with an empty deps cell waits for nobody, as before.
cat > "$SANDBOX/legacy.md" <<'LEGACY_EOF'
## SDLC State

current: 4

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | a build | implementor | — | 30 | REQ-x | lib/a.sh | pending |
| T2 | 4 | build | waits for T1 to land | implementor | T1 | 30 | REQ-x | lib/b.sh | pending |
| T3 | 5 | verify | names no dependency | researcher | — | 30 | REQ-x | — | pending |
LEGACY_EOF
READY_LEG="$(call units_ready "$SANDBOX/legacy.md" 4)"
expect_eq "READS.14 a table without reads validates clean" "0" "$(call_rc units_validate "$SANDBOX/legacy.md")"
expect_eq "READS.14b …a deps id waits for that task to land: T2 is not ready while T1 is pending" "no" \
  "$(has_line "$READY_LEG" T2)"
expect_eq "READS.14c …and units_waiting names the id as the read and as its writer" "yes" \
  "$(has_line "$(call units_waiting "$SANDBOX/legacy.md" 4)" "T2${TAB}T1${TAB}T1${TAB}pending")"
expect_eq "READS.14d …and no kind default applies without the column: T3 is ready beside the open build" \
  "yes" "$(has_line "$READY_LEG" T3)"

# ROWS OPEN ON THE ROSTER ARE NOT READY (D9). The launch recorder moves the plan row, but until
# it has, a row dispatched as `w26-T1` is still `pending` in the table; the id-to-name rule is
# fill_row_launched's, the open names roster_open_names'.
{
  roster_header
  roster_row_fixture status=confirmed session=s name=w26-T1 agent_id=a1
} > "$SANDBOX/reads.roster"
READY_ROST="$(call units_ready "$SANDBOX/reads.md" 4 "$SANDBOX/reads.roster")"
expect_eq "READS.15 a ready row open on the roster under w26-T1 is subtracted" "no" "$(has_line "$READY_ROST" T1)"
# The review T3 is not among them: nothing in this table has landed, so it waits for the first
# landing (wave-26 T14, READS.6).
expect_eq "READS.15b …the other ready row stays" "yes" "$(has_line "$READY_ROST" T5)"
expect_eq "READS.15c …and without a roster operand T1 is offered" "yes" "$(has_line "$READY_READS" T1)"

# ============================================================
section "EDGES — wave-26 T2: an edge only where a read meets a write; the wave-24 replay (REQ-5, AC-5.2; D1, D2)"
# ============================================================
#
# THE REPLAY. The rows below are wave-24's own (`wave-24-fixit-1811.plan.md`, `## Tasks`),
# spliced verbatim — header, task text, deps, Files, tree and base — with only the status cell
# rewound to the moment T29 and T30 were building and T31 was queued, while the walk T16, the
# review T17 and the release T18 waited. The plan tree is gitignored, so the specimen lives here.
# Under 1.10 T16's deps named every Step-4 row and T17's named T16, so the review waited for
# the walk it never read (research R3 B4, B5). `replay-legacy.md` is that table as written;
# `replay.md` is the same rows with a `reads` column (every cell empty, so each row takes its
# kind default) and the deps ids cleared, plus T32, a record-only write-up the fixture adds.
cat > "$SANDBOX/replay-legacy.md" <<'REPLAY_EOF'
---
current: 5
---

## SDLC State

current: 5
approved-by: fixture 2026-10-03T00:00Z "approved"

- Step 5: in flight

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | Close-out finds the shipped wave table once (row 78) and fills the ADR cell from the spec (row 86) (D17) · complexity: standard | w24-T1 | — | 45 | REQ-1 | payload/scripts/close-out.sh, tests/close-out.test.sh, .bionic/docs/record/wave-24-fixit-1811/T1-close-out.md, .bionic/docs/record/wave-24-fixit-1811/assumptions.md | .worktrees/24-T1 | 7223b594 | landed |
| T5 | 4 | build | The classifier right in both directions: bare-wait fan-outs, run.sh no-run flags, case patterns, leading redirects, literal suite loops and assignments, whole-basename variables (D9, D12) · complexity: complex | w24-T5 | — | 150 | REQ-6, REQ-7 | payload/scripts/lib/cmd-class.sh, tests/cmd-class.test.sh, tests/background-suite-guard.test.sh, .bionic/docs/record/wave-24-fixit-1811/T5-classifier.md, .bionic/docs/record/wave-24-fixit-1811/assumptions.md | .worktrees/24-T5 | 7223b594 | landed |
| T16 | 5 | verify | The walk (head beside base, fresh processes), the live hold in this session, the 202-brief replay, version on a copy of the real cache, then the floor `bash tests/run.sh` at the final head · complexity: complex | — | T1, T2, T3, T4, T5, T6, T7, T8, T9, T10, T11, T12, T13, T14, T15, T19, T20, T21, T22, T23, T24, T25, T26, T27, T28, T29, T30, T31 | 120 | REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-10 | .bionic/docs/record/wave-24-fixit-1811/walk-head.md, .bionic/docs/record/wave-24-fixit-1811/live-hold.md, .bionic/docs/record/wave-24-fixit-1811/brief-replay.md | .worktrees/24-fixit-1811 | 60529224 | pending |
| T17 | 6 | review | Six-axis review over `git diff 7223b594 <head>` by one reviewer, one verdict per axis; the critic and auditor are ledgered in the dispatch ledger · complexity: standard | w24-T17 | T16 | 60 | REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-10 | .bionic/docs/record/wave-24-fixit-1811/review.md | .worktrees/24-fixit-1811 | 60529224 | pending |
| T18 | 7 | doc | Release 1.9.0 and the semver policy: CHANGELOG (policy in its header), plugin.json, repo CLAUDE.md, re-render, integrity manifest, version pins; ADR-041 Accepted; on Chris's release approval (D19) · complexity: standard | w24-T18 | T16, T17 | 45 | REQ-11 | CHANGELOG.md, CLAUDE.md, payload/.claude-plugin/plugin.json, payload/commands/help.md, payload/integrity/rendered.sha256, tests/docs-pins.test.sh, .bionic/docs/adrs/epic-23-bionic-tech-debt/adr-041-an-answer-stands-until-its-facts-change.md, .bionic/docs/record/wave-24-fixit-1811/T18-release-190.md | .worktrees/24-T18 | c0d6ab04 | pending |
| T29 | 4 | build | Critic findings: a message counts as the completion signal only when it names the row's deliverable, so a mid-task question no longer reads MET (I1); the fix lines in dispatch-preflight.sh and brief.sh quote the plugin root (I2, AC-6.5); dispatch.md stops saying done is the artifact on disk · complexity: complex | w24-T29 | T9, T13, T26 | 60 | REQ-4, REQ-6 | hooks/session-sweeper.sh, hooks/session-poker.sh, payload/scripts/lib/stop.sh, tests/fixtures/refusal-inventory.md, tests/refuse.test.sh, hooks/dispatch-preflight.sh, payload/scripts/lib/brief.sh, agents-src/blocks/orchestrator-dispatch.md, agents-src/blocks/report-contract.md, agents-src/templates/skills/canonical-sdlc/dispatch.md.tmpl, skills/canonical-sdlc/dispatch.md, agents/auditor.md, agents/critic.md, agents/implementor.md, agents/researcher.md, agents/senior-implementor.md, agents/test-runner.md, payload/integrity/rendered.sha256, tests/session-sweeper.test.sh, tests/dispatch-preflight.test.sh, tests/docs-pins.test.sh, tests/render.test.sh, tests/session-poker.test.sh, tests/cross-gate-agreement.test.sh, tests/stop-orders.test.sh, tests/patrol-duties-gate.test.sh, tests/stop.test.sh, tests/landing-gate.test.sh, tests/stop-guard.test.sh, tests/doctor-patrol.test.sh, tests/execution-recorder.test.sh, .bionic/docs/record/wave-24-fixit-1811/T29-critic-fixes.md, .bionic/docs/record/wave-24-fixit-1811/T29-progress.md, .bionic/docs/record/wave-24-fixit-1811/assumptions.md | .worktrees/24-T29 | ac258929 | active |
| T30 | 4 | build | Critic addendum A1: an escape-dense quoted command no longer times the Bash hook out — cmdnorm_qend copies the remainder once per backslash, so 207 KB of escaped quotes takes 10.99 s under bash 3.2 and every wall fails open; make the quote-end scan linear, with a hook-timeout row and an output-parity differential · complexity: complex | w24-T30 | T28 | 45 | REQ-5 | payload/scripts/lib/cmd-class.sh, tests/cmd-class.test.sh, tests/hook-timeout.test.sh, .bionic/docs/record/wave-24-fixit-1811/T30-escape-dense.md, .bionic/docs/record/wave-24-fixit-1811/T30-progress.md, .bionic/docs/record/wave-24-fixit-1811/assumptions.md | .worktrees/24-T30 | c0d6ab04 | active |
| T31 | 4 | build | A command name is compared the way the machine resolves it: GIT push and Git push are seen as git push by the shared command reader and the git screen in front of it, so protect-main cannot be passed by capitalising the program (found by wave-25, present in 1.8.10); staged on its branch, landing is Chris's call · complexity: complex | w24-T31 | T30 | 45 | REQ-7 | payload/scripts/lib/git-argv.sh, payload/scripts/lib/walls.sh, payload/scripts/lib/cmd-class.sh, tests/git-argv.test.sh, tests/bash-walls.test.sh, tests/cmd-class.test.sh, tests/protect-main.test.sh, tests/hook-timeout.test.sh, CHANGELOG.md, .bionic/docs/record/wave-24-fixit-1811/T31-command-identity.md, .bionic/docs/record/wave-24-fixit-1811/T31-progress.md, .bionic/docs/record/wave-24-fixit-1811/T31.done, .bionic/docs/record/wave-24-fixit-1811/assumptions.md | .worktrees/24-T31 | 4fd82348 | pending |
REPLAY_EOF

# The reads replay, by a transform that knows two header names and nothing else: `deps`
# cleared to an em dash on every data row, and an empty `reads` cell appended to every row.
awk -F'|' -v OFS='|' '
  /^\| id \|/ { for (i = 1; i <= NF; i++) { c = $i; gsub(/ /, "", c); if (c == "deps") dc = i }
                sub(/ \|$/, " | reads |"); print; next }
  /^\|---/    { print $0 "---|"; next }
  /^\| T/     { $dc = " — "; print $0 "  |"; next }
  { print }' "$SANDBOX/replay-legacy.md" > "$SANDBOX/replay.md"
printf '| T32 | 4 | build | a record-only write-up (fixture row) | w24-T32 | — | 20 | REQ-1 | .bionic/docs/record/wave-24-fixit-1811/T32-notes.md | .worktrees/24-T32 | c0d6ab04 | active |  |\n' \
  >> "$SANDBOX/replay.md"
# THE RELEASE NAMES ITS APPROVAL (wave-26 T62; K2-F3): a Step-7 doc row reads approval:release, and
# head as its default does, so it is the one cell the transform does not leave empty.
sed '/^| T18 | 7 | doc /s/  |$/ approval:release, head |/' "$SANDBOX/replay.md" > "$SANDBOX/replay.tmp" && mv "$SANDBOX/replay.tmp" "$SANDBOX/replay.md"

expect_eq "EDGES.0 the reads replay carries the column and validates clean" "0 0" \
  "$(call_rc units_has_column "$SANDBOX/replay.md" reads) $(call_rc units_validate "$SANDBOX/replay.md")"
READY_REPLAY="$(call units_ready "$SANDBOX/replay.md" 5)"
EDGES_REPLAY="$(call units_edges "$SANDBOX/replay.md")"
WAIT_REPLAY="$(call units_waiting "$SANDBOX/replay.md" 5)"
expect_eq "EDGES.1 AC-5.2 the review unit is ready while the verify unit is pending" "yes no" \
  "$(printf '%s %s' "$(has_line "$READY_REPLAY" T17)" "$(has_line "$READY_REPLAY" T16)")"
expect_eq "EDGES.2 units_edges joins each open build writing outside .bionic/ to the walk by head" "yes yes yes" \
  "$(printf '%s %s %s' "$(has_line "$EDGES_REPLAY" "T29${TAB}T16${TAB}head")" \
     "$(has_line "$EDGES_REPLAY" "T30${TAB}T16${TAB}head")" "$(has_line "$EDGES_REPLAY" "T31${TAB}T16${TAB}head")")"
expect_eq "EDGES.3 AC-5.2 …and the walk does not wait for a build whose files it does not read (record-only T32)" "no" \
  "$(has_line "$EDGES_REPLAY" "T32${TAB}T16${TAB}head")"
expect_eq "EDGES.4 no edge enters the review: it reads live:head, which waits for nobody" "" \
  "$(printf '%s\n' "$EDGES_REPLAY" | awk -F'\t' '$2 == "T17"')"
expect_eq "EDGES.5 every edge is <from><TAB><to><TAB><read>, both ends rows of the table" "" \
  "$(printf '%s\n' "$EDGES_REPLAY" | awk -F'\t' 'NF != 3 || $1 !~ /^T[0-9]+$/ || $2 !~ /^T[0-9]+$/ || $3 == ""')"
expect_eq "EDGES.6 units_waiting names the walk's unmet read and each writer with its status" "yes yes" \
  "$(printf '%s %s' "$(has_line "$WAIT_REPLAY" "T16${TAB}head${TAB}T30${TAB}active")" \
     "$(has_line "$WAIT_REPLAY" "T16${TAB}head${TAB}T31${TAB}pending")")"
# THE RELEASE READS head TOO, AND IT WRITES CHANGELOG.md — outside .bionic/. A row that itself
# reads the settled head is downstream of it, not a writer of it: counting it would make the
# walk wait for the release, and the release (held for its step and its approval) for the walk.
expect_eq "EDGES.7 a row that reads head is not a writer of head: the walk does not wait for the release" "no" \
  "$(has_line "$EDGES_REPLAY" "T18${TAB}T16${TAB}head")"
expect_eq "EDGES.7b …while the release does wait for the open builds" "yes" \
  "$(has_line "$EDGES_REPLAY" "T30${TAB}T18${TAB}head")"

# THE SAME ROWS AS WRITTEN, deps ids and no reads column: the review waits for the walk.
expect_eq "EDGES.8 the legacy replay keeps 1.10's answer: the review is not ready behind the walk" "no" \
  "$(has_line "$(call units_ready "$SANDBOX/replay-legacy.md" 5)" T17)"
expect_eq "EDGES.8b …and units_edges reads its deps id as the edge" "yes" \
  "$(has_line "$(call units_edges "$SANDBOX/replay-legacy.md")" "T16${TAB}T17${TAB}T16")"

# ============================================================
section "SHARE — wave-26 T2: shared files run together; only an unmergeable path holds a row (REQ-5, AC-5.3; D11)"
# ============================================================
#
# Two rows that write one file are both ready: they reconcile on landing. A `Files` entry
# ending in `!` is unmergeable, and a row holding one waits while another open row declares
# the same path — the active row first, then table order, so two pending rows never hold each
# other for ever.
cat > "$SANDBOX/share.md" <<'SHARE_EOF'
## SDLC State

current: 4
approved-by: fixture 2026-10-03T00:00Z "approved"

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | reads | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | shares x.sh | implementor | — | 30 | REQ-x | lib/x.sh, tests/x1.test.sh |  | pending |
| T2 | 4 | build | shares x.sh | implementor | — | 30 | REQ-x | lib/x.sh, tests/x2.test.sh |  | pending |
| T3 | 4 | build | y.sh, unmergeable | implementor | — | 30 | REQ-x | lib/y.sh! |  | pending |
| T4 | 4 | build | y.sh, unmergeable | implementor | — | 30 | REQ-x | lib/y.sh!, tests/y.test.sh |  | pending |
| T5 | 4 | build | z.sh, plain, behind an active unmergeable writer | implementor | — | 30 | REQ-x | lib/z.sh |  | pending |
| T6 | 4 | build | z.sh, unmergeable, running | implementor | — | 30 | REQ-x | lib/z.sh! |  | active |
SHARE_EOF
READY_SHARE="$(call units_ready "$SANDBOX/share.md" 4)"
expect_eq "SHARE.1 AC-5.3 two rows declaring one plain file are both ready" "yes yes" \
  "$(printf '%s %s' "$(has_line "$READY_SHARE" T1)" "$(has_line "$READY_SHARE" T2)")"
expect_eq "SHARE.2 AC-5.3 two rows declaring y.sh! are not both ready: the first in table order goes" "yes no" \
  "$(printf '%s %s' "$(has_line "$READY_SHARE" T3)" "$(has_line "$READY_SHARE" T4)")"
expect_eq "SHARE.3 …and units_waiting names the held row, the marked path and its holder" "yes" \
  "$(has_line "$(call units_waiting "$SANDBOX/share.md" 4)" "T4${TAB}lib/y.sh!${TAB}T3${TAB}pending")"
expect_eq "SHARE.4 an active row's unmergeable path holds a pending row declaring it plain" "no" \
  "$(has_line "$READY_SHARE" T5)"
expect_eq "SHARE.4b …and the hold is an edge, from the holder" "yes" \
  "$(has_line "$(call units_edges "$SANDBOX/share.md")" "T6${TAB}T5${TAB}lib/z.sh!")"
expect_eq "SHARE.5 the mark is legal in a Files cell: the table validates clean" "0" \
  "$(call_rc units_validate "$SANDBOX/share.md")"
sed 's/| lib\/z.sh! |  | active |/| lib\/z.sh! |  | landed |/' "$SANDBOX/share.md" > "$SANDBOX/share-landed.md"
expect_eq "SHARE.6 once the holder lands, the held row is ready" "yes" \
  "$(has_line "$(call units_ready "$SANDBOX/share-landed.md" 4)" T5)"

# ============================================================
section "EXT — wave-26 T2: an outside input is declared, in either cell (REQ-5, AC-5.5; D1)"
# ============================================================
cat > "$SANDBOX/ext-reads.md" <<'EXTR_EOF'
## SDLC State

current: 4
approved-by: fixture 2026-10-03T00:00Z "approved"

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | reads | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | an ordinary build | implementor | — | 30 | REQ-x | lib/a.sh |  | pending |
| T2 | 4 | build | waits on a vendor fix | implementor | — | 30 | REQ-x | lib/b.sh | approval:plan, ext:vendor-fix | pending |
| T3 | 4 | build | waits on CI, in the deps cell | implementor | ext:ci-green | 30 | REQ-x | lib/c.sh |  | pending |
EXTR_EOF
READY_EXT="$(call units_ready "$SANDBOX/ext-reads.md" 4)"
WAIT_EXT="$(call units_waiting "$SANDBOX/ext-reads.md" 4)"
expect_eq "EXT.1 ext: is valid in the reads cell and in the deps cell of a reads table" "0" \
  "$(call_rc units_validate "$SANDBOX/ext-reads.md")"
expect_eq "EXT.2 AC-5.5 a row reading ext:vendor-fix is waiting, the ordinary row ready" "no yes" \
  "$(printf '%s %s' "$(has_line "$READY_EXT" T2)" "$(has_line "$READY_EXT" T1)")"
expect_eq "EXT.3 AC-5.5 …named with that reason, and no writer in the table" "yes" \
  "$(has_line "$WAIT_EXT" "T2${TAB}ext:vendor-fix${TAB}-${TAB}-")"
expect_eq "EXT.4 an ext: token in the deps cell waits the same way" "yes no" \
  "$(printf '%s %s' "$(has_line "$WAIT_EXT" "T3${TAB}ext:ci-green${TAB}-${TAB}-")" "$(has_line "$READY_EXT" T3)")"
expect_eq "EXT.5 units_held reports the world's hold on a row whose other reads are met" "yes" \
  "$(has_line "$(call units_held "$SANDBOX/ext-reads.md" 4)" "T2: held by ext:vendor-fix")"
sed 's/| approval:plan, ext:vendor-fix |/| approval:plan |/' "$SANDBOX/ext-reads.md" > "$SANDBOX/ext-reads-done.md"
expect_eq "EXT.6 AC-5.5 …until the token is removed" "yes" \
  "$(has_line "$(call units_ready "$SANDBOX/ext-reads-done.md" 4)" T2)"
# AN UNKNOWN TOKEN IS NEVER SATISFIED (AC-5.5 fails-when). The validator refuses it, and the
# ready set, asked anyway, holds the row and names the token.
sed 's/| approval:plan, ext:vendor-fix |/| approval:plan, vendor-fix |/' "$SANDBOX/ext-reads.md" > "$SANDBOX/ext-reads-unknown.md"
expect_eq "EXT.7 a bare word in place of the ext: token is not satisfied" "no" \
  "$(has_line "$(call units_ready "$SANDBOX/ext-reads-unknown.md" 4)" T2)"
expect_eq "EXT.7b …the wait names it" "yes" \
  "$(has_line "$(call units_waiting "$SANDBOX/ext-reads-unknown.md" 4)" "T2${TAB}vendor-fix${TAB}-${TAB}-")"

# ============================================================
section "LIVE — wave-26 T2: a live read is satisfied by what exists; named artifacts from the plan text (REQ-6, AC-6.5 lib half; D1)"
# ============================================================
#
# The lib half only: `live:<artifact>` is satisfied when the artifact exists at all. "Ready
# again only for the difference since its last proof" is T14's rule, on the seam this leaves.
# `proof:<kind>` reads a `proved: kind=<kind>` line and `approval:<name>` an `approved: <name>`
# line, both inside `## SDLC State`; `approval:plan` is the `approved-by:` line.
cat > "$SANDBOX/live-reads.md" <<'LIVE_EOF'
## SDLC State

current: 5
approved-by: fixture 2026-10-03T00:00Z "approved"

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | reads | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T0 | 4 | build | already landed | implementor | — | 30 | REQ-x | lib/z.sh |  | landed |
| T1 | 4 | build | still building | implementor | — | 30 | REQ-x | lib/a.sh |  | active |
| T2 | 6 | review | follows the build | critic | — | 30 | REQ-x | .bionic/docs/record/w/review.md | approval:plan, live:head | pending |
| T3 | 6 | review | reads the floor proof live | critic | — | 30 | REQ-x | .bionic/docs/record/w/r2.md | live:proof:floor | pending |
| T4 | 5 | verify | the floor | test-runner | — | 30 | REQ-x | .bionic/docs/record/w/floor.txt | approval:plan | pending |
| T5 | 7 | doc | the release, on its approval | implementor | — | 30 | REQ-x | .bionic/docs/record/w/release.md | approval:release, proof:floor | pending |
LIVE_EOF
READY_LIVE="$(call units_ready "$SANDBOX/live-reads.md" 7)"
WAIT_LIVE="$(call units_waiting "$SANDBOX/live-reads.md" 7)"
expect_eq "LIVE.1 a live:head read is satisfied while a build is still open, once one has landed (T0)" "yes" "$(has_line "$READY_LIVE" T2)"
expect_eq "LIVE.2 live:proof:floor is not satisfied before a proved: kind=floor line exists" "no" \
  "$(has_line "$READY_LIVE" T3)"
expect_eq "LIVE.3 approval:release and proof:floor wait, each named; the floor's writer is the open verify row" "yes yes" \
  "$(printf '%s %s' "$(has_line "$WAIT_LIVE" "T5${TAB}approval:release${TAB}-${TAB}-")" \
     "$(has_line "$WAIT_LIVE" "T5${TAB}proof:floor${TAB}T4${TAB}pending")")"
awk '{ print } /^approved-by:/ {
  print "proved: kind=floor head=0123456789abcdef0123456789abcdef01234567 at=2026-10-03T01:00:00Z evidence=record/w/floor.txt"
  print "approved: release by fixture 2026-10-03T02:00:00Z \"ship it\"" }' \
  "$SANDBOX/live-reads.md" > "$SANDBOX/live-reads-proved.md"
READY_PROVED="$(call units_ready "$SANDBOX/live-reads-proved.md" 7)"
expect_eq "LIVE.4 with the proof line, the live floor read is satisfied" "yes" "$(has_line "$READY_PROVED" T3)"
# A SETTLED proof: READ WAITS FOR ITS OPEN WRITERS EVEN WITH A LINE WRITTEN (wave-26 T35, review 5
# F2): the floor row T4 is still pending, so the line is stale until it lands.
expect_eq "LIVE.5 with the proof and the approval lines but the floor row still open, the release waits on it" "no yes" \
  "$(printf '%s %s' "$(has_line "$READY_PROVED" T5)" \
     "$(has_line "$(call units_waiting "$SANDBOX/live-reads-proved.md" 7)" "T5${TAB}proof:floor${TAB}T4${TAB}pending")")"
sed 's/| approval:plan | pending |$/| approval:plan | landed |/' "$SANDBOX/live-reads-proved.md" > "$SANDBOX/live-reads-floored.md"
floor_at_head "$SANDBOX/live-reads-floored.md" "$FLOOR_REPO/live-reads-floored.md"
expect_eq "LIVE.5b …and once the floor row lands, the release's settled reads are satisfied (the proof at the head)" "yes" \
  "$(has_line "$(call units_ready "$FLOOR_REPO/live-reads-floored.md" 7)" T5)"
expect_eq "LIVE.6 a live read is never an edge: nothing enters T2 or T3" "" \
  "$(call units_edges "$SANDBOX/live-reads.md" | awk -F'\t' '$2 == "T2" || $2 == "T3"')"
expect_eq "LIVE.6b …while the settled proof:floor read is one, from the verify row" "yes" \
  "$(has_line "$(call units_edges "$SANDBOX/live-reads.md")" "T4${TAB}T5${TAB}proof:floor")"
# A FENCED LINE IS DOCUMENTATION, not a proof: the plan text is read fence-aware.
awk '{ print } /^approved-by:/ { print "```"; print "proved: kind=floor head=x at=y evidence=z"; print "```" }' \
  "$SANDBOX/live-reads.md" > "$SANDBOX/live-reads-fenced.md"
expect_eq "LIVE.7 a proved: line inside a fence proves nothing" "no" \
  "$(has_line "$(call units_ready "$SANDBOX/live-reads-fenced.md" 7)" T3)"

# A REVIEW FOLLOWS THE BUILD (wave-26 T14; D10, AC-6.1, AC-6.5). A row reading `live:head` is
# ready when the plan is approved, landed work exists that the last `proved: kind=review` line
# has not read, and no other row of its kind is open. "Past the last proof" compares two heads:
# the proof line's `head=` and the working branch's head now, which the program does not fetch —
# its caller hands it in as UNITS_LIVE_HEAD (the tick reads it from git; a caller that has none
# gets the cautious answer, not ready). With no review proof yet, the first review is offered as
# soon as a row that writes outside .bionic/ has landed. `units_live_range` names the difference
# the ready review reads. SYNTHESIZED tables; the heads are fixed hex, no repository needed.
LV_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
LV_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
LV_C=cccccccccccccccccccccccccccccccccccccccc
lv_plan() {  # <file> <state lines> <rows...> -> an approved reads table
  local f="$1" st="$2"; shift 2
  { printf '## SDLC State\n\ncurrent: 4\napproved-by: fixture 2026-10-04T00:00Z "approved"\n%s\n\n## Tasks\n\n' "$st"
    printf '| id | step | kind | task | agent | deps | size | serves | Files | reads | status |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
    for r in "$@"; do printf '%s\n' "$r"; done; } > "$f"
}
lv_proof() { printf 'proved: kind=review head=%s at=2026-10-04T0%s:00:00Z evidence=record/w/review.md' "$1" "${2:-1}"; }
# live_call <head> <fn> <args...> -> `call` with UNITS_LIVE_HEAD in the child's environment.
live_call() { local h="$1"; shift; UNITS_LIVE_HEAD="$h" call "$@"; }
LV_BUILD_LANDED="| T1 | 4 | build | landed work | implementor | — | 30 | REQ-x | lib/a.sh |  | landed |"
LV_BUILD_OPEN="| T2 | 4 | build | still building | implementor | — | 30 | REQ-x | lib/b.sh |  | active |"
LV_REVIEW="| T3 | 6 | review | follows the build | critic | — | 30 | REQ-x | .bionic/docs/record/w/review.md |  | pending |"
LV_FINAL="| T4 | 6 | review | the final review, settled head | critic | — | 30 | REQ-x | .bionic/docs/record/w/final.md | approval:plan, head | pending |"

# AC-6.1: no proof yet, one build landed, one still open — the review is offered now.
lv_plan "$SANDBOX/lv-first.md" "" "$LV_BUILD_LANDED" "$LV_BUILD_OPEN" "$LV_REVIEW" "$LV_FINAL"
expect_eq "LIVE.8 AC-6.1 no review proof yet and one build landed: the review is ready while a build is open" "yes" \
  "$(has_line "$(call units_ready "$SANDBOX/lv-first.md" 4)" T3)"
expect_eq "LIVE.8b …and the settled-head final review, pending, neither runs early nor holds it" "no" \
  "$(has_line "$(call units_ready "$SANDBOX/lv-first.md" 4)" T4)"
# THE DIFFERENTIAL: the same table with the landed build still open — nothing to review yet.
lv_plan "$SANDBOX/lv-none.md" "" "${LV_BUILD_LANDED/| landed |/| pending |}" "$LV_BUILD_OPEN" "$LV_REVIEW"
expect_eq "LIVE.8c …with nothing landed the review waits, and the wait says for what" "no yes" \
  "$(printf '%s %s' "$(has_line "$(call units_ready "$SANDBOX/lv-none.md" 4)" T3)" \
     "$(has_line "$(call units_waiting "$SANDBOX/lv-none.md" 4)" "T3${TAB}live:head: nothing has landed yet${TAB}-${TAB}-")")"
# A landed row that wrote only the record (.bionic/) is not work a review reads.
lv_plan "$SANDBOX/lv-rec.md" "" "| T1 | 4 | doc | a record only | implementor | — | 30 | REQ-x | .bionic/docs/record/w/n.md |  | landed |" "$LV_REVIEW"
expect_eq "LIVE.8d …and a landed record-only row is not a landing the review reads" "no" \
  "$(has_line "$(call units_ready "$SANDBOX/lv-rec.md" 4)" T3)"
# REVIEW 10 F4 (wave-26 T46): `record/…` is the record too, spelled from the docs root as older
# plans and proof lines spell it; a landed row writing only there made the first review ready
# with nothing built. The wait names why, read through the same table.
lv_plan "$SANDBOX/lv-rec2.md" "" "| T1 | 4 | review | an earlier review | critic | — | 30 | REQ-x | record/w/r1.md |  | landed |" "$LV_REVIEW"
expect_eq "LIVE.8e F4 a landed row whose only file is spelled record/… is no landing either, and the wait says so" "no yes" \
  "$(printf '%s %s' "$(has_line "$(call units_ready "$SANDBOX/lv-rec2.md" 4)" T3)" \
     "$(has_line "$(call units_waiting "$SANDBOX/lv-rec2.md" 4)" "T3${TAB}live:head: nothing has landed yet${TAB}-${TAB}-")")"
# ONE PREDICATE (A-T46.2): the record read waits on an open row writing record/…, as it does on
# one writing .bionic/…, and the shell spelling of the predicate answers the same.
lv_plan "$SANDBOX/lv-recrd.md" "" \
  "| T1 | 4 | doc | notes, record/ spelling | implementor | — | 30 | REQ-x | record/w/n.md |  | active |" \
  "| T2 | 4 | doc | notes, .bionic/ spelling | implementor | — | 30 | REQ-x | .bionic/docs/record/w/m.md |  | active |" \
  "| T5 | 4 | build | reads the record | implementor | — | 30 | REQ-x | lib/r.sh | approval:plan, record | pending |"
expect_eq "LIVE.8f F4 a record read waits on the open writer of either spelling" "yes yes" \
  "$(W="$(call units_waiting "$SANDBOX/lv-recrd.md" 4)"; printf '%s %s' \
     "$(has_line "$W" "T5${TAB}record${TAB}T1${TAB}active")" "$(has_line "$W" "T5${TAB}record${TAB}T2${TAB}active")")"
expect_eq "LIVE.8g F4 units_writes_head: record/… and .bionic/… write no head; a tracked path does" "1 1 0" \
  "$(call_rc units_writes_head "record/w/r1.md") $(call_rc units_writes_head ".bionic/docs/record/w/r1.md") $(call_rc units_writes_head "record/w/r1.md, lib/a.sh")"

# AC-6.5: after proof-add review at head A the review is not ready at A; one more landing (head
# B) makes it ready for A..B only, never for the whole diff again.
lv_plan "$SANDBOX/lv-proved.md" "$(lv_proof "$LV_A")" "$LV_BUILD_LANDED" "$LV_BUILD_OPEN" "$LV_REVIEW"
expect_eq "LIVE.9 AC-6.5 a review proof at head A and the head still A: not ready" "no" \
  "$(has_line "$(live_call "$LV_A" units_ready "$SANDBOX/lv-proved.md" 4)" T3)"
expect_eq "LIVE.9b …and the wait names the proof's head it has not moved past" "yes" \
  "$(has_line "$(live_call "$LV_A" units_waiting "$SANDBOX/lv-proved.md" 4)" \
     "T3${TAB}live:head: nothing landed past the review proof at aaaaaaaaaaaa${TAB}-${TAB}-")"
expect_eq "LIVE.10 AC-6.5 one more landing, the head at B: ready" "yes" \
  "$(has_line "$(live_call "$LV_B" units_ready "$SANDBOX/lv-proved.md" 4)" T3)"
expect_eq "LIVE.10b …and the difference it reads is A..B, not the whole diff" "${LV_A}..${LV_B}" \
  "$(live_call "$LV_B" units_live_range "$SANDBOX/lv-proved.md")"
lv_plan "$SANDBOX/lv-proved2.md" "$(lv_proof "$LV_A" 1)
$(lv_proof "$LV_B" 2)" "$LV_BUILD_LANDED" "$LV_BUILD_OPEN" "$LV_REVIEW"
expect_eq "LIVE.10c two review proofs: the newest is the one compared — at B not ready, at C ready for B..C" "no yes ${LV_B}..${LV_C}" \
  "$(printf '%s %s %s' "$(has_line "$(live_call "$LV_B" units_ready "$SANDBOX/lv-proved2.md" 4)" T3)" \
     "$(has_line "$(live_call "$LV_C" units_ready "$SANDBOX/lv-proved2.md" 4)" T3)" \
     "$(live_call "$LV_C" units_live_range "$SANDBOX/lv-proved2.md")")"
expect_eq "LIVE.10d with no review proof the range is the whole landed work: units_live_range prints nothing" "" \
  "$(live_call "$LV_B" units_live_range "$SANDBOX/lv-first.md")"
# THE CAUTIOUS DIRECTION: a proof exists and the caller handed in no head — nothing past the
# proof can be seen, so the row is not ready, and the wait says the head is unknown.
expect_eq "LIVE.11 a review proof and no head handed in: not ready, the wait names the unknown head" "no yes" \
  "$(printf '%s %s' "$(has_line "$(live_call "" units_ready "$SANDBOX/lv-proved.md" 4)" T3)" \
     "$(has_line "$(live_call "" units_waiting "$SANDBOX/lv-proved.md" 4)" \
        "T3${TAB}live:head: the head past the review proof at aaaaaaaaaaaa is not known here${TAB}-${TAB}-")")"
# REVIEW 7 F6: ONE READING OF A PROOF LINE. Readiness and proof.sh's `proof_last` read through the
# same `proof_fields`: a proof line starts `proved:` at the first column and its head is hex. A
# bulleted `- proved:` line and a `head=none` line are prose to both — so the review waits as for
# no proof at all (nothing landed but T1, which here is pending) — while the column-0 hex line
# is a proof to both.
PROOF_LIB="$REPO_ROOT/payload/scripts/lib/proof.sh"
proof_last_of() { bash -c '. "$1" && proof_last "$2" review' _ "$PROOF_LIB" "$1" 2>/dev/null; }
LV_PENDING_BUILD="${LV_BUILD_LANDED/| landed |/| pending |}"
lv_plan "$SANDBOX/lv-f6-hex.md" "$(lv_proof "$LV_A")" "$LV_PENDING_BUILD" "$LV_REVIEW"
lv_plan "$SANDBOX/lv-f6-bullet.md" "- $(lv_proof "$LV_A")" "$LV_PENDING_BUILD" "$LV_REVIEW"
lv_plan "$SANDBOX/lv-f6-none.md" "proved: kind=review head=none at=2026-10-04T01:00:00Z evidence=record/w/review.md" "$LV_PENDING_BUILD" "$LV_REVIEW"
expect_eq "LIVE.16 F6 a column-0 hex proof line: proof_last reads it and readiness compares against it" \
  "${LV_A} yes" "$(proof_last_of "$SANDBOX/lv-f6-hex.md") $(has_line "$(live_call "$LV_A" units_waiting "$SANDBOX/lv-f6-hex.md" 4)" \
     "T3${TAB}live:head: nothing landed past the review proof at aaaaaaaaaaaa${TAB}-${TAB}-")"
expect_eq "LIVE.16b F6 a bulleted - proved: line is no proof to either reader" "|yes" \
  "$(proof_last_of "$SANDBOX/lv-f6-bullet.md")|$(has_line "$(live_call "$LV_A" units_waiting "$SANDBOX/lv-f6-bullet.md" 4)" \
     "T3${TAB}live:head: nothing has landed yet${TAB}-${TAB}-")"
expect_eq "LIVE.16c F6 head=none is no proof to either reader" "|yes" \
  "$(proof_last_of "$SANDBOX/lv-f6-none.md")|$(has_line "$(live_call "$LV_A" units_waiting "$SANDBOX/lv-f6-none.md" 4)" \
     "T3${TAB}live:head: nothing has landed yet${TAB}-${TAB}-")"

# A fenced review proof is documentation: the table rule (one landed build) still answers.
lv_plan "$SANDBOX/lv-fenced.md" '```
'"$(lv_proof "$LV_A")"'
```' "$LV_BUILD_LANDED" "$LV_REVIEW"
expect_eq "LIVE.11b a fenced review proof is no proof: with one build landed the review is ready, head or none" "yes yes" \
  "$(printf '%s %s' "$(has_line "$(live_call "$LV_A" units_ready "$SANDBOX/lv-fenced.md" 4)" T3)" \
     "$(has_line "$(live_call "" units_ready "$SANDBOX/lv-fenced.md" 4)" T3)")"
# The plan approval is still read: the kind default is approval:plan, live:head.
grep -v '^approved-by:' "$SANDBOX/lv-proved.md" > "$SANDBOX/lv-unapproved.md"
expect_eq "LIVE.12 without approved-by: the head past the proof does not make it ready" "no yes" \
  "$(printf '%s %s' "$(has_line "$(live_call "$LV_B" units_ready "$SANDBOX/lv-unapproved.md" 4)" T3)" \
     "$(has_line "$(live_call "$LV_B" units_waiting "$SANDBOX/lv-unapproved.md" 4)" "T3${TAB}approval:plan${TAB}-${TAB}-")")"

# NO ROW OF ITS KIND OPEN: a second review pass is not offered while one is running, and of two
# pending live reviews the one higher in the table goes first.
lv_plan "$SANDBOX/lv-busy.md" "$(lv_proof "$LV_A")" "$LV_BUILD_LANDED" "$LV_REVIEW" \
  "| T5 | 6 | review | a review pass in flight | critic | — | 30 | REQ-x | .bionic/docs/record/w/r5.md |  | active |"
expect_eq "LIVE.13 another review row active: the head past the proof does not make it ready" "no" \
  "$(has_line "$(live_call "$LV_B" units_ready "$SANDBOX/lv-busy.md" 4)" T3)"
expect_eq "LIVE.13b …the wait names the open review" "yes" \
  "$(has_line "$(live_call "$LV_B" units_waiting "$SANDBOX/lv-busy.md" 4)" "T3${TAB}live:head: review T5 is open (active)${TAB}-${TAB}-")"
sed 's/record\/w\/r5.md |  | active |/record\/w\/r5.md |  | landed |/' \
  "$SANDBOX/lv-busy.md" > "$SANDBOX/lv-done.md"
expect_eq "LIVE.13c …and once it lands the review is ready" "yes" \
  "$(has_line "$(live_call "$LV_B" units_ready "$SANDBOX/lv-done.md" 4)" T3)"
lv_plan "$SANDBOX/lv-two.md" "" "$LV_BUILD_LANDED" "$LV_REVIEW" \
  "| T6 | 6 | review | a second live review | critic | — | 30 | REQ-x | .bionic/docs/record/w/r6.md | approval:plan, live:head | pending |"
expect_eq "LIVE.13d two pending live reviews: the first is ready, the second waits for it" "yes no yes" \
  "$(R="$(call units_ready "$SANDBOX/lv-two.md" 4)"; printf '%s %s %s' "$(has_line "$R" T3)" "$(has_line "$R" T6)" \
     "$(has_line "$(call units_waiting "$SANDBOX/lv-two.md" 4)" "T6${TAB}live:head: review T3 goes first${TAB}-${TAB}-")")"

# REVIEW 5 F4: AN UNKNOWN LIVE TOKEN IS NEVER SATISFIED. The finding's probe P8 rows, beside a
# live path read whose only writer has landed (the positive on the same extractor).
lv_plan "$SANDBOX/lv-p8.md" "" "$LV_BUILD_LANDED" \
  "| T7 | 4 | build | live:foo | implementor | — | 30 | REQ-x | lib/p.sh | live:foo | pending |" \
  "| T8 | 4 | build | live:ext:ci | implementor | — | 30 | REQ-x | lib/q.sh | live:ext:ci | pending |" \
  "| T9 | 4 | build | live:T9 | implementor | — | 30 | REQ-x | lib/r.sh | live:T1 | pending |" \
  "| T10 | 4 | build | live path, landed writer | implementor | — | 30 | REQ-x | lib/s.sh | live:lib/a.sh | pending |"
READY_P8="$(call units_ready "$SANDBOX/lv-p8.md" 4)"
expect_eq "LIVE.14 F4 live:foo, live:ext:ci and live:<task id> are not ready; a live path with its writer landed is" "no no no yes" \
  "$(printf '%s %s %s %s' "$(has_line "$READY_P8" T7)" "$(has_line "$READY_P8" T8)" "$(has_line "$READY_P8" T9)" "$(has_line "$READY_P8" T10)")"

# THE ROWS proof-add review RETURNS TO pending: `units_live_rows` lists every row reading
# live:head with its kind and status, the kind default included; a settled head read is not one.
lv_plan "$SANDBOX/lv-rows.md" "" "$LV_BUILD_LANDED" "${LV_REVIEW/| pending |/| active |}" "$LV_FINAL" \
  "| T6 | 6 | doc | an addendum that reads the head live | implementor | — | 30 | REQ-x | .bionic/docs/record/w/a.md | live:head | pending |"
LIVE_ROWS="$(call units_live_rows "$SANDBOX/lv-rows.md")"
expect_eq "LIVE.15 units_live_rows names the review whose empty cell defaults to live:head, and the explicit reader" "yes yes" \
  "$(printf '%s %s' "$(has_line "$LIVE_ROWS" "T3${TAB}review${TAB}active")" "$(has_line "$LIVE_ROWS" "T6${TAB}doc${TAB}pending")")"
expect_eq "LIVE.15b …and not the settled-head final review" "" "$(printf '%s\n' "$LIVE_ROWS" | awk -F'\t' '$1 == "T4"')"
# REVIEW 10 F3 (wave-26 T46): handed the evidence path, units_live_rows names only the live row
# whose Files hold it — in either spelling of the record — and none for the final review's.
lv_plan "$SANDBOX/lv-rows2.md" "" "$LV_BUILD_LANDED" "${LV_REVIEW/| pending |/| active |}" "${LV_FINAL/| pending |/| active |}" \
  "| T7 | 6 | review | a second live pass, record/ spelling | critic | — | 30 | REQ-x | record/w/r7.md |  | active |"
expect_eq "LIVE.15c F3 with no evidence path both active live reviews are named" "yes yes" \
  "$(L="$(call units_live_rows "$SANDBOX/lv-rows2.md")"; printf '%s %s' \
     "$(has_line "$L" "T3${TAB}review${TAB}active")" "$(has_line "$L" "T7${TAB}review${TAB}active")")"
expect_eq "LIVE.15d F3 the evidence record/w/review.md names T3 alone" "T3" \
  "$(call units_live_rows "$SANDBOX/lv-rows2.md" "record/w/review.md .bionic/docs/record/w/review.md" | cut -f1 | tr '\n' ' ' | sed 's/ $//')"
expect_eq "LIVE.15e F3 …record/w/r7.md names T7 alone" "T7" \
  "$(call units_live_rows "$SANDBOX/lv-rows2.md" "record/w/r7.md .bionic/docs/record/w/r7.md" | cut -f1 | tr '\n' ' ' | sed 's/ $//')"
expect_eq "LIVE.15f F3 …and the final review's evidence, on the same table, names no row" "" \
  "$(call units_live_rows "$SANDBOX/lv-rows2.md" "record/w/final.md .bionic/docs/record/w/final.md")"

# ============================================================
section "LIVE-Q — wave-27 T10: a chain per question; each read row is offered its own range (REQ-1 AC-1.5, REQ-2 AC-2.3; D4)"
# ============================================================
#
# A read row is a review row whose reads carry `live:head:<q>[+<q>]`. Its exclusivity, its
# range and its return to pending are per question: the last proof it compares against is the
# last reading of each of ITS questions (`question=<q>` on the proof line), and its range starts
# at the oldest of those. A plan carries one read row per reader the rigor deals — one at
# `single` (the critic holds all three), two at `double` (wave-30 T11, D1) — and AC-1.5 asks that
# the timing be the same at each: one landing makes every dealt row ready. A third plan splits
# every question to its own row, which no level deals but a plan may carry: the mechanics hold.
# FIXTURE FIDELITY: SYNTHESIZED tables and proof lines in the shape lib/proof.sh `proof_line`
# writes (wave-27 T2); the heads are fixed hex and the head now is handed in, as the tick does.
#
# THE CONTROLS FIRST (the compatibility rule, written and run green before units.sh changed): a
# `review` row with the bare `live:head` read keeps 1.11.0's reading whatever the proof lines
# carry — its last proof is the last review line of ANY question, its range starts there, a
# review row of any kind open blocks it, and `units_live_range` with no row id answers the same.
# THE HEADS ARE COMMITS (wave-27 T43; review pass 17 F2): a read row's range starts by commit
# ancestry, so its plans sit in a throwaway repository and A..D are four commits in a line, A
# the oldest. X is a commit off A that D does not carry, M merges D and X, and Z is 40 hex that
# names no commit. Before T43 these were fixed hex in a directory that is no repository.
LQR="$SANDBOX/lq-repo"; mkdir -p "$LQR"
lq_git() { git -C "$LQR" -c user.name=units -c user.email=units@example.invalid "$@"; }
lq_git init -q 2>/dev/null
for lqc in A B C D; do lq_git commit -q --allow-empty -m "landing $lqc"; done
LQ_A="$(lq_git rev-parse HEAD~3)"; LQ_B="$(lq_git rev-parse HEAD~2)"
LQ_C="$(lq_git rev-parse HEAD~1)"; LQ_D="$(lq_git rev-parse HEAD)"
LQ_X="$(lq_git commit-tree -p "$LQ_A" -m "a landing off A" "$(lq_git rev-parse "$LQ_A^{tree}")")"
LQ_M="$(lq_git commit-tree -p "$LQ_D" -p "$LQ_X" -m "D and X merged" "$(lq_git rev-parse "$LQ_D^{tree}")")"
LQ_Z=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
expect_eq "LIVEQ.R0 precondition: A..D are four commits in a line, X off A, M their merge" "yes yes yes no" \
  "$(lq_git merge-base --is-ancestor "$LQ_A" "$LQ_D" && echo yes) $(lq_git merge-base --is-ancestor "$LQ_X" "$LQ_M" && echo yes) $(lq_git merge-base --is-ancestor "$LQ_D" "$LQ_M" && echo yes) $(lq_git merge-base --is-ancestor "$LQ_X" "$LQ_D" 2>/dev/null && echo yes || echo no)"
lq_read() {  # <question> <head> <minute> -> a reading's proof line, as proof_line writes it
  printf 'proved: kind=review head=%s at=2026-10-04T10:%s:00Z evidence=record/w/%s.md question=%s reader=w-%s result=pass scope=piece' \
    "$2" "$3" "$1" "$1" "$1"
}
lq_row() {  # <id> <task> <reads> [<status>] [<Files>] -> a review row
  printf '| %s | 6 | review | %s | critic | — | 30 | REQ-x | %s | %s | %s |' "$1" "$2" "${5:-.bionic/docs/record/w/$1.md}" "$3" "${4:-pending}"
}
lq_range() {  # <head> <plan> <row id> -> the row's range
  live_call "$1" units_live_range "$2" "$3"
}

# CTL — a bare live:head row in a plan whose proof lines are readings: the newest of any question.
lv_plan "$LQR/lq-ctl.md" "$(lq_read adversarial "$LQ_A" 01)
$(lq_read evidence "$LQ_B" 02)" "$LV_BUILD_LANDED" "$LV_REVIEW"
expect_eq "LIVEQ.CTL1 bare live:head, readings on the plan: at the newest reading's head it waits, naming that head" "no yes" \
  "$(printf '%s %s' "$(has_line "$(live_call "$LQ_B" units_ready "$LQR/lq-ctl.md" 4)" T3)" \
     "$(has_line "$(live_call "$LQ_B" units_waiting "$LQR/lq-ctl.md" 4)" \
        "T3${TAB}live:head: nothing landed past the review proof at ${LQ_B:0:12}${TAB}-${TAB}-")")"
expect_eq "LIVEQ.CTL2 …one landing later it is ready, its range from the newest reading of any question" "yes ${LQ_B}..${LQ_C}" \
  "$(has_line "$(live_call "$LQ_C" units_ready "$LQR/lq-ctl.md" 4)" T3) $(live_call "$LQ_C" units_live_range "$LQR/lq-ctl.md")"
expect_eq "LIVEQ.CTL3 …and the range asked for the bare row by its id is the same answer" "${LQ_B}..${LQ_C}" \
  "$(lq_range "$LQ_C" "$LQR/lq-ctl.md" T3)"
# CTL — an idle bare row writes no newer proof (wave-26 T62): at the proof's head the integrate
# row's proof:review names no writer; one landing later the bare row is its writer again.
lv_plan "$LQR/lq-ctl-int.md" "$(lq_read evidence "$LQ_B" 02)" "$LV_BUILD_LANDED" "$LV_REVIEW" \
  "| T9 | 8 | integrate | merge | integrator | — | 30 | REQ-x | — | proof:review | pending |"
expect_eq "LIVEQ.CTL4 bare row idle at the proof's head: integrate's proof:review has no writer; past it, the row is one" "no yes" \
  "$(has_line "$(live_call "$LQ_B" units_waiting "$LQR/lq-ctl-int.md" 8)" "T9${TAB}proof:review${TAB}T3${TAB}pending") $(has_line "$(live_call "$LQ_C" units_waiting "$LQR/lq-ctl-int.md" 8)" "T9${TAB}proof:review${TAB}T3${TAB}pending")"
# CTL — a bare live row is still blocked by any open review row, whatever that row reads.
lv_plan "$LQR/lq-ctl-busy.md" "$(lq_read evidence "$LQ_A" 01)" "$LV_BUILD_LANDED" "$LV_REVIEW" \
  "$(lq_row T5 'an evidence read in flight' 'approval:plan, live:head:evidence' active)"
expect_eq "LIVEQ.CTL5 a bare live row waits while any review row is active, a read row included" "no yes" \
  "$(printf '%s %s' "$(has_line "$(live_call "$LQ_B" units_ready "$LQR/lq-ctl-busy.md" 4)" T3)" \
     "$(has_line "$(live_call "$LQ_B" units_waiting "$LQR/lq-ctl-busy.md" 4)" "T3${TAB}live:head: review T5 is open (active)${TAB}-${TAB}-")")"

# THE TWO DEALINGS AND A SPLIT. `single`: T3 reads all three. `double`: T3 evidence (the
# auditor), T4 adversarial and structure (the critic). The split: T3, T4, T5, one question each.
LQ_SINGLE="$(lq_row T3 'the critic, all three' 'approval:plan, live:head:evidence+adversarial+structure')"
LQ_DOUBLE_E="$(lq_row T3 'the auditor' 'approval:plan, live:head:evidence')"
LQ_DOUBLE_AS="$(lq_row T4 'the critic' 'approval:plan, live:head:adversarial+structure')"
LQ_SPLIT_A="$(lq_row T4 'the critic' 'approval:plan, live:head:adversarial')"
LQ_SPLIT_S="$(lq_row T5 'the critic, structure alone' 'approval:plan, live:head:structure')"
# PHASE 1: every question last read at C, in the order adversarial, structure, evidence.
LQ_P1="$(lq_read adversarial "$LQ_C" 01)
$(lq_read structure "$LQ_C" 02)
$(lq_read evidence "$LQ_C" 03)"
lv_plan "$LQR/lq-single.md" "$LQ_P1" "$LV_BUILD_LANDED" "$LQ_SINGLE"
lv_plan "$LQR/lq-double.md" "$LQ_P1" "$LV_BUILD_LANDED" "$LQ_DOUBLE_E" "$LQ_DOUBLE_AS"
lv_plan "$LQR/lq-split.md" "$LQ_P1" "$LV_BUILD_LANDED" "$LQ_DOUBLE_E" "$LQ_SPLIT_A" "$LQ_SPLIT_S"
expect_eq "LIVEQ.0 precondition: the three fixtures are valid plans" "||" \
  "$(call units_validate "$LQR/lq-single.md")|$(call units_validate "$LQR/lq-double.md")|$(call units_validate "$LQR/lq-split.md")"
# lq_ready_ids <head> <plan> -> the ready read rows, space-joined
lq_ready_ids() { live_call "$1" units_ready "$2" 4 | awk '/^T[345]$/' | tr '\n' ' ' | sed 's/ $//'; }
expect_eq "LIVEQ.1 AC-1.5 at the head every question was read at, no read row is ready — single, double, split" "||" \
  "$(lq_ready_ids "$LQ_C" "$LQR/lq-single.md")|$(lq_ready_ids "$LQ_C" "$LQR/lq-double.md")|$(lq_ready_ids "$LQ_C" "$LQR/lq-split.md")"
expect_eq "LIVEQ.1b …and each waits naming its own questions and the head" "yes yes yes" \
  "$(W="$(live_call "$LQ_C" units_waiting "$LQR/lq-split.md" 4)"; printf '%s %s %s' \
     "$(has_line "$W" "T3${TAB}live:head:evidence: nothing landed past the evidence review proof at ${LQ_C:0:12}${TAB}-${TAB}-")" \
     "$(has_line "$W" "T4${TAB}live:head:adversarial: nothing landed past the adversarial review proof at ${LQ_C:0:12}${TAB}-${TAB}-")" \
     "$(has_line "$W" "T5${TAB}live:head:structure: nothing landed past the structure review proof at ${LQ_C:0:12}${TAB}-${TAB}-")")"
expect_eq "LIVEQ.2 AC-1.5 one landing (head D) makes every dealt read row ready at once — single, double, split" "T3|T3 T4|T3 T4 T5" \
  "$(lq_ready_ids "$LQ_D" "$LQR/lq-single.md")|$(lq_ready_ids "$LQ_D" "$LQR/lq-double.md")|$(lq_ready_ids "$LQ_D" "$LQR/lq-split.md")"
expect_eq "LIVEQ.2b …each with its own range, C..D" "${LQ_C}..${LQ_D}|${LQ_C}..${LQ_D} ${LQ_C}..${LQ_D}|${LQ_C}..${LQ_D} ${LQ_C}..${LQ_D} ${LQ_C}..${LQ_D}" \
  "$(lq_range "$LQ_D" "$LQR/lq-single.md" T3)|$(lq_range "$LQ_D" "$LQR/lq-double.md" T3) $(lq_range "$LQ_D" "$LQR/lq-double.md" T4)|$(lq_range "$LQ_D" "$LQR/lq-split.md" T3) $(lq_range "$LQ_D" "$LQR/lq-split.md" T4) $(lq_range "$LQ_D" "$LQR/lq-split.md" T5)"

# PHASE 2: the questions were last read at different heads — adversarial at A, structure at B,
# evidence at C — so each row's range starts at the OLDEST last head among its own questions.
LQ_P2="$(lq_read adversarial "$LQ_A" 01)
$(lq_read structure "$LQ_B" 02)
$(lq_read evidence "$LQ_C" 03)"
lv_plan "$LQR/lq2-single.md" "$LQ_P2" "$LV_BUILD_LANDED" "$LQ_SINGLE"
lv_plan "$LQR/lq2-double.md" "$LQ_P2" "$LV_BUILD_LANDED" "$LQ_DOUBLE_E" "$LQ_DOUBLE_AS"
lv_plan "$LQR/lq2-split.md" "$LQ_P2" "$LV_BUILD_LANDED" "$LQ_DOUBLE_E" "$LQ_SPLIT_A" "$LQ_SPLIT_S"
expect_eq "LIVEQ.3 each row's range starts at the oldest last head among its questions (single: A; double: C, A; split: C, A, B)" \
  "${LQ_A}..${LQ_D}|${LQ_C}..${LQ_D} ${LQ_A}..${LQ_D}|${LQ_C}..${LQ_D} ${LQ_A}..${LQ_D} ${LQ_B}..${LQ_D}" \
  "$(lq_range "$LQ_D" "$LQR/lq2-single.md" T3)|$(lq_range "$LQ_D" "$LQR/lq2-double.md" T3) $(lq_range "$LQ_D" "$LQR/lq2-double.md" T4)|$(lq_range "$LQ_D" "$LQR/lq2-split.md" T3) $(lq_range "$LQ_D" "$LQR/lq2-split.md" T4) $(lq_range "$LQ_D" "$LQR/lq2-split.md" T5)"
expect_eq "LIVEQ.3b at head C only the rows with a question read before C are ready, each from its own start" \
  "T3|T4 ${LQ_A}..${LQ_C}|T4 T5 ${LQ_A}..${LQ_C} ${LQ_B}..${LQ_C}" \
  "$(lq_ready_ids "$LQ_C" "$LQR/lq2-single.md")|$(lq_ready_ids "$LQ_C" "$LQR/lq2-double.md") $(lq_range "$LQ_C" "$LQR/lq2-double.md" T4)|$(lq_ready_ids "$LQ_C" "$LQR/lq2-split.md") $(lq_range "$LQ_C" "$LQR/lq2-split.md" T4) $(lq_range "$LQ_C" "$LQR/lq2-split.md" T5)"
expect_eq "LIVEQ.3c …and the idle evidence row prints no range at C" "" "$(lq_range "$LQ_C" "$LQR/lq2-split.md" T3)"
expect_eq "LIVEQ.3d units_live_range with no row id keeps 1.11.0's one range, from the newest review line of any question" \
  "${LQ_C}..${LQ_D}" "$(live_call "$LQ_D" units_live_range "$LQR/lq2-split.md")"

# STRICT KEYING (T2's A-T2.4): a 1.11.0 line carries no question and is no question's last proof.
# A question never read starts at the base: its row is ready once a code row has landed, its
# range prints nothing (the reader reads from the wave's base), and the head is not needed.
lv_plan "$LQR/lq-first.md" "$(lv_proof "$LQ_A")
$(lq_read adversarial "$LQ_B" 02)" "$LV_BUILD_LANDED" "$LQ_DOUBLE_E" "$LQ_SPLIT_A"
expect_eq "LIVEQ.4 a question with no reading of its own (only a 1.11.0 line): ready at any head, no range" "yes yes |" \
  "$(has_line "$(live_call "$LQ_B" units_ready "$LQR/lq-first.md" 4)" T3) $(has_line "$(live_call "" units_ready "$LQR/lq-first.md" 4)" T3) |$(lq_range "$LQ_C" "$LQR/lq-first.md" T3)"
expect_eq "LIVEQ.4b …beside the adversarial row on the same plan, idle at its own reading's head and ready past it" "no yes ${LQ_B}..${LQ_C}" \
  "$(has_line "$(live_call "$LQ_B" units_ready "$LQR/lq-first.md" 4)" T4) $(has_line "$(live_call "$LQ_C" units_ready "$LQR/lq-first.md" 4)" T4) $(lq_range "$LQ_C" "$LQR/lq-first.md" T4)"
lv_plan "$LQR/lq-first-none.md" "" "${LV_BUILD_LANDED/| landed |/| pending |}" "$LQ_DOUBLE_E"
expect_eq "LIVEQ.4c …and with nothing landed it waits, saying so" "no yes" \
  "$(has_line "$(call units_ready "$LQR/lq-first-none.md" 4)" T3) $(has_line "$(call units_waiting "$LQR/lq-first-none.md" 4)" "T3${TAB}live:head:evidence: nothing has landed yet${TAB}-${TAB}-")"
expect_eq "LIVEQ.5 a reading and no head handed in: not ready, the wait names the question's unknown head" "no yes" \
  "$(has_line "$(live_call "" units_ready "$LQR/lq-split.md" 4)" T4) $(has_line "$(live_call "" units_waiting "$LQR/lq-split.md" 4)" "T4${TAB}live:head:adversarial: the head past the adversarial review proof at ${LQ_C:0:12} is not known here${TAB}-${TAB}-")"

# EXCLUSIVITY IS PER QUESTION: an active read row holds a row that shares a question with it, and
# not one that does not. Of two pending rows sharing a question, the higher goes first.
lv_plan "$LQR/lq-busy.md" "$LQ_P1" "$LV_BUILD_LANDED" "$LQ_DOUBLE_E" "${LQ_SPLIT_A/| pending |/| active |}" "$LQ_SPLIT_S" \
  "$(lq_row T6 'a second adversarial read' 'approval:plan, live:head:adversarial+structure')"
expect_eq "LIVEQ.6 an active adversarial row holds the row sharing it and leaves the evidence and structure rows ready" "T3 T5|no" \
  "$(lq_ready_ids "$LQ_D" "$LQR/lq-busy.md")|$(has_line "$(live_call "$LQ_D" units_ready "$LQR/lq-busy.md" 4)" T6)"
expect_eq "LIVEQ.6b …the wait names the open row" "yes" \
  "$(has_line "$(live_call "$LQ_D" units_waiting "$LQR/lq-busy.md" 4)" "T6${TAB}live:head:adversarial+structure: review T4 is open (active)${TAB}-${TAB}-")"
lv_plan "$LQR/lq-two.md" "$LQ_P1" "$LV_BUILD_LANDED" "$LQ_DOUBLE_E" "$LQ_SPLIT_S" \
  "$(lq_row T6 'a second structure read' 'approval:plan, live:head:adversarial+structure')"
expect_eq "LIVEQ.6c two pending rows sharing structure: the higher is ready, the lower goes after it" "T3 T5|no yes" \
  "$(lq_ready_ids "$LQ_D" "$LQR/lq-two.md")|$(has_line "$(live_call "$LQ_D" units_ready "$LQR/lq-two.md" 4)" T6) $(has_line "$(live_call "$LQ_D" units_waiting "$LQR/lq-two.md" 4)" "T6${TAB}live:head:adversarial+structure: review T5 goes first${TAB}-${TAB}-")"
lv_plan "$LQR/lq-bare-busy.md" "$LQ_P1" "$LV_BUILD_LANDED" "$LQ_DOUBLE_E" \
  "| T7 | 6 | review | a 1.11.0 pass in flight | critic | — | 30 | REQ-x | .bionic/docs/record/w/r7.md |  | active |"
expect_eq "LIVEQ.6d an active review row with no question (bare or settled) holds every read row: the cautious direction" "no yes" \
  "$(has_line "$(live_call "$LQ_D" units_ready "$LQR/lq-bare-busy.md" 4)" T3) $(has_line "$(live_call "$LQ_D" units_waiting "$LQR/lq-bare-busy.md" 4)" "T3${TAB}live:head:evidence: review T7 is open (active)${TAB}-${TAB}-")"

# THE proof:review WRITER SET COUNTS OPEN READ ROWS PER QUESTION: a pending read row whose every
# question was read at the head writes no newer proof; one with a question past its reading does.
lv_plan "$LQR/lq-int.md" "$LQ_P2" "$LV_BUILD_LANDED" "$LQ_DOUBLE_E" "$LQ_SPLIT_A" "$LQ_SPLIT_S" \
  "| T9 | 8 | integrate | merge | integrator | — | 30 | REQ-x | — | proof:review | pending |"
LQ_INT_W="$(live_call "$LQ_C" units_waiting "$LQR/lq-int.md" 8 | awk -F'\t' '$1 == "T9" && $2 == "proof:review" { print $3 }' | tr '\n' ' ' | sed 's/ $//')"
expect_eq "LIVEQ.7 at head C the evidence row is idle and no writer; the adversarial and structure rows are" "T4 T5" "$LQ_INT_W"
expect_eq "LIVEQ.7b …one landing later all three are writers" "T3 T4 T5" \
  "$(live_call "$LQ_D" units_waiting "$LQR/lq-int.md" 8 | awk -F'\t' '$1 == "T9" && $2 == "proof:review" { print $3 }' | tr '\n' ' ' | sed 's/ $//')"

# THE ROW A READING RETURNS TO pending: handed a question, `units_live_rows` names the read rows
# carrying it, whatever their Files say; a bare row is still matched by its Files, as before.
LQ_DIR=.bionic/docs/record/w/
lv_plan "$LQR/lq-rows.md" "$LQ_P1" "$LV_BUILD_LANDED" \
  "$(lq_row T3 'the auditor' 'approval:plan, live:head:evidence' active "$LQ_DIR")" \
  "$(lq_row T4 'the critic' 'approval:plan, live:head:adversarial+structure' active "$LQ_DIR")" \
  "| T7 | 6 | review | a 1.11.0 pass | critic | — | 30 | REQ-x | .bionic/docs/record/w/r7.md |  | active |"
lq_rows_ids() { call units_live_rows "$@" | cut -f1 | tr '\n' ' ' | sed 's/ $//'; }
expect_eq "LIVEQ.8 with no question, the evidence path names every live row whose Files hold it" "T3 T4" \
  "$(lq_rows_ids "$LQR/lq-rows.md" record/w/ev.md .bionic/docs/record/w/ev.md)"
expect_eq "LIVEQ.8b with --question evidence, only the row carrying evidence" "T3" \
  "$(lq_rows_ids "$LQR/lq-rows.md" --question evidence record/w/ev.md .bionic/docs/record/w/ev.md)"
expect_eq "LIVEQ.8c with --question structure, only the row carrying structure" "T4" \
  "$(lq_rows_ids "$LQR/lq-rows.md" --question structure record/w/ev.md .bionic/docs/record/w/ev.md)"
expect_eq "LIVEQ.8d a bare row is matched by its Files under a question too, and only by them" "T3 T7|T3" \
  "$(lq_rows_ids "$LQR/lq-rows.md" --question evidence record/w/r7.md)|$(lq_rows_ids "$LQR/lq-rows.md" --question evidence record/w/other.md)"

# THE VALIDATOR: the token is accepted on a review row, with questions from the set; anything
# else under live:head: is refused, naming the row.
lv_plan "$LQR/lq-bad.md" "" "$LV_BUILD_LANDED" \
  "$(lq_row T3 'a style read' 'approval:plan, live:head:style')" \
  "$(lq_row T4 'no question' 'approval:plan, live:head:')" \
  "$(lq_row T5 'a doubled plus' 'approval:plan, live:head:evidence++structure')" \
  "| T6 | 4 | build | a builder that reads a question | implementor | — | 30 | REQ-x | lib/q.sh | approval:plan, live:head:evidence | pending |"
LQ_VAL="$(call units_validate "$LQR/lq-bad.md")"
expect_contains "LIVEQ.9 a question outside the set is refused, naming it" "T3: read live:head:style names a question outside evidence adversarial structure" "$LQ_VAL"
expect_contains "LIVEQ.9b an empty question list is refused" "T4: read live:head: names a question outside evidence adversarial structure" "$LQ_VAL"
expect_contains "LIVEQ.9c an empty question between two plusses is refused" "T5: read live:head:evidence++structure names a question outside evidence adversarial structure" "$LQ_VAL"
expect_contains "LIVEQ.9d a question read on a row that is not a review is refused" "T6: read live:head:evidence names questions; only a review row reads them" "$LQ_VAL"
expect_eq "LIVEQ.9e …and none of them is ever ready" "no no no no" \
  "$(R="$(live_call "$LQ_D" units_ready "$LQR/lq-bad.md" 4)"; printf '%s %s %s %s' "$(has_line "$R" T3)" "$(has_line "$R" T4)" "$(has_line "$R" T5)" "$(has_line "$R" T6)")"
# F10 (review pass 17): a refused token's wait carries one colon, an empty question list included.
LQ_BADW="$(live_call "$LQ_D" units_waiting "$LQR/lq-bad.md" 4)"
expect_eq "LIVEQ.9f F10 the wait of live:head: carries one colon; live:head:style keeps its own" "yes yes" \
  "$(has_line "$LQ_BADW" "T4${TAB}live:head: the read names a question outside evidence adversarial structure or sits on a row that is not a review${TAB}-${TAB}-") $(has_line "$LQ_BADW" "T3${TAB}live:head:style: the read names a question outside evidence adversarial structure or sits on a row that is not a review${TAB}-${TAB}-")"

# ---------- REVIEW PASS 17 ON T10 (wave-27 T43; A-orch-66) ----------
# F4: the validator holds each `+` part to an exact question, by the scheduler's own test. Two
# questions joined by a blank are one part that is no question: refused, and never ready.
lv_plan "$LQR/lq-f4.md" "" "$LV_BUILD_LANDED" \
  "$(lq_row T3 'two questions and a blank' 'approval:plan, live:head:evidence adversarial')" \
  "$(lq_row T4 'the same, the other pair' 'approval:plan, live:head:adversarial structure')" \
  "$(lq_row T5 'a good read beside them' 'approval:plan, live:head:adversarial+structure')"
LQ_F4V="$(call units_validate "$LQR/lq-f4.md")"
expect_contains "LIVEQ.F4 F4 live:head:evidence adversarial is a violation" "T3: read live:head:evidence adversarial names a question outside evidence adversarial structure" "$LQ_F4V"
expect_contains "LIVEQ.F4b …and so is live:head:adversarial structure" "T4: read live:head:adversarial structure names a question outside evidence adversarial structure" "$LQ_F4V"
expect_eq "LIVEQ.F4c …the + row beside them is no violation, and the scheduler agrees: neither refused row is ever ready" "2|no no" \
  "$(nlines "$LQ_F4V")|$(R="$(live_call "$LQ_D" units_ready "$LQR/lq-f4.md" 4)"; printf '%s %s' "$(has_line "$R" T3)" "$(has_line "$R" T4)")"

# F1 (blocker): T3 is a review row whose reads are empty, the kind default, a bare live:head; T4
# below it reads adversarial. adversarial was last read at A, the bare proof is at C, the head C.
# The bare row is idle (nothing landed past its proof), so it no longer holds T4: T4 is ready with
# A..C, and the integrate row's proof:review names T4 and never T3.
LQ_INT="| T9 | 8 | integrate | merge | integrator | — | 30 | REQ-x | — | proof:review | pending |"
lv_plan "$LQR/lq-f1.md" "$(lq_read adversarial "$LQ_A" 01)
$(lv_proof "$LQ_C" 2)" "$LV_BUILD_LANDED" "$LV_REVIEW" "$(lq_row T4 'the critic' 'approval:plan, live:head:adversarial')" "$LQ_INT"
expect_eq "LIVEQ.F1 F1 at C the idle bare T3 waits (nothing landed past), and T4 below it is ready" "no yes yes" \
  "$(has_line "$(live_call "$LQ_C" units_ready "$LQR/lq-f1.md" 4)" T3) $(has_line "$(live_call "$LQ_C" units_waiting "$LQR/lq-f1.md" 4)" "T3${TAB}live:head: nothing landed past the review proof at ${LQ_C:0:12}${TAB}-${TAB}-") $(has_line "$(live_call "$LQ_C" units_ready "$LQR/lq-f1.md" 4)" T4)"
expect_eq "LIVEQ.F1b …T4's range is A..C" "${LQ_A}..${LQ_C}" "$(lq_range "$LQ_C" "$LQR/lq-f1.md" T4)"
lq_int_w() {  # <head> <plan> -> the writers integrate's proof:review names, space-joined
  live_call "$1" units_waiting "$2" 8 | awk -F'\t' '$1 == "T9" && $2 == "proof:review" { print $3 }' | tr '\n' ' ' | sed 's/ $//'
}
expect_eq "LIVEQ.F1c …integrate's proof:review names T4 alone at C" "T4" "$(lq_int_w "$LQ_C" "$LQR/lq-f1.md")"
lv_plan "$LQR/lq-f1-read.md" "$(lq_read adversarial "$LQ_A" 01)
$(lv_proof "$LQ_C" 2)
$(lq_read adversarial "$LQ_C" 03)" "$LV_BUILD_LANDED" "$LV_REVIEW" "$(lq_row T4 'the critic' 'approval:plan, live:head:adversarial')" "$LQ_INT"
expect_eq "LIVEQ.F1d …once T4's reading registers at C neither is a writer; one landing later both are" "|T3 T4" \
  "$(lq_int_w "$LQ_C" "$LQR/lq-f1-read.md")|$(lq_int_w "$LQ_D" "$LQR/lq-f1-read.md")"
# Between two bare rows, idle together, 1.11.0's order and its words are unchanged.
lv_plan "$LQR/lq-f1-bare.md" "$(lv_proof "$LQ_C" 1)" "$LV_BUILD_LANDED" "$LV_REVIEW" \
  "| T4 | 6 | review | a second bare pass | critic | — | 30 | REQ-x | .bionic/docs/record/w/r4.md |  | pending |"
expect_eq "LIVEQ.F1e two bare rows idle at C: T3 waits on nothing landed, T4 on review T3 goes first" "yes yes" \
  "$(W="$(live_call "$LQ_C" units_waiting "$LQR/lq-f1-bare.md" 4)"; printf '%s %s' "$(has_line "$W" "T3${TAB}live:head: nothing landed past the review proof at ${LQ_C:0:12}${TAB}-${TAB}-")" "$(has_line "$W" "T4${TAB}live:head: review T3 goes first${TAB}-${TAB}-")")"
# The exemption needs the row BELOW to name a question: a bare row below an idle read row is held.
lv_plan "$LQR/lq-f1-below.md" "$(lq_read evidence "$LQ_C" 01)
$(lv_proof "$LQ_B" 2)" "$LV_BUILD_LANDED" "$(lq_row T3 'the auditor' 'approval:plan, live:head:evidence')" \
  "| T4 | 6 | review | a bare pass below | critic | — | 30 | REQ-x | .bionic/docs/record/w/r4.md |  | pending |"
expect_eq "LIVEQ.F1f a bare row below an idle read row still waits for it to go first" "no yes" \
  "$(has_line "$(live_call "$LQ_C" units_ready "$LQR/lq-f1-below.md" 4)" T4) $(has_line "$(live_call "$LQ_C" units_waiting "$LQR/lq-f1-below.md" 4)" "T4${TAB}live:head: review T3 goes first${TAB}-${TAB}-")"

# F5: an idle pending READ row above a read row sharing a question holds it not. T3 reads
# adversarial+structure, both read at C (idle); T4 reads adversarial+evidence, evidence at A.
lv_plan "$LQR/lq-f5.md" "$(lq_read adversarial "$LQ_C" 01)
$(lq_read structure "$LQ_C" 02)
$(lq_read evidence "$LQ_A" 03)" "$LV_BUILD_LANDED" \
  "$(lq_row T3 'idle at C' 'approval:plan, live:head:adversarial+structure')" \
  "$(lq_row T4 'evidence unread past A' 'approval:plan, live:head:adversarial+evidence')"
expect_eq "LIVEQ.F5 F5 an idle read row above shares adversarial and does not hold T4: T3 waits, T4 ready from A" "no yes ${LQ_A}..${LQ_C}" \
  "$(has_line "$(live_call "$LQ_C" units_ready "$LQR/lq-f5.md" 4)" T3) $(has_line "$(live_call "$LQ_C" units_ready "$LQR/lq-f5.md" 4)" T4) $(lq_range "$LQ_C" "$LQR/lq-f5.md" T4)"
# …and the review's mutant M1 (the exemption deleted), planted on a doctored copy of the library in
# a directory of its own, turns that row red: T4 then waits on T3 going first.
LQ_MUT="$SANDBOX/lq-mut"; mkdir -p "$LQ_MUT"; cp "$(dirname "$LIB")"/*.sh "$LQ_MUT/"
perl -0pi -e 's/ && !\(nq\[i\] && live_idle\(j\)\)\) \{ lwhy = knd\[i\] " " id\[j\] " goes first"/) { lwhy = knd[i] " " id[j] " goes first"/' "$LQ_MUT/units.sh"
expect_eq "LIVEQ.F5b M1 applied: the doctored copy differs from the library, and still parses" "differs 0" \
  "$(cmp -s "$LIB" "$LQ_MUT/units.sh" && echo same || echo differs) $(bash -n "$LQ_MUT/units.sh"; echo $?)"
LQ_F5M="$(LIB="$LQ_MUT/units.sh" live_call "$LQ_C" units_waiting "$LQR/lq-f5.md" 4)"
expect_eq "LIVEQ.F5c …under M1 T3 still waits on its own reading (the mutant runs) and T4 waits on T3 going first: F5 is red" "yes yes" \
  "$(has_line "$LQ_F5M" "T3${TAB}live:head:adversarial+structure: nothing landed past the adversarial+structure review proof at ${LQ_C:0:12}${TAB}-${TAB}-") $(has_line "$LQ_F5M" "T4${TAB}live:head:adversarial+evidence: review T3 goes first${TAB}-${TAB}-")"

# F2: the range starts by COMMIT ANCESTRY, never line order. structure's line is written first at
# C, adversarial's second at A, A an ancestor of C: at D the row reads A..D.
LQ_F2ROW="$(lq_row T4 'the critic' 'approval:plan, live:head:adversarial+structure')"
lv_plan "$LQR/lq-f2.md" "$(lq_read structure "$LQ_C" 01)
$(lq_read adversarial "$LQ_A" 02)" "$LV_BUILD_LANDED" "$LQ_F2ROW"
expect_eq "LIVEQ.F2 F2 structure at C written first, adversarial at A second: the range at D is A..D" "${LQ_A}..${LQ_D}" \
  "$(lq_range "$LQ_D" "$LQR/lq-f2.md" T4)"
expect_eq "LIVEQ.F2b …with the head moved back to A no range prints (C is no ancestor of A), never C..A" "${LQ_A}..${LQ_D}|" \
  "$(lq_range "$LQ_D" "$LQR/lq-f2.md" T4)|$(lq_range "$LQ_A" "$LQR/lq-f2.md" T4)"
# A last head that is no ancestor of the head asked counts as no reading: adversarial at X (off A),
# structure at A. At D no range (the question reads from the base); at M, which carries X, A..M.
lv_plan "$LQR/lq-f2x.md" "$(lq_read adversarial "$LQ_X" 01)
$(lq_read structure "$LQ_A" 02)" "$LV_BUILD_LANDED" "$LQ_F2ROW"
expect_eq "LIVEQ.F2c a last head D does not carry prints no range at D; at M, which carries it, A..M" "${LQ_A}..${LQ_M}|" \
  "$(lq_range "$LQ_M" "$LQR/lq-f2x.md" T4)|$(lq_range "$LQ_D" "$LQR/lq-f2x.md" T4)"
# Two last heads neither of which is an ancestor of the other (X and D, under M): no start is an
# ancestor of every other, so no range (A-T43.4); a one-question row on the same plan has its own.
lv_plan "$LQR/lq-f2m.md" "$(lq_read adversarial "$LQ_X" 01)
$(lq_read structure "$LQ_D" 02)" "$LV_BUILD_LANDED" "$LQ_F2ROW" \
  "$(lq_row T5 'the reviewer' 'approval:plan, live:head:structure')"
expect_eq "LIVEQ.F2d last heads on two lines of history: no range for the row; the structure row's is D..M" "|${LQ_D}..${LQ_M}" \
  "$(lq_range "$LQ_M" "$LQR/lq-f2m.md" T4)|$(lq_range "$LQ_M" "$LQR/lq-f2m.md" T5)"
# The repository asked is the one nearest the plan: a project kept under another project's .bionic/
# (as a scratch fixture is) answers from its own history, not the outer one's.
LQ_OUT="$SANDBOX/lq-outer"; mkdir -p "$LQ_OUT/.bionic/tmp"; git -C "$LQ_OUT" init -q 2>/dev/null
git clone -q "$LQR" "$LQ_OUT/.bionic/tmp/inner" 2>/dev/null; mkdir -p "$LQ_OUT/.bionic/tmp/inner/.bionic/docs/plans"
cp "$LQR/lq-f2.md" "$LQ_OUT/.bionic/tmp/inner/.bionic/docs/plans/p.md"
expect_eq "LIVEQ.F2f a plan under an inner project's .bionic/, itself under an outer one: the inner history answers, A..D" "${LQ_A}..${LQ_D}" \
  "$(lq_range "$LQ_D" "$LQ_OUT/.bionic/tmp/inner/.bionic/docs/plans/p.md" T4)"
# A head that names no commit is no reading, as before T43.
lv_plan "$LQR/lq-f2z.md" "$(lq_read adversarial "$LQ_Z" 01)
$(lq_read structure "$LQ_A" 02)" "$LV_BUILD_LANDED" "$LQ_F2ROW" \
  "$(lq_row T5 'the reviewer' 'approval:plan, live:head:structure')"
expect_eq "LIVEQ.F2e a last head that names no commit: no range for the row; the structure row's is A..D" "|${LQ_A}..${LQ_D}" \
  "$(lq_range "$LQ_D" "$LQR/lq-f2z.md" T4)|$(lq_range "$LQ_D" "$LQR/lq-f2z.md" T5)"

# F3: handed --reader, a read row returns only when the reader is its agent and every question it
# carries has a reading at the head just registered; a bare row is matched by its Files, as before.
lq_arow() {  # <id> <agent> <reads> <status> -> a review row with its agent cell
  printf '| %s | 6 | review | a read | %s | — | 30 | REQ-x | .bionic/docs/record/w/%s.md | %s | %s |' "$1" "$2" "$1" "$3" "$4"
}
LQ_F3ROWS=("$(lq_arow T4 w-crit 'approval:plan, live:head:adversarial+structure' active)" \
  "$(lq_arow T5 w-aud 'approval:plan, live:head:evidence' active)" \
  "| T7 | 6 | review | a 1.11.0 pass | critic | — | 30 | REQ-x | .bionic/docs/record/w/r7.md |  | active |")
lv_plan "$LQR/lq-f3.md" "$(lq_read adversarial "$LQ_A" 01)
$(lq_read structure "$LQ_A" 02)
$(lq_read evidence "$LQ_C" 03)
$(lq_read adversarial "$LQ_C" 04)" "$LV_BUILD_LANDED" "${LQ_F3ROWS[@]}"
expect_eq "LIVEQ.F3 F3 w-crit's adversarial reading at C returns nothing while structure is at A; w-aud's evidence returns T5" "|T5" \
  "$(lq_rows_ids "$LQR/lq-f3.md" --question adversarial --reader w-crit record/w/adversarial.md)|$(lq_rows_ids "$LQR/lq-f3.md" --question evidence --reader w-aud record/w/evidence.md)"
lv_plan "$LQR/lq-f3b.md" "$(lq_read adversarial "$LQ_A" 01)
$(lq_read structure "$LQ_A" 02)
$(lq_read evidence "$LQ_C" 03)
$(lq_read adversarial "$LQ_C" 04)
$(lq_read structure "$LQ_C" 05)" "$LV_BUILD_LANDED" "${LQ_F3ROWS[@]}"
expect_eq "LIVEQ.F3b …its structure reading at C returns T4; the same reading by w-rev returns nothing" "T4|" \
  "$(lq_rows_ids "$LQR/lq-f3b.md" --question structure --reader w-crit record/w/structure.md)|$(lq_rows_ids "$LQR/lq-f3b.md" --question structure --reader w-rev record/w/structure.md)"
expect_eq "LIVEQ.F3c a bare row is matched by its Files under a reader as before; T5 not, for its reader is w-aud" "T7" \
  "$(lq_rows_ids "$LQR/lq-f3b.md" --question evidence --reader w-other record/w/r7.md)"

# ============================================================
section "MOVED — wave-27 T43: a read after a fix is told which rows landed inside its range (REQ-1 AC-1.5, REQ-2 AC-2.3; D10; A-orch-48, A-orch-71)"
# ============================================================
#
# Once a question has its `scope=whole` reading, a later read of that question covers only the
# fixes that landed past it. The library names them from the plan and the run's landing record
# (`landing-proofs.log`, the header lines `land` writes; T44), never from git:
#   - `units_landings <plan> <record>`: each row's landing, the `merge=` of the last header carrying
#     its row; a landed or done build row with none is owed one.
#   - `units_rows_in_range <plan> <a>..<b> <record>`: given on stdin the merges the caller's git put
#     inside the range, the rows that landed there, with the matrix criteria of what they serve.
#   - `units_whole_read <plan> <row id>`: whether every question the read row carries has a whole
#     reading.
# FIXTURE FIDELITY: SYNTHESIZED plans and records. The record's header line is the Interfaces
# table's shape, with `stamp/v1|` lines under each header as `land` writes them. The heads are fixed
# hex, because membership is the caller's answer and no git is asked here.
MV_W=1111111111111111111111111111111111111111
MV_X=2222222222222222222222222222222222222222
MV_Y=3333333333333333333333333333333333333333
MV_P=4444444444444444444444444444444444444444
mv_plan() {  # <file> <state lines> <rows...> -> a reads table and a matrix of five criteria
  local f="$1" st="$2"; shift 2
  lv_plan "$f" "$st" "$@"
  printf '\n## Verification Matrix\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n' >> "$f"
  printf '| AC-%s | T2 | pending | record/w/x.md | |\n' 1.1 2.1 2.2 4.1 5.1 12.1 >> "$f"
}
mv_head() {  # <row> <merge> -> a landing record's header line and a stamp line under it
  printf 'landed: row=%s branch=wt/27-%s head=%s merge=%s at=2026-10-05T04:00:00Z\nstamp/v1|head=%s|dirty=0|rc=0|at=2026-10-05T03:59:00Z|suites=units.test.sh\n' \
    "$1" "$1" "$2" "$2" "$2"
}
MV_T1="| T1 | 4 | build | landed before the whole read | implementor | — | 30 | REQ-1 | lib/a.sh |  | landed |"
MV_T7="| T7 | 4 | build | a fix | implementor | — | 30 | REQ-2 | lib/b.sh |  | landed |"
MV_T8="| T8 | 4 | build | another fix | implementor | — | 30 | REQ-4, REQ-5 | lib/c.sh |  | landed |"
MV_T3="$(lq_row T3 'the reviewer' 'approval:plan, live:head:structure')"
MV_WHOLE="$(printf 'proved: kind=review head=%s at=2026-10-04T10:01:00Z evidence=record/w/st-whole.md question=structure reader=w-rev result=pass scope=whole' "$MV_W")"
mv_plan "$SANDBOX/mv.md" "$MV_WHOLE" "$MV_T1" "$MV_T7" "$MV_T8" "$MV_T3"
{ mv_head T1 "$MV_P"; mv_head T7 "$MV_X"; mv_head T8 "$MV_Y"; } > "$SANDBOX/mv-landings.log"
mv_in() {  # <merges, one per line> <plan> <record> -> units_rows_in_range's answer on W..Y
  call units_rows_in_range "$2" "${MV_W}..${MV_Y}" "$3" <<< "$1"
}
expect_eq "MOVED.0 precondition: the fixture plan is a valid plan" "" "$(call units_validate "$SANDBOX/mv.md")"
expect_eq "MOVED.1 units_landings names each row's merge, owed for a landed build row, table order" \
  "T1${TAB}${MV_P}${TAB}owed|T7${TAB}${MV_X}${TAB}owed|T8${TAB}${MV_Y}${TAB}owed" \
  "$(call units_landings "$SANDBOX/mv.md" "$SANDBOX/mv-landings.log" | tr '\n' '|' | sed 's/|$//')"
# Two fixes in one range: both merges inside W..Y, each row named with its matrix criteria.
expect_eq "MOVED.2 two fixes in one range: T7 and T8, each with the criteria of what it serves" \
  "T7${TAB}REQ-2${TAB}AC-2.1, AC-2.2|T8${TAB}REQ-4, REQ-5${TAB}AC-4.1, AC-5.1" \
  "$(mv_in "$MV_X
$MV_Y" "$SANDBOX/mv.md" "$SANDBOX/mv-landings.log" | tr '\n' '|' | sed 's/|$//')"
# One fix after the whole read: only T7's merge is inside; T1, landed before W, is never named.
expect_eq "MOVED.3 one fix after the whole read: T7 alone; T1, landed before the range, is not named" \
  "T7${TAB}REQ-2${TAB}AC-2.1, AC-2.2" "$(mv_in "$MV_X" "$SANDBOX/mv.md" "$SANDBOX/mv-landings.log")"
# A docs-only tail: no landing merge inside the range. Nothing, exit 0, beside MOVED.3's positive.
expect_eq "MOVED.4 a docs-only tail: no merge inside the range prints nothing and exits 0" "|0" \
  "$(mv_in "" "$SANDBOX/mv.md" "$SANDBOX/mv-landings.log"; printf '|%s' "$CALL_RC")"
expect_eq "MOVED.4b …and a range that is not <a>..<b> is a caller fault, exit 2" "2" \
  "$(printf '%s' "$MV_X" | call_rc units_rows_in_range "$SANDBOX/mv.md" "$MV_W" "$SANDBOX/mv-landings.log")"
# No whole fact yet: units_whole_read says no; with the whole reading it says yes.
mv_plan "$SANDBOX/mv-nowhole.md" "$(lq_read structure "$MV_W" 01)" "$MV_T1" "$MV_T7" "$MV_T8" "$MV_T3"
expect_eq "MOVED.5 no whole fact for the row's question: units_whole_read fails; with one it holds" "1|0" \
  "$(call_rc units_whole_read "$SANDBOX/mv-nowhole.md" T3)|$(call_rc units_whole_read "$SANDBOX/mv.md" T3)"
mv_plan "$SANDBOX/mv-two.md" "$MV_WHOLE" "$MV_T1" "$(lq_row T3 'the critic' 'approval:plan, live:head:adversarial+structure')"
expect_eq "MOVED.5b …a row carrying two questions needs a whole reading of each; a bare row has none" "1|1" \
  "$(call_rc units_whole_read "$SANDBOX/mv-two.md" T3)|$(lv_plan "$SANDBOX/mv-bare.md" "$MV_WHOLE" "$MV_T1" "$LV_REVIEW"; call_rc units_whole_read "$SANDBOX/mv-bare.md" T3)"
# The record's edges: a re-landing (the last header counts), row=— and an id the table lacks
# (skipped), a landed build row with no header (owed, no merge), a review row's landing (not owed).
{ mv_head T7 "$MV_P"; mv_head T7 "$MV_X"; mv_head — "$MV_Y"; mv_head T99 "$MV_Y"; mv_head T3 "$MV_Y"; } > "$SANDBOX/mv-edges.log"
expect_eq "MOVED.6 the last header of a row counts; row=— and an unknown id name no row; a build row with none is owed; a review row's is not" \
  "T1${TAB}-${TAB}owed|T7${TAB}${MV_X}${TAB}owed|T8${TAB}-${TAB}owed|T3${TAB}${MV_Y}${TAB}-" \
  "$(call units_landings "$SANDBOX/mv.md" "$SANDBOX/mv-edges.log" | tr '\n' '|' | sed 's/|$//')"
expect_eq "MOVED.6b …the re-landed T7 is named by its last merge, not its first" "T7|" \
  "$(mv_in "$MV_X" "$SANDBOX/mv.md" "$SANDBOX/mv-edges.log" | cut -f1)|$(mv_in "$MV_P" "$SANDBOX/mv.md" "$SANDBOX/mv-edges.log" | cut -f1)"
expect_eq "MOVED.6c no record file at all: every landed build row is owed one, none has a merge" \
  "T1${TAB}-${TAB}owed|T7${TAB}-${TAB}owed|T8${TAB}-${TAB}owed" \
  "$(call units_landings "$SANDBOX/mv.md" "$SANDBOX/no-such-landings.log" | tr '\n' '|' | sed 's/|$//')"
# EVERY COMMIT OF THE RANGE IS A RECORDED LANDING, OR THE LIST IS NOT PRINTED (wave-27 T34; review
# pass 30 should-fix 1 and 2, A-orch-86). The tick hands `units_unrecorded` the range's first-parent
# commits, from one `git rev-list` per offered row, and the library says which are the merge= of no
# header naming a row of the plan: a header with `row=—`, an id the table lacks, a commit made
# straight on the working branch, a landed row of any kind that left no header. Any one of them makes
# the tick print one `MOVED unknown` line. A header's merge may be short; it names the commit it is a
# prefix of. Still no git: the commits are the caller's.
MV_Z=5555555555555555555555555555555555555555
mv_unrec() {  # <commits, one per line> <record> -> units_unrecorded's answer, |-joined
  call units_unrecorded "$SANDBOX/mv.md" "$2" <<< "$1" | tr '\n' '|' | sed 's/|$//'
}
expect_eq "MOVED.7 a commit no header names is unrecorded; the rows' merges are not" "$MV_Z" \
  "$(mv_unrec "$MV_X
$MV_Z
$MV_Y" "$SANDBOX/mv-landings.log")"
expect_eq "MOVED.7b …every commit recorded: nothing, exit 0" "|0" \
  "$(call units_unrecorded "$SANDBOX/mv.md" "$SANDBOX/mv-landings.log" <<< "$MV_X
$MV_Y"; printf '|%s' "$CALL_RC")"
{ mv_head T7 "$MV_X"; mv_head — "$MV_Y"; mv_head T99 "$MV_Y"; } > "$SANDBOX/mv-nameless.log"
expect_eq "MOVED.7c a merge named only by row=— or by an id the table lacks is unrecorded" "$MV_Y" \
  "$(mv_unrec "$MV_X
$MV_Y" "$SANDBOX/mv-nameless.log")"
expect_eq "MOVED.7d no record file: every commit of the range is unrecorded, in the order given" "$MV_X|$MV_Y" \
  "$(mv_unrec "$MV_X
$MV_Y" "$SANDBOX/no-such-landings.log")"
mv_plan "$SANDBOX/mv-doc.md" "$MV_WHOLE" "$MV_T1" "$MV_T7" \
  "| T9 | 4 | doc | the changelog | implementor | — | 30 | REQ-12 | CHANGELOG.md |  | landed |" "$MV_T3"
{ mv_head T7 "${MV_X:0:7}"; mv_head T9 "$MV_Z"; } > "$SANDBOX/mv-doc.log"
expect_eq "MOVED.7e a landed doc row with a header is a recorded landing, and a short merge names its commit" "" \
  "$(call units_unrecorded "$SANDBOX/mv-doc.md" "$SANDBOX/mv-doc.log" <<< "$MV_X
$MV_Z")"
expect_eq "MOVED.7f …so both rows are named, the doc row with its criteria" \
  "T7${TAB}REQ-2${TAB}AC-2.1, AC-2.2|T9${TAB}REQ-12${TAB}AC-12.1" \
  "$(call units_rows_in_range "$SANDBOX/mv-doc.md" "${MV_W}..${MV_Z}" "$SANDBOX/mv-doc.log" <<< "$MV_X
$MV_Z" | tr '\n' '|' | sed 's/|$//')"
expect_eq "MOVED.7g control: the same doc row with no header leaves its merge unrecorded" "$MV_Z" \
  "$(call units_unrecorded "$SANDBOX/mv-doc.md" "$SANDBOX/mv-landings.log" <<< "$MV_X
$MV_Z" | /usr/bin/grep -x "$MV_Z")"

# ============================================================
section "HOLD — wave-26 T13: a doc row waits for its reads, not its step, in a table that declares reads (REQ-6, AC-6.1, AC-6.2; D3)"
# ============================================================
#
# D3 takes the step hold off `doc` rows: a doc row in a reads table waits for what it reads,
# like any row — the release for `approval:release`, a draft for the head. A table WITHOUT the
# column keeps the hold (A-T13.1): it has no approval to read, so its step is the one thing
# that keeps a release from being dispatched the moment its deps land. integrate and close keep
# theirs in either shape.
cat > "$SANDBOX/hold-reads.md" <<'HOLD_EOF'
## SDLC State

current: 4
approved-by: fixture 2026-10-04T00:00Z "approved"

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | reads | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | landed | implementor | — | 30 | REQ-x | lib/a.sh |  | landed |
| T2 | 7 | doc | the notes draft, reads exist | implementor | — | 30 | REQ-x | .bionic/docs/record/w/notes.md | approval:plan | pending |
| T3 | 7 | doc | the release | implementor | — | 30 | REQ-x | CHANGELOG.md | approval:release | pending |
| T4 | 8 | integrate | the merge | implementor | — | 30 | REQ-x | — | approval:plan | pending |
HOLD_EOF
READY_HOLD="$(call units_ready "$SANDBOX/hold-reads.md" 4)"
WAIT_HOLD="$(call units_waiting "$SANDBOX/hold-reads.md" 4)"
expect_eq "HOLD.1 at current: 4 a Step-7 doc row whose reads exist is ready" "yes" "$(has_line "$READY_HOLD" T2)"
expect_eq "HOLD.2 the release waits, for its approval" "yes" \
  "$(has_line "$WAIT_HOLD" "T3${TAB}approval:release${TAB}-${TAB}-")"
expect_eq "HOLD.2b …and not for its step" "no" "$(has_line "$WAIT_HOLD" "T3${TAB}step:7${TAB}-${TAB}-")"
expect_eq "HOLD.3 an integrate row keeps its step hold in a reads table" "yes" \
  "$(has_line "$WAIT_HOLD" "T4${TAB}step:8${TAB}-${TAB}-")"
expect_eq "HOLD.3b …and is not ready" "no" "$(has_line "$READY_HOLD" T4)"
awk '{ print } /^approved-by:/ { print "approved: release by fixture 2026-10-04T01:00:00Z \"ship it\"" }' \
  "$SANDBOX/hold-reads.md" > "$SANDBOX/hold-reads-released.md"
expect_eq "HOLD.4 with approved: release written, the release is ready at current: 4" "yes" \
  "$(has_line "$(call units_ready "$SANDBOX/hold-reads-released.md" 4)" T3)"
# THE CONTROL: the same rows in a table without the reads column. The doc rows are held for
# their step, the hold the tick names.
cat > "$SANDBOX/hold-legacy.md" <<'HOLD_EOF'
## SDLC State

current: 4
approved-by: fixture 2026-10-04T00:00Z "approved"

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | landed | implementor | — | 30 | REQ-x | lib/a.sh | landed |
| T2 | 7 | doc | the notes draft | implementor | T1 | 30 | REQ-x | .bionic/docs/record/w/notes.md | pending |
| T5 | 4 | build | ready | implementor | T1 | 30 | REQ-x | lib/b.sh | pending |
HOLD_EOF
READY_LEG="$(call units_ready "$SANDBOX/hold-legacy.md" 4)"
expect_eq "HOLD.5 in a table without reads a Step-7 doc row is held at current: 4" "no" "$(has_line "$READY_LEG" T2)"
expect_eq "HOLD.5b …while the build beside it is ready (the extractor reads a real set)" "yes" "$(has_line "$READY_LEG" T5)"
expect_eq "HOLD.5c …and the hold is named" "yes" \
  "$(has_line "$(call units_held "$SANDBOX/hold-legacy.md" 4)" "T2: step 7 doc row waits for current: 7")"

# ============================================================
section "HARDEN — wave-26 T35: the graph neither starts work early, deadlocks in silence, nor stops on one bracket (review 5, F1 F2 F3 F5 F7)"
# ============================================================
#
# Each table below is the review's failing table (review-5, probes P5-P12), SYNTHESIZED there
# and copied here; each was red against the lib it reviewed (3a707629).
# hard_plan <file> <state lines> <rows...> -> a reads table with an approved plan.
hard_plan() {
  local f="$1" st="$2"; shift 2
  { printf '## SDLC State\n\ncurrent: 5\napproved-by: fixture 2026-10-03T00:00Z "approved"\n%s\n\n## Tasks\n\n' "$st"
    printf '| id | step | kind | task | agent | deps | size | serves | Files | reads | status |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
    for r in "$@"; do printf '%s\n' "$r"; done; } > "$f"
}

# F1 — A ROW THAT READS head STILL WRITES IT FOR A ROW AT A LATER STEP. A test row (default
# `approval:plan, head`), a doc row, or a build row naming `head` can be writing code while the
# floor at Step 5 is asked; the floor must wait, or it proves a head without their changes.
FLOOR='| T2 | 5 | verify | floor | test-runner | — | 30 | REQ-x | .bionic/docs/record/w/floor.txt |  | pending |'
hard_plan "$SANDBOX/f1-doc.md" "" \
  '| T1 | 4 | doc | skills | implementor | — | 30 | REQ-x | skills/x/SKILL.md, tests/docs-pins.test.sh |  | pending |' "$FLOOR"
hard_plan "$SANDBOX/f1-test.md" "" \
  '| T1 | 4 | test | new tests | implementor | — | 30 | REQ-x | tests/new.test.sh |  | pending |' "$FLOOR"
hard_plan "$SANDBOX/f1-build.md" "" \
  '| T1 | 4 | build | a | implementor | — | 30 | REQ-x | lib/a.sh | approval:plan, head | pending |' "$FLOOR"
for v in doc test build; do
  R="$(call units_ready "$SANDBOX/f1-$v.md" 5)"
  expect_eq "HARDEN.F1 a $v row at Step 4 that reads head is ready, the Step-5 floor is not" "yes no" \
    "$(printf '%s %s' "$(has_line "$R" T1)" "$(has_line "$R" T2)")"
  expect_eq "HARDEN.F1b …the floor waits on it by head ($v)" "yes" \
    "$(has_line "$(call units_edges "$SANDBOX/f1-$v.md")" "T1${TAB}T2${TAB}head")"
done
# TWO HEAD READERS AT ONE STEP DO NOT HOLD EACH OTHER: the exception A-T2.4 made still stands
# between equals, or two test rows would wait for each other for ever.
hard_plan "$SANDBOX/f1-peers.md" "" \
  '| T1 | 4 | test | tests a | implementor | — | 30 | REQ-x | tests/a.test.sh |  | pending |' \
  '| T2 | 4 | test | tests b | implementor | — | 30 | REQ-x | tests/b.test.sh |  | pending |'
R="$(call units_ready "$SANDBOX/f1-peers.md" 5)"
expect_eq "HARDEN.F1c two head-reading rows at one step are both ready" "yes yes" \
  "$(printf '%s %s' "$(has_line "$R" T1)" "$(has_line "$R" T2)")"
# record, the same rule over .bionic/ paths (A-T2.4 applied the exception to both).
hard_plan "$SANDBOX/f1-record.md" "" \
  '| T1 | 4 | build | notes | implementor | — | 30 | REQ-x | .bionic/docs/record/w/notes.md | approval:plan, record | pending |' \
  '| T2 | 5 | verify | reads the record | test-runner | — | 30 | REQ-x | lib/r.sh | approval:plan, record | pending |'
R="$(call units_ready "$SANDBOX/f1-record.md" 5)"
expect_eq "HARDEN.F1d a record reader at an earlier step still writes the record for a later one" "yes no" \
  "$(printf '%s %s' "$(has_line "$R" T1)" "$(has_line "$R" T2)")"

# F2 — A proof: READ WAITS FOR EVERY OPEN WRITER, EVEN WHEN A PROOF LINE EXISTS. A re-floor
# verify row added after the floor was proved makes that proof stale: integrate must wait.
PROVED="proved: kind=floor head=0123456789abcdef0123456789abcdef01234567 at=2026-10-03T00:00:00Z evidence=record/f.txt
proved: kind=review head=0123456789abcdef0123456789abcdef01234567 at=2026-10-03T00:00:00Z evidence=record/r.txt"
hard_plan "$SANDBOX/f2.md" "$PROVED" \
  '| T1 | 5 | verify | re-floor | test-runner | — | 30 | REQ-x | .bionic/docs/record/w/floor2.txt |  | pending |' \
  '| T2 | 8 | integrate | merge | — | — | 30 | REQ-x | — |  | pending |'
R="$(call units_ready "$SANDBOX/f2.md" 8)"
expect_eq "HARDEN.F2 a proved floor with an open re-floor row: the re-floor is ready, integrate is not" "yes no" \
  "$(printf '%s %s' "$(has_line "$R" T1)" "$(has_line "$R" T2)")"
expect_eq "HARDEN.F2b …and integrate waits on proof:floor, naming the open verify row" "yes" \
  "$(has_line "$(call units_waiting "$SANDBOX/f2.md" 8)" "T2${TAB}proof:floor${TAB}T1${TAB}pending")"
sed 's/record\/w\/floor2.txt |  | pending |/record\/w\/floor2.txt |  | landed |/' \
  "$SANDBOX/f2.md" > "$SANDBOX/f2-landed.md"
floor_at_head "$SANDBOX/f2-landed.md" "$FLOOR_REPO/f2-landed.md"
# REWRITTEN BY wave-27 T14 (D3): integrate's proof:review is met by the facts state the tick hands
# in, not by the review line; this row is about the floor, so the review half is handed in covered.
expect_eq "HARDEN.F2c once the re-floor lands, the proof line satisfies integrate (the proof at the head)" "yes" \
  "$(has_line "$(UNITS_FACTS_STATE=covered call units_ready "$FLOOR_REPO/f2-landed.md" 8)" T2)"

# F3 — A READ CYCLE IS REFUSED AT VALIDATION, NAMING THE ROWS ON IT. Through two path reads, or
# one path read closed by an unmergeable hold. A row that merely waits behind the cycle is not
# on it; a cycle through a row already running is not a deadlock (it lands, and the wait clears).
hard_plan "$SANDBOX/f3-reads.md" "" \
  '| T1 | 4 | build | a | implementor | — | 30 | REQ-x | lib/a.sh | approval:plan, lib/b.sh | pending |' \
  '| T2 | 4 | build | b | implementor | — | 30 | REQ-x | lib/b.sh | approval:plan, lib/a.sh | pending |' \
  '| T3 | 4 | build | c, behind the cycle | implementor | — | 30 | REQ-x | lib/c.sh | approval:plan, lib/a.sh | pending |'
V="$(call units_validate "$SANDBOX/f3-reads.md")"; VRC="$(call_rc units_validate "$SANDBOX/f3-reads.md")"
CYC="$(printf '%s\n' "$V" | grep -F 'read cycle')"
expect_eq "HARDEN.F3 a cycle of two path reads is refused" "1" "$VRC"
expect_nonempty "HARDEN.F3b …by a line that says read cycle" "$CYC"
expect_eq "HARDEN.F3c …naming both rows on it" "yes yes" \
  "$(printf '%s %s' "$(printf '%s' "$CYC" | grep -qw T1 && echo yes || echo no)" \
     "$(printf '%s' "$CYC" | grep -qw T2 && echo yes || echo no)")"
expect_eq "HARDEN.F3d …and not the row that only waits behind it" "no" \
  "$(printf '%s' "$CYC" | grep -qw T3 && echo yes || echo no)"
hard_plan "$SANDBOX/f3-bang.md" "" \
  '| T1 | 4 | build | a | implementor | — | 30 | REQ-x | lib/x.sh! | approval:plan, lib/y.sh | pending |' \
  '| T2 | 4 | build | b | implementor | — | 30 | REQ-x | lib/y.sh, lib/x.sh |  | pending |'
V="$(call units_validate "$SANDBOX/f3-bang.md")"; VRC="$(call_rc units_validate "$SANDBOX/f3-bang.md")"
CYC="$(printf '%s\n' "$V" | grep -F 'read cycle')"
expect_eq "HARDEN.F3e a cycle closed by an unmergeable hold is refused" "1" "$VRC"
expect_eq "HARDEN.F3f …naming both rows" "yes yes" \
  "$(printf '%s %s' "$(printf '%s' "$CYC" | grep -qw T1 && echo yes || echo no)" \
     "$(printf '%s' "$CYC" | grep -qw T2 && echo yes || echo no)")"
# No worktree column: an active row owes no tree there (§12), so the status is the one change.
sed 's/| approval:plan, lib\/b.sh | pending |/| approval:plan, lib\/b.sh | active |/' \
  "$SANDBOX/f3-reads.md" > "$SANDBOX/f3-active.md"
V="$(call units_validate "$SANDBOX/f3-active.md")"
expect_eq "HARDEN.F3g the same loop with one row already active is not refused as a cycle" "" \
  "$(printf '%s\n' "$V" | grep -F 'read cycle')"
expect_eq "HARDEN.F3h …while the fixture still carries the loop as edges both ways" "yes yes" \
  "$(printf '%s %s' "$(has_line "$(call units_edges "$SANDBOX/f3-active.md")" "T1${TAB}T2${TAB}lib/a.sh")" \
     "$(has_line "$(call units_edges "$SANDBOX/f3-active.md")" "T2${TAB}T1${TAB}lib/b.sh")")"
expect_eq "HARDEN.F3i an acyclic reads table still validates clean (READS fixture)" "0" \
  "$(call_rc units_validate "$SANDBOX/reads.md")"
# A ROW THAT WAITS ON ITSELF is a cycle of one (wave-26 T32; review 7 F5). Its group holds only
# itself, so the count of two or more never named it; it validated and was never ready.
cat > "$SANDBOX/f3-self.md" <<'SELF_EOF'
## SDLC State

current: 5

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | a, waiting on itself | implementor | T1 | 30 | REQ-x | lib/a.sh | pending |
| T2 | 4 | build | b | implementor | — | 30 | REQ-x | lib/b.sh | pending |
SELF_EOF
expect_eq "HARDEN.F3j precondition: the self-dependency is an edge from the row to itself" "yes" \
  "$(has_line "$(call units_edges "$SANDBOX/f3-self.md")" "T1${TAB}T1${TAB}T1")"
V="$(call units_validate "$SANDBOX/f3-self.md")"
expect_eq "HARDEN.F3j F5 a row that depends on itself is refused" "1" "$(call_rc units_validate "$SANDBOX/f3-self.md")"
expect_contains "HARDEN.F3k …as a cycle naming it" "T1: read cycle through T1" "$V"
expect_absent "HARDEN.F3l …and not the row beside it" "T2:" "$V"

# F5 — ONE BRACKET DOES NOT STOP THE PLAN. A `[` in a Files glob used to build a broken regex and
# abort the program: every verb exit 2, nothing ready. The matcher reads a bracket literally (the
# Files grammar globs with * and ? only), and the validator refuses the entry, naming the row.
hard_plan "$SANDBOX/f5.md" "" \
  '| T1 | 4 | build | a | implementor | — | 30 | REQ-x | tests/[ab*.sh |  | pending |' \
  '| T2 | 4 | build | b | implementor | — | 30 | REQ-x | lib/b.sh | approval:plan, tests/a.sh | pending |' \
  '| T3 | 4 | build | c, unrelated | implementor | — | 30 | REQ-x | lib/c.sh |  | pending |' \
  '| T4 | 4 | build | d | implementor | — | 30 | REQ-x | lib/d.sh | approval:plan, tests/[ab1.sh | pending |'
R="$(call units_ready "$SANDBOX/f5.md" 5)"; RRC="$(call_rc units_ready "$SANDBOX/f5.md" 5)"
expect_eq "HARDEN.F5 a bracket in a Files glob: units_ready exits 0" "0" "$RRC"
expect_eq "HARDEN.F5b …the unrelated row and the bracket row are ready" "yes yes" \
  "$(printf '%s %s' "$(has_line "$R" T3)" "$(has_line "$R" T1)")"
expect_eq "HARDEN.F5c …tests/a.sh is not what tests/[ab*.sh covers, read literally: T2 is ready" "yes" \
  "$(has_line "$R" T2)"
expect_eq "HARDEN.F5d …tests/[ab1.sh is, read literally: T4 waits on T1" "yes" \
  "$(has_line "$(call units_waiting "$SANDBOX/f5.md" 5)" "T4${TAB}tests/[ab1.sh${TAB}T1${TAB}pending")"
expect_eq "HARDEN.F5e units_waiting and units_edges exit 0 too" "0 0" \
  "$(call_rc units_waiting "$SANDBOX/f5.md" 5) $(call_rc units_edges "$SANDBOX/f5.md")"
V="$(call units_validate "$SANDBOX/f5.md")"; VRC="$(call_rc units_validate "$SANDBOX/f5.md")"
expect_eq "HARDEN.F5f the validator refuses the table" "1" "$VRC"
expect_eq "HARDEN.F5g …naming the Files entry against its row" "yes" \
  "$(printf '%s\n' "$V" | grep -F 'T1: Files entry tests/[ab*.sh' >/dev/null && echo yes || echo no)"
expect_eq "HARDEN.F5h …and the read against its row" "yes" \
  "$(printf '%s\n' "$V" | grep -F 'T4: read tests/[ab1.sh' >/dev/null && echo yes || echo no)"
expect_eq "HARDEN.F5i …and accuses neither clean row" "" \
  "$(printf '%s\n' "$V" | grep -E '^T(2|3):')"

# F7 — READINESS IS NOT QUADRATIC IN THE FILES PAIRS. A RELATION, never a clock: the review's
# generator at 120 rows, units_ready timed against units_rows on the same table in the same run,
# so the machine load sits on both sides. Measured before T35: 90-108; after: 3.5-7.1.
hard_now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
{ printf '## SDLC State\n\napproved-by: x\n\n## Tasks\n\n'
  printf '| id | step | kind | task | agent | deps | size | serves | Files | reads | status |\n|---|---|---|---|---|---|---|---|---|---|---|\n'
  i=1; while [ "$i" -le 120 ]; do
    files=""; for k in 1 2 3 4 5 6 7 8; do files="$files, payload/m$i/f$k.sh"; done
    printf '| T%s | 4 | build | t | - | — | S | s | %s, tests/t%s*.test.sh, docs/d%s/! | approval:plan, payload/m%s/f1.sh, tests/t%sx.test.sh, docs/d%s/a.md | pending |\n' \
      "$i" "${files#, }" "$i" "$i" "$((i + 1))" "$((i + 2))" "$((i + 3))"
    i=$((i + 1))
  done
  printf '| T121 | 5 | verify | floor | - | — | S | s | .bionic/docs/record/x.txt |  | pending |\n'; } > "$SANDBOX/f7.md"
t0="$(hard_now)"; NROWS="$(call units_rows "$SANDBOX/f7.md" | wc -l | tr -d ' ')"; t1="$(hard_now)"
F7R="$(call units_ready "$SANDBOX/f7.md" 5)"; t2="$(hard_now)"
# Every generated row reads what a neighbour writes, so nothing is ready: the table is live, and
# the timed call did the whole judgement, when the floor names its open writers.
expect_eq "HARDEN.F7 the 120-row table parses whole, and the floor waits on its open writers" "yes yes" \
  "$([ "$NROWS" -gt 100 ] && echo yes || echo no) $(has_line "$(call units_waiting "$SANDBOX/f7.md" 5)" "T121${TAB}head${TAB}T1${TAB}pending")"
expect_eq "HARDEN.F7a …and nothing is ready in it" "" "$F7R"
expect_eq "HARDEN.F7b units_ready costs under twenty-five parses of the same table" "yes" \
  "$(perl -e "print((($t2 - $t1) < 25 * ($t1 - $t0)) ? 'yes' : 'no')")"

# ============================================================
section "CHAIN — wave-26 T3: units_chain, the longest chain and the widest the plan can run (REQ-7, AC-7.1 lib half; D12)"
# ============================================================
# Pure over stdin: `N<TAB><id><TAB><minutes>` and `E<TAB><from><TAB><to>` lines in, the longest
# chain and the width out. It reads no plan, so every fixture here is the lines themselves.
# The fixtures are written with single spaces and turned to tabs by `tr`, which knows no
# column and so cannot agree with the reader by accident.
chain_tabs() { tr ' ' '\t'; }
# chain_run <ceiling> <file> — sets CHAIN_OUT and CALL_RC in THIS shell (a `$(call …)` would
# lose the status to its subshell and leave the last row'"'"'s behind).
chain_run() { call units_chain "$1" < "$2" > "$SANDBOX/.chain-out"; CHAIN_OUT="$(cat "$SANDBOX/.chain-out")"; }

# The wave-25 plan's `## Tasks` table (ids, `size`, `deps`), written out literally from
# .bionic/docs/plans/epic-23-bionic-tech-debt/wave-25-never-paused.plan.md at bc1516fc.
# That table carries fifteen rows; T15 (deps T1, T5; T8 waits for it) is the row that makes
# the chain 670 minutes through T15, where the same table without T15 gives 610 through T5, T8.
chain_tabs > "$SANDBOX/chain-w25.in" <<'CHAIN_W25_EOF'
N T1 60
N T2 90
N T3 120
N T4 150
N T5 75
N T6 75
N T7 40
N T8 120
N T9 60
N T10 45
N T11 40
N T12 120
N T13 30
N T14 30
N T15 60
E T1 T4
E T2 T4
E T3 T4
E T11 T4
E T4 T5
E T1 T6
E T4 T7
E T1 T8
E T2 T8
E T3 T8
E T4 T8
E T5 T8
E T6 T8
E T7 T8
E T12 T8
E T13 T8
E T14 T8
E T15 T8
E T8 T9
E T8 T10
E T9 T10
E T3 T11
E T4 T13
E T12 T13
E T4 T14
E T1 T15
E T5 T15
CHAIN_W25_EOF

chain_run 8 "$SANDBOX/chain-w25.in"; out="$CHAIN_OUT"
expect_eq "CHAIN.1 the wave-25 table: the longest chain runs through T15, 670 minutes, and the widest it can run is four" \
  "$(printf 'chain\tT3,T11,T4,T5,T15,T8,T9,T10\t670\nwidth\t4')" "$out"
expect_eq "CHAIN.1b …and the call succeeds" "0" "$CALL_RC"

# The plan's stated chain: the table before T15 joined it. Dropping T15's node and edges is
# a name-blind filter on the fixture above, so both sides share one specimen.
grep -v 'T15' "$SANDBOX/chain-w25.in" > "$SANDBOX/chain-w25-no15.in"
expect_eq "CHAIN.2 without T15 the chain is the 610-minute one: T3,T11,T4,T5,T8,T9,T10" \
  "chain	T3,T11,T4,T5,T8,T9,T10	610" "$(call units_chain 8 < "$SANDBOX/chain-w25-no15.in" | head -n 1)"

# WIDTH NEVER EXCEEDS THE CEILING: four nodes are ready at the start, so every ceiling below
# four is reached, and a ceiling above four is not.
for ceil in 1 2 3 4 5 8; do
  want="$ceil"; [ "$ceil" -gt 4 ] && want=4
  got="$(call units_chain "$ceil" < "$SANDBOX/chain-w25.in" | awk -F'\t' '$1 == "width" { print $2 }')"
  expect_eq "CHAIN.3 ceiling $ceil: width is $want" "$want" "$got"
done
expect_eq "CHAIN.3b the chain does not depend on the ceiling" \
  "chain	T3,T11,T4,T5,T15,T8,T9,T10	670" "$(call units_chain 1 < "$SANDBOX/chain-w25.in" | head -n 1)"

# A DIAMOND: A then B and C side by side, then D.
chain_tabs > "$SANDBOX/chain-diamond.in" <<'CHAIN_D_EOF'
N A 10
N B 20
N C 30
N D 5
E A B
E A C
E B D
E C D
CHAIN_D_EOF
expect_eq "CHAIN.4 a diamond: the chain takes the longer side, the width is the two sides" \
  "$(printf 'chain\tA,C,D\t45\nwidth\t2')" "$(call units_chain 4 < "$SANDBOX/chain-diamond.in")"
expect_eq "CHAIN.4b a ceiling of one runs the sides one after the other" \
  "width	1" "$(call units_chain 1 < "$SANDBOX/chain-diamond.in" | tail -n 1)"

# A TIE goes to the chain whose ids come first in input order.
chain_tabs > "$SANDBOX/chain-tie.in" <<'CHAIN_T_EOF'
N A 10
N C 30
N B 30
N D 5
E A B
E A C
E B D
E C D
CHAIN_T_EOF
expect_eq "CHAIN.5 two chains of equal minutes: the one through C, which comes first in the input, wins" \
  "chain	A,C,D	45" "$(call units_chain 4 < "$SANDBOX/chain-tie.in" | head -n 1)"

# NODES WITH NO EDGES: three of them, the chain is the largest alone, the first on a tie.
chain_tabs > "$SANDBOX/chain-free.in" <<'CHAIN_F_EOF'
N X 15
N Y 15
N Z 5
CHAIN_F_EOF
expect_eq "CHAIN.6 three free nodes, ceiling 5: the first of the equal largest is the chain, all three run at once" \
  "$(printf 'chain\tX\t15\nwidth\t3')" "$(call units_chain 5 < "$SANDBOX/chain-free.in")"
expect_eq "CHAIN.6b …and ceiling 2 holds the width to two" \
  "width	2" "$(call units_chain 2 < "$SANDBOX/chain-free.in" | tail -n 1)"

# REFUSALS: one line on stderr naming the cause, rc 2, nothing on stdout. Each refusal sits
# beside the same fixture made valid, which answers, so the empty readback is read off a
# call that runs.
chain_tabs > "$SANDBOX/chain-ok.in" <<'CHAIN_OK_EOF'
N A 10
N B 20
E A B
CHAIN_OK_EOF
expect_eq "CHAIN.7 control: the acyclic pair answers" \
  "$(printf 'chain\tA,B\t30\nwidth\t1')" "$(call units_chain 4 < "$SANDBOX/chain-ok.in")"

chain_tabs > "$SANDBOX/chain-cycle.in" <<'CHAIN_C_EOF'
N A 10
N B 20
E A B
E B A
CHAIN_C_EOF
chain_run 4 "$SANDBOX/chain-cycle.in"; out="$CHAIN_OUT"
expect_eq "CHAIN.8 a cycle is refused with status 2" "2" "$CALL_RC"
expect_empty "CHAIN.8b …printing nothing on stdout" "$out"
expect_eq "CHAIN.8c …and one line on stderr" "1" "$(nlines "$(cat "$SANDBOX/.err")")"
expect_regex "CHAIN.8d …that says cycle and names its members" 'cycle.*A.*B' "$(cat "$SANDBOX/.err")"

chain_tabs > "$SANDBOX/chain-self.in" <<'CHAIN_S_EOF'
N A 10
E A A
CHAIN_S_EOF
chain_run 4 "$SANDBOX/chain-self.in"
expect_eq "CHAIN.8e an edge from a node to itself is a cycle: status 2" "2" "$CALL_RC"

chain_tabs > "$SANDBOX/chain-unknown.in" <<'CHAIN_U_EOF'
N A 10
N B 20
E A B
E B Q9
CHAIN_U_EOF
chain_run 4 "$SANDBOX/chain-unknown.in"; out="$CHAIN_OUT"
expect_eq "CHAIN.9 an edge naming an unknown id is refused with status 2" "2" "$CALL_RC"
expect_empty "CHAIN.9b …printing nothing on stdout" "$out"
expect_eq "CHAIN.9c …and one line on stderr" "1" "$(nlines "$(cat "$SANDBOX/.err")")"
expect_contains "CHAIN.9d …that names the id" "Q9" "$(cat "$SANDBOX/.err")"

for bad in abc 1.5 -3 ""; do
  chain_tabs > "$SANDBOX/chain-bad.in" <<CHAIN_B_EOF
N A 10
N B $bad
E A B
CHAIN_B_EOF
  chain_run 4 "$SANDBOX/chain-bad.in"; out="$CHAIN_OUT"
  expect_eq "CHAIN.10 minutes '$bad' is refused with status 2" "2" "$CALL_RC"
  expect_empty "CHAIN.10b …printing nothing on stdout for '$bad'" "$out"
  expect_eq "CHAIN.10c …and one line on stderr for '$bad'" "1" "$(nlines "$(cat "$SANDBOX/.err")")"
  expect_contains "CHAIN.10d …that names the node B for '$bad'" "B" "$(cat "$SANDBOX/.err")"
done

# A node of zero minutes starts and ends at one instant, so it is never running for any
# length of time and is not in the width.
chain_tabs > "$SANDBOX/chain-zero.in" <<'CHAIN_Z_EOF'
N A 0
N B 10
N C 10
CHAIN_Z_EOF
chain_run 3 "$SANDBOX/chain-zero.in"
expect_eq "CHAIN.11 a zero-minute node is not counted in the width: two of the three run" \
  "$(printf 'chain\tB\t10\nwidth\t2')" "$CHAIN_OUT"
expect_eq "CHAIN.11b …and the call succeeds" "0" "$CALL_RC"

# An empty id is malformed, beside the same line with an id, which answers.
printf 'N\tA\t5\n' > "$SANDBOX/chain-idok.in"
chain_run 4 "$SANDBOX/chain-idok.in"
expect_eq "CHAIN.12 control: a node line with an id answers" \
  "$(printf 'chain\tA\t5\nwidth\t1')" "$CHAIN_OUT"
printf 'N\t\t5\n' > "$SANDBOX/chain-noid.in"
chain_run 4 "$SANDBOX/chain-noid.in"; out="$CHAIN_OUT"
expect_eq "CHAIN.12b a node line with an empty id is refused with status 2" "2" "$CALL_RC"
expect_empty "CHAIN.12c …printing nothing on stdout" "$out"
expect_contains "CHAIN.12d …and saying the node line is malformed" "malformed node line" "$(cat "$SANDBOX/.err")"

# ============================================================
section "FLOOR-HOLDS — wave-26 T52: only the rows the floor waits on hold a full run (review 14 B1, N4; ruling R1)"
# ============================================================
#
# units_floor_holds <plan> [<id>] -> `id<TAB>step<TAB>status` for each row the floor row waits on
# (its deps and its reads, judged by the ready set's own program) that has not landed and writes
# a tracked file (`writes_head`). A row downstream of the floor never holds it: through T5 the
# dispatch wall counted every open row, so the release, which waits on the floor, held the floor.
# SYNTHESIZED tables, in the review's shapes (V14-hold.sh).
hard_plan "$SANDBOX/fh-reads.md" "" \
  '| T1 | 4 | build | a | implementor | — | 30 | REQ-x | lib/a.sh | | active |' \
  '| T3 | 4 | test | t | implementor | — | 30 | REQ-x | tests/t.test.sh | | pending |' \
  '| T4 | 4 | build | notes | implementor | — | 30 | REQ-x | record/w/T4.md | | active |' \
  '| T2 | 5 | verify | floor | test-runner | — | 30 | REQ-x | .bionic/docs/record/w/floor.txt | | pending |' \
  '| T5 | 7 | doc | release | implementor | — | 30 | REQ-x | CHANGELOG.md | approval:release, head | pending |'
FH="$(call units_floor_holds "$SANDBOX/fh-reads.md" T2)"
expect_eq "FLOOR-HOLDS.1 the floor is held by the active build row it reads head from" "yes" \
  "$(has_line "$FH" "T1${TAB}4${TAB}active")"
expect_eq "FLOOR-HOLDS.1b …and by the step-4 test row that reads head and writes code (T35 F1)" "yes" \
  "$(has_line "$FH" "T3${TAB}4${TAB}pending")"
expect_eq "FLOOR-HOLDS.1c …never by the release, which reads head at a later step" "no" \
  "$(has_line "$FH" "T5${TAB}7${TAB}pending")"
expect_eq "FLOOR-HOLDS.1d …nor by a row whose only Files are record/… (writes_head says no)" "no" \
  "$(has_line "$FH" "T4${TAB}4${TAB}active")"
expect_eq "FLOOR-HOLDS.1e …and the call succeeds" "0" "$(call_rc units_floor_holds "$SANDBOX/fh-reads.md" T2)"
# NO ROW NAMED: the floor is every open verify or test row, the rows proof:floor names as its
# writers, so the answer is what they wait on together.
FH0="$(call units_floor_holds "$SANDBOX/fh-reads.md")"
expect_eq "FLOOR-HOLDS.2 with no row named, the open verify row stands for the floor: T1 holds it" "yes" \
  "$(has_line "$FH0" "T1${TAB}4${TAB}active")"
expect_eq "FLOOR-HOLDS.2b …and the release still does not" "no" "$(has_line "$FH0" "T5${TAB}7${TAB}pending")"
# A TABLE WITHOUT reads (this wave's own plan): the floor waits on its deps until they land.
{ printf '## SDLC State\n\ncurrent: 5\napproved-by: fixture 2026-10-03T00:00Z "approved"\n\n## Tasks\n\n'
  printf '| id | step | kind | task | agent | deps | size | serves | Files | status |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| T1 | 4 | build | a | x | — | 30 | R | lib/a.sh | landed |\n'
  printf '| T2 | 4 | build | b | x | — | 30 | R | lib/b.sh | landed |\n'
  printf '| T6 | 4 | build | n | x | — | 30 | R | record/w/T6.md | active |\n'
  printf '| T27 | 5 | verify | floor | x | T1, T2, T6 | 30 | R | .bionic/docs/record/w/floor.txt | pending |\n'
  printf '| T28 | 6 | review | final | x | T1, T2, T6 | 30 | R | .bionic/docs/record/w/review.md | pending |\n'
  printf '| T29 | 7 | doc | release | x | T27, T28 | 30 | R | CHANGELOG.md, tests/docs-pins.test.sh | pending |\n'
  printf '| T31 | 4 | build | c | x | — | 30 | R | lib/c.sh | active |\n'
  printf '| T30 | 5 | verify | other floor | x | T31 | 30 | R | .bionic/docs/record/w/floor2.txt | pending |\n'
} > "$SANDBOX/fh-wave.md"
expect_eq "FLOOR-HOLDS.3a control, same table: a floor that depends on the active T31 is held by it" \
  "T31${TAB}4${TAB}active" "$(call units_floor_holds "$SANDBOX/fh-wave.md" T30)"
FH="$(call units_floor_holds "$SANDBOX/fh-wave.md" T27)"
expect_eq "FLOOR-HOLDS.3 this wave's shape: every build row landed, the release pending on the floor — nothing holds it" \
  "" "$FH"
expect_eq "FLOOR-HOLDS.3b …and the call succeeds" "0" "$(call_rc units_floor_holds "$SANDBOX/fh-wave.md" T27)"
{ printf '## SDLC State\n\ncurrent: 5\napproved-by: fixture 2026-10-03T00:00Z "approved"\n\n## Tasks\n\n'
  printf '| id | step | kind | task | agent | deps | size | serves | Files | status |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| T1 | 4 | build | a | x | — | 30 | R | lib/a.sh | landed |\n'
  printf '| T2 | 4 | build | b | x | — | 30 | R | lib/b.sh | active |\n'
  printf '| T6 | 4 | build | n | x | — | 30 | R | record/w/T6.md | active |\n'
  printf '| T27 | 5 | verify | floor | x | T1, T2, T6 | 30 | R | .bionic/docs/record/w/floor.txt | pending |\n'
  printf '| T29 | 7 | doc | release | x | T27 | 30 | R | CHANGELOG.md | pending |\n'
} > "$SANDBOX/fh-wave2.md"
FH="$(call units_floor_holds "$SANDBOX/fh-wave2.md" T27)"
expect_eq "FLOOR-HOLDS.4 a build row the floor depends on, still active, holds it — and only it" \
  "T2${TAB}4${TAB}active" "$FH"

# N4: `approve` records only a name an OPEN row reads. A name read only by a landed or dropped
# row satisfies nothing, so it is not offered.
hard_plan "$SANDBOX/ap-names.md" "" \
  '| T1 | 4 | build | a | x | — | 30 | R | lib/a.sh | approval:landedonly | landed |' \
  '| T2 | 4 | build | b | x | — | 30 | R | lib/b.sh | approval:droppedonly | dropped |' \
  '| T3 | 7 | doc | c | x | — | 30 | R | CHANGELOG.md | live:approval:release | pending |' \
  '| T4 | 4 | build | d | x | — | 30 | R | lib/d.sh | approval:ship | active |'
AN="$(call units_approval_names "$SANDBOX/ap-names.md")"
expect_eq "APPROVAL-NAMES.1 the names open rows read are listed (pending live:, active)" "yes yes" \
  "$(has_line "$AN" release) $(has_line "$AN" ship)"
expect_eq "APPROVAL-NAMES.1b …and a name read only by a landed or dropped row is not" "no no" \
  "$(has_line "$AN" landedonly) $(has_line "$AN" droppedonly)"

# ============================================================
section "RUN-EDGES — wave-26 T62: the graph holds at a run's edges (critic 2, K2-F1 F3 F4 F5)"
# ============================================================
#
# The second critic's probes (record/wave-26-never-idle/critic-2-scheduling-and-proof.md), each
# turned into rows on the plan it ran. edges_plan writes a plan with the state lines given and the
# header given, then the rows.
edges_plan() {  # <file> <current> <state lines> <header> <rows...>
  local f="$1" cur="$2" st="$3" hd="$4" cols; shift 4
  cols="$(printf '%s\n' "$hd" | awk -F'|' '{ s = "|"; for (i = 2; i < NF; i++) s = s "---|"; print s }')"
  { printf '## SDLC State\n\ncurrent: %s\napproved-by: fixture 2026-10-04T10:00:00Z "approved"\n%s\n- T1: landed abc\n\n## Tasks\n\n%s\n%s\n' \
      "$cur" "$st" "$hd" "$cols"
    for r in "$@"; do printf '%s\n' "$r"; done; } > "$f"
}
E_LEG='| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status |'
E_RDS='| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |'
E_H=8d7216ce2835456ae38b03d6a7d30a50400cf30f
E_H2=1111111111111111111111111111111111111111
E_PROOFS="proved: kind=floor head=$E_H at=2026-10-04T11:00:00Z evidence=record/x/floor.log
proved: kind=review head=$E_H at=2026-10-04T11:05:00Z evidence=record/x/review-1.md"

# K2-F1 — A TABLE WITHOUT reads KEEPS 1.10 THREADING. Every plan written before 1.11 has no reads
# column, so no `head` read holds its floor; the only thing that did was the id task-add threaded
# into the deps of the open Step-5+ rows. A Step-4 row added mid-run is threaded into the frontier
# exactly as c81d865e did: the floor gets it, the integrate row that reaches it through the floor
# does not.
edges_plan "$SANDBOX/e1-leg.md" 5 "" "$E_LEG" \
  '| T1 | 4 | build | a | w-T1 | — | 10 | REQ-1 | lib/a.sh | — | — | landed |' \
  '| T2 | 5 | verify | floor | w-T2 | T1 | 10 | REQ-1 | .bionic/docs/record/x/T2.md | — | — | pending |' \
  '| T3 | 8 | integrate | merge | — | T2 | 10 | REQ-1 | — | — | — | pending |'
call units_add_row "$SANDBOX/e1-leg.md" T4 4 build 'late fix' w-T4 '—' 10 REQ-1 'lib/b.sh' > "$SANDBOX/e1-leg-add.md"
expect_eq "RUN-EDGES.F1 precondition: the add projects (exit 0) and the new row is in it" "0 yes" \
  "$CALL_RC $(has_line "$(grep '^| T4 ' "$SANDBOX/e1-leg-add.md")" '| T4 | 4 | build | late fix | w-T4 | — | 10 | REQ-1 | lib/b.sh | — | — | pending |')"
expect_eq "RUN-EDGES.F1a a mid-run build row on a table without reads is threaded into the floor's deps" \
  '| T2 | 5 | verify | floor | w-T2 | T1, T4 | 10 | REQ-1 | .bionic/docs/record/x/T2.md | — | — | pending |' \
  "$(grep '^| T2 ' "$SANDBOX/e1-leg-add.md")"
expect_eq "RUN-EDGES.F1b …and not into the integrate row, which reaches it through the floor (1.10's frontier)" \
  '| T3 | 8 | integrate | merge | — | T2 | 10 | REQ-1 | — | — | — | pending |' \
  "$(grep '^| T3 ' "$SANDBOX/e1-leg-add.md")"
expect_eq "RUN-EDGES.F1c at current: 5 the late build is ready and the floor is not (1.10 read T4 here)" "T4" \
  "$(call units_ready "$SANDBOX/e1-leg-add.md" 5)"
expect_eq "RUN-EDGES.F1d …so the full-run wall has the row to hold the run with" "T4${TAB}4${TAB}pending" \
  "$(call units_floor_holds "$SANDBOX/e1-leg-add.md" T2)"
expect_eq "RUN-EDGES.F1e …and the projection validates" "0" "$(call_rc units_validate "$SANDBOX/e1-leg-add.md")"
call units_add_row "$SANDBOX/e1-leg.md" T4 6 build 'a Step-6 row' w-T4 '—' 10 REQ-1 'lib/b.sh' > "$SANDBOX/e1-leg-add6.md"
expect_eq "RUN-EDGES.F1f a row at any other step threads nothing, as in 1.10 (the floor keeps T1)" \
  '| T2 | 5 | verify | floor | w-T2 | T1 | 10 | REQ-1 | .bionic/docs/record/x/T2.md | — | — | pending |' \
  "$(grep '^| T2 ' "$SANDBOX/e1-leg-add6.md")"
# A LANDED OR DROPPED ROW IS NOT THREADED, and a row that already names the id is not threaded twice.
edges_plan "$SANDBOX/e1-leg2.md" 5 "" "$E_LEG" \
  '| T1 | 4 | build | a | w-T1 | — | 10 | REQ-1 | lib/a.sh | — | — | landed |' \
  '| T2 | 5 | verify | floor | w-T2 | T1 | 10 | REQ-1 | .bionic/docs/record/x/T2.md | — | — | landed |' \
  '| T5 | 5 | verify | re-floor | w-T5 | T1, T4 | 10 | REQ-1 | .bionic/docs/record/x/T5.md | — | — | pending |' \
  '| T6 | 6 | review | final | w-T6 | T1 | 10 | REQ-1 | .bionic/docs/record/x/T6.md | — | — | pending |'
call units_add_row "$SANDBOX/e1-leg2.md" T4 4 build 'late fix' w-T4 '—' 10 REQ-1 'lib/b.sh' > "$SANDBOX/e1-leg2-add.md"
expect_eq "RUN-EDGES.F1g the open review that misses it is threaded, the landed floor and the row naming it already are not" \
  "T1, T4|T1|T1, T4" \
  "$(for r in T6 T2 T5; do grep "^| $r " "$SANDBOX/e1-leg2-add.md" | awk -F'|' '{ gsub(/^ +| +$/, "", $7); printf "%s|", $7 }'; done | sed 's/|$//')"
# THE CONTROL: the same plan WITH the reads column. The floor waits on what it reads (head), so
# nothing is appended to any row (D2; T59's ADD-READS pins the verb's half).
edges_plan "$SANDBOX/e1-rds.md" 5 "" "$E_RDS" \
  '| T1 | 4 | build | a | w-T1 | — | 10 | REQ-1 | lib/a.sh | — | — | landed | — |' \
  '| T2 | 5 | verify | floor | w-T2 | — | 10 | REQ-1 | .bionic/docs/record/x/T2.md | — | — | pending | — |' \
  '| T3 | 8 | integrate | merge | — | — | 10 | REQ-1 | — | — | — | pending | — |'
call units_add_row "$SANDBOX/e1-rds.md" T4 4 build 'late fix' w-T4 '—' 10 REQ-1 'lib/b.sh' > "$SANDBOX/e1-rds-add.md"
expect_eq "RUN-EDGES.F1h in a table with reads every row already there is byte-identical after the add" \
  "$(grep '^| T[0-9]' "$SANDBOX/e1-rds.md")" "$(grep '^| T[0-9]' "$SANDBOX/e1-rds-add.md" | grep -v '^| T4 ')"
expect_eq "RUN-EDGES.F1i …and its floor is held by the late build through head all the same" "T4${TAB}4${TAB}pending" \
  "$(call units_floor_holds "$SANDBOX/e1-rds-add.md" T2)"

# K2-F3 — THE RELEASE READS ITS APPROVAL. In a reads table a doc row at Step 7 or later is the
# release (the hold a table without the column keeps names it so), and D3 says it reads
# approval:release. The validator refuses one that names no approval, and readiness never offers
# one that slipped past it (a hand edit) before approved: release exists.
edges_plan "$SANDBOX/e3.md" 4 "" "$E_RDS" \
  '| T1 | 4 | build | a | w-T1 | — | 10 | REQ-1 | lib/a.sh | — | — | landed | — |' \
  '| T2 | 5 | verify | floor | w-T2 | — | 10 | REQ-1 | .bionic/docs/record/x/T2.md | — | — | pending | — |' \
  '| T3 | 7 | doc | release 1.2.0: CHANGELOG, version | w-T3 | — | 10 | REQ-1 | CHANGELOG.md, plugin.json | — | — | pending | — |' \
  '| T4 | 8 | integrate | merge | — | — | 10 | REQ-1 | — | — | — | pending | — |'
expect_eq "RUN-EDGES.F3a a Step-7 doc row with an empty reads cell is refused, naming the read to write" \
  "T3: a doc row at step 7 or later is the release and must read the approval it waits for; add approval:release to its reads (approval:plan for a document that needs no release)" \
  "$(call units_validate "$SANDBOX/e3.md")"
expect_eq "RUN-EDGES.F3a2 …exit 1" "1" "$(call_rc units_validate "$SANDBOX/e3.md")"
expect_eq "RUN-EDGES.F3b readiness at current: 4 offers the floor and never the release (the probe read T2 T3)" "T2" \
  "$(call units_ready "$SANDBOX/e3.md" 4)"
expect_eq "RUN-EDGES.F3c …which waits for approval:release" "yes" \
  "$(has_line "$(call units_waiting "$SANDBOX/e3.md" 4)" "T3${TAB}approval:release${TAB}-${TAB}-")"
sed '/^| T3 /s/| pending | — |$/| pending | head |/' "$SANDBOX/e3.md" > "$SANDBOX/e3-head.md"
expect_eq "RUN-EDGES.F3d a release whose reads name no approval (head alone) is refused the same way" "yes" \
  "$(has_line "$(call units_validate "$SANDBOX/e3-head.md")" "T3: a doc row at step 7 or later is the release and must read the approval it waits for; add approval:release to its reads (approval:plan for a document that needs no release)")"
sed '/^| T3 /s/| pending | — |$/| pending | approval:release |/' "$SANDBOX/e3.md" > "$SANDBOX/e3-ok.md"
expect_eq "RUN-EDGES.F3e the release that reads approval:release validates" "0" "$(call_rc units_validate "$SANDBOX/e3-ok.md")"
awk '{ print } /^approved-by:/ { print "approved: release by fixture 2026-10-04T12:00:00Z \"ship it\"" }' "$SANDBOX/e3.md" > "$SANDBOX/e3-appr.md"
expect_eq "RUN-EDGES.F3f once approved: release is written the release is ready" "yes" \
  "$(has_line "$(call units_ready "$SANDBOX/e3-appr.md" 4)" T3)"
# A PLAIN DOC ROW WORKS AS TODAY: on its kind default before Step 7, or reading approval:plan at
# Step 7 (HOLD.1), it validates and is ready.
edges_plan "$SANDBOX/e3-plain.md" 4 "" "$E_RDS" \
  '| T1 | 4 | build | a | w-T1 | — | 10 | REQ-1 | lib/a.sh | — | — | landed | — |' \
  '| T2 | 4 | doc | the guide | w-T2 | — | 10 | REQ-1 | skills/x/SKILL.md | — | — | pending | — |' \
  '| T3 | 7 | doc | the notes | w-T3 | — | 10 | REQ-1 | .bionic/docs/record/x/notes.md | — | — | pending | approval:plan |'
expect_eq "RUN-EDGES.F3g a plain doc row on its default and a Step-7 notes row reading approval:plan validate" "0" \
  "$(call_rc units_validate "$SANDBOX/e3-plain.md")"
expect_eq "RUN-EDGES.F3h …and both are ready at current: 4" "$(printf 'T2\nT3')" "$(call units_ready "$SANDBOX/e3-plain.md" 4)"

# K2-F4 — THE END OF A RUN ON DEFAULTS. The live review row went back to pending on the last
# review proof and nothing landed after it; it will write no newer proof, so integrate's
# proof:review does not wait on it. Every row reads its kind default.
edges_plan "$SANDBOX/e4.md" 8 "$E_PROOFS" "$E_RDS" \
  '| T1 | 4 | build | a | w-T1 | — | 10 | REQ-1 | lib/a.sh | — | — | landed | — |' \
  '| T2 | 6 | review | review each landing | — | — | 10 | REQ-1 | .bionic/docs/record/x/review-1.md | — | — | pending | — |' \
  '| T5 | 5 | verify | floor | w-T5 | — | 10 | REQ-1 | .bionic/docs/record/x/floor.log | — | — | landed | — |' \
  '| T3 | 8 | integrate | merge | — | — | 10 | REQ-1 | — | — | — | pending | — |' \
  '| T4 | 9 | close | close | — | — | 10 | REQ-1 | — | — | — | pending | — |'
floor_at_head "$SANDBOX/e4.md" "$FLOOR_REPO/e4.md"
# REWRITTEN BY wave-27 T14 (D3): the facts state handed in covered, as the tick hands it when the
# readings hold at the head (§INTEGRATE-JUDGE below drives the other answers).
expect_eq "RUN-EDGES.F4a at the head both proofs name, integrate is ready (the probe read nothing)" "T3" \
  "$(UNITS_FACTS_STATE=covered live_call "$E_H" units_ready "$FLOOR_REPO/e4.md" 8)"
E4W="$(live_call "$E_H" units_waiting "$SANDBOX/e4.md" 8)"
expect_eq "RUN-EDGES.F4b …the idle review row is no writer of proof:review" "no" \
  "$(has_line "$E4W" "T3${TAB}proof:review${TAB}T2${TAB}pending")"
expect_eq "RUN-EDGES.F4b2 …while the waiting extractor reads real lines: the review waits on the world" "yes" \
  "$(has_line "$E4W" "T2${TAB}live:head: nothing landed past the review proof at ${E_H:0:12}${TAB}-${TAB}-")"
expect_eq "RUN-EDGES.F4c past the proof (something landed), the review is ready and integrate waits on it" \
  "T2|yes" \
  "$(live_call "$E_H2" units_ready "$SANDBOX/e4.md" 8)|$(has_line "$(live_call "$E_H2" units_waiting "$SANDBOX/e4.md" 8)" "T3${TAB}proof:review${TAB}T2${TAB}pending")"
expect_eq "RUN-EDGES.F4d with the head unknown, the review may still write: integrate waits on it" \
  "yes" "$(has_line "$(live_call "" units_waiting "$SANDBOX/e4.md" 8)" "T3${TAB}proof:review${TAB}T2${TAB}pending")"

# K2-F5 — INTEGRATE WAITS FOR AN OPEN BUILD. Its default reads head (proof:floor, proof:review,
# head), so a late fix still active holds the merge, and the WAIT line names it.
edges_plan "$SANDBOX/e5.md" 8 "$E_PROOFS" "$E_RDS" \
  '| T1 | 4 | build | a | w-T1 | — | 10 | REQ-1 | lib/a.sh | — | — | landed | — |' \
  '| T2 | 6 | review | final review | w-T2 | — | 10 | REQ-1 | .bionic/docs/record/x/review-1.md | — | — | landed | — |' \
  '| T5 | 5 | verify | floor | w-T5 | — | 10 | REQ-1 | .bionic/docs/record/x/floor.log | — | — | landed | — |' \
  '| T6 | 6 | build | late fix from the review | w-T6 | — | 10 | REQ-1 | lib/a.sh | .worktrees/T6 | abcdef12 | active | — |' \
  '| T3 | 8 | integrate | merge to main | — | — | 10 | REQ-1 | — | — | — | pending | — |'
expect_eq "RUN-EDGES.F5a a late build active: nothing is ready at current: 8 (the probe read T3)" "" \
  "$(live_call "$E_H" units_ready "$SANDBOX/e5.md" 8)"
expect_eq "RUN-EDGES.F5b …integrate waits on head, written by the build" "yes" \
  "$(has_line "$(live_call "$E_H" units_waiting "$SANDBOX/e5.md" 8)" "T3${TAB}head${TAB}T6${TAB}active")"
sed '/^| T6 /s/| active | — |$/| landed | — |/' "$SANDBOX/e5.md" > "$SANDBOX/e5-landed.md"
floor_at_head "$SANDBOX/e5-landed.md" "$FLOOR_REPO/e5-landed.md"
expect_eq "RUN-EDGES.F5c the build landed and both proofs at the head: integrate is ready (facts handed in covered, T14)" "T3" \
  "$(UNITS_FACTS_STATE=covered live_call "$E_H" units_ready "$FLOOR_REPO/e5-landed.md" 8)"

# ============================================================
section "§FLOOR-STANDS — integrate waits while the floor is not proved: one whole run, and every commit after it proved by the runs recorded at it (wave-26 T64; REQ-3 AC-3.3, AC-3.4; wave-31 T25: REQ-4 AC-4.1, REQ-13 AC-13.4; D3)"
# ============================================================
#
# Through T63 a `proof:floor` read was satisfied by ANY `proved: kind=floor` line, whatever its
# head: a new file under a directory no suite names landed with no suite run (a tree with no stamp
# lands, by design), integrate read ready, and the release went out on a change no suite had read.
# The read now stands only while lib/proof.sh `proof_state` answers `covered`: the floor proof
# names the head, or every commit since it is proved by the runs recorded at it (wave-31 T25, D3).
# On `uncovered`, or a state that cannot be computed, the row waits, and `units_waiting` says what
# is lacking and names the way out (the lacking suites run, or a whole run recorded with
# `proof-add floor`).
#
# THE FIXTURE IS A REAL REPOSITORY on `wave/99-fs` with five suites. Every floor proof line is
# written by the product: `proof_line` and `proof_add_line` (lib/proof.sh, the pair `proof-add`
# writes through), with the head the checkout is at; session-poker §54 drives the verb itself on a
# real full run. The suite runs are SYNTHESIZED stamps in `booked.sh`'s documented shape
# (`stamp/v1|head=|dirty=|rc=|at=|suites=|cmd=`), appended to the checkout's git dir where the shim
# writes them; session-poker §54 and §72 write them with the real shim. A `git` shim on PATH counts
# the walk's one call (`git log --first-parent --reverse`): the cost rows read the count. The plan
# reads integrate's kind default (`proof:floor, proof:review, head`).
FS_REPO="$SANDBOX/fs-repo"
FS_COUNT="$SANDBOX/fs-walk.count"
FS_SHIM="$SANDBOX/fs-git-shim"
FS_PLAN="$FS_REPO/.bionic/docs/plans/epic-99/wave-99-fs.plan.md"
mkdir -p "$FS_SHIM"
{
  printf '#!/bin/bash\n'
  printf 'case " $* " in *" --first-parent --reverse "*) printf "x\\n" >> "%s" ;; esac\n' "$FS_COUNT"
  printf 'exec %s "$@"\n' "$(command -v git)"
} > "$FS_SHIM/git"
chmod +x "$FS_SHIM/git"
fs_git() { git -C "$FS_REPO" -c user.name=fixture -c user.email=fixture@example.invalid "$@"; }
fs_commit() {  # <path> <content> -> one commit on the checkout's branch
  mkdir -p "$(dirname "$FS_REPO/$1")"; printf '%s\n' "$2" > "$FS_REPO/$1"
  fs_git add "$1" && fs_git commit -qm "change $1"
}
fs_stamp() {  # <suite> <rc> <at> -> one stamp at the checkout's head, clean, in the shim's shape and place
  printf 'stamp/v1|head=%s|dirty=0|rc=%s|at=%s|suites=%s|cmd=bash tests/%s\n' \
    "$(fs_git rev-parse HEAD)" "$2" "$3" "$1" "$1" >> "$(fs_git rev-parse --absolute-git-dir)/bionic-stamps"
}
mkdir -p "$FS_REPO/tests" "$FS_REPO/lib" "$(dirname "$FS_PLAN")"
fs_git init -q 2>/dev/null; fs_git checkout -q -b wave/99-fs 2>/dev/null
for s in a b c d e; do printf '#!/bin/bash\n' > "$FS_REPO/tests/$s.test.sh"; done
printf 'one\n' > "$FS_REPO/lib/one.sh"
printf '.bionic/\n' > "$FS_REPO/.gitignore"
fs_git add .gitignore tests lib && fs_git commit -qm base
# fs_plan <current> <T3 status> -> the plan, no proof lines yet
fs_plan() {
  { printf '## SDLC State\n\ncurrent: %s\nworking-branch: wave/99-fs\napproved-by: fixture 2026-10-04T10:00:00Z "approved"\n\n' "$1"
    printf '## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | reads | status |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | a | implementor | — | 30 | REQ-x | lib/one.sh |  | landed |\n'
    printf '| T5 | 5 | verify | the floor | test-runner | — | 30 | REQ-x | .bionic/docs/record/fs/floor.txt |  | landed |\n'
    printf '| T2 | 6 | review | the review | critic | — | 30 | REQ-x | .bionic/docs/record/fs/review.md |  | landed |\n'
    printf '| T3 | 8 | integrate | merge to main | — | — | 10 | REQ-x | — |  | %s |\n' "$2"
  } > "$FS_PLAN"
}
# fs_prove <kind> -> a proof line at the checkout's head, written by the product's writer pair
fs_prove() {
  local h out
  h="$(fs_git rev-parse HEAD)"
  out="$(call proof_add_line "$FS_PLAN" "$(call proof_line "$1" "$h" 2026-10-04T12:00:00Z "record/fs/$1.txt")")" \
    && printf '%s\n' "$out" > "$FS_PLAN"
}
fs_count() { awk 'END { print NR + 0 }' "$FS_COUNT" 2>/dev/null; }
fs_why() {  # -> integrate's proof:floor wait reason, or nothing
  call units_waiting "$FS_PLAN" 8 | awk -F'\t' '$1 == "T3" && index($2, "proof:floor") == 1 { print $2 }'
}
FS_LEAD="proof:floor: the floor is one whole run plus each later commit proved; past the proof at"
FS_OUT="; run what it lacks, or a whole run on this head, and proof-add floor"
# THE REVIEW HALF IS HANDED IN COVERED (wave-27 T14; D3). integrate's proof:review is met only by
# the facts state the tick hands in (UNITS_FACTS_STATE); every row here is about the floor, so the
# state is the one the tick hands when the readings hold. §INTEGRATE-JUDGE drives the others.
export UNITS_FACTS_STATE=covered
: > "$FS_COUNT"
fs_plan 8 pending; fs_prove floor; fs_prove review
FS_H0="$(fs_git rev-parse HEAD)"
expect_eq "FS.0 precondition: the product wrote a floor proof at the working head" "$FS_H0" "$(call proof_last "$FS_PLAN" floor)"
expect_eq "FS.0b precondition: proof_state reads the plan's own tree: covered" "covered" \
  "$(call proof_state "$FS_PLAN" "$FS_REPO" | cut -f1)"
expect_eq "FS.1 covered: the proof is at the head, integrate is ready" "T3" "$(PATH="$FS_SHIM:$PATH" call units_ready "$FS_PLAN" 8)"
expect_eq "FS.1b …and a proof at the head walks no commit" "0" "$(fs_count)"

# AC-13.4: A COMMIT PAST THE FLOOR IS PROVED BY THE RUNS RECORDED AT IT, and by nothing predicted.
fs_commit lib/one.sh 'one, changed'
FS_X1="$(fs_git rev-parse HEAD)"
expect_eq "FS.2 a commit past the floor proof with no run recorded at it: integrate is NOT ready" "" "$(call units_ready "$FS_PLAN" 8)"
expect_eq "FS.2b …and its wait names the commit, what it lacks and the way out" \
  "${FS_LEAD} ${FS_H0:0:12}, commit ${FS_X1:0:12} (no landing row) is not proved: no suite run is recorded at it${FS_OUT}" "$(fs_why)"
fs_stamp a.test.sh 0 2026-10-04T12:01:00Z
expect_eq "FS.2c AC-3.3 AC-13.4 a green run recorded at it: the floor stands, integrate is ready" "T3" "$(call units_ready "$FS_PLAN" 8)"
expect_eq "FS.2d …and no wait is told for it" "" "$(fs_why)"

# AC-3.4, THE CRITERION'S OWN PLANT: a new file under a directory no suite names, no suite run.
fs_commit newdir/x.sh 'new'
FS_X2="$(fs_git rev-parse HEAD)"
expect_eq "FS.3 AC-3.4 a new file under a directory no suite names: integrate is NOT ready" "" "$(call units_ready "$FS_PLAN" 8)"
expect_eq "FS.3b …and its wait names that commit, not the proved one before it" \
  "${FS_LEAD} ${FS_H0:0:12}, commit ${FS_X2:0:12} (no landing row) is not proved: no suite run is recorded at it${FS_OUT}" \
  "$(fs_why)"
expect_eq "FS.3c …while the extractor reads a real line: the review proof is no wait (paired positive)" "" \
  "$(call units_waiting "$FS_PLAN" 8 | awk -F'\t' '$1 == "T3" && index($2, "proof:review") == 1')"
expect_eq "FS.3d units_held names no hold for it either: it waits on a read, not on the world" "" \
  "$(call units_held "$FS_PLAN" 8)"
expect_eq "FS.3e a live:proof:floor read is a read of what exists, and is not judged by the state" "yes" \
  "$(sed 's/^| T3 | 8 | integrate | merge to main | — | — | 10 | REQ-x | — |  |/| T3 | 6 | review | r | critic | — | 10 | REQ-x | .bionic\/docs\/record\/fs\/r2.md | live:proof:floor |/' "$FS_PLAN" > "$FS_REPO/.bionic/live.md"; has_line "$(call units_ready "$FS_REPO/.bionic/live.md" 8)" T3)"
fs_prove floor
FS_H1="$(fs_git rev-parse HEAD)"
expect_eq "FS.4 the way out: a floor proof at the new head and integrate is ready again" "T3" "$(call units_ready "$FS_PLAN" 8)"

# A RED RUN RECORDED AT A COMMIT: the newest run at it decides.
fs_commit lib/one.sh 'one, changed again'
FS_X3="$(fs_git rev-parse HEAD)"
fs_stamp b.test.sh 1 2026-10-04T12:02:00Z
expect_eq "FS.5 a commit whose only recorded run is red: integrate waits" "" "$(call units_ready "$FS_PLAN" 8)"
expect_contains "FS.5b …saying which suite is red where, from the newest floor proof" \
  "${FS_LEAD} ${FS_H1:0:12}, commit ${FS_X3:0:12} (no landing row) is not proved: b.test.sh is red at ${FS_X3:0:12}" "$(fs_why)"
fs_stamp b.test.sh 0 2026-10-04T12:03:00Z
expect_eq "FS.5c …and a newer green run of it releases it" "T3" "$(call units_ready "$FS_PLAN" 8)"

# A MERGE OF WORK FROM OUTSIDE THE RUN: a first-parent commit no landing names, nothing run at it.
FS_H2="$(fs_git rev-parse HEAD)"
fs_git checkout -q -b other-work 2>/dev/null; fs_commit lib/one.sh 'one, from outside'
fs_git checkout -q wave/99-fs 2>/dev/null; fs_git merge -q --no-ff -m 'merge other-work' other-work 2>/dev/null
FS_M="$(fs_git rev-parse HEAD)"
expect_eq "FS.6 a merge from outside the run: integrate waits" "" "$(call units_ready "$FS_PLAN" 8)"
expect_contains "FS.6b …naming the merge, at which no run is recorded" \
  "commit ${FS_M:0:12} (no landing row) is not proved: no suite run is recorded at it" "$(fs_why)"
fs_prove floor
expect_eq "FS.6c …and a floor proof at the merge releases it" "T3" "$(call units_ready "$FS_PLAN" 8)"

# THE COST. One proof_state per answer that turns on it, once per memoised command, and none when
# no answer does. The walk's one git call is what the shim counts.
FS_H3="$(fs_git rev-parse HEAD)"
fs_commit lib/one.sh 'one, once more'
: > "$FS_COUNT"
PATH="$FS_SHIM:$PATH" call units_ready "$FS_PLAN" 8 >/dev/null
FS_ONE="$(fs_count)"
expect_eq "FS.7 precondition: one answer that turns on the floor walks the commits once" "1" "$FS_ONE"
printf '. "%s" >/dev/null 2>&1\nfs3() { units_ready "$1" 8; units_waiting "$1" 8; units_held "$1" 8; }\nunits_memoised "$1" fs3 "$1" >/dev/null\n' \
  "$LIB" > "$SANDBOX/fs-three.sh"
: > "$FS_COUNT"; PATH="$FS_SHIM:$PATH" bash "$SANDBOX/fs-three.sh" "$FS_PLAN"
expect_eq "FS.7b three questions inside one memoised command walk once between them" "$FS_ONE" "$(fs_count)"
: > "$FS_COUNT"
PATH="$FS_SHIM:$PATH" call units_ready "$FS_PLAN" 8 >/dev/null; PATH="$FS_SHIM:$PATH" call units_waiting "$FS_PLAN" 8 >/dev/null
PATH="$FS_SHIM:$PATH" call units_held "$FS_PLAN" 8 >/dev/null
expect_eq "FS.7c …the differential: the same three asked bare walk three times" "$((FS_ONE * 3))" "$(fs_count)"
mkdir -p "$SANDBOX/fs-tmp"
printf '. "%s" >/dev/null 2>&1\nfsin() { units_ready "$1" 8 >/dev/null; ls "$TMPDIR"; }\nunits_memoised "$1" fsin "$1"\n' \
  "$LIB" > "$SANDBOX/fs-inside.sh"
expect_contains "FS.7d inside the memoised command the state is kept in one file" "bionic-units-floor-" \
  "$(TMPDIR="$SANDBOX/fs-tmp" bash "$SANDBOX/fs-inside.sh" "$FS_PLAN")"
expect_eq "FS.7e …which the command removes when it returns" "" "$(ls "$SANDBOX/fs-tmp")"
fs_plan 7 pending; fs_prove floor; fs_prove review
fs_commit newdir/y.sh 'held'
: > "$FS_COUNT"
FS_W7="$(PATH="$FS_SHIM:$PATH" call units_waiting "$FS_PLAN" 7)"
expect_eq "FS.8 integrate held for its step (current: 7): the wait is the step" "yes" "$(has_line "$FS_W7" "T3${TAB}step:8${TAB}-${TAB}-")"
expect_eq "FS.8b …the state is not asked for a row held for its step" "0" "$(fs_count)"
fs_plan 8 landed; fs_prove floor; fs_prove review
fs_commit newdir/z.sh 'after the merge'
: > "$FS_COUNT"
expect_eq "FS.9 integrate landed: nothing is ready" "" "$(PATH="$FS_SHIM:$PATH" call units_ready "$FS_PLAN" 8)"
expect_eq "FS.9b …and with no open row reading proof:floor the state is not asked" "0" "$(fs_count)"
fs_plan 8 pending; fs_prove floor; fs_prove review
FS_H4="$(fs_git rev-parse HEAD)"
fs_commit newdir/w.sh 'pending again'
FS_X4="$(fs_git rev-parse HEAD)"
: > "$FS_COUNT"
PATH="$FS_SHIM:$PATH" call units_edges "$FS_PLAN" >/dev/null
expect_eq "FS.9c the edges never turn on the state, and do not ask it" "0" "$(fs_count)"
PATH="$FS_SHIM:$PATH" call proof_state "$FS_PLAN" "$FS_REPO" >/dev/null
FS_PS="$(fs_count)"
expect_true "FS.9d precondition: one proof_state over this change walks the commits (the counter reads real calls)" \
  test "$FS_PS" -gt 0
: > "$FS_COUNT"
PATH="$FS_SHIM:$PATH" call units_ready "$FS_PLAN" 8 >/dev/null
expect_eq "FS.9e …and the ready set over the same plan asks the state once: as many walks as one proof_state" \
  "$FS_PS" "$(fs_count)"

# THE STATE'S WORDS: covered or uncovered, and the reason names what is lacking (A-orch-23).
expect_eq "FS.10 proof_state's first field over an unproved commit is uncovered" "uncovered" \
  "$(call proof_state "$FS_PLAN" "$FS_REPO" | cut -f1)"
expect_eq "FS.11 …and integrate's wait carries the reason: the commit, and that no run is recorded at it" \
  "${FS_LEAD} ${FS_H4:0:12}, commit ${FS_X4:0:12} (no landing row) is not proved: no suite run is recorded at it${FS_OUT}" \
  "$(fs_why)"
fs_prove floor
expect_eq "FS.11b …and a floor proof at the head walks nothing: covered, ready" "T3" "$(call units_ready "$FS_PLAN" 8)"

# PLAN SHAPES THAT WERE READY BEFORE: each now says what to do.
sed 's/^working-branch: wave\/99-fs$//' "$FS_PLAN" > "$FS_REPO/.bionic/nobranch.md"
expect_contains "FS.12 a plan naming no working branch: the wait says so" ", the plan names no working-branch;" \
  "$(call units_waiting "$FS_REPO/.bionic/nobranch.md" 8 | awk -F'\t' '$1 == "T3" { print $2 }')"
awk '/^proved: kind=floor / { sub(/head=[0-9a-f]+/, "head=0123456789abcdef0123456789abcdef01234567") } { print }' \
  "$FS_PLAN" > "$FS_REPO/.bionic/foreign.md"
expect_contains "FS.13 a floor proof whose head is no commit here: the wait says so" ", the proved head is not a commit here;" \
  "$(call units_waiting "$FS_REPO/.bionic/foreign.md" 8 | awk -F'\t' '$1 == "T3" { print $2 }')"
fs_git checkout -q --detach 2>/dev/null
expect_contains "FS.14 a detached checkout: no checkout holds the working branch, and the wait says so" \
  ", no checkout holds the working branch wave/99-fs;" "$(fs_why)"
fs_git checkout -q wave/99-fs 2>/dev/null
expect_eq "FS.14b …and back on the branch, the floor proof at its head stands" "T3" "$(call units_ready "$FS_PLAN" 8)"

unset UNITS_FACTS_STATE

# ============================================================
section "§INTEGRATE-JUDGE — integrate's proof:review is met only by the judge's covered (wave-27 T14; REQ-2 AC-2.3 AC-2.4, D3; A-orch-40)"
# ============================================================
# Through T13 the read was met by any `proved: kind=review` line, a `result=fail` reading among
# them (A-orch-40). The tick now asks lib/proof.sh `facts_state` once and hands the answer in
# through UNITS_FACTS_STATE, as it hands the floor state in: `covered`, or the owed lines that do
# not hold. Only `covered` meets the read; anything else is a wait naming the answer, and an answer
# not handed in (the stop wall, the card, the dispatch wall) is a wait saying so.
# The plan is §FLOOR-STANDS's, at a head the floor proof names (covered), with one reading of the
# product's writer whose result is fail.
fs_plan 8 pending; fs_prove floor
IJ_H="$(fs_git rev-parse HEAD)"
out="$(call proof_add_line "$FS_PLAN" "$(call proof_line review "$IJ_H" 2026-10-04T12:00:00Z record/fs/structure.md structure w-read fail piece)")" \
  && printf '%s\n' "$out" > "$FS_PLAN"
ij_why() {  # -> integrate's proof:review wait, or nothing
  awk -F'\t' '$1 == "T3" && index($2, "proof:review") == 1 { print $2 }'
}
expect_eq "IJ.0 precondition: the plan's only review line is a result=fail reading" "1" \
  "$(/usr/bin/grep -c 'kind=review .* result=fail ' "$FS_PLAN" | tr -d ' ')"
expect_eq "IJ.0b precondition: the floor holds at the head (proof_state covered)" "covered" \
  "$(call proof_state "$FS_PLAN" "$FS_REPO" | cut -f1)"
IJ_FAILING="review structure bionic:critic piece failing record/fs/structure.md"
expect_eq "IJ.1 A-orch-40 a failing reading handed in as the facts state: integrate is NOT ready" "" \
  "$(UNITS_FACTS_STATE="$IJ_FAILING" call units_ready "$FS_PLAN" 8)"
expect_eq "IJ.1b …and its wait names the judge's answer" \
  "proof:review: the facts the run owes do not hold (facts_state): $IJ_FAILING" \
  "$(UNITS_FACTS_STATE="$IJ_FAILING" call units_waiting "$FS_PLAN" 8 | ij_why)"
expect_eq "IJ.2 with no facts state handed in, the review line alone does not meet it: integrate waits" "" \
  "$(call units_ready "$FS_PLAN" 8)"
expect_eq "IJ.2b …saying the facts are not known here" \
  "proof:review: the facts the run owes are judged by the tick (facts_state) and are not known here" \
  "$(call units_waiting "$FS_PLAN" 8 | ij_why)"
expect_eq "IJ.3 the judge's covered handed in: integrate is ready" "T3" \
  "$(UNITS_FACTS_STATE=covered call units_ready "$FS_PLAN" 8)"
expect_eq "IJ.3b …and nothing is waited on for proof:review (the extractor read IJ.1b's line on the same plan)" "" \
  "$(UNITS_FACTS_STATE=covered call units_waiting "$FS_PLAN" 8 | ij_why)"


# ---------------------------------------------------------------------------
section "§STEP-FIELD — wave-28 T8: units_step_fields --replace writes or replaces one field of a step block (REQ-3 AC-3.5; D17)"
# ---------------------------------------------------------------------------
# `units_step_fields <plan> <N> <key=value>…` fills what a block lacks and never rewrites what is there
# (the `current 4` fill). `--replace` is the mode `session-poker.sh step-field` writes through: a key the
# block has is REPLACED where it stands (one line, its place kept), a key it lacks is written after the
# block's last line, and the rest of the plan is the same bytes. Exit 1 no `Step N:` line · 4 a value with
# a line break · 5 a key the step line itself carries (the gate reads it before any indented line, so a
# second line could not win and a rewrite would be the step-line verb's). FIXTURE FIDELITY: the block is the
# gate's own grammar (walls.sh `extract_continuation`): the indented lines under `- Step N:`.
SF_PLAN="$SANDBOX/sf.plan.md"
sf_plan() {
  { printf '# plan\n\n## SDLC State\n\ncurrent: 5\n\n'
    printf -- '- Step 4: opened\n  worktree: .\n  branch: wave/x\n'
    printf -- '- Step 5: floor\n  cmd: bash tests/run.sh\n\n  pass: 3\n  total: 4\n  output: record/x.log\n'
    printf -- '- Step 6: pass: 9\n'
    printf -- '- T1: landed\n\n## Notes\n\nStep 5 pass: elsewhere\n  pass: 77\n'; } > "$SF_PLAN"
}
sf_plan
sf_run() {  # sets SF_OUT (stdout) and SF_RC, in this shell
  call units_step_fields "$@" > "$SANDBOX/sf.out"; SF_RC=$CALL_RC; SF_OUT="$(cat "$SANDBOX/sf.out")"
}
sf_run --replace "$SF_PLAN" 5 pass=4
expect_eq "SF-1 --replace: the block's pass: line is replaced where it stands (exit 0)" "0" "$SF_RC"
expect_eq "SF-1b …the block holds one pass: line, with the new value" "  pass: 4" \
  "$(printf '%s\n' "$SF_OUT" | awk '/^- Step 5:/ { f = 1; next } /^- Step 6:/ { exit } f && /^  pass:/ { print }')"
expect_eq "SF-1c …its place is kept: the line before it is the blank the block had" "[]" \
  "$(printf '%s\n' "$SF_OUT" | awk '/^  pass: 4$/ { print "[" prev "]"; exit } { prev = $0 }')"
expect_eq "SF-1d …and it is the only line that differs (one removed, one added)" "1 1" \
  "$(diff "$SF_PLAN" <(printf '%s\n' "$SF_OUT") | awk '/^</ { a++ } /^>/ { b++ } END { print a + 0, b + 0 }')"
expect_eq "SF-1e …the same key in another section, and on another step's line, is left as written" "2" \
  "$(printf '%s\n' "$SF_OUT" | /usr/bin/grep -cE '^  pass: 77$|^- Step 6: pass: 9$')"
sf_run --replace "$SF_PLAN" 5 head=abc1234
expect_eq "SF-2 --replace of a key the block lacks writes it after the block's last line (exit 0)" "0" "$SF_RC"
expect_eq "SF-2b …directly under the last field, before the next step's line" "  output: record/x.log|  head: abc1234|- Step 6: pass: 9" \
  "$(printf '%s\n' "$SF_OUT" | awk '/^  output:/ { f = 1 } f { printf "%s%s", (n++ ? "|" : ""), $0 } /^- Step 6:/ { exit }')"
sf_run --replace "$SF_PLAN" 5 pass=4 total=4 head=abc1234
expect_eq "SF-3 several keys at once: two replaced, one written, one line each" "pass: 4|total: 4|head: abc1234" \
  "$(printf '%s\n' "$SF_OUT" | awk '/^- Step 5:/ { f = 1; next } /^- Step 6:/ { exit } f && /^  (pass|total|head):/ { sub(/^  /, ""); printf "%s%s", (n++ ? "|" : ""), $0 }')"
# a duplicate of the key in the block: the gate reads the first, so the first is replaced and the rest go
{ sed 's/^  total: 4$/  pass: 5\n  total: 4/' "$SF_PLAN"; } > "$SF_PLAN.dup"
sf_run --replace "$SF_PLAN.dup" 5 pass=4
expect_eq "SF-4 a block holding the key twice leaves one line of it, the new value" "1|  pass: 4" \
  "$(printf '%s\n' "$SF_OUT" | awk '/^- Step 5:/ { f = 1; next } /^- Step 6:/ { exit } f && /^  pass:/ { n++; l = $0 } END { print n + 0 "|" l }')"
sf_run "$SF_PLAN" 5 pass=4
expect_eq "SF-5 the fill mode (no flag) still leaves a key the block has as written (control: 1.12.0 behaviour)" "0|  pass: 3" \
  "$SF_RC|$(printf '%s\n' "$SF_OUT" | awk '/^- Step 5:/ { f = 1; next } f && /^  pass:/ { print; exit }')"
sf_run --replace "$SF_PLAN" 5 $'cmd=a\nb'
expect_eq "SF-6 a value with a line break: exit 4, and nothing on stdout" "4|0" \
  "$SF_RC|$(printf %s "$SF_OUT" | wc -c | tr -d ' ')"
sf_run --replace "$SF_PLAN" 5 $'cmd=a\rb' >/dev/null
expect_eq "SF-6b …and a carriage return the same" "4" "$SF_RC"
sf_run --replace "$SF_PLAN" 8 head=abc1234 >/dev/null
expect_eq "SF-7 a step with no line: exit 1" "1" "$SF_RC"
sf_run --replace "$SF_PLAN" 6 pass=4 >/dev/null
expect_eq "SF-8 a key the step line itself carries: exit 5, nothing replaced or written" "5" "$SF_RC"
sf_run --replace "$SF_PLAN" 5 pass >/dev/null
expect_eq "SF-9 an operand with no =: exit 3" "3" "$SF_RC"
# a value holding regex and awk metacharacters is written as it is
sf_run --replace "$SF_PLAN" 5 'cmd=bash tests/a.test.sh && echo "$X" \1 & .*'
expect_eq "SF-10 a value with & \\1 .* and a quote is written as typed" '  cmd: bash tests/a.test.sh && echo "$X" \1 & .*' \
  "$(printf '%s\n' "$SF_OUT" | awk '/^- Step 5:/ { f = 1; next } f && /^  cmd:/ { print; exit }')"

# THE MUTATION ARM: a copy of the library whose replace mode writes the new line AFTER the old one (an append
# where a replacement belongs) turns SF-1b, SF-1d and SF-4 red. The copy is made in the sandbox, never in the tree.
SF_NEEDLE='if (replace && (i in at_line)) print "  " key[at_line[i]] ": " val[at_line[i]]'
anchor "$LIB" "$SF_NEEDLE" 1
SF_MUT="$SANDBOX/units-mut-append.sh"
SF_R='if (replace && (i in at_line)) { print L[i]; print "  " key[at_line[i]] ": " val[at_line[i]] }'
SF_N="$SF_NEEDLE" SF_R="$SF_R" awk 'BEGIN { n = ENVIRON["SF_N"]; r = ENVIRON["SF_R"] } { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) r substr($0, i + length(n)); print }' "$LIB" > "$SF_MUT"
expect_eq "SF-mut0 the append copy of the library differs from it in one line" "1" "$(diff "$LIB" "$SF_MUT" | grep -c '^>')"
SF_MOUT="$(bash -c '. "$1" >/dev/null 2>&1; units_step_fields --replace "$2" 5 pass=4' _ "$SF_MUT" "$SF_PLAN" 2>/dev/null)"
expect_eq "SF-mut1 the mutant runs and returns the plan (its output is real: the Step 5 line is there)" "1" \
  "$(printf '%s\n' "$SF_MOUT" | grep -c '^- Step 5: floor$')"
expect_eq "SF-mut2 …but its Step 5 block holds two pass: lines (the old one kept), so SF-1b's one line goes red" "2" \
  "$(printf '%s\n' "$SF_MOUT" | awk '/^- Step 5:/ { f = 1; next } /^- Step 6:/ { exit } f && /^  pass:/ { n++ } END { print n + 0 }')"
expect_eq "SF-mut3 …and the library's own replacement holds one (the same extractor on the same plan)" "1" \
  "$(call units_step_fields --replace "$SF_PLAN" 5 pass=4 | awk '/^- Step 5:/ { f = 1; next } /^- Step 6:/ { exit } f && /^  pass:/ { n++ } END { print n + 0 }')"

section "§READS-HEAD — wave-30 T13: a verify or test row that drops head from its reads is refused (REQ-4 AC-4.3; D7, Δ6a)"
# THE REGRESSION ROW'S READINESS IS STRUCTURAL. Its kind default, approval:plan, head, waits on every
# open row that writes code (READS.5). Wave-28's T28 overrode the cell with a record path and ran its
# full run while build rows were still open; the validator now refuses that cell, naming the row and
# the token it dropped. The fixture is READS' own table with its verify row's cell rewritten.
rh_cell() {  # <T2's reads cell> <file> — reads.md with the verify row T2 reading <cell>
  sed "s#^| T2 | 5 | verify | the walk, reads empty | researcher | — | 30 | REQ-x | .bionic/docs/record/w/walk.md | — | pending |#| T2 | 5 | verify | the walk | researcher | — | 30 | REQ-x | .bionic/docs/record/w/walk.md | $1 | pending |#" \
    "$SANDBOX/reads.md" > "$2"
}
rh_cell ".bionic/docs/record/w/build-log.md" "$SANDBOX/rh-record.md"
expect_eq "RH-0 precondition: the fixture's T2 reads the record path" "1" \
  "$(grep -c '^| T2 | 5 | verify | the walk | researcher | — | 30 | REQ-x | .bionic/docs/record/w/walk.md | .bionic/docs/record/w/build-log.md | pending |$' "$SANDBOX/rh-record.md")"
RH_V="$(call units_validate "$SANDBOX/rh-record.md")"
expect_contains "RH-1 a verify row reading a record path instead of head is refused, naming the row and the token" \
  "T2: reads .bionic/docs/record/w/build-log.md drops head; a verify row must read head" "$RH_V"
expect_eq "RH-1b …and the verb exits 1" "1" "$(call_rc units_validate "$SANDBOX/rh-record.md")"
rh_cell "approval:plan, head" "$SANDBOX/rh-default.md"
expect_eq "RH-2 the same row reading approval:plan, head validates (the default, written out)" "0|" \
  "$(call_rc units_validate "$SANDBOX/rh-default.md")|$(call units_validate "$SANDBOX/rh-default.md")"
expect_eq "RH-2b …and that row waits for T1, the open build row (the structural readiness)" "yes" \
  "$(has_line "$(call units_waiting "$SANDBOX/rh-default.md" 4)" "T2${TAB}head${TAB}T1${TAB}pending")"
rh_cell "approval:plan, .bionic/docs/record/w/build-log.md, head" "$SANDBOX/rh-both.md"
expect_eq "RH-3 a record path beside head is admitted: head is what is asked for" "0" \
  "$(call_rc units_validate "$SANDBOX/rh-both.md")"
rh_cell "approval:plan" "$SANDBOX/rh-approval.md"
expect_contains "RH-4 approval alone drops head too" \
  "T2: reads approval:plan drops head; a verify row must read head" "$(call units_validate "$SANDBOX/rh-approval.md")"
rh_cell "live:head" "$SANDBOX/rh-live.md"
expect_contains "RH-5 live:head is not head: it waits on no open writer, so it is refused on a verify row" \
  "T2: reads live:head drops head; a verify row must read head" "$(call units_validate "$SANDBOX/rh-live.md")"
# A test row is held to the same rule; a doc row is not (its Files are not code).
sed 's#^| T5 | 4 | build | reads a file no open row writes |#| T5 | 4 | test | reads a file no open row writes |#' \
  "$SANDBOX/reads.md" > "$SANDBOX/rh-test.md"
expect_contains "RH-6 a test row reading lib/old.sh, approval:plan is refused, named as a test row" \
  "T5: reads lib/old.sh, approval:plan drops head; a test row must read head" "$(call units_validate "$SANDBOX/rh-test.md")"
sed 's#^| T5 | 4 | build | reads a file no open row writes |#| T5 | 4 | doc | reads a file no open row writes |#' \
  "$SANDBOX/reads.md" > "$SANDBOX/rh-doc.md"
expect_eq "RH-7 a doc row reading the same cell validates: a doc row is not held to head" "0|" \
  "$(call_rc units_validate "$SANDBOX/rh-doc.md")|$(call units_validate "$SANDBOX/rh-doc.md")"
# ONLY AN OPEN ROW (A-T13.1): a landed or dropped row's reads schedule nothing, and a plan already
# carrying one from before this rule must still commit.
sed 's#| .bionic/docs/record/w/build-log.md | pending |$#| .bionic/docs/record/w/build-log.md | landed |#' \
  "$SANDBOX/rh-record.md" > "$SANDBOX/rh-landed.md"
expect_eq "RH-8 precondition: the landed copy differs from the refused one in T2's status alone" "1" \
  "$(diff "$SANDBOX/rh-record.md" "$SANDBOX/rh-landed.md" | grep -c '^>')"
expect_eq "RH-8b …and a landed verify row that dropped head is not refused" "0" \
  "$(call_rc units_validate "$SANDBOX/rh-landed.md")"

# ============================================================
section "§TASK-SPLIT — wave-30 T17: a split is one projection, its children a partition of the parent's Files (REQ-12 AC-12.6; D14d-3, Δ11)"
# ============================================================
#
# THREE PURE READERS UNDER `session-poker.sh task-split`. `units_split_check` judges the child specs'
# Files against the parent's: each child's entries are the parent's, and together they name every
# one (a path left out, or one the parent never declared, is a line naming it). `units_split_dependents`
# names every row that waits on the parent: an edge from it (a read it satisfies) or a deps token
# naming it. `units_split_row` prints the whole plan with the split written: the parent `dropped`
# with ` · split-into: <ids>` on its task, each deps token naming it replaced by every child, the
# children added by `units_add_row` (the parent's step, kind, deps, serves and reads; their own task,
# size and Files), and the lines under `## SDLC State`. It writes nothing; the instant is an operand.
cat > "$SANDBOX/split-nr.md" <<'SPNR_EOF'
## SDLC State

current: 4
approved-by: fixture 2026-10-03T00:00Z "approved"

- Step 4: opened
- T1: landed at record/T1.md
- T2: dispatched to w-T2
- T6: pending dispatch — added by task-add at 2026-10-08T00:00:00Z
- T7: pending dispatch

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the build | implementor | — | 30 | REQ-x | a.sh | — | — | landed |
| T2 | 4 | build | in flight | implementor | — | 30 | REQ-x | b.sh | 01-T2 | abc1234 | active |
| T6 | 4 | build | the big one | w01-T6 | T1 | 90 | REQ-5 | lib/c.sh, lib/d.sh, .bionic/docs/record/w/T6-iface.md | — | — | pending |
| T7 | 4 | build | after the big one | implementor | T6 | 30 | REQ-x | lib/e.sh | — | — | pending |
| T5 | 5 | verify | the floor | test-runner | T1, T2, T6, T7 | 30 | REQ-x | — | — | — | pending |
SPNR_EOF
SP_IFACE=".bionic/docs/record/w/T6-iface.md"
SP_PF="lib/c.sh, lib/d.sh, $SP_IFACE"

# ---------- the partition: subset and cover ----------
expect_eq "SPLIT-1 a partition of the parent's Files passes the check (exit 0, nothing printed)" "0|" \
  "$(call_rc units_split_check T6 "$SP_PF" T8 "$SP_IFACE, lib/c.sh" T9 "lib/d.sh")|$(call units_split_check T6 "$SP_PF" T8 "$SP_IFACE, lib/c.sh" T9 "lib/d.sh")"
expect_eq "SPLIT-1b …spelled ./ or marked ! it is the same entry" "0" \
  "$(call_rc units_split_check T6 "$SP_PF" T8 "./$SP_IFACE, lib/c.sh!" T9 "lib/d.sh")"
expect_eq "SPLIT-2 a child naming a path the parent does not declare is refused, naming the child and the path" \
  "T9: Files entry lib/x.sh is not one of T6's Files" \
  "$(call units_split_check T6 "$SP_PF" T8 "$SP_IFACE, lib/c.sh" T9 "lib/d.sh, lib/x.sh")"
expect_eq "SPLIT-2b …exit 1" "1" "$(call_rc units_split_check T6 "$SP_PF" T8 "$SP_IFACE, lib/c.sh" T9 "lib/d.sh, lib/x.sh")"
expect_eq "SPLIT-3 a partition that leaves a parent path out is refused, naming the path" \
  "T6: Files entry lib/d.sh is in no child's Files" \
  "$(call units_split_check T6 "$SP_PF" T8 "$SP_IFACE, lib/c.sh" T9 "lib/c.sh")"
expect_eq "SPLIT-3b …exit 1" "1" "$(call_rc units_split_check T6 "$SP_PF" T8 "$SP_IFACE, lib/c.sh" T9 "lib/c.sh")"
expect_eq "SPLIT-3c a parent with no Files splits into children with none" "0" "$(call_rc units_split_check T6 "—" T8 "—" T9 "—")"

# ---------- the dependents ----------
expect_eq "SPLIT-4 the rows waiting on T6 in a table without reads: T7 and T5, by deps (table order)" "T7 T5" \
  "$(call units_split_dependents "$SANDBOX/split-nr.md" T6 | tr '\n' ' ' | sed 's/ $//')"

# ---------- the projection, a table without reads ----------
SP_SUM="$(cksum < "$SANDBOX/split-nr.md")"
SP_OUT="$(call units_split_row "$SANDBOX/split-nr.md" T6 2026-10-09T00:00:00Z \
  T8 'the interface' 20 "$SP_IFACE, lib/c.sh" T9 'the rest' 70 'lib/d.sh')"
SP_RC="$CALL_RC"
printf '%s\n' "$SP_OUT" > "$SANDBOX/split-nr-out.md"
expect_eq "SPLIT-5 the projector exits 0" "0" "$SP_RC"
expect_eq "SPLIT-5b …and writes nothing: the plan is byte-identical" "$SP_SUM" "$(cksum < "$SANDBOX/split-nr.md")"
expect_contains "SPLIT-6 the parent is dropped, its task naming the children" \
  "| T6 | 4 | build | the big one · split-into: T8, T9 | w01-T6 | T1 | 90 | REQ-5 | $SP_PF | — | — | dropped |" "$SP_OUT"
expect_contains "SPLIT-7 the first child: the parent's step, kind, deps and serves, its own task, size and Files, the agent renamed" \
  "| T8 | 4 | build | the interface | w01-T8 | T1 | 20 | REQ-5 | $SP_IFACE, lib/c.sh | — | — | pending |" "$SP_OUT"
expect_contains "SPLIT-7b …and the second" \
  "| T9 | 4 | build | the rest | w01-T9 | T1 | 70 | REQ-5 | lib/d.sh | — | — | pending |" "$SP_OUT"
expect_contains "SPLIT-8 a deps dependent waits on every child in the parent's place" \
  "| T7 | 4 | build | after the big one | implementor | T8, T9 |" "$SP_OUT"
expect_contains "SPLIT-8b …and the floor too, the token replaced where it stood and nothing threaded twice" \
  "| T5 | 5 | verify | the floor | test-runner | T1, T2, T8, T9, T7 |" "$SP_OUT"
expect_eq "SPLIT-8c …no deps cell names the dropped parent: no row waits on it" "" \
  "$(call units_split_dependents "$SANDBOX/split-nr-out.md" T6)"
expect_contains "SPLIT-9 the ledger line: - T6: split into the children at the instant" \
  "- T6: split into T8, T9 at 2026-10-09T00:00:00Z" "$SP_OUT"
expect_contains "SPLIT-9b …each child's own line" "- T8: pending dispatch — split from T6 at 2026-10-09T00:00:00Z" "$SP_OUT"
expect_contains "SPLIT-9c …and the second's" "- T9: pending dispatch — split from T6 at 2026-10-09T00:00:00Z" "$SP_OUT"
expect_eq "SPLIT-10 the projection validates clean" "0|" \
  "$(call_rc units_validate "$SANDBOX/split-nr-out.md")|$(call units_validate "$SANDBOX/split-nr-out.md")"
expect_eq "SPLIT-11 an active parent is not projected (exit 3), nothing printed" "3|" \
  "$(call_rc units_split_row "$SANDBOX/split-nr.md" T2 2026-10-09T00:00:00Z T8 a 10 b.sh T9 b 10 b.sh)|$(call units_split_row "$SANDBOX/split-nr.md" T2 2026-10-09T00:00:00Z T8 a 10 b.sh T9 b 10 b.sh)"
expect_eq "SPLIT-11b …nor an id the table does not carry (exit 2)" "2" \
  "$(call_rc units_split_row "$SANDBOX/split-nr.md" T44 2026-10-09T00:00:00Z T8 a 10 b.sh T9 b 10 b.sh)"

# ---------- a table with reads: the reader is re-pointed by the path it reads ----------
cat > "$SANDBOX/split-r.md" <<'SPR_EOF'
## SDLC State

current: 4
approved-by: fixture 2026-10-03T00:00Z "approved"

- T1: landed at record/T1.md
- T6: pending dispatch
- T7: pending dispatch

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the build | implementor | — | 30 | REQ-x | a.sh | — | — | landed | — |
| T6 | 4 | build | the big one | w01-T6 | — | 90 | REQ-5 | lib/c.sh, lib/d.sh, .bionic/docs/record/w/T6-iface.md | — | — | pending | approval:plan |
| T7 | 4 | build | reads the interface | implementor | — | 30 | REQ-x | lib/e.sh | — | — | pending | .bionic/docs/record/w/T6-iface.md |
| T5 | 5 | verify | the floor | test-runner | — | 30 | REQ-x | — | — | — | pending | approval:plan, head |
SPR_EOF
expect_eq "SPLIT-12 precondition: the reads table validates" "0" "$(call_rc units_validate "$SANDBOX/split-r.md")"
expect_eq "SPLIT-12b the rows waiting on T6 by what they read: T7 (its record) and T5 (head)" "T7 T5" \
  "$(call units_split_dependents "$SANDBOX/split-r.md" T6 | tr '\n' ' ' | sed 's/ $//')"
call units_split_row "$SANDBOX/split-r.md" T6 2026-10-09T00:00:00Z \
  T8 'the interface' 20 "$SP_IFACE" T9 'the rest' 70 'lib/c.sh, lib/d.sh' > "$SANDBOX/split-r-out.md"
expect_eq "SPLIT-13 the projector exits 0 on a reads table" "0" "$CALL_RC"
expect_contains "SPLIT-13b …the children carry the parent's reads" \
  "| T8 | 4 | build | the interface | w01-T8 | — | 20 | REQ-5 | $SP_IFACE | — | — | pending | approval:plan |" "$(cat "$SANDBOX/split-r-out.md")"
SP_EDGES="$(bash -c '. "$1" && units_edges "$2"' _ "$LIB" "$SANDBOX/split-r-out.md" 2>/dev/null)"
expect_contains "SPLIT-14 the reader of the record now waits on the child that writes it, T8" \
  "$(printf 'T8\tT7\t%s' "$SP_IFACE")" "$SP_EDGES"
expect_absent "SPLIT-14b …and not on T9, which does not" "$(printf 'T9\tT7\t')" "$SP_EDGES"
expect_absent "SPLIT-14c …no edge leaves the dropped parent" "$(printf 'T6\t')" "$SP_EDGES"
expect_eq "SPLIT-14d …and no row waits on it" "" "$(call units_split_dependents "$SANDBOX/split-r-out.md" T6)"
expect_eq "SPLIT-15 the reads projection validates clean" "0" "$(call_rc units_validate "$SANDBOX/split-r-out.md")"
section "§SUSPECT — wave-30 T16: a dependency that shares no file with its holder is named, never loosened (REQ-12 AC-12.2; D14a, Δ8)"
# A ROW THAT WAITS ON ANOTHER ONLY FOR ITS RECORD, AND WRITES NOTHING IT WRITES, IS A SUSPECT. Wave-28
# held T2 50 minutes, T18 255 and T20 49 on a declared read whose landed diffs shared no file
# (research-waits-w28.md §Were the declared waits real?). `units_suspect` names each such pair, with
# the `task-set` line that would loosen it, and changes no cell: a dependency may be runtime state or
# an order no file test sees, so the mind decides. Judged: an open row of a writing kind, against an
# open holder it names by id (deps) or by a path the holder's Files cover (reads). Not suspect: the
# two rows share a path outside the record, or the row reads a path outside the record the holder writes.
cat > "$SANDBOX/suspect.md" <<'SUSPECT_EOF'
## SDLC State

current: 4
approved-by: fixture 2026-10-08T00:00Z "approved"

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status | reads |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the holder | w-T1 | — | 30 | REQ-x | payload/a.sh, .bionic/docs/record/w/T1-a.md | active | — |
| T2 | 4 | build | reads only the holder's record and shares nothing | w-T2 | — | 20 | REQ-x | payload/b.sh, .bionic/docs/record/w/T2-b.md | pending | .bionic/docs/record/w/T1-a.md |
| T3 | 4 | build | reads the record and shares a.sh | w-T3 | — | 20 | REQ-x | payload/a.sh, .bionic/docs/record/w/T3.md | pending | .bionic/docs/record/w/T1-a.md |
| T4 | 4 | build | reads the code the holder writes | w-T4 | — | 20 | REQ-x | payload/c.sh | pending | payload/a.sh, approval:plan |
| T5 | 4 | build | reads the record beside the approval | w-T5 | — | 20 | REQ-x | payload/d.sh | pending | approval:plan, .bionic/docs/record/w/T1-a.md |
| T6 | 5 | verify | the walk reads the record | w-T6 | — | 20 | REQ-x | .bionic/docs/record/w/walk.md | pending | approval:plan, head, .bionic/docs/record/w/T1-a.md |
| T7 | 4 | build | reads a landed row's record | w-T7 | — | 20 | REQ-x | payload/e.sh | pending | .bionic/docs/record/w/T0.md |
| T0 | 4 | build | landed | w-T0 | — | 20 | REQ-x | payload/f.sh, .bionic/docs/record/w/T0.md | landed | — |
SUSPECT_EOF
expect_eq "SU-0 precondition: the fixture reads as eight rows (the extractor reads real input)" "8" \
  "$(nlines "$(call units_rows "$SANDBOX/suspect.md")")"
SU_CK="$(cksum < "$SANDBOX/suspect.md")"
expect_eq "SU-1 AC-12.2 the suspects are T2 and T5 on T1, each with its clause and the task-set line that loosens it" \
  "T2${TAB}T1${TAB}suspect: T2 reads T1, shares no file${TAB}task-set T2 reads=—
T5${TAB}T1${TAB}suspect: T5 reads T1, shares no file${TAB}task-set T5 reads='approval:plan'" \
  "$(call units_suspect "$SANDBOX/suspect.md")"
expect_eq "SU-1b …and it exits 0" "0" "$(call_rc units_suspect "$SANDBOX/suspect.md")"
expect_eq "SU-2 asked of one row, it answers for that row alone" \
  "T2${TAB}T1${TAB}suspect: T2 reads T1, shares no file${TAB}task-set T2 reads=—" \
  "$(call units_suspect "$SANDBOX/suspect.md" T2)"
expect_eq "SU-3 a row sharing a path outside the record with its holder is not suspect (beside SU-2, same fixture)" "" \
  "$(call units_suspect "$SANDBOX/suspect.md" T3)"
expect_eq "SU-4 a row reading code its holder writes is not suspect" "" "$(call units_suspect "$SANDBOX/suspect.md" T4)"
expect_eq "SU-5 a verify row is not judged: reading records is its work" "" "$(call units_suspect "$SANDBOX/suspect.md" T6)"
expect_eq "SU-6 a landed holder holds nothing, so nothing is suspect" "" "$(call units_suspect "$SANDBOX/suspect.md" T7)"
expect_eq "SU-7 AC-12.2 the machine never rewrites a declaration: the plan is byte-identical" "$SU_CK" "$(cksum < "$SANDBOX/suspect.md")"
# A TABLE WITHOUT A reads COLUMN: a deps id is the dependency, and the loosening line is deps=.
cat > "$SANDBOX/suspect-deps.md" <<'SUSPECT_EOF'
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the holder | w-T1 | — | 30 | REQ-x | payload/a.sh | active |
| T2 | 4 | build | deps on T1, disjoint | w-T2 | T1 | 20 | REQ-x | payload/b.sh | pending |
| T3 | 4 | build | deps on T1, shares a.sh | w-T3 | T1 | 20 | REQ-x | payload/a.sh | pending |
| T4 | 4 | build | deps on T1 and the world | w-T4 | T1, ext:ci | 20 | REQ-x | payload/c.sh | pending |
SUSPECT_EOF
expect_eq "SU-8 in a deps table the suspects are T2 and T4, loosened through deps" \
  "T2${TAB}T1${TAB}suspect: T2 reads T1, shares no file${TAB}task-set T2 deps=—
T4${TAB}T1${TAB}suspect: T4 reads T1, shares no file${TAB}task-set T4 deps='ext:ci'" \
  "$(call units_suspect "$SANDBOX/suspect-deps.md")"
expect_eq "SU-9 a plan with no table answers nothing, exit 0" "0|" \
  "$(call_rc units_suspect "$SANDBOX/no-such-plan.md")|$(call units_suspect "$SANDBOX/no-such-plan.md")"


# ============================================================
section "§BORN-READ — wave-30 T21: units_born reads the review-born rows off their ## SDLC State lines (REQ-10 AC-10.2, REQ-2 AC-2.3; D4)"
# ============================================================
# A row task-add --born made carries ` born: review S<n> <reach>` on its `- <id>:` line (the one place the count
# reads). units_born prints `<id>\t<S<n> <reach>>\t<Files cell>` per such line, table order of the lines, the line
# found as the gate finds it (the first `- <id>:` of the section, fences skipped). Nothing, exit 0, when none.
cat > "$SANDBOX/born.md" <<'BORN_EOF'
## SDLC State

current: 4

- T1: landed abc 2026-10-09T00:00:00Z
- T2: pending dispatch — added by task-add at 2026-10-09T01:00:00Z born: review S2 on landed def 2026-10-09T02:00:00Z
- T3: pending dispatch — added by task-add at 2026-10-09T01:10:00Z
- T4: pending dispatch — added by task-add at 2026-10-09T01:20:00Z born: review S1 off

```
- T9: an example born: review S1 on
```

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | one | w-T1 | — | 30 | REQ-x | payload/a.sh | landed |
| T2 | 4 | build | two · born: review | w-T2 | — | 30 | REQ-x | payload/a.sh, payload/b.sh | landed |
| T3 | 4 | build | three | w-T3 | — | 30 | REQ-x | payload/c.sh | pending |
| T4 | 4 | build | four · born: review | w-T4 | — | 30 | REQ-x | payload/a.sh | pending |
BORN_EOF
expect_eq "BR-1 the two review-born rows, each with its rating and its Files cell; the fenced example is not one" \
  "T2${TAB}S2 on${TAB}payload/a.sh, payload/b.sh
T4${TAB}S1 off${TAB}payload/a.sh" "$(call units_born "$SANDBOX/born.md")"
expect_eq "BR-1b …exit 0" "0" "$(call_rc units_born "$SANDBOX/born.md")"
sed '/born: review S/s/ born: review S[0-9] o[nf]*//' "$SANDBOX/born.md" > "$SANDBOX/born-none.md"
expect_eq "BR-2 the same plan with the markers taken off has no review-born row (BR-1 read two from it), exit 0" "|0" \
  "$(call units_born "$SANDBOX/born-none.md")|$(call_rc units_born "$SANDBOX/born-none.md")"

# ============================================================
section "§ONE-SHAPE — wave-31 T5: a plan in the retired task-scale shape is refused aloud; the one table validates at task scale (REQ-1 AC-1.2, AC-1.3; D2)"
# ============================================================
#
# ONE LEDGER SHAPE AT EVERY SCALE (D2). A task-scale run carries the one `## Tasks` table and a
# numeric `current:`; the scales differ in their artifacts, never in the ledger. The retired shape's
# `current: T<n>` used to make launch-sync exit 0 having written nothing, so a task-scale run went
# unrecorded in silence. It is refused now, on stderr, exit 1: the turn-end wall passes 0 and 75
# only, so a plan in the old shape is told. The plan is written by tests/lib/plan-fixture.sh, the one
# helper every suite builds a plan through; the launch-sync world is §49's of session-poker-2, small.
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"
OS_SID="5e7a9c10-31a5-4b2e-9d0f-0a1b2c3d4e5f"
OS_POKER="$REPO_ROOT/hooks/session-poker.sh"
os_world() {  # <label> <current> -> the repo; a bound task-scale plan, w-T1 launched on the roster
  local r="$SANDBOX/$1" p tree
  mkdir -p "$r/.bionic/tmp"
  ( cd "$r" && git init -q . && git commit -q --allow-empty -m init ) >/dev/null 2>&1
  : > "$r/.bionic/tmp/engaged-$OS_SID.state"
  p="$(plan_fixture --current "$2" "$r/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md" task \
    "| T1 | 4 | build | the unit in flight | implementor | — | — | 30 | REQ-1 | a.sh | — | — | pending |" \
    "| T2 | 4 | build | the next unit | implementor | — | a.sh | 30 | REQ-1 | b.sh | — | — | pending |")"
  bound_marker "$r" "$OS_SID" "$p"
  ( cd "$r" && git add -f "$p" && git commit -qm plan ) >/dev/null 2>&1
  { roster_header
    roster_row_fixture status=confirmed session="$OS_SID" name=w-T1 agent_id=a-w-T1 \
      launched_at=2026-10-04T03:30:00Z deliverable=t1.md 'duration=45 minutes' subagent_type=bionic:implementor
  } > "$r/.bionic/tmp/roster-$OS_SID.state"
  tree="$(cd "$r" && pwd -P)/.worktrees/01-T1"
  git -C "$r" worktree add -q -b wt/01-T1 "$tree" >/dev/null 2>&1
  printf 'workspace/v1|session=%s|name=w-T1|path=%s|branch=wt/01-T1|base=0123456789abcdef0123456789abcdef01234567|plan=%s|at=2026-10-04T03:36:00Z\n' \
    "$OS_SID" "$tree" "$p" >> "$r/.bionic/tmp/workspaces-$OS_SID.state"
  printf '%s' "$r"
}
os_sync() {  # <repo> -> OS_OUT (stdout), OS_ERR (stderr), OS_RC
  OS_OUT="$( cd "$1" && CLAUDE_CODE_SESSION_ID="$OS_SID" bash "$OS_POKER" launch-sync 2>"$SANDBOX/os.err" )"
  OS_RC=$?
  OS_ERR="$(cat "$SANDBOX/os.err")"
}
OS_PLAN_REL=".bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
# THE CONTROL: the same world at a numeric current records the launch, so the world is one the verb
# acts on, and the refusal below is about the field and nothing else.
OS_R4="$(os_world one-shape-4 4)"
os_sync "$OS_R4"
expect_eq "OS-1 control: at current: 4 launch-sync records the launch (exit 0)" "0" "$OS_RC"
expect_contains "OS-1b …and says so" "poker: LAUNCHED T1 w-T1" "$OS_OUT"
expect_contains "OS-1c …and the row is active in its tree" "| a.sh | .worktrees/01-T1 | 01234567 | active |" \
  "$(/usr/bin/grep '^| T1 |' "$OS_R4/$OS_PLAN_REL")"
OS_RT="$(os_world one-shape-t1 T1)"
cp "$OS_RT/$OS_PLAN_REL" "$SANDBOX/os-before.md"
os_sync "$OS_RT"
expect_eq "OS-2 AC-1.2 a plan at current: T1 is refused by launch-sync (exit 1)" "1" "$OS_RC"
expect_eq "OS-2b …with exactly the refusal line, on stderr" \
  "NOT-RECORDED — current: T1 is not numeric; a plan in the retired task-scale shape is refused, not skipped" "$OS_ERR"
expect_true "OS-2c …and the plan is byte-identical (cmp)" cmp -s "$SANDBOX/os-before.md" "$OS_RT/$OS_PLAN_REL"
# THE ONE TABLE VALIDATES AT TASK SCALE: clean, beside the same table with one row broken, which names it.
expect_eq "OS-3 AC-1.3 units_validate on the one table under scale: task is clean" "" \
  "$(call units_validate "$OS_R4/$OS_PLAN_REL")"
expect_eq "OS-3b …exit 0" "0" "$(call_rc units_validate "$OS_R4/$OS_PLAN_REL")"
sed 's/| b.sh | — | — | pending |/| b.sh | — | — | done |/' "$OS_R4/$OS_PLAN_REL" > "$SANDBOX/os-done.md"
expect_eq "OS-3c …and the retired word done is named on the same table (the reader reads it)" \
  "T2: status done is not one of pending active landed dropped" "$(call units_validate "$SANDBOX/os-done.md")"

finish
