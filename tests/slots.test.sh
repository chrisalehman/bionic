#!/bin/bash
# tests/slots.test.sh — payload/scripts/booked.sh, the shim every wrapped suite runs in, and
# payload/scripts/lib/slots.sh, the liveness rule it and the gate share (epic-23
# wave-26-never-idle, T6; REQ-6 AC-6.3, AC-6.4 hermetic; spec D8, D14; on the gate since
# wave-28-finished-work-lands T12: D10, D13, AC-2.6, AC-2.13).
#
# WHAT IS UNDER TEST. The claims, one section each:
#
#   §RUN         the shim runs the command it was given (one word after `--`, through `bash -c`)
#                and answers its code; it asks the gate first and ends its request on every end,
#                a signal included; a shim killed with SIGKILL leaves a request the gate counts
#                killed, and the next ask proceeds; `--kill-after` stops a command past its limit
#                with exit 124; a store that cannot be written runs an ordinary command
#                unadmitted at once and refuses a whole-machine run at once (69); several words
#                after `--` are refused, never re-parsed.
#   §LIVE        lib/slots.sh as T12 left it: the liveness rule (a pid that lives and started
#                when the record says; a reused pid does not hold) and the directory claim the
#                gate's lock is built on, exactly one winner per race.
#   §QUIET       a whole-machine run waits at the gate while another run is admitted, holds
#                every other ask off while it runs, does not start above the settled load, and
#                prints `void` (retrying twice under the same admission, then exit 75) when the
#                load rose during the run; one ceiling covers the settle and every retry; the
#                run's own load is not a disturbance; a failure stays a failure.
#   §STAMP       a `stamp/v1` line goes into the git directory of the tree the command ran
#                in, with the head and dirty count read BEFORE the command and its rc after;
#                the tree's own `.bionic` link is not counted dirty; `cmd=` is one line with
#                no `|`; outside a git tree, no stamp and no error; every end stamps, a wait at
#                the gate that ran out (75) included.
#   §NESTED-ENV  the command sees BIONIC_GATE_ADMIT naming its request; a shim inside a shim is
#                believed and never waits on its parent; BIONIC_SLOT_HELD=1 skips nothing;
#                `BIONIC_QUIET=1` is `--quiet`.
#   §SHELL       `--shell <path>` runs the command the way the harness runs a Bash call
#                (`<path> -c "eval '<cmd>'"`), so its output, diagnostics and exit code are
#                the harness's own; the stamp's `cmd=` stays the command as given (T7).
#   §KILL        --kill-after stops the command's whole process group; its limit covers the
#                wait at the gate, which ends 75, never 124 (AC-2.6).
#
# REMOVED AT T12, with the place count, the take loop and the wait they pinned (lib/slots.sh's
# slots_take, slots_take_all, slots_release, slots_count and the knobs BIONIC_SLOTS_*): §BOOK's
# B3, B3b, B6, B9, B11; §QUIET's Q2 mutation, Q5's drain and Q6 (lending a place to a nested
# take); K9's freed-place rows; §QUIET-HELD, §SOLO-SAME and §MAX-WAIT. Their claims are now the
# gate's: tests/gate.test.sh §NUMBER, §TWO, §ANCESTOR and §WRAP. §BOOK became §RUN (B2 now waits
# at the gate), and its B5 race and B10 reused pid became §LIVE's L2 and L1.
#
# HERMETIC. No row touches the real store: every call sets BIONIC_GATE_DIR to a scratch
# directory, pins the memory reading low and the processor idle (a row that wants a full
# machine pins the memory over the share instead), and reads the load from BIONIC_LOAD_NOW_FILE,
# a file the row writes. Every row's commands run with cwd under the scratch root and
# GIT_CEILING_DIRECTORIES above it, so no stamp can land in this repository's git dir.
# Every wait in a row is gated on a file the row touches, never on a bare sleep, and every
# gate and every shim wait has a ceiling, so a regression fails a row instead of hanging.
#
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"):
#   * The store's readings and the load are SYNTHESIZED, by design: the claims are about how
#     the shim and the gate interact, and a real reading would make them depend on what the
#     machine is doing. resources_settled's reading of the real machine is
#     tests/resources.test.sh's to assert, not this suite's.
#   * Holder pids are REAL processes: a booked command that is still running, a planted
#     request held by a live `sleep`, or a pid taken from a process that has exited. Nothing
#     fakes liveness.
#   * The git trees in §STAMP are real repositories made with `git init`, and the linked
#     worktree is a real `git worktree add`, so the git-dir each stamp lands in is git's
#     own answer.
#
# ANTI-VACUITY (declared, per .claude/rules/test-harness.md, "Anti-vacuity"):
#   * The suite refuses to run when either subject is missing or does not parse.
#   * Every absence (a command that must not have started, a waiting line that must not
#     appear) sits beside a positive on the same output in the same row.
#   * The claim race (§LIVE) carries a mutation control on a scratch copy of the library: the
#     claim's `mkdir` made non-exclusive gives more than one winner. It anchors its mutation
#     first and proves the mutant still runs.
#
# Usage: bash tests/slots.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
BOOKED="$REPO_ROOT/payload/scripts/booked.sh"
SLOTS="$REPO_ROOT/payload/scripts/lib/slots.sh"

# A run of this suite may itself be inside an admitted command (the Bash wall wraps suites in
# the shim, and the runner asks for each suite), and the rows below measure a caller that
# holds nothing.
unset BIONIC_GATE_ADMIT BIONIC_GATE_AGENT BIONIC_SLOT_HELD BIONIC_QUIET BIONIC_NOW_FILE \
  BIONIC_NOW_EPOCH GIT_DIR GIT_WORK_TREE

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

# The gate's environment every booked call here gets: an idle processor and a low memory
# reading, so an ask is decided by what this row has admitted and nothing else.
GE=(-u BIONIC_GATE_ADMIT -u BIONIC_GATE_AGENT BIONIC_GATE_POLL=0.1 BIONIC_PROBE_USED_PCT=10
  BIONIC_PROBE_BUSY_CORES=0 BIONIC_PROBE_CORES=8 BIONIC_PROBE_TOTAL_MB=8192)

