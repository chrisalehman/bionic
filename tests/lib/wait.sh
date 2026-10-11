# tests/lib/wait.sh — the bounded poll a suite waits on a condition with (wave-33 T15; debt line
# bounded-wait, raised by wave-32's structure critic).
#
#     . "$(dirname "$0")/lib/wait.sh"
#
# WHY ONE HELPER. tests/name-scan.test.sh, tests/slots.test.sh and tests/worktree.test.sh each carried a
# hand-rolled loop that polls until something is ready, beside tests/gate.test.sh's `wait_for`, and each
# spelled its bound its own way (a counter against a literal, a `for` over a seq, a ceiling in hundredths of
# a second). A bound is the one number a flaky suite gets raised at, so it is spelled once here, as a count
# of ticks and the length of a tick, and the product is what the caller reads at the call.
#
# wait_ticks <ticks> <tick-seconds> <command>… — rc 0 as soon as the command succeeds, rc 1 once <ticks>
#     ticks of <tick-seconds> each have gone by without it. The command is tried at once, then after every
#     tick, so it is tried <ticks> + 1 times and the ceiling is <ticks> × <tick-seconds>. The command is
#     run in THIS shell, so a function of the suite is a legal command.
#
# wait_for <seconds> <command>… — wait_ticks at the 0.05 s tick the suites poll at, with the ceiling given
#     in whole seconds. It tries the command <seconds> × 20 times (one fewer sleep than wait_ticks would
#     take), the reading tests/gate.test.sh's own `wait_for` has always had.
wait_ticks() {
  local n="$1" t="$2" i=0
  shift 2
  until "$@"; do
    [ "$i" -lt "$n" ] || return 1
    i=$((i + 1)); sleep "$t"
  done
  return 0
}

wait_for() {
  local i=0 lim=$(( $1 * 20 ))
  shift
  until "$@"; do
    i=$((i + 1)); [ "$i" -lt "$lim" ] || return 1
    sleep 0.05
  done
  return 0
}
