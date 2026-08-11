#!/bin/bash
# THE STOP GATE — epic-15 wave-01R, extended at wave-03 slice 4/6. ONE
# registration, PreToolUse|TaskStop. A stop during an active wave is permitted
# only against an observation that is:
#
#   OURS      — this session's (D-1), and the STOPPER'S OWN look, not another
#               actor's borrowed one (D-3, slice 4/6);
#   FRESH     — on both activity channels: the target's working log (D-1) and,
#               where the work contract named one, its progress artifact (D-6,
#               slice 4/6);
#   SPENT     — one observation discharges exactly one stop (D-2).
#
# And it is a stop of an agent THIS SESSION LAUNCHED. A target the session roster
# does not record is refused when addressed by name and permitted when addressed
# by full agent id (AC-6, slice 4/6) — a name is not an identity.
#
# Why a gate at all: a stop is irreversible, and the failure mode it guards is
# the orchestrator's own judgment lapsing mid-drift — so the guarantee cannot
# live in the orchestrator's context (design/orchestrator-subagent-coordination.md
# §3.1). The gate reads state and decides; it never judges. Every judgment
# belongs upstream, in the observation.
#
# THIS SCRIPT NO LONGER WRITES THE RECORDS IT SPENDS (slice 4/4). It used to
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
# FAIL DIRECTIONS (TDD §7, pinned by hooks/stop-guard.test.sh):
#   - the gate is OPEN and SILENT before the active-wave verdict (an
#     unconfigured machine is not a stop decision);
#   - the gate is CLOSED and LOUD after it (irreversibility: the ambiguous case
#     is exactly what the wall exists for).
#
# Exit code 2 = block the tool call entirely in Claude Code hooks.
# [WALL: hooks/stop-guard.test.sh]
#
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

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
OBSERVE_CMD="bash ~/.claude/hooks/stop-check.sh"
ORDER_CMD="bash ~/.claude/hooks/stop-orders.sh order"
# HOW LONG A HUMAN'S STOP ORDER IS CURRENT. Duplicated as a literal from its WRITER,
# hooks/stop-orders.sh, and held to it by tests/cross-gate-agreement.test.sh §M, which
# places an order either side of this boundary and asks this gate about it. See the
# discharge block below for why an instruction gets a clock when evidence never does.
ORDER_TTL_SECONDS=1800

INPUT=$(cat)
_jq() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

TOOL_NAME=$(_jq '.tool_name')

# ---------- portable file facts ----------
# DELIBERATELY DUPLICATED from hooks/stop-check.sh, byte for byte. A shared
# library is rejected by design (TDD §9): a sourced file the installer misses is
# a silently inert wall. The copies are held together by the resolver agreement
# battery in tests/cross-gate-agreement.test.sh §C, which drives both copies —
# the observation's and this one — over one fixture world.
file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
file_size()  { stat -f %z "$1" 2>/dev/null || stat -c %s "$1" 2>/dev/null || echo 0; }

# Resolve a typed reference (a name, an agent id, or `name@team` — all legal
# TaskStop inputs, none of them resolved for us, P5) against on-disk metadata.
# Second copy of hooks/stop-check.sh's resolver, same deliberate duplication.
# Comparison is LITERAL: a target string is never treated as a pattern.
# The two copies are driven against one fixture world by
# tests/cross-gate-agreement.test.sh §C, which asks the observation and this gate
# the same resolution question about the same typed name.
scan_subagent_dirs() {  # <typed> <dir>... -> "<agent-id>|<meta>|<subagents-dir>" per match
  local typed="$1"; shift
  local sub meta base id name
  for sub in "$@"; do
    [ -d "$sub" ] || continue
    for meta in "$sub"/agent-*.meta.json; do
      [ -f "$meta" ] || continue
      base="${meta##*/}"; base="${base%.meta.json}"; id="${base#agent-}"
      name=$(jq -r '.name // empty' "$meta" 2>/dev/null)
      if [ "$id" = "$typed" ] || { [ -n "$name" ] && [ "$name" = "$typed" ]; }; then
        printf '%s|%s|%s\n' "$id" "$meta" "$sub"
      fi
    done
  done
}

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

