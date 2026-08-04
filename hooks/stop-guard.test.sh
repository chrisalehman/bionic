#!/bin/bash
# Tests for hooks/stop-guard.sh — ONE script, TWO arms (epic-15 wave-01R).
#
#   Bash arm    (PreToolUse|Bash)     RECORDS an observation run into versioned
#                                     state. Never blocks anything, ever.
#   TaskStop arm (PreToolUse|TaskStop) GATES the stop: D-1 activity-boundary
#                                     freshness, D-2 consume-on-stop.
#
# Serves AC-3 (the recording half), AC-4 (D-1), AC-5 (D-2), and the stop-side
# rows of AC-8/AC-10.
#
# HERMETIC. Every payload is crafted and piped straight into the NEW script;
# nothing here invokes the TaskStop tool, touches the live installed hooks, or
# writes outside a mktemp'd sandbox.
#
# Usage: bash hooks/stop-guard.test.sh

set -uo pipefail

GUARD="$(cd "$(dirname "$0")" && pwd)/stop-guard.sh"
PASS=0
FAIL=0
TOTAL=0

# `cd … && pwd` normalizes the path: $TMPDIR carries a trailing slash on
# macOS, and a doubled separator would slugify differently from the cwd the
# script under test actually sees.
SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/stop-guard-test.XXXXXX")" && pwd)"
trap 'rm -rf "$SANDBOX"' EXIT

# ---------- assertions ----------

ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }

expect_status()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected exit $2, got $3"; fi; }
expect_contains() { if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else no "$1" "missing: $2"; fi; }
expect_matches()  { if printf '%s' "$3" | grep -qE -- "$2"; then ok "$1"; else no "$1" "no match: $2"; fi; }
expect_absent()   { if printf '%s' "$3" | grep -qF -- "$2"; then no "$1" "unexpectedly present: $2"; else ok "$1"; fi; }
expect_empty()    { if [ -z "$2" ]; then ok "$1"; else no "$1" "expected no output, got: $2"; fi; }
expect_file()     { if [ -f "$2" ]; then ok "$1"; else no "$1" "no such file: $2"; fi; }
expect_no_file()  { if [ -f "$2" ]; then no "$1" "file exists but should not: $2"; else ok "$1"; fi; }

# ---------- fixtures ----------
#
# FIXTURE FIDELITY (declared per checklist §A / spec §Design).
#
# Source: .bionic/docs/record/epic-15-kill-interception-experiment.md, CLI
# 2.1.220 verbatim captures.
#
#   * PreToolUse|TaskStop payload — FAITHFUL to §2.2, field for field:
#     session_id, transcript_path, cwd, prompt_id, permission_mode, effort,
#     hook_event_name, tool_name, tool_input.task_id, tool_use_id. Critically
#     §2.2 establishes that `tool_input.task_id` is THE CALLER'S STRING AS TYPED
#     ("victim", a name) and that no resolved agent id is present in the
#     payload — the property every resolution test here depends on.
#   * PreToolUse|Bash payload — same base fields with
#     `tool_input.command`, per the same PreToolUse builder (§2.1 shows Bash
#     PreToolUse firing through the identical pipeline; §2.9 captures one).
#   * transcript_path → session directory — FAITHFUL to §2.5, which captures
#     `agent_transcript_path` as "<transcript-dir>/<session-id>/subagents/agent-<id>.jsonl".
#   * meta.json — FAITHFUL to §2.8 (verbatim field set), plus the named
#     in-process-teammate fields read live from this machine on 2026-08-04.
#   * SYNTHESIZED and declared: session ids, agent ids, plan text, message text.
#     None is a platform surface.
#
# NOT modelled, deliberately: no PostToolUse payload appears in this suite. §2.3
# shows PostToolUse is where the RESOLVED id lives — but the gate must decide
# BEFORE the stop happens, so it only ever sees §2.2's unresolved reference.

mk_bash_payload() {  # <sid> <transcript> <cwd> <command>
  jq -n --arg s "$1" --arg t "$2" --arg c "$3" --arg cmd "$4" \
    '{session_id:$s, transcript_path:$t, cwd:$c,
      prompt_id:"f3cd7d62-305d-47ed-9eaf-46fb12d4f4ed",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PreToolUse", tool_name:"Bash",
      tool_input:{command:$cmd}, tool_use_id:"toolu_018jyjgop7KMxP6yKtoAWWtB"}'
}

mk_stop_payload() {  # <sid> <transcript> <cwd> <task_id>
  jq -n --arg s "$1" --arg t "$2" --arg c "$3" --arg id "$4" \
    '{session_id:$s, transcript_path:$t, cwd:$c,
      prompt_id:"f3cd7d62-305d-47ed-9eaf-46fb12d4f4ed",
      permission_mode:"bypassPermissions", effort:{level:"high"},
      hook_event_name:"PreToolUse", tool_name:"TaskStop",
      tool_input:{task_id:$id}, tool_use_id:"toolu_018jyjgop7KMxP6yKtoAWWtB"}'
}

GUARD_OUT=""; GUARD_ERR=""; GUARD_ST=0
run_guard() {  # <payload-json>
  GUARD_OUT=$(printf '%s' "$1" | bash "$GUARD" 2>"$SANDBOX/.err"); GUARD_ST=$?
  GUARD_ERR=$(cat "$SANDBOX/.err")
  return 0
}

SID_A="6c85684c-9588-45a0-bd26-e8c46956c94f"
SID_B="11111111-2222-3333-4444-555555555555"

