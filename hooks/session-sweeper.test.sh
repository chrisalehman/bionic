#!/bin/bash
# Tests for hooks/session-sweeper.sh — epic-15 wave-04's ONE session-level watcher.
#
# Governing design: .bionic/docs/specs/epic-15-orchestrator-subagent-coordination/
# wave-04-watchers.spec.md §Design (sweeper shape, interview-ratified 2026-08-06).
# Serves AC-2 (predicates derived from roster row field presence) and AC-3 (arm/retire
# ledger, retire-before-rearm refusal).
#
# Hermetic: every case runs inside a throwaway sandbox git repo. Nothing reads or writes
# the real .bionic/tmp, the real roster, or a live wave. The only machine-global fact any
# case consults is process liveness, and the process it consults is one this suite starts
# and kills itself.
#
# CLOCK ACCELERATION (house rule): the tick is a parameter, so every loop case runs at
# `--tick 1` and every threshold is seconds-to-minutes rather than the 120 s default.
# Thresholds that would otherwise need real waiting are reached by BACKDATING — launch
# time is a roster field and progress staleness is an mtime, so both are fixture data.
# Nothing here sleeps for a declared cadence.
#
# FIXTURE FIDELITY: roster rows are generated to the roster-state/v1 schema exactly as
# written by hooks/dispatch-preflight.sh:490 (field set and order), shaped after the
# confirmed-row fixture in hooks/stop-check.test.sh:588. This suite's subject is the
# READER; hooks/dispatch-preflight.test.sh owns the writer. Rows are hand-built here for
# the same reason that suite hand-builds them: the shapes under test (unparseable cadence,
# a 45-minute-old launch) are not producible from a live dispatch inside a test.
#
# Usage: bash hooks/session-sweeper.test.sh

set -uo pipefail

# Overridable so this suite can be driven against a MUTATED COPY of the sweeper without the
# shipped file ever being modified — the same substitution
# tests/cross-gate-agreement.test.sh offers for its four parties, and the only safe way to
# take RED evidence for Section 7: an unguarded `retire` against a ledger carrying `pid=-1`
# SIGTERMs every process the operator can signal, so the pre-guard proof is taken against a
# copy whose `kill -TERM` is neutered:
#   W4_SWEEPER_UNDER_TEST=/tmp/mutant.sh bash hooks/session-sweeper.test.sh
SWEEPER="${W4_SWEEPER_UNDER_TEST:-$(cd "$(dirname "$0")" && pwd)/session-sweeper.sh}"
TMPROOT="$(mktemp -d)"
PASS=0; FAIL=0; TOTAL=0
BG_PIDS=""

cleanup() {
  local p
  for p in $BG_PIDS; do kill -9 "$p" 2>/dev/null; done
  chmod -R u+rwX "$TMPROOT" 2>/dev/null
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

# fixture-fidelity: SHAPE-ONLY well-formed session ids. Only "a well-formed session key,
# and a second one distinct from it" is load-bearing; the digits are arbitrary.
SID="4b2f7a10-1c33-4e05-9f21-7d0c5a8e6b44"
SID_FOREIGN="0e91c355-77aa-42d6-b0e8-3c1f2a94d7e0"

# ---------- assertion helpers ----------

ok()  { TOTAL=$((TOTAL+1)); PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"
        [ $# -gt 1 ] && printf '      %s\n' "$2"; return 0; }

expect_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi; }
expect_contains() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "no [$2] in: $(printf '%s' "$3" | head -3)" ;; esac; }
expect_absent()   { case "$3" in *"$2"*) bad "$1" "unexpected [$2] in: $(printf '%s' "$3" | head -3)" ;; *) ok "$1" ;; esac; }
expect_matches()  { if printf '%s\n' "$3" | grep -qE "$2"; then ok "$1"; else bad "$1" "no match /$2/ in: $(printf '%s' "$3" | head -3)"; fi; }
expect_true()     { local l="$1"; shift; if "$@"; then ok "$l"; else bad "$l" "condition failed: $*"; fi; }
expect_false()    { local l="$1"; shift; if "$@"; then bad "$l" "condition unexpectedly true: $*"; else ok "$l"; fi; }
section()         { printf '\n=== %s ===\n' "$1"; }

# ---------- sandbox + fixture builders ----------

make_repo() {  # <label> -> repo path
  local r="$TMPROOT/$1"
  mkdir -p "$r/.bionic/tmp"
  ( cd "$r" && git init -q . 2>/dev/null )
  printf '%s' "$r"
}

roster_of()   { printf '%s/.bionic/tmp/roster-%s.state'          "$1" "${2:-$SID}"; }
ledger_of()   { printf '%s/.bionic/tmp/sweeper-%s.state'         "$1" "${2:-$SID}"; }
findings_of() { printf '%s/.bionic/tmp/sweeper-%s-findings.log'  "$1" "${2:-$SID}"; }

iso_ago() {  # <seconds ago> -> UTC ISO-8601, the launched_at shape
  date -u -v-"$1"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "-$1 seconds" +%Y-%m-%dT%H:%M:%SZ
}

backdate() {  # <file> <seconds ago> — sets mtime, the staleness input
  local ts
  ts="$(date -v-"$2"S +%Y%m%d%H%M.%S 2>/dev/null || date -d "-$2 seconds" +%Y%m%d%H%M.%S)"
  touch -t "$ts" "$1"
}

new_roster() {  # <repo>
  printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' \
    > "$(roster_of "$1")"
}

# Emits one roster-state/v1 row. Field set and ORDER are dispatch-preflight.sh:490's;
# every unnamed field takes the empty value that gate writes when a brief declares none.
mkrow() {  # <key=value>...
  local status=confirmed session="$SID" name=agent agent_id=a000 launched_at=""
  local subagent_type=implementor model=opus deliverable="" duration="" progress=""
  local claims="" cadence="" tool_use_id=toolu_x kv
  for kv in "$@"; do
    case "$kv" in
      status=*)      status="${kv#*=}" ;;
      session=*)     session="${kv#*=}" ;;
      name=*)        name="${kv#*=}" ;;
      agent_id=*)    agent_id="${kv#*=}" ;;
      launched_at=*) launched_at="${kv#*=}" ;;
      deliverable=*) deliverable="${kv#*=}" ;;
      duration=*)    duration="${kv#*=}" ;;
      progress=*)    progress="${kv#*=}" ;;
      claims=*)      claims="${kv#*=}" ;;
      cadence=*)     cadence="${kv#*=}" ;;
      tool_use_id=*) tool_use_id="${kv#*=}" ;;
      *) printf 'mkrow: unknown key %s\n' "$kv" >&2; return 1 ;;
    esac
  done
  [ -n "$launched_at" ] || launched_at="$(iso_ago 60)"
  printf 'roster-state/v1|status=%s|session=%s|name=%s|agent_id=%s|launched_at=%s|subagent_type=%s|model=%s|deliverable=%s|duration=%s|progress=%s|claims=%s|cadence=%s|absent=|tool_use_id=%s\n' \
    "$status" "$session" "$name" "$agent_id" "$launched_at" "$subagent_type" "$model" \
    "$deliverable" "$duration" "$progress" "$claims" "$cadence" "$tool_use_id"
}

