#!/bin/bash
# hooks/bash-walls.sh — ONE PROCESS ON PreToolUse|Bash (epic-23 wave-11-lean-spine,
# REQ-1f (v), AC-1f.5; ADR-004; user ruling A-50 "Option 3", 2026-09-12).
#
# Registered exactly once, on PreToolUse with matcher `Bash`. It reads the payload and
# the command, runs the five wall functions of payload/scripts/lib/walls.sh in the
# order the manifest listed them, and lets payload/scripts/lib/fold.sh compose whatever
# they say by one rule:
#
#     any block is a block · all reasons print · blocks before advisories
#
# WHAT THIS REPLACES. Five command objects fired on every Bash tool call —
# protect-main, protect-database, the canonical-sdlc evidence gate, farm-out-reminder
# and background-suite-guard — each
# with its own copy of this preamble, its own loader run and its own verdict, and NO
# rule for how five verdicts combine. Up to three of them could refuse one command; the
# platform collected whichever arrived. The functions are named below in the order that
# manifest listed them, so the reasons appear in the order the machine has always
# produced them.
#
# THE ORDER IS A CHOICE THIS FILE MAKES AND NOTHING ELSE DOES. `bionic_fold` runs what
# it is given, in the order it is given. The five are independent — none reads state
# another writes during one event — so the argument order below is about how a composed
# refusal READS, not about correctness. Every one of them always runs: a push that is
# also draws a farm-out nudge gets both answers.
#
# THE PAYLOAD AND THE COMMAND ARE READ BEFORE THE LIBRARY IS. Not for convenience: the
# repair matcher under the loader's stub needs the command text, and it has to be
# consulted BEFORE this wall decides to refuse — otherwise a broken publish locks the
# user out of the very commands that repair it. `jq` on the payload is the one read
# that does not need the library.
#
# ── FAIL-CLOSED, AND WHOSE REACH IT IS (T23 ruling R4) ───────────────────────
#
# The five disagree about a missing library, and they are right to: protect-main and
# the evidence gate stand over IRREVERSIBLE actions and refuse rather than wave a
# command through that they cannot read; the other three step aside, because what they
# prevent costs a re-run. In ONE process the loader either loads or it does not, so
# there is one arm and it is the union of the two closed ones — which is
# protect-main's, because protect-main's is unconditional. It guards a push in EVERY
# project on the machine, wave or no wave, so it carries no pre-check and refuses
# anything that is not one of the four repair commands, in any directory.
#
# THE EVIDENCE GATE'S NARROWER ARM IS GONE, AND HERE IS WHAT THAT DID AND DID NOT
# CHANGE. That wall answered the cheapest question a broken plugin still allows —
# could a run exist HERE, i.e. is there a real `.bionic` at or above the payload cwd —
# and stayed silent where the answer was no (the Step-6 critic's finding 1, 2026-09-03;
# tests/hook-adoption.test.sh §6b). Sharing a process with protect-main's unconditional
# arm, that walk can never be reached: protect-main refuses first, everywhere. What is
# unchanged is the direction and the REACH a user meets — with a broken library every
# Bash command in every project was already refused, by protect-main, and §6b's own
# differential control pinned exactly that. What changed is which wall's name appears
# in the line. The walk is deleted rather than kept unreachable, and the loss is named
# here rather than left for a reader to discover.
#
# THE ENGAGEMENT PREDICATE IS READ HERE, ONCE. All five walls asked the same question in
# identical words (Chris, 2026-09-03: "Nothing should apply until bionic is triggered");
# there is one guard now, ahead of all five, and BELOW the fail-closed arm — which cannot
# be scoped by it, because the predicate lives in the library that just failed to load.
# Only the seal's comparison runs ahead of it, because a changed run is refused whether or
# not its engaged file still stands.
#
# THE LIBRARY IS WANTED ONLY AS WIDE AS THE FAIL-CLOSED ARM REACHES (A-56.1).
# `BIONIC_LIB_WANT` is the union of the two CLOSED walls' pre-fold lists — protect-main's
# and the evidence gate's, readable back at `git show 60c528b:hooks/protect-main.sh` and
# `git show 60c528b:hooks/canonical-sdlc-evidence-gate.sh` — plus fold.sh and walls.sh,
# which are not a wall's ask but the two files this compound is MADE of: a fail-closed
# wall that cannot be called has not been consulted, and a compound that cannot compose
# has no verdict to give.
#
# WHAT IT DELIBERATELY OMITS, AND WHY. Folding five WANT lines into one made this the
# UNION of five, and a union is fail-closed at its widest member: `cmd-class.sh` absent
# refused EVERY Bash command in every project on the machine, where before it only made
# farm-out-reminder and background-suite-guard step aside. R4 puts fail-closed per WALL,
# not per compound, so a library only an advisory wall needs is sourced by that wall's
# own function in payload/scripts/lib/walls.sh (`wall_libs`), and that wall steps aside
# naming the file, in the words its hook used. The declaration lives beside the
# functions, in walls.sh's per-wall table, which doctor reads for the same reason.
#
# [WALL: tests/bash-walls.test.sh]
#
# Registered in hooks/hooks.json: once on PreToolUse, matcher `Bash`.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

