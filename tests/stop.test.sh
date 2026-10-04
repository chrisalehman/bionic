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
# THE FIVE CASES (R7b):
#   §1  two verdicts block on one Stop -> BOTH reasons, blocks before advisories
#   §2  one block and one advisory     -> the block first, the advisory kept
#   §3  four quiet verdicts            -> silent, exit 0
#   §4  a SubagentStop payload         -> only the landing arm can speak
#   §5  stop_hook_active: true         -> silent, and the guard is read ONCE
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
expect_contains "1c: the PATROL reason is too — not just the first blocker" \
  "The Patrol died mid-run and nothing said so." "$(reason_of)"
expect_true "1d: …and in the manifest's order, landing before patrol, by offset" \
  test "$(offset_in_reason 'LANDING CONTRACT UNMET')" -lt \
       "$(offset_in_reason 'The Patrol died mid-run')"
expect_eq "1e: the user stream carries exactly ONE rendered refusal, not two" \
  "1" "$(refusal_lines)"
expect_contains "1f: …and it is the first blocker's line" \
  "bionic: stop refused — a dispatched agent's contract is unmet" "$STOP_ERR"

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
expect_contains "2b: its line is on stderr" \
  "bionic: stop refused — a dispatched agent's contract is unmet" "$STOP_ERR"
expect_eq "2c: exactly one rendered refusal" "1" "$(refusal_lines)"
expect_contains "2d: the advisory is kept" \
  "run resolved by newest-plan fallback (session unbound) — " "$STOP_ERR"
expect_true "2e: …after the refusal" \
  test "$(awk '/^bionic: /{print NR; exit}' <<<"$STOP_ERR")" -lt \
       "$(awk '/^run resolved by newest-plan fallback/{print NR; exit}' <<<"$STOP_ERR")"

# ─────────────────────────────────────────────────────────────────────────────
section "3: four quiet verdicts — silence, exit 0"

# A BYSTANDER SESSION. Every one of the four asks engagement before it acts, so a
# session that never invoked canonical-sdlc must see nothing at all — not a
# refusal, not an advisory, not a state write.
D=$(mkfix); rm -f "$D/.bionic/tmp/engaged-$SID.state"
fire "$D"
expect_status "3a: a bystander turn end exits 0" "0" "$STOP_RC"
expect_empty "3b: …with nothing on stdout" "$STOP_OUT"
expect_empty "3c: …and nothing on stderr" "$STOP_ERR"

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
section "5: stop_hook_active — the re-entrancy guard is read ONCE, for all four"

# BLOCKS ONCE. Claude Code re-enters the stop with the flag true after a hook
# blocked it; refusing again would wedge the turn with no way out. Three of the four
# hooks carried an identical copy of this line and the fourth carried none; there is
# one now, ahead of all four, and a fixture that makes TWO of them block is what
# shows it covers the whole process rather than one arm.
D=$(mkfix); unmet_row "$D"; stale_stamp "$D"
fire "$D" Stop true
expect_status "5a: a re-entry exits 0" "0" "$STOP_RC"
expect_empty "5b: …with nothing on stdout" "$STOP_OUT"
expect_empty "5c: …and nothing at all on stderr, advisories included" "$STOP_ERR"

# NOT VACUOUS: the identical fixture without the flag refuses.
fire "$D" Stop false
expect_nonempty "5d: …while the same fixture without the flag does refuse" "$STOP_OUT$STOP_ERR"

# ─────────────────────────────────────────────────────────────────────────────
section "6: the derivation bound has ONE owner (REQ-7, AC-7.4)"

# WHAT CHANGED, AND WHY THERE ARE TWO NUMBERS (spec D4; wave-14 T15 fold-in).
# `tests/lib/impact.sh` used to rebuild its whole edge graph on every invocation
# — ~4.2 s at quiet load, argument-independent to 13 ms (R2 Q8) — so the number
# bounding it was doing two jobs at once: paying for a cost nobody had removed,
# and guarding against a command that never returns. The graph is cached per
# tree state now, which leaves the bound one job: a HANG GUARD.
#
# BUT A HANG GUARD IS ONLY AS LONG AS ITS HOST WILL WAIT, and the two legs have
# different hosts. THE RULE IS THE SAME FOR BOTH (wave-14 D2, ratified): every
# inner bound sits strictly under its own hook's registration, margin named —
# the wall's 10 s under dispatch-preflight.sh's 15 s registration, the sweep's
# 6 s under hooks/stop.sh's `"timeout": 10` on Stop and SubagentStop. A bound at
# or above its registration is never reached, because the CLI kills the hook at
# the registration and a hook killed on the harness's timeout does NOT exit 2:
# the refusal becomes a pass, which is the one thing the gate must never do.
# tests/landing-gate.test.sh §16i measures exactly that, live, and caught it;
# tests/cross-gate-agreement.test.sh §L.4c pins both pairs against hooks.json.
# So lib/bounds.sh owns TWO named bounds and each consumer reads its own.
#
# TWO COPIES IS STILL THE DEFECT THIS SECTION EXISTS FOR — two numbers under one
# owner is not two copies. The sweep's bound at lib/stop.sh and the dispatch
# wall's at dispatch-preflight.sh:2225 were the same 6 s, written twice, in two
# files, with two independent budgets and neither file saying the other existed.
# What these rows hold is that every numeric definition lives in ONE file, and
# that lib/stop.sh defines nothing of its own — it reads.
#
# STATIC, BY THE SPEC'S OWN EVAL DESIGN (AC-7.4, eval type `static`). Observing
# either value through the sweep would mean hanging a real derivation to read one
# number out of one message, and would still say nothing about the second
# consumer. So these rows read the files — and because a grep against a file is
# exactly the assertion that keeps passing after its pattern has drifted, each
# reading is PAIRED with a mutation that removes what it looks for.
BOUNDS_SH="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/bounds.sh"
STOP_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/stop.sh"

