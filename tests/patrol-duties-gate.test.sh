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
# the task-tools census in payload/scripts/lib/env.sh).
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
# THE TASK-LIST DUTIES ARE GONE (wave-31 T32; D6, REQ-6 AC-6.5). No tick turn owes a task-list
# refresh and no dispatch turn owes a task entry set in progress: a process check the turn's end
# demanded of the model, with nothing behind it to do. The tick still prints `poker: RECONCILE` and
# writes `duty=` to its digest, as advice no wall reads. What this wall still refuses on a tick turn
# is a marker turn that ran no tick, an unanswered FILL or stand-down, an unrecorded launch and the
# resume ritual, and the rows below that used the refresh to show the wall was listening now use the
# marker that ran no tick (`u_marker` beside an `arm` stamp).
#
# Usage: bash tests/patrol-duties-gate.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"
. "$(dirname "$0")/lib/assert.sh"
# The one roster-row builder and the one swept-marker writer (S17): wave-19's fill fixtures
# write this session's roster through them rather than spelling either shape by hand.
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
# The one ListAgents-answer builder (T2d, row 64m): the real tick needs a fresh panel.
. "$(dirname "$0")/lib/live-answer.sh"
# The one bound-marker builder (wave-23-fixit-1810 T1): a fixture that means "this session is
# running this plan" binds to it, because an unbound session's newest-plan fallback is
# announced and never acted on.
. "$(dirname "$0")/lib/bound-marker.sh"

# THE MERGED ENTRY POINT (epic-23 wave-11, T12). This gate is a FUNCTION now —
# `stop_patrol_duties` in payload/scripts/lib/stop.sh — and the process that runs it is
# hooks/stop.sh, registered once on Stop and once on SubagentStop. Every fixture below
# drives that process, so each assertion is now a claim about the verdict this gate
# contributes to the composed one rather than about a hook of its own.
HOOK="${BIONIC_PATROL_DUTIES_GATE_UNDER_TEST:-${BIONIC_HOOKS_DIR}/stop.sh}"

# THE SOURCE THE THREE FILE-READING ARMS BELOW ASK (epic-23 wave-11, T12). This
# gate's body lives in payload/scripts/lib/stop.sh now; $HOOK is the process that
# runs it. An arm that reads TEXT reads the library, an arm that DRIVES drives the
# hook, and the two are named separately so neither can silently read the other.
HOOK_SRC="${BIONIC_PATROL_DUTIES_GATE_SRC_UNDER_TEST:-${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/stop.sh}"

# pass/fail were pure-rename shadows of the framework's ok/no; the suite's own
# explicit TOTAL=$((TOTAL + 1)) lines (including the two inside expect_allow/
# expect_block below) are dropped too since ok/no already increment it
# (S7, AC-12). expect_allow/expect_block are suite-specific helpers (not
# owned names) rebuilt on the framework's ok/no.

command -v jq >/dev/null 2>&1 || { echo "patrol-duties-gate: jq absent — suite cannot run"; exit 1; }

PLAN_REL="task-fixture.plan.md"
PLAN_NAME="$PLAN_REL"

# THE FIXTURE SESSION. Spelled once now that two things are built from it: the payload the
# driver ships, and — since task-engaged-session — the engagement marker every fixture
# plants and the `bionic-patrol session=<sid[0:8]>` token that makes a USER row a TICK.
SID="11111111-2222-3333-4444-555555555555"
SID8="${SID:0:8}"

# ---------- fixture builders ----------

# A scratch project with a docs-root plans dir holding ONE plan file, and an
# empty transcript ready to be appended to.
#
# ENGAGED BY DEFAULT since task-engaged-session: this gate asks `engaged_session` before it
# reads a byte of the transcript, so a fixture without the marker would be silent for a
# reason that has nothing to do with the duties under test. The unengaged direction is
# driven deliberately in Group 25, on the same fixtures.
make_env() {  # -> project dir on stdout
  local dir; dir=$(mktemp -d)
  mkdir -p "$dir/.bionic/docs/plans" "$dir/.bionic/tmp"
  : > "$dir/.bionic/tmp/engaged-$SID.state"
  # APPROVED (wave-26 T13; D3): the run's ledger is live on its `approved-by:` line, and 23b
  # reads the fill ledger's line a live Stop writes.
  cat > "$dir/.bionic/docs/plans/$PLAN_REL" <<'EOF'
---
governing-skill: canonical-sdlc
---
## SDLC State

current: 4
approved-by: fixture 2026-10-04T00:00Z "approved"
EOF
  # BOUND TO ITS PLAN (wave-23-fixit-1810, REQ-1, D1). An empty marker beside an open plan is
  # the unbound state, whose `fallback` plan is announced and never acted on — the basename
  # discharge below would never count. Group 24/25 drive the unbound state on purpose.
  bound_marker "$dir" "$SID" "$dir/.bionic/docs/plans/$PLAN_REL"
  : > "$dir/transcript.jsonl"
  printf '%s' "$dir"
}

# A project with NO plans directory at all.
make_env_planless() {
  local dir; dir=$(mktemp -d)
  mkdir -p "$dir/.bionic/tmp"
  : > "$dir/.bionic/tmp/engaged-$SID.state"
  : > "$dir/transcript.jsonl"
  printf '%s' "$dir"
}

# One user PROMPT entry — content is a bare string, the shape a cron-fired tick
# actually has.
u_prompt() {  # <dir> <text>
  jq -nc --arg t "$2" '{type:"user",isMeta:true,isSidechain:false,userType:"external",
                        message:{role:"user",content:$t}}' >> "$1/transcript.jsonl"
}

