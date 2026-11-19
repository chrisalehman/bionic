#!/bin/bash
# hooks/watch.sh — THE WATCHER: the tick's pass, looped with no model, waking the model only by its exit code.
#
# Registered in hooks/hooks.json on Stop and on SessionStart with `asyncRewake: true` and a `timeout` of
# WATCH_LIFE_MAX (lib/patrol.sh). The platform starts it at each turn's end and at the session's start and does not
# wait for it. While it runs it costs no turn; exit 2 wakes the model with its stderr as the model's message; exit 0, a
# kill and the timeout end it with nothing shown.
# THIS IS THE ONLY PROCESS THAT EXITS WITH THE WAKE CODE TO THE PLATFORM: the pass names the act, the hook decides
# whether the model hears it.
#
# ONE LOOP. Each turn: is the record still mine, is my conversation still the one its process holds, then one pass
# (`session-poker.sh tick --watch`, which runs the tick and stamps), then:
#   wake   -> the pass's line, unchanged, to stderr; the record says resting, woke; exit 2. The turn's end starts the
#             next watcher, so a wake hands the watch on rather than ending it.
#   rest   -> the run waits only on the person: the record says resting, person; exit 0, silent.
#   quiet  -> sleep the watch interval and pass again.
#   refused-> the tick could not judge this session (no roster and never armed, no key): the record says resting,
#             refused; exit 0, silent. A refusal never wakes: the model cannot act on a session the tick cannot read.
# Before resting and on every quiet pass it asks doctor's restart reader for this session: a restart the session
# needs is printed by the tick on every print, but an unchanged print wakes no pass, so nothing would ever say it
# while the run stands still. The watcher wakes on it once, and `told=` on the record keeps it from saying it twice.
#
# ITS DAY. The platform ends the hook at its timeout without a word, so the watcher ends itself first: when the next
# pass would come within WATCH_LIFE_MARGIN of the day's end, an agent still out, or the run's pull request still open
# and watched for its merge, wakes the model once (the turn's end starts a fresh watcher), and with neither it rests at
# its limit. The pass says whether it watched the request in the file BIONIC_WATCH_PR names.
#
# AT MOST ONE A SESSION: the record is the lock (lib/patrol.sh `watch_claim`). A second watcher, from a second turn
# end, finds the first alive and ends at once and silently.
#
# NOTHING IS PRINTED BUT THE WAKE LINE. The tick's own warnings are dropped here: on an asyncRewake hook any stderr
# that rides a wake is read by the model as its instruction.
#
# BY HAND, for one session, as the platform gives it:
#   printf '{"session_id":"<sid>","cwd":"<project>","hook_event_name":"SessionStart","source":"startup"}' \
#     | bash <plugin-root>/hooks/watch.sh
# The session's id is read from that input alone; CLAUDE_CODE_SESSION_ID is set from it for the pass.
#
# BIONIC_WATCH_DEADLINE (seconds) replaces the day's working span, WATCH_LIFE_MAX less WATCH_LIFE_MARGIN, so a suite can
# drive the day's end in seconds.
#
# [WALL: tests/watch.test.sh §HOOK, tests/doctor-restart.test.sh §WATCH]

set -u

command -v jq >/dev/null 2>&1 || exit 0
if [ -t 0 ]; then BIONIC_INPUT=""; else BIONIC_INPUT="$(cat)"; fi

BIONIC_LIB_WANT="patrol.sh alive.sh root.sh roots.sh run.sh"
# Find the library through lib/loader.sh beside this hook; payload/scripts/lib/loader.sh says how.
_bl_dir="$(dirname "$0")"; _bl_l="$_bl_dir/../scripts/lib/loader.sh"; [ -r "$_bl_l" ] || _bl_l="$_bl_dir/../payload/scripts/lib/loader.sh"
# shellcheck source=/dev/null
if [ -r "$_bl_l" ]; then . "$_bl_l"; bionic_load; else
  BIONIC_LIB=""; BIONIC_LIB_MISSING="${BIONIC_LIB_WANT%% *}"; BIONIC_LIB_CANDS="$_bl_dir/../scripts/lib, $_bl_dir/../payload/scripts/lib"
  loader_fail_open() { echo "$1: library $BIONIC_LIB_MISSING not found at $BIONIC_LIB_CANDS — hook stepping aside; run /bionic:doctor" >&2; exit 0; }
  loader_fail_closed() { set -- "$1"; [ "${#1}" -le 25 ] || set -- "${1:0:24}…"; echo "bionic: load refused — $1 cannot load the bionic library (run /bionic:doctor)" >&2; exit 2; }
fi
# A watcher with no library watches nothing and must never wake: it steps aside, as every advisory hook does.
[ -z "$BIONIC_LIB_MISSING" ] || loader_fail_open watch

# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/patrol.sh"

W_POKER="$(cd "$_bl_dir" 2>/dev/null && pwd -P)/session-poker.sh"
W_DOCTOR="$BIONIC_LIB/../doctor.sh"

W_SID="$(printf '%s' "$BIONIC_INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
case "$W_SID" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
W_CWD="$(printf '%s' "$BIONIC_INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$W_CWD" ] || W_CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$W_CWD" 2>/dev/null || exit 0
export CLAUDE_CODE_SESSION_ID="$W_SID"

