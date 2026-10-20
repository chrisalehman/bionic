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

# ---------- the tool directory: the fixture's, not the machine's ----------

# A WHOLE RUN USED TO SHELL OUT TO WHATEVER THIS MACHINE HAD INSTALLED. Doctor asks `claude plugin list`,
# `claude mcp get`, `npm list -g`, `pnpm store path`, `uv --version` and `notebooklm --version`, and every
# launch here inherited the runner's PATH, so each of them ran the real tool (a traced whole run on a laptop
# that has all six reached ten of those calls and took 13 s; under the directory below, 5 s). A hermetic
# suite must not read the machine it runs on: what the page prints would then depend on what the developer
# has installed, and each launch pays for those tools' start-up. The two sister suites (doctor-version,
# doctor-reads) already launch the doctor on a PATH replaced by a fixture directory; this is the same.
#
# WHAT IS IN IT. Only programs doctor itself RUNS (and the ones this suite's fixtures rely on under it),
# symlinked from the real ones, the list the sister suites carry. NOTHING doctor only ASKS ABOUT is in it:
# not `claude`, `npm`, `brew`, `notebooklm`, `pnpm`, `uv`, and no stub for them either. Every one is simply
# absent, which is a state doctor renders (a missing dependency, "claude CLI is not on PATH"), and which no
# row below reads except T37. PATH is REPLACED, never prepended: a prefixed PATH still finds the real tools
# for anything the directory lacks.
_TOOLS_REAL="bash sh env cat grep sed awk mkdir rm cp mv chmod stat readlink ls tr head tail
sort uniq wc cut jq mktemp find xargs shasum uname date touch diff cmp printf true false
sleep dirname basename realpath id ps df sysctl vm_stat git strings"
_HOST_TOOLS="claude npm brew notebooklm pnpm uv"

BIN="${TMP}/toolbox"
_TOOLS_MISSING=""
mkdir -p "$BIN"
for _t in $_TOOLS_REAL; do
  if _p="$(command -v "$_t" 2>/dev/null)"; then ln -sf "$_p" "${BIN}/${_t}"
  else _TOOLS_MISSING="${_TOOLS_MISSING}${_TOOLS_MISSING:+ }${_t}"; fi
done

# THE SHELL RC AND HOME ARE FIXTURES, NOT THE MACHINE'S. PATH is already the tool directory; HOME and the rc
# were still the host's, so the page printed host-derived lines (the shell proxy row, the renderer and browser
# rows) that no row here reads. An empty rc, as the sister suites carry.
FIXTURE_RC="${TMP}/dot.zshrc"
: > "$FIXTURE_RC"

# ---------- driving doctor ----------

# THE PROBE BOUND IS 15 SECONDS, THE DOCTOR'S OWN DEFAULT, ON EVERY LAUNCH. It was 3, and no row here is
# about a probe that hangs: `_patrol_scan` (lib/patrol.sh) runs its jq over the session's transcript under
# `detect_bounded` at this bound, and a scan cut short returns nothing, so the session has no Patrol job and
# the page drops it whole. On a busy machine a jq that took over 3 s therefore decided a row about idle time
# (row 81 went red once under load, 82 stayed green). A fixture's bound must not decide a row that is not
# about the bound, and `detect_bounded` returns within a tenth of a second of the probe ending, so a
# generous bound costs a fast probe nothing.
#
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
  ( cd "$2" && HOME="$TMP" PATH="$BIN" BIONIC_SHELL_RC="$FIXTURE_RC" \
      BIONIC_CLAUDE_HOME="$1" BIONIC_PLUGIN_ROOT="$PAYLOAD" BIONIC_DOCTOR_PROBE_SECONDS=15 \
      bash "$DOCTOR_SH" < /dev/null 2>&1 )
}

# The PATROL section alone — from its bare header to end of output, which is
# where the default (no --updates) run ends.
patrol_block() {  # <full-output>
  printf '%s\n' "$1" | awk '/^PATROL$/{f=1} f'
}

