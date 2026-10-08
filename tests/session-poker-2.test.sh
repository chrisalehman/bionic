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
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/live-answer.sh"

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
expect_contains "35q precondition: the first Stop is refused for the row left out" "Fillable gap" "$S35Q_OUT1"
jq -nc '{type:"user",isMeta:true,uuid:"u-35q-fb",timestamp:"2026-09-23T10:00:30.000Z",isSidechain:false,userType:"external",message:{role:"user",content:"Stop hook feedback:\nbionic: stop refused — rows are ready"}}' >> "$S35Q_TR"
s35q_agent toolu_35Q2 W-T2
s35q_stop true >/dev/null
S35Q_LED="$R35Q/.bionic/docs/record/wave-35q-refused/fill-ledger.log"
expect_eq "35q …the two Stops wrote two ledger lines" "2" "$(grep -c '^fill-ledger/v1|' "$S35Q_LED" 2>/dev/null)"
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
expect_contains "37b …and the tick's WAIT line names the hold" \
  "T3 — step 7 doc row waits for current: 7" "$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: WAIT')"

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
expect_contains "37e R6 …and the task text lands byte for byte: backslashes, \\| and \$ intact" \
  '| T7 | 7 | doc | Release: match C:\new\table and a\|b for $5 | bionic:implementor | T5 | 30 | REQ-5 | — | — | — | pending |' \
  "$(cat "$P37D")"
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
expect_contains "40a precondition: the no-roster first tick decides QUIET" "poker: QUIET — armed, nothing dispatched yet on this session" "$OUT"
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
expect_contains "40b precondition: the gate gives no room" "poker: no FILL — the gate gives no room" "$OUT"
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
expect_absent "41a AC-4.1 the unconditional fill-declined sentence is gone" \
  'or write a line "fill-declined: <reason>"; TaskStop' "$S41_PROMPT"
expect_contains "41a2 …the fill answer is asked only when a FILL line printed" \
  'only if a "poker: FILL" line printed' "$S41_PROMPT"
expect_contains "41a3 …the stand-down answer only when a STANDDOWN line printed" \
  'only if a "poker: STANDDOWN" line printed' "$S41_PROMPT"
expect_contains "41a4 …and the fill answer is still named: the decline verb (wave-27 T34)" 'decline IDS' "$S41_PROMPT"
expect_contains "41a5 AC-4.12 …the stand-down answer names hold, its reason a quoted placeholder" "session-poker.sh hold NAME 'why it stays up'" "$S41_PROMPT"
expect_contains "41a6 AC-4.13 …ListAgents only when the roster has an open row" \
  "ListAgents only when the roster has an open row" "$S41_PROMPT"
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
expect_contains "41b8 …and the Patrol prompt carries the same reason placeholder" \
  "hold NAME 'why it stays up'" "$S41_PROMPT"

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
expect_eq "41c13 …and neither wrote a row" "$S41H_ROWS" "$(grep -c '|name=w-1|' "$(roster_of "$R41H")")"

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
expect_eq "41f4 AC-4.9 the second tick's stdout is exactly one line" "1" \
  "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
expect_regex "41f5 …and that line is the unchanged line" \
  "^poker: unchanged since [0-9TZ:-]+ — decision=QUIET$" "$OUT"
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
R41S="$(mk_rung_repo s41-sd-some)"
s41_sd_line "$R41S" "$SID" 4 ONE,TWO "ONE and TWO wait on the BASE merge"
poke_rung "$R41S" 60 0 tick
expect_contains "41i C2 AC-4.7 the tick prints the standing decline, its instant and its reason" \
  "poker: fill-declined standing since 2026-10-03T09:00:00Z — ONE and TWO wait on the BASE merge" "$OUT"
expect_eq "41i2 …and fills only the rows it did not answer" "poker: FILL THREE FOUR" "$(s41_fill_line "$OUT")"
R41A="$(mk_rung_repo s41-sd-all)"
s41_sd_line "$R41A" "$SID" 4 ONE,TWO,THREE,FOUR "the batch waits on the BASE merge"
poke_rung "$R41A" 60 0 tick
expect_contains "41i3 a decline that answered every ready row prints as standing" \
  "poker: fill-declined standing since 2026-10-03T09:00:00Z — the batch waits on the BASE merge" "$OUT"
expect_eq "41i4 …and the tick prints no FILL line" "" "$(s41_fill_line "$OUT")"
expect_absent "41i5 …nor decision=FILL" "decision=FILL" "$OUT"
# A moved current: is not one of the ways a line stands for nothing (wave-26 T15; D16).
R41M="$(mk_rung_repo s41-sd-moved)"
s41_sd_line "$R41M" "$SID" 3 ONE,TWO,THREE,FOUR "answered at an earlier step"
poke_rung "$R41M" 60 0 tick
expect_contains "41i6 wave-26 T15 (D16) a decline taken at another current: still stands over the same ready set" \
  "fill-declined standing since " "$OUT"
expect_eq "41i7 …and the tick prints no FILL line" "" "$(s41_fill_line "$OUT")"
R41O="$(mk_rung_repo s41-sd-other)"
s41_sd_line "$R41O" "ffffffff-0000-4000-8000-000000000000" 4 ONE,TWO,THREE,FOUR "another session's answer"
poke_rung "$R41O" 60 0 tick
expect_eq "41i8 another session's decline does not stand here" \
  "poker: FILL ONE TWO THREE FOUR" "$(s41_fill_line "$OUT")"
R41D2="$(mk_rung_repo s41-sd-dash)"
s41_sd_line "$R41D2" "$SID" 4 ONE,TWO,THREE,FOUR "—"
poke_rung "$R41D2" 60 0 tick
expect_eq "41i9 C4 a decline that is only a dash does not stand" \
  "poker: FILL ONE TWO THREE FOUR" "$(s41_fill_line "$OUT")"
expect_absent "41i10 …and no standing line" "fill-declined standing" "$OUT"

# ============================================================
section "Section 42: plan-row verbs — task-set, step-line, current, ledger-add, ledger-set (wave-24 T15; REQ-9 AC-9.1–9.3, 9.5, 9.6; D14)"
# ============================================================
#
# Five verbs replace the hand edits a run makes to its own plan: a `## Tasks` cell, a
# `- Step N:` or `- T<n>:` line, `current:`, and a `## Dispatch ledger` row. Each one is the
# task-add transaction (§34): projected onto a copy through units.sh, the copy judged by a dry
# commit through the REAL hooks/bash-walls.sh, the plan's checksum compared, and only then the
# swap. The fixture is §34's plan, which the real gate admits, plus a dispatch ledger, and it is
# committed so `git diff --numstat` can say exactly which lines a verb moved.
# HOISTED to tests/session-poker.prelude.sh: s42_plan, s42_numstat, s42_snap, s42_unchanged, s42_builds_landed — every later shard builds, snapshots and compares plans with them.
S42_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180

R42="$(make_repo s42-verbs)"; ( cd "$R42" && git commit -q --allow-empty -m init )
P42="$(s42_plan "$R42" 4)"
s34_gate "$R42"
expect_eq "42a precondition: the fixture plan is admitted by the real commit gate" "0" "$GATE_RC"
expect_eq "42a2 precondition: the fixture is committed, so a diff starts empty" "" "$(s42_numstat "$R42")"

# ---------- §VERB (AC-9.1): exactly those cells change; Files names amend ----------
poke "$R42" task-set T2 status=landed worktree=— base=def5678
expect_eq "42b §VERB AC-9.1 task-set of three cells exits 0" "0" "$RC"
expect_contains "42b2 …and says what it did" "task-set — T2" "$OUT"
expect_eq "42b3 …git diff --numstat shows one line" "1 1;" "$(s42_numstat "$R42")"
expect_contains "42b4 …and that line is the row with exactly those cells" \
  "| T2 | 4 | build | the second build | implementor | — | 30 | REQ-1 | b.sh | — | def5678 | landed |" "$(cat "$P42")"
s34_gate "$R42"
expect_eq "42b5 …and the next commit is admitted" "0" "$GATE_RC"
s42_snap "$R42" "$P42"
poke "$R42" task-set T5 Files=c.sh
s42_unchanged "42c §VERB Files= is refused" 1 "$P42"
expect_contains "42c2 …naming amend" "task-set does not write Files — widen a dispatched contract with amend" "$OUT"
poke "$R42" task-set T5 files=c.sh
s42_unchanged "42c3 §VERB …and so is files=, in any case" 1 "$P42"

# ---------- §VERB-bad (AC-9.2): refused, byte-identical ----------
poke "$R42" task-set T5 colour=red
s42_unchanged "42d §VERB-bad a column the header does not carry" 1 "$P42"
expect_contains "42d2 …naming it" "colour" "$OUT"
poke "$R42" task-set T99 status=landed
s42_unchanged "42d3 §VERB-bad an id the table does not carry" 1 "$P42"
poke "$R42" task-set T5 'task=a|b'
s42_unchanged "42d4 §VERB-bad a pipe in a value" 1 "$P42"
poke "$R42" task-set T5 "task=a
b"
s42_unchanged "42d5 §VERB-bad a newline in a value" 1 "$P42"
poke "$R42" task-set T5 status
s42_unchanged "42d6 §VERB-bad an operand with no =" 2 "$P42"
poke "$R42" task-set T5 id=T9
s42_unchanged "42d7 §VERB-bad the id is the row's key, not a cell to set" 1 "$P42"
poke "$R42" task-set T5 status=bogus
s42_unchanged "42d8 §VERB-bad a status the Task invariants refuse" 1 "$P42"
expect_contains "42d9 …in the validator's own words" "T5: status bogus is not one of" "$OUT"
poke "$R42" step-line T5 "a
b"
s42_unchanged "42d10 §VERB-bad a newline in a step line" 1 "$P42"
poke "$R42" step-line Q5 text
s42_unchanged "42d11 §VERB-bad a key that is neither a step number nor T<n>" 2 "$P42"
poke "$R42" ledger-add T1 agent=x
s42_unchanged "42d12 §VERB-bad ledger-add of an id the ledger already carries" 1 "$P42"
poke "$R42" ledger-set T7 landed=yes
s42_unchanged "42d13 §VERB-bad ledger-set of an id the ledger does not carry" 1 "$P42"
poke "$R42" ledger-set T1 colour=red
s42_unchanged "42d14 §VERB-bad ledger-set of a column the ledger does not carry" 1 "$P42"
poke "$R42" ledger-set T1 'notes=a|b'
s42_unchanged "42d15 §VERB-bad a pipe in a ledger value" 1 "$P42"
# THE ID IS AN OPERAND TOO (wave-24 T27; Step-6 review C1). `ledger-add` wrote its id into the
# new row unchecked: a line break in it forged a plan line past the commit gate, and a pipe a
# cell. Every row verb now judges the id by one grammar before any projection.
poke "$R42" ledger-add "T8
- Step 9: forged" agent=y
s42_unchanged "42d15b §VERB-bad C1 ledger-add of an id carrying a line break" 1 "$P42"
expect_contains "42d15c …naming the id grammar" "is not one row id" "$OUT"
poke "$R42" ledger-add 'T9|x' agent=y
s42_unchanged "42d15d §VERB-bad C1 ledger-add of an id carrying a pipe" 1 "$P42"
poke "$R42" ledger-add 'T9 x' agent=y
s42_unchanged "42d15e §VERB-bad C1 ledger-add of an id of two words" 1 "$P42"
# THE GRAMMAR IS ASCII UNDER ANY LOCALE (wave-24 T29; critic addendum A3). `[A-Za-z]` is a
# collation range, and /bin/bash 3.2 under a UTF-8 locale let é, ö, ß and a fullwidth Ｔ
# through, so `Ｔ9` keyed a row that reads as T9. Driven by /bin/bash itself under UTF-8.
s42_u8() {  # <verb args...> -> sets OUT, RC; /bin/bash 3.2, a UTF-8 locale
  OUT="$( cd "$R42" && env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 CLAUDE_CODE_SESSION_ID="$SID" /bin/bash "$POKER" "$@" 2>&1 )"; RC=$?
}
for _s42_id in 'é9' 'Tö' 'Ｔ9' 'T9ß'; do
  s42_u8 ledger-add "$_s42_id" agent=y
  s42_unchanged "42d15i §VERB-bad A3 ledger-add of the non-ASCII id $_s42_id under /bin/bash and UTF-8" 1 "$P42"
done
poke "$R42" ledger-set 'T1|x' notes=y
s42_unchanged "42d15f §VERB-bad C1 ledger-set of an id carrying a pipe" 1 "$P42"
poke "$R42" task-set "T5
x" size=45
s42_unchanged "42d15g §VERB-bad C1 task-set of an id carrying a line break" 1 "$P42"
poke "$R42" ledger-set T1 "notes
- Step 9: forged=y"
s42_unchanged "42d15h §VERB-bad C1 a column name carrying a line break" 1 "$P42"
expect_contains "42d15i …naming the column, not the value" "the column name" "$OUT"

# THE DRY COMMIT IS REAL: a valid cell on a plan the gate refuses — its Step-4 block has lost
# its base-sha, which no table check reads (§34e's fixture) — is refused in the gate's words.
R42E="$(make_repo s42-gate)"; ( cd "$R42E" && git commit -q --allow-empty -m init )
P42E="$(s42_plan "$R42E" 4 '  worktree: .worktrees/01-fixture
  branch: wave/01-fixture')"
s42_snap "$R42E" "$P42E"
poke "$R42E" task-set T5 size=45
s42_unchanged "42d16 §VERB-bad a valid cell on a plan the commit gate refuses" 1 "$P42E"
expect_contains "42d17 …in the gate's own words" "bionic: commit refused" "$OUT"
expect_contains "42d18 …naming the field it wants" "base-sha" "$OUT"
# …and the gate's placeholder arm, which the dry commit reaches only past the matrix: a row
# whose `- T<n>:` line is a placeholder refuses any write, naming the line.
R42P="$(make_repo s42-placeholder)"; ( cd "$R42P" && git commit -q --allow-empty -m init )
P42P="$(s42_plan "$R42P" 4)"
sed 's/^- T5: pending dispatch — .*$/- T5: TBD/' "$P42P" > "$P42P.tmp" && mv "$P42P.tmp" "$P42P"
s42_snap "$R42P" "$P42P"
expect_eq "42d19 precondition: the fixture's T5 line is a placeholder" "1" "$(grep -cx -- '- T5: TBD' "$P42P")"
poke "$R42P" task-set T5 size=45
s42_unchanged "42d20 §VERB-bad a write to a plan with a placeholder task line" 1 "$P42P"
expect_contains "42d21 …in the gate's own words" "dispatched task T5 evidence line is a placeholder ('TBD')" "$OUT"
s42_snap "$R42" "$P42"

# ---------- §VERB-race (AC-9.3): the plan touched between projection and swap ----------
# A `jq` on PATH that, the first time a process OTHER than this session's own poker calls it,
# appends a line to the plan before handing over to the real jq. The only such process is the
# dry commit's gate, which runs after the projection and before the swap — so the line lands
# in exactly the window the checksum guards.
mkdir -p "$TMPROOT/s42-shim"
cat > "$TMPROOT/s42-shim/jq" <<'SH'
#!/bin/bash
if [ "${CLAUDE_CODE_SESSION_ID:-}" != "$S42_SID" ] && [ ! -e "$S42_RACE_DONE" ]; then
  : > "$S42_RACE_DONE"
  printf '%s\n' '<!-- a concurrent edit -->' >> "$S42_RACE_PLAN"
fi
exec "$S42_REAL_JQ" "$@"
SH
chmod +x "$TMPROOT/s42-shim/jq"
export S42_SID="$SID" S42_REAL_JQ="$(command -v jq)" S42_RACE_DONE="$TMPROOT/s42-race-done" S42_RACE_PLAN="$P42"
S42_PATH_WAS="$PATH"; PATH="$TMPROOT/s42-shim:$PATH"
poke "$R42" task-set T5 size=45
PATH="$S42_PATH_WAS"
expect_eq "42e precondition: the concurrent edit landed during the dry commit" "yes" \
  "$([ -e "$S42_RACE_DONE" ] && echo yes)"
expect_eq "42e2 §VERB-race AC-9.3 the verb is refused (exit 1)" "1" "$RC"
expect_contains "42e3 …saying the plan changed" "changed while" "$OUT"
expect_contains "42e4 …the concurrent edit is intact" "<!-- a concurrent edit -->" "$(cat "$P42")"
expect_contains "42e5 …and the verb wrote nothing: T5 keeps its size" \
  "| T5 | 5 | verify | the floor | test-runner | T1, T2 | 30 |" "$(cat "$P42")"
poke "$R42" task-set T5 size=45
expect_eq "42e6 run again, it lands (exit 0)" "0" "$RC"
expect_contains "42e7 …the new cell is in" "| T5 | 5 | verify | the floor | test-runner | T1, T2 | 45 |" "$(cat "$P42")"
expect_contains "42e8 …beside the concurrent edit: nothing was lost" "<!-- a concurrent edit -->" "$(cat "$P42")"
s42_snap "$R42" "$P42"

# ---------- §VERB-cur (AC-9.5): current moves, 9 is close-out's ----------
poke "$R42" current 9
s42_unchanged "42f §VERB-cur AC-9.5 current 9 is refused" 1 "$P42"
expect_contains "42f2 …naming close-out" "close-out" "$OUT"
poke "$R42" current 5
s42_unchanged "42f3 §VERB-cur a move the gate refuses (no Step 5 block) is refused" 1 "$P42"
expect_contains "42f4 …in the gate's own words" "Step 5" "$OUT"
poke "$R42" current 4x
s42_unchanged "42f5 §VERB-cur a step that is neither N nor T<n>" 2 "$P42"

# The Step-4 block (A-orch-8): advancing to 4 writes the worktree/base-sha/branch fields the
# first writer's commit is refused without, from the run's own `working-branch:` — and only
# the fields the block lacks. The control is the same plan with no working-branch: line.
R42C="$(make_repo s42-cur)"
( cd "$R42C" && git commit -q --allow-empty -m init && git checkout -q -b wave/01-fixture )
P42C="$(s42_plan "$R42C" 3 '  note: the block owes its three fields')"
s42_snap "$R42C" "$P42C"
poke "$R42C" current 4
s42_unchanged "42f6 control: with no working-branch: line the block cannot be written, and current 4 is refused" 1 "$P42C"
expect_contains "42f7 …in the gate's own words, naming the missing fields" "base-sha" "$OUT"
awk '{ print } /^current: 3$/ { print "working-branch: wave/01-fixture" }' "$P42C" > "$P42C.tmp" && mv "$P42C.tmp" "$P42C"
s42_snap "$R42C" "$P42C"
poke "$R42C" current 4
expect_eq "42f8 §VERB-cur AC-9.5 current 4 from 3 exits 0" "0" "$RC"
expect_contains "42f9 …current: is 4" "current: 4" "$(cat "$P42C")"
expect_contains "42f10 …the Step-4 block carries its branch" "  branch: wave/01-fixture" "$(cat "$P42C")"
expect_contains "42f11 …its base-sha, the branch head at the advance" \
  "  base-sha: $(git -C "$R42C" rev-parse --short wave/01-fixture)" "$(cat "$P42C")"
expect_contains "42f12 …and its worktree, the checkout holding the branch" "  worktree: ." "$(cat "$P42C")"
# (wave-28 T8, A-orch-140: at wave scale the block gains a fourth line, share: <n>, D16's plan fact; §STEP-FIELD (share) pins it)
expect_eq "42f13 …and nothing else moved: current: plus the three fields and the share fact, four added lines" "5 1;" "$(s42_numstat "$R42C")"
s34_gate "$R42C"
expect_eq "42f14 …and the first Step-4 commit is admitted" "0" "$GATE_RC"

# ---------- §VERB-line (AC-9.6): step-line and the ledger verbs write only their line or row ----------
poke "$R42" step-line T2 'landed — def5678 on wt/01-T2'
expect_eq "42g §VERB-line step-line T2 exits 0" "0" "$RC"
expect_eq "42g2 AC-9.6 …one line replaced" "1 1;" "$(s42_numstat "$R42")"
expect_eq "42g3 …and it reads as written" "1" "$(grep -cx -- '- T2: landed — def5678 on wt/01-T2' "$P42")"
s42_snap "$R42" "$P42"
poke "$R42" step-line T2 'merge abc1234' --append
expect_eq "42g4 §VERB-line --append exits 0" "0" "$RC"
expect_eq "42g5 AC-9.6 …one line replaced" "1 1;" "$(s42_numstat "$R42")"
expect_eq "42g6 …the text appended to the line" "1" \
  "$(grep -cx -- '- T2: landed — def5678 on wt/01-T2; merge abc1234' "$P42")"
s42_snap "$R42" "$P42"
poke "$R42" step-line 5 opened
expect_eq "42g7 §VERB-line step-line of a step with no line exits 0" "0" "$RC"
expect_eq "42g8 AC-9.6 …one line added" "1 0;" "$(s42_numstat "$R42")"
expect_eq "42g9 …after the Step-4 block, not inside it" "- Step 5: opened" \
  "$(awk 'prev ~ /^  branch: / { print; exit } { prev = $0 }' "$P42")"
s42_snap "$R42" "$P42"
poke "$R42" ledger-add T2 'agent=implementor (w-T2)' dispatched=2026-10-03T01:00Z 'expected=30 min'
expect_eq "42g10 §VERB-line ledger-add exits 0" "0" "$RC"
expect_eq "42g11 AC-9.6 …one row added" "1 0;" "$(s42_numstat "$R42")"
expect_eq "42g12 …after the last row, the cells it was not given spelled —" \
  "| T2 | implementor (w-T2) | 2026-10-03T01:00Z | 30 min | — | — | — |" \
  "$(awk 'prev ~ /^\| T1 \| implementor \(w-T1\)/ { print; exit } { prev = $0 }' "$P42")"
s42_snap "$R42" "$P42"
poke "$R42" ledger-set T2 'landed=landed 2026-10-03T02:00Z (merge abc1234)'
expect_eq "42g13 §VERB-line ledger-set exits 0" "0" "$RC"
expect_eq "42g14 AC-9.6 …one row replaced" "1 1;" "$(s42_numstat "$R42")"
expect_eq "42g15 …the one cell set" "1" \
  "$(grep -cxF -- '| T2 | implementor (w-T2) | 2026-10-03T01:00Z | 30 min | — | landed 2026-10-03T02:00Z (merge abc1234) | — |' "$P42")"
