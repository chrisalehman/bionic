#!/bin/bash
# Tests for hooks/patrol-duties-gate.sh — the PATROL-DUTIES WALL (task-scale
# session task-dispatch-wall-channel-loss, T5).
#
# THE CONTRACT UNDER TEST. A Patrol tick is a turn the machine started, not the
# user, and its two standing duties — refresh the subagent panel, refresh the
# task list — are carried today by prompt text, which cannot bind. This Stop
# hook makes the TURN'S END the wall: if the last user prompt was a Patrol tick
# (structural marker: it contains `session-poker.sh tick`), the turn may not end
# until the transcript shows, AFTER that prompt, a main-thread `ListAgents` AND
# either a `TaskList` or a write naming the active plan file (the version-gated
# fallback for sessions where the task tools are absent — see
# memory/task-tools-tengu-gate).
#
# HARNESS IDIOM mirrors tests/context-spend.test.sh: PASS/FAIL counters, mktemp
# projects, resolve-roots for the hook path, real-shape Stop stdin JSON. The
# transcript fixtures replay the JSONL shapes read out of live transcripts under
# ~/.claude/projects/-Users-admin-workspace-personal-bionic/ on 2026-08-22:
#
#   a cron-fired Patrol tick  -> {"type":"user", ..., "message":{"content":"Patrol tick — ..."}}
#                                content is a STRING, isMeta true, isSidechain false
#   a tool call               -> {"type":"assistant", "isSidechain":false,
#                                 "message":{"content":[{"type":"tool_use","name":"ListAgents","input":{}}]}}
#                                main-thread entries carry NO agentId/agent_id
#   a tool result             -> {"type":"user", "message":{"content":[{"type":"tool_result",...}]}}
#
# Usage: bash tests/patrol-duties-gate.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

HOOK="${BIONIC_PATROL_DUTIES_GATE_UNDER_TEST:-${BIONIC_HOOKS_DIR}/patrol-duties-gate.sh}"
PASS=0; FAIL=0; TOTAL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  $2"; FAIL=$((FAIL + 1)); }

command -v jq >/dev/null 2>&1 || { echo "patrol-duties-gate: jq absent — suite cannot run"; exit 1; }

PLAN_REL="task-fixture.plan.md"
PLAN_NAME="$PLAN_REL"

# ---------- fixture builders ----------

# A scratch project with a docs-root plans dir holding ONE plan file, and an
# empty transcript ready to be appended to.
make_env() {  # -> project dir on stdout
  local dir; dir=$(mktemp -d)
  mkdir -p "$dir/.bionic/docs/plans" "$dir/.bionic/tmp"
  cat > "$dir/.bionic/docs/plans/$PLAN_REL" <<'EOF'
---
governing-skill: canonical-sdlc
---
## SDLC State

current: T5
EOF
  : > "$dir/transcript.jsonl"
  printf '%s' "$dir"
}

# A project with NO plans directory at all.
make_env_planless() {
  local dir; dir=$(mktemp -d)
  mkdir -p "$dir/.bionic/tmp"
  : > "$dir/transcript.jsonl"
  printf '%s' "$dir"
}

# One user PROMPT entry — content is a bare string, the shape a cron-fired tick
# actually has.
u_prompt() {  # <dir> <text>
  jq -nc --arg t "$2" '{type:"user",isMeta:true,isSidechain:false,userType:"external",
                        message:{role:"user",content:$t}}' >> "$1/transcript.jsonl"
}

# The tick itself, verbatim in shape: the marker is the poker command inside a
# longer composed prompt, never the prompt's wording (T2 judgment call (b)).
u_tick() {  # <dir>
  u_prompt "$1" "Patrol tick for the fixture wave (bionic). Run: bash /abs/hooks/session-poker.sh tick — the poker decides per row; QUIET/DISARM = no-op. Then continue toward the goal until a wall."
}

# A tool_result carrier: a `user`-typed entry that is NOT a prompt. It must not
# reset the turn, or every tick with a single tool call in it would read as a
# fresh non-tick turn and the wall would never fire.
u_result() {  # <dir>
  jq -nc '{type:"user",isSidechain:false,
           message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_x",content:"ok"}]}}' \
    >> "$1/transcript.jsonl"
}

