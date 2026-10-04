#!/bin/bash
# tests/slots.test.sh — payload/scripts/lib/slots.sh and payload/scripts/booked.sh: a suite
# run books one of N machine-wide places, and a timing check books the whole machine
# (epic-23 wave-26-never-idle, T6; REQ-6 AC-6.3, AC-6.4 hermetic; spec D8, D14).
#
# WHAT IS UNDER TEST. Four claims, one section each:
#
#   §BOOK        with N places, take N+1 and the last one waits, names who holds the
#                places, and proceeds when one is released; a dead holder's place is
#                reclaimed; a killed command gives its place back; two takers racing for
#                one place produce exactly one winner; every wait has a ceiling; and
#                `--kill-after` stops a command past its limit with exit 124. Review 4
#                (T36): a stale reap lock never gives two winners (B9); a reused pid does
#                not hold a place and a dead place is reaped on every take (B10, B11); an
#                unwritable store runs a shared command unbooked at once and refuses a
#                whole-machine take at once (B12); several words after `--` are refused,
#                never re-parsed (B13).
#   §QUIET       a whole-machine take waits for the held places to drain, blocks new takes
#                while it holds, does not start above the settled load, and prints `void`
#                (retrying twice, then exit 75) when the load rose during the run. Taken
#                from inside a held place it waits for the OTHER places only, and two such
#                takes do not deadlock each other. Review 4 (T36): every wait of one call
#                shares one ceiling (Q8), and the run's own load is not a disturbance (Q9).
#   §STAMP       a `stamp/v1` line goes into the git directory of the tree the command ran
#                in, with the head and dirty count read BEFORE the command and its rc after;
#                the tree's own `.bionic` link is not counted dirty; `cmd=` is one line with
#                no `|`; outside a git tree, no stamp and no error.
#   §NESTED-ENV  `BIONIC_SLOT_HELD=1` books nothing and is what the command sees; a shim
#                inside a shim never waits on its own parent; `BIONIC_QUIET=1` is `--quiet`.
#   §SHELL       `--shell <path>` runs the command the way the harness runs a Bash call
#                (`<path> -c "eval '<cmd>'"`), so its output, diagnostics and exit code are
#                the harness's own; the stamp's `cmd=` stays the command as given (T7).
#
# HERMETIC. No row touches the real store: every call sets BIONIC_SLOTS_DIR to a scratch
# directory and BIONIC_SLOTS_N, and the load is read from BIONIC_LOAD_NOW_FILE, a file the
# row writes. Every row's commands run with cwd under the scratch root and
# GIT_CEILING_DIRECTORIES above it, so no stamp can land in this repository's git dir.
# Every wait in a row is gated on a file the row touches, never on a bare sleep, and every
# gate and every shim wait has a ceiling, so a regression fails a row instead of hanging.
#
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"):
#   * The store, the place count and the load are SYNTHESIZED, by design: the claims are
#     about how takers interact, and a real store or a real load would make them depend on
#     what the machine is doing. resources_settled's reading of the real machine is
#     tests/resources.test.sh's to assert, not this suite's.
#   * Holder pids are REAL processes: a booked command that is still running, or a pid
#     taken from a process that has exited (the dead-holder row). Nothing fakes liveness.
#   * The git trees in §STAMP are real repositories made with `git init`, and the linked
#     worktree is a real `git worktree add`, so the git-dir each stamp lands in is git's
#     own answer.
#
# ANTI-VACUITY (declared, per .claude/rules/test-harness.md, "Anti-vacuity"):
#   * The suite refuses to run when either subject is missing or does not parse.
#   * Every absence (a command that must not have started, a waiting line that must not
#     appear) sits beside a positive on the same output in the same row.
#   * Two rule-bearing rows carry a mutation control on a scratch copy of the library: the
#     race row with the claim's `mkdir` made non-exclusive (more than one winner), and the
#     whole-machine block with the quiet-marker check removed (the shared take proceeds).
#     Each anchors its mutation first and proves the mutant still runs.
#   * The stale-lock row (B9) slows the takers' liveness check by 50 ms, in the takers
#     only, to widen the window it tests; against the library before T36 it gave two or
#     more winners in 7 to 9 rounds of 10 (T36 record). Its pass is structural, not timing.
#
# Usage: bash tests/slots.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
BOOKED="$REPO_ROOT/payload/scripts/booked.sh"
SLOTS="$REPO_ROOT/payload/scripts/lib/slots.sh"

# A run of this suite may itself be inside a booked command (the Bash wall wraps suites in
# the shim), and the rows below measure what an UNBOOKED caller sees.
unset BIONIC_SLOT_HELD BIONIC_SLOT_PLACE BIONIC_SLOT_QUIET BIONIC_QUIET GIT_DIR GIT_WORK_TREE

for _subj in "$BOOKED" "$SLOTS"; do
  if [ ! -r "$_subj" ] || ! bash -n "$_subj" 2>/dev/null; then
    no "subject present and parses: ${_subj#"$REPO_ROOT"/}" "missing or unparseable"
  else
    ok "subject present and parses: ${_subj#"$REPO_ROOT"/}"
  fi
done
[ "$FAIL" -eq 0 ] || finish

TMPROOT="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/slots-test.XXXXXX")" && pwd -P)"
export GIT_CEILING_DIRECTORIES="${TMPROOT%/*}"
BG=""
kill_tree() {  # <pid> — the pid and every descendant, children first
  local c
  for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c"; done
  kill -KILL "$1" 2>/dev/null
}
cleanup() {
  local p f
  for p in $BG; do kill_tree "$p"; done
  for f in "$TMPROOT"/*/*.kid; do
    [ -f "$f" ] && kill_tree "$(cat "$f" 2>/dev/null)"
  done
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

# ── fixture helpers ──────────────────────────────────────────────────────────

newrow() {  # <name> — a fresh row directory, store and load file; resets the knobs
  ROW="$TMPROOT/$1"
  mkdir -p "$ROW"
  ST="$ROW/store"
  LOADF="$ROW/load"
  printf '0.00\n' > "$LOADF"
  SN=2; MW=30; NOTE=60; POLL=0.1; BK_SCRIPT="$BOOKED"
}

bk() {  # booked.sh with this row's store, count, ceilings and load; cwd is the row
  ( cd "$ROW" || exit 1
    env BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N="$SN" BIONIC_SLOTS_POLL="$POLL" \
        BIONIC_SLOTS_MAX_WAIT="$MW" BIONIC_SLOTS_NOTE_S="$NOTE" \
        BIONIC_LOAD_NOW_FILE="$LOADF" bash "$BK_SCRIPT" "$@" )
}

gate() {  # <name> — a command that marks itself started, then holds until <name>.go
  printf 'touch %q; n=0; while [ ! -f %q ] && [ $n -lt 600 ]; do n=$((n+1)); sleep 0.05; done' \
    "$ROW/$1.started" "$ROW/$1.go"
}

wait_file() {  # <path> [<seconds>] — rc 0 once the path exists, 1 at the ceiling
  local i=0 lim=$(( ${2:-20} * 20 ))
  while [ ! -e "$1" ]; do
    i=$((i + 1)); [ "$i" -ge "$lim" ] && return 1
    sleep 0.05
  done
  return 0
}

wait_text() {  # <file> <needle> [<seconds>] — rc 0 once the file contains the needle
  local i=0 lim=$(( ${3:-20} * 20 ))
  while ! grep -qF -- "$2" "$1" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -ge "$lim" ] && return 1
    sleep 0.05
  done
  return 0
}

held_pids() {  # every pid recorded in this row's store, space separated
  cat "$ST"/place.*/pid 2>/dev/null | tr '\n' ' '
}

places() {  # the place directories in this row's store, by name
  ( cd "$ST" 2>/dev/null && ls -d place.* 2>/dev/null | tr '\n' ' ' )
}