# The tick itself, verbatim in shape: the patrol prompt leads with the marker
# `bionic-patrol session=<session-id[0:8]>` (skills/canonical-sdlc/SKILL.md §The patrol
# prompt) and the rest of the prompt follows it.
#
# RESHAPED AT task-engaged-session (T6, AC-22). It used to lead with prose and be
# recognised by the substring `session-poker.sh tick` anywhere in the row — a test the
# injected canonical-sdlc SKILL.md body passes, because that body contains the literal.
# Invoking the skill was therefore a Patrol tick as far as this gate could tell, and the
# gate refused the invoking turn for duties no tick had asked for. What identifies a tick
# is the marker the prompt was designed to carry, at the front, naming THIS session.
#
# A TICK TURN IS THE MARKER AND THE TICK (wave-20 REQ-6, D6; AC-6.2). The stop wall now refuses
# a marker turn whose tick never stamped, so a fixture that means "the Patrol fired and ticked"
# plants both halves: the prompt, and the `verb=tick` stamp the tick writes before it decides
# (hooks/session-poker.sh `write_patrol_stamp`). The marker row is undated here, so the stamp's
# verb alone answers for it; the dated rows of §5f drive the "at or after" half. `u_marker` is
# the prompt alone — a cron that fired and a turn that never ran the tick.
u_marker() {  # <dir>
  u_prompt "$1" "bionic-patrol session=$SID8 — Patrol tick for the fixture wave (bionic). Run: bash /abs/hooks/session-poker.sh tick — the poker decides per row; QUIET/DISARM = no-op. Then continue toward the goal until a wall."
}
tick_stamp() {  # <dir> [at ISO] [verb] — the stamp the tick (or `arm`) writes
  printf 'patrol-stamp/v1|at=%s|session=%s|verb=%s\n' \
    "${2:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}" "$SID" "${3:-tick}" > "$1/.bionic/tmp/patrol-$SID.state"
}
u_tick() {  # <dir>
  u_marker "$1"; tick_stamp "$1"
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

# The orchestrator's own words: a turn's prose, and one of the places a decline may be
# written. DEFINED WITH THE OTHER ENTRY BUILDERS, above every case (wave-21 T14): §4's 35e calls
# it, and a definition in §5 left those calls printing "command not found" while the case passed.
a_text() {  # <dir> <text>
  jq -nc --arg t "$2" \
    '{type:"assistant",isSidechain:false,
      message:{role:"assistant",content:[{type:"text",text:$t}]}}' \
    >> "$1/transcript.jsonl"
}

junk() { printf 'not json at all {{{\n' >> "$1/transcript.jsonl"; }

# ---------- driving the hook ----------

stdin_for() {  # <project> <transcript-path> [event] [stop_hook_active]
  jq -nc --arg t "$2" --arg c "$1" --arg e "${3:-Stop}" --argjson a "${4:-false}" --arg s "$SID" \
    '{session_id:$s,transcript_path:$t,cwd:$c,
      hook_event_name:$e,stop_hook_active:$a}'
}

# THE ENVIRONMENT AGREES WITH THE PAYLOAD, because on the machine it does (A-probe-2).
# NEW AT task-engaged-session: this gate now takes its session key from lib/session.sh,
# where the ENV value is primary and the payload a witness — so a driver that left the
# RUNNER's own CLAUDE_CODE_SESSION_ID in the environment would drive every fixture under the
# operator's real session id, find no marker under it, and pass every case in silence. The
# same mirroring hooks/stop-guard.sh's and dispatch-preflight's suites already do.
fire() {  # <project> [event] [stop_hook_active]
  HOOK_OUT=$(env CLAUDE_CODE_SESSION_ID="$SID" bash "$HOOK" <<< "$(stdin_for "$1" "$1/transcript.jsonl" "${2:-Stop}" "${3:-false}")" 2>"${PE1_ERRFILE:-/dev/null}")
  # THE USER STREAM, kept for the AC-E1.3 section at the end (task 13). The JSON reason
  # on stdout is what every arm above reads; this is the one line a reader is shown.
  HOOK_ERR_USER=$(cat "${PE1_ERRFILE:-/dev/null}" 2>/dev/null)
  HOOK_RC=$?
}

# The raw driver takes the id OUT OF THE PAYLOAD it was handed, so a case that ships a
# deliberately odd session key still drives the gate with that key on both channels.
fire_raw() {  # <project> <stdin-json>
  local _sid; _sid=$(printf '%s' "$2" | jq -r '.session_id // ""' 2>/dev/null) || _sid=""
  HOOK_OUT=$(env CLAUDE_CODE_SESSION_ID="$_sid" bash "$HOOK" <<< "$2" 2>/dev/null); HOOK_RC=$?
}

reason_of() { printf '%s' "$HOOK_OUT" | jq -r '.reason // ""' 2>/dev/null; }
decision_of() { printf '%s' "$HOOK_OUT" | jq -r '.decision // ""' 2>/dev/null; }

expect_allow() {  # <label>
  if [ "$HOOK_RC" -eq 0 ] && [ -z "$HOOK_OUT" ]; then
    ok "$1"
  else
    no "$1" "rc=$HOOK_RC stdout=<$HOOK_OUT>"
  fi
}

# A block is the JSON decision payload on stdout, with rc 0 — the form Design
# (T5) names. Every block assertion also states what the reason must NOT say:
# a reason that lists both duties whichever one is missing tells the reader
# nothing, and is the failure this gate's whole value rests on avoiding.
expect_block() {  # <label> <must-contain> [must-not-contain]
  local d r; d=$(decision_of); r=$(reason_of)
  if [ "$HOOK_RC" -ne 0 ]; then
    no "$1" "rc=$HOOK_RC (a JSON block exits 0); stdout=<$HOOK_OUT>"; return
  fi
  if [ "$d" != "block" ]; then
    no "$1" "decision=<$d> expected block; stdout=<$HOOK_OUT>"; return
  fi
  case "$r" in
    *"$2"*) ;;
    *) no "$1" "reason does not name <$2>: $r"; return ;;
  esac
  if [ -n "${3:-}" ]; then
    case "$r" in
      *"$3"*) no "$1" "reason wrongly names <$3>: $r"; return ;;
    esac
  fi
  ok "$1"
}

