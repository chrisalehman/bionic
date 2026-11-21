# tests/lib/maker-stop.sh — a maker that cannot make what it was asked for stops the suite that asked.
#
# A suite takes a maker's path as `R="$(make_repo x)"` and writes through it on the next line. A maker that failed
# prints no path, and then `git -C ""` acts in the repository the suite stands in and `cd ""` stays where it is. The
# take runs in a command substitution, so a maker's own `exit` ends only that child and the suite goes on: a maker
# that fails calls maker_stop, which ends the shell that loaded this file from wherever below it the maker runs.
#
# maker_stop <maker> <why> prints the one line `<maker>: <why>; the suite stops` on stderr, then
#   - sends USR2 to the shell that loaded this file, which traps it as `exit 1`: the suite exits 1 through its own
#     EXIT trap, so its sandbox is still removed and the runner reads a failed suite, not a death by signal;
#   - sends PIPE to every other process under that shell, so a take made inside `( … )`, a second command
#     substitution or a background row runs no line after it either (bash prints no notice for a PIPE death);
#   - and exits 1. It never returns.
# The processes are found by walking each one's parent up to that shell, and are signalled by their own ids: the
# stop never reaches a process group, the runner, or a suite running beside this one.
#
# A row that tests a maker's refusal runs the maker in a child bash that loads the setup: there the child is the
# shell that loaded this file, and the stop ends the child alone.
#
# Loaded once: a second load, from a library the setup also loads or from inside a subshell, keeps the first
# shell as the one to stop, since only that shell holds the trap.
if [ -z "${MAKER_STOP_SHELL:-}" ] || ! declare -F maker_stop >/dev/null 2>&1; then
  # The loading shell's own id: bash 3.2 has no BASHPID, and $$ names the top shell even in a subshell.
  MAKER_STOP_SHELL="$(exec /bin/sh -c 'echo "$PPID"')"
  trap 'exit 1' USR2
  maker_stop() {  # <maker> <why>
    printf '%s: %s; the suite stops\n' "$1" "$2" >&2
    local me pids
    me="$(exec /bin/sh -c 'echo "$PPID"')"
    # Every process whose parents lead up to the loading shell, leaving out that shell and this one with what it
    # runs: ps, awk and kill below are this process's own children.
    pids="$(ps -A -o pid= -o ppid= 2>/dev/null | awk -v top="$MAKER_STOP_SHELL" -v me="$me" '
      { up[$1] = $2 }
      END {
        for (p in up) {
          if (p == top || p == me || p + 0 <= 1) continue
          q = p
          while (q in up && q != top && q != me && q + 0 > 1) q = up[q]
          if (q == top) print p
        }
      }')"
    kill -USR2 "$MAKER_STOP_SHELL" 2>/dev/null
    # shellcheck disable=SC2086
    [ -z "$pids" ] || kill -PIPE $pids 2>/dev/null
    exit 1
  }
fi
