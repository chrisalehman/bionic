#!/bin/bash
# Tests for hooks/session-poker.sh — shard 2 of 4: Sections 35 through 55.
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
section "Section 35: fill-report — missed opportunity, HOLD and declines, from the fill ledger (wave-20 REQ-5, AC-5.6; Δ2)"
# ============================================================
#
# THE MEASURE (ADR-036 decision 4). Every Stop of an engaged run appends a `fill-ledger/v1`
# line; `fill-report` folds the lines by turn key (the last line of a turn wins — a refused
# Stop and its re-entry are one turn), orders them by `at`, and gives each line the interval
# up to the next. Missed minutes are the intervals whose line is `state=ok`, `missed>0` and
# undeclined; HOLD minutes are `state=hold|emergency` with a row ready; declined minutes are
# listed per reason. While the run is open the last line's interval runs to now; once it is
# closed, nothing after the last line is counted.
#
# THE FIXTURE: 10 minutes missed and 5 of HOLD, with a superseded line inside the missed turn
# (at 10:02, missed=1) that an unfolded sum would count as 3.5 more minutes.
s35_iso_epoch() {  # <ISO Z> -> epoch seconds, BSD or GNU date
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || date -u -d "$1" +%s
}
s35_line() {  # <at> <turn> <state> <ready> <launched> <declined> <missed>
  printf 'fill-ledger/v1|at=%s|session=%s|turn=%s|current=5|state=%s|ceiling=8|width=8|open=2|free=6|ready=%s|launched=%s|declined=%s|missed=%s\n' \
    "$1" "$SID" "$2" "$3" "$4" "$5" "$6" "$7"
}
s35_fixture() {  # <repo> <last line's missed> -> the plan path; writes plan + ledger
  local r="$1" plan led
  plan="$(plan_at "$r" epic-99-fixture/wave-35-fill.plan.md "$(plan_body 5)")"
  led="$r/.bionic/docs/record/wave-35-fill/fill-ledger.log"
  mkdir -p "${led%/*}"
  {
    s35_line 2026-09-23T10:00:00Z u-t1 ok ''    W-T1 ''          0
    s35_line 2026-09-23T10:02:00Z u-t2 ok T2    ''   ''          1
    s35_line 2026-09-23T10:05:30Z u-t2 ok T2    ''   ''          1
    s35_line 2026-09-23T10:15:30Z u-t3 hold T4  ''   ''          1
    s35_line 2026-09-23T10:20:30Z u-t4 ok ''    W-T4 ''          0
    s35_line 2026-09-23T10:25:30Z u-t5 ok T5    ''   'mid-merge' 1
    s35_line 2026-09-23T10:30:30Z u-t6 ok T6    ''   ''          "$2"
  } > "$led"
  printf '%s' "$plan"
}
S35_NOW="$(( $(s35_iso_epoch 2026-09-23T10:30:30Z) + 120 ))"

R35="$(make_repo s35)"
P35="$(s35_fixture "$R35" 0)"
OUT="$( cd "$R35" && BIONIC_NOW_EPOCH="$S35_NOW" CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" fill-report "$P35" 2>&1 )"; RC=$?
expect_eq "35a fill-report exits 0" "0" "$RC"
expect_contains "35b AC-5.6 the fixture's 10 missed minutes, exactly" "missed=10|" "$OUT"
expect_contains "35c …and its 5 HOLD minutes, separately" "hold=5|" "$OUT"
expect_contains "35d …and the declined minutes, with their reason" "declined=5|" "$OUT"
expect_contains "35e …the reason listed on its own line" "mid-merge" "$OUT"
expect_contains "35f …the superseded line folded away: six turns, not seven" "turns=6|" "$OUT"
expect_contains "35g …the line is the report's schema" "fill-report/v1|plan=wave-35-fill|" "$OUT"

# 35h: THE OPEN RUN'S LAST INTERVAL RUNS TO NOW. The last line misses one ready row, two minutes
# ago: open, those two minutes are missed; closed, nothing after the last line counts.
R35H="$(make_repo s35h)"
P35H="$(s35_fixture "$R35H" 1)"
OUT="$( cd "$R35H" && BIONIC_NOW_EPOCH="$S35_NOW" CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" fill-report "$P35H" 2>&1 )"
expect_contains "35h an open run's last interval runs to now: 10 + 2 missed" "missed=12|" "$OUT"
printf '%s' "$(plan_body 9 'delivered: bionic 9.9.9; report: record/x.md')" > "$P35H"
OUT="$( cd "$R35H" && BIONIC_NOW_EPOCH="$S35_NOW" CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" fill-report "$P35H" 2>&1 )"
expect_contains "35i …and a delivered run's does not: 10 missed" "missed=10|" "$OUT"
expect_contains "35j …and says the run is closed" "open=no" "$OUT"

