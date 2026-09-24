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
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PAYLOAD="${REPO}/payload"
DOCTOR_SH="${PAYLOAD}/scripts/doctor.sh"

command -v jq >/dev/null 2>&1 || { echo "doctor-patrol.test.sh: jq is required"; exit 1; }

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
  # 3600, not 100: the fixture must outlive the SUITE, not a case — under load this suite
  # has taken 323 s (tests-floor3, 2026-09-07), and a fake session whose process has exited
  # before the case that reads it is honestly reported dead (doctor-patrol case 44). The
  # EXIT trap kills every one of these; nothing waits on them.
  sleep 3600 &
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
    # THE INVENTED `ts=` IS GONE (S17, on S14's F-S14-2). This fixture carried a field
    # no production writer has ever emitted and no reader in the fleet consumes — proven
    # by grep over payload/hooks and payload/scripts — for as long as nothing checked.
    # `roster_row` refuses the key outright, which is the point: a fixture cannot invent
    # a field the fleet has no reader for.
    roster_row_fixture status=intended session="$sid" name="$nm" >> "$f"
    # THE MARKER IN THE SHAPE ITS ONE ORIGINATOR WRITES IT, `state=` and all
    # (hooks/landing-gate.sh's `SWEPT_SCHEMA` printf). A closing marker says
    # `state=MET`; a marker that says anything else is a contract the sweep
    # judged UNMET, and since S17 those travel — `adopt_copy_marker` copies a
    # predecessor's verdict verbatim onto a successor's roster. A fixture that
    # wrote no `state=` at all could not tell the two apart, which is precisely
    # the distinction `patrol_roster_state` now makes.
    #
    # AND THE ACK THAT ACTUALLY CLOSES IT (epic-23 wave-20 T17, D10). A MET marker records that
    # a landing was seen, not that the agent left, so it closes nothing on its own any more:
    # `patrol_roster_state` asks `roster_open_names`, which closes a name only on a sweeper
    # ledger ack stamped after the row's `launched_at=` (the fixture writer's default,
    # 2026-09-02T00:00:00Z). The marker stays because it is what a landed row carries; the ack
    # is what a closed one carries.
    if [ "$mode" = "closed" ]; then
      swept_marker_write "$f" 2026-08-27T00:00:01Z "$sid" "$nm" a000 MET
      ack_write "$dir/.bionic/tmp/sweeper-${sid}.state" 2026-09-02T01:00:00Z "$sid" "$nm"
    fi
  done
  printf '%s' "$dir"
}

# THE SWEEPER LEDGER'S ACK LINE, in its writer's shape (hooks/session-sweeper.sh `ack`).
ack_write() {  # <ledger> <at> <sid> <name>
  [ -f "$1" ] || printf '# bionic session sweeper ledger — schema sweeper-ledger/v1 — machine-local, safe to delete\n' > "$1"
  printf 'sweeper-ledger/v1|event=ack|at=%s|epoch=0|pid=1|session=%s|name=%s|by=patrol|reason=landed\n' \
    "$2" "$3" "$4" >> "$1"
}

# THE STAMP hooks/session-poker.sh touches on every tick, and the ONE fact that
# separates an armed Patrol from a dead one. `patrol_stamp_state` reads only its
# mtime against 2x the poker interval (20m default → a 2400s limit), so a file
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

# ISO instants, and the two record shapes a gap is measured between — the same builders
# tests/patrol-revive.test.sh uses on the same predicate, so the two surfaces are driven by
# one fixture idiom rather than two.
dp_iso() {  # <seconds ago> -> ISO-8601 Z
  date -u -v-"$1"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "-$1 seconds" +%Y-%m-%dT%H:%M:%SZ
}
dp_assistant() {  # <transcript> <seconds ago>
  jq -nc --arg ts "$(dp_iso "$2")" \
    '{type:"assistant",isSidechain:false,timestamp:$ts,
      message:{role:"assistant",content:[{type:"text",text:"working"}]}}' >> "$1"
}
dp_user() {  # <transcript> <seconds ago> <text>
  jq -nc --arg ts "$(dp_iso "$2")" --arg t "$3" \
    '{type:"user",isSidechain:false,timestamp:$ts,
      message:{role:"user",content:[{type:"text",text:$t}]}}' >> "$1"
}
# A stamp aged in SECONDS. `plant_patrol_stamp` takes whole hours, which cannot express the
# field's own number (2459s against a 1320s window).
dp_backdate() {  # <file> <seconds ago>
  local ts
  ts="$(date -v-"$2"S +%Y%m%d%H%M.%S 2>/dev/null || date -d "-$2 seconds" +%Y%m%d%H%M.%S)"
  touch -t "$ts" "$1"
}
# `plant_patrol_job` with its two records DATED. The job join reads `C` records whatever
# their date (the roster window gates only the `A`/`R` records it counts), but the verdict
# scan dates every record it sees and one it cannot date poisons the whole answer — so a
# fixture that wants a verdict has to date the job too.
plant_patrol_job_dated() {  # <transcript> <tool_use_id> <job-id> <seconds ago>
  local t="$1" tid="$2" jobid="$3" ts; ts="$(dp_iso "$4")"
  jq -nc --arg id "$tid" --arg ts "$ts" \
    '{type:"assistant",isSidechain:false,timestamp:$ts,
      message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"CronCreate",
        input:{cron:"*/20 * * * *",recurring:true,
               prompt:"Patrol tick for the fixture (bionic). Run: bash /abs/hooks/session-poker.sh tick — then continue."}}]}}' \
    >> "$t"
  jq -nc --arg id "$tid" --arg ts "$ts" --arg c "Scheduled recurring job ${jobid} (*/20 * * * *) — Patrol tick" \
    '{type:"user",isSidechain:false,timestamp:$ts,
      message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:$c}]}}' \
    >> "$t"
}
# THE INTERVAL IS PINNED IN THE FIXTURE, not inherited from the poker's built-in default:
# this section's numbers (2459s and 1500s against a 1320s window) only mean what they say at
# a 1200s interval.
dp_pin_interval() {  # <repo>
  printf 'poker-interval: 20m\n' > "$1/.bionic/config.yaml"
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
        input:{description:"fixture task",subagent_type:"general-purpose",
               prompt:"Do the fixture work and report back."}}]}}' \
    >> "$t"
  jq -nc --arg id "$tid" \
    '{type:"user",isSidechain:false,
      message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,
        content:"The agent finished and reported back."}]}}' \
    >> "$t"
}

# ---------- driving doctor ----------

# DOCTOR IS ALWAYS RUN FROM INSIDE THE PROJECT IT IS DIAGNOSING, because that is
# the only thing that makes its answer addressable: `project_root "$PWD"` is
# doctor's `DOCTOR_ROOT`, and the Patrol section reports on the sessions belonging
# to THAT root. Before Section 11 this helper took the claude-home alone and let
# doctor inherit the test runner's own cwd — this checkout — while every fixture
# session named a `/var/folders/...` project. The sections passed because doctor
# filtered on nothing at all; a session from any project on the machine printed
# here. The cwd is now an argument, and it is the fixture repo the session under
# test actually lives in.
run_doctor() {  # <claude-home> <project-cwd>
  ( cd "$2" && BIONIC_CLAUDE_HOME="$1" BIONIC_PLUGIN_ROOT="$PAYLOAD" BIONIC_DOCTOR_PROBE_SECONDS=3 \
      bash "$DOCTOR_SH" < /dev/null 2>&1 )
}

# The PATROL section alone — from its bare header to end of output, which is
# where the default (no --updates) run ends.
patrol_block() {  # <full-output>
  printf '%s\n' "$1" | awk '/^PATROL$/{f=1} f'
}

section "Section 1: no live Patrol anywhere"

EMPTY_HOME="$(make_empty_claude_home)"
EMPTY_PROJ="$(make_repo_without_roster)"
OUT1="$(run_doctor "$EMPTY_HOME" "$EMPTY_PROJ")"
PB1="$(patrol_block "$OUT1")"