# A session bionic never engaged gets no watcher and no record: nothing applies until bionic is triggered.
W_ROOT="$(project_root "$PWD")"
W_ROOT="$(cd "$W_ROOT" 2>/dev/null && pwd -P)" || exit 0
engaged_session "$W_ROOT" "$W_SID" || exit 0
[ -d "$W_ROOT/.bionic/tmp" ] && [ ! -L "$W_ROOT/.bionic/tmp" ] || exit 0

watch_claim "$W_ROOT" "$W_SID" "$$" >/dev/null || exit 0

W_BORN="$(date +%s)"
W_SPAN="${BIONIC_WATCH_DEADLINE:-$(( WATCH_LIFE_MAX - WATCH_LIFE_MARGIN ))}"
case "$W_SPAN" in ''|*[!0-9]*) W_SPAN=$(( WATCH_LIFE_MAX - WATCH_LIFE_MARGIN )) ;; esac
# The CLI process this conversation runs in, when its file can be read: after `/clear` that process holds another
# conversation, whose own start brings its own watcher, and this one would wake it with the old one's acts.
W_CLI="$(alive_holder "$W_SID" 2>/dev/null)" || W_CLI=""
W_SLEEP=""
W_PR="$(mktemp "${TMPDIR:-/tmp}/bionic-watch-pr.XXXXXX" 2>/dev/null)" || W_PR=""
trap '[ -z "$W_PR" ] || rm -f "$W_PR"' EXIT
trap '[ -z "$W_SLEEP" ] || kill "$W_SLEEP" 2>/dev/null; exit 143' TERM INT HUP

w_rest() { watch_rest "$W_ROOT" "$W_SID" "$$" "$1" >/dev/null 2>&1; exit 0; }
w_wake() {  # <line> [why]
  watch_rest "$W_ROOT" "$W_SID" "$$" "${2:-woke}" >/dev/null 2>&1
  printf '%s\n' "$1" >&2
  exit "$WATCH_RC_WAKE"
}

# w_restart -> the restart this session needs as `<classes>|<reloaded-since>` on stdout, or nothing: doctor's reader,
# the one the tick prints its restart line from.
w_restart() {
  bash "$W_DOCTOR" --restart-lines < /dev/null 2>/dev/null \
    | awk -F'\t' -v s="$W_SID" 'NF >= 5 && $2 == s { print $4 "|" $5; exit }'
}
# w_restart_once -> wakes on a restart not yet told; returns when there is none, or it was told.
w_restart_once() {
  local key f line
  key="$(w_restart)"
  [ -n "$key" ] && [ "$key" != "$(watch_told_key "$W_ROOT" "$W_SID")" ] || return 0
  f="$(mktemp "${TMPDIR:-/tmp}/bionic-watch.XXXXXX" 2>/dev/null)" || return 0
  printf 'poker: restart needed — %s\n' "$key" > "$f"
  line="$(watch_wake_line "$f")"; rm -f "$f"
  [ -n "$line" ] || return 0
  watch_told "$W_ROOT" "$W_SID" "$$" "$key" >/dev/null 2>&1
  w_wake "$line"
}

while :; do
  watch_holds "$W_ROOT" "$W_SID" "$$" || exit 0
  if [ -n "$W_CLI" ]; then
    W_NOW="$(alive_current "$W_CLI" 2>/dev/null)" || W_NOW=""
    [ -z "$W_NOW" ] || [ "$W_NOW" = "$W_SID" ] || w_rest cleared
  fi

  W_LINE="$(BIONIC_WATCH_PR="$W_PR" bash "$W_POKER" tick --watch 2>/dev/null)"
  W_RC=$?
  case "$W_RC" in
    "$WATCH_RC_WAKE")
      W_LINE="${W_LINE%%$'\n'*}"
      # The pass's line already names a restart when its print was in full: the restart is told by it.
      case "$W_LINE" in
        "bionic watch: restart "*|*"; also restart"|*"; also restart,"*|*", restart"|*", restart,"*)
          W_KEY="$(w_restart)"
          [ -z "$W_KEY" ] || watch_told "$W_ROOT" "$W_SID" "$$" "$W_KEY" >/dev/null 2>&1 ;;
      esac
      w_wake "$W_LINE" ;;
    "$WATCH_RC_REST") w_restart_once; w_rest person ;;
    "$WATCH_RC_QUIET") w_restart_once ;;
    *) w_rest refused ;;
  esac

  W_IV="$(bash "$W_POKER" interval --watch 2>/dev/null)" || W_IV="$WATCH_INTERVAL_DEFAULT"
  case "$W_IV" in ''|*[!0-9]*) W_IV="$WATCH_INTERVAL_DEFAULT" ;; esac
  if [ $(( $(date +%s) - W_BORN + W_IV )) -ge "$W_SPAN" ]; then
    # Out is open on the roster, by the one close predicate every wall asks.
    W_OPEN="$(roster_open_names "$W_ROOT/.bionic/tmp/roster-$W_SID.state" "$W_ROOT/.bionic/tmp/sweeper-$W_SID.state" "$W_SID")"
    [ -n "$W_OPEN" ] && w_wake "bionic watch: RENEW - the watch has run its day with an agent still out: end this turn; its end starts a new watch"
    [ -n "$W_PR" ] && [ -s "$W_PR" ] || w_rest limit
    w_wake "bionic watch: RENEW - the watch has run its day with the pull request open: end this turn; its end starts a new watch"
  fi
  sleep "$W_IV" &
  W_SLEEP=$!
  wait "$W_SLEEP" 2>/dev/null
  W_SLEEP=""
done
