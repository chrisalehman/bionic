#!/bin/bash
# Tests for hooks/session-poker.sh — shard 2 of 4: Sections 36 through 55.
#
# THE SUITE IS FOUR SHARDS (wave-30 T2; design-ledger Δ7, D8). Its governing design, its
# hermetic posture and its clock discipline are written once, in tests/session-poker.test.sh's
# header; the sandbox, the pins and the shared fixture builders are
# tests/session-poker.prelude.sh, sourced below after the framework and the POKER seam.
#
# SPLIT WHERE NO FIXTURE CROSSES. Section 49 reads the review repository Section 48 builds, so
# they sit together here; the rest of this shard builds its own repositories and calls only
# hoisted helpers from shard 1.
#
# Usage: bash tests/session-poker-2.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"

# THE SEAM, exactly as tests/session-poker.test.sh offers it, for RED evidence against a
# mutated copy without ever touching the shipped file:
#   W2_POKER_UNDER_TEST=/tmp/mutant.sh bash tests/session-poker-2.test.sh
POKER="${W2_POKER_UNDER_TEST:-${BIONIC_HOOKS_DIR}/session-poker.sh}"
. "$(dirname "$0")/session-poker.prelude.sh"

# ============================================================
section "Section 36: prompt — the canonical Patrol prompt (wave-20 REQ-6, AC-6.1; D6)"
# ============================================================
#
# THE PROMPT IS PRINTED, NOT COMPOSED. Report #1: a Patrol job whose prompt was the bare tick
# command (or a marker with no tick) was never a tick turn, or ran no tick. `prompt` prints the
# one prompt a CronCreate should carry — the session's marker first, the tick command in it.
R36="$(make_repo s36)"
poke "$R36" prompt
expect_eq "36a prompt exits 0" "0" "$RC"
case "$OUT" in
  "bionic-patrol session=${SID:0:8} "*) ok "36b AC-6.1 the prompt starts with this session's marker" ;;
  *) no "36b AC-6.1 the prompt starts with this session's marker" "$OUT" ;;
esac
expect_contains "36c …and carries the tick command, by this poker's absolute path" "bash $POKER tick" "$OUT"
expect_eq "36d …on one line (a CronCreate prompt)" "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
expect_contains "36e …and names the fill answer: dispatch, or a row made not ready, never an answer in words" \
  "a row that should wait is made not ready instead, by one of the three forms the stop wall prints" "$OUT"
OUT="$( cd "$R36" && CLAUDE_CODE_SESSION_ID="" bash "$POKER" prompt 2>&1 )"; RC=$?
expect_eq "36f with no session key there is no marker to print (exit 3)" "3" "$RC"
poke "$R36" prompt extra
expect_eq "36g prompt takes no arguments (exit 2)" "2" "$RC"


# ============================================================
section "Section 37: the release fills once its waits are met, at any step; task-add keeps author text byte for byte"
# ============================================================
#
# A RELEASE ROW WAITS ON WHAT ITS DEPS AND ITS KIND NAME, and on no step: the person approves the
# release at the merge, which waits on that approval.
R37A="$(make_repo s37-held)"; new_roster "$R37A"
sp_plan_at_step "$R37A" 5 \
  "| T1 | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 5 | verify | the live bed, landed | implementor | T1 | 15m | REQ-x | — | landed |" \
  "| T3 | 7 | doc | Release 1.8.7 | implementor | T2 | 15m | REQ-x | CHANGELOG.md | pending |" > /dev/null
poke_pressure "$R37A" 8192 1.0 tick
expect_contains "37a at current: 5 the release row at 15, its waits met, is filled: no step holds it" \
  "poker: FILL T3" "$OUT"

# 37c — AT ITS STEP THE RELEASE FILLS. Same table at current: 7.
R37C="$(make_repo s37-at-step)"; new_roster "$R37C"
sp_plan_at_step "$R37C" 7 \
  "| T1 | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 5 | verify | the live bed, landed | implementor | T1 | 15m | REQ-x | — | landed |" \
  "| T3 | 7 | doc | Release 1.8.7 | implementor | T2 | 15m | REQ-x | CHANGELOG.md | pending |" > /dev/null
poke_pressure "$R37C" 8192 1.0 tick
expect_contains "37c at current: 7 the release row is filled" "poker: FILL T3" "$OUT"

# 37d–37i — A ROW IS ADDED BY AN EDIT AND task-add RECORDS ITS BIRTH, writing no plan. A step hold is a schedule
# fact, not a broken invariant. A row the plan lacks and a short row are refused in different words, the short one
# with the line the verb would accept, which it then accepts as pasted.
S37_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R37D="$(make_repo s37-task-add)"; ( cd "$R37D" && git commit -q --allow-empty -m init )
P37D="$(s34_plan "$R37D" 5)"
L37D="${P37D%/plans/*}/record/$(basename "$P37D" .plan.md)/run.log"; s37() { cmp -s "$TMPROOT/s42-before" "$P37D" && echo same; }
ta_add "$R37D" T7 7 doc 'Keep C:\new\table, a\|b, $5. The release keeps its text as typed.' bionic:implementor 'T5' 30 REQ-5 '—'
expect_eq "37d task-add of a Step-7 doc row edited in at current: 5 is accepted (exit 0)" "0" "$RC"
expect_eq "37f …the plan's sum the same across it, no line of its own written, its birth one born event in the run's log" "same|0|1" \
  "$(s37)|$(/usr/bin/grep -c '^- T7: ' "$P37D")|$(/usr/bin/grep -c '|ev=born|row=T7|' "$L37D")"
poke "$R37D" task-add T9; expect_eq "37g a row the plan does not hold is refused in its own words, nothing born" "1|holds no row T9|0" "$RC|$(printf '%s' "$OUT" | /usr/bin/grep -o 'holds no row T9')|$(/usr/bin/grep -c '|ev=born|row=T9|' "$L37D")"
ta_add "$R37D" T8 5 verify 'Verify the fixture. The floor runs once.' bionic:test-runner — 30 REQ-5 '—'
expect_eq "37h a verify row whose Files name no record is short: refused with the line it would accept, the plan the same, nothing born" "1|is short|same|0" \
  "$RC|$(printf '%s' "$OUT" | /usr/bin/grep -o 'is short')|$(s37)|$(/usr/bin/grep -c '|ev=born|row=T8|' "$L37D")"
