#!/bin/bash
# Tests for hooks/stop.sh — ONE PROCESS AT TURN END (epic-23 wave-11-lean-spine,
# REQ-1f (iv); spec Design §2 D4; ADR-004; T12 ruling R7).
#
# WHAT THIS FILE IS FOR, AND WHAT IT IS NOT. The four verdicts keep their own
# suites, re-pointed at this process and unchanged in count:
#
#   tests/context-spend.test.sh        30 assertions   stop_context_spend
#   tests/landing-gate.test.sh        185 assertions   stop_landing_gate
#   tests/patrol-duties-gate.test.sh   94 assertions   stop_patrol_duties
#   tests/patrol-revive.test.sh        65 assertions   stop_patrol_revive
#
# and tests/fold.test.sh drives the composition MECHANISM with stub functions. What
# is left over — and what this file owns — is the composition of the REAL four in
# the real process: what a turn end looks like when more than one of them has
# something to say, which no per-verdict suite can see and no stub suite can prove.
#
# THE CASES:
#   §1  two verdicts block on one Stop -> BOTH reasons, blocks before advisories
#   §2  one block and one advisory     -> the block first, the advisory kept
#   §4  a SubagentStop payload         -> only the landing arm can speak
#
# §1 IS THE ONE THAT GOES RED AGAINST FIRST-BLOCK-WINS, which is the alternative
# ADR-004 rejects by name, and against the pre-merge arrangement too: before the
# merge these two verdicts were two processes producing two unreconciled outputs on
# two different wires, and an operator saw whichever the platform surfaced.
#
# EVERY FIXTURE IS A REAL TREE with a real roster, a real plan and a real stamp —
# no stubs — because the claim is about the four functions, not about the fold.
# Nothing sleeps: staleness is a backdated mtime, the way
# tests/patrol-revive.test.sh manufactures it.
#
# Usage: bash tests/stop.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
# THE ONE ROW BUILDER (cross-gate §S17): no suite hand-writes a roster row.
. "$(dirname "$0")/lib/roster-row.sh"
# The one bound-marker builder (wave-23-fixit-1810 T1): mkfix binds its session, and §UB
# plants the unbound one beside it.
. "$(dirname "$0")/lib/bound-marker.sh"

HOOK="${BIONIC_STOP_UNDER_TEST:-${BIONIC_HOOKS_DIR}/stop.sh}"

command -v jq >/dev/null 2>&1 || { echo "stop: jq absent — suite cannot run"; exit 1; }

# NOT VACUOUS. Several assertions below read "silent, exit 0", which is what a
# MISSING hook also produces once the shell's own 127 is discarded.
[ -f "$HOOK" ] || { echo "stop: no hook at $HOOK — suite refuses to run"; exit 1; }
bash -n "$HOOK" || { echo "stop: $HOOK does not parse — suite refuses to run"; exit 1; }

SID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
AID="a-worker-0123456789abcdef"

# THE GATE IS FIXTURE DATA (wave-28 T13; D14). The fill duty sizes its width at the gate, which
# reads the machine through the readers' pins and its store at BIONIC_GATE_DIR: 8 cores, 30%
# used, a load of 1.0 over both windows, and one run on record taking 0.1 core — room for every
# row a fixture here makes ready, so no width below is this host's load.
STOP_GATE="$(cd "$(mktemp -d)" && pwd -P)/gate"
mkdir -p "$STOP_GATE/requests" "$STOP_GATE/cost"
printf '5:0.1:30:1000\n' > "$STOP_GATE/cost/fixture.test.sh"
export BIONIC_GATE_DIR="$STOP_GATE"
export BIONIC_PROBE_CORES=8 BIONIC_PROBE_USED_PCT=30 BIONIC_PROBE_BUSY_CORES=1.0 BIONIC_PROBE_BUSY_CORES_5M=1.0

# ---------- fixtures ----------

# RESOLVED (`pwd -P`): mktemp answers under /var, which is a symlink to /private/var
# on this platform, and `project_root` answers with the physical path — so an
# unresolved fixture path would not match the paths the verdicts print.
mkfix() {
  local d
  d=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$d/.bionic/tmp" "$d/.bionic/docs/plans"
  printf -- '---\ncanonical_sdlc_version: 14\n---\n\n## SDLC State\n\ncurrent: 4\n\n- Step 4\n' \
    > "$d/.bionic/docs/plans/wave-01.plan.md"
  # BOUND (wave-23-fixit-1810, REQ-1, D1): an empty marker beside an open plan is the
  # unbound state, whose fallback is announced and never acted on — the Patrol verdict
  # would return before reading the stamp §1 needs. §2 and §UB drive the unbound state.
  bound_marker "$d" "$SID" "$d/.bionic/docs/plans/wave-01.plan.md"
  printf '%s' "$d"
}

# A ROSTER ROW WITH AN UNDELIVERED ARTIFACT — the landing sweep's block. Built through
# tests/lib/roster-row.sh, the fleet's one row writer, so a schema change that the sweep
# stopped producing cannot pass here (cross-gate §S17).
unmet_row() {  # <project>
  {
    roster_header
    roster_row_fixture status=identified session="$SID" name=w1-row agent_id="$AID" \
      deliverable=.bionic/docs/record/never.md launched_at=2026-09-01T00:00:00Z \
      tool_use_id=toolu_X
  } > "$1/.bionic/tmp/roster-$SID.state"
}

# A PATROL STAMP PAST ONE FIRE WINDOW — patrol-revive's block. The interval is
# pinned tiny through the project's own knob and the age is a backdated mtime; the idle gap
# the verdict needs beside it comes from `usage_tx`'s dated transcript above (REQ-1, T1).
stale_stamp() {  # <project>
  printf 'poker-interval: 1s\n' > "$1/.bionic/config.yaml"
  printf 'patrol-stamp/v1|at=2026-08-27T00:00:00Z|session=%s|verb=arm\n' "$SID" \
    > "$1/.bionic/tmp/patrol-$SID.state"
  touch -t "$(date -v-600S +%Y%m%d%H%M.%S 2>/dev/null || date -d '-600 seconds' +%Y%m%d%H%M.%S)" \
    "$1/.bionic/tmp/patrol-$SID.state"
}

# A TRANSCRIPT whose last assistant entry carries usage — what context-spend reads.
#
# AND WHOSE RECORDS ARE DATED, WITH ONE IDLE GAP IN THEM (amended at epic-23 wave-15 REQ-1,
# T1). The Patrol verdict is an idle-time predicate now: `stop_patrol_revive` reads this
# same `transcript_path` for the span between the last activity record and the next
# turn-starting user record, and a stamp past the fire window is a DEATH only when such a
# gap has passed with no tick in it. This fixture used to be one undated assistant record,
# which the predicate reads — correctly — as "idle time cannot be measured here", so §1 and
# §4d would have been asserting the advisory rather than the block they name. Every record
# the CLI writes carries `.timestamp` (spec assumption 1, verified live 2026-09-16), so the
# dated shape is also the faithful one. The usage entry stays LAST, which is what
# context-spend reads.
usage_tx() {  # <file>
  local t_old t_now
  t_old="$(date -u -v-10000S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
           || date -u -d '-10000 seconds' +%Y-%m-%dT%H:%M:%SZ)"
  t_now="$(date -u -v-1S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
           || date -u -d '-1 seconds' +%Y-%m-%dT%H:%M:%SZ)"
  { jq -nc --arg t "$t_old" '{type:"assistant",timestamp:$t,message:{role:"assistant",content:[{type:"text",text:"working"}]}}'
    jq -nc --arg t "$t_now" '{type:"user",timestamp:$t,message:{role:"user",content:"carry on"}}'
    jq -nc --arg t "$t_now" '{type:"assistant",timestamp:$t,message:{model:"claude-opus-5",usage:{input_tokens:1000,cache_creation_input_tokens:0,cache_read_input_tokens:0}}}'
  } > "$1"
}

# ---------- driving ----------

STOP_OUT=""
STOP_ERR=""
STOP_RC=0
STOP_ERRFILE="$(mktemp)"

