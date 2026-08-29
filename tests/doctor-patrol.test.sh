#!/bin/bash
# tests/doctor-patrol.test.sh — doctor.sh's PATROL section (F3, epic-19 wave-01,
# spec AC-F3; design ledger .bionic/docs/record/epic-19/step2-design-ledger.md
# ratification round 2).
#
# THE CONTRACT UNDER TEST. Doctor's Patrol section shows running Patrols or
# nothing: one line per live Patrol — `✓ session <short> · <n> open
# dispatches` — and `– none running` when there is none. Gone from the default
# output: the "reconstructed from the transcript" narrative header, per-job
# cron/prompt detail lines, the stamp's firing/not-firing state and interval
# provenance, and the dispatch-wall tally. The one survivor is the
# duplicate-Patrol fix line (`CronDelete <id>`) — ratified to stay because it
# costs nothing in the healthy, single-Patrol case.
#
# EXECUTED, NOT SOURCED — doctor.sh's own header states this is the only
# supported mode ("Executed, never sourced"), so this suite drives the real
# script exactly the way a user's shell would, through the one seam
# lib/patrol.sh already offers every caller: BIONIC_CLAUDE_HOME. A fixture
# claude-home carries a `sessions/<id>.json` naming a REAL live process (a
# spawned `sleep`, so `kill -0` succeeds the way it would for an actual CLI)
# and that session's own transcript, where a `CronCreate`/`CronDelete` pair is
# a recorded tool_use like any other (lib/patrol.sh:22-29). A fixture repo
# supplies the roster file patrol_roster_state reads directly off disk — no
# session-poker, no cron table, nothing that needs a live CLI.
#
# NO doctor.test.sh EXISTED BEFORE THIS SUITE. The broad one (epic-17 W3 S7)
# fingerprinted a whole fixture machine and was deleted at 8582861 (epic-18
# wave-03, the reliability ruling) with nothing replacing it — this suite
# covers only the Patrol section, scoped the way tests/rc-item.test.sh scopes
# to one setup-managed item rather than re-fingerprinting the world.
#
# ASSERTION-HELPER RACE. No `printf | grep -q` anywhere below
# (tests/assert-helper-race.test.sh): containment is bash `[[ == * ]]`
# in-process, and the one `awk` extraction below reads to EOF rather than
# closing early.
#
# Usage: bash tests/doctor-patrol.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PAYLOAD="${REPO}/payload"
DOCTOR_SH="${PAYLOAD}/scripts/doctor.sh"

command -v jq >/dev/null 2>&1 || { echo "doctor-patrol.test.sh: jq is required"; exit 1; }

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

expect_true()  { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
expect_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then ok "$label"; else no "$label" "no match for '$pattern' in: $(printf '%.400s' "$actual")"; fi
}
expect_no_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then no "$label" "unexpected match for '$pattern'"; else ok "$label"; fi
}

TMP="$(mktemp -d)"
LIVE_PIDS=""
cleanup() {
  for p in $LIVE_PIDS; do kill "$p" 2>/dev/null; done
  rm -rf "$TMP"
}
trap cleanup EXIT

expect_true "payload/scripts/doctor.sh exists" test -f "$DOCTOR_SH"

# ---------- fixture builders ----------

# A live process this machine's `kill -0` will actually find, the same way a
# real CLI session's pid does. SETS $LIVE_PID RATHER THAN PRINTING IT — a
# `$(...)` command substitution runs in its own subshell, and on this machine
# a background job started inside one dies the instant that subshell exits
# (measured: `sleep 100 &` inside `$(...)` was already gone by the caller's
# next line). Called plain, never captured.
spawn_live_pid() {
  sleep 100 &
  LIVE_PID=$!
  LIVE_PIDS="${LIVE_PIDS} ${LIVE_PID}"
}

# A claude-home with one live session named in sessions/<sid>.json.
make_claude_home() {  # <sid> <pid> <cwd> -> claude-home dir on stdout
  local sid="$1" pid="$2" cwd="$3" dir
  dir="$(mktemp -d -p "$TMP")"
  mkdir -p "$dir/sessions" "$dir/projects/-fixture-proj"
  jq -nc --arg sid "$sid" --argjson pid "$pid" --arg cwd "$cwd" \
    '{sessionId:$sid,pid:$pid,cwd:$cwd}' > "$dir/sessions/${sid}.json"
  : > "$dir/projects/-fixture-proj/${sid}.jsonl"
  printf '%s' "$dir"
}

