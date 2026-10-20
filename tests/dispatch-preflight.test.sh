#!/bin/bash
# Tests for hooks/dispatch-preflight.sh — THE START GATE (epic-15 wave-01R).
#
# PreToolUse|Agent. Serves AC-2, and the start-side share of AC-9/AC-10.
#
# Governing design: design/orchestrator-subagent-coordination.md §4 "The start
# gate", §3.4 Starting, §7 (fail-direction table).
#
# HERMETIC. Every payload is crafted and piped straight into the script under
# test; nothing here dispatches a real Agent tool call, touches the live
# installed hooks, or depends on a live wave. Repos are throwaway git inits
# under a mktemp'd sandbox; attestations are written directly as fixtures
# (never by invoking the real preflight-probe.sh), except in the S9
# runnability check, which installs a COPY of the real producer into a
# sandboxed HOME specifically to prove its fix command executes.
#
# Usage: bash tests/dispatch-preflight.test.sh
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

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"
. "$(dirname "$0")/lib/assert.sh"
# THE NARROWING (wave-39 T44; D6, AC-2.4, A-orch-22). The verbs of hooks/session-poker.sh this suite reaches,
# directly or through the hooks and scripts it runs: arm, debt, fill-report, interval, interval-default,
# landing-report, window. Each line below is that closure: the library (every run executes it), the arm of
# each verb, the sections defining the globals they read, and each helper outside those.
reads hooks/session-poker.sh section "the library"
reads hooks/session-poker.sh section "whose run is this?"
reads hooks/session-poker.sh fn clean
reads hooks/session-poker.sh fn epoch_iso
reads hooks/session-poker.sh fn file_birth
reads hooks/session-poker.sh fn file_mtime
reads hooks/session-poker.sh fn iso_epoch
reads hooks/session-poker.sh fn iso_now
reads hooks/session-poker.sh fn line_field
reads hooks/session-poker.sh fn note
reads hooks/session-poker.sh fn now_epoch
reads hooks/session-poker.sh fn parse_seconds
reads hooks/session-poker.sh fn patrol_stamp_file
reads hooks/session-poker.sh fn poker_interval_seconds
reads hooks/session-poker.sh fn roster_window
reads hooks/session-poker.sh fn row_has_key
reads hooks/session-poker.sh fn sched_facts_state
reads hooks/session-poker.sh fn tmp_dir_ok
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/dispatch-preflight.prelude.sh"

section "§CAP — a probe's writers= refuses nothing; a plan with no line is not named (wave-28 T9, AC-2.9)"
CAP_RUN_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/run.sh"
cap_of() {  # <budget value or "-"> -> what budget_cap prints for a plan carrying that line
  local d; d="$(mktemp -d)"
  if [ "$1" = "-" ]; then printf -- '---\nx: y\n---\n' > "$d/p.plan.md"
  else printf -- '---\nparallel-budget: %s\n---\n' "$1" > "$d/p.plan.md"; fi
  ( . "$CAP_RUN_LIB" >/dev/null 2>&1; budget_cap "$d/p.plan.md" )
  rm -rf "$d"
}
require_helpers cap_of
expect_eq "§CAP.u1 budget_cap: source=user answers writers=<n>" "writers=3" "$(cap_of "writers=3 suites=2 source=user")"
expect_eq "§CAP.u2 budget_cap: source=override answers too" "writers=4" "$(cap_of "writers=4 source=override")"
expect_eq "§CAP.u3 budget_cap: source=probe answers nothing" "" "$(cap_of "writers=3 suites=2 source=probe")"
expect_eq "§CAP.u4 budget_cap: a line with no source= answers nothing" "" "$(cap_of "writers=3 suites=2")"
expect_eq "§CAP.u5 budget_cap: no line answers nothing" "" "$(cap_of -)"
expect_eq "§CAP.u6 budget_cap: the whole field, not max_writers=" "writers=2" "$(cap_of "max_writers=9 writers=2 source=user")"
expect_eq "§CAP.u7 budget_cap: a user line with no writers= answers nothing" "" "$(cap_of "suites=2 source=user")"