# HAS THE ORCHESTRATOR CLOSED THIS ROW? DELIBERATELY DUPLICATED, byte for byte, into
# hooks/stop-guard.sh and hooks/landing-gate.sh — the TDD's §9 convention, for its reason:
# a sourced library the installer misses is a silently inert wall. The three copies are
# held together by tests/cross-gate-agreement.test.sh's stop-arc section, which drives all
# three over one ledger written by the real `session-sweeper.sh ack`.
#
# It reads the sweeper's ledger rather than its verdict because ack is invisible to
# `verdict` BY DESIGN (a contract is met by artifacts or it is not, which is what lets an
# ack over an UNMET row warn instead of quietly erasing the discrepancy). Whole-name match,
# never a substring: `w4-s1` must not be closed by an ack of `w4-s10`.
ledger_acked() {  # <ledger-file> <name> -> 0 when an ack closed that row
  local f="$1" want="$2" line n
  [ -n "$want" ] || return 1
  [ -L "$f" ] && return 1
  [ -f "$f" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "sweeper-ledger/v1|"*) : ;; *) continue ;; esac
    case "$line" in *"|event=ack|"*) : ;; *) continue ;; esac
    n=$(printf '%s' "$line" | tr '|' '\n' | grep '^name=' | head -1 | cut -d= -f2-)
    [ -n "$n" ] && [ "$n" = "$want" ] && return 0
  done < "$f"
  return 1
}
record_version() { printf '%s' "$1" | cut -d'|' -f1; }

