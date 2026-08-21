#!/bin/bash
# Tests for the repo's config file, its hook roster, and the .claude/rules/
# roster. (Named for claude-bootstrap.sh/claude-reset.sh, which it also covered
# until those retired at epic-17 W5 — see the retired Sections 3 and 5.)
# Covers config parsing, config file well-formedness, script symmetry,
# hook consistency, and shell alias marker consistency.
# Does NOT run bootstrap or reset — no side effects.
#
# Usage: bash tests/scripts.test.sh

set -euo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/frontmatter-parser.sh"

REPO="${BIONIC_SCRIPTS_DIR}"

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
# Set to a tmpfile for Section 1 parsing tests — read_config's own logic is what's under
# test, not any particular file's contents (the repo's dependency roster is
# payload/scripts/lib/deps.sh's alone; see Section 2).
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
# SECTION 2: No dead dependency config at the repo root
# ============================================================
#
# claude-config.txt and claude-config.everything.txt were the bootstrap era's
# dependency roster, superseded by payload/scripts/lib/deps.sh and deleted at
# epic-17 W6 (A-4.S3.F): the dependency roster has exactly ONE owner now. This
# section pins that no second declaring file has reappeared at the repo root
# to drift out of sync with it. (The type/entry-shape coverage this section
# used to run against claude-config.txt's contents lives on structurally in
# Section 1, which drives the same read_config parser against synthetic
# fixtures — that coverage was always of the parser, not of any one file's
# bytes.)

echo ""
echo "=== Section 2: No dead dependency config at the repo root ==="

_stray_config=""
for _cfg in "${REPO}"/claude-config*.txt; do
  [ -f "$_cfg" ] || continue
  _stray_config="${_stray_config}$(basename "$_cfg") "
done
expect_eq "no claude-config*.txt at the repo root — the dependency roster has one owner, payload/scripts/lib/deps.sh" "" "$_stray_config"

# ============================================================
# SECTION 3: RETIRED — bootstrap/reset script symmetry
# ============================================================
#
# claude-bootstrap.sh and claude-reset.sh were DELETED at epic-17 W5 (4/6):
# the plugin channel installs the payload now, and /bionic:setup carries the
# two obligations the installer still owned (the legacy .zshrc alias block and
# the legacy-channel managed-hook entries). This section asserted symmetry
# BETWEEN those two files — every claim in it named at least one of them, so
# there is nothing left here to point at and no surviving surface the claims
# could be retargeted to.
#
# Where the coverage went, so this is a move and not a loss:
#   - config-type reading (3c-3k)   -> Section 1 already drives read_config
#                                      directly, over the same claude-config.txt
#   - install/remove symmetry        -> tests/setup.test.sh (setup side) and
#                                      tests/remove.test.sh (removal side),
#                                      both against the shipped payload
#   - lib/platform.sh sourcing (3o)  -> the library retired WITH those two
#                                      consumers at the Step-6 review: nothing in
#                                      the payload ever sourced it, so its own
#                                      suite was its last one. tests/run.sh
#                                      carries the note on where its facts went.
#   - manifest symmetry (3x2)        -> the manifests were install-time
#                                      artifacts of the retired installer

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

# 4c: Every hook the ALWAYS-ON channel registers exists in hooks/.
#
# The array this used to read — claude-bootstrap.sh's MANAGED_HOOKS — retired
# with the installer at epic-17 W5 (4/6). Its successor is the payload's own
# hooks/hooks.json, which is what the CLI reads to register the always-on
# walls; the registrations there spell their commands
# ${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh. The check is unchanged in kind: a
# registration naming a file that is not there is a wall that cannot fire, and
# it is the registration side, not the file side, that has always been the one
# that drifts.
HOOKS_JSON="${BIONIC_HOOKS_DIR}/hooks.json"
expect_true "payload hooks.json exists (the always-on channel)" test -f "$HOOKS_JSON"

_alwayson_commands="$(jq -r '[.hooks | to_entries[] | .value[]? | .hooks[]? | .command] | .[]' "$HOOKS_JSON" 2>/dev/null)"

_missing_managed_hooks=""
for _word in $_alwayson_commands; do
  case "$_word" in
    *'/hooks/'*.sh)
      _bn="$(basename "$_word")"
      [ -f "${BIONIC_HOOKS_DIR}/${_bn}" ] || _missing_managed_hooks="${_missing_managed_hooks}${_bn} "
      ;;
  esac
done
expect_eq "every hooks.json registration names a file that exists in hooks/" "" "$_missing_managed_hooks"

# Every always-on command is rooted at ${CLAUDE_PLUGIN_ROOT} — never an
# installed-path literal. This is the channel half of the same claim
# tests/plugin-paths.test.sh makes about the payload's contents.
_unrooted=""
for _word in $_alwayson_commands; do
  case "$_word" in
    '${CLAUDE_PLUGIN_ROOT}/hooks/'*) ;;
    *) _unrooted="${_unrooted}${_word} " ;;
  esac
