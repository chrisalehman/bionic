#!/bin/bash
# booked.sh — RUN A COMMAND THE GATE ADMITTED: stamp, ask, run, end, record rc
# (epic-23 wave-26-never-idle, D8, D14; REQ-6 AC-6.3, AC-6.4, REQ-4 AC-4.1; the gate from
# wave-28-finished-work-lands T12, D10, D13; REQ-2 AC-2.6, AC-2.12, AC-2.13).
#
#   bash <plugin-root>/scripts/booked.sh [--agent <name>] [--kill-after <seconds>]
#                                        [--max-wait <seconds>] [--shell <path>]
#                                        [--stamp-dir <dir>] [--suites <names>] [--runner]
#                                        [--detach]
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
# as reading the tree. A command the gate did not admit in time (75) and a shim signalled while
# it waited (128+n) stamp the code they ended on, with the same `suites=`, though nothing ran: otherwise "suite a green, suite b never
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
# --unplaced: THE WALL CANNOT SAY WHICH TREE THE RUN IS IN (wave-35 T6; D14, design ledger Δ7). A `cd`
# ahead of the suite that the wall cannot follow (a variable, `pushd`, a subshell, `cd` behind `||`)
# leaves the run's tree unknown, and the shim's own directory is a guess: in 1.17.0 a red run in a
# writer's dirty tree was stamped there as a clean green at the main head. So the shim writes NO
# stamp, at any end, and says on the run's own output (stderr, the detached run's log) that the run
# did not count. Nothing reads a marked stamp: an unplaced run leaves nothing to read.
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
# guard. So a command runs UNADMITTED at once, with one stderr line that names the store and
# says so.
#
# NO WHOLE-MACHINE RUN (wave-35 T2; D11, AC-2.1). The shim asks `work` or nothing: `--quiet` and
# `BIONIC_QUIET=1`, its whole-machine timing check with a settle wait, a void and two retries, are
# gone. `--quiet` is an option the shim does not know (usage, 2), and nothing reads BIONIC_QUIET.
# A command that passes or fails by the clock is a defect in the command, not a reading to excuse.
#
# --kill-after <s>: once MORE than <s> seconds have passed since the shim started, the command's
# whole process group is killed, one line says it is over the short limit and belongs in a
# subagent, and the shim exits 124. The clock is `$SECONDS`, whole seconds, so the kill lands
# up to a second past <s> and never before it (review 12 F4, A-T50.3). THE LIMIT COVERS THE WAIT
# AT THE GATE (T44, review 8 F2): the ask's --within is the limit and the kill is timed from the
# shim's start, so the call ends inside the harness's own timeout whatever the machine is doing.
# A command the gate did not admit within it ends 75, not 124 (AC-2.6): it ran nothing and keeps
# its number.
#
# --max-wait <s>: THE CALL'S OWN BOUND ON THE WAIT (wave-27 T6, critic 3 S2). The wall passes the
# Bash call's staged timeout, in seconds, less ten; it is the ask's --within, so a wait at the
# gate ends inside the call instead of outliving it into the background. It kills nothing: an admitted command runs as
# long as it runs. The wall leaves it out beside --kill-after, whose limit already bounds the wait.
#
# --detach: A RUN IS AN OBJECT, MADE HERE (wave-30 T8; D6, Δ5, Δ5a; REQ-3). The shim's whole tail,
# ask → run → end → stamp, runs in a session of its own, so nothing that kills the calling Bash call
# (a /clear, a stopped agent, the caller's process group taken down by SIGKILL) takes the run with
# it. The caller claims the run's log, starts the detached side, checks it is alive (or already
# ended) and prints ONE line, then WAITS on it (T12; A-orch-7, "detach means detach AND wait"):
#
#   booked: started pid=<pid> log=<path> run=<id>
#   booked: attached pid=<pid> log=<path> run=<id>     (a live run of the same id, tree and command)
#   booked: progress <UTC> <suite> <rc|§section>       (stderr, each time the run's last progress line changes)
#   booked: LOST run=<id> last-written=<UTC>           (stderr, the pid is dead and the run wrote no end)
#
# THE WAIT polls the log every BIONIC_RUN_POLL seconds (1 unless set; a fraction is allowed), copies
# each new WHOLE line of it to stdout, and exits with the run's code once `<log>.rc` holds it (the
# log's last line is then `rc=<n>`, which it does not copy): so a caller left alone keeps the foreground contract (the command's
# output, the command's own code), and the only difference is that killing the caller no longer
# kills the run. ATTACH: before claiming a log, the caller looks for a LIVE run of the same id (the
# id and every `-<n>` attempt) whose `<log>.key` (the tree and the command, written by the caller
# that started it) is its own; it attaches to that run, printing the `attached` line, and starts
# nothing. A run whose pid is alive is "live" only while that pid is still this run's detached shim
# (`ps` names booked.sh and its --run-log), so a recycled pid is never waited on. LOST is never a
# timeout: a dead pid with no `<log>.rc` is reported with the time the log was last written, and the
# caller exits 70. `session-poker.sh wait <name>` is the same wait, by name, after the caller is gone.
#
# THE LOG is `<runs>/<id>.log`, `<runs>` being the project's
# `.bionic/tmp/runs` (the project is the checkout git's common dir belongs to, so a row tree's run
# logs land in the main checkout's state, never in the tree; with no `.bionic` there,
# `${TMPDIR:-/tmp}/bionic-runs`). THE ID is `<agent>-<suites>`: --agent (or `main`), then --suites
# with `,` written `+` and `?` written `_` (or `cmd` when none is named), every other character
# outside letters, digits, `.`, `_`, `+` and `-` written `_`. A SECOND ATTEMPT NEVER TRUNCATES THE
# FIRST: the log is claimed with noclobber, and a taken name moves on to `<id>-2.log`, `<id>-3.log`
# and so on. Beside the log, written by the caller that claimed it:
#   <log>.key           the caller's tree (`pwd -P`) and the command, the attach's comparison;
# and by the detached side:
#   <log>.pid           its pid, written before anything else runs (the place, the stamp and the
#                       roster record are all that pid's);
#   <log>.rc            the run's code, written last, after the log's rc line: the end a waiter
#                       reads (the log's last line alone is not, since a command may print `rc=`);
#   <log>.progress.tsv  the run's progress file (Δ5a): the detached side exports
#                       BIONIC_TEST_PROGRESS=<it>, so tests/run.sh appends a line per suite as it
#                       lands and tests/lib/assert.sh `section()` one per section as it opens.
# The log holds everything the run printed, the shim's own lines included, and its LAST line is
# `rc=<n>`, the run's exit code, written on every exit the detached side takes (a usage or start
# failure aside); a log with no `rc=` line and a dead pid is a run that was LOST. THE RUN RECORD:
# with --agent naming a row of this session's roster (`<project>/.bionic/tmp/roster-
# <CLAUDE_CODE_SESSION_ID>.state`), that row gets `run_pid= run_log= run_head= run_cmd=
# run_started_at=` when the run starts and `run_rc= run_ended_at=` when it ends
# (lib/roster.sh `roster_mark_run`); with no such row the run still runs, recorded by its log alone.
# THE PLACE is the detached side's: it asks the gate itself, so the request's holder is its pid and
# the place stays booked until it ends the request, whatever became of the caller. --kill-after is
# the run's own ceiling, as before. --max-wait does not reach a detached run: it was the Bash call's
# bound on a wait inside that call, and a detached run's wait is inside no call. THE CEILING (wave-31
# T12; D10): the detached side asks the gate with --within BIONIC_SETTLE_MAX_WAIT (1200 s unless set;
# the name is older than the ceiling, from the retired --quiet settle, and kept as the knob callers set)
# when nothing smaller bounds it, so a run the gate has not admitted by then ends through the
# not-admitted path below: exit 75, one line naming the wait and the command to run again in the log,
# `rc=75` there, `75` in `<log>.rc`, `run_rc=75` on the roster row; the caller copies the line and
# exits 75, and `session-poker.sh wait` prints it. The detached side is started by `perl -MPOSIX` (fork, `POSIX::setsid`, exec):
# macOS ships no `setsid`, and perl is the one tool a stock machine has for it. No perl, or a
# detached side that is neither alive nor ended once its pid file is read, exits 71 with one line.
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
# Everything above is the FOREGROUND shim's. Under --detach the caller has handed the run off before
# any signal can matter: the detached side is in a session of its own, with no terminal and nobody's
# process group, so the caller's death (its group SIGKILLed, a HUP, a /clear) reaches neither it nor
# its command; the detached side's own traps still pass a signal sent to IT on to the command's group,
# end the request, stamp and write the rc line. Stopping a detached run on purpose signals its pid
# (T12's verb); a SIGKILL to the detached side itself runs no trap and leaves the run LOST.
#
# EXIT CODES. The command's own, except:
#   (--detach: the caller exits with the run's own code, the log's last line `rc=<n>`)
#   2    usage: no `--`, no command, more than one word after `--` (with or without
#        --kill-after), a bad --kill-after or --max-wait, an empty --agent, or an option the
#        shim does not know (`--quiet` among them, since wave-35 T2)
#   71   --detach: the detached run could not be started (no perl, no log, or a detached side
#        neither alive nor ended); one line says which
#   70   --detach: the run was LOST — its pid died and it wrote no `<log>.rc` (never a timeout)
#   75   the gate did not admit the command within the call's limit (the line says to run it
#        again; the command never ran)
#   124  --kill-after fired during the run
#   128+n  the shim itself was stopped by signal n (its command is killed with it)
# 75 is EX_TEMPFAIL, "try again later", which is what a wait that ran out means.
# A command can exit 75 or 124 itself; the shim's own always comes after a `booked:` or
# `gate:` line on stderr, and the stamp of either is never proof of a green run. The stamp's
# `rc=` is the exit code.
#
# THE WAITS. The gate's wait polls every BIONIC_GATE_POLL seconds (lib/gate.sh) and prints one
# line when it starts. The store follows BIONIC_GATE_DIR.
#
# BASH 3.2.
#
# [WALL: tests/slots.test.sh]
# [WALL: tests/gate.test.sh]