# THE ROW LIST, NOT THE WHOLE TEXT (wave-27 T37; review pass 42 S1, A-orch-112). The fill refusal
# prints `bash <hooks dir>/session-poker.sh decline <ids> …`, so a must-not over the whole reason
# also reads the checkout's path, and a tree whose path holds `T20` turned 69c red. A row that says
# an id is NOT named reads the ids of the refusal's `decline` operand and matches one as a whole
# word there. The list must be non-empty, so the absence is read off a real list.
refusal_rows() {  # -> the ids the fill refusal's decline operand names, space-joined
  reason_of | /usr/bin/grep -o "session-poker\.sh'\{0,1\} decline [A-Za-z0-9_.,-]*" | head -1 \
    | sed 's/.* decline //' | tr ',' ' '
}
expect_block_unnamed() {  # <label> <id the refusal's row list must not hold>
  local d rows; d=$(decision_of); rows=$(refusal_rows)
  if [ "$HOOK_RC" -ne 0 ] || [ "$d" != "block" ]; then
    no "$1" "rc=$HOOK_RC decision=<$d> expected a block; stdout=<$HOOK_OUT>"; return
  fi
  if [ -z "$rows" ]; then no "$1" "the refusal names no decline row list: $(reason_of)"; return; fi
  case " $rows " in
    *" $2 "*) no "$1" "the row list <$rows> names <$2>"; return ;;
  esac
  ok "$1"
}
# THE SAME READ FOR A ROW THAT NAMES ONE ID AND NOT ANOTHER (wave-31 T34; A-orch-53 (1)). 60c, 60e, 71c and
# L8a asked `expect_block ... "T3" "T2"`, whose must-not is a substring of the WHOLE reason, and the reason
# prints the checkout's path (`bash <hooks dir>/session-poker.sh decline ...` and the scratch path in the
# note), so a tree under `.worktrees/31-T24` held `T2` and all four read red. Both ids are read off the
# refusal's decline operand instead, as whole words, and the list must be non-empty.
expect_block_rows() {  # <label> <id the row list must hold> <id it must not hold>
  local d rows; d=$(decision_of); rows=$(refusal_rows)
  if [ "$HOOK_RC" -ne 0 ] || [ "$d" != "block" ]; then
    no "$1" "rc=$HOOK_RC decision=<$d> expected a block; stdout=<$HOOK_OUT>"; return
  fi
  if [ -z "$rows" ]; then no "$1" "the refusal names no decline row list: $(reason_of)"; return; fi
  case " $rows " in
    *" $2 "*) ;;
    *) no "$1" "the row list <$rows> does not name <$2>"; return ;;
  esac
  case " $rows " in
    *" $3 "*) no "$1" "the row list <$rows> names <$3>"; return ;;
  esac
  ok "$1"
}

LA_MISSING="ListAgents"
TL_MISSING="TaskList or a plan-ledger write"

section "Section 1: the six contract cases (Design T5)"

# 1: tick + both duties -> allow.
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" TaskList
fire "$d"; expect_allow "1: tick + ListAgents + TaskList passes"

# 2: tick + panel refresh only, no TaskList -> ends (wave-31 T32; AC-6.5).
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents
fire "$d"; expect_allow "2: AC-6.5 tick + ListAgents only, no TaskList: not refused (the task-list duty is gone)"

# 3: THE LISTAGENTS DUTY IS RETIRED (T22, A-orch-33; AC-4.4). A tick turn used to be
# refused until the transcript showed a main-thread `ListAgents` call — a chore demanded of
# the model before this gate would let its turn end, which is ADR-024's P-A. The obligation
# it stood for moved to the tick, which reads the roster and prints `poker: TASKSTOP <name>`
# for every MET lineage still open on it (tests/session-poker.test.sh §12a-T22-e). One duty
# remains here, and a tick that discharged it ends its turn.
d=$(make_env); u_tick "$d"; a_tool "$d" TaskList
fire "$d"; expect_allow "3: tick + TaskList alone now passes — the panel duty is retired"

# 4: the version-gated fallback — a write naming the active plan file stands in
# for TaskList, because in a session without the task tools the plan ledger IS
# the task list (the task-tools census in payload/scripts/lib/env.sh).
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

section "Section 2: discrimination — what counts, and when"

# 7: no refresh at all -> ends (wave-31 T32; AC-6.5). Rows 8 to 13 pinned what discharged the
# refresh (its order, the plan-file write, a subagent's TaskList); the duty is gone with them.
d=$(make_env); u_tick "$d"
fire "$d"; expect_allow "7a: AC-6.5 a tick turn with no TaskList and no plan write ends: not refused"
# 7b: THE PAIRED POSITIVE on the same fixture: the marker under an `arm` stamp ran no tick, and the
# wall says so, naming the tick and never a refresh.
tick_stamp "$d" "" arm
fire "$d"; expect_block "7b: …while the same marker turn under an arm stamp is refused for the tick, never a refresh" \
  "session-poker.sh tick" "$TL_MISSING"

# 14: a tool_result carrier is not a prompt. The turn's boundary is the last
# PROMPT; if results reset it, a tick whose duties are separated by any tool
# result reads as a fresh non-tick turn and the wall goes permanently silent.
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; u_result "$d"; a_tool "$d" TaskList
fire "$d"; expect_allow "14: tool_result entries do not end the tick's turn"