mutant_tree() {  # <name> — a scratch copy of booked.sh and its libraries; prints its root
  local m="$TMPROOT/$1"
  mkdir -p "$m/scripts/lib"
  cp "$BOOKED" "$m/scripts/booked.sh"
  cp "$REPO_ROOT"/payload/scripts/lib/*.sh "$m/scripts/lib/"
  printf '%s' "$m"
}

dead_pid() {  # a pid that existed and has exited
  bash -c 'exit 0' &
  local p=$!
  wait "$p" 2>/dev/null
  printf '%s' "$p"
}

# ════════════════════════════════════════════════════════════════════ §BOOK
section "BOOK — one place per run; N+1 waits; dead holders reclaimed; one winner per race"

# B1. The command runs through `bash -c` exactly as given, and its exit code is the shim's.
newrow b1
B1_OUT="$(bk -- 'printf "%s|%s\n" a "b  c"; exit 7' 2>"$ROW/err")"; B1_RC=$?
expect_status "B1.1 the shim's exit code is the command's" 7 "$B1_RC"
expect_eq "B1.2 the command ran through bash -c as given (quotes, spaces and the pipe kept)" \
  "a|b  c" "$B1_OUT"
expect_eq "B1.3 a place was released after the run" "" "$(places)"
expect_true "B1.4 …and one was taken (the store exists)" test -d "$ST"
expect_eq "B1.5 the command reads the shim's stdin, not /dev/null" "piped-in" \
  "$(printf 'piped-in\n' | bk -- cat 2>/dev/null)"

# B2. With two places, a third take waits, names the holders, and proceeds on a release.
newrow b2
bk -- "$(gate a)" > "$ROW/a.out" 2>&1 & BG="$BG $!"; B2_A=$!
bk -- "$(gate b)" > "$ROW/b.out" 2>&1 & BG="$BG $!"; B2_B=$!
wait_file "$ROW/a.started"; wait_file "$ROW/b.started"
B2_HELD="$(held_pids)"
expect_regex "B2.1 both places are held by live pids" '^[0-9]+ [0-9]+ $' "$B2_HELD"
bk -- "touch $ROW/c.started" > "$ROW/c.out" 2>&1 & BG="$BG $!"; B2_C=$!
expect_true "B2.2 the third take prints that it is waiting" wait_text "$ROW/c.out" "waiting"
B2_WAITLINE="$(grep -m1 -F waiting "$ROW/c.out")"
for _p in $B2_HELD; do
  expect_contains "B2.3 the waiting line names holder pid $_p" "$_p" "$B2_WAITLINE"
done
expect_false "B2.4 …and the third command has not started while both are held" \
  test -e "$ROW/c.started"
touch "$ROW/a.go"
expect_true "B2.5 the third command starts once a place is released" wait_file "$ROW/c.started"
wait "$B2_C"; B2_CRC=$?
expect_status "B2.6 …and the third shim exits with its command's code" 0 "$B2_CRC"
touch "$ROW/b.go"; wait "$B2_A" "$B2_B" 2>/dev/null
expect_eq "B2.7 every place is free once all three are done" "" "$(places)"

# B3. A place whose holder pid is gone is free to the next taker.
newrow b3
SN=1; MW=3
B3_DEAD="$(dead_pid)"
mkdir -p "$ST/place.1"; printf '%s\n' "$B3_DEAD" > "$ST/place.1/pid"
expect_false "B3.1 the planted holder pid is dead" kill -0 "$B3_DEAD"
B3_OUT="$(bk -- 'echo ran' 2>&1)"; B3_RC=$?
expect_status "B3.2 the take over a dead holder succeeds" 0 "$B3_RC"
expect_contains "B3.3 …and the command ran" "ran" "$B3_OUT"
expect_absent "B3.4 …without waiting" "waiting" "$B3_OUT"

# B3b. A place left with no holder file (a taker killed between mkdir and the pid write) is
# reclaimed once it is old; a fresh one is a take in progress and is left alone.
newrow b3b
SN=1; MW=1
mkdir -p "$ST/place.1"
B3B_OUT="$(bk -- 'echo ran' 2>&1)"; B3B_RC=$?
expect_status "B3b.1 a fresh place with no holder file is not reclaimed (the wait runs out)" \
  69 "$B3B_RC"
expect_absent "B3b.2 …and the command did not run" "ran" "$B3B_OUT"
touch -t 202001010000 "$ST/place.1"
B3B_OUT="$(bk -- 'echo ran' 2>&1)"; B3B_RC=$?
expect_status "B3b.3 the same place, aged past the orphan line, is reclaimed" 0 "$B3B_RC"
expect_contains "B3b.4 …and the command ran" "ran" "$B3B_OUT"

# B4. A shim killed by a signal kills its command and gives its place back.
newrow b4
SN=1; MW=5
bk -- "echo \$\$ > $ROW/cmd.kid; touch $ROW/k.started; sleep 30" > "$ROW/k.out" 2>&1 &
BG="$BG $!"; B4_BG=$!
wait_file "$ROW/k.started"
B4_SHIM="$(held_pids)"; B4_SHIM="${B4_SHIM% }"
expect_regex "B4.1 the running command holds the place" '^[0-9]+$' "$B4_SHIM"
B4_CMD="$(cat "$ROW/cmd.kid" 2>/dev/null)"
kill -TERM "$B4_SHIM" 2>/dev/null
wait "$B4_BG" 2>/dev/null
expect_true "B4.2 the shim is gone after TERM" bash -c "! kill -0 $B4_SHIM 2>/dev/null"
expect_eq "B4.3 …and its place was released, not left to be reclaimed" "" "$(places)"
expect_true "B4.4 …and its command was killed with it" \
  bash -c "for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 ${B4_CMD:-999999} 2>/dev/null || exit 0; sleep 0.2; done; exit 1"
B4_OUT="$(bk -- 'echo next' 2>&1)"
expect_contains "B4.5 the next take proceeds" "next" "$B4_OUT"

# B4b. A shim killed with SIGKILL runs no trap: its place stays, and the next taker
# reclaims it because the holder pid is gone.
newrow b4b
SN=1; MW=5
bk -- "echo \$\$ > $ROW/cmd.kid; touch $ROW/k.started; sleep 30" > "$ROW/k.out" 2>&1 &
BG="$BG $!"
wait_file "$ROW/k.started"
B4B_SHIM="$(held_pids)"; B4B_SHIM="${B4B_SHIM% }"
kill -KILL "$B4B_SHIM" 2>/dev/null
expect_regex "B4b.1 the SIGKILLed shim's place is still on disk" 'place\.1' "$(places)"
B4B_OUT="$(bk -- 'echo reclaimed' 2>&1)"; B4B_RC=$?
expect_status "B4b.2 the next take reclaims it" 0 "$B4B_RC"
expect_contains "B4b.3 …and runs" "reclaimed" "$B4B_OUT"

# B5. Takers racing for one place: exactly one wins, round after round.
cat > "$TMPROOT/taker.sh" <<'TAKER'
. "$1"
while [ ! -f "$2/start" ]; do sleep 0.01; done
if slots_take >/dev/null 2>&1; then
  echo WIN > "$2/res.$$"
  n=0; while [ ! -f "$2/go" ] && [ $n -lt 400 ]; do n=$((n + 1)); sleep 0.05; done
  slots_release
else
  echo LOSE > "$2/res.$$"
fi
TAKER
race_round() {  # <lib> <dir> — six takers, one place; prints the number of winners
  local lib="$1" d="$2" i n=0 pids=""
  mkdir -p "$d"
  for i in 1 2 3 4 5 6; do
    env BIONIC_SLOTS_DIR="$d/store" BIONIC_SLOTS_N=1 BIONIC_SLOTS_MAX_WAIT=0 \
      BIONIC_SLOTS_POLL=0.05 "$BASH" "$TMPROOT/taker.sh" "$lib" "$d" &
    pids="$pids $!"; BG="$BG $!"
  done
  touch "$d/start"
  while [ "$(ls "$d"/res.* 2>/dev/null | wc -l | tr -d ' ')" -lt 6 ] && [ "$n" -lt 400 ]; do
    n=$((n + 1)); sleep 0.05
  done
  grep -l WIN "$d"/res.* 2>/dev/null | wc -l | tr -d ' '
  touch "$d/go"
  for i in $pids; do wait "$i" 2>/dev/null; done
}
B5_BAD=""; B5_SEEN=""
for _r in 1 2 3 4 5; do
  _w="$(race_round "$SLOTS" "$TMPROOT/b5/r$_r")"
  B5_SEEN="$B5_SEEN $_w"
  [ "$_w" = "1" ] || B5_BAD="$B5_BAD round$_r=$_w"
done
expect_eq "B5.1 every round of six takers for one place had exactly one winner (saw:$B5_SEEN)" \
  "" "$B5_BAD"
expect_regex "B5.2 …and the rounds ran (one result per round)" '^( 1){5}$' "$B5_SEEN"
# Mutation control: a non-exclusive claim lets more than one taker in.
B5M="$(mutant_tree b5-mut)"
anchor "$B5M/scripts/lib/slots.sh" 'mkdir "$place" 2>/dev/null || return 1' 1
sed -i.bak 's|mkdir "$place" 2>/dev/null \|\| return 1|mkdir -p "$place" 2>/dev/null \|\| return 1|' \
  "$B5M/scripts/lib/slots.sh"
expect_true "B5.3 the mutant library still parses" bash -n "$B5M/scripts/lib/slots.sh"
B5M_W="$(race_round "$B5M/scripts/lib/slots.sh" "$TMPROOT/b5/mut")"
expect_true "B5.4 MUTATION: with mkdir -p the same race has more than one winner (saw $B5M_W)" \
  test "${B5M_W:-0}" -gt 1

# B6. Every wait has a ceiling: at the maximum the shim gives up non-zero, naming the
# holder, and notes the wait once at the start and then once per interval, not per poll.
newrow b6
SN=1; MW=3; NOTE=1
bk -- "$(gate h)" > "$ROW/h.out" 2>&1 & BG="$BG $!"; B6_H=$!
wait_file "$ROW/h.started"
B6_HOLDER="$(held_pids)"; B6_HOLDER="${B6_HOLDER% }"
B6_OUT="$(bk -- "touch $ROW/w.ran" 2>&1)"; B6_RC=$?
expect_status "B6.1 at the maximum wait the shim exits 69" 69 "$B6_RC"
expect_contains "B6.2 …naming who holds the place" "$B6_HOLDER" "$(printf '%s' "$B6_OUT" | tail -1)"
expect_false "B6.3 …and its command never ran" test -e "$ROW/w.ran"
B6_NOTES="$(printf '%s\n' "$B6_OUT" | grep -c waiting)"
expect_true "B6.4 the wait is noted at the start and once per interval, not once per poll (saw $B6_NOTES)" \
  test "$B6_NOTES" -ge 2 -a "$B6_NOTES" -le 5
touch "$ROW/h.go"; wait "$B6_H" 2>/dev/null

# B7. --kill-after: past the limit the command and its children are killed, one line says
# it ran past the short limit, and the shim exits 124. Under the limit, nothing changes.
newrow b7
B7_T0=$SECONDS
B7_OUT="$(bk --kill-after 1 -- "sleep 20 & echo \$! > $ROW/kid.kid; wait" 2>&1)"; B7_RC=$?
B7_DT=$(( SECONDS - B7_T0 ))
expect_status "B7.1 a command past --kill-after exits 124" 124 "$B7_RC"
expect_contains "B7.2 …and says it ran past the short limit" "short limit" "$B7_OUT"
expect_true "B7.3 …well before the command would have ended (took ${B7_DT}s)" test "$B7_DT" -lt 15
B7_KID="$(cat "$ROW/kid.kid" 2>/dev/null)"
expect_regex "B7.4 the child recorded its pid" '^[0-9]+$' "$B7_KID"
expect_true "B7.5 …and the child was killed too" \
  bash -c "for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 ${B7_KID:-999999} 2>/dev/null || exit 0; sleep 0.2; done; exit 1"
B7_OUT="$(bk --kill-after 10 -- 'echo inside; exit 3' 2>&1)"; B7_RC=$?
expect_status "B7.6 a command inside its limit keeps its own exit code" 3 "$B7_RC"
expect_contains "B7.7 …and its output" "inside" "$B7_OUT"
expect_absent "B7.8 …and no short-limit line" "short limit" "$B7_OUT"

# B8. A call without the `--` separator is a usage error, and runs nothing.
newrow b8
B8_OUT="$(bk "touch $ROW/u.ran" 2>&1)"; B8_RC=$?
expect_status "B8.1 no -- is a usage error (exit 2)" 2 "$B8_RC"
expect_contains "B8.2 …that says what the usage is" "--" "$B8_OUT"
expect_false "B8.3 …and runs nothing" test -e "$ROW/u.ran"

# B9. A stale reap lock cannot give two winners (review 4 F1). One place and the `.reap`
# lock are both left by a dead pid, so every taker must first steal the lock. Before T36 two
# stealers that both read the dead pid could each drop the lock, the second dropping the
# first's fresh one, and both then reclaimed the place. The takers' liveness check is slowed
# by 50 ms (the window between reading the lock's pid and acting on it), which made the old
# library give two or more winners in 7 and 9 of 10 rounds in two runs; on a library
# that steals the lock one stealer at a time, the count is one whatever the timing.
cat > "$TMPROOT/stealer.sh" <<'STEALER'
. "$1"
_slots_alive() { sleep 0.05; [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
while [ ! -f "$2/start" ]; do :; done
if slots_take >/dev/null 2>&1; then
  echo WIN > "$2/res.$$"
  n=0; while [ ! -f "$2/go" ] && [ $n -lt 400 ]; do n=$((n + 1)); sleep 0.05; done
  slots_release
else
  echo LOSE > "$2/res.$$"
fi
STEALER
B9_K=8; B9_R=10
steal_round() {  # <dir> — B9_K takers, one place and the lock left by a dead pid; prints winners
  local d="$1" i n=0 pids="" dead
  mkdir -p "$d/store/place.1" "$d/store/.reap"
  dead="$(dead_pid)"
  printf '%s\n' "$dead" > "$d/store/place.1/pid"; printf '%s\n' "$dead" > "$d/store/.reap/pid"
  i=0
  while [ "$i" -lt "$B9_K" ]; do
    env BIONIC_SLOTS_DIR="$d/store" BIONIC_SLOTS_N=1 BIONIC_SLOTS_MAX_WAIT=0 \
      BIONIC_SLOTS_POLL=0.05 "$BASH" "$TMPROOT/stealer.sh" "$SLOTS" "$d" 2>/dev/null &
    pids="$pids $!"; BG="$BG $!"; i=$((i + 1))
  done
  sleep 0.2; touch "$d/start"
  while [ "$(ls "$d"/res.* 2>/dev/null | wc -l | tr -d ' ')" -lt "$B9_K" ] && [ "$n" -lt 600 ]; do
    n=$((n + 1)); sleep 0.05
  done
  grep -l WIN "$d"/res.* 2>/dev/null | wc -l | tr -d ' '
  touch "$d/go"
  for i in $pids; do wait "$i" 2>/dev/null; done
}
B9_BAD=""; B9_SEEN=""; _r=1
while [ "$_r" -le "$B9_R" ]; do
  _w="$(steal_round "$TMPROOT/b9/r$_r")"
  B9_SEEN="$B9_SEEN $_w"
  [ "$_w" = "1" ] || B9_BAD="$B9_BAD round$_r=$_w"
  _r=$((_r + 1))
done
expect_eq "B9.1 a stale reap lock never gives two winners: $B9_R rounds of $B9_K takers (saw:$B9_SEEN)" \
  "" "$B9_BAD"
expect_regex "B9.2 …and every round ran (one count per round)" "^( [0-9]+){$B9_R}\$" "$B9_SEEN"

# B10. A holder is the process that claimed the place, not just its pid (review 4 F2). A
# place whose pid now belongs to a different, live process (the pid was reused) is free.
newrow b10
SN=1; MW=2
sleep 60 & B10_LIVE=$!; BG="$BG $!"
mkdir -p "$ST/place.1"
printf 'Thu Jan 1 00:00:00 2015\n' > "$ST/place.1/since"
printf '%s\n' "$B10_LIVE" > "$ST/place.1/pid"
expect_true "B10.1 the planted pid is a live process" kill -0 "$B10_LIVE"
B10_OUT="$(bk -- 'echo ran' 2>&1)"; B10_RC=$?
expect_status "B10.2 a place held by a reused pid is taken" 0 "$B10_RC"
expect_contains "B10.3 …and the command ran" "ran" "$B10_OUT"
expect_absent "B10.4 …without waiting" "waiting" "$B10_OUT"
# The claim records the holder's start, and a live holder whose start matches still holds.
newrow b10b
SN=1; MW=2
bk -- "$(gate h)" > "$ROW/h.out" 2>&1 & BG="$BG $!"; B10_H=$!
wait_file "$ROW/h.started"
B10_HOLDER="$(held_pids)"; B10_HOLDER="${B10_HOLDER% }"
B10_SINCE="$(cat "$ST/place.1/since" 2>/dev/null)"
expect_nonempty "B10.5 a claim records its holder's start time" "$B10_SINCE"
B10_PS="$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$B10_HOLDER" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//')"
expect_eq "B10.6 …as the process's own start time" "$B10_PS" "$B10_SINCE"
MW=1
B10_OUT="$(bk -- "touch $ROW/w.ran" 2>&1)"; B10_RC=$?
expect_status "B10.7 that live holder still holds the place (the take runs out)" 69 "$B10_RC"
expect_false "B10.8 …and its command did not run" test -e "$ROW/w.ran"
touch "$ROW/h.go"; wait "$B10_H" 2>/dev/null

# B11. A dead place is reaped on every take, not only when a take finds no place free (F2).
newrow b11
SN=3; MW=5
mkdir -p "$ST/place.3"; printf '%s\n' "$(dead_pid)" > "$ST/place.3/pid"
B11_OUT="$(bk -- "ls $ST" 2>&1)"; B11_RC=$?
expect_status "B11.1 a take with a free place proceeds" 0 "$B11_RC"
expect_contains "B11.2 …holding place.1 while its command runs" "place.1" "$B11_OUT"
expect_absent "B11.3 …and the dead holder's place.3 is gone by then" "place.3" "$B11_OUT"

# B12. A store that cannot be written (review 4 F5). Booking manages throughput, it is not a
# guard: a shared take runs its command UNBOOKED at once, with one line naming the store. A
# whole-machine take does not run, because a timing result taken without the machine is
# worth nothing: it refuses at once, naming the store.
newrow b12
SN=2; MW=6
mkdir -p "$ST"; chmod 555 "$ST"
B12_T0=$SECONDS
B12_OUT="$(bk -- 'echo ran-unbooked; exit 3' 2>&1)"; B12_RC=$?
B12_DT=$((SECONDS - B12_T0))
expect_status "B12.1 an unwritable store: a shared take runs its command anyway" 3 "$B12_RC"
expect_contains "B12.2 …which ran" "ran-unbooked" "$B12_OUT"
expect_true "B12.3 …at once, not after the wait (took ${B12_DT}s, ceiling ${MW}s)" test "$B12_DT" -le 2
B12_LINE="$(printf '%s\n' "$B12_OUT" | grep -F "$ST")"
expect_nonempty "B12.4 one line names the store" "$B12_LINE"
expect_contains "B12.5 …and says the command ran unbooked" "unbooked" "$B12_LINE"
expect_eq "B12.6 …and it is the only line about it" 1 "$(printf '%s\n' "$B12_OUT" | grep -c -F "$ST")"
B12_T0=$SECONDS
B12_OUT="$(bk --quiet -- "touch $ROW/q.ran" 2>&1)"; B12_RC=$?
B12_DT=$((SECONDS - B12_T0))
expect_status "B12.7 a whole-machine take on the same store refuses (69)" 69 "$B12_RC"
expect_false "B12.8 …and its command never ran" test -e "$ROW/q.ran"
expect_true "B12.9 …at once (took ${B12_DT}s, ceiling ${MW}s)" test "$B12_DT" -le 2
expect_contains "B12.10 …naming the store" "$ST" "$B12_OUT"
# tests/run.sh calls the lib directly for a solo suite and reports any non-zero take as VOID.
B12_T0=$SECONDS
( . "$SLOTS"; BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=2 BIONIC_SLOTS_MAX_WAIT="$MW" \
    slots_take_all "$$" runner >/dev/null 2>&1 ); B12_RC=$?
B12_DT=$((SECONDS - B12_T0))
expect_ne "B12.11 slots_take_all itself answers non-zero on that store" 0 "$B12_RC"
expect_true "B12.12 …at once (took ${B12_DT}s)" test "$B12_DT" -le 2
chmod 755 "$ST"

# B13. Words after `--` are never re-parsed as shell (review 4 F6). The one meaning is one
# word, the whole command line, as the Bash wall passes it; several words are refused.
newrow b13
B13_OUT="$(bk -- printf '%s\n' 'one-literal-argument; echo SECOND-COMMAND-RAN' 2>&1)"; B13_RC=$?
expect_status "B13.1 several words after -- are a usage error (exit 2)" 2 "$B13_RC"
expect_absent "B13.2 …and nothing in them ran as a command" "SECOND-COMMAND-RAN" "$B13_OUT"
expect_contains "B13.3 …and the line says to pass one word" "one word" "$B13_OUT"
B13_OUT="$(bk -- "printf '%s\n' 'one-literal-argument; echo SECOND-COMMAND-RAN'" 2>&1)"; B13_RC=$?
expect_status "B13.4 the same command as one word runs" 0 "$B13_RC"
expect_eq "B13.5 …with its quoted argument kept literal" \
  "one-literal-argument; echo SECOND-COMMAND-RAN" "$B13_OUT"
# The one-word rule holds with --kill-after too (A-T36.11).
B13_OUT="$(bk --kill-after 5 -- printf '%s\n' 'x; echo SECOND-COMMAND-RAN' 2>&1)"; B13_RC=$?
expect_status "B13.8 several words with --kill-after are a usage error (exit 2)" 2 "$B13_RC"
expect_contains "B13.9 …saying to pass one word" "one word" "$B13_OUT"
expect_absent "B13.7 …and nothing in them ran" "SECOND-COMMAND-RAN" "$B13_OUT"
B13_OUT="$(bk --kill-after 5 -- "printf '%s\n' 'x; echo SECOND-COMMAND-RAN'" 2>&1)"; B13_RC=$?
expect_eq "B13.10 the same command as one word runs under --kill-after, its argument literal" \
  "x; echo SECOND-COMMAND-RAN" "$B13_OUT"

# ═══════════════════════════════════════════════════════════════════ §QUIET
section "QUIET — the whole machine: drain, block, settle, re-read, void"

# Q1. A whole-machine take waits for the held places to drain.
newrow q1
bk -- "$(gate a)" > "$ROW/a.out" 2>&1 & BG="$BG $!"; Q1_A=$!
wait_file "$ROW/a.started"
bk --quiet -- "touch $ROW/q.started" > "$ROW/q.out" 2>&1 & BG="$BG $!"; Q1_Q=$!
expect_true "Q1.1 the whole-machine take prints that it is waiting" wait_text "$ROW/q.out" "waiting"
expect_contains "Q1.2 …naming the holder" "$(held_pids | awk '{print $1}')" \
  "$(grep -m1 -F waiting "$ROW/q.out")"
expect_false "Q1.3 …and has not started while a place is held" test -e "$ROW/q.started"
touch "$ROW/a.go"
expect_true "Q1.4 it starts once the held place drains" wait_file "$ROW/q.started"
wait "$Q1_Q"; Q1_RC=$?
expect_status "Q1.5 …and exits with its command's code" 0 "$Q1_RC"
wait "$Q1_A" 2>/dev/null

# Q2. While the whole machine is held, a new shared take waits — even for a place that
# frees while the hold is still draining. The whole-machine taker polls slowly (2 s) and the
# shared one fast (0.1 s), so without the marker the shared take would win the freed place.
q2_drive() {  # <booked script> -> Q2_FIRST (who ran first), Q2_EARLY (1 if C ran during Q)
  BK_SCRIPT="$1"
  bk -- "$(gate a)" > "$ROW/a.out" 2>&1 & BG="$BG $!"; Q2_A=$!
  wait_file "$ROW/a.started"
  POLL=2
  bk --quiet -- "echo Q >> $ROW/order; $(gate q)" > "$ROW/q.out" 2>&1 & BG="$BG $!"; Q2_Q=$!
  POLL=0.1
  wait_text "$ROW/q.out" "waiting"
  bk -- "echo C >> $ROW/order; touch $ROW/c.started" > "$ROW/c.out" 2>&1 & BG="$BG $!"; Q2_C=$!
  Q2_WAITED=0; wait_text "$ROW/c.out" "waiting" 5 && Q2_WAITED=1
  touch "$ROW/a.go"
  wait_file "$ROW/q.started" 10
  Q2_EARLY=0; [ -e "$ROW/c.started" ] && Q2_EARLY=1
  Q2_FIRST="$(head -1 "$ROW/order" 2>/dev/null)"
  touch "$ROW/q.go"
  wait_file "$ROW/c.started" 10
  wait "$Q2_A" "$Q2_Q" "$Q2_C" 2>/dev/null
}
newrow q2
q2_drive "$BOOKED"
expect_eq "Q2.1 a shared take during a whole-machine hold waits" 1 "$Q2_WAITED"
expect_eq "Q2.2 …and the place freed during the drain goes to the whole-machine take" \
  "Q" "$Q2_FIRST"
expect_eq "Q2.3 …and the shared command has not run while the hold runs" 0 "$Q2_EARLY"
expect_true "Q2.4 …then it runs" test -e "$ROW/c.started"
# Mutation control: without the quiet-marker check the shared take takes the freed place.
Q2M="$(mutant_tree q2-mut)"
anchor "$Q2M/scripts/lib/slots.sh" '_slots_quiet_blocks() {' 1
sed -i.bak 's|^_slots_quiet_blocks() {|_slots_quiet_blocks() { return 1;|' "$Q2M/scripts/lib/slots.sh"
expect_true "Q2.5 the mutant library still parses" bash -n "$Q2M/scripts/lib/slots.sh"
newrow q2m
q2_drive "$Q2M/scripts/booked.sh"
expect_eq "Q2.6 MUTATION: without the marker check the shared take runs first" "C" "$Q2_FIRST"

# Q3. It does not start above the settled load; it starts once the load settles.
newrow q3
printf '99.0\n' > "$LOADF"; MW=2
Q3_OUT="$(bk --quiet -- "touch $ROW/q.ran" 2>&1)"; Q3_RC=$?
expect_status "Q3.1 above the settled line the whole-machine take gives up at the ceiling (69)" \
  69 "$Q3_RC"
expect_false "Q3.2 …and never ran its command" test -e "$ROW/q.ran"
expect_contains "Q3.3 …and says it was waiting for the load to settle" "settle" "$Q3_OUT"
MW=20
( sleep 1; printf '0.00\n' > "$LOADF" ) >/dev/null 2>&1 & BG="$BG $!"
Q3_OUT="$(bk --quiet -- "touch $ROW/q.ran" 2>&1)"; Q3_RC=$?
expect_status "Q3.4 once the load settles it runs" 0 "$Q3_RC"
expect_true "Q3.5 …its command" test -e "$ROW/q.ran"
expect_contains "Q3.6 …after noting the wait for the load" "settle" "$Q3_OUT"

# Q4. A load that rose during the run voids it: `void`, release, retry; twice, then exit 75.
newrow q4
Q4_CMD="echo run >> $ROW/runs; printf '99.0\n' > $LOADF; ( sleep 1.5; printf '0.00\n' > $LOADF ) >/dev/null 2>&1 &"
Q4_OUT="$(bk --quiet -- "$Q4_CMD" 2>&1)"; Q4_RC=$?
expect_status "Q4.1 a run voided every time exits 75, not the command's code" 75 "$Q4_RC"
expect_regex "Q4.2 …printing void" '(^|[^a-z])void([^a-z]|$)' "$Q4_OUT"
expect_eq "Q4.3 …after the first run and two retries" 3 "$(wc -l < "$ROW/runs" | tr -d ' ')"
expect_eq "Q4.4 …and every place is free afterwards" "" "$(places)"
# Once only: the second run is clean, so the shim answers with the command's own code.
newrow q4b
Q4B_CMD="if [ ! -f $ROW/runs ]; then printf '99.0\n' > $LOADF; ( sleep 1.5; printf '0.00\n' > $LOADF ) >/dev/null 2>&1 & fi; echo run >> $ROW/runs; exit 4"
Q4B_OUT="$(bk --quiet -- "$Q4B_CMD" 2>&1)"; Q4B_RC=$?
expect_status "Q4.5 a run voided once and clean on retry exits with the command's code" 4 "$Q4B_RC"
expect_eq "Q4.6 …having run twice" 2 "$(wc -l < "$ROW/runs" | tr -d ' ')"
expect_regex "Q4.7 …and printed void for the first" '(^|[^a-z])void([^a-z]|$)' "$Q4B_OUT"

# Q5. From inside a held place a whole-machine take waits for the OTHER places only.
newrow q5
Q5_OUT="$(bk -- "bash $BOOKED --quiet -- 'echo inner-ran'" 2>&1)"; Q5_RC=$?
expect_status "Q5.1 a whole-machine take nested in a booked command completes" 0 "$Q5_RC"
expect_contains "Q5.2 …running its command" "inner-ran" "$Q5_OUT"
bk -- "$(gate x)" > "$ROW/x.out" 2>&1 & BG="$BG $!"; Q5_X=$!
wait_file "$ROW/x.started"
bk -- "bash $BOOKED --quiet -- 'touch $ROW/inner.ran'" > "$ROW/o.out" 2>&1 & BG="$BG $!"; Q5_O=$!
expect_true "Q5.3 with the other place held elsewhere, the nested take waits" \
  wait_text "$ROW/o.out" "waiting"
expect_false "Q5.4 …and has not run" test -e "$ROW/inner.ran"
touch "$ROW/x.go"
expect_true "Q5.5 it runs once the other place drains" wait_file "$ROW/inner.ran"
wait "$Q5_O" "$Q5_X" 2>/dev/null

# Q6. Two booked commands that each nest a whole-machine take do not deadlock: a nested
# take waiting for the machine lends its parent's place to the one that holds it.
newrow q6
for _n in 1 2; do
  bk -- "touch $ROW/o$_n.in; n=0; while [ ! -f $ROW/both ] && [ \$n -lt 400 ]; do n=\$((n+1)); sleep 0.05; done; bash $BOOKED --quiet -- 'touch $ROW/q$_n.ran'" \
    > "$ROW/o$_n.out" 2>&1 &
  BG="$BG $!"; eval "Q6_O$_n=\$!"
done
wait_file "$ROW/o1.in"; wait_file "$ROW/o2.in"
expect_regex "Q6.1 both outer commands hold a place" '^[0-9]+ [0-9]+ $' "$(held_pids)"
touch "$ROW/both"
wait "$Q6_O1"; Q6_RC1=$?
wait "$Q6_O2"; Q6_RC2=$?
expect_eq "Q6.2 both complete without running out the wait" "0 0" "$Q6_RC1 $Q6_RC2"
expect_true "Q6.3 …and both nested commands ran" test -e "$ROW/q1.ran" -a -e "$ROW/q2.ran"

# Q7. A whole-machine take inside a whole-machine hold already has the machine.
newrow q7
MW=5
Q7_OUT="$(bk --quiet -- "bash $BOOKED --quiet -- 'echo nested-quiet'" 2>&1)"; Q7_RC=$?
expect_status "Q7.1 a whole-machine take nested in one completes" 0 "$Q7_RC"
expect_contains "Q7.2 …and runs" "nested-quiet" "$Q7_OUT"

# Q8. One ceiling covers every wait of one call (review 4 F3): the drain, the settle and
# every void retry share BIONIC_SLOTS_MAX_WAIT. Before T36 each wait got the whole ceiling.
# The foreign place drains at half the ceiling, so the drain always completes inside it and
# the two shapes stay apart: one ceiling ends at 8 s, a fresh one per wait at 4 + 8 s.
newrow q8
MW=8
bk -- "$(gate a)" > "$ROW/a.out" 2>&1 & BG="$BG $!"; Q8_A=$!
wait_file "$ROW/a.started"
( sleep 4; touch "$ROW/a.go" ) >/dev/null 2>&1 & BG="$BG $!"
printf '99.0\n' > "$LOADF"
Q8_T0=$SECONDS
Q8_OUT="$(bk --quiet -- "touch $ROW/q.ran" 2>&1)"; Q8_RC=$?
Q8_DT=$((SECONDS - Q8_T0))
expect_status "Q8.1 a drain then a load that never settles gives up (69)" 69 "$Q8_RC"
expect_false "Q8.2 …without running its command" test -e "$ROW/q.ran"
expect_contains "Q8.3 …after waiting for the drain" "drain" "$Q8_OUT"
expect_true "Q8.4 …within one ceiling for both waits (took ${Q8_DT}s, ceiling ${MW}s)" \
  test "$Q8_DT" -le $((MW + 2))
wait "$Q8_A" 2>/dev/null
# The void retries share it too: each run raises the load for 2.5 s, so a retry has to wait.
newrow q8b
MW=4
Q8B_CMD="echo run >> $ROW/runs; printf '99.0\n' > $LOADF; ( sleep 2.5; printf '0.00\n' > $LOADF ) >/dev/null 2>&1 &"
Q8B_T0=$SECONDS
Q8B_OUT="$(bk --quiet -- "$Q8B_CMD" 2>&1)"; Q8B_RC=$?
Q8B_DT=$((SECONDS - Q8B_T0))
Q8B_RUNS="$(wc -l < "$ROW/runs" 2>/dev/null | tr -d ' ')"
expect_regex "Q8.5 the command ran at least once" '^[1-9]' "${Q8B_RUNS:-0}"
expect_true "Q8.6 …but the retries stopped at the ceiling: at most 2 runs (saw ${Q8B_RUNS:-0})" \
  test "${Q8B_RUNS:-0}" -le 2
expect_status "Q8.7 …and the result is void (75), never the command's own code" 75 "$Q8B_RC"
expect_true "Q8.8 …within one ceiling (took ${Q8B_DT}s, ceiling ${MW}s)" test "$Q8B_DT" -le $((MW + 2))

# Q9. The void check does not count the command's own load (review 4 F4). The command burns
# CPU, then sets the load after the run to the settled line plus HALF of its own share of
# the one-minute average (from its own `times`). A disturbance by others would have raised
# it past its own share; this run's own load alone must not void it.
newrow q9
MW=4
Q9_LINE="$( cd "$ROW" && . "$REPO_ROOT/payload/scripts/lib/resources.sh" && resources_settled_line "$(_res_cores)" )"
expect_regex "Q9.1 the settled line is read" '^[0-9]+\.[0-9]+$' "$Q9_LINE"
cat > "$ROW/burn.sh" <<'BURN'
s=$SECONDS; while [ $((SECONDS - s)) -lt 2 ]; do :; done
w=$((SECONDS - s)); times > "$1/t"
echo run >> "$1/runs"
awk -v line="$2" -v w="$w" '
  function sec(x, a) { sub(/s$/, "", x); gsub(",", ".", x); split(x, a, "m"); return a[1] * 60 + a[2] }
  NR == 1 { cpu = sec($1) + sec($2); own = (cpu / w) * (1 - exp(-w / 60)); printf "%.6f\n", line + own / 2 }
' "$1/t" > "$1/load.next"
cat "$1/load.next" > "$3"
BURN
Q9_OUT="$(bk --quiet -- "bash $ROW/burn.sh $ROW $Q9_LINE $LOADF" 2>&1)"; Q9_RC=$?
Q9_AFTER="$(cat "$ROW/load.next" 2>/dev/null)"
expect_true "Q9.2 the load after the run is above the settled line (${Q9_AFTER:-?} > $Q9_LINE)" \
  awk -v a="${Q9_AFTER:-0}" -v l="$Q9_LINE" 'BEGIN { exit !(a + 0 > l + 0) }'
expect_status "Q9.3 …yet the run is not void: its own load is not a disturbance" 0 "$Q9_RC"
expect_eq "Q9.4 …and it ran once" 1 "$(wc -l < "$ROW/runs" | tr -d ' ')"
expect_absent "Q9.5 …with no void line" "void" "$Q9_OUT"

# Q10. A FAILURE STAYS A FAILURE WHEN IT IS ALSO VOID (review 12 F2, A-T50.1; the runner's rule
# since T43). 75 is "try again later", which is what a disturbed PASS means (Q4.1, Q8.7). Over a
# failing run it would hide the failure's own code behind a reason to re-run; so the code is
# the command's, and the void line is still printed.
newrow q10
Q10_CMD="echo run >> $ROW/runs; printf '99.0\n' > $LOADF; ( sleep 1.5; printf '0.00\n' > $LOADF ) >/dev/null 2>&1 & exit 3"
Q10_OUT="$(bk --quiet -- "$Q10_CMD" 2>&1)"; Q10_RC=$?
expect_status "Q10.1 a failing run voided every time exits with its own code (3), not 75" 3 "$Q10_RC"
expect_contains "Q10.2 …and still says it was void" "booked: void — the load rose above" "$Q10_OUT"
expect_eq "Q10.3 …after the first run and two retries, as a passing void does (Q4.3)" 3 \
  "$(wc -l < "$ROW/runs" | tr -d ' ')"
expect_eq "Q10.4 …and every place is free afterwards" "" "$(places)"
# The other void end: the ceiling runs out before a retry can start (Q8's second shape).
newrow q10b
MW=4
Q10B_CMD="echo run >> $ROW/runs; printf '99.0\n' > $LOADF; ( sleep 2.5; printf '0.00\n' > $LOADF ) >/dev/null 2>&1 & exit 3"
Q10B_OUT="$(bk --quiet -- "$Q10B_CMD" 2>&1)"; Q10B_RC=$?
expect_contains "Q10.5 the retries ran out of ceiling" "ran out before a retry could start" "$Q10B_OUT"
expect_status "Q10.6 …and the failing run keeps its own code (3), not 75 (beside Q8.7's 75 for a pass)" 3 "$Q10B_RC"

# ═══════════════════════════════════════════════════════════════════ §STAMP
section "STAMP — stamp/v1 in the tree's own git dir: head and dirty before, rc after"

mkrepo() {  # <dir> — a real repo with one commit
  git init -q "$1"
  git -C "$1" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m init
}
stamps_of() {  # <tree> — the stamp file git's own git-dir answer names
  printf '%s/bionic-stamps' "$(git -C "$1" rev-parse --absolute-git-dir)"
}

newrow s1
mkrepo "$ROW/repo"
printf 'x\n' > "$ROW/repo/untracked"
S1_HEAD="$(git -C "$ROW/repo" rev-parse HEAD)"
S1_STAMPS="$(stamps_of "$ROW/repo")"
( cd "$ROW/repo" && env BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=2 BIONIC_SLOTS_MAX_WAIT=10 \
    bash "$BOOKED" -- 'touch new1; exit 3' ) >/dev/null 2>&1; S1_RC=$?
expect_status "S1.1 the shim still answers the command's code" 3 "$S1_RC"
S1_LINE="$(tail -1 "$S1_STAMPS" 2>/dev/null)"
expect_nonempty "S1.2 a stamp was appended to the tree's git dir" "$S1_LINE"
expect_regex "S1.3 the stamp is stamp/v1 with head, the PRE-run dirty count, rc, ISO-UTC time and the command" \
  "^stamp/v1\\|head=${S1_HEAD}\\|dirty=1\\|rc=3\\|at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\|cmd=touch new1; exit 3\$" \
  "$S1_LINE"

S1_BEFORE="$(wc -l < "$S1_STAMPS" | tr -d ' ')"
( cd "$ROW/repo" && env BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=2 BIONIC_SLOTS_MAX_WAIT=10 \
    bash "$BOOKED" -- 'echo a | cat' ) >/dev/null 2>&1
S1_AFTER="$(wc -l < "$S1_STAMPS" | tr -d ' ')"
expect_eq "S2.1 a second run appends one line" "$((S1_BEFORE + 1))" "$S1_AFTER"
S2_LINE="$(tail -1 "$S1_STAMPS")"
expect_eq "S2.2 a pipe in the command is replaced, so the line keeps six fields" \
  6 "$(printf '%s' "$S2_LINE" | awk -F'|' '{print NF}')"
expect_regex "S2.3 …and the command is still legible" 'cmd=echo a .* cat$' "$S2_LINE"
expect_regex "S2.4 …with dirty counting the file the previous command made" '\|dirty=2\|' "$S2_LINE"

S3_LONG=": $(printf 'x%.0s' $(seq 1 200))"
( cd "$ROW/repo" && env BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=2 BIONIC_SLOTS_MAX_WAIT=10 \
    bash "$BOOKED" -- "$S3_LONG" ) >/dev/null 2>&1
S3_CMD="$(tail -1 "$S1_STAMPS" | sed 's/.*|cmd=//')"
expect_eq "S3.1 the cmd field keeps the first 120 characters" 120 "${#S3_CMD}"
expect_eq "S3.2 …and they are the command's first 120" "${S3_LONG:0:120}" "$S3_CMD"

# S4. Outside a git tree: no stamp, no error.
newrow s4
S4_OUT="$(bk -- 'echo ran' 2>"$ROW/err")"; S4_RC=$?
expect_status "S4.1 outside a git tree the shim runs the command" 0 "$S4_RC"
expect_eq "S4.2 …with its output" "ran" "$S4_OUT"
expect_eq "S4.3 …and nothing on stderr" "" "$(cat "$ROW/err")"
expect_eq "S4.4 …and no stamp file anywhere under the row" "" \
  "$(find "$ROW" -name bionic-stamps 2>/dev/null)"

# S5. A linked worktree is stamped in its OWN git dir, not the main checkout's.
newrow s5
mkrepo "$ROW/main"
git -C "$ROW/main" worktree add -q "$ROW/wt" -b side 2>/dev/null
S5_MAIN_STAMPS="$(stamps_of "$ROW/main")"
S5_WT_STAMPS="$(stamps_of "$ROW/wt")"
expect_ne "S5.1 the worktree has a git dir of its own" "$S5_MAIN_STAMPS" "$S5_WT_STAMPS"
( cd "$ROW/wt" && env BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=2 BIONIC_SLOTS_MAX_WAIT=10 \
    bash "$BOOKED" -- 'true' ) >/dev/null 2>&1
expect_regex "S5.2 the stamp lands in the worktree's git dir with its head" \
  "head=$(git -C "$ROW/wt" rev-parse HEAD)\\|" "$(tail -1 "$S5_WT_STAMPS" 2>/dev/null)"
expect_false "S5.3 …and not in the main checkout's" test -e "$S5_MAIN_STAMPS"

# S6. A voided timing check is stamped with the void code, so it never reads as green.
newrow s6
mkrepo "$ROW/repo"
( cd "$ROW/repo" && env BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=2 BIONIC_SLOTS_MAX_WAIT=20 \
    BIONIC_SLOTS_POLL=0.1 BIONIC_LOAD_NOW_FILE="$LOADF" \
    bash "$BOOKED" --quiet -- "printf '99.0\n' > $LOADF; ( sleep 1.5; printf '0.00\n' > $LOADF ) >/dev/null 2>&1 &" ) \
  >/dev/null 2>&1; S6_RC=$?
expect_status "S6.1 the voided run exits 75" 75 "$S6_RC"
expect_regex "S6.2 …and its stamp carries rc=75" '\|rc=75\|' "$(tail -1 "$(stamps_of "$ROW/repo")" 2>/dev/null)"
# A voided run that FAILED is stamped with its own code (review 12 F2, A-T50.1): still red, and
# red for its own reason. The stamp has no field for the void, and its shape does not change.
( cd "$ROW/repo" && env BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=2 BIONIC_SLOTS_MAX_WAIT=20 \
    BIONIC_SLOTS_POLL=0.1 BIONIC_LOAD_NOW_FILE="$LOADF" \
    bash "$BOOKED" --quiet -- "printf '99.0\n' > $LOADF; ( sleep 1.5; printf '0.00\n' > $LOADF ) >/dev/null 2>&1 & exit 3" ) \
  >/dev/null 2>&1; S6_RC=$?
expect_status "S6.3 a voided run that failed exits with its own code (3)" 3 "$S6_RC"
expect_regex "S6.4 …and its stamp carries rc=3, not rc=75" '\|rc=3\|' "$(tail -1 "$(stamps_of "$ROW/repo")" 2>/dev/null)"

# S7. The tree's own `.bionic` link is not dirt. With no ignore entry git lists it as
# `?? .bionic`; the stamp skips exactly that line when `.bionic` is a symlink, and counts
# every other untracked path — and a `.bionic` that is a plain file — as before.
newrow s7
st_run() {  # <tree> <command> — one booked run in <tree>
  ( cd "$1" && env BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=2 BIONIC_SLOTS_MAX_WAIT=10 \
      bash "$BOOKED" -- "$2" ) >/dev/null 2>&1
}
mkrepo "$ROW/repo"
ln -s "$ROW" "$ROW/repo/.bionic"
expect_contains "S7.1 the fixture's git lists the link as untracked" "?? .bionic" \
  "$(git -C "$ROW/repo" status --porcelain)"
st_run "$ROW/repo" true
expect_regex "S7.2 a tree whose only untracked path is its .bionic link stamps dirty=0" \
  '\|dirty=0\|' "$(tail -1 "$(stamps_of "$ROW/repo")" 2>/dev/null)"
printf 'x\n' > "$ROW/repo/real"
st_run "$ROW/repo" true
expect_regex "S7.3 …and a real untracked file beside it still counts (dirty=1)" \
  '\|dirty=1\|' "$(tail -1 "$(stamps_of "$ROW/repo")" 2>/dev/null)"
mkrepo "$ROW/plain"
printf 'not a link\n' > "$ROW/plain/.bionic"
st_run "$ROW/plain" true
expect_regex "S7.4 a .bionic that is a plain file, not a link, counts (dirty=1)" \
  '\|dirty=1\|' "$(tail -1 "$(stamps_of "$ROW/plain")" 2>/dev/null)"

# S8. The cmd field is made safe before the cut: a multi-line command stamps one line, and a
# command carrying `|rc=0|` stamps a line whose only rc= field is the real one.
newrow s8
mkrepo "$ROW/repo"
S8_STAMPS="$(stamps_of "$ROW/repo")"
st_run "$ROW/repo" true
S8_BEFORE="$(wc -l < "$S8_STAMPS" | tr -d ' ')"
st_run "$ROW/repo" "$(printf 'echo one\r\necho\ttwo')"
expect_eq "S8.1 a multi-line command appends exactly one line" "$((S8_BEFORE + 1))" \
  "$(wc -l < "$S8_STAMPS" | tr -d ' ')"
expect_regex "S8.2 …with its line breaks and tab made spaces" 'cmd=echo one  echo two$' \
  "$(tail -1 "$S8_STAMPS")"
st_run "$ROW/repo" ": '|rc=0|head=0000000000000000000000000000000000000000'; exit 5"
S8_LINE="$(tail -1 "$S8_STAMPS")"
expect_eq "S8.3 a command carrying |rc=0| still stamps six fields" 6 \
  "$(printf '%s' "$S8_LINE" | awk -F'|' '{print NF}')"
expect_eq "S8.4 …whose only rc= field is the real one" "rc=5" \
  "$(printf '%s\n' "$S8_LINE" | tr '|' '\n' | grep '^rc=')"
expect_eq "S8.5 …and whose only head= field is the tree's" "head=$(git -C "$ROW/repo" rev-parse HEAD)" \
  "$(printf '%s\n' "$S8_LINE" | tr '|' '\n' | grep '^head=')"

# S9. --stamp-dir <dir> (wave-26 T56, final review B1): the wall passes the directory the
# command's leading literal `cd` reaches, because the shim itself stands in the main checkout.
# Head and dirty are read THERE and the stamp goes to THAT tree's git dir; nothing lands in the
# shim's own. A dir that does not exist or is in no work tree: no stamp and no error, as outside
# a git tree (S4) — never a stamp in the wrong place.
newrow s9
mkrepo "$ROW/main"
git -C "$ROW/main" worktree add -q "$ROW/wt" -b side 2>/dev/null
printf 'x\n' > "$ROW/wt/untracked"
S9_MAIN_STAMPS="$(stamps_of "$ROW/main")"
S9_WT_STAMPS="$(stamps_of "$ROW/wt")"
s9_run() {  # <command> <shim option>... — one booked run standing in the main checkout
  local c="$1"; shift
  ( cd "$ROW/main" && env BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=2 BIONIC_SLOTS_MAX_WAIT=10 \
      bash "$BOOKED" "$@" -- "$c" ) 2>"$ROW/err"
}
S9_OUT="$(s9_run 'cd ../wt || exit 1; echo ran; exit 4' --stamp-dir "$ROW/wt")"; S9_RC=$?
expect_status "S9.1 with --stamp-dir the shim still answers the command's code" 4 "$S9_RC"
expect_eq "S9.2 …and runs it where the shim stands (the cd is the command's own)" "ran" "$S9_OUT"
expect_regex "S9.3 the stamp lands in the stamp dir's git dir, with ITS head and PRE-run dirty count" \
  "^stamp/v1\\|head=$(git -C "$ROW/wt" rev-parse HEAD)\\|dirty=1\\|rc=4\\|at=[^|]*\\|cmd=cd ../wt    exit 1; echo ran; exit 4\$" \
  "$(tail -1 "$S9_WT_STAMPS" 2>/dev/null)"
expect_false "S9.4 …and nothing lands in the checkout the shim stood in" test -e "$S9_MAIN_STAMPS"
expect_eq "S9.5 …with nothing on stderr" "" "$(cat "$ROW/err")"
s9_run 'true' --stamp-dir=../wt >/dev/null
expect_eq "S9.6 --stamp-dir=<dir>, relative to where the shim stands, is the same option" "2" \
  "$(grep -c . "$S9_WT_STAMPS" 2>/dev/null)"
s9_run 'exit 0' >/dev/null
expect_regex "S9.7 without the option, today's behaviour: the shim's own tree, its own head" \
  "^stamp/v1\\|head=$(git -C "$ROW/main" rev-parse HEAD)\\|dirty=0\\|rc=0\\|" "$(tail -1 "$S9_MAIN_STAMPS" 2>/dev/null)"
expect_eq "S9.7 …and the stamp dir of the earlier runs gets nothing more" "2" \
  "$(grep -c . "$S9_WT_STAMPS" 2>/dev/null)"
mkdir -p "$ROW/plain"
for sd in "$ROW/no-such-dir" "$ROW/plain"; do
  S9_OUT="$(s9_run 'echo ran; exit 5' --stamp-dir "$sd")"; S9_RC=$?
  expect_status "S9.8 [${sd##*/}] a stamp dir in no work tree: the command runs with its code" 5 "$S9_RC"
  expect_eq "S9.8 [${sd##*/}] …and its output" "ran" "$S9_OUT"
  expect_eq "S9.8 [${sd##*/}] …nothing on stderr" "" "$(cat "$ROW/err")"
  expect_eq "S9.8 [${sd##*/}] …no stamp in the shim's own tree (one line, from S9.7)" "1" \
    "$(grep -c . "$S9_MAIN_STAMPS" 2>/dev/null)"
  expect_eq "S9.8 [${sd##*/}] …nor in the worktree's (two lines, from S9.1 and S9.6)" "2" \
    "$(grep -c . "$S9_WT_STAMPS" 2>/dev/null)"