done
expect_eq "every hooks.json command is rooted at \${CLAUDE_PLUGIN_ROOT}/hooks/" "" "$_unrooted"

# 4d: the always-on channel registers protect-main.sh
expect_true "always-on channel registers protect-main.sh" \
  /usr/bin/grep -qF '${CLAUDE_PLUGIN_ROOT}/hooks/protect-main.sh' "$HOOKS_JSON"

# 4e: the always-on channel registers protect-database.sh
expect_true "always-on channel registers protect-database.sh" \
  /usr/bin/grep -qF '${CLAUDE_PLUGIN_ROOT}/hooks/protect-database.sh' "$HOOKS_JSON"

# 4h: canonical-sdlc-evidence-gate.sh is ARMED-SCOPED, not always-on
# (session-20260814-wave-detector-terminal-state, R1). It must be absent from
# the always-on channel and present in the skill frontmatter. The claim used to
# be made against MANAGED_HOOKS; hooks.json is the same claim on the channel
# that replaced it. (The shell's bare `grep` is ugrep with ignore-files active
# and lies about absence, so every absence check here goes through
# /usr/bin/grep.)
expect_false "always-on channel does NOT register canonical-sdlc-evidence-gate.sh (armed-scoped, SKILL.md frontmatter)" \
  /usr/bin/grep -qF 'canonical-sdlc-evidence-gate.sh' "$HOOKS_JSON"

# Shared with cross-gate-agreement.test.sh via tests/lib/frontmatter-parser.sh
# (epic-17 W4 AC-12 dedupe).
expect_true "skills/canonical-sdlc/SKILL.md frontmatter registers canonical-sdlc-evidence-gate.sh as PreToolUse|Bash" \
  skill_hooks_has "${BIONIC_SKILLS_DIR}/canonical-sdlc/SKILL.md" PreToolUse Bash \
    '${CLAUDE_PLUGIN_ROOT}/hooks/canonical-sdlc-evidence-gate.sh'

# 4i: farm-out-reminder.sh is armed-scoped for the same reason
# (session-20260815-landing-supervision T5, AC-6) — it guards a workflow
# preference rather than irreversible damage, so it binds only in armed
# sessions, sharing the PreToolUse|Bash matcher entry with 4h's hook.
expect_false "always-on channel does NOT register farm-out-reminder.sh (armed-scoped, SKILL.md frontmatter)" \
  /usr/bin/grep -qF 'farm-out-reminder.sh' "$HOOKS_JSON"

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

# 4r: README promotes canonical-sdlc as flagship (Wave 6 closure; Wave 7 repointed
# link; RE-POINTED at wave-06 S13, when the README was rewritten from the payload).
#
# THE OBLIGATION IS UNCHANGED and it is what these four pin: the README must present
# canonical-sdlc as the flagship, must name it the way a user invokes it, and must
# tell a reader that BOTH lifecycle walls exist. What moved is the RENDERING. The
# retired spellings pinned the shape of a page that no longer exists — a bold
# `**Canonical SDLC**` list item inside a patterns section the user deleted, and one
# sentence naming the two wall SCRIPTS by filename. That page is product-facing and
# the rewrite bans internal names on it, so a filename pin would now require the
# README to break its own rule to stay green. These pin the CLAIMS instead, each in
# the words the page actually uses, so a rewrite that drops one still goes red.
expect_true "README presents canonical-sdlc as the flagship" \
  grep -qE 'centerpiece is .?canonical-sdlc' "${REPO}/README.md"
expect_true "README names the skill as a user invokes it" \
  grep -q 'bionic:canonical-sdlc' "${REPO}/README.md"
expect_true "README states the commit-evidence wall" \
  grep -q 'no evidence for the step' "${REPO}/README.md"
expect_true "README states the artifact-frontmatter wall" \
  grep -q 'will not write without' "${REPO}/README.md"

# ============================================================
# SECTION 5: RETIRED — shell alias marker consistency
# ============================================================
#
# This section pinned ALIAS_START/ALIAS_END agreement between
# claude-bootstrap.sh and claude-reset.sh, both deleted at epic-17 W5 (4/6).
# The markers themselves did NOT retire — a machine bootstrapped before the
# cutover still carries the block, and removing it is now /bionic:setup's job.
# Their pin moved to tests/setup.test.sh Group 6, which STATES the marker
# literals and requires all three surviving copies to match: setup.sh
# (SETUP_ALIAS_START/END), detect.sh (the presence probe) and remove.sh
# (RM_RC_START/END).

# ============================================================
# SECTION 6: .claude/rules/ roster
# ============================================================

echo ""
echo "=== Section 6: .claude/rules/ roster ==="

