#!/bin/bash
# THE STOP GATE — epic-15 wave-01R, extended at wave-03 task 4/6. ONE
# registration, PreToolUse|TaskStop. A stop during an active wave is permitted
# only against an observation that is:
#
#   OURS      — this session's (D-1), and the STOPPER'S OWN look, not another
#               actor's borrowed one (D-3, task 4/6);
#   FRESH     — on both activity channels: the target's working log (D-1) and,
#               where the work contract named one, its progress artifact (D-6,
#               task 4/6);
#   SPENT     — one observation discharges exactly one stop (D-2).
#
# And it is a stop of an agent THIS SESSION LAUNCHED. A target the session roster
# does not record is refused when addressed by name and permitted when addressed
# by full agent id (AC-6, task 4/6) — a name is not an identity.
#
# Why a gate at all: a stop is irreversible, and the failure mode it guards is
# the orchestrator's own judgment lapsing mid-drift — so the guarantee cannot
# live in the orchestrator's context (design/orchestrator-subagent-coordination.md
# §3.1). The gate reads state and decides; it never judges. Every judgment
# belongs upstream, in the observation.
#
# THIS SCRIPT NO LONGER WRITES THE RECORDS IT SPENDS (task 4/4). It used to
# carry a second arm on PreToolUse|Bash that watched for hooks/stop-check.sh in a
# command line and recorded an observation from the command TEXT. That arm fired
# BEFORE the command ran, so it could never know whether one had — and it paid
# for that twice: once when its command-line grammar diverged from the producer's
# and the record named an agent nobody had examined (Step-6 review F-1), and once
# as the standing residual where a refused or mistyped invocation still left a
# consumable record (critic finding A). Recording now happens once, in
# hooks/execution-recorder.sh on PostToolUse, from the machine line the
# observation itself prints. There is exactly ONE writer of this state and this
# gate is purely its reader.
#
# FAIL DIRECTIONS (TDD §7, pinned by tests/stop-guard.test.sh):
#   - the gate is OPEN and SILENT before the active-wave verdict (an
#     unconfigured machine is not a stop decision);
#   - the gate is CLOSED and LOUD after it (irreversibility: the ambiguous case
#     is exactly what the wall exists for).
#
# Exit code 2 = block the tool call entirely in Claude Code hooks.
# [WALL: tests/stop-guard.test.sh]
#
# Registered in skills/canonical-sdlc/SKILL.md frontmatter; live only while that skill is armed.

set -uo pipefail

STATE_VERSION="v1"
# The session roster's schema token. Written by hooks/dispatch-preflight.sh at
# launch and completed by hooks/execution-recorder.sh at execution confirmation;
# read here, and by hooks/stop-check.sh, never written. A row this gate cannot
# read is a row it will not guess at — an unknown version simply does not match,
# which lands on the closed side.
ROSTER_VERSION="v1"
# The bound on this file's length lives with its WRITER, hooks/execution-recorder.sh
# — this gate only reads it, and a reader that also capped it would be a second
# opinion about how much evidence a session may hold.
# THIS SCRIPT'S OWN DIRECTORY, and therefore its siblings'. hooks/stop-check.sh and
# hooks/stop-orders.sh ship beside this gate, so `$0` resolves them identically in a repo
# checkout, in a bootstrap-installed ~/.claude/hooks/, and in an installed plugin payload.
# Deliberately NOT ${CLAUDE_PLUGIN_ROOT}: the harness runs this gate straight out of the
# repo, where no plugin is mounted and that variable does not exist. The fix lines below
# stay absolute — a refusal has to hand an operator something runnable from any cwd.
HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -n "$HOOK_DIR" ] || HOOK_DIR="$(dirname "$0")"
OBSERVE_CMD="bash ${HOOK_DIR}/stop-check.sh"
ORDER_CMD="bash ${HOOK_DIR}/stop-orders.sh order"
# HOW LONG A HUMAN'S STOP ORDER IS CURRENT. Duplicated as a literal from its WRITER,
# hooks/stop-orders.sh, and held to it by tests/cross-gate-agreement.test.sh §M, which
# places an order either side of this boundary and asks this gate about it. See the
# discharge block below for why an instruction gets a clock when evidence never does.
ORDER_TTL_SECONDS=1800

BIONIC_INPUT=$(cat)
_jq() { printf '%s' "$BIONIC_INPUT" | jq -r "$1 // empty" 2>/dev/null; }

TOOL_NAME=$(_jq '.tool_name')

# ---------- portable file facts ----------
# DELIBERATELY DUPLICATED from hooks/stop-check.sh, byte for byte. A shared
# library is rejected by design (TDD §9): a sourced file the installer misses is
# a silently inert wall. The copies are held together by the resolver agreement
# battery in tests/cross-gate-agreement.test.sh §C, which drives both copies —
# the observation's and this one — over one fixture world.
file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
file_size()  { stat -f %z "$1" 2>/dev/null || stat -c %s "$1" 2>/dev/null || echo 0; }

# RESOLUTION IS NO LONGER A DIRECTORY SCAN (wave-roster-lifecycle S6, D2/D2′). This file
# used to carry `scan_subagent_dirs` — a walk of `agent-*.meta.json` matching a typed
# reference against the filename's id or the file's `.name` — duplicated byte for byte into
# hooks/stop-check.sh. It answered "which agent is this" from RECORDS, and records outlive
# agents: after a `/clear` one agent's meta.json is filed under two session directories at
# once (proven on this machine, research-code-map §4.4), so a bare name went ambiguous while
# the agent was still running and its contract had landed. That is the reported defect.
#
# WHAT DECIDES NOW IS THIS SESSION'S ROSTER (T22). Between S6 and 1.7.1 it was
# `live_agents_has` — the newest recorded ListAgents answer — which fixed the double-file
# defect but bought a precondition with it: a stop taken before the turn's first ListAgents
# call was refused for want of a reading, and the model was told to go take one. The roster
# answers the same question from state the system already wrote, so the `/clear` defect stays
# fixed and the chore is gone (ADR-024, P-A). `adopted_subagent_dirs` went with the scan —
# the widening it performed was a way to resolve a predecessor's agents, and `adopt` now
# journals those rows onto this session's own roster, which is the same widening done once,
# in writing, by the verb whose job it is.
#
# The session's own subagent directory, from the payload's transcript_path.
# §2.5 of record/epic-15-kill-interception-experiment.md captures the layout
# verbatim: "<transcript-dir>/<session-id>/subagents/agent-<id>.jsonl". Scoping
# resolution to the CALLER'S session is exact rather than heuristic — a session
# can only stop its own tasks — and hooks/execution-recorder.sh scopes its writes
# the same way, so writer and reader agree by construction.
session_subagents_dir() {  # <transcript-path>
  local tr="$1"
  [ -n "$tr" ] || return 1
  case "$tr" in *.jsonl) : ;; *) return 1 ;; esac
  printf '%s/subagents\n' "${tr%.jsonl}"
}

# One field out of a versioned record, BY KEY. Never by position: the discarded
# run's fixed-field-order parser broke undiagnosably the moment a field was
# added (checklist A6), so an unknown extra field must be inert here.
record_field() {  # <record-line> <key>
  printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-
}

record_version() { printf '%s' "$1" | cut -d'|' -f1; }

