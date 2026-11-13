#!/bin/bash
# THE STOP GATE'S REGISTERED NAME — PreToolUse|TaskStop in hooks/hooks.json. It decides nothing: the
# payload goes to hooks/stop.sh beside it, which answers the orchestrator's stop of an agent by the
# event's name, and this file exits with what that says. It holds the loader's stub and the context
# call every registered hook holds, so a TaskStop it cannot check is refused here, as it always was:
# exit 2 blocks only that tool call, and the person can still stop a task from the terminal.
#
# [WALL: tests/stop.test.sh]

set -uo pipefail

BIONIC_LIB_WANT="context.sh root.sh run.sh session.sh"
_bl_dir="$(dirname "$0")"; _bl_l="$_bl_dir/../scripts/lib/loader.sh"; [ -r "$_bl_l" ] || _bl_l="$_bl_dir/../payload/scripts/lib/loader.sh"
# shellcheck source=/dev/null
if [ -r "$_bl_l" ]; then . "$_bl_l"; bionic_load; else
  BIONIC_LIB=""; BIONIC_LIB_MISSING="${BIONIC_LIB_WANT%% *}"; BIONIC_LIB_CANDS="$_bl_dir/../scripts/lib, $_bl_dir/../payload/scripts/lib"
  loader_fail_open() { echo "$1: library $BIONIC_LIB_MISSING not found at $BIONIC_LIB_CANDS — hook stepping aside; run /bionic:doctor" >&2; exit 0; }
  loader_fail_closed() { set -- "$1"; [ "${#1}" -le 25 ] || set -- "${1:0:24}…"; echo "bionic: load refused — $1 cannot load the bionic library (run /bionic:doctor)" >&2; exit 2; }
fi
if [ -n "$BIONIC_LIB_MISSING" ] || [ ! -r "$_bl_dir/stop.sh" ]; then loader_fail_closed "stop-guard"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/context.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"

bionic_context 2>/dev/null || exit 0
printf '%s' "$BIONIC_INPUT" | bash "$_bl_dir/stop.sh"
exit $?
