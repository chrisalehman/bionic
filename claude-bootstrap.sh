#!/usr/bin/env bash
#
# claude-bootstrap.sh
# Sets up Claude Code plugins, skills, and dependencies.
# Idempotent — safe to run multiple times; produces the same result.
# Requires: claude CLI + Homebrew (macOS or Linux/WSL)
#
set -euo pipefail

cleanup() { rm -f ~/.claude/settings.json.tmp ~/.claude/CLAUDE.md.tmp; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${SCRIPT_DIR}/claude-config.txt"

# ─── Prerequisite checks ────────────────────────────────────────────────────

check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    echo "ERROR: '$1' not found. $2" >&2
    exit 1
  fi
}

check_cmd claude  "Install with: brew install claude-code"

# ─── Platform Detection ─────────────────────────────────────────────────────

source "${SCRIPT_DIR}/lib/platform.sh"

# ─── Homebrew ────────────────────────────────────────────────────────────────

if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Re-source to pick up the newly installed brew
  source "${SCRIPT_DIR}/lib/platform.sh"
fi

# ─── Config reader ──────────────────────────────────────────────────────────

# Reads claude-config.txt and calls a callback for each entry of a given type.
# Usage: read_config <type> <callback>
#   callback receives: field1 field2 field3 (trimmed, pipe-delimited; f2 and f3 may be empty)
read_config() {
  local type="$1" callback="$2"
  while IFS='|' read -r entry_type f1 f2 f3; do
    entry_type="$(echo "$entry_type" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ "$entry_type" = "$type" ] || continue
    f1="$(echo "$f1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    f2="$(echo "${f2:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    f3="$(echo "${f3:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    "$callback" "$f1" "$f2" "$f3"
  done < <(grep -v '^\s*#' "$CONFIG" | grep -v '^\s*$')
}

# ─── Resilience ──────────────────────────────────────────────────────────────
#
# The install phase must run to completion even when individual steps fail
# (network blips, renamed packages, registry hiccups). Each install records its
# failure into INSTALL_FAILURES and CONTINUES rather than aborting; the
# end-of-run summary reports them and sets the exit code. Network operations go
# through run_retry (exponential backoff). Genuine prerequisites (claude, brew,
# npm, uv) still hard-fail up front — those are not recoverable mid-run.

INSTALL_FAILURES=()
RETRY_MAX="${RETRY_MAX:-3}"
RUN_ERR=""

# run_retry <cmd...> — runs cmd with stdout+stderr captured into RUN_ERR,
# retrying up to RETRY_MAX times with exponential backoff (2s, 4s, 8s...).
# Returns 0 on first success, 1 if every attempt fails. Never aborts the script.
run_retry() {
  local n=1 delay=2
  while :; do
    if RUN_ERR="$("$@" 2>&1)"; then return 0; fi
    [ "$n" -ge "$RETRY_MAX" ] && return 1
    sleep "$delay"
    n=$((n + 1)); delay=$((delay * 2))
  done
}

# record_fail <message> — note a non-fatal install failure for the summary.
record_fail() { INSTALL_FAILURES+=("$1"); }

# ─── Helpers ─────────────────────────────────────────────────────────────────

ensure_cmd() {
  local cmd="$1" pkg="${2:-$1}"
  echo -n "  ${cmd}... "
  if command -v "$cmd" &>/dev/null; then
    echo "✓ (already installed)"
    return 0
  fi
  if run_retry brew install "$pkg" --quiet; then
    echo "✓"
  else
    echo "⚠ FAILED (continuing)"
    record_fail "brew ${pkg}: ${RUN_ERR}"
  fi
  return 0
}

# Installs a Homebrew *cask* (SDKs / apps not shipped as core formulae, e.g. the
# Google Cloud CLI). binary = the command it provides on PATH; token = the cask
# name. Casks need `brew install --cask`, which plain ensure_cmd cannot do.
do_install_brew_cask() {
  local binary="$1" token="${2:-$1}"
  echo -n "  ${binary} (cask: ${token})... "
  if command -v "$binary" &>/dev/null || brew list --cask "$token" &>/dev/null; then
    echo "✓ (already installed)"
    return 0
  fi
  if run_retry brew install --cask "$token" --quiet; then
    echo "✓"
  else
    echo "⚠ FAILED (continuing)"
    record_fail "brew --cask ${token}: ${RUN_ERR}"
  fi
  return 0
}

do_install_brew_dep() {
  local binary="$1" pkg="${2:-$1}"
  ensure_cmd "$binary" "$pkg"
}

do_install_npm_global() {
  local pkg="$1"
  echo -n "  ${pkg}... "
  if npm list -g --depth=0 "$pkg" &>/dev/null; then
    echo "✓ (already installed)"
    return 0
  fi
  if run_retry npm install -g "$pkg" --silent; then
    echo "✓"
  else
    echo "⚠ FAILED (continuing)"
    record_fail "npm -g ${pkg}: ${RUN_ERR}"
  fi
  return 0
}

do_install_uv_tool() {
  local pkg="$1" binary="${2:-$1}"
  echo -n "  ${pkg} (→ ${binary})... "
  if command -v "$binary" &>/dev/null; then
    echo "✓ (already installed)"
    return 0
  fi
  if run_retry uv tool install "$pkg" --quiet; then
    echo "✓"
  else
    echo "⚠ FAILED (continuing)"
    record_fail "uv tool ${pkg}: ${RUN_ERR}"
  fi
  return 0
}

# Pre-warms the pnpm content-addressable store with a frontend library so that
# `pnpm add <pkg>` in any project hard-links from the store (instant, offline).
# A library is imported per-project — the store is a shared cache, never an
# import path — so there is no global "already installed" state to check.
# Always pulls @latest so re-runs refresh the cached version.
do_install_pnpm_store() {
  local pkg="$1"
  echo -n "  ${pkg} (pnpm store)... "
  if run_retry pnpm store add "${pkg}@latest"; then
    echo "✓"
  else
    echo "⚠ FAILED (continuing)"
    record_fail "pnpm store add ${pkg}: ${RUN_ERR}"
  fi
  return 0
}

do_build_local_package() {
  local pkg="$1"
  local pkg_dir="${SCRIPT_DIR}/${pkg}"

  # Only build if the directory has a package.json (it's a local Node package)
  [ -f "${pkg_dir}/package.json" ] || return 0

  echo -n "  ${pkg} (npm install && build)... "
  (cd "$pkg_dir" && npm install --silent 2>/dev/null && npm run build --silent 2>/dev/null)
  echo "✓"
}

# Registers an MCP server via claude mcp add. If env_vars is provided (comma-separated
# list of env var names, e.g. "KEY1,KEY2"), reads their values from the current shell
# environment and passes them as -e flags. Skips with a warning if any are missing.
do_configure_mcp_server() {
  local name="$1" pkg="$2" env_vars="${3:-}"

  echo -n "  ${name} (${pkg})... "

  # Check if already configured via claude mcp
  if claude mcp get "$name" &>/dev/null; then
    echo "✓ (already configured)"
    return 0
  fi

  # Build env-var flags from comma-separated list (e.g. "TRELLO_API_KEY,TRELLO_TOKEN")
  local env_flags=()
  if [ -n "$env_vars" ]; then
    local missing=()
    IFS=',' read -ra vars <<< "$env_vars"
    for var in "${vars[@]}"; do
      var="$(echo "$var" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      local val="${!var:-}"
      if [ -z "$val" ]; then
        missing+=("$var")
      else
        env_flags+=("-e" "${var}=${val}")
      fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
      echo "⚠ skipped (set ${missing[*]} in your environment, then re-run)"
      return 0
    fi
  fi

  # Check if the package exists as a local subdirectory with a built server
  local local_server="${SCRIPT_DIR}/${pkg}/dist/server.js"

  if [ -f "$local_server" ]; then
    # Local package — resolve absolute path and register via claude mcp add
    local abs_path
    abs_path="$(cd "$(dirname "$local_server")" && pwd)/$(basename "$local_server")"

    claude mcp add "$name" -s user ${env_flags[@]+"${env_flags[@]}"} -- node "$abs_path" &>/dev/null
    echo "✓ (local)"
  else
    # Remote package — register via claude mcp add
    claude mcp add "$name" -s user ${env_flags[@]+"${env_flags[@]}"} -- npx -y "$pkg" &>/dev/null
    echo "✓"
  fi
}

do_install_marketplace() {
  local name="$1"
  echo -n "  ${name}... "
  local output
  # First attempt is also the idempotency check: an already-added marketplace
  # exits non-zero with "already" in the message — that's success, not a retry.
  if output=$(claude plugin marketplace add "$name" 2>&1); then
    echo "✓"
    return 0
  fi
  if echo "$output" | grep -qi "already"; then
    echo "✓ (already added)"
    return 0
  fi
  # Genuine failure (network, auth, bad name) — retry, then record and continue.
  if run_retry claude plugin marketplace add "$name"; then
    echo "✓"
  else
    echo "⚠ FAILED (continuing)"
    record_fail "marketplace ${name}: ${RUN_ERR:-$output}"
  fi
  return 0
}

do_install_plugin() {
  local plugin="$1" source="$2"
  echo -n "  ${plugin} (${source})... "
  if claude plugin list 2>&1 | grep -q "${plugin}@${source}"; then
    echo "✓ (already installed)"
    return 0
  fi
  if run_retry claude plugin install "${plugin}@${source}"; then
    echo "✓"
  else
    echo "⚠ FAILED (continuing)"
    record_fail "plugin ${plugin}@${source}: ${RUN_ERR}"
  fi
  return 0
}

do_install_github_skill() {
  local name="$1" repo="$2"
  echo -n "  ${name} (${repo})... "
  local tmp="/tmp/claude-skill-${name}"
  rm -rf "$tmp"
  if ! run_retry git clone --depth 1 --quiet "https://github.com/${repo}.git" "$tmp"; then
    echo "⚠ FAILED (continuing)"
    record_fail "github-skill ${name} (${repo}): ${RUN_ERR}"
    rm -rf "$tmp"
    return 0
  fi
  mkdir -p ~/.claude/skills
  rm -rf ~/.claude/skills/"${name}"
  cp -r "$tmp" ~/.claude/skills/"${name}" && rm -rf ~/.claude/skills/"${name}"/.git
  rm -rf "$tmp"
  echo "✓"
}

do_install_github_skill_pack() {
  local name="$1" repo="$2"
  echo -n "  ${name} (${repo})... "
  local tmp="/tmp/claude-skill-pack-${name}"
  rm -rf "$tmp"
  if ! run_retry git clone --depth 1 --quiet "https://github.com/${repo}.git" "$tmp"; then
    echo "⚠ FAILED (continuing)"
    record_fail "github-skill-pack ${name} (${repo}): ${RUN_ERR}"
    rm -rf "$tmp"
    return 0
  fi
  mkdir -p ~/.claude/skills
  local count=0
  for skill_dir in "$tmp"/.claude/skills/*/; do
    [ -d "$skill_dir" ] || continue
    local skill_name
    skill_name="$(basename "$skill_dir")"
    rm -rf ~/.claude/skills/"${skill_name}"
    cp -r "$skill_dir" ~/.claude/skills/"${skill_name}" && rm -rf ~/.claude/skills/"${skill_name}"/.git
    count=$((count + 1))
  done
  rm -rf "$tmp"
  echo "✓ (${count} skills)"
}

do_install_local_skill() {
  local name="$1"
  local source="${SCRIPT_DIR}/skills/${name}"
  echo -n "  ${name} (local)... "
  if [ ! -d "$source" ] || [ ! -f "${source}/SKILL.md" ]; then
    echo "⚠ FAILED (continuing)"
    record_fail "local-skill ${name}: skills/${name}/SKILL.md not found in ${SCRIPT_DIR}"
    return 0
  fi
  mkdir -p ~/.claude/skills
  rm -rf ~/.claude/skills/"${name}"
  cp -r "$source" ~/.claude/skills/"${name}"
  echo "✓"
}

do_install_local_command() {
  local name="$1"
  local source="${SCRIPT_DIR}/commands/${name}.md"
  echo -n "  /${name} (local)... "
  if [ ! -f "$source" ]; then
    echo "⚠ FAILED (continuing)"
    record_fail "local-command ${name}: commands/${name}.md not found in ${SCRIPT_DIR}"
    return 0
  fi
  mkdir -p ~/.claude/commands
  cp "$source" ~/.claude/commands/"${name}.md"
  echo "✓"
}

do_install_global_memory() {
  local file="$1"
  local source="${SCRIPT_DIR}/${file}"
  local target=~/.claude/CLAUDE.md
  local start_marker="<!-- bionic:start -->"
  local end_marker="<!-- bionic:end -->"
  local old_start="<!-- claude-setup:start -->"

  echo -n "  ${file} → ~/.claude/CLAUDE.md... "

  if [ ! -f "$source" ]; then
    echo "⚠ FAILED (continuing)"
    record_fail "global-memory ${file}: not found in ${SCRIPT_DIR}"
    return 0
  fi

  mkdir -p ~/.claude

  local content
  content="$(cat "$source")"
  local section="${start_marker}
${content}
${end_marker}"

  # Migrate old claude-setup markers to bionic
  if [ -f "$target" ] && grep -q "$old_start" "$target"; then
    sed_inplace "s|<!-- claude-setup:start -->|${start_marker}|;s|<!-- claude-setup:end -->|${end_marker}|" "$target"
  fi

  if [ ! -f "$target" ]; then
    # No existing file — create with managed section
    echo "$section" > "$target"
  elif grep -q "$start_marker" "$target"; then
    # Markers exist — replace managed section
    local tmp="${target}.tmp"
    {
      awk -v start="$start_marker" '
        $0 == start { exit }
        { print }
      ' "$target"
      echo "$section"
      awk -v end="$end_marker" '
        found { print }
        $0 == end { found=1 }
      ' "$target"
    } > "$tmp" && mv "$tmp" "$target"
  else
    # File exists, no markers — append with blank line separator
    printf "\n%s\n" "$section" >> "$target"
  fi

  echo "✓"
}

verify_brew_dep() {
  local binary="$1"
  if command -v "$binary" &>/dev/null; then
    echo "    ${binary} ✓"
  else
    echo "    ${binary} — not found"
    verify_errors+=("${binary} CLI tool — not found")
  fi
}

verify_brew_cask() {
  local binary="$1"
  if command -v "$binary" &>/dev/null; then
    echo "    ${binary} ✓"
  else
    echo "    ${binary} — not found"
    verify_errors+=("${binary} (brew cask) — not found")
  fi
}

verify_npm_global() {
  local pkg="$1"
  if npm list -g --depth=0 "$pkg" &>/dev/null; then
    echo "    ${pkg} ✓"
  else
    echo "    ${pkg} — not found"
    verify_errors+=("${pkg} npm package — not found")
  fi
}

verify_uv_tool() {
  local pkg="$1" binary="${2:-$1}"
  if command -v "$binary" &>/dev/null; then
    echo "    ${binary} ✓"
  else
    echo "    ${binary} — not found"
    verify_errors+=("${binary} uv tool (${pkg}) — not found")
  fi
}

verify_mcp_server() {
  local name="$1" pkg="${2:-}" env_vars="${3:-}"
  if claude mcp get "$name" &>/dev/null; then
    echo "    ${name} ✓"
    return 0
  fi
  # If the server requires env vars that aren't set, it was intentionally skipped
  if [ -n "$env_vars" ]; then
    local missing=()
    IFS=',' read -ra vars <<< "$env_vars"
    for var in "${vars[@]}"; do
      var="$(echo "$var" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      if [ -z "${!var:-}" ]; then
        missing+=("$var")
      fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
      echo "    ${name} — skipped (${missing[*]} not set)"
      verify_warnings+=("${name} MCP server — skipped (set ${missing[*]} in your environment)")
      return 0
    fi
  fi
  echo "    ${name} — not configured"
  verify_errors+=("${name} MCP server — not configured")
}

verify_local_package_built() {
  local pkg="$1"
  local pkg_dir="${SCRIPT_DIR}/${pkg}"
  [ -f "${pkg_dir}/package.json" ] || return 0
  if [ -d "${pkg_dir}/node_modules" ] && [ -d "${pkg_dir}/dist" ]; then
    echo "    ${pkg} ✓"
  else
    echo "    ${pkg} — node_modules/ or dist/ missing"
    verify_errors+=("${pkg} local package — node_modules/ or dist/ missing")
  fi
}

# ─── CLI Tools (brew) ───────────────────────────────────────────────────────

echo "CLI tools (brew):"
read_config "brew-dep" do_install_brew_dep
echo ""

# ─── CLI Tools (brew casks) ──────────────────────────────────────────────────

echo "CLI tools (brew casks):"
read_config "brew-cask" do_install_brew_cask
echo ""

# ─── CLI Tools (npm) ─────────────────────────────────────────────────────────

echo "CLI tools (npm):"
# node (hence npm) is itself a brew-dep installed above. If that failed, skip
# the npm-globals rather than aborting the whole run — recorded for the summary.
if ! command -v npm &>/dev/null; then
  echo "  ⚠ npm not found (node install failed?) — skipping npm globals (continuing)"
  record_fail "npm not found — npm globals not installed (install node)"
else
  read_config "npm-global" do_install_npm_global
fi
echo ""

# ─── CLI Tools (uv) ─────────────────────────────────────────────────────────

echo "CLI tools (uv):"
# uv is a brew-dep installed above; skip its tools (not abort) if it's missing.
if ! command -v uv &>/dev/null; then
  echo "  ⚠ uv not found — skipping uv tools (continuing)"
  record_fail "uv not found — uv tools not installed (brew install uv)"
else
  # Ensure uv tool bin directory is on PATH (uv installs binaries to ~/.local/bin/)
  uv_bin_dir="$(uv tool dir --bin 2>/dev/null)"
  if [ -n "$uv_bin_dir" ] && [[ ":$PATH:" != *":${uv_bin_dir}:"* ]]; then
    export PATH="${uv_bin_dir}:${PATH}"
  fi
  read_config "uv-tool" do_install_uv_tool
fi
echo ""

# ─── Frontend Libraries (pnpm store) ─────────────────────────────────────────
#
# Pre-warm the pnpm content-addressable store with importable JS libraries
# (e.g. motion). Projects pull them in with `pnpm add <pkg>`, which hard-links
# from the warm store — instant and offline. See the `motion` skill for usage.

echo "Frontend libraries (pnpm store):"
if ! command -v pnpm &>/dev/null; then
  echo "  ⚠ pnpm not found — skipping frontend library pre-warm (continuing)"
  record_fail "pnpm not found — frontend libraries not pre-warmed"
else
  read_config "pnpm-store" do_install_pnpm_store
fi
echo ""

# ─── Playwright Browsers ────────────────────────────────────────────────────

echo -n "Playwright browsers (chromium)... "
if npx playwright install chromium 2>/dev/null; then
  echo "✓"
else
  echo "⚠ FAILED (continuing)"
  record_fail "playwright chromium browser install"
fi
echo ""

# ─── Marketplaces ────────────────────────────────────────────────────────────

echo "Marketplaces:"
read_config "marketplace" do_install_marketplace
echo ""

# ─── Plugins ─────────────────────────────────────────────────────────────────

echo "Plugins:"
read_config "plugin" do_install_plugin
echo ""

# ─── Global Memory ─────────────────────────────────────────────────────────

echo "Global memory:"
read_config "global-memory" do_install_global_memory
echo ""

# ─── Shell Alias ─────────────────────────────────────────────────────────────

echo "Shell alias:"
echo -n "  claude → claude --dangerously-skip-permissions... "
ALIAS_RC="$SHELL_RC"
ALIAS_START="# ─── bionic:start ───"
ALIAS_END="# ─── bionic:end ───"
ALIAS_CONTENT="alias claude='claude --dangerously-skip-permissions'"
ALIAS_SECTION="${ALIAS_START}
${ALIAS_CONTENT}
${ALIAS_END}"

# Migrate old unmarked alias to marker-based section
if [ -f "$ALIAS_RC" ] && grep -q "alias claude=.*dangerously-skip-permissions" "$ALIAS_RC" && ! grep -qF "$ALIAS_START" "$ALIAS_RC"; then
  grep -v "alias claude=.*dangerously-skip-permissions" "$ALIAS_RC" > "${ALIAS_RC}.tmp" && mv "${ALIAS_RC}.tmp" "$ALIAS_RC"
  printf '\n%s\n' "$ALIAS_SECTION" >> "$ALIAS_RC"
  echo "✓ (migrated to markers)"
elif grep -qF "$ALIAS_START" "$ALIAS_RC" 2>/dev/null; then
  # Markers exist — replace managed section
  {
    awk -v start="$ALIAS_START" '
      $0 == start { exit }
      { print }
    ' "$ALIAS_RC"
    echo "$ALIAS_SECTION"
    awk -v end="$ALIAS_END" '
      found { print }
      $0 == end { found=1 }
    ' "$ALIAS_RC"
  } > "${ALIAS_RC}.tmp" && mv "${ALIAS_RC}.tmp" "$ALIAS_RC"
  echo "✓ (already installed)"
else
  # No markers, no alias — append
  printf '\n%s\n' "$ALIAS_SECTION" >> "$ALIAS_RC"
  echo "✓"
fi
echo ""

# ─── Custom Skills ───────────────────────────────────────────────────────────

echo "Custom skills:"
read_config "github-skill" do_install_github_skill
read_config "github-skill-pack" do_install_github_skill_pack
read_config "local-skill" do_install_local_skill
echo ""

# ─── Custom Commands ────────────────────────────────────────────────────────

echo "Custom commands:"

# Prune orphan commands: anything in ~/.claude/commands/ not listed in
# claude-config.txt as a local-command entry. Renames (memory-sweep →
# memory-compact) leave stale files behind without this step.
if [ -d ~/.claude/commands ]; then
  managed_commands="$(grep -E '^\s*local-command\s*\|' "$CONFIG" | sed -E 's/^[^|]+\|[[:space:]]*//;s/[[:space:]]+$//')"
  for f in ~/.claude/commands/*.md; do
    [ -f "$f" ] || continue
    base="$(basename "$f" .md)"
    if ! echo "$managed_commands" | grep -qx "$base"; then
      rm -f "$f"
      echo "  /${base}... ✗ removed (no longer in config)"
    fi
  done
fi

read_config "local-command" do_install_local_command
echo ""

# ─── Skill Setup ────────────────────────────────────────────────────────────

echo "Skill setup:"
if [ -d ~/.claude/skills/excalidraw-diagram/references ]; then
  echo -n "  excalidraw-diagram renderer... "
  if (cd ~/.claude/skills/excalidraw-diagram/references && uv sync --quiet 2>&1 && uv run playwright install chromium 2>&1) | tail -1; then
    echo "  ✓"
  else
    echo "  ⚠ FAILED (continuing)"
    record_fail "excalidraw-diagram renderer (uv sync / playwright)"
  fi
else
  echo "  excalidraw-diagram — skipped (not installed)"
fi
if command -v notebooklm &>/dev/null; then
  echo -n "  notebooklm skill install... "
  notebooklm skill install &>/dev/null && echo "✓" || echo "✓ (skill already installed)"
else
  echo "  notebooklm — skipped (CLI not installed)"
fi
echo ""

# ─── Global Hooks ────────────────────────────────────────────────────────────

echo "Global hooks:"
mkdir -p ~/.claude/hooks

# settings.json mutations below need jq. If its brew install failed earlier,
# skip the jq-driven config (hooks wiring, env vars, statusline) rather than
# aborting the whole run — recorded for the summary. Hook *files* are still
# copied; only the settings.json wiring is skipped.
settings=~/.claude/settings.json
HAVE_JQ=1
command -v jq &>/dev/null || { HAVE_JQ=0; record_fail "jq unavailable — settings.json hooks/env/statusline not configured"; }

# Build the set of hook files present in the repo (canonical source of truth).
declare -a repo_hooks=()
for hook in "${SCRIPT_DIR}"/hooks/*.sh; do
  [ -f "$hook" ] || continue
  [[ "$(basename "$hook")" == *.test.sh ]] && continue
  repo_hooks+=("$(basename "$hook")")
done

# Remove any installed hooks that no longer exist in the repo. The repo is
# canonical — orphaned hooks in ~/.claude/hooks/ are deletion candidates from
# prior refactors and must be cleaned up so they don't fire stale logic.
removed_hooks=0
for installed in ~/.claude/hooks/*.sh; do
  [ -f "$installed" ] || continue
  base="$(basename "$installed")"
  found=0
  for r in "${repo_hooks[@]}"; do
    if [ "$base" = "$r" ]; then found=1; break; fi
  done
  if [ "$found" -eq 0 ]; then
    rm -f "$installed"
    echo "  ${base}... ✗ removed (no longer in repo)"
    removed_hooks=$((removed_hooks + 1))
  fi
done

# Install current hooks from the repo.
for hook in "${SCRIPT_DIR}"/hooks/*.sh; do
  [ -f "$hook" ] || continue
  [[ "$(basename "$hook")" == *.test.sh ]] && continue
  name="$(basename "$hook")"
  echo -n "  ${name}... "
  cp "$hook" ~/.claude/hooks/"$name"
  chmod +x ~/.claude/hooks/"$name"
  echo "✓"
done

# Rebuild hook config in global settings.
echo -n "  settings.json hook config... "
if [ ! -f "$settings" ]; then
  echo '{}' > "$settings"
fi

# Define all managed hooks (event|matcher_or_empty|command pairs)
# PreToolUse uses Bash/Write/Edit/Agent matchers; SessionStart uses a
# source matcher (startup — don't fire on compact/clear/resume since
# cleanup was already done for this notebook); UserPromptSubmit takes
# no matcher.
MANAGED_HOOKS=(
  "PreToolUse|Bash|~/.claude/hooks/protect-main.sh"
  "PreToolUse|Bash|~/.claude/hooks/protect-database.sh"
  "PreToolUse|Bash|~/.claude/hooks/canonical-sdlc-evidence-gate.sh"
  "PreToolUse|Write|~/.claude/hooks/canonical-sdlc-governing-skill.sh"
  "PreToolUse|Edit|~/.claude/hooks/canonical-sdlc-governing-skill.sh"
  "SessionStart|startup|~/.claude/hooks/memory-cleanup.sh"
  "UserPromptSubmit||~/.claude/hooks/terseness-reminder.sh"
)

if [ "$HAVE_JQ" != 1 ]; then
  echo "⚠ skipped (jq unavailable)"
else
# Reset .hooks to exactly the managed set. This is convergent: removing an
# entry from MANAGED_HOOKS removes it from settings.json on the next run.
tmp="${settings}.tmp"
jq '.hooks = {}' "$settings" > "$tmp" && mv "$tmp" "$settings"

for entry in "${MANAGED_HOOKS[@]}"; do
  IFS='|' read -r event matcher cmd <<< "$entry"
  tmp="${settings}.tmp"
  if ! jq -e --arg ev "$event" '.hooks[$ev]' "$settings" &>/dev/null; then
    jq --arg ev "$event" '.hooks[$ev] = []' "$settings" > "$tmp" && mv "$tmp" "$settings"
  fi
  tmp="${settings}.tmp"
  if [ -n "$matcher" ]; then
    jq --arg ev "$event" --arg m "$matcher" --arg c "$cmd" '
      .hooks[$ev] += [{
        "matcher": $m,
        "hooks": [{"type": "command", "command": $c, "timeout": 10}]
      }]
    ' "$settings" > "$tmp" && mv "$tmp" "$settings"
  else
    jq --arg ev "$event" --arg c "$cmd" '
      .hooks[$ev] += [{
        "hooks": [{"type": "command", "command": $c}]
      }]
    ' "$settings" > "$tmp" && mv "$tmp" "$settings"
  fi
done

echo "✓ (${#MANAGED_HOOKS[@]} managed hooks)"
fi
if [ "$removed_hooks" -gt 0 ]; then
  echo "  cleaned up ${removed_hooks} stale hook file(s) from ~/.claude/hooks/"
fi
echo ""

# ─── Account-mirror symlinks ────────────────────────────────────────────────
#
# When multiple Claude accounts exist (~/.claude-other, ~/.claude-synthesis,
# etc.), share the global config across them by symlinking settings.json and
# CLAUDE.md back to the canonical ~/.claude/ copies. Auth (.claude.json),
# history, and per-account caches stay separate.

echo "Account-mirror symlinks:"
mirror_count=0
for mirror in ~/.claude-*; do
  [ -d "$mirror" ] || continue
  account="$(basename "$mirror")"
  for f in settings.json CLAUDE.md; do
    target="${mirror}/${f}"
    canonical="${HOME}/.claude/${f}"
    if [ -L "$target" ]; then
      continue  # already symlinked
    fi
    if [ -f "$target" ]; then
      mv "$target" "${target}.bak-$(date +%Y%m%d-%H%M%S)"
    fi
    ln -s "$canonical" "$target"
    echo "  ${account}/${f} → ~/.claude/${f} ✓"
    mirror_count=$((mirror_count + 1))
  done
done
if [ "$mirror_count" -eq 0 ]; then
  echo "  (no additional accounts found, or already symlinked)"
fi
echo ""

# ─── Env Vars ───────────────────────────────────────────────────────────────

echo "Env vars:"

env_added=0
do_set_env_var() {
  local key="$1" val="$2"
  echo -n "  ${key}=${val}... "
  if jq -e --arg k "$key" --arg v "$val" '.env[$k] == $v' "$settings" &>/dev/null; then
    echo "✓ (already set)"
    return
  fi
  tmp="${settings}.tmp"
  jq --arg k "$key" --arg v "$val" '.env[$k] = $v' "$settings" > "$tmp" && mv "$tmp" "$settings"
  env_added=$((env_added + 1))
  echo "✓"
}
if [ "$HAVE_JQ" = 1 ]; then
  read_config "env-var" do_set_env_var
else
  echo "  ⚠ skipped (jq unavailable)"
fi
echo ""

# ─── Status Line ──────────────────────────────────────────────────────────────

echo "Status line:"

do_set_statusline() {
  local cmd="$1"
  echo -n "  ${cmd}... "
  if jq -e --arg c "$cmd" '.statusLine.command == $c' "$settings" &>/dev/null; then
    echo "✓ (already set)"
    return
  fi
  tmp="${settings}.tmp"
  jq --arg c "$cmd" '.statusLine = {"type": "command", "command": $c}' "$settings" > "$tmp" && mv "$tmp" "$settings"
  echo "✓"
}
if [ "$HAVE_JQ" = 1 ]; then
  read_config "statusline" do_set_statusline
else
  echo "  ⚠ skipped (jq unavailable)"
fi
echo ""

# ─── ccstatusline Config ──────────────────────────────────────────────────────

echo "ccstatusline config:"
echo -n "  settings.json → ~/.config/ccstatusline/settings.json... "
mkdir -p ~/.config/ccstatusline
if diff -q "${SCRIPT_DIR}/ccstatusline/settings.json" ~/.config/ccstatusline/settings.json &>/dev/null; then
  echo "✓ (already up to date)"
else
  cp "${SCRIPT_DIR}/ccstatusline/settings.json" ~/.config/ccstatusline/settings.json
  echo "✓"
fi
echo ""

# ─── Local Package Builds ────────────────────────────────────────────────────

echo "Local packages:"
read_config "mcp-server" do_build_local_package
echo ""

# ─── MCP Servers ─────────────────────────────────────────────────────────────

echo "MCP servers:"
read_config "mcp-server" do_configure_mcp_server
echo ""

# ─── Verification ───────────────────────────────────────────────────────────

verify_errors=()
verify_warnings=()
echo "Verification:"

echo ""
echo "  CLI tools (brew):"
read_config "brew-dep" verify_brew_dep

echo ""
echo "  CLI tools (brew casks):"
read_config "brew-cask" verify_brew_cask

echo ""
echo "  CLI tools (npm):"
read_config "npm-global" verify_npm_global

echo ""
echo "  CLI tools (uv):"
read_config "uv-tool" verify_uv_tool

echo ""
echo "  Playwright browsers:"
if ls "${PLAYWRIGHT_CACHE}"/chromium-* &>/dev/null; then
  echo "    chromium ✓"
else
  echo "    chromium — not found"
  verify_errors+=("chromium browser — not found")
fi

echo ""
echo "  Skill setup:"
if [ -d ~/.claude/skills/excalidraw-diagram/references/.venv ]; then
  echo "    excalidraw-diagram renderer ✓"
else
  echo "    excalidraw-diagram renderer — .venv not found (skill not installed or uv sync failed)"
fi
if [ -f ~/.claude/skills/notebooklm/SKILL.md ]; then
  echo "    notebooklm skill ✓"
elif command -v notebooklm &>/dev/null; then
  echo "    notebooklm skill — SKILL.md not found (run: notebooklm skill install)"
fi

echo ""
echo "  Local package builds:"
read_config "mcp-server" verify_local_package_built

echo ""
echo "  MCP servers:"
read_config "mcp-server" verify_mcp_server

echo ""
echo "  Global hooks:"
for hook in ~/.claude/hooks/*.sh; do
  [ -f "$hook" ] || continue
  echo "    $(basename "$hook") ✓"
done

echo ""
echo "  Plugins (official skills):"
claude plugin list 2>&1 | while IFS= read -r line; do echo "    $line"; done

echo ""
echo "  Custom skills:"
for skill_dir in ~/.claude/skills/*/; do
  [ -d "$skill_dir" ] || continue
  name="$(basename "$skill_dir")"
  if [ -f "${skill_dir}SKILL.md" ]; then
    echo "    ${name} ✓"
  else
    echo "    ${name} ⚠ (missing SKILL.md)"
  fi
done

echo ""
echo "  Custom commands:"
if [ -d ~/.claude/commands ] && [ -n "$(ls -A ~/.claude/commands 2>/dev/null)" ]; then
  for cmd_file in ~/.claude/commands/*.md; do
    [ -f "$cmd_file" ] || continue
    echo "    /$(basename "$cmd_file" .md) ✓"
  done
else
  echo "    (none installed)"
fi


echo ""
echo "  Status line:"
if jq -e '.statusLine.command' "$settings" &>/dev/null; then
  echo "    $(jq -r '.statusLine.command' "$settings") ✓"
else
  echo "    (not configured)"
fi

echo ""
echo "  ccstatusline config:"
if diff -q "${SCRIPT_DIR}/ccstatusline/settings.json" ~/.config/ccstatusline/settings.json &>/dev/null; then
  echo "    settings.json ✓"
else
  echo "    settings.json — out of sync"
  verify_errors+=("ccstatusline settings.json — out of sync")
fi

echo ""
echo "  Global memory:"
if [ -f ~/.claude/CLAUDE.md ] && grep -q "<!-- bionic:start -->" ~/.claude/CLAUDE.md; then
  echo "    ~/.claude/CLAUDE.md ✓"
else
  echo "    ~/.claude/CLAUDE.md — not installed"
fi

echo ""
echo "  Shell alias:"
if [ -f "$SHELL_RC" ] && grep -qF "# ─── bionic:start ───" "$SHELL_RC"; then
  echo "    ~/${SHELL_RC_NAME} ✓"
else
  echo "    ~/${SHELL_RC_NAME} — not installed"
fi

# ─── Summary Report ─────────────────────────────────────────────────────────

echo ""
error_count=${#verify_errors[@]}
warning_count=${#verify_warnings[@]}
install_fail_count=${#INSTALL_FAILURES[@]}

if [ "$error_count" -eq 0 ] && [ "$warning_count" -eq 0 ] && [ "$install_fail_count" -eq 0 ]; then
  echo "Done ✓"
else
  if [ "$error_count" -gt 0 ] || [ "$install_fail_count" -gt 0 ]; then
    echo "Done (${install_fail_count} install failure(s), ${error_count} verification error(s), ${warning_count} warning(s))"
  else
    echo "Done ✓ (${warning_count} warning(s))"
  fi
  # The install phase always runs to completion. Steps that failed are listed
  # here (with their captured error) rather than aborting the run mid-way.
  if [ "$install_fail_count" -gt 0 ]; then
    echo ""
    echo "  Install failures (run completed; these steps did not — re-run to retry):"
    for msg in "${INSTALL_FAILURES[@]}"; do
      echo "    ✗ ${msg}"
    done
  fi
  if [ "$error_count" -gt 0 ]; then
    echo ""
    echo "  Verification errors:"
    for msg in "${verify_errors[@]}"; do
      echo "    ✗ ${msg}"
    done
  fi
  if [ "$warning_count" -gt 0 ]; then
    echo ""
    echo "  Warnings:"
    for msg in "${verify_warnings[@]}"; do
      echo "    ⚠ ${msg}"
    done
  fi
fi

if [ "$error_count" -gt 0 ] || [ "$install_fail_count" -gt 0 ]; then
  exit 1
fi