_bionic_symlink_in_repo() {  # <repo> -> 0 iff $repo/.bionic resolves under this repo's own root
  # spawn-worktree.sh links every spawned tree's .bionic to the main checkout's so a wave
  # shares one plan tree. That one link is trusted when its target resolves INSIDE the
  # same repository — under the parent of the git common dir — which a hostile repo cannot
  # point at another repo's tree (Chris, 2026-08-23, epic-18 w3).
  local repo="$1" target common root
  target="$(cd "$repo/.bionic" 2>/dev/null && pwd -P)" || return 1
  common="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  root="$(cd "${common%/.git}" 2>/dev/null && pwd -P)" || return 1
  case "$target/" in "$root"/*) return 0 ;; *) return 1 ;; esac
}

state_paths() {  # <repo> -> echoes "<state-dir>|<state-file>"; nonzero if unsafe
  local repo="$1"
  # A hostile repo controls its own .bionic/ contents (TDD §8). A symlink at
  # any level lets a repo choose which file this gate reads its evidence out of —
  # the OPEN direction, which §8 forbids a repo from reaching. Refuse rather than
  # follow: this gate refuses the stop, which is the safe side. The one exception
  # is the spawned-worktree link, accepted only when it stays inside this repo.
  if [ -L "$repo/.bionic" ]; then
    _bionic_symlink_in_repo "$repo" || return 1
  fi
  [ -L "$repo/.bionic/tmp" ] && return 1
  local dir="$repo/.bionic/tmp"
  [ -L "$dir/stop-check.state" ] && return 1
  printf '%s|%s\n' "$dir" "$dir/stop-check.state"
}

# ============================================================
# THE GATE (PreToolUse|TaskStop).
# ============================================================

[ "$TOOL_NAME" = "TaskStop" ] || exit 0

# ---------- before the verdict: OPEN and SILENT ----------
# ---------- the library ----------
#
# One loader idiom, byte-identical in every hook (spec AC-16); its source of truth is
# payload/scripts/lib/loader.sh. FAIL OPEN: the stop verdict is advisory or repeatable, and a
# hook that refused because a file was missing would hold every turn in every session
# on the machine hostage to it.
BIONIC_LIB_WANT="context.sh refuse.sh root.sh run.sh session.sh"
# --- bionic-loader/v2 BEGIN
# Find the bionic library — pasted BYTE-IDENTICALLY into all 15 carriers, because a library
# cannot load itself. payload/scripts/lib/loader.sh owns this text and its header holds the
# long form; §N.1 of tests/cross-gate-agreement.test.sh pins and caps every copy, and
# tests/loader.test.sh drives the behaviour. BIONIC_LIB_WANT, set on the line above, names
# the basenames this hook sources; afterwards exactly one of BIONIC_LIB (a directory holding
# all of them) and BIONIC_LIB_MISSING is non-empty. CANDIDATES, each class reached only when
# the earlier one fails: (1) beside the hook in BOTH spellings, since `..` resolves after the
# payload/hooks symlink; (2) the marketplace source tree, read from the registry and never
# assumed; (3) the newest version in that marketplace's cache, by THREE-INTEGER compare —
# 1.10.0 beats 1.3.2, which a lexical sort gets backwards. (2) and (3) heal a partly damaged
# install, so one broken location cannot lock the user out of the repair (R-1 §(5)).
BIONIC_LIB=""; BIONIC_LIB_MISSING=""; BIONIC_LIB_CANDS=""
_bl_dir="$(dirname "$0")"; _bl_want="${BIONIC_LIB_WANT:-}"
_bl_try() {
  [ -n "${1:-}" ] || return 1
  if [ -z "$BIONIC_LIB_CANDS" ]; then BIONIC_LIB_CANDS="$1"; else BIONIC_LIB_CANDS="$BIONIC_LIB_CANDS, $1"; fi
  [ -d "$1" ] || return 1
  for _bl_f in $_bl_want; do [ -r "$1/$_bl_f" ] || return 1; done
  BIONIC_LIB="$1"
}
if ! _bl_try "$_bl_dir/../scripts/lib" && ! _bl_try "$_bl_dir/../payload/scripts/lib"; then
  _bl_pd="${BIONIC_PLUGINS_DIR:-${HOME:-/nonexistent}/.claude/plugins}"; _bl_mk=""
  if [ -r "$_bl_pd/installed_plugins.json" ]; then
    _bl_keys="$(jq -r '(.plugins // {}) | keys[] | select(startswith("bionic@"))' "$_bl_pd/installed_plugins.json" 2>/dev/null)"
    _bl_mk="${_bl_keys%%
*}"
    _bl_mk="${_bl_mk#bionic@}"
  fi
  if [ -n "$_bl_mk" ]; then
    _bl_src=""
    if [ -r "$_bl_pd/known_marketplaces.json" ]; then
      _bl_src="$(jq -r --arg mk "$_bl_mk" '.[$mk].source.path // empty' "$_bl_pd/known_marketplaces.json" 2>/dev/null)"
    fi
    if [ -n "$_bl_src" ]; then _bl_try "$_bl_src/payload/scripts/lib" || :; fi
    if [ -z "$BIONIC_LIB" ]; then
      _bl_best=""; _bl_bestk=""
      for _bl_v in "$_bl_pd/cache/$_bl_mk/bionic"/*; do
        [ -d "$_bl_v" ] || continue
        _bl_n="${_bl_v##*/}"
        case "$_bl_n" in ''|*[!0-9.]*) continue ;; esac
        _bl_x1=""; _bl_x2=""; _bl_x3=""
        IFS=. read -r _bl_x1 _bl_x2 _bl_x3 _bl_rest <<BIONIC_LOADER_VER
