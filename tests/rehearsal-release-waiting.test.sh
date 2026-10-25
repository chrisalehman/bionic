#!/bin/bash
# Tests for the release-waiting run state the sitrep card is read in, reached by playing a small run forward through the
# real commands (tests/lib/rehearsal.sh `rehearse`), never by writing the state's files. Each rehearsal state has
# its own suite (rehearsal.test.sh holds the clean one), so no suite runs longer than one rehearsal and its reads.
#
#   §RELEASE-WAITING  the release approval card rendered and waiting on its reply: the sheet
#                     owes what the card put
#   §TRUE             the person accepting the release reads a pace taken in minutes, a close that is not
#                     weeks out, a held task naming what it waits on, and a card head with no invented wave
#   §FACTS            three goals declared, met, not met and not measured; a close at 1× under three landings;
#                     the suites and the whole run named; a held task naming every read it waits on
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
# Usage: bash tests/rehearsal-release-waiting.test.sh

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
section "§RELEASE-WAITING: the release approval card rendered and waiting on its reply"
# ============================================================
# fails-when: the state is not reached through the commands, its sheet lacks the release approval, or the card drawn
# from it fails its check.
rt_state release-waiting
expect_eq "RW-1 rehearse reaches the state and prints the sandbox's plan (exit 0)" "0|yes" \
  "$RT_RC|$([ -f "$RT_PLAN" ] && echo yes)"
if [ "$RT_RC" = 0 ]; then
  expect_eq "RW-1b …through the door's landing, the regression run and the release approval card's own verb" \
    "yes|yes|yes" "$([ "$(rt_ran 'spawn-worktree.sh land')" -ge 1 ] && echo yes)|$([ "$(rt_ran 'regression-run')" -ge 1 ] && echo yes)|$([ "$(rt_ran 'release-approval')" -ge 1 ] && echo yes)"
  # The release text landed past the whole run, so the card asks the merge without a pass at this head beside the
  # release and the merge. No row reads that approval by name, so the sheet's holds reads it as holding nothing,
  # though the gate at Step 8 holds the merge on it.
  rt_sheet_and_card RW "approve:merge approve:merge-unproved approve:release" \
    "approve:merge-unproved>nothing approve:merge>8/4 approve:release>8/4" approve:release
fi

# ============================================================
section "§TRUE: the sheet of the release-waiting state reads true to the person who accepts the release on it"
# ============================================================
# FIXTURE FIDELITY: the sandbox of the section above, read again with its own poker. The rehearsal's plan is
# approved when the rehearsal starts, as a person approves it at Step 3 just before the build.
# fails-when: the plan carries an approval from weeks before the run, so the pace reads hundreds of hours and the
# close lands weeks out; a task held on a decision says it is building; the head names a wave the plan lacks.
rt_true_state release-waiting

# ============================================================
section "§FACTS: the sheet's facts read true: every line a measurement naming what it measures, its unit and its source; every goal the plan declares, a close not scaled by fewer than three landed tasks, the suites and the whole run named"
# ============================================================
# FIXTURE FIDELITY: the sandbox of the first section, read again with its own poker. The rehearsal's plan declares
# three goals measured by records: one it writes passing, one failing, one it never writes.
# fails-when: a measured line is missing or names no measure, unit and source; a metric. line prints; a sheet draws no
# goal, or a goal reads another status; the close is scaled by one or two landed tasks; a review that passed and then
# failed counts as both; a note counts the reads it leaves out.
rt_facts_state release-waiting
RT_ROOT="$WORLD_ROOT/release-waiting/project"; RT_PLAN="$RT_ROOT/$DOOR_PLAN_REL"
if [ -f "$RT_PLAN" ]; then
  rt_poker sitrep "$RT_PLAN"
  expect_eq "FA-6 release-waiting: the merge row names every read it waits on, in words: its step and both approvals" \
    "note=waits on step 8, your approval of the release and your approval of the merge" \
    "$(rt_taskline "$RT_OUT" T4 | /usr/bin/grep -o 'note=.*$')"
  # The whole run's head F, read off the plan's regression proof, and the working head H, off the branch's ref; the
  # count between them is git's, so the line is held to the history and not to the printer's own arithmetic.
  RT_F="$(bash -c '. "$1/proof.sh" && proof_last "$2" regression' _ "$BIONIC_SCRIPTS_DIR/payload/scripts/lib" "$RT_PLAN" 2>/dev/null)"
  RT_H="$(bash -c '. "$1/run.sh" && . "$1/proof.sh" && proof_branch_head "$2" "$3"' _ "$BIONIC_SCRIPTS_DIR/payload/scripts/lib" "$RT_PLAN" "$RT_ROOT" 2>/dev/null)"
  RT_N="$(git -C "$RT_ROOT" rev-list --first-parent --count "$RT_F..$RT_H" 2>/dev/null)"
  expect_eq "FA-6b precondition: the release text landed past the whole run, so the working head is not the run's" \
    "yes|yes" "$([ -n "$RT_F" ] && [ -n "$RT_H" ] && [ "$RT_F" != "$RT_H" ] && echo yes)|$([ "${RT_N:-0}" -gt 0 ] && echo yes)"
  RT_L="landings"; [ "${RT_N:-}" != 1 ] || RT_L="landing"
  expect_eq "FA-6c …so the whole run the regression row ran reads red at its head, the landings since counted" \
    "red at ${RT_F:0:8}, ${RT_N:-?} $RT_L before this head" "$(rt_m "$RT_OUT" tests.whole-run)"
fi

finish
