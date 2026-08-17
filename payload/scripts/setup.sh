#!/bin/bash
# setup.sh — `/bionic:setup` (epic-17 wave-03, spec AC-2 and AC-6).
#
# WHAT THIS SCRIPT OWNS. The whole of tier 2: everything that has to be true of
# a MACHINE for bionic to work, in one idempotent, re-runnable pass. Tier 2
# contains tier 1 — the native plugin install is this script's first step, not a
# prerequisite the user is expected to have done — so `/bionic:setup` is a
# complete answer to "set this machine up", from a cold box or from a box that
# is already three quarters of the way there.
#
# WHAT IT DOES NOT OWN. Facts and mechanisms. Whether a dependency is present is
# `detect.sh`/`deps.sh`'s answer; HOW a dependency installs is `deps.sh`'s
# `install_dep`, the same function a just-in-time offer calls (AC-5: one owner,
# no second installer); how the permission profile renders and applies is
# `profile.sh`. This script decides ORDER, asks the questions, and reports. Any
# fact it recomputed itself would be a second implementation of somebody else's
# truth, which is the defect the wave's ownership table exists to prevent.
#
# THE SEVEN STEPS, in this order and for these reasons:
#
#   1. plugin install       tier 1 first: everything after it assumes the payload
#                           is installed, and a machine that skips it gets an
#                           honest action line rather than six confusing ones.
#   2. lane-3a enable-verify the harness installs these; what it does NOT always
#                           do is leave them enabled (measured: W1 run B landed
#                           superpowers `enabled: false`). Repair is an explicit
#                           `claude plugin enable`, never a reinstall.
#   3. lane-3b install loop the deps with no native mechanism, one row at a time
#                           through `install_dep` — the setup loop and the JIT
#                           offer are the same function called twice.
#   4. shell rc export      CLAUDE_CODE_ENABLE_TODO_TOOLS=1, marker-scoped.
#   5. legacy alias removal the block claude-bootstrap.sh used to write. Auto
#                           mode is the default now and the safer equivalent, so
#                           the block is retired footprint. Ported here because
#                           the installer retires at W5 and this obligation must
#                           not retire with it.
#   6. stale managed hooks  settings.json entries still naming ~/.claude/hooks/.
#                           The plugin registers its own hooks through the
#                           payload's hooks.json; a leftover settings entry fires
#                           a stale COPY of a hook the plugin already provides.
#                           Also ported from the retiring installer.
#   7. permission profile   rendered against this machine's plugin root and
#                           applied under explicit consent (AC-6). Consent is
#                           obtained HERE and handed to `profile_apply` as a
#                           token: the library never asks, so there is exactly
#                           one place in the system where consent is decided.
#
# CONSENT, AND WHY THERE IS ONE PROMPT SHAPE. Every mutation below is gated, per
# item, on an explicit `y` on stdin, and the gate is `deps.sh`'s `_dep_consent`
# — not a second prompt implementation. The plan is printed BEFORE the question
# and executed AFTER it, from the same string, so what the user agreed to is by
# construction what runs. There is no assume-yes knob: an env var that switched
# consent off would be the hole in "consent per event, never silent, never
# unattended". A closed stdin therefore declines everything, which is the
# fail-closed direction.
#
# WARN AND CONTINUE. `set -e` is deliberately absent. A machine that cannot do
# step 3 can still do steps 4-7, and stopping at the first problem is how a user
# ends up running setup five times. Every step that could not finish appends an
# ACTION LINE, and the run ends with all of them together — the summary is the
# interface, not the scroll. Exit status is 0 whenever setup itself worked,
# including a run where the user declined everything; declining is a valid
# answer, not an error.
#
# HONEST UNKNOWNS. `jq` is itself a row in the dependency table, so a cold
# machine may not have it. Where a fact cannot be read without it, this script
# says `unknown` and names jq as the fix rather than guessing — and never
# mutates on an unknown. Running setup twice on such a machine (once to install
# jq, once to use it) is the intended path, which is exactly what idempotence
# buys.
#
# IDEMPOTENT, AND WHAT THAT MEANS PRECISELY. A second run against an
# already-set-up machine performs no mutation and leaves every file it touches
# byte for byte identical. Each step's guard is the fact function that owns the
# question, so "already done" is decided by the same code doctor reports with.
#
# ROOTS ARE OVERRIDABLE, read at CALL time, so the hermetic suite can point the
# whole script at a fixture tree:
#
#   BIONIC_LIB_DIR        where scripts/lib/*.sh live   (default: beside this file)
#   BIONIC_PLUGIN_ROOT    the payload / render target   (or ${CLAUDE_PLUGIN_ROOT})
#   BIONIC_PROFILE_TEMPLATE  the profile template
#   BIONIC_CLAUDE_HOME    the CLI config dir            (or ${CLAUDE_CONFIG_DIR})
#   BIONIC_SETTINGS_FILE  user settings.json
#   BIONIC_INSTALLED_PLUGINS_FILE  the CLI's install registry
#   BIONIC_SHELL_RC       the shell rc bionic edits
#
# Executed, never sourced:  bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"

