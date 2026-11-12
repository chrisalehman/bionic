#!/bin/bash
# hooks/stop.sh — ONE PROCESS AT TURN END (epic-23 wave-11-lean-spine, REQ-1f (iv);
# spec Design §1 "TurnEndVerdict", §2 D4; ADR-004).
#
# Registered exactly once on Stop and exactly once on SubagentStop. It reads the
# event, runs the four verdict functions of payload/scripts/lib/stop.sh, and lets
# payload/scripts/lib/fold.sh compose whatever they say by one rule:
#
#     any block is a block · all reasons print · blocks before advisories
#
# WHAT THIS REPLACES. Four separate command objects fired on Stop — context-spend,
# landing-gate, patrol-duties-gate, patrol-revive — each with its own copy of the
# same preamble and its own verdict, and NO rule for how four verdicts combine. Up
# to three of them could refuse one stop; the platform collected whichever arrived,
# and an operator reconciled up to four outputs. The functions are named below in
# the order that manifest listed them, so the reasons appear in the order the
# machine has always produced them.
#
# THE ORDER IS A CHOICE THIS FILE MAKES AND NOTHING ELSE DOES. `bionic_fold` runs
# what it is given, in the order it is given; census §6.2 measured that the four are
# independent and order-free at Stop — none reads a file another writes during the
# same event — so the argument order below is about how a composed refusal READS,
# not about correctness.
#
# THE RE-ENTRANCY GUARD IS READ HERE, ONCE. Claude Code re-enters the stop with
# `stop_hook_active` true after a hook blocked it; refusing again would wedge the
# turn with no way out. Three of the four hooks carried an identical copy of this
# line and the fourth carried none at all; there is one now, ahead of all four.
#
# THE LIBRARY IS WANTED IN FULL. `BIONIC_LIB_WANT` names every file the four
# functions between them source — the union of the four hooks' lists plus fold.sh
# and stop.sh — so a partial library fails the loader's readability check and this
# hook refuses rather than running three verdicts and dropping the fourth.
#
# FAIL CLOSED, ONCE: a stop refused on every re-entry because a file was missing is a turn
# nobody can end, so the refusal under the loader's stub lets the re-entry through.
#
# [WALL: tests/stop.test.sh]
#
# Registered in hooks/hooks.json: once on Stop, once on SubagentStop behind
# hooks/agent-context-guard.sh — the same wrapper landing-gate's SubagentStop
# registration carried, with the same reach.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

# ---------- the library ----------
#
# The stub below sources the one loader, whose stub and walk both live in
# payload/scripts/lib/loader.sh.
BIONIC_LIB_WANT="context.sh fill.sh fold.sh patrol.sh refuse.sh root.sh roster.sh run.sh session.sh stop.sh worktree.sh"
# Find the library through lib/loader.sh beside this hook; payload/scripts/lib/loader.sh says how.
_bl_dir="$(dirname "$0")"; _bl_l="$_bl_dir/../scripts/lib/loader.sh"; [ -r "$_bl_l" ] || _bl_l="$_bl_dir/../payload/scripts/lib/loader.sh"
# shellcheck source=/dev/null
if [ -r "$_bl_l" ]; then . "$_bl_l"; bionic_load; else
  BIONIC_LIB=""; BIONIC_LIB_MISSING="${BIONIC_LIB_WANT%% *}"; BIONIC_LIB_CANDS="$_bl_dir/../scripts/lib, $_bl_dir/../payload/scripts/lib"
  loader_fail_open() { echo "$1: library $BIONIC_LIB_MISSING not found at $BIONIC_LIB_CANDS — hook stepping aside; run /bionic:doctor" >&2; exit 0; }
  loader_fail_closed() { set -- "$1"; [ "${#1}" -le 25 ] || set -- "${1:0:24}…"; echo "bionic: load refused — $1 cannot load the bionic library (run /bionic:doctor)" >&2; exit 2; }
fi
# A MISSING LIBRARY REFUSES A STOP ONCE. Exit 2 holds the turn open, so only a first stop
# (`stop_hook_active` false) is refused; the re-entry, a payload without the field and one jq
# cannot read all end the turn, so a session with no library can still end or be repaired.
if [ -n "$BIONIC_LIB_MISSING" ]; then
  [ "$(jq -r '.stop_hook_active' 2>/dev/null)" = "false" ] || exit 0
  loader_fail_closed "stop"
fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/context.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/refuse.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/roster.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"
# THE ROW -> WORKTREE MAPPING (S18, AC-22), for stop_landing_gate's Files:
# reconciliation: `worktree_for_row` is the one place that convention lives.
# shellcheck source=/dev/null
. "$BIONIC_LIB/worktree.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/fold.sh"
# THE READY SET THE FILL DUTY REFUSES BY (epic-23 wave-18, REQ-3, D2; ADR-033 decision 2).
# `stop_patrol_duties` computes the rows a live ledger has ready rather than overhearing the
# tick's printed line, so a turn that ends on a fillable gap is refused whether or not a
# Patrol tick fired in it. Named in the WANT line above — and not merely sourced by
# payload/scripts/lib/stop.sh the way units.sh is — because the loader's readability check is
# what makes this process refuse rather than run three verdicts and drop the fourth.
# shellcheck source=/dev/null
. "$BIONIC_LIB/fill.sh"
# THE FILL LEDGER'S PATH AND THE PATROL VERDICT (epic-23 wave-20, REQ-5 and REQ-6).
# `stop_fill_ledger` appends to `fill_ledger_path`, the path `session-poker.sh fill-report`
# reads, and the death notice asks `patrol_verdict`; both live in patrol.sh. Wanted and
# sourced here for fill.sh's reason above: a partial library makes this process refuse.
# shellcheck source=/dev/null
. "$BIONIC_LIB/patrol.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/stop.sh"

# THE RUN VERDICT IS ASKED FOR (epic-23 wave-14 REQ-4, spec D5). `bionic_context`
# computes it only for a caller that sets this, because the plan scan behind it is
# the preamble's most expensive value and most hooks never read the answer. Three of the four
# verdict functions in `payload/scripts/lib/stop.sh` branch on it — `stop_context_spend`,
# `stop_patrol_duties`, `stop_patrol_revive` (:340, :1313, :1936).
BIONIC_CONTEXT_WANT_RUN=1

# THE EIGHT VALUES, ONCE (REQ-1h, lib/context.sh). All four functions read the root,
# the session key, the engagement answer and the run verdict out of this one call.
# Four hooks each spelling the cwd ladder their own way could attribute one session's
# stop to two different roots; one call cannot.
bionic_context 2>/dev/null || exit 0

# AN ABSENT FIELD IS PASSED ON AS THE EMPTY STRING, and what each function makes of it
# is the function's own business — not a rule this line imposes. Only `stop_context_spend`
# treats an absent event as Stop (`case "$_ev" in ''|Stop)`, payload/scripts/lib/stop.sh),
# which is the rule hooks/landing-gate.sh stated for its own `case` and the one that
# function keeps. The other three match `Stop` strictly, exactly as their hooks did before
# the merge, so a hand-run payload with no event field wakes the spend instrument and
# nothing else. Base-faithful in both directions; the comment claimed a uniformity the
# four never had. Read ABOVE the guard since wave-20, because the recorder below needs it.
EVENT=$(bionic_jq .hook_event_name)

# EVERY STOP IS RECORDED, THE RE-ENTRY INCLUDED (epic-23 wave-20 REQ-5, AC-5.5; Δ2). The fill
# ledger's recorder runs HERE, before the guard: after a refusal, the Stop that actually ends
# the turn carries `stop_hook_active` and runs nothing below — and it is the one that sees the
# launches the model made in answer to the refusal. A recorder, never a verdict: it prints
# nothing, refuses nothing and swallows its own failures, so this line cannot change what the
# guard or the fold decide. It also computes the turn's facts once for the fill duty below
# (`stop_turn_facts`), so the ledger line and the verdict are one computation. The refusal the
# CLI feeds back before that re-entry ("Stop hook feedback:") opens no turn there, so both of a
# refused turn's lines carry its prompt's key and `fill-report` counts them once (wave-20 T11b).
stop_fill_ledger "$EVENT" 2>/dev/null

# BLOCKS ONCE. (jq's `//` folds `false` to empty, so a literal "true" is the only
# value that can match here — which is the comparison we want anyway.) Nothing is
# verdicted on a re-entry: every row is still owed its one answer.
[ "$(bionic_jq .stop_hook_active)" = "true" ] && exit 0

bionic_fold "$EVENT" \
  stop_context_spend \
  stop_landing_gate \
  stop_patrol_duties \
  stop_patrol_revive
exit $?
