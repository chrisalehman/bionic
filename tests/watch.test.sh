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
# THE HOOK: hooks/watch.sh, the shipped file, run as the platform runs it: the event's JSON on stdin, the session's id
# in that JSON alone (CLAUDE_CODE_SESSION_ID is removed from its environment), the project as its cwd. Each world sets
# `watch-interval: 1s`, so a pass comes as fast as a tick runs. A pass is seen by the stamp it moves: the suite plants
# a year-2000 stamp and waits for the next pass to rewrite it.
# ============================================================
WH_HOOK="${BIONIC_HOOKS_DIR}/watch.sh"
WP_LIFE="$(wp_const WATCH_LIFE_MAX)"
WH_BOUND=60
wh_rec() { printf '%s/.bionic/tmp/watch-%s.state' "$1" "$SID"; }
wh_field() { sed -n "s/^$2=//p" "$(wh_rec "$1")" 2>/dev/null | head -1; }
wh_fast() { printf 'watch-interval: 1s\n' > "$1/.bionic/config.yaml"; }
# wh_start <repo> [event] [env assignment...] -> WH_PID: the hook, started as the platform starts it
wh_start() {
  local repo="$1" ev="${2:-Stop}"; shift 2 2>/dev/null || shift $#
  jq -nc --arg s "$SID" --arg c "$repo" --arg e "$ev" \
    '{session_id:$s,cwd:$c,hook_event_name:$e,stop_hook_active:false} + (if $e == "SessionStart" then {source:"startup"} else {} end)' \
    > "$TMPROOT/wh.in"
  ( cd "$repo" && exec env -u CLAUDE_CODE_SESSION_ID "$@" bash "$WH_HOOK" < "$TMPROOT/wh.in" ) \
    > "$TMPROOT/wh.out" 2> "$TMPROOT/wh.err" &
  WH_PID=$!
}
# wh_wait [seconds] -> WH_RC (124 while it still runs), WH_OUT, WH_ERR
wh_wait() {
  local i=0 n="${1:-$WH_BOUND}"
  while kill -0 "$WH_PID" 2>/dev/null && [ "$i" -lt $(( n * 10 )) ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$WH_PID" 2>/dev/null; then WH_RC=124; else wait "$WH_PID" 2>/dev/null; WH_RC=$?; fi
  WH_OUT="$(cat "$TMPROOT/wh.out")"; WH_ERR="$(cat "$TMPROOT/wh.err")"
}
wh_kill() { kill "$WH_PID" 2>/dev/null; wait "$WH_PID" 2>/dev/null; sleep 1; }
# wh_passes <repo> <n> -> WH_SEEN: how many of <n> planted stamps a pass rewrote while the hook stayed up
wh_passes() {
  local repo="$1" n="$2" k i
  WH_SEEN=0
  for k in $(seq 1 "$n"); do
    wp_old_stamp "$repo"; i=0
    while [ "$(wp_stamp_at "$repo")" = "2000-01-01T00:00:00Z" ] && [ "$i" -lt $(( WH_BOUND * 10 )) ]; do
      sleep 0.1; i=$((i + 1))
    done
    [ "$(wp_stamp_at "$repo")" != "2000-01-01T00:00:00Z" ] && kill -0 "$WH_PID" 2>/dev/null || return 0
    WH_SEEN=$((WH_SEEN + 1))
  done
}

section "§HOOK: the watcher is registered on the turn end and at session start, as a hook that can wake, for one day"
expect_regex "H0 precondition: the library names the watch's day" '^[0-9]+$' "$WP_LIFE"
for ev in Stop SessionStart; do
  WH_REG="$(jq -c --arg e "$ev" '[.hooks[$e][]?.hooks[]? | select(.command | test("/hooks/watch\\.sh$"))]' \
    "${BIONIC_HOOKS_DIR}/hooks.json" 2>/dev/null)"
  expect_eq "H0.$ev hooks.json registers hooks/watch.sh on $ev, once" "1" "$(printf '%s' "$WH_REG" | jq 'length' 2>/dev/null)"
  expect_eq "H0.$ev.a …as a hook that can wake (asyncRewake)" "true" "$(printf '%s' "$WH_REG" | jq -r '.[0].asyncRewake' 2>/dev/null)"
  expect_eq "H0.$ev.b …with the watch's day as its time limit" "$WP_LIFE" "$(printf '%s' "$WH_REG" | jq -r '.[0].timeout' 2>/dev/null)"
done

section "§HOOK-WAKE: a pass that wakes ends the watcher with the wake code and the pass's line on stderr, and nothing else"
RHW="$(make_repo wh-fill)"; new_roster "$RHW"; armed_ago "$RHW"; wh_fast "$RHW"
sp_plan_at_step "$RHW" 4 \
  "| T1 | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T3 | 4 | build | ordinary, ready | implementor | T1 | 15m | REQ-x | c.sh | pending |" > /dev/null
poke_bind "$RHW"
wh_start "$RHW" Stop; wh_wait
expect_eq "HW1 a ready row with room: the hook exits with the wake code" "$WP_WAKE" "$WH_RC"
expect_eq "HW1.a …its stderr is one line" "1" "$(wp_lines "$WH_ERR")"
expect_regex "HW1.b …the pass's own wake line, naming the row and the act" '^bionic watch: FILL T3 - .*dispatch' "$WH_ERR"
expect_eq "HW1.c …and stdout is empty" "" "$WH_OUT"
expect_eq "HW1.d the watch record says resting, because the wake ended it and the turn's end starts the next" \
  "resting|woke" "$(wh_field "$RHW" state)|$(wh_field "$RHW" why)"
wh_start "$RHW" Stop; wh_wait 4
expect_eq "HW2 the next watcher over the same fill does not wake again: it is still watching" "124" "$WH_RC"
expect_eq "HW2.a …and its record names it, watching" "watching|$WH_PID" "$(wh_field "$RHW" state)|$(wh_field "$RHW" pid)"
expect_eq "HW2.b …with nothing said on either stream" "|" "$WH_OUT|$WH_ERR"
wh_kill

section "§HOOK-QUIET: over an unchanged run the watcher passes again and again and says nothing (AC-9.1, the suite's half)"
plant_answer "$WP_TR" fresh "busy:running"
RHQ="$(wp_quiet_world wh-quiet)"; wh_fast "$RHQ"
wh_start "$RHQ" SessionStart
wh_passes "$RHQ" 3
expect_eq "HQ1 three passes, each moving the stamp, while the watcher stays up" "3" "$WH_SEEN"
wh_wait 1
expect_eq "HQ1.a …it is still running" "124" "$WH_RC"
expect_eq "HQ1.b …and it said nothing on either stream" "|" "$WH_OUT|$WH_ERR"
expect_eq "HQ2 the watch record says watching, naming the watcher's own process" \
  "watching|$WH_PID" "$(wh_field "$RHQ" state)|$(wh_field "$RHQ" pid)"
expect_eq "HQ2.a …and the start the one alive rule reads it by" \
  "$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$WH_PID" | awk '{$1=$1; print}')" "$(wh_field "$RHQ" start)"
