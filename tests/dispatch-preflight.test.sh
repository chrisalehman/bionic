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
#   dispatch-preflight-4.test.sh   §Q … §RECORDER, and S10h, which §RECORDER reads
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
. "$(dirname "$0")/lib/assert.sh"
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

section "S22c: an idle (finished, unstopped) teammate does not count open"

# (a) THE HEADLINE. Byte-for-byte r22jb's fixture — one row `r1`, writers=1, r1 named in
# a fresh answer — with `running` changed to `idle`. r22jb REFUSES. This must pass.
REPO=$(make_repo r22ka yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "r1"
R22KA_T="$SANDBOX/.r22ka.jsonl"
mk_transcript "$R22KA_T" fresh "r1:idle"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KA_T")"
expect_status "r22ka an idle (finished, unstopped) teammate does NOT count open" "0" "$GATE_ST"
expect_absent "…so no writers refusal is printed at all" "writers:" "$GATE_ERR"
expect_absent "…and the dispatch is not blocked" "BLOCKED" "$GATE_ERR"

# The meta-row: the fixture really did say idle. Without it, a builder that silently
# dropped the status and wrote nothing would make (a) pass for the wrong reason.
expect_contains "r22ka meta: the answer body names r1 idle, not running" \
  "r1 [8895ce]  ·  bionic:implementor  ·  idle" "$(cat "$R22KA_T")"

# (b) THE DISCRIMINATING PAIR, on one answer. Two rows, one idle and one running,
# against writers=1: the count is 1, not 2 and not 0. A rule that ignored status would
# say 2; a rule that stopped counting altogether would say 0 and let this through.
REPO=$(make_repo r22kb yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "r1"
s22_roster_row "$REPO" "$SID_A" "r2"
R22KB_T="$SANDBOX/.r22kb.jsonl"
mk_transcript "$R22KB_T" fresh "r1:idle" "r2:running"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KB_T")"
expect_eq "r22kb one idle row and one running row against writers=1 -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…counting the running one ONLY: open=1, not open=2" \
  "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"

# (c) AMBIGUITY IS STILL OPEN, and it is the arm that keeps (a) from being read as
# "anything the reader cannot call running is free". The same name twice — two sessions
# in one root launching same-named agents — is unresolvable, so the slot is spent.
REPO=$(make_repo r22kc yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "r1"
R22KC_T="$SANDBOX/.r22kc.jsonl"
mk_transcript "$R22KC_T" fresh "r1:idle" "r1:idle"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KC_T")"
expect_eq "r22kc the same name listed TWICE is unresolvable -> still counted open" \
  "deny" "$GATE_VERDICT"
expect_contains "…open=1 on the safe direction, even though neither copy reads running" \
  "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"

# (d) A STALE `idle` IS NOT AN `idle` (wave-12 T1, D1). The status arms above all read a
# FRESH answer. On a stale one the word says nothing about now, so the row is not closed
# by it — it falls back to the roster and counts OPEN, and the BUDGET is what refuses.
# Before D1 this arm refused on the staleness itself and never reached a count; the
# outcome is the same exit, for a reason the operator can act on without a tool call.
REPO=$(make_repo r22kd yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "r1"
R22KD_T="$SANDBOX/.r22kd.jsonl"
mk_transcript "$R22KD_T" stale "r1:idle"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KD_T")"
expect_eq "r22kd a STALE idle does not close the row -> REFUSED on the budget" "deny" "$GATE_VERDICT"
expect_contains "…by the budget arm, not by the staleness" \
  "bionic: dispatch refused — this passes the run's writer budget" "$GATE_ERR"
expect_contains "…counting the row the stale answer could not speak for" \
  "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"

# (e) THE REAL ANSWER, byte-verbatim. Everything above is synthesized from the harness's
# shape; this arm drives the shipped hook against a body captured from this project's own
# orchestrator session at 2026-09-05T03:07:41.801Z — `s6-stop-resolution` idle beside
# `s5-dispatch-budget` running, the moment S6 had delivered its report and had not yet
# been stopped (the stop is recorded at 03:07:46.215Z, five seconds later). Both names
# are on the roster and the budget is two: presence-counting fills it and refuses; the
# rule under test counts the one running writer and lets the dispatch through.
REPO=$(make_repo r22ke yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=2 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "s6-stop-resolution"
s22_roster_row "$REPO" "$SID_A" "s5-dispatch-budget"
# THE BODY IS THE CORPUS'S OWN LINE, not a copy of it (S17). This section is about ONE
# REAL ANSWER — the 03:07:41.801Z one, an idle writer beside a running one — and that
# answer is committed at tests/fixtures/claude/listagents-answers.jsonl as the line
# `LIVE_ANSWER_MIXED_LINE` names. Read back rather than re-typed, so the two names below
# and the two names on the roster rows above cannot drift apart from it.
R22KE_BODY="$(live_answer_content "$LIVE_ANSWER_MIXED_LINE")"
R22KE_T="$SANDBOX/.r22ke.jsonl"
{
  entry_prompt      "2026-09-05T03:07:30.000Z" "land S6"
  entry_tool_use    "2026-09-05T03:07:40.000Z" "ListAgents" "toolu_01Amv2QjVrsFDp5uVfKEowty"
  entry_tool_result "2026-09-05T03:07:41.801Z" "toolu_01Amv2QjVrsFDp5uVfKEowty" "$R22KE_BODY"
} > "$R22KE_T"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KE_T")"
expect_status "r22ke the real 03:07:41.801Z answer: one finished writer, one working -> allowed at writers=2" \
  "0" "$GATE_ST"
expect_absent "…no writers refusal, because open=1 and not 2" "writers:" "$GATE_ERR"

# The paired direction on the SAME real body: at writers=1 the one genuinely running
# writer fills the budget, and the refusal names open=1. This is what keeps (e) from
# passing against a gate that had simply stopped counting.
REPO=$(make_repo r22kf yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "s6-stop-resolution"
s22_roster_row "$REPO" "$SID_A" "s5-dispatch-budget"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KE_T")"
expect_eq "r22kf …and at writers=1 the still-running one alone fills it -> REFUSED" \
  "deny" "$GATE_VERDICT"
expect_contains "…open=1, the finished agent uncounted" \
  "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"

# (f) retired at wave-26 T8 (D8): hand-out no longer counts `claims=` rows, so there is no
# suite allowance left to ride the predicate. (g) and (i) below are unchanged.

# (g) FAIL-CLOSED ON AN UNKNOWN STATUS WORD (S19, Step-5 auditor F-13). S16 counted a row
# open only on the exact word `running`, which made every OTHER word — a renamed status, a
# third one the harness starts printing — read as CLOSED and hand out a writer slot. That is
# fail-OPEN, and it sat inside the same function whose ambiguity arm (c) is deliberately
# fail-CLOSED. The rule is now `open unless the harness said idle`, owned by
# `live_row_open` in payload/scripts/lib/agents.sh, and these two arms are the inversion.
#
# `starting` is deliberately a word the measured corpus does NOT contain: 26 captured
# answers, 44 teammate rows, two words only — 33 `running`, 11 `idle`. The predicate must
# not depend on that staying true.
REPO=$(make_repo r22kh yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=1 suites=9 worktrees=9 test_jobs=4 source=user"
s22_roster_row "$REPO" "$SID_A" "r1"
R22KH_T="$SANDBOX/.r22kh.jsonl"
mk_transcript "$R22KH_T" fresh "r1:starting"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KH_T")"
expect_eq "r22kh an UNKNOWN third status word still counts OPEN -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…open=1, the slot kept on a reading nobody has seen before" \
  "writers: budget=1 open=1 with-this-dispatch=2" "$GATE_VERR"
expect_contains "r22kh meta: the answer body really says starting, not running" \
  "r1 [8895ce]  ·  bionic:implementor  ·  starting" "$(cat "$R22KH_T")"

# THE DISCRIMINATING PAIR for (g), on one roster and one budget: the SAME row read `idle`
# is let through. Without it, r22kh would pass against a gate that had gone back to
# counting presence — and presence is exactly what S16 removed.
mk_transcript "$R22KH_T" fresh "r1:idle"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" "$R22KH_T")"
expect_status "…while the SAME row read idle is still not open -> allowed" "0" "$GATE_ST"
expect_absent "…and prints no writers refusal" "writers:" "$GATE_ERR"

# (h) retired at wave-26 T8 (D8) with (f): the suite allowance it followed is gone.

# (i) THE PREDICATE HAS ONE OWNER, and this gate is not a second copy of it. The inline
# `status = running` test S16 wrote lived here; S19 deleted it. A grep is the honest
# observable for "the rule is not spelled twice", and the anti-vacuity arm below proves the
# grep can see the string it is looking for.
expect_eq "the hook carries no inline status-word predicate of its own" "0" \
  "$(/usr/bin/grep -c '"\$la_st" = "running"' "$GATE")"
expect_eq "…and asks the library's one predicate by name instead" "1" \
  "$( [ "$(/usr/bin/grep -c 'live_row_open' "$GATE")" -ge 1 ] && echo 1 || echo 0 )"
S22K_MUT="$SANDBOX/.s22k-inline-mut.sh"
{ printf '# doctored: %s\n' '[ "$la_st" = "running" ] && row_open=yes'; cat "$GATE"; } > "$S22K_MUT"
expect_eq "…and the grep really can see that string when it is there (not vacuous)" "1" \
  "$(/usr/bin/grep -c '"\$la_st" = "running"' "$S22K_MUT")"

# ============================================ S23: THE ORCHESTRATOR-IN-WORKTREE ARM
# (spec AC-14; handoff 2.5.)
#
# A worktree is LEASED to the writer it was spawned for. A main-thread dispatch made
# from inside one is an orchestrator that has moved into a writer's tree — the roster
# it appends to hangs off the MAIN checkout (project_root maps the worktree back), so
# the dispatch is journalled in one address space while its author works in another,
# and the tree's own lease has no row that accounts for the orchestrator. The refusal
# names the main checkout, which is where dispatch authority sits.
#
# AN AGENT CONTEXT IS ALLOWED, and that is the whole point of the arm: a writer
# dispatched INTO a tree works there by construction, and refusing it would refuse the
# arrangement the wave is built on. Two spellings mark an agent context — the guard's
# BIONIC_HOOK_CHANNEL on the settings channel, and the payload's own `agent_id`, which
# the harness sets for a dispatched agent — and either one is enough. (T7b: was
# `agent_type`, which a `claude --agent` main session carries too — critic C4.)

section "S23: a main-thread dispatch from inside a linked worktree"

REPO=$(make_repo r23a yes)
write_attestation "$REPO" "$SID_A"
git -C "$REPO" worktree add -q -b wt/one "$REPO/.worktrees/one" >/dev/null 2>&1
S23_TREE="$REPO/.worktrees/one"
# PHYSICAL, because every root this gate prints is: project_root resolves with `pwd -P`
# and the sandbox sits under macOS's /var -> /private/var link. Comparing the refusal's
# main-checkout line against the LOGICAL fixture path would fail on the link alone,
# which is the same trap tests/canonical-sdlc-governing-skill.test.sh's make_project
# documents.
S23_MAIN=$( cd "$REPO" && pwd -P )

run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_status "r23a a dispatch from the MAIN checkout passes (the control)" "0" "$GATE_ST"

# A DISTINCT NAME from r23a's, for the reason r23c states below and this arm now needs too:
# r23a was ALLOWED and journalled `w99-impl`, and with the arms pooled (wave-14 REQ-8) a
# re-used name would add the name-in-flight fault to the lease fault and refuse for both at
# once. The lease wall is what this arm is about.
run_gate "$(mk_agent_payload "$SID_A" "$S23_TREE" "$BRIEF_FULL" "w99-impl-b")"
expect_eq "r23b the same dispatch from inside the linked worktree is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…naming the main checkout" "main checkout: $S23_MAIN" "$GATE_VERR"
expect_contains "…and the tree it was made from" "$S23_TREE" "$GATE_VERR"

# The settings-channel spelling of an agent context.
# A DISTINCT NAME per dispatch from here (T22): r23a's ALLOWED dispatch journalled a
# `w99-impl` row on this repo's roster, and a name with an open row cannot be handed out
# twice — which is the arm under test in §T22-name-in-flight, not this section's subject.
# A READ-ONLY TYPE (wave-20 T7): an agent context may launch only a read-only role (Δ12),
# and this arm's subject is the lease wall, not the class.
GATE_ENV="$GATE_ENV BIONIC_HOOK_CHANNEL=agent-context"
run_gate "$(mk_agent_payload "$SID_A" "$S23_TREE" "$BRIEF_FULL" "w99-impl-c" "claude-sonnet-5" \
             "$S5_LIVE_TRANSCRIPT" "bionic:researcher")"
GATE_ENV="${GATE_ENV% BIONIC_HOOK_CHANNEL=agent-context}"
expect_status "r23c the same dispatch in an agent context (BIONIC_HOOK_CHANNEL) is allowed" "0" "$GATE_ST"

# The payload spelling IS `agent_id` (T7b; critic C4). A dispatched agent's payload carries
# it (T12 measured it on every nested payload); `agent_type` alone is a `claude --agent` main
# session — the orchestrator — and the lease wall is about the orchestrator.
S23_AGENT_PAYLOAD=$(mk_agent_payload "$SID_A" "$S23_TREE" "$BRIEF_FULL" "w99-impl-d" "claude-sonnet-5" \
  "$S5_LIVE_TRANSCRIPT" "bionic:researcher" | jq '. + {agent_id:"a23d-0123456789abcdef", agent_type:"senior-implementor"}')
run_gate "$S23_AGENT_PAYLOAD"
expect_status "r23d …and so is one whose payload carries agent_id (T7b: was agent_type alone)" "0" "$GATE_ST"
# r23e: agent_type WITHOUT agent_id, from inside the tree — an --agent main session sitting
# in a writer's lease. It is the orchestrator, so the lease wall refuses it as it refuses r23b.
S23_MAIN_AGENT=$(mk_agent_payload "$SID_A" "$S23_TREE" "$BRIEF_FULL" "w99-impl-e" "claude-sonnet-5" \
  "$S5_LIVE_TRANSCRIPT" "bionic:researcher" | jq '. + {agent_type:"senior-implementor"}')
run_gate "$S23_MAIN_AGENT"
expect_eq "r23e (T7b: was allowed) an agent_type-only payload in the tree is the orchestrator — REFUSED" \
  "deny" "$GATE_VERDICT"
expect_contains "r23e …by the lease wall, naming the main checkout" "main checkout: $S23_MAIN" "$GATE_VERR"

section "S24 — THE ENGAGEMENT SWITCH (AC-5, AC-13, AC-14, AC-23)"
#
# The switch this wave adds, driven in both directions on ONE fixture so neither half can
# be true by accident. Every silence below sits beside the positive it is the negation of:
# the same repo, the same payload, the marker the only difference.

S24_REPO=$(make_repo r24 yes)
# An attestation up front (AC-25 / r24e): without one, r24a's dispatch auto-probes and
# WRITES it as a side effect, adding a one-time "environment check was run
# automatically" advisory line that r24e's later re-dispatch — now that the
# attestation already exists — does not repeat. That made the two refusals differ
# for a reason that had nothing to do with engagement, the thing r24e is testing;
# writing it up front, as every other fixture in this file does, removes the
# confound so "byte-identical" tests only the engagement switch.
write_attestation "$S24_REPO" "$SID_A"
S24_MARK="$S24_REPO/.bionic/tmp/engaged-$SID_A.state"
# THE MARKER'S BODY IS KEPT, so (e) restores the same binding make_repo wrote rather than an
# empty marker — which is the unbound state, a different session (wave-23-fixit-1810 T1).
S24_MARK_BODY="$SANDBOX/r24-marker-body"
cp "$S24_MARK" "$S24_MARK_BODY"

# (a) ENGAGED — the positive. A dispatch whose brief carries no deliverable is refused
# exactly as it was before this wave existed.
S24_BARE='Go and do the thing. No contract fields at all.'
run_gate "$(mk_agent_payload "$SID_A" "$S24_REPO" "$S24_BARE")"
# T17: this brief trips SEVERAL brief-shape arms, so its one refusal is a deny verdict
# on stdout with exit 0, not exit 2. The refusal itself — and every assertion below — is
# unchanged; only the channel the wall blocks on is.
expect_eq "r24a engaged: a dispatch with no deliverable is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…at the absent-deliverable wall" "Expected artifact" "$GATE_ERR"
S24_REFUSAL="$GATE_ERR"

# (b) THE SAME payload, the SAME repo, the marker removed -> nothing at all (AC-5).
rm -f "$S24_MARK"
run_gate "$(mk_agent_payload "$SID_A" "$S24_REPO" "$S24_BARE")"
expect_status "r24b unengaged: the same dispatch exits 0" "0" "$GATE_ST"
expect_empty "r24b …with no stdout" "$GATE_OUT"
expect_empty "r24b …and no stderr" "$GATE_ERR"

# (c) A SYMLINK at the marker path reads as ABSENT, never followed (AC-4's direction, at
# this gate). The link points at a real regular file, so only the -L refusal in
# `engaged_session` can produce this silence.
S24_DECOY="$SANDBOX/r24-decoy-marker"
printf 'plan=none\n' > "$S24_DECOY"
ln -s "$S24_DECOY" "$S24_MARK"
run_gate "$(mk_agent_payload "$SID_A" "$S24_REPO" "$S24_BARE")"
expect_status "r24c a SYMLINK at the marker path exits 0" "0" "$GATE_ST"
expect_empty "r24c …with no stdout" "$GATE_OUT"
expect_empty "r24c …and no stderr" "$GATE_ERR"
rm -f "$S24_MARK"

# (d) A FOREIGN session's marker is not this session's (AC-4).
: > "$S24_REPO/.bionic/tmp/engaged-$SID_B.state"
run_gate "$(mk_agent_payload "$SID_A" "$S24_REPO" "$S24_BARE")"
expect_status "r24d another session's marker exits 0" "0" "$GATE_ST"
expect_empty "r24d …and says nothing" "$GATE_ERR"
rm -f "$S24_REPO/.bionic/tmp/engaged-$SID_B.state"

# (e) THE REFUSAL TEXT IS BYTE-UNCHANGED for an engaged session (AC-13, AC-14). Restoring
# the marker must reproduce (a) exactly — not merely refuse, but refuse in the same words.
cp "$S24_MARK_BODY" "$S24_MARK"
run_gate "$(mk_agent_payload "$SID_A" "$S24_REPO" "$S24_BARE")"
expect_eq "r24e re-engaged: the refusal is byte-identical to r24a" "$S24_REFUSAL" "$GATE_ERR"

# META (spec AC-25): r24e must not be vacuous the way it was before this task — a
# DOCTORED refusal (one byte changed) has to make it FAIL. Run in a subshell so the
# probe's own local ok/no/PASS/FAIL shadow the real ones and never touch this suite's
# actual counts; only the verdict below is a real assertion.
(
  PASS=0; FAIL=0; TOTAL=0
  ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); }
  no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); }
  expect_eq "probe" "$S24_REFUSAL" "${S24_REFUSAL}Z"
  exit "$FAIL"
)
if [ $? -ne 0 ]; then
  ok "r24e meta: a doctored refusal (one byte changed) makes expect_eq report a failure"
else
  no "r24e meta: a doctored refusal did NOT make expect_eq fail — the assertion is vacuous"
fi

# ---------- ENGAGED WITH NO PLAN ON DISK (AC-23) ----------
#
# The half of the ruling that is not "silence": engagement decides WHETHER a hook acts,
# the plan decides WHAT. A run's Step 0 precedes its own plan, and the walls that need no
# plan are owed from the first dispatch.
S24_NOPLAN=$(make_repo r24np yes)
rm -rf "$S24_NOPLAN/.bionic/docs"

# the Patrol checkpoint is plan-free: no stamp, no dispatch.
rm -f "$S24_NOPLAN/.bionic/tmp/patrol-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$S24_NOPLAN")"
expect_eq "r24f engaged, no plan, no stamp -> REFUSED at the Patrol checkpoint" "deny" "$GATE_VERDICT"
expect_contains "…naming the Patrol" "Patrol" "$GATE_ERR"

# the deliverable wall is plan-free too: stamp back, brief stripped.
printf 'patrol-stamp/v1|at=%s|session=%s|verb=arm\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SID_A" > "$S24_NOPLAN/.bionic/tmp/patrol-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$S24_NOPLAN" "$S24_BARE")"
# T17: this brief trips SEVERAL brief-shape arms, so its one refusal is a deny verdict
# on stdout with exit 0, not exit 2. The refusal itself — and every assertion below — is
# unchanged; only the channel the wall blocks on is.
expect_eq "r24g engaged, no plan, no deliverable -> REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…at the absent-deliverable wall" "Expected artifact" "$GATE_ERR"

# the BUDGET wall is plan-bound: it measures against a ceiling only a plan can declare,
# so with no plan it says nothing. Driven with a contract-complete brief so the walls
# above have nothing to say, and the silence is the budget wall's own.
run_gate "$(mk_agent_payload "$SID_A" "$S24_NOPLAN")"
expect_status "r24h engaged, no plan, a complete brief -> passes" "0" "$GATE_ST"
expect_absent "r24h …and the budget wall stays silent" "parallel-budget" "$GATE_ERR"

# THE PAIRED POSITIVE, so r24h is not silence-by-vacuity: the same dispatch against a plan
# whose ceiling is already full IS refused by that wall.
S24_BUDGET=$(make_repo r24bw yes)
S24_PLAN="$S24_BUDGET/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
awk 'NR==2 { print "parallel-budget: writers=0 suites=4 worktrees=32 test_jobs=8 source=user" } { print }' \
  "$S24_PLAN" > "$S24_PLAN.tmp" && mv "$S24_PLAN.tmp" "$S24_PLAN"
run_gate "$(mk_agent_payload "$SID_A" "$S24_BUDGET")"
expect_eq "r24i the same brief against a FULL budget is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "…by the budget wall" "writers" "$GATE_VERR"

# and the same full budget with NO plan-free failure and NO marker is silent.
rm -f "$S24_BUDGET/.bionic/tmp/engaged-$SID_A.state"
run_gate "$(mk_agent_payload "$SID_A" "$S24_BUDGET")"
expect_status "r24j …and unengaged, that same full budget decides nothing" "0" "$GATE_ST"
expect_empty "r24j …silently" "$GATE_ERR"

setup_section "S25 — active_run -> session_run (wave-session-bound-run S5)"
#
# THE CONTRACT UNDER TEST (design ledger AC-1/AC-3/AC-6). `PLAN` used to come from
# `active_run "$REPO"` — the newest open plan in the root, with no session input at
# all. It now comes from `session_run "$REPO" "$PAYLOAD_SID"`: a session BOUND to a
# plan (`.bionic/tmp/engaged-<sid>.state` carrying `plan=<path>`) is gated on that
# plan and that plan alone, whatever else is open in the root; a session bound to a plan
# that has since closed is treated as having no open run at all, and says that too. An
# UNBOUND session (the marker empty) still resolves to the newest plan, and since
# wave-23-fixit-1810 (REQ-1, D1) that plan is announced and never acted on: the gate prints
# lib/run.sh's one advisory, judges the dispatch with no plan, and refuses a writer with
# the bind instruction — never with the other plan's budget or step (S25b).
#
# s25_bind <repo> <sid> <plan-abs-path> — overwrites the marker s25_repo leaves (empty =
# unbound) with a real binding, under the same two-line shape
# hooks/engage.sh writes (spec §Session binding), via the real `bind_plan` (S11,
# tests/lib/bound-marker.sh).
s25_bind() {
  bound_marker "$1" "$2" "$3"
}

# s25_repo <name> <budget-a> <budget-b> -> sets the globals S25_REPO / S25_PLAN_A
# / S25_PLAN_B (a plain call, never `$(...)` — a command substitution runs in a
# subshell, and every assignment here would be lost the instant it returned). A
# and B are the ONLY open plans in the root — make_repo's own default plan is
# removed — and A is older by mtime, so an UNBOUND session's fallback is
# decisively B.
s25_repo() {
  local name="$1" budget_a="$2" budget_b="$3"
  local repo; repo=$(make_repo "$name" yes)
  rm -f "$repo/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
  # UNBOUND TO START: make_repo bound its sessions to the plan just removed, which would
  # read `bound-closed`. Each section below binds what it means to bind.
  local _usid
  for _usid in "${SID_A:-}" "${SID_B:-}"; do
    [ -n "$_usid" ] && unbound_marker "$repo" "$_usid" empty
  done
  S25_REPO="$repo"
  S25_PLAN_A="$repo/.bionic/docs/plans/epic-99-test/plan-a.plan.md"
  S25_PLAN_B="$repo/.bionic/docs/plans/epic-99-test/plan-b.plan.md"
  cat > "$S25_PLAN_A" <<PLANA
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
parallel-budget: $budget_a
---

## SDLC State

current: 4
approved-by: dana 2026-09-07T19:05Z "approved"

- Step 4: plan A in flight
PLANA
  cat > "$S25_PLAN_B" <<PLANB
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
parallel-budget: $budget_b
---

## SDLC State

current: 4
approved-by: dana 2026-09-07T19:05Z "approved"

- Step 4: plan B in flight
PLANB
  touch -t 202601010000 "$S25_PLAN_A"
  touch -t 202602010000 "$S25_PLAN_B"
}

# s25_deliver <plan-abs-path> — closes a plan (Step 9, delivered).
s25_deliver() {
  cat > "$1" <<'PLANDONE'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
---

## SDLC State

current: 9

- Step 9: report record/x.md, delivered: 2026-09-04
PLANDONE
}

section "S25a: bound-open — the caller's OWN plan is the ceiling"

# A's budget is tight (writers=1, already at the ceiling with one open row); B's is
# loose (writers=99). Bound to A, the dispatch is refused by A's ceiling — proof
# that a second open plan in the same root (B, newer, looser) is never consulted.
s25_repo r25a "writers=1 suites=9 worktrees=9 test_jobs=4 source=user" \
              "writers=99 suites=9 worktrees=9 test_jobs=4 source=user"
write_attestation "$S25_REPO" "$SID_A"
s25_bind "$S25_REPO" "$SID_A" "$S25_PLAN_A"
s22_roster_row "$S25_REPO" "$SID_A" "W-ONE"
run_gate "$(mk_agent_payload "$SID_A" "$S25_REPO")"
expect_eq "25a1: bound to A (tight budget), the dispatch is REFUSED by A's ceiling" "deny" "$GATE_VERDICT"
expect_contains "25a2: …naming A as the plan the budget came from" "$S25_PLAN_A" "$GATE_VERR"
expect_absent "25a3: …and B's path is never named" "$S25_PLAN_B" "$GATE_ERR$GATE_REASON"
expect_absent "25a4: bound: no fallback line is printed" \
  "run resolved by newest-plan fallback" "$GATE_ERR$GATE_REASON"

section "S25b: fallback — unbound, the newest plan is announced and never acted on"

# The SAME shape, a fresh repo, budgets swapped so B (the newest, and the fallback target)
# is the tight one. Left UNBOUND, the gate prints lib/run.sh's one advisory naming B and
# then judges the dispatch with no plan (wave-23-fixit-1810, REQ-1, D1): B's ceiling is
# never read, and the writer is refused with the bind instruction instead — not with B's
# budget, which is somebody else's run. The positive (advisory, bind refusal) sits beside
# its negative (gone once bound) on the same fixture.
s25_repo r25b "writers=99 suites=9 worktrees=9 test_jobs=4 source=user" \
              "writers=1 suites=9 worktrees=9 test_jobs=4 source=user"
S25_REPO2="$S25_REPO"
# PHYSICAL, because the fallback path comes off active_plan's own resolution —
# `project_root` calls `pwd -P` internally (payload/scripts/lib/root.sh) — while
# $S25_PLAN_B is built from the SANDBOX's logical path (plain `pwd`, no `-P`, in
# this file's own SANDBOX= line). The two differ under macOS's /var -> /private/var
# link, and unlike a bare path-substring check (25b2/25b3, which match anywhere
# in GATE_ERR), this assertion pins an exact adjacency — "— " immediately
# followed by the path — so it needs the SAME physical form the hook itself
# prints. Mirrors tests/dispatch-preflight.test.sh S23's own S23_MAIN idiom.
S25_PLAN_B_PHYS="$(cd "$S25_REPO2" && pwd -P)/.bionic/docs/plans/epic-99-test/plan-b.plan.md"
write_attestation "$S25_REPO2" "$SID_A"
s22_roster_row "$S25_REPO2" "$SID_A" "W-ONE"
run_gate "$(mk_agent_payload "$SID_A" "$S25_REPO2")"
expect_eq "25b1: unbound, a writer dispatch is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "25b2: …with the bind instruction, not another run's verdict" \
  "dispatch refused — this session is bound to no run (bind it, or write its plan)" "$GATE_ERR"
expect_absent "25b2b: …and B's budget is never read: its writers=1 line is named nowhere" \
  "writers=1" "$GATE_ERR$GATE_REASON"
expect_absent "25b3: …and A's path is never named" "$S25_PLAN_A" "$GATE_ERR$GATE_REASON"
expect_contains "25b4: …and the advisory is lib/run.sh's one sentence, naming B verbatim" \
  "run resolved by newest-plan fallback (session unbound) — $S25_PLAN_B_PHYS; bind with session-poker.sh bind $S25_PLAN_B_PHYS, or write this session's plan" \
  "$GATE_ERR"
# A READ-ONLY ROLE STILL DISPATCHES: the pre-approval roster applies to an unbound session as
# it does to any plan nobody approved (D1's consumer table).
run_gate "$(mk_agent_payload "$SID_A" "$S25_REPO2" "$BRIEF_FULL" "w99-res" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:researcher")"
expect_status "25b4b: unbound, a read-only researcher dispatch is admitted" "0" "$GATE_ST"

# THE NEGATIVE, same repo, same payload, only the binding added: once bound to A
# the fallback line disappears (A's loose budget also lets the dispatch through).
s25_bind "$S25_REPO2" "$SID_A" "$S25_PLAN_A"
run_gate "$(mk_agent_payload "$SID_A" "$S25_REPO2")"
expect_status "25b5: the SAME repo, now bound to A (loose budget), passes" "0" "$GATE_ST"
expect_absent "25b6: …and the fallback advisory is gone" \
  "run resolved by newest-plan fallback" "$GATE_ERR"

section "S25c: bound-closed — a plan that closed is no open run at all"

# A is delivered (closed); B stays open, with a ceiling of zero — so if B were
# consulted at all, ANY dispatch would refuse. Bound to closed A, the dispatch
# passes (the budget wall is inert, as it is for any engaged-with-no-plan
# session) and the closed-plan advisory names A; B's path is nowhere in the
# output, proving B was never the fallback here.
s25_repo r25c "suites=9 worktrees=9 test_jobs=4 source=user" \
              "writers=0 suites=9 worktrees=9 test_jobs=4 source=user"
S25_REPO3="$S25_REPO"
s25_deliver "$S25_PLAN_A"
write_attestation "$S25_REPO3" "$SID_A"
s25_bind "$S25_REPO3" "$SID_A" "$S25_PLAN_A"
run_gate "$(mk_agent_payload "$SID_A" "$S25_REPO3")"
expect_status "25c1: bound to a CLOSED plan (A), the dispatch passes — the budget wall is inert" \
  "0" "$GATE_ST"
expect_contains "25c2: …and the closed-plan advisory names A, verbatim" \
  "dispatch-preflight: bound plan closed — $S25_PLAN_A; this session has no open run" \
  "$GATE_ERR"
expect_absent "25c3: …B's path (the still-open plan) appears nowhere" "$S25_PLAN_B" "$GATE_ERR"
expect_absent "25c4: …nor does the writers=0 budget line B carries" "writers=0" "$GATE_ERR"

section "S25d: the roster row's plan= field (AC-2, §Roster attribution)"

# Roster attribution is the BINDING, not the resolved run: a session bound to A
# gets plan=A on its row even though the budget/fallback logic above resolves
# differently case by case. An unbound session's row carries the literal "none".
s25_repo r25d "suites=9 worktrees=9 test_jobs=4 source=user" \
              "suites=9 worktrees=9 test_jobs=4 source=user"
S25_REPO4="$S25_REPO"
# PHYSICAL, same reason as S25_PLAN_B_PHYS above: s25_bind (S11) writes through the real
# bind_plan, which stores the CANONICAL directory (`pwd -P`), not the sandbox's logical one.
S25_PLAN_A_PHYS="$(cd "$S25_REPO4" && pwd -P)/.bionic/docs/plans/epic-99-test/plan-a.plan.md"
write_attestation "$S25_REPO4" "$SID_A"
s25_bind "$S25_REPO4" "$SID_A" "$S25_PLAN_A"
run_gate "$(mk_agent_payload "$SID_A" "$S25_REPO4")"
expect_status "25d1: bound dispatch passes" "0" "$GATE_ST"
S25_ROW=$(roster_nth_row "$(roster_path "$S25_REPO4" "$SID_A")" 1)
expect_status "25d2: the row's plan= field is A's path, verbatim" "$S25_PLAN_A_PHYS" \
  "$(roster_field "$S25_ROW" plan)"

s25_repo r25e "suites=9 worktrees=9 test_jobs=4 source=user" \
              "suites=9 worktrees=9 test_jobs=4 source=user"
S25_REPO5="$S25_REPO"
write_attestation "$S25_REPO5" "$SID_A"
# A READ-ONLY ROLE, because an unbound session's writer is refused with the bind instruction
# (wave-23-fixit-1810, REQ-1, D1; S25b) and writes no row; the researcher is admitted and is
# rostered like any dispatch.
run_gate "$(mk_agent_payload "$SID_A" "$S25_REPO5" "$BRIEF_FULL" "w99-res" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:researcher")"
expect_status "25d3: unbound read-only dispatch passes" "0" "$GATE_ST"
S25_ROW2=$(roster_nth_row "$(roster_path "$S25_REPO5" "$SID_A")" 1)
expect_status "25d4: the row's plan= field is the literal 'none'" "none" \
  "$(roster_field "$S25_ROW2" plan)"