# THE ID GRAMMAR ADMITS THE LEDGER'S OWN SHAPES (T27, C1's positive): a suffixed id is one token.
s42_snap "$R42" "$P42"
poke "$R42" ledger-add T2-critic agent=critic
expect_eq "42g15b §VERB-line ledger-add of a suffixed id (T2-critic) exits 0" "0" "$RC"
expect_eq "42g15c …one row added" "1 0;" "$(s42_numstat "$R42")"
# A3's positive, same driver as 42d15i: an ASCII id under /bin/bash and UTF-8 is admitted.
s42_u8 ledger-add T2-u8 agent=critic
expect_eq "42g15d …and the same /bin/bash UTF-8 driver admits an ASCII id (T2-u8)" "0" "$RC"
s34_gate "$R42"
expect_eq "42g16 …and after all five verbs the next commit is admitted" "0" "$GATE_RC"

# ---------- the refusals that precede any projection, and nothing left behind ----------
R42G="$(make_repo s42-unbound)"; ( cd "$R42G" && git commit -q --allow-empty -m init )
P42G="$(s42_plan "$R42G" 4)"; engage "$R42G"
s42_snap "$R42G" "$P42G"
poke "$R42G" task-set T5 size=45
s42_unchanged "42h an unbound session is refused and the newest plan is not written" 1 "$P42G"
expect_contains "42h2 …saying why" "bound" "$OUT"
expect_eq "42h3 no projection copy is left beside any plan" "" \
  "$(find "$R42" "$R42C" "$R42E" "$R42P" -name '*.plan.md.*' 2>/dev/null)"
expect_eq "42h4 …and no dry-run engagement marker is left in .bionic/tmp" "" \
  "$(find "$R42/.bionic/tmp" "$R42C/.bionic/tmp" -name 'engaged-*' ! -name "engaged-$SID.state" 2>/dev/null)"
POKE_BOUND="$S42_BOUND_WAS"

# ============================================================
section "Section 43: the Done marker travels with the contract — hold and amend keep it, extend drops it, adopt carries it (wave-24 T9, REQ-4 AC-4.8; D3; A-orch-31)"
# ============================================================
#
# The verdict reads the LATEST row for a name, so a successor row that dropped `done=` would
# un-say an agent that had said it was done: a held row would leave MET and never print held.
# `hold` and `amend` continue the contract and keep the marker; `extend` re-opens it for new
# work, launched now, which is signalled afresh; `adopt` files the same contract under a new
# session and carries it.
# fails-when: a successor row of hold/amend/adopt lacks done=, or extend keeps it.
S43_CFG="$(fake_config_dir s43-done)"
export CLAUDE_CONFIG_DIR="$S43_CFG"
s43_last() { grep -F "|name=${2:-w-1}|" "$(roster_of "$1")" | tail -1; }
s43_done() { printf '%s' "$1" | tr '|' '\n' | grep '^done=' | head -1 | cut -d= -f2-; }
R43="$(s41_world s43-hold)"
S41_TR="$S43_CFG/projects/-fixture-project/$SID.jsonl"; s41_transcript 1 "w-1:idle"
S43_MARK="$R43/w-1.done"
expect_eq "43a precondition: the launch row names its Done marker" "$S43_MARK" "$(s43_done "$(s43_last "$R43")")"
poke "$R43" hold w-1 "second pass"
expect_eq "43a2 precondition: the hold took (exit 0)" "0" "$RC"
expect_contains "43a3 …its row is the hold's" "held=" "$(s43_last "$R43")"
expect_eq "43a4 hold keeps the Done marker on its successor row" "$S43_MARK" "$(s43_done "$(s43_last "$R43")")"
poke "$R43" tick
expect_contains "43a5 …so the held row still reads MET and prints held" "poker: held w-1 since " "$OUT"
poke "$R43" extend w-1 "more work"
expect_contains "43b precondition: the extend took — its row is the latest" "extended=" "$(s43_last "$R43")"
expect_eq "43b2 extend drops the Done marker: new work is signalled afresh" "" "$(s43_done "$(s43_last "$R43")")"

R43M="$(make_repo s43-amend)"; new_roster "$R43M"
s30_row "$R43M" "$(said "$R43M" w1)"
poke "$R43M" amend w1 --files+ hooks/b.sh --reason 'the fix touches b'
expect_eq "43c precondition: the amend took (exit 0)" "0" "$RC"
expect_contains "43c2 …its row is the amend's" "amended=" "$(s43_last "$R43M" w1)"
expect_eq "43c3 amend keeps the Done marker on its successor row" "$R43M/w1.done" "$(s43_done "$(s43_last "$R43M" w1)")"

PRED_43="d6d6d6d6-1111-4bbb-8ccc-000000000043"
R43A="$(make_repo s43-adopt)"; new_roster "$R43A"
echo done > "$R43A/adopted.md"
add_row_to "$R43A" "$PRED_43" name=adopted-writer status=identified agent_id=aadopted-434343434343434 \
  subagent_type=bionic:implementor deliverable="$R43A/adopted.md" duration="45 minutes" \
  cadence="10 minutes" "$(said "$R43A" adopted-writer)"
poke "$R43A" adopt
expect_contains "43d precondition: the row was adopted onto this session's roster" "adopted_from=$PRED_43" \
  "$(s43_last "$R43A" adopted-writer)"
expect_eq "43d2 adopt carries the Done marker onto the adopted row" "$R43A/adopted-writer.done" \
  "$(s43_done "$(s43_last "$R43A" adopted-writer)")"
unset CLAUDE_CONFIG_DIR

# ============================================================
section "Section 44: the lines a reader pastes keep a plugin root with a space as one word (wave-24 T29; critic I2, A-T27.8)"
# ============================================================
#
# The Patrol prompt, the tick's STANDDOWN line and its re-arm note print the poker's own path
# for a reader to paste. They printed `${HOOK_DIR}` bare, so a plugin root with a space (a
# `--plugin-dir` checkout under `~/My Projects/`) split in two at the paste. The poker here
# runs from a COPY of the payload under `<tmp>/my plugin/`, the layout an installed plugin has.
# Each printed command is parsed the way a pasting shell reads it (`eval set --`, nothing run)
# and the script path must come back as ONE argument naming the real file.
# fails-when: a printed poker path splits at the space.
s44_args() { eval "set -- $1"; printf '%s\n' "$@"; }  # <command text> -> its words, one per line
s44_word() { printf '%s\n' "$1" | sed -n "${2}p"; }    # <words> <n> -> the n-th
S44_ROOT="$TMPROOT/my plugin"
cp -RL "$(cd "$(dirname "$POKER")/../payload" && pwd -P)" "$S44_ROOT"
S44_POKER_SAVED="$POKER"; POKER="$S44_ROOT/hooks/session-poker.sh"
expect_true "44 precondition: the poker under test is the copy under a root with a space" test -f "$POKER"
S44_CFG="$(fake_config_dir s44-root)"
export CLAUDE_CONFIG_DIR="$S44_CFG"
S41_TR="$S44_CFG/projects/-fixture-project/$SID.jsonl"

R44P="$(make_repo s44-prompt)"
poke "$R44P" prompt
S44_TICK="$(printf '%s\n' "$OUT" | sed -n 's/.*then run: \(bash .*\) tick — the tick decides.*/\1 tick/p')"
expect_nonempty "44a the prompt names the tick command" "$S44_TICK"
S44_W="$(s44_args "$S44_TICK")"
expect_eq "44a2 …which parses as bash, the script and tick" "3" "$(printf '%s\n' "$S44_W" | grep -c '')"
expect_contains "44a3 …its script path one argument, space and all" "my plugin/hooks/session-poker.sh" "$(s44_word "$S44_W" 2)"
expect_true "44a4 …naming the real file" test -f "$(s44_word "$S44_W" 2)"
S44_HOLD="$(printf '%s\n' "$OUT" | sed -n "s/.*the hold line it prints: \(bash .* hold NAME 'why it stays up'\),.*/\1/p")"
expect_nonempty "44b the prompt names the hold command" "$S44_HOLD"
S44_W="$(s44_args "$S44_HOLD")"
expect_eq "44b2 …which parses as bash, the script, hold, NAME and the reason" "5" "$(printf '%s\n' "$S44_W" | grep -c '')"
expect_true "44b3 …its script path one argument naming the real file" test -f "$(s44_word "$S44_W" 2)"

R44S="$(s41_world s44-standdown)"
s41_transcript 1 "w-1:idle"
poke "$R44S" tick
S44_SD="$(printf '%s\n' "$OUT" | grep -F 'poker: STANDDOWN w-1' | sed -n 's/.*keep it up with: //p')"
expect_nonempty "44c the tick's STANDDOWN line prints its hold command" "$S44_SD"
S44_W="$(s44_args "$S44_SD")"
expect_eq "44c2 …which parses as bash, the script, hold, the name and the reason" "5" "$(printf '%s\n' "$S44_W" | grep -c '')"
expect_true "44c3 …its script path one argument naming the real file" test -f "$(s44_word "$S44_W" 2)"
expect_eq "44c4 …and the name is the row's" "w-1" "$(s44_word "$S44_W" 4)"

R44V="$(make_repo s44-pver)"; new_roster "$R44V"
add_row "$R44V" name=busy deliverable="$R44V/never-written.md" duration="4 hours" \
  launched_at="$(iso_ago 60)"
poke "$R44V" tick
S44_RA="$(printf '%s\n' "$OUT" | grep -F 're-arm the Patrol')"
expect_nonempty "44d the tick prints its re-arm note" "$S44_RA"
S44_ARM="$(printf '%s\n' "$S44_RA" | sed -n 's/.*then run `\(bash [^`]*\)`.*/\1/p')"
S44_W="$(s44_args "$S44_ARM")"
expect_eq "44d2 …whose arm command parses as bash, the script and arm" "3" "$(printf '%s\n' "$S44_W" | grep -c '')"
expect_true "44d3 …its script path one argument naming the real file" test -f "$(s44_word "$S44_W" 2)"
POKER="$S44_POKER_SAVED"
unset CLAUDE_CONFIG_DIR

# ============================================================
section "Section 45 §GATE: a reserved request reaches the lead through the Patrol tick, once (wave-25 T5; REQ-4 AC-4.3; D7)"
# ============================================================
#
# THE GAP. hooks/permission-answer.sh denies a reserved action (anything that leaves the
# machine, credentials, billing, production infrastructure) and appends one gate line per
# distinct request to `.bionic/tmp/gate-<lead sid>.state`. Nothing read that file, so a writer's
# denied push reached the lead only if the writer's report happened to say so. The tick reads it
# now: a request no tick has raised yet makes the band NOTIFY, prints one GATE line, and puts
# `gate=<count>:<categories>` last on the decision line. The digest records it as raised, so no
# later tick raises it again, whatever else moved; a new line raises again, and only itself.
#
# FIXTURE FIDELITY. The world is §41's DIGEST world (one open row inside its duration, a fresh
# panel), so the band without the gate is QUIET and every NOTIFY here is the gate's. Gate lines
# are written in the hook's own shape (the plan's Interfaces table: `gate/v1|at=|session=|asker=
# |category=|head=`); §GATE-dup writes them with the REAL hook instead, fed the platform's
# PermissionRequest payload twice (the shape tests/permission-answer.test.sh §A15 drives).
#
# ANTI-VACUITY. The decision-line extractor is proven on the control tick (45a reads QUIET
# through it) before any `gate=` absence is read through it, and every absence of `gate=` or of
# a GATE line sits beside a positive `decision=` read through the same extractor on the same
# output. The hook drive asserts the line exists and has the gate/v1 shape beside its count.
# fails-when: the tick ignores the gate file, or the hook appends a duplicate.

S45_CFG="$(fake_config_dir s45-gate)"
export CLAUDE_CONFIG_DIR="$S45_CFG"
S45_TR="$S45_CFG/projects/-fixture-project/$SID.jsonl"
gate_of() { printf '%s/.bionic/tmp/gate-%s.state' "$1" "${2:-$SID}"; }
gate_line() {  # <asker> <category> <head> -> one request in the hook's shape
  printf 'gate/v1|at=2026-10-03T23:00:00Z|session=%s|asker=%s|category=%s|head=%s\n' "$SID" "$1" "$2" "$3"
}
s45_world() {  # <label> -> a repo: armed, one open row inside its duration
  local r; r="$(make_repo "$1")"; new_roster "$r"; armed_ago "$r"
  add_row "$r" name=busy deliverable="$r/never-written.md" duration="4 hours" \
    launched_at="$(iso_ago 60)"
  printf '%s' "$r"
}
s45_line()  { printf '%s\n' "$1" | grep '^poker-tick/v1|' | tail -1; }  # <output> -> the decision line
s45_field() { s45_line "$1" | tr '|' '\n' | sed -n "s/^$2=//p" | head -1; }  # <output> <key>
s45_gates() { printf '%s\n' "$1" | grep -c '^poker: GATE ' | tr -d ' '; }  # <output> -> GATE lines
plant_answer "$S45_TR" fresh "busy:running"

# ---------- §GATE-a: no file and an empty file change nothing; one line raises NOTIFY ----------
R45="$(s45_world s45-gate)"
poke "$R45" tick
expect_eq "45a precondition: no gate file, the band read off the decision line is QUIET (exit 0)" \
  "QUIET|0" "$(s45_field "$OUT" decision)|$RC"
expect_eq "45a2 …and the line carries no gate= field" "" "$(s45_field "$OUT" gate)"
: > "$(gate_of "$R45")"
poke "$R45" tick
expect_regex "45a3 an empty gate file adds nothing to the digest: the next tick is the unchanged line" \
  "^poker: unchanged since [0-9TZ:-]+ — decision=QUIET$" "$OUT"
gate_line w99-T1 leaves-the-machine "git push origin wave/99-fx" >> "$(gate_of "$R45")"
poke "$R45" tick
expect_eq "45b AC-4.3 a gate line makes the tick decide NOTIFY (exit 1)" "NOTIFY|1" \
  "$(s45_field "$OUT" decision)|$RC"
expect_eq "45b2 …with a gate= field: the count and the category" "1:leaves-the-machine" \
  "$(s45_field "$OUT" gate)"
expect_regex "45b3 …last on the line, after the fields that were there" \
  '\|decision=NOTIFY\|total=[0-9]+\|open=[0-9]+(\|[a-z]+=[^|]*)*\|gate=1:leaves-the-machine$' "$(s45_line "$OUT")"
expect_eq "45b4 …so the open= reader cross-gate's la6_open_tick uses still reads it" "1" \
  "$(s45_line "$OUT" | sed -n 's/.*decision=[A-Z]*|total=[0-9]*|open=\([0-9]*\).*/\1/p')"
expect_eq "45b5 …and one GATE line" "1" "$(s45_gates "$OUT")"
expect_contains "45b6 …naming the asker, the category and the command head" \
  "poker: GATE w99-T1 — leaves-the-machine: git push origin wave/99-fx" "$OUT"
expect_contains "45b7 …under a sentence that says what to do with it" "put each GATE line below to the human once" "$OUT"

# ---------- §GATE-once: the next tick does not repeat it, whatever else moved ----------
poke "$R45" tick
expect_regex "45c AC-4.3 the next tick with no new line does not repeat it: it is the unchanged line" \
  "^poker: unchanged since [0-9TZ:-]+ — decision=QUIET$" "$OUT"
expect_eq "45c2 …exit 0, not NOTIFY's 1" "0" "$RC"
add_row "$R45" name=busy2 deliverable="$R45/never-written-2.md" duration="4 hours" \
  launched_at="$(iso_ago 60)"
plant_answer "$S45_TR" fresh "busy:running" "busy2:running"
poke "$R45" tick
expect_eq "45c3 another fact moved, so the tick prints in full and decides on the rows" "QUIET" \
  "$(s45_field "$OUT" decision)"
expect_eq "45c4 …the request already raised is not raised again: no gate= field" "" "$(s45_field "$OUT" gate)"
expect_eq "45c5 …and no GATE line" "0" "$(s45_gates "$OUT")"
armed_ago "$R45"
poke "$R45" tick
expect_eq "45c6 a re-arm drops the digest's hash, so the next tick prints in full" "QUIET" \
  "$(s45_field "$OUT" decision)"
expect_eq "45c7 …and keeps what was raised: no gate= field" "" "$(s45_field "$OUT" gate)"

# ---------- §GATE-new: a new request raises again, and only itself ----------
gate_line lead credentials "cat ~/.ssh/id_ed25519" >> "$(gate_of "$R45")"
poke "$R45" tick
expect_eq "45d a new line after a raised one raises again" "NOTIFY|1:credentials" \
  "$(s45_field "$OUT" decision)|$(s45_field "$OUT" gate)"
expect_eq "45d2 …with one GATE line" "1" "$(s45_gates "$OUT")"
expect_contains "45d3 …the new request's" "poker: GATE lead — credentials: cat ~/.ssh/id_ed25519" "$OUT"
expect_absent "45d4 …and not the one already raised" "git push origin wave/99-fx" "$OUT"

# ---------- §GATE-two: two requests at once are two lines and one NOTIFY ----------
R45T="$(s45_world s45-two)"
{ gate_line w99-T1 leaves-the-machine "gh pr create --fill"
  gate_line w99-T2 credentials "gh auth token"
} > "$(gate_of "$R45T")"
poke "$R45T" tick
expect_eq "45e two different requests: one decision line, NOTIFY" "1|NOTIFY" \
  "$(printf '%s\n' "$OUT" | grep -c '^poker-tick/v1|' | tr -d ' ')|$(s45_field "$OUT" decision)"
expect_eq "45e2 …carrying the count and both categories, sorted" "2:credentials,leaves-the-machine" \
  "$(s45_field "$OUT" gate)"
expect_eq "45e3 …and two GATE lines" "2" "$(s45_gates "$OUT")"
expect_contains "45e4 …one for each request" "poker: GATE w99-T2 — credentials: gh auth token" "$OUT"
expect_contains "45e5 …the other's too" "poker: GATE w99-T1 — leaves-the-machine: gh pr create --fill" "$OUT"

# ---------- §GATE-bad: a malformed line is ignored, and the tick still decides ----------
R45M="$(s45_world s45-malformed)"
{ printf 'not a gate line\n'
  printf 'gate/v1|at=2026-10-03T23:00:00Z|session=%s|asker=w99-T1|head=no category here\n' "$SID"
  printf 'gate/v1|at=2026-10-03T23:00:00Z|session=another-session|asker=w99-T1|category=billing|head=a neighbour request\n'
  printf 'gate/v9|at=2026-10-03T23:00:00Z|session=%s|asker=w99-T1|category=billing|head=a future schema\n' "$SID"
  printf 'gate/v1|at=2026-10-03T23:00:00Z|session=%s|asker=|category=billing|head=no asker\n' "$SID"
} > "$(gate_of "$R45M")"
poke "$R45M" tick
expect_eq "45f malformed lines only: the tick completes and decides on the rows (QUIET, exit 0)" \
  "QUIET|0" "$(s45_field "$OUT" decision)|$RC"
expect_eq "45f2 …raising none of them: no gate= field" "" "$(s45_field "$OUT" gate)"
gate_line w99-T1 billing "stripe charges create" >> "$(gate_of "$R45M")"
poke "$R45M" tick
expect_eq "45f3 …and a valid line among them is raised alone" "NOTIFY|1:billing|1" \
  "$(s45_field "$OUT" decision)|$(s45_field "$OUT" gate)|$(s45_gates "$OUT")"

# ---------- §GATE-link: a symlinked gate file is refused, not followed ----------
R45L="$(s45_world s45-link)"
gate_line w99-T1 leaves-the-machine "git push --force origin main" > "$TMPROOT/s45-elsewhere.state"
ln -s "$TMPROOT/s45-elsewhere.state" "$(gate_of "$R45L")"
poke "$R45L" tick
expect_eq "45g a symlinked gate file: the tick decides on the rows" "QUIET" "$(s45_field "$OUT" decision)"
expect_eq "45g2 …the link's target is not raised: no gate= field" "" "$(s45_field "$OUT" gate)"
expect_absent "45g3 …and its request is not printed" "git push --force origin main" "$OUT"
expect_contains "45g4 …the refusal is said, as a note" "is a symlink" "$OUT"

# ---------- §GATE-first: the armed tick before any dispatch raises it too ----------
R45F="$(make_repo s45-first)"; armed_ago "$R45F"
gate_line lead leaves-the-machine "git push origin wave/99-fx" > "$(gate_of "$R45F")"
poke "$R45F" tick
expect_eq "45h no roster yet (armed, nothing dispatched): NOTIFY, gate=, exit 1" \
  "NOTIFY|1:leaves-the-machine|1" "$(s45_field "$OUT" decision)|$(s45_field "$OUT" gate)|$RC"
expect_contains "45h2 …with its GATE line" "poker: GATE lead — leaves-the-machine: git push origin wave/99-fx" "$OUT"

# ---------- §GATE-disarm: DISARM outranks NOTIFY, and still carries the request ----------
R45X="$(make_repo s45-disarm)"; new_roster "$R45X"; armed_ago "$R45X"; delivered_plan "$R45X"
gate_line lead leaves-the-machine "git push origin main" > "$(gate_of "$R45X")"
poke "$R45X" tick
expect_eq "45i a delivered run with a request pending: the band stays DISARM (exit 0)" "DISARM|0" \
  "$(s45_field "$OUT" decision)|$RC"
expect_eq "45i2 …and the line still carries gate=" "1:leaves-the-machine" "$(s45_field "$OUT" gate)"
expect_contains "45i3 …under its GATE line" "poker: GATE lead — leaves-the-machine: git push origin main" "$OUT"