expect_match    "1: the fallback line prints" "*none running*" "$PB1"
expect_no_match "2: no session line prints alongside the fallback" "*session*" "$PB1"

section "Section 2: one live Patrol, one open dispatch (singular)"

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

OUT2="$(run_doctor "$HOME2" "$REPO2")"
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

section "Section 3: duplicate Patrols — the one survivor"

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

OUT3="$(run_doctor "$HOME3" "$REPO3")"
PB3="$(patrol_block "$OUT3")"

expect_match "12: the running Patrol still prints, 0 open dispatches (plural)" \
  "*✓ session ${SHORT3} · 0 open dispatches*" "$PB3"
expect_match "13: the duplicate fix line names the OLDER job for deletion" \
  "*session ${SHORT3} has 2 Patrol jobs armed → CronDelete old11111*" "$OUT3"
expect_no_match "14: the fix line does NOT also name the newer (kept) job" \
  "*CronDelete*new22222*" "$OUT3"
expect_no_match "15: the Patrol block itself carries no per-job detail" \
  "*old11111*" "$PB3"

section "Section 4: the job is in the transcript and the Patrol is DEAD"

# WHAT THIS SECTION OWNS, and why nothing above it could see it. Jobs are
# reconstructed from the transcript — CronCreate minus CronDelete — and the four
# events that kill a Patrol (a plugin update, /reload-plugins, a continue, a
# /clear and resume) take the job out of the CLI's in-memory cron table with no
# tool call behind them. So the count stays positive on a machine where nothing
# is firing, and doctor printed `✓ session … · N open dispatches` for it: the
# Step-6 correctness FAIL against AC-F3. The fixture is Section 2's, with one
# thing changed — the stamp is three hours old, well past the fire window.
#
# AND THE STAMP'S AGE IS NO LONGER THE WHOLE FIXTURE (epic-23 wave-16 REQ-11). A session
# cron fires only while the session is idle, so "dead" is now an idle gap at least one fire
# window long since the stamp with no tick in it — read off the transcript, which therefore
# has to be DATABLE and has to hold that gap. Three hours of stamp with one turn-starting
# user record a second ago is the same machine this section always described, said in the
# terms the reading now uses. Section 17 holds the other three verdicts.

SID4="dddddddd-1111-2222-3333-444455556666"
SHORT4="${SID4%%-*}"
spawn_live_pid; PID4="$LIVE_PID"
REPO4="$(make_repo_with_roster "$SID4" beta -- alpha)"
HOME4="$(make_claude_home "$SID4" "$PID4" "$REPO4")"
TR4="$(transcript_of "$HOME4" "$SID4")"
plant_patrol_job_dated "$TR4" "toolu_1" "abc12345" 10000
dp_user "$TR4" 1 "carry on"
plant_patrol_stamp "$REPO4" "$SID4" 3

OUT4="$(run_doctor "$HOME4" "$REPO4")"
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

section "Section 5: the job is in the transcript and there is no stamp"

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

OUT5="$(run_doctor "$HOME5" "$REPO5")"
PB5="$(patrol_block "$OUT5")"

expect_no_match "23: a never-armed session prints no running line" "*session ${SHORT5}*" "$PB5"
expect_match    "24: the section falls back to none running" "*none running*" "$PB5"
expect_no_match "25: and a deliberate stop earns no fix line" \
  "*session ${SHORT5}: the Patrol*" "$OUT5"

section "Section 7: a firing Patrol with NO roster file and launches in the transcript"

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

OUT7="$(run_doctor "$HOME7" "$REPO7")"
PB7="$(patrol_block "$OUT7")"

expect_match "27: an absent roster is rendered as absent, not as a count" \
  "*✓ session ${SHORT7} · roster absent — launches unrecorded*" "$PB7"
# THE ORIGINAL LIE, WALLED. Not "the number is right now" — the claim itself is
# withdrawn, because a session with no roster has no open-dispatch count to make.
expect_no_match "28: and the row makes no open-dispatch claim at all" \
  "*open dispatch*" "$PB7"
# ALL THREE, AND THE WINDOW IS WHY THAT IS STILL THE RIGHT NUMBER (S9). Since the
# windowing cluster landed, `blind` is counted from the roster's own birth — and with no
# roster on disk that window falls back to the Patrol stamp planted above. These launches
# carry no `timestamp` field at all, which both readers treat as in-window (the
# alternative, dropping undatable entries, would silently shrink every count on a
# transcript shape neither reader has seen). Section 12 is where a DATED transcript
# separates the two behaviours; here the count is the whole transcript because the
# transcript has nothing to scope by, and that is the fallback the window must not disturb.
expect_match "29: an undatable transcript is counted whole — the fix line names all three" \
  "*session ${SHORT7}: 3 launches unrostered → re-invoke /bionic:canonical-sdlc*" "$OUT7"

section "Section 8: a firing Patrol whose roster is PRESENT and incomplete"

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

OUT8="$(run_doctor "$HOME8" "$REPO8")"
PB8="$(patrol_block "$OUT8")"

expect_match "30: a present roster still prints its own open count, unchanged" \
  "*✓ session ${SHORT8} · 1 open dispatch*" "$PB8"
expect_no_match "31: and a present roster is never re-rendered as absent" \
  "*roster absent*" "$PB8"
# THE ROSTER IS PRESENT HERE, so the window is its own birth — and these launches are
# undated, so all three are in it and `blind` is the roster's real shortfall rather than a
# lifetime tally that happens to match. The distinction is invisible on this fixture by
# construction; Section 12 is the fixture where it is not.
expect_match "32: an undatable transcript, present roster — only the launches it never saw" \
  "*session ${SHORT8}: 2 launches unrostered → re-invoke /bionic:canonical-sdlc*" "$OUT8"

section "Section 9: one cure, two surfaces — and the column budget"

# ONE CURE, ONE SURFACE NOW (bionic 1.4.0, task ADOPT). This used to be a two-reader
# agreement: hooks/session-poker.sh decided `wall-blind` at tick time and named the
# repair, and doctor named the same repair hours later off the same `patrol-wall/v1`
# record. The tick's decision is retired — it inferred a dead dispatch wall from
# dispatches outnumbering roster rows, and always-on registration removes the condition
# that made that inference worth drawing — so there is no second speller left to agree
# with, and a pin against a deleted line would be a pin over air.
#
# What remains is worth pinning on its own: the cure doctor prints and the row it prints
# it beside come from ONE record, `patrol-wall/v1`, whose schema token lives in
# lib/patrol.sh. Both halves are asserted, so a doctor that stopped reading that record
# or a library that renamed it goes red.
lines_matching() {  # <text> <glob> -> the matching lines
  local line out=""
  while IFS= read -r line || [ -n "$line" ]; do
    # shellcheck disable=SC2053  # RHS is a glob on purpose
    if [[ "$line" == $2 ]]; then out="${out}${line}"$'\n'; fi
  done <<< "$1"
  printf '%s' "$out"
}

CURE='re-invoke /bionic:canonical-sdlc'
PATROL_LIB_TEXT="$(cat "${PAYLOAD}/scripts/lib/patrol.sh")"
DOCTOR_TEXT="$(cat "$DOCTOR_SH")"
# PINNED TO THE RECORD DOCTOR READS, not merely to the file that contains the phrase.
# An extraction that found nothing fails the match rather than passing it, which is what
# keeps this from becoming a pin over air.
DOCTOR_WALL_LINE="$(lines_matching "$DOCTOR_TEXT" '*patrol-wall/v1*')"
expect_match "33: payload/scripts/doctor.sh reads the patrol-wall/v1 record" \
  "*patrol-wall/v1*" "$DOCTOR_WALL_LINE"
expect_match "33b: …and lib/patrol.sh is where that schema token is defined" \
  "*PATROL_WALL_SCHEMA=\"patrol-wall/v1\"*" "$PATROL_LIB_TEXT"
expect_match "34: payload/scripts/doctor.sh spells the cure" "*${CURE}*" "$DOCTOR_TEXT"

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

