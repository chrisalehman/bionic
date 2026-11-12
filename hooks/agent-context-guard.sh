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
# The stub below sources the one loader, payload/scripts/lib/loader.sh. FAIL CLOSED, ONCE: a
# subagent's stop with no library is refused, and exit 2 holds that subagent open, so only
# a first stop (`stop_hook_active` false) is refused; the re-entry, a payload without the
# field and one jq cannot read all let it end. A main-thread event has left above.
BIONIC_LIB_WANT="context.sh root.sh run.sh session.sh stop.sh"
# Find the library through lib/loader.sh beside this hook; payload/scripts/lib/loader.sh says how.
_bl_dir="$(dirname "$0")"; _bl_l="$_bl_dir/../scripts/lib/loader.sh"; [ -r "$_bl_l" ] || _bl_l="$_bl_dir/../payload/scripts/lib/loader.sh"
# shellcheck source=/dev/null
if [ -r "$_bl_l" ]; then . "$_bl_l"; bionic_load; else
  BIONIC_LIB=""; BIONIC_LIB_MISSING="${BIONIC_LIB_WANT%% *}"; BIONIC_LIB_CANDS="$_bl_dir/../scripts/lib, $_bl_dir/../payload/scripts/lib"
  loader_fail_open() { echo "$1: library $BIONIC_LIB_MISSING not found at $BIONIC_LIB_CANDS — hook stepping aside; run /bionic:doctor" >&2; exit 0; }
  loader_fail_closed() { set -- "$1"; [ "${#1}" -le 25 ] || set -- "${1:0:24}…"; echo "bionic: load refused — $1 cannot load the bionic library (run /bionic:doctor)" >&2; exit 2; }
fi
if [ -n "$BIONIC_LIB_MISSING" ]; then
  [ "$(printf '%s' "$BIONIC_INPUT" | jq -r '.stop_hook_active' 2>/dev/null)" = "false" ] || exit 0
  loader_fail_closed "agent-context-guard"
fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/context.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/stop.sh"

# ---------- 2. is this session armed? ----------
#
# THE CONTEXT IS ONE CALL (lib/context.sh): the session id, environment first and the payload a
# witness, so this guard and the wall behind it key on the one roster; and the root, mapped from a
# worktree onto the main repository, so an armed session is not read as unarmed from its trees.
#
# THE ARMING QUESTION IS THE STOP LIBRARY'S `stop_agent_armed`: the session engaged bionic (every
# unreadable state of the marker reads as not engaged, since the marker is the consent boundary), no
# link on the path to the roster, and the roster file there. It lives with the stop hook, whose question it is.
bionic_context 2>/dev/null || exit 0
stop_agent_armed || exit 0

# ---------- both true: hand the payload to the wall ----------
#
# The payload goes back in on stdin exactly as it arrived, and the wall's exit
# status is this guard's — a refusal must reach the harness as the wall's own 2,
# with the wall's own words already on stderr.
printf '%s' "$BIONIC_INPUT" | BIONIC_HOOK_CHANNEL=agent-context bash "$TARGET"
exit $?
