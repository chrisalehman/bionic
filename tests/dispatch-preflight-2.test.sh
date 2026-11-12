#!/bin/bash
# Tests for hooks/dispatch-preflight.sh — THE START GATE. One shard of four:
# S1 … S22.
#
# The suite's header (what it governs, how it stays hermetic) is in
# tests/dispatch-preflight.test.sh; the fixtures and their fidelity notes are in
# tests/dispatch-preflight.prelude.sh.
#
# FOUR SHARDS, ONE SUITE (wave-30 T1; design ledger Δ7, D8; AC-5.1). This suite ran for
# 1,462 s at width 4, the longest in the roster, so it is split by section into four files
# that the runner schedules side by side. Each is a gating suite by location, and each passes
# alone:
#
#   dispatch-preflight.test.sh     §CAP … §role-class, then §no-listagents
#   dispatch-preflight-2.test.sh   S1 … S22
#   dispatch-preflight-3.test.sh   §combined … §two-deliverables
#   dispatch-preflight-4a.test.sh  S10h … §LR       (two parts since wave-39 T37; the helpers they share
#   dispatch-preflight-4b.test.sh  §T72 … §FILES     are in tests/dispatch-preflight-4.prelude.sh)
#
# What every shard needs and no section owns is in tests/dispatch-preflight.prelude.sh: the
# fixtures, the sandbox and its traps, run_gate and the payload builders, and the helpers and
# constant strings that a section defined and a section in another shard reads. Each shard
# sources the framework and the shared libraries itself, then the prelude. The one fixture
# that crosses sections, the decoy roster file S10h plants and §RECORDER reads, is kept in
# one shard by moving S10h beside §RECORDER. §no-listagents reads a sweep that run_gate keeps
# over every payload driven before it, so it closes the shard that drives the most; it sweeps
# that shard's traffic, not the whole suite's. The sum of the four shards' checks is the
# unsplit suite's count.
#
# Usage: bash tests/run.sh --only dispatch-preflight-2.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
MAKE_REPO_AT=15; . "$(dirname "$0")/dispatch-preflight.prelude.sh"

section "S1 — relevance hoist (A7): irrelevant tool passes, silent"


REPO=$(make_repo r1 yes)
# no attestation exists at all — if tool_name gating were bypassed, an
# "Agent" payload here would be REFUSED. A "Bash" payload must still pass.
run_gate "$(mk_bash_payload "$SID_A" "$REPO")"
expect_status "irrelevant tool exits 0 even with no attestation in an active wave" "0" "$GATE_ST"
expect_empty "irrelevant tool produces no stdout" "$GATE_OUT"
expect_empty "irrelevant tool produces no stderr" "$GATE_ERR"

# static pin: the relevance check must appear in the source BEFORE the
# active-wave machinery (resolve_docs_root / the plan-directory find) — this
# is the textual half of A7's hoist proof; the behavioral half is above.
TOOL_LINE=$(grep -n '\[ "\$TOOL_NAME" = "Agent" \]' "$GATE" | head -1 | cut -d: -f1)
# RE-POINTED (epic-23 wave-11-lean-spine, REQ-1f). The first thing this gate pays for is
# no longer its own `session_run` call: `bionic_context` resolves the root, the session id
# and the run verdict in one, and THAT is the line the relevance check must precede. What
# is pinned is unchanged — nothing touches disk before the cheap check.
#
# THE ANCHOR IS THE POINT. Both line numbers are asserted findable BEFORE they are
# compared, because a grep whose literal has left the file yields the empty string and
# `[ "$TOOL_LINE" -lt "" ]` is an error, not a comparison — an order pin over two empty
# values pins nothing, which is exactly the state this one was heading for.
WALK_LINE=$(grep -n '^bionic_context' "$GATE" | head -1 | cut -d: -f1)
expect_nonempty "the relevance check is findable in the gate's source" "$TOOL_LINE"
expect_nonempty "the context call is findable in the gate's source" "$WALK_LINE"
if [ -n "$TOOL_LINE" ] && [ -n "$WALK_LINE" ] && [ "$TOOL_LINE" -lt "$WALK_LINE" ]; then
  ok "relevance check (line $TOOL_LINE) precedes the context resolution (line $WALK_LINE)"