# THE FILTERED RUN (BIONIC_DOCTOR_ONLY, doctor.sh's test seam). Same fixture, same environment, but the
# doctor gathers and prints only the sections this suite reads: the "→" fix lines the Patrol and project
# gathers raise, PATROL, and PROJECT. It skips the dependency sweep and the CLI's plugin listing, which
# are most of a whole run (measured at about 7 s of 12) and read nothing from the project.
#
# A ROW MAY USE IT ONLY IF every line it asserts on is one of those three. The header verdict and its
# problem count, the three tables, RESOURCES and the "Nothing to do" line are NOT printed by a filtered
# run, so a row on any of them (57-78's count and attestation rows, 67-71) runs the whole doctor. A row
# that asserts a fix line ABSENT may use it only because that line has one producer in doctor.sh, a single
# `fix` call; a line a filtered run could not produce would turn the absence into a pass over air. Section
# 9 below checks the other half: that the filtered page's PATROL..end block is the whole page's.
#
# EVERY SECTION KEEPS A WHOLE RUN, `run_doctor`, because a defect at the doctor's entry point (option
# parsing, the library sourcing, the address resolution) is only seen by a row that executes the real
# page: Sections 1-11 and 16 run it for every fixture; in 12 the first of three, in 13 the first of
# three, in 14 the first of three, in 15 the first of four and in 17 the first of five do, and the rest of
# each use this.
run_doctor_only() {  # <claude-home> <project-cwd>
  ( cd "$2" && HOME="$TMP" PATH="$BIN" BIONIC_SHELL_RC="$FIXTURE_RC" BIONIC_DOCTOR_ONLY="PATROL,PROJECT,FIXES" \
      BIONIC_CLAUDE_HOME="$1" BIONIC_PLUGIN_ROOT="$PAYLOAD" \
      BIONIC_DOCTOR_PROBE_SECONDS=15 bash "$DOCTOR_SH" < /dev/null 2>&1 )
}

section "Section 1: no live Patrol anywhere"

EMPTY_HOME="$(make_empty_claude_home)"
EMPTY_PROJ="$(make_repo_without_roster)"
OUT1="$(run_doctor "$EMPTY_HOME" "$EMPTY_PROJ")"
PB1="$(patrol_block "$OUT1")"

expect_match    "1: the fallback line prints" "*none running*" "$PB1"
expect_no_match "2: no session line prints alongside the fallback" "*session*" "$PB1"

# T37: THE POINT OF THE TOOL DIRECTORY ABOVE. OUT1 is a whole run, so it ran the dependency sweep and the
# CLI's plugin listing, the part that asks the six host tools. It is read for each tool's absence rather than
# its presence: a tool reached through the host's PATH prints as installed (a version, `present`), a tool the
# directory withholds prints as absent or as the PATH cause doctor names. `brew` is asked only by the
# `--updates` page, so it is read from the directory itself, as the sister suites' T0b reads it. The row is
# built so that it cannot pass over air: a directory missing a real program it must carry, or a page with no
# THIRD PARTY table to read, is itself a leak.
_dep_row() {  # <name> <page> — the THIRD PARTY row that names it
  printf '%s\n' "$2" | awk -v n="$1" '$2 == n'
}
_T37_LEAK=""
[ -z "$_TOOLS_MISSING" ] || _T37_LEAK="${_T37_LEAK} missing:${_TOOLS_MISSING// /,}"
[ -e "${BIN}/jq" ] || _T37_LEAK="${_T37_LEAK} no-jq-in-directory"
[[ "$OUT1" == *"THIRD PARTY"* ]] || _T37_LEAK="${_T37_LEAK} no-third-party-table"
for _t in $_HOST_TOOLS; do
  [ -e "${BIN}/${_t}" ] && _T37_LEAK="${_T37_LEAK} ${_t}(in-directory)"
done
[[ "$OUT1" == *"the claude CLI is not on PATH"* ]] || _T37_LEAK="${_T37_LEAK} claude(page)"
[[ "$OUT1" == *"npm is not on PATH"* ]]            || _T37_LEAK="${_T37_LEAK} npm(page)"
for _t in pnpm uv notebooklm; do
  _row="$(_dep_row "$_t" "$OUT1")"
  [[ "$_row" == *"not installed"* ]] || _T37_LEAK="${_T37_LEAK} ${_t}(page: '${_row}')"
