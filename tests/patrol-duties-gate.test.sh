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
. "$(dirname "$0")/lib/assert.sh"
# The one roster-row builder and the one swept-marker writer (S17): wave-19's fill fixtures
# write this session's roster through them rather than spelling either shape by hand.
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
# The one ListAgents-answer builder (T2d, row 64m): the real tick needs a fresh panel.
. "$(dirname "$0")/lib/live-answer.sh"

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

LA_MISSING="ListAgents"
TL_MISSING="TaskList or a plan-ledger write"

section "Section 1: the six contract cases (Design T5)"

# 1: tick + both duties -> allow.
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" TaskList
fire "$d"; expect_allow "1: tick + ListAgents + TaskList passes"

# 2: tick + panel refresh only -> block naming the task-list side AND its
# fallback, and NOT naming ListAgents (which was done).
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents
fire "$d"; expect_block "2: tick + ListAgents only blocks, naming TaskList or a plan-ledger write" \
  "$TL_MISSING" "$LA_MISSING"

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

section "Section 2: discrimination — what counts, and when"

# 7: no duty at all -> the reason names the one that is left, and never the retired one.
d=$(make_env); u_tick "$d"
fire "$d"; expect_block "7a: tick + no refresh blocks, naming the task list" "$TL_MISSING"
fire "$d"; expect_block "7b: …and the retired panel duty is never named" "$TL_MISSING" "$LA_MISSING"

# 8: ORDERING. Both duties performed BEFORE the tick arrived satisfy nothing —
# the panel and the task list are stale by exactly the interval the tick exists
# to cover. Without this the wall passes every tick in any session that ever
# called ListAgents once.
d=$(make_env); a_tool "$d" ListAgents; a_tool "$d" TaskList; u_tick "$d"
fire "$d"; expect_block "8a: a refresh performed BEFORE the tick does not count" "$TL_MISSING"
fire "$d"; expect_block "8b: …and the retired panel duty is not named either" "$TL_MISSING" "$LA_MISSING"

# 9/10: the fallback's other two shapes.
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" Write "$d/.bionic/docs/plans/$PLAN_REL"
fire "$d"; expect_allow "9: a Write naming the plan satisfies the task-list duty"

d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents
a_tool "$d" Bash "printf '%s\\n' 'row' >> .bionic/docs/plans/$PLAN_NAME"
fire "$d"; expect_allow "10: a Bash command naming the plan satisfies the task-list duty"

# 11: a write to something else is not a ledger write.
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" Edit "$d/notes.md"
fire "$d"; expect_block "11: an Edit naming a different file does not satisfy it" "$TL_MISSING" "$LA_MISSING"

# 12/13: agent-context calls are not the orchestrator's — RE-POINTED at the duty that is
# left (T22). The claim is about the SCOPE of the fold, not about which tool it looks for:
# a subagent's TaskList did not refresh the orchestrator's ledger, so it satisfies nothing.
d=$(make_env); u_tick "$d"; a_tool_sidechain "$d" TaskList
fire "$d"; expect_block "12: a sidechain TaskList does not count" "$TL_MISSING" "$LA_MISSING"

d=$(make_env); u_tick "$d"; a_tool_agentid "$d" TaskList
fire "$d"; expect_block "13: a TaskList carrying an agentId does not count" "$TL_MISSING" "$LA_MISSING"

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
d=$(make_env_planless); u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" Edit "$d/notes.md"
fire "$d"; expect_block "21: an engaged session with no plan still owes the tick its duties" "$TL_MISSING" "$LA_MISSING"

# 21b: THE SAME transcript, the SAME plan-less project, the marker removed. A bystander
# session is not policed at all — the pairing that makes 21 a statement about engagement
# rather than about the transcript.
rm -f "$d/.bionic/tmp/engaged-$SID.state"
fire "$d"; expect_allow "21b: …and with no engagement marker it is silent"

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
expect_eq "23b: …and the Stop's one write is the fill ledger's line" "1" "$(wc -l < "$_led" 2>/dev/null | tr -d ' ')"

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
if grep -q '\${CLAUDE_PLUGIN_ROOT}/hooks/patrol-duties-gate\.sh' \
     "${BIONIC_SKILLS_DIR}/canonical-sdlc/SKILL.md"; then
  no "25b: SKILL.md still registers the gate — a second registration fires it twice per turn"
else
  ok "25b: …and SKILL.md's frontmatter does not, so it fires exactly once"
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

# 37: …and the wording of the retired arm never appears.
d=$(make_env); u_tick "$d"; a_tool "$d" ListAgents; u_tick_out "$d" "poker: FILL ALPHA"
fire "$d"; expect_block "37: a tick turn missing its task-list refresh still names that duty" "$TL_MISSING" "$FILL_MARK"
fire "$d"; expect_block "37b: …and never the printed id — the FILL line is not evidence" "$TL_MISSING" "ALPHA"

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
fire "$d"; expect_block "48b: …and says what would answer it" "standdown-declined"
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
section "Section 5c: the fill duty is an INVARIANT — a live ledger with rows ready (wave-18 REQ-3, AC-3.2; ADR-033 d2)"
#
# WHAT CHANGED, AND WHY. Every row above this one is about a tick: the duty existed only
# because the tick had PRINTED a line, so the gate read the transcript for `poker: FILL ` and
# went inert when it found none. That makes the wall a function of the Patrol's cadence
# rather than of the run's state — a turn ending with three rows ready, twenty minutes before
# the next tick, ended in silence. The stop library computes the ready set itself now
# (payload/scripts/lib/fill.sh, the same function the tick prints from), so the question is
# the run's: is the ledger live, and is there a fillable gap.
#
# A TICK THAT PRINTED FILL IS ANSWERED BY ITS PRINTED IDS in the wording §5 pins. A tick
# that printed NONE is no longer exempt (wave-19 REQ-4, D6; ADR-034 decision 3): it is judged
# like a no-tick turn against the ready set this wall computes, and the one exemption left is
# a `poker: fill withheld — HOLD|EMERGENCY` line — a machine fact the plan cannot hold.
#
# THE FIXTURE IS A PLAN AND A ROSTER. The plan carries the budget Step 0 measured, a
# `current:` past Step 3, and a `## Tasks` table whose rows are ready or not. The ROSTER is
# the occupancy (wave-19 REQ-5, D6; ADR-034 decision 2): the wall counts this session's
# roster rows neither acked nor swept, and the plan's `active` column is no longer read —
# so every row below that means "N rows in flight" says so with `ledger_roster`.

# A project whose plan is a LIVE wave ledger: writers=8, at <current>, with the rows given.
# LEDGER_BUDGET is the header's budget line; `make_env_ledger_keyless` blanks it, which is
# the one plan shape REQ-3 refuses at write time and the wall names as a backstop.
LEDGER_BUDGET='parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=probe'
make_env_ledger_keyless() { LEDGER_BUDGET='' make_env_ledger "$@"; }
make_env_ledger() {  # <current> <row>... -> project dir on stdout
  local cur="$1"; shift
  local dir; dir=$(mktemp -d)
  mkdir -p "$dir/.bionic/docs/plans" "$dir/.bionic/tmp"
  : > "$dir/.bionic/tmp/engaged-$SID.state"
  {
    printf -- '---\n'
    printf 'governing-skill: superpowers:writing-plans\n'
    [ -z "$LEDGER_BUDGET" ] || printf '%s\n' "$LEDGER_BUDGET"
    printf -- '---\n\n# fixture plan\n\n'
    printf '## SDLC State\n\ncurrent: %s\n\n- Step %s: in progress\n\n' "$cur" "$cur"
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | status | worktree |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
    local row
    for row in "$@"; do printf '%s\n' "$row"; done
  } > "$dir/.bionic/docs/plans/$PLAN_REL"
  : > "$dir/transcript.jsonl"
  printf '%s' "$dir"
}

LEDGER_LANDED='| T1 | 4 | build | the landed row | implementor | — | 30m | REQ-x | a.sh | landed | — |'
LEDGER_READY_2='| T2 | 4 | build | the first ready row | implementor | — | 30m | REQ-x | b.sh | pending | — |'
LEDGER_READY_3='| T3 | 4 | build | the second ready row | implementor | — | 30m | REQ-x | c.sh | pending | — |'
LEDGER_ACTIVE='| T4 | 4 | build | the row in flight | implementor | — | 30m | REQ-x | d.sh | active | 18-T4 |'
LEDGER_BLOCKED='| T5 | 4 | build | a row behind an unlanded dep | implementor | T2 | 30m | REQ-x | e.sh | pending | — |'
LEDGER_READY_20='| T20 | 4 | build | the third ready row | implementor | — | 30m | REQ-x | h2.sh | pending | — |'

# THE ROSTER WRITER (wave-19 REQ-5). One roster row per name on THIS session's roster,
# through `roster_row_fixture` (tests/lib/roster-row.sh, the production writer), and then the
# state's own record: `acked` appends the sweeper ledger's `event=ack` line in the shape
# hooks/session-sweeper.sh journals it (the one terminal state of a name, ADR-034 decision 1),
# `swept` appends the stop library's MET marker through `swept_marker_write`, keyed by the
# row's agent id, `open` appends nothing. `deliverable=` is empty on
# purpose: a row that declares nothing is never a landing-gate candidate, so these fixtures
# drive the fill duty and nothing else.
ledger_roster() {  # <dir> <open|acked|swept> <name>...
  local dir="$1" st="$2"; shift 2
  local r="$dir/.bionic/tmp/roster-$SID.state" l="$dir/.bionic/tmp/sweeper-$SID.state" n
  for n in "$@"; do
    roster_row_fixture status=intended session="$SID" name="$n" agent_id="a${n}0000000000000001" \
      deliverable= >> "$r"
    case "$st" in
      acked) printf 'sweeper-ledger/v1|event=ack|at=2026-09-22T00:01:00Z|epoch=1758499260|pid=1|session=%s|name=%s|by=patrol|reason=landed\n' \
               "$SID" "$n" >> "$l" ;;
      swept) swept_marker_write "$r" 2026-09-22T00:01:00Z "$SID" "$n" "a${n}0000000000000001" MET ;;
    esac
  done
}

# THE RING IS SANDBOXED FOR THIS SECTION (wave-18 T2b, R1). Every fixture below carries a
# `parallel-budget:`, so `stop_patrol_duties`'s fill duty now reads the same rung the tick
# reads (`pressure_level`, payload/scripts/lib/resources.sh — this row's fix). Undriven, that
# would read and occasionally sample THIS MACHINE'S real ring
# (`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/pressure.ring`), which is neither hermetic nor
# safe to touch from a suite. CLEAR_RING pins a warm, clear sample so `pressure_level 8`
# answers `rung=8` — the same width the pre-fix ceiling always gave — so every row below that
# predates this fix (59-68) is unchanged by it. Row 69 swaps in a second, loaded ring to
# prove the RUNG, not the ceiling, is what caps the refusal.
CLEAR_RING="$(mktemp -d)/clear.ring"
printf '1700000000|80|0|1.0|8\n' > "$CLEAR_RING"
export BIONIC_PRESSURE_RING="$CLEAR_RING" BIONIC_NOW_EPOCH="1700000000"
# THE MACHINE IS PINNED CLEAR TOO (wave-20 REQ-5, Δ7). The wall reads the pressure STATE
# itself now (`resources_pressure`, the reading the tick's HOLD and EMERGENCY come from), so
# an unpinned suite on a loaded runner would read HOLD and exempt every gap below. The
# BIONIC_PROBE_* pins are the idiom the tick's own rows (64m) already use; 68d/68e override
# them per row to drive the two withholding states. They stay exported for the rest of the
# suite, whose later sections drive the same wall.
export BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_SWAP_PCT=0