$_bl_n
BIONIC_LOADER_VER
        _bl_k="$(printf '%05d%05d%05d' "$((10#${_bl_x1:-0}))" "$((10#${_bl_x2:-0}))" "$((10#${_bl_x3:-0}))" 2>/dev/null)" || continue
        if [ -z "$_bl_bestk" ] || [ "$_bl_k" \> "$_bl_bestk" ]; then _bl_bestk="$_bl_k"; _bl_best="$_bl_n"; fi
      done
      if [ -n "$_bl_best" ]; then _bl_try "$_bl_pd/cache/$_bl_mk/bionic/$_bl_best/scripts/lib" || :; fi
    fi
  fi
fi
if [ -z "$BIONIC_LIB" ]; then
  BIONIC_LIB_MISSING="${_bl_want%% *}"
  [ -n "$BIONIC_LIB_MISSING" ] || BIONIC_LIB_MISSING="scripts/lib"
fi
loader_fail_open() {
  echo "$1: library ${BIONIC_LIB_MISSING:-the bionic library} not found at ${BIONIC_LIB_CANDS:-(no candidate)} — hook stepping aside; run /bionic:doctor" >&2
  exit 0
}
loader_fail_closed() {
  _bl_root="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)" || _bl_root=""
  [ -n "$_bl_root" ] || _bl_root="$(dirname "$0")/.."
  case "${2:-}" in
    "claude plugin update bionic@bionic"|\
    "claude plugin install bionic@bionic"|\
    "bash $_bl_root/scripts/doctor.sh"|\
    "bash $_bl_root/scripts/setup.sh") exit 0 ;;
  esac
  _bl_who="${1:-a bionic hook}"
  if [ "${#_bl_who}" -gt 25 ]; then _bl_who="${_bl_who:0:24}…"; fi
  printf 'bionic: load refused — %s cannot load the bionic library (run /bionic:doctor)\n' "$_bl_who" >&2
  if [ "${BIONIC_WALL_VERBOSE:-}" = "1" ]; then
    cat >&2 <<BIONIC_LOADER_REFUSE
A wall that cannot read a command refuses it rather than waving it through.

Wanted: ${BIONIC_LIB_MISSING:-the bionic library}
Looked in: ${BIONIC_LIB_CANDS:-(no candidate)}

Until the plugin is whole again this wall permits exactly four commands, each matched
as a whole string:

    claude plugin update bionic@bionic
    claude plugin install bionic@bionic
    bash $_bl_root/scripts/doctor.sh
    bash $_bl_root/scripts/setup.sh

Anything else is refused, including one of those four with another command chained
after it. Run one of them, or act from your own terminal.
BIONIC_LOADER_REFUSE
  fi
  exit 2
}
# --- bionic-loader/v2 END
if [ -n "$BIONIC_LIB_MISSING" ]; then loader_fail_open "stop-guard"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/context.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/refuse.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"
# THE LIVE-SET READER IS NOT SOURCED HERE ANY MORE (T22, AC-4.4). `agents.sh` was this
# gate's whole resolution rule between wave-roster-lifecycle S6 and 1.7.1; the roster is now,
# and a library a file does not read is a library it must not load — loading it would leave
# the next reader of this header believing the answer still decides something.

# THE ROOT (spec AC-10, lib/root.sh). `git rev-parse --show-toplevel` answered with the
# WORKTREE's own root, so a stop raised from a linked worktree looked for the roster
# under a tree the dispatch wall had never written one into — and this gate then passed
# every row in silence, exactly where a wave most needs it. `project_root` maps a linked
# worktree onto its main repository and walks for the nearest real `.bionic`, so the
# reader and the writer land on one address space.
bionic_context 2>/dev/null || exit 0
[ -d "$BIONIC_ROOT" ] || exit 0

# ---------- THE ENGAGEMENT SWITCH — asked before anything else ----------
#
# task-engaged-session: bionic's walls are the RUN's, not the repo's, and a run is entered
# by invoking canonical-sdlc. A session that never did is a bystander here and must not see
# a refusal, an advisory, or a state write from this hook. `engaged_session` (lib/run.sh) is
# true only for a REGULAR file at `.bionic/tmp/engaged-<sid>.state`; every unreadable state —
# absent, symlink, foreign sid, `unknown` — reads as NOT engaged. Silent, exit 0 — which is
# the OPPOSITE direction to everything below it in this file, and deliberately so: §7 makes
# this gate fail CLOSED on an ambiguous identity *inside* a run, while engagement is the
# question of whether there is a run to be inside at all (1.3.2 close-out ruling — the
# arming partition IS the consent boundary).
#
# THE KEY COMES FROM THE LIBRARY (design §1: env primary, payload witness), which is what
# the marker's writer uses, so the two spell one session one way. It is now the ONLY key
# this gate has: the raw payload read that used to sit ~70 lines below, building the
# roster filename out of a second, unguarded reading of the same field, is gone (REQ-1h,
# AC-1h.2). One source, so the roster path this gate reads is keyed by the session the
# engagement switch admitted — a clean environment value and a malformed payload value
# used to pass this switch and then address a file outside the state directory.
bionic_context 2>/dev/null || exit 0
[ "$BIONIC_ENGAGED" = 1 ] || exit 0

# ---------- THE RUN PREDICATE IS GONE — ENGAGEMENT SCOPES THIS HOOK (task-engaged-session) --
#
# It used to take the run predicate here — `PLAN=$(active_run <repo>)`, exit 0 on false —
# and nothing below ever consulted
# the value: every rule this gate applies — the addressing carve, the
# observation freshness, the human order — reads the roster and the observation record,
# never the plan.
# The plan answered WHETHER, which is now engagement's question and is answered above.
#
# WHY THIS HOOK MOVES WITH THE DISPATCH WALL RATHER THAN KEEPING A RUN GATE. The four
# members of the roster lifecycle — hooks/dispatch-preflight.sh writes an `intended` row,
# this family confirms it, the landing gate takes its verdict, the stop gate polices the
# stop — have to share one scope or the lifecycle splits: the dispatch wall runs for an
# engaged session with no plan yet (AC-23, a fresh run's Step 0 precedes its plan), and a
# recorder or a gate that stayed silent for want of a plan would leave rows nothing ever
# answers for. A landing contract also OUTLIVES the run that created it — engagement does
# not end when `current:` reaches 9 (plan §Lifecycle) — and a verdict owed on an agent this
# session launched is owed after the run closes too.

# ---------- after the verdict: CLOSED and LOUD ----------

RAW=$(_jq '.tool_input.task_id')

# THE ACTOR REQUESTING THIS STOP (D-3, task 4/6). A subagent-invoked payload
# carries a top-level `agent_id`; the orchestrator's does not (task 4/1 probe,
# assumption A resolved FULL). hooks/execution-recorder.sh renders the same field
# the same way into `observer=` — absence as the literal token `orchestrator`, so
# neither side ever has to decide what a blank means. One key, two payloads.
ACTOR=$(_jq '.agent_id')
[ -n "$ACTOR" ] || ACTOR="orchestrator"

# What the Fix line names. It stays RUNNABLE AS PRINTED (Step-6 review R2) on
# every path: a refusal that hands back a foreign target rewrites the TARGET to
# the unambiguous full id, and one that names an unlooked-at progress artifact
# appends the flag that looks at it. Both are still one pasteable command.
FIX_TARGET="${RAW:-<agent-name-or-id>}"
FIX_EXTRA=""

deny() {  # <fact> <fix> <reason line>...
  # THE FRAME KEEPS ITS PARAMETERS AND LOSES ITS VOICE (task 13, ruling D-1). It used
  # to print twelve fixed lines and then the caller's reasons, all to the one stream the
  # reader is interrupted on. Now the caller's FACT and FIX — the ruled wording, one row
  # per reason, s12-refusal-wording-draft.md §1 rows 15-36 — render as the single user
  # line, and everything the frame used to print becomes `detail`: the pasteable observe
  # command, the one-observation-one-stop rule, and the human-order route. The verb is
  # `stop` for all three Stop hooks (D-3); the fact discriminates the gate.
  local fact="$1" fix="$2"; shift 2
  local reasons="" line
  for line in "$@"; do reasons="${reasons}${line}
"; done
  refuse exit2 stop "$fact" "$fix" "${reasons}A stop needs a fresh observation of its target, and a wave is active.

Fix: ${OBSERVE_CMD} ${FIX_TARGET}${FIX_EXTRA}
     (pass each contracted deliverable path as a further argument)
Then read what it prints, and stop again if the evidence supports it.
One observation discharges exactly one stop (D-2), and it goes stale the
moment the target writes again (D-1).

If a human ordered this stop, it executes — record the order and stop again:
     ${ORDER_CMD} ${FIX_TARGET}
A stop the human performs themselves does not reach this gate at all."
}

[ -n "$RAW" ] || deny "this stop names no target" "name the agent to stop" "The stop names no target: tool_input.task_id is empty."

TRANSCRIPT=$(_jq '.transcript_path')
SUB=$(session_subagents_dir "$TRANSCRIPT") \
  || deny "this stop carries no transcript path" "run /bionic:doctor" "This stop request carries no usable transcript path, so its session's agents cannot be resolved."

# ---------- RESOLUTION AGAINST THE LIVE SET (D1′/D2′, AC-9…AC-11) ----------
#
# The state paths are taken FIRST, because resolution now reads the roster — for the agent
# id, and for the rosters an `@session-` alias is checked against. `state_paths` declines a
# symlinked state path, which is the same refusal it always made, one step earlier.
PATHS=$(state_paths "$BIONIC_ROOT") \
  || deny "the observation state path is a symlink" "remove that symlink" "The observation state path is a symlink; nothing here will read or write through it."
STATE_DIR="${PATHS%|*}"; STATE_FILE="${PATHS#*|}"

# THE TYPED REFERENCE, split. `TaskStop` hands this gate the operator's string as typed and
# resolves nothing for it (P5). Three spellings reach here: a bare name, that name with an
# `@session-<launcher>` alias suffix, and the transcript-form agent id.
BASE="${RAW%@*}"; [ -n "$BASE" ] || BASE="$RAW"
ALIAS_SUFFIX=""
case "$RAW" in *@*) ALIAS_SUFFIX="${RAW##*@}" ;; esac

