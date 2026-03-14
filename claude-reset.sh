#!/usr/bin/env bash
#
# claude-reset.sh
# Removes Claude Code plugins and skills installed by claude-bootstrap.sh.
# Idempotent — safe to run multiple times; produces the same result.
# Requires: claude CLI (brew install claude-code)
#
# Usage:
#   bash claude-reset.sh          # prompt before removal
#   bash claude-reset.sh --all    # remove everything without prompting
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${SCRIPT_DIR}/claude-config.txt"

# ─── Options ─────────────────────────────────────────────────────────────────

REMOVE_ALL=false
if [[ "${1:-}" == "--all" ]]; then
  REMOVE_ALL=true
fi

if ! $REMOVE_ALL; then
  read -rp "Remove all installed plugins and skills? [y/N] " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    REMOVE_ALL=true
  fi
fi

# ─── Prerequisite checks ────────────────────────────────────────────────────

if ! command -v claude &>/dev/null; then
  echo "ERROR: 'claude' not found. Install with: brew install claude-code" >&2
  exit 1
fi

# ─── Config reader ──────────────────────────────────────────────────────────

read_config() {
  local type="$1" callback="$2"
  while IFS='|' read -r entry_type f1 f2; do
    entry_type="$(echo "$entry_type" | xargs)"
    [ "$entry_type" = "$type" ] || continue
    f1="$(echo "$f1" | xargs)"
    f2="$(echo "${f2:-}" | xargs)"
    "$callback" "$f1" "$f2"
  done < <(grep -v '^\s*#' "$CONFIG" | grep -v '^\s*$')
}

# ─── Helpers ─────────────────────────────────────────────────────────────────

confirm() {
  if $REMOVE_ALL; then return 0; fi
  read -rp "  Remove $1? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

do_remove_skill() {
  local name="$1"
  if ! confirm "${name}"; then
    echo "  ${name} — skipped"
    return 0
  fi
  echo -n "  ${name}... "
  if [ -d ~/.claude/skills/"${name}" ]; then
    rm -rf ~/.claude/skills/"${name}"
    echo "✓"
  else
    echo "✓ (already removed)"
  fi
}

do_remove_plugin() {
  local plugin="$1" source="$2"
  if ! confirm "${plugin} (${source})"; then
    echo "  ${plugin} — skipped"
    return 0
  fi
  echo -n "  ${plugin} (${source})... "
  claude plugin uninstall "${plugin}@${source}" 2>/dev/null && echo "✓" || echo "✓ (already removed)"
}

do_remove_marketplace() {
  local name="$1"
  if ! confirm "${name}"; then
    echo "  ${name} — skipped"
    return 0
  fi
  echo -n "  ${name}... "
  claude plugin marketplace remove "$name" 2>/dev/null && echo "✓" || echo "✓ (already removed)"
}

do_remove_global_memory() {
  local file="$1"
  local target=~/.claude/CLAUDE.md
  local start_marker="<!-- claude-setup:start -->"
  local end_marker="<!-- claude-setup:end -->"

  if ! confirm "global memory (${file})"; then
    echo "  global memory — skipped"
    return 0
  fi

  echo -n "  ~/.claude/CLAUDE.md... "

  if [ ! -f "$target" ]; then
    echo "✓ (already removed)"
    return 0
  fi

  if ! grep -q "$start_marker" "$target"; then
    echo "✓ (no managed section)"
    return 0
  fi

  # Remove managed section using awk
  awk -v start="$start_marker" -v end="$end_marker" '
    $0 == start { skip=1; next }
    $0 == end { skip=0; next }
    !skip { print }
  ' "$target" > "${target}.tmp" && mv "${target}.tmp" "$target"

  # Delete file if only whitespace remains
  if [ ! -s "$target" ] || ! grep -q '[^[:space:]]' "$target"; then
    rm -f "$target"
  fi

  echo "✓"
}

# ─── Custom Skills ──────────────────────────────────────────────────────────

echo "Custom skills:"
read_config "github-skill" do_remove_skill
echo ""

# ─── Global Memory ──────────────────────────────────────────────────────────

echo "Global memory:"
read_config "global-memory" do_remove_global_memory
echo ""

# ─── Plugins ────────────────────────────────────────────────────────────────

echo "Plugins:"
read_config "plugin" do_remove_plugin
echo ""

# ─── Marketplaces ───────────────────────────────────────────────────────────

echo "Marketplaces:"
read_config "marketplace" do_remove_marketplace
echo ""

# ─── Verification ───────────────────────────────────────────────────────────

echo "Verification:"

echo ""
echo "  Plugins (official skills):"
plugin_output="$(claude plugin list 2>&1)"
if echo "$plugin_output" | grep -q "No plugins"; then
  echo "    (none installed) ✓"
else
  echo "$plugin_output" | while IFS= read -r line; do echo "    $line"; done
fi

echo ""
echo "  Custom skills:"
if [ -d ~/.claude/skills ] && [ "$(ls -A ~/.claude/skills 2>/dev/null)" ]; then
  for skill_dir in ~/.claude/skills/*/; do
    [ -d "$skill_dir" ] || continue
    echo "    $(basename "$skill_dir") — still present"
  done
else
  echo "    (none installed) ✓"
fi

echo ""
echo "  Global memory:"
if [ -f ~/.claude/CLAUDE.md ] && grep -q "<!-- claude-setup:start -->" ~/.claude/CLAUDE.md; then
  echo "    ~/.claude/CLAUDE.md — managed section still present"
else
  echo "    ~/.claude/CLAUDE.md ✓ (clean)"
fi

echo "" ; echo "Done"
