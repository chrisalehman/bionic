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
# observed by hooks/execution-recorder.sh's PostToolUse|Bash arm, which reads the
# MACHINE LINE this command prints on its success path and turns it into the
# record a later stop spends — so "I looked" becomes a fact rather than a memory
# (design/orchestrator-subagent-coordination.md §4).
#
# THE MACHINE LINE IS THE ONLY THING THE RECORDER READS (slice 4/4). It is
# printed on the SUCCESS path and nowhere else: a usage error, an unresolved
# target and an ambiguous target all exit non-zero having printed no such line,
# so a run that showed the operator no evidence tier leaves nothing behind that
# a stop could spend. That is the whole of the C6 closure — the recorder no
# longer re-parses this command's ARGUMENTS with a second grammar (the F-1
# divergence class), it reads this command's own OUTPUT.
#
# This is a PRODUCER, not a hook — it lives in hooks/ for test-harness pairing
# only. Producers may think and take seconds; gates may only read (§3.2).
# [WALL: tests/stop-check.test.sh]
#
# Registered on no channel — invoked on demand from the mounted plugin payload.

set -uo pipefail

# THIS SCRIPT'S OWN PATH, so the usage it prints names the copy the operator actually
# invoked — identical in a repo checkout, in a bootstrap-installed ~/.claude/hooks/, and in
# an installed plugin payload. Deliberately NOT ${CLAUDE_PLUGIN_ROOT}: this script is run by
# hand and by the harness outside any plugin context, where that variable does not exist.
HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -n "$HOOK_DIR" ] || HOOK_DIR="$(dirname "$0")"

MAX_MESSAGE_CHARS=600

# The machine line's schema token. Versioned so the recorder can refuse a shape
# it does not read rather than guess at it, and greppable as a fixed string so
# the recorder's hot path is one `grep -F` on every Bash call in the session.
MACHINE_SCHEMA="stop-check-observation/v1"

usage() {  # [reason]
  [ -n "${1:-}" ] && echo "$1" >&2
  echo "Usage: bash ${HOOK_DIR}/stop-check.sh <agent-name-or-id> [deliverable-path ...] [--progress <path>]" >&2
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
# whole command exists to prevent. An EMPTY value is a missing one — a token
# following the flag is not a path that was named, and `--progress "$PROG"`
# with PROG unset would otherwise print an authoritative ABSENT for an artifact
# nobody contracted, which is the false negative D-6 exists to prevent. Written without arrays — bash 3.2 is what
# macOS ships, and an empty array under `set -u` is a crash there.
case "${1:-}" in
  "") usage ;;
  -*) usage "The target comes first: '$1' is an option, not an agent." ;;
esac
TARGET="$1"; shift

PROGRESS_PATH=""
PROGRESS_NAMED=0
CLAIMS_PATTERN=""
CLAIMS_NAMED=0
ARGN=$#
while [ "$ARGN" -gt 0 ]; do
  arg="$1"; shift; ARGN=$((ARGN - 1))
  case "$arg" in
    --progress)
      [ "$PROGRESS_NAMED" -eq 0 ] || usage "Only one --progress path may be named; got a second."
      [ "$ARGN" -gt 0 ] || usage "--progress needs a path."
      [ -n "$1" ] || usage "--progress needs a path."
      PROGRESS_PATH="$1"; shift; ARGN=$((ARGN - 1)); PROGRESS_NAMED=1 ;;
    --claims)
      # P2 (Liveness contract, ratified 2026-08-05): a subprocess claim is a
      # PATTERN, checked for existence only — same grammar as --progress, and
      # for the same reason (the target-first rule above is what the recorder
      # can parse; a flag anywhere else would be unparseable by it too).
      [ "$CLAIMS_NAMED" -eq 0 ] || usage "Only one --claims pattern may be named; got a second."
      [ "$ARGN" -gt 0 ] || usage "--claims needs a pattern."
      [ -n "$1" ] || usage "--claims needs a pattern."
      CLAIMS_PATTERN="$1"; shift; ARGN=$((ARGN - 1)); CLAIMS_NAMED=1 ;;
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

