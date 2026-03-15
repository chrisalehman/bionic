#!/bin/bash
# Warns before pushes to main/master branches.
# Requires user confirmation via the permission prompt.
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

if echo "$COMMAND" | grep -qE 'git push.*(main|master)|git push\s*$|git push -f'; then
  echo "⚠ Push to main/master detected. Confirm you have explicit user permission." >&2
  exit 0
fi

exit 0