BIONIC_INPUT=$(cat) || exit 0
[ -n "$BIONIC_INPUT" ] || exit 0
# `// empty` IS THE SPELLING FOUR OF THE FIVE USED. protect-main's own read had no
# fallback and turned an absent field into the literal `null`; neither value is one of
# the four repair commands and neither parses as a push, so the arm it feeds answers
# the same way and the empty string is the honest one.
COMMAND=$(printf '%s' "$BIONIC_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# ---------- the library ----------
#
# The stub below sources the one loader, whose stub and walk both live in
# payload/scripts/lib/loader.sh.
BIONIC_LIB_WANT="context.sh fold.sh git-argv.sh refuse.sh root.sh run.sh session.sh units.sh walls.sh"
# Find the library through lib/loader.sh beside this hook; payload/scripts/lib/loader.sh says how.
_bl_dir="$(dirname "$0")"; _bl_l="$_bl_dir/../scripts/lib/loader.sh"; [ -r "$_bl_l" ] || _bl_l="$_bl_dir/../payload/scripts/lib/loader.sh"
# shellcheck source=/dev/null
if [ -r "$_bl_l" ]; then . "$_bl_l"; bionic_load; else
  BIONIC_LIB=""; BIONIC_LIB_MISSING="${BIONIC_LIB_WANT%% *}"; BIONIC_LIB_CANDS="$_bl_dir/../scripts/lib, $_bl_dir/../payload/scripts/lib"
  loader_fail_open() { echo "$1: library $BIONIC_LIB_MISSING not found at $BIONIC_LIB_CANDS — hook stepping aside; run /bionic:doctor" >&2; exit 0; }
  loader_fail_closed() { set -- "$1"; [ "${#1}" -le 25 ] || set -- "${1:0:24}…"; echo "bionic: load refused — $1 cannot load the bionic library (run /bionic:doctor)" >&2; exit 2; }
fi
if [ -n "$BIONIC_LIB_MISSING" ]; then
  # The four commands that mend an install that cannot load pass, each matched as a whole string, so one
  # with another command chained after it is refused like any other; no variable widens them, since a
  # turn can set one on itself. They live here because this file is what runs when the loader is gone.
  _bw_root="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)" || _bw_root="$(dirname "$0")/.."
  case "$COMMAND" in
    "claude plugin update bionic@bionic"|"claude plugin install bionic@bionic"|\
    "bash $_bw_root/scripts/doctor.sh"|"bash $_bw_root/scripts/setup.sh") exit 0 ;;
  esac
  loader_fail_closed "bash-walls"
fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/context.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/git-argv.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/refuse.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"
# THE ONE READER OF `## Tasks` (REQ-1e, spec §2 D3), for the evidence gate's ledger
# and prototype-row arms.
# shellcheck source=/dev/null
. "$BIONIC_LIB/units.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/fold.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/walls.sh"

# THE EIGHT VALUES, ONCE (REQ-1h, lib/context.sh). All five functions read the root,
# the session key, the engagement answer and the run verdict out of this one call — and
# it ADOPTS the BIONIC_INPUT already read above rather than reaching for a stdin that is
# spent. Five hooks each spelling the cwd ladder their own way could attribute one
# session's command to two different roots; one call cannot.
bionic_context 2>/dev/null || exit 0

# THE PLAN THIS SESSION IS BOUND TO, read once: lib/run.sh `session_plan`, which believes the
# binding record kept beside the seals over the engaged file, and reads that file only for a
# session with no record. A session not engaged resolves the record's home here, in this shell,
# so the later readers inherit it (an engaged one had it resolved by `bionic_context`).
[ "$BIONIC_ENGAGED" = 1 ] || { _run_seal && seal_binding_warm "$BIONIC_ROOT"; } >/dev/null 2>&1 || :
BIONIC_BOUND_PLAN="$(session_plan "$BIONIC_ROOT" "$BIONIC_SID" 2>/dev/null)" || BIONIC_BOUND_PLAN=""

