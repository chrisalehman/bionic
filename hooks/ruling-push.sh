#!/bin/bash
# hooks/ruling-push.sh — A RULING RIDES THE WRITER'S NEXT TOOL RESULT (epic-23 wave-33 T10; REQ-1
# AC-1.1, AC-1.3; spec D1; ADR-052).
#
# Registered once in hooks/hooks.json: PostToolUse, matcher `*`, every tool, every agent. The hooks
# reference (code.claude.com/docs/en/hooks, "Matcher patterns") reads `"*"`, `""` or an omitted
# matcher as "fires on every occurrence of the event".
#
# WHAT IT DOES. A ruling the orchestrator recorded with `session-poker.sh rule <writer> '<text>'` is
# a `ruling/v1` line on the session's roster (lib/roster.sh, which owns the state). A message reaches
# a writer only at idle; this hook reaches it at its next tool call. It maps the payload's top-level
# `agent_id` to the roster name (`roster_row_for_id`, the budget wall's own join), and for each
# ruling of that name neither carried nor shown it claims the push (`ruling_push_claim`: append, then
# read which call's stamp came first, so of a writer's concurrent calls exactly one carries it) and
# prints the ruling as `hookSpecificOutput.additionalContext`, headed `bionic ruling`. PostToolUse
# additionalContext reaches a subagent's model (record/wave-33-workhorse/P1-additional-context.md,
# 2 of 2); seen is not obeyed, which is why the commit wall and `ready` guard the ruling too.
#
# WHAT IT NEVER DOES: block, or fail a tool. Every path exits 0; a library, a jq or a roster it
# cannot read is a ruling not pushed, and the guard still holds it.
#
# THE FAST PATH IS ONE FILE TEST. It runs on every tool call of every agent in every session, so
# while nothing is pending it reads no stdin and forks nothing: the session key and the project root
# come from the environment the CLI gives every hook (`CLAUDE_CODE_SESSION_ID`, `CLAUDE_PROJECT_DIR`),
# and the pending flag beside the roster (`ruling_pending_flag`) is absent. tests/hook-latency.test.sh
# §10 counts it. With either variable unset (a hand run) the payload's `session_id` and `cwd` stand in,
# the cwd through the library's root walk, which a worktree's cwd needs.
#
# RESIDUAL, NAMED: a session started below its project's root has a CLAUDE_PROJECT_DIR with no
# `.bionic` and gets no push. A call made before SubagentStart has joined the writer's id to its row
# maps to no name and gets none (spec §5). Both still meet the guard.
#
# [WALL: tests/inbox.test.sh]

_rp_sid="${CLAUDE_CODE_SESSION_ID:-}"
_rp_root="${CLAUDE_PROJECT_DIR:-}"
if [ -n "$_rp_sid" ] && [ -n "$_rp_root" ]; then
  [ -e "$_rp_root/.bionic/tmp/ruling-pending-${_rp_sid}.state" ] || exit 0
fi

# ---------- the slow path: something may be pending ----------
command -v jq >/dev/null 2>&1 || exit 0
_rp_lib="${0%/*}/../scripts/lib"
[ -r "$_rp_lib/roster.sh" ] || _rp_lib="${0%/*}/../payload/scripts/lib"
[ -r "$_rp_lib/roster.sh" ] || exit 0
# shellcheck source=/dev/null
. "$_rp_lib/roster.sh" 2>/dev/null || exit 0

_rp_in="$(cat)"
IFS="$RULING_US" read -r _rp_aid _rp_call _rp_psid _rp_cwd <<RP_PAYLOAD
$(printf '%s' "$_rp_in" | jq -r '[.agent_id // "", .tool_use_id // "", .session_id // "", .cwd // ""] | join("\u001f")' 2>/dev/null)
RP_PAYLOAD
# The orchestrator's own call carries no agent_id: it is never a ruling's writer.
[ -n "${_rp_aid:-}" ] || exit 0
[ -n "$_rp_sid" ] || _rp_sid="${_rp_psid:-}"
if [ -z "$_rp_root" ] && [ -n "${_rp_cwd:-}" ] && [ -r "$_rp_lib/root.sh" ]; then
  # shellcheck source=/dev/null
  . "$_rp_lib/root.sh" 2>/dev/null && _rp_root="$(project_root "$_rp_cwd" 2>/dev/null)"
fi
{ [ -n "$_rp_sid" ] && [ -n "$_rp_root" ]; } || exit 0
_rp_roster="$_rp_root/.bionic/tmp/roster-${_rp_sid}.state"
_rp_flag="$(ruling_pending_flag "$_rp_roster")" || exit 0
[ -e "$_rp_flag" ] || exit 0

_rp_name=""
if _rp_row="$(roster_row_for_id "$_rp_roster" "$_rp_aid")"; then
  _rp_name="$(printf '%s\n' "$_rp_row" | awk -F'|' '{ for (i = 2; i <= NF; i++) if (index($i, "name=") == 1) { print substr($i, 6); exit } }')"
fi
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && _rp_plugin="$CLAUDE_PLUGIN_ROOT" \
  || _rp_plugin="$(cd "${0%/*}/.." 2>/dev/null && pwd -P)"
[ -n "$_rp_call" ] || _rp_call="pid$$-$RANDOM"
# A ruling already shown (acknowledged, or printed by a guard) is read, so it is never pushed.
_rp_ctx=""
while IFS="$RULING_US" read -r _rp_id _rp_w _rp_rec _rp_p _rp_c _rp_s _rp_b _rp_t; do
  [ -n "$_rp_id" ] && [ -z "$_rp_p" ] && [ -z "$_rp_s" ] || continue
  [ -n "$_rp_name" ] && [ "$_rp_w" = "$_rp_name" ] || continue
  ruling_push_claim "$_rp_roster" "$_rp_id" "$_rp_w" "$_rp_call" || continue
  _rp_ctx="${_rp_ctx:+$_rp_ctx
}$(ruling_render "$_rp_id" "$_rp_t" "$_rp_plugin")"
done <<RP_FOLD
$(ruling_fold "$_rp_roster")
RP_FOLD
# The flag stays up only while a ruling of some writer is still pending after these claims.
ruling_flag_settle "$_rp_roster"
[ -n "$_rp_ctx" ] || exit 0
jq -nc --arg c "$_rp_ctx" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}' 2>/dev/null
exit 0
