#!/usr/bin/env bash
#
# claude-reset.sh
# Removes Claude Code plugins and skills installed by claude-bootstrap.sh.
# Idempotent — safe to run multiple times; produces the same result.
# Requires: claude CLI + Homebrew (macOS or Linux/WSL)
#
# Usage:
#   bash claude-reset.sh                                   # prompt before removal
#   bash claude-reset.sh --all                             # remove everything without prompting
#   bash claude-reset.sh [--all] claude-config.everything.txt   # core + profile(s)
#
# Profile files mirror claude-bootstrap.sh: core (claude-config.txt) always
# applies; positional args add profile files so resets stay symmetric with
# installs.
#
# shellcheck disable=SC2088  # literal "~/" in note_*/LEFTOVERS strings is display text, not paths
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILES=("${SCRIPT_DIR}/claude-config.txt")

# ─── Platform Detection ─────────────────────────────────────────────────────

source "${SCRIPT_DIR}/lib/platform.sh"

cleanup() { rm -f ~/.claude/settings.json.tmp ~/.claude/CLAUDE.md.tmp "${SHELL_RC}.tmp"; }
trap cleanup EXIT

# ─── Options ─────────────────────────────────────────────────────────────────

usage() {
  cat <<'USAGE'
claude-reset.sh — remove what claude-bootstrap.sh installed.

Usage:
  ./claude-reset.sh [--all] [profile-config.txt ...]

  ./claude-reset.sh                                    # prompt per item
  ./claude-reset.sh --all                              # remove everything, no prompts
  ./claude-reset.sh --all claude-config.everything.txt # core + profile entries

Pass the same profile files you bootstrapped with so profile-only entries
(extra npm/uv tools, MCP servers) are removed too. Deliberately left in
place: brew formulae/casks, the pnpm store, Homebrew, node, and the claude
CLI itself. Restore anytime with ./claude-bootstrap.sh.
USAGE
}

REMOVE_ALL=false
for arg in "$@"; do
  if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
    usage; exit 0
  elif [[ "$arg" == "--all" ]]; then
    REMOVE_ALL=true
  elif [ -f "$arg" ]; then
    CONFIG_FILES+=("$arg")
  else
    echo "ERROR: profile file not found: ${arg}" >&2
    echo "Run ./claude-reset.sh --help for usage." >&2
    exit 2
  fi
done

if ! $REMOVE_ALL; then
  read -rp "Remove all installed plugins and skills? [y/N] " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    REMOVE_ALL=true
  fi
fi

# ─── Prerequisite checks ────────────────────────────────────────────────────

if ! command -v claude &>/dev/null; then
  echo "ERROR: 'claude' not found. Install with: npm install -g @anthropic-ai/claude-code@latest" >&2
  exit 1
fi

# ─── Outcome records (for the final report) ─────────────────────────────────
# Every removal step notes its outcome: removed (did work), clean (nothing to
# do), or skipped (user declined). Verification appends anything still present
# to LEFTOVERS. Records are "group|item" — group drives report aggregation.

START_TS="$(date +%s)"
REMOVED=()
CLEAN=()
SKIPPED=()
LEFTOVERS=()
note_removed() { REMOVED+=("$1|$2"); }
note_clean()   { CLEAN+=("$1|$2"); }
note_skipped() { SKIPPED+=("$1|$2"); }

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_YELLOW=""; C_RED=""; C_BOLD=""; C_RESET=""
fi

# ─── Config reader ──────────────────────────────────────────────────────────
# callback receives: field1 field2 field3 (trimmed, pipe-delimited; f2 and f3 may be empty)