# make_world <name> <active-wave:yes|no> — echoes "<repo>|<transcript>|<subagents>"
make_world() {
  local name="$1" wave="$2"
  local home="$SANDBOX/$name/home" repo="$SANDBOX/$name/repo"
  local proj="$home/.claude/projects/p-$name"
  mkdir -p "$repo" "$proj/$SID_A/subagents" "$proj/$SID_B/subagents"
  : > "$proj/$SID_A.jsonl"
  : > "$proj/$SID_B.jsonl"
  git -C "$repo" init -q 2>/dev/null
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name "T"
  echo seed > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm seed 2>/dev/null
  if [ "$wave" = "yes" ]; then
    mkdir -p "$repo/.bionic/docs/plans/epic-99-test"
    cat > "$repo/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md" <<'PLAN'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 13
intent: build
rigor: audited
scale: wave
---

# Test wave plan

## SDLC State

integration-branch: main
current: 4

- Step 4: slices in flight
PLAN
  fi
  printf '%s|%s|%s\n' "$repo" "$proj/$SID_A.jsonl" "$proj/$SID_A/subagents"
}

# plant_agent <subagents-dir> <agent-id> <name> [mtime-touch]
plant_agent() {
  local dir="$1" aid="$2" aname="$3" touchts="${4:-}"
  printf '{"agentType":"general-purpose","description":"a test agent","name":"%s","toolUseId":"toolu_01TEST","spawnDepth":0,"model":"opus","taskKind":"in_process_teammate"}\n' \
    "$aname" > "$dir/agent-$aid.meta.json"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}\n' \
    > "$dir/agent-$aid.jsonl"
  [ -n "$touchts" ] && touch -t "$touchts" "$dir/agent-$aid.jsonl"
  return 0
}

STATE_REL=".bionic/tmp/stop-check.state"

observe() {  # <sid> <transcript> <repo> <typed-target>
  run_guard "$(mk_bash_payload "$1" "$2" "$3" "bash ~/.claude/hooks/stop-check.sh $4")"
}

# ============================================================
echo ""
echo "=== Section 1: the hot path — relevance before any plan walk (checklist A7) ==="
# ============================================================

IFS='|' read -r W1_REPO W1_TR W1_SUB <<< "$(make_world w1 yes)"
plant_agent "$W1_SUB" "aquiet-reviewer-deadbeefdeadbeef" "quiet-reviewer"

run_guard "$(jq -n --arg c "$W1_REPO" '{session_id:"x", cwd:$c, hook_event_name:"PreToolUse", tool_name:"Read", tool_input:{file_path:"/tmp/x"}}')"
expect_status "an unrelated TOOL passes untouched" 0 "$GUARD_ST"
expect_no_file "an unrelated tool writes no state" "$W1_REPO/$STATE_REL"

run_guard "$(mk_bash_payload "$SID_A" "$W1_TR" "$W1_REPO" "ls -la && git status")"
expect_status "an unrelated Bash command passes untouched" 0 "$GUARD_ST"
expect_no_file "an unrelated Bash command writes no state" "$W1_REPO/$STATE_REL"

run_guard "$(jq -n --arg c "$W1_REPO" '{session_id:"x", cwd:$c, hook_event_name:"PreToolUse", tool_name:"Agent", tool_input:{prompt:"go"}}')"
expect_status "the Agent tool is not this gate's business" 0 "$GUARD_ST"

# Static order pin: the cheap relevance test must precede the plan-directory
# walk in the source, not merely produce the same answer (arch-perf F8/F9 — the
# defect was cost, which behavior alone cannot detect).
_rel_line=$(grep -nE "grep -qF? '?stop-check\.sh" "$GUARD" | head -1 | cut -d: -f1)
_walk_line=$(grep -nE '^[[:space:]]*(PLAN=|find )' "$GUARD" | head -1 | cut -d: -f1)
if [ -n "$_rel_line" ] && [ -n "$_walk_line" ] && [ "$_rel_line" -lt "$_walk_line" ]; then
  ok "relevance check precedes the plan walk in source order"
else
  no "relevance check precedes the plan walk in source order" "relevance@${_rel_line:-none} walk@${_walk_line:-none}"
fi

# ============================================================
echo ""
echo "=== Section 2: the Bash arm records the observation (AC-3) ==="
# ============================================================

observe "$SID_A" "$W1_TR" "$W1_REPO" "quiet-reviewer"
expect_status "recording an observation never blocks" 0 "$GUARD_ST"
expect_file "an observation run writes state" "$W1_REPO/$STATE_REL"
STATE=$(cat "$W1_REPO/$STATE_REL" 2>/dev/null)
expect_contains "the record names the RESOLVED target" "aquiet-reviewer-deadbeefdeadbeef" "$STATE"
expect_contains "the record names the observing session" "$SID_A" "$STATE"
expect_matches "the record carries the activity level seen (log mtime)" 'mtime=[0-9]+' "$STATE"
expect_matches "the record carries the activity level seen (log size)" 'size=[0-9]+' "$STATE"

# COMMAND-WORD DISCIPLINE. A mention is not a run (checklist §C, the "recorded a
# look but nothing ran" class). Each of these must record NOTHING.
for mention in \
  "cat hooks/stop-check.sh" \
  "echo stop-check.sh quiet-reviewer" \
  "grep -n stop-check.sh hooks/stop-guard.sh" \
  "# bash ~/.claude/hooks/stop-check.sh quiet-reviewer"