REPO=$(make_repo r22c yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=probe"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
s22_roster_row "$REPO" "$SID_A" "W-TWO"
expect_contains "§CAP.1 meta: the plan carries the probe's line" "parallel-budget: writers=1 suites=9 worktrees=9 test_jobs=4 source=probe" \
  "$(cat "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "§CAP.1 source=probe writers=1 with two open rows → the third dispatch is admitted" "allow" "$GATE_VERDICT"
expect_absent "§CAP.1b …no ceiling count is printed" "writers: budget=" "$GATE_ERR$GATE_VERR"
expect_absent "§CAP.1c …and nothing is said about the budget line" "parallel-budget" "$GATE_ERR$GATE_VERR"

REPO=$(make_repo r22c2 yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "§CAP.2 a line with no source= caps nothing: writers=1 and one open row → admitted" "allow" "$GATE_VERDICT"

REPO=$(make_repo r22c3 yes)
write_attestation "$REPO" "$SID_A"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
s22_roster_row "$REPO" "$SID_A" "W-TWO"
s22_roster_row "$REPO" "$SID_A" "W-THREE"
expect_absent "§CAP.3 meta: the live plan carries no parallel-budget: line" "parallel-budget" \
  "$(cat "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "§CAP.3 no line in a live plan → admitted, three rows notwithstanding" "allow" "$GATE_VERDICT"
expect_absent "§CAP.3b …and the plan is not named for want of the line" "parallel-budget" "$GATE_ERR"
expect_absent "§CAP.3c …nor is the budget listed as not checked" "not checked: budget" "$GATE_ERR$GATE_VERR"

# A KEY SPELLED ANY OTHER WAY IS NO KEY: an indented person's line reads as no line, so it caps
# nothing and is not named either.
REPO=$(make_repo r22c4 yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=user"
sed -i '' 's/^parallel-budget: /  parallel-budget: /' "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
expect_contains "§CAP.4 meta: the plan carries the indented key" "  parallel-budget: writers=1" \
  "$(cat "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "§CAP.4 an indented key reads as no key: nothing is refused on writers=1" "allow" "$GATE_VERDICT"

# §CAP-USER — A PERSON'S LIMIT STILL CAPS (wave-28 T9; D15, REQ-2 AC-2.10). The same two open
# rows that §CAP.1 admitted a third beside are refused when a person wrote the line. This is the
# paired control for §CAP.1: the fixture differs in the one word. fails-when: a third writer is
# admitted under `source=user writers=2`.

section "§CAP-USER — a person's writers= refuses the writer past it (wave-28 T9, AC-2.10)"
REPO=$(make_repo r22cu yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=2 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
s22_roster_row "$REPO" "$SID_A" "W-TWO"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "§CAP-USER.1 source=user writers=2 with two open rows → the third writer is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "§CAP-USER.1b …on the writer count" "writers: budget=2 open=2 with-this-dispatch=3" "$GATE_VERR"
expect_contains "§CAP-USER.1c …saying the cap is a person's" "That cap is a person's" "$GATE_VERR"
REPO=$(make_repo r22co yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 source=override"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "§CAP-USER.2 source=override writers=1 with one open row → REFUSED" "deny" "$GATE_VERDICT"
expect_contains "§CAP-USER.2b …on the writer count" "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"

# r22c6 — max_writers IS NOT writers. The field is read whole: `max_writers=9 writers=1`
# carries a ceiling of ONE, so one open row refuses the second dispatch (the 9-vs-3 defect,
# triage-D, at this wall's own numbers).
REPO=$(make_repo r22c6 yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "max_writers=9 writers=1 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "r22c6 max_writers=9 writers=1 with one open row → REFUSED on writers=1" "deny" "$GATE_VERDICT"
expect_contains "…naming the whole-field reading" "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"

# --- a row absent from the fresh live set is not an open one (AC-7; the
#     anti-vacuity control: the same fixture refuses while the row is live).
#     `landing-swept` is no longer consulted at all — the row's own PRESENCE in
#     THIS TURN's ListAgents answer is the only thing that opens or closes it.
REPO=$(make_repo r22d yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "r22d one LIVE row against writers=1 → refused (the control)" "deny" "$GATE_VERDICT"
R22D_ABSENT="$SANDBOX/.r22d-absent.jsonl"
mk_transcript "$R22D_ABSENT" fresh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22D_ABSENT")"
expect_status "…and the same row, absent from a fresh answer, no longer counts → passes" \
  "0" "$GATE_ST"

# --- suites: no ceiling at hand-out any more (wave-26 T8, D8). The rows that refused a
#     dispatch on an open subprocess claim, r22e and r22f, moved to §READONLY-FREE, which
#     proves the arm is gone for a writer and for a read-only role alike.

# --- NO WORKTREES CEILING (wave-28 T9; D15). A person's line that names `worktrees=1` with a
#     live tree standing still dispatches: what the ceiling stood for is asked of the disk where a
#     tree is made (`spawn-worktree.sh create`, tests/spawn-worktree.test.sh §DISK). The writer
#     cap on the same line is obeyed, so the pass is the worktrees arm's absence, not an inert line.
REPO=$(make_repo r22h yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=9 suites=9 worktrees=1 test_jobs=4 source=user"
s22_fake_tree "$REPO" "one"
s22_fake_tree "$REPO" "two"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "r22h worktrees=1 with two live trees → admitted: no worktrees ceiling" "allow" "$GATE_VERDICT"
expect_absent "r22h2 …and no tree count is printed" "worktrees: budget=" "$GATE_ERR$GATE_VERR"

# --- r22g: the wall and the Patrol count the same open rows on THIS fixture. AC-7
#     retires `landing-swept` as the wall's own signal — W-FOUR is left off the fresh
#     transcript instead. RE-AUTHORED BY T17 (epic-23 wave-20, D10): lib/patrol.sh's
#     `patrol_roster_state` used to close W-FOUR on a MET marker; it now asks
#     `roster_open_names`, which closes a name only on a sweeper ledger ack stamped after
#     its launch, so W-FOUR is closed for the Patrol's count by an ack instead.
REPO=$(make_repo r22g yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=3 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "W-ONE"
s22_roster_row "$REPO" "$SID_A" "W-TWO"
s22_roster_row "$REPO" "$SID_A" "W-THREE"
s22_roster_row "$REPO" "$SID_A" "W-FOUR"
s22_ack "$REPO" "$SID_A" "W-FOUR"
R22G_TRANSCRIPT="$SANDBOX/.r22g-live.jsonl"
mk_transcript "$R22G_TRANSCRIPT" fresh W-ONE W-TWO W-THREE
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22G_TRANSCRIPT")"
expect_eq "r22g three live rows and one absent, against writers=3 → REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…the wall counts three open" "writers: budget=3 open=3 with-this-dispatch=4" "$GATE_VERR"
# shellcheck source=/dev/null
( . "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/patrol.sh" 2>/dev/null \
  && patrol_roster_state "$REPO" "$SID_A" ) > "$SANDBOX/.r22g" 2>/dev/null
expect_contains "…and so does lib/patrol.sh's patrol_roster_state, on the same file (T17: W-FOUR closed by an ack, not a MET marker)" \
  "open=3" "$(cat "$SANDBOX/.r22g")"

# ================================== S22b: LIVE-AGENTS FRESHNESS GATES THE COUNT
# (spec AC-7, AC-8; task S5.)
#
# The predicate itself, isolated from every other S22 arm: one `status=intended` row,
# writers budget tight enough that whether it counts open decides pass vs refuse.

section "S22b: the budget count is read off the fresh live set"

# (a) the row's agent is ABSENT from a FRESH answer -> open=0, and the dispatch that
# would have been the SECOND writer (budget=1, one row not counted) is allowed.
REPO=$(make_repo r22ja yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "r1"
R22JA_T="$SANDBOX/.r22ja.jsonl"
mk_transcript "$R22JA_T" fresh W-OTHER
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22JA_T")"
expect_status "r22ja r1 absent from a fresh answer -> open=0, dispatch allowed at budget=1" \
  "0" "$GATE_ST"
expect_absent "…and no budget refusal, live-agents or otherwise" "BLOCKED" "$GATE_ERR"
expect_absent "…specifically no writers count printed" "writers:" "$GATE_ERR"

# (b) the SAME roster, repo and budget; only the answer changes to name r1 itself ->
# open=1, and the same dispatch is now the second writer against a budget of one.
REPO=$(make_repo r22jb yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "r1"
R22JB_T="$SANDBOX/.r22jb.jsonl"
mk_transcript "$R22JB_T" fresh r1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22JB_T")"
expect_eq "r22jb r1 present in the fresh answer -> open=1, REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…naming the count" "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"

# ======================== S22b-nla: A LISTAGENTS ANSWER IS NOT A PRECONDITION
# (wave-12 T1; spec D1 and principle P-A; Chris 2026-09-13 "What the hell. I don't want
# this to happen to begin with!" — AC-4.1, AC-4.2.)
#
# WHAT MOVED. Until 1.7.0 a transcript carrying no fresh ListAgents answer refused the
# WHOLE dispatch and told the orchestrator to go call the tool first. That is a chore on
# the normal path, and it asks for a fact the machine already holds: the roster. N deduped
# `status=intended` rows ARE N open writers until some reading says otherwise, so the
# count falls back to the roster and the dispatch is JUDGED rather than deferred.
#
# THE DISCRIMINATOR IS THE CEILING, NOT THE EXIT CODE. Each pair below holds the repo, the
# roster and the transcript fixed and moves ONLY the writers ceiling across N+1. A rule
# that counted 0 would pass both halves; a rule that still refused on freshness would fail
# both; only a rule that counts exactly N passes one and refuses the other.

section "S22b-nla: with no ListAgents answer the count is the open roster rows"

# (a) N=2 rows, NO answer in the transcript at all, ceiling 3 -> 2+1 = 3 fits: ALLOWED.
REPO=$(make_repo r22nla yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=3 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "n1"
s22_roster_row "$REPO" "$SID_A" "n2"
R22NLA_NONE="$SANDBOX/.r22nla-none.jsonl"
mk_transcript "$R22NLA_NONE" none
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22NLA_NONE")"
expect_status "r22nla 2 open rows, no answer, ceiling 3 -> judged against 2, ALLOWED" \
  "0" "$GATE_ST"
expect_absent "…and nothing is said about a missing live-agents answer" \
  "live-agents:" "$GATE_ERR"
expect_absent "…and no tool call is demanded of the dispatcher" \
  "call ListAgents" "$GATE_ERR"

# (b) THE SAME two rows and the same empty transcript; only the ceiling moves to 2 ->
# 2+1 = 3 passes it: REFUSED, and the count it names is the roster's own N.
REPO=$(make_repo r22nlb yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=2 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "n1"
s22_roster_row "$REPO" "$SID_A" "n2"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22NLA_NONE")"
expect_eq "r22nlb the same two rows against a ceiling of 2 -> REFUSED on the BUDGET" \
  "deny" "$GATE_VERDICT"
# THE LINE, NOT ONLY THE DETAIL. A freshness refusal carries no `bionic: ` line at all, so
# this row is what says the budget arm is the one that spoke — and, because run_gate only
# re-drives for the detail when a `bionic: ` line was printed, it is also what keeps the
# rows below from reading a GATE_VERR left over from an earlier arm.
expect_contains "…and it is the budget arm that speaks, in the one line" \
  "bionic: dispatch refused — this passes the run's writer budget" "$GATE_ERR"
expect_contains "…naming the roster count as the live-agent count" \
  "writers: budget=2 open=2 with-this-dispatch=3" "$GATE_VERR"
expect_absent "…and never asking for a ListAgents call first" \
  "call ListAgents" "$GATE_VERR"
expect_absent "…nor refusing for want of a fresh answer" "live-agents: none" "$GATE_VERR"

# (c) N IS READ, NOT ASSUMED. Three rows, same empty transcript, ceiling 3 -> open=3.
# Without this arm a hard-coded 2 would pass (a) and (b) both.
REPO=$(make_repo r22nlc yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=3 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "n1"
s22_roster_row "$REPO" "$SID_A" "n2"
s22_roster_row "$REPO" "$SID_A" "n3"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22NLA_NONE")"
expect_eq "r22nlc three open rows against a ceiling of 3 -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…on the budget, in the one line" \
  "bionic: dispatch refused — this passes the run's writer budget" "$GATE_ERR"
expect_contains "…counting three, because three is what the roster holds" \
  "writers: budget=3 open=3 with-this-dispatch=4" "$GATE_VERR"

# (d) A STALE ANSWER READS THE SAME WAY. Freshness is a property of the transcript, so a
# stale answer tells this wall nothing about any row — and telling the operator to go
# refresh it is the very chore D1 struck. Same two rows, same ceiling of 2 as (b).
REPO=$(make_repo r22nld yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=2 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "n1"
s22_roster_row "$REPO" "$SID_A" "n2"
R22NLD_STALE="$SANDBOX/.r22nld-stale.jsonl"
mk_transcript "$R22NLD_STALE" stale n1 n2
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22NLD_STALE")"
expect_eq "r22nld a STALE answer is judged against the roster too -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…on the budget, in the one line" \
  "bionic: dispatch refused — this passes the run's writer budget" "$GATE_ERR"
expect_contains "…on the budget, with the same count" \
  "writers: budget=2 open=2 with-this-dispatch=3" "$GATE_VERR"
expect_absent "…not on the staleness" "call ListAgents" "$GATE_VERR"

# (e) THE FALLBACK IS A FALLBACK, not a new rule. When the answer IS fresh it still
# decides: the same two rows, a fresh answer naming neither of them, and a ceiling of 1 —
# open=0 and the dispatch is allowed. A rule that had simply started counting every row
# would refuse here.
REPO=$(make_repo r22nle yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "n1"
s22_roster_row "$REPO" "$SID_A" "n2"
R22NLE_FRESH="$SANDBOX/.r22nle-fresh.jsonl"
mk_transcript "$R22NLE_FRESH" fresh W-OTHER
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22NLE_FRESH")"
expect_status "r22nle a FRESH answer naming neither row still closes both -> ALLOWED" \
  "0" "$GATE_ST"
expect_absent "…so no writers count is printed at all" "writers:" "$GATE_ERR"

# The paired negative: an EMPTY roster (no `status=intended` rows at all) needs no live
# reading at all, so a STALE transcript never even reaches the reader — the loop that
# would call it has nothing to iterate. The row below is what keeps the fallback in
# §S22b-nla from being read as "a stale answer makes the wall say something": with no
# rows there is nothing to count and nothing to say.
REPO=$(make_repo r22jd yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=user"
R22JD_STALE="$SANDBOX/.r22jd-stale.jsonl"
mk_transcript "$R22JD_STALE" stale r1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22JD_STALE")"
expect_status "r22jd an empty roster needs no live reading -> the same STALE transcript passes" \
  "0" "$GATE_ST"
expect_absent "…and says nothing about live-agents" "live-agents:" "$GATE_ERR"

# (e) THE CLOSING MARKER IS UNREACHABLE WHILE THE PANEL IS FRESH (wave-14 AC-3.4,
# narrowing wave-12 AC-7).
#
# WHAT THE OLD PIN SAID. AC-7 retired `landing-swept` as this wall's closing signal
# outright and pinned the retirement on the function's own body at the TOKEN level, so the
# marker could not quietly come back as a second, competing signal on some future edit.
# r22ja/r22jb pin the BEHAVIOUR — presence in the fresh live set is what opens or closes a
# row — and this arm pinned the implementation beside them.
#
# WHAT WAVE-14 NARROWS, AND WHY (D7, REQ-3). The retirement is kept whole for the case it
# was written for: WHILE THE PANEL IS FRESH THE PANEL IS THE TRUTH AND NO MARKER IS
# CONSULTED. It is lifted on the one path wave-12 left counting every `status=intended` row
# open forever — a STALE or ABSENT panel, where there is no reading to prefer and nine
# landed rows held nine writer slots for the rest of the session (§budget-markers below).
# The precedent is in this same file: the name-in-flight arm has read the same marker off
# the same roster to answer the same question since T26.
#
# SO THE PIN MOVES from "the token is absent from the body" to "the token is UNREACHABLE on
# the fresh path", and it is held by a delimited span: everything the count does when the
# panel HAS spoken for a row sits between `BEGIN fresh-panel branch` and `END fresh-panel
# branch`, and no closing reading may appear inside it. The mutation arm plants one there.
BUDGET_FN_BODY="$(sed -n '/^  budget_roster_counts() {/,/^  }$/p' "$GATE")"
expect_eq "…and the extracted span is non-empty (the pin is not vacuously true)" "1" \
  "$(printf '%s\n' "$BUDGET_FN_BODY" | /usr/bin/grep -c 'budget_roster_counts() {' || true)"
# THE NARROWING IS REAL IN BOTH DIRECTIONS. The count DOES consult the closing reading —
# once, through the one owner both roster walls share — so a body that had simply dropped
# the marker again (and taken §budget-markers red) fails here too.
expect_eq "budget_roster_counts consults the closing reading exactly once, through its one owner" "1" \
  "$(printf '%s\n' "$BUDGET_FN_BODY" | /usr/bin/grep -c 'roster_open_names' || true)"
BUDGET_FRESH_SPAN="$(printf '%s\n' "$BUDGET_FN_BODY" \
  | /usr/bin/awk '/BEGIN fresh-panel branch/, /END fresh-panel branch/')"
expect_nonempty "…and the fresh-panel branch is delimited (the span pin is not vacuous)" \
  "$BUDGET_FRESH_SPAN"
expect_eq "the fresh-panel branch consults no landing marker at all (never while FRESH)" "0" \
  "$(printf '%s\n' "$BUDGET_FRESH_SPAN" | /usr/bin/grep -cE 'landing-swept|roster_open_names' || true)"

# THE ANTI-VACUITY ARM: a doctored copy that reads a marker INSIDE the fresh-panel branch
# must fail the pin above. The doctor inserts one inert statement right after the span's own
# opening delimiter — not a comment change to the function signature, which would move the
# extractor's anchor and prove nothing.
GATE_MUT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dispatch-preflight-swept-mut.XXXXXX")"
GATE_MUT="$GATE_MUT_ROOT/dispatch-preflight.sh"
awk '
  { print }
  /---- BEGIN fresh-panel branch/ { print "        : \"$(roster_open_names \"$f\")\" # landing-swept read on the FRESH path (test-only)" }
' "$GATE" > "$GATE_MUT"
expect_eq "swept-mut meta: the doctor's re-added line landed (the anchor still matches)" "1" \
  "$(/usr/bin/grep -c 'landing-swept read on the FRESH path' "$GATE_MUT")"
BUDGET_FN_BODY_MUT="$(sed -n '/^  budget_roster_counts() {/,/^  }$/p' "$GATE_MUT")"
BUDGET_FRESH_SPAN_MUT="$(printf '%s\n' "$BUDGET_FN_BODY_MUT" \
  | /usr/bin/awk '/BEGIN fresh-panel branch/, /END fresh-panel branch/')"
expect_contains "…and the doctored fresh branch now DOES read a marker (the pin above discriminates)" \
  "roster_open_names" "$BUDGET_FRESH_SPAN_MUT"
rm -rf "$GATE_MUT_ROOT"

# ================= §budget-markers: A LANDED ROW HOLDS NO WRITER SLOT ON A DARK PANEL
# (wave-14 REQ-3, design D7; seed C18; A-orch-23.)
#
# WHAT S22b-nla LEFT. The fallback above judges a dark panel against the roster's own
# `status=intended` rows — every one of them, because nothing there asks whether a row
# FINISHED. On a wave of nine tasks that is nine writers for the rest of the session: the
# panel goes stale for one turn and the next dispatch is refused on a budget that eight
# landed rows are still holding. The roster already carries the closing fact — the
# `landing-swept/v1|…|state=MET` marker the name-in-flight arm has read since T26 — and the
# sweeper's ledger carries the other, for a row the sweep cannot verdict (a row that
# declared nothing durable stats MET vacuously).
#
# THE RULE (D7, narrowed by epic-23 wave-20 T2, D10; ADR-034 d1). A row is open iff
# `status=intended` and, WHEN THE PANEL IS STALE OR ABSENT, no ack taken after its latest
# launch closes it — `roster_open_names` (payload/scripts/lib/roster.sh), the one close
# predicate every reader calls. A landing marker closes NOTHING any more: wave-14 counted it as
# a second closing truth here, and that was one of the four readings of "is this name closed"
# that disagreed (triage-C claim 4). The ack is the one terminal state; the Patrol writes it
# once a fresh panel shows the agent gone. A FRESH panel is still the whole truth and no
# closing reading is consulted at all — that is (c).
#
# EACH ARM MOVES ONE THING. (a) and (b) share the roster, the ceiling and the stale panel and
# differ only in whether the markers are there; (b) and (c) share the markers and differ only
# in the panel's freshness; (d) and (e) share the acks and differ only in WHEN they were taken.

section "§budget-markers: a landed row holds no writer slot on a dark panel"

S22MK_NAMES="m1 m2 m3 m4 m5 m6 m7 m8 m9"
S22MK_LANDED="m1 m2 m3 m4 m5 m6 m7"

expect_nonempty "§budget-markers meta: the ack fixture read a ledger schema out of the writer" \
  "$S22_LEDGER_SCHEMA"

# (a) REVERSED BY epic-23 wave-20 T2 (REQ-10 AC-10.1, D10). Wave-14 AC-3.1 drove this arm the
# other way: nine intended rows, seven carrying a landing marker, a STALE panel and a ceiling
# of eight read open=2 and ALLOWED the dispatch. A marker without an ack is now OPEN to every
# reader alike — the sweeper and the stop wall already counted it open, so the Patrol filled
# against a slot this wall had handed out — and the same fixture is REFUSED at open=9. The
# marker-free close is (d): the same seven rows ACKED.
REPO=$(make_repo r22mka yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=9 worktrees=9 test_jobs=4 source=user"
for _n in $S22MK_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
for _n in $S22MK_LANDED; do s22_sweep "$REPO" "$SID_A" "$_n"; done
R22MK_STALE="$SANDBOX/.r22mk-stale.jsonl"
# shellcheck disable=SC2086
mk_transcript "$R22MK_STALE" stale $S22MK_NAMES
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK_STALE")"
expect_eq "r22mka nine rows, seven MET-marked and NONE acked, STALE panel, writers=8 -> REFUSED" \
  "deny" "$GATE_VERDICT"
expect_contains "…counting all nine open: a marker closes nothing" \
  "writers: budget=8 open=9 with-this-dispatch=10" "$GATE_VERR"
expect_absent "…and nothing is said about the panel's staleness" "live-agents:" "$GATE_ERR"

# (b) AC-3.2 — THE CONTROL: the same nine rows, the same stale panel and the same ceiling,
# with NO markers written. open=9 and the dispatch is refused, naming the budget — the same
# answer (a) now gives, which is the point: the markers changed nothing.
REPO=$(make_repo r22mkb yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=9 worktrees=9 test_jobs=4 source=user"
for _n in $S22MK_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK_STALE")"
expect_eq "r22mkb the same nine rows UNMARKED on the same stale panel -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…on the budget, in the one line" \
  "bionic: dispatch refused — this passes the run's writer budget" "$GATE_ERR"
expect_contains "…naming the count the roster holds" \
  "writers: budget=8 open=9 with-this-dispatch=10" "$GATE_VERR"

# (c) AC-3.3 — THE PANEL WINS WHEN IT IS FRESH. The same nine rows and the same seven
# markers as (a); only the panel changes, to a FRESH answer naming all nine as live. The
# markers say landed, the panel says working, and the panel is the truth: open=9, REFUSED.
REPO=$(make_repo r22mkc yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=9 worktrees=9 test_jobs=4 source=user"
for _n in $S22MK_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
for _n in $S22MK_LANDED; do s22_sweep "$REPO" "$SID_A" "$_n"; done
R22MK_FRESH="$SANDBOX/.r22mk-fresh.jsonl"
# shellcheck disable=SC2086
mk_transcript "$R22MK_FRESH" fresh $S22MK_NAMES
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK_FRESH")"
expect_eq "r22mkc a FRESH panel naming all nine live is not overridden by seven markers -> REFUSED" \
  "deny" "$GATE_VERDICT"
expect_contains "…counting all nine open, because the panel said so" \
  "writers: budget=8 open=9 with-this-dispatch=10" "$GATE_VERR"

# (d) THE ACK IS THE SECOND CLOSING TRUTH (REQ-3: "a landing marker or an ack"). The same
# nine rows and the same stale panel as (b), no markers at all — seven rows acked on the
# sweeper's own ledger instead. open=2, ALLOWED.
REPO=$(make_repo r22mkd yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=9 worktrees=9 test_jobs=4 source=user"
for _n in $S22MK_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
for _n in $S22MK_LANDED; do s22_ack "$REPO" "$SID_A" "$_n"; done
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK_STALE")"
expect_status "r22mkd seven rows ACKED on a stale panel, writers=8 -> ALLOWED" "0" "$GATE_ST"
expect_absent "…so no writers count is printed at all" "writers:" "$GATE_ERR"

# (e) AN ACK CLOSES THE ROW IT POSTDATES, NOT THE NAME FOREVER. Byte-for-byte (d)'s
# fixture with the acks dated BEFORE the rows were launched — the shape a name re-dispatched
# after its ack leaves behind. The ledger holds no ordering against the roster, so the
# comparison is by time, and an ack that predates the launch closes nothing: open=9, REFUSED.
REPO=$(make_repo r22mke yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=9 worktrees=9 test_jobs=4 source=user"
for _n in $S22MK_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
for _n in $S22MK_LANDED; do s22_ack "$REPO" "$SID_A" "$_n" 2026-09-01T00:00:00Z; done
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK_STALE")"
expect_eq "r22mke acks dated BEFORE the rows were launched close nothing -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…counting all nine open" \
  "writers: budget=8 open=9 with-this-dispatch=10" "$GATE_VERR"

# (f) A MARKER IS NOT A LATCH (the C1/S2 defect, in this wall's own terms). (a)'s fixture
# with every landed name DISPATCHED AGAIN below its marker: a fresh `status=intended` row
# retires the marker above it, so all nine are open once more and the ceiling of eight
# refuses. This is what makes the reading above a LATEST-CONTRACT reading and not a set.
REPO=$(make_repo r22mkf yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=9 worktrees=9 test_jobs=4 source=user"
for _n in $S22MK_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
for _n in $S22MK_LANDED; do s22_sweep "$REPO" "$SID_A" "$_n"; done
for _n in $S22MK_LANDED; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK_STALE")"
expect_eq "r22mkf a name re-dispatched below its own marker is open again -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…counting all nine open" \
  "writers: budget=8 open=9 with-this-dispatch=10" "$GATE_VERR"

# (g) retired at wave-26 T8 (D8): it proved an acked row gave its suite claim back, and
# hand-out no longer counts suite claims at all.

# (i) REQ-9 AC-9.3 AT ITS OWN NUMBERS, SUPERSEDED IN ITS CLOSING FACT by epic-23 wave-20 T2
# (REQ-10 AC-10.1, D10). EIGHT rows, a ceiling of eight writers. AC-9.3 closed six of them
# with a landing marker and ALLOWED the ninth; a marker is no close now, so six marked-but-
# unacked rows still hold their slots and the ninth is REFUSED at open=8. (i.3) below is the
# criterion's surviving half — six rows ACKED, open=2, ALLOWED — and is the close this wall
# honours.
#
# fails-when (AC-10.1): six rows MET-marked and never acked stop counting.
S22MK9_NAMES="n1 n2 n3 n4 n5 n6 n7 n8"
S22MK9_LANDED="n1 n2 n3 n4 n5 n6"
R22MK9_STALE="$SANDBOX/.r22mk9-stale.jsonl"
# shellcheck disable=SC2086
mk_transcript "$R22MK9_STALE" stale $S22MK9_NAMES

REPO=$(make_repo r22mki yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=8 worktrees=8 test_jobs=4 source=user"
for _n in $S22MK9_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
for _n in $S22MK9_LANDED; do s22_sweep "$REPO" "$SID_A" "$_n"; done
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK9_STALE")"
expect_eq "r22mki eight rows, six MET-marked and none acked, writers=8 -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "r22mki …counting all eight open" "writers: budget=8 open=8 with-this-dispatch=9" "$GATE_VERR"

# (i.2) THE CONTROL. The same eight rows and the same ceiling with no markers: open=8, the
# ninth is over — the same answer (i) gives, because the markers change nothing.
REPO=$(make_repo r22mki2 yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=8 worktrees=8 test_jobs=4 source=user"
for _n in $S22MK9_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK9_STALE")"
expect_eq "r22mki2 the same eight rows UNMARKED at the same ceiling -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "r22mki2 …naming the count the roster holds" \
  "writers: budget=8 open=8 with-this-dispatch=9" "$GATE_VERR"

# (i.3) THE ACK IS THE SECOND CLOSING TRUTH AT THESE NUMBERS TOO (AC-9.3 names both). Six of
# the eight acked on the sweeper's own ledger instead of marked: open=2, ALLOWED.
REPO=$(make_repo r22mki3 yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=8 suites=8 worktrees=8 test_jobs=4 source=user"
for _n in $S22MK9_NAMES; do s22_roster_row "$REPO" "$SID_A" "$_n"; done
for _n in $S22MK9_LANDED; do s22_ack "$REPO" "$SID_A" "$_n"; done
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MK9_STALE")"
expect_status "r22mki3 six rows ACKED at ceiling 8 -> ALLOWED" "0" "$GATE_ST"
expect_absent "r22mki3 …and no writers count is printed" "writers:" "$GATE_ERR"

# (h) THE CLOSED-SET LOOKUP DOES NOT LOSE A ROW TO ITS OWN PIPE (correctness review F8,
# wave-14 T26; `producer | grep -q` under pipefail exits 141 when grep quits early). `budget_roster_counts`'s dark-rows
# settlement asked `printf '%s\n' "$closed" | grep -qxF -- "$nm"` under this file's own
# `set -uo pipefail` (:67). `grep -q` exits at its first match; when `$closed` is large
# enough that the match leaves more queued than the pipe buffer holds, `printf` takes
# SIGPIPE, `pipefail` promotes that 141 over grep's own 0, and `|| continue` reads a name
# that WAS found as though it were not — a landed row keeps holding its writer slot.
#
# THE FIXTURE NEEDS THE FAILURE MODE, NOT A ROUND NUMBER. F8's own measurement put the
# threshold at roughly 4,000-6,000 short lines on this machine; six thousand rows, every
# one closed, is the margin this pin uses — and the first-inserted name is checked first
# against a list that also starts with it, which is the worst case (the biggest possible
# queued tail behind an early match). Built through the real roster writer
# (`roster_row_no_plan`) and the ack line `s22_ack` writes in the sweeper's own shape — ONE
# real row and ONE real ack captured with a placeholder name, then mechanically substituted
# six thousand times each, so the suite pays one writer call per shape rather than twelve
# thousand subprocess spawns for an equivalent loop. THE CLOSE IS AN ACK since epic-23
# wave-20 T2 (D10): a landing marker closes nothing, so the fixture that used to close six
# thousand rows with markers closes them the one way every reader honours.

section "§budget-markers-pipe: a closed name past the pipe buffer is still recognised"

R22MKH_N=6000
REPO=$(make_repo r22mkh yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=user"

R22MKH_F="$(roster_path "$REPO" "$SID_A")"
mkdir -p "$(dirname "$R22MKH_F")"

R22MKH_ROW_TMPL="$(roster_row_no_plan status=intended "session=$SID_A" "name=%%NM%%" \
  agent_id= launched_at=2026-09-02T00:00:00Z subagent_type=implementor model= \
  "deliverable=/tmp/d-%%NM%%" source=declared "duration=~10 minutes" progress= \
  claims= cadence= absent= waiver= "tool_use_id=t-%%NM%%")"
R22MKH_ACK_REPO="$SANDBOX/.r22mkh-ack-one"
s22_ack "$R22MKH_ACK_REPO" "$SID_A" "%%NM%%"
R22MKH_MARK_TMPL="$(cat "$R22MKH_ACK_REPO/.bionic/tmp/sweeper-$SID_A.state" 2>/dev/null)"
R22MKH_LEDGER="$REPO/.bionic/tmp/sweeper-$SID_A.state"

expect_nonempty "§budget-markers-pipe meta: the row template came from the real writer" \
  "$R22MKH_ROW_TMPL"
expect_nonempty "§budget-markers-pipe meta: the ack template came from the ledger's shape" \
  "$R22MKH_MARK_TMPL"

/usr/bin/awk -v tmpl="$R22MKH_ROW_TMPL" -v n="$R22MKH_N" '
  BEGIN {
    for (i = 0; i < n; i++) {
      nm = sprintf("f%05d", i)
      row = tmpl
      gsub(/%%NM%%/, nm, row)
      print row
    }
  }
' >> "$R22MKH_F"
/usr/bin/awk -v tmpl="$R22MKH_MARK_TMPL" -v n="$R22MKH_N" '
  BEGIN {
    for (i = 0; i < n; i++) {
      nm = sprintf("f%05d", i)
      row = tmpl
      gsub(/%%NM%%/, nm, row)
      print row
    }
  }
' >> "$R22MKH_LEDGER"

expect_eq "§budget-markers-pipe meta: the fixture really wrote six thousand roster rows" \
  "$R22MKH_N" "$(/usr/bin/grep -c "^roster-state/${ROSTER_SCHEMA_VERSION}|status=intended|" "$R22MKH_F" 2>/dev/null || echo 0)"
expect_eq "§budget-markers-pipe meta: …and six thousand acks" \
  "$R22MKH_N" "$(/usr/bin/grep -c "^${S22_LEDGER_SCHEMA}|event=ack|" "$R22MKH_LEDGER" 2>/dev/null || echo 0)"

R22MKH_STALE="$SANDBOX/.r22mkh-stale.jsonl"
mk_transcript "$R22MKH_STALE" stale f00000
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22MKH_STALE")"
expect_status "r22mkh six thousand acked rows on a stale panel, writers=1 -> ALLOWED" \
  "0" "$GATE_ST"
expect_absent "…so no writers count is printed at all" "writers:" "$GATE_ERR"

# ================= §budget-roster-one-pass: THE COUNT READS THE ROSTER ONCE, AND COUNTS THE SAME
# (epic-23 wave-32 T4; REQ-3 AC-3.1, AC-3.3; D3, ruling A-orch-3.)
#
# WHAT IT COST. §budget-markers-pipe above spent 351 s of this suite's 739 at b7b5bdbe inside one
# call to `budget_roster_counts`. Per roster row it ran a command substitution through tr, sed and
# head to take the name and searched a dedupe string that grew with every row. On the dark path it
# then ran one grep per dark name and two more processes per closed one: about 54,000 spawns for
# 6,000 rows. The read is now one awk over the roster and one over the three name lists.
#
# TWO PINS, ONE FOR EACH WAY THAT REWRITE CAN GO WRONG.
#   (a) THE BYTES. The function is extracted from the hook and driven directly, its two real
#       libraries sourced, over five planted rosters. Its stdout is compared byte for byte,
#       trailing newline included: the old settlement's `$(…)` dropped the open list's last
#       newline only when some name closed, and the caller is not the only reader of the bytes.
#       Every expected string below is what the pre-change function printed for that roster.
#   (b) THE WORK. The same function over §budget-markers-pipe's own 6,000-row roster and ledger,
#       with every tool it or its libraries spawn by name routed through a counting shim, spawns
#       at most BRC_CEIL tools. Past the ceiling the shim stops the harness, so a per-row read
#       fails here in under a second instead of after six minutes.

section "§budget-roster-one-pass: the count reads the roster once and prints the same bytes"

BRC_DIR="$SANDBOX/.brc"
mkdir -p "$BRC_DIR/fx" "$BRC_DIR/shim"
BRC_LIB="$(cd "${BIONIC_HOOKS_DIR}/../payload/scripts/lib" && pwd -P)"
BRC_FN="$BRC_DIR/fn.sh"
sed -n '/^  budget_roster_counts() {/,/^  }$/p' "$GATE" > "$BRC_FN"
expect_eq "§budget-roster-one-pass meta: the function came out of the hook whole" "1" \
  "$(/usr/bin/grep -c '^  budget_roster_counts() {' "$BRC_FN")"

# brc_harness <harness path> <function file> [shim dir] — a script that sources the two libraries
# the function reads, the hook's two constants it uses, and the function, then runs it once:
#   bash <harness> <roster> <ack ledger> <transcript>
brc_harness() {
  {
    printf '#!/bin/bash\nset -uo pipefail\n'
    printf '. %q\n. %q\n' "$BRC_LIB/agents.sh" "$BRC_LIB/roster.sh"
    printf 'ROSTER_VERSION="$ROSTER_SCHEMA_VERSION"\nACK_LEDGER_FILE="$2"\n'
    printf '. %q\n' "$2"
    printf 'export BRC_HARNESS_PID=$$\n'
    [ -z "${3:-}" ] || printf 'PATH=%q:"$PATH"\n' "$3"
    printf 'budget_roster_counts "$1" "$3"\n'
  } > "$1"
}
BRC_H="$BRC_DIR/harness.sh"
brc_harness "$BRC_H" "$BRC_FN"

# brc_run <roster> <ledger> <transcript> -> BRC_OUT, the function's stdout to the last byte.
brc_run() { BRC_OUT="$(bash "$BRC_H" "$1" "$2" "$3" 2>/dev/null; printf x)"; BRC_OUT="${BRC_OUT%x}"; }

# brc_row <roster> <name> [subagent_type] [status] — one launch row through the real writer.
brc_row() {
  roster_row_no_plan "status=${4:-intended}" "session=$SID_A" "name=$2" agent_id= \
    launched_at=2026-09-02T00:00:00Z "subagent_type=${3:-implementor}" model= \
    "deliverable=/tmp/d-$2" source=declared "duration=~10 minutes" progress= \
    claims= cadence= absent= waiver= "tool_use_id=t-$2" >> "$1"
}
# brc_ack <ledger> <name> [at] — one ack in the sweeper's own ledger shape (s22_ack's line).
brc_ack() {
  printf '%s|event=ack|at=%s|epoch=1756771200|pid=%s|session=%s|name=%s|by=human\n' \
    "$S22_LEDGER_SCHEMA" "${3:-2026-09-03T00:00:00Z}" "$$" "$SID_A" "$2" >> "$1"
}

BRC_FX="$BRC_DIR/fx"

# (a.1) A DARK PANEL OVER EVERY SHAPE THE READ SKIPS OR SETTLES. Kept: a1 (whose second row is a
# duplicate), r1 (read-only, so open but no writer), a3 (acked BEFORE its launch, so still open) and
# q.1. Skipped: a `confirmed` row, a row with an empty `name=`, a row with no `name=` at all and a
# row of another schema version. Closed by an ack: a2, -d1 (a name grep would read as an option) and
# qx1 (a name a regex q.1 would match).
roster_header > "$BRC_FX/mixed.roster"
brc_row "$BRC_FX/mixed.roster" a1
brc_row "$BRC_FX/mixed.roster" a2
brc_row "$BRC_FX/mixed.roster" r1 bionic:researcher
brc_row "$BRC_FX/mixed.roster" c1 implementor confirmed
brc_row "$BRC_FX/mixed.roster" a1
BRC_TMPL="$(brc_row /dev/stdout TMPL)"
printf '%s\n' "${BRC_TMPL/|name=TMPL|/|name=|}" >> "$BRC_FX/mixed.roster"
printf '%s\n' "${BRC_TMPL/|name=TMPL|/|}" >> "$BRC_FX/mixed.roster"
BRC_V0="${BRC_TMPL/roster-state\/${ROSTER_SCHEMA_VERSION}|/roster-state/v0|}"
printf '%s\n' "${BRC_V0/|name=TMPL|/|name=old1|}" >> "$BRC_FX/mixed.roster"
brc_row "$BRC_FX/mixed.roster" a3
brc_row "$BRC_FX/mixed.roster" -d1
brc_row "$BRC_FX/mixed.roster" q.1
brc_row "$BRC_FX/mixed.roster" qx1
brc_ack "$BRC_FX/mixed.ledger" a2
brc_ack "$BRC_FX/mixed.ledger" a3 2026-09-01T00:00:00Z
brc_ack "$BRC_FX/mixed.ledger" -d1
brc_ack "$BRC_FX/mixed.ledger" qx1
mk_transcript "$BRC_FX/mixed.jsonl" stale a1
expect_eq "§budget-roster-one-pass meta: the mixed roster holds its twelve rows and its header" "13" \
  "$(/usr/bin/awk 'END { print NR }' "$BRC_FX/mixed.roster")"
expect_contains "…one of them a row of another schema version" "roster-state/v0|status=intended|" \
  "$(cat "$BRC_FX/mixed.roster")"
brc_run "$BRC_FX/mixed.roster" "$BRC_FX/mixed.ledger" "$BRC_FX/mixed.jsonl"
expect_eq "brc-a1 dark panel: three writers open, the open names in roster order, no last newline" \
  "3"$'\n'"a1"$'\n'"r1"$'\n'"a3"$'\n'"q.1" "$BRC_OUT"

# (a.2) A FRESH PANEL DECIDES EVERY ROW AND NO ACK IS READ: a1 running stays open although it is
# acked, a2 idle closes, a3 absent closes. Nothing settled, so the list keeps its last newline.
brc_row "$BRC_FX/fresh.roster" a1
brc_row "$BRC_FX/fresh.roster" a2
brc_row "$BRC_FX/fresh.roster" a3
brc_ack "$BRC_FX/fresh.ledger" a1
mk_transcript "$BRC_FX/fresh.jsonl" fresh a1 a2:idle
brc_run "$BRC_FX/fresh.roster" "$BRC_FX/fresh.ledger" "$BRC_FX/fresh.jsonl"
expect_eq "brc-a2 fresh panel: the panel's one running row, and its last newline kept" \
  "1"$'\n'"a1"$'\n' "$BRC_OUT"

# (a.3) NO ANSWER AT ALL AND NOTHING ACKED: every row open, nothing closed, last newline kept.
brc_row "$BRC_FX/none.roster" a1
brc_row "$BRC_FX/none.roster" a2
mk_transcript "$BRC_FX/none.jsonl" none
brc_run "$BRC_FX/none.roster" "$BRC_FX/none.ledger" "$BRC_FX/none.jsonl"
expect_eq "brc-a3 no answer, no ack: both rows open, last newline kept" \
  "2"$'\n'"a1"$'\n'"a2"$'\n' "$BRC_OUT"

# (a.4) A CLOSED LIST LONGER THAN A PIPE BUFFER, its first name checked first (F8's worst case, as
# §budget-markers-pipe builds it, with long names so 320 rows pass 64 KiB): every one closes, and
# the one unacked row after them stays open.
BRC_TMPL="$(brc_row /dev/stdout '%%NM%%')"
/usr/bin/awk -v tmpl="$BRC_TMPL" -v sch="$S22_LEDGER_SCHEMA" -v sid="$SID_A" -v led="$BRC_FX/pipe.ledger" '
  BEGIN {
    pad = sprintf("%250s", ""); gsub(/ /, "x", pad)
    for (i = 0; i < 320; i++) {
      nm = sprintf("p%04d-%s", i, pad); r = tmpl; gsub(/%%NM%%/, nm, r); print r
      printf "%s|event=ack|at=2026-09-03T00:00:00Z|epoch=1756771200|pid=1|session=%s|name=%s|by=human\n", sch, sid, nm > led
    }
  }' > "$BRC_FX/pipe.roster"
brc_row "$BRC_FX/pipe.roster" z-open
mk_transcript "$BRC_FX/pipe.jsonl" stale
expect_eq "§budget-roster-one-pass meta: the pipe ledger holds more than a pipe buffer of names" "yes" \
  "$(/usr/bin/awk '{ n += length($0) + 1 } END { print (n > 65536) ? "yes" : "no" }' "$BRC_FX/pipe.ledger")"
brc_run "$BRC_FX/pipe.roster" "$BRC_FX/pipe.ledger" "$BRC_FX/pipe.jsonl"
expect_eq "brc-a4 320 closed names past the pipe buffer close, the one after them stays open" \
  "1"$'\n'"z-open" "$BRC_OUT"

# (a.5) NO ROSTER FILE: the bare zero, no newline.
mk_transcript "$BRC_FX/absent.jsonl" stale
brc_run "$BRC_FX/absent.roster" "$BRC_FX/absent.ledger" "$BRC_FX/absent.jsonl"
expect_eq "brc-a5 no roster: a bare 0" "0" "$BRC_OUT"

# (b) THE WORK CEILING over §budget-markers-pipe's 6,000 rows and 6,000 acks on its stale panel.
# The function's own absolute tool paths are routed through PATH for the count, and the shim is
# the tool it is named as. Forty is the ceiling. The one-pass read spawns nine here, five awk, three
# cut and one cat, most of them the transcript reader's and none of them per row. The per-row read it
# replaced spent five before its loop and three per row, so it passed forty at its twelfth row.
BRC_CEIL=40
cat > "$BRC_DIR/shim/_count" <<'BRCSHIM'
#!/bin/bash
printf '%s\n' "${0##*/}" >> "$BRC_COUNT_LOG"
c=0; read -r c < "$BRC_COUNT" 2>/dev/null || c=0
c=$((c + 1)); printf '%s\n' "$c" > "$BRC_COUNT"
if [ "$c" -gt "$BRC_CEIL" ]; then kill -TERM "$BRC_HARNESS_PID" 2>/dev/null; exit 1; fi
for d in /usr/bin /bin; do [ -x "$d/${0##*/}" ] && exec "$d/${0##*/}" "$@"; done
exit 127
BRCSHIM
chmod +x "$BRC_DIR/shim/_count"
for _t in awk grep sed tr head tail cat cut wc sort uniq tee; do ln -s _count "$BRC_DIR/shim/$_t"; done
sed 's#/usr/bin/##g' "$BRC_FN" > "$BRC_DIR/fn-counted.sh"
expect_eq "§budget-roster-one-pass meta: the counted copy is the whole function" "1" \
  "$(/usr/bin/grep -c '^  budget_roster_counts() {' "$BRC_DIR/fn-counted.sh")"
expect_eq "…and names no tool by an absolute path the shims cannot see" "0" \
  "$(/usr/bin/grep -c '/usr/bin/' "$BRC_DIR/fn-counted.sh")"
brc_harness "$BRC_DIR/harness-counted.sh" "$BRC_DIR/fn-counted.sh" "$BRC_DIR/shim"
printf '0\n' > "$BRC_DIR/count"; : > "$BRC_DIR/count.log"
BRC_OUT="$(BRC_COUNT="$BRC_DIR/count" BRC_COUNT_LOG="$BRC_DIR/count.log" BRC_CEIL="$BRC_CEIL" \
  bash "$BRC_DIR/harness-counted.sh" "$R22MKH_F" "$R22MKH_LEDGER" "$R22MKH_STALE" 2>/dev/null
  printf '\nrc=%s' "$?")"
BRC_SPAWNS="$(/usr/bin/awk 'END { print NR }' "$BRC_DIR/count.log")"
# r22mkh's dispatch was admitted, so the wall journalled its own launch row for w99-impl, the one
# row on this roster no ack closes. It is the one open writer, after six thousand closed names.
expect_eq "brc-b six thousand acked rows close and the admitted dispatch's own row stays open, the harness finished" \
  "1"$'\n'"w99-impl"$'\n'"rc=0" "$BRC_OUT"
if [ "${BRC_SPAWNS:-0}" -ge 1 ]; then
  ok "brc-b …the shims saw the function's tools (the ceiling below is not vacuous)"
else
  no "brc-b …the shims saw the function's tools (the ceiling below is not vacuous)" "counted 0 spawns"
fi
if [ "${BRC_SPAWNS:-0}" -le "$BRC_CEIL" ]; then
  ok "brc-b …in at most $BRC_CEIL tool spawns, whatever the roster's length"
else
  no "brc-b …in at most $BRC_CEIL tool spawns, whatever the roster's length" \
    "spawned $BRC_SPAWNS before the ceiling stopped it: $(sort "$BRC_DIR/count.log" | uniq -c | tr -s ' \n' ' ')"
fi

# ============================== S22c: A FINISHED-BUT-UNSTOPPED AGENT IS NOT A WRITER
# (spec R2, AC-27; task S16, closing the Step-5 auditor's F-1.)
#
# R2 names two departure modes — "delivered and stopped, or finished and never stopped".
# S22b counts a row open on PRESENCE, which discharges the first and misses the second:
# the harness keeps listing a teammate that finished its turn and was never TaskStop'd,
# with status `idle`, because it stays addressable (a SendMessage would resume it). Under
# presence-counting that finished agent holds a writer slot until somebody stops it —
# B-1's stuck-slot defect wearing a new coat.
#
# THE RULE. A roster row counts OPEN only when its name is present in the fresh answer
# with status `running`. Presence is still what the STOP GUARD resolves on (an idle agent
# is exactly the one you stop), and both consumers read the one parse — the budget
# through `live_agents_status`, the guard through `live_agents_has` — so they cannot
# disagree about who is listed, only about what the status means. AMBIGUITY (a name
# listed twice, exit 2) still counts OPEN: the reader could not resolve it, and spending
# a slot beats handing one out on a reading nobody could make.
#
# Every arm below holds the roster, the repo and the budget fixed and moves ONLY the
# status in the answer, so nothing but the status can explain the verdict.

finish
