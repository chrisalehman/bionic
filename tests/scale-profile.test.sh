#!/bin/bash
# Tests for payload/scripts/lib/scale.sh — THE SCALE PROFILE (epic-23 wave-38 T16; D25,
# REQ-5 AC-5.1, AC-5.3).
#
# ONE ROW PER SCALE, ONE CELL PER PROPERTY. A scale's properties (patrol, rigor default,
# writer cap, regression default, branch pattern, integrate act, reader dealing) were five
# literals in five files; they are one table read through `scale_cell <scale> <column>`, and
# every site reads its cell. "The next property of a scale is a column, never a check."
#
#   §CELL   the table: every cell, and the refusal of a scale or column it does not hold
#   §TASK   a task-scale fixture at every reader: engagement arms no Patrol; `facts_owed
#           single task` deals one critic; the dispatch wall refuses the fourth writer and
#           not for a Patrol; close-out accepts `fix/x` and its integrate act is a PR
#   §TABLE  SKILL.md's scale table cell for cell against the library; "Full set, compressed"
#           gone; the doctrine's byte count not grown
#
# fails-when: a patrol armed at task scale, two readers dealt unflagged, a branch refused, a
# fourth writer admitted with no person's cap, a cell of the doctrine table differing from the
# library, or the phrase surviving.
#
# FIXTURE FIDELITY (the rule of that name, .claude/rules/test-harness.md). The engagement and
# close-out roots are SYNTHESIZED: a plan carrying only the keys its reader asks (`scale:`, and
# for close-out `## SDLC State` with the two branches and `current: 8`), in a real git
# repository for close-out. The dispatch fixtures are the wall's own shards' (make_repo and the
# roster rows of tests/dispatch-preflight.prelude.sh), with the plan's `scale:` line rewritten
# and the Patrol stamp make_repo plants removed, so the wall reads the cell, not the fixture.
# §TABLE reads the shipped SKILL.md and its template.
#
# ANTI-VACUITY (the rule of that name). Every absence sits beside a positive on the same
# output: no stamp beside the binding the same engagement wrote; no Patrol refusal beside the
# budget wall's line in the same reason; no shape refusal beside the merge line in the same
# check. Each task-scale row has a wave-scale pair whose answer moves. The table extractor is
# proved to find the three rows before a cell is compared.
#
# Usage: bash tests/run.sh --only scale-profile.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
# The dispatch wall's fixtures (make_repo, run_gate, the roster rows) and the sandbox with its
# cleanup trap: §TASK drives the real wall through the same builders its own shards use.
. "$(dirname "$0")/dispatch-preflight.prelude.sh"

SP_REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
SP_LIB="$SP_REPO/payload/scripts/lib"
SP_SKILL="$SP_REPO/skills/canonical-sdlc/SKILL.md"
SP_TMPL="$SP_REPO/agents-src/templates/skills/canonical-sdlc/SKILL.md.tmpl"
SP_ENGAGE="${BIONIC_HOOKS_DIR}/engage.sh"
SP_CLOSE="$SP_REPO/payload/scripts/close-out.sh"

# sp_cell <scale> <column> -> stdout of scale_cell; SP_RC its exit; SP_ERR its stderr
SP_RC=0; SP_ERR=""
sp_cell() {
  local out
  out="$(bash -c '. "$1/scale.sh" || exit 9; scale_cell "$2" "$3"' _ "$SP_LIB" "$1" "$2" 2>"$SANDBOX/.sp-err")"
  SP_RC=$?
  SP_ERR="$(cat "$SANDBOX/.sp-err" 2>/dev/null)"
  printf '%s' "$out"
}

# ============================================================================
section "§CELL — one table, three rows, seven columns, one reader (D25)"
# ============================================================================

SP_COLUMNS="patrol rigor writers regression branch integrate dealing"
SP_WANT_task="no single 3 no any pr piece"
SP_WANT_wave="yes double uncapped yes wave/<NN>-<slug> merge piece+whole"
SP_WANT_epic="yes double uncapped no epic/<NN>-<slug> merge piece"
for sp_s in task wave epic; do
  eval "sp_want=\$SP_WANT_$sp_s"
  set -- $sp_want
  for sp_c in $SP_COLUMNS; do
    sp_got="$(sp_cell "$sp_s" "$sp_c")"
    expect_eq "C.$sp_s.$sp_c — scale_cell $sp_s $sp_c" "$1" "$sp_got"
    shift
  done
done

