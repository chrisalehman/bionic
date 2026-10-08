#!/bin/bash
# booked.sh — RUN A COMMAND THE GATE ADMITTED: stamp, ask, run, end, record rc
# (epic-23 wave-26-never-idle, D8, D14; REQ-6 AC-6.3, AC-6.4, REQ-4 AC-4.1; the gate from
# wave-28-finished-work-lands T12, D10, D13; REQ-2 AC-2.6, AC-2.12, AC-2.13).
#
#   bash <plugin-root>/scripts/booked.sh [--agent <name>] [--kill-after <seconds>]
#                                        [--max-wait <seconds>] [--quiet] [--shell <path>]
#                                        [--stamp-dir <dir>] [--suites <names>] [--runner]
#                                        -- '<the whole command line, as ONE word>'
#
# WHAT IT IS FOR. The Bash wall rewrites a suite-class command into this shim, so every run
# asks the machine's one gate (lib/gate.sh) before it starts and waits its turn there when the
# machine has no room. The command is ONE word after `--`, the whole command line, run exactly
# as given. Several words are refused (exit 2): joined, they would be parsed again as shell, so
# a literal `;` in an argument would run as a command (T36, review 4 F6). Quote the whole
# command as one word.
#
# --shell <path>: THE HARNESS'S OWN SHELL (wave-26 T7, A-T7.1). The harness runs a Bash call
# as `<its shell> -c '… eval <command> < /dev/null'`, and under a zsh harness `bash -c` would
# change what the command means (echo escapes, word splitting, `${pipestatus}`, an
# unmatched glob). With `--shell` the command runs as `<path> -c "eval '<command>'"`: the
# same shell, the same `eval`, so even the shell's own diagnostics read `(eval):1: …` as
# they do unwrapped. The stamp's `cmd=` is always the command as given, never this form.
#
# WHAT A WRAPPED COMMAND LOSES (T44, review 8 F4; the T7 record said "fails loud", and for most
# of this it does not). The command runs in the shim's child shell, not in the harness's own:
#   - a `cd` (or `pushd`) does not outlive the call: the next Bash call starts where this one
#     did, and NOTHING says so;
#   - the harness's shell snapshot is not loaded: a name that exists only as a snapshot alias
#     or function stops with `command not found` (127), which is loud, but one that shadows a
#     command on PATH runs the PATH command instead, in silence, and the snapshot's shell
#     options are zsh's or bash's defaults, also in silence.
# This is why the wall wraps only a suite, short or not (the lead's ruling at T44): a suite's
# `cd` rarely needs to outlive it, and the gate is worth the loss. There is no opt-out (wave-28
# T12, D13): `BIONIC_SLOT_HELD=1` in a suite's prefix used to leave it unwrapped and unbooked,
# and now it is wrapped like any other, so a suite that needs a `cd` or a snapshot name sets it
# up inside its own command text.
#
# THE ORDER, AND WHY THE STAMP IS READ FIRST. Before booking, the head (`git rev-parse HEAD`)
# and the dirty count (`git status --porcelain | wc -l`) of the tree the shim stands in are
# read; when the command ends one line is appended to that tree's own git dir:
#
#   stamp/v1|head=<40-hex>|dirty=<count>|rc=<n>|at=<ISO-UTC>[|suites=<names>]|cmd=<first 120 chars>
#
# They are read BEFORE the command because what a green run proves is the tree it ran on,
# not the tree its own output left behind. In `cmd=` every `|`, newline, carriage return and
# tab becomes a space BEFORE the cut to 120, so a stamp is always one line of six fields and
# `cmd=` can never carry a `|rc=…` into a reader that splits on `|`. The dirty count skips
# the one line `?? .bionic` when the tree's `.bionic` is a symlink (spawn-worktree's link). In a linked worktree the git dir is the tree's own
# (`.git/worktrees/<name>`), so a stamp never lands in another checkout. Outside a git
# tree, or in one with no commit, there is no stamp and no error. worktree_land reads it.
#
# EVERY END STAMPS (wave-26 T61, critic 3 S5), except a usage error (exit 2), which never got as far
# as reading the tree. A command the gate did not admit in time (75), a whole-machine run on a
# store it cannot write (69) and a shim signalled while it waited (128+n) stamp the code they
# ended on, with the same `suites=`, though nothing ran: otherwise "suite a green, suite b never
# ran" at one head leaves only a's line, and the land reads a's proof as the tree's.
#
# --stamp-dir <dir>: THE TREE THE SUITE RUNS IN, WHEN THAT IS NOT WHERE THE SHIM STANDS (wave-26
# T56, final review B1). The wall wraps the WHOLE command, so `cd <tree> || exit 1; bash tests/x`
# typed from the main checkout starts the shim in the main checkout; the wall reads the leading
# literal `cd` and passes where it leads. Head and dirty are then read in <dir> (relative to the
# shim's own directory) and the stamp goes to <dir>'s git dir, and the gate's request names <dir>
# as its tree (`tree=`, which the landing's busy check reads); the command itself still runs where
# the shim stands, and its own `cd` moves it. A <dir> that does not exist or is in no work tree
# is "outside a git tree": no stamp, no error, never a stamp in the shim's own tree instead.
#
# --suites <names>: WHICH SUITES THE COMMAND RAN (wave-26 T61, critic F1). The doctrine runs a
# brief's suites one call each, so one tree collects one stamp per suite, and `cmd=` cannot say
# which suite a line was for (behind the doctrine's `cd <tree> || exit 1;` its 120 characters are
# the path). The wall names the suite files the command runs, by basename, comma-joined, `?` for
# one it cannot name, and the shim writes them as the field `suites=<names>` between `at=` and
# `cmd=`, as handed. Any character outside a name's set (letters, digits, `.`, `_`, `+`, `-`, the
# `,` and `?`) becomes `?`, so the field is always one field of one line. Handed nothing, the
# shim writes the line without the field, as before; a reader that stops at `cmd=` and ignores a
# key it does not know reads both. An empty value is usage. One name, with no `,` or `?`, is also
# the gate's command key (THE ASK, below).
#
# --agent <name>: WHO ASKS (wave-28 T12; T2's A-T2.6). The gate's request records
# `who=<session id>:<agent name>`, and a shell does not know which agent it runs for, so the
# wall, which reads the calling agent's roster row, passes its name (or, with no row, its agent
# id) and the shim exports it as BIONIC_GATE_AGENT. Without it the gate reads `main`. Any
# character outside letters, digits, `.`, `_`, `+` and `-` becomes `_`; an empty value is usage.
#
# THE ASK (wave-28 T12; D10, D13, AC-2.6, AC-2.13). Before the command starts the shim asks the
# gate (lib/gate.sh): `gate_ask work <key> --within <the call's limit>`, the key being the one
# suite file `--suites` names, otherwise the command's first 60 characters, and the limit the
# smaller of --kill-after and --max-wait (none given: it waits until admitted). Admitted, it
# exports `BIONIC_GATE_ADMIT=<request id>`, runs the command, and ends the request with the
# command's own code (`gate_end`), so the gate learns what the command cost. While the command
# runs the shim reads `gate_state` every BIONIC_GATE_POLL seconds (2 unless set), the one call
# that samples a run nothing else polls (T2's sampling note), so its peak is the request's. Not
# admitted in time, it prints one line naming the command to run again, stamps 75 and exits 75:
# NOTHING RAN, and the request keeps its turn, so the same command asked again by the same agent
# resumes its number and is served before every later one. A wait never ends in a kill, under
# --kill-after either.
#
# NESTING. A shim inside an admitted command inherits BIONIC_GATE_ADMIT, and the gate believes
# it only while that request is admitted, unfinished and held by an ancestor of the asker (its
# holder is the outer shim): the nested shim then runs at once under its parent's admission,
# takes no number, and ends nothing. A typed BIONIC_GATE_ADMIT held by no ancestor is not
# believed and the shim asks as usual; BIONIC_SLOT_HELD is not read at all.
#
# THE RUNNER HOLDS NOTHING (D13). A command whose only suite is `run.sh` (the wall's name for a
# runner) is not asked for: each of its suites asks for itself (tests/run.sh --one), so one
# admission never stands for a whole run. It is still stamped.
#
# --runner: THE DOOR'S RUNNER HOLDS NOTHING EITHER (wave-28 T36; D27, AC-10.2). `tests/run.sh
# --only a.test.sh b.test.sh` is the runner, but its --suites names the suites it runs, so the
# stamp says which ones the run proved; the wall passes --runner beside them, when every suite the
# command runs is run by the runner, and the shim then asks nothing, as for `run.sh`.
#
# THE TREE THE ASK NAMES (wave-28 T36; ruling A-orch-55/56). The gate's request records the tree
# the command runs in (`tree=`, git's toplevel where the ask is made), and the landing's busy
# check reads it. That is the tree the stamp goes to: the checkout --stamp-dir resolves inside,
# else the directory a literal `cd <dir>` opening the command names, else where the shim stands.
# The shim makes its ask from there and comes straight back, so the command still runs where the
# shim stands. It used to ask from its own cwd only, so a doctrine call made from the main
# checkout named the main checkout and every writer's suite read as a run there.
#
# A STORE THAT CANNOT BE WRITTEN (T36, review 4 F5). The gate manages throughput; it is not a
# guard. So an ordinary command runs UNADMITTED at once, with one stderr line that names the
# store and says so. A whole-machine run does not run (exit 69, the line names the store): a
# timing result taken without the machine is worth nothing.
#
# --quiet, OR BIONIC_QUIET=1: THE WHOLE MACHINE. Ask `whole` (admitted only alone, nothing else
# admitted unfinished), wait for `resources_settled`, run, then read the load again. If it rose
# above the settled line by more than the run's own share (from the CPU its children used,
# `times`; resources_own_load) the run is VOID: print `void`, settle again and run again, under
# the same admission, at most twice more. Its own load is not a disturbance (T36, review 4 F4).
# A SETTLE THAT GIVES UP ON THE FIRST TRY RUNS THE COMMAND ONCE, AND VOID (wave-27 T6, critic 3
# S4): the runner's rule (tests/run.sh _solo_run), so a timing suite on a machine that never
# settles has output to read whoever runs it. It prints `void` and why, and ends with the
# command's code, or 75 over a pass. A whole run nested inside a whole admission runs at once
# and voids nothing: the hold it runs in is already the whole machine, and its owner reads the
# load. One nested inside a work admission settles and voids as usual.
#
# --kill-after <s>: once MORE than <s> seconds have passed since the shim started, the command's
# whole process group is killed, one line says it is over the short limit and belongs in a
# subagent, and the shim exits 124. The clock is `$SECONDS`, whole seconds, so the kill lands
# up to a second past <s> and never before it (review 12 F4, A-T50.3). THE LIMIT COVERS THE WAIT
# AT THE GATE (T44, review 8 F2): the ask's --within is the limit and the kill is timed from the
# shim's start, so the call ends inside the harness's own timeout whatever the machine is doing.
# A command the gate did not admit within it ends 75, not 124 (AC-2.6): it ran nothing and keeps
# its number. A void --quiet run's retry gets only what is left.
#
# --max-wait <s>: THE CALL'S OWN BOUND ON THE WAIT (wave-27 T6, critic 3 S2). The wall passes the
# Bash call's staged timeout, in seconds, less ten; it is the ask's --within, so a wait at the
# gate ends inside the call instead of outliving it into the background, and it bounds the
# settle and every void retry of a --quiet run. It kills nothing: an admitted command runs as
# long as it runs. The wall leaves it out beside --kill-after, whose limit already bounds the wait.
#
# EVERY COMMAND LEADS ITS OWN PROCESS GROUP (`set -m` around the one spawn; T44, review 8 F3).
# Without job control bash starts a background command with SIGINT and SIGQUIT ignored, and every
# process below it inherits that, so a suite that traps or relies on an interrupt behaved
# differently wrapped. Under `set -m` the command keeps the dispositions it would have had
# unwrapped. What that changes: a signal the shim takes (HUP, INT, QUIT, TERM) is passed on by
# its trap AS ITSELF to the command's group, and whatever is left two seconds later (the
# command, or a child that outlived its parent) gets TERM, then KILL, as under --kill-after
# (review 12 F3, A-T50.2); a signal sent to the CALLER's process group no longer reaches the
# command directly, only through the shim's trap, so a SIGKILL to that group (which runs no
# trap) leaves the command running; and with a controlling terminal the command is a
# background group, so a read from that terminal stops it (a harness Bash call has none, A-T9.4).
#
# EXIT CODES. The command's own, except:
#   2    usage: no `--`, no command, more than one word after `--` (with or without
#        --kill-after), a bad --kill-after or --max-wait, an empty --agent, or an option the
#        shim does not know
#   69   a whole-machine run on a gate store it cannot write; the command never ran
#   75   the gate did not admit the command within the call's limit (the line says to run it
#        again; the command never ran), or void over a PASSING run: the load rose during the
#        run on the first run and both retries, the limit ran out before a retry could start,
#        or the load never settled on the first try. A failing run keeps its own code and still
#        prints the void line (review 12 F2, A-T50.1; the runner's rule)
#   124  --kill-after fired during the run
#   128+n  the shim itself was stopped by signal n (its command is killed with it)
# 75 is EX_TEMPFAIL, "try again later", which is what both a wait that ran out and a void timing
# check of a green run mean; over a red run it would hide the failure behind a reason to re-run.
# A command can exit 69, 75 or 124 itself; the shim's own always comes after a `booked:` or
# `gate:` line on stderr, and the stamp of either is never proof of a green run. The stamp's
# `rc=` is the exit code; it has no field for the void, so a void failure's stamp reads as the
# failure it is.
#
# THE WAITS. The gate's wait polls every BIONIC_GATE_POLL seconds (lib/gate.sh) and prints one
# line when it starts. A --quiet run's settle and its void retries give up together at one
# ceiling taken as the shim starts: the call's limit (--max-wait or --kill-after), or
# BIONIC_SETTLE_MAX_WAIT seconds (1200 unless set) when the call names none. The store follows
# BIONIC_GATE_DIR; the load follows BIONIC_LOAD_NOW_FILE (lib/resources.sh).
#
# BASH 3.2.
#
# [WALL: tests/slots.test.sh]
# [WALL: tests/gate.test.sh]