# THE ENVIRONMENT AGREES WITH THE PAYLOAD (A-probe-2), and CLAUDE_PROJECT_DIR is
# blanked because it is rung 1 of the one cwd ladder and the runner's own value
# would outrank the fixture's `.cwd`. HOME is the fixture's: context-spend's audit
# stream is $HOME-rooted by incident 0001 and must not reach the real ~/.claude.
fire() {  # <project> <event> <stop_hook_active> [extra JSON object]
  local d="$1" ev="${2:-Stop}" sha="${3:-false}" extra="${4:-}"
  [ -n "$extra" ] || extra='{}' 
  local home t payload
  home=$(cd "$(mktemp -d)" && pwd -P)
  t=$(mktemp); usage_tx "$t"
  payload=$(jq -nc --arg c "$d" --arg t "$t" --arg s "$SID" --arg e "$ev" \
                   --argjson a "$sha" --argjson x "$extra" \
    '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:$e,stop_hook_active:$a,background_tasks:[]} + $x')
  STOP_OUT=$(env HOME="$home" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$SID" \
    BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_SWAP_PCT=0 \
    bash "$HOOK" <<< "$payload" 2>"$STOP_ERRFILE")
  STOP_RC=$?
  STOP_ERR=$(cat "$STOP_ERRFILE" 2>/dev/null)
}

reason_of() {
  printf '%s' "$STOP_OUT" | jq -r '.reason // ""' 2>/dev/null
}

# offset_in_reason <needle> — where the needle sits in the composed reason, or -1.
# ORDER IS ASSERTED BY POSITION, which is the whole content of "blocks before
# advisories" and of "in manifest order".
offset_in_reason() {
  local hay pre
  hay=$(reason_of)
  pre="${hay%%$1*}"
  if [ "$pre" = "$hay" ]; then printf '%s' "-1"; else printf '%s' "${#pre}"; fi
}

refusal_lines() {
  printf '%s\n' "$STOP_ERR" | /usr/bin/grep -c '^bionic: ' || true
}

require_helpers roster_header roster_row_fixture mkfix unmet_row stale_stamp usage_tx fire reason_of \
                offset_in_reason refusal_lines

# ─────────────────────────────────────────────────────────────────────────────
section "1: TWO verdicts block on one Stop — both reasons, blocks first"

# THE CASE THE MERGE EXISTS FOR. An undelivered landing contract AND a dead Patrol,
# on one turn end. Before the merge these were two processes: landing-gate exited 2
# with its line on stderr, patrol-revive exited 0 with a JSON block on stdout, and
# nothing said how the two combine. One verdict now.
D=$(mkfix); unmet_row "$D"; stale_stamp "$D"
fire "$D"

expect_nonempty "1a: the turn end is refused — something was rendered" "$STOP_OUT$STOP_ERR"
expect_contains "1b: the LANDING reason is in the composed verdict" \
  "LANDING CONTRACT UNMET" "$(reason_of)"
expect_true "1d: …and in the manifest's order, landing before patrol, by offset" \
  test "$(offset_in_reason 'LANDING CONTRACT UNMET')" -lt \
       "$(offset_in_reason 'The Patrol died mid-run')"
expect_eq "1e: the user stream carries exactly ONE rendered refusal, not two" \
  "1" "$(refusal_lines)"

# A BOUND SESSION HEARS NO UNBOUND ADVISORY (wave-23-fixit-1810, REQ-1, D1). This session
# is bound to the run it is in, which is what lets the Patrol verdict reach the stamp at all;
# §2 drives the unbound session, where the advisory survives the block and prints last.
expect_absent "1g: a bound session's composed verdict carries no unbound advisory" \
  "session unbound" "$STOP_ERR"

# ─────────────────────────────────────────────────────────────────────────────
section "2: one block and one advisory"

# UNBOUND (wave-23-fixit-1810, REQ-1, D1): the landing sweep reads no plan, so it blocks as it
# always did, and lib/run.sh's one advisory is the non-blocking verdict that rides beside it.
D=$(mkfix); unmet_row "$D"; unbound_marker "$D" "$SID" empty
fire "$D"
expect_status "2a: a lone landing block exits 2, the channel that verdict has always used" \
  "2" "$STOP_RC"
expect_eq "2c: exactly one rendered refusal" "1" "$(refusal_lines)"
expect_true "2e: …after the refusal" \
  test "$(awk '/^bionic: /{print NR; exit}' <<<"$STOP_ERR")" -lt \
       "$(awk '/^run resolved by newest-plan fallback/{print NR; exit}' <<<"$STOP_ERR")"

# ─────────────────────────────────────────────────────────────────────────────
section "4: SubagentStop — only the landing arm has anything to say there"

# THE OTHER THREE READ THE EVENT AND RETURN. A subagent has no Patrol duties and
# arms no Patrol; the instrument was registered on Stop alone before the merge and
# keeps that scope through its own guard. So a SubagentStop payload over a fixture
# that would make all four speak on a Stop produces the LANDING answer and nothing
# else — asserted from both sides, or it would pass on a hook that did nothing.
D=$(mkfix); unmet_row "$D"; stale_stamp "$D"
fire "$D" SubagentStop false "$(jq -nc --arg a "$AID" '{agent_id:$a,agent_type:"worker"}')"
expect_absent "4a: the PATROL verdict does not speak on SubagentStop" \
  "The Patrol died mid-run" "$STOP_OUT$STOP_ERR"
# THE STOP-ONLY ARMS' ADVISORY, on an UNBOUND copy of the fixture: the instrument, the duties
# gate and the revive arm are the ones that announce the unbound state, and none of them runs
# on SubagentStop — while the same unbound fixture on a Stop does announce it, so the absence
# is the event's doing (wave-23-fixit-1810: the three used to carry their own prefixes).
D3=$(mkfix); unmet_row "$D3"; unbound_marker "$D3" "$SID" empty
fire "$D3" SubagentStop false "$(jq -nc --arg a "$AID" '{agent_id:$a,agent_type:"worker"}')"
expect_absent "4b: nor does an unbound session's advisory, on SubagentStop" \
  "session unbound" "$STOP_ERR"
fire "$D3"
expect_contains "4c: …which the SAME unbound fixture on a Stop does print" \
  "session unbound" "$STOP_ERR"

# THE PAIRED POSITIVE: the same fixture on a Stop does make the patrol verdict
# speak, so §4a is a claim about the event and not about the fixture.
D2=$(mkfix); unmet_row "$D2"; stale_stamp "$D2"
fire "$D2"
expect_contains "4d: …while the SAME fixture on a Stop does reach the patrol verdict" \
  "The Patrol died mid-run" "$(reason_of)"

# ─────────────────────────────────────────────────────────────────────────────
section "7: the real tick's turn, judged by the wall's own ready set (REQ-10 AC-10.2; D5; wave-20 Δ7)"

# RE-POINTED AT WAVE-20 (REQ-5, Δ7; ADR-036 decision 3). The wall no longer reads the printed
# FILL at all: it computes the ready set and the pressure state itself and judges by count, so
# the seam below is now "the real tick's turn ends refused on the same gap the tick named".
# What this section still owns is that the whole channel — a real tick's output in the turn,
# the real stop process — reaches that verdict, and that a real dispatch clears it.
#
# THE SEAM THIS SECTION OWNED. `decision=` became the ranked maximum DISARM > NOTIFY > FILL >
# QUIET, with the fill ids carried in a `fill=` field on the `poker-tick/v1` line. The duty
# wall does not read that line: it reads the PRINTED `poker: FILL <ids>` out of the tick's
# tool result, cuts the ids at the first escaped newline, and refuses a turn that neither
# dispatched nor declined them. Both halves changed in one wave — one in the tick, one
# nowhere — and nothing between them would have said so.
#
# THE FILL LINE IS THE REAL TICK'S, not a literal. tests/patrol-duties-gate.test.sh drives
# every arm of the wall against synthesized text, which is right for a suite about the wall
# and cannot see a tick that stopped printing the line. So this section RUNS the poker into a
# fixture wave and feeds the wall exactly what came back — the whole channel, notes, rung
# report, decision line and all.
S7_POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"
expect_true "7a: the poker is where this section expects it" test -f "$S7_POKER"

# A wave fixture the tick will FILL: writers=2, one pending task, an empty roster. The plan
# is at `current: 4`, since a fill before Step-3 approval is withheld by design.
s7_fixture() {  # -> project dir on stdout
  local d
  d=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$d/.bionic/tmp" "$d/.bionic/docs/plans/epic-99-fixture"
  { printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
    printf 'parallel-budget: writers=2 suites=2 worktrees=8 test_jobs=8 source=user\n'
    printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: 4\napproved-by: fixture 2026-10-04T00:00Z "approved"\n\n- Step 4: in progress\n\n'
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | status |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T13 | 4 | build | fixture task | implementor | — | 15m | REQ-x | a.sh | pending |\n'
  } > "$d/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
  # BOUND to the plan the tick fills from: the stop wall charges only a bound session's own
  # ledger (wave-23-fixit-1810, REQ-1, D1).
  bound_marker "$d" "$SID" "$d/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
  printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' \
    > "$d/.bionic/tmp/roster-$SID.state"
  printf '%s' "$d"
}

S7_D="$(s7_fixture)"
S7_TICK="$( cd "$S7_D" && env CLAUDE_CODE_SESSION_ID="$SID" BIONIC_PROBE_FREE_MB=8192 \
            BIONIC_PROBE_LOAD_1M=1.0 bash "$S7_POKER" tick 2>/dev/null )"
expect_contains "7b: the fixture wave really does fill — the tick printed the line" \
  "poker: FILL T13" "$S7_TICK"
expect_contains "7c: …and the decision line carries the band, which is what D5 added" \
  "decision=FILL" "$S7_TICK"

# THE TURN: a Patrol tick prompt, the two standing duties answered, the tick's own output as
# a tool result, and NO dispatch after it. The prompt shape is the one the wall recognises
# (it carries the literal `session-poker.sh tick`), mirrored from
# tests/patrol-duties-gate.test.sh's `u_tick`.
s7_transcript() {  # <file> <tick output> [extra assistant tool_use name]
  local f="$1" out="$2"
  { jq -nc --arg t "bionic-patrol session=${SID:0:8} — Patrol tick for the fixture wave (bionic). Run: bash /abs/hooks/session-poker.sh tick — the poker decides per row." \
      '{type:"user",isMeta:true,isSidechain:false,userType:"external",timestamp:"2026-09-19T00:00:00Z",message:{role:"user",content:$t}}'
    jq -nc '{type:"assistant",isSidechain:false,timestamp:"2026-09-19T00:00:01Z",
             message:{role:"assistant",content:[{type:"tool_use",id:"toolu_la",name:"ListAgents",input:{}}]}}'
    jq -nc '{type:"assistant",isSidechain:false,timestamp:"2026-09-19T00:00:02Z",
             message:{role:"assistant",content:[{type:"tool_use",id:"toolu_tl",name:"TaskList",input:{}}]}}'
    jq -nc --arg t "$out" '{type:"user",isSidechain:false,timestamp:"2026-09-19T00:00:03Z",
             message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_x",content:$t}]}}'
    shift 2
    local n
    for n in "$@"; do
      jq -nc --arg n "$n" '{type:"assistant",isSidechain:false,timestamp:"2026-09-19T00:00:04Z",
               message:{role:"assistant",content:[{type:"tool_use",id:"toolu_ag",name:"Agent",
                        input:{name:$n,description:"task",subagent_type:"bionic:implementor",prompt:("Task " + $n)}}]}}'
    done
  } > "$f"
}

