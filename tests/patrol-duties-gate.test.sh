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
# HARNESS IDIOM mirrored tests/context-spend.test.sh (deleted at 8582861, epic-18
# wave-03): PASS/FAIL counters, mktemp
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

d=$(make_env); u_tick "$d"
fire_raw "$d" "$(jq -nc --arg c "$d" '{session_id:"s",cwd:$c,hook_event_name:"Stop",stop_hook_active:false}')"

# 20: malformed lines are skipped, not fatal.
d=$(make_env); u_tick "$d"; junk "$d"; a_tool "$d" ListAgents; junk "$d"; a_tool "$d" TaskList
fire "$d"; expect_allow "20: malformed transcript lines do not break the read"

# 21/22: NO PLAN, NO RUN, NO DUTY (bionic 1.4.0, spec AC-7). The gate is registered
# always-on now, so it is delivered on every Stop in every project on the machine, and
# what scopes it is `active_run`. A project with no plan has no run, no Patrol and
# therefore no Patrol duties — the gate says nothing, and it says nothing before it
# parses the transcript at all, which is where its whole cost lives.
d=$(make_env_planless); u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" Edit "$d/notes.md"
fire "$d"; expect_allow "21: a project with no plan is silent even with both duties skipped"

# THE PAIRED POSITIVE, and it is what keeps 21 from passing vacuously: the SAME
# transcript, in a project that does have an open run, refuses. Nothing separates the
# two but the plan file.
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" Edit "$d/notes.md"
fire "$d"; expect_block "22: …and with a plan, that same unrelated Edit satisfies nothing" "$TL_MISSING" "$LA_MISSING"

# 22b: the plan's basename must never be an EMPTY needle — an empty one would make
# every write in the turn discharge the task-list duty. Driven by an Edit whose path
# shares no component with the plan's name.
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" Edit "$d/unrelated-file.txt"
fire "$d"; expect_block "22b: an Edit that does not name the plan leaves the task-list duty owed" "$TL_MISSING" "$LA_MISSING"

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
# nothing drives. (The pattern was tests/doctor.test.sh Group 11, deleted at
# 8582861, epic-18 wave-03.)
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
# A hook with a suite, a run line and no registration is installed, green in its own
# suite, and never fired. THE CHANNEL MOVED (bionic 1.4.0, slice ADOPT, spec AC-7): this
# gate was registered in the governing skill's frontmatter so it would be live exactly
# while that skill was, and that coupling is the defect — a `/clear`, a compaction or a
# session the skill was never invoked in left the wall installed and not running, while
# the duty it binds went on existing. Both halves are asserted, because either alone is a
# wall in the wrong place: a lingering frontmatter entry fires it twice per turn (the CLI
# does not deduplicate across the two manifests), and a missing manifest entry not at all.
TOTAL=$((TOTAL + 1))
if grep -q '\${CLAUDE_PLUGIN_ROOT}/hooks/patrol-duties-gate\.sh' \
     "${BIONIC_HOOKS_DIR}/hooks.json"; then
  pass "25: hooks/hooks.json registers the gate on the Stop channel, always on"
else
  fail "25: the gate is not registered in hooks/hooks.json — it would never fire"
fi
TOTAL=$((TOTAL + 1))
if grep -q '\${CLAUDE_PLUGIN_ROOT}/hooks/patrol-duties-gate\.sh' \
     "${BIONIC_SKILLS_DIR}/canonical-sdlc/SKILL.md"; then
  fail "25b: SKILL.md still registers the gate — a second registration fires it twice per turn"
else
  pass "25b: …and SKILL.md's frontmatter does not, so it fires exactly once"
fi

# 26/26b: THE HEADER'S OWN HONESTY ABOUT ITS BACKSTOP. This file used to cite the
# hooks reference — "Claude Code overrides the hook and ends the turn after 8
# consecutive blocks" — as the net under both of its accepted limits. It cannot
# be: `stop_hook_active` guarantees exactly one block per turn and the re-entry
# always passes, so the blocks are never consecutive and that override can never
# engage here. hooks/patrol-revive.sh carried the identical claim and lost it at
# S10 (critic C-2); this is the same correction on the other hook that makes it,
# pinned the same way — as a PAIR, so the absence rests on an extractor proven to
# find text in this very file.
TOTAL=$((TOTAL + 1))
if grep -q 'never consecutive' "$HOOK"; then
  pass "26: the header states why the CLI's consecutive-block override cannot engage here"