# AT MOST ONE A SESSION: a second watcher, as the next turn's end starts it, finds the first and ends silently.
WH_FIRST="$WH_PID"
wh_start "$RHQ" Stop; wh_wait 20
expect_eq "HQ3 a second watcher while the first watches ends at once, quietly" "0|" "$WH_RC|$WH_OUT$WH_ERR"
expect_eq "HQ3.a …and the record still names the first" "watching|$WH_FIRST" "$(wh_field "$RHQ" state)|$(wh_field "$RHQ" pid)"
WH_PID="$WH_FIRST"; wh_kill
# THE POSITIVE ON THE SAME EXTRACTOR: the same world, a request denied, and a new watcher wakes on it.
gate_line w99-T9 leaves-the-machine "git push origin wave/99-q" >> "$(gate_of "$RHQ")"
wh_start "$RHQ" Stop; wh_wait
expect_eq "HQ4 the same world with a request denied: the watcher wakes" "$WP_WAKE" "$WH_RC"
expect_regex "HQ4.a …with the gate's line on stderr" '^bionic watch: GATE ' "$WH_ERR"

section "§HOOK-REST: a run that waits only on the person ends the watcher silently, its record saying why (AC-10.1, the suite's half)"
wp_person_world wh-person
RHP="$WP_R"; wh_fast "$RHP"
wp_ask "$RHP" "$WP_PLAN" owed_open approve:step3 "approval: step3" "the plan is put to you"
wh_start "$RHP" Stop; wh_wait
expect_eq "HP1 the plan's approval put to the person and nothing else open: the watcher exits 0" "0" "$WH_RC"
expect_eq "HP1.a …and says nothing on either stream" "|" "$WH_OUT|$WH_ERR"
expect_eq "HP1.b …its record says resting, on the person" "resting|person" "$(wh_field "$RHP" state)|$(wh_field "$RHP" why)"
gate_line w99-T9 leaves-the-machine "git push origin wave/99-p" >> "$(gate_of "$RHP")"
wh_start "$RHP" Stop; wh_wait
expect_eq "HP2 the same world with a request denied: the watcher wakes instead" "$WP_WAKE" "$WH_RC"
expect_regex "HP2.a …its line on stderr" '^bionic watch: GATE ' "$WH_ERR"