state_paths() {  # <repo> -> echoes "<state-dir>|<state-file>"; nonzero if unsafe
  local repo="$1"
  # A hostile repo controls its own .bionic/ contents (TDD §8). A symlink at
  # any level lets a repo choose which file this gate reads its evidence out of —
  # the OPEN direction, which §8 forbids a repo from reaching. Refuse rather than
  # follow: this gate refuses the stop, which is the safe side.
  [ -L "$repo/.bionic" ] && return 1
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

CWD=$(_jq '.cwd')
[ -n "$CWD" ] || exit 0
REPO=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$REPO" ] || exit 0

# One of four copies of active-wave detection (dispatch-preflight, the evidence
# gate and execution-recorder hold the others). Deliberately duplicated per TDD §9
# and held together by the N-way agreement suite, which drives all four.
resolve_docs_root() {
  local proj="$1" config="$1/.bionic/config.yaml" override
  if [ -f "$config" ]; then
    override=$(grep -E '^[[:space:]]*docs-root[[:space:]]*:' "$config" 2>/dev/null \
      | head -1 \
      | sed -E 's/^[[:space:]]*docs-root[[:space:]]*:[[:space:]]*//' \
      | sed -E "s/^['\"]//;s/['\"]\$//" \
      | sed -E 's/[[:space:]]+$//')
    if [ -n "$override" ]; then
      case "$override" in
        /*) echo "$override" ;;
        *)  echo "$proj/$override" ;;
      esac
      return
    fi
  fi
  echo "$proj/.bionic/docs"
}

DOCS_ROOT=$(resolve_docs_root "$REPO")
PLAN=""
for d in "$DOCS_ROOT/plans" "$DOCS_ROOT/incidents"; do
  [ -d "$d" ] || continue
  while IFS= read -r -d '' f; do
    if [ -z "$PLAN" ] || [ "$f" -nt "$PLAN" ]; then PLAN="$f"; fi
  done < <(find "$d" -maxdepth 2 -type f -name '*.md' -print0 2>/dev/null)
done
[ -n "$PLAN" ] && [ -f "$PLAN" ] || exit 0

# The run-state marker, read exactly as the evidence gate reads it: the
# fence-aware ## SDLC State section, then its `current:` value.
#
# Line endings are TRANSLATED, never deleted. `tr -d '\r'` collapses a CR-only
# file to a single line, every line-anchored match misses, and this gate would
# then go silently inert on a repo with a live wave — the fail-dangerous shape
# that bypassed the evidence gate for a whole wave (.claude/rules/hook-authoring.md).
CURRENT=$(awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$PLAN" 2>/dev/null | awk '
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  /^## SDLC State/ { flag=1; next }
  /^## / { flag=0 }
  flag' \
  | grep -E '^[[:space:]]*current[[:space:]]*:' \
  | head -1 \
  | sed -E 's/^[[:space:]]*current[[:space:]]*:[[:space:]]*//' \
  | tr -d '[:space:]')
echo "$CURRENT" | grep -qE '^([0-9]+[ab]?|T[0-9]+)$' || exit 0

# ---------- after the verdict: CLOSED and LOUD ----------

RAW=$(_jq '.tool_input.task_id')

# THE ACTOR REQUESTING THIS STOP (D-3, slice 4/6). A subagent-invoked payload
# carries a top-level `agent_id`; the orchestrator's does not (slice 4/1 probe,
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

deny() {  # <reason line>...
  echo "BLOCKED: a stop needs a fresh observation of its target — a wave is active." >&2
  echo "" >&2
  local line
  for line in "$@"; do echo "$line" >&2; done
  echo "" >&2
  # Runnable AS PRINTED: a blocked orchestrator pastes this line verbatim, and
  # bracketed placeholders on it became three positional arguments the
  # observation reported as absent deliverables (Step-6 review R2). The optional
  # arguments are described beneath the command, never inside it.
  echo "Fix: ${OBSERVE_CMD} ${FIX_TARGET}${FIX_EXTRA}" >&2
  echo "     (pass each contracted deliverable path as a further argument)" >&2
  echo "Then read what it prints, and stop again if the evidence supports it." >&2
  echo "One observation discharges exactly one stop (D-2), and it goes stale the" >&2
  echo "moment the target writes again (D-1)." >&2
  echo "" >&2
  # THE OTHER TWO WAYS PAST THIS GATE, named at the refusal because a wall that only
  # names its ceremony teaches the ceremony. A landed contract needs neither of them —
  # this gate never asked in the first place.
  echo "If a human ordered this stop, it executes — record the order and stop again:" >&2
  echo "     ${ORDER_CMD} ${FIX_TARGET}" >&2
  echo "A stop the human performs themselves does not reach this gate at all." >&2
  exit 2
}

[ -n "$RAW" ] || deny "The stop names no target: tool_input.task_id is empty."

SID=$(_jq '.session_id')
[ -n "$SID" ] || deny "This stop request carries no session key, so no observation can be proven mine."

TRANSCRIPT=$(_jq '.transcript_path')
SUB=$(session_subagents_dir "$TRANSCRIPT") \
  || deny "This stop request carries no usable transcript path, so its session's agents cannot be resolved."

MATCHES=$(scan_subagent_dirs "${RAW%@*}" "$SUB")
MATCH_COUNT=0
[ -n "$MATCHES" ] && MATCH_COUNT=$(printf '%s\n' "$MATCHES" | grep -c .)

if [ "$MATCH_COUNT" -eq 0 ]; then
  # Naming the SCOPE is what makes this refusal clearable (Step-6 review R4).
  # Resolution is this session's own agents; a target another session launched
  # resolves for the observation — which scans the whole project — and never
  # here, so without this clause the named fix succeeds and the stop refuses
  # identically forever, with nothing in the message naming the way out.
  deny "Target '${RAW}' is unresolved: no agent in THIS session's metadata answers to it." \
       "The platform hands this gate the name AS TYPED and resolves nothing for it (P5)." \
       "Resolution is scoped to agents this session launched — one session cannot stop" \
       "another's tasks, so no observation can discharge this. If the agent belongs to a" \
       "different session, stop it from there, or stop it yourself (a human-initiated stop" \
       "bypasses this gate). Otherwise check the name against what you launched it under."
fi
if [ "$MATCH_COUNT" -gt 1 ]; then
  deny "Target '${RAW}' is ambiguous: ${MATCH_COUNT} agents in this session answer to it." \
       "Name the agent by its id — the observation prints every candidate."
fi

IFS='|' read -r AGENT_ID META SUBDIR <<< "$MATCHES"
LOG="$SUBDIR/agent-${AGENT_ID}.jsonl"

PATHS=$(state_paths "$REPO") \
  || deny "The observation state path is a symlink; nothing here will read or write through it."
STATE_DIR="${PATHS%|*}"; STATE_FILE="${PATHS#*|}"

# ---------- AC-6: what this session did not launch, it does not stop BY NAME ----------
#
# A NAME IS NOT AN IDENTITY. It is chosen by the operator, reused across waves,
# and written to disk by every session that ever ran here — which is how a dead
# epic-14 fleet came to answer to the names a live session was still using
# (the bb20f616 exhibit, continuation.md §carry-overs). The identity is the
# metadata's own filing: the platform writes an agent's metadata under the
# subagents directory of the session that launched it, and nothing else writes
# there, so "this session launched it" is a fact on disk rather than a memory.
# A target filed under another session is NOT OURS, and stopping it by name is
# refused.
#
# THE FULL AGENT ID IS THE ESCAPE HATCH, and it is not a loophole: an id is
# unambiguous by construction, so naming one is a statement about a particular
# agent rather than a guess that resolved. Refusing those too would outlaw the
# documented zombie-predecessor cleanup (by-id stops after a /clear); the design
# rejected both "warn but allow" and "refuse always" for exactly this pair of
# reasons. A by-id stop still needs a fresh observation like any other.
#
# WHAT IDENTITY IS, corrected in slice 4/9: the metadata's own filing. An agent
# under <session>/subagents/ was launched by <session>. Slice 4/6 keyed this on
# ROSTER MEMBERSHIP and live operation broke both arms — unconfirmed rows (every
# row, until a session restarts after the recorder ships) matched by NAME and
# handed ownership to another session's corpse, while every agent dispatched
# before the roster hook shipped had no row and was refused as foreign. The
# roster keeps the job it can do: it carries the CONTRACT, and ownership by id is
# established by a `confirmed` OR `identified` row carrying a NON-EMPTY `agent_id`
# — in teammate mode the transcript-form id lands on the `identified` row while
# the `confirmed` row's `agent_id=` is empty by design (the detail below says
# why). It is never a name-oracle again. Read the way hooks/stop-check.sh reads
# it, deliberately duplicated per TDD §9 and driven over one fixture world by
# tests/cross-gate-agreement.test.sh §F.
#
# WHAT THIS CHECK STILL GUARDS, named honestly because it is narrower than what
# the roster rule claimed to guard: resolution here is already scoped to
# ${transcript}/subagents, so a target outside this session's own directory can
# only resolve when the payload's transcript path and its session key DISAGREE.
# That disagreement is precisely what a name-keyed rule could not see, and it is
# the one way the bb20f616 collision reaches this gate rather than the
# observation (whose scan is project-wide, which is where it did fire).
AGENT_NAME=$(jq -r '.name // empty' "$META" 2>/dev/null)
OWNING_SID="${SUBDIR%/subagents}"; OWNING_SID="${OWNING_SID##*/}"
ROSTER_FILE="$STATE_DIR/roster-${SID}.state"
ROSTER_ROW=""
ROSTER_ID_MATCH=""
if [ -f "$ROSTER_FILE" ] && [ ! -L "$ROSTER_FILE" ]; then
  ROW_BY_ID=""; ROW_BY_NAME=""
  while IFS= read -r rline; do
    case "$rline" in '#'*|'') continue ;; esac
    case "$rline" in "roster-state/${ROSTER_VERSION}|"*) : ;; *) continue ;; esac
    rid=$(record_field "$rline" agent_id)
    rname=$(record_field "$rline" name)
    # `confirmed` or `identified`, never merely non-empty — the same accepted set
    # as hooks/stop-check.sh's copy, for the same reasons.
    #
    # NOT `intended` (Step-6 review C-2): the comment above always stated the
    # invariant this way, while the code leaned on hooks/dispatch-preflight.sh
    # emitting `agent_id=` empty on `intended` rows to keep it true. Here the gap
    # is a wall, not a display — an intended row carrying an id walked a foreign
    # agent past the ownership rule.
    #
    # BUT `identified` TOO (epic-16 wave-01 slice 1), because `confirmed` alone
    # is a set no teammate row can satisfy BY ID. The launch response carries
    # only the addressing form `name@session-xxxx`, so hooks/execution-recorder.sh
    # writes `agent_id=` EMPTY on a confirmed teammate row by design; the
    # transcript-form id — the only form this gate ever resolves a target to —
    # arrives one state later, from SubagentStart. Without this the rule was
    # unreachable for every interactive dispatch this repo makes, while the
    # suite's async-shaped fixtures kept it looking alive.
    if [ -n "$rid" ] && [ "$rid" = "$AGENT_ID" ]; then
      case "$(record_field "$rline" status)" in
        confirmed|identified) ROW_BY_ID="$rline" ;;
      esac
    fi
    [ -n "$rname" ] && [ "$rname" = "$AGENT_NAME" ] && ROW_BY_NAME="$rline"
  done < "$ROSTER_FILE"
  ROSTER_ID_MATCH="$ROW_BY_ID"
  ROSTER_ROW="${ROW_BY_ID:-$ROW_BY_NAME}"