newrow() {  # <name> — a fresh row directory, store and load file; resets the knobs
  ROW="$TMPROOT/$1"
  mkdir -p "$ROW"
  ST="$ROW/store"
  LOADF="$ROW/load"
  printf '0.00\n' > "$LOADF"
  MW=30; POLL=0.1; USED=10; BK_SCRIPT="$BOOKED"
}

bk() {  # booked.sh with this row's store, readings, settle ceiling and load; cwd is the row
  ( cd "$ROW" || exit 1
    env "${GE[@]}" BIONIC_GATE_DIR="$ST" BIONIC_GATE_POLL="$POLL" BIONIC_PROBE_USED_PCT="$USED" \
        BIONIC_SETTLE_MAX_WAIT="$MW" BIONIC_LOAD_NOW_FILE="$LOADF" bash "$BK_SCRIPT" "$@" )
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

# The admitted, unfinished requests in this row's store: their holders' pids (held_pids) and
# their ids (places, empty once every run has ended).
_unfinished() {  # <field: pid|id>
  local f h
  for f in "$ST"/requests/[0-9]*; do
    [ -f "$f" ] || continue
    grep -q '^admitted=' "$f" && ! grep -q '^ended=' "$f" || continue
    if [ "$1" = id ]; then printf '%s ' "${f##*/}"; continue; fi
    h="$(sed -n 's/^holder=//p' "$f" | tail -n 1)"
    printf '%s ' "${h%%:*}"
  done
}
held_pids() { _unfinished pid; }
places() { _unfinished id; }
nreq() { ls "$ST/requests" 2>/dev/null | grep -c '^[0-9][0-9]*$'; }

plant_req() {  # <id> <holder pid> — a foreign run the gate admitted, held by a live process
  local st
  st="$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$2" 2>/dev/null | awk '{ $1 = $1; print }')"
  mkdir -p "$ST/requests"
  printf 'key=foreign\nkind=work\nwho=foreign:w\ntree=/\nasked=1\nholder=%s:%s\nadmitted=1\npromise=1:0.1:10\n' \
    "$2" "$st" > "$ST/requests/$1"
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

# ════════════════════════════════════════════════════════════════════ §RUN
section "RUN — the shim asks, runs the command as given, and ends its request on every end"

# B1. The command runs through `bash -c` exactly as given, and its exit code is the shim's.
newrow b1
B1_OUT="$(bk -- 'printf "%s|%s\n" a "b  c"; exit 7' 2>"$ROW/err")"; B1_RC=$?
expect_status "B1.1 the shim's exit code is the command's" 7 "$B1_RC"
expect_eq "B1.2 the command ran through bash -c as given (quotes, spaces and the pipe kept)" \
  "a|b  c" "$B1_OUT"
expect_eq "B1.3 its request was ended after the run" "" "$(places)"
expect_eq "B1.4 …and one was asked (the store holds it)" "1" "$(nreq)"
expect_eq "B1.5 the command reads the shim's stdin, not /dev/null" "piped-in" \
  "$(printf 'piped-in\n' | bk -- cat 2>/dev/null)"

# B2. A second run asks while the first holds the gate's only room (no cost on record, so the
# gate admits one at a time): it waits, says so, and runs once the first ends.
newrow b2
bk -- "$(gate a)" > "$ROW/a.out" 2>&1 & BG="$BG $!"; B2_A=$!
wait_file "$ROW/a.started"
bk -- "touch $ROW/c.started" > "$ROW/c.out" 2>&1 & BG="$BG $!"; B2_C=$!
expect_true "B2.1 the second run prints that it waits at the gate" wait_text "$ROW/c.out" "waits for its turn"
expect_false "B2.2 …and has not started while the first is admitted" test -e "$ROW/c.started"
touch "$ROW/a.go"
expect_true "B2.3 it starts once the first ends" wait_file "$ROW/c.started"
wait "$B2_C"; B2_CRC=$?
expect_status "B2.4 …and the second shim exits with its command's code" 0 "$B2_CRC"
wait "$B2_A" 2>/dev/null
expect_eq "B2.5 every request is ended once both are done" "" "$(places)"

# B4. A shim killed by a signal kills its command and ends its request with the signal's code.
newrow b4
bk -- "echo \$\$ > $ROW/cmd.kid; touch $ROW/k.started; sleep 30" > "$ROW/k.out" 2>&1 &
BG="$BG $!"; B4_BG=$!
wait_file "$ROW/k.started"
B4_SHIM="$(held_pids)"; B4_SHIM="${B4_SHIM% }"
expect_regex "B4.1 the running command's shim holds the admission" '^[0-9]+$' "$B4_SHIM"
B4_ID="$(places)"; B4_ID="${B4_ID% }"
B4_CMD="$(cat "$ROW/cmd.kid" 2>/dev/null)"
kill -TERM "$B4_SHIM" 2>/dev/null
wait "$B4_BG" 2>/dev/null
expect_true "B4.2 the shim is gone after TERM" bash -c "! kill -0 $B4_SHIM 2>/dev/null"
expect_eq "B4.3 …and its request was ended, with 143" "143" \
  "$(sed -n 's/^rc=//p' "$ST/requests/${B4_ID:-none}" 2>/dev/null)"
expect_true "B4.4 …and its command was killed with it" \
  bash -c "for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 ${B4_CMD:-999999} 2>/dev/null || exit 0; sleep 0.2; done; exit 1"
B4_OUT="$(bk -- 'echo next' 2>&1)"
expect_contains "B4.5 the next run proceeds" "next" "$B4_OUT"

# B4b. A shim killed with SIGKILL runs no trap: its request is never ended, and the gate counts
# it killed because its holder is gone, so the next ask is admitted at once.
newrow b4b
bk -- "echo \$\$ > $ROW/cmd.kid; touch $ROW/k.started; sleep 30" > "$ROW/k.out" 2>&1 &
BG="$BG $!"
wait_file "$ROW/k.started"
B4B_SHIM="$(held_pids)"; B4B_SHIM="${B4B_SHIM% }"
kill -KILL "$B4B_SHIM" 2>/dev/null
expect_regex "B4b.1 the SIGKILLed shim's request is still unended on disk" '^[0-9]+ $' "$(places)"
B4B_OUT="$(bk -- 'echo reclaimed' 2>&1)"; B4B_RC=$?
expect_status "B4b.2 the next ask is admitted" 0 "$B4B_RC"
expect_contains "B4b.3 …and runs" "reclaimed" "$B4B_OUT"
expect_absent "B4b.4 …without waiting" "waits for its turn" "$B4B_OUT"

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

# B12. A store that cannot be written (review 4 F5). The gate manages throughput, it is not a
# guard: an ordinary run goes on UNADMITTED at once, with one line naming the store. A
# whole-machine run does not run, because a timing result taken without the machine is
# worth nothing: it refuses at once, naming the store.
newrow b12
MW=6
mkdir -p "$ST"; chmod 555 "$ST"
B12_T0=$SECONDS
B12_OUT="$(bk -- 'echo ran-unadmitted; exit 3' 2>&1)"; B12_RC=$?
B12_DT=$((SECONDS - B12_T0))
expect_status "B12.1 an unwritable store: an ordinary run runs its command anyway" 3 "$B12_RC"
expect_contains "B12.2 …which ran" "ran-unadmitted" "$B12_OUT"
expect_true "B12.3 …at once (took ${B12_DT}s)" test "$B12_DT" -le 2
B12_LINE="$(printf '%s\n' "$B12_OUT" | grep -F "booked:" | grep -F "$ST")"
expect_nonempty "B12.4 the shim's line names the store" "$B12_LINE"
expect_contains "B12.5 …and says the command runs unadmitted" "unadmitted" "$B12_LINE"
expect_eq "B12.6 …and it is the shim's only line about it" 1 "$(printf '%s\n' "$B12_OUT" | grep -F "booked:" | grep -c -F "$ST")"
B12_T0=$SECONDS
B12_OUT="$(bk --quiet -- "touch $ROW/q.ran" 2>&1)"; B12_RC=$?
B12_DT=$((SECONDS - B12_T0))
expect_status "B12.7 a whole-machine run on the same store refuses (69)" 69 "$B12_RC"
expect_false "B12.8 …and its command never ran" test -e "$ROW/q.ran"
expect_true "B12.9 …at once (took ${B12_DT}s)" test "$B12_DT" -le 2
expect_contains "B12.10 …naming the store" "$ST" "$B12_OUT"
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

# ═══════════════════════════════════════════════════════════════════ §LIVE
section "LIVE — the liveness rule and the claim, what lib/slots.sh keeps"

# L1. The rule: a holder is a live pid that started when its record says (review 4 F2).
newrow l1
sleep 60 & L1_LIVE=$!; BG="$BG $L1_LIVE"
L1_START="$( . "$SLOTS"; _slots_since "$L1_LIVE" )"
L1_PS="$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$L1_LIVE" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//')"
expect_nonempty "L1.1 _slots_since reads a live process's start" "$L1_START"
expect_eq "L1.2 …as ps prints it, one space between fields" "$L1_PS" "$L1_START"
expect_true "L1.3 a live pid with its own start is live" bash -c '. "$1"; _slots_live "$2" "$3"' _ "$SLOTS" "$L1_LIVE" "$L1_START"
expect_false "L1.4 the same live pid with another start (a reused pid) is not" \
  bash -c '. "$1"; _slots_live "$2" "Thu Jan 1 00:00:00 2015"' _ "$SLOTS" "$L1_LIVE"
expect_true "L1.5 a record with no start (an older bionic) falls back to kill -0" \
  bash -c '. "$1"; _slots_live "$2" ""' _ "$SLOTS" "$L1_LIVE"
L1_DEAD="$(dead_pid)"
expect_false "L1.6 a dead pid is not live, whatever its record says" \
  bash -c '. "$1"; _slots_live "$2" ""' _ "$SLOTS" "$L1_DEAD"
mkdir -p "$ROW/claim"; printf '%s\n' "$L1_START" > "$ROW/claim/since"
expect_true "L1.7 _slots_holds reads the start from the claim directory" \
  bash -c '. "$1"; _slots_holds "$2" "$3"' _ "$SLOTS" "$ROW/claim" "$L1_LIVE"
printf 'Thu Jan 1 00:00:00 2015\n' > "$ROW/claim/since"
expect_false "L1.8 …and a claim whose start is not the pid's is not held" \
  bash -c '. "$1"; _slots_holds "$2" "$3"' _ "$SLOTS" "$ROW/claim" "$L1_LIVE"
kill "$L1_LIVE" 2>/dev/null; wait "$L1_LIVE" 2>/dev/null

# L2. Claimers racing for one directory: exactly one wins, round after round. The gate's lock
# is this claim.
cat > "$TMPROOT/taker.sh" <<'TAKER'
. "$1"
while [ ! -f "$2/start" ]; do sleep 0.01; done
if _slots_claim "$2/claim" "$$"; then echo WIN > "$2/res.$$"; else echo LOSE > "$2/res.$$"; fi
TAKER
race_round() {  # <lib> <dir> — six claimers, one directory; prints the number of winners
  local lib="$1" d="$2" i n=0 pids=""
  mkdir -p "$d"
  for i in 1 2 3 4 5 6; do
    "$BASH" "$TMPROOT/taker.sh" "$lib" "$d" &
    pids="$pids $!"; BG="$BG $!"
  done
  touch "$d/start"
  while [ "$(ls "$d"/res.* 2>/dev/null | wc -l | tr -d ' ')" -lt 6 ] && [ "$n" -lt 400 ]; do
    n=$((n + 1)); sleep 0.05
  done
  grep -l WIN "$d"/res.* 2>/dev/null | wc -l | tr -d ' '
  for i in $pids; do wait "$i" 2>/dev/null; done
}
L2_BAD=""; L2_SEEN=""
for _r in 1 2 3 4 5; do
  _w="$(race_round "$SLOTS" "$TMPROOT/l2/r$_r")"
  L2_SEEN="$L2_SEEN $_w"
  [ "$_w" = "1" ] || L2_BAD="$L2_BAD round$_r=$_w"
done
expect_eq "L2.1 every round of six claimers for one directory had exactly one winner (saw:$L2_SEEN)" \
  "" "$L2_BAD"
expect_regex "L2.2 …and the rounds ran (one result per round)" '^( 1){5}$' "$L2_SEEN"
# Mutation control: a non-exclusive claim lets more than one claimer in.
L2M="$(mutant_tree l2-mut)"
anchor "$L2M/scripts/lib/slots.sh" 'mkdir "$place" 2>/dev/null || return 1' 1
sed -i.bak 's|mkdir "$place" 2>/dev/null \|\| return 1|mkdir -p "$place" 2>/dev/null \|\| return 1|' \
  "$L2M/scripts/lib/slots.sh"
expect_true "L2.3 the mutant library still parses" bash -n "$L2M/scripts/lib/slots.sh"
L2M_W="$(race_round "$L2M/scripts/lib/slots.sh" "$TMPROOT/l2/mut")"
expect_true "L2.4 MUTATION: with mkdir -p the same race has more than one winner (saw $L2M_W)" \
  test "${L2M_W:-0}" -gt 1
expect_eq "L2.5 the place count, the take loop and the wait are gone from the library" "" \
  "$(grep -E '^(slots_take|slots_take_all|slots_release|slots_count|_slots_max_wait|_slots_poll)\(\)' "$SLOTS")"
expect_nonempty "L2.6 …while the liveness rule stays (L2.5 reads the same file)" \
  "$(grep -E '^_slots_live\(\)' "$SLOTS")"

# L3. The take-over lib/line.sh's publish lock uses (`_slots_take_one`, B3 and B3b before T12): a
# claim whose holder is dead, or one left with no holder and older than the orphan line, is
# reclaimed once; a live holder's, or a fresh claim still being written, is not.
newrow l3
l3_take() {  # <dir> — _slots_take_one on <dir> for this shell; prints rc and the pid it holds
  bash -c '. "$1"; _slots_take_one "$2" "$3" "$$" l3; echo "$? $(cat "$3/pid" 2>/dev/null)"' _ "$SLOTS" "$ROW" "$1"
}
L3_DEAD="$(dead_pid)"
mkdir -p "$ROW/dead"; printf '%s\n' "$L3_DEAD" > "$ROW/dead/pid"
L3_OUT="$(l3_take "$ROW/dead")"
expect_regex "L3.1 a claim whose holder is dead is reclaimed (rc 0) for the new holder" '^0 [0-9]+$' "$L3_OUT"
expect_ne "L3.2 …which now names the taker, not the dead holder" "0 $L3_DEAD" "$L3_OUT"
sleep 60 & L3_LIVE=$!; BG="$BG $L3_LIVE"
mkdir -p "$ROW/live"; printf '%s\n' "$L3_LIVE" > "$ROW/live/pid"
expect_regex "L3.3 a live holder's claim is not taken (rc 1)" '^1 ' "$(l3_take "$ROW/live")"
expect_eq "L3.4 …and it still names that holder" "$L3_LIVE" "$(cat "$ROW/live/pid")"
mkdir -p "$ROW/fresh"
expect_regex "L3.5 a fresh claim with no holder yet is a take in progress, left alone (rc 1)" '^1' "$(l3_take "$ROW/fresh")"
touch -t 202001010000 "$ROW/fresh"
expect_regex "L3.6 …the same claim aged past the orphan line is reclaimed (rc 0)" '^0 [0-9]+$' "$(l3_take "$ROW/fresh")"
kill "$L3_LIVE" 2>/dev/null; wait "$L3_LIVE" 2>/dev/null

# ═══════════════════════════════════════════════════════════════════ §QUIET
section "QUIET — the whole machine: ask, hold, settle, re-read, void"

# Q1. A whole-machine run waits at the gate while another run is admitted.
newrow q1
bk -- "$(gate a)" > "$ROW/a.out" 2>&1 & BG="$BG $!"; Q1_A=$!
wait_file "$ROW/a.started"
bk --quiet -- "touch $ROW/q.started" > "$ROW/q.out" 2>&1 & BG="$BG $!"; Q1_Q=$!
expect_true "Q1.1 the whole-machine run prints that it waits at the gate" wait_text "$ROW/q.out" "waits for its turn"
expect_contains "Q1.2 …as a whole request" "(whole " "$(grep -m1 -F 'waits for its turn' "$ROW/q.out")"
expect_false "Q1.3 …and has not started while the other run is admitted" test -e "$ROW/q.started"
touch "$ROW/a.go"
expect_true "Q1.4 it starts once the other run ends" wait_file "$ROW/q.started"
wait "$Q1_Q"; Q1_RC=$?
expect_status "Q1.5 …and exits with its command's code" 0 "$Q1_RC"
wait "$Q1_A" 2>/dev/null

# Q2. While the whole machine is held, a new ordinary ask waits.
newrow q2
bk --quiet -- "echo Q >> $ROW/order; $(gate q)" > "$ROW/q.out" 2>&1 & BG="$BG $!"; Q2_Q=$!
wait_file "$ROW/q.started"
bk -- "echo C >> $ROW/order; touch $ROW/c.started" > "$ROW/c.out" 2>&1 & BG="$BG $!"; Q2_C=$!
Q2_WAITED=0; wait_text "$ROW/c.out" "waits for its turn" 5 && Q2_WAITED=1
expect_eq "Q2.1 an ordinary ask during a whole-machine hold waits" 1 "$Q2_WAITED"
expect_false "Q2.2 …and the ordinary command has not run while the hold runs" test -e "$ROW/c.started"
touch "$ROW/q.go"
wait_file "$ROW/c.started" 10
expect_true "Q2.3 …then it runs" test -e "$ROW/c.started"
expect_eq "Q2.4 …after the whole-machine command" "Q C" "$(tr '\n' ' ' < "$ROW/order" | sed 's/ $//')"
wait "$Q2_Q" "$Q2_C" 2>/dev/null

# Q3. It does not start above the settled load; it starts once the load settles. A load that
# never settles within the ceiling gets the runner's answer: one run, void.
newrow q3
printf '99.0\n' > "$LOADF"; MW=2
Q3_OUT="$(bk --quiet -- "touch $ROW/q.ran" 2>&1)"; Q3_RC=$?
expect_status "Q3.1 above the settled line the settle gives up at the ceiling, and the run is void (75)" \
  75 "$Q3_RC"
expect_true "Q3.2 …its command ran once, after the ceiling" test -e "$ROW/q.ran"
expect_contains "Q3.3 …and says it was waiting for the load to settle" "settle" "$Q3_OUT"
rm -f "$ROW/q.ran"
MW=20
( sleep 1; printf '0.00\n' > "$LOADF" ) >/dev/null 2>&1 & BG="$BG $!"
Q3_OUT="$(bk --quiet -- "touch $ROW/q.ran" 2>&1)"; Q3_RC=$?
expect_status "Q3.4 once the load settles it runs" 0 "$Q3_RC"
expect_true "Q3.5 …its command" test -e "$ROW/q.ran"
expect_contains "Q3.6 …after noting the wait for the load" "settle" "$Q3_OUT"

# Q4. A load that rose during the run voids it: `void`, settle, retry; twice, then exit 75.
newrow q4
Q4_CMD="echo run >> $ROW/runs; printf '99.0\n' > $LOADF; ( sleep 1.5; printf '0.00\n' > $LOADF ) >/dev/null 2>&1 &"
Q4_OUT="$(bk --quiet -- "$Q4_CMD" 2>&1)"; Q4_RC=$?
expect_status "Q4.1 a run voided every time exits 75, not the command's code" 75 "$Q4_RC"
expect_regex "Q4.2 …printing void" '(^|[^a-z])void([^a-z]|$)' "$Q4_OUT"
expect_eq "Q4.3 …after the first run and two retries" 3 "$(wc -l < "$ROW/runs" | tr -d ' ')"
expect_eq "Q4.4 …all under one whole request, ended afterwards" "1 " "$(nreq) $(places)"
# Once only: the second run is clean, so the shim answers with the command's own code.
newrow q4b
Q4B_CMD="if [ ! -f $ROW/runs ]; then printf '99.0\n' > $LOADF; ( sleep 1.5; printf '0.00\n' > $LOADF ) >/dev/null 2>&1 & fi; echo run >> $ROW/runs; exit 4"
Q4B_OUT="$(bk --quiet -- "$Q4B_CMD" 2>&1)"; Q4B_RC=$?
expect_status "Q4.5 a run voided once and clean on retry exits with the command's code" 4 "$Q4B_RC"
expect_eq "Q4.6 …having run twice" 2 "$(wc -l < "$ROW/runs" | tr -d ' ')"
expect_regex "Q4.7 …and printed void for the first" '(^|[^a-z])void([^a-z]|$)' "$Q4B_OUT"

# Q5. A whole-machine run nested in an ordinary admitted command is believed under the parent's
# admission: it runs, takes no number, and still settles (the hold is not the whole machine).
newrow q5
Q5_OUT="$(bk -- "bash $BOOKED --quiet -- 'echo inner-ran'" 2>&1)"; Q5_RC=$?
expect_status "Q5.1 a whole-machine run nested in a booked command completes" 0 "$Q5_RC"
expect_contains "Q5.2 …running its command" "inner-ran" "$Q5_OUT"
expect_eq "Q5.3 …under its parent's admission: one request in all" "1" "$(nreq)"

# Q7. A whole-machine run inside a whole-machine hold already has the machine.
newrow q7
MW=5
Q7_OUT="$(bk --quiet -- "bash $BOOKED --quiet -- 'echo nested-quiet'" 2>&1)"; Q7_RC=$?
expect_status "Q7.1 a whole-machine run nested in one completes" 0 "$Q7_RC"
expect_contains "Q7.2 …and runs" "nested-quiet" "$Q7_OUT"
expect_eq "Q7.3 …taking no number of its own" "1" "$(nreq)"

# Q8. One ceiling covers every wait of one call (review 4 F3): the wait at the gate, the settle
# and every void retry share it, counted from the shim's start. The other run ends at half the
# ceiling, so the wait always completes inside it and the two shapes stay apart: one ceiling
# ends at 8 s, a fresh one per wait at 4 + 8 s.
newrow q8
MW=8
bk -- "$(gate a)" > "$ROW/a.out" 2>&1 & BG="$BG $!"; Q8_A=$!
wait_file "$ROW/a.started"
( sleep 4; touch "$ROW/a.go" ) >/dev/null 2>&1 & BG="$BG $!"
printf '99.0\n' > "$LOADF"
Q8_T0=$SECONDS
Q8_OUT="$(bk --quiet -- "touch $ROW/q.ran" 2>&1)"; Q8_RC=$?
Q8_DT=$((SECONDS - Q8_T0))
expect_status "Q8.1 a wait then a load that never settles gives up, and the one run is void (75)" 75 "$Q8_RC"
expect_true "Q8.2 …running its command once" test -e "$ROW/q.ran"
expect_contains "Q8.3 …after waiting at the gate" "waits for its turn" "$Q8_OUT"
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
expect_eq "Q10.4 …and its request was ended afterwards" "" "$(places)"
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
( cd "$ROW/repo" && env "${GE[@]}" BIONIC_GATE_DIR="$ST" \
    bash "$BOOKED" -- 'touch new1; exit 3' ) >/dev/null 2>&1; S1_RC=$?
expect_status "S1.1 the shim still answers the command's code" 3 "$S1_RC"
S1_LINE="$(tail -1 "$S1_STAMPS" 2>/dev/null)"
expect_nonempty "S1.2 a stamp was appended to the tree's git dir" "$S1_LINE"
expect_regex "S1.3 the stamp is stamp/v1 with head, the PRE-run dirty count, rc, ISO-UTC time and the command" \
  "^stamp/v1\\|head=${S1_HEAD}\\|dirty=1\\|rc=3\\|at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\|cmd=touch new1; exit 3\$" \
  "$S1_LINE"

S1_BEFORE="$(wc -l < "$S1_STAMPS" | tr -d ' ')"
( cd "$ROW/repo" && env "${GE[@]}" BIONIC_GATE_DIR="$ST" \
    bash "$BOOKED" -- 'echo a | cat' ) >/dev/null 2>&1
S1_AFTER="$(wc -l < "$S1_STAMPS" | tr -d ' ')"
expect_eq "S2.1 a second run appends one line" "$((S1_BEFORE + 1))" "$S1_AFTER"
S2_LINE="$(tail -1 "$S1_STAMPS")"
expect_eq "S2.2 a pipe in the command is replaced, so the line keeps six fields" \
  6 "$(printf '%s' "$S2_LINE" | awk -F'|' '{print NF}')"
expect_regex "S2.3 …and the command is still legible" 'cmd=echo a .* cat$' "$S2_LINE"
expect_regex "S2.4 …with dirty counting the file the previous command made" '\|dirty=2\|' "$S2_LINE"

S3_LONG=": $(printf 'x%.0s' $(seq 1 200))"
( cd "$ROW/repo" && env "${GE[@]}" BIONIC_GATE_DIR="$ST" \
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
( cd "$ROW/wt" && env "${GE[@]}" BIONIC_GATE_DIR="$ST" \
    bash "$BOOKED" -- 'true' ) >/dev/null 2>&1
expect_regex "S5.2 the stamp lands in the worktree's git dir with its head" \
  "head=$(git -C "$ROW/wt" rev-parse HEAD)\\|" "$(tail -1 "$S5_WT_STAMPS" 2>/dev/null)"
expect_false "S5.3 …and not in the main checkout's" test -e "$S5_MAIN_STAMPS"

# S6. A voided timing check is stamped with the void code, so it never reads as green.
newrow s6
mkrepo "$ROW/repo"
( cd "$ROW/repo" && env "${GE[@]}" BIONIC_GATE_DIR="$ST" \
    BIONIC_LOAD_NOW_FILE="$LOADF" \
    bash "$BOOKED" --quiet -- "printf '99.0\n' > $LOADF; ( sleep 1.5; printf '0.00\n' > $LOADF ) >/dev/null 2>&1 &" ) \
  >/dev/null 2>&1; S6_RC=$?
expect_status "S6.1 the voided run exits 75" 75 "$S6_RC"
expect_regex "S6.2 …and its stamp carries rc=75" '\|rc=75\|' "$(tail -1 "$(stamps_of "$ROW/repo")" 2>/dev/null)"
# A voided run that FAILED is stamped with its own code (review 12 F2, A-T50.1): still red, and
# red for its own reason. The stamp has no field for the void, and its shape does not change.
( cd "$ROW/repo" && env "${GE[@]}" BIONIC_GATE_DIR="$ST" \
    BIONIC_LOAD_NOW_FILE="$LOADF" \
    bash "$BOOKED" --quiet -- "printf '99.0\n' > $LOADF; ( sleep 1.5; printf '0.00\n' > $LOADF ) >/dev/null 2>&1 & exit 3" ) \
  >/dev/null 2>&1; S6_RC=$?
expect_status "S6.3 a voided run that failed exits with its own code (3)" 3 "$S6_RC"
expect_regex "S6.4 …and its stamp carries rc=3, not rc=75" '\|rc=3\|' "$(tail -1 "$(stamps_of "$ROW/repo")" 2>/dev/null)"

# S7. The tree's own `.bionic` link is not dirt. With no ignore entry git lists it as
# `?? .bionic`; the stamp skips exactly that line when `.bionic` is a symlink, and counts
# every other untracked path — and a `.bionic` that is a plain file — as before.
newrow s7
st_run() {  # <tree> <command> — one booked run in <tree>
  ( cd "$1" && env "${GE[@]}" BIONIC_GATE_DIR="$ST" \
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
  ( cd "$ROW/main" && env "${GE[@]}" BIONIC_GATE_DIR="$ST" \
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
  ( cd "$ROW/repo" && env "${GE[@]}" BIONIC_GATE_DIR="$ST" \
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

# S11. A RUN THAT NEVER FINISHED STILL STAMPS (wave-26 T61, critic 3 S5). A suite the gate did not
# admit within its call's limit (75, under --max-wait or --kill-after alike) or signalled while it
# waited (128+n) used to leave no line, so "a green, b never ran" at one head read as a's proof
# alone. Each of these ends stamps the code it ended on and the suites it was handed; the land
# refuses on it and names the suite. A usage error (exit 2) still stamps nothing (S10.7). The
# machine is planted over the share, so the gate admits nothing.
newrow s11
mkrepo "$ROW/repo"
S11_STAMPS="$(stamps_of "$ROW/repo")"
s11_run() {  # <shim option>... — one booked run in the repo, on a machine the gate admits nothing on
  ( cd "$ROW/repo" && env "${GE[@]}" BIONIC_GATE_DIR="$ST" BIONIC_PROBE_USED_PCT=95 \
      bash "$BOOKED" "$@" -- "touch $ROW/s11.ran" ) >"$ROW/out" 2>&1
}
s11_run --max-wait 1 --suites b.test.sh; S11_RC=$?
expect_status "S11.1 not admitted within its limit: the shim exits 75" 75 "$S11_RC"
expect_false "S11.1 …and its command never ran" test -e "$ROW/s11.ran"
expect_regex "S11.2 …and it stamped that end: rc=75, with the suite it was handed" \
  "^stamp/v1\\|head=$(git -C "$ROW/repo" rev-parse HEAD)\\|dirty=0\\|rc=75\\|at=[^|]*\\|suites=b\\.test\\.sh\\|cmd=touch " \
  "$(tail -1 "$S11_STAMPS" 2>/dev/null)"
s11_run --kill-after 1 --suites c.test.sh; S11_RC=$?
expect_status "S11.3 its short limit spent waiting: 75, not 124 (a wait never ends in a kill)" 75 "$S11_RC"
expect_regex "S11.4 …and it stamped rc=75 with its suite" \
  "\\|rc=75\\|at=[^|]*\\|suites=c\\.test\\.sh\\|cmd=touch " "$(tail -1 "$S11_STAMPS" 2>/dev/null)"
( cd "$ROW/repo" && exec env "${GE[@]}" BIONIC_GATE_DIR="$ST" BIONIC_PROBE_USED_PCT=95 \
    bash "$BOOKED" --suites d.test.sh -- "touch $ROW/s11.ran" ) \
  >"$ROW/sig.out" 2>&1 & S11_S=$!; BG="$BG $S11_S"
expect_true "S11.5 a run waiting at the gate says so" wait_text "$ROW/sig.out" "waits for its turn"
kill -TERM "$S11_S" 2>/dev/null; wait "$S11_S" 2>/dev/null; S11_RC=$?
expect_status "S11.5 …and signalled while it waits it ends 143" 143 "$S11_RC"
expect_regex "S11.6 …and it stamped rc=143 with its suite, though it never ran" \
  "\\|rc=143\\|at=[^|]*\\|suites=d\\.test\\.sh\\|cmd=touch " "$(tail -1 "$S11_STAMPS" 2>/dev/null)"
expect_false "S11.6 …its command never ran" test -e "$ROW/s11.ran"
expect_eq "S11.7 three ends, three lines" "3" "$(grep -c . "$S11_STAMPS" 2>/dev/null)"
expect_contains "S11.8 the 75 says to run the command again, naming it" "run again: touch $ROW/s11.ran" \
  "$(cat "$ROW/out")"

# ══════════════════════════════════════════════════════════════════ §NESTED-ENV
section "NESTED-ENV — a command runs under its own admission and a nested one never waits on its parent"

newrow n1
N1_SEEN="$(bk -- 'printf %s "${BIONIC_GATE_ADMIT:-unset}"' 2>/dev/null)"
expect_eq "N1.1 the command sees BIONIC_GATE_ADMIT naming its own request" "$(ls "$ST/requests" 2>/dev/null | grep '^[0-9]' | head -n 1)" "$N1_SEEN"
expect_regex "N1.2 …a request id" '^[0-9]+$' "$N1_SEEN"

# N2. BIONIC_SLOT_HELD=1 in the environment skips nothing (wave-28 T12, AC-2.13): on a machine
# the gate admits nothing on, the shim asks, waits, and ends 75 with nothing run.
newrow n2
N2_OUT="$( cd "$ROW" && env "${GE[@]}" BIONIC_SLOT_HELD=1 BIONIC_GATE_DIR="$ST" BIONIC_PROBE_USED_PCT=95 \
  bash "$BOOKED" --max-wait 1 -- "touch $ROW/n2.ran" 2>&1)"; N2_RC=$?
expect_status "N2.1 a run marked held still asks, and is not admitted (75)" 75 "$N2_RC"
expect_false "N2.2 …and does not run" test -e "$ROW/n2.ran"
expect_eq "N2.3 …having taken a number" "1" "$(nreq)"

# N3. A shim inside a shim, where the gate admits one at a time: the inner run is believed under
# its parent's admission and does not wait on it.
newrow n3
N3_OUT="$(bk -- "bash $BOOKED -- 'echo inner'" 2>&1)"; N3_RC=$?
expect_status "N3.1 a booked command nested in one completes" 0 "$N3_RC"
expect_eq "N3.2 …at once, without waiting" "inner" "$N3_OUT"
expect_eq "N3.3 …and took no number of its own" "1" "$(nreq)"

# N4. BIONIC_QUIET=1 in the environment is --quiet.
newrow n4
printf '99.0\n' > "$LOADF"; MW=1
N4_OUT="$( cd "$ROW" && env "${GE[@]}" BIONIC_QUIET=1 BIONIC_GATE_DIR="$ST" BIONIC_SETTLE_MAX_WAIT=1 \
  BIONIC_LOAD_NOW_FILE="$LOADF" bash "$BOOKED" -- "touch $ROW/q.ran" 2>&1)"; N4_RC=$?
expect_status "N4.1 BIONIC_QUIET=1 waits for a settled load like --quiet (gives up, void: 75)" 75 "$N4_RC"
expect_contains "N4.2 …saying the load never settled" "never settled" "$N4_OUT"
N4_OUT="$(bk -- "touch $ROW/plain.ran" 2>&1)"; N4_RC=$?
expect_status "N4.3 without it, the same load does not hold an ordinary run" 0 "$N4_RC"
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
H2_OUT="$(bk --shell "$H_SH" -- 'printf %s "${BIONIC_GATE_ADMIT:-unset}"' 2>/dev/null)"
expect_regex "H2.1 under --shell the command still runs under its own admission" '^[0-9]+$' "$H2_OUT"
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
( cd "$ROW/repo" && env "${GE[@]}" BIONIC_GATE_DIR="$ST" \
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
( cd "$ROW/repo" && env "${GE[@]}" BIONIC_GATE_DIR="$ST" \
    bash "$BOOKED" --kill-after 1 -- 'sleep 20' ) >/dev/null 2>&1; K3_RC=$?
expect_status "K3.1 the killed run exits 124" 124 "$K3_RC"
expect_regex "K3.2 …and its stamp says rc=124" '\|rc=124\|' "$(tail -1 "$K3_STAMPS" 2>/dev/null)"

# K4. THE LIMIT COVERS THE WAIT AT THE GATE (review 8 F2, A-T44.2; wave-28 T12, AC-2.6). The
# machine is planted over the share, so the command cannot start inside its limit: the shim
# gives up AT the limit with the gate's line and 75, never 124 (a wait never ends in a kill),
# and runs nothing.
newrow k4
mkrepo "$ROW/repo"
K4_STAMPS="$(stamps_of "$ROW/repo")"
K4_T0=$SECONDS
K4_OUT="$( cd "$ROW/repo" && env "${GE[@]}" BIONIC_GATE_DIR="$ST" BIONIC_PROBE_USED_PCT=95 \
    bash "$BOOKED" --kill-after 2 -- "touch $ROW/k4.ran" 2>&1 )"; K4_RC=$?
K4_DT=$(( SECONDS - K4_T0 ))
expect_status "K4.1 a short command not admitted inside its limit exits 75" 75 "$K4_RC"
expect_true "K4.2 …at its 2 s limit (took ${K4_DT}s)" test "$K4_DT" -lt 10
expect_contains "K4.3 …it waited at the gate" "waits for its turn" "$K4_OUT"
expect_contains "K4.4 …and says the gate did not admit it within its limit" \
  "booked: the gate did not admit this command within 2s" "$K4_OUT"
expect_absent "K4.4b …not that it was stopped at its limit: nothing ran to stop" "over the short limit" "$K4_OUT"
expect_false "K4.5 …and its command never ran" test -e "$ROW/k4.ran"
expect_eq "K4.6 …and it stamped once, rc=75, though it ran nothing" "1 rc=75" \
  "$(grep -c . "$K4_STAMPS" 2>/dev/null) $(tail -1 "$K4_STAMPS" 2>/dev/null | tr '|' '\n' | grep '^rc=')"
( cd "$ROW/repo" && env "${GE[@]}" BIONIC_GATE_DIR="$ST" \
    bash "$BOOKED" --kill-after 5 -- "touch $ROW/k4.ran" ) >/dev/null 2>&1; K4_RC=$?
expect_status "K4.7 with room on the machine the same call runs" 0 "$K4_RC"
expect_true "K4.8 …its command ran" test -e "$ROW/k4.ran"
expect_eq "K4.9 …and it stamped its own line, rc=0 (beside K4.6)" "2 rc=0" \
  "$(grep -c . "$K4_STAMPS" 2>/dev/null) $(tail -1 "$K4_STAMPS" 2>/dev/null | tr '|' '\n' | grep '^rc=')"

# K5. THE KILL IS TIMED FROM THE SHIM'S START, so the wait spends the limit. Another run is
# admitted for 4 s and the command needs 4 s: inside a 6 s limit counted from the run it would
# finish (at about 8 s, 2 s to spare); counted from the shim's start it is stopped at 6 s.
newrow k5
MW=30
K5_H="$( ( sleep 4 >/dev/null 2>&1 & printf '%s' "$!" ) )"
plant_req 1 "$K5_H"
K5_OUT="$(bk --kill-after 6 -- 'sleep 4; echo finished' 2>&1)"; K5_RC=$?
expect_contains "K5.1 the command waited at the gate" "waits for its turn" "$K5_OUT"
expect_status "K5.2 …and was stopped at 6 s from the shim's start: exit 124" 124 "$K5_RC"
expect_contains "K5.3 …with the short-limit line" "over the short limit" "$K5_OUT"
expect_eq "K5.4 …before it could finish: no line of its own output reads finished (the gate's line names the command)" \
  "0" "$(printf '%s\n' "$K5_OUT" | grep -cx finished)"

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
MW=5
bk -- "(sleep 30 > /dev/null 2>&1 & echo \$! > $ROW/orphan.kid); touch $ROW/k.started; sleep 30" > "$ROW/k.out" 2>&1 &
BG="$BG $!"; K7_BG=$!
wait_file "$ROW/k.started"
K7_SHIM="$(held_pids)"; K7_SHIM="${K7_SHIM% }"
expect_regex "K7.1 the running command's shim holds the admission" '^[0-9]+$' "$K7_SHIM"
K7_KID="$(cat "$ROW/orphan.kid" 2>/dev/null)"
expect_regex "K7.2 the orphaned child recorded its pid" '^[0-9]+$' "$K7_KID"
kill -TERM "$K7_SHIM" 2>/dev/null
wait "$K7_BG" 2>/dev/null
expect_true "K7.3 TERM to the shim kills the orphan too, outside the tree but inside the group" \
  bash -c "for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 ${K7_KID:-999999} 2>/dev/null || exit 0; sleep 0.2; done; exit 1"
expect_eq "K7.4 …and its request was ended" "" "$(places)"

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
MW=5
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
    exec env "${GE[@]}" BIONIC_GATE_DIR="$ST" \
      BIONIC_LOAD_NOW_FILE="$LOADF" \
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
  expect_eq "K8.0 [$_sig] the shim holds the admission" 1 "$K8_SHIM_OK"
  expect_regex "K8.1 [$_sig] the command and its orphan were running" '^[0-9]+ [0-9]+$' "$K8_PID $K8_KID"
  expect_eq "K8.2 [$_sig] the command saw the signal the shim took, not TERM" "got-$_sig" "$K8_SAW"
  expect_status "K8.3 [$_sig] the shim exits 128 + the signal's number" "${_k8#*:}" "$K8_RC"
  expect_true "K8.4 [$_sig] the command is gone" gone "$K8_PID"
  expect_true "K8.5 [$_sig] …and so is its orphan, outside its tree but inside its group" gone "$K8_KID"
  expect_eq "K8.6 [$_sig] …and its request was ended (beside K7.1's held admission)" "" "$(places)"
  k8_reap
done
for _sig in INT QUIT; do
  k8_drive "$_sig" --shell "$H_SH"
  expect_eq "K8.7 [$_sig] under --shell ${H_SH##*/} the command saw the signal too" "got-$_sig" "$K8_SAW"
  expect_true "K8.8 [$_sig] …and it is gone" gone "$K8_PID"
  expect_eq "K8.9 [$_sig] …with its request ended" "" "$(places)"
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
# U1. --unbooked IS GONE (the lead's ruling at T44): only a suite is wrapped, so the shim has no
# command to run without asking. The flag is now an unknown option.
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