# ---------- §GATE-dup: the REAL hook, asked the same reserved question twice, leaves one line ----------
# Overridable for the planted defect, never by editing the hook in the tree:
#   W25_GATE_HOOK_UNDER_TEST=<copy>/hooks/permission-answer.sh bash tests/session-poker.test.sh
S45_HOOK="${W25_GATE_HOOK_UNDER_TEST:-${BIONIC_HOOKS_DIR}/permission-answer.sh}"
expect_true "45j precondition: the hook under test exists" test -f "$S45_HOOK"
gate_ask() {  # <repo> <command> -> sets GATE_ANSWER, the decision's behavior
  local pl
  pl="$(jq -n --arg s "$SID" --arg c "$1" --arg cmd "$2" \
    '{session_id:$s, transcript_path:"/dev/null", cwd:$c, permission_mode:"bypassPermissions",
      hook_event_name:"PermissionRequest", tool_name:"Bash",
      tool_input:{command:$cmd, description:"a fixture command"}, permission_suggestions:[]}')"
  GATE_ANSWER="$( cd "$1" && printf '%s' "$pl" \
    | env HOME="$TMPROOT/s45-home" CLAUDE_PROJECT_DIR="$1" CLAUDE_CODE_SESSION_ID="$SID" bash "$S45_HOOK" 2>/dev/null \
    | jq -r '.hookSpecificOutput.decision.behavior // "none"' 2>/dev/null )"
}
R45H="$(s45_world s45-hook)"
gate_ask "$R45H" "git push origin wave/99-fx"
expect_eq "45j2 the lead's git push: the hook denies it" "deny" "$GATE_ANSWER"
gate_ask "$R45H" "git push origin wave/99-fx"
expect_eq "45j3 …asked again, denied again" "deny" "$GATE_ANSWER"
expect_regex "45j4 …and the request is on file in the gate/v1 shape" \
  "^gate/v1\|at=[0-9TZ:-]+\|session=$SID\|asker=lead\|category=leaves-the-machine\|head=git push origin wave/99-fx$" \
  "$(head -1 "$(gate_of "$R45H")" 2>/dev/null)"
expect_eq "45j5 AC-4.3 the same request twice leaves one line" "1" \
  "$(grep -c '' "$(gate_of "$R45H")" 2>/dev/null | tr -d ' ')"
poke "$R45H" tick
expect_eq "45j6 …which the tick raises once: NOTIFY, one request, one GATE line" "NOTIFY|1:leaves-the-machine|1" \
  "$(s45_field "$OUT" decision)|$(s45_field "$OUT" gate)|$(s45_gates "$OUT")"

# ---------- §GATE-prompt: the Patrol prompt says what gate= means, and the version moved ----------
poke "$R45T" prompt
expect_contains "45k the Patrol prompt names the gate= field" "gate=" "$OUT"
expect_contains "45k2 …as a gate act for the human, through the human's own notify channel" \
  "through the human's own notify channel" "$OUT"
expect_contains "45k3 …and not to be performed" "do not perform it" "$OUT"
S45_V="$(printf '%s\n' "$OUT" | sed -n 's/^bionic-patrol session=[^ ]* v=\([0-9]*\) .*/\1/p')"
expect_regex "45k4 the prompt's version moved past 2, the version before the gate sentence" '^([3-9]|[1-9][0-9]+)$' "$S45_V"
printf 'patrol-digest/v1\nprompt_version=2\n' > "$(digest_of "$R45T")"
poke "$R45T" tick
expect_contains "45k5 …so a Patrol armed under v=2 is told to re-arm" \
  "its prompt is v=2 and this poker prints v=${S45_V}" "$OUT"
unset CLAUDE_CONFIG_DIR

# ============================================================
section "Section 47 §WAIT: the tick names every pending row — FILL or WAIT, with its unmet read and writer — and the longest chain (wave-26 T13; REQ-6 AC-6.6; D9)"
# ============================================================
#
# A TABLE WITH A `reads` COLUMN, so every row waits for what it reads and the kind defaults
# apply (D1). The fixture carries one row of each way to wait: a path an active row writes
# (T2), an external prerequisite (T3), an approval nobody has given (T4, the release), and the
# settled head every open code row writes (T6, the floor). T5 reads only the plan's approval
# and is the one ready writer. Sizes are minutes, so the longest chain is checkable by hand:
# T1 (30) → T2 (20) → T6 (60) = 110, against T5 (40) → T6 = 100 and T4 (15) → T6 = 75.
# HOISTED to tests/session-poker.prelude.sh: s47_plan, s47_lines — Section 59, §SEV, §RC-DEFER and §MOVE-PASTED write reads tables and read tick lines with them.

R47="$(make_repo s46-wait)"; new_roster "$R47"
s47_plan "$R47" 2 \
  "| T1 | 4 | build | in flight | implementor | — | 30 | REQ-x | payload/x.sh | active | |" \
  "| T2 | 4 | build | reads what T1 writes | implementor | — | 20 | REQ-x | payload/y.sh | pending | payload/x.sh |" \
  "| T3 | 4 | build | held by the world | implementor | ext:vendor-fix | 10 | REQ-x | payload/z.sh | pending | |" \
  "| T4 | 7 | doc | the release | implementor | — | 15 | REQ-x | CHANGELOG.md | pending | approval:release |" \
  "| T5 | 4 | build | ready | implementor | — | 40 | REQ-x | payload/w.sh | pending | |" \
  "| T6 | 5 | verify | the floor | auditor | — | 60 | REQ-x | .bionic/docs/record/floor.md | pending | |" >/dev/null
poke_pressure "$R47" 8192 1.0 tick
expect_eq "47a the tick over a reads table exits 0" "0" "$RC"
expect_nonempty "47a2 …and prints WAIT lines (the extractor reads real output)" "$(s47_lines WAIT)"
expect_contains "47b the one ready writer is filled" "poker: FILL T5" "$OUT"
expect_contains "47c a path read names the row that writes it and its status" \
  "poker: WAIT T2 — reads payload/x.sh, written by T1 (active)" "$OUT"
expect_contains "47d an external prerequisite is named as itself" "poker: WAIT T3 — ext:vendor-fix" "$OUT"
expect_eq "47e the release waits for its approval and nothing else — no step hold in a reads table" \
  "poker: WAIT T4 — approval:release" "$(s47_lines WAIT | /usr/bin/grep '^poker: WAIT T4 ')"
expect_contains "47f the floor names the head's writers, the active one first" \
  "poker: WAIT T6 — reads head, written by T1 (active), T2 (pending)" "$OUT"
# AC-6.6: EVERY PENDING ROW IS ON A FILL OR A WAIT LINE, the fixture's ids walked one by one.
S47_FILL="$(s47_lines FILL)"
for _s47 in T2 T3 T4 T5 T6; do
  _s47_on=no
  case " ${S47_FILL#poker: FILL } " in *" $_s47 "*) _s47_on=fill ;; esac
  [ -n "$(s47_lines WAIT | /usr/bin/grep "^poker: WAIT $_s47 — ")" ] && _s47_on="${_s47_on/no/wait}"
  expect_ne "47g AC-6.6 pending $_s47 is on a FILL or a WAIT line" "no" "$_s47_on"
done
expect_absent "47g2 …and the active row is on neither (it is not pending)" "WAIT T1 " "$(s47_lines WAIT)"
expect_absent "47h the bulk sentence is gone" "none has all its dependencies landed" "$OUT"
expect_eq "47i AC-6.6 the CHAIN line is the fixture's longest chain, by hand: 30 + 20 + 60" \
  "poker: CHAIN T1→T2→T6 (110 min)" "$(s47_lines CHAIN)"
# THE DIFFERENTIAL: land T1 and the chain moves to the next heaviest path, so 47i reads the
# graph and not a constant.
sed -i.bak 's/| payload\/x.sh | active |/| payload\/x.sh | landed |/' "$R47/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
poke_pressure "$R47" 8192 1.0 tick
expect_eq "47j with T1 landed the chain is T5 → T6 (40 + 60)" "poker: CHAIN T5→T6 (100 min)" "$(s47_lines CHAIN)"
expect_contains "47j2 …and T2, its read now landed, is filled beside T5" "poker: FILL T2 T5" "$OUT"

# ============================================================
section "Section 47 §READY-EARLY (tick half): a doc row whose reads exist is offered before its step; a read-only row outside the writer gap (wave-26 T13; REQ-6 AC-6.1; D3, D9)"
# ============================================================
#
# current: 4 and one task landed. The Step-7 doc row reads the plan approval and the head, and
# nothing open writes the head, so it is ready now — it is not held until current: 7 (D3). The
# review row (kind review) takes no writer slot, so it is offered whatever the writer gap.
# A Step-7 doc row names the approval it waits for (wave-26 T62; K2-F3): this one is notes, not the
# release, so it reads approval:plan.
s47_early() {  # <repo> -> the plan; writers=1
  s47_plan "$1" 1 \
    "| T1 | 4 | build | landed | implementor | — | 30 | REQ-x | payload/x.sh | landed | |" \
    "| T2 | 7 | doc | the release notes draft | implementor | — | 20 | REQ-x | .bionic/docs/record/notes.md | pending | approval:plan, head |" \
    "| T3 | 6 | review | the review | critic | — | 30 | REQ-x | .bionic/docs/record/review.md | pending | |" >/dev/null
}
R47E="$(make_repo s46-early)"; new_roster "$R47E"; s47_early "$R47E"
poke_pressure "$R47E" 8192 1.0 tick
expect_contains "47k AC-6.1 at current: 4 the tick offers the doc row and the review row" "poker: FILL T2 T3" "$OUT"
# THE WRITER GAP CLOSED: one writer open, writers=1. The doc row is a writer and waits for a
# slot; the review is read-only and is still offered.
R47F="$(make_repo s46-early-full)"; new_roster "$R47F"; s47_early "$R47F"
add_row "$R47F" name=w1 deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
poke_pressure "$R47F" 8192 1.0 tick
expect_contains "47l D9 with no writer slot free the read-only review is still offered" "poker: FILL T3" "$OUT"
expect_absent "47l2 …and the doc row, a writer, is not on the FILL line (its sentence, which names the rows behind the gap, set aside)" "T2" "$(s47_lines FILL | /usr/bin/grep -v '^poker: FILL — ')"
expect_eq "47l2b …positive on the same extractor: the FILL line is the review alone" "poker: FILL T3" "$(s47_lines FILL | /usr/bin/grep -v '^poker: FILL — ')"
expect_contains "47l3 …it is on a WAIT line saying it is ready and waits for a writer slot" \
  "poker: WAIT T2 — ready; no writer slot free" "$OUT"
# REVIEW 10 ANSWER (b) (wave-26 T46): THE EXEMPTION IS THE RECORD, NOT THE KIND ALONE. A verify
# row whose Files name tracked code was offered with no slot free, then demanded by the wall and
# refused by the budget. It now takes a writer place like any writer; the same row writing only
# the record is still offered outside the gap.
s47_verify() {  # <repo> <T4 Files> -> the plan; writers=1, one writer open
  s47_plan "$1" 1 \
    "| T1 | 4 | build | landed | implementor | — | 30 | REQ-x | payload/x.sh | landed | |" \
    "| T4 | 5 | verify | the floor | test-runner | — | 30 | REQ-x | $2 | pending | |" >/dev/null
  add_row "$1" name=w1 deliverable=a.md duration="4 hours" launched_at="$(iso_ago 60)"
}
R47G="$(make_repo s47-verify-code)"; new_roster "$R47G"; s47_verify "$R47G" "payload/v.sh"
poke_pressure "$R47G" 8192 1.0 tick
expect_contains "47l4 b a verify row naming tracked code, no writer slot free: one WAIT line with the budget reason" \
  "poker: WAIT T4 — ready; no writer slot free" "$OUT"
expect_absent "47l5 …and it is not on a FILL line" "T4" "$(s47_lines FILL)"
R47H="$(make_repo s47-verify-record)"; new_roster "$R47H"; s47_verify "$R47H" ".bionic/docs/record/floor.md"
poke_pressure "$R47H" 8192 1.0 tick
expect_contains "47l6 b the same row writing only the record, no writer slot free: offered" "poker: FILL T4" "$OUT"

# ============================================================
section "Section 47 §APPROVE: approve <name> '<reply>' writes the approved: line through the verb transaction (wave-26 T13; REQ-6 AC-6.2; D3)"
# ============================================================
S47_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R47A="$(make_repo s46-approve)"; ( cd "$R47A" && git commit -q --allow-empty -m init )
git -C "$R47A" config user.name "Dana Fixture"
P47A="$(s42_plan "$R47A" 4)"
# A READS TABLE (wave-26 T46; review 10 F6): approve records only a name some row reads, so the
# fixture's open rows read two — T5 `approval:release`, the active T2 `live:approval:ship`; the
# landed T1 reads `live:approval:landedonly`, which satisfies nothing (wave-26 T52; review 14 N4).
awk '
  /^\| id \| step \|/ { print $0 " reads |"; next }
  /^\|---\|/ { print $0 "---|"; next }
  /^\| T1 \|/ { print $0 " live:approval:landedonly |"; next }
  /^\| T2 \|/ { print $0 " live:approval:ship |"; next }
  /^\| T5 \|/ { sub(/\| T1, T2 \|/, "| — |"); print $0 " approval:release |"; next }
  /^\| T[0-9]+ \|/ { print $0 "  |"; next }
  { print }' "$P47A" > "$P47A.tmp" && mv "$P47A.tmp" "$P47A"
s42_snap "$R47A" "$P47A"
s34_gate "$R47A"
expect_eq "47m0 precondition: the reads-table fixture is admitted by the real commit gate" "0" "$GATE_RC"
poke "$R47A" approve release 'Ship it.'
expect_eq "47m approve release exits 0" "0" "$RC"
expect_contains "47m2 …and says what it wrote" "approve — release" "$OUT"
S47_LINE="$(/usr/bin/grep '^approved: release ' "$P47A")"
expect_regex "47n the line is approved: <name> by <git user> <ISO-UTC> \"<reply>\"" \
  '^approved: release by Dana Fixture [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z "Ship it\."$' "$S47_LINE"
expect_eq "47n2 …inside ## SDLC State, ahead of the next section" "SDLC" \
  "$(awk '/^## /{ s = $2 } /^approved: release /{ print s; exit }' "$P47A")"
expect_eq "47n3 …and git diff --numstat shows one line added, none removed" "1 0;" "$(s42_numstat "$R47A")"
s34_gate "$R47A"
expect_eq "47o the commit gate admits the approved plan" "0" "$GATE_RC"
s42_snap "$R47A" "$P47A"
poke "$R47A" approve release 'Again.'
s42_unchanged "47p a second approve of the same name" 1 "$P47A"
expect_contains "47p2 …naming the line already there" "approved: release" "$OUT"
poke "$R47A" approve plan 'approved'
s42_unchanged "47q approve plan" 1 "$P47A"
expect_contains "47q2 …saying the plan's approval is the approved-by: line written at Step 3" \
  "approved-by:" "$OUT"
expect_contains "47q3 …at Step 3" "Step 3" "$OUT"
poke "$R47A" approve 'rel|x' 'ok'
s42_unchanged "47r a name outside the approval:<name> grammar" 2 "$P47A"
poke "$R47A" approve integrate "a
b"
s42_unchanged "47s a reply carrying a line break" 1 "$P47A"
poke "$R47A" approve integrate
s42_unchanged "47t no reply at all" 2 "$P47A"
# REVIEW 10 F6: A NAME NO ROW READS IS REFUSED, and the refusal lists the names that are read,
# so a mistyped name is not recorded "once" while the row it was meant for waits in silence.
# The match is exact: a name in another case is another name.
poke "$R47A" approve relase 'Ship it.'
s42_unchanged "47t2 F6 a name no row reads (a typo of release)" 1 "$P47A"
expect_contains "47t3 …naming the names the rows read" "the rows read: release ship" "$OUT"
poke "$R47A" approve Release 'Ship it.'
s42_unchanged "47t4 F6 the read name in another case" 1 "$P47A"
# REVIEW 14 N4 (wave-26 T52): a name only the landed T1 reads satisfies nothing, so it is refused
# and is not among the names listed.
poke "$R47A" approve landedonly 'Go.'
s42_unchanged "47t4b N4 a name read only by a landed row" 1 "$P47A"
expect_contains "47t4c …listing only the names open rows read" "the rows read: release ship" "$OUT"
poke "$R47A" approve ship 'Go.'
expect_eq "47t5 F6 a name read as live:approval:<name> is recorded" "0" "$RC"
expect_contains "47t6 …the line written" "approved: ship by Dana Fixture" "$(cat "$P47A")"
POKE_BOUND="$S47_BOUND_WAS"

# ============================================================
section "Section 47 §WAITING-READY: WAITING says nothing is ready only when nothing is (wave-26 T13; review-6 F3; D9, D16)"
# ============================================================
#
# A QUIET tick with a row running printed `WAITING — <n> running, nothing ready` whatever the
# ready set held, so a full writer budget or a standing fill-declined read as "nothing ready"
# while a row was ready. Each such row now has its WAIT line saying why, and WAITING prints only
# when the untrimmed ready set is empty. Three worlds over one table shape, writers=1 and one
# writer running: a ready row the budget cannot take, a ready row the standing decline answered
# (writers=2, so a slot is free), and the control where the row waits on an unlanded read.
s47_quiet() {  # <repo> <writers> <T2 reads> -> the plan; T9 active, T2 pending, one writer open
  s47_plan "$1" "$2" \
    "| T9 | 4 | build | in flight | implementor | — | 30 | REQ-x | payload/q.sh | active | |" \
    "| T2 | 4 | build | the row | implementor | — | 20 | REQ-x | payload/r.sh | pending | $3 |" >/dev/null
  add_row "$1" name=w1 deliverable="$1/never-written.md" duration="4 hours" launched_at="$(iso_ago 60)"
}
R47Q="$(make_repo s47-waiting-full)"; new_roster "$R47Q"; s47_quiet "$R47Q" 1 ""
poke_pressure "$R47Q" 8192 1.0 tick
expect_contains "47u F3 a full writer budget names the ready row it cannot take, and why" \
  "poker: WAIT T2 — ready; no writer slot free" "$OUT"
expect_absent "47u2 …and does not say nothing is ready" "poker: WAITING" "$OUT"
R47R="$(make_repo s47-waiting-declined)"; new_roster "$R47R"; s47_quiet "$R47R" 2 ""
mkdir -p "$R47R/.bionic/docs/record/wave-01-fixture"
printf 'fill-ledger/v1|at=2026-10-04T00:00:00Z|session=%s|turn=u-47r|current=4|state=ok|ceiling=2|width=2|open=1|free=1|ready=T2|launched=|declined=T2 waits on the merge|missed=1\n' "$SID" \
  > "$R47R/.bionic/docs/record/wave-01-fixture/fill-ledger.log"
poke_pressure "$R47R" 8192 1.0 tick
expect_contains "47v precondition: the standing decline is read" "fill-declined standing since" "$OUT"
expect_contains "47v2 F3 a ready row the standing decline answered is named, and why" \
  "poker: WAIT T2 — ready; answered by the standing fill-declined" "$OUT"
expect_absent "47v3 …and the tick does not say nothing is ready" "poker: WAITING" "$OUT"
R47S="$(make_repo s47-waiting-none)"; new_roster "$R47S"; s47_quiet "$R47S" 1 "payload/q.sh"
poke_pressure "$R47S" 8192 1.0 tick
expect_contains "47w the control: the row waits on what T9 writes, on its WAIT line" \
  "poker: WAIT T2 — reads payload/q.sh, written by T9 (active)" "$OUT"
expect_contains "47w2 …and with nothing ready and a row running, WAITING prints" \
  "poker: WAITING — 1 running, nothing ready" "$OUT"

# ============================================================
section "Section 46 §PROOF-ADD: a proof names the head it read (wave-26 T4; REQ-3 AC-3.2; D5)"
# ============================================================
#
# `proof-add <floor|review|task> <evidence>` writes one line inside `## SDLC State`:
# `proved: kind=<kind> head=<40-hex> at=<ISO-UTC> evidence=<path under record/>`. The head
# is never an operand: it is the one the evidence names (a run log's `head=` header, a
# review's `reviewed: a..b` end; T14), held against the checkout holding the plan's
# `working-branch:`, which here is a linked worktree one commit ahead of the main checkout,
# so a head read from the cwd would be the wrong one. The write is §42's transaction: a
# copy, a dry commit through the real gate, a checksum, a swap; every refusal leaves the
# plan byte-identical. `proof_last <plan> <kind>` (payload/scripts/lib/proof.sh) reads the
# newest line of a kind back.
S46_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
S46_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
# HOISTED to tests/session-poker.prelude.sh: s46_last, s46_proved — shards 3 and 4 read proof lines with them (each names S46_LIB itself).

