#!/usr/bin/env bash
#
# claude-bootstrap.sh
# Sets up Claude Code plugins, skills, and dependencies.
# Idempotent — safe to run multiple times; produces the same result.
#
# Usage:
#   ./claude-bootstrap.sh                                # core profile
#   ./claude-bootstrap.sh claude-config.everything.txt   # core + catalog profile
#
# Profile files are layered on top of claude-config.txt (core). Profiles are
# additive-only; exact-duplicate entries are deduped; for single-valued
# settings (env-var by key, statusline) the last file wins.
#
# Exit codes:
#   0  success (including warnings and env-gated skips)
#   1  ran to completion but one or more steps failed — fix and re-run
#   2  could not run: hard prerequisite failed in preflight
#
set -euo pipefail

cleanup() { rm -f ~/.claude/settings.json.tmp ~/.claude/CLAUDE.md.tmp; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
START_TS="$(date +%s)"

# ─── Config profiles ─────────────────────────────────────────────────────────
# Core always applies; positional args are additional profile files.

usage() {
  cat <<'USAGE'
claude-bootstrap.sh — set up Claude Code plugins, skills, and dependencies.

Usage:
  ./claude-bootstrap.sh [profile-config.txt ...]

  ./claude-bootstrap.sh                                # core profile only
  ./claude-bootstrap.sh claude-config.everything.txt   # core + full catalog

Profiles are layered on top of claude-config.txt (core): additive-only,
exact-duplicate entries deduped, last file wins for single-valued settings
(env-var by key, statusline). Idempotent — re-run anytime; completed steps
are skipped. Undo with ./claude-reset.sh (same profile arguments).

Environment:
  RETRY_MAX=N     retry attempts for network steps (default 3)
  NO_COLOR=1      disable colored glyphs

Exit codes:
  0  success (env-gated skips and warnings included)
  1  ran to completion but one or more steps failed — fix and re-run
  2  could not run: hard prerequisite failed in preflight
USAGE
}

CONFIG_FILES=("${SCRIPT_DIR}/claude-config.txt")
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
  esac
  if [ ! -f "$arg" ]; then
    echo "ERROR: profile file not found: ${arg}" >&2
    echo "Run ./claude-bootstrap.sh --help for usage." >&2
    exit 2
  fi
  CONFIG_FILES+=("$arg")
done

# ─── Structural git environment ──────────────────────────────────────────────
# claude plugin install clones GitHub repos via SSH (git@github.com:) even for
# public repos; fresh machines without a default GitHub SSH key fail with
# "Permission denied (publickey)". Rewrite SSH→HTTPS for this process only —
# the user's ~/.gitconfig is never touched. GIT_TERMINAL_PROMPT=0 converts any
# would-be credential prompt (which would hang the run) into a fast failure
# that run_retry captures.
export GIT_CONFIG_COUNT=1 \
       GIT_CONFIG_KEY_0='url.https://github.com/.insteadOf' \
       GIT_CONFIG_VALUE_0='git@github.com:' \
       GIT_TERMINAL_PROMPT=0

# ─── Platform Detection ─────────────────────────────────────────────────────

source "${SCRIPT_DIR}/lib/platform.sh"

# ─── Sections ────────────────────────────────────────────────────────────────
# Bump SECTION_TOTAL when adding a section() call.

SECTION_TOTAL=23
SECTION_IDX=0
CURRENT_SECTION=""
section() {
  local title="$1" count="${2:-}"
  SECTION_IDX=$((SECTION_IDX + 1))
  CURRENT_SECTION="$title"
  echo ""
  if [ -n "$count" ]; then
    printf '[%2d/%d] %s — %s items\n' "$SECTION_IDX" "$SECTION_TOTAL" "$title" "$count"
  else
    printf '[%2d/%d] %s\n' "$SECTION_IDX" "$SECTION_TOTAL" "$title"
  fi
}

# Count active entries of a type across all config files (deduped).
config_count() {
  cat "${CONFIG_FILES[@]}" | grep -v '^\s*#' | grep -v '^\s*$' | awk '!seen[$0]++' \
    | grep -cE "^[[:space:]]*${1}[[:space:]]*\|" || true
}

# ─── Config reader ──────────────────────────────────────────────────────────

# Reads all config files (core + profiles, deduped) and calls a callback for
# each entry of a given type. Usage: read_config <type> <callback>
#   callback receives: field1 field2 field3 (trimmed, pipe-delimited; f2 and f3 may be empty)
# The callback runs with stdin redirected to /dev/null: a child that reads
# stdin (e.g. a brew tap install's git clone) would otherwise consume the rest
# of the config stream and silently truncate the section.
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

# ─── Resilience ──────────────────────────────────────────────────────────────
#
# The install phase must run to completion even when individual steps fail
# (network blips, renamed packages, registry hiccups). Every install step
# reports through one path — step_start then step_ok/step_cached/step_skip/
# step_fail — which both prints the live status line and appends a uniform
# record to STEP_RECORDS for the end-of-run report. step_fail never aborts;
# hard failures (exit 2) live exclusively in preflight. Network operations go
# through run_retry (exponential backoff, stdin detached).
#
# STEP_RECORDS entry: status|category|section|name|remediation|detail
#   status   ∈ ok|cached|skip|warn|fail
#   category ∈ prereq|network|auth|env|tool|config|fs|state
#   detail is LAST so embedded pipes can't break parsing; newlines flattened.

INSTALL_FAILURES=()
STEP_RECORDS=()
RETRY_MAX="${RETRY_MAX:-3}"
RUN_ERR=""
RUN_ATTEMPT=1
STEP_NAME=""
STEP_T0=0
CURRENT_SECTION="${CURRENT_SECTION:-}"

# Color only the glyphs, only on a TTY. Piped output is byte-identical minus
# color, so captured logs replay cleanly.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_YELLOW=""; C_RED=""; C_BOLD=""; C_RESET=""
fi

# _init_run_log — tee the whole run to ~/.claude/logs/, newest 5 kept.
# MUST run after color detection ([ -t 1 ] above): the exec turns stdout
# into a pipe, so testing later would kill terminal colors. The log branch
# strips ANSI so captured logs stay clean while the terminal keeps color.
# Logging failure never blocks the run (a bootstrap that can't log must
# still bootstrap).
BOOTSTRAP_LOG=""
_init_run_log() {
  local dir="$HOME/.claude/logs" old
  { mkdir -p "$dir" 2>/dev/null && [ -w "$dir" ]; } || {
    echo "  ${C_YELLOW}⚠${C_RESET} could not create ${dir} — run log disabled"
    return 0
  }
  BOOTSTRAP_LOG="${dir}/bootstrap-$(date -u +%Y%m%dT%H%M%SZ).log"
  ls -1t "${dir}"/bootstrap-*.log 2>/dev/null | tail -n +5 | while IFS= read -r old; do
    rm -f "$old"
  done
  exec > >(tee >(sed -E $'s/\x1b\\[[0-9;]*m//g' >> "$BOOTSTRAP_LOG")) 2>&1
  return 0
}

# run_retry <cmd...> — runs cmd with stdout+stderr captured into RUN_ERR and
# stdin detached, retrying up to RETRY_MAX times with exponential backoff
# (2s, 4s, 8s...). Sets RUN_ATTEMPT to the attempt count. Returns 0 on
# success, 1 if every attempt fails. Never aborts the script.
run_retry() {
  local n=1 delay=2
  while :; do
    if RUN_ERR="$("$@" </dev/null 2>&1)"; then RUN_ATTEMPT="$n"; return 0; fi
    case "$(classify_err "$RUN_ERR")" in
      cert\|*|perms\|*) RUN_ATTEMPT="$n"; return 1 ;;  # deterministic — retry can't help
    esac
    if [ "$n" -ge "$RETRY_MAX" ]; then RUN_ATTEMPT="$n"; return 1; fi
    sleep "$delay"
    n=$((n + 1)); delay=$((delay * 2))
  done
}

# classify_err <text> — map captured error output to "class|hint" on stdout.
# class ∈ cert|perms|net|unknown; unknown carries an empty hint so callers
# keep their own remediation. cert/perms are DETERMINISTIC — retrying cannot
# change the outcome, so run_retry short-circuits them (field incident
# 2026-07-21: a broken OpenSSL CA store burned 3 retries × N steps with an
# EACCES hint that sent the user down the wrong path).
classify_err() {
  local t
  t="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$t" in
    *unable_to_get_issuer_cert_locally*|*self_signed_cert_in_chain*|*'unable to get local issuer certificate'*)
      printf '%s' "cert|run 'brew postinstall openssl@3', then re-run ./claude-bootstrap.sh" ;;
    *eacces*)
      printf '%s' "perms|fix npm's global prefix (e.g. npm config set prefix ~/.npm-global), then re-run ./claude-bootstrap.sh" ;;
    *enotfound*|*eai_again*|*etimedout*)
      printf '%s' "net|check network/VPN/proxy, then re-run ./claude-bootstrap.sh" ;;
    *)
      printf 'unknown|' ;;
  esac
}

# record_fail <message> — note a non-fatal install failure (legacy summary).
record_fail() { INSTALL_FAILURES+=("$1"); }

# record_step <status> <category> <name> <remediation> <detail>
record_step() {
  local detail="${5:-}"
  detail="$(printf '%s' "$detail" | tr '\n' ' ' | cut -c1-160)"
  STEP_RECORDS+=("${1}|${2}|${CURRENT_SECTION:-}|${3}|${4:-}|${detail}")
}

# step_start <display-name> — begin a step line: "  name... "
step_start() {
  STEP_NAME="$1"
  STEP_T0="$(date +%s)"
  RUN_ATTEMPT=1
  echo -n "  ${1}... "
}

# Append " (Ns)" for steps that took ≥5s.
_step_dur() {
  local dt=$(( $(date +%s) - STEP_T0 ))
  if [ "$dt" -ge 5 ]; then printf ' (%ss)' "$dt"; fi
}

