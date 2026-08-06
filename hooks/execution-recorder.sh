#!/bin/bash
# THE EXECUTION-CONFIRMATION RECORDER — epic-15 wave-03, slice 4/4.
#
# ONE script, TWO registrations, one job: write down what ACTUALLY RAN.
#
#   PostToolUse|Bash  — the OBSERVATION arm. When hooks/stop-check.sh has run and
#                       printed its machine line, that line becomes the record a
#                       later stop spends (target, activity level, observer).
#   PostToolUse|Agent — the ROSTER arm. When a dispatch has actually spawned, the
#                       session roster's `intended` row is completed with the
#                       full agent id and status `confirmed`.
#
# WHY POSTTOOLUSE IS THE WHOLE POINT. Both facts this script records are claims
# that something HAPPENED, and a PreToolUse hook cannot make either one: it fires
# before the tool runs and never learns whether it ran, succeeded, or was blocked
# further down the pipeline. The predecessor recorded observations from
# PreToolUse|Bash by re-parsing the command TEXT with a grammar of its own, and
# paid for it twice — once when the two grammars diverged and the record named an
# agent the operator had not examined (Step-6 review F-1), and once as the
# standing residual where a refused or mistyped command still left a record
# behind (tests/cross-gate-agreement.test.sh §C case 6, critic finding A). Both
# defects are the same defect: a second reader guessing at what the first one
# did. Here there is no second reader. The observation prints one machine line on
# its success path and this script copies it; a command that was refused, that
# exited non-zero, or that merely MENTIONS stop-check.sh prints no such line and
# leaves nothing behind. Slice 4/1's probe confirmed the harness never fires this
# event for a call it blocked pre-dispatch, so the gating is the platform's, not
# ours (record/w3-slice1-posttooluse-probe.md §5).
#
# IT NEVER BLOCKS — PostToolUse cannot: the tool has already run. Every failure
# path here therefore exits 0 having recorded nothing, and the cost lands where
# §7 puts it: an unwritten observation refuses a stop that one re-observation
# immediately re-arms, and an uncompleted roster row stays `intended`, which is
# exactly the signal that a dispatch never spawned.
#
# INERT OUTSIDE AN ACTIVE WAVE, like every other gate in this family, and inert
# in one cheap test before that: anything that is not this script's business
# leaves after a single fixed-string grep.
#
# [WALL: hooks/execution-recorder.test.sh]
#
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

set -uo pipefail

STATE_VERSION="v1"
# The most records the observation state may retain (inherited bound, Step-6
# review P2): every stop walks this file line by line, so its length is a cost
# each one pays. Fail-closed — a dropped record refuses a stop that one
# re-observation re-arms.
MAX_RECORDS=200
# The producer's schema token, matched as a FIXED STRING and anchored at
# line start. hooks/stop-check.sh owns the other half of this constant; the two
# are held together by tests/cross-gate-agreement.test.sh §C case 6, which drives
# the real producer's real output into this script.
MACHINE_SCHEMA="stop-check-observation/v1"
ROSTER_VERSION="v1"

INPUT=$(cat)
_jq() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

TOOL_NAME=$(_jq '.tool_name')
case "$TOOL_NAME" in Bash|Agent) : ;; *) exit 0 ;; esac

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

