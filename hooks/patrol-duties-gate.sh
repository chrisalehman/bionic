#!/bin/bash
# THE PATROL-DUTIES WALL — task-dispatch-wall-channel-loss, T5.
#
# Stop. On every orchestrator turn end: if the turn was started by a PATROL TICK,
# refuse the stop once unless the tick's two standing duties were performed
# inside it — a subagent-panel refresh (`ListAgents`) and a task-list refresh
# (`TaskList`, or a write naming the active plan file). Any other turn passes
# untouched, as does any ambiguity along the way.
#
# WHY A WALL AND NOT BETTER WORDING. The duties live in the Patrol prompt today,
# and a prompt is text: it asks. Every rule in this repo that actually binds is a
# wall (memory/rules-are-walls-not-wishes), and the only event that can express
# "this must have happened before the turn ends" is the turn's END. A PreToolUse
# arm cannot say it — at the moment any single tool runs, the turn is not over
# and nothing has been skipped yet. So the predicate is retrospective by
# construction, and Stop is the one channel that can ask it.
#
# WHY THE SKILL CHANNEL. `Stop` is delivered to skill-frontmatter hooks keyed by
# SESSION id, fires once per orchestrator turn, and keeps firing on turns the
# skill was not re-invoked on — the same three properties hooks/landing-gate.sh
# depends on and documents at length. This gate is registered beside it in
# payload/skills/canonical-sdlc/SKILL.md, so it is live exactly while the
# governing skill is.
#
# WHAT A "PATROL TICK" IS, STRUCTURALLY. The tick prompt is composed per session
# by a model and its wording is therefore not a fact anything may key on. What IS
# a fact is the command SKILL.md's Dispatch section makes the first of the
# prompt's reads: `session-poker.sh tick`. That literal in the turn's opening
# user message is the marker — the same structural-not-textual identification
# payload/scripts/lib/patrol.sh uses to recognise a Patrol cron job (T2 judgment
# call (b)), reached independently and agreeing.
#
# WHAT COUNTS, AND WHEN. Only AFTER the tick's own prompt: duties performed in
# some earlier turn are stale by exactly the interval the tick exists to cover.
# Only on the MAIN THREAD: a tool_use inside an agent context (`isSidechain`, or
# a non-empty agent key) belongs to a subagent, and a subagent's ListAgents did
# not refresh the orchestrator's panel — the mirror image of the exclusion
# hooks/session-poker.sh:399-406 makes for the same reason.
#
# THE TASK-LIST FALLBACK IS NOT A CONVENIENCE. The task tools are absent from
# some model/CLI combinations (memory/task-tools-tengu-gate: removed for fable-5
# in CLI 2.1.228–2.1.233), and in those sessions the plan's own ledger IS the
# task list. A wall that demanded `TaskList` there would be unsatisfiable, which
# is the one failure mode a blocking gate must not have. So an Edit/Write/
# NotebookEdit/Bash tool_use whose input names the active plan file discharges
# the same duty.
#
# FAIL DIRECTIONS (pinned by tests/patrol-duties-gate.test.sh):
#   - jq absent                                          -> pass, silent
#   - not a Stop payload (SubagentStop included)          -> pass, silent
#   - stop_hook_active true                               -> pass, silent (blocks ONCE)
#   - no cwd, or it is not a directory                    -> pass, silent
#   - no transcript_path, or no file there, or a symlink  -> pass, silent
#   - no user prompt in the transcript at all             -> pass, silent
#   - the last user prompt is not a Patrol tick           -> pass, silent
#   - both duties done since that prompt                  -> pass, silent
#   - either duty missing                                 -> REFUSE, naming which
#
# TWO ACCEPTED LIMITS, both a false BLOCK rather than a false silence, and both
# cheap because the refusal is once-only (stop again and the turn ends). First,
# the Stop-time transcript "isn't guaranteed to include the final message ... on
# all versions" (hooks reference, Stop input), so a duty discharged as the very
# last act of the turn may not be on disk when this reads it. Second, a Patrol
# tick that legitimately has nothing to do still owes both duties under this
# gate — which is the contract SKILL.md states, not an accident of the read.
# The reference's own backstop — "Claude Code overrides the hook and ends the
# turn after 8 consecutive blocks" — cannot engage here: this gate blocks once per
# turn and passes the re-entry, so its blocks are never consecutive. The
# once-only refusal above is the whole bound.
#
# IT WRITES NOTHING AND DECIDES NOTHING ELSE. No state file, no roster append, no
# stamp: this is a gate, and gates may only read (TDD §3.2). It takes no view on
# whether the tick's WORK was right, only on whether the two duties happened.
#
# Registered on the Stop channel in payload/skills/canonical-sdlc/SKILL.md; live
# only while that skill is armed.
# [WALL: tests/patrol-duties-gate.test.sh]

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)

