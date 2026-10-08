#!/bin/bash
# tests/booked.test.sh — THE DETACHED SHIM (epic-23 wave-30-efficiency T8; D6, Δ5, Δ5a;
# REQ-3 AC-3.1, AC-3.4, AC-3.6, AC-3.8).
#
# WHAT IT COVERS. `payload/scripts/booked.sh --detach` forks its whole tail (ask → run → end →
# stamp) into a session of its own, so a run outlives the call that started it. The caller prints
# one line, `booked: started pid=<pid> log=<path> run=<id>`, and exits 0. These rows kill the
# CALLER's whole process group with SIGKILL, which runs no trap, and then read what the run left
# behind: a log whose last line is `rc=<n>`, the `.pid` written at start, the stamp in the tree's
# own git dir, the gate's request ended by the run itself, and the run record on the roster.
#
#   §DETACH  AC-3.1, AC-3.6, AC-3.8 — the run survives its caller's group and ends `rc=<n>`; its
#            place is held by the detached pid until the end; the stamp, the end and the roster
#            record are written with nobody waiting; the progress file is exported.
#   §LOG2    AC-3.4 — a second attempt writes `…-2.log` and never truncates the first.
#
# The gate (gate.test.sh, slots.test.sh) owns the foreground shim; nothing here re-proves it.
#
# FIXTURE FIDELITY ("Fixture fidelity", .claude/rules/test-harness.md). The caller is a real
# process group leader killed by a real SIGKILL to the whole group, the shape a harness gives a
# Bash call and takes away at a /clear; the detached side is the real shim under the real perl;
# the tree is a real git worktree with the `.bionic` link spawn-worktree plants; the roster is
# world.sh's, written by the real roster_row. SYNTHESIZED: the commands run (a mark, a hold on a
# go-file, an `exit 3`), which stand for a suite and pin nothing a suite would change.
#
# ANTI-VACUITY ("Anti-vacuity"). DT.0 is the control the whole section stands on: the same kill
# over a command left in the caller's group takes the command with it, so a later rc line is a
# run that escaped, not a kill that missed. Every empty readback (DT.9, DT.23) sits beside a
# positive on the same file (DT.9b, DT.18).
#
# HERMETIC. Every run happens in the model world (tests/lib/world.sh): its own gate store, its own
# fixture repository with row trees T1 and T2 and a roster naming wx-T1 and wx-T2 under WORLD_SID.
#
# Usage: bash tests/booked.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="$BIONIC_SCRIPTS_DIR"
BOOKED="$REPO/payload/scripts/booked.sh"

. "$(dirname "$0")/lib/world.sh"
world_machine 8 8192 10 0.5
unset BIONIC_GATE_ADMIT BIONIC_GATE_AGENT BIONIC_QUIET BIONIC_TEST_PROGRESS _BIONIC_TEST_PROGRESS_FILE
export BIONIC_GATE_POLL=0.1
export CLAUDE_CODE_SESSION_ID="$WORLD_SID"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1

D="$WORLD_ROOT/d"; mkdir -p "$D"

# bk_wait <seconds> <test...> — polls every 0.1 s until the test passes; rc 1 when time runs out.
bk_wait() {
  local n=$(( $1 * 10 )) i=0
  shift
  while ! "$@" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -lt "$n" ] || return 1
    sleep 0.1
  done
  return 0
}
bk_has() { [ -s "$1" ]; }
bk_grep() { grep -q "$1" "$2"; }
bk_last_rc() { tail -n 1 "$1" 2>/dev/null | grep -q '^rc=[0-9][0-9]*$'; }
bk_dead() { ! kill -0 "$1"; }

# bk_caller <name> <dir> <booked args...> — THE CALLER, in a process group of its own (`set -m`),
# as a harness Bash call is: it runs the shim, then lingers, so the kill below lands on a live
# caller and not on one that already left. Sets BK_PG to the group's id; its output goes to
# $D/<name>.out.
BK_PG=""
bk_caller() {
  local name="$1" dir="$2"
  shift 2
  set -m
  ( cd "$dir" && bash "$BOOKED" "$@"; echo "caller-rc=$?"; sleep 60 ) > "$D/$name.out" 2>&1 &
  BK_PG=$!
  set +m
}
# bk_started <name> <field> — a field of the caller's `booked: started` line.
bk_started() { sed -n "s/^booked: started .*$2=\\([^ ]*\\).*/\\1/p" "$D/$1.out" | head -n 1; }
bk_kill_group() { kill -KILL -- "-$1" 2>/dev/null; bk_wait 5 bk_dead "$1"; }

WR="$(world_repo)"
T1="$WR/.worktrees/T1"
expect_true "(fixture) the world repository and its row tree T1 exist" test -d "$T1/.git" -o -f "$T1/.git"
ROSTER="$WR/.bionic/tmp/roster-$WORLD_SID.state"
expect_true "(fixture) the world's roster exists and names wx-T1" grep -q '|name=wx-T1|' "$ROSTER"