done
expect_eq "S9.8 …and no stamp file anywhere else under the row" \
  "$(printf '%s\n%s' "$S9_MAIN_STAMPS" "$S9_WT_STAMPS" | sort)" \
  "$(find "$ROW" -name bionic-stamps 2>/dev/null | sort)"
s9_run 'true' --stamp-dir >/dev/null; S9_RC=$?
expect_status "S9.9 --stamp-dir with no value is usage (exit 2)" 2 "$S9_RC"
s9_run 'true' --stamp-dir= >/dev/null; S9_RC=$?
expect_status "S9.9 …and so is an empty --stamp-dir=" 2 "$S9_RC"

# S10. --suites <names> (wave-26 T61, critic F1): the wall names the suite files the command runs
# (their basenames, `?` for one it cannot name) and the shim writes them as ONE field, `suites=`,
# just before `cmd=`, so a land can keep the newest stamp of each suite apart. Handed nothing,
# the shim writes today's line. The field keeps one line of fields: a character outside a
# suite name's set (letters, digits, `.`, `_`, `+`, `-`, the `,` between names, `?`) becomes `?`.
newrow s10
mkrepo "$ROW/repo"
S10_STAMPS="$(stamps_of "$ROW/repo")"
S10_HEAD="$(git -C "$ROW/repo" rev-parse HEAD)"
s10_run() {  # <command> <shim option>... — one booked run in the repo
  local c="$1"; shift
  ( cd "$ROW/repo" && env BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=2 BIONIC_SLOTS_MAX_WAIT=10 \
      bash "$BOOKED" "$@" -- "$c" ) 2>"$ROW/err"
}
s10_run 'exit 3' --suites a.test.sh >/dev/null; S10_RC=$?
expect_status "S10.1 with --suites the shim still answers the command's code" 3 "$S10_RC"
expect_regex "S10.2 the stamp carries the field as handed, after at= and before cmd=" \
  "^stamp/v1\\|head=${S10_HEAD}\\|dirty=0\\|rc=3\\|at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\|suites=a\\.test\\.sh\\|cmd=exit 3\$" \
  "$(tail -1 "$S10_STAMPS" 2>/dev/null)"