# 59: THE INVARIANT. A live ledger, two ready rows, an ordinary turn that dispatched
# neither and never saw a tick -> REFUSE, naming both rows.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
ledger_roster "$d" acked T1
u_prompt "$d" "merge the two landed trees and tell me where we are"
fire "$d"; expect_block "59a: a turn ending on a fillable gap is refused, naming the first row" "T2"
fire "$d"; expect_block "59b: …and the second — named, not counted" "T3"
fire "$d"; expect_block "59c: …and says what answers it" "fill-declined"

# 60: THE DISCHARGE IS THE ONE THE TICK-PRINTED DUTY ALREADY HAD. One line in the record,
# and the invariant is answered for this turn.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
u_prompt "$d" "merge the two landed trees and tell me where we are"
a_text "$d" "fill-declined: the wave head has not merged, so neither row can base off it."
fire "$d"; expect_allow "60: a fill-declined line answers the gap as it answers a printed FILL"

# 60b: and a dispatch of every ready row answers it too. A DISPATCH IS TWO FACTS ON DISK
# (wave-20 Δ7, count not names): the roster row the dispatch wall writes at launch, and the
# plan row the orchestrator ledgers `active` the moment it dispatches (dispatch.md, "Ledger
# the dispatch, not the return"). The wall reads those two, never the Agent call's words.
LEDGER_SENT_2='| T2 | 4 | build | the first ready row | implementor | — | 30m | REQ-x | b.sh | active | 20-T2 |'
LEDGER_SENT_3='| T3 | 4 | build | the second ready row | implementor | — | 30m | REQ-x | c.sh | active | 20-T3 |'
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_SENT_2" "$LEDGER_SENT_3")
ledger_roster "$d" open W-T2 W-T3
u_prompt "$d" "dispatch the batch"
a_agent "$d" "W-T2" "row T2, implementor."
a_agent "$d" "W-T3" "row T3, implementor."
fire "$d"; expect_allow "60b: a turn that dispatched every ready row is not refused"

# 60c: …and a turn that dispatched ONE of the two is refused, naming only the other.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_SENT_2" "$LEDGER_READY_3")
ledger_roster "$d" open W-T2
u_prompt "$d" "dispatch the first one"
a_agent "$d" "W-T2" "row T2, implementor."
fire "$d"; expect_block "60c: a half-filled gap names the row left out, and not the one sent" "T3" "T2"

# 60d: A ROW THIS TURN LAUNCHED IS NEVER NAMED AS MISSED (T11b; review R4, T12 F7). Two agents
# launched and rostered while both plan rows still read `pending`. The launch already holds a
# roster slot, so counting the row as ready as well charged it twice: the refusal named the
# rows the turn had just sent. The ready set stays the plan's; what the turn missed is that set
# less this turn's launches, matched by the dispatch name `fill_name` hands out (the id, or
# the id with a `-r<n>` suffix, behind any `<prefix>-`). A-T11b.2.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
ledger_roster "$d" open W-T2 W-T3
u_prompt "$d" "dispatch the batch"
a_agent "$d" "W-T2" "row T2, implementor."
a_agent "$d" "W-T3" "row T3, implementor."
fire "$d"; expect_allow "60d: (T11b: was \"launched but still pending in the plan — the gap stands, T2 named\") a turn that launched every ready row is not refused, ledgered active or not"
# 60e: …and one launched of two, both pending: the one left out is named, the launched one never.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
ledger_roster "$d" open W-T2
u_prompt "$d" "dispatch the first"
a_agent "$d" "W-T2" "row T2, implementor."
fire "$d"; expect_block "60e: (T11b: was \"…and T3\") launched-but-pending T2 is not named; unlaunched T3 is" "T3" "T2"

# 61: THE LEDGER IS NOT LIVE BELOW STEP 4. Steps 0-3 are research, spec, plan and review;
# the same table at `current: 3` is a schedule nobody has ratified, and dispatching into it
# is what the tick's own approval gate exists to prevent.
d=$(make_env_ledger 3 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
u_prompt "$d" "draft the plan's task table"
fire "$d"; expect_allow "61: a plan at current: 3 is not a fillable gap — Step 3 has not passed"

# 62: NO GAP, TWO WAYS. Nothing is ready (every row landed, or every pending row sits
# behind an unlanded dependency) -> silent.
d=$(make_env_ledger 4 "$LEDGER_LANDED")
u_prompt "$d" "what is left?"
fire "$d"; expect_allow "62a: a ledger with no pending row is silent"

d=$(make_env_ledger 4 "$LEDGER_SENT_2" "$LEDGER_BLOCKED")
ledger_roster "$d" open W-T2
u_prompt "$d" "start the row behind T2"
a_agent "$d" "W-T2" "row T2, implementor."
fire "$d"; expect_allow "62b: a pending row behind an unlanded dep is not ready, so the turn ends"

# 63: THE BUDGET IS A MEASUREMENT, AND ITS ABSENCE IS NAMED, NEVER SILENT (wave-19 REQ-3
# AC-3.2, D5; ADR-035 decision 2). A live ledger with ready rows and no `parallel-budget:`
# line is a plan the governing-skill hook would have refused to write; the wall is the
# backstop, and it names the key rather than ending the turn in silence.
d=$(make_env_ledger_keyless 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
u_prompt "$d" "carry on"
fire "$d"; expect_block "63a: a live ledger with no budget key is refused, naming the key" "parallel-budget:"
fire "$d"; expect_block "63b: …and the field the width is read from" "writers="
# …and the same keyless plan below Step 4 is not a live ledger: nothing is owed yet.
d=$(make_env_ledger_keyless 3 "$LEDGER_LANDED" "$LEDGER_READY_2")
u_prompt "$d" "carry on"
fire "$d"; expect_allow "63c: a keyless plan at current: 3 is not refused — the backstop is past Step 3 only"
# …and a plan whose `current:` names no unit the table can answer (no table at all) is the
# tick's unreadable-`current:` withhold, which comes BEFORE its budget note — so it stays
# silent here too.
d=$(make_env); u_prompt "$d" "carry on"
fire "$d"; expect_allow "63d: a keyless plan with no readable unit is the unreadable-current withhold, not a budget refusal"
# …and a keyless live ledger with NOTHING ready hides no gap: a keyed plan would end the same
# turn in the same silence, so the absence is not what silenced it. The backstop names the key
# exactly where the missing width would have hidden a fillable row (A-T2.2).
d=$(make_env_ledger_keyless 4 "$LEDGER_LANDED")
u_prompt "$d" "carry on"
fire "$d"; expect_allow "63f: a keyless live ledger with no ready row is not refused — no gap was hidden"
# …and the same turn with `stop_hook_active` passes: the backstop blocks once per turn.
d=$(make_env_ledger_keyless 4 "$LEDGER_LANDED" "$LEDGER_READY_2")
u_prompt "$d" "carry on"
fire "$d" Stop true; expect_allow "63e: the budget backstop blocks once — stop_hook_active passes"

# 64: THE ARITHMETIC IS THE RUNG MINUS THE OPEN ROWS, and the open rows are the ROSTER's
# (REQ-5 AC-5.1). Eight open roster rows against writers=8 is a full budget, ready rows or not.
d=$(make_env_ledger 4 "$LEDGER_READY_2" \
  '| T11 | 4 | build | in flight | implementor | — | 30m | REQ-x | f.sh | active | 18-T11 |' \
  '| T12 | 4 | build | in flight | implementor | — | 30m | REQ-x | g.sh | active | 18-T12 |' \
  '| T13 | 4 | build | in flight | implementor | — | 30m | REQ-x | h.sh | active | 18-T13 |' \
  '| T14 | 4 | build | in flight | implementor | — | 30m | REQ-x | i.sh | active | 18-T14 |' \
  '| T15 | 4 | build | in flight | implementor | — | 30m | REQ-x | j.sh | active | 18-T15 |' \
  '| T16 | 4 | build | in flight | implementor | — | 30m | REQ-x | k.sh | active | 18-T16 |' \
  '| T17 | 4 | build | in flight | implementor | — | 30m | REQ-x | l.sh | active | 18-T17 |' \
  '| T18 | 4 | build | in flight | implementor | — | 30m | REQ-x | m.sh | active | 18-T18 |')
ledger_roster "$d" open T11 T12 T13 T14 T15 T16 T17 T18
u_prompt "$d" "anything else to start?"
fire "$d"; expect_allow "64a: eight open roster rows against writers=8 is a full budget, not a gap"

# 64a2: THE PLAN COLUMN IS NOT READ. The same eight `active` plan rows with NO roster: the
# occupancy is zero, the gap is eight, and T2 is named. Pre-fix the wall read the column and
# passed this turn (AC-5.1 fails-when: "the wall still reads the plan's active column").
d=$(make_env_ledger 4 "$LEDGER_READY_2" \
  '| T11 | 4 | build | in flight | implementor | — | 30m | REQ-x | f.sh | active | 18-T11 |' \
  '| T12 | 4 | build | in flight | implementor | — | 30m | REQ-x | g.sh | active | 18-T12 |' \
  '| T13 | 4 | build | in flight | implementor | — | 30m | REQ-x | h.sh | active | 18-T13 |' \
  '| T14 | 4 | build | in flight | implementor | — | 30m | REQ-x | i.sh | active | 18-T14 |' \
  '| T15 | 4 | build | in flight | implementor | — | 30m | REQ-x | j.sh | active | 18-T15 |' \
  '| T16 | 4 | build | in flight | implementor | — | 30m | REQ-x | k.sh | active | 18-T16 |' \
  '| T17 | 4 | build | in flight | implementor | — | 30m | REQ-x | l.sh | active | 18-T17 |' \
  '| T18 | 4 | build | in flight | implementor | — | 30m | REQ-x | m.sh | active | 18-T18 |')
u_prompt "$d" "anything else to start?"
fire "$d"; expect_block "64a2: eight active PLAN rows with an empty roster are not occupancy — the gap is named" "T2"

# 64a3: …and an ACKED roster row is closed — the ack is the one terminal state of a name
# (ADR-034 decision 1). Eight acked rows occupy nothing, so the ready row is named.
d=$(make_env_ledger 4 "$LEDGER_READY_2")
ledger_roster "$d" acked T11 T12 T13 T14 T15 T16 T17 T18
u_prompt "$d" "anything else to start?"
fire "$d"; expect_block "64a3: acked roster rows occupy nothing" "T2"

# 64a3b: A SWEPT ROW IS NOT A CLOSE. The `landing-swept/v1` marker records that a landing
# was seen; until the ack, the row still occupies the wall's count. That keeps the wall's
# number at or above the tick's in every case — the tick counts a swept row open whenever
# its verdict is not MET (a deliverable since removed; session-poker §12a-T22-c), and the
# wall cannot recompute a verdict — so the wall refuses less, never more. Eight swept,
# unacked rows against writers=8: full, and the turn passes.
d=$(make_env_ledger 4 "$LEDGER_READY_2")
ledger_roster "$d" swept T11 T12 T13 T14 T15 T16 T17 T18
u_prompt "$d" "anything else to start?"
fire "$d"; expect_allow "64a3b: swept-but-unacked roster rows still occupy — the wall refuses less, never more"

# 64a3c: THE ROSTER IS THIS SESSION'S. A row another session wrote into this file (a copied
# or hand-edited roster) is not occupancy here: eight such rows leave the gap open.
d=$(make_env_ledger 4 "$LEDGER_READY_2")
for _n in X1 X2 X3 X4 X5 X6 X7 X8; do
  roster_row_fixture status=intended session=99999999-0000-0000-0000-000000000000 name="$_n" \
    agent_id= deliverable= >> "$d/.bionic/tmp/roster-$SID.state"
done
u_prompt "$d" "anything else to start?"
fire "$d"; expect_block "64a3c: another session's rows are not this session's occupancy" "T2"

# 64a3d: THE LATEST ROW OF A NAME WINS, as every roster reader folds it: one name written
# three times (intended, identified, confirmed) is one row in flight, not three. Seven such
# names fill seven of eight, so exactly one row is named.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
ledger_roster "$d" open W1 W2 W3 W4 W5 W6 W7
ledger_roster "$d" open W1 W2 W3 W4 W5 W6 W7
ledger_roster "$d" open W1 W2 W3 W4 W5 W6 W7
u_prompt "$d" "anything else to start?"
fire "$d"; expect_block "64a3d: a name written three times occupies once — one row named" "T2" "T3"

# 64a4: AC-5.1's own shape — a roster with two open rows and a plan with no `active` row:
# gap = rung − 2. On the loaded ring (rung 2) that is zero, so nothing is owed…
LOADED_RING_64="$(mktemp -d)/loaded.ring"
printf '1700000000|10|0|1.0|8\n' > "$LOADED_RING_64"
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
ledger_roster "$d" open W1 W2
u_prompt "$d" "anything else ready?"
export BIONIC_PRESSURE_RING="$LOADED_RING_64"
fire "$d"; expect_allow "64a4: two open roster rows against rung 2 leave no gap"
# …and with one of the two acked the gap is one: exactly T2 is named, never T3.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
ledger_roster "$d" open W1
ledger_roster "$d" acked W2
u_prompt "$d" "anything else ready?"
fire "$d"; expect_block "64a5: one open roster row against rung 2 names one row" "T2" "T3"
export BIONIC_PRESSURE_RING="$CLEAR_RING"

# …and one row in flight leaves room, so the same table with seven refuses.
d=$(make_env_ledger 4 "$LEDGER_READY_2" "$LEDGER_ACTIVE")
ledger_roster "$d" open T4
u_prompt "$d" "anything else to start?"
fire "$d"; expect_block "64b: one row in flight against writers=8 leaves room, and the gap is named" "T2"

# 64m: THE DIFFERENTIAL ON THE END-OF-BATCH SHAPE (wave-19 audit V-2; T2d). 64a–64a5 drive
# the wall alone, and session-poker 12l2 compares the two on an UNMET row, where they already
# agreed. The shape nothing bound: a MET row the ack has not closed, its agent still idle on a
# FRESH panel (so the tick's STANDDOWN names it and does not ack it), writers=2, two ready
# rows. The REAL tick runs on this same fixture repo — the same roster, the same plan, the
# same ledger — and its printed FILL is compared with the ids the wall's refusal names on an
# ordinary turn. Pre-fix the tick dropped the MET row from its occupancy and filled T2 T3;
# the wall counts every unacked row and names T2 alone.
POKER_64M="${BIONIC_HOOKS_DIR}/session-poker.sh"
d=$(LEDGER_BUDGET='parallel-budget: writers=2 suites=2 worktrees=8 test_jobs=8 source=probe' \
      make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
echo "done" > "$d/landed-64m.md"
roster_row_fixture status=intended session="$SID" name=W-MET agent_id= \
  deliverable="$d/landed-64m.md" >> "$d/.bionic/tmp/roster-$SID.state"
CFG_64M="$(mktemp -d)"; mkdir -p "$CFG_64M/projects/-fixture-project"
{
  jq -nc '{type:"user",timestamp:"2026-09-05T00:50:00.000Z",message:{role:"user",content:"go"}}'
  jq -nc '{type:"assistant",timestamp:"2026-09-05T00:51:00.000Z",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_0164MLISTAGENTS",name:"ListAgents",input:{}}]}}'
  jq -nc --arg b "$(live_answer_body "W-MET:idle")" \
    '{type:"user",timestamp:"2026-09-05T00:52:23.349Z",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_0164MLISTAGENTS",content:$b}]}}'
} > "$CFG_64M/projects/-fixture-project/$SID.jsonl"
( cd "$d" && git init -q . 2>/dev/null )
# THE TICK'S MACHINE IS PINNED, AND ITS RING IS ITS OWN COPY. Unpinned, the tick samples this
# machine (a loaded runner reads HOLD and fills nothing) and appends that sample to the ring it
# is handed — which, shared, is the CLEAR_RING every later row's wall reads. The copy starts
# from the same clear sample, so both sides answer the same rung.
RING_64M="$CFG_64M/clear.ring"; cp "$CLEAR_RING" "$RING_64M"
TICK_64M="$(cd "$d" && env CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_CONFIG_DIR="$CFG_64M" \
  BIONIC_PRESSURE_RING="$RING_64M" BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_FREE_PCT=80 \
  BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=1.0 bash "$POKER_64M" tick 2>&1)"
FILL_64M="$(printf '%s\n' "$TICK_64M" | sed -n 's/^poker: FILL \([A-Za-z0-9].*\)$/\1/p' | head -1 \
  | tr ' ' '\n' | /usr/bin/grep -v '^$' | sort | tr '\n' ' ')"
case "$TICK_64M" in
  *"poker: STANDDOWN W-MET"*) ok "64m precondition: the real tick stood the MET row down (listed, not acked)" ;;
  *) no "64m precondition: the real tick stood the MET row down (listed, not acked)" "$TICK_64M" ;;
esac
u_prompt "$d" "anything else to start?"
fire "$d"
WALL_64M=""
for _id in T1 T2 T3; do
  case " $(reason_of | tr -c 'A-Za-z0-9_.-' ' ') " in *" $_id "*) WALL_64M="${WALL_64M}${_id} " ;; esac