sp_got="$(sp_cell task patrol)"
expect_eq "C.rc0 a known cell exits 0" "0" "$SP_RC"
sp_got="$(sp_cell sprint patrol)"
expect_eq "C.u1 a scale the table does not hold exits 1" "1" "$SP_RC"
expect_empty "C.u2 …and prints no cell" "$sp_got"
expect_contains "C.u3 …and its line names the fix" "use task, wave or epic" "$SP_ERR"
sp_got="$(sp_cell task colour)"
expect_eq "C.u4 a column the table does not hold exits 1" "1" "$SP_RC"
expect_empty "C.u5 …and prints no cell" "$sp_got"
expect_contains "C.u6 …and its line names every column" "use patrol, rigor, writers, regression, branch, integrate or dealing" "$SP_ERR"

# ============================================================================
section "§TASK — a task-scale fixture at every reader (AC-5.1)"
# ============================================================================

# (1) ENGAGEMENT ARMS NO PATROL AT TASK SCALE. A planless root holding one live task-scale run:
# the engagement binds it (the positive on the marker) and writes no stamp; the same root shape
# at wave scale writes one (the pair, so the absence is the scale's and not the fixture's).
sp_engage_root() {  # <name> <scale> -> root holding one fresh open plan at that scale
  local r p
  mkdir -p "$SANDBOX/engage-$1/.bionic/tmp" "$SANDBOX/engage-$1/.bionic/docs/plans"
  r="$(cd "$SANDBOX/engage-$1" && pwd -P)"
  p="$r/.bionic/docs/plans/$1.plan.md"
  printf -- '---\ncanonical_sdlc_version: 14\nscale: %s\n---\n\n## SDLC State\n\ncurrent: 4\n\n- Step 4: tasks in flight\n' "$2" > "$p"
  printf '%s' "$r"
}
sp_engage() {  # <sid> <root>
  local payload
  payload="$(jq -nc --arg s "$1" --arg c "$2" \
    '{session_id:$s,prompt_id:"p-1",transcript_path:"/dev/null",cwd:$c,
      permission_mode:"default",hook_event_name:"PreToolUse",
      tool_name:"Skill",tool_input:{skill:"bionic:canonical-sdlc"},tool_use_id:"toolu_sp"}')"
  env -u CLAUDE_PROJECT_DIR CLAUDE_CODE_SESSION_ID="$1" bash "$SP_ENGAGE" <<< "$payload" >/dev/null 2>&1
}
sp_plan_of() { sed -n 's/^plan=//p' "$1/.bionic/tmp/engaged-$2.state" 2>/dev/null | head -1; }
SP_ESID="5ca1e0e1-1111-2222-3333-444444444444"

SP_ET="$(sp_engage_root etask task)"
sp_engage "$SP_ESID" "$SP_ET"
expect_eq "T.e1 engagement at scale: task binds the task-scale run" "$SP_ET/.bionic/docs/plans/etask.plan.md" "$(sp_plan_of "$SP_ET" "$SP_ESID")"
expect_false "T.e2 …and writes no Patrol stamp" test -e "$SP_ET/.bionic/tmp/patrol-$SP_ESID.state"
SP_EW="$(sp_engage_root ewave wave)"
sp_engage "$SP_ESID" "$SP_EW"
expect_eq "T.e3 the pair: engagement at scale: wave binds its run" "$SP_EW/.bionic/docs/plans/ewave.plan.md" "$(sp_plan_of "$SP_EW" "$SP_ESID")"
expect_true "T.e4 …and arms the stamp, as today" test -f "$SP_EW/.bionic/tmp/patrol-$SP_ESID.state"

# (2) THE DEALING: `facts_owed single task` deals one critic — every question to bionic:critic, a
# piece read each and no whole read; at wave the code questions owe a whole read too.
sp_owed() { bash -c '. "$1/proof.sh" || exit 9; facts_owed "$2" "$3"' _ "$SP_LIB" "$1" "$2" 2>/dev/null; }
SP_OT="$(sp_owed single task)"
expect_eq "T.d1 facts_owed single task deals three questions" "3" "$(printf '%s\n' "$SP_OT" | grep -c '^review	')"
expect_eq "T.d2 …each to bionic:critic" "bionic:critic" "$(printf '%s\n' "$SP_OT" | awk -F'\t' '$1 == "review" { print $3 }' | sort -u)"
expect_eq "T.d3 …each a piece read, no whole read" "piece" "$(printf '%s\n' "$SP_OT" | awk -F'\t' '$1 == "review" { print $4 }' | sort -u)"
SP_OW="$(sp_owed single wave)"
expect_eq "T.d4 the pair: at wave the two code questions owe a whole read" "2" "$(printf '%s\n' "$SP_OW" | awk -F'\t' '$4 == "whole"' | grep -c .)"
SP_OD="$(sp_owed double task)"
expect_eq "T.d5 a flag that raises task to double is still dealt: the auditor takes evidence" "bionic:auditor" "$(printf '%s\n' "$SP_OD" | awk -F'\t' '$2 == "evidence" { print $3 }')"
expect_eq "T.d6 a scale the profile does not hold deals nothing" "" "$(sp_owed single sprint)"