# step_ok <category> [note]
step_ok() {
  local note="${2:-}"
  if [ -z "$note" ] && [ "${RUN_ATTEMPT:-1}" -gt 1 ]; then
    note="succeeded on retry ${RUN_ATTEMPT}"
  fi
  echo "${C_GREEN}✓${C_RESET}${note:+ (${note})}$(_step_dur)"
  record_step ok "$1" "$STEP_NAME" "" "$note"
}

# step_cached <category> [note]
step_cached() {
  local note="${2:-already installed}"
  echo "${C_GREEN}✓${C_RESET} (${note})"
  record_step cached "$1" "$STEP_NAME" "" "$note"
}

# step_skip <category> <reason> [remediation]
step_skip() {
  echo "${C_YELLOW}⚠${C_RESET} skipped — ${2}"
  record_step skip "$1" "$STEP_NAME" "${3:-}" "$2"
}

# step_warn <category> <reason> [remediation]
step_warn() {
  echo "${C_YELLOW}⚠${C_RESET} ${2}"
  record_step warn "$1" "$STEP_NAME" "${3:-}" "$2"
}

# step_fail <category> <detail> [remediation] — record and CONTINUE. A
# classified detail (cert/perms/net) overrides the caller's canned hint so
# the report names the real cause, not a guess.
step_fail() {
  local remediation="${3:-re-run ./claude-bootstrap.sh — completed steps are skipped}"
  local _c _hint
  _c="$(classify_err "$2")"; _hint="${_c#*|}"; _c="${_c%%|*}"
  if [ "$_c" != "unknown" ] && [ -n "$_hint" ]; then remediation="$_hint"; fi
  echo "${C_RED}✗${C_RESET} failed (continuing)$(_step_dur)"
  record_step fail "$1" "$STEP_NAME" "$remediation" "$2"
  record_fail "${STEP_NAME}: ${2}"
}

# step_stream <category> <remediation> <cmd...> — for steps expected to run
# >30s (big downloads): stream the child's own output indented instead of
# capturing it, so long steps have a heartbeat. The child's progress lines are
# plain text when piped, so captured logs stay clean. No run_retry — heavy
# downloaders retry internally, and a silent from-scratch re-download is worse
# UX than a visible failure with a re-run remediation. Call after step_start.
step_stream() {
  local category="$1" remediation="$2"; shift 2
  local name="$STEP_NAME" t0="$STEP_T0"
  echo ""
  if "$@" </dev/null 2>&1 | sed 's/^/    /'; then
    step_start "$name"; STEP_T0="$t0"
    step_ok "$category"
  else
    step_start "$name"; STEP_T0="$t0"
    step_fail "$category" "failed (see output above)" "$remediation"
  fi
  return 0
}

# ─── Helpers ─────────────────────────────────────────────────────────────────

# Placed here (not immediately after the function definition above) so the
# test harness's Resilience→Helpers extraction (tests/installer-behavior.
# test.sh) doesn't source-and-execute this call: that range is sourced
# wholesale to expose the function for direct testing, and a bare top-level
# call inside it would exec-tee the test script's own stdout. Still runs
# before any real bootstrap output.
_init_run_log

# Formulae with heavy dependency trees (>30s installs) stream brew's own
# progress instead of installing silently — see step_stream.
STREAM_HEAVY_BREW=" fastlane "

ensure_cmd() {
  local cmd="$1" pkg="${2:-$1}"
  step_start "$cmd"
  if command -v "$cmd" &>/dev/null; then
    step_cached tool
    return 0
  fi
  case "$STREAM_HEAVY_BREW" in
    *" ${cmd} "*)
      step_stream network "run 'brew install ${pkg}' by hand, then re-run ./claude-bootstrap.sh" \
        brew install "$pkg" --quiet
      return 0
      ;;
  esac
  if run_retry brew install "$pkg" --quiet; then
    step_ok network
  else
    step_fail network "$RUN_ERR" "run 'brew install ${pkg}' by hand (if the formula was renamed, update its line in claude-config), then re-run ./claude-bootstrap.sh"
  fi
  return 0
}

# Installs a Homebrew *cask* (SDKs / apps not shipped as core formulae, e.g. the
# Google Cloud CLI). binary = the command it provides on PATH; token = the cask
# name. Casks need `brew install --cask`, which plain ensure_cmd cannot do.
do_install_brew_cask() {
  local binary="$1" token="${2:-$1}"
  step_start "${binary} (cask: ${token})"
  if command -v "$binary" &>/dev/null || brew list --cask "$token" &>/dev/null; then
    step_cached tool
    return 0
  fi
  # Casks are the big downloads (gcloud-cli is ~600 MB) — stream brew's progress.
  step_stream network "run 'brew install --cask ${token}' by hand, then re-run ./claude-bootstrap.sh" \
    brew install --cask "$token" --quiet
  return 0
}

do_install_brew_dep() {
  local binary="$1" pkg="${2:-$1}"
  ensure_cmd "$binary" "$pkg"
}

# do_preflight_node — node is needed by the registry TLS probe (F1) and the
# npm channel of the claude CLI install. Formerly hidden inside the claude-CLI
# else-branch behind `command -v claude` with its failure swallowed by
# `|| true` — a machine with claude but no node reached the npm steps with no
# npm at all, and a brew failure was misreported as a claude-CLI failure.
# Never aborts: with the native-installer fallback (F2) the claude CLI no
# longer requires node, and npm-dependent steps fail individually with
# classified hints.
do_preflight_node() {
  if command -v node &>/dev/null; then
    step_cached prereq "$(node -v 2>/dev/null || echo present)"
  elif run_retry brew install node --quiet; then
    step_ok prereq "$(node -v 2>/dev/null || echo installed)"
  else
    step_fail prereq "$RUN_ERR" "run 'brew install node' by hand, then re-run ./claude-bootstrap.sh"
  fi
  return 0
}

# _node_probe — hit the npm registry with node itself. npm/pnpm/npx verify
# TLS through OpenSSL's CA store (Homebrew node is built shared_openssl),
# NOT the macOS keychain that curl uses — so curl 200 + node cert-fail is
# exactly the broken-CA-store signature (field incident 2026-07-21: missing
# /opt/homebrew/etc/openssl@3/cert.pem symlink).
_node_probe() {
  node -e 'require("https").get("https://registry.npmjs.org/-/ping",function(r){process.exit(r.statusCode===200?0:1)}).on("error",function(e){console.error(e.code||e.message);process.exit(1)})' 2>&1
}

# do_preflight_registry_tls — probe; on cert-class failure auto-repair the
# one known cause (brew postinstall openssl@3 — recreates the cert.pem
# symlink, idempotent) and re-probe. Unrepaired cert store is a hard
# preflight failure (exit 2): every npm/pnpm/npx step downstream would fail.
# Non-cert failures warn and continue (mirrors the curl reachability arm).
do_preflight_registry_tls() {
  local out
  if ! command -v node &>/dev/null; then
    step_skip prereq "node unavailable — probe skipped (npm installs may fail)"
    return 0
  fi
  if out="$(_node_probe)"; then
    step_ok prereq
    return 0
  fi
  case "$(classify_err "$out")" in
    cert\|*)
      brew postinstall openssl@3 >/dev/null 2>&1 || true
      if out="$(_node_probe)"; then
        step_warn prereq "CA store was broken — auto-repaired (brew postinstall openssl@3)"
        return 0
      fi
      echo "${C_RED}✗${C_RESET}"
      echo ""
      echo "  node cannot verify registry.npmjs.org's TLS certificate (${out})."
      echo "  Auto-repair (brew postinstall openssl@3) did not resolve it."
      echo "  Every npm/pnpm install would fail. Fix the OpenSSL CA store, then"
      echo "  re-run ./claude-bootstrap.sh"
      exit 2
      ;;
    *)
      step_warn prereq "registry probe failed (${out}) — npm installs may fail" "check network/VPN/proxy"
      ;;
  esac
  return 0
}

# do_preflight_claude_cli — npm is the canonical channel (the Homebrew cask
# lags many versions). The official native installer is the fallback: it
# verifies TLS through the system keychain via curl, so it survives the
# broken-OpenSSL-CA-store failure that kills the npm channel (and is exactly
# what the field fix was on 2026-07-21). Hard-fails (exit 2) only when both
# channels are dead — the CLI is the bootstrap's one true prerequisite.
do_preflight_claude_cli() {
  local npm_err="" hint=""
  if command -v claude &>/dev/null; then
    step_cached prereq "$(claude --version 2>/dev/null | head -1 || echo present)"
    return 0
  fi
  if command -v npm &>/dev/null && run_retry npm install -g @anthropic-ai/claude-code@latest; then
    step_ok prereq "$(claude --version 2>/dev/null | head -1 || echo installed)"
    return 0
  fi
  npm_err="${RUN_ERR:-npm unavailable}"
  if run_retry bash -c 'curl -fsSL https://claude.ai/install.sh | bash' \
     && { command -v claude &>/dev/null || [ -x "$HOME/.local/bin/claude" ]; }; then
    step_ok prereq "native installer — npm channel failed"
    return 0
  fi
  hint="$(classify_err "$npm_err")"; hint="${hint#*|}"
  echo "${C_RED}✗${C_RESET}"
  echo ""
  echo "  Could not install the claude CLI by either channel. Install it manually:"
  echo "    npm:    npm install -g @anthropic-ai/claude-code@latest"
  echo "    native: curl -fsSL https://claude.ai/install.sh | bash"
  if [ -n "$hint" ]; then
    echo "  npm channel failure looks like: ${hint}"
  fi
  echo "  then re-run ./claude-bootstrap.sh"
  exit 2
}

do_install_npm_global() {
  local pkg="$1"
  step_start "$pkg"
  if npm list -g --depth=0 "$pkg" &>/dev/null; then
    step_cached tool
    return 0
  fi
  if run_retry npm install -g "$pkg" --silent; then
    step_ok network
  else
    step_fail network "$RUN_ERR" "run 'npm install -g ${pkg}' by hand (EACCES → fix npm's global prefix), then re-run ./claude-bootstrap.sh"
  fi
  return 0
}