# 35k: WITH NO OPERAND, the session's own run — the bound plan, as every verb resolves it.
R35K="$(make_repo s35k)"
P35K="$(s35_fixture "$R35K" 0)"
bind_marker "$R35K" "$P35K"
OUT="$( cd "$R35K" && BIONIC_NOW_EPOCH="$S35_NOW" CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" fill-report 2>&1 )"
expect_contains "35k with no operand the bound run's ledger is read" "plan=wave-35-fill|" "$OUT"
expect_contains "35l …with the same answer" "missed=10|" "$OUT"

# 35m: a plan with no ledger yet says so, and reports zeros rather than failing.
R35M="$(make_repo s35m)"
P35M="$(plan_at "$R35M" epic-99-fixture/wave-36-none.plan.md "$(plan_body 5)")"
poke "$R35M" fill-report "$P35M"
expect_eq "35m a run with no ledger exits 0" "0" "$RC"
expect_contains "35n …and names the file it looked for" "record/wave-36-none/fill-ledger.log" "$OUT"

# 35o: an operand that names no plan is a refusal, exit 2.
poke "$R35M" fill-report "$R35M/no-such.plan.md"
expect_eq "35o a plan that does not exist is refused (exit 2)" "2" "$RC"
poke "$R35M" fill-report a b
expect_eq "35p two operands is a usage error (exit 2)" "2" "$RC"

# 35q: A REFUSED TURN IS ONE TURN IN THE REPORT, END TO END (wave-20 T11b; review R3, critic C1).
# The ledger above is hand-written; this one is written by the REAL stop hook over a transcript
# in the CLI's own shape. One prompt, a launch, a refusal (T2 ready and left out), the Stop
# hook's feedback record — the synthetic user record the CLI writes after every Stop refusal —
# a second launch, and the re-entry Stop. Two ledger lines, one prompt: the report counts one.
S35Q_STOP="$(dirname "$POKER")/stop.sh"
R35Q="$(make_repo s35q)"
P35Q="$(plan_at "$R35Q" epic-99-fixture/wave-35q-refused.plan.md "$(
  printf -- '---\ngoverning-skill: canonical-sdlc\nparallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=user\n---\n\n'
  plan_body 4
  printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | status | worktree |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| T1 | 4 | build | first | implementor | — | 30m | REQ-x | a.sh | pending | — |\n'
  printf '| T2 | 4 | build | second | implementor | — | 30m | REQ-x | b.sh | pending | — |\n')")"
bind_marker "$R35Q" "$P35Q"
roster_header > "$R35Q/.bionic/tmp/roster-$SID.state"
S35Q_TR="$R35Q/s35q-transcript.jsonl"
S35Q_RING="$TMPROOT/s35q.ring"; printf '1700000000|80|0|1.0|8\n' > "$S35Q_RING"
s35q_agent() {  # <tool_use id> <name>
  jq -nc --arg i "$1" --arg n "$2" '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:$i,name:"Agent",input:{name:$n,description:"task",subagent_type:"bionic:implementor",prompt:"x"}}]}}' >> "$S35Q_TR"
  jq -nc --arg i "$1" '{type:"user",isSidechain:false,message:{role:"user",content:[{type:"tool_result",tool_use_id:$i,is_error:false,content:"Spawned"}]}}' >> "$S35Q_TR"
  roster_row_fixture status=intended session="$SID" name="$2" agent_id="a${2}000000000001" deliverable= \
    >> "$R35Q/.bionic/tmp/roster-$SID.state"
}
s35q_stop() {  # <stop_hook_active true|false> -> the hook's stdout
  jq -nc --arg c "$R35Q" --arg s "$SID" --arg t "$S35Q_TR" --argjson a "$1" \
    '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:"Stop",stop_hook_active:$a}' \
    | ( cd "$R35Q" && env CLAUDE_CODE_SESSION_ID="$SID" BIONIC_PRESSURE_RING="$S35Q_RING" \
          BIONIC_NOW_EPOCH=1700000000 bash "$S35Q_STOP" 2>/dev/null )
}
jq -nc '{type:"user",uuid:"u-35q-1",timestamp:"2026-09-23T10:00:00.000Z",isSidechain:false,message:{role:"user",content:"dispatch the batch"}}' > "$S35Q_TR"
s35q_agent toolu_35Q1 W-T1
S35Q_OUT1="$(s35q_stop false)"
expect_contains "35q precondition: the first Stop is refused for the row left out" "ready with room:" "$S35Q_OUT1"
jq -nc '{type:"user",isMeta:true,uuid:"u-35q-fb",timestamp:"2026-09-23T10:00:30.000Z",isSidechain:false,userType:"external",message:{role:"user",content:"Stop hook feedback:\nbionic: stop refused — rows are ready"}}' >> "$S35Q_TR"
s35q_agent toolu_35Q2 W-T2
s35q_stop true >/dev/null
S35Q_LED="$R35Q/.bionic/docs/record/wave-35q-refused/fill-ledger.log"
OUT="$( cd "$R35Q" && BIONIC_NOW_EPOCH="$S35_NOW" CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" fill-report "$P35Q" 2>&1 )"
expect_contains "35r T11b fill-report folds the refused turn's two lines into one turn" "turns=1|" "$OUT"
expect_contains "35s …and the turn's final line is the one that saw both launches: nothing missed" \
  "|launched=W-T1,W-T2|" "$(tail -n 1 "$S35Q_LED" 2>/dev/null)"