do
  IFS='|' read -r M_REPO M_TR M_SUB <<< "$(make_world "m$RANDOM" yes)"
  plant_agent "$M_SUB" "aquiet-reviewer-deadbeefdeadbeef" "quiet-reviewer"
  run_guard "$(mk_bash_payload "$SID_A" "$M_TR" "$M_REPO" "$mention")"
  expect_no_file "a mention is not a run: ${mention:0:34}" "$M_REPO/$STATE_REL"
done

# Two real runs in one command line record two observations.
IFS='|' read -r W2_REPO W2_TR W2_SUB <<< "$(make_world w2 yes)"
plant_agent "$W2_SUB" "aone-1111111111111111" "one"
plant_agent "$W2_SUB" "atwo-2222222222222222" "two"
run_guard "$(mk_bash_payload "$SID_A" "$W2_TR" "$W2_REPO" \
  "bash ~/.claude/hooks/stop-check.sh one && bash ~/.claude/hooks/stop-check.sh two")"
STATE=$(cat "$W2_REPO/$STATE_REL" 2>/dev/null)
expect_contains "two chained runs record the first target" "aone-1111111111111111" "$STATE"
expect_contains "two chained runs record the second target" "atwo-2222222222222222" "$STATE"

# An unresolvable target records nothing and still never blocks.
run_guard "$(mk_bash_payload "$SID_A" "$W2_TR" "$W2_REPO" "bash ~/.claude/hooks/stop-check.sh ghost")"
expect_status "an unresolvable observation target never blocks" 0 "$GUARD_ST"
expect_absent "an unresolvable observation target records nothing" "ghost" "$(cat "$W2_REPO/$STATE_REL")"

# C1 (Step-6 correctness review, slice 4/7): AN OBSERVATION THAT PRINTED NO
# EVIDENCE MUST RECORD NOTHING. The recorder fires PreToolUse — before the
# observation runs — so it cannot read the producer's outcome. It must therefore
# resolve against THE SAME DIRECTORY SET THE OPERATOR SAW: every session of this
# project, then the all-projects fallback (hooks/stop-check.sh:103-133). Where
# that set is ambiguous the operator was shown a candidate list and no evidence
# tier at all, and a record written anyway attests to an examination that never
# produced anything — the "recorded a look but nothing ran" class (checklist §C)
# in a new shape.
IFS='|' read -r C1_REPO C1_TR C1_SUB <<< "$(make_world c1 yes)"
C1_OTHER="${C1_TR%/*}/$SID_B/subagents"
plant_agent "$C1_SUB"  "aworker-1111111111111111" "worker"
plant_agent "$C1_OTHER" "aworker-2222222222222222" "worker"
observe "$SID_A" "$C1_TR" "$C1_REPO" "worker"
expect_status "an ambiguous observation target never blocks" 0 "$GUARD_ST"
if [ -f "$C1_REPO/$STATE_REL" ]; then
  expect_absent "a name ambiguous ACROSS SESSIONS records nothing (C1)" \
    "target=aworker-" "$(cat "$C1_REPO/$STATE_REL")"
else
  ok "a name ambiguous ACROSS SESSIONS records nothing (C1)"
fi
# …and the stop of that target is therefore refused, rather than discharged by a
# record the operator's own output contradicts.
run_guard "$(mk_stop_payload "$SID_A" "$C1_TR" "$C1_REPO" "worker")"
expect_status "the stop after an evidence-less observation is REFUSED (C1)" 2 "$GUARD_ST"

# The mirror image, fail-closed: a target that resolves ONLY in another session
# is visible to the operator's observation but unstoppable from here, so no
# dischargeable record may be written for it either.
IFS='|' read -r C1B_REPO C1B_TR C1B_SUB <<< "$(make_world c1b yes)"
plant_agent "${C1B_TR%/*}/$SID_B/subagents" "aforeign-3333333333333333" "foreign"
observe "$SID_A" "$C1B_TR" "$C1B_REPO" "foreign"
if [ -f "$C1B_REPO/$STATE_REL" ]; then
  expect_absent "a target resolving only in ANOTHER session records nothing (C1)" \
    "target=aforeign-3333333333333333" "$(cat "$C1B_REPO/$STATE_REL")"
else
  ok "a target resolving only in ANOTHER session records nothing (C1)"
fi

# Positive pair (a wall that refuses everything is equally broken, TDD §9):
# unique in the operator's set AND in this session still records.
IFS='|' read -r C1C_REPO C1C_TR C1C_SUB <<< "$(make_world c1c yes)"
plant_agent "$C1C_SUB" "asolo-4444444444444444" "solo"
observe "$SID_A" "$C1C_TR" "$C1C_REPO" "solo"
expect_contains "an unambiguous target still records (C1 positive pair)" \
  "target=asolo-4444444444444444" "$(cat "$C1C_REPO/$STATE_REL" 2>/dev/null)"