section "Section 10: a firing Patrol with NO roster file and NOTHING dispatched"

# THE HEALTHY HALF OF `present=no`, and the reason Section 7's row is gated on a
# COUNT rather than on the file. The roster file is written by the FIRST
# dispatch — hooks/dispatch-preflight.sh appends its header and the first row
# together and nothing pre-creates it at session start — so a perfectly healthy
# session that has not dispatched anything yet has no roster file either. This
# fixture is Section 7's with exactly one thing removed: the three `Agent`
# tool_uses. `blind` is the field that separates the two (`agents - rostered -
# refused`), and a session with no launches has nothing unrecorded.
#
# 1.3.0 printed `0 open dispatches` here and that number was TRUE. This task
# exists to stop doctor claiming a count nobody dispatched; saying "launches
# unrecorded" over a session that launched nothing is the same error pointed the
# other way. This section is the control that keeps the fix from overshooting,
# and it is why the absent row is gated on `blind > 0` rather than on
# `present = no`.

SID10="bbbbbbbb-7777-2222-3333-444455556666"
SHORT10="${SID10%%-*}"
spawn_live_pid; PID10="$LIVE_PID"
REPO10="$(make_repo_without_roster)"
HOME10="$(make_claude_home "$SID10" "$PID10" "$REPO10")"
TR10="$(transcript_of "$HOME10" "$SID10")"
plant_patrol_job "$TR10" "toolu_1" "abc12345"
# No plant_agent_dispatch call — the absence IS the variable under test.
plant_patrol_stamp "$REPO10" "$SID10"

OUT10="$(run_doctor "$HOME10" "$REPO10")"
PB10="$(patrol_block "$OUT10")"

expect_match "37: a session that dispatched nothing keeps its true zero" \
  "*✓ session ${SHORT10} · 0 open dispatches*" "$PB10"
expect_no_match "38: and is never described as a missing record" \
  "*roster absent*" "$PB10"
expect_no_match "39: nor earns an unrostered-launch fix line it cannot have" \
  "*session ${SHORT10}: * unrostered*" "$OUT10"

section "Section 11: two projects on one machine — doctor answers about ONE"

# THE DEFECT THIS SECTION OWNS (T3 finding 1, AC-35 drive, 2026-09-03). Doctor
# was driven cold in a session whose cwd was a probe project and printed a PATROL
# section naming `b1a850c1` (cwd this checkout) and `6c4fe341` (cwd a synthesis
# repo) — two sessions belonging to two OTHER projects — while the `active run`
# row three lines below it resolved the probe project's own plan. Both facts came
# off the same page, so the page contradicted itself about which machine it was
# describing.
#
# WHERE IT CAME FROM. `patrol_report` (lib/patrol.sh) walks every live session on
# the machine, and already computes for each one whether its repo is the caller's
# — it emits `here=yes|no` and has since it was written. doctor.sh's parse loop
# read `session=`, `open=`, `present=`, `blind=` and `state=`, and never `here=`
# or `cwd=`: the filter was not wrong, it was absent.
#
# THE ADDRESS IS `project_root`, NOT A STRING COMPARE. `lib/root.sh` is the SSoT
# every reader in this payload resolves a cwd through, and a session's recorded
# cwd is routinely a SUBDIRECTORY of its project — so session A below stands in
# `${REPO_A}/sub/deeper`, which only resolves onto the project doctor is
# diagnosing if the comparison goes through the library. A literal `cwd = root`
# test passes every other case in this file and fails this one.

SID_A="11111111-aaaa-2222-3333-444455556666"
SHORT_A="${SID_A%%-*}"
SID_B="22222222-bbbb-2222-3333-444455556666"
SHORT_B="${SID_B%%-*}"

spawn_live_pid; PID_A="$LIVE_PID"
spawn_live_pid; PID_B="$LIVE_PID"

# Project A — the one doctor is pointed at. One open dispatch, and the session
# sits two directories below the root.
REPO_A="$(make_repo_with_roster "$SID_A" beta -- alpha)"
mkdir -p "${REPO_A}/sub/deeper"
HOME_AB="$(make_claude_home "$SID_A" "$PID_A" "${REPO_A}/sub/deeper")"
TR_A="$(transcript_of "$HOME_AB" "$SID_A")"
plant_patrol_job "$TR_A" "toolu_a" "aaa11111"
plant_patrol_stamp "$REPO_A" "$SID_A"

# Project B — a second, entirely unrelated project on the same machine, with its
# own live session, its own firing Patrol, its own roster, and TWO Patrol jobs so
# that it would also emit a duplicate-Patrol fix line if doctor were listening.
REPO_B="$(make_repo_with_roster "$SID_B" gamma delta)"
jq -nc --arg sid "$SID_B" --argjson pid "$PID_B" --arg cwd "$REPO_B" \
  '{sessionId:$sid,pid:$pid,cwd:$cwd}' > "${HOME_AB}/sessions/${SID_B}.json"
: > "${HOME_AB}/projects/-fixture-proj/${SID_B}.jsonl"
TR_B="$(transcript_of "$HOME_AB" "$SID_B")"
plant_patrol_job "$TR_B" "toolu_b1" "bbb11111"
plant_patrol_job "$TR_B" "toolu_b2" "bbb22222"
plant_patrol_stamp "$REPO_B" "$SID_B"

OUT11="$(run_doctor "$HOME_AB" "$REPO_A")"
PB11="$(patrol_block "$OUT11")"

expect_match "40: the session belonging to THIS project prints, resolved from a subdirectory" \
  "*✓ session ${SHORT_A} · 1 open dispatch*" "$PB11"
expect_no_match "41: the other project's live session is not listed here" \
  "*session ${SHORT_B}*" "$PB11"
expect_no_match "42: nor does its duplicate-Patrol fix line reach this page" \
  "*CronDelete*bbb11111*" "$OUT11"
expect_no_match "43: and no row is attributed to the other project's roster" \
  "*2 open dispatches*" "$PB11"

section "Section 12: the wall-blind window is scoped to the roster's OWN birth"
# ============================================================
#
# THE FALSE ALARM THIS CLOSES (S9, ledger P2/T4; the live site is
# payload/scripts/doctor.sh:1381). lib/patrol.sh counted `agents` and `refused` over the
# transcript's WHOLE LIFE, so a session that ran a wave BEFORE `.bionic/tmp` was last wiped
# read that earlier wave's dispatches against a roster that only began at the wipe — and
# doctor printed `N launches unrostered → re-invoke /bionic:canonical-sdlc` at a wall that
# had rostered everything asked of it since. The cure it names clears nothing, which is the
# worst shape a fix line can take.
#
# WHY IT NEEDS ITS OWN FIXTURE. Sections 7 and 8 plant launches with no `timestamp` field,
# so no window can move their counts — they pin the undatable fallback and say so. Here
# every launch is DATED, on both sides of the roster's own creation instant, which is the
# only fixture shape where the windowed answer and the lifetime answer differ.
#
# 12a is the false alarm itself: silent after the fix, and the RED before it. 12b is the
# paired negative — a REAL gap INSIDE the window is still named, so 12a is not the fix
# line being switched off. 12c pins the fallback 12a must not have disturbed.
#
# ASSERTION NUMBERS CONTINUE THE FILE'S SEQUENCE (75+) rather than the section's position:
# the labels are identities a red line is looked up by, and renumbering 44-74 to make room
# would rewrite the identity of every assertion below this one.

plant_agent_dispatch_at() {  # <transcript> <tool_use_id> <iso ts>
  local t="$1" tid="$2" ts="$3"
  jq -nc --arg id "$tid" --arg ts "$ts" \
    '{type:"assistant",isSidechain:false,timestamp:$ts,
      message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"Agent",
        input:{description:"fixture task",subagent_type:"general-purpose",
               prompt:"Do the fixture work and report back."}}]}}' \
    >> "$t"
  jq -nc --arg id "$tid" --arg ts "$ts" \
    '{type:"user",isSidechain:false,timestamp:$ts,
      message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,
        content:"The agent finished and reported back."}]}}' \
    >> "$t"
}