set -uo pipefail

# No `dirname` here, same reason the libraries give: a cold or half-broken
# machine is exactly where this script has to run.
_setup_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}

SETUP_LIB_DIR="${BIONIC_LIB_DIR:-$(_setup_self_dir)/lib}"

for _setup_lib in deps.sh detect.sh profile.sh; do
  if [ ! -f "${SETUP_LIB_DIR}/${_setup_lib}" ]; then
    echo "setup.sh: cannot find ${SETUP_LIB_DIR}/${_setup_lib} — the payload looks incomplete." >&2
    echo "          reinstall with: claude plugin install bionic@bionic" >&2
    exit 1
  fi
done
# shellcheck source=/dev/null
. "${SETUP_LIB_DIR}/deps.sh"
# shellcheck source=/dev/null
. "${SETUP_LIB_DIR}/detect.sh"
# shellcheck source=/dev/null
. "${SETUP_LIB_DIR}/profile.sh"

# ─── Constants ───────────────────────────────────────────────────────────────

SETUP_PLUGIN_ID="${BIONIC_PLUGIN_ID:-bionic@bionic}"
SETUP_DEP_MARKETPLACE="${BIONIC_DEP_MARKETPLACE:-bionic}"

# bionic's own rc block. DISTINCT markers from the legacy alias block below on
# purpose: step 5 removes that block by exact marker match, and sharing a marker
# would have step 5 delete what step 4 just wrote.
SETUP_ENV_START='# ─── bionic:env:start ───'
SETUP_ENV_END='# ─── bionic:env:end ───'

# The retired alias block's markers, verbatim from claude-bootstrap.sh —
# box-drawing dashes included, because they are what makes the block
# addressable. `SETUP_ALIAS_PATTERN` is the pre-marker spelling the installer
# itself still migrates (claude-bootstrap.sh's do_install_shell_alias), and it
# is a separate case because a machine that stopped bootstrapping before markers
# existed has the alias with no markers around it at all.
SETUP_ALIAS_START='# ─── bionic:start ───'
SETUP_ALIAS_END='# ─── bionic:end ───'
SETUP_ALIAS_PATTERN='alias claude=.*dangerously-skip-permissions'

# ─── Reporting ───────────────────────────────────────────────────────────────
#
# Actions accumulate in one newline-delimited string rather than an array: an
# empty array under `set -u` is an unbound variable on bash 3.2, which is the
# bash a stock macOS box runs this script with.

SETUP_ACTIONS=""

say()    { printf '%s\n' "$*"; }
action() { SETUP_ACTIONS="${SETUP_ACTIONS}${1}"$'\n'; }
consent() { _dep_consent "$1"; }   # deps.sh owns the one prompt shape

