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
#                       full agent id and status `confirmed`.
#   SubagentStart     — the IDENTIFICATION arm (epic-16 wave-01; re-keyed in
#                       wave-03). When the agent itself starts, its TRANSCRIPT-form
#                       id is joined BY THAT ID onto the roster as an `identified`
#                       row. It used to join by name, off this payload's
#                       `agent_type` — which carries the subagent TYPE, so the join
#                       never matched (t4-probes-report.md §5.1).
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
# the duplicate-start check below. Sourcing is definitions only; the call is made on the
# SubagentStart path, and only when an id's last row already says it started.
# shellcheck source=/dev/null
. "$BIONIC_LIB/roster.sh"

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
  printf '%s\n' "$COMPLETED" >> "$ROSTER_FILE" 2>/dev/null

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
# a key — so this arm can no longer rescue a dispatch whose PostToolUse never
# fired. A TEAMMATE row is never identified at all, because ARM 2 deliberately
# leaves its `agent_id=` empty (the launch response carries only the ADDRESSING
# form, and writing that into `agent_id=` would turn every by-id wall's input from
# unknown into wrong). Both were ALREADY missing — a join on a field that carries
# no name matches nothing either — and what changes is that the miss is structural
# and visible instead of silent. The alternative, keeping a name join beside this
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
  case "$(sanitize "$START_TYPE" 200)" in
    bionic:*)
      SURVIVAL_FILE="$BIONIC_LIB/../../context/survival.md"
      if [ -r "$SURVIVAL_FILE" ]; then
        jq -cn --rawfile _sf_c "$SURVIVAL_FILE" \
          '{hookSpecificOutput:{hookEventName:"SubagentStart",additionalContext:$_sf_c}}' \
          2>/dev/null
      else
        echo "execution-recorder: survival terms not found at $SURVIVAL_FILE — printing nothing" >&2
      fi
      ;;
  esac

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
  # ---- BEGIN open-contract reading — the one close predicate, asked of one name (cross-gate §LC) ----
  if [ -n "$DUP_PRIOR" ]; then
    case "$DUP_PRIOR" in *"|name="*) DUP_NAME="${DUP_PRIOR#*|name=}"; DUP_NAME="${DUP_NAME%%|*}" ;; *) DUP_NAME="" ;; esac
    [ -n "$DUP_NAME" ] || DUP_NAME="(unnamed)"
    DUP_NAME="${DUP_NAME//$'\t'/ }"
    grep -qxF -- "$DUP_NAME" <<< "$(roster_open_names "$ROSTER_FILE" "$STATE_DIR/sweeper-${BIONIC_SID}.state" "$BIONIC_SID")" || DUP_PRIOR=""
  fi
  # ---- END open-contract reading ----
  if [ -n "$DUP_PRIOR" ]; then
    # EVERY FIELD CARRIED FORWARD, exactly as the identification below does: the row is a
    # CONTRACT, and a row that dropped a field would silently retract what it inherited.
    # Only `status=` moves, to a value no other reader recognises — which is deliberate:
    # every roster reader in the fleet filters by status, so a `duplicate-start` row is
    # inert to the budget, to the sweep and to both stop gates, and visible to the tick,
    # which is the one surface that should say something about it.
    printf '%s\n' "$DUP_PRIOR" | awk '
      BEGIN { RS = "|"; ORS = "" }
      { f = $0; sub(/\n$/, "", f)
        if (f ~ /^status=/) f = "status=duplicate-start"
        printf "%s%s", (NR > 1 ? "|" : ""), f }
      END { printf "\n" }' >> "$ROSTER_FILE" 2>/dev/null
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
  if [ -z "$ROW" ] && [ -n "$START_TYPE" ]; then
    while IFS= read -r line; do
      case "$line" in '#'*|'') continue ;; esac
      case "$line" in "roster-state/${ROSTER_VERSION}|"*) : ;; *) continue ;; esac
      # Superset prefilter, exactly as the id join above: in-shell, quoted so glob
      # metacharacters stay literal, and matching both the mid-row and end-of-row
      # forms rather than assuming the writer field order (checklist A6).
      case "$line" in
        *"|name=$START_TYPE"|*"|name=$START_TYPE|"*) : ;;
        *) continue ;;
      esac
      [ "$(line_field "$line" name)" = "$START_TYPE" ] || continue
      case "$(line_field "$line" status)" in intended|confirmed) : ;; *) continue ;; esac
      [ "$(line_field "$line" session)" = "$BIONIC_SID" ] || continue
      ROW="$line"
    done < "$ROSTER_FILE"
  fi
  [ -n "$ROW" ] || exit 0

  # S6 (AC-5, R6): THE RESUME CASE. `agent_id` here is the transcript form, and
  # a resume delivers this same event again for an id the roster already
  # carries — see prior_launch_for_agent() above (defined beside ROSTER_FILE).
  # On a first identification the id has never appeared before, so this is
  # empty and changes nothing; on a resume it recovers the ORIGINAL dispatch's
  # launch reference regardless of how many fresher rows now name the same id,
  # including one this very join just picked up.
  PRIOR_LAUNCH=$(prior_launch_for_agent "$START_ID")

  # `agent_id` is appended when the joined row has no such field and substituted
  # when it has one — ARM 2's rule for `teammate_id`, for ARM 2's reason: every
  # reader takes the FIRST match for a key, so a row carrying two of them would
  # answer with whichever the writer happened to put first. Today's writer always
  # emits the field, so the append branch is a belt against a writer that stops.
  IDENTIFIED=$(printf '%s' "$ROW" | awk -v id="$START_ID" -v pl="$PRIOR_LAUNCH" '
    BEGIN { RS = "|"; ORS = ""; seen = 0 }
    {
      f = $0
      if (f ~ /^status=/)   f = "status=identified"
      if (f ~ /^agent_id=/) { f = "agent_id=" id; seen = 1 }
      if (pl != "" && f ~ /^launched_at=/) f = "launched_at=" pl
      printf "%s%s", (NR > 1 ? "|" : ""), f
    }
    END { if (!seen) printf "|agent_id=%s", id }')
  printf '%s\n' "$IDENTIFIED" >> "$ROSTER_FILE" 2>/dev/null

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