else
  fail "26: the header does not say why the consecutive-block override cannot engage"
fi
TOTAL=$((TOTAL + 1))
if grep -q 'Backstop above ours, from the same reference' "$HOOK"; then
  fail "26b: the header still claims a backstop that cannot fire for this hook"
else
  pass "26b: …and no longer claims that backstop as its own"
fi

echo ""
echo "=== Section 4: the resume/clear ritual arm (bionic 1.4.0, AC-3) ==="
#
# A /clear rewrites the session id in place but does NOT kill a predecessor's cron
# job (A-probe-4: it survives and keeps firing into the new conversation). The
# probe's own new transcript begins with the literal `<command-name>/clear</command-name>`
# turn (record/wave-1.4.0-probe.md); a resume is announced the same way this gate's
# SessionStart sibling (hooks/session-start.sh) prints it: the literal substring
# `source: resume` inside its title line. Either marker means a CronCreate that is
# not preceded by a CronList SINCE that marker would leave two clocks on one
# project — the wall refuses once, naming the resume ritual.

# A user-role entry shaped exactly like the probe's own new-transcript first turn.
u_clear_marker() { u_prompt "$1" "<command-name>/clear</command-name>"; }

# The marker is type-agnostic by design (a SessionStart report is not a user
# prompt), so this is driven as a "system"-typed entry — proving the scan reads
# raw transcript text, not one JSON shape.
u_resume_marker() {
  jq -nc '{type:"system",isSidechain:false,
           message:{content:"bionic session-start (source: resume) — state the previous conversation left on this project."}}' \
    >> "$1/transcript.jsonl"
}

RITUAL_CRONLIST="CronList"
RITUAL_JOB="bionic-patrol session="
RITUAL_CRONCREATE="CronCreate"
RITUAL_ARM="session-poker.sh arm"
RITUAL_ADOPT="adopt"

# 27: a clear marker, then a CronCreate with no CronList since it -> block, naming
# every step of the ritual.
d=$(make_env); u_clear_marker "$d"; a_tool "$d" CronCreate
fire "$d"
expect_block "27: CronCreate with no prior CronList after a clear marker blocks" "$RITUAL_CRONLIST"
TOTAL=$((TOTAL + 1))
r=$(reason_of)
case "$r" in
  *"$RITUAL_CRONLIST"*"$RITUAL_JOB"*"$RITUAL_CRONCREATE"*"$RITUAL_ARM"*"$RITUAL_ADOPT"*)
    pass "28: the reason states the ritual in order — CronList, delete the stray job, CronCreate, arm, adopt" ;;
  *) fail "28: the reason does not state the ritual in order" "$r" ;;
esac

# 29: the same marker, but CronList precedes the CronCreate -> passes.
d=$(make_env); u_clear_marker "$d"; a_tool "$d" CronList; a_tool "$d" CronCreate
fire "$d"; expect_allow "29: CronList before CronCreate after a clear marker passes"

# 30: no marker at all -> the arm is inert, whatever the Cron calls did.
d=$(make_env); a_tool "$d" CronCreate
fire "$d"; expect_allow "30: no marker in the transcript — the arm is inert"

# 31: the resume spelling blocks the same way.
d=$(make_env); u_resume_marker "$d"; a_tool "$d" CronCreate
fire "$d"; expect_block "31: a resume marker with no prior CronList blocks" "$RITUAL_CRONLIST"

# 32: BLOCKS ONCE. The re-entry with stop_hook_active true always passes, exactly
# the mechanism the tick-duties arm already uses — nothing new to enforce it.
d=$(make_env); u_clear_marker "$d"; a_tool "$d" CronCreate
fire "$d" Stop true
expect_allow "32: stop_hook_active true passes the same unresolved ritual — the refusal fires only once"

# 33: ORDERING. A CronCreate that happened BEFORE the marker is not "since" it —
# only a later marker starts the window this rule judges.
d=$(make_env); a_tool "$d" CronCreate; u_clear_marker "$d"
fire "$d"; expect_allow "33: a CronCreate before the marker does not count against it"