# Epic-17 W4 remediation fold (review F-3). The .gitignore negation pair made
# `.claude/rules/` a permanently committable surface — the first part of `.claude/`
# a fresh clone receives. S4 audited its files once, by hand, for machine paths
# and consumer-project names. A one-time audit does not survive the next addition,
# and nothing else in the suite looks at this directory, so the roster itself is the
# wall: a new committed file, a renamed one, or a subdirectory trips this and gets
# the same read S4's originals got.
#
# THE ROSTER WENT FROM FIVE TO FOUR AT W5 (4/8, spec AC-13). `bootstrap-install.md`
# described the installer era whole — install types, sync mechanics, the mirror,
# the blast radius of a bootstrap run — and carried a self-retiring notice naming
# its own trigger: W5's deletion of claude-bootstrap.sh. That trigger fired in 4/6.
# The file was deleted rather than edited down because the notice was explicit that
# nothing in it had a post-bootstrap successor. This pin is what made the deletion
# a deliberate act rather than a silent one: it went red on the `git rm` and had to
# be moved by hand, which is the whole point of stating the roster.
#
# git ls-files, not the filesystem, on purpose. What matters is what a clone RECEIVES.
# An untracked scratch file under .claude/rules/ is machine-local and none of this
# suite's business; a COMMITTED one is a new public surface. `--` separates the
# pathspec so a directory named like a flag cannot be misread, and the pathspec is
# non-empty by construction here (the five files below), which is what keeps this
# from being the silent zero-match failure git-grep-style pathspecs are prone to.
EXPECTED_RULES="agent-discipline.md
git-worktree-docs.md
hook-authoring.md
test-harness.md"

_actual_rules="$(cd "$REPO" && git ls-files -- .claude/rules/ | sed 's#^\.claude/rules/##' | LC_ALL=C sort)"
expect_eq "the committed .claude/rules/ roster is exactly the four audited files" \
  "$EXPECTED_RULES" "$_actual_rules"

# The retirement, stated as its own arm. The roster equality above already fails if
# the file comes back, but it fails as an opaque set mismatch; this names the file
# and the reason, so a revert reports what it reverted rather than that something
# moved. Absence goes through /usr/bin/grep-free machinery on purpose — this is a
# git question, not a text one, and git ls-files cannot lie about a tracked path.
_bootstrap_rule="$(cd "$REPO" && git ls-files -- .claude/rules/bootstrap-install.md)"
expect_eq "the bootstrap-era rules file stays retired (its trigger fired at W5 4/6)" \
  "" "$_bootstrap_rule"

# Stated as its own arm so a subdirectory reports as a subdirectory rather than as an
# opaque roster mismatch: any tracked path under .claude/rules/ with a further slash in
# it is a nested tree the audit never covered.
_nested_rules="$(cd "$REPO" && git ls-files -- .claude/rules/ | sed 's#^\.claude/rules/##' | grep '/' || true)"
expect_eq "no committed subdirectory under .claude/rules/" "" "$_nested_rules"

# ============================================================
# SECTION 7: wsl-setup.sh — the last clone-and-run script
# ============================================================

echo ""
echo "=== Section 7: wsl-setup.sh — the last clone-and-run script ==="

# Epic-17 W5 Step-6 review, RV-2. wsl-setup.sh is the ONE script bionic still asks a
# person to clone the repo and run: a bare Ubuntu box under WSL2 has no CLI to type
# `/bionic:setup` into, so something has to put one there. Everything past that point
# is the plugin channel and then /bionic:setup.
#
# Its two ends both pointed at claude-bootstrap.sh, which 4/6 deleted — the header
# ("installs prerequisites so that claude-bootstrap.sh can run") and, worse, the
# next-steps block, which printed `./claude-bootstrap.sh` as the literal command to
# type next. That is a dead end at the exact moment a new user has done everything
# right, and nothing in the suite was looking at this file, which is why it survived
# a whole wave of installer retirement.
#
# The pin is an AGREEMENT, not a spelling: the commands wsl-setup prints have to be
# the commands README's Install section states, read out of README at run time. A
# rename of the marketplace or the plugin moves both together or fails here.
WSL="${REPO}/wsl-setup.sh"
README_SRC="${REPO}/README.md"

expect_true "wsl-setup.sh exists (it is the WSL entry point README step 4 names)" \
  test -f "$WSL"

# --- 7a: no retired root script survives anywhere in the file ---
for _dead in claude-bootstrap.sh claude-reset.sh; do
  _hits="$(/usr/bin/grep -c -F -- "$_dead" "$WSL" 2>/dev/null || true)"
  expect_eq "wsl-setup.sh names no retired root script: ${_dead}" "0" "${_hits:-0}"
done