BOOKED_SELF_DIR="$(cd "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd -P)"
case "${BASH_SOURCE[0]}" in */*) : ;; *) BOOKED_SELF_DIR="$(pwd -P)" ;; esac
# shellcheck disable=SC1091
. "$BOOKED_SELF_DIR/lib/roots.sh" 2>/dev/null
# shellcheck disable=SC1091
. "$BOOKED_SELF_DIR/lib/resources.sh" || exit 2
# gate.sh brings the liveness rule (slots.sh) with it.
# shellcheck disable=SC1091
. "$BOOKED_SELF_DIR/lib/gate.sh" || exit 2

BOOKED_WAITED_RC=75
BOOKED_KILLED_RC=124

booked_usage() {
  printf 'booked: usage: bash booked.sh [--agent <name>] [--kill-after <seconds>] [--max-wait <seconds>] [--shell <path>] [--stamp-dir <dir>] [--suites <names>] [--runner] [--unplaced] [--detach] -- <command>\n' >&2
  exit 2
}

kill_after=""; max_wait=""; sep=0; run_shell=""; stamp_dir=""; suites=""; agent=""; runner=0; unplaced=0
detach=0; run_log=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent)        [ "$#" -ge 2 ] && [ -n "$2" ] || booked_usage; agent="$2"; shift 2 ;;
    --agent=*)      agent="${1#--agent=}"; [ -n "$agent" ] || booked_usage; shift ;;
    --kill-after)   [ "$#" -ge 2 ] || booked_usage; kill_after="$2"; shift 2 ;;
    --kill-after=*) kill_after="${1#--kill-after=}"; shift ;;
    --max-wait)     [ "$#" -ge 2 ] || booked_usage; max_wait="$2"; shift 2 ;;
    --max-wait=*)   max_wait="${1#--max-wait=}"; shift ;;
    --shell)        [ "$#" -ge 2 ] && [ -n "$2" ] || booked_usage; run_shell="$2"; shift 2 ;;
    --shell=*)      run_shell="${1#--shell=}"; [ -n "$run_shell" ] || booked_usage; shift ;;
    --stamp-dir)    [ "$#" -ge 2 ] && [ -n "$2" ] || booked_usage; stamp_dir="$2"; shift 2 ;;
    --stamp-dir=*)  stamp_dir="${1#--stamp-dir=}"; [ -n "$stamp_dir" ] || booked_usage; shift ;;
    --suites)       [ "$#" -ge 2 ] && [ -n "$2" ] || booked_usage; suites="$2"; shift 2 ;;
    --suites=*)     suites="${1#--suites=}"; [ -n "$suites" ] || booked_usage; shift ;;
    --runner)       runner=1; shift ;;
    --unplaced)     unplaced=1; shift ;;
    --detach)       detach=1; shift ;;
    # THE DETACHED SIDE (internal): the caller of --detach starts this shim again with the log it
    # claimed; nobody types it.
    --run-log)      [ "$#" -ge 2 ] && [ -n "$2" ] || booked_usage; run_log="$2"; shift 2 ;;
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
  if [ "$unplaced" -eq 1 ]; then
    printf 'bionic: not counted — the wall could not tell which tree this run ran in, so it left no stamp and proves nothing; for a run that counts, open the command with a literal cd <tree> || exit 1;\n' >&2
    return 0
  fi
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
trap 'rm -f ${BOOKED_IDF:+"$BOOKED_IDF"}' EXIT

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

# booked_cd_dir — where the command's first suite segment runs, or nothing: the one placement reader's
# answer (wave-36 T25; D11, AC-5.1), `cmd_place "$cmd" "$PWD" suite` (lib/placement.sh), the question
# the wall asks for the stamp's --stamp-dir, so the gate names the tree the stamp names. A `moving`
# answer, any other, or a reader that cannot load gives nothing, and the ask names where the shim
# stands. Until T25 this read a plain word after a `cd` opening the text, and nothing else.
booked_cd_dir() {
  local d
  [ -r "$BOOKED_SELF_DIR/lib/placement.sh" ] || return 0
  # shellcheck source=/dev/null
  . "$BOOKED_SELF_DIR/lib/placement.sh" 2>/dev/null || return 0
  d="$(cmd_place "$cmd" "$PWD" suite 2>/dev/null)" || return 0
  printf '%s' "$d"
}
BOOKED_ASK_DIR="$stamp_dir"
[ -n "$BOOKED_ASK_DIR" ] || BOOKED_ASK_DIR="$(booked_cd_dir)"

# booked_ask <work> — asks the gate in this shell (never in `$( )`: a signal must reach
# the trap while it waits, and the holder is this process). Sets BOOKED_ID and BOOKED_OWN and
# exports BIONIC_GATE_ADMIT; ends the shim itself on a wait that ran out (75). A run on a store it
# cannot write goes on unadmitted.
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
      printf 'booked: cannot write the gate'\''s store %s — this command runs unadmitted, beside whatever else runs; fix: make it writable, or point BIONIC_GATE_DIR at a directory you can write\n' \
        "$(gate_dir)" >&2 ;;
  esac
}

# ── --detach: the caller hands the run off (wave-30 T8; D6) ──────────────────
# booked_project_root — the checkout git's common dir belongs to, from the tree the ask names: a row
# tree's project is the main checkout. Nothing outside git.
booked_project_root() {
  local d="${BOOKED_ASK_DIR:-.}" c
  c="$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
  case "$c" in
    */.git) printf '%s' "${c%/.git}" ;;
    *) git -C "$d" rev-parse --show-toplevel 2>/dev/null ;;
  esac
}