BOOKED_SELF_DIR="$(cd "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd -P)"
case "${BASH_SOURCE[0]}" in */*) : ;; *) BOOKED_SELF_DIR="$(pwd -P)" ;; esac
# roots.sh gives resources_settled the project's `quiet-load:`; without it the default holds.
# shellcheck disable=SC1091
. "$BOOKED_SELF_DIR/lib/roots.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$BOOKED_SELF_DIR/lib/resources.sh" || exit 2
# gate.sh brings the liveness rule (slots.sh) with it.
# shellcheck disable=SC1091
. "$BOOKED_SELF_DIR/lib/gate.sh" || exit 2

BOOKED_NOSTORE_RC=69
BOOKED_WAITED_RC=75
BOOKED_VOID_RC=75
BOOKED_KILLED_RC=124
BOOKED_RETRIES=2

booked_usage() {
  printf 'booked: usage: bash booked.sh [--agent <name>] [--kill-after <seconds>] [--max-wait <seconds>] [--quiet] [--shell <path>] [--stamp-dir <dir>] [--suites <names>] [--runner] -- <command>\n' >&2
  exit 2
}

kill_after=""; max_wait=""; quiet=0; sep=0; run_shell=""; stamp_dir=""; suites=""; agent=""; runner=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent)        [ "$#" -ge 2 ] && [ -n "$2" ] || booked_usage; agent="$2"; shift 2 ;;
    --agent=*)      agent="${1#--agent=}"; [ -n "$agent" ] || booked_usage; shift ;;
    --kill-after)   [ "$#" -ge 2 ] || booked_usage; kill_after="$2"; shift 2 ;;
    --kill-after=*) kill_after="${1#--kill-after=}"; shift ;;
    --max-wait)     [ "$#" -ge 2 ] || booked_usage; max_wait="$2"; shift 2 ;;
    --max-wait=*)   max_wait="${1#--max-wait=}"; shift ;;
    --quiet)        quiet=1; shift ;;
    --shell)        [ "$#" -ge 2 ] && [ -n "$2" ] || booked_usage; run_shell="$2"; shift 2 ;;
    --shell=*)      run_shell="${1#--shell=}"; [ -n "$run_shell" ] || booked_usage; shift ;;
    --stamp-dir)    [ "$#" -ge 2 ] && [ -n "$2" ] || booked_usage; stamp_dir="$2"; shift 2 ;;
    --stamp-dir=*)  stamp_dir="${1#--stamp-dir=}"; [ -n "$stamp_dir" ] || booked_usage; shift ;;
    --suites)       [ "$#" -ge 2 ] && [ -n "$2" ] || booked_usage; suites="$2"; shift 2 ;;
    --suites=*)     suites="${1#--suites=}"; [ -n "$suites" ] || booked_usage; shift ;;
    --runner)       runner=1; shift ;;
    --)             sep=1; shift; break ;;
    *)              booked_usage ;;
  esac
done
[ "$sep" -eq 1 ] && [ "$#" -ge 1 ] || booked_usage
if [ "$#" -gt 1 ]; then
  printf 'booked: %s words after --, and each would be parsed again as shell — pass the command as one word: booked.sh -- '\''<the whole command line>'\''\n' "$#" >&2
  exit 2
fi
for _n in "$kill_after" "$max_wait"; do
  case "$_n" in
    '') : ;;
    *[!0-9]*|0) booked_usage ;;
  esac
done
[ "${BIONIC_QUIET:-}" = 1 ] && quiet=1
cmd="$*"
[ -z "$agent" ] || export BIONIC_GATE_AGENT="${agent//[!A-Za-z0-9._+-]/_}"

# ── the stamp, read before anything runs ─────────────────────────────────────
stamp_file=""; stamp_head=""; stamp_dirty=""
# Every read goes to --stamp-dir when one is given (`git -C`, no subshell, no extra fork).
stamp_git=(git)
[ -z "$stamp_dir" ] || stamp_git=(git -C "$stamp_dir")
if [ "$("${stamp_git[@]}" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ] &&
   stamp_head="$("${stamp_git[@]}" rev-parse --verify -q HEAD 2>/dev/null)" && [ -n "$stamp_head" ]; then
  stamp_file="$("${stamp_git[@]}" rev-parse --absolute-git-dir 2>/dev/null)/bionic-stamps"
  # The tree's own `.bionic` link (spawn-worktree plants it) is not a change to the tree,
  # but git lists it as `?? .bionic` unless the project ignores `.bionic` without a slash.
  # Exactly that one line is skipped, and only when the link is there; nothing else is.
  stamp_top="$("${stamp_git[@]}" rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$stamp_top" ] && [ -L "$stamp_top/.bionic" ]; then
    stamp_dirty="$("${stamp_git[@]}" status --porcelain 2>/dev/null | grep -cvxF -- '?? .bionic')"
  else
    stamp_dirty="$("${stamp_git[@]}" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
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
  local c s=""
  c="$(booked_one_line "$cmd" 120)"
  [ -z "$suites" ] || s="|suites=${suites//[!A-Za-z0-9._+,?-]/?}"
  printf 'stamp/v1|head=%s|dirty=%s|rc=%s|at=%s%s|cmd=%s\n' \
    "$stamp_head" "${stamp_dirty:-0}" "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$s" "$c" \
    >> "$stamp_file" 2>/dev/null
  return 0
}

# ── running the command ──────────────────────────────────────────────────────
CHILD=""; RUN_RC=0
# The request this shim asked for: its id, and whether this shim holds it (1) or runs under an
# ancestor's admission the gate believed (0). Only a holder samples and ends it.
BOOKED_ID=""; BOOKED_OWN=0; BOOKED_SAMPLE_TICKS=10; BOOKED_IDF=""

booked_tree() {  # <pid> — the pid and its descendants, each stopped so none can fork
  local c
  kill -STOP "$1" 2>/dev/null
  printf '%s ' "$1"
  for c in $(pgrep -P "$1" 2>/dev/null); do booked_tree "$c"; done
}

booked_kill_tree() {  # <pid> — TERM the whole tree, then KILL whatever outlives two seconds
  local all p i=0 any
  # The command leads its own process group (booked_run), so the group is stopped first and
  # signalled with the tree: a child whose parent already exited has left the tree `pgrep -P`
  # walks, but not the group (wave-26 T9, A-T9.4; every spawn since T44).
  kill -STOP -- "-$1" 2>/dev/null
  all="$(booked_tree "$1")"
  for p in $all; do kill -TERM "$p" 2>/dev/null; kill -CONT "$p" 2>/dev/null; done
  kill -TERM -- "-$1" 2>/dev/null; kill -CONT -- "-$1" 2>/dev/null
  while [ "$i" -lt 20 ]; do
    any=0
    for p in $all; do kill -0 "$p" 2>/dev/null && any=1; done
    [ "$any" -eq 1 ] || break
    i=$((i + 1)); sleep 0.1
  done
  [ "$any" -eq 0 ] || for p in $all; do kill -KILL "$p" 2>/dev/null; done
  kill -KILL -- "-$1" 2>/dev/null
  return 0
}

booked_over_limit() {  # the one line a command stopped at its short limit gets
  printf 'booked: stopped after %ss — over the short limit; a longer command belongs in a subagent: dispatch it with the Agent tool, do not raise the timeout\n' \
    "$kill_after" >&2
}

booked_run() {  # runs $cmd; sets RUN_RC
  local killed=0 q tick=0
  # THE COMMAND LEADS ITS OWN PROCESS GROUP (`set -m` around the one spawn; see the header):
  # it starts with the signal dispositions it would have had unwrapped, and the kill reaches
  # every process it started, an orphan included. The group is never the shim's own, so the
  # kill cannot reach the shim or its caller.
  #
  # THE FORK SPEAKS ON NOTHING (wave-26 T63, the full run's W8.3). Under `set -m` the parent and
  # the forked child each put the child in its own group, and under load the two calls race:
  # about one fork in a thousand, the child's call fails, and bash prints `child setpgid (<pid> to
  # <pid>): Operation not permitted` on the stderr it holds at that moment, which is the
  # command's. The parent's call has made the group either way. So the shim's own stderr is
  # /dev/null for the fork alone, and the command gets the real one back (fd 9) before it runs.
  exec 9>&2 2>/dev/null
  set -m
  if [ -n "$run_shell" ]; then
    # `eval '<cmd>'`, quoted the one way every POSIX shell reads alike: a `'` becomes `'\''`.
    # Unquoted on purpose: bash 3.2 reads `\'` inside a double-quoted ${//} differently.
    q="'\\''"; q=${cmd//\'/$q}; q="'$q'"
    "$run_shell" -c "eval $q" 0<&0 2>&9 9>&- &
  else
    bash -c "$cmd" 0<&0 2>&9 9>&- &
  fi
  CHILD=$!
  set +m
  exec 2>&9 9>&-
  if [ -n "$kill_after" ] || [ "$BOOKED_OWN" -eq 1 ]; then
    # One loop watches both clocks. The kill is timed from the shim's start (BOOKED_T0), so the
    # wait at the gate spends the limit too. `$SECONDS` counts whole seconds of the wall clock,
    # so a difference of N is anywhere in (N-1, N+1) seconds: only "more than N" is never early
    # (review 12 F4, A-T50.3). It fires up to a second late, which the five seconds the wall
    # leaves before the harness's own timeout absorb with the kill's grace. THE SAMPLE (T12; T2's
    # sampling note): a request's peak rises only on a locked gate read, so a holder reads
    # `gate_state` every BIONIC_GATE_POLL seconds while its command runs; its own output is
    # nothing the command's reader sees. IN A SUBSHELL: a trap runs between two commands of a
    # function, so a signal taken inside `gate_state` here would run booked_end while this very
    # shell held the gate's lock, and gate_end would wait out the lock it holds itself. A
    # subshell is one foreground command: the trap waits for it, and the lock it took is its own.
    while kill -0 "$CHILD" 2>/dev/null; do
      if [ -n "$kill_after" ] && [ $((SECONDS - BOOKED_T0)) -gt "$kill_after" ]; then
        booked_kill_tree "$CHILD"
        killed=1
        break
      fi
      if [ "$BOOKED_OWN" -eq 1 ]; then
        tick=$((tick + 1))
        if [ "$tick" -ge "$BOOKED_SAMPLE_TICKS" ]; then
          ( gate_state ) >/dev/null 2>&1
          tick=0
        fi
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
    booked_over_limit
  fi
}

booked_end() {  # the request this shim holds is over: the gate records it with the run's code
  [ "$BOOKED_OWN" -eq 1 ] || return 0
  BOOKED_OWN=0
  gate_end "$BOOKED_ID" "$RUN_RC" >/dev/null
}

booked_on_signal() {  # <signal number>
  local i=0
  if [ -n "$CHILD" ]; then
    # THE SIGNAL GOES ON AS ITSELF (review 12 F3, A-T50.2): the command's group gets what the shim
    # got, so an INT handler sees INT, as it would unwrapped. Two seconds later whatever is left,
    # the leader or an orphan in its group, gets the TERM-then-KILL of booked_kill_tree.
    kill -"$1" -- "-$CHILD" 2>/dev/null
    while [ "$i" -lt 20 ] && kill -0 "$CHILD" 2>/dev/null; do i=$((i + 1)); sleep 0.1; done
    booked_kill_tree "$CHILD"
  fi
  CHILD=""
  RUN_RC=$((128 + $1))
  # An admitted run ends at the gate with the signal's code; a shim stopped while it waited
  # leaves its request to the gate, which serves no request whose holder is gone.
  booked_end
  # Stamped whether or not the command had started: a signal during the wait is an end too.
  booked_stamp "$RUN_RC"
  exit "$RUN_RC"
}
trap 'booked_on_signal 1' HUP
trap 'booked_on_signal 2' INT
trap 'booked_on_signal 3' QUIT
trap 'booked_on_signal 15' TERM
trap 'rm -f ${BOOKED_TIMES:+"$BOOKED_TIMES"} ${BOOKED_IDF:+"$BOOKED_IDF"}' EXIT

# booked_req_field <id> <field> — the request's last <field>= line (lib/gate.sh's request file).
booked_req_field() {
  sed -n "s/^$2=//p" "$(gate_dir)/requests/$1" 2>/dev/null | tail -n 1
}

booked_not_admitted() {  # the gate did not admit the command within the call's limit; nothing ran
  printf 'booked: the gate did not admit this command within %ss; request %s keeps its turn — run again: %s\n' \
    "$BOOKED_WITHIN" "${BOOKED_ID:-?}" "$cmd" >&2
  booked_stamp "$BOOKED_WAITED_RC"
  exit "$BOOKED_WAITED_RC"
}

# booked_cd_dir — the directory a literal `cd <dir>` opening the command names, or nothing. A
# plain word only: a quote, an expansion, a glob or a `~` is not read, and the ask then names
# where the shim stands.
booked_cd_dir() {
  local c="${cmd#"${cmd%%[![:space:]]*}"}" d
  case "$c" in cd[[:space:]]*) : ;; *) return 0 ;; esac
  d="${c#cd}"; d="${d#"${d%%[![:space:]]*}"}"; d="${d%%[[:space:];&|]*}"
  case "$d" in ''|-*|*[\'\"\$\`\\~*?\[]*) return 0 ;; esac
  printf '%s' "$d"
}
BOOKED_ASK_DIR="$stamp_dir"
[ -n "$BOOKED_ASK_DIR" ] || BOOKED_ASK_DIR="$(booked_cd_dir)"

# booked_ask <work|whole> — asks the gate in this shell (never in `$( )`: a signal must reach
# the trap while it waits, and the holder is this process). Sets BOOKED_ID and BOOKED_OWN and
# exports BIONIC_GATE_ADMIT; ends the shim itself on a wait that ran out (75) and on a store it
# cannot write for a whole run (69). An ordinary run on such a store goes on unadmitted.
booked_ask() {
  local rc here="$PWD" moved=0
  BOOKED_IDF="$(mktemp "${TMPDIR:-/tmp}/booked-id.XXXXXX" 2>/dev/null)"
  # Asked from the stamp's tree (THE TREE THE ASK NAMES), in this shell, then straight back.
  if [ -n "$BOOKED_ASK_DIR" ] && cd "$BOOKED_ASK_DIR" 2>/dev/null; then moved=1; fi
  if [ -n "$BOOKED_IDF" ]; then
    gate_ask "$1" "$BOOKED_KEY" ${BOOKED_WITHIN:+--within "$BOOKED_WITHIN"} > "$BOOKED_IDF"; rc=$?
    { read -r BOOKED_ID < "$BOOKED_IDF"; } 2>/dev/null
    rm -f "$BOOKED_IDF"; BOOKED_IDF=""
  else
    BOOKED_ID="$(gate_ask "$1" "$BOOKED_KEY" ${BOOKED_WITHIN:+--within "$BOOKED_WITHIN"})"; rc=$?
  fi
  [ "$moved" -eq 0 ] || cd "$here" 2>/dev/null
  case "$rc" in
    0)
      # Held by this process, or by an ancestor whose admission the gate believed (nested).
      case "$(booked_req_field "$BOOKED_ID" holder)" in
        "$$:"*) BOOKED_OWN=1 ;;
        *) BOOKED_OWN=0 ;;
      esac
      export BIONIC_GATE_ADMIT="$BOOKED_ID" ;;
    75) booked_not_admitted ;;
    *)
      BOOKED_ID=""
      if [ "$1" = whole ]; then
        printf 'booked: cannot write the gate'\''s store %s, so the whole machine cannot be had and a timing result would mean nothing — fix: make it writable, or point BIONIC_GATE_DIR at a directory you can write\n' \
          "$(gate_dir)" >&2
        booked_stamp "$BOOKED_NOSTORE_RC"
        exit "$BOOKED_NOSTORE_RC"
      fi
      printf 'booked: cannot write the gate'\''s store %s — this command runs unadmitted, beside whatever else runs; fix: make it writable, or point BIONIC_GATE_DIR at a directory you can write\n' \
        "$(gate_dir)" >&2 ;;
  esac
}

booked_settle() {  # wait for resources_settled, until the shim's one ceiling (BOOKED_DEADLINE)
  local cores poll line noted=0
  cores="$(_res_cores)"; poll="${BIONIC_GATE_POLL:-2}"
  line="$(resources_settled_line "$cores")"
  while ! resources_settled "$cores"; do
    if [ "$SECONDS" -ge "$BOOKED_DEADLINE" ]; then
      printf 'booked: gave up after %ss — the load (%s) never settled at or below %s\n' \
        "$((SECONDS - BOOKED_T0))" "$(_res_load_now)" "$line" >&2
      return 1
    fi
    if [ "$noted" -eq 0 ]; then
      printf 'booked: holding the whole machine, waiting for the load (%s) to settle at or below %s\n' \
        "$(_res_load_now)" "$line" >&2
      noted=1
    fi
    sleep "$poll"
  done
  return 0
}

# booked_times — sets BOOKED_CPU to the CPU seconds this shell's finished children have used
# (`times`, second line). Called directly, never in `$( )`: a subshell has no children.
BOOKED_TIMES=""; BOOKED_CPU=0
booked_times() {
  BOOKED_CPU=0
  [ -n "$BOOKED_TIMES" ] || return 0
  times > "$BOOKED_TIMES" 2>/dev/null || return 0
  BOOKED_CPU="$(awk '
    function sec(x, a) { sub(/s$/, "", x); gsub(",", ".", x); split(x, a, "m"); return a[1] * 60 + a[2] }
    NR == 2 { printf "%.3f\n", sec($1) + sec($2) }' "$BOOKED_TIMES" 2>/dev/null)"
  [ -n "$BOOKED_CPU" ] || BOOKED_CPU=0
}

booked_void() {  # <why> — a whole-machine run that was not measured: `void`, why, and 75 over a pass
  # A failing run keeps its own code (review 12 F2, A-T50.1): 75 over it would hide the failure
  # behind a reason to re-run.
  printf 'void\n' >&2
  printf 'booked: void — %s\n' "$1" >&2
  [ "$RUN_RC" -ne 0 ] || RUN_RC=$BOOKED_VOID_RC
}

# ── main ─────────────────────────────────────────────────────────────────────
BOOKED_T0=$SECONDS
# THE CALL'S LIMIT: the smaller of --kill-after and --max-wait; the ask's --within, and the one
# ceiling of a --quiet run's settle and retries. With neither, the gate waits until it admits,
# and the settle's ceiling is BIONIC_SETTLE_MAX_WAIT.
BOOKED_WITHIN="$kill_after"
if [ -n "$max_wait" ] && { [ -z "$BOOKED_WITHIN" ] || [ "$max_wait" -lt "$BOOKED_WITHIN" ]; }; then
  BOOKED_WITHIN="$max_wait"
fi
case "${BIONIC_SETTLE_MAX_WAIT:-}" in ''|*[!0-9]*) BOOKED_SETTLE_MAX=1200 ;; *) BOOKED_SETTLE_MAX=$BIONIC_SETTLE_MAX_WAIT ;; esac
# The settle gives up at "$SECONDS >= deadline", so a kill limit gets one second more: the
# settle then gives up past the limit, never before it, by the kill's own rule (A-T50.3).
if [ -n "$BOOKED_WITHIN" ]; then
  BOOKED_CUT=0; [ "$BOOKED_WITHIN" != "$kill_after" ] || BOOKED_CUT=1
  BOOKED_DEADLINE=$((BOOKED_T0 + BOOKED_WITHIN + BOOKED_CUT))
else
  BOOKED_DEADLINE=$((BOOKED_T0 + BOOKED_SETTLE_MAX))
fi
# THE COMMAND KEY: the one suite file --suites names, else the command's first 60 characters.
case "$suites" in
  ''|*,*|*'?'*) BOOKED_KEY="$(booked_one_line "$cmd" 60)" ;;
  *) BOOKED_KEY="${suites//[!A-Za-z0-9._+-]/?}" ;;
esac
# The sample's cadence, in the run loop's 0.2 s ticks: the gate's own poll, at least one tick.
BOOKED_SAMPLE_TICKS="$(awk -v p="${BIONIC_GATE_POLL:-2}" 'BEGIN { t = int(p / 0.2 + 0.5); print (t >= 1 ? t : 1) }' 2>/dev/null)"
case "$BOOKED_SAMPLE_TICKS" in ''|*[!0-9]*|0) BOOKED_SAMPLE_TICKS=10 ;; esac

if [ "$quiet" -eq 0 ]; then
  # THE RUNNER HOLDS NOTHING (D13): each of its suites asks for itself.
  if [ "$suites" != run.sh ] && [ "$runner" -eq 0 ]; then
    booked_ask work
  fi
  booked_run
  booked_end
elif booked_ask whole && [ "$BOOKED_OWN" -eq 0 ] && [ -n "$BOOKED_ID" ] &&
     [ "$(booked_req_field "$BOOKED_ID" kind)" = whole ]; then
  # Inside a whole admission already: the hold is the whole machine, and its owner reads the load.
  booked_run
else
  tries=0
  BOOKED_TIMES="$(mktemp "${TMPDIR:-/tmp}/booked-times.XXXXXX" 2>/dev/null)"
  if ! booked_settle; then
    # THE RUNNER'S RULE (tests/run.sh _solo_run; wave-27 T6): the load never settled within the
    # ceiling, so the command runs once and the run is void. No retry: waiting the whole ceiling
    # again would only say the same thing.
    booked_run
    booked_void "the load never settled within the ceiling of $((BOOKED_DEADLINE - BOOKED_T0))s; it ran once and is not retried"
  else
    while :; do
      booked_times; cpu0=$BOOKED_CPU; t0=$SECONDS
      booked_run
      booked_times; cpu1=$BOOKED_CPU; wall=$((SECONDS - t0))
      [ "$RUN_RC" -ne "$BOOKED_KILLED_RC" ] || break
      cores="$(_res_cores)"
      # The run's own share of the load is not a disturbance (review 4 F4): take it off.
      own="$(resources_own_load "$(awk -v a="$cpu0" -v b="$cpu1" 'BEGIN { d = b - a; printf "%.3f\n", (d > 0 ? d : 0) }')" "$wall")"
      [ -n "$own" ] || own=0
      resources_undisturbed "$cores" "$own" && break
      rose="$(_res_load_now)"; line="$(resources_settled_line "$cores")"
      tries=$((tries + 1))
      if [ "$tries" -gt "$BOOKED_RETRIES" ]; then
        booked_void "the load rose above $line during every run (last $rose, about $own of it the run's own); a timing result from this machine now would not mean anything"
        break
      fi
      printf 'void\n' >&2
      printf 'booked: void — the load rose to %s during the run (about %s of it the run'\''s own), above the settled line %s; retrying (%s of %s)\n' \
        "$rose" "$own" "$line" "$tries" "$BOOKED_RETRIES" >&2
      # The retry keeps the admission and settles again under the same ceiling.
      if ! booked_settle; then
        booked_void "the ceiling of $((BOOKED_DEADLINE - BOOKED_T0))s ran out before a retry could start; a timing result from this machine now would not mean anything"
        break
      fi
    done
  fi
  booked_end
fi

booked_stamp "$RUN_RC"
exit "$RUN_RC"