# --- 7b: the install commands AGREE with README's Install section ---
#
# Derived, not restated. Every fenced `claude plugin ...` line in README is required to
# appear in wsl-setup.sh's output, so the two surfaces cannot drift apart in one
# direction. Leading whitespace is stripped on both sides — README fences them at
# column 0 and wsl-setup indents them inside an echo — because the agreement is about
# the COMMAND, not its indentation.
_readme_cmds="$(/usr/bin/grep -oE '^claude plugin [a-z]+ [^ ]+.*$' "$README_SRC" | LC_ALL=C sort -u)"
# No backticks in this label: it is inside a double-quoted string, where a backtick pair
# is command substitution and would silently eat the words it was meant to quote.
expect_true "README states at least one plugin-install command to agree with" \
  test -n "$_readme_cmds"

_missing_cmds=""
while IFS= read -r _cmd; do
  [ -n "$_cmd" ] || continue
  /usr/bin/grep -qF -- "$_cmd" "$WSL" || _missing_cmds="${_missing_cmds}${_cmd}; "
done <<EOF
$_readme_cmds
EOF
expect_eq "wsl-setup.sh's next steps carry every README install command" "" "$_missing_cmds"

# --- 7c: and it hands the user to tier 2 rather than stopping at tier 1 ---
#
# Named separately from 7b because it is a different claim: 7b says the plugin gets
# installed, this says the machine gets set up. A WSL box that just ran wsl-setup is
# exactly the box that still needs /bionic:setup, so ending at the plugin install
# would leave the user one undiscoverable step short.
expect_true "wsl-setup.sh points the user at /bionic:setup for the machine tier" \
  /usr/bin/grep -qF -- "/bionic:setup" "$WSL"

# ============================================================
# SECTION 8: SKILL.md's re-converge sentence names update, not install (AC-3)
# ============================================================

echo ""
echo "=== Section 8: SKILL.md re-converge sentence (AC-3) ==="

# epic-17 W7 S2. `claude plugin install <id>` on an already-registered id reports
# "already installed" and does NOT refresh a directory-source cache copy — the CLI's
# own re-converge verb is `update`. SKILL.md's worktree-paragraph asserted the
# install-vs-update semantics with the wrong verb in its own closing clause; this pins
# the fix so the doc and the code (`detect_reconverge_hint`, doctor.sh) cannot drift
# back apart independently.
SKILL_S2="${BIONIC_SKILLS_DIR}/canonical-sdlc/SKILL.md"

_reconverge_update_count="$(/usr/bin/grep -c 'claude plugin update bionic@bionic' "$SKILL_S2" 2>/dev/null || true)"
expect_true "SKILL.md names the update verb for re-convergence at least once" \
  [ "${_reconverge_update_count:-0}" -ge 1 ]

# The specific defect: the closing clause of the worktree paragraph used to read
# "...and `claude plugin install bionic@bionic` is what re-converges them." That exact
# combination (install, immediately followed by "is what re-converges them") must be
# gone — the earlier "plugin not installed — run `claude plugin install bionic@bionic`"
# refusal message in the same paragraph is a DIFFERENT sentence (dispatch-spans.test.sh
# pins it separately) and stays untouched.
expect_false "…and no longer says install is what re-converges them" \
  /usr/bin/grep -qF -- "install bionic@bionic\` is what re-converges them" "$SKILL_S2"
expect_true "…the sentence now says update is what re-converges them" \
  /usr/bin/grep -qF -- "update bionic@bionic\` is what re-converges them" "$SKILL_S2"

# epic-17 W7 S2b. S2's fix above was still wrong on the OTHER half of the sentence: it
# said `update` re-converges them UNCONDITIONALLY, but measured fact (2026-08-21,
# .bionic/docs/record/epic-17-w7/ac2-relay-drive.md) is that on a directory-source
# install — a local checkout registered as a feed, which is what a dogfood install is —
# `claude plugin update bionic@bionic` at an unchanged plugin.json version reports
# "already at the latest version" and refreshes nothing, because the CLI never reads the
# cache it would refresh. The sentence must scope the update claim to a git-source feed
# and say the true, separate thing for a directory-source one.
expect_true "…the update claim is scoped to a git-source feed" \
  /usr/bin/grep -qF -- "on a git-source feed \`claude plugin update bionic@bionic\` is what re-converges them" "$SKILL_S2"
expect_true "…and a directory-source marketplace is told update does nothing for it" \
  /usr/bin/grep -qF -- "on a directory-source marketplace there is nothing to re-converge with that command" "$SKILL_S2"
expect_true "…naming the CLI's own words for that no-op" \
  /usr/bin/grep -qF -- "already at the latest version" "$SKILL_S2"


# ============================================================
# SECTION 9: tests/run.sh — the job runner (epic-17 W7 S10, spec AC-16)
# ============================================================

echo ""
echo "=== Section 9: tests/run.sh — the job runner (AC-16) ==="