expect_eq "S10.2 …nothing on stderr" "" "$(cat "$ROW/err")"
s10_run 'true' --suites=a.test.sh,b.test.sh >/dev/null
expect_regex "S10.3 --suites=<names>, two names joined by a comma, is the same option" \
  "\\|rc=0\\|at=[^|]*\\|suites=a\\.test\\.sh,b\\.test\\.sh\\|cmd=true\$" "$(tail -1 "$S10_STAMPS" 2>/dev/null)"
s10_run 'true' --suites '?' >/dev/null
expect_regex "S10.4 a suite the wall cannot name is written as ?" \
  "\\|suites=\\?\\|cmd=true\$" "$(tail -1 "$S10_STAMPS" 2>/dev/null)"
s10_run 'true' --suites "$(printf 'a|rc=0\nx y')" >/dev/null
S10_LINE="$(tail -1 "$S10_STAMPS" 2>/dev/null)"
expect_regex "S10.5 a pipe, a newline, a space or = in the value becomes ?, so the line keeps its fields" \
  "\\|suites=a\\?rc\\?0\\?x\\?y\\|cmd=true\$" "$S10_LINE"
expect_eq "S10.5 …seven fields, one rc=" "7 rc=0" \
  "$(printf '%s' "$S10_LINE" | awk -F'|' '{print NF}') $(printf '%s\n' "$S10_LINE" | tr '|' '\n' | grep '^rc=')"
