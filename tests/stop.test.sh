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
    printf 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=user\n'
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
section "DECLINE-VERB: a decline is recorded by a verb, and the wall reads it there (wave-27 T34; REQ-15 AC-15.1, AC-15.5; D24)"

# THE DEFECT (design ledger Δ9). The fill wall read its answer out of the reply, so the
# orchestrator answered it with a `fill-declined:` line the user read on every turn, for hours,
# and that said nothing to a person. `session-poker.sh decline <id>[,<id>] '<reason>'` records
# the decline on disk: one line in the run's fill ledger, the line the reply form's turn leaves
# there, so `fill_standing_decline` reads both forms by one rule. The turn that recorded it
# carries no decline in its text and ends; a row it did not name is still owed; the rows it
# named stay answered.
DV_POKER="$(dirname "$HOOK")/session-poker.sh"
dv_fixture() {  # -> project dir; T7 and T9 pending and ready, T10 active, writers=8, current: 4
  local d p
  d="$(sd_fixture)"
  p="$d/.bionic/docs/plans/epic-99-fixture/wave-24-sd.plan.md"
  printf '| T9 | 4 | build | a second row behind the merge | implementor | — | 15m | REQ-x | c.sh | pending | — |\n' >> "$p"
  printf '| T10 | 4 | build | a row already running | implementor | — | 15m | REQ-x | d.sh | active | 24-T10 |\n' >> "$p"
  printf '%s' "$d"
}
dv_poke() {  # <project> <verb args...> -> sets DV_OUT, DV_RC
  local d="$1"; shift
  DV_OUT=$( cd "$d" && env CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR="" \
    BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_SWAP_PCT=0 \
    bash "$DV_POKER" "$@" 2>&1 ); DV_RC=$?
}
dv_lines() { sd_led "$1" | /usr/bin/grep -c '^fill-ledger/v1|' || true; }
require_helpers dv_fixture dv_poke dv_lines
export BIONIC_PRESSURE_RING="$SD_RING" BIONIC_NOW_EPOCH=1700000000

DV_D="$(dv_fixture)"
DV_P="$DV_D/.bionic/docs/plans/epic-99-fixture/wave-24-sd.plan.md"
dv_poke "$DV_D" decline T7,T9 'the machine is saturated'
expect_eq "DV0 precondition: the verb records the decline (exit 0)" "0" "$DV_RC"
DV_LINE="$(sd_led "$DV_D" | tail -1)"
expect_eq "DV1 AC-15.5 the run's fill ledger gains the decline's line, naming its ids" "T7,T9" "$(sd_field "$DV_LINE" named)"
expect_eq "DV1b …its reason" "the machine is saturated" "$(sd_field "$DV_LINE" declined)"
expect_regex "DV1c …and its time" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$(sd_field "$DV_LINE" at)"
expect_eq "DV1d …for this session" "$SID" "$(sd_field "$DV_LINE" session)"
sd_turn "$SD_TX" u-dv-1
s7_fire "$DV_D" "$SD_TX"
expect_eq "DV2 AC-15.1 the turn ends with no decline line in its reply, and the wall does not refuse it" "" "$(sd_decision)"
expect_contains "DV2b …and that turn's ledger line carries the recorded reason" \
  "the machine is saturated" "$(sd_field "$(sd_led "$DV_D" | tail -1)" declined)"
sd_turn "$SD_TX" u-dv-2
s7_fire "$DV_D" "$SD_TX"
expect_eq "DV2c …and it stands on the next turn too" "" "$(sd_decision)"
printf '| T11 | 4 | build | a row the decline never named | implementor | — | 15m | REQ-x | e.sh | pending | — |\n' >> "$DV_P"
sd_turn "$SD_TX" u-dv-3
s7_fire "$DV_D" "$SD_TX"
expect_eq "DV3 a row the decline did not name is ready: the silent turn is refused" "block" "$(sd_decision)"
DV_HEAD="$(printf '%s\n' "$STOP_ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "DV3b …naming T11" "not launched: T11" "$DV_HEAD"
expect_absent "DV3c …and not T7 or T9, which the decline named" "T7" "$DV_HEAD"
expect_absent "DV3d …nor T9" "T9" "$DV_HEAD"
expect_contains "DV3e the refusal names the verb, with the rows it owes" "session-poker.sh decline T11 '" "$(reason_of)"
expect_absent "DV3f …and asks for no decline line in the reply" 'write "fill-declined:' "$(reason_of)"
# THE REFUSALS. Each names what it refused, and writes nothing.
DV_N="$(dv_lines "$DV_D")"
expect_ne "DV4 precondition: the ledger has lines to count" "0" "$DV_N"
dv_poke "$DV_D" decline T8 'no such row'
expect_eq "DV4b an id that is no plan row is refused (exit 1)" "1" "$DV_RC"
expect_contains "DV4c …saying which" "T8" "$DV_OUT"
dv_poke "$DV_D" decline T10 'it is running'
expect_eq "DV4d a plan row that is not ready is refused (exit 1)" "1" "$DV_RC"
expect_contains "DV4e …saying which" "T10" "$DV_OUT"
dv_poke "$DV_D" decline T11 '   '
expect_eq "DV4f an empty reason is refused (exit 2)" "2" "$DV_RC"
dv_poke "$DV_D" decline 'the machine is saturated'
expect_eq "DV4g no ids is refused: there is no decline-everything form (exit 2)" "2" "$DV_RC"
dv_poke "$DV_D" decline ',' 'the machine is saturated'
expect_eq "DV4h ids that are only separators are refused (exit 2)" "2" "$DV_RC"
expect_eq "DV4i …and no refusal wrote a ledger line" "$DV_N" "$(dv_lines "$DV_D")"
# A SECOND DECLINE KEEPS THE FIRST'S ROWS. Declining T11 by itself leaves T7 and T9 answered.
dv_poke "$DV_D" decline T11 'T11 waits for the same merge'
expect_eq "DV5 precondition: the second decline is recorded (exit 0)" "0" "$DV_RC"
expect_eq "DV5b …and it is one more line" "$((DV_N + 1))" "$(dv_lines "$DV_D")"
sd_turn "$SD_TX" u-dv-4
s7_fire "$DV_D" "$SD_TX"
expect_eq "DV5c the rows the first decline named stay answered beside the second's" "" "$(sd_decision)"
# THE TWO FORMS GIVE ONE ANSWER. One world declines T7 and T9 in its reply, the other by the
# verb; a row neither named becomes ready in both; the wall owes the same rows in each.
dv_owed() {  # <project> -> the first refusal line's not-launched rows
  printf '%s\n' "$STOP_ERR" | /usr/bin/grep -m1 '^bionic: ' | sed -n 's/.*not launched:\(.*\) (.*/\1/p'
}
DV_TA="$(dv_fixture)"; DV_TB="$(dv_fixture)"
sd_turn "$SD_TX" u-dvt-1 "fill-declined: the machine is saturated"
s7_fire "$DV_TA" "$SD_TX"
expect_eq "DV6 precondition: the reply form's turn ends" "" "$(sd_decision)"
dv_poke "$DV_TB" decline T7,T9 'the machine is saturated'
for _dv_t in "$DV_TA" "$DV_TB"; do
  printf '| T11 | 4 | build | a row neither form named | implementor | — | 15m | REQ-x | e.sh | pending | — |\n' \
    >> "$_dv_t/.bionic/docs/plans/epic-99-fixture/wave-24-sd.plan.md"