R46="$(make_repo s46-proof)"; ( cd "$R46" && git commit -q --allow-empty -m init )
P46="$(s42_plan "$R46" 4)"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$P46" > "$P46.tmp" && mv "$P46.tmp" "$P46"
# THREE SUITES ARE THE ROSTER (wave-26 T52; review 14 N1): a floor log's `Gating:` tally must
# count every tests/*.test.sh at the head it read, so the fixture's logs say 3.
mkdir -p "$R46/tests"
for s46s in a b c; do printf '#!/bin/bash\n' > "$R46/tests/$s46s.test.sh"; done
( cd "$R46" && git add -f "$P46" tests && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$R46/.worktrees/01-fixture" \
  && git -C "$R46/.worktrees/01-fixture" commit -q --allow-empty -m "wave work" ) >/dev/null 2>&1
W46_HEAD="$(git -C "$R46/.worktrees/01-fixture" rev-parse HEAD 2>/dev/null)"
mkdir -p "$R46/.bionic/docs/record/wave-01-fixture" "$R46/.bionic/docs/plans/elsewhere"
# THE EVIDENCE ATTESTS ITS HEAD (wave-26 T14; review 7 F1): a floor log carries the suite runner's
# header line `head=<sha> dirty=<n>`, a review its `reviewed: <a>..<b>` line.
printf 'floor log\nenv: os=fixture\nhead=%s dirty=0\nall suites passed\nGating: 3 passed, 0 failed\n' "$W46_HEAD" > "$R46/.bionic/docs/record/wave-01-fixture/floor.txt"
printf 'review notes\n' > "$R46/.bionic/docs/record/wave-01-fixture/review.md"
printf 'not a record\n' > "$R46/.bionic/docs/plans/elsewhere/notes.md"
expect_regex "46a0 precondition: the working branch's checkout has a 40-hex head" '^[0-9a-f]{40}$' "$W46_HEAD"
expect_true "46a0b precondition: …which is not the main checkout's head" \
  test "$W46_HEAD" != "$(git -C "$R46" rev-parse HEAD)"
s34_gate "$R46"
expect_eq "46a0c precondition: the fixture plan is admitted by the real commit gate" "0" "$GATE_RC"
expect_eq "46a0d precondition: the plan carries no proof line yet" "" "$(s46_proved "$P46")"
expect_true "46a0e precondition: proof.sh is in the tree under test" test -r "$S46_LIB"

# ---------- the write ----------
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor.txt
expect_eq "46a proof-add floor exits 0" "0" "$RC"
expect_contains "46a2 …and says what it wrote" "proof-add — kind=floor head=$W46_HEAD" "$OUT"
expect_eq "46a3 …git diff --numstat shows one line added" "1 0;" "$(s42_numstat "$R46")"
expect_regex "46a4 …in the proof line's shape, with the working branch's head" \
  "^proved: kind=floor head=${W46_HEAD} at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z evidence=record/wave-01-fixture/floor.txt$" \
  "$(s46_proved "$P46")"
expect_eq "46a5 …inside ## SDLC State" "SDLC" \
  "$(awk '/^##[[:space:]]/ { s = $2 } /^proved: / { print s; exit }' "$P46")"
expect_eq "46a6 proof_last reads the floor head back" "$W46_HEAD" "$(s46_last "$P46" floor)"
expect_eq "46a7 …and a kind never proved reads nothing" "" "$(s46_last "$P46" review)"
s34_gate "$R46"
expect_eq "46a8 …and the next commit is admitted" "0" "$GATE_RC"

# A later proof of the same kind is the one proof_last reads; an absolute path under record/
# is written docs-root relative.
git -C "$R46/.worktrees/01-fixture" commit -q --allow-empty -m "more wave work" >/dev/null 2>&1
W46_HEAD2="$(git -C "$R46/.worktrees/01-fixture" rev-parse HEAD 2>/dev/null)"
# The review names what it read in abbreviated form; the proof names the commit it resolves to.
printf '# review\n\nreviewed: %s..%s (the fixture)\n\nnotes\n' "${W46_HEAD:0:8}" "${W46_HEAD2:0:10}" \
  > "$R46/.bionic/docs/record/wave-01-fixture/review.md"
s42_snap "$R46" "$P46"
poke "$R46" proof-add review "$R46/.bionic/docs/record/wave-01-fixture/review.md"
expect_eq "46b proof-add review by absolute path exits 0" "0" "$RC"
expect_eq "46b2 …one line added" "1 0;" "$(s42_numstat "$R46")"
expect_contains "46b3 …naming the evidence under record/" \
  "proved: kind=review head=${W46_HEAD2} " "$(s46_proved "$P46")"
expect_contains "46b4 …docs-root relative" "evidence=record/wave-01-fixture/review.md" "$(s46_proved "$P46" | tail -1)"
# REVIEW 7 F1: THE SAME FLOOR LOG AFTER A LANDING PROVES NOTHING NEW. The log read W46_HEAD; the
# branch has moved to W46_HEAD2 with no run, so re-citing it is refused and the floor proof
# stays at the head the run read. A log of a run at W46_HEAD2 proves W46_HEAD2.
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor.txt
s42_unchanged "46b5 F1 the floor log of the old head, after a landing" 1 "$P46"
expect_contains "46b5b …naming both heads and the fix" \
  "read head ${W46_HEAD:0:12}, but the working branch is at ${W46_HEAD2:0:12}; run it again on ${W46_HEAD2:0:12}" "$OUT"
expect_eq "46b6 F1 proof_last floor still reads the head the run read" "$W46_HEAD" "$(s46_last "$P46" floor)"
printf 'floor log\nhead=%s dirty=0\nGating: 3 passed, 0 failed\n' "$W46_HEAD2" > "$R46/.bionic/docs/record/wave-01-fixture/floor2.txt"
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor2.txt
expect_eq "46b6b …a log of a run at the new head exits 0" "0" "$RC"
expect_eq "46b6c …and proof_last floor reads the new head" "$W46_HEAD2" "$(s46_last "$P46" floor)"
expect_eq "46b7 …and the review head is its own, resolved from the review's reviewed: line" "$W46_HEAD2" "$(s46_last "$P46" review)"
expect_eq "46b8 …the proof lines sit together, newest last" "floor review floor" \
  "$(s46_proved "$P46" | sed -E 's/^proved: kind=([a-z]+) .*/\1/' | tr '\n' ' ' | sed 's/ $//')"

# ---------- F1: what the evidence must attest, each refusal naming its fix ----------
S46_REC="$R46/.bionic/docs/record/wave-01-fixture"
printf 'floor log\nhead=%s dirty=3\n' "$W46_HEAD2" > "$S46_REC/floor-dirty.txt"
printf 'floor log\nhead=none dirty=none\n' > "$S46_REC/floor-norepo.txt"
printf 'a log with no run header\n' > "$S46_REC/floor-bare.txt"
printf '# review\n\nno range here\n' > "$S46_REC/review-bare.md"
printf '# review\n\nreviewed: %s..0123456789abcdef0123456789abcdef01234567\n' "${W46_HEAD:0:8}" > "$S46_REC/review-gone.md"
S46_SIDE="$(git -C "$R46" commit-tree -p "$W46_HEAD" -m "a side commit" "$(git -C "$R46" rev-parse "$W46_HEAD^{tree}")" 2>/dev/null)"
printf '# review\n\nreviewed: %s..%s\n' "${W46_HEAD:0:8}" "$S46_SIDE" > "$S46_REC/review-side.md"
printf '# review\n\nreviewed: %s..%s\n' "${W46_HEAD:0:8}" "$W46_HEAD" > "$S46_REC/review-older.md"
expect_regex "46f0 precondition: the side commit exists" '^[0-9a-f]{40}$' "$S46_SIDE"
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor-dirty.txt
s42_unchanged "46f F1 a run at the head on a dirty tree" 1 "$P46"
expect_contains "46f2 …naming the dirt and the fix" "dirty tree (dirty=3); commit, run it again" "$OUT"
poke "$R46" proof-add floor record/wave-01-fixture/floor-norepo.txt
s42_unchanged "46f3 F1 a run that read no repository (head=none)" 1 "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor-bare.txt
s42_unchanged "46f4 F1 a floor evidence with no run header" 1 "$P46"
expect_contains "46f5 …naming the line it needs" "carries no head=<sha> dirty=<n> line" "$OUT"
poke "$R46" proof-add review record/wave-01-fixture/review-bare.md
s42_unchanged "46f6 F1 a review with no reviewed: line" 1 "$P46"
expect_contains "46f7 …naming the line it needs" "carries no reviewed: <a>..<b> line" "$OUT"
poke "$R46" proof-add review record/wave-01-fixture/review-gone.md
s42_unchanged "46f8 F1 a review that read a commit this repository lacks" 1 "$P46"
poke "$R46" proof-add review record/wave-01-fixture/review-side.md
s42_unchanged "46f9 F1 a review of a commit off the working branch" 1 "$P46"
expect_contains "46f10 …naming it" "which is not on the working branch" "$OUT"
poke "$R46" proof-add floor record/wave-01-fixture/review-older.md
s42_unchanged "46f11 a floor proof never reads a review's range" 1 "$P46"
# REVIEW 10 F1 (wave-26 T5): A RUN AT THE HEAD MUST ALSO HAVE PASSED. The header says which head
# the run read, the runner's last `Gating:` line how it ended; a red run, a note quoting the
# header, a void suite, and a green inner verdict above a red outer one prove nothing. The green
# log at the same head (floor2.txt, 46b6b) is this block's positive control.
printf 'floor log\nhead=%s dirty=0\nGating: 40 passed, 3 failed\n' "$W46_HEAD2" > "$S46_REC/floor-red.txt"
printf '# review notes\nThe runner printed:\nhead=%s dirty=0\n(no run here)\n' "$W46_HEAD2" > "$S46_REC/floor-quote.txt"
printf 'floor log\nhead=%s dirty=0\nGating: 40 passed, 0 failed\nVoid: 1 — not timed\n' "$W46_HEAD2" > "$S46_REC/floor-void.txt"
printf 'floor log\nhead=%s dirty=0\n───── x: captured output ─────\nGating: 5 passed, 0 failed\n───── end x ─────\nGating: 40 passed, 2 failed\n' \
  "$W46_HEAD2" > "$S46_REC/floor-inner.txt"
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor-red.txt
s42_unchanged "46f12 F1 a red run at the head, on a clean tree" 1 "$P46"
expect_contains "46f12b …naming the verdict and the fix" "did not pass (Gating: 40 passed, 3 failed); fix it, run it again" "$OUT"
poke "$R46" proof-add floor record/wave-01-fixture/floor-quote.txt
s42_unchanged "46f13 F1 a note that quotes the run header" 1 "$P46"
expect_contains "46f13b …naming the verdict it lacks" "has no Gating: <n> passed, <m> failed verdict" "$OUT"
poke "$R46" proof-add floor record/wave-01-fixture/floor-void.txt
s42_unchanged "46f14 F1 a run whose tally does not reach the roster, with a Void: line" 1 "$P46"
expect_contains "46f14b …naming the tally against the roster" "40 passed and 1 void of 3 suites" "$OUT"
poke "$R46" proof-add floor record/wave-01-fixture/floor-inner.txt
s42_unchanged "46f15 F1 a green inner verdict above the runner's red one" 1 "$P46"
poke "$R46" proof-add task record/wave-01-fixture/floor-red.txt
s42_unchanged "46f16 F1 a task proof citing a red run" 1 "$P46"
# REVIEW 14 S3, N1, N2 (wave-26 T52). THE LAST RUN IN THE LOG IS JUDGED, and a verdict that sits
# inside a failing suite's captured output is not the runner's: a log cut off after a nested
# green verdict, or a red run for this head with another head's green run appended, proves
# nothing. A floor must be a WHOLE run: passed plus void reaches the suites at the head (three
# here). A void suite passed (T43), so a whole run with one is a floor.
printf 'floor log\nhead=%s dirty=0\n✗ FAIL\n───── x.test.sh: captured output ─────\nGating: 3 passed, 0 failed\n───── end x.test.sh ─────\n' \
  "$W46_HEAD2" > "$S46_REC/floor-cut.txt"
printf 'floor log\nhead=%s dirty=0\nGating: 2 passed, 1 failed\nFailed:\nhead=0123456789abcdef0123456789abcdef01234567 dirty=0\nGating: 3 passed, 0 failed\n' \
  "$W46_HEAD2" > "$S46_REC/floor-appended.txt"
printf 'floor log\nhead=%s dirty=0\nGating: 1 passed, 0 failed\n' "$W46_HEAD2" > "$S46_REC/floor-part.txt"
printf 'floor log\nhead=%s dirty=0\nGating: 2 passed, 0 failed\nVoid: 1 — not timed, each for the reason given; advisory, not a failure:\n    - c.test.sh (the machine was busy)\nNo gating suite failed; 1 void\n' \
  "$W46_HEAD2" > "$S46_REC/floor-whole-void.txt"
printf 'floor log\nhead=%s dirty=0\nGating: 2 passed, 1 failed\nhead=%s dirty=0\nGating: 3 passed, 0 failed\n' \
  "$W46_HEAD2" "$W46_HEAD2" > "$S46_REC/floor-rerun.txt"
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor-cut.txt
s42_unchanged "46f17 S3 a log cut off after a nested green verdict inside a capture" 1 "$P46"
expect_contains "46f17b …saying the verdict is inside a captured output" "inside a suite's captured output" "$OUT"
poke "$R46" proof-add floor record/wave-01-fixture/floor-appended.txt
s42_unchanged "46f18 S3 a red run for this head with another head's green run appended" 1 "$P46"
expect_contains "46f18b …judged by the last run, which read another head" "read head 0123456789ab" "$OUT"
poke "$R46" proof-add floor record/wave-01-fixture/floor-part.txt
s42_unchanged "46f19 N1 a green verdict over one suite of the three at the head" 1 "$P46"
expect_contains "46f19b …naming the tally against the roster" "1 passed and 0 void of 3 suites" "$OUT"
poke "$R46" proof-add floor record/wave-01-fixture/floor-whole-void.txt
expect_eq "46f20 N2 a whole run with one void suite that passed is a floor" "0" "$RC"
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor-rerun.txt
expect_eq "46f21 S3 a red run then a green rerun on the same head: the last run is judged, and it passed" "0" "$RC"
# A REVIEW OF AN OLDER HEAD IS A TRUE PROOF OF THAT HEAD: what landed since stays unread.
poke "$R46" proof-add review record/wave-01-fixture/review-older.md
expect_eq "46g a review of an ancestor of the branch head exits 0" "0" "$RC"
expect_eq "46g2 …and proves the head it read, not the branch head" "$W46_HEAD" "$(s46_last "$P46" review)"
# kind=task takes whichever the evidence carries, the run header first (A-T14.9).
s42_snap "$R46" "$P46"
poke "$R46" proof-add task record/wave-01-fixture/floor2.txt
expect_eq "46g3 a task proof citing a run log at the head exits 0" "0" "$RC"
poke "$R46" proof-add task record/wave-01-fixture/review-older.md
expect_eq "46g4 …and one citing a review of an older head exits 0" "0" "$RC"
expect_eq "46g5 …proving the head that review read" "$W46_HEAD" "$(s46_last "$P46" task)"
s42_snap "$R46" "$P46"
poke "$R46" proof-add task record/wave-01-fixture/floor-bare.txt
s42_unchanged "46g6 a task proof whose evidence attests no head" 1 "$P46"
expect_contains "46g7 …naming both forms" "neither a head=<sha> dirty=<n> run header nor a reviewed: <a>..<b> line" "$OUT"

# ---------- the refusals: byte-identical, naming the fix ----------
s42_snap "$R46" "$P46"
poke "$R46" proof-add bogus record/wave-01-fixture/floor.txt
s42_unchanged "46c a kind outside floor|review|task" 1 "$P46"
expect_contains "46c2 …naming the three kinds" "floor, review or task" "$OUT"
poke "$R46" proof-add floor plans/elsewhere/notes.md
s42_unchanged "46c3 an evidence path outside record/" 1 "$P46"
expect_contains "46c4 …naming record/" "under record/" "$OUT"
poke "$R46" proof-add floor record/../plans/elsewhere/notes.md
s42_unchanged "46c5 a path that climbs out of record/" 1 "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/absent.txt
s42_unchanged "46c6 a missing evidence file" 1 "$P46"
expect_contains "46c7 …naming the file" "absent.txt" "$OUT"
# REVIEW 10 F7 (wave-26 T46): A SYMLINK UNDER record/ IS NOT A RECORD. The check resolved the
# directory, not the file, so a link to a log elsewhere was admitted and the evidence could
# change after the proof. The same bytes as a regular file under record/ are admitted.
printf 'floor log\nhead=%s dirty=0\nGating: 3 passed, 0 failed\n' "$W46_HEAD2" > "$R46/.bionic/docs/plans/elsewhere/run.log"
ln -s ../../plans/elsewhere/run.log "$S46_REC/floor-link.txt"
expect_true "46c7b precondition: the link is a symlink to a log outside record/" test -L "$S46_REC/floor-link.txt"
poke "$R46" proof-add floor record/wave-01-fixture/floor-link.txt
s42_unchanged "46c7c F7 evidence that is a symlink" 1 "$P46"
expect_contains "46c7d …naming the fix: copy the log into the record" "copy the log into the record" "$OUT"
cp "$R46/.bionic/docs/plans/elsewhere/run.log" "$S46_REC/floor-copy.txt"
poke "$R46" proof-add floor record/wave-01-fixture/floor-copy.txt
expect_eq "46c7e …and the same log copied into the record is admitted" "0" "$RC"
s42_snap "$R46" "$P46"
printf 'x\n' > "$R46/.bionic/docs/record/wave-01-fixture/two words.txt"
poke "$R46" proof-add floor "record/wave-01-fixture/two words.txt"
s42_unchanged "46c8 an evidence path with a space (the line is space-separated)" 1 "$P46"
poke "$R46" proof-add floor
s42_unchanged "46c9 one operand is the usage error" 2 "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor.txt "$W46_HEAD"
s42_unchanged "46c10 …and so is a head given as an operand" 2 "$P46"

# The head is held against the working branch's checkout, so a plan whose branch no checkout
# holds, or that names none, is refused before any evidence head is read.
sed 's#^working-branch: wave/01-fixture$#working-branch: wave/99-gone#' "$P46" > "$P46.tmp" && mv "$P46.tmp" "$P46"
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor.txt
s42_unchanged "46d a working-branch: no checkout holds" 1 "$P46"
expect_contains "46d2 …naming the branch" "wave/99-gone" "$OUT"
sed '/^working-branch: /d' "$P46" > "$P46.tmp" && mv "$P46.tmp" "$P46"
s42_snap "$R46" "$P46"
poke "$R46" proof-add floor record/wave-01-fixture/floor.txt
s42_unchanged "46d3 a plan naming no working-branch:" 1 "$P46"
expect_contains "46d4 …naming the key to add" "working-branch:" "$OUT"
expect_eq "46e no projection copy is left beside the plan" "" \
  "$(find "$R46/.bionic/docs/plans" -name '*.plan.md.*' 2>/dev/null)"
POKE_BOUND="$S46_BOUND_WAS"

# ============================================================
section "Section 48 §READY-EARLY (review half): a review follows the build — offered once per landed difference, back to pending on its proof (wave-26 T14; REQ-6 AC-6.1, AC-6.5; D10)"
# ============================================================
#
# A reads table at current: 4 with one build landed and one still active. The review row (an
# empty reads cell, so `approval:plan, live:head`) is offered as soon as the first build lands,
# with no review proof yet (AC-6.1). Dispatched, it is active; `proof-add review` records the
# working branch's head A and returns the row to `pending` with its agent, worktree and base
# cells cleared — the next pass is its own launch and its own ledger line. The tick reads the
# head from the checkout holding `working-branch:` (a linked worktree one commit ahead of the
# main checkout, as §46), so at A the review waits, naming the proof's head; one more commit on
# the working branch — a landing — and the tick offers it again (AC-6.5). A tick that read the
# head from the main checkout would see a head other than A and offer it at 48e.
S48_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
# HOISTED to tests/session-poker.prelude.sh: s48_row, s48_fill_has — Section 59 reads rows and FILL lines with them.

R48="$(make_repo s48-review)"; new_roster "$R48"; ( cd "$R48" && git commit -q --allow-empty -m init )
add_row "$R48" name=w-T2 deliverable=b.md duration="4 hours" launched_at="$(iso_ago 600)"
P48="$(s42_plan "$R48" 4)"
awk '
  /^current: / && !wb { print; print "working-branch: wave/01-fixture"; wb = 1; next }
  /^- T5: / { print "- T3: review passes, one per landed difference — record/wave-01-fixture/review.md" }
  /^\| id \| step \|/ { intab = 1
    print "| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |"
    print "|---|---|---|---|---|---|---|---|---|---|---|---|---|"
    print "| T1 | 4 | build | the first build | implementor | — | 30 | REQ-1 | a.sh | — | — | landed |  |"
    print "| T2 | 4 | build | the second build | w-T2 | — | 30 | REQ-1 | b.sh | 01-T2 | abc1234 | active |  |"
    print "| T3 | 6 | review | follows the build | critic | — | 30 | REQ-1 | .bionic/docs/record/wave-01-fixture/review.md | — | — | pending |  |"
    print "| T5 | 5 | verify | the floor | test-runner | — | 30 | REQ-1 | — | — | — | pending |  |"
    next }
  intab && /^\|/ { next }
  { intab = 0; print }' "$P48" > "$P48.tmp" && mv "$P48.tmp" "$P48"
( cd "$R48" && git add -f "$P48" && git commit -qm "reads table" \
  && git worktree add -q -b wave/01-fixture "$R48/.worktrees/01-fixture" \
  && git -C "$R48/.worktrees/01-fixture" commit -q --allow-empty -m "the first build lands" ) >/dev/null 2>&1
mkdir -p "$R48/.bionic/docs/record/wave-01-fixture"
W48_A="$(git -C "$R48/.worktrees/01-fixture" rev-parse HEAD 2>/dev/null)"
printf '# review\n\nreviewed: %s..%s (the first build)\n' "$(git -C "$R48" rev-parse HEAD)" "$W48_A" \
  > "$R48/.bionic/docs/record/wave-01-fixture/review.md"
expect_eq "48a0 precondition: the T3 row is a review with an empty reads cell, pending" \
  "T3|6|review|follows the build|critic|—|30|REQ-1|.bionic/docs/record/wave-01-fixture/review.md|—|—|pending|" \
  "$(s48_row "$P48" T3)"
expect_true "48a0b precondition: the working branch's head is not the main checkout's" \
  test "$W48_A" != "$(git -C "$R48" rev-parse HEAD)"
s34_gate "$R48"
expect_eq "48a0c precondition: the reads-table plan is admitted by the real commit gate" "0" "$GATE_RC"

# ---------- AC-6.1: no review proof yet, one build landed, one active — offered now ----------
poke_pressure "$R48" 8192 1.0 tick
expect_nonempty "48a the tick prints a FILL line (the extractor reads real output)" "$(s47_lines FILL)"
expect_eq "48a2 AC-6.1 with one build landed and one still active, the review is on the FILL line" "yes" "$(s48_fill_has T3)"

# ---------- dispatched, then its proof: the row goes back to pending ----------
add_row "$R48" name=w-T3 deliverable=review.md duration="1 hour" launched_at="$(iso_ago 60)"
poke "$R48" task-set T3 status=active agent=w-T3 worktree=01-T3 base=abc1234
expect_eq "48b0 precondition: task-set moves T3 active" "0" "$RC"
poke_pressure "$R48" 8192 1.0 tick
expect_eq "48b an active review is not offered again" "no" "$(s48_fill_has T3)"
expect_absent "48b2 …and it is on no WAIT line (it is not pending)" "WAIT T3 " "$(s47_lines WAIT)"
s42_snap "$R48" "$P48"
poke "$R48" proof-add review record/wave-01-fixture/review.md
expect_eq "48c proof-add review exits 0" "0" "$RC"
expect_contains "48c2 …writes the proof at the working branch's head" "proved: kind=review head=${W48_A} " \
  "$(/usr/bin/grep -E '^proved: ' "$P48")"
expect_eq "48c3 …and returns the review row to pending, its agent, worktree and base cleared" \
  "T3|6|review|follows the build|—|—|30|REQ-1|.bionic/docs/record/wave-01-fixture/review.md|—|—|pending|" \
  "$(s48_row "$P48" T3)"
expect_eq "48c4 …touching nothing else: the proof line added, the one row rewritten" "2 1;" "$(s42_numstat "$R48")"
expect_contains "48c5 …and it says which row it returned" "T3 back to pending" "$OUT"
s34_gate "$R48"
expect_eq "48c6 …and the next commit is admitted" "0" "$GATE_RC"

# ---------- AC-6.5: at head A it waits, naming A; one landing later it is offered ----------
poke_pressure "$R48" 8192 1.0 tick
expect_nonempty "48d the tick prints WAIT lines (the extractor reads real output)" "$(s47_lines WAIT)"
expect_eq "48d2 AC-6.5 at the proof's head the review is not offered" "no" "$(s48_fill_has T3)"
expect_eq "48d3 …its WAIT line names the proof head it has not moved past" \
  "poker: WAIT T3 — live:head: nothing landed past the review proof at ${W48_A:0:12}" \
  "$(s47_lines WAIT | /usr/bin/grep '^poker: WAIT T3 ')"
git -C "$R48/.worktrees/01-fixture" commit -q --allow-empty -m "the second build lands" >/dev/null 2>&1
W48_B="$(git -C "$R48/.worktrees/01-fixture" rev-parse HEAD 2>/dev/null)"
expect_true "48e0 precondition: the working branch moved past A" test "$W48_B" != "$W48_A"
poke_pressure "$R48" 8192 1.0 tick
expect_eq "48e AC-6.5 one landing past the proof and the review is offered again" "yes" "$(s48_fill_has T3)"
expect_absent "48e2 …and it is on no WAIT line" "WAIT T3 " "$(s47_lines WAIT)"

# REVIEW 10 F3 (wave-26 T46): ONLY THE ROW WHOSE RECORD IS THE EVIDENCE GOES BACK. A live review
# T3 is mid-pass while the settled final review T8 (reads head) is active beside it; the final
# review's proof returned T3 to pending too, and the next landing re-offered it under a reviewer
# still running. Now the final review's proof moves no row, and T3's own proof still returns it
# (a Files cell spelled record/… matches the same evidence: units LIVE.15e).
R48F="$(make_repo s48-final)"; new_roster "$R48F"; ( cd "$R48F" && git commit -q --allow-empty -m init )
add_row "$R48F" name=w-T3 deliverable=review.md duration="1 hour" launched_at="$(iso_ago 60)"
add_row "$R48F" name=w-T8 deliverable=final.md duration="1 hour" launched_at="$(iso_ago 60)"
P48F="$(s42_plan "$R48F" 4)"
awk '
  /^current: / && !wb { print; print "working-branch: wave/01-fixture"; wb = 1; next }
  /^- T5: / { print "- T3: review passes — record/wave-01-fixture/review.md"; print "- T8: the final review — record/wave-01-fixture/final.md" }
  /^\| id \| step \|/ { intab = 1
    print "| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |"
    print "|---|---|---|---|---|---|---|---|---|---|---|---|---|"
    print "| T1 | 4 | build | the first build | implementor | — | 30 | REQ-1 | a.sh | — | — | landed |  |"
    print "| T3 | 6 | review | follows the build | w-T3 | — | 30 | REQ-1 | .bionic/docs/record/wave-01-fixture/review.md | — | — | active |  |"
    print "| T8 | 6 | review | the final review | w-T8 | — | 30 | REQ-1 | .bionic/docs/record/wave-01-fixture/final.md | — | — | active | approval:plan, head |"
    print "| T5 | 5 | verify | the floor | test-runner | — | 30 | REQ-1 | — | — | — | pending |  |"
    next }
  intab && /^\|/ { next }
  { intab = 0; print }' "$P48F" > "$P48F.tmp" && mv "$P48F.tmp" "$P48F"
( cd "$R48F" && git add -f "$P48F" && git commit -qm "reads table" \
  && git worktree add -q -b wave/01-fixture "$R48F/.worktrees/01-fixture" \
  && git -C "$R48F/.worktrees/01-fixture" commit -q --allow-empty -m "the first build lands" ) >/dev/null 2>&1
mkdir -p "$R48F/.bionic/docs/record/wave-01-fixture"
W48F_A="$(git -C "$R48F/.worktrees/01-fixture" rev-parse HEAD 2>/dev/null)"
printf '# final review\n\nreviewed: %s..%s (the wave)\n' "$(git -C "$R48F" rev-parse HEAD)" "$W48F_A" \
  > "$R48F/.bionic/docs/record/wave-01-fixture/final.md"
printf '# review\n\nreviewed: %s..%s (the first build)\n' "$(git -C "$R48F" rev-parse HEAD)" "$W48F_A" \
  > "$R48F/.bionic/docs/record/wave-01-fixture/review.md"
s34_gate "$R48F"
expect_eq "48f0 precondition: the two-review plan is admitted by the real commit gate" "0" "$GATE_RC"
s42_snap "$R48F" "$P48F"
poke "$R48F" proof-add review record/wave-01-fixture/final.md
expect_eq "48f F3 the final review's proof exits 0" "0" "$RC"
expect_contains "48f2 …and writes its proof line" "proved: kind=review head=${W48F_A} " \
  "$(/usr/bin/grep -E '^proved: ' "$P48F")"
expect_eq "48f3 F3 …and leaves the live review mid-pass active, its agent kept" \
  "T3|6|review|follows the build|w-T3|—|30|REQ-1|.bionic/docs/record/wave-01-fixture/review.md|—|—|active|" \
  "$(s48_row "$P48F" T3)"
expect_eq "48f4 …touching nothing but the proof line" "1 0;" "$(s42_numstat "$R48F")"
expect_absent "48f5 …and it names no row returned" "back to pending" "$OUT"
s42_snap "$R48F" "$P48F"
poke "$R48F" proof-add review record/wave-01-fixture/review.md
expect_eq "48g F3 the live review's own proof exits 0" "0" "$RC"
expect_eq "48g2 …and returns T3 to pending, its agent cleared" \
  "T3|6|review|follows the build|—|—|30|REQ-1|.bionic/docs/record/wave-01-fixture/review.md|—|—|pending|" \
  "$(s48_row "$P48F" T3)"
expect_eq "48g3 …and only T3: the final review stays active" "active" \
  "$(s48_row "$P48F" T8 | awk -F'|' '{ print $12 }')"
# REVIEW 14 S4 (wave-26 T51): A REVIEW PROOF THAT RETURNS NO LIVE ROW SAYS SO. The live review's
# record was written under another name than its Files cell (`review-14.md`, Files `review.md`):
# the proof returns no row, rightly (T46), and through T46 the success line said nothing of it, so
# the active pass was never offered again and nobody saw why. The verb now names the active live
# review rows and their Files on such a proof, and still resets none of them. The control: once no
# live review is active, the final review's proof says nothing of the kind.
awk -F'|' 'BEGIN { OFS = "|" } $2 == " T3 " { $6 = " w-T3 "; $13 = " active " } { print }' "$P48F" > "$P48F.tmp" && mv "$P48F.tmp" "$P48F"
expect_eq "48h precondition: the live review T3 is active again, its agent named" \
  "T3|6|review|follows the build|w-T3|—|30|REQ-1|.bionic/docs/record/wave-01-fixture/review.md|—|—|active|" \
  "$(s48_row "$P48F" T3)"
cp "$R48F/.bionic/docs/record/wave-01-fixture/review.md" "$R48F/.bionic/docs/record/wave-01-fixture/review-14.md"
poke "$R48F" proof-add review record/wave-01-fixture/review-14.md
expect_eq "48h S4 a review proof no live row's Files hold exits 0" "0" "$RC"
expect_contains "48h2 S4 …and says it returned no live review row, naming the active one and its Files" \
  "no active live review row holds record/wave-01-fixture/review-14.md in its Files: T3 (.bionic/docs/record/wave-01-fixture/review.md)" "$OUT"
expect_eq "48h3 …and resets nothing: T3 stays active under its agent" \
  "T3|6|review|follows the build|w-T3|—|30|REQ-1|.bionic/docs/record/wave-01-fixture/review.md|—|—|active|" \
  "$(s48_row "$P48F" T3)"
poke "$R48F" proof-add review record/wave-01-fixture/review.md
expect_contains "48h4 control precondition: T3's own proof returns it" "T3 back to pending" "$OUT"
poke "$R48F" proof-add review record/wave-01-fixture/final.md
expect_eq "48h5 control: with no live review active, the final review's proof exits 0" "0" "$RC"
expect_absent "48h6 control …and says nothing of live rows" "no active live review row holds" "$OUT"
POKE_BOUND="$S48_BOUND_WAS"

# ============================================================
section "Section 49 §SYNC: the tick applies the launches the plan lacks, in one write (wave-26 T32, D4; review-3 F1, F2)"
# ============================================================
#
# The launch recorder starts `launch-sync` and does not wait for it. The tick runs the same
# transaction before it reads the plan, so a launch the detached call did not record (killed,
# refused, or never started) is recorded here and says so once, and one that cannot be recorded
# is printed on every tick until it is fixed. The fixture is §34's plan, which the real commit
# gate admits, with T2's agent cell naming a launch on the roster (the gate reads it there).
S49_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R49="$(make_repo s49-sync)"; ( cd "$R49" && git commit -q --allow-empty -m init )
P49="$(s34_plan "$R49" 4)"
sed -e 's/^| T2 | 4 | build | the second build | implementor |/| T2 | 4 | build | the second build | w-T2 |/' \
    "$P49" > "$P49.tmp" && mv "$P49.tmp" "$P49"
awk '{ print } /^- T5: pending dispatch/ { print "- T6: pending dispatch"; print "- T7: pending dispatch" }
  /^\| T2 \| 4 \| build/ {
  print "| T6 | 4 | build | the sixth build | — | — | 30 | REQ-1 | f.sh | — | — | pending |"
  print "| T7 | 4 | build | the seventh build | — | — | 30 | REQ-1 | g.sh | — | — | pending |" }' "$P49" > "$P49.tmp" && mv "$P49.tmp" "$P49"
new_roster "$R49"
add_row "$R49" name=w-T2 agent_id=a-w-T2 launched_at="$(iso_ago 600)"
add_row "$R49" name=w-T6 agent_id=a-w-T6 launched_at="$(iso_ago 60)" deliverable=t6.md duration="45 minutes" \
  subagent_type=bionic:implementor
# A real linked worktree, its path as git lists it: the record counts nothing else (wave-26 T40).
T49_TREE="$(cd "$R49" && pwd -P)/.worktrees/01-T6"; git -C "$R49" worktree add -q -b wt/01-T6 "$T49_TREE" >/dev/null 2>&1
printf 'workspace/v1|session=%s|name=w-T6|path=%s|branch=wt/01-T6|base=0123456789abcdef0123456789abcdef01234567|plan=%s|at=2026-10-04T03:36:00Z\n' \
  "$SID" "$T49_TREE" "$P49" >> "$R49/.bionic/tmp/workspaces-$SID.state"
expect_contains "49 precondition: T6 is in the table, pending" "| f.sh | — | — | pending |" "$(grep '^| T6 |' "$P49")"
s34_gate "$R49"
expect_eq "49 precondition: the fixture is admitted by the real commit gate" "0" "$GATE_RC"

poke_pressure "$R49" 8192 1.0 tick
expect_contains "49a §SYNC the tick records the launch the plan lacked, and says so" "poker: LAUNCHED T6 w-T6" "$OUT"
expect_contains "49a2 …row T6 is active in its tree" "| w-T6 | — | 30 | REQ-1 | f.sh | .worktrees/01-T6 | 01234567 | active |" \
  "$(grep '^| T6 |' "$P49")"
expect_absent "49a3 …and the ready set it fills from no longer offers T6" "FILL T6" "$OUT"
poke_pressure "$R49" 8192 1.0 tick
expect_absent "49b …the next tick has nothing to record and says nothing of it" "poker: LAUNCHED" "$OUT"
expect_contains "49b2 …while it still decides" "decision=" "$OUT"

# 49c: a launch that cannot be recorded (a build row, no tree) is printed by the tick.
add_row "$R49" name=w-T7 agent_id=a-w-T7 launched_at="$(iso_ago 30)" deliverable=t7.md duration="45 minutes"
cp "$P49" "$TMPROOT/s49-before"
poke_pressure "$R49" 8192 1.0 tick
expect_contains "49c §SYNC the tick prints the launch it could not record" "poker: NOT-RECORDED T7 w-T7" "$OUT"
expect_contains "49c2 …with the command to run by hand" "task-set T7 status=active agent=w-T7" "$OUT"
expect_true "49c3 …and the plan is unchanged" cmp -s "$TMPROOT/s49-before" "$P49"
expect_eq "49d no projection copy is left beside the plan" "" \
  "$(find "$R49/.bionic/docs/plans" -name '*.plan.md.*' 2>/dev/null)"

# 49f (wave-26 T51; review 13 F1): the lock cannot be made — .bionic/tmp is not writable. The tick's
# call leaves a held lock to its holder and does not wait, yet through T32 its takeover arm looped
# without a bound and the tick never returned. Run in a process group of its own, bounded, and
# killed whole past the bound; what it left running is read by working directory.
s49_procs() {  # <dir> -> the pids of bash processes whose working directory is <dir> or below it
  local d
  d="$(cd "$1" 2>/dev/null && pwd -P)" || return 0
  lsof -a -c bash -d cwd -Fpn 2>/dev/null | awk -v d="$d" '
    /^p/ { p = substr($0, 2); next }
    /^n/ { n = substr($0, 2); if (n == d || index(n, d "/") == 1) print p }'
}
s49_tick_bounded() {  # <seconds> <repo> -> OUT, RC; 124, the tick's whole group killed, past the bound
  local i=0 n=$(( $1 * 10 )) p
  rm -f "$TMPROOT/s49f.rc"
  p="$( set -m
    ( cd "$2" && env CLAUDE_CODE_SESSION_ID="$SID" BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 \
        bash "$POKER" tick > "$TMPROOT/s49f.out" 2>&1
      echo "$?" > "$TMPROOT/s49f.rc" ) </dev/null >/dev/null 2>&1 &
    echo "$!" )"
  while [ ! -s "$TMPROOT/s49f.rc" ] && [ "$i" -lt "$n" ]; do sleep 0.1; i=$((i + 1)); done
  if [ -s "$TMPROOT/s49f.rc" ]; then RC="$(cat "$TMPROOT/s49f.rc")"; else kill -9 -- "-$p" 2>/dev/null; RC=124; fi
  OUT="$(cat "$TMPROOT/s49f.out" 2>/dev/null)"
}
require_helpers s49_procs s49_tick_bounded
command -v lsof >/dev/null 2>&1 || { echo "session-poker: lsof absent — 49f cannot read what it left running"; exit 1; }
( cd "$R49" && while :; do sleep 1; done ) & S49_PLANT=$!
sleep 0.5
expect_contains "49f precondition: a process the row starts in the repo is found by its working directory" \
  " $S49_PLANT " " $(s49_procs "$R49" | tr '\n' ' ')"