# One assistant entry carrying one tool_use.
a_tool() {  # <dir> <name> [file_path-or-command]
  local dir="$1" name="$2" arg="${3:-}"
  local input='{}'
  case "$name" in
    Edit|Write|NotebookEdit) input=$(jq -nc --arg p "$arg" '{file_path:$p}') ;;
    Bash)                    input=$(jq -nc --arg c "$arg" '{command:$c}') ;;
  esac
  jq -nc --arg n "$name" --argjson i "$input" \
    '{type:"assistant",isSidechain:false,
      message:{role:"assistant",content:[{type:"tool_use",id:"toolu_1",name:$n,input:$i}]}}' \
    >> "$dir/transcript.jsonl"
}

# TWO tool_uses in ONE assistant entry — a parallel batch. A line-counting read
# would see one call; occurrences are what matter (the poker's own lesson).
a_tool_batch() {  # <dir> <name1> <name2>
  jq -nc --arg a "$2" --arg b "$3" \
    '{type:"assistant",isSidechain:false,
      message:{role:"assistant",content:[{type:"tool_use",id:"toolu_1",name:$a,input:{}},
                                         {type:"tool_use",id:"toolu_2",name:$b,input:{}}]}}' \
    >> "$1/transcript.jsonl"
}

# The same tool call, but inside an agent context. A subagent's ListAgents is
# not the orchestrator's panel refresh; the poker excludes agent-context
# tool_uses for the mirror-image reason (session-poker.sh:399-406).
a_tool_sidechain() {  # <dir> <name>
  jq -nc --arg n "$2" '{type:"assistant",isSidechain:true,
      message:{role:"assistant",content:[{type:"tool_use",id:"toolu_1",name:$n,input:{}}]}}' \
    >> "$1/transcript.jsonl"
}

a_tool_agentid() {  # <dir> <name>
  jq -nc --arg n "$2" '{type:"assistant",isSidechain:false,agentId:"aworker-5fb2ff80f2de21f7",
      message:{role:"assistant",content:[{type:"tool_use",id:"toolu_1",name:$n,input:{}}]}}' \
    >> "$1/transcript.jsonl"
}

junk() { printf 'not json at all {{{\n' >> "$1/transcript.jsonl"; }

# ---------- driving the hook ----------

stdin_for() {  # <project> <transcript-path> [event] [stop_hook_active]
  jq -nc --arg t "$2" --arg c "$1" --arg e "${3:-Stop}" --argjson a "${4:-false}" \
    '{session_id:"11111111-2222-3333-4444-555555555555",transcript_path:$t,cwd:$c,
      hook_event_name:$e,stop_hook_active:$a}'
}

fire() {  # <project> [event] [stop_hook_active]
  HOOK_OUT=$(bash "$HOOK" <<< "$(stdin_for "$1" "$1/transcript.jsonl" "${2:-Stop}" "${3:-false}")" 2>/dev/null)
  HOOK_RC=$?
}

fire_raw() {  # <project> <stdin-json>
  HOOK_OUT=$(bash "$HOOK" <<< "$2" 2>/dev/null); HOOK_RC=$?
}

reason_of() { printf '%s' "$HOOK_OUT" | jq -r '.reason // ""' 2>/dev/null; }
decision_of() { printf '%s' "$HOOK_OUT" | jq -r '.decision // ""' 2>/dev/null; }

expect_allow() {  # <label>
  TOTAL=$((TOTAL + 1))
  if [ "$HOOK_RC" -eq 0 ] && [ -z "$HOOK_OUT" ]; then
    pass "$1"
  else
    fail "$1" "rc=$HOOK_RC stdout=<$HOOK_OUT>"
  fi
}

# A block is the JSON decision payload on stdout, with rc 0 — the form Design
# (T5) names. Every block assertion also states what the reason must NOT say:
# a reason that lists both duties whichever one is missing tells the reader
# nothing, and is the failure this gate's whole value rests on avoiding.
expect_block() {  # <label> <must-contain> [must-not-contain]
  TOTAL=$((TOTAL + 1))
  local d r; d=$(decision_of); r=$(reason_of)
  if [ "$HOOK_RC" -ne 0 ]; then
    fail "$1" "rc=$HOOK_RC (a JSON block exits 0); stdout=<$HOOK_OUT>"; return
  fi
  if [ "$d" != "block" ]; then
    fail "$1" "decision=<$d> expected block; stdout=<$HOOK_OUT>"; return
  fi
  case "$r" in
    *"$2"*) ;;
    *) fail "$1" "reason does not name <$2>: $r"; return ;;
  esac
  if [ -n "${3:-}" ]; then
    case "$r" in
      *"$3"*) fail "$1" "reason wrongly names <$3>: $r"; return ;;
    esac
  fi
  pass "$1"
}

