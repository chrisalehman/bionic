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
#   §WAIT-CALLER  (T12; A-orch-7) the caller waits on its run: the log's lines on stdout, the progress
#            line on stderr, the run's own code; a re-run of a live run attaches; LOST exits 70.
#   §DETACH-CEILING  (T12; D10; AC-9.4) a detached run the gate has not admitted within the bound ends
#            75 with the one line, in its log, `<log>.rc` and its roster row; the command never ran.
#   §WALL    AC-3.1 end to end — the Bash wall's wrap carries --detach and outlives its caller.
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
# DETACH AND WAIT (A-orch-7, T12): the caller does not leave; it waits on the run from inside the
# caller's group, so the kill below lands on a caller that is still there.
expect_nonempty "DT.2 …and does not exit: the caller is still waiting on the run in the caller's group" \
  "$(pgrep -g "$BK_PG" -f 'booked\.sh' 2>/dev/null)"
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

# =====================================================================================
section "§WAIT-CALLER — the caller waits on its run, streams it, and a re-run attaches (T12; A-orch-7; AC-3.2, AC-3.3, AC-3.8)"
# =====================================================================================
#
# DETACH AND WAIT. The caller of --detach polls the run's log every BIONIC_RUN_POLL seconds until
# its last line is `rc=<n>`, copies each new whole line of the log to its stdout, prints the run's
# last progress line on stderr when it changes, and exits with the run's own code. A caller that
# finds a LIVE run of the same id, tree and command attaches to it and never starts a second.
export BIONIC_RUN_POLL=0.1
AW_CMD="echo aw-body; printf '%s\\t%s\\t§%s\\n' 2026-10-08T00:00:00Z aw.test.sh one >> \"\$BIONIC_TEST_PROGRESS\"; sleep 0.6; echo aw-last; exit 4"
AW_OUT="$(cd "$T1" && bash "$BOOKED" --detach --agent wx-T2 --suites aw.test.sh -- "$AW_CMD" 2>"$D/aw.err")"; AW_RC=$?
expect_eq "AW.1 a caller left alone exits with the run's own code" "4" "$AW_RC"
expect_contains "AW.2 …its stdout carries the command's output, read from the log" "aw-body" "$AW_OUT"
expect_eq "AW.3 …up to the command's last line, and not the log's rc line after it" "aw-last" \
  "$(printf '%s\n' "$AW_OUT" | tail -n 1)"
expect_contains "AW.4 …and the run's progress line was printed on stderr while it ran" \
  "booked: progress 2026-10-08T00:00:00Z aw.test.sh §one" "$(cat "$D/aw.err" 2>/dev/null)"

# A COMMAND WHOSE OWN LAST LINE IS `rc=<n>` (a door command's `echo "rc=$rc"`) is not the run's end:
# the caller waits for the shim's own end and exits with the run's code.
RL_OUT="$(cd "$T1" && bash "$BOOKED" --detach --agent wx-T2 --suites rl.test.sh -- 'echo rc=3; sleep 0.4; exit 0' 2>/dev/null)"; RL_RC=$?
expect_eq "AW.5 a command that prints rc=3 and exits 0: the caller exits 0, the run's own code" "0" "$RL_RC"
expect_eq "AW.6 …and the command's rc=3 line is output, printed as its last line" "rc=3" \
  "$(printf '%s\n' "$RL_OUT" | tail -n 1)"

# THE ATTACH: a held run, its first caller's group killed, then the same command again.
AT_CMD="echo x >> '$D/at.count'; i=0; while [ ! -f '$D/at.go' ] && [ \$i -lt 300 ]; do i=\$((i+1)); sleep 0.05; done; echo at-body; exit 5"
bk_caller at1 "$T1" --detach --agent wx-T2 --suites at.test.sh -- "$AT_CMD"
bk_wait 10 bk_grep '^booked: started ' "$D/at1.out"
AT_PID="$(bk_started at1 pid)"; AT_LOG="$(bk_started at1 log)"
bk_wait 10 test -s "$D/at.count"
bk_kill_group "$BK_PG"
( cd "$T1" && bash "$BOOKED" --detach --agent wx-T2 --suites at.test.sh -- "$AT_CMD" > "$D/at2.out" 2>&1; echo "rc=$?" > "$D/at2.rc" ) &
AT2=$!
bk_wait 10 bk_grep '^booked: attached ' "$D/at2.out"
expect_eq "AT.1 a second caller of the same live run attaches: one line naming the same pid and log" \
  "booked: attached pid=${AT_PID:-<none>} log=${AT_LOG:-<none>} run=$(basename "${AT_LOG:-x}" .log)" \
  "$(grep '^booked: attached ' "$D/at2.out" 2>/dev/null)"