# CLOCK DISCIPLINE, the house rule: nothing here sleeps. "Before the roster" is a
# timestamp a day old and "inside the window" is now — the roster file is created by
# `make_repo_with_roster` on the line above the planting, so its birth instant is already
# past by the time these entries are written.
iso_ago() {  # <seconds ago> -> UTC ISO-8601
  date -u -v-"$1"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "-$1 seconds" +%Y-%m-%dT%H:%M:%SZ
}

# THE WINDOW NEEDS A FILESYSTEM THAT KEEPS CREATION TIMES. `roster_window` reads `stat %B`
# / `%W`, and a filesystem answering 0 means "no birth recorded" — the window then falls
# back to empty and every arm below would read the whole transcript. That is a correct
# fallback and a useless test, so it is named out loud rather than passed over.
S12_BIRTH_OK=yes
S12_PROBE="$TMP/birth-probe"; : > "$S12_PROBE"
S12_B="$(stat -f %B "$S12_PROBE" 2>/dev/null || stat -c %W "$S12_PROBE" 2>/dev/null)"
case "${S12_B:-0}" in ''|*[!0-9]*|0) S12_BIRTH_OK=no ;; esac

if [ "$S12_BIRTH_OK" = no ]; then
  no "75: this filesystem records no file birth time — Section 12 cannot run" \
     "stat %B/%W returned '${S12_B:-}' for $S12_PROBE"
else

# --- 12a: a wave BEFORE this roster's birth, one rostered dispatch inside the window ---
SID12A="12aaaaaa-1111-2222-3333-444455556666"
SHORT12A="${SID12A%%-*}"
spawn_live_pid; PID12A="$LIVE_PID"
REPO12A="$(make_repo_with_roster "$SID12A" wave-two-row)"   # <- the roster is born HERE
HOME12A="$(make_claude_home "$SID12A" "$PID12A" "$REPO12A")"
TR12A="$(transcript_of "$HOME12A" "$SID12A")"
plant_patrol_job "$TR12A" "toolu_1" "abc12345"
plant_agent_dispatch_at "$TR12A" "toolu_w1a" "$(iso_ago 86400)"   # wave one, before the wipe
plant_agent_dispatch_at "$TR12A" "toolu_w1b" "$(iso_ago 86400)"
plant_agent_dispatch_at "$TR12A" "toolu_w1c" "$(iso_ago 86400)"
plant_agent_dispatch_at "$TR12A" "toolu_w1d" "$(iso_ago 86400)"
plant_agent_dispatch_at "$TR12A" "toolu_w2a" "$(iso_ago 0)"       # wave two, and it IS rostered
plant_patrol_stamp "$REPO12A" "$SID12A"

OUT12A="$(run_doctor "$HOME12A" "$REPO12A")"
PB12A="$(patrol_block "$OUT12A")"

expect_match "75: a live wall's row prints its true, in-window open count (1)" \
  "*✓ session ${SHORT12A} · 1 open dispatch*" "$PB12A"
expect_no_match "76: …and earns NO fix line — the earlier wave is not this roster's blind spot" \
  "*session ${SHORT12A}: * unrostered*" "$OUT12A"

# --- 12b: the paired negative — a REAL gap INSIDE the window still fires ---
SID12B="12bbbbbb-1111-2222-3333-444455556666"
SHORT12B="${SID12B%%-*}"
spawn_live_pid; PID12B="$LIVE_PID"
REPO12B="$(make_repo_with_roster "$SID12B" wave-two-row)"
HOME12B="$(make_claude_home "$SID12B" "$PID12B" "$REPO12B")"
TR12B="$(transcript_of "$HOME12B" "$SID12B")"
plant_patrol_job "$TR12B" "toolu_1" "abc12345"
plant_agent_dispatch_at "$TR12B" "toolu_w1a" "$(iso_ago 86400)"
plant_agent_dispatch_at "$TR12B" "toolu_w1b" "$(iso_ago 86400)"
plant_agent_dispatch_at "$TR12B" "toolu_w1c" "$(iso_ago 86400)"
plant_agent_dispatch_at "$TR12B" "toolu_w1d" "$(iso_ago 86400)"
plant_agent_dispatch_at "$TR12B" "toolu_w2a" "$(iso_ago 0)"   # rostered
plant_agent_dispatch_at "$TR12B" "toolu_w2b" "$(iso_ago 0)"   # NOT rostered
plant_agent_dispatch_at "$TR12B" "toolu_w2c" "$(iso_ago 0)"   # NOT rostered
plant_patrol_stamp "$REPO12B" "$SID12B"

OUT12B="$(run_doctor "$HOME12B" "$REPO12B")"
PB12B="$(patrol_block "$OUT12B")"

expect_match "77: …and a wall that missed a dispatch INSIDE the window is still caught" \
  "*✓ session ${SHORT12B} · 1 open dispatch*" "$PB12B"
expect_match "78: the fix line counts the window's own gap (2), not the transcript's lifetime (6)" \
  "*session ${SHORT12B}: 2 launches unrostered → re-invoke /bionic:canonical-sdlc*" "$OUT12B"

# --- 12c: the fallback the fix must not disturb — no roster at all, undatable launches ---
SID12C="12cccccc-1111-2222-3333-444455556666"
SHORT12C="${SID12C%%-*}"
spawn_live_pid; PID12C="$LIVE_PID"
REPO12C="$(make_repo_without_roster)"
HOME12C="$(make_claude_home "$SID12C" "$PID12C" "$REPO12C")"
TR12C="$(transcript_of "$HOME12C" "$SID12C")"
plant_patrol_job "$TR12C" "toolu_1" "abc12345"
plant_agent_dispatch "$TR12C" "toolu_c1"
plant_agent_dispatch "$TR12C" "toolu_c2"
plant_patrol_stamp "$REPO12C" "$SID12C"

OUT12C="$(run_doctor "$HOME12C" "$REPO12C")"
PB12C="$(patrol_block "$OUT12C")"

expect_match "79: no roster to scope a window by — the row still says the record is absent" \
  "*✓ session ${SHORT12C} · roster absent — launches unrecorded*" "$PB12C"
expect_match "80: …with a fix line for both unrostered launches" \
  "*session ${SHORT12C}: 2 launches unrostered → re-invoke /bionic:canonical-sdlc*" "$OUT12C"

# THE WINDOW ITSELF, ASKED DIRECTLY. 75-80 read doctor's rendering; this reads the
# instant the whole cluster turns on, so a section that went green because the window
# came back EMPTY (every count falling back to the lifetime) cannot pass unnoticed.
S12_WIN="$( cd "$REPO12A" && CLAUDE_CODE_SESSION_ID="$SID12A" \
            bash "${BIONIC_HOOKS_DIR}/session-poker.sh" window 2>/dev/null )"
expect_regex "81: the poker dates 12a's roster — the window is a real instant, not empty" \
  '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$S12_WIN"

fi

section "Section 13: a NESTED .bionic below a git root — roster must resolve through project_root"
# ============================================================
# FIX-PATROL-ROOT (wave.plan.md Assumptions, FIX-DOCTOR/5). lib/patrol.sh's
# _patrol_repo_root asked git for --git-common-dir FIRST and walked for a
# nested `.bionic` only when no repository existed at all — the ordering
# lib/root.sh's own header names as the bug the other eight copies shared
# before this wave. A git repo holding a `.bionic` BELOW its root (spec AC-10,
# tests/root.test.sh §3) writes its roster under the nested `.bionic/tmp`
# while this resolver answered with the git toplevel — the roster read as
# absent and the session as blind. The session's own repo and doctor's
# `here_repo` both go through the same (buggy) resolver, so the "here" gate
# still agreed; what broke was finding the roster file at all.
SID13="ffffffff-1111-2222-3333-444455556666"
SHORT13="${SID13%%-*}"
spawn_live_pid; PID13="$LIVE_PID"

