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
# THE MACHINE LINE IS THE ONLY THING THE RECORDER READS (task 4/4). It is
# printed on the SUCCESS path and nowhere else: a usage error, an unresolved
# target and an ambiguous target all exit non-zero having printed no such line,
# so a run that showed the operator no evidence tier leaves nothing behind that
# a stop could spend. That is the whole of the C6 closure — the recorder no
# longer re-parses this command's ARGUMENTS with a second grammar (the F-1
# divergence class), it reads this command's own OUTPUT.
#
# This is a PRODUCER, not a hook — it lives in hooks/ for test-harness pairing
# only. Producers may think and take seconds; gates may only read (§3.2).
#
# UNREGISTERED BY DESIGN: this is the hand-run observation producer. The
# orchestrator runs it by hand, before stopping a subagent, and it is the sole
# producer of the stop-check-observation/v1 records the stop gate spends
# (wave-11-lean-spine T9 ruling, 2026-09-11 — the census's "unregistered" was
# a misclassification of intentional design, not evidence of dead code).
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

# THE MACHINE LINE'S SCHEMA TOKEN LIVES WITH THE LINE (REQ-2). It was a constant here and,
# byte for byte, in hooks/execution-recorder.sh; the recorder's arm that read it is gone and
# payload/scripts/lib/observe.sh owns both the token and the printf that spells it.

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

# ---------- the helpers live in the library now ----------
#
# `file_mtime`, `file_size`, `line_field`, `mline_value`, `fmt_epoch`, `fmt_age`,
# `claims_live` and `slugify` were defined here and, byte for byte, in hooks/stop-guard.sh
# — the price of the no-library rule (TDD §9), held together by the resolver agreement
# battery in tests/cross-gate-agreement.test.sh §C. They are one definition now, in
# payload/scripts/lib/observe.sh, sourced below with the observation itself (REQ-2, D2).

# ---------- resolving the target (P5: the platform does not translate) ----------
#
# A typed reference is a NAME, an agent id, or `name@team` — all three are legal
# TaskStop inputs, and none of them is resolved for us. Comparison is LITERAL:
# a target string is never treated as a pattern.
# [WALL: tests/stop-check.test.sh]
#
# `slugify` is the library's (payload/scripts/lib/observe.sh), sourced below.

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

# RESOLUTION IS NO LONGER A DIRECTORY SCAN (wave-roster-lifecycle S6, D2/D2′). This script
# used to carry `scan_subagent_dirs` — a walk of every `agent-*.meta.json` in the project,
# matching a typed reference against the filename's id or the file's `.name` — byte-identical
# to a copy in hooks/stop-guard.sh, the two held together by an agreement suite. It answered
# "which agent is this" from RECORDS, and records outlive agents: after a `/clear` the same
# agent's metadata is filed under two session directories at once (proven on this machine,
# research-code-map §4.4), which the walk reported as two agents.
#
# What decides now is THIS SESSION'S ROSTER (T22, A-orch-33). Between S6 and 1.7.1 it was
# `live_agents_has` on the session's own transcript — a reading only the model can ask for,
# so an observation taken before the turn's first ListAgents call printed nothing and told
# the operator to go take one. The roster answers the same question from state the system
# already wrote, and one name means one row because the dispatch wall refuses a second.
# The same walk runs in hooks/stop-guard.sh, deliberately duplicated per TDD §9 and held
# together by tests/cross-gate-agreement.test.sh.

# Candidate project slugs, in order: the cwd, then the enclosing repo root.
# Claude Code names a project directory by slugifying its path — every
# non-alphanumeric character becomes a dash (confirmed against two verbatim
# captures in record/epic-15-kill-interception-experiment.md §1.1/§2.2).
# ---------- the library ----------
#
# One loader idiom, byte-identical in every hook (spec AC-16). FAIL OPEN: this script
# reports, it does not refuse, and a diagnosis that died with the thing being diagnosed
# would be worth nothing.
BIONIC_LIB_WANT="roots.sh root.sh session.sh agents.sh observe.sh"
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
if [ -n "$BIONIC_LIB_MISSING" ]; then loader_fail_open "stop-check"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/roots.sh"
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"
# THE ONE READER OF THE LIVE SET (wave-roster-lifecycle S4/S6, D1′). hooks/stop-guard.sh
# calls the SAME function on the SAME transcript, which is what makes the observation and the
# gate resolve one candidate set (AC-10) — where before they carried one loop in two copies.
# shellcheck source=/dev/null
. "$BIONIC_LIB/agents.sh"
# THE OBSERVATION (REQ-2, D2; ADR-028). The resolution, the file facts, the contract
# precedence and the classification, in the one place hooks/stop-guard.sh can reach them too.
# shellcheck source=/dev/null
. "$BIONIC_LIB/observe.sh"