STDOUT=""
MLINES=""
if [ "$TOOL_NAME" = "Bash" ]; then
  # A Bash tool_response is an object carrying stdout/stderr (slice 4/1 capture
  # A); a failed call can hand back a bare string instead, and `tostring` keeps
  # that case parseable rather than crashing jq. Only STDOUT is searched — the
  # machine line is printed there, and searching stderr would let a quoted error
  # message masquerade as evidence.
  STDOUT=$(printf '%s' "$INPUT" \
    | jq -r 'if (.tool_response | type) == "object" then (.tool_response.stdout // "")
             else (.tool_response // "" | tostring) end' 2>/dev/null)
  MLINES=$(printf '%s\n' "$STDOUT" | grep "^${MACHINE_SCHEMA}|")
  # THE RESIDUAL, stated rather than claimed away: stdout is not a trusted
  # channel — a command that PRINTS a well-formed machine line produces a record
  # without any observation having run. It is a strictly smaller residual than
  # the one it replaces (the predecessor recorded on any command line that merely
  # named a live agent, including refused ones), and it is not reachable by
  # mistake: forging one means typing the schema token, the resolved agent id and
  # that agent's current log mtime and size, all of which the gate re-checks
  # against the live file before it discharges anything.
  [ -n "$MLINES" ] || exit 0
else
  AGENT_ID=$(_jq '.tool_response.agentId')
  TOOL_USE_ID=$(_jq '.tool_use_id')
  [ -n "$AGENT_ID" ] && [ -n "$TOOL_USE_ID" ] || exit 0
fi

CWD=$(_jq '.cwd')
[ -n "$CWD" ] || exit 0
REPO=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$REPO" ] || exit 0

SID=$(_jq '.session_id')
[ -n "$SID" ] || exit 0

# ---------- active-wave detection ----------
# FOURTH copy (dispatch-preflight, stop-guard and the evidence gate hold the
# others), deliberately duplicated per TDD §9 and held together by the N-way
# agreement suite. Line endings are TRANSLATED, never deleted: `tr -d '\r'`
# collapses a CR-only file to one line, every line-anchored match misses, and
# this script would go silently inert with a wave live
# (.claude/rules/hook-authoring.md).
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

# ---------- state paths ----------
#
# A hostile repo controls its own .bionic/ contents (TDD §8). A symlink at any
# level redirects our write outside the repo — the proven arbitrary-file-overwrite
# shape. Refuse rather than follow; refusing to RECORD only makes the later stop
# refuse, which is the safe direction.
STATE_DIR="$REPO/.bionic/tmp"
STATE_FILE="$STATE_DIR/stop-check.state"
ROSTER_FILE="$STATE_DIR/roster-${SID}.state"
[ -L "$REPO/.bionic" ] && exit 0
[ -L "$STATE_DIR" ] && exit 0

# ============================================================
# ARM 2 — the ROSTER (PostToolUse|Agent).
# ============================================================
#
# The launch half wrote an `intended` row at PreToolUse, keyed by `tool_use_id`
# because no agent id exists yet at that moment (slice 4/3). This event carries
# the same `tool_use_id` and, in `tool_response.agentId`, the id that row was
# waiting for — slice 4/1 capture E confirms the pair, in both dispatch modes.
#
# COMPLETION IS AN APPEND, NOT A REWRITE. The launch half appends without a lock
# by design (a lock in front of a dispatch is a wedgeable failure mode on the
# fail-open side), so a read-modify-write here would silently drop any row a
# concurrent dispatch appended between our read and our rename. The completed row
# is instead appended, and a reader takes the LAST row for a `tool_use_id` — the
# fold is one line of shell and it costs a race nothing. Nothing is written from
# memory: every field is either copied verbatim from the intended row on disk or
# read out of this payload.
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
    [ "$(line_field "$line" tool_use_id)" = "$TOOL_USE_ID" ] || continue
    [ "$(line_field "$line" status)" = "intended" ] || continue
    [ "$(line_field "$line" session)" = "$SID" ] || continue
    ROW="$line"
  done < "$ROSTER_FILE"
  [ -n "$ROW" ] || exit 0

  # A `|` reaching here would forge a field. The id comes from the platform and
  # the row from our own launch half, so this is a belt rather than a repair.
  case "$AGENT_ID" in *'|'*) exit 0 ;; esac

  # Substitute the two fields that execution confirms, leaving every other field
  # of the launched row — the contract state especially — where the brief put it,
  # so the completed row is self-sufficient for a consumer that reads only it.
  COMPLETED=$(printf '%s' "$ROW" | awk -v id="$AGENT_ID" '
    BEGIN { RS = "|"; ORS = "" }
    {
      f = $0
      if (f ~ /^status=/)   f = "status=confirmed"
      if (f ~ /^agent_id=/) f = "agent_id=" id
      printf "%s%s", (NR > 1 ? "|" : ""), f
    }')
  printf '%s\n' "$COMPLETED" >> "$ROSTER_FILE" 2>/dev/null
  exit 0
fi

# ============================================================
# ARM 1 — the OBSERVATION (PostToolUse|Bash).
# ============================================================

[ -L "$STATE_FILE" ] && exit 0

TRANSCRIPT=$(_jq '.transcript_path')
SUB=$(session_subagents_dir "$TRANSCRIPT") || exit 0

# THE OBSERVER (slice 4/1, assumption A resolved FULL). A top-level `agent_id` is
# present on subagent-invoked payloads and absent on the orchestrator's — that is
# the entire discriminator, and it is positive rather than inferential: present
# means "this subagent made the call, and here is which one". Absence is rendered
# as a literal token rather than an empty value so a consumer never has to decide
# whether a blank means "the orchestrator" or "the field was not written" — the
# same absence-is-its-own-field rule the roster row follows. Agent ids are
# `a`-prefixed hex (capture B/F), so the token cannot collide with one.
OBSERVER=$(_jq '.agent_id')
[ -n "$OBSERVER" ] || OBSERVER="orchestrator"
case "$OBSERVER" in *'|'*) exit 0 ;; esac

# Write one observation under a lock. Read-modify-write on shared state races
# otherwise (checklist A4), and the temp file must carry an unpredictable name
# (checklist A2) — a predictable one plus a planted symlink was a proven
# arbitrary-file overwrite.
write_record() {  # <target-id> <typed> <log> <mtime> <size> <deliverables> <progress> <progress-mtime> <progress-state> <classification> <deliverable-source> <progress-source>
  local tid="$1" typed="$2" log="$3" mt="$4" sz="$5" dl="$6" pp="$7" pm="$8" ps="$9"
  local cl="${10}" dsrc="${11}" psrc="${12}"
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0

  local lock="$STATE_DIR/.stop-check.lock" tries=0 reclaimed=0
  while ! mkdir "$lock" 2>/dev/null; do
    tries=$((tries + 1))
    # A lock left behind by a killed writer must not wall recording forever — but
    # the reclaim gets exactly ONE go, and only against a lock that is actually
    # there. `mkdir` also fails for reasons no reclaim can fix (an unwritable
    # state directory, repo-controlled), and `rm -rf` of an ABSENT path SUCCEEDS,
    # so an unbounded reclaim-and-retry loop spins forever (Step-6 review S2/A3).
    if [ "$tries" -gt 20 ]; then
      local age now
      if [ "$reclaimed" -eq 0 ] && [ -d "$lock" ]; then
        now=$(date -u +%s); age=$((now - $(file_mtime "$lock")))
        if [ "$age" -gt 30 ]; then
          reclaimed=1; tries=0
          rm -rf "$lock" 2>/dev/null
          continue
        fi
      fi
      return 0   # this script never blocks — it simply records nothing
    fi
    sleep 0.1 2>/dev/null || sleep 1
  done

  local tmp
  tmp=$(mktemp "$STATE_DIR/.stop-check.XXXXXX" 2>/dev/null) || { rm -rf "$lock"; return 0; }
  {
    printf '# bionic observation records — schema stop-check-state/%s\n' "$STATE_VERSION"
    # One live record per (session, target): re-observing REPLACES, so a second
    # stop can never find a second copy of the same look.
    #
    # Two bounds beyond that, both fail-closed — a dropped record refuses a stop
    # that a re-observation immediately re-arms:
    #   * records whose session's subagents directory is gone are inert (the gate
    #     resolves targets only through that directory) and are dropped;
    #   * the survivors are capped, oldest first.
    if [ -f "$STATE_FILE" ]; then
      {
        while IFS= read -r line; do
          case "$line" in '#'*|'') continue ;; esac
          [ "$(line_field "$line" session)" = "$SID" ] \
            && [ "$(line_field "$line" target)" = "$tid" ] && continue
          local rlog rdir
          rlog=$(line_field "$line" log); rdir="${rlog%/agent-*}"
          [ -n "$rdir" ] && [ ! -d "$rdir" ] && continue
          printf '%s\n' "$line"
        done < "$STATE_FILE"
      } | tail -n "$((MAX_RECORDS - 1))"
    fi
    # The first six fields are byte-identical in name to the schema the stop gate
    # already reads; `observer` and the D-6 progress snapshot are additive, and
    # the gate's by-key reader is inert to fields it does not know (checklist A6),
    # which is why this is still `v1` rather than a version bump that would refuse
    # every record until its reader caught up. Slice 4/5 adds `classification` and
    # the two contract-source fields the same way — copied verbatim from the
    # producer's own machine line, additive, still `v1`.
    printf '%s|session=%s|target=%s|typed=%s|log=%s|mtime=%s|size=%s|observer=%s|deliverables=%s|progress=%s|progress_mtime=%s|progress_state=%s|classification=%s|deliverable_source=%s|progress_source=%s\n' \
      "$STATE_VERSION" "$SID" "$tid" "$typed" "$log" "$mt" "$sz" "$OBSERVER" "$dl" "$pp" "$pm" "$ps" "$cl" "$dsrc" "$psrc"
  } > "$tmp" 2>/dev/null
  mv -f "$tmp" "$STATE_FILE" 2>/dev/null || rm -f "$tmp"
  rm -rf "$lock"
  return 0
}