GITROOT13="$(mktemp -d -p "$TMP")"
git -c init.defaultBranch=main init -q "$GITROOT13" >/dev/null 2>&1
NESTED13="$GITROOT13/apps/inner"
mkdir -p "$NESTED13/.bionic/tmp"
roster_row_fixture status=intended session="$SID13" name=beta \
  > "$NESTED13/.bionic/tmp/roster-${SID13}.state"

HOME13="$(make_claude_home "$SID13" "$PID13" "$NESTED13")"
TR13="$(transcript_of "$HOME13" "$SID13")"
plant_patrol_job "$TR13" "toolu_13" "fff13131"
plant_patrol_stamp "$NESTED13" "$SID13"

OUT13="$(run_doctor "$HOME13" "$NESTED13")"
PB13="$(patrol_block "$OUT13")"

expect_match "46: a nested .bionic below the git root still finds its roster" \
  "*✓ session ${SHORT13} · 1 open dispatch*" "$PB13"

# ---- differential control: .bionic AT the git root resolves the same way ----
# Same shape, .bionic planted at the repo root instead of nested below it — the
# git root and project_root's answer already coincide here, so this passed
# before the fix too. Proves 46 is not vacuous: the harness can find a roster
# through this path, and the nested case above is what specifically breaks.
GITROOT13B="$(mktemp -d -p "$TMP")"
git -c init.defaultBranch=main init -q "$GITROOT13B" >/dev/null 2>&1
mkdir -p "$GITROOT13B/.bionic/tmp"
SID13B="00000000-1111-2222-3333-444455556666"
SHORT13B="${SID13B%%-*}"
spawn_live_pid; PID13B="$LIVE_PID"
roster_row_fixture status=intended session="$SID13B" name=beta \
  > "$GITROOT13B/.bionic/tmp/roster-${SID13B}.state"
HOME13B="$(make_claude_home "$SID13B" "$PID13B" "$GITROOT13B")"
TR13B="$(transcript_of "$HOME13B" "$SID13B")"
plant_patrol_job "$TR13B" "toolu_13b" "fff13132"
plant_patrol_stamp "$GITROOT13B" "$SID13B"

OUT13B="$(run_doctor "$HOME13B" "$GITROOT13B")"
PB13B="$(patrol_block "$OUT13B")"

expect_match "47: control — .bionic AT the git root still resolves" \
  "*✓ session ${SHORT13B} · 1 open dispatch*" "$PB13B"

# THE CONTROL, so 41-43 are not three negatives over an empty section. Pointed at
# project B, the same claude-home, the same two sessions, doctor answers about B
# and says nothing about A.
OUT12="$(run_doctor "$HOME_AB" "$REPO_B")"
PB12="$(patrol_block "$OUT12")"

expect_match "44: pointed at the other project, that project's session prints" \
  "*✓ session ${SHORT_B} · 2 open dispatches*" "$PB12"
expect_no_match "45: and the first project's session is now the one absent" \
  "*session ${SHORT_A}*" "$PB12"

section "Section 14: the engagement field — report only (T4/AC-16)"
# THE SAME SWITCH EVERY RUN-SCOPED HOOK READS FIRST (lib/run.sh
# `engaged_session`) — doctor's row says which side of it this session's
# marker is on, and changes nothing on disk: the `find | sort` fingerprint
# below is taken AFTER the fixture is fully built and BEFORE doctor runs, so
# any write doctor itself made would show up as a mismatch.

SID14="33333333-cccc-2222-3333-444455556666"
SHORT14="${SID14%%-*}"
spawn_live_pid; PID14="$LIVE_PID"
REPO14="$(make_repo_with_roster "$SID14" beta -- alpha)"
HOME14="$(make_claude_home "$SID14" "$PID14" "$REPO14")"
TR14="$(transcript_of "$HOME14" "$SID14")"
plant_patrol_job "$TR14" "toolu_14" "eee14141"
plant_patrol_stamp "$REPO14" "$SID14"
mkdir -p "$REPO14/.bionic/tmp"
: > "$REPO14/.bionic/tmp/engaged-${SID14}.state"
BEFORE14="$(find "$REPO14/.bionic" | sort)"

OUT14="$(run_doctor "$HOME14" "$REPO14")"
PB14="$(patrol_block "$OUT14")"

expect_match "48: an engaged session's row says so" \
  "*✓ session ${SHORT14} · 1 open dispatch · engaged*" "$PB14"
if [ "$BEFORE14" = "$(find "$REPO14/.bionic" | sort)" ]; then
  ok "49: doctor changed nothing on disk for an engaged session"
else
  no "49: doctor changed nothing on disk for an engaged session"
fi

SID15="44444444-dddd-2222-3333-444455556666"
SHORT15="${SID15%%-*}"
spawn_live_pid; PID15="$LIVE_PID"
REPO15="$(make_repo_with_roster "$SID15" beta -- alpha)"
HOME15="$(make_claude_home "$SID15" "$PID15" "$REPO15")"
TR15="$(transcript_of "$HOME15" "$SID15")"
plant_patrol_job "$TR15" "toolu_15" "eee15151"
plant_patrol_stamp "$REPO15" "$SID15"
BEFORE15="$(find "$REPO15/.bionic" | sort)"

OUT15="$(run_doctor "$HOME15" "$REPO15")"
PB15="$(patrol_block "$OUT15")"

expect_match "50: a session with no marker reads not engaged" \
  "*✓ session ${SHORT15} · 1 open dispatch · not engaged*" "$PB15"
if [ "$BEFORE15" = "$(find "$REPO15/.bionic" | sort)" ]; then
  ok "51: doctor changed nothing on disk for a not-engaged session"
else
  no "51: doctor changed nothing on disk for a not-engaged session"
fi

# The roster-absent row carries the field too — the two _patrol_add call
# sites under `firing)` share the one computed value, so neither can drift.
SID16="55555555-eeee-2222-3333-444455556666"
spawn_live_pid; PID16="$LIVE_PID"
REPO16="$(make_repo_without_roster)"
HOME16="$(make_claude_home "$SID16" "$PID16" "$REPO16")"
TR16="$(transcript_of "$HOME16" "$SID16")"
plant_patrol_job "$TR16" "toolu_16" "eee16161"
plant_agent_dispatch "$TR16" "toolu_a16"
plant_patrol_stamp "$REPO16" "$SID16"

OUT16="$(run_doctor "$HOME16" "$REPO16")"
PB16="$(patrol_block "$OUT16")"

expect_match "52: the roster-absent row carries the field too" \
  "*roster absent — launches unrecorded · not engaged*" "$PB16"

# THE COLUMN BUDGET, same ruler as Section 9 — bionic_cols/first_over_budget/
# BIONIC_LINE_WIDTH are already sourced above.
WIDE_ENG="$(first_over_budget "${PB14}
${PB15}
${PB16}")"
if [ -z "$WIDE_ENG" ]; then
  ok "53: every engaged/not-engaged row fits the ${BIONIC_LINE_WIDTH}-column budget"
else
  no "53: every engaged/not-engaged row fits the ${BIONIC_LINE_WIDTH}-column budget" \
    "line is $(bionic_cols "$WIDE_ENG") columns: $WIDE_ENG"
fi

section "Section 15: a marker alone closes no row — an UNMET one never did, a MET one no longer does (Step-6 security review, out-of-axis 2; epic-23 wave-20 T17, D10)"

# FOUR READERS OF ONE SCHEMA DISAGREED ABOUT WHETHER `state=` MATTERS.
# hooks/session-start.sh's `open_rows` and the poker's `adopt_fold` require
# `state=MET` before a `landing-swept/v1` line closes a row; `patrol_roster_state`
# here and `youngest_suite_writer` in the poker took ANY marker at all. S17's
# `adopt_copy_marker` is a second writer that copies a predecessor's verdict —
# UNMET included — verbatim onto a successor's roster, so the two state-blind
# readers are exactly the two that now meet those markers. A row whose contract
# the sweep judged UNMET is open work by every other reader in the fleet, and
# doctor reporting it as closed is doctor reporting a wave as finished.