# P2 (Step-6 performance review, slice 4/7): the observation state must not grow
# without bound. Records written by OTHER sessions were pruned by nothing, and
# both arms walk the file line by line at ~3ms per record, so a multi-session
# wave paid a growing tax on every observation and every stop.
IFS='|' read -r P2_REPO P2_TR P2_SUB <<< "$(make_world p2 yes)"
plant_agent "$P2_SUB" "akeeper-7777777777777777" "keeper"
mkdir -p "$P2_REPO/.bionic/tmp"
{
  printf '# bionic observation records — schema stop-check-state/v1\n'
  _i=0
  while [ "$_i" -lt 300 ]; do
    # live-looking foreign records: their session directory still exists, so only
    # the hard cap can drop them
    printf 'v1|session=dead-%s|target=aghost-%s|typed=ghost|log=%s/agent-aghost-%s.jsonl|mtime=1|size=1\n' \
      "$_i" "$_i" "$P2_SUB" "$_i"
    _i=$((_i + 1))
  done
} > "$P2_REPO/$STATE_REL"
observe "$SID_A" "$P2_TR" "$P2_REPO" "keeper"
P2_COUNT=$(grep -c '^v1|' "$P2_REPO/$STATE_REL" 2>/dev/null || echo 0)
if [ "$P2_COUNT" -le 200 ]; then
  ok "the observation state is bounded, not unbounded (P2): $P2_COUNT records"
else
  no "the observation state is bounded, not unbounded (P2)" "$P2_COUNT records retained"
fi
expect_contains "the record just written survives the bound" \
  "akeeper-7777777777777777" "$(cat "$P2_REPO/$STATE_REL" 2>/dev/null)"

# A record whose session's subagents directory is gone can never discharge
# anything — the gate resolves targets only through that directory — so it is
# inert weight and gets dropped on the next write.
IFS='|' read -r P2B_REPO P2B_TR P2B_SUB <<< "$(make_world p2b yes)"
plant_agent "$P2B_SUB" "alive-8888888888888888" "alive"
mkdir -p "$P2B_REPO/.bionic/tmp"
printf '# bionic observation records — schema stop-check-state/v1\nv1|session=gone|target=avanished-9999999999999999|typed=vanished|log=/no/such/session/subagents/agent-avanished-9999999999999999.jsonl|mtime=1|size=1\n' \
  > "$P2B_REPO/$STATE_REL"
observe "$SID_A" "$P2B_TR" "$P2B_REPO" "alive"
expect_absent "a record whose session directory is gone is pruned (P2)" \
  "avanished-9999999999999999" "$(cat "$P2B_REPO/$STATE_REL" 2>/dev/null)"
expect_contains "pruning does not disturb the record being written" \
  "alive-8888888888888888" "$(cat "$P2B_REPO/$STATE_REL" 2>/dev/null)"

# Credential-leak class (§8, AC-8): no command text reaches the state file.
run_guard "$(mk_bash_payload "$SID_A" "$W2_TR" "$W2_REPO" \
  "AWS_SECRET=hunter2 bash ~/.claude/hooks/stop-check.sh one")"
expect_absent "no command text reaches the state file" "hunter2" "$(cat "$W2_REPO/$STATE_REL")"

# ============================================================
echo ""
echo "=== Section 3: the observation record is VERSIONED and key-addressed (checklist A6) ==="
# ============================================================

IFS='|' read -r W3_REPO W3_TR W3_SUB <<< "$(make_world w3 yes)"
plant_agent "$W3_SUB" "atarget-3333333333333333" "target"
observe "$SID_A" "$W3_TR" "$W3_REPO" "target"
STATE=$(cat "$W3_REPO/$STATE_REL")
expect_matches "the record leads with a schema version token" '(^|\|)v1(\||$)' "$STATE"
expect_matches "fields are key=value, not positional" 'target=' "$STATE"

# Forward compatibility: one MORE field must not break the reader (A6 — the
# defect was a fixed-field-order parser breaking undiagnosably on a new field).
sed -i.bak 's/$/|futurefield=whatever/' "$W3_REPO/$STATE_REL"
rm -f "$W3_REPO/$STATE_REL.bak"
run_guard "$(mk_stop_payload "$SID_A" "$W3_TR" "$W3_REPO" "target")"
expect_status "an unknown EXTRA field does not break the reader" 0 "$GUARD_ST"

# An unknown schema VERSION is not guessed at — it is refused.
observe "$SID_A" "$W3_TR" "$W3_REPO" "target"
sed -i.bak 's/^v1|/v9|/' "$W3_REPO/$STATE_REL"; rm -f "$W3_REPO/$STATE_REL.bak"
run_guard "$(mk_stop_payload "$SID_A" "$W3_TR" "$W3_REPO" "target")"
expect_status "an unknown schema VERSION refuses the stop" 2 "$GUARD_ST"

# ============================================================
echo ""
echo "=== Section 4: fail directions at the stop gate (AC-10, TDD §7) ==="
# ============================================================

# --- before the active-wave verdict: OPEN and SILENT ---
IFS='|' read -r N_REPO N_TR N_SUB <<< "$(make_world nowave no)"
plant_agent "$N_SUB" "aidle-4444444444444444" "idle"
run_guard "$(mk_stop_payload "$SID_A" "$N_TR" "$N_REPO" "idle")"
expect_status "no active wave: the stop passes" 0 "$GUARD_ST"
expect_empty "no active wave: the gate is silent" "$GUARD_ERR"

run_guard "$(jq -n --arg c "$N_REPO" '{cwd:$c, hook_event_name:"PreToolUse", tool_name:"TaskStop", tool_input:{task_id:"idle"}}')"
expect_status "no active wave + no session key: still open (pre-verdict)" 0 "$GUARD_ST"
expect_empty "no active wave + no session key: still silent" "$GUARD_ERR"

