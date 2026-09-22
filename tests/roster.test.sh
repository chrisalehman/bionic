#!/bin/bash
# ROSTER ROW — the writer's own round-trip (epic-23 wave-18, T4; REQ-7, D4).
#
# WHAT THIS SUITE OWNS. `payload/scripts/lib/roster.sh` — the ONE writer of the
# `roster-state/v1` row — and the invariant D4 names: WHAT IS WRITTEN IS WHAT IS READ
# BACK. Every other suite in the fleet uses that writer through
# `tests/lib/roster-row.sh` to build a fixture and then asserts something about a
# READER; none of them asks whether the writer's own encoding is reversible, and until
# this wave it was not: `roster_row` folded `|` to a space in every field, silently, so
# a declared run carrying a quoted pipe reached the row as a command no agent could
# ever type back.
#
# THE DELIMITER IS STILL DEFENDED, and that is the half a round-trip must not cost.
# A pipe inside a value would forge a segment on a line every reader in the fleet
# parses BY KEY, so the pipe cannot survive the row as itself. `re_executes=` — the
# one field whose value is a COMMAND the writer-side budget arm compares character for
# character — carries it percent-encoded instead of folded; every other field keeps
# the fold, because none of them is compared back against something a human typed.
#
# NOT THE READERS. `_run_is_declared` (payload/scripts/lib/walls.sh) is
# tests/background-suite-guard.test.sh §B13's; the lift that produces the value is
# tests/dispatch-preflight.test.sh's; `adopt`'s re-write is tests/session-poker.test.sh's.
# This suite is the writer and its decoder twin, alone.
#
# HERMETIC. No repo, no roster file, no hook: the library is sourced into a clean
# subshell and its two functions are called directly.
#
# Usage: bash tests/roster.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

ROSTER_SH="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/roster.sh"

# The library is sourced ONCE, here, and never into this suite's own shell: `roster.sh`
# defines `roster_row` and `live_ids_of_name`, and a private definition of either name in
# a test file is the shadow tests/stop-guard.test.sh and tests/fail-direction-table.test.sh
# both carry a comment about. A subshell per call keeps the suite honest for the same price.
lib() {  # <fn> [args...] -> that roster.sh function's stdout; its status is this call's
  bash -c '. "$1"; shift; "$@"' _ "$ROSTER_SH" "$@"
}

field_of_row() {  # <row> <key> -> the FIRST value the fleet's by-key read would see
  printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-
}

count_fields() {  # <row> <key=value> -> how many segments carry exactly this text
  printf '%s' "$1" | tr '|' '\n' | grep -c "^$2\$" | tr -d ' '
}

section "R0 — the library is on disk and its two encoding functions exist"

if [ -r "$ROSTER_SH" ]; then ok "payload/scripts/lib/roster.sh is readable"; else
  no "payload/scripts/lib/roster.sh is readable" "$ROSTER_SH"; finish; fi

expect_eq "R0a roster_row is defined" "function" "$(lib type -t roster_row 2>/dev/null)"
expect_eq "R0b roster_pipe_escape is defined" "function" \
  "$(lib type -t roster_pipe_escape 2>/dev/null)"
expect_eq "R0c roster_pipe_unescape is defined" "function" \
  "$(lib type -t roster_pipe_unescape 2>/dev/null)"

section "R1 — the escape pair is a bijection on the values a run can hold"

# THE CONSUMER'S OWN COMMAND (research R2 §2; the jest case that opened REQ-7). It carries
# a pipe inside single quotes AND the backslashes of a regex, which is why the escape form
# is percent and not backslash: a backslash escape would have to double every one of those.
R1_JEST="npx jest --testPathPattern='(a|b)\\.spec\\.ts\$'"
R1_ENC="$(lib roster_pipe_escape "$R1_JEST")"
expect_eq "R1a the pipe leaves the value as %7C" \
  "npx jest --testPathPattern='(a%7Cb)\\.spec\\.ts\$'" "$R1_ENC"
expect_eq "R1b …and it decodes back to the exact command" "$R1_JEST" \
  "$(lib roster_pipe_unescape "$R1_ENC")"

# THE ESCAPE CHARACTER IS ESCAPED TOO, which is what makes the pair reversible rather than
# merely lossy in one direction. Without it a command holding the literal text %7C would
# decode into one holding a pipe — a different command, admitted under the first one's name.
R1_PCT='printf "50%% done" | tee %7C'
R1_PENC="$(lib roster_pipe_escape "$R1_PCT")"
expect_absent "R1c an encoded value carries no bare pipe" "|" "$R1_PENC"
expect_eq "R1d …and a literal %7C in the command survives as itself" "$R1_PCT" \
  "$(lib roster_pipe_unescape "$R1_PENC")"