SID17="ffffffff-7777-2222-3333-444455556666"
SHORT17="${SID17%%-*}"
spawn_live_pid; PID17="$LIVE_PID"
REPO17="$(make_repo_with_roster "$SID17" -- closed-met)"
# The UNMET row, appended in the originator's exact shape beside the MET one.
ROSTER17="$REPO17/.bionic/tmp/roster-${SID17}.state"
roster_row_fixture status=intended session="$SID17" name=unmet-row >> "$ROSTER17"
swept_marker_write "$ROSTER17" 2026-08-27T00:00:01Z "$SID17" unmet-row a000 UNMET
HOME17="$(make_claude_home "$SID17" "$PID17" "$REPO17")"
TR17="$(transcript_of "$HOME17" "$SID17")"
plant_patrol_job "$TR17" "toolu_1" "abc17777"
plant_patrol_stamp "$REPO17" "$SID17"

OUT17="$(run_doctor "$HOME17" "$REPO17")"
PB17="$(patrol_block "$OUT17")"

expect_match "54: an UNMET marker leaves its row OPEN — one open dispatch, not zero" \
  "*✓ session ${SHORT17} · 1 open dispatch*" "$PB17"
expect_no_match "55: …and the acked MET row beside it is still closed (the count is 1, never 2)" \
  "*2 open dispatches*" "$PB17"

# RE-AUTHORED BY T17 (epic-23 wave-20, D10). This row used to read "flipping that same marker
# to MET closes it", pinning the MET close T17 removes: `patrol_roster_state` now asks
# `roster_open_names`, the predicate the dispatch wall, the sweeper, the stop wall and the
# tick's adopt fold already share, and a MET marker there closes nothing — it records a
# landing seen, not an agent gone. So the flip leaves the count where it was.
sed 's/|name=unmet-row|agent_id=a000|state=UNMET$/|name=unmet-row|agent_id=a000|state=MET/' \
  "$ROSTER17" > "$ROSTER17.met" && mv "$ROSTER17.met" "$ROSTER17"
OUT17B="$(run_doctor "$HOME17" "$REPO17")"
PB17B="$(patrol_block "$OUT17B")"
expect_match "56 (T17: was '…flipping that same marker to MET closes it'): a MET marker with no ack closes nothing — still one open dispatch" \
  "*✓ session ${SHORT17} · 1 open dispatch*" "$PB17B"

# THE PAIRED POSITIVE the old 56 was: the one thing that does close the row. An ack stamped
# after the row's launch takes the count to zero, so "1 open" above is not a reader that has
# stopped closing rows at all.
ack_write "$REPO17/.bionic/tmp/sweeper-${SID17}.state" 2026-09-02T01:00:00Z "$SID17" unmet-row
OUT17C="$(run_doctor "$HOME17" "$REPO17")"
PB17C="$(patrol_block "$OUT17C")"
expect_match "56b …and an ack after its launch closes it (56 discriminates)" \
  "*✓ session ${SHORT17} · 0 open dispatches*" "$PB17C"

# AN ACK OLDER THAN A RELAUNCH CLOSES NOTHING. The same name dispatched again after its ack
# is open work again — the case a MET latch used to hide for the rest of the session.
roster_row_fixture status=intended session="$SID17" name=unmet-row launched_at=2026-09-02T02:00:00Z \
  >> "$ROSTER17"
OUT17D="$(run_doctor "$HOME17" "$REPO17")"
PB17D="$(patrol_block "$OUT17D")"
expect_match "56c …and dispatching it again after that ack opens it again" \
  "*✓ session ${SHORT17} · 1 open dispatch*" "$PB17D"

section "Section 16: dead-session state — one collapsed line, one fix, no \"Nothing to do\" (1.5.1 T5, AC-8)"

# THE DEFECT THIS CLOSES, in its own shape (ideas/fixit-1.5.2-dead-session-sweep.md
# §Observed): a project whose predecessor sessions are all gone, whose `.bionic/tmp`
# holds their roster, preflight and engagement files, and whose doctor page listed
# them as informational dashes — or, for the ones whose rows had all landed, did not
# list them at all — under a header reading "Nothing to do".
#
# FIXTURE FIDELITY: the layout is the defect's, scaled down — three dead sessions
# with three classes each, one live session beside them, and `context-spend.state`,
# which carries no session id and must survive every reading. The residue case is
# the one that matters most: NONE of these rosters carries an open row, which is
# exactly the state the old open-row test rendered nothing for.
SID16_LIVE="e96260d1-6666-4666-8666-666666666666"
SID16_A="018c3ea1-1111-4111-8111-111111111111"
SID16_B="1dc72c57-2222-4222-8222-222222222222"
SID16_C="aa69dcad-3333-4333-8333-333333333333"

spawn_live_pid; PID16="$LIVE_PID"
REPO16="$(mktemp -d -p "$TMP")"
mkdir -p "$REPO16/.bionic/tmp"
for _s16 in "$SID16_A" "$SID16_B" "$SID16_C"; do
  printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' \
    > "$REPO16/.bionic/tmp/roster-${_s16}.state"
  printf 'preflight-attestation/v1|session=%s\n' "$_s16" \
    > "$REPO16/.bionic/tmp/preflight-${_s16}.state"
  printf 'engaged/v1|session=%s\n' "$_s16" \
    > "$REPO16/.bionic/tmp/engaged-${_s16}.state"
done
printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' \
  > "$REPO16/.bionic/tmp/roster-${SID16_LIVE}.state"
printf 'preflight-attestation/v1|session=%s\n' "$SID16_LIVE" \
  > "$REPO16/.bionic/tmp/preflight-${SID16_LIVE}.state"
printf 'context-spend/v1\n' > "$REPO16/.bionic/tmp/context-spend.state"

HOME16="$(make_claude_home "$SID16_LIVE" "$PID16" "$REPO16")"
OUT16="$(run_doctor "$HOME16" "$REPO16")"
PB16="$(patrol_block "$OUT16")"

# ONE LINE PER DEAD SESSION, counting files rather than open rows.
expect_match "57: a dead session with no open row still earns a line, and it counts files" \
  "*predecessor 018c3ea1*3 leftover files*" "$PB16"
expect_match "58: …so does the second" "*predecessor 1dc72c57*3 leftover files*" "$PB16"
expect_match "59: …and the residue session the defect was filed on" \
  "*predecessor aa69dcad*3 leftover files*" "$PB16"
expect_match "60: …and the line says what a reader can conclude, in words" \
  "*nothing open; the session is gone*" "$PB16"

# THE LIVE SESSION IS NOT ONE OF THEM — the paired positive that keeps the three
# rows above from passing on a page that simply lists every session it finds.
expect_no_match "61: the live session is never called a predecessor" \
  "*predecessor e96260d1*" "$PB16"

# COLLAPSED: a dead session costs the page ONE line, not one per section. Its
# attestation is gone from RESOURCES while the live session's remains.
DSR16="$(printf '%s\n' "$OUT16" | awk '/^RESOURCES$/{f=1;next} f && /^[A-Z][A-Z]/{exit} f')"
expect_no_match "62: a dead session's attestation is dropped from RESOURCES" \
  "*session 018c3ea1*" "$DSR16"
expect_no_match "63: …and so is the residue session's" "*session aa69dcad*" "$DSR16"
expect_match "64: …while the live session's attestation still renders there" \
  "*session e96260d1*" "$DSR16"