expect_true "6a: payload/scripts/lib/bounds.sh exists" test -f "$BOUNDS_SH"
expect_true "6b: …and parses under bash -n" bash -n "$BOUNDS_SH"

# THE VALUES ARE READ BY SOURCING, not by grepping literals back out of the file:
# what a consumer gets is what sourcing gives it.
expect_eq "6c: sourcing it defines IMPACT_BOUND_S=10, the dispatch wall's guard, under its own 15s registration" "10" \
  "$(bash -c '. "$1" 2>/dev/null && printf "%s" "${IMPACT_BOUND_S:-}"' _ "$BOUNDS_SH" 2>/dev/null)"
expect_eq "6d: …and LG_IMPACT_BOUND_S=6, the landing gate's, inside a 10s hook" "6" \
  "$(bash -c '. "$1" 2>/dev/null && printf "%s" "${LG_IMPACT_BOUND_S:-}"' _ "$BOUNDS_SH" 2>/dev/null)"

# THE LANDING GATE'S BOUND IS STRICTLY UNDER ITS HOOK'S REGISTRATION, and the
# registration is read from hooks.json rather than typed here — a wave that
# raised the Stop hook's timeout without revisiting this number would otherwise
# leave the row green while the reason for it had moved.
HOOKS_JSON="${BIONIC_SCRIPTS_DIR}/hooks/hooks.json"
LG_HOOK_TIMEOUT="$(/usr/bin/grep -A3 '"command": "\${CLAUDE_PLUGIN_ROOT}/hooks/stop.sh"' \
  "$HOOKS_JSON" 2>/dev/null | /usr/bin/grep -oE '"timeout": [0-9]+' | head -1 \
  | /usr/bin/grep -oE '[0-9]+')"
expect_eq "6e: hooks.json registers hooks/stop.sh at a 10s timeout" "10" "${LG_HOOK_TIMEOUT:-}"
if [ -n "$LG_HOOK_TIMEOUT" ] && [ "6" -lt "$LG_HOOK_TIMEOUT" ] 2>/dev/null; then
  ok "6f: …and the landing gate's bound (6s) is strictly under it, so the sweep ends on OUR terms"
else
  no "6f: …and the landing gate's bound (6s) is strictly under it, so the sweep ends on OUR terms" \
    "registration=${LG_HOOK_TIMEOUT:-<unread>}s"
fi

# NOT VACUOUS: the rows above read the file rather than agreeing with constants
# typed into this suite, and a copy carrying different numbers proves it.
B_MUTD="$(mktemp -d)"
anchor -E "$BOUNDS_SH" '^IMPACT_BOUND_S=10$' 1
anchor -E "$BOUNDS_SH" '^LG_IMPACT_BOUND_S=6$' 1
sed -e 's/^IMPACT_BOUND_S=10$/IMPACT_BOUND_S=3/' \
    -e 's/^LG_IMPACT_BOUND_S=6$/LG_IMPACT_BOUND_S=4/' "$BOUNDS_SH" >"$B_MUTD/bounds.sh"
expect_eq "6g: …and a copy carrying 3 answers 3, so 6c read the file" "3" \
  "$(bash -c '. "$1" 2>/dev/null && printf "%s" "${IMPACT_BOUND_S:-}"' _ "$B_MUTD/bounds.sh" 2>/dev/null)"
expect_eq "6h: …and that copy answers 4 for the gate's, so 6d read it too" "4" \
  "$(bash -c '. "$1" 2>/dev/null && printf "%s" "${LG_IMPACT_BOUND_S:-}"' _ "$B_MUTD/bounds.sh" 2>/dev/null)"

# THE HEADER SAYS WHAT THE NUMBERS ARE FOR. Without those sentences the next
# reader who meets a slow derivation tunes them, which is the habit D4 retires —
# and the reader who meets the SHORTER one has to be told it is not a tuned
# budget but a ceiling the Stop hook's own registration imposes.
# Case-tolerant on purpose: the file says it in a heading (HANG GUARD) and a
# reviewer who rewords the heading in lower case has not weakened anything.
BOUNDS_SRC="$(cat "$BOUNDS_SH" 2>/dev/null)"
expect_regex "6i: …and its header names the number a hang guard" \
  "[Hh][Aa][Nn][Gg][ -][Gg][Uu][Aa][Rr][Dd]" "$BOUNDS_SRC"
expect_contains "6j: …and says why the gate's is the shorter one: the 10 s registration" \
  '"timeout": 10' "$BOUNDS_SRC"
expect_contains "6k: …naming what a bound at or above it costs — the killed hook's exit" \
  "124" "$BOUNDS_SRC"

# ONE OWNER IN THE LIBRARY TREE (AC-7.4, this task's half). A DEFINITION is a
# literal number; a consumer's read of the constant is not counted, which is the
# distinction the criterion's "defined in two places" turns on — the criterion's
# own spelling, `grep -rn 'IMPACT_BOUND_S='`, matches both and can never reach
# one. TWO NAMES, ONE FILE: what the row holds is the FILE count, because the
# defect was two files disagreeing, not one file carrying two bounds it explains.
#
# SCOPED TO payload/scripts/, AND THE SCOPE IS THE POINT. The other consumer is
# hooks/dispatch-preflight.sh, which still carries its own `IMPACT_BOUND_S=6`
# until T6 re-points it; that file's row belongs to
# tests/dispatch-preflight.test.sh, and a count here that spanned both would be
# pinning a transitional state — green today only because T6 has not landed, red
# the moment it does. What this suite owns is that the LIBRARY has one owner.
#
# AND THE FLEET-WIDE SWEEP MUST NAME hooks/ SEPARATELY. `payload/hooks` is a
# symlink to `../hooks`, and neither `grep -r` nor `grep -R` descends through a
# symlinked directory met during recursion — so AC-7.4's literal command over
# `payload/` cannot see the preflight's definition at all, and would report "one"
# while two exist. Whoever discharges AC-7.4 at Step 5 scans
# `payload/scripts/` and `hooks/`, or `find -L`.
B_DEFS="$(/usr/bin/grep -rnE '^[[:space:]]*[A-Z_]*IMPACT_BOUND_S=[0-9]' \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts" 2>/dev/null)"
expect_eq "6l: the two numeric bound definitions in payload/scripts/ live in ONE file" \
  "1" "$(printf '%s\n' "$B_DEFS" | cut -d: -f1 | sort -u | /usr/bin/grep -c .)"