# A plan that exists but names no step is not a run in progress. This is the
# rung BELOW "no plan at all", and it needs its own case: a gate that treated
# any plan file as an active wave would wall every repo that has ever held one.
IFS='|' read -r P_REPO P_TR P_SUB <<< "$(make_world plannostep yes)"
plant_agent "$P_SUB" "aidle-4444444444444444" "idle"
sed -i.bak 's/^current: 4$/current: pending/' "$P_REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
rm -f "$P_REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md.bak"
run_guard "$(mk_stop_payload "$SID_A" "$P_TR" "$P_REPO" "idle")"
expect_status "a plan with no valid current step is not an active wave: open" 0 "$GUARD_ST"
expect_empty "a plan with no valid current step: silent" "$GUARD_ERR"

# --- after the verdict: CLOSED and LOUD ---
IFS='|' read -r W4_REPO W4_TR W4_SUB <<< "$(make_world w4 yes)"
plant_agent "$W4_SUB" "aquiet-reviewer-deadbeefdeadbeef" "quiet-reviewer"

run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "quiet-reviewer")"
expect_status "active wave + no observation: REFUSED" 2 "$GUARD_ST"
expect_contains "the refusal names the observation command" "stop-check.sh" "$GUARD_ERR"
expect_contains "the fix command uses the INSTALL path, not a repo-relative one (A1)" \
  "~/.claude/hooks/stop-check.sh" "$GUARD_ERR"
expect_absent "the fix command is not repo-relative" "bash hooks/stop-check.sh" "$GUARD_ERR"
expect_contains "the refusal names the target as typed" "quiet-reviewer" "$GUARD_ERR"

run_guard "$(jq -n --arg c "$W4_REPO" --arg t "$W4_TR" \
  '{transcript_path:$t, cwd:$c, hook_event_name:"PreToolUse", tool_name:"TaskStop", tool_input:{task_id:"quiet-reviewer"}}')"
expect_status "active wave + payload missing its session key: REFUSED (closed)" 2 "$GUARD_ST"

run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "")"
expect_status "active wave + empty task_id: REFUSED" 2 "$GUARD_ST"

run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "no-such-agent")"
expect_status "active wave + unresolvable name: REFUSED" 2 "$GUARD_ST"
expect_contains "an unresolvable name says so" "unresolved" "$GUARD_ERR"

# Ambiguity: two live agents answering to the same name in one session.
plant_agent "$W4_SUB" "adouble-5555555555555555" "twin"
plant_agent "$W4_SUB" "adouble-6666666666666666" "twin"
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "twin")"
expect_status "active wave + ambiguous name: REFUSED" 2 "$GUARD_ST"
expect_contains "an ambiguous name says so" "ambiguous" "$GUARD_ERR"

# A plan with CR-only line endings is still a plan. `tr -d` on those separators
# collapses the file to one line, the run-state marker goes unseen, and the gate
# quietly reports "no wave" on a repo mid-wave — the fail-dangerous shape that
# bypassed the evidence gate for a whole wave (.claude/rules/hook-authoring.md).
IFS='|' read -r CR_REPO CR_TR CR_SUB <<< "$(make_world crplan yes)"
plant_agent "$CR_SUB" "acrlf-0123456789abcdef" "crlf"
CR_PLAN="$CR_REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
tr '\n' '\r' < "$CR_PLAN" > "$CR_PLAN.cr" && mv "$CR_PLAN.cr" "$CR_PLAN"
run_guard "$(mk_stop_payload "$SID_A" "$CR_TR" "$CR_REPO" "crlf")"
expect_status "a CR-only plan is still read: the wave is still detected" 2 "$GUARD_ST"

# The positive pair — a wall that refuses everything is equally broken (§9).
observe "$SID_A" "$W4_TR" "$W4_REPO" "quiet-reviewer"
run_guard "$(mk_stop_payload "$SID_A" "$W4_TR" "$W4_REPO" "quiet-reviewer")"
expect_status "active wave + fresh observation: PERMITTED" 0 "$GUARD_ST"
expect_empty "a permitted stop is silent" "$GUARD_ERR"

# A foreign session's observation is not mine.
IFS='|' read -r W5_REPO W5_TR W5_SUB <<< "$(make_world w5 yes)"
plant_agent "$W5_SUB" "aquiet-reviewer-deadbeefdeadbeef" "quiet-reviewer"
observe "$SID_B" "$W5_TR" "$W5_REPO" "quiet-reviewer"
run_guard "$(mk_stop_payload "$SID_A" "$W5_TR" "$W5_REPO" "quiet-reviewer")"
expect_status "another session's observation does not discharge my stop" 2 "$GUARD_ST"
expect_contains "the foreign-session refusal says whose it was" "session" "$GUARD_ERR"

# ============================================================
echo ""
echo "=== Section 5: D-1 — freshness by ACTIVITY BOUNDARY, no clocks (AC-4) ==="
# ============================================================

IFS='|' read -r D1_REPO D1_TR D1_SUB <<< "$(make_world d1 yes)"
plant_agent "$D1_SUB" "aworker-7777777777777777" "worker"

# STALE: the target wrote AFTER the observation. This is the founding incident
# (UC-5) and the flaw the v1 exchange-keyed design provably re-permitted.
observe "$SID_A" "$D1_TR" "$D1_REPO" "worker"
sleep 1
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"committed my work"}]}}\n' \
  >> "$D1_SUB/agent-aworker-7777777777777777.jsonl"
run_guard "$(mk_stop_payload "$SID_A" "$D1_TR" "$D1_REPO" "worker")"
expect_status "target wrote after the observation: REFUSED as stale" 2 "$GUARD_ST"
expect_contains "the staleness refusal names activity, not elapsed time" "since" "$GUARD_ERR"
expect_absent "the staleness refusal quotes no clock window" "seconds ago" "$GUARD_ERR"

