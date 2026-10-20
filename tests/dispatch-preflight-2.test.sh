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
. "$(dirname "$0")/dispatch-preflight.prelude.sh"

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

section "S2 — ambiguity: repo unresolvable -> OPEN, silent"

GATE_CWD_FREE=1 run_gate "$(mk_agent_payload "$SID_A" "")"
expect_status "empty cwd exits 0" "0" "$GATE_ST"
expect_empty "empty cwd produces no stdout" "$GATE_OUT"
expect_empty "empty cwd produces no stderr" "$GATE_ERR"

# A NON-GIT CWD IS NOT THE QUESTION ANY MORE (bionic 1.4.0, spec AC-12, Decision A2).
# It used to be the whole precondition: `git rev-parse --show-toplevel` had to succeed
# or the wall exited silently, which made the wall's coverage a property of the SHELL's
# cwd rather than of the project. A dispatch from a scratch directory that nonetheless
# sat under a real `.bionic` root disarmed arming, containment and rostering at once.
#
# The question now is whether there is a PROJECT: `project_root` walks for the nearest
# real `.bionic` ancestor and `active_run` asks whether its run is open. The two rows
# below are the same non-git cwd on either side of that line, and nothing separates
# them but a `.bionic` directory above.
NONGIT="$SANDBOX/not-a-repo"; mkdir -p "$NONGIT"
run_gate "$(mk_agent_payload "$SID_A" "$NONGIT")"
expect_status "A2 non-git cwd with NO .bionic above it exits 0" "0" "$GATE_ST"
expect_empty "A2 …producing no stdout" "$GATE_OUT"
expect_empty "A2 …and no stderr" "$GATE_ERR"

# The other side: a non-git cwd INSIDE a project with an open run. The wall runs, and
# with no Patrol stamp for this session it refuses at the arming wall — the refusal
# that was unreachable from here before A2.
A2_ROOT=$(make_repo a2root yes)
rm -rf "$A2_ROOT/.git"
rm -f "$A2_ROOT/.bionic/tmp/patrol-$SID_A.state"   # unarmed: the refusal this row drives
A2_SCRATCH="$A2_ROOT/scratch/deep"; mkdir -p "$A2_SCRATCH"
write_attestation "$A2_ROOT" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$A2_SCRATCH")"
expect_eq "A2 non-git cwd WITH a .bionic root above it reaches the wall (exit 2)" "deny" "$GATE_VERDICT"
expect_contains "A2 …refusing at the arming wall, which is what the old precondition hid" \
  "Patrol" "$GATE_ERR"

section "S3 — no active wave -> inert, nothing to decide"

REPO_NOWAVE=$(make_repo r3a no)
run_gate "$(mk_agent_payload "$SID_A" "$REPO_NOWAVE")"
expect_status "no plan directory at all exits 0" "0" "$GATE_ST"
expect_empty "no plan directory produces no stdout" "$GATE_OUT"
expect_empty "no plan directory produces no stderr" "$GATE_ERR"

REPO_NOWAVE2=$(make_repo r3b yes)
# UNENGAGED, DELIBERATELY (task-engaged-session). make_repo plants the engagement marker
# with the Patrol stamp, and since this wave an ENGAGED session is walled whether or not a
# plan is on disk (AC-23, driven in S24 below). What this block claims is the older, and
# still true, half: a session that never invoked canonical-sdlc sees nothing at all. Removing
# the marker is what keeps the claim about the run predicate rather than about engagement.
rm -f "$REPO_NOWAVE2/.bionic/tmp/engaged-$SID_A.state"
# overwrite with a plan that has no ## SDLC State at all
cat > "$REPO_NOWAVE2/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md" <<'PLAN'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
---
# A plan with no SDLC State section
PLAN
run_gate "$(mk_agent_payload "$SID_A" "$REPO_NOWAVE2")"
expect_status "plan with no SDLC State section exits 0" "0" "$GATE_ST"
expect_empty "no SDLC State produces no stdout" "$GATE_OUT"
expect_empty "no SDLC State produces no stderr" "$GATE_ERR"

