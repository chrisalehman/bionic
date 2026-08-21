#!/bin/bash
# remove.sh — consented teardown of bionic's machine footprint (epic-17
# wave-03, spec AC-4; ownership table row "footprint removal").
#
# WHAT THIS FILE OWNS. Everything bionic's own scripts put on a machine, and the
# order it comes back off in. One item at a time, each one announced before it is
# asked about and asked about before it happens: the legacy `.zshrc` alias block,
# the `CLAUDE_CODE_ENABLE_TODO_TOOLS` export, legacy-channel managed-hook entries in
# settings, the permission marker block, the tools it installed, the plugin
# data directory — and then the native plugin uninstall as the finisher.
#
# THE NEVER-LIST IS NOT A PREFERENCE. Three classes are excluded from removal and
# consent does not unlock them:
#
#   `.bionic/` trees      plans, specs, the operational record, memory. These are
#                         the user's work, not bionic's footprint.
#   shared binaries       git, node, jq, docker, ... bionic ENSURED them; it does
#                         not own them. deps.sh marks every such row `keep-shared`
#                         and `remove_dep` declines them even when told yes.
#   the pnpm store        a shared content-addressable cache other projects
#                         hard-link out of.
#
# THE REMOVER MUST NOT DEPEND ON THE THING IT REMOVES. This is the one payload
# script reachable standalone — `curl`-fetched to a machine whose plugin is
# already gone (spec AC-4; doctor prints the one-liner for exactly that state).
# There, `scripts/lib/*` do not exist. So:
#
#   * Every fact this script needs, it establishes itself. It does not source
#     detect.sh. The predicates are deliberately the SAME predicates detect.sh
#     uses — the todo-tools export regex, the `bionic:start` marker, the
#     `.claude/hooks/` substring, the profile begin/end sentinels — and
#     tests/remove.test.sh pins them against detect.sh and profile.sh so the two
#     cannot drift apart silently.
#   * Where a library IS beside the script, the library owner does the work:
#     `profile_strip` strips the permission block and `remove_dep` applies the
#     three-valued removal policy. The inline strip below is the standalone
#     fallback for the first of those, and the two are pinned to produce
#     byte-identical output from the same input.
#   * The one thing that genuinely cannot be reconstructed standalone is the
#     dependency TABLE — it ships with the payload and there is no second copy of
#     it, by design (AC-8). Standalone says so, out loud, and moves on. A silently
#     skipped item would be the worse failure.
#
# CONSENT, PER ITEM, READ FROM THIS SCRIPT'S OWN INPUT. No `--all`, no
# assume-yes env knob: deps.sh ratified "consent per event, never silent, never
# unattended" and a flag that switched it off would be the hole in it. An item
# with nothing to do is not asked about — consent to do nothing is noise, not
# safety.
#
# TWO FLAGS, AND NEITHER OF THEM IS AN ANSWER (critic F-1 and F-2):
#
#   --list          print the name of every item this machine can be asked
#                   about, one per line, and exit.
#   --only <name>   ask about exactly that one item. Every other item is neither
#                   run nor asked about.
#
# The answer channel is one line read from this script's input, and a line read
# that way is POSITIONAL — it lands on the first question asked, which is
# whichever item this machine happens to have. So the yes is made addressable
# rather than the questions made skippable: `--only` narrows WHICH question is
# asked, never whether it is asked, and the answer to it can only consent to the
# item that was named. `_rm_item_ids` is the one place the roster is spelled —
# `--list` prints it and `--only` is checked against it, so a name a reader can
# see is a name this script takes.
#
# THE FINISHER IS INVOKED, NOT PRINTED. `claude plugin uninstall` works from a
# script subprocess mid-session and takes effect immediately
# (record/epic-17-w3/probe-uninstall-semantics.md, VERDICT IMMEDIATE), so there is
# no "run this yourself afterwards" branch. Dependencies PERSIST past the parent
# uninstall (probe-dep-persistence.md) and the CLI names its own primitive for
# them, so the last offer is `claude plugin prune`, driven from that command's own
# `--dry-run` listing rather than from a hand-rolled walk of plugin.json.
#
# ROOTS ARE OVERRIDABLE, read at CALL time (detect.sh's convention):
#
#   BIONIC_CLAUDE_HOME       the CLI's config dir      ${CLAUDE_CONFIG_DIR:-~/.claude}
#   BIONIC_SETTINGS_FILE     user settings.json        <claude-home>/settings.json
#   BIONIC_SHELL_RC          the rc bionic edited      ~/.zshrc or ~/.bashrc, per $SHELL
#   BIONIC_PLUGIN_DATA_DIR   plugin data root          <claude-home>/plugins/data
#
# NO EXTERNAL TEXT TOOLS. No `dirname`, no `basename`, and — going past what
# detect.sh needs — no `grep`, `awk` or `sed` either: every match and every rewrite
# below is bash's own. detect.sh avoids coreutils so it can be SOURCED on a broken
# machine; this script is the one that RUNS on it, and a missing or shadowed
# `grep` silently reporting a dirty machine as clean is the failure that matters
# here. `jq` is the single exception, and its absence is reported, never assumed
# away. (See "TEXT WORK IS DONE IN BASH ITSELF" below.)
#
# Usage:  bash remove.sh          (as /bionic:remove, or standalone by raw URL)

set -uo pipefail

# Every default root below hangs off $HOME. An unset HOME would make them resolve
# against `/`, so it is checked once, up front, where the message can say so —
# rather than as a bare unbound-variable abort halfway through a teardown.
: "${HOME:?remove.sh: HOME is not set — cannot locate the configuration for this machine}"

# ─── Roots ───────────────────────────────────────────────────────────────────

_rm_self_dir() {
  local self="${BASH_SOURCE[0]:-$0}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}

_rm_claude_home()      { echo "${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"; }
_rm_settings_file()    { echo "${BIONIC_SETTINGS_FILE:-$(_rm_claude_home)/settings.json}"; }
_rm_plugin_data_dir()  { echo "${BIONIC_PLUGIN_DATA_DIR:-$(_rm_claude_home)/plugins/data}"; }

_rm_shell_rc() {
  if [ -n "${BIONIC_SHELL_RC:-}" ]; then echo "$BIONIC_SHELL_RC"; return; fi
  local shell_name="${SHELL:-/bin/bash}"
  case "${shell_name##*/}" in
    zsh) echo "$HOME/.zshrc" ;;
    *)   echo "$HOME/.bashrc" ;;
  esac
}

_rm_have() { command -v "${1:-}" >/dev/null 2>&1; }

# ─── The invocation a person can type, when there is one ─────────────────────
#
# A declined item ends with one line saying how to say yes to just that item,
# and the line has to name a route that exists. This script is the one payload
# script that can be fetched and piped straight into a shell, and there is no
# file on disk to point at when it is — so the path is RESOLVED rather than
# composed, and when it does not resolve the route line is simply not printed.
# A sentence naming a path nobody has is the failure this line exists to end.