# WHY THIS LIVES HERE. Section 4 pins the hook roster and Section 6 the rules
# roster; this pins the shape of the thing that RUNS the suite roster. Every other
# suite asserts its own `run` line exists (A4.S4.1 — there is no count to bump);
# nothing until now asserted what `tests/run.sh` DOES with those lines. S8's
# isolation audit found all 44 suites hermetic under their own `mktemp -d`, which
# is what licenses running them concurrently; this section is the wall that keeps
# the two modes honest afterwards.
#
# HOW IT TESTS THE REAL FILE. Every arm drives a throwaway COPY of tests/run.sh in
# which only the `run "…"` roster lines have been swapped for fixture ones. Flag
# parsing, the queue, the worker fork, the verdict printer, the summary line and
# the exit status are the real file's own code — a fixture roster is the only way
# to get a deterministic, seconds-long drive of a runner whose real roster takes a
# quarter of an hour.
#
# WHY THE CONCURRENCY ARMS USE A BARRIER AND NOT A STOPWATCH. "Parallel is faster"
# is a wall-clock claim, and wall-clock under a loaded machine is exactly the
# flaky-test shape this repo keeps banning. A barrier is load-independent: each
# fixture suite appends a line and then passes only if it can SEE N lines while it
# is still running. N suites can only all pass if N of them were alive at once, and
# a suite that runs alone can never see a second line. The pass/fail SIGNATURE is
# therefore a direct read of the job count, with no timing assumption in it.

RUNNER_TMP="$(mktemp -d)"

cleanup() {
  rm -f "$S1_TMPFILE" "$S1_TMPFILE2"
  rm -rf "$RUNNER_TMP"
}

RUN_SH_UNDER_TEST="${REPO}/tests/run.sh"

# mk_runner <dir> <roster-line>...
# A copy of the real runner whose roster block is the lines given here. The awk
# splices the fixture roster in at the position of the first real `run` line and
# drops every other one, so the surrounding code — including the comments that
# explain the hand-listing discipline — is byte-for-byte the shipped file.
mk_runner() {
  local dir="$1"; shift
  mkdir -p "$dir/tests/lib" "$dir/tests/fx"
  cp "$RUN_SH_UNDER_TEST" "$dir/tests/run.sh.orig"
  cp "${REPO}/tests/lib/resolve-roots.sh" "$dir/tests/lib/resolve-roots.sh"
  local roster="$dir/roster.txt"
  : > "$roster"
  local line
  for line in "$@"; do printf '%s\n' "$line" >> "$roster"; done
  awk -v roster="$roster" '
    /^run "/ {
      if (!spliced) { while ((getline l < roster) > 0) print l; spliced = 1 }
      next
    }
    { print }
  ' "$dir/tests/run.sh.orig" > "$dir/tests/run.sh"
  rm -f "$dir/tests/run.sh.orig"
}

# mk_fixture_suites <dir> — the fixture suites every arm below draws from.
mk_fixture_suites() {
  local d="$1/tests/fx"
  printf '%s\n' '#!/bin/bash' 'exit 0' > "$d/green.sh"
  printf '%s\n' '#!/bin/bash' 'echo "fixture: an assertion failed"' 'exit 1' > "$d/red.sh"
  printf '%s\n' '#!/bin/bash' 'echo "fixture: about to die"' 'kill -9 $$' > "$d/killer.sh"
  printf '%s\n' '#!/bin/bash' 'sleep 1' 'exit 0' > "$d/slow.sh"
  # The barrier: appears alive to its peers, then passes only if BARRIER_N of them
  # are alive at the same time. 4 s ceiling, polled — never a bare sleep of the
  # length being measured.
  cat > "$d/barrier.sh" <<'BARRIER'
#!/bin/bash
echo "$$" >> "$BARRIER_FILE"
i=0
while [ "$i" -lt 40 ]; do
  n="$(wc -l < "$BARRIER_FILE" | tr -d ' ')"
  [ "$n" -ge "$BARRIER_N" ] && exit 0
  sleep 0.1
  i=$((i + 1))
done
exit 1
BARRIER
}

# drive <dir> <outfile> [args...] — run the fixture runner, capture everything,
# leave its exit status in DRIVE_RC. Never lets a red fixture abort this suite.
#
# EVERY KNOB THE RUNNER READS IS SET HERE, ON EVERY CALL — never inherited. The
# arms below fingerprint the job count by how many barrier suites can see one
# another, so a `BIONIC_TEST_JOBS=2` already in the operator's shell would report
# a perfectly-behaving runner as red; and an inherited BIONIC_TEST_TIMING would
# have each fixture drive append its labels to the operator's timing file — a
# write outside the fixture root, which is the one thing S8's isolation audit
# exists to forbid. Empty means "as shipped": the runner's own
# `${BIONIC_TEST_JOBS:-4}` reads an empty value as unset.
DRIVE_RC=0
DRIVE_JOBS=""      # per-arm job count; "" = the runner's shipped default
DRIVE_TIMING=""    # per-arm timing file; "" = timing off
drive() {
  local dir="$1" out="$2"; shift 2
  DRIVE_RC=0
  ( cd "$dir" \
      && BIONIC_TEST_JOBS="$DRIVE_JOBS" BIONIC_TEST_TIMING="$DRIVE_TIMING" \
         bash tests/run.sh "$@" ) > "$out" 2>&1 || DRIVE_RC=$?
}

