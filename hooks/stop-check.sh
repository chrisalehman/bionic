#!/bin/bash
# THE OBSERVATION — epic-15 wave-01R, AC-3.
#
# Run this before stopping a subagent:
#
#   bash ~/.claude/hooks/stop-check.sh <agent-name-or-id> [deliverable-path ...] [--progress <path>]
#
# It resolves the target against the metadata the platform writes to disk (P5/P6)
# and prints that agent's EVIDENCE TIER — working-log recency as absolute time
# and age, the agent's last message, repo activity, each contracted
# deliverable's existence and substance, and — when the work contract named a
# progress artifact — that artifact's own recency (D-6).
#
# IT DECIDES NOTHING. No verdict, no recommendation, no stop. The judgment stays
# with the reader; this command only makes the evidence visible. Its run is
# observed by hooks/stop-guard.sh's Bash arm, which records that an examination
# happened and what activity level it saw — so "I looked" becomes a fact rather
# than a memory (design/orchestrator-subagent-coordination.md §4).
#
# This is a PRODUCER, not a hook — it lives in hooks/ for test-harness pairing
# only. Producers may think and take seconds; gates may only read (§3.2).
# [WALL: hooks/stop-check.test.sh]
#
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

set -uo pipefail

MAX_MESSAGE_CHARS=600

usage() {  # [reason]
  [ -n "${1:-}" ] && echo "$1" >&2
  echo "Usage: bash ~/.claude/hooks/stop-check.sh <agent-name-or-id> [deliverable-path ...] [--progress <path>]" >&2
  echo "" >&2
  echo "Prints one subagent's evidence tier. Decides nothing." >&2
  exit 1
}

# ---------- arguments ----------
#
# TARGET FIRST, and no flag before it. This grammar is not a style choice: the
# Bash arm of hooks/stop-guard.sh re-parses this same command line to record
# WHICH agent was examined, and it reads only what is written here — it skips
# `-*` tokens one at a time and takes the first non-flag token, with no
# knowledge that `--progress` consumes the token after it. Accepting the flag
# ahead of the target therefore makes the two halves name DIFFERENT agents: the
# operator looks at one, the record attests to the other, and a record naming an
# unexamined agent is the stop wall opening on a look that never happened. The
# producer stays inside what its paired reader can parse; the agreement is
# pinned by tests/cross-gate-agreement.test.sh §C case 6.
#
# For the same reason an unrecognized `-`-leading token is a usage error rather
# than a deliverable path. `--progres` and `--progress=<path>` are the likely
# typos, and silently filing them under Deliverables prints an evidence tier
# missing a channel the reader believes they asked for.
#
# After the target, each non-flag argument is rotated to the back, so what
# survives the loop is the contracted deliverables in the order they were typed.
# ONE progress path, or nothing: a second flag makes "which artifact did the
# contract name?" a guess, and guessing about evidence is the failure this
# whole command exists to prevent. Written without arrays — bash 3.2 is what
# macOS ships, and an empty array under `set -u` is a crash there.
case "${1:-}" in
  "") usage ;;
  -*) usage "The target comes first: '$1' is an option, not an agent." ;;
esac
TARGET="$1"; shift

PROGRESS_PATH=""
PROGRESS_NAMED=0
ARGN=$#
while [ "$ARGN" -gt 0 ]; do
  arg="$1"; shift; ARGN=$((ARGN - 1))
  case "$arg" in
    --progress)
      [ "$PROGRESS_NAMED" -eq 0 ] || usage "Only one --progress path may be named; got a second."
      [ "$ARGN" -gt 0 ] || usage "--progress needs a path."
      PROGRESS_PATH="$1"; shift; ARGN=$((ARGN - 1)); PROGRESS_NAMED=1 ;;
    -*)
      usage "Unknown option: $arg" ;;
    *)
      set -- "$@" "$arg" ;;
  esac
done

# ---------- portable file facts ----------
# DELIBERATELY DUPLICATED in hooks/stop-guard.sh, byte for byte. A shared
# library is rejected by design (TDD §9): a sourced file the installer misses is
# a silently inert wall. The copies are held together by the N-way agreement
# suite, which drives every copy including this one.
file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
file_size()  { stat -f %z "$1" 2>/dev/null || stat -c %s "$1" 2>/dev/null || echo 0; }

fmt_epoch() {
  date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || printf 'epoch:%s\n' "$1"
}

fmt_age() {  # <seconds> -> "3m 12s"
  local s="$1"
  [ "$s" -lt 0 ] 2>/dev/null && s=0
  if   [ "$s" -lt 60 ];    then printf '%ds\n' "$s"
  elif [ "$s" -lt 3600 ];  then printf '%dm %ds\n' $((s / 60)) $((s % 60))
  elif [ "$s" -lt 86400 ]; then printf '%dh %dm\n' $((s / 3600)) $(((s % 3600) / 60))
  else                          printf '%dd %dh\n' $((s / 86400)) $(((s % 86400) / 3600))
  fi
}