do_install_uv_tool() {
  local pkg="$1" binary="${2:-$1}"
  step_start "${pkg} (→ ${binary})"
  if command -v "$binary" &>/dev/null; then
    step_cached tool
    return 0
  fi
  if run_retry uv tool install "$pkg" --quiet; then
    step_ok network
  else
    step_fail network "$RUN_ERR" "run 'uv tool install ${pkg}' by hand, then re-run ./claude-bootstrap.sh"
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
  step_start "${pkg} (pnpm store)"
  if run_retry pnpm store add "${pkg}@latest"; then
    step_ok network
  else
    step_fail network "$RUN_ERR"
  fi
  return 0
}

do_build_local_package() {
  local pkg="$1"
  local pkg_dir="${SCRIPT_DIR}/${pkg}"

  # Only build if the directory has a package.json (it's a local Node package)
  [ -f "${pkg_dir}/package.json" ] || return 0

  step_start "${pkg} (npm install && build)"
  _build_local_pkg() { cd "$pkg_dir" && npm install --silent && npm run build --silent; }
  if run_retry _build_local_pkg; then
    step_ok network
  else
    step_fail network "$RUN_ERR" "cd ${pkg} && npm install && npm run build, then re-run ./claude-bootstrap.sh"
  fi
  return 0
}

# Registers an MCP server via claude mcp add. If env_vars is provided (comma-separated
# list of env var names, e.g. "KEY1,KEY2"), reads their values from the current shell
# environment and passes them as -e flags. Skips with a warning if any are missing.
do_configure_mcp_server() {
  local name="$1" pkg="$2" env_vars="${3:-}"

  step_start "${name} (${pkg})"

  # Check if already configured via claude mcp
  if claude mcp get "$name" &>/dev/null; then
    step_cached state "already configured"
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
      step_skip auth "${missing[*]} not set" "export ${missing[*]} in your shell rc (the config file comments say where to get credentials), then re-run ./claude-bootstrap.sh"
      return 0
    fi
  fi

  # Check if the package exists as a local subdirectory with a built server
  local local_server="${SCRIPT_DIR}/${pkg}/dist/server.js"

  if [ -f "$local_server" ]; then
    # Local package — resolve absolute path and register via claude mcp add
    local abs_path
    abs_path="$(cd "$(dirname "$local_server")" && pwd)/$(basename "$local_server")"
    if run_retry claude mcp add "$name" -s user ${env_flags[@]+"${env_flags[@]}"} -- node "$abs_path"; then
      step_ok network "local"
    else
      step_fail network "$RUN_ERR"
    fi
  else
    # Remote package — register via claude mcp add
    if run_retry claude mcp add "$name" -s user ${env_flags[@]+"${env_flags[@]}"} -- npx -y "$pkg"; then
      step_ok network
    else
      step_fail network "$RUN_ERR"
    fi
  fi
  return 0
}

do_install_marketplace() {
  local name="$1"
  step_start "$name"
  local output
  # First attempt is also the idempotency check: an already-added marketplace
  # exits non-zero with "already" in the message — that's success, not a retry.
  if output=$(claude plugin marketplace add "$name" </dev/null 2>&1); then
    step_ok network
    return 0
  fi
  if echo "$output" | grep -qi "already"; then
    step_cached state "already added"
    return 0
  fi
  # Genuine failure (network, auth, bad name) — retry, then record and continue.
  if run_retry claude plugin marketplace add "$name"; then
    step_ok network
  else
    step_fail network "${RUN_ERR:-$output}" "check network access to github.com, then re-run ./claude-bootstrap.sh"
  fi
  return 0
}

do_install_plugin() {
  local plugin="$1" source="$2"
  step_start "${plugin} (${source})"
  if claude plugin list 2>&1 | grep -q "${plugin}@${source}"; then
    step_cached state
    return 0
  fi
  if run_retry claude plugin install "${plugin}@${source}"; then
    step_ok network
  else
    step_fail network "$RUN_ERR" "run 'claude plugin install ${plugin}@${source}' by hand, then re-run ./claude-bootstrap.sh"
  fi
  return 0
}

do_install_github_skill() {
  local name="$1" repo="$2"
  step_start "${name} (${repo})"
  local tmp="/tmp/claude-skill-${name}"
  rm -rf "$tmp"
  if ! run_retry git clone --depth 1 --quiet "https://github.com/${repo}.git" "$tmp"; then
    step_fail network "$RUN_ERR"
    rm -rf "$tmp"
    return 0
  fi
  mkdir -p ~/.claude/skills
  rm -rf ~/.claude/skills/"${name}"
  if cp -r "$tmp" ~/.claude/skills/"${name}"; then
    rm -rf ~/.claude/skills/"${name}"/.git
    step_ok network
  else
    step_fail fs "copy to ~/.claude/skills/${name} failed"
  fi
  rm -rf "$tmp"
  return 0
}