# ---------- 9.1 the two modes agree, all green ----------

A1="$RUNNER_TMP/a1"
mk_runner "$A1" \
  'run "one.test.sh" bash tests/fx/green.sh' \
  'run "two.test.sh" bash tests/fx/green.sh' \
  'run "three.test.sh" bash tests/fx/green.sh'
mk_fixture_suites "$A1"

drive "$A1" "$A1/serial.txt" --serial
_a1_serial_rc="$DRIVE_RC"
drive "$A1" "$A1/parallel.txt"
_a1_parallel_rc="$DRIVE_RC"

expect_eq "--serial is a recognised flag (an all-green roster exits 0)" \
  "0" "$_a1_serial_rc"
expect_eq "the default mode exits 0 on the same all-green roster" \
  "0" "$_a1_parallel_rc"
expect_true "an all-green run is byte-identical in both modes" \
  diff -q "$A1/serial.txt" "$A1/parallel.txt"
expect_true "…and it is the real summary line, not a stub" \
  /usr/bin/grep -qF "Gating: 3 passed, 0 failed" "$A1/parallel.txt"

# ---------- 9.2 the two modes agree with a failure in the roster ----------

A2="$RUNNER_TMP/a2"
mk_runner "$A2" \
  'run "one.test.sh" bash tests/fx/green.sh' \
  'run "two.test.sh" bash tests/fx/red.sh' \
  'run "three.test.sh" bash tests/fx/green.sh'
mk_fixture_suites "$A2"

drive "$A2" "$A2/serial.txt" --serial
_a2_serial_rc="$DRIVE_RC"
drive "$A2" "$A2/parallel.txt"
_a2_parallel_rc="$DRIVE_RC"

expect_eq "a red suite fails the serial run" "1" "$_a2_serial_rc"
expect_eq "a red suite fails the default run identically" "1" "$_a2_parallel_rc"
expect_true "a red roster is byte-identical in both modes, captured output included" \
  diff -q "$A2/serial.txt" "$A2/parallel.txt"
expect_true "…the captured-output block survives the parallel path" \
  /usr/bin/grep -qF "fixture: an assertion failed" "$A2/parallel.txt"
expect_true "…and the summary counts it" \
  /usr/bin/grep -qF "Gating: 2 passed, 1 failed" "$A2/parallel.txt"

# ---------- 9.3 results print in roster order, not completion order ----------

A3="$RUNNER_TMP/a3"
mk_runner "$A3" \
  'run "slow.test.sh" bash tests/fx/slow.sh' \
  'run "quick.test.sh" bash tests/fx/green.sh'
mk_fixture_suites "$A3"
drive "$A3" "$A3/parallel.txt"

_slow_line="$(/usr/bin/grep -n 'slow.test.sh' "$A3/parallel.txt" | head -1 | cut -d: -f1 || true)"
_quick_line="$(/usr/bin/grep -n 'quick.test.sh' "$A3/parallel.txt" | head -1 | cut -d: -f1 || true)"
_order_ok=0
if [ -n "$_slow_line" ] && [ -n "$_quick_line" ] && [ "$_slow_line" -lt "$_quick_line" ]; then
  _order_ok=1
fi
expect_eq "the slow suite still prints first — roster order, not finish order" "1" "$_order_ok"

# ---------- 9.4 a suite killed by a signal is reported as KILLED ----------

A4="$RUNNER_TMP/a4"
mk_runner "$A4" \
  'run "killer.test.sh" bash tests/fx/killer.sh'
mk_fixture_suites "$A4"

drive "$A4" "$A4/serial.txt" --serial
_a4_serial_rc="$DRIVE_RC"
drive "$A4" "$A4/parallel.txt"
_a4_parallel_rc="$DRIVE_RC"

# A4.2: with seven full suites running concurrently the kernel SIGKILLed one of
# them and the old runner printed a plain ✗ FAIL, which reads as "this suite's
# assertions failed" and sent the reader looking for a defect that was not there.
expect_true "a SIGKILLed suite reports KILLED, with the signal named (serial)" \
  /usr/bin/grep -qF "✗ KILLED (SIGKILL)" "$A4/serial.txt"
expect_true "a SIGKILLed suite reports KILLED, with the signal named (parallel)" \
  /usr/bin/grep -qF "✗ KILLED (SIGKILL)" "$A4/parallel.txt"
