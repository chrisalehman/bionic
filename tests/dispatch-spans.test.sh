#!/bin/bash
# Pin suite for the three normative dispatch-resilience spans in
# skills/canonical-sdlc/SKILL.md §Dispatch (epic-15 wave-01R slice 4/4):
# the starting standard, the stopping standard, and the non-response
# procedure — plus the single pointer line to the governing design.
#
# Source of the pinned literals: design/orchestrator-subagent-coordination.md
# (v4 RATIFIED) §3.3 "Non-response procedure" entity row, §3.4 Starting/
# Stopping, §5 D-1/D-2, and the 08-04 register rows (both-classes
# examine-before-acting; spans-only, no restatement).
#
# This suite is written BEFORE the SKILL.md amendment lands, so it is
# expected to FAIL now (RED evidence) and turn GREEN once the spans are
# written.
#
# Usage: bash tests/dispatch-spans.test.sh

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="${REPO}/skills/canonical-sdlc/SKILL.md"

PASS=0
FAIL=0
TOTAL=0

# expect_pin_in_file <label> <needle> <file>
# Fixed-string (grep -F) presence check. Names the missing string and file on
# failure so a RED run is self-explanatory.
expect_pin_in_file() {
  local label="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$file" 2>/dev/null; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (missing '$needle' in $file)"
    FAIL=$((FAIL + 1))
  fi
}

expect_absent_in_file() {
  local label="$1" needle="$2" file="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "$needle" "$file" 2>/dev/null; then
    echo "FAIL: $label (should be gone, still found '$needle' in $file)"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: $label"
    PASS=$((PASS + 1))
  fi
}

echo ""
echo "=== Section 1: §Dispatch exists ==="
expect_pin_in_file "SKILL.md carries a Dispatch section" "## Dispatch" "$SKILL"

echo ""
echo "=== Section 2: The starting standard (attestation / contract / ledger) ==="
expect_pin_in_file "starting standard heading" "The starting standard." "$SKILL"
expect_pin_in_file "starting standard: attestation before dispatch" "environment attestation from this session is present" "$SKILL"
expect_pin_in_file "starting standard: work contract at launch" "a work contract exists at launch, naming the task and a durable deliverable path" "$SKILL"
expect_pin_in_file "starting standard: ledger at dispatch" "the launch is ledgered the moment it happens" "$SKILL"

echo ""
echo "=== Section 3: The stopping standard (observation / D-1 / D-2 / never-idle) ==="
expect_pin_in_file "stopping standard heading" "The stopping standard." "$SKILL"
expect_pin_in_file "stopping standard: observation before stop" "may be stopped only when a fresh observation of that target has been recorded first" "$SKILL"
expect_pin_in_file "stopping standard: D-1 freshness rule cited" "Freshness is the activity boundary, not a clock (D-1)" "$SKILL"
expect_pin_in_file "stopping standard: D-1 stale-by-definition path" "anything written since is stale by definition" "$SKILL"
expect_pin_in_file "stopping standard: D-1 dormant-however-old path" "dormancy since the observation is valid however old" "$SKILL"
expect_pin_in_file "stopping standard: D-2 one-observation-one-stop" "One observation discharges exactly one stop (D-2)" "$SKILL"
# The ownership table's third row (spec.md:120) names this rendering surface as
# the SKILL.md half of the progress-observation pair, and it did not exist: the
# field was declared at dispatch, hooks/stop-check.sh supported the flag, and no
# normative text connected the two — so an orchestrator following the stopping
# standard literally took exactly the observation that was insufficient before
# this wave (Step-6 critic, issue C).
expect_pin_in_file "stopping standard: a contracted progress path is named in the observation" \
  "the observation of that target names that path" "$SKILL"
expect_pin_in_file "stopping standard: the D-6 channel is what it names" \
  "the D-6 channel" "$SKILL"
expect_pin_in_file "stopping standard: never on idle notification" "Never on an idle notification" "$SKILL"
expect_pin_in_file "stopping standard: never on elapsed silence" "never on elapsed silence alone" "$SKILL"