booked_runs_dir() {  # where a detached run's log goes (the header's THE LOG)
  local r
  r="$(booked_project_root)"
  if [ -n "$r" ] && [ -d "$r/.bionic" ]; then
    printf '%s/.bionic/tmp/runs' "$r"
  else
    printf '%s/bionic-runs' "${TMPDIR:-/tmp}"
  fi
}

booked_run_id() {  # <agent>-<suites>, one plain word (the header's THE ID)
  local s="${suites:-cmd}" w
  s="${s//,/+}"; s="${s//\?/_}"
  w="${agent:-main}-$s"
  w="${w//[!A-Za-z0-9._+-]/_}"
  printf '%s' "${w:0:120}"
}

# booked_claim_log <dir> <id> — sets BOOKED_CLAIM to a log no attempt has used: <id>.log, else
# <id>-2.log, -3.log, …, each claimed with noclobber, so two starts never share one and a second
# never truncates the first. rc 1 when none can be made.
BOOKED_CLAIM=""
booked_claim_log() {
  local n=1 p
  while [ "$n" -le 999 ]; do
    if [ "$n" -eq 1 ]; then p="$1/$2.log"; else p="$1/$2-$n.log"; fi
    if ( set -C; : > "$p" ) 2>/dev/null; then BOOKED_CLAIM="$p"; return 0; fi
    [ -e "$p" ] || return 1
    n=$((n + 1))
  done
  return 1
}