do_install_github_skill_pack() {
  local name="$1" repo="$2"
  step_start "${name} (${repo})"
  local tmp="/tmp/claude-skill-pack-${name}"
  rm -rf "$tmp"
  if ! run_retry git clone --depth 1 --quiet "https://github.com/${repo}.git" "$tmp"; then
    step_fail network "$RUN_ERR"
    rm -rf "$tmp"
    return 0
  fi
  mkdir -p ~/.claude/skills
  # Manifest of what this pack installed, so reset can remove exactly these
  # skills without re-cloning the repo (works offline).
  local manifest=~/.claude/skills/.pack-${name}.manifest
  : > "$manifest" || true
  local count=0 copy_fail=0
  for skill_dir in "$tmp"/.claude/skills/*/; do
    [ -d "$skill_dir" ] || continue
    local skill_name
    skill_name="$(basename "$skill_dir")"
    rm -rf ~/.claude/skills/"${skill_name}"
    if cp -r "$skill_dir" ~/.claude/skills/"${skill_name}"; then
      rm -rf ~/.claude/skills/"${skill_name}"/.git
      count=$((count + 1))
      echo "$skill_name" >> "$manifest" || true
    else
      copy_fail=1
    fi
  done
  rm -rf "$tmp"
  if [ "$copy_fail" -eq 0 ]; then
    step_ok network "${count} skills"
  else
    step_fail fs "some skills failed to copy (${count} succeeded)"
  fi
  return 0
}

do_install_local_skill() {
  local name="$1"
  local source="${SCRIPT_DIR}/skills/${name}"
  step_start "${name} (local)"
  if [ ! -d "$source" ] || [ ! -f "${source}/SKILL.md" ]; then
    step_fail config "skills/${name}/SKILL.md not found in ${SCRIPT_DIR}" "fix or remove the local-skill entry in the config file"
    return 0
  fi
  mkdir -p ~/.claude/skills
  rm -rf ~/.claude/skills/"${name}"
  if cp -r "$source" ~/.claude/skills/"${name}"; then
    step_ok fs
  else
    step_fail fs "copy to ~/.claude/skills/${name} failed"
  fi
  return 0
}

do_install_local_command() {
  local name="$1"
  local source="${SCRIPT_DIR}/commands/${name}.md"
  step_start "/${name} (local)"
  if [ ! -f "$source" ]; then
    step_fail config "commands/${name}.md not found in ${SCRIPT_DIR}" "fix or remove the local-command entry in the config file"
    return 0
  fi
  mkdir -p ~/.claude/commands
  if cp "$source" ~/.claude/commands/"${name}.md"; then
    step_ok fs
  else
    step_fail fs "copy to ~/.claude/commands/${name}.md failed"
  fi
  return 0
}

do_install_global_memory() {
  local file="$1"
  local source="${SCRIPT_DIR}/${file}"
  local target=~/.claude/CLAUDE.md
  local start_marker="<!-- bionic:start -->"
  local end_marker="<!-- bionic:end -->"
  local old_start="<!-- claude-setup:start -->"

  step_start "${file} → ~/.claude/CLAUDE.md"

  if [ ! -f "$source" ]; then
    step_fail config "${file} not found in ${SCRIPT_DIR}"
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
    if ! echo "$section" > "$target"; then
      step_fail fs "could not write ${target}"
      return 0
    fi
  elif grep -q "$start_marker" "$target"; then
    # Markers exist — replace managed section
    local tmp="${target}.tmp"
    if ! {
      awk -v start="$start_marker" '
        $0 == start { exit }
        { print }
      ' "$target"
      echo "$section"
      awk -v end="$end_marker" '
        found { print }
        $0 == end { found=1 }
      ' "$target"
    } > "$tmp"; then
      step_fail fs "could not write ${tmp}"
      return 0
    fi
    if ! mv "$tmp" "$target"; then
      step_fail fs "could not replace ${target}"
      return 0
    fi
  else
    # File exists, no markers — append with blank line separator
    if ! printf "\n%s\n" "$section" >> "$target"; then
      step_fail fs "could not append to ${target}"
      return 0
    fi
  fi

  step_ok fs
  return 0
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

verify_plugin_installed() {
  local plugin="$1" source="$2"
  if echo "${PLUGIN_LIST_OUTPUT:-}" | grep -q "${plugin}@${source}"; then
    echo "    ${plugin}@${source} ✓"
  else
    echo "    ${plugin}@${source} — not installed"
    verify_errors+=("${plugin}@${source} plugin — not installed")
  fi
}

# verify_playwright_registry — read-only registry walk: one status line per
# live registered installation; any missing pinned build becomes a named
# verify error (the chromium-* glob above only proves SOME build exists —
# it is blind to which one each registered project needs).
verify_playwright_registry() {
  local links="${PLAYWRIGHT_CACHE}/.links" f target ver missing label hint
  [ -d "$links" ] || return 0
  for f in "$links"/*; do
    [ -f "$f" ] || continue   # skips unexpanded glob + non-file entries (set -e safety)
    target="$(cat "$f" 2>/dev/null || true)"
    { [ -n "$target" ] && [ -d "$target" ]; } || continue   # dangling: nothing to verify
    label="${target%/node_modules/playwright-core}"
    ver="$(jq -r '.version // "unknown"' "$target/package.json" 2>/dev/null || echo unknown)"
    missing="$(_pw_link_missing "$target")" || continue      # unreadable demands: skip
    if [ -z "$missing" ]; then
      echo "    playwright ${ver} (${label}) ✓"
    else
      echo "    playwright ${ver} (${label}) — missing: ${missing//$'\n'/ }"
      # If this machine can't heal the installation (old CLI, no node ≤22),
      # the generic "re-run bootstrap" advice is a circle — name the real fix.
      hint=""
      _pw_heal_node "$ver" >/dev/null || hint=" — heal skipped: needs node ≤22 (brew install node@22) or upgrade this installation past 1.60"
      verify_errors+=("playwright ${ver} pinned builds missing: ${missing//$'\n'/ } (${label})${hint}")
    fi
  done
}

# ─── Preflight ───────────────────────────────────────────────────────────────
# Hard prerequisites and environment checks. This is the ONLY place the script
# may exit early (exit 2). Everything after preflight records failures and
# continues.

preflight_lint_config() {
  local known=" marketplace plugin github-skill github-skill-pack local-skill local-command global-memory brew-dep brew-cask npm-global pnpm-store uv-tool mcp-server env-var statusline "
  local cfg lineno line trimmed t
  for cfg in "${CONFIG_FILES[@]}"; do
    lineno=0
    while IFS= read -r line; do
      lineno=$((lineno + 1))
      trimmed="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [ -z "$trimmed" ] && continue
      case "$trimmed" in "#"*) continue ;; esac
      if [ "${trimmed#*|}" = "$trimmed" ]; then
        echo "    $(basename "$cfg"):${lineno}: no '|' delimiter — line ignored"
        continue
      fi
      t="$(echo "${trimmed%%|*}" | sed 's/[[:space:]]*$//')"
      case "$known" in
        *" $t "*) ;;
        *) echo "    $(basename "$cfg"):${lineno}: unknown type '${t}' — line ignored" ;;
      esac
    done < "$cfg"
  done
}

section "Preflight"

# Fresh-Mac expectation setting: Homebrew's installer needs sudo and may open
# the Xcode Command Line Tools dialog. Say so before it happens.
if [ "$OS" = "Darwin" ] && ! command -v brew &>/dev/null; then
  echo "  ${C_YELLOW}⚠${C_RESET} Homebrew setup will ask for your macOS password and may open the"
  echo "    Xcode Command Line Tools dialog — this is expected on a fresh Mac."
fi

# Network reachability — everything downstream needs github.com + npm registry.
step_start "network (github.com, registry.npmjs.org)"
_gh_ok=0; _npm_ok=0
if curl -fsS --max-time 5 https://api.github.com/zen >/dev/null 2>&1; then _gh_ok=1; fi
if curl -fsS --max-time 5 https://registry.npmjs.org/-/ping >/dev/null 2>&1; then _npm_ok=1; fi
if [ "$_gh_ok" -eq 1 ] && [ "$_npm_ok" -eq 1 ]; then
  step_ok network
elif [ "$_gh_ok" -eq 0 ] && [ "$_npm_ok" -eq 0 ]; then
  echo "${C_RED}✗${C_RESET}"
  echo ""
  echo "  No network access to github.com or registry.npmjs.org."
  echo "  Connect to the internet (check VPN / proxy), then re-run ./claude-bootstrap.sh"
  exit 2
else
  if [ "$_gh_ok" -eq 0 ]; then
    step_warn network "github.com unreachable — clones and plugins may fail" "check VPN/proxy"
  else
    step_warn network "registry.npmjs.org unreachable — npm installs may fail" "check VPN/proxy"
  fi
fi

# Homebrew — auto-install if missing; hard-fail if that fails.
step_start "Homebrew"
if command -v brew &>/dev/null; then
  step_cached prereq
else
  echo "installing..."
  if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    # Re-source to pick up the newly installed brew
    source "${SCRIPT_DIR}/lib/platform.sh"
  fi
  step_start "Homebrew"
  if command -v brew &>/dev/null; then
    step_ok prereq
  else
    echo "${C_RED}✗${C_RESET}"
    echo ""
    echo "  Homebrew could not be installed. Install it manually:"
    echo "    /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    echo "  then re-run ./claude-bootstrap.sh"
    exit 2
  fi
fi

# node — hoisted preflight step (see do_preflight_node).
step_start "node"
do_preflight_node

# Registry TLS through node's CA store — curl alone probes the WRONG TLS
# stack (system keychain) and greenlit the 2026-07-21 broken-store run.
step_start "registry TLS (node)"
do_preflight_registry_tls

# claude CLI — npm canonical, native installer fallback (see function).
step_start "claude CLI"
do_preflight_claude_cli

# claude auth — warn only; the bootstrap itself works logged out, but plugin
# and MCP registration may not.
step_start "claude auth"
if [ -n "${ANTHROPIC_API_KEY:-}" ] || grep -q '"oauthAccount"' ~/.claude.json 2>/dev/null; then
  step_ok auth "logged in"
else
  step_warn auth "not logged in — run 'claude' once and complete login; setup continues" "run 'claude' and log in, then re-run ./claude-bootstrap.sh if any plugin steps failed"
fi

# Config lint — warn with file:line; a typo must not brick the run.
step_start "config ($(printf '%s ' "${CONFIG_FILES[@]##*/}" | sed 's/ $//'))"
_lint_out="$(preflight_lint_config)"
if [ -z "$_lint_out" ]; then
  step_ok config
else
  step_warn config "config lint warnings (listed in preflight output)" "fix the flagged lines in the config file(s)"
  printf '%s\n' "$_lint_out"
fi

# settings.json validity — a corrupt file would abort every jq write later.
# shellcheck disable=SC2088  # display string, not a path
step_start "~/.claude/settings.json"
if [ ! -f ~/.claude/settings.json ]; then
  step_ok fs "will be created"
elif ! command -v jq &>/dev/null; then
  step_ok fs "validity checked after jq installs"
elif jq empty ~/.claude/settings.json &>/dev/null; then
  step_ok fs "valid JSON"
else
  _bak=~/.claude/settings.json.bak-$(date +%Y%m%d-%H%M%S)
  mv ~/.claude/settings.json "$_bak"
  echo '{}' > ~/.claude/settings.json
  step_warn fs "was invalid JSON — backed up and reset" "review $(basename "$_bak") in ~/.claude/ and re-apply any custom settings"
fi

# Disk space — warn under 5 GB.
step_start "disk space"
_free_gb="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {printf "%d", $4/1048576}' || true)"
if [ -n "$_free_gb" ] && [ "$_free_gb" -lt 5 ]; then
  step_warn env "only ${_free_gb}GB free — installs may fail" "free up disk space"
else
  step_ok env "${_free_gb:-?}GB free"
fi

# ─── CLI Tools (brew) ───────────────────────────────────────────────────────

section "CLI tools (brew)" "$(config_count brew-dep)"
read_config "brew-dep" do_install_brew_dep

# ─── CLI Tools (brew casks) ──────────────────────────────────────────────────

section "CLI tools (brew casks)" "$(config_count brew-cask)"
read_config "brew-cask" do_install_brew_cask

# ─── CLI Tools (npm) ─────────────────────────────────────────────────────────

section "CLI tools (npm)" "$(config_count npm-global)"
# node (hence npm) is itself a brew-dep installed above. If that failed, skip
# the npm-globals rather than aborting the whole run — recorded for the summary.
if ! command -v npm &>/dev/null; then
  step_start "npm globals"
  step_fail prereq "npm not found (node install failed?)" "brew install node, then re-run ./claude-bootstrap.sh"
else
  read_config "npm-global" do_install_npm_global
fi

# ─── CLI Tools (uv) ─────────────────────────────────────────────────────────

section "CLI tools (uv)" "$(config_count uv-tool)"
# uv is a brew-dep installed above; skip its tools (not abort) if it's missing.
if ! command -v uv &>/dev/null; then
  step_start "uv tools"
  step_fail prereq "uv not found" "brew install uv, then re-run ./claude-bootstrap.sh"
else
  # Ensure uv tool bin directory is on PATH (uv installs binaries to ~/.local/bin/)
  uv_bin_dir="$(uv tool dir --bin 2>/dev/null)"
  if [ -n "$uv_bin_dir" ] && [[ ":$PATH:" != *":${uv_bin_dir}:"* ]]; then
    export PATH="${uv_bin_dir}:${PATH}"
  fi
  read_config "uv-tool" do_install_uv_tool
fi

# ─── Frontend Libraries (pnpm store) ─────────────────────────────────────────
#
# Pre-warm the pnpm content-addressable store with importable JS libraries
# (e.g. motion). Projects pull them in with `pnpm add <pkg>`, which hard-links
# from the warm store — instant and offline. See the `motion` skill for usage.

section "Frontend libraries (pnpm store)" "$(config_count pnpm-store)"
if ! command -v pnpm &>/dev/null; then
  step_start "pnpm store"
  step_fail prereq "pnpm not found" "brew install pnpm, then re-run ./claude-bootstrap.sh"
else
  read_config "pnpm-store" do_install_pnpm_store
fi

# ─── Playwright Browsers ────────────────────────────────────────────────────

# Machine-global Playwright browser cache (shared by every project and
# session on this machine). Also consumed by the Verification section.
PLAYWRIGHT_CACHE="${PLAYWRIGHT_CACHE:-$HOME/Library/Caches/ms-playwright}"