_jq() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

# ---------- relevance hoist ----------
# SubagentStop is deliberately NOT accepted. A subagent has no Patrol duties, and
# a wall that refused its stop would hold a worker hostage to its orchestrator's
# obligations.
[ "$(_jq '.hook_event_name')" = "Stop" ] || exit 0

# BLOCKS ONCE. Claude Code re-enters the stop with stop_hook_active true after a
# hook blocked it; refusing again would wedge the turn in a loop it has no way
# out of. One refusal names the duties; the second stop is the orchestrator's to
# decide about. That re-entry is also this gate's safety valve: nothing it can
# ever demand is unsatisfiable, because stopping again always passes.
[ "$(_jq '.stop_hook_active')" = "true" ] && exit 0

TRANSCRIPT=$(_jq '.transcript_path')
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && [ ! -L "$TRANSCRIPT" ] || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
[ -n "$PROJECT_DIR" ] || PROJECT_DIR=$(_jq '.cwd')
[ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ] || exit 0

# ---------- the active plan file ----------
#
# DELIBERATELY DUPLICATED from hooks/context-spend.sh, which mirrors
# hooks/canonical-sdlc-evidence-gate.sh's own discovery — three copies of one
# question ("which plan is the active one"), held together by the fleet's
# no-shared-lib rule (TDD §9: a sourced file the installer misses is a silently
# inert wall). If these are ever bridged, context-spend.sh's copy and this one
# go together; the evidence gate's is the original.
#
# Only the plan's BASENAME is kept. The path a tool_use carries may be absolute,
# repo-relative or cwd-relative depending on which tool wrote it, and the
# basename is the one form all three contain. An empty name matches nothing —
# guarded at the awk boundary, because an empty needle would otherwise make
# every write in the turn discharge the duty.
DOCS_ROOT=".bionic/docs"
if [ -f "$PROJECT_DIR/.bionic/config.yaml" ]; then
  _cfg=$(grep -E '^docs-root:' "$PROJECT_DIR/.bionic/config.yaml" 2>/dev/null | head -1 \
         | sed 's/^docs-root:[[:space:]]*//' | tr -d '\r' | sed 's/[[:space:]]*$//')
  [ -n "$_cfg" ] && DOCS_ROOT="$_cfg"
fi
PLANS_DIR="$PROJECT_DIR/$DOCS_ROOT/plans"
PLAN_NAME=""
if [ -d "$PLANS_DIR" ]; then
  _plan=$(ls -t "$PLANS_DIR"/*.plan.md "$PLANS_DIR"/*/*.plan.md "$PLANS_DIR"/*/*/*.plan.md 2>/dev/null | head -1)
  [ -n "$_plan" ] && [ -f "$_plan" ] && PLAN_NAME="$(basename "$_plan")"
fi