# THE DRIVER, this file's own `fire` with one thing changed: the transcript is ours, not
# `usage_tx`'s. Everything else — the blanked CLAUDE_PROJECT_DIR, the fixture HOME, the
# session key on both channels — is the same environment §1-§5 drive.
s7_fire() {  # <project> <transcript>
  local home
  home=$(cd "$(mktemp -d)" && pwd -P)
  local payload
  payload=$(jq -nc --arg c "$1" --arg t "$2" --arg s "$SID" \
    '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:"Stop",stop_hook_active:false,background_tasks:[]}')
  STOP_OUT=$(env HOME="$home" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$SID" \
    BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_SWAP_PCT=0 \
    bash "$HOOK" <<< "$payload" 2>"$STOP_ERRFILE")
  STOP_RC=$?
  STOP_ERR=$(cat "$STOP_ERRFILE" 2>/dev/null)
}

require_helpers s7_fixture s7_transcript s7_fire

S7_TX="$(mktemp)"
s7_transcript "$S7_TX" "$S7_TICK"
s7_fire "$S7_D" "$S7_TX"
expect_contains "7d: an undispatched ready row refuses the real tick's turn" \
  "ready with room:" "$(reason_of)"
expect_contains "7e: …naming the task the tick asked for" "T13" "$(reason_of)"

# THE PAIRED POSITIVE, or 7d passes against a wall that refuses every Patrol turn. A dispatch
# is two facts on disk the wall reads — the roster row the dispatch wall writes at launch, and
# the plan row ledgered `active` — and the Agent call's words are not read (Δ7).
S7_TX2="$(mktemp)"
s7_transcript "$S7_TX2" "$S7_TICK" "T13"
roster_row_fixture status=intended session="$SID" name=T13 agent_id=aT130000000000001 deliverable= \
  >> "$S7_D/.bionic/tmp/roster-$SID.state"
sed -i.bak 's/| a.sh | pending |$/| a.sh | active |/' "$S7_D/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
s7_fire "$S7_D" "$S7_TX2"
expect_absent "7f: …and a turn that dispatched the named task is not refused for the fill" \
  "ready with room:" "$(reason_of)$STOP_ERR"
expect_absent "7g: …nor for the retired printed-FILL arm" "Patrol fill unanswered" "$(reason_of)$STOP_ERR"


# ─────────────────────────────────────────────────────────────────────────────
section "8: an amended Files: is the one the landing reads (wave-20 T9, REQ-4, AC-4.1)"

# THE DEFECT (consumer report #4). A writer's brief declared its Files:, the work turned out to
# need one more file, and nothing but a re-dispatch could widen the row — so the landing's
# Files: reconciliation refused the writer's stop for exactly the file the orchestrator had
# asked for. `session-poker.sh amend <name> --files+ <p> --reason r` appends a successor row;
# the landing reads the latest row's files=, so the SAME stop, the SAME tree and the SAME diff
# pass once the row is amended. The pair below differs only by that one command.
S8_POKER="$(dirname "$HOOK")/session-poker.sh"
s8_fixture() {  # -> a git project, on main, with a delivered row whose tree touched undeclared/two.sh
  local d wt
  d=$(mkfix)
  git -C "$d" init -q 2>/dev/null
  git -C "$d" symbolic-ref HEAD refs/heads/main
  git -C "$d" config user.email t@example.invalid; git -C "$d" config user.name T
  printf '.bionic/\n.worktrees/\n' > "$d/.gitignore"; echo base > "$d/base.txt"
  git -C "$d" add .gitignore base.txt; git -C "$d" commit -qm base
  wt="$d/.worktrees/s8-writer"
  git -C "$d" worktree add -q "$wt" -b wt/s8-writer >/dev/null 2>&1
  git -C "$wt" config user.email t@example.invalid; git -C "$wt" config user.name T
  mkdir -p "$wt/declared" "$wt/undeclared"
  echo one > "$wt/declared/one.sh"; echo two > "$wt/undeclared/two.sh"
  git -C "$wt" add -A; git -C "$wt" commit -qm work
  {
    roster_header
    roster_row_fixture status=identified session="$SID" name=s8-writer agent_id="$AID" \
      deliverable=.bionic/docs/record/s8.md launched_at=2026-09-01T00:00:00Z \
      subagent_type=bionic:implementor files=declared/ suites_allowed=none suites_source=declared \
      tool_use_id=toolu_S8
  } > "$d/.bionic/tmp/roster-$SID.state"
  mkdir -p "$d/.bionic/docs/record"; echo done > "$d/.bionic/docs/record/s8.md"
  printf '%s' "$d"
}

D=$(s8_fixture)
fire "$D"
expect_status "8a: the control — a tree touching a file outside Files: refuses the stop" "2" "$STOP_RC"
expect_contains "8b: …naming the file" "undeclared/two.sh" "$STOP_ERR$(reason_of)"

# 8b2 (wave-24 T27; critic I2, AC-6.5): the printed amend is pasteable from a plugin root whose
# path holds a space. The same refusal, from a copy of the hooks and library under `my plugin/`;
# the fix line is parsed the way a pasting shell parses it, and the script must be one argument.
S8_SP="$(cd "$(mktemp -d)" && pwd -P)/my plugin"
mkdir -p "$S8_SP/hooks" "$S8_SP/scripts/lib"
cp "$(dirname "$HOOK")"/*.sh "$S8_SP/hooks/"
S8_LIB="$(dirname "$HOOK")/../payload/scripts/lib"
[ -d "$S8_LIB" ] || S8_LIB="$(dirname "$HOOK")/../scripts/lib"
cp "$S8_LIB"/*.sh "$S8_SP/scripts/lib/"
S8_HOOK_SAVED="$HOOK"; HOOK="$S8_SP/hooks/stop.sh"
D=$(s8_fixture)
fire "$D"
HOOK="$S8_HOOK_SAVED"
S8_FIXLINE="$(printf '%s\n' "$STOP_ERR$(reason_of)" | /usr/bin/grep -m1 'session-poker.sh.* amend ' | sed 's/^[[:space:]]*//')"
expect_contains "8b2 precondition: the refusal from the spaced root prints its amend line" "my plugin" "$S8_FIXLINE"
eval "set -- $S8_FIXLINE"
expect_eq "8b2: critic I2 the pasted line's script is one argument, under the spaced root" \
  "bash|$S8_SP/hooks/session-poker.sh|amend" "$1|$2|$3"
set --

D=$(s8_fixture)
S8_AMEND=$( cd "$D" && CLAUDE_CODE_SESSION_ID="$SID" bash "$S8_POKER" amend s8-writer \
  --files+ undeclared/two.sh --reason 'the fix needs two.sh' 2>&1 ); S8_RC=$?
expect_eq "8c: amend --files+ on the writer's row exits 0" "0" "$S8_RC"
fire "$D"
expect_absent "8d: AC-4.1 after the amend the same diff is inside Files: — no landing refusal" \
  "LANDING DIFF OUTSIDE" "$STOP_ERR$(reason_of)"
expect_status "8e: …and the stop is admitted" "0" "$STOP_RC"

# 8f (wave-27 T49; review pass 19 should-fix 1): a Files: path written in quotes is recorded without
# them, so the stop wall counts the file INSIDE the contract. The row's files= is built by the real
# reader (lib/brief.sh) from `Files: "lib/a.sh"`; the control carries the value the reader used to
# record, quotes and all, and refuses the same diff.
s8f_fixture() {  # <files= value> -> a project whose delivered tree touched only lib/a.sh
  local d wt
  d=$(mkfix)
  git -C "$d" init -q 2>/dev/null
  git -C "$d" symbolic-ref HEAD refs/heads/main
  git -C "$d" config user.email t@example.invalid; git -C "$d" config user.name T
  printf '.bionic/\n.worktrees/\n' > "$d/.gitignore"; echo base > "$d/base.txt"
  git -C "$d" add .gitignore base.txt; git -C "$d" commit -qm base
  wt="$d/.worktrees/s8f-writer"
  git -C "$d" worktree add -q "$wt" -b wt/s8f-writer >/dev/null 2>&1
  git -C "$wt" config user.email t@example.invalid; git -C "$wt" config user.name T
  mkdir -p "$wt/lib"; echo one > "$wt/lib/a.sh"
  git -C "$wt" add -A; git -C "$wt" commit -qm work
  {
    roster_header
    roster_row_fixture status=identified session="$SID" name=s8f-writer agent_id="$AID" \
      deliverable=.bionic/docs/record/s8f.md launched_at=2026-09-01T00:00:00Z \
      subagent_type=bionic:implementor files="$1" suites_allowed=none suites_source=declared \
      tool_use_id=toolu_S8F
  } > "$d/.bionic/tmp/roster-$SID.state"
  mkdir -p "$d/.bionic/docs/record"; echo done > "$d/.bionic/docs/record/s8f.md"
  printf '%s' "$d"
}
S8F_FILES=$(bash -c '. "$1" || exit 9; brief_field "$(lift_contract_fields "$2" bionic:implementor)" files' _ \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/brief.sh" 'Files: "lib/a.sh"')
expect_eq "8f precondition: the reader records Files: \"lib/a.sh\" as lib/a.sh" "lib/a.sh" "$S8F_FILES"
D=$(s8f_fixture '"lib/a.sh"')
fire "$D"
expect_status "8f0: the control — the quoted value the reader used to record refuses the diff" "2" "$STOP_RC"
expect_contains "8f0: …naming lib/a.sh" "lib/a.sh" "$STOP_ERR$(reason_of)"
D=$(s8f_fixture "$S8F_FILES")
fire "$D"
expect_absent "8f: the stop wall counts lib/a.sh inside a contract declared as \"lib/a.sh\"" \
  "LANDING DIFF OUTSIDE" "$STOP_ERR$(reason_of)"
expect_status "8f: …and the stop is admitted" "0" "$STOP_RC"

# ─────────────────────────────────────────────────────────────────────────────
section "9: the fill refusal's headline names only the rows the turn left out (wave-20 T11b; review R4; wave-36 T32)"

# THE DEFECT (review R4, T12 F7). The headline said "rows are ready and this turn dispatched
# none" beside a ledger line that named the turn's launches, and the refusal named the first
# ready rows in table order, the launched one included. A launched row stays in the plan's
# ready set until the orchestrator ledgers it `active` (A-T11.1), so the naming subtracts the
# turn's launches by dispatch name. Two ready rows, one launched under a wave-prefixed name
# and still `pending`: the headline says 1 of 2 and names the other.
s9_fixture() {  # -> project dir; plan with T13 and T14 pending, writers=8
  local d
  d=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$d/.bionic/tmp" "$d/.bionic/docs/plans/epic-99-fixture"
  { printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
    printf 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=user\n'
    printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: 4\napproved-by: fixture 2026-10-04T00:00Z "approved"\n\n- Step 4: in progress\n\n'
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | status | worktree |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T13 | 4 | build | first task | implementor | — | 15m | REQ-x | a.sh | pending | — |\n'
    printf '| T14 | 4 | build | second task | implementor | — | 15m | REQ-x | b.sh | pending | — |\n'
  } > "$d/.bionic/docs/plans/epic-99-fixture/wave-09-fixture.plan.md"
  bound_marker "$d" "$SID" "$d/.bionic/docs/plans/epic-99-fixture/wave-09-fixture.plan.md"
  roster_header > "$d/.bionic/tmp/roster-$SID.state"
  printf '%s' "$d"
}
s9_transcript() {  # <file> [agent name]...
  local f="$1"; shift
  { jq -nc '{type:"user",uuid:"u-s9",isSidechain:false,timestamp:"2026-09-19T00:00:00Z",message:{role:"user",content:"dispatch what is ready"}}'
    local n
    for n in "$@"; do
      jq -nc --arg n "$n" '{type:"assistant",isSidechain:false,timestamp:"2026-09-19T00:00:04Z",
               message:{role:"assistant",content:[{type:"tool_use",id:("toolu_" + $n),name:"Agent",
                        input:{name:$n,description:"task",subagent_type:"bionic:implementor",prompt:("Task " + $n)}}]}}'
    done
  } > "$f"
}
s9_headline() { printf '%s\n' "$STOP_ERR" | /usr/bin/grep -m1 '^bionic: ' || true; }
require_helpers s9_fixture s9_transcript s9_headline

# THE WIDTH IS PINNED (the idiom of tests/patrol-duties-gate.test.sh §5c): a warm, clear ring so
# `pressure_level 8` answers 8 whatever this machine is doing; unset again after the section.
S9_RING="$(mktemp)"; printf '1700000000|80|0|1.0|8\n' > "$S9_RING"
export BIONIC_PRESSURE_RING="$S9_RING" BIONIC_NOW_EPOCH=1700000000

S9_D="$(s9_fixture)"
roster_row_fixture status=intended session="$SID" name=w9-T13 agent_id=aw9T130000000001 deliverable= \
  >> "$S9_D/.bionic/tmp/roster-$SID.state"
S9_TX="$(mktemp)"; s9_transcript "$S9_TX" w9-T13
# THE TURN SETS ITS ENTRY IN PROGRESS, as the doctrine's dispatch turn does (wave-28 T38, A-T38.5).
# Since wave-31 T32 (D6) no wall counts it; the record is kept so the transcript stays that turn.
jq -nc '{type:"assistant",isSidechain:false,agentId:null,timestamp:"2026-09-19T00:00:05Z",
  message:{role:"assistant",content:[{type:"tool_use",id:"toolu_s9up",name:"TaskUpdate",input:{taskId:"1",status:"in_progress"}}]}}' >> "$S9_TX"
