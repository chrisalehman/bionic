#!/bin/bash
# Tests for hooks/patrol-duties-gate.sh — the PATROL-DUTIES WALL.
#
# THE CONTRACT UNDER TEST. The turn's END is the wall for what the tick decided and only the
# model can do: a fillable gap left undispatched, and a stand-down the tick ordered since the
# previous turn end left unanswered.
#
# HARNESS IDIOM mirrored tests/context-spend.test.sh (deleted at 8582861, epic-18
# wave-03): PASS/FAIL counters, mktemp
# projects, resolve-roots for the hook path, real-shape Stop stdin JSON. The
# transcript fixtures replay the JSONL shapes read out of live transcripts under
# ~/.claude/projects/-Users-admin-workspace-personal-bionic/ on 2026-08-22:
#
#   a turn's prompt           -> {"type":"user", ..., "message":{"content":"..."}}
#                                content is a STRING, isSidechain false
#   a tool call               -> {"type":"assistant", "isSidechain":false,
#                                 "message":{"content":[{"type":"tool_use","name":"ListAgents","input":{}}]}}
#                                main-thread entries carry NO agentId/agent_id
#   a tool result             -> {"type":"user", "message":{"content":[{"type":"tool_result",...}]}}
#
# THE TASK-LIST DUTIES ARE GONE (wave-31 T32; D6, REQ-6 AC-6.5). No tick turn owes a task-list
# refresh and no dispatch turn owes a task entry set in progress: a process check the turn's end
# demanded of the model, with nothing behind it to do. The tick still prints `poker: RECONCILE` and
# writes `duty=` to its digest, as advice no wall reads. What this wall still refuses is an
# unanswered FILL, and a stand-down the tick ordered since the previous turn end left unanswered.
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
. "$(dirname "$0")/lib/duty-read.sh"

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
# driver ships, and — since task-engaged-session — the engagement marker every fixture plants.
SID="11111111-2222-3333-4444-555555555555"

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
  # APPROVED: the run's ledger is live on its approval, and 23b reads the fill ledger's line a live Stop writes.
  # The page is at 15, its step and approval in the run's log.
  plan_fixture "$dir/.bionic/docs/plans/$PLAN_REL" task > /dev/null
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