S37_LINE="$(printf '%s\n' "$OUT" | /usr/bin/grep '^| T8 |')"; ta_put "$P37D" "$S37_LINE"; poke "$R37D" task-add T8
expect_eq "37i its own printed line pasted in, the verb accepts it with no further edit" "0|T8.md|1" "$RC|$(printf '%s' "$S37_LINE" | /usr/bin/grep -o 'T8\.md' | head -1)|$(/usr/bin/grep -c '|ev=born|row=T8|' "$L37D")"
cp "$P37D" "$TMPROOT/s42-before"; poke "$R37D" task-add T7 --drop 'the person no longer wants it'
expect_eq "37j --drop of a pending row is accepted, the plan the same, its one drop event holding the words" "0|same|1" "$RC|$(s37)|$(/usr/bin/grep -c '|ev=drop|row=T7|why=the person no longer wants it|' "$L37D")"
S37_D=""; for a in T1 T2 T9; do poke "$R37D" task-add "$a" --drop 'gone'; S37_D="$S37_D$RC"; done; poke "$R37D" task-add T5 --drop 'a|b'; S37_D="$S37_D$RC"
expect_eq "37k a landed row, a row in flight and a row the plan lacks are refused, words holding a bar are a usage error: nothing dropped" "1112|1" "$S37_D|$(/usr/bin/grep -c '|ev=drop|' "$L37D")"
POKE_BOUND="$S37_BOUND_WAS"


# ============================================================
section "Section 38: the tick names an ext:-held row — poker: HELD <id> ext:<slug> (wave-21 T4; REQ-3, AC-3.3; D3, ADR-037 decision 2)"
# ============================================================
#
# A ROW WAITING ON THE WORLD IS DECLARED ONCE, IN ITS DEPS CELL, as `ext:<slug>`. The ready
# set already leaves it out (an ext: token never equals `landed`); what the tick adds is the
# report: one `poker: HELD <id> ext:<slug>` line per held row, every interval, AFTER the rung
# line and BEFORE the FILL line, so the hold is printed to the only actor who can lift it and
# nobody writes a decline for it turn after turn (triage-A §F.3).
# s38_line_no <pattern> — the first line of $OUT starting with <pattern>, by number; 0 if none.
s38_line_no() { printf '%s\n' "$OUT" | awk -v p="$1" 'index($0, p) == 1 { print NR; f = 1; exit } END { if (!f) print 0 }'; }

R38A="$(make_repo s38-held)"; new_roster "$R38A"
sp_plan_at_step "$R38A" 4 \
  "| T1 | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | waits on CI | implementor | T1, ext:ci-ce9520e | 15m | REQ-x | b.sh | pending |" \
  "| T3 | 4 | build | ordinary, ready | implementor | T1 | 15m | REQ-x | c.sh | pending |" > /dev/null
poke_pressure "$R38A" 8192 1.0 tick
expect_contains "38a AC-3.3 the ext:-held row prints its HELD line" "poker: HELD T2 ext:ci-ce9520e" "$OUT"
expect_contains "38b …the ready row is filled" "poker: FILL T3" "$OUT"
expect_absent "38c …and the held row is not on the FILL line" "T2" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: FILL')"
S38_RUNG="$(s38_line_no 'poker: gate share=')"; S38_HELD="$(s38_line_no 'poker: HELD ')"; S38_FILL="$(s38_line_no 'poker: FILL ')"
expect_true "38d …and the HELD line sits after the gate line and before the FILL line (gate=$S38_RUNG held=$S38_HELD fill=$S38_FILL)" \
  test "$S38_RUNG" -gt 0 -a "$S38_HELD" -gt "$S38_RUNG" -a "$S38_FILL" -gt "$S38_HELD"

# 38e — NOTHING ELSE READY: the HELD line still prints, and the no-FILL line's step sentence
# does not borrow it (the step hold and the ext hold are different facts).
R38E="$(make_repo s38-held-only)"; new_roster "$R38E"
sp_plan_at_step "$R38E" 4 \
  "| T1 | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | waits on a rig and CI | implementor | ext:rig-2, T1, ext:ci-9 | 15m | REQ-x | b.sh | pending |" > /dev/null
poke_pressure "$R38E" 8192 1.0 tick
expect_contains "38e a row with two tokens prints one HELD line naming both, in cell order" "poker: HELD T2 ext:rig-2 ext:ci-9" "$OUT"
expect_absent "38f …no FILL line is printed" "poker: FILL" "$OUT"
expect_absent "38g …and the no-FILL line names no step hold for it" "Held for their step" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: no FILL')"

# 38h — THE TOKEN REMOVED, the row is ready again and no HELD line is printed (AC-3.4's tick side).
R38H="$(make_repo s38-cleared)"; new_roster "$R38H"
sp_plan_at_step "$R38H" 4 \
  "| T1 | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | CI went green | implementor | T1 | 15m | REQ-x | b.sh | pending |" \
  "| T3 | 4 | build | ordinary, ready | implementor | T1 | 15m | REQ-x | c.sh | pending |" > /dev/null
poke_pressure "$R38H" 8192 1.0 tick
expect_contains "38h with the token removed the row is filled again" "poker: FILL T2 T3" "$OUT"
expect_absent "38i …and no HELD line is printed" "poker: HELD" "$OUT"

# ============================================================
section "Section 39: the tick lints the ledger — poker: LEDGER <id> <finding> (wave-21 T5; REQ-4, AC-4.2; D4, ADR-037 decision 3)"
# ============================================================
#
# THE SAME READER THE GATE ASKS. `units_findings` names every ledger defect — a status off
# the enum, a landed row the reader does not answer landed, an active row whose agent cell names no row
# on this session's roster — and the tick prints each one, every interval, as
# `poker: LEDGER <id> <kind> [<value>]`, after the HELD lines and before the FILL line. The
# finding reaches the orchestrator, who owns the ledger, before a writer's commit meets it.
R39A="$(make_repo s39-ledger)"; new_roster "$R39A"
mkrow name=w-T2 agent_id=a-w-T2 >> "$(roster_of "$R39A")"
P39A="$(sp_plan_at_step "$R39A" 4 \
  "| T1 | 4 | build | landed, no line | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | active, launched | w-T2 | — | 15m | REQ-x | b.sh | active |" \
  "| T3 | 4 | build | active, agent names no roster row | implementor | — | 15m | REQ-x | c.sh | active |" \
  "| T4 | 4 | build | active, another name no roster row carries | w-T4 | — | 15m | REQ-x | d.sh | active |" \
  "| T6 | 4 | build | waits on CI | implementor | T1, ext:ci-6 | 15m | REQ-x | f.sh | pending |" \
  "| T7 | 4 | build | ordinary, ready | implementor | T1 | 15m | REQ-x | g.sh | pending |")"
