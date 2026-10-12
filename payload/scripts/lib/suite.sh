#!/bin/bash
# payload/scripts/lib/suite.sh — HOW A SUITE RUNS (wave-33 T2; spec D3; REQ-7 AC-7.1).
#
# One plugin-owned primitive for starting a project's suite, so that a suite proved at a landing
# starts in the environment the whole run starts it in, and is green there exactly when it is green
# through the door and in the whole run:
#
#   bionic_suite_exec  [--admit <id>] <tree> <suite> [args...]  runs the suite to its end; its rc
#   bionic_suite_start [--admit <id>] <tree> <suite> [args...]  starts it as a job of its own and
#                                                               sets BIONIC_SUITE_PID; the caller waits
#   bionic_job <command> [args...]                              starts any command as a job of its
#                                                               own; sets BIONIC_JOB_PID
#
# THE SUITE'S ENVIRONMENT, the whole run's (tests/run.sh's worker, wave-30 T9 and wave-28 T12):
#   - its working directory is <tree>, and <suite> is run there as `bash <suite> [args...]`: a path
#     the caller names, relative to the tree or absolute; nothing else about the project is assumed;
#   - BIONIC_GATE_DIR is unset in it: the caller keeps the gate's store for its own ask and end, and
#     a suite that wants a store makes its own fixture;
#   - with `--admit <id>` (the caller holds that admission) BIONIC_GATE_ADMIT is <id> in it, so a
#     nested ask under the suite is placed under the caller's admission; without it, whatever the
#     caller inherited is left as it was. An empty <id> is refused (exit 2), as any empty flag is;
#   - its stdin is /dev/null, as the whole run's xargs and solo drain give it.
#
# INT AND QUIT AT THEIR DEFAULTS. Without job control bash starts a background command with SIGINT
# and SIGQUIT ignored, every process below inherits that, and a shell cannot trap or reset a signal
# ignored at its entry: a suite whose rows trap INT or QUIT, or need a child to die of INT (slots K6),
# went red at the landing, whose runner and suite were two such `&` jobs (R4 §3). So a job is started
# with job control on around its one spawn (`set -m`, the booked.sh precedent): it starts with the
# dispositions the caller has. A caller that itself started with them ignored passes that on; this
# is why each of the landing's two spawns goes through bionic_job, and why one alone was not enough.
# bionic_suite_exec does not need it: a foreground child keeps the caller's dispositions as they are,
# and the caller's terminal interrupt still reaches the suite.
#
# What a job of its own changes: it leads its own process group, so a signal sent to the caller's
# group no longer reaches it directly; a caller that stops it walks its tree by ppid (line.sh
# `_line_kill_tree`) or signals its group.
#
# bash 3.2 (ADR-001).

# THE FORK SPEAKS ON NOTHING (booked.sh, wave-26 T63): under `set -m` the parent and the child each
# put the child in its own group, and under load one call can fail with `child setpgid … Operation not
# permitted` on the stderr held at that moment. So the spawn's stderr is /dev/null, and the job gets
# the caller's real one back (fd 9) before it runs. Job control is left as the caller had it.
bionic_job() {  # <command> [args...] -> BIONIC_JOB_PID
  local had_m=""
  case $- in *m*) had_m=1 ;; esac
  BIONIC_JOB_PID=""
  {
    set -m
    "$@" 2>&9 9>&- &
    BIONIC_JOB_PID=$!
    [ -n "$had_m" ] || set +m
  } 9>&2 2>/dev/null
}

# The suite's own process: the environment above, then the suite in place of this shell.
_bionic_suite_run() {  # <admission | empty> <tree> <suite> [args...]
  local admit="$1" tree="$2" suite="$3"
  shift 3
  cd -- "$tree" || exit 126
  unset BIONIC_GATE_DIR
  [ -z "$admit" ] || export BIONIC_GATE_ADMIT="$admit"
  exec bash "$suite" "$@" < /dev/null
}

# The arguments, read once for both entry points: sets _BIONIC_SUITE_ADMIT and _BIONIC_SUITE_SHIFT
# (how many words the options took); rc 2 with one line on stderr when they cannot be read.
_bionic_suite_args() {  # <caller's name> [--admit <id>] <tree> <suite> ...
  local me="$1"
  shift
  _BIONIC_SUITE_ADMIT=""; _BIONIC_SUITE_SHIFT=0
  if [ "${1:-}" = --admit ]; then
    [ -n "${2:-}" ] || { echo "${me}: --admit needs an admission id, got an empty value" >&2; return 2; }
    _BIONIC_SUITE_ADMIT="$2"; _BIONIC_SUITE_SHIFT=2
    shift 2
  fi
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || { echo "${me}: usage: ${me} [--admit <id>] <tree> <suite> [args...]" >&2; return 2; }
  [ -d "$1" ] || { echo "${me}: no tree at $1" >&2; return 2; }
}

bionic_suite_start() {  # [--admit <id>] <tree> <suite> [args...] -> BIONIC_SUITE_PID
  BIONIC_SUITE_PID=""
  _bionic_suite_args bionic_suite_start "$@" || return 2
  shift "$_BIONIC_SUITE_SHIFT"
  bionic_job _bionic_suite_run "$_BIONIC_SUITE_ADMIT" "$@"
  BIONIC_SUITE_PID="$BIONIC_JOB_PID"
}

bionic_suite_exec() {  # [--admit <id>] <tree> <suite> [args...] -> the suite's rc
  _bionic_suite_args bionic_suite_exec "$@" || return 2
  shift "$_BIONIC_SUITE_SHIFT"
  ( _bionic_suite_run "$_BIONIC_SUITE_ADMIT" "$@" )
}