# SUB-SECOND: a write inside the same mtime second still counts as activity.
IFS='|' read -r D1B_REPO D1B_TR D1B_SUB <<< "$(make_world d1b yes)"
plant_agent "$D1B_SUB" "aworker-8888888888888888" "worker"
observe "$SID_A" "$D1B_TR" "$D1B_REPO" "worker"
LOG="$D1B_SUB/agent-aworker-8888888888888888.jsonl"
MT=$(date -r "$LOG" +%Y%m%d%H%M.%S 2>/dev/null)
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"x"}]}}\n' >> "$LOG"
touch -t "$MT" "$LOG"   # restored to the SAME mtime second; only the size grew
run_guard "$(mk_stop_payload "$SID_A" "$D1B_TR" "$D1B_REPO" "worker")"
expect_status "a write within the same mtime second is still activity: REFUSED" 2 "$GUARD_ST"

# DORMANT, HOWEVER OLD: no clock may expire an honest observation.
IFS='|' read -r D2_REPO D2_TR D2_SUB <<< "$(make_world d1old yes)"
plant_agent "$D2_SUB" "asleeper-9999999999999999" "sleeper" "202601010000"
observe "$SID_A" "$D2_TR" "$D2_REPO" "sleeper"
touch -t 202601010000 "$D2_SUB/agent-asleeper-9999999999999999.jsonl"
run_guard "$(mk_stop_payload "$SID_A" "$D2_TR" "$D2_REPO" "sleeper")"
expect_status "dormant since the observation, however old: PERMITTED" 0 "$GUARD_ST"

# LONG-EXCHANGE, MULTI-AGENT (§9 — the configuration v1 never tested). One
# session, three agents, interleaved observations and stops, with one agent
# waking up mid-sequence.
IFS='|' read -r LX_REPO LX_TR LX_SUB <<< "$(make_world longx yes)"
plant_agent "$LX_SUB" "aalpha-aaaaaaaaaaaaaaaa" "alpha"
plant_agent "$LX_SUB" "abeta-bbbbbbbbbbbbbbbb"  "beta"
plant_agent "$LX_SUB" "agamma-cccccccccccccccc" "gamma"
observe "$SID_A" "$LX_TR" "$LX_REPO" "alpha"
observe "$SID_A" "$LX_TR" "$LX_REPO" "beta"
observe "$SID_A" "$LX_TR" "$LX_REPO" "gamma"
sleep 1
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"still here"}]}}\n' \
  >> "$LX_SUB/agent-abeta-bbbbbbbbbbbbbbbb.jsonl"
run_guard "$(mk_stop_payload "$SID_A" "$LX_TR" "$LX_REPO" "alpha")"
expect_status "long exchange: dormant alpha still stoppable" 0 "$GUARD_ST"
run_guard "$(mk_stop_payload "$SID_A" "$LX_TR" "$LX_REPO" "beta")"
expect_status "long exchange: beta woke up — its earlier observation is stale" 2 "$GUARD_ST"
run_guard "$(mk_stop_payload "$SID_A" "$LX_TR" "$LX_REPO" "gamma")"
expect_status "long exchange: gamma's own observation survives the others" 0 "$GUARD_ST"

# ============================================================
echo ""
echo "=== Section 6: D-2 — one observation, one stop (AC-5) ==="
# ============================================================

IFS='|' read -r D2R_REPO D2R_TR D2R_SUB <<< "$(make_world d2 yes)"
plant_agent "$D2R_SUB" "arunner-dddddddddddddddd" "runner"
observe "$SID_A" "$D2R_TR" "$D2R_REPO" "runner"
run_guard "$(mk_stop_payload "$SID_A" "$D2R_TR" "$D2R_REPO" "runner")"
expect_status "the first stop is permitted" 0 "$GUARD_ST"
expect_absent "a permitted stop CONSUMES its observation" \
  "arunner-dddddddddddddddd" "$(cat "$D2R_REPO/$STATE_REL" 2>/dev/null)"

run_guard "$(mk_stop_payload "$SID_A" "$D2R_TR" "$D2R_REPO" "runner")"
expect_status "a second stop without a fresh observation: REFUSED" 2 "$GUARD_ST"

observe "$SID_A" "$D2R_TR" "$D2R_REPO" "runner"
run_guard "$(mk_stop_payload "$SID_A" "$D2R_TR" "$D2R_REPO" "runner")"
expect_status "re-observing re-arms the stop" 0 "$GUARD_ST"

# A REFUSED stop consumes nothing — nothing was stopped.
IFS='|' read -r D2B_REPO D2B_TR D2B_SUB <<< "$(make_world d2b yes)"
plant_agent "$D2B_SUB" "abusy-eeeeeeeeeeeeeeee" "busy"
observe "$SID_A" "$D2B_TR" "$D2B_REPO" "busy"
sleep 1
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"awake"}]}}\n' \
  >> "$D2B_SUB/agent-abusy-eeeeeeeeeeeeeeee.jsonl"
run_guard "$(mk_stop_payload "$SID_A" "$D2B_TR" "$D2B_REPO" "busy")"
expect_status "the stale stop is refused" 2 "$GUARD_ST"
expect_contains "a REFUSED stop consumes nothing" \
  "abusy-eeeeeeeeeeeeeeee" "$(cat "$D2B_REPO/$STATE_REL" 2>/dev/null)"