section "§ONLY-PERSON (the stop line): the turn-end hook says once, in one line, that the watch has stopped and that the person's reply starts it again (AC-10.2)"
# fails-when: a turn end whose watcher rests on the person shows no line; the line is said again over the same resting
# state; it is said over a watcher still watching, a rest for another reason, a rest older than the turn's prompt, or
# a roster row open; it does not name the return or outgrows the window; the turn-end hook does not wait for the
# watcher the same turn end started.
WS_HOOK="${BIONIC_HOOKS_DIR}/stop.sh"
WS_LINE_WANT="bionic watch: stopped - waiting on you; your reply starts it again"
# ws_tx <repo> <prompt time> -> the transcript path: one prompt of the person's, at that time. It lives outside the
# repository, as the platform's own transcript does, so the tree the watcher's pass reads is the fixture's alone.
ws_tx() {
  jq -nc --arg t "$2" '{type:"user",uuid:"u-ws",isSidechain:false,userType:"external",timestamp:$t,
    message:{role:"user",content:"over to you"}}' > "$TMPROOT/ws-tx-${1##*/}.jsonl"
  printf '%s' "$TMPROOT/ws-tx-${1##*/}.jsonl"
}
# ws_stop <repo> <transcript> [env assignment...] -> WS_OUT WS_ERR WS_RC: the turn-end hook, as the platform runs it,
# with the agents WS_BG names (a JSON array, none by default) still running, and WS_ACTIVE the platform's
# `stop_hook_active` (false by default; true at the end of a turn a duty continued)
ws_stop() {
  local repo="$1" tx="$2"; shift 2
  jq -nc --arg s "$SID" --arg c "$repo" --arg t "$tx" --argjson bg "${WS_BG:-[]}" \
    --argjson a "${WS_ACTIVE:-false}" \
    '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:"Stop",stop_hook_active:$a,background_tasks:$bg}' > "$TMPROOT/ws.in"
  ( cd "$repo" && exec env CLAUDE_PROJECT_DIR= CLAUDE_CODE_SESSION_ID="$SID" \
      BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_SWAP_PCT=0 \
      "$@" bash "$WS_HOOK" < "$TMPROOT/ws.in" ) \
    > "$TMPROOT/ws.out" 2> "$TMPROOT/ws.err"
  WS_RC=$?; WS_OUT="$(cat "$TMPROOT/ws.out")"; WS_ERR="$(cat "$TMPROOT/ws.err")"
}
ws_line() { printf '%s' "$WS_OUT" | jq -r '.systemMessage // ""' 2>/dev/null; }
# ws_rest <repo> <why> <at> [digest] -> the watch record resting, and the digest the resting pass left
ws_rest() {
  printf 'state=resting\nwhy=%s\nat=%s\n' "$2" "$3" > "$(wh_rec "$1")"
  [ -z "${4:-}" ] || printf 'tick-digest/v1\ndigest=%s\nat=%s\n' "$4" "$3" > "$1/.bionic/tmp/tick-digest-$SID.state"
}
ws_iso() { date -u -v-"$1"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "-$1 seconds" +%Y-%m-%dT%H:%M:%SZ; }
# ws_claimed <repo> -> rc 0 once the watcher wh_start launched has claimed the record, as an earlier turn end's
# watcher already had in a live session; the hook does not wait on a session that never ran one
ws_claimed() {
  local i=0
  while [ ! -f "$(wh_rec "$1")" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  [ -f "$(wh_rec "$1")" ]
}
# ws_late_rest <repo> <digest> <seconds> -> a live watcher claims the record now and rests on the person <seconds>
# later, in the background: this turn end's watcher, still on its first pass when the hook first reads the record
ws_late_rest() {
  sleep 3600 & WS_LATE=$!
  printf 'state=watching\npid=%s\nstart=%s\nat=%s\n' "$WS_LATE" \
    "$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$WS_LATE" | awk '{$1=$1; print}')" "$(ws_iso 0)" > "$(wh_rec "$1")"
  ( sleep "$3"; ws_rest "$1" person "$(ws_iso 0)" "$2"; kill "$WS_LATE" 2>/dev/null ) &
  WS_LATE_REST=$!
}
ws_late_done() { wait "$WS_LATE_REST" 2>/dev/null; wait "$WS_LATE" 2>/dev/null; }
require_helpers ws_tx ws_stop ws_line ws_rest ws_iso ws_claimed ws_late_rest ws_late_done

