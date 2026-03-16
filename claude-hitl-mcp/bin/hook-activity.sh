#!/bin/bash
# Post-tool-use hook: report activity to HITL listener
command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)
sid=$(echo "$input" | jq -r '.session_id // empty') || exit 0
tool=$(echo "$input" | jq -r '.tool_name // empty') || exit 0
[ -z "$sid" ] || [ -z "$tool" ] && exit 0
cwd=$(echo "$input" | jq -r '.cwd // empty')
SOCK="${CLAUDE_HITL_SOCKET:-$HOME/.claude-hitl/sock}"
jq -nc --arg sid "$sid" --arg tool "$tool" --arg cwd "${cwd:-}" \
  'if $cwd == "" then {type:"activity", sessionId:$sid, toolName:$tool}
   else {type:"activity", sessionId:$sid, toolName:$tool, cwd:$cwd} end' \
  | nc -U "$SOCK" 2>/dev/null
exit 0