# ---------- §REPORT (wave-26 T16, D17; AC-6.8): idle minutes and peak width, from stamps the code wrote ----------
#
# The ledger line ends with `idle=` (the ready rows no launch and no decline covered while a slot was
# free) and `room=`; `fill-report` adds `idle minutes: <n>` (the interval from a line whose idle= is
# non-empty to the next line, once per interval) and `peak width: <n>` (the most roster rows open at
# one instant: `launched_at` to the sweeper ledger's ack stamp, the one close rule; no ack, open to now).
#
# THE FIXTURE: idle=T2 at 10:00, then a 12-minute interval to 10:12 (an 8-minute one after it has
# idle= empty and counts nothing). Four roster rows: A 10:00-10:10, B 10:05-10:15, C 10:08-open,
# D 10:20-open. Three are open at 10:08-10:10 and never more, so the peak is 3: four rows launched
# would read 4, and the two open now would read 2.
s35r_line() {  # <at> <turn> <idle> <room>
  printf 'fill-ledger/v1|at=%s|session=%s|turn=%s|current=5|state=ok|ceiling=8|width=8|open=2|free=%s|ready=T2|launched=|declined=|missed=1|idle=%s|room=%s\n' \
    "$1" "$SID" "$2" "$4" "$3" "$4"
}
R35R="$(make_repo s35r)"
P35R="$(plan_at "$R35R" epic-99-fixture/wave-35-rp.plan.md "$(plan_body 5)")"
L35R="$R35R/.bionic/docs/record/wave-35-rp/fill-ledger.log"
mkdir -p "${L35R%/*}"
{
  s35r_line 2026-09-23T10:00:00Z u-r1 T2 3
  s35r_line 2026-09-23T10:12:00Z u-r2 ''  2
  s35r_line 2026-09-23T10:20:00Z u-r3 ''  0
} > "$L35R"
new_roster "$R35R"
add_row_to "$R35R" "$SID" name=rp-a launched_at=2026-09-23T10:00:00Z
add_row_to "$R35R" "$SID" name=rp-b launched_at=2026-09-23T10:05:00Z
add_row_to "$R35R" "$SID" name=rp-c launched_at=2026-09-23T10:08:00Z
add_row_to "$R35R" "$SID" name=rp-d launched_at=2026-09-23T10:20:00Z
s20_ack "$R35R" rp-a 2026-09-23T10:10:00Z
s20_ack "$R35R" rp-b 2026-09-23T10:15:00Z
OUT="$( cd "$R35R" && BIONIC_NOW_EPOCH="$S35_NOW" CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" fill-report "$P35R" 2>&1 )"; RC=$?
expect_eq "35t fill-report exits 0 on the idle/width fixture" "0" "$RC"
expect_contains "35u AC-6.8 the planted 12-minute interval, exactly" "idle minutes: 12" "$OUT"
expect_contains "35v AC-6.8 the instant three rows overlap, exactly" "peak width: 3" "$OUT"
# A PLAN THAT SAYS OTHERWISE CHANGES NOTHING: the report reads the ledger and the roster, never prose.
OUT_R1="$OUT"
printf '\nThe run sat idle for 99 minutes at 2026-01-01T00:00:00Z and ran 9 wide at 2026-01-01T00:00:00Z.\n' >> "$P35R"
OUT="$( cd "$R35R" && BIONIC_NOW_EPOCH="$S35_NOW" CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" fill-report "$P35R" 2>&1 )"
expect_eq "35w a plan carrying a misleading time and width changes nothing in the report" "$OUT_R1" "$OUT"
# THE ZERO CASE, so 35u cannot pass on a constant: no line names an idle row, and an old-shape line
# (no idle= field at all) reads as none. The roster is the same, so the width still reads 3.
R35Z="$(make_repo s35z)"
P35Z="$(plan_at "$R35Z" epic-99-fixture/wave-35-rz.plan.md "$(plan_body 5)")"
L35Z="$R35Z/.bionic/docs/record/wave-35-rz/fill-ledger.log"
mkdir -p "${L35Z%/*}"
{
  s35r_line 2026-09-23T10:00:00Z u-z1 '' 3
  s35_line 2026-09-23T10:12:00Z u-z2 ok T2 '' '' 1
} > "$L35Z"
cp "$(roster_of "$R35R")" "$(roster_of "$R35Z")"
cp "$(ack_ledger_of "$R35R")" "$(ack_ledger_of "$R35Z")"
OUT="$( cd "$R35Z" && BIONIC_NOW_EPOCH="$S35_NOW" CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" fill-report "$P35Z" 2>&1 )"
expect_contains "35x no idle row names a zero, and an old-shape line is none" "idle minutes: 0" "$OUT"
expect_contains "35y …while the same roster still reads its peak" "peak width: 3" "$OUT"

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
expect_contains "36e …and names the fill answer, the decline verb (wave-27 T34)" "session-poker.sh decline IDS" "$OUT"
OUT="$( cd "$R36" && CLAUDE_CODE_SESSION_ID="" bash "$POKER" prompt 2>&1 )"; RC=$?
expect_eq "36f with no session key there is no marker to print (exit 3)" "3" "$RC"
poke "$R36" prompt extra
expect_eq "36g prompt takes no arguments (exit 2)" "2" "$RC"


