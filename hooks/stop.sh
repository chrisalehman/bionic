#!/bin/bash
# hooks/stop.sh — ONE PROCESS AT TURN END (epic-23 wave-11-lean-spine, REQ-1f (iv);
# spec Design §1 "TurnEndVerdict", §2 D4; ADR-004).
#
# Registered exactly once on Stop and exactly once on SubagentStop. It reads the
# event, runs the four verdict functions of payload/scripts/lib/stop.sh, and lets
# payload/scripts/lib/fold.sh compose whatever they say by one rule:
#
#     any block is a block · all reasons print · blocks before advisories
#
# WHAT THIS REPLACES. Four separate command objects fired on Stop — context-spend,
# landing-gate, patrol-duties-gate, patrol-revive — each with its own copy of the
# same preamble and its own verdict, and NO rule for how four verdicts combine. Up
# to three of them could refuse one stop; the platform collected whichever arrived,
# and an operator reconciled up to four outputs. The functions are named below in
# the order that manifest listed them, so the reasons appear in the order the
# machine has always produced them.
#
# THE ORDER IS A CHOICE THIS FILE MAKES AND NOTHING ELSE DOES. `bionic_fold` runs
# what it is given, in the order it is given; census §6.2 measured that the four are
# independent and order-free at Stop — none reads a file another writes during the
# same event — so the argument order below is about how a composed refusal READS,
# not about correctness.
#
# THE RE-ENTRANCY GUARD IS READ HERE, ONCE. Claude Code re-enters the stop with
# `stop_hook_active` true after a hook blocked it; refusing again would wedge the
# turn with no way out. Three of the four hooks carried an identical copy of this
# line and the fourth carried none at all; there is one now, ahead of all four.
#
# THE LIBRARY IS WANTED IN FULL. `BIONIC_LIB_WANT` names every file the four
# functions between them source — the union of the four hooks' lists plus fold.sh
# and stop.sh — so a partial library fails the loader's readability check and this
# hook steps aside rather than running three verdicts and dropping the fourth.
#
# FAIL OPEN, for the reason all four originals gave: this process can refuse a STOP,
# and a stop refused because a file was missing is a turn nobody can end.
#
# [WALL: tests/stop.test.sh]
#
# Registered in hooks/hooks.json: once on Stop, once on SubagentStop behind
# hooks/agent-context-guard.sh — the same wrapper landing-gate's SubagentStop
# registration carried, with the same reach.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

# ---------- the library ----------
#
# One loader idiom, byte-identical in every hook (spec AC-16); its source of truth is
# payload/scripts/lib/loader.sh.
BIONIC_LIB_WANT="context.sh fold.sh refuse.sh root.sh run.sh session.sh stop.sh worktree.sh"
# --- bionic-loader/v2 BEGIN
# Find the bionic library — pasted BYTE-IDENTICALLY into all 15 carriers, because a library
# cannot load itself. payload/scripts/lib/loader.sh owns this text and its header holds the
# long form; §N.1 of tests/cross-gate-agreement.test.sh pins and caps every copy, and
# tests/loader.test.sh drives the behaviour. BIONIC_LIB_WANT, set on the line above, names
# the basenames this hook sources; afterwards exactly one of BIONIC_LIB (a directory holding
# all of them) and BIONIC_LIB_MISSING is non-empty. CANDIDATES, each class reached only when
# the earlier one fails: (1) beside the hook in BOTH spellings, since `..` resolves after the
# payload/hooks symlink; (2) the marketplace source tree, read from the registry and never
# assumed; (3) the newest version in that marketplace's cache, by THREE-INTEGER compare —
# 1.10.0 beats 1.3.2, which a lexical sort gets backwards. (2) and (3) heal a partly damaged
# install, so one broken location cannot lock the user out of the repair (R-1 §(5)).
BIONIC_LIB=""; BIONIC_LIB_MISSING=""; BIONIC_LIB_CANDS=""
_bl_dir="$(dirname "$0")"; _bl_want="${BIONIC_LIB_WANT:-}"
_bl_try() {
  [ -n "${1:-}" ] || return 1
  if [ -z "$BIONIC_LIB_CANDS" ]; then BIONIC_LIB_CANDS="$1"; else BIONIC_LIB_CANDS="$BIONIC_LIB_CANDS, $1"; fi
  [ -d "$1" ] || return 1
  for _bl_f in $_bl_want; do [ -r "$1/$_bl_f" ] || return 1; done
  BIONIC_LIB="$1"
}
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
loader_fail_open() {
  echo "$1: library ${BIONIC_LIB_MISSING:-the bionic library} not found at ${BIONIC_LIB_CANDS:-(no candidate)} — hook stepping aside; run /bionic:doctor" >&2
  exit 0
}
loader_fail_closed() {
  _bl_root="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)" || _bl_root=""
  [ -n "$_bl_root" ] || _bl_root="$(dirname "$0")/.."
  case "${2:-}" in
    "claude plugin update bionic@bionic"|\
    "claude plugin install bionic@bionic"|\
    "bash $_bl_root/scripts/doctor.sh"|\
    "bash $_bl_root/scripts/setup.sh") exit 0 ;;
  esac
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
if [ -n "$BIONIC_LIB_MISSING" ]; then loader_fail_open "stop"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/context.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/refuse.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"
# THE ROW -> WORKTREE MAPPING (S18, AC-22), for stop_landing_gate's Files:
# reconciliation: `worktree_for_row` is the one place that convention lives.
# shellcheck source=/dev/null
. "$BIONIC_LIB/worktree.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/fold.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/stop.sh"

# THE SEVEN VALUES, ONCE (REQ-1h, lib/context.sh). All four functions read the root,
# the session key, the engagement answer and the run verdict out of this one call.
# Four hooks each spelling the cwd ladder their own way could attribute one session's
# stop to two different roots; one call cannot.
bionic_context 2>/dev/null || exit 0

# BLOCKS ONCE. (jq's `//` folds `false` to empty, so a literal "true" is the only
# value that can match here — which is the comparison we want anyway.) Nothing is
# verdicted on a re-entry: every row is still owed its one answer.
[ "$(bionic_jq .stop_hook_active)" = "true" ] && exit 0

# AN ABSENT FIELD IS PASSED ON AS THE EMPTY STRING, and what each function makes of it
# is the function's own business — not a rule this line imposes. Only `stop_context_spend`
# treats an absent event as Stop (`case "$_ev" in ''|Stop)`, payload/scripts/lib/stop.sh),
# which is the rule hooks/landing-gate.sh stated for its own `case` and the one that
# function keeps. The other three match `Stop` strictly, exactly as their hooks did before
# the merge, so a hand-run payload with no event field wakes the spend instrument and
# nothing else. Base-faithful in both directions; the comment claimed a uniformity the
# four never had.
EVENT=$(bionic_jq .hook_event_name)

bionic_fold "$EVENT" \
  stop_context_spend \
  stop_landing_gate \
  stop_patrol_duties \
  stop_patrol_revive
exit $?