# ONE WALK OF THIS SESSION'S ROSTER, BY BOTH KEYS. The roster is read before the live set
# because the transcript-form id is a spelling only it can translate: the harness's answer
# lists teammates by NAME, so an id has to become a name before the live set can be asked
# about it. Nothing here is a name-oracle — a row supplies an id for a name, never the fact
# that the agent exists, which is the whole of what D1′ moved.
ROSTER_FILE="$STATE_DIR/roster-${BIONIC_SID}.state"
ROW_BY_ID=""; ROW_BY_NAME=""; ROW_WITH_ID=""
# A ROSTER THIS GATE CANNOT READ IS NOT A LICENCE TO PASS (T22; delta review S1). The roster
# is repo-controlled state, and a symlink at its own path would let a repo choose which file
# answers the question this gate asks — the OPEN direction §8 forbids a repo from reaching.
# It is not read through, exactly as before; what changes is that the unreadability now has
# to be carried, because standing used to come from the live set and no longer can. An
# unreadable register gives the gate standing and leaves the id unestablished, which lands
# on the closed side with the fact named ("no agent id") rather than on a silent passthrough.
#
# A SYMLINK IS ONE WAY A REGISTER GOES UNREADABLE; A MODE IS ANOTHER. A file that EXISTS and
# this process cannot open — mode 000, or a hook running under a uid that is not the one that
# wrote it — yields the same nothing as a link refused on purpose, and the sentence above was
# only true of the first. Until T26 the second left ROW_BY_NAME empty
# and ROSTER_UNREADABLE empty, so EVERY bare-name stop of every agent this session dispatched
# took the passthrough, silently, announcing that the target "appears on no roster row". At
# c19c16e that hole was closed by accident (standing came from the live set); T22 made the
# register the only source of standing, which is what turned the accident into a licence.
#
# AN UNREADABLE PARENT IS NOT THIS PREDICATE'S CASE, AND DOES NOT NEED TO BE (T31; delta
# review S2). `[ -e ]` is a stat of the path, and a stat through a directory this process
# cannot search FAILS — so with `.bionic/tmp` at mode 000 the test below is false and
# ROSTER_UNREADABLE stays empty, exactly as if no roster existed. Nothing is lost by that:
# the engagement marker is a file in that same directory, so a gate that cannot read the
# directory has already DISARMED several screens above this one and never reaches the roster
# at all. The mode-000 directory is a silent pass by the arming partition's own rule, not by
# an oversight here, and a link refused on purpose and a file this uid cannot open are the
# whole of what the two lines below are for.
ROSTER_UNREADABLE=""
[ -L "$ROSTER_FILE" ] && ROSTER_UNREADABLE=1
[ -e "$ROSTER_FILE" ] && [ ! -r "$ROSTER_FILE" ] && ROSTER_UNREADABLE=1
# TWO ROWS CAN CARRY ONE AGENT. The dispatch writes the CONTRACT and the recorder writes the
# id one state later, so the last row of a name is the current statement about it while the
# id may sit on an earlier one. They are collected separately rather than picking one row and
# reading both facts off it: preferring the row WITH the id loses a contract recorded after
# it, and preferring the last row loses the id.
roster_walk() {  # <key-name>
  local key="$1" rline rid rname
  ROW_BY_ID=""; ROW_BY_NAME=""; ROW_WITH_ID=""
  [ -f "$ROSTER_FILE" ] || return 0
  [ -L "$ROSTER_FILE" ] && return 0
  # Not read, rather than read and failing: an unopenable file would put the shell's own
  # "Permission denied" on the gate's stderr, where every byte is a refusal a reader parses.
  [ -r "$ROSTER_FILE" ] || return 0
  while IFS= read -r rline; do
    case "$rline" in '#'*|'') continue ;; esac
    case "$rline" in "roster-state/${ROSTER_VERSION}|"*) : ;; *) continue ;; esac
    rid=$(record_field "$rline" agent_id)
    rname=$(record_field "$rline" name)
    # `confirmed` or `identified`, never `intended` (Step-6 review C-2): the id on an
    # unconfirmed row is a claim about a launch nothing has observed.
    case "$(record_field "$rline" status)" in
      confirmed|identified)
        [ -n "$rid" ] && [ "$rid" = "$key" ] && ROW_BY_ID="$rline"
        [ -n "$rid" ] && [ -n "$rname" ] && [ "$rname" = "$key" ] && ROW_WITH_ID="$rline"
        ;;
    esac
    [ -n "$rname" ] && [ "$rname" = "$key" ] && ROW_BY_NAME="$rline"
  done < "$ROSTER_FILE"
  return 0
}
roster_walk "$BASE"

# An id-shaped target becomes the name its row carries, and that name is what the live set is
# asked about. This keeps the by-id spelling working — it is unambiguous by construction,
# which is why it was the escape hatch — without giving it a second resolution path. The
# second walk is by that NAME, so the contract comes off the same row it would for a bare one.
#
# WHICH SPELLING THE OPERATOR TYPED IS A FACT THE SECOND WALK DESTROYS (T29). `roster_walk`
# clears all three ROW_ variables on entry, so after the re-walk `ROW_BY_ID` says nothing
# about the typed reference any more — and the ambiguity arm below turns on exactly that:
# an agent id names ONE row by construction and must keep resolving, which is the whole
# reason that arm can offer it as the fix.
TYPED_AS_ID=""
TYPED_ROW=""
if [ -n "$ROW_BY_ID" ]; then
  TYPED_AS_ID=1
  # AND THE ROW ITSELF IS KEPT, not just the fact that one was typed (T31; delta review D1).
  # The re-walk below is by NAME and clears all three ROW_ variables on entry, so the row the
  # operator actually named is gone the moment it has been translated — and on an ambiguous
  # roster the name no longer picks it back out.
  TYPED_ROW="$ROW_BY_ID"
  BASE=$(record_field "$ROW_BY_ID" name)
  roster_walk "$BASE"
fi

AGENT_NAME="$BASE"
ROSTER_ROW="$ROW_BY_NAME"
AGENT_ID=""
[ -n "$ROW_WITH_ID" ] && AGENT_ID=$(record_field "$ROW_WITH_ID" agent_id)

# AN AGENT ID RESOLVES TO THE ROW THAT CARRIES IT, NEVER TO THE LAST ROW OF ITS NAME (T31;
# delta review D1). `ROW_WITH_ID` is the last confirmed/identified row of the NAME, which is
# the right answer for a bare name — it is the current statement about an identity the
# register holds one of — and the wrong one for an id, which names ONE row by construction.
# With two live rows of one name, both ids used to land on whichever row is last: the
# observation channel, the contract row, the deliverable and progress paths and the working
# log all belonged to the other agent, so a look at one twin discharged a stop of the other.
# The arm below refuses an ambiguous NAME and prints the ids as the way out of it (§7 — a
# stop is irreversible), and this is what makes that way out arrive where it says it does.
#
# WITHIN ONE LIFECYCLE THIS CHANGES NOTHING, which is why it is an override and not a fourth
# walk. A lifecycle is `intended` (the dispatch's contract, no id yet) → `confirmed` →
# `identified` (hooks/execution-recorder.sh, both carrying the id), so the LAST row of a name
# with one lifecycle is the row with the id and `ROW_BY_NAME` and `TYPED_ROW` are the same
# line. They diverge only where a second lifecycle exists — which is the defect's whole
# domain.
if [ -n "$TYPED_ROW" ]; then
  ROSTER_ROW="$TYPED_ROW"
  AGENT_ID=$(record_field "$TYPED_ROW" agent_id)
fi

# THE ROSTER DECIDES (T22, A-orch-33; AC-4.4). This gate used to ask `live_agents_has` —
# the newest recorded ListAgents answer — whether exactly one live teammate answered to the
# typed name, and it refused when the answer was STALE or absent, when the name was in it
# twice, and when the name was not in it at all. Chris's ruling, 2026-09-14: the live set is
# IMMATERIAL to stopping. The gate only ever used it for two things — turning a bare name
# into an agent id, and refusing an ambiguity — and this session's roster answers both. The
# roster is the identity register: `hooks/dispatch-preflight.sh` opens a row per dispatch,
# `hooks/execution-recorder.sh` writes the id onto it at SubagentStart, `session-poker.sh
# adopt` journals a predecessor's rows onto it, and every one of those writes is a fact the
# system recorded for itself. No act is demanded of the model before this gate will judge
# (ADR-024, P-A), and there is no reading here that can be stale in a way the model has to
# repair.
#
# WHERE THE AMBIGUITY WENT — AND WHERE IT CAME BACK (T29). Most of it was never a property
# of stopping: it was the door standing open at dispatch, and a second DISPATCH under a live
# name is refused one event earlier now by the preflight's in-flight arm. What that door does
# not cover is the OTHER writer of live rows — `hooks/session-poker.sh`'s `adopt_write_row`,
# whose idempotence check is `agent_id` + `adopted_from` and never asks whether this session
# already carries a live row of that NAME. So the arm below counts the ambiguity on the
# register, after the resolution above rather than instead of it, and §7's cell is unchanged:
# a stop is irreversible, so the ambiguous case is what this gate is for.

