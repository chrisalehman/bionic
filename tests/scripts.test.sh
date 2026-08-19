#!/bin/bash
# Tests for claude-bootstrap.sh and claude-reset.sh shared logic.
# Covers config parsing, config file well-formedness, script symmetry,
# hook consistency, and shell alias marker consistency.
# Does NOT run bootstrap or reset — no side effects.
#
# Usage: bash tests/scripts.test.sh

set -euo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/frontmatter-parser.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
CONFIG="${REPO}/claude-config.txt"
BOOTSTRAP="${BIONIC_SCRIPTS_DIR}/claude-bootstrap.sh"
RESET="${BIONIC_SCRIPTS_DIR}/claude-reset.sh"

PASS=0
FAIL=0
TOTAL=0

# ---------- helpers ----------

expect_true() {
  local label="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" 2>/dev/null; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label"
    FAIL=$((FAIL + 1))
  fi
}

expect_false() {
  local label="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@" 2>/dev/null; then
    echo "FAIL (expected false): $label"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: $label"
    PASS=$((PASS + 1))
  fi
}

expect_eq() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (expected='$expected' actual='$actual')"
    FAIL=$((FAIL + 1))
  fi
}

expect_contains() {
  local label="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF "$needle"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (expected to contain '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

# ---------- setup: define read_config pointing at $CONFIG_FILES ----------
#
# Identical to the function in both scripts. We keep it here so tests can
# run it against a temp file without sourcing the full scripts (side effects).

# CONFIG_FILES: the config file(s) read_config operates against.
# Set to a tmpfile for Section 1 parsing tests; set to $CONFIG for real-config tests.
# The EXIT trap only cleans up the tmpfiles (created here for Section 1).
CONFIG_FILES=()
S1_TMPFILE="$(mktemp)"
S1_TMPFILE2="$(mktemp)"

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

cleanup() {
  rm -f "$S1_TMPFILE" "$S1_TMPFILE2"
}
trap cleanup EXIT

# ============================================================
# SECTION 1: Config file parsing (read_config)
# ============================================================

echo ""
echo "=== Section 1: Config file parsing (read_config) ==="

CONFIG_FILES=("$S1_TMPFILE")
cat > "$S1_TMPFILE" << 'EOF'
# This is a comment — must be skipped
brew-dep     | git
brew-dep     | rg            | ripgrep
npm-global   | @playwright/cli
npm-global   | @sentry/cli
mcp-server   | context7      | @upstash/context7-mcp@latest
mcp-server   | trello        | @delorenj/mcp-server-trello | TRELLO_API_KEY,TRELLO_TOKEN
mcp-server   | sentry        | @sentry/mcp-server@latest   | SENTRY_ACCESS_TOKEN

   # Indented comment — must be skipped

local-skill  | browser-verify
env-var      | CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS | 1
statusline   | npx ccstatusline@latest
plugin       | superpowers         | claude-plugins-official
global-memory | claude-global.md
uv-tool      | notebooklm-py       | notebooklm
EOF

# 1a: Basic two-field entry (git) parses correctly
_found_git=0
_found_git_f2="nonempty"
_check_git() {
  if [ "$1" = "git" ]; then
    _found_git=1
    _found_git_f2="$2"
  fi
}
read_config "brew-dep" _check_git
expect_eq "brew-dep two-field: git entry found" "1" "$_found_git"
expect_eq "brew-dep two-field: git f2 is empty" "" "$_found_git_f2"

# 1b: Three-field brew-dep entry (binary != package)
_found_rg_pkg=""
_check_rg() {
  if [ "$1" = "rg" ]; then
    _found_rg_pkg="$2"
  fi
}
read_config "brew-dep" _check_rg
expect_eq "brew-dep three-field: rg maps to ripgrep" "ripgrep" "$_found_rg_pkg"

# 1c: npm-global entry parses correctly (@playwright/cli)
_found_playwright=0
_check_playwright() {
  if [ "$1" = "@playwright/cli" ]; then
    _found_playwright=1
  fi
}
read_config "npm-global" _check_playwright
expect_eq "npm-global: @playwright/cli entry found" "1" "$_found_playwright"

# 1d: mcp-server two-field entry (name + package, no env vars)
_ctx7_pkg=""
_check_ctx7() {
  if [ "$1" = "context7" ]; then
    _ctx7_pkg="$2"
  fi
}
read_config "mcp-server" _check_ctx7
expect_eq "mcp-server two-field: context7 pkg correct" "@upstash/context7-mcp@latest" "$_ctx7_pkg"

# 1e: mcp-server three-field entry (name + package + env vars)
_trello_env=""
_check_trello() {
  if [ "$1" = "trello" ]; then
    _trello_env="$3"
  fi
}
read_config "mcp-server" _check_trello
expect_eq "mcp-server three-field: trello env vars parsed" "TRELLO_API_KEY,TRELLO_TOKEN" "$_trello_env"

# 1f: Commented lines are skipped — type '#' should produce zero callbacks
_comment_count=0
_count_entries() { _comment_count=$((_comment_count + 1)); }
read_config "#" _count_entries
expect_eq "commented lines produce no callbacks" "0" "$_comment_count"

# 1g: Blank lines are skipped — exactly 2 brew-dep entries in test config
_brew_count=0
_count_brew() { _brew_count=$((_brew_count + 1)); }
read_config "brew-dep" _count_brew
expect_eq "blank lines skipped: exactly 2 brew-dep entries" "2" "$_brew_count"

# 1h: Fields are trimmed of leading/trailing whitespace
_local_skill_name=""
_check_local_skill() { _local_skill_name="$1"; }
read_config "local-skill" _check_local_skill
expect_eq "local-skill: name whitespace-trimmed" "browser-verify" "$_local_skill_name"

# 1i: env-var two-field entry (key and value both trimmed)
_env_key="" _env_val=""
_check_env() { _env_key="$1"; _env_val="$2"; }
read_config "env-var" _check_env
expect_eq "env-var: key trimmed correctly" "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" "$_env_key"
expect_eq "env-var: value trimmed correctly" "1" "$_env_val"

# 1j: statusline single-field entry
_statusline_cmd=""
_check_statusline() { _statusline_cmd="$1"; }
read_config "statusline" _check_statusline
expect_eq "statusline: command parsed" "npx ccstatusline@latest" "$_statusline_cmd"

# 1k: plugin two-field entry
_plugin_name="" _plugin_src=""
_check_plugin() { _plugin_name="$1"; _plugin_src="$2"; }
read_config "plugin" _check_plugin
expect_eq "plugin: name trimmed" "superpowers" "$_plugin_name"
expect_eq "plugin: source trimmed" "claude-plugins-official" "$_plugin_src"

# 1l: global-memory single-field entry
_gm_file=""
_check_gm() { _gm_file="$1"; }
read_config "global-memory" _check_gm
expect_eq "global-memory: filename parsed" "claude-global.md" "$_gm_file"

# 1m: uv-tool two-field entry (package + binary)
_uv_pkg="" _uv_bin=""
_check_uv() { _uv_pkg="$1"; _uv_bin="$2"; }
read_config "uv-tool" _check_uv
expect_eq "uv-tool: package parsed" "notebooklm-py" "$_uv_pkg"
expect_eq "uv-tool: binary parsed" "notebooklm" "$_uv_bin"

# 1n: Optional f3 field is empty string when not present (not unbound variable)
_ctx7_f3="__unset__"
_check_ctx7_f3() {
  if [ "$1" = "context7" ]; then
    _ctx7_f3="$3"
  fi
}
read_config "mcp-server" _check_ctx7_f3
expect_eq "mcp-server two-field: f3 is empty string (not unset)" "" "$_ctx7_f3"

# 1n: sentry entry has correct env var in f3
_sentry_env=""
_check_sentry() {
  if [ "$1" = "sentry" ]; then
    _sentry_env="$3"
  fi
}
read_config "mcp-server" _check_sentry
expect_eq "mcp-server: sentry f3 has SENTRY_ACCESS_TOKEN" "SENTRY_ACCESS_TOKEN" "$_sentry_env"

# 1o: npm-global sentry-cli entry parses correctly
_found_sentry_cli=0
_check_sentry_cli() {
  if [ "$1" = "@sentry/cli" ]; then
    _found_sentry_cli=1
  fi
}
read_config "npm-global" _check_sentry_cli
expect_eq "npm-global: @sentry/cli entry found" "1" "$_found_sentry_cli"

# 1p: Unknown type yields zero callbacks
_unknown_count=0
_count_unknown() { _unknown_count=$((_unknown_count + 1)); }
read_config "no-such-type" _count_unknown
expect_eq "unknown type yields zero callbacks" "0" "$_unknown_count"

# 1q: mcp-server callback receives all three fields (f1, f2, f3) for three-field entry
_trello_f1="" _trello_f2="" _trello_f3=""
_check_trello_all() {
  if [ "$1" = "trello" ]; then
    _trello_f1="$1"; _trello_f2="$2"; _trello_f3="$3"
  fi
}
read_config "mcp-server" _check_trello_all
expect_eq "mcp-server: trello f1=name" "trello" "$_trello_f1"
expect_eq "mcp-server: trello f2=pkg" "@delorenj/mcp-server-trello" "$_trello_f2"
expect_eq "mcp-server: trello f3=env_vars" "TRELLO_API_KEY,TRELLO_TOKEN" "$_trello_f3"

# 1r: stdin-theft regression — a callback whose child consumes stdin must NOT
# truncate the remaining config entries. This is the bug that made a brew tap
# install (git clone reads stdin) silently skip 6 of 17 brew deps.
_theft_count=0
_stdin_thief() {
  _theft_count=$((_theft_count + 1))
  cat > /dev/null   # would eat the rest of the config stream without </dev/null
}
read_config "brew-dep" _stdin_thief
expect_eq "stdin-reading callback does not truncate the config (all 2 brew-deps seen)" "2" "$_theft_count"

# 1s: profile layering — a second config file's entries are appended, and
# exact-duplicate lines across files are deduped.
cat > "$S1_TMPFILE2" << 'EOF'
brew-dep     | git
brew-dep     | extra-tool
EOF
CONFIG_FILES=("$S1_TMPFILE" "$S1_TMPFILE2")
_layer_names=""
_collect_brew() { _layer_names="${_layer_names}${1} "; }
read_config "brew-dep" _collect_brew
expect_eq "profile layering: core entries + profile additions, duplicates deduped" "git rg extra-tool " "$_layer_names"
CONFIG_FILES=("$S1_TMPFILE")

# ============================================================
# SECTION 2: Config file consistency (claude-config.txt)
# ============================================================

echo ""
echo "=== Section 2: Config file consistency (claude-config.txt) ==="

CONFIG_FILES=("$CONFIG")

KNOWN_TYPES="brew-dep brew-cask npm-global pnpm-store uv-tool mcp-server plugin marketplace github-skill github-skill-pack local-skill local-command global-memory env-var statusline"

# 2a: Every uncommented, non-blank line has at least one pipe delimiter
# (checked across core AND all profile config files)
_bad_lines=""
for _cfg in "$CONFIG" "${REPO}"/claude-config.*.txt; do
  [ -f "$_cfg" ] || continue
  while IFS= read -r line; do
    stripped="$(echo "$line" | sed 's/^[[:space:]]*//')"
    [ -z "$stripped" ] && continue
    if echo "$stripped" | grep -q '^#'; then
      continue
    fi
    if ! echo "$line" | grep -q '|'; then
      _bad_lines="${_bad_lines}$(basename "$_cfg"): ${line}\n"
    fi
  done < "$_cfg"
done
expect_eq "all uncommented non-blank lines have a pipe delimiter" "" "$_bad_lines"

# 2b: Every type field on uncommented lines is a known type
# (checked across core AND all profile config files)
_unknown_types=""
for _cfg in "$CONFIG" "${REPO}"/claude-config.*.txt; do
  [ -f "$_cfg" ] || continue
  while IFS='|' read -r entry_type _rest; do
    entry_type="$(echo "$entry_type" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    found=0
    for known in $KNOWN_TYPES; do
      if [ "$entry_type" = "$known" ]; then
        found=1
        break
      fi
    done
    if [ "$found" -eq 0 ]; then
      _unknown_types="${_unknown_types}${entry_type} "
    fi
  done < <(grep -v '^\s*#' "$_cfg" | grep -v '^\s*$')
done
expect_eq "all type fields are known types" "" "$_unknown_types"

# 2c: Every local-skill entry has a skills/<name>/SKILL.md file
_missing_skills=""
_check_local_skill_exists() {
  local name="$1"
  if [ ! -f "${BIONIC_SKILLS_DIR}/${name}/SKILL.md" ]; then
    _missing_skills="${_missing_skills}${name} "
  fi
}
read_config "local-skill" _check_local_skill_exists
expect_eq "all local-skill entries have SKILL.md" "" "$_missing_skills"

# 2c-bis: Every local-command entry has a commands/<name>.md file
_missing_commands=""
_check_local_command_exists() {
  local name="$1"
  if [ ! -f "${REPO}/commands/${name}.md" ]; then
    _missing_commands="${_missing_commands}${name} "
  fi
}
read_config "local-command" _check_local_command_exists
expect_eq "all local-command entries have commands/<name>.md" "" "$_missing_commands"

# 2d: Every global-memory file exists in the repo root
_missing_gm=""
_check_gm_exists() {
  local file="$1"
  if [ ! -f "${REPO}/${file}" ]; then
    _missing_gm="${_missing_gm}${file} "
  fi
}
read_config "global-memory" _check_gm_exists
expect_eq "all global-memory files exist in repo" "" "$_missing_gm"

# 2e: MCP server env var lists use valid identifier syntax (UPPER_SNAKE_CASE, comma-separated)
_bad_env_vars=""
_check_mcp_env_format() {
  local name="$1" env_vars="$3"
  [ -z "$env_vars" ] && return 0
  local old_ifs="$IFS"
  IFS=',' read -ra vars <<< "$env_vars"
  IFS="$old_ifs"
  for var in "${vars[@]}"; do
    var="$(echo "$var" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [ -z "$var" ] || ! echo "$var" | grep -qE '^[A-Z_][A-Z0-9_]*$'; then
      _bad_env_vars="${_bad_env_vars}${name}:${var} "
    fi
  done
}
read_config "mcp-server" _check_mcp_env_format
expect_eq "MCP env var names are valid UPPER_SNAKE_CASE identifiers" "" "$_bad_env_vars"

# 2f: Config file has at least one brew-dep entry
_brew_total=0
_count_brew_real() { _brew_total=$((_brew_total + 1)); }
read_config "brew-dep" _count_brew_real
expect_true "config has at least one brew-dep entry" [ "$_brew_total" -gt 0 ]

# 2g: Config file has at least one mcp-server entry
_mcp_total=0
_count_mcp_real() { _mcp_total=$((_mcp_total + 1)); }
read_config "mcp-server" _count_mcp_real
expect_true "config has at least one mcp-server entry" [ "$_mcp_total" -gt 0 ]

# 2h: Config file has exactly one statusline entry
_statusline_total=0
_count_statusline() { _statusline_total=$((_statusline_total + 1)); }
read_config "statusline" _count_statusline
expect_eq "config has exactly one statusline entry" "1" "$_statusline_total"

# 2i: Config file has exactly one global-memory entry
_gm_total=0
_count_gm() { _gm_total=$((_gm_total + 1)); }
read_config "global-memory" _count_gm
expect_eq "config has exactly one global-memory entry" "1" "$_gm_total"

# 2j: gcloud is installed as a brew-cask mapping to the gcloud-cli cask.
# Regression guard: the google-cloud-sdk cask was renamed (now 404s) and there
# is no `gcloud` formula, so the old `brew-dep | gcloud` entry failed on a
# fresh machine.
_gcloud_cask=""
_check_gcloud_cask() { if [ "$1" = "gcloud" ]; then _gcloud_cask="$2"; fi; }
read_config "brew-cask" _check_gcloud_cask
expect_eq "gcloud is a brew-cask mapping to gcloud-cli" "gcloud-cli" "$_gcloud_cask"

# 2k: gcloud is NOT a brew-dep (that would install the nonexistent formula)
_gcloud_brewdep=0
_check_gcloud_brewdep() { if [ "$1" = "gcloud" ]; then _gcloud_brewdep=1; fi; }
read_config "brew-dep" _check_gcloud_brewdep
expect_eq "gcloud is not a (broken) brew-dep formula entry" "0" "$_gcloud_brewdep"

# 2l: motion is pre-warmed into the pnpm store
_motion_store=0
_check_motion_store() { if [ "$1" = "motion" ]; then _motion_store=1; fi; }
read_config "pnpm-store" _check_motion_store
expect_eq "motion is registered as a pnpm-store library" "1" "$_motion_store"

# ============================================================
# SECTION 3: Bootstrap/reset script symmetry
# ============================================================

echo ""
echo "=== Section 3: Bootstrap/reset script symmetry ==="

# 3a: Both scripts define read_config
expect_true "bootstrap defines read_config function" grep -q "^read_config()" "$BOOTSTRAP"
expect_true "reset defines read_config function" grep -q "^read_config()" "$RESET"

# 3b: Both scripts derive the core config path from SCRIPT_DIR and accept
# profile files as positional args (CONFIG_FILES array).
expect_true "bootstrap uses CONFIG_FILES from SCRIPT_DIR" grep -q 'CONFIG_FILES=(.*claude-config' "$BOOTSTRAP"
expect_true "reset uses CONFIG_FILES from SCRIPT_DIR" grep -q 'CONFIG_FILES=(.*claude-config' "$RESET"

# 3c-3k: Every config type read in bootstrap is also read in reset
for config_type in mcp-server env-var statusline plugin global-memory github-skill local-skill local-command npm-global uv-tool marketplace; do
  expect_true "bootstrap reads type: ${config_type}" grep -q "\"${config_type}\"" "$BOOTSTRAP"
  expect_true "reset reads type: ${config_type}" grep -q "\"${config_type}\"" "$RESET"
done

# 3l: context7 MCP server entry is active (not commented out) in config
_ctx7_found=0
_check_ctx7_config() {
  if [ "$1" = "context7" ]; then
    _ctx7_found=1
  fi
}
read_config "mcp-server" _check_ctx7_config
expect_eq "context7 MCP server entry is active in config" "1" "$_ctx7_found"

# 3m: Any active mcp-server entries with env vars list at least one var
_mcp_with_empty_env=""
_check_mcp_has_env() {
  local name="$1" env_vars="$3"
  # If f3 is non-empty but all whitespace, that's a malformed entry
  if [ -n "$env_vars" ]; then
    local trimmed
    trimmed="$(echo "$env_vars" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [ -z "$trimmed" ]; then
      _mcp_with_empty_env="${_mcp_with_empty_env}${name} "
    fi
  fi
}
read_config "mcp-server" _check_mcp_has_env
expect_eq "no mcp-server entries have whitespace-only env var list" "" "$_mcp_with_empty_env"

# 3n: read_config function body is identical in bootstrap and reset
_bootstrap_fn="$(awk '/^read_config\(\)/{found=1} found{print} found && /^\}$/{exit}' "$BOOTSTRAP")"
_reset_fn="$(awk '/^read_config\(\)/{found=1} found{print} found && /^\}$/{exit}' "$RESET")"
expect_eq "read_config function body identical in bootstrap and reset" "$_bootstrap_fn" "$_reset_fn"

# 3o: Both scripts source lib/platform.sh
expect_true "bootstrap sources lib/platform.sh" grep -q 'source.*lib/platform\.sh' "$BOOTSTRAP"
expect_true "reset sources lib/platform.sh" grep -q 'source.*lib/platform\.sh' "$RESET"

# 3p: agent-skills plugin entry is active (not commented out) in config
_agent_skills_found=0
_agent_skills_source=""
_check_agent_skills() {
  if [ "$1" = "agent-skills" ]; then
    _agent_skills_found=1
    _agent_skills_source="$2"
  fi
}
read_config "plugin" _check_agent_skills
expect_eq "agent-skills plugin entry is active in config" "1" "$_agent_skills_found"
expect_eq "agent-skills plugin sourced from addy-agent-skills" "addy-agent-skills" "$_agent_skills_source"

# 3q: addyosmani/agent-skills marketplace entry is active in config
_addy_marketplace_found=0
_check_addy_marketplace() {
  if [ "$1" = "addyosmani/agent-skills" ]; then
    _addy_marketplace_found=1
  fi
}
read_config "marketplace" _check_addy_marketplace
expect_eq "addyosmani/agent-skills marketplace entry is active in config" "1" "$_addy_marketplace_found"

# 3r: chrome-devtools MCP server entry is active (not commented out) in config
# Required by agent-skills:browser-testing-with-devtools, which assumes a
# `chrome-devtools` MCP server is configured.
_cdt_found=0
_cdt_pkg=""
_cdt_env=""
_check_cdt() {
  if [ "$1" = "chrome-devtools" ]; then
    _cdt_found=1
    _cdt_pkg="$2"
    _cdt_env="$3"
  fi
}
read_config "mcp-server" _check_cdt
expect_eq "chrome-devtools MCP server entry is active in config" "1" "$_cdt_found"

# 3s: chrome-devtools uses the official upstream package (chrome-devtools-mcp).
# The addy-agent-skills SKILL.md references @anthropic/chrome-devtools-mcp,
# which is wrong — the real package on npm is chrome-devtools-mcp. This test
# guards against accidentally adopting the bad name.
expect_eq "chrome-devtools package is chrome-devtools-mcp@latest" "chrome-devtools-mcp@latest" "$_cdt_pkg"

# 3t: chrome-devtools requires no env vars (no auth — runs against local Chrome)
expect_eq "chrome-devtools entry has no required env vars" "" "$_cdt_env"

# 3u: Bootstrap reads the install-only config types (brew-cask, pnpm-store).
# Like brew-dep, these are NOT undone by reset (shared system / cache state),
# so they are intentionally excluded from the symmetry loop above.
expect_true "bootstrap reads type: brew-cask" grep -q '"brew-cask"' "$BOOTSTRAP"
expect_true "bootstrap reads type: pnpm-store" grep -q '"pnpm-store"' "$BOOTSTRAP"

# 3v: Resilience posture — the install phase must run to completion even when a
# step fails. Bootstrap defines the retry + failure-collection helpers and the
# network installers record failures (non-fatal) instead of `exit 1`.
expect_true "bootstrap defines run_retry helper" grep -q "^run_retry()" "$BOOTSTRAP"
expect_true "bootstrap defines record_fail helper" grep -q "^record_fail()" "$BOOTSTRAP"
expect_true "bootstrap defines step_fail helper" grep -q "^step_fail()" "$BOOTSTRAP"
expect_true "bootstrap defines step_stream helper (heartbeat for >30s downloads)" grep -q "^step_stream()" "$BOOTSTRAP"
expect_true "bootstrap defines the read-only updates advisory" grep -q "^collect_updates()" "$BOOTSTRAP"
# The advisory must stay read-only: no upgrade verbs outside echoed remediation text.
expect_false "advisory never runs brew upgrade itself" grep -qE '^\s*(run_retry )?brew upgrade' "$BOOTSTRAP"
expect_true "bootstrap collects INSTALL_FAILURES" grep -q "INSTALL_FAILURES=" "$BOOTSTRAP"
expect_true "bootstrap collects STEP_RECORDS" grep -q "STEP_RECORDS=" "$BOOTSTRAP"

# Extract a function body from the bootstrap for content assertions.
_fn_body() {
  awk -v fn="$1" '$0 ~ "^"fn"\\(\\) \\{"{f=1} f{print} f&&/^\}$/{exit}' "$BOOTSTRAP"
}
expect_contains "marketplace installer records failures (non-fatal)" "step_fail" "$(_fn_body do_install_marketplace)"
expect_contains "plugin installer records failures (non-fatal)" "step_fail" "$(_fn_body do_install_plugin)"
expect_contains "mcp installer records failures (non-fatal, retried)" "run_retry claude mcp add" "$(_fn_body do_configure_mcp_server)"
# step_fail must keep feeding the legacy INSTALL_FAILURES array.
expect_contains "step_fail records into INSTALL_FAILURES" "record_fail" "$(_fn_body step_fail)"
# The marketplace + plugin installers used to `exit 1` on failure; ensure that
# fail-fast behavior is gone.
expect_false "marketplace/plugin installers no longer hard-exit" grep -qE 'echo "FAILED" >&2|echo "FAILED: \$output" >&2' "$BOOTSTRAP"

# 3w: stdin discipline — read_config detaches the callback's stdin, and
# run_retry detaches the child's stdin (defense in depth for the tap-install
# stdin-theft bug).
expect_contains "read_config detaches callback stdin" '</dev/null' "$(_fn_body read_config)"
expect_contains "run_retry detaches child stdin" '</dev/null' "$(_fn_body run_retry)"

# 3x: SSH→HTTPS structural fix — plugin installs must not depend on GitHub SSH
# keys existing on a fresh machine.
expect_true "bootstrap rewrites git SSH to HTTPS for its process" grep -q "GIT_CONFIG_KEY_0='url.https://github.com/.insteadOf'" "$BOOTSTRAP"
expect_true "bootstrap disables git terminal prompts" grep -q 'GIT_TERMINAL_PROMPT=0' "$BOOTSTRAP"

# 3x2: manifest symmetry — bootstrap writes install-time manifests (skill-pack
# skills, bionic-owned hooks, agent role files); reset consumes them so
# removal works offline and survives repo renames.
expect_true "bootstrap writes skill-pack manifest" grep -qF '.pack-${name}.manifest' "$BOOTSTRAP"
expect_true "reset reads skill-pack manifest" grep -qF '.pack-${name}.manifest' "$RESET"
expect_true "bootstrap writes hook manifest" grep -qF '.bionic-manifest' "$BOOTSTRAP"
expect_true "reset consumes hook manifest" grep -qF '.bionic-manifest' "$RESET"
expect_true "bootstrap writes agents manifest" grep -qF 'agents/.bionic-manifest' "$BOOTSTRAP"
expect_true "reset reads agents manifest" grep -qF 'agents/.bionic-manifest' "$RESET"
expect_true "reset has an agents leftover-audit block" grep -qF 'LEFTOVERS+=("agent ' "$RESET"

# 3x2b: agents removal is MANIFEST-ONLY — ~/.claude/agents/ is Claude Code's
# standard USER subagent directory, so attribution for removal comes from the
# install-time manifest alone, never a repo glob (deliberate divergence from
# the hooks precedent above, which does union repo+manifest).
expect_false "reset agents removal no longer globs repo agents/*.md" \
  grep -qF 'for agent in "${SCRIPT_DIR}"/agents/*.md' "$RESET"
expect_true "reset agents removal reads the manifest" \
  grep -qF 'if [ -f ~/.claude/agents/.bionic-manifest ]; then' "$RESET"

# 3x3: reset reverts account-mirror symlinks (and restores backups)
expect_true "reset handles account-mirror symlinks" grep -q 'Account-mirror symlinks' "$RESET"
expect_true "reset restores mirror backups" grep -qF '.bak-' "$RESET"

# 3y: profile superset rule — every active entry in any profile file must also
# appear in claude-config.everything.txt (the catalog is the superset). Trivial
# while everything.txt is the only profile; guards future profile additions.
_superset_missing=""
EVERYTHING="${REPO}/claude-config.everything.txt"
if [ -f "$EVERYTHING" ]; then
  for profile in "${REPO}"/claude-config.*.txt; do
    [ "$profile" = "$EVERYTHING" ] && continue
    while IFS= read -r line; do
      stripped="$(echo "$line" | sed 's/^[[:space:]]*//')"
      [ -z "$stripped" ] && continue
      case "$stripped" in "#"*) continue ;; esac
      if ! grep -qxF "$line" "$EVERYTHING"; then
        _superset_missing="${_superset_missing}$(basename "$profile"): ${line}\n"
      fi
    done < "$profile"
  done