else
  no "relevance check precedes the context resolution" "tool=$TOOL_LINE walk=${WALK_LINE:-none}"
fi

section "S5 — active wave + no attestation on disk -> AUTO-PROBE, then pass (AC-2 / AC-4)"
#
# THE DIRECTION REVERSED IN EPIC-16 WAVE-02 (R5). Through wave-01 this refused and named
# a command for the operator to run by hand — and a field report measured
# what that cost: five serialized minutes between deciding to dispatch and the agent
# existing, paid again after every /clear, which re-fires the this-session demand
# mid-wave although nothing about the machine has changed.
#
# A missing attestation is not evidence of a broken environment; it is the absence of
# evidence, and re-reading the fact costs a second and cannot go stale. So the gate takes
# the reading itself. The refusal did not disappear — it MOVED, onto the probe's own
# verdict (S16 drives that half, and the arc end to end).

REPO=$(make_repo r5 yes)
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "no attestation in an active wave no longer refuses" "0" "$GATE_ST"
expect_empty "the auto-probe path produces no stdout" "$GATE_OUT"
expect_absent "…and no refusal is printed" "BLOCKED" "$GATE_ERR"
expect_status "…the attestation it was missing now exists" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_A.state" ] && echo 0 || echo 1)"

# The fix command survives where it still means something — the probe-failure refusal —
# and checklist A1's requirement on it is unchanged: an install-path spelling, runnable
# from any cwd, never this gate itself. Driven here on the one path that still refuses.
REPO=$(make_repo r5b yes)
mkdir -p "$REPO/.bionic/tmp"; chmod 500 "$REPO/.bionic/tmp"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
chmod 700 "$REPO/.bionic/tmp"
expect_contains "a probe-failure refusal still names the install-path fix command" \
  "bash $PROBE_SRC" "$GATE_VERR"
expect_absent "refusal does not name a repo-relative fix command (checklist A1)" "hooks/preflight-probe.sh\"" "$GATE_ERR"
case "$GATE_ERR" in
  *"hooks/dispatch-preflight.sh"*) no "refusal never names itself as the fix" ;;
  *) ok "refusal never names itself as the fix" ;;
esac

section "S8 — hostile/malformed attestation shapes -> REFUSE, never followed (AC-8-adjacent)"

# attestation path occupied by a directory
REPO=$(make_repo r8a yes)
mkdir -p "$REPO/.bionic/tmp/preflight-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "attestation path is a directory -> refuse" "2" "$GATE_ST"

# attestation path is a symlink to a file that DOES contain a matching
# session_id= line — proves the gate never follows it, even when doing so
# would happen to "pass": the wall must not be foolable by planted content.
REPO=$(make_repo r8b yes)
mkdir -p "$REPO/.bionic/tmp"
DECOY="$SANDBOX/decoy-attestation"
printf 'session_id=%s\nversion=1\n' "$SID_A" > "$DECOY"
ln -s "$DECOY" "$REPO/.bionic/tmp/preflight-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "attestation path is a symlink -> refuse, not followed" "2" "$GATE_ST"

