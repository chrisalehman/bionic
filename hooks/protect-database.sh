#!/bin/bash
# HARD BLOCK: Prevents AI from running destructive database operations.
# Exit code 2 = block the tool call entirely in Claude Code hooks.
# Catches DROP, TRUNCATE, DELETE without WHERE, and ALTER TABLE...DROP
# via psql, mysql, sqlite3, and other common DB CLIs.
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check Bash commands
[ -z "$COMMAND" ] && exit 0

# Uppercase for case-insensitive matching
CMD_UPPER=$(echo "$COMMAND" | tr '[:lower:]' '[:upper:]')

# Check if this involves a database CLI
if echo "$COMMAND" | grep -qEi '(psql|mysql|sqlite3|mongosh|mongo |clickhouse-client|cqlsh|cockroach sql|pg_|mariadb)\b'; then

  # DROP TABLE / DROP DATABASE / DROP SCHEMA / DROP INDEX
  if echo "$CMD_UPPER" | grep -qE 'DROP\s+(TABLE|DATABASE|SCHEMA|INDEX|COLLECTION)'; then
    echo "BLOCKED: Destructive database operation (DROP) detected." >&2
    echo "Run destructive migrations manually from your terminal." >&2
    exit 2
  fi

  # TRUNCATE
  if echo "$CMD_UPPER" | grep -qE 'TRUNCATE\s'; then
    echo "BLOCKED: Destructive database operation (TRUNCATE) detected." >&2
    echo "Run destructive migrations manually from your terminal." >&2
    exit 2
  fi

  # DELETE without WHERE (mass delete)
  if echo "$CMD_UPPER" | grep -qE 'DELETE\s+FROM\s' && ! echo "$CMD_UPPER" | grep -qE 'DELETE\s+FROM\s+\S+\s+WHERE\s'; then
    echo "BLOCKED: DELETE without WHERE clause detected." >&2
    echo "Run destructive operations manually from your terminal." >&2
    exit 2
  fi

  # ALTER TABLE ... DROP COLUMN
  if echo "$CMD_UPPER" | grep -qE 'ALTER\s+TABLE\s+.*DROP\s'; then
    echo "BLOCKED: Destructive ALTER TABLE (DROP) detected." >&2
    echo "Run destructive migrations manually from your terminal." >&2
    exit 2
  fi
fi

# Also catch raw SQL piped or passed inline (e.g., echo "DROP TABLE..." | psql)
if echo "$CMD_UPPER" | grep -qE '(DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s)' && echo "$COMMAND" | grep -qEi '(\|\s*(psql|mysql|sqlite3|mongosh)|<< )'; then
  echo "BLOCKED: Destructive SQL piped to database client." >&2
  echo "Run destructive migrations manually from your terminal." >&2
  exit 2
fi

exit 0