# One field out of a versioned pipe-delimited line, BY KEY, never by position
# (checklist A6). DELIBERATELY DUPLICATED from hooks/execution-recorder.sh, which
# reads the session roster with the identical function — the two copies are held
# together by tests/cross-gate-agreement.test.sh. This copy reads the roster row
# for classification and contract state (slice 4/5); it never writes one.
line_field() {  # <line> <key>
  printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-
}

# Existence only, for P2 (Liveness contract). `pgrep -f` matches the full
# command line; a `ps` fallback covers a machine without it.
claims_live() {  # <pattern> -> 0 if a process matches, 1 otherwise
  local pat="$1"
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -f -- "$pat" >/dev/null 2>&1
    return $?
  fi
  ps -eo command 2>/dev/null | grep -qF -- "$pat"
}

# The machine line is pipe-delimited key=value, like the observation record it
# becomes and like the roster row (hooks/dispatch-preflight.sh). A `|`, a newline
# or a control character inside a VALUE would forge a field, and every value here
# is operator-supplied — the typed target, the deliverable paths, the progress
# path. They are normalized rather than refused: this command's job is to print
# evidence, and a target with an odd character in it is still a target the
# operator asked about.
mline_value() {  # <value>
  printf '%s' "$1" | tr '\n\r\t|' '    ' | sed -e 's/[[:cntrl:]]/ /g' -e 's/  */ /g' \
    -e 's/^ *//' -e 's/ *$//' | cut -c 1-400
}

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
# [WALL: tests/stop-check.test.sh]

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