# _pw_satisfied <dry-run-cmd...> — 0 iff the CLI's dry-run reports at least
# one "Install location:" and every reported directory carries Playwright's
# INSTALLATION_COMPLETE marker. Dry-run never touches the cache dirlock, so
# a warm re-run skips the real install entirely — immune to lock contention.
# Any dry-run failure or unparseable output returns 1: fall through to the
# real install, never skip on absent evidence.
# Real-world contract (observed playwright 1.6x): `install chromium` stages
# THREE components — chromium, ffmpeg, chromium_headless_shell — and all
# three write INSTALLATION_COMPLETE. If a future component omits the marker,
# this probe degrades fail-open (warm skip lost, install re-runs every time,
# nothing hangs or breaks) — if warm runs stop reporting "already installed",
# look here first.
_pw_satisfied() {
  local out locs loc
  out="$("$@" 2>/dev/null)" || return 1
  locs="$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*Install location:[[:space:]]*//p')"
  [ -n "$locs" ] || return 1
  while IFS= read -r loc; do
    [ -f "${loc}/INSTALLATION_COMPLETE" ] || return 1
  done <<< "$locs"
  return 0
}

# _pw_lock_preflight — triage the machine-global cache lock before a real
# install. Held by a live installer (any process, incl. another session's)
# → return 1: the caller fails fast instead of waiting silently forever.
# Present but orphaned → stale: remove and proceed. Absent → proceed.
# Pattern requires a space-separated "install" arg after a playwright-bearing
# token (matches `npx playwright install`, `.../cli.js install`, python's
# driver) without matching doc/log files like playwright-install-notes.md.
# No self-exclusion needed: this script's cmdline never matches, and the
# dry-run child has exited before preflight runs (synchronous command
# substitution) — preserve that ordering if refactoring.
_pw_lock_preflight() {
  local lock="${PLAYWRIGHT_CACHE}/__dirlock"
  [ -e "$lock" ] || return 0
  if pgrep -f "playwright[^ ]* install" >/dev/null 2>&1; then
    return 1
  fi
  rm -rf "$lock"
  echo ""
  echo "    removed stale browser-cache lock (${lock})"
  return 0
}

# ─── Registry-heal helpers ───
# Playwright records every installation that ever ran `playwright install` in
# ${PLAYWRIGHT_CACHE}/.links (one file per installation, containing the path
# to its playwright-core package dir), and each installation's browsers.json
# declares the exact browser builds that version launches. These helpers read
# that registry. The formats are unversioned Playwright internals (same
# accepted-risk class as the dry-run parse above): every consumer fails open —
# unreadable input skips loudly, never blocks the run.