fi
expect_eq "every profile entry appears in claude-config.everything.txt" "" "$_superset_missing"

# 3z: core/everything disjoint — an active entry duplicated in both files is
# redundant (core always applies) and hides drift.
_overlap=""
if [ -f "$EVERYTHING" ]; then
  while IFS= read -r line; do
    stripped="$(echo "$line" | sed 's/^[[:space:]]*//')"
    [ -z "$stripped" ] && continue
    case "$stripped" in "#"*) continue ;; esac
    if grep -qxF "$line" "$CONFIG"; then
      _overlap="${_overlap}${line}\n"
    fi
  done < "$EVERYTHING"
fi
expect_eq "no active entry appears in both core and everything profiles" "" "$_overlap"

# ============================================================
# SECTION 4: Hook file consistency
# ============================================================

echo ""
echo "=== Section 4: Hook file consistency ==="

# Epic-17 W4 S9 (spec AC-9): hooks/*.test.sh moved to tests/, so hooks/ no longer
# holds test files at all and tests/ is no longer hook-exclusive — a bare
# existence scan of tests/*.test.sh can't tell a hook's test apart from an
# unrelated suite like doctor.test.sh (neither has a hooks/*.sh namesake, for
# different reasons). 4b's orphan direction (a lingering test for a deleted
# hook) needs to know WHICH tests/*.test.sh are hook-derived; this manifest is
# that fact, fixed at the move and re-checked below for drift rather than
# re-derived from directory placement.
TESTS_DIR="${REPO}/tests"
HOOK_TEST_NAMES="agent-context-guard canonical-sdlc-evidence-gate canonical-sdlc-governing-skill context-spend dispatch-preflight execution-recorder farm-out-reminder landing-gate preflight-probe protect-database protect-main session-poker session-sweeper stop-check stop-guard stop-orders"