# A claude-home with no live sessions at all — patrol_live_sessions() returns
# nothing without even a `sessions/` directory to look in.
make_empty_claude_home() {
  mktemp -d -p "$TMP"
}

transcript_of() {  # <claude-home> <sid>
  printf '%s/projects/-fixture-proj/%s.jsonl' "$1" "$2"
}

# One CronCreate + its joined tool_result, the shape lib/patrol.sh's join
# reads: the job id comes back in the result's prose ("Scheduled recurring job
# <id> (...)"), never in the request.
plant_patrol_job() {  # <transcript> <tool_use_id> <job-id>
  local t="$1" tid="$2" jobid="$3"
  jq -nc --arg id "$tid" \
    '{type:"assistant",isSidechain:false,
      message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"CronCreate",
        input:{cron:"*/30 * * * *",recurring:true,
               prompt:"Patrol tick for the fixture (bionic). Run: bash /abs/hooks/session-poker.sh tick — then continue."}}]}}' \
    >> "$t"
  jq -nc --arg id "$tid" --arg c "Scheduled recurring job ${jobid} (*/30 * * * *) — Patrol tick" \
    '{type:"user",isSidechain:false,
      message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:$c}]}}' \
    >> "$t"
}

# The roster file patrol_roster_state() reads straight off disk — no session-
# poker, no live process, just the append-only shape the wall itself writes.
make_repo_with_roster() {  # <sid> <open-names...> -- <closed-names...> -> repo dir on stdout
  local sid="$1" dir nm; shift
  dir="$(mktemp -d -p "$TMP")"
  mkdir -p "$dir/.bionic/tmp"
  local f="$dir/.bionic/tmp/roster-${sid}.state"
  local mode=open
  for nm in "$@"; do
    if [ "$nm" = "--" ]; then mode=closed; continue; fi
    printf 'roster-state/v1|status=intended|name=%s|ts=2026-08-27T00:00:00Z\n' "$nm" >> "$f"
    [ "$mode" = "closed" ] && printf 'landing-swept/v1|name=%s|ts=2026-08-27T00:00:01Z\n' "$nm" >> "$f"
  done
  printf '%s' "$dir"
}

# THE STAMP hooks/session-poker.sh touches on every tick, and the ONE fact that
# separates an armed Patrol from a dead one. `patrol_stamp_state` reads only its
# mtime against 2x the poker interval (30m default → a 3600s limit), so a file
# written now is `firing` and one backdated past that is `not-firing`. Absent is
# a third answer, `never-armed`, and it needs no builder — it is what every
# fixture here had before this existed.
plant_patrol_stamp() {  # <repo> <sid> [<backdate-hours>]
  local repo="$1" sid="$2" hours="${3:-}" f="$1/.bionic/tmp/patrol-$2.state"
  mkdir -p "$repo/.bionic/tmp"
  printf 'patrol-stamp/v1|verb=arm|ts=fixture\n' > "$f"
  [ -n "$hours" ] && touch -t "$(date -v-"${hours}"H +%Y%m%d%H%M.%S)" "$f"
  return 0
}

# A repo whose session never wrote a roster at all — the state this suite's
# Sections 7 and 9 are about, and the one lib/patrol.sh reports as
# `present=no|rows=0|open=0`. `make_repo_with_roster` called with no names
# produces the same tree, which is exactly how Section 3 acquired it by
# accident; this builder says out loud what that fixture is.
make_repo_without_roster() {  # -> repo dir on stdout
  local dir
  dir="$(mktemp -d -p "$TMP")"
  mkdir -p "$dir/.bionic/tmp"
  printf '%s' "$dir"
}

# ONE LAUNCH, AS THE TRANSCRIPT RECORDS IT: the `Agent` tool_use lib/patrol.sh's
# scan counts (`_patrol_scan_jq`, the `A` record) plus the ordinary tool_result
# it joins to.
#
# THE RESULT IS BENIGN ON PURPOSE. A refusal is credited only when a tool_result
# carrying `PreToolUse:Agent hook error:` joins BY tool_use_id to an `Agent`
# tool_use (`_patrol_join_awk`) — the join, not the marker, is the rule — so
# these launches land in `dispatched=` and none of them in `refused=`, and the
# `blind=` arithmetic under test is `agents - rostered - 0`.
#
# `isSidechain:false` and no `agent_id` key anywhere in the entry: both are what
# the scan's two main-thread filters test, and a fixture that failed either would
# be counted as somebody else's turn and vanish from the tally.
plant_agent_dispatch() {  # <transcript> <tool_use_id>
  local t="$1" tid="$2"
  jq -nc --arg id "$tid" \
    '{type:"assistant",isSidechain:false,
      message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"Agent",
        input:{description:"fixture slice",subagent_type:"general-purpose",
               prompt:"Do the fixture work and report back."}}]}}' \
    >> "$t"
  jq -nc --arg id "$tid" \
    '{type:"user",isSidechain:false,
      message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,
        content:"The agent finished and reported back."}]}}' \
    >> "$t"
}