# 14b: a tool_result carrier must not reset internal duty/tick bookkeeping either
# -- same fixture family as 14, but only ONE duty is done, so a wrongful reset
# (tick lost -> quiet/allow) is DISCRIMINABLE from the correct outcome (block,
# naming the missing duty), unlike 14 where both outcomes coincide at allow.
d=$(make_env); u_marker "$d"; tick_stamp "$d" "" arm; a_tool "$d" ListAgents; u_result "$d"
fire "$d"; expect_block "14b: a tool_result carrier does not end the marker's turn: the unticked turn is still refused" \
  "session-poker.sh tick" "$TL_MISSING"

# 15: a batch — two tool_uses in one assistant entry.
d=$(make_env); u_tick "$d"; a_tool_batch "$d" ListAgents TaskList
fire "$d"; expect_allow "15: both duties in ONE assistant entry pass"

# 16: a later user prompt ends the tick's turn. The duties belong to the tick,
# and a turn the user started is judged by case 5's rule.
d=$(make_env); u_tick "$d"; u_prompt "$d" "actually, do this instead"
fire "$d"; expect_allow "16: a user prompt after the tick ends the tick's turn"

section "Section 3: fail directions — silence on every ambiguity"

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

# 21/22: NO PLAN, BUT A TICK IS STILL A TICK (task-engaged-session, AC-23). What scopes
# this gate is ENGAGEMENT, not the plan: bionic 1.4.0 scoped it by `active_run`, and that
# walled every session in a repo that merely held an open plan while leaving an engaged
# session at Step 0 — whose plan does not exist yet — unpoliced. Both duties are owed to
# the TICK, and a tick fires as soon as the Patrol is armed, which is at engagement. So a
# plan-less project with an engaged session and a skipped duty is refused; what the missing
# plan costs is only the ALTERNATIVE way to discharge the task-list duty (a write to the
# plan file), which is why the refusal below names the task list and not the panel.
d=$(make_env_planless); u_marker "$d"; tick_stamp "$d" "" arm; a_tool "$d" ListAgents; a_tool "$d" Edit "$d/notes.md"
fire "$d"; expect_block "21: an engaged session with no plan still owes the marker its tick" "session-poker.sh tick" "$TL_MISSING"

# 21b: THE SAME transcript, the SAME plan-less project, the marker removed. A bystander
# session is not policed at all — the pairing that makes 21 a statement about engagement
# rather than about the transcript.
rm -f "$d/.bionic/tmp/engaged-$SID.state"
fire "$d"; expect_allow "21b: …and with no engagement marker it is silent"

# THE PAIRED POSITIVE, and it is what keeps 21 from passing vacuously: the SAME
# transcript, in a project that does have an open run, refuses. Nothing separates the
# two but the plan file.
d=$(make_env); u_marker "$d"; tick_stamp "$d" "" arm; a_tool "$d" ListAgents; a_tool "$d" Edit "$d/notes.md"
fire "$d"; expect_block "22: …and with a plan, the same turn is refused the same way" "session-poker.sh tick" "$TL_MISSING"

# 23: THE GATE WRITES NOTHING. It is a gate, and gates only read (TDD §3.2). The one file the
# Stop process writes is the fill ledger's recorder's (wave-20 REQ-5, AC-5.5), which is not
# this gate: it appends one line under the run's record directory and touches nothing else.
d=$(make_env); u_tick "$d"
_led="$d/.bionic/docs/record/${PLAN_REL%.plan.md}/fill-ledger.log"
_before=$(find "$d" -type f ! -path "$_led" | sort | cksum)
fire "$d"
_after=$(find "$d" -type f ! -path "$_led" | sort | cksum)
if [ "$_before" = "$_after" ]; then
  ok "23: the gate creates and removes no file in the project"
else
  no "23: the gate touched the project tree" "$_before -> $_after"
fi

# 25: THE GATE IS REGISTERED ON THE STOP CHANNEL. A hook with a suite, a run line
# and no registration is the exact shape the landing sweep spent a wave being:
# installed, syntactically fine, green in its own suite, and never fired.
# A hook with a suite, a run line and no registration is installed, green in its own
# suite, and never fired. THE CHANNEL MOVED (bionic 1.4.0, task ADOPT, spec AC-7): this
# gate was registered in the governing skill's frontmatter so it would be live exactly
# while that skill was, and that coupling is the defect — a `/clear`, a compaction or a
# session the skill was never invoked in left the wall installed and not running, while
# the duty it binds went on existing. Both halves are asserted, because either alone is a
# wall in the wrong place: a lingering frontmatter entry fires it twice per turn (the CLI
# does not deduplicate across the two manifests), and a missing manifest entry not at all.
if grep -q '\${CLAUDE_PLUGIN_ROOT}/hooks/stop\.sh' \
     "${BIONIC_HOOKS_DIR}/hooks.json"; then
  ok "25: hooks/hooks.json registers the gate on the Stop channel, always on"
else
  no "25: the gate is not registered in hooks/hooks.json — it would never fire"
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
if grep -q 'never consecutive' "$HOOK_SRC"; then
  ok "26: the header states why the CLI's consecutive-block override cannot engage here"
else
  no "26: the header does not say why the consecutive-block override cannot engage"
fi
if grep -q 'Backstop above ours, from the same reference' "$HOOK"; then
  no "26b: the header still claims a backstop that cannot fire for this hook"
else
  ok "26b: …and no longer claims that backstop as its own"
fi

section "Section 4: the resume/clear ritual arm (bionic 1.4.0, AC-3)"
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
r=$(reason_of)
case "$r" in
  *"$RITUAL_CRONLIST"*"$RITUAL_JOB"*"$RITUAL_CRONCREATE"*"$RITUAL_ARM"*"$RITUAL_ADOPT"*)
    ok "28: the reason states the ritual in order — CronList, delete the stray job, CronCreate, arm, adopt" ;;
  *) no "28: the reason does not state the ritual in order" "$r" ;;
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