# =====================================================================================
section "§DETACH — the run outlives its caller's process group and ends rc=<n> (AC-3.1, AC-3.6, AC-3.8)"
# =====================================================================================
#
# THE CONTROL FIRST: the same SIGKILL of the same kind of group, over a command that is NOT
# detached, takes the command with it. So "the detached run wrote its rc" below is a run that
# escaped the kill, not a kill that missed.
set -m
( cd "$T1" && bash -c "sleep 1.5; : > '$D/ctl.ran'"; sleep 60 ) >/dev/null 2>&1 &
CTL_PG=$!
set +m
sleep 0.3
bk_kill_group "$CTL_PG"
sleep 2
expect_false "DT.0 control: a command in the caller's group dies with the group (no mark after the kill)" \
  test -e "$D/ctl.ran"

DT_CMD="printf '%s' \"\$BIONIC_TEST_PROGRESS\" > '$D/dt.prog'; printf '%s' \"\$BIONIC_GATE_ADMIT\" > '$D/dt.admit'; : > '$D/dt.ran'; i=0; while [ ! -f '$D/dt.go' ] && [ \$i -lt 200 ]; do i=\$((i+1)); sleep 0.05; done; echo detached-body; exit 0"
bk_caller dt "$T1" --detach --agent wx-T1 --suites probe.test.sh -- "$DT_CMD"
bk_wait 10 bk_grep '^booked: started ' "$D/dt.out"
DT_PID="$(bk_started dt pid)"; DT_LOG="$(bk_started dt log)"; DT_RUN="$(bk_started dt run)"
expect_regex "DT.1 the caller prints one started line naming the pid, the log and the run" \
  '^booked: started pid=[0-9]+ log=/.+\.log run=[^ ]+$' "$(grep '^booked: started ' "$D/dt.out" 2>/dev/null)"
expect_eq "DT.2 …and exits 0 at once, while the run is still going" "caller-rc=0" \
  "$(grep '^caller-rc=' "$D/dt.out" 2>/dev/null)"
expect_true "DT.3 the command started" bk_wait 10 test -e "$D/dt.ran"
expect_eq "DT.4 a .pid file was written at start, holding the started pid" "${DT_PID:-<none>}" \
  "$(cat "$DT_LOG.pid" 2>/dev/null)"
DT_PGID="$(ps -o pgid= -p "$DT_PID" 2>/dev/null | tr -d ' ')"
expect_nonempty "DT.5a the detached side is alive while its command runs" "$DT_PGID"
expect_true "DT.5 …and it is not in the caller's process group" test "${DT_PGID:-x}" != "$BK_PG"
DT_REQ="$(grep -l "^who=$WORLD_SID:wx-T1\$" "$BIONIC_GATE_DIR"/requests/[0-9]* 2>/dev/null | tail -n 1)"
DT_REQ_ID="${DT_REQ##*/}"
expect_nonempty "DT.6a the detached side asked the gate as wx-T1" "$DT_REQ"
expect_eq "DT.6 the place is held by the detached pid, not the caller" "${DT_PID:-<none>}" \
  "$(sed -n 's/^holder=//p' "$DT_REQ" 2>/dev/null | tail -n 1 | cut -d: -f1)"
expect_eq "DT.7 …and the command runs under that admission" "${DT_REQ_ID:-<none>}" "$(cat "$D/dt.admit" 2>/dev/null)"

# THE KILL: the caller's whole group, SIGKILL, no trap anywhere.
bk_kill_group "$BK_PG"
expect_true "DT.8 the caller's group is dead" bk_dead "$BK_PG"
expect_eq "DT.9 the place stays booked after the caller died (no ended= yet)" "" \
  "$(sed -n 's/^ended=//p' "$DT_REQ" 2>/dev/null)"
expect_true "DT.9b …while the request itself is admitted" grep -q '^admitted=' "$DT_REQ"
touch "$D/dt.go"
expect_true "DT.10 the run continues to its end with nobody waiting" bk_wait 20 bk_last_rc "$DT_LOG"
expect_eq "DT.11 the log's last line is rc=0" "rc=0" "$(tail -n 1 "$DT_LOG" 2>/dev/null)"
expect_contains "DT.12 …and the log carries the command's own output" "detached-body" "$(cat "$DT_LOG" 2>/dev/null)"
expect_eq "DT.13 the run's id is the log's name" "${DT_RUN:-<none>}" "$(basename "$DT_LOG" .log)"

# AC-3.6: the end and the stamp, by the detached side.
bk_wait 5 bk_grep '^ended=' "$DT_REQ"
expect_eq "DT.14 the gate's request was ended by the run, with its rc" "0" \
  "$(sed -n 's/^rc=//p' "$DT_REQ" 2>/dev/null | tail -n 1)"