# ---------- driving doctor ----------

run_doctor() {  # <claude-home>
  BIONIC_CLAUDE_HOME="$1" BIONIC_PLUGIN_ROOT="$PAYLOAD" BIONIC_DOCTOR_PROBE_SECONDS=3 \
    bash "$DOCTOR_SH" < /dev/null 2>&1
}

# The PATROL section alone — from its bare header to end of output, which is
# where the default (no --updates) run ends.
patrol_block() {  # <full-output>
  printf '%s\n' "$1" | awk '/^PATROL$/{f=1} f'
}

echo "=== Section 1: no live Patrol anywhere ==="

EMPTY_HOME="$(make_empty_claude_home)"
OUT1="$(run_doctor "$EMPTY_HOME")"
PB1="$(patrol_block "$OUT1")"

expect_match    "1: the fallback line prints" "*none running*" "$PB1"
expect_no_match "2: no session line prints alongside the fallback" "*session*" "$PB1"

echo ""
echo "=== Section 2: one live Patrol, one open dispatch (singular) ==="

SID2="cccccccc-1111-2222-3333-444455556666"
SHORT2="${SID2%%-*}"
spawn_live_pid; PID2="$LIVE_PID"
# THE SESSION'S cwd MUST BE THE FIXTURE REPO, not a decorative path — it is
# what patrol_roster_state() resolves the roster file's location from
# (lib/patrol.sh:369, _patrol_repo_root on the session's own cwd).
REPO2="$(make_repo_with_roster "$SID2" beta -- alpha)"
HOME2="$(make_claude_home "$SID2" "$PID2" "$REPO2")"
TR2="$(transcript_of "$HOME2" "$SID2")"
plant_patrol_job "$TR2" "toolu_1" "abc12345"
# A FRESH STAMP, because a transcript-visible job is not a running Patrol. The
# row is gated on this file's age (doctor.sh, `_patrol_flush`); Sections 4 and 5
# below are the same fixture with the stamp stale and with it absent.
plant_patrol_stamp "$REPO2" "$SID2"

OUT2="$(run_doctor "$HOME2")"
PB2="$(patrol_block "$OUT2")"

expect_match "3: the running Patrol prints session · singular open dispatch" \
  "*✓ session ${SHORT2} · 1 open dispatch*" "$PB2"
expect_no_match "4: 'dispatches' (plural) does not also appear on that line" \
  "*1 open dispatches*" "$PB2"

# The five deleted detail classes, checked as absences BESIDE the positive
# assertions above on the SAME fixture and the SAME extractor
# (memory/no-vacuous-tests-at-authoring) — this is not an empty-fixture
# vacuous negative, it is a section proven non-empty (3/4 above) that must not
# also carry the retired detail.
expect_no_match "5: the reconstruction narrative header is gone" \
  "*reconstructed from the transcript*" "$PB2"
expect_no_match "6: the per-job 'patrol jobs' row is gone" "*patrol jobs*" "$PB2"
expect_no_match "7: the job id/cron/prompt detail line is gone" "*abc12345*" "$PB2"
expect_no_match "8: the 'patrol stamp' row is gone" "*patrol stamp*" "$PB2"
expect_no_match "9: the interval-provenance detail is gone" "*came from the poker*" "$PB2"
expect_no_match "10: the 'dispatch wall' row is gone" "*dispatch wall*" "$PB2"
expect_no_match "11: the this-repo cwd detail is gone" "*this repo*" "$PB2"

echo ""
echo "=== Section 3: duplicate Patrols — the one survivor ==="