done
expect_eq "T37: a whole run reaches none of claude, npm, brew, notebooklm, pnpm, uv outside the tool directory" \
  "" "${_T37_LEAK# }"

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
# (.claude/rules/test-harness.md, "Anti-vacuity") — this is not an empty-fixture
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

# THE FILTER SEAM, KEPT HONEST (BIONIC_DOCTOR_ONLY; see `run_doctor_only` above). The rows that use it
# are only as good as the claim that a filtered page carries the same lines as the whole one, so the
# claim is a row here, on a fixture that has a fix line, a Patrol row and a project section (Section 7's).
# The whole page's PATROL..end block and its launches-unrostered line are the control: each filtered
# assertion below sits beside the same assertion on the whole page.
ONLY7="$(run_doctor_only "$HOME7" "$REPO7")"
expect_nonempty "36b: the filtered run prints a PATROL block (the equality below is not over air)" \
  "$(patrol_block "$ONLY7")"
expect_eq "36c: …and it is the whole page's PATROL..end block, line for line" \
  "$PB7" "$(patrol_block "$ONLY7")"
expect_eq "36d: …and its fix line is the whole page's, line for line" \
  "$(lines_matching "$OUT7" '*launches unrostered*')" "$(lines_matching "$ONLY7" '*launches unrostered*')"
expect_match "36e: the whole page has the tables the filtered page leaves out" "*THIRD PARTY*" "$OUT7"
expect_no_match "36f: …and the filtered page has neither a table nor the header" "*THIRD PARTY*" "$ONLY7"
expect_no_match "36g: …nor the verdict line" "*→ * problem*" "$ONLY7"

# AN UNKNOWN SECTION NAME IS REFUSED BEFORE ANYTHING IS GATHERED: one line on stderr, status 2, nothing
# on stdout. Beside it, the same call with the known names succeeds (36b above), so a refusal that
# fired on every name would not pass.
KNOWN_OUT="$( cd "$EMPTY_PROJ" && PATH="$BIN" BIONIC_DOCTOR_ONLY="PATROL" BIONIC_CLAUDE_HOME="$EMPTY_HOME" \
  BIONIC_PLUGIN_ROOT="$PAYLOAD" bash "$DOCTOR_SH" 2>/dev/null < /dev/null )"
expect_match "36g2: the same call with only a known name prints that section" "*none running*" "$KNOWN_OUT"
UNK_ERR="$( cd "$EMPTY_PROJ" && PATH="$BIN" BIONIC_DOCTOR_ONLY="PATROL,NOPE" BIONIC_CLAUDE_HOME="$EMPTY_HOME" \
  BIONIC_PLUGIN_ROOT="$PAYLOAD" bash "$DOCTOR_SH" 2>&1 >/dev/null < /dev/null )"
UNK_RC=$?
UNK_OUT="$( cd "$EMPTY_PROJ" && PATH="$BIN" BIONIC_DOCTOR_ONLY="PATROL,NOPE" BIONIC_CLAUDE_HOME="$EMPTY_HOME" \
  BIONIC_PLUGIN_ROOT="$PAYLOAD" bash "$DOCTOR_SH" 2>/dev/null < /dev/null )"
expect_eq "36h: an unknown section name exits 2" "2" "$UNK_RC"
expect_match "36i: …with one line on stderr naming the section" "doctor.sh: unknown section 'NOPE'*" "$UNK_ERR"
expect_eq "36j: …exactly one line" "1" "$(printf '%s\n' "$UNK_ERR" | grep -c .)"
expect_eq "36k: …and nothing on stdout" "" "$UNK_OUT"

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
# section naming `b1a850c1` (cwd this checkout) and `6c4fe341` (cwd another project's
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

OUT12B="$(run_doctor_only "$HOME12B" "$REPO12B")"
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

OUT12C="$(run_doctor_only "$HOME12C" "$REPO12C")"
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

finish