# THE PERSON'S ASKS A WALL HANDED BACK, OPENED HERE. A refusal that asks the person for a waiver (a failing question,
# a matrix row only they can let go) or a ruling on a changed run comes back from its wall beside its words, one
# `<key> TAB <title> TAB <reply>` line each in BIONIC_WALL_OWED; the wall itself writes nothing (the freeze), so its
# caller opens the items on the person's ledger (lib/owed.sh), keyed as the answer verb closes them. Opening is
# idempotent per key. owed.sh is not in BIONIC_LIB_WANT and is sourced only when there is an ask. The ledger is the run's register: the session's bound plan names it, or `OWED_PLAN` from a caller
# that drives this wall for a plan under a stand-in session (close-out.sh `gate_ask`), passed through as it came.
# A plan verb's dry commit (`planverb-<pid>`, hooks/session-poker.sh `plan_verb_dry`) is a synthetic session whose
# ledger nobody reads: its refusal is printed to the verb's caller, and the real commit opens the item.
bw_open_asks() {
  [ -n "$BIONIC_WALL_OWED" ] || return 0
  case "$BIONIC_SID" in planverb-*) return 0 ;; esac
  { declare -F owed_open >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/owed.sh" ] && . "$BIONIC_LIB/owed.sh"; }; } 2>/dev/null || return 0
  while IFS=$'\t' read -r _bw_key _bw_title _bw_reply; do
    [ -n "$_bw_key" ] || continue
    OWED_ROOT="$BIONIC_ROOT" OWED_SID="$BIONIC_SID" OWED_PLAN="${OWED_PLAN:-}" owed_open "$_bw_key" "$_bw_title" "$_bw_reply" >/dev/null 2>&1
  done <<< "$BIONIC_WALL_OWED"
}

# THE SEAL, FIRST. A commit of a bound run is compared with that run's seal before the
# engagement test and before any costly read: the collector below derives readings and the
# gate folds the log, and a hook that runs past its ten seconds admits the commit, so a run
# changed around the tool is refused here or not at all. It costs one digest of the plan and
# one of the log. On a change the seal's wall alone is folded, and nothing after it runs. A
# commit placed in another repository is not this run's, as the gate itself judges it. A
# session with no seal standing (a run the appender has not sealed yet) is not compared.
BIONIC_SEAL_LINE=""; BIONIC_SEAL_PLAN=""; BIONIC_SEAL_LOG=""; SEAL_LINE=""; SEAL_LOG=""
case "$COMMAND" in
  *commit*)
    # A plan this process cannot read has no digest to take, and that is not a change: the gate
    # refuses it in its own words, naming what cannot be opened.
    if [ -n "$BIONIC_BOUND_PLAN" ] && ! plan_unreadable "$BIONIC_BOUND_PLAN" >/dev/null \
       && git_argv_has_sub "$COMMAND" commit && ! eg_commit_outside_root && _run_seal; then
      seal_verify "$BIONIC_BOUND_PLAN" >/dev/null 2>&1
    fi ;;
esac
case "$SEAL_LINE" in
  changed*|busy)
    BIONIC_SEAL_LINE="$SEAL_LINE"; BIONIC_SEAL_PLAN="$BIONIC_BOUND_PLAN"; BIONIC_SEAL_LOG="$SEAL_LOG"
    EVENT=$(bionic_jq .hook_event_name); [ -n "$EVENT" ] || EVENT="PreToolUse"
    bionic_fold "$EVENT" wall_run_seal; _bw_rc=$?
    # The catch is kept in the seal before the ask is written, so the ask's own line, which the appender cannot
    # seal for a plan that is gone, never reads later as the log added to, and a plan put back reads changed.
    case "$SEAL_LINE" in changed*) seal_write "$BIONIC_SEAL_PLAN" "$BIONIC_SEAL_LOG" >/dev/null 2>&1 ;; esac
    bw_open_asks
    exit $_bw_rc ;;
esac