# THE SHAPE CARVE (T4, AC-6, session-20260815-landing-cleanup). The live set only ever named
# AGENTS, so any OTHER kind of TaskStop target — chief among them a background bash task id
# (A-D4) — was absent from it forever, with no code path back to order_current() below: the
# deny() call is an unconditional `exit 2`, so the escape hatch this gate documents in its own
# header (a human's order executes) would be permanently unreachable for a target of that kind
# (step2-research-a1-a3.md §A3). The carve is by SHAPE, not by trying harder to resolve: refuse
# only a target wearing an AGENT-ADDRESS shape — `name@session-xxxx`, or the transcript form
# `a<hex>` / `a<name>-<16hex>` — since only those could ever have named an Agent-tool dispatch
# (A-D3: TaskStop on an unknown id already fails cleanly on the platform side and stops
# nothing). Anything else gets out of the way — logged once, so this is never a silent gate.
is_address_shaped() {  # <typed> -> 0 if it wears an agent-address shape
  local t="$1"
  case "$t" in *@session-*) return 0 ;; esac
  printf '%s' "$t" | grep -qE '^a[0-9a-f]+$' && return 0
  printf '%s' "$t" | grep -qE '^a.+-[0-9a-f]{16}$' && return 0
  return 1
}

# A BACKGROUND BASH TASK ID (D8, T5; A-D4 probe evidence: t1o3yxz7p, tvivnv41s, tlfh9woyt,
# t5triyxvo). It never gets an agent-*.meta.json and never opens a roster row — it names no
# Agent-tool dispatch at all, so it is the one shape that still gets out of this gate's way
# with no row of any kind (REQ-5). The leading `t` is load-bearing: it is what keeps this
# carve from ever widening to a bare name that merely happens to be short and lowercase.
is_bash_task_shaped() {  # <typed> -> 0 if it wears a background-bash-task-id shape
  printf '%s' "$1" | grep -qE '^t[a-z0-9]{8,}$'
}

# EVERY ROSTER IN THIS BIONIC_ROOT THAT CARRIES THIS NAME, as the addresses the platform's stop
# primitive takes. It is the one spelling this gate prints and the one it accepts (Section R),
# and it is built from the roster FILENAME because that is the session that wrote the row.
accepted_addresses() {  # -> "    <name>@session-xxxxxxxx" per launcher, newline separated
  local f b out=""
  for f in "$STATE_DIR"/roster-*.state; do
    [ -f "$f" ] || continue
    [ -L "$f" ] && continue
    grep -qF "|name=${BASE}|" "$f" || continue
    b="${f##*/roster-}"; b="${b%.state}"
    out="${out}    ${BASE}@session-$(printf '%s' "$b" | cut -c1-8)
"
  done
  printf '%s' "$out"
}

# STANDING IS TWO FACTS, either of which is enough, and NEITHER NEEDS A TRANSCRIPT (T22).
# A target wearing an AGENT-ADDRESS shape could only ever have named an Agent-tool dispatch.
# And a target this session's own roster carries a row for is one this session dispatched,
# whatever it is spelled like — which is what lets a BARE NAME be refused rather than waved
# through, and a bare name is the spelling the whole of B-2 is about.
#
# NOT OURS IS A REFUSAL NOW (D8, T5 — it was a passthrough through 1.7.1, and the doctrine
# always said the refusal would return). A target this gate has no standing over is, for
# every OTHER shape, still a stop this gate can name and decline: refusing it in one line
# beats waving it through silently, because the wave-through was never provable to have been
# a deliberate choice rather than a typo or a stray target. The one exception is a
# BACKGROUND BASH TASK ID (is_bash_task_shaped): it never carries agent metadata and never
# opens a roster row by construction, so it is not an Agent-tool dispatch at all and keeps
# the passthrough this gate always gave it — logged once, never silent. A roster this
# session cannot read is a THIRD, unrelated case: ROSTER_UNREADABLE grants standing above,
# so it never reaches this branch, and the escape hatch this gate's own header advertises (a
# human's order executes) is unaffected either way — deny() below still ends with it.
guard_has_standing() {
  is_address_shaped "$RAW" && return 0
  [ -n "$ROW_BY_NAME" ] && return 0
  [ -n "$ROSTER_UNREADABLE" ] && return 0
  return 1
}
if ! guard_has_standing; then
  if is_bash_task_shaped "$RAW"; then
    # STRUCTURAL, not remote-controlled (Step-6 review flag 2-B): reachable only when standing
    # is absent, and the `if` keeps that true regardless of what `deny()` does — which an
    # unconditional `exit 2` in another function forty lines away did not.
    echo "PASSTHROUGH: '${RAW}' wears a background-bash-task-id shape and carries no agent metadata — not an Agent-tool dispatch this gate has standing to guard. The stop proceeds." >&2
    exit 0
  fi
  deny "this target is on no roster row of this session" "name a rostered agent or id" \
       "Target '${RAW}' is on no roster row of this session and wears no agent-address or" \
       "background-bash-task-id shape, so this gate cannot tell which Agent-tool dispatch," \
       "if any, it names (REQ-5, D8)."
fi

# ---------- AMBIGUITY, COUNTED ON THE REGISTER (T29; §7 — CLOSED and loud) ----------
#
# THE QUESTION, IN THE REGISTER'S OWN TERMS. Two rows of one name are an ambiguity when BOTH
# are under an open contract — `intended`/`confirmed`/`identified` with no
# `landing-swept/v1|…|state=MET` marker closing them — and they carry DIFFERENT agent ids.
# That is one name, two live contracts, two processes, and a stop typed as that name would
# pick whichever row happens to be last. A stop is irreversible; it must not guess.
#
# THE ORDERING IS THE ANSWER, exactly as it is in the two roster walls that share the
# `latest-contract reading` (hooks/dispatch-preflight.sh, hooks/execution-recorder.sh; pinned
# byte-equal by tests/cross-gate-agreement.test.sh §LC). A MET marker closes the contract it
# was written for and NOTHING after it, so a name that landed and was dispatched again is not
# two identities — it is one, below the marker. This reading is NOT a third copy of that span:
# the two walls compute a per-NAME boolean ("is this name under an open contract"), and what
# is needed here is the per-ID SET underneath it, which the marker clears rather than latches.
# Same file, same rule, a different question — stated here so an editor of either can see it.
#
# NOT FOR AN AGENT ID. An id names exactly one row by construction, which is why it was the
# escape hatch before T22 and why it is the fix this refusal prints; refusing it would leave
# an ambiguous name with no spelling at all. Every OTHER spelling reaches here, the
# `@session-` alias included: the suffix names the session that LAUNCHED an agent, so it
# cannot separate two rows of one name on one session's own roster. That is the same
# direction the retired live-set arm took, for the same reason.
#
# AFTER STANDING, so a target this gate has no business guarding is never trapped by it, and
# BEFORE the alias clause, so an ambiguous alias is told which fault it has.
live_ids_of_name() {  # <name> -> the agent ids currently under an open contract, one per line
  local f="$ROSTER_FILE"
  [ -f "$f" ] || return 0
  [ -L "$f" ] && return 0
  [ -r "$f" ] || return 0
  awk -v want="$1" -v ver="$ROSTER_VERSION" '
    function kv(line, key,   i, n, parts) {
      n = split(line, parts, "|")
      for (i = 1; i <= n; i++) if (index(parts[i], key "=") == 1) return substr(parts[i], length(key) + 2)
      return ""
    }
    function live_status(st) { return (st == "intended" || st == "confirmed" || st == "identified") }
    # A MET MARKER FOR THIS NAME DISCHARGES EVERY ID ABOVE IT, and the generation counter is
    # how that is spelled without `delete arr` — which is not in the one-true-awk this
    # machine runs as /usr/bin/awk. Rows below the marker start a fresh set.
    index($0, "landing-swept/v1|") == 1 {
      if (kv($0, "name") == want && kv($0, "state") == "MET") { n = 0; gen++ }
      next
    }
    index($0, "roster-state/" ver "|") == 1 {
      if (kv($0, "name") != want) next
      if (!live_status(kv($0, "status"))) next
      id = kv($0, "agent_id")
      # An `intended` row carries no id yet — the recorder writes it one state later — and a
      # lifecycle (intended → confirmed → identified) is ONE identity, so ids are counted
      # DISTINCT. Neither an unidentified row nor a re-stated one is a second agent.
      if (id == "") next
      if ((gen SUBSEP id) in seen) next
      seen[gen SUBSEP id] = 1
      ids[++n] = id
      next
    }
    END { for (i = 1; i <= n; i++) print ids[i] }
  ' "$f" 2>/dev/null
  return 0
}