fi

# HOW THE OPERATOR ADDRESSES THIS AGENT, in a form the platform's stop primitive accepts
# (epic-16 wave-02 slice S3, from field data 2026-08-11). The launch response hands back
# `name@session-xxxxxxxx` and that is what TaskStop takes for a teammate; the
# TRANSCRIPT-form id this gate resolves to (`aname-<hex>`) is a THIRD namespace that
# nothing bridges (capture probe §3-D/§5). So the refusal below used to name a way out the
# operator could not type — it cost four calls and an ambiguity round to stop one finished,
# verified, acked agent. The roster's recorded teammate address wins; the constructed form
# is the fallback, built from the OWNING session because that is the session the address
# names.
ROSTER_TEAMMATE=$(record_field "$ROSTER_ROW" teammate_id)
STOP_ADDRESS="$ROSTER_TEAMMATE"
if [ -z "$STOP_ADDRESS" ]; then
  STOP_ADDRESS="${AGENT_NAME:-$AGENT_ID}@session-$(printf '%s' "$OWNING_SID" | cut -c1-8)"
fi

# IS THE TYPED REFERENCE AN IDENTITY, or a name that happened to resolve? The distinction
# is the whole of the AC-6 rule below, and until now only one spelling of an identity
# existed here. `name@session-xxxxxxxx` is the other, and it is an identity by the same
# argument the raw id is: it carries the launching session, so it cannot silently mean a
# different agent that reused the name. It is accepted only when the session it names is
# the one the target is actually filed under (or the one the roster recorded for it) — a
# suffix naming any other session is a guess wearing an id's shape, and stays a name.
typed_is_identity() {
  [ "$RAW" = "$AGENT_ID" ] && return 0
  case "$RAW" in *@*) : ;; *) return 1 ;; esac
  [ -n "$ROSTER_TEAMMATE" ] && [ "$RAW" = "$ROSTER_TEAMMATE" ] && return 0
  local base="${RAW%@*}" suffix="${RAW##*@}" want
  [ "$base" = "$AGENT_ID" ] || { [ -n "$AGENT_NAME" ] && [ "$base" = "$AGENT_NAME" ]; } || return 1
  case "$suffix" in session-*) : ;; *) return 1 ;; esac
  want="${suffix#session-}"
  [ -n "$want" ] || return 1
  case "$OWNING_SID" in "$want"*) return 0 ;; esac
  return 1
}