# 4a: Every non-test .sh in hooks/ has a matching tests/<name>.test.sh
_hooks_missing_tests=""
for hook in "${BIONIC_HOOKS_DIR}/"*.sh; do
  [ -f "$hook" ] || continue
  name="$(basename "$hook")"
  if echo "$name" | grep -q '\.test\.sh$'; then
    continue
  fi
  testfile="${TESTS_DIR}/${name%.sh}.test.sh"
  if [ ! -f "$testfile" ]; then
    _hooks_missing_tests="${_hooks_missing_tests}${name} "
  fi
done
expect_eq "every hook .sh has a matching tests/*.test.sh" "" "$_hooks_missing_tests"

# 4b: Every manifested hook test has a corresponding non-test hook (orphan check).
# The manifest also gets checked for staleness in the other direction — a hook
# test that exists on disk but fell out of HOOK_TEST_NAMES would silently escape
# this whole section, so 4b's own no-drift arm below closes that gap.
_tests_missing_hooks=""
for name in $HOOK_TEST_NAMES; do
  testfile="${TESTS_DIR}/${name}.test.sh"
  if [ ! -f "$testfile" ]; then
    _tests_missing_hooks="${_tests_missing_hooks}${name}.test.sh(manifested-but-absent) "
    continue
  fi
  if [ ! -f "${BIONIC_HOOKS_DIR}/${name}.sh" ]; then
    _tests_missing_hooks="${_tests_missing_hooks}${name}.test.sh "
  fi
