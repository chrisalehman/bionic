#!/bin/bash
# THE PLUGIN-CHANNEL PARTITION GUARD — session-20260815-landing-supervision, T6.
#
# WHAT IS TRUE OF IT TODAY, measured rather than inherited (A-54, and wave-11's fold).
# ONE registration in hooks/hooks.json — SubagentStop, in front of hooks/stop.sh — and
# no other. The header below still describes the partition this file exists for, and the
# partition still holds; what is no longer true of THIS file is the count and the second
# lane:
#
#     hooks.json  ->  this guard  ->  exec hooks/stop.sh   (agent contexts only)
#
# THERE IS NO SKILL-FRONTMATTER LANE. No SKILL.md in this repo carries a `hooks:` key —
# every registration bionic ships is in hooks/hooks.json. The lane the diagram used to
# name was real when this file was written and is not real now, and the argument below
# for why a SECOND channel was needed is kept because it is still why the guard exists:
# the plugin channel is the only one alive inside an agent context.
#
# ITS BASH-SIDE WORK MOVED INTO THE WALL, IT DID NOT DISAPPEAR (A-54, T23). Silencing
# background-suite-guard's backgrounded-suite arm on the main thread and in a session
# with no roster row is a FUNCTION-level gate inside `wall_background_suite_guard`
# (payload/scripts/lib/walls.sh) now, not a wrapper around the folded Bash compound —
# the same five conditions, asked where the wall is rather than in front of five
# processes. This file keeps the turn-end half.
#
# (Historically the first lane was the CLI's own settings.json, which is how this
# file was written and named; the epic-17 plugin conversion moved every always-on
# registration into the payload's hooks.json and nothing on that channel is read out
# of settings.json any more.)
#
# WHY A SECOND CHANNEL WAS NEEDED, which is the argument this file was built on. The
# skill-frontmatter channel was looked up by SESSION key, and a tool-class event raised
# inside a teammate or subagent context is dispatched under the AGENT key — so `PreToolUse|Write`, `PreToolUse|Agent` and
# their PostToolUse twins never reach a skill-registered hook from inside an agent.
# Measured, both directions, with a same-session main-thread positive control:
# .bionic/docs/record/session-20260815-landing-supervision/t1-probe-report.md §3
# (CLI 2.1.233). Every wall this repo has ever installed therefore stopped at depth
# one, and delegating was enough to escape it. The plugin channel IS alive in
# those contexts, which is what this file makes usable.
#
# WHY THE GUARD CANNOT LIVE INSIDE THE WALL. The plugin channel is alive on the
# main thread too, and in every session that mounts the plugin including the ones
# that never invoked the governing skill. A wall invoked through it cannot tell which
# channel called it — same script, same payload — so a guard written into the wall
# would answer the same way on both, and the only predicate that silences the
# plugin channel on a main-thread event (no top-level `agent_id`) would silence
# the skill channel there too, disarming main-thread coverage outright. The guard
# has to be the thing the channel points AT, and nothing else can be.
#
# THE PARTITION (design D1, ratified 2026-08-15; plan AC-8). Run the wall iff:
#
#   1. the payload carries a top-level `agent_id`      — this is an agent context.
#      Main-thread payloads have no such field (t1 §3, `ctx = .agent_id // "MAIN"`).
#   2. `.bionic/tmp/roster-<session_id>.state` exists   — this session is armed.
#      The roster is written by the dispatch wall on the SKILL channel, so it
#      provably precedes any agent context: a teammate exists only after a
#      main-thread dispatch, and that dispatch is what writes the file. An
#      unarmed session therefore fails this check on one stat and pays nothing
#      else, which is what keeps an always-on hooks.json registration from
#      re-globalising walls that were deliberately made skill-scoped.
#
# Anything else — ambiguity included — exits 0 in silence. This guard never
# refuses on its own account and never prints: a refusal here would be a wall
# nobody wrote, and a message here would be attributed to the wall behind it.
#
# THE WALL BEHIND IT IS NAMED BY ARGUMENT, one guard for every wall, because the
# partition is a single fact about a channel rather than a property of any one
# wall. A second copy of this predicate — one per wall, or one per script — is the
# twin the design rejected by name.
#
# THE LEDGER DOES NOT TRAVEL WITH THE WALL. Walls are read-and-refuse predicates
# and cost nothing at depth; writers stay at depth one (the governing principle,
# "distribute the reads, centralize the writes"). hooks/dispatch-preflight.sh is
# both, so this guard hands it BIONIC_HOOK_CHANNEL=agent-context and that script
# skips its roster append alone — a nested dispatch is refused or passed by the
# wall, and never rostered.
#
# Exit code 2 (from the wall behind it) = block the tool call entirely.
# [WALL: tests/agent-context-guard.test.sh]
#
# Registered always-on in hooks/hooks.json, once, on SubagentStop, in front of the wall
# named by its argument — today that argument is hooks/stop.sh.