RM_SELF_CMD=""
_rm_resolve_self() {
  local self="${BASH_SOURCE[0]:-$0}" dir
  case "$self" in */*) ;; *) return 1 ;; esac
  dir="$(cd "${self%/*}" 2>/dev/null && pwd -P)" || return 1
  [ -f "${dir}/${self##*/}" ] || return 1
  RM_SELF_CMD="bash ${dir}/${self##*/}"
  return 0
}
_rm_resolve_self || RM_SELF_CMD=""

RM_YES_PIPE="printf 'y\\n' | "

# ONE OWNER for the sentence. The decline line and the end summary both quote
# it, so they cannot come to disagree about what the user should run.
_rm_answer_yes() {  # <name> — the route, or nothing when there is no path to name
  [ -n "$RM_SELF_CMD" ] || return 0
  printf 'answer yes to %s with: %s%s --only %s' "$1" "$RM_YES_PIPE" "$RM_SELF_CMD" "$1"
}

# ─── Which items this run is doing ───────────────────────────────────────────
#
# Empty means the whole teardown, which is the only thing this script did before
# and is still what it does with no flags. A name means that item and nothing
# else: every item below asks this before it prints its own header, so a
# narrowed run is SILENT about the items it is not doing rather than listing
# them as skipped.

RM_ONLY=""
_rm_wants() { [ -z "$RM_ONLY" ] || [ "$RM_ONLY" = "$1" ]; }

# ─── The shared literals ─────────────────────────────────────────────────────
#
# Each of these is a copy of a constant that lives in the payload libraries, and
# each copy exists because the standalone door cannot read those libraries. They
# are pinned to their originals by tests/remove.test.sh; changing one without the
# other is what that pin exists to catch.

# from detect.sh: the rc block markers and the two rc predicates
RM_RC_START='# ─── bionic:start ───'
RM_RC_END='# ─── bionic:end ───'
RM_TODO_EXPORT_RE='^[[:space:]]*export[[:space:]]+CLAUDE_CODE_ENABLE_TODO_TOOLS=1'
RM_LEGACY_ALIAS_RE='alias claude=.*dangerously-skip-permissions'
# from detect.sh: the substring that puts a managed-hook entry on the legacy channel
RM_LEGACY_HOOK_SUBSTR='.claude/hooks/'
# from detect.sh (DETECT_LEGACY_SKILL_NAME): the one skill the retired installer rendered
# into the CLI's own skills directory. ONE NAME, NOT A WILDCARD — the same installer left
# copies of bionic's other skills behind, 4/6 measured those as registering nothing, and
# what to do with them is the wave's close-out decision. A consented step reading a wildcard
# would recursively delete directories nobody has decided about, which is a larger defect
# than the one it fixes.
RM_LEGACY_SKILL_NAME='canonical-sdlc'
# from deps.sh (BIONIC_DEFAULT_PERMISSION_MODE): the default permission mode
# setup offers to write. In payload mode the OWNER's value is what this script
# compares against — read at call time, below the source — and this fallback is
# for the standalone door alone, where there is no deps.sh to read. It is pinned
# to the original by tests/remove.test.sh, like every other literal here.
_rm_default_mode() { echo "${BIONIC_DEFAULT_PERMISSION_MODE:-auto}"; }

# from profile.sh: the sentinels bracketing the block bionic owns
RM_PROFILE_BEGIN_PREFIX='Bash(: bionic-profile-begin version='
RM_PROFILE_END='Bash(: bionic-profile-end)'

# ─── Mode ────────────────────────────────────────────────────────────────────

RM_LIB_DIR="$(_rm_self_dir)/lib"
RM_MODE=standalone
if [ -f "${RM_LIB_DIR}/deps.sh" ] && [ -f "${RM_LIB_DIR}/profile.sh" ]; then
  # shellcheck source=/dev/null
  . "${RM_LIB_DIR}/deps.sh" && . "${RM_LIB_DIR}/profile.sh" && RM_MODE=payload
fi

# ─── Outcome records ─────────────────────────────────────────────────────────

RM_REMOVED=0
RM_CLEAN=0
RM_SKIPPED=0
RM_SKIPPED_LIST=""
RM_LEFTOVERS=""

_rm_removed() { RM_REMOVED=$((RM_REMOVED + 1)); echo "  ✓ ${1}"; }
_rm_clean()   { RM_CLEAN=$((RM_CLEAN + 1));     echo "  ✓ ${1} — already clean"; }
_rm_skipped() {  # <name> <what was left>
  local route
  route="$(_rm_answer_yes "$1")"
  RM_SKIPPED=$((RM_SKIPPED + 1))
  if [ -n "$route" ]; then
    RM_SKIPPED_LIST="${RM_SKIPPED_LIST}    ⚠ ${2} — ${route}"$'\n'
  else
    RM_SKIPPED_LIST="${RM_SKIPPED_LIST}    ⚠ ${2}"$'\n'
  fi
  echo "  declined — ${2} left in place."
  [ -n "$route" ] && echo "  ${route}"
  return 0
}
_rm_leftover() { RM_LEFTOVERS="${RM_LEFTOVERS}    ✗ ${1}"$'\n'; echo "  ⚠ ${1}"; }

# ─── Consent ─────────────────────────────────────────────────────────────────
#
# Identical in shape to deps.sh's `_dep_consent`, and identical in rule: nothing
# but an explicit yes counts, and EOF (a non-interactive stdin) counts as no.

_rm_consent() {  # <prompt>
  local prompt="$1" answer=""
  printf '  %s [y/N] ' "$prompt"
  IFS= read -r answer || { echo ""; return 1; }
  echo ""
  case "$answer" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}

# ─── File helpers ────────────────────────────────────────────────────────────

# Whole-file read that keeps the trailing byte, so a rewrite can reproduce the
# file's own newline shape. Same mechanism profile.sh uses and for the same
# reason: `$(...)` would strip the very byte the round trip turns on.
_rm_slurp_into() {  # <varname> <file>
  local __rm_var="$1" __rm_file="$2" __rm_text
  [ -f "$__rm_file" ] || return 1
  IFS= read -r -d '' __rm_text < "$__rm_file" || true
  printf -v "$__rm_var" '%s' "$__rm_text"
}

# Byte-identical to profile.sh's `_profile_write` apart from the name, which is
# what tests/remove.test.sh pins. The mode capture is not decoration: `mv`
# replaces the inode, so a settings.json the user kept at 0600 would come back at
# whatever the umask says, and this script's whole job is editing that file. See
# profile.sh for why `stat` is spelled twice, why an absent `stat` degrades to
# "write, don't chmod" rather than to a refusal — the standalone door runs on the
# machine with the bare /bin — and why the `umask 077` and the `chmod` must both
# stay ABOVE the `mv`.
_rm_write() {  # <file> <content> <trailing-newline 0|1>
  local file="$1" content="$2" nl="$3" tmp="${1}.bionic.tmp" mode
  mode="$(stat -f '%Lp' "$file" 2>/dev/null || stat -c '%a' "$file" 2>/dev/null)"
  if [ "$nl" = "1" ]; then (umask 077; printf '%s\n' "$content" > "$tmp"); else (umask 077; printf '%s' "$content" > "$tmp"); fi
  [ -n "$mode" ] && chmod "$mode" "$tmp"
  mv "$tmp" "$file" || return 1
  return 0
}

