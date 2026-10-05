#!/bin/bash
# THE EXECUTION-CONFIRMATION RECORDER — epic-15 wave-03, task 4/4.
#
# ONE script, THREE registrations, one job: write down what ACTUALLY RAN.
#
#   PostToolUse|Bash  — the PRESSURE arm, and nothing else since epic-23 wave-15. It
#                       used to copy hooks/stop-check.sh's machine line into an
#                       observation record a later stop spent; the stop gate takes its
#                       own look now (ADR-028, REQ-2) and that record is deleted.
#   PostToolUse|Agent — the ROSTER arm. When a dispatch has actually spawned, the
#                       session roster's `intended` row is completed with the
#                       full agent id and status `confirmed`; a launch whose name
#                       maps to a pending `## Tasks` row of the bound plan then sets
#                       that row `active` and adds its ledger line (wave-26 T12, D4).
#   SubagentStart     — the IDENTIFICATION arm (epic-16 wave-01; re-keyed in
#                       wave-03). When the agent itself starts, its TRANSCRIPT-form
#                       id is joined BY THAT ID onto the roster as an `identified`
#                       row; a teammate by its name, and a plain dispatch whose
#                       launch call has not returned by its TYPE (wave-27 T5), so a
#                       foreground agent has its budget from its first tool call.
#
# WHY POSTTOOLUSE IS THE WHOLE POINT. The facts this script records are claims that something
# HAPPENED, and a PreToolUse hook cannot make one: it fires before the tool runs and never
# learns whether it ran, succeeded, or was blocked further down the pipeline. Task 4/1's
# probe confirmed the harness never fires this event for a call it blocked pre-dispatch, so
# the gating is the platform's, not ours (record/w3-slice1-posttooluse-probe.md §5).
#
# IT NEVER BLOCKS — PostToolUse cannot: the tool has already run. Every failure
# path here therefore exits 0 having recorded nothing, and the cost lands where
# §7 puts it: an uncompleted roster row stays `intended`, which is
# exactly the signal that a dispatch never spawned.
#
# INERT OUTSIDE AN ACTIVE WAVE, like every other gate in this family, and inert
# in one cheap test before that: anything that is not this script's business
# leaves after a single fixed-string grep.
#
# [WALL: tests/execution-recorder.test.sh]
#
# Registered in skills/canonical-sdlc/SKILL.md frontmatter; live only while that skill is armed.

set -uo pipefail

# THE OBSERVATION CONSTANTS ARE GONE WITH THE ARM (epic-23 wave-15, REQ-2): the record's
# schema version, the cap on how many records it held, and the producer's machine-line token
# this script matched as a fixed string. payload/scripts/lib/observe.sh owns the token now,
# and nothing writes the record at all.
ROSTER_VERSION="v1"

BIONIC_INPUT=$(cat)
_jq() { printf '%s' "$BIONIC_INPUT" | jq -r "$1 // empty" 2>/dev/null; }

TOOL_NAME=$(_jq '.tool_name')
# THE THIRD ARM'S EVENT CARRIES NO TOOL NAME AT ALL (capture probe §3-C): a
# SubagentStart payload is six keys, none of them `tool_name`, so it cannot sit
# behind the gate the other two arms share. The hook-event read is deliberately
# INSIDE the fallthrough rather than beside the tool-name read: the two hot paths
# — every Bash call and every dispatch in the session — pay nothing for it, and a
# payload that is none of the three pays exactly one extra jq before leaving.
IS_START=""
case "$TOOL_NAME" in
  Bash|Agent) : ;;
  *) [ "$(_jq '.hook_event_name')" = "SubagentStart" ] || exit 0; IS_START=1 ;;
esac
# ONE REGISTRATION PER QUESTION (wave-27 T30). hooks/hooks.json registers this script on
# SubagentStart once bare (the terms, the join, every roster write) and once per reading question,
# the question its one argument. The argument means nothing on any other event, so a registration
# carrying one does no work there. See "ONE STRING PER FILE" in ARM 3.
START_QUESTION="${1-}"
[ -z "$START_QUESTION" ] || [ -n "$IS_START" ] || exit 0

# ---------- portable file facts ----------
# DELIBERATELY DUPLICATED from hooks/stop-check.sh and hooks/stop-guard.sh, byte
# for byte. A shared library is rejected by design (TDD §9): a sourced file the
# installer misses is a silently inert wall. The copies are held together by the
# agreement battery in tests/cross-gate-agreement.test.sh §C.
file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

# One field out of a versioned pipe-delimited line, BY KEY. Never by position —
# a fixed-field-order parser broke undiagnosably the moment a field was added
# (checklist A6), so an unknown extra field must be inert here. The same reader
# serves the machine line and the roster row, which is why both artifacts carry
# the same shape.
line_field() {  # <line> <key>
  printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-
}

# DELIBERATELY DUPLICATED from hooks/dispatch-preflight.sh's sanitize(), pipeline
# for pipeline, and for the same reason its comment gives: values are
# pipe-delimited on one line, so a `|` forges a field and a newline forges a row.
# This script checked for `|` alone until the Step-6 six-axis review (S-1) named
# the asymmetry — a newline in a platform id then aborted the completion awk
# outright and appended a blank line to the roster, and in the observation case
# split one record across two lines, the second of them still schema-shaped.
# Neither value is repo-supplied, so no §8 wall was open; what was open was one
# artifact family normalizing two different ways forty lines apart. Normalizing
# rather than refusing is the writer's rule too: the ledger records what it saw.
sanitize() {  # <value> <max-chars>
  printf '%s' "$1" \
    | tr '\n\r\t|' '    ' \
    | sed -e 's/[[:cntrl:]]/ /g' -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//' \
    | cut -c "1-$2"
}

# The session's own subagent directory, from the payload's transcript path.
# §2.5 of record/epic-15-kill-interception-experiment.md captures the layout
# verbatim: "<transcript-dir>/<session-id>/subagents/agent-<id>.jsonl".
session_subagents_dir() {  # <transcript-path>
  local tr="$1"
  [ -n "$tr" ] || return 1
  case "$tr" in *.jsonl) : ;; *) return 1 ;; esac
  printf '%s/subagents\n' "${tr%.jsonl}"
}

# ---------- relevance first (checklist A7) ----------
#
# This script is registered on EVERY Bash call and EVERY dispatch in the session,
# so the cheapest possible test comes before any git resolution or plan walk. For
# the observation arm that is one fixed-string grep over the tool's own stdout;
# for the roster arm it is the presence of the two payload fields the completion
# is made of. Everything expensive is below this line.

if [ -n "$IS_START" ]; then
  # THE ONE FIELD THE IDENTIFICATION IS MADE OF, and the whole of the cheap test
  # for this arm. It used to read `agent_type` beside it as "the teammate's
  # NAME" — measured wrong in wave-03: on a live Agent dispatch that field
  # carries the subagent TYPE (`general-purpose`), so every by-name join missed
  # and this arm was inert even when it did receive its event
  # (record/session-20260814-wave-detector-terminal-state/t4-probes-report.md
  # §5.1, t4b-probe-report.md §3). The payload has seven keys and only `agent_id`
  # can key a row: it is the TRANSCRIPT form, byte-identical to the
  # `tool_response.agentId` ARM 2 records at confirmation and to the
  # `background_tasks[].id` the landing sweep reads.
  #
  # AND THE FIELD THAT IDENTIFIES A TEAMMATE, re-read (session-20260815, T2).
  # `agent_type` is not one field with one meaning: measured on one live session it
  # carries `general-purpose` — the TYPE — for an async dispatch, and the dispatch
  # NAME for a named teammate (t1-probe-report.md §2.1). Wave-03 read the first
  # half and removed the join for cause; the second half is the ONLY identifying
  # field a teammate payload has, and without it a teammate row is never joinable
  # at all. The join below is therefore by id first and by this name second, over
  # rows whose status is `intended` or `confirmed` and whose session matches this
  # one — not scoped to rows the writer marked as teammates; that scope is gone
  # (see the name join further down, and Step-6 review flag 2-A).
  START_TYPE=$(_jq '.agent_type')
  START_ID=$(_jq '.agent_id')
  [ -n "$START_ID" ] || exit 0
elif [ "$TOOL_NAME" = "Bash" ]; then
  # A BASH CALL HAS NOTHING TO READ ANY MORE (REQ-2). This branch used to pull the tool's
  # whole stdout through jq and grep it for the observation's machine line, on EVERY Bash
  # call in the session, so that the line could become a record a later stop spent. The stop
  # gate takes its own look now and the record is deleted; what a Bash payload is still here
  # for is the pressure sample below, which is a fact about the call having happened. No
  # read, no grep, and the arm exits immediately after the sample.
  : 
  # THE RESIDUAL, stated rather than claimed away: stdout is not a trusted
  # channel — a command that PRINTS a well-formed machine line produces a record
  # without any observation having run. It is a strictly smaller residual than
  # the one it replaces (the predecessor recorded on any command line that merely
  # named a live agent, including refused ones), and it is not reachable by
  # mistake: forging one means typing the schema token, the resolved agent id and
  # that agent's current log mtime and size, all of which the gate re-checks
  # against the live file before it discharges anything.
  #
  # THE EARLY EXIT SITS IMMEDIATELY AFTER THE PRESSURE SAMPLE (wave-roster-lifecycle S9,
  # then Step-6 review P-2, then REQ-2). S9 needed a sample on every ENGAGED Bash call and
  # the engagement switch is below the loader, so the exit had to move below the sample
  # rather than stay above it. With the observation arm deleted the sample is the only
  # business a Bash payload has here, and the exit is unconditional.
else
  # TWO SPELLINGS, ONE FACT (AC-10). The dispatch modes name the same field
  # differently: an async task launch returns `tool_response.agentId` (camel),
  # and an interactive teammate spawn returns `tool_response.agent_id` (snake)
  # alongside `teammate_id`. This guard read the camel spelling ALONE, so every
  # dispatch from an interactive session — which is every dispatch this repo has
  # made since 07-12 — exited here, and no roster row on any live session ever
  # reached `confirmed` (record/landing-wave-payload-probe.md §Task 1). The
  # fixture that made the arm look proven was faithful to the OTHER mode: it came
  # from a `claude -p` child, and print mode can never take the teammate branch
  # (capture probe §1).
  AGENT_ID=$(_jq '.tool_response.agentId // .tool_response.agent_id')
  TOOL_USE_ID=$(_jq '.tool_use_id')
  # THE DISPATCH NAME, off the one payload that carries it beside the agent id
  # (t4b-probe-report.md §3: `tool_input.name` and `tool_response.agentId` arrive
  # together on this event and nowhere else). Recording it makes the completed row
  # self-sufficient for BOTH keys, so nothing downstream has to recover a name
  # from `agent_type` — the field that carries the subagent type. Absent on an
  # unnamed dispatch, in which case the launch row's own name stands.
  DISPATCH_NAME=$(_jq '.tool_input.name')
  # WHICH NAMESPACE the id above is in, decided by the platform's own word for
  # what it did rather than by sniffing the id's shape. Read here, spent below.
  DISPATCH_STATUS=$(_jq '.tool_response.status')
  TEAMMATE_ID=$(_jq '.tool_response.teammate_id // .tool_response.agent_id')
  [ -n "$AGENT_ID" ] && [ -n "$TOOL_USE_ID" ] || exit 0
fi