done
expect_eq "every manifested hook test has a corresponding hook .sh" "" "$_tests_missing_hooks"

# 4b-drift: no test file living alongside the manifested ones LOOKS like a hook
# test (same basename shape as a real hooks/*.sh) but is missing from the
# manifest — that would be an orphan 4b can't see. Scoped to names that are
# currently real hooks/*.sh basenames, so unrelated suites (doctor.test.sh, etc.)
# never enter this comparison.
_unmanifested_hook_tests=""
for hook in "${BIONIC_HOOKS_DIR}/"*.sh; do
  [ -f "$hook" ] || continue
  name="$(basename "$hook" .sh)"
  echo "$name" | grep -q '\.test$' && continue
  if [ -f "${TESTS_DIR}/${name}.test.sh" ]; then
    case " $HOOK_TEST_NAMES " in
      *" $name "*) : ;;
      *) _unmanifested_hook_tests="${_unmanifested_hook_tests}${name}.test.sh " ;;
    esac
  fi
done
expect_eq "no hook's test file is missing from HOOK_TEST_NAMES" "" "$_unmanifested_hook_tests"

# 4c: Every hook file referenced inside MANAGED_HOOKS in bootstrap exists in hooks/
_missing_managed_hooks=""
while IFS= read -r line; do
  # Lines look like: "PreToolUse|Bash|~/.claude/hooks/foo.sh"
  if echo "$line" | grep -qE '"[^"]+\|[^|]*\|[^"]+\.sh"'; then
    hookfile="$(echo "$line" | grep -oE 'hooks/[^"]+\.sh' | head -1)"
    if [ -n "$hookfile" ]; then
      basename_hook="$(basename "$hookfile")"
      if [ ! -f "${BIONIC_HOOKS_DIR}/${basename_hook}" ]; then
        _missing_managed_hooks="${_missing_managed_hooks}${basename_hook} "
      fi
    fi
  fi
