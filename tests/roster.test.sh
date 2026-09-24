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
# R6's MET marker, written by hooks/landing-gate.sh's own function (S17: no suite hand-writes it).
. "$(dirname "$0")/lib/swept-marker.sh"

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

section "R5 — the two audit keys a successor row carries (wave-20 T9, REQ-4, AC-4.2/4.4)"

# `amend` records when and why a live contract widened (`amended=`), and `extend` records its
# reason as data (`extended=`) rather than in `claims=`, which the sweeper hands to `pgrep -f`.
# Both are PRESENT-IF-PASSED, like `adopted_from=`: a row that names neither is byte-identical
# to the rows before this wave, and every captured fixture still reproduces.
R5_BASE=(status=identified session=s1 name=w-t9 agent_id=a9 launched_at=2026-09-23T00:00:00Z
  subagent_type=bionic:implementor model=opus deliverable=rec/x.md source=declared duration=
  progress= claims=worker-proc cadence= absent= waiver= tool_use_id=toolu_x plan=none)
R5_PLAIN="$(lib roster_row "${R5_BASE[@]}")"
R5_AM="$(lib roster_row "${R5_BASE[@]}" "amended=2026-09-23T01:00:00Z the fix touches b")"
R5_EX="$(lib roster_row "${R5_BASE[@]}" "extended=2026-09-23T01:00:00Z retry .* (x|y)")"
expect_absent "R5a a row that names neither carries neither" "amended=" "$R5_PLAIN$(printf '%s' "$R5_PLAIN" | grep -o 'extended=')"
expect_contains "R5b amended= is written when passed" "|amended=2026-09-23T01:00:00Z the fix touches b|" "$R5_AM"
expect_contains "R5c extended= is written when passed, its pipe folded like every prose field" \
  "|extended=2026-09-23T01:00:00Z retry .* (x y)|" "$R5_EX"
expect_contains "R5d …and claims= is whatever the caller passed, untouched by it" "|claims=worker-proc|" "$R5_EX"
expect_eq "R5e the keys sit before tool_use_id=, after the instrument fields: the row minus them is the plain row" \
  "$R5_PLAIN" "$(printf '%s' "$R5_AM" | sed 's/|amended=[^|]*//')"

section "R6 — live_ids_of_name asks the one close predicate (epic-23 wave-20 T17, REQ-10; D10)"

# THE DEFECT (T2's carry-over, research D3 §REQ-10). `live_ids_of_name` — the stop wall's
# ambiguity refusal and `adopt_write_row`'s "is this name already live here" — discharged a
# name's ids on a `landing-swept/v1|…|state=MET` marker and never read the sweeper's ledger.
# Every other occupancy reader closes a name only on an ack taken after its latest launch
# (`roster_open_names`), so after a /clear the two could disagree about the same file: a
# MET-but-unacked agent that the dispatch wall, the sweeper and the stop wall all hold open
# read as gone here, and an acked one read as still live.
#
# THE RULE HERE: nothing is live unless `roster_open_names` answers the name open, and within
# an open name an id is discharged exactly as a name is — by an ack whose stamp is later than
# that row's `launched_at=`. The ledger is the roster's sibling, `sweeper-<sid>.state`, the
# path the sweeper writes it to.
#
# A TEMP DIRECTORY, not the hermetic no-file shape R0–R4 keep: the function reads a file.
R6_DIR="$(mktemp -d "${TMPDIR:-/tmp}/roster-r6.XXXXXX")"
trap 'rm -rf "$R6_DIR"' EXIT
r6_row() {  # <roster> <name> <agent id> <launched_at> — the intended then identified pair
  lib roster_row status=intended session=s1 name="$2" agent_id= launched_at="$4" \
    subagent_type=implementor model=opus deliverable= source=declared duration= progress= \
    claims= cadence= absent= waiver= tool_use_id=toolu_r6 plan=none >> "$1"
  lib roster_row status=identified session=s1 name="$2" agent_id="$3" launched_at="$4" \
    subagent_type=implementor model=opus deliverable= source=declared duration= progress= \
    claims= cadence= absent= waiver= tool_use_id=toolu_r6 plan=none >> "$1"
}
r6_ack() {  # <ledger> <at> <name> — the sweeper ledger's ack line, in its writer's shape
  printf 'sweeper-ledger/v1|event=ack|at=%s|epoch=0|pid=1|session=s1|name=%s|by=patrol|reason=landed\n' \
    "$2" "$3" >> "$1"
}
r6_met() {  # <roster> <at> <name> <agent id> — through the landing gate's own writer (S17)
  swept_marker_write "$1" "$2" s1 "$3" "$4" MET
}
r6_ids() {  # <case dir> <name> -> the live ids, space-joined
  ROSTER_FILE="$1/roster-s1.state" lib live_ids_of_name "$2" | tr '\n' ' ' | sed 's/ $//'
}