# ─── The CLI's own view of a plugin ──────────────────────────────────────────
#
# Presence of a lane-3a dependency is `check_dep`'s answer (it reads the install
# registry, and it is the one owner of that fact). ENABLED-ness is not in that
# registry at all — it lives in the CLI's settings — so it is asked of the CLI
# itself, the same tool that would repair it. Matching is on the NAME half of
# `name@marketplace`, exactly as `_dep_check_native` does, so a dependency
# re-pointed at a different marketplace still resolves.
#
# Prints `<state>|<id>` where state is enabled | disabled | absent | unknown.
# `unknown` is a real answer here: without the CLI or without jq there is no
# honest way to look, and a confident `absent` would make setup offer to install
# a plugin that is already there.

_setup_cli_plugin() {  # <name>
  local name="${1:-}" json row
  command -v claude >/dev/null 2>&1 || { echo "unknown|"; return 0; }
  command -v jq >/dev/null 2>&1     || { echo "unknown|"; return 0; }
  json="$(claude plugin list --json 2>/dev/null)" || { echo "unknown|"; return 0; }
  [ -n "$json" ] || { echo "unknown|"; return 0; }
  row="$(jq -r --arg n "$name" '
      [ .[]? | select(((.id // "") | split("@")[0]) == $n) ] as $m
      | if ($m | length) == 0 then "absent|"
        else (if ($m[0].enabled // false) then "enabled|" else "disabled|" end) + ($m[0].id // "")
        end' <<< "$json" 2>/dev/null)" || row=""
  case "$row" in
    enabled*|disabled*|absent*) echo "$row" ;;
    *)                          echo "unknown|" ;;
  esac
}

# ─── rc block surgery ────────────────────────────────────────────────────────
#
# Ported from claude-reset.sh's alias removal, with one deliberate difference:
# reset deletes the rc file when only whitespace is left, and this script must
# not — step 4 writes to the same file, and a setup that can delete a user's
# shell rc is a setup nobody should run.

_setup_rc_strip_block() {  # <file> <start-marker> <end-marker>
  local file="${1:-}" start="${2:-}" end="${3:-}" tmp
  [ -f "$file" ] || return 0
  grep -qF "$start" "$file" 2>/dev/null || return 0
  tmp="${file}.bionic.tmp"
  awk -v start="$start" -v end="$end" '
    $0 == start { skip=1; next }
    $0 == end   { skip=0; next }
    !skip { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# ─── Step 1 — the native plugin install (tier 2 ⊃ tier 1) ────────────────────

setup_plugin_install() {
  say ""
  say "1. Plugin install"
  local state id
  IFS='|' read -r state id <<< "$(_setup_cli_plugin bionic)"

  case "$state" in
    enabled|disabled)
      say "   bionic is already installed (${id}) — nothing to do."
      return 0 ;;
    unknown)
      say "   plugin install state is unknown — the claude CLI or jq could not be used to read it."
      action "install jq (and make sure the claude CLI is on PATH), then re-run /bionic:setup — the plugin install state read as unknown"
      return 0 ;;
  esac

  say "   bionic is not installed here."
  say "   bionic would run: claude plugin install ${SETUP_PLUGIN_ID} --scope user --yes"
  if ! consent "   Install the bionic plugin now?"; then
    say "   declined — the plugin stays uninstalled."
    action "run: claude plugin install ${SETUP_PLUGIN_ID} --scope user --yes"
    return 0
  fi
  if claude plugin install "$SETUP_PLUGIN_ID" --scope user --yes; then
    say "   installed."
  else
    say "   the install did not succeed."
    action "run: claude plugin install ${SETUP_PLUGIN_ID} --scope user --yes (add bionic's marketplace first if it is not registered)"
  fi
  return 0
}

# ─── Step 2 — lane-3a: present AND enabled ───────────────────────────────────
#
# The harness installs these; the measured failure mode is that it can leave one
# `enabled: false`, which looks installed to every check that only counts rows.
# Repair is an explicit enable — never a reinstall, which would be the second
# installer lane 3a exists to avoid.

setup_dep_enable_verify() {
  say ""
  say "2. Dependencies — lane 3a (installed by the plugin harness)"
  local name line present state id
  # The list is read on fd 3, NEVER on stdin. A `while read ... done < <(list)`
  # loop redirects the BODY's stdin too, so the consent prompt inside it would
  # read the next dependency NAME as the user's answer and decline every item
  # while consuming the rest of the list.
  while IFS= read -r name <&3; do
    [ -n "$name" ] || continue
    line="$(detect_dep "$name")" || continue
    present="${line#*present=}"; present="${present%% *}"
    IFS='|' read -r state id <<< "$(_setup_cli_plugin "$name")"
    [ -n "$id" ] || id="${name}@${SETUP_DEP_MARKETPLACE}"

    case "$state" in
      enabled)
        say "   ${name}: installed and enabled."
        ;;
      disabled)
        say "   ${name}: installed but DISABLED."
        say "   bionic would run: claude plugin enable ${id}"
        if ! consent "   Enable ${name} now?"; then
          say "   declined — ${name} stays disabled."
          action "run: claude plugin enable ${id}"
        elif claude plugin enable "$id"; then
          say "   enabled."
        else
          action "run: claude plugin enable ${id}"
        fi
        ;;
      absent)
        say "   ${name}: not installed — the plugin harness installs it with bionic."
        action "reinstall bionic so its dependencies resolve: claude plugin install ${SETUP_PLUGIN_ID} --scope user --yes (${name} is missing)"
        ;;
      *)
        say "   ${name}: enabled-state unknown (present=${present}) — the claude CLI or jq could not be used to read it."
        action "install jq, then re-run /bionic:setup — ${name}'s enabled-state read as unknown"
        ;;
    esac
  done 3< <(dep_names_lane 3a)
  return 0
}