# TEXT WORK IS DONE IN BASH ITSELF, not by grep/awk/sed. detect.sh refuses
# `dirname` so it can be sourced on a broken machine; this script is the one that
# RUNS on the broken machine, so it goes further: bash's own `[[ =~ ]]` and `case`
# do every match and every rewrite below. Three things follow from that. A missing
# coreutil cannot silently turn a dirty rc file into a clean report. A `grep`
# shadowed by an alias or a lookalike on the user's PATH cannot either. And the
# behaviour is the same on a machine whose /bin is bare. `jq` is the one exception
# — JSON is not bash's job — and its absence is reported rather than assumed away.

_rm_file_has_literal() {  # <file> <string>
  local file="$1" needle="$2" text
  [ -f "$file" ] || return 1
  _rm_slurp_into text "$file" || return 1
  case "$text" in *"$needle"*) return 0 ;; *) return 1 ;; esac
}

_rm_file_has_line_matching() {  # <file> <ere>
  local file="$1" ere="$2" line
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ $ere ]] && return 0
  done < "$file"
  return 1
}

# Drops every line matching an ERE.
_rm_filter_out_lines() {  # <file> <ere>
  local file="$1"
  local ere="$2"
  local tmp="${file}.bionic.tmp"
  local line
  : > "$tmp" || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ $ere ]] && continue
    printf '%s\n' "$line" >> "$tmp"
  done < "$file"
  mv "$tmp" "$file"
}

# Drops a marker-delimited block, markers included. Line equality is exact —
# these markers carry box-drawing dashes, and a fuzzy match would be a rewrite
# rule for lines nobody wrote.
_rm_strip_marker_block() {  # <file> <start-line> <end-line>
  local file="$1" start="$2" end="$3"
  local tmp="${file}.bionic.tmp"
  local line skip=0
  : > "$tmp" || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$start" ]; then skip=1; continue; fi
    if [ "$line" = "$end" ];   then skip=0; continue; fi
    [ "$skip" = "1" ] && continue
    printf '%s\n' "$line" >> "$tmp"
  done < "$file"
  mv "$tmp" "$file"
}

_rm_indent() {  # <text> — four spaces on every line, no sed
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    printf '    %s\n' "$line"
  done <<< "$1"
}