# ---------- resolving the target (P5: the platform does not translate) ----------
#
# A typed reference is a NAME, an agent id, or `name@team` — all three are legal
# TaskStop inputs, and none of them is resolved for us. Comparison is LITERAL:
# a target string is never treated as a pattern.
# [WALL: hooks/stop-check.test.sh]

slugify() { printf '%s' "$1" | sed 's/[^a-zA-Z0-9]/-/g'; }

# WHERE CLAUDE CODE STORES SESSION AND PROJECT METADATA. One concept, three
# renderings in this wave, and they must name one directory: hooks/stop-guard.sh
# derives it from the payload's transcript path (it has one), hooks/preflight-probe.sh
# reads `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, and this producer has no payload
# so it must read the same variable. Rooting this at $HOME alone made the two
# sides name different directories the moment CLAUDE_CONFIG_DIR was set — the
# observation printed "unresolved" while the recorder wrote a record the stop
# gate then spent, which is the wall OPENING on a look that showed nothing
# (Step-6 critic, issue 1). Pinned by tests/cross-gate-agreement.test.sh §C,
# which runs with the two roots deliberately different.
PROJECTS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
TARGET_BASE="${TARGET%@*}"
[ -n "$TARGET_BASE" ] || TARGET_BASE="$TARGET"