# THE REAL WATCHER. The platform starts the watcher and the turn-end hook together; the hook waits for the watcher
# this turn end started, and the watcher's first pass decides the rest. The ask is the release's: the turn-end hook
# closes a plan step's ask once the plan is approved, so a step's ask would leave the run waiting on nothing.
wp_person_world ws-race
RWS="$WP_R"; wh_fast "$RWS"
wp_ask "$RWS" "$WP_PLAN" owed_open approve:release "approval: release" "the release card is put to you"
WS_TX="$(ws_tx "$RWS" "$(ws_iso 120)")"
wh_start "$RWS" Stop; ws_claimed "$RWS"; ws_stop "$RWS" "$WS_TX" BIONIC_STOP_WATCH_WAIT=60; wh_wait
expect_eq "OPL1 precondition: the watcher this turn end started rests on the person" "0|resting|person" \
  "$WH_RC|$(wh_field "$RWS" state)|$(wh_field "$RWS" why)"
expect_eq "OPL1.a the turn end that leaves the run waiting on the person says the line, once, on the quiet channel" \
  "$WS_LINE_WANT|0|" "$(ws_line)|$WS_RC|$WS_ERR"
expect_eq "OPL1.b …one systemMessage and nothing else: no turn, no error look" "systemMessage" \
  "$(printf '%s' "$WS_OUT" | jq -r 'keys | join(",")' 2>/dev/null)"
expect_true "OPL1.c …the line keeps to 66 columns, so the window's line under the platform's label keeps to 80" \
  test "$(printf '%s' "$(ws_line)" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')" -le 66
expect_contains "OPL1.d …and it names the return" "your reply starts it again" "$(ws_line)"
wh_start "$RWS" Stop; ws_claimed "$RWS"; ws_stop "$RWS" "$WS_TX" BIONIC_STOP_WATCH_WAIT=60; wh_wait
expect_eq "OPL2 the next turn end over the same resting state: the watcher rests again" "0|resting|person" \
  "$WH_RC|$(wh_field "$RWS" state)|$(wh_field "$RWS" why)"
expect_eq "OPL2.a …and the line is not said a second time" "" "$(ws_line)$WS_ERR"
# THE WAIT IS WHAT SETTLES IT, timed by hand: this turn end's watcher rests four seconds after its claim.
wp_person_world ws-nowait
RWN="$WP_R"
WN_TX="$(ws_tx "$RWN" "$(ws_iso 120)")"
ws_late_rest "$RWN" n1 4; ws_stop "$RWN" "$WN_TX" BIONIC_STOP_WATCH_WAIT=0; ws_late_done
expect_eq "OPL3 with no wait the watcher still rests on the person" "resting|person" \
  "$(wh_field "$RWN" state)|$(wh_field "$RWN" why)"