s10_run 'true' >/dev/null
S10_LINE="$(tail -1 "$S10_STAMPS" 2>/dev/null)"
expect_regex "S10.6 handed nothing, the shim writes today's line" \
  "^stamp/v1\\|head=${S10_HEAD}\\|dirty=0\\|rc=0\\|at=[^|]*\\|cmd=true\$" "$S10_LINE"
expect_eq "S10.6 …six fields, no suites=" "6" "$(printf '%s' "$S10_LINE" | awk -F'|' '{print NF}')"
S10_N="$(grep -c . "$S10_STAMPS")"
s10_run 'true' --suites >/dev/null; S10_RC=$?
expect_status "S10.7 --suites with no value is usage (exit 2)" 2 "$S10_RC"
s10_run 'true' --suites= >/dev/null; S10_RC=$?
expect_status "S10.7 …and so is an empty --suites=" 2 "$S10_RC"
expect_eq "S10.7 …and neither ran nor stamped" "$S10_N" "$(grep -c . "$S10_STAMPS")"
git -C "$ROW/repo" worktree add -q "$ROW/wt" -b side 2>/dev/null
s10_run 'exit 1' --stamp-dir "$ROW/wt" --suites b.test.sh >/dev/null
expect_regex "S10.8 beside --stamp-dir, the field goes with the stamp into that tree" \
  "^stamp/v1\\|head=$(git -C "$ROW/wt" rev-parse HEAD)\\|dirty=0\\|rc=1\\|at=[^|]*\\|suites=b\\.test\\.sh\\|cmd=exit 1\$" \
  "$(tail -1 "$(stamps_of "$ROW/wt")" 2>/dev/null)"