done
expect_eq "64m: the tick's FILL on a MET-unacked roster is the wall's gap of one" "T2 " "$FILL_64M"
expect_eq "64m2: …and the wall names exactly the ids the tick printed (AC-5.2 differential)" \
  "$FILL_64M" "$WALL_64M"
rm -rf "$CFG_64M"

# 64n: THE SAME DIFFERENTIAL, ON AN UNMET ROW (wave-19 delta review R2-5/C2-5, on 64m). 64m
# pins the MET-unacked shape the liveness-trim removal covers; nothing bound the SAME shape
# on a row that never met its contract — an UNMET row, unacked, whose agent a fresh panel
# does not list. That is exactly what the trim used to drop for the fill (A-T2.13), so it is
# the differential's other half. writers=2, one such row, two ready rows: the real tick's
# FILL is compared with the ids the wall's refusal names on an ordinary turn.
d=$(LEDGER_BUDGET='parallel-budget: writers=2 suites=2 worktrees=8 test_jobs=8 source=probe' \
      make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
roster_row_fixture status=intended session="$SID" name=W-UNMET agent_id= \
  deliverable="$d/never-written-64n.md" >> "$d/.bionic/tmp/roster-$SID.state"
CFG_64N="$(mktemp -d)"; mkdir -p "$CFG_64N/projects/-fixture-project"
{
  jq -nc '{type:"user",timestamp:"2026-09-05T00:50:00.000Z",message:{role:"user",content:"go"}}'
  jq -nc '{type:"assistant",timestamp:"2026-09-05T00:51:00.000Z",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_0164NLISTAGENTS",name:"ListAgents",input:{}}]}}'
  jq -nc --arg b "$(live_answer_body "somebody-else:idle")" \
    '{type:"user",timestamp:"2026-09-05T00:52:23.349Z",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_0164NLISTAGENTS",content:$b}]}}'
} > "$CFG_64N/projects/-fixture-project/$SID.jsonl"
( cd "$d" && git init -q . 2>/dev/null )
RING_64N="$CFG_64N/clear.ring"; cp "$CLEAR_RING" "$RING_64N"
TICK_64N="$(cd "$d" && env CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_CONFIG_DIR="$CFG_64N" \
  BIONIC_PRESSURE_RING="$RING_64N" BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_FREE_PCT=80 \
  BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=1.0 bash "$POKER_64M" tick 2>&1)"
FILL_64N="$(printf '%s\n' "$TICK_64N" | sed -n 's/^poker: FILL \([A-Za-z0-9].*\)$/\1/p' | head -1 \
  | tr ' ' '\n' | /usr/bin/grep -v '^$' | sort | tr '\n' ' ')"
u_prompt "$d" "anything else to start?"
fire "$d"
WALL_64N=""
for _id in T1 T2 T3; do
  case " $(reason_of | tr -c 'A-Za-z0-9_.-' ' ') " in *" $_id "*) WALL_64N="${WALL_64N}${_id} " ;; esac
done
expect_eq "64n R2-5: the tick's FILL on an UNMET-gone roster is the wall's gap of one" "T2 " "$FILL_64N"
expect_eq "64n2 …and the wall names exactly the ids the tick printed (AC-5.2 differential)" \
  "$FILL_64N" "$WALL_64N"
expect_contains "64n3 R2-6/C2-5: the tick names the gone-UNMET row and the closing verb" \
  "poker: GONE W-UNMET — UNMET and absent from a fresh panel; close it with: bash ${BIONIC_HOOKS_DIR}/stop-orders.sh stopped W-UNMET" \
  "$TICK_64N"
rm -rf "$CFG_64N"

# 65: BLOCKS ONCE, through the same stop_hook_active valve the other three duties use.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2")
u_prompt "$d" "carry on"
fire "$d" Stop true; expect_allow "65: stop_hook_active true passes the same fillable gap"

# 66: A SUBAGENT'S STOP IS NOT THE ORCHESTRATOR'S. A writer ending its own turn owes
# nothing about the run's schedule — the Stop-only rule this whole function is built on.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2")
u_prompt "$d" "carry on"
fire "$d" SubagentStop; expect_allow "66: a SubagentStop is never asked about the run's gap"

# 67: THE TICK ARM IS GONE (wave-20 Δ7). A tick turn whose tick printed `FILL T2` is judged
# on the ready set the wall computes, like every other turn: both ready rows are named, in the
# one gap wording, and never in the retired "the tick printed FILL" sentence.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
u_tick "$d"; both_duties "$d"; u_tick_out "$d" "poker: FILL T2"
fire "$d"; expect_block "67a: a tick turn that printed FILL T2 is judged on the computed gap" "T3"
fire "$d"; expect_block "67b: …in the gap arm's wording, never the retired tick arm's" "T2" "the tick printed FILL"

# 68: BUDGET-FULL ON THE ROSTER (re-authored, wave-19 REQ-4 AC-4.2). A tick that printed
# "the budget is full" is no longer exempt by its words; it passes because the wall counts the
# same roster and finds the same full budget. Eight open rows, writers=8, rung 8: gap zero.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
ledger_roster "$d" open W1 W2 W3 W4 W5 W6 W7 W8
u_tick "$d"; both_duties "$d"; u_tick_out "$d" "poker: no FILL — rung=8 of writers=8 and 8 unacked roster row(s): the budget is full."
fire "$d"; expect_allow "68: a budget-full tick turn on a full roster passes on the wall's own arithmetic"

# 68b: …and the same printed words over a roster with room are not an exemption: no withheld
# line, a gap, ready rows → refused, naming them (REQ-4 AC-4.2 fails-when: "a tick turn with
# no FILL and no withheld line ends silently with a non-empty ready set").
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
u_tick "$d"; both_duties "$d"; u_tick_out "$d" "poker: no FILL — rung=8 of writers=8 and 8 unacked roster row(s): the budget is full."
fire "$d"; expect_block "68b: a tick turn with no FILL and no withheld line is judged on the gap" "T2"
fire "$d"; expect_block "68c: …naming every ready row, in the gap arm's wording" "T3" "the tick printed FILL"

# 68d: THE HOLD, MEASURED BY THE WALL (wave-20 Δ7). The machine reads HOLD — free memory under
# the warning line — and the wall takes that reading itself, the one the tick's HOLD comes
# from: the turn passes although the arithmetic finds a gap, and no printed line is needed.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
u_prompt "$d" "carry on"
BIONIC_PROBE_FREE_MB=512 fire "$d"; expect_allow "68d: a machine at HOLD withholds the fill — the wall measured it"