AMBIG_IDS=""
[ -z "$TYPED_AS_ID" ] && AMBIG_IDS=$(live_ids_of_name "$BASE")
AMBIG_N=0
[ -n "$AMBIG_IDS" ] && AMBIG_N=$(printf '%s\n' "$AMBIG_IDS" | grep -c .)
if [ "$AMBIG_N" -gt 1 ]; then
  deny "that name has more than one live row" "name the full agent id" \
       "Target '${RAW}' is ambiguous: ${AMBIG_N} rows of this session's roster are live for '${BASE}'." \
       "The agent ids they carry, each of which names exactly one of them:" \
       "$(printf '%s\n' "$AMBIG_IDS" | sed 's/^/    /')" \
       "A name is an identity here, and two open contracts are carrying this one. The" \
       "@session- alias cannot separate them: it names the session that LAUNCHED an agent," \
       "and this is that session's own roster. Stop the one you mean by its agent id above," \
       "or land the row that is finished — its landing-swept marker frees the name."
fi

# ---------- AC-11: `name@session-<launcher>` IS AN ALIAS, AND ONLY THAT ----------
#
# The suffix is the spelling the platform's stop primitive takes for a teammate and the only
# one an operator can actually type (field data 2026-08-11), so it has to be accepted. What it
# is NOT is a second way to resolve: the bare name has already resolved to exactly one live
# entry above, and this clause only asks whether the launcher the suffix names is one that
# launched something of that name. The check is the launcher's own roster file
# (`roster-<sid>*.state` carrying `|name=<base>|`) — an eight-character prefix is what the
# platform prints, so the filename is matched by prefix — or this session's own row, whose
# `teammate_id=` records the exact address `adopt` printed for a taken-over agent.
if [ -n "$ALIAS_SUFFIX" ]; then
  ROSTER_TEAMMATE=$(record_field "$ROSTER_ROW" teammate_id)
  ALIAS_OK=0
  if [ -n "$ROSTER_TEAMMATE" ] && [ "$RAW" = "$ROSTER_TEAMMATE" ]; then
    ALIAS_OK=1
  else
    case "$ALIAS_SUFFIX" in
      session-*)
        ALIAS_WANT="${ALIAS_SUFFIX#session-}"
        case "$ALIAS_WANT" in
          ''|*[!A-Za-z0-9-]*) : ;;
          *)
            for _af in "$STATE_DIR"/roster-"$ALIAS_WANT"*.state; do
              [ -f "$_af" ] || continue
              [ -L "$_af" ] && continue
              grep -qF "|name=${BASE}|" "$_af" || continue
              ALIAS_OK=1
              break
            done
            ;;
        esac
        ;;
    esac
  fi
  if [ "$ALIAS_OK" -eq 0 ]; then
    ACCEPTED=$(accepted_addresses)
    [ -n "$ACCEPTED" ] || ACCEPTED="    (no roster in this repo carries the name '${BASE}')
"
    deny "that alias is not accepted for this agent" "use the agent's own name" "Target '${RAW}' is not an accepted alias for '${BASE}'." \
         "An alias suffix names the session that LAUNCHED the agent, spelled" \
         "@session-<first eight of that session's id>, and it is checked against that" \
         "session's own roster: the roster named here does not carry a row for '${BASE}'." \
         "A suffix naming any other session is a guess wearing an identity's shape." \
         "The spellings this gate accepts for it are:" \
         "${ACCEPTED%
}"
  fi
fi

# ---------- WHERE THE WORKING LOG IS, once the target has resolved ----------
#
# The id and the session the log is filed under both come from the ROSTER ROW, which is the
# only record that ever knew them: the harness's answer lists names, and the directory scan
# that used to supply an id is what this task deleted. `adopted_from` names the session that
# LAUNCHED an agent this one took over after a `/clear` — the log stays filed there, and the
# row is where that fact was written down (session-poker.sh `adopt`).
AFROM=$(record_field "$ROSTER_ROW" adopted_from)
case "$AFROM" in *[!A-Za-z0-9-]*) AFROM="" ;; esac
if [ -n "$AFROM" ]; then
  LOG_DIR="${TRANSCRIPT%/*}/$AFROM/subagents"
else
  LOG_DIR="$SUB"
fi

# HOW THE OPERATOR ADDRESSES THIS AGENT, in a form the platform's stop primitive accepts
# (epic-16 wave-02 task S3, from field data 2026-08-11). The roster's recorded teammate
# address wins; the constructed form is the fallback, and it is built from the session that
# launched the agent, because that is the session the address names.
ROSTER_TEAMMATE=$(record_field "$ROSTER_ROW" teammate_id)
STOP_ADDRESS="$ROSTER_TEAMMATE"
if [ -z "$STOP_ADDRESS" ]; then
  STOP_ADDRESS="${AGENT_NAME}@session-$(printf '%s' "${AFROM:-$BIONIC_SID}" | cut -c1-8)"
fi

# ---------- epic-16 wave-02: FACTS DISCHARGE THE STOP (R2), ORDERS EXECUTE (R3) ----------
#
# The ceremony below was never the point. The point was that a stop not destroy work
# nobody had looked at — and when the contract has LANDED, the artifact on disk answers
# that better than any look can, because it cannot go stale and nobody has to remember to
# take it. Wave-01 built the reader for exactly this question and gave it no authority:
# `hooks/session-sweeper.sh verdict` is a stateless read of the disk, and this gate
# CONSUMES it rather than forming a second opinion, the same way hooks/landing-gate.sh
# does. A gate with its own copy of the predicate can disagree with the verb an
# orchestrator reads by hand, and the two answers would be given to different people about
# the same contract.
#
# WHAT DISCHARGES, and why each is a fact rather than a ritual:
#   an ORDER    — a human asked for this stop. Not evidence, and not a claim the work
#                 landed: an instruction, which this gate has no standing to argue with.
#                 It reports what is being given up and gets out of the way.
#   an ACK      — the orchestrator verified this agent's completion and made that durable.
#                 It is the ONLY thing that can close a row which declared no
#                 machine-visible artifact, which is the job it exists for. It arrives as
#                 `acked=` on the verdict's own line (epic-16 wave-02 S9): this gate used to
#                 open the sweeper's ledger through a private copy of a reader, one of three
#                 such copies in the fleet, and the verb it was already running for `state=`
#                 owns that file. One reader, one normalization of the name, one answer.
#   MET/WAIVED  — the contract landed, or was explicitly waived at dispatch.
#
# WHAT DOES NOT: a MET over a row that DECLARED NOTHING. The verb calls such a row MET
# correctly — it names nothing to hold the agent to — but that is an absence of a contract,
# not a landing, and discharging on it would open the gate for every contract-less
# dispatch on a fact nobody produced. AC-1 spells MET as "artifact delivered"; ack closes
# the rest. Nothing else changes: a live agent with an unmet contract meets the same arc
# it met before, which is what Sections 4–10 of the suite still pin.
#
# AND AN ACK FOR A NAME NO ROSTER ROW CARRIES no longer discharges anything here, which is
# the one behaviour S9's promotion moved. The ack verb records such a name with a warning
# and holds it "exempt the moment a row of that name appears" — the ack closes a ROW — and
# with the answer riding a per-row verdict line there is no row for it to ride. This gate
# was the only reader that had been closing on the bare name; the landing gate passes such a
# stop for an unrelated reason and the stand-down never sees one, so this is the reading all
# three now share. Pinned in the suite beside its paired positive.

SWEEPER="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/session-sweeper.sh"
ORDERS_FILE="$STATE_DIR/stop-orders-${BIONIC_SID}.state"

V_TAKEN=0; V_STATE=""; V_DETAIL=""; V_ACKED=""
take_verdict() {
  [ "$V_TAKEN" -eq 1 ] && return 0
  V_TAKEN=1
  [ -f "$SWEEPER" ] || return 0
  [ -n "$AGENT_NAME" ] || return 0
  # A NAME THAT CLEANS TO NOTHING WIDENS THE VERB, exactly as it does at the landing gate
  # (Step-6 critic F-1): the verdict scopes on the sweeper's clean() of this value, and a
  # name made only of the characters it folds scopes to the EMPTY predicate — one line per
  # roster row, the first of which is some other agent's contract. Fold the same set and
  # decline to ask rather than ask the wrong question.
  case "$(printf '%s' "$AGENT_NAME" | tr -d '[:space:][:cntrl:]|')" in "") return 0 ;; esac
  local out line
  out=$( cd "$BIONIC_ROOT" 2>/dev/null || exit 9
         CLAUDE_CODE_SESSION_ID="$BIONIC_SID" bash "$SWEEPER" verdict "$AGENT_NAME" 2>/dev/null )
  line=$(printf '%s\n' "$out" | grep -F 'landing-verdict/v1|' | head -1)
  [ -n "$line" ] || return 0
  V_STATE=$(record_field "$line" state)
  V_DETAIL=$(record_field "$line" detail)
  V_ACKED=$(record_field "$line" acked)
  return 0
}

