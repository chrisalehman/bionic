#!/bin/bash
# THE STOP GATE — PreToolUse|TaskStop, one registration in hooks/hooks.json.
#
# A thin caller. It reads its payload, loads the bionic library, resolves the session's context and
# hands the stop to `stop_guard` in payload/scripts/lib/stop.sh, which judges it, says every refusal
# and writes the roster; this file exits with what it is given. Its own directory is passed in, so a
# fix the guard prints names the scripts beside this hook (stop-check.sh, stop-orders.sh) and the
# sweeper it asks is this hook's sibling, in a checkout and in an installed plugin alike.
#
# FAIL DIRECTIONS: open and silent before the engagement verdict, closed and loud after it. A stop
# is irreversible; the person's recorded order (hooks/stop-orders.sh) is the one override.
#
# Exit code 2 = block the tool call entirely in Claude Code hooks.
# [WALL: tests/stop-guard.test.sh]

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -n "$HOOK_DIR" ] || HOOK_DIR="$(dirname "$0")"

BIONIC_INPUT=$(cat)
_jq() { printf '%s' "$BIONIC_INPUT" | jq -r "$1 // empty" 2>/dev/null; }

TOOL_NAME=$(_jq '.tool_name')
[ "$TOOL_NAME" = "TaskStop" ] || exit 0

# ---------- the library ----------
#
# FAIL CLOSED: a TaskStop this hook cannot check against the roster is refused, which blocks only that
# tool call (never a turn's end); the person can still stop a task from the terminal, and the Bash wall
# admits the four repair commands.
BIONIC_LIB_WANT="context.sh observe.sh refuse.sh root.sh roots.sh roster.sh run.sh session.sh stop.sh"
# Find the library through lib/loader.sh beside this hook; payload/scripts/lib/loader.sh says how.
_bl_dir="$(dirname "$0")"; _bl_l="$_bl_dir/../scripts/lib/loader.sh"; [ -r "$_bl_l" ] || _bl_l="$_bl_dir/../payload/scripts/lib/loader.sh"
# shellcheck source=/dev/null
if [ -r "$_bl_l" ]; then . "$_bl_l"; bionic_load; else
  BIONIC_LIB=""; BIONIC_LIB_MISSING="${BIONIC_LIB_WANT%% *}"; BIONIC_LIB_CANDS="$_bl_dir/../scripts/lib, $_bl_dir/../payload/scripts/lib"
  loader_fail_open() { echo "$1: library $BIONIC_LIB_MISSING not found at $BIONIC_LIB_CANDS — hook stepping aside; run /bionic:doctor" >&2; exit 0; }
  loader_fail_closed() { set -- "$1"; [ "${#1}" -le 25 ] || set -- "${1:0:24}…"; echo "bionic: load refused — $1 cannot load the bionic library (run /bionic:doctor)" >&2; exit 2; }
fi
if [ -n "$BIONIC_LIB_MISSING" ]; then loader_fail_closed "stop-guard"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/context.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/refuse.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/roster.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/roots.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/observe.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/stop.sh"

# The root maps a linked worktree onto its main repository, so the roster this reads is the one the
# dispatch wall wrote; the session key is the library's, the one the engagement marker's writer uses.
bionic_context 2>/dev/null || exit 0
stop_guard "$HOOK_DIR"
exit $?