read_config() {
  local type="$1" callback="$2"
  while IFS='|' read -r entry_type f1 f2 f3; do
    entry_type="$(echo "$entry_type" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ "$entry_type" = "$type" ] || continue
    f1="$(echo "$f1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    f2="$(echo "${f2:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    f3="$(echo "${f3:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    "$callback" "$f1" "$f2" "$f3" </dev/null
  done < <(cat "${CONFIG_FILES[@]}" | grep -v '^\s*#' | grep -v '^\s*$' | awk '!seen[$0]++')
}

# ─── Helpers ─────────────────────────────────────────────────────────────────

# Prompts read from /dev/tty, not stdin: callbacks run inside read_config's
# while-read loop, where stdin is the config stream (and is detached anyway) —
# reading it would consume config lines as answers.
confirm() {
  if $REMOVE_ALL; then return 0; fi
  local answer
  if ! read -rp "  Remove $1? [y/N] " answer </dev/tty 2>/dev/null; then
    return 1
  fi
  [[ "$answer" =~ ^[Yy]$ ]]
}

do_remove_skill() {
  local name="$1"
  if ! confirm "${name}"; then
    echo "  ${name} — skipped"
    note_skipped "Skills" "$name"
    return 0
  fi
  echo -n "  ${name}... "
  if [ -d ~/.claude/skills/"${name}" ]; then
    rm -rf ~/.claude/skills/"${name}"
    echo "✓"
    note_removed "Skills" "$name"
  else
    echo "✓ (already removed)"
    note_clean "Skills" "$name"
  fi
}

do_remove_command() {
  local name="$1"
  if ! confirm "/${name}"; then
    echo "  /${name} — skipped"
    note_skipped "Commands" "/${name}"
    return 0
  fi
  echo -n "  /${name}... "
  if [ -f ~/.claude/commands/"${name}.md" ]; then
    rm -f ~/.claude/commands/"${name}.md"
    echo "✓"
    note_removed "Commands" "/${name}"
  else
    echo "✓ (already removed)"
    note_clean "Commands" "/${name}"
  fi
}

do_remove_github_skill_pack() {
  local name="$1" repo="$2"
  if ! confirm "${name} (all skills from ${repo})"; then
    echo "  ${name} — skipped"
    note_skipped "Skills" "${name} (pack)"
    return 0
  fi
  echo -n "  ${name} (${repo})... "
  # Preferred path: the manifest bootstrap wrote at install time — removes
  # exactly what was installed, no network needed.
  local manifest=~/.claude/skills/.pack-${name}.manifest
  if [ -f "$manifest" ]; then
    local count=0 skill_name
    while IFS= read -r skill_name; do
      [ -n "$skill_name" ] || continue
      rm -rf ~/.claude/skills/"${skill_name}"
      count=$((count + 1))
    done < "$manifest"
    rm -f "$manifest"
    echo "✓ (${count} skills removed via manifest)"
    note_removed "Skills" "${name} pack (${count} skills)"
  else
    # Fallback for packs installed before manifests existed: re-clone to
    # enumerate the pack's skills.
    local tmp="/tmp/claude-skill-pack-${name}"
    rm -rf "$tmp"
    if git clone --depth 1 --quiet "https://github.com/${repo}.git" "$tmp" 2>/dev/null; then
      local count=0
      for skill_dir in "$tmp"/.claude/skills/*/; do
        [ -d "$skill_dir" ] || continue
        local skill_name
        skill_name="$(basename "$skill_dir")"
        rm -rf ~/.claude/skills/"${skill_name}"
        count=$((count + 1))
      done
      rm -rf "$tmp"
      echo "✓ (${count} skills removed)"
      note_removed "Skills" "${name} pack (${count} skills)"
    else
      echo "⚠ (no manifest and cannot fetch skill list — remove ~/.claude/skills/ entries manually)"
      LEFTOVERS+=("${name} pack skills — no manifest and offline; remove ~/.claude/skills/ entries manually")
    fi
  fi
  # Clean up old project-local artifacts from npx-skill era
  rm -rf "${SCRIPT_DIR}/.agents" "${SCRIPT_DIR}/.kiro" "${SCRIPT_DIR}/skills-lock.json" "${SCRIPT_DIR}/.claude/skills"
}

do_remove_plugin() {
  local plugin="$1" source="$2"
  if ! confirm "${plugin} (${source})"; then
    echo "  ${plugin} — skipped"
    note_skipped "Plugins" "${plugin}@${source}"
    return 0
  fi
  echo -n "  ${plugin} (${source})... "
  if claude plugin uninstall "${plugin}@${source}" &>/dev/null; then
    echo "✓"
    note_removed "Plugins" "${plugin}@${source}"
  else
    echo "✓ (already removed)"
    note_clean "Plugins" "${plugin}@${source}"
  fi
}

do_remove_marketplace() {
  local name="$1"
  if ! confirm "${name}"; then
    echo "  ${name} — skipped"
    note_skipped "Marketplaces" "$name"
    return 0
  fi
  echo -n "  ${name}... "
  if claude plugin marketplace remove "$name" &>/dev/null; then
    echo "✓"
    note_removed "Marketplaces" "$name"
  else
    echo "✓ (already removed)"
    note_clean "Marketplaces" "$name"
  fi
}

do_remove_global_memory() {
  local file="$1"
  local target=~/.claude/CLAUDE.md
  local start_marker="<!-- bionic:start -->"
  local end_marker="<!-- bionic:end -->"

  if ! confirm "global memory (${file})"; then
    echo "  global memory — skipped"
    note_skipped "Global memory" "~/.claude/CLAUDE.md"
    return 0
  fi

  echo -n "  ~/.claude/CLAUDE.md... "

  if [ ! -f "$target" ]; then
    echo "✓ (already removed)"
    note_clean "Global memory" "~/.claude/CLAUDE.md"
    return 0
  fi

  if ! grep -q "$start_marker" "$target"; then
    echo "✓ (no managed section)"
    note_clean "Global memory" "~/.claude/CLAUDE.md"
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
  note_removed "Global memory" "managed section in ~/.claude/CLAUDE.md"
}

do_clean_local_package() {
  local pkg="$1"
  local pkg_dir="${SCRIPT_DIR}/${pkg}"

  # Only clean if the directory has a package.json (it's a local Node package)
  [ -f "${pkg_dir}/package.json" ] || return 0

  if ! confirm "local package build artifacts: ${pkg}"; then
    echo "  ${pkg} — skipped"
    note_skipped "Local packages" "$pkg"
    return 0
  fi

  echo -n "  ${pkg} (node_modules/ and dist/)... "
  local removed=0
  if [ -d "${pkg_dir}/node_modules" ]; then
    rm -rf "${pkg_dir}/node_modules"
    removed=$((removed + 1))
  fi
  if [ -d "${pkg_dir}/dist" ]; then
    rm -rf "${pkg_dir}/dist"
    removed=$((removed + 1))
  fi
  if [ "$removed" -gt 0 ]; then
    echo "✓"
    note_removed "Local packages" "$pkg"
  else
    echo "✓ (already removed)"
    note_clean "Local packages" "$pkg"
  fi
}

do_remove_mcp_server() {
  local name="$1"
  # $2 (pkg) and $3 (env_vars) are unused — removal only needs the name.

  if ! confirm "MCP server: ${name}"; then
    echo "  ${name} — skipped"
    note_skipped "MCP servers" "$name"
    return 0
  fi

  echo -n "  ${name}... "

  if ! claude mcp get "$name" &>/dev/null; then
    echo "✓ (already removed)"
    note_clean "MCP servers" "$name"
    return 0
  fi

  if claude mcp remove "$name" -s user &>/dev/null; then
    echo "✓"
    note_removed "MCP servers" "$name"
  else
    echo "✓ (already removed)"
    note_clean "MCP servers" "$name"
  fi
}

do_remove_npm_global() {
  local pkg="$1"
  if ! confirm "CLI tool: ${pkg}"; then
    echo "  ${pkg} — skipped"
    note_skipped "CLI tools (npm)" "$pkg"
    return 0
  fi
  echo -n "  ${pkg}... "
  if npm list -g --depth=0 "$pkg" &>/dev/null; then
    npm uninstall -g "$pkg" --silent 2>/dev/null
    echo "✓"
    note_removed "CLI tools (npm)" "$pkg"
  else
    echo "✓ (already removed)"
    note_clean "CLI tools (npm)" "$pkg"
  fi
}

do_remove_uv_tool() {
  local pkg="$1" binary="${2:-$1}"
  if ! confirm "uv tool: ${pkg}"; then
    echo "  ${pkg} — skipped"
    note_skipped "CLI tools (uv)" "$pkg"
    return 0
  fi
  echo -n "  ${pkg}... "
  if uv tool uninstall "$pkg" &>/dev/null; then
    echo "✓"
    note_removed "CLI tools (uv)" "$pkg"
  else
    echo "✓ (already removed)"
    note_clean "CLI tools (uv)" "$pkg"
  fi
}

verify_npm_global_removed() {
  local pkg="$1"
  if npm list -g --depth=0 "$pkg" &>/dev/null; then
    npm_global_found=true
    echo "    ${pkg} — still installed"
    LEFTOVERS+=("npm package ${pkg} — still installed")
  fi
}

verify_uv_tool_removed() {
  local pkg="$1" binary="${2:-$1}"
  if command -v "$binary" &>/dev/null; then
    uv_tool_found=true
    echo "    ${binary} — still installed"
    LEFTOVERS+=("uv tool ${binary} — still installed")
  fi
}

verify_mcp_removed() {
  local name="$1"
  if claude mcp get "$name" &>/dev/null; then
    mcp_found=true
    echo "    ${name} — still configured"
    LEFTOVERS+=("MCP server ${name} — still configured")
  fi
}

verify_local_package_clean() {
  local pkg="$1"
  local pkg_dir="${SCRIPT_DIR}/${pkg}"
  [ -f "${pkg_dir}/package.json" ] || return 0
  if [ -d "${pkg_dir}/node_modules" ] || [ -d "${pkg_dir}/dist" ]; then
    local_pkg_found=true
    echo "    ${pkg} — build artifacts still present"
    LEFTOVERS+=("local package ${pkg} — build artifacts still present")
  fi
}

# ─── Global Hooks ──────────────────────────────────────────────────────────

echo "Global hooks:"
if ! confirm "global hooks (~/.claude/hooks/)"; then
  echo "  hooks — skipped"
  note_skipped "Hooks" "all hooks + settings.json wiring"
else
  settings=~/.claude/settings.json
  hooks_removed=0
  # Remove the union of hooks currently in this repo's hooks/ directory and
  # hooks recorded in the install-time manifest (.bionic-manifest) — the
  # manifest attributes files orphaned by later repo renames/deletions.
  _hook_names=""
  for hook in "${SCRIPT_DIR}"/hooks/*.sh; do
    [ -f "$hook" ] || continue
    [[ "$(basename "$hook")" == *.test.sh ]] && continue
    _hook_names="${_hook_names}$(basename "$hook")"$'\n'
  done
  if [ -f ~/.claude/hooks/.bionic-manifest ]; then
    _hook_names="${_hook_names}$(cat ~/.claude/hooks/.bionic-manifest)"$'\n'
  fi
  _hook_names="$(printf '%s' "$_hook_names" | grep -v '^$' | sort -u || true)"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    echo -n "  ${name}... "
    if [ -f ~/.claude/hooks/"${name}" ]; then
      rm -f ~/.claude/hooks/"${name}"
      echo "✓"
      note_removed "Hooks" "$name"
    else
      echo "✓ (already removed)"
      note_clean "Hooks" "$name"
    fi
    hooks_removed=$((hooks_removed + 1))
    # Remove matching entries from settings.json across every hook event
    # type (PreToolUse, Stop, SessionStart, ...). Bionic-managed hooks can
    # live under any event, so we iterate rather than hardcoding PreToolUse.
    if [ -f "$settings" ] && jq -e '.hooks' "$settings" &>/dev/null; then
      # Note: uses literal ~ to match what bootstrap stored in settings.json
      # shellcheck disable=SC2088  # literal tilde is intentional — string-matches the settings.json entry
      cmd="~/.claude/hooks/${name}"
      tmp="${settings}.tmp"
      jq --arg c "$cmd" '
        .hooks |= with_entries(
          .value |= map(select(.hooks | all(.command != $c)))
        )
      ' "$settings" > "$tmp" && mv "$tmp" "$settings"
    fi
  done <<< "$_hook_names"
  rm -f ~/.claude/hooks/.bionic-manifest
  # Clean up: drop any event arrays that are now empty, then drop the
  # whole hooks object if nothing is left.
  if [ -f "$settings" ]; then
    tmp="${settings}.tmp"
    jq 'if .hooks then .hooks |= with_entries(select(.value | length > 0)) else . end' "$settings" > "$tmp" && mv "$tmp" "$settings"
    jq 'if .hooks == {} then del(.hooks) else . end' "$settings" > "$tmp" && mv "$tmp" "$settings"
  fi
  if [ "$hooks_removed" -eq 0 ]; then
    echo "  (no hooks to remove)"
  fi
fi
echo ""

# ─── Account-mirror symlinks ────────────────────────────────────────────────
# Bootstrap symlinks ~/.claude-*/settings.json and CLAUDE.md to the canonical
# ~/.claude/ copies, backing up any originals as <file>.bak-<ts>. Undo that:
# remove the symlink and restore the most recent backup.

echo "Account-mirror symlinks:"
mirror_count=0
for mirror in ~/.claude-*; do
  [ -d "$mirror" ] || continue
  account="$(basename "$mirror")"
  for f in settings.json CLAUDE.md; do
    target="${mirror}/${f}"
    [ -L "$target" ] || continue
    # Only touch links that point at the canonical ~/.claude copy.
    [ "$(readlink "$target")" = "${HOME}/.claude/${f}" ] || continue
    if ! confirm "${account}/${f} symlink"; then
      echo "  ${account}/${f} — skipped"
      note_skipped "Account mirrors" "${account}/${f}"
      continue
    fi
    echo -n "  ${account}/${f}... "
    rm -f "$target"
    latest_bak="$(ls -1 "${target}".bak-* 2>/dev/null | sort | tail -1 || true)"
    if [ -n "$latest_bak" ]; then
      mv "$latest_bak" "$target"
      echo "✓ (symlink removed, restored $(basename "$latest_bak"))"
      note_removed "Account mirrors" "${account}/${f} (backup restored)"
    else
      echo "✓ (symlink removed)"
      note_removed "Account mirrors" "${account}/${f}"
    fi
    mirror_count=$((mirror_count + 1))
  done
done
if [ "$mirror_count" -eq 0 ]; then
  echo "  (no bionic-managed symlinks found)"
fi
echo ""

# ─── Env Vars ─────────────────────────────────────────────────────────────

do_remove_env_var() {
  local key="$1" _val="$2"  # _val unused; config format requires two fields
  if ! confirm "env var: ${key}"; then
    echo "  ${key} — skipped"
    note_skipped "Settings" "env var ${key}"
    return 0
  fi
  local settings=~/.claude/settings.json
  echo -n "  ${key}... "
  if [ ! -f "$settings" ] || ! jq -e --arg k "$key" '.env[$k]' "$settings" &>/dev/null; then
    echo "✓ (already removed)"
    note_clean "Settings" "env var ${key}"
    return 0
  fi
  local tmp="${settings}.tmp"
  jq --arg k "$key" 'del(.env[$k]) | if .env == {} then del(.env) else . end' "$settings" > "$tmp" && mv "$tmp" "$settings"
  echo "✓"
  note_removed "Settings" "env var ${key}"
}

echo "Env vars:"
read_config "env-var" do_remove_env_var
echo ""

# ─── Status Line ──────────────────────────────────────────────────────────────

do_remove_statusline() {
  local _cmd="$1"
  if ! confirm "status line"; then
    echo "  status line — skipped"
    note_skipped "Settings" "status line"
    return 0
  fi
  local settings=~/.claude/settings.json
  echo -n "  status line... "
  if [ ! -f "$settings" ] || ! jq -e '.statusLine' "$settings" &>/dev/null; then
    echo "✓ (already removed)"
    note_clean "Settings" "status line"
    return 0
  fi
  local tmp="${settings}.tmp"
  jq 'del(.statusLine)' "$settings" > "$tmp" && mv "$tmp" "$settings"
  echo "✓"
  note_removed "Settings" "status line"
}

echo "Status line:"
read_config "statusline" do_remove_statusline

echo -n "  ccstatusline config... "
if ! confirm "ccstatusline config (~/.config/ccstatusline/)"; then
  echo "skipped"
  note_skipped "Settings" "ccstatusline config"
else
  if [ -d ~/.config/ccstatusline ]; then
    rm -rf ~/.config/ccstatusline
    echo "✓"
    note_removed "Settings" "ccstatusline config"
  else
    echo "✓ (already removed)"
    note_clean "Settings" "ccstatusline config"
  fi
fi
echo ""

# ─── Local Package Builds ────────────────────────────────────────────────────

echo "Local packages:"
read_config "mcp-server" do_clean_local_package
echo ""

# ─── MCP Servers ───────────────────────────────────────────────────────────

echo "MCP servers:"
read_config "mcp-server" do_remove_mcp_server
echo ""

# ─── Playwright Browsers ────────────────────────────────────────────────────

echo "Playwright browsers:"
if ! confirm "Playwright browsers (chromium)"; then
  echo "  browsers — skipped"
  note_skipped "Playwright browsers" "chromium"
else
  echo -n "  chromium... "
  if npx playwright uninstall --all 2>/dev/null; then
    echo "✓"
    note_removed "Playwright browsers" "chromium"
  elif [ -d "$PLAYWRIGHT_CACHE" ]; then
    rm -rf "$PLAYWRIGHT_CACHE"
    echo "✓ (cache removed directly)"
    note_removed "Playwright browsers" "chromium (cache removed directly)"
  else
    echo "✓ (already removed)"
    note_clean "Playwright browsers" "chromium"
  fi
fi
echo ""

# ─── CLI Tools (npm) ───────────────────────────────────────────────────────

echo "CLI tools (npm):"
read_config "npm-global" do_remove_npm_global
echo ""

# ─── CLI Tools (uv) ──────────────────────────────────────────────────────

echo "CLI tools (uv):"
read_config "uv-tool" do_remove_uv_tool
echo ""

# ─── CLI Tools (brew) ─────────────────────────────────────────────────────

echo "CLI tools (brew):"
echo "  (not removed — system-level tools may be used by other software)"
echo "  (casks likewise left in place; e.g. gcloud-cli)"
echo ""

# ─── Frontend Libraries (pnpm store) ───────────────────────────────────────

echo "Frontend libraries (pnpm store):"
echo "  (not removed — the pnpm store is a shared cache; run 'pnpm store prune' to reclaim space)"
echo ""

# ─── Custom Skills ──────────────────────────────────────────────────────────

echo "Custom skills:"
read_config "github-skill" do_remove_skill
read_config "github-skill-pack" do_remove_github_skill_pack
read_config "local-skill" do_remove_skill
echo ""

# ─── Custom Commands ────────────────────────────────────────────────────────

echo "Custom commands:"
read_config "local-command" do_remove_command
echo ""

# ─── Skill Setup ────────────────────────────────────────────────────────────

echo "Skill setup:"
echo "  excalidraw-diagram renderer — not removed separately (.venv removed with skill dir; Playwright cache removed above)"
if [ -d ~/.claude/skills/notebooklm ]; then
  echo -n "  notebooklm skill... "
  rm -rf ~/.claude/skills/notebooklm
  echo "✓"
  note_removed "Skills" "notebooklm"
else
  echo "  notebooklm skill ✓ (already removed)"
  note_clean "Skills" "notebooklm"
fi
echo ""

# ─── Global Memory ──────────────────────────────────────────────────────────

echo "Global memory:"
read_config "global-memory" do_remove_global_memory
echo ""

# ─── Shell Alias ─────────────────────────────────────────────────────────────

echo "Shell alias:"
ALIAS_RC="$SHELL_RC"
ALIAS_START="# ─── bionic:start ───"
ALIAS_END="# ─── bionic:end ───"
if ! confirm "shell alias (dangerously-skip-permissions)"; then
  echo "  shell alias — skipped"
  note_skipped "Shell alias" "~/${SHELL_RC_NAME}"
else
  echo -n "  ~/${SHELL_RC_NAME} alias... "
  if [ -f "$ALIAS_RC" ] && grep -qF "$ALIAS_START" "$ALIAS_RC"; then
    # Remove marker-delimited section
    awk -v start="$ALIAS_START" -v end="$ALIAS_END" '
      $0 == start { skip=1; next }
      $0 == end { skip=0; next }
      !skip { print }
    ' "$ALIAS_RC" > "${ALIAS_RC}.tmp" && mv "${ALIAS_RC}.tmp" "$ALIAS_RC"
    # Delete file if only whitespace remains
    if [ ! -s "$ALIAS_RC" ] || ! grep -q '[^[:space:]]' "$ALIAS_RC"; then
      rm -f "$ALIAS_RC"
    fi
    echo "✓"
    note_removed "Shell alias" "~/${SHELL_RC_NAME}"
  elif [ -f "$ALIAS_RC" ] && grep -q "alias claude=.*dangerously-skip-permissions" "$ALIAS_RC"; then
    # Fallback: remove old unmarked alias
    grep -v "alias claude=.*dangerously-skip-permissions" "$ALIAS_RC" > "${ALIAS_RC}.tmp" && mv "${ALIAS_RC}.tmp" "$ALIAS_RC"
    if [ ! -s "$ALIAS_RC" ] || ! grep -q '[^[:space:]]' "$ALIAS_RC"; then
      rm -f "$ALIAS_RC"
    fi
    echo "✓ (removed legacy unmarked alias)"
    note_removed "Shell alias" "~/${SHELL_RC_NAME} (legacy)"
  else
    echo "✓ (already removed)"
    note_clean "Shell alias" "~/${SHELL_RC_NAME}"
  fi
fi
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
    LEFTOVERS+=("skill $(basename "$skill_dir") — still present in ~/.claude/skills/")
  done
else
  echo "    (none installed) ✓"
fi

echo ""
echo "  Custom commands:"
if [ -d ~/.claude/commands ] && [ -n "$(ls -A ~/.claude/commands 2>/dev/null)" ]; then
  for cmd_file in ~/.claude/commands/*.md; do
    [ -f "$cmd_file" ] || continue
    echo "    /$(basename "$cmd_file" .md) — still present"
    LEFTOVERS+=("command /$(basename "$cmd_file" .md) — still present in ~/.claude/commands/")
  done
else
  echo "    (none installed) ✓"
fi

echo ""
echo "  Global memory:"
if [ -f ~/.claude/CLAUDE.md ] && grep -q "<!-- bionic:start -->" ~/.claude/CLAUDE.md; then
  echo "    ~/.claude/CLAUDE.md — managed section still present"
  LEFTOVERS+=("~/.claude/CLAUDE.md — managed section still present")
else
  echo "    ~/.claude/CLAUDE.md ✓ (clean)"
fi

echo ""
echo "  Shell alias:"
if [ -f "$SHELL_RC" ] && grep -qF "# ─── bionic:start ───" "$SHELL_RC"; then
  echo "    ~/${SHELL_RC_NAME} — bionic section still present"
  LEFTOVERS+=("~/${SHELL_RC_NAME} — bionic alias section still present")
elif [ -f "$SHELL_RC" ] && grep -qF "dangerously-skip-permissions" "$SHELL_RC"; then
  echo "    ~/${SHELL_RC_NAME} — legacy alias still present"
  LEFTOVERS+=("~/${SHELL_RC_NAME} — legacy alias still present")
else
  echo "    ~/${SHELL_RC_NAME} ✓ (clean)"
fi

echo ""
echo "  Global hooks:"
if [ -d ~/.claude/hooks ] && [ "$(ls -A ~/.claude/hooks 2>/dev/null)" ]; then
  for hook in ~/.claude/hooks/*; do
    echo "    $(basename "$hook") — still present"
    LEFTOVERS+=("hook $(basename "$hook") — still present in ~/.claude/hooks/")
  done
else
  echo "    (none installed) ✓"
fi

echo ""
echo "  CLI tools (npm):"
npm_global_found=false
read_config "npm-global" verify_npm_global_removed
if ! $npm_global_found; then
  echo "    (none installed) ✓"
fi

echo ""
echo "  CLI tools (uv):"
uv_tool_found=false
read_config "uv-tool" verify_uv_tool_removed
if ! $uv_tool_found; then
  echo "    (none installed) ✓"
fi

echo ""
echo "  MCP servers:"
mcp_found=false
read_config "mcp-server" verify_mcp_removed
if ! $mcp_found; then
  echo "    (all removed) ✓"
fi

echo ""
echo "  Local package builds:"
local_pkg_found=false
read_config "mcp-server" verify_local_package_clean
if ! $local_pkg_found; then
  echo "    (all clean) ✓"
fi

echo ""
echo "  Playwright browsers:"
if [ -d "$PLAYWRIGHT_CACHE" ] && [ "$(ls -A "$PLAYWRIGHT_CACHE" 2>/dev/null)" ]; then
  echo "    ${PLAYWRIGHT_CACHE} — still present"
  LEFTOVERS+=("playwright cache — still present at ${PLAYWRIGHT_CACHE}")
else
  echo "    ${PLAYWRIGHT_CACHE} ✓ (clean)"
fi

echo ""
echo "  Skill setup:"
if [ -d ~/.claude/skills/excalidraw-diagram/references/.venv ]; then
  echo "    excalidraw-diagram .venv — still present (skill dir not removed?)"
  LEFTOVERS+=("excalidraw-diagram .venv — still present (skill dir not removed?)")
else
  echo "    excalidraw-diagram .venv ✓ (clean)"
fi
if [ -f ~/.claude/skills/notebooklm/SKILL.md ]; then
  echo "    notebooklm skill — SKILL.md still present"
  LEFTOVERS+=("notebooklm skill — SKILL.md still present")
else
  echo "    notebooklm skill ✓ (clean)"
fi

# ─── Final Report ───────────────────────────────────────────────────────────

print_reset_report() {
  local rec grp item
  local n_removed=${#REMOVED[@]} n_clean=${#CLEAN[@]} n_skipped=${#SKIPPED[@]} n_left=${#LEFTOVERS[@]}
  local elapsed=$(( $(date +%s) - START_TS ))
  local mins=$((elapsed / 60)) secs=$((elapsed % 60))

  echo ""
  if [ "$n_left" -eq 0 ]; then
    echo "# ─── ${C_BOLD}Reset complete ${C_GREEN}✓${C_RESET} ─────────────────────────────────────────────"
  else
    echo "# ─── ${C_BOLD}Reset finished — leftovers present ${C_YELLOW}⚠${C_RESET} ─────────────────────"
  fi
  echo ""
  printf '  %d removed · %d already clean · %d skipped by you · %d leftovers · %dm %02ds\n' \
    "$n_removed" "$n_clean" "$n_skipped" "$n_left" "$mins" "$secs"
  echo ""

  # Removed table — one row per group, removed/total-touched counts.
  if [ $((n_removed + n_clean)) -gt 0 ]; then
    echo "  Removed"
    local groups=() g found t r
    for rec in ${REMOVED[@]+"${REMOVED[@]}"} ${CLEAN[@]+"${CLEAN[@]}"}; do
      grp="${rec%%|*}"
      found=0
      for g in ${groups[@]+"${groups[@]}"}; do
        if [ "$g" = "$grp" ]; then found=1; break; fi
      done
      [ "$found" -eq 0 ] && groups+=("$grp")
    done
    for g in ${groups[@]+"${groups[@]}"}; do
      t=0; r=0
      for rec in ${REMOVED[@]+"${REMOVED[@]}"}; do
        [ "${rec%%|*}" = "$g" ] && { t=$((t + 1)); r=$((r + 1)); }
      done
      for rec in ${CLEAN[@]+"${CLEAN[@]}"}; do
        [ "${rec%%|*}" = "$g" ] && t=$((t + 1))
      done
      if [ "$r" -gt 0 ]; then
        printf '    %b✓%b %-26s %3d removed%s\n' "$C_GREEN" "$C_RESET" "$g" "$r" "$( [ $((t - r)) -gt 0 ] && echo " ($((t - r)) already clean)" )"
      else
        printf '    %b✓%b %-26s already clean\n' "$C_GREEN" "$C_RESET" "$g"
      fi
    done
    echo ""
  fi

  # Skipped — the user's own choices, listed so nothing is silently retained.
  if [ "$n_skipped" -gt 0 ]; then
    echo "  Skipped (your choice — still installed)"
    for rec in ${SKIPPED[@]+"${SKIPPED[@]}"}; do
      grp="${rec%%|*}"; item="${rec#*|}"
      printf '    %b⚠%b %s — %s\n' "$C_YELLOW" "$C_RESET" "$grp" "$item"
    done
    echo ""
  fi

  # Leftovers — verification found these still present; action needed.
  if [ "$n_left" -gt 0 ]; then
    echo "  Leftovers (verification found these still present)"
    for item in ${LEFTOVERS[@]+"${LEFTOVERS[@]}"}; do
      printf '    %b✗%b %s\n' "$C_RED" "$C_RESET" "$item"
    done
    echo "    → re-run ./claude-reset.sh --all, or remove by hand"
    echo ""
  fi

  echo "  Left in place by design"
  echo "    • brew formulae and casks (git, node, docker, gcloud, ...) — shared system tools"
  echo "    • the pnpm store (shared cache — reclaim with: pnpm store prune)"
  echo "    • Homebrew, node, and the claude CLI itself"
  echo ""
  echo "  Next steps"
  echo "    • Restart your shell (or run: source ~/${SHELL_RC_NAME}) — the claude alias is gone"
  echo "    • Claude Code still works, without Bionic's skills, hooks, and plugins"
  echo "    • Restore everything anytime: ./claude-bootstrap.sh (idempotent)"
  echo ""
}

print_reset_report

# Exit contract: leftovers after an explicit --all run mean the reset did not
# deliver what it promised — exit 1. Interactive runs exit 0 (skips are
# expected to leave things behind).
if $REMOVE_ALL && [ "${#LEFTOVERS[@]}" -gt 0 ]; then
  exit 1
fi