# ─── Step 3 — lane-3b: one row at a time, through the one installer ──────────
#
# `unknown` presence gets an OFFER, not a skip. Two mechanisms genuinely have no
# presence surface (the pnpm store is a cache, not an install), and the
# installer they replace re-warmed those unconditionally; skipping them would
# quietly drop coverage the old installer had. The offer is consented like every
# other, and the unknown is named in the same breath so the user is deciding
# with the real state in front of them.

setup_dep_install_loop() {
  say ""
  say "3. Dependencies — lane 3b (bionic's own installers)"
  local name raw present
  # fd 3, not stdin — see the note in setup_dep_enable_verify. install_dep
  # prompts, so this loop must leave stdin alone.
  while IFS= read -r name <&3; do
    [ -n "$name" ] || continue
    raw="$(check_dep "$name")" || continue
    present="${raw#present=}"; present="${present%%|*}"
    case "$present" in
      yes)
        say "   ${name}: present."
        ;;
      unknown)
        say "   ${name}: presence unknown — this mechanism has no presence surface to read."
        install_dep "$name" || action "install ${name} by hand ($(dep_field "$name" source_url)) — bionic could not confirm it"
        ;;
      *)
        install_dep "$name" || action "install ${name} by hand: $(dep_field "$name" source_url)"
        ;;
    esac
  done 3< <(dep_names_lane 3b)
  return 0
}

# ─── Step 4 — the todo-tools export ──────────────────────────────────────────

setup_env_export() {
  say ""
  say "4. Shell environment"
  local rc line present
  rc="$(_detect_shell_rc)"
  line="$(detect_env_todo_tools)"; present="${line#*present=}"

  if [ "$present" = "yes" ]; then say "   CLAUDE_CODE_ENABLE_TODO_TOOLS=1 is already exported in ${rc} — nothing to do."; return 0; fi  # idempotence guard: rc export

  say "   ${rc} does not export CLAUDE_CODE_ENABLE_TODO_TOOLS=1 (current CLI builds need it for the native task tools)."
  say "   bionic would append a marker-scoped block to ${rc}."
  if ! consent "   Add the export to ${rc}?"; then say "   declined — ${rc} is unchanged."; action "add 'export CLAUDE_CODE_ENABLE_TODO_TOOLS=1' to ${rc}"; return 0; fi  # consent gate: rc export

  # Replace rather than stack: a block whose export was commented out reads as
  # absent above, and appending beside it would leave two blocks.
  _setup_rc_strip_block "$rc" "$SETUP_ENV_START" "$SETUP_ENV_END"
  if printf '\n%s\nexport CLAUDE_CODE_ENABLE_TODO_TOOLS=1\n%s\n' "$SETUP_ENV_START" "$SETUP_ENV_END" >> "$rc"; then
    say "   added."
  else
    say "   could not write ${rc}."
    action "add 'export CLAUDE_CODE_ENABLE_TODO_TOOLS=1' to ${rc} (bionic could not write the file)"
  fi
  return 0
}