poke_pressure "$R39A" 8192 1.0 tick
expect_absent "39a AC-4.2 a landed row with no line, which the reader answers landed, ticks no LEDGER line" "poker: LEDGER T1" "$OUT"
expect_contains "39b …an active row whose agent is not on the roster ticks a launch line, naming the cell" \
  "poker: LEDGER T3 launch implementor" "$OUT"
expect_contains "39c …and a second such row a line of its own, naming its launch's name" "poker: LEDGER T4 launch w-T4" "$OUT"
expect_absent "39d …the launched active row is not a finding" "poker: LEDGER T2" "$OUT"
expect_eq "39f …exactly two LEDGER lines" "2" "$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^poker: LEDGER ')"
S39_HELD="$(s38_line_no 'poker: HELD ')"; S39_LEDGER="$(s38_line_no 'poker: LEDGER ')"; S39_FILL="$(s38_line_no 'poker: FILL ')"
expect_true "39g …and the LEDGER lines sit after the HELD line and before the FILL line (held=$S39_HELD ledger=$S39_LEDGER fill=$S39_FILL)" \
  test "$S39_HELD" -gt 0 -a "$S39_LEDGER" -gt "$S39_HELD" -a "$S39_FILL" -gt "$S39_LEDGER"
expect_contains "39h …and the fill is unchanged by the lint" "poker: FILL T7" "$OUT"

# 39i — THE LEDGER REPAIRED: T3 launched again under its roster row's name, T4's launch taken back. No LEDGER line.
mkrow name=w-T3 agent_id=a-w-T3 >> "$(roster_of "$R39A")"
printf 'run/v1|ev=%s|at=2026-10-04T00:3%s:00Z\n' 'dispatch|row=T3|name=w-T3' 0 'cancel|of=dispatch|row=T4|name=w-T4' 1 >> "$R39A/.bionic/docs/record/wave-01-fixture/run.log"
poke_pressure "$R39A" 8192 1.0 tick
expect_contains "39i the repaired ledger's tick still reaches its fill" "poker: FILL " "$OUT"
expect_absent "39j a repaired ledger ticks no LEDGER line" "poker: LEDGER" "$OUT"

# 39k — AN EMPTY ROSTER LAUNCHES NOBODY. The tick reaches its fill arm only with a roster file
# (no file is its own REFUSED/QUIET answer, §13), so the reader's no-roster rule is the gate's
# alone; what the tick can meet is a roster with no rows, and there an agent-named active row is
# a launch finding, not an evidence one.
R39K="$(make_repo s39-empty-roster)"; new_roster "$R39K"
sp_plan_at_step "$R39K" 4 \
  "| T1 | 4 | build | active, agent-named, nobody launched | w-T1 | — | 15m | REQ-x | a.sh | active |" \
  "| T2 | 4 | build | ordinary, ready | implementor | — | 15m | REQ-x | b.sh | pending |" > /dev/null
poke_pressure "$R39K" 8192 1.0 tick
expect_contains "39k an empty roster: the agent-named active row ticks a launch line" \
  "poker: LEDGER T1 launch w-T1" "$OUT"

# ============================================================
section "Section 40: HELD and LEDGER print in EVERY tick state — no roster, no room, over the share, no budget (wave-21 T13; REQ-3 AC-3.3, REQ-4 AC-4.1/AC-4.2; wave-28 T13)"
# ============================================================
#
# THREE REACHABLE STATES NEVER REACH THE FILL BRANCH: the first tick of a run (no roster file yet:
# rung, QUIET, exit), HOLD or EMERGENCY under machine pressure, and a plan with no `parallel-budget`.
# The commit gate reads the ledger in every one of them, so the tick does too. Every case here holds
# an ext:-held row and a defective ledger row, and expects each line EXACTLY ONCE — printed
# before the state split, never a second time inside an arm. Sections 38/39 pin the probes to
# a healthy machine; these pin them to the states those sections never reach.
s40_count() { printf '%s\n' "$OUT" | /usr/bin/grep -c "^$1" 2>/dev/null; }
# THE SHARE IS FIXTURE DATA (wave-31 T25; A-T25-7). "A 90% load is over the share" holds only
# against a share below 90, and the gate reads it from ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/share
# (lib/gate.sh `gate_share`): left unpinned, this section read the machine's file and went red the
# day it was set to 92. So the section runs under a config dir of its own holding share 80, as
# tests/gate.test.sh's `fresh()` plants it, and gives the environment back after 40e.
S40_CFG="$(fake_config_dir s40)"; mkdir -p "$S40_CFG/bionic"; printf '80\n' > "$S40_CFG/bionic/share"
export CLAUDE_CONFIG_DIR="$S40_CFG"

# 40a — THE FIRST TICK: armed, no roster file. With no roster the tick reads the ledger as the gate does: a row the
# log holds launched under a name is launched, so it is no finding, whatever name it carries.
R40A="$(make_repo s40-no-roster)"
poke "$R40A" arm
P40A="$(sp_plan_at_step "$R40A" 4 \
  "| T1 | 4 | build | launched under a name no roster row carries | w-T9 | — | 15m | REQ-x | a.sh | active |" \
  "| T2 | 4 | build | waits on CI | implementor | ext:ci-40a | 15m | REQ-x | b.sh | pending |" \
  "| T3 | 4 | build | active, agent-named, no line | w-T3 | — | 15m | REQ-x | c.sh | active |")"
poke_pressure "$R40A" 8192 1.0 tick
expect_contains "40a AC-3.3 the first tick prints the ext:-held row's HELD line" "poker: HELD T2 ext:ci-40a" "$OUT"
expect_absent "40a2 AC-4.2 …and the row launched under a name no roster row carries ticks no LEDGER line, as the gate reads it" "poker: LEDGER T1" "$OUT"
expect_absent "40a3 AC-4.1 …nor does the other launched row" "poker: LEDGER T3" "$OUT"
s40_find() { bash -c '. "$1/units.sh" && units_findings "$2" "$3"' _ "$BIONIC_SCRIPTS_DIR/payload/scripts/lib" "$P40A" "$1"; }
expect_eq "40a3b …the gate's reading of the same world admits both rows, and with a roster naming neither it names each launch" \
  "|launch T1 w-T9 launch T3 w-T3" "$(s40_find '')|$(new_roster "$R40A"; s40_find "$(roster_of "$R40A")" | paste -sd' ' -; rm -f "$(roster_of "$R40A")")"
