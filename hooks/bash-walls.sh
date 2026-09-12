#!/bin/bash
# hooks/bash-walls.sh — ONE PROCESS ON PreToolUse|Bash (epic-23 wave-11-lean-spine,
# REQ-1f (v), AC-1f.5; ADR-004; user ruling A-50 "Option 3", 2026-09-12).
#
# Registered exactly once, on PreToolUse with matcher `Bash`. It reads the payload and
# the command, runs the five wall functions of payload/scripts/lib/walls.sh in the
# order the manifest listed them, and lets payload/scripts/lib/fold.sh compose whatever
# they say by one rule:
#
#     any block is a block · all reasons print · blocks before advisories
#
# WHAT THIS REPLACES. Five command objects fired on every Bash tool call —
# protect-main, protect-database, the canonical-sdlc evidence gate, farm-out-reminder
# and background-suite-guard (that last behind hooks/agent-context-guard.sh) — each
# with its own copy of this preamble, its own loader run and its own verdict, and NO
# rule for how five verdicts combine. Up to three of them could refuse one command; the
# platform collected whichever arrived. The functions are named below in the order that
# manifest listed them, so the reasons appear in the order the machine has always
# produced them.
#
# THE ORDER IS A CHOICE THIS FILE MAKES AND NOTHING ELSE DOES. `bionic_fold` runs what
# it is given, in the order it is given. The five are independent — none reads state
# another writes during one event — so the argument order below is about how a composed
# refusal READS, not about correctness. Every one of them always runs: a push that is
# also a chain-class command gets both answers.
#
# THE PAYLOAD AND THE COMMAND ARE READ BEFORE THE LIBRARY IS. Not for convenience: the
# repair allowlist in `loader_fail_closed` needs the command text, and it has to be
# consulted BEFORE this wall decides to refuse — otherwise a broken publish locks the
# user out of the very commands that repair it (R-1 §(5), the lockout this wave is
# named for). `jq` on the payload is the one read that does not need the library.
#
# ── FAIL-CLOSED, AND WHOSE REACH IT IS (T23 ruling R4) ───────────────────────
#
# The five disagree about a missing library, and they are right to: protect-main and
# the evidence gate stand over IRREVERSIBLE actions and refuse rather than wave a
# command through that they cannot read; the other three step aside, because what they
# prevent costs a re-run. In ONE process the loader either loads or it does not, so
# there is one arm and it is the union of the two closed ones — which is
# protect-main's, because protect-main's is unconditional. It guards a push in EVERY
# project on the machine, wave or no wave, so it carries no pre-check and refuses
# anything that is not one of the four repair commands, in any directory.
#
# THE EVIDENCE GATE'S NARROWER ARM IS GONE, AND HERE IS WHAT THAT DID AND DID NOT
# CHANGE. That wall answered the cheapest question a broken plugin still allows —
# could a run exist HERE, i.e. is there a real `.bionic` at or above the payload cwd —
# and stayed silent where the answer was no (the Step-6 critic's finding 1, 2026-09-03;
# tests/hook-adoption.test.sh §6b). Sharing a process with protect-main's unconditional
# arm, that walk can never be reached: protect-main refuses first, everywhere. What is
# unchanged is the direction and the REACH a user meets — with a broken library every
# Bash command in every project was already refused, by protect-main, and §6b's own
# differential control pinned exactly that. What changed is which wall's name appears
# in the line. The walk is deleted rather than kept unreachable, and the loss is named
# here rather than left for a reader to discover.
#
# THE ENGAGEMENT PREDICATE IS READ HERE, ONCE. All five walls asked the same question in
# identical words (Chris, 2026-09-03: "Nothing should apply until bionic is triggered");
# there is one guard now, ahead of all five, and BELOW the fail-closed arm — which cannot
# be scoped by it, because the predicate lives in the library that just failed to load.
# The line itself is at column zero further down, and it is deliberately the FIRST mention
# of that variable in this file: tests/cross-gate-agreement.test.sh reads the first one and
# holds it to the canonical shape, so a comment quoting the guard above the guard would
# make that row read prose instead of code.
#
# THE LIBRARY IS WANTED ONLY AS WIDE AS THE FAIL-CLOSED ARM REACHES (A-56.1).
# `BIONIC_LIB_WANT` is the union of the two CLOSED walls' pre-fold lists — protect-main's
# and the evidence gate's, readable back at `git show 60c528b:hooks/protect-main.sh` and
# `git show 60c528b:hooks/canonical-sdlc-evidence-gate.sh` — plus fold.sh and walls.sh,
# which are not a wall's ask but the two files this compound is MADE of: a fail-closed
# wall that cannot be called has not been consulted, and a compound that cannot compose
# has no verdict to give.
#
# WHAT IT DELIBERATELY OMITS, AND WHY. Folding five WANT lines into one made this the
# UNION of five, and a union is fail-closed at its widest member: `cmd-class.sh` absent
# refused EVERY Bash command in every project on the machine, where before it only made
# farm-out-reminder and background-suite-guard step aside. R4 puts fail-closed per WALL,
# not per compound, so a library only an advisory wall needs is sourced by that wall's
# own function in payload/scripts/lib/walls.sh (`wall_libs`), and that wall steps aside
# naming the file, in the words its hook used. The declaration lives beside the
# functions, in walls.sh's per-wall table, which doctor reads for the same reason.
#
# [WALL: tests/bash-walls.test.sh]
#
# Registered in hooks/hooks.json: once on PreToolUse, matcher `Bash`.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