# booked_live <pid> <log> — rc 0 when <pid> is alive AND is still the detached shim of <log>: `ps`
# names booked.sh with that --run-log. A pid the system gave to another process is not this run.
booked_live() {
  local c
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$1" 2>/dev/null || return 1
  c="$(ps -ww -o command= -p "$1" 2>/dev/null)" || return 1
  case "$c" in *booked.sh*"--run-log $2"*) return 0 ;; esac
  return 1
}

# booked_rc_of <log> — the run's code, from `<log>.rc`, which only the detached side writes, after
# the log's own rc line; rc 1 while there is none. Never from the log's last line alone: a command
# whose own last output is `rc=<n>` (a door command's `echo "rc=$rc"`) would read as ended.
booked_rc_of() {
  local l=""
  { read -r l < "$1.rc"; } 2>/dev/null
  case "$l" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$l"
}

booked_key() {  # the attach's comparison: this caller's tree and its command
  printf '%s\n%s' "$(pwd -P)" "$cmd"
}

# booked_find_live <dir> <id> — sets BOOKED_CLAIM and BOOKED_LIVE_PID to the newest attempt of <id>
# whose pid is this run's and alive, which has not ended (no `<log>.rc`), and whose key is this caller's; rc 1
# when none is.
BOOKED_LIVE_PID=""
booked_find_live() {
  local n=1 p pid key found="" fpid=""
  key="$(booked_key)"
  while [ "$n" -le 999 ]; do
    if [ "$n" -eq 1 ]; then p="$1/$2.log"; else p="$1/$2-$n.log"; fi
    [ -e "$p" ] || break
    pid=""; { read -r pid < "$p.pid"; } 2>/dev/null
    if [ -n "$pid" ] && ! booked_rc_of "$p" >/dev/null && booked_live "$pid" "$p" \
       && [ "$(cat "$p.key" 2>/dev/null)" = "$key" ]; then
      found="$p"; fpid="$pid"
    fi
    n=$((n + 1))
  done
  [ -n "$found" ] || return 1
  BOOKED_CLAIM="$found"; BOOKED_LIVE_PID="$fpid"
}