mkdir -p "$R6_DIR/met"
r6_row "$R6_DIR/met/roster-s1.state" w-met a-met-1 2026-09-01T00:00:00Z
r6_met "$R6_DIR/met/roster-s1.state" 2026-09-01T01:00:00Z w-met a-met-1
expect_eq "R6a a MET marker with no ack discharges nothing: the id is still live" \
  "a-met-1" "$(r6_ids "$R6_DIR/met" w-met)"

mkdir -p "$R6_DIR/acked"
r6_row "$R6_DIR/acked/roster-s1.state" w-acked a-acked-1 2026-09-01T00:00:00Z
r6_ack "$R6_DIR/acked/sweeper-s1.state" 2026-09-01T01:00:00Z w-acked
expect_eq "R6b an ack after the launch discharges the name: nothing is live" \
  "" "$(r6_ids "$R6_DIR/acked" w-acked)"

mkdir -p "$R6_DIR/again"
r6_row "$R6_DIR/again/roster-s1.state" w-again a-again-1 2026-09-01T00:00:00Z
r6_ack "$R6_DIR/again/sweeper-s1.state" 2026-09-01T01:00:00Z w-again
r6_row "$R6_DIR/again/roster-s1.state" w-again a-again-2 2026-09-01T02:00:00Z
expect_eq "R6c acked, then dispatched again: only the id launched after the ack is live" \
  "a-again-2" "$(r6_ids "$R6_DIR/again" w-again)"

# THE PAIRED POSITIVE for the ambiguity the stop wall polices: two ids of one name, neither
# acked, are BOTH live. Without it R6b is equally green on a function that answers nothing.
mkdir -p "$R6_DIR/twin"
r6_row "$R6_DIR/twin/roster-s1.state" w-twin a-twin-1 2026-09-01T00:00:00Z
r6_row "$R6_DIR/twin/roster-s1.state" w-twin a-twin-2 2026-09-01T02:00:00Z
expect_eq "R6d two unacked ids of one name are both live (the ambiguity)" \
  "a-twin-1 a-twin-2" "$(r6_ids "$R6_DIR/twin" w-twin)"

# STRICTLY LATER, as the predicate says: an ack in the launch's own second cannot be ordered
# against it, and the safe direction is live.
mkdir -p "$R6_DIR/same"
r6_row "$R6_DIR/same/roster-s1.state" w-same a-same-1 2026-09-01T00:00:00Z
r6_ack "$R6_DIR/same/sweeper-s1.state" 2026-09-01T00:00:00Z w-same
expect_eq "R6e an ack stamped in the launch's own second discharges nothing" \
  "a-same-1" "$(r6_ids "$R6_DIR/same" w-same)"

# A SYMLINKED LEDGER IS READ AS EMPTY, as `roster_open_names` reads it: every id stays live.
mkdir -p "$R6_DIR/link"
r6_row "$R6_DIR/link/roster-s1.state" w-link a-link-1 2026-09-01T00:00:00Z
r6_ack "$R6_DIR/link/real-ledger" 2026-09-01T01:00:00Z w-link
ln -s "$R6_DIR/link/real-ledger" "$R6_DIR/link/sweeper-s1.state"
expect_eq "R6f a symlinked ledger closes nothing" \
  "a-link-1" "$(r6_ids "$R6_DIR/link" w-link)"

section "R7 — roster_open_names takes the LATEST launch, not the last row in file order (epic-23 wave-20 T20b, C7)"