# ─── Step 5 — the retired alias block ────────────────────────────────────────

setup_legacy_alias() {
  say ""
  say "5. Legacy shell alias"
  local rc line present tmp
  rc="$(_detect_shell_rc)"
  line="$(detect_zshrc_legacy_block)"; present="${line#*present=}"

  if [ "$present" = "yes" ]; then
    say "   ${rc} carries the legacy bionic alias block (claude --dangerously-skip-permissions)."
    say "   Auto mode is the default now and is the safer equivalent, so the block is retired footprint."
    if ! consent "   Remove the legacy alias block from ${rc}?"; then
      say "   declined — the block stays."
      action "remove the legacy bionic alias block from ${rc}"
      return 0
    fi
    _setup_rc_strip_block "$rc" "$SETUP_ALIAS_START" "$SETUP_ALIAS_END"
    if grep -qF "$SETUP_ALIAS_START" "$rc" 2>/dev/null; then
      say "   the block could not be removed."
      action "remove the legacy bionic alias block from ${rc} by hand"
    else
      say "   removed."
    fi
    return 0
  fi

  if [ -f "$rc" ] && grep -qE "$SETUP_ALIAS_PATTERN" "$rc" 2>/dev/null; then
    say "   ${rc} carries the legacy UNMARKED alias — the spelling that predates the marker block."
    if ! consent "   Remove the legacy alias line from ${rc}?"; then
      say "   declined — the alias stays."
      action "remove the legacy 'alias claude=...--dangerously-skip-permissions' line from ${rc}"
      return 0
    fi
    tmp="${rc}.bionic.tmp"
    if grep -vE "$SETUP_ALIAS_PATTERN" "$rc" > "$tmp" && mv "$tmp" "$rc"; then
      say "   removed (legacy unmarked alias)."
    else
      rm -f "$tmp"
      say "   could not rewrite ${rc}."
      action "remove the legacy 'alias claude=...--dangerously-skip-permissions' line from ${rc} by hand"
    fi
    return 0
  fi

  say "   no legacy alias block in ${rc} — nothing to remove."
  return 0
}

# ─── Step 6 — stale managed-hook entries ─────────────────────────────────────
#
# The filter matches detect.sh's own predicate exactly (a hook command naming
# `.claude/hooks/`), because the count that decided to prompt and the edit that
# clears it must be the same question. Foreign hooks — anything not pointing
# into the pre-plugin directory — are untouched: this is bionic's leftover being
# removed, not the machine's hook config being taken over.