expect_eq "6m: …and there are exactly two of them, one per bound" \
  "2" "$(printf '%s\n' "$B_DEFS" | /usr/bin/grep -c .)"
expect_contains "6n: …and the file is lib/bounds.sh" "lib/bounds.sh" "$B_DEFS"
# NOT VACUOUS: the sweep reaches a file it could have missed, and the READ in
# lib/stop.sh is inside its span and deliberately uncounted.
expect_nonempty "6o: the sweep reaches lib/stop.sh, whose READ it declines to count" \
  "$(/usr/bin/grep -rn 'IMPACT_BOUND_S' "${BIONIC_SCRIPTS_DIR}/payload/scripts" 2>/dev/null \
     | /usr/bin/grep 'lib/stop.sh')"

# THIS CONSUMER READS IT, AND READS THE GATE'S. The dispatch wall is the other,
# pinned in its own suite; what stop.test.sh owns is the sweep's side. The name
# matters as much as the number: reading IMPACT_BOUND_S here would put the
# preflight's bound — sized for ITS registration — inside a hook the CLI kills
# at 10 (§16i).
STOP_SRC="$(cat "$STOP_LIB")"
expect_nonempty "6p: lib/stop.sh sources lib/bounds.sh" \
  "$(/usr/bin/grep -nE '^[[:space:]]*(\.|source)[[:space:]]+.*bounds\.sh' "$STOP_LIB")"
expect_no_regex "6q: …and defines neither bound itself — the value it uses is the library's" \
  '^[[:space:]]*(local[[:space:]]+)?(LG_)?IMPACT_BOUND_S=' "$STOP_SRC"
# THE PAIRED POSITIVE for 6q, so the row above cannot pass on a file that stopped
# mentioning the bound at all: the sweep's wait ends on the NAME, and both refusal
# messages quote it.
#
# RE-SPELLED ONTO THE CLOCK (wave-14 T35, carrying T34's fix across). This read the
# sweep's tick budget, `LG_IMPACT_TICKS_LEFT=$(( LG_IMPACT_BOUND_S * 10 ))`, and asserted
# it was DERIVED from the constant rather than typed as a second literal. The budget is
# gone: a count of `sleep 0.1` polls cost 115 ms a poll, so spending six seconds of them
# waited ~6.9 s inside a 10 s registration — the margin the shorter bound exists to keep,
# eaten by the spending of it, and by more under load. The wait now ends on `SECONDS`
# against the constant itself, which is the strongest form of "not a second number":
# no second number at all.
expect_regex "6r: …and the sweep's wait ends on LG_IMPACT_BOUND_S itself, not on a derived second number" \
  '\[[[:space:]]*"\$SECONDS"[[:space:]]*-ge[[:space:]]*"\$LG_IMPACT_BOUND_S"[[:space:]]*\]' "$STOP_SRC"
expect_eq "6s: …and both refusal messages quote the bound they actually used" "2" \
  "$(/usr/bin/grep -c '\${LG_IMPACT_BOUND_S}s' "$STOP_LIB" | tr -d ' ')"

# AND NO TICK BUDGET IS LEFT TO DRIFT AGAINST IT. A count of polls beside a bound in
# seconds is two numbers meaning one thing, and the poll is not a tenth of a second: it
# is a fork, an exec and a tenth of a second. LINE-ANCHORED on purpose — the removed
# expression survives inside the comment that explains why it went, and a pin that could
# match a comment would go green on a file that still ran one.
expect_no_regex "6t: …leaving no tick budget behind to drift against it" \
  '^[[:space:]]*LG_IMPACT_TICKS_LEFT=' "$STOP_SRC"

# NOT VACUOUS: a copy with the source line cut has nothing for 6p to find, so
# 6p discriminates rather than matching any mention of the name anywhere.
S_MUTD="$(mktemp -d)"
anchor -E "$STOP_LIB" '^[[:space:]]*(\.|source)[[:space:]]+.*bounds\.sh' 1
/usr/bin/grep -vE '^[[:space:]]*(\.|source)[[:space:]]+.*bounds\.sh' "$STOP_LIB" \
  >"$S_MUTD/stop.sh"
expect_empty "6u: …and a copy with that line cut has no source line left to find" \
  "$(/usr/bin/grep -nE '^[[:space:]]*(\.|source)[[:space:]]+.*bounds\.sh' "$S_MUTD/stop.sh")"


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
# every arm of the wall against synthesised text, which is right for a suite about the wall
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
    printf 'parallel-budget: writers=2 suites=2 worktrees=8 test_jobs=8 source=probe\n'
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
  "Fillable gap at turn end" "$(reason_of)"
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
  "Fillable gap" "$(reason_of)$STOP_ERR"
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

# ─────────────────────────────────────────────────────────────────────────────
section "9: the fill refusal's headline counts the turn's launches and names only the rows left out (wave-20 T11b; review R4)"

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
    printf 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=probe\n'
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
s7_fire "$S9_D" "$S9_TX"
expect_contains "9a: the turn that launched one of two ready rows is refused for the fill" \
  "Fillable gap at turn end" "$(reason_of)"