# 35a-c: THE RITUAL DISCHARGES. The offending CronCreate never leaves the transcript, so a
# verdict that only ever set `violated` latched: every later turn's first Stop was refused
# again, "blocks once" holding within one turn (case 32) and failing across turns. A CronList
# since the marker is the look the gate exists to force, so it clears the violation whichever
# side of the CronCreate it falls on; a LATER marker still opens a fresh window (35c).
d=$(make_env); u_clear_marker "$d"; a_tool "$d" CronCreate; a_tool "$d" CronList
fire "$d"; expect_allow "35a: a CronList after the CronCreate discharges the ritual"

d=$(make_env); u_clear_marker "$d"; a_tool "$d" CronCreate; a_tool "$d" CronList
a_tool "$d" CronDelete; a_tool "$d" CronCreate
fire "$d"; expect_allow "35b: CronCreate, CronList, CronDelete, CronCreate — the whole ritual in the order the refusal asks — passes"

d=$(make_env); u_clear_marker "$d"; a_tool "$d" CronCreate; a_tool "$d" CronList
u_clear_marker "$d"; a_tool "$d" CronCreate
fire "$d"; expect_block "35c: a CronList before a LATER marker does not discharge the new window" "$RITUAL_CRONLIST"

# 35d: THE STEP-3 TEXT. A session whose own Patrol job already exists has nothing to re-create,
# so the refusal's step 3 is conditional on what step 2 left.
d=$(make_env); u_clear_marker "$d"; a_tool "$d" CronCreate
fire "$d"
case "$(reason_of)" in
  *"3. CronCreate — only if step 2 left this session with no Patrol job of its own"*)
    ok "35d: step 3 of the refusal is conditional on step 2's result" ;;
  *) no "35d: step 3 of the refusal is still unconditional" "$(reason_of)" ;;
esac

# 35e: THE LATER TURN (wave-21 T13; walk-3b45d05 item 3). The window since the marker stays open
# until a CronList, so the block repeats on the turn AFTER the one that created the cron — and
# its reason opened "This is the first Stop after a /clear or a resume", false on that turn.
# The text says what is true on every turn it fires: the window is open until a CronList.
d=$(make_env); u_clear_marker "$d"; a_tool "$d" CronCreate; a_text "$d" "armed."
u_prompt "$d" "carry on with the wave"; a_text "$d" "on it."
# THE LATER TURN IS REAL ONLY IF ITS TEXT LANDED (wave-21 T14; floor-4e6d4a9). `a_text` was
# defined below this case, so both calls printed "command not found" and the fixture had no
# assistant entry after the prompt — the case still passed, on a transcript that was not the
# one it describes. The fixture is asserted first: the CronCreate's turn said "armed.", the
# later turn said only "on it." and made no Cron call.
expect_eq "35e0 precondition: the CronCreate's turn and the later turn each carry their text" "armed.|on it." \
  "$(jq -sr '[.[] | select(.type=="assistant") | .message.content[] | select(.type=="text") | .text] | join("|")' \
       "$d/transcript.jsonl" 2>/dev/null)"
expect_eq "35e0b precondition: …and the later turn made no Cron call" "0" \
  "$(jq -sr '(map(.type=="user" and (.message.content|type)=="string") | rindex(true)) as $i
             | .[($i+1):] | [.[] | select(.type=="assistant") | .message.content[]
             | select(.type=="tool_use" and (.name|startswith("Cron")))] | length' \
       "$d/transcript.jsonl" 2>/dev/null)"
fire "$d"; expect_block "35e: a later turn with the window still open is refused, saying the window is open until a CronList" \
  "stays open until a CronList" "This is the first Stop"

section "Section 5: a printed FILL is advice, not evidence (AC-29, retired by wave-20 Δ7)"

# THE CONTRACT. `session-poker.sh tick` can compute the gap between the plan's budget and
# the roster and name the tasks that are ready, but it cannot dispatch — and a
# recommendation nobody is obliged to answer is how this repo's own 1.4.0 wave ran six
# writers against a budget of twenty-two. The turn's END is the only moment at which "the
# FILL went unanswered" is a fact, so it is the moment this gate asks.
#
# ANSWERED = an `Agent` tool_use naming the task, or an explicit `fill-declined: <reason>`
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

# One Agent dispatch, shaped as the harness sends it: the task id may land in the name, the
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

# A TASK ENTRY SET IN PROGRESS (wave-28 T38; REQ-13, D30), the harness's TaskUpdate shape. A turn
# that dispatched plan rows owes one per row, so a row here that pins "the dispatching turn ends"
# sets them, as the doctrine's dispatch turn does.
# Since wave-31 T32 (D6) no wall counts it: the rows that call it keep the doctrine's dispatch turn
# whole, and §5c's AC-6.5 row drives the same dispatch with none.
a_taskup() {  # <dir> <task number>
  jq -nc --arg n "$2" \
    '{type:"assistant",isSidechain:false,agentId:null,
      message:{role:"assistant",content:[{type:"tool_use",id:("toolu_up" + $n),name:"TaskUpdate",
        input:{taskId:$n,status:"in_progress"}}]}}' \
    >> "$1/transcript.jsonl"
}

both_duties() {  # <dir> — the two standing duties, so §5 measures the THIRD one alone
  a_tool "$1" ListAgents; a_tool "$1" TaskList
}

FILL_MARK="fill unanswered"

