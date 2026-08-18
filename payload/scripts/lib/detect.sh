#!/bin/bash
# detect.sh — machine facts, read-only (epic-17 wave-03, spec AC-3/AC-5).
#
# WHAT THIS FILE OWNS. Every observable truth about the machine bionic is
# running on: is the payload intact, is a dependency there and at what version,
# does the shell rc carry the flag, is there a legacy alias block, are there
# stale managed-hook registrations, is this box half-uninstalled. One function
# per fact class, and every door — doctor's report, setup's action list, a
# route's just-in-time offer, remove's teardown — reads the SAME function. A
# second implementation of any of these is the defect the ownership table
# exists to prevent.
#
# THE OUTPUT CONTRACT. One line, parseable, exit 0. Always exit 0: a fact
# function's job is to REPORT, and "I could not tell" is a fact with a value
# (`unknown`), not an error. Callers parse fields; they never branch on the
# exit code. The line shapes are fixed and consumed by later slices verbatim:
#
#   plugin: version=<v> hooks=<ok|degraded|absent>
#   dep:<name> lane=<3a|3b> present=<yes|no|unknown> version=<v|unknown> constraint=<c> verdict=<ok|violation|unknown>
#   env:todo-tools present=<yes|no>
#   env:zshrc-legacy present=<yes|no>
#   env:stale-managed-hooks count=<n|unknown>
#   state:half-uninstalled=<yes|no>
#
# `unknown` APPEARS WHERE HONESTY REQUIRES IT. Two of these values can read
# `unknown` where the spec's table sketched only yes/no: a dependency whose
# mechanism has no presence surface at all (the pnpm store is a cache, not an
# install), and a count that cannot be taken because `jq` — itself one of the
# table's own rows — is missing. The alternative is a confident wrong answer,
# and a doctor that confidently reports a clean machine as dirty is worse than
# one that says it could not look.
#
# READ-ONLY IS A CONTRACT, NOT AN INTENTION. Nothing here writes, creates,
# moves, or removes anything, and `/bionic:doctor` is built entirely on it.
# tests/plugin-lib.test.sh fingerprints a fixture tree before and after a full
# sweep to keep that true.
#
# ROOTS ARE OVERRIDABLE, read at CALL time so one sourced copy can be pointed
# at several roots in turn (the suite does exactly that):
#
#   BIONIC_PLUGIN_ROOT     the payload tree            ${CLAUDE_PLUGIN_ROOT} or this file's ../..
#   BIONIC_CLAUDE_HOME     the CLI's config dir        ${CLAUDE_CONFIG_DIR:-~/.claude}
#   BIONIC_SETTINGS_FILE   user settings.json          <claude-home>/settings.json
#   BIONIC_SHELL_RC        the shell rc bionic edits   ~/.zshrc or ~/.bashrc, per $SHELL
#
# Sourced, never executed:  . "${CLAUDE_PLUGIN_ROOT}/scripts/lib/detect.sh"

# deps.sh is a sibling; the dependency table and the per-mechanism probes live
# there because they are properties of the DEPENDENCY, not of the machine.
# detect_dep below is their only formatter.
# No `dirname`/`basename` anywhere below, on purpose: a library that cannot be
# SOURCED without coreutils is a library that dies on the machine it is most
# needed on (jq missing, PATH broken, a half-uninstalled box). Bash's own
# parameter expansion does the same work with no process at all.
_detect_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}

if ! declare -F check_dep >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$(cd "$(_detect_self_dir)" && pwd -P)/deps.sh"
fi

_detect_plugin_root() {
  if [ -n "${BIONIC_PLUGIN_ROOT:-}" ]; then echo "$BIONIC_PLUGIN_ROOT"; return; fi
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then echo "$CLAUDE_PLUGIN_ROOT"; return; fi
  # lib -> scripts -> payload root
  ( cd "$(_detect_self_dir)/../.." && pwd -P )
}

_detect_shell_rc() {
  if [ -n "${BIONIC_SHELL_RC:-}" ]; then echo "$BIONIC_SHELL_RC"; return; fi
  local shell_name="${SHELL:-/bin/bash}"
  case "${shell_name##*/}" in
    zsh) echo "$HOME/.zshrc" ;;
    *)   echo "$HOME/.bashrc" ;;
  esac
}