expect_contains "9b: T11b the headline states the counts — launched 1 of 2" "launched 1 of 2" "$(s9_headline)"
expect_contains "9c: …and names the row that was not launched" "not launched: T14" "$(s9_headline)"
expect_contains "9d: …as the reason does" "T14" "$(reason_of)"
expect_absent "9e: T11b the row this turn launched is never named as missed, pending or not" \
  "T13" "$(s9_headline)$(reason_of)"
S9_LED="$S9_D/.bionic/docs/record/wave-09-fixture/fill-ledger.log"
expect_contains "9f: …and the ledger's ready set is still the plan's, both rows" "|ready=T13,T14|" "$(cat "$S9_LED" 2>/dev/null)"
expect_contains "9g: …with one row missed, not two" "|missed=1" "$(cat "$S9_LED" 2>/dev/null)"

# THE ZERO CASE, so 9b cannot pass on a constant: nothing launched reads 0 of 2, both named.
S9_D0="$(s9_fixture)"
S9_TX0="$(mktemp)"; s9_transcript "$S9_TX0"
s7_fire "$S9_D0" "$S9_TX0"
expect_contains "9h: a turn that launched nothing reads 0 of 2" "launched 0 of 2" "$(s9_headline)"
expect_contains "9i: …and names both rows" "not launched: T13 T14" "$(s9_headline)"

# T16 (wave-26, D17): the ledger line ends with `idle=` and `room=`, the ready rows no launch and no
# decline covered while a slot was free, and the free slots at that moment. Positive on the same
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
s7_fire "$S9_D8" "$S9_TX8"
expect_eq "9j: eight ready rows still refuse through the JSON block, not a refuse-call error" "block" \
  "$(printf '%s' "$STOP_OUT" | jq -r '.decision // ""' 2>/dev/null)"
expect_contains "9k: …the headline counts the names it could not fit" "more (dispatch or decline)" "$(s9_headline)"
expect_true "9l: …and keeps to 100 columns" test "$(printf '%s' "$(s9_headline)" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')" -le 100
expect_contains "9m: …while the reason names every row" "T106" "$(reason_of)"
unset BIONIC_PRESSURE_RING BIONIC_NOW_EPOCH

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
    printf 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=probe\n'
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
expect_absent "UB1c: …and is never told about p1's rows" "not launched" "$STOP_ERR"
expect_absent "UB1d: …nor names T5 anywhere" "T5" "$STOP_OUT$STOP_ERR"

# UB3 (AC-1.3): B is told why, in lib/run.sh's one sentence, once — three verdicts meet the
# same fallback on this Stop, and the process says it once.
UB_LINE="run resolved by newest-plan fallback (session unbound) — $UB_P1; bind with session-poker.sh bind $UB_P1, or write this session's plan"
expect_eq "UB3: B's stderr carries the unbound advisory exactly once" \
  "1" "$(printf '%s\n' "$STOP_ERR" | grep -cxF "$UB_LINE")"
expect_eq "UB3b: …and that is the whole of what the Stop says to B" "$UB_LINE" "$STOP_ERR"

# UB2 (AC-1.2): the BOUND session, same root, same turn shape, T5 untouched -> refused.
ub_fire "$UB_D" "$UB_SID_A"
expect_eq "UB2: A (bound to p1) is refused — the fill gate's JSON block" "block" \
  "$(printf '%s' "$STOP_OUT" | jq -r '.decision // ""' 2>/dev/null)"
expect_contains "UB2b: …naming T5 as not launched" "not launched: T5" "$STOP_ERR"
expect_absent "UB2c: …and A hears no unbound advisory" "session unbound" "$STOP_ERR"
unset BIONIC_PRESSURE_RING BIONIC_NOW_EPOCH

# ─────────────────────────────────────────────────────────────────────────────
section "SD: a fill decline stands against the ready set it answered (wave-24 T8, REQ-4, AC-4.7; D2)"

# THE DEFECT. A `fill-declined: <reason>` answered the turn it was written in and no other, so
# a decline with a reason that still held ("T7 waits on T6's merge") had to be written again on
# every turn end until the reason went away. The fill ledger already records each Stop's ready
# set, `current:` and decline. The collector now reads the session's latest declined line from
# it, and the wall refuses only when a row is ready that the decline did not answer, or when
# `current:` has moved. The predicate is "an unanswered row exists", not "a decline exists".
# Each turn is its own transcript, keyed by its own prompt uuid; the ledger is what carries.
sd_fixture() {  # -> project dir; T7 pending, writers=8, current: 4
  local d
  d=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$d/.bionic/tmp" "$d/.bionic/docs/plans/epic-99-fixture"
  { printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
    printf 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=probe\n'
    printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: 4\napproved-by: fixture 2026-10-04T00:00Z "approved"\n\n- Step 4: in progress\n\n'
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | status | worktree |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T7 | 4 | build | the row behind a merge | implementor | — | 15m | REQ-x | a.sh | pending | — |\n'
  } > "$d/.bionic/docs/plans/epic-99-fixture/wave-24-sd.plan.md"
  bound_marker "$d" "$SID" "$d/.bionic/docs/plans/epic-99-fixture/wave-24-sd.plan.md"
  roster_header > "$d/.bionic/tmp/roster-$SID.state"
  printf '%s' "$d"
}
sd_turn() {  # <file> <prompt uuid> [assistant text]
  { jq -nc --arg u "$2" '{type:"user",uuid:$u,isSidechain:false,timestamp:"2026-10-03T00:00:00Z",message:{role:"user",content:"carry on"}}'
    [ -z "${3:-}" ] || jq -nc --arg t "$3" '{type:"assistant",isSidechain:false,timestamp:"2026-10-03T00:00:01Z",
                                          message:{role:"assistant",content:[{type:"text",text:$t}]}}'
  } > "$1"
}
sd_led() { cat "$1/.bionic/docs/record/wave-24-sd/fill-ledger.log" 2>/dev/null; }
sd_field() {  # <ledger line> <key>
  printf '%s\n' "$1" | awk -F'|' -v k="$2" '{ for (i = 2; i <= NF; i++) if (index($i, k "=") == 1) print substr($i, length(k) + 2) }'
}
sd_decision() { printf '%s' "$STOP_OUT" | jq -r '.decision // ""' 2>/dev/null; }
require_helpers sd_fixture sd_turn sd_led sd_field sd_decision