# 68e: THE EMERGENCY, the same way.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
u_prompt "$d" "carry on"
BIONIC_PROBE_FREE_MB=100 fire "$d"; expect_allow "68e: a machine at EMERGENCY withholds the fill"

# 68f: THE PRINTED LINE IS NOT THE MEASUREMENT. The tick's own `fill withheld — HOLD` line in
# its tool result, on a machine that reads clear at the wall, exempts nothing: the line is
# advice, and the turn is judged on the wall's reading.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
u_tick "$d"; both_duties "$d"
u_tick_out "$d" "poker: HOLD free_mb=512 load_1m=1.0 — no fills
poker: fill withheld — HOLD free_mb=512 load_1m=1.0"
fire "$d"; expect_block "68f: a printed withheld line on a clear machine exempts nothing" "T2"

# 68g: THE LINE IS THE TICK'S, READ OFF A TOOL RESULT. The model's own text quoting the
# withheld line is not the tick having printed it.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
u_tick "$d"; both_duties "$d"
a_text "$d" "poker: fill withheld — HOLD free_mb=512 load_1m=1.0"
fire "$d"; expect_block "68g: the withheld words in the model's own text exempt nothing" "T2"

# 68h: …and a decline answers a tick turn's gap as it answers any other (REQ-4 AC-4.3's
# fill-declined row).
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
u_tick "$d"; both_duties "$d"; u_tick_out "$d" "poker: QUIET"
a_text "$d" "fill-declined: the wave head is mid-merge; both rows base off it."
fire "$d"; expect_allow "68h: fill-declined answers a tick turn's gap"

# 68i: THE WITHHELD LINE IS ANCHORED TO THE TICK'S OWN OUTPUT (Step-5/6 review R5, wave-19
# T2b). A tool_result that merely ECHOES the literal words — a `grep -rn` hit, or a `cat`/`sed`
# of this very test file's source — is not the tick having printed them. The record below
# carries the phrase with a GAP before it (a grep-style `file:line:` prefix), exactly the shape
# `grep -rn 'poker: fill withheld — \(HOLD\|EMERGENCY\)' tests` produces, so it must not exempt
# the turn: the gap arm judges the ready set and names it.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
u_tick "$d"; both_duties "$d"
u_tick_out "$d" "tests/patrol-duties-gate.test.sh:1034:poker: fill withheld — HOLD free_mb=512 load_1m=1.0"
fire "$d"; expect_block "68i: a withheld line read off a grep/cat echo (a gap before it) exempts nothing" "T2"

# 58c: BOTH UNANSWERED DUTIES ARE TOLD AT ONCE. A computed gap and a printed stand-down in one
# tick turn name the row and the agent in one refusal: the next stop passes by design.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2")
u_tick "$d"; both_duties "$d"; sd_stood "$d" W-BETA; u_tick_out "$d" "$(sd_line W-BETA)"
fire "$d"; expect_block "58c: a gap and a stand-down together name the row" "T2"
fire "$d"; expect_block "58d: …and the agent, in the same refusal" "W-BETA"

# 69: THE RUNG, NOT THE CEILING (Step-6 review R1, wave-18 T2b). Three rows are ready
# (T2, T3, T20) against a declared ceiling of 8 — the pre-fix wall would have named all
# three. LOADED_RING pins a critical-band sample (free_pct=10, inside [0, 12)) against
# that ceiling: rung = (8 + 3) / 4 = 2. The wall must name exactly the rung-minus-open
# count — T2 and T3 — and never T20, which the tick's own rung declined to order.
LOADED_RING="$(mktemp -d)/loaded.ring"
printf '1700000000|10|0|1.0|8\n' > "$LOADED_RING"
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3" "$LEDGER_READY_20")
u_prompt "$d" "anything else ready?"
export BIONIC_PRESSURE_RING="$LOADED_RING" BIONIC_NOW_EPOCH="1700000000"
fire "$d"; expect_block "69a: a rung pinned below the ceiling caps the refusal at rung - open" "T2"
fire "$d"; expect_block "69b: …and the second row, at the rung's width" "T3"
fire "$d"; expect_block "69c: …and never the ceiling's wider count — T20 stays unnamed" "fill-declined" "T20"
export BIONIC_PRESSURE_RING="$CLEAR_RING" BIONIC_NOW_EPOCH="1700000000"

# 69d: THE PAIRED CASE, rung = ceiling. The same three-ready-row table, back on the clear
# ring: rung=8, gap=8-0=8, and all three ready rows fit inside it — unchanged from 59-68.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3" "$LEDGER_READY_20")
u_prompt "$d" "anything else ready?"
fire "$d"; expect_block "69d: a rung equal to the ceiling names every ready row, T20 included" "T20"

# 69e: READINESS IS THE PREREQUISITE GRAPH (wave-20 REQ-5, AC-5.1; Δ1, Δ6; ADR-036). At
# current: 5 a pending Step-6 review row whose deps have landed is READY — the step is a label
# — so a turn that ends with it undispatched and a slot free is refused, naming it. A Step-8
# integrate row with the same landed deps is a gate act and waits for its step: it is never
# named at Step 5, and a ledger holding only that row is not a fillable gap.
LEDGER_REVIEW_6='| T6 | 6 | review | the review whose deps landed | critic | T1 | 30m | REQ-x | — | pending | — |'
LEDGER_INTEGRATE_8='| T8 | 8 | integrate | the merge, a gate act | implementor | T1 | 30m | REQ-x | — | pending | — |'
d=$(make_env_ledger 5 "$LEDGER_LANDED" "$LEDGER_REVIEW_6" "$LEDGER_INTEGRATE_8")
u_prompt "$d" "how is Verify going?"
fire "$d"; expect_block "69e: AC-5.1 at current: 5 a ready Step-6 row left undispatched is refused, naming it" "T6"
fire "$d"; expect_block "69f: Δ6 …and the Step-8 integrate row is never named at Step 5" "fill-declined" "T8"
d=$(make_env_ledger 5 "$LEDGER_LANDED" "$LEDGER_INTEGRATE_8")
u_prompt "$d" "how is Verify going?"
fire "$d"; expect_allow "69g: Δ6 a ledger whose only pending row is a gate act ahead of its step is not a gap"

# ============================================================
# 70: ONE PARSE PER STOP (wave-19 REQ-6, D7; AC-6.2). The fill duty asks three questions of
# one plan — is the ledger live, which unit is it on, which rows are ready — and each used to
# re-read the file: `current:` three times on every live Stop, the `## Tasks` table three
# times at task scale. The answers are facts of the plan, which no Stop writes, so each is
# read once. The instrument is the R2 PATH shim (record/wave-19-fixit-186/
# step2-research-R2-fill-invariant.md Q4): an `awk` in front of PATH that logs its program
# and execs the real one by ABSOLUTE path (a bare `exec awk` re-enters the shim). A parse is
# counted by its program's own text, and 70g pins that each text is spelled once in its
# library, so the count cannot go quietly to zero when a program is rewritten.
PDG_SHIM="$(mktemp -d)"
printf '%s\n' '#!/bin/bash' \
  'a="$*"; a="${a//$'"'"'\n'"'"'/ }"; printf "%s\n" "${a:0:400}" >> "$PDG_AWKLOG"' \
  'exec /usr/bin/awk "$@"' > "$PDG_SHIM/awk"
chmod +x "$PDG_SHIM/awk"
PDG_CUR_SIG='/^## SDLC State/ { flag = 1; next }'   # fill.sh's current: reader
PDG_TBL_SIG='FOLDS THE ESCAPE'                      # units.sh's _units_read
fire_counted() {  # <project> -> fire, with every awk this Stop runs logged to $PDG_AWKLOG
  local _path="$PATH"
  export PDG_AWKLOG="$1/awk.log"; : > "$PDG_AWKLOG"
  PATH="$PDG_SHIM:$PATH"; fire "$1"; PATH="$_path"
}
pdg_count() { LC_ALL=C grep -cF -- "$1" "$PDG_AWKLOG"; }

d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
ledger_roster "$d" acked T1
u_prompt "$d" "merge the landed tree and tell me where we are"
fire_counted "$d"
expect_block "70a: the counted Stop still computes the ready set (wave scale), naming T2" "T2"
expect_eq "70b: …after ONE read of current: (the gate, the step token and the set share it)" \
  "1" "$(pdg_count "$PDG_CUR_SIG")"
expect_eq "70c: …and ONE parse of the table" "1" "$(pdg_count "$PDG_TBL_SIG")"

# Task scale: `current: T<n>` against a table of units, where the step token asks the header
# twice (`units_has_column` step, then id) before the ready set reads the rows.
d=$(make_env_ledger T2)
{
  printf -- '---\ngoverning-skill: canonical-sdlc\n%s\n---\n\n# fixture task plan\n\n' "$LEDGER_BUDGET"
  printf '## SDLC State\n\ncurrent: T2\n\n## Tasks\n\n'
  printf '| id | intent | rigor | description | status | worktree |\n|---|---|---|---|---|---|\n'
  printf '| T1 | bugfix | standard | the done unit | done | — |\n'
  printf '| T2 | bugfix | standard | the unit the run is on | pending | — |\n'
  printf '| T3 | bugfix | standard | the next unit | pending | — |\n'
} > "$d/.bionic/docs/plans/$PLAN_REL"
u_prompt "$d" "carry on"
fire_counted "$d"
expect_block "70d: the counted Stop still computes the ready set (task scale), naming T2" "T2"
expect_eq "70e: …after ONE read of current:" "1" "$(pdg_count "$PDG_CUR_SIG")"
expect_eq "70f: …and ONE parse of the table, the header questions included" \
  "1" "$(pdg_count "$PDG_TBL_SIG")"