# ============================================================
section "Section 37: T10b — the release waits for its step and the tick names the hold; task-add keeps author text byte for byte (critic C3, review R6)"
# ============================================================
#
# C3: at current: 5, with its Step-5 dependency landed, the Step-7 release row (kind `doc`) was
# ready, so the tick ordered `FILL` for a release before any auditor or critic verdict. Δ6's
# accepted reading holds a gate act until `current:` reaches its step; the release is the
# Document step's gate act. The tick's no-FILL line now NAMES each row held for its step, so a
# reader of the line can tell "nothing is ready" from "the release waits for Step 7".
R37A="$(make_repo s37-held)"; new_roster "$R37A"
sp_plan_at_step "$R37A" 5 \
  "| T1 | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 5 | verify | the live bed, landed | implementor | T1 | 15m | REQ-x | — | landed |" \
  "| T3 | 7 | doc | Release 1.8.7 | implementor | T2 | 15m | REQ-x | CHANGELOG.md | pending |" > /dev/null
poke_pressure "$R37A" 8192 1.0 tick
expect_absent "37a C3 at current: 5 the landed-dep Step-7 release row is not filled" \
  "poker: FILL" "$OUT"
# A TABLE WITHOUT `reads` KEEPS THE RELEASE'S STEP HOLD (wave-26 T13, A-T13.1): it has no
# `approval:release` to wait on, so its step is the one thing holding it. The hold is named on
# the row's own WAIT line now, not inside the no-FILL sentence.

# 37c — AT ITS STEP THE RELEASE FILLS. Same table at current: 7.
R37C="$(make_repo s37-at-step)"; new_roster "$R37C"
sp_plan_at_step "$R37C" 7 \
  "| T1 | 4 | build | landed | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 5 | verify | the live bed, landed | implementor | T1 | 15m | REQ-x | — | landed |" \
  "| T3 | 7 | doc | Release 1.8.7 | implementor | T2 | 15m | REQ-x | CHANGELOG.md | pending |" > /dev/null
poke_pressure "$R37C" 8192 1.0 tick
expect_contains "37c at current: 7 the release row is filled" "poker: FILL T3" "$OUT"