# S11. A RUN THAT NEVER FINISHED STILL STAMPS (wave-26 T61, critic 3 S5). A suite that never got
# its place (69), was stopped at its short limit while it waited (124), or was signalled while it
# waited (128+n) used to leave no line, so "a green, b never ran" at one head read as a's proof
# alone. Each of these ends now stamps the code it ended on and the suites it was handed; the
# land refuses on it and names the suite. A usage error (exit 2) still stamps nothing (S10.7).
newrow s11
mkrepo "$ROW/repo"
S11_STAMPS="$(stamps_of "$ROW/repo")"
sleep 60 & S11_H=$!; BG="$BG $S11_H"
mkdir -p "$ST/place.1"; printf '%s\n' "$S11_H" > "$ST/place.1/pid"
s11_run() {  # <max wait> <shim option>... — one booked run in the repo, the only place held
  local mw="$1"; shift
  ( cd "$ROW/repo" && env BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=1 BIONIC_SLOTS_POLL=0.1 \
      BIONIC_SLOTS_MAX_WAIT="$mw" bash "$BOOKED" "$@" -- "touch $ROW/s11.ran" ) >"$ROW/out" 2>&1
}
s11_run 1 --suites b.test.sh; S11_RC=$?
expect_status "S11.1 no place within the ceiling: the shim exits 69" 69 "$S11_RC"
expect_false "S11.1 …and its command never ran" test -e "$ROW/s11.ran"
expect_regex "S11.2 …and it stamped that end: rc=69, with the suite it was handed" \
  "^stamp/v1\\|head=$(git -C "$ROW/repo" rev-parse HEAD)\\|dirty=0\\|rc=69\\|at=[^|]*\\|suites=b\\.test\\.sh\\|cmd=touch " \
  "$(tail -1 "$S11_STAMPS" 2>/dev/null)"
s11_run 12 --kill-after 1 --suites c.test.sh; S11_RC=$?
expect_status "S11.3 stopped at its short limit while it waited: 124" 124 "$S11_RC"
expect_regex "S11.4 …and it stamped rc=124 with its suite" \
  "\\|rc=124\\|at=[^|]*\\|suites=c\\.test\\.sh\\|cmd=touch " "$(tail -1 "$S11_STAMPS" 2>/dev/null)"
( cd "$ROW/repo" && exec env BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=1 BIONIC_SLOTS_POLL=0.1 \
    BIONIC_SLOTS_MAX_WAIT=20 BIONIC_SLOTS_NOTE_S=60 bash "$BOOKED" --suites d.test.sh -- "touch $ROW/s11.ran" ) \
  >"$ROW/sig.out" 2>&1 & S11_S=$!; BG="$BG $S11_S"
expect_true "S11.5 a run waiting for its place says so" wait_text "$ROW/sig.out" "waiting"
kill -TERM "$S11_S" 2>/dev/null; wait "$S11_S" 2>/dev/null; S11_RC=$?
expect_status "S11.5 …and signalled while it waits it ends 143" 143 "$S11_RC"
expect_regex "S11.6 …and it stamped rc=143 with its suite, though it never ran" \
  "\\|rc=143\\|at=[^|]*\\|suites=d\\.test\\.sh\\|cmd=touch " "$(tail -1 "$S11_STAMPS" 2>/dev/null)"
expect_false "S11.6 …its command never ran" test -e "$ROW/s11.ran"
expect_eq "S11.7 three ends, three lines" "3" "$(grep -c . "$S11_STAMPS" 2>/dev/null)"
kill "$S11_H" 2>/dev/null; wait "$S11_H" 2>/dev/null

# ══════════════════════════════════════════════════════════════════ §NESTED-ENV
section "NESTED-ENV — a command inside a place books nothing and never waits on its parent"

newrow n1
expect_eq "N1.1 the command sees BIONIC_SLOT_HELD=1" "1" \
  "$(bk -- 'printf %s "${BIONIC_SLOT_HELD:-unset}"' 2>/dev/null)"

# N2. With BIONIC_SLOT_HELD=1 in the environment the shim takes nothing, even with every
# place held by someone else.
newrow n2
SN=1; MW=2
bk -- "$(gate h)" > "$ROW/h.out" 2>&1 & BG="$BG $!"; N2_H=$!
wait_file "$ROW/h.started"
N2_BEFORE="$(held_pids)"
N2_OUT="$( cd "$ROW" && env BIONIC_SLOT_HELD=1 BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=1 \
  BIONIC_SLOTS_MAX_WAIT=2 BIONIC_SLOTS_POLL=0.1 bash "$BOOKED" -- 'echo ran' 2>&1)"; N2_RC=$?
expect_status "N2.1 a held run proceeds with every place taken" 0 "$N2_RC"
expect_eq "N2.2 …and runs" "ran" "$N2_OUT"
expect_eq "N2.3 …without taking or touching a place" "$N2_BEFORE" "$(held_pids)"
touch "$ROW/h.go"; wait "$N2_H" 2>/dev/null

# N3. A shim inside a shim, one place: the inner run does not wait on its own parent.
newrow n3
SN=1; MW=5
N3_OUT="$(bk -- "bash $BOOKED -- 'echo inner'" 2>&1)"; N3_RC=$?
expect_status "N3.1 a booked command nested in one, with one place, completes" 0 "$N3_RC"
expect_eq "N3.2 …at once, without waiting" "inner" "$N3_OUT"

# N4. BIONIC_QUIET=1 in the environment is --quiet.
newrow n4
printf '99.0\n' > "$LOADF"; MW=1
N4_OUT="$( cd "$ROW" && env BIONIC_QUIET=1 BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=2 \
  BIONIC_SLOTS_MAX_WAIT=1 BIONIC_SLOTS_POLL=0.1 BIONIC_LOAD_NOW_FILE="$LOADF" \
  bash "$BOOKED" -- "touch $ROW/q.ran" 2>&1)"; N4_RC=$?
expect_status "N4.1 BIONIC_QUIET=1 waits for a settled load like --quiet (gives up: 69)" 69 "$N4_RC"
expect_false "N4.2 …and does not run above it" test -e "$ROW/q.ran"
N4_OUT="$(bk -- "touch $ROW/plain.ran" 2>&1)"; N4_RC=$?
expect_status "N4.3 without it, the same load does not hold a shared take" 0 "$N4_RC"
expect_true "N4.4 …which runs" test -e "$ROW/plain.ran"

