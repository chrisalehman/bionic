#!/bin/bash
# Tests for canonical-sdlc-evidence-gate.sh — shard 1 of 2 (Sections 1-28, then the AC-E1 sweep and R2).
#
# The evidence-gate suite was sharded in two at wave-30 T3 (D8b) so a landing that touches the
# gate proves in minutes. The runners, helpers and shared plan fixtures live in
# tests/canonical-sdlc-evidence-gate.prelude.sh, sourced by both shards; the strategy note
# there applies to each. Usage: bash tests/canonical-sdlc-evidence-gate.test.sh
#
# THE PRELUDE IS SOURCED BEFORE THE FRAMEWORK, on purpose — see its header.

set -euo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/canonical-sdlc-evidence-gate.prelude.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"

# THE SEAM IS hooks/bash-walls.sh (epic-23 wave-11-lean-spine, T23). This wall is a
# FUNCTION now — `wall_evidence_gate` in payload/scripts/lib/walls.sh — registered through
# the one PreToolUse|Bash command object that carries all five. Every case below drives
# that process, which is what a Bash tool call actually starts; the wall's own verdict is
# unchanged and tests/bash-walls.test.sh owns the composition the process adds.
HOOK="${BIONIC_HOOKS_DIR}/bash-walls.sh"

# THE FLOOR A RUN PAST STEP 6 CARRIES (wave-35 T31; D20, A-orch-50). From `current: 7` the gate refuses a
# `regression: yes` plan whose section holds no `proved: kind=regression` line. A fixture at Step 7..9 that is
# about something else is written through eg_floor: the prelude's readings (eg_readings) and one floor
# line in proof-add regression's shape after `current:`. Rows about the floor arm itself write plans as given.
eg_floor() {  # <plan content> -> the content with the readings and one floor proof line
  eg_readings "$1" | EG_H="$EG_HEAD" awk '{ print }
    !done && /^[[:space:]]*current[[:space:]]*:[[:space:]]*[7-9][ab]?[[:space:]]*$/ {
      printf "proved: kind=regression head=%s at=2026-10-12T00:00:00Z evidence=record/floor.log\n", ENVIRON["EG_H"]; done = 1 }'
}

# ============================================================
# Section 1: non-commit commands always allowed
# ============================================================

section "Section 1: Non-commit commands pass through"

h1=$(make_home)
# Seed a plan that WOULD block if the command were a commit.
write_plan "$h1" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: TODO" > /dev/null

expect_allow "ls command — not a commit" "$h1" "ls /tmp"
expect_allow "git status — not a commit" "$h1" "git status"
# THE DESTINATION IS A FEATURE BRANCH, AND ONLY SINCE T23. This row is about "a push is
# not a commit", and the destination was incidental — but hooks/protect-main.sh is a
# function in the same process now, and it refuses a push to main in every project on the
# machine, which it did as a separate process before this suite ever saw the payload. A
# row that kept `origin main` would be asserting the GATE's silence through another wall's
# refusal, which is a green that proves a different line than the one it names.
expect_allow "git push — not a commit" "$h1" "git push origin feature/x"

# ============================================================
# Section 2: commit with no plans directory / no plans
# ============================================================

section "Section 2: Commit with no canonical-sdlc state — allowed"

h2=$(make_home)
# plans dir exists but empty

h2b=$(mktemp -d); cleanup_dirs+=("$h2b")
# A bare temp dir: no plan directory of any kind.
expect_allow "no plans dir at all — allow commit" "$h2b" 'git commit -m "x"'

h2c=$(make_home)
write_plan "$h2c" "# regular plan
Some content.
No SDLC State section here." > /dev/null

# ============================================================
# Section 5: empty / placeholder evidence — blocked
# ============================================================

section "Section 5: Placeholder evidence — blocked"

h5=$(make_home)
write_plan "$h5" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5:   " > /dev/null
expect_block "empty evidence line" "$h5" 'git commit -m "x"' "is empty"

for token in TODO pending "in progress" XXX TBD placeholder; do
  h=$(make_home)
  write_plan "$h" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: $token" > /dev/null
  expect_block "placeholder '$token'" "$h" 'git commit -m "x"' "placeholder"
done