# 34: a CronList satisfies the ritual with nothing else following it.
d=$(make_env); u_clear_marker "$d"; a_tool "$d" CronList
fire "$d"; expect_allow "34: a marker followed only by CronList passes — nothing to cure"

# 35: agent-context calls are not the orchestrator's ritual, same exclusion as the
# tick-duties arm's ListAgents/TaskList reads.
d=$(make_env); u_clear_marker "$d"; a_tool_sidechain "$d" CronCreate
fire "$d"; expect_allow "35: a sidechain CronCreate does not count against the ritual"

echo ""
echo "=== Section 5: the third duty — a printed FILL is answered (AC-29) ==="

# THE CONTRACT. `session-poker.sh tick` can compute the gap between the plan's budget and
# the roster and name the slices that are ready, but it cannot dispatch — and a
# recommendation nobody is obliged to answer is how this repo's own 1.4.0 wave ran six
# writers against a budget of twenty-two. The turn's END is the only moment at which "the
# FILL went unanswered" is a fact, so it is the moment this gate asks.
#
# ANSWERED = an `Agent` tool_use naming the slice, or an explicit `fill-declined: <reason>`
# anywhere in the turn. The decline is the point, not a loophole: there are good reasons not
# to fill and every one is worth one line in the record. What is refused is SILENCE.
#
# The FILL line reaches the transcript as the CONTENT of the tick's Bash tool result — a
# `user`-typed entry that is deliberately NOT a prompt — so these fixtures carry it the way
# a live transcript does.

# A tool_result carrying the tick's output.
u_tick_out() {  # <dir> <text>
  jq -nc --arg t "$2" \
    '{type:"user",isSidechain:false,
      message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_x",content:$t}]}}' \
    >> "$1/transcript.jsonl"
}

# One Agent dispatch, shaped as the harness sends it: the slice id may land in the name, the
# description or the prompt, and this gate reads all of them.
a_agent() {  # <dir> <name> [prompt]
  jq -nc --arg n "$2" --arg p "${3:-}" \
    '{type:"assistant",isSidechain:false,
      message:{role:"assistant",content:[{type:"tool_use",id:"toolu_9",name:"Agent",
        input:{name:$n,prompt:$p,subagent_type:"implementor"}}]}}' \
    >> "$1/transcript.jsonl"
}

a_agent_sidechain() {  # <dir> <name>
  jq -nc --arg n "$2" \
    '{type:"assistant",isSidechain:true,
      message:{role:"assistant",content:[{type:"tool_use",id:"toolu_9",name:"Agent",
        input:{name:$n,prompt:"x",subagent_type:"implementor"}}]}}' \
    >> "$1/transcript.jsonl"
}

# The orchestrator's own words, which is one of the places a decline may be written.
a_text() {  # <dir> <text>
  jq -nc --arg t "$2" \
    '{type:"assistant",isSidechain:false,
      message:{role:"assistant",content:[{type:"text",text:$t}]}}' \
    >> "$1/transcript.jsonl"
}

both_duties() {  # <dir> — the two standing duties, so §5 measures the THIRD one alone
  a_tool "$1" ListAgents; a_tool "$1" TaskList
}

FILL_MARK="fill unanswered"

# 36: every named slice dispatched -> allow.
d=$(make_env); u_tick "$d"; both_duties "$d"; u_tick_out "$d" "poker: FILL ALPHA BETA"
a_agent "$d" "W-ALPHA" "Slice ALPHA, senior-implementor."
a_agent "$d" "W-BETA" "Slice BETA, implementor."
fire "$d"; expect_allow "36: a FILL whose every slice was dispatched passes"

# 37: one of two dispatched -> block, naming the one that was not, and NOT the one that was.
d=$(make_env); u_tick "$d"; both_duties "$d"; u_tick_out "$d" "poker: FILL ALPHA BETA"
a_agent "$d" "W-ALPHA" "Slice ALPHA, senior-implementor."
fire "$d"; expect_block "37: a half-answered FILL blocks, naming the slice left out" "BETA" "ALPHA"

