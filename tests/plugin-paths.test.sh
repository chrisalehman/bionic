#!/bin/bash
# PLUGIN PATH LITERALS — the rewrite wall for epic-17 wave-01 slice S3.
#
# Governing evidence: .bionic/docs/record/epic-17-discovery/repo-inventory.md §9 finding 7
# ("Nineteen ~/.claude/hooks/... literals must become ${CLAUDE_PLUGIN_ROOT}, and they sit
# beside near-identical strings that must NOT").
#
# WHAT THIS SUITE EXISTS FOR. A plugin payload is mounted at ${CLAUDE_PLUGIN_ROOT}, not at
# ~/.claude/hooks/. Two DIFFERENT rewrites carry that, and the whole hazard of this slice is
# that a mechanical find-and-replace would apply one rule to all of them:
#
#   1. HOOK REGISTRATION (skills/canonical-sdlc/SKILL.md frontmatter) → ${CLAUDE_PLUGIN_ROOT}.
#      The plugin mechanism substitutes that variable when it REGISTERS a hook command
#      (plugin-api-affordances.md §"${CLAUDE_PLUGIN_ROOT} Substitution": supported "in hook
#      commands, MCP server configurations ... and LSP server command/args"). It is a
#      registration-time substitution, not an exported shell variable.
#
#   2. SIBLING-SCRIPT INVOCATION (inside hooks/*.sh) → resolved from "$0".
#      These scripts must run OUTSIDE any plugin context — the test harness runs them
#      straight out of the repo — so they may NOT depend on ${CLAUDE_PLUGIN_ROOT}. A hook
#      and the script it invokes always share one directory, so "$(dirname "$0")" resolves
#      identically in a repo checkout, in a bootstrap-installed ~/.claude/hooks/, and in an
#      installed plugin payload. This is the idiom hooks/dispatch-preflight.sh:301 and
#      hooks/landing-gate.sh already used before the conversion.
#
# WHAT MUST NOT MOVE. State paths spelled almost identically to the command paths above.
# They address Claude Code's OWN data, not bionic's payload, and rewriting them to plugin
# root would break them. They are asserted present, verbatim, at the bottom of this suite.
#
# Usage: bash tests/plugin-paths.test.sh

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
G=/usr/bin/grep   # the shell `grep` on this machine is ugrep and skips/mis-reports; see
                  # .claude/rules — every absence claim here goes through the real grep.

PASS=0
FAIL=0