s7_fire "$S9_D" "$S9_TX"
expect_contains "9a: the turn that launched one of two ready rows is refused for the fill" \
  "ready with room:" "$(reason_of)"
expect_contains "9b: T11b the headline names the row left out, alone (wave-36 T32: the count went with the paragraph)" \
  "ready with room: T14 (" "$(s9_headline)"
expect_contains "9c: …and names the row that was not launched" "ready with room: T14" "$(s9_headline)"
expect_contains "9d: …as the reason does" "T14" "$(reason_of)"
# The hook's own path is taken out of the reason first: the commands the refusal prints name it,
# and a checkout whose path holds the row id (a worktree for row T13) would match there.
expect_absent "9e: T11b the row this turn launched is never named as missed, pending or not" \
  "T13" "$(s9_headline)$(reason_of | sed -E 's#[^ ]*session-poker\.sh##g')"
S9_LED="$S9_D/.bionic/docs/record/wave-09-fixture/fill-ledger.log"
expect_contains "9f: …and the ledger's ready set is still the plan's, both rows" "|ready=T13,T14|" "$(cat "$S9_LED" 2>/dev/null)"
expect_contains "9g: …with one row missed, not two" "|missed=1" "$(cat "$S9_LED" 2>/dev/null)"

# THE ZERO CASE, so 9b cannot pass on a constant: nothing launched reads 0 of 2, both named.
S9_D0="$(s9_fixture)"
S9_TX0="$(mktemp)"; s9_transcript "$S9_TX0"
s7_fire "$S9_D0" "$S9_TX0"
expect_contains "9h: a turn that launched nothing names both ready rows" "ready with room: T13 T14 (" "$(s9_headline)"

