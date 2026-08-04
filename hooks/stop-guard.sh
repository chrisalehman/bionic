#!/bin/bash
# THE STOP GATE — epic-15 wave-01R. ONE script, TWO registrations:
#
#   PreToolUse|Bash     — the RECORDER arm. When the orchestrator runs
#                         hooks/stop-check.sh, this records that an examination
#                         happened and what activity level it saw. It NEVER
#                         blocks anything, under any condition.
#   PreToolUse|TaskStop — the GATE arm. A stop during an active wave is
#                         permitted only against a fresh observation of that
#                         target from this session (D-1), and one observation
#                         discharges exactly one stop (D-2).
#
# Why a gate at all: a stop is irreversible, and the failure mode it guards is
# the orchestrator's own judgment lapsing mid-drift — so the guarantee cannot
# live in the orchestrator's context (design/orchestrator-subagent-coordination.md
# §3.1). The gate reads state and decides; it never judges. Every judgment
# belongs upstream, in the observation.
#
# FAIL DIRECTIONS (TDD §7, pinned by hooks/stop-guard.test.sh):
#   - the recorder arm never blocks, ever;
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
OBSERVE_CMD="bash ~/.claude/hooks/stop-check.sh"

INPUT=$(cat)
_jq() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

TOOL_NAME=$(_jq '.tool_name')

# ---------- portable file facts ----------
# DELIBERATELY DUPLICATED from hooks/stop-check.sh, byte for byte. A shared
# library is rejected by design (TDD §9): a sourced file the installer misses is
# a silently inert wall. The copies are held together by the N-way agreement
# suite, which drives every copy including the origin.
file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
file_size()  { stat -f %z "$1" 2>/dev/null || stat -c %s "$1" 2>/dev/null || echo 0; }

# Resolve a typed reference (a name, an agent id, or `name@team` — all legal
# TaskStop inputs, none of them resolved for us, P5) against on-disk metadata.
# Second copy of hooks/stop-check.sh's resolver, same deliberate duplication.
# Comparison is LITERAL: a target string is never treated as a pattern.
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
# can only stop its own tasks — and it is the same scoping on both arms, so the
# recorder and the gate agree by construction.
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

state_paths() {  # <repo> -> echoes "<state-dir>|<state-file>"; nonzero if unsafe
  local repo="$1"
  # A hostile repo controls its own .bionic/ contents (TDD §8). A symlink at
  # either level redirects our write outside the repo — the proven
  # arbitrary-file-overwrite shape from the discarded run's review. Refuse
  # rather than follow; refusing to RECORD only makes the later stop refuse.
  [ -L "$repo/.bionic" ] && return 1
  [ -L "$repo/.bionic/tmp" ] && return 1
  local dir="$repo/.bionic/tmp"
  [ -L "$dir/stop-check.state" ] && return 1
  printf '%s|%s\n' "$dir" "$dir/stop-check.state"
}

# ============================================================
# ARM 1 — the RECORDER (PreToolUse|Bash). Never blocks.
# ============================================================