# (3) THE WALL: a task-scale plan with no person's cap holds three writers. No Patrol stamp is
# planted: at task scale the arming wall does not apply, so the admissions below are the budget
# wall's verdict alone. The wave-scale pair with the same missing stamp is refused for it.
sp_task_repo() {  # <name> -> make_repo's plan at scale: task, its Patrol stamp removed
  local r p
  r="$(make_repo "$1" yes)"
  write_attestation "$r" "$SID_A"
  p="$r/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
  sed 's/^scale: wave$/scale: task/' "$p" > "$p.tmp" && mv "$p.tmp" "$p"
  rm -f "$r/.bionic/tmp/patrol-$SID_A.state"
  printf '%s' "$r"
}
SP_NONE="$SANDBOX/.sp-none.jsonl"
mk_transcript "$SP_NONE" none

REPO="$(sp_task_repo sp-w3)"
expect_eq "T.w0 the fixture really is task-scale" "yes" \
  "$(grep -q '^scale: task$' "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md" && echo yes || echo no)"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
s22_roster_row "$REPO" "$SID_A" "W-TWO"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "W-THREE" "claude-sonnet-5" "$SP_NONE" "implementor")"
expect_eq "T.w1 two writers open at task scale, no stamp → the third is ADMITTED (no arming wall)" "allow" "$GATE_VERDICT"
REPO="$(sp_task_repo sp-w4)"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
s22_roster_row "$REPO" "$SID_A" "W-TWO"
s22_roster_row "$REPO" "$SID_A" "W-THREE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "W-FOUR" "claude-sonnet-5" "$SP_NONE" "implementor")"
expect_eq "T.w2 three writers open at task scale → the fourth is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "T.w3 …by the budget wall, at the scale's cap" "writers: budget=3 open=3 with-this-dispatch=4" "$GATE_VERR"
expect_contains "T.w4 …which names the cap's source, the scale profile" "the task scale's writer cap" "$GATE_VERR"
expect_absent "T.w5 …and never for a Patrol stamp" "no Patrol stamp exists" "$GATE_VERR"
s22_set_budget "$REPO" "writers=5 source=user"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "W-FOUR" "claude-sonnet-5" "$SP_NONE" "implementor")"
expect_eq "T.w6 a person's writers=5 line overrides the cell: the fourth is ADMITTED" "allow" "$GATE_VERDICT"
REPO="$(make_repo sp-wave-nostamp yes)"
write_attestation "$REPO" "$SID_A"
rm -f "$REPO/.bionic/tmp/patrol-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "W-ONE" "claude-sonnet-5" "$SP_NONE" "implementor")"
expect_eq "T.w7 the pair: at wave scale the same missing stamp REFUSES" "deny" "$GATE_VERDICT"
expect_contains "T.w8 …for the Patrol" "no Patrol stamp exists" "$GATE_VERR"