ok()  { echo "PASS: $1"; PASS=$((PASS + 1)); }
no()  { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# The two spellings of the installed-hooks directory that a command literal can carry.
# `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/` is deliberately NOT here: it is the
# exotic-invocation fallback at dispatch-preflight.sh:302, which stays correct for as long
# as claude-bootstrap.sh keeps installing to that directory (through W5).
FORBIDDEN='~/\.claude/hooks/|\$HOME/\.claude/hooks/'

# ============================================================
echo "=== A — skills/canonical-sdlc/SKILL.md: the registration channel ==="
# ============================================================
#
# The `hooks:` frontmatter block is the whole of the rewrite class here. Every `command:`
# in it is registered by the plugin mechanism, which is exactly where ${CLAUDE_PLUGIN_ROOT}
# is substituted.

SKILL="${REPO}/skills/canonical-sdlc/SKILL.md"

# The frontmatter block, bounded generously. The eleven commands live at :9–:56 today; the
# bound is 80 so a line-shifting edit inside the block still gets scanned rather than
# silently falling out of the window.
FM=$(sed -n '1,80p' "$SKILL")

if printf '%s\n' "$FM" | $G -qE -- "$FORBIDDEN"; then
  no "frontmatter carries no installed-path hook literal"
  printf '%s\n' "$FM" | $G -nE -- "$FORBIDDEN" | sed 's/^/       /'
else
  ok "frontmatter carries no installed-path hook literal"
fi

N_ROOT=$(printf '%s\n' "$FM" | $G -cF -- 'command: ${CLAUDE_PLUGIN_ROOT}/hooks/')
if [ "$N_ROOT" = "11" ]; then
  ok "frontmatter registers exactly 11 commands under \${CLAUDE_PLUGIN_ROOT}/hooks/"
else
  no "frontmatter registers exactly 11 commands under \${CLAUDE_PLUGIN_ROOT}/hooks/ (got ${N_ROOT})"
fi

# Each registered script, by name — a count alone would pass if one command were duplicated
# and another dropped.
for s in canonical-sdlc-evidence-gate farm-out-reminder stop-guard dispatch-preflight \
         canonical-sdlc-governing-skill execution-recorder context-spend landing-gate; do
  if printf '%s\n' "$FM" | $G -qF -- "command: \${CLAUDE_PLUGIN_ROOT}/hooks/${s}.sh"; then
    ok "  registered: ${s}.sh"
  else
    no "  registered: ${s}.sh"
  fi
done

# ---- the two prose lines this slice deliberately did NOT rewrite ----
#
# SKILL.md:497 and :515 hand an OPERATOR (or the model, through the Bash tool) a command to
# type. They are not hook registrations, so nothing substitutes ${CLAUDE_PLUGIN_ROOT} in
# them, and the docs do not establish that the variable is exported into a tool shell. They
# are pinned here as KNOWN-UNCONVERTED so the open question stays visible instead of being
# quietly absorbed: whoever gives operator commands a plugin-layout spelling must delete
# these two pins in the same change.
for pin in 'bash ~/.claude/hooks/session-poker.sh' 'bash ~/.claude/hooks/stop-orders.sh'; do
  if $G -qF -- "$pin" "$SKILL"; then
    ok "known-unconverted operator command still pinned: ${pin}"
  else
    no "known-unconverted operator command still pinned: ${pin} (if this was converted, delete this pin)"
  fi
done

# ============================================================
echo ""
echo "=== B — hooks/*.sh: no installed-path literal on any executable line ==="
# ============================================================
#
# Comments are exempt and only comments are. `# Installed globally by claude-bootstrap.sh to
# ~/.claude/hooks/` is TRUE for as long as the bootstrap is the live install mechanism, which
# this epic keeps through W5 — rewriting it in W1 would replace a true statement with a
# false one. What may not survive is a literal on a line that RUNS or that the machinery
# PRINTS as a command to run.

check_script() {  # <relative-path>
  local rel="$1" file="${REPO}/$1" hits
  # Strip comment-only lines (first non-blank character is `#`), then look for the literal.
  hits=$($G -nE -- "$FORBIDDEN" "$file" | $G -vE '^[0-9]+:[[:space:]]*#' || true)
  if [ -z "$hits" ]; then
    ok "${rel} — no installed-path literal on an executable line"
  else
    no "${rel} — no installed-path literal on an executable line"
    printf '%s\n' "$hits" | sed 's/^/       /'
  fi
}

# EVERY shipped hook script, not the enumerated four. The inventory's finding-7 list named
# dispatch-preflight, stop-guard, session-sweeper and session-poker; driving the suite found
# three more scripts printing an installed-path command at RUNTIME — preflight-probe.sh
# (:413, :456), stop-check.sh (:46) and stop-orders.sh (:72, :74). The gap was invisible from
# the enumeration because hooks/dispatch-preflight.test.sh asserts on the fix line the GATE
# emits, and that line is the PROBE's stderr passed through: the gate's own literal was
# rewritten and the assertion still passed, because the string was coming from a file nobody
# had looked at. Globbing is what closes that class — an enumeration can only ever pin what
# somebody already noticed.
for s in "${REPO}"/hooks/*.sh; do
  case "$s" in *.test.sh) continue ;; esac
  check_script "hooks/$(basename "$s")"
done

# ---- and the positive form: each command constant resolves from "$0" ----
#
# Asserting only the absence would pass if a constant were deleted outright. These pin what
# each one became.
expect_line() {  # <label> <needle> <relative-path>
  if $G -qF -- "$2" "${REPO}/$3"; then ok "$1"; else no "$1 (missing '$2' in $3)"; fi
}

expect_line "dispatch-preflight resolves the probe beside itself" \
  'PREFLIGHT_CMD="bash ${HOOK_DIR}/preflight-probe.sh"' hooks/dispatch-preflight.sh
expect_line "stop-guard resolves stop-check beside itself" \
  'OBSERVE_CMD="bash ${HOOK_DIR}/stop-check.sh"' hooks/stop-guard.sh
expect_line "stop-guard resolves stop-orders beside itself" \
  'ORDER_CMD="bash ${HOOK_DIR}/stop-orders.sh order"' hooks/stop-guard.sh
expect_line "session-sweeper names itself by its own resolved path" \
  'ACK_COMMAND="bash ${HOOK_DIR}/session-sweeper.sh ack"' hooks/session-sweeper.sh
expect_line "session-sweeper's verdict command likewise" \
  'VERDICT_COMMAND="bash ${HOOK_DIR}/session-sweeper.sh verdict"' hooks/session-sweeper.sh
expect_line "session-poker's usage names its own resolved path" \
  'bash ${HOOK_DIR}/session-poker.sh tick' hooks/session-poker.sh
expect_line "preflight-probe's re-run line names its own resolved path" \
  'bash ${HOOK_DIR}/preflight-probe.sh' hooks/preflight-probe.sh
expect_line "stop-check's usage names its own resolved path" \
  'bash ${HOOK_DIR}/stop-check.sh <agent-name-or-id>' hooks/stop-check.sh
expect_line "stop-orders' usage names its own resolved path" \
  'bash ${HOOK_DIR}/stop-orders.sh order' hooks/stop-orders.sh

# Every one of those needs HOOK_DIR to actually exist and to be derived from "$0" — a
# constant referencing an unset variable under `set -u` would abort the hook.
for s in dispatch-preflight stop-guard session-sweeper session-poker \
         preflight-probe stop-check stop-orders; do
  if $G -qF -- 'HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"' "${REPO}/hooks/${s}.sh"; then
    ok "  ${s}.sh derives HOOK_DIR from \$0"
  else
    no "  ${s}.sh derives HOOK_DIR from \$0"
  fi
done

# ---- hooks must NOT depend on the plugin variable ----
#
# The harness runs these scripts straight out of the repo, with no plugin mounted. A hook
# that reached for ${CLAUDE_PLUGIN_ROOT} would resolve it to nothing under `set -u`, or to
# an empty prefix without it — the exact failure this slice's two-rule split avoids.
# Comment-only lines are exempt for the same reason as in check_script — and here they are
# load-bearing documentation: each rewritten script says in a comment WHY it resolves from
# `$0` and not from the plugin variable. A mention cannot break a hook; a use can.
PR_HITS=$($G -nF -- '${CLAUDE_PLUGIN_ROOT}' "${REPO}"/hooks/*.sh 2>/dev/null \
          | $G -vE ':[0-9]+:[[:space:]]*#' || true)
if [ -z "$PR_HITS" ]; then
  ok "no hook script depends on \${CLAUDE_PLUGIN_ROOT}"
else
  no "no hook script depends on \${CLAUDE_PLUGIN_ROOT}"
  printf '%s\n' "$PR_HITS" | sed 's/^/       /'
fi

# ============================================================
echo ""
echo "=== C — the look-alikes that must NOT have moved ==="
# ============================================================
#
# Inventory §9 finding 7 names these as the strings a mechanical sweep would have broken.
# They are STATE paths (Claude Code's own transcripts, the audit sink) or the still-live
# bootstrap install target — none of them addresses bionic payload.

expect_line "stop-check reads Claude Code's own project transcripts" \
  '${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects' hooks/stop-check.sh
expect_line "dispatch-preflight's roster config dir is untouched" \
  'ROSTER_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"' hooks/dispatch-preflight.sh
expect_line "dispatch-preflight keeps the config-dir probe fallback" \
  'PROBE_SCRIPT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/preflight-probe.sh"' hooks/dispatch-preflight.sh

# The audit sink, in all three writers.
for s in hooks/context-spend.sh hooks/farm-out-reminder.sh hooks/canonical-sdlc-governing-skill.sh; do
  if $G -qF -- '$HOME/.claude/logs' "${REPO}/${s}"; then
    ok "audit sink unchanged in $(basename "$s")"
  else
    no "audit sink unchanged in $(basename "$s")"
  fi
done

# claude-bootstrap.sh is out of this epic's W1 scope entirely — it stays the live install
# mechanism until W5, and its six MANAGED_HOOKS literals must still spell the directory it
# installs to. This is the pin that fails loudly if a later sweep gets mechanical.
BOOT="${REPO}/claude-bootstrap.sh"
N_MANAGED=$($G -cF -- '~/.claude/hooks/' "$BOOT")
if [ "$N_MANAGED" -ge 6 ]; then
  ok "claude-bootstrap.sh still installs to ~/.claude/hooks/ (${N_MANAGED} references)"
else
  no "claude-bootstrap.sh still installs to ~/.claude/hooks/ (${N_MANAGED} references, expected >= 6)"
fi
for m in 'PreToolUse|Bash|~/.claude/hooks/protect-main.sh' \
         'PreToolUse|Bash|~/.claude/hooks/protect-database.sh' \
         'SubagentStop||~/.claude/hooks/agent-context-guard.sh ~/.claude/hooks/landing-gate.sh'; do
  if $G -qF -- "\"$m\"" "$BOOT"; then
    ok "  MANAGED_HOOKS entry intact: ${m%%|*}…"
  else
    no "  MANAGED_HOOKS entry intact: ${m}"
  fi
done

# ============================================================
echo ""
echo "──────────────────────────────────────────────"
echo "plugin-paths: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
echo "All plugin-path assertions green ✓"
