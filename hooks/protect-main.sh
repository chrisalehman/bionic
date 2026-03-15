#!/bin/bash
# Blocks direct pushes to main/master branches.
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

if echo "$COMMAND" | grep -qE 'git push.*(main|master)|git push\s*$|git push -f'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Direct pushes to main/master are blocked. Ask the user for explicit permission first."
    }
  }'
  exit 0
fi

exit 0