# ---------- reading the turn ----------
#
# One pass, two stages. jq flattens each transcript line into at most one record
# per event we care about; awk then folds that stream, resetting at every user
# PROMPT so that what survives to END describes the LAST turn only.
#
# A user-typed entry is a PROMPT only if it carries text. The `user` type is also
# how the CLI records every TOOL RESULT, and treating those as prompts would end
# the tick's turn at its first tool call — the wall would then be permanently
# silent, passing every tick in the fleet while looking installed and green.
#
# Newlines and tabs are squashed inside values because the stream is
# line-and-tab delimited; a prompt is many lines long and would otherwise forge
# records. Nothing downstream reads a value except by substring, so squashing
# costs no fidelity.
STREAM=$(jq -Rr '
  fromjson?
  | select((.isSidechain // false) != true)
  | select((((.agentId // .agent_id) // "") | tostring) == "")
  | if .type == "user" then
      ( if (.message.content | type) == "string" then .message.content
        else ([.message.content[]? | select(.type == "text") | .text] | join(" "))
        end ) as $t
      | select(($t // "") != "")
      | "USER\t" + ($t | gsub("[\n\t\r]"; " "))
    elif .type == "assistant" then
      .message.content[]?
      | select(.type == "tool_use")
      | "TOOL\t" + (.name // "")
        + "\t" + (((.input.file_path // .input.path // .input.command // "") | tostring) | gsub("[\n\t\r]"; " "))
    else empty
    end
' "$TRANSCRIPT" 2>/dev/null) || STREAM=""
[ -n "$STREAM" ] || exit 0

# TICK / LISTAGENTS / TASKLIST, folded over the last turn.
VERDICT=$(printf '%s\n' "$STREAM" | awk -F'\t' -v plan="$PLAN_NAME" '
  $1 == "USER" {
    tick = (index($0, "session-poker.sh tick") > 0)
    la = 0; tl = 0
    next
  }
  $1 == "TOOL" {
    if ($2 == "ListAgents") { la = 1; next }
    if ($2 == "TaskList")   { tl = 1; next }
    if (plan != "" && index($3, plan) > 0) {
      if ($2 == "Edit" || $2 == "Write" || $2 == "NotebookEdit" || $2 == "Bash") tl = 1
    }
    next
  }
  END {
    if (!tick) { print "quiet"; exit }
    if (la && tl) { print "quiet"; exit }
    if (!la && !tl) { print "both"; exit }
    if (!la) { print "listagents"; exit }
    print "tasklist"
  }
')

[ "$VERDICT" = "quiet" ] && exit 0
[ -n "$VERDICT" ] || exit 0

# ---------- the refusal ----------
#
# THE REASON NAMES WHAT IS MISSING AND NOTHING ELSE. A reason that recites both
# duties whichever one was skipped makes the reader re-derive the answer the gate
# already knows, and a gate that fires on every tick with the same paragraph is
# read as noise inside two ticks. Each string is a LITERAL: no payload value and
# no path is interpolated into it, so there is no JSON-quoting surface here at
# all.
case "$VERDICT" in
  both)
    REASON='Patrol duties incomplete: no ListAgents call, and no task-list refresh — TaskList or a plan-ledger write. Do both, then stop again — this gate blocks once.' ;;
  listagents)
    REASON='Patrol duties incomplete: no ListAgents call since this Patrol tick. Refresh the subagent panel, then stop again — this gate blocks once.' ;;
  tasklist)
    REASON='Patrol duties incomplete: no task-list refresh since this Patrol tick — TaskList or a plan-ledger write. Do one, then stop again — this gate blocks once.' ;;
  *)
    exit 0 ;;
esac

# The JSON decision payload on STDOUT with exit 0, the form Design (T5) names.
# (hooks/landing-gate.sh refuses through exit 2 + stderr instead; both are live
# Stop-hook block channels in this CLI, and the two gates deliberately do not
# share a mechanism they never share a code path with.)
jq -nc --arg r "$REASON" '{decision:"block",reason:$r}'
exit 0
