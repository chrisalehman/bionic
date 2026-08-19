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
echo "=== Section 5i: the Patrol doctrine (epic-17 W4 S6 / W5 4/4, spec AC-8, AC-4..AC-6) ==="
# ONE Patrol replaces the old dispatch-conditional poker duty. What is pinned here is
# the OBLIGATION SPAN, never the paragraph's name: a rename leaves the duty intact, and a
# reworded arming trigger is the defect this suite exists to catch. The arming trigger is
# the sharpest literal in the doctrine — "at engagement, every session" and "when you
# dispatch something" are the two readings that diverge, and the wrong one leaves an
# orchestrator working alone with no pulse for the whole stretch (design-ledger D2, arming
# trigger CORRECTED by Chris 2026-08-18).
expect_pin_in_file "patrol-doctrine: one clock per run" \
  "One clock per run, and only one." "$SKILL"
expect_pin_in_file "patrol-doctrine: armed at ENGAGEMENT, every session of the run" \
  "the Step-0 confirmation of a new run, or the resume ritual of an open one, in every session of that run" "$SKILL"
expect_pin_in_file "patrol-doctrine: arming is not dispatch-conditional" \
  "Arming is not conditional on having dispatched anything" "$SKILL"
expect_pin_in_file "patrol-doctrine: the interval is the poker's" \
  "config knob \`poker-interval:\` in \`.bionic/config.yaml\`, default 30m" "$SKILL"
expect_pin_in_file "patrol-doctrine: CronDelete at run close" \
  "\`CronDelete\` the job at run close." "$SKILL"
expect_pin_in_file "patrol-doctrine: 7-day expiry is the backstop, not the disarm" \
  "the forgotten-disarm backstop, not the disarm" "$SKILL"
expect_pin_in_file "patrol-doctrine: subagents stay timerless" \
  "a dispatched agent arms nothing" "$SKILL"
expect_pin_in_file "patrol-doctrine: the manual /loop poke ritual is retired" \
  "The manual \`/loop\` poke ritual is retired" "$SKILL"

# --- W5 4/4 (AC-4): the doctrine's SUBJECT is the Patrol, and the retired names are gone.
# Vocabulary is not decoration here: the arming wall, the stamp and the cron job are three
# mechanisms with one name between them, and a session reading "heartbeat" in one paragraph
# and "the Patrol" in the next has to work out whether they are the same thing.
expect_pin_in_file "vocabulary: the doctrine paragraph is named for the Patrol" \
  "**The Patrol.**" "$SKILL"
expect_count_in_file "vocabulary: no heartbeat survives anywhere in the skill" \
  "heartbeat" 0 "$SKILL"
expect_count_in_file "vocabulary: nor the session-cron spelling it travelled with" \
  "session cron" 0 "$SKILL"

# --- W5 4/4 (AC-6): the arming wall, and the stamp ordering that makes it honest.
expect_pin_in_file "arming wall: arm is not bookkeeping" \
  "**The arming wall.**" "$SKILL"
expect_pin_in_file "arming wall: the stamp is written BEFORE the poker decides" \
  "stamps a session-keyed file beside the roster before the poker decides anything" "$SKILL"
expect_pin_in_file "arming wall: both refusal states, absent and stale" \
  "absent (never armed) or older than twice the poker-interval" "$SKILL"
expect_pin_in_file "arming wall: the arm command is named where arming is instructed" \
  "session-poker.sh arm\`" "$SKILL"
expect_pin_in_file "arming wall: the honest limit is stated, not implied" \
  "it cannot see the CLI's cron table" "$SKILL"

# --- W5 4/4 (AC-5): the plugin root is resolved, once, and never guessed.
expect_pin_in_file "plugin root: resolved once per session, at arming" \
  "resolve the root ONCE per session, at Patrol arming" "$SKILL"
expect_pin_in_file "plugin root: the resolved ABSOLUTE path is what gets baked into session text" \
  "bake the resulting ABSOLUTE path into everything the session writes afterwards" "$SKILL"
expect_pin_in_file "plugin root: the named fix on failure, verbatim" \
  "claude plugin install bionic@bionic" "$SKILL"
expect_pin_in_file "plugin root: and no other root is substituted for a failed resolution" \
  "no other root is substituted for it" "$SKILL"