# THE FIX LINE, RE-POINTED TO THE AUTO-SWEEP'S OWN FAILURE MARKER (R2, ticket-30;
# this section pinned the OLD unconditional line — "N dead sessions left state
# under .bionic/tmp", one per dead session, count == dead sessions — until this
# task's own dead-session-state row change, which is what closed ticket-30's
# actual defect: hooks/session-start.sh sweeps this residue routinely now
# (REQ-R2), so "N dead sessions have residue right now" stopped being a problem
# doctor should keep naming forever between one `/clear` and the next session
# start. What is STILL a problem is the auto-sweep itself failing, which is a
# fact about a MARKER FILE, not about how many dead sessions exist — so this
# fixture (no marker planted) earns NO fix line at all, and a second fixture
# below (marker planted) earns exactly one, independent of the dead-session
# count.
#
# THE PREDECESSOR ROWS THEMSELVES ALSO CHANGED GLYPH (doctor.sh's PATROL loop):
# $DOCTOR_NIL now, not $DOCTOR_BAD — tests/doctor-reads.test.sh 12f18's own rule
# ("every ✗ row is a problem, count >= rows on the whole page") is what caught
# the old unconditional line leaving three ✗ predecessor rows on the page with
# nothing in N_FIX accounting for them once the fix line went conditional; a
# predecessor line marked ✗ while contributing nothing to the count is exactly
# that inequality, broken.
expect_absent "65: without a failure marker, no fix line names the dead sessions" \
  "left state under .bionic/tmp" "$OUT16"
expect_no_match "66: …and their PATROL lines are informational (§ above), never ✗ rows" \
  "*✗ predecessor*" "$PB16"

# ---------- the auto-sweep's own failure marker: exactly one fix line, however many dead sessions ----------
printf 'sweep-failed/v1|at=2026-09-07T00:00:00Z|rc=2\n' > "$REPO16/.bionic/tmp/sweep-failed.state"
OUT16M="$(run_doctor "$HOME16" "$REPO16")"

expect_contains "67: with the marker, the page names the failure and its rc" \
  "the automatic dead-session sweep failed (rc=2)" "$OUT16M"
expect_contains "68: …and the hint still comes from the check table, naming the auto-sweep, not a raw script (AC-6.3)" \
  "the automatic dead-session sweep failed (rc=2) → start a new session — its auto-sweep retries this" "$OUT16M"
expect_eq "69: …exactly once, regardless of how many dead sessions are on this page" \
  "1" "$(printf '%s\n' "$OUT16M" | grep -c 'automatic dead-session sweep failed')"
expect_absent "70: …and never sends the reader to setup, which has no project concept" \
  "sweep failed (rc=2) → /bionic:setup" "$OUT16M"
expect_absent "71: the header does not say there is nothing to do" \
  "Nothing to do" "$OUT16M"

# CAUSATION, NOT COINCIDENCE. The fixture machine has unrelated problems of its
# own, so a page that names a failure proves little by itself. Removing ONLY
# the marker (not the dead sessions' files, which are irrelevant to this row
# now) must drop the fix line and lower the problem count by exactly one — the
# count this ONE fix line stands for, never a function of how many predecessor
# sessions happen to be dead alongside it.
n16_problems() {  # <doctor output> -> the header's problem count, or empty
  printf '%s\n' "$1" | sed -n 's/^→ \([0-9][0-9]*\) problems*\..*$/\1/p' | head -1
}
N16_WITH_MARKER="$(n16_problems "$OUT16M")"
rm -f "$REPO16/.bionic/tmp/sweep-failed.state"
OUT16NM="$(run_doctor "$HOME16" "$REPO16")"
N16_NO_MARKER="$(n16_problems "$OUT16NM")"

expect_nonempty "72: the header states a problem count with the marker (73 is not vacuous)" \
  "$N16_WITH_MARKER"
expect_eq "73: …and removing ONLY the marker drops the count by exactly one" \
  "1" "$(( N16_WITH_MARKER - N16_NO_MARKER ))"
expect_absent "74: …and the fix line is gone with it" \
  "automatic dead-session sweep failed" "$OUT16NM"
expect_match "75: …while the (still-dead, still-unswept) predecessor lines remain, informational" \
  "*predecessor 018c3ea1*" "$(patrol_block "$OUT16NM")"

# THE ORIGINAL FIXTURE'S OWN DECAY, KEPT (1.5.1 T5, AC-8): removing the dead
# sessions' FILES (not the marker, which is already gone above) still collapses
# their predecessor lines away and leaves the live session's attestation and
# the unkeyed context-spend.state exactly where they were.
rm -f "$REPO16/.bionic/tmp/"roster-018c3ea1*.state "$REPO16/.bionic/tmp/"preflight-018c3ea1*.state \
      "$REPO16/.bionic/tmp/"engaged-018c3ea1*.state \
      "$REPO16/.bionic/tmp/"roster-1dc72c57*.state "$REPO16/.bionic/tmp/"preflight-1dc72c57*.state \
      "$REPO16/.bionic/tmp/"engaged-1dc72c57*.state \
      "$REPO16/.bionic/tmp/"roster-aa69dcad*.state "$REPO16/.bionic/tmp/"preflight-aa69dcad*.state \
      "$REPO16/.bionic/tmp/"engaged-aa69dcad*.state
OUT16B="$(run_doctor "$HOME16" "$REPO16")"
expect_no_match "76: …and no predecessor line remains" "*predecessor *" "$(patrol_block "$OUT16B")"
expect_match "77: …while the live session's attestation is still there" \
  "*session e96260d1*" "$(printf '%s\n' "$OUT16B" | awk '/^RESOURCES$/{f=1;next} f && /^[A-Z][A-Z]/{exit} f')"
expect_true "78: …and the unkeyed context-spend.state was never the subject" \
  test -f "$REPO16/.bionic/tmp/context-spend.state"

# =============================================================================
section "Section 17: the stamp is graded by IDLE time, never wall time (epic-23 wave-16 REQ-11, AC-11.1; ADR-028)"
# =============================================================================
#
# THE DEFECT THIS SECTION OWNS (carry-over 18, promoted by the user 2026-09-19: "/doctor
# still reports bionic unhealthy"). A session cron fires only while the session is IDLE, so
# a stamp older than any threshold says one of two things and arithmetic cannot tell them
# apart: the job is gone, or the orchestrator has been working. Wave-15 moved the two
# BLOCKING readers onto `patrol_verdict` (ADR-028) and left doctor's own reading — 
# `patrol_stamp_state` — multiplying the interval by two, so a busy orchestrator with a
# 2459s stamp against a 2400s limit was still told its Patrol was "armed but not firing".
#
# THE THRESHOLD IS THE FIRE WINDOW AND THE VERDICT IS THE TRANSCRIPT'S. Past one fire
# window (`patrol_fire_window`: the interval plus a tenth for jitter) the stamp is worth
# READING THE TRANSCRIPT about and is not, on its own, a verdict — the same two-step the
# stop library's revive notice and the dispatch wall take, for the same reason.
#
# SECTIONS 2, 7, 8 AND 10 ABOVE ARE THE OTHER HALF OF THIS PIN, unedited: their stamps are
# FRESH and their transcripts carry no dates at all, and they still print `✓`. A stamp
# inside one fire window cannot have missed a firing, so no scan is taken and an undatable
# transcript never costs a healthy session its row.

# ---------- AC-11.1, the field's own fixture: stale, and every second of it a busy turn ----
#
# 2459s stamp, 1200s interval, 1320s fire window, and a transcript holding ONE continuous
# 2500s turn — a prompt, then assistant records all the way to now, with no turn-starting
# user record after the prompt. There is no idle gap to measure, so the clock has had no
# opportunity to fire and its silence proves nothing.
SID17A="17aaaaaa-1111-2222-3333-444455556666"
SHORT17A="${SID17A%%-*}"
spawn_live_pid; PID17A="$LIVE_PID"
REPO17A="$(make_repo_with_roster "$SID17A" beta -- alpha)"
dp_pin_interval "$REPO17A"
HOME17A="$(make_claude_home "$SID17A" "$PID17A" "$REPO17A")"
TR17A="$(transcript_of "$HOME17A" "$SID17A")"
plant_patrol_job_dated "$TR17A" "toolu_1" "abc12345" 2600
dp_user "$TR17A" 2500 "a long piece of work"
for s17a in 2400 2100 1800 1500 1200 900 600 300 120 30 5; do dp_assistant "$TR17A" "$s17a"; done
plant_patrol_stamp "$REPO17A" "$SID17A"
dp_backdate "$REPO17A/.bionic/tmp/patrol-$SID17A.state" 2459