# ---------- the library ----------
#
# One loader idiom, byte-identical in every hook (spec AC-16); its source of truth is
# payload/scripts/lib/loader.sh. FAIL OPEN: the roster row is advisory or repeatable, and a
# hook that refused because a file was missing would hold every turn in every session
# on the machine hostage to it.
BIONIC_LIB_WANT="context.sh root.sh run.sh session.sh resources.sh roster.sh"
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
if [ -n "$BIONIC_LIB_MISSING" ]; then loader_fail_open "execution-recorder"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/context.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/resources.sh"
# THE ONE CLOSE PREDICATE (epic-23 wave-20 T20, REQ-10, D10): `roster_open_names`, asked by
# the duplicate-start check below. STILL WANTED HERE (so the loader's directory pick still
# requires it to exist beside the other five), but no longer sourced on this line — every
# Bash call and every dispatch confirmation in the session reaches this far, and parsing
# roster.sh's ~460 lines for a definition only the SubagentStart duplicate-start check ever
# calls cost every one of them (epic-23 wave-20 T20b, review R5's perf note: ~2ms/call
# measured on the Bash path, `.bionic/docs/record/wave-20-fixit-187/T20b-restart-reads-open.md`
# "Hook latency"). `roster_sh_load` below sources it exactly once, lazily, on the one path
# that ever needs `roster_open_names`. THE SOURCE LINE ITSELF IS UNINDENTED, deliberately —
# it is still the one literal `. "$BIONIC_LIB/roster.sh"` tests/hook-adoption.test.sh pins
# byte for byte, and the loop pinning "every wanted basename is sourced" reads it by that
# same literal regardless of which function body it sits in.
roster_sh_load() {
  [ -n "${_ROSTER_SH_LOADED:-}" ] && return 0
  _ROSTER_SH_LOADED=1
# shellcheck source=/dev/null
. "$BIONIC_LIB/roster.sh"
}

# THE ROOT (spec AC-10, lib/root.sh). `git rev-parse --show-toplevel` answered with the
# WORKTREE's own root, so a stop raised from a linked worktree looked for the roster
# under a tree the dispatch wall had never written one into — and this gate then passed
# every row in silence, exactly where a wave most needs it. `project_root` maps a linked
# worktree onto its main repository and walks for the nearest real `.bionic`, so the
# reader and the writer land on one address space.
# THE SESSION KEY comes back from the same call (design §1): env primary, payload
# witness, and SHAPE-CHECKED BEFORE IT BECOMES A PATH. The roster filename is built from
# it and this script APPENDS to that file; the symlink guards check `.bionic`, the state
# directory and the exact filenames, so a key carrying path separators does not trip a
# guard — it writes outside the directory the guards protect (Step-6 review S-4). That
# rule is `bionic_context`'s now, applied for all fifteen, so the writer and every reader
# spell one session one way by construction rather than by four hooks agreeing.
bionic_context 2>/dev/null || exit 0
[ -d "$BIONIC_ROOT" ] || exit 0

# ---------- THE ENGAGEMENT SWITCH — asked before anything else ----------
#
# task-engaged-session: bionic's walls are the RUN's, not the repo's, and a run is entered
# by invoking canonical-sdlc. A session that never did is a bystander here and must not see
# a refusal, an advisory, or a state write from this hook. `engaged_session` (lib/run.sh) is
# true only for a REGULAR file at `.bionic/tmp/engaged-<sid>.state`; every unreadable state —
# absent, symlink, foreign sid, `unknown` — reads as NOT engaged. Silent, exit 0: the
# direction §7 gives every start-side ambiguity, and here it is the consent boundary itself
# (1.3.2 close-out ruling — the arming partition IS the consent boundary).
[ "$BIONIC_ENGAGED" = 1 ] || exit 0

# ---------- THE PRESSURE SAMPLE (wave-roster-lifecycle S9, spec AC-15, R4) ----------
#
# One sample per engaged Bash call, appended to the ring resources.sh owns. The
# consumers sample (D3 amendment): plugin hooks were not observed firing inside
# subagents, so this arm cannot be the ONLY sampler — but it IS reliable for the
# orchestrator's own calls, which is what this gives the ring: frequent readings
# between the sparser ones tests/run.sh and the Patrol tick take. Bash-only —
# ARM 2 (a dispatch confirming) and ARM 3 (an agent starting) are not "time
# passed at the machine", and sampling on those too would count a dispatch
# twice against the calls that produced it. FAILURE-TOLERANT like every write in
# this file: a lost sample costs `pressure_level`'s median one input, never a
# hook failure, so its result is discarded and its failure swallowed.
if [ "$TOOL_NAME" = "Bash" ]; then
  pressure_sample >/dev/null 2>&1 || :
fi

# ---------- THE EARLY EXIT, NOW UNCONDITIONAL FOR BASH (Step-6 review P-2; REQ-2) ----------
#
# A Bash call has no arm below it any more — the observation record went with ADR-028 — so
# the sample above is the whole of this hook's business on that channel. It used to exit here
# only when the call had printed no machine line, which cost a jq pass over every tool
# response in the session; now nothing below this line runs for a Bash payload at all.
if [ -z "$IS_START" ] && [ "$TOOL_NAME" = "Bash" ]; then
  exit 0
fi

# ---------- THE RUN PREDICATE IS GONE — ENGAGEMENT SCOPES THIS HOOK (task-engaged-session) --
#
# It used to take the run predicate here — `PLAN=$(active_run <repo>)`, exit 0 on false —
# and nothing below ever consulted
# the value: this recorder journals that THIS SESSION launched an agent, a
# fact true before a plan exists and still true after the run closes.
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


# ---------- state paths ----------
#
# A hostile repo controls its own .bionic/ contents (TDD §8). A symlink at any
# level redirects our write outside the repo — the proven arbitrary-file-overwrite
# shape. Refuse rather than follow; refusing to RECORD only makes the later stop
# refuse, which is the safe direction.
STATE_DIR="$BIONIC_ROOT/.bionic/tmp"
ROSTER_FILE="$STATE_DIR/roster-${BIONIC_SID}.state"
[ -L "$BIONIC_ROOT/.bionic" ] && exit 0
[ -L "$STATE_DIR" ] && exit 0

# ONE LAUNCH REFERENCE PER AGENT ID, EVER (epic-16 wave-02 S6; AC-5; R6; spec
# domain model "Roster row": `launched_at` is immutable across resume). A
# resume carries the SAME transcript-form agent id an earlier row on this
# roster already wrote down, but reaches this script beside a FRESH
# `launched_at` — the field case shape is a new intended/confirmed cycle for
# the same id, stamped at resume time. Left alone, that fresh stamp lands on
# the row a later stop reads, and a deliverable authored BEFORE the resume —
# by orchestrator takeover, the documented case — reads as authored before
# nothing: its mtime predates a launch reference that moved out from under it
# (record/w1-rc-verify-floor.md §Amendment-2).
#
# KEYED BY AGENT ID, NOT NAME. A name dispatched twice in one session is two
# DIFFERENT agents — ARM 3's own join below exists for exactly that case, and
# each dispatch is entitled to its own launch reference — so this must never
# key on the field the join already uses. Only a repeat of the SAME agent id
# is a resume. The scan returns the EARLIEST `launched_at` this session's
# roster carries for that id: on a first sighting nothing matches yet (the
# caller's own row is the first), so the caller's own value survives
# untouched; on a resume it is the ORIGINAL dispatch's, however many fresher
# rows now carry the same id.
prior_launch_for_agent() {  # <agent-id> -> earliest launched_at for that id this session, or empty
  local aid="$1" line found=""
  [ -n "$aid" ] || return 0
  [ -f "$ROSTER_FILE" ] || return 0
  while IFS= read -r line; do
    case "$line" in '#'*|'') continue ;; esac
    case "$line" in "roster-state/${ROSTER_VERSION}|"*) : ;; *) continue ;; esac
    # Same prefilter discipline as ARM 2/ARM 3 below (Step-6 critic F-1): a
    # cheap in-shell superset match before the exact `line_field` reads, so an
    # unbounded roster does not pay four processes per row for a lookup that
    # matches at most a handful of rows.
    case "$line" in
      *"|agent_id=$aid"|*"|agent_id=$aid|"*) : ;;
      *) continue ;;
    esac
    [ "$(line_field "$line" agent_id)" = "$aid" ] || continue
    [ "$(line_field "$line" session)" = "$BIONIC_SID" ] || continue
    found=$(line_field "$line" launched_at)
    [ -n "$found" ] || continue
    printf '%s' "$found"
    return 0
  done < "$ROSTER_FILE"
  return 0
}

# THE LATEST LAUNCH, FOR THE RESTART-AFTER-ACK PATH ONLY (epic-23 wave-20 T20d, critic
# C3-1). `prior_launch_for_agent` above answers "the contract's original launch", which is
# right for an ordinary resume — the takeover case, where the roster's own first row for
# this id IS the contract, however many join rows have picked the id up since. A restart
# after an ack is a different question: `hooks/session-poker.sh`'s `extend` verb re-opens a
# MET row by appending a FRESH row for the SAME id, "launched now, so the old deliverable
# reads stale" (session-poker.sh, `extend`). If that extended contract is then acked and the
# id restarts, "the contract as it stood at the ack" is the EXTEND's launch, not the first
# dispatch's — carrying the earliest stamp forward instead rolls a revoked, abandoned
# contract's clock back past the extend, so the stale pre-extend deliverable reads MET again
# with acked=no, and a tree `stopped` had left standing for salvage becomes landable.
# Same scan as `prior_launch_for_agent`, but kept running to the LAST match rather than
# returning at the first: this session's roster is append-only, so the last matching row is
# the latest launch, whatever else has been appended for other ids in between.
latest_launch_for_agent() {  # <agent-id> -> latest launched_at for that id this session, or empty
  local aid="$1" line found=""
  [ -n "$aid" ] || return 0
  [ -f "$ROSTER_FILE" ] || return 0
  while IFS= read -r line; do
    case "$line" in '#'*|'') continue ;; esac
    case "$line" in "roster-state/${ROSTER_VERSION}|"*) : ;; *) continue ;; esac
    case "$line" in
      *"|agent_id=$aid"|*"|agent_id=$aid|"*) : ;;
      *) continue ;;
    esac
    [ "$(line_field "$line" agent_id)" = "$aid" ] || continue
    [ "$(line_field "$line" session)" = "$BIONIC_SID" ] || continue
    local lf
    lf=$(line_field "$line" launched_at)
    [ -n "$lf" ] && found="$lf"
  done < "$ROSTER_FILE"
  printf '%s' "$found"
  return 0
}