set -uo pipefail

# ---------- the wall this invocation guards ----------
#
# `~` is expanded by the shell that runs the hooks.json command string, so the
# argument normally arrives absolute; the expansion below only covers a literal
# tilde surviving an exotic invocation. A target that is missing or unnamed is a
# misconfiguration, and a misconfigured guard passes the tool call through rather
# than blocking work on its own confusion.
TARGET="${1:-}"
[ -n "$TARGET" ] || exit 0
case "$TARGET" in '~/'*) TARGET="$HOME/${TARGET#\~/}" ;; esac
[ -f "$TARGET" ] || exit 0

BIONIC_INPUT=$(cat)
_jq() { printf '%s' "$BIONIC_INPUT" | jq -r "$1 // empty" 2>/dev/null; }

# ---------- 1. is this an agent context? ----------
# The cheapest question, asked first and with no filesystem behind it: every
# main-thread tool call on this machine — armed or not — leaves here.
[ -n "$(_jq '.agent_id')" ] || exit 0

# ---------- the library ----------
#
# One loader idiom, byte-identical in every hook (spec AC-16). FAIL OPEN: this guard
# decides whether a wall RUNS, and a guard that refused when it could not load would
# take every wall behind it down with it in every session on the machine.
BIONIC_LIB_WANT="context.sh root.sh run.sh session.sh"
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
if [ -n "$BIONIC_LIB_MISSING" ]; then loader_fail_open "agent-context-guard"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/context.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"

# ---------- 2. is this session armed? ----------
#
# THE CONTEXT IS ONE CALL (REQ-1f, lib/context.sh), and it answers both halves of
# the question this hook used to spell out over twelve lines.
#
# THE SESSION ID (design §1): the environment value is primary, the payload a
# witness. The roster filename is built from it, so this guard and the wall behind
# it have to key on the same one — a guard reading the payload while the wall read
# the environment would answer "unarmed" for the roster the wall had just written.
# The shape guard that used to sit below is the library's now, in the same
# direction: a key carrying a path separator addresses a file outside the state
# directory entirely, and `bionic_context` returns 1 rather than hand it back.
#
# THE ROOT (spec AC-10). This guard must land on the same `.bionic` the dispatch
# wall wrote the roster into, or it answers "unarmed" from a worktree of an armed
# session — a wall that goes quiet exactly where it was added to bind.
bionic_context 2>/dev/null || exit 0
[ -d "$BIONIC_ROOT" ] || exit 0

# ---------- THE ENGAGEMENT GUARD (AC-20): is this session bionic's at all? ----------
#
# FIRST, above every other scoping question this hook asks. Chris, 2026-09-03: "all
# guardrails imposed by bionic should only apply when exercising bionic. Nothing should
# apply until bionic is triggered" — and the trigger is the canonical-sdlc skill, which
# writes `.bionic/tmp/engaged-<sid>.state` at the instant it is invoked. A session that
# never invoked it is one this hook has nothing to say to, and it says nothing: exit 0,
# no stdout, no stderr.
#
# EVERY UNREADABLE STATE READS AS NOT ENGAGED — absent marker, a symlink at the path, a
# foreign or unshaped session key, no key at all. The marker is the one artifact whose
# PRESENCE opens a wall, so the fail direction is inverted here on purpose: the arming
# partition is the consent boundary (1.3.2 close-out), and a wall that binds a session
# which never consented is the defect this guard exists to remove.
# [WALL: tests/agent-context-guard.test.sh]
[ "$BIONIC_ENGAGED" = 1 ] || exit 0

# A symlink anywhere on the arming path is not followed, the same three levels the
# attestation gets in hooks/dispatch-preflight.sh. The stakes are lower here — the
# only thing a planted roster can do is make a wall RUN — but a repo pointing this
# guard at another tree's arming fact is still a repo deciding which session it
# belongs to, and the answer is cheap.
[ ! -L "$BIONIC_ROOT/.bionic" ] && [ ! -L "$BIONIC_ROOT/.bionic/tmp" ] || exit 0
ROSTER_FILE="$BIONIC_ROOT/.bionic/tmp/roster-${BIONIC_SID}.state"
[ ! -L "$ROSTER_FILE" ] && [ -f "$ROSTER_FILE" ] || exit 0

# ---------- both true: hand the payload to the wall ----------
#
# The payload goes back in on stdin exactly as it arrived, and the wall's exit
# status is this guard's — a refusal must reach the harness as the wall's own 2,
# with the wall's own words already on stderr.
printf '%s' "$BIONIC_INPUT" | BIONIC_HOOK_CHANNEL=agent-context bash "$TARGET"
exit $?