# THE ENGAGEMENT GUARD, asked once for all five. EVERY UNREADABLE STATE READS AS NOT
# ENGAGED — absent marker, a symlink at the path, a foreign or unshaped session key, no key
# at all — and the fail direction is inverted here on purpose: a session that never invoked
# the skill never consented, and no wall binds it. But consent is given once, by binding, not
# held by the engaged file: under D3 a session the binding record holds to a plan stays judged
# whatever became of that file, since a tool can remove it or replace it with a link, and a
# guard that let that lift every wall would make the file a switch any command can throw. So
# such a session is judged as engaged, by every wall below. A record of `none`, or no record,
# leaves the file the one answer, as before.
[ "$BIONIC_ENGAGED" = 1 ] || [ -n "$BIONIC_BOUND_PLAN" ] || exit 0
BIONIC_ENGAGED=1

# AN ABSENT FIELD IS NOT A MISMATCH, so a hand-run payload still reaches the walls — the
# rule hooks/stop.sh states for its own event. The event is handed to every function and
# to the fold, which renders `hookSpecificOutput` on it; this hook is registered on one
# event only, so an absent field reads as that one rather than as an empty channel name.
EVENT=$(bionic_jq .hook_event_name)
[ -n "$EVENT" ] || EVENT="PreToolUse"

# THE MEMORY STORE'S TWO FACTS, gathered for `wall_memory_store` (wave-24-fixit-1811 T12;
# REQ-3, D16). A sixth wall, after the manifest's five, and a pure predicate over what this
# block hands it — the store root and the command's write targets — per the freeze.
#
# THE SCREEN IS THE WORD `memory`, in the command, its quote-free strip (T4's `_wall_screen`
# cache, shared with every screen in this process) or the payload cwd. A store path always
# carries it; a command whose text, strip and cwd all lack it cannot name a store target
# except through a glob or a variable the text does not pin, which `cmd_write_targets` could
# not resolve either. A miss costs no fork and loads nothing.
#
# cmd-class.sh IS NOT IN THIS HOOK'S BIONIC_LIB_WANT (A-56.1: a union is fail-closed at its
# widest member), so a hit loads it the way an advisory wall does: `wall_libs`, which steps
# aside naming the file when it is missing, and then this wall has nothing to judge.
BIONIC_MEM_PROJECTS=""; BIONIC_WRITE_TARGETS=""; _bw_mem=0
case "$COMMAND$BIONIC_CWD" in *memory*) _bw_mem=1 ;; esac
if [ "$_bw_mem" = 0 ]; then
  _wall_screen "$COMMAND"
  case "$_WALL_STRIPPED" in *memory*) _bw_mem=1 ;; esac
fi
if [ "$_bw_mem" = 1 ] && wall_libs memory-store cmd-class.sh; then
  BIONIC_WRITE_TARGETS=$(cmd_write_targets "$COMMAND" "$BIONIC_CWD")
  _bw_ch="${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}}"
  case "$_bw_ch" in
    '~'|'~/'*)             _bw_ch="${HOME:-}${_bw_ch#\~}" ;;
    '$HOME'|'$HOME/'*)     _bw_ch="${HOME:-}${_bw_ch#\$HOME}" ;;
    '${HOME}'|'${HOME}/'*) _bw_ch="${HOME:-}${_bw_ch#\$\{HOME\}}" ;;
  esac
  case "$_bw_ch" in */) _bw_ch="${_bw_ch%/}" ;; esac
  BIONIC_MEM_PROJECTS="$_bw_ch/projects"
fi