touch "$D/at.go"
wait "$AT2"
expect_eq "AT.2 …it exits with the run's own code" "rc=5" "$(cat "$D/at2.rc" 2>/dev/null)"
expect_eq "AT.3 …and the command ran once" "1" "$(wc -l < "$D/at.count" | tr -d ' ')"
expect_true "AT.4a the run's own log is there" test -f "$AT_LOG"
expect_false "AT.4 …and no second log was claimed for it" test -e "${AT_LOG%.log}-2.log"
expect_contains "AT.5 the attached caller streamed the run's output" "at-body" "$(cat "$D/at2.out" 2>/dev/null)"

# A DIFFERENT COMMAND UNDER THE SAME ID never attaches: it is a run of its own.
AD_CMD="i=0; while [ ! -f '$D/ad.go' ] && [ \$i -lt 300 ]; do i=\$((i+1)); sleep 0.05; done; exit 0"
bk_caller ad1 "$T1" --detach --agent wx-T2 --suites ad.test.sh -- "$AD_CMD"
bk_wait 10 bk_grep '^booked: started ' "$D/ad1.out"
AD_LOG="$(bk_started ad1 log)"
bk_caller ad2 "$T1" --detach --agent wx-T2 --suites ad.test.sh -- "echo other-command"
bk_wait 10 bk_grep '^booked: ' "$D/ad2.out"
expect_eq "AT.6 a different command under a live id starts a run of its own, on the next log" \
  "${AD_LOG%.log}-2.log" "$(bk_started ad2 log)"
touch "$D/ad.go"
bk_kill_group "$BK_PG"

# LOST: the detached side itself SIGKILLed (no trap, no rc line) while a caller waits on it.
LS_CMD="i=0; while [ ! -f '$D/ls.go' ] && [ \$i -lt 300 ]; do i=\$((i+1)); sleep 0.05; done; exit 0"
( cd "$T1" && bash "$BOOKED" --detach --agent wx-T2 --suites ls.test.sh -- "$LS_CMD" > "$D/ls.out" 2>&1; echo "rc=$?" > "$D/ls.rc" ) &
LS_W=$!
bk_wait 10 bk_grep '^booked: started ' "$D/ls.out"
LS_PID="$(bk_started ls pid)"
kill -KILL "${LS_PID:-0}" 2>/dev/null
wait "$LS_W"
touch "$D/ls.go"
expect_eq "LS.1 a waiting caller whose run's pid died with no rc line exits 70" "rc=70" "$(cat "$D/ls.rc" 2>/dev/null)"
expect_regex "LS.2 …with one LOST line naming the run and when its log was last written" \
  '^booked: LOST run=[^ ]+ last-written=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' \
  "$(grep '^booked: LOST ' "$D/ls.out" 2>/dev/null)"
expect_eq "LS.3 …and never the word timeout (beside LS.2 on the same output)" "0" \
  "$(grep -ci 'timeout' "$D/ls.out" 2>/dev/null)"