# S1 (Step-6 security review, task 4/7): the DIRECTORY levels are guarded too.
# Checking only the file leaves the same class open one level up — a repo
# controls its own `.bionic/` contents, so pointing `.bionic/tmp` (or `.bionic`)
# at a directory holding a valid same-session attestation opens the wall with
# content the repo arranges. §8's load-bearing property is that a hostile repo
# can CLOSE or AIM these walls but never OPEN them, and the sibling gate already
# refuses at both levels (hooks/stop-guard.sh's state_paths(); checklist A3
# names this variant, discharged for the WRITE path only).
for _lvl in .bionic/tmp .bionic; do
  _tag=$(printf '%s' "$_lvl" | tr -d './')
  REPO=$(make_repo "r8d-$_tag" yes)
  ELSEWHERE="$SANDBOX/elsewhere-$_tag/.bionic/tmp"
  mkdir -p "$ELSEWHERE"
  printf 'session_id=%s\nversion=1\nkind=preflight-attestation\n' "$SID_A" \
    > "$ELSEWHERE/preflight-$SID_A.state"
  # THE HOSTILE DIRECTORY CARRIES THE ENGAGEMENT MARKER AS WELL (task-engaged-session).
  # The gate asks `engaged_session` first, and its path runs through the very directory
  # this case redirects — so without a marker on the far side the gate would exit at the
  # switch and the S1 claim (the attestation is not read THROUGH a directory symlink)
  # would be proven by an exit that never reached the attestation at all. Planting it is
  # also the honest shape: engagement is the one artifact whose PRESENCE opens a wall, so
  # a repo that can arrange it can only ever ARM these walls against itself.
  : > "$ELSEWHERE/engaged-$SID_A.state"
  if [ "$_lvl" = ".bionic/tmp" ]; then
    mkdir -p "$REPO/.bionic"
    # make_repo plants a real .bionic/tmp (the Patrol stamp lives there); it has to GO,
    # or `ln -s` lands the link INSIDE it and the hostile shape under test never exists.
    rm -rf "$REPO/.bionic/tmp"
    ln -s "$ELSEWHERE" "$REPO/.bionic/tmp"
  else
    # The whole `.bionic` redirected: the active plan has to travel with it, or
    # the case is vacuous (no wave, nothing to decide).
    cp -R "$REPO/.bionic/docs" "$SANDBOX/elsewhere-$_tag/.bionic/docs"
    rm -rf "$REPO/.bionic"
    ln -s "$SANDBOX/elsewhere-$_tag/.bionic" "$REPO/.bionic"
  fi
  run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
  expect_status "a planted DIRECTORY symlink at ${_lvl} -> refuse, not read through (S1)" \
    "2" "$GATE_ST"
done

# attestation file exists but is empty / has no session_id= line at all. Unlike the
# hostile shapes above, this is not an attack — it is an unreadable fact, which R5 treats
# as no fact at all: the probe re-takes it and overwrites the unreadable record. The
# security property is untouched, because the two are distinguished by WHO fixes them —
# a symlink is refused by the probe, a bad record is replaced by it.
REPO=$(make_repo r8c yes)
mkdir -p "$REPO/.bionic/tmp"
printf 'version=1\nkind=preflight-attestation\n' > "$REPO/.bionic/tmp/preflight-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "attestation with no session_id= line -> re-taken, not refused" "0" "$GATE_ST"
expect_status "…and the unreadable record is replaced by a keyed one" "0" \
  "$(grep -qx "session_id=$SID_A" "$REPO/.bionic/tmp/preflight-$SID_A.state" && echo 0 || echo 1)"

section "S10 — the roster row is written on the pass path (AC-1, launch half)"
#
# Governing design: spec §Design "Roster" + §Component boundaries. The row is
# appended at launch with status `intended`; the full agent id and `confirmed`
# are task 4/4's, not this one's.