# even with NO attestation present, no-active-wave still passes an Agent
# dispatch — proving the wave check, not the attestation check, gates entry.
run_gate "$(mk_agent_payload "$SID_A" "$REPO_NOWAVE")"
expect_status "Agent dispatch with no wave and no attestation still exits 0" "0" "$GATE_ST"

section "S4 — active wave + payload missing session_id -> OPEN, silent (§7 table)"

REPO=$(make_repo r4 yes)
run_gate "$(mk_agent_payload "" "$REPO")"
expect_status "missing session_id in an active wave exits 0" "0" "$GATE_ST"
expect_empty "missing session_id produces no stdout" "$GATE_OUT"
expect_empty "missing session_id produces no stderr" "$GATE_ERR"

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

section "S6 — active wave + only a FOREIGN session's attestation exists -> AUTO-PROBE (AC-2)"
#
# task 4/2 (D-5): the foreign attestation is written at ITS OWN per-session filename
# (preflight-<SID_B>.state) — there is no file at all for SID_A, which is exactly what
# "foreign, however fresh, is not an attestation for this session" means once filenames
# are the primary key. That reading is UNCHANGED by R5; what changed is what follows from
# it. A foreign record is still never read as mine — the gate takes my own reading
# instead of refusing, and B's record is left exactly where it was.

REPO=$(make_repo r6 yes)
write_attestation "$REPO" "$SID_B"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "foreign-only attestation auto-probes rather than refusing" "0" "$GATE_ST"
expect_status "…and this session gets a record of its OWN, at its own filename" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_A.state" ] && echo 0 || echo 1)"
expect_status "…while the LIVE foreign session's record is untouched (D-5)" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_B.state" ] && echo 0 || echo 1)"

section "S6b — active wave + BOTH sessions hold valid attestations concurrently (AC-2)"
#
# The D-5 core case: two sessions on one repo, each with its own per-session file. Both
# dispatches pass — session B's attestation existing is neither necessary nor sufficient
# for session A's gate, and vice versa.

REPO=$(make_repo r6b yes)
write_attestation "$REPO" "$SID_A"
write_attestation "$REPO" "$SID_B"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "session A's dispatch passes with both attestations present" "0" "$GATE_ST"
expect_empty "session A's pass produces no stdout" "$GATE_OUT"
run_gate "$(mk_agent_payload "$SID_B" "$REPO")"
expect_status "session B's dispatch ALSO passes with both attestations present" "0" "$GATE_ST"
expect_empty "session B's pass produces no stdout" "$GATE_OUT"

section "S6c — the legacy single-slot file is NEVER consulted (task 4/2)"
#
# A legacy preflight.state carrying this session's own, perfectly valid-looking
# session_id= must still refuse: only the per-session filename is ever read.

REPO=$(make_repo r6c yes)
write_legacy_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "a legacy single-slot attestation is not consulted; the probe runs instead" "0" "$GATE_ST"
expect_status "…and the record that admits the dispatch is at the PER-SESSION filename" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight-$SID_A.state" ] && echo 0 || echo 1)"
# The probe prunes the legacy slot on every run — the strongest form of "never consulted"
# is that the file is not there to consult by the time the next dispatch asks.
expect_status "…the legacy slot is gone, not merely ignored" "0" \
  "$([ -f "$REPO/.bionic/tmp/preflight.state" ] && echo 1 || echo 0)"

section "S7 — active wave + attestation IS this session -> pass, verdict silent (AC-2)"
#
# "Silent" here is about the VERDICT (no BLOCKED refusal, nothing on stdout ever) — not
# absolute stderr silence, which S10c's absence warning already established is not the
# invariant. Since the unarmed-sweeper nag was deleted with the watcher (epic-16 w2 S1) a
# contract-complete fixture like this one has nothing to say on stderr either, and that is
# asserted directly below rather than left implied.