# =====================================================================================
section "§DETACH-CEILING — a detached run the gate has not admitted within the bound ends 75 with one line (T12; D10; AC-9.4)"
# =====================================================================================
#
# A detached run's wait is inside no call, so with nothing else to bound it the wait had no end. The
# detached side now asks the gate with --within BIONIC_SETTLE_MAX_WAIT (1200 s by default; 3 here), and
# a run not admitted inside it ends through the shim's one not-admitted path: exit 75, the line in the
# log (stderr is the log in the detached side), `rc=75` on the log's last line, `75` in `<log>.rc`,
# `run_rc=75` on the roster row. The caller follows the log, copies the line and exits 75.
#
# FIXTURE FIDELITY. gate.test.sh's held gate (B.7): the machine reads 60% used, the share is 80, a
# REAL background process holds a 15% admission, and the request the detached run makes would add 15
# more. The machine, clock and cost record are SYNTHESIZED (the world's pins); the holder, the shim,
# the perl detach and the roster write are real. The share is pinned here because the default moved.
CE_HOME="$D/ce-home"; mkdir -p "$CE_HOME/bionic"; printf '80\n' > "$CE_HOME/bionic/share"
CE_CFG_WAS="${CLAUDE_CONFIG_DIR:-}"; export CLAUDE_CONFIG_DIR="$CE_HOME"
export BIONIC_GATE_DIR="$D/ce-gate"
world_machine 8 8192 60 1.0
world_clock 1000
world_cost h 15 0.5 30
world_cost ce.test.sh 15 0.5 30
cat > "$D/ce-holder.sh" <<'CEHOLD'
d="$1"
. "$2"
export BIONIC_GATE_AGENT=ce-holder
id="$(gate_ask work h --within 0)"; rc=$?
printf '%s\n' "$rc" > "$d/ce-holder.rc"
[ "$rc" = 0 ] || exit 0
i=0; while [ ! -f "$d/ce-holder.go" ] && [ "$i" -lt 1200 ]; do i=$((i + 1)); sleep 0.05; done
gate_end "$id" 0
CEHOLD
bash "$D/ce-holder.sh" "$D" "$BIONIC_SCRIPTS_DIR/payload/scripts/lib/gate.sh" >/dev/null 2>&1 &
CE_HOLDER=$!
bk_wait 10 bk_has "$D/ce-holder.rc"
expect_eq "DC.0 precondition: the holder is admitted (60 + 15), so the run below finds no room" "0" \
  "$(cat "$D/ce-holder.rc" 2>/dev/null)"
export BIONIC_SETTLE_MAX_WAIT=3
CE_CMD="touch '$D/ce.ran'"
( cd "$T1" && bash "$BOOKED" --detach --agent wx-T2 --suites ce.test.sh -- "$CE_CMD" > "$D/ce.out" 2> "$D/ce.err"; echo "$?" > "$D/ce.rc" ) &
CE_CALLER=$!
bk_wait 10 bk_grep '^booked: started ' "$D/ce.out"
CE_LOG="$(sed -n 's/^booked: started .* log=\([^ ]*\) .*/\1/p' "$D/ce.out" | head -n 1)"
expect_nonempty "DC.1 precondition: the detached run started and named its log" "$CE_LOG"
bk_ce_asked() { ls "$BIONIC_GATE_DIR/requests" 2>/dev/null | grep -q '^[0-9][0-9]*$' \
  && grep -qs '^key=ce.test.sh$' "$BIONIC_GATE_DIR"/requests/[0-9]*; }
bk_wait 10 bk_ce_asked
expect_true "DC.2 …and it is waiting at the gate: its request is there, unadmitted" bk_ce_asked
sleep 0.5
expect_false "DC.3 at 1000 of a 3-second bound the run has not ended (beside DC.2 on the same run)" \
  test -e "${CE_LOG:-$D/none}.rc"
world_tick 3
bk_wait 20 bk_has "$D/ce.rc"
expect_eq "DC.4 at 1003 the caller exits 75, the run's own code" "75" "$(cat "$D/ce.rc" 2>/dev/null)"
expect_regex "DC.5 …the log carries the one line naming the wait, the request and the command to run again" \
  '^booked: the gate did not admit this command within 3s; request [^ ]+ keeps its turn — run again: ' \
  "$(grep '^booked: the gate did not admit' "${CE_LOG:-$D/none}" 2>/dev/null)"