# 37d–37f — TASK-ADD ACCEPTS A STEP-HELD ROW, AND KEEPS ITS TEXT (R6). The hold is a
# schedule fact, not a broken invariant, so the validator stays silent and the dry commit
# admits it. Author text reached awk through -v, which read `\n` and `\t` as escapes; now a
# backslash, an author-escaped `\|` and a `$` land in the row exactly as typed.
S37_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R37D="$(make_repo s37-task-add)"; ( cd "$R37D" && git commit -q --allow-empty -m init )
P37D="$(s34_plan "$R37D" 5)"
poke "$R37D" task-add T7 7 doc 'Release: match C:\new\table and a\|b for $5' bionic:implementor 'T5' 30 REQ-5 '—'
expect_eq "37d task-add of a Step-7 doc row at current: 5 is accepted (exit 0)" "0" "$RC"
expect_contains "37f …with its - T7: line" "- T7: pending dispatch — added by task-add" "$(cat "$P37D")"
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
# the enum, a landed row with no `- T<n>:` line, an active row whose agent cell names no row
# on this session's roster — and the tick prints each one, every interval, as
# `poker: LEDGER <id> <kind> [<value>]`, after the HELD lines and before the FILL line. The
# finding reaches the orchestrator, who owns the ledger, before a writer's commit meets it.
R39A="$(make_repo s39-ledger)"; new_roster "$R39A"
mkrow name=w-T2 agent_id=a-w-T2 >> "$(roster_of "$R39A")"
P39A="$(sp_plan_at_step "$R39A" 4 \
  "| T1 | 4 | build | landed, no line | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | active, launched | w-T2 | — | 15m | REQ-x | b.sh | active |" \
  "| T3 | 4 | build | active, agent names no roster row | implementor | — | 15m | REQ-x | c.sh | active |" \
  "| T4 | 4 | build | status off the enum | implementor | — | 15m | REQ-x | d.sh | doing |" \
  "| T5 | 4 | build | active, self-owned | — | — | 15m | REQ-x | e.sh | active |" \
  "| T6 | 4 | build | waits on CI | implementor | T1, ext:ci-6 | 15m | REQ-x | f.sh | pending |" \
  "| T7 | 4 | build | ordinary, ready | implementor | T1 | 15m | REQ-x | g.sh | pending |")"
poke_pressure "$R39A" 8192 1.0 tick
expect_contains "39a AC-4.2 a landed row with no line ticks a LEDGER line" "poker: LEDGER T1 evidence" "$OUT"
expect_contains "39b …an active row whose agent is not on the roster ticks a launch line, naming the cell" \
  "poker: LEDGER T3 launch implementor" "$OUT"
expect_contains "39c …a status off the enum ticks a status line, naming the value" "poker: LEDGER T4 status doing" "$OUT"
expect_absent "39d …the launched active row is not a finding" "poker: LEDGER T2" "$OUT"
expect_absent "39e …nor is the self-owned one" "poker: LEDGER T5" "$OUT"
expect_eq "39f …exactly three LEDGER lines" "3" "$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^poker: LEDGER ')"
S39_HELD="$(s38_line_no 'poker: HELD ')"; S39_LEDGER="$(s38_line_no 'poker: LEDGER ')"; S39_FILL="$(s38_line_no 'poker: FILL ')"
expect_true "39g …and the LEDGER lines sit after the HELD line and before the FILL line (held=$S39_HELD ledger=$S39_LEDGER fill=$S39_FILL)" \
  test "$S39_HELD" -gt 0 -a "$S39_LEDGER" -gt "$S39_HELD" -a "$S39_FILL" -gt "$S39_LEDGER"
expect_contains "39h …and the fill is unchanged by the lint" "poker: FILL T7" "$OUT"

# 39i — THE LEDGER REPAIRED: T1's line written, T3's cell naming its roster row, T4 back on
# the enum. No LEDGER line.
mkrow name=w-T3 agent_id=a-w-T3 >> "$(roster_of "$R39A")"
awk '{ print } $0 == "- Step 4: in progress" { print "- T1: bash suite 9/9 green" }' "$P39A" \
  | sed -e 's/| active, agent names no roster row | implementor |/| active, agent names no roster row | w-T3 |/' \
        -e 's/| d.sh | doing |/| d.sh | pending |/' > "$P39A.new" && mv "$P39A.new" "$P39A"