# THE PRINTED FILL IS ADVICE NOW (wave-20 REQ-5, AC-5.4; Δ7; ADR-036 decision 3). Rows 36-47
# used to pin a wall that read the tick's `poker: FILL <ids>` out of the transcript and asked
# for each printed id to be answered by an Agent call NAMING it. Every way of planting that
# line reproduced (research D1 §4): the model's own prose, a file read, a grep. The wall now
# computes the ready set and the pressure state itself and judges the turn by count (§5c,
# §5d), so on this section's fixture — a task-shaped plan with no table, nothing ready — a
# printed FILL is owed nothing, whoever printed it.

# 36: a tick turn whose tick printed FILL, both duties done, nothing dispatched: the wall's own
# ready set is empty, so the printed line binds nothing.
d=$(make_env); u_tick "$d"; both_duties "$d"; u_tick_out "$d" "poker: FILL ALPHA BETA"
fire "$d"; expect_allow "36: Δ7 a printed FILL over an empty computed ready set is not a duty"

# 37: …and with no refresh either the turn ends (wave-31 T32; AC-6.5).
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; u_tick_out "$d" "poker: FILL ALPHA"
fire "$d"; expect_allow "37: AC-6.5 a tick turn with a printed FILL and no refresh ends: neither is owed"
# 37b: the paired positive: the same turn under an arm stamp is refused for the tick, and never
# names the printed id — the FILL line is not evidence.
tick_stamp "$d" "" arm
fire "$d"; expect_block "37b: …and the same turn unticked is refused for the tick, never the printed id" "session-poker.sh tick" "ALPHA"

# 41: INERT with no FILL line, as before.
d=$(make_env); u_tick "$d"; both_duties "$d"; u_tick_out "$d" "poker: QUIET — 0 open row(s)"
fire "$d"; expect_allow "41: a tick that printed no FILL is not asked about one"

# 45: BLOCKS ONCE, through the existing stop_hook_active valve — no new bookkeeping.
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; u_tick_out "$d" "poker: FILL ALPHA"
fire "$d" Stop true
expect_allow "45: stop_hook_active true passes the same turn"

# 47: a non-tick turn is never asked about a printed line either.
d=$(make_env); u_prompt "$d" "run the suite and tell me what broke"
u_tick_out "$d" "poker: FILL ALPHA"
fire "$d"; expect_allow "47: a turn the user started is not asked about a FILL"

section "Section 5b: the fourth duty — a stand-down the tick ordered is answered (AC-1.2; T1, D1; wave-20 T19)"
#
# THE CONTRACT. `session-poker.sh tick` stands down every row whose contract is MET and whose
# agent the harness still lists: it prints `poker: STANDDOWN <name>` for the human and writes
# the stop order (`stop-orders.sh order <name> --by patrol`) that makes the TaskStop pass the
# stop gate. It cannot stop anything — the tick holds no authority (ADR-003) — so what it
# decided is a duty the turn's END is the only moment to judge: a recommendation nobody is
# obliged to answer is how eighteen finished agents came to sit idle on one panel.
#
# THE WALL COMPUTES THE SET; IT OVERHEARS NOTHING (wave-20 T19, the carry-over of T11's AC-5.4
# work; D5). These rows used to plant the tick's printed line in a tool result and nothing
# on disk, because the wall read the SET off that line — the channel AC-5.4 closed for the
# FILL: a model's own prose could plant a name, a `cat` of a file could forge one, and a tick
# output nobody showed let every name go. The set is now what the tick WROTE, read back from
# disk: this session's MET, unacked lineages (the sweeper's verdict) carrying a `by=patrol`
# stop order stamped at or after this turn's tick stamp. The printed line still rides in the
# fixtures that model a real tick, for realism; the §SD rows below take it away, restate it
# and forge it, and none of that moves the verdict.
#
# ANSWERED = a main-thread `TaskStop` tool_use naming the agent (by its name or by the address
# the roster carries for it) that the harness did not refuse, an ack closing the row, or a
# `standdown-declined: <name> <reason>` line at the start of a line of the model's own text —
# the fill-declined rule (AC-5.4). The decline is the point, not a loophole: an agent still
# writing its record is a good reason not to stop it, and it is worth one line in the record.

# The stop itself, shaped as the harness sends it: the id may be the agent's name or the
# `name@session-xxxxxxxx` address the launch response handed back.
a_taskstop() {  # <dir> <task-id> [tool_use id]
  jq -nc --arg t "$2" --arg id "${3:-toolu_7}" \
    '{type:"assistant",isSidechain:false,
      message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"TaskStop",
        input:{task_id:$t}}]}}' \
    >> "$1/transcript.jsonl"
}

sd_line() {  # <name> -> the tick's own line, verbatim in shape
  printf 'poker: STANDDOWN %s — contract MET and the agent is still on the panel; TaskStop it (the order is written)' "$1"
}

SD_ORDERS="${BIONIC_HOOKS_DIR}/stop-orders.sh"
SD_SWEEPER="${BIONIC_HOOKS_DIR}/session-sweeper.sh"

# A MET lineage on this session's roster: a declared deliverable that exists, written after
# the fixture launch instant (the shape row 64m's real tick stands down).
sd_met() {  # <dir> <name>
  echo done > "$1/landed-$2.md"
  roster_row_fixture status=intended session="$SID" name="$2" agent_id= \
    deliverable="$1/landed-$2.md" >> "$1/.bionic/tmp/roster-$SID.state"
}
# An UNMET lineage: the declared deliverable was never written.
sd_unmet() {  # <dir> <name>
  roster_row_fixture status=intended session="$SID" name="$2" agent_id= \
    deliverable="$1/never-$2.md" >> "$1/.bionic/tmp/roster-$SID.state"
}
# The stop order, through the real verb — exactly the call the tick's stand-down arm makes.
sd_order() {  # <dir> <name> [by]
  ( cd "$1" && env CLAUDE_CODE_SESSION_ID="$SID" bash "$SD_ORDERS" order "$2" --by "${3:-patrol}" >/dev/null 2>&1 )
}
# What a tick that printed `STANDDOWN <name>` leaves on disk: the MET row and its order.
sd_stood() {  # <dir> <name>
  sd_met "$1" "$2"; sd_order "$1" "$2"
}