if [ "$OWNING_SID" != "$SID" ] && [ -z "$ROSTER_ID_MATCH" ]; then
  # FOREIGN or DEAD HISTORY, by the OWNING session's transcript — the same
  # existence check hooks/stop-check.sh, hooks/preflight-probe.sh and
  # hooks/dispatch-preflight.sh already make, so the operator reads one
  # vocabulary across all four. It answers whether that session's transcript
  # file still exists, and nothing about whether the agent is running, which is
  # why neither label says `live` any more (slice 4/9).
  if [ -f "${SUBDIR%/subagents}.jsonl" ]; then
    CLASSIFICATION="FOREIGN"
    WHOSE="that session's transcript is still on disk, which says nothing about whether the agent is running"
  else
    CLASSIFICATION="DEAD HISTORY"
    WHOSE="that session's transcript is gone — this is history's agent, not yours"
  fi
  if ! typed_is_identity; then
    # The way out is the id, so the id is what the Fix line observes.
    FIX_TARGET="$AGENT_ID"
    deny "Target '${RAW}' was not launched by this session: ${CLASSIFICATION}." \
         "Its metadata is filed under session ${OWNING_SID}, not this one (${SID}), and" \
         "${WHOSE}." \
         "A NAME is not an identity — it is reused across waves and written to disk by every" \
         "session that ever ran here, which is how a dead fleet came to answer to live names." \
         "Address it by an IDENTITY instead. Either of these is unambiguous by construction," \
         "and the first is the form the stop primitive takes for a teammate:" \
         "    ${STOP_ADDRESS}" \
         "    ${AGENT_ID}" \
         "(A by-id stop still needs a fresh observation of its own.)"
  fi
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
#                 machine-visible artifact, which is the job it exists for.
#   MET/WAIVED  — the contract landed, or was explicitly waived at dispatch.
#
# WHAT DOES NOT: a MET over a row that DECLARED NOTHING. The verb calls such a row MET
# correctly — it names nothing to hold the agent to — but that is an absence of a contract,
# not a landing, and discharging on it would open the gate for every contract-less
# dispatch on a fact nobody produced. AC-1 spells MET as "artifact delivered"; ack closes
# the rest. Nothing else changes: a live agent with an unmet contract meets the same arc
# it met before, which is what Sections 4–10 of the suite still pin.