# (4) CLOSE-OUT: a task-scale plan on `fix/x`, not yet merged. `check` refuses no branch shape,
# and its integrate act is the PR: the merge line carries the `gh pr create` command for the
# working branch against the integration branch, and nothing is merged. The wave-scale pair on
# the same branch is refused for its shape. `run` recording the command is close-out.test.sh's
# ANY-BRANCH section (its fixtures carry the facts a close needs).
sp_co_root() {  # <name> <scale> -> a repository with main and an unmerged fix/x, and a plan at Step 8
  local d="$SANDBOX/co-$1" p
  mkdir -p "$d"
  (
    cd "$d" || exit 1
    git init -q -b main 2>/dev/null || { git init -q && git checkout -q -b main; }
    git config user.email t@example.com; git config user.name T
    echo a > f.txt; git add f.txt; git commit -qm seed
    git checkout -qb fix/x; echo b >> f.txt; git commit -qam fix; git checkout -q main
  ) >/dev/null 2>&1
  p="$d/.bionic/docs/plans/epic-99-test/fix-x.plan.md"
  mkdir -p "${p%/*}" "$d/.bionic/tmp"
  printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: bugfix\nrigor: single\nscale: %s\n---\n\n# Fix x\n\n## SDLC State\n\nintegration-branch: main\nworking-branch: fix/x\ncurrent: 8\n' "$2" > "$p"
  printf '%s' "$d"
}
SP_CT="$(sp_co_root task task)"
SP_MAIN0="$(git -C "$SP_CT" rev-parse main)"
SP_CO_OUT="$(cd "$SP_CT" && bash "$SP_CLOSE" "$SP_CT/.bionic/docs/plans/epic-99-test/fix-x.plan.md" check 2>&1)"
SP_CO_RC=$?
expect_eq "T.c1 close-out check on a task-scale fix/x exits 0" "0" "$SP_CO_RC"
expect_contains "T.c2 …and reaches its merge line" "merge: " "$SP_CO_OUT"
expect_absent "T.c3 …with no branch-shape refusal" "shaped" "$SP_CO_OUT"
expect_contains "T.c4 the integrate act is a PR: the line carries the command" "gh pr create --base main --head fix/x" "$SP_CO_OUT"
expect_absent "T.c5 …and does not refuse the unmerged branch" "WOULD REFUSE — fix/x" "$SP_CO_OUT"
expect_eq "T.c6 …and merges nothing" "$SP_MAIN0" "$(git -C "$SP_CT" rev-parse main)"
SP_CW="$(sp_co_root wave wave)"
SP_CO_OUT="$(cd "$SP_CW" && bash "$SP_CLOSE" "$SP_CW/.bionic/docs/plans/epic-99-test/fix-x.plan.md" check 2>&1)"
expect_contains "T.c7 the pair: at wave scale fix/x is refused for its shape" "is not wave/<NN>-<slug> shaped" "$SP_CO_OUT"

# ============================================================================
section "§TABLE — SKILL.md's scale table is the library's rows (AC-5.3)"
# ============================================================================

# sp_table <file> -> one line per table row, `<scale>\t<col>=<cell>\t…`, the header's labels
# lowercased as the column names and backticks stripped from each cell.
sp_table() {
  awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); gsub(/`/, "", s); return s }
    /^\| Scale \|/ { for (i = 2; i < NF; i++) h[i] = tolower(trim($i)); n = NF; inT = 1; next }
    inT && /^\|---/ { next }
    inT && /^\|/ { s = trim($2); line = s; for (i = 3; i < n; i++) line = line "\t" h[i] "=" trim($i); print line; next }
    inT { exit }' "$1"
}
SP_ROWS="$(sp_table "$SP_SKILL")"
expect_eq "B.0 the table carries exactly the three scales" "task wave epic" "$(printf '%s\n' "$SP_ROWS" | cut -f1 | tr '\n' ' ' | sed 's/ $//')"
for sp_s in task wave epic; do
  sp_row="$(printf '%s\n' "$SP_ROWS" | awk -F'\t' -v s="$sp_s" '$1 == s')"
  for sp_c in $SP_COLUMNS; do
    sp_doc="$(printf '%s\n' "$sp_row" | tr '\t' '\n' | sed -n "s/^$sp_c=//p")"
    sp_lib="$(sp_cell "$sp_s" "$sp_c")"
    # Two empties are not agreement: each side names its own absence.
    expect_eq "B.$sp_s.$sp_c — the doctrine's cell is the library's" "${sp_lib:-<no library cell>}" "${sp_doc:-<no doctrine cell>}"
  done
done
expect_eq "B.t the template's table is the same table" "$SP_ROWS" "$(sp_table "$SP_TMPL")"

expect_eq "B.p1 the task row is there to read" "1" "$(/usr/bin/grep -c '^| `task` |' "$SP_SKILL")"
expect_eq "B.p2 'Full set, compressed' is gone" "0" "$(/usr/bin/grep -c 'Full set, compressed' "$SP_SKILL")"
expect_contains "B.r the rigor default sentence reads the task row" 'at `task`, `single` unless a flag raises it; at `wave` and above, `double`' "$(cat "$SP_SKILL")"
# THE BYTES DO NOT GROW (net zero): SKILL.md held 22819 bytes at the wave head this row started
# from (fda9f0fc); the table's new cells pay with the phrase and the shortened sentence.
SP_BYTES="$(wc -c < "$SP_SKILL" | tr -d ' ')"
expect_true "B.n SKILL.md is not larger than 22819 bytes (it is $SP_BYTES)" test "$SP_BYTES" -le 22819

finish