OUT17A="$(run_doctor "$HOME17A" "$REPO17A")"
PB17A="$(patrol_block "$OUT17A")"

expect_match "79: a stale stamp whose staleness is all busy turns keeps its running row" \
  "*✓ session ${SHORT17A}*" "$PB17A"
expect_no_match "80: …and earns no fix line" \
  "*session ${SHORT17A}: the Patrol is armed but not firing*" "$OUT17A"

# ---------- AC-11.1, the discrimination: the same stamp, an idle gap, no tick ----------
#
# CHANGE THE TRANSCRIPT ALONE and the same page accuses. Without this, 79 is a row anyone
# could earn by breaking the gate.
SID17B="17bbbbbb-1111-2222-3333-444455556666"
SHORT17B="${SID17B%%-*}"
spawn_live_pid; PID17B="$LIVE_PID"
REPO17B="$(make_repo_with_roster "$SID17B" beta -- alpha)"
dp_pin_interval "$REPO17B"
HOME17B="$(make_claude_home "$SID17B" "$PID17B" "$REPO17B")"
TR17B="$(transcript_of "$HOME17B" "$SID17B")"
plant_patrol_job_dated "$TR17B" "toolu_1" "abc12345" 10000
dp_user "$TR17B" 1 "carry on"
plant_patrol_stamp "$REPO17B" "$SID17B"
dp_backdate "$REPO17B/.bionic/tmp/patrol-$SID17B.state" 1500

OUT17B="$(run_doctor "$HOME17B" "$REPO17B")"
PB17B="$(patrol_block "$OUT17B")"

expect_match "81: an idle gap of a full fire window since the stamp, with no tick, is not firing" \
  "*session ${SHORT17B}: the Patrol is armed but not firing*" "$OUT17B"
expect_no_match "82: …and the section prints no running row for it" \
  "*✓ session ${SHORT17B}*" "$PB17B"

# ---------- the TICK's stamp is the proof of life, not the marker (wave-20 REQ-6, AC-6.3) ----------
#
# RE-AUTHORED AT WAVE-20 (D6). This used to read a `bionic-patrol session=` prompt after the
# stamp as the cron firing, moving the reference instant to it — so a Patrol whose job carried
# the marker but never ran the tick read healthy here for as long as it kept firing (report #1).
# The tick stamps before it decides, so a marker its tick answered sits BEFORE the stamp: here
# the marker fires at -2000s, its tick stamps at -1900s (past the 1320s fire window, so the
# verdict is read), and the session works on with no idle gap since. Still running.
SID17C="17cccccc-1111-2222-3333-444455556666"
SHORT17C="${SID17C%%-*}"
spawn_live_pid; PID17C="$LIVE_PID"
REPO17C="$(make_repo_with_roster "$SID17C" beta -- alpha)"
dp_pin_interval "$REPO17C"
HOME17C="$(make_claude_home "$SID17C" "$PID17C" "$REPO17C")"
TR17C="$(transcript_of "$HOME17C" "$SID17C")"
plant_patrol_job_dated "$TR17C" "toolu_1" "abc12345" 10000
dp_user "$TR17C" 2000 "bionic-patrol session=${SID17C} — patrol tick"
dp_assistant "$TR17C" 1990
dp_assistant "$TR17C" 30
plant_patrol_stamp "$REPO17C" "$SID17C"
dp_backdate "$REPO17C/.bionic/tmp/patrol-$SID17C.state" 1900

OUT17C="$(run_doctor "$HOME17C" "$REPO17C")"
PB17C="$(patrol_block "$OUT17C")"

expect_match "83: a marker turn its tick stamped after, then busy work — the row prints" \
  "*✓ session ${SHORT17C}*" "$PB17C"
expect_no_match "84: …and no fix line" \
  "*session ${SHORT17C}: the Patrol is armed but not firing*" "$OUT17C"

# THE PAIRED ROW: the old fixture, kept — a marker turn 60s ago over a three-hour-old stamp,
# and no tick after it. A clock that fires without ticking is not a running Patrol (AC-6.3).
SID17E="17eeeeee-1111-2222-3333-444455556666"
SHORT17E="${SID17E%%-*}"
spawn_live_pid; PID17E="$LIVE_PID"
REPO17E="$(make_repo_with_roster "$SID17E" beta -- alpha)"
dp_pin_interval "$REPO17E"
HOME17E="$(make_claude_home "$SID17E" "$PID17E" "$REPO17E")"
TR17E="$(transcript_of "$HOME17E" "$SID17E")"
plant_patrol_job_dated "$TR17E" "toolu_1" "abc12345" 10000
dp_user "$TR17E" 60 "bionic-patrol session=${SID17E} — patrol tick"
dp_assistant "$TR17E" 30
plant_patrol_stamp "$REPO17E" "$SID17E" 3

OUT17E="$(run_doctor "$HOME17E" "$REPO17E")"
expect_match "84b: AC-6.3 a marker turn after a stale stamp, with no tick, is armed but not firing" \
  "*session ${SHORT17E}: the Patrol is armed but not firing*" "$OUT17E"

# ---------- idle time that cannot be read is an advisory, with the reason ----------
#
# THE PAGE SAYS WHAT IT COULD NOT OBSERVE (ADR-028, one layer up from the walls). A stale
# stamp whose transcript cannot be dated is neither a running Patrol nor a stopped one:
# doctor prints the NIL glyph, names the reason the library gave, and raises NO fix line —
# an accusation doctor cannot support is the very defect this requirement removes. The
# fixture is the undated one every section above this wave used.
SID17D="17dddddd-1111-2222-3333-444455556666"
SHORT17D="${SID17D%%-*}"
spawn_live_pid; PID17D="$LIVE_PID"
REPO17D="$(make_repo_with_roster "$SID17D" beta -- alpha)"
dp_pin_interval "$REPO17D"
HOME17D="$(make_claude_home "$SID17D" "$PID17D" "$REPO17D")"
TR17D="$(transcript_of "$HOME17D" "$SID17D")"
plant_patrol_job "$TR17D" "toolu_1" "abc12345"
plant_patrol_stamp "$REPO17D" "$SID17D" 3

OUT17D="$(run_doctor "$HOME17D" "$REPO17D")"
PB17D="$(patrol_block "$OUT17D")"

expect_match "85: a stale stamp over an undatable transcript is reported, not graded" \
  "*session ${SHORT17D} · the Patrol cannot be graded*" "$PB17D"
# THE REASON AS FAR AS THE ROW HAS ROOM FOR IT. The library's sentence here is "a record in
# the scanned window carries no readable timestamp" — 59 columns against the 52 this row's
# fixed part leaves — so what the page carries is its head plus the product's own ellipsis.
# Matched on the head rather than the tail on purpose: the tail is what the budget cuts, and
# an assertion against it would be an assertion against the cut.
expect_match "86: …naming the reason the library gave, as far as the row has room for it" \
  "*a record in the scanned window*" "$PB17D"
expect_match "87: …and the cut is the product's, visible rather than silent" \
  "*…*" "$PB17D"
expect_no_match "88: …and it is never the not-firing accusation" \
  "*session ${SHORT17D}: the Patrol is armed but not firing*" "$OUT17D"
expect_no_match "89: …nor a running row" "*✓ session ${SHORT17D}*" "$PB17D"

# THE BUDGET, WITH THE PRODUCT'S OWN RULER (Section 9's, reused): the advisory carries a
# library reason that can run long, so the row is the one new line on this page that has to
# be cut to fit.
WIDE17="$(first_over_budget "${PB17A}
${PB17B}
${PB17C}
${PB17D}")"
if [ -z "$WIDE17" ]; then
  ok "90: every row of the four verdict fixtures fits the ${BIONIC_LINE_WIDTH}-column budget"
else
  no "90: a verdict row exceeds the ${BIONIC_LINE_WIDTH}-column budget" \
     "$(bionic_cols "$WIDE17") columns: ${WIDE17}"
fi

finish