expect_eq "40a4 …each HELD line once" "1" "$(s40_count 'poker: HELD ')"
expect_eq "40a5 …and no LEDGER line" "0" "$(s40_count 'poker: LEDGER ')"
S40_RUNG="$(s38_line_no 'poker: gate share=')"; S40_HELD="$(s38_line_no 'poker: HELD ')"; S40_QUIET="$(s38_line_no 'poker: QUIET')"
expect_true "40a6 …after the gate line and before the QUIET line (gate=$S40_RUNG held=$S40_HELD quiet=$S40_QUIET)" \
  test "$S40_RUNG" -gt 0 -a "$S40_HELD" -gt "$S40_RUNG" -a "$S40_QUIET" -gt "$S40_HELD"

# 40b — NO ROOM: a roster, a ready row, and a five-minute load over the share. No fill, and
# the lint still runs: a busy machine has nothing to do with the ledger.
R40B="$(make_repo s40-hold)"; new_roster "$R40B"
sp_plan_at_step "$R40B" 4 \
  "| T1 | 4 | build | launched under a name no roster row carries | w-T9 | — | 15m | REQ-x | a.sh | active |" \
  "| T2 | 4 | build | waits on CI | implementor | ext:ci-40b | 15m | REQ-x | b.sh | pending |" \
  "| T3 | 4 | build | ordinary, ready | implementor | — | 15m | REQ-x | c.sh | pending |" > /dev/null
BIONIC_PROBE_BUSY_CORES_5M=7.0 poke "$R40B" tick
expect_absent "40b precondition: …and fills nothing" "poker: FILL" "$OUT"
expect_contains "40b AC-3.3 with no room the ext:-held row prints its HELD line" "poker: HELD T2 ext:ci-40b" "$OUT"
expect_contains "40b2 AC-4.2 …and the row launched under a name no roster row carries ticks a LEDGER line" "poker: LEDGER T1 launch w-T9" "$OUT"
expect_eq "40b3 …HELD once" "1" "$(s40_count 'poker: HELD ')"
expect_eq "40b4 …LEDGER once" "1" "$(s40_count 'poker: LEDGER ')"
S40_RUNG="$(s38_line_no 'poker: gate share=')"; S40_HELD="$(s38_line_no 'poker: HELD ')"
S40_LEDGER="$(s38_line_no 'poker: LEDGER ')"; S40_HOLD="$(s38_line_no 'poker: no FILL — the gate')"
expect_true "40b5 …after the gate line and before the no-room line (gate=$S40_RUNG held=$S40_HELD ledger=$S40_LEDGER noroom=$S40_HOLD)" \
  test "$S40_RUNG" -gt 0 -a "$S40_HELD" -gt "$S40_RUNG" -a "$S40_LEDGER" -gt "$S40_HELD" -a "$S40_HOLD" -gt "$S40_LEDGER"
# THE PAIRED POSITIVE: the same repo on a healthy machine fills T3 and prints each line once.
poke_pressure "$R40B" 8192 1.0 tick
expect_contains "40b6 …the same plan on a healthy machine fills the ready row" "poker: FILL T3" "$OUT"
expect_eq "40b7 …and still prints HELD once, not once per arm" "1" "$(s40_count 'poker: HELD ')"
expect_eq "40b8 …and LEDGER once" "1" "$(s40_count 'poker: LEDGER ')"

# 40c — OVER THE SHARE: the same pair with memory used past the share.
R40C="$(make_repo s40-emergency)"; new_roster "$R40C"
sp_plan_at_step "$R40C" 4 \
  "| T1 | 4 | build | launched under a name no roster row carries | w-T9 | — | 15m | REQ-x | a.sh | active |" \
  "| T2 | 4 | build | waits on CI | implementor | ext:ci-40c | 15m | REQ-x | b.sh | pending |" > /dev/null
BIONIC_PROBE_USED_PCT=90 poke "$R40C" tick
expect_contains "40c precondition: the tick is over the share" "poker: over share — used=90% admitted: none" "$OUT"
expect_contains "40c AC-3.3 over the share the ext:-held row prints its HELD line" "poker: HELD T2 ext:ci-40c" "$OUT"
expect_contains "40c2 AC-4.2 …and the row launched under a name no roster row carries ticks a LEDGER line" "poker: LEDGER T1 launch w-T9" "$OUT"
expect_eq "40c3 …HELD once" "1" "$(s40_count 'poker: HELD ')"
expect_eq "40c4 …LEDGER once" "1" "$(s40_count 'poker: LEDGER ')"

# 40d — NO BUDGET: the plan carries no `parallel-budget:` line, so the fill arm takes its
# no-budget note — and the lint does not wait on a budget it has no use for.
R40D="$(make_repo s40-no-budget)"; new_roster "$R40D"
P40D="$(sp_plan_at_step "$R40D" 4 \
  "| T1 | 4 | build | launched under a name no roster row carries | w-T9 | — | 15m | REQ-x | a.sh | active |" \
  "| T2 | 4 | build | waits on CI | implementor | ext:ci-40d | 15m | REQ-x | b.sh | pending |")"
/usr/bin/grep -v '^parallel-budget:' "$P40D" > "$P40D.new" && mv "$P40D.new" "$P40D"
poke_pressure "$R40D" 8192 1.0 tick
expect_absent "40d precondition: the tick names no budget key on a plan with no line" "parallel-budget" "$OUT"
expect_contains "40d AC-3.3 with no budget the ext:-held row prints its HELD line" "poker: HELD T2 ext:ci-40d" "$OUT"
expect_contains "40d2 AC-4.2 …and the row launched under a name no roster row carries ticks a LEDGER line" "poker: LEDGER T1 launch w-T9" "$OUT"
expect_eq "40d3 …HELD once" "1" "$(s40_count 'poker: HELD ')"
expect_eq "40d4 …LEDGER once" "1" "$(s40_count 'poker: LEDGER ')"

