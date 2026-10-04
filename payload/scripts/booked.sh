#!/bin/bash
# booked.sh — RUN A COMMAND INSIDE A MACHINE-WIDE PLACE: stamp, book, run, record rc,
# release (epic-23 wave-26-never-idle, D8, D14; REQ-6 AC-6.3, AC-6.4, REQ-4 AC-4.1).
#
#   bash <plugin-root>/scripts/booked.sh [--kill-after <seconds> [--unbooked]] [--quiet] [--shell <path>]
#                                        -- <command>
#
# WHAT IT IS FOR. The Bash wall rewrites a suite-class command into this shim, so every run
# books one of N places (lib/slots.sh) before it starts and waits when none is free. The
# words after `--` are joined with single spaces and run by `bash -c`, exactly as given: a
# caller that wants the command byte for byte passes it as one quoted word.
#
# --shell <path>: THE HARNESS'S OWN SHELL (wave-26 T7, A-T7.1). The harness runs a Bash call
# as `<its shell> -c '… eval <command> < /dev/null'`, and under a zsh harness `bash -c` would
# change what the command means (echo escapes, word splitting, `${pipestatus}`, an
# unmatched glob). With `--shell` the command runs as `<path> -c "eval '<command>'"`: the
# same shell, the same `eval`, so even the shell's own diagnostics read `(eval):1: …` as
# they do unwrapped. What the shim cannot carry is the harness's shell snapshot (aliases,
# functions, options) and a `cd` that should outlive the call; both fail loud, see the
# T7 record. The stamp's `cmd=` is always the command as given, never this form.
#
# THE ORDER, AND WHY THE STAMP IS READ FIRST. Before booking, the head (`git rev-parse HEAD`)
# and the dirty count (`git status --porcelain | wc -l`) of the tree the shim stands in are
# read; when the command ends one line is appended to that tree's own git dir:
#
#   stamp/v1|head=<40-hex>|dirty=<count>|rc=<n>|at=<ISO-UTC>|cmd=<first 120 chars>
#
# They are read BEFORE the command because what a green run proves is the tree it ran on,
# not the tree its own output left behind. In `cmd=` every `|`, newline, carriage return and
# tab becomes a space BEFORE the cut to 120, so a stamp is always one line of six fields and
# `cmd=` can never carry a `|rc=…` into a reader that splits on `|`. The dirty count skips
# the one line `?? .bionic` when the tree's `.bionic` is a symlink (spawn-worktree's link). In a linked worktree the git dir is the tree's own
# (`.git/worktrees/<name>`), so a stamp never lands in another checkout. Outside a git
# tree, or in one with no commit, there is no stamp and no error. worktree_land reads it.
#
# NESTING. When `BIONIC_SLOT_HELD=1` is already set the command is inside a place, so it
# books nothing and runs (a nested run must never wait on its own parent). Otherwise the
# shim takes a place, exports `BIONIC_SLOT_HELD=1` and `BIONIC_SLOT_PLACE`, and releases on
# every exit path, a signal included. A shim killed with SIGKILL runs no trap; its place is
# reclaimed by the next taker because its pid is gone.
#
# --quiet, OR BIONIC_QUIET=1: THE WHOLE MACHINE. Take every place (slots_take_all: block new
# takes, wait for the held ones to drain), wait for `resources_settled`, run, then read the
# load again. If it rose above the settled line the run is VOID: print `void`, release, and
# go again, at most twice more. Inside a whole-machine hold (`BIONIC_SLOT_QUIET=1`) a nested
# shim, quiet or not, books nothing and runs.
#
# --kill-after <s>: past <s> seconds the command's whole process group is killed, one line says
# it is over the short limit and belongs in a subagent, and the shim exits 124.
#
# --unbooked (only with --kill-after, never with --quiet): THE KILL AND NOTHING ELSE (wave-26
# T9, A-T9.1). The wall sends a short command of a class other than suite through the shim for
# its limit only: it books no place and writes no stamp, because a stamp is a suite's proof
# and the landing rule reads the LAST one in a tree; a short `make` stamped after a green suite
# would stand in for that suite. BIONIC_QUIET in the environment is not read.
#
# EXIT CODES. The command's own, except:
#   2    usage: no `--`, no command, a bad --kill-after, or --unbooked without it or with --quiet
#   69   no place within BIONIC_SLOTS_MAX_WAIT (the line names the holders), or a
#        whole-machine take whose load never settled within it; the command never ran
#   75   void: the load rose during the run on the first run and both retries
#   124  --kill-after fired
#   128+n  the shim itself was stopped by signal n (its command is killed with it)
# 75 is EX_TEMPFAIL, "try again later", which is what a void timing check means.
#
# THE WAITS. Every wait polls every BIONIC_SLOTS_POLL seconds and gives up at
# BIONIC_SLOTS_MAX_WAIT, printing a line at the start and every BIONIC_SLOTS_NOTE_S (lib/
# slots.sh). The store and count follow BIONIC_SLOTS_DIR and BIONIC_SLOTS_N; the load
# follows BIONIC_LOAD_NOW_FILE (lib/resources.sh).
#
# BASH 3.2.
#
# [WALL: tests/slots.test.sh]