# THE IDIOM IS THE LIBRARY'S, NOT A SECOND READING OF THE REGISTRY. The doctrine has to
# carry a runnable seed — resolving the plugin root is precisely the thing you cannot do
# from inside the plugin, so `detect_plugin_root` cannot be sourced before it has answered.
# What that must never become is a SECOND parse of a CLI-internal schema, drifting from the
# one every payload script calls. So the jq program is read OUT of detect.sh here and
# demanded verbatim in the skill: change the function and this goes red until the doctrine
# follows.
DETECT_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/detect.sh"
if [ -f "$DETECT_LIB" ]; then
  _jq_prog="$(sed -n "s/^DETECT_PLUGIN_ROOT_JQ='\(.*\)'\$/\1/p" "$DETECT_LIB" | head -1)"
  if [ -n "$_jq_prog" ]; then
    expect_pin_in_file "plugin root: the doctrine's seed IS detect_plugin_root's jq program" \
      "$_jq_prog" "$SKILL"
  else
    no "plugin root: DETECT_PLUGIN_ROOT_JQ could not be read out of detect.sh"
  fi
  expect_pin_in_file "plugin root: …and the doctrine names the function the seed agrees with" \
    "detect_plugin_root" "$SKILL"
else
  no "plugin root: detect.sh not found at $DETECT_LIB"
fi
unset _jq_prog

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

# THE SPELLING IS A PLACEHOLDER NOW (W5 4/4, AC-5), and the reason is the fallback's own
# failure. `${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}` was chosen in W4 because a bare
# `${CLAUDE_PLUGIN_ROOT}` is unset in a model's own shell and exits 127 — but the fallback
# ALWAYS resolves, and what it resolves to is a bootstrap-era `~/.claude` copy that can be an
# older build than the plugin the CLI loads. A wrong-version hook that runs beats a missing
# one at nothing: it enforces a doctrine nobody is following, silently. `<plugin-root>` cannot
# be pasted by accident, and the doctrine above says where the real path comes from.
#
# COUNT-SCOPED, as before: `interval`/`arm`/`tick` are three invocations of one script and
# `standdown`/`order` two of the other, so a spelling that survives on one line while another
# reverts would pass a bare presence check.
expect_count_in_file "exactly 3 placeholder-rooted session-poker invocations (interval, arm, tick)" \
  'bash <plugin-root>/hooks/session-poker.sh' 3 "$SKILL"
expect_count_in_file "exactly 2 placeholder-rooted stop-orders invocations (standdown, order)" \
  'bash <plugin-root>/hooks/stop-orders.sh' 2 "$SKILL"
# Both retired forms are pinned absent AS INVOCATIONS. The doctrine still NAMES the fallback
# spelling once, in the sentence explaining why it is retired — a supersession note is not a
# command, and deleting the explanation would leave the next author to rediscover the trap.
expect_count_in_file "no fallback-rooted poker invocation survives" \
  'bash ${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/hooks/session-poker.sh' 0 "$SKILL"
expect_count_in_file "no fallback-rooted stop-orders invocation survives" \
  'bash ${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/hooks/stop-orders.sh' 0 "$SKILL"
expect_count_in_file "no bare-plugin-root poker invocation survives" \
  'bash ${CLAUDE_PLUGIN_ROOT}/hooks/session-poker.sh' 0 "$SKILL"
expect_count_in_file "no bare-plugin-root stop-orders invocation survives" \
  'bash ${CLAUDE_PLUGIN_ROOT}/hooks/stop-orders.sh' 0 "$SKILL"
expect_count_in_file "zero installed-hooks-directory literals anywhere in the skill" \
  '~/.claude/hooks/' 0 "$SKILL"