# 40e — DISARM: the terminal tick (critic-4e6d4a9 I3). An empty roster on a run that says it is
# delivered — its step 9 carrying `delivered=`, armed before that — decides DISARM,
# and a delivered run whose ledger still carries a finding is one the gate would refuse, so this
# last tick says so. No other case ticks DISARM over a plan with a hold and a finding, so the
# report's call on that arm was unpinned: deleting it left every suite green.
R40E="$(make_repo s40-disarm)"; new_roster "$R40E"
armed_ago "$R40E"
P40E="$(sp_plan_at_step "$R40E" 9 \
  "| T1 | 4 | build | launched under a name no roster row carries | w-T9 | — | 15m | REQ-x | a.sh | active |" \
  "| T2 | 4 | build | waits on CI | implementor | ext:ci-40e | 15m | REQ-x | b.sh | pending |")"
L40E="$R40E/.bionic/docs/record/wave-01-fixture/run.log"
printf 'run/v1|ev=step|n=9|delivered=bionic 9.9.9; report: record/fixture/close-out.md|at=2026-10-04T00:30:00Z\n' >> "$L40E"
poke_pressure "$R40E" 8192 1.0 tick
expect_contains "40e precondition: the run's step 9 records the delivery" \
  "|ev=step|n=9|delivered=bionic 9.9.9" "$(cat "$L40E")"
expect_contains "40e precondition: …and the tick decides DISARM" "decision=DISARM" "$OUT"
expect_contains "40e AC-3.3 the DISARM tick prints the ext:-held row's HELD line" "poker: HELD T2 ext:ci-40e" "$OUT"
expect_contains "40e2 AC-4.2 …and the row launched under a name no roster row carries ticks a LEDGER line" "poker: LEDGER T1 launch w-T9" "$OUT"
expect_eq "40e3 …HELD once" "1" "$(s40_count 'poker: HELD ')"
expect_eq "40e4 …LEDGER once" "1" "$(s40_count 'poker: LEDGER ')"
S40_RUNG="$(s38_line_no 'poker: gate share=')"; S40_HELD="$(s38_line_no 'poker: HELD ')"
S40_LEDGER="$(s38_line_no 'poker: LEDGER ')"; S40_DISARM="$(s38_line_no 'poker: DISARM')"
expect_true "40e5 …after the gate line and before the DISARM line (gate=$S40_RUNG held=$S40_HELD ledger=$S40_LEDGER disarm=$S40_DISARM)" \
  test "$S40_RUNG" -gt 0 -a "$S40_HELD" -gt "$S40_RUNG" -a "$S40_LEDGER" -gt "$S40_HELD" -a "$S40_DISARM" -gt "$S40_LEDGER"
expect_contains "40f the section read its own share, never the machine's (the gate line names 80)" "poker: gate share=80" "$OUT"
unset CLAUDE_CONFIG_DIR
# ============================================================
section "SHARE — the verb prints the reserve and sets it (REQ-6, AC-6.2)"
# ============================================================
# One config dir on a planted 8-core world; the verb reads and writes the files the gate reads.
SS_CFG="$(fake_config_dir sshare)"
ss_verb() { ( cd "$TMPROOT" && CLAUDE_CONFIG_DIR="$SS_CFG" bash "$POKER" share "$@" 2>&1 ); }
expect_eq "SS.1 share prints the share, the default reserve, the cores and the room" \
  "share=92 reserve=1 cores=8 room=6.36" "$(ss_verb)"
ss_verb reserve=2 >/dev/null
expect_eq "SS.2 reserve=2 writes 2 and the next print reads it (room 5.36)" \
  "2|share=92 reserve=2 cores=8 room=5.36" "$(sed -n 1p "$SS_CFG/bionic/reserve")|$(ss_verb)"
ss_verb reserve=9 >/dev/null; SS_RC=$?
expect_eq "SS.3 reserve=9 on 8 cores exits 2 and leaves the file as it was" \
  "2|2" "$SS_RC|$(sed -n 1p "$SS_CFG/bionic/reserve")"
ss_res() { printf '%s\n' "$1" > "$SS_CFG/bionic/reserve"; ss_verb reserve="$1" >/dev/null; echo "$?|$(ss_verb | sed -n 's/.* reserve=\([^ ]*\) .*/\1/p')"; }
expect_eq "SS.4 the verb and gate_reserve (its print) judge a reserve alike: ten characters refused by both (2, read 1), 2.5 taken by both" \
  "2|1 0|2.5" "$(ss_res 0000000002) $(ss_res 2.5)"
# ============================================================
section "Section 41: the quiet Patrol, tick side — prompt, band, hold, digest, version (wave-24 T7; REQ-4 AC-4.1–4.6, 4.9, 4.11; D1, D4, D5; ADR-041)"
# ============================================================
#
# THE DEFECT (research-R1). The prompt asked for a `fill-declined:` line on every tick, so all 29
# declines of the 1.8.10 run answered nothing the wall asked; the band ignored STANDDOWN, so
# `decision=QUIET` printed under a stand-down; and the tick wrote a fresh stop order for the
# same finished agent every tick, with no answer that lasted past one turn. The fix: a hold on
# the roster row that stands while its fingerprint does, a digest that makes an unchanged tick
# one line, and a prompt that asks only for what the tick printed.
#
# FIXTURE FIDELITY. Every fixture is SYNTHESIZED in this suite's own sandbox: the roster rows
# through `roster_row` (tests/lib/roster-row.sh), the panel through tests/lib/live-answer.sh's
# committed corpus, the completion message in the `<teammate-message>` envelope §30b plants (the
# shape the CLI writes, measured wave-20 T9b). The hold and the stand-down are written by the
# REAL verbs. §41c's Stop drive is the shipped hooks/stop.sh on a tick turn built the way
# tests/cross-gate-agreement.test.sh's CG-standdown builds one.
#
# ANTI-VACUITY. Every absence beside a positive on the same output: §41c's "no STANDDOWN" sits
# beside its `held w-1` count, and its Stop pass beside §41b's Stop refusal on the same drive.

