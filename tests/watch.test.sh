#!/bin/bash
# Tests for the watcher's pass: `session-poker.sh tick --watch`, one pass of the tick with no model.
#
# THE PASS'S CONTRACT. It runs the tick once, refreshes the stamp as every tick does, and then says one of two
# things by its exit code: quiet (nothing in the tick's print asks for an act) or wake (an act is owed), in which
# case its stdout is exactly one line of at most 120 characters, worded as the instruction the model acts on. The
# codes, the line's ceiling and the watch interval's bounds are named once, in payload/scripts/lib/patrol.sh, and
# this suite reads them from there rather than typing them.
#
# FIXTURE FIDELITY. Every world is built with the session-poker suite's own builders (tests/session-poker.prelude.sh):
# a real repository, the roster in the dispatch wall's row shape, plans the tick's scheduler reads, the panel and
# the completion message from the committed live-answer corpus, and a gate request in the gate store's own line
# shape. The pass is the shipped hooks/session-poker.sh, never a copy.
#
# ANTI-VACUITY. Every quiet pass's empty stdout sits beside a wake on the same extractor in the same world, and
# every "tick ran" claim reads the stamp the tick rewrote and the digest it left.
#
# Usage: bash tests/watch.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"

POKER="${W2_POKER_UNDER_TEST:-${BIONIC_HOOKS_DIR}/session-poker.sh}"
. "$(dirname "$0")/session-poker.prelude.sh"

WP_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"
# THE NAMES, FROM THEIR ONE HOME. A suite that typed 2 and 120 would pass against a library that had moved them.
wp_const() { bash -c '. "$1/patrol.sh" >/dev/null 2>&1 && eval "printf %s \"\${$2:-}\""' _ "$WP_LIB" "$1"; }
WP_QUIET="$(wp_const WATCH_RC_QUIET)"; WP_WAKE="$(wp_const WATCH_RC_WAKE)"; WP_REST="$(wp_const WATCH_RC_REST)"
WP_MAX="$(wp_const WATCH_LINE_MAX)"; WP_IV_DEF="$(wp_const WATCH_INTERVAL_DEFAULT)"; WP_IV_MAX="$(wp_const WATCH_INTERVAL_MAX)"