# T16 (wave-26, D17): the ledger line ends with `idle=` and `room=`, the ready rows no launch
# covered while a slot was free, and the free slots at that moment. Positive on the same
# line first: the launched row is out of idle, the unlaunched one is in, and room is the line's own free.
S9_LED0="$S9_D0/.bionic/docs/record/wave-09-fixture/fill-ledger.log"
S9_FREE="$(sed -n 's/.*|free=\([0-9]*\)|.*/\1/p' "$S9_LED" 2>/dev/null)"
expect_true "9n: T16 the ledger line carries a free count to compare room against" test -n "$S9_FREE"
expect_contains "9o: T16 the row this turn did not launch is idle, the one it launched is not" \
  "|idle=T14|room=$S9_FREE" "$(cat "$S9_LED" 2>/dev/null)"
expect_contains "9p: T16 a turn that launched nothing leaves both ready rows idle" \
  "|idle=T13,T14|room=" "$(cat "$S9_LED0" 2>/dev/null)"

# THE LINE BUDGET (found while implementing, not at RED): the user line is width.sh's 100
# columns and refuse.sh refuses a longer one, which would turn this refusal into a refuse-call
# error. Eight ready rows, nothing launched: the headline names what fits and counts the rest,
# and the reason still names every row.
S9_D8="$(s9_fixture)"
S9_P8="$S9_D8/.bionic/docs/plans/epic-99-fixture/wave-09-fixture.plan.md"
for _s9_i in 101 102 103 104 105 106; do
  printf '| T%s | 4 | build | more | implementor | — | 15m | REQ-x | x%s.sh | pending | — |\n' "$_s9_i" "$_s9_i" >> "$S9_P8"
done
S9_TX8="$(mktemp)"; s9_transcript "$S9_TX8"
# ROOM FOR EIGHT (wave-33 T1; Δ10): each owed writer costs one core, and the suite's 8 cores at share
# 80 under a load of 1.0 owe five; these rows test the line budget over eight owed rows, so the
# machine is 16 cores (12.8).
BIONIC_PROBE_CORES=16 s7_fire "$S9_D8" "$S9_TX8"
expect_eq "9j: eight ready rows still refuse through the JSON block, not a refuse-call error" "block" \
  "$(printf '%s' "$STOP_OUT" | jq -r '.decision // ""' 2>/dev/null)"
expect_true "9l: …and keeps to 100 columns" test "$(printf '%s' "$(s9_headline)" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')" -le 100
expect_contains "9m: …while the reason names every row" "T106" "$(reason_of)"

# THE WIDTH IS THE GATE'S (wave-28 T13; D14, AC-2.8). 9h's fixture, nothing launched, under a
# five-minute load over the share: the gate gives no room, so the wall owes no row and its
# ledger records the hold. 9h above is the same fixture with room, and refuses. 8.0 busy cores of the
# fixture's 8 is over the gate's width at any share below 100 (92 x 8 / 100 = 7.36; wave-31 T36, A-T36-4).
S9_DG="$(s9_fixture)"
S9_TXG="$(mktemp)"; s9_transcript "$S9_TXG"
BIONIC_PROBE_BUSY_CORES_5M=8.0 s7_fire "$S9_DG" "$S9_TXG"
S9_LEDG="$S9_DG/.bionic/docs/record/wave-09-fixture/fill-ledger.log"
expect_contains "9q: with no room at the gate the ledger records the hold, both rows ready, none free" \
  "|state=hold|" "$(cat "$S9_LEDG" 2>/dev/null)"
expect_contains "9r: …free=0" "|free=0|" "$(cat "$S9_LEDG" 2>/dev/null)"
expect_absent "9s: …and the wall refuses no fill" "ready with room:" "$(reason_of)"
expect_contains "9t: the same fixture with room records state=ok (9q discriminates)" "|state=ok|" \
  "$(cat "$S9_LED0" 2>/dev/null)"
unset BIONIC_PRESSURE_RING BIONIC_NOW_EPOCH

# ─────────────────────────────────────────────────────────────────────────────
section "GAP: one width fact and one refusal — the wall asks the gate as the tick does, and names every unanswered row once (wave-36 T32; D13, AC-7.1)"