S41_CFG="$(fake_config_dir s41-quiet)"
# THE SHARE IS FIXTURE DATA (wave-31 T36; A-T36-3). 41h drives a 90% reading against the share, and the
# gate's default is now 92 (D8), so the section pins 80 as §40 does and as the prelude's dir does.
mkdir -p "$S41_CFG/bionic"; printf '80\n' > "$S41_CFG/bionic/share"
export CLAUDE_CONFIG_DIR="$S41_CFG"
S41_TR="$S41_CFG/projects/-fixture-project/$SID.jsonl"
orders_of() { printf '%s/.bionic/tmp/stop-orders-%s.state' "$1" "${2:-$SID}"; }
s41_msg() {  # <name> -> one completion message from <name>, in the envelope the CLI writes
  jq -nc --arg b "<teammate-message teammate_id=\"$1\" color=\"blue\" summary=\"r\">
report
</teammate-message>" '{type:"user",timestamp:"2026-09-05T00:50:10.000Z",message:{role:"user",content:$b}}'
}
s41_transcript() {  # <messages from w-1> <name:status>... -> this session's transcript, panel fresh
  local n="$1" i tmp="$TMPROOT/s41.panel"; shift
  plant_answer "$tmp" fresh "$@"
  { head -1 "$tmp"; i=0; while [ "$i" -lt "$n" ]; do s41_msg w-1; i=$((i + 1)); done; tail -n +2 "$tmp"; } > "$S41_TR"
}
# A LIVE LEDGER WITH NO GAP: writers=1, one ready row, and the MET row still unacked holds the
# slot — so the tick names no FILL and the stop wall's fill duty owes nothing.
s41_world() {  # <label> -> a repo: armed, bound, w-1 MET with a landed deliverable
  local r; r="$(make_repo "$1")"; new_roster "$r"; armed_ago "$r"
  local p; p="$(wave_plan_at "$r" "epic-99-fixture/wave-41.plan.md" \
    "writers=1 suites=2 worktrees=8 test_jobs=8 source=user" \
    "| R1 | 4 | build | ready row | implementor | — | 15m | REQ-x | r1.sh | pending |")"
  bind_marker "$r" "$p"
  echo "done" > "$r/w1-report.md"; backdate "$r/w1-report.md" 300
  add_row "$r" name=w-1 agent_id=aw1-41414141414141 deliverable="$r/w1-report.md" \
    duration="4 hours" launched_at="$(iso_ago 600)" "$(said "$r" w-1)"
  printf '%s' "$r"
}
s41_count() {  # <text> <fixed string> -> lines carrying it
  printf '%s\n' "$1" | grep -cF -- "$2" | tr -d ' '
}

# ---------- §PROMPT (AC-4.1; D5): the prompt asks only for what the tick printed ----------
R41P="$(make_repo s41-prompt)"
poke "$R41P" prompt
S41_PROMPT="$OUT"
expect_nonempty "41a precondition: the prompt printed" "$S41_PROMPT"
expect_contains "41a4 …and the fill answer is still named" 'Answer a FILL only if a "poker: FILL" line printed' "$S41_PROMPT"
expect_absent "41a4b …and names no decline" 'decline' "$S41_PROMPT"
expect_regex "41a7 AC-4.11 …and it carries its version after the session token" \
  "^bionic-patrol session=${SID:0:8} v=[0-9]+ — " "$S41_PROMPT"

# ---------- §BAND (AC-4.2; D4): a stand-down raises the band ----------
R41B="$(s41_world s41-band)"
s41_transcript 1 "w-1:idle"
poke "$R41B" tick
S41B_OUT="$OUT"
expect_contains "41b precondition: the MET row on the panel is stood down" "poker: STANDDOWN w-1" "$S41B_OUT"
expect_contains "41b AC-4.2 …and the decision says so" "decision=STANDDOWN" "$S41B_OUT"
expect_absent "41b2 …never QUIET beside a STANDDOWN line" "decision=QUIET" "$S41B_OUT"
expect_contains "41b3 …and the order is written" "target=w-1" "$(cat "$(orders_of "$R41B")" 2>/dev/null)"
expect_contains "41b4 AC-4.12 …and the STANDDOWN line names the standing answer" "hold w-1" "$S41B_OUT"

# The tick turn the stop wall judges: the Patrol prompt, the tick's Bash call and its output,
# and the task-list refresh — no decline text anywhere.
S41_STOP="${BIONIC_HOOKS_DIR}/stop.sh"
s41_turn() {  # <repo> <tick output> -> the transcript path
  local tr="$1/s41-turn.jsonl"
  {
    jq -nc --arg t "$S41_PROMPT" '{type:"user",isMeta:true,isSidechain:false,userType:"external",message:{role:"user",content:$t}}'
    jq -nc --arg c "bash $POKER tick" '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01S41TICK",name:"Bash",input:{command:$c}}]}}'
    jq -nc --arg o "$2" '{type:"user",isSidechain:false,message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_01S41TICK",content:$o}]}}'
    jq -nc '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01S41TL",name:"TaskList",input:{}}]}}'
    jq -nc '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"text",text:"Continuing."}]}}'
  } > "$tr"
  printf '%s' "$tr"
}
s41_stop() {  # <repo> <transcript> -> sets S41_STOP_OUT
  S41_STOP_OUT="$(jq -nc --arg t "$2" --arg c "$1" --arg s "$SID" \
      '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:"Stop",stop_hook_active:false}' \
    | env CLAUDE_CODE_SESSION_ID="$SID" bash "$S41_STOP" 2>/dev/null)"
}
s41_stop "$R41B" "$(s41_turn "$R41B" "$S41B_OUT")"
expect_contains "41b5 the CONTROL: the real stop wall refuses an unanswered stand-down on this drive" \
  "stand-down unanswered" "$(printf '%s' "$S41_STOP_OUT" | jq -r '.reason // ""' 2>/dev/null)"

# ---------- §HOLD-fix (wave-24 T27; critic I4): one pasteable hold line at all three sites ----------
# The tick's STANDDOWN line, the stop wall's stand-down refusal and the Patrol prompt each print
# the hold command. A bare `<reason>` pasted as printed is a redirect from a file named `reason`;
# each site now prints the reason as the one quoted placeholder. The tick's and the wall's lines
# carry the real name and parse, as a pasting shell parses them, into exactly five arguments.
s41_hold_argv() {  # <text> -> the first `bash …session-poker.sh hold …` command in it, as argc|name|reason
  local l
  l="$(printf '%s\n' "$1" | /usr/bin/grep -o "bash [^ ]*session-poker.sh hold [A-Za-z0-9_.-]* 'why it stays up'" | head -1)"
  [ -n "$l" ] || return 0
  eval "set -- $l"
  printf '%s|%s|%s' "$#" "$4" "$5"
}
S41B_WALL="$(printf '%s' "$S41_STOP_OUT" | jq -r '.reason // ""' 2>/dev/null)"
expect_eq "41b6 critic I4 the tick's STANDDOWN line pastes as one hold of w-1 with a quoted reason" \
  "5|w-1|why it stays up" "$(s41_hold_argv "$S41B_OUT")"
expect_eq "41b7 …and the stop wall's refusal prints the same command for the same row" \
  "5|w-1|why it stays up" "$(s41_hold_argv "$S41B_WALL")"