# _pw_link_demands <pkg-dir> — print "name rev [rev...]" per chromium-set
# component (chromium, chromium-headless-shell, ffmpeg — the three components
# `install chromium` stages). Revisions after the first are the entry's
# revisionOverrides values (per-platform pins, e.g. ffmpeg mac12 → older
# build): the component is satisfied by ANY candidate revision, because on a
# given machine Playwright itself resolves and installs exactly one of them —
# replicating its host-platform detection here would chase an internal
# contract. rc≠0 / empty output when browsers.json is missing or unparseable.
_pw_link_demands() {
  jq -r '.browsers[]
         | select(.name == "chromium" or .name == "chromium-headless-shell" or .name == "ffmpeg")
         | .name + " " + .revision + ((.revisionOverrides // {}) | [.[]] | map(" " + .) | join(""))' \
    "$1/browsers.json" 2>/dev/null
}

# _pw_component_dir <name> <revision> — cache dir for one component build.
# Playwright's naming: dashes in the component name become underscores
# (chromium-headless-shell @ 1217 → chromium_headless_shell-1217).
_pw_component_dir() {
  echo "${PLAYWRIGHT_CACHE}/${1//-/_}-$2"
}

# _pw_link_missing <pkg-dir> — print demanded component names with no complete
# build under ANY candidate revision (no INSTALLATION_COMPLETE marker). Empty
# output + rc 0 = fully satisfied. rc 1 = demands unreadable/empty (caller
# skips loudly).
_pw_link_missing() {
  local demands name revs rev sat
  demands="$(_pw_link_demands "$1")"
  [ -n "$demands" ] || return 1
  while IFS=' ' read -r name revs; do
    sat=0
    for rev in $revs; do
      if [ -f "$(_pw_component_dir "$name" "$rev")/INSTALLATION_COMPLETE" ]; then
        sat=1
        break
      fi
    done
    [ "$sat" -eq 1 ] || echo "$name"
  done <<< "$demands"
}

# _pw_heal_node <cli-version> — echo the node binary safe for running that
# Playwright CLI's installer. Playwright ≤1.59 deadlocks at download
# completion under node ≥23 (proven live 2026-07-17: identical cli.js hung
# under node 26.5, completed under node 22 — 0% CPU, no open fds, an awaited
# stream event that never fires; 1.61+ is unaffected, which is why the
# @latest baseline never hangs). For old CLIs, pick the first node with
# major ≤22 from: $PLAYWRIGHT_HEAL_NODE override, Homebrew node@22 (both
# prefixes), system node. rc 1 = no safe runtime on this machine — the
# caller skips that heal loudly (Verification still names the missing
# builds), never risks the hang.
_pw_heal_node() {
  local ver="$1" cand major
  case "$ver" in
    1.6[1-9]*|1.[7-9][0-9]*|[2-9].*) echo node; return 0;;
  esac
  for cand in "${PLAYWRIGHT_HEAL_NODE:-}" /opt/homebrew/opt/node@22/bin/node /usr/local/opt/node@22/bin/node node; do
    [ -n "$cand" ] || continue
    command -v "$cand" >/dev/null 2>&1 || continue
    major="$("$cand" -e 'console.log(process.versions.node.split(".")[0])' 2>/dev/null || true)"
    case "$major" in (''|*[!0-9]*) continue;; esac
    if [ "$major" -le 22 ]; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

# _pw_heal_one <node-binary> <pkg-dir> — restore an installation's pinned
# chromium components via ITS OWN CLI (the only authority on its build
# numbers), executed under a runtime _pw_heal_node vetted for that CLI
# version. Downloads land in the shared machine-global cache and re-register
# the link, so later installers' GC passes keep these builds. Same sed filter
# as _playwright_install (strips the per-project warning box).
_pw_heal_one() {
  "$1" "$2/cli.js" install chromium 2>&1 | sed '/[╔║╚]/d'
}

# do_heal_playwright_registry — walk the installation registry and restore
# any missing pinned builds. Zero-config: the registry is maintained by
# Playwright as a side effect of use. Runs AFTER the @latest baseline so
# every link this pass touches is re-registered and survives subsequent GC
# passes (including the excalidraw renderer's python install). Fail-open at
# every rung: dangling/unreadable links skip loudly; heals serialize behind
# the machine-global cache lock; a failed heal records and continues.
do_heal_playwright_registry() {
  local links="${PLAYWRIGHT_CACHE}/.links" f target ver missing label nodebin
  if [ ! -d "$links" ]; then
    echo "  registry heal — no installation registry yet (skipped)"
    return 0
  fi
  for f in "$links"/*; do
    # -f (not -e) skips the unexpanded-glob literal AND non-file entries
    # (a stray subdirectory); `|| true` keeps an unreadable link file from
    # tripping set -e — both are fail-open contract, never abort.
    [ -f "$f" ] || continue
    target="$(cat "$f" 2>/dev/null || true)"
    if [ -z "$target" ] || [ ! -d "$target" ]; then
      echo "  ${target:-$(basename "$f")} — dangling registry link (skipped; re-registers on that project's next install)"
      continue
    fi
    label="${target%/node_modules/playwright-core}"
    ver="$(jq -r '.version // "unknown"' "$target/package.json" 2>/dev/null || echo unknown)"
    if ! missing="$(_pw_link_missing "$target")"; then
      echo "  ${label} — unreadable browsers.json (skipped)"
      continue
    fi
    if [ -z "$missing" ]; then
      echo "  ✓ playwright ${ver} (${label}) — pinned builds present"
      continue
    fi
    if ! nodebin="$(_pw_heal_node "$ver")"; then
      echo "  ${label} — playwright ${ver} needs node ≤22 to install (system node deadlocks its installer); no safe node found (skipped)"
      echo "    fix: brew install node@22 and re-run, or set PLAYWRIGHT_HEAL_NODE=/path/to/node22"
      continue
    fi
    step_start "heal playwright ${ver}: ${missing//$'\n'/ }"
    if ! _pw_lock_preflight; then
      step_fail network "another Playwright install holds the browser-cache lock (often a second Claude session)" \
        "finish or kill it, then re-run ./claude-bootstrap.sh"
      continue
    fi
    step_stream network "run '${nodebin} ${target}/cli.js install chromium' by hand, then re-run ./claude-bootstrap.sh" \
      _pw_heal_one "$nodebin" "$target"
  done
}

section "Playwright browsers"
# The one legitimately slow step (~170 MB on first install), so: stream
# playwright's own progress instead of capturing it (it prints plain progress
# lines when piped — log-safe), cap stalled downloads so a dead socket aborts
# and playwright's internal retry kicks in, and --yes so npx can never prompt.
export PLAYWRIGHT_DOWNLOAD_CONNECTION_TIMEOUT="${PLAYWRIGHT_DOWNLOAD_CONNECTION_TIMEOUT:-60000}"
# playwright@latest, not bare `playwright`: bare npx resolves any stale global
# Playwright, and old Playwright + new node hangs during zip extraction
# (verified live: @playwright/test 1.58.2 froze under node 26.5.0; 1.61.1
# completed). Pinning @latest removes the stale-global variable entirely.
# The sed drop-filter strips playwright's "install your project's
# dependencies first" warning box — it's aimed at per-project test setups and
# is meaningless (but alarming) for this global browser install. sed always
# exits 0, so pipefail still surfaces npx's own status.
_playwright_install() {
  npx --yes playwright@latest install chromium 2>&1 | sed '/[╔║╚]/d'
}
# Guard → preflight → install. The dry-run probe costs ~2-3s but never
# touches the cache lock, so warm re-runs are instant and immune to a lock
# held by another session's install (which previously hung this step
# silently and indefinitely).
do_install_playwright_chromium() {
  step_start "chromium (first install downloads ~170 MB)"
  if _pw_satisfied npx --yes playwright@latest install chromium --dry-run; then
    step_cached network "browsers already installed"
  elif ! _pw_lock_preflight; then
    step_fail network "another Playwright install holds the browser-cache lock (often a second Claude session)" \
      "finish or kill it, then re-run ./claude-bootstrap.sh"
  else
    step_stream network "run 'npx --yes playwright@latest install chromium' by hand, then re-run ./claude-bootstrap.sh" \
      _playwright_install
  fi
}
do_install_playwright_chromium
do_heal_playwright_registry

# ─── Marketplaces ────────────────────────────────────────────────────────────

section "Marketplaces" "$(config_count marketplace)"
read_config "marketplace" do_install_marketplace

# ─── Plugins ─────────────────────────────────────────────────────────────────

section "Plugins" "$(config_count plugin)"
read_config "plugin" do_install_plugin

# ─── Global Memory ─────────────────────────────────────────────────────────

section "Global memory"
read_config "global-memory" do_install_global_memory

# ─── Shell Alias ─────────────────────────────────────────────────────────────

section "Shell alias"
ALIAS_RC="$SHELL_RC"
ALIAS_START="# ─── bionic:start ───"
ALIAS_END="# ─── bionic:end ───"
ALIAS_CONTENT="alias claude='claude --dangerously-skip-permissions'"
ALIAS_SECTION="${ALIAS_START}
${ALIAS_CONTENT}
${ALIAS_END}"

# Writes the marker-managed alias section into $ALIAS_RC. Sets ALIAS_NOTE for
# the status line; returns 1 on write failure.
do_install_shell_alias() {
  ALIAS_NOTE=""
  # Migrate old unmarked alias to marker-based section
  if [ -f "$ALIAS_RC" ] && grep -q "alias claude=.*dangerously-skip-permissions" "$ALIAS_RC" && ! grep -qF "$ALIAS_START" "$ALIAS_RC"; then
    grep -v "alias claude=.*dangerously-skip-permissions" "$ALIAS_RC" > "${ALIAS_RC}.tmp" || true
    mv "${ALIAS_RC}.tmp" "$ALIAS_RC" || return 1
    printf '\n%s\n' "$ALIAS_SECTION" >> "$ALIAS_RC" || return 1
    ALIAS_NOTE="migrated to markers"
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
    } > "${ALIAS_RC}.tmp" || return 1
    mv "${ALIAS_RC}.tmp" "$ALIAS_RC" || return 1
    ALIAS_NOTE="already installed"
  else
    # No markers, no alias — append
    printf '\n%s\n' "$ALIAS_SECTION" >> "$ALIAS_RC" || return 1
  fi
  return 0
}

step_start "claude → claude --dangerously-skip-permissions"
if do_install_shell_alias; then
  if [ -n "$ALIAS_NOTE" ]; then step_cached fs "$ALIAS_NOTE"; else step_ok fs; fi
else
  step_fail fs "could not write ${ALIAS_RC}" "check permissions on ${ALIAS_RC}, then re-run ./claude-bootstrap.sh"
fi

# ─── Custom Skills ───────────────────────────────────────────────────────────

section "Custom skills"
read_config "github-skill" do_install_github_skill
read_config "github-skill-pack" do_install_github_skill_pack
read_config "local-skill" do_install_local_skill

# ─── Custom Commands ────────────────────────────────────────────────────────

section "Custom commands" "$(config_count local-command)"

# Prune orphan commands: anything in ~/.claude/commands/ not listed in
# the config as a local-command entry. Renames (memory-sweep →
# memory-compact) leave stale files behind without this step.
if [ -d ~/.claude/commands ]; then
  # `|| true`: a config with zero local-command entries makes grep exit 1,
  # which pipefail + set -e would turn into a mid-run abort.
  managed_commands="$(cat "${CONFIG_FILES[@]}" | grep -E '^\s*local-command\s*\|' | sed -E 's/^[^|]+\|[[:space:]]*//;s/[[:space:]]+$//' || true)"
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

# ─── Skill Setup ────────────────────────────────────────────────────────────

section "Skill setup"
_excalidraw_dry_run() {
  cd "$1" && uv run playwright install chromium --dry-run
}
_excalidraw_setup() {
  cd "$1" && uv sync --quiet && uv run playwright install chromium
}
# Same guard→preflight→install shape as the chromium step, against the
# python Playwright CLI (it resolves its own browser builds — the probe
# must use *its* dry-run, not the npm one). `uv run` syncs the venv
# implicitly, so a satisfied-skip has already done uv sync's work.
do_setup_excalidraw_renderer() {
  local refs="$1"
  step_start "excalidraw-diagram renderer"
  if _pw_satisfied _excalidraw_dry_run "$refs"; then
    step_cached network "renderer browsers already installed"
  elif ! _pw_lock_preflight; then
    step_fail network "another Playwright install holds the browser-cache lock (often a second Claude session)" \
      "finish or kill it, then re-run ./claude-bootstrap.sh"
  else
    step_stream network "cd ${refs} && uv sync && uv run playwright install chromium, then re-run ./claude-bootstrap.sh" \
      _excalidraw_setup "$refs"
  fi
}
if [ -d ~/.claude/skills/excalidraw-diagram/references ]; then
  # First install downloads the chromium headless shell (~90 MB) — stream it.
  do_setup_excalidraw_renderer ~/.claude/skills/excalidraw-diagram/references
else
  echo "  excalidraw-diagram — skipped (not installed)"
fi
if command -v notebooklm &>/dev/null; then
  step_start "notebooklm skill install"
  if notebooklm skill install &>/dev/null; then
    step_ok tool
  else
    step_cached tool "skill already installed"
  fi
else
  echo "  notebooklm — skipped (CLI not installed)"
fi

# ─── Global Agents ───────────────────────────────────────────────────────────
#
# Installs bionic's agent role files (repo agents/*.md) to ~/.claude/agents so
# Claude Code can dispatch subagents via `subagent_type: implementor|
# senior-implementor|researcher|auditor|critic|test-runner`. Same glob /
# orphan-prune / manifest shape as Global Hooks below: the repo is canonical,
# installs orphaned by prior refactors are removed, and a manifest records
# exactly what bionic installed so reset can undo it even if the repo's
# agents/ contents change between install and reset.
do_install_agents() {
  mkdir -p ~/.claude/agents

  declare -a repo_agents=()
  for agent in "${SCRIPT_DIR}"/agents/*.md; do
    [ -f "$agent" ] || continue
    repo_agents+=("$(basename "$agent")")
  done

  # ~/.claude/agents/ is Claude Code's standard USER subagent directory, so
  # the prune must be scoped to manifest-tracked orphans only — a file only
  # gets removed if bionic installed it in a prior run (its basename is in
  # the PRE-EXISTING manifest, read before this run overwrites it) and it's
  # no longer in the repo. A hand-authored file never listed in the manifest
  # (or a first run with no manifest yet) is never touched.
  declare -a prior_manifest=()
  if [ -f ~/.claude/agents/.bionic-manifest ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && prior_manifest+=("$line")
    done < ~/.claude/agents/.bionic-manifest
  fi

  for installed in ~/.claude/agents/*.md; do
    [ -f "$installed" ] || continue
    base="$(basename "$installed")"
    tracked=0
    for m in ${prior_manifest[@]+"${prior_manifest[@]}"}; do
      if [ "$base" = "$m" ]; then tracked=1; break; fi
    done
    [ "$tracked" -eq 1 ] || continue
    found=0
    for r in ${repo_agents[@]+"${repo_agents[@]}"}; do
      if [ "$base" = "$r" ]; then found=1; break; fi
    done
    if [ "$found" -eq 0 ]; then
      rm -f "$installed"
      echo "  ${base}... ✗ removed (no longer in repo)"
    fi
  done

  # Files this run actually installs (or attempted to) — becomes the new
  # manifest. A colliding user-authored file is skipped entirely and must
  # NOT enter the manifest: bionic did not install it, so reset must never
  # attribute it to bionic later.
  declare -a manifest_agents=()
  for agent in "${SCRIPT_DIR}"/agents/*.md; do
    [ -f "$agent" ] || continue
    name="$(basename "$agent")"
    step_start "$name"
    if [ -f ~/.claude/agents/"$name" ]; then
      tracked=0
      for m in ${prior_manifest[@]+"${prior_manifest[@]}"}; do
        if [ "$name" = "$m" ]; then tracked=1; break; fi
      done
      if [ "$tracked" -eq 0 ]; then
        step_fail fs "user-authored ~/.claude/agents/${name} exists — rename it to adopt the bionic role"
        continue
      fi
    fi
    if cp "$agent" ~/.claude/agents/"$name"; then
      step_ok fs
    else
      step_fail fs "could not install agent role file to ~/.claude/agents/${name}"
    fi
    manifest_agents+=("$name")
  done

  { for r in ${manifest_agents[@]+"${manifest_agents[@]}"}; do echo "$r"; done; } > ~/.claude/agents/.bionic-manifest || true
  return 0
}

section "Global agents"
do_install_agents

# ─── Global Hooks ────────────────────────────────────────────────────────────

section "Global hooks"
mkdir -p ~/.claude/hooks

# settings.json mutations below need jq. If its brew install failed earlier,
# skip the jq-driven config (hooks wiring, env vars, statusline) rather than
# aborting the whole run — recorded for the summary. Hook *files* are still
# copied; only the settings.json wiring is skipped.
settings=~/.claude/settings.json
HAVE_JQ=1
if ! command -v jq &>/dev/null; then
  HAVE_JQ=0
  step_start "jq"
  step_fail prereq "jq unavailable — settings.json hooks/env/statusline not configured" "brew install jq, then re-run ./claude-bootstrap.sh"
fi

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
  for r in ${repo_hooks[@]+"${repo_hooks[@]}"}; do
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
  step_start "$name"
  if cp "$hook" ~/.claude/hooks/"$name" && chmod +x ~/.claude/hooks/"$name"; then
    step_ok fs
  else
    step_fail fs "could not install hook to ~/.claude/hooks/${name}"
  fi
done

# Manifest of bionic-owned hook files, so reset can attribute and remove them
# even if the repo's hooks/ contents change between install and reset.
{ for r in ${repo_hooks[@]+"${repo_hooks[@]}"}; do echo "$r"; done; } > ~/.claude/hooks/.bionic-manifest || true

# Define all managed hooks (event|matcher_or_empty|command pairs)
# PreToolUse uses Bash/Write/Edit/Agent matchers; SessionStart uses a
# source matcher (startup — don't fire on compact/clear/resume since
# cleanup was already done for this notebook); UserPromptSubmit takes
# no matcher.
MANAGED_HOOKS=(
  "PreToolUse|Bash|~/.claude/hooks/protect-main.sh"
  "PreToolUse|Bash|~/.claude/hooks/protect-database.sh"
  "PreToolUse|Bash|~/.claude/hooks/canonical-sdlc-evidence-gate.sh"
  "PreToolUse|Bash|~/.claude/hooks/farm-out-reminder.sh"
  "PreToolUse|Write|~/.claude/hooks/canonical-sdlc-governing-skill.sh"
  "PreToolUse|Edit|~/.claude/hooks/canonical-sdlc-governing-skill.sh"
  "SessionStart|startup|~/.claude/hooks/memory-cleanup.sh"
  "UserPromptSubmit||~/.claude/hooks/terseness-reminder.sh"
  "Stop||~/.claude/hooks/context-spend.sh"
)

# Rebuild hook config in global settings. Resetting .hooks to exactly the
# managed set is convergent: removing an entry from MANAGED_HOOKS removes it
# from settings.json on the next run. Returns 1 on any write failure.
wire_managed_hooks() {
  local tmp="${settings}.tmp" entry event matcher cmd
  if [ ! -f "$settings" ]; then
    echo '{}' > "$settings" || return 1
  fi
  jq '.hooks = {}' "$settings" > "$tmp" || return 1
  mv "$tmp" "$settings" || return 1
  for entry in "${MANAGED_HOOKS[@]}"; do
    IFS='|' read -r event matcher cmd <<< "$entry"
    if ! jq -e --arg ev "$event" '.hooks[$ev]' "$settings" &>/dev/null; then
      jq --arg ev "$event" '.hooks[$ev] = []' "$settings" > "$tmp" || return 1
      mv "$tmp" "$settings" || return 1
    fi
    if [ -n "$matcher" ]; then
      jq --arg ev "$event" --arg m "$matcher" --arg c "$cmd" '
        .hooks[$ev] += [{
          "matcher": $m,
          "hooks": [{"type": "command", "command": $c, "timeout": 10}]
        }]
      ' "$settings" > "$tmp" || return 1
      mv "$tmp" "$settings" || return 1
    else
      jq --arg ev "$event" --arg c "$cmd" '
        .hooks[$ev] += [{
          "hooks": [{"type": "command", "command": $c}]
        }]
      ' "$settings" > "$tmp" || return 1
      mv "$tmp" "$settings" || return 1
    fi
  done
  return 0
}

step_start "settings.json hook config"
if [ "$HAVE_JQ" != 1 ]; then
  step_skip prereq "jq unavailable" "brew install jq, then re-run ./claude-bootstrap.sh"
elif wire_managed_hooks; then
  step_ok fs "${#MANAGED_HOOKS[@]} managed hooks"
else
  step_fail fs "could not update ${settings}" "check that ${settings} is writable and valid JSON, then re-run ./claude-bootstrap.sh"
fi
if [ "$removed_hooks" -gt 0 ]; then
  echo "  cleaned up ${removed_hooks} stale hook file(s) from ~/.claude/hooks/"
fi

# ─── Account-mirror symlinks ────────────────────────────────────────────────
#
# When multiple Claude accounts exist (~/.claude-other, ~/.claude-synthesis,
# etc.), share the global config across them by symlinking settings.json and
# CLAUDE.md back to the canonical ~/.claude/ copies. Auth (.claude.json),
# history, and per-account caches stay separate.

section "Account-mirror symlinks"
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
      if ! mv "$target" "${target}.bak-$(date +%Y%m%d-%H%M%S)"; then
        step_start "${account}/${f}"
        step_fail fs "could not back up ${target}"
        continue
      fi
    fi
    if ln -s "$canonical" "$target"; then
      echo "  ${account}/${f} → ~/.claude/${f} ✓"
      mirror_count=$((mirror_count + 1))
    else
      step_start "${account}/${f}"
      step_fail fs "could not symlink ${target}"
    fi
  done
done
if [ "$mirror_count" -eq 0 ]; then
  echo "  (no additional accounts found, or already symlinked)"
fi

# ─── Env Vars ───────────────────────────────────────────────────────────────

section "Env vars" "$(config_count env-var)"

do_set_env_var() {
  local key="$1" val="$2"
  step_start "${key}=${val}"
  if jq -e --arg k "$key" --arg v "$val" '.env[$k] == $v' "$settings" &>/dev/null; then
    step_cached fs "already set"
    return 0
  fi
  local tmp="${settings}.tmp"
  if jq --arg k "$key" --arg v "$val" '.env[$k] = $v' "$settings" > "$tmp" && mv "$tmp" "$settings"; then
    step_ok fs
  else
    step_fail fs "could not update ${settings}"
  fi
  return 0
}
if [ "$HAVE_JQ" = 1 ]; then
  read_config "env-var" do_set_env_var
else
  echo "  ⚠ skipped (jq unavailable)"
fi

# ─── Status Line ──────────────────────────────────────────────────────────────

section "Status line"

do_set_statusline() {
  local cmd="$1"
  step_start "$cmd"
  if jq -e --arg c "$cmd" '.statusLine.command == $c' "$settings" &>/dev/null; then
    step_cached fs "already set"
    return 0
  fi
  local tmp="${settings}.tmp"
  if jq --arg c "$cmd" '.statusLine = {"type": "command", "command": $c}' "$settings" > "$tmp" && mv "$tmp" "$settings"; then
    step_ok fs
  else
    step_fail fs "could not update ${settings}"
  fi
  return 0
}
if [ "$HAVE_JQ" = 1 ]; then
  read_config "statusline" do_set_statusline
else
  echo "  ⚠ skipped (jq unavailable)"
fi

# ─── ccstatusline Config ──────────────────────────────────────────────────────

section "ccstatusline config"
step_start "settings.json → ~/.config/ccstatusline/settings.json"
if [ ! -f "${SCRIPT_DIR}/ccstatusline/settings.json" ]; then
  step_fail config "ccstatusline/settings.json missing from repo"
elif diff -q "${SCRIPT_DIR}/ccstatusline/settings.json" ~/.config/ccstatusline/settings.json &>/dev/null; then
  step_cached fs "already up to date"
else
  mkdir -p ~/.config/ccstatusline
  if cp "${SCRIPT_DIR}/ccstatusline/settings.json" ~/.config/ccstatusline/settings.json; then
    step_ok fs
  else
    step_fail fs "could not write ~/.config/ccstatusline/settings.json"
  fi
fi

# ─── Local Package Builds ────────────────────────────────────────────────────

section "Local packages"
read_config "mcp-server" do_build_local_package

# ─── MCP Servers ─────────────────────────────────────────────────────────────

section "MCP servers" "$(config_count mcp-server)"
read_config "mcp-server" do_configure_mcp_server

# ─── Verification ───────────────────────────────────────────────────────────

verify_errors=()
verify_warnings=()
section "Verification"

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
echo "  Playwright registry:"
verify_playwright_registry

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
echo "  Hook wiring (settings.json):"
if [ "$HAVE_JQ" = 1 ] && [ -f "$settings" ]; then
  for entry in "${MANAGED_HOOKS[@]}"; do
    IFS='|' read -r event matcher cmd <<< "$entry"
    if jq -e --arg ev "$event" --arg c "$cmd" \
        '.hooks[$ev] // [] | map(.hooks // [] | map(.command)) | flatten | index($c)' \
        "$settings" &>/dev/null; then
      echo "    ${event}: $(basename "$cmd") ✓"
    else
      echo "    ${event}: $(basename "$cmd") — not wired"
      verify_errors+=("hook $(basename "$cmd") (${event}) — not wired in settings.json")
    fi
  done
else
  echo "    (skipped — jq or settings.json unavailable)"
fi

echo ""
echo "  Plugins:"
PLUGIN_LIST_OUTPUT="$(claude plugin list 2>&1 || true)"
read_config "plugin" verify_plugin_installed

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
  # shellcheck disable=SC2088  # display string, not a path
  verify_errors+=("~/.claude/CLAUDE.md — managed section not installed")
fi

echo ""
echo "  Shell alias:"
if [ -f "$SHELL_RC" ] && grep -qF "# ─── bionic:start ───" "$SHELL_RC"; then
  echo "    ~/${SHELL_RC_NAME} ✓"
else
  echo "    ~/${SHELL_RC_NAME} — not installed"
  verify_errors+=("shell alias in ~/${SHELL_RC_NAME} — not installed")
fi

# ─── Staleness advisory (read-only) ─────────────────────────────────────────
# Version drift is a real failure class (old Playwright + new node hung
# forever), but upgrades belong to the tools' own managers. So: detect drift
# in managed tools, report it with the exact command to fix it, never upgrade
# anything ourselves. Purely informational — does not affect the exit code.

UPDATES=()

collect_updates() {
  # Managed package names (brew uses the package field, normalized to short
  # names — tap-qualified entries like stripe/stripe-cli/stripe print as
  # `stripe` in brew outdated).
  local managed_brew="" managed_npm=""
  _collect_brew_pkg() { local p="${2:-$1}"; managed_brew="${managed_brew} ${p##*/}"; }
  read_config "brew-dep" _collect_brew_pkg
  _collect_npm_pkg() { managed_npm="${managed_npm} $1"; }
  read_config "npm-global" _collect_npm_pkg

  # brew outdated exits non-zero when outdated formulae exist — capture anyway.
  local outdated f stale=""
  outdated="$(brew outdated --quiet 2>/dev/null || true)"
  for f in $outdated; do
    case " ${managed_brew} " in
      *" ${f##*/} "*) stale="${stale} ${f##*/}" ;;
    esac
  done
  stale="${stale# }"
  [ -n "$stale" ] && UPDATES+=("brew formulae outdated: ${stale}|brew upgrade ${stale}")

  # npm outdated also exits non-zero when outdated packages exist.
  if command -v jq &>/dev/null; then
    local pkg cur latest npmbin
    # Absolute path in the remediation: the advisory inspects THIS npm's
    # global root, and on multi-node machines (nvm + homebrew) a bare `npm`
    # in the user's shell can resolve elsewhere — the advised command would
    # install to the wrong prefix and the advisory would never clear.
    npmbin="$(command -v npm)"
    while IFS=$'\t' read -r pkg cur latest; do
      [ -n "$pkg" ] || continue
      case " ${managed_npm} " in
        *" ${pkg} "*) UPDATES+=("${pkg} ${cur} → ${latest}|${npmbin} install -g ${pkg}@latest") ;;
      esac
    done < <(npm outdated -g --json 2>/dev/null | jq -r 'to_entries[] | [.key, .value.current // "?", .value.latest // "?"] | @tsv' 2>/dev/null || true)
  fi
  return 0
}

