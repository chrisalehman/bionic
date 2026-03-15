#!/bin/bash
# HARD BLOCK: Prevents AI from writing to secret/credential files.
# Exit code 2 = block the tool call entirely in Claude Code hooks.
# Matches on Write, Edit, and Bash tools.
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')

# Sensitive file patterns
SECRETS_RE='\.(env|env\.[a-zA-Z0-9_]+|pem|key|p12|pfx|jks|keystore)$|credentials\.json|service.account\.json|\.aws/credentials|\.ssh/|secrets\.(ya?ml|json|toml)|\.netrc|token\.json'

case "$TOOL" in
  Write|Edit)
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    if echo "$FILE" | grep -qEi "$SECRETS_RE"; then
      echo "BLOCKED: Writing to secrets/credential file is not allowed from Claude Code." >&2
      echo "  File: $FILE" >&2
      echo "Modify secret files manually from your terminal." >&2
      exit 2
    fi
    ;;
  Bash)
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    # Check if command writes to a secrets file (redirect or tee)
    if echo "$CMD" | grep -qEi "(>|tee\s).*(\.env|credentials|\.pem|\.key|secrets\.|\.netrc|token\.json|\.aws/credentials)"; then
      echo "BLOCKED: Writing to secrets/credential file is not allowed from Claude Code." >&2
      echo "Modify secret files manually from your terminal." >&2
      exit 2
    fi
    ;;
esac

exit 0