done < <(grep -A 20 'MANAGED_HOOKS=(' "$BOOTSTRAP" | grep -v 'MANAGED_HOOKS=(')
expect_eq "all MANAGED_HOOKS entries exist in hooks/ dir" "" "$_missing_managed_hooks"

# 4d: MANAGED_HOOKS includes protect-main.sh
expect_true "MANAGED_HOOKS includes protect-main.sh" grep -q 'protect-main\.sh' "$BOOTSTRAP"

# 4e: MANAGED_HOOKS includes protect-database.sh
expect_true "MANAGED_HOOKS includes protect-database.sh" grep -q 'protect-database\.sh' "$BOOTSTRAP"

# 4h: canonical-sdlc-evidence-gate.sh moved out of MANAGED_HOOKS into
# skills/canonical-sdlc/SKILL.md's frontmatter hooks: block (session-20260814-
# wave-detector-terminal-state, R1) — absent from the global array (the shell's
# bare `grep` is ugrep with ignore-files active and lies about absence, so this
# goes through /usr/bin/grep), present as a PreToolUse|Bash command entry in
# the skill frontmatter.
expect_false "MANAGED_HOOKS no longer includes canonical-sdlc-evidence-gate.sh (moved to SKILL.md frontmatter)" \
  /usr/bin/grep -qF '"PreToolUse|Bash|~/.claude/hooks/canonical-sdlc-evidence-gate.sh"' "$BOOTSTRAP"