SD_RING="$(mktemp)"; printf '1700000000|80|0|1.0|8\n' > "$SD_RING"
export BIONIC_PRESSURE_RING="$SD_RING" BIONIC_NOW_EPOCH=1700000000

SD_D="$(sd_fixture)"
SD_P="$SD_D/.bionic/docs/plans/epic-99-fixture/wave-24-sd.plan.md"
SD_TX="$(mktemp)"

# SD1: the turn that declines is answered by its own line.
sd_turn "$SD_TX" u-sd-1 "fill-declined: T7 waits on the T6 merge"
s7_fire "$SD_D" "$SD_TX"
expect_eq "SD1: the declining turn ends" "" "$(sd_decision)"
expect_contains "SD1b: …and its ledger line carries the reason against ready {T7}" \
  "|ready=T7|" "$(sd_led "$SD_D" | tail -1)"

# SD2: the next turn, no text, the ready set unchanged. The decline stands.
sd_turn "$SD_TX" u-sd-2
s7_fire "$SD_D" "$SD_TX"
expect_eq "SD2: AC-4.7 next turn, ready {T7}, no text — passes on the standing decline" "" "$(sd_decision)"
expect_contains "SD2b: …and its ledger line carries the standing reason, so the report keeps the idle cost with it" \
  "T7 waits on the T6 merge" "$(sd_field "$(sd_led "$SD_D" | tail -1)" declined)"

# SD3: a row the decline never saw is ready. Refused, naming that row and not the declined one.
printf '| T8 | 4 | build | a row nobody declined | implementor | — | 15m | REQ-x | b.sh | pending | — |\n' >> "$SD_P"
sd_turn "$SD_TX" u-sd-3
s7_fire "$SD_D" "$SD_TX"
expect_eq "SD3: AC-4.7 ready {T7,T8}, no text — refused" "block" "$(sd_decision)"
expect_contains "SD3b: …naming T8" "not launched: T8" "$STOP_ERR"
expect_absent "SD3c: …and not T7, which the decline answered" "T7" "$(printf '%s\n' "$STOP_ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_eq "SD3d: …and the refused turn's line carries no decline, so the standing set does not grow" \
  "" "$(sd_field "$(sd_led "$SD_D" | tail -1)" declined)"

# SD4 (the `current:` move) is §DECLINE's D2 now: since wave-26 T15 (D16) a move of `current:`
# alone no longer voids a standing decline, so the row that pinned the refusal was inverted there.

# SD5: an empty `fill-declined:` is not an answer, in its own turn or the next.
SD_D5="$(sd_fixture)"
sd_turn "$SD_TX" u-sd5-1 "fill-declined:   "
s7_fire "$SD_D5" "$SD_TX"
expect_eq "SD5: an empty fill-declined: does not answer the gap" "block" "$(sd_decision)"
expect_eq "SD5b: …and records no decline" "" "$(sd_field "$(sd_led "$SD_D5" | tail -1)" declined)"
sd_turn "$SD_TX" u-sd5-2
s7_fire "$SD_D5" "$SD_TX"
expect_eq "SD5c: …so nothing stands on the next turn" "block" "$(sd_decision)"

# SD6: the decline is this session's. A line another session wrote into the same plan's ledger
# was an answer the model in this conversation never gave.
SD_D6="$(sd_fixture)"
sd_turn "$SD_TX" u-sd6-1 "fill-declined: T7 waits on the T6 merge"
s7_fire "$SD_D6" "$SD_TX"
sed -i.bak "s/|session=$SID|/|session=ffffffff-0000-4000-8000-000000000000|/" \
  "$SD_D6/.bionic/docs/record/wave-24-sd/fill-ledger.log"
expect_contains "SD6 precondition: the decline now belongs to another session" \
  "|session=ffffffff-" "$(sd_led "$SD_D6")"
sd_turn "$SD_TX" u-sd6-2
s7_fire "$SD_D6" "$SD_TX"
expect_eq "SD6: another session's decline does not stand in this one" "block" "$(sd_decision)"

# SD7 (wave-24 T27; Step-6 review C4): a ledger line written before the reason rule (A-T8.7),
# whose decline is only a dash, is not an answer either. The reader holds the line to the rule
# the turn's own decline is held to: a letter or a digit.
SD_D7="$(sd_fixture)"
sd_turn "$SD_TX" u-sd7-1 "fill-declined: T7 waits on the T6 merge"
s7_fire "$SD_D7" "$SD_TX"
expect_eq "SD7 precondition: the declining turn ends" "" "$(sd_decision)"
sed -i.bak 's/|declined=[^|]*|/|declined=—|/' "$SD_D7/.bionic/docs/record/wave-24-sd/fill-ledger.log"
expect_eq "SD7 precondition: the ledger line now carries a dash for its decline" \
  "—" "$(sd_field "$(sd_led "$SD_D7" | tail -1)" declined)"
sd_turn "$SD_TX" u-sd7-2
s7_fire "$SD_D7" "$SD_TX"
expect_eq "SD7: C4 a pre-upgrade declined=— does not stand" "block" "$(sd_decision)"
expect_contains "SD7b: …and the refusal names T7" "not launched: T7" "$STOP_ERR"
unset BIONIC_PRESSURE_RING BIONIC_NOW_EPOCH

# ─────────────────────────────────────────────────────────────────────────────
section "SDR: a stand-down decline carries a reason, and the refusal names hold (wave-24 T8, REQ-4, AC-4.10, AC-4.12)"