expect_eq "OPL3.a …but the hook read the record before the rest, and said nothing" "" "$(ws_line)"
ws_late_rest "$RWN" n2 4; ws_stop "$RWN" "$WN_TX" BIONIC_STOP_WATCH_WAIT=12; ws_late_done
expect_eq "OPL3.b with a wait the hook reads the rest the watcher writes after it started, and says the line" \
  "$WS_LINE_WANT|0|" "$(ws_line)|$WS_RC|$WS_ERR"

# THE RULE OVER A PLANTED RECORD, with no wait: each row moves one fact of OPL4's.
wp_person_world ws-rule
RWR="$WP_R"
WR_TX="$(ws_tx "$RWR" "$(ws_iso 120)")"
ws_rest "$RWR" person "$(ws_iso 5)" d1; ws_stop "$RWR" "$WR_TX" BIONIC_STOP_WATCH_WAIT=0
expect_eq "OPL4 a rest on the person since this turn's prompt: the line" "$WS_LINE_WANT" "$(ws_line)"
ws_stop "$RWR" "$WR_TX" BIONIC_STOP_WATCH_WAIT=0
expect_eq "OPL4.a …the same digest at the next turn end: nothing" "" "$(ws_line)"
ws_rest "$RWR" person "$(ws_iso 4)" d2; ws_stop "$RWR" "$WR_TX" BIONIC_STOP_WATCH_WAIT=0
expect_eq "OPL4.b a rest over a changed run: said again" "$WS_LINE_WANT" "$(ws_line)"
ws_rest "$RWR" person "$(ws_iso 4)" d2b; WS_ACTIVE=true ws_stop "$RWR" "$WR_TX" BIONIC_STOP_WATCH_WAIT=0
expect_eq "OPL4.c the end of a turn a duty continued leaves the run on the person: said there too" \
  "$WS_LINE_WANT|0|" "$(ws_line)|$WS_RC|$WS_ERR"
ws_rest "$RWR" woke "$(ws_iso 3)" d3; ws_stop "$RWR" "$WR_TX" BIONIC_STOP_WATCH_WAIT=0
expect_eq "OPL5 a rest for a wake is not the person's: nothing" "" "$(ws_line)"
ws_rest "$RWR" person "$(ws_iso 600)" d4; ws_stop "$RWR" "$WR_TX" BIONIC_STOP_WATCH_WAIT=0
expect_eq "OPL6 a rest older than this turn's prompt is the person's return: nothing" "" "$(ws_line)"
sleep 3600 & WS_LIVE=$!
printf 'state=watching\npid=%s\nstart=%s\nat=%s\n' "$WS_LIVE" \
  "$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$WS_LIVE" | awk '{$1=$1; print}')" "$(ws_iso 2)" > "$(wh_rec "$RWR")"
ws_stop "$RWR" "$WR_TX" BIONIC_STOP_WATCH_WAIT=0
expect_eq "OPL7 a watcher still watching: nothing" "" "$(ws_line)"
printf 'state=watching\npid=%s\nstart=%s\nat=%s\n' "$WS_LIVE" \
  "$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$WS_LIVE" | awk '{$1=$1; print}')" "$(ws_iso 60)" > "$(wh_rec "$RWR")"
WS_T0=$(date +%s); ws_stop "$RWR" "$WR_TX" BIONIC_STOP_WATCH_WAIT=12; WS_T1=$(date +%s)
expect_eq "OPL7.a a watcher an earlier turn end started, still watching: nothing" "" "$(ws_line)"
expect_true "OPL7.b …and the hook does not wait out its bound for it" test $((WS_T1 - WS_T0)) -lt 8
kill "$WS_LIVE" 2>/dev/null; wait "$WS_LIVE" 2>/dev/null
ws_rest "$RWR" person "$(ws_iso 2)" d5
# The row's agent is still running, so the landing sweep does not judge it and the open row alone keeps the line back.
add_row "$RWR" name=busy agent_id=abusy-1111111111111111 deliverable="$RWR/never-written.md" duration="4 hours" \
  launched_at="$(iso_ago 60)"