BOOKED_SELF_DIR="$(cd "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd -P)"
case "${BASH_SOURCE[0]}" in */*) : ;; *) BOOKED_SELF_DIR="$(pwd -P)" ;; esac
# roots.sh gives resources_settled the project's `quiet-load:`; without it the default holds.
# shellcheck disable=SC1091
. "$BOOKED_SELF_DIR/lib/roots.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$BOOKED_SELF_DIR/lib/resources.sh" || exit 2
# shellcheck disable=SC1091
. "$BOOKED_SELF_DIR/lib/slots.sh" || exit 2

BOOKED_NOPLACE_RC=69
BOOKED_VOID_RC=75
BOOKED_KILLED_RC=124
BOOKED_RETRIES=2

booked_usage() {
  printf 'booked: usage: bash booked.sh [--kill-after <seconds> [--unbooked]] [--quiet] [--shell <path>] -- <command>\n' >&2
  exit 2
}

kill_after=""; quiet=0; sep=0; run_shell=""; unbooked=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --kill-after)   [ "$#" -ge 2 ] || booked_usage; kill_after="$2"; shift 2 ;;
    --kill-after=*) kill_after="${1#--kill-after=}"; shift ;;
    --quiet)        quiet=1; shift ;;
    --unbooked)     unbooked=1; shift ;;
    --shell)        [ "$#" -ge 2 ] && [ -n "$2" ] || booked_usage; run_shell="$2"; shift 2 ;;
    --shell=*)      run_shell="${1#--shell=}"; [ -n "$run_shell" ] || booked_usage; shift ;;
    --)             sep=1; shift; break ;;
    *)              booked_usage ;;
  esac
done
[ "$sep" -eq 1 ] && [ "$#" -ge 1 ] || booked_usage
case "$kill_after" in
  '') : ;;
  *[!0-9]*|0) booked_usage ;;
esac
if [ "$unbooked" -eq 1 ]; then
  [ -n "$kill_after" ] && [ "$quiet" -eq 0 ] || booked_usage
else
  [ "${BIONIC_QUIET:-}" = 1 ] && quiet=1
fi
cmd="$*"

# ── the stamp, read before anything runs ─────────────────────────────────────
stamp_file=""; stamp_head=""; stamp_dirty=""
if [ "$unbooked" -eq 0 ] &&
   [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ] &&
   stamp_head="$(git rev-parse --verify -q HEAD 2>/dev/null)" && [ -n "$stamp_head" ]; then
  stamp_file="$(git rev-parse --absolute-git-dir 2>/dev/null)/bionic-stamps"
  # The tree's own `.bionic` link (spawn-worktree plants it) is not a change to the tree,
  # but git lists it as `?? .bionic` unless the project ignores `.bionic` without a slash.
  # Exactly that one line is skipped, and only when the link is there; nothing else is.
  stamp_top="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$stamp_top" ] && [ -L "$stamp_top/.bionic" ]; then
    stamp_dirty="$(git status --porcelain 2>/dev/null | grep -cvxF -- '?? .bionic')"
  else
    stamp_dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  fi
  case "$stamp_dirty" in ''|*[!0-9]*) stamp_dirty=0 ;; esac
fi

booked_one_line() {  # <text> <n> — pipes and line breaks made spaces, then the first <n> chars
  local s="$1"
  s="${s//|/ }"; s="${s//$'\n'/ }"; s="${s//$'\r'/ }"; s="${s//$'\t'/ }"
  printf '%s' "${s:0:$2}"
}

booked_stamp() {  # <rc>
  [ -n "$stamp_file" ] || return 0
  local c
  c="$(booked_one_line "$cmd" 120)"
  printf 'stamp/v1|head=%s|dirty=%s|rc=%s|at=%s|cmd=%s\n' \
    "$stamp_head" "${stamp_dirty:-0}" "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$c" \
    >> "$stamp_file" 2>/dev/null
  return 0
}

# ── running the command ──────────────────────────────────────────────────────
CHILD=""; RUN_RC=0; STARTED=0; GROUP=0

booked_tree() {  # <pid> — the pid and its descendants, each stopped so none can fork
  local c
  kill -STOP "$1" 2>/dev/null
  printf '%s ' "$1"
  for c in $(pgrep -P "$1" 2>/dev/null); do booked_tree "$c"; done
}

booked_kill_tree() {  # <pid> — TERM the whole tree, then KILL whatever outlives two seconds
  local all p i=0 any
  # A --kill-after command leads its own process group (booked_run), so the group is
  # stopped first and signalled with the tree: a child whose parent already exited has
  # left the tree `pgrep -P` walks, but not the group (wave-26 T9, A-T9.4).
  [ "$GROUP" -eq 0 ] || kill -STOP -- "-$1" 2>/dev/null
  all="$(booked_tree "$1")"
  for p in $all; do kill -TERM "$p" 2>/dev/null; kill -CONT "$p" 2>/dev/null; done
  [ "$GROUP" -eq 0 ] || { kill -TERM -- "-$1" 2>/dev/null; kill -CONT -- "-$1" 2>/dev/null; }
  while [ "$i" -lt 20 ]; do
    any=0
    for p in $all; do kill -0 "$p" 2>/dev/null && any=1; done
    [ "$any" -eq 1 ] || break
    i=$((i + 1)); sleep 0.1
  done
  [ "$any" -eq 0 ] || for p in $all; do kill -KILL "$p" 2>/dev/null; done
  [ "$GROUP" -eq 0 ] || kill -KILL -- "-$1" 2>/dev/null
  return 0
}

booked_run() {  # runs $cmd; sets RUN_RC
  local start killed=0 q
  STARTED=1
  # UNDER --kill-after THE COMMAND LEADS ITS OWN PROCESS GROUP (`set -m` around the one
  # spawn), so the kill reaches every process it started, an orphan included. The group
  # is never the shim's own, so the kill cannot reach the shim or its caller.
  [ -z "$kill_after" ] || { GROUP=1; set -m; }
  if [ -n "$run_shell" ]; then
    # `eval '<cmd>'`, quoted the one way every POSIX shell reads alike: a `'` becomes `'\''`.
    # Unquoted on purpose: bash 3.2 reads `\'` inside a double-quoted ${//} differently.
    q="'\\''"; q=${cmd//\'/$q}; q="'$q'"
    "$run_shell" -c "eval $q" 0<&0 &
  else
    bash -c "$cmd" 0<&0 &
  fi
  CHILD=$!
  [ "$GROUP" -eq 0 ] || set +m
  if [ -n "$kill_after" ]; then
    start=$SECONDS
    while kill -0 "$CHILD" 2>/dev/null; do
      if [ $((SECONDS - start)) -ge "$kill_after" ]; then
        booked_kill_tree "$CHILD"
        killed=1
        break
      fi
      sleep 0.2
    done
  fi
  # The wait's own stderr is closed: a job started under `set -m` and killed by a signal
  # draws a `Terminated: 15` notice from this shell, which is not the command's output.
  { wait "$CHILD"; } 2>/dev/null; RUN_RC=$?
  CHILD=""
  if [ "$killed" -eq 1 ]; then
    RUN_RC=$BOOKED_KILLED_RC
    printf 'booked: stopped after %ss — over the short limit; a longer command belongs in a subagent: dispatch it with the Agent tool, do not raise the timeout\n' \
      "$kill_after" >&2
  fi
}

booked_on_signal() {  # <signal number>
  [ -z "$CHILD" ] || booked_kill_tree "$CHILD"
  CHILD=""
  RUN_RC=$((128 + $1))
  [ "$STARTED" -eq 0 ] || booked_stamp "$RUN_RC"
  exit "$RUN_RC"
}
trap 'booked_on_signal 1' HUP
trap 'booked_on_signal 2' INT
trap 'booked_on_signal 15' TERM
trap 'slots_release "$$"' EXIT

booked_settle() {  # wait for resources_settled under the same ceiling as a place
  local cores start max poll line
  cores="$(_res_cores)"; max="$(_slots_max_wait)"; poll="$(_slots_poll)"
  line="$(resources_settled_line "$cores")"
  start=$SECONDS; _SLOTS_NOTED=-1
  while ! resources_settled "$cores"; do
    if [ $((SECONDS - start)) -ge "$max" ]; then
      printf 'booked: gave up after %ss — the load (%s) never settled at or below %s\n' \
        "$((SECONDS - start))" "$(_res_load_now)" "$line" >&2
      return 1
    fi
    _slots_note "holding the whole machine, waiting for the load ($(_res_load_now)) to settle at or below $line"
    sleep "$poll"
  done
  return 0
}

# ── main ─────────────────────────────────────────────────────────────────────
what="$(booked_one_line "$cmd" 60)"

if [ "$unbooked" -eq 1 ] || [ "${BIONIC_SLOT_QUIET:-}" = 1 ] ||
   { [ "$quiet" -eq 0 ] && [ "${BIONIC_SLOT_HELD:-}" = 1 ]; }; then
  booked_run
elif [ "$quiet" -eq 0 ]; then
  slots_take "$$" "$what" >/dev/null || exit "$BOOKED_NOPLACE_RC"
  export BIONIC_SLOT_HELD=1 BIONIC_SLOT_PLACE="$SLOTS_TAKEN"
  booked_run
else
  # A whole-machine take from inside a held place reads BIONIC_SLOT_HELD to know it is
  # nested, so each retry must see the value this shim was started with.
  outer_held="${BIONIC_SLOT_HELD:-}"
  tries=0
  while :; do
    slots_take_all "$$" "$what" >/dev/null || exit "$BOOKED_NOPLACE_RC"
    booked_settle || exit "$BOOKED_NOPLACE_RC"
    export BIONIC_SLOT_HELD=1 BIONIC_SLOT_QUIET=1
    booked_run
    [ "$RUN_RC" -ne "$BOOKED_KILLED_RC" ] || break
    cores="$(_res_cores)"
    resources_settled "$cores" && break
    rose="$(_res_load_now)"; line="$(resources_settled_line "$cores")"
    slots_release "$$"
    unset BIONIC_SLOT_QUIET
    if [ -n "$outer_held" ]; then export BIONIC_SLOT_HELD="$outer_held"; else unset BIONIC_SLOT_HELD; fi
    tries=$((tries + 1))
    if [ "$tries" -gt "$BOOKED_RETRIES" ]; then
      printf 'void\n' >&2
      printf 'booked: void — the load rose above %s during every run (last %s); a timing result from this machine now would not mean anything\n' \
        "$line" "$rose" >&2
      RUN_RC=$BOOKED_VOID_RC
      break
    fi
    printf 'void\n' >&2
    printf 'booked: void — the load rose to %s during the run, above the settled line %s; retrying (%s of %s)\n' \
      "$rose" "$line" "$tries" "$BOOKED_RETRIES" >&2
  done
fi

booked_stamp "$RUN_RC"
exit "$RUN_RC"