# ---------- resolving a contracted path (epic-17 W6 S15, A-6.6 (c)) ----------
#
# WHAT WAS WRONG. The paths this command stats — the deliverables, and the `--progress`
# artifact — arrive as brief prose, and the spelling every slice brief in this epic uses is
# `record/epic-NN-wM/x.md`, because that is the form the Step-5 contract and
# `canonical-sdlc-evidence-gate.sh` publish for an artifact under the docs root. This
# command resolved nothing at all: a relative path was stat'd against whatever directory
# the observer happened to be standing in, so a present progress file read `absent` and a
# landed deliverable read `ABSENT` — an observation that decides nothing, deciding wrongly.
#
# THE RULE IS THE EVIDENCE GATE'S, and so is the body of both functions below: they are
# `resolve_docs_root()` and `resolve_walk_path()` copied whole, held to one text by
# tests/cross-gate-agreement.test.sh. `PROJECT_DIR` and `DOCS_ROOT` carry the gate's names
# for the same reason. The VALUE of PROJECT_DIR is this command's own — the repo it was run
# from, falling back to the cwd when that is not a repository, which is the root every
# other path in this file is already read against.
#
# WHAT IS STILL NOT JUDGED. Resolution is not a verdict. A path that climbs out with `..`
# resolves and is reported like any other: §4's rule is that this command decides nothing,
# and refusing a contract here would be deciding. The landing gate is where a deliverable
# is judged, and hooks/session-sweeper.sh refuses `..` there.
resolve_docs_root() {
  local proj="$1"
  local config="$proj/.bionic/config.yaml"
  if [ -f "$config" ]; then
    local override
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

PROJECT_DIR="${REPO_ROOT:-$CWD}"
DOCS_ROOT="$(resolve_docs_root "$PROJECT_DIR")"

abs_path() {  # <path, as the roster spells it> -> absolute
  case "$1" in
    /*)       printf '%s\n' "$1" ;;
    record/*) printf '%s/%s\n' "$DOCS_ROOT" "$1" ;;
    *)        printf '%s/%s\n' "$PROJECT_DIR" "$1" ;;
  esac
}

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

# ONE LOGICAL AGENT IS NOT AN AMBIGUITY (epic-16 wave-02 slice S3, field data 2026-08-11).
# The scan above walks EVERY session directory of the project, and one agent's metadata can
# be filed under more than one of them — the launching session's record and the agent's own
# runtime session are two rows about the same agent. Refusing that as "two agents answer to
# this name" sent the operator round an ambiguity loop over a target that was never
# ambiguous: an AGENT ID identifies an agent, so two matches carrying one id are one match.
# Only distinct ids are candidates.
#
# WHICH COPY SURVIVES: the one whose working log was written most recently. The log is the
# evidence this whole command exists to print, and the freshest copy is the live one — the
# stale copy is a record of the same agent, not a different one, so choosing between them
# by anything else would print older evidence about the very same target.
if [ -n "$MATCHES" ]; then
  MATCHES=$(
    printf '%s\n' "$MATCHES" | while IFS='|' read -r m_id m_meta m_sub; do
      [ -n "$m_id" ] || continue
      printf '%s|%s|%s|%s\n' "$(file_mtime "$m_sub/agent-${m_id}.jsonl")" "$m_id" "$m_meta" "$m_sub"
    done | sort -t'|' -k1,1nr | awk -F'|' '!seen[$2]++ { print $2 "|" $3 "|" $4 }'
  )
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
    # BOTH FORMS, because the two readers of this list need different ones. The
    # transcript-form id is what this command and hooks/stop-guard.sh resolve against; the
    # `name@session-xxxxxxxx` form is what the platform's stop primitive takes for a
    # teammate, and it is the only one an operator who is about to stop this agent can
    # actually type (capture probe §3-D/§5). Printing only the id is what turned one stop
    # into four calls and an ambiguity round on 2026-08-11.
    cand_name=$(jq -r '.name // empty' "$meta" 2>/dev/null)
    echo "  ${id}   (session ${sid})"
    [ -n "$cand_name" ] \
      && echo "      stop it as: ${cand_name}@session-$(printf '%s' "$sid" | cut -c1-8)"
  done <<< "$MATCHES"
  echo ""
  echo "Name the agent by an id above — observe it by the long id, stop it by the"
  echo "name@session form. This command decides nothing."
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

# ---------- classification against the session roster (slice 4/5, AC-6) ----------
#
# THIS SESSION'S OWN id, for a script with no payload to carry one — the same
# resolution hooks/preflight-probe.sh already makes (CLAUDE_CODE_SESSION_ID,
# exported into every Bash subprocess Claude Code runs). Empty when this command
# runs outside a Claude Code session, or the variable is otherwise unset;
# classification then reports UNKNOWN rather than guessing.
ROSTER_VERSION="v1"
OWN_SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
ROSTER_PATH=""
if [ -n "$REPO_ROOT" ] && [ -n "$OWN_SESSION_ID" ]; then
  ROSTER_PATH="$REPO_ROOT/.bionic/tmp/roster-${OWN_SESSION_ID}.state"
fi

# OWNERSHIP IS THE METADATA'S OWN FILING (slice 4/9). An agent whose metadata
# sits under <session>/subagents/ was launched by <session> — the platform files
# it there and nothing else writes that directory. Slice 4/5 keyed this on ROSTER
# MEMBERSHIP instead, and live operation broke both arms of that key:
#
#   * The NAME arm handed ownership away. Every row in a session that has not
#     restarted since the recorder shipped is `status=intended` with an EMPTY
#     `agent_id=`, so the name arm was the only one live — and a name is not an
#     identity. A three-day-dead agent of another session, answering to a name
#     this session's roster happened to carry, classified OURS and was then shown
#     with THIS session's contracted progress path.
#   * The absence of a row refused our own agents. Anything dispatched before the
#     roster hook shipped has no row at all and classified foreign, of an agent
#     sitting in this session's own subagents directory.
#
# So the directory decides, and the roster keeps the job it can actually do: it
# is the CONTRACT source for a target already established as ours, and ownership
# by id is established by a `confirmed` OR `identified` row carrying a NON-EMPTY
# `agent_id` — an id is unambiguous by construction. In teammate mode the
# transcript-form id arrives on the `identified` row while the `confirmed` row's
# `agent_id=` is EMPTY by design (the detail below and execution-recorder.sh's
# ARM 2 say why), so `identified` is what makes the by-id clause reachable for an
# interactive dispatch at all. It is never consulted as a name-oracle again.
ROSTER_ROW=""
ROSTER_ID_MATCH=""
if [ -n "$ROSTER_PATH" ] && [ -f "$ROSTER_PATH" ] && [ ! -L "$ROSTER_PATH" ]; then
  ROW_BY_ID=""; ROW_BY_NAME=""
  while IFS= read -r rline; do
    case "$rline" in '#'*|'') continue ;; esac
    case "$rline" in "roster-state/${ROSTER_VERSION}|"*) : ;; *) continue ;; esac
    rid=$(line_field "$rline" agent_id)
    rname=$(line_field "$rline" name)
    # `confirmed` or `identified`, never merely non-empty: the id on an
    # UNCONFIRMED row is a claim about a launch that has not been observed to
    # happen. What kept the weaker test safe was a property of a different file —
    # hooks/dispatch-preflight.sh emits `agent_id=` empty on every `intended` row
    # — and an invariant enforced elsewhere is exactly what slice 4/9 was
    # remediating (Step-6 review C-2). Costs the pre-restart world nothing: its
    # rows carry no id at all, so this clause never fired for them, and their
    # CONTRACT still comes from the row by name below.
    #
    # `identified` joins the set in epic-16 wave-01 slice 1, and is the state
    # that makes the clause reachable at all for a teammate. A confirmed teammate
    # row's `agent_id=` is EMPTY by design — the launch response knows only the
    # addressing form `name@session-xxxx`, and writing that into the id field
    # would make every by-id reader's input wrong rather than unknown. The
    # transcript-form id, which is what this script resolves a target to, first
    # appears on SubagentStart and lands on the `identified` row.
    if [ -n "$rid" ] && [ "$rid" = "$AGENT_ID" ]; then
      case "$(line_field "$rline" status)" in
        confirmed|identified) ROW_BY_ID="$rline" ;;
      esac
    fi
    [ -n "$rname" ] && [ "$rname" = "$AGENT_NAME" ] && ROW_BY_NAME="$rline"
  done < "$ROSTER_PATH"
  ROSTER_ID_MATCH="$ROW_BY_ID"
  ROSTER_ROW="${ROW_BY_ID:-$ROW_BY_NAME}"
fi

# Not OURS: FOREIGN or DEAD HISTORY, by the owning session's transcript — the
# same existence check hooks/preflight-probe.sh and hooks/dispatch-preflight.sh
# already make (session_transcript_exists / roster_session_live), duplicated here
# for the same TDD §9 reason as the file-facts functions above.
#
# WHAT THIS ANSWERS, stated exactly because the old name overstated it: whether
# the owning session's transcript FILE EXISTS. Transcripts are not deleted when a
# session ends — measured on this machine, all 57 sessions with subagent metadata
# under this project satisfy it, including sessions that finished days ago. So it
# separates "there is still a session on disk accounting for this agent" from the
# bb20f616 shape, "metadata answering to a live-looking name, from a session whose
# own transcript is gone". It says nothing whatever about whether the AGENT is
# running, which is why the label no longer says `live`; the working log's age,
# printed below, is the only evidence of that this command has.
owning_session_on_disk() {  # <session id>
  local sid="$1" d
  [ -n "$sid" ] || return 1
  [ -d "$PROJECTS" ] || return 1
  for d in "$PROJECTS"/*/; do
    [ -f "${d}${sid}.jsonl" ] && return 0
  done
  return 1
}

CLASSIFICATION="unknown"
OURS_BECAUSE=""
if [ -z "$OWN_SESSION_ID" ]; then
  CLASSIFICATION="unknown"
elif [ "$SESSION_ID" = "$OWN_SESSION_ID" ]; then
  CLASSIFICATION="ours"
  OURS_BECAUSE="its metadata is filed under this session's own subagents directory"
elif [ -n "$ROSTER_ID_MATCH" ]; then
  CLASSIFICATION="ours"
  OURS_BECAUSE="this session's roster confirms it by agent id (roster-${OWN_SESSION_ID}.state)"
  # OURS BY ADOPTION, said out loud. A row carrying `adopted_from=` is one
  # hooks/session-poker.sh's `adopt` wrote after a `/clear`+resume: the agent is still the
  # predecessor's — same process, same subagents directory — and this session took the
  # contract over. The by-id clause above already answers OURS for it, and answering MUTELY
  # is what this adds to: the operator is reading OURS about an agent filed under a session
  # they are not in, and the provenance is what tells them which session's directory the
  # observe address below names, and which one hooks/stop-guard.sh widened its resolution to.
  # It is reported, never judged (§4: this command decides nothing).
  ADOPTED_FROM=$(line_field "$ROSTER_ID_MATCH" adopted_from)
  if [ -n "$ADOPTED_FROM" ]; then
    OURS_BECAUSE="this session ADOPTED it (adopted_from=${ADOPTED_FROM}) and its roster confirms it by agent id (roster-${OWN_SESSION_ID}.state)"
  fi
elif owning_session_on_disk "$SESSION_ID"; then
  CLASSIFICATION="foreign"
else
  CLASSIFICATION="dead-history"
fi

# ---------- contract state: roster-sourced when OURS, CLI always overrides ----------
#
# "Deliverable/progress display logic itself is unchanged — only the SOURCE of
# the paths widens" (slice 4/5 brief). An explicit CLI value always wins; when it
# differs from what the roster recorded, that is printed, never judged (§4: this
# command decides nothing).
ROSTER_DELIVERABLE=""; ROSTER_PROGRESS=""; ROSTER_CLAIMS=""; ROSTER_CADENCE=""
if [ "$CLASSIFICATION" = "ours" ] && [ -n "$ROSTER_ROW" ]; then
  ROSTER_DELIVERABLE=$(line_field "$ROSTER_ROW" deliverable)
  ROSTER_PROGRESS=$(line_field "$ROSTER_ROW" progress)
  ROSTER_CLAIMS=$(line_field "$ROSTER_ROW" claims)
  ROSTER_CADENCE=$(line_field "$ROSTER_ROW" cadence)
fi

ORIG_ARGS_COUNT="$#"
ORIG_ARGS_JOINED=""
if [ "$ORIG_ARGS_COUNT" -gt 0 ]; then
  ORIG_ARGS_JOINED=$(IFS=,; echo "$*")
fi

DELIVERABLE_SOURCE="none"
DELIVERABLE_MISMATCH=""
if [ "$ORIG_ARGS_COUNT" -gt 0 ]; then
  DELIVERABLE_SOURCE="args"
  if [ -n "$ROSTER_DELIVERABLE" ] && [ "$ORIG_ARGS_JOINED" != "$ROSTER_DELIVERABLE" ]; then
    DELIVERABLE_MISMATCH="$ROSTER_DELIVERABLE"
  fi
elif [ -n "$ROSTER_DELIVERABLE" ]; then
  DELIVERABLE_SOURCE="roster"
  # PATHNAME EXPANSION OFF for exactly this split. Setting IFS suppresses word
  # splitting on other characters and says nothing about globbing, so a roster
  # value of `docs/*.md` — which a brief can produce, since the lifter accepts
  # any slash-and-letter token and the writer's sanitizer does not strip `*` —
  # expanded against whatever happened to be sitting in the OBSERVER'S CWD.
  # Files nobody contracted for were then reported PRESENT and rode into the
  # durable record as confirmed deliverables (Step-6 review C-1/S-3). No wall
  # opened; the human judgment this whole command exists to inform was the thing
  # being fooled, which is worse to leave standing.
  OLDIFS="$IFS"; IFS=','; set -f; set -- $ROSTER_DELIVERABLE; set +f; IFS="$OLDIFS"
fi

PROGRESS_SOURCE="none"
PROGRESS_MISMATCH=""
if [ "$PROGRESS_NAMED" -eq 1 ]; then
  PROGRESS_SOURCE="args"
  if [ -n "$ROSTER_PROGRESS" ] && [ "$PROGRESS_PATH" != "$ROSTER_PROGRESS" ]; then
    PROGRESS_MISMATCH="$ROSTER_PROGRESS"
  fi
elif [ -n "$ROSTER_PROGRESS" ]; then
  PROGRESS_SOURCE="roster"
  PROGRESS_PATH="$ROSTER_PROGRESS"
  PROGRESS_NAMED=1
fi

CLAIMS_SOURCE="none"
if [ "$CLAIMS_NAMED" -eq 1 ]; then
  CLAIMS_SOURCE="args"
elif [ -n "$ROSTER_CLAIMS" ]; then
  CLAIMS_SOURCE="roster"
  CLAIMS_PATTERN="$ROSTER_CLAIMS"
  CLAIMS_NAMED=1
fi

echo "Resolved:      ${AGENT_ID}"
echo "               name: ${AGENT_NAME} · type: ${AGENT_TYPE} · model: ${AGENT_MODEL}"
echo "               task: ${AGENT_DESC}"
echo "Session:       ${SESSION_ID}"
case "$CLASSIFICATION" in
  ours)
    echo "Classification: OURS — ${OURS_BECAUSE}." ;;
  foreign)
    echo "Classification: FOREIGN — owned by session ${SESSION_ID}; that session's transcript is still on disk, but this session did not launch it."
    echo "               (A transcript on disk does not mean the agent is still running — the working log's age below is the only evidence of that.)" ;;
  dead-history)
    echo "Classification: DEAD HISTORY — owned by session ${SESSION_ID}; that session's transcript is gone, so nothing on disk still accounts for it." ;;
  unknown)
    echo "Classification: UNKNOWN — this session's own id is unavailable (CLAUDE_CODE_SESSION_ID unset), so ownership could not be established." ;;