REPO=$(make_repo r7 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "matching attestation exits 0" "0" "$GATE_ST"
expect_empty "matching attestation produces no stdout (never print on the allow path)" "$GATE_OUT"
expect_absent "matching attestation prints no BLOCKED refusal on stderr" "BLOCKED" "$GATE_ERR"
expect_absent "…and says nothing about a sweeper being armed (the nag is deleted)" \
  "sweeper" "$GATE_ERR"

# forward-compatibility (A6): unknown extra fields, reordered, must still
# read the session_id BY KEY, not by position — mirrors
# preflight-probe.test.sh's own reorder case. Written at the PER-SESSION path.
REPO=$(make_repo r7b yes)
mkdir -p "$REPO/.bionic/tmp"
printf 'unknown_future_field=x\nsession_id=%s\nversion=1\nrepo=%s\n' "$SID_A" "$REPO" \
  > "$REPO/.bionic/tmp/preflight-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "reordered/extended attestation with a matching key still passes" "0" "$GATE_ST"
expect_empty "reordered/extended pass produces no stdout" "$GATE_OUT"

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

section "S9 — the fix command is runnable from a NON-REPO cwd (checklist A1)"

# The fix line now lives on the surviving refusal — a probe that FAILED — rather than on
# a missing attestation, which the gate takes for itself (S5). What A1 asks of it is
# unchanged: whatever command the refusal hands an operator has to run from wherever they
# are standing, which a repo-relative spelling does not.
REPO=$(make_repo r9 yes)
mkdir -p "$REPO/.bionic/tmp"; chmod 500 "$REPO/.bionic/tmp"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
chmod 700 "$REPO/.bionic/tmp"
# THE FIX LINE AS THE GATE ACTUALLY PRINTED IT, never a grep for the spelling we
# hope to find. The old form was `grep -oF "bash $PROBE_SRC"`, which could only ever
# yield the exact absolute command or nothing at all — so the one defect A1 exists to
# catch, a repo-relative spelling, made FIXLINE EMPTY, `bash -c ""` exited 0 with no
# stderr, and all three assertions below passed over a run that never happened. The
# extractor pinned away the property under test (.claude/rules/test-harness.md,
# "Fixture fidelity"); proven vacuous by mutation in epic-18 W3 4/2, where
# rewriting PREFLIGHT_CMD to `bash preflight-probe.sh` flipped nothing.
# Lifting the gate's own text lets a relative spelling reach the execution below.
# THE FIX TEXT IS IN THE DETAIL NOW (task 13, D-1): the user line carries the repair in
# six words and the runnable command travels with `detail`, so the extractor reads the
# verbose stream. That the extracted line still EXECUTES is what the arms below prove.
FIXLINE=$(printf '%s\n' "$GATE_VERR" | sed -n 's/.*re-run by hand: \(.*\))\..*/\1/p' | head -1)
# The extractor's own non-emptiness, positive, on the same fixture — without it the
# three assertions below are again a test of nothing (authoring rule: prove the
# extractor before asserting an absence through it).
expect_contains "a fix line was captured to execute" "preflight-probe.sh" "$FIXLINE"

# A throwaway HOME, so executing the captured fix line cannot touch the real one. Since
# epic-17 W1 S3 the fix line resolves the probe beside the GATE rather than under $HOME, so
# the installed copy below is no longer what makes the line runnable — it stays as the
# hostile case: a stale ~/.claude/hooks/ copy that the fix line must NOT be reaching for.
RUNHOME="$SANDBOX/run9/home"
mkdir -p "$RUNHOME/.claude/hooks"
cp "$PROBE_SRC" "$RUNHOME/.claude/hooks/preflight-probe.sh"
chmod +x "$RUNHOME/.claude/hooks/preflight-probe.sh"

NONREPO_CWD="$SANDBOX/run9/nowhere"
mkdir -p "$NONREPO_CWD"

RUN9_OUT="$SANDBOX/run9.out"; RUN9_ERR="$SANDBOX/run9.err"
( cd "$NONREPO_CWD" && env -i \
    HOME="$RUNHOME" PATH="$PATH" \
    CLAUDE_CONFIG_DIR="$RUNHOME/.claude" \
    CLAUDE_CODE_SESSION_ID="$SID_A" \
    ANTHROPIC_API_KEY="sk-fixture-marker" \
    bash -c "$FIXLINE" ) >"$RUN9_OUT" 2>"$RUN9_ERR"
RUN9_ST=$?

# 127 = command not found, 126 = found but not executable — exactly the
# failure shapes a repo-relative fix command produces from a foreign cwd.
if [ "$RUN9_ST" -eq 127 ] || [ "$RUN9_ST" -eq 126 ]; then
  no "fix command runs from a non-repo cwd" "exit $RUN9_ST (not found/not executable): $(cat "$RUN9_ERR")"
else
  ok "fix command runs from a non-repo cwd"
fi
# `$RUN9_ERR` is the PATH of the capture file; these two used to pass it as the
# HAYSTACK, so they asked whether the string "/tmp/.../run9.err" contains "No such
# file or directory" — which it never can, on any run, however broken. Both were
# vacuous from birth; proven so in epic-18 W3 4/2, where pointing the fix command at
# a file that does not exist (exit 127, that exact message on stderr) flipped neither.
# The arm above already reads the CONTENTS, via `$(cat "$RUN9_ERR")`; these now do too.
RUN9_ERR_TEXT="$(cat "$RUN9_ERR")"
expect_absent "fix-command run produces no 'No such file or directory'" "No such file or directory" "$RUN9_ERR_TEXT"
expect_absent "fix-command run produces no 'command not found'" "command not found" "$RUN9_ERR_TEXT"

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

section "S10b — the compact one-line label grammar is lifted too (AC-1)"
#
# Real briefs put two labels on one line ("Expected duration: ~35 minutes.
# Progress: append to <path> per stage") — see the exemplar at
# .bionic/docs/record/w2-ac3-run.md. A line-scoped extractor would swallow the
# second label into the first's value; the span must end at the NEXT LABEL, not
# at the newline.

BRIEF_COMPACT='Task 4/4 of epic-99 wave-01; build · double · wave.
Deliverables: (1) one commit `feat(x): thing (epic-99 w1 task 4/4)`; (2) record/w99-two.txt, verbatim.
Expected duration: ~35 minutes. Progress: append to .bionic/tmp/w99-two.progress per stage.
Exit: both deliverables exist.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_COMPACT" "w99-two")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "compact grammar: the dispatch passes" "0" "$GATE_ST"
expect_contains "compact grammar: deliverable lifted from 'Deliverables:'" \
  "record/w99-two.txt" "$(roster_field "$ROW" deliverable)"
expect_contains "compact grammar: duration lifted, not swallowed by the next label" \
  "35" "$(roster_field "$ROW" duration)"
expect_absent "compact grammar: the duration value stops at the next label" \
  "Progress" "$(roster_field "$ROW" duration)"
expect_status "compact grammar: progress path lifted from a mid-line 'Progress:'" \
  ".bionic/tmp/w99-two.progress" "$(roster_field "$ROW" progress)"
# "4/4" inside the commit subject is slash-bearing but not a path; a lifted
# deliverable list containing it would mean the extractor is matching fractions.

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

section "S10L — the LIVENESS fields are lifted: cadence + the subprocess claim (6-axis A-1)"
#
# The ratified liveness contract shipped into skills/canonical-sdlc/SKILL.md
# §Dispatch in task 4/7 — "The progress-artifact path carries a `cadence`
# alongside it" and "A subprocess claim — a process pattern plus its output file
# — is conditional-required". The Step-6 six-axis review found the procedure
# layer instructing authors to declare two fields this writer had no extraction
# site for, with hooks/stop-check.sh:389 already READING `claims=` off the row
# (axis-3 FAIL: a shipped reader with no producer). These cases are the writer
# half of that closure; tests/stop-check.test.sh §8(g) drives the reader half
# over a row THIS gate really wrote.
#
# GRAMMAR, stated because it is the one place this extractor reads a value that
# is not a path and not free text: `cadence` may be introduced by a colon OR by
# whitespace alone, because the ratified sentence puts it "alongside" the
# progress path inside one sentence rather than on a labeled line of its own.
# The subprocess claim's PATTERN is the backticked/quoted run when the author
# marks one, else the text up to the first comma or arrow; the output file half
# is the path the same span carries.

BRIEF_LIVENESS='Canonical-sdlc Step 4, task 4/10 of epic-99 wave-01; build · double · wave.
Your task: the widget, behind the existing seam.
Expected artifact: .bionic/docs/record/w99-live.txt
Expected duration: ~50 minutes. Progress: .bionic/tmp/w99-live.progress, cadence ~6m.
Subprocess claim: `bash tests/run.sh` → .bionic/tmp/w99-suite.log
Exit condition: the artifact exists and the suite is green.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10L yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_LIVENESS" "w99-live")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)

expect_status "liveness brief: the dispatch passes" "0" "$GATE_ST"
expect_status "the row lifts the cadence declared beside the progress path" \
  "~6m." "$(roster_field "$ROW" cadence)"
expect_status "the row lifts the subprocess claim's PATTERN, backticks stripped" \
  "bash tests/run.sh" "$(roster_field "$ROW" claims)"
expect_status "the progress path still stops at the cadence that follows it" \
  ".bionic/tmp/w99-live.progress" "$(roster_field "$ROW" progress)"
# THE REWRITTEN ASSERTION (Step-6 critic N-2). The line here used to read
#   expect_absent "the cadence value stops at the next label" "Subprocess" …
# which certified a property that was never under threat — the span was ALWAYS
# bounded by the next label — while the real defect (a value running ON past its
# own duration token, on its own line, before any label) went undriven and the
# green masked it. The property that matters is that cadence carries the token
# and NOTHING after it; the run-on case below drives the shape the production
# writer actually emits, and this pins the no-run-on baseline exactly.
expect_status "cadence carries the duration token and no run-on (real property, N-2)" \
  "~6m." "$(roster_field "$ROW" cadence)"
expect_status "the duration is unharmed by the new labels" \
  "~50 minutes." "$(roster_field "$ROW" duration)"

# ---- THE RUN-ON case (Step-6 critic N-2, C-1/F-3 root): cadence followed by
# run-on NON-label prose on the SAME line must still lift a bounded token. This
# is the shape the production writer emitted onto the live roster
# (w2-t3-victim2: `cadence=2m) claims=…`) — the field-merge that flipped a
# visibly-alive agent to UNMET by feeding parse_seconds a value it refuses. The
# defect is NOT rescued by a following label: the run-on sits BEFORE the label,
# already inside the value. Bounded extraction stops at the first clause
# boundary (comma / closing bracket / newline), the same restraint claimpat()
# already applies to the subprocess pattern.
BRIEF_CADENCE_RUNON='Canonical-sdlc Step 4, task 4/12 of epic-99 wave-01; build · double · wave.
Your task: the widget behind the seam.
Expected artifact: .bionic/docs/record/w99-runon.txt
Expected duration: ~50 minutes.
Progress: .bionic/tmp/w99-runon.progress, cadence 2m) claims=w99-marker,/var/tmp/f3 and keep going
Exit condition: the artifact exists.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10Lrunon yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_CADENCE_RUNON" "w99-runon")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "run-on cadence: the dispatch passes" "0" "$GATE_ST"
expect_status "run-on cadence: the value is the bounded token, not the swallowed line" \
  "2m" "$(roster_field "$ROW" cadence)"
