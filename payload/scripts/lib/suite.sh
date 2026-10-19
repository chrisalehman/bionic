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
#   bionic_command_start [--admit <id>] <tree> <command>        starts a Lands-on command (`bash -c`)
#                                                               the same way; sets BIONIC_SUITE_PID
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

# WHAT A SUITE IS CALLED (wave-35 T6; the debt line lands-on-path-grammar): the one grammar of a suite
# named in a `Lands-on:` line (brief.sh's lift) or a roster's `lands_on=` / `suites_allowed=` (line.sh
# `_line_suites`). An awk function, pasted in front of each program that reads one:
# `suite_name(t)` is "" for a token that is no suite, else its canonical spelling. A name is
# `[A-Za-z0-9_][A-Za-z0-9_-]*`, with or without `.test.sh`, which it then carries; a path keeps its
# directories (wave-34 T27), each a plain name, never `..` and never absolute, and a leading `./` is
# dropped while another `/` follows. So `run.sh`, `a.b` and `../x.test.sh` are no suite.
BIONIC_SUITE_NAME_AWK='
function suite_name(t,   n, P, i) {
  while (t ~ /^\.\/.*\//) t = substr(t, 3)
  n = split(t, P, "/")
  for (i = 1; i < n; i++) if (P[i] !~ /^[A-Za-z0-9_.-]+$/ || P[i] == ".." || (P[i] == "." && i > 1)) return ""
  if (P[n] !~ /^[A-Za-z0-9_][A-Za-z0-9_-]*(\.test\.sh)?$/) return ""
  sub(/\.test\.sh$/, "", t)
  return t ".test.sh"
}
# A COMMAND ON LANDS-ON (wave-39 T20; D20, AC-14.3). `Lands-on:` may name, in backticks, a command its brief declares
# under `Re-executes:` (the runs of a jest or Playwright row), and ready runs it and judges it by its exit code. Every
# reader of a lands_on= value splits it on commas and blanks, the roster folds a `|` to a blank, and several cut a
# suite to its file name with `${s##*/}`; so the command is written as ONE entry those readers keep whole: backticks
# around its text with `%`, a blank, a tab, `,`, `|`, `/`, `*`, `?` and `[` percent-encoded (`%` first, so the pair
# is a bijection, as roster.sh `roster_pipe_escape` holds it; no glob character is left for an unquoted expansion).
# `lands_cmd(c)` writes it; `lands_cmd_entry(t)` is 1 for a token that is one. `bionic_lands_cmd` below reads it back.
function lands_cmd(c,   o, i, ch) {
  o = ""
  for (i = 1; i <= length(c); i++) {
    ch = substr(c, i, 1)
    if (ch == "%") ch = "%25"; else if (ch == " ") ch = "%20"; else if (ch == "\t") ch = "%09"
    else if (ch == ",") ch = "%2C"; else if (ch == "|") ch = "%7C"; else if (ch == "/") ch = "%2F"
    else if (ch == "*") ch = "%2A"; else if (ch == "?") ch = "%3F"; else if (ch == "[") ch = "%5B"
    o = o ch
  }
  return "`" o "`"
}
function lands_cmd_entry(t) { return (t ~ /^`[^` \t,|\/*?[]+`$/) }
'

# bionic_lands_cmd <lands_on entry> -> the command it names, as its brief declared it; 1 when the entry is no command.
bionic_lands_cmd() {
  local v="${1:-}" sl=/   # `/` through a variable: bash 3.2 keeps the backslash of a `\/` replacement
  case "$v" in '`'?*'`') ;; *) return 1 ;; esac
  v="${v#\`}"; v="${v%\`}"
  case "$v" in *'`'*|*[[:space:],\|/*?[]*) return 1 ;; esac
  v="${v//\%20/ }"; v="${v//\%09/	}"; v="${v//\%2C/,}"; v="${v//\%7C/|}"; v="${v//\%2F/$sl}"
  v="${v//\%2A/*}"; v="${v//\%3F/?}"; v="${v//\%5B/[}"
  printf '%s' "${v//\%25/%}"
}
# bionic_lands_show <lands_on value> -> the value as a brief writes it: each command decoded in backticks, `, `-joined.
bionic_lands_show() {
  local e c out=""
  for e in $(printf '%s' "${1:-}" | tr ',' ' '); do
    if c="$(bionic_lands_cmd "$e")"; then e="\`${c}\`"; fi
    out="${out:+${out}, }${e}"
  done
  printf '%s' "$out"
}

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
_bionic_suite_env() {  # <admission | empty> <tree>
  cd -- "$2" || exit 126
  unset BIONIC_GATE_DIR
  [ -z "$1" ] || export BIONIC_GATE_ADMIT="$1"
}
_bionic_suite_run() {  # <admission | empty> <tree> <suite> [args...]
  local suite="$3"
  _bionic_suite_env "$1" "$2"
  shift 3
  exec bash "$suite" "$@" < /dev/null
}
# A LANDS-ON COMMAND'S OWN PROCESS (wave-39 T20; D20): the same environment, then the command as a shell line in place
# of this shell, `bash -c <command>`, as the writer typed it under Re-executes:.
_bionic_command_run() {  # <admission | empty> <tree> <command>
  _bionic_suite_env "$1" "$2"
  exec bash -c "$3" < /dev/null
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

bionic_command_start() {  # [--admit <id>] <tree> <command> -> BIONIC_SUITE_PID
  BIONIC_SUITE_PID=""
  _bionic_suite_args bionic_command_start "$@" || return 2
  shift "$_BIONIC_SUITE_SHIFT"
  bionic_job _bionic_command_run "$_BIONIC_SUITE_ADMIT" "$1" "$2"
  BIONIC_SUITE_PID="$BIONIC_JOB_PID"
}

bionic_suite_exec() {  # [--admit <id>] <tree> <suite> [args...] -> the suite's rc
  _bionic_suite_args bionic_suite_exec "$@" || return 2
  shift "$_BIONIC_SUITE_SHIFT"
  ( _bionic_suite_run "$_BIONIC_SUITE_ADMIT" "$@" )
}