# 70g: THE COUNTER'S OWN CONTROL. Each signature is spelled exactly once in its library, so a
# zero above is a reader that stopped running, never a program that changed its text.
expect_eq "70g: fill.sh spells the current: reader's program once" \
  "1" "$(LC_ALL=C grep -cF -- "$PDG_CUR_SIG" "${HOOK_SRC%/*}/fill.sh")"
expect_eq "70g: …and units.sh the table parse's" \
  "1" "$(LC_ALL=C grep -cF -- "$PDG_TBL_SIG" "${HOOK_SRC%/*}/units.sh")"

# ============================================================
section "Section 5d: nothing quoted plants a verdict (wave-20 REQ-5, AC-5.4; Δ7)"
#
# THE FOUR PLANTS research D1 §4 reproduced at b60efe2, each of which moved this wall's
# verdict: the model's own prose carrying `poker: FILL T9`, a `cat` of a file whose line 1 is
# a withheld line, a Bash command that greps `fill-declined:`, and an Agent call whose PROMPT
# names the ready ids. The wall now computes the ready set and the pressure state, judges by
# count, and reads only a decline anchored at a line start in the model's own text, so each
# plant leaves the baseline verdict exactly where it was: refused, naming T2 and T3.
#
# The fixture is a TICK turn with both standing duties done, so the only thing that can move
# the verdict is the fill duty — and the tick arm, where the old wall read a printed FILL, is
# reachable by the plant.
plant_env() {  # -> a live ledger, two rows ready, a tick turn with both duties done
  local d; d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
  u_tick "$d"; both_duties "$d"
  printf '%s' "$d"
}
expect_plant_inert() {  # <label> — the baseline verdict: refused, both ready rows named
  local r; r="$(reason_of)"
  if [ "$(decision_of)" != "block" ]; then no "$1" "decision=<$(decision_of)> stdout=<$HOOK_OUT>"; return; fi
  case "$r" in *T2*) ;; *) no "$1" "T2 not named: $r"; return ;; esac
  case "$r" in *T3*) ;; *) no "$1" "T3 not named: $r"; return ;; esac
  case "$r" in *T9*) no "$1" "the planted T9 was named: $r"; return ;; esac
  ok "$1"
}

d=$(plant_env)
fire "$d"; expect_plant_inert "P0: the baseline — two rows ready, nothing sent: refused, both named"

# P1: THE MODEL'S OWN PROSE, quoting the tick's line at a line start of its text.
d=$(plant_env)
a_text "$d" "The last tick said:
poker: FILL T9
so I will look at it after this."
fire "$d"; expect_plant_inert "P1: AC-5.4 assistant prose carrying 'poker: FILL T9' changes nothing"

# P2: A `cat` OF A FILE whose first line is the withheld line, at column 0 of the result.
d=$(plant_env)
a_tool "$d" Bash "cat notes.md"
u_tick_out "$d" "poker: fill withheld — HOLD free_mb=512 load_1m=1.0
(notes from the last wave)"
fire "$d"; expect_plant_inert "P2: AC-5.4 a cat of a withheld line at column 0 changes nothing"

# P3: A GREP OF THE DECLINE LITERAL — the words in a Bash command, not a decline.
d=$(plant_env)
a_tool "$d" Bash "grep -n fill-declined: .bionic/docs/record/notes.md"
fire "$d"; expect_plant_inert "P3: AC-5.4 a grep of fill-declined: changes nothing"

# P4: AN AGENT WHOSE PROMPT NAMES THE IDS. The helper is launched and rostered — it holds a
# slot — but it is not T2 or T3, and the plan still has both rows pending with slots free.
d=$(plant_env)
ledger_roster "$d" open helper
a_agent "$d" "helper" "Read the diffs for T2 and T3 and summarise them."
fire "$d"; expect_plant_inert "P4: AC-5.4 an Agent prompt naming the ids changes nothing"

# P5: THE DECLINE THAT DOES COUNT — the paired positive, so P1-P4 are not a wall that refuses
# everything. At a line start of the model's own text, mid-message.
d=$(plant_env)
a_text "$d" "Both rows are ready.
fill-declined: the wave head is mid-merge; both rows base off it."
fire "$d"; expect_allow "P5: a decline at a line start of the model's own text answers the gap"

# P6: …and the same words NOT at a line start are prose about a decline, not one.
d=$(plant_env)
a_text "$d" "If I had to, I would write fill-declined: with a reason, but I will not."
fire "$d"; expect_plant_inert "P6: fill-declined: mid-line is not a decline"

# P7: …nor is a decline written only in the model's thinking.
d=$(plant_env)
jq -nc '{type:"assistant",isSidechain:false,
         message:{role:"assistant",content:[{type:"thinking",thinking:"fill-declined: I would rather not"}]}}' \
  >> "$d/transcript.jsonl"
fire "$d"; expect_plant_inert "P7: a decline in thinking only is not the model's decline record"

# ============================================================
section "Section 5e: every Stop writes the fill ledger (wave-20 REQ-5, AC-5.5; Δ2)"
#
# THE RECORD. `hooks/stop.sh` appends one `fill-ledger/v1` line per Stop of an engaged run to
# `<docs-root>/record/<plan slug>/fill-ledger.log` — BEFORE the re-entry guard, so the Stop
# that ends a refused turn is recorded too, with the launches the model made after the
# refusal. The report folds by the turn key (the prompt's uuid), so a refused turn's two
# lines count once, as the last.
#
# THREE STOPS. Turn 1 dispatches T2 (rostered, ledgered active) and ends clean. Turn 2 finds
# T3 ready and sends nothing, and is refused; the model then dispatches T3 and one more agent
# whose dispatch the preflight refused (an `is_error` result, no roster row), and stops again
# with `stop_hook_active`. Each line's `launched=` names that turn's Agent calls that were not
# refused.
LEDGER_T3_BEHIND='| T3 | 4 | build | the row behind T2 | implementor | T2 | 30m | REQ-x | c.sh | pending | — |'
LEDGER_T2_LANDED='| T2 | 4 | build | the first ready row | implementor | — | 30m | REQ-x | b.sh | landed | 20-T2 |'
LEDGER_T3_READY='| T3 | 4 | build | the row behind T2 | implementor | T2 | 30m | REQ-x | c.sh | pending | — |'
LEDGER_T3_SENT='| T3 | 4 | build | the row behind T2 | implementor | T2 | 30m | REQ-x | c.sh | active | 20-T3 |'
led_plan() {  # <dir> <row>... — rewrite the plan's table, keeping the fixture's header
  local dir="$1"; shift
  local tmp; tmp="$(make_env_ledger 4 "$@")"
  cp "$tmp/.bionic/docs/plans/$PLAN_REL" "$dir/.bionic/docs/plans/$PLAN_REL"
  rm -rf "$tmp"
}
led_user() {  # <dir> <uuid> <iso> <text>
  jq -nc --arg u "$2" --arg ts "$3" --arg t "$4" \
    '{type:"user",uuid:$u,timestamp:$ts,isSidechain:false,message:{role:"user",content:$t}}' >> "$1/transcript.jsonl"
}
led_agent() {  # <dir> <tool_use id> <name> <iso>
  jq -nc --arg i "$2" --arg n "$3" --arg ts "$4" \
    '{type:"assistant",timestamp:$ts,isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:$i,name:"Agent",
       input:{name:$n,description:"task",subagent_type:"bionic:implementor",prompt:("Task " + $n)}}]}}' >> "$1/transcript.jsonl"
}
led_result() {  # <dir> <tool_use id> <iso> <is_error true|false> <text>
  jq -nc --arg i "$2" --arg ts "$3" --argjson e "$4" --arg t "$5" \
    '{type:"user",timestamp:$ts,isSidechain:false,message:{role:"user",content:[{type:"tool_result",tool_use_id:$i,is_error:$e,content:$t}]}}' \
    >> "$1/transcript.jsonl"
}
# THE CLI'S OWN SYNTHETIC USER RECORDS (T11b; Step-6 review R3, critic C1). Two `user` records
# the CLI writes into the transcript that no person typed, each INSIDE the turn it interrupts.
# Shapes read out of the r2 bed transcript (record/wave-20-fixit-187/bed, session 1899e04c,
# records 27 and 37) and checked against 528 transcripts on this machine (2026-09-24):
#   the Stop hook's refusal   -> isMeta:true, content a STRING that starts "Stop hook feedback:"
#                                (187 of 187 such records; payload/scripts/lib/refuse.sh names the
#                                channel: "a synthetic user turn \"Stop hook feedback\" on Stop")
#   a skill's body            -> isMeta:true, turnCompanion:true, sourceToolUseID = the Skill call,
#                                content an ARRAY of one text block (135 of 135 carry the id)
# isMeta alone marks neither: a cron-fired Patrol prompt is isMeta:true too, and it IS a turn.
led_feedback() {  # <dir> <uuid> <iso> — the Stop hook's refusal, fed back to the model
  jq -nc --arg u "$2" --arg ts "$3" \
    '{type:"user",isMeta:true,uuid:$u,timestamp:$ts,isSidechain:false,userType:"external",
      message:{role:"user",content:"Stop hook feedback:\nbionic: stop refused — rows are ready and this turn dispatched none (dispatch each row, or decline)\n\nFillable gap at turn end: the run'"'"'s ledger is live."}}' \
    >> "$1/transcript.jsonl"
}
led_skill() {  # <dir> <tool_use id> <body uuid> <iso> — a Skill call, its result, and the body after it
  jq -nc --arg i "$2" --arg ts "$4" \
    '{type:"assistant",timestamp:$ts,isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:$i,name:"Skill",
       input:{skill:"bionic:canonical-sdlc"}}]}}' >> "$1/transcript.jsonl"
  jq -nc --arg i "$2" --arg ts "$4" \
    '{type:"user",timestamp:$ts,isSidechain:false,message:{role:"user",content:[{type:"tool_result",tool_use_id:$i,content:"Launching skill: bionic:canonical-sdlc"}]}}' \
    >> "$1/transcript.jsonl"
  jq -nc --arg i "$2" --arg u "$3" --arg ts "$4" \
    '{type:"user",isMeta:true,turnCompanion:true,sourceToolUseID:$i,uuid:$u,timestamp:$ts,isSidechain:false,userType:"external",
      message:{role:"user",content:[{type:"text",text:"Base directory for this skill: /abs/skills/canonical-sdlc\n\n# Canonical SDLC\n\nThe Patrol runs: bash /abs/hooks/session-poker.sh tick"}]}}' \
    >> "$1/transcript.jsonl"
}
LED_LOG_REL=".bionic/docs/record/${PLAN_REL%.plan.md}/fill-ledger.log"
led_line() {  # <dir> <n> -> the n-th ledger line
  sed -n "${2}p" "$1/$LED_LOG_REL" 2>/dev/null
}
led_field() {  # <line> <key>
  printf '%s\n' "$1" | tr '|' '\n' | sed -n "s/^$2=//p" | head -1
}

d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_SENT_2" "$LEDGER_T3_BEHIND")
ledger_roster "$d" open W-T2
led_user "$d" "u-turn-0001" "2026-09-23T10:00:00.000Z" "dispatch T2"
led_agent "$d" "toolu_A1" "W-T2" "2026-09-23T10:00:05.000Z"
led_result "$d" "toolu_A1" "2026-09-23T10:00:06.000Z" false "Spawned W-T2"
fire "$d"; expect_allow "L1a: Stop 1 — the dispatching turn ends clean"
L1="$(led_line "$d" 1)"
expect_contains "L1b: AC-5.5 Stop 1 appended a fill-ledger/v1 line" "fill-ledger/v1|" "$L1"
expect_eq "L1c: …keyed by the turn's prompt" "u-turn-0001" "$(led_field "$L1" turn)"
expect_eq "L1d: …launched names the turn's Agent call" "W-T2" "$(led_field "$L1" launched)"
expect_eq "L1e: …and nothing was missed" "0" "$(led_field "$L1" missed)"
expect_eq "L1f: …with fourteen fields, schema first" "14" "$(printf '%s' "$L1" | awk -F'|' '{ print NF }')"
expect_eq "L1g: …the session it belongs to" "$SID" "$(led_field "$L1" session)"

# Stop 2: T2 has landed, T3 is ready, the turn sends nothing -> refused, and recorded missed.
led_plan "$d" "$LEDGER_LANDED" "$LEDGER_T2_LANDED" "$LEDGER_T3_READY"
ledger_roster "$d" acked W-T2
led_user "$d" "u-turn-0002" "2026-09-23T10:20:00.000Z" "where are we?"
fire "$d"; expect_block "L2a: Stop 2 — T3 ready and nothing sent is refused" "T3"
L2="$(led_line "$d" 2)"
expect_eq "L2b: AC-5.5 the refused Stop is recorded too — same turn key" "u-turn-0002" "$(led_field "$L2" turn)"
expect_eq "L2c: …nothing launched" "" "$(led_field "$L2" launched)"
expect_eq "L2d: …one ready row missed" "1" "$(led_field "$L2" missed)"
expect_eq "L2e: …the ready row named" "T3" "$(led_field "$L2" ready)"

# Stop 3: after the refusal the model dispatches T3 and one refused dispatch, then stops with
# stop_hook_active — the re-entry the guard waves through, recorded before it does. The CLI
# feeds the refusal back first, as the synthetic user record it always writes (T11b: the
# fixture gained it; without it L3b was red-green against a transcript the CLI never writes).
led_feedback "$d" "u-fb-0002" "2026-09-23T10:20:30.000Z"
led_agent "$d" "toolu_A2" "W-T3" "2026-09-23T10:21:00.000Z"
led_result "$d" "toolu_A2" "2026-09-23T10:21:01.000Z" false "Spawned W-T3"
led_agent "$d" "toolu_A3" "W-BAD" "2026-09-23T10:21:02.000Z"
led_result "$d" "toolu_A3" "2026-09-23T10:21:03.000Z" true "PreToolUse:Agent hook error: dispatch refused — the name is in flight"
led_plan "$d" "$LEDGER_LANDED" "$LEDGER_T2_LANDED" "$LEDGER_T3_SENT"
ledger_roster "$d" open W-T3
fire "$d" Stop true; expect_allow "L3a: Stop 3 — the re-entry passes"
L3="$(led_line "$d" 3)"
expect_eq "L3b: AC-5.5 the re-entered Stop wrote a third line" "u-turn-0002" "$(led_field "$L3" turn)"
expect_eq "L3c: …launched is the post-refusal Agent call, the refused one left out" "W-T3" "$(led_field "$L3" launched)"
expect_eq "L3d: …and the turn now misses nothing" "0" "$(led_field "$L3" missed)"
expect_eq "L3e: three Stops, three lines" "3" "$(wc -l < "$d/$LED_LOG_REL" | tr -d ' ')"

# L8: THE REFUSED TURN IS ONE TURN (T11b; review R3, critic C1). A launch BEFORE the refusal,
# the Stop hook's feedback record, a launch after it, and the re-entry Stop: both lines carry
# the prompt's key, and the final line names both launches.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2" "$LEDGER_READY_3")
ledger_roster "$d" open W-T2
led_user "$d" "u-turn-0008" "2026-09-23T12:00:00.000Z" "dispatch the batch"
led_agent "$d" "toolu_B1" "W-T2" "2026-09-23T12:00:05.000Z"
led_result "$d" "toolu_B1" "2026-09-23T12:00:06.000Z" false "Spawned W-T2"
fire "$d"; expect_block "L8a: T11b Stop 1 — T2 launched, T3 left out: refused naming T3 and not T2" "T3" "T2"
expect_eq "L8b: …its line names the launch" "W-T2" "$(led_field "$(led_line "$d" 1)" launched)"
led_feedback "$d" "u-fb-0008" "2026-09-23T12:00:10.000Z"
led_agent "$d" "toolu_B2" "W-T3" "2026-09-23T12:00:20.000Z"
led_result "$d" "toolu_B2" "2026-09-23T12:00:21.000Z" false "Spawned W-T3"
ledger_roster "$d" open W-T3
led_plan "$d" "$LEDGER_LANDED" "$LEDGER_SENT_2" "$LEDGER_SENT_3"
fire "$d" Stop true; expect_allow "L8c: the re-entry passes"
L8_2="$(led_line "$d" 2)"
expect_eq "L8d: T11b the re-entry line keeps the prompt's key across the Stop hook's feedback record" \
  "u-turn-0008" "$(led_field "$L8_2" turn)"
expect_eq "L8e: …and the launch made before the refusal survives into the turn's final line" \
  "W-T2,W-T3" "$(led_field "$L8_2" launched)"
expect_eq "L8f: …two lines, one turn key" "1" \
  "$(sed -n 's/.*|turn=\([^|]*\)|.*/\1/p' "$d/$LED_LOG_REL" | sort -u | wc -l | tr -d ' ')"

# L9: THE DECLINE SURVIVES THE REFUSAL TOO. A Patrol marker turn declines the fill, ends without
# running its tick and is refused for that (§5f); the model runs the tick and stops again. The
# decline was written before the refusal, so only a turn that the feedback record did not
# split still carries it.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2")
tick_stamp "$d" 2026-09-23T12:59:00Z arm
jq -nc --arg t "bionic-patrol session=$SID8 — Patrol tick. Run: bash /abs/hooks/session-poker.sh tick" \
  '{type:"user",isMeta:true,uuid:"u-turn-0009",timestamp:"2026-09-23T13:00:00.000Z",isSidechain:false,message:{role:"user",content:$t}}' \
  >> "$d/transcript.jsonl"
both_duties "$d"
a_text "$d" "fill-declined: the wave head is mid-merge"
fire "$d"; expect_block "L9a: the marker turn that ran no tick is refused (the refusal whose feedback follows)" "session-poker.sh tick"
led_feedback "$d" "u-fb-0009" "2026-09-23T13:00:10.000Z"
tick_stamp "$d" 2026-09-23T13:00:20Z tick
fire "$d" Stop true; expect_allow "L9b: the re-entry passes"
L9_2="$(led_line "$d" 2)"
expect_eq "L9c: T11b the re-entry line keeps the marker prompt's key" "u-turn-0009" "$(led_field "$L9_2" turn)"
expect_contains "L9d: …and the decline written before the refusal is still the turn's" \
  "mid-merge" "$(led_field "$L9_2" declined)"

# L10: A SKILL'S BODY IS NOT A PROMPT (T11b; T21 bed item 6). A launch, then a Skill call whose
# body the CLI injects as a user record: the turn is still the prompt's, launch included.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_SENT_2")
ledger_roster "$d" open W-T2
led_user "$d" "u-turn-0010" "2026-09-23T14:00:00.000Z" "dispatch T2, then load the skill"
led_agent "$d" "toolu_C1" "W-T2" "2026-09-23T14:00:05.000Z"
led_result "$d" "toolu_C1" "2026-09-23T14:00:06.000Z" false "Spawned W-T2"
led_skill "$d" "toolu_C2" "u-skill-0010" "2026-09-23T14:00:07.000Z"
fire "$d"; expect_allow "L10a: the turn ends clean"
expect_eq "L10b: T11b the skill body opens no turn — the line is keyed by the prompt" \
  "u-turn-0010" "$(led_field "$(led_line "$d" 1)" turn)"
expect_eq "L10c: …and the launch before the Skill call is the turn's" "W-T2" "$(led_field "$(led_line "$d" 1)" launched)"

# L11: …AND A MARKER TURN THAT LOADS A SKILL IS STILL A MARKER TURN: the tick flag survives the
# body, so a turn that never ran its tick is refused for it (§5f), and one that did is not.
l11_env() {  # <stamp at> <verb>
  local d; d=$(make_env_ledger 4 "$LEDGER_LANDED")
  tick_stamp "$d" "$1" "$2"
  jq -nc --arg t "bionic-patrol session=$SID8 — Patrol tick. Run: bash /abs/hooks/session-poker.sh tick" \
    '{type:"user",isMeta:true,uuid:"u-turn-0011",timestamp:"2026-09-23T15:00:00.000Z",isSidechain:false,message:{role:"user",content:$t}}' \
    >> "$d/transcript.jsonl"
  led_skill "$d" "toolu_D1" "u-skill-0011" "2026-09-23T15:00:03.000Z"
  both_duties "$d"
  printf '%s' "$d"
}
d=$(l11_env 2026-09-23T14:59:00Z arm)
fire "$d"; expect_block "L11a: T11b a marker turn that loads a skill and runs no tick is refused for the tick" "session-poker.sh tick"
d=$(l11_env 2026-09-23T15:00:05Z tick)
fire "$d"; expect_allow "L11b: …and with the tick stamped after the marker it passes"

# L12: THE FEEDBACK MARK IS THE CLI'S, NOT THE WORDS. A prompt a person typed that merely starts
# "Stop hook feedback:" carries no isMeta, and it is a turn of its own.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_SENT_2")
ledger_roster "$d" open W-T2
led_user "$d" "u-turn-0012" "2026-09-23T16:00:00.000Z" "dispatch T2"
led_agent "$d" "toolu_E1" "W-T2" "2026-09-23T16:00:05.000Z"
led_result "$d" "toolu_E1" "2026-09-23T16:00:06.000Z" false "Spawned W-T2"
led_user "$d" "u-turn-0012b" "2026-09-23T16:01:00.000Z" "Stop hook feedback: pasted from another window"
fire "$d"
expect_eq "L12a: a typed prompt that quotes the feedback prefix opens a turn" "u-turn-0012b" "$(led_field "$(led_line "$d" 1)" turn)"
expect_eq "L12b: …and the previous turn's launch is not its" "" "$(led_field "$(led_line "$d" 1)" launched)"

# L4: a SubagentStop records nothing — a writer's turn end is not the run's.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2")
led_user "$d" "u-turn-0004" "2026-09-23T11:00:00.000Z" "carry on"
fire "$d" SubagentStop
expect_false "L4: a SubagentStop appends no ledger line" test -s "$d/$LED_LOG_REL"

# L5: an unengaged session records nothing — the consent boundary.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2")
rm -f "$d/.bionic/tmp/engaged-$SID.state"
led_user "$d" "u-turn-0005" "2026-09-23T11:00:00.000Z" "carry on"
fire "$d"
expect_false "L5: an unengaged session appends no ledger line" test -s "$d/$LED_LOG_REL"

# L6: a machine at HOLD is recorded as HOLD, the gap with it — the report's HOLD minutes.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2")
led_user "$d" "u-turn-0006" "2026-09-23T11:00:00.000Z" "carry on"
BIONIC_PROBE_FREE_MB=512 fire "$d"
expect_eq "L6: a HOLD Stop records state=hold" "hold" "$(led_field "$(led_line "$d" 1)" state)"

# L7: a decline is recorded with its reason, pipes squashed so the line keeps its fields.
d=$(make_env_ledger 4 "$LEDGER_LANDED" "$LEDGER_READY_2")
led_user "$d" "u-turn-0007" "2026-09-23T11:00:00.000Z" "carry on"
a_text "$d" "fill-declined: the head is mid-merge | back in ten"
fire "$d"; expect_allow "L7a: the declined turn ends"
expect_contains "L7b: …and its reason is on the ledger line" "the head is mid-merge" "$(led_field "$(led_line "$d" 1)" declined)"
expect_eq "L7c: …with the line still fourteen fields" "14" "$(led_line "$d" 1 | awk -F'|' '{ print NF }')"

# ============================================================
section "Section 5f: a Patrol marker turn that ran no tick is refused once (wave-20 REQ-6, AC-6.2; D6)"
#
# THE DEFECT (report #1, M4). A Patrol job whose prompt carried the marker but not the tick
# produced turns this wall called ticks — the task-list refresh was asked for, nothing else —
# while the tick never ran and nothing decided anything. The tick's own record is its stamp:
# it writes `verb=tick` before it decides. So a marker turn ends only when a `verb=tick`
# stamp sits at or after the marker row; otherwise it is refused once, naming the tick.
MK_TICK="session-poker.sh tick"
mk_env() {  # <stamp at|none> [verb] -> a marker turn at 10:00:00Z with both duties done
  local d; d=$(make_env)
  jq -nc --arg t "bionic-patrol session=$SID8 — Patrol tick. Run: bash /abs/hooks/session-poker.sh tick" \
    '{type:"user",uuid:"u-mk",timestamp:"2026-09-23T10:00:00.000Z",isSidechain:false,message:{role:"user",content:$t}}' \
    >> "$d/transcript.jsonl"
  both_duties "$d"
  [ "$1" = none ] || tick_stamp "$d" "$1" "${2:-tick}"
  printf '%s' "$d"
}

d=$(mk_env 2026-09-23T09:59:00Z arm)
fire "$d"; expect_block "M1: AC-6.2 a marker turn over an older arm stamp is refused" "$MK_TICK"
fire "$d" Stop true; expect_allow "M2: …once — stop_hook_active passes"

d=$(mk_env 2026-09-23T09:40:00Z tick)
fire "$d"; expect_block "M3: a tick stamp from BEFORE the marker does not answer it" "$MK_TICK"

d=$(mk_env 2026-09-23T10:00:05Z tick)
fire "$d"; expect_allow "M4: a verb=tick stamp after the marker answers it"

d=$(mk_env 2026-09-23T10:00:00Z tick)
fire "$d"; expect_allow "M5: …and one at the marker's own second does too (at or after)"

d=$(mk_env 2026-09-23T10:00:05Z arm)
fire "$d"; expect_block "M6: an arm stamp after the marker is not a tick" "$MK_TICK"

# M7: the refusal names the canonical prompt verb as well, for the job that never runs it.
d=$(mk_env 2026-09-23T09:59:00Z arm)
fire "$d"; expect_block "M7: …and names the verb that prints the canonical prompt" "session-poker.sh prompt"

# M8: an undated marker row (the older fixture shape) is answered by the stamp's verb alone.
d=$(make_env); u_marker "$d"; both_duties "$d"; tick_stamp "$d" "" arm
fire "$d"; expect_block "M8: an undated marker with only an arm stamp is refused" "$MK_TICK"
d=$(make_env); u_tick "$d"; both_duties "$d"
fire "$d"; expect_allow "M9: …and with a tick stamp it passes"

# M10: a turn that is not a marker turn owes no tick, whatever the stamp says.
d=$(make_env); u_prompt "$d" "carry on"; tick_stamp "$d" 2026-09-01T00:00:00Z arm
fire "$d"; expect_allow "M10: a non-marker turn is never asked for a tick"

# M11: no stamp at all — a disarmed Patrol, or none armed — is not asked (the tick's DISARM
# removes the stamp as its last act; the revive notice's absent state is silent for the same
# reason).
d=$(mk_env none)
fire "$d"; expect_allow "M11: a marker turn with no stamp on disk is not refused"

# M12: the duty and the missing tick are told together.
d=$(make_env); u_marker "$d"; tick_stamp "$d" "" arm
fire "$d"; expect_block "M12: a marker turn missing its task-list refresh AND its tick names the refresh" "$TL_MISSING"
fire "$d"; expect_block "M12b: …and the tick, in the same refusal" "$MK_TICK"

# THE RING AND THE PROBES STAY PINNED for the rest of the suite (wave-20): §6 drives the same
# fill duty on live ledgers, and an unpinned ring is this machine's real one.

# ============================================================
section "Section 6: marker scope — a file the agent merely READ is not a decline (review F2)"
#
# THE DEFECT. `fill-declined:` and the two clear/resume markers were read as a raw-text
# substring of EVERY transcript record, tool results included. A tool result is how the
# content of any file the agent reads enters the transcript, so a README, a fixture or a
# code comment carrying the literal `fill-declined:` discharged the AC-29 fill duty that
# nobody had declined — fail-open on the exact wall AC-29 exists to be. The mirror case is
# friction rather than compromise: a file carrying the /clear or resume marker forced a
# spurious resume-ritual refusal.
#
# THE SCOPE. These two markers are now read only off rows the ORCHESTRATOR authored: a
# main-thread assistant record (its text and its tool_use inputs alike), a user record
# whose content is a STRING — the CLI's own command records and the operator's own typing
# — and any other record type, which is how a SessionStart report reaches the transcript.
# Never the `tool_result` elements of a user record. STOPGATES/1's type-agnostic substring
# read is kept WITHIN a qualifying row; what changed is which rows qualify. The `poker:
# FILL` line itself is deliberately NOT scoped — it arrives as the content of the tick's
# own Bash tool result, and a planted one costs a false BLOCK, the safe direction.

# An assistant text row inside an agent context — a subagent's words, not the
# orchestrator's.
a_text_sidechain() {  # <dir> <text>
  jq -nc --arg t "$2" \
    '{type:"assistant",isSidechain:true,
      message:{role:"assistant",content:[{type:"text",text:$t}]}}' \
    >> "$1/transcript.jsonl"
}