REPO=$(make_repo r10 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
R10=$(roster_path "$REPO" "$SID_A")

expect_status "a contract-complete dispatch still passes (verdict unchanged)" "0" "$GATE_ST"
expect_empty "a contract-complete dispatch still prints nothing on stdout" "$GATE_OUT"
# The invariant this row protects is "no BLOCKED refusal", asserted directly. Since the
# unarmed-sweeper nag was deleted with the watcher there is nothing else on this stream for
# a contract-complete dispatch either.
expect_absent "a contract-complete dispatch prints no BLOCKED refusal on stderr" "BLOCKED" "$GATE_ERR"
expect_absent "…and nothing about an unarmed sweeper" "sweeper" "$GATE_ERR"
expect_status "the roster file exists at the per-session path" "0" "$([ -f "$R10" ] && echo 0 || echo 1)"
expect_contains "the roster carries a versioned schema header" "roster-state/v1" "$(head -1 "$R10" 2>/dev/null)"
expect_status "exactly one row was appended" "1" "$(roster_rows "$R10")"

ROW=$(roster_nth_row "$R10" 1)
expect_contains "the row's leading field is the schema version" "roster-state/v1" "$(printf '%s' "$ROW" | cut -d'|' -f1)"
expect_status "row status is 'intended'" "intended" "$(roster_field "$ROW" status)"
expect_status "row carries this session's id" "$SID_A" "$(roster_field "$ROW" session)"
expect_status "row carries the agent name from tool_input" "w99-impl" "$(roster_field "$ROW" name)"
expect_status "row carries subagent_type from tool_input" "implementor" "$(roster_field "$ROW" subagent_type)"
expect_status "row carries the model from tool_input" "claude-sonnet-5-high" "$(roster_field "$ROW" model)"
expect_status "row carries the tool_use_id (the recorder's correlation key)" \
  "toolu_018jyjgop7KMxP6yKtoAWWtB" "$(roster_field "$ROW" tool_use_id)"
expect_status "row's agent_id is empty at launch (task 4/4 fills it)" "" "$(roster_field "$ROW" agent_id)"

LAUNCHED=$(roster_field "$ROW" launched_at)
if printf '%s' "$LAUNCHED" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
  ok "row carries a UTC ISO launch timestamp"
else
  no "row carries a UTC ISO launch timestamp" "got '$LAUNCHED'"
fi

# contract state, lifted from the brief's labeled fields
expect_status "row lifts the deliverable path from 'Expected artifact:'" \
  ".bionic/docs/record/w99-widget.txt" "$(roster_field "$ROW" deliverable)"
expect_contains "row lifts the expected duration" "25" "$(roster_field "$ROW" duration)"
expect_status "row lifts the progress path from 'Progress artifact:'" \
  ".bionic/tmp/w99-widget.progress" "$(roster_field "$ROW" progress)"
expect_status "no contract field is recorded absent for a complete brief" "" "$(roster_field "$ROW" absent)"

section "S10c — a missing NON-deliverable field is RECORDED + WARNED, never blocked (AC-1)"
#
# Spec §Component boundaries: "Extraction failure warns and records absence —
# starts fail open (TDD §7)." The verdict is the load-bearing assertion here: a
# brief missing everything BUT its deliverable is a warning, not a refusal.
#
# The deliverable is the one field that escaped this rule (S10W): a dispatch
# that names none is refused outright. So this fixture carries a deliverable and
# nothing else — which is also what keeps the two directions honest, since a
# brief carrying no fields at all now never reaches the roster to be warned about.

REPO=$(make_repo r10c yes)
write_attestation "$REPO" "$SID_A"
# The label sits on its OWN line (R8: final-audit A-1 pinned the deliverable-kind
# labels to line start) — a trailing mid-line occurrence would no longer register
# as a hit at all, and this fixture is meant to test the near-fieldless-brief
# warning path, not the line-start rule.
run_gate "$(mk_agent_payload "$SID_A" "$REPO" \
  "Go and do the thing, please.
Expected artifact: .bionic/docs/record/w99-min.txt
Suites: tests/widget.test.sh" "-" "-")"
R10C=$(roster_path "$REPO" "$SID_A")
ROW=$(roster_nth_row "$R10C" 1)

expect_status "a brief with only its deliverable still PASSES the gate" "0" "$GATE_ST"
expect_empty "the absence warning never goes to stdout" "$GATE_OUT"
expect_contains "the absence is warned on stderr" "WARN" "$GATE_ERR"
expect_contains "the warning names the duration field" "duration" "$GATE_ERR"
expect_contains "the warning names the progress field" "progress" "$GATE_ERR"
expect_absent "the warning is not phrased as a refusal" "BLOCKED" "$GATE_ERR"
expect_status "the row is still appended for a near-fieldless brief" "1" "$(roster_rows "$R10C")"
ABSENT=$(roster_field "$ROW" absent)
expect_contains "the row records the duration absence" "duration" "$ABSENT"
expect_contains "the row records the progress absence" "progress" "$ABSENT"
expect_contains "the row records the missing agent name" "name" "$ABSENT"
expect_absent "the deliverable it DID name is not recorded absent" "deliverable" "$ABSENT"
expect_status "the absent contract field is empty in the row, not fabricated" "" "$(roster_field "$ROW" duration)"
# An OMITTED model is not an absence finding — the role file names the model (agents/<role>.md,
# §ROLE-MODEL below) and the roster row journals it, so a warning here would fire on the ordinary
# case and train the operator to read past the real ones.
expect_absent "an omitted model is NOT recorded as an absence" "model" "$ABSENT"

section "S10W — a brief naming NO deliverable is REFUSED; the in-brief waiver is the only way through"
#
# USER-DIRECTED (epic-15 post-w4): "A wall. It should be a wall." The absence
# warning above was the whole enforcement for the one contract field the rest of
# the machinery cannot work without — the sweeper's landing verdict has nothing to
# stat, and a dispatch that dies quietly leaves nothing behind. So this single
# field escalates from warn to REFUSAL, and every escape from the refusal is a
# line in the brief, which means it lands on the roster.
#
# Everything else stays exactly where it was: progress absence warns, duration
# absence warns. This is one wall, not a policy.

BRIEF_NO_DELIVERABLE='Your task: go and do the thing, please.
Expected duration: ~25 minutes.
Progress artifact: .bionic/tmp/w99-nodeliv.progress
Suites: tests/widget.test.sh'

REPO=$(make_repo r10w yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_NO_DELIVERABLE" "w99-nodeliv")"

expect_eq "a dispatch whose brief names no deliverable is REFUSED" "deny" "$GATE_VERDICT"
expect_eq "the refusal's stdout is ONE deny verdict and nothing else" "1" \
  "$(printf '%s\n' "$GATE_OUT" | /usr/bin/grep -c . || true)"
expect_contains "the refusal is phrased as a refusal, in the renderer's one line" \
  "bionic: dispatch refused — " "$GATE_ERR"
expect_contains "the refusal names the field that is missing" "names no deliverable" "$GATE_ERR"
expect_contains "the refusal shows a label that lifts one" "Expected artifact:" "$GATE_ERR"
expect_contains "the refusal names the waiver escape verbatim" "Deliverable-waiver:" "$GATE_VERR"
# The wrong fix would be the environment attestation's — this refusal is a
# different one and must not send the operator to re-run the probe.
expect_absent "the refusal does not name the attestation fix command" "preflight-probe.sh" "$GATE_ERR$GATE_REASON"
expect_status "a refused dispatch writes no roster row" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

# ---- deliverable PRESENT: wholly unaffected ----
REPO=$(make_repo r10w2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-hasdeliv")"
expect_status "a brief that names a deliverable is not touched by the wall" "0" "$GATE_ST"
expect_absent "…and prints no refusal" "BLOCKED" "$GATE_ERR"
expect_status "…and is journalled as before" "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ---- progress absence stays WARN-ONLY: only the deliverable escalated ----
BRIEF_NO_PROGRESS='Your task: build the widget.
Expected artifact: .bionic/docs/record/w99-noprog.txt
Expected duration: ~25 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10w3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_NO_PROGRESS" "w99-noprog")"
expect_status "an absent PROGRESS path still passes — only the deliverable escalated" "0" "$GATE_ST"
expect_contains "…and is still warned" "progress" "$GATE_ERR"
expect_absent "…and is never phrased as a refusal" "BLOCKED" "$GATE_ERR"

# ---- the waiver: refusal becomes a warning that echoes the reason ----
BRIEF_WAIVED='Your task: answer one question from the tree; nothing durable is produced.
Deliverable-waiver: read-only reconnaissance, the answer is the report itself
Expected duration: ~10 minutes.
Progress artifact: .bionic/tmp/w99-waived.progress
Suites: tests/widget.test.sh'

REPO=$(make_repo r10w4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_WAIVED" "w99-waived")"
R10W4=$(roster_path "$REPO" "$SID_A")
ROW=$(roster_nth_row "$R10W4" 1)

expect_status "an in-brief waiver converts the refusal into a pass" "0" "$GATE_ST"
expect_absent "a waived dispatch prints no refusal" "BLOCKED" "$GATE_ERR"
expect_contains "the echo is a warning, not a verdict" "WARN" "$GATE_ERR"
expect_status "the waived dispatch is journalled" "1" "$(roster_rows "$R10W4")"
# The waiver excuses the refusal; it does not make the fact untrue.
expect_contains "the row still records the deliverable as absent" \
  "deliverable" "$(roster_field "$ROW" absent)"
expect_status "…and fabricates no deliverable path" "" "$(roster_field "$ROW" deliverable)"
# The waiver value must stop where the next labelled field starts.
expect_absent "the waiver reason does not swallow the field after it" \
  "10 minutes" "$(roster_field "$ROW" waiver)"

# ---- a waiver with no reason is not a waiver ----
BRIEF_EMPTY_WAIVER='Your task: do the thing.
Deliverable-waiver:
Expected duration: ~10 minutes.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10w5 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_EMPTY_WAIVER" "w99-emptywaiver")"
expect_eq "a reasonless waiver does not open the wall" "deny" "$GATE_VERDICT"
expect_contains "…and the refusal still names the escape" "Deliverable-waiver:" "$GATE_VERR"

# ---- the ordinary brief records no waiver ----
REPO=$(make_repo r10w6 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-nowaiver")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a brief that waives nothing carries an empty waiver field" \
  "" "$(roster_field "$ROW" waiver)"
expect_absent "…and no waiver is echoed for it" "waived" "$GATE_ERR"

section "S10e — the roster is per-session from birth (D-5)"

# live_session <config dir> <sid> — the CLI's session file naming a running process (this shell,
# with its start), which is what makes <sid> live to the roster prune; a transcript does not.
live_session() {
  mkdir -p "$1/sessions"
  jq -n --argjson p "$$" --arg s "$2" --arg t "$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$$" | tr -s ' ' | sed 's/ *$//')" \
    '{pid:$p, sessionId:$s, procStart:$t}' > "$1/sessions/$$.json"
}
# A, the first dispatcher, is the live foreign session when B dispatches.
live_session "$GATE_CONFIG_DIR" "$SID_A"
REPO=$(make_repo r10e yes)
write_attestation "$REPO" "$SID_A"
write_attestation "$REPO" "$SID_B"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "agent-of-A")"
run_gate "$(mk_agent_payload "$SID_B" "$REPO" "$BRIEF_FULL" "agent-of-B")"
RA=$(roster_path "$REPO" "$SID_A"); RB=$(roster_path "$REPO" "$SID_B")
expect_status "session A has its own roster file" "0" "$([ -f "$RA" ] && echo 0 || echo 1)"
expect_status "session B has its own roster file" "0" "$([ -f "$RB" ] && echo 0 || echo 1)"
expect_status "session A's roster holds only A's launch" "1" "$(roster_rows "$RA")"
expect_status "session B's roster holds only B's launch" "1" "$(roster_rows "$RB")"
expect_status "A's row is A's agent" "agent-of-A" "$(roster_field "$(roster_nth_row "$RA" 1)" name)"
expect_status "B's row is B's agent" "agent-of-B" "$(roster_field "$(roster_nth_row "$RB" 1)" name)"
expect_status "no shared single-slot roster.state was created" "1" \
  "$([ -f "$REPO/.bionic/tmp/roster.state" ] && echo 0 || echo 1)"
rm -rf "$GATE_CONFIG_DIR/sessions/$$.json" "$GATE_CONFIG_DIR/bionic/alive"   # A is not live past this section

section "S10f — dead-session rosters are pruned, LIVE foreign ones are not (D-5)"
#
# A session is live while its process runs with the start the CLI's session file
# records (payload/scripts/lib/alive.sh), the rule the attestation prune asks too. A
# transcript outlives its session, so SID_DEAD keeps one and is still dead. A live
# foreign session's roster surviving another session's dispatch is the concurrency
# per-session rosters exist for.

SID_DEAD="deadfeed-0000-4000-8000-000000000001"
SID_LIVE="1ivefeed-0000-4000-8000-000000000002"
CFG="$SANDBOX/cfg10f/.claude"
mkdir -p "$CFG/projects/-some-project"
: > "$CFG/projects/-some-project/$SID_A.jsonl"
: > "$CFG/projects/-some-project/$SID_DEAD.jsonl"
live_session "$CFG" "$SID_LIVE"

REPO=$(make_repo r10f yes)
write_attestation "$REPO" "$SID_A"
mkdir -p "$REPO/.bionic/tmp"
# THE PRUNE READS THE PREFIX, so the fixture is a prefix (tests/lib/roster-row.sh's
# `roster_row_prefix_only`, S14): what decides here is whether the FILE survives, and the
# row exists only to make the file a roster the reader recognises.
{ roster_header; roster_row_prefix_only status=intended "session=$SID_DEAD" name=ghost; } \
  > "$(roster_path "$REPO" "$SID_DEAD")"
{ roster_header; roster_row_prefix_only status=intended "session=$SID_LIVE" name=neighbour; } \
  > "$(roster_path "$REPO" "$SID_LIVE")"

GATE_CONFIG_DIR="$CFG"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
probe_env_on   # restore the file-wide sandbox, never the operator's own config dir

expect_status "the dispatch still passes while pruning" "0" "$GATE_ST"
expect_status "a DEAD session's roster is pruned" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_DEAD")" ] && echo 0 || echo 1)"
expect_status "a LIVE foreign session's roster is left untouched" "0" \
  "$([ -f "$(roster_path "$REPO" "$SID_LIVE")" ] && echo 0 || echo 1)"
expect_contains "the live foreign roster's content is unmodified" "neighbour" \
  "$(cat "$(roster_path "$REPO" "$SID_LIVE")" 2>/dev/null)"
expect_status "our own roster was written" "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"
# The prune must not reach across artifacts: the attestation files share the
# same directory and the same per-session scheme.
expect_status "the prune leaves attestations alone" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_A.state" ] && echo 0 || echo 1)"

section "S10g — a roster WRITE FAILURE is a refusal, never an admission (wave-28 T70)"
#
# TDD §7 said starts fail open and the roster was a ledger, not a wall. That was the wrong rule
# (wave-28 T70, A-orch-205 to 212): a dispatch the roster does not carry is one no later wall can
# judge, so a launch that cannot be journalled is refused in the dispatch wall's own shape and
# nothing is spawned. The row is built and appended last, after every wall has spoken, so the
# refusal leaves no row behind.

REPO=$(make_repo r10g yes)
write_attestation "$REPO" "$SID_A"
chmod 555 "$REPO/.bionic/tmp"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
chmod 755 "$REPO/.bionic/tmp"
expect_eq "an unwritable state dir REFUSES the dispatch" "deny" "$GATE_VERDICT"
expect_contains "…the detail names the roster path" "roster-${SID_A}.state" "$GATE_VERR"
expect_contains "…and the reason the append gave" "Permission denied" "$GATE_VERR"
expect_status "no roster file was left behind" "1" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo 0 || echo 1)"

finish