# rm -rf with the never-list as a precondition rather than as a hope. Nothing
# under a `.bionic` path is removable by this script, whatever it was handed.
_rm_purge_dir() {  # <dir>
  local target="${1:-}"
  [ -n "$target" ] || return 1
  case "$target" in
    */.bionic|*/.bionic/*) echo "  refusing to remove a .bionic path: ${target}" >&2; return 1 ;;
    /|"$HOME") echo "  refusing to remove ${target}" >&2; return 1 ;;
  esac
  rm -rf "$target"
}

# Does this directory hold anything at all — dotfiles included? Bash 3.2 has no
# option to make a glob see hidden entries and an unmatched glob comes back as
# its own pattern, so each candidate is tested for existence rather than counted.
_rm_dir_is_empty() {  # <dir> — true when nothing is inside
  local d="${1:-}" entry
  [ -d "$d" ] || return 1
  for entry in "$d"/* "$d"/.[!.]* "$d"/..?*; do
    if [ -e "$entry" ] || [ -L "$entry" ]; then return 1; fi
  done
  return 0
}

# ─── The roots every item reads ──────────────────────────────────────────────
#
# Resolved once, above the items, because more than one item reads each of them
# and because an item is a function now: a root computed inside one of them
# would be invisible to the next.

RC_FILE="$(_rm_shell_rc)"
RM_SETTINGS="$(_rm_settings_file)"
RM_LEGACY_SKILL_DIR="$(_rm_claude_home)/skills/${RM_LEGACY_SKILL_NAME}"
RM_DATA_ROOT="$(_rm_plugin_data_dir)"
RM_DATA_DECLINED=0
# ONE OFFER PER RUN. The orphan question has two callers — the uninstall that
# creates the orphans, and the roster entry that owns the standalone case — and a
# whole pass reaches both. Asking twice would be asking a person to answer the
# same thing twice, so the first caller closes the door behind it.
RM_ORPHANS_OFFERED=0

# ─── The roster ──────────────────────────────────────────────────────────────
#
# Every item this machine can be asked about, in the order the whole teardown
# asks about them. The tool rows are READ from the dependency table, never
# restated — and they exist only in payload mode, because standalone there is no
# table to read and the tools item says exactly that instead of pretending.

_rm_item_ids() {
  local n
  echo "legacy-alias"
  echo "shell-env"
  echo "legacy-hooks"
  echo "legacy-skill-copy"
  echo "permission-profile"
  echo "permission-mode"
  if [ "$RM_MODE" = "payload" ]; then
    # fd 3: the standard input belongs to the questions, never to a list.
    while IFS= read -r n <&3; do
      [ -n "$n" ] && echo "tool:${n}"
    done 3<<< "$( { dep_names_class basic; dep_names_class when-needed; dep_names_class extra; } )"
  fi
  echo "plugin-data"
  echo "plugin"
  echo "orphaned-dependencies"
  return 0
}

# ─── Arguments ───────────────────────────────────────────────────────────────
#
# Read here rather than in a wrapper, because the roster they are checked
# against is built from the dependency table this script has already decided
# whether it can see. An unrecognised name stops the run before anything is
# printed at it: a narrowed run that silently did nothing would look exactly
# like a machine that was already clean.

rm_list=0
while [ $# -gt 0 ]; do
  case "$1" in
    --list)
      rm_list=1; shift ;;
    --only)
      if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
        echo "remove: --only needs the name of the one item to remove."
        echo "        run ${RM_SELF_CMD:-this script} --list to see the names."
        exit 2
      fi
      RM_ONLY="$2"; shift 2 ;;
    --only=*)
      RM_ONLY="${1#--only=}"; shift ;;
    *)
      echo "remove: ${1} is not something this command takes."
      echo "        run ${RM_SELF_CMD:-this script} --list to see what can be removed one item at a time."
      exit 2 ;;
  esac
done

if [ "$rm_list" = "1" ]; then
  _rm_item_ids
  exit 0
fi

if [ -n "$RM_ONLY" ]; then
  rm_known=""
  while IFS= read -r rm_id <&3; do
    [ "$rm_id" = "$RM_ONLY" ] && { rm_known=1; break; }
  done 3< <(_rm_item_ids)
  if [ -z "$rm_known" ]; then
    echo "remove: there is nothing called ${RM_ONLY} to remove on this machine."
    echo "        run ${RM_SELF_CMD:-this script} --list to see the names."
    exit 2
  fi
fi

echo ""
echo "bionic remove — consented teardown of the machine footprint"
# WHAT THIS LINE IS FOR (R-1). `mode: payload` named one of this script's own
# branches at a user who has no way to know it has branches. What the line has to
# answer is whether the teardown in front of them is the whole teardown.
if [ "$RM_MODE" = "payload" ]; then
  echo "running from the plugin — the full teardown is available."
else
  echo "running standalone — bionic's own files are not beside this script, so a few items can only be reported."
fi
echo ""

# ─── Item: the shell rc's legacy alias block ─────────────────────────────────
#
# Two shapes, because two eras of claude-bootstrap.sh wrote them: the
# marker-delimited block, and — older still — a bare alias line with no markers
# at all. The markers are matched verbatim, box-drawing dashes included; they are
# what makes the block addressable.
#
# The rc FILE is never deleted, even if the block was all it held. claude-reset.sh
# deletes an emptied rc; a script that can be curl-fetched onto an unknown machine
# should not.

_rm_item_legacy_alias() {
  _rm_wants legacy-alias || return 0
  rc_variant=none
  if [ -f "$RC_FILE" ]; then
    if _rm_file_has_literal "$RC_FILE" "$RM_RC_START"; then
      rc_variant=marked
    elif _rm_file_has_line_matching "$RC_FILE" "$RM_LEGACY_ALIAS_RE"; then
      rc_variant=legacy
    fi
  fi

  echo "legacy shell alias block:"
  case "$rc_variant" in
    none)
      _rm_clean "legacy alias block in ${RC_FILE}"
      ;;
    marked)
      echo "  ${RC_FILE} carries the bionic marker block; bionic would delete the block and everything between its markers."
      if _rm_consent "Remove the marker block from ${RC_FILE}?"; then
        if _rm_strip_marker_block "$RC_FILE" "$RM_RC_START" "$RM_RC_END"; then
          _rm_removed "legacy alias block in ${RC_FILE}"
        else
          rm -f "${RC_FILE}.bionic.tmp"
          _rm_leftover "could not rewrite ${RC_FILE} — the alias block is still there"
        fi
      else
        _rm_skipped legacy-alias "legacy alias block in ${RC_FILE}"
      fi
      ;;
    legacy)
      echo "  ${RC_FILE} carries an unmarked legacy alias line; bionic would delete that line."
      if _rm_consent "Remove the legacy alias line from ${RC_FILE}?"; then
        if _rm_filter_out_lines "$RC_FILE" "$RM_LEGACY_ALIAS_RE"; then
          _rm_removed "legacy alias line in ${RC_FILE}"
        else
          _rm_leftover "could not rewrite ${RC_FILE} — the legacy alias line is still there"
        fi
      else
        _rm_skipped legacy-alias "legacy alias line in ${RC_FILE}"
      fi
      ;;
  esac
  echo ""
}

# ─── Item: the CLAUDE_CODE_ENABLE_TODO_TOOLS export ──────────────────────────
#
# The predicate is detect.sh's, character for character: a commented-out export
# is NOT present, so it is not removed either.

_rm_item_shell_env() {
  _rm_wants shell-env || return 0
  echo "todo-tools export:"
  if _rm_file_has_line_matching "$RC_FILE" "$RM_TODO_EXPORT_RE"; then
    echo "  ${RC_FILE} exports CLAUDE_CODE_ENABLE_TODO_TOOLS=1; bionic would delete that line."
    if _rm_consent "Remove the CLAUDE_CODE_ENABLE_TODO_TOOLS export from ${RC_FILE}?"; then
      if _rm_filter_out_lines "$RC_FILE" "$RM_TODO_EXPORT_RE"; then
        _rm_removed "CLAUDE_CODE_ENABLE_TODO_TOOLS export in ${RC_FILE}"
      else
        _rm_leftover "could not rewrite ${RC_FILE} — the export is still there"
      fi
    else
      _rm_skipped shell-env "CLAUDE_CODE_ENABLE_TODO_TOOLS export in ${RC_FILE}"
    fi
  else
    _rm_clean "CLAUDE_CODE_ENABLE_TODO_TOOLS export in ${RC_FILE}"
  fi
  echo ""
}

# ─── Item: legacy-channel managed-hook entries in settings ───────────────────
#
# Entries whose command still names the pre-plugin `~/.claude/hooks/` copies. The
# plugin channel registers its hooks through the payload's own hooks.json, so one
# of these is a migrated machine still firing its copy through the settings
# channel, alongside the plugin's own registration of the same hook.
#
# The filter reaches INSIDE each matcher group rather than dropping the group: a
# group can hold a bionic hook and a foreign one, and dropping it whole would
# remove somebody else's hook. Groups left empty are collapsed afterwards, and a
# `hooks` object left empty is deleted — the same shape claude-reset.sh produced.

# Byte-identical to detect.sh's DETECT_LEGACY_HOOK_COUNT_JQ apart from the name
# of the variable interpolated into it — the same arrangement the strip program
# already has, and pinned in the same place. detect.sh is the declared single
# source for machine facts; this is the standalone door's copy, which exists
# because the door must answer on a machine where detect.sh is gone.
RM_LEGACY_HOOK_COUNT_JQ='
  [ (.hooks // {}) | to_entries[] | .value[]? | .hooks[]?
    | .command? // empty
    | select(contains("'"${RM_LEGACY_HOOK_SUBSTR}"'")) ] | length
'

RM_LEGACY_HOOK_STRIP_JQ='
  if (.hooks | type) != "object" then .
  else
      .hooks |= with_entries(
        .value |= ( map( .hooks |= map(select(((.command? // "") | contains("'"${RM_LEGACY_HOOK_SUBSTR}"'")) | not)) )
                    | map(select((.hooks | length) > 0)) )
      )
    | .hooks |= with_entries(select((.value | length) > 0))
    | if (.hooks | length) == 0 then del(.hooks) else . end
  end
'

_rm_item_legacy_hooks() {
  _rm_wants legacy-hooks || return 0
  echo "legacy-channel managed-hook entries in settings.json:"
  legacy_hook_count=0
  if [ -f "$RM_SETTINGS" ]; then
    if _rm_have jq; then
      legacy_hook_count="$(jq "$RM_LEGACY_HOOK_COUNT_JQ" "$RM_SETTINGS" 2>/dev/null)"
      case "$legacy_hook_count" in ''|*[!0-9]*) legacy_hook_count=unknown ;; esac
    else
      legacy_hook_count=unknown
    fi
  fi

  if [ "$legacy_hook_count" = "unknown" ]; then
    _rm_leftover "cannot read ${RM_SETTINGS} without jq — managed-hook entries left as they are"
  elif [ "$legacy_hook_count" = "0" ]; then
    _rm_clean "legacy-channel managed-hook entries in ${RM_SETTINGS}"
  else
    echo "  ${RM_SETTINGS} carries ${legacy_hook_count} hook entr(y/ies) still pointing at ${RM_LEGACY_HOOK_SUBSTR}; bionic would delete those entries and nothing else."
    if _rm_consent "Remove ${legacy_hook_count} legacy-channel managed-hook entr(y/ies) from ${RM_SETTINGS}?"; then
      rm_settings_nl=0
      # shellcheck disable=SC2154  # set by printf -v inside _rm_slurp_into
      _rm_slurp_into rm_settings_text "$RM_SETTINGS" && case "$rm_settings_text" in *$'\n') rm_settings_nl=1 ;; esac
      if rm_stripped="$(jq "$RM_LEGACY_HOOK_STRIP_JQ" "$RM_SETTINGS" 2>/dev/null)"; then
        _rm_write "$RM_SETTINGS" "$rm_stripped" "$rm_settings_nl"
        _rm_removed "${legacy_hook_count} legacy-channel managed-hook entr(y/ies) in ${RM_SETTINGS}"
      else
        _rm_leftover "${RM_SETTINGS} is not valid JSON — refusing to write; the legacy-channel entries are still there"
      fi
    else
      _rm_skipped legacy-hooks "legacy-channel managed-hook entries in ${RM_SETTINGS}"
    fi
  fi
  echo ""
}

# ─── Item: the legacy installed skill copy ───────────────────────────────────
#
# THE GAP THIS CLOSES (Step-6 review, RV-6). The retired installer rendered bionic's skills
# into the CLI's OWN skills directory, and the plugin ships the same skill inside its
# payload — so on a pre-plugin machine the installed copy is a SECOND canonical-sdlc, and
# not an inert one: W5 4/6 measured eleven hook registrations in its frontmatter, every one
# spelled for the pre-plugin hooks directory. Until now this script finished without ever
# looking, and then told the user bionic was gone. They ran a teardown, believed it, and
# kept arming bionic's walls every session.
#
# INLINE, NOT `detect_legacy_skill_copy`, and the constraint is this file's oldest one: the
# standalone door. remove.sh is curl-fetchable onto a machine whose plugin is already gone,
# where scripts/lib/ does not exist, so it may not source detect.sh. The established answer
# is a shared literal pinned at both ends — RM_LEGACY_SKILL_NAME above — exactly as the rc
# markers and the todo-tools regex are handled. tests/remove.test.sh Group 17 pins the
# constant in both files and would go red if either moved alone.
#
# THE PREDICATE IS THE DIRECTORY PLUS ITS SKILL.md, copied from the fact function along with
# the name, and it is not decoration: this is a recursive delete, and a bare directory of
# that name is not evidence that the installer rendered anything into it. Re-checked at
# DELETE time as well as at ASK time, the same way setup step 7 re-derives its guards, so a
# resolution that went wrong between the prompt and the removal takes nothing with it.
_rm_item_legacy_skill_copy() {
  _rm_wants legacy-skill-copy || return 0
  echo "legacy installed skill copy:"
  if [ -d "$RM_LEGACY_SKILL_DIR" ] && [ -f "${RM_LEGACY_SKILL_DIR}/SKILL.md" ]; then
    echo "  ${RM_LEGACY_SKILL_DIR} is a pre-plugin rendered copy of a skill the payload also ships."
    echo "  Its frontmatter registers hooks through the pre-plugin channel, so a session that loads"
    echo "  it arms the same walls twice — once from the plugin, once from this copy."
    if _rm_consent "Remove ${RM_LEGACY_SKILL_DIR} and everything under it?"; then
      if [ -d "$RM_LEGACY_SKILL_DIR" ] && [ -f "${RM_LEGACY_SKILL_DIR}/SKILL.md" ]; then
        rm -rf "$RM_LEGACY_SKILL_DIR" 2>/dev/null
      fi
      if [ ! -e "$RM_LEGACY_SKILL_DIR" ]; then
        _rm_removed "legacy installed skill copy at ${RM_LEGACY_SKILL_DIR}"
      else
        _rm_leftover "could not remove ${RM_LEGACY_SKILL_DIR} — the legacy skill copy is still there"
      fi
    else
      _rm_skipped legacy-skill-copy "legacy installed skill copy at ${RM_LEGACY_SKILL_DIR}"
    fi
  else
    _rm_clean "legacy installed skill copy"
  fi
  echo ""
}

# ─── Item: the permission marker block ───────────────────────────────────────
#
# In payload mode the owner does it: profile.sh's `profile_strip` removes the
# block, collapses the containers it created, and preserves the file's newline
# shape. Standalone there is no owner to call, so the jq program below is a
# verbatim copy of profile.sh's `_PROFILE_STRIP_JQ`. Two implementations of one
# behavior is precisely the drift the ownership table exists to prevent, which is
# why tests/remove.test.sh drives the same fixture through both and requires
# byte-identical output.

RM_PROFILE_STRIP_JQ='
  if (.permissions | type) != "object" then .
  elif (.permissions.allow | type) != "array" then .
  else
    .permissions.allow as $a
    | ($a | map(type == "string" and startswith("'"${RM_PROFILE_BEGIN_PREFIX}"'")) | index(true)) as $b
    | ($a | map(. == "'"${RM_PROFILE_END}"'") | index(true)) as $e
    | if $b == null or $e == null or $e < $b then .
      else .permissions.allow = ($a[0:$b] + $a[$e+1:]) end
  end
  | if (.permissions | type) == "object"
       and (.permissions.allow | type) == "array"
       and (.permissions.allow | length) == 0
    then del(.permissions.allow) else . end
  | if (.permissions | type) == "object" and (.permissions | length) == 0
    then del(.permissions) else . end
'

_rm_item_permission_profile() {
  _rm_wants permission-profile || return 0
  echo "permission marker block:"
  if _rm_file_has_literal "$RM_SETTINGS" "$RM_PROFILE_BEGIN_PREFIX"; then
    echo "  ${RM_SETTINGS} carries bionic's permission marker block; bionic would remove the block and leave every rule outside it."
    if _rm_consent "Remove bionic's permission marker block from ${RM_SETTINGS}?"; then
      if [ "$RM_MODE" = "payload" ]; then
        if profile_strip; then
          _rm_removed "permission marker block in ${RM_SETTINGS}"
        else
          _rm_leftover "could not strip the permission marker block from ${RM_SETTINGS}"
        fi
      elif ! _rm_have jq; then
        _rm_leftover "jq is required to edit ${RM_SETTINGS} safely — the permission block is still applied"
      else
        rm_profile_nl=0
        # shellcheck disable=SC2154  # set by printf -v inside _rm_slurp_into
        _rm_slurp_into rm_profile_text "$RM_SETTINGS" && case "$rm_profile_text" in *$'\n') rm_profile_nl=1 ;; esac
        if rm_profile_stripped="$(jq "$RM_PROFILE_STRIP_JQ" "$RM_SETTINGS" 2>/dev/null)"; then
          _rm_write "$RM_SETTINGS" "$rm_profile_stripped" "$rm_profile_nl"
          _rm_removed "permission marker block in ${RM_SETTINGS}"
        else
          _rm_leftover "${RM_SETTINGS} is not valid JSON — refusing to write; the permission block is still applied"
        fi
      fi
    else
      _rm_skipped permission-profile "permission marker block in ${RM_SETTINGS}"
    fi
  else
    _rm_clean "permission marker block in ${RM_SETTINGS}"
  fi
  echo ""
}

# ─── Item: the default permission mode ───────────────────────────────────────
#
# setup.sh's permission-mode step can write `.permissions.defaultMode` — the
# value is deps.sh's, read here rather than spelled again (six-axis review D-1) —
# OUTSIDE the marker block stripped above — a preference of the machine's, not
# one of bionic's rendered rules (A-4.S5.6) — so that strip does not touch it
# and a machine torn down after answering yes to that question keeps
# `defaultMode: auto` behind. This closes the leftover: reset it ONLY when the
# value is still exactly what bionic offers. Any other value, or no key at
# all, is somebody else's setting or somebody else's choice and gets no
# question at all — this item does not decide permission mode, it only offers
# to undo the one value it knows it wrote.
#
# jq REQUIRED to tell "auto" from anything else. A substring check — the way
# the marker block item above tells its block is present — cannot distinguish
# a real `defaultMode` of "auto" from the word appearing anywhere else in the
# file, so without jq this item cannot tell whether it applies and says so
# rather than guessing either way.

_rm_item_permission_mode() {
  _rm_wants permission-mode || return 0
  echo "default permission mode:"
  rm_mode_value="$(_rm_default_mode)"
  if ! _rm_have jq; then
    _rm_leftover "jq is required to read ${RM_SETTINGS} — the default permission mode was not checked"
  elif [ -f "$RM_SETTINGS" ] && [ "$(jq -r '.permissions.defaultMode // ""' "$RM_SETTINGS" 2>/dev/null)" = "$rm_mode_value" ]; then
    if _rm_consent "Reset Claude Code's default permission mode? bionic set it to ${rm_mode_value} at setup."; then
      rm_mode_nl=0
      # shellcheck disable=SC2154  # set by printf -v inside _rm_slurp_into
      _rm_slurp_into rm_mode_text "$RM_SETTINGS" && case "$rm_mode_text" in *$'\n') rm_mode_nl=1 ;; esac
      if rm_mode_stripped="$(jq 'del(.permissions.defaultMode)' "$RM_SETTINGS" 2>/dev/null)"; then
        _rm_write "$RM_SETTINGS" "$rm_mode_stripped" "$rm_mode_nl"
        _rm_removed "default permission mode in ${RM_SETTINGS}"
      else
        _rm_leftover "${RM_SETTINGS} is not valid JSON — refusing to write; the default permission mode is unchanged"
      fi
    else
      _rm_skipped permission-mode "default permission mode in ${RM_SETTINGS}"
    fi
  else
    _rm_clean "default permission mode in ${RM_SETTINGS}"
  fi
  echo ""
}

# ─── Item: the tools bionic installed ────────────────────────────────────────
#
# The table is the payload's, and there is no second copy of it — so this item
# exists only in payload mode, and standalone says exactly that instead of
# pretending the machine is clean.
#
# ENUMERATED BY CLASS: every class except `core` (six-axis review A-1). `core` is
# the two plugins bionic DECLARES, which the uninstall and prune at the end of
# this script take. Everything else — the substrate, the when-needed tools, the
# extras — is a candidate here. This used to walk `dep_names_lane 3b`, the
# retired view, whose rule was "kind != native": it dropped `impeccable`, the one
# native row bionic does not declare, so the plugin a design route can install
# mid-session survived a full, all-yes teardown with nothing even mentioning it.
#
# `remove_dep` is the SSoT for what happens to a dependency: a shared binary is
# kept with consent already given, a plugin bionic declares is left to the
# finisher below, a plugin nothing declares gets its own consented uninstall, and
# only `remove-on-consent` rows reach a package-manager command. Presence is
# asked first so a machine is not interrogated about packages it never had.
#
# The dep names are read on fd 3 deliberately: a `while read < <(...)` loop would
# take the loop's stdin from the process substitution, and remove_dep's consent
# prompt would then read a dependency name as the user's answer.

_rm_item_tools() {
  # A class of items, not one: each row in the table is its own name, so the
  # gate is per row below. The block runs when the whole teardown runs, or when
  # the name asked for is one of its rows.
  case "$RM_ONLY" in ''|tool:*) ;; *) return 0 ;; esac
  echo "tools bionic installed:"
  if [ "$RM_MODE" != "payload" ]; then
    echo "  the dependency table ships with the payload — not available standalone."
    echo "  (reinstall bionic and run /bionic:remove for the dependency pass, or remove them by hand)"
    _rm_leftover "tool teardown was not attempted (standalone mode)"
  else
    dep_lines="$( { dep_names_class basic; dep_names_class when-needed; dep_names_class extra; } )"
    while IFS= read -r dep_name <&3; do
      [ -n "$dep_name" ] || continue
      _rm_wants "tool:${dep_name}" || continue
      dep_behavior="$(dep_field "$dep_name" removal_behavior)"
      dep_present="$(check_dep "$dep_name")"
      dep_present="${dep_present#present=}"; dep_present="${dep_present%%|*}"

      case "$dep_present" in
        yes)
          # THREE OUTCOMES, NOT TWO (critic F-4). `remove_dep` answers 0 for "done
          # what this row's policy says", non-zero for "not done" — and the two
          # not-done cases are different facts about the machine. Exit 2 is "left
          # in place by policy, nothing was asked and nothing was declined": the
          # same-named plugin from another catalog that bionic never installed. It
          # is counted with the rows that were already clean, because reporting an
          # untouched plugin as removed and reporting it as declined are both false.
          remove_dep "$dep_name"; dep_rc=$?
          case "$dep_rc" in
            0)
              if [ "$dep_behavior" = "keep-shared" ]; then
                RM_CLEAN=$((RM_CLEAN + 1))
              else
                RM_REMOVED=$((RM_REMOVED + 1))
              fi
              ;;
            2)
              RM_CLEAN=$((RM_CLEAN + 1))
              ;;
            *)
              RM_SKIPPED=$((RM_SKIPPED + 1))
              RM_SKIPPED_LIST="${RM_SKIPPED_LIST}    ⚠ dependency ${dep_name} — $(_rm_answer_yes "tool:${dep_name}")"$'\n'
              ;;
          esac
          ;;
        no)
          _rm_clean "dependency ${dep_name} (not installed)"
          ;;
        *)
          echo "  ${dep_name}: presence is not knowable on this machine — left in place."
          ;;
      esac
    done 3<<< "$dep_lines"
  fi
  echo ""
}

# ─── Item: the plugin data directory ─────────────────────────────────────────
#
# `~/.claude/plugins/data/<plugin>-<marketplace>` is the state that survives
# plugin updates. The CLI's own uninstall deletes it unless `--keep-data` is
# passed, which is why the answer given here binds the finisher below: declining
# to remove the data and then watching the uninstall delete it anyway would make
# this prompt a lie.
#
# The glob is `bionic-*` and it is announced entry by entry before the question,
# because a plugin whose name merely STARTS with "bionic" would also match it and
# the user is the one who can tell.

_rm_item_plugin_data() {
  _rm_wants plugin-data || return 0
  echo "plugin data:"
  rm_data_found=""
  for rm_data_dir in "$RM_DATA_ROOT"/bionic-*; do
    [ -d "$rm_data_dir" ] || continue
    rm_data_found="${rm_data_found}${rm_data_dir}"$'\n'
  done

  if [ -z "$rm_data_found" ]; then
    _rm_clean "plugin data under ${RM_DATA_ROOT}"
  else
    echo "  bionic would delete these plugin data directories:"
    printf '%s' "$rm_data_found" | while IFS= read -r rm_line; do
      [ -n "$rm_line" ] && echo "    ${rm_line}"
    done
    if _rm_consent "Remove bionic's plugin data?"; then
      rm_data_failed=0
      while IFS= read -r rm_data_dir <&3; do
        [ -n "$rm_data_dir" ] || continue
        _rm_purge_dir "$rm_data_dir" || rm_data_failed=1
      done 3<<< "$rm_data_found"
      if [ "$rm_data_failed" = "0" ]; then
        _rm_removed "plugin data under ${RM_DATA_ROOT}"
      else
        _rm_leftover "some plugin data under ${RM_DATA_ROOT} could not be removed"
      fi
    else
      RM_DATA_DECLINED=1
      _rm_skipped plugin-data "plugin data under ${RM_DATA_ROOT}"
    fi
  fi
  echo ""
}

# ─── Finisher: the native plugin uninstall ───────────────────────────────────
#
# Invoked directly, in this process, with no "come back next session" caveat:
# mid-session uninstall is immediate at the registry level and the very next
# `plugin list` sees it gone (probe-uninstall-semantics.md).
#
# The plugin's ID is asked of the CLI rather than assumed, because the standalone
# door's whole premise is a machine whose answer may be "nothing is registered" —
# and because a machine could carry bionic from a differently-named marketplace.

_rm_item_plugin() {
  _rm_wants plugin || return 0
  # AN ANSWER NOBODY GAVE IS A NO. The uninstall deletes the plugin data unless
  # it is told to keep it, and the question about that data is a DIFFERENT item —
  # one a narrowed run never asked. So a run narrowed to the uninstall keeps the
  # data it was given no permission to take; a whole pass is unchanged, because
  # there the question really was asked and its answer is already recorded.
  _rm_wants plugin-data || RM_DATA_DECLINED=1
  echo "native plugin uninstall:"
  rm_plugin_id=""
  rm_uninstall_ok=0
  if ! _rm_have claude; then
    _rm_leftover "the claude CLI is not on PATH — the native plugin uninstall cannot be invoked here"
  else
    rm_listing="$(claude plugin list --json 2>/dev/null)" || rm_listing=""
    if [ -n "$rm_listing" ] && _rm_have jq; then
      rm_plugin_id="$(printf '%s' "$rm_listing" \
        | jq -r '[ .[]? | select((.id? // "" | split("@")[0]) == "bionic") | .id ][0] // empty' 2>/dev/null)"
    elif [ -n "$rm_listing" ]; then
      # No jq: the id is pulled out of the listing text by bash's own regex
      # engine. A machine missing jq is exactly the machine this door serves.
      if [[ "$rm_listing" =~ \"(bionic@[^\"]+)\" ]]; then rm_plugin_id="${BASH_REMATCH[1]}"; fi
    fi

    if [ -z "$rm_plugin_id" ]; then
      _rm_clean "the bionic plugin (not registered with the CLI)"
    else
      # The plan is printed from the same argv that runs, so the command the user
      # consented to is by construction the command that executes (deps.sh's rule).
      rm_uninstall_argv=(claude plugin uninstall "$rm_plugin_id" --yes)
      [ "$RM_DATA_DECLINED" = "1" ] && rm_uninstall_argv+=(--keep-data)
      echo "  bionic would run: ${rm_uninstall_argv[*]}"
      # WHAT WAS ALREADY THERE, recorded before the call that may add to it. The
      # re-check below removes an empty directory the UNINSTALL left; saying so
      # truthfully means knowing which directories the uninstall did not leave.
      rm_data_before=""
      for rm_data_dir in "$RM_DATA_ROOT"/bionic-*; do
        [ -d "$rm_data_dir" ] || continue
        rm_data_before="${rm_data_before}${rm_data_dir}"$'\n'
      done
      if _rm_consent "Uninstall ${rm_plugin_id} now?"; then
        if "${rm_uninstall_argv[@]}"; then
          rm_uninstall_ok=1
          _rm_removed "plugin ${rm_plugin_id}"
          # ─── Re-check: plugin data, in case the uninstall recreated it ──────
          #
          # Chris's live teardown showed `claude plugin uninstall` re-creating
          # an empty plugins/data/bionic-bionic directory as a side effect of
          # the uninstall itself, independent of the question asked above —
          # that question ran BEFORE this call and never looked again
          # (r1-surface-map.md Item 4). The consent already given is honored
          # against what is actually on disk now, not re-asked: a user who
          # consented to removing bionic's plugin data gets that promise kept
          # even if the CLI resurrects the directory afterward.
          #
          # AND AN EMPTY DIRECTORY IS NOT THE USER'S DATA. The live teardown that
          # found this took the OTHER path — the data question belonged to a
          # different run, so this one told the uninstall to keep the data, and
          # the CLI left an EMPTY directory behind anyway. Keeping nothing is not
          # what "keep my data" asked for; it is just litter with bionic's name
          # on it. So a directory that holds nothing goes either way, and a
          # directory that holds something is removed only where the user said
          # so. Nothing here re-asks, because neither branch takes anything the
          # user has.
          #
          # AND THE CLAIM HAS TO BE TRUE. "The uninstall left this behind" is only
          # sayable about a directory the uninstall actually left, so a directory
          # that was already there when this run began is not taken on that
          # ground — which is also what keeps this from removing something the
          # user declined by name a few lines earlier in the same report.
          rm_data_recheck=""
          for rm_data_dir in "$RM_DATA_ROOT"/bionic-*; do
            [ -d "$rm_data_dir" ] || continue
            if [ "$RM_DATA_DECLINED" = "1" ]; then
              case $'\n'"${rm_data_before}" in
                *$'\n'"${rm_data_dir}"$'\n'*) continue ;;
              esac
              _rm_dir_is_empty "$rm_data_dir" || continue
            fi
            rm_data_recheck="${rm_data_recheck}${rm_data_dir}"$'\n'
          done
          if [ -n "$rm_data_recheck" ]; then
            rm_data_recheck_failed=0
            while IFS= read -r rm_data_dir <&3; do
              [ -n "$rm_data_dir" ] || continue
              _rm_purge_dir "$rm_data_dir" || rm_data_recheck_failed=1
            done 3<<< "$rm_data_recheck"
            if [ "$rm_data_recheck_failed" = "0" ]; then
              if [ "$RM_DATA_DECLINED" = "1" ]; then
                _rm_removed "an empty plugin data directory the uninstall left under ${RM_DATA_ROOT} — it held nothing of yours"
              else
                _rm_removed "plugin data under ${RM_DATA_ROOT} — recreated by the uninstall, removed again"
              fi
            else
              _rm_leftover "some plugin data under ${RM_DATA_ROOT} could not be removed after the uninstall recreated it"
            fi
          fi
        else
          _rm_leftover "claude plugin uninstall ${rm_plugin_id} failed — the plugin is still registered"
        fi
      else
        _rm_skipped plugin "plugin ${rm_plugin_id}"
      fi
    fi
  fi
  echo ""
  # ─── The follow-on rides with the item that creates it ──────────────────────
  #
  # A DEPENDENT CHANGE IS CONSENTED WHEN IT BECOMES REAL. Nothing is orphaned
  # until this uninstall lands, so a run narrowed to one item meets the orphan
  # question BEFORE its own precondition exists: asked first, the CLI's dry run
  # answers with bionic still installed, names nothing, and prints no question —
  # and nobody comes back once the uninstall has made it true. So the offer is
  # made here, by the item that made the orphans, in the run that made them.
  #
  # Only in a narrowed run, and only after a real uninstall: a whole pass already
  # reaches the roster's own entry a moment later, and an uninstall that never
  # happened orphaned nothing.
  if [ "$RM_ONLY" = "plugin" ] && [ "$rm_uninstall_ok" = "1" ]; then
    _rm_offer_orphans
  fi
}

# ─── Finisher: orphaned dependencies ─────────────────────────────────────────
#
# Lane-3a dependencies survive the parent uninstall (probe-dep-persistence.md),
# and the CLI volunteers its own primitive for them in the uninstall's output.
# The offer is built from `prune --dry-run`'s listing verbatim — bionic does not
# walk plugin.json and decide for itself what is orphaned.

_rm_item_orphans() {
  _rm_wants orphaned-dependencies || return 0
  _rm_offer_orphans
}

# The offer itself, callable by whoever gets there first. `_rm_item_plugin` calls
# it because the uninstall is what MAKES these dependencies orphans; the roster
# entry above calls it because a person may come back for them alone.
_rm_offer_orphans() {
  [ "$RM_ORPHANS_OFFERED" = "1" ] && return 0
  RM_ORPHANS_OFFERED=1
  echo "orphaned dependencies:"
  if ! _rm_have claude; then
    _rm_clean "orphaned dependencies (no claude CLI to ask)"
  else
    rm_prune_dry="$(claude plugin prune --dry-run 2>/dev/null)" || rm_prune_dry=""
    case "$rm_prune_dry" in
      *@*)
        echo "  the CLI reports these auto-installed dependencies are no longer needed:"
        _rm_indent "$rm_prune_dry"
        if _rm_consent "Run claude plugin prune to remove them?"; then
          if claude plugin prune --yes; then
            _rm_removed "orphaned dependencies (claude plugin prune)"
          else
            _rm_leftover "claude plugin prune failed — the orphaned dependencies are still installed"
          fi
        else
          _rm_skipped orphaned-dependencies "orphaned dependencies"
        fi
        ;;
      *)
        _rm_clean "orphaned dependencies (the CLI names none)"
        ;;
    esac
  fi
  echo ""
}

# ─── Run ─────────────────────────────────────────────────────────────────────

_rm_item_legacy_alias
_rm_item_shell_env
_rm_item_legacy_hooks
_rm_item_legacy_skill_copy
_rm_item_permission_profile
_rm_item_permission_mode
_rm_item_tools
_rm_item_plugin_data
_rm_item_plugin
_rm_item_orphans

# ─── End summary ─────────────────────────────────────────────────────────────
#
# A NARROWED RUN GETS THE HALF OF THIS THAT IS ABOUT IT. The banner, the
# never-list and the next steps are claims about a WHOLE teardown — "Claude Code
# still works, without bionic's skills, hooks and agents" is false after one
# item — so they belong to the run that earns them. What a narrowed run does
# print is what it did: the counts, and anything it could not finish.

if [ -n "$RM_ONLY" ]; then
  printf '  %d removed · %d already clean · %d skipped by you\n' "$RM_REMOVED" "$RM_CLEAN" "$RM_SKIPPED"
  echo ""
  if [ -n "$RM_LEFTOVERS" ]; then
    echo "  Leftovers (bionic could not finish these)"
    printf '%s' "$RM_LEFTOVERS"
    echo ""
  fi
  exit 0
fi

if [ -z "$RM_LEFTOVERS" ]; then
  echo "# ─── remove complete ───────────────────────────────────────────"
else
  echo "# ─── remove finished — leftovers present ──────────────────────"
fi
echo ""
printf '  %d removed · %d already clean · %d skipped by you\n' "$RM_REMOVED" "$RM_CLEAN" "$RM_SKIPPED"
echo ""

if [ -n "$RM_SKIPPED_LIST" ]; then
  echo "  Skipped (your choice — still on this machine)"
  printf '%s' "$RM_SKIPPED_LIST"
  echo ""
fi

if [ -n "$RM_LEFTOVERS" ]; then
  echo "  Leftovers (bionic could not finish these)"
  printf '%s' "$RM_LEFTOVERS"
  echo ""
fi

echo "  Left in place by design"
echo "    • .bionic/ trees — plans, specs, the record and memory are your work, not bionic's footprint"
echo "    • shared binaries bionic ensured but does not own (git, node, jq, docker, ...)"
echo "    • the pnpm store — a shared cache other projects hard-link from (reclaim with: pnpm store prune)"
echo ""
echo "  Next steps"
echo "    • Restart your shell if the rc file changed"
# THE CLAIM HAS TO SURVIVE ITS OWN REPORT (RV-6). This line was printed unconditionally,
# including four lines under a Skipped list naming the things still on the machine. A
# summary that contradicts the list above it is worse than no summary: it teaches the
# reader to stop reading it. So the unqualified sentence is now the CLEAN run's sentence,
# and a run that left anything behind gets one that points at what it left.
if [ "$RM_SKIPPED" -eq 0 ] && [ -z "$RM_LEFTOVERS" ]; then
  echo "    • Claude Code still works, without bionic's skills, hooks and agents"
else
  echo "    • Claude Code still works — but the items listed above are still on this machine"
fi
echo "    • Reinstall anytime: claude plugin install bionic@bionic"
echo ""

exit 0