# THE DEFECT. `standdown-declined:` captured the name and nothing after it, so
# `standdown-declined: W-SDR` answered the stand-down with no reason in the record, which is the
# one thing the decline exists to leave. And the refusal offered no way to keep a finished agent
# up past the turn: `session-poker.sh hold` (T7) is that way, and the refusal now names it. A hold
# written after this turn's tick answers the stand-down from the roster, never from the words.
# The fixture is what a tick that stood W-SDR down leaves on disk: the tick's stamp, a MET row,
# and the patrol's stop order. The transcript is the tick turn with its task-list refresh done.
SDR_POKER="$(dirname "$HOOK")/session-poker.sh"
sdr_fixture() {  # -> project dir with W-SDR stood down
  local d
  d=$(mkfix)
  printf 'patrol-stamp/v1|at=2026-01-01T00:00:00Z|session=%s|verb=tick\n' "$SID" > "$d/.bionic/tmp/patrol-$SID.state"
  echo done > "$d/landed-sdr.md"
  { roster_header
    roster_row_fixture status=intended session="$SID" name=W-SDR agent_id= deliverable="$d/landed-sdr.md"
  } > "$d/.bionic/tmp/roster-$SID.state"
  ( cd "$d" && env CLAUDE_CODE_SESSION_ID="$SID" bash "$(dirname "$HOOK")/stop-orders.sh" order W-SDR --by patrol >/dev/null 2>&1 )
  printf '%s' "$d"
}
sdr_turn() {  # <file> [assistant text]
  { jq -nc --arg t "bionic-patrol session=${SID:0:8} v=2 — Patrol tick. Run: bash /abs/hooks/session-poker.sh tick" \
      '{type:"user",isMeta:true,isSidechain:false,userType:"external",message:{role:"user",content:$t}}'
    jq -nc '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_tl",name:"TaskList",input:{}}]}}'
    [ -z "${2:-}" ] || jq -nc --arg t "$2" '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[{type:"text",text:$t}]}}'
  } > "$1"
}
require_helpers sdr_fixture sdr_turn

SDR_TX="$(mktemp)"
SDR_D="$(sdr_fixture)"
expect_contains "SDR precondition: the patrol's stop order for W-SDR is on disk" \
  "target=W-SDR" "$(cat "$SDR_D/.bionic/tmp/stop-orders-$SID.state" 2>/dev/null)"
sdr_turn "$SDR_TX"
s7_fire "$SDR_D" "$SDR_TX"
expect_contains "SDR1: the unanswered stand-down is refused" "stand-down unanswered" "$(reason_of)"
expect_contains "SDR1b: AC-4.12 …and the refusal names hold as the way to keep the agent" \
  "session-poker.sh hold W-SDR 'why it stays up'" "$(reason_of)"

sdr_turn "$SDR_TX" "standdown-declined: W-SDR"
s7_fire "$SDR_D" "$SDR_TX"
expect_contains "SDR2: AC-4.10 a name-only decline is refused" "stand-down unanswered" "$(reason_of)"

sdr_turn "$SDR_TX" "standdown-declined: W-SDR —"
s7_fire "$SDR_D" "$SDR_TX"
expect_contains "SDR2b: …as is a name and a dash with no words" "stand-down unanswered" "$(reason_of)"

sdr_turn "$SDR_TX" "standdown-declined: W-SDR is writing its record, one more cadence"
s7_fire "$SDR_D" "$SDR_TX"
expect_eq "SDR3: AC-4.10 the decline with a reason passes" "" "$(sd_decision)"
expect_absent "SDR3b: …and says nothing about a stand-down" "stand-down" "$STOP_OUT$STOP_ERR"

# SDR4: THE HOLD ANSWERS IT. The real verb, after the tick's order, with no decline in the text.
SDR_D4="$(sdr_fixture)"
SDR_CFG="$(mktemp -d)"
SDR_HOLD=$( cd "$SDR_D4" && env CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_CONFIG_DIR="$SDR_CFG" \
  bash "$SDR_POKER" hold W-SDR "kept for a second pass" 2>&1 ); SDR_HOLD_RC=$?
expect_eq "SDR4 precondition: the hold verb took W-SDR (rc 0)" "0" "$SDR_HOLD_RC"
sdr_turn "$SDR_TX"
s7_fire "$SDR_D4" "$SDR_TX"
expect_eq "SDR4: a hold written this turn answers the stand-down" "" "$(sd_decision)"
# …and only one written after the tick: the same held row, the tick stamped after the hold.
printf 'patrol-stamp/v1|at=2099-01-01T00:00:00Z|session=%s|verb=tick\n' "$SID" > "$SDR_D4/.bionic/tmp/patrol-$SID.state"
( cd "$SDR_D4" && env CLAUDE_CODE_SESSION_ID="$SID" bash "$(dirname "$HOOK")/stop-orders.sh" order W-SDR --by patrol >/dev/null 2>&1 )
sed -i.bak 's/|at=[^|]*|/|at=2099-01-01T00:00:01Z|/' "$SDR_D4/.bionic/tmp/stop-orders-$SID.state"
s7_fire "$SDR_D4" "$SDR_TX"
expect_contains "SDR4b: …a hold older than this turn's tick does not answer that tick's order" \
  "stand-down unanswered" "$(reason_of)"
rm -rf "$SDR_CFG"

# ─────────────────────────────────────────────────────────────────────────────
section "DECLINE: a decline stands until the set it answered changes (wave-26 T15, REQ-4, AC-4.6; D16)"

# THE DEFECT (research-R2 §3, P1 and P3). A `fill-declined:` stood until a new row was ready
# or `current:` moved, so a run whose author wanted serial execution wrote a fresh decline after
# every step move over the same ready set. A `standdown-declined:` stood for its own turn only,
# so the next tick ordered the same unchanged agent down again and the turn had to decline it
# again. Now a fill decline stands until the READY SET gains a row it did not answer. A
# stand-down decline is written to the roster as `hold` writes it, so it stands until the
# agent's launch, deliverable or messages move. The tick reads that check (hold_fingerprint).
# The end-to-end proof, through the real tick, is tests/session-poker.test.sh §41 DECLINE-tick.
export BIONIC_PRESSURE_RING="$SD_RING" BIONIC_NOW_EPOCH=1700000000