# --- S25d5: a plan path carrying a `|` cannot forge a row (S10a, review SEC F3) ---
#
# THE ROW IS PIPE-DELIMITED ON ONE LINE, which is why `sanitize()` exists and why every
# other interpolated value on it goes through that filter first. `plan=` is the field this
# wave added and was the one field that skipped it, while the parallel writer in
# `session-poker.sh adopt` filtered the same value through `clean()` — so the two writers
# disagreed about whether the field was trusted.
#
# THE FIXTURE IS A REAL FILE. A plan named `wave-99|status=landed|name=ghost.plan.md` is a
# legal filename on every filesystem bionic runs on, so no part of this is hypothetical.
#
# WHAT IS ASSERTED IS THE ROW'S SHAPE, not just the field's text: a forged `status=landed`
# would lose to the real one at `line_field`'s `head -1` today, which makes a value-only
# assertion pass for a reason that could evaporate under any reader change. The field COUNT
# is what says no segment was injected.
s25_repo r25f "suites=9 worktrees=9 test_jobs=4 source=user" \
              "suites=9 worktrees=9 test_jobs=4 source=user"
S25_REPO6="$S25_REPO"
write_attestation "$S25_REPO6" "$SID_A"
S25_EVIL="$S25_REPO6/.bionic/docs/plans/epic-99-test/wave-99|status=landed|name=ghost.plan.md"
cp "$S25_PLAN_A" "$S25_EVIL"
# PHYSICAL, same reason as S25_PLAN_B_PHYS above: s25_bind (S11) now writes through the
# real bind_plan, which resolves the marker's DIRECTORY with `pwd -P` and leaves the leaf
# (the pipe-bearing filename) untouched — so the roster row's plan= field carries this
# physical directory spelling, not the logical $S25_EVIL one.
S25_EVIL_PHYS="$(cd "$(dirname "$S25_EVIL")" && pwd -P)/$(basename "$S25_EVIL")"
expect_status "25d5a: the pipe-bearing plan file really exists (non-vacuity)" "yes" \
  "$([ -f "$S25_EVIL" ] && echo yes || echo no)"
s25_bind "$S25_REPO6" "$SID_A" "$S25_EVIL"
run_gate "$(mk_agent_payload "$SID_A" "$S25_REPO6")"
expect_status "25d5b: the dispatch still passes" "0" "$GATE_ST"
S25_ROW3=$(roster_nth_row "$(roster_path "$S25_REPO6" "$SID_A")" 1)
S25_ROW_CLEAN=$(roster_nth_row "$(roster_path "$S25_REPO4" "$SID_A")" 1)
expect_status "25d5c: the row has exactly as many pipe-delimited fields as a clean row" \
  "$(printf '%s' "$S25_ROW_CLEAN" | tr -cd '|' | wc -c | tr -d ' ')" \
  "$(printf '%s' "$S25_ROW3" | tr -cd '|' | wc -c | tr -d ' ')"