SD_MISSING="stand-down unanswered"

# 48: neither stopped nor declined -> block, naming the agent and the way out.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_stood "$d" W-ALPHA; u_tick_out "$d" "$(sd_line W-ALPHA)"
fire "$d"; expect_block "48a: an unanswered stand-down blocks, naming the agent" "W-ALPHA"
fire "$d"; expect_block "48b: …and says what would answer it: the hold verb, and no line in the reply (wave-27 T34)" "session-poker.sh hold W-ALPHA" "standdown-declined"
fire "$d"; expect_block "48c: …and says the gate blocks once" "this gate blocks once"

# 49: the TaskStop answers it.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_stood "$d" W-ALPHA; u_tick_out "$d" "$(sd_line W-ALPHA)"
a_taskstop "$d" "W-ALPHA"
fire "$d"; expect_allow "49: a TaskStop of the named agent answers the stand-down"

# 49b: the ADDRESS is what an operator actually types, and it carries the name.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_stood "$d" W-ALPHA; u_tick_out "$d" "$(sd_line W-ALPHA)"
a_taskstop "$d" "W-ALPHA@session-11111111"
fire "$d"; expect_allow "49b: a TaskStop by the roster address answers it too"

# 50: the DECLINE answers it — a reason in the record is the point.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_stood "$d" W-ALPHA; u_tick_out "$d" "$(sd_line W-ALPHA)"
a_text "$d" "standdown-declined: W-ALPHA is still writing its record, one more cadence."
fire "$d"; expect_allow "50: an explicit standdown-declined line answers the stand-down"

# 51: NAMED, NOT COUNTED. Two stood down, one stopped -> the refusal names the other one
# and not the one that was answered.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_stood "$d" W-ALPHA; sd_stood "$d" W-BETA
u_tick_out "$d" "$(sd_line W-ALPHA)"; u_tick_out "$d" "$(sd_line W-BETA)"
a_taskstop "$d" "W-ALPHA"
fire "$d"; expect_block "51: a half-answered stand-down names the agent left running" "W-BETA" "W-ALPHA"

# 52: a decline for ANOTHER name does not answer this one. The decline is per agent, because
# the instruction is: `standdown-declined: <name> <reason>`.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_stood "$d" W-ALPHA; sd_stood "$d" W-BETA
u_tick_out "$d" "$(sd_line W-ALPHA)"; u_tick_out "$d" "$(sd_line W-BETA)"
a_taskstop "$d" "W-ALPHA"
a_text "$d" "standdown-declined: W-GAMMA is not even on this roster."
fire "$d"; expect_block "52: a decline naming a third agent leaves this one unanswered" "W-BETA"

# 53: INERT when the tick stood nothing down — every turn in every session whose tick prints none.
d=$(make_env); u_tick "$d"; both_duties "$d"; u_tick_out "$d" "poker: QUIET — 0 open row(s)"
fire "$d"; expect_allow "53: a tick that stood nothing down is not asked about one"

# 54: ORDERING. A stand-down ordered in an EARLIER turn is not this turn's to answer.
# RE-AUTHORED at wave-20 T19: the earlier turn's line is no longer what binds, the earlier
# tick's ORDER is — so the order is dated before this turn's tick stamp, which is what a tick
# one Patrol interval later leaves on disk. Same claim, on the fact the wall now reads.
d=$(make_env); u_tick "$d"; sd_stood "$d" W-ALPHA; u_tick_out "$d" "$(sd_line W-ALPHA)"
sed -i.bak 's/|at=[^|]*|/|at=2026-01-01T00:00:00Z|/' "$d/.bionic/tmp/stop-orders-$SID.state"
u_tick "$d"; both_duties "$d"
fire "$d"; expect_allow "54: a stand-down from a previous turn does not bind this one"

# 55: a non-tick turn is never asked, whatever its transcript or the disk carries.
d=$(make_env); u_prompt "$d" "run the suite and tell me what broke"; sd_stood "$d" W-ALPHA
u_tick_out "$d" "$(sd_line W-ALPHA)"
fire "$d"; expect_allow "55: a turn the user started is not asked about a stand-down"

# 56: BLOCKS ONCE, through the same stop_hook_active valve the other three duties use.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_stood "$d" W-ALPHA; u_tick_out "$d" "$(sd_line W-ALPHA)"
fire "$d" Stop true
expect_allow "56: stop_hook_active true passes the same unanswered stand-down"

# 57: an agent-context TaskStop is not the orchestrator's — the same exclusion every other
# arm of this gate makes.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_stood "$d" W-ALPHA; u_tick_out "$d" "$(sd_line W-ALPHA)"
jq -nc '{type:"assistant",isSidechain:true,
         message:{role:"assistant",content:[{type:"tool_use",id:"toolu_7",name:"TaskStop",
           input:{task_id:"W-ALPHA"}}]}}' >> "$d/transcript.jsonl"
fire "$d"; expect_block "57: a sidechain TaskStop does not answer the orchestrator's stand-down" "W-ALPHA"

# 58: THE PRINTED FILL BESIDE A STAND-DOWN IS STILL ONLY ADVICE (wave-20 Δ7). The stand-down
# is answered for its own name; the FILL line names nothing the wall computed, so it adds
# nothing to the refusal. "Both told at once" is now the computed gap beside a stand-down,
# row 58c in §5c.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_stood "$d" W-BETA
u_tick_out "$d" "poker: FILL ALPHA"; u_tick_out "$d" "$(sd_line W-BETA)"
fire "$d"; expect_block "58a: a stand-down beside a printed FILL names the agent" "W-BETA" "ALPHA"
fire "$d"; expect_block "58b: …and never the printed FILL's id" "W-BETA" "$FILL_MARK"