esac
if [ "$CLASSIFICATION" = "ours" ]; then
  echo "Contract (roster):  deliverables=${ROSTER_DELIVERABLE:-(none recorded)}  progress=${ROSTER_PROGRESS:-(none recorded)}"
fi
if [ "$OUT_OF_PROJECT" -eq 1 ]; then
  echo "Note:          this agent was found outside this project's own directory."
fi
echo ""

# ---------- evidence 1: the working log (§2.2 — unfakeable, written by working) ----------
echo "Working log:   ${LOG}"
LOG_MTIME=0
LOG_SIZE=0
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
if [ -n "$DELIVERABLE_MISMATCH" ]; then
  echo "  (note: the roster recorded a different deliverable set: ${DELIVERABLE_MISMATCH} — not judged)"
fi
# Each deliverable's state is accumulated for the machine line as
# `<state>:<path>`, comma-joined — the same comma-joined path list the roster row
# uses for the same concept (hooks/dispatch-preflight.sh's `deliverable=`), so
# the two machine artifacts in .bionic/tmp/ render one concept one way.
DELIV_STATES=""
add_deliv() { DELIV_STATES="${DELIV_STATES:+$DELIV_STATES,}$1:$(mline_value "$2")"; }
if [ "$#" -eq 0 ]; then
  echo "  (none named on the command line — pass each contracted path as an argument)"