kill "$S49_PLANT" 2>/dev/null; wait "$S49_PLANT" 2>/dev/null
poke_bind "$R49"
chmod a-w "$R49/.bionic/tmp"
s49_tick_bounded 20 "$R49"
chmod u+w "$R49/.bionic/tmp"
expect_ne "49f §F1 the tick returns when the launch lock cannot be made (rc $RC; 124 is the bound)" "124" "$RC"
expect_contains "49f2 …and prints that the lock cannot be made" "cannot be made" "$OUT"
expect_eq "49f3 …and leaves nothing running" "" "$(s49_procs "$R49")"

# 49e (wave-26 T32; T14, AC-6.5): the offered review names the range it reads. §48's world as it
# ends: a review proof at A, one landing to B, the review offered again. The digest is removed so
# the tick prints in full; the head is the one the tick reads for live:head, with no git of its own.
expect_nonempty "49e precondition: §48 left its world and both heads" "${R48:-}${W48_A:-}${W48_B:-}"
rm -f "$R48/.bionic/tmp/tick-digest-$SID.state"
poke_pressure "$R48" 8192 1.0 tick
expect_eq "49e precondition: the tick offers the review" "yes" "$(s48_fill_has T3)"
expect_contains "49e AC-6.5 …and names the range it reads, the proof's head to the head now" \
  "poker: RANGE T3 ${W48_A}..${W48_B}" "$OUT"
expect_absent "49e2 …and only for the review: the active build has no RANGE line" "poker: RANGE T2" "$OUT"
# 49e3 (wave-26 T62; critic 3 S3): THE DIGEST THIS REAL TICK WROTE CARRIES THAT HEAD. The turn-end
# wall reads `head=` from it and hands it to the same ready set (stop.sh); stop.test.sh §LH plants
# the field by hand, so this is the one row that reads what the tick itself wrote.
expect_eq "49e3 …and the digest the tick wrote carries the head it judged live:head against" "head=${W48_B}" \
  "$(/usr/bin/grep -E '^head=' "$(digest_of "$R48")" 2>/dev/null)"
POKE_BOUND="$S49_BOUND_WAS"


# ============================================================
section "Section 50 §FIRST-TICK: the armed first tick names the ready set — FILL, WAIT and CHAIN from the scheduler's one site (wave-26 T59; REQ-6 AC-6.6)"
# ============================================================
#
# THE FIRST TICK OF EVERY RUN FINDS NO ROSTER: arming precedes dispatch (§13a). Through T58 that
# arm printed the rung, the holds and the ledger, then `QUIET — armed, nothing dispatched yet`,
# and exited above the scheduler, so FILL, WAIT and CHAIN never printed on the one tick where
# every ready row is unstarted. Both arms now run the scheduler from one site, and the decision
# line agrees with what the tick printed: FILL with its `fill=` field when it names rows, QUIET
# (exit 0, stamp kept) when nothing is ready or approval is pending. The approval gate
# holds as everywhere: the gate is the plan's `approved-by:` line (wave-26 T13), so the plan at
# current: 3 below carries none, as a plan before Step-3 approval does.
s50_plan() {  # <repo> <current> <approved-by line, or empty> -> the plan path
  local f="$1/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
  mkdir -p "$(dirname "$f")"
  {
    printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
    printf 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=user\n'
    printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: %s\n%s\n\n- Step %s: in progress\n\n' "$2" "$3" "$2"
    printf '## Tasks\n\n%s' "$SP_TASKS_HEADER"
    printf '| T1 | 4 | build | ready, the long one | implementor | — | 20m | REQ-x | a.sh | pending |\n'
    printf '| T2 | 4 | build | ready | implementor | — | 10m | REQ-x | b.sh | pending |\n'
    printf '| T3 | 4 | build | ready | implementor | — | 5m | REQ-x | c.sh | pending |\n'
    printf '| T4 | 4 | build | waits on T1 | implementor | T1 | 15m | REQ-x | d.sh | pending |\n'
  } > "$f"
  printf '%s' "$f"
}
s50_last() { printf '%s\n' "$OUT" | tail -1; }

R50="$(make_repo s50-first-tick)"
poke "$R50" arm
s50_plan "$R50" 4 "$SP_APPROVED_LINE" >/dev/null
poke_pressure "$R50" 8192 1.0 tick
expect_eq "50a the armed first tick exits 0" "0" "$RC"
expect_eq "50a3 precondition: …with no roster file on disk, the no-roster arm" "no" "$([ -e "$(roster_of "$R50")" ] && echo yes || echo no)"
expect_contains "50b the first tick fills the three ready rows" "poker: FILL T1 T2 T3" "$OUT"
expect_contains "50c …names the waiting row with the read it lacks and its writer" \
  "poker: WAIT T4 — waits for T1 (pending)" "$OUT"
expect_contains "50d …and the longest chain, by hand: 20 + 15" "poker: CHAIN T1→T4 (35 min)" "$OUT"
expect_contains "50a2 …and its sentence is the FILL band's own" \
  "poker: FILL — T1 T2 T3 named for dispatch; the decision line carries them." "$OUT"
S50_FILL="$(s38_line_no 'poker: FILL T')"; S50_WAIT="$(s38_line_no 'poker: WAIT ')"
S50_CHAIN="$(s38_line_no 'poker: CHAIN ')"; S50_SAID="$(s38_line_no 'poker: FILL — ')"
expect_true "50e …each above the band's sentence (fill=$S50_FILL wait=$S50_WAIT chain=$S50_CHAIN said=$S50_SAID)" \
  test "$S50_FILL" -gt 0 -a "$S50_WAIT" -gt "$S50_FILL" -a "$S50_CHAIN" -gt "$S50_WAIT" -a "$S50_SAID" -gt "$S50_CHAIN"
expect_regex "50f the decision line agrees with what the tick printed: last, FILL, and the fill field" \
  '^poker-tick/v1\|at=[^|]+\|session=[^|]+\|decision=FILL\|total=0\|open=0\|fill=T1 T2 T3$' "$(s50_last)"
expect_absent "50f2 …and the QUIET sentence is not printed beside it" "poker: QUIET" "$OUT"
expect_eq "50g the gate line prints once, from the one site" "1" "$(count_lines_matching 'poker: gate share=' "$OUT")"
expect_eq "50h the stamp is kept" "yes" "$([ -f "$(stamp_of "$R50")" ] && echo yes || echo no)"
expect_eq "50i the tick digest the stop collector reads carries the FILL band, and the duty it owes" \
  "decision=FILL duty=owed" \
  "$(/usr/bin/grep -E '^(decision|duty)=' "$R50/.bionic/tmp/tick-digest-$SID.state" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"

# 50k — A FIRST TICK WITH NOTHING READY IS STILL QUIET: the one row waits on the world.
R50K="$(make_repo s50-first-tick-nothing-ready)"
poke "$R50K" arm
sp_plan_at_step "$R50K" 4 \
  "| T1 | 4 | build | waits on CI | implementor | ext:ci-50k | 15m | REQ-x | a.sh | pending |" >/dev/null