setup_stale_hooks() {
  say ""
  say "6. Stale managed-hook entries"
  local line count settings tmp
  line="$(detect_stale_settings_hooks)"; count="${line#*count=}"
  settings="$(_dep_settings_file)"

  case "$count" in
    0)
      say "   no stale managed-hook entries in ${settings} — nothing to remove."
      return 0 ;;
    unknown)
      say "   stale managed-hook entries: count unknown — jq is unavailable, so ${settings} was not parsed."
      action "install jq, then re-run /bionic:setup — stale managed-hook entries could not be counted"
      return 0 ;;
  esac

  # The pre-plugin hooks directory is named without a path literal on purpose:
  # tests/plugin-paths.test.sh forbids an installed-path literal on any
  # executable line in the payload, and a user-facing string is still one.
  say "   ${count} hook entr(ies) in ${settings} still point into the machine's pre-plugin hooks directory."
  say "   The plugin registers its own hooks; these fire a stale copy of a hook bionic already provides."
  if ! consent "   Remove the stale entries from ${settings}?"; then
    say "   declined — ${settings} is unchanged."
    action "remove ${count} stale managed-hook entr(ies) from ${settings}"
    return 0
  fi

  tmp="${settings}.bionic.tmp"
  if jq '
        if (.hooks | type) != "object" then .
        else
          .hooks |= ( with_entries(
                        .value |= ( map(.hooks |= map(select((((.command // "") | contains(".claude/hooks/")) | not))))
                                    | map(select((((.hooks // []) | length) > 0))) ) )
                      | with_entries(select((((.value // []) | length) > 0))) )
          | if (.hooks | length) == 0 then del(.hooks) else . end
        end
      ' "$settings" > "$tmp" && mv "$tmp" "$settings"; then
    say "   removed."
  else
    rm -f "$tmp"
    say "   could not rewrite ${settings}."
    action "remove ${count} stale managed-hook entr(ies) from ${settings} by hand"
  fi
  return 0
}

# ─── Step 7 — the permission profile ─────────────────────────────────────────
#
# Consent is obtained here and handed to `profile_apply` as a token. The library
# refuses to write without it and never prompts, so there is one conversation
# with the user and one gate, not two.

setup_profile() {
  say ""
  say "7. Permission profile"
  local state applied stale template root settings rendered
  state="$(detect_profile_state)"
  applied="${state#*applied=}"; applied="${applied%% *}"
  stale="${state#*stale=}";     stale="${stale%% *}"
  settings="$(_dep_settings_file)"

  if [ "$applied" = "yes" ] && [ "$stale" = "no" ]; then
    say "   the permission profile is applied and current — nothing to do."
    return 0
  fi

  template="$(_profile_template_path)"
  root="$(_profile_plugin_root)"
  rendered="$(mktemp 2>/dev/null)" || rendered=""
  if [ -z "$rendered" ]; then
    say "   could not create a temporary file to render the profile."
    action "apply the permission profile: re-run /bionic:setup once a temporary directory is writable"
    return 0
  fi
  if ! render_profile "$template" "$root" > "$rendered"; then
    rm -f "$rendered"
    say "   the profile template could not be rendered."
    action "apply the permission profile: reinstall bionic — ${template} is missing or unreadable"
    return 0
  fi

  if [ "$applied" = "yes" ]; then
    say "   the applied permission profile is stale (${state})."
    say "   A plugin update moves the install path, which is what stales the rendered rules."
  else
    say "   bionic ships a permission profile for its own scripts and hooks, rendered for ${root}."
  fi
  say "   It goes into ${settings} inside a marker block; nothing outside that block is read or changed."
  if ! consent "   Apply the permission profile to ${settings}?"; then
    rm -f "$rendered"
    say "   declined — ${settings} is unchanged."
    action "apply the permission profile: re-run /bionic:setup and answer y at the permission step"
    return 0
  fi

  if profile_apply "$rendered" "$BIONIC_PROFILE_CONSENT"; then
    say "   applied."
  else
    say "   the permission profile could not be applied."
    action "apply the permission profile: see the message above (jq is required to edit ${settings} safely)"
  fi
  rm -f "$rendered"
  return 0
}

# ─── The summary ─────────────────────────────────────────────────────────────

setup_summary() {
  say ""
  say "Summary"
  if [ -z "$SETUP_ACTIONS" ]; then
    say "   nothing left to do — this machine is set up."
    return 0
  fi
  local a
  while IFS= read -r a; do
    [ -n "$a" ] && say "   - ${a}"
  done <<< "$SETUP_ACTIONS"
  return 0
}

# ─── Run ─────────────────────────────────────────────────────────────────────

say "bionic setup — every change below is asked for first, one item at a time."

setup_plugin_install
setup_dep_enable_verify
setup_dep_install_loop
setup_env_export
setup_legacy_alias
setup_stale_hooks
setup_profile
setup_summary

exit 0
