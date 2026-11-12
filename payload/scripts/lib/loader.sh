#!/bin/bash
# payload/scripts/lib/loader.sh — the one loader: how a hook finds the bionic library.
#
# Every hook sources this file through the stub `bionic_loader_pin` prints, pasted on the line under the
# hook's BIONIC_LIB_WANT, and then calls `loader_fail_closed` or `loader_fail_open` when nothing was
# found. Sourcing it defines functions and runs nothing, so doctor and the check table source it too and
# drive the stub against a hook's own path: a probe that re-derived where a hook looks could disagree
# with where it does look.
#
# THE STUB KNOWS TWO PLACES, both beside the hook: scripts/lib, where an install lays hooks/ and scripts/
# as siblings, and payload/scripts/lib, where the repository lays them, payload/hooks being a link to the
# top-level hooks/ ("$0" is textual and `..` is resolved after the link). A hook with this file in
# neither is a broken install: the stub finds nothing, says so in the words below, and the hook's own
# call takes its direction, so a stop that refuses only once still refuses only once.
#
# THE CANDIDATES, each class reached only when the earlier one fails, so a healthy hook pays for no jq
# and no registry read:
#  (1) beside the hook, in the two spellings above;
#  (2) the marketplace source tree. installed_plugins.json names the marketplace this plugin came from
#      and known_marketplaces.json gives its source.path; it is read, never assumed, since a fork
#      installs under its own name. jq runs with stderr closed, so a machine without jq finds nothing
#      in silence rather than printing a shell diagnostic;
#  (3) the newest version directory in that marketplace's cache, by a three-integer compare: 1.10.0
#      beats 1.3.2, which a lexical sort gets backwards.
# (2) and (3) heal a partly damaged install whose loader survived: one damaged location, a sibling
# intact. A publish broken upstream breaks every location alike and is not covered. Tests override the
# machine, never the reverse: BIONIC_PLUGINS_DIR (default "$HOME/.claude/plugins") is the only door to
# the registry and the cache.
#
# THE CONTRACT. BIONIC_LIB_WANT names the basenames the hook sources. Afterwards exactly one of these is
# non-empty: BIONIC_LIB, a readable directory holding every wanted basename, or BIONIC_LIB_MISSING, the
# library wanted and not got. BIONIC_LIB_CANDS lists every location tried, in order. A candidate
# qualifies only by holding all the wanted names, so with none qualifying the first wanted name is the
# honest one to report. A verb that loads a library late takes it from the same BIONIC_LIB.
#
# THE TWO POLICIES. The failure direction is chosen by the cost of the mistake: a wall over an action
# that cannot be taken back calls `loader_fail_closed` and refuses; every other hook calls
# `loader_fail_open`, prints one line and steps aside, since blocking reversible work buys no safety.
# The Bash wall admits the four commands that mend the install before it refuses, matched in its own
# file, the one place that survives this file going missing.
#
# THE REFUSAL IS SPELLED BY HAND, in the renderer's one-line format, because refuse.sh is in the library
# this refusal reports missing; the name is bounded in pure bash for the same reason, 25 columns with the
# ellipsis spent from inside the budget as bionic_trunc spends it. The detail behind BIONIC_WALL_VERBOSE
# is for whoever asks; there is no hook log to write, since the library that owns logging did not load.

# --- bionic-loader/v2 BEGIN
_bl_try() {
  [ -n "${1:-}" ] || return 1
  if [ -z "$BIONIC_LIB_CANDS" ]; then BIONIC_LIB_CANDS="$1"; else BIONIC_LIB_CANDS="$BIONIC_LIB_CANDS, $1"; fi
  [ -d "$1" ] || return 1
  for _bl_f in $_bl_want; do [ -r "$1/$_bl_f" ] || return 1; done
  BIONIC_LIB="$1"
}
bionic_load() {
  BIONIC_LIB=""; BIONIC_LIB_MISSING=""; BIONIC_LIB_CANDS=""
  _bl_dir="${_bl_dir:-$(dirname "$0")}"; _bl_want="${BIONIC_LIB_WANT:-}"
  if ! _bl_try "$_bl_dir/../scripts/lib" && ! _bl_try "$_bl_dir/../payload/scripts/lib"; then
    _bl_pd="${BIONIC_PLUGINS_DIR:-${HOME:-/nonexistent}/.claude/plugins}"; _bl_mk=""
    if [ -r "$_bl_pd/installed_plugins.json" ]; then
      _bl_keys="$(jq -r '(.plugins // {}) | keys[] | select(startswith("bionic@"))' "$_bl_pd/installed_plugins.json" 2>/dev/null)"
      _bl_mk="${_bl_keys%%
*}"
      _bl_mk="${_bl_mk#bionic@}"
    fi
    if [ -n "$_bl_mk" ]; then
      _bl_src=""
      if [ -r "$_bl_pd/known_marketplaces.json" ]; then
        _bl_src="$(jq -r --arg mk "$_bl_mk" '.[$mk].source.path // empty' "$_bl_pd/known_marketplaces.json" 2>/dev/null)"
      fi
      if [ -n "$_bl_src" ]; then _bl_try "$_bl_src/payload/scripts/lib" || :; fi
      if [ -z "$BIONIC_LIB" ]; then
        _bl_best=""; _bl_bestk=""
        for _bl_v in "$_bl_pd/cache/$_bl_mk/bionic"/*; do
          [ -d "$_bl_v" ] || continue
          _bl_n="${_bl_v##*/}"
          case "$_bl_n" in ''|*[!0-9.]*) continue ;; esac
          _bl_x1=""; _bl_x2=""; _bl_x3=""
          IFS=. read -r _bl_x1 _bl_x2 _bl_x3 _bl_rest <<BIONIC_LOADER_VER