# ════════════════════════════════════════════════════════════════════ §SHELL
section "SHELL — --shell runs the command the way the harness does; cmd= stays the original"
#
# THE RULING (wave-26 T7, A-T7.1). The Bash wall wraps a suite command in this shim, and the
# harness runs a Bash call as `<its shell> -c '… eval <command> < /dev/null'`. A plain
# `bash -c` under a zsh harness changes what the command means (echo escapes, word
# splitting, `${pipestatus}`, an unmatched glob), so the wall names the harness's shell with
# `--shell` and the shim evals the command under it. With no `--shell` it is `bash -c`, as
# built. The rows compare against the harness's own shape, run here directly.
H_SH="$(command -v zsh 2>/dev/null)"
[ -n "$H_SH" ] || H_SH="$(command -v bash)"
sq() { local s="$1" r="'\\''"; s="${s//\'/$r}"; printf "'%s'" "$s"; }
harness() {  # <command> — the command as the harness runs it, in this row's directory
  ( cd "$ROW" && "$H_SH" -c "eval $(sq "$1") < /dev/null" 2>&1; echo "rc=$?" )
}

newrow h1
H1_CMDS=( 'echo "a\nb"; true'
          'F="x y"; printf "[%s]" $F; echo'
          'false | true; echo "first=${pipestatus[1]}"'
          'ls nomatch*.zz; echo after'
          'nosuchcmd_t7; echo "rc=$?"'
          'echo "$#"; exit 4' )
H1_I=0
for H1_C in "${H1_CMDS[@]}"; do
  H1_I=$((H1_I + 1))
  H1_WANT="$(harness "$H1_C")"
  H1_GOT="$( bk --shell "$H_SH" -- "$H1_C" < /dev/null 2>&1; echo "rc=$?" )"
  expect_eq "H1.$H1_I under --shell $H_SH the shim answers what the harness answers: [$H1_C]" \
    "$H1_WANT" "$H1_GOT"
done
# The differential: without --shell the same commands are bash's, so at least one row above
# would have read differently under a zsh harness. Asserted only where zsh is the harness.
case "$H_SH" in
  */zsh)
    expect_ne "H1.d without --shell the shim is bash -c, which a zsh harness disagrees with" \
      "$(harness 'echo "a\nb"')" "$(bk -- 'echo "a\nb"' 2>&1; echo "rc=$?")" ;;
  *) ok "H1.d skipped: no zsh on this machine, so bash is the harness and the two agree" ;;
esac

newrow h2
H2_OUT="$(bk --shell "$H_SH" -- 'printf %s "${BIONIC_SLOT_HELD:-unset}"' 2>/dev/null)"
expect_eq "H2.1 under --shell the command is still inside its place" "1" "$H2_OUT"
H2_OUT="$(bk --shell="$H_SH" -- 'echo eq-form' 2>&1)"; H2_RC=$?
expect_status "H2.2 --shell=<path> is the same option" 0 "$H2_RC"
expect_eq "H2.3 …and runs" "eq-form" "$H2_OUT"
bk --shell > /dev/null 2>&1; H2_RC=$?
expect_status "H2.4 --shell with no value is a usage error" 2 "$H2_RC"
bk --shell "" -- 'echo x' > /dev/null 2>&1; H2_RC=$?
expect_status "H2.5 an empty --shell is a usage error" 2 "$H2_RC"

newrow h3
mkrepo "$ROW/repo"
H3_STAMPS="$(stamps_of "$ROW/repo")"
( cd "$ROW/repo" && env BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=2 BIONIC_SLOTS_MAX_WAIT=10 \
    bash "$BOOKED" --shell "$H_SH" -- "echo 'it''s'; exit 5" ) >/dev/null 2>&1; H3_RC=$?
expect_status "H3.1 under --shell the shim answers the command's code" 5 "$H3_RC"
H3_LINE="$(tail -1 "$H3_STAMPS" 2>/dev/null)"
expect_nonempty "H3.2 a stamp was written" "$H3_LINE"
expect_regex "H3.3 the stamp's cmd= is the ORIGINAL command, not the shell form" \
  "\\|rc=5\\|.*\\|cmd=echo 'it''s'; exit 5\$" "$H3_LINE"
expect_absent "H3.4 …with no trace of the shell or the eval in it" "eval" "$H3_LINE"

# ═══════════════════════════════════════════════════════════════════ §KILL
section "KILL — --kill-after stops the command's whole process group, says why, exits 124 (wave-26 T9, D14)"
#
# The Bash wall wraps a short main-thread command with `--kill-after <s>` (A-T9.1..3). Past
# <s> the shim stops the command's PROCESS GROUP, not only the tree it can still see: a child
# whose parent already exited is reparented away from the tree, but stays in the group.
# The orphan's streams go to /dev/null: holding this capture's pipe open would make the `$(…)`
# wait for it to end on its own, and the row would read a natural death as a kill.
newrow k1
K1_T0=$SECONDS
K1_OUT="$(bk --kill-after 1 -- "(sleep 30 > /dev/null 2>&1 & echo \$! > $ROW/orphan.kid); sleep 30" 2>&1)"; K1_RC=$?
K1_DT=$(( SECONDS - K1_T0 ))
expect_status "K1.1 a command past --kill-after exits 124" 124 "$K1_RC"
expect_true "K1.1b …well before the command would have ended (took ${K1_DT}s)" test "$K1_DT" -lt 15
K1_KID="$(cat "$ROW/orphan.kid" 2>/dev/null)"
expect_regex "K1.2 the orphaned child recorded its pid" '^[0-9]+$' "$K1_KID"
expect_true "K1.3 …and the orphan, outside the command's tree, was killed too" \
  bash -c "for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 ${K1_KID:-999999} 2>/dev/null || exit 0; sleep 0.2; done; exit 1"
expect_contains "K1.4 the one line says it is over the short limit" "over the short limit" "$K1_OUT"
expect_contains "K1.5 …and that the fix is a subagent, not a longer timeout" "a longer command belongs in a subagent" "$K1_OUT"
expect_eq "K1.6 …and it is the only line: no job notice from the shell" "1" \
  "$(printf '%s\n' "$K1_OUT" | grep -c .)"

# K2. --kill-after composes with --shell and --quiet, in the order the wall writes them.
newrow k2
K2_OUT="$(bk --shell "$H_SH" --quiet --kill-after 1 -- 'sleep 20; echo never' 2>&1)"; K2_RC=$?
expect_status "K2.1 --shell --quiet --kill-after: exit 124" 124 "$K2_RC"
expect_contains "K2.2 …with the short-limit line" "over the short limit" "$K2_OUT"
expect_absent "K2.3 …and the command did not finish" "never" "$K2_OUT"
K2_OUT="$(bk --shell "$H_SH" --quiet --kill-after 5 -- 'echo inside; exit 4' 2>&1)"; K2_RC=$?
expect_status "K2.4 inside the limit the command's own code passes through" 4 "$K2_RC"
expect_contains "K2.5 …with its output" "inside" "$K2_OUT"

# K3. A killed run stamps 124, so a landing never reads it as proof.
newrow k3
mkrepo "$ROW/repo"
K3_STAMPS="$(stamps_of "$ROW/repo")"
( cd "$ROW/repo" && env BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=2 BIONIC_SLOTS_MAX_WAIT=10 \
    bash "$BOOKED" --kill-after 1 -- 'sleep 20' ) >/dev/null 2>&1; K3_RC=$?
expect_status "K3.1 the killed run exits 124" 124 "$K3_RC"
expect_regex "K3.2 …and its stamp says rc=124" '\|rc=124\|' "$(tail -1 "$K3_STAMPS" 2>/dev/null)"

# K4. THE LIMIT COVERS THE WAIT FOR A PLACE (review 8 F2, A-T44.2). The only place is held past
# the limit, so the command cannot start inside it: the shim gives up AT the limit, not at the
# ceiling, with the line and the code of a run killed at its limit, and runs nothing.
newrow k4
mkrepo "$ROW/repo"
K4_STAMPS="$(stamps_of "$ROW/repo")"
sleep 30 & K4_H=$!; BG="$BG $K4_H"
mkdir -p "$ST/place.1"; printf '%s\n' "$K4_H" > "$ST/place.1/pid"
K4_T0=$SECONDS
K4_OUT="$( cd "$ROW/repo" && env BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=1 BIONIC_SLOTS_POLL=0.1 \
    BIONIC_SLOTS_MAX_WAIT=12 bash "$BOOKED" --kill-after 2 -- "touch $ROW/k4.ran" 2>&1 )"; K4_RC=$?
K4_DT=$(( SECONDS - K4_T0 ))
expect_status "K4.1 a short command with no place free inside its limit exits 124" 124 "$K4_RC"
expect_true "K4.2 …at its 2 s limit, not at the 12 s ceiling (took ${K4_DT}s)" test "$K4_DT" -lt 10
expect_contains "K4.3 …it waited, naming the holder" "$K4_H" "$K4_OUT"
expect_contains "K4.4 …with the line of a run stopped at its limit" \
  "booked: stopped after 2s — over the short limit; a longer command belongs in a subagent" "$K4_OUT"
expect_false "K4.5 …and its command never ran" test -e "$ROW/k4.ran"
# Since T61 (critic 3 S5) a run that never got its place still stamps, with the code it ended
# on, so a land never reads "this suite did not run" as nothing to answer for.
expect_eq "K4.6 …and it stamped once, rc=124, though it ran nothing" "1 rc=124" \
  "$(grep -c . "$K4_STAMPS" 2>/dev/null) $(tail -1 "$K4_STAMPS" 2>/dev/null | tr '|' '\n' | grep '^rc=')"
kill "$K4_H" 2>/dev/null; wait "$K4_H" 2>/dev/null
( cd "$ROW/repo" && env BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N=1 BIONIC_SLOTS_MAX_WAIT=12 \
    bash "$BOOKED" --kill-after 5 -- "touch $ROW/k4.ran" ) >/dev/null 2>&1; K4_RC=$?
expect_status "K4.7 with the holder gone the same call runs" 0 "$K4_RC"
expect_true "K4.8 …its command ran" test -e "$ROW/k4.ran"
expect_eq "K4.9 …and it stamped its own line, rc=0 (beside K4.6)" "2 rc=0" \
  "$(grep -c . "$K4_STAMPS" 2>/dev/null) $(tail -1 "$K4_STAMPS" 2>/dev/null | tr '|' '\n' | grep '^rc=')"

# K5. THE KILL IS TIMED FROM THE SHIM'S START, so the wait spends the limit. The place is held
# for 4 s and the command needs 4 s: inside a 6 s limit counted from the run it would finish
# (at about 8 s, 2 s to spare); counted from the shim's start it is stopped at 6 s (2 s early).
newrow k5
SN=1; MW=30
( sleep 4 ) & K5_H=$!; BG="$BG $K5_H"
mkdir -p "$ST/place.1"; printf '%s\n' "$K5_H" > "$ST/place.1/pid"
K5_OUT="$(bk --kill-after 6 -- 'sleep 4; echo finished' 2>&1)"; K5_RC=$?
expect_contains "K5.1 the command waited for its place" "waiting for a place" "$K5_OUT"
expect_status "K5.2 …and was stopped at 6 s from the shim's start: exit 124" 124 "$K5_RC"
expect_contains "K5.3 …with the short-limit line" "over the short limit" "$K5_OUT"
expect_absent "K5.4 …before it could finish" "finished" "$K5_OUT"