booked_mtime_utc() {  # <file> — its last write, UTC ISO-8601
  local m
  m="$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null)"
  [ -n "$m" ] || { printf 'unknown'; return 0; }
  date -u -r "$m" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$m" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf 'unknown'
}

# booked_follow <log> <pid> — THE WAIT: every BIONIC_RUN_POLL seconds, the log's new whole lines to
# stdout and the run's last progress line to stderr when it changed; exits with the run's code from
# `<log>.rc` (the log's rc line is not printed), or 70 when the pid is dead and no end came (LOST,
# never a timeout).
booked_follow() {
  local log="$1" pid="$2" poll="${BIONIC_RUN_POLL:-1}" done_n=0 total rc prog last_prog="" id dead=0
  case "$poll" in ''|*[!0-9.]*|.|*.*.*) poll=1 ;; esac
  id="${log##*/}"; id="${id%.log}"
  while :; do
    rc="$(booked_rc_of "$log")" && {
      total="$(wc -l < "$log" | tr -d ' ')"
      [ "$((total - 1))" -le "$done_n" ] || sed -n "$((done_n + 1)),$((total - 1))p" "$log"
      exit "$rc"
    }
    total="$(wc -l < "$log" 2>/dev/null | tr -d ' ')"
    case "$total" in ''|*[!0-9]*) total=$done_n ;; esac
    # A LAST LINE `rc=<n>` IS HELD BACK until a line follows it or the end is known: it may be the
    # shim's own rc line, written just before `<log>.rc`, which is never copied.
    if [ "$total" -gt "$done_n" ]; then
      prog="$(sed -n "${total}p" "$log")"
      case "$prog" in rc=[0-9]*) case "${prog#rc=}" in *[!0-9]*) : ;; *) total=$((total - 1)) ;; esac ;; esac
    fi
    if [ "$total" -gt "$done_n" ]; then sed -n "$((done_n + 1)),${total}p" "$log"; done_n=$total; fi
    prog="$(tail -n 1 "$log.progress.tsv" 2>/dev/null)"
    if [ -n "$prog" ] && [ "$prog" != "$last_prog" ]; then
      printf 'booked: progress %s\n' "${prog//$'\t'/ }" >&2
      last_prog="$prog"
    fi
    # THE PID DIED: one more read of `<log>.rc` (the run may have ended between the two reads),
    # then LOST.
    if [ "$dead" -eq 1 ]; then
      total="$(wc -l < "$log" 2>/dev/null | tr -d ' ')"
      case "$total" in ''|*[!0-9]*) total=$done_n ;; esac
      [ "$total" -le "$done_n" ] || sed -n "$((done_n + 1)),${total}p" "$log"
      printf 'booked: LOST run=%s last-written=%s\n' "$id" "$(booked_mtime_utc "$log")" >&2
      exit 70
    fi
    booked_live "$pid" "$log" || { dead=1; continue; }
    sleep "$poll"
  done
}