done
sd_turn "$SD_TX" u-dvt-2
s7_fire "$DV_TA" "$SD_TX"; DV_OWED_A="$(dv_owed)"
s7_fire "$DV_TB" "$SD_TX"; DV_OWED_B="$(dv_owed)"
expect_eq "DV6b precondition: the reply form owes T11" " T11" "$DV_OWED_A"
expect_eq "DV6c the verb form owes the same rows as the reply form" "$DV_OWED_A" "$DV_OWED_B"
unset BIONIC_PRESSURE_RING BIONIC_NOW_EPOCH

# ─────────────────────────────────────────────────────────────────────────────
section "DECLINE-TEXT: a run in flight that still writes the old line is not refused for it (wave-27 T34; REQ-15 AC-15.3; D24)"

# The reply form is still read, row for row as §SD and §DECLINE pin it: a turn whose reply holds
# `fill-declined: <reason>` and ran no verb ends, and its reason stands; a `standdown-declined:`
# line is still kept as a hold (§DECLINE D4).
export BIONIC_PRESSURE_RING="$SD_RING" BIONIC_NOW_EPOCH=1700000000
DT_D="$(dv_fixture)"
sd_turn "$SD_TX" u-dt-1 "fill-declined: T7 and T9 wait on the T6 merge"
s7_fire "$DT_D" "$SD_TX"
expect_eq "DT1 AC-15.3 a reply carrying the old line, and no verb, is admitted" "" "$(sd_decision)"
expect_eq "DT1b …its line records the reason against the rows it saw" \
  "T7 and T9 wait on the T6 merge" "$(sd_field "$(sd_led "$DT_D" | tail -1)" declined)"
sd_turn "$SD_TX" u-dt-2
s7_fire "$DT_D" "$SD_TX"
expect_eq "DT2 …and it stands on the next turn, as before" "" "$(sd_decision)"
DT_D2="$(dv_fixture)"
sd_turn "$SD_TX" u-dt-3
s7_fire "$DT_D2" "$SD_TX"
expect_eq "DT3 control: the same fixture with neither form is refused" "block" "$(sd_decision)"
unset BIONIC_PRESSURE_RING BIONIC_NOW_EPOCH

# ─────────────────────────────────────────────────────────────────────────────
section "BUDGET-USER: a user's writer cap is a fact in the header the wall already reads (wave-27 T34; REQ-15 AC-15.4; D24)"

# `session-poker.sh budget writers=<n> '<reply>'` rewrites the header's `writers=` with
# `source=user` and adds `budget-override:` (tests/session-poker.test.sh §BUDGET-USER drives the
# verb). The wall reads the header it always read: with the user's cap reached it asks for
# nothing, and no decline is recorded or written. The control is the probe's header over the same
# roster, which owes the ready row.
export BIONIC_PRESSURE_RING="$SD_RING" BIONIC_NOW_EPOCH=1700000000
bu_fixture() {  # <budget line> -> project dir; three writers open, T7 ready
  local d p
  d="$(sd_fixture)"
  p="$d/.bionic/docs/plans/epic-99-fixture/wave-24-sd.plan.md"
  BU_B="$1" awk '/^parallel-budget:/ { print ENVIRON["BU_B"]; next } { print }' "$p" > "$p.tmp" && mv "$p.tmp" "$p"
  for _bu_n in 1 2 3; do
    roster_row_fixture status=intended session="$SID" name="BU-$_bu_n" agent_id="aBU0000000000000$_bu_n" \
      deliverable= subagent_type=implementor >> "$d/.bionic/tmp/roster-$SID.state"
  done
  printf '%s' "$d"
}
require_helpers bu_fixture
BU_C="$(bu_fixture 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=user')"
sd_turn "$SD_TX" u-bu-1
s7_fire "$BU_C" "$SD_TX"
expect_eq "BU1 control: a person's eight writers with three open owe the ready row" "block" "$(sd_decision)"
BU_D="$(bu_fixture "$(printf 'parallel-budget: writers=3 suites=2 worktrees=8 test_jobs=8 source=user\nbudget-override: Dana Fixture 2026-10-04 derived=8 chosen=3')")"
expect_contains "BU2 precondition: the header carries the user's cap" "writers=3 suites=2 worktrees=8 test_jobs=8 source=user" \
  "$(cat "$BU_D/.bionic/docs/plans/epic-99-fixture/wave-24-sd.plan.md")"
s7_fire "$BU_D" "$SD_TX"
expect_eq "BU2b AC-15.4 the user's cap of three reached: the wall asks for nothing" "" "$(sd_decision)"
BU_LINE="$(sd_led "$BU_D" | tail -1)"
expect_eq "BU2c …the turn's ledger line reads the cap" "3" "$(sd_field "$BU_LINE" ceiling)"
expect_eq "BU2d …and records no decline" "" "$(sd_field "$BU_LINE" declined)"

# §NOBUDGET — NO PLAN OWES THE LINE, AND A PROBE'S NUMBER CAPS NOTHING (wave-28 T9; D15, REQ-2
# AC-2.9). Until wave-28 a live ledger whose plan carried no readable `writers=` was refused once
# ("Fill budget unreadable", naming Step 0's key), and a probe-written `writers=8` sized the fill
# the way BU1's person's line does. The same roster and the same ready row as BU1: with no line,
# and with the probe's line, the wall refuses nothing on the budget. BU1 is the paired control
# (the one word `source=user` makes it block). fails-when: a plan with no line is refused.
BU_N="$(bu_fixture 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=user')"
/usr/bin/grep -v '^parallel-budget:' "$BU_N/.bionic/docs/plans/epic-99-fixture/wave-24-sd.plan.md" > "$BU_N/p.tmp" \
  && mv "$BU_N/p.tmp" "$BU_N/.bionic/docs/plans/epic-99-fixture/wave-24-sd.plan.md"
expect_absent "§NOBUDGET.0 meta: the live plan carries no parallel-budget: line" "parallel-budget" \
  "$(cat "$BU_N/.bionic/docs/plans/epic-99-fixture/wave-24-sd.plan.md")"
expect_contains "§NOBUDGET.0b meta: …and is still the live fixture (current: 4)" "current: 4" \
  "$(cat "$BU_N/.bionic/docs/plans/epic-99-fixture/wave-24-sd.plan.md")"
