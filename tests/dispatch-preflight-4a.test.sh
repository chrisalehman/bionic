#!/bin/bash
# Tests for hooks/dispatch-preflight.sh — THE START GATE. One shard of four, in two parts: part 1 of 2, S10h … §AC-E1.3.
#
# The suite's header (what it governs, how it stays hermetic) is in tests/dispatch-preflight.test.sh; the
# fixtures and their fidelity notes are in tests/dispatch-preflight.prelude.sh; what the two parts of this shard
# share, and why it is two, is in tests/dispatch-preflight-4.prelude.sh.
#
# THIS SHARD IS TWO PARTS (wave-39 T37; D1, D13, REQ-3 AC-3.3). One dispatch-preflight-4.test.sh promised more
# than a landing window holds, so it runs as two suites cut at a section boundary:
#
#   dispatch-preflight-4a.test.sh   S10h … §AC-E1.3
#   dispatch-preflight-4b.test.sh   §LANDS-ON … §RECORDER
#
# Each is a gating suite by location and each passes alone.
#
# Usage: bash tests/run.sh --only dispatch-preflight-4a.test.sh


set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
MAKE_REPO_AT=15; . "$(dirname "$0")/dispatch-preflight.prelude.sh"

. "$(dirname "$0")/dispatch-preflight-4.prelude.sh"

section "S10h — a symlinked roster path is never written through, and the dispatch is refused (§8; wave-28 T70)"
#
# A hostile repo controls its own .bionic/ contents. It must not gain an arbitrary-file append,
# and since T70 it must not gain a silent admission either. (The DIRECTORY-level variants are
# already refused upstream by the attestation check — S8 drives them — so the file level is the
# only one reachable here.)

REPO=$(make_repo r10h yes)
write_attestation "$REPO" "$SID_A"
# DECOY_ROSTER: hoisted to tests/dispatch-preflight-4.prelude.sh (§RECORDER, in part b, reads the file this section plants)
ln -s "$DECOY_ROSTER" "$(roster_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "a symlinked roster path REFUSES the dispatch" "deny" "$GATE_VERDICT"
expect_contains "…the detail names the link" "roster-${SID_A}.state" "$GATE_VERR"
expect_status "the symlink target is not appended to" "untouched" "$(cat "$DECOY_ROSTER")"

section "AC-E1.3/E1.5 — every refusal this gate makes is one line, in the shape"

# fails-when: a refusal reaches the user as more than one line, or in any shape but
# `bionic: <verb> refused — <fact> (<fix ≤ 40 cols>)`.
#
# WHY A WRAPPER AND NOT ONE ROW PER SITE. This gate has sixteen refusal sites behind
# three frames, and every one of them is already driven somewhere above. `run_gate` is
# wrapped here so that EVERY refusal the rest of this suite produced was checked as it
# happened — shape, line count and column budget — and the counter proves the sweep saw
# real refusals rather than counting over air.


expect_eq "E1.3 the gate refused in this run (not counting over air)" "yes" \
  "$([ "${DP_E1_SEEN:-0}" -ge 1 ] && echo yes || echo no)"
expect_eq "E1.3 every refusal matched the criterion's shape" "" "${DP_E1_BAD_SHAPE:-}"
expect_eq "E1.3 every refusal was exactly one line" "" "${DP_E1_BAD_LINES:-}"
expect_eq "E1.3 every refusal fitted the 100-column budget" "" "${DP_E1_BAD_COLS:-}"
# THE UNCOVERED SITE, named rather than silently tolerated: `live-agents:` has no row in
# the task-12 wording table, so it still speaks in its own voice. Any OTHER refusal that
# renders no line fails here.
expect_eq "E1.3 the only refusals with no rendered line are the uncovered live-agents site" \
  "" "${DP_E1_UNNAMED:-}"

# THE TABLE'S EXACT WORDING at three sites, one per frame: the environment frame, the
# Patrol frame, and a direct arm.
REPO=$(make_repo re13b yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "Your task: build it.
Expected duration: ~15 minutes.
Suites: tests/widget.test.sh" "w-e13b")"

# AC-E1.5, the pair: the user stream LEADS with the verdict line, and the knob carries the
# frame's Fix block.
#
# RE-AUTHORED FROM A LINE COUNT TO THE LINE (REQ-2, D2/ADR-030; A-orch-13/A-orch-14). This
# assertion used to read "the Fix block is NOT on the user stream", which was the 1.8.2
# reading of AC-E1.5: an `exit2` refusal rendered its one line and nothing else, so the
# absence of any detail text WAS the criterion. D2 reverses that by Chris's own call — an
# `exit2` refusal now prints its bounded violation detail under the verdict — and an absence
# pin would red at the wave head for the change it was never about. What AC-E1.5 has always
# been about is that the READER GETS THE VERDICT: one line, in the table's words, first.
# That claim holds on both sides of the flip, and it is what is pinned here.
# THE FIRST `bionic: ` LINE, not the first line and not the only line. The user stream can
# carry an advisory above the verdict — this very fixture draws `dispatch-preflight: run
# resolved by newest-plan fallback` — and under D2 it carries bounded detail below it, so
# both edges of the refusal are lines this assertion must not count.
expect_contains "E1.5 …and BIONIC_WALL_VERBOSE=1 puts it back" \
  "Then retry the dispatch" "$GATE_VERR"

# ============================================================================

finish