# THE DEFECT (found in wave-36's own run; record/wave-36-zero-machine-errors/fill-ledger.log from
# 2026-10-14T00:07Z). With one writer slot free and fourteen ready rows, the wall named only
# `min(free, ready)` of them, one; the next turn named the next row, fourteen turns in all. Now the
# wall's room is the gate's answer to the tick's own question, on one reading (`fill_gate_width`,
# whose first ask is the tick's gate line, `gate_room --owed <owed>`), and a refusal names every
# ready row in one line the user reads. The model's copy adds the rows comma-joined in one dispatch
# line and the three forms that make a row wait: a dependency, a read of a ruling, an order.
#
# THE READING IS PINNED for the tick and the wall alike: 8 cores at the default share 92 (7.36
# cores of room; HOME is a fresh directory, so no share file is read). The first row is asked with
# nothing owed and each row offered owes one promise more, so a busy reading of 7.0 leaves room for
# exactly one writer (7 <= 7.36 < 7 + the suite cost, wave-38 T5), and 8.0 for none.
gap_fixture() {  # -> project dir; three pending writer rows T13 T14 T15 reading their kind's default, an empty roster
  local d
  d=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$d/.bionic/tmp" "$d/.bionic/docs/plans/epic-99-fixture"
  { printf -- '---\ngoverning-skill: superpowers:writing-plans\n---\n\n# fixture plan\n\n'
    printf '## SDLC State\n\ncurrent: 4\napproved-by: fixture 2026-10-04T00:00Z "approved"\n\n- Step 4: in progress\n\n'
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | status | reads |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T13 | 4 | build | first | implementor | — | 15m | REQ-x | a.sh | pending |  |\n'
    printf '| T14 | 4 | build | second | implementor | — | 15m | REQ-x | b.sh | pending |  |\n'
    printf '| T15 | 4 | build | third | implementor | — | 15m | REQ-x | c.sh | pending |  |\n'
  } > "$d/.bionic/docs/plans/epic-99-fixture/wave-37-fixture.plan.md"
  bound_marker "$d" "$SID" "$d/.bionic/docs/plans/epic-99-fixture/wave-37-fixture.plan.md"
  roster_header > "$d/.bionic/tmp/roster-$SID.state"
  printf '%s' "$d"
}
gap_tick() {  # <project> <busy cores> -> the real tick's output on that reading
  local home
  home=$(cd "$(mktemp -d)" && pwd -P)
  ( cd "$1" && env HOME="$home" CLAUDE_CONFIG_DIR="" CLAUDE_CODE_SESSION_ID="$SID" \
      BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 \
      BIONIC_PROBE_BUSY_CORES="$2" BIONIC_PROBE_BUSY_CORES_5M="$2" \
      bash "$S7_POKER" tick 2>/dev/null )
}
gap_led() { cat "$1/.bionic/docs/record/wave-37-fixture/fill-ledger.log" 2>/dev/null; }
require_helpers gap_fixture gap_tick gap_led s7_transcript s7_fire s9_headline

# GAP1: NO ROOM AT THE GATE. The real tick on the reading ends `no FILL — the gate gives no room`,
# and the wall, on its turn and the same reading, passes and records the hold.
GAP_D1="$(gap_fixture)"
GAP_T1="$(gap_tick "$GAP_D1" 8.0)"
GAP_X1="$(mktemp)"; s7_transcript "$GAP_X1" "$GAP_T1"
BIONIC_PROBE_BUSY_CORES=8.0 BIONIC_PROBE_BUSY_CORES_5M=8.0 s7_fire "$GAP_D1" "$GAP_X1"
expect_contains "GAP1b meta: the wall read the turn — its ledger line is there" "fill-ledger/v1|" "$(gap_led "$GAP_D1" | tail -1)"
expect_contains "GAP1c …recording the gate's hold, three rows ready, none free" "|state=hold|" "$(gap_led "$GAP_D1" | tail -1)"
expect_eq "GAP1d the tick's no-room turn passes at stop" "" "$(printf '%s' "$STOP_OUT" | jq -r '.decision // ""' 2>/dev/null)"

# GAP2: ROOM FOR ONE, THREE READY. The tick on the reading offers one row; the wall refuses once,
# naming all three.
GAP_D2="$(gap_fixture)"
GAP_T2="$(gap_tick "$GAP_D2" 7.0)"
expect_contains "GAP2a precondition: the tick on this reading offers exactly one row" \
  "poker: FILL T13" "$GAP_T2"
expect_absent "GAP2a2 …and only one" "poker: FILL T13 T14" "$GAP_T2"
GAP_X2="$(mktemp)"; s7_transcript "$GAP_X2" "$GAP_T2"
BIONIC_PROBE_BUSY_CORES=7.0 BIONIC_PROBE_BUSY_CORES_5M=7.0 s7_fire "$GAP_D2" "$GAP_X2"
expect_contains "GAP2b meta: the wall's ledger counts one free slot on the same reading" "|free=1|" "$(gap_led "$GAP_D2" | tail -1)"
expect_eq "GAP2c the turn is refused" "block" "$(printf '%s' "$STOP_OUT" | jq -r '.decision // ""' 2>/dev/null)"
GAP_LINE="$(s9_headline)"
expect_true "GAP2e …under 100 columns" \
  test "$(printf '%s' "$GAP_LINE" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')" -lt 100
expect_contains "GAP2f the model's copy names all three rows, comma-joined, in one dispatch line" \
  "dispatch T13,T14,T15, or make each wait by one of three forms:" "$(reason_of)"
expect_eq "GAP2g …and is the line, a blank, that dispatch line and the three forms, nothing else" "6" \
  "$(reason_of | awk 'END { print NR }')"
expect_contains "GAP2h meta: the reason is the refusal's" "ready with room: T13 T14 T15" "$(reason_of)"
expect_absent "GAP2i …and the six-line paragraph is gone" "Fillable gap" "$(reason_of)"
expect_contains "GAP2j the tick that offered one row names the two behind the gap" \
  "behind the gap: T14 T15" "$GAP_T2"
expect_absent "GAP2k …and the tick names no decline" "decline" "$GAP_T2"

# GAP3: THE RULING FORM, RUN AS PRINTED, MAKES THE ROWS WAIT. The refusal's read-of-a-ruling line, its
# ID and DN filled in, is a task-set the poker takes: each row keeps its kind's reads and gains the
# decision, which is unruled, so the next turn end finds no row ready and passes.
GAP_CMD="$(reason_of | sed -n 's/^a read of a ruling: \(bash .* task-set ID reads+=approval:DN\).*$/\1/p' | head -1)"
expect_contains "GAP3a precondition: the reason holds the ruling form" "task-set ID reads+=approval:DN" "$GAP_CMD"
GAP_CMD="${GAP_CMD/ ID / T13,T14,T15 }"; GAP_CMD="${GAP_CMD/approval:DN/approval:D3}"
( cd "$GAP_D2" && env CLAUDE_CODE_SESSION_ID="$SID" bash -c "$GAP_CMD" >/dev/null 2>&1 )
GAP_P2="$GAP_D2/.bionic/docs/plans/epic-99-fixture/wave-37-fixture.plan.md"
expect_contains "GAP3b the read is appended after the kind's default reads, which the empty cell stood for" \
  "| T13 | 4 | build | first | implementor | — | 15m | REQ-x | a.sh | pending | approval:plan, approval:D3 |" "$(cat "$GAP_P2")"
expect_contains "GAP3c …on every row the command named" "| pending | approval:plan, approval:D3 |" "$(grep -F '| T15 |' "$GAP_P2")"
GAP_X3="$(mktemp)"
jq -nc '{type:"user",uuid:"u-gap3",isSidechain:false,timestamp:"2026-09-19T00:01:00Z",message:{role:"user",content:"carry on"}}' > "$GAP_X3"
BIONIC_PROBE_BUSY_CORES=7.0 BIONIC_PROBE_BUSY_CORES_5M=7.0 s7_fire "$GAP_D2" "$GAP_X3"
expect_contains "GAP3d meta: the next turn's ledger line still counts one free slot" "|free=1|" "$(gap_led "$GAP_D2" | tail -1)"
expect_contains "GAP3e …and no row ready" "|ready=|" "$(gap_led "$GAP_D2" | tail -1)"
expect_eq "GAP3f the rows wait on the ruling: the turn passes" "" \
  "$(printf '%s' "$STOP_OUT" | jq -r '.decision // ""' 2>/dev/null)"

# GAP4: A WAITING REQUEST ALONE LEAVES ROOM (wave-38 T5; D21, ADR-060). The gate's room reads its
# admitted runs and the owed count, never its queue: a landing run waiting at the gate used to answer
# room=no and close FILL for every writer. Planted: a store holding one landing request that waits,
# held by a live process, on the quiet reading (1.0 busy of 7.36). The tick counts it waiting and
# still offers FILL. The holder is this suite's own shell, live for the whole case and never a sleep
# (shell-lint's clock census), as gate.test.sh's held requests are.
GAP4_GATE="$(cd "$(mktemp -d)" && pwd -P)/gate"; mkdir -p "$GAP4_GATE/requests" "$GAP4_GATE/cost"
GAP4_HOLDER=$$
GAP4_START="$(bash -c '. "$1/payload/scripts/lib/slots.sh" && _slots_since "$2"' _ "$BIONIC_SCRIPTS_DIR" "$GAP4_HOLDER")"
printf 'key=a.test.sh\nkind=landing\nwho=%s:wx-T1\ntree=/\nasked=1000\nholder=%s:%s\n' \
  "$SID" "$GAP4_HOLDER" "$GAP4_START" > "$GAP4_GATE/requests/1"