# THE DEFECT (critic C7, roster.sh:374). `_roster_open_of`'s `born[nm]` was overwritten by
# EVERY live row of a name, in file order — so the name's remembered launch was whichever row
# happened to be LAST on disk, not the latest `launched_at`. Adoption
# (`adopt_write_row`, hooks/session-poker.sh:1841) can append a PREDECESSOR's row, carrying
# its own original — and OLDER — `launched_at`, after a fresher live row already on the file
# for the same name. An ack taken between the two stamps then closed a name whose real latest
# launch was still open.
R7_DIR="$(mktemp -d "${TMPDIR:-/tmp}/roster-r7.XXXXXX")"
trap 'rm -rf "$R7_DIR"' EXIT
r7_open() {  # <case dir> -> the open names, space-joined
  lib roster_open_names "$1/roster-s1.state" "$1/sweeper-s1.state" | tr '\n' ' ' | sed 's/ $//'
}

mkdir -p "$R7_DIR/outoforder"
# The FRESHER launch is written FIRST in file order...
r6_row "$R7_DIR/outoforder/roster-s1.state" w-outoforder a-outoforder-1 2026-09-01T05:00:00Z
# ...and an OLDER launch for the SAME name is appended SECOND — the adopt-order shape (a
# predecessor's row, carrying its own earlier stamp, landing after a fresher dispatch).
r6_row "$R7_DIR/outoforder/roster-s1.state" w-outoforder a-outoforder-2 2026-09-01T01:00:00Z
r6_ack "$R7_DIR/outoforder/sweeper-s1.state" 2026-09-01T02:00:00Z w-outoforder
expect_eq "R7a the name stays open: the ack (02:00) is not later than the LATEST launch (05:00), whichever row is last on disk" \
  "w-outoforder" "$(r7_open "$R7_DIR/outoforder")"

# THE PAIRED CONTROL: in FILE order (fresher last), the same two stamps and the same ack
# already gave the right answer before this fix — the bug is order-dependent, not present on
# every input, and this pins the direction that was never wrong.
mkdir -p "$R7_DIR/infileorder"
r6_row "$R7_DIR/infileorder/roster-s1.state" w-infileorder a-infileorder-1 2026-09-01T01:00:00Z
r6_row "$R7_DIR/infileorder/roster-s1.state" w-infileorder a-infileorder-2 2026-09-01T05:00:00Z
r6_ack "$R7_DIR/infileorder/sweeper-s1.state" 2026-09-01T02:00:00Z w-infileorder
expect_eq "R7b …and stays open when the fresher launch is already last on disk (the control)" \
  "w-infileorder" "$(r7_open "$R7_DIR/infileorder")"

section "R8 — an unreadable stamp on ANY live row of a name keeps it open, in either file order (epic-23 wave-20 T20c, review R2-2)"

# THE DEFECT (review R2-2, INTRODUCED by T20b's max-stamp rule). `born[nm]` kept the maximum
# WELL-FORMED stamp, and an unreadable candidate never displaced it — so an older well-formed
# launch won over a later live row whose stamp could not be read, and an ack between them
# closed the name. That is the predicate's own rule read backwards: "AN UNREADABLE STAMP ON
# EITHER SIDE CLOSES NOTHING". The fix: an unreadable stamp on any live row makes `born`
# unreadable, and that sticks, whatever order the rows sit in. The fixture is the review's:
# `unread` launched 01:00Z, then a row with `launched_at=` empty, and an ack at 02:00Z.
# bionic's own writers cannot produce the empty stamp (preflight and the recorder both stamp
# `date -u`); a hand-edited or legacy row can.
mkdir -p "$R7_DIR/unread"
r6_row "$R7_DIR/unread/roster-s1.state" unread a-unread-1 2026-09-01T01:00:00Z
r6_row "$R7_DIR/unread/roster-s1.state" unread a-unread-2 ""
r6_ack "$R7_DIR/unread/sweeper-s1.state" 2026-09-01T02:00:00Z unread
expect_eq "R8a the review's fixture: a later live row with an unreadable stamp keeps the name open (fail closed)" \
  "unread" "$(r7_open "$R7_DIR/unread")"

# THE ORDER CONTROL: the same two rows the other way round. Stickiness is the point — the
# unreadable row seen FIRST must not be displaced by the well-formed one after it either.
mkdir -p "$R7_DIR/unreadfirst"
r6_row "$R7_DIR/unreadfirst/roster-s1.state" unreadfirst a-unreadfirst-1 "not-a-time"
r6_row "$R7_DIR/unreadfirst/roster-s1.state" unreadfirst a-unreadfirst-2 2026-09-01T01:00:00Z
r6_ack "$R7_DIR/unreadfirst/sweeper-s1.state" 2026-09-01T02:00:00Z unreadfirst
expect_eq "R8b …and in the other file order: an unreadable stamp seen first sticks (the order control)" \
  "unreadfirst" "$(r7_open "$R7_DIR/unreadfirst")"

