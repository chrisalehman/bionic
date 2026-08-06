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

SWEEPER="$(cd "$(dirname "$0")" && pwd)/session-sweeper.sh"
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

# ============================================================
printf '\n──────────────────────────────────────────────\n'
printf 'session-sweeper: %d passed, %d failed, %d total\n' "$PASS" "$FAIL" "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
