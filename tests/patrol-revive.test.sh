#!/bin/bash
# Tests for hooks/patrol-revive.sh — THE PATROL SELF-HEAL.
#
# THE CONTRACT UNDER TEST. `stop_patrol_revive` (payload/scripts/lib/stop.sh), run by hooks/stop.sh
# at every turn end of an engaged session on a bound open run: a watcher that died without a word is
# said in one advisory line, once, and the turn is never refused for it. The registration rows hold
# hooks/stop.sh on the Stop channel, runnable as the manifest names it.
#
# Usage: bash tests/patrol-revive.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
# The one bound-marker builder (wave-23-fixit-1810 T1), for engage_marker below.
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/duty-read.sh"

# THE MERGED ENTRY POINT (epic-23 wave-11, T12). This monitor is a FUNCTION now —
# `stop_patrol_revive` in payload/scripts/lib/stop.sh — and the process that runs it is
# hooks/stop.sh. Every fixture below drives that process.
HOOK="${BIONIC_PATROL_REVIVE_UNDER_TEST:-${BIONIC_HOOKS_DIR}/stop.sh}"

# THE SOURCE THE THREE FILE-READING ARMS BELOW ASK (epic-23 wave-11, T12). This
# gate's body lives in payload/scripts/lib/stop.sh now; $HOOK is the process that
# runs it. An arm that reads TEXT reads the library, an arm that DRIVES drives the
# hook, and the two are named separately so neither can silently read the other.
HOOK_SRC="${BIONIC_PATROL_REVIVE_SRC_UNDER_TEST:-${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/stop.sh}"

# pass/fail were pure-rename shadows of the framework's ok/no; the suite's own
# explicit TOTAL=$((TOTAL + 1)) lines (including the ones inside
# expect_quiet/expect_block/expect_reason_names below) are dropped too since
# ok/no already increment it (S7, AC-12). expect_quiet/expect_block/
# expect_reason_names are suite-specific helpers (not owned names) rebuilt on
# the framework's ok/no.

command -v jq >/dev/null 2>&1 || { echo "patrol-revive: jq absent — suite cannot run"; exit 1; }

# THE SUITE IS NOT ALLOWED TO BE VACUOUS. Every silent-pass assertion below reads
# "rc 0 and no stdout", which is exactly what a MISSING hook produces once the
# shell's own 127 is discarded — so an absent or unparsable hook would turn most
# of this file green over nothing. Prove the subject exists and parses before any
# of it runs (.claude/rules/test-harness.md, "Anti-vacuity").
[ -f "$HOOK" ] || { echo "patrol-revive: no hook at $HOOK — suite refuses to run"; exit 1; }
bash -n "$HOOK" || { echo "patrol-revive: $HOOK does not parse — suite refuses to run"; exit 1; }

SID="11111111-2222-3333-4444-555555555555"

# ---------- fixture builders ----------