# A HUMAN'S ORDER, and the one clock in this gate that belongs. D-1 refuses to put a window
# on EVIDENCE, and that refusal stands: an observation is stale the moment its subject
# writes, however recent, and good however old while the subject is dormant. An INSTRUCTION
# is the other kind of thing — it is current when it is given and it stops being current,
# and a standing order would open this gate for a name some later dispatch reuses. The
# window is generous, the fail direction is the closed one (an expired order leaves the
# ceremony exactly where it was), and the writer is hooks/stop-orders.sh.
# WHO ORDERED IT, carried out of the read for the one line below (bionic 1.8.0, REQ-1 D1).
# The READING is unchanged — an order is an order, and this gate discharges a stop for
# either author at the same boundary — but since 1.8.0 an order can be written by the Patrol
# as well as by a person, and a reader owed "executing" is also owed "on whose word". Absent
# on a line written before 1.8.0, which reads back as the default the writer had then.
ORDER_BY=""
order_current() {
  local f="$ORDERS_FILE" line t e now delta
  ORDER_BY=""
  [ -L "$f" ] && return 1
  [ -f "$f" ] || return 1
  now=$(date -u +%s)
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "stop-order/v1|"*) : ;; *) continue ;; esac
    t=$(record_field "$line" target)
    [ -n "$t" ] || continue
    # The order may name what the operator typed, the agent's name, or its id: all three
    # are things a human says out loud, and an order that resolved to none of them would be
    # a wall built out of spelling.
    [ "$t" = "$RAW" ] || [ "$t" = "$AGENT_NAME" ] || [ "$t" = "$AGENT_ID" ] || continue
    e=$(record_field "$line" epoch)
    case "$e" in ''|*[!0-9]*) continue ;; esac
    delta=$((now - e))
    # A future-dated order is a skewed clock or a hand-edited file; a small tolerance
    # absorbs the first and nothing here honours the second indefinitely.
    if [ "$delta" -le "$ORDER_TTL_SECONDS" ] && [ "$delta" -ge -60 ]; then
      ORDER_BY=$(record_field "$line" by)
      case "$ORDER_BY" in human|patrol) : ;; *) ORDER_BY=human ;; esac
      return 0
    fi
  done < "$f"
  return 1
}

if order_current; then
  take_verdict
  # ONE LINE, and it is information rather than a verdict on the operator. R3: a
  # user-ordered stop executes at once; what an unmet contract earns is a sentence naming
  # what is being given up, never a refusal.
  if [ -z "$V_STATE" ]; then
    echo "STOP ORDERED (by ${ORDER_BY}) — executing. No contract row of this name is on the session roster." >&2
  elif [ "$V_STATE" = "MET" ] || [ "$V_STATE" = "WAIVED" ]; then
    echo "STOP ORDERED (by ${ORDER_BY}) — executing. Its contract stands ${V_STATE}: nothing is given up." >&2
  else
    echo "STOP ORDERED (by ${ORDER_BY}) — executing. Contract ${V_STATE}, giving up: ${V_DETAIL}" >&2
  fi
  exit 0
fi

take_verdict
[ "$V_ACKED" = "yes" ] && exit 0
case "$V_STATE" in
  WAIVED) exit 0 ;;
  MET)    [ -n "$(record_field "$ROSTER_ROW" deliverable)" ] && exit 0 ;;
esac

# ---------- THE OBSERVATION CHANNEL NEEDS AN AGENT ID, AND THE ROSTER OWNS IT ----------
#
# Placed AFTER the discharge set on purpose. An ack, a waiver and a landed contract are facts
# about the ROW, and a row can be discharged without anyone ever having resolved the agent's
# working log — which is the whole point of a landing (epic-16 wave-02 R2). What needs the id
# is the observation: the record is keyed on it, and the log it compares is
# `<session>/subagents/agent-<id>.jsonl`.
#
# Since the directory scan is gone, the roster row is the only thing that knows the id, and a
# `confirmed`/`identified` row is what carries it (an `intended` row's id is a claim about a
# launch nothing has observed — Step-6 review C-2). A live agent with no such row is refused
# rather than passed: it is inside a run, and §7 puts this gate on the CLOSED side of anything
# it cannot establish. The refusal names the missing fact instead of demanding a look that
# cannot be taken, and both other ways past this gate are printed beneath it as always.
if [ -z "$AGENT_ID" ]; then
  deny "the session roster carries no id for it" "stop it yourself or order it" "Target '${RAW}' is not on this session's register: the roster carries no agent id for '${AGENT_NAME}'." \
       "An observation is a look at a particular agent's working log, and the log is filed" \
       "under its agent id — which a dispatch records on its roster row when the agent starts" \
       "(status \`identified\`), and which nothing else in this repo knows. Without it there is" \
       "no evidence channel for this target, so there is nothing that could discharge the stop." \
       "If this agent was launched outside bionic's dispatch, stop it yourself or record an order."
fi

LOG="$LOG_DIR/agent-${AGENT_ID}.jsonl"

[ -f "$STATE_FILE" ] \
  || deny "no observation exists in this repo" "observe it with stop-check" "No observation has been recorded in this repo at all."

# Find this target's record. A record for the target under another session key
# or another schema version is reported for what it is — never guessed at.
RECORD=""; FOREIGN=""; BAD_VERSION=""
while IFS= read -r line; do
  case "$line" in '#'*|'') continue ;; esac
  [ "$(record_field "$line" target)" = "$AGENT_ID" ] || continue
  if [ "$(record_version "$line")" != "$STATE_VERSION" ]; then
    BAD_VERSION=$(record_version "$line"); continue
  fi
  if [ "$(record_field "$line" session)" != "$BIONIC_SID" ]; then
    FOREIGN=$(record_field "$line" session); continue
  fi
  RECORD="$line"
done < "$STATE_FILE"

if [ -z "$RECORD" ]; then
  [ -n "$BAD_VERSION" ] && deny "the observation record is unreadable" "observe it with stop-check" \
    "The only observation of '${RAW}' carries schema version '${BAD_VERSION}', which this gate does not read." \
    "A record it cannot read is a record it will not trust. Observe again."
  [ -n "$FOREIGN" ] && deny "that observation is another session's" "observe it with stop-check" \
    "The only observation of '${RAW}' was recorded by a different session (${FOREIGN})." \
    "Another session's look is not evidence that I looked."
  deny "this session has not observed it" "observe it with stop-check" "No observation of '${RAW}' (${AGENT_ID}) has been recorded by this session."
fi

# ---------- D-3: the look must be the STOPPER'S OWN (AC-4) ----------
#
# D-1 made an observation perishable. It never made one ATTRIBUTABLE: any record
# for the target discharged any actor's stop, so a subagent's look could pay for
# the orchestrator's stop and neither had seen what the other saw. Same session,
# so the session key above says nothing about it — the actor is a finer grain
# than the session, and it is the grain the judgment happens at, because the
# reader of the evidence is who decides.
#
# A record with no observer at all cannot prove this either way, and unprovable
# lands on the closed side (§7): the cost is one re-observation.
REC_OBSERVER=$(record_field "$RECORD" observer)
if [ -z "$REC_OBSERVER" ]; then
  deny "the observation records no observer" "observe it with stop-check" "The observation of '${RAW}' records no observer, so it cannot be shown to be yours." \
       "A look nobody signed is not evidence that YOU looked (D-3). Observe again."
fi
if [ "$REC_OBSERVER" != "$ACTOR" ]; then
  deny "another actor made that observation" "observe it yourself, then stop" "The observation of '${RAW}' was made by a different actor." \
       "    it was looked at by:  ${REC_OBSERVER}" \
       "    this stop comes from: ${ACTOR}" \
       "A look you did not take is not evidence that you looked (D-3): the reader of the" \
       "evidence is who decides, and that reader has to be you. Take your own look."
