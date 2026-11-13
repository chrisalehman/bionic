#!/bin/bash
# Tests for the clean run state the sitrep card is read in, reached by playing a small run forward through the
# real commands (tests/lib/rehearsal.sh `rehearse`), never by writing the state's files. Each rehearsal state has
# its own suite (rehearsal-failed-review.test.sh, rehearsal-release-waiting.test.sh and rehearsal-stop-rule.test.sh
# hold the others), so no suite runs longer than one rehearsal and its reads.
#
#   §CLEAN            mid-build, nothing owed: the sheet says so
#   §TRUE             the person accepting the release reads a pace taken in minutes, a close that is not
#                     weeks out, a held task naming what it waits on, and a card head with no invented wave
#   §FACTS            three goals declared, met, not met and not measured; a close at 1× under three landings;
#                     the suites and the whole run named
#   §GATE             a rehearsed world whose own gate is full stops at its landing's WAITING
#
# EACH SECTION, ONE SHAPE. The sandbox's own `hooks/session-poker.sh sitrep <plan>` prints the sheet, whose `ask:`
# lines are exactly the state's asks; a judgment written from the sheet, answering every open ask, renders through
# `sitrep card` (rc 0, every line at most 100 columns); a judgment that drops one is refused (rc 1, stdout empty). The
# clean state has no ask to drop, so its refusal is a judgment naming an ask the register lacks, the same floor read
# from the other side.
#
# FIXTURE FIDELITY: the sandbox is tests/lib/door.sh's, a real repository carrying the plugin's hooks and scripts and
# the release check's closure, with no plan: its run starts at the configuration card. Every state is a command's: the poker's verbs,
# the door's landing, the sweeper's ack, close-out. What `rehearse` writes by hand is what a run's people and agents
# write by hand: the plan's prose, a review's record, a row's code, a criterion's evidence. Each command it runs is
# logged beside the sandbox (`rehearsal.log`), and each section reads the commands its state turns on from that log.
#
# ANTI-VACUITY: a state that cannot be reached stops its section before the sheet is read, asserting the failure.
# Every empty read (no ask, no wide line, an empty stdout) stands beside a non-empty read through the same reader in
# the same section.
#
# Usage: bash tests/rehearsal.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
RH_LOADED=0
# shellcheck source=/dev/null
. "$(dirname "$0")/lib/rehearsal.sh" && RH_LOADED=1
[ -n "${WORLD_ROOT:-}" ] || . "$(dirname "$0")/lib/world.sh"
# shellcheck source=/dev/null
. "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/width.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/lib/rehearsal-read.sh"

# ============================================================
section "§CLEAN: mid-build, nothing owed"
# ============================================================
# fails-when: the state is not reached through the commands, its sheet shows an ask, or the card drawn from it fails
# its check.
rt_state clean
expect_eq "CL-1 rehearse reaches the state and prints the sandbox's plan (exit 0)" "0|yes" \
  "$RT_RC|$([ -f "$RT_PLAN" ] && echo yes)"
if [ "$RT_RC" = 0 ]; then
  expect_eq "CL-1b …through the build row's ready, the release row launched" "yes|yes" \
    "$([ "$(rt_ran 'spawn-worktree.sh ready')" -ge 1 ] && echo yes)|$([ "$(rt_ran 'dispatch event')" -ge 2 ] && echo yes)"
  rt_sheet_and_card CL "" "" ""
fi


# ============================================================
section "§TRUE: the sheet of the clean state reads true to the person who accepts the release on it"
# ============================================================
# FIXTURE FIDELITY: the sandbox of the section above, read again with its own poker. The rehearsal's plan is
# approved when the rehearsal starts, as a person approves it at Step 3 just before the build.
# fails-when: the plan carries an approval from weeks before the run, so the pace reads hundreds of hours and the
# close lands weeks out; a task held on a decision says it is building; the head names a wave the plan lacks.
rt_true_state clean

# ============================================================
section "§FACTS: the sheet's facts read true: every line a measurement naming what it measures, its unit and its source; every goal the plan declares, a close not scaled by fewer than three landed tasks, the suites and the whole run named"
# ============================================================
# FIXTURE FIDELITY: the sandbox of the first section, read again with its own poker. The rehearsal's plan declares
# three goals measured by records: one it writes passing, one failing, one it never writes.
# fails-when: a measured line is missing or names no measure, unit and source; a metric. line prints; a sheet draws no
# goal, or a goal reads another status; the close is scaled by one or two landed tasks; a review that passed and then
# failed counts as both; a note counts the reads it leaves out.
rt_facts_state clean

section "§GATE: a rehearsed world whose own gate is full stops at the build row's landing"
# fails-when: the rehearsal takes the landing line's WAITING as a landing, or its world's gate ignores its own config.
mkdir -p "$WORLD_ROOT/full/config/bionic" && printf '1\n' > "$WORLD_ROOT/full/config/bionic/share"
GA_RC=0; ( RH_WITHIN=5 rehearse single-verify "$WORLD_ROOT/full" ) > /dev/null 2> "$WORLD_ROOT/full.err" || GA_RC=$?
expect_eq "GA-1 a share of 1% under 30% used admits nothing: rehearse stops (exit 1)" "1" "$GA_RC"
expect_contains "GA-1b …at the build row's ready, WAITING (rc 75)" "the build row says ready failed (rc 75)" "$(cat "$WORLD_ROOT/full.err")"

finish
