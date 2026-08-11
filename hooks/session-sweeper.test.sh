#!/bin/bash
# Tests for hooks/session-sweeper.sh — the landing verdict and the ack that closes a row.
#
# Governing design: .bionic/docs/specs/epic-16-landing-contract/
# wave-02-fact-based-supervision.spec.md §Design (deletion inventory, interview-ratified
# 2026-08-11), succeeding epic-15 wave-04's watcher spec. Serves AC-9 (the deleted
# watch-half leaves nothing behind) and carries wave-01's verdict coverage forward intact.
#
# WHAT THIS SUITE NO LONGER DRIVES. Until epic-16 wave-02 the sweeper was also a resident
# watcher — armed once per session, sleeping on a tick, reporting findings by exiting — and
# most of this file drove that loop. The loop, the `arm`/`retire`/`status` verbs, the
# findings file and the advisory satisfied-check are deleted, so their cases are gone with
# them. Nothing here starts a background process any more; every case is one foreground
# invocation that reads the disk and exits. The assertions those cases carried that were
# about something OTHER than the loop were migrated rather than dropped: the prose
# threshold parser is now driven through `verdict`'s STILL-LIVE path (Section 2), path
# safety through the two surviving verbs (Section 3), and the ack exemption through the
# ledger it writes (Section 4).
#
# Hermetic: every case runs inside a throwaway sandbox git repo. Nothing reads or writes
# the real .bionic/tmp, the real roster, or a live wave. The only machine-global fact any
# case consults is process liveness, and the process it consults is one this suite starts
# and kills itself.
#
# CLOCK DISCIPLINE (house rule): nothing here sleeps for a declared threshold. Launch times
# are roster fields (`iso_ago`) and artifact ages are mtimes (`backdate`, which is
# `touch -t`), so every threshold is fixture data.
#
# FIXTURE FIDELITY: roster rows are generated to the roster-state/v1 schema exactly as
# written by hooks/dispatch-preflight.sh (field set and order), shaped after the
# confirmed-row fixture in hooks/stop-check.test.sh. This suite's subject is the READER;
# hooks/dispatch-preflight.test.sh owns the writer. Rows are hand-built here for the same
# reason that suite hand-builds them: the shapes under test (an unparseable cadence, a
# 45-minute-old launch) are not producible from a live dispatch inside a test.
#
# Usage: bash hooks/session-sweeper.test.sh

set -uo pipefail

# Overridable so this suite can be driven against a MUTATED COPY of the sweeper without the
# shipped file ever being modified — the same substitution
# tests/cross-gate-agreement.test.sh offers for its parties, and the way to take RED
# evidence for any predicate case without editing what ships:
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
state_dir_of(){ printf '%s/.bionic/tmp'                          "$1"; }

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

# Emits one roster-state/v1 row. Field set and ORDER are those of the roster writer in
# hooks/dispatch-preflight.sh (the `ROW=` assignment, `absent-deliverable wall` era —
# `waiver=` is part of that row and was missing here until the verdict verb needed it);
# every unnamed field takes the empty value that gate writes when a brief declares none.
mkrow() {  # <key=value>...
  local status=confirmed session="$SID" name=agent agent_id=a000 launched_at=""
  local subagent_type=implementor model=opus deliverable="" duration="" progress=""
  local claims="" cadence="" waiver="" tool_use_id=toolu_x source=declared kv
  for kv in "$@"; do
    case "$kv" in
      waiver=*)      waiver="${kv#*=}" ;;
      source=*)      source="${kv#*=}" ;;
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
  printf 'roster-state/v1|status=%s|session=%s|name=%s|agent_id=%s|launched_at=%s|subagent_type=%s|model=%s|deliverable=%s|source=%s|duration=%s|progress=%s|claims=%s|cadence=%s|absent=|waiver=%s|tool_use_id=%s\n' \
    "$status" "$session" "$name" "$agent_id" "$launched_at" "$subagent_type" "$model" \
    "$deliverable" "$source" "$duration" "$progress" "$claims" "$cadence" "$waiver" "$tool_use_id"
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

# Every case here is a fast path: this script reads the disk and exits, and nothing it does
# can legitimately block. If one of them BLOCKS, a suite that hangs on it would wedge
# `bash tests/run.sh` rather than report the defect. So the runner is its own watchdog:
# RC=124 on a run that overruns the bound, which fails whatever the case expected.
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