SWEEPER="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/session-sweeper.sh"
LEDGER_FILE="$STATE_DIR/sweeper-${SID}.state"
ORDERS_FILE="$STATE_DIR/stop-orders-${SID}.state"

V_TAKEN=0; V_STATE=""; V_DETAIL=""
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
  out=$( cd "$REPO" 2>/dev/null || exit 9
         CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER" verdict "$AGENT_NAME" 2>/dev/null )
  line=$(printf '%s\n' "$out" | grep -F 'landing-verdict/v1|' | head -1)
  [ -n "$line" ] || return 0
  V_STATE=$(record_field "$line" state)
  V_DETAIL=$(record_field "$line" detail)
  return 0
}

# A HUMAN'S ORDER, and the one clock in this gate that belongs. D-1 refuses to put a window
# on EVIDENCE, and that refusal stands: an observation is stale the moment its subject
# writes, however recent, and good however old while the subject is dormant. An INSTRUCTION
# is the other kind of thing — it is current when it is given and it stops being current,
# and a standing order would open this gate for a name some later dispatch reuses. The
# window is generous, the fail direction is the closed one (an expired order leaves the
# ceremony exactly where it was), and the writer is hooks/stop-orders.sh.
order_current() {
  local f="$ORDERS_FILE" line t e now delta
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
    [ "$delta" -le "$ORDER_TTL_SECONDS" ] && [ "$delta" -ge -60 ] && return 0
  done < "$f"
  return 1
}

if order_current; then
  take_verdict
  # ONE LINE, and it is information rather than a verdict on the operator. R3: a
  # user-ordered stop executes at once; what an unmet contract earns is a sentence naming
  # what is being given up, never a refusal.
  if [ -z "$V_STATE" ]; then
    echo "STOP ORDERED — executing. No contract row of this name is on the session roster." >&2
  elif [ "$V_STATE" = "MET" ] || [ "$V_STATE" = "WAIVED" ]; then
    echo "STOP ORDERED — executing. Its contract stands ${V_STATE}: nothing is given up." >&2
  else
    echo "STOP ORDERED — executing. Contract ${V_STATE}, giving up: ${V_DETAIL}" >&2
  fi
  exit 0
fi

ledger_acked "$LEDGER_FILE" "$AGENT_NAME" && exit 0

take_verdict
case "$V_STATE" in
  WAIVED) exit 0 ;;
  MET)    [ -n "$(record_field "$ROSTER_ROW" deliverable)" ] && exit 0 ;;
esac

[ -f "$STATE_FILE" ] \
  || deny "No observation has been recorded in this repo at all."