WS_BG='[{"id":"abusy-1111111111111111","status":"running"}]' ws_stop "$RWR" "$WR_TX" BIONIC_STOP_WATCH_WAIT=0
expect_eq "OPL8 a roster row open: nothing rests, and nothing is said" "" "$(ws_line)"
expect_eq "OPL8.a …because the row is open, not because a wall refused the turn" "0||" \
  "$WS_RC|$WS_OUT|$(head -1 "$RWR/.bionic/tmp/duty-$SID.state" 2>/dev/null)"

section "§HOOK-STAYS: with an agent or a detached run out and nothing changing, ten passes leave the watcher running (AC-10.4, the suite's half)"
wp_person_world wh-stays-row
RHA="$WP_R"; wh_fast "$RHA"
wp_ask "$RHA" "$WP_PLAN" owed_open approve:step3 "approval: step3" "the plan is put to you"
add_row "$RHA" name=busy deliverable="$RHA/never-written.md" duration="4 hours" launched_at="$(iso_ago 60)"
plant_answer "$WP_TR" fresh "busy:running"
poke "$RHA" tick >/dev/null
wh_start "$RHA" Stop
wh_passes "$RHA" 10
expect_eq "HS1 one active row: ten passes, the watcher up through all of them" "10" "$WH_SEEN"
wh_wait 1
expect_eq "HS1.a …still running after the tenth, silent" "124||" "$WH_RC|$WH_OUT|$WH_ERR"
wh_kill
wp_person_world wh-stays-run
RHD="$WP_R"; wh_fast "$RHD"
wp_ask "$RHD" "$WP_PLAN" owed_open approve:step3 "approval: step3" "the plan is put to you"
WH_RUNLOG="$RHD/.bionic/tmp/runs/regression@cccccccc.log"; mkdir -p "${WH_RUNLOG%/*}"; : > "$WH_RUNLOG"
bash "$TMPROOT/shim/booked.sh" --run-log "$WH_RUNLOG" >/dev/null 2>&1 &
WH_RUNPID=$!
roster_row_fixture status=run session="$SID" name=regression@cccccccc agent_id= launched_at="$(iso_ago 60)" \
  subagent_type=bionic:test-runner model= waiver="a whole run the tick started, not an agent: its log and its proof are its record" \
  suites_allowed=run.sh suites_source=DECLARED tool_use_id= plan="$WP_PLAN" \
  run_log="$WH_RUNLOG" run_pid="$WH_RUNPID" run_started_at="$(iso_ago 60)" >> "$(roster_of "$RHD")"
poke "$RHD" tick >/dev/null
wh_start "$RHD" Stop
wh_passes "$RHD" 10
expect_eq "HS2 no row but a live detached run: ten passes, the watcher up through all of them" "10" "$WH_SEEN"
wh_wait 1
expect_eq "HS2.a …still running after the tenth, silent" "124||" "$WH_RC|$WH_OUT|$WH_ERR"
wh_kill
kill "$WH_RUNPID" 2>/dev/null; wait "$WH_RUNPID" 2>/dev/null; printf '0\n' > "$WH_RUNLOG.rc"
wh_start "$RHD" Stop; wh_wait
expect_eq "HS2.b …and once the run has ended the next watcher rests" "0|resting|person" "$WH_RC|$(wh_field "$RHD" state)|$(wh_field "$RHD" why)"