poke_pressure "$R50K" 8192 1.0 tick
expect_eq "50k the first tick with nothing ready exits 0" "0" "$RC"
expect_contains "50k2 precondition: …and read the plan: the held row is named" "poker: HELD T1 ext:ci-50k" "$OUT"
expect_absent "50k3 …names no row to fill" "poker: FILL" "$OUT"
expect_contains "50k4 …and decides QUIET in the no-roster arm" \
  "poker: QUIET — armed, nothing dispatched yet on this session" "$OUT"
expect_regex "50k5 …with the QUIET decision line, no fill field" \
  '^poker-tick/v1\|at=[^|]+\|session=[^|]+\|decision=QUIET\|total=0\|open=0$' "$(s50_last)"
expect_contains "50k6 …and a digest that says QUIET" "decision=QUIET" \
  "$(cat "$R50K/.bionic/tmp/tick-digest-$SID.state" 2>/dev/null)"

# 50j — THE SAME TABLE BEFORE STEP-3 APPROVAL: no FILL, no WAIT, no CHAIN, the approval line,
# and the same QUIET decision and exit code.
R50B="$(make_repo s50-first-tick-step3)"
poke "$R50B" arm
s50_plan "$R50B" 3 "" >/dev/null
poke_pressure "$R50B" 8192 1.0 tick
expect_eq "50j the first tick before approval exits 0" "0" "$RC"
expect_contains "50j2 …and prints the approval line" \
  "poker: no FILL — plan at current: 3, Step-3 approval pending" "$OUT"
expect_absent "50j3 …and names no row to fill" "poker: FILL" "$OUT"
expect_absent "50j4 …no WAIT line" "poker: WAIT" "$OUT"
expect_absent "50j5 …and no CHAIN line" "poker: CHAIN" "$OUT"
expect_contains "50j6 …deciding QUIET in the no-roster arm" \
  "poker: QUIET — armed, nothing dispatched yet on this session" "$OUT"
expect_regex "50j7 …with the decision line unchanged" \
  '^poker-tick/v1\|at=[^|]+\|session=[^|]+\|decision=QUIET\|total=0\|open=0$' "$(s50_last)"

# ============================================================
section "Section 51 §ADD-READS: a task added mid-run says what it reads, and the graph is the one a fresh derivation gives (wave-26 T59; REQ-5 AC-5.4)"
# ============================================================
#
# `task-add` takes an optional tenth operand, `<reads>`, passed to `units_add_row` as the row's
# reads cell (wave-26 T2, A-T2.14). In a table with a reads column a row waits for what it
# reads and its deps carry only `ext:<slug>`, so the add needs no hand-written dependency: its
# edges come from the table. A `—` reads is the cell `—`, which the readiness program reads as
# the kind's default. A reads operand on a table with no reads column has nowhere to go and is
# refused, unless it is `—`, which writes what the nine-operand form writes.
#
# THE FIXTURE IS §34's, WITH A reads COLUMN: s34_plan's admitted plan, its table widened by one
# column and T5's deps (task ids, which a reads table refuses) emptied.
S51_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
S51_UNITS="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/units.sh"
s51_plan() {  # <repo> -> the plan path; s34_plan's, with a reads column
  local p; p="$(s34_plan "$1" 4)"
  awk '/^## Tasks/ { t = 1 } /^## Verification/ { t = 0 }
       t && /^\| id / { print $0 " reads |"; next }
       t && /^\|---/ { print $0 "---|"; next }
       t && /^\| T/ { sub(/\| T1, T2 \|/, "| — |"); print $0 " — |"; next }
       { print }' "$p" > "$p.tmp" && mv "$p.tmp" "$p"
  printf '%s' "$p"
}
s51_edges() { bash -c '. "$1" && units_edges "$2"' _ "$S51_UNITS" "$1" 2>/dev/null | LC_ALL=C sort; }  # <plan>
s51_rows() { /usr/bin/grep '^| T[0-9]' "$1"; }  # <plan> -> its task rows

R51="$(make_repo s51-add-reads)"; ( cd "$R51" && git commit -q --allow-empty -m init )
P51="$(s51_plan "$R51")"
s34_gate "$R51"
expect_eq "51a precondition: the reads-table fixture is admitted by the real commit gate" "0" "$GATE_RC"
S51_ROWS_BEFORE="$(s51_rows "$P51")"
poke "$R51" task-add T6 4 build 'reads what T2 writes' bionic:implementor '—' 30 REQ-5 'lib/c.sh' 'b.sh'
expect_eq "51b task-add with a reads operand and no deps exits 0" "0" "$RC"
expect_contains "51b2 …the reads operand is the row's reads cell" \
  "| T6 | 4 | build | reads what T2 writes | bionic:implementor | — | 30 | REQ-5 | lib/c.sh | — | — | pending | b.sh |" "$(cat "$P51")"
S51_EDGES="$(s51_edges "$P51")"
expect_contains "51c AC-5.4 the added row's edge comes from what it reads: T2 writes b.sh" \
  "$(printf 'T2\tT6\tb.sh')" "$S51_EDGES"
# THE FRESH DERIVATION: the same table written by hand in a second repo, its edges derived.
R51F="$(make_repo s51-add-reads-fresh)"; ( cd "$R51F" && git commit -q --allow-empty -m init )
P51F="$(s51_plan "$R51F")"
awk '{ print }
     /^\| T5 \| 5 \|/ { print "| T6 | 4 | build | reads what T2 writes | bionic:implementor | — | 30 | REQ-5 | lib/c.sh | — | — | pending | b.sh |" }
     /^- T5: / { print "- T6: pending dispatch — by hand" }' "$P51F" > "$P51F.tmp" && mv "$P51F.tmp" "$P51F"
expect_nonempty "51d precondition: the hand-written table derives edges" "$(s51_edges "$P51F")"
expect_eq "51d2 AC-5.4 the graph after the add equals a fresh derivation of the same table" \
  "$(s51_edges "$P51F")" "$S51_EDGES"
expect_eq "51e no other row is touched: T6 is appended to no later row's deps (every other row byte-identical)" \
  "$S51_ROWS_BEFORE" "$(s51_rows "$P51" | /usr/bin/grep -v '^| T6 ')"
s34_gate "$R51"
expect_eq "51f the next commit is admitted" "0" "$GATE_RC"

# 51g — REFUSALS LEAVE THE PLAN BYTE-IDENTICAL (cmp, §42's helpers).
s42_snap "$R51" "$P51"
poke "$R51" task-add T6 4 build 'the same id again' implementor '—' 30 REQ-5 'lib/d.sh' 'a.sh'
s42_unchanged "51g a duplicate id with a reads operand" 1 "$P51"
expect_contains "51g2 …naming the duplicate" "T6: duplicate id" "$OUT"
poke "$R51" task-add T7 4 build 'a read naming nothing' implementor '—' 30 REQ-5 'lib/d.sh' 'nonsense'
s42_unchanged "51g3 a reads token naming no artifact" 1 "$P51"
expect_contains "51g4 …in the validator's words" "read nonsense names no artifact" "$OUT"
poke "$R51" task-add T7 4 build 'a bare word for Files' implementor '—' 30 REQ-5 'CHANGELOG' 'a.sh'
s42_unchanged "51g5 a Files operand the dispatch grammar refuses" 1 "$P51"
poke "$R51" task-add T7 4 build 'eleven' implementor '—' 30 REQ-5 'lib/d.sh' 'a.sh' extra
s42_unchanged "51g6 eleven operands are the usage error" 2 "$P51"
expect_contains "51g7 …and the usage names the optional reads operand" "[<reads>]" "$OUT"

# 51h — TEN OPERANDS ON A TABLE WITHOUT THE COLUMN: a read has nowhere to go, so it is refused
# in one line, the plan byte-identical; `—` is the nine-operand form, byte for byte.
R51N="$(make_repo s51-no-reads)"; ( cd "$R51N" && git commit -q --allow-empty -m init )
P51N="$(s42_plan "$R51N" 4)"
s42_snap "$R51N" "$P51N"
poke "$R51N" task-add T6 4 build 'reads into no column' implementor '—' 30 REQ-5 'lib/c.sh' 'b.sh'
s42_unchanged "51h a reads operand on a table with no reads column" 1 "$P51N"
expect_contains "51h2 …saying why, in one line" "has no reads column" "$OUT"
poke "$R51N" task-add T6 4 build 'the dash reads' implementor '—' 30 REQ-5 'lib/c.sh' '—'
expect_eq "51h3 a — reads on that table is admitted" "0" "$RC"
R51M="$(make_repo s51-nine)"; ( cd "$R51M" && git commit -q --allow-empty -m init )
P51M="$(s42_plan "$R51M" 4)"
poke "$R51M" task-add T6 4 build 'the dash reads' implementor '—' 30 REQ-5 'lib/c.sh'
expect_eq "51h4 precondition: the nine-operand add of the same row exits 0" "0" "$RC"
expect_eq "51h5 …and the — reads wrote what the nine-operand form writes, byte for byte (the add's instant aside)" \
  "$(sed -E 's/ added by task-add at [0-9TZ:-]+$//' "$P51M")" "$(sed -E 's/ added by task-add at [0-9TZ:-]+$//' "$P51N")"
POKE_BOUND="$S51_BOUND_WAS"

# ============================================================
section "Section 52 §RUN-END: integrate waits for an open build, and the WAIT line names it (wave-26 T62; critic 2 K2-F5)"
# ============================================================
#
# A reads table at current: 8, the floor and the review both proved, the review row landed, and
# a late fix from the review still active. Integrate reads its default, now `proof:floor,
# proof:review, head`, so the open build holds the merge and the tick says so. Through T61 the
# tick offered the merge beside the build (FILL T3) and the turn-end wall demanded it.
# THE PROOFS NAME THE HEAD THE WORKING BRANCH IS AT (wave-26 T64): from T64 a floor proof stands
# only while proof_state answers covered or bounded, so the repository gets one commit, the plan
# names its branch as `working-branch:`, and both proofs name that commit, not a made-up hex.
s52_plan() {  # <repo> <T6 status> -> the plan path
  local f h b
  ( cd "$1" && git commit -q --allow-empty -m init ) >/dev/null 2>&1
  h="$(git -C "$1" rev-parse HEAD 2>/dev/null)"; b="$(git -C "$1" symbolic-ref --short HEAD 2>/dev/null)"
  f="$(s47_plan "$1" 2 \
    "| T1 | 4 | build | landed | implementor | — | 30 | REQ-x | payload/x.sh | landed | |" \
    "| T5 | 5 | verify | the floor | test-runner | — | 30 | REQ-x | .bionic/docs/record/floor.log | landed | |" \
    "| T2 | 6 | review | the final review | critic | — | 30 | REQ-x | .bionic/docs/record/review.md | landed | |" \
    "| T6 | 6 | build | late fix from the review | implementor | — | 20 | REQ-x | payload/x.sh | $2 | |" \
    "| T3 | 8 | integrate | merge to main | — | — | 10 | REQ-x | — | pending | |")"
  awk -v h="$h" -v b="$b" '
    /^governing-skill: / && !fm { print; print "rigor: tested"; print "scale: wave"; fm = 1; next }
    /^current: / { print "current: 8"; print "working-branch: " b; print "base-sha: " h; next }
    { print }
    /^approved-by: / { print "proved: kind=floor head=" h " at=2026-10-04T11:00:00Z evidence=record/floor.log"
                       print "proved: kind=review head=" h " at=2026-10-04T11:05:00Z evidence=record/review.md" }' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  printf '%s' "$f"
}
# THE READINGS THE RUN OWES, HELD AT THE HEAD (wave-27 T14; D3). From T14 integrate's proof:review
# is met only when lib/proof.sh `facts_state` holds the plan at the working head, which the tick
# asks once and hands in. These sections are about the build and the floor, so the plan is handed
# what a run at Step 8 has: every reading `facts_owed` deals its rigor and scale, `result=pass`, at
# <head>, written by the product's pair (`proof_line` placed by `proof_add_line`).
owed_readings() {  # <plan> <head> -> the readings appended to the plan
  bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1
    facts_owed "$(plan_frontmatter_get "$2" rigor)" "$(plan_frontmatter_get "$2" scale)" \
      | while IFS="	" read -r k q role scope; do
          [ "$k" = review ] || continue
          proof_add_line "$2" "$(proof_line review "$3" 2026-10-04T12:00:00Z "record/$q-$scope.md" "$q" w-read pass "$scope")" > "$2.or" \
            && mv "$2.or" "$2"
        done' _ "${BIONIC_HOOKS_DIR}/../payload/scripts/lib" "$1" "$2"
}
R52="$(make_repo s52-open-build)"; new_roster "$R52"; S52_P="$(s52_plan "$R52" active)"
owed_readings "$S52_P" "$(git -C "$R52" rev-parse HEAD)"
expect_eq "52a0 precondition: the plan (tested, wave) holds its five readings at the head: facts_state reads each covered" "5" \
  "$(bash -c '. "$1/proof.sh" && facts_state "$2" "$3"' _ "${BIONIC_HOOKS_DIR}/../payload/scripts/lib" "$S52_P" "$(git -C "$R52" rev-parse HEAD)" 2>/dev/null \
     | awk -F'\t' '$1 == "review" && $NF == "covered"' | wc -l | tr -d ' ')"
add_row "$R52" name=w-T6 deliverable=T6.md duration="1 hour" launched_at="$(iso_ago 10)"
poke_pressure "$R52" 8192 1.0 tick
expect_nonempty "52a precondition: the tick prints WAIT lines (the extractor reads real output)" "$(s47_lines WAIT)"
expect_contains "52a2 K2-F5 integrate waits on head, and its WAIT line names the late build" \
  "poker: WAIT T3 — reads head, written by T6 (active)" "$OUT"
R52L="$(make_repo s52-landed)"; new_roster "$R52L"; S52_PL="$(s52_plan "$R52L" landed)"
owed_readings "$S52_PL" "$(git -C "$R52L" rev-parse HEAD)"
poke_pressure "$R52L" 8192 1.0 tick
expect_contains "52b the build landed, both proofs in: the merge is offered" "poker: FILL T3" "$OUT"

# ============================================================
section "Section 53 §REVIEW-RANGE: a review proof starts where the last one ended (wave-26 T62; critic 2 K2-F2)"
# ============================================================
#
# `reviewed: <a>..<b>`: through T61 only <b> was attested, so `<head~1>..<head>` and
# `zzzz..<head>` were recorded as a review of everything up to the head. <a> must now be a
# commit on <b>'s history, at or before the last review proof's head, or, before the first
# review proof, at or before the plan's base: the Step-4 block's `base-sha:`, a real commit here.
# The working branch is cut from that base and carries four commits, C1 to C4.
S53_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R53="$(make_repo s53-range)"; ( cd "$R53" && git commit -q --allow-empty -m init )
S53_B="$(git -C "$R53" rev-parse HEAD)"
P53="$(s42_plan "$R53" 4 "  worktree: .worktrees/01-fixture
  base-sha: ${S53_B:0:8}
  branch: wave/01-fixture")"
awk '{ print } /^current: / && !d { print "working-branch: wave/01-fixture"; d = 1 }' "$P53" > "$P53.tmp" && mv "$P53.tmp" "$P53"
( cd "$R53" && git add -f "$P53" && git commit -qm wb \
  && git worktree add -q -b wave/01-fixture "$R53/.worktrees/01-fixture" "$S53_B" ) >/dev/null 2>&1
for s53c in 1 2 3 4; do git -C "$R53/.worktrees/01-fixture" commit -q --allow-empty -m "C$s53c" >/dev/null 2>&1; done
S53_C1="$(git -C "$R53/.worktrees/01-fixture" rev-parse HEAD~3)"; S53_C2="$(git -C "$R53/.worktrees/01-fixture" rev-parse HEAD~2)"
S53_C3="$(git -C "$R53/.worktrees/01-fixture" rev-parse HEAD~1)"; S53_C4="$(git -C "$R53/.worktrees/01-fixture" rev-parse HEAD)"
S53_REC="$R53/.bionic/docs/record/wave-01-fixture"; mkdir -p "$S53_REC"
s53_review() { printf '# review\n\nreviewed: %s..%s\n' "$1" "$2" > "$S53_REC/$3"; }  # <a> <b> <file>
expect_regex "53a0 precondition: the working branch's head is C4, a 40-hex commit" '^[0-9a-f]{40}$' "$S53_C4"
expect_eq "53a0b precondition: the plan's base is the branch point" "$S53_B" \
  "$(git -C "$R53" merge-base "$S53_B" "$S53_C1")"
s53_review "$S53_C1" "$S53_C2" first-late.md
s53_review zzzz "$S53_C2" junk.md
s53_review "$S53_C3" "$S53_C2" backwards.md
s53_review "${S53_B:0:10}" "$S53_C2" first.md
s42_snap "$R53" "$P53"
poke "$R53" proof-add review record/wave-01-fixture/first-late.md
s42_unchanged "53a the first review starting past the plan's base" 1 "$P53"
expect_contains "53a2 …naming the base and the range to read" \
  "starts at ${S53_C1:0:12}, past the plan's base ${S53_B:0:12}, so what landed between them is unread; review ${S53_B:0:12}..${S53_C2:0:12}" "$OUT"
poke "$R53" proof-add review record/wave-01-fixture/junk.md
s42_unchanged "53b a range whose start is no commit (the critic's zzzz)" 1 "$P53"
expect_contains "53b2 …saying so" "starts at zzzz, which is no commit here" "$OUT"
poke "$R53" proof-add review record/wave-01-fixture/backwards.md
s42_unchanged "53c a range whose start is not on its end's history" 1 "$P53"
expect_contains "53c2 …saying so" "which is not on the history of its end ${S53_C2:0:12}" "$OUT"
poke "$R53" proof-add review record/wave-01-fixture/first.md
expect_eq "53d the first review from the base is recorded (exit 0)" "0" "$RC"
expect_eq "53d2 …at the end it read" "$S53_C2" "$(s46_last "$P53" review)"
# THE NEXT REVIEW STARTS AT OR BEFORE C2. One that read only the last commit, C3..C4, leaves C3
# unread and is refused; C2..C4 and an overlap from C1 are both recorded.
s53_review "$S53_C3" "$S53_C4" narrow.md
s53_review "$S53_C2" "$S53_C4" second.md
s42_snap "$R53" "$P53"
poke "$R53" proof-add review record/wave-01-fixture/narrow.md
s42_unchanged "53e K2-F2 a review of <head~1>..<head> past the last review proof" 1 "$P53"
expect_contains "53e2 …naming the proof and the range to read" \
  "starts at ${S53_C3:0:12}, past the last review proof ${S53_C2:0:12}, so what landed between them is unread; review ${S53_C2:0:12}..${S53_C4:0:12}" "$OUT"
poke "$R53" proof-add review record/wave-01-fixture/second.md
expect_eq "53f the review from the last proof is recorded (exit 0)" "0" "$RC"
expect_eq "53f2 …at its end" "$S53_C4" "$(s46_last "$P53" review)"
s53_review "$S53_C1" "$S53_C4" overlap.md
poke "$R53" proof-add review record/wave-01-fixture/overlap.md
expect_eq "53g a review that starts before the last proof (an overlap) is recorded" "0" "$RC"
POKE_BOUND="$S53_BOUND_WAS"