expect_absent "run-on cadence: the swallowed 'claims=' text never enters the cadence field" \
  "claims=" "$(roster_field "$ROW" cadence)"
expect_absent "run-on cadence: nor does the swallowed path" \
  "/var/tmp/f3" "$(roster_field "$ROW" cadence)"
# The same bounded discipline protects duration from a run-on sentence (A-2:
# an unreadable duration silently exempts a row from overdue notification forever).
BRIEF_DURATION_RUNON='Your task: build it.
Expected artifact: .bionic/docs/record/w99-durrunon.txt
Expected duration: ~15 minutes. Every verbatim output you quote is its own evidence, laid out.
Progress: .bionic/tmp/w99-durrunon.progress
Suites: tests/widget.test.sh'
REPO=$(make_repo r10Ldur yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_DURATION_RUNON" "w99-durrunon")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "run-on duration: the value stops at the end of its own sentence" \
  "~15 minutes." "$(roster_field "$ROW" duration)"
expect_absent "run-on duration: the following sentence never enters the field" \
  "verbatim" "$(roster_field "$ROW" duration)"

# The colon form and the unquoted comma form — the two other shapes the ratified
# sentence permits an author to write.
#
# The claim line reads `Subprocess claim:` rather than the bare `Claims:` this
# fixture used until the Step-6 critic (F-2). That bare label was withdrawn from
# the grammar because it also matched "verify every claim the report claims:" in
# an ordinary review brief and invented a subprocess from it. The two properties
# this case exists for are untouched by the respelling — a cadence introduced by
# a colon on its own line, and an unquoted pattern that stops at the comma before
# its output file — and the vocabulary it now uses is the contract's own.
BRIEF_LIVENESS2='Task 4/11 of epic-99 wave-01.
Deliverables: record/w99-b.txt
Expected duration: ~40 minutes.
Progress: .bionic/tmp/w99-b.progress
Cadence: every 5 minutes
Subprocess claim: pgrep-me-w99, output .bionic/tmp/w99-b.log
Exit: the deliverable exists.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10L2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_LIVENESS2" "w99-live2")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "the colon form of cadence lifts too" \
  "every 5 minutes" "$(roster_field "$ROW" cadence)"
expect_status "an unquoted claim pattern stops at the comma before its output file" \
  "pgrep-me-w99" "$(roster_field "$ROW" claims)"

# CONDITIONAL-REQUIRED, both directions: a brief that declares neither field
# leaves both EMPTY rather than fabricating one, and — because the subprocess
# claim is declared only when the task backgrounds a long command — its absence
# is never an absence FINDING. The whole point of the contract is that shape
# emerges from which fields are present.
REPO=$(make_repo r10L3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-noclaim")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a brief with no subprocess claim leaves claims= empty, not fabricated" \
  "" "$(roster_field "$ROW" claims)"
expect_status "a brief with no cadence leaves cadence= empty" "" "$(roster_field "$ROW" cadence)"
expect_absent "an undeclared subprocess claim is NOT an absence finding" \
  "claims" "$(roster_field "$ROW" absent)"

# THE SCAFFOLD'S OWN OPTIONAL LINE, PASTED (wave-21 T7; REQ-7, D7). The shipped scaffold
# carries `Subprocess claim: <process pattern>   # a backgrounded watcher, e.g. gh run
# watch — optional`. Pasted unfilled, the slot is guidance, exactly as an unfilled
# `Deliverable-waiver: <reason>` is: a claim lifted from it would put a pattern no process
# carries on the row, and the P2 display reads that as `live: no`, the alarm direction.
# Filled, the trailing `#` comment is the scaffold's, not the pattern's: `pgrep -f` with
# the comment glued on matches nothing. Both directions, over the scaffold line itself.
#
# fails-when: the unfilled line lifts a claim, or a filled line's claim carries the comment.
T7_CLAIM_LINE="$(scaffold_raw_line "$DISPATCH_FILE" "Subprocess claim")"
REPO=$(make_repo r10Lc1 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "${BRIEF_FULL}
${T7_CLAIM_LINE}" "w99-claim-slot")"
expect_status "r10Lc1 a brief carrying the unfilled scaffold claim line is ADMITTED" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_nonempty "r10Lc1 …and wrote its row" "$ROW"
expect_status "r10Lc1 …with no claim lifted from the slot" "" "$(roster_field "$ROW" claims)"

REPO=$(make_repo r10Lc2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "${BRIEF_FULL}
$(printf '%s\n' "$T7_CLAIM_LINE" | sed 's/<process pattern>/gh run watch 4242/')" "w99-claim-filled")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "r10Lc2 a filled scaffold claim line lifts the pattern alone, comment dropped" \
  "gh run watch 4242" "$(roster_field "$ROW" claims)"

# THE NEGATIVE DIRECTION, which is the one that was missing (Step-6 critic F-2).
# Every case above declares a liveness contract and checks it is read correctly.
# None checked the far more common brief that declares NONE and merely uses one
# of the words in prose — and both labels fabricated a declaration from it.
#
# Fabrication is not neutral noise here. Under the ratified contract
# (skills/canonical-sdlc/SKILL.md) field PRESENCE is the shape key — "shape
# emerges from which are present… adding a subprocess claim is a delegated
# command" — and a claims= value opens a `-- claimed process (P2) --` section
# whose pgrep finds nothing and prints `live: no`, the ALARM direction. So a
# brief that says "keep a steady cadence" was classified long-shape and armed a
# quiescence watcher, and one that says "verify every claim" grew a phantom
# subprocess. Both briefs below are verbatim from the critic's repro
# (.bionic/docs/record/w3-critic-repro-lift.sh, briefs C and D).
BRIEF_PROSE_CADENCE='Your task: write the report.
Deliverables: .bionic/docs/record/w99.md
Expected duration: ~40 minutes.
Progress: .bionic/tmp/w99.progress, a line per section.
Scope constraint: keep a steady cadence and do not batch the sections.
Exit: report written.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10L4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_PROSE_CADENCE" "w99-prose1")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "the word 'cadence' in ordinary prose declares no cadence" \
  "" "$(roster_field "$ROW" cadence)"
# …and the fix is not a blunt one: the fields this brief DOES declare still lift.
expect_status "…while the progress path the same brief declares still lifts" \
  ".bionic/tmp/w99.progress" "$(roster_field "$ROW" progress)"
expect_status "…and its duration" "~40 minutes." "$(roster_field "$ROW" duration)"

BRIEF_PROSE_CLAIMS='Your task: audit the report.
Deliverables: .bionic/docs/record/audit.md
Expected duration: ~20 minutes.
Progress: .bionic/tmp/audit.progress, a line per claim checked.
Scope constraint: verify every claim the report claims: proof or the label unverified.
Exit: audit written.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10L5 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_PROSE_CLAIMS" "w99-prose2")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "a brief that REVIEWS claims declares no subprocess claim" \
  "" "$(roster_field "$ROW" claims)"
expect_status "…and grows no cadence either" "" "$(roster_field "$ROW" cadence)"
expect_status "…while its own progress path is still read" \
  ".bionic/tmp/audit.progress" "$(roster_field "$ROW" progress)"

# The cadence rule stated as the rule it is: the word only declares a cadence
# where the contract puts it — beside the progress path — so the SAME word in the
# SAME brief lifts or does not lift depending on where it falls.
BRIEF_CADENCE_PLACE='Your task: build it.
Deliverables: .bionic/docs/record/w99.md
Expected duration: ~40 minutes.
Progress: .bionic/tmp/w99.progress, cadence ~9m.
Scope constraint: keep a steady cadence throughout.
Exit: built.
Suites: tests/widget.test.sh'

REPO=$(make_repo r10L6 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_CADENCE_PLACE" "w99-place")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "the cadence beside the progress path is the one that counts" \
  "~9m." "$(roster_field "$ROW" cadence)"

section "S10d — rows APPEND; the roster is a ledger, not a slot"

REPO=$(make_repo r10d yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "first-agent")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "second-agent")"
R10D=$(roster_path "$REPO" "$SID_A")
expect_status "two dispatches leave two rows" "2" "$(roster_rows "$R10D")"
expect_status "the first row survives the second dispatch" "first-agent" "$(roster_field "$(roster_nth_row "$R10D" 1)" name)"
expect_status "the second row is the second dispatch" "second-agent" "$(roster_field "$(roster_nth_row "$R10D" 2)" name)"

section "S10e — the roster is per-session from birth (D-5)"

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

section "S10f — dead-session rosters are pruned, LIVE foreign ones are not (D-5)"
#
# Same liveness rule task 4/2 established for the attestation
# (hooks/preflight-probe.sh: a session is live iff its transcript still exists
# somewhere under CLAUDE_CONFIG_DIR/projects). A live foreign session's roster
# surviving another session's dispatch IS the concurrency D-5 exists for.

SID_DEAD="deadfeed-0000-4000-8000-000000000001"
SID_LIVE="1ivefeed-0000-4000-8000-000000000002"
CFG="$SANDBOX/cfg10f/.claude"
mkdir -p "$CFG/projects/-some-project"
: > "$CFG/projects/-some-project/$SID_LIVE.jsonl"
: > "$CFG/projects/-some-project/$SID_A.jsonl"
# SID_DEAD deliberately has NO transcript anywhere.

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