LA_MISSING="ListAgents"
TL_MISSING="TaskList or a plan-ledger write"

echo "=== Section 1: the six contract cases (Design T5) ==="

# 1: tick + both duties -> allow.
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" TaskList
fire "$d"; expect_allow "1: tick + ListAgents + TaskList passes"

# 2: tick + panel refresh only -> block naming the task-list side AND its
# fallback, and NOT naming ListAgents (which was done).
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents
fire "$d"; expect_block "2: tick + ListAgents only blocks, naming TaskList or a plan-ledger write" \
  "$TL_MISSING" "$LA_MISSING"

# 3: tick + task-list refresh only -> block naming ListAgents, and NOT naming
# TaskList (which was done).
d=$(make_env); u_tick "$d"; a_tool "$d" TaskList
fire "$d"; expect_block "3: tick + TaskList only blocks, naming ListAgents" \
  "$LA_MISSING" "TaskList"

# 4: the version-gated fallback — a write naming the active plan file stands in
# for TaskList, because in a session without the task tools the plan ledger IS
# the task list (memory/task-tools-tengu-gate).
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" Edit "$d/.bionic/docs/plans/$PLAN_REL"
fire "$d"; expect_allow "4: tick + ListAgents + an Edit naming the plan passes"

# 5: a turn the user started is not a Patrol tick — the wall is silent on it,
# whatever it did or did not do.
d=$(make_env); u_prompt "$d" "run the suite and tell me what broke"
fire "$d"; expect_allow "5: a non-tick turn with neither duty passes"

# 6: blocks ONCE. The harness re-enters the stop with stop_hook_active true;
# refusing again wedges the turn with no way out.
d=$(make_env); u_tick "$d"
fire "$d" Stop true; expect_allow "6: stop_hook_active true passes the same incomplete tick"

echo ""
echo "=== Section 2: discrimination — what counts, and when ==="

# 7: neither duty -> the reason names BOTH.
d=$(make_env); u_tick "$d"
fire "$d"; expect_block "7a: tick + neither blocks, naming ListAgents" "$LA_MISSING"
fire "$d"; expect_block "7b: the same block also names TaskList or a plan-ledger write" "$TL_MISSING"

# 8: ORDERING. Both duties performed BEFORE the tick arrived satisfy nothing —
# the panel and the task list are stale by exactly the interval the tick exists
# to cover. Without this the wall passes every tick in any session that ever
# called ListAgents once.
d=$(make_env); a_tool "$d" ListAgents; a_tool "$d" TaskList; u_tick "$d"
fire "$d"; expect_block "8a: duties performed BEFORE the tick do not count (ListAgents)" "$LA_MISSING"
fire "$d"; expect_block "8b: duties performed BEFORE the tick do not count (task list)" "$TL_MISSING"

# 9/10: the fallback's other two shapes.
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" Write "$d/.bionic/docs/plans/$PLAN_REL"
fire "$d"; expect_allow "9: a Write naming the plan satisfies the task-list duty"

d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents
a_tool "$d" Bash "printf '%s\\n' 'row' >> .bionic/docs/plans/$PLAN_NAME"
fire "$d"; expect_allow "10: a Bash command naming the plan satisfies the task-list duty"

# 11: a write to something else is not a ledger write.
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" Edit "$d/notes.md"
fire "$d"; expect_block "11: an Edit naming a different file does not satisfy it" "$TL_MISSING" "$LA_MISSING"

# 12/13: agent-context calls are not the orchestrator's. A subagent that ran
# ListAgents did not refresh the orchestrator's panel.
d=$(make_env); u_tick "$d"; a_tool_sidechain "$d" ListAgents; a_tool "$d" TaskList
fire "$d"; expect_block "12: a sidechain ListAgents does not count" "$LA_MISSING" "TaskList"

d=$(make_env); u_tick "$d"; a_tool_agentid "$d" ListAgents; a_tool "$d" TaskList
fire "$d"; expect_block "13: a ListAgents carrying an agentId does not count" "$LA_MISSING" "TaskList"

# 14: a tool_result carrier is not a prompt. The turn's boundary is the last
# PROMPT; if results reset it, a tick whose duties are separated by any tool
# result reads as a fresh non-tick turn and the wall goes permanently silent.
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; u_result "$d"; a_tool "$d" TaskList
fire "$d"; expect_allow "14: tool_result entries do not end the tick's turn"