# 38: neither dispatched nor declined -> block, naming both.
d=$(make_env); u_tick "$d"; both_duties "$d"; u_tick_out "$d" "poker: FILL ALPHA BETA"
fire "$d"; expect_block "38a: an unanswered FILL blocks, naming the first slice" "ALPHA"
fire "$d"; expect_block "38b: …and the second" "BETA"
fire "$d"; expect_block "38c: …and says what would answer it" "fill-declined"

# 39: the DECLINE answers it. Not a loophole — a reason in the record is the point.
d=$(make_env); u_tick "$d"; both_duties "$d"; u_tick_out "$d" "poker: FILL ALPHA BETA"
a_text "$d" "fill-declined: ADOPT has not merged, so neither slice can base off the wave head."
fire "$d"; expect_allow "39: an explicit fill-declined line answers the FILL"

# 40: the decline may be written anywhere the orchestrator writes — including a plan-ledger
# line, which is where a run without the task tools keeps its record.
d=$(make_env); u_tick "$d"; both_duties "$d"; u_tick_out "$d" "poker: FILL ALPHA"
a_tool "$d" Bash "printf '%s\\n' 'fill-declined: peers not idle (D1)' >> .bionic/docs/plans/$PLAN_NAME"
fire "$d"; expect_allow "40: a decline written into the plan ledger answers it too"

# 41: INERT with no FILL line. Every turn in every project whose tick prints none — which is
# every project with no budget in its plan — must pass exactly as it did before.
d=$(make_env); u_tick "$d"; both_duties "$d"; u_tick_out "$d" "poker: QUIET — 0 open row(s)"
fire "$d"; expect_allow "41: a tick that printed no FILL is not asked about one"

# 42: ORDERING. A FILL printed in an EARLIER turn is not this turn's to answer — the fold
# resets at every user prompt, exactly as the duties fold does.
d=$(make_env); u_tick "$d"; u_tick_out "$d" "poker: FILL ALPHA"; u_tick "$d"; both_duties "$d"
fire "$d"; expect_allow "42: a FILL from a previous turn does not bind this one"

# 43: an agent-context dispatch is not the orchestrator's. A subagent that dispatched
# does not discharge the orchestrator's fill — the same exclusion every other arm makes.
d=$(make_env); u_tick "$d"; both_duties "$d"; u_tick_out "$d" "poker: FILL ALPHA"
a_agent_sidechain "$d" "W-ALPHA"
fire "$d"; expect_block "43: a sidechain Agent does not answer the orchestrator's FILL" "ALPHA"

# 44: WORD BOUNDARY. A dispatch that merely CONTAINS the id inside a longer word has not
# named it — the difference between matching `ONE` and matching `PHONE`.
d=$(make_env); u_tick "$d"; both_duties "$d"; u_tick_out "$d" "poker: FILL ONE"
a_agent "$d" "W-PHONE" "Slice PHONEBOOK, implementor."
fire "$d"; expect_block "44: an id inside a longer word does not answer the FILL" "ONE"

# 45: BLOCKS ONCE, through the existing stop_hook_active valve — no new bookkeeping.
d=$(make_env); u_tick "$d"; both_duties "$d"; u_tick_out "$d" "poker: FILL ALPHA"
fire "$d" Stop true
expect_allow "45: stop_hook_active true passes the same unanswered FILL"

# 46: BOTH FAILURES AT ONCE are told at once. Blocking on the standing duty and staying
# silent about the FILL would hide the second behind the one-shot: the next stop passes by
# design, so a duty not named in the first refusal is a duty never named at all.
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; u_tick_out "$d" "poker: FILL ALPHA"
fire "$d"; expect_block "46a: a turn missing a standing duty AND a fill names the duty" "$TL_MISSING"
fire "$d"; expect_block "46b: …and names the unanswered slice in the same refusal" "ALPHA"

# 47: a non-tick turn is never asked, whatever its transcript contains.
d=$(make_env); u_prompt "$d" "run the suite and tell me what broke"
u_tick_out "$d" "poker: FILL ALPHA"
fire "$d"; expect_allow "47: a turn the user started is not asked about a FILL"

echo ""
echo "========================================"
echo "patrol-duties-gate: $PASS/$TOTAL passed"
echo "========================================"

[ "$FAIL" -eq 0 ] || exit 1
