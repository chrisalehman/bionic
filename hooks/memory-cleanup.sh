#!/bin/bash
# AUTO-CLEANUP: Scans .bionic/memory/ for two kinds of problems and
# injects an advisory additionalContext for Claude on SessionStart.
#
#   1. Stale topical files — <topic>.md with `updated:` frontmatter
#      older than 30 days.
#   2. Oversized index / journal — INDEX.md > 30 Always Apply rules
#      or > 5 KB; context.md > 500 lines or > 50 KB.
# [INSTRUMENT]
#
# INDEX.md and context.md are never considered "stale" by the date
# check — only topical files are date-aged. They are subject to the
# size check.
# [INSTRUMENT]
#
# When anything is flagged, emits hookSpecificOutput.additionalContext
# so Claude picks up the recommendation silently at session start.
# Advisory only — NEVER blocks. When nothing trips, exits silently.
# [INSTRUMENT]
#
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

set -u

INPUT=$(cat)

# Resolve the project directory. CLAUDE_PROJECT_DIR is the canonical
# source; fall back to the hook input's cwd field.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR=$(echo "$INPUT" | jq -r '.cwd // empty')
fi
if [ -z "$PROJECT_DIR" ]; then
  exit 0
fi

MEMORY_DIR="${PROJECT_DIR}/.bionic/memory"
if [ ! -d "$MEMORY_DIR" ]; then
  exit 0
fi

# Cross-platform epoch conversion for YYYY-MM-DD dates.
# Returns 0 (treated as missing/unknown) on parse failure.
date_to_epoch() {
  local date_str="$1"
  if [ "$(uname)" = "Darwin" ]; then
    date -j -f "%Y-%m-%d" "$date_str" +%s 2>/dev/null || echo 0
  else
    date -d "$date_str" +%s 2>/dev/null || echo 0
  fi
}

NOW_EPOCH=$(date +%s)
THIRTY_DAYS=2592000  # 30 * 86400

STALE_LIST=""
for file in "$MEMORY_DIR"/*.md; do
  [ -f "$file" ] || continue
  base=$(basename "$file")

  # INDEX.md and context.md never expire per the protocol. [INSTRUMENT]
  [ "$base" = "INDEX.md" ] && continue
  [ "$base" = "context.md" ] && continue

  # Extract the first `updated:` value from the YAML frontmatter.
  # Frontmatter is delimited by lines containing only "---" at file start.
  updated=$(awk '
    BEGIN { inside = 0; lines = 0 }
    /^---[[:space:]]*$/ {
      if (inside == 0 && lines == 0) { inside = 1; lines++; next }
      if (inside == 1) { exit }
    }
    inside == 1 && /^updated:[[:space:]]*/ {
      sub(/^updated:[[:space:]]*/, "")
      sub(/[[:space:]]*$/, "")
      # Strip surrounding quotes if present
      gsub(/^["'\'']|["'\'']$/, "")
      print
      exit
    }
    { lines++ }
  ' "$file")

  [ -z "$updated" ] && continue

  file_epoch=$(date_to_epoch "$updated")
  [ "${file_epoch:-0}" -eq 0 ] && continue

  age=$((NOW_EPOCH - file_epoch))
  if [ "$age" -gt "$THIRTY_DAYS" ]; then
    age_days=$((age / 86400))
    STALE_LIST="${STALE_LIST}- ${base} (${age_days} days since last update)
"
  fi
done

# ---- Size audit ----
#
# Thresholds (in sync with commands/memory-compact.md):
#   INDEX.md     — > 30 Always Apply rules OR > 5 KB
#   context.md   — > 500 lines OR > 50 KB
# [INSTRUMENT]
INDEX_FILE="$MEMORY_DIR/INDEX.md"
CONTEXT_FILE="$MEMORY_DIR/context.md"

SIZE_LIST=""

# Cross-platform byte size for a regular file. Echoes 0 on missing.
file_bytes() {
  local f="$1"
  [ -f "$f" ] || { echo 0; return; }
  if [ "$(uname)" = "Darwin" ]; then
    stat -f%z "$f" 2>/dev/null || echo 0
  else
    stat -c%s "$f" 2>/dev/null || echo 0
  fi
}

if [ -f "$INDEX_FILE" ]; then
  index_bytes=$(file_bytes "$INDEX_FILE")
  index_lines=$(wc -l < "$INDEX_FILE" | tr -d ' ')
  # Count Always Apply bullets: top-level "- " lines that fall under the
  # Always Apply heading, before the next "## " heading. We approximate
  # by counting any line that begins with "- " in the file — the typical
  # INDEX.md is dominated by Always Apply bullets, and Deep Context
  # pointers count toward the rule budget too (both are bullets).
  # [INSTRUMENT]
  index_bullets=$(grep -c '^- ' "$INDEX_FILE" 2>/dev/null || echo 0)
  index_bullets=${index_bullets//[!0-9]/}
  : "${index_bullets:=0}"

  if [ "$index_bullets" -gt 30 ] || [ "$index_bytes" -gt 5120 ]; then
    SIZE_LIST="${SIZE_LIST}- INDEX.md (${index_bullets} bullets, ${index_bytes} bytes — threshold: 30 rules / 5KB)
"
  fi
fi

if [ -f "$CONTEXT_FILE" ]; then
  context_bytes=$(file_bytes "$CONTEXT_FILE")
  context_lines=$(wc -l < "$CONTEXT_FILE" | tr -d ' ')
  if [ "$context_lines" -gt 500 ] || [ "$context_bytes" -gt 51200 ]; then
    SIZE_LIST="${SIZE_LIST}- context.md (${context_lines} lines, ${context_bytes} bytes — threshold: 500 lines / 50KB)
"
  fi
fi

# If nothing tripped, exit silently (preserve existing behavior).
if [ -z "$STALE_LIST" ] && [ -z "$SIZE_LIST" ]; then
  exit 0
fi

# Build the advisory message. Sections only appear when their list is non-empty.
CONTEXT="Memory auto-cleanup advisory (.bionic/memory/):"

if [ -n "$STALE_LIST" ]; then
  CONTEXT="${CONTEXT}

Stale topical files (past 30-day freshness window):
${STALE_LIST}"
fi

if [ -n "$SIZE_LIST" ]; then
  CONTEXT="${CONTEXT}

Oversized files — run \`/memory-compact\` to compact:
${SIZE_LIST}"
fi

CONTEXT="${CONTEXT}
Recommendation:
- For stale files: verify each against the current codebase. If still accurate, bump \`updated:\`. Otherwise rewrite or delete.
- For oversized files: invoke \`/memory-compact\` to migrate Always Apply bullets into topical files and rotate older sessions out of context.md.
- Skip files the user's task will naturally touch — those will get updated during the work.

Advisory only. Keep tidying fast — this is not redesign."

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
exit 0