expect_false "…and never as a plain assertion failure (serial)" \
  /usr/bin/grep -qF "✗ FAIL" "$A4/serial.txt"
expect_false "…and never as a plain assertion failure (parallel)" \
  /usr/bin/grep -qF "✗ FAIL" "$A4/parallel.txt"
expect_true "…the Failed: list names the signal too" \
  /usr/bin/grep -qF "killed by SIGKILL" "$A4/parallel.txt"
expect_true "…it still counts as failed" \
  /usr/bin/grep -qF "Gating: 0 passed, 1 failed" "$A4/parallel.txt"
expect_eq "…and it still fails the run (serial)" "1" "$_a4_serial_rc"
expect_eq "…and it still fails the run (parallel)" "1" "$_a4_parallel_rc"

# ---------- 9.5 the default job count is exactly 4 ----------

# Four barrier suites needing four peers: passes only if four ran at once.
A5="$RUNNER_TMP/a5"
mk_runner "$A5" \
  'run "b1.test.sh" bash tests/fx/barrier.sh' \
  'run "b2.test.sh" bash tests/fx/barrier.sh' \
  'run "b3.test.sh" bash tests/fx/barrier.sh' \
  'run "b4.test.sh" bash tests/fx/barrier.sh'
mk_fixture_suites "$A5"
export BARRIER_FILE="$A5/barrier" BARRIER_N=4
drive "$A5" "$A5/out.txt"
unset BARRIER_FILE BARRIER_N
expect_true "the default mode really runs four suites at once" \
  /usr/bin/grep -qF "Gating: 4 passed, 0 failed" "$A5/out.txt"

# Five barrier suites needing five peers: the first four time out together, the
# fifth starts as they die and sees all five lines. `1 passed, 4 failed` is the
# fingerprint of a job count of exactly four — a count of five would be 5 passed.
A6="$RUNNER_TMP/a6"
mk_runner "$A6" \
  'run "b1.test.sh" bash tests/fx/barrier.sh' \
  'run "b2.test.sh" bash tests/fx/barrier.sh' \
  'run "b3.test.sh" bash tests/fx/barrier.sh' \
  'run "b4.test.sh" bash tests/fx/barrier.sh' \
  'run "b5.test.sh" bash tests/fx/barrier.sh'
mk_fixture_suites "$A6"
export BARRIER_FILE="$A6/barrier" BARRIER_N=5
drive "$A6" "$A6/out.txt"
unset BARRIER_FILE BARRIER_N
expect_true "…and not five — the default is bounded, well below the roster size (A4.2)" \
  /usr/bin/grep -qF "Gating: 1 passed, 4 failed" "$A6/out.txt"
expect_true "the default job count is named as a settable knob in the runner" \
  /usr/bin/grep -qF 'BIONIC_TEST_JOBS:-4' "$RUN_SH_UNDER_TEST"

# ---------- 9.6 BIONIC_TEST_JOBS overrides it, and --serial means one ----------

A7="$RUNNER_TMP/a7"
mk_runner "$A7" \
  'run "b1.test.sh" bash tests/fx/barrier.sh' \
  'run "b2.test.sh" bash tests/fx/barrier.sh' \
  'run "b3.test.sh" bash tests/fx/barrier.sh'
mk_fixture_suites "$A7"
export BARRIER_FILE="$A7/barrier" BARRIER_N=3
DRIVE_JOBS=2
drive "$A7" "$A7/out.txt"
DRIVE_JOBS=""
unset BARRIER_FILE BARRIER_N
expect_true "BIONIC_TEST_JOBS caps the run (2 jobs, 3 suites needing 3 peers)" \
  /usr/bin/grep -qF "Gating: 1 passed, 2 failed" "$A7/out.txt"

A8="$RUNNER_TMP/a8"
mk_runner "$A8" \
  'run "b1.test.sh" bash tests/fx/barrier.sh' \
  'run "b2.test.sh" bash tests/fx/barrier.sh'
mk_fixture_suites "$A8"
export BARRIER_FILE="$A8/barrier" BARRIER_N=2
drive "$A8" "$A8/out.txt" --serial
unset BARRIER_FILE BARRIER_N
expect_true "--serial runs one at a time — the first suite never sees a peer" \
  /usr/bin/grep -qF "Gating: 1 passed, 1 failed" "$A8/out.txt"

# ---------- 9.6b the fingerprints do not depend on the operator's environment ----------

# The two knobs the runner reads are the two knobs an operator may already have
# set in the shell that runs this suite. Both would corrupt the section silently:
# an ambient BIONIC_TEST_JOBS re-fingerprints every barrier arm above, so a
# runner behaving exactly as specified would report red; an ambient
# BIONIC_TEST_TIMING makes each fixture drive append its labels to a file outside
# its own fixture root — the one thing S8's isolation audit exists to forbid, and
# it is this suite that would be committing it. `drive` therefore sets both on
# every call rather than letting either through.
A11="$RUNNER_TMP/a11"
mk_runner "$A11" \
  'run "b1.test.sh" bash tests/fx/barrier.sh' \
  'run "b2.test.sh" bash tests/fx/barrier.sh' \
  'run "b3.test.sh" bash tests/fx/barrier.sh' \
  'run "b4.test.sh" bash tests/fx/barrier.sh'