poke_pressure "$R39A" 8192 1.0 tick
expect_contains "39i precondition: T1's line is in the plan" "- T1: bash suite 9/9 green" "$(cat "$P39A")"
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
# THE AUDIT'S REFUTATION, PINNED (record/wave-21-fixit-188/audit-3b45d05.md). Through T5 the
# HELD and LEDGER lines printed only inside the FILL branch, and three reachable states never
# reach it: the first tick of a run (no roster file yet: rung, QUIET, exit), HOLD or EMERGENCY
# under machine pressure, and a plan with no `parallel-budget`. The commit gate reads the
# ledger in every one of them, so a plan the gate refused ticked clean. Every case here holds
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

# 40a — THE FIRST TICK: armed, nothing dispatched, no roster file. With no roster the reader
# takes its no-roster rule, the gate's: an agent-named active row with no line is an
# `evidence` finding, not a `launch` one.
R40A="$(make_repo s40-no-roster)"
poke "$R40A" arm
sp_plan_at_step "$R40A" 4 \
  "| T1 | 4 | build | landed, no line | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | waits on CI | implementor | T1, ext:ci-40a | 15m | REQ-x | b.sh | pending |" \
  "| T3 | 4 | build | active, agent-named, no line | w-T3 | — | 15m | REQ-x | c.sh | active |" > /dev/null
poke_pressure "$R40A" 8192 1.0 tick
expect_contains "40a AC-3.3 the first tick prints the ext:-held row's HELD line" "poker: HELD T2 ext:ci-40a" "$OUT"
expect_contains "40a2 AC-4.2 …and the landed row with no line ticks a LEDGER line" "poker: LEDGER T1 evidence" "$OUT"
expect_contains "40a3 AC-4.1 …and the agent-named active row owes its line, as the gate's no-roster rule says" \
  "poker: LEDGER T3 evidence" "$OUT"
expect_eq "40a4 …each HELD line once" "1" "$(s40_count 'poker: HELD ')"
expect_eq "40a5 …each LEDGER line once" "2" "$(s40_count 'poker: LEDGER ')"
S40_RUNG="$(s38_line_no 'poker: gate share=')"; S40_HELD="$(s38_line_no 'poker: HELD ')"
S40_LEDGER="$(s38_line_no 'poker: LEDGER ')"; S40_QUIET="$(s38_line_no 'poker: QUIET')"
expect_true "40a6 …after the gate line and before the QUIET line (gate=$S40_RUNG held=$S40_HELD ledger=$S40_LEDGER quiet=$S40_QUIET)" \
  test "$S40_RUNG" -gt 0 -a "$S40_HELD" -gt "$S40_RUNG" -a "$S40_LEDGER" -gt "$S40_HELD" -a "$S40_QUIET" -gt "$S40_LEDGER"

# 40b — NO ROOM: a roster, a ready row, and a five-minute load over the share. No fill, and
# the lint still runs: a busy machine has nothing to do with the ledger.
R40B="$(make_repo s40-hold)"; new_roster "$R40B"
sp_plan_at_step "$R40B" 4 \
  "| T1 | 4 | build | landed, no line | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | waits on CI | implementor | T1, ext:ci-40b | 15m | REQ-x | b.sh | pending |" \
  "| T3 | 4 | build | ordinary, ready | implementor | T1 | 15m | REQ-x | c.sh | pending |" > /dev/null
BIONIC_PROBE_BUSY_CORES_5M=7.0 poke "$R40B" tick
expect_absent "40b precondition: …and fills nothing" "poker: FILL" "$OUT"
expect_contains "40b AC-3.3 with no room the ext:-held row prints its HELD line" "poker: HELD T2 ext:ci-40b" "$OUT"
expect_contains "40b2 AC-4.2 …and the landed row with no line ticks a LEDGER line" "poker: LEDGER T1 evidence" "$OUT"
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
  "| T1 | 4 | build | landed, no line | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | waits on CI | implementor | T1, ext:ci-40c | 15m | REQ-x | b.sh | pending |" > /dev/null
BIONIC_PROBE_USED_PCT=90 poke "$R40C" tick
expect_contains "40c precondition: the tick is over the share" "poker: over share — used=90% admitted: none" "$OUT"
expect_contains "40c AC-3.3 over the share the ext:-held row prints its HELD line" "poker: HELD T2 ext:ci-40c" "$OUT"
expect_contains "40c2 AC-4.2 …and the landed row with no line ticks a LEDGER line" "poker: LEDGER T1 evidence" "$OUT"
expect_eq "40c3 …HELD once" "1" "$(s40_count 'poker: HELD ')"
expect_eq "40c4 …LEDGER once" "1" "$(s40_count 'poker: LEDGER ')"