echo ""
echo "=== Section 5k: Patrol doctrine agrees across BOTH its rendering surfaces ==="
# Ownership row 4 gives Patrol doctrine two owners: SKILL.md §Dispatch and this script's
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
  expect_pin_in_file "agreement/${_which}: the tick command, in the placeholder spelling" \
    'bash <plugin-root>/hooks/session-poker.sh tick' "$_surface"
  # THE WAKEUP BAN JOINS THE PAIR (W5 4/4, closing 4/1's A10). It is clock doctrine of
  # exactly the class this pair exists to hold — how a run schedules a wake — and it landed
  # in SKILL.md alone, which is the asymmetry that let the header document a retired
  # mechanism for a whole wave. Both halves are pinned: the rule and the mechanism that
  # makes it true, because the rule without the reason reads as arbitrary and gets "fixed".
  expect_pin_in_file "agreement/${_which}: wakeups are recurring, never date-pinned" \
    "Wakeups are recurring, never date-pinned" "$_surface"
  expect_pin_in_file "agreement/${_which}: …because a busy minute drops a one-shot" \
    "a busy minute DROPS the tick rather than queuing it" "$_surface"
  # The Patrol name, on both surfaces, so the rename cannot half-land (AC-4).
  expect_absent_in_file "agreement/${_which}: no heartbeat vocabulary survives" \
    "heartbeat" "$_surface"
  expect_absent_in_file "agreement/${_which}: no retired fallback invocation survives" \
    'bash ${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/hooks/session-poker.sh' "$_surface"
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
echo "=== Section 5l: the completion-signal doctrine (epic-17 W5 slice 4/1, spec AC-1) ==="
# Root cause, measured across W4: a finished subagent wrote its report as plain final TEXT,
# which routes nowhere — the orchestrator saw an idle notification and an empty mailbox, and
# two read-only deliveries (auditor, critic) were reconstructed out of transcripts after the
# fact. The fix is a delivery CHANNEL stated in the doctrine and carried by every role file:
# the report is handed over by the SendMessage tool. What is pinned here is the obligation,
# not the paragraph name — and the broken form is pinned by its own arm, because "your final
# message is the report" is the phrasing several W4 briefs actually shipped.
expect_pin_in_file "completion signal: the final act is a SendMessage naming the artifacts" \
  "A writer's final act is a \`SendMessage\` naming the artifact path(s) it produced" "$SKILL"
expect_pin_in_file "completion signal: plain final text is discarded" \
  "plain final text is discarded" "$SKILL"
expect_pin_in_file "completion signal: the broken brief form is named and banned" \
  "a brief that contracts for the report as a final message is contracting for a report that never arrives" \
  "$SKILL"
expect_pin_in_file "completion signal: idle is still not a completion signal" \
  "only the sent message closes the phase" "$SKILL"

# The safety net keeps its rank. This arm exists because the recovery recipe below is the
# kind of text that quietly gets promoted to "the proof" on a rewrite.
expect_pin_in_file "transcript recovery: heading" \
  "**When a report is lost anyway.**" "$SKILL"
expect_pin_in_file "transcript recovery: artifacts/ledger/progress stay the primary proof" \
  "are the safety net and remain the primary proof" "$SKILL"
expect_pin_in_file "transcript recovery: the message is the latency channel, not the evidence" \
  "the message is the latency channel, not the evidence" "$SKILL"
expect_pin_in_file "transcript recovery: the transcript path" \
  "subagents/agent-*.jsonl" "$SKILL"
expect_pin_in_file "transcript recovery: what to extract" \
  "the last long \`assistant\` text block" "$SKILL"
expect_pin_in_file "transcript recovery: persist before acting" \
  "persist it under \`<docs-root>/record/\` before acting on it" "$SKILL"

# The wakeup ban. A date-pinned one-shot is the shape that reads correct and dies silently:
# CronCreate DROPS a tick whose minute finds the session busy, and a one-shot has exactly one
# minute (re-measured, epic-17 W4 S6).
expect_pin_in_file "wakeups: heading states the rule, not a topic" \
  "**Wakeups are recurring, never date-pinned.**" "$SKILL"
expect_pin_in_file "wakeups: the one-shot is banned in those words" \
  "A one-shot \`CronCreate\` pinned to a wall-clock minute is banned" "$SKILL"
expect_pin_in_file "wakeups: the mechanism — busy minutes drop, they do not queue" \
  "a busy minute DROPS the tick rather than queuing it" "$SKILL"
expect_pin_in_file "wakeups: the sanctioned form is recurring-then-delete" \
  "create a SHORT RECURRING job and \`CronDelete\` it on its first fire" "$SKILL"
# Count-scoped: a second, softer copy of the rule elsewhere in the section is how a ban
# becomes a suggestion (same reasoning as the arming-rule count arms above).
expect_count_in_file "the wakeup ban has exactly one copy in the skill" \
  "**Wakeups are recurring, never date-pinned.**" 1 "$SKILL"

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