GAP_D4="$(gap_fixture)"
GAP_T4="$(BIONIC_GATE_DIR="$GAP4_GATE" gap_tick "$GAP_D4" 1.0)"
expect_eq "GAP4-pre the request is still open after the tick: its holder lives, nothing ended it" "open" \
  "$(grep -q '^ended=' "$GAP4_GATE/requests/1" 2>/dev/null && echo ended || { [ -s "$GAP4_GATE/requests/1" ] && echo open; })"
GAP4_LINE="$(printf '%s\n' "$GAP_T4" | grep -F 'poker: gate ' | head -n 1)"
expect_nonempty "GAP4a precondition: the tick printed its gate line" "$GAP4_LINE"
expect_contains "GAP4b …which counts the one waiting request and gives room: the room reads admitted runs, not waiters" \
  "waiting=1 room=yes" "$GAP4_LINE"
expect_contains "GAP4c the tick offers FILL though a request waits at the gate" "poker: FILL T13" "$GAP_T4"

# ─────────────────────────────────────────────────────────────────────────────
section "UB: unbound means no run — two plans, two sessions, the real Stop per session (wave-23-fixit-1810, REQ-1, AC-1.1/AC-1.2)"

# THE SEED, REPRODUCED (record/wave-23-fixit-1810/seed-bug-fill-gate-acts-on-fallback-plan-
# 2026-10-02.md). One root, two open runs. Session A is bound to p1, whose ledger is live past
# Step 3 with one ready row (T5, its dependency landed). Session B engaged with no plan yet,
# so engagement wrote `plan=none`. p1 is the NEWEST open plan, which makes it B's
# newest-plan fallback — the exact state in which the fill gate charged B with A's row on
# every turn end ("launched 0 of 1 ready rows; not launched: T5"). The fallback is announced
# and never acted on now: B's Stop passes and says why, once; A's Stop is refused as before.
# p2 sits at Step 2 beside them so the root holds several runs, the shape that leaves a
# session unbound in the first place.
UB_SID_A="aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"
UB_SID_B="bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb"
ub_world() {  # -> the root on stdout; p1 newest, p2 older
  local d
  d=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$d/.bionic/tmp" "$d/.bionic/docs/plans/epic-99-ub"
  { printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
    printf 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=user\n'
    printf -- '---\n\n# p1\n\n## SDLC State\n\ncurrent: 4\napproved-by: fixture 2026-10-04T00:00Z "approved"\n\n- Step 4: in progress\n\n'
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | status | worktree |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T4 | 4 | build | the merge in flight | implementor | — | 15m | REQ-x | a.sh | landed | — |\n'
    printf '| T5 | 4 | build | the next row | implementor | T4 | 15m | REQ-x | b.sh | pending | — |\n'
  } > "$d/.bionic/docs/plans/epic-99-ub/p1.plan.md"
  { printf -- '---\ngoverning-skill: superpowers:writing-plans\n---\n\n# p2\n\n'
    printf '## SDLC State\n\ncurrent: 2\n\n- Step 2: designing\n'
  } > "$d/.bionic/docs/plans/epic-99-ub/p2.plan.md"
  touch -t 202601010000 "$d/.bionic/docs/plans/epic-99-ub/p2.plan.md"
  bound_marker "$d" "$UB_SID_A" "$d/.bionic/docs/plans/epic-99-ub/p1.plan.md"
  unbound_marker "$d" "$UB_SID_B" none
  roster_header > "$d/.bionic/tmp/roster-$UB_SID_A.state"
  roster_header > "$d/.bionic/tmp/roster-$UB_SID_B.state"
  printf '%s' "$d"
}
ub_fire() {  # <root> <sid> — an ordinary turn that dispatched nothing, ended by a real Stop
  local home tx payload
  home=$(cd "$(mktemp -d)" && pwd -P)
  tx=$(mktemp)
  jq -nc '{type:"user",uuid:"u-ub",isSidechain:false,timestamp:"2026-10-02T19:40:00Z",message:{role:"user",content:"scope wave 21"}}' > "$tx"
  payload=$(jq -nc --arg c "$1" --arg t "$tx" --arg s "$2" \
    '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:"Stop",stop_hook_active:false,background_tasks:[]}')
  STOP_OUT=$(env HOME="$home" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$2" \
    BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_SWAP_PCT=0 \
    bash "$HOOK" <<< "$payload" 2>"$STOP_ERRFILE")
  STOP_RC=$?
  STOP_ERR=$(cat "$STOP_ERRFILE" 2>/dev/null)
}
require_helpers ub_world ub_fire

UB_RING="$(mktemp)"; printf '1700000000|80|0|1.0|8\n' > "$UB_RING"
export BIONIC_PRESSURE_RING="$UB_RING" BIONIC_NOW_EPOCH=1700000000

UB_D="$(ub_world)"
UB_P1="$UB_D/.bionic/docs/plans/epic-99-ub/p1.plan.md"
expect_eq "UB0: premise — p1 is the newest open run, so it is B's fallback" \
  "fallback $UB_P1" \
  "$(bash -c '. "$1/payload/scripts/lib/run.sh" && session_run "$2" "$3"' _ "$BIONIC_SCRIPTS_DIR" "$UB_D" "$UB_SID_B")"

# UB1 (AC-1.1): the unbound session's Stop is not refused for p1's rows.
ub_fire "$UB_D" "$UB_SID_B"
expect_status "UB1: B (plan=none) ends its turn — exit 0" "0" "$STOP_RC"
expect_empty "UB1b: …with no block on stdout" "$STOP_OUT"
expect_absent "UB1c: …and is never told about p1's rows" "ready with room" "$STOP_ERR"
expect_absent "UB1d: …nor names T5 anywhere" "T5" "$STOP_OUT$STOP_ERR"

# UB3 (AC-1.3): B is told why, in lib/run.sh's one sentence, once — three verdicts meet the
# same fallback on this Stop, and the process says it once.
UB_LINE="run resolved by newest-plan fallback (session unbound) — $UB_P1; bind with session-poker.sh bind $UB_P1, or write this session's plan"

# UB2 (AC-1.2): the BOUND session, same root, same turn shape, T5 untouched -> refused.
ub_fire "$UB_D" "$UB_SID_A"
expect_eq "UB2: A (bound to p1) is refused — the fill gate's JSON block" "block" \
  "$(printf '%s' "$STOP_OUT" | jq -r '.decision // ""' 2>/dev/null)"
expect_contains "UB2b: …naming T5 as not launched" "ready with room: T5" "$STOP_ERR"
expect_absent "UB2c: …and A hears no unbound advisory" "session unbound" "$STOP_ERR"
unset BIONIC_PRESSURE_RING BIONIC_NOW_EPOCH

# ─────────────────────────────────────────────────────────────────────────────
section "WAIT: a row waits by a dependency, a read of a ruling or an order; the refusal names the three, and a waiting row is not ready, so the turn ends"

# THE DEFECT. A ready row the run meant to hold was answered by a reason in prose, which the wall
# read again on every turn end and the tick could not judge. A wait is a fact of the plan now: a
# read of the record of a row still open, a read of a decision nobody has ruled, or the user's order
# under ## SDLC State. Each leaves the row not ready, so the wall has nothing to refuse and the turn
# ends. Each wait has a control beside it, the same fixture with the wait removed, which is refused,
# so every pass below is the wait's doing and not a fixture the wall never reads.
wait_fixture() {  # <extra ## SDLC State lines, or ""> <row>... -> project dir; a reads table, bound, an empty roster
  local d extra="$1" r
  shift
  d=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$d/.bionic/tmp" "$d/.bionic/docs/plans/epic-99-fixture"
  { printf -- '---\ngoverning-skill: superpowers:writing-plans\n---\n\n# fixture plan\n\n'
    printf '## SDLC State\n\ncurrent: 4\napproved-by: fixture 2026-10-04T00:00Z "approved"\n'
    [ -z "$extra" ] || printf '%s\n' "$extra"
    printf '\n- Step 4: in progress\n\n## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | status | reads |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
    for r in "$@"; do printf '%s\n' "$r"; done
  } > "$d/.bionic/docs/plans/epic-99-fixture/wave-09-wait.plan.md"
  bound_marker "$d" "$SID" "$d/.bionic/docs/plans/epic-99-fixture/wave-09-wait.plan.md"
  roster_header > "$d/.bionic/tmp/roster-$SID.state"
  printf '%s' "$d"
}
wait_fire() {  # <project> -> the real Stop on an ordinary turn that dispatched nothing
  local tx
  tx="$(mktemp)"
  jq -nc '{type:"user",uuid:"u-wait",isSidechain:false,timestamp:"2026-10-20T00:00:00Z",message:{role:"user",content:"carry on"}}' > "$tx"
  s7_fire "$1" "$tx"
}
wait_led() { cat "$1/.bionic/docs/record/wave-09-wait/fill-ledger.log" 2>/dev/null; }
wait_decision() { printf '%s' "$STOP_OUT" | jq -r '.decision // ""' 2>/dev/null; }
require_helpers wait_fixture wait_fire wait_led wait_decision s7_fire reason_of

WT_READY='| T13 | 4 | build | ready | implementor | — | 15m | REQ-x | a.sh | pending |  |'
WT_RULED='| T13 | 4 | build | reads a ruling | implementor | — | 15m | REQ-x | a.sh | pending | approval:plan, approval:D3 |'
WT_REC='.bionic/docs/record/wave-09-wait/T12-held.md'

# WAIT1: THE REFUSAL NAMES THE THREE FORMS. One ready row, room, nothing launched.
W_D1="$(wait_fixture "" "$WT_READY")"
wait_fire "$W_D1"
expect_eq "WAIT1 a ready row with room and nothing launched is refused" "block" "$(wait_decision)"
W_R="$(reason_of)"
expect_contains "WAIT1b the refusal names the first form, a dependency" "a dependency: bash " "$W_R"
expect_contains "WAIT1c …a task-set that reads the record of the row it waits on" "task-set ID reads+=RECORD" "$W_R"
expect_contains "WAIT1d the second, a read of a ruling" "a read of a ruling: bash " "$W_R"
expect_contains "WAIT1e …a task-set that reads the decision" "task-set ID reads+=approval:DN" "$W_R"
expect_contains "WAIT1f the third, an order" "an order: bash " "$W_R"
expect_contains "WAIT1g …the order verb with what the user said" "order 'WORDS'" "$W_R"
expect_absent "WAIT1h …and no decline anywhere in the refusal" "decline" "$W_R$STOP_ERR"
expect_contains "WAIT1i the line the user reads names the row and the fix" "ready with room: T13 (dispatch, or make each wait)" "$STOP_ERR"

# WAIT2: A READ OF AN UNRULED DECISION. The row reads D3, which no approved: line rules.
W_D2="$(wait_fixture "" "$WT_RULED")"
wait_fire "$W_D2"
expect_contains "WAIT2 meta: the wall read the turn, its ledger line is there" "fill-ledger/v1|" "$(wait_led "$W_D2" | tail -1)"
expect_contains "WAIT2b …and the row reading the unruled D3 is not ready" "|ready=|" "$(wait_led "$W_D2" | tail -1)"
expect_eq "WAIT2c the turn ends: no refusal" "" "$(wait_decision)"
W_D2R="$(wait_fixture 'approved: D3 fixture "go"' "$WT_RULED")"
wait_fire "$W_D2R"
expect_eq "WAIT2d the control: D3 ruled, the same row is ready and refused" "block" "$(wait_decision)"
expect_contains "WAIT2e …naming it" "ready with room: T13" "$STOP_ERR"

# WAIT3: A DEPENDENCY ON AN OPEN ROW. T13 reads the record T12 writes, and T12 is active.
W_D3="$(wait_fixture "" \
  "| T12 | 4 | build | the open row | implementor | — | 15m | REQ-x | $WT_REC, z.sh | active |  |" \
  "| T13 | 4 | build | waits on T12 | implementor | — | 15m | REQ-x | a.sh | pending | approval:plan, $WT_REC |")"
wait_fire "$W_D3"
expect_contains "WAIT3 meta: the wall read the turn" "fill-ledger/v1|" "$(wait_led "$W_D3" | tail -1)"
expect_contains "WAIT3b …and the row waiting on the open T12 is not ready" "|ready=|" "$(wait_led "$W_D3" | tail -1)"
expect_eq "WAIT3c the turn ends: no refusal" "" "$(wait_decision)"
W_D3L="$(wait_fixture "" \
  "| T12 | 4 | build | the landed row | implementor | — | 15m | REQ-x | $WT_REC, z.sh | landed |  |" \
  "| T13 | 4 | build | waits on T12 | implementor | — | 15m | REQ-x | a.sh | pending | approval:plan, $WT_REC |")"
wait_fire "$W_D3L"
expect_eq "WAIT3d the control: T12 landed, T13 is ready and refused" "block" "$(wait_decision)"
expect_contains "WAIT3e …naming it" "ready with room: T13" "$STOP_ERR"

# WAIT4: THE USER'S ORDER. An open order makes no row ready; the order lifted, the row is owed again.
W_D4="$(wait_fixture 'order: given 2026-10-20T00:00:00Z "hold the fleet while I read"' "$WT_READY")"
wait_fire "$W_D4"
expect_contains "WAIT4 meta: the wall read the turn" "fill-ledger/v1|" "$(wait_led "$W_D4" | tail -1)"
expect_contains "WAIT4b …and under the open order no row is ready" "|ready=|" "$(wait_led "$W_D4" | tail -1)"
expect_eq "WAIT4c the turn ends: no refusal" "" "$(wait_decision)"
W_D4L="$(wait_fixture 'order: given 2026-10-20T00:00:00Z "hold the fleet while I read"
order: lifted 2026-10-20T00:30:00Z "hold the fleet while I read"' "$WT_READY")"
wait_fire "$W_D4L"
expect_eq "WAIT4d the control: the order lifted, the row is ready and refused" "block" "$(wait_decision)"
expect_contains "WAIT4e …naming it" "ready with room: T13" "$STOP_ERR"

# ─────────────────────────────────────────────────────────────────────────────
section "GONE: no verb records a wait in prose: decline is an unknown verb, nothing writes a decline or a lapse, and the Patrol prompt names none"

# THE HISTORY READER. A run's old fill ledger keeps its decline and lapse lines, and the hand-holds
# count (hooks/poker/line.sh) still counts them as history, so its text spells the state. Every
# other hit of the three shapes in the shipped code is a writer, or a reader of the reply form.
GONE_POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"
GONE_HITS="$(/usr/bin/grep -rlE 'state=decline|state=lapsed|fill-declined' "$BIONIC_HOOKS_DIR" "$BIONIC_SCRIPTS_DIR/payload/scripts" 2>/dev/null \
  | sed "s#^$BIONIC_SCRIPTS_DIR/##" | sort -u)"
expect_contains "GONE1 the grep reads the shipped tree: the hand-holds reader is found" "hooks/poker/line.sh" "$GONE_HITS"
expect_eq "GONE1b …and is the only hit" "hooks/poker/line.sh" "$GONE_HITS"

GONE_OUT="$(cd "$(mktemp -d)" && env CLAUDE_CODE_SESSION_ID="$SID" bash "$GONE_POKER" decline T1 'why they wait' 2>&1)"
GONE_RC=$?
expect_eq "GONE2 the decline verb exits as any unknown verb does" "2" "$GONE_RC"
expect_contains "GONE2b …and says it is unknown" "unknown verb: decline" "$GONE_OUT"

GONE_PROMPT="$(cd "$(mktemp -d)" && env CLAUDE_CODE_SESSION_ID="$SID" bash "$GONE_POKER" prompt 2>/dev/null)"
expect_contains "GONE3 the Patrol prompt still says how a FILL is answered" 'Answer a FILL only if a "poker: FILL" line printed' "$GONE_PROMPT"
expect_absent "GONE3b …and names no decline" "decline" "$GONE_PROMPT"

# ─────────────────────────────────────────────────────────────────────────────
finish