else
  NOW=$(date -u +%s)
  # STAT THE RESOLVED PATH, REPORT THE CONTRACTED ONE. `$dp` is where this command looked;
  # `$d` is what the contract spelled, and it is what the readback and the machine line
  # carry — so the roster, the brief and this output all name the artifact the same way,
  # which is the property the mismatch note above depends on.
  for d in "$@"; do
    dp="$(abs_path "$d")"
    if [ -f "$dp" ]; then
      DSIZE=$(file_size "$dp"); DMTIME=$(file_mtime "$dp")
      if [ "$DSIZE" -eq 0 ]; then
        echo "  ${d} — PRESENT but EMPTY, 0 bytes"
        add_deliv empty "$d"
      else
        echo "  ${d} — PRESENT, ${DSIZE} bytes, last write $(fmt_epoch "$DMTIME") (age $(fmt_age $((NOW - DMTIME))))"
        add_deliv present "$d"
      fi
    elif [ -d "$dp" ]; then
      echo "  ${d} — PRESENT as a directory, $(find "$dp" -type f 2>/dev/null | grep -c .) file(s)"
      add_deliv dir "$d"
    else
      echo "  ${d} — ABSENT"
      add_deliv absent "$d"
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
PROGRESS_STATE="unnamed"
PROGRESS_MTIME=0
if [ "$PROGRESS_NAMED" -eq 1 ]; then
  echo ""
  echo "-- progress artifact (D-6) --"
  if [ -n "$PROGRESS_MISMATCH" ]; then
    echo "  (note: the roster recorded a different progress path: ${PROGRESS_MISMATCH} — not judged)"
  fi
  # Same rule as the deliverables above: stat the resolved path, print the contracted one.
  PROGRESS_ABS="$(abs_path "$PROGRESS_PATH")"
  if [ -e "$PROGRESS_ABS" ]; then
    PMTIME=$(file_mtime "$PROGRESS_ABS")
    PSIZE=$(file_size "$PROGRESS_ABS")
    NOW=$(date -u +%s)
    echo "progress: ${PROGRESS_PATH}  last-write $(fmt_epoch "$PMTIME") ($(fmt_age $((NOW - PMTIME))) ago)  size ${PSIZE}B"
    PROGRESS_STATE="present"; PROGRESS_MTIME="$PMTIME"
  else
    echo "progress: ${PROGRESS_PATH}  ABSENT"
    PROGRESS_STATE="absent"
  fi
  # THE DECLARED CADENCE, beside the age it qualifies. The ratified liveness
  # contract extends the ≥15m rule by one number — "too quiet" means quieter than
  # the AUTHOR'S OWN declaration, not a fixed clock — so the age above is
  # unreadable without it. Printed, never compared: this command decides nothing,
  # and the comparison belongs to whoever is doing the judging (P3's watcher, or
  # the operator reading this).
  if [ -n "$ROSTER_CADENCE" ]; then
    echo "cadence:  ${ROSTER_CADENCE}  (declared in the dispatch contract)"
  fi