# D1/D2: the fill decline. Turn one declines ready {T7}. `current:` moves and the ready set does
# not: the second turn, with no text, is not refused.
DC_D="$(sd_fixture)"
DC_P="$DC_D/.bionic/docs/plans/epic-99-fixture/wave-24-sd.plan.md"
sd_turn "$SD_TX" u-dc-1 "fill-declined: T7 waits on the T6 merge"
s7_fire "$DC_D" "$SD_TX"
expect_eq "D1 precondition: the declining turn ends" "" "$(sd_decision)"
sed -i.bak 's/^current: 4$/current: 4b/' "$DC_P"
expect_contains "D1 precondition: current: moved" "current: 4b" "$(cat "$DC_P")"
sd_turn "$SD_TX" u-dc-2
s7_fire "$DC_D" "$SD_TX"
expect_eq "D2: AC-4.6 current: moved over the same ready set — the decline stands, not refused" "" "$(sd_decision)"
expect_contains "D2b: …and the turn's ledger line carries the standing reason" \
  "T7 waits on the T6 merge" "$(sd_field "$(sd_led "$DC_D" | tail -1)" declined)"
# D3: the ready set changes. Refused, naming the row the decline never saw.
printf '| T8 | 4 | build | a row nobody declined | implementor | — | 15m | REQ-x | b.sh | pending | — |\n' >> "$DC_P"
sd_turn "$SD_TX" u-dc-3
s7_fire "$DC_D" "$SD_TX"
expect_eq "D3: AC-4.6 a changed ready set is refused" "block" "$(sd_decision)"
expect_contains "D3b: …naming the new row" "not launched: T8" "$STOP_ERR"
unset BIONIC_PRESSURE_RING BIONIC_NOW_EPOCH

# D4: the stand-down decline is written where hold writes. The tick turn that declines W-SDR with
# a reason ends, and the roster's latest W-SDR row now carries `held=<at> <reason> fp=…`, the
# answer the tick reads on every later tick.
DC_D4="$(sdr_fixture)"
DC_CFG="$(mktemp -d)"
DC_ROWS="$(grep -c '|name=W-SDR|' "$DC_D4/.bionic/tmp/roster-$SID.state")"
sdr_turn "$SDR_TX" "standdown-declined: W-SDR is writing its record, one more cadence"
CLAUDE_CONFIG_DIR="$DC_CFG" s7_fire "$DC_D4" "$SDR_TX"
expect_eq "D4 precondition: the declining tick turn ends" "" "$(sd_decision)"
DC_ROW="$(grep -F '|name=W-SDR|' "$DC_D4/.bionic/tmp/roster-$SID.state" | tail -1)"
expect_regex "D4: AC-4.6 the decline is written as a hold, with its reason and the fingerprint" \
  '\|held=[0-9TZ:-]+ is writing its record, one more cadence fp=[^|]+\|' "$DC_ROW"
expect_eq "D4b: …one row added" "$((DC_ROWS + 1))" "$(grep -c '|name=W-SDR|' "$DC_D4/.bionic/tmp/roster-$SID.state")"
# D5: the re-entered Stop of the same turn writes no second hold.
CLAUDE_CONFIG_DIR="$DC_CFG" s7_fire "$DC_D4" "$SDR_TX"
expect_eq "D5 precondition: the same turn's Stop again ends" "" "$(sd_decision)"
expect_eq "D5: …and adds no second held row" "$((DC_ROWS + 1))" "$(grep -c '|name=W-SDR|' "$DC_D4/.bionic/tmp/roster-$SID.state")"
rm -rf "$DC_CFG"

# ─────────────────────────────────────────────────────────────────────────────
section "FO: the stop wall's occupancy is the tick's — a read-only row holds no writer slot (wave-24 T13, D11)"

# THE THIRD READER ON THE OLD NUMBER (A-T10.3, A-orch-32). The dispatch wall and the tick count
# open rows through `budget_open_writers` (payload/scripts/lib/roster.sh), which leaves a
# read-only role out. The stop wall's `FILL_OPEN` counted every open row, so with writers=1 and
# a researcher open it saw no free slot, while the tick printed FILL for the same ready row.
# One fixture, two rosters: a researcher open (a free writer slot) and a writer open (none).
fo_fixture() {  # <subagent_type of the one open row> -> project dir; writers=1, T7 pending
  local d
  d=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$d/.bionic/tmp" "$d/.bionic/docs/plans/epic-99-fixture"
  { printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
    printf 'parallel-budget: writers=1 suites=2 worktrees=8 test_jobs=8 source=probe\n'
    printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: 4\napproved-by: fixture 2026-10-04T00:00Z "approved"\n\n- Step 4: in progress\n\n'
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | status | worktree |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T7 | 4 | build | the ready row | implementor | — | 15m | REQ-x | a.sh | pending | — |\n'
  } > "$d/.bionic/docs/plans/epic-99-fixture/wave-24-fo.plan.md"
  bound_marker "$d" "$SID" "$d/.bionic/docs/plans/epic-99-fixture/wave-24-fo.plan.md"
  roster_header > "$d/.bionic/tmp/roster-$SID.state"
  roster_row_fixture status=intended session="$SID" name=FO-ONE agent_id=aFO00000000000001 \
    deliverable= "subagent_type=$1" >> "$d/.bionic/tmp/roster-$SID.state"
  printf '%s' "$d"
}
fo_tick() {  # <project> -> the real tick's output
  ( cd "$1" && env CLAUDE_CODE_SESSION_ID="$SID" BIONIC_PROBE_FREE_MB=8192 \
      BIONIC_PROBE_LOAD_1M=1.0 bash "${BIONIC_HOOKS_DIR}/session-poker.sh" tick 2>/dev/null )
}
require_helpers fo_fixture fo_tick