s7_fire "$BU_N" "$SD_TX"
expect_eq "§NOBUDGET.1 a live plan with no parallel-budget: line is not refused" "" "$(sd_decision)"
BU_P="$(bu_fixture 'parallel-budget: writers=8 suites=2 worktrees=8 test_jobs=8 source=probe')"
s7_fire "$BU_P" "$SD_TX"
expect_eq "§NOBUDGET.2 the probe's eight with three open: its number sizes no fill, nothing is refused" "" "$(sd_decision)"
unset BIONIC_PRESSURE_RING BIONIC_NOW_EPOCH

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
    printf 'parallel-budget: writers=1 suites=2 worktrees=8 test_jobs=8 source=user\n'
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
    printf 'parallel-budget: writers=1 suites=2 worktrees=8 test_jobs=8 source=user\n'
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
# THE ROW LIST, NOT THE TEXT (wave-27 T67; A-orch-140): the refusal prints the hook's absolute
# path, which may hold any id (this row's own tree is 27-T67), so a must-not reads the ids the
# printed decline names, as a word, the shape tests/patrol-duties-gate.test.sh uses.
fw_rows() {  # -> the ids the refusal's printed decline names, space-joined
  reason_of | /usr/bin/grep -o "session-poker\.sh'\{0,1\} decline [A-Za-z0-9_.,-]*" | head -1 \
    | sed 's/.* decline //' | tr ',' ' '
}
fw_rows_unnamed() {  # <label> <id the refusal's row list must not hold>
  local rows; rows="$(fw_rows)"
  if [ -z "$rows" ]; then no "$1" "the refusal names no decline row list: $(reason_of)"; return; fi
  case " $rows " in *" $2 "*) no "$1" "the row list <$rows> names <$2>"; return ;; esac
  ok "$1"
}
require_helpers fw_rows fw_rows_unnamed
expect_eq "FW1c0 precondition: the refusal's row list is read, and it is T5" "T5" "$(fw_rows)"
fw_rows_unnamed "FW1c: …and never the row that waits on an unlanded read" "T6"
fw_rows_unnamed "FW1d: …nor the writer the closed gap holds back" "T1"
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


# ─────────────────────────────────────────────────────────────────────────────
section "FLOOR-WALL: the turn-end wall never demands an integrate row whose floor proof the change has outrun (wave-26 T64; REQ-3 AC-3.4)"
# ─────────────────────────────────────────────────────────────────────────────
#
# THE WALL'S READY SET IS THE TICK'S (lib/units.sh), so the rule that integrate's `proof:floor`
# stands only while proof_state answers covered or bounded reaches the turn end too. The fixture
# is a git repository on `wave/99-fl` with no `impact-command:`, so any change past the floor
# proof is unbounded; writers=1 and no writer open, so a ready integrate row is a fillable gap.
# Each proof line is written by lib/proof.sh's own writer pair at the head the checkout is at.
# A new file lands past the proof: the wall demands nothing, while the tick says why the row
# waits. The differential records a floor proof at the new head: the same wall refuses the turn,
# naming T3.
# THE INTEGRATE ROW'S proof:review IS THE JUDGE'S (wave-27 T14; T43, A-orch-82). It is met only
# when lib/proof.sh `facts_state` answers covered. The tick writes that answer into its digest
# (`facts_state=`), and the wall hands it to the same ready set. So the plan declares a rigor and
# a scale the dealing knows (`tested`, `wave`: the floor, and the critic's three piece reads and
# two whole reads) and a real base-sha:. The readings are written at the new head by the same
# writer pair. With one reading missing (FL1b), neither the tick nor the wall offers integrate.
fl_git() { git -C "$1" -c user.name=fixture -c user.email=fixture@example.invalid "${@:2}"; }
fl_prove() {  # <project> <kind> [<question> <reader> <result> <scope>] -> a proof line at the checkout's head, by proof_line + proof_add_line
  local p="$1/.bionic/docs/plans/epic-99-fixture/wave-99-fl.plan.md" out
  out="$( . "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/proof.sh" >/dev/null 2>&1
          proof_add_line "$p" "$(proof_line "$2" "$(fl_git "$1" rev-parse HEAD)" 2026-10-04T12:00:00Z "record/fl/$2${3:+-$3-${6:-}}.txt" "${@:3}")")" \
    && printf '%s\n' "$out" > "$p"
}
fl_read() {  # <project> <question> <scope> -> a passing reading by the critic at the checkout's head
  fl_prove "$1" review "$2" w-crit pass "$3"
}
fl_fixture() {  # -> project dir: proofs at the base, then a new file past them
  local d
  d=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$d/.bionic/tmp" "$d/.bionic/docs/plans/epic-99-fixture"
  fl_git "$d" init -q 2>/dev/null; fl_git "$d" checkout -q -b wave/99-fl 2>/dev/null
  printf '.bionic/\n' > "$d/.gitignore"; fl_git "$d" add .gitignore; fl_git "$d" commit -qm base
  { printf -- '---\ngoverning-skill: superpowers:writing-plans\nrigor: tested\nscale: wave\nbase-sha: %s\n' "$(fl_git "$d" rev-parse HEAD)"
    printf 'parallel-budget: writers=1 suites=2 worktrees=8 test_jobs=8 source=user\n'
    printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: 8\nworking-branch: wave/99-fl\n'
    printf 'approved-by: fixture 2026-10-04T00:00Z "approved"\n\n- Step 8: in progress\n\n'
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | status | reads |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | the build | implementor | — | 15m | REQ-x | a.sh | landed |  |\n'
    printf '| T5 | 5 | verify | the floor | test-runner | — | 15m | REQ-x | .bionic/docs/record/fl/floor.txt | landed |  |\n'
    printf '| T2 | 6 | review | the review | critic | — | 15m | REQ-x | .bionic/docs/record/fl/review.md | landed |  |\n'
    printf '| T3 | 8 | integrate | merge to main | implementor | — | 15m | REQ-x | — | pending |  |\n'
  } > "$d/.bionic/docs/plans/epic-99-fixture/wave-99-fl.plan.md"
  fl_prove "$d" floor; fl_prove "$d" review
  mkdir -p "$d/newdir"; printf 'new\n' > "$d/newdir/x.sh"; fl_git "$d" add newdir; fl_git "$d" commit -qm 'a new file'
  bound_marker "$d" "$SID" "$d/.bionic/docs/plans/epic-99-fixture/wave-99-fl.plan.md"
  roster_header > "$d/.bionic/tmp/roster-$SID.state"
  printf '%s' "$d"
}
require_helpers fl_fixture

FL_RING="$(mktemp)"; printf '1700000000|80|0|1.0|8\n' > "$FL_RING"
export BIONIC_PRESSURE_RING="$FL_RING" BIONIC_NOW_EPOCH=1700000000
FL_TX="$(mktemp)"
FL_D="$(fl_fixture)"
expect_contains "FL0: the tick on the fixture says integrate waits for a full run (the ready set's reason)" \
  "poker: WAIT T3 — proof:floor: the head moved past the floor proof at" "$(fo_tick "$FL_D")"
sd_turn "$FL_TX" u-fl-1
s7_fire "$FL_D" "$FL_TX"
expect_absent "FL1: AC-3.4 the turn-end wall does not demand integrate while the change past the floor proof is unbounded" \
  "Fillable gap" "$(reason_of)$STOP_ERR"
