#!/bin/bash
# tests/units.test.sh — payload/scripts/lib/units.sh: THE ONE READER OF `## Tasks`
# (epic-23 wave-11-lean-spine, REQ-1e; AC-1e.1/1e.2; spec Design §1 "Task", §2 D3/D7).
#
# WHAT IT OWNS. The contract three callers bind to after T8 — the evidence gate's ledger
# checks and its prototype check, the tick's FILL, and the governing-skill Step-3 wall — so
# that none of them carries a parser of its own. Three questions, one per function:
#
#   §1 units_rows <plan>          the eleven fields, in the FIXED order, whatever order the
#                                 table's columns are written in
#   §10 the `worktree` cell        slot 11, OPTIONAL: a table without the column is valid
#                                 and reads it empty (wave-14 REQ-2, ADR-027)
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
| T16 | 5 | verify | Auditor on the REQ-1e and REQ-1f rows (audited) and the wave verdict | auditor | T15 | 45m | REQ-1e, REQ-1f | record/wave-11-lean-spine/auditor.md | pending |
| T17 | 6 | review | Six-axis self-review, one reviewer per axis in parallel at exec-complex | orchestrator | T16 | 45m | all | record/wave-11-lean-spine/review/ | pending |
| T18 | 6 | review | Critic on T7–T12 (audited rows) | critic | T17 | 45m | REQ-1e, REQ-1f | record/wave-11-lean-spine/critic.md | pending |
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
section "1 — units_rows: the live table, eleven fields per row, in the fixed order"
# ============================================================

expect_eq "the live specimen yields one line per data row (22)" "22" "$(nlines "$ROWS_LIVE")"

# ELEVEN, NOT TEN, SINCE wave-14 REQ-2 — and the specimen carries no `worktree` column, so
# every one of the 22 lines ends in an EMPTY eleventh field rather than stopping at ten. A
# record whose width depended on which columns the table happened to carry would put every
# caller back to counting cells, which is the whole of what this reader exists to stop.
expect_eq "every line carries exactly eleven tab-separated fields" "22" \
  "$(printf '%s\n' "$ROWS_LIVE" | awk -F'\t' 'NF == 11 { n++ } END { print n + 0 }')"

# THE FIRST ROW, WHOLE. Written out by hand from the plan, which is the point: a row asserted
# against a value the reader itself produced would pass on any consistent misreading.
expect_eq "T1 renders id·step·kind·task·agent·deps·size·serves·Files·status·worktree in that order" \
  "$(printf 'T1\t3\tdoc\tPlan, Tasks and matrix written; Step-3 card approved\torchestrator\t—\t30m\tall\tplan\tlanded\t')" \
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
| T1 | bugfix | tested | fix the frontmatter parser | done |
| T2 | refactor | peer-reviewed | extract the ledger helper | active |
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
  "[tested][peer-reviewed][]" \
  "$(printf '%s\n' "$ROWS_TASK_SCALE" | awk -F'\t' '{ printf "[%s]", $3 }')"
expect_eq "units_field takes that cell by either name" "peer-reviewed peer-reviewed" \
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
section "4 — units_ready: pending, at this step, every dep landed"
# ============================================================

expect_eq "step 4: a row whose dep is still pending is not ready, and its siblings are" \
  "$(printf 'T3\nT5')" "$(call units_ready "$SANDBOX/ready-a.md" 4)"
expect_eq "…so T4, blocked behind pending T3, is absent" "" \
  "$(call units_ready "$SANDBOX/ready-a.md" 4 | grep -x T4)"
expect_eq "…and T2, already landed, is not offered again" "" \
  "$(call units_ready "$SANDBOX/ready-a.md" 4 | grep -x T2)"
expect_eq "…and step 3, whose only row is landed, is empty" "" \
  "$(call units_ready "$SANDBOX/ready-a.md" 3)"

expect_eq "step 5 with every Step-4 row landed: the ready rows, in TABLE order" \
  "$(printf 'T7\nT5')" "$(call units_ready "$SANDBOX/ready-b.md" 5)"
expect_eq "…a dep naming an id the table does not carry is never ready" "" \
  "$(call units_ready "$SANDBOX/ready-b.md" 5 | grep -x T6)"
expect_eq "…the step argument filters: step 4 is all landed, so nothing is ready" "" \
  "$(call units_ready "$SANDBOX/ready-b.md" 4)"