FO_RING="$(mktemp)"; printf '1700000000|80|0|1.0|8\n' > "$FO_RING"
export BIONIC_PRESSURE_RING="$FO_RING" BIONIC_NOW_EPOCH=1700000000
FO_TX="$(mktemp)"

# FO1: a researcher open, T7 ready, writers=1 — the tick fills, and the stop wall demands it.
FO_D="$(fo_fixture bionic:researcher)"
expect_contains "FO1a: the tick, counting writers only, fills T7 past the open researcher" \
  "poker: FILL T7" "$(fo_tick "$FO_D")"
sd_turn "$FO_TX" u-fo-1
s7_fire "$FO_D" "$FO_TX"
expect_contains "FO1b: …and the stop wall agrees: the free writer slot is a fillable gap" \
  "Fillable gap at turn end" "$(reason_of)"
expect_contains "FO1c: …naming the ready row" "T7" "$(reason_of)"

# FO2: the same fixture with a WRITER open — no slot is free, so neither the tick nor the wall
# asks for a fill. The control that FO1 cannot pass on a wall that refuses every turn.
FO_DW="$(fo_fixture implementor)"
expect_contains "FO2a: with a writer open the tick reports the budget full" \
  "the budget is full" "$(fo_tick "$FO_DW")"
sd_turn "$FO_TX" u-fo-2
s7_fire "$FO_DW" "$FO_TX"
expect_absent "FO2b: …and the stop wall asks for no fill" "Fillable gap" "$(reason_of)$STOP_ERR"
unset BIONIC_PRESSURE_RING BIONIC_NOW_EPOCH

# ============================================================
section "FILL-WALL: the wall's set is the tick's — a ready read-only row refuses the turn once, a waiting row is never demanded (wave-26 T13; REQ-6 AC-6.7; D9)"
# ============================================================
#
# ONE READY SET, READ-ONLY ROWS INCLUDED. writers=1 and a writer open, so no writer slot is free.
# T1 is a ready build row the closed gap holds back; T5 is a ready verify row, which takes no
# writer slot and is therefore owed whatever the gap; T6 waits on T1, which has not landed. The
# tick offers T5 alone, and the wall refuses a turn that left it undispatched — naming T5, and
# never T6. The differential lands T5: nothing ready is left that a slot could take, so the same
# wall asks for nothing.
fw_fixture() {  # <status of T5> -> project dir
  local d
  d=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$d/.bionic/tmp" "$d/.bionic/docs/plans/epic-99-fixture"
  { printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
    printf 'parallel-budget: writers=1 suites=2 worktrees=8 test_jobs=8 source=probe\n'
    printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: 4\n'
    printf 'approved-by: fixture 2026-10-04T00:00Z "approved"\n\n- Step 4: in progress\n\n'
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | status | worktree |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | a ready writer, no slot free | implementor | — | 15m | REQ-x | a.sh | pending | — |\n'
    printf '| T5 | 5 | verify | the ready read-only row | auditor | — | 15m | REQ-x | — | %s | — |\n' "$1"
    printf '| T6 | 5 | verify | waits on T1 | auditor | T1 | 15m | REQ-x | — | pending | — |\n'
  } > "$d/.bionic/docs/plans/epic-99-fixture/wave-26-fw.plan.md"
  bound_marker "$d" "$SID" "$d/.bionic/docs/plans/epic-99-fixture/wave-26-fw.plan.md"
  roster_header > "$d/.bionic/tmp/roster-$SID.state"
  roster_row_fixture status=intended session="$SID" name=FW-ONE agent_id=aFW00000000000001 \
    deliverable= "subagent_type=implementor" >> "$d/.bionic/tmp/roster-$SID.state"
  printf '%s' "$d"
}
require_helpers fw_fixture

FW_RING="$(mktemp)"; printf '1700000000|80|0|1.0|8\n' > "$FW_RING"
export BIONIC_PRESSURE_RING="$FW_RING" BIONIC_NOW_EPOCH=1700000000
FW_TX="$(mktemp)"

FW_D="$(fw_fixture pending)"
FW_TICK="$(fo_tick "$FW_D")"
expect_contains "FW0: the tick offers the read-only row with no writer slot free" "poker: FILL T5" "$FW_TICK"
sd_turn "$FW_TX" u-fw-1
s7_fire "$FW_D" "$FW_TX"
expect_contains "FW1: AC-6.7 a ready read-only row left undispatched refuses the turn end" \
  "Fillable gap at turn end" "$(reason_of)"
expect_contains "FW1b: …naming it" "T5" "$(reason_of)"
expect_absent "FW1c: …and never the row that waits on an unlanded read" "T6" "$(reason_of)"
expect_absent "FW1d: …nor the writer the closed gap holds back" "T1" "$(reason_of)"
expect_contains "FW1e: the refusal asks for the dispatch" "Dispatch each named row" "$(reason_of)"
expect_absent "FW1f: …and no longer for a hand edit of the row: the launch recorder ledgers it" \
  "ledger it active" "$(reason_of)"

FW_DL="$(fw_fixture landed)"
sd_turn "$FW_TX" u-fw-2
s7_fire "$FW_DL" "$FW_TX"
expect_absent "FW2: the differential — with T5 landed, only a waiting row and a slotless writer remain, and nothing is demanded" \
  "Fillable gap" "$(reason_of)$STOP_ERR"
expect_contains "FW2b: …while the tick on that fixture still names the waiting row" \
  "poker: WAIT T6 — waits for T1 (pending)" "$(fo_tick "$FW_DL")"
unset BIONIC_PRESSURE_RING BIONIC_NOW_EPOCH


finish