booked_detach() {  # the caller's whole part: attach or claim and start, report, then wait
  local runs child i=0 pid="" id
  # The caller stamps nothing and ends nothing: a signal here leaves no run behind to speak for.
  trap - HUP INT QUIT TERM
  if ! command -v perl >/dev/null 2>&1; then
    printf 'booked: --detach needs perl (POSIX::setsid) and none is on PATH — the run was not started\n' >&2
    exit 71
  fi
  runs="$(booked_runs_dir)"
  mkdir -p "$runs" 2>/dev/null
  # ATTACH, NEVER A SECOND START: a live run of this id, tree and command is waited on as it stands.
  if booked_find_live "$runs" "$(booked_run_id)"; then
    id="${BOOKED_CLAIM##*/}"; id="${id%.log}"
    printf 'booked: attached pid=%s log=%s run=%s\n' "$BOOKED_LIVE_PID" "$BOOKED_CLAIM" "$id"
    booked_follow "$BOOKED_CLAIM" "$BOOKED_LIVE_PID"
  fi
  if ! booked_claim_log "$runs" "$(booked_run_id)"; then
    printf 'booked: cannot claim a run log under %s — the run was not started\n' "$runs" >&2
    exit 71
  fi
  booked_key > "$BOOKED_CLAIM.key" 2>/dev/null
  # THE DETACHED SIDE is this shim again, with the log it is to write and the caller's options but
  # --max-wait (a detached run's wait is inside no call; see the header).
  child=(bash "$BOOKED_SELF_DIR/booked.sh" --run-log "$BOOKED_CLAIM")
  [ -z "$agent" ] || child+=(--agent "$agent")
  [ -z "$kill_after" ] || child+=(--kill-after "$kill_after")
  [ -z "$run_shell" ] || child+=(--shell "$run_shell")
  [ -z "$stamp_dir" ] || child+=(--stamp-dir "$stamp_dir")
  [ -z "$suites" ] || child+=(--suites "$suites")
  [ "$runner" -eq 0 ] || child+=(--runner)
  [ "$unplaced" -eq 0 ] || child+=(--unplaced)
  child+=(-- "$cmd")
  # fork; the parent returns at once; the child leaves the caller's session (setsid), takes the log
  # as stdout and stderr and /dev/null as stdin, closes every other descriptor it inherited (one held
  # open would keep the harness waiting on the call), writes its pid, and becomes the shim. The pid
  # file's handle is declared before it is opened, and the pid is checked below before any start is
  # reported: the two silent failures of the prototype (ideas/runs-outlive-a-rollover.md).
  # shellcheck disable=SC2016  # perl's own variables, not the shell's
  perl -MPOSIX -e '
    my $log = shift @ARGV;
    my $pid = fork;
    exit 1 unless defined $pid;
    exit 0 if $pid;
    POSIX::setsid() or POSIX::_exit(3);
    open(STDIN, "<", "/dev/null") or POSIX::_exit(4);
    open(STDOUT, ">>", $log) or POSIX::_exit(4);
    open(STDERR, ">&", \*STDOUT) or POSIX::_exit(4);
    POSIX::close($_) for 3 .. 255;
    my $p;
    open($p, ">", "$log.pid") or POSIX::_exit(5);
    print $p "$$\n";
    close($p);
    exec { $ARGV[0] } @ARGV;
    POSIX::_exit(6);
  ' "$BOOKED_CLAIM" "${child[@]}" < /dev/null > /dev/null 2>&1
  while [ "$i" -lt 100 ]; do
    pid=""
    { read -r pid < "$BOOKED_CLAIM.pid"; } 2>/dev/null
    case "$pid" in ''|*[!0-9]*) pid="" ;; *) break ;; esac
    i=$((i + 1)); sleep 0.1
  done
  if [ -z "$pid" ] || { ! kill -0 "$pid" 2>/dev/null && ! booked_rc_of "$BOOKED_CLAIM" >/dev/null; }; then
    printf 'booked: the detached run did not start (pid %s) — see %s\n' "${pid:-none}" "$BOOKED_CLAIM" >&2
    exit 71
  fi
  id="${BOOKED_CLAIM##*/}"; id="${id%.log}"
  printf 'booked: started pid=%s log=%s run=%s\n' "$pid" "$BOOKED_CLAIM" "$id"
  booked_follow "$BOOKED_CLAIM" "$pid"
}