fl_prove "$FL_D" floor
fl_read "$FL_D" adversarial piece; fl_read "$FL_D" structure piece
fl_read "$FL_D" adversarial whole; fl_read "$FL_D" structure whole
rm -f "$FL_D/.bionic/tmp/tick-digest-$SID.state"
FL_OUT="$(fo_tick "$FL_D")"
expect_contains "FL1b precondition: a floor proof at the head and the evidence reading missing: integrate waits on the judge" \
  "poker: WAIT T3 — proof:review: the facts the run owes do not hold (facts_state): review evidence" "$FL_OUT"
expect_eq "FL1b0 precondition: the tick wrote what it judged into its digest" "yes" \
  "$(/usr/bin/grep -q '^facts_state=review evidence' "$FL_D/.bionic/tmp/tick-digest-$SID.state" && echo yes || echo no)"
s7_transcript "$FL_TX" "$FL_OUT"
s7_fire "$FL_D" "$FL_TX"
expect_absent "FL1b: with a reading missing the tick does not offer T3 and the wall does not demand it: they agree" \
  "Fillable gap" "$(reason_of)$STOP_ERR"
fl_read "$FL_D" evidence piece
rm -f "$FL_D/.bionic/tmp/tick-digest-$SID.state"
FL_OUT="$(fo_tick "$FL_D")"
expect_contains "FL2 precondition: with a floor proof at the head and every owed reading held, the tick offers integrate" "poker: FILL T3" "$FL_OUT"
s7_transcript "$FL_TX" "$FL_OUT"
s7_fire "$FL_D" "$FL_TX"
expect_contains "FL2: the differential — on the tick's turn the same wall refuses the turn that left the merge undispatched" \
  "Fillable gap at turn end" "$(reason_of)"
expect_contains "FL2b: …naming T3" "T3" "$(reason_of)"
# Off a tick's turn the wall has no digest of this turn, hands no facts state, and integrate waits.
sd_turn "$FL_TX" u-fl-2c
s7_fire "$FL_D" "$FL_TX"
expect_absent "FL2c: …on a turn that is not the tick's, the wall hands no facts state and demands no integrate" \
  "Fillable gap" "$(reason_of)$STOP_ERR"
unset BIONIC_PRESSURE_RING BIONIC_NOW_EPOCH


# ─────────────────────────────────────────────────────────────────────────────
section "LS: the turn-end wall records the launches the plan lacks, and refuses on one it cannot (wave-26 T32, D4; review-3 F2)"

# The launch recorder starts `session-poker.sh launch-sync` and does not wait for it, so its
# failure has to surface somewhere a model reads. The turn-end wall runs the same transaction:
# a launch it records is silent, and one it cannot record refuses the turn once, naming the
# commands to run by hand. The fixture is a plan the real commit gate admits (the shape
# tests/execution-recorder.test.sh §17 builds), because the transaction dry-commits through it.
ls_world() {  # -> project dir; T3 and T4 pending build rows, T2 active, the session bound
  local d p
  d=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$d/.bionic/tmp" "$d/.bionic/docs/plans/epic-99-fixture" "$d/.bionic/docs/specs/epic-99-fixture"
  git -C "$d" init -q 2>/dev/null
  git -C "$d" config user.email t@example.com; git -C "$d" config user.name T
  echo seed > "$d/README.md"; git -C "$d" add README.md; git -C "$d" commit -qm seed 2>/dev/null
  printf '# requirements\n' > "$d/.bionic/docs/specs/epic-99-fixture/wave-01-fixture.requirements.md"
  printf '# spec\n' > "$d/.bionic/docs/specs/epic-99-fixture/wave-01-fixture.spec.md"
  p="$d/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: bugfix\n'
    printf 'rigor: audited\nscale: wave\nmulti_agent: true\nuse_worktree: true\nhas_ui: false\n'
    printf 'walk: exempt\ndeploy_target: n/a\n'
    printf 'parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=user\n---\n\n'
    printf '# fixture wave\n\n## SDLC State\n\ncurrent: 4\n'
    printf 'approved-by: fixture 2026-09-23T00:00Z "approved"\n\n'
    printf -- '- Step 1: requirements: specs/epic-99-fixture/wave-01-fixture.requirements.md\n'
    printf -- '- Step 2: spec: specs/epic-99-fixture/wave-01-fixture.spec.md\n'
    printf -- '- Step 3: plan: plans/epic-99-fixture/wave-01-fixture.plan.md\n'
    printf -- '- Step 4: opened\n  worktree: .worktrees/01-fixture\n  base-sha: abc1234\n  branch: wave/01-fixture\n'
    printf -- '- T1: landed at record/T1.md\n- T2: dispatched to w1-T2\n'
    printf -- '- T3: pending dispatch\n- T4: pending dispatch\n\n'
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | the first build | implementor | — | 30 | REQ-1 | a.sh | — | — | landed |\n'
    printf '| T2 | 4 | build | the second build | w1-T2 | — | 30 | REQ-1 | b.sh | 01-T2 | abc1234 | active |\n'
    printf '| T3 | 4 | build | the third build | — | — | 30 | REQ-1 | c.sh | — | — | pending |\n'
    printf '| T4 | 4 | build | the fourth build | — | — | 30 | REQ-1 | d.sh | — | — | pending |\n\n'
    printf '## Verification Matrix\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
    printf '| AC-1.1 | T2 | pending | — | — |\n\nAC-1.1:\n  provenance: fixture\n  fails-when: the fixture is wrong\n'
    printf '\n## Dispatch ledger\n\n| id | agent | dispatched | expected | artifact | landed | notes |\n'
    printf '|---|---|---|---|---|---|---|\n| T2 | implementor (w1-T2) | 2026-10-04T03:00Z | 30 min | record/T2.md | — | batch 1 |\n'
  } > "$p"
  ( cd "$d" && git add -f "$p" .bionic/docs/specs && git commit -qm plan ) >/dev/null 2>&1
  bound_marker "$d" "$SID" "$p"
  { roster_header
    roster_row_fixture status=confirmed session="$SID" name=w1-T2 agent_id=aLS2000000000001 \
      launched_at=2026-10-04T03:00:00Z subagent_type=bionic:implementor tool_use_id=toolu_LS2
  } > "$d/.bionic/tmp/roster-$SID.state"
  printf '%s' "$d"
}
ls_plan() { printf '%s/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md' "$1"; }
ls_launch() {  # <project> <name> [tree basename] -> a confirmed launch, and its tree record when named
  roster_row_fixture status=confirmed session="$SID" name="$2" agent_id="aLS$(printf '%s' "$2" | tr -dc 'A-Za-z0-9')000" \
    launched_at=2026-10-04T03:37:00Z subagent_type=bionic:implementor deliverable=.bionic/docs/record/w1/r.md \
    duration='45 minutes' tool_use_id="toolu_LS$2" >> "$1/.bionic/tmp/roster-$SID.state"
  [ -n "${3:-}" ] || return 0
  # A real linked worktree, its path as git lists it: the record counts nothing else (wave-26 T40).
  local t; t="$(cd "$1" && pwd -P)/.worktrees/$3"
  git -C "$1" worktree add -q -b "wt/$3" "$t" >/dev/null 2>&1
  printf 'workspace/v1|session=%s|name=%s|path=%s|branch=wt/%s|base=0123456789abcdef0123456789abcdef01234567|plan=%s|at=2026-10-04T03:36:00Z\n' \
    "$SID" "$2" "$t" "$3" "$(ls_plan "$1")" >> "$1/.bionic/tmp/workspaces-$SID.state"
}
require_helpers ls_world ls_plan ls_launch
LS_TX="$(mktemp)"