section "§HOOK-REFUSED: a pass the tick refuses ends the watcher silently and never wakes; a session bionic never engaged gets no watcher"
RHR="$(make_repo wh-refused)"; wh_fast "$RHR"
wh_start "$RHR" SessionStart; wh_wait
expect_eq "HR1 engaged, never armed and no roster, so the tick refuses: the watcher exits 0" "0" "$WH_RC"
expect_eq "HR1.a …saying nothing on either stream" "|" "$WH_OUT|$WH_ERR"
expect_eq "HR1.b …its record says resting, on the refusal" "resting|refused" "$(wh_field "$RHR" state)|$(wh_field "$RHR" why)"
rm -f "$(wh_rec "$RHR")"; unengage "$RHR"
wh_start "$RHR" SessionStart; wh_wait
expect_eq "HR2 the same project, the session not engaged: the watcher exits 0, silent" "0|" "$WH_RC|$WH_OUT$WH_ERR"
expect_false "HR2.a …and leaves no watch record" test -e "$(wh_rec "$RHR")"
engage "$RHR"
printf '{}' > "$TMPROOT/wh.in"
( cd "$RHR" && exec env -u CLAUDE_CODE_SESSION_ID bash "$WH_HOOK" < "$TMPROOT/wh.in" ) > "$TMPROOT/wh.out" 2> "$TMPROOT/wh.err"
expect_eq "HR3 an input that names no session: exit 0, silent, no record" "0||no" \
  "$?|$(cat "$TMPROOT/wh.out" "$TMPROOT/wh.err")|$([ -e "$(wh_rec "$RHR")" ] && echo yes || echo no)"

section "§HOOK-DAY: near its day's end a watcher with an agent out wakes once so the turn's end replaces it; with none it rests"
RHL="$(wp_quiet_world wh-day)"; wh_fast "$RHL"
plant_answer "$WP_TR" fresh "busy:running"
poke "$RHL" tick >/dev/null
wh_start "$RHL" Stop BIONIC_WATCH_DEADLINE=3; wh_wait
expect_eq "HL1 an open row and the day nearly spent: the watcher exits with the wake code" "$WP_WAKE" "$WH_RC"
expect_regex "HL1.a …its one line says to end the turn so a new watch starts" '^bionic watch: RENEW .*turn' "$WH_ERR"
expect_eq "HL1.b …one line, inside the ceiling" "1|yes" "$(wp_lines "$WH_ERR")|$([ "$(wp_len "$WH_ERR")" -le "$WP_MAX" ] && echo yes)"
expect_eq "HL1.c …its record says resting, woken" "resting|woke" "$(wh_field "$RHL" state)|$(wh_field "$RHL" why)"
wp_person_world wh-day-none
RHN="$WP_R"; wh_fast "$RHN"
wh_start "$RHN" Stop BIONIC_WATCH_DEADLINE=3; wh_wait
expect_eq "HL2 no agent out and the day nearly spent: the watcher exits 0, silent" "0|" "$WH_RC|$WH_OUT$WH_ERR"
expect_eq "HL2.a …its record says resting, at its limit" "resting|limit" "$(wh_field "$RHN" state)|$(wh_field "$RHN" why)"

section "§HOOK-CLEARED: a watcher whose conversation was cleared ends silently; the new conversation's start brings its own"
RHC="$(wp_quiet_world wh-cleared)"; wh_fast "$RHC"
plant_answer "$WP_TR" fresh "busy:running"
poke "$RHC" tick >/dev/null
sleep 600 & WH_CLI=$!
WH_CLI_START="$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$WH_CLI" | awk '{$1=$1; print}')"
mkdir -p "$WP_CFG/sessions"
wh_cli() { jq -nc --argjson p "$WH_CLI" --arg s "$1" --arg st "$WH_CLI_START" --arg c "$RHC" \
  '{pid:$p,sessionId:$s,procStart:$st,cwd:$c}' > "$WP_CFG/sessions/$WH_CLI.json"; }
wh_cli "$SID"
wh_start "$RHC" Stop
wh_passes "$RHC" 2
expect_eq "HC0 precondition: the CLI's file names this conversation, and the watcher passes" "2" "$WH_SEEN"
wh_cli "a-new-conversation-0000"
wh_wait 20
expect_eq "HC1 the CLI's file now names another conversation: the watcher exits 0, silent" "0|" "$WH_RC|$WH_OUT$WH_ERR"
expect_eq "HC1.a …its record says resting, cleared" "resting|cleared" "$(wh_field "$RHC" state)|$(wh_field "$RHC" why)"
kill "$WH_CLI" 2>/dev/null; wait "$WH_CLI" 2>/dev/null; rm -f "$WP_CFG/sessions/$WH_CLI.json"

# ============================================================
finish