# ── the detached side's own acts (wave-30 T8): the progress file, the run record, the rc line ──
BOOKED_ROSTER=""
booked_run_open() {  # at the start of the tail, in the detached side
  local r sid="${CLAUDE_CODE_SESSION_ID:-}"
  export BIONIC_TEST_PROGRESS="$run_log.progress.tsv"
  : >> "$BIONIC_TEST_PROGRESS" 2>/dev/null
  # THE RC LINE IS THE LOG'S LAST, ON EVERY EXIT: the exit trap takes over the temp-file cleanup.
  trap 'booked_run_close $?' EXIT
  [ -n "$agent" ] || return 0
  case "$sid" in ''|*[!A-Za-z0-9_-]*) return 0 ;; esac
  r="$(booked_project_root)"
  [ -n "$r" ] || return 0
  BOOKED_ROSTER="$r/.bionic/tmp/roster-$sid.state"
  if [ ! -f "$BOOKED_ROSTER" ] || [ -L "$BOOKED_ROSTER" ]; then BOOKED_ROSTER=""; return 0; fi
  # shellcheck disable=SC1091
  . "$BOOKED_SELF_DIR/lib/roster.sh" 2>/dev/null || { BOOKED_ROSTER=""; return 0; }
  roster_mark_run "$BOOKED_ROSTER" "$agent" "$run_log" "run_pid=$$" "run_head=$stamp_head" \
    "run_cmd=$(booked_one_line "$cmd" 120)" "run_started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" || BOOKED_ROSTER=""
}