# LS1: a launch the detached call never recorded is recorded by the turn-end wall, silently.
LS_D="$(ls_world)"
ls_launch "$LS_D" w1-T3 01-T3
expect_contains "LS1 precondition: row T3 starts pending" "| c.sh | — | — | pending |" "$(cat "$(ls_plan "$LS_D")")"
sd_turn "$LS_TX" u-ls-1 "fill-declined: T4 waits on the T3 merge"
s7_fire "$LS_D" "$LS_TX"
expect_contains "LS1: the turn-end wall records the launch: row T3 active in its tree" \
  "| w1-T3 | — | 30 | REQ-1 | c.sh | .worktrees/01-T3 | 01234567 | active |" "$(cat "$(ls_plan "$LS_D")")"
expect_contains "LS1b: …with its ledger line" "| T3 | implementor (w1-T3) |" "$(cat "$(ls_plan "$LS_D")")"
expect_absent "LS1c: …and says nothing of it" "NOT-RECORDED" "$STOP_OUT$STOP_ERR"

# LS2: a launch it cannot record (a build row with no tree) refuses the turn, once, naming it.
ls_launch "$LS_D" w1-T4
sd_turn "$LS_TX" u-ls-2
s7_fire "$LS_D" "$LS_TX"
expect_eq "LS2: a launch the plan cannot record refuses the turn" "block" "$(sd_decision)"
expect_contains "LS2b: …naming the launch the transaction printed" "poker: NOT-RECORDED T4 w1-T4" "$(reason_of)"
expect_contains "LS2c: …with the command to run by hand" "task-set T4 status=active agent=w1-T4" "$(reason_of)"
expect_contains "LS2d: …row T4 is still pending" "| d.sh | — | — | pending |" "$(cat "$(ls_plan "$LS_D")")"
LS_HOME=$(cd "$(mktemp -d)" && pwd -P)
STOP_OUT=$(env HOME="$LS_HOME" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$SID" \
  bash "$HOOK" <<< "$(jq -nc --arg c "$LS_D" --arg t "$LS_TX" --arg s "$SID" \
    '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:"Stop",stop_hook_active:true,background_tasks:[]}')" 2>/dev/null)
expect_eq "LS2e: …once: the re-entered Stop passes" "" "$(sd_decision)"


# A BOUND ON THE WALL, AND WHAT IT LEFT RUNNING (wave-26 T51; review 13 F1, F6). `ls_fire_bg`
# starts the Stop hook in a process group of its own; `ls_fire_end` waits for it a fixed number
# of times, then kills that group whole and reads 124. A transaction runs in the fixture's
# project, so every bash process whose working directory is under it was started by the row.
LS_BG=""; LS_BGDIR="$(mktemp -d)"
ls_fire_bg() {  # <project> <transcript> -> LS_BG, the pid and process group of the Stop hook
  local home payload
  home=$(cd "$(mktemp -d)" && pwd -P)
  payload=$(jq -nc --arg c "$1" --arg t "$2" --arg s "$SID" \
    '{session_id:$s,transcript_path:$t,cwd:$c,hook_event_name:"Stop",stop_hook_active:false,background_tasks:[]}')
  rm -f "$LS_BGDIR/rc" "$LS_BGDIR/out" "$LS_BGDIR/err"
  LS_BG="$( set -m
    ( env HOME="$home" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$SID" \
        BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_SWAP_PCT=0 \
        bash "$HOOK" <<< "$payload" > "$LS_BGDIR/out" 2> "$LS_BGDIR/err"
      echo "$?" > "$LS_BGDIR/rc" ) </dev/null >/dev/null 2>&1 &
    echo "$!" )"
}
ls_fire_end() {  # <seconds> -> STOP_OUT, STOP_ERR, STOP_RC; 124, the group killed, past the bound
  local i=0 n=$(( $1 * 10 ))
  while [ ! -s "$LS_BGDIR/rc" ] && [ "$i" -lt "$n" ]; do sleep 0.1; i=$((i + 1)); done
  if [ -s "$LS_BGDIR/rc" ]; then STOP_RC="$(cat "$LS_BGDIR/rc")"; else kill -9 -- "-$LS_BG" 2>/dev/null; STOP_RC=124; fi
  STOP_OUT="$(cat "$LS_BGDIR/out" 2>/dev/null)"; STOP_ERR="$(cat "$LS_BGDIR/err" 2>/dev/null)"
}
ls_procs() {  # <dir> -> the pids of bash processes whose working directory is <dir> or below it
  local d
  d="$(cd "$1" 2>/dev/null && pwd -P)" || return 0
  lsof -a -c bash -d cwd -Fpn 2>/dev/null | awk -v d="$d" '
    /^p/ { p = substr($0, 2); next }
    /^n/ { n = substr($0, 2); if (n == d || index(n, d "/") == 1) print p }'
}
require_helpers ls_fire_bg ls_fire_end ls_procs
command -v lsof >/dev/null 2>&1 || { echo "stop: lsof absent — the LS rows that find what they left running cannot read"; exit 1; }

# LS3 (review 13 F1): the lock cannot be made — .bionic/tmp is not writable. Through T32 the
# transaction looped without its bound and the turn end never returned.
LS_E="$(ls_world)"
ls_launch "$LS_E" w1-T3 01-T3
( cd "$LS_E" && while :; do sleep 1; done ) & LS_PLANT=$!
sleep 0.5
expect_contains "LS3 precondition: a process the row starts in the project is found by its working directory" \
  " $LS_PLANT " " $(ls_procs "$LS_E" | tr '\n' ' ')"
kill "$LS_PLANT" 2>/dev/null; wait "$LS_PLANT" 2>/dev/null
sd_turn "$LS_TX" u-ls-3 "fill-declined: T4 waits on the T3 merge"
chmod a-w "$LS_E/.bionic/tmp"
ls_fire_bg "$LS_E" "$LS_TX"; ls_fire_end 20
chmod u+w "$LS_E/.bionic/tmp"
expect_ne "LS3: §F1 the turn end returns when the launch lock cannot be made (rc $STOP_RC; 124 is the bound)" "124" "$STOP_RC"
expect_eq "LS3b: …and leaves nothing running" "" "$(ls_procs "$LS_E")"
expect_contains "LS3c: …and names the lock it could not make" "cannot be made" "$(reason_of)"
sd_turn "$LS_TX" u-ls-3b "fill-declined: T4 waits on the T3 merge"
s7_fire "$LS_E" "$LS_TX"
expect_contains "LS3d: …and once it can, the next turn end records the launch" \
  "| w1-T3 | — | 30 | REQ-1 | c.sh | .worktrees/01-T3 | 01234567 | active |" "$(cat "$(ls_plan "$LS_E")")"