echo ""
echo "=== Section 4: The non-response procedure (both classes / bounded rounds / reporting) ==="
expect_pin_in_file "non-response procedure heading" "The non-response procedure." "$SKILL"
expect_pin_in_file "non-response: examine-first for both classes" "examine its evidence first — for BOTH agent classes, before any other action" "$SKILL"
expect_pin_in_file "non-response: readers path (one follow-up, relaunch fresh)" "read-only agents may be messaged once and relaunched fresh" "$SKILL"
expect_pin_in_file "non-response: writers path (never resumed, take over)" "writing agents are never resumed — examine their output directly, take over the work, and stand the agent down" "$SKILL"
expect_pin_in_file "non-response: bounded two rounds" "Bounded to two rounds" "$SKILL"
expect_pin_in_file "non-response: outcome — delivered" "work delivered" "$SKILL"
expect_pin_in_file "non-response: outcome — taken over" "work taken over" "$SKILL"
expect_pin_in_file "non-response: outcome — stopped-and-reported" "agent stopped-and-reported" "$SKILL"
expect_pin_in_file "non-response: every stop reported" "Every stop is reported to the user, never absorbed silently" "$SKILL"

echo ""
echo "=== Section 4b: verification means the artifact, not the report (R1) ==="
# The pre-wave paragraph this diff replaced carried a standing rule the three
# ratified spans do not recover: "verify the named artifact exists before
# believing the report" (Step-6 readability review R1). Recovered as one clause
# in the ledger paragraph, which is the smallest form that does not reopen the
# ratified spans-only decision. (Wave 2 has since landed the full reporting
# contract — §5b below pins it — so this clause is no longer the only rendering;
# it stays because the ledger paragraph is where the verify-before-believing
# duty attaches to the dispatch row.)
expect_pin_in_file "ledger paragraph: verify the artifact, not the report" \
  "verify that the named artifact exists before believing the report" "$SKILL"

echo ""
echo "=== Section 5: One pointer line to the governing design, no restatement ==="
expect_pin_in_file "pointer line names the design doc path" "design/orchestrator-subagent-coordination.md" "$SKILL"

echo ""
echo "=== Section 5b: The reporting contract (§Dispatch rendering, epic-15 w2 slice 4/2) ==="
expect_pin_in_file "reporting contract: heading" "**The reporting contract.**" "$SKILL"
expect_pin_in_file "reporting contract: core sentence" \
  "carries the command that proves it and that command's output, or the explicit label" "$SKILL"
expect_pin_in_file "reporting contract: unverified obligation" \
  "An \`unverified\` claim obligates the orchestrator to re-check before acting" "$SKILL"
expect_pin_in_file "reporting contract: no-proof-no-label is a violation" \
  "a claim with neither proof nor label is a contract violation" "$SKILL"

echo ""
echo "=== Section 5c: Auditor mandate — reporting-contract duty (epic-15 w2 slice 4/2) ==="
expect_pin_in_file "auditor mandate: reporting-contract duty addition" \
  "Hold every report to the reporting contract: a factual claim carrying neither its proving command with output nor the label \"unverified\" is itself a finding." "$SKILL"

echo ""
echo "=== Section 5d: Contract fields + overdue-as-trigger span (epic-15 w2 slice 4/3) ==="
expect_pin_in_file "contract-fields sentence: the count matches the enumeration" \
  "carries the seven things the role file cannot know" "$SKILL"
expect_pin_in_file "contract-fields sentence: expected duration is one of them" \
  "exit condition, an expected duration, and" "$SKILL"
expect_pin_in_file "contract-fields sentence: progress-artifact path for D-6" \
  "a progress-artifact path the task appends to as it" "$SKILL"
# The sentence is the SSoT for the brief contract, and it counted five while
# enumerating seven — "only" made the two added fields read as elaboration on the
# five rather than as fields of their own (Step-6 critic, issue D).
expect_absent_in_file "the falsified 'only the five things' count is gone" \
  "only the five things" "$SKILL"
expect_pin_in_file "overdue span: heading" \
  "Overdue is a trigger, never evidence:" "$SKILL"
expect_pin_in_file "overdue span: routes mechanically" \
  "routes into this procedure mechanically" "$SKILL"