# ============================================================
echo ""
echo "=== Section 6a: the refusal's Fix line is runnable AS PRINTED (R2) ==="
# ============================================================
#
# The ownership table names one test for fix-command text across TWO rendering
# gates, and it drove only the start gate's (Step-6 duplication review, row 5).
# This is the stop side's counterpart: capture the literal line a blocked
# orchestrator sees and EXECUTE it, from a non-repo cwd, against a staged copy
# of the real observation. The defect it pins: bracketed placeholders on the
# command line became positional arguments the observation reported as three
# absent deliverables (R2) — a refusal that teaches the reader something false.
IFS='|' read -r R2_REPO R2_TR R2_SUB <<< "$(make_world r2 yes)"
plant_agent "$R2_SUB" "ablocked-aaaaaaaaaaaaaaaa" "blocked"
run_guard "$(mk_stop_payload "$SID_A" "$R2_TR" "$R2_REPO" "blocked")"
expect_status "the stop with no observation is refused (setup for R2)" 2 "$GUARD_ST"
FIXLINE=$(printf '%s\n' "$GUARD_ERR" | grep '^Fix: ' | sed 's/^Fix: //')
expect_contains "a fix line was captured to execute" "stop-check.sh" "$FIXLINE"
expect_absent "the fix line carries no bracketed placeholder (R2)" "[" "$FIXLINE"

# The world's OWN home, so the observation genuinely resolves the target and
# reaches its Deliverables section — otherwise it exits at "unresolved" and the
# fabricated-deliverable assertion below is vacuous.
R2_HOME="${R2_TR%%/.claude/projects/*}"
mkdir -p "$R2_HOME/.claude/hooks" "$SANDBOX/r2run/nowhere"
cp "$(dirname "$GUARD")/stop-check.sh" "$R2_HOME/.claude/hooks/stop-check.sh"
R2_OUT=$( cd "$SANDBOX/r2run/nowhere" && HOME="$R2_HOME" bash -c "$FIXLINE" 2>&1 )
R2_ST=$?
if [ "$R2_ST" -eq 127 ] || [ "$R2_ST" -eq 126 ]; then
  no "the captured fix line executes from a non-repo cwd" "exit $R2_ST: $R2_OUT"
else
  ok "the captured fix line executes from a non-repo cwd (exit $R2_ST)"
fi
expect_absent "running the fix line as printed reports no fabricated deliverable" \
  "— ABSENT" "$R2_OUT"
expect_absent "running the fix line as printed produces no usage error" "Usage:" "$R2_OUT"

# ============================================================
echo ""
echo "=== Section 6b: the lock and the consume — the failure paths (C3, S2) ==="
# ============================================================
#
# This region shipped with no callsite at all (Step-6 architecture review A4),
# and both a fail-OPEN consume (C3) and an unbounded spin (S2) lived in it.

# --- C3: a consume that cannot complete must REFUSE the stop ---
#
# The rename is the one consume failure a fixture cannot provoke directly (the
# other two — lock held, no writable temp — deny already and are driven below).
# Proven the way §9 names as durable: mutate a COPY so the rename targets an
# unwritable path, drive it, then re-checksum the shipped file.
GUARD_SUM_BEFORE=$(shasum "$GUARD" | awk '{print $1}')
MUTANT="$SANDBOX/stop-guard.consume-fails.sh"
sed 's|mv -f "$TMP" "$STATE_FILE" 2>/dev/null|mv -f "$TMP" "/nonexistent-dir-0xdead/x" 2>/dev/null|' \
  "$GUARD" > "$MUTANT"
if grep -qF '/nonexistent-dir-0xdead/x' "$MUTANT"; then
  ok "the consume-failure mutation applied (a mutation matching nothing must FAIL, not skip)"
else
  no "the consume-failure mutation applied (a mutation matching nothing must FAIL, not skip)"
fi

IFS='|' read -r C3_REPO C3_TR C3_SUB <<< "$(make_world c3 yes)"
plant_agent "$C3_SUB" "aunconsumable-5555555555555555" "unconsumable"
observe "$SID_A" "$C3_TR" "$C3_REPO" "unconsumable"
C3_PAYLOAD=$(mk_stop_payload "$SID_A" "$C3_TR" "$C3_REPO" "unconsumable")
C3_ERR=$(printf '%s' "$C3_PAYLOAD" | bash "$MUTANT" 2>&1 >/dev/null)
C3_ST=$?
expect_status "a consume that cannot complete REFUSES the stop (C3)" 2 "$C3_ST"
expect_contains "the refusal says the record could not be consumed (C3)" \
  "could not be consumed" "$C3_ERR"
expect_contains "the record survives an unconsumed stop, so D-2 still holds it" \
  "aunconsumable-5555555555555555" "$(cat "$C3_REPO/$STATE_REL" 2>/dev/null)"
if [ -d "$C3_REPO/.bionic/tmp/.stop-check.lock" ]; then
  no "a refused consume RELEASES the lock" "the lock survived, wedging every later stop"
else
  ok "a refused consume RELEASES the lock"
fi
expect_status "the shipped script was never modified by the mutation proof" 0 \
  "$([ "$GUARD_SUM_BEFORE" = "$(shasum "$GUARD" | awk '{print $1}')" ]; echo $?)"