# LS4 (review 13 F6): another writer replaces the plan while the transaction judges its copy. That
# is a retryable refusal (exit 75): the turn end is not refused for it, and the next caller
# applies the launch. A refusal no retry repairs (LS4d) still refuses it, on the same extractor.
LS_R="$(ls_world)"
ls_launch "$LS_R" w1-T3 01-T3
sd_turn "$LS_TX" u-ls-4 "fill-declined: T4 waits on the T3 merge"
ls_fire_bg "$LS_R" "$LS_TX"
LS_SEEN=""; LS_END=$(( $(date +%s) + 30 ))
while [ -z "$LS_SEEN" ] && [ "$(date +%s)" -lt "$LS_END" ] && [ ! -s "$LS_BGDIR/rc" ]; do
  for LS_F in "$(ls_plan "$LS_R")".launch-sync.*; do [ -e "$LS_F" ] && LS_SEEN="$LS_F"; done
  [ -n "$LS_SEEN" ] || sleep 0.02
done
printf '\n<!-- another writer -->\n' >> "$(ls_plan "$LS_R")"
ls_fire_end 30
expect_nonempty "LS4 precondition: the other writer landed while the judged copy existed" "$LS_SEEN"
expect_contains "LS4 precondition: …so the transaction wrote nothing: T3 still pending" "| c.sh | — | — | pending |" \
  "$(grep '^| T3 |' "$(ls_plan "$LS_R")")"
expect_absent "LS4: §F6 a plan replaced under the transaction does not refuse the turn" \
  "Launches not recorded" "$(reason_of)$STOP_ERR"
sd_turn "$LS_TX" u-ls-4b "fill-declined: T4 waits on the T3 merge"
s7_fire "$LS_R" "$LS_TX"
expect_contains "LS4b: …and the next turn end records the launch" \
  "| w1-T3 | — | 30 | REQ-1 | c.sh | .worktrees/01-T3 | 01234567 | active |" "$(cat "$(ls_plan "$LS_R")")"
expect_contains "LS4c: …keeping the other writer's change" "<!-- another writer -->" "$(cat "$(ls_plan "$LS_R")")"
ls_launch "$LS_R" w1-T4
sd_turn "$LS_TX" u-ls-4d
s7_fire "$LS_R" "$LS_TX"
expect_contains "LS4d: …while a launch the plan cannot record still refuses the turn" "Launches not recorded" "$(reason_of)"


# ─────────────────────────────────────────────────────────────────────────────
section "LH: on a tick's turn the wall judges live:head against the tick's head (wave-26 T32; A-T14.2)"

# After the first review proof a `live:head` review is ready only when the working branch's head
# has moved past the proof's head, and the head lives in git. The tick reads it; the wall reads
# no git, so through T14 it handed the ready set no head and never owed a follow-up review the
# tick had offered. The tick now writes the head it judged against into its digest (`head=`),
# and on that tick's turn the wall hands the same head in. The digest here is written as the
# tick writes it, fresh for the turn; the control is the same digest naming the proof's head.
LH_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
LH_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
lh_fixture() {  # -> project dir; T1 landed (writes lib/a.sh), T2 a review proved at LH_A
  local d
  d=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$d/.bionic/tmp" "$d/.bionic/docs/plans/epic-99-fixture"
  { printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
    printf 'parallel-budget: writers=2 suites=2 worktrees=8 test_jobs=8 source=user\n'
    printf -- '---\n\n# fixture plan\n\n## SDLC State\n\ncurrent: 4\napproved-by: fixture 2026-10-04T00:00Z "approved"\n'
    printf 'proved: kind=review head=%s at=2026-10-04T00:00:00Z evidence=record/r.txt\n\n- Step 4: in progress\n\n' "$LH_A"
    printf '## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | size | serves | Files | reads | status |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | the build | implementor | — | 15m | REQ-x | lib/a.sh |  | landed |\n'
    printf '| T2 | 6 | review | the review | critic | — | 15m | REQ-x | — |  | pending |\n'
  } > "$d/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
  bound_marker "$d" "$SID" "$d/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
  printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' \
    > "$d/.bionic/tmp/roster-$SID.state"
  printf '%s' "$d"
}
lh_digest() {  # <project> <head> [at] -> the tick digest, as the tick writes it, after the turn's marker (at: now)
  printf 'patrol-digest/v1\nprompt_version=5\ndigest=1-1\nsince=2026-10-04T00:00:00Z\ndecision=FILL\nduty=none\nat=%s\nhead=%s\n' \
    "${3:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}" "$2" > "$1/.bionic/tmp/tick-digest-$SID.state"
}
require_helpers lh_fixture lh_digest
LH_D="$(lh_fixture)"
LH_TX="$(mktemp)"
s7_transcript "$LH_TX" "poker: FILL T2"
lh_digest "$LH_D" "$LH_B"
s7_fire "$LH_D" "$LH_TX"
expect_contains "LH1: with the tick's head past the proof, the wall owes the follow-up review" \
  "Fillable gap at turn end" "$(reason_of)"
expect_contains "LH1b: …naming it" "T2" "$(reason_of)"
lh_digest "$LH_D" "$LH_A"
s7_fire "$LH_D" "$LH_TX"
expect_absent "LH2: at the proof's own head the review waits, and the wall owes nothing" \
  "Fillable gap" "$(reason_of)$STOP_ERR"
# LH3 (review 10): the tick wrote head=B, then `proof-add review` recorded a proof at B in the
# same turn, and the digest is still fresh. The wall compares the digest's head with the plan's
# CURRENT last review proof, so B against B is nothing landed past it: no review of nothing.
lh_digest "$LH_D" "$LH_B"
sed -i.bak "s/^\(proved: kind=review head=$LH_A at=2026-10-04T00:00:00Z evidence=record\/r.txt\)\$/\1\\
proved: kind=review head=$LH_B at=2026-10-04T00:10:00Z evidence=record\/r2.txt/" \
  "$LH_D/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
expect_contains "LH3 precondition: the plan now carries a later review proof at B" "head=$LH_B" \
  "$(grep '^proved: kind=review' "$LH_D/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md")"
s7_fire "$LH_D" "$LH_TX"
expect_absent "LH3: a proof at the digest's head, added after the tick, leaves nothing for the wall to owe" \
  "Fillable gap" "$(reason_of)$STOP_ERR"

# LH4 (review 13 F3; review 10 (a)'s guard): the tick wrote head=B, then a landing moved the head
# to C and `proof-add review` recorded a proof at C, after the tick. The digest is still fresh for
# the turn, but its head is older than the newest proof: handed in, B against C reads as a
# landing past the proof and the wall owes a review of nothing. The wall hands the digest's head
# in only when its `at=` is not older than the newest review proof's `at=`. The control is the
# same plan with the proof at C made before the tick: then B is the tick's head past the proof.
LH_C="cccccccccccccccccccccccccccccccccccccccc"
LH_P="$LH_D/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
sed -i.bak "s/^\(proved: kind=review head=$LH_B at=2026-10-04T00:10:00Z evidence=record\/r2.txt\)\$/\1\\
proved: kind=review head=$LH_C at=2026-10-04T00:30:00Z evidence=record\/r3.txt/" "$LH_P"
expect_contains "LH4 precondition: the newest review proof is at C" "head=$LH_C at=2026-10-04T00:30:00Z" \
  "$(grep '^proved: kind=review' "$LH_P" | tail -1)"