expect_pin_in_file "overdue span: never justifies a stop by itself" \
  "never justifies a stop by itself" "$SKILL"
expect_pin_in_file "overdue span: eventual stop still needs fresh observation" \
  "the eventual stop still requires its own fresh observation" "$SKILL"

echo ""
echo "=== Section 5e: Roster as SSoT (epic-15 w3 slice 4/7) ==="
# Design ownership table: "the roster is SSoT for 'who is ours' — the plan's
# dispatch ledger is a rendering of it." Extends the existing "Ledger the
# dispatch" span rather than contradicting it.
expect_pin_in_file "roster: authoritative launch record" \
  "is the authoritative launch record" "$SKILL"
expect_pin_in_file "roster: plan ledger renders it, not the reverse" \
  "the plan's dispatch ledger renders it, not the reverse" "$SKILL"

echo ""
echo "=== Section 5f: Same-actor + foreign-stop rules (epic-15 w3 slice 4/7) ==="
# spec AC-4 (D-3, same-actor) and AC-6 (D-3/R-F, foreign-stop) — rendered as
# one sentence each inside the stopping standard, per hooks/stop-guard.sh's
# shipped same-actor and foreign-stop checks (slice 4/6).
expect_pin_in_file "same-actor rule: the discharging observation is the stopper's own" \
  "The observation that discharges a stop is the stopper's own" "$SKILL"
expect_pin_in_file "foreign-stop rule: not-launched is not stoppable by name" \
  "What this session did not launch, it does not stop by name" "$SKILL"
expect_pin_in_file "foreign-stop rule: full agent id is the deliberate path" \
  "the full agent id is the deliberate path" "$SKILL"

echo ""
echo "=== Section 5g: Liveness fields, ratified simpler form (epic-15 w3 slice 4/7) ==="
# Liveness contract (plan Assumptions, user-RATIFIED 2026-08-05): cadence rides
# with the progress path; a subprocess claim is CONDITIONAL-REQUIRED; shape
# emerges from field presence rather than a restated label (the F-1 class).
expect_pin_in_file "liveness fields: heading" "**Liveness fields.**" "$SKILL"
expect_pin_in_file "liveness fields: cadence rides with the progress path" \
  "carries a \`cadence\` alongside it" "$SKILL"
expect_pin_in_file "liveness fields: extends the 15-minute rule by one number" \
  "extending the 15-minute rule by one number" "$SKILL"
expect_pin_in_file "liveness fields: too-quiet is relative to the author's own declaration" \
  "quieter than the author's own declaration" "$SKILL"
expect_pin_in_file "liveness fields: subprocess claim is conditional-required" \
  "is conditional-required: declared only when the task backgrounds a long-running command" "$SKILL"
expect_pin_in_file "liveness fields: quiescence irrelevant while the claimed process exists" \
  "quiescence is irrelevant" "$SKILL"
expect_pin_in_file "liveness fields: absence with no deliverable wakes immediately" \
  "wakes the watcher immediately" "$SKILL"
expect_pin_in_file "liveness fields: shape emerges from field presence, no restated label" \
  "shape emerges from which are present" "$SKILL"

echo ""
echo "=== Section 5h: Watcher-arming, P1 (epic-15 w3 slice 4/7) ==="
expect_pin_in_file "watcher-arming: heading" "**Watcher-arming.**" "$SKILL"
expect_pin_in_file "watcher-arming: long-shape declarations are armed at dispatch time" \
  "is armed with a quiescence watcher at dispatch time" "$SKILL"

echo ""
echo "=== Section 6: superseded generic non-response text is gone ==="
# Pre-wave text handled a "wedged agent" uniformly (kill-and-redispatch) with
# no reader/writer distinction — exactly what the ratified non-response
# procedure supersedes (writers are never resumed, let alone killed and
# blindly redispatched). Its presence after the amendment would mean the
# span replaced nothing and the section now contradicts itself.
expect_absent_in_file "old undifferentiated kill-and-redispatch text removed" "a genuinely wedged agent is killed and re-dispatched" "$SKILL"

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