# Shared with cross-gate-agreement.test.sh and installer-behavior.test.sh via
# tests/lib/frontmatter-parser.sh (epic-17 W4 AC-12 dedupe).
expect_true "skills/canonical-sdlc/SKILL.md frontmatter registers canonical-sdlc-evidence-gate.sh as PreToolUse|Bash" \
  skill_hooks_has "${BIONIC_SKILLS_DIR}/canonical-sdlc/SKILL.md" PreToolUse Bash \
    '${CLAUDE_PLUGIN_ROOT}/hooks/canonical-sdlc-evidence-gate.sh'

# 4i: farm-out-reminder.sh moved out of MANAGED_HOOKS into skills/canonical-sdlc/
# SKILL.md's frontmatter hooks: block (session-20260815-landing-supervision T5,
# AC-6) — it guards a workflow preference rather than irreversible damage, so it
# now binds only in armed sessions, same pattern as canonical-sdlc-evidence-gate.sh
# above (4h) except it shares the PreToolUse|Bash matcher entry with that hook
# rather than opening its own.
expect_false "MANAGED_HOOKS no longer includes farm-out-reminder.sh (moved to SKILL.md frontmatter)" \
  /usr/bin/grep -qF '"PreToolUse|Bash|~/.claude/hooks/farm-out-reminder.sh"' "$BOOTSTRAP"

