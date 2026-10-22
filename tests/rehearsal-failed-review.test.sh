#!/bin/bash
# Tests for the failed-review run state the sitrep card is read in, reached by playing a small run forward through the
# real commands (tests/lib/rehearsal.sh `rehearse`), never by writing the state's files. Each rehearsal state has
# its own suite (rehearsal.test.sh holds the clean one), so no suite runs longer than one rehearsal and its reads.
#
#   §FAILED-REVIEW    the build landed, a whole review registered failing and close-out refused at
#                     Step 8: the sheet owes the waiver and the held merge
#   §TRUE             the person accepting the release reads a pace taken in minutes, a close that is not
#                     weeks out, a held task naming what it waits on, and a card head with no invented wave
#   §FACTS            three goals declared, met, not met and not measured; a close at 1× under three landings;
#                     the suites and the whole run named; a review counted once by its latest result
#
# ONE SHAPE. The sandbox's own `hooks/session-poker.sh sitrep <plan>` prints the sheet, whose `ask:` lines are
# exactly the state's asks; a judgment written from the sheet, answering every open ask, renders through
# `sitrep card` (rc 0, every line at most 100 columns); a judgment that drops one is refused (rc 1, stdout empty).
#
# FIXTURE FIDELITY: the sandbox is tests/lib/door.sh's, a real repository carrying the plugin's hooks and scripts, a
# plan in its Step-3 shape and the release check's closure. Every later state is a command's: the poker's verbs,
# the door's landing, the sweeper's ack, close-out. What `rehearse` writes by hand is what a run's people and agents
# write by hand: the plan's prose, a review's record, a row's code, a criterion's evidence. Each command it runs is
# logged beside the sandbox (`rehearsal.log`), and each section reads the commands its state turns on from that log.
#
# ANTI-VACUITY: a state that cannot be reached stops its section before the sheet is read, asserting the failure.
# Every empty read (no ask, no wide line, an empty stdout) stands beside a non-empty read through the same reader in
# the same section.
#
# Usage: bash tests/rehearsal-failed-review.test.sh

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
section "§FAILED-REVIEW: the build landed, a whole review failed, close-out refused at Step 8"
# ============================================================
# fails-when: the state is not reached through the commands, its sheet lacks the waiver or the held merge, or the
# card drawn from it fails its check.
rt_state failed-review
expect_eq "FR-1 rehearse reaches the state and prints the sandbox's plan (exit 0)" "0|yes" \
  "$RT_RC|$([ -f "$RT_PLAN" ] && echo yes)"
if [ "$RT_RC" = 0 ]; then
  expect_eq "FR-1b …through the door's landing, a failing review registered by its verb, and close-out refused" \
    "yes|yes|yes" "$([ "$(rt_ran 'spawn-worktree.sh land')" -ge 1 ] && echo yes)|$([ "$(rt_ran 'proof-add review')" -ge 1 ] && echo yes)|$([ "$(rt_ran 'close-out.sh')" -ge 1 ] && echo yes)"
  rt_sheet_and_card FR "hold:merge waive:structure" "hold:merge>8/4 waive:structure>8/4" waive:structure
fi

# ============================================================
section "§TRUE: the sheet of the failed-review state reads true to the person who accepts the release on it"
# ============================================================
# FIXTURE FIDELITY: the sandbox of the section above, read again with its own poker. The rehearsal's plan is
# approved when the rehearsal starts, as a person approves it at Step 3 just before the build.
# fails-when: the plan carries an approval from weeks before the run, so the pace reads hundreds of hours and the
# close lands weeks out; a task held on a decision says it is building; the head names a wave the plan lacks.
rt_true_state failed-review

# ============================================================
section "§FACTS: the sheet's facts read true: every line a measurement naming what it measures, its unit and its source; every goal the plan declares, a close not scaled by fewer than three landed tasks, the suites and the whole run named"
# ============================================================
# FIXTURE FIDELITY: the sandbox of the first section, read again with its own poker. The rehearsal's plan declares
# three goals measured by records: one it writes passing, one failing, one it never writes.
# fails-when: a measured line is missing or names no measure, unit and source; a metric. line prints; a sheet draws no
# goal, or a goal reads another status; the close is scaled by one or two landed tasks; a review that passed and then
# failed counts as both; a note counts the reads it leaves out.
rt_facts_state failed-review
RT_ROOT="$WORLD_ROOT/failed-review/project"; RT_PLAN="$RT_ROOT/$DOOR_PLAN_REL"
if [ -f "$RT_PLAN" ]; then
  rt_poker sitrep "$RT_PLAN"
  expect_eq "FA-5 failed-review: the structure review of the whole passed, then failed: it counts once, failed, beside the four that passed" \
    "2|4 passed, 1 failed, 0 running" \
    "$(printf '%s\n' "$RT_OUT" | /usr/bin/grep -c '^review: question=structure scope=whole ')|$(rt_m "$RT_OUT" reviews)"
fi

finish