expect_eq "…and a step with no rows at all answers nothing" "" \
  "$(call units_ready "$SANDBOX/ready-b.md" 9)"

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

# TEN, NOT SEVEN (wave-17 REQ-5, AC-5.2). Seven invariants are broken, but the transitive
# arm now reports EVERY Step-4 row the offending row fails to reach rather than the first —
# T7 reaches only T1, so it misses X1, T4, T5 and T6, which is four lines from one row.
expect_eq "a table breaking seven invariants reports ten violations" "10" "$(nlines "$VAL_BAD")"
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
expect_contains "a Step-6 row that reaches no Step-4 row names the ones it misses" \
  "T7: step 6 does not depend transitively on step-4 row X1" "$VAL_BAD"
# …AND NAMES ALL OF THEM, IN TABLE ORDER. The author threading a plan reads the whole debt
# in one pass instead of one edge per round trip (AC-5.2; A-orch-59 of wave-16 is the
# ten-round-trip specimen). The duplicate `T1` row is a Step-4 row too, and it is NOT
# reported: T7 reaches the id, and reachability is keyed on the id, not on the row.
expect_eq "…every one of them, once each, in table order" \
  "X1 T4 T5 T6" \
  "$(printf '%s\n' "$VAL_BAD" | /usr/bin/grep '^T7: step 6 does not depend' | sed -E 's/.*step-4 row //' | tr '\n' ' ' | sed -E 's/ $//')"

# PAIRED POSITIVE. The good row is in the same table and is not accused of anything.
expect_eq "the one well-formed row draws no violation of its own" "0" \
  "$(printf '%s\n' "$VAL_BAD" | grep -c '^T1: [^d]' | tr -d ' ')"

# ============================================================
section "6b — the transitive rule is decided PER ROW, and the arm proves it discriminates"
# ============================================================
#
# WHY THIS SECTION EXISTS. §6's table carries exactly one Step-5-or-later row, so a library
# that computed the reachable set ONCE for the whole table — never resetting it between rows —
# would pass every assertion there. That is not hypothetical: the first implementation of this
# rule did exactly that, and the live specimen hid it, because the row before the offender
# reached everything and left its closure behind. Two Step-5 rows, the first reaching both
# Step-4 rows and the second reaching only one, is the smallest table that tells them apart.

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

VAL_LEAK="$(call units_validate "$SANDBOX/leak.md")"
expect_eq "of two Step-5 rows, only the one that misses a Step-4 row is reported" "1" \
  "$(nlines "$VAL_LEAK")"
expect_contains "…naming the row and the Step-4 row it never reaches" \
  "T5: step 5 does not depend transitively on step-4 row T3" "$VAL_LEAK"
expect_eq "…and the Step-5 row that does reach both draws nothing" "" \
  "$(printf '%s\n' "$VAL_LEAK" | grep '^T4:')"

# THE MUTATION ARM. Strip the per-row reset of the reachable set from a scratch copy of the
# shipped library: T4's closure then leaks into T5's, T5 appears to reach T3, and the
# violation disappears. Without this arm the three rows above pass just as loudly on a
# library that decides the rule once for the whole table.
anchor "$LIB" 'split("", reach)' 1
MUTANT="$SANDBOX/units-mutant.sh"
grep -v 'split("", reach)' "$LIB" > "$MUTANT"
MUTANT_OUT="$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; units_validate "$2"' \
  _ "$MUTANT" "$SANDBOX/leak.md")"
expect_eq "the shipped library reports it; the mutant that never resets the set does not" \
  "1 0" "$(nlines "$VAL_LEAK") $(nlines "$MUTANT_OUT")"
expect_eq "…and the mutant still parses, so the arm measures behaviour and not a syntax error" \
  "yes" "$(bash -n "$MUTANT" 2>/dev/null && echo yes || echo no)"

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
  printf '%s' "$u" | grep -v '^$' | sort || true
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
expect_eq "asked about Step 4 alone, units_ready names only the Step-4 row" \
  "T10" "$(sorted "$(new_ready "$SANDBOX/diff-wave.md" 4)")"
expect_eq "…and the old whole-table reader could not make that distinction" \
  "no" "$([ "$WAVE_OLD" = "T10" ] && echo yes || echo no)"

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
expect_eq "every row still carries exactly eleven fields" "3" \
  "$(printf '%s\n' "$ROWS_ESC" | awk -F'\t' 'NF == 11 { n++ } END { print n + 0 }')"

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