expect_status "25d5d: status is still the writer's own value, not the injected one" "intended" \
  "$(roster_field "$S25_ROW3" status)"
expect_status "25d5e: name is still the dispatched agent's, not the injected one" \
  "$(roster_field "$S25_ROW_CLEAN" name)" "$(roster_field "$S25_ROW3" name)"
expect_status "25d5f: and plan= holds the path with its pipes neutralised" \
  "$(printf '%s' "$S25_EVIL_PHYS" | tr '|' ' ')" "$(roster_field "$S25_ROW3" plan)"

# ================================================== S26: ONE TRANSCRIPT PARSE PER GATE
#
# Step-6 review P-1. The budget loop asks `live_row_open` once per unique `status=intended`
# name, and each ask used to run two whole-file `jq` passes over the transcript. Twelve
# rows against a 4.1 MB transcript measured 1.22 s — over the ~1 s budget for a hook that
# fronts every dispatch — and the row count grows for the life of a session while the
# transcript grows too. `live_agents` now memoizes its parse per process, and the loop
# primes that cache once in the shell the loop runs in, because the per-row call is a
# command substitution and a subshell's cache write dies with it.
#
# THE COUNT IS THE PIN, not the timing. A `jq` shim on PATH records one line per
# invocation whose argv names the transcript; the answer must be 2 (one `_la_scan`, one
# `_la_body`) no matter how many rows the roster carries.

section "S26: the budget parses the transcript once, not once per row"

S26_SHIM="$SANDBOX/s26shim"
mkdir -p "$S26_SHIM"
S26_REAL_JQ="$(command -v jq)"
S26_COUNT="$SANDBOX/.s26-jq-calls"
cat > "$S26_SHIM/jq" <<S26EOF
#!/bin/bash
for _a in "\$@"; do
  case "\$_a" in *"\$LA_COUNT_TRANSCRIPT") printf '%s\n' "\$_a" >> "\$LA_COUNT_FILE" ;; esac
done
exec "$S26_REAL_JQ" "\$@"
S26EOF
chmod +x "$S26_SHIM/jq"

REPO=$(make_repo r26 yes)
write_attestation "$REPO" "$SID_A"
s22_set_budget "$REPO" "writers=99 suites=9 worktrees=9 test_jobs=4 source=user"
S26_N=1
while [ "$S26_N" -le 12 ]; do
  s22_roster_row "$REPO" "$SID_A" "r26-$S26_N"
  S26_N=$((S26_N + 1))
done
S26_T="$SANDBOX/.r26.jsonl"
mk_transcript "$S26_T" fresh W-OTHER

: > "$S26_COUNT"
S26_SAVED_ENV="$GATE_ENV"
GATE_ENV="$GATE_ENV PATH=$S26_SHIM:$PATH LA_COUNT_FILE=$S26_COUNT LA_COUNT_TRANSCRIPT=$S26_T"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w26-impl" "claude-sonnet-5" "$S26_T")"
GATE_ENV="$S26_SAVED_ENV"

expect_status "26a twelve intended rows and the gate still passes at writers=99" "0" "$GATE_ST"
expect_status "26b …and the transcript was parsed exactly twice — once per jq pass, not once per row" \
  "2" "$(grep -c . "$S26_COUNT" | tr -d ' ')"

# ============================================================================

section "S27: the suite-allowance wall (AC-20, AC-24)"
# ============================================================================
#
# THE INCIDENT THIS SECTION IS ABOUT. Two dispatched writers finished their own work
# green at ~45 minutes and then spent 40 more re-running the whole tree, one suite at a
# time, in parallel, on an 8 GB machine. Their briefs said "run impacted suites only;
# never tests/run.sh". Prose in a brief is a wish; the roster row is what the writer-side
# guard can read. So the brief declares INTENT (`Files:`) or the closed set (`Suites:`),
# the wall records the budget, and a brief that declares neither is refused here.
#
# THE IMPACT COMMAND IS FIXTURED, NOT REAL. What this section proves is that the wall
# RUNS the configured command over the declared paths and records what comes back — so the
# command is a two-line stub whose answer is unmistakably its own, and doctoring it must
# move the row. Driving the real `tests/lib/impact.sh` through this contract is
# tests/cross-gate-agreement.test.sh's job (one owner per shared truth): a fixture that
# reproduced its output would pin this file to a derivation it does not own.

# [s27_impact, BRIEF_FILES: defined in tests/dispatch-preflight.prelude.sh, hoisted from here for the shards — wave-30 T1]

# --- S27a: Files: + a configured impact command -> the DERIVED row ---
REPO=$(make_repo r27a yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" beta.test.sh alpha.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w27-files")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27a a brief declaring Files: with an impact command PASSES" "0" "$GATE_ST"
expect_status "27a …and the row records the declared paths verbatim" \
  "payload/scripts/lib/widget.sh,hooks/widget-guard.sh" "$(roster_field "$ROW" files)"
expect_status "27a …the derived set is the impact command's answer, sorted and deduplicated" \
  "alpha.test.sh beta.test.sh" "$(roster_field "$ROW" suites_allowed)"
expect_status "27a …and the row says the set was DERIVED, not declared" \
  "derived" "$(roster_field "$ROW" suites_source)"
# NON-VACUITY, both directions. The stub really ran, and it really received the paths the
# brief declared — a wall that ignored the command and wrote a constant would pass every
# assertion above.
expect_status "27a …the impact command was really run" "0" \
  "$([ -f "$REPO/.bionic/impact-args.txt" ] && echo 0 || echo 1)"
expect_eq "27a …over the declared paths, one argument each" \
  "payload/scripts/lib/widget.sh
hooks/widget-guard.sh" "$(cat "$REPO/.bionic/impact-args.txt")"

# --- S27a2: MUTATION — doctor the command, and the row must move ---
# The row is the command's answer, not the wall's opinion of it.
REPO=$(make_repo r27a2 yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" gamma.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w27-files2")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27a2 a DIFFERENT impact command answer lands a different budget" \
  "gamma.test.sh" "$(roster_field "$ROW" suites_allowed)"