# Case-insensitive placeholder match. Under whole-value equality the ENTIRE
# trimmed value must equal a token, so the fixture is the bare token 'Todo'
# (was "Todo — still writing", which is prose that merely starts with the
# token — legal under the new contract; see 5e).
h5b=$(make_home)
write_plan "$h5b" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: Todo" > /dev/null
expect_block "placeholder 'Todo' (mixed case, bare token)" "$h5b" 'git commit -m "x"' "placeholder"

# --- whole-value equality: the placeholder ban matches only when the whole
# trimmed, lowercased value EQUALS a token (todo/pending/in progress/
# inprogress/xxx/tbd/placeholder). A token appearing as a substring of a
# longer value is legal evidence.

# 5c — whole-line 'Step 5: pending' (single-line value) → block.
h5c=$(make_home)
write_plan "$h5c" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5: pending" > /dev/null
expect_block "whole-line 'Step 5: pending' → block" "$h5c" 'git commit -m "x"' "placeholder"

# 5d — trim + lowercase before comparison: '  Pending  ' (padded, mixed case)
# as a continuation value still equals the token → block.
h5d=$(make_home)
write_plan "$h5d" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5:
  readback:   Pending  " > /dev/null
expect_block "padded mixed-case 'readback:   Pending  ' → block" "$h5d" 'git commit -m "x"' "placeholder"

# 5e — a value that merely CONTAINS a token as a substring is legal:
# 'resolved all TODOs from the last review' (contains 'todo') → allow. Under
# the OLD substring ban this was a false block.
h5e=$(make_home)
write_plan "$h5e" "$FM
## SDLC State
current: 3
Step 3: resolved all TODOs from the last review" > /dev/null
expect_allow "substring-only 'resolved all TODOs' → allow (whole-value equality)" \
  "$h5e" 'git commit -m "x"'

# 5f — a continuation key whose whole value equals a token still blocks:
# 'stack-health: pending' (value 'pending') → block.
h5f=$(make_home)
write_plan "$h5f" "$FM
## SDLC State
current: 5
approved-by: fixture 2026-09-07T00:00Z "approved"
Step 5:
  stack-health: pending" > /dev/null
expect_block "continuation 'stack-health: pending' (whole value) → block" \
  "$h5f" 'git commit -m "x"' "placeholder"

# ============================================================
# Section 9: a criterion is owed at the step whose task proves it
# ============================================================
#
# A matrix row's AC block names, in `task:`, the plan row whose work proves it. The row is owed at
# that row's step: before it, a pending or blocked row owes neither its per-tier keys nor an
# auditor's verdict, at any tier; from it on, it is judged as every other row. The literal `task: 9`
# is the close's step, as before. A row owed at Step 9 is the close's to settle, so the gate never
# demands it of an open plan; the close's own final act is what it waits for.
# FIXTURE FIDELITY: the plan builders every matrix section uses, with a `## Tasks` table placed
# before the matrix; the floor and readings a Step-7+ plan carries come from eg_floor.
# fails-when: a pending T3 row whose task is a Step-9 row is refused at 6, 7 or 8, or a row whose task
# is a Step-4 row is let through at 6, or the deferral outlives its owing step.

section "Section 9: a criterion is owed at the step whose task proves it"

ow_tasks="## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the build | implementor | — | 30m | REQ-1 | a.sh | landed |
| T7 | 7 | doc | the release | orchestrator | — | 10 | REQ-1 | CHANGELOG.md | pending |
| T9 | 9 | close | the close | orchestrator | — | 10 | REQ-1 | none | pending |"