mk_fixture_suites "$A11"
export BARRIER_FILE="$A11/barrier" BARRIER_N=4
export BIONIC_TEST_JOBS=2 BIONIC_TEST_TIMING="$A11/leaked.tsv"
drive "$A11" "$A11/out.txt"
unset BARRIER_FILE BARRIER_N BIONIC_TEST_JOBS BIONIC_TEST_TIMING
expect_true "an ambient BIONIC_TEST_JOBS never reaches a fixture drive" \
  /usr/bin/grep -qF "Gating: 4 passed, 0 failed" "$A11/out.txt"
expect_false "…nor does an ambient BIONIC_TEST_TIMING — no fixture writes outside its root" \
  [ -e "$A11/leaked.tsv" ]

# ---------- 9.7 per-suite wall-clock is recordable ----------

# S8 finding (c): no per-suite timing has ever existed, so "which suite is the long
# pole" was answerable only by a line-count proxy. BIONIC_TEST_TIMING is the seam
# that answers it for real; it is opt-in so that setting it cannot change what the
# gating run prints.
A9="$RUNNER_TMP/a9"
mk_runner "$A9" \
  'run "slow.test.sh" bash tests/fx/slow.sh' \
  'run "quick.test.sh" bash tests/fx/green.sh'
mk_fixture_suites "$A9"

DRIVE_TIMING="$A9/timing-parallel.tsv"
drive "$A9" "$A9/parallel.txt"
DRIVE_TIMING="$A9/timing-serial.tsv"
drive "$A9" "$A9/serial.txt" --serial
DRIVE_TIMING=""

_tp="$(wc -l < "$A9/timing-parallel.tsv" 2>/dev/null | tr -d ' ' || echo 0)"
_ts="$(wc -l < "$A9/timing-serial.tsv" 2>/dev/null | tr -d ' ' || echo 0)"
expect_eq "the default mode records one timing row per suite" "2" "$_tp"
expect_eq "--serial records one timing row per suite" "2" "$_ts"
expect_true "…each row is <label>TAB<seconds>" \
  awk -F'\t' 'NF != 2 || $2 !~ /^[0-9]+$/ { bad = 1 } END { exit bad ? 1 : 0 }' "$A9/timing-parallel.tsv"
expect_true "…and the one-second fixture is measured as at least a second" \
  awk -F'\t' '$1 == "slow.test.sh" && $2 >= 1 { found = 1 } END { exit found ? 0 : 1 }' "$A9/timing-parallel.tsv"
expect_true "setting it does not change what the run prints" \
  diff -q "$A9/serial.txt" "$A9/parallel.txt"

# ---------- 9.8 an unknown flag is refused, not ignored ----------

# The old runner ignored argv outright, so `bash tests/run.sh --serial` before this
# slice ran the whole roster and looked like it had honoured a flag it had never
# heard of. A runner that silently accepts any word is a runner whose mode nobody
# can prove.
A10="$RUNNER_TMP/a10"
mk_runner "$A10" 'run "one.test.sh" bash tests/fx/green.sh'
mk_fixture_suites "$A10"
drive "$A10" "$A10/out.txt" --no-such-flag
expect_true "an unknown flag exits nonzero rather than running the roster" \
  [ "$DRIVE_RC" -ne 0 ]
expect_true "…and names the flag it refused" \
  /usr/bin/grep -qF -- "--no-such-flag" "$A10/out.txt"
expect_false "…and does not run a single suite" \
  /usr/bin/grep -qF "✓ PASS" "$A10/out.txt"

# ---------- 9.9 one roster, read by both modes ----------

# The roster stays the hand-listed `run` lines (the whole discipline the runner's
# own header describes). Both modes go through the same helper, so a suite cannot
# be present in one mode and absent from the other.
_run_helper_count="$(/usr/bin/grep -c '^run() {' "$RUN_SH_UNDER_TEST" || true)"
expect_eq "exactly one roster helper defines what gets run" "1" "$_run_helper_count"
_roster_lines="$(/usr/bin/grep -c '^run "' "$RUN_SH_UNDER_TEST" || true)"
expect_true "the roster is still the hand-listed run lines (45 of them today)" \
  [ "$_roster_lines" -ge 45 ]
expect_false "no discovery glob has crept in beside them" \
  /usr/bin/grep -qE '^[^#]*for .* in .*tests/\*\.test\.sh' "$RUN_SH_UNDER_TEST"

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