# ---------- §HOLD (AC-4.3; D1): a hold stands, prints once, and the turn ends ----------
R41H="$(s41_world s41-hold)"
s41_transcript 1 "w-1:idle"
poke "$R41H" hold w-1 "addendum"
expect_eq "41c the hold verb exits 0" "0" "$RC"
S41H_ROW="$(grep -F '|name=w-1|' "$(roster_of "$R41H")" | tail -1)"
expect_regex "41c2 …and appends the row with held=<at> <reason> fp=<launch>:<mtime>:<count>" \
  '\|held=[0-9TZ:-]+ addendum fp=[0-9TZ:-]+:[0-9]+:1\|' "$S41H_ROW"
poke "$R41H" tick
S41H_T1="$OUT"
poke "$R41H" tick
S41H_T2="$OUT"
expect_eq "41c3 two ticks print exactly one held note" "1" \
  "$(s41_count "$S41H_T1
$S41H_T2" "poker: held w-1 since ")"
expect_contains "41c4 …which carries the reason" "— addendum" "$S41H_T1"
expect_absent "41c5 …and neither tick stands it down" "poker: STANDDOWN" "$S41H_T1$S41H_T2"
expect_absent "41c6 …nor writes it an order" "target=w-1" "$(cat "$(orders_of "$R41H")" 2>/dev/null)"
s41_stop "$R41H" "$(s41_turn "$R41H" "$S41H_T1")"
expect_eq "41c7 AC-4.3 the real stop wall ends the held tick's turn with no decline text" "" \
  "$(printf '%s' "$S41_STOP_OUT" | jq -r '.decision // ""' 2>/dev/null)"
# A successor row (a re-dispatch's, or `extend`'s) is a new contract and carries no hold (D1).
poke "$R41H" extend w-1 "more work"
expect_absent "41c8 the copy a successor row takes drops held=" "held=" \
  "$(grep -F '|name=w-1|' "$(roster_of "$R41H")" | tail -1)"
expect_contains "41c9 …while the row it copied from carried it" "held=" "$S41H_ROW"
poke "$R41H" hold w-nobody "x"
expect_eq "41c10 hold refuses a name with no row (exit 1)" "1" "$RC"
# A REASON THAT IS ONLY BLANKS IS NO REASON (wave-24 T27; Step-6 review C3): the tick would
# print a hold with nothing after its dash. The usage error, and no row is written.
poke "$R41H" hold w-1 "   "
expect_eq "41c11 C3 hold with a blank reason is the usage error (exit 2)" "2" "$RC"
poke "$R41H" hold w-1 "
"
expect_eq "41c12 C3 …and so is one of tabs and line breaks" "2" "$RC"

# ---------- §HOLD-fp (AC-4.4; D1): each fingerprint component voids the hold ----------
s41_fp_case() {  # <label> <change command, eval'd with R set> 
  local R; R="$(s41_world "s41-fp-$1")"
  s41_transcript 1 "w-1:idle"
  poke "$R" hold w-1 "idle on purpose"
  poke "$R" tick
  expect_contains "41d-$1 precondition: held before the change" "poker: held w-1 since " "$OUT"
  eval "$2"
  poke "$R" tick
  expect_contains "41d-$1 AC-4.4 after the change the row is stood down again" "poker: STANDDOWN w-1" "$OUT"
  expect_contains "41d-$1 …and the order returns" "target=w-1" "$(cat "$(orders_of "$R")" 2>/dev/null)"
}
# The launch moves while the held= string is carried verbatim, so only the comparison can see it.
s41_fp_case launch 'grep -F "|name=w-1|" "$(roster_of "$R")" | tail -1 | sed "s/|launched_at=[^|]*|/|launched_at=$(iso_ago 500)|/" >> "$(roster_of "$R")"'
s41_fp_case mtime 'backdate "$R/w1-report.md" 200'
s41_fp_case message 's41_transcript 2 "w-1:idle"'

# ---------- §DECLINE-tick (wave-26 T15, AC-4.6; D16): a stand-down decline stands as a hold does ----------
# The decline used to answer its own turn only: the next tick ordered the same unchanged agent
# down again. The stop wall now writes the decline to the roster as `hold` writes it, so the real
# tick reads it through the hold's own fingerprint check. The second turn, with the agent
# unchanged, is not refused. A new message from the agent is a changed agent, and its turn is.
R41DC="$(s41_world s41-decline)"
s41_transcript 1 "w-1:idle"
poke "$R41DC" tick
expect_contains "41dc precondition: the tick stands w-1 down" "poker: STANDDOWN w-1" "$OUT"
S41DC_TR="$(s41_turn "$R41DC" "$OUT")"
jq -nc '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"text",text:"standdown-declined: w-1 is kept for a second pass"}]}}' >> "$S41DC_TR"
s41_stop "$R41DC" "$S41DC_TR"
expect_eq "41dc2 the declining turn ends" "" "$(printf '%s' "$S41_STOP_OUT" | jq -r '.decision // ""' 2>/dev/null)"
# An unrelated row joins, so the next tick prints in full rather than `unchanged` (an unchanged
# tick writes no order whatever the answer was) and has to decide w-1 again.
add_row "$R41DC" name=busy2 deliverable="$R41DC/never-written-2.md" duration="4 hours" launched_at="$(iso_ago 60)"
s41_transcript 1 "w-1:idle" "busy2:running"
poke "$R41DC" tick
expect_absent "41dc3 precondition: the tick prints in full" "unchanged since" "$OUT"
expect_contains "41dc3 AC-4.6 the next tick reads the decline as a hold" "poker: held w-1 since " "$OUT"
expect_absent "41dc4 …and does not stand w-1 down again" "poker: STANDDOWN" "$OUT"
s41_stop "$R41DC" "$(s41_turn "$R41DC" "$OUT")"
expect_eq "41dc5 AC-4.6 the second turn, same agent and no decline text, is not refused" "" \
  "$(printf '%s' "$S41_STOP_OUT" | jq -r '.decision // ""' 2>/dev/null)"
s41_transcript 2 "w-1:idle" "busy2:running"
poke "$R41DC" tick
expect_contains "41dc6 a new message from w-1 voids the decline: the tick stands it down" "poker: STANDDOWN w-1" "$OUT"
s41_stop "$R41DC" "$(s41_turn "$R41DC" "$OUT")"
expect_contains "41dc7 …and that turn, with no answer, is refused" "stand-down unanswered" \
  "$(printf '%s' "$S41_STOP_OUT" | jq -r '.reason // ""' 2>/dev/null)"