CWD="$(pwd)"
# THE ROOT (spec AC-10, lib/root.sh). `rev-parse --show-toplevel` answers with whatever
# tree the SHELL stands in, so from a linked worktree this script looked for the roster
# under a tree nothing had written one into and reported every contracted path absent.
# `project_root` maps a worktree onto its main repository and walks for the nearest real
# `.bionic`. The slug list below still carries both the cwd and the root, because the
# harness names a project directory after the path the SESSION was started in.
REPO_ROOT=$(project_root "$CWD")
SLUGS="$(slugify "$CWD")"
if [ -n "$REPO_ROOT" ] && [ "$REPO_ROOT" != "$CWD" ]; then
  SLUGS="${SLUGS}
$(slugify "$REPO_ROOT")"
fi

# ---------- resolving a contracted path (epic-17 W6 S15, A-6.6 (c)) ----------
#
# WHAT WAS WRONG. The paths this command stats — the deliverables, and the `--progress`
# artifact — arrive as brief prose, and the spelling every task brief in this epic uses is
# `record/epic-NN-wM/x.md`, because that is the form the Step-5 contract and
# `canonical-sdlc-evidence-gate.sh` publish for an artifact under the docs root. This
# command resolved nothing at all: a relative path was stat'd against whatever directory
# the observer happened to be standing in, so a present progress file read `absent` and a
# landed deliverable read `ABSENT` — an observation that decides nothing, deciding wrongly.
#
# THE RULE IS ONE FUNCTION NOW. The docs root comes from lib/roots.sh's `docs_root` — this
# command used to carry a copy of the evidence gate's `resolve_docs_root()`, held to the
# gate's text by a body-for-body comparison; cross-gate §Roots holds the single definition
# instead (epic-22 wave-01, N1). `abs_path` below is still a copy of the gate's
# `resolve_walk_path()` under another name, deliberately out of that scope.
# `PROJECT_DIR` and `DOCS_ROOT` carry the gate's names for the same reason. The VALUE of PROJECT_DIR is this command's own — the repo it was run
# from, falling back to the cwd when that is not a repository, which is the root every
# other path in this file is already read against.
#
# WHAT IS STILL NOT JUDGED. Resolution is not a verdict. A path that climbs out with `..`
# resolves and is reported like any other: §4's rule is that this command decides nothing,
# and refusing a contract here would be deciding. The landing gate is where a deliverable
# is judged, and hooks/session-sweeper.sh refuses `..` there.

PROJECT_DIR="${REPO_ROOT:-$CWD}"
DOCS_ROOT="$(docs_root "$PROJECT_DIR")"

# The resolver itself is `observe_abs_path` in the library, reading `OBSERVE_DOCS_ROOT` and
# `OBSERVE_ROOT`, which this command sets from the two values below.

# ---------- THIS SESSION'S OWN id, and the transcript the live set is read from ----------
#
# THE KEY. This script has no hook payload to carry a session key, so it reads the one the
# harness exports into every Bash subprocess — the same resolution hooks/preflight-probe.sh
# makes. Empty when the command runs outside a Claude Code session; the live set is then
# unreadable and this command says so rather than guessing.
OWN_SESSION_ID=$(session_id "" 2>/dev/null) || OWN_SESSION_ID=""