lh_digest "$LH_D" "$LH_B" 2026-10-04T01:00:00Z
s7_fire "$LH_D" "$LH_TX"
expect_contains "LH4 control: a tick after the proof at C, at head B, owes the review" "Fillable gap at turn end" "$(reason_of)"
sed -i.bak "s/head=$LH_C at=2026-10-04T00:30:00Z/head=$LH_C at=2026-10-04T02:00:00Z/" "$LH_P"
expect_contains "LH4 precondition: the proof at C is now newer than the tick" "head=$LH_C at=2026-10-04T02:00:00Z" \
  "$(grep '^proved: kind=review' "$LH_P" | tail -1)"
s7_fire "$LH_D" "$LH_TX"
expect_absent "LH4: §F3 a proof newer than the tick's digest leaves its head out: no review of nothing" \
  "Fillable gap" "$(reason_of)$STOP_ERR"
# LH5 (wave-26 T54; review 17 N4): the proof at C made in the tick's own second. A proof in the
# same second as the digest cannot be ordered against it, and keeping the head owed a review of
# nothing once; a tie now hands in no head, and the review waits for the next tick. LH4's control,
# on this fixture, is the positive: a proof older than the digest still owes it.
sed -i.bak "s/head=$LH_C at=2026-10-04T02:00:00Z/head=$LH_C at=2026-10-04T01:00:00Z/" "$LH_P"
expect_contains "LH5 precondition: the proof at C carries the digest's own second" "head=$LH_C at=2026-10-04T01:00:00Z" \
  "$(grep '^proved: kind=review' "$LH_P" | tail -1)"
s7_fire "$LH_D" "$LH_TX"
expect_absent "LH5: §N4 a proof in the digest's own second leaves its head out: no review of nothing" \
  "Fillable gap" "$(reason_of)$STOP_ERR"

# LH-Q (wave-27 T10; D4): THE WALL OWES EACH READ ROW BY ITS OWN QUESTIONS. Two read rows, T2
# `live:head:evidence` and T3 `live:head:adversarial`, each question last read at A. The wall
# hands the tick's head to the same ready set the tick asks, and that set keys the last proof by
# question, so the wall owes what the tick offered: at B both rows, at A neither; and once the
# evidence reading has moved to B (before the tick), at B only the adversarial row. The rule for
# WHICH head goes in is unchanged and global: a reading of any question newer than the digest
# leaves the head out (LH4), the soft side, one tick's wait. SYNTHESIZED, as LH.
lhq_fixture() {  # -> project dir; T1 landed, T2 and T3 read rows, both questions read at LH_A
  local d p
  d="$(lh_fixture)"; p="$d/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
  awk -v a="$LH_A" '
    /^proved: kind=review / {
      print "proved: kind=review head=" a " at=2026-10-04T00:00:00Z evidence=record/ev.md question=evidence reader=w-aud result=pass scope=piece"
      print "proved: kind=review head=" a " at=2026-10-04T00:01:00Z evidence=record/adv.md question=adversarial reader=w-crit result=pass scope=piece"
      next }
    /^\| T2 \| 6 \| review / {
      print "| T2 | 6 | review | the evidence read | auditor | — | 15m | REQ-x | — | approval:plan, live:head:evidence | pending |"
      print "| T3 | 6 | review | the adversarial read | critic | — | 15m | REQ-x | — | approval:plan, live:head:adversarial | pending |"
      next }
    { print }' "$p" > "$p.new" && mv "$p.new" "$p"
  printf '%s' "$d"
}
lhq_owed() {  # -> the ids the wall's reason names as ready to dispatch, space-joined
  reason_of | sed -n 's/.*these rows are ready to dispatch — \(.*\) — and this turn neither.*/\1/p' | tr -c 'A-Za-z0-9\n' ' ' \
    | tr ' ' '\n' | /usr/bin/grep -E '^T[0-9]+$' | sort | tr '\n' ' ' | sed 's/ $//'
}
require_helpers lhq_fixture lhq_owed
LHQ_D="$(lhq_fixture)"
LHQ_P="$LHQ_D/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
expect_eq "LH-Q0 precondition: two readings, one per question, and two read rows" "2 2" \
  "$(grep -c '^proved: kind=review .* question=' "$LHQ_P") $(grep -c 'live:head:' "$LHQ_P")"
s7_transcript "$LH_TX" "poker: FILL T2 T3"
lh_digest "$LHQ_D" "$LH_B"
s7_fire "$LHQ_D" "$LH_TX"
expect_eq "LH-Q1: with the tick's head past both readings, the wall owes both read rows" "T2 T3" "$(lhq_owed)"
lh_digest "$LHQ_D" "$LH_A"
s7_fire "$LHQ_D" "$LH_TX"
expect_absent "LH-Q2: at the readings' own head neither row is owed" "Fillable gap" "$(reason_of)$STOP_ERR"
sed -i.bak "s/^\(proved: kind=review head=\)$LH_A\( at=2026-10-04T00:00:00Z evidence=record\/ev.md question=evidence\)/\1$LH_B\2/" "$LHQ_P"
expect_contains "LH-Q3 precondition: the evidence reading is now at B, the adversarial one still at A" \
  "head=$LH_B at=2026-10-04T00:00:00Z evidence=record/ev.md question=evidence" "$(grep '^proved: kind=review' "$LHQ_P")"
s7_transcript "$LH_TX" "poker: FILL T3"
lh_digest "$LHQ_D" "$LH_B"
s7_fire "$LHQ_D" "$LH_TX"
expect_eq "LH-Q3: at B the wall owes the adversarial row alone; the evidence row read B already" "T3" "$(lhq_owed)"


# ─────────────────────────────────────────────────────────────────────────────
section "FILES-REMEDY: the amend the landing refusal prints is one amend accepts, run as printed (wave-27 T29; REQ-12 AC-12.3, D21)"