# Find this target's record. A record for the target under another session key
# or another schema version is reported for what it is — never guessed at.
RECORD=""; FOREIGN=""; BAD_VERSION=""
while IFS= read -r line; do
  case "$line" in '#'*|'') continue ;; esac
  [ "$(record_field "$line" target)" = "$AGENT_ID" ] || continue
  if [ "$(record_version "$line")" != "$STATE_VERSION" ]; then
    BAD_VERSION=$(record_version "$line"); continue
  fi
  if [ "$(record_field "$line" session)" != "$SID" ]; then
    FOREIGN=$(record_field "$line" session); continue
  fi
  RECORD="$line"
done < "$STATE_FILE"

if [ -z "$RECORD" ]; then
  [ -n "$BAD_VERSION" ] && deny \
    "The only observation of '${RAW}' carries schema version '${BAD_VERSION}', which this gate does not read." \
    "A record it cannot read is a record it will not trust. Observe again."
  [ -n "$FOREIGN" ] && deny \
    "The only observation of '${RAW}' was recorded by a different session (${FOREIGN})." \
    "Another session's look is not evidence that I looked."
  deny "No observation of '${RAW}' (${AGENT_ID}) has been recorded by this session."
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
  deny "The observation of '${RAW}' records no observer, so it cannot be shown to be yours." \
       "A look nobody signed is not evidence that YOU looked (D-3). Observe again."
fi
if [ "$REC_OBSERVER" != "$ACTOR" ]; then
  deny "The observation of '${RAW}' was made by a different actor." \
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
  deny "The observation of '${RAW}' recorded a different working log than the one that resolves now." \
       "Something about this target's identity changed since you looked."
fi

if [ "$NOW_MTIME" != "$REC_MTIME" ] || [ "$NOW_SIZE" != "$REC_SIZE" ]; then
  deny "'${RAW}' has written to its working log SINCE your observation, so that observation is stale." \
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
# observation already resolved it under the precedence slice 4/5 fixed (an
# explicit --progress overrides the roster's row), and re-deriving it here would
# be a second parser answering the same question — the F-1 divergence class this
# wave closed elsewhere. What the roster is still consulted for is the one thing
# the record cannot say: that a contracted channel was never looked at at all.
#
# A relative path is resolved against the REPO ROOT, which is where the contract
# is written from and where the observation runs; the resolved path is printed in
# the refusal so the comparison is never a hidden one.
REC_PROGRESS=$(record_field "$RECORD" progress)
REC_PMTIME=$(record_field "$RECORD" progress_mtime)
REC_PSTATE=$(record_field "$RECORD" progress_state)

abs_progress() {  # <path> -> absolute
  case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$REPO" "$1" ;; esac
}

case "$REC_PSTATE" in
  present|absent)
    if [ -n "$REC_PROGRESS" ]; then
      PROG_ABS=$(abs_progress "$REC_PROGRESS")
      NOW_PSTATE="absent"; NOW_PMTIME=0
      if [ -e "$PROG_ABS" ]; then NOW_PSTATE="present"; NOW_PMTIME=$(file_mtime "$PROG_ABS"); fi
      if [ "$NOW_PSTATE" != "$REC_PSTATE" ] || [ "$NOW_PMTIME" != "$REC_PMTIME" ]; then
        deny "'${RAW}' has written to its contracted PROGRESS ARTIFACT since your observation," \
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
        deny "The work contract for '${RAW}' names a progress artifact your observation never looked at." \
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
    deny "The observation record could not be consumed (the state lock at $STATE_DIR could not be taken), and an unconsumed record would discharge a second stop." \
         "Either another writer holds it, or this repo's .bionic/tmp is not writable by you."
  fi
  sleep 0.1 2>/dev/null || sleep 1
done

TMP=$(mktemp "$STATE_DIR/.stop-check.XXXXXX" 2>/dev/null) || {
  rm -rf "$LOCK"
  deny "The observation record could not be consumed (no writable temp file), and an unconsumed record would discharge a second stop."
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
  deny "The observation record could not be consumed (the state file could not be replaced), and an unconsumed record would discharge a second stop."
}
rm -rf "$LOCK"

exit 0