# ow_matrix <tier> <task value> -> the first row discharged and confirmed, the second pending with that tier and task:
ow_matrix() {
  printf '%s\n' "## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |
| AC-2 | $1 | pending | — |  |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: bash test.sh — unit suite
  readback: 332/332 asserted
AC-2:
  fails-when: the close reads above zero
  eval: $1 — \`bash payload/hooks/session-poker.sh landing-report --hand-holds\` at the close reads total=0
  task: $2
  evidence: pending"
}
# ow_plan <current> <tier> <task value> -> the whole plan at that step, the Tasks table above the matrix
ow_plan() {
  local body p
  case "$1" in
    5) body="$step5_base" ;; 6) body="$step6_body" ;; 7) body="$v9_step7_body" ;;
    8) body="$v9_step8_body" ;; 9) body="$v9_step9_body" ;;
  esac
  p="$(plan "$1" "$body" "$(ow_matrix "$2" "$3")" | OW_T="$ow_tasks" awk '/^## Verification Matrix/ { print ENVIRON["OW_T"]; print "" } { print }')"
  if [ "$1" -ge 7 ]; then eg_floor "$p"; else printf '%s\n' "$p"; fi
}
ow_home() {  # <current> <tier> <task value> -> a sandbox holding that plan
  local h; h=$(make_home); write_plan "$h" "$(ow_plan "$@")" > /dev/null; printf '%s' "$h"
}

for ow_c in 5 6 7 8; do
  expect_allow "9a-$ow_c a pending T3 row whose task is a Step-9 row owes nothing at current $ow_c" \
    "$(ow_home "$ow_c" T3 T9)" 'git commit -m "x"'
done
expect_allow "9b at current 9, the plan still open, the row is the close's own to settle" \
  "$(ow_home 9 T3 T9)" 'git commit -m "x"'
expect_allow "9c the literal task: 9 on a T0 row still defers to the close at current 8" \
  "$(ow_home 8 T0 9)" 'git commit -m "x"'
expect_allow "9d the literal task: 9 on a T3 row defers too: the tier says how, the step says when" \
  "$(ow_home 6 T3 9)" 'git commit -m "x"'
expect_block "9e a pending T3 row whose task is a Step-4 row still owes its evidence at 6" \
  "$(ow_home 6 T3 T1)" 'git commit -m "x"' "AC-2 has placeholder evidence"
expect_allow "9f a row whose task is a Step-7 row owes nothing at 6" \
  "$(ow_home 6 T3 T7)" 'git commit -m "x"'
expect_block "9g …and is owed from Step 7 on" \
  "$(ow_home 7 T3 T7)" 'git commit -m "x"' "AC-2 has placeholder evidence"
expect_allow "9h a task list is owed at the latest step it names (T1, T9 at 8)" \
  "$(ow_home 8 T3 "T1, T9")" 'git commit -m "x"'

# The two file-scope readers the judge and the card share with the gate, asked as hooks/poker/judge.sh asks them.
ow_ask() {  # <plan> <function> [args…] -> what the function prints, then `rc=<n>`
  bash -c 'L="$1"; shift; . "$L/root.sh" && . "$L/run.sh" && . "$L/units.sh" && . "$L/walls.sh" >/dev/null 2>&1 || exit 9
    PLAN="$1"; RIGOR="$(plan_frontmatter_get "$1" rigor)"; shift; "$@"; echo "rc=$?"' _ "$BIONIC_SCRIPTS_DIR/payload/scripts/lib" "$@"
}
ow_p8="$(write_plan "$(make_home)" "$(ow_plan 8 T3 T9 | awk '
  /^\| AC-2 \|/ { print; print "| AC-3 | T3 | pending | — |  |"; next }
  { print }
  END { print "AC-3:"; print "  fails-when: the build is red"; print "  task: T1"; print "  evidence: pending" }')")"
expect_eq "9i matrix_unruled at 8 names the row owed at 4 and not the row owed at the close" "AC-3
rc=0" "$(ow_ask "$ow_p8" matrix_unruled "$ow_p8" 8)"
expect_eq "9j the owing step of a row id is that row's step, read from the Tasks table" "9|4|7|9|9" \
  "$(for t in T9 T1 T7 9 'T1, T9'; do ow_ask "$ow_p8" matrix_owing_step "$ow_p8" "  task: $t" | head -1; done | paste -sd'|' -)"
ow_p9="$(write_plan "$(make_home)" "$(ow_plan 9 T3 T9)")"
ow_p9d="$(write_plan "$(make_home)" "$(ow_plan 9 T3 T9 | awk '/^Step 9:/ { print "- Step 9: delivered: 2026-10-24T00:00Z wave-01"; skip = 1; next } skip && /^  / { next } { skip = 0; print }')")"
expect_eq "9k a row owed at 9 is deferred while the plan is open, and owed once the Step-9 line carries delivered:" \
  "rc=0|rc=1" "$(ow_ask "$ow_p9" matrix_row_deferred "$ow_p9" 9 9 pending | tail -1)|$(ow_ask "$ow_p9d" matrix_row_deferred "$ow_p9d" 9 9 pending | tail -1)"
expect_eq "9l a discharged row is never deferred, and a pending one is before its step" "rc=1|rc=0" \
  "$(ow_ask "$ow_p9" matrix_row_deferred "$ow_p9" 9 6 discharged | tail -1)|$(ow_ask "$ow_p9" matrix_row_deferred "$ow_p9" 9 6 pending | tail -1)"

finish
