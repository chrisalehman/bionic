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

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
SKILL="${BIONIC_SKILLS_DIR}/canonical-sdlc/SKILL.md"
POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"

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

# expect_count_in_file <label> <needle> <expected-count> <file>
# Occurrence count, not line count — `grep -c` would collapse two hits on one line into
# one, which is exactly the reversion a count-scoped pin exists to catch.
expect_count_in_file() {
  local label="$1" needle="$2" want="$3" file="$4" got
  TOTAL=$((TOTAL + 1))
  got=$(grep -oF -- "$needle" "$file" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$got" = "$want" ]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (wanted ${want} occurrences of '$needle' in $file, got ${got})"
    FAIL=$((FAIL + 1))
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
expect_pin_in_file "liveness fields: absence with no deliverable is what reads as broken" \
  "is what the landing verdict reads as a broken contract" "$SKILL"
expect_pin_in_file "liveness fields: shape emerges from field presence, no restated label" \
  "shape emerges from which are present" "$SKILL"

echo ""
echo "=== Section 5h: the Watcher-arming duty is GONE (epic-16 w2 slice S1) ==="
# The duty said a long-shape dispatch is armed with a quiescence watcher at dispatch time.
# The watcher is deleted, so the duty is deleted with it — and its absence is pinned in the
# same file that used to pin its presence, because a doctrine paragraph nobody notices is
# missing is exactly how a deleted subsystem grows a second life in a brief.
expect_absent_in_file "the Watcher-arming heading is gone" "**Watcher-arming.**" "$SKILL"
expect_absent_in_file "…and so is the duty it carried" \
  "is armed with a quiescence watcher at dispatch time" "$SKILL"

echo ""
echo "=== Section 5i: the heartbeat doctrine (epic-17 W4 S6, spec AC-8 as amended) ==="
# ONE heartbeat replaces the old dispatch-conditional poker duty. What is pinned here is
# the OBLIGATION SPAN, never the paragraph's name: a rename leaves the duty intact, and a
# reworded arming trigger is the defect this suite exists to catch. The arming trigger is
# the sharpest literal in the doctrine — "at engagement, every session" and "when you
# dispatch something" are the two readings that diverge, and the wrong one leaves an
# orchestrator working alone with no pulse for the whole stretch (design-ledger D2, arming
# trigger CORRECTED by Chris 2026-08-18).
expect_pin_in_file "heartbeat: one clock per run" \
  "One clock per run, and only one." "$SKILL"
expect_pin_in_file "heartbeat: armed at ENGAGEMENT, every session of the run" \
  "the Step-0 confirmation of a new run, or the resume ritual of an open one, in every session of that run" "$SKILL"
expect_pin_in_file "heartbeat: arming is not dispatch-conditional" \
  "Arming is not conditional on having dispatched anything" "$SKILL"
expect_pin_in_file "heartbeat: the interval is the poker's" \
  "config knob \`poker-interval:\` in \`.bionic/config.yaml\`, default 30m" "$SKILL"
expect_pin_in_file "heartbeat: CronDelete at run close" \
  "\`CronDelete\` the job at run close." "$SKILL"
expect_pin_in_file "heartbeat: 7-day expiry is the backstop, not the disarm" \
  "the forgotten-disarm backstop, not the disarm" "$SKILL"
expect_pin_in_file "heartbeat: subagents stay timerless" \
  "a dispatched agent arms nothing" "$SKILL"
expect_pin_in_file "heartbeat: the manual /loop poke ritual is retired" \
  "The manual \`/loop\` poke ritual is retired" "$SKILL"

# The patrol prompt's four reads, then the continue.
expect_pin_in_file "patrol: idempotent by construction" \
  "idempotent by construction" "$SKILL"
expect_pin_in_file "patrol: the poker is the decision brain" \
  "is the decision brain — the prompt gathers, the poker decides" "$SKILL"
expect_pin_in_file "patrol: liveness reads the contracted cadence, not the tick interval" \
  "quieter than the \`cadence\` its own brief declared" "$SKILL"
expect_pin_in_file "patrol: continue toward the goal until a wall" \
  "Then continue toward the goal until a wall." "$SKILL"

# The tool-grounded duty clauses, transcribed VERBATIM from spec AC-8 (as amended
# 2026-08-18) rather than paraphrased — normative values ship as verbatim text, because two
# implementers once resolved the same paraphrased span in opposite directions.
#
# PIN MOVED 2026-08-18 (W4 rfold2, review F-7). The span used to be one 112-word run-on
# bullet and was pinned as one 771-byte fixed string. F-7 broke it into a bold lead-in plus
# three sub-bullets for scanability, and a fixed-string grep cannot span the newlines that
# split introduced. So the whole-string pin becomes one pin per CLAUSE, covering the same
# normative text with nothing dropped: a "clarifying" reword of any clause still fails here,
# and each failure now names which clause moved instead of one opaque byte-count.
expect_pin_in_file "patrol: the duties are tool-grounded, not judgment-worded" \
  "Both duties are TOOL-GROUNDED, never judgment-worded" "$SKILL"
expect_pin_in_file "patrol: panel refresh is ListAgents then a fact-discharged TaskStop" \
  "= ListAgents, then TaskStop on each listed lineage whose ledger row is fact-discharged (CLOSED / MET / acked)" \
  "$SKILL"
expect_pin_in_file "patrol: a listed agent with no ledger row is a duplicate-session tell" \
  "A listed agent with NO ledger row is surfaced as a duplicate-session tell, never silently stopped" \
  "$SKILL"
expect_pin_in_file "patrol: task-list refresh is TaskList then mechanical chronological order" \
  "= TaskList, then chronological display order (current-step slice entries first, dependency order, later-step entries after) restored mechanically" \
  "$SKILL"
expect_pin_in_file "patrol: the reorder mechanics, TaskCreate/TaskUpdate and the no-op case" \
  "TaskCreate fresh copies of every entry that must sort later, TaskUpdate status=deleted on the stale originals, no-op when ascending-ID order already matches" \
  "$SKILL"
expect_pin_in_file "patrol: statuses reconciled with verified reality" \
  "then statuses reconciled with verified reality" "$SKILL"
# Named separately so a truncation of the chain's tail reports as the fallback going missing
# rather than as one clause among six failing.
expect_pin_in_file "patrol: the version-gated fallback names the plan ledger" \
  "where the task tools are absent (version-gated), the plan ledger stands in as the task list" "$SKILL"

echo ""
echo "=== Section 5j: the retired poker duty, and the re-rooted invocation paths ==="
# The old duty armed the wake ON DISPATCH. Its absence is pinned in the same file that
# pinned its presence: a doctrine paragraph nobody notices is missing is how a superseded
# rule grows a second life in a brief (same reasoning as §5h's watcher).
expect_absent_in_file "the old poker-duty heading is gone" "**The poker duty.**" "$SKILL"
expect_absent_in_file "…and so is its dispatch-conditional arming rule" \
  "Dispatching a long-shape unit arms a session-scoped self-wake" "$SKILL"

# C-10: the two operator commands were the last installed-path literals in the skill. They
# are COUNT-scoped, not merely present — `interval` and `tick` are two invocations of the
# same script, and `standdown` and `order` two of the other, so a spelling that survives on
# one line while the other reverts would pass a bare presence check.
expect_absent_in_file "no installed-path poker literal survives" \
  "bash ~/.claude/hooks/session-poker.sh" "$SKILL"
expect_absent_in_file "no installed-path stop-orders literal survives" \
  "bash ~/.claude/hooks/stop-orders.sh" "$SKILL"

# The spelling is plugin-rooted WITH the payload's established fallback (F-1, 2026-08-18).
# A bare `${CLAUDE_PLUGIN_ROOT}` is only expanded by the CLI at command-registration time; in
# a model's own Bash shell the variable is unset, so the bare form expands to `/hooks/...`
# and exits 127 — and these four are commands a model runs by hand, the patrol prompt's
# first duty among them. The fallback keeps C-10's plugin-rooted intent and makes the command
# resolve wherever a shell rather than the CLI does the expanding.
expect_count_in_file "exactly 2 fallback-rooted session-poker invocations (interval, tick)" \
  'bash ${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/hooks/session-poker.sh' 2 "$SKILL"
expect_count_in_file "exactly 2 fallback-rooted stop-orders invocations (standdown, order)" \
  'bash ${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/hooks/stop-orders.sh' 2 "$SKILL"
# The bare form is what the fallback replaced: pinning its absence on these two scripts is
# what makes a silent revert of any one site red rather than merely uncounted.
expect_count_in_file "no bare-plugin-root poker invocation survives" \
  'bash ${CLAUDE_PLUGIN_ROOT}/hooks/session-poker.sh' 0 "$SKILL"
expect_count_in_file "no bare-plugin-root stop-orders invocation survives" \
  'bash ${CLAUDE_PLUGIN_ROOT}/hooks/stop-orders.sh' 0 "$SKILL"
expect_count_in_file "zero installed-hooks-directory literals anywhere in the skill" \
  '~/.claude/hooks/' 0 "$SKILL"

echo ""
echo "=== Section 5k: heartbeat doctrine agrees across BOTH its rendering surfaces ==="
# Ownership row 4 gives heartbeat doctrine two owners: SKILL.md §Dispatch and this script's
# own header prose. §5i/§5j read SKILL.md only, so they are presence pins on one owner, not
# an agreement test for the pair — and the pair silently diverged for a whole wave (the
# header kept documenting the retired self-wake loop and the `~/.claude` spelling long after
# the doctrine replaced both). These arms read BOTH files for the same literals, so a rewrite
# of either surface alone goes red.
for _surface in "$SKILL" "$POKER"; do
  _which="$(basename "$_surface")"
  expect_pin_in_file "agreement/${_which}: one clock per run" \
    "One clock per run, and only one." "$_surface"
  expect_pin_in_file "agreement/${_which}: armed at engagement, not on dispatch" \
    "Arm it at engagement" "$_surface"
  expect_pin_in_file "agreement/${_which}: disarmed by CronDelete at run close" \
    '`CronDelete` the job at run close' "$_surface"
  expect_pin_in_file "agreement/${_which}: the tick command, in the runnable spelling" \
    'bash ${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/hooks/session-poker.sh tick' "$_surface"
done
unset _surface _which

# The retired mechanism must not survive as a live claim on either surface. The header may
# NAME the self-wake loop in its supersession note — what it may not do is spell the tick
# command the old way, which is the form an operator would actually paste.
expect_absent_in_file "poker header carries no installed-path invocation" \
  "bash ~/.claude/hooks/session-poker.sh" "$POKER"
expect_absent_in_file "poker header no longer calls its caller the self-wake loop" \
  "the doctrine's self-wake loop" "$POKER"
# Count-scoped so a second, contradicting copy of the arming rule cannot be added to either
# surface without this going red (same reasoning as close-out.test.sh §5).
expect_count_in_file "the arming rule has exactly one copy in the skill" \
  "One clock per run, and only one." 1 "$SKILL"
expect_count_in_file "…and exactly one in the poker header" \
  "One clock per run, and only one." 1 "$POKER"

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