expect_true "skills/canonical-sdlc/SKILL.md frontmatter registers farm-out-reminder.sh as PreToolUse|Bash" \
  skill_hooks_has "${BIONIC_SKILLS_DIR}/canonical-sdlc/SKILL.md" PreToolUse Bash \
    '${CLAUDE_PLUGIN_ROOT}/hooks/farm-out-reminder.sh'

# 4m: hooks/ dir contains at least one non-test hook
_hook_count=0
for hook in "${BIONIC_HOOKS_DIR}/"*.sh; do
  [ -f "$hook" ] || continue
  if ! echo "$(basename "$hook")" | grep -q '\.test\.sh$'; then
    _hook_count=$((_hook_count + 1))
  fi
done
expect_true "hooks/ contains at least one non-test hook" [ "$_hook_count" -gt 0 ]

# 4p: both canonical-sdlc hooks pin exactly one supported version and neither
# carries a version-dispatch chain.
_egate="${BIONIC_HOOKS_DIR}/canonical-sdlc-evidence-gate.sh"
_gskill="${BIONIC_HOOKS_DIR}/canonical-sdlc-governing-skill.sh"
expect_true "evidence-gate hook pins SUPPORTED_SDLC_VERSION" \
  grep -q 'SUPPORTED_SDLC_VERSION=14' "$_egate"
expect_true "governing-skill hook pins SUPPORTED_SDLC_VERSION" \
  grep -q 'SUPPORTED_SDLC_VERSION=14' "$_gskill"
# The contract: comparing SDLC_VERSION to the $SUPPORTED_SDLC_VERSION *variable*
# is the one legitimate check; comparing it to a version *literal* is the
# regression. Three shapes a reintroduced version arm actually takes in bash:
#   1. a dereference compared to a digit — [ "$SDLC_VERSION" != "11" ],
#      [[ ${SDLC_VERSION} == 9 ]], [ "$SDLC_VERSION" -ne 10 ]
#   2. a bare name compared to a digit in arithmetic context — (( SDLC_VERSION == 11 ))
#      (two-char operators only, so the SUPPORTED_SDLC_VERSION=14 pin is not flagged)
#   3. a case dispatch — case "$SDLC_VERSION" in 11) ...
_vdispatch_re='\$\{?(SUPPORTED_)?SDLC_VERSION\}?"?[[:space:]]*(=|==|!=|-eq|-ne|-lt|-le|-gt|-ge)[[:space:]]*"?[0-9]'
_vdispatch_re="${_vdispatch_re}|(^|[^A-Z_])SDLC_VERSION[[:space:]]*(==|!=|-eq|-ne)[[:space:]]*\"?[0-9]"
_vdispatch_re="${_vdispatch_re}|case[[:space:]]+\"?\\\$\\{?SDLC_VERSION"
expect_false "evidence-gate hook has no version-dispatch chain" \
  grep -qE "$_vdispatch_re" "$_egate"
expect_false "governing-skill hook has no version-dispatch chain" \
  grep -qE "$_vdispatch_re" "$_gskill"

# 4r: README promotes canonical-sdlc as flagship (Wave 6 closure; Wave 7 repointed link)
expect_true "README has a Canonical SDLC pattern subsection" \
  grep -q '\*\*Canonical SDLC\*\*' "${REPO}/README.md"
expect_true "README Skills row mentions bionic:canonical-sdlc as flagship" \
  grep -q 'bionic:canonical-sdlc' "${REPO}/README.md"
expect_true "README Hooks list mentions both canonical-sdlc hooks" \
  grep -qE 'canonical-sdlc-evidence-gate.*canonical-sdlc-governing-skill' "${REPO}/README.md"