SID3="dddddddd-1111-2222-3333-444455556666"
SHORT3="${SID3%%-*}"
spawn_live_pid; PID3="$LIVE_PID"
REPO3="$(make_repo_with_roster "$SID3" -- alpha)"  # a roster, one closed row — open=0
# THE ROSTER IS PRESENT AND EMPTY OF OPEN WORK, which is not the same fixture as
# a session that never wrote one. This section owns the duplicate-Patrol fix line
# and wants the ordinary `0 open dispatches` row underneath it; the no-roster case
# it used to be built on is Section 7's, where it is asserted rather than incidental.
HOME3="$(make_claude_home "$SID3" "$PID3" "$REPO3")"
TR3="$(transcript_of "$HOME3" "$SID3")"
plant_patrol_job "$TR3" "toolu_1" "old11111"
plant_patrol_job "$TR3" "toolu_2" "new22222"
plant_patrol_stamp "$REPO3" "$SID3"

OUT3="$(run_doctor "$HOME3")"
PB3="$(patrol_block "$OUT3")"

expect_match "12: the running Patrol still prints, 0 open dispatches (plural)" \
  "*✓ session ${SHORT3} · 0 open dispatches*" "$PB3"
expect_match "13: the duplicate fix line names the OLDER job for deletion" \
  "*session ${SHORT3} has 2 Patrol jobs armed → CronDelete old11111*" "$OUT3"
expect_no_match "14: the fix line does NOT also name the newer (kept) job" \
  "*CronDelete*new22222*" "$OUT3"
expect_no_match "15: the Patrol block itself carries no per-job detail" \
  "*old11111*" "$PB3"

echo ""
echo "=== Section 4: the job is in the transcript and the Patrol is DEAD ==="

# WHAT THIS SECTION OWNS, and why nothing above it could see it. Jobs are
# reconstructed from the transcript — CronCreate minus CronDelete — and the four
# events that kill a Patrol (a plugin update, /reload-plugins, a continue, a
# /clear and resume) take the job out of the CLI's in-memory cron table with no
# tool call behind them. So the count stays positive on a machine where nothing
# is firing, and doctor printed `✓ session … · N open dispatches` for it: the
# Step-6 correctness FAIL against AC-F3. The fixture is Section 2's, with one
# thing changed — the stamp is three hours old, well past the 3600s limit.

SID4="dddddddd-1111-2222-3333-444455556666"
SHORT4="${SID4%%-*}"
spawn_live_pid; PID4="$LIVE_PID"
REPO4="$(make_repo_with_roster "$SID4" beta -- alpha)"
HOME4="$(make_claude_home "$SID4" "$PID4" "$REPO4")"
TR4="$(transcript_of "$HOME4" "$SID4")"
plant_patrol_job "$TR4" "toolu_1" "abc12345"
plant_patrol_stamp "$REPO4" "$SID4" 3

OUT4="$(run_doctor "$HOME4")"
PB4="$(patrol_block "$OUT4")"

expect_no_match "17: a dead Patrol prints no running line" "*✓ session ${SHORT4}*" "$PB4"
expect_no_match "18: and no session line of any kind" "*session ${SHORT4}*" "$PB4"
expect_match    "19: the section falls back to none running" "*none running*" "$PB4"
# NOT SILENCE. Running-or-nothing governs the SECTION; a Patrol that was armed
# and stopped ticking is the one state a person can act on, and the fix channel
# is where doctor says so.
expect_match    "20: the fix section names the session and what to do" \
  "*session ${SHORT4}: the Patrol is armed but not firing*" "$OUT4"
# The deleted detail stays deleted — the stamp is read, not rendered.
expect_no_match "21: the stamp state itself is still not printed" "*not-firing*" "$OUT4"
expect_no_match "22: nor its age or interval provenance" "*came from the poker*" "$OUT4"

echo ""
echo "=== Section 5: the job is in the transcript and there is no stamp ==="

# THE THIRD STATE, AND IT IS NOT A FAULT. An absent stamp means never armed —
# or deliberately ended, because the poker's `disarm` verb REMOVES this file
# (S10). Both are decisions, so this machine gets the same quiet page as one
# with no Patrol at all: no row, and no fix line either. This is the assertion
# that keeps Section 4's fix line from becoming noise on every stopped run.

SID5="eeeeeeee-1111-2222-3333-444455556666"
SHORT5="${SID5%%-*}"
spawn_live_pid; PID5="$LIVE_PID"
REPO5="$(make_repo_with_roster "$SID5" beta -- alpha)"
HOME5="$(make_claude_home "$SID5" "$PID5" "$REPO5")"
TR5="$(transcript_of "$HOME5" "$SID5")"
plant_patrol_job "$TR5" "toolu_1" "abc12345"

OUT5="$(run_doctor "$HOME5")"
PB5="$(patrol_block "$OUT5")"