# 40d — NO BUDGET: the plan carries no `parallel-budget:` line, so the fill arm takes its
# no-budget note — and the lint does not wait on a budget it has no use for.
R40D="$(make_repo s40-no-budget)"; new_roster "$R40D"
P40D="$(sp_plan_at_step "$R40D" 4 \
  "| T1 | 4 | build | landed, no line | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | waits on CI | implementor | T1, ext:ci-40d | 15m | REQ-x | b.sh | pending |")"
/usr/bin/grep -v '^parallel-budget:' "$P40D" > "$P40D.new" && mv "$P40D.new" "$P40D"
poke_pressure "$R40D" 8192 1.0 tick
expect_absent "40d precondition: the tick names no budget key on a plan with no line" "parallel-budget" "$OUT"
expect_contains "40d AC-3.3 with no budget the ext:-held row prints its HELD line" "poker: HELD T2 ext:ci-40d" "$OUT"
expect_contains "40d2 AC-4.2 …and the landed row with no line ticks a LEDGER line" "poker: LEDGER T1 evidence" "$OUT"
expect_eq "40d3 …HELD once" "1" "$(s40_count 'poker: HELD ')"
expect_eq "40d4 …LEDGER once" "1" "$(s40_count 'poker: LEDGER ')"

# 40e — DISARM: the terminal tick (critic-4e6d4a9 I3). An empty roster on a run that says it is
# delivered — `current: 9`, `delivered:` on the Step-9 line, armed before that — decides DISARM,
# and a delivered run whose ledger still carries a finding is one the gate would refuse, so this
# last tick says so. No other case ticks DISARM over a plan with a hold and a finding, so the
# report's call on that arm was unpinned: deleting it left every suite green.
R40E="$(make_repo s40-disarm)"; new_roster "$R40E"
armed_ago "$R40E"
P40E="$(sp_plan_at_step "$R40E" 9 \
  "| T1 | 4 | build | landed, no line | implementor | — | 15m | REQ-x | a.sh | landed |" \
  "| T2 | 4 | build | waits on CI | implementor | T1, ext:ci-40e | 15m | REQ-x | b.sh | pending |")"
sed -e 's/^- Step 9: in progress$/- Step 9: delivered: bionic 9.9.9; report: record\/fixture\/close-out.md/' \
  "$P40E" > "$P40E.new" && mv "$P40E.new" "$P40E" && touch "$P40E"
poke_pressure "$R40E" 8192 1.0 tick
expect_contains "40e precondition: the plan's Step-9 line records the delivery" \
  "- Step 9: delivered: bionic 9.9.9" "$(cat "$P40E")"
expect_contains "40e precondition: …and the tick decides DISARM" "decision=DISARM" "$OUT"
expect_contains "40e AC-3.3 the DISARM tick prints the ext:-held row's HELD line" "poker: HELD T2 ext:ci-40e" "$OUT"
expect_contains "40e2 AC-4.2 …and the landed row with no line ticks a LEDGER line" "poker: LEDGER T1 evidence" "$OUT"
expect_eq "40e3 …HELD once" "1" "$(s40_count 'poker: HELD ')"
expect_eq "40e4 …LEDGER once" "1" "$(s40_count 'poker: LEDGER ')"
S40_RUNG="$(s38_line_no 'poker: gate share=')"; S40_HELD="$(s38_line_no 'poker: HELD ')"
S40_LEDGER="$(s38_line_no 'poker: LEDGER ')"; S40_DISARM="$(s38_line_no 'poker: DISARM')"
expect_true "40e5 …after the gate line and before the DISARM line (gate=$S40_RUNG held=$S40_HELD ledger=$S40_LEDGER disarm=$S40_DISARM)" \
  test "$S40_RUNG" -gt 0 -a "$S40_HELD" -gt "$S40_RUNG" -a "$S40_LEDGER" -gt "$S40_HELD" -a "$S40_DISARM" -gt "$S40_LEDGER"
expect_contains "40f the section read its own share, never the machine's (the gate line names 80)" "poker: gate share=80" "$OUT"
unset CLAUDE_CONFIG_DIR
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
expect_contains "41a4 …and the fill answer is still named: the decline verb (wave-27 T34)" 'decline IDS' "$S41_PROMPT"
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
S41H_ROWS="$(grep -c '|name=w-1|' "$(roster_of "$R41H")")"
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