# --- S2: neither arm may spin forever when the lock cannot be taken ---
#
# `mkdir` fails for reasons a stale-lock reclaim cannot fix — an unwritable state
# directory is repo-controlled — and `rm -rf` of an ABSENT path SUCCEEDS, so a
# reclaim-and-retry loop with no hard bound never terminates. A PreToolUse hook
# that never returns renders no verdict at all, which §7's table has no row for.
run_bounded() {  # <label> <secs> <payload> -> sets BOUNDED_ST (137 = killed)
  local secs="$2" payload="$3" waited=0 pid
  printf '%s' "$payload" | bash "$GUARD" >"$SANDBOX/.bout" 2>"$SANDBOX/.berr" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "$secs" ]; do
    sleep 1; waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; BOUNDED_ST=137
  else
    wait "$pid"; BOUNDED_ST=$?
  fi
  return 0
}

IFS='|' read -r S2_REPO S2_TR S2_SUB <<< "$(make_world s2 yes)"
plant_agent "$S2_SUB" "awedged-6666666666666666" "wedged"
observe "$SID_A" "$S2_TR" "$S2_REPO" "wedged"        # a valid record, so the gate reaches the consume
mkdir -p "$S2_REPO/.bionic/tmp"
chmod 500 "$S2_REPO/.bionic/tmp"

run_bounded "recorder" 12 "$(mk_bash_payload "$SID_A" "$S2_TR" "$S2_REPO" \
  "bash ~/.claude/hooks/stop-check.sh wedged")"
if [ "$BOUNDED_ST" = "137" ]; then
  no "the RECORDER arm terminates when the lock cannot be taken (S2)" "still running after 12s"
else
  expect_status "the RECORDER arm never blocks, even unable to lock (S2)" 0 "$BOUNDED_ST"
fi

run_bounded "gate" 12 "$(mk_stop_payload "$SID_A" "$S2_TR" "$S2_REPO" "wedged")"
if [ "$BOUNDED_ST" = "137" ]; then
  no "the GATE arm terminates when the lock cannot be taken (S2)" "still running after 12s"
else
  expect_status "the GATE arm REFUSES rather than spinning (S2, §7 stop=closed)" 2 "$BOUNDED_ST"
  expect_contains "the lock refusal says why and names the state directory" \
    "could not be consumed" "$(cat "$SANDBOX/.berr")"
fi
chmod 700 "$S2_REPO/.bionic/tmp"

# ============================================================
echo ""
echo "=== Section 7: hostile repo (AC-8, TDD §8, checklist A2/A3) ==="
# ============================================================

# Predictable temp names + symlink-following writes were a PROVEN arbitrary-file
# overwrite in the discarded run (corr-sec S1/S2). Both levels are replanted.
IFS='|' read -r S_REPO S_TR S_SUB <<< "$(make_world sec yes)"
plant_agent "$S_SUB" "avictim-ffffffffffffffff" "victim"
mkdir -p "$S_REPO/.bionic/tmp"
VICTIM_FILE="$SANDBOX/sec-outside-file.txt"
echo "ORIGINAL CONTENT" > "$VICTIM_FILE"
ln -s "$VICTIM_FILE" "$S_REPO/$STATE_REL"
observe "$SID_A" "$S_TR" "$S_REPO" "victim"
expect_status "a planted state SYMLINK does not crash the recorder" 0 "$GUARD_ST"
expect_contains "a planted state symlink is not written through (file level)" \
  "ORIGINAL CONTENT" "$(cat "$VICTIM_FILE")"

# The gate refuses to READ through a planted symlink too — not only to write
# through it. Without this the file-level guard has no discriminating test: `mv`
# happens to replace a symlink rather than follow it, so the write side stays
# safe for a reason that has nothing to do with the check.
run_guard "$(mk_stop_payload "$SID_A" "$S_TR" "$S_REPO" "victim")"
expect_status "a symlinked state path refuses the stop" 2 "$GUARD_ST"
expect_contains "the symlink refusal says what it found" "symlink" "$GUARD_ERR"

IFS='|' read -r S2_REPO S2_TR S2_SUB <<< "$(make_world sec2 yes)"
plant_agent "$S2_SUB" "avictim-ffffffffffffffff" "victim"
OUTSIDE_DIR="$SANDBOX/sec2-outside-dir"
mkdir -p "$OUTSIDE_DIR" "$S2_REPO/.bionic"
ln -s "$OUTSIDE_DIR" "$S2_REPO/.bionic/tmp"
observe "$SID_A" "$S2_TR" "$S2_REPO" "victim"
expect_status "a planted state DIRECTORY symlink does not crash the recorder" 0 "$GUARD_ST"
if [ -z "$(ls -A "$OUTSIDE_DIR")" ]; then
  ok "a planted directory symlink is not written through (directory level)"
else
  no "a planted directory symlink is not written through (directory level)" "$(ls -A "$OUTSIDE_DIR")"
fi

# Unpredictable temp names: mktemp with an X-template, and no PID-based name.
expect_matches "temp files use an mktemp X-template" 'mktemp.*XXXXXX' "$(cat "$GUARD")"
expect_absent "no PID-based temp filename" '.tmp.$$' "$(cat "$GUARD")"

# The gate reads the working log; it must never quote it. (§8 keeps that
# disclosure in the observation, whose whole purpose is to show it to a reader.)
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"CANARY_LOG_BODY"}]}}\n' \
  >> "$S_SUB/agent-avictim-ffffffffffffffff.jsonl"
run_guard "$(mk_stop_payload "$SID_A" "$S_TR" "$S_REPO" "victim")"
expect_absent "the refusal prints no working-log contents" "CANARY_LOG_BODY" "$GUARD_ERR"

# ============================================================
echo ""
echo "──────────────────────────────────────────────"
echo "stop-guard.sh: ${PASS}/${TOTAL} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