fi

# ---------- P2: claimed-process liveness (Liveness contract, ratified 2026-08-05) ----------
#
# Existence only — is any process matching the claimed pattern running right
# now? This is a display fact, exactly like everything else in this command: it
# names nothing about health, only presence. Source is the roster's `claims=`
# field when OURS and no --claims was typed, or the explicit flag when one
# was — same override rule as deliverables and progress.
if [ "$CLAIMS_NAMED" -eq 1 ]; then
  echo ""
  echo "-- claimed process (P2) --"
  echo "claims:   pattern='${CLAIMS_PATTERN}'  source=${CLAIMS_SOURCE}"
  if claims_live "$CLAIMS_PATTERN"; then
    echo "live:     yes — a process matching this pattern exists right now"
  else
    echo "live:     no — no process matching this pattern was found"
  fi
  echo "This is an existence check only. It decides nothing."
fi

echo ""
echo "This command decides nothing. It prints evidence; the judgment is yours."

# ---------- the machine line (slice 4/4 — the recorder's ONLY input) ----------
#
# Last line of a successful run, and the only line any machine reads. Three
# properties earn their place:
#
#   * it is printed HERE, past every refusal path, so its existence IS the proof
#     that an observation ran and produced an evidence tier. The recorder is
#     PostToolUse and reads it out of the tool RESPONSE, so a command the harness
#     refused to dispatch, a command that exited non-zero, and a command that
#     merely MENTIONS this script all leave no line and therefore no record —
#     the "recorded a look but nothing ran" class closed at its root rather than
#     narrowed (tests/cross-gate-agreement.test.sh §C case 6);
#   * it carries the RESOLVED identity and the file facts THIS RUN computed, so
#     the recorder never re-resolves anything. One resolver decides who was
#     looked at, which is what makes the operator's view and the record the same
#     fact rather than two computations that must be kept in agreement (F-1);
#   * `progress_state=unnamed` distinguishes "the contract named no progress
#     artifact" from "it named one and the artifact is missing" — the D-6
#     distinction a blank value would erase.
printf '%s|target=%s|typed=%s|log=%s|mtime=%s|size=%s|deliverables=%s|progress=%s|progress_mtime=%s|progress_state=%s|classification=%s|deliverable_source=%s|progress_source=%s\n' \
  "$MACHINE_SCHEMA" \
  "$(mline_value "$AGENT_ID")" \
  "$(mline_value "$TARGET")" \
  "$(mline_value "$LOG")" \
  "$LOG_MTIME" \
  "$LOG_SIZE" \
  "$DELIV_STATES" \
  "$(mline_value "$PROGRESS_PATH")" \
  "$PROGRESS_MTIME" \
  "$PROGRESS_STATE" \
  "$(mline_value "$CLASSIFICATION")" \
  "$(mline_value "$DELIVERABLE_SOURCE")" \
  "$(mline_value "$PROGRESS_SOURCE")"
exit 0