fi

# ---------- D-1: freshness by ACTIVITY BOUNDARY ----------
#
# An observation is a snapshot of the evidence tier; it stops being true the
# moment the evidence changes, and the working log says precisely when that is —
# the agent's next write. No clock window appears anywhere in this comparison:
# dormant since the observation is valid HOWEVER OLD, and one write after it is
# stale immediately. Any difference in the log counts, not only a later mtime —
# a rewritten or truncated log is a changed log.

REC_LOG=$(record_field "$RECORD" log)
REC_MTIME=$(record_field "$RECORD" mtime)
REC_SIZE=$(record_field "$RECORD" size)

NOW_MTIME=0; NOW_SIZE=0
if [ -f "$LOG" ]; then NOW_MTIME=$(file_mtime "$LOG"); NOW_SIZE=$(file_size "$LOG"); fi

if [ "$REC_LOG" != "$LOG" ]; then
  deny "the observation names another working log" "observe it with stop-check" "The observation of '${RAW}' recorded a different working log than the one that resolves now." \
       "Something about this target's identity changed since you looked."
fi

if [ "$NOW_MTIME" != "$REC_MTIME" ] || [ "$NOW_SIZE" != "$REC_SIZE" ]; then
  deny "it has written since your observation" "observe it again, then stop" "'${RAW}' has written to its working log SINCE your observation, so that observation is stale." \
       "(Any CHANGE counts, not only a later write: a truncated or rewritten log is a changed log.)" \
       "Its evidence tier now includes work you have not seen — which may be the very work a stop would destroy." \
       "This is an activity boundary, not a timer: an agent dormant since your look stays stoppable however long ago it was."
fi

# ---------- D-6: the contracted progress artifact is the SECOND activity channel (AC-5) ----------
#
# The comparison above watches one channel, and an agent that spends forty
# minutes inside a single tool call writes nothing to it. "Dormant since your
# look" is then true of a wedged agent and a working one alike — and the work
# contract's own progress artifact, the one thing that separates them, counted
# for nothing here. The rule is the log's rule, applied to the second channel:
# any activity after the look stales the look.
#
# THE PATH COMES OUT OF THE RECORD, not out of a second resolution. The
# observation already resolved it under the precedence task 4/5 fixed (an
# explicit --progress overrides the roster's row), and re-deriving it here would
# be a second parser answering the same question — the F-1 divergence class this
# wave closed elsewhere. What the roster is still consulted for is the one thing
# the record cannot say: that a contracted channel was never looked at at all.
#
# A relative path is resolved against the BIONIC_ROOT ROOT, which is where the contract
# is written from and where the observation runs; the resolved path is printed in
# the refusal so the comparison is never a hidden one.
REC_PROGRESS=$(record_field "$RECORD" progress)
REC_PMTIME=$(record_field "$RECORD" progress_mtime)
REC_PSTATE=$(record_field "$RECORD" progress_state)

abs_progress() {  # <path> -> absolute
  case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$BIONIC_ROOT" "$1" ;; esac
}

case "$REC_PSTATE" in
  present|absent)
    if [ -n "$REC_PROGRESS" ]; then
      PROG_ABS=$(abs_progress "$REC_PROGRESS")
      NOW_PSTATE="absent"; NOW_PMTIME=0
      if [ -e "$PROG_ABS" ]; then NOW_PSTATE="present"; NOW_PMTIME=$(file_mtime "$PROG_ABS"); fi
      if [ "$NOW_PSTATE" != "$REC_PSTATE" ] || [ "$NOW_PMTIME" != "$REC_PMTIME" ]; then
        deny "its progress artifact changed since you looked" "observe it again" "'${RAW}' has written to its contracted PROGRESS ARTIFACT since your observation," \
             "so that observation is stale." \
             "    artifact: ${PROG_ABS}" \
             "    at your look: ${REC_PSTATE} (mtime ${REC_PMTIME})   ·   now: ${NOW_PSTATE} (mtime ${NOW_PMTIME})" \
             "This is the second activity channel (D-6): a long-running command silences the" \
             "working log for its whole duration, and the progress artifact is what tells a" \
             "wedged agent from a working one. It is an activity boundary, not a timer."
      fi
    fi
    ;;
  *)
    # The look never opened a contracted channel. An artifact nobody looked at can
    # never go stale, so without this the check above is dodgeable by simply
    # looking wrong — which is the ordinary case whenever the observation ran
    # without its own session key and so never saw the roster at all.
    if [ -n "$ROSTER_ROW" ]; then
      ROSTER_PROGRESS=$(record_field "$ROSTER_ROW" progress)
      if [ -n "$ROSTER_PROGRESS" ]; then
        FIX_EXTRA=" --progress ${ROSTER_PROGRESS}"
        deny "your observation skipped the progress artifact" "observe with --progress" "The work contract for '${RAW}' names a progress artifact your observation never looked at." \
             "    contracted progress: ${ROSTER_PROGRESS}   (from this session's roster)" \
             "An observation that skips a contracted channel cannot be staled by it, so it is" \
             "not evidence about the work this stop would end (D-6). Look at it, then stop."
      fi
    fi
    ;;
esac

# ---------- D-2: consume on stop ----------
#
# One observation is evidence about one target at one moment. Letting the record
# ride for repeated stops re-admits staleness through the side door, so it is
# spent here, before the stop happens. A REFUSED stop consumes nothing: every
# path above exits without touching the file.

LOCK="$STATE_DIR/.stop-check.lock"
tries=0
reclaimed=0
# The wait is BOUNDED: one stale-lock reclaim, then a refusal. `mkdir` fails for
# reasons no reclaim can fix — an unwritable $STATE_DIR is repo-controlled — and
# `rm -rf` of an absent path succeeds, so an unbounded reclaim-and-retry loop
# never terminates and this gate would render no verdict at all (Step-6 review
# S2/A3). §7 gives this side its direction: after the active-wave verdict the
# stop gate is CLOSED and loud, so a wait that runs out refuses.
while ! mkdir "$LOCK" 2>/dev/null; do
  tries=$((tries + 1))
  if [ "$tries" -gt 20 ]; then
    if [ "$reclaimed" -eq 0 ] && [ -d "$LOCK" ]; then
      now=$(date -u +%s)
      if [ $((now - $(file_mtime "$LOCK"))) -gt 30 ]; then
        reclaimed=1; tries=0
        rm -rf "$LOCK" 2>/dev/null
        continue
      fi
    fi
    deny "the state lock is held, so nothing was consumed" "retry in a moment" "The observation record could not be consumed (the state lock at $STATE_DIR could not be taken), and an unconsumed record would discharge a second stop." \
         "Either another writer holds it, or this repo's .bionic/tmp is not writable by you."
  fi
  sleep 0.1 2>/dev/null || sleep 1
done

TMP=$(mktemp "$STATE_DIR/.stop-check.XXXXXX" 2>/dev/null) || {
  rm -rf "$LOCK"
  deny "no writable temp file, so nothing was consumed" "free space, then retry" "The observation record could not be consumed (no writable temp file), and an unconsumed record would discharge a second stop."
}
{
  printf '# bionic observation records — schema stop-check-state/%s\n' "$STATE_VERSION"
  while IFS= read -r line; do
    case "$line" in '#'*|'') continue ;; esac
    [ "$line" = "$RECORD" ] && continue
    printf '%s\n' "$line"
  done < "$STATE_FILE"
} > "$TMP" 2>/dev/null
# The rename is the third way the consume can fail, and it fails the same way as
# its two siblings above: CLOSED. Permitting the stop here would leave the record
# intact, and that one observation would then discharge every later stop of this
# target — D-2 broken at the only line that can break it (Step-6 review C3/A2).
mv -f "$TMP" "$STATE_FILE" 2>/dev/null || {
  rm -f "$TMP"
  rm -rf "$LOCK"
  deny "the state file could not be replaced" "retry in a moment" "The observation record could not be consumed (the state file could not be replaced), and an unconsumed record would discharge a second stop."
}
rm -rf "$LOCK"

exit 0