# THE PAIRED POSITIVE: the same history with both stamps readable closes the name. Without it
# R8a and R8b are equally green on a predicate that never closes anything.
mkdir -p "$R7_DIR/readable"
r6_row "$R7_DIR/readable/roster-s1.state" readable a-readable-1 2026-09-01T00:30:00Z
r6_row "$R7_DIR/readable/roster-s1.state" readable a-readable-2 2026-09-01T01:00:00Z
r6_ack "$R7_DIR/readable/sweeper-s1.state" 2026-09-01T02:00:00Z readable
expect_eq "R8c …while the same history with every stamp readable is closed by the ack (the row discriminates)" \
  "" "$(r7_open "$R7_DIR/readable")"

section "R9 — a restart after an ack holds the name open by its restarted_at, not by moving launched_at (epic-23 wave-20 T20c, critic C2-2)"

# OCCUPANCY AND THE CONTRACT ARE TWO QUESTIONS (D10). A SubagentStart for an id whose lineage
# an ack already closed is a restart: the agent is back on the panel and holds a slot. T20b
# answered that by stamping the restart row's `launched_at` fresh — and `launched_at` is also
# the clock the sweeper dates the deliverable against, so a contract met before the ack read
# UNMET for good, and `stopped` closed it `abandoned` (critic C2-2). The recorder now keeps
# `launched_at` as the contract's launch and writes the restart's own time as `restarted_at=`;
# this predicate — the one close predicate — takes a row's occupancy stamp from
# `restarted_at` when the row carries one. The row is built the way the recorder builds it:
# the production row, with `restarted_at=` appended at the end.
r9_restart_row() {  # <roster> <name> <agent id> <launched_at> <restarted_at>
  printf '%s|restarted_at=%s\n' "$(lib roster_row status=identified session=s1 name="$2" agent_id="$3" \
    launched_at="$4" subagent_type=implementor model=opus deliverable= source=declared duration= \
    progress= claims= cadence= absent= waiver= tool_use_id=toolu_r6 plan=none)" "$5" >> "$1"
}
mkdir -p "$R7_DIR/restart"
r6_row "$R7_DIR/restart/roster-s1.state" w-restart a-restart-1 2026-09-01T01:00:00Z
r6_ack "$R7_DIR/restart/sweeper-s1.state" 2026-09-01T02:00:00Z w-restart
r9_restart_row "$R7_DIR/restart/roster-s1.state" w-restart a-restart-1 2026-09-01T01:00:00Z 2026-09-01T03:00:00Z
expect_eq "R9a a restart row whose restarted_at postdates the ack holds the name open — though its launched_at does not" \
  "w-restart" "$(r7_open "$R7_DIR/restart")"

# THE CONTROL: the same row with no restarted_at is an ordinary resume carrying the original
# launch, and the ack closes it — so R9a's answer comes from the new field and nothing else.
mkdir -p "$R7_DIR/norestart"
r6_row "$R7_DIR/norestart/roster-s1.state" w-norestart a-norestart-1 2026-09-01T01:00:00Z
r6_ack "$R7_DIR/norestart/sweeper-s1.state" 2026-09-01T02:00:00Z w-norestart
r6_row "$R7_DIR/norestart/roster-s1.state" w-norestart a-norestart-1 2026-09-01T01:00:00Z
expect_eq "R9b …the same history with no restarted_at is closed by the ack (the control)" \
  "" "$(r7_open "$R7_DIR/norestart")"

# A RESTART BEFORE THE ACK closes like any launch: the ack after it discharges the name.
mkdir -p "$R7_DIR/restartacked"
r6_row "$R7_DIR/restartacked/roster-s1.state" w-racked a-racked-1 2026-09-01T01:00:00Z
r9_restart_row "$R7_DIR/restartacked/roster-s1.state" w-racked a-racked-1 2026-09-01T01:00:00Z 2026-09-01T03:00:00Z
r6_ack "$R7_DIR/restartacked/sweeper-s1.state" 2026-09-01T04:00:00Z w-racked
expect_eq "R9c …and an ack after the restart closes the restarted name (the close still works)" \
  "" "$(r7_open "$R7_DIR/restartacked")"

finish