T1_HEAD="$(git -C "$T1" rev-parse HEAD)"
T1_STAMPS="$(git -C "$T1" rev-parse --absolute-git-dir)/bionic-stamps"
expect_regex "DT.15 the stamp is in T1's own git dir: its head, clean, rc 0, its suite" \
  "^stamp/v1[|]head=$T1_HEAD[|]dirty=0[|]rc=0[|]at=[0-9TZ:-]+[|]suites=probe\\.test\\.sh[|]cmd=" \
  "$(tail -n 1 "$T1_STAMPS" 2>/dev/null)"

# AC-3.8: the progress file the run owns.
expect_eq "DT.16 the detached run exported BIONIC_TEST_PROGRESS=<log>.progress.tsv" \
  "$DT_LOG.progress.tsv" "$(cat "$D/dt.prog" 2>/dev/null)"
expect_true "DT.17 …and the progress file exists" test -f "$DT_LOG.progress.tsv"

# The run record on the roster: the name's latest row.
DT_ROW="$(grep '|name=wx-T1|' "$ROSTER" | tail -n 1)"
expect_contains "DT.18 the roster row carries the run's pid" "|run_pid=$DT_PID|" "$DT_ROW|"
expect_contains "DT.19 …its log" "|run_log=$DT_LOG|" "$DT_ROW|"
expect_contains "DT.20 …the head it ran on" "|run_head=$T1_HEAD|" "$DT_ROW|"
expect_regex "DT.21 …the command and the start" '[|]run_cmd=printf [^|]*[|]run_started_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z[|]' "$DT_ROW|"
expect_regex "DT.22 …and, at the end, its rc and when" '[|]run_rc=0[|]run_ended_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$' "$DT_ROW"
expect_eq "DT.23 every row of wx-T1 still carries its contract (name, session)" "" \
  "$(grep '|name=wx-T1|' "$ROSTER" | grep -v "|session=$WORLD_SID|")"

# An exit code that is not 0 is the log's too, through a command that ends in `exit`.
bk_caller dx "$T1" --detach --agent wx-T2 --suites probe-x.test.sh -- "echo before; exit 3"
bk_wait 10 bk_grep '^booked: started ' "$D/dx.out"
DX_LOG="$(bk_started dx log)"
bk_kill_group "$BK_PG"
expect_true "DT.24 a command that exits 3 still ends its log with an rc line" bk_wait 20 bk_last_rc "$DX_LOG"
expect_eq "DT.25 …and that line is rc=3" "rc=3" "$(tail -n 1 "$DX_LOG" 2>/dev/null)"

# =====================================================================================
section "§LOG2 — a second attempt writes …-2.log and never truncates the first (AC-3.4)"
# =====================================================================================
L1_BYTES="$(wc -c < "$DT_LOG" | tr -d ' ')"
expect_true "L2.0 the first attempt's log is not empty" test "${L1_BYTES:-0}" -gt 0
bk_caller l2 "$T1" --detach --agent wx-T1 --suites probe.test.sh -- "echo second-attempt"
bk_wait 10 bk_grep '^booked: started ' "$D/l2.out"
L2_LOG="$(bk_started l2 log)"; L2_RUN="$(bk_started l2 run)"
bk_kill_group "$BK_PG"
bk_wait 20 bk_last_rc "$L2_LOG"
expect_eq "L2.1 the second attempt of the same run writes …-2.log beside the first" \
  "${DT_LOG%.log}-2.log" "$L2_LOG"
expect_eq "L2.2 …its run id carries the -2" "${DT_RUN}-2" "$L2_RUN"
expect_eq "L2.3 the first log is byte for byte as long as before" "$L1_BYTES" \
  "$(wc -c < "$DT_LOG" | tr -d ' ')"
expect_eq "L2.4 …and still ends rc=0" "rc=0" "$(tail -n 1 "$DT_LOG" 2>/dev/null)"
expect_contains "L2.5 the second log holds the second run's output" "second-attempt" "$(cat "$L2_LOG" 2>/dev/null)"
bk_caller l3 "$T1" --detach --agent wx-T1 --suites probe.test.sh -- "echo third-attempt"
bk_wait 10 bk_grep '^booked: started ' "$D/l3.out"
L3_LOG="$(bk_started l3 log)"
bk_kill_group "$BK_PG"
bk_wait 20 bk_last_rc "$L3_LOG"
expect_eq "L2.6 a third attempt writes …-3.log" "${DT_LOG%.log}-3.log" "$L3_LOG"
expect_eq "L2.7 …and the roster's latest wx-T1 row names that third run" "${L3_LOG:-<none>}" \
  "$(grep '|name=wx-T1|' "$ROSTER" | tail -n 1 | tr '|' '\n' | sed -n 's/^run_log=//p')"

finish