echo ""
echo "  Update check (advisory):"
collect_updates
if [ "${#UPDATES[@]}" -eq 0 ]; then
  echo "    all managed tools current ✓"
else
  echo "    ${#UPDATES[@]} update(s) available — see report below"
fi

# ─── Final Report ───────────────────────────────────────────────────────────

print_report() {
  local rec st cat sec name rem det
  local total=0 n_ok=0 n_cached=0 n_fail=0 n_warnish=0

  for rec in ${STEP_RECORDS[@]+"${STEP_RECORDS[@]}"}; do
    st="${rec%%|*}"
    total=$((total + 1))
    case "$st" in
      ok)        n_ok=$((n_ok + 1)) ;;
      cached)    n_cached=$((n_cached + 1)) ;;
      fail)      n_fail=$((n_fail + 1)) ;;
      skip|warn) n_warnish=$((n_warnish + 1)) ;;
    esac
  done

  # Verification errors not already represented by a failed install step.
  local extra_verify=()
  local e covered fname
  for e in ${verify_errors[@]+"${verify_errors[@]}"}; do
    covered=0
    for rec in ${STEP_RECORDS[@]+"${STEP_RECORDS[@]}"}; do
      st="${rec%%|*}"
      [ "$st" = "fail" ] || continue
      IFS='|' read -r st cat sec fname rem det <<< "$rec"
      case "$e" in
        *"$fname"*) covered=1; break ;;
      esac
    done
    [ "$covered" -eq 0 ] && extra_verify+=("$e")
  done
  local n_verify=${#extra_verify[@]}
  local n_bad=$((n_fail + n_verify))

  # Verify-phase warnings that merely restate a skipped install step are
  # deduped: match on the warning's first token against skip/warn names.
  local extra_vwarn=()
  local _tok
  for e in ${verify_warnings[@]+"${verify_warnings[@]}"}; do
    covered=0
    _tok="${e%% *}"
    for rec in ${STEP_RECORDS[@]+"${STEP_RECORDS[@]}"}; do
      st="${rec%%|*}"
      case "$st" in skip|warn) ;; *) continue ;; esac
      IFS='|' read -r st cat sec name rem det <<< "$rec"
      case "$name" in
        "$_tok"*) covered=1; break ;;
      esac
    done
    [ "$covered" -eq 0 ] && extra_vwarn+=("$e")
  done
  local n_warn_total=$((n_warnish + ${#extra_vwarn[@]}))

  local elapsed=$(( $(date +%s) - START_TS ))
  local mins=$((elapsed / 60)) secs=$((elapsed % 60))

  echo ""
  if [ "$n_bad" -eq 0 ]; then
    echo "# ─── ${C_BOLD}Bootstrap complete ${C_GREEN}✓${C_RESET} ─────────────────────────────────────────"
  else
    echo "# ─── ${C_BOLD}Bootstrap finished — action needed ${C_RED}✗${C_RESET} ──────────────────────"
  fi
  echo ""
  printf '  %d steps · %d ok (%d already up to date) · %d failed · %d verify errors · %d warnings · %dm %02ds\n' \
    "$total" "$((n_ok + n_cached))" "$n_cached" "$n_fail" "$n_verify" "$n_warn_total" "$mins" "$secs"
  echo ""

  # Installed table — one row per section, glyph = worst member status.
  echo "  Installed"
  local sections=() s found glyph t good bad sk
  for rec in ${STEP_RECORDS[@]+"${STEP_RECORDS[@]}"}; do
    IFS='|' read -r st cat sec name rem det <<< "$rec"
    [ "$sec" = "Preflight" ] && continue
    found=0
    for s in ${sections[@]+"${sections[@]}"}; do
      if [ "$s" = "$sec" ]; then found=1; break; fi
    done
    [ "$found" -eq 0 ] && sections+=("$sec")
  done
  for s in ${sections[@]+"${sections[@]}"}; do
    t=0; good=0; bad=0; sk=0
    for rec in ${STEP_RECORDS[@]+"${STEP_RECORDS[@]}"}; do
      IFS='|' read -r st cat sec name rem det <<< "$rec"
      [ "$sec" = "$s" ] || continue
      t=$((t + 1))
      case "$st" in
        ok|cached)  good=$((good + 1)) ;;
        fail)       bad=$((bad + 1)) ;;
        skip|warn)  sk=$((sk + 1)) ;;
      esac
    done
    if [ "$bad" -gt 0 ]; then glyph="${C_RED}✗${C_RESET}"
    elif [ "$sk" -gt 0 ]; then glyph="${C_YELLOW}⚠${C_RESET}"
    else glyph="${C_GREEN}✓${C_RESET}"
    fi
    printf '    %b %-32s %3d/%d\n' "$glyph" "$s" "$good" "$t"
  done
  echo ""

  # Failures with remediation.
  if [ "$n_bad" -gt 0 ]; then
    echo "  Failures (${n_bad}) — fix the cause, then re-run ./claude-bootstrap.sh."
    echo "  Re-runs are idempotent: completed steps are skipped, only failures retry."
    local i=1
    for rec in ${STEP_RECORDS[@]+"${STEP_RECORDS[@]}"}; do
      st="${rec%%|*}"
      [ "$st" = "fail" ] || continue
      IFS='|' read -r st cat sec name rem det <<< "$rec"
      echo ""
      printf '    %d. %b✗%b %s — %s   [%s]\n' "$i" "$C_RED" "$C_RESET" "$sec" "$name" "$cat"
      [ -n "$det" ] && printf '         %s\n' "$det"
      [ -n "$rem" ] && printf '         → %s\n' "$rem"
      i=$((i + 1))
    done
    for e in ${extra_verify[@]+"${extra_verify[@]}"}; do
      echo ""
      printf '    %d. %b✗%b %s   [verify]\n' "$i" "$C_RED" "$C_RESET" "$e"
      printf '         → re-run ./claude-bootstrap.sh; if it persists, install by hand\n'
      i=$((i + 1))
    done
    echo ""
  fi

  # Warnings (env-gated skips, auth, lint).
  if [ "$n_warn_total" -gt 0 ]; then
    echo "  Warnings (${n_warn_total}) — optional; everything else works without them."
    local j=1
    for rec in ${STEP_RECORDS[@]+"${STEP_RECORDS[@]}"}; do
      st="${rec%%|*}"
      case "$st" in skip|warn) ;; *) continue ;; esac
      IFS='|' read -r st cat sec name rem det <<< "$rec"
      echo ""
      printf '    %d. %b⚠%b %s — %s   [%s]\n' "$j" "$C_YELLOW" "$C_RESET" "$sec" "$name" "$cat"
      [ -n "$det" ] && printf '         %s\n' "$det"
      [ -n "$rem" ] && printf '         → %s\n' "$rem"
      j=$((j + 1))
    done
    for e in ${extra_vwarn[@]+"${extra_vwarn[@]}"}; do
      echo ""
      printf '    %d. %b⚠%b %s\n' "$j" "$C_YELLOW" "$C_RESET" "$e"
      j=$((j + 1))
    done
    echo ""
  fi

  # Updates advisory — informational only, never affects the exit code.
  if [ "${#UPDATES[@]}" -gt 0 ]; then
    echo "  Updates available (${#UPDATES[@]}) — optional; nothing here blocks you."
    local u
    for u in ${UPDATES[@]+"${UPDATES[@]}"}; do
      echo ""
      printf '    • %s\n' "${u%%|*}"
      printf '        → %s\n' "${u#*|}"
    done
    echo ""
  fi

  echo "  Next steps"
  if [ "$n_bad" -gt 0 ]; then
    echo "    • Fix the ${n_bad} failure(s) above, then re-run ./claude-bootstrap.sh"
  fi
  echo "    • Restart your shell (or run: source ~/${SHELL_RC_NAME})"
  echo "    • Run \`claude\` in any project to verify"
  if [ -n "${BOOTSTRAP_LOG:-}" ]; then
    echo "    • Full run log: ${BOOTSTRAP_LOG}"
  fi
  echo "    • Pencil: install the app from pencil.dev — its MCP server registers"
  echo "      itself with Claude Code whenever the app is running"
  if [ "$n_bad" -gt 0 ]; then
    echo ""
    echo "  Exit code: 1 (failures present)"
  fi
  echo ""
}

print_report

# Exit contract: 0 success (warnings ok) · 1 step/verify failures · 2 preflight.
_fail_count=0
for _rec in ${STEP_RECORDS[@]+"${STEP_RECORDS[@]}"}; do
  case "${_rec%%|*}" in fail) _fail_count=$((_fail_count + 1)) ;; esac
done
if [ "$_fail_count" -gt 0 ] || [ "${#verify_errors[@]}" -gt 0 ]; then
  exit 1
fi