# units_rows IS UNTOUCHED BY THE RULE. The shifted row is still emitted with its eleven
# fields: the violation is advice to whoever wrote the plan, not a reason to hide a row from
# the schedulers that can still read most of it.
ROWS_RAW="$(call units_rows "$SANDBOX/raw-pipe.md")"
expect_eq "both rows still come through units_rows" "2" "$(nlines "$ROWS_RAW")"
expect_eq "…each carrying eleven fields" "2" \
  "$(printf '%s\n' "$ROWS_RAW" | awk -F'\t' 'NF == 11 { n++ } END { print n + 0 }')"

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
expect_eq "…each carrying eleven fields" "3" \
  "$(printf '%s\n' "$ROWS_WT" | awk -F'\t' 'NF == 11 { n++ } END { print n + 0 }')"

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
section "13 — the transitive arm names EVERY unreached step-4 row (wave-17 REQ-5, AC-5.2)"
# ============================================================
#
# WHY THIS SECTION EXISTS. The arm used to `break` after the first Step-4 row an offending
# row failed to reach, so an author threading a Step-5 row against four build rows learned
# of the second missing edge only after fixing the first, and paid one refused commit per
# edge. wave-16's A-orch-59 is the field specimen: a mid-run row unthreaded from ten rows,
# ten round trips. The file's own contract paragraph says EVERY FAULT IS REPORTED; this arm
# was the exception to it.
#
# THE SMALLEST TABLE THAT SHOWS IT is one Step-5 row threaded to exactly one of four Step-4
# rows: one line proves nothing about the bound, three do.

cat > "$SANDBOX/three-missing.md" <<'THREE_EOF'
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 3 | doc | plan written | orchestrator | — | 30m | all | plan | landed |
| T2 | 4 | build | first | implementor | T1 | 15m | REQ-x | a.sh | landed |
| T3 | 4 | build | second | implementor | T1 | 15m | REQ-x | b.sh | landed |
| T4 | 4 | build | third | implementor | T1 | 15m | REQ-x | c.sh | landed |
| T5 | 4 | build | fourth | implementor | T1 | 15m | REQ-x | d.sh | landed |
| T9 | 5 | test | the floor, threaded to one build row of four | test-runner | T2 | 40m | all | f.md | pending |
THREE_EOF

VAL_THREE="$(call units_validate "$SANDBOX/three-missing.md")"

expect_eq "13.1 a Step-5 row missing three step-4 rows reports three violations" "3" \
  "$(nlines "$VAL_THREE")"
expect_contains "13.2 …naming the first" \
  "T9: step 5 does not depend transitively on step-4 row T3" "$VAL_THREE"
expect_contains "13.3 …the second" \
  "T9: step 5 does not depend transitively on step-4 row T4" "$VAL_THREE"
expect_contains "13.4 …and the third" \
  "T9: step 5 does not depend transitively on step-4 row T5" "$VAL_THREE"
expect_eq "13.5 …and exits 1" "1" "$(call_rc units_validate "$SANDBOX/three-missing.md")"
# THE ROW IT DOES REACH IS NOT ACCUSED, and neither is the Step-3 row: only Step-4 rows are
# owed, and only the unreached ones are named.
expect_eq "13.6 the reached step-4 row and the step-3 row draw nothing" "" \
  "$(printf '%s\n' "$VAL_THREE" | /usr/bin/grep -E 'step-4 row (T1|T2)$')"

# THE MUTATION ARM. Put the `break` back into a scratch copy of the shipped library: the
# same table then yields one line instead of three. Without this arm, an implementation
# that reported three lines for some other reason — or a fixture that happened to miss one
# row — would read identically.
anchor "$LIB" 'does not depend transitively on step-4 row %s' 1
MUTANT_BREAK="$SANDBOX/units-mutant-break.sh"
awk '{ print }
     index($0, "does not depend transitively on step-4 row %s") { print "            break" }' \
  "$LIB" > "$MUTANT_BREAK"
MUTANT_BREAK_OUT="$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; units_validate "$2"' \
  _ "$MUTANT_BREAK" "$SANDBOX/three-missing.md")"
expect_eq "13.7 the shipped library reports three; the mutant that breaks reports one" \
  "3 1" "$(nlines "$VAL_THREE") $(nlines "$MUTANT_BREAK_OUT")"


finish