# A turn's prompt, and the previous turn's end: the transcript's `stop_hook_summary` record, the
# instant the stand-down duty counts the tick's orders from.
u_tick() {  # <dir>
  u_prompt "$1" "continue the fixture wave"
}
u_end() {  # <dir> <ISO>
  jq -nc --arg t "$2" '{type:"system",subtype:"stop_hook_summary",timestamp:$t}' >> "$1/transcript.jsonl"
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

# The orchestrator's own words: a turn's prose, and the one place a stand-down decline may be
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
# same mirroring the suites of hooks/stop.sh and dispatch-preflight already do.
fire() {  # <project> [event] [stop_hook_active]
  FIRE_D="$1"
  HOOK_OUT=$(env CLAUDE_CODE_SESSION_ID="$SID" bash "$HOOK" <<< "$(stdin_for "$1" "$1/transcript.jsonl" "${2:-Stop}" "${3:-false}")" 2>"${PE1_ERRFILE:-/dev/null}")
  # THE USER STREAM, kept for the AC-E1.3 section at the end (task 13). The JSON reason
  # on stdout is what every arm above reads; this is the one line a reader is shown.
  HOOK_ERR_USER=$(cat "${PE1_ERRFILE:-/dev/null}" 2>/dev/null)
  HOOK_RC=$?
}

# The raw driver takes the id OUT OF THE PAYLOAD it was handed, so a case that ships a
# deliberately odd session key still drives the gate with that key on both channels.
fire_raw() {  # <project> <stdin-json>
  FIRE_D="$1"
  local _sid; _sid=$(printf '%s' "$2" | jq -r '.session_id // ""' 2>/dev/null) || _sid=""
  HOOK_OUT=$(env CLAUDE_CODE_SESSION_ID="$_sid" bash "$HOOK" <<< "$2" 2>/dev/null); HOOK_RC=$?
}

# Every duty this gate owes is the agent's, so it is read on the duty channel (tests/lib/duty-read.sh).
FIRE_D=""
reason_of() { duty_reason "$HOOK_OUT" "$(duty_path "$FIRE_D" "$SID")"; }
decision_of() { duty_channel "$HOOK_OUT"; }

expect_allow() {  # <label>
  if [ "$HOOK_RC" -eq 0 ] && [ -z "$HOOK_OUT" ]; then
    ok "$1"
  else
    no "$1" "rc=$HOOK_RC stdout=<$HOOK_OUT>"
  fi
}

# A refusal of this gate is the duty on stdout, with rc 0: the agent's fix, so the agent's channel. Every
# refusal assertion also states what the reason must NOT say:
# a reason that lists both duties whichever one is missing tells the reader
# nothing, and is the failure this gate's whole value rests on avoiding.
expect_block() {  # <label> <must-contain> [must-not-contain]
  local d r; d=$(decision_of); r=$(reason_of)
  if [ "$HOOK_RC" -ne 0 ]; then
    no "$1" "rc=$HOOK_RC (a JSON block exits 0); stdout=<$HOOK_OUT>"; return
  fi
  if [ "$d" != "duty" ]; then
    no "$1" "decision=<$d> expected duty; stdout=<$HOOK_OUT>"; return
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

TL_MISSING="TaskList or a plan-ledger write"

section "Section 2: discrimination — what counts, and when"

# 7: no refresh at all -> ends (wave-31 T32; AC-6.5). Rows 8 to 13 pinned what discharged the
# refresh (its order, the plan-file write, a subagent's TaskList); the duty is gone with them.
d=$(make_env); u_tick "$d"
fire "$d"; expect_allow "7a: AC-6.5 a tick turn with no TaskList and no plan write ends: not refused"
# 14: a tool_result carrier is not a prompt. The turn's boundary is the last
# PROMPT; if results reset it, a tick whose duties are separated by any tool
# result reads as a fresh non-tick turn and the wall goes permanently silent.
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; u_result "$d"; a_tool "$d" TaskList
fire "$d"; expect_allow "14: tool_result entries do not end the tick's turn"

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

# 23: THE GATE WRITES NOTHING. It is a gate, and gates only read (TDD §3.2). The one file the
# Stop process writes is the run's log, where the recorder of the turn's `stop` event, which is
# not this gate, appends one line under the run's record directory and touches nothing else.
d=$(make_env); u_tick "$d"
_led="$d/.bionic/docs/record/${PLAN_REL%.plan.md}/run.log"
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
# stop order stamped at or after the previous turn end. The printed line still rides in the
# fixtures that model a real tick, for realism; the §SD rows below take it away, restate it
# and forge it, and none of that moves the verdict.
#
# ANSWERED = a main-thread `TaskStop` tool_use naming the agent (by its name or by the address
# the roster carries for it) that the harness did not refuse, an ack closing the row, or a
# `standdown-declined: <name> <reason>` line at the start of a line of the model's own text,
# never a quote of one. The decline is the point, not a loophole: an agent still
# writing its record is a good reason not to stop it, and it is worth one line in the record.

# The stop itself, shaped as the harness sends it: the id may be the agent's name or the
# `name@session-xxxxxxxx` address the launch response handed back.
# A tool_result carrying the tick's output.
u_tick_out() {  # <dir> <text>
  jq -nc --arg t "$2" \
    '{type:"user",isSidechain:false,
      message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_x",content:$t}]}}' \
    >> "$1/transcript.jsonl"
}

both_duties() {  # <dir> — the two standing duties, so §5 measures the THIRD one alone
  a_tool "$1" ListAgents; a_tool "$1" TaskList
}

FILL_MARK="fill unanswered"

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

# 54: ORDERING. A stand-down ordered before the previous turn ended was that turn's to answer.
d=$(make_env); u_tick "$d"; sd_stood "$d" W-ALPHA; u_tick_out "$d" "$(sd_line W-ALPHA)"
sed -i.bak 's/|at=[^|]*|/|at=2026-01-01T00:00:00Z|/' "$d/.bionic/tmp/stop-orders-$SID.state"
u_end "$d" 2026-06-01T00:00:00.000Z; u_tick "$d"; both_duties "$d"
fire "$d"; expect_allow "54: a stand-down ordered before the previous turn end does not bind this one"

# 55: …and one ordered since it binds whatever started the turn: a reply of the person's too.
d=$(make_env); u_end "$d" 2026-01-01T00:00:00.000Z; u_prompt "$d" "run the suite and tell me what broke"; sd_stood "$d" W-ALPHA
fire "$d"; expect_block "55: a stand-down ordered since the previous turn end binds a turn the person started" "W-ALPHA"

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

# ============================================================
finish