# THE DEFECT, from a real run: a writer committed a file at the repository root, the landing
# refused the stop, and the remedy it printed — `amend <name> --files+ 'CONTEXT.md'` — was
# itself refused by amend, which read a Files: entry as a path only when it carried a `/`.
# The remedy is now spelled by the one reader in brief.sh that amend reads with: a root file
# with an extension as written, and a bare name as `./<name>`. The fixture touches one of each,
# and the printed line is run exactly as printed. The bare name, Widgetfile, is in the main
# checkout's base commit too (wave-27 T42): T29's reader admitted a bare name by listing the
# project root, and with the file there it printed `--files+ 'Widgetfile'`; no wall lists the
# root now, so the spelling is `./Widgetfile` whatever the root holds.
fr_fixture() {  # -> a git project whose writer tree committed two root files outside Files:
  local d wt
  d=$(mkfix)
  git -C "$d" init -q 2>/dev/null
  git -C "$d" symbolic-ref HEAD refs/heads/main
  git -C "$d" config user.email t@example.invalid; git -C "$d" config user.name T
  printf '.bionic/\n.worktrees/\n' > "$d/.gitignore"; echo base > "$d/base.txt"; echo base > "$d/Widgetfile"
  git -C "$d" add .gitignore base.txt Widgetfile; git -C "$d" commit -qm base
  wt="$d/.worktrees/fr-writer"
  git -C "$d" worktree add -q "$wt" -b wt/fr-writer >/dev/null 2>&1
  git -C "$wt" config user.email t@example.invalid; git -C "$wt" config user.name T
  mkdir -p "$wt/declared"
  echo one > "$wt/declared/one.sh"; echo ctx > "$wt/CONTEXT.md"; echo w > "$wt/Widgetfile"
  git -C "$wt" add -A; git -C "$wt" commit -qm work
  {
    roster_header
    roster_row_fixture status=identified session="$SID" name=fr-writer agent_id="$AID" \
      deliverable=.bionic/docs/record/fr.md launched_at=2026-09-01T00:00:00Z \
      subagent_type=bionic:implementor files=declared/ suites_allowed=none suites_source=declared \
      tool_use_id=toolu_FR
  } > "$d/.bionic/tmp/roster-$SID.state"
  mkdir -p "$d/.bionic/docs/record"; echo done > "$d/.bionic/docs/record/fr.md"
  printf '%s' "$d"
}
D=$(fr_fixture)
fire "$D"
expect_status "FR1 the control — root files outside Files: refuse the stop" "2" "$STOP_RC"
FR_FIXLINE="$(printf '%s\n' "$STOP_ERR$(reason_of)" | /usr/bin/grep -m1 'session-poker.sh.* amend ' | sed 's/^[[:space:]]*//')"
expect_contains "FR1 precondition: the refusal prints its amend line" "amend 'fr-writer'" "$FR_FIXLINE"
expect_contains "FR2 the line spells the root file with an extension as written" "--files+ 'CONTEXT.md'" "$FR_FIXLINE"
expect_contains "FR3 …and the extensionless root file, present at the root, as ./<name>" "--files+ './Widgetfile'" "$FR_FIXLINE"
# A fresh fixture for the amend and the second stop, as section 8 does: the first stop has
# already judged its row, so a second stop over the same fixture never reaches the landing check.
D=$(fr_fixture)
FR_OUT=$( cd "$D" && CLAUDE_CODE_SESSION_ID="$SID" bash -c "$FR_FIXLINE" 2>&1 ); FR_RC=$?
expect_eq "FR4 AC-12.3 the printed amend, run as printed, succeeds" "0" "$FR_RC"
expect_contains "FR4 …saying it amended" "amended" "$FR_OUT"
fire "$D"
expect_absent "FR5 …and the same diff now lands: no landing refusal" "LANDING DIFF OUTSIDE" "$STOP_ERR$(reason_of)"
expect_status "FR5 …and the stop is admitted" "0" "$STOP_RC"

# ─────────────────────────────────────────────────────────────────────────────
section "RW: the reconcile refusal says the plan moved when that is why it is owed (wave-27 T37; review pass 8 F2)"

# The tick writes `reconcile=step4` or `reconcile=grew` beside `duty=owed` when the reconcile is
# owed because the plan moved (tests/session-poker.test.sh §RECON-WHY). A tick turn with no
# task-list refresh is refused as before; the refusal now gives that cause and names the rebuild,
# and with no cause in the digest, or a digest older than the turn's tick, it is today's words.
# The fixture is LH's at the proof's own head, so no fill is owed, and its transcript is s7's
# tick turn with the TaskList call taken out. SYNTHESIZED, as LH.
rw_digest() {  # <project> <reconcile cause or ""> [at]
  { printf 'patrol-digest/v1\nprompt_version=5\ndigest=1-1\nsince=2026-10-04T00:00:00Z\ndecision=QUIET\nduty=owed\nat=%s\nhead=%s\n' \
      "${3:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}" "$LH_A"
    [ -z "$2" ] || printf 'reconcile=%s\n' "$2"
  } > "$1/.bionic/tmp/tick-digest-$SID.state"
}
require_helpers rw_digest
RW_D="$(lh_fixture)"
RW_TX="$(mktemp)"
s7_transcript "$RW_TX" "poker: RECONCILE"
/usr/bin/grep -v '"name":"TaskList"' "$RW_TX" > "$RW_TX.n" && mv "$RW_TX.n" "$RW_TX"
expect_eq "RW0 precondition: the turn holds no TaskList call" "0" "$(/usr/bin/grep -c '"TaskList"' "$RW_TX" | tr -d ' ')"
rw_digest "$RW_D" ""
s7_fire "$RW_D" "$RW_TX"
expect_contains "RW1 control: with no cause the refusal is today's" \
  'which owes one (it prints "poker: RECONCILE" when a ## Tasks status or the ready set changed)' "$(reason_of)"
rw_digest "$RW_D" step4
s7_fire "$RW_D" "$RW_TX"
expect_contains "RW2 the plan moved into Step 4: the refusal says so" "the plan moved from approval into Step 4" "$(reason_of)"
expect_contains "RW2b …and names the rebuild" "rebuild the task list in execution order: delete every pending entry and recreate them" "$(reason_of)"
expect_absent "RW2c …and not the status-changed cause" "when a ## Tasks status or the ready set changed" "$(reason_of)"
rw_digest "$RW_D" grew
s7_fire "$RW_D" "$RW_TX"
expect_contains "RW3 the table grew: the refusal says so" "the ## Tasks table grew" "$(reason_of)"
expect_contains "RW3b …and names the rebuild" "delete the pending entries after the new row and recreate them" "$(reason_of)"
rw_digest "$RW_D" step4 2026-09-18T00:00:00Z
s7_fire "$RW_D" "$RW_TX"
expect_contains "RW4 a digest older than the turn's tick gives no cause: the refusal is today's" \
  'which owes one (it prints "poker: RECONCILE" when a ## Tasks status or the ready set changed)' "$(reason_of)"

# THE FIX NAMES WHAT THE WALL COUNTS (wave-27 T74; review pass 53 S1). The wall's predicate is a
# TaskList call or a write naming the plan; the delete-and-recreate it asked for (TaskUpdate,
# TaskCreate) is never counted, so the fix read `rebuild it` and dropped the one act that
# discharges it. Now the fix names TaskList first and the detail keeps "or a plan-ledger write",
# the fallback where the task tools are absent. The first line keeps to 100 columns.
# fails-when: a plan-moved refusal's fix leaves out TaskList, or its detail the plan-ledger write.
rw_first() { reason_of | head -1; }
require_helpers rw_first
for rw_cause in step4 grew; do
  rw_digest "$RW_D" "$rw_cause"
  s7_fire "$RW_D" "$RW_TX"
  expect_contains "RW5 ($rw_cause) the first line's fix names TaskList first" \
    "no task-list refresh since this tick (TaskList, rebuild it, then stop again)" "$(rw_first)"
  expect_contains "RW5b ($rw_cause) …the detail keeps the plan-ledger write" "or a plan-ledger write" "$(reason_of)"
  expect_true "RW5c ($rw_cause) …and the first line keeps to 100 columns" \
    test "$(rw_first | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')" -le 100
done

finish