# THE DECLARED DEBTS `land` WROTE, gathered for the evidence gate (wave-27 T67; A-orch-121). From
# Step 6 the gate holds a commit while a debt is open, and a wall reads only what it is handed: so
# this block reads the landing record of the plan this session is bound to (lib/run.sh
# `session_plan`, the binding field the gate's own run verdict starts from; this hook asks for no
# run verdict) into ONE fact, its open debts as lib/proof.sh `proof_debts_read` prints them, beside
# the plan they belong to. The gate reads it only when that is the plan it judges. Only for a call
# that holds a commit (the word, no fork otherwise), so no other call pays for the read.
#
# JURISDICTION FIRST (T80; wave-19 AC-9.2). A commit that lands in another repository has no plan
# here, so the collector asks the gate's own predicate (lib/walls.sh `eg_commit_outside_root`)
# before it resolves anything, and for such a commit reads neither the binding nor any record.
# Nor for one placed outside that the gate refuses for the split (`_EG_JUR_UNPLACED`, wave-35 T4),
# nor for one whose move the placement reader cannot follow (`_EG_CWD_SRC` moving, wave-36 T25):
# those refusals read no plan either.
BIONIC_DEBTS_PLAN=""; BIONIC_DEBTS_ORIGIN=""; BIONIC_DEBTS_OPEN=""; BIONIC_READINGS=""
case "$COMMAND" in
  *commit*)
    if ! eg_commit_outside_root && [ -z "$_EG_JUR_UNPLACED" ] && [ "$_EG_CWD_SRC" != moving ]; then
      BIONIC_DEBTS_PLAN="$(session_plan "$BIONIC_ROOT" "$BIONIC_SID" 2>/dev/null)" || BIONIC_DEBTS_PLAN=""
      # A session is bound to the plan itself, so the plan whose landing record is read is the plan judged; lib/walls.sh
      # still reads this name in two places, and it is that plan.
      BIONIC_DEBTS_ORIGIN="$BIONIC_DEBTS_PLAN"
      # THE READINGS' RESULTS AS THE JUDGE DERIVES THEM (wave-28 T60; D33, AC-8.6; A-orch-161). A
      # reading re-rated by a `check:`, `deferred:` or `moved:` line is judged on its derived result,
      # which needs the record its findings are in; the gate reads no record, so the collector reads it
      # once, for the plan the gate judges, and hands the lines over beside `BIONIC_DEBTS_PLAN`
      # (lib/proof.sh `proof_readings_derived`; the gate's `_eg_reading_gaps` takes them only for that
      # plan). ONLY WHEN THE GATE READS THEM (T72): the gate reads the readings from the step
      # `eg_step_reads_readings` names, so a commit below it derives nothing, and the deriver itself
      # prints nothing for a plan with no line that binds a pass. The hook's clock is 10 s, past which
      # the walls fail open for the commit.
      if [ -n "$BIONIC_DEBTS_PLAN" ] && declare -F proof_readings_derived >/dev/null 2>&1 && eg_plan_reads_readings "$BIONIC_DEBTS_PLAN"; then
        BIONIC_READINGS="$(proof_readings_derived "$BIONIC_DEBTS_PLAN" "$BIONIC_ROOT" 2>/dev/null)" || BIONIC_READINGS=""
      fi
      if [ -n "$BIONIC_DEBTS_PLAN" ] && declare -F proof_debt_record >/dev/null 2>&1 \
         && _bw_rec="$(proof_debt_record "$BIONIC_DEBTS_PLAN" "$BIONIC_ROOT")"; then
        BIONIC_DEBTS_OPEN="$(proof_debts_read "$_bw_rec")"
      fi
    fi ;;
esac

# THE WRITER'S UNREAD RULINGS, gathered for `wall_ruling_unread` (wave-33 T10; REQ-1 AC-1.4, D1). A
# ruling the orchestrator recorded for a writer (`session-poker.sh rule`) is pushed with the writer's
# next tool result, and a push is seen, not necessarily obeyed (record/wave-33-workhorse/
# P1-additional-context.md); so no work lands against one unread. For a writer's call (the payload's
# `agent_id`, joined to its roster name by `roster_row_for_id`) that holds a `git commit` segment, this
# reads each ruling of that name not yet shown, in the one wording (lib/roster.sh
# `ruling_take_unread`), and marks it shown: the refusal the wall below then gives is the reading, so
# the retry passes. Only for such a call: any other call, and the orchestrator's, read nothing.
# roster.sh is not in this hook's BIONIC_LIB_WANT (A-56.1: a union is fail-closed at its widest
# member); a library dir without it gathers nothing, and the push still stands.
BIONIC_RULINGS_UNREAD=""; BIONIC_RULINGS_WRITER=""
case "$COMMAND" in
  *commit*)
    _bw_aid="$(bionic_jq .agent_id)"
    if [ -n "$_bw_aid" ] && git_argv_has_sub "$COMMAND" commit && [ -r "$BIONIC_LIB/roster.sh" ] \
       && { declare -F ruling_take_unread >/dev/null 2>&1 || . "$BIONIC_LIB/roster.sh"; } 2>/dev/null; then
      _bw_roster="$BIONIC_ROOT/.bionic/tmp/roster-${BIONIC_SID}.state"
      if _bw_row="$(roster_row_for_id "$_bw_roster" "$_bw_aid")"; then
        BIONIC_RULINGS_WRITER="$(printf '%s\n' "$_bw_row" | awk -F'|' '{ for (i = 2; i <= NF; i++) if (index($i, "name=") == 1) { print substr($i, 6); exit } }')"
        BIONIC_RULINGS_UNREAD="$(ruling_take_unread "$_bw_roster" "$BIONIC_RULINGS_WRITER" commit)"
      fi
    fi ;;
