#!/bin/bash
# AN AGENT'S STOP, ITS REGISTERED NAME — SubagentStop in hooks/hooks.json, whose command names
# hooks/stop.sh as this file's argument. It decides nothing: the payload goes to the hook its argument
# names, exactly as it arrived, and this file exits with what that says. hooks/stop.sh asks whether an
# agent's stop is this tool's to judge. An argument that is missing or names no file is a
# misconfiguration, passed through in silence rather than refused.
#
# It holds the loader's stub and the context call every registered hook holds. FAIL CLOSED, ONCE: with
# no library the first stop (`stop_hook_active` false) is refused, and exit 2 holds that agent open,
# so the re-entry, a payload without the field and one jq cannot read all let it end.
#
# [WALL: tests/stop.test.sh]

set -uo pipefail

TARGET="${1:-}"
[ -n "$TARGET" ] || exit 0
case "$TARGET" in '~/'*) TARGET="$HOME/${TARGET#\~/}" ;; esac
[ -f "$TARGET" ] || exit 0

BIONIC_LIB_WANT="context.sh root.sh run.sh session.sh"
# Find the library through lib/loader.sh beside this hook; payload/scripts/lib/loader.sh says how.
_bl_dir="$(dirname "$0")"; _bl_l="$_bl_dir/../scripts/lib/loader.sh"; [ -r "$_bl_l" ] || _bl_l="$_bl_dir/../payload/scripts/lib/loader.sh"
# shellcheck source=/dev/null
if [ -r "$_bl_l" ]; then . "$_bl_l"; bionic_load; else
  BIONIC_LIB=""; BIONIC_LIB_MISSING="${BIONIC_LIB_WANT%% *}"; BIONIC_LIB_CANDS="$_bl_dir/../scripts/lib, $_bl_dir/../payload/scripts/lib"
  loader_fail_open() { echo "$1: library $BIONIC_LIB_MISSING not found at $BIONIC_LIB_CANDS — hook stepping aside; run /bionic:doctor" >&2; exit 0; }
  loader_fail_closed() { set -- "$1"; [ "${#1}" -le 25 ] || set -- "${1:0:24}…"; echo "bionic: load refused — $1 cannot load the bionic library (run /bionic:doctor)" >&2; exit 2; }
fi
if [ -n "$BIONIC_LIB_MISSING" ]; then
  [ "$(jq -r '.stop_hook_active' 2>/dev/null)" = "false" ] || exit 0
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

bionic_context 2>/dev/null || exit 0
printf '%s' "$BIONIC_INPUT" | BIONIC_HOOK_CHANNEL=agent-context bash "$TARGET"
exit $?
