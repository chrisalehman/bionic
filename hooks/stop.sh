#!/bin/bash
# hooks/stop.sh — ONE PROCESS AT TURN END (epic-23 wave-11-lean-spine, REQ-1f (iv);
# spec Design §1 "TurnEndVerdict", §2 D4; ADR-004).
#
# It answers three events, told apart by the event's name. Stop is the turn's end: it reads the
# event, runs the four verdict functions of payload/scripts/lib/stop.sh, and lets
# payload/scripts/lib/fold.sh compose whatever they say by one rule:
#
#     any block is a block · all reasons print · blocks before advisories
#
# SubagentStop is an agent's own stop: judged by the same four only in a session the stop library's
# `stop_agent_armed` calls armed, and silent for a payload with no `agent_id`. PreToolUse of TaskStop
# is the orchestrator's stop of an agent, judged by the library's `stop_guard`; any other tool's
# PreToolUse is not a stop and passes before anything is loaded.
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
# nobody can end, so the refusal under the loader's stub lets the re-entry through. The stop
# of an agent is refused every time: exit 2 there blocks only that tool call.
#
# [WALL: tests/stop.test.sh]
#
# Registered in hooks/hooks.json three times: on Stop, on PreToolUse TaskStop and on SubagentStop.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

# THE PAYLOAD IS READ FIRST, so the event is known before anything is loaded; `bionic_context`
# adopts this text rather than reading stdin again. A terminal on stdin is a hand run with no payload.
if [ -t 0 ]; then BIONIC_INPUT=""; else BIONIC_INPUT="$(cat)"; fi
_st_jq() { printf '%s' "$BIONIC_INPUT" | jq -r "$1 // empty" 2>/dev/null; }
EVENT=$(_st_jq .hook_event_name)
case "$EVENT" in
  PreToolUse)   [ "$(_st_jq .tool_name)" = "TaskStop" ] || exit 0 ;;
  SubagentStop) [ -n "$(_st_jq .agent_id)" ] || exit 0 ;;
esac

# ---------- the library ----------
#
# The stub below sources the one loader, whose stub and walk both live in
# payload/scripts/lib/loader.sh.
BIONIC_LIB_WANT="context.sh fill.sh fold.sh observe.sh patrol.sh refuse.sh root.sh roots.sh roster.sh run.sh session.sh stop.sh worktree.sh"
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
# The stop of an agent it cannot check is refused outright, as the TaskStop gate always was.
if [ -n "$BIONIC_LIB_MISSING" ]; then
  [ "$EVENT" = "PreToolUse" ] || [ "$(printf '%s' "$BIONIC_INPUT" | jq -r '.stop_hook_active' 2>/dev/null)" = "false" ] || exit 0
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
# THE PATROL VERDICT. The death notice asks `patrol_verdict`,
# which lives in patrol.sh. Wanted and sourced here for fill.sh's reason above: a partial
# library makes this process refuse.
# shellcheck source=/dev/null
. "$BIONIC_LIB/patrol.sh"
# The stop of an agent takes its own look at the target, through observe.sh and the roots it reads.
# shellcheck source=/dev/null
. "$BIONIC_LIB/roots.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/observe.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/stop.sh"

# THE RUN VERDICT IS ASKED FOR ON A TURN'S END. `bionic_context` computes it only for a caller that
# sets this, because the plan scan behind it is the preamble's most expensive value. Three of the four
# verdict functions branch on it; the stop of an agent never reads it.
[ "$EVENT" = "PreToolUse" ] || BIONIC_CONTEXT_WANT_RUN=1

# THE EIGHT VALUES, ONCE (lib/context.sh). Every function below reads the root, the session key,
# the engagement answer and the run verdict out of this one call.
bionic_context 2>/dev/null || exit 0

# The stop of an agent is the guard's whole answer, with this hook's directory for the scripts its fixes
# name. An agent's own stop goes on to the four only in an armed session.
case "$EVENT" in
  PreToolUse)   stop_guard "${_STOP_HOOK_DIR_ABS:-$_STOP_HOOK_DIR_RAW}"; exit $? ;;
  SubagentStop) stop_agent_armed || exit 0 ;;
esac

# AN ABSENT EVENT IS PASSED ON AS THE EMPTY STRING, and what each function makes of it is its own
# business: only `stop_context_spend` treats it as Stop.
#
# EVERY STOP IS RECORDED, THE RE-ENTRY INCLUDED. The recorder of the turn's
# `stop` event runs HERE, before the guard: after a refusal, the Stop that actually ends
# the turn carries `stop_hook_active` and runs nothing below — and it is the one that sees the
# launches the model made in answer to the refusal. A recorder, never a verdict: it prints
# nothing, refuses nothing and swallows its own failures, so this line cannot change what the
# guard or the fold decide. It also computes the turn's facts once for the fill duty below
# (`stop_turn_facts`), so the ledger line and the verdict are one computation. The refusal the
# CLI feeds back before that re-entry ("Stop hook feedback:") opens no turn there, so both of a
# refused turn's lines carry its prompt's key and the fold counts them once.
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
