#!/bin/bash
# THE START GATE — epic-15 wave-01R.
#
# PreToolUse|Agent. On every subagent dispatch, during an active wave: refuse
# unless a this-session environment attestation is present, naming the exact
# fix command. Outside an active wave, or on any ambiguity along the way,
# the dispatch passes through untouched — this gate never blocks a machine
# that isn't running a wave, and never blocks on a question it cannot
# answer cleanly.
#
# Why a gate at all: the environment check (hooks/preflight-probe.sh) proves,
# once per session, that a fleet has what it needs to survive — a
# credential, a writable repo, a writable state directory. A fleet inherits
# its environment and dies collectively if that proof never happened
# (design/orchestrator-subagent-coordination.md §3.4 "Starting"). This
# gate's entire vocabulary is: read the attestation, allow silently or
# refuse loudly naming the fix. It parses no check detail — the
# attestation's EXISTENCE, keyed to THIS session, is the whole verdict
# (§4 "The start gate"); this gate never re-derives or second-guesses what
# the producer already decided.
#
# FAIL DIRECTIONS (TDD §7, pinned by hooks/dispatch-preflight.test.sh):
#   - not an Agent-tool call                            -> pass, silent  (A7 relevance hoist)
#   - cwd/repo unresolvable                              -> pass, silent (ambiguity)
#   - no active wave                                     -> pass, silent (nothing to decide)
#   - payload carries no session_id                      -> pass, silent (§7 table: start=open)
#   - attestation missing, unreadable, symlinked, or
#     keyed to a different session (foreign)              -> REFUSE, naming the fix command
#   - attestation present and keyed to THIS session_id    -> pass, silent
#
# Exit code 2 = block the tool call entirely in Claude Code hooks.
# [WALL: hooks/dispatch-preflight.test.sh]
#
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

set -uo pipefail

PREFLIGHT_CMD="bash ~/.claude/hooks/preflight-probe.sh"
STATE_REL=".bionic/tmp/preflight.state"

INPUT=$(cat)
_jq() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

# ---------- relevance first (checklist A7): the cheapest possible check,
# before any git resolution or plan-directory walk. Anything that isn't a
# subagent dispatch is none of this gate's business. ----------
TOOL_NAME=$(_jq '.tool_name')
[ "$TOOL_NAME" = "Agent" ] || exit 0

# ---------- ambiguity: cannot even locate the repo -> OPEN, silent ----------
CWD=$(_jq '.cwd')
[ -n "$CWD" ] || exit 0
REPO=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$REPO" ] || exit 0

# ---------- active-wave detection ----------
# DELIBERATELY DUPLICATED, byte for byte where the logic overlaps, from
# hooks/stop-guard.sh's copy (stop-guard and the evidence gate hold the
# others). A shared library is rejected by design (TDD §9): a sourced file
# the installer misses is a silently inert wall. The copies are held
# together by the N-way agreement suite (slice 4/6), which drives all three
# including the evidence gate as the origin.
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

# The run-state marker, read exactly as the evidence gate and stop-guard read
# it: the fence-aware ## SDLC State section, then its `current:` value.
# Line endings TRANSLATED, never deleted — see .claude/rules/hook-authoring.md
# (a CR-only file deleted by `tr -d '\r'` collapses to one line and every
# line-anchored match misses, going silently inert with a wave live).
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

# ---------- a wave is active: this IS a decision ----------

# Payload missing its session key: the §7 fail-direction table names this
# exact ambiguity and pins the start-side direction as open, silent — we
# cannot prove whose dispatch this is, so we cannot refuse it as foreign.
PAYLOAD_SID=$(_jq '.session_id')
[ -n "$PAYLOAD_SID" ] || exit 0

deny() {  # <reason line>...
  echo "BLOCKED: this subagent start needs a this-session environment attestation — a wave is active." >&2
  echo "" >&2
  local line
  for line in "$@"; do echo "$line" >&2; done
  echo "" >&2
  echo "Fix: ${PREFLIGHT_CMD}" >&2
  echo "Then retry the dispatch." >&2
  exit 2
}

STATE_FILE="$REPO/$STATE_REL"

# A symlink ANYWHERE on the attestation path is never followed — a hostile repo
# can AIM or CLOSE this wall but must not be able to OPEN it by planting content
# at a path it controls (design §8). The DIRECTORY levels matter as much as the
# file: `.bionic/tmp` pointed at a tree holding a valid same-session attestation
# (one session working across a repo and its `.worktrees/` siblings produces
# exactly that) would otherwise admit a dispatch on an environment proof taken
# for a different tree — and this gate deliberately parses no check detail (§4),
# so the record's own `repo=` field never exposes the mismatch. Checklist A3
# names this class; it was discharged for the WRITE path only. The sibling stop
# gate refuses at all three levels (hooks/stop-guard.sh's state_paths()); these
# are the same three. Treated the same as "missing": refuse.
if [ -L "$REPO/.bionic" ] || [ -L "$REPO/.bionic/tmp" ] \
   || [ -L "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
  deny "No environment attestation was found for this repo."
fi

# Read by KEY, never by position (checklist A6) — mirrors the producer's own
# readback. This gate parses no check detail beyond the session key: the
# attestation's existence, keyed to THIS session, is the whole verdict
# (§4 "The start gate").
#
# So the record's `version=` line is written and never read here, while the
# observation schema's version IS enforced by its reader, which refuses loudly on
# an unknown one. The asymmetry is deliberate, not drift (Step-6 review D5): each
# side follows the direction §7 assigns it. A start gate that refused an
# unrecognised attestation version would be a false block on every session after
# a schema bump — the expensive direction here — while an unreadable observation
# record must refuse a stop, because that side's ambiguity is what the wall is
# for. Recorded in the spec's ownership table beside both schema rows.
ATTESTED_SID=$(grep -m1 '^session_id=' "$STATE_FILE" 2>/dev/null | cut -d= -f2-)
if [ -z "$ATTESTED_SID" ] || [ "$ATTESTED_SID" != "$PAYLOAD_SID" ]; then
  deny "The attestation on disk is not this session's (foreign, or not a valid attestation record)." \
       "It may have been written by a different session, or the record could not be read."
fi

# Present and mine: pass in silence. Never print on the allow path (§4 "The
# start gate": "Parses no check detail... Never: print on the allow path.").
exit 0