# K6. A BOOKED COMMAND KEEPS THE SIGNALS IT WOULD HAVE UNWRAPPED (review 8 F3, A-T44.5). A command
# started in the background without job control starts with SIGINT and SIGQUIT ignored, and
# every process below inherits that. Each command runs unwrapped first; the booked run, in
# bash and under --shell as the wall writes it, must print the same.
newrow k6
K6_INT='trap "echo got-int" INT; kill -INT $$; sleep 0.2; echo after'
K6_QUIT='trap "echo got-quit" QUIT; kill -QUIT $$; sleep 0.2; echo after'
K6_KID="sh -c 'kill -INT \$\$; echo survived'; echo \"rc=\$?\""
K6_PLAIN="$(bash -c "$K6_INT" 2>&1)"
expect_eq "K6.1 control: unwrapped, the command's own INT trap runs" "got-int"$'\n'"after" "$K6_PLAIN"
expect_eq "K6.2 booked, it runs the same" "$K6_PLAIN" "$(bk -- "$K6_INT" 2>&1)"
K6_PLAIN="$(bash -c "$K6_QUIT" 2>&1)"
expect_eq "K6.3 control: unwrapped, the QUIT trap runs" "got-quit"$'\n'"after" "$K6_PLAIN"
expect_eq "K6.4 booked, it runs the same" "$K6_PLAIN" "$(bk -- "$K6_QUIT" 2>&1)"
K6_PLAIN="$(bash -c "$K6_KID" 2>&1)"
expect_eq "K6.5 control: unwrapped, a process below the command dies of INT" "rc=130" "$K6_PLAIN"
expect_eq "K6.6 booked, it dies the same way: INT is not ignored below the shim" "$K6_PLAIN" "$(bk -- "$K6_KID" 2>&1)"
expect_eq "K6.7 …under --shell as well" "$K6_PLAIN" "$(bk --shell "$H_SH" -- "$K6_KID" 2>&1)"
expect_eq "K6.8 …and under --kill-after, which always had job control" "$K6_PLAIN" "$(bk --kill-after 9 -- "$K6_KID" 2>&1)"

# K7. EVERY COMMAND LEADS ITS OWN PROCESS GROUP NOW, so a shim stopped by a signal kills the
# group with the tree: a child whose parent already exited dies too, as under --kill-after (K1).
newrow k7
SN=1; MW=5
bk -- "(sleep 30 > /dev/null 2>&1 & echo \$! > $ROW/orphan.kid); touch $ROW/k.started; sleep 30" > "$ROW/k.out" 2>&1 &
BG="$BG $!"; K7_BG=$!
wait_file "$ROW/k.started"
K7_SHIM="$(held_pids)"; K7_SHIM="${K7_SHIM% }"
expect_regex "K7.1 the running command holds the place" '^[0-9]+$' "$K7_SHIM"
K7_KID="$(cat "$ROW/orphan.kid" 2>/dev/null)"
expect_regex "K7.2 the orphaned child recorded its pid" '^[0-9]+$' "$K7_KID"
kill -TERM "$K7_SHIM" 2>/dev/null
wait "$K7_BG" 2>/dev/null
expect_true "K7.3 TERM to the shim kills the orphan too, outside the tree but inside the group" \
  bash -c "for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 ${K7_KID:-999999} 2>/dev/null || exit 0; sleep 0.2; done; exit 1"
expect_eq "K7.4 …and the place was released" "" "$(places)"

# K8. A SIGNAL SENT TO THE SHIM REACHES THE COMMAND AS ITSELF, AND QUIT IS TAKEN TOO (review 12
# F3, A-T50.2). K6 has the command signal itself; here the signal comes from outside, as an
# interrupt or a stop from the harness would. The shim is started with INT and QUIT at their
# defaults, as a harness spawn starts a call: perl resets them before it execs the shim, because
# this suite may itself have been started with them ignored (a background job without job
# control is), and a signal ignored on entry can be neither trapped nor received. The command
# traps each signal and writes the one it saw; an orphan it left behind (outside its tree,
# inside its group) must die too, and the place must be free afterwards.
# EVERY WAIT HERE IS BOUNDED: a shim that does not end within 8 s of the signal is a failed row,
# and the row then stops what it started itself, so a regression fails in seconds, never hangs.
newrow k8
SN=1; MW=5
K8_CMD="for s in INT QUIT TERM HUP; do trap \"echo got-\$s > $ROW/k8.saw; exit 7\" \$s; done; echo \$\$ > $ROW/k8.pid; (sleep 30 > /dev/null 2>&1 & echo \$! > $ROW/k8.kid); touch $ROW/k8.started; while :; do sleep 0.1; done"
gone() {  # <pid> — rc 0 once the pid is gone, within two seconds
  local i=0
  while kill -0 "${1:-999999}" 2>/dev/null; do i=$((i + 1)); [ "$i" -lt 20 ] || return 1; sleep 0.1; done
  return 0
}
k8_drive() {  # <signal> [<shim option>...] -> K8_RC (or "hung"), K8_SAW, K8_PID, K8_KID
  local _sig="$1" _job _shim _i=0
  shift
  rm -f "$ROW"/k8.*
  # `exec` all the way down, so the job's pid IS the shim's.
  ( cd "$ROW" || exit 1
    exec env BIONIC_SLOTS_DIR="$ST" BIONIC_SLOTS_N="$SN" BIONIC_SLOTS_POLL="$POLL" \
      BIONIC_SLOTS_MAX_WAIT="$MW" BIONIC_SLOTS_NOTE_S="$NOTE" BIONIC_LOAD_NOW_FILE="$LOADF" \
      perl -e '$SIG{INT} = $SIG{QUIT} = "DEFAULT"; exec @ARGV or exit 126' \
      bash "$BK_SCRIPT" "$@" -- "$K8_CMD" ) > "$ROW/k8.out" 2>&1 &
  _job=$!
  BG="$BG $_job"
  wait_file "$ROW/k8.started" 10
  _shim="$(held_pids)"; _shim="${_shim% }"
  K8_SHIM_OK=0; [ "$_shim" = "$_job" ] && K8_SHIM_OK=1
  K8_PID="$(cat "$ROW/k8.pid" 2>/dev/null)"; K8_KID="$(cat "$ROW/k8.kid" 2>/dev/null)"
  kill -"$_sig" "$_job" 2>/dev/null
  while kill -0 "$_job" 2>/dev/null && [ "$_i" -lt 80 ]; do _i=$((_i + 1)); sleep 0.1; done
  if kill -0 "$_job" 2>/dev/null; then
    K8_RC=hung
    kill_tree "$_job"
    wait "$_job" 2>/dev/null
  else
    wait "$_job" 2>/dev/null; K8_RC=$?
  fi
  K8_SAW="$(cat "$ROW/k8.saw" 2>/dev/null)"
}
k8_reap() {  # after the rows: a command a failing shim left running is this suite's to stop
  [ -z "$K8_PID" ] || kill -KILL "$K8_PID" 2>/dev/null
  [ -z "$K8_KID" ] || kill -KILL "$K8_KID" 2>/dev/null
  rm -rf "$ST"
}
for _k8 in INT:130 QUIT:131 TERM:143 HUP:129; do
  _sig="${_k8%:*}"
  k8_drive "$_sig"
  expect_eq "K8.0 [$_sig] the shim holds the place" 1 "$K8_SHIM_OK"
  expect_regex "K8.1 [$_sig] the command and its orphan were running" '^[0-9]+ [0-9]+$' "$K8_PID $K8_KID"
  expect_eq "K8.2 [$_sig] the command saw the signal the shim took, not TERM" "got-$_sig" "$K8_SAW"
  expect_status "K8.3 [$_sig] the shim exits 128 + the signal's number" "${_k8#*:}" "$K8_RC"
  expect_true "K8.4 [$_sig] the command is gone" gone "$K8_PID"
  expect_true "K8.5 [$_sig] …and so is its orphan, outside its tree but inside its group" gone "$K8_KID"
  expect_eq "K8.6 [$_sig] …and the place was released (beside K7.1's held place)" "" "$(places)"
  k8_reap
done
for _sig in INT QUIT; do
  k8_drive "$_sig" --shell "$H_SH"
  expect_eq "K8.7 [$_sig] under --shell ${H_SH##*/} the command saw the signal too" "got-$_sig" "$K8_SAW"
  expect_true "K8.8 [$_sig] …and it is gone" gone "$K8_PID"
  expect_eq "K8.9 [$_sig] …with the place free" "" "$(places)"
  k8_reap
done

# K9. THE LIMIT NEVER FIRES EARLY (review 12 F4, A-T50.3). The elapsed time is read from
# `$SECONDS`, which counts whole seconds of the wall clock, so "elapsed >= limit" is true as
# soon as a second boundary passes after the shim's start: up to a second early. Each run here
# starts 0.4 s into a wall-clock second (perl's clock), so a boundary always falls inside the
# 0.8 s command, early enough for the 0.2 s poll to see it: before T50 every such run was killed
# under a 1 s limit. The command records whether its run crossed a boundary, so the row proves
# the condition was there.
newrow k9
k9_align() {  # sleep until the wall clock is 0.4 s into a second
  perl -MTime::HiRes=time,sleep -e '$f = time - int(time); sleep(($f < 0.4 ? 0.4 : 1.4) - $f)'
}
K9_CMD='s=$(date +%s); sleep 0.8; [ "$(date +%s)" = "$s" ] || echo crossed; echo done'
K9_KILLED=0; K9_DONE=0; K9_CROSSED=0
for _i in 1 2 3 4 5; do
  k9_align
  _out="$(bk --kill-after 1 -- "$K9_CMD" 2>&1)"; _rc=$?
  [ "$_rc" -ne 124 ] || K9_KILLED=$((K9_KILLED + 1))
  case "$_out" in *done*) K9_DONE=$((K9_DONE + 1)) ;; esac
  case "$_out" in *crossed*) K9_CROSSED=$((K9_CROSSED + 1)) ;; esac
done
expect_eq "K9.1 a 0.8 s command under --kill-after 1 is never killed (killed $K9_KILLED of 5)" 0 "$K9_KILLED"
expect_eq "K9.2 …every run finished" 5 "$K9_DONE"
expect_true "K9.3 …and a second boundary fell inside the command in at least 4 of 5 runs (saw $K9_CROSSED)" \
  test "$K9_CROSSED" -ge 4
k9_align
_out="$(bk --kill-after 1 -- 'sleep 3; echo done' 2>&1)"; _rc=$?
expect_status "K9.4 the same limit still stops a 3 s command (124; beside K9.1 on the same code)" 124 "$_rc"
# The limit spends the wait for a place too (K4), and gives up there by the same rule. The only
# place is held until 0.9 s after the aligned start: inside the limit, so the command runs.
SN=1
for _i in 1 2 3; do
  k9_align
  ( sleep 0.9 ) & K9_H=$!; BG="$BG $K9_H"
  mkdir -p "$ST/place.1"; printf '%s\n' "$K9_H" > "$ST/place.1/pid"
  _out="$(bk --kill-after 1 -- 'echo ran' 2>&1)"; _rc=$?
  expect_status "K9.5 [$_i] a place freed 0.9 s in is taken under a 1 s limit, not given up early" 0 "$_rc"
  expect_contains "K9.6 [$_i] …it waited for it first" "waiting for a place" "$_out"
  wait "$K9_H" 2>/dev/null
done

# U1. --unbooked IS GONE (the lead's ruling at T44): only a suite is wrapped, so the shim has no
# command to run without a place. The flag is now an unknown option.
newrow u1
bk --unbooked --kill-after 5 -- "touch $ROW/u.ran" > "$ROW/u.out" 2>&1; U1_RC=$?
expect_status "U1.1 --unbooked is a usage error (exit 2)" 2 "$U1_RC"
expect_contains "U1.2 …the usage line names the options there are" "--kill-after <seconds>" "$(cat "$ROW/u.out")"
expect_absent "U1.3 …and --unbooked is not one of them" "unbooked" "$(cat "$ROW/u.out")"
expect_false "U1.4 …and the command did not run" test -e "$ROW/u.ran"
bk --kill-after 5 -- "touch $ROW/u.ran" > /dev/null 2>&1; U1_RC=$?
expect_status "U1.5 the same call without it runs" 0 "$U1_RC"
expect_true "U1.6 …and its command ran (beside U1.4)" test -e "$ROW/u.ran"

finish