# pr_page <plan> <header lines, or ""> <event>... -> a page at 15 and its run's log, one line per event at
# increasing instants: the log is where a run at 15 keeps its step, so the page holds its header alone.
pr_page() {
  local p="$1" h="$2" d i=0 e; shift 2
  d="${p%/*}"; case "$d" in */plans/*) d="${d%/plans/*}" ;; *) d="${d%/plans}" ;; esac
  d="$d/record/$(basename "$p" .plan.md)"; mkdir -p "${p%/*}" "$d"
  printf -- '---\ncanonical_sdlc_version: 15\n%s---\n' "${h:+$h
}" > "$p"
  for e in "$@"; do i=$((i + 1)); printf 'run/v1|ev=%s|at=2026-10-04T00:%02d:00Z\n' "$e" "$i"; done > "$d/run.log"
}

# An engaged project bound to its own open plan: the one state in which the turn end reads the watch.
make_env() {  # -> project dir on stdout
  local dir; dir=$(mktemp -d)
  mkdir -p "$dir/.bionic/tmp" "$dir/.bionic/docs/plans"
  pr_page "$dir/.bionic/docs/plans/wave-01.plan.md" "" 'step|n=4'
  bound_marker "$dir" "$SID" "$dir/.bionic/docs/plans/wave-01.plan.md"
  printf '%s' "$dir"
}

PR_LIB_DIR_EARLY="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"
pr_iso() {  # <seconds ago> -> ISO-8601 Z
  date -u -v-"$1"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "-$1 seconds" +%Y-%m-%dT%H:%M:%SZ
}

# ---------- driving the hook ----------

# THE ENVIRONMENT AGREES WITH THE PAYLOAD, because on the machine it does (A-probe-2).
PR_ERRFILE="$(mktemp)"
HOOK_ERR_USER=""
fire() {  # <cwd>
  HOOK_OUT=$(jq -nc --arg c "$1" --arg s "$SID" '{session_id:$s,transcript_path:"/dev/null",cwd:$c,hook_event_name:"Stop",stop_hook_active:false}' \
    | env CLAUDE_CODE_SESSION_ID="$SID" bash "$HOOK" 2>"$PR_ERRFILE")
  HOOK_RC=$?
  HOOK_ERR_USER=$(cat "$PR_ERRFILE" 2>/dev/null)
}

section "Group 6: registration"

# A hook with a suite, a run line and no registration is installed, green in its
# own suite, and never fired.
#
# THE CHANNEL MOVED (bionic 1.4.0, task ADOPT, spec AC-7). It was registered in the
# governing skill's frontmatter, which is what made this monitor share the failure mode
# it monitors: three of the four events that kill a Patrol also deregistered the hook,
# silently and at the same moment. It is in hooks/hooks.json now and survives all four —
# so BOTH halves are asserted, because either alone is a wall in the wrong place: a
# lingering frontmatter entry would fire it twice per turn (the CLI does not deduplicate
# across the two manifests), and a missing manifest entry would not fire it at all.
if grep -q '\${CLAUDE_PLUGIN_ROOT}/hooks/stop.sh' \
     "${BIONIC_HOOKS_DIR}/hooks.json"; then
  ok "28: hooks/hooks.json registers the hook, always on"
else
  no "28: the hook is not registered in hooks/hooks.json — it would never fire"
fi

# 29: THE ASSERTION THAT WOULD HAVE CAUGHT THIS. The manifest registers
# this hook as a BARE PATH — `command: ${CLAUDE_PLUGIN_ROOT}/hooks/patrol-revive.sh`,
# no interpreter — and that is exactly how the CLI's own hook runner invokes it: a
# shell handed the literal path as the command, which requires the tracked file
# itself to carry the execute bit. Every other assertion in this suite drives the
# hook through `bash "$HOOK"`, which reads the file regardless of its mode bits and
# would stay green even if the tracked file were not executable — the walk that
# found this bug caught it by reproducing the registration exactly, and that is
# what this assertion now does: a bare path handed to `sh -c`, matching
# `sh -c ".../patrol-revive.sh"` verbatim.
sh -c "$HOOK" <<< '{"hook_event_name":"Stop"}' >/dev/null 2>&1
REGISTERED_RC=$?
if [ "$REGISTERED_RC" -ne 126 ]; then
  ok "29: the hook runs when invoked exactly as registered (bare path via sh -c, rc=$REGISTERED_RC)"
else
  no "29: rc=126 (Permission denied) invoking the hook as the manifest registers it — the tracked file lost its execute bit"
fi

section "§WATCH-LOST — a watcher killed mid-run: the next turn end says so in one line, once, and starts another (AC-12.2)"

# THE CONTRACT. hooks/watch.sh keeps `watch-<sid>.state` in the project's tmp directory; a watcher killed from outside leaves
# it saying watching over a dead process. The turn end runs hooks/stop.sh and hooks/watch.sh together,
# in no fixed order. The new watcher's claim keeps the dead one's pid as `lost=`, so whichever hook
# reads first, the stop wall prints one advisory line naming the dead watcher, and no later turn end
# prints it again. It is a line, not a block: the turn end starts the new watcher itself, so there is
# nothing for the model to do.
# FIXTURE FIDELITY: make_env's engaged project, the real hooks/stop.sh process and the real
# hooks/watch.sh, run on a Stop input as the platform hands it, its day cut to one pass by
# BIONIC_WATCH_DEADLINE so it ends by itself. The dead watcher is a finished subshell's pid.
# ANTI-VACUITY: the one-line rows count the line on the same stream where the control finds none
# over a live watcher; the once-only rows run the turn end that printed it a second time.
# fails-when: the turn end after a watcher's death prints nothing, prints it on a later turn end
# again, refuses the turn, or leaves the record naming the dead watcher.
WL_HOOK="${BIONIC_HOOKS_DIR}/watch.sh"
wl_record() { printf '%s/.bionic/tmp/watch-%s.state' "$1" "$SID"; }
wl_lines() { printf '%s\n' "$HOOK_ERR_USER" | /usr/bin/grep -c 'bionic watch: stopped' ; }
wl_watch() {  # <project> -> the real watcher on a Stop input, one pass, in that project
  jq -nc --arg c "$1" --arg s "$SID" '{session_id:$s,cwd:$c,hook_event_name:"Stop",stop_hook_active:false}' \
    | ( cd "$1" && env BIONIC_WATCH_DEADLINE=1 CLAUDE_CONFIG_DIR="$1/no-config" bash "$WL_HOOK" ) >/dev/null 2>&1
}
wl_dead() {  # <project> -> a record that says watching over a process that has exited
  ( exit 0 ) & WL_PID=$!; wait "$WL_PID" 2>/dev/null
  printf 'state=watching\npid=%s\nstart=%s\nat=%s\n' "$WL_PID" "Thu Jan  1 00:00:00 2026" "$(pr_iso 120)" > "$(wl_record "$1")"
}
sleep 600 & WL_LIVE=$!
WL_START="$(bash -c '. "$1/alive.sh" && alive_since "$2"' _ "$PR_LIB_DIR_EARLY" "$WL_LIVE")"
[ -f "$WL_HOOK" ] && [ -n "$WL_START" ] && ok "WL0 the watcher hook is there and the live fixture has a start" \
  || no "WL0 the watcher hook or the live fixture's start is missing" "hook=$WL_HOOK start=<$WL_START>"

WL=$(make_env)
printf 'state=watching\npid=%s\nstart=%s\nat=%s\n' "$WL_LIVE" "$WL_START" "$(pr_iso 120)" > "$(wl_record "$WL")"
fire "$WL"
expect_eq "WL1 the control: over a live watcher the turn end says nothing of the watch" "0" "$(wl_lines)"

# The stop wall reads first: the record still says watching over the dead process.
WL=$(make_env); wl_dead "$WL"
fire "$WL"; WL_OUT="$HOOK_OUT"; WL_RC=$HOOK_RC
expect_eq "WL2 the stop wall first: one line says the watch stopped" "1" "$(wl_lines)"
expect_contains "WL2a …naming the watcher that died" "pid $WL_PID" "$HOOK_ERR_USER"
expect_eq "WL2b …and it is no block: the turn ends" "0|" "$WL_RC|$(printf '%s' "$WL_OUT" | jq -r '.decision // empty' 2>/dev/null)"
wl_watch "$WL"
WL_STATE="$(bash -c '. "$1/patrol.sh" && watch_state "$2" "$3"' _ "$PR_LIB_DIR_EARLY" "$WL" "$SID")"
case "$WL_STATE" in stopped*|'') no "WL3 …and the turn end's watcher took the record over" "state=<$WL_STATE>" ;;
  *) ok "WL3 …and the turn end's watcher took the record over ($WL_STATE)" ;; esac
fire "$WL"
expect_eq "WL4 the next turn end does not say it again" "0" "$(wl_lines)"

# The watcher claims first: the record already names the new watcher when the stop wall reads.
WL=$(make_env); wl_dead "$WL"; wl_watch "$WL"
expect_contains "WL5 the watcher first: its claim keeps the dead watcher's pid" "lost=$WL_PID" "$(cat "$(wl_record "$WL")")"
fire "$WL"
expect_eq "WL6 …and the stop wall still says it, in one line" "1" "$(wl_lines)"
expect_contains "WL6a …naming the watcher that died" "pid $WL_PID" "$HOOK_ERR_USER"
fire "$WL"
expect_eq "WL7 …and the next turn end does not say it again" "0" "$(wl_lines)"
kill "$WL_LIVE" 2>/dev/null

# ---------- the header's own honesty about its backstop ----------
#
# The retired sentence claimed the CLI overrides this hook "after 8 consecutive blocks".
# It cannot: `stop_hook_active` guarantees exactly one block per turn and the re-entry
# always passes, so the blocks are never consecutive and that override can never engage
# here. A limit accepted against a safety net that does not exist is the thing this pin
# exists to keep out — asserted as a PAIR, so the absence rests on an extractor proven to
# find text in this file.
if grep -q 'never consecutive' "$HOOK_SRC"; then
  ok "39: the header states why the CLI's consecutive-block override cannot engage here"
else
  no "39: the header does not say why the consecutive-block override cannot engage"
fi
if grep -q 'backstop above ours is the CLI' "$HOOK"; then
  no "39b: the header still claims a backstop that cannot fire for this hook"
else
  ok "39b: …and no longer claims that backstop as its own"
fi

finish