BIONIC_INPUT=$(cat) || exit 0
[ -n "$BIONIC_INPUT" ] || exit 0
# `// empty` IS THE SPELLING FOUR OF THE FIVE USED. protect-main's own read had no
# fallback and turned an absent field into the literal `null`; neither value is one of
# the four repair commands and neither parses as a push, so the arm it feeds answers
# the same way and the empty string is the honest one.
COMMAND=$(printf '%s' "$BIONIC_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# ---------- the library ----------
#
# One loader idiom, byte-identical in every hook (spec AC-16); its source of truth is
# payload/scripts/lib/loader.sh.
BIONIC_LIB_WANT="context.sh fold.sh git-argv.sh refuse.sh root.sh run.sh session.sh units.sh walls.sh"
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
if [ -n "$BIONIC_LIB_MISSING" ]; then loader_fail_closed "bash-walls" "$COMMAND"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/context.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/git-argv.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/refuse.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"
# THE ONE READER OF `## Tasks` (REQ-1e, spec §2 D3), for the evidence gate's ledger
# and prototype-row arms.
# shellcheck source=/dev/null
. "$BIONIC_LIB/units.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/fold.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/walls.sh"

# THE SEVEN VALUES, ONCE (REQ-1h, lib/context.sh). All five functions read the root,
# the session key, the engagement answer and the run verdict out of this one call — and
# it ADOPTS the BIONIC_INPUT already read above rather than reaching for a stdin that is
# spent. Five hooks each spelling the cwd ladder their own way could attribute one
# session's command to two different roots; one call cannot.
bionic_context 2>/dev/null || exit 0

# THE ENGAGEMENT GUARD (AC-20), asked once for all five. EVERY UNREADABLE STATE READS
# AS NOT ENGAGED — absent marker, a symlink at the path, a foreign or unshaped session
# key, no key at all. The marker is the one artifact whose PRESENCE opens a wall, so the
# fail direction is inverted here on purpose: the arming partition is the consent
# boundary (1.3.2 close-out).
[ "$BIONIC_ENGAGED" = 1 ] || exit 0

# AN ABSENT FIELD IS NOT A MISMATCH, so a hand-run payload still reaches the walls — the
# rule hooks/stop.sh states for its own event. The event is handed to every function and
# to the fold, which renders `hookSpecificOutput` on it; this hook is registered on one
# event only, so an absent field reads as that one rather than as an empty channel name.
EVENT=$(bionic_jq .hook_event_name)
[ -n "$EVENT" ] || EVENT="PreToolUse"

bionic_fold "$EVENT" \
  wall_protect_main \
  wall_protect_database \
  wall_evidence_gate \
  wall_farm_out_reminder \
  wall_background_suite_guard
exit $?