# 48/49: THE PAIR. The same literal decline text, once as file content the agent read and
# once as the orchestrator's own writing. Only the second answers.
# RE-POINTED AT THE COMPUTED GAP (wave-20 Δ7): the printed FILL these rows used to carry is not
# evidence any more, so the duty they decline is §5d's two-row ledger gap.
d=$(plant_env)
u_tick_out "$d" "fill-declined: <reason> is the line to write when you decline a fill."
fire "$d"; expect_plant_inert "48: a fill-declined: inside a tool result does not answer the gap"

d=$(plant_env)
a_text "$d" "fill-declined: peers not idle (D1)."
fire "$d"; expect_allow "49: …and the same words in the orchestrator's own assistant row do"

# 50/51: THE PAIR, ritual side. The /clear marker as file content the agent read is inert;
# the CLI's own /clear record still arms the ritual.
d=$(make_env)
u_tick_out "$d" "record/wave-1.4.0-probe.md:12  the new transcript opens with <command-name>/clear</command-name> verbatim."
a_tool "$d" CronCreate
fire "$d"; expect_allow "50: a /clear marker inside a tool result does not arm the ritual"

d=$(make_env); u_clear_marker "$d"; a_tool "$d" CronCreate
fire "$d"; expect_block "51: …and the CLI's own /clear record still does" "$RITUAL_CRONLIST"