# NOTHING TO ESCAPE, NOTHING CHANGED. Every run this repo has ever declared is this shape,
# and the wave's own constraint is that those rows read exactly as before.
R1_PLAIN="npx jest --testPathPatterns 'x'"
expect_eq "R1e a value with neither pipe nor percent is untouched" "$R1_PLAIN" \
  "$(lib roster_pipe_escape "$R1_PLAIN")"
expect_eq "R1f …and decoding it is the same no-op" "$R1_PLAIN" \
  "$(lib roster_pipe_unescape "$R1_PLAIN")"

section "R2 — re_executes= round-trips its own delimiter through the row"

R2_ROW="$(lib roster_row status=intended session=s1 name=w-t4 agent_id=a000 \
  launched_at=2026-09-22T00:00:00Z subagent_type=implementor model=opus \
  deliverable= source=declared duration= progress= claims= cadence= absent= waiver= \
  "re_executes=$R1_JEST" tool_use_id=toolu_x plan=none)"

expect_nonempty "R2a the writer emitted a row" "$R2_ROW"
expect_eq "R2b the row is ONE line" "1" "$(printf '%s\n' "$R2_ROW" | wc -l | tr -d ' ')"
expect_eq "R2c the field carries the ESCAPED command, not the typed one" \
  "npx jest --testPathPattern='(a%7Cb)\\.spec\\.ts\$'" "$(field_of_row "$R2_ROW" re_executes)"
expect_eq "R2d …and decoding that field gives back exactly what was written" \
  "$R1_JEST" "$(lib roster_pipe_unescape "$(field_of_row "$R2_ROW" re_executes)")"

# THE SEGMENT COUNT IS THE PROPERTY, not the field's text (the reasoning
# tests/dispatch-preflight.test.sh S25d5 records): a by-key reader sees SEGMENTS, and the
# encoding is worth nothing if the value still split the line into one more of them.
expect_eq "R2e the value forged no segment of its own" "0" "$(count_fields "$R2_ROW" 'b)\\.spec\\.ts\$=')"
expect_eq "R2f every field of the row is a key=value" "0" \
  "$(printf '%s' "$R2_ROW" | tr '|' '\n' | sed 1d | grep -cv '^[a-z_]*=' | tr -d ' ')"

section "R3 — every OTHER field still folds the pipe, and a plain row is byte-identical"

# THE FOLD IS NOT WEAKENED. `re_executes=` is the one field whose value is compared back
# against a command a human typed; `deliverable=`, `name=`, `plan=` and the rest are prose
# or paths, nothing reads them back for equality with typed text, and a percent-encoding
# there would only make a forged value readable again. So they keep the fold they had.
R3_ROW="$(lib roster_row status=intended session=s1 name=w-t4 agent_id=a000 \
  launched_at= subagent_type= model= "deliverable=rec|status=landed|name=ghost.md" \
  source= duration= progress= claims= cadence= absent= waiver= tool_use_id= plan=none)"
expect_eq "R3a a pipe in deliverable= is still folded to a space" \
  "rec status=landed name=ghost.md" "$(field_of_row "$R3_ROW" deliverable)"
expect_eq "R3b …so the forged status= is not a segment" "0" \
  "$(count_fields "$R3_ROW" 'status=landed')"
expect_eq "R3c …and the real one still is, exactly once" "1" \
  "$(count_fields "$R3_ROW" 'status=intended')"

# THE EXISTING FLEET READS EXACTLY AS BEFORE. No row bionic has ever written carries a pipe
# or a percent in `re_executes=`, so the wave must be invisible to every one of them.
R3_PLAIN="$(lib roster_row status=confirmed session=s1 name=w-t4 agent_id=a000 \
  launched_at=2026-09-22T00:00:00Z subagent_type=implementor model=opus \
  deliverable=rec/x.md source=declared duration= progress= claims= cadence= absent= \
  waiver= "re_executes=\`npx jest --testPathPatterns 'x'\`" tool_use_id=toolu_x plan=none)"
expect_contains "R3d a run with no pipe lands on the row verbatim" \
  "re_executes=\`npx jest --testPathPatterns 'x'\`" "$R3_PLAIN"
expect_absent "R3e …and nothing was percent-encoded into it" "%" "$R3_PLAIN"

section "R4 — the writer's refusals are unchanged"

# NOT VACUOUS IN THE NEGATIVE DIRECTION. R2 and R3 would both pass against a writer that
# had stopped refusing anything, so the two refusals that make `roster_row` the one writer
# are driven here beside them.
lib roster_row status=intended "ts=2026-09-22" >/dev/null 2>&1
expect_status "R4a an unrecognised key is still a refusal" "2" "$?"
lib roster_row status=intended barewordarg >/dev/null 2>&1
expect_status "R4b a bare word is still a refusal" "2" "$?"

finish