# ============================================================
section "Section 54 §FULL-RUN-REQUIRED: integrate waits for a full run when the change past the floor proof cannot be bounded (wave-26 T64; REQ-3 AC-3.3, AC-3.4)"
# ============================================================
#
# AC-3.4: "A second full run is required when the change cannot be bounded … Fails when a planted
# new file under a directory no suite names lands with no suite run at all." Through T63 the run
# only ADMITTED that full run: a task tree with no suite stamp lands (by design: a file no suite
# names has no affected suite), and integrate's `proof:floor` read took any floor proof line,
# whatever its head, so the tick offered the merge on a change no suite had read.
#
# EVERYTHING HERE IS THE PRODUCT'S OWN: the working branch `wave/01-fixture` in a linked checkout
# (as §46); its full runs are the shipped suite runner, copied byte for byte into the fixture with
# three green suites (runner-roster's recipe), so every log is a real runner's log; each proof
# line is written by `proof-add`; each task tree lands through the real `worktree_land`; the WAIT
# and FILL lines are the tick's. The map (`impact-command:`) answers lib/one.sh with two suites,
# lib/every.sh with all three, anything else with nothing. Integrate reads its kind default.
S54_BOUND_WAS="$POKE_BOUND"; POKE_BOUND=180
R54="$(make_repo s54-full-run)"; new_roster "$R54"
S54_WT="$R54/.worktrees/01-fixture"
S54_REC="$R54/.bionic/docs/record/wave-01-fixture"
S54_MAP="$TMPROOT/s54-map.sh"
S54_COUNT="$TMPROOT/s54-map.count"
S54_WTLIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/worktree.sh"
{
  printf '#!/bin/bash\n'
  printf 'printf "x\\n" >> "%s"\n' "$S54_COUNT"
  printf 'for f in "$@"; do\n'
  printf '  case "$f" in\n'
  printf '    lib/one.sh)   for s in a b; do printf "%%s.test.sh\\tdir-ref:%%s\\n" "$s" "$f"; done ;;\n'
  printf '    lib/every.sh) for s in a b c; do printf "%%s.test.sh\\tdir-ref:%%s\\n" "$s" "$f"; done ;;\n'
  printf '  esac\n'
  printf 'done\n'
} > "$S54_MAP"
mkdir -p "$R54/tests/lib" "$R54/payload/scripts/lib" "$R54/lib" "$S54_REC"
cp "$BIONIC_SCRIPTS_DIR/tests/run.sh" "$R54/tests/run.sh"
cp "$BIONIC_SCRIPTS_DIR/tests/lib/resolve-roots.sh" "$BIONIC_SCRIPTS_DIR/tests/lib/assert.sh" "$R54/tests/lib/"
cp "$BIONIC_SCRIPTS_DIR"/payload/scripts/lib/*.sh "$R54/payload/scripts/lib/"
for s54s in a b c; do
  printf '#!/bin/bash\nset -uo pipefail\n. "$(dirname "$0")/lib/assert.sh"\nsection "%s"\nexpect_eq "%s ran" x x\nfinish\n' \
    "$s54s" "$s54s" > "$R54/tests/$s54s.test.sh"
done
printf 'one\n' > "$R54/lib/one.sh"; printf 'every\n' > "$R54/lib/every.sh"
printf '.bionic/\n.worktrees/\n' > "$R54/.gitignore"
( cd "$R54" && git add .gitignore tests payload lib && git commit -qm base ) >/dev/null 2>&1
S54_BASE="$(git -C "$R54" rev-parse HEAD 2>/dev/null)"
# A REAL BASE (wave-27 T14, on the T45 ruling): the judge deals no reading on a plan whose
# base-sha names no commit, so the Step-4 block names the commit the working branch is cut from.
P54="$(s42_plan "$R54" 4 "  worktree: .worktrees/01-fixture
  base-sha: ${S54_BASE}
  branch: wave/01-fixture")"
awk '
  /^current: / && !wb { print; print "working-branch: wave/01-fixture"; wb = 1; next }
  /^- T5: / { print; print "- T3: integrate at Step 8"; next }
  /^\| id \| step \|/ { intab = 1
    print "| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |"
    print "|---|---|---|---|---|---|---|---|---|---|---|---|---|"
    print "| T1 | 4 | build | the build | implementor | — | 30 | REQ-1 | lib/one.sh | — | — | landed |  |"
    print "| T5 | 5 | verify | the floor | test-runner | — | 30 | REQ-1 | .bionic/docs/record/wave-01-fixture/floor.log | — | — | landed |  |"
    print "| T2 | 6 | review | the final review | critic | — | 30 | REQ-1 | .bionic/docs/record/wave-01-fixture/final-review.md | — | — | landed |  |"
    print "| T3 | 8 | integrate | merge to main | — | — | 10 | REQ-1 | — | — | — | pending |  |"
    next }
  intab && /^\|/ { next }
  { intab = 0; print }' "$P54" > "$P54.tmp" && mv "$P54.tmp" "$P54"
( cd "$R54" && git add -f "$P54" && git commit -qm "reads table" \
  && git worktree add -q -b wave/01-fixture "$S54_WT" ) >/dev/null 2>&1
printf 'impact-command: bash %s\n' "$S54_MAP" > "$R54/.bionic/config.yaml"
# s54_full <log> -> the copied runner, run whole in the working checkout, its log in the record
s54_full() {
  ( cd "$S54_WT" && env -u BIONIC_GATE_ADMIT -u BIONIC_GATE_AGENT -u BIONIC_QUIET \
      -u BIONIC_LOAD_NOW_FILE BIONIC_GATE_DIR="$TMPROOT/s54-gate" BIONIC_GATE_POLL=0.1 \
      BIONIC_PROBE_USED_PCT=10 BIONIC_PROBE_BUSY_CORES=0 BIONIC_PRESSURE_RING="$TMPROOT/s54-ring" \
      BIONIC_TEST_JOBS_CEILING=2 BIONIC_PROBE_FREE_PCT=44 BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=0.1 \
      bash tests/run.sh ) > "$S54_REC/$1" 2>&1
}
# s54_land <id> <path> <content> -> a task tree on wt/01-<id> commits one file and NO suite runs
# in it (no stamp); the real land merges it. Leaves S54_LAND.
s54_land() {
  local t="$R54/.worktrees/01-$1"
  git -C "$S54_WT" worktree add -q -b "wt/01-$1" "$t" HEAD >/dev/null 2>&1
  mkdir -p "$(dirname "$t/$2")"; printf '%s\n' "$3" > "$t/$2"
  ( cd "$t" && git add "$2" && git commit -qm "$1: $2" ) >/dev/null 2>&1
  S54_LAND="$( . "$S54_WTLIB" >/dev/null 2>&1; worktree_land "$t" wave/01-fixture 2>&1 )"
}
# s54_floor <log> -> a full run on the working head, recorded by proof-add floor
s54_floor() { s54_full "$1"; poke "$R54" proof-add floor "record/wave-01-fixture/$1"; }
# s54_tick -> the tick at current: 8 (proof-add runs at current: 4, where the fixture plan's gate
# admits it; the tick reads current: 8, where integrate is no longer held for its step). The
# digest is cleared first, so each tick prints its whole reading rather than "unchanged" (as 48).
# FROM wave-27 T14 the review half is held at each tick's head (`owed_readings`, §52): this
# section is about the floor, so a reading of each question is taken on whatever landed.
s54_tick() {
  rm -f "$(digest_of "$R54")"
  owed_readings "$P54" "$(git -C "$S54_WT" rev-parse HEAD)"
  sed 's/^current: 4$/current: 8/' "$P54" > "$P54.tmp" && mv "$P54.tmp" "$P54"
  poke_pressure "$R54" 8192 1.0 tick
  sed 's/^current: 8$/current: 4/' "$P54" > "$P54.tmp" && mv "$P54.tmp" "$P54"
}
s54_wait() { s47_lines WAIT | /usr/bin/grep '^poker: WAIT T3 '; }

S54_W0="$(git -C "$S54_WT" rev-parse HEAD 2>/dev/null)"
s54_floor floor-1.log
expect_contains "54a0 precondition: the copied runner's log names the working head on a clean tree" \
  "head=${S54_W0} dirty=0" "$(cat "$S54_REC/floor-1.log")"
expect_contains "54a0b precondition: …and its verdict, every suite passed" "Gating: 3 passed, 0 failed" \
  "$(cat "$S54_REC/floor-1.log")"
expect_eq "54a0c precondition: proof-add floor recorded it (exit 0)" "0" "$RC"
printf '# final review\n\nreviewed: %s..%s\n' "$S54_BASE" "$S54_W0" > "$S54_REC/review.md"
poke "$R54" proof-add review record/wave-01-fixture/review.md
expect_eq "54a0d precondition: proof-add review recorded the review (exit 0)" "0" "$RC"
expect_eq "54a0e precondition: the plan's floor proof names the working head" "$S54_W0" "$(s46_last "$P54" floor)"
s54_tick
expect_contains "54a at the proved head integrate is offered" "poker: FILL T3" "$OUT"

# ---------- AC-3.4, the criterion's planted defect: a new file under a directory no suite names ----------
s54_land T7 newdir/x.sh 'new'
expect_contains "54b0 precondition: the task tree with no suite run LANDED through the real land" \
  "spawn-worktree: LANDED branch=wt/01-T7" "$S54_LAND"
expect_false "54b0b precondition: …and no suite ever stamped it" \
  test -e "$R54/.git/worktrees/01-T7/bionic-stamps"
S54_W1="$(git -C "$S54_WT" rev-parse HEAD 2>/dev/null)"
s54_tick
expect_nonempty "54b1 precondition: the tick prints a WAIT line for integrate (the extractor reads real output)" "$(s54_wait)"
expect_eq "54b AC-3.4 integrate WAITS: the head moved past the floor proof in a way the map cannot bound, and the line names the way out" \
  "poker: WAIT T3 — proof:floor: the head moved past the floor proof at ${S54_W0:0:12} in a way the map cannot bound (the map answers newdir/x.sh with no suite); take the full run on this head and record it with proof-add floor; proof:review: the facts the run owes do not hold (facts_state): the readings are judged once the floor holds" \
  "$(s54_wait)"
expect_absent "54b2 …and the merge is not offered" "poker: FILL T3" "$OUT"
# THE COST: one tick runs proof_state once, though its schedule and its change fingerprint each
# ask the ready set. The map is the one process the state runs that this suite can count.
: > "$S54_COUNT"; s54_tick; S54_TICK_MAPS="$(awk 'END { print NR + 0 }' "$S54_COUNT")"
: > "$S54_COUNT"; ( . "$S46_LIB" >/dev/null 2>&1; proof_state "$P54" "$R54" ) >/dev/null 2>&1
S54_PS_MAPS="$(awk 'END { print NR + 0 }' "$S54_COUNT")"
expect_true "54b2c precondition: one proof_state over this change calls the map (the counter reads real calls)" \
  test "$S54_PS_MAPS" -gt 0
expect_eq "54b2d …and one tick calls it exactly as often: the floor state is computed once per tick" \
  "$S54_PS_MAPS" "$S54_TICK_MAPS"
s54_floor floor-2.log
expect_eq "54b3 the way out: a full run on the new head, recorded with proof-add floor (exit 0)" "0" "$RC"
expect_eq "54b4 …at that head" "$S54_W1" "$(s46_last "$P54" floor)"
s54_tick
expect_contains "54b5 …and the tick offers the merge" "poker: FILL T3" "$OUT"

# ---------- AC-3.3 still holds: a bounded change after a full pass is proved by its suites ----------
s54_land T8 lib/one.sh 'one, changed'
expect_contains "54c0 precondition: the bounded change LANDED" "spawn-worktree: LANDED branch=wt/01-T8" "$S54_LAND"
s54_tick
expect_contains "54c AC-3.3 a change the map bounds leaves the pass standing: the merge is offered" "poker: FILL T3" "$OUT"
expect_eq "54c2 …with no WAIT line for it" "" "$(s54_wait)"

# ---------- a change the map answers with every suite ----------
s54_land T9 lib/every.sh 'every, changed'
expect_contains "54d0 precondition: the every-suite change LANDED" "spawn-worktree: LANDED branch=wt/01-T9" "$S54_LAND"
s54_tick
expect_contains "54d a change the map answers with every suite: integrate WAITS, saying so" \
  "poker: WAIT T3 — proof:floor: the head moved past the floor proof at ${S54_W1:0:12} in a way the map cannot bound (the map answers the change with every suite (3 of 3))" \
  "$OUT"
expect_absent "54d2 …and the merge is not offered" "poker: FILL T3" "$OUT"
s54_floor floor-3.log
s54_tick
expect_contains "54d3 …until a full run on its head is recorded" "poker: FILL T3" "$OUT"

# ---------- a merge of work from outside the run (a file the map bounds, so only the outside rule holds it) ----------
S54_W3="$(git -C "$S54_WT" rev-parse HEAD 2>/dev/null)"
( cd "$S54_WT" && git checkout -q -b other-work && printf 'one, from outside\n' > lib/one.sh \
  && git commit -qam 'outside work' && git checkout -q wave/01-fixture \
  && git merge -q --no-ff -m 'merge other-work' other-work ) >/dev/null 2>&1
expect_true "54e0 precondition: the outside commit is on the working branch" \
  git -C "$S54_WT" merge-base --is-ancestor other-work wave/01-fixture
s54_tick
expect_contains "54e a merge from outside the run: integrate WAITS, saying another branch carries it" \
  "poker: WAIT T3 — proof:floor: the head moved past the floor proof at ${S54_W3:0:12} in a way the map cannot bound (1 of 2 commits since ${S54_W3:0:7} are on another branch than wave/01-fixture" \
  "$OUT"
expect_absent "54e2 …and the merge is not offered" "poker: FILL T3" "$OUT"
s54_floor floor-4.log
s54_tick
expect_contains "54e3 …until a full run on the merge is recorded" "poker: FILL T3" "$OUT"
POKE_BOUND="$S54_BOUND_WAS"


# ============================================================
section "AMEND-ROOT: amend reads a Files: entry with the dispatch wall's one reader (wave-27 T29; REQ-12 AC-12.3, D21)"
# ============================================================
#
# THE DEFECT, from a real run: the stop wall printed `amend <name> --files+ 'CONTEXT.md'` and
# amend REFUSED it as a change of nothing, because the grammar read a Files: entry as a path
# only when it carried a `/`. amend now reads each addition with the one reader in brief.sh,
# the dispatch wall's own: a path carries a `/`, or an extension. A bare word is refused naming
# `./<word>`, whether or not a file of that name is at the root (wave-27 T42: no wall lists it).
RAR="$(make_repo amend-root)"; new_roster "$RAR"; s30_row "$RAR"
poke "$RAR" amend w1 --files+ 'CONTEXT.md' --reason 'the fix touches the root file'
expect_eq "AMEND-ROOT AC-12.3 amend --files+ 'CONTEXT.md' succeeds" "0" "$RC"
expect_eq "AMEND-ROOT …and files= holds the root file as written" "hooks/a.sh,CONTEXT.md" \
  "$(s30_field "$(s30_last "$RAR")" files)"
# A BARE WORD IS REFUSED THOUGH A FILE OF THAT NAME IS AT THE ROOT (wave-27 T42): T29's arm that
# listed the root is gone, and `./Widgetfile` is the spelling, with no listing behind it.
echo x > "$RAR/Widgetfile"
RAR_SUM="$(cksum < "$(roster_of "$RAR")")"
poke "$RAR" amend w1 --files+ Widgetfile --reason 'and the root build file'
expect_eq "AMEND-ROOT2 a bare word is REFUSED though the file is at the root (exit 1)" "1" "$RC"
expect_contains "AMEND-ROOT2 …naming the word and ./Widgetfile" "Files: names Widgetfile, not a path — spell it ./Widgetfile" "$OUT"
expect_eq "AMEND-ROOT2 …and writes nothing" "$RAR_SUM" "$(cksum < "$(roster_of "$RAR")")"
poke "$RAR" amend w1 --files+ ./Widgetfile --reason 'the spelling it named'
expect_eq "AMEND-ROOT2b its ./ spelling is accepted" "0" "$RC"
expect_eq "AMEND-ROOT2b …and stored as written" "hooks/a.sh,CONTEXT.md,./Widgetfile" \
  "$(s30_field "$(s30_last "$RAR")" files)"
# Any other entry refuses, naming the spelling that is accepted, and writes nothing.
RAR_SUM="$(cksum < "$(roster_of "$RAR")")"
poke "$RAR" amend w1 --files+ Otherfile --reason 'a name with no file behind it'
expect_eq "AMEND-ROOT3 an entry that is not read as a path is REFUSED (exit 1)" "1" "$RC"
expect_contains "AMEND-ROOT3 …naming the entry and the accepted spelling" "./Otherfile" "$OUT"
expect_eq "AMEND-ROOT3 …and writes nothing" "$RAR_SUM" "$(cksum < "$(roster_of "$RAR")")"
poke "$RAR" amend w1 --files+ ./Otherfile --reason 'the spelling it named'
expect_eq "AMEND-ROOT4 the spelling the refusal names is accepted" "0" "$RC"
expect_eq "AMEND-ROOT4 …and recorded" "hooks/a.sh,CONTEXT.md,./Widgetfile,./Otherfile" \
  "$(s30_field "$(s30_last "$RAR")" files)"
# TWO ADDITIONS IN ONE AMEND are two items of the list, never one item holding white space.
poke "$RAR" amend w1 --files+ lib/x.sh --files+ lib/y.sh --reason 'two at once'
expect_eq "AMEND-ROOT5 two --files+ in one amend succeed" "0" "$RC"
expect_eq "AMEND-ROOT5 …and both are recorded" "hooks/a.sh,CONTEXT.md,./Widgetfile,./Otherfile,lib/x.sh,lib/y.sh" \
  "$(s30_field "$(s30_last "$RAR")" files)"
# A PROSE ADDITION is refused once, naming it, with no ./ advice.
RAR_SUM="$(cksum < "$(roster_of "$RAR")")"
poke "$RAR" amend w1 --files+ 'lib/z.sh (new)' --reason 'a note in the path'
expect_eq "AMEND-ROOT6 an addition holding white space is REFUSED (exit 1)" "1" "$RC"
expect_contains "AMEND-ROOT6 …naming it whole" "Files: lib/z.sh (new) is not a path" "$OUT"
expect_absent "AMEND-ROOT6 …with no ./ advice" "./lib/z.sh" "$OUT"
expect_eq "AMEND-ROOT6 …and writes nothing" "$RAR_SUM" "$(cksum < "$(roster_of "$RAR")")"
# A DERIVED BUDGET with suites added re-derives the merged files: two of them are a list of two.
RAD="$(make_repo amend-root-derived)"; new_roster "$RAD"
printf '#!/bin/bash\necho tests/a.test.sh\n' > "$RAD/impact.sh"
mkdir -p "$RAD/.bionic"; printf 'impact-command: bash impact.sh\n' > "$RAD/.bionic/config.yaml"
s30_row "$RAD" files=hooks/a.sh,hooks/b.sh suites_source=derived
poke "$RAD" amend w1 --suites+ tests/c.test.sh --reason 'one more suite'
expect_eq "AMEND-ROOT7 a derived row holding two files takes a suite (exit 0)" "0" "$RC"
expect_contains "AMEND-ROOT7 …and the suite is on the row" "c.test.sh" \
  "$(s30_field "$(s30_last "$RAD")" suites_allowed)"
# EACH --files+ VALUE IS READ ON ITS OWN (wave-27 T34; review pass 19 should-fix 2, A-orch-70): the
# values used to be joined into one Files: line, so a ` #` note in one hid every later one and the
# call exited 0. A quoted value records the bare path, as the dispatch wall's reader reads one line.
RAC="$(make_repo amend-comment)"; new_roster "$RAC"; s30_row "$RAC"
poke "$RAC" amend w1 --files+ 'lib/x.sh # the hook' --files+ lib/y.sh --reason 'a note on the first'
expect_eq "AMEND-ROOT8 a note after the first value: both values recorded (exit 0)" "0" "$RC"
expect_eq "AMEND-ROOT8 …files= holds lib/x.sh and lib/y.sh" "hooks/a.sh,lib/x.sh,lib/y.sh" \
  "$(s30_field "$(s30_last "$RAC")" files)"
poke "$RAC" amend w1 --files+ '"lib/q.sh"' --reason 'a quoted path'
expect_eq "AMEND-ROOT9 a quoted value records the bare path (exit 0)" "0" "$RC"
expect_eq "AMEND-ROOT9 …files= gains lib/q.sh, no quote" "hooks/a.sh,lib/x.sh,lib/y.sh,lib/q.sh" \
  "$(s30_field "$(s30_last "$RAC")" files)"
# THE ROW'S QUESTIONS REACH THE CAP (wave-27 T34; T15's report items 1 and 2, A-orch-73): a critic
# holding `evidence` is held to three runs as an auditor is; one holding `adversarial` is not.
RAQ="$(make_repo amend-questions)"; new_roster "$RAQ"
s30_row "$RAQ" subagent_type=bionic:critic suites_allowed=none questions=evidence \
  're_executes=`npm test` `pytest tests/unit` `go test ./...`'
RAQ_SUM="$(cksum < "$(roster_of "$RAQ")")"
poke "$RAQ" amend w1 --reexec+ 'cargo test' --reason 'a fourth run'
expect_eq "AMEND-Q1 a critic holding evidence: a fourth run is REFUSED (exit 1)" "1" "$RC"
expect_contains "AMEND-Q1b …by the three-run cap" "3-run cap" "$OUT"
expect_eq "AMEND-Q1c …and the roster is unchanged" "$RAQ_SUM" "$(cksum < "$(roster_of "$RAQ")")"
RAQ2="$(make_repo amend-questions-adv)"; new_roster "$RAQ2"
s30_row "$RAQ2" subagent_type=bionic:critic suites_allowed=none questions=adversarial \
  're_executes=`npm test` `pytest tests/unit` `go test ./...`'
poke "$RAQ2" amend w1 --reexec+ 'cargo test' --reason 'a fourth run'
expect_eq "AMEND-Q2 control: a critic holding adversarial takes a fourth run (exit 0)" "0" "$RC"
expect_eq "AMEND-Q3 the amended row carries questions= from the row it copied" "adversarial" \
  "$(s30_field "$(s30_last "$RAQ2")" questions)"
poke "$RAQ2" extend w1 'more to read'
expect_eq "AMEND-Q4 extend's row carries questions= too (exit 0)" "0|adversarial" \
  "$RC|$(s30_field "$(s30_last "$RAQ2")" questions)"
R41Q="$(s41_world s41-hold-questions)"
s41_transcript 1 "w-1:idle"
printf '%s|questions=evidence\n' "$(grep -F '|name=w-1|' "$(roster_of "$R41Q")" | tail -1)" >> "$(roster_of "$R41Q")"
poke "$R41Q" hold w-1 'kept for a second pass'
expect_eq "AMEND-Q5 hold's row carries questions= too (exit 0)" "0|evidence" \
  "$RC|$(s30_field "$(grep -F '|name=w-1|' "$(roster_of "$R41Q")" | tail -1)" questions)"

# ============================================================
section "Section 55 §RECON-PLAN: the tick asks for a task-list reconcile when current: moves 3 to 4 and when the table grows (wave-27 T13; REQ-11 AC-11.3; D20)"
# ============================================================
#
# The tick's digest records the plan's `current:` and its `## Tasks` row count. The tick prints
# the same `poker: RECONCILE` line it already prints for a status or ready-set change when
# `current:` was 3 at the last digest and is 4 now, or the row count has grown; and nothing
# extra when neither moved. Every row below waits on the world (an `ext:` read), so the ready
# set and the decision stay QUIET across the whole case: no status or ready-set move can print
# the line, and what prints it here is the new reading alone.
# HOISTED to tests/session-poker.prelude.sh: SRP_ROW1, SRP_ROW2 — Section 67 plants the same two rows.
sRP_plan() { sp_plan_at_step "$RRP" "$1" "$SRP_ROW1" "${@:2}" >/dev/null; }
RRP="$(make_repo s55-recon-plan)"
poke "$RRP" arm
sRP_plan 3
poke_pressure "$RRP" 8192 1.0 tick
expect_contains "RPa precondition: the first tick at current: 3 read the plan (the held row is named)" "poker: HELD T1 ext:ci-rp" "$OUT"
expect_absent "RPa2 …and asks no reconcile: nothing has moved yet" "poker: RECONCILE" "$OUT"
expect_contains "RPa3 precondition: the digest records the plan's current: and its row count" \
  "plan_current=3 plan_rows=1" \
  "$(/usr/bin/grep -E '^plan_(current|rows)=' "$(digest_of "$RRP")" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
sRP_plan 4
poke_pressure "$RRP" 8192 1.0 tick
expect_contains "RPb AC-11.3 current: moves from 3 to 4: the tick prints the RECONCILE line" "poker: RECONCILE — " "$OUT"
expect_contains "RPb2 …saying the plan moved into Step 4 and naming the rebuild (wave-27 T37)" \
  "poker: RECONCILE — the plan moved from approval into Step 4 since the last tick: TaskList, and rebuild the task list in execution order (delete every pending entry and recreate them)" "$OUT"
expect_eq "RPb3 …once" "1" "$(count_lines_matching 'poker: RECONCILE' "$OUT")"
expect_contains "RPb4 …and the digest owes the duty" "duty=owed" "$(cat "$(digest_of "$RRP")" 2>/dev/null)"
poke_pressure "$RRP" 8192 1.0 tick
expect_absent "RPc the next tick over the same plan prints no RECONCILE" "poker: RECONCILE" "$OUT"
expect_contains "RPc2 …and says so: unchanged" "unchanged since" "$OUT"
sRP_plan 4 "$SRP_ROW2"
poke_pressure "$RRP" 8192 1.0 tick
expect_contains "RPd a row added to the table: the tick prints the RECONCILE line" "poker: RECONCILE — " "$OUT"
poke_pressure "$RRP" 8192 1.0 tick
expect_absent "RPe …and the tick after it prints none" "poker: RECONCILE" "$OUT"
sRP_plan 5 "$SRP_ROW2"
poke_pressure "$RRP" 8192 1.0 tick
expect_absent "RPf current: moving 4 to 5 is not a reconcile" "poker: RECONCILE" "$OUT"
expect_eq "RPf2 …and the digest keeps what it read (current 5, two rows)" "plan_current=5 plan_rows=2" \
  "$(/usr/bin/grep -E '^plan_(current|rows)=' "$(digest_of "$RRP")" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"


# ============================================================
section "Section 56 §WAIT §LOST §ADOPT-RUN §RUNS: the run's verbs (wave-30 T12; REQ-3 AC-3.2, AC-3.3, AC-3.5, AC-3.8; REQ-4 AC-4.6; D6, D7d)"
# ============================================================
#
# A RUN IS AN OBJECT (D6): `booked.sh --detach` starts it in a session of its own and records it on
# the roster row its --agent names (wave-30 T8). These rows start REAL detached runs through the
# shipped shim, kill the caller's group as a /clear would, and read them back through the verbs:
# `wait` (re-entrant: a second wait finds the same run and never starts it again), `stop-run`, the
# word LOST for a run whose pid died with no end (never a timeout), `adopt`'s run line, the tick's
# RUNNING line with the run's progress, and `regression-runs`, counted from the records and written
# into the bound plan's header by the tick.
#
# FIXTURE FIDELITY: the runs are the real shim under the real perl setsid, asking this suite's
# sandboxed gate; the rows are written by mkrow and the run records by the shim itself. SYNTHESIZED:
# the commands (a counter, a progress line, a hold on a go-file), and in §RUNS the run records of
# finished runs, written as the shim writes them (run_log, run_rc, run_cmd with each `|` a space,
# booked.sh `booked_one_line`), and one fake shim
# (§STOP-KILL) that ignores TERM, which no real shim does, to drive the KILL arm.
export BIONIC_RUN_POLL=0.1 BIONIC_GATE_POLL=0.1
S56_BOOKED="$BIONIC_SCRIPTS_DIR/payload/scripts/booked.sh"
s56_until() {  # <seconds> <test...> — polls every 0.1 s; rc 1 when time runs out
  local n=$(( $1 * 10 )) i=0; shift
  while ! "$@" 2>/dev/null; do i=$((i + 1)); [ "$i" -lt "$n" ] || return 1; sleep 0.1; done
}
S56_PID=""; S56_LOG=""; S56_RUN=""; S56_N=0
s56_start() {  # <repo> <session> <agent> <suites> <command> — a real detached run; its caller's group then SIGKILLed
  local out pg
  S56_N=$((S56_N + 1)); out="$TMPROOT/s56-start-$S56_N.out"
  set -m
  ( cd "$1" && env CLAUDE_CODE_SESSION_ID="$2" bash "$S56_BOOKED" --detach --agent "$3" --suites "$4" -- "$5"; sleep 60 ) > "$out" 2>&1 &
  pg=$!
  set +m
  s56_until 15 grep -q '^booked: started ' "$out"
  S56_PID="$(sed -n 's/^booked: started pid=\([0-9]*\) .*/\1/p' "$out" | head -n 1)"
  S56_LOG="$(sed -n 's/^booked: started .* log=\([^ ]*\) .*/\1/p' "$out" | head -n 1)"
  S56_RUN="$(sed -n 's/^booked: started .* run=\([^ ]*\)$/\1/p' "$out" | head -n 1)"
  kill -KILL -- "-$pg" 2>/dev/null; wait "$pg" 2>/dev/null
}
s56_hold() {  # <go-file> -> shell text: wait for it, at most 60 s
  printf "i=0; while [ ! -f '%s' ] && [ \$i -lt 1200 ]; do i=\$((i+1)); sleep 0.05; done" "$1"
}
s56_prog() {  # <section> -> shell text: one section line on the run's progress file
  printf "printf '%%s\\\\t%%s\\\\t§%%s\\\\n' 2026-10-08T00:00:01Z wt.test.sh %s >> \"\$BIONIC_TEST_PROGRESS\"" "$1"
}
s56_poker() {  # <repo> <out file> <args...> — the poker in the background; sets S56_BG
  local repo="$1" out="$2"; shift 2
  ( cd "$repo" && exec env CLAUDE_CODE_SESSION_ID="$SID" bash "$POKER" "$@" ) > "$out" 2>&1 &
  S56_BG=$!
}