# wp_pass <repo> -> WP_OUT (stdout), WP_ERR (stderr), WP_RC: one pass, under the poke watchdog's bound.
wp_pass() {
  local repo="$1" p i=0
  [ "${POKE_UNBOUND:-0}" = 1 ] || poke_bind "$repo"
  ( cd "$repo" && exec env CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" tick --watch ) \
    > "$TMPROOT/wp.out" 2> "$TMPROOT/wp.err" &
  p=$!
  while kill -0 "$p" 2>/dev/null && [ "$i" -lt $(( POKE_BOUND * 10 )) ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$p" 2>/dev/null; then kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null; WP_RC=124
  else wait "$p" 2>/dev/null; WP_RC=$?; fi
  WP_OUT="$(cat "$TMPROOT/wp.out")"; WP_ERR="$(cat "$TMPROOT/wp.err")"
}
# wp_old_stamp <repo> -> the stamp is a year-2000 arm stamp, so a pass that rewrites it is seen to.
wp_old_stamp() { printf 'patrol-stamp/v1|at=2000-01-01T00:00:00Z|session=%s|verb=arm\n' "$SID" > "$(stamp_of "$1")"; }
wp_stamp_at() { sed -n 's/^.*|at=\([^|]*\)|.*$/\1/p' "$(stamp_of "$1")" 2>/dev/null | head -1; }
wp_stamp_verb() { sed -n 's/^.*|verb=\([^|]*\).*$/\1/p' "$(stamp_of "$1")" 2>/dev/null | head -1; }
wp_lines() { [ -n "$1" ] || { printf '0'; return; }; printf '%s\n' "$1" | awk 'END { print NR }'; }
wp_bare() { printf '%s\n' "$1" | grep -c '^[0-9][0-9]*$' | tr -d ' '; }
wp_len() { printf '%s' "$1" | LC_ALL=C awk '{ n += length($0) } END { print n + 0 }'; }
wp_owed() {  # <repo> <fn> [args] -> the person's ledger, read through lib/owed.sh
  local repo="$1"; shift
  ( cd "$repo" && CLAUDE_CODE_SESSION_ID="$SID" bash -c '. "$1/owed.sh" && shift && "$@"' _ "$WP_LIB" "$@" ) 2>/dev/null
}
gate_of() { printf '%s/.bionic/tmp/gate-%s.state' "$1" "$SID"; }
gate_line() {  # <asker> <category> <head>
  printf 'gate/v1|at=2026-10-11T00:00:00Z|session=%s|asker=%s|category=%s|head=%s\n' "$SID" "$1" "$2" "$3"
}

WP_CFG="$(fake_config_dir wp-config)"
mkdir -p "$WP_CFG/bionic"; printf '80\n' > "$WP_CFG/bionic/share"
export CLAUDE_CONFIG_DIR="$WP_CFG"
WP_TR="$WP_CFG/projects/-fixture-project/$SID.jsonl"

# THE QUIET WORLD: armed, one open row inside its duration and on the panel, no plan, nothing ready.
wp_quiet_world() {  # <label> -> repo
  local r; r="$(make_repo "$1")"; new_roster "$r"; armed_ago "$r"
  add_row "$r" name=busy deliverable="$r/never-written.md" duration="4 hours" launched_at="$(iso_ago 60)"
  printf '%s' "$r"
}

expect_eq "precondition: the library names the wake code" "2" "$WP_WAKE"
expect_regex "precondition: …and the line's ceiling, the default interval and the ceiling on it" \
  '^[0-9]+ [0-9]+ [0-9]+ [0-9]+ [0-9]+$' "$WP_QUIET $WP_REST $WP_MAX $WP_IV_DEF $WP_IV_MAX"

# ============================================================
section "§QUIET: three passes over an unchanged run exit quiet, and each moves the stamp (AC-9.1, the hermetic half)"
# ============================================================
plant_answer "$WP_TR" fresh "busy:running"
RQ="$(wp_quiet_world wp-quiet)"
for n in 1 2 3; do
  wp_old_stamp "$RQ"
  wp_pass "$RQ"
  expect_eq "Q$n pass $n exits quiet" "$WP_QUIET" "$WP_RC"
  expect_eq "Q$n.a …prints nothing on stdout" "" "$WP_OUT"
  expect_regex "Q$n.b …and the stamp moved off the planted one to a fresh tick stamp" "^20[0-9][0-9]-.*\|tick$" \
    "$(wp_stamp_at "$RQ")|$(wp_stamp_verb "$RQ")"
  expect_ne "Q$n.c …not the planted instant" "2000-01-01T00:00:00Z" "$(wp_stamp_at "$RQ")"
done
expect_contains "Q4 the tick behind the passes left its digest: the second and third passes read an unchanged run" \
  "decision=QUIET" "$(cat "$(digest_of "$RQ")" 2>/dev/null)"
# THE POSITIVE ON THE SAME EXTRACTOR: the same world, one fact moved, and the pass wakes.
gate_line w99-T9 leaves-the-machine "git push origin wave/99-q" >> "$(gate_of "$RQ")"
wp_pass "$RQ"
expect_eq "Q5 the same world with a request denied: the pass wakes" "$WP_WAKE" "$WP_RC"
expect_nonempty "Q5.a …and stdout carries its line" "$WP_OUT"

# ============================================================
section "§WAKE: a ready row with room, an agent that reported and an agent quiet past its cadence each wake (AC-9.2)"
# ============================================================
# A READY ROW WITH ROOM. T1 landed, T3 ready on it, writers=8 and an empty roster: the tick fills T3.
RF="$(make_repo wp-fill)"; new_roster "$RF"; armed_ago "$RF"
sp_plan_at_step "$RF" 4 \
  "| T1 | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T3 | 4 | build | ordinary, ready | implementor | T1 | 15m | REQ-x | c.sh | pending |" > /dev/null
wp_pass "$RF"
WK_FILL="$WP_OUT"
expect_eq "W1 a ready row with room: the pass exits with the wake code" "$WP_WAKE" "$WP_RC"
expect_contains "W1.a …its line names the row" "T3" "$WK_FILL"
expect_contains "W1.b …and the act, as an instruction" "dispatch" "$WK_FILL"
wp_pass "$RF"
expect_eq "W1.c the next pass over the same fill is quiet: the wake was told once" "$WP_QUIET" "$WP_RC"
expect_eq "W1.d …with nothing on stdout" "" "$WP_OUT"

# AN AGENT THAT REPORTED. w-1's deliverable landed, its Done marker is written and its completion message is in the
# transcript, and it is still on the panel: the tick stands it down.
wk_msg() {
  jq -nc --arg b "<teammate-message teammate_id=\"$1\" color=\"blue\" summary=\"r\">
report
</teammate-message>" '{type:"user",timestamp:"2026-09-05T00:50:10.000Z",message:{role:"user",content:$b}}'
}
RS="$(make_repo wp-reported)"; new_roster "$RS"; armed_ago "$RS"
WK_PLAN="$(wave_plan_at "$RS" "epic-99-fixture/wave-41.plan.md" \
  "writers=1 suites=2 worktrees=8 test_jobs=8 source=user" \
  "| R1 | 4 | build | ready row | implementor | — | 15m | REQ-x | r1.sh | pending |")"
bind_marker "$RS" "$WK_PLAN"
echo "done" > "$RS/w1-report.md"; backdate "$RS/w1-report.md" 300
add_row "$RS" name=w-1 agent_id=aw1-41414141414141 deliverable="$RS/w1-report.md" \
  duration="4 hours" launched_at="$(iso_ago 600)" "$(said "$RS" w-1)"
plant_answer "$TMPROOT/wk.panel" fresh "w-1:idle"
{ head -1 "$TMPROOT/wk.panel"; wk_msg w-1; tail -n +2 "$TMPROOT/wk.panel"; } > "$WP_TR"
wp_pass "$RS"
WK_SD="$WP_OUT"
expect_eq "W2 an agent that reported and is still on the panel: the pass wakes" "$WP_WAKE" "$WP_RC"
expect_contains "W2.a …its line names the agent" "w-1" "$WK_SD"
expect_contains "W2.b …and the act" "TaskStop" "$WK_SD"

# AN AGENT QUIET PAST ITS CADENCE. T1 active, w1's progress file ten cadences old, no carrier and no request.
RN="$(make_repo wp-cadence)"; new_roster "$RN"; armed_ago "$RN"
wave_plan_at "$RN" 'epic-99-fixture/wave-01-fixture.plan.md' "-" \
  "| T1 | 4 | build | the writer's row | implementor | — | 60 | REQ-x | a.sh | active |" > /dev/null
printf 'working\n' > "$RN/progress-w1.md"; backdate "$RN/progress-w1.md" 3000
add_row "$RN" name=w1 agent_id=aquiet-one-bbbbbbbbbbbbbbbb deliverable="$RN/absent-w1.md" \
  duration="4 hours" launched_at="$(iso_ago 3600)" progress="$RN/progress-w1.md" cadence="5 minutes"
plant_answer "$WP_TR" fresh "w1:running"
wp_pass "$RN"
WK_NT="$WP_OUT"
expect_eq "W3 an agent quiet past its cadence: the pass wakes" "$WP_WAKE" "$WP_RC"
expect_contains "W3.a …its line names the agent" "w1" "$WK_NT"
expect_contains "W3.b …says why" "cadence" "$WK_NT"
expect_contains "W3.c …and the act" "ListAgents" "$WK_NT"

# THE INTERVAL. Five minutes by default, twenty at most; one above twenty is refused and never taken.
RI="$(wp_quiet_world wp-interval)"
plant_answer "$WP_TR" fresh "busy:running"
poke "$RI" interval --watch
expect_eq "W4 no watch-interval configured: the watch interval is the default" "0|$WP_IV_DEF" "$RC|$OUT"
printf 'watch-interval: 20m\n' > "$RI/.bionic/config.yaml"
poke "$RI" interval --watch
expect_eq "W4.a twenty minutes is taken" "0|1200" "$RC|$OUT"
expect_eq "W4.a2 …printed as the one bare number the watch takes" "1" "$(wp_bare "$OUT")"
printf 'watch-interval: 21m\n' > "$RI/.bionic/config.yaml"
poke "$RI" interval --watch
expect_eq "W4.b twenty-one minutes is refused (exit 2)" "2" "$RC"
expect_eq "W4.c …and no period is printed for the watch to take: no line of it is a bare number" "0" "$(wp_bare "$OUT")"
expect_contains "W4.d …the refusal names the ceiling" "20m" "$OUT"
printf 'watch-interval: soon\n' > "$RI/.bionic/config.yaml"
poke "$RI" interval --watch
expect_eq "W4.e a malformed interval is refused (exit 2)" "2" "$RC"
poke "$RI" interval
expect_eq "W4.f the Patrol's own interval is untouched by the watch key" "0|1200" "$RC|$OUT"
rm -f "$RI/.bionic/config.yaml"
wp_pass "$RI"; wp_pass "$RI"
expect_eq "W5 precondition: the quiet world, settled, is quiet with no interval set" "$WP_QUIET|" "$WP_RC|$WP_OUT"
printf 'watch-interval: 30m\n' > "$RI/.bionic/config.yaml"
wp_pass "$RI"
WK_IV="$WP_OUT"
expect_eq "W5.a the same world with watch-interval: 30m wakes rather than taking it" "$WP_WAKE" "$WP_RC"
expect_contains "W5.b …its line names the key" "watch-interval" "$WK_IV"
expect_contains "W5.c …and the ceiling to set it under" "20m" "$WK_IV"
rm -f "$RI/.bionic/config.yaml"

# ============================================================
section "§PROMPT: the wake text over each wake fixture is one line of at most 120 characters (AC-9.3)"
# ============================================================
for wk in FILL SD NT IV; do
  eval "wk_text=\"\$WK_$wk\""
  expect_nonempty "P-$wk precondition: the $wk fixture woke with text" "$wk_text"
  expect_eq "P-$wk.a …one line" "1" "$(wp_lines "$wk_text")"
  expect_true "P-$wk.b …of at most $WP_MAX characters ($(wp_len "$wk_text")): $wk_text" \
    test "$(wp_len "$wk_text")" -le "$WP_MAX"
done
# THE COMPOSER, ON ITS OWN. A print holding every woken kind, a 200-character agent name and a multibyte one: still
# one line, inside the ceiling, plain ASCII, the person's act first.
wp_line() { bash -c '. "$1/patrol.sh" >/dev/null 2>&1 && watch_wake_line "$2"' _ "$WP_LIB" "$1"; }
WP_LONG="$(printf 'agent-%.0s' $(seq 1 34))"
cat > "$TMPROOT/all.print" <<EOF
poker: gate share=80 room=6.4
poker: FILL T3 T4 T5
poker: STANDDOWN $WP_LONG — contract MET and the agent is still on the panel; TaskStop it
poker: NOTIFY — quieter than the declared cadence: wé1: no line for 50m
poker: GATE w99-T1 — leaves-the-machine: git push origin wave/99-fx
poker: RECONCILE — a ## Tasks status or the ready set changed since the last tick: TaskList
poker: NOT-LANDED T2 — the orchestrator's integrate row waits: refused
poker-tick/v1|at=2026-11-18T00:00:00Z|session=$SID|decision=NOTIFY|total=2|open=2|rows=wé1|fill=T3,T4,T5|gate=1:leaves-the-machine
EOF
WP_ALL="$(wp_line "$TMPROOT/all.print")"
expect_nonempty "P1 precondition: a print holding every kind composes a line" "$WP_ALL"
expect_eq "P1.a …one line" "1" "$(wp_lines "$WP_ALL")"
expect_true "P1.b …inside the ceiling ($(wp_len "$WP_ALL")): $WP_ALL" test "$(wp_len "$WP_ALL")" -le "$WP_MAX"
expect_eq "P1.c …plain printable ASCII" "" "$(printf '%s' "$WP_ALL" | LC_ALL=C tr -d '\040-\176')"
expect_regex "P1.d …the person's act first: the gate" '^bionic watch: GATE ' "$WP_ALL"
expect_contains "P1.e …and the other kinds named after it" "also" "$WP_ALL"
# THE NEGATIVES, EACH BESIDE P1 ON THE SAME EXTRACTOR: an unchanged print, even one re-printing a standing hold,
# and a print of advice alone, compose nothing.
printf 'poker: NOT-LANDED T2 — waits\npoker: unchanged since 2026-11-18T00:00:00Z — decision=QUIET\n' > "$TMPROOT/unch.print"
expect_eq "P2 an unchanged print composes no line" "" "$(wp_line "$TMPROOT/unch.print")"
printf '%s\n' 'poker: HELD T2 ext:ci' 'poker: LEDGER T4 no-launch' 'poker: WAITING — 1 running, nothing ready' \
  'poker: QUIET — 1 open row(s) on this roster' 'poker: no FILL — width=8 occupied=1 gap=7, and no pending task is ready.' \
  > "$TMPROOT/advice.print"
expect_eq "P3 a print of advice and quiet lines composes no line" "" "$(wp_line "$TMPROOT/advice.print")"

# ============================================================
section "§GATE: a denied reserved request wakes the pass with the gate act, and its ask is open on the register (AC-12.3)"
# ============================================================
plant_answer "$WP_TR" fresh "busy:running"
RG="$(wp_quiet_world wp-gate)"
wp_pass "$RG"; wp_pass "$RG"
expect_eq "G0 precondition: the world is quiet before the request" "$WP_QUIET" "$WP_RC"
gate_line w99-T1 leaves-the-machine "git push origin wave/99-fx" >> "$(gate_of "$RG")"
wp_pass "$RG"
WK_GATE="$WP_OUT"
expect_eq "G1 a denied reserved request: the pass exits with the wake code" "$WP_WAKE" "$WP_RC"
expect_regex "G1.a …its line is the gate act, naming the category" '^bionic watch: GATE leaves-the-machine' "$WK_GATE"
expect_contains "G1.b …and that it goes to the person" "person" "$WK_GATE"
expect_eq "G1.c …one line" "1" "$(wp_lines "$WK_GATE")"
expect_true "G1.d …of at most $WP_MAX characters ($(wp_len "$WK_GATE"))" test "$(wp_len "$WK_GATE")" -le "$WP_MAX"
expect_contains "G2 …and the request's ask is open on the person's register" "gate:" "$(wp_owed "$RG" owed_list | cut -f1)"
wp_pass "$RG"
expect_eq "G3 the next pass does not wake for the same request again" "$WP_QUIET" "$WP_RC"
expect_eq "G3.a …and prints nothing" "" "$WP_OUT"
expect_contains "G3.b …while the ask stays open" "gate:" "$(wp_owed "$RG" owed_list | cut -f1)"

# THE PERSON'S WORLD: armed, an empty roster, the session bound to a plan at Step 3, so no row is ready, no run is
# delivered and the run's log holds no pull request. Sets WP_R and WP_PLAN (not a subshell, so both survive).
wp_person_world() {  # <label>
  WP_R="$(make_repo "$1")"; new_roster "$WP_R"; armed_ago "$WP_R"
  WP_PLAN="$(sp_plan_at_step "$WP_R" 3 "| T1 | 4 | build | a row | implementor | — | 15m | REQ-x | a.sh | pending |")"
  bind_marker "$WP_R" "$WP_PLAN"
}
wp_ask() {  # <repo> <plan> <owed.sh fn> [args] -> an act on the run's own register, as the card and the verbs write it
  local repo="$1" plan="$2"; shift 2
  ( cd "$repo" && CLAUDE_CODE_SESSION_ID="$SID" OWED_ROOT="$repo" OWED_PLAN="$plan" \
      bash -c '. "$1/owed.sh" && shift && "$@"' _ "$WP_LIB" "$@" ) >/dev/null 2>&1
}
# wp_why <repo> -> the fact the tick says keeps the run off the rest, or `rest`: one plain tick, its watch facts read
wp_why() {
  rm -f "$TMPROOT/wp.facts"
  ( cd "$1" && exec env CLAUDE_CODE_SESSION_ID="$SID" BIONIC_WATCH_FACTS="$TMPROOT/wp.facts" bash "$POKER" tick ) \
    >/dev/null 2>&1
  sed -n 's/^watch-facts\/v[0-9]*|.*rest=\([a-z]*\).*$/\1/p' "$TMPROOT/wp.facts" 2>/dev/null | head -1 | grep -q '^yes$' \
    && { printf 'rest'; return; }
  sed -n 's/^.*|why=\([^|]*\).*$/\1/p' "$TMPROOT/wp.facts" 2>/dev/null | head -1
}
WP_SH="$(printf 'b%.0s' $(seq 40))"
wp_pr_line() { printf 'run/v1|ev=published|part=pr|url=https://host.invalid/o/r/pull/7|branch=wave/01-fixture|commit=%s|base=main|at=2026-11-18T00:00:00Z\n' "$WP_SH"; }

# ============================================================
section "§ONLY-PERSON: with no row, nothing ready, no run, no pull request and every open ask the person's, the pass returns the rest code (AC-10.1, the hermetic half)"
# ============================================================
wp_person_world wp-person
RP="$WP_R"; PP="$WP_PLAN"
wp_pass "$RP"
expect_eq "OP0 the person's world with no ask open is quiet, not a rest: nothing has put anything to the person" \
  "$WP_QUIET|" "$WP_RC|$WP_OUT"
expect_eq "OP0.a …and the tick's facts name that" "no-ask" "$(wp_why "$RP")"
wp_ask "$RP" "$PP" owed_open approve:step3 "approval: step3" "the plan is put to you"
wp_old_stamp "$RP"
wp_pass "$RP"
expect_eq "OP1 the plan's approval put to the person and nothing else open: the pass exits with the rest code" "$WP_REST" "$WP_RC"
expect_eq "OP1.a …and prints nothing on stdout" "" "$WP_OUT"
expect_ne "OP1.b …the tick ran behind it: the stamp moved off the planted one" "2000-01-01T00:00:00Z" "$(wp_stamp_at "$RP")"
wp_pass "$RP"
expect_eq "OP2 the next pass over the same resting state, its print unchanged, rests again" "$WP_REST|" "$WP_RC|$WP_OUT"
expect_eq "OP2.a …and the tick's facts say rest" "rest" "$(wp_why "$RP")"
# AN ASK THAT WAITS ON AN EVENT IS NOT THE PERSON'S: the waiver answered no waits on its review's next run.
wp_ask "$RP" "$PP" owed_open waive:Q1 "waiver: Q1" "review Q1 is waived"
wp_ask "$RP" "$PP" owed_answer waive:Q1 no
wp_pass "$RP"
expect_ne "OP3 one ask more, answered so it waits on its review's run: the pass does not rest" "$WP_REST" "$WP_RC"
expect_eq "OP3.a …the tick's facts name the ask on an event" "ask-on-event" "$(wp_why "$RP")"
wp_ask "$RP" "$PP" owed_close waive:Q1 "the review passed"
wp_pass "$RP"
expect_eq "OP3.b …and with that ask closed the same world rests again" "$WP_REST" "$WP_RC"
# AN OPEN PULL REQUEST IS NOT WAITING ONLY ON THE PERSON (D27): the run's log holds the published request.
wp_pr_line >> "$(plan_fixture_log "$PP")"
wp_pass "$RP"
expect_ne "OP4 the same world with its pull request published: the pass does not rest" "$WP_REST" "$WP_RC"
expect_eq "OP4.a …the tick's facts name the pull request" "pull-request" "$(wp_why "$RP")"

# THE PLAN THAT CANNOT BE READ IS A WAKE, NOT A REST: only the person can restore it, and nothing has told them.
wp_person_world wp-unread
RU="$WP_R"; PU="$WP_PLAN"
wp_ask "$RU" "$PU" owed_open approve:step3 "approval: step3" "the plan is put to you"
wp_pass "$RU"
expect_eq "OP5 precondition: the readable world with the approval put rests" "$WP_REST" "$WP_RC"
chmod 000 "$PU"
wp_pass "$RU"
WK_PU="$WP_OUT"
expect_eq "OP6 the bound plan made unreadable: the pass wakes" "$WP_WAKE" "$WP_RC"
expect_regex "OP6.a …its line names the plan and the person" '^bionic watch: PLAN unreadable - .*person' "$WK_PU"
expect_eq "OP6.b …one line" "1" "$(wp_lines "$WK_PU")"
expect_true "OP6.c …of at most $WP_MAX characters ($(wp_len "$WK_PU"))" test "$(wp_len "$WK_PU")" -le "$WP_MAX"
wp_pass "$RU"
expect_eq "OP7 the next pass over the same unreadable plan neither wakes again nor rests" "$WP_QUIET|" "$WP_RC|$WP_OUT"
expect_eq "OP7.a …the tick's facts name the plan" "plan-unreadable" "$(wp_why "$RU")"
chmod 644 "$PU"

# ============================================================
section "§STAYS: an active row with nothing changing, and no row but a detached run, never rest (AC-10.4, the pass's half)"
# ============================================================
# ONE ACTIVE ROW: the person's resting world with one agent at work inside its duration and cadence.
wp_person_world wp-stays-row
RA="$WP_R"
wp_ask "$RA" "$WP_PLAN" owed_open approve:step3 "approval: step3" "the plan is put to you"
wp_pass "$RA"
expect_eq "ST0 precondition: the world with no row rests" "$WP_REST" "$WP_RC"
add_row "$RA" name=busy deliverable="$RA/never-written.md" duration="4 hours" launched_at="$(iso_ago 60)"
plant_answer "$WP_TR" fresh "busy:running"
WP_ST=""
for n in 1 2 3 4 5 6 7 8 9 10; do wp_pass "$RA"; WP_ST="$WP_ST$WP_RC "; done
expect_eq "ST1 one active row and nothing changing: ten passes, none rests and none wakes after the first" \
  "$(printf '%s ' $WP_QUIET $WP_QUIET $WP_QUIET $WP_QUIET $WP_QUIET $WP_QUIET $WP_QUIET $WP_QUIET $WP_QUIET)" \
  "${WP_ST#* }"
expect_ne "ST1.a …nor the first" "$WP_REST" "${WP_ST%% *}"
expect_eq "ST1.b …the tick's facts name the open row" "open-row" "$(wp_why "$RA")"

# NO ROW BUT A DETACHED RUN: a whole run the tick started, alive under booked.sh's shim, its row a run object.
wp_person_world wp-stays-run
RD="$WP_R"
wp_ask "$RD" "$WP_PLAN" owed_open approve:step3 "approval: step3" "the plan is put to you"
mkdir -p "$TMPROOT/shim" "$RD/.bionic/tmp/runs"
WP_RUNLOG="$RD/.bionic/tmp/runs/regression@bbbbbbbb.log"; : > "$WP_RUNLOG"
printf 'sleep 600\n' > "$TMPROOT/shim/booked.sh"
bash "$TMPROOT/shim/booked.sh" --run-log "$WP_RUNLOG" >/dev/null 2>&1 &
WP_RUNPID=$!
roster_row_fixture status=run session="$SID" name=regression@bbbbbbbb agent_id= launched_at="$(iso_ago 60)" \
  subagent_type=bionic:test-runner model= waiver="a whole run the tick started, not an agent: its log and its proof are its record" \
  suites_allowed=run.sh suites_source=DECLARED tool_use_id= plan="$WP_PLAN" \
  run_log="$WP_RUNLOG" run_pid="$WP_RUNPID" run_started_at="$(iso_ago 60)" >> "$(roster_of "$RD")"
WP_ST=""
for n in 1 2 3 4 5 6 7 8 9 10; do wp_pass "$RD"; WP_ST="$WP_ST$WP_RC "; done
expect_eq "ST2 no row but a live detached run: ten passes, none rests" "" \
  "$(printf '%s\n' $WP_ST | grep -x "$WP_REST")"
expect_eq "ST2.a …each pass ran: ten codes read" "10" "$(printf '%s\n' $WP_ST | grep -c .)"
expect_eq "ST2.b …the tick's facts name the detached run" "detached-run" "$(wp_why "$RD")"
kill "$WP_RUNPID" 2>/dev/null; wait "$WP_RUNPID" 2>/dev/null
printf '0\n' > "$WP_RUNLOG.rc"
wp_pass "$RD"
expect_eq "ST3 …and once the run has ended the same world rests" "$WP_REST" "$WP_RC"

# ============================================================
finish
