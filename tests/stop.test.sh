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
  : > "$d/.bionic/tmp/engaged-$SID.state"
  printf -- '---\ncanonical_sdlc_version: 14\n---\n\n## SDLC State\n\ncurrent: 4\n\n- Step 4\n' \
    > "$d/.bionic/docs/plans/wave-01.plan.md"
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

# A PATROL STAMP PAST 2x THE INTERVAL — patrol-revive's block. The interval is
# pinned tiny through the project's own knob and the age is a backdated mtime.
stale_stamp() {  # <project>
  printf 'poker-interval: 1s\n' > "$1/.bionic/config.yaml"
  printf 'patrol-stamp/v1|at=2026-08-27T00:00:00Z|session=%s|verb=arm\n' "$SID" \
    > "$1/.bionic/tmp/patrol-$SID.state"
  touch -t "$(date -v-600S +%Y%m%d%H%M.%S 2>/dev/null || date -d '-600 seconds' +%Y%m%d%H%M.%S)" \
    "$1/.bionic/tmp/patrol-$SID.state"
}

# A TRANSCRIPT whose last assistant entry carries usage — what context-spend reads.
usage_tx() {  # <file>
  jq -nc '{type:"assistant",message:{model:"claude-opus-5",usage:{input_tokens:1000,cache_creation_input_tokens:0,cache_read_input_tokens:0}}}' > "$1"
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

# THE ADVISORIES ARE STILL THERE, AND THEY ARE LAST. Three of the four resolve this
# unbound session's run by the newest-plan fallback and say so; a fold that put them
# first would bury the refusal under them.
expect_contains "1g: an advisory from a non-blocking verdict survives the block" \
  "context-spend: run resolved by newest-plan fallback" "$STOP_ERR"
expect_true "1h: …and prints AFTER the refusal line" \
  test "$(awk '/^bionic: /{print NR; exit}' <<<"$STOP_ERR")" -lt \
       "$(awk '/^context-spend: /{print NR; exit}' <<<"$STOP_ERR")"

# ─────────────────────────────────────────────────────────────────────────────
section "2: one block and one advisory"

D=$(mkfix); unmet_row "$D"
fire "$D"
expect_status "2a: a lone landing block exits 2, the channel that verdict has always used" \
  "2" "$STOP_RC"
expect_contains "2b: its line is on stderr" \
  "bionic: stop refused — a dispatched agent's contract is unmet" "$STOP_ERR"
expect_eq "2c: exactly one rendered refusal" "1" "$(refusal_lines)"
expect_contains "2d: the advisories are kept" \
  "patrol-revive: run resolved by newest-plan fallback" "$STOP_ERR"
expect_true "2e: …after the refusal" \
  test "$(awk '/^bionic: /{print NR; exit}' <<<"$STOP_ERR")" -lt \
       "$(awk '/^patrol-revive: /{print NR; exit}' <<<"$STOP_ERR")"

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
expect_absent "4b: nor does the instrument's fallback advisory" \
  "context-spend: run resolved" "$STOP_ERR"
expect_absent "4c: nor the duties gate's" \
  "patrol-duties-gate: run resolved" "$STOP_ERR"

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

# WHAT CHANGED, AND WHY THE NUMBER MOVED (spec D4). `tests/lib/impact.sh` used
# to rebuild its whole edge graph on every invocation — ~4.2 s at quiet load,
# argument-independent to 13 ms (R2 Q8) — so the number bounding it was doing
# two jobs at once: paying for a cost nobody had removed, and guarding against a
# command that never returns. The graph is cached per tree state now. That
# leaves the bound one job, and one honest value for it: 20 s, a HANG GUARD.
#
# TWO COPIES IS THE DEFECT THIS SECTION EXISTS FOR. The sweep's bound at
# lib/stop.sh:886 and the dispatch wall's at dispatch-preflight.sh:2225 were the
# same 6 s, written twice, in two files, with two independent budgets — so a
# wave that moved one of them shipped a tree whose two legs disagreed about what
# "bounded" means, and neither file said the other existed. There is one
# definition now, in payload/scripts/lib/bounds.sh, and both consumers read it.
#
# STATIC, BY THE SPEC'S OWN EVAL DESIGN (AC-7.4, eval type `static`). Observing
# the value through the sweep would mean hanging a real derivation for 20 s to
# read one number out of one message, and would still say nothing about the
# second consumer. So these rows read the files — and because a grep against a
# file is exactly the assertion that keeps passing after its pattern has
# drifted, each reading is PAIRED with a mutation that removes what it looks for.
BOUNDS_SH="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/bounds.sh"
STOP_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/stop.sh"

expect_true "6a: payload/scripts/lib/bounds.sh exists" test -f "$BOUNDS_SH"
expect_true "6b: …and parses under bash -n" bash -n "$BOUNDS_SH"

# THE VALUE IS READ BY SOURCING, not by grepping a literal back out of the file:
# what a consumer gets is what sourcing gives it.
expect_eq "6c: sourcing it defines IMPACT_BOUND_S=20" "20" \
  "$(bash -c '. "$1" 2>/dev/null && printf "%s" "${IMPACT_BOUND_S:-}"' _ "$BOUNDS_SH" 2>/dev/null)"

# NOT VACUOUS: the row above reads the file rather than agreeing with a constant
# typed into this suite, and a copy carrying a different number proves it.
B_MUTD="$(mktemp -d)"
anchor -E "$BOUNDS_SH" '^IMPACT_BOUND_S=20$' 1
sed 's/^IMPACT_BOUND_S=20$/IMPACT_BOUND_S=3/' "$BOUNDS_SH" >"$B_MUTD/bounds.sh"
expect_eq "6d: …and a copy carrying 3 answers 3, so 6c read the file" "3" \
  "$(bash -c '. "$1" 2>/dev/null && printf "%s" "${IMPACT_BOUND_S:-}"' _ "$B_MUTD/bounds.sh" 2>/dev/null)"

# THE HEADER SAYS WHAT THE NUMBER IS FOR. Without that sentence the next reader
# who meets a slow derivation tunes this number, which is the habit D4 retires.
# Case-tolerant on purpose: the file says it in a heading (HANG GUARD) and a
# reviewer who rewords the heading in lower case has not weakened anything.
expect_regex "6e: …and its header names the number a hang guard" \
  "[Hh][Aa][Nn][Gg][ -][Gg][Uu][Aa][Rr][Dd]" "$(cat "$BOUNDS_SH" 2>/dev/null)"

# ONE DEFINITION IN THE LIBRARY TREE (AC-7.4, this task's half). A DEFINITION is
# a literal number; a consumer's `LG_IMPACT_BOUND_S="$IMPACT_BOUND_S"` is a READ
# and is not counted, which is the distinction the criterion's "defined in two
# places" turns on — the criterion's own spelling, `grep -rn 'IMPACT_BOUND_S='`,
# matches both and can never reach one.
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
expect_eq "6f: exactly one numeric definition of the bound in payload/scripts/" \
  "1" "$(printf '%s\n' "$B_DEFS" | /usr/bin/grep -c .)"
expect_contains "6g: …and it is the one in lib/bounds.sh" "lib/bounds.sh" "$B_DEFS"
# NOT VACUOUS: the sweep reaches a file it could have missed, and the READ in
# lib/stop.sh is inside its span and deliberately uncounted.
expect_nonempty "6f2: the sweep reaches lib/stop.sh, whose READ it declines to count" \
  "$(/usr/bin/grep -rn 'IMPACT_BOUND_S' "${BIONIC_SCRIPTS_DIR}/payload/scripts" 2>/dev/null \
     | /usr/bin/grep 'lib/stop.sh')"

# THIS CONSUMER READS IT. The dispatch wall is the other, pinned in its own
# suite; what stop.test.sh owns is the sweep's side.
STOP_SRC="$(cat "$STOP_LIB")"
expect_nonempty "6h: lib/stop.sh sources lib/bounds.sh" \
  "$(/usr/bin/grep -nE '^[[:space:]]*(\.|source)[[:space:]]+.*bounds\.sh' "$STOP_LIB")"
expect_regex "6i: …and takes the sweep's bound from that constant" \
  'LG_IMPACT_BOUND_S="?\$\{?IMPACT_BOUND_S' "$STOP_SRC"
expect_no_regex "6j: …leaving no literal bound of its own behind" \
  '^[[:space:]]*LG_IMPACT_BOUND_S=[0-9]' "$STOP_SRC"

# THE TICK BUDGET IS THE BOUND, IN TENTHS. A bound that moved while the ticks
# stayed at 60 would leave the sweep still stopping at 6 s while both of its
# messages (lib/stop.sh:1000, :1027) quoted 20 — a lie in the one place an
# operator is told why the suites were not derived.
expect_no_regex "6k: …and the tick budget is derived from the bound, not written twice" \
  '^[[:space:]]*LG_IMPACT_TICKS_LEFT=[0-9]' "$STOP_SRC"

# NOT VACUOUS: a copy with the source line cut has nothing for 6h to find, so
# 6h discriminates rather than matching any mention of the name anywhere.
S_MUTD="$(mktemp -d)"
anchor -E "$STOP_LIB" '^[[:space:]]*(\.|source)[[:space:]]+.*bounds\.sh' 1
/usr/bin/grep -vE '^[[:space:]]*(\.|source)[[:space:]]+.*bounds\.sh' "$STOP_LIB" \
  >"$S_MUTD/stop.sh"
expect_empty "6l: …and a copy with that line cut has no source line left to find" \
  "$(/usr/bin/grep -nE '^[[:space:]]*(\.|source)[[:space:]]+.*bounds\.sh' "$S_MUTD/stop.sh")"

finish
