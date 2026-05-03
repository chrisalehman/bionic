#!/bin/bash
# migrate-frontmatter.sh — grandfather existing canonical-sdlc plan/spec/adr
# documents into v1 by adding three frontmatter fields if missing:
#
#   canonical_sdlc_version: 1
#   evidence_schema: legacy
#   created: <YYYY-MM-DD>
#
# Idempotent: a file with all three fields already present is a no-op.
# Files without YAML frontmatter, or whose basename does not match the
# canonical-sdlc artifact patterns (the same patterns enforced by
# hooks/canonical-sdlc-governing-skill.sh), are left unchanged.
#
# Usage:
#   migrate-frontmatter.sh <path> [<path> ...]
#
# Each <path> is a single markdown file. Globbing is the caller's job.
# Non-matching paths are silently skipped (exit 0 for the run).
#
# Environment:
#   MIGRATE_TODAY=YYYY-MM-DD   override the inserted `created:` date
#                              (defaults to `date +%Y-%m-%d`).
#
# Why this script exists: see canonical-sdlc-autonomous-redesign.md §1.2.3
# and §4.3. Wave 1a of the redesign execution plan.

set -uo pipefail

TODAY="${MIGRATE_TODAY:-$(date +%Y-%m-%d)}"

# Match the same artifact patterns as canonical-sdlc-governing-skill.sh.
is_enforced_basename() {
  case "$1" in
    *.plan.md|*.spec.md|continuation*.md) return 0 ;;
    adr-*.md) return 0 ;;
    *) return 1 ;;
  esac
}

# Print 0 if the frontmatter (everything between the first two `---`
# lines) does NOT contain a top-level `<field>:` assignment, 1 if it
# does. Used to decide whether each migrated field needs to be added.
has_field() {
  local frontmatter="$1" field="$2"
  echo "$frontmatter" \
    | grep -qE "^[[:space:]]*${field}[[:space:]]*:" \
    && return 0
  return 1
}

migrate_file() {
  local file="$1"

  if [ ! -f "$file" ]; then
    echo "skip: not a file: $file" >&2
    return 0
  fi

  local base
  base=$(basename "$file")
  if ! is_enforced_basename "$base"; then
    return 0
  fi

  # Frontmatter must start on line 1 with a literal `---`.
  local first_line
  first_line=$(head -n 1 "$file")
  if [ "$first_line" != "---" ]; then
    echo "skip: no frontmatter: $file" >&2
    return 0
  fi

  # Closing delimiter line number (the second `---` at column 0).
  local close_line
  close_line=$(awk 'NR>1 && $0=="---" {print NR; exit}' "$file")
  if [ -z "$close_line" ]; then
    echo "skip: unterminated frontmatter: $file" >&2
    return 0
  fi

  # Body of the frontmatter (between the two delimiters), used only to
  # check for existing fields.
  local frontmatter
  frontmatter=$(sed -n "2,$((close_line - 1))p" "$file")

  # Compute the lines to insert. Order is fixed for stable diffs.
  local additions=""
  if ! has_field "$frontmatter" "canonical_sdlc_version"; then
    additions+="canonical_sdlc_version: 1"$'\n'
  fi
  if ! has_field "$frontmatter" "evidence_schema"; then
    additions+="evidence_schema: legacy"$'\n'
  fi
  if ! has_field "$frontmatter" "created"; then
    additions+="created: ${TODAY}"$'\n'
  fi

  # All three already present → no-op.
  if [ -z "$additions" ]; then
    return 0
  fi

  # Splice the additions in just before the closing `---`. Atomic
  # rewrite via temp file to avoid partial writes on interruption.
  local tmp
  tmp=$(mktemp)
  {
    head -n "$((close_line - 1))" "$file"
    printf '%s' "$additions"
    tail -n "+${close_line}" "$file"
  } > "$tmp"
  mv "$tmp" "$file"
}

if [ "$#" -eq 0 ]; then
  echo "usage: $(basename "$0") <path> [<path> ...]" >&2
  exit 64
fi

for path in "$@"; do
  migrate_file "$path"
done

exit 0