booked_run_close() {  # <rc> — the exit trap of the detached side
  rm -f ${BOOKED_IDF:+"$BOOKED_IDF"}
  if [ -n "$BOOKED_ROSTER" ]; then
    roster_mark_run "$BOOKED_ROSTER" "$agent" "$run_log" "run_rc=$1" \
      "run_ended_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" 2>/dev/null
  fi
  # THE RC LINE IS A LINE OF ITS OWN: a command whose output ends without a newline would glue it.
  [ -z "$(tail -c 1 "$run_log" 2>/dev/null)" ] || printf '\n' >> "$run_log"
  printf 'rc=%s\n' "$1" >> "$run_log"
  # THE END, FOR A READER: `<log>.rc`, written after the log's rc line and by nothing else, so a
  # waiter never mistakes a command's own `rc=<n>` output for the run's end.
  printf '%s\n' "$1" > "$run_log.rc"
}

# ── main ─────────────────────────────────────────────────────────────────────
[ "$detach" -eq 0 ] || [ -n "$run_log" ] || booked_detach
[ -z "$run_log" ] || booked_run_open
BOOKED_T0=$SECONDS
# THE CALL'S LIMIT: the smaller of --kill-after and --max-wait; the ask's --within. With neither,
# the gate waits until it admits; a detached run's ask is bounded by BIONIC_SETTLE_MAX_WAIT.
BOOKED_WITHIN="$kill_after"
if [ -n "$max_wait" ] && { [ -z "$BOOKED_WITHIN" ] || [ "$max_wait" -lt "$BOOKED_WITHIN" ]; }; then
  BOOKED_WITHIN="$max_wait"
fi
# THE DETACHED SIDE'S CEILING (T12; D10): its wait is inside no call, so with no smaller limit the ask
# is bounded by BIONIC_SETTLE_MAX_WAIT (1200 s unless set), and a run not admitted inside it ends 75
# (booked_not_admitted).
case "${BIONIC_SETTLE_MAX_WAIT:-}" in ''|*[!0-9]*) BOOKED_ASK_MAX=1200 ;; *) BOOKED_ASK_MAX=$BIONIC_SETTLE_MAX_WAIT ;; esac
[ -z "$run_log" ] || [ -n "$BOOKED_WITHIN" ] || BOOKED_WITHIN="$BOOKED_ASK_MAX"
# THE COMMAND KEY: the one suite file --suites names, else the command's first 60 characters.
case "$suites" in
  ''|*,*|*'?'*) BOOKED_KEY="$(booked_one_line "$cmd" 60)" ;;
  *) BOOKED_KEY="${suites//[!A-Za-z0-9._+-]/?}" ;;
esac
# The sample's cadence, in the run loop's 0.2 s ticks: the gate's own poll, at least one tick.
BOOKED_SAMPLE_TICKS="$(awk -v p="${BIONIC_GATE_POLL:-2}" 'BEGIN { t = int(p / 0.2 + 0.5); print (t >= 1 ? t : 1) }' 2>/dev/null)"
case "$BOOKED_SAMPLE_TICKS" in ''|*[!0-9]*|0) BOOKED_SAMPLE_TICKS=10 ;; esac

# THE RUNNER HOLDS NOTHING (D13): each of its suites asks for itself.
if [ "$suites" != run.sh ] && [ "$runner" -eq 0 ]; then
  booked_ask work
fi
booked_run
booked_end

booked_stamp "$RUN_RC"
exit "$RUN_RC"