# THE TRANSCRIPT. hooks/stop-guard.sh is handed one in its payload; this script has to find
# the same file. The harness names it `<projects>/<slug>/<session-id>.jsonl`, so the slugs
# above are tried first and a keyed walk of the project directories covers the one case that
# breaks them: a worktree cwd files its session under a different slug from the repo it is
# reading. Exactly the same two-step `adopted_subagent_dirs` used before this task deleted it.
own_transcript() {  # -> the transcript file of THIS session, or nothing
  local slug d
  [ -n "$OWN_SESSION_ID" ] || return 1
  while IFS= read -r slug; do
    [ -n "$slug" ] || continue
    if [ -f "$PROJECTS/$slug/$OWN_SESSION_ID.jsonl" ]; then
      printf '%s\n' "$PROJECTS/$slug/$OWN_SESSION_ID.jsonl"; return 0
    fi
  done <<< "$SLUGS"
  for d in "$PROJECTS"/*/"$OWN_SESSION_ID.jsonl"; do
    [ -f "$d" ] && { printf '%s\n' "$d"; return 0; }
  done
  return 1
}
OWN_TRANSCRIPT=$(own_transcript) || OWN_TRANSCRIPT=""

# ---------- THE LOOK ITSELF, taken by the library ----------
#
# THE WHOLE OF THE RESOLUTION AND THE FACT-GATHERING MOVED (REQ-2, D2; ADR-028). What stood
# here — the roster walk by both keys, the id-typed row override, the working-log path, the
# contract-from-roster precedence, the deliverable and progress stats — is
# `observe_agent` in payload/scripts/lib/observe.sh, because the STOP GATE needs the same
# look and could not take one. It read a RECORD of an earlier run of this command instead,
# and on 2026-09-15 refused a correct stop with "no observation exists in this repo" because
# nobody had run it. One function, two callers: this one prints, hooks/stop-guard.sh decides.
#
# WHAT THIS COMMAND STILL IS. A PRODUCER that decides nothing (§4): every unresolved shape
# prints what it saw, exits 1, and prints no machine line.
OBSERVE_ROOT="$PROJECT_DIR"
OBSERVE_SESSION="$OWN_SESSION_ID"
OBSERVE_TRANSCRIPT="$OWN_TRANSCRIPT"
OBSERVE_DOCS_ROOT="$DOCS_ROOT"
OBSERVE_ROSTER=""
if [ -n "$REPO_ROOT" ] && [ -n "$OWN_SESSION_ID" ]; then
  OBSERVE_ROSTER="$REPO_ROOT/.bionic/tmp/roster-${OWN_SESSION_ID}.state"
fi
# The two flags, in the variable form the library takes. Empty is "not named", which is a
# different fact from "named and absent" — the D-6 distinction a blank would erase.
OBSERVE_PROGRESS_ARG=""
[ "$PROGRESS_NAMED" -eq 1 ] && OBSERVE_PROGRESS_ARG="$PROGRESS_PATH"
OBSERVE_CLAIMS_ARG=""
[ "$CLAIMS_NAMED" -eq 1 ] && OBSERVE_CLAIMS_ARG="$CLAIMS_PATTERN"

echo "OBSERVATION — target as typed: ${TARGET}"

observe_agent "$TARGET" "$@"

# THE ROSTER RESOLVED IT, AND THE ROSTER IS ALL THAT RESOLVES IT (T22, A-orch-33; AC-4.4).
# Three arms stood here between wave-roster-lifecycle S6 and 1.7.1, all three driven off
# `live_agents_has`: a STALE or absent ListAgents answer printed a demand for a fresh panel
# reading and exited 1; two live entries of one name printed an ambiguity; a name the
# answer did not carry printed "not live". They are gone with the gate's copies of them. A
# NAME now means one row on this session's roster, because `hooks/dispatch-preflight.sh`
# refuses a dispatch that would make it mean two; the row carries the id; and this command,
# which decides nothing, has nothing left to be unable to resolve except a missing id.
if [ "$OBS_OK" -ne 1 ]; then
  echo "Resolved:      live, but no agent id — this session's roster carries no \`confirmed\` or"
  echo "               \`identified\` row with an agent id for '${OBS_NAME:-$TARGET_BASE}'."
  echo ""
  echo "A working log is filed under an agent's id, and a dispatch records that id on its"
  echo "roster row when the agent starts. Without it there is no evidence tier to print."
  echo "This command decides nothing."
  exit 1
fi

echo "Resolved:      ${OBS_ID}"
echo "               name: ${OBS_NAME} · type: ${OBS_TYPE} · model: ${OBS_MODEL}"
echo "               task: ${OBS_DESC}"
echo "Session:       ${OBS_SESSION}"
# FOREIGN and DEAD HISTORY are gone with the directory scan that produced them (S6). Both
# were verdicts about where an agent's METADATA sat, and a target that reaches this line has
# been named by the harness as a teammate of this session — which is the only sense in which
# an agent is ours. `unknown` is unreachable for the same reason: a session with no key of
# its own cannot read a register and refuses above, before anything is resolved.
echo "Classification: OURS — ${OBS_OURS_BECAUSE}."
echo "Contract (roster):  deliverables=$(line_field "$OBS_ROW" deliverable || true)  progress=$(line_field "$OBS_ROW" progress || true)"
if [ -n "$OBS_ADOPTED_FROM" ]; then
  echo "Note:          adopted from ${OBS_ADOPTED_FROM}; its working log was found under session ${OBS_SESSION} (the newest copy of it anywhere in this project — D8)."
fi
echo ""

# ---------- evidence 1: the working log (§2.2 — unfakeable, written by working) ----------
echo "Working log:   ${OBS_LOG}"
if [ -f "$OBS_LOG" ]; then
  echo "  last write:  $(fmt_epoch "$OBS_LOG_MTIME")  (age $(fmt_age "$OBS_LOG_AGE"))"
  echo "  size:        ${OBS_LOG_SIZE} bytes"
  LAST_MSG=$(tail -400 "$OBS_LOG" 2>/dev/null \
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
#
# THE STATES ARE THE LIBRARY'S, THE PROSE IS THIS COMMAND'S. `observe_agent` already stat'ed
# every contracted path and recorded `<state>:<path>` per deliverable — the same comma-joined
# list the roster row uses for the same concept — so what is left here is rendering it. A
# second stat for the size and the age is a display, not a decision: the state a reader is
# shown and the state a machine reads come off one computation (F-1).
echo "Deliverables:"
if [ -n "$OBS_DELIV_MISMATCH" ]; then
  echo "  (note: the roster recorded a different deliverable set: ${OBS_DELIV_MISMATCH} — not judged)"
fi
if [ -z "$OBS_DELIVERABLES" ]; then
  echo "  (none named on the command line — pass each contracted path as an argument)"
else
  OLDIFS="$IFS"; IFS=','; set -f; set -- $OBS_DELIVERABLES; set +f; IFS="$OLDIFS"
  for pair in "$@"; do
    dstate="${pair%%:*}"; d="${pair#*:}"
    dp="$(observe_abs_path "$d")"
    case "$dstate" in
      present)
        echo "  ${d} — PRESENT, $(file_size "$dp") bytes, last write $(fmt_epoch "$(file_mtime "$dp")") (age $(fmt_age $((OBS_NOW - $(file_mtime "$dp")))))" ;;
      empty)
        echo "  ${d} — PRESENT but EMPTY, 0 bytes" ;;
      dir)
        echo "  ${d} — PRESENT as a directory, $(find "$dp" -type f 2>/dev/null | grep -c .) file(s)" ;;
      *)
        echo "  ${d} — ABSENT" ;;
    esac
  done
fi

# ---------- evidence 4: the progress artifact (D-6 — the task's own byproducts) ----------
#
# An hour-long command silences the working log for its whole hour: one tool call, one result
# at the end. "No activity for 47 minutes" therefore describes a healthy suite and a wedged
# one identically, and no amount of reading the agent will separate them. The separation
# lives one level DOWN, in the work's own byproducts.
#
# Printed only when the contract named a path — the section is additive.
if [ "$OBS_PROGRESS_NAMED" -eq 1 ]; then
  echo ""
  echo "-- progress artifact (D-6) --"
  if [ -n "$OBS_PROGRESS_MISMATCH" ]; then
    echo "  (note: the roster recorded a different progress path: ${OBS_PROGRESS_MISMATCH} — not judged)"
  fi
  if [ "$OBS_PROGRESS_STATE" = "present" ]; then
    echo "progress: ${OBS_PROGRESS}  last-write $(fmt_epoch "$OBS_PROGRESS_MTIME") ($(fmt_age "$OBS_PROGRESS_AGE") ago)  size $(file_size "$OBS_PROGRESS_ABS")B"
  else
    echo "progress: ${OBS_PROGRESS}  ABSENT"
  fi
  # THE DECLARED CADENCE, beside the age it qualifies. The ratified liveness contract extends
  # the ≥15m rule by one number — "too quiet" means quieter than the AUTHOR'S OWN declaration,
  # not a fixed clock — so the age above is unreadable without it. Printed here, never
  # compared: this command decides nothing. The COMPARISON is the library's `observe_class`,
  # and hooks/stop-guard.sh is who acts on it.
  if [ -n "$OBS_CADENCE" ]; then
    echo "cadence:  ${OBS_CADENCE}  (declared in the dispatch contract)"
  fi
fi

# ---------- P2: claimed-process liveness (Liveness contract, ratified 2026-08-05) ----------
#
# Existence only — is any process matching the claimed pattern running right now? This is a
# display fact, exactly like everything else in this command: it names nothing about health,
# only presence.
if [ "$OBS_CLAIMS_NAMED" -eq 1 ]; then
  echo ""
  echo "-- claimed process (P2) --"
  echo "claims:   pattern='${OBS_CLAIMS}'  source=${OBS_CLAIMS_SOURCE}"
  if observe_claims_live "$OBS_CLAIMS"; then
    echo "live:     yes — a process matching this pattern exists right now"
  else
    echo "live:     no — no process matching this pattern was found"
  fi
  echo "This is an existence check only. It decides nothing."
fi

echo ""
echo "This command decides nothing. It prints evidence; the judgment is yours."

# ---------- the machine line ----------
#
# Last line of a successful run, and the only line any machine reads. It is printed HERE,
# past every refusal path, so its existence IS the proof that an observation ran and produced
# an evidence tier — a usage error, an unresolved target and a target with no agent id all
# exit non-zero having printed no such line.
#
# ITS SHAPE BELONGS TO THE LIBRARY NOW (REQ-2). `observe_machine_line` renders the facts
# `observe_agent` computed, so the identity and the file facts a reader sees above and the
# ones a machine reads below are one computation rather than two kept in agreement (F-1).
observe_machine_line
exit 0