add_row() {  # <repo> <key=value>...
  local repo="$1"; shift
  mkrow "$@" >> "$(roster_of "$repo")"
}

# ---------- running the sweeper ----------
#
# Both runners set GLOBALS rather than printing: a `$(...)` wrapper would put the exit
# code and the background pid in a subshell, where `wait` cannot reach the job and the
# cleanup trap cannot kill it.

# Every foreground case here is a fast path — a refusal, a usage error, `status`, or
# `retire`. If one of them BLOCKS, the bug is that a verb entered the watch loop when it
# should not have, and a suite that hangs on it would wedge `bash tests/run.sh` rather
# than report the defect. So the runner is its own watchdog: RC=124 on a run that overruns
# the bound, which fails whatever the case expected.
SWEEP_BOUND=20
sweep() {  # <repo> <args...> -> sets OUT, RC
  local repo="$1"; shift
  ( cd "$repo" && exec env CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER" "$@" ) \
    > "$TMPROOT/sweep.out" 2>&1 &
  local p=$! i=0
  BG_PIDS="$BG_PIDS $p"
  while kill -0 "$p" 2>/dev/null && [ "$i" -lt $(( SWEEP_BOUND * 10 )) ]; do
    sleep 0.1; i=$((i+1))
  done
  if kill -0 "$p" 2>/dev/null; then
    kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null
    RC=124
  else
    wait "$p" 2>/dev/null; RC=$?
  fi
  OUT="$(cat "$TMPROOT/sweep.out")"
}

# `exec` matters: without it the job is the subshell and the ledger's pid (the sweeper's
# own $$) would name a different process, so every liveness assertion would test the
# wrong pid.
sweep_bg() {  # <repo> <outfile> <args...> -> sets BGPID
  local repo="$1" out="$2"; shift 2
  ( cd "$repo" && exec env CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER" "$@" >"$out" 2>&1 ) &
  BGPID=$!
  BG_PIDS="$BG_PIDS $BGPID"
}

wait_grep() {  # <pattern> <file> <timeout-seconds>
  local i=0 lim=$(( $3 * 10 ))
  while [ "$i" -lt "$lim" ]; do
    [ -f "$2" ] && grep -qE "$1" "$2" 2>/dev/null && return 0
    sleep 0.1; i=$((i+1))
  done
  return 1
}

wait_exit() {  # <pid> <timeout-seconds>
  local i=0 lim=$(( $2 * 10 ))
  while [ "$i" -lt "$lim" ]; do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.1; i=$((i+1))
  done
  return 1
}

alive() { kill -0 "$1" 2>/dev/null; }

# ============================================================
section "Section 1: surface — verbs, refusals, the tick parameter"
# ============================================================

R1="$(make_repo s1)"; new_roster "$R1"

OUT="$( cd "$R1" && CLAUDE_CODE_SESSION_ID="" bash "$SWEEPER" status 2>&1 )"; RC=$?
expect_eq "no session key REFUSES with exit 3" "3" "$RC"
expect_contains "no session key: the refusal says why" "session key" "$OUT"

sweep "$R1"
expect_eq "no verb is a usage error (exit 2)" "2" "$RC"
expect_contains "usage names arm" "arm" "$OUT"
expect_contains "usage names retire" "retire" "$OUT"
expect_contains "usage names status" "status" "$OUT"

sweep "$R1" sweep-everything
expect_eq "an unknown verb is a usage error (exit 2)" "2" "$RC"

sweep "$R1" arm --tick
expect_eq "--tick with no value is refused" "2" "$RC"
sweep "$R1" arm --tick soon
expect_eq "--tick with a non-numeric value is refused" "2" "$RC"
expect_contains "the non-numeric tick refusal names the flag" "--tick" "$OUT"
sweep "$R1" arm --tick 0
expect_eq "--tick 0 is refused" "2" "$RC"

sweep "$R1" status
expect_eq "status with nothing armed exits 1" "1" "$RC"
expect_contains "status with nothing armed reports not-live" "live=no" "$OUT"

# ============================================================
section "Section 2: the ledger — arm fields, refusal, retire, re-arm (AC-3)"
# ============================================================

R2="$(make_repo s2)"; new_roster "$R2"
L2="$(ledger_of "$R2")"
sweep_bg "$R2" "$TMPROOT/s2.out" arm --tick 30; P2="$BGPID"
expect_true "arm writes an arm entry to the ledger" wait_grep 'event=arm' "$L2" 10

ARMLINE="$(grep 'event=arm' "$L2" 2>/dev/null | head -1)"
expect_contains "the arm entry is a versioned pipe-delimited line" "sweeper-ledger/v1|" "$ARMLINE"
expect_matches "the arm entry carries a UTC timestamp" 'at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "$ARMLINE"
expect_contains "the arm entry carries the arming pid" "pid=$P2" "$ARMLINE"
expect_contains "the arm entry carries the effective tick" "tick=30" "$ARMLINE"
expect_contains "the arm entry carries the session" "session=$SID" "$ARMLINE"
expect_true "the ledger is at the path the design names" test -f "$R2/.bionic/tmp/sweeper-$SID.state"

sweep "$R2" status
expect_eq "status with a live arming exits 0" "0" "$RC"
expect_contains "status reports live=yes" "live=yes" "$OUT"
expect_contains "status names the live pid" "pid=$P2" "$OUT"
expect_contains "status names the effective tick" "tick=30" "$OUT"

sweep "$R2" arm --tick 5
expect_eq "a second arm over a live arming is REFUSED (exit 1)" "1" "$RC"
expect_contains "the refusal names the live arming's pid" "$P2" "$OUT"
expect_matches "the refusal names when the live arming was armed" '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "$OUT"
expect_contains "the refusal says how to proceed" "retire" "$OUT"
expect_eq "the refused arm wrote no second arm entry" "1" "$(grep -c 'event=arm' "$L2")"
expect_true "the refused arm did not disturb the live one" alive "$P2"

sweep "$R2" retire
expect_eq "retire succeeds (exit 0)" "0" "$RC"
expect_eq "retire closes the open entry" "1" "$(grep -c 'event=retire' "$L2")"
expect_contains "the retire entry names the pid it closed" "pid=$P2" "$(grep 'event=retire' "$L2")"
expect_true "the retired sweeper exits" wait_exit "$P2" 15

sweep "$R2" status
expect_eq "status after retire exits 1" "1" "$RC"
expect_contains "status after retire reports not-live" "live=no" "$OUT"

sweep_bg "$R2" "$TMPROOT/s2b.out" arm --tick 30; P2B="$BGPID"
expect_true "re-arm after retire succeeds" wait_grep "pid=$P2B" "$L2" 10
expect_eq "the ledger now holds two arm entries" "2" "$(grep -c 'event=arm' "$L2")"
expect_eq "append-only: the first arm entry survives" "1" "$(grep -c "event=arm|.*|pid=$P2|" "$L2")"
expect_eq "append-only: the retire entry survives" "1" "$(grep -c 'event=retire' "$L2")"
sweep "$R2" retire; wait_exit "$P2B" 15

# A prior arming whose pid is gone (killed, crashed, session ended) must not wedge the
# session: it is a LIVE pid that refuses, not an open entry.
R2C="$(make_repo s2c)"; new_roster "$R2C"
L2C="$(ledger_of "$R2C")"
{
  printf '# bionic session sweeper ledger — schema sweeper-ledger/v1 — machine-local, safe to delete\n'
  printf 'sweeper-ledger/v1|event=arm|at=2026-08-06T00:00:00Z|epoch=1780000000|pid=999999|tick=120|session=%s|rows=0|degraded=\n' "$SID"
} > "$L2C"
sweep_bg "$R2C" "$TMPROOT/s2c.out" arm --tick 30; P2C="$BGPID"
expect_true "arm over a STALE open entry (dead pid) succeeds" wait_grep "pid=$P2C" "$L2C" 10
sweep "$R2C" retire; wait_exit "$P2C" 15

# The tick default is the sweeper's own (spec ownership table) and it is a FLAG, never
# ambient: no environment variable moves it.
R2D="$(make_repo s2d)"; new_roster "$R2D"
L2D="$(ledger_of "$R2D")"
( cd "$R2D" && exec env CLAUDE_CODE_SESSION_ID="$SID" SWEEPER_TICK=3 BIONIC_SWEEPER_TICK=3 \
    bash "$SWEEPER" arm > "$TMPROOT/s2d.out" 2>&1 ) &
P2D=$!; BG_PIDS="$BG_PIDS $P2D"
expect_true "arm without --tick writes an arm entry" wait_grep 'event=arm' "$L2D" 10
expect_contains "the default tick is 120 s" "tick=120" "$(grep 'event=arm' "$L2D" | head -1)"
expect_absent "no environment variable overrides the tick" "tick=3" "$(grep 'event=arm' "$L2D" | head -1)"
sweep "$R2D" retire; wait_exit "$P2D" 15

# ============================================================
section "Section 3: predicates by field presence — the three classes (AC-2)"
# ============================================================

# --- stale progress: progress + cadence, mtime older than the declared cadence ---
R3="$(make_repo s3)"; new_roster "$R3"
PROG3="$R3/w-progress.md"; echo "a line" > "$PROG3"; backdate "$PROG3" 600
add_row "$R3" name=staler progress="$PROG3" cadence="every ~2 minutes" \
        duration="4 hours" deliverable="$R3/never-written.md" launched_at="$(iso_ago 300)"
sweep_bg "$R3" "$TMPROOT/s3.out" arm --tick 1; P3="$BGPID"
expect_true "stale progress: the sweeper exits — the exit IS the delivery" wait_exit "$P3" 20
wait "$P3" 2>/dev/null; RC3=$?
expect_eq "stale progress: the delivering exit is 0" "0" "$RC3"
F3="$(cat "$(findings_of "$R3")" 2>/dev/null)"
expect_contains "stale progress: a finding line is mirrored to the findings file" "sweeper-finding/v1|" "$F3"
expect_contains "stale progress: the finding names its class" "class=stale-progress" "$F3"
expect_contains "stale progress: the finding names the row" "name=staler" "$F3"
expect_contains "stale progress: the finding names the progress path" "$PROG3" "$F3"
O3="$(cat "$TMPROOT/s3.out")"
expect_contains "stale progress: the wake is printed on stdout too" "stale-progress" "$O3"
LED3="$(cat "$(ledger_of "$R3")")"
expect_contains "stale progress: the ledger records the delivering exit" "event=exit" "$LED3"
expect_contains "stale progress: the exit entry names the reason" "reason=finding" "$LED3"
# It reports state facts. It never judges, never prescribes, never stops anything.
for word in "kill" "you should" "recommend" "hung" "is dead" "safe to stop"; do
  expect_absent "stale progress: the finding does not judge (\"$word\")" "$word" "$F3$O3"
done

# --- fresh progress inside the declared cadence: silence holds ---
R3B="$(make_repo s3b)"; new_roster "$R3B"
PROG3B="$R3B/w-progress.md"; echo "just written" > "$PROG3B"
add_row "$R3B" name=fresh progress="$PROG3B" cadence="every ~5 min" duration="4 hours"
sweep_bg "$R3B" "$TMPROOT/s3b.out" arm --tick 1; P3B="$BGPID"
sleep 3
expect_true "fresh progress: the sweeper is still watching" alive "$P3B"
expect_false "fresh progress: no findings were written" test -s "$(findings_of "$R3B")"
sweep "$R3B" retire; wait_exit "$P3B" 15

# --- dead claim: the claimed process is absent AND the deliverables are absent ---
R3C="$(make_repo s3c)"; new_roster "$R3C"
add_row "$R3C" name=claimer claims="bionic-no-such-process-marker-91731" \
        deliverable="$R3C/absent-report.md" duration="4 hours"
sweep_bg "$R3C" "$TMPROOT/s3c.out" arm --tick 1; P3C="$BGPID"
expect_true "dead claim: the sweeper exits on the finding" wait_exit "$P3C" 20
F3C="$(cat "$(findings_of "$R3C")" 2>/dev/null)"
expect_contains "dead claim: the finding names its class" "class=dead-claim" "$F3C"
expect_contains "dead claim: the finding names the row" "name=claimer" "$F3C"
expect_contains "dead claim: the finding names the claimed pattern" "bionic-no-such-process-marker-91731" "$F3C"

# --- a live claimed process quiets EVERY class for that row ---
R3D="$(make_repo s3d)"; new_roster "$R3D"
CLAIMSCRIPT="$TMPROOT/bionic-claim-marker-40217.sh"
printf '#!/bin/bash\nsleep 60\n' > "$CLAIMSCRIPT"; chmod +x "$CLAIMSCRIPT"
bash "$CLAIMSCRIPT" & CLAIMPID=$!; BG_PIDS="$BG_PIDS $CLAIMPID"
PROG3D="$R3D/claimer-progress.md"; echo "old" > "$PROG3D"; backdate "$PROG3D" 900
# Everything else about this row is broken — launched far past its duration, progress far
# past its cadence, deliverable absent. The live claim is the only quieting fact.
add_row "$R3D" name=busy claims="$CLAIMSCRIPT" progress="$PROG3D" cadence="10 seconds" \
        duration="1 minute" deliverable="$R3D/absent.md" launched_at="$(iso_ago 3600)"
sweep_bg "$R3D" "$TMPROOT/s3d.out" arm --tick 1; P3D="$BGPID"
sleep 3
expect_true "live claim: the sweeper is still watching" alive "$P3D"
expect_false "live claim: no finding of any class was raised" test -s "$(findings_of "$R3D")"
kill -9 "$CLAIMPID" 2>/dev/null; wait "$CLAIMPID" 2>/dev/null
expect_true "live claim: once the claimed process is gone the row breaks" wait_exit "$P3D" 20
expect_contains "live claim: the finding that follows is dead-claim" "class=dead-claim" \
  "$(cat "$(findings_of "$R3D")" 2>/dev/null)"

# --- overdue: a turns-shaped row (no progress, no claims) against its declared duration ---
R3E="$(make_repo s3e)"; new_roster "$R3E"
add_row "$R3E" name=slowpoke duration="20 minutes" launched_at="$(iso_ago 1500)" \
        deliverable="$R3E/absent.md"
sweep_bg "$R3E" "$TMPROOT/s3e.out" arm --tick 1; P3E="$BGPID"
expect_true "overdue: the sweeper exits on the finding" wait_exit "$P3E" 20
F3E="$(cat "$(findings_of "$R3E")" 2>/dev/null)"
expect_contains "overdue: the finding names its class" "class=overdue" "$F3E"
expect_contains "overdue: the finding names the row" "name=slowpoke" "$F3E"
expect_contains "overdue: the finding names the declared duration" "20 minutes" "$F3E"

# --- done-detection: every declared deliverable present ⇒ satisfied, never woken on ---
R3F="$(make_repo s3f)"; new_roster "$R3F"
echo "the report" > "$R3F/one.md"; echo "the appendix" > "$R3F/two.md"
PROG3F="$R3F/done-progress.md"; echo "stale" > "$PROG3F"; backdate "$PROG3F" 900
add_row "$R3F" name=finished deliverable="$R3F/one.md,$R3F/two.md" duration="1 minute" \
        progress="$PROG3F" cadence="10 seconds" claims="bionic-no-such-process-marker-91731" \
        launched_at="$(iso_ago 3600)"
sweep_bg "$R3F" "$TMPROOT/s3f.out" arm --tick 1; P3F="$BGPID"
sleep 3
expect_true "satisfied: a row with all deliverables present is never woken on" alive "$P3F"
expect_false "satisfied: no findings were written" test -s "$(findings_of "$R3F")"
sweep "$R3F" retire; wait_exit "$P3F" 15

# --- a PARTIAL deliverable set is not done ---
R3G="$(make_repo s3g)"; new_roster "$R3G"
echo "only the first" > "$R3G/one.md"
add_row "$R3G" name=halfway deliverable="$R3G/one.md,$R3G/two.md" duration="1 minute" \
        launched_at="$(iso_ago 600)"
sweep_bg "$R3G" "$TMPROOT/s3g.out" arm --tick 1; P3G="$BGPID"
expect_true "partial deliverables: the row is NOT satisfied and still breaks" wait_exit "$P3G" 20
expect_contains "partial deliverables: the finding is overdue" "class=overdue" \
  "$(cat "$(findings_of "$R3G")" 2>/dev/null)"

# --- an empty deliverable file is not a delivered deliverable ---
R3H="$(make_repo s3h)"; new_roster "$R3H"
: > "$R3H/empty.md"
add_row "$R3H" name=emptyhanded deliverable="$R3H/empty.md" duration="1 minute" \
        launched_at="$(iso_ago 600)"
sweep_bg "$R3H" "$TMPROOT/s3h.out" arm --tick 1; P3H="$BGPID"
expect_true "an empty deliverable file does not satisfy a row" wait_exit "$P3H" 20
expect_contains "the empty-deliverable row is reported overdue" "class=overdue" \
  "$(cat "$(findings_of "$R3H")" 2>/dev/null)"

# --- a DIRECTORY deliverable is judged by what is in it, exactly as hooks/stop-check.sh
# judges one (6-axis D-2). `[ -s <dir> ]` is TRUE for an empty directory on both BSD and
# GNU, so the naive substance test marked a row SATISFIED — permanently exempt from
# watching — on a directory nobody had written anything into. The two implementations of
# "is this deliverable delivered?" are bound on shared fixtures in
# tests/cross-gate-agreement.test.sh §I; these two cases hold the sweeper's own half.
R3I="$(make_repo s3i)"; new_roster "$R3I"
mkdir -p "$R3I/empty-dir"
add_row "$R3I" name=emptydir deliverable="$R3I/empty-dir" duration="1 minute" \
        launched_at="$(iso_ago 600)"
sweep_bg "$R3I" "$TMPROOT/s3i.out" arm --tick 1; P3I="$BGPID"
expect_true "an EMPTY directory does not satisfy a row" wait_exit "$P3I" 20
expect_contains "the empty-directory row is reported overdue" "class=overdue" \
  "$(cat "$(findings_of "$R3I")" 2>/dev/null)"

R3J="$(make_repo s3j)"; new_roster "$R3J"
mkdir -p "$R3J/full-dir"; echo "the report" > "$R3J/full-dir/one.md"
add_row "$R3J" name=fulldir deliverable="$R3J/full-dir" duration="1 minute" \
        launched_at="$(iso_ago 600)"
sweep_bg "$R3J" "$TMPROOT/s3j.out" arm --tick 1; P3J="$BGPID"
sleep 3
expect_true "a directory holding at least one file DOES satisfy a row" alive "$P3J"
expect_false "the satisfied directory row wrote no findings" test -s "$(findings_of "$R3J")"
sweep "$R3J" retire; wait_exit "$P3J" 15

# --- a RELATIVE deliverable path is the REPO's, not the arming shell's cwd. Deliberate,
# logged divergence from hooks/stop-check.sh (which resolves the paths TYPED at it against
# the operator's own cwd): this process is armed once from whatever directory the harness
# happened to be in and then outlives it, so a cwd-relative reading would make a roster
# row mean different things on two arms of the same file.
#
# Both cases arm from a SUBDIRECTORY of the repo, which is what separates the two
# readings: the roster and the ledger are repo-derived either way, so only the
# deliverable's resolution can differ.
R3K="$(make_repo s3k)"; new_roster "$R3K"
mkdir -p "$R3K/sub"
echo "the report" > "$R3K/rel-deliverable.md"
add_row "$R3K" name=relative deliverable="rel-deliverable.md" duration="1 minute" \
        launched_at="$(iso_ago 600)"
( cd "$R3K/sub" && exec env CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER" arm --tick 1 \
    >"$TMPROOT/s3k.out" 2>&1 ) &
P3K=$!; BG_PIDS="$BG_PIDS $P3K"
sleep 3
expect_true "a relative deliverable IS resolved against the repo root" alive "$P3K"
sweep "$R3K" retire; wait_exit "$P3K" 15

R3K2="$(make_repo s3k2)"; new_roster "$R3K2"
mkdir -p "$R3K2/sub"
echo "the report" > "$R3K2/sub/rel-deliverable.md"
add_row "$R3K2" name=relative-cwd deliverable="rel-deliverable.md" duration="1 minute" \
        launched_at="$(iso_ago 600)"
( cd "$R3K2/sub" && exec env CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER" arm --tick 1 \
    >"$TMPROOT/s3k2.out" 2>&1 ) &
P3K2=$!; BG_PIDS="$BG_PIDS $P3K2"
expect_true "…and NOT against the arming shell's cwd" wait_exit "$P3K2" 20
expect_contains "the cwd-relative row is reported overdue" "class=overdue" \
  "$(cat "$(findings_of "$R3K2")" 2>/dev/null)"

# ============================================================
section "Section 4: the prose-lifted threshold parser"
# ============================================================
#
# Cadence and duration arrive as prose the dispatch gate lifted out of a brief. The parser
# is deterministic: units it knows, a range read at its generous end, and no guess for
# anything else. Rows are batched into one quiet run and one firing run so the whole table
# costs two ticks rather than a dozen.

R4="$(make_repo s4)"; new_roster "$R4"
add_row "$R4" name=q-minutes  duration="20 minutes"      launched_at="$(iso_ago 60)"   deliverable="$R4/x.md"
add_row "$R4" name=q-tilde    duration="~10 minutes"     launched_at="$(iso_ago 60)"   deliverable="$R4/x.md"
add_row "$R4" name=q-hour     duration="1 hour"          launched_at="$(iso_ago 600)"  deliverable="$R4/x.md"
add_row "$R4" name=q-seconds  duration="90 seconds"      launched_at="$(iso_ago 30)"   deliverable="$R4/x.md"
add_row "$R4" name=q-range    duration="30–40 minutes"   launched_at="$(iso_ago 2100)" deliverable="$R4/x.md"
add_row "$R4" name=q-short    duration="2m"              launched_at="$(iso_ago 60)"   deliverable="$R4/x.md"
# An unparseable duration on a turns-shaped row: nothing to compare against, so no finding
# is manufactured from it.
add_row "$R4" name=q-unparse  duration="when it is done" launched_at="$(iso_ago 9000)" deliverable="$R4/x.md"
# A row declaring no threshold at all is unwatchable, not overdue.
add_row "$R4" name=q-bare     launched_at="$(iso_ago 9000)"
# A row belonging to another session is not this sweeper's to watch.
add_row "$R4" name=q-foreign  session="$SID_FOREIGN" duration="1 minute" launched_at="$(iso_ago 9000)"
# Lines the reader must skip rather than choke on.
printf 'roster-state/v9|status=confirmed|name=q-future|duration=1 minute|launched_at=%s\n' "$(iso_ago 9000)" >> "$(roster_of "$R4")"
printf 'not a roster row at all\n' >> "$(roster_of "$R4")"
sweep_bg "$R4" "$TMPROOT/s4.out" arm --tick 1; P4="$BGPID"
sleep 3
expect_true "parser: every in-bounds / unparseable / foreign row stays quiet" alive "$P4"
expect_false "parser: nothing was written for the quiet table" test -s "$(findings_of "$R4")"
L4="$(cat "$(ledger_of "$R4")" 2>/dev/null)"
expect_contains "an unparseable DURATION is named as a degradation at arm time" "q-unparse" "$L4"
expect_contains "a row declaring no threshold at all is named as a degradation" "q-bare" "$L4"
sweep "$R4" retire; wait_exit "$P4" 15

R4B="$(make_repo s4b)"; new_roster "$R4B"
add_row "$R4B" name=f-minutes duration="20 minutes"    launched_at="$(iso_ago 1300)" deliverable="$R4B/x.md"
add_row "$R4B" name=f-tilde   duration="~10 minutes"   launched_at="$(iso_ago 700)"  deliverable="$R4B/x.md"
add_row "$R4B" name=f-hour    duration="1 hour"        launched_at="$(iso_ago 3700)" deliverable="$R4B/x.md"
add_row "$R4B" name=f-seconds duration="90 seconds"    launched_at="$(iso_ago 200)"  deliverable="$R4B/x.md"
add_row "$R4B" name=f-range   duration="30–40 minutes" launched_at="$(iso_ago 2700)" deliverable="$R4B/x.md"
add_row "$R4B" name=f-short   duration="2m"            launched_at="$(iso_ago 200)"  deliverable="$R4B/x.md"
sweep_bg "$R4B" "$TMPROOT/s4b.out" arm --tick 1; P4B="$BGPID"
expect_true "parser: the out-of-bounds table wakes the orchestrator" wait_exit "$P4B" 20
F4B="$(cat "$(findings_of "$R4B")" 2>/dev/null)"
for n in f-minutes f-tilde f-hour f-seconds f-range f-short; do
  expect_contains "parser: \"$n\" is read as overdue" "name=$n" "$F4B"
done
expect_eq "parser: a range is read at its generous end (35 min quiet, 45 min overdue)" \
  "1" "$(printf '%s\n' "$F4B" | grep -c 'name=f-range')"

# --- an unparseable CADENCE degrades that row to overdue-only, and says so ---
R4C="$(make_repo s4c)"; new_roster "$R4C"
PROG4C="$R4C/degraded-progress.md"; echo "old" > "$PROG4C"; backdate "$PROG4C" 900
add_row "$R4C" name=cadence-mush progress="$PROG4C" cadence="whenever it feels right" \
        duration="4 hours" launched_at="$(iso_ago 60)" deliverable="$R4C/absent.md"
sweep_bg "$R4C" "$TMPROOT/s4c.out" arm --tick 1; P4C="$BGPID"
expect_true "unparseable cadence: an arm entry is written" wait_grep 'event=arm' "$(ledger_of "$R4C")" 10
L4C="$(grep 'event=arm' "$(ledger_of "$R4C")" | head -1)"
expect_contains "unparseable cadence: the degradation names the row" "cadence-mush" "$L4C"
expect_contains "unparseable cadence: the degradation names the surviving predicate" "overdue-only" "$L4C"
sleep 3
expect_true "unparseable cadence: no stale-progress finding is guessed from it" alive "$P4C"
expect_false "unparseable cadence: nothing was written to the findings file" test -s "$(findings_of "$R4C")"
sweep "$R4C" retire; wait_exit "$P4C" 15

# ...and the same shape still goes overdue on its declared duration.
R4D="$(make_repo s4d)"; new_roster "$R4D"
PROG4D="$R4D/degraded-progress.md"; echo "old" > "$PROG4D"; backdate "$PROG4D" 900
add_row "$R4D" name=cadence-mush-2 progress="$PROG4D" cadence="whenever it feels right" \
        duration="1 minute" launched_at="$(iso_ago 600)" deliverable="$R4D/absent.md"
sweep_bg "$R4D" "$TMPROOT/s4d.out" arm --tick 1; P4D="$BGPID"
expect_true "a cadence-degraded row is still watched for overdue" wait_exit "$P4D" 20
F4D="$(cat "$(findings_of "$R4D")" 2>/dev/null)"
expect_contains "the degraded row's finding is overdue" "class=overdue" "$F4D"
expect_absent "the degraded row raises no stale-progress finding" "class=stale-progress" "$F4D"

# ============================================================
section "Section 5: the loop — fresh roster reads, batching, delivery"
# ============================================================

# --- the roster is re-read every tick: a row added AFTER arm is watched ---
R5="$(make_repo s5)"; new_roster "$R5"
add_row "$R5" name=quiet-one duration="4 hours" deliverable="$R5/absent.md"
sweep_bg "$R5" "$TMPROOT/s5.out" arm --tick 1; P5="$BGPID"
expect_true "roster re-read: the sweeper arms over the initial roster" wait_grep 'event=arm' "$(ledger_of "$R5")" 10
sleep 2
expect_true "roster re-read: it is quiet while the initial roster holds" alive "$P5"
add_row "$R5" name=late-arrival duration="1 minute" launched_at="$(iso_ago 600)" \
        deliverable="$R5/absent.md"
expect_true "roster re-read: a row added after arm wakes it" wait_exit "$P5" 20
expect_contains "roster re-read: the finding names the late row" "name=late-arrival" \
  "$(cat "$(findings_of "$R5")" 2>/dev/null)"

# --- findings batch per tick: every broken row in ONE exit ---
R6="$(make_repo s6)"; new_roster "$R6"
PROG6="$R6/p.md"; echo "old" > "$PROG6"; backdate "$PROG6" 900
add_row "$R6" name=broken-a duration="1 minute" launched_at="$(iso_ago 600)" deliverable="$R6/absent-a.md"
add_row "$R6" name=broken-b claims="bionic-no-such-process-marker-91731" deliverable="$R6/absent-b.md" duration="4 hours"
add_row "$R6" name=broken-c progress="$PROG6" cadence="10 seconds" duration="4 hours" deliverable="$R6/absent-c.md"
sweep_bg "$R6" "$TMPROOT/s6.out" arm --tick 1; P6="$BGPID"
expect_true "batching: one exit delivers the whole tick" wait_exit "$P6" 20
F6="$(cat "$(findings_of "$R6")" 2>/dev/null)"
expect_eq "batching: all three broken rows are in the batch" "3" \
  "$(printf '%s\n' "$F6" | grep -c '^sweeper-finding/v1|')"
expect_contains "batching: the overdue row is in it" "name=broken-a" "$F6"
expect_contains "batching: the dead-claim row is in it" "name=broken-b" "$F6"
expect_contains "batching: the stale-progress row is in it" "name=broken-c" "$F6"
expect_eq "batching: the batch is delivered once, not row by row" "1" \
  "$(grep -c 'event=exit' "$(ledger_of "$R6")")"
expect_contains "batching: the exit entry counts the findings" "findings=3" \
  "$(grep 'event=exit' "$(ledger_of "$R6")")"
# The findings file is the hedge against a lost wake, so it must be on disk BY the time
# the process is gone — which is exactly what waiting on the pid above establishes.
expect_true "the findings file is on disk once the delivering process is gone" \
  test -s "$(findings_of "$R6")"

# --- the first evaluation happens AFTER a tick, not at arm ---
R7="$(make_repo s7)"; new_roster "$R7"
add_row "$R7" name=instant duration="1 minute" launched_at="$(iso_ago 600)" deliverable="$R7/absent.md"
sweep_bg "$R7" "$TMPROOT/s7.out" arm --tick 5; P7="$BGPID"
sleep 2
expect_true "the loop sleeps its tick before the first evaluation" alive "$P7"
expect_true "the broken row is delivered on the following tick" wait_exit "$P7" 20
expect_contains "the delivery names the row it was waiting on" "name=instant" \
  "$(cat "$(findings_of "$R7")" 2>/dev/null)"

# --- arming before any roster exists is legitimate: rows arrive later ---
R8="$(make_repo s8)"
sweep_bg "$R8" "$TMPROOT/s8.out" arm --tick 1; P8="$BGPID"
expect_true "arm succeeds before any dispatch has written a roster" wait_grep 'event=arm' "$(ledger_of "$R8")" 10
sleep 2
expect_true "an absent roster is zero rows, not an error" alive "$P8"
new_roster "$R8"
add_row "$R8" name=first-ever duration="1 minute" launched_at="$(iso_ago 600)" deliverable="$R8/absent.md"
expect_true "the first row to appear is watched" wait_exit "$P8" 20

# ============================================================
section "Section 6: path safety"
# ============================================================

R9="$(make_repo s9)"
rm -rf "$R9/.bionic/tmp"
mkdir -p "$TMPROOT/elsewhere-s9"
ln -s "$TMPROOT/elsewhere-s9" "$R9/.bionic/tmp"
sweep "$R9" arm --tick 1
expect_eq "a symlinked state directory REFUSES (exit 2)" "2" "$RC"
expect_contains "the refusal names the symbolic link" "symbolic link" "$OUT"
expect_false "nothing was written through the link" test -e "$TMPROOT/elsewhere-s9/sweeper-$SID.state"

R10="$(make_repo s10)"; new_roster "$R10"
ln -s "$TMPROOT/elsewhere-s10.state" "$(ledger_of "$R10")"
sweep "$R10" arm --tick 1
expect_eq "a symlinked ledger path REFUSES (exit 2)" "2" "$RC"
expect_false "nothing was written through the ledger link" test -e "$TMPROOT/elsewhere-s10.state"

# A symlinked ROSTER is not read (§8) — but the sweeper stays armed, so it must NAME what
# it cannot watch instead of looking healthy while watching nothing (6-axis C-2). Every
# other path-safety refusal in this script is loud; this branch is the arm's only one that
# keeps running, which is exactly why the ledger has to carry it.
R10B="$(make_repo s10b)"
printf 'roster-state/v1|status=confirmed|session=%s|name=elsewhere|deliverable=|duration=1 minute|\n' \
  "$SID" > "$TMPROOT/elsewhere-s10b-roster.state"
ln -s "$TMPROOT/elsewhere-s10b-roster.state" "$(roster_of "$R10B")"
sweep_bg "$R10B" "$TMPROOT/s10b.out" arm --tick 1; P10B="$BGPID"
expect_true "arm over a symlinked roster still arms" wait_grep 'event=arm' "$(ledger_of "$R10B")" 10
ARM10B="$(grep 'event=arm' "$(ledger_of "$R10B")" | head -1)"
expect_contains "the arm entry NAMES the symlinked roster as a degradation" \
  "symlinked-roster-unreadable" "$ARM10B"
expect_contains "…attributed to the roster rather than to a row" "(roster)" "$ARM10B"
expect_contains "the operator is told on stdout too" "symlinked-roster-unreadable" \
  "$(cat "$TMPROOT/s10b.out")"
expect_contains "no row from the symlinked file was read" "rows=0" "$ARM10B"
sweep "$R10B" retire; wait_exit "$P10B" 15

# A DANGLING symlinked roster is the same unwatchable state and must not be silent either.
R10C="$(make_repo s10c)"
ln -s "$TMPROOT/no-such-roster-s10c.state" "$(roster_of "$R10C")"
sweep_bg "$R10C" "$TMPROOT/s10c.out" arm --tick 1; P10C="$BGPID"
expect_true "arm over a dangling roster symlink still arms" wait_grep 'event=arm' "$(ledger_of "$R10C")" 10
expect_contains "…and names the degradation" "symlinked-roster-unreadable" \
  "$(grep 'event=arm' "$(ledger_of "$R10C")" | head -1)"
sweep "$R10C" retire; wait_exit "$P10C" 15

# ============================================================
section "Section 7: the ledger's pid is validated before it is believed (6-axis S-1)"
# ============================================================
#
# `pid=` is read out of a file in the repo's own .bionic/tmp — the directory the script
# header's threat model names as repo-controlled — and it reaches `kill -0` and, in
# `retire`, `kill -TERM`. In POSIX `kill` a NEGATIVE pid is a process group and `-1` is
# "every process the caller may signal", so an unvalidated `pid=-1` turns `retire` into a
# session-wide SIGTERM. `0` is the caller's own process group; `1` is init. No adversary is
# required: a truncated or partial write that leaves a `-` in the field lands in the same
# place, and the second-order damage is worse than the signal — `status` reports live=yes
# forever, so `arm` refuses permanently and the unarmed-dispatch nag goes quiet.
#
# The rejection is ASYMMETRIC, and the asymmetry is the whole of the Step-6 critic's F-1.
# Rejecting symmetrically — the entry reading as "no open arming" for signalling AND for
# arming AND for status alike — trades a fail-closed bug for a fail-open one: a corrupt
# line appended after a healthy one erased a genuinely live sweeper from all three readers
# at once, so `arm` started a second over it and `retire` closed only the second. Two live
# sweepers, unenumerable, which is the defect class this wave exists to end. So:
#   signalling  FAIL-OPEN   — `retire` never `kill`s a value it could not validate.
#   arming      FAIL-CLOSED — an unreadable open entry means "a sweeper MAY be live",
#                             and a second is refused rather than stacked over it.
#   status      NEITHER     — it may not answer live=no over an entry it cannot read;
#                             the third answer is live=unknown.
# Asserted per rejected shape below: status reports live=unknown and exits non-zero (the
# dispatch nag warns), arm REFUSES naming the escape, retire neither signals nor journals
# a close — and deleting the ledger restores arming, which is the escape being real.
#
# RED evidence for this section is taken against a copy whose `kill -TERM` is neutered
# (W4_SWEEPER_UNDER_TEST above). Running it against an unguarded sweeper would terminate
# the operator's own session, which is the finding.

plant_arm() {  # <pid literal> <ledger path>
  {
    printf '# bionic session sweeper ledger — schema sweeper-ledger/v1 — machine-local, safe to delete\n'
    printf 'sweeper-ledger/v1|event=arm|at=2026-08-06T00:00:00Z|epoch=1780000000|pid=%s|tick=120|session=%s|rows=0|degraded=\n' \
      "$1" "$SID"
  } > "$2"
}

_bad=0
for BADPID in "-1" "-99999" "0" "1" "junk" "12x" " "; do
  _bad=$((_bad + 1))
  RB="$(make_repo "s7-$_bad")"; new_roster "$RB"
  LB="$(ledger_of "$RB")"
  plant_arm "$BADPID" "$LB"

  sweep "$RB" status
  expect_eq "pid=[$BADPID]: status exits non-zero (nothing is PROVABLY live)" "1" "$RC"
  expect_contains "pid=[$BADPID]: status answers live=unknown, never live=no" "live=unknown" "$OUT"
  expect_absent "pid=[$BADPID]: status does not answer live=no over an unreadable entry" "live=no" "$OUT"
  expect_absent "pid=[$BADPID]: status never republishes the unusable pid" "pid=$BADPID|" "$OUT"

  sweep "$RB" retire
  expect_eq "pid=[$BADPID]: retire exits 0" "0" "$RC"
  expect_eq "pid=[$BADPID]: retire journals NO close over an unusable pid" \
    "0" "$(grep -c 'event=retire' "$LB")"
  expect_contains "pid=[$BADPID]: retire says there was nothing to retire" "nothing to retire" "$OUT"

  # FAIL-CLOSED: the script cannot tell this state from a live-sweeper one, so it refuses
  # unconditionally — no live process is required anywhere for the refusal to be right.
  sweep "$RB" arm --tick 30
  expect_eq "pid=[$BADPID]: arm REFUSES over the unreadable entry (exit 1)" "1" "$RC"
  expect_contains "pid=[$BADPID]: the refusal is named REFUSED" "REFUSED" "$OUT"
  expect_contains "pid=[$BADPID]: the refusal names the unreadable value" \
    "unreadable (\"$BADPID\")" "$OUT"
  expect_contains "pid=[$BADPID]: the refusal names the escape (the ledger path)" "$LB" "$OUT"
  expect_eq "pid=[$BADPID]: nothing was armed (the planted entry is the only one)" \
    "1" "$(grep -c 'event=arm' "$LB")"

  # …and the escape is REAL: the ledger is machine-local, so deleting it un-wedges arming.
  rm -f "$LB"
  sweep_bg "$RB" "$TMPROOT/s7-$_bad.out" arm --tick 30; PB="$BGPID"
  expect_true "pid=[$BADPID]: after deleting the ledger, arm succeeds" \
    wait_grep "pid=$PB" "$LB" 10
  sweep "$RB" retire; wait_exit "$PB" 15
done

# ---- F-2's truth-test: a REAL live sweeper the readers may never deny ----
#
# Every agreement test in this wave proves the three readers render ONE answer; none asked
# whether that answer is TRUE of the world. In the critic's reproduction all three agreed
# and all three were wrong. So: an actually-running sweeper, then the corrupt line appended
# after its healthy one — the exact byte sequence a truncated write produces — and the
# question is not "do the readers agree" but "is a live process still visible".
R7F="$(make_repo s7-f1)"; new_roster "$R7F"
L7F="$(ledger_of "$R7F")"
sweep_bg "$R7F" "$TMPROOT/s7f.out" arm --tick 30; P7F="$BGPID"
expect_true "a real sweeper is armed and ledgered" wait_grep "pid=$P7F" "$L7F" 10
printf 'sweeper-ledger/v1|event=arm|at=2026-08-06T00:00:00Z|epoch=1780000000|pid=-1|tick=120|session=%s|rows=0|degraded=\n' \
  "$SID" >> "$L7F"

sweep "$R7F" status
expect_true "F-1: the live sweeper is still running" alive "$P7F"
expect_absent "F-1: status does NOT deny a live sweeper it can still see" "live=no" "$OUT"
expect_contains "F-1: status still reports it live" "live=yes" "$OUT"
expect_contains "F-1: …by its own well-formed pid" "pid=$P7F|" "$OUT"
expect_contains "F-1: …and still names the corrupt entry" "unreadable (\"-1\")" "$OUT"

sweep "$R7F" arm --tick 5
expect_eq "F-1: a second arm is REFUSED (exit 1)" "1" "$RC"
expect_contains "F-1: the refusal is named REFUSED" "REFUSED" "$OUT"

sweep "$R7F" retire
expect_eq "F-1: retire exits 0" "0" "$RC"
expect_eq "F-1: retire journals exactly one close" "1" "$(grep -c 'event=retire' "$L7F")"
expect_contains "F-1: …naming the live pid, not the unvalidated value" "pid=$P7F|" \
  "$(grep 'event=retire' "$L7F")"
expect_absent "F-1: nothing was signalled with the bad value" "pid=-1|session=$SID|by=retire" \
  "$(grep 'event=retire' "$L7F")"
expect_true "F-1: the real sweeper is actually gone" wait_exit "$P7F" 15

# The bad entry outlives the retire it never named, and arming stays closed until the
# operator takes the escape — an unreadable entry can never be proven closed.
sweep "$R7F" arm --tick 30
expect_eq "F-1: arming stays refused while the unreadable entry stands" "1" "$RC"
rm -f "$L7F"
sweep_bg "$R7F" "$TMPROOT/s7f2.out" arm --tick 30; P7F2="$BGPID"
expect_true "F-1: deleting the ledger restores arming" wait_grep "pid=$P7F2" "$L7F" 10
sweep "$R7F" retire; wait_exit "$P7F2" 15

# The guard rejects unusable shapes ONLY: a well-formed pid still refuses a second arm,
# so the fix cannot have quietly disabled the single-live-sweeper invariant it protects.
R7L="$(make_repo s7-live)"; new_roster "$R7L"
sweep_bg "$R7L" "$TMPROOT/s7l.out" arm --tick 30; P7L="$BGPID"
expect_true "a well-formed live pid is still believed" wait_grep "pid=$P7L" "$(ledger_of "$R7L")" 10
sweep "$R7L" arm --tick 5
expect_eq "…and still refuses a second arm (exit 1)" "1" "$RC"
sweep "$R7L" retire; wait_exit "$P7L" 15

# ============================================================
section "Section 8: ack — the orchestrator's completion event"
# ============================================================
#
# A roster row has no completion event. A finished agent whose row carries no
# machine-visible deliverable reads as overdue forever once its declared duration elapses,
# so the sweeper fires one tick after every re-arm until someone hand-prunes the roster.
# The orchestrator already verifies every agent's completion; `ack` is that verification
# reaching the roster. An acked row takes the SAME exemption a satisfied row takes — it is
# out of every finding class, not out of one of them.

# --- the discriminating pair: two identical overdue rows, one acked ---
R11="$(make_repo s11)"; new_roster "$R11"
add_row "$R11" name=done-agent  duration="1 minute" launched_at="$(iso_ago 600)" deliverable="$R11/absent-a.md"
add_row "$R11" name=still-going duration="1 minute" launched_at="$(iso_ago 600)" deliverable="$R11/absent-b.md"
sweep "$R11" ack done-agent
expect_eq "ack exits 0" "0" "$RC"
expect_contains "ack journals an ack event" "event=ack" "$(cat "$(ledger_of "$R11")" 2>/dev/null)"
expect_contains "the ack entry names the row it closed" "name=done-agent" \
  "$(grep 'event=ack' "$(ledger_of "$R11")" 2>/dev/null)"
expect_contains "the ack entry carries the session" "session=$SID" \
  "$(grep 'event=ack' "$(ledger_of "$R11")" 2>/dev/null)"
sweep_bg "$R11" "$TMPROOT/s11.out" arm --tick 1; P11="$BGPID"
expect_true "the un-acked twin still breaks its promise" wait_exit "$P11" 20
F11="$(cat "$(findings_of "$R11")" 2>/dev/null)"
expect_contains "…and is delivered as overdue" "name=still-going" "$F11"
expect_absent "the acked row raises NO finding under identical conditions" "name=done-agent" "$F11"

# --- the ack outlives the delivering exit and the re-arm that follows it ---
sweep_bg "$R11" "$TMPROOT/s11b.out" arm --tick 1; P11B="$BGPID"
expect_true "the re-armed sweeper fires again on the un-acked row" wait_exit "$P11B" 20
F11B="$(cat "$(findings_of "$R11")" 2>/dev/null)"
expect_eq "…twice over, once per arming" "2" "$(printf '%s\n' "$F11B" | grep -c 'name=still-going')"
expect_absent "the ack survives the exit and the re-arm" "name=done-agent" "$F11B"

# --- exempt from EVERY class, not from one of them ---
R12="$(make_repo s12)"; new_roster "$R12"
PROG12="$R12/p.md"; echo "old" > "$PROG12"; backdate "$PROG12" 900
add_row "$R12" name=every-class claims="bionic-no-such-process-marker-91731" \
        progress="$PROG12" cadence="10 seconds" duration="1 minute" \
        launched_at="$(iso_ago 3600)" deliverable="$R12/absent.md"
sweep "$R12" ack every-class
sweep_bg "$R12" "$TMPROOT/s12.out" arm --tick 1; P12="$BGPID"
sleep 3
expect_true "an acked row is exempt from dead-claim, stale-progress and overdue alike" alive "$P12"
expect_false "…and nothing at all is written to the findings file" test -s "$(findings_of "$R12")"
sweep "$R12" retire; wait_exit "$P12" 15

# --- several names in one call, and a repeat that does not double-count ---
R13="$(make_repo s13)"; new_roster "$R13"
for n in one two three; do
  add_row "$R13" name="row-$n" duration="1 minute" launched_at="$(iso_ago 600)" \
          deliverable="$R13/absent-$n.md"
done
sweep "$R13" ack row-one row-two row-three
expect_eq "ack takes several names in one call" "3" "$(grep -c 'event=ack' "$(ledger_of "$R13")")"
sweep_bg "$R13" "$TMPROOT/s13.out" arm --tick 1; P13="$BGPID"
sleep 3
expect_true "every named row is exempt" alive "$P13"
expect_false "a fully acked roster wakes nobody" test -s "$(findings_of "$R13")"
sweep "$R13" ack row-one
expect_eq "an ack against a live sweeper exits 0" "0" "$RC"
expect_true "…and never signals or stops it" alive "$P13"
sweep "$R13" status
expect_eq "status over a live arming still exits 0" "0" "$RC"
expect_contains "status counts the acked rows, a repeat counting once" "acked=3" "$OUT"
sweep "$R13" retire; wait_exit "$P13" 15

sweep "$R1" status
expect_contains "status with nothing acked reports acked=0" "acked=0" "$OUT"

# --- a name not on the roster: warned and recorded, never refused (assumption A-4) ---
R14="$(make_repo s14)"; new_roster "$R14"
add_row "$R14" name=real-row duration="4 hours" deliverable="$R14/absent.md"
sweep "$R14" ack ghost-row
expect_eq "ack of a name not on the roster still exits 0" "0" "$RC"
expect_contains "…and says which name was not found" "ghost-row" "$OUT"
expect_contains "…and records it anyway" "name=ghost-row" "$(grep 'event=ack' "$(ledger_of "$R14")")"
add_row "$R14" name=ghost-row duration="1 minute" launched_at="$(iso_ago 600)" \
        deliverable="$R14/absent-g.md"
sweep_bg "$R14" "$TMPROOT/s14.out" arm --tick 1; P14="$BGPID"
sleep 3
expect_true "a row that arrives AFTER its ack is exempt too" alive "$P14"
sweep "$R14" retire; wait_exit "$P14" 15

sweep "$R14" ack
expect_eq "ack with no name is a usage error (exit 2)" "2" "$RC"
expect_contains "the usage names ack" "ack <name>" "$OUT"

# ============================================================
printf '\n──────────────────────────────────────────────\n'
printf 'session-sweeper: %d passed, %d failed, %d total\n' "$PASS" "$FAIL" "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