esac

# wall_ruling_unread — the writer's commit with a ruling unread is refused, carrying the ruling. The facts are gathered
# above (the freeze, .claude/rules/hook-authoring.md); the words and the decision are lib/roster.sh
# `ruling_unread_refusal`'s, defined only when the gathering loaded that library.
wall_ruling_unread() {  # <event> -> 0 nothing · 2 block
  declare -F ruling_unread_refusal >/dev/null 2>&1 || return 0
  ruling_unread_refusal "$BIONIC_RULINGS_WRITER" "$BIONIC_RULINGS_UNREAD"
}

# THE TWO FACTS OF AN ACKNOWLEDGEMENT, gathered for `wall_ruling_ack` (wave-34 T5; REQ-4 AC-4.3, D9 "1"). `ruling-ack
# <id>` marks a ruling read, and only the writer it is addressed to has read it: an ack from the main thread or from
# another writer would mark it shown while its writer never saw it (walk.md §8). The verb cannot see its caller, so
# for a call that runs the verb (`_wall_poker_contract_verb`'s argv, asked for this one verb) this reads the ruling's
# writer off the session's roster (lib/roster.sh `ruling_fold`) and the caller's roster name off the payload's
# `agent_id` (`roster_row_for_id`, empty for the main thread or an agent no row names), and counts the call's segments:
# the ack is admitted alone in one call. An id no ruling carries gathers nothing; the verb refuses it.
BIONIC_ACK_ID=""; BIONIC_ACK_WRITER=""; BIONIC_ACK_CALLER=""; BIONIC_ACK_AGENT=""; BIONIC_ACK_ALONE=0
case "$COMMAND" in
  *ruling-ack*)
    if _wall_poker_contract_verb "$COMMAND" ruling-ack && [ -r "$BIONIC_LIB/roster.sh" ] \
       && { declare -F ruling_fold >/dev/null 2>&1 || . "$BIONIC_LIB/roster.sh"; } 2>/dev/null; then
      BIONIC_ACK_ID="${_WALL_POKER_ARGS%%"$GIT_ARGV_US"*}"
      _bw_roster="$BIONIC_ROOT/.bionic/tmp/roster-${BIONIC_SID}.state"
      if [ -n "$BIONIC_ACK_ID" ]; then
        BIONIC_ACK_WRITER="$(ruling_fold "$_bw_roster" | awk -F"$RULING_US" -v id="$BIONIC_ACK_ID" '$1 == id { print $2; exit }')"
      fi
      BIONIC_ACK_AGENT="$(bionic_jq .agent_id)"
      if [ -n "$BIONIC_ACK_AGENT" ] && _bw_row="$(roster_row_for_id "$_bw_roster" "$BIONIC_ACK_AGENT")"; then
        BIONIC_ACK_CALLER="$(printf '%s\n' "$_bw_row" | awk -F'|' '{ for (i = 2; i <= NF; i++) if (index($i, "name=") == 1) { print substr($i, 6); exit } }')"
      fi
      _bw_n=0
      while IFS= read -r _bw_l; do [ -z "$_bw_l" ] || _bw_n=$((_bw_n + 1)); done <<< "$(git_argv_expand "$COMMAND")"
      [ "$_bw_n" -ne 1 ] || BIONIC_ACK_ALONE=1
    fi ;;
esac

# wall_ruling_ack — an acknowledgement from anyone but the ruling's writer, or not alone in its call, is refused naming
# the writer it needs, and the ruling stays unread. The facts are gathered above (the freeze); the words and the
# decision are lib/roster.sh `ruling_ack_refusal`'s, defined only when the gathering loaded that library.
wall_ruling_ack() {  # <event> -> 0 nothing · 2 block
  declare -F ruling_ack_refusal >/dev/null 2>&1 || return 0
  ruling_ack_refusal "$BIONIC_ACK_ID" "$BIONIC_ACK_WRITER" "$BIONIC_ACK_CALLER" "$BIONIC_ACK_AGENT" "$BIONIC_ACK_ALONE"
}

bionic_fold "$EVENT" \
  wall_protect_main \
  wall_protect_database \
  wall_evidence_gate \
  wall_farm_out_reminder \
  wall_background_suite_guard \
  wall_memory_store \
  wall_ruling_unread \
  wall_ruling_ack
_bw_rc=$?

bw_open_asks
exit $_bw_rc
