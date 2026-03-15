#!/bin/bash
# HARD BLOCK: Prevents AI from pushing to main/master branches.
# Exit code 2 = block the tool call entirely in Claude Code hooks.
# The user must push to main manually from their own terminal.
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

# Block any push to main/master, bare push (defaults to current branch),
# or force pushes
if echo "$COMMAND" | grep -qE 'git push.*(main|master)|git push\s*$|git push\s+-f|git push --force'; then
  echo "BLOCKED: Pushing to main/master is not allowed from Claude Code." >&2
  echo "Push to main must be done manually by the user." >&2
  exit 2
fi

exit 0