# --- S27a3: a derivation that answers NOTHING leaves the budget empty, and warns ---
REPO=$(make_repo r27a3 yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w27-files3")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27a3 an impact command that derives nothing still PASSES the dispatch" "0" "$GATE_ST"
expect_status "27a3 …with an empty budget on the row" "" "$(roster_field "$ROW" suites_allowed)"
expect_status "27a3 …still marked derived, so no reader mistakes it for a declaration" \
  "derived" "$(roster_field "$ROW" suites_source)"
expect_contains "27a3 …and the operator is told at dispatch" "derived no suites" "$GATE_ERR"

# --- S27b: Suites: -> the DECLARED row, normalised to basenames ---
REPO=$(make_repo r27b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27b.md
Suites: tests/one.test.sh, tests/two.test.sh' "w27-decl")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27b a declared Suites: line PASSES with no impact command configured" "0" "$GATE_ST"
expect_status "27b …recorded as BASENAMES, the same alphabet the derivation prints" \
  "one.test.sh two.test.sh" "$(roster_field "$ROW" suites_allowed)"
expect_status "27b …and the row says the set was DECLARED" \
  "declared" "$(roster_field "$ROW" suites_source)"
expect_status "27b …with no files= value, because the brief declared none" \
  "" "$(roster_field "$ROW" files)"

# --- S27c: NEITHER label -> refused, naming all three fixes ---
REPO=$(make_repo r27c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27c.md
Expected duration: ~15 minutes.' "w27-neither")"
expect_eq "27c a brief declaring neither Files: nor Suites: is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "27c …naming the Files: fix" "Files: path/one.sh" "$GATE_VERR"
expect_contains "27c …naming the Suites: fix" "Suites: tests/one.test.sh" "$GATE_VERR"
expect_contains "27c …and the waiver" "Suites: none" "$GATE_VERR"
# THE SPELLING RULE, IN THE ONE MESSAGE AN AUTHOR READS WHEN THE LABELS ARE MISSING. Both
# labels are read out of the brief TEXT before any shell expands anything, and the
# writer-side guard reads its command the same way (review-c C-5/C-6): a name that is still
# a variable when a hook sees it can be neither derived from nor checked against anything.
expect_contains "27c …and the spelling rule the two labels share" \
  "one path per token, no shell variables" "$GATE_VERR"
expect_eq "27c …with ONE deny verdict on stdout and nothing else" "1" \
  "$(printf '%s\n' "$GATE_OUT" | /usr/bin/grep -c . || true)"
expect_status "27c …and no row journalled for a refused dispatch" \
  "0" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# --- S27d: `Suites: none` is the waiver, and it lands on the row ---
REPO=$(make_repo r27d yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: read the tree and report.
Expected artifact: .bionic/docs/record/w27d.md
Suites: none' "w27-waived")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27d a Suites: none brief PASSES" "0" "$GATE_ST"
expect_status "27d …and the waiver is on the row, where the writer-side guard reads it" \
  "none" "$(roster_field "$ROW" suites_allowed)"
expect_status "27d …recorded as a declaration, because a human declared it" \
  "declared" "$(roster_field "$ROW" suites_source)"

# --- S27e: Files: with NO impact command -> refused, naming the two fixes ---
#
# `Files:` states an intent that only a derivation can turn into a budget. bionic runs in
# repositories that configure none, and there the author is the only one who can name the
# set — so this refuses rather than passing with an empty budget, at the one moment the
# author is still holding the brief.
REPO=$(make_repo r27e yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w27-nocmd")"
expect_eq "27e Files: with no impact-command configured is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "27e …naming the declared-set fix" "Suites: tests/one.test.sh" "$GATE_VERR"
expect_contains "27e …and the config key that would derive it" "impact-command:" "$GATE_VERR"

# --- S27f: a brief carrying BOTH — the declaration wins ---
#
# `Suites: none` is a waiver, and a waiver a derivation could overrule is not a waiver.
REPO=$(make_repo r27f yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" derived-only.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27f.md
Files: payload/scripts/lib/widget.sh
Suites: tests/declared-only.test.sh' "w27-both")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27f a brief with both labels takes the DECLARED set" \
  "declared-only.test.sh" "$(roster_field "$ROW" suites_allowed)"
expect_status "27f …and says so" "declared" "$(roster_field "$ROW" suites_source)"
expect_status "27f …while still recording the files the brief declared" \
  "payload/scripts/lib/widget.sh" "$(roster_field "$ROW" files)"
# NON-VACUITY: the impact command that would have answered differently really was configured.
expect_status "27f …non-vacuity: an impact command WAS configured for this repo" "0" \
  "$([ -f "$REPO/.bionic/config.yaml" ] && echo 0 || echo 1)"

# --- §declared-new-suite (T8, AC-5.1) — a declared suite ABSENT ON DISK lands verbatim ---
#
# T7's repro (record/wave-14-tune-181/T7-req5-repro.md §3, RUN 2) drove this exact shape —
# Files: + a Suites: paragraph naming a suite the task itself is about to create, path-
# prefixed, own paragraph — against the REAL hook and found it already passing: lift
# (`lift_contract_fields`/`suite_names()`, moved by T6 into payload/scripts/lib/brief.sh)
# performs no on-disk existence check, and selection (the `brief_field` calls in
# hooks/dispatch-preflight.sh) takes the declared set whole. This is that RUN, kept as a
# PIN beside 27f rather than a new implementation — 27f's own "declared wins whole"
# assertion is unchanged by it. Per the T8 brief: if this never goes red against the
# parent, it is reported as a pin, not as RED→GREEN.
REPO=$(make_repo r27new yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" archive.test.sh run.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Canonical-sdlc Step 4, task 4/4 of epic-23 wave-13; build · double · wave.
Your task: the close-out script (D5, D6).
Expected artifact: .bionic/docs/record/wave-13-fixit-180/T4-close-out.md
Expected duration: ~120 minutes.
Files: payload/scripts/close-out.sh, payload/scripts/lib/archive.sh, tests/close-out.test.sh, tests/archive.test.sh, payload/scripts/lib/run.sh

Suites: tests/close-out.test.sh, tests/run-predicate.test.sh' "w27-newsuite")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "declared-new-suite a Files:+Suites: brief naming a suite absent on disk PASSES" \
  "0" "$GATE_ST"
expect_status "declared-new-suite …the row carries BOTH declared tokens, verbatim" \
  "close-out.test.sh run-predicate.test.sh" "$(roster_field "$ROW" suites_allowed)"
expect_status "declared-new-suite …suites_source= is declared, not derived" \
  "declared" "$(roster_field "$ROW" suites_source)"
# NON-VACUITY: the file really is absent from this fixture repo, and the impact command
# really was configured (so a wall that fell through to derivation would answer
# "archive.test.sh run.sh" instead, not this pair).
expect_status "declared-new-suite …non-vacuity: tests/close-out.test.sh is absent on disk" \
  "1" "$([ -f "$REPO/tests/close-out.test.sh" ] && echo 0 || echo 1)"
expect_status "declared-new-suite …non-vacuity: an impact command WAS configured for this repo" \
  "0" "$([ -f "$REPO/.bionic/config.yaml" ] && echo 0 || echo 1)"

# --- S27g: the row's instrument fields never disturb the ones already on it ---
#
# RE-AUTHORED FOR THE FOURTH FIELD (epic-23 wave-16, REQ-1/REQ-7 AC-7.3). `re_executes=` is
# the runner-agnostic half of the instrument declaration and joins the group as its LAST
# member, so the contiguity claim below is now over four keys rather than three. The claim
# itself is unchanged and is the one that matters: the group sits between `waiver=` and
# `tool_use_id=`, it does not interleave with anything, and `plan=` is still last on the row.
# A field appended anywhere else would pass a key-by-key read and still move bytes the
# captured row in tests/fixtures/roster-row.captured pins (cross-gate §RA.2).
REPO=$(make_repo r27g yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w27-shape")"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27g the deliverable is unmoved by the instrument fields" \
  ".bionic/docs/record/w99-widget.txt" "$(roster_field "$ROW" deliverable)"
expect_status "27g …and plan= is still the LAST field on the row" "0" \
  "$(printf '%s' "$ROW" | grep -qE '\|plan=[^|]*$' && echo 0 || echo 1)"
expect_status "27g the four instrument fields sit between waiver= and tool_use_id=" "0" \
  "$(printf '%s' "$ROW" | grep -qE '\|waiver=[^|]*\|files=[^|]*\|suites_allowed=[^|]*\|suites_source=[^|]*\|re_executes=[^|]*\|tool_use_id=' && echo 0 || echo 1)"

# --- S27h: SELF-CONSISTENCY — a brief following this wall's own Fix lines passes ---
#
# The same pin R6-2 applies to the deliverable walls, read back off THIS wall's stderr:
# an author who copies the recommended `Suites:` line verbatim must not be refused by the
# wall that recommended it.
S27_FIX=$(printf '%s\n' "$GATE_ERR" | grep -m1 -E '^[[:space:]]+Suites: ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
REPO=$(make_repo r27c2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27c2.md' "w27-neither2")"
S27_FIX=$(printf '%s\n' "$GATE_VERR" | grep -m1 -E '^[[:space:]]+Suites: tests' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
expect_status "27h the refusal really recommended a Suites: line" "0" \
  "$([ -n "$S27_FIX" ] && echo 0 || echo 1)"
REPO=$(make_repo r27h yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: .bionic/docs/record/w27h.md
$S27_FIX" "w27-followed")"
expect_status "27h a brief following that Fix: line verbatim PASSES" "0" "$GATE_ST"

# --- S27i: A WIDE DECLARED BUDGET SURVIVES WHOLE ON THE ROW (T18, REQ-9/D7 write side) ---
#
# T9 exempted `suites_allowed=`/`files=` from `clean()`'s 400-char cut on the READER side
# (`hooks/session-poker.sh`'s `adopt_write_row`). This is the same defect's WRITE side: the
# two `sanitize()` calls that build `C_FILES`/`C_SUITES` from a brief's own `Files:`/
# `Suites:` line still capped at 900 (the widest cap this file had, per the comment they
# used to carry — "truncating a list silently narrows a budget"). `SUITES_MAX`/`FILES_MAX`
# (60, `lift_contract_fields`'s own token-count bound, a SEPARATE and deliberate limit — see
# A-T18.2) cap the item COUNT the extraction stage lifts at all, so this fixture stays at
# exactly that many items and makes each one long enough that 60 of them still overflow the
# 900-char cap this task removes — a real budget this wide is not a hypothetical (A-orch-16).
S27I_SUITES=""; S27I_EXPECT=""
for _s27i in $(seq -w 1 60); do
  _s27i_name="very-long-suite-basename-for-the-budget-cut-test-number-${_s27i}.test.sh"
  S27I_SUITES="${S27I_SUITES}tests/${_s27i_name}, "
  S27I_EXPECT="${S27I_EXPECT:+$S27I_EXPECT }${_s27i_name}"
done
S27I_SUITES="${S27I_SUITES%, }"
expect_status "27i fixture non-vacuity: the declared line really overflows 900 chars" \
  "0" "$([ "${#S27I_SUITES}" -gt 900 ] && echo 0 || echo 1)"
REPO=$(make_repo r27i yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: .bionic/docs/record/w27i.md
Suites: ${S27I_SUITES}" "w27-wide-declared")"
expect_status "27i a brief declaring a 60-suite, >900-char budget PASSES" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
S27I_ROW_SUITES=$(roster_field "$ROW" suites_allowed)
expect_eq "27i …and the row's suites_allowed= carries the WHOLE set, byte for byte" \
  "$S27I_EXPECT" "$S27I_ROW_SUITES"
expect_status "27i …the LAST one specifically — the one 900 chars would have cut" \
  "0" "$(printf '%s\n' "$S27I_ROW_SUITES" | tr ' ' '\n' | grep -qxF 'very-long-suite-basename-for-the-budget-cut-test-number-60.test.sh' && echo 0 || echo 1)"
expect_status "27i …every one of the 60, none dropped" \
  "60" "$(printf '%s\n' "$S27I_ROW_SUITES" | tr ' ' '\n' | grep -c 'very-long-suite-basename')"

# --- S27j: A WIDE DECLARED Files: LIST SURVIVES WHOLE TOO (same fix, `files=`) ---
S27J_FILES=""; S27J_EXPECT=""
for _s27j in $(seq -w 1 60); do
  _s27j_path="payload/scripts/lib/a-fairly-long-widget-module-name-number-${_s27j}.sh"
  S27J_FILES="${S27J_FILES}${_s27j_path}, "
  S27J_EXPECT="${S27J_EXPECT:+$S27J_EXPECT,}${_s27j_path}"
done
S27J_FILES="${S27J_FILES%, }"
expect_status "27j fixture non-vacuity: the declared line really overflows 900 chars" \
  "0" "$([ "${#S27J_FILES}" -gt 900 ] && echo 0 || echo 1)"
REPO=$(make_repo r27j yes)
write_attestation "$REPO" "$SID_A"
s27_impact "$REPO" alpha.test.sh
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: .bionic/docs/record/w27j.md
Files: ${S27J_FILES}" "w27-wide-files")"
expect_status "27j a brief declaring 60 long files PASSES" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
S27J_ROW_FILES=$(roster_field "$ROW" files)
expect_eq "27j …and files= carries the WHOLE declared list, byte for byte (no cut at all)" \
  "$S27J_EXPECT" "$S27J_ROW_FILES"

# --- S27k: CONTROL — an ORDINARY field still cuts, unaffected by the fix above ---
#
# `deliverable=` keeps its own pre-existing 300-char cap: the fix is scoped to the two
# LIST-valued fields, exactly as `clean()`'s exemption was on the reader side.
S27K_LONG=$(printf 'x%.0s' $(seq 1 500))
REPO=$(make_repo r27k yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: .bionic/docs/record/w27k-${S27K_LONG}.md
Suites: tests/one.test.sh" "w27-control-cut")"
expect_status "27k a 500-char deliverable still PASSES" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
S27K_ROW_DELIV=$(roster_field "$ROW" deliverable)
expect_eq "27k …but its deliverable= is cut at exactly its own 300-char cap" \
  "300" "${#S27K_ROW_DELIV}"

# --- S27l: A 70-SUITE BUDGET LANDS WHOLE — the item-COUNT cap, raised (T19, A-orch-19.1) ---
#
# S27i/j proved the CHAR cut is gone (T18). This is the separate, third layer the walk
# found: `suite_names()`'s own token-COUNT bound, `SUITES_MAX` — the exact "your own suite
# is off your budget" shape that bit T9 at 70 declared suites. 70 is chosen to match that
# incident directly; the cap this task raises (200) holds it with room to spare.
S27L_SUITES=""; S27L_EXPECT=""
for _s27l in $(seq -w 1 70); do
  _s27l_name="count-cap-suite-${_s27l}.test.sh"
  S27L_SUITES="${S27L_SUITES}tests/${_s27l_name}, "
  S27L_EXPECT="${S27L_EXPECT:+$S27L_EXPECT }${_s27l_name}"
done
S27L_SUITES="${S27L_SUITES%, }"
REPO=$(make_repo r27l yes)
write_attestation "$REPO" "$SID_A"
# A BUDGETED PLAN, as every live plan is (ADR-035): since epic-23 wave-20 T2 a keyless live
# plan earns preflight's named-backstop WARN, and this row's "no WARN" is about the suite cap.
s22_set_budget "$REPO" "writers=99 suites=99 worktrees=99 test_jobs=4 source=user"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: .bionic/docs/record/w27l.md
Expected duration: 5 minutes
Progress: .bionic/docs/record/w27-progress.md, cadence 5 minutes
Suites: ${S27L_SUITES}" "w27-count-70")"
expect_status "27l a brief declaring 70 real suites PASSES" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
S27L_ROW_SUITES=$(roster_field "$ROW" suites_allowed)
expect_eq "27l …and suites_allowed= carries all 70, none dropped" \
  "$S27L_EXPECT" "$S27L_ROW_SUITES"
expect_status "27l …the 70th specifically" "0" \
  "$(printf '%s\n' "$S27L_ROW_SUITES" | tr ' ' '\n' | grep -qxF 'count-cap-suite-70.test.sh' && echo 0 || echo 1)"
expect_absent "27l …no WARN, because 70 is under the raised cap" "WARN" "$GATE_ERR"

# --- S27m: OVER THE RAISED CAP IS LOUD — a WARN naming the cap and what it dropped ---
#
# 201 tokens (SUITES_MAX + 1) so the cap this task sets (200) is exercised at its own
# boundary. The prior behaviour here was a SILENT exit 0 (A-orch-19.1) — the same class of
# bug T9 fixed on the char cut and T18 fixed on the preflight-sanitize char cut, now fixed
# on the count cap. `expect_absent` on the OLD (silent) shape would pass vacuously if the
# WARN plumbing were simply missing, so this checks both the cap enforcement (200 kept, the
# 201st absent from the row) AND the WARN naming that exact 201st token.
S27M_SUITES=""
for _s27m in $(seq -w 1 201); do
  S27M_SUITES="${S27M_SUITES}tests/count-cap-over-${_s27m}.test.sh, "
done
S27M_SUITES="${S27M_SUITES%, }"
REPO=$(make_repo r27m yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: .bionic/docs/record/w27m.md
Expected duration: 5 minutes
Progress: .bionic/docs/record/w27-progress.md, cadence 5 minutes
Suites: ${S27M_SUITES}" "w27-count-201")"
expect_status "27m a 201-suite brief still PASSES (the cap warns, it does not refuse)" \
  "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
S27M_ROW_SUITES=$(roster_field "$ROW" suites_allowed)
expect_status "27m …suites_allowed= holds exactly the cap, 200" "200" \
  "$(printf '%s\n' "$S27M_ROW_SUITES" | tr ' ' '\n' | grep -c 'count-cap-over-')"
expect_absent "27m …the 201st is NOT on the row" "count-cap-over-201.test.sh" "$S27M_ROW_SUITES"
expect_contains "27m …and dispatch WARNs, naming the cap" "WARN" "$GATE_ERR"
expect_contains "27m …by number" "200" "$GATE_ERR"
expect_contains "27m …naming the dropped 201st token specifically" \
  "count-cap-over-201.test.sh" "$GATE_ERR"
expect_status "27m …never a SILENT exit 0 — stderr is non-empty" "0" \
  "$([ -n "$GATE_ERR" ] && echo 0 || echo 1)"

# ============================================================================

section "S27n: a dropped Suites: token is a refusal, not a silent no-instrument arm (T3, REQ-8, AC-8.1)"
# ============================================================================
#
# `suite_names()`'s filter (`:1748`) has always kept only a `*.test.sh` basename or a
# path-qualified `run.sh`; everything else fell off in total silence — a jest spec name,
# a pytest module — and the brief then met the UNRELATED "no Files: and no Suites:" arm,
# for having named something real. This puts the drop on the same channel the unexpanded-
# variable arm already uses (`:1746`, `suites_bad=`), named, before that arm is reached
# (research R3 §C1.4, option 3 — no existence check, D11-compliant).

REPO=$(make_repo r27n yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: audit the wave-99 matrix.
Expected artifact: .bionic/docs/record/w27n-audit.md
Expected duration: ~30 minutes.
Questions: evidence
Suites: image-id.spec.ts" "w27n-aud-spec" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:auditor")"
expect_eq "27n an auditor brief naming a dropped token is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "27n …naming the token it saw" "image-id.spec.ts" "$GATE_VERR"
expect_contains "27n …the new verdict" \
  "Suites: names a file the shell runner cannot run" "$GATE_ERR"
expect_contains "27n …the fix points at Re-executes:" "Re-executes:" "$GATE_VERR"
expect_absent "27n …never the unrelated no-instrument text" \
  "declares no Files: and no Suites:" "$GATE_ERR$GATE_REASON"
expect_status "27n …no roster row for the refused dispatch" \
  "0" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

REPO=$(make_repo r27n2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected artifact: .bionic/docs/record/w27n-writer.md
Expected duration: ~30 minutes.
Suites: image-id.spec.ts" "w27n-writer-spec")"
expect_eq "27n2 a writer brief naming the same dropped token is REFUSED likewise" \
  "deny" "$GATE_VERDICT"
expect_contains "27n2 …naming the token it saw" "image-id.spec.ts" "$GATE_VERR"
expect_absent "27n2 …never the unrelated no-instrument text" \
  "declares no Files: and no Suites:" "$GATE_ERR$GATE_REASON"

# ============================================================================

section "S27p: a trailing # comment is not a dropped Suites: token (T23, review R1)"
# ============================================================================
#
# THE SHIPPED SCAFFOLD CARRIES ONE. `agents-src/blocks/brief-scaffold.md` renders
# `Suites: none    # *.test.sh names or a path-qualified run.sh; other runners:
# Re-executes:` into all eight surfaces, and an author who fills the scaffold in keeps
# the comment. The drop refusal above read EVERY whitespace-separated token on the span,
# so `other`, `runners:` and the rest each scored as a file the shell runner cannot run,
# and a brief was refused for carrying this repo's own teaching text — with a message
# that names
# `Re-executes:` and never mentions the comment, so the repair was not discoverable from
# it (Step-6 review R1, HIGH; the base at 72e07ec admitted the same brief). `suite_names()`
# now stops reading the span at the first token beginning with `#`.
#
# fails-when: a commented span refuses; a word of the comment reaches the roster row; the
# comment changes the budget the bare span would have produced; or stopping at `#` also
# stopped the drop arm from seeing a real dropped token.

R27P_BRIEF='Your task: build it.
Expected artifact: .bionic/docs/record/w27p.md
Suites: tests/a.test.sh  # the impacted suite'
R27P_BARE='Your task: build it.
Expected artifact: .bionic/docs/record/w27p.md
Suites: tests/a.test.sh'

REPO=$(make_repo r27p yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$R27P_BRIEF" "w27p-comment")"
expect_status "27p a filled brief whose Suites: line ends in a comment is ADMITTED" \
  "0" "$GATE_ST"
expect_status "27p …on the deny channel as well as the exit one" "allow" "$GATE_VERDICT"
ROW_COMMENTED=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27p …the budget is the declared suite alone" "a.test.sh" \
  "$(roster_field "$ROW_COMMENTED" suites_allowed)"
expect_status "27p …declared, because a human declared it" "declared" \
  "$(roster_field "$ROW_COMMENTED" suites_source)"
expect_absent "27p …no word of the comment reaches the row" "impacted" "$ROW_COMMENTED"
expect_absent "27p …and the suite-drop refusal never fires" \
  "Suites: names a file the shell runner cannot run" "$GATE_ERR"

# THE CONTROL: the same brief with the comment deleted. The row is compared WHOLE, field
# for field, `launched_at=` excepted — that cell is one `date -u` per drive and the two
# drives can straddle a second boundary — and `plan=` excepted, because the two drives are
# two repos and each session is bound to its own repo's plan (wave-23-fixit-1810 T1).
REPO=$(make_repo r27p2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$R27P_BARE" "w27p-comment")"
expect_status "27p2 the same brief without the comment is ADMITTED too" "0" "$GATE_ST"
ROW_BARE=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27p2 …and its row is the commented brief's row, field for field" \
  "$(printf '%s' "$ROW_COMMENTED" | sed 's/launched_at=[^|]*/launched_at=/; s/|plan=[^|]*$/|plan=/')" \
  "$(printf '%s' "$ROW_BARE"      | sed 's/launched_at=[^|]*/launched_at=/; s/|plan=[^|]*$/|plan=/')"
expect_contains "27p2 …non-vacuity: the compared row really carries the budget" \
  "suites_allowed=a.test.sh" "$ROW_BARE"

# THE WAIVER, COMMENTED — the scaffold line as it ships, filled in and left commented.
REPO=$(make_repo r27p3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: read the tree and report.
Expected artifact: .bionic/docs/record/w27p3.md
Suites: none    # *.test.sh names or a path-qualified run.sh; other runners: Re-executes:' \
  "w27p-waiver")"
expect_status "27p3 a commented Suites: none is the waiver it always was" "0" "$GATE_ST"
# ...and on the OTHER channel too: a several-fault refusal exits 0 and denies on stdout, so
# the exit status alone would score this ADMITTED whatever the gate decided (wave-12 T17).
expect_status "27p3 …no refusal verdict on either channel" "allow" "$GATE_VERDICT"
expect_status "27p3 …the waiver on the row, where the writer-side guard reads it" "none" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" suites_allowed)"

# THE SAME LINE ON THE ROLE WHOSE OWN FILE SHIPS IT. `agents/auditor.md` carries the
# scaffold, and an auditor that waives every suite must declare runs instead (16lb1/16lb2) —
# so this is that admitted shape with the comment left on, and the control below is the same
# brief without the runs, which must still meet the AUDITOR arm and not the drop arm.
REPO=$(make_repo r27p3b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: audit the wave-99 matrix.
Expected artifact: .bionic/docs/record/w27p3b-audit.md
Expected duration: ~30 minutes.
Questions: evidence
Suites: none    # *.test.sh names or a path-qualified run.sh; other runners: Re-executes:
Re-executes: `pytest tests/unit`' "w27p-aud-waiver" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" \
  "bionic:auditor")"
expect_status "27p3b an auditor waiving suites in a comment-carrying line, declaring runs, is ADMITTED" \
  "0" "$GATE_ST"
expect_status "27p3b …the waiver on the row" "none" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" suites_allowed)"

REPO=$(make_repo r27p3c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: audit the wave-99 matrix.
Expected artifact: .bionic/docs/record/w27p3c-audit.md
Expected duration: ~30 minutes.
Questions: evidence
Suites: none    # *.test.sh names or a path-qualified run.sh; other runners: Re-executes:' \
  "w27p-aud-bare" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "bionic:auditor")"
expect_eq "27p3c …and the same line without runs still meets the AUDITOR arm" "deny" "$GATE_VERDICT"
expect_contains "27p3c …named as an auditor that re-executes nothing" \
  "the auditor declares nothing to re-execute" "$GATE_ERR"
expect_absent "27p3c …never the suite-drop refusal" \
  "Suites: names a file the shell runner cannot run" "$GATE_ERR$GATE_REASON"

# THE DISCRIMINATOR: a genuinely dropped token AHEAD of a comment still refuses, naming the
# token and no word of the comment. §27n/§27n2 pin the whole-span case; this pins that
# stopping at `#` did not stop the arm.
REPO=$(make_repo r27p4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27p4.md
Suites: image-id.spec.ts  # the impacted suite' "w27p-drop")"
expect_eq "27p4 a dropped token ahead of a comment is still REFUSED" "deny" "$GATE_VERDICT"
expect_contains "27p4 …naming the token it saw" "image-id.spec.ts" "$GATE_VERR"
expect_absent "27p4 …and never a word of the comment" "impacted" "$GATE_VERR"

# ============================================================================

section "S27q: a # comment ends its LINE, not the whole span (critic C8/C9)"
# ============================================================================
#
# A `Suites:` SPAN IS NOT A LINE. `spanof()` runs to the next LABELLED line or the next
# blank line, so a roster wrapped across several lines is one span — and this wave's own
# dispatches carry 19-suite rosters. §27p above stopped the scan at the first `#` token
# anywhere in that span, so a comment on the FIRST line silently discarded every suite
# declared on the continuation lines: no refusal, no `suites_dropped=`, nothing on the
# roster row to show it happened, and the writer met the run-time budget wall instead
# (critic C8 — the loud drop §27n installed turned back into a quiet budget cut).
#
# THE RULE IS NOW LINE-SCOPED: a `#` token ends the tokens of ITS OWN line, and the scan
# resumes at the next line of the span. §27p's whole promise is kept — no word of a
# comment reaches the row or the drop refusal — and a comment that opens a CONTINUATION
# line ends that line only, contributing nothing from it.
#
# AND A SPAN THAT IS ALL COMMENT NOW SAYS SO (critic C9). `Suites: # read-only` lifts
# nothing, so all four guards of the no-instrument arm read empty and the brief is refused
# for "declaring no Files: and no Suites:" — of a brief that declares `Suites:` in as many
# words, the self-refuting shape C3 was fixed for. The verdict and the fix stay as they
# are (there genuinely is no budget for the row to carry); the DETAIL now opens by naming
# what happened and the one-word repair, first so it survives refuse.sh's twelve-line fold.
#
# fails-when: a suite declared on a continuation line is dropped behind a comment; a word
# of a comment reaches the row or a refusal; a dropped token on a continuation line goes
# silent; or an all-comment span is still refused as a brief that declared nothing.

S27Q_WRAP='Your task: build it.
Expected artifact: .bionic/docs/record/w27q.md
Suites: tests/a.test.sh   # the impact set
  tests/b.test.sh tests/c.test.sh'
S27Q_WRAP_BARE='Your task: build it.
Expected artifact: .bionic/docs/record/w27q.md
Suites: tests/a.test.sh
  tests/b.test.sh tests/c.test.sh'

REPO=$(make_repo r27q yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S27Q_WRAP" "w27q-wrap")"
expect_status "27q a wrapped Suites: span whose first line ends in a comment is ADMITTED" \
  "0" "$GATE_ST"
ROW_WRAP=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27q …and the budget is every suite the SPAN names, not the first line's alone" \
  "a.test.sh b.test.sh c.test.sh" "$(roster_field "$ROW_WRAP" suites_allowed)"
expect_absent "27q …no word of the comment reaches the row" "impact" "$ROW_WRAP"

# THE CONTROL: the same wrapped span with the comment deleted. Row compared WHOLE, field
# for field, `launched_at=` excepted — one `date -u` per drive, two drives can straddle a
# second boundary (§27p2's rule).
REPO=$(make_repo r27q2 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$S27Q_WRAP_BARE" "w27q-wrap")"
expect_status "27q2 the same wrapped span without the comment is ADMITTED too" "0" "$GATE_ST"
ROW_WRAP_BARE=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "27q2 …and its row is the commented span's row, field for field" \
  "$(printf '%s' "$ROW_WRAP"      | sed 's/launched_at=[^|]*/launched_at=/; s/|plan=[^|]*$/|plan=/')" \
  "$(printf '%s' "$ROW_WRAP_BARE" | sed 's/launched_at=[^|]*/launched_at=/; s/|plan=[^|]*$/|plan=/')"
expect_contains "27q2 …non-vacuity: the compared row really carries all three suites" \
  "suites_allowed=a.test.sh b.test.sh c.test.sh" "$ROW_WRAP_BARE"

# THE COMMENT'S OWN WORDS ARE STILL NOT TOKENS — the hazard `break` was chosen for
# (A-T23.1). A suite NAMED INSIDE the comment is prose, not a declaration, on the comment's
# own line and glued to the `#` alike.
REPO=$(make_repo r27q3 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27q3.md
Suites: tests/a.test.sh  # and tests/b.test.sh' "w27q-prose")"
expect_status "27q3 a suite named inside the comment is not declared" "0" "$GATE_ST"
expect_status "27q3 …the budget is the declared suite alone" "a.test.sh" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" suites_allowed)"

REPO=$(make_repo r27q4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27q4.md
Suites: tests/a.test.sh #tests/b.test.sh' "w27q-glued")"
expect_status "27q4 …and a comment glued to its own marker reads the same" "0" "$GATE_ST"
expect_status "27q4 …the budget is the declared suite alone" "a.test.sh" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" suites_allowed)"

# A CONTINUATION LINE THAT IS ITSELF ALL COMMENT contributes nothing, and does not end the
# span's reading either — the line scope cuts both ways.
REPO=$(make_repo r27q5 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27q5.md
Suites: tests/a.test.sh
  # tests/b.test.sh is out of scope
  tests/c.test.sh' "w27q-contcomment")"
expect_status "27q5 an all-comment continuation line is ADMITTED" "0" "$GATE_ST"
expect_status "27q5 …contributes nothing, and does not stop the line after it" \
  "a.test.sh c.test.sh" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" suites_allowed)"

# THE DISCRIMINATOR FOR C8: a genuinely dropped token on a CONTINUATION line, behind a
# comment on the first. §27p4 pins the same token ahead of a comment; this is the shape
# `break` silenced.
REPO=$(make_repo r27q6 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27q6.md
Suites: tests/a.test.sh  # the impact set
  image-id.spec.ts' "w27q-contdrop")"
expect_eq "27q6 a dropped token on a continuation line behind a comment is REFUSED" \
  "deny" "$GATE_VERDICT"
expect_contains "27q6 …naming the token it saw" "image-id.spec.ts" "$GATE_VERR"
expect_absent "27q6 …and never a word of the comment" "impact set" "$GATE_VERR"

# --- C9: a span that is ALL comment is refused for what it is ---------------------
REPO=$(make_repo r27q7 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27q7.md
Suites: # none needed, this is read-only' "w27q-allcomment")"
expect_eq "27q7 a Suites: span that is entirely a comment is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "27q7 …the verdict is the no-instrument one, unchanged" \
  "declares no Files: and no Suites:" "$GATE_ERR"
expect_contains "27q7 …and the detail names what actually happened" \
  "its span is a comment" "$GATE_REASON"
expect_contains "27q7 …with the one-word repair beside it" \
  "write \`none\` to waive" "$GATE_REASON"
expect_absent "27q7 …no word of the comment is read as a suite" \
  "read-only" "$GATE_VERR"

# NON-VACUITY, BOTH WAYS. (i) An ordinary no-instrument brief — no `Suites:` label at all —
# keeps the detail it has always had and never gains the clause. (ii) An all-comment
# `Suites:` beside a `Files:` declaration is not refused at all: the clause is a sentence
# in one arm's detail, never a new refusal.
REPO=$(make_repo r27q8 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27q8.md' "w27q-noinstrument")"
expect_eq "27q8 a brief with no Suites: label at all is refused as before" "deny" "$GATE_VERDICT"
expect_contains "27q8 …same verdict" "declares no Files: and no Suites:" "$GATE_ERR"
expect_absent "27q8 …and never the comment clause" "its span is a comment" "$GATE_ERR$GATE_REASON"

REPO=$(make_repo r27q9 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/w27q9.md
Suites: # the marked runs below are the whole budget
Re-executes: `pytest tests/unit`' "w27q-runsplus")"
expect_status "27q9 an all-comment Suites: beside a declared run is ADMITTED" \
  "0" "$GATE_ST"
S27Q9_ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_contains "27q9 …non-vacuity: the declared run really is the row's budget" \
  "re_executes=\`pytest tests/unit\`" "$S27Q9_ROW"
expect_absent "27q9 …and no word of the comment reaches the row" "whole budget" \
  "$S27Q9_ROW"

# ============================================================================

setup_section "S28: the full-run wall asks the proof state (wave-26 REQ-3, D6)"
# ============================================================================
#
# THE FULL SUITE IS TIED TO THE CODE STATE, NOT TO A COUNT OF RUNS. Through 1.10 this wall
# counted full-tree rows on the roster and charged one `regression-cause:` line per extra
# run, and a sibling arm held the floor while any step-4 row was open unless a cause line
# released it. Both arms are gone. The wall now asks the proof record one question
# (`proof_state`, payload/scripts/lib/proof.sh): is the working branch's head the one the
# last floor proof names (`covered`), is the change since that proof provable by a named
# set of suites (`bounded`), or neither (`unbounded`)? A full run is admitted only when the
# state is unbounded and no row that writes tracked files is open.
#
# THE FIXTURE (pf_repo) IS A REAL REPOSITORY ON A WORKING BRANCH. Five committed suites under
# tests/ are the roster; `.bionic/config.yaml` names a map stub that answers lib/one.sh with
# three suites, lib/every.sh with all five, and anything else with nothing. Every shape the
# state depends on — the floor head, the commits since it, which branches carry them — is a
# git fact the fixture builds, never a value handed to the code under test.
#
# fails-when: the wall admits the run because a cause line exists (AC-3.3); an empty answer
# is read as "no suite needed" (AC-3.4); the cause-line arm survives, or the wall reads
# roster row counts, not the proof (AC-3.5).

# [PF_LIB_DIR, PF_MAP (and the map stub it names), PF_FULL_BRIEF, pf_repo, pf_commit, pf_plan_path, pf_row, PF_STATE_EXTRA, pf_plan, pf_state, pf_line: defined in tests/dispatch-preflight.prelude.sh, hoisted from here for the shards — wave-30 T1]

section "§PROOF-BOUNDED — a change the map bounds refuses the full run and names its suites (AC-3.3)"
REPO=$(pf_repo rpb)
write_attestation "$REPO" "$SID_A"
PF_H=$(git -C "$REPO" rev-parse HEAD)
pf_commit "$REPO" lib/one.sh 'one, changed'
# THE CAUSE LINE IS PLANTED ON PURPOSE: AC-3.3 fails when the wall admits the run because one
# exists. Through 1.10 this exact line released a second full run.
PF_STATE_EXTRA='regression-cause: the tree must be re-proved'
pf_plan "$REPO" "$PF_H"
PF_STATE_EXTRA=""
expect_eq "PB.1 proof_state: one changed file the map answers with three of five suites is bounded by those three" \
  "$(printf 'bounded\ta.test.sh b.test.sh c.test.sh')" "$(pf_state "$REPO")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$PF_FULL_BRIEF" "w-pb-full")"
expect_eq "PB.2 a full-run dispatch after a floor proof is REFUSED when the change is bounded" \
  "deny" "$GATE_VERDICT"
expect_contains "PB.2 …though the plan carries a regression-cause: line, which buys nothing now" \
  "regression-cause:" "$(cat "$(pf_plan_path "$REPO")")"
expect_contains "PB.2 …the one line says the change is bounded" "bounded" "$(pf_line)"
expect_contains "PB.2 …and the detail names the three suites, ready to copy into a brief" \
  "Suites: tests/a.test.sh tests/b.test.sh tests/c.test.sh" "$GATE_VERR"
expect_absent "PB.2 …and no suite the map did not answer" "d.test.sh" "$GATE_VERR"
expect_contains "PB.2 …naming the proved head it measured from" "${PF_H:0:7}" "$GATE_VERR"
expect_absent "PB.2 …and asks for no cause line" "regression-cause" "$GATE_VERR"
expect_status "PB.2 …and the refused dispatch journalled no row" \
  "0" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: prove the change.
Expected artifact: .bionic/docs/record/w28-bounded.txt
Expected duration: ~10 minutes.
Suites: tests/a.test.sh tests/b.test.sh tests/c.test.sh' "w-pb-narrow")"
expect_eq "PB.3 the brief the refusal names, those three suites, dispatches" "allow" "$GATE_VERDICT"

# A TASK BRANCH OF THIS RUN IS NOT OUTSIDE WORK. The same one-file change, landed through
# `wt/99-T1` the way the land verb merges, stays bounded: only another branch's commit makes
# the change unbounded (the discriminator for PU.3 below).
REPO=$(pf_repo rpbt)
PF_H=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q -b wt/99-T1 2>/dev/null
pf_commit "$REPO" lib/one.sh 'one, from the task'
git -C "$REPO" checkout -q wave/99-test 2>/dev/null
git -C "$REPO" merge -q --no-ff -m 'merge wt/99-T1 (land)' wt/99-T1 2>/dev/null
pf_plan "$REPO" "$PF_H"
expect_eq "PB.4 a change landed from the run's own task branch stays bounded" \
  "$(printf 'bounded\ta.test.sh b.test.sh c.test.sh')" "$(pf_state "$REPO")"

section "§PROOF-UNBOUNDED — what no named set of suites can prove admits the full run (AC-3.4)"
# A NEW FILE UNDER A DIRECTORY NO SUITE NAMES. The map answers it with nothing, and nothing is
# not "no suite needed": it is a change no suite is known to prove.
REPO=$(pf_repo rpu1)
write_attestation "$REPO" "$SID_A"
PF_H=$(git -C "$REPO" rev-parse HEAD)
pf_commit "$REPO" newdir/zz.sh 'new'
pf_plan "$REPO" "$PF_H"
PF_S=$(pf_state "$REPO")
expect_eq "PU.1 proof_state: a file the map answers with nothing is unbounded" "unbounded" "${PF_S%%$'\t'*}"
expect_contains "PU.1 …and the reason names the file" "newdir/zz.sh" "$PF_S"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$PF_FULL_BRIEF" "w-pu1-full")"
expect_eq "PU.1 …and the full run is ADMITTED, with no cause line on the plan" "allow" "$GATE_VERDICT"
expect_status "PU.1 …and journalled" "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# A CHANGE THE MAP ANSWERS WITH EVERY SUITE. The union is the roster, which is a full run by
# another name.
REPO=$(pf_repo rpu2)
PF_H=$(git -C "$REPO" rev-parse HEAD)
pf_commit "$REPO" lib/every.sh 'every, changed'
pf_plan "$REPO" "$PF_H"
PF_S=$(pf_state "$REPO")
expect_eq "PU.2 proof_state: a change the map answers with every suite is unbounded" "unbounded" "${PF_S%%$'\t'*}"
expect_contains "PU.2 …and the reason says every suite" "every suite" "$PF_S"

# A COMMIT ANOTHER BRANCH CONTAINS. The file is one the map bounds (PB.1), so only the outside
# rule can make this unbounded: a merge brings work no proof of this run has read.
REPO=$(pf_repo rpu3)
write_attestation "$REPO" "$SID_A"
PF_H=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q -b other-work 2>/dev/null
pf_commit "$REPO" lib/one.sh 'one, from outside'
git -C "$REPO" checkout -q wave/99-test 2>/dev/null
git -C "$REPO" merge -q --no-ff -m 'merge other-work' other-work 2>/dev/null
pf_plan "$REPO" "$PF_H"
PF_S=$(pf_state "$REPO")
expect_eq "PU.3 proof_state: a range holding a commit another branch contains is unbounded" \
  "unbounded" "${PF_S%%$'\t'*}"
expect_contains "PU.3 …and the reason says another branch carries it" "another branch" "$PF_S"

# NO FLOOR PROOF YET: the first full run of a plan is always admitted.
REPO=$(pf_repo rpu4)
write_attestation "$REPO" "$SID_A"
pf_plan "$REPO" ""
PF_S=$(pf_state "$REPO")
expect_eq "PU.4 proof_state: a plan with no regression proof is unbounded" "unbounded" "${PF_S%%$'\t'*}"
expect_contains "PU.4 …saying so" "no regression proof on this plan yet" "$PF_S"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$PF_FULL_BRIEF" "w-pu4-full")"
expect_eq "PU.4 …and the plan's first full run is ADMITTED" "allow" "$GATE_VERDICT"

# THE RUN WAITS FOR THE RUN THE WALL ADMITS (wave-26 T64; AC-3.4). Integrate's `proof:floor` read
# stands only while the state is covered or bounded, so on PU.1's change it waits, naming a full
# run on the head; this wall must keep admitting exactly that run, or the two would deadlock. A
# reads table at current: 8: the floor and review rows landed, integrate pending on its kind
# default, a floor proof at the base and a new file under a directory no suite names since.
REPO=$(pf_repo rpu64)
write_attestation "$REPO" "$SID_A"
PF_H=$(git -C "$REPO" rev-parse HEAD)
pf_commit "$REPO" newdir/zz.sh 'new'
pf_plan "$REPO" "$PF_H"
awk '{ print } /^approved-by:/ { print "proved: kind=review head='"$PF_H"' at=2026-10-04T00:00:00Z evidence=record/w99-review.md" }' \
  "$(pf_plan_path "$REPO")" > "$SANDBOX/pu64.tmp"
{ sed 's/^current: 5$/current: 8/' "$SANDBOX/pu64.tmp"
  printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | reads | status |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
  printf '| T1 | 4 | build | a | implementor | — | 30 | REQ-1 | lib/one.sh |  | landed |\n'
  printf '| T5 | 5 | verify | the floor | test-runner | — | 30 | REQ-1 | .bionic/docs/record/w99-floor.txt |  | landed |\n'
  printf '| T2 | 6 | review | the review | critic | — | 30 | REQ-1 | .bionic/docs/record/w99-review.md |  | landed |\n'
  printf '| T3 | 8 | integrate | merge | — | — | 10 | REQ-1 | — |  | pending |\n'
} > "$(pf_plan_path "$REPO")"
PF_W64="$( . "$PF_LIB_DIR/units.sh" >/dev/null 2>&1; units_waiting "$(pf_plan_path "$REPO")" 8 2>/dev/null)"
expect_contains "PU.64 precondition: integrate waits for a full run on this head (the ready set's own wait)" \
  "proof:floor: the head moved past the regression proof at ${PF_H:0:12} in a way the map cannot bound (the map answers newdir/zz.sh with no suite)" \
  "$PF_W64"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$PF_FULL_BRIEF" "w-pu64-full")"
expect_eq "PU.64 …and the full run it waits for is ADMITTED (the wait and the wall do not deadlock)" "allow" "$GATE_VERDICT"
expect_status "PU.64 …and journalled" "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# UNBOUNDED IS NOT ENOUGH WHILE A ROW THE FLOOR WAITS ON STILL WRITES TRACKED FILES. A full run
# over a head that such a row is about to move proves a tree that does not survive it landing.
# ONLY THOSE ROWS HOLD IT (wave-26 T52; review 14 B1, ruling R1): through T5 this row asserted
# that a pending row at a LATER step held the floor too, and on this wave's own plan that was
# the release, which waits on the floor — a deadlock. PU.5 now asserts the ruling: the rows the
# floor row waits on (its deps and its reads, the ready set's own judgment), not landed, whose
# Files leave the record by units.sh `writes_head`. The dispatch names the floor row (T12).
REPO=$(pf_repo rpu5)
write_attestation "$REPO" "$SID_A"
pf_plan "$REPO" "" \
  "$(pf_row T1 4 landed lib/one.sh)" \
  "$(pf_row T2 4 active 'lib/two.sh, tests/two.test.sh')" \
  "$(pf_row T4 4 active 'record/w99/T4-notes.md')" \
  "$(pf_row T12 5 pending .bionic/docs/record/w99-floor.txt verify 'T1, T2, T4')" \
  "$(pf_row T3 7 pending 'CHANGELOG.md, lib/one.sh!' doc T12)"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$PF_FULL_BRIEF" "w99-T12")"
expect_eq "PU.5 an unbounded full run is REFUSED while a row the floor waits on writes tracked files" \
  "deny" "$GATE_VERDICT"
expect_contains "PU.5 …the one line names that active writer" "T2" "$(pf_line)"
expect_absent "PU.5 …but not the release that waits on the floor, though its Files are tracked (R1)" "T3" "$(pf_line)"
expect_absent "PU.5 …nor the landed row" "T1" "$(pf_line)"
expect_absent "PU.5 …nor the open row whose only Files are record/… (writes_head says no)" "T4" "$(pf_line)"
expect_contains "PU.5 …the detail gives it its step and status" "step 4, active" "$GATE_VERR"
expect_absent "PU.5 …and asks for no cause line" "regression-cause" "$GATE_VERR"
expect_status "PU.5 …and journalled no row" "0" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"
# A DISPATCH THAT NAMES NO ROW is held by what the plan's open verify rows wait on: the same T2.
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$PF_FULL_BRIEF" "w-pu5-full")"
expect_eq "PU.5b a full run that names no row is held by what the open verify row waits on" "deny" "$GATE_VERDICT"
expect_contains "PU.5b …naming T2" "T2" "$(pf_line)"
expect_absent "PU.5b …and not the release" "T3" "$(pf_line)"
# THIS WAVE'S OWN SHAPE (V14-hold.sh): every build row landed, the verify and review rows
# pending, a release row that writes tracked files and waits on the verify row. Through T5 the
# release held the floor; the floor is admitted now.
REPO=$(pf_repo rpu5c)
write_attestation "$REPO" "$SID_A"
pf_plan "$REPO" "" \
  "$(pf_row T1 4 landed lib/one.sh)" \
  "$(pf_row T2 4 landed 'lib/two.sh, tests/two.test.sh')" \
  "$(pf_row T27 5 pending .bionic/docs/record/w99-floor.txt verify 'T1, T2')" \
  "$(pf_row T28 6 pending .bionic/docs/record/w99-review.md review 'T1, T2')" \
  "$(pf_row T29 7 pending 'CHANGELOG.md, tests/docs-pins.test.sh' doc 'T27, T28')"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$PF_FULL_BRIEF" "w99-T27")"
expect_eq "PU.5c this wave's shape: the Step-5 floor is ADMITTED while the release waits on it" "allow" "$GATE_VERDICT"
expect_absent "PU.5c …with nothing from this arm on the wire" "write tracked files" "$GATE_ERR"
expect_status "PU.5c …and journalled" "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"
REPO=$(pf_repo rpu6)
write_attestation "$REPO" "$SID_A"
pf_plan "$REPO" "" \
  "$(pf_row T1 4 landed lib/one.sh)" \
  "$(pf_row T2 4 dropped lib/two.sh)" \
  "$(pf_row T12 5 pending .bionic/docs/record/w99-floor.txt)"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$PF_FULL_BRIEF" "w-pu6-full")"
expect_eq "PU.6 with every tracked-file writer landed or dropped, the full run is ADMITTED" "allow" "$GATE_VERDICT"
expect_absent "PU.6 …with nothing from this arm on the wire" "write tracked files" "$GATE_ERR"

# ---- wave-26 T52: review 14 S1, S2, N5, N7 (ruling R2), N8 ----
# S1 — AN OUTSIDE COMMIT IS SEEN ON A REMOTE-TRACKING REF OR A TAG, not only on a local branch.
# `git merge origin/feat` or a merge of a tag brings work no proof of this run read; the file is
# one the map bounds (PB.1), so only the outside rule can make it unbounded.
REPO=$(pf_repo rpu7)
PF_H=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q --detach 2>/dev/null
pf_commit "$REPO" lib/one.sh 'one, from a remote'
git -C "$REPO" update-ref refs/remotes/origin/feat HEAD
git -C "$REPO" checkout -q wave/99-test 2>/dev/null
git -C "$REPO" merge -q --no-ff -m 'merge origin/feat' origin/feat 2>/dev/null
pf_plan "$REPO" "$PF_H"
PF_S=$(pf_state "$REPO")
expect_eq "PU.7 S1 a merge from a remote-tracking ref only is unbounded" "unbounded" "${PF_S%%$'\t'*}"
expect_contains "PU.7b …saying another branch carries it" "another branch" "$PF_S"
REPO=$(pf_repo rpu7t)
PF_H=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q --detach 2>/dev/null
pf_commit "$REPO" lib/one.sh 'one, from a tag'
git -C "$REPO" tag v-outside HEAD
git -C "$REPO" checkout -q wave/99-test 2>/dev/null
git -C "$REPO" merge -q --no-ff -m 'merge v-outside' v-outside 2>/dev/null
pf_plan "$REPO" "$PF_H"
PF_S=$(pf_state "$REPO")
expect_eq "PU.7c S1 a merge from a tag only is unbounded" "unbounded" "${PF_S%%$'\t'*}"
# …AND THE RUN'S OWN WORK, PUSHED, STAYS BOUNDED: the wave branch and a task branch on the
# remote are excluded like their local names.
REPO=$(pf_repo rpu7w)
PF_H=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q -b wt/99-T1 2>/dev/null
pf_commit "$REPO" lib/one.sh 'one, from the task'
git -C "$REPO" update-ref refs/remotes/origin/wt/99-T1 HEAD
git -C "$REPO" checkout -q wave/99-test 2>/dev/null
git -C "$REPO" merge -q --no-ff -m 'merge wt/99-T1 (land)' wt/99-T1 2>/dev/null
git -C "$REPO" update-ref refs/remotes/origin/wave/99-test HEAD
pf_plan "$REPO" "$PF_H"
expect_eq "PU.7d S1 control: the run's own task branch, landed and pushed with the wave branch, stays bounded" \
  "$(printf 'bounded\ta.test.sh b.test.sh c.test.sh')" "$(pf_state "$REPO")"

# A SECOND MAP STUB, SHAPED LIKE THE SHIPPED MAP: one line per suite, naming the first file that
# reaches it, so a file whose suites another changed file already claims is named by no line.
# lib/one.sh reaches a b c; a suite file reaches itself; lib/ghost.sh reaches a and a suite the
# checkout does not hold; the runner and the test library are answered like the shipped map
# answers them (some suites, not every one).
PF_MAP2="$SANDBOX/pf-map2.sh"
{
  printf '#!/bin/bash\n'
  printf 'seen=" "\n'
  printf 'say() { case "$seen" in *" $1 "*) return ;; esac; seen="$seen$1 "; printf "%%s\\t%%s:%%s\\n" "$1" "$2" "$3"; }\n'
  printf 'for f in "$@"; do\n'
  printf '  case "$f" in\n'
  printf '    lib/one.sh)       for s in a b c; do say "$s.test.sh" dir-ref "$f"; done ;;\n'
  printf '    lib/ghost.sh)     say a.test.sh path-ref "$f"; say gone.test.sh path-ref "$f" ;;\n'
  printf '    tests/lib/*)      say a.test.sh source "$f" ;;\n'
  printf '    tests/*.test.sh)  say "${f#tests/}" self "$f" ;;\n'
  printf '    tests/*)          say a.test.sh path-ref "$f"; say b.test.sh path-ref "$f" ;;\n'
  printf '  esac\n'
  printf 'done\n'
} > "$PF_MAP2"
pf_repo2() { local r; r=$(pf_repo "$1"); printf 'impact-command: bash %s\n' "$PF_MAP2" > "$r/.bionic/config.yaml"; printf '%s' "$r"; }

# S2 — A FILE WHOSE SUITES ANOTHER CHANGED FILE CLAIMS IS STILL ANSWERED. lib/one.sh alone is
# bounded; lib/one.sh with tests/a.test.sh read as "tests/a.test.sh with no suite" through T5.
REPO=$(pf_repo2 rpu8)
PF_H=$(git -C "$REPO" rev-parse HEAD)
pf_commit "$REPO" lib/one.sh 'one, changed'
pf_commit "$REPO" tests/a.test.sh $'#!/bin/bash\n# changed'
pf_plan "$REPO" "$PF_H"
expect_eq "PU.8 S2 a changed suite whose one suite another changed file names keeps the change bounded" \
  "$(printf 'bounded\ta.test.sh b.test.sh c.test.sh')" "$(pf_state "$REPO")"
# …and a file the map truly answers with nothing still says so, by name.
pf_commit "$REPO" newdir/zz.sh 'new'
PF_S=$(pf_state "$REPO")
expect_eq "PU.8b S2 control: with a file no suite reaches, the change is unbounded" "unbounded" "${PF_S%%$'\t'*}"
expect_contains "PU.8c …naming that file, not the claimed one" "newdir/zz.sh with no suite" "$PF_S"

# N8 — A SUITE THE CHECKOUT DOES NOT HOLD IS NEVER NAMED, and deleting a suite is unbounded: the
# roster the full run reads has changed, and no remaining suite is known to prove the deletion.
REPO=$(pf_repo2 rpu9)
PF_H=$(git -C "$REPO" rev-parse HEAD)
pf_commit "$REPO" lib/ghost.sh 'ghost'
pf_plan "$REPO" "$PF_H"
expect_eq "PU.9 N8 a suite the map names that the checkout lacks is dropped from the bounded set" \
  "$(printf 'bounded\ta.test.sh')" "$(pf_state "$REPO")"
git -C "$REPO" rm -q tests/e.test.sh
git -C "$REPO" commit -qm 'drop suite e' 2>/dev/null
PF_S=$(pf_state "$REPO")
expect_eq "PU.9b N8 a change that deletes a suite is unbounded" "unbounded" "${PF_S%%$'\t'*}"
expect_contains "PU.9c …saying which suite it deletes" "deletes the suite tests/e.test.sh" "$PF_S"

# N7 / R2 — A CHANGE TO THE RUNNER OR TO tests/lib/ OWES A FULL RUN, whatever the map says. The
# map stub answers both with a suite or two, as the shipped map does (11 suites for the runner).
# Committed with `add tests`, so no command line here carries the runner's path.
REPO=$(pf_repo2 rpu10)
PF_H=$(git -C "$REPO" rev-parse HEAD)
printf '#!/bin/bash\necho changed\n' > "$REPO/tests/run.sh"
( cd "$REPO" && git add tests && git commit -qm 'change the runner' ) >/dev/null 2>&1
pf_plan "$REPO" "$PF_H"
PF_S=$(pf_state "$REPO")
expect_eq "PU.10 R2 a change to the full-suite runner alone is unbounded" "unbounded" "${PF_S%%$'\t'*}"
expect_contains "PU.10b …saying it is the runner every suite runs through" "the full-suite runner" "$PF_S"
REPO=$(pf_repo2 rpu10l)
PF_H=$(git -C "$REPO" rev-parse HEAD)
pf_commit "$REPO" tests/lib/assert.sh '# the framework'
pf_plan "$REPO" "$PF_H"
PF_S=$(pf_state "$REPO")
expect_eq "PU.10c R2 a change under tests/lib/ is unbounded" "unbounded" "${PF_S%%$'\t'*}"
expect_contains "PU.10d …naming the file" "tests/lib/assert.sh" "$PF_S"
# …and the same stub bounds an ordinary tests/ file it answers (the discriminator).
REPO=$(pf_repo2 rpu10c)
PF_H=$(git -C "$REPO" rev-parse HEAD)
pf_commit "$REPO" tests/fixtures/x.txt 'fixture'
pf_plan "$REPO" "$PF_H"
expect_eq "PU.10e R2 control: a fixture file under tests/ stays bounded by the map" \
  "$(printf 'bounded\ta.test.sh b.test.sh')" "$(pf_state "$REPO")"

# N5 — A MAP THAT OVERRUNS ITS BOUND IS KILLED, NOT LEFT RUNNING. The stub loops for ever; the
# bound is set to one second for this row only (the shipped bound is §29's subject).
PF_SLOW="$SANDBOX/pf-slow-map-$$.sh"
printf '#!/bin/bash\nwhile :; do sleep 0.1; done\n' > "$PF_SLOW"
bash "$PF_SLOW" & PF_SLOW_PID=$!
sleep 0.3
expect_nonempty "PU.11 precondition: pgrep sees the slow map while it runs" "$(pgrep -f "pf-slow-map-$$" 2>/dev/null)"
kill "$PF_SLOW_PID" 2>/dev/null; wait "$PF_SLOW_PID" 2>/dev/null
REPO=$(pf_repo rpu11)
printf 'impact-command: bash %s\n' "$PF_SLOW" > "$REPO/.bionic/config.yaml"
PF_H=$(git -C "$REPO" rev-parse HEAD)
pf_commit "$REPO" lib/one.sh 'one, changed'
pf_plan "$REPO" "$PF_H"
PF_S=$( (IMPACT_BOUND_S=1; export IMPACT_BOUND_S; pf_state "$REPO") )
expect_contains "PU.11b N5 a map that overruns is unbounded, saying so" "overran its 1 s bound" "$PF_S"
sleep 0.3
PF_LEFT="$(pgrep -f "pf-slow-map-$$" 2>/dev/null)"
expect_eq "PU.11c N5 …and no map process is left running after the answer" "" "$PF_LEFT"
# shellcheck disable=SC2086
[ -z "$PF_LEFT" ] || kill $PF_LEFT 2>/dev/null

section "§PROOF-COVERED — the proved head refuses, an outside merge admits (AC-3.5)"
REPO=$(pf_repo rpc)
write_attestation "$REPO" "$SID_A"
PF_H=$(git -C "$REPO" rev-parse HEAD)
pf_plan "$REPO" "$PF_H"
PF_S=$(pf_state "$REPO")
expect_eq "PC.1 proof_state: the head the last floor proof names is covered" "covered" "${PF_S%%$'\t'*}"
expect_eq "PC.1 …and it names the working head it judged (N6)" "$PF_H" "${PF_S#*$'\t'}"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$PF_FULL_BRIEF" "w-pc-full")"
expect_eq "PC.1 a full run on the proved head is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "PC.1 …the one line says the head is proved" "already proved" "$(pf_line)"
expect_contains "PC.1 …the detail names the head and the evidence" "record/w99-floor.txt" "$GATE_VERR"
expect_contains "PC.1 …and the head" "${PF_H:0:7}" "$GATE_VERR"
# …AND AFTER AN OUTSIDE MERGE THE SAME PLAN DISPATCHES, with no cause line written anywhere.
git -C "$REPO" checkout -q -b other-work 2>/dev/null
pf_commit "$REPO" lib/one.sh 'one, from outside'
git -C "$REPO" checkout -q wave/99-test 2>/dev/null
git -C "$REPO" merge -q --no-ff -m 'merge other-work' other-work 2>/dev/null
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$PF_FULL_BRIEF" "w-pc-after")"
expect_eq "PC.2 after an outside merge the full run is ADMITTED" "allow" "$GATE_VERDICT"
expect_absent "PC.2 …and the plan carries no regression-cause: line" "regression-cause" \
  "$(cat "$(pf_plan_path "$REPO")")"
expect_contains "PC.2 …(the plan read is the one with the floor proof)" "proved: kind=floor" \
  "$(cat "$(pf_plan_path "$REPO")")"
expect_status "PC.2 …and journalled" "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# THE ARM READS NO CAUSE LINE AND NO ROSTER COUNT. A second admitted full run on an unbounded
# change is not a count the wall keeps: the roster already holds w-pc-after's row.
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$PF_FULL_BRIEF" "w-pc-again")"
expect_eq "PC.3 a second full run on the same unbounded change is not refused by a roster count" \
  "allow" "$GATE_VERDICT"
expect_eq "PC.3 …the hook defines no cause-line reader" "0" \
  "$(/usr/bin/grep -c 'regression_causes\|regression-cause' "$GATE")"
expect_eq "PC.3 …and no roster counter of full-tree rows" "0" "$(/usr/bin/grep -c 'regression_rows' "$GATE")"
expect_nonempty "PC.3 …(the extractor reads the hook: it holds the proof_state call)" \
  "$(/usr/bin/grep -n 'proof_state' "$GATE")"

# N6 (wave-26 T52) — AN EMPTY DIFFERENCE WITH ANOTHER HEAD IS COVERED (A-T5.5), AND THE REFUSAL
# NAMES THE HEAD BEING RELEASED. Through T5 it named the proof's head and called the working head
# "the one the plan's last floor proof names", which an empty commit made untrue.
REPO=$(pf_repo rpc4)
write_attestation "$REPO" "$SID_A"
PF_H=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" commit -q --allow-empty -m 'an empty commit' 2>/dev/null
PF_H2=$(git -C "$REPO" rev-parse HEAD)
pf_plan "$REPO" "$PF_H"
PF_S=$(pf_state "$REPO")
expect_eq "PC.4 proof_state: an empty change since the proof is covered" "covered" "${PF_S%%$'\t'*}"
expect_eq "PC.4b …naming the working head, not the proof's" "$PF_H2" "${PF_S#*$'\t'}"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$PF_FULL_BRIEF" "w-pc4-full")"
expect_eq "PC.4c the full run is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "PC.4d …the one line names the released head" "head ${PF_H2:0:7} is already proved" "$(pf_line)"
expect_contains "PC.4e …and the detail the tree proved at the proof's head" "(the tree proved at ${PF_H:0:7})" "$GATE_VERR"

section "SECTION 29 — the derivation is BOUNDED, and the overrun is a refusal (review-c C-16)"
# THE DEFECT. The impact command is the whole of this gate's cost — ~0.3 s without it,
# ~2.9-3.1 s with it on an idle tree, 5.06-6.51 s measured while this wave's own writers
# were running. hooks/hooks.json registers the hook at a timeout of its own and the call
# had no bound of its own. A PreToolUse hook killed on the CLI's timeout does NOT exit 2: the
# dispatch proceeds, NO ROSTER ROW IS WRITTEN, and the writer runs with no budget at all —
# the wall defeated by the cost of the wall. So the bound is built here, and it refuses.
#
# NO SEAM. The bound is the shipped constant, not a value this suite hands the hook; the
# stub below simply outruns it. A test that shortened the bound would prove a constant it
# had itself supplied and leave the production path unverified.
#
# AND THE CONSTANT IS READ, NOT TRANSCRIBED (wave-14 REQ-7, D4). It moved from a literal in
# the hook to `payload/scripts/lib/bounds.sh`, which both this wall and the landing sweep
# source; a number typed here would go stale the first time the library's does, and the
# assertions below would then be pinning this file's memory of the bound rather than the
# bound. `s29_impact`'s sleep is derived from it for the same reason.
S29_BOUND="$(bash -c '. "$1" 2>/dev/null && printf "%s" "${IMPACT_BOUND_S:-}"' _ \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/bounds.sh" 2>/dev/null)"
expect_nonempty "29 the shipped bound is readable from lib/bounds.sh" "$S29_BOUND"

# [s29_impact: defined in tests/dispatch-preflight.prelude.sh, hoisted from here for the shards — wave-30 T1]

# --- 29a: a derivation that outruns the bound REFUSES, and refuses in time ---
REPO=$(make_repo r29a yes)
write_attestation "$REPO" "$SID_A"
s29_impact "$REPO" $(( S29_BOUND + 10 ))
S29_T0=$(date +%s)
GATE_HIRES=1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w29-slow")"
GATE_HIRES=""
# THE WALL'S OWN COST, not the suite's: `run_gate` drives the call a second time with
# BIONIC_WALL_VERBOSE=1 to read `detail`, and that second bounded derivation would double
# the number measured here. `$GATE_TIME` is the first drive alone.
S29_ELAPSED="$GATE_TIME_CS"
expect_eq "29a a derivation that outruns the bound REFUSES the dispatch" "deny" "$GATE_VERDICT"
expect_contains "29a …naming the bound it outran" "bound:   ${S29_BOUND}s" "$GATE_VERR"
expect_contains "29a …naming the command that was slow" "impact-stub.sh" "$GATE_VERR"
expect_contains "29a …naming the paths it was asked about" "payload/scripts/lib/widget.sh" "$GATE_VERR"
expect_contains "29a …and saying why an unbounded one would be worse" "no roster row" "$GATE_VERR"
# THE POINT OF THE BOUND IS THE CLOCK: the wait ends when the bound says so and not when
# the command finishes. The stub sleeps ten seconds longer than the bound, so a gate that
# waited for it would be caught here.
#
# THIS ASSERTION USED TO READ `< 10`, THE HOOK'S OWN REGISTRATION IN hooks/hooks.json, and
# it is re-pinned to the bound instead (wave-14 T6, A-T6.5) — NOT because the registration
# stopped mattering. THE GAP A-T6.5 NAMED IS CLOSED (wave-14 T35, D1 by Chris): the bound
# was 20 under a registration of 10, so on the machine the CLI killed this hook before its
# own bound could fire, and a hook killed on the CLI timeout does not exit 2 — the exact
# failure the bound exists to prevent, invisible here because a suite has no CLI timeout.
# Both numbers moved: the registration to 15, the bound to 10, five seconds clear. What
# this file discharges is AC-7.2, that the wait ends when the bound says so; that the bound
# sits strictly UNDER its registration is a two-file claim neither file can make alone, and
# tests/cross-gate-agreement.test.sh §L.4c is where it is pinned.
# EIGHT SECONDS OF SLACK WAS ENOUGH TO HIDE THE DEFECT IT WAS WATCHING (wave-14 T34). This
# read `< S29_BOUND + 8` over a whole-second clock. The gate's wait was denominated in
# `sleep 0.1` polls costing 115 ms each, so a stated 20s bound waited 23.0-23.2s — comfortably
# inside `+8`, and therefore green, for as long as the drift stayed under eight seconds,
# which is to say for as long as nobody was under enough load to care. Measured: 22s here
# and 22s at §hanging-impact on the tick-counted wait, against 20s and 21s on the clock.
#
# THE SLACK IS ONE SECOND NOW, AND THE CLOCK CAN SEE IT. `$GATE_TIME_CS` is the first
# drive in hundredths (`GATE_HIRES` above), so what is left to absorb is the gate's own
# non-waiting work rather than a second of rounding at each end. A wait denominated in
# anything that stretches under load misses by seconds and fails here.
if [ "$S29_ELAPSED" -le $(( (S29_BOUND + 1) * 100 )) ]; then
  ok "29a …and it stopped waiting at the bound, not at the sleep ($(( S29_ELAPSED / 100 )).$(printf '%02d' $(( S29_ELAPSED % 100 )))s)"
else
  no "29a …and it stopped waiting at the bound, not at the sleep" \
    "took $(( S29_ELAPSED / 100 )).$(printf '%02d' $(( S29_ELAPSED % 100 )))s against a ${S29_BOUND}s bound"
fi
# FAIL-CLOSED MEANS NO ROW. A refused dispatch journals nothing, so there is no row a
# writer-side guard could read as "no budget was stated" and stand aside on.
expect_status "29a …and journalled no row at all" \
  "0" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# --- 29b: CONTROL — the same brief, the same stub, fast, still derives and passes ---
REPO=$(make_repo r29b yes)
write_attestation "$REPO" "$SID_A"
s29_impact "$REPO" 0
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w29-fast")"
expect_status "29b control: the same stub, prompt, PASSES" "0" "$GATE_ST"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "29b …and the derived budget is the stub's answer" \
  "alpha.test.sh" "$(roster_field "$ROW" suites_allowed)"
expect_status "29b …recorded as derived" "derived" "$(roster_field "$ROW" suites_source)"

# --- 29c: a derivation that answers NOTHING is unchanged: empty budget, a warning ---
# The overrun is a refusal because the alternative is an unwritten row; a command that
# fails or answers nothing has still answered, and the third state (`suites_allowed=` empty)
# already has readers. This is the boundary between the two, asserted so a later edit
# cannot quietly turn one into the other.
REPO=$(make_repo r29c yes)
write_attestation "$REPO" "$SID_A"
mkdir -p "$REPO/.bionic"
printf '#!/bin/bash\nexit 3\n' > "$REPO/.bionic/impact-stub.sh"
chmod +x "$REPO/.bionic/impact-stub.sh"
printf 'impact-command: bash %s/.bionic/impact-stub.sh\n' "$REPO" > "$REPO/.bionic/config.yaml"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FILES" "w29-empty")"
expect_status "29c a derivation that answers nothing still PASSES" "0" "$GATE_ST"
expect_contains "29c …with the operator warned at the moment the config is fixable" \
  "derived no suites" "$GATE_ERR"
ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
expect_status "29c …and the row records the empty third state" "" "$(roster_field "$ROW" suites_allowed)"

# --- 29d/29e: the overrun refusal keeps whatever brief-shape faults were already
# collected (review-c19c16e F3, wave-12 T23, AC-1.1's fails-when). A15 sat between the
# five collecting arms and dp_refuse_findings and refused on the spot, discarding
# DP_FINDINGS — an ambiguous-label brief with a slow impact command was told about the
# label alone on attempt 1, and the impact overrun alone (with no memory of the label) on
# attempt 2. That is the exact one-fault-per-attempt loop T2 built dp_finding to end.

BRIEF_T23_COMBINED_IMPACT='Your task: review the wave.
Expected artifact: compare .bionic/docs/record/a-notes.md against .bionic/docs/record/b-notes.md
Expected duration: 20 minutes
Files: payload/scripts/lib/widget.sh'

# --- 29d: the ambiguous-label brief + an overrunning impact command -> ONE refusal, BOTH faults ---
REPO=$(make_repo r29d yes)
write_attestation "$REPO" "$SID_A"
s29_impact "$REPO" 30
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_T23_COMBINED_IMPACT" "w29d-slow")"
expect_eq "29d an ambiguous label + an overrunning impact command is refused ONCE" "deny" "$GATE_VERDICT"
expect_eq "29d …exactly one refusal line reaches the user" "1" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -c '^bionic: ' || true)"
expect_contains "29d …naming the multi-path fault (A11)" "several paths" "$GATE_VERR"
# T2 (D3, D11) NARROWS WHAT THIS CAN STILL PROVE. The several-fault wire no longer carries
# ANY per-finding rationale — not just the brief-shape kind C-2/R6-1/S18b above lost, but
# A15's config-shaped fact and Fix: too, since neither is one of the five scaffold labels
# and there is nowhere left on the wire to put it.
# T26 (critic Issue 3) NARROWS IT FURTHER STILL: the Expected artifact: line is no longer
# marked <ADD> even here, because `dp_scaffold_marked` now treats a non-empty candidate
# list as a label that WAS populated, just ambiguously — the same reasoning that keeps the
# absent-deliverable arm quiet on this brief (see A11 above; the second fault here is A15,
# not the absent-deliverable arm). The discriminator that A15 specifically fired — not just
# A11 — is what 29a already covers on its own single-fault path; this
# pair no longer distinguishes it from a combined-brief-fault-only refusal on the WIRE,
# which is a real narrowing this task surfaces rather than papers over (A-T2, assumptions.md).
expect_absent "29d …the Expected artifact: line is NOT marked <ADD> (a populated, ambiguous label)" \
  "$(scaffold_raw_line "$DISPATCH_FILE" "Expected artifact") <ADD>" "$GATE_VERR"
expect_status "29d …and journalled no roster row at all" "0" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# --- 29e: CONTROL — the same brief, a fast impact command -> the multi-path fault named,
# the impact fault absent: nothing overran, so there is nothing to append.
REPO=$(make_repo r29e yes)
write_attestation "$REPO" "$SID_A"
s29_impact "$REPO" 0
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_T23_COMBINED_IMPACT" "w29e-fast")"
# T26 (critic Issue 3): nothing overran, and A11 is now this brief's ONLY fault (Files:
# is declared, so the no-Files/no-Suites arm does not fire either) — the single-fault
# shape, not a pooled list (since wave-19 T4 one fault is a deny verdict too, its own detail on the reason).
expect_eq "29e control: the same brief, a fast impact command, is still refused" \
  "deny" "$GATE_VERDICT"
expect_contains "29e …naming the multi-path fault (A11)" "several paths" "$GATE_ERR"


# ===========================================================================

section "S30: the approval checkpoint — a writer needs an approved plan (epic-22 K2, AC-K2.4)"
# ===========================================================================
#
# WHY THE WRITER AND NOT ONLY THE COMMIT. The evidence gate refuses a commit made at
# `current: 4` while the plan carries no `approved-by:`. That is the right wall, and it is
# the LATE one: by the time it fires, eight writers have already read the brief, taken
# worktrees and written code against a plan nobody ratified. This arm is the early half —
# it refuses the writer, which is the first act of a plan that closing a file cannot undo.
#
# THE ROLE SET IS THE WHOLE DISCRIMINATION. Researchers, test-runners, auditors and critics
# are dispatched BEFORE approval as a matter of course: the research that informs the plan
# is exactly such a dispatch, and refusing it would refuse the work that produces the
# approval. So the arm names two roles and only two, matched whole.
#
# HERMETIC, like everything else here: `make_repo` writes a plan at `current: 4` with no
# `approved-by:` line, which is precisely the refused state; the pass cases add the line.

# k2_plan_line <repo> <line...> — rewrite the fixture plan's `## SDLC State` body.
k2_write_plan() {  # <repo> <current> <approved-by line, or "">
  local repo="$1" cur="$2" approved="$3"
  local dir="$repo/.bionic/docs/plans/epic-99-test"
  mkdir -p "$dir"
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n'
    printf -- 'intent: build\nrigor: double\nscale: wave\n---\n\n'
    printf -- '# Test wave plan\n\n## SDLC State\n\nintegration-branch: main\ncurrent: %s\n' "$cur"
    [ -n "$approved" ] && printf -- '%s\n' "$approved"
    printf -- '\n- Step %s: tasks in flight\n' "$cur"
  } > "$dir/wave-01-test.plan.md"
}

K2_APPROVED_LINE='approved-by: dana 2026-09-07T19:05Z "Ok, amazing! Approved."'

# k2_questions <role> <rigor> -> a newline and the `Questions:` line that rigor deals the role (REQ-1's
# table, wave-30 T11), or nothing for a role the line does not apply to. A reader brief
# without its dealt line is refused by the dispatch wall (§Q), whatever this section is testing.
k2_questions() {
  case "$2:$1" in
    double:bionic:auditor) printf '\nQuestions: evidence' ;;
    double:bionic:critic)  printf '\nQuestions: adversarial, structure' ;;
    single:bionic:critic)  printf '\nQuestions: evidence, adversarial, structure' ;;
  esac
  return 0
}

# --- 30a/30b: the two writer roles are refused while the line is absent ---
for _role in bionic:implementor bionic:senior-implementor; do
  _tag="30a"; [ "$_role" = "bionic:senior-implementor" ] && _tag="30b"
  REPO=$(make_repo "r${_tag}" yes)
  write_attestation "$REPO" "$SID_A"
  k2_write_plan "$REPO" 4 ""
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w${_tag}" "claude-sonnet-5" \
                               "$S5_LIVE_TRANSCRIPT" "$_role")"
  expect_eq "${_tag} a ${_role} dispatch at current: 4 with no approved-by is refused" "deny" "$GATE_VERDICT"
  expect_contains "${_tag} …and the refusal names the missing line" "approved-by" "$GATE_VERR"
  # NOT merely the plan path: an unbound session's own resolution announcement carries that
  # already, so a path assertion here would be green with no refusal printed at all.
  expect_contains "${_tag} …and says what a writer needs" "writers run against an APPROVED plan" "$GATE_VERR"
done

# --- 30c: THE CONTROL — the same dispatch with the line present passes ---
REPO=$(make_repo r30c yes)
write_attestation "$REPO" "$SID_A"
k2_write_plan "$REPO" 4 "$K2_APPROVED_LINE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w30c" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_status "30c control: the same writer dispatch with approved-by present passes" "0" "$GATE_ST"
expect_absent "30c …with no refusal printed" "BLOCKED" "$GATE_ERR"

# --- 30n: THE READER CANNOT BE LOADED — the writer is refused (wave-26 T56; final review N2) ---
# The approval is read by fill.sh's `fill_plan_approved`, sourced lazily at this arm. Before T56 a
# library directory without it said `not checked` and ADMITTED the writer; before wave 26 the line
# was read inline and an unapproved plan was refused. Ruled: an approval the hook cannot read is
# no approval. A copied hook beside a library directory that holds every file but fill.sh, on the
# APPROVED plan of 30c, is refused, naming the reader and the file; the same copy beside the whole
# library admits it, unchanged.
n2_plant() {  # <root> <with fill.sh: yes|no> -> the copied hook's path
  local root="$1" lib f
  lib="$(cd "${BIONIC_HOOKS_DIR}/../payload/scripts/lib" && pwd -P)"
  mkdir -p "$root/hooks" "$root/scripts/lib"
  for f in "$lib"/*; do
    [ "$2" = no ] && [ "${f##*/}" = fill.sh ] && continue
    ln -s "$f" "$root/scripts/lib/${f##*/}"
  done
  cp "$GATE" "$root/hooks/dispatch-preflight.sh"
  printf '%s' "$root/hooks/dispatch-preflight.sh"
}
N2_SAVED_GATE="$GATE"
N2_ROOT=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/n2-nofill.XXXXXX")" && pwd -P)
GATE="$(n2_plant "$N2_ROOT/nofill" no)"
expect_false "30n fixture: the copied library has no fill.sh" test -e "$N2_ROOT/nofill/scripts/lib/fill.sh"
expect_true "30n fixture: …and has its neighbours (units.sh)" test -e "$N2_ROOT/nofill/scripts/lib/units.sh"
REPO=$(make_repo r30n yes)
write_attestation "$REPO" "$SID_A"
k2_write_plan "$REPO" 4 "$K2_APPROVED_LINE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w30n" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_eq "30n a writer whose plan approval cannot be read (no lib/fill.sh) is refused" "deny" "$GATE_VERDICT"
expect_contains "30n …and the refusal says the approval reader could not be loaded" \
  "the approval reader lib/fill.sh cannot be loaded (reinstall the plugin)" "$GATE_ERR"
expect_contains "30n …naming the reader and the copy's library it looked in" "fill_plan_approved, from $N2_ROOT/nofill/" "$GATE_VERR"
expect_contains "30n …and the file" "/scripts/lib/fill.sh — not there" "$GATE_VERR"
expect_absent "30n …and it is no longer a not-checked line beside an admission" \
  "not checked: plan approval" "$GATE_VERR"
GATE="$(n2_plant "$N2_ROOT/withfill" yes)"
REPO=$(make_repo r30n2 yes)
write_attestation "$REPO" "$SID_A"
k2_write_plan "$REPO" 4 "$K2_APPROVED_LINE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w30n2" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_status "30n control: the same copy beside the whole library admits the approved writer" "0" "$GATE_ST"
expect_absent "30n control: …with no word of the reader" "cannot be loaded" "$GATE_ERR$GATE_VERR"
# A read-only role is not asked for an approval, so a missing reader refuses it nothing.
GATE="$N2_ROOT/nofill/hooks/dispatch-preflight.sh"
REPO=$(make_repo r30n3 yes)
write_attestation "$REPO" "$SID_A"
k2_write_plan "$REPO" 4 ""
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w30n3" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:researcher")"
expect_status "30n a read-only role through the copy with no fill.sh still passes" "0" "$GATE_ST"
GATE="$N2_SAVED_GATE"; rm -rf "$N2_ROOT"

# --- 30d: an approved-by whose value is empty records no approval ---
REPO=$(make_repo r30d yes)
write_attestation "$REPO" "$SID_A"
k2_write_plan "$REPO" 4 "approved-by:"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w30d" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_eq "30d an empty approved-by: value is not an approval" "deny" "$GATE_VERDICT"

# --- 30e: the reading roles pass through the same refused plan ---
# The reviewer is not here: the role is retired (wave-30 T20, AC-1.6); Explore reads in its place.
for _role in bionic:researcher bionic:test-runner bionic:auditor bionic:critic Explore; do
  REPO=$(make_repo "r30e-${_role##*:}" yes)
  write_attestation "$REPO" "$SID_A"
  k2_write_plan "$REPO" 4 ""
  # A double critic is dealt two questions, so it names two records (wave-27 T49's rule).
  _e30=""; [ "$_role" = bionic:critic ] && _e30="
Files: .bionic/docs/record/w99-widget.txt, .bionic/docs/record/w99-adv.md"
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL$(k2_questions "$_role" double)$_e30" "w30e" "claude-sonnet-5" \
                               "$S5_LIVE_TRANSCRIPT" "$_role")"
  # REBUILT (wave-27 T31; A-orch-43): a deny exits 0 too, so the exit said nothing. The verdict
  # and the row the wall recorded do.
  expect_eq "30e a ${_role} dispatch against the SAME unapproved plan is admitted" "allow" "$GATE_VERDICT"
  expect_eq "30e2 …and the wall recorded its launch row, as that role" "intended ${_role}" \
    "$(_r=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1); printf '%s %s' "$(roster_field "$_r" status)" "$(roster_field "$_r" subagent_type)")"
done

# --- 30f: below Step 4 the arm BINDS too (wave-20 T7, AC-9.1) ---
# It used to be inert here ("the plan is still being authored"). Flipped by design: before
# Step-3 approval only the read-only set dispatches, and a writer at Step 3 builds against a
# plan nobody has approved exactly as one at Step 4 does. §role-class drives current: 2.
REPO=$(make_repo r30f yes)
write_attestation "$REPO" "$SID_A"
k2_write_plan "$REPO" 3 ""
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w30f" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_eq "30f current: 3 with no approved-by — a writer is refused" "deny" "$GATE_VERDICT"

# --- 30g: the durable half — the approval still binds after Step 4 ---
REPO=$(make_repo r30g yes)
write_attestation "$REPO" "$SID_A"
k2_write_plan "$REPO" 6 ""
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w30g" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_eq "30g current: 6 with no approved-by — still refused" "deny" "$GATE_VERDICT"

# --- 30h: no plan on disk at all — a plan-bound arm with nothing to measure ---
REPO=$(make_repo r30h no)
mkdir -p "$REPO/.bionic/tmp"
printf 'patrol-stamp/v1|at=%s|session=%s|verb=arm\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SID_A" > "$REPO/.bionic/tmp/patrol-$SID_A.state"
: > "$REPO/.bionic/tmp/engaged-$SID_A.state"
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w30h" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_status "30h an engaged session with no plan on disk — the arm is inert" "0" "$GATE_ST"


# ===========================================================================

section "S31: the approval checkpoint binds at task scale too (epic-22 K2.5)"
# ===========================================================================
#
# K2.5 (Chris 2026-09-07 "Option 2"): a task-scale plan's `current: T<n>` reads as
# past Step 3 the same way the evidence gate's `k2_step_num` reads it — there is
# no "still being authored" state at task scale, so this arm binds on ANY
# `current: T<n>` (n >= 1), not only on numbered `current: 4`+. Mirrors S30
# exactly, on a `scale: task` plan instead of `scale: wave`.

# k2_write_task_plan <repo> <current T<n>> <approved-by line, or "">
k2_write_task_plan() {
  local repo="$1" cur="$2" approved="$3"
  local dir="$repo/.bionic/docs/plans/epic-99-test"
  mkdir -p "$dir"
  {
    printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n'
    printf -- 'intent: build\nrigor: single\nscale: task\n---\n\n'
    printf -- '# Test task-scale plan\n\n## Tasks\n\n'
    printf -- '| id | intent | rigor | description | status |\n|---|---|---|---|---|\n'
    printf -- '| %s | build | single | wire the K2.5 arms | active |\n\n' "$cur"
    printf -- '## SDLC State\n\nscale: task\ncurrent: %s\n' "$cur"
    [ -n "$approved" ] && printf -- '%s\n' "$approved"
    printf -- '\n- %s: bash tests/dispatch-preflight.test.sh green\n' "$cur"
  } > "$dir/task-99-test.plan.md"
  # BOUND TO THE TASK PLAN (wave-23-fixit-1810 T1): make_repo bound the session to its own
  # wave plan, which is approved; the checkpoint under test reads the plan this session is
  # bound to, never the root's newest.
  bound_marker "$repo" "$SID_A" "$dir/task-99-test.plan.md"
}

# --- 31a/31b: the two writer roles are refused while the line is absent ---
for _role in bionic:implementor bionic:senior-implementor; do
  _tag="31a"; [ "$_role" = "bionic:senior-implementor" ] && _tag="31b"
  REPO=$(make_repo "r${_tag}" yes)
  write_attestation "$REPO" "$SID_A"
  k2_write_task_plan "$REPO" T1 ""
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w${_tag}" "claude-sonnet-5" \
                               "$S5_LIVE_TRANSCRIPT" "$_role")"
  expect_eq "${_tag} a ${_role} dispatch at task-scale current: T1 with no approved-by is refused" "deny" "$GATE_VERDICT"
  expect_contains "${_tag} …and the refusal names the missing line" "approved-by" "$GATE_VERR"
done

# --- 31c: THE CONTROL — the same dispatch with the line present passes ---
REPO=$(make_repo r31c yes)
write_attestation "$REPO" "$SID_A"
k2_write_task_plan "$REPO" T1 "$K2_APPROVED_LINE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w31c" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_status "31c control: the same task-scale writer dispatch with approved-by present passes" "0" "$GATE_ST"
expect_absent "31c …with no refusal printed" "BLOCKED" "$GATE_ERR"

# --- 31d: an approved-by whose value is empty records no approval, at task scale ---
REPO=$(make_repo r31d yes)
write_attestation "$REPO" "$SID_A"
k2_write_task_plan "$REPO" T1 "approved-by:"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w31d" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_eq "31d an empty approved-by: value is not an approval, at task scale" "deny" "$GATE_VERDICT"

# --- 31e: the reading roles pass through the same refused task-scale plan ---
# THE AUDITOR AND THE REVIEWER ARE NOT HERE (wave-27 T15): this plan is `rigor: single`, which deals
# both of them no question, so the dispatch wall refuses them on their Questions: line (§Q Q5, Q8n)
# whatever the approval says. The critic carries all three.
for _role in bionic:researcher bionic:test-runner bionic:critic; do
  REPO=$(make_repo "r31e-${_role##*:}" yes)
  write_attestation "$REPO" "$SID_A"
  k2_write_task_plan "$REPO" T1 ""
  # A single critic is dealt three questions, so it names three records (wave-27 T49's rule).
  _e31=""; [ "$_role" = bionic:critic ] && _e31="
Files: .bionic/docs/record/w99-widget.txt, .bionic/docs/record/w99-adv.md, .bionic/docs/record/w99-str.md"
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL$(k2_questions "$_role" single)$_e31" "w31e" "claude-sonnet-5" \
                               "$S5_LIVE_TRANSCRIPT" "$_role")"
  # REBUILT (wave-27 T31; A-orch-43), as 30e: the verdict and the recorded row, not the exit.
  expect_eq "31e a ${_role} dispatch against the SAME unapproved task-scale plan is admitted" "allow" "$GATE_VERDICT"
  expect_eq "31e2 …and the wall recorded its launch row, as that role" "intended ${_role}" \
    "$(_r=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1); printf '%s %s' "$(roster_field "$_r" status)" "$(roster_field "$_r" subagent_type)")"
done

# --- 31f: any n >= 1 binds, not only T1 ---
REPO=$(make_repo r31f yes)
write_attestation "$REPO" "$SID_A"
k2_write_task_plan "$REPO" T3 ""
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w31f" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_eq "31f task-scale current: T3 with no approved-by is refused (any n >= 1, not just T1)" "deny" "$GATE_VERDICT"


# ============================================================================

section "§role-class — one read-only role set, delegation one level deep (wave-20 T7, REQ-9, D9, Δ12)"
# ============================================================================
#
# THE CLASS IS AN ALLOW-LIST NOW (AC-9.1). The approval checkpoint used to name the two
# writer roles and let every other `subagent_type` through, so a `fork`, a `general-purpose`
# or a `claude` agent — each of which can write the tree — was admitted on a plan nobody had
# approved (triage-B D2a, driven). The set that passes before approval is
# `role_is_readonly`'s (payload/scripts/lib/roster.sh): the four bionic read-only roles,
# plugin-qualified, plus the harness's `Explore` and `Plan`. Everything else is writer-class,
# the empty type (the harness's general-purpose default) and an unknown type included.
#
# BEFORE APPROVAL MEANS BEFORE APPROVAL, not "at Step 4 and later". The plan exists from
# Step 0, and a writer launched at Step 2 builds against a plan nobody has seen either; the
# spec's eval drives `current: 2`.
#
# DELEGATION IS ONE LEVEL DEEP (AC-9.2, AC-9.4; Δ12). A payload carrying a top-level
# `agent_id` comes from inside a subagent (t1-probe-report §3: main-thread payloads carry
# none). It may launch only a read-only role, and it writes NO roster row: the roster is the
# orchestrator's ledger. The channel variable is UNSET for every drive here — the old §S20
# proved the skip by setting `BIONIC_HOOK_CHANNEL` itself, a variable no production
# registration ever hands this hook (triage-B D2c).
unset BIONIC_HOOK_CHANNEL
expect_eq "rc0 the channel variable is unset for this section (the seam D2c named)" "unset" \
  "${BIONIC_HOOK_CHANNEL-unset}"
case "$GATE_ENV" in *BIONIC_HOOK_CHANNEL*) _rc_env=set ;; *) _rc_env=clean ;; esac
expect_eq "rc0 …and the gate's own environment list does not carry it either" "clean" "$_rc_env"

RC_NESTED_ID="a7nested-0123456789abcdef"
rc_nested() {  # <payload> -> the same payload as a subagent's hook sees it
  printf '%s' "$1" | jq -c --arg a "$RC_NESTED_ID" '. + {agent_id:$a}'
}

# --- rc1: before approval, every writer-class type is refused ---
_rc=0
for _role in fork general-purpose claude acme:helper "" researcher bionic:implementor; do
  _rc=$((_rc + 1))
  REPO=$(make_repo "rrc1-$_rc" yes)
  write_attestation "$REPO" "$SID_A"
  k2_write_plan "$REPO" 2 ""
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "wrc1-$_rc" "claude-sonnet-5" \
                               "$S5_LIVE_TRANSCRIPT" "$_role")"
  expect_eq "rc1 '${_role:-<empty>}' at current: 2 with no approved-by is refused" "deny" "$GATE_VERDICT"
  expect_contains "rc1 …by the approval checkpoint, in its own words" \
    "writers run against an APPROVED plan" "$GATE_VERR"
  expect_eq "rc1 …and journals nothing" "no" \
    "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo yes || echo no)"
done

# --- rc2: before approval, the read-only set dispatches ---
for _role in bionic:researcher bionic:test-runner bionic:auditor bionic:critic Explore Plan; do
  REPO=$(make_repo "rrc2-${_role##*:}" yes)
  write_attestation "$REPO" "$SID_A"
  k2_write_plan "$REPO" 2 ""
  _rc_brief="$BRIEF_FULL$(k2_questions "$_role" double)"
  # A double critic is dealt two questions, so it names two records (wave-27 T49's rule).
  [ "$_role" = bionic:critic ] && _rc_brief="$_rc_brief
Files: .bionic/docs/record/w99-widget.txt, .bionic/docs/record/w99-adv.md"
  # S33: an auditor brief may not waive Suites:, and BRIEF_FULL declares one — no change.
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$_rc_brief" "wrc2" "claude-sonnet-5" \
                               "$S5_LIVE_TRANSCRIPT" "$_role")"
  expect_status "rc2 '${_role}' at current: 2 with no approved-by is admitted" "0" "$GATE_ST"
  expect_eq "rc2 …on no deny verdict" "allow" "$GATE_VERDICT"
done
# …and the reviewer, a retired role (wave-30 T20, AC-1.6), is refused as retired at current: 2 as at any step.
REPO=$(make_repo "rrc2-reviewer" yes)
write_attestation "$REPO" "$SID_A"
k2_write_plan "$REPO" 2 ""
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL
Questions: structure" "wrc2" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" bionic:reviewer)"
expect_eq "rc2 'bionic:reviewer' at current: 2 is refused: the role is retired" "deny" "$GATE_VERDICT"
expect_contains "rc2 …saying so, and naming the role that holds structure" "bionic:reviewer is retired (1.14.0) (dispatch bionic:critic)" "$GATE_ERR"

# --- rc3: THE CONTROL — approval admits the writer at the same step ---
REPO=$(make_repo rrc3 yes)
write_attestation "$REPO" "$SID_A"
k2_write_plan "$REPO" 2 "$K2_APPROVED_LINE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "wrc3" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "general-purpose")"
expect_eq "rc3 control: general-purpose with approved-by present is admitted" "allow" "$GATE_VERDICT"

# --- rc4: a nested read-only launch is admitted and writes NO roster row (AC-9.2) ---
REPO=$(make_repo rrc4 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(rc_nested "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "wrc4" "claude-sonnet-5" \
                                          "$S5_LIVE_TRANSCRIPT" "bionic:researcher")")"
expect_eq "rc4 a subagent's bionic:researcher launch is admitted" "allow" "$GATE_VERDICT"
expect_eq "rc4 …and the orchestrator's roster gains no row (no roster file at all)" "no" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo yes || echo no)"

# rc4b: an existing roster is left byte-identical by a nested launch — the ledger a real
# wave holds is not appended to, not merely absent in a fresh repo.
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "wrc4-main" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:researcher")"
expect_eq "rc4b control: the same launch from the main thread journals exactly one row" "1" \
  "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"
RC4_BEFORE=$(cksum < "$(roster_path "$REPO" "$SID_A")")
run_gate "$(rc_nested "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "wrc4-sub" "claude-sonnet-5" \
                                          "$S5_LIVE_TRANSCRIPT" "Explore")")"
expect_eq "rc4b a nested Explore launch is admitted" "allow" "$GATE_VERDICT"
expect_eq "rc4b …and the roster is byte-identical after it" "$RC4_BEFORE" \
  "$(cksum < "$(roster_path "$REPO" "$SID_A")")"

# --- rc5: a nested writer-class launch is refused, on an APPROVED plan (AC-9.4) ---
_rc=0
for _role in fork general-purpose claude bionic:implementor bionic:senior-implementor ""; do
  _rc=$((_rc + 1))
  REPO=$(make_repo "rrc5-$_rc" yes)
  write_attestation "$REPO" "$SID_A"
  run_gate "$(rc_nested "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "wrc5-$_rc" "claude-sonnet-5" \
                                            "$S5_LIVE_TRANSCRIPT" "$_role")")"
  expect_eq "rc5 a subagent's '${_role:-<empty>}' launch is refused" "deny" "$GATE_VERDICT"
  expect_contains "rc5 …saying a subagent launches read-only roles only" \
    "a subagent may launch only read-only roles" "$GATE_ERR"
  expect_eq "rc5 …and journals nothing" "no" \
    "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo yes || echo no)"
done

# rc5b: THE MAIN-THREAD CONTROL — the same writer launch with no agent_id passes, so rc5 is
# the nesting and not the brief or the plan.
REPO=$(make_repo rrc5b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "wrc5b" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor")"
expect_eq "rc5b control: bionic:implementor from the main thread on an approved plan is admitted" \
  "allow" "$GATE_VERDICT"

# rc5c (T7b: was "a fork launched from an agent_type-only payload is refused"). The payload's
# `agent_type` ALONE is not an agent context: the harness sets it on a main session started
# with `claude --agent <x>` too ("present when the session uses --agent or the hook fires
# inside a subagent" — critic C4), and that session is the orchestrator. Only `agent_id`
# marks a subagent (A1's dependable spelling; T12 measured it on every nested payload).
REPO=$(make_repo rrc5c yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "wrc5c" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "fork" | jq -c '. + {agent_type:"bionic:implementor"}')"
expect_eq "rc5c (T7b: was refused) a fork launched from an agent_type-only payload is ADMITTED — it is the orchestrator" \
  "allow" "$GATE_VERDICT"

# --- rc7: a `claude --agent` MAIN SESSION dispatches writers and journals them (T7b; critic C4) ---
# agent_type present, agent_id absent: the orchestrator, launched through --agent. Its writer
# dispatch is admitted and rostered exactly as a plain main session's is (rc5b, S20's r20b).
REPO=$(make_repo rrc7 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "wrc7" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor" | jq -c '. + {agent_type:"my-orchestrator"}')"
expect_eq "rc7 an --agent main session's bionic:implementor dispatch is ADMITTED" "allow" "$GATE_VERDICT"
expect_absent "rc7 …the delegation arm says nothing" "a subagent may launch only read-only roles" "$GATE_ERR"
expect_eq "rc7 …and the roster journals exactly one row" "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"
expect_eq "rc7 …the row names the dispatch" "wrc7" \
  "$(roster_field "$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)" name)"
# rc7b: a --agent main session's read-only launch is journalled too — the skip is for nested
# launches, and this is not one.
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "wrc7b" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:researcher" | jq -c '. + {agent_type:"bionic:researcher"}')"
expect_eq "rc7b an --agent main session's bionic:researcher dispatch is admitted" "allow" "$GATE_VERDICT"
expect_eq "rc7b …and journalled: two rows now" "2" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# --- rc8: THE NESTED SHAPE AS T12 MEASURED IT — agent_id AND the caller's agent_type ---
# (live-rows-802ee6d.md §AC-9.2/9.4: `"agent_id":"a8b8…","agent_type":"general-purpose"`.)
# Today's refusal unchanged: the writer launch is refused, the read-only launch admitted,
# and neither journals a row.
REPO=$(make_repo rrc8 yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "wrc8" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "bionic:implementor" \
            | jq -c '. + {agent_id:"a8b824d95c81dd996", agent_type:"general-purpose"}')"
expect_eq "rc8 a nested (agent_id + agent_type) bionic:implementor launch is REFUSED" "deny" "$GATE_VERDICT"
expect_contains "rc8 …by the delegation arm" "a subagent may launch only read-only roles" "$GATE_ERR"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "wrc8b" "claude-sonnet-5" \
                             "$S5_LIVE_TRANSCRIPT" "Explore" \
            | jq -c '. + {agent_id:"a8b824d95c81dd996", agent_type:"general-purpose"}')"
expect_eq "rc8b a nested (agent_id + agent_type) Explore launch is admitted" "allow" "$GATE_VERDICT"
expect_eq "rc8b …and neither nested launch journals a row" "no" \
  "$([ -f "$(roster_path "$REPO" "$SID_A")" ] && echo yes || echo no)"

# --- rc6: the scaffold refusal says the wall reads the prompt only (AC-9.3) ---
# A brief FILE carrying the whole scaffold, and a prompt that only points at it: the lift
# reads `tool_input.prompt` and nothing else (triage-B D1, driven).
REPO=$(make_repo rrc6 yes)
write_attestation "$REPO" "$SID_A"
mkdir -p "$REPO/.bionic/docs/record/w99"
printf '%s\n' "$BRIEF_FULL" > "$REPO/.bionic/docs/record/w99/brief.md"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" \
  "Read the brief at .bionic/docs/record/w99/brief.md and do what it says." "wrc6")"
expect_eq "rc6 a prompt that only points at a brief file is refused" "deny" "$GATE_VERDICT"
expect_contains "rc6 …and the model's wire says the wall reads the prompt text only" \
  "reads the prompt text only" "$GATE_REASON"
expect_contains "rc6 …and says to copy the scaffold lines into the prompt" \
  "copy its scaffold lines into the prompt" "$GATE_REASON"

# rc6b: the single-fault no-deliverable refusal carries the same sentence in its detail.
RC6B_BRIEF=$(printf '%s\n' "$BRIEF_FULL" | /usr/bin/grep -v '^Expected artifact:')
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$RC6B_BRIEF" "wrc6b")"
expect_eq "rc6b a brief missing only its artifact line is refused" "deny" "$GATE_VERDICT"
expect_contains "rc6b …as naming no deliverable" "this brief names no deliverable" "$GATE_ERR"
expect_contains "rc6b …and its detail says the wall reads the prompt text only" \
  "reads the prompt text only" "$GATE_VERR"
expect_contains "rc6b …and to copy the scaffold lines into the prompt" \
  "copy its scaffold lines into the prompt" "$GATE_VERR"


# ============================================================================

section "§no-listagents — no brief, in any session state, is told to call ListAgents"

# READ OF THE DRIVER SWEEP INSTALLED IN run_gate. Every payload this file drives — every
# brief shape, every roster, every transcript state, allowed and refused, line and
# detail — has passed through that case statement by the time this runs. AC-4.1 is "any
# brief in any state", and this is the only assertion in the suite that can carry it.
expect_eq "no dispatch this suite drove asked for a ListAgents call" "" "${DP_NLA_HITS:-}"

# THE TWO ANTI-VACUITY ARMS. An empty counter proves nothing unless the sweep both RAN
# and DISCRIMINATES. The first says it ran over real traffic — a run_gate that never
# reached the case statement would leave this at zero. The second says the predicate
# still catches the retired string, so the row above is empty because no dispatch
# printed it, not because the test stopped looking.
expect_eq "…having swept every payload this suite drove (the sweep is not dead code)" \
  "yes" "$([ "${DP_NLA_SWEPT:-0}" -gt 100 ] && echo yes || echo "no: ${DP_NLA_SWEPT:-0}")"
DP_NLA_PROBE=""
case "bionic: dispatch refused — call ListAgents, then dispatch" in
  *"call ListAgents"*) DP_NLA_PROBE="caught" ;;
esac
expect_eq "…and the sweep's own predicate still catches that string when it is present" \
  "caught" "$DP_NLA_PROBE"

# ============================================================================


finish