expect_no_match "23: a never-armed session prints no running line" "*session ${SHORT5}*" "$PB5"
expect_match    "24: the section falls back to none running" "*none running*" "$PB5"
expect_no_match "25: and a deliberate stop earns no fix line" \
  "*session ${SHORT5}: the Patrol*" "$OUT5"

echo ""
echo "=== Section 6: registration ==="

# THE SUITE IS REGISTERED. tests/*.test.sh is NOT globbed by the runner — see
# tests/patrol-duties-gate.test.sh's own case 24 for the prior instance of this
# lesson (doctor.test.sh, deleted at 8582861, was never re-registered because
# nothing needed to be — this is that suite's live successor).
expect_true "26: tests/run.sh names doctor-patrol.test.sh" \
  grep -q 'run "doctor-patrol.test.sh" bash tests/doctor-patrol.test.sh' "${BIONIC_SCRIPTS_DIR}/tests/run.sh"

echo ""
echo "=== Section 7: a firing Patrol with NO roster file and launches in the transcript ==="

# THE DEFECT THIS SECTION OWNS (Chris, 2026-08-29, on the 1.3.0 plugin):
# `/bionic:doctor` printed `✓ session 61be8dc9 · 0 open dispatches` while two
# agents were running. The launch-time hook was never registered in that
# session — hooks do not survive a continue, a /clear+resume or a
# /reload-plugins — so no roster file was ever written, and doctor rendered the
# ABSENCE of the record as the NUMBER zero. Every Patrol tick on that machine
# was emitting `NOTIFY wall-blind` at the same moment. lib/patrol.sh had both
# facts the whole time (`patrol-roster/v1 … present=no`, `patrol-wall/v1 …
# blind=N`); the renderer parsed the first, read neither, and printed a count
# nobody dispatched.
#
# THE ROW KEEPS ITS ✓. The Patrol IS running — that is what the stamp says and
# what running-or-nothing (F3) reports. The roster is the thing that is missing,
# and that is what the text now says.

SID7="ffffffff-1111-2222-3333-444455556666"
SHORT7="${SID7%%-*}"
spawn_live_pid; PID7="$LIVE_PID"
REPO7="$(make_repo_without_roster)"
HOME7="$(make_claude_home "$SID7" "$PID7" "$REPO7")"
TR7="$(transcript_of "$HOME7" "$SID7")"
plant_patrol_job "$TR7" "toolu_1" "abc12345"
plant_agent_dispatch "$TR7" "toolu_a1"
plant_agent_dispatch "$TR7" "toolu_a2"
plant_agent_dispatch "$TR7" "toolu_a3"
plant_patrol_stamp "$REPO7" "$SID7"

OUT7="$(run_doctor "$HOME7")"
PB7="$(patrol_block "$OUT7")"

expect_match "27: an absent roster is rendered as absent, not as a count" \
  "*✓ session ${SHORT7} · roster absent — launches unrecorded*" "$PB7"
# THE ORIGINAL LIE, WALLED. Not "the number is right now" — the claim itself is
# withdrawn, because a session with no roster has no open-dispatch count to make.
expect_no_match "28: and the row makes no open-dispatch claim at all" \
  "*open dispatch*" "$PB7"
expect_match "29: the fix line names the unrostered launches and ends in the cure" \
  "*session ${SHORT7}: 3 launches unrostered → re-invoke /bionic:canonical-sdlc*" "$OUT7"

echo ""
echo "=== Section 8: a firing Patrol whose roster is PRESENT and incomplete ==="

# THE OTHER HALF, and what keeps Section 7's row honest: here the roster is
# real — one open dispatch, and the row still says exactly that — while the
# transcript carries three launches, so two of them never reached the wall. The
# roster is not absent, it is INCOMPLETE, and the count doctor prints stays the
# count it can stand behind. `blind = 3 launches - 1 rostered - 0 refused = 2`.

SID8="aaaaaaaa-9999-2222-3333-444455556666"
SHORT8="${SID8%%-*}"
spawn_live_pid; PID8="$LIVE_PID"
REPO8="$(make_repo_with_roster "$SID8" beta)"
HOME8="$(make_claude_home "$SID8" "$PID8" "$REPO8")"
TR8="$(transcript_of "$HOME8" "$SID8")"
plant_patrol_job "$TR8" "toolu_1" "abc12345"
plant_agent_dispatch "$TR8" "toolu_a1"
plant_agent_dispatch "$TR8" "toolu_a2"
plant_agent_dispatch "$TR8" "toolu_a3"
plant_patrol_stamp "$REPO8" "$SID8"