scan_subagent_dirs() {  # <typed> <dir>...  -> "<agent-id>|<meta>|<subagents-dir>" per match
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

# Candidate project slugs, in order: the cwd, then the enclosing repo root.
# Claude Code names a project directory by slugifying its path — every
# non-alphanumeric character becomes a dash (confirmed against two verbatim
# captures in record/epic-15-kill-interception-experiment.md §1.1/§2.2).
CWD="$(pwd)"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
SLUGS="$(slugify "$CWD")"
if [ -n "$REPO_ROOT" ] && [ "$REPO_ROOT" != "$CWD" ]; then
  SLUGS="${SLUGS}
$(slugify "$REPO_ROOT")"
fi

IN_PROJECT_DIRS=""
while IFS= read -r slug; do
  [ -n "$slug" ] || continue
  for d in "$PROJECTS/$slug"/*/subagents; do
    [ -d "$d" ] && IN_PROJECT_DIRS="${IN_PROJECT_DIRS}${d}
"
  done
done <<< "$SLUGS"

OUT_OF_PROJECT=0
MATCHES=""
if [ -n "$IN_PROJECT_DIRS" ]; then
  # shellcheck disable=SC2086
  MATCHES=$(scan_subagent_dirs "$TARGET_BASE" $IN_PROJECT_DIRS)
fi

# Fallback: the fix command must work from ANY cwd (checklist A1), including
# one outside the project whose agents are being observed. A match found this
# way is reported with an explicit out-of-project note — never silently.
if [ -z "$MATCHES" ]; then
  ALL_DIRS=""
  for d in "$PROJECTS"/*/*/subagents; do
    [ -d "$d" ] && ALL_DIRS="${ALL_DIRS}${d}
"
  done
  if [ -n "$ALL_DIRS" ]; then
    # shellcheck disable=SC2086
    MATCHES=$(scan_subagent_dirs "$TARGET_BASE" $ALL_DIRS)
    [ -n "$MATCHES" ] && OUT_OF_PROJECT=1
  fi
fi

MATCH_COUNT=0
[ -n "$MATCHES" ] && MATCH_COUNT=$(printf '%s\n' "$MATCHES" | grep -c .)

echo "OBSERVATION — target as typed: ${TARGET}"

if [ "$MATCH_COUNT" -eq 0 ]; then
  echo "Resolved:      unresolved — no agent metadata under ${PROJECTS} answers to '${TARGET_BASE}'."
  echo ""
  echo "An unresolved target is not evidence of anything: the agent may never have"
  echo "existed, or the name may be misspelled. Check the name you launched it under."
  echo "This command decides nothing."
  exit 1
fi

if [ "$MATCH_COUNT" -gt 1 ]; then
  echo "Resolved:      ambiguous — ${MATCH_COUNT} agents answer to '${TARGET_BASE}':"
  while IFS='|' read -r id meta sub; do
    [ -n "$id" ] || continue
    sid="${sub%/subagents}"; sid="${sid##*/}"
    echo "  ${id}   (session ${sid})"
  done <<< "$MATCHES"
  echo ""
  echo "Name the agent by its id above. This command decides nothing."
  exit 1
fi

IFS='|' read -r AGENT_ID META SUBDIR <<< "$MATCHES"
SESSION_DIR="${SUBDIR%/subagents}"
SESSION_ID="${SESSION_DIR##*/}"
LOG="$SUBDIR/agent-${AGENT_ID}.jsonl"

AGENT_NAME=$(jq -r '.name // "—"' "$META" 2>/dev/null)
AGENT_TYPE=$(jq -r '.customAgentType // .agentType // "—"' "$META" 2>/dev/null)
AGENT_MODEL=$(jq -r '.model // "—"' "$META" 2>/dev/null)
AGENT_DESC=$(jq -r '.description // "—"' "$META" 2>/dev/null)

echo "Resolved:      ${AGENT_ID}"
echo "               name: ${AGENT_NAME} · type: ${AGENT_TYPE} · model: ${AGENT_MODEL}"
echo "               task: ${AGENT_DESC}"
echo "Session:       ${SESSION_ID}"
if [ "$OUT_OF_PROJECT" -eq 1 ]; then
  echo "Note:          this agent was found outside this project's own directory."
fi
echo ""

# ---------- evidence 1: the working log (§2.2 — unfakeable, written by working) ----------
echo "Working log:   ${LOG}"
if [ -f "$LOG" ]; then
  LOG_MTIME=$(file_mtime "$LOG")
  LOG_SIZE=$(file_size "$LOG")
  NOW=$(date -u +%s)
  echo "  last write:  $(fmt_epoch "$LOG_MTIME")  (age $(fmt_age $((NOW - LOG_MTIME))))"
  echo "  size:        ${LOG_SIZE} bytes"
  LAST_MSG=$(tail -400 "$LOG" 2>/dev/null \
    | jq -R -r 'fromjson? | select(.type=="assistant")
                | ((.message.content // []) | map(select(.type=="text").text) | join(" "))
                | select(length > 0)' 2>/dev/null \
    | tail -1)
  if [ -n "$LAST_MSG" ]; then
    echo "  last message: ${LAST_MSG:0:$MAX_MESSAGE_CHARS}"
  else
    echo "  last message: (none yet — no assistant text in the last 400 lines)"
  fi
else
  echo "  last write:  (no working log on disk yet)"
fi
echo ""

# ---------- evidence 2: repo activity ----------
echo "Repo activity:"
if [ -n "$REPO_ROOT" ]; then
  echo "  root:        ${REPO_ROOT}"
  echo "  HEAD:        $(git -C "$REPO_ROOT" log -1 --format='%h %s' 2>/dev/null)"
  echo "  uncommitted: $(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | grep -c .) path(s)"
else
  echo "  (cwd is not inside a git repository — no repo evidence available)"
fi
echo ""

# ---------- evidence 3: the contracted deliverables (§2.2 — meaning from the contract) ----------
echo "Deliverables:"
if [ "$#" -eq 0 ]; then
  echo "  (none named on the command line — pass each contracted path as an argument)"
else
  NOW=$(date -u +%s)
  for d in "$@"; do
    if [ -f "$d" ]; then
      DSIZE=$(file_size "$d"); DMTIME=$(file_mtime "$d")
      if [ "$DSIZE" -eq 0 ]; then
        echo "  ${d} — PRESENT but EMPTY, 0 bytes"
      else
        echo "  ${d} — PRESENT, ${DSIZE} bytes, last write $(fmt_epoch "$DMTIME") (age $(fmt_age $((NOW - DMTIME))))"
      fi
    elif [ -d "$d" ]; then
      echo "  ${d} — PRESENT as a directory, $(find "$d" -type f 2>/dev/null | grep -c .) file(s)"
    else
      echo "  ${d} — ABSENT"
    fi
  done
fi

# ---------- evidence 4: the progress artifact (D-6 — the task's own byproducts) ----------
#
# An hour-long command silences the working log for its whole hour: one tool
# call, one result at the end. "No activity for 47 minutes" therefore describes
# a healthy suite and a wedged one identically, and no amount of reading the
# agent will separate them. The separation lives one level DOWN, in the work's
# own byproducts: a contract that requires the long command to accrue output at
# a named path turns "log quiet 47 minutes, progress file grew 12 seconds ago"
# into proof of life (design/orchestrator-subagent-coordination.md §5 D-6).
#
# Printed only when the contract named a path — the section is additive, and
# without the flag this command's output is what it always was.
if [ "$PROGRESS_NAMED" -eq 1 ]; then
  echo ""
  echo "-- progress artifact (D-6) --"
  if [ -e "$PROGRESS_PATH" ]; then
    PMTIME=$(file_mtime "$PROGRESS_PATH")
    PSIZE=$(file_size "$PROGRESS_PATH")
    NOW=$(date -u +%s)
    echo "progress: ${PROGRESS_PATH}  last-write $(fmt_epoch "$PMTIME") ($(fmt_age $((NOW - PMTIME))) ago)  size ${PSIZE}B"
  else
    echo "progress: ${PROGRESS_PATH}  ABSENT"
  fi
fi

echo ""
echo "This command decides nothing. It prints evidence; the judgment is yours."
exit 0