# ============================================================
# SECTION 5: Shell alias marker consistency
# ============================================================

echo ""
echo "=== Section 5: Shell alias marker consistency ==="

# 5a: Bootstrap defines ALIAS_START containing 'bionic:start'
_bootstrap_start="$(grep 'ALIAS_START=' "$BOOTSTRAP" | head -1)"
expect_contains "bootstrap ALIAS_START contains bionic:start" "bionic:start" "$_bootstrap_start"

# 5b: Bootstrap defines ALIAS_END containing 'bionic:end'
_bootstrap_end="$(grep 'ALIAS_END=' "$BOOTSTRAP" | head -1)"
expect_contains "bootstrap ALIAS_END contains bionic:end" "bionic:end" "$_bootstrap_end"

# 5c: Reset defines ALIAS_START with the same value as bootstrap
_reset_start="$(grep 'ALIAS_START=' "$RESET" | head -1)"
expect_eq "reset ALIAS_START matches bootstrap ALIAS_START" "$_bootstrap_start" "$_reset_start"

# 5d: Reset defines ALIAS_END with the same value as bootstrap
_reset_end="$(grep 'ALIAS_END=' "$RESET" | head -1)"
expect_eq "reset ALIAS_END matches bootstrap ALIAS_END" "$_bootstrap_end" "$_reset_end"

# 5e: Bootstrap uses bionic:start marker (may also reference old claude-setup:start for migration)
expect_true "bootstrap references bionic:start" grep -q 'bionic:start' "$BOOTSTRAP"
expect_true "npm-update advisory uses the inspected npm's absolute path (multi-node prefix safety)" \
  grep -q '{npmbin} install -g ${pkg}@latest' "$BOOTSTRAP"
expect_true "npm-update advisory resolves npmbin from command -v" \
  grep -q 'npmbin="$(command -v npm)"' "$BOOTSTRAP"
# The active start_marker variable must be bionic:start (not the legacy value)
_bs_active_marker="$(grep 'start_marker=' "$BOOTSTRAP" | grep -v 'old_start' | grep -v '#' | head -1)"
expect_contains "bootstrap active start_marker uses bionic:start" "bionic:start" "$_bs_active_marker"

# 5f: Reset uses bionic:start marker (no migration code — must not reference old claude-setup:start at all)
expect_true "reset references bionic:start" grep -q 'bionic:start' "$RESET"
expect_false "reset does not reference claude-setup:start" grep -q 'claude-setup:start' "$RESET"

# 5g: Bootstrap global-memory section uses bionic:start and bionic:end markers
expect_true "bootstrap global-memory start_marker is bionic:start" \
  grep -q 'bionic:start' "$BOOTSTRAP"
expect_true "bootstrap global-memory end_marker is bionic:end" \
  grep -q 'bionic:end' "$BOOTSTRAP"

# 5h: Reset global-memory section uses bionic:start and bionic:end markers
expect_true "reset global-memory start_marker is bionic:start" \
  grep -q 'bionic:start' "$RESET"
expect_true "reset global-memory end_marker is bionic:end" \
  grep -q 'bionic:end' "$RESET"

# 5i: Bootstrap verification section checks for bionic:start in shell rc
_bootstrap_verify_shell="$(grep -A 3 '"  Shell alias:"' "$BOOTSTRAP" 2>/dev/null || grep -A 3 'Shell alias:' "$BOOTSTRAP" | head -6)"
expect_contains "bootstrap verification checks bionic:start in shell rc" "bionic:start" "$_bootstrap_verify_shell"

# 5j: Reset verification section checks for bionic:start in shell rc
_reset_verify_shell="$(grep -A 3 'Shell alias:' "$RESET" | head -8)"
expect_contains "reset verification checks bionic:start in shell rc" "bionic:start" "$_reset_verify_shell"

# ============================================================
# SECTION 6: .claude/rules/ roster
# ============================================================

echo ""
echo "=== Section 6: .claude/rules/ roster ==="

# Epic-17 W4 remediation fold (review F-3). The .gitignore negation pair made
# `.claude/rules/` a permanently committable surface — the first part of `.claude/`
# a fresh clone receives. S4 audited its five files once, by hand, for machine paths
# and consumer-project names. A one-time audit does not survive the next addition,
# and nothing else in the suite looks at this directory, so the roster itself is the
# wall: a sixth committed file, a renamed one, or a subdirectory trips this and gets
# the same read S4's five got.
#
# git ls-files, not the filesystem, on purpose. What matters is what a clone RECEIVES.
# An untracked scratch file under .claude/rules/ is machine-local and none of this
# suite's business; a COMMITTED one is a new public surface. `--` separates the
# pathspec so a directory named like a flag cannot be misread, and the pathspec is
# non-empty by construction here (the five files below), which is what keeps this
# from being the silent zero-match failure git-grep-style pathspecs are prone to.
EXPECTED_RULES="agent-discipline.md
bootstrap-install.md
git-worktree-docs.md
hook-authoring.md
test-harness.md"

_actual_rules="$(cd "$REPO" && git ls-files -- .claude/rules/ | sed 's#^\.claude/rules/##' | LC_ALL=C sort)"
expect_eq "the committed .claude/rules/ roster is exactly the five audited files" \
  "$EXPECTED_RULES" "$_actual_rules"

# Stated as its own arm so a subdirectory reports as a subdirectory rather than as an
# opaque roster mismatch: any tracked path under .claude/rules/ with a further slash in
# it is a nested tree the audit never covered.
_nested_rules="$(cd "$REPO" && git ls-files -- .claude/rules/ | sed 's#^\.claude/rules/##' | grep '/' || true)"
expect_eq "no committed subdirectory under .claude/rules/" "" "$_nested_rules"

# ============================================================
# Results
# ============================================================

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