OUT8="$(run_doctor "$HOME8")"
PB8="$(patrol_block "$OUT8")"

expect_match "30: a present roster still prints its own open count, unchanged" \
  "*✓ session ${SHORT8} · 1 open dispatch*" "$PB8"
expect_no_match "31: and a present roster is never re-rendered as absent" \
  "*roster absent*" "$PB8"
expect_match "32: the fix line reports only the launches the roster never saw" \
  "*session ${SHORT8}: 2 launches unrostered → re-invoke /bionic:canonical-sdlc*" "$OUT8"

echo ""
echo "=== Section 9: one cure, two surfaces — and the column budget ==="

# ONE CURE, SPELLED ONCE. hooks/session-poker.sh decides `wall-blind` at tick
# time and names the repair; doctor names the same repair from the same fact
# hours later, off the same `patrol-wall/v1` record. Two spellings of one cure
# is two answers, so the literal is pinned from BOTH files rather than from
# either alone — the shape tests/cross-gate-agreement.test.sh uses wherever two
# readers have to agree.
CURE='re-invoke /bionic:canonical-sdlc'
POKER_TEXT="$(cat "${PAYLOAD}/hooks/session-poker.sh")"
DOCTOR_TEXT="$(cat "$DOCTOR_SH")"
expect_match "33: hooks/session-poker.sh spells the cure this way" "*${CURE}*" "$POKER_TEXT"
expect_match "34: payload/scripts/doctor.sh spells it identically" "*${CURE}*" "$DOCTOR_TEXT"

# THE BUDGET, MEASURED WITH THE PRODUCT'S OWN RULER rather than by eye
# (lib/width.sh — `bionic_cols` counts COLUMNS, and every glyph on these rows is
# three bytes and one column wide). Sections 7 and 8 print the only rows and fix
# lines in the product that this suite is the first to produce;
# tests/doctor-version.test.sh walls the rest of the page but never drives a live
# Patrol, so nothing else measures these.
#
# THE RULER OVER-COUNTS `→` AND THAT IS THE SAFE DIRECTION. The arrow is not in
# lib/width.sh's closed glyph set, so each one measures three columns instead of
# one and a fix line carrying two of them is scored four columns wide. The
# effect is a wall that is stricter than the terminal, never looser — which is
# what that file's own header says the omission costs.
# shellcheck source=/dev/null
. "${PAYLOAD}/scripts/lib/width.sh"

lines_matching() {  # <text> <glob> -> the matching lines
  local line out=""
  while IFS= read -r line || [ -n "$line" ]; do
    # shellcheck disable=SC2053  # RHS is a glob on purpose
    if [[ "$line" == $2 ]]; then out="${out}${line}"$'\n'; fi
  done <<< "$1"
  printf '%s' "$out"
}

first_over_budget() {  # <text> -> the first line wider than the budget, or empty
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    if [ "$(bionic_cols "$line")" -gt "$BIONIC_LINE_WIDTH" ]; then printf '%s' "$line"; return 0; fi
  done <<< "$1"
  return 0
}

# TWO CAPTURES, SEPARATED BY A REAL NEWLINE. `$(...)` strips the trailing one,
# so gluing the two captures together concatenated the two fix lines into a
# single 152-column string and the budget check below failed on a line that does
# not exist — caught by this suite's own first green run.
NEW_FIX="$(lines_matching "$OUT7" '*launches unrostered*')
$(lines_matching "$OUT8" '*launches unrostered*')"

# THE POSITIVE THE WALL IS WORTHLESS WITHOUT: both fix lines really were
# produced, so the width check below is measuring text and not an empty string.
expect_match "35: both new fix lines were extracted for measurement" \
  "*3 launches unrostered*2 launches unrostered*" "$(printf '%s' "$NEW_FIX" | tr '\n' ' ')"

WIDE="$(first_over_budget "${PB7}
${PB8}
${NEW_FIX}")"
if [ -z "$WIDE" ]; then
  ok "36: every new Patrol row and fix line fits the ${BIONIC_LINE_WIDTH}-column budget"
else
  no "36: every new Patrol row and fix line fits the ${BIONIC_LINE_WIDTH}-column budget" \
     "$(bionic_cols "$WIDE") columns: ${WIDE}"
fi

echo ""
echo "========================================"
echo "doctor-patrol: $PASS/$TOTAL passed"
echo "========================================"

[ "$FAIL" -eq 0 ] || exit 1