expect_eq "DC.6 …`<log>.rc` holds 75" "75" "$(cat "${CE_LOG:-$D/none}.rc" 2>/dev/null)"
expect_eq "DC.7 …the log's last line is rc=75" "rc=75" "$(tail -n 1 "${CE_LOG:-$D/none}" 2>/dev/null)"
expect_eq "DC.8 …the roster row carries run_rc=75" "75" \
  "$(grep -F "run_log=$CE_LOG" "$ROSTER" | tail -n 1 | tr '|' '\n' | sed -n 's/^run_rc=//p')"
expect_contains "DC.9 …the caller copied the line to its stdout" "booked: the gate did not admit this command within 3s" \
  "$(cat "$D/ce.out" 2>/dev/null)"
expect_false "DC.10 …and the command never ran" test -e "$D/ce.ran"
touch "$D/ce-holder.go"
wait "$CE_HOLDER" "$CE_CALLER" 2>/dev/null
unset BIONIC_SETTLE_MAX_WAIT BIONIC_NOW_FILE
if [ -n "$CE_CFG_WAS" ]; then export CLAUDE_CONFIG_DIR="$CE_CFG_WAS"; else unset CLAUDE_CONFIG_DIR; fi
export BIONIC_GATE_DIR="$WORLD_ROOT/gate"
world_machine 8 8192 10 0.5

# =====================================================================================
section "§WALL — the Bash wall wraps a suite call in --detach, and the run outlives its caller (T12; A-orch-7; AC-3.1)"
# =====================================================================================
#
# END TO END ONCE: the real hooks/bash-walls.sh rewrites a main-thread suite call (advisory mode,
# so the call is allowed and booked), and the rewritten text, run in a caller's group that is then
# SIGKILLed, still ends its run's log with an rc line. §DETACH proved the shim half; this proves the
# wall passes the flag.
mkdir -p "$D/home" "$T1/tests"
printf 'farm-out-mode: advisory\n' >> "$WR/.bionic/config.yaml"
: > "$WR/.bionic/tmp/engaged-$WORLD_SID.state"
printf '#!/bin/bash\necho wall-run >> "%s/wl.count"\ni=0; while [ ! -f "%s/wl.go" ] && [ $i -lt 300 ]; do i=$((i+1)); sleep 0.05; done\necho wall-body\n' "$D" "$D" \
  > "$T1/tests/hold.test.sh"
WL_WRAP="$(jq -n --arg s "$WORLD_SID" --arg c "$T1" \
    '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Bash",
      tool_input:{command:"bash tests/hold.test.sh"}, tool_use_id:"toolu_01bookedwall"}' \
  | ( cd "$T1" && env HOME="$D/home" BIONIC_PLUGINS_DIR="$D/no-plugins" CLAUDE_PROJECT_DIR= \
        bash "$BIONIC_HOOKS_DIR/bash-walls.sh" 2>/dev/null ) \
  | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null)"
expect_regex "WL.1 the wall rewrites the suite call into the shim with --detach" \
  "^bash [^ ]+/booked\\.sh( [^ ]+)* --detach( |\$)" "$WL_WRAP"
expect_no_regex "WL.2 …and with no --max-wait (beside WL.1 on the same text)" " --max-wait " "$WL_WRAP"
set -m
( cd "$T1" && eval "$WL_WRAP"; echo "caller-rc=$?"; sleep 60 ) > "$D/wl.out" 2>&1 &
WL_PG=$!
set +m
bk_wait 10 bk_grep '^booked: started ' "$D/wl.out"
WL_LOG="$(bk_started wl log)"
bk_wait 10 test -s "$D/wl.count"
bk_kill_group "$WL_PG"
touch "$D/wl.go"
expect_true "WL.3 the caller's group SIGKILLed mid-run, the run still ends its log with an rc line" \
  bk_wait 20 bk_last_rc "${WL_LOG:-$D/none}"
expect_eq "WL.4 …and that line is the suite's own rc=0" "rc=0" "$(tail -n 1 "${WL_LOG:-$D/none}" 2>/dev/null)"
expect_eq "WL.5 …and the suite ran once" "1" "$(wc -l < "$D/wl.count" 2>/dev/null | tr -d ' ')"

finish