# 14b: a tool_result carrier must not reset internal duty/tick bookkeeping either
# -- same fixture family as 14, but only ONE duty is done, so a wrongful reset
# (tick lost -> quiet/allow) is DISCRIMINABLE from the correct outcome (block,
# naming the missing duty), unlike 14 where both outcomes coincide at allow.
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; u_result "$d"
fire "$d"; expect_block "14b: a tool_result carrier does not clear an already-done duty" "$TL_MISSING" "$LA_MISSING"

# 15: a batch — two tool_uses in one assistant entry.
d=$(make_env); u_tick "$d"; a_tool_batch "$d" ListAgents TaskList
fire "$d"; expect_allow "15: both duties in ONE assistant entry pass"

# 16: a later user prompt ends the tick's turn. The duties belong to the tick,
# and a turn the user started is judged by case 5's rule.
d=$(make_env); u_tick "$d"; u_prompt "$d" "actually, do this instead"
fire "$d"; expect_allow "16: a user prompt after the tick ends the tick's turn"

echo ""
echo "=== Section 3: fail directions — silence on every ambiguity ==="

# 17: SubagentStop is not this gate's event. A subagent has no Patrol duties.
d=$(make_env); u_tick "$d"
fire "$d" SubagentStop; expect_allow "17: a SubagentStop payload passes"

# 18/19: nothing to read -> nothing to say.
d=$(make_env); u_tick "$d"
fire_raw "$d" "$(stdin_for "$d" "$d/nonexistent.jsonl")"
expect_allow "18: a transcript_path that does not exist passes"

d=$(make_env); u_tick "$d"
fire_raw "$d" "$(jq -nc --arg c "$d" '{session_id:"s",cwd:$c,hook_event_name:"Stop",stop_hook_active:false}')"
expect_allow "19: a payload with no transcript_path passes"

# 20: malformed lines are skipped, not fatal.
d=$(make_env); u_tick "$d"; junk "$d"; a_tool "$d" ListAgents; junk "$d"; a_tool "$d" TaskList
fire "$d"; expect_allow "20: malformed transcript lines do not break the read"

# 21: no plan file at all — the TaskList duty is still satisfiable, and an empty
# plan name must never match every write.
d=$(make_env_planless); u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" TaskList
fire "$d"; expect_allow "21: a project with no plans dir still passes on TaskList"

d=$(make_env_planless); u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" Edit "$d/notes.md"
fire "$d"; expect_block "22: with no plan file, an unrelated Edit satisfies nothing" "$TL_MISSING" "$LA_MISSING"

# 23: THE GATE WRITES NOTHING. It is a gate, and gates only read (TDD §3.2).
d=$(make_env); u_tick "$d"
_before=$(find "$d" -type f | sort | cksum)
fire "$d"
_after=$(find "$d" -type f | sort | cksum)
TOTAL=$((TOTAL + 1))
if [ "$_before" = "$_after" ]; then
  pass "23: the gate creates and removes no file in the project"
else
  fail "23: the gate touched the project tree" "$_before -> $_after"
fi

# 24: THE SUITE IS REGISTERED. tests/*.test.sh is NOT globbed by the runner — an
# unregistered suite is a silent false green, and this gate would then be a wall
# nothing drives. (The pattern is tests/doctor.test.sh Group 11.)
TOTAL=$((TOTAL + 1))
if grep -q 'run "patrol-duties-gate.test.sh" bash tests/patrol-duties-gate.test.sh' \
     "${BIONIC_SCRIPTS_DIR}/tests/run.sh"; then
  pass "24: tests/run.sh names patrol-duties-gate.test.sh"
else
  fail "24: tests/run.sh does not name this suite — it would never run"
fi

# 25: THE GATE IS REGISTERED ON THE STOP CHANNEL. A hook with a suite, a run line
# and no registration is the exact shape the landing sweep spent a wave being:
# installed, syntactically fine, green in its own suite, and never fired.
TOTAL=$((TOTAL + 1))
if grep -q '\${CLAUDE_PLUGIN_ROOT}/hooks/patrol-duties-gate.sh' \
     "${BIONIC_SKILLS_DIR}/canonical-sdlc/SKILL.md"; then
  pass "25: SKILL.md registers the gate on the Stop channel"
else
  fail "25: the gate is not registered in SKILL.md — it would never fire"
fi

echo ""
echo "========================================"
echo "patrol-duties-gate: $PASS/$TOTAL passed"
echo "========================================"

[ "$FAIL" -eq 0 ] || exit 1