# ---------- §HOLD-idle (AC-4.5; D1): a held idle row is not re-opened ----------
R41I="$(s41_world s41-hold-idle)"
s41_transcript 1 "w-1:idle"
poke "$R41I" hold w-1 "auditor kept for a second pass"
poke "$R41I" tick
S41I_T1="$OUT"
rm -f "$(digest_of "$R41I")"
poke "$R41I" tick
expect_contains "41e precondition: the held row prints its note" "poker: held w-1 since " "$S41I_T1$OUT"
expect_absent "41e AC-4.5 two ticks over a held idle row draw no NOTIFY" "NOTIFY" "$S41I_T1$OUT"

# ---------- §DIGEST (AC-4.9; D4): an unchanged tick is one line ----------
R41D="$(make_repo s41-digest)"; new_roster "$R41D"; armed_ago "$R41D"
add_row "$R41D" name=busy deliverable="$R41D/never-written.md" duration="4 hours" \
  launched_at="$(iso_ago 60)"
plant_answer "$S41_TR" fresh "busy:running"
expect_contains "41f precondition: arm recorded the prompt version" "prompt_version=" \
  "$(cat "$(digest_of "$R41D")" 2>/dev/null)"
poke "$R41D" tick
S41D_T1="$OUT"
expect_contains "41f2 the first tick prints its decision" "decision=QUIET" "$S41D_T1"
expect_contains "41f3 …and, QUIET with a row open, prints WAITING (wave-26 T15; D16)" "poker: WAITING" "$S41D_T1"
expect_contains "41f3b …and owes no task-list duty" "duty=none" "$(cat "$(digest_of "$R41D")" 2>/dev/null)"
poke "$R41D" tick
# From wave-38 T11 (D13, A-T11-7, A-T11-8) a tick on a plan also prints the run's one-line sitrep above the
# unchanged line, which asks nothing (sitrep.test.sh S6 pins that two-line tick). This world binds no plan, so
# its unchanged tick is still the one line; the unchanged line is byte-identical and last either way.
expect_eq "41f4 AC-4.9 with no plan to report on, the second tick's stdout is exactly one line" "1" \
  "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
expect_regex "41f5 …and the last line is the unchanged line" \
  "^poker: unchanged since [0-9TZ:-]+ — decision=QUIET$" "$(printf '%s\n' "$OUT" | tail -1)"
expect_contains "41f6 …and the duty is none" "duty=none" "$(cat "$(digest_of "$R41D")" 2>/dev/null)"
add_row "$R41D" name=busy2 deliverable="$R41D/never-written-2.md" duration="4 hours" \
  launched_at="$(iso_ago 60)"
poke "$R41D" tick
expect_absent "41f7 a new row is a change: the full tick prints" "unchanged since" "$OUT"
expect_contains "41f8 …with its decision line" "decision=" "$OUT"

# ---------- §PVER (AC-4.11; D5): a stale or missing prompt version asks for a re-arm ----------
R41V="$(make_repo s41-pver)"; new_roster "$R41V"
add_row "$R41V" name=busy deliverable="$R41V/never-written.md" duration="4 hours" \
  launched_at="$(iso_ago 60)"
poke "$R41V" tick
expect_eq "41g AC-4.11 a tick with no recorded version prints one re-arm line" "1" \
  "$(s41_count "$OUT" "re-arm the Patrol")"
printf 'patrol-digest/v1\nprompt_version=1\n' > "$(digest_of "$R41V")"
poke "$R41V" tick
expect_eq "41g2 …and so does a tick under an older version" "1" "$(s41_count "$OUT" "re-arm the Patrol")"
poke "$R41V" arm
poke "$R41V" tick
expect_eq "41g3 …and an armed one prints none" "0" "$(s41_count "$OUT" "re-arm the Patrol")"
expect_contains "41g4 …while still printing its decision" "decision=" "$OUT"
# ---------- §DIGEST-over (D4; wave-28 T13): a tick over the share prints in full every time ----------
R41X="$(make_repo s41-emergency)"; new_roster "$R41X"; armed_ago "$R41X"
add_row "$R41X" name=suite-writer deliverable="$R41X/never-written.md" duration="4 hours" \
  claims="bash tests/run.sh" launched_at="$(iso_ago 60)"
plant_answer "$S41_TR" fresh "suite-writer:running"
BIONIC_PROBE_USED_PCT=90 poke "$R41X" tick
expect_contains "41h precondition: the first tick over the share names what holds the memory" "poker: over share" "$OUT"
BIONIC_PROBE_USED_PCT=90 poke "$R41X" tick
expect_contains "41h2 the second tick over the same facts still prints in full" "poker: over share" "$OUT"
expect_absent "41h3 …never as unchanged" "unchanged since" "$OUT"
unset CLAUDE_CONFIG_DIR

# ============================================================
section "§NAMES-ACT: the tick's no-FILL lines name what the page or the log holds and the verb that writes it"
# ============================================================
# A run at 15 holds its approval in its log and its plan under the docs root, never in a state section, which the write
# hook refuses. A page whose log holds no approval, and a root that holds no plan, each name the verb that clears them.
# fails-when: a line names a state section, or names no verb.
export CLAUDE_CONFIG_DIR="$SP_CONFIG_DIR"
RNA="$(make_repo names-act)"; new_roster "$RNA"
SP_APPROVED_LINE="" sp_plan_at_step "$RNA" 4 "| T1 | 4 | build | the first | implementor | — | 30 | REQ-1 | a.sh | pending |" >/dev/null
poke "$RNA" tick; NA_FILL="$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: no FILL')"
expect_contains "NA-1 a page at 15 whose log holds no approval: the line names the approve verb" "approve plan '<" "$NA_FILL"
expect_absent "NA-1b …and no state section" "SDLC State" "$NA_FILL"
RNB="$(make_repo names-none)"; new_roster "$RNB"; poke "$RNB" tick
NA_NONE="$(printf '%s\n' "$OUT" | /usr/bin/grep -E '^poker: (note: no FILL|QUIET)')"
expect_contains "NA-2 a root with no run's plan: the FILL line and the QUIET line each name the bind verb" "2" "$(printf '%s\n' "$NA_NONE" | /usr/bin/grep -c 'bind <plan>')"
expect_absent "NA-2b …and no state section" "SDLC State" "$NA_NONE"

# ============================================================
finish