# ---------- §WAIT: re-entrant, one run, polls in short intervals (AC-3.2, AC-3.8) ----------
R56="$(make_repo s56-runs)"; new_roster "$R56"
add_row "$R56" name=w-run status=identified agent_id=a56run00000000000 duration="4 hours" \
  launched_at="$(iso_ago 60)" deliverable="$R56/never.md"
S56_CMD="echo run >> '$R56/count'; $(s56_hold "$R56/go1"); $(s56_prog sec-one); $(s56_hold "$R56/go2"); exit 3"
s56_start "$R56" "$SID" w-run wt.test.sh "$S56_CMD"
expect_nonempty "56a precondition: the detached run started under w-run (the shim printed its pid)" "$S56_PID"
s56_until 10 grep -qF "|run_pid=$S56_PID|" "$(roster_of "$R56")"
expect_contains "56a2 precondition: …and recorded it on w-run's row" "|run_pid=$S56_PID|" \
  "$(grep -F '|name=w-run|' "$(roster_of "$R56")" | tail -n 1)|"
s56_poker "$R56" "$TMPROOT/s56-w1.out" wait w-run; S56_W1=$S56_BG
s56_until 10 grep -q '^poker: RUNNING w-run ' "$TMPROOT/s56-w1.out"
kill -KILL "$S56_W1" 2>/dev/null; wait "$S56_W1" 2>/dev/null
expect_contains "56b AC-3.2 a first wait finds the run by its row's name: RUNNING, its id and pid" \
  "poker: RUNNING w-run run=$S56_RUN pid=$S56_PID elapsed=" "$(cat "$TMPROOT/s56-w1.out" 2>/dev/null)"
s56_poker "$R56" "$TMPROOT/s56-w2.out" wait w-run; S56_W2=$S56_BG
s56_until 10 grep -q '^poker: RUNNING w-run ' "$TMPROOT/s56-w2.out"
touch "$R56/go1"
s56_until 10 grep -q 'sec-one' "$TMPROOT/s56-w2.out"
expect_contains "56c AC-3.8 a second wait, the first killed, prints the run's progress line while it runs" \
  "progress: 2026-10-08T00:00:01Z wt.test.sh §sec-one" "$(cat "$TMPROOT/s56-w2.out" 2>/dev/null)"
expect_contains "56d AC-3.2 …and found the same run: the same pid" "run=$S56_RUN pid=$S56_PID " \
  "$(cat "$TMPROOT/s56-w2.out" 2>/dev/null)"
touch "$R56/go2"
wait "$S56_W2"; S56_W2_RC=$?
expect_eq "56e the second wait exits with the run's own code" "3" "$S56_W2_RC"
expect_contains "56f …and says FINISHED, with the code and the log" "poker: FINISHED w-run run=$S56_RUN rc=3 log=$S56_LOG" \
  "$(cat "$TMPROOT/s56-w2.out" 2>/dev/null)"
expect_eq "56g AC-3.2 two waits, one run: the command ran once" "1" "$(wc -l < "$R56/count" | tr -d ' ')"
expect_true "56h the run's log is there" test -f "$S56_LOG"
expect_false "56h2 …and no second attempt was claimed beside it" test -e "${S56_LOG%.log}-2.log"
expect_true "56i AC-3.2 the wait polled: two RUNNING lines before the end (its start, and the progress that moved)" \
  test "$(grep -c '^poker: RUNNING w-run ' "$TMPROOT/s56-w2.out" 2>/dev/null)" -ge 2
poke "$R56" wait w-run
expect_eq "56j a wait on an ended run answers at once from its record, with its code" "3|poker: FINISHED w-run run=$S56_RUN rc=3 log=$S56_LOG" "$RC|$OUT"
poke "$R56" wait "$S56_RUN"
expect_eq "56j2 …and by its run id too (the main thread's runs have no row)" "3" "$RC"
poke "$R56" wait w-nobody
expect_eq "56j3 a name with no run is a usage error, exit 2, naming it" "2|yes" \
  "$RC|$(printf '%s' "$OUT" | grep -q 'no run named w-nobody' && echo yes || echo no)"

# ---------- §LOST: a dead pid with no end is LOST, never a timeout (AC-3.3) ----------
add_row "$R56" name=w-lost status=identified agent_id=a56lost0000000000 duration="4 hours" \
  launched_at="$(iso_ago 60)" deliverable="$R56/never.md"
s56_start "$R56" "$SID" w-lost lost.test.sh "$(s56_hold "$R56/go3")"
S56_LOST_PID="$S56_PID"; S56_LOST_RUN="$S56_RUN"
poke "$R56" wait w-lost --for 1
expect_eq "56k wait --for bounds the call: 75 while the run goes on" "75" "$RC"
expect_contains "56k2 …and says to wait again" "still RUNNING after 1s — the run goes on; wait again: " "$OUT"
kill -KILL "$S56_LOST_PID" 2>/dev/null
s56_until 5 bash -c "! kill -0 $S56_LOST_PID"
poke "$R56" wait w-lost
expect_eq "56l AC-3.3 a wait on a run whose pid died with no end exits 70" "70" "$RC"
expect_regex "56m …and says LOST, with the time its log was last written" \
  "^poker: LOST w-lost run=$S56_LOST_RUN last-written=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z " "$OUT"
expect_eq "56n AC-3.3 …and never the word timeout (beside 56m on the same output)" "0" \
  "$(printf '%s\n' "$OUT" | grep -ci 'timeout')"
touch "$R56/go3"

# ---------- the tick's RUNNING line, and stop-run (AC-3.8; D6 "stop-run reaches the group") ----------
add_row "$R56" name=w-stop status=identified agent_id=a56stop0000000000 duration="4 hours" \
  launched_at="$(iso_ago 60)" deliverable="$R56/never.md"
s56_start "$R56" "$SID" w-stop stop.test.sh "$(s56_prog sec-stop); $(s56_hold "$R56/never-go")"
S56_STOP_PID="$S56_PID"; S56_STOP_RUN="$S56_RUN"
s56_until 10 grep -q 'sec-stop' "$S56_LOG.progress.tsv"
poke "$R56" tick
expect_contains "56o AC-3.8 the tick's RUNNING line names the live run, its pid and its progress line" \
  "poker: RUNNING w-stop run=$S56_STOP_RUN pid=$S56_STOP_PID elapsed=" "$OUT"
expect_contains "56o2 …ending in the run's last progress line" "progress: 2026-10-08T00:00:01Z wt.test.sh §sec-stop" \
  "$(printf '%s\n' "$OUT" | grep '^poker: RUNNING w-stop ')"
poke "$R56" stop-run w-stop --report-only
expect_contains "56p stop-run --report-only says what it would do" \
  "poker: stop-run w-stop run=$S56_STOP_RUN pid=$S56_STOP_PID — RUNNING; would TERM its process group" "$OUT"
expect_true "56p2 …and sends nothing: the run is alive" kill -0 "$S56_STOP_PID"
poke "$R56" stop-run w-stop
expect_contains "56q stop-run stops the run through its own trap (TERM), which writes its end" \
  "poker: stop-run w-stop run=$S56_STOP_RUN pid=$S56_STOP_PID — stopped (TERM); the run wrote its own end, rc=143" "$OUT"
expect_true "56q2 …and the run is gone" s56_until 5 bash -c "! kill -0 $S56_STOP_PID"
expect_contains "56q3 …its row records the end" "|run_rc=143|" "$(grep -F '|name=w-stop|' "$(roster_of "$R56")" | tail -n 1)|"
poke "$R56" wait w-stop
expect_eq "56q4 …so a wait reads it FINISHED rc=143, a stop, never LOST" "143" "$RC"

# §STOP-KILL: a shim that ignores TERM is KILLed, and the end it never wrote is recorded as 137.
mkdir -p "$TMPROOT/s56-fake"
printf '#!/bin/bash\ntrap "" TERM\nwhile :; do sleep 0.2; done\n' > "$TMPROOT/s56-fake/booked.sh"
S56_KLOG="$R56/.bionic/tmp/runs/w-kill-k.test.sh.log"; : > "$S56_KLOG"
perl -MPOSIX -e 'my $l = shift; my $p = fork; exit 0 if $p; POSIX::setsid(); open(my $f, ">", "$l.pid"); print $f "$$\n"; close $f; open(STDIN, "<", "/dev/null"); open(STDOUT, ">>", $l); open(STDERR, ">&", \*STDOUT); exec @ARGV' \
  "$S56_KLOG" bash "$TMPROOT/s56-fake/booked.sh" --run-log "$S56_KLOG"
s56_until 5 test -s "$S56_KLOG.pid"
S56_KPID="$(cat "$S56_KLOG.pid" 2>/dev/null)"
printf '%s|run_pid=%s|run_log=%s|run_started_at=%s\n' \
  "$(mkrow name=w-kill status=identified agent_id=a56kill0000000000 duration='4 hours' launched_at="$(iso_ago 60)" deliverable="$R56/never.md")" \
  "$S56_KPID" "$S56_KLOG" "$(iso_ago 5)" >> "$(roster_of "$R56")"
poke "$R56" stop-run w-kill
expect_contains "56r stop-run KILLs a run that outlives its TERM, and records rc=137 for the end it never wrote" \
  "poker: stop-run w-kill run=w-kill-k.test.sh pid=$S56_KPID — stopped (TERM, then KILL); it wrote no end, so rc=137 was recorded for it" "$OUT"
expect_eq "56r2 …the log ends rc=137 and <log>.rc holds it" "rc=137|137" "$(tail -n 1 "$S56_KLOG")|$(cat "$S56_KLOG.rc" 2>/dev/null)"
expect_contains "56r3 …and the row records it through roster_mark_run" "|run_rc=137|" \
  "$(grep -F '|name=w-kill|' "$(roster_of "$R56")" | tail -n 1)|"
expect_false "56r4 …and the process is gone" kill -0 "$S56_KPID"

# ---------- §ADOPT-RUN: adopt prints each adopted row's run state (AC-3.5) ----------
PRED_56="d6d6d6d6-1111-4bbb-8ccc-000000000056"
S56_CFG="$(fake_config_dir s56-adopt)"
R56A="$(make_repo s56-adopt)"; new_roster "$R56A"
add_row_to "$R56A" "$PRED_56" name=p-run status=identified agent_id=ap56run0000000000 \
  subagent_type=bionic:implementor deliverable="$R56A/never.md" duration="4 hours" cadence="10 minutes" \
  launched_at="$(iso_ago 60)"
s56_start "$R56A" "$PRED_56" p-run prun.test.sh "$(s56_hold "$R56A/go")"
S56_A_PID="$S56_PID"; S56_A_RUN="$S56_RUN"
S56_A_RF="$(roster_of "$R56A" "$PRED_56")"
printf '%s|run_log=%s/.bionic/tmp/runs/p-fin-f.test.sh.log|run_rc=0|run_ended_at=%s\n' \
  "$(mkrow session="$PRED_56" name=p-fin status=identified agent_id=ap56fin0000000000 subagent_type=bionic:implementor deliverable="$R56A/never.md" duration='4 hours' cadence='10 minutes' launched_at="$(iso_ago 60)")" \
  "$R56A" "$(iso_ago 10)" >> "$S56_A_RF"
S56_DEAD_PID="$(sh -c 'echo $$')"
: > "$R56A/.bionic/tmp/runs/p-lost-l.test.sh.log"
printf '%s|run_pid=%s|run_log=%s/.bionic/tmp/runs/p-lost-l.test.sh.log|run_started_at=%s\n' \
  "$(mkrow session="$PRED_56" name=p-lost status=identified agent_id=ap56lost000000000 subagent_type=bionic:implementor deliverable="$R56A/never.md" duration='4 hours' cadence='10 minutes' launched_at="$(iso_ago 60)")" \
  "$S56_DEAD_PID" "$R56A" "$(iso_ago 30)" >> "$S56_A_RF"
add_row_to "$R56A" "$PRED_56" name=p-none status=identified agent_id=ap56none000000000 \
  subagent_type=bionic:implementor deliverable="$R56A/never.md" duration="4 hours" cadence="10 minutes" \
  launched_at="$(iso_ago 60)"
CLAUDE_CONFIG_DIR="$S56_CFG" poke "$R56A" adopt --report-only
s56_block() { printf '%s\n' "$OUT" | awk -v h="poker: $1 (" 'index($0, h) == 1 { on = 1 } on && $0 == "" { exit } on'; }
expect_regex "56s AC-3.5 adopt prints a RUNNING row's run: its pid and its age" \
  "^  run         : RUNNING pid=$S56_A_PID elapsed=[0-9]+s run=$S56_A_RUN\$" "$(s56_block p-run | grep '^  run ')"
expect_eq "56t AC-3.5 …a FINISHED row's, with its code" "  run         : FINISHED rc=0 run=p-fin-f.test.sh" \
  "$(s56_block p-fin | grep '^  run ')"
expect_regex "56u AC-3.5 …a LOST row's, with the time its log was last written" \
  '^  run         : LOST last-written=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z run=p-lost-l\.test\.sh$' \
  "$(s56_block p-lost | grep '^  run ')"
expect_contains "56v …a row with no run record is still printed (its launch line)" "  launched    : " "$(s56_block p-none)"
expect_eq "56v2 …and prints no run line (beside 56s–56u on the same reader)" "" "$(s56_block p-none | grep '^  run ')"
expect_eq "56w AC-3.3 adopt never prints the word timeout" "0" "$(printf '%s\n' "$OUT" | grep -ci 'timeout')"
touch "$R56A/go"

# ---------- §RUNS: regression-runs, counted from the run records (AC-4.6; Δ6d) ----------
R56R="$(make_repo s56-regruns)"; new_roster "$R56R"
S56_RR_PLAN="$(plan_at "$R56R" epic-99-fixture/wave-56-runs.plan.md "$(printf -- '---\nregression-runs: 5\n---\n'; plan_body 4)")"
S56_RD="$R56R/.bionic/tmp/runs"
s56_rec() {  # <roster file> <name> <run fields>... — a roster row with a run record, as the shim leaves it
  local f="$1" n="$2" row kv
  shift 2
  row="$(mkrow name="$n" status=identified agent_id="a56$n" duration='4 hours' launched_at="$(iso_ago 600)" deliverable="$R56R/never.md")"
  for kv in "$@"; do row="$row|$kv"; done
  printf '%s\n' "$row" >> "$f"
}
S56_OWN="$(roster_of "$R56R")"
s56_rec "$S56_OWN" w-a "run_log=$S56_RD/w-a-run.sh.log" "run_cmd=tests/run.sh" "run_rc=0"
s56_rec "$S56_OWN" w-a "run_log=$S56_RD/w-a-run.sh.log" "run_cmd=tests/run.sh" "run_rc=0"
s56_rec "$S56_OWN" w-b "run_log=$S56_RD/w-b-x.test.sh.log" "run_cmd=tests/run.sh --only x.test.sh" "run_rc=0"
s56_rec "$S56_OWN" w-c "run_log=$S56_RD/w-c-run.sh.log" "run_cmd=tests/run.sh" "run_pid=1"
S56_PRED_RF="$(roster_of "$R56R" "$PRED_56")"; roster_header > "$S56_PRED_RF"
s56_rec "$S56_PRED_RF" w-d "run_log=$S56_RD/w-d-cmd.log" "run_cmd=cd /x    exit 1; bash tests/run.sh 2>&1   tee x.log" "run_rc=1"
s56_rec "$S56_PRED_RF" w-e "run_log=$S56_RD/w-e-run.sh-2.log" "run_cmd=bash tests/run.sh --dry-run" "run_rc=0"
poke "$R56R" regression-runs
expect_eq "56x AC-4.6 regression-runs counts the ended full-runner runs on every roster, each once" \
  "0|poker: regression-runs=2" "$RC|$OUT"
poke "$R56R" tick
expect_contains "56y AC-4.6 the tick prints the count" "poker: regression-runs=2" "$OUT"
expect_eq "56z AC-4.6 …and the hand-typed header value did not survive the tick: the header reads the count" \
  "2" "$(sed -n 's/^regression-runs: *//p' "$S56_RR_PLAN" | head -n 1)"
expect_contains "56z2 …through the verb's transaction, which says what it wrote" \
  "poker: regression-runs — the plan header read 5 and the run records count 2: 2 written to " "$OUT"
s56_rec "$S56_OWN" w-f "run_log=$S56_RD/w-f-run.sh.log" "run_cmd=tests/run.sh" "run_rc=0"
poke "$R56R" tick
expect_contains "56z3 a new full run is news: the next tick prints in full, with the new count" "poker: regression-runs=3" "$OUT"
expect_eq "56z4 …and the header follows it" "3" "$(sed -n 's/^regression-runs: *//p' "$S56_RR_PLAN" | head -n 1)"
poke "$R56R" tick
expect_regex "56z5 nothing new: the tick is the one unchanged line (wave-24 AC-4.9 kept)" \
  "^poker: unchanged since [0-9TZ:-]+ — decision=[A-Z]+\$" "$OUT"


finish