# ---- BEGIN an amend by id survives the placing (wave-27 T59; review pass 36 N1) ----
# `session-poker.sh amend <id>` records a set for an agent its start did not place as a row of
# its own: `status=unplaced`, named by the id. When the agent IS placed later, by the launch
# call's return (ARM 2) or by a later start (ARM 3), the placing row is appended after it and
# becomes the id's last row, which is the row the budget wall reads (`roster_row_for_id`), so the
# unplaced row no longer speaks for the id. That is enough for the reading and too much for the
# set: the placing row carried the launch's own set only, and the suite the orchestrator granted
# was refused again. So the placing row takes the id's latest unplaced row's `suites_allowed=`
# and `re_executes=` as well as its own: the union, its own first, `none` read as no suite (as
# the verb reads it), each run as its marked text. A row that has no such field gains it.
unplaced_carry() {  # <the placing row> <agent id> -> that row, carrying the id's amended set
  local _uc_up
  [ -n "$2" ] && [ -f "$ROSTER_FILE" ] || { printf '%s' "$1"; return 0; }
  _uc_up=$(awk -v id="$2" -v sid="$BIONIC_SID" -v pre="roster-state/${ROSTER_VERSION}|" '
    function kv(line, key,   i, n, parts) {
      n = split(line, parts, "|")
      for (i = 1; i <= n; i++) if (index(parts[i], key "=") == 1) return substr(parts[i], length(key) + 2)
      return ""
    }
    index($0, pre) == 1 && kv($0, "agent_id") == id && kv($0, "session") == sid && kv($0, "status") == "unplaced" { row = $0 }
    END { if (row != "") print row }' "$ROSTER_FILE" 2>/dev/null)
  [ -n "$_uc_up" ] || { printf '%s' "$1"; return 0; }
  printf '%s' "$1" | UC_SA="$(line_field "$_uc_up" suites_allowed)" UC_RX="$(line_field "$_uc_up" re_executes)" awk '
    function suites(own,   n, i, a, out, seen) {
      n = split(own " " ENVIRON["UC_SA"], a, /[ ,]+/)
      for (i = 1; i <= n; i++) if (a[i] != "" && a[i] != "none" && !(a[i] in seen)) { seen[a[i]] = 1; out = out (out == "" ? "" : " ") a[i] }
      return out
    }
    function runs(own,   n, i, k, a, out, seen, src) {
      src[1] = own; src[2] = ENVIRON["UC_RX"]
      for (k = 1; k <= 2; k++) {
        n = split(src[k], a, "`")
        for (i = 2; i <= n; i += 2) if (a[i] != "" && !(a[i] in seen)) { seen[a[i]] = 1; out = out (out == "" ? "" : " ") "`" a[i] "`" }
      }
      return out
    }
    BEGIN { RS = "|"; ORS = ""; sseen = 0; rseen = 0 }
    {
      f = $0
      if (!sseen && f ~ /^suites_allowed=/) { sseen = 1; v = suites(substr(f, 16)); if (v != "") f = "suites_allowed=" v }
      if (!rseen && f ~ /^re_executes=/)    { rseen = 1; v = runs(substr(f, 13));   if (v != "") f = "re_executes=" v }
      printf "%s%s", (NR > 1 ? "|" : ""), f
    }
    END {
      if (!sseen) { v = suites(""); if (v != "") printf "|suites_allowed=%s", v }
      if (!rseen) { v = runs("");   if (v != "") printf "|re_executes=%s", v }
    }'
}
# ---- END an amend by id survives the placing ----

# ============================================================
# THE PLAN ROW MOVES WITH THE LAUNCH (wave-26 T12, D4, AC-1.4; T32).
# ============================================================
#
# A dispatch used to cost the orchestrator two more calls after it: `task-set <id>
# status=active agent=<name>` and `ledger-add`, copying into the plan what this arm had just
# confirmed on the roster. The confirmation now moves the row, through ONE transaction:
# `session-poker.sh launch-sync`, which writes every open launch of this session the bound plan
# lacks, its row and its ledger line, in one validated, dry-committed write. Its rules (which
# launch maps to which row, the tree cells, a re-dispatch, a launch with no tree of its own) are
# written beside it, in session-poker.sh.
#
# THIS HOOK STARTS IT AND DOES NOT WAIT (T32). Through T12 the hook ran two verb transactions
# itself, about a second each, under the 10 s limit hooks.json gives it, so a batch of launches
# outran it and the later ones printed a busy refusal for the orchestrator to finish by hand. The
# call is now detached: its own process group (`set -m`), no terminal, every stream on /dev/null,
# so the hook returns at once and the harness has nothing of it to wait for. It takes `--wait`,
# so it queues behind another launch's transaction rather than giving up.
#
# A FAILURE STILL SURFACES. The detached call prints to nowhere, and that is safe only because
# it is not the only caller: the Patrol tick and the turn-end wall (payload/scripts/lib/stop.sh)
# run the same transaction, and whichever runs next prints what it could not record and the
# commands to run by hand. A kill of the detached call cannot leave half a launch: the row and
# its line are one write, by one rename.
#
# NO RUN PREDICATE HERE (T32; tests/hook-adoption.test.sh §4). This hook is the roster
# lifecycle and reads nothing out of the plan; the verb asks whose run the session is in, and
# exits silently when there is none, as it does before Step 4 and without a roster.
#
# BIONIC_LAUNCH_SYNC_INLINE=1 runs the call in the foreground, still silent, so a test can read
# the plan the moment the hook returns. Nothing in a session sets it.
POKER="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/session-poker.sh"

launch_sync_start() {  # -> 0 always; starts this session's launch-sync and does not wait for it
  [ -f "$POKER" ] || return 0
  if [ "${BIONIC_LAUNCH_SYNC_INLINE:-}" = 1 ]; then
    ( cd "$BIONIC_ROOT" 2>/dev/null && CLAUDE_CODE_SESSION_ID="$BIONIC_SID" \
        "${BASH:-bash}" "$POKER" launch-sync --wait ) </dev/null >/dev/null 2>&1
    return 0
  fi
  ( set -m
    cd "$BIONIC_ROOT" 2>/dev/null || exit 0
    CLAUDE_CODE_SESSION_ID="$BIONIC_SID" nohup "${BASH:-bash}" "$POKER" launch-sync --wait \
      </dev/null >/dev/null 2>&1 &
  ) </dev/null >/dev/null 2>&1
  return 0
}

# ============================================================
# ARM 2 — the ROSTER (PostToolUse|Agent).
# ============================================================
#
# The launch half wrote an `intended` row at PreToolUse, keyed by `tool_use_id`
# because no agent id exists yet at that moment (task 4/3). This event carries
# the same `tool_use_id` and an id for the agent that spawned — and WHICH id
# depends on the dispatch mode, which is the whole of epic-16 task 0.
#
# THE ID NAMESPACES DO NOT MEET. An async launch returns the transcript-form id
# (`a26bd30bf8616411b`) — the same form every later observation of that agent
# carries, so the roster's `agent_id=` is directly matchable and the by-id walls
# work. A teammate spawn returns the ADDRESSING form
# (`probemate@session-3b51bef0`) in both `agent_id` and `teammate_id`, while
# every subsequent payload for that same teammate — SubagentStart, SubagentStop,
# its own tool calls — carries the transcript form `aprobemate-4da9be517e8f90bd`
# at top level. No payload carries both, and the only key bridging them is the
# NAME (capture probe §3, conclusion 3).
#
# So the addressing id is recorded in a field of its own and `agent_id=` is left
# EMPTY in teammate mode. Writing it into `agent_id=` would cost more than the
# empty it replaces: hooks/stop-guard.sh's by-id match feeds the foreign-session
# wall, and a roster asserting an identity no observation can ever produce turns
# that wall's input from "unknown" into "wrong" — the failure the payload probe
# named before either was written (§Task 1 fix direction 2). The transcript-form
# id is not lost, only later: it arrives on SubagentStart, name-joined onto an
# `identified` row. A `confirmed` row never carries a wrong-namespace id.
#
# COMPLETION IS AN APPEND, NOT A REWRITE, without exception — this arm never
# rewrites the roster and never removes a row from it. THE SERIALIZATION STORY,
# stated plainly because it is the reason: hooks/dispatch-preflight.sh appends
# WITHOUT A LOCK, by design and in writing ("No lock, unlike the observation
# record… a single O_APPEND write of well under a pipe buffer, which the kernel
# does not interleave. A lock here would put a failure mode… in front of a
# dispatch, on the fail-open side"). The lock this script takes for the
# OBSERVATION record therefore serializes it against stop-guard's consume and its
# own writes — never against a launch. So any read-modify-write of the roster
# here, however brief and whatever lock it held, would silently drop a row a
# concurrent dispatch appended between the read and the rename. The completed row
# is instead appended, and a reader takes the LAST row for a `tool_use_id`. That
# fold is one line of shell in each reader and it costs a race nothing. Nothing is
# written from memory: every field is either copied verbatim from the intended row
# on disk or read out of this payload.
#
# A DISPATCH THAT WAS NEVER JOURNALLED IS NEVER CONFIRMED. Without a matching
# `intended` row this arm writes nothing rather than inventing a row the start
# gate never saw — and a row that never reaches `confirmed` is the signal that a
# spawn did not happen, which is precisely what AC-1 asks the ledger to show.
if [ "$TOOL_NAME" = "Agent" ]; then
  [ -f "$ROSTER_FILE" ] || exit 0
  [ -L "$ROSTER_FILE" ] && exit 0

  ROW=""
  while IFS= read -r line; do
    case "$line" in '#'*|'') continue ;; esac
    case "$line" in "roster-state/${ROSTER_VERSION}|"*) : ;; *) continue ;; esac
    # THE PREFILTER, and the whole reason this arm can afford an unbounded ledger
    # (Step-6 critic F-1). `line_field` is four processes per call and this loop
    # ran three of them on EVERY row of the file; at 3000 rows that measured
    # 9260 ms against the 10 s hook timeout this script's registration declares
    # (skills/canonical-sdlc/SKILL.md frontmatter; hooks/hooks.json carries the
    # same ceiling, and tests/cross-gate-agreement.test.sh L.4b pins them equal), which
    # is what pushed the review toward capping the file instead. A `case` is
    # in-shell and matches only the row this event is about, so the expensive
    # reads run once per dispatch rather than once per row.
    #
    # It is a SUPERSET filter, never the decision: the id is quoted, so glob
    # metacharacters in a platform value are literal, but a row whose id merely
    # STARTS WITH ours still reaches the `line_field` checks below — which are
    # exact, and which stay the authority on all three fields. `tool_use_id` is
    # the row's last field today, so both the mid-row and end-of-row forms are
    # matched rather than assuming the writer's field order (checklist A6).
    case "$line" in
      *"|tool_use_id=$TOOL_USE_ID"|*"|tool_use_id=$TOOL_USE_ID|"*) : ;;
      *) continue ;;
    esac
    [ "$(line_field "$line" tool_use_id)" = "$TOOL_USE_ID" ] || continue
    [ "$(line_field "$line" status)" = "intended" ] || continue
    [ "$(line_field "$line" session)" = "$BIONIC_SID" ] || continue
    ROW="$line"
  done < "$ROSTER_FILE"
  [ -n "$ROW" ] || exit 0

  # A `|` or a newline reaching here would forge a field or a row. The id comes
  # from the platform and the row from our own launch half, so this is a belt
  # rather than a repair — but it is the SAME belt the writer wears (S-1).
  AGENT_ID=$(sanitize "$AGENT_ID" 200)
  [ -n "$AGENT_ID" ] || exit 0

  # The namespace split, spent. `teammate_spawned` is the platform's own word for
  # the branch it took, so the mode is READ rather than inferred from the id's
  # shape — an id-shape sniff would be a second grammar guessing at what the
  # first one did, which is the defect class this whole script exists to avoid.
  # The addressing form keeps the `@` that makes it addressable: sanitize strips
  # `|`, newlines and control characters, and `@` is none of those.
  ROW_AGENT_ID="$AGENT_ID"
  ROW_TEAMMATE_ID=""
  if [ "$DISPATCH_STATUS" = "teammate_spawned" ]; then
    ROW_TEAMMATE_ID=$(sanitize "$TEAMMATE_ID" 200)
    [ -n "$ROW_TEAMMATE_ID" ] || exit 0
    ROW_AGENT_ID=""
  fi

  # S6 (AC-5, R6): a resume's fresh Agent-tool completion carries the SAME
  # transcript-form id an earlier row on this session's roster already wrote
  # down — see prior_launch_for_agent() above. Empty in the ordinary case (a
  # first confirmation's own id has never appeared before), so this changes
  # nothing there; teammate mode never reaches it, since ROW_AGENT_ID is empty
  # until identification (ARM 3) supplies the transcript form.
  PRIOR_LAUNCH=""
  [ -n "$ROW_AGENT_ID" ] && PRIOR_LAUNCH=$(prior_launch_for_agent "$ROW_AGENT_ID")

  # Substitute the fields that execution confirms, leaving every other field
  # of the launched row — the contract state especially — where the brief put it,
  # so the completed row is self-sufficient for a consumer that reads only it.
  # `teammate_id` is the one field the launch half does not write, so it is
  # appended when absent and substituted when present: a launch row that grows
  # the field later must not end up carrying two of them, since every reader
  # takes the FIRST match for a key. In async mode it is not written at all —
  # the field's presence is itself the statement of which namespace the row's id
  # is in, and an always-empty field would say that much less clearly.
  ROW_NAME=$(sanitize "$DISPATCH_NAME" 200)

  COMPLETED=$(printf '%s' "$ROW" | awk -v id="$ROW_AGENT_ID" -v tid="$ROW_TEAMMATE_ID" -v pl="$PRIOR_LAUNCH" -v nm="$ROW_NAME" '
    BEGIN { RS = "|"; ORS = ""; seen = 0 }
    {
      f = $0
      if (f ~ /^status=/)   f = "status=confirmed"
      if (f ~ /^agent_id=/) f = "agent_id=" id
      if (nm != "" && f ~ /^name=/) f = "name=" nm
      if (tid != "" && f ~ /^teammate_id=/) { f = "teammate_id=" tid; seen = 1 }
      if (pl != "" && f ~ /^launched_at=/) f = "launched_at=" pl
      printf "%s%s", (NR > 1 ? "|" : ""), f
    }
    END { if (tid != "" && !seen) printf "|teammate_id=%s", tid }')
  # The set an amend by id recorded for this agent rides the placing row (T59; `unplaced_carry`).
  [ -n "$ROW_AGENT_ID" ] && COMPLETED=$(unplaced_carry "$COMPLETED" "$ROW_AGENT_ID")
  printf '%s\n' "$COMPLETED" >> "$ROSTER_FILE" 2>/dev/null || exit 0

  # THE PLAN ROW MOVES WITH THE CONFIRMATION (wave-26 T12, D4), only once the roster row is
  # written: the launch is the record, and the plan follows it. See `launch_sync_start` above.
  # A dispatch with no name maps to no row, so it starts nothing.
  [ -n "$(line_field "$COMPLETED" name)" ] && launch_sync_start

  # NO BOUND ON THE ROSTER, deliberately (Step-6 critic F-1, reproduced end to end in
  # record/w3-critic-repro-cap.sh). The observation record this reasoning contrasted the
  # roster with is deleted (REQ-2), and the half that mattered is the half that survives:
  # a roster row is a CONTRACT — the only copy
  # of the progress path, cadence and subprocess claim the brief declared — and
  # the look hooks/stop-guard.sh takes reads its progress path, its deliverables and its
  # cadence off it. Drop a LIVE agent's row and that look has nothing to measure: the stop is
  # PERMITTED, the operator is shown a contract that says nothing, which is
  # indistinguishable from "the brief declared no contract". Eviction by recency
  # cannot tell a finished agent from a running one, and the rows most likely to be
  # oldest are the long-running agents D-6 exists for. That is a wall going inert,
  # not a look being refused.
  #
  # The cost the cap was bought with is paid at its source instead — the prefilter
  # above, which is what actually made this arm quadratic in session length. See
  # tests/cross-gate-agreement.test.sh §F for the survival case driven writer →
  # recorder → gate, and tests/execution-recorder.test.sh's P block for the budget.
  exit 0
fi

# ============================================================
# ARM 3 — the IDENTIFICATION (SubagentStart).
# ============================================================
#
# The third state, and the one that finally makes the roster's id matchable.
# ARM 2 left `agent_id=` EMPTY on every teammate row for the reason it states at
# length: the launch response carries the ADDRESSING form
# (`probemate@session-3b51bef0`) and nothing else ever does, so writing it into
# `agent_id=` would turn every by-id wall's input from unknown into wrong. This
# event is where the TRANSCRIPT form (`aprobemate-4da9be517e8f90bd`) first
# appears — the same form every later observation of that agent carries, and the
# form hooks/stop-guard.sh and hooks/stop-check.sh match on.
#
# THE JOIN IS BY AGENT ID, and the change is a repair (epic-16 wave-03, T4c).
# It used to be by NAME, read out of this payload's `agent_type` — which the
# wave-01 capture probe read as the teammate's name and wave-03 measured as the
# subagent TYPE (`general-purpose`) on a live Agent dispatch. Every by-name join
# therefore missed, silently, and this arm was inert even when its event arrived
# (t4-probes-report.md §5.1). This payload has seven keys and only one of them can
# key a row: `agent_id`, the transcript form, which is the SAME string ARM 2 wrote
# into `agent_id=` from `tool_response.agentId` and the SAME string the landing
# sweep matches against `background_tasks[].id` (t4b-probe-report.md §4, all three
# observed on one dispatch). The lookup is scoped to THIS session's roster file and
# re-checked against the row's own `session=` field, so an id this session never
# dispatched joins nothing.
#
# WHAT THE REPAIR COSTS, stated rather than left to be discovered. An `intended`
# row carries an EMPTY `agent_id` until ARM 2 completes it, and an empty id is not
# a key — so the id join cannot rescue a dispatch whose PostToolUse has not fired;
# the TYPE join below does, for a bionic role (wave-27 T5). A TEAMMATE row is not
# identified by this id join, because ARM 2 deliberately leaves its `agent_id=` empty
# (the launch response carries only the ADDRESSING form, and writing that into
# `agent_id=` would turn every by-id wall's input from unknown into wrong). A teammate IS identified, by the NAME join at SubagentStart
# below, and its `confirmed` row carries no id by design; the roster's one rule for
# the rows written after that moment is stated in payload/scripts/lib/roster.sh at
# `roster_row_for_id` (ADR-039). Both misses were ALREADY there — a join on a field
# that carries no name matches nothing either — and what changes is that the miss is
# structural and visible instead of silent. The alternative, keeping a name join beside this
# one, is keeping the defect: `agent_type` is not a name.
#
# LATEST WINS, and `intended` is accepted alongside `confirmed`. The roster is
# append-only and the latest row for an id is authoritative, so a resume
# identifies against the later contract.
#
# A START WE CANNOT PLACE IS NOT OURS TO RECORD. An id on no row of ours is a
# foreign or phantom agent — the shape the capture probe found firing at §4 — and
# it exits 0 having written nothing: inventing a row here would put a contract on
# the roster that no brief ever declared.
#
# EVERY FIELD IS COPIED FORWARD, exactly as ARM 2 does and for a sharper reason:
# hooks/session-sweeper.sh's verdict folds the roster to the LATEST row per name
# and reads the whole contract — deliverable, launch clock, progress path,
# cadence, waiver — off that row alone. A row that dropped a field would not
# merely be terse; it would silently retract the contract it inherited.
if [ -n "$IS_START" ]; then
  # ---------- SURVIVAL TERMS DELIVERY (wave-11 1c-b, design D2, probe P2) ----------
  #
  # D2 (spec §2, "Dispatcher ↔ agent"): this hook already reads `agent_type` on every
  # SubagentStart; for `bionic:*` it now prints `payload/context/survival.md` as
  # `additionalContext`, so a dispatched bionic agent receives the dispatch terms by PUSH
  # rather than by pulling a file it might skip. Third-party and harness agent types get
  # nothing. Probe P2 (record/wave-11-lean-spine/step2-probe-premises.md §2) proved this
  # exact stdout shape reaches a live subagent's transcript as a `<system-reminder>` and is
  # acted on — this is that shape, unchanged:
  #   {"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"<text>"}}
  #
  # THE FIELD, and why `agent_type` alone is the right test here even though the comment
  # above (THE FIELD THAT IDENTIFIES A TEAMMATE) says it is not one field with one meaning.
  # That caution is about using it as a NAME for a roster join; this is a TYPE test, and
  # `agent_type` is the only field this payload carries that could ever hold a subagent
  # TYPE string like `bionic:senior-implementor`. A teammate dispatch that puts a dispatch
  # NAME there instead is not a bionic type either way this reads it — worst case, one
  # dispatch literally named after a bionic role does not receive terms it does not need
  # a hook to hand it, which is the same class of residual ARM 3 already accepts below.
  #
  # PLACED BEFORE THE ROSTER, deliberately — delivery must not depend on this session's
  # roster carrying a row to join (a bionic agent dispatched outside that bookkeeping would
  # otherwise silently lose its dispatch terms), and every existing arm below this line is
  # untouched: this prints to stdout only and returns to falling through unchanged.
  #
  # RESOLVED THROUGH THE HOOK'S OWN LIB ROOT, never a hard-coded path. `$BIONIC_LIB` is
  # `<root>/scripts/lib` in both shapes the loader above already normalized (the installed
  # plugin root, and this repo's `payload/`), so its grandparent is that same root, and
  # `context/survival.md` sits directly under it (payload/context/survival.md on disk).
  #
  # NEVER FAILS THE HOOK (PostToolUse invariant, restated at the top of this file): a
  # missing or unreadable file prints nothing and logs one stderr line rather than
  # touching the exit code below.
  #
  # A SECOND DECIDER, ON THE JOINED ROW (wave-24 T6, D8, research-R3 Q2/Q3). For a teammate
  # `agent_type` is the dispatch NAME, so the test above never fires for one. The name join
  # below finds the roster row, and that row's `subagent_type=` carries the TYPE the
  # dispatch declared; `terms_for_row` asks it the same `bionic:*` question once the join
  # has run, and prints at most once (`TERMS_DELIVERED`). Delivery still never depends on a
  # row existing: the `agent_type` test here is first and unchanged.
  #
  # A READER'S CHECKS ARE PUSHED AT START (wave-27 T15; REQ-5, D5): `context/checks-<q>.md` for
  # each question on the reader's roster row (`questions=`, written by the dispatch wall).
  #
  # ---- BEGIN one string per file (wave-27 T30; review pass 24's blocker, A-orch-77) ----
  # THE HARNESS HANDS A HOOK'S additionalContext TO THE MODEL WHOLE ONLY UP TO 10,000 CHARACTERS,
  # each hook's string measured on its own; past that it saves the string to a file, passes the
  # path and a 2,000-character preview, and does not ask the model to read it (Claude Code hooks
  # reference). T15 pushed survival.md and the checks as ONE string, and three of the six deals
  # went over: those readers started without their checks and with part of the terms. So the push
  # is split, one string per file, one registration per string (hooks/hooks.json):
  #   - the bare registration pushes survival.md, and it alone joins, writes `agent_id`,
  #     `terms-delivered` and the duplicate-start row, so four hooks on one start are one start;
  #   - one registration per question (`$START_QUESTION`, its argument) pushes `bionic checks: <q>`
  #     and that question's file when the agent's row carries the question, and nothing otherwise.
  #     It reads the roster and writes nothing. The four may run at once and in any order, and no
  #     string depends on another having arrived: each checks string names itself on line one.
  # THE CAP. Every string is counted here, in UTF-16 code units (what the harness's string length
  # counts; a multi-byte character is one, never its bytes), and one over BIONIC_START_PUSH_MAX is
  # NOT printed: in its place goes one line naming the file to read, and stderr says so. The agent
  # starts either way: a SubagentStart hook cannot block, and this one never tries.
  BIONIC_START_PUSH_MAX=9500
  START_CONTEXT_DIR=$(cd "$BIONIC_LIB/../../context" 2>/dev/null && pwd) \
    || START_CONTEXT_DIR="$BIONIC_LIB/../../context"
  push_string() {  # <the file the string came from> — the string on stdin; prints one line
    local _ps_json _ps_n
    _ps_json=$(jq -Rsc --argjson max "$BIONIC_START_PUSH_MAX" '
      ([explode[] | if . > 65535 then 2 else 1 end] | add // 0) as $n
      | if $n <= $max then {hookSpecificOutput:{hookEventName:"SubagentStart",additionalContext:.}}
        else {over:$n} end' 2>/dev/null) || return 1
    case "$_ps_json" in
      '{"over":'*)
        _ps_n="${_ps_json#\{\"over\":}"; _ps_n="${_ps_n%\}}"
        echo "execution-recorder: the start push of $1 is $_ps_n characters, over BIONIC_START_PUSH_MAX=$BIONIC_START_PUSH_MAX — pushed one line naming the file instead" >&2
        jq -nc --arg p "$1" \
          '{hookSpecificOutput:{hookEventName:"SubagentStart",additionalContext:("Read this file before anything else: " + $p)}}' \
          2>/dev/null ;;
      *) printf '%s\n' "$_ps_json" ;;
    esac
  }
  deliver_checks() {  # <question>
    local _dc_f="$START_CONTEXT_DIR/checks-$1.md"
    if [ ! -r "$_dc_f" ]; then
      echo "execution-recorder: checks file not found at $_dc_f — nothing pushed for $1" >&2
      return 0
    fi
    { printf 'bionic checks: %s\n' "$1"; cat "$_dc_f"; } | push_string "$_dc_f"
  }
  # THE JOINS, ONE COPY EACH, asked by the terms registration (which writes what they find) and by
  # a question registration (which only reads it), so the two cannot place one start on two rows.
  name_join_row() {  # <name> -> the last intended|confirmed row of this session carrying that name
    local _nj_line _nj_row=""
    while IFS= read -r _nj_line; do
      case "$_nj_line" in '#'*|'') continue ;; esac
      case "$_nj_line" in "roster-state/${ROSTER_VERSION}|"*) : ;; *) continue ;; esac
      # Superset prefilter, exactly as the id join below: in-shell, quoted so glob
      # metacharacters stay literal, and matching both the mid-row and end-of-row
      # forms rather than assuming the writer field order (checklist A6).
      case "$_nj_line" in
        *"|name=$1"|*"|name=$1|"*) : ;;
        *) continue ;;
      esac
      [ "$(line_field "$_nj_line" name)" = "$1" ] || continue
      case "$(line_field "$_nj_line" status)" in intended|confirmed) : ;; *) continue ;; esac
      [ "$(line_field "$_nj_line" session)" = "$BIONIC_SID" ] || continue
      _nj_row="$_nj_line"
    done < "$ROSTER_FILE"
    [ -z "$_nj_row" ] || printf '%s\n' "$_nj_row"
  }
  # ---- BEGIN a stale launch is no candidate (wave-27 T38; review pass 8 F3, F4) ----
  # A LAUNCH THAT NEVER SPAWNED stays `intended` with no id for the rest of the session, and under
  # T5's filter (session, type, unclaimed) it made every later start of its type two candidates,
  # so none of them was placed, and with one live launch beside it the start could be written onto
  # the stale row. A launch is a candidate only when a start can still be its agent's:
  #   - THIS PLAN'S: its `plan=` is the plan this session is bound to now, as the dispatch wall
  #     stamps it (`session_plan`, `none` when unbound; an empty `plan=` reads `none` too);
  #   - NOT ACKED: no ack of its name later than its launch, read off the sweeper's ledger by the
  #     roster's own discharge rule (`_roster_discharged`, `_roster_occupied_at`), per launch;
  #   - READABLE: a launch whose stamp cannot be read is not a start this event can be.
  # THE WINDOW IS A TIE-BREAK, NEVER A FILTER (wave-27 T59; review pass 36 S2, A-orch-100). The
  # dispatch wall writes the launch row BEFORE the harness asks the user to permit the dispatch, so
  # a plain foreground start follows its launch by however long that prompt stood, and while the
  # orchestrator is held in that agent's call the refusal's `amend` line cannot be run. A stamp
  # later than now reads as now (N4), so a clock stepped back cannot keep one launch fresher than
  # every real one for good.
  # THE WINDOW CHOOSES A GROUP, AND ONE RULE JUDGES IT (wave-27 T68; review pass 47 B1, A-orch-122).
  # The group is the launches above launched at most START_JOIN_WINDOW_S seconds ago, or all of them
  # when none is. A group of one is joined, whatever its age. A group of several is launches a start
  # cannot tell apart, fresh or late: none is joined and the terms registration says so, and the
  # launch call's return places each agent by its `tool_use_id`. T59 took "the newest" of several
  # late launches, and with two in flight the newest is not always the start's own, so each agent
  # ran on the other's suites, files and checks. A launch that never spawned still blocks nothing
  # for long: the next dispatch of its type writes a launch inside the window, which is a group of
  # its own. What stays open is named in operational-rules.md (a start whose own dispatch wrote no
  # launch row, beside ONE dead launch, is joined to it).
  START_JOIN_WINDOW_S=300
  # ONE START, ONE CLOCK (T59; review pass 36 N6). One start runs four registrations (the terms and
  # one per question), four processes. Each judging the window by its own `date` could place the
  # start on one launch and push the checks of two, or the reverse, when they straddle a second at
  # the window's edge. So the first of them to judge writes its reading to a file named by the
  # session and the agent id, linked into place whole (`ln` fails when the file is there), and
  # every other one reads it. A reading more than START_CLOCK_SHARE_S seconds from the reader's own
  # clock is another start's (the registrations of one start run together, each bounded by its
  # 10-second timeout) and is replaced. `BIONIC_NOW_EPOCH` pins the reading, the libraries' idiom,
  # so a suite can put a launch exactly at the edge.
  # THE CLOCK FILES ARE A CLASS (wave-27 T68; review pass 47 S1, A-orch-137): `start-clock` in
  # lib/patrol.sh's PATROL_STATE_CLASSES, named `start-clock-<session>.<agent id>.state`, so the
  # session sweep, doctor and Step 8's wipe take a dead session's with its other state. A live
  # session holds only the files of starts still inside START_CLOCK_KEEP_S: each new file sweeps
  # the session's files whose reading no start of now can share, and a start that is placed
  # removes its own (its question registrations read its row, not the clock).
  START_CLOCK_SHARE_S=10
  START_CLOCK_KEEP_S=30
  start_clock_path() {  # -> this start's clock file, or nothing when its id cannot name one
    case "$START_ID" in ''|*[!A-Za-z0-9._@-]*) return 1 ;; esac
    printf '%s/start-clock-%s.%s.state' "$STATE_DIR" "$BIONIC_SID" "$START_ID"
  }
  start_clock_sweep() {  # this session's clock files no start judging now can share are removed
    local _cs_f _cs_r
    for _cs_f in "$STATE_DIR/start-clock-${BIONIC_SID}".*.state; do
      { [ -f "$_cs_f" ] && [ ! -L "$_cs_f" ]; } || continue
      _cs_r=$(head -c 20 "$_cs_f" 2>/dev/null | tr -d '\n')
      case "$_cs_r" in
        ''|*[!0-9]*|0?*|?????????????*) rm -f "$_cs_f"; continue ;;
      esac
      [ "$((START_NOW - _cs_r))" -le "$START_CLOCK_KEEP_S" ] && [ "$((_cs_r - START_NOW))" -le "$START_CLOCK_KEEP_S" ] \
        || rm -f "$_cs_f"
    done
    return 0
  }
  START_NOW=""
  clock_share() {  # <a reading> -> 0 when it is this start's: within START_CLOCK_SHARE_S of START_NOW
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ "$((START_NOW - $1))" -le "$START_CLOCK_SHARE_S" ] && [ "$(($1 - START_NOW))" -le "$START_CLOCK_SHARE_S" ]
  }
  start_clock() {  # -> START_NOW, epoch seconds: one reading per start, shared by its registrations
    [ -z "$START_NOW" ] || return 0
    local _sc_f _sc_was _sc_tmp
    START_NOW="${BIONIC_NOW_EPOCH:-}"
    case "$START_NOW" in ''|*[!0-9]*) START_NOW=$(date -u +%s) ;; esac
    _sc_f=$(start_clock_path) || return 0
    { [ -d "$STATE_DIR" ] && [ ! -L "$STATE_DIR" ] && [ ! -L "$_sc_f" ]; } || return 0
    _sc_was=$(head -c 20 "$_sc_f" 2>/dev/null | tr -d '\n')
    if clock_share "$_sc_was"; then START_NOW="$_sc_was"; return 0; fi
    _sc_tmp=$(mktemp "$STATE_DIR/.start-clock.XXXXXX" 2>/dev/null) || return 0
    printf '%s\n' "$START_NOW" > "$_sc_tmp"
    if ln "$_sc_tmp" "$_sc_f" 2>/dev/null; then
      rm -f "$_sc_tmp"
      start_clock_sweep
      return 0
    fi
    _sc_was=$(head -c 20 "$_sc_f" 2>/dev/null | tr -d '\n')
    if clock_share "$_sc_was"; then START_NOW="$_sc_was"; rm -f "$_sc_tmp"; return 0; fi
    mv -f "$_sc_tmp" "$_sc_f" 2>/dev/null || rm -f "$_sc_tmp"
    return 0
  }
  type_join_candidates() {  # <subagent type> -> the candidate count, then each candidate's row
    local _tj_plan _tj_nowiso _tj_from _tj_ledger="$STATE_DIR/sweeper-${BIONIC_SID}.state"
    roster_sh_load
    _tj_plan=$(sanitize "$(session_plan "$BIONIC_ROOT" "$BIONIC_SID" 2>/dev/null)" 400)
    [ -n "$_tj_plan" ] || _tj_plan="none"
    start_clock
    _tj_nowiso=$(date -u -r "$START_NOW" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
      || date -u -d "@$START_NOW" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
    _tj_from=$(date -u -r "$((START_NOW - START_JOIN_WINDOW_S))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
      || date -u -d "@$((START_NOW - START_JOIN_WINDOW_S))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
    { [ -f "$_tj_ledger" ] && [ ! -L "$_tj_ledger" ] && [ -r "$_tj_ledger" ]; } || _tj_ledger=""
    TJ_LEDGER="$_tj_ledger" \
    awk -v sid="$BIONIC_SID" -v ty="$1" -v plan="$_tj_plan" -v from="$_tj_from" -v now="$_tj_nowiso" \
        -v me="$START_ID" -v pre="roster-state/${ROSTER_VERSION}|" "$_ROSTER_OPEN_AWK"'
      BEGIN { _roster_acks(ENVIRON["TJ_LEDGER"], ACK) }
      index($0, "start-claim/v1|") == 1 {
        if (_roster_kv($0, "session") != sid) next
        cu = _roster_kv($0, "launch")
        if (cu != "" && !(cu in claimer)) claimer[cu] = _roster_kv($0, "claimed_by")
        next
      }
      index($0, pre) == 1 {
        if (_roster_kv($0, "session") != sid) next
        u = _roster_kv($0, "tool_use_id"); if (u == "") next
        if (!(u in last)) order[++n] = u
        last[u] = $0
        if (_roster_kv($0, "agent_id") != "" || _roster_kv($0, "teammate_id") != "") claimed[u] = 1
      }
      END {
        c = 0; o = 0; mine = ""
        for (i = 1; i <= n; i++) {
          u = order[i]
          if (u in claimed) continue
          st = _roster_kv(last[u], "status")
          if (st != "intended" && st != "confirmed") continue
          if (_roster_kv(last[u], "subagent_type") != ty) continue
          p = _roster_kv(last[u], "plan"); if (p == "") p = "none"
          if (p != plan) continue
          nm = _roster_kv(last[u], "name"); if (nm == "") nm = "(unnamed)"
          at = _roster_occupied_at(last[u])
          if ((nm in ACK) && _roster_discharged(at, ACK[nm])) continue
          if (!_roster_stamp_ok(at)) continue
          if (u in claimer) {
            if (claimer[u] == me) { mine = last[u] }
            continue
          }
          if (_roster_stamp_ok(now) && at "" > now "") at = now
          if (_roster_stamp_ok(from) && at "" >= from "") { pick[++c] = last[u]; continue }
          late[++o] = last[u]
        }
        if (mine != "") { print "1 mine"; print mine; exit }
        if (c == 0) { c = o; for (i = 1; i <= o; i++) pick[i] = late[i] }
        print c
        for (i = 1; i <= c; i++) print pick[i]
      }' "$ROSTER_FILE" 2>/dev/null
  }
  # A LAUNCH IS CLAIMED BY ONE ATOMIC ACT (wave-27 T68; review pass 47 B1). Two starts judging at once
  # each read the roster before either wrote its row, so both could join one launch. A start whose
  # group is one launch claims it first: it appends one `start-claim/v1` line naming the launch and
  # its own id to the roster, a single O_APPEND write as every roster row is, and the FIRST claim of
  # a launch in file order is the one that holds (the roster's own serialisation: the file's order
  # is the order of the writes). Then it judges again: a launch another start claimed is no
  # candidate, the one it holds itself is its answer, so the start that lost the claim judges the
  # candidates without that launch. Only the terms registration claims, as it is the one writer of
  # the start's row; a question registration reads the claims (the launch its agent id claimed is its
  # answer). A claim is never released; once the start's row is written the row says the same.
  launch_claim() {  # <tool_use_id> -> one claim line for this start's agent id, appended to the roster
    case "$1" in ''|*'|'*) return 0 ;; esac
    printf 'start-claim/v1|at=%s|session=%s|launch=%s|claimed_by=%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$BIONIC_SID" "$1" "$START_ID" >> "$ROSTER_FILE" 2>/dev/null
    return 0
  }
  type_join_pick() {  # <subagent type> -> what type_join_candidates prints, a group of one claimed first
    local _tp_out _tp_n _tp_u _tp_i=0
    start_clock
    while :; do
      _tp_out=$(type_join_candidates "$1")
      _tp_n="${_tp_out%%$'\n'*}"
      case "$_tp_n" in
        "1 mine") _tp_out="1${_tp_out#1 mine}"; break ;;
        1) : ;;
        *) break ;;
      esac
      _tp_u=$(line_field "${_tp_out#*$'\n'}" tool_use_id)
      _tp_i=$((_tp_i + 1))
      if [ -z "$_tp_u" ] || [ "$_tp_i" -gt 16 ]; then _tp_out=0; break; fi
      launch_claim "$_tp_u"
    done
    printf '%s\n' "$_tp_out"
  }
  # A READER STARTED WITHOUT ITS CHECKS IS WRITTEN DOWN (wave-27 T38; review pass 31 F2,
  # A-orch-88). When a start cannot be placed and its candidates carry DIFFERENT `questions=`, no
  # question registration pushes a checks file (above), and its stderr line reaches no reader.
  # The terms registration, the one writer, appends one line to the session's roster: the time,
  # the role, the candidates' roster names. `session-poker.sh tick` prints it once, so the
  # orchestrator stops that reader and dispatches it again. A question registration writes nothing.
  unchecked_start_record() {  # <the candidate rows, one per line>
    local _us_l _us_sets _us_names=""
    _us_sets=$(while IFS= read -r _us_l; do [ -n "$_us_l" ] && printf '%s\n' "$(line_field "$_us_l" questions)"; done <<< "$1" | sort -u)
    [ "$(printf '%s\n' "$_us_sets" | grep -c '')" -gt 1 ] || return 0
    while IFS= read -r _us_l; do
      [ -n "$_us_l" ] || continue
      _us_l=$(line_field "$_us_l" name); [ -n "$_us_l" ] || _us_l="(unnamed)"
      _us_names="${_us_names:+$_us_names,}${_us_l//,/ }"
    done <<< "$1"
    printf 'start-unchecked/v1|event=start|at=%s|session=%s|agent_id=%s|role=%s|candidates=%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$BIONIC_SID" "$START_ID" "$START_TYPE" "$_us_names" \
      >> "$ROSTER_FILE" 2>/dev/null
    return 0
  }
  # ---- END a stale launch is no candidate ----

  # A QUESTION REGISTRATION: read the agent's row, push one checks file or nothing, write nothing.
  # THE ROW, in this order, which is why it agrees with the terms registration whichever ran first:
  #   1. the last row of this session carrying this agent's id, whatever its status. After the
  #      terms registration has joined, that is its `identified` row, a copy of the joined row with
  #      `questions=` carried forward; on a resumed copy it is the `identified` or
  #      `duplicate-start` row, so the copy is pushed what the first start was; and a launch whose
  #      call already returned carries the id on its `confirmed` row.
  #   2. otherwise the joins the terms registration is about to make, by name and then by type,
  #      through the same functions: same candidates, same answer, nothing written.
  # A START THAT CANNOT BE PLACED (several unclaimed launches of its type, none named): when every
  # candidate carries the same `questions=` that set is pushed; when they differ nothing is, and a
  # registration whose question one of them carries says so, naming the candidates.
  if [ -n "$START_QUESTION" ]; then
    case "$START_QUESTION" in evidence|adversarial|structure) : ;; *) exit 0 ;; esac
    [ -f "$ROSTER_FILE" ] && [ ! -L "$ROSTER_FILE" ] || exit 0
    START_ID=$(sanitize "$START_ID" 200)
    START_TYPE=$(sanitize "$START_TYPE" 200)
    [ -n "$START_ID" ] || exit 0
    roster_sh_load
    Q_ROW=$(awk -v id="$START_ID" -v sid="$BIONIC_SID" -v pre="roster-state/${ROSTER_VERSION}|" "$_ROSTER_OPEN_AWK"'
      index($0, pre) == 1 && _roster_kv($0, "agent_id") == id && _roster_kv($0, "session") == sid { row = $0 }
      END { if (row != "") print row }' "$ROSTER_FILE" 2>/dev/null)
    [ -n "$Q_ROW" ] || [ -z "$START_TYPE" ] || Q_ROW=$(name_join_row "$START_TYPE")
    Q_SET=""
    if [ -n "$Q_ROW" ]; then
      Q_SET=$(line_field "$Q_ROW" questions)
    else
      case "$START_TYPE" in
        bionic:*)
          # A question registration claims nothing (it writes nothing, PC-f2); it reads the claims:
          # the launch this agent id claimed is its answer, one another start claimed is no candidate.
          Q_PICK=$(type_join_candidates "$START_TYPE")
          case "${Q_PICK%%$'\n'*}" in "1 mine") Q_PICK="1${Q_PICK#1 mine}" ;; esac
          Q_N="${Q_PICK%%$'\n'*}"
          if [ "${Q_N:-0}" -ge 1 ] 2>/dev/null; then
            Q_CANDS="${Q_PICK#*$'\n'}"
            Q_SETS=$(while IFS= read -r _q_l; do printf '%s\n' "$(line_field "$_q_l" questions)"; done <<< "$Q_CANDS" | sort -u)
            if [ "$(printf '%s\n' "$Q_SETS" | grep -c '')" = 1 ]; then
              Q_SET="$Q_SETS"
            else
              case ",$(printf '%s' "$Q_SETS" | tr '\n' ','),"  in
                *",$START_QUESTION,"*)
                  Q_NAMES=$(while IFS= read -r _q_l; do printf ' %s=%s' "$(line_field "$_q_l" name)" "$(line_field "$_q_l" questions)"; done <<< "$Q_CANDS")
                  echo "execution-recorder: agent $START_ID cannot be placed on one of the $Q_N launches of $START_TYPE, and they carry different questions= (name=questions:$Q_NAMES) — checks-$START_QUESTION.md not pushed" >&2 ;;
              esac
            fi
          fi
          ;;
      esac
    fi
    case ",$Q_SET," in *",$START_QUESTION,"*) deliver_checks "$START_QUESTION" ;; esac
    exit 0
  fi
  # ---- END one string per file ----

  # THE TERMS (wave-11 1c-b; T15; T30). A start the `agent_type` test marks bionic OWES the terms
  # (`TERMS_OWED`): the joins below deliver them once a row is found, and a start that exits before
  # any row is joined is delivered them on its way out (the EXIT trap). survival.md alone: a
  # reader's checks are its question registrations' strings, never this one's.
  TERMS_DELIVERED=""
  TERMS_OWED=""
  # ---- BEGIN scratch space per agent (wave-27 T30 part two; REQ-13, D22) ----
  # The terms string closes with one line naming `<project root>/.bionic/tmp/scratch/<session>/<roster
  # name>/`, made here, as the agent's own scratch directory. `TERMS_NAME` is the joined row's name,
  # set where a row is found; with none the directory is named by the agent id. The line counts
  # toward the cap like the rest of the string. A directory that cannot be made, or a name that
  # is not one path segment, is logged and the line left out. The agent starts either way. The
  # symlink tests are the state directory's own (A2/A3 above): a hostile repo's link is not
  # followed out of the tree.
  TERMS_NAME=""
  scratch_line() {  # -> the scratch line, its directory made; nothing when it cannot be
    local _sl_leaf="${TERMS_NAME:-$(sanitize "$START_ID" 200)}" _sl_dir
    _sl_dir="$STATE_DIR/scratch/$BIONIC_SID/$_sl_leaf"
    case "$_sl_leaf" in
      ''|.|..|*/*)
        echo "execution-recorder: [$_sl_leaf] is not one directory name — no scratch directory pushed to agent $START_ID" >&2
        return 0 ;;
    esac
    if [ -L "$STATE_DIR/scratch" ] || [ -L "$STATE_DIR/scratch/$BIONIC_SID" ] || [ -L "$_sl_dir" ] \
       || ! mkdir -p "$_sl_dir" 2>/dev/null || [ ! -d "$_sl_dir" ]; then
      echo "execution-recorder: scratch directory $_sl_dir could not be made — the scratch line is left out" >&2
      return 0
    fi
    printf 'Your scratch directory is %s/ — nothing outside it is yours to write as scratch.\n' "$_sl_dir"
  }
  # ---- END scratch space per agent ----
  deliver_terms() {
    local _dt_f="$START_CONTEXT_DIR/survival.md" _dt_line
    if [ ! -r "$_dt_f" ]; then
      echo "execution-recorder: survival terms not found at $_dt_f — printing nothing" >&2
      return 0
    fi
    _dt_line=$(scratch_line)
    { cat "$_dt_f"; [ -z "$_dt_line" ] || printf '%s\n' "$_dt_line"; } \
      | push_string "$_dt_f" && TERMS_DELIVERED=1
  }
  case "$(sanitize "$START_TYPE" 200)" in
    bionic:*) TERMS_OWED=1 ;;
  esac
  trap '[ -n "$TERMS_OWED" ] && [ -z "$TERMS_DELIVERED" ] && deliver_terms' EXIT

  [ -f "$ROSTER_FILE" ] || exit 0
  [ -L "$ROSTER_FILE" ] && exit 0

  # The same belt the writer wears (S-1): a `|` or a newline in a platform value
  # forges a field or a row. The id is sanitized BEFORE it is compared, so the
  # value matched against the roster is the value that was written there.
  START_ID=$(sanitize "$START_ID" 200)
  [ -n "$START_ID" ] || exit 0

  # ---------- T22: A SECOND START FOR ONE ID IS A RESUMED COPY ----------
  #
  # (A-orch-33; AC-4.4's start-side half.) One agent id that starts TWICE in one session is
  # not a lifecycle this machinery has any other name for: the harness loses the agent table
  # across a `/clear` and keeps the teammate one, so a resume aimed at a transcript id brings
  # a second process up against a contract the first is still working. Both answer to one
  # roster row, one name and one address.
  #
  # IT IS RECORDED, NOT REFUSED, AND THAT IS MEASURED RATHER THAN ASSUMED. The installed
  # CLI's own hook-event contract for this event reads, verbatim:
  #     SubagentStart … Exit code 0 - JSON additionalContext shown to subagent
  #                     Exit code 2 - show stderr to user only
  #                     Other exit codes - show stderr to user only
  # and the binary's `hookSpecificOutput` switch consumes only `additionalContext` for
  # SubagentStart — there is no `permissionDecision` branch for it as there is for PreToolUse.
  # A SubagentStart hook CANNOT block. So this journals the fact and `session-poker.sh tick`
  # is what names it; the door that can actually close is one event earlier, at
  # `hooks/dispatch-preflight.sh`'s name-in-flight arm.
  #
  # THE PREDICATE IS THE ROSTER'S ONE CLOSE READING, not a second liveness truth. A row
  # already `identified` for this id is a lineage that has started; it has finished only when
  # its name is CLOSED, and a name is closed by the one predicate every roster reader in the
  # fleet asks — `roster_open_names` (payload/scripts/lib/roster.sh): an ack stamped after the
  # name's latest launch, and nothing else (ADR-034 d1). A start against a finished lineage is
  # a name being reused, which is allowed; a start against an open one is a resumed copy.
  #
  # A MET MARKER CLOSES NOTHING HERE ANY MORE (epic-23 wave-20 T20, REQ-10, D10; found by T17,
  # approved by Chris). Until T20 this check carried its own latest-contract reading — four awk
  # functions, byte-pinned by cross-gate §LC — under which a `landing-swept/v1|…|state=MET`
  # marker with no live row after it closed the name. The marker records that a landing was
  # SEEN, not that the agent left, so a second start behind one was let through unjournalled
  # while the dispatch wall, the sweeper, the stop wall and the tick's adopt fold all called the
  # same name open (cross-gate §CG-close T20). The reading's own fix — a live row after the
  # marker re-opens the name (delta review C1) — is the predicate's by construction: an ack
  # older than the latest launch closes nothing.
  #
  # TWO STEPS, SO THE COMMON PATH PAYS NOTHING. The awk below reads only this id's LAST row;
  # the predicate is asked after it, of that one name, and only when that row already says
  # the id started — the first start of every id is `confirmed` there and never asks.
  #
  # IT IS PURELY ADDITIVE. Before this, a second start for an already-`identified` id matched
  # neither join below (both accept `intended|confirmed` only) and exited silently — except
  # where the ORIGINAL `confirmed` row was still on the append-only roster, in which case it
  # was joined a second time and a second `identified` row appended. Both of those are what
  # this replaces.
  DUP_PRIOR=$(awk -F'|' -v id="$START_ID" -v sid="$BIONIC_SID" '
    function kv(line, key,   i, n, parts) {
      n = split(line, parts, "|")
      for (i = 1; i <= n; i++) if (index(parts[i], key "=") == 1) return substr(parts[i], length(key) + 2)
      return ""
    }
    /^roster-state\/v1\|/ {
      if (kv($0, "agent_id") != id) next
      if (kv($0, "session") != sid) next
      # THE LAST ROW OF THIS ID, WHATEVER ITS STATUS. A RESUME is a fresh
      # intended/confirmed cycle for the same id, written moments ago by the dispatch wall
      # and ARM 2 — a contract deliberately re-opened, which this event is then the ordinary
      # identification of. A DUPLICATE START has no such cycle: the last thing said about
      # this id is that it already started. That difference is the whole predicate, and it
      # is read off the ordering of an append-only file.
      row = $0; st = kv($0, "status")
      next
    }
    # A DUPLICATE-START ROW IS NOT A RE-CONTRACT EITHER. The predicate is "nothing has
    # re-opened a contract for this id since it started": `identified` is the first start,
    # `duplicate-start` is the second, and a third start is the third. Only an `intended` or
    # `confirmed` row — written by the dispatch wall and ARM 2 — is a fresh cycle.
    END { if (row != "" && (st == "identified" || st == "duplicate-start")) print row }
  ' "$ROSTER_FILE" 2>/dev/null) || DUP_PRIOR=""
  # LAZY, ONLY WHEN THIS ARM MIGHT ASK roster_open_names (epic-23 wave-20 T20b, review R5's
  # perf note). Every other SubagentStart — the first start of every id, which is the common
  # path — never reaches this condition and never pays for roster.sh's definitions at all.
  DUP_PRIOR_BEFORE="$DUP_PRIOR"
  [ -n "$DUP_PRIOR" ] && roster_sh_load
  # ---- BEGIN open-contract reading — the one close predicate, asked of one name (cross-gate §LC) ----
  if [ -n "$DUP_PRIOR" ]; then
    case "$DUP_PRIOR" in *"|name="*) DUP_NAME="${DUP_PRIOR#*|name=}"; DUP_NAME="${DUP_NAME%%|*}" ;; *) DUP_NAME="" ;; esac
    [ -n "$DUP_NAME" ] || DUP_NAME="(unnamed)"
    DUP_NAME="${DUP_NAME//$'\t'/ }"
    grep -qxF -- "$DUP_NAME" <<< "$(roster_open_names "$ROSTER_FILE" "$STATE_DIR/sweeper-${BIONIC_SID}.state" "$BIONIC_SID")" || DUP_PRIOR=""
  fi
  # ---- END open-contract reading ----
  # A RESTART AFTER AN ACK (epic-23 wave-20 T20b, review R5). The span above reset DUP_PRIOR to
  # empty because roster_open_names found the name CLOSED — this WAS a duplicate reading (the
  # id's last row already says it started) against a lineage the ack has since finished. The
  # fallthrough below re-identifies this id as a reused name, and that identification must
  # carry a FRESH occupancy stamp — `restarted_at=`, beside the contract's unchanged
  # `launched_at` (T20c; see RESTARTED_AT further down) — otherwise the row reads exactly as
  # old as the row the ack already discharged, and roster_open_names keeps reading the name
  # closed forever (walk §9b/9c; the restarted agent held no slot at all).
  RESTART_AFTER_ACK=""
  [ -n "$DUP_PRIOR_BEFORE" ] && [ -z "$DUP_PRIOR" ] && RESTART_AFTER_ACK=1
  if [ -n "$DUP_PRIOR" ]; then
    # EVERY FIELD CARRIED FORWARD, exactly as the identification below does: the row is a
    # CONTRACT, and a row that dropped a field would silently retract what it inherited.
    # Only `status=` moves, to a value the status-filtered readers do not recognise: the
    # sweep and the stop gates skip a `duplicate-start` row, and the tick is the surface
    # that says something about it. The BUDGET arm does not filter by status — it reads the
    # last row carrying the id (`roster_row_for_id`, payload/scripts/lib/roster.sh) — so
    # this row IS what it reads after a restart. That is the intent: the successor copied
    # here is identified, so it carries the id and the contract, amended or not (ADR-039).
    printf '%s\n' "$DUP_PRIOR" | awk '
      BEGIN { RS = "|"; ORS = "" }
      { f = $0; sub(/\n$/, "", f)
        if (f ~ /^status=/) f = "status=duplicate-start"
        printf "%s%s", (NR > 1 ? "|" : ""), f }
      END { printf "\n" }' >> "$ROSTER_FILE" 2>/dev/null
    # The copy's terms (the EXIT trap) name the scratch directory the first start was given (T30).
    TERMS_NAME=$(line_field "$DUP_PRIOR" name)
    exit 0
  fi

  ROW=""
  while IFS= read -r line; do
    case "$line" in '#'*|'') continue ;; esac
    case "$line" in "roster-state/${ROSTER_VERSION}|"*) : ;; *) continue ;; esac
    # The same prefilter discipline as ARM 2 (Step-6 critic F-1): `line_field` is
    # four processes per call, and an unbounded roster cannot afford three of
    # them on every row. The `case` is in-shell and the id is quoted, so glob
    # metacharacters in a platform value stay literal. It is a SUPERSET filter —
    # a row whose id merely starts with ours still reaches the exact checks
    # below, which stay the authority. `agent_id=` is mid-row in every shape the
    # writer emits, but the end-of-row form is matched too rather than assuming
    # the field order (checklist A6).
    case "$line" in
      *"|agent_id=$START_ID"|*"|agent_id=$START_ID|"*) : ;;
      *) continue ;;
    esac
    [ "$(line_field "$line" agent_id)" = "$START_ID" ] || continue
    case "$(line_field "$line" status)" in intended|confirmed) : ;; *) continue ;; esac
    [ "$(line_field "$line" session)" = "$BIONIC_SID" ] || continue
    ROW="$line"
  done < "$ROSTER_FILE"

  # THE NAME JOIN (session-20260815, T2 — design D2, tactical default 2), WIDENED
  # TO THE DOOR (session-20260815-landing-cleanup, T1). Only reached when the id
  # join found nothing, which for a teammate is every time: ARM 2 leaves
  # `agent_id=` empty on that branch, so there is no id on the row for the loop
  # above to match, and without this join the row is never identified at all —
  # which is what left every teammate outside the landing contract.
  #
  # WHY THE TEAMMATE SCOPE HAD TO GO, measured rather than argued. The join was
  # first written to fire only over rows whose `teammate_id=` is non-empty — the
  # writer's own statement that the platform said `teammate_spawned`. But that
  # field is written by ARM 2, at PostToolUse|Agent, and this event arrives BEFORE
  # it: at a teammate's FIRST SubagentStart the row is still `intended`, with an
  # empty `agent_id=` for the loop above and an empty `teammate_id=` for the scope
  # here, so identification could not fire at the door — only at a resume, after a
  # completion had filled the field. Live measurement on the predecessor wave's own
  # roster: three confirmed teammate contracts, all three `agent_id=` empty, none
  # ever identified, zero sweep markers (step2-research-a1-a3.md §A1(3), quoting
  # t1-probe-report.md:41-51). A scope that can only be satisfied after the moment
  # it guards is not a scope, it is an off switch.
  #
  # WHAT GUARDS IT INSTEAD is that same field carrying two meanings — the fact the
  # wave-03 removal was right about and this join is built on rather than against.
  # `agent_type` carries the dispatch NAME for a teammate and the subagent TYPE for
  # an async dispatch (t1-probe-report.md §2.1, both measured on one live session).
  # THE CORRECTED HISTORY (Step-6 review flag 1-A; the prior text here had it
  # backwards). This join is not new and was never unscoped: it was WRITTEN at
  # `47e8961` (epic-16 w1 task 1/7) with the same predicates as today's — `name=`
  # equality, `intended|confirmed`, session-scoped (`git show
  # 47e8961:hooks/execution-recorder.sh`) — then DELETED at `27a8e4c`, whose own
  # message gives the cause: "the execution recorder's identification arm keyed on
  # agent_type, which carries the subagent TYPE and never the dispatch name, so
  # every by-name join missed silently." It was removed on the belief that it was
  # a no-op, not that it misjoined. This wave's research falsified that belief
  # (t1-probe-report.md §2.1: `agent_type` carries the dispatch NAME for a
  # teammate). So this is not a rescoped join — it is the same join, restored,
  # because the measurement its removal rested on was wrong.
  #
  # THE RESIDUAL IS ONE DISPATCH LITERALLY NAMED AFTER A SUBAGENT TYPE (plan
  # Assumptions A-D1): a teammate named `general-purpose` and an async dispatch of
  # TYPE `general-purpose` are the same string on this payload, and nothing on the
  # roster separates them. Accepted, and pinned from the residual side in
  # tests/execution-recorder.test.sh Section 10 so that un-accepting it is a design
  # change rather than a silent one.
  #
  # `intended` AND `confirmed` are both join targets, as they are for the id loop
  # above. The door case is the `intended` half; the `confirmed` half is what keeps
  # a teammate identifiable at a resume, or when the completion beat the start.
  #
  # RESIDUAL, kept and documented rather than solved here: one NAME dispatched twice
  # in one session is two agents on two rows, and the later row wins — the same
  # residual the resume case above already carries, and the reason the landing
  # verdict prefers the id this arm fills over the name it joined on.
  # The same belt the writer wears, before the value is compared against what the
  # writer stored: the roster holds sanitized names, so an unsanitized needle would
  # miss a row it should match rather than merely failing safe.
  START_TYPE=$(sanitize "$START_TYPE" 200)
  # The loop itself is `name_join_row` above (T30), which a question registration asks too.
  if [ -z "$ROW" ] && [ -n "$START_TYPE" ]; then
    ROW=$(name_join_row "$START_TYPE")
  fi
  # THE TYPE JOIN (wave-27 T5, D15, AC-8.1; walk-triage-3). Reached when neither join above
  # found a row, which for a plain dispatch whose launch call has not returned is every time:
  # the dispatch wall wrote its row with `agent_id=` EMPTY, ARM 2 fills the id only when the
  # Agent call returns, and a FOREGROUND call returns when the agent has finished. Until then the
  # budget arm (payload/scripts/lib/walls.sh) found no row for the id and refused a runner its
  # own full run. This event carries the id and, for a plain dispatch, the subagent TYPE in
  # `agent_type` — and the row carries that type in `subagent_type=`. So the row gains its id
  # here, at the door, and ARM 2 stays the second writer of the same value.
  #
  # ONLY A BIONIC ROLE, AND ONLY ONE CANDIDATE. A candidate is a launch (keyed by `tool_use_id`)
  # of this session and this type that no row has yet given an id or a `teammate_id=`: a
  # teammate is joined by the name join above, and a launch that already has an id belongs to
  # an agent that already started, and it must still be one a start can follow (this plan's, not
  # acked, inside the window before outside it: T38, T59, in `type_join_candidates`). Two candidates are two
  # launches this event cannot tell apart
  # — the name the start carries is the only tie-break, and the name join above already spent
  # it — so both are left to ARM 2's tool_use_id join and one line says so. A third-party type
  # is left out because `general-purpose` is the one type a teammate could also be named (the
  # A-D1 residual above); the budget arm names that reason when it refuses such an agent's suite,
  # with the `amend` line that records a set for it by its id (T38).
  if [ -z "$ROW" ] && [ -z "${RESTART_AFTER_ACK:-}" ]; then
    case "$START_TYPE" in
      bionic:*)
        # The candidate filter is `type_join_candidates` above (T30), which a question registration
        # asks too; it loads roster.sh's field reader (`_roster_kv`) lazily, so only a start both
        # joins missed ever pays for it. One candidate is the row; several are left.
        TYPE_PICK=$(type_join_pick "$START_TYPE")
        case "${TYPE_PICK%%$'\n'*}" in
          1) ROW="${TYPE_PICK#*$'\n'}" ;;
          0|'') : ;;
          *) echo "execution-recorder: ${TYPE_PICK%%$'\n'*} launches of $START_TYPE on this session roster have no id and the start names none of them; agent $START_ID is left to the return of its launch call" >&2
             unchecked_start_record "${TYPE_PICK#*$'\n'}" ;;
        esac
        ;;
    esac
  fi
  # A RESTART AFTER AN ACK RE-IDENTIFIES FROM THE ID'S LATEST STARTED ROW (epic-23 wave-22 T9;
  # ADR-039 Δ2; critic-b2f70c1 C1). Both joins above accept `intended|confirmed` only, and the
  # contract a restart must carry is on neither: `session-poker.sh amend` and `extend` append
  # their successor as an `identified` row carrying the id (ADR-039), which both joins skip. A
  # teammate's id join finds nothing and its name join takes the recorder's ORIGINAL `confirmed`
  # row; an async agent's id join takes the pre-amend `confirmed` row. Either copy carried the
  # first contract, became the id's last row, and the budget arm refused the amended run again.
  # `DUP_PRIOR_BEFORE` is the id's last row when that row says it started (identified or
  # duplicate-start) — the amended or extended successor whenever there is one. Placed after
  # BOTH joins: the async id join would overwrite it otherwise. The awk below rewrites its
  # status, launch and restarted_at as it does for a joined row.
  # THE COPY SOURCE CHANGES FOR EVERY RESTART AFTER AN ACK, AMENDED OR NOT (wave-22 T13;
  # critic-3598752 I3). With no amend, a teammate's latest started row is usually the
  # recorder's first `identified` row, which carries no teammate_id (ARM 2 adds it to the
  # `confirmed` row only), so the joined row's teammate_id is kept when the source has none —
  # without it `stop-orders.sh standdown` addresses the transcript id.
  if [ -n "${RESTART_AFTER_ACK:-}" ] && [ -n "$DUP_PRIOR_BEFORE" ]; then
    RA_TID=$(line_field "$ROW" teammate_id)
    ROW="$DUP_PRIOR_BEFORE"
    case "$ROW" in *"|teammate_id="*) : ;; *) [ -n "$RA_TID" ] && ROW="$ROW|teammate_id=$RA_TID" ;; esac
  fi
  [ -n "$ROW" ] || exit 0
  # The set an amend by id recorded for this agent rides the placing row (T59; `unplaced_carry`).
  ROW=$(unplaced_carry "$ROW" "$START_ID")

  # THE TEAMMATE'S TERMS, decided on the row the joins above found (wave-24 T6, D8), and every
  # owed delivery made here (wave-27 T15; the checks are the question registrations', T30).
  case "$(line_field "$ROW" subagent_type)" in
    bionic:*) TERMS_OWED=1 ;;
  esac
  TERMS_NAME=$(line_field "$ROW" name)
  [ -n "$TERMS_OWED" ] && [ -z "$TERMS_DELIVERED" ] && deliver_terms
  TERMS_AT=""
  [ -n "$TERMS_DELIVERED" ] && TERMS_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # S6 (AC-5, R6): THE RESUME CASE. `agent_id` here is the transcript form, and
  # a resume delivers this same event again for an id the roster already
  # carries — see prior_launch_for_agent() above (defined beside ROSTER_FILE).
  # On a first identification the id has never appeared before, so this is
  # empty and changes nothing; on a resume it recovers the ORIGINAL dispatch's
  # launch reference regardless of how many fresher rows now name the same id,
  # including one this very join just picked up.
  PRIOR_LAUNCH=$(prior_launch_for_agent "$START_ID")

  # ON THE RESTART_AFTER_ACK PATH ONLY, take the id's LATEST launched_at instead of its
  # earliest (epic-23 wave-20 T20d, critic C3-1; see latest_launch_for_agent() above). Every
  # other identification — the first, and an ordinary resume — keeps the earliest reading:
  # this override reaches only the one case where a contract may have been extended (a fresh
  # row for this same id, launched later) since the first dispatch and before the ack that
  # `RESTART_AFTER_ACK` names.
  if [ -n "${RESTART_AFTER_ACK:-}" ]; then
    LATEST_LAUNCH=$(latest_launch_for_agent "$START_ID")
    [ -n "$LATEST_LAUNCH" ] && PRIOR_LAUNCH="$LATEST_LAUNCH"
  fi

  # A RESTART AFTER AN ACK HOLDS A SLOT BY ITS OWN STAMP, NOT BY MOVING THE CONTRACT'S CLOCK
  # (epic-23 wave-20 T20b, review R5; repaired at T20c, critic C2-2). The name must read open
  # again — the agent is back on the panel — and roster_open_names only re-opens a name whose
  # latest occupancy stamp postdates its ack. T20b gave the restart that stamp by overriding
  # PRIOR_LAUNCH, i.e. `launched_at`. But `launched_at` is ALSO the clock the sweeper dates the
  # deliverable against, so a contract met before the ack read UNMET for good and `stopped`
  # closed a landed row `abandoned`. Occupancy and the contract are two questions (D10), so
  # they are two fields: `launched_at` keeps the contract's launch, carried forward exactly as
  # every ordinary resume carries it, and the restart's own time rides `restarted_at=`, which
  # roster_open_names — the one close predicate — reads, and no contract reader does.
  RESTARTED_AT=""
  [ -n "${RESTART_AFTER_ACK:-}" ] && RESTARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # `agent_id` is appended when the joined row has no such field and substituted
  # when it has one — ARM 2's rule for `teammate_id`, for ARM 2's reason: every
  # reader takes the FIRST match for a key, so a row carrying two of them would
  # answer with whichever the writer happened to put first. Today's writer always
  # emits the field, so the append branch is a belt against a writer that stops.
  # `restarted_at` follows the same substitute-or-append rule, and only on a restart: the
  # joined row is an intended/confirmed row, which no writer stamps with one, so on every
  # other identification the row is byte-identical to before T20b.
  IDENTIFIED=$(printf '%s' "$ROW" | awk -v id="$START_ID" -v pl="$PRIOR_LAUNCH" -v ra="$RESTARTED_AT" -v td="$TERMS_AT" '
    BEGIN { RS = "|"; ORS = ""; seen = 0; rseen = 0; tseen = 0 }
    {
      f = $0
      if (f ~ /^status=/)   f = "status=identified"
      if (td != "" && f ~ /^terms-delivered=/) { f = "terms-delivered=" td; tseen = 1 }
      if (f ~ /^agent_id=/) { f = "agent_id=" id; seen = 1 }
      if (pl != "" && f ~ /^launched_at=/) f = "launched_at=" pl
      if (ra != "" && f ~ /^restarted_at=/) { f = "restarted_at=" ra; rseen = 1 }
      printf "%s%s", (NR > 1 ? "|" : ""), f
    }
    END { if (!seen) printf "|agent_id=%s", id
          if (ra != "" && !rseen) printf "|restarted_at=%s", ra
          if (td != "" && !tseen) printf "|terms-delivered=%s", td }')
  printf '%s\n' "$IDENTIFIED" >> "$ROSTER_FILE" 2>/dev/null
  # Placed, so its clock file has done its work (T68): the start's question registrations read
  # the row above by its id.
  START_CLOCK_F=$(start_clock_path) && [ ! -L "$START_CLOCK_F" ] && rm -f "$START_CLOCK_F"

  # NO BOUND ON THE ROSTER, for the reason ARM 2 gives above: a roster row is a
  # contract, not a look, and eviction by recency cannot tell a finished agent
  # from a running one.
  exit 0
fi

# ============================================================
# ARM 1 — THE OBSERVATION RECORD IS GONE (epic-23 wave-15-fixit-182, REQ-2; ADR-028).
# ============================================================
#
# This arm read hooks/stop-check.sh's machine line out of a Bash tool response and wrote
# `.bionic/tmp/stop-check.state` — the record hooks/stop-guard.sh spent to admit a stop,
# under the D-1 freshness, D-2 consume, D-3 ownership and D-6 progress rules. All of it
# asserted things about the RECORD and none of it about the TARGET, and on 2026-09-15 the
# gate refused a correct stop with "no observation exists in this repo" because nobody had
# run the verb. The gate observes its target for itself now, through
# payload/scripts/lib/observe.sh, so there is nothing left for this script to record: one
# writer of a state nobody reads is a state that should not exist.
#
# WHAT STAYS ON THIS CHANNEL. The pressure sample above, which is a fact about a Bash call
# having happened rather than about what it printed. A Bash payload reaches this line with
# its sample already taken and nothing to do.
exit 0