# Like `sweep`, but keeps the two streams APART. A verb that exits 0 while the shell
# complains on stderr is invisible to a merged capture — that is precisely the shape of the
# defect Section 8's live-caught case pins — so the cases that assert stderr SILENCE need
# the streams separated. Same watchdog, same globals plus ERR.
sweep_streams() {  # <repo> <args...> -> sets OUT, ERR, RC
  local repo="$1"; shift
  ( cd "$repo" && exec env CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER" "$@" ) \
    > "$TMPROOT/sweep.out" 2> "$TMPROOT/sweep.err" &
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
  OUT="$(cat "$TMPROOT/sweep.out")"; ERR="$(cat "$TMPROOT/sweep.err")"
}

# ============================================================
section "Section 1: surface — the two verbs, and the refusals"
# ============================================================

R1="$(make_repo s1)"; new_roster "$R1"

OUT="$( cd "$R1" && CLAUDE_CODE_SESSION_ID="" bash "$SWEEPER" verdict 2>&1 )"; RC=$?
expect_eq "no session key REFUSES with exit 3" "3" "$RC"
expect_contains "no session key: the refusal says why" "session key" "$OUT"

sweep "$R1"
expect_eq "no verb is a usage error (exit 2)" "2" "$RC"
expect_contains "usage names verdict" "verdict" "$OUT"
expect_contains "usage names ack" "ack" "$OUT"

sweep "$R1" sweep-everything
expect_eq "an unknown verb is a usage error (exit 2)" "2" "$RC"

# THE DELETED VERBS ARE GONE, not silently accepted. `arm`, `retire` and `status` were the
# resident watcher's whole surface; a caller still spelling one of them gets the same
# unknown-verb refusal as any other typo rather than a no-op that looks like it worked.
for _dead in arm retire status; do
  sweep "$R1" "$_dead"
  expect_eq "the deleted verb \"$_dead\" is refused as unknown (exit 2)" "2" "$RC"
  expect_contains "…and the usage names only the two surviving verbs" "verdict [<name>]" "$OUT"
done
sweep "$R1" arm --tick 1
expect_eq "the deleted --tick flag has no verb left to take it (exit 2)" "2" "$RC"

# The source-level half of this claim — that no deleted symbol survives anywhere in the
# repo — is AC-9's grep inventory and deliberately NOT restated here: a list of the dead
# names inside a test file is itself a reference the inventory would then have to explain
# away. Behavior is what this suite owns; the inventory owns the corpus.

# ============================================================
section "Section 2: the prose-lifted threshold parser (migrated from the deleted loop)"
# ============================================================
#
# `cadence=` arrives as prose the dispatch gate lifted out of a brief. The parser is
# deterministic: units it knows, a range read at its generous end, and no guess for anything
# else. It used to be driven through the tick loop's stale-progress class; with that loop
# deleted the ONE surviving consumer is `row_still_live`, which is where the same table is
# asked now. The observable is the verdict: a row whose progress artifact was written INSIDE
# its declared cadence is STILL-LIVE, and the same row once the promise lapses is UNMET.
# Every form therefore carries its own paired positive by construction.
#
# Each row declares an absent deliverable, so the only thing separating STILL-LIVE from
# UNMET is whether the parser read the cadence and the progress mtime cleared it.

R2="$(make_repo s2parse)"; new_roster "$R2"

# <name> <cadence prose> <progress age, seconds> <expected state>
parse_case() {
  local name="$1" cadence="$2" age="$3" want="$4"
  local prog="$R2/prog-$name.md"
  echo "working" > "$prog"; backdate "$prog" "$age"
  add_row "$R2" name="$name" progress="$prog" cadence="$cadence" \
          deliverable="$R2/absent-$name.md" duration="4 hours" launched_at="$(iso_ago 60)"
  sweep "$R2" verdict "$name"
  expect_contains "cadence \"$cadence\" at ${age}s reads $want" "name=$name|state=$want" "$OUT"
}

# INSIDE the declared cadence — the parser read the unit and the row is still working.
parse_case in-minutes  "20 minutes"      600  STILL-LIVE
parse_case in-tilde    "every ~10 min"   300  STILL-LIVE
parse_case in-hour     "1 hour"         1800  STILL-LIVE
parse_case in-seconds  "90 seconds"       30  STILL-LIVE
parse_case in-short    "2m"               30  STILL-LIVE

# PAST it — the same units, the same rows, one fact about the disk changed.
parse_case out-minutes "20 minutes"     1500  UNMET
parse_case out-tilde   "every ~10 min"   900  UNMET
parse_case out-hour    "1 hour"         4200  UNMET
parse_case out-seconds "90 seconds"      200  UNMET
parse_case out-short   "2m"              200  UNMET

# A RANGE is read at its GENEROUS end: 35 minutes is inside "30–40 minutes" and 45 is not.
# The strict reading would call the first one UNMET, so this pair is what discriminates.
parse_case in-range    "30–40 minutes"  2100  STILL-LIVE
parse_case out-range   "30–40 minutes"  2700  UNMET

# UNREADABLE PROSE IS NOT A GUESSED INTERVAL. The parser refuses, so no cadence clears the
# row and the verdict falls through to the disk's answer — never to an invented threshold.
parse_case mush        "whenever it feels right" 30 UNMET
parse_case zero        "0 minutes"               30 UNMET
parse_case units       "20 parsecs"              30 UNMET

# NOT ASSERTED HERE, and deliberately: two forms the parser's own header says it refuses are
# in fact READ, and reading them wrong. `0.5h` matches the trailing `5h` and becomes 5 hours;
# `1h30m` matches only the trailing `30m` and becomes 30 minutes, because the first pair is
# rejected for being followed by a digit. Both are pre-existing defects in a predicate this
# slice only inherited — epic-16 wave-02 S1 deletes machinery and changes no surviving
# behavior — so they are named here and carried out of the slice as a concern rather than
# pinned in either direction. Asserting the current answer would ratify the misread;
# asserting the documented one would fail a suite over a defect this slice did not cause.

# The paired positive for the whole refusal class: the SAME 30-second-old artifact under a
# cadence the parser CAN read is STILL-LIVE, so the four rows above failed on the prose and
# not on the clock.
parse_case readable    "5 minutes"                30 STILL-LIVE

# A row with a cadence but NO progress path has nothing for the parser to clear.
add_row "$R2" name=no-progress cadence="5 minutes" deliverable="$R2/absent-np.md" \
        duration="4 hours" launched_at="$(iso_ago 600)"
sweep "$R2" verdict no-progress
expect_contains "a cadence with no progress path leaves the row UNMET" \
  "name=no-progress|state=UNMET" "$OUT"

# A progress artifact NEVER WRITTEN is dated from the launch, exactly as one that stopped
# being written would be: inside the cadence it is still live, past it, it is not.
add_row "$R2" name=never-written progress="$R2/no-such-progress.md" cadence="10 minutes" \
        deliverable="$R2/absent-nw.md" duration="4 hours" launched_at="$(iso_ago 120)"
sweep "$R2" verdict never-written
expect_contains "an unwritten progress artifact inside the cadence dates from the launch" \
  "name=never-written|state=STILL-LIVE" "$OUT"
add_row "$R2" name=never-written-late progress="$R2/no-such-progress.md" cadence="10 minutes" \
        deliverable="$R2/absent-nwl.md" duration="4 hours" launched_at="$(iso_ago 1800)"
sweep "$R2" verdict never-written-late
expect_contains "…and past it the same row is UNMET" \
  "name=never-written-late|state=UNMET" "$OUT"

# ============================================================
section "Section 3: path safety"
# ============================================================
#
# Hostile-repo posture (design §8): a repo controls its own .bionic/ contents, so every path
# this script writes is checked for symlink redirection first. These cases used to be driven
# through `arm`, the only verb that wrote at the time; they are driven through the two
# surviving verbs now, which is where the same refusals live.

R3="$(make_repo s3dir)"
rm -rf "$R3/.bionic/tmp"
mkdir -p "$TMPROOT/elsewhere-s3"
ln -s "$TMPROOT/elsewhere-s3" "$R3/.bionic/tmp"
sweep "$R3" ack somebody
expect_eq "a symlinked state directory REFUSES the writing verb (exit 2)" "2" "$RC"
expect_contains "the refusal names the symbolic link" "symbolic link" "$OUT"
expect_false "nothing was written through the link" test -e "$TMPROOT/elsewhere-s3/sweeper-$SID.state"
sweep "$R3" verdict
expect_eq "…and the reading verb refuses over it too (exit 2)" "2" "$RC"

R3B="$(make_repo s3ledger)"; new_roster "$R3B"
ln -s "$TMPROOT/elsewhere-s3-ledger.state" "$(ledger_of "$R3B")"
sweep "$R3B" ack somebody
expect_eq "a symlinked ledger path REFUSES (exit 2)" "2" "$RC"
expect_false "nothing was written through the ledger link" test -e "$TMPROOT/elsewhere-s3-ledger.state"
# The guard sits ahead of the verb dispatch, so the READING verb refuses over the same link
# even though it would never have opened the ledger. Pinned as-is rather than narrowed: the
# refusal is unchanged from wave-01, and a redirected state directory is a fact the operator
# needs told whichever question was being asked.
sweep "$R3B" verdict
expect_eq "…and the reading verb refuses over the same link too (exit 2)" "2" "$RC"
expect_contains "…naming the link rather than answering over it" "symbolic link" "$OUT"

# A symlinked ROSTER splits the two verbs, and the split is the point. `verdict` REFUSES:
# its answer is a claim about contracts, and a clean one computed over a roster the script
# was redirected away from is a false statement. `ack` RECORDS ANYWAY: its answer is a
# ledger line the operator asked for, and refusing it would deny the one action still
# available precisely when the roster cannot be read.
R3C="$(make_repo s3roster)"
printf 'roster-state/v1|status=confirmed|session=%s|name=elsewhere|deliverable=|duration=1 minute|\n' \
  "$SID" > "$TMPROOT/elsewhere-s3-roster.state"
ln -s "$TMPROOT/elsewhere-s3-roster.state" "$(roster_of "$R3C")"
sweep "$R3C" verdict
expect_eq "verdict over a symlinked roster REFUSES (exit 2), never a clean session" "2" "$RC"
expect_contains "…and says why" "symbolic link" "$OUT"
expect_absent "…and invents no verdict line for the rows it did not read" "landing-verdict/v1|" "$OUT"
sweep "$R3C" ack elsewhere
expect_eq "ack over a symlinked roster still records (exit 0)" "0" "$RC"
expect_contains "…and warns rather than claiming the name is unknown on evidence it never had" \
  "elsewhere" "$OUT"
expect_contains "…journalling it all the same" "name=elsewhere" \
  "$(grep 'event=ack' "$(ledger_of "$R3C")" 2>/dev/null)"

# A DANGLING roster symlink is the same unreadable state and is answered the same way —
# tested BEFORE `-f`, which is true THROUGH a link to a file and false for a dangling one.
R3D="$(make_repo s3dangle)"
ln -s "$TMPROOT/no-such-roster-s3d.state" "$(roster_of "$R3D")"
sweep "$R3D" verdict
expect_eq "verdict over a DANGLING roster symlink refuses the same way (exit 2)" "2" "$RC"

# ============================================================
section "Section 4: ack — the orchestrator's completion event"
# ============================================================
#
# A roster row has no completion event of its own. An agent that finished but declared no
# machine-visible deliverable leaves nothing on disk to read, and the orchestrator verifies
# every agent's completion anyway; `ack` is that verification made durable.
#
# WHAT OBSERVES AN ACK, since the watcher was deleted: the ledger it appends to, and the
# count it reports back. The old cases here observed it through the tick loop — an acked row
# raised no finding where its un-acked twin did — and that observable is gone with the loop.
# The fact under test is the same one: an ack is recorded, once per name, durably, and it
# survives everything.

R4="$(make_repo s4ack)"; new_roster "$R4"
add_row "$R4" name=done-agent  duration="1 minute" launched_at="$(iso_ago 600)" deliverable="$R4/absent-a.md"
add_row "$R4" name=still-going duration="1 minute" launched_at="$(iso_ago 600)" deliverable="$R4/absent-b.md"
sweep "$R4" ack done-agent
expect_eq "ack exits 0" "0" "$RC"
expect_contains "ack journals an ack event" "event=ack" "$(cat "$(ledger_of "$R4")" 2>/dev/null)"
expect_contains "the ack entry names the row it closed" "name=done-agent" \
  "$(grep 'event=ack' "$(ledger_of "$R4")" 2>/dev/null)"
expect_contains "the ack entry carries the session" "session=$SID" \
  "$(grep 'event=ack' "$(ledger_of "$R4")" 2>/dev/null)"
expect_contains "…and the count comes back" "1 row(s) acked" "$OUT"
# The discriminating half: the twin row was NOT closed by its neighbour's ack.
expect_absent "the un-acked twin is not in the ledger" "name=still-going" \
  "$(cat "$(ledger_of "$R4")" 2>/dev/null)"

# --- several names in one call, and a repeat that does not double-count ---
R5="$(make_repo s5ack)"; new_roster "$R5"
for n in one two three; do
  add_row "$R5" name="row-$n" duration="1 minute" launched_at="$(iso_ago 600)" \
          deliverable="$R5/absent-$n.md"
done
sweep "$R5" ack row-one row-two row-three
expect_eq "ack takes several names in one call" "3" "$(grep -c 'event=ack' "$(ledger_of "$R5")")"
expect_contains "…and counts them" "3 row(s) acked" "$OUT"
sweep "$R5" ack row-one
expect_eq "a repeated ack still exits 0" "0" "$RC"
expect_eq "…and appends its line, append-only as the ledger is" "4" \
  "$(grep -c 'event=ack' "$(ledger_of "$R5")")"
expect_contains "…while the COUNT of closed rows is de-duplicated by name" "3 row(s) acked" "$OUT"

# --- a name not on the roster: warned and recorded, never refused (assumption A-4) ---
R6="$(make_repo s6ack)"; new_roster "$R6"
add_row "$R6" name=real-row duration="4 hours" deliverable="$R6/absent.md"
sweep "$R6" ack ghost-row
expect_eq "ack of a name not on the roster still exits 0" "0" "$RC"
expect_contains "…and says which name was not found" "ghost-row" "$OUT"
expect_contains "…and records it anyway" "name=ghost-row" "$(grep 'event=ack' "$(ledger_of "$R6")")"
# An ack can legitimately precede its row: the roster is written by the dispatch gate, and
# the row that arrives afterwards is closed by the ack already standing for it.
add_row "$R6" name=ghost-row duration="1 minute" launched_at="$(iso_ago 600)" \
        deliverable="$R6/absent-g.md"
sweep "$R6" ack second-ghost
expect_contains "a row that arrived AFTER its ack is counted as closed" "2 row(s) acked" "$OUT"

sweep "$R6" ack
expect_eq "ack with no name is a usage error (exit 2)" "2" "$RC"
expect_contains "the usage names ack" "ack <name>" "$OUT"

# --- the FIRST ack over an existing ledger says nothing on stderr (live-caught, post-w4) ---
#
# The state a live session hit: a ledger that exists and carries lines, no ack journalled
# yet, and a name whose roster row is not there. The ack succeeded and still printed a shell
# diagnostic, because `grep -c` prints its count AND exits 1 when that count is zero: the
# `|| printf 0` fallback appended a SECOND line to an already-complete answer, and the
# two-line "0" reached an integer test. Succeeding-while-complaining is what makes this worth
# a case of its own — every other ack assertion here passes in the defective state, since
# none of them looks at stderr alone. The pre-ack ledger is the bare header the script's own
# first write lays down, which is the zero-count shape the defect lived on.
R7="$(make_repo s7ack)"; new_roster "$R7"
printf '# bionic session sweeper ledger — schema sweeper-ledger/v1 — machine-local, safe to delete\n' \
  > "$(ledger_of "$R7")"
sweep_streams "$R7" ack late-row
expect_eq "the first ack over a header-only ledger exits 0" "0" "$RC"
expect_eq "…and writes NOTHING to stderr" "" "$ERR"
expect_contains "…while stdout still confirms the ack" "acked: late-row" "$OUT"
expect_contains "…and journals it" "name=late-row" \
  "$(grep 'event=ack' "$(ledger_of "$R7")" 2>/dev/null)"

# --- an ack is durable: a second process reads it back ---
sweep "$R7" ack another-row
expect_contains "a later invocation counts the earlier ack too" "2 row(s) acked" "$OUT"

# ============================================================
section "Section 5: verdict — the landing readback (epic-16 w1 AC-3, AC-4)"
# ============================================================
#
# The LANDING question: did this contract land? The STRICT predicate answers it — exists
# AND non-empty AND mtime after the row's own `launched_at`. Since epic-16 wave-02 it is the
# only delivered-predicate this script owns; the looser reading it once shared the file with
# died with the watch loop rather than being promoted into it. A file that was already on
# disk when the agent was dispatched is
# not that agent's delivery, and saying so is the whole point — the same three conjuncts
# are what the landing gate reads back to a stopping agent.
#
# EVERY NEGATIVE HERE CARRIES ITS PAIRED POSITIVE (AC-4's absence-readback rule): the same
# row, the same command, one fact about the disk changed, and the state flips. A negative
# case alone cannot tell "the predicate caught it" from "the verb never looked".
#
# Clock discipline is the house rule: launch times are roster fields (`iso_ago`) and file
# ages are mtimes (`backdate`, which is `touch -t`). Nothing here sleeps.

# --- the four conjuncts, each against its paired positive ---
RV="$(make_repo vc)"; new_roster "$RV"
L9="$(iso_ago 600)"
DEL9="$RV/report.md"; echo "the landed report" > "$DEL9"
add_row "$RV" name=lander deliverable="$DEL9" duration="4 hours" launched_at="$L9"

sweep "$RV" verdict lander
expect_eq "delivered: a met contract exits 0" "0" "$RC"
expect_contains "delivered: a machine line is printed" "landing-verdict/v1|" "$OUT"
expect_contains "delivered: the line names the row and its state" "name=lander|state=MET" "$OUT"
expect_contains "delivered: the line carries this session" "session=$SID" "$OUT"
expect_contains "delivered: the readback names the file it stat'd" "delivered=$DEL9" "$OUT"

: > "$DEL9"   # exists, zero bytes, written now — only the emptiness is wrong
sweep "$RV" verdict lander
expect_eq "empty: an empty deliverable is UNMET (exit 1)" "1" "$RC"
expect_contains "empty: the state is UNMET" "name=lander|state=UNMET" "$OUT"
expect_contains "empty: the failing conjunct is named" "empty=$DEL9" "$OUT"
expect_absent "empty: and it is not reported as missing" "missing=$DEL9" "$OUT"
echo "written for real this time" > "$DEL9"
sweep "$RV" verdict lander
expect_eq "empty→filled: the paired positive exits 0" "0" "$RC"
expect_contains "empty→filled: the paired positive is MET" "state=MET" "$OUT"

backdate "$DEL9" 1200   # non-empty, but last written 20 min ago against a 10-min-old launch
sweep "$RV" verdict lander
expect_eq "stale: a pre-launch file is UNMET (exit 1)" "1" "$RC"
expect_contains "stale: the failing conjunct is named" "stale=$DEL9" "$OUT"
expect_contains "stale: the detail quotes the row's own launched_at" "launched_at $L9" "$OUT"
expect_matches "stale: the detail renders the file's mtime as an ISO stamp" \
  "mtime [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z" "$OUT"
touch "$DEL9"
sweep "$RV" verdict lander
expect_eq "stale→rewritten: the paired positive exits 0" "0" "$RC"
expect_contains "stale→rewritten: the paired positive is MET" "state=MET" "$OUT"

rm -f "$DEL9"
sweep "$RV" verdict lander
expect_eq "missing: an absent deliverable is UNMET (exit 1)" "1" "$RC"
expect_contains "missing: the failing conjunct is named" "missing=$DEL9" "$OUT"
expect_absent "missing: and it is not reported as empty" "empty=$DEL9" "$OUT"
echo "finally" > "$DEL9"
sweep "$RV" verdict lander
expect_eq "missing→written: the paired positive exits 0" "0" "$RC"
expect_contains "missing→written: the paired positive is MET" "state=MET" "$OUT"

# --- a partial set names ONLY what failed ---
RVP="$(make_repo vp)"; new_roster "$RVP"
echo "the first half" > "$RVP/one.md"
add_row "$RVP" name=halfway deliverable="$RVP/one.md,$RVP/two.md" duration="4 hours" \
        launched_at="$(iso_ago 600)"
sweep "$RVP" verdict halfway
expect_eq "partial: one absent deliverable is UNMET" "1" "$RC"
expect_contains "partial: the absent one is named" "missing=$RVP/two.md" "$OUT"
expect_absent "partial: the delivered one is not named as a failure" "missing=$RVP/one.md" "$OUT"

# --- a directory deliverable: delivered when a file lives in it (the sibling reading) ---
RVD="$(make_repo vd)"; new_roster "$RVD"
mkdir -p "$RVD/record"
add_row "$RVD" name=dirrow deliverable="$RVD/record" duration="4 hours" launched_at="$(iso_ago 600)"
sweep "$RVD" verdict dirrow
expect_eq "empty directory: UNMET (a created path is not a written deliverable)" "1" "$RC"
expect_contains "empty directory: named as empty, never as missing" "empty=$RVD/record" "$OUT"
echo "a landed artifact" > "$RVD/record/report.md"
sweep "$RVD" verdict dirrow
expect_eq "directory with a file in it: the paired positive exits 0" "0" "$RC"
expect_contains "directory with a file in it: MET" "state=MET" "$OUT"

# --- bare verdict over one row of every state: four lines, exit 1 ---
RVB="$(make_repo vb)"; new_roster "$RVB"
L9B="$(iso_ago 600)"
echo "landed" > "$RVB/met.md"
add_row "$RVB" name=row-met    deliverable="$RVB/met.md"   duration="4 hours" launched_at="$L9B"
add_row "$RVB" name=row-unmet  deliverable="$RVB/never.md" duration="4 hours" launched_at="$L9B"
# FIXTURE FIDELITY (Step-6 review S-1): a genuine waiver row declares NO deliverable —
# the wall's own waiver label reads "why this dispatch produces nothing durable". A row
# carrying BOTH a declared artifact and a waiver is contradictory, and Section 7 is where
# that shape is answered for; it must not be the fixture that stands for WAIVED.
add_row "$RVB" name=row-waived duration="4 hours" launched_at="$L9B" \
        waiver="exploratory probe: no artifact expected"
CLAIM9="$TMPROOT/bionic-verdict-marker-55831.sh"
printf '#!/bin/bash\nsleep 120\n' > "$CLAIM9"; chmod +x "$CLAIM9"
bash "$CLAIM9" & CLAIM9PID=$!; BG_PIDS="$BG_PIDS $CLAIM9PID"
add_row "$RVB" name=row-live claims="$CLAIM9" deliverable="$RVB/never3.md" duration="4 hours" \
        launched_at="$L9B"

sweep "$RVB" verdict
expect_eq "bare verdict: one UNMET row makes the whole run exit 1" "1" "$RC"
expect_eq "bare verdict: one machine line per row, no more" "4" \
  "$(printf '%s\n' "$OUT" | grep -c '^landing-verdict/v1|')"
expect_contains "bare verdict: the delivered row reads MET" "name=row-met|state=MET" "$OUT"
expect_contains "bare verdict: the undelivered row reads UNMET" "name=row-unmet|state=UNMET" "$OUT"
expect_contains "bare verdict: the waived row reads WAIVED" "name=row-waived|state=WAIVED" "$OUT"
expect_contains "bare verdict: the row whose claim is alive reads STILL-LIVE" \
  "name=row-live|state=STILL-LIVE" "$OUT"
expect_contains "bare verdict: the UNMET line still names what is missing" \
  "missing=$RVB/never.md" "$OUT"
expect_contains "bare verdict: the waived line quotes the waiver" "exploratory probe" "$OUT"
expect_contains "bare verdict: a human summary follows the machine lines" \
  "1 MET, 1 UNMET, 1 WAIVED, 1 STILL-LIVE" "$OUT"
# It reports state facts. Same doctrine as every other surface of this script.
for word in "kill" "you should" "recommend" "hung" "is dead" "safe to stop"; do
  expect_absent "verdict does not judge (\"$word\")" "$word" "$OUT"
done

# --- scoping: a name takes one row and answers for that row alone ---
sweep "$RVB" verdict row-met
expect_eq "verdict <name>: exactly one machine line" "1" \
  "$(printf '%s\n' "$OUT" | grep -c '^landing-verdict/v1|')"
expect_eq "verdict <name>: a MET row exits 0 even while a sibling row is UNMET" "0" "$RC"
expect_contains "verdict <name>: the line is the row that was asked for" "name=row-met" "$OUT"
expect_absent "verdict <name>: the sibling rows are not answered for" "row-unmet" "$OUT"
sweep "$RVB" verdict row-unmet
expect_eq "verdict <name>: an UNMET row exits 1" "1" "$RC"
expect_contains "verdict <name>: …and names its conjunct" "missing=$RVB/never.md" "$OUT"
kill -9 "$CLAIM9PID" 2>/dev/null; wait "$CLAIM9PID" 2>/dev/null
sweep "$RVB" verdict row-live
expect_eq "the same row once its claimed process is gone: UNMET" "1" "$RC"
expect_contains "…and the conjunct is named" "missing=$RVB/never3.md" "$OUT"

# --- still-live by progress: a progress artifact inside its declared cadence ---
RVL="$(make_repo vl)"; new_roster "$RVL"
PROG9="$RVL/w-progress.md"; echo "still working" > "$PROG9"
add_row "$RVL" name=writer progress="$PROG9" cadence="every ~5 minutes" duration="4 hours" \
        deliverable="$RVL/pending.md" launched_at="$(iso_ago 600)"
sweep "$RVL" verdict writer
expect_eq "fresh progress: an undelivered row is STILL-LIVE, not UNMET (exit 0)" "0" "$RC"
expect_contains "fresh progress: the state says so" "state=STILL-LIVE" "$OUT"
expect_contains "fresh progress: the outstanding deliverable is still named" \
  "missing=$RVL/pending.md" "$OUT"
backdate "$PROG9" 1800   # 30 min since the last write, against a 5-minute promise
sweep "$RVL" verdict writer
expect_eq "stale progress: the same row is UNMET once the promise lapses" "1" "$RC"
expect_contains "stale progress: the state says so" "state=UNMET" "$OUT"

# --- the roster is append-only: the LATEST row for a name is the answer ---
RVS="$(make_repo vs)"; new_roster "$RVS"
echo "landed" > "$RVS/final.md"
add_row "$RVS" name=chained status=intended  deliverable="$RVS/never.md" duration="4 hours" \
        launched_at="$(iso_ago 600)"
add_row "$RVS" name=chained status=confirmed deliverable="$RVS/final.md" duration="4 hours" \
        launched_at="$(iso_ago 600)"
sweep "$RVS" verdict
expect_eq "a three-state chain is ONE contract: one line per name" "1" \
  "$(printf '%s\n' "$OUT" | grep -c '^landing-verdict/v1|')"
expect_eq "…and the latest row is the one answered for" "0" "$RC"
expect_contains "…which is the row that landed" "state=MET" "$OUT"

# --- rows belonging to another session are not this session's contracts ---
RVF="$(make_repo vf)"; new_roster "$RVF"
add_row "$RVF" name=foreign session="$SID_FOREIGN" deliverable="$RVF/never.md" \
        duration="4 hours" launched_at="$(iso_ago 600)"
sweep "$RVF" verdict
expect_eq "a foreign session's broken row is not this session's UNMET" "0" "$RC"
expect_absent "…and is not answered for at all" "landing-verdict/v1|" "$OUT"

# --- surface: usage, an unknown name, an empty roster ---
sweep "$RVB" verdict row-met row-unmet
expect_eq "verdict takes at most one name (exit 2)" "2" "$RC"
expect_contains "…and the usage says so" "verdict" "$OUT"
sweep "$RVB" verdict no-such-agent
expect_eq "a name on no roster row is not an UNMET contract (exit 0)" "0" "$RC"
expect_absent "…and no verdict line is invented for it" "landing-verdict/v1|" "$OUT"
expect_contains "…while the answer still names what was asked" "no-such-agent" "$OUT"
RVE="$(make_repo ve)"
sweep "$RVE" verdict
expect_eq "a session with no roster at all exits 0" "0" "$RC"
expect_absent "…with no verdict lines" "landing-verdict/v1|" "$OUT"
sweep "$RVE" nonsense-verb
expect_contains "usage lists the verdict verb alongside the others" "verdict [<name>]" "$OUT"

# --- verdict is READ-ONLY: it journals nothing and acks nothing ---
RVR="$(make_repo vr)"; new_roster "$RVR"
add_row "$RVR" name=readonly deliverable="$RVR/never.md" duration="4 hours" launched_at="$(iso_ago 600)"
sweep "$RVR" verdict
expect_eq "the read-only run saw its UNMET row" "1" "$RC"
expect_false "verdict writes no ledger" test -e "$(ledger_of "$RVR")"
expect_eq "verdict does not touch the roster" "1" \
  "$(grep -c '^roster-state/v1|' "$(roster_of "$RVR")")"
# The state directory holds the roster it was handed and NOTHING this verb put there —
# asserted over the whole directory rather than against a list of filenames, so a state
# file nobody thought to name is caught too.
expect_eq "verdict leaves no other state file behind" "roster-$SID.state" \
  "$(ls -1 "$(state_dir_of "$RVR")" 2>/dev/null | tr '\n' ' ' | sed -e 's/ *$//')"

# --- an acked row is still judged: an ack closes the orchestrator's watch on a row, and
#     never the contract itself ---
sweep "$RVR" ack readonly
expect_eq "the ack is recorded" "0" "$RC"
sweep "$RVR" verdict readonly
expect_eq "an acked row whose artifact is absent is still UNMET" "1" "$RC"
expect_contains "…and still names the missing artifact" "missing=$RVR/never.md" "$OUT"

# --- a symlinked roster is refused, never guessed at (§8 path safety) ---
RVY="$(make_repo vy)"; new_roster "$RVY"
mv "$(roster_of "$RVY")" "$RVY/real-roster.state"
ln -s "$RVY/real-roster.state" "$(roster_of "$RVY")"
sweep "$RVY" verdict
expect_eq "a symlinked roster refuses (exit 2), it does not report a clean session" "2" "$RC"
expect_contains "…and says why" "symbolic link" "$OUT"

# ============================================================
section "Section 6: ack — the UNMET warning (epic-16 w1 slice 3)"
# ============================================================
#
# Ack does NOT reach the verdict: an acked row is re-stat'd like any
# other. What changes here is only the WARNING — acking a row that has not landed still
# records the ack (the orchestrator still verified the agent finished), but says so, and
# journals the verdict it
# overrode so the ledger carries the fact rather than losing it.

# --- ack over an UNMET row: warns, and the ledger line carries the verdict ---
R16="$(make_repo s16)"; new_roster "$R16"
add_row "$R16" name=unmet-agent deliverable="$R16/absent.md" duration="4 hours" \
        launched_at="$(iso_ago 600)"
sweep "$R16" ack unmet-agent
expect_eq "ack over an UNMET row still exits 0 (it still records)" "0" "$RC"
expect_contains "…and prints the UNMET warning" "WARNING: acking UNMET contract" "$OUT"
expect_contains "…naming the failing conjunct" "missing=$R16/absent.md" "$OUT"
ACKLINE16="$(grep 'event=ack' "$(ledger_of "$R16")" 2>/dev/null | head -1)"
expect_contains "the ledger line carries verdict=UNMET" "verdict=UNMET" "$ACKLINE16"
expect_contains "…and the failing-conjunct detail" "detail=missing=$R16/absent.md" "$ACKLINE16"

# --- ack over a MET row: no warning, journaled exactly as today ---
R17="$(make_repo s17)"; new_roster "$R17"
DEL17="$R17/report.md"; echo "landed" > "$DEL17"
add_row "$R17" name=met-agent deliverable="$DEL17" duration="4 hours" launched_at="$(iso_ago 600)"
sweep "$R17" ack met-agent
expect_eq "ack over a MET row exits 0" "0" "$RC"
expect_absent "…and prints no warning" "WARNING" "$OUT"
ACKLINE17="$(grep 'event=ack' "$(ledger_of "$R17")" 2>/dev/null | head -1)"
expect_absent "the ledger line carries no verdict field" "verdict=" "$ACKLINE17"

section "Section 7: the wave-01 Step-6 review remediations (C-2, C-3, C-6, S-1, S-3, perf)"
# ============================================================
#
# Six independent holes the Step-6 correctness/security and architecture/performance
# reviews found in the verdict machinery, each with the repro that found it. They share a
# section because they share a subject — what the verdict says when the INPUT is ordinary,
# rather than when the code is wrong — and because five of the six are answered inside
# `landing_conjunct` / `verdict_row` / `latest_rows`.

# --- S-3: one direction for symlinks, held by BOTH branches of the predicate ---
#
# The file branch followed links ([ -e ], [ -s ], stat all resolve) and the directory
# branch did not (`find -type f` skips them), so `ln -s` satisfied a file contract with
# zero bytes written while the same link inside a directory contract satisfied nothing.
# The direction taken: a symbolic link is not a delivered artifact, on either branch.
RS3="$(make_repo s3link)"; new_roster "$RS3"
echo "an artifact that lives somewhere else entirely" > "$RS3/real-target.md"
ln -s "$RS3/real-target.md" "$RS3/linked.md"
add_row "$RS3" name=symfile deliverable="$RS3/linked.md" duration="4 hours" \
        launched_at="$(iso_ago 600)"
sweep "$RS3" verdict symfile
expect_eq "a symlinked deliverable is NOT delivered (exit 1)" "1" "$RC"
expect_contains "…and the failing conjunct names it as a link" "symlink=$RS3/linked.md" "$OUT"
expect_absent "…never as delivered" "delivered=$RS3/linked.md" "$OUT"
rm -f "$RS3/linked.md"; echo "written for real this time" > "$RS3/linked.md"
sweep "$RS3" verdict symfile
expect_eq "paired positive: a real file at the same path is MET (exit 0)" "0" "$RC"
expect_contains "paired positive: …and reads as delivered" "delivered=$RS3/linked.md" "$OUT"

mkdir -p "$RS3/realdir"; echo "landed" > "$RS3/realdir/report.md"
ln -s "$RS3/realdir" "$RS3/linkdir"
add_row "$RS3" name=symdir deliverable="$RS3/linkdir" duration="4 hours" \
        launched_at="$(iso_ago 600)"
sweep "$RS3" verdict symdir
expect_eq "a symlinked DIRECTORY deliverable is refused the same way (exit 1)" "1" "$RC"
expect_contains "…by the same conjunct, so the two branches agree" \
  "symlink=$RS3/linkdir" "$OUT"

mkdir -p "$RS3/onlylink"; ln -s "$RS3/real-target.md" "$RS3/onlylink/x.md"
add_row "$RS3" name=dironlylink deliverable="$RS3/onlylink" duration="4 hours" \
        launched_at="$(iso_ago 600)"
sweep "$RS3" verdict dironlylink
expect_eq "a directory holding nothing but a symlink is empty, not delivered" "1" "$RC"
expect_contains "…named as empty" "empty=$RS3/onlylink" "$OUT"

# --- C-3(b): the directory branch is BOUNDED, on a path the roster chose ---
#
# The branch walked `find <path> -type f` TWICE with no depth or effort bound, then stat'd
# every file it found: 86 s inside a SubagentStop hook from one roster row naming
# /usr/share. One traversal now, capped; and when the cap truncates the walk the staleness
# conjunct is DROPPED rather than judged from a partial answer — "named, never guessed",
# the same degradation rule an unreadable launched_at follows.
RC3="$(make_repo c3dir)"; new_roster "$RC3"
BIGDIR="$RC3/bigdir"; mkdir -p "$BIGDIR"
_i=1; while [ "$_i" -le 210 ]; do printf 'x\n' > "$BIGDIR/f$_i.md"; _i=$((_i + 1)); done
_old_ts="$(date -v-7200S +%Y%m%d%H%M.%S 2>/dev/null || date -d '-7200 seconds' +%Y%m%d%H%M.%S)"
find "$BIGDIR" -type f -exec touch -t "$_old_ts" {} +
add_row "$RC3" name=bigrow deliverable="$BIGDIR" duration="4 hours" launched_at="$(iso_ago 600)"
sweep "$RC3" verdict bigrow
expect_eq "a directory bigger than the scan cap is delivered, not judged for staleness" "0" "$RC"
expect_contains "…and the detail names the cap rather than implying a full walk" \
  "scan capped" "$OUT"
# The paired control: under the cap, the same backdated files ARE judged, and go stale.
SMALLDIR="$RC3/smalldir"; mkdir -p "$SMALLDIR"
printf 'x\n' > "$SMALLDIR/one.md"
find "$SMALLDIR" -type f -exec touch -t "$_old_ts" {} +
add_row "$RC3" name=smallrow deliverable="$SMALLDIR" duration="4 hours" launched_at="$(iso_ago 600)"
sweep "$RC3" verdict smallrow
expect_eq "paired control: a directory under the cap is still judged for staleness" "1" "$RC"
expect_contains "…and reads stale" "stale=$SMALLDIR" "$OUT"

# --- C-2: one name, two contracts — the verdict says so and judges neither ---
#
# The gate joins by name and `latest_rows` folds to the latest row per name, so a re-used
# agent name made the EARLIER agent answerable for the LATER one's artifact: agent #1 landed
# its own contract in full and was refused, told to write a file that was never its job.
# There is no id the gate can use instead, so the answer is to say the name is ambiguous and
# hold nobody to it — a stop let through beats the wrong agent blocked.
RA="$(make_repo amb)"; new_roster "$RA"
echo "the first agent's landed report" > "$RA/first.md"
add_row "$RA" name=dup deliverable="$RA/first.md"  tool_use_id=toolu_01FIRST  \
        duration="4 hours" launched_at="$(iso_ago 900)"
add_row "$RA" name=dup deliverable="$RA/second.md" tool_use_id=toolu_01SECOND \
        duration="4 hours" launched_at="$(iso_ago 600)"
sweep "$RA" verdict dup
expect_contains "two dispatches under one name read AMBIGUOUS" "name=dup|state=AMBIGUOUS" "$OUT"
expect_eq "…and an ambiguous name is not an UNMET run (exit 0 — the gate's pass)" "0" "$RC"
expect_contains "…the detail says how many contracts share the name" "2 contracts" "$OUT"
expect_absent "…and no agent is told to write the other's artifact" \
  "missing=$RA/second.md" "$OUT"

# The paired control, and the reason the count is over DISPATCHES and not over rows: a
# three-state chain is ONE contract advancing, and it must not read as three.
RA2="$(make_repo amb2)"; new_roster "$RA2"
echo "landed" > "$RA2/final.md"
for _st in intended confirmed identified; do
  add_row "$RA2" name=chain status="$_st" deliverable="$RA2/final.md" \
          tool_use_id=toolu_01CHAIN duration="4 hours" launched_at="$(iso_ago 600)"
done
sweep "$RA2" verdict chain
expect_eq "paired control: a three-state chain is one contract, answered normally" "0" "$RC"
expect_contains "…as MET, never AMBIGUOUS" "name=chain|state=MET" "$OUT"
sweep "$RA" verdict
expect_contains "the bare readback counts ambiguous names in its summary" "AMBIGUOUS" "$OUT"

# --- S-1 (precedence half): a waiver does not silence a DECLARED deliverable ---
#
# `WAIVED` was verdict_row's first unconditional branch, so one line of quoted prose in a
# brief — the wall's own help text, which this repo's briefs quote constantly — silenced a
# contract that also named an artifact. A row carrying both is contradictory, and the
# contradiction is surfaced rather than resolved in the direction that checks nothing.
RW="$(make_repo waiv)"; new_roster "$RW"
add_row "$RW" name=truly-waived duration="4 hours" launched_at="$(iso_ago 600)" \
        waiver="this dispatch produces nothing durable"
sweep "$RW" verdict truly-waived
expect_eq "a waiver over a row declaring NO artifact is still WAIVED (exit 0)" "0" "$RC"
expect_contains "…and says so" "state=WAIVED" "$OUT"

add_row "$RW" name=contradiction deliverable="$RW/never.md" source=declared \
        duration="4 hours" launched_at="$(iso_ago 600)" \
        waiver="<why this dispatch produces nothing durable>"
sweep "$RW" verdict contradiction
expect_eq "a waiver over a DECLARED deliverable does not silence the contract (exit 1)" "1" "$RC"
expect_contains "…the state is the disk's answer" "state=UNMET" "$OUT"
expect_contains "…which still names the artifact" "missing=$RW/never.md" "$OUT"
expect_contains "…and the detail surfaces the contradiction rather than hiding it" \
  "waiver disregarded" "$OUT"

add_row "$RW" name=inferred-waived deliverable="$RW/never2.md" source=inferred \
        duration="4 hours" launched_at="$(iso_ago 600)" \
        waiver="a scouting pass: nothing durable comes out of it"
sweep "$RW" verdict inferred-waived
expect_eq "an explicit waiver still outranks an INFERRED path (exit 0)" "0" "$RC"
expect_contains "…as WAIVED, because only the waiver was declared" "state=WAIVED" "$OUT"

# --- C-6: the ack delta-count counts the CALLER'S OWN line ---
#
# The guard asked "did the count of this event rise", which a CONCURRENT caller's append
# satisfies just as well as our own — so a failed write could be journalled as a success by
# somebody else's line. The race itself is not deterministically reproducible in a suite
# (the window is between two adjacent statements), so the scoping is pinned at the source
# and the ordinary path is driven for regression beside it. The arm half of this pin retired
# with the `arm` verb; ack is the only journalling verb left.
SWEEPER_SRC="$(cat "$SWEEPER")"
expect_matches "ack's delta-count is scoped to the acking pid, not to any ack line" \
  'ledger_count .\|event=ack\|\.\*\|pid=\$\$\|.' "$SWEEPER_SRC"

# …and the scoped count still answers correctly with a FOREIGN entry already in the ledger,
# which is the shape that made the unscoped count wrong.
R20="$(make_repo s20)"; new_roster "$R20"
L20="$(ledger_of "$R20")"
printf '# bionic session sweeper ledger — schema sweeper-ledger/v1 — machine-local, safe to delete\n' > "$L20"
printf 'sweeper-ledger/v1|event=ack|at=%s|epoch=1|pid=999999|session=%s|name=somebody-elses-row\n' \
  "$(iso_ago 600)" "$SID" >> "$L20"
sweep "$R20" ack mine
expect_eq "ack succeeds over a ledger already holding another pid's ack entry" "0" "$RC"
expect_contains "…journalling its own line under its own pid" "name=mine" \
  "$(grep "pid=$$" "$L20" 2>/dev/null || grep 'name=mine' "$L20")"
expect_contains "…and counting both rows as closed" "2 row(s) acked" "$OUT"

# --- the perf half of the review: the fold's name is used, not re-derived per row ---
#
# `latest_rows` folded the roster in awk (0.029 s at 1000 rows) and then a shell loop called
# `line_field` on every folded row to recover the name the fold had already parsed — five
# processes per row, 9.665 s at 1000 rows, on the path the landing gate runs at EVERY
# subagent stop. The bound below is ~40x the fixed cost and ~4x under the measured broken
# one, so it discriminates without being a stopwatch.
RP="$(make_repo perf)"; new_roster "$RP"
awk -v sid="$SID" -v n=2000 -v la="$(iso_ago 600)" '
  BEGIN {
    for (i = 1; i <= n; i++)
      printf "roster-state/v1|status=confirmed|session=%s|name=perf%04d|agent_id=a%04d|launched_at=%s|subagent_type=implementor|model=opus|deliverable=|source=declared|duration=4 hours|progress=|claims=|cadence=|absent=|waiver=|tool_use_id=toolu_%04d\n", sid, i, i, la, i
  }' >> "$(roster_of "$RP")"
SWEEP_BOUND=30
_t0=$(date -u +%s)
sweep "$RP" verdict perf1999
_t1=$(date -u +%s)
SWEEP_BOUND=20
expect_eq "a scoped verdict over a 2000-row roster answers (exit 0)" "0" "$RC"
expect_contains "…for the row it was asked about" "name=perf1999|state=MET" "$OUT"
expect_true "…within the stop path's budget (10 s at 2000 rows)" test "$(( _t1 - _t0 ))" -le 10

# ============================================================
printf '\n──────────────────────────────────────────────\n'
printf 'session-sweeper: %d passed, %d failed, %d total\n' "$PASS" "$FAIL" "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