$_bl_n
BIONIC_LOADER_VER
          _bl_k="$(printf '%05d%05d%05d' "$((10#${_bl_x1:-0}))" "$((10#${_bl_x2:-0}))" "$((10#${_bl_x3:-0}))" 2>/dev/null)" || continue
          if [ -z "$_bl_bestk" ] || [ "$_bl_k" \> "$_bl_bestk" ]; then _bl_bestk="$_bl_k"; _bl_best="$_bl_n"; fi
        done
        if [ -n "$_bl_best" ]; then _bl_try "$_bl_pd/cache/$_bl_mk/bionic/$_bl_best/scripts/lib" || :; fi
      fi
    fi
  fi
  if [ -z "$BIONIC_LIB" ]; then
    BIONIC_LIB_MISSING="${_bl_want%% *}"
    [ -n "$BIONIC_LIB_MISSING" ] || BIONIC_LIB_MISSING="scripts/lib"
  fi
  return 0
}
loader_fail_open() {
  echo "$1: library ${BIONIC_LIB_MISSING:-the bionic library} not found at ${BIONIC_LIB_CANDS:-(no candidate)} — hook stepping aside; run /bionic:doctor" >&2
  exit 0
}
loader_fail_closed() {
  _bl_root="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)" || _bl_root=""
  [ -n "$_bl_root" ] || _bl_root="$(dirname "$0")/.."
  _bl_who="${1:-a bionic hook}"
  if [ "${#_bl_who}" -gt 25 ]; then _bl_who="${_bl_who:0:24}…"; fi
  printf 'bionic: load refused — %s cannot load the bionic library (run /bionic:doctor)\n' "$_bl_who" >&2
  if [ "${BIONIC_WALL_VERBOSE:-}" = "1" ]; then
    cat >&2 <<BIONIC_LOADER_REFUSE
A wall that cannot read a command refuses it rather than waving it through.

Wanted: ${BIONIC_LIB_MISSING:-the bionic library}
Looked in: ${BIONIC_LIB_CANDS:-(no candidate)}

Until the plugin is whole again this wall permits exactly four commands, each matched
as a whole string:

    claude plugin update bionic@bionic
    claude plugin install bionic@bionic
    bash $_bl_root/scripts/doctor.sh
    bash $_bl_root/scripts/setup.sh

Anything else is refused, including one of those four with another command chained
after it. Run one of them, or act from your own terminal.
BIONIC_LOADER_REFUSE
  fi
  exit 2
}
# --- bionic-loader/v2 END

# The stub, printed for a hook to carry and for a probe to run with "$0" set to a hook's path. Without
# this file beside the hook the stub sets what the loader would have set with nothing found, and defines
# the two calls with the loader's own words, so a hook alone answers as one whose library is gone.
bionic_loader_pin() {
  cat <<'BIONIC_LOADER_PIN_EOF'
# Find the library through lib/loader.sh beside this hook; payload/scripts/lib/loader.sh says how.
_bl_dir="$(dirname "$0")"; _bl_l="$_bl_dir/../scripts/lib/loader.sh"; [ -r "$_bl_l" ] || _bl_l="$_bl_dir/../payload/scripts/lib/loader.sh"
# shellcheck source=/dev/null
if [ -r "$_bl_l" ]; then . "$_bl_l"; bionic_load; else
  BIONIC_LIB=""; BIONIC_LIB_MISSING="${BIONIC_LIB_WANT%% *}"; BIONIC_LIB_CANDS="$_bl_dir/../scripts/lib, $_bl_dir/../payload/scripts/lib"
  loader_fail_open() { echo "$1: library $BIONIC_LIB_MISSING not found at $BIONIC_LIB_CANDS — hook stepping aside; run /bionic:doctor" >&2; exit 0; }
  loader_fail_closed() { set -- "$1"; [ "${#1}" -le 25 ] || set -- "${1:0:24}…"; echo "bionic: load refused — $1 cannot load the bionic library (run /bionic:doctor)" >&2; exit 2; }
fi
BIONIC_LOADER_PIN_EOF
}