# ---------- §SD: the four plants AC-5.4 closed for the FILL, on the stand-down (wave-20 T19) ----
#
# Each row is a way the old read could be steered from the transcript: a name the model
# RESTATES in its own text, a tick line OMITTED from what the transcript shows, a line FORGED
# into a tool result by reading a file, and a DECLINE that is not the model's own line. None
# of them may move the verdict, in either direction.

# SD1: RESTATED. The model's own text carries the tick's line for a name the tick did not
# stand down -> nothing is owed.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_met "$d" W-GHOST
a_text "$d" "$(sd_line W-GHOST)"
fire "$d"; expect_allow "SD1: AC-5.4 a stand-down line restated in the model's prose plants no duty"
# SD1b: …and beside a real stand-down it adds no name to the refusal.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_stood "$d" W-ALPHA; sd_met "$d" W-OTHER
a_text "$d" "$(sd_line W-OTHER)"
fire "$d"; expect_block "SD1b: a restated line adds no name — only the ordered agent is named" "W-ALPHA" "W-OTHER"

# SD2: OMITTED. The tick stood W-ALPHA down on disk and its line never reached the transcript
# (output unshown, redirected, or the turn ran it inside another command) -> still owed.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_stood "$d" W-ALPHA
fire "$d"; expect_block "SD2: AC-5.4 a stand-down whose line is omitted is still owed" "W-ALPHA"

# SD3: FORGED. A `cat` of a file puts the line at column 0 of a tool result, for a MET row
# the tick did not order -> nothing is owed.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_met "$d" W-FORGED
u_tick_out "$d" "$(sd_line W-FORGED)"
fire "$d"; expect_allow "SD3: AC-5.4 a stand-down line forged into a tool result plants no duty"

# SD4: DECLINE IN PROSE. Mid-line, the decline is a sentence about declining, not a decline.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_stood "$d" W-ALPHA
a_text "$d" "If it comes to it I would write standdown-declined: W-ALPHA — but not yet."
fire "$d"; expect_block "SD4: AC-5.4 a decline mid-line in prose answers nothing" "W-ALPHA"
# SD4b: …in thinking, it is not the model's reply.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_stood "$d" W-ALPHA
jq -nc '{type:"assistant",isSidechain:false,
         message:{role:"assistant",content:[{type:"thinking",thinking:"standdown-declined: W-ALPHA still writing"}]}}' \
  >> "$d/transcript.jsonl"
fire "$d"; expect_block "SD4b: a decline in thinking answers nothing" "W-ALPHA"
# SD4c: …in a tool result (a grep of the phrase), it is a file's words.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_stood "$d" W-ALPHA
u_tick_out "$d" "standdown-declined: W-ALPHA planted by a grep"
fire "$d"; expect_block "SD4c: a decline in a tool result answers nothing" "W-ALPHA"

# SD5: THE ACK CLOSES IT. A row the ledger closed after the tick ordered it (the sweeper's ack
# — what `stop-orders.sh stopped` writes) is not owed, whatever the tick printed.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_stood "$d" W-ALPHA; u_tick_out "$d" "$(sd_line W-ALPHA)"
( cd "$d" && env CLAUDE_CODE_SESSION_ID="$SID" bash "$SD_SWEEPER" ack W-ALPHA --by human --reason landed >/dev/null 2>&1 )
fire "$d"; expect_allow "SD5: an acked row is not owed a stop"

# SD6: MET LINEAGES ONLY. An order standing on a row that is not MET (never landed) is not a
# stand-down the tick made, whatever the transcript prints.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_unmet "$d" W-UNMET; sd_order "$d" W-UNMET
u_tick_out "$d" "$(sd_line W-UNMET)"
fire "$d"; expect_allow "SD6: an ordered row that is not MET is not owed a stand-down"

# SD7: THE TICK'S ORDER, NOT ANY ORDER. A human's order is an instruction to the stop gate, not
# a stand-down the tick decided.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_met "$d" W-ALPHA; sd_order "$d" W-ALPHA human
fire "$d"; expect_allow "SD7: a human's stop order is not the tick's stand-down"
# SD7b: THE PAIRED POSITIVE — the same row, ordered by the patrol.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_met "$d" W-ALPHA; sd_order "$d" W-ALPHA patrol
fire "$d"; expect_block "SD7b: …the same row ordered by the patrol is owed" "W-ALPHA"

# SD8: A REFUSED TaskStop STOPPED NOTHING. The harness answered the call with an error, so the
# agent is still on the panel and the stand-down is still owed.
d=$(make_env); u_tick "$d"; both_duties "$d"; sd_stood "$d" W-ALPHA
a_taskstop "$d" "W-ALPHA" toolu_SD8
jq -nc '{type:"user",isSidechain:false,
         message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_SD8",is_error:true,content:"refused"}]}}' \
  >> "$d/transcript.jsonl"
fire "$d"; expect_block "SD8: a TaskStop the harness refused does not answer the stand-down" "W-ALPHA"

# SD9: NO TICK STAMPED THIS TURN, NO STAND-DOWN SET. A marker turn whose tick never ran owes the
# tick (§5f), and the orders on disk belong to whichever tick wrote them — not to this turn.
d=$(make_env); u_marker "$d"; sd_stood "$d" W-ALPHA
tick_stamp "$d" "2026-01-01T00:00:00Z" arm
both_duties "$d"
fire "$d"; expect_block "SD9: a marker turn that ran no tick is refused for the tick" "Patrol tick not run" "W-ALPHA"

# ============================================================
finish
