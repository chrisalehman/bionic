#!/bin/bash
# tests/units.test.sh — payload/scripts/lib/units.sh: THE ONE READER OF `## Tasks`
# (epic-23 wave-11-lean-spine, REQ-1e; AC-1e.1/1e.2; spec Design §1 "Task", §2 D3/D7).
#
# WHAT IT OWNS. The contract three callers bind to after T8 — the evidence gate's ledger
# checks and its prototype check, the tick's FILL, and the governing-skill Step-3 wall — so
# that none of them carries a parser of its own. Three questions, one per function:
#
#   §1 units_rows <plan>          the ten fields, in the FIXED order, whatever order the
#                                 table's columns are written in
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
section "1 — units_rows: the live table, ten fields per row, in the fixed order"
# ============================================================

expect_eq "the live specimen yields one line per data row (22)" "22" "$(nlines "$ROWS_LIVE")"

expect_eq "every line carries exactly ten tab-separated fields" "22" \
  "$(printf '%s\n' "$ROWS_LIVE" | awk -F'\t' 'NF == 10 { n++ } END { print n + 0 }')"

# THE FIRST ROW, WHOLE. Written out by hand from the plan, which is the point: a row asserted
# against a value the reader itself produced would pass on any consistent misreading.
expect_eq "T1 renders id·step·kind·task·agent·deps·size·serves·Files·status in that order" \
  "$(printf 'T1\t3\tdoc\tPlan, Tasks and matrix written; Step-3 card approved\torchestrator\t—\t30m\tall\tplan\tlanded')" \
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

expect_eq "a table breaking seven invariants reports seven violations" "7" "$(nlines "$VAL_BAD")"
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
expect_contains "a Step-6 row that reaches no Step-4 row names the first one it misses" \
  "T7: step 6 does not depend transitively on step-4 row X1" "$VAL_BAD"

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

finish