# 52/53: the resume spelling, same pair. The system-typed record of §31 still arms it
# (STOPGATES/1's type-agnostic read is untouched); the same words read out of a file do not.
d=$(make_env)
u_tick_out "$d" "hooks/session-start.sh:41  prints (source: resume) into its own title line."
a_tool "$d" CronCreate
fire "$d"; expect_allow "52: a resume marker inside a tool result does not arm the ritual"

d=$(make_env); u_resume_marker "$d"; a_tool "$d" CronCreate
fire "$d"; expect_block "53: …and a system-typed session-start report still does" "$RITUAL_CRONLIST"

# 54: a SUBAGENT's decline is not the orchestrator's — the same agent-context exclusion
# every other arm of this gate makes, now applied to the decline it never applied to.
d=$(plant_env)
a_text_sidechain "$d" "fill-declined: the subagent decided not to."
fire "$d"; expect_plant_inert "54: a sidechain assistant's decline does not answer the orchestrator's gap"

# 55: THE FILL LINE IS NOT READ AT ALL (wave-20 Δ7, reversing this row's old pin). It used to
# be read raw out of the tick's tool result and nothing else; now nothing reads it. A tick
# turn that printed `FILL ALPHA BETA` over an empty computed ready set, with one of the two
# "answered" by an Agent call, owes nothing either way.
d=$(make_env); u_tick "$d"; both_duties "$d"; u_tick_out "$d" "poker: FILL ALPHA BETA"
a_agent "$d" "W-ALPHA" "Task ALPHA, implementor."
fire "$d"; expect_allow "55: the printed FILL line is read by nothing — the ready set is the wall's"

section "Section 7: RETIRED — no id is matched against a dispatch's words (wave-20 Δ7)"
#
# This section pinned the word-boundary regex that matched a printed FILL id against an Agent
# call's name, description and prompt, and the escape that kept a `.` in an id literal
# (review correctness F1). The wall no longer matches ids to words at all: a turn is judged by
# count, the ready set is the plan's and the occupancy the roster's (§5c, §5d P4). The regex
# is gone, and with it the class of defect these four rows guarded; a dotted id reaching the
# refusal verbatim is the one property left, and it is asserted here.
d=$(make_env_ledger 4 "$LEDGER_LANDED" '| T4.2 | 4 | build | a dotted row | implementor | — | 30m | REQ-x | z.sh | pending | — |')
u_prompt "$d" "carry on"
fire "$d"; expect_block "59: a ready id carrying a dot is named verbatim" "T4.2"

section "Section 8: the scan is windowed (review performance, finding 1)"
#
# THE DEFECT. This gate read the WHOLE transcript through one jq pass on every Stop of an
# open run — from byte zero, ~85 ms of CPU per MB, measured 4.3 s over the 50 MB a long
# wave session reaches, and rising monotonically for the life of the run: worst exactly
# when the run is oldest and busiest. hooks/context-spend.sh, in this same wave, already
# bounds the same class of read with `tail -n 400`.
#
# THE WINDOW. Every fact this scan needs is a "since the most recent X" fact — the last
# user prompt, the last clear/resume marker, the last FILL line — so a window suffices
# provided it holds a whole orchestrator turn. It does: the largest single turn in this
# repo's own two busiest wave transcripts is 264 records (measured 2026-09-03 over
# 494cf1b6 and b1a850c1), and the window is 2000.
#
# WHAT SCROLLING OUT COSTS, pinned here rather than left to be discovered: a marker older
# than the window reads as NO MARKER, so the ritual arm goes INERT — it does not refuse.
# That is FAIL-OPEN, and it is the right direction for a marker whose whole purpose is to
# catch the FIRST stop after a resume; by the time 2000 records have gone by the ritual is
# either long done or long moot.

# N benign padding records — a main-thread Read, which satisfies no duty, answers no FILL
# and names no plan. Written by awk rather than a shell loop: these fixtures are 20k lines.
pad() {  # <dir> <n>
  local line
  line=$(jq -nc '{type:"assistant",isSidechain:false,
                  message:{role:"assistant",content:[{type:"tool_use",id:"toolu_p",name:"Read",
                    input:{file_path:"/tmp/pad.txt"}}]}}')
  awk -v n="$2" -v l="$line" 'BEGIN{ for (i = 0; i < n; i++) print l }' >> "$1/transcript.jsonl"
}

# 60: 20k records of history BEFORE the marker change nothing — the marker and the
# CronCreate are both inside the window, and the refusal fires exactly as in §27.
d=$(make_env); pad "$d" 20000; u_clear_marker "$d"; a_tool "$d" CronCreate
fire "$d"; expect_block "60: a marker inside the window is still found under 20k records of history" "$RITUAL_CRONLIST"

# 61: THE DOCUMENTED LIMIT. The same marker with 20k records AFTER it has scrolled out of
# the window, and the arm reads "no marker" — inert, not a refusal. Fail-open, stated.
d=$(make_env); u_clear_marker "$d"; pad "$d" 20000; a_tool "$d" CronCreate
fire "$d"; expect_allow "61: a marker beyond the window reads as no marker — the arm goes inert"

# 62: THE BOUND IS NAMED AND IS A CONSTANT. A window that regresses to an unbounded read
# is invisible in every behavioural test above — 60 and 61 both still pass without a
# `tail` if the whole file is small. This is the assertion that the bound exists at all.
if grep -q '^SCAN_WINDOW_LINES=[0-9][0-9]*$' "$HOOK_SRC" && grep -q 'tail -n "\$SCAN_WINDOW_LINES"' "$HOOK_SRC"; then
  ok "62: the transcript scan is bounded by a named SCAN_WINDOW_LINES constant"
else
  no "62: the transcript scan has no named line bound — it reads from byte zero"
fi
# ---------- Group 25: THE ENGAGEMENT SWITCH (AC-8) ----------
#
# The switch is asked before the transcript is read at all, so each silence below is paired
# with the refusal the same fixture produces once the marker is back.

# 63: the ordinary refusing fixture, engaged -> blocks.
d=$(make_env); u_tick "$d"
fire "$d"; expect_block "63: engaged: a tick with neither duty blocks" "$TL_MISSING"

# 64: the SAME fixture with the marker removed -> nothing at all.
rm -f "$d/.bionic/tmp/engaged-$SID.state"
fire "$d"; expect_allow "64: the same fixture unengaged is silent"

# 65: a SYMLINK at the marker path reads as absent, never followed.
DECOY_MARK=$(mktemp); printf 'plan=none\n' > "$DECOY_MARK"
ln -s "$DECOY_MARK" "$d/.bionic/tmp/engaged-$SID.state"
fire "$d"; expect_allow "65: a symlink at the marker path is not an engagement"
rm -f "$d/.bionic/tmp/engaged-$SID.state"

# 66: ANOTHER session's marker is not this session's.
: > "$d/.bionic/tmp/engaged-99999999-8888-7777-6666-555555555555.state"
fire "$d"; expect_allow "66: another session's marker is not this session's engagement"