# One record per machine line: a single Bash call may chain two observations, and
# each one printed its own line.
while IFS= read -r mline; do
  [ -n "$mline" ] || continue
  M_TARGET=$(line_field "$mline" target)
  M_LOG=$(line_field "$mline" log)
  [ -n "$M_TARGET" ] && [ -n "$M_LOG" ] || continue

  # A session can only stop its own tasks, so a record the gate could never match
  # is not worth writing — and one written for another session's agent would
  # claim evidence about work this session cannot act on. The observation
  # deliberately resolves more widely than that (it must work from any cwd and
  # reports out-of-project matches explicitly); this is where that wider view
  # stops being dischargeable evidence.
  case "$M_LOG" in "$SUB"/*) : ;; *) continue ;; esac

  M_MTIME=$(line_field "$mline" mtime); M_SIZE=$(line_field "$mline" size)
  case "$M_MTIME" in ''|*[!0-9]*) continue ;; esac
  case "$M_SIZE"  in ''|*[!0-9]*) continue ;; esac

  write_record "$M_TARGET" "$(line_field "$mline" typed)" "$M_LOG" \
    "$M_MTIME" "$M_SIZE" "$(line_field "$mline" deliverables)" \
    "$(line_field "$mline" progress)" "$(line_field "$mline" progress_mtime)" \
    "$(line_field "$mline" progress_state)" \
    "$(line_field "$mline" classification)" \
    "$(line_field "$mline" deliverable_source)" \
    "$(line_field "$mline" progress_source)"
done <<< "$MLINES"

exit 0