# ---------- §SD-tick (AC-4.7; D2): the tick prints the standing fill decline ----------
#
# THE DEFECT (wave-24 Step-6 review C2). The stop wall read the session's latest declined fill-
# ledger line as the standing answer for the ready rows it saw, and the tick read nothing: it
# still printed `FILL ONE` and `decision=FILL` for a row the wall treated as answered, so the
# prompt asked for the answer again. The tick now asks the same reader the wall asks
# (`fill_standing_decline`, lib/fill.sh), prints `fill-declined standing since <at> — <reason>`,
# and names no standing row in its FILL. The ledger line is the recorder's shape
# (stop.sh `stop_fill_ledger`); the plan is mk_rung_repo's, at `current: 4` with four ready rows.
s41_sd_line() {  # <repo> <session> <current> <ready> <declined>
  local d="$1/.bionic/docs/record/wave-01-fixture"
  mkdir -p "$d"
  printf 'fill-ledger/v1|at=2026-10-03T09:00:00Z|session=%s|turn=u-1|current=%s|state=ok|ceiling=8|width=8|open=0|free=8|ready=%s|launched=|declined=%s|missed=4\n' \
    "$2" "$3" "$4" "$5" >> "$d/fill-ledger.log"
}
s41_fill_line() { printf '%s\n' "$1" | /usr/bin/grep '^poker: FILL ' | head -1; }
# A DECLINE STANDS WHILE THE GATE GIVES NO ROOM (wave-37 T18; REQ-11 AC-11.4; D13). With room=yes and a writer
# slot free it lapses (tests/session-poker-4.test.sh §REOPEN), so the pins of what a standing decline answers read
# the tick at room=no (BIONIC_PROBE_BUSY_CORES_5M=8.0 over the rung fixture's share, session-poker.test.sh 11a), and the control ticks at room=yes.
R41S="$(mk_rung_repo s41-sd-some)"
s41_sd_line "$R41S" "$SID" 4 ONE,TWO "ONE and TWO wait on the BASE merge"
BIONIC_PROBE_BUSY_CORES_5M=8.0 poke_rung "$R41S" 60 0 tick
expect_eq "41i2 …and with no room names no FILL, the declined rows answered" "" "$(s41_fill_line "$OUT")"
forget_digest "$R41S"; poke_rung "$R41S" 60 0 tick
expect_contains "41i2b AC-11.4 …and with room and a free slot the decline lapses and the tick asks every ready row" \
  "poker: fill-declined lapsed — room=yes" "$OUT"
R41A="$(mk_rung_repo s41-sd-all)"
s41_sd_line "$R41A" "$SID" 4 ONE,TWO,THREE,FOUR "the batch waits on the BASE merge"
BIONIC_PROBE_BUSY_CORES_5M=8.0 poke_rung "$R41A" 60 0 tick
expect_eq "41i4 …and the tick prints no FILL line" "" "$(s41_fill_line "$OUT")"
expect_absent "41i5 …nor decision=FILL" "decision=FILL" "$OUT"
forget_digest "$R41A"; poke_rung "$R41A" 60 0 tick
# A moved current: is not one of the ways a line stands for nothing (wave-26 T15; D16).
R41M="$(mk_rung_repo s41-sd-moved)"
s41_sd_line "$R41M" "$SID" 3 ONE,TWO,THREE,FOUR "answered at an earlier step"
BIONIC_PROBE_BUSY_CORES_5M=8.0 poke_rung "$R41M" 60 0 tick
expect_contains "41i6 wave-26 T15 (D16) a decline taken at another current: still stands over the same ready set" \
  "fill-declined standing since " "$OUT"
expect_eq "41i7 …and the tick prints no FILL line" "" "$(s41_fill_line "$OUT")"
R41O="$(mk_rung_repo s41-sd-other)"
s41_sd_line "$R41O" "ffffffff-0000-4000-8000-000000000000" 4 ONE,TWO,THREE,FOUR "another session's answer"
poke_rung "$R41O" 60 0 tick
R41D2="$(mk_rung_repo s41-sd-dash)"
s41_sd_line "$R41D2" "$SID" 4 ONE,TWO,THREE,FOUR "—"
poke_rung "$R41D2" 60 0 tick
expect_absent "41i10 …and no standing line" "fill-declined standing" "$OUT"

# ============================================================
finish