# 67: restoring this session's marker restores the refusal, word for word.
: > "$d/.bionic/tmp/engaged-$SID.state"
fire "$d"; expect_block "67: re-engaged, the refusal returns unchanged" "$TL_MISSING"

# ---------- Group 26: WHAT COUNTS AS A TICK (T6, AC-22) ----------
#
# The defect this replaces: the gate called a turn a tick when the last USER row CONTAINED
# `session-poker.sh tick`, and the canonical-sdlc SKILL.md body — injected into the
# transcript as a USER row — contains exactly that literal. Invoking the skill was a tick.

# 68j: a USER row that merely CONTAINS the tick command is not a tick (renamed from a second
# `68:` — labels are unique, audit V-8).
d=$(make_env)
u_prompt "$d" "Base directory for this skill: /x/skills/canonical-sdlc

# Canonical SDLC

... **Tick the poker.** \`bash <plugin-root>/hooks/session-poker.sh tick\` is the decision brain — the prompt gathers, the poker decides, per row. ..."
fire "$d"; expect_allow "68j: the injected SKILL.md body is not a Patrol tick"

# 69: THE PAIRED POSITIVE, so 68 is not silence-by-vacuity: the same fixture with the real
# marker at the front of the row refuses.
d=$(make_env); u_tick "$d"
fire "$d"; expect_block "69: …while a row led by the patrol marker is" "$TL_MISSING"

# 70: ANOTHER session's marker leads the row -> a predecessor's cron firing into this
# conversation after a /clear is not this session's tick.
d=$(make_env)
u_prompt "$d" "bionic-patrol session=deadbeef — Patrol tick. Run: bash /abs/hooks/session-poker.sh tick"
fire "$d"; expect_allow "70: a row led by ANOTHER session's patrol marker is not a tick"

# 71: the marker must LEAD the row, not merely appear in it.
d=$(make_env)
u_prompt "$d" "Here is what the cron job carries: bionic-patrol session=$SID8 — and that is all I wanted to show you."
fire "$d"; expect_allow "71: the marker mid-row is not a tick — it must be the first token"

# 72: the tick-turn arms read the same marker. A real tick turn missing its refresh is
# refused; the SKILL.md body carrying the literal is not a tick at all (73).
d=$(make_env); u_tick "$d"; u_tick_out "$d" "poker: FILL S3 S4"
fire "$d"; expect_block "72: a real tick turn missing its refresh blocks" "$TL_MISSING"

d=$(make_env)
u_prompt "$d" "... \`bash <plugin-root>/hooks/session-poker.sh tick\` is the decision brain ..."
both_duties "$d"; u_tick_out "$d" "poker: FILL S3 S4"
fire "$d"; expect_allow "73: …and the same FILL line after a non-tick row is not a duty"

setup_section "Section S5: active_run -> session_run (wave-session-bound-run S5)"
#
# THE CONTRACT UNDER TEST (design ledger AC-1/AC-3/AC-6). `PLAN` — and so
# `PLAN_NAME`, the basename that discharges the task-list duty — used to come
# from `active_run "$PROJECT_DIR"`: the newest open plan in the root, with no
# session input at all. It now comes from `session_run "$PROJECT_DIR" "$SID"`: a
# session BOUND to a plan is policed against that plan's basename alone, whatever
# else is open in the root; UNBOUND (the marker empty, as make_env's own marker
# is) it falls back to the newest plan exactly as before, and says so on stderr;
# bound to a plan that has since closed, it is policed exactly as an engaged
# session with no plan at all (no basename can ever discharge the duty), and
# that closure is announced too.

# Captures stderr SEPARATELY from fire() (which discards it) — the advisory is a
# diagnostic line, and this is the only way to read it. Mirrors
# tests/patrol-revive.test.sh's own fire_stderr.
fire_stderr() {  # <project> [event] [stop_hook_active]
  HOOK_ERR=$(env CLAUDE_CODE_SESSION_ID="$SID" bash "$HOOK" \
    <<< "$(stdin_for "$1" "$1/transcript.jsonl" "${2:-Stop}" "${3:-false}")" 2>&1 >/dev/null)
}

PLAN_A_REL="plan-a.plan.md"
PLAN_B_REL="plan-b.plan.md"

# make_env_two_plans -> project dir on stdout. Two OPEN plans under one docs
# root, ages controlled by touch so the newest (B) is decisively the fallback
# target. ENGAGED, UNBOUND by default (make_env's own convention) — s5_bind
# below overwrites the marker for the bound cases.
make_env_two_plans() {
  local dir; dir=$(mktemp -d)
  mkdir -p "$dir/.bionic/docs/plans" "$dir/.bionic/tmp"
  : > "$dir/.bionic/tmp/engaged-$SID.state"
  cat > "$dir/.bionic/docs/plans/$PLAN_A_REL" <<'EOF'
---
governing-skill: canonical-sdlc
---
## SDLC State

current: T5
EOF
  cat > "$dir/.bionic/docs/plans/$PLAN_B_REL" <<'EOF'
---
governing-skill: canonical-sdlc
---
## SDLC State

current: T5
EOF
  touch -t 202601010000 "$dir/.bionic/docs/plans/$PLAN_A_REL"
  touch -t 202602010000 "$dir/.bionic/docs/plans/$PLAN_B_REL"
  : > "$dir/transcript.jsonl"
  printf '%s' "$dir"
}

# s5_bind <project> <plan-rel-under-docs-plans>
s5_bind() {
  { printf 'plan=%s/.bionic/docs/plans/%s\n' "$1" "$2"
    printf 'engaged_at=2026-09-04T00:00:00Z\n'
  } > "$1/.bionic/tmp/engaged-$SID.state"
  chmod 600 "$1/.bionic/tmp/engaged-$SID.state"
}

# s5_deliver <plan-abs-path> — closes a T-scale plan by replacing it with a
# closed numeric-scale one (task scale, per lib/run.sh's own table, is always
# open — there is no "delivered" state to give it).
s5_deliver() {
  cat > "$1" <<'EOF'
---
governing-skill: canonical-sdlc
---
## SDLC State

current: 9

- Step 9: report record/x.md, delivered: 2026-09-04
EOF
}

section "24: bound-open — only the BOUND plan's basename discharges the duty"

d=$(make_env_two_plans); s5_bind "$d" "$PLAN_A_REL"
u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" Edit "$d/.bionic/docs/plans/$PLAN_A_REL"
fire "$d"; expect_allow "24a: bound to A, an Edit naming A satisfies the task-list duty"

d=$(make_env_two_plans); s5_bind "$d" "$PLAN_A_REL"
u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" Edit "$d/.bionic/docs/plans/$PLAN_B_REL"
fire "$d"; expect_block "24b: bound to A, an Edit naming B (unrelated to A) does not satisfy it" \
  "$TL_MISSING" "$LA_MISSING"
fire_stderr "$d"
case "$HOOK_ERR" in
  *"run resolved by newest-plan fallback"*) no "24c: bound to A prints no fallback line" "$HOOK_ERR" ;;
  *) ok "24c: bound to A prints no fallback line" ;;
esac

section "25: fallback — unbound resolves to the newest plan (B), and says so"

d=$(make_env_two_plans)
# PHYSICAL, because the fallback path comes off active_plan's own resolution —
# `project_root` calls `pwd -P` internally (payload/scripts/lib/root.sh) — while
# `$d` is `mktemp -d`'s raw (logical) answer. The two differ under macOS's
# /var -> /private/var link; this assertion pins an exact adjacency ("— "
# immediately followed by the path), so — unlike a bare path-substring check —
# it needs the physical form the hook itself prints.
d_phys=$(cd "$d" && pwd -P)
u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" Edit "$d/.bionic/docs/plans/$PLAN_B_REL"
fire "$d"; expect_allow "25a: unbound, an Edit naming B (the newest) satisfies the duty"
fire_stderr "$d"
case "$HOOK_ERR" in
  *"patrol-duties-gate: run resolved by newest-plan fallback (session unbound) — $d_phys/.bionic/docs/plans/$PLAN_B_REL"*)
    ok "25b: unbound prints the fallback line, naming B verbatim" ;;
  *) no "25b: unbound prints the fallback line, naming B verbatim" "$HOOK_ERR" ;;
esac

# THE PAIRED NEGATIVE: unbound, A's name (the OLDER plan, not the fallback
# target) does not satisfy the duty.
d=$(make_env_two_plans)
u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" Edit "$d/.bionic/docs/plans/$PLAN_A_REL"
fire "$d"; expect_block "25c: unbound, an Edit naming A (not the fallback target) does not satisfy it" \
  "$TL_MISSING" "$LA_MISSING"

section "26: bound-closed — a plan that closed is no open run at all"

d=$(make_env_two_plans)
s5_deliver "$d/.bionic/docs/plans/$PLAN_A_REL"
s5_bind "$d" "$PLAN_A_REL"
u_tick "$d"; a_tool "$d" ListAgents; a_tool "$d" Edit "$d/.bionic/docs/plans/$PLAN_B_REL"
fire "$d"; expect_block "26a: bound to a CLOSED A, an Edit naming open B satisfies nothing" \
  "$TL_MISSING" "$LA_MISSING"
fire_stderr "$d"
case "$HOOK_ERR" in
  *"patrol-duties-gate: bound plan closed — $d/.bionic/docs/plans/$PLAN_A_REL; this session has no open run"*)
    ok "26b: the closed-plan advisory names A, verbatim" ;;
  *) no "26b: the closed-plan advisory names A, verbatim" "$HOOK_ERR" ;;
esac
case "$HOOK_ERR" in
  *"$PLAN_B_REL"*) no "26c: B's path (the still-open plan) appears nowhere in the output" "$HOOK_ERR" ;;
  *) ok "26c: B's path (the still-open plan) appears nowhere in the output" ;;
esac

section "AC-E1.3/E1.5: the refusal's user stream is one line, in the criterion's shape"

# fails-when: a refusal reaches the user as more than one line, or in any shape but
# `bionic: <verb> refused — <fact> (<fix ≤ 40 cols>)`. This gate refuses over the JSON
# `block` channel, which has a model-only wire — so the reason the arms above read stays
# whole in the JSON while the USER stream is the single rendered line, always, knob or
# no knob. Both halves are asserted on one drive of a real refusal.

PE1_RE='^bionic: [a-z-]+ refused — .+ \(.{1,40}\)$'
PE1_ERRFILE="$(mktemp)"
# Drive a real refusal through the same helper the arms above use, then read the user
# stream it left behind. The status is the block channel's own: exit 0 with a verdict.
PE1_D=$(make_env); u_tick "$PE1_D"; a_tool "$PE1_D" ListAgents
fire "$PE1_D"
expect_contains "E1.3 the JSON verdict is still a block (the model's half is unchanged)" \
  '"decision":"block"' "$HOOK_OUT"
# ONE REFUSAL LINE. The gate also prints its own diagnostics to stderr before it
# decides, so the count is of RENDERED refusals and not of every byte on the stream.
expect_eq "E1.3 the user stream carries exactly one rendered refusal" \
  "1" "$(printf '%s\n' "$HOOK_ERR_USER" | /usr/bin/grep -c '^bionic: ')"
if printf '%s\n' "$HOOK_ERR_USER" | /usr/bin/grep '^bionic: ' | /usr/bin/grep -qE "$PE1_RE"; then
  ok "E1.3 …in AC-E1.3's shape"
else
  no "E1.3 …in AC-E1.3's shape" "line=[$HOOK_ERR_USER]"
fi
expect_contains "E1.3 …and it is one of this gate's ruled facts" \
  "bionic: stop refused — no task-list refresh since this tick" "$HOOK_ERR_USER"
expect_absent "E1.5 the paragraph the model reads is NOT on the user stream" \
  "this gate blocks once" "$HOOK_ERR_USER"

finish