# ─── Plugin integrity ────────────────────────────────────────────────────────
#
# Two questions in one line: which version of the payload is running, and are
# its hooks wired to files that actually exist. `degraded` is the interesting
# state — hooks.json present but naming a script that is not there is exactly
# what a partial update or a half-copied install leaves behind, and it is
# invisible to any check that only asks whether hooks.json exists.

detect_plugin_integrity() {
  local root version="unknown" hooks_json hooks_state cmd script tok
  local -a toks
  root="$(_detect_plugin_root)"
  hooks_json="${root}/hooks/hooks.json"

  if [ -f "${root}/.claude-plugin/plugin.json" ]; then
    if command -v jq >/dev/null 2>&1; then
      version="$(jq -r '.version // "unknown"' "${root}/.claude-plugin/plugin.json" 2>/dev/null)"
    else
      version="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "${root}/.claude-plugin/plugin.json" 2>/dev/null \
                 | head -1 | grep -oE '"[^"]+"$' | tr -d '"')"
    fi
    [ -n "$version" ] || version="unknown"
  fi

  if [ ! -f "$hooks_json" ]; then
    hooks_state="absent"
  else
    hooks_state="ok"
    # Every command in hooks.json names a script under the plugin root via
    # ${CLAUDE_PLUGIN_ROOT}. Resolve that prefix against the root we are
    # actually inspecting and confirm the file is there.
    #
    # EVERY token, not just the first. Four of the six shipped entries CHAIN
    # two scripts (`agent-context-guard.sh <inner>`), and the inner one is
    # where the evidence gate, the governing-skill gate and the landing gate
    # live. Reading `${cmd%% *}` alone called a payload missing all three
    # healthy. `read -a` splits on whitespace without letting the shell glob
    # the pieces; the `/*` guard then skips anything that is not a resolved
    # absolute path (a flag, a plain argument, an unexpanded env reference).
    while IFS= read -r cmd; do
      [ -n "$cmd" ] || continue
      read -r -a toks <<<"$cmd"
      for tok in "${toks[@]}"; do
        script="${tok//\$\{CLAUDE_PLUGIN_ROOT\}/$root}"
        script="${script//\$CLAUDE_PLUGIN_ROOT/$root}"
        case "$script" in /*) ;; *) continue ;; esac
        [ -f "$script" ] || { hooks_state="degraded"; break 2; }
      done
    done < <(grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]+"' "$hooks_json" 2>/dev/null \
             | sed -e 's/.*:[[:space:]]*"//' -e 's/"$//')
  fi

  echo "plugin: version=${version} hooks=${hooks_state}"
  return 0
}

# ─── Dependencies ────────────────────────────────────────────────────────────
#
# The fact line for one dependency. Everything factual comes from deps.sh —
# the row from the table, the probe from the mechanism — and this function
# only renders. That split is why there is exactly one place a dependency's
# presence is decided.

detect_dep() {  # <name>
  local name="${1:-}" lane constraint raw present version verdict
  lane="$(dep_field "$name" lane)" || return 1
  constraint="$(dep_field "$name" constraint)"
  raw="$(check_dep "$name")" || return 1
  present="${raw#present=}"; present="${present%%|*}"
  version="${raw#*version=}"; version="${version%%|*}"
  verdict="${raw##*verdict=}"
  echo "dep:${name} lane=${lane} present=${present} version=${version} constraint=${constraint} verdict=${verdict}"
  return 0
}

# ─── Environment class ───────────────────────────────────────────────────────

# The flag current CLI builds need for the native task tools. A commented-out
# line does not count: it is the state a user lands in after commenting the
# export out, and reporting it as present would make setup skip the very
# repair that is wanted.
detect_env_todo_tools() {
  local rc present=no
  rc="$(_detect_shell_rc)"
  if [ -f "$rc" ] && grep -qE '^[[:space:]]*export[[:space:]]+CLAUDE_CODE_ENABLE_TODO_TOOLS=1' "$rc" 2>/dev/null; then
    present=yes
  fi
  echo "env:todo-tools present=${present}"
  return 0
}

# The legacy alias block claude-bootstrap.sh used to write:
#
#     # ─── bionic:start ───
#     alias claude='claude --dangerously-skip-permissions'
#     # ─── bionic:end ───
#
# Auto mode is the default now and the safer equivalent, so the block is
# retired footprint that setup removes. The markers are matched verbatim,
# box-drawing dashes included — they are what makes the block addressable.
detect_zshrc_legacy_block() {
  local rc present=no
  rc="$(_detect_shell_rc)"
  if [ -f "$rc" ] && grep -qF '# ─── bionic:start ───' "$rc" 2>/dev/null; then
    present=yes
  fi
  echo "env:zshrc-legacy present=${present}"
  return 0
}

# Managed-hook entries in USER settings.json that still point at the
# pre-plugin copies under ~/.claude/hooks/. The plugin channel registers hooks
# through the payload's own hooks.json using ${CLAUDE_PLUGIN_ROOT}, so any
# settings.json command naming .claude/hooks/ is a migrated machine's leftover
# — it fires a stale copy of a hook the plugin already provides.
detect_stale_settings_hooks() {
  local settings count
  settings="${BIONIC_SETTINGS_FILE:-${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/settings.json}"
  if ! command -v jq >/dev/null 2>&1; then
    echo "env:stale-managed-hooks count=unknown"
    return 0
  fi
  if [ ! -f "$settings" ]; then
    echo "env:stale-managed-hooks count=0"
    return 0
  fi
  count="$(jq '[ (.hooks // {}) | to_entries[] | .value[]? | .hooks[]?
                 | .command? // empty
                 | select(contains(".claude/hooks/")) ] | length' "$settings" 2>/dev/null)"
  case "$count" in
    ''|*[!0-9]*) count=unknown ;;
  esac
  echo "env:stale-managed-hooks count=${count}"
  return 0
}

# ─── Half-uninstalled ────────────────────────────────────────────────────────
#
# The plugin is gone but its machine footprint is not. This is the state
# `/bionic:remove`'s standalone door (AC-4) exists to serve, which fixes how
# the question must be asked: NOT "does this payload tree exist" — in the case
# being detected the payload tree is exactly what is missing — but "is bionic
# still registered with the CLI, and is there anything left behind".
#
# The footprint considered here is the part detect.sh owns: the legacy rc
# block, stale managed-hook entries, and the todo-tools export setup writes.
# The permission marker block is profile.sh's fact (slice S5) and joins this
# disjunction there.
detect_half_uninstalled() {
  local installed_json registered=no footprint=no line

  installed_json="${BIONIC_INSTALLED_PLUGINS_FILE:-${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/plugins/installed_plugins.json}"
  if [ -f "$installed_json" ] && command -v jq >/dev/null 2>&1; then
    if [ "$(jq -r '[ (.plugins // {}) | keys[] | select(split("@")[0] == "bionic") ] | length' \
              "$installed_json" 2>/dev/null)" != "0" ]; then
      registered=yes
    fi
  elif [ -f "$installed_json" ]; then
    grep -q '"bionic@' "$installed_json" 2>/dev/null && registered=yes
  fi

  if [ "$registered" = "no" ]; then
    line="$(detect_zshrc_legacy_block)";   [ "$line" = "env:zshrc-legacy present=yes" ] && footprint=yes
    line="$(detect_env_todo_tools)";       [ "$line" = "env:todo-tools present=yes" ] && footprint=yes
    line="$(detect_stale_settings_hooks)"
    case "$line" in *"count=0"|*"count=unknown") ;; *) footprint=yes ;; esac
  fi

  if [ "$registered" = "no" ] && [ "$footprint" = "yes" ]; then
    echo "state:half-uninstalled=yes"
  else
    echo "state:half-uninstalled=no"
  fi
  return 0
}

# ─── Sweep ───────────────────────────────────────────────────────────────────
#
# Every fact, once, in a stable order. doctor renders this; it does not
# recompute any of it.
detect_all() {
  local name
  detect_plugin_integrity
  detect_env_todo_tools
  detect_zshrc_legacy_block
  detect_stale_settings_hooks
  detect_half_uninstalled
  while IFS= read -r name; do
    [ -n "$name" ] && detect_dep "$name"
  done < <(dep_names)
  return 0
}