if [ "$TOOL_NAME" = "Bash" ]; then
  CMD=$(_jq '.tool_input.command')

  # RELEVANCE FIRST, before anything expensive. This arm is registered on every
  # Bash call on the machine; the discarded run did a full plan-directory walk
  # (jq + git + find, unbounded with plan count) on all of them before checking
  # whether the command was even related (checklist A7). One fixed-string grep
  # is the whole hot path for every unrelated command.
  printf '%s' "$CMD" | grep -qF 'stop-check.sh' || exit 0

  SID=$(_jq '.session_id')
  TRANSCRIPT=$(_jq '.transcript_path')
  CWD=$(_jq '.cwd')
  [ -n "$SID" ] && [ -n "$TRANSCRIPT" ] && [ -n "$CWD" ] || exit 0

  SUB=$(session_subagents_dir "$TRANSCRIPT") || exit 0
  REPO=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
  [ -n "$REPO" ] || exit 0
  PATHS=$(state_paths "$REPO") || exit 0
  STATE_DIR="${PATHS%|*}"; STATE_FILE="${PATHS#*|}"

  is_interpreter() {
    case "${1##*/}" in
      bash|sh|zsh|dash|ksh|env|exec|command|nohup|time) return 0 ;;
      *) return 1 ;;
    esac
  }

  # Write one observation under a lock. Read-modify-write on shared state races
  # otherwise (checklist A4), and the temp file must carry an unpredictable name
  # (checklist A2) — a predictable one plus a planted symlink was a proven
  # arbitrary-file overwrite.
  write_record() {  # <session> <target-id> <typed> <log> <mtime> <size>
    local sid="$1" tid="$2" typed="$3" log="$4" mt="$5" sz="$6"
    case "$sid$tid$typed$log" in *'|'*) return 0 ;; esac
    mkdir -p "$STATE_DIR" 2>/dev/null || return 0

    local lock="$STATE_DIR/.stop-check.lock" tries=0
    while ! mkdir "$lock" 2>/dev/null; do
      tries=$((tries + 1))
      # A lock left behind by a killed writer must not wall recording forever.
      if [ "$tries" -gt 20 ]; then
        local age now
        now=$(date -u +%s); age=$((now - $(file_mtime "$lock")))
        [ "$age" -gt 30 ] && rm -rf "$lock" 2>/dev/null && continue
        return 0
      fi
      sleep 0.1 2>/dev/null || sleep 1
    done

    local tmp
    tmp=$(mktemp "$STATE_DIR/.stop-check.XXXXXX" 2>/dev/null) || { rm -rf "$lock"; return 0; }
    {
      printf '# bionic observation records — schema stop-check-state/%s\n' "$STATE_VERSION"
      # One live record per (session, target): re-observing REPLACES, so a
      # second stop can never find a second copy of the same look.
      if [ -f "$STATE_FILE" ]; then
        while IFS= read -r line; do
          case "$line" in '#'*|'') continue ;; esac
          [ "$(record_field "$line" session)" = "$sid" ] \
            && [ "$(record_field "$line" target)" = "$tid" ] && continue
          printf '%s\n' "$line"
        done < "$STATE_FILE"
      fi
      printf '%s|session=%s|target=%s|typed=%s|log=%s|mtime=%s|size=%s\n' \
        "$STATE_VERSION" "$sid" "$tid" "$typed" "$log" "$mt" "$sz"
    } > "$tmp" 2>/dev/null
    mv -f "$tmp" "$STATE_FILE" 2>/dev/null || rm -f "$tmp"
    rm -rf "$lock"
    return 0
  }

  record_observation() {  # <typed>
    local typed="$1" matches count id meta sub log mt=0 sz=0
    matches=$(scan_subagent_dirs "${typed%@*}" "$SUB")
    [ -n "$matches" ] || return 0
    count=$(printf '%s\n' "$matches" | grep -c .)
    [ "$count" -eq 1 ] || return 0
    IFS='|' read -r id meta sub <<< "$matches"
    log="$sub/agent-${id}.jsonl"
    if [ -f "$log" ]; then mt=$(file_mtime "$log"); sz=$(file_size "$log"); fi
    write_record "$SID" "$id" "$typed" "$log" "$mt" "$sz"
  }

  # WHAT COUNTS AS A RUN. `stop-check.sh` must appear as a COMMAND WORD — first
  # token of a segment, or immediately after an interpreter. `cat hooks/stop-check.sh`,
  # `grep -n stop-check.sh …` and a commented-out line all MENTION it without
  # running it, and recording those would manufacture an examination that never
  # happened — the "recorded a look but nothing ran" class the redesign exists
  # to close (checklist §C).
  while IFS= read -r segment; do
    [ -n "$segment" ] || continue
    set -f; set -- $segment; set +f
    [ "$#" -gt 0 ] || continue
    case "$1" in '#'*) continue ;; esac
    pos=0; prev=""
    while [ "$#" -gt 0 ]; do
      pos=$((pos + 1))
      if [ "${1##*/}" = "stop-check.sh" ] && { [ "$pos" -eq 1 ] || is_interpreter "$prev"; }; then
        shift
        while [ "$#" -gt 0 ]; do
          case "$1" in -*) shift; continue ;; esac
          record_observation "$1"
          break
        done
        break
      fi
      prev="$1"; shift
    done
  done <<< "$(printf '%s' "$CMD" | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g; s/|/\n/g')"

  exit 0
fi

# ============================================================
# ARM 2 — the GATE (PreToolUse|TaskStop).
# ============================================================

[ "$TOOL_NAME" = "TaskStop" ] || exit 0

# ---------- before the verdict: OPEN and SILENT ----------

CWD=$(_jq '.cwd')
[ -n "$CWD" ] || exit 0
REPO=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$REPO" ] || exit 0

# Third copy of active-wave detection (dispatch-preflight and the evidence gate
# hold the others). Deliberately duplicated per TDD §9 and held together by the
# N-way agreement suite, which drives all three including the evidence gate.
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

deny() {  # <reason line>...
  echo "BLOCKED: a stop needs a fresh observation of its target — a wave is active." >&2
  echo "" >&2
  local line
  for line in "$@"; do echo "$line" >&2; done
  echo "" >&2
  echo "Fix: ${OBSERVE_CMD} ${RAW:-<agent-name-or-id>} [each contracted deliverable]" >&2
  echo "Then read what it prints, and stop again if the evidence supports it." >&2
  echo "One observation discharges exactly one stop (D-2), and it goes stale the" >&2
  echo "moment the target writes again (D-1). Human-initiated stops bypass this gate." >&2
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
  deny "Target '${RAW}' is unresolved: no agent in this session's metadata answers to it." \
       "The platform hands this gate the name AS TYPED and resolves nothing for it (P5)."
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
       "Its evidence tier now includes work you have not seen — which may be the very work a stop would destroy." \
       "This is an activity boundary, not a timer: an agent dormant since your look stays stoppable however long ago it was."
fi

# ---------- D-2: consume on stop ----------
#
# One observation is evidence about one target at one moment. Letting the record
# ride for repeated stops re-admits staleness through the side door, so it is
# spent here, before the stop happens. A REFUSED stop consumes nothing: every
# path above exits without touching the file.

LOCK="$STATE_DIR/.stop-check.lock"
tries=0
while ! mkdir "$LOCK" 2>/dev/null; do
  tries=$((tries + 1))
  if [ "$tries" -gt 20 ]; then
    now=$(date -u +%s)
    if [ $((now - $(file_mtime "$LOCK"))) -gt 30 ]; then rm -rf "$LOCK" 2>/dev/null; continue; fi
    deny "The observation record could not be consumed (state is locked), and an unconsumed record would discharge a second stop."
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
mv -f "$TMP" "$STATE_FILE" 2>/dev/null || rm -f "$TMP"
rm -rf "$LOCK"

exit 0
