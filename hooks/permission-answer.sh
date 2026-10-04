#!/bin/bash
# hooks/permission-answer.sh — THE CARRIER: bionic answers the platform's permission question
# for an engaged run (epic-23 wave-25-never-paused, REQ-1, REQ-2, REQ-3, REQ-5, REQ-6, REQ-7;
# spec D1, D8, D9, D10; ADR-042).
#
# Registered exactly once, on PermissionRequest, timeout 10. The platform raises that event
# when it would otherwise put a dialog in front of a human ("may I run this?"). With nobody
# there the dialog halts the asker and everything waiting on it, so for a session that engaged
# a run this hook answers instead: ONE decision object, allow or deny with a message, built
# from the grant (payload/scripts/lib/grant.sh) over facts collected here.
#
# THE ORDER OF WORK, and why it is this order.
#   1. Read the payload; load the library; `bionic_context`. Not engaged -> nothing printed,
#      exit 0: the stock dialog shows. `permission-answers: false` in .bionic/config.yaml ->
#      the same, with no log line (only the literal `false` turns it off). A tool that exists
#      to collect human input (AskUserQuestion, ExitPlanMode) -> the same: a question for the
#      human is never answered by bionic.
#   2. From here the session is known to be engaged and the boundary on, and a trap is armed:
#      any exit that has not printed a decision prints a DENY naming the failure.
#   3. Facts: who asked (the payload's agent_id through this session's roster; none means
#      the lead), its class (lead, unbound, writer, reader), its roots, and the main root.
#   4. Effects: what the action writes, deletes and reads, from the command reader for Bash
#      (resolved in one process, and none past PA_EFFECTS_MAX) and from the tool's own path
#      for the file tools; anything else is unknown.
#   5. grant_reserved over the spelling, then over the place (every path, typed and
#      resolved), then grant_decide. One answer. One answer line. For a reserved denial, one
#      gate line for the lead.
#
# THE FAIL DIRECTION DIFFERS FROM EVERY OTHER HOOK'S, ON PURPOSE (spec D8; the sanctioned
# difference is recorded in tests/hook-adoption.test.sh). The fleet either steps aside
# (exit 0, nothing) or refuses (exit 2) when it cannot work. Here stepping aside means the
# stock dialog, which in an unattended run is the halt this hook exists to remove, and a
# refusal by exit code is not a decision the platform reads from this event. So the
# direction is split at the one fact that decides who may answer at all: BEFORE engagement is
# established a failure is silent (jq missing, the loader failing, a session that cannot be
# identified: bionic claims no authority it cannot establish), and AFTER it every failure is
# a denial that says what failed. Never an allow, never empty stdout.
#
# WHAT IT NEVER PRINTS: `updatedPermissions`, `updatedInput` or `interrupt`, on any path, and
# never the payload's `permission_suggestions`. An answer changes no trust setting (REQ-5),
# and a denial does not stop the asker (REQ-3): it reads the message and carries on.
#
# THE FREEZE (.claude/rules/hook-authoring.md). The decision is grant.sh's and reads nothing;
# this file is the collector that hands it every fact, already resolved.
#
# [WALL: tests/permission-answer.test.sh]

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

BIONIC_INPUT=$(cat) || exit 0

# ---------- the library ----------
#
# One loader idiom, byte-identical in every hook (spec AC-16); its source of truth is
# payload/scripts/lib/loader.sh. Its fail-open arm is the silent half of the split above: a
# library that will not load cannot say whether this session is engaged.
BIONIC_LIB_WANT="cmd-class.sh context.sh git-argv.sh grant.sh root.sh roots.sh roster.sh run.sh session.sh worktree.sh"
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
if [ -n "$BIONIC_LIB_MISSING" ]; then loader_fail_open "permission-answer"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/context.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/roots.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/roster.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/worktree.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/cmd-class.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/git-argv.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/grant.sh"

# The run verdict is wanted: whether the lead is bound to an open run decides its class.
BIONIC_CONTEXT_WANT_RUN=1
bionic_context 2>/dev/null || exit 0
[ "$BIONIC_ENGAGED" = 1 ] || exit 0

# THE SWITCH (D10). On unless the project says, literally, `permission-answers: false`.
if [ "$(config_value "$BIONIC_ROOT" permission-answers true 2>/dev/null)" = "false" ]; then
  exit 0
fi

PA_TAB=$'\t'
PA_NL=$'\n'

# _pa_field <jq path> -> the payload's string at that path, or nothing.
_pa_field() {
  printf '%s' "$BIONIC_INPUT" | jq -r "$1 | if type == \"string\" then . else empty end" 2>/dev/null
}

PA_PARSED=0
PA_TOOL=""
if printf '%s' "$BIONIC_INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  PA_PARSED=1
  PA_TOOL="$(_pa_field .tool_name)"
fi

# A question for the human is never answered by bionic (AC-1.4).
case "$PA_TOOL" in
  AskUserQuestion|ExitPlanMode) exit 0 ;;
esac

# _pa_clean <text> [<max chars>] -> the text cut to <max> (default 2000), then on one line
# with no field separator: `|`, CR and LF become spaces. Used for every log and gate field.
# THE CUT COMES FIRST, AND IT IS NOT AN OPTIMISATION: bash 3.2's `${v//x/y}` is quadratic in
# the string's length, and on a 52 KB command the three replacements below ran past the 10 s
# registration (measured, tests/hook-timeout.test.sh §3c) — a killed carrier answers nothing.
_pa_clean() {
  local v="${1-}"
  v="${v:0:${2:-2000}}"
  v="${v//|/ }"
  v="${v//$'\r'/ }"
  v="${v//$PA_NL/ }"
  printf '%s' "$v"
}

# _pa_emit <allow|deny> [<message>] — THE ONE PRINT. Exactly the two shapes the live check
# measured as honoured; built with jq so the message is escaped. Nothing else is ever added.
_pa_emit() {
  local out
  if [ "$1" = allow ]; then
    out="$(jq -cn '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"allow"}}}' 2>/dev/null)"
  else
    out="$(jq -cn --arg m "${2:-bionic: denied}" \
      '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"deny",message:$m}}}' 2>/dev/null)"
    # jq is known present; if it still fails, a fixed denial is printed rather than nothing.
    [ -n "$out" ] || out='{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"bionic: denied (the answer could not be built)"}}}'
  fi
  [ -n "$out" ] || out='{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"bionic: denied (the answer could not be built)"}}}'
  PA_ANSWERED=1
  printf '%s\n' "$out" >&3 2>/dev/null || printf '%s\n' "$out"
}

# _pa_log <decision> <reason> — the answer line (D9), through lib/root.sh's appender:
# `<ISO-UTC>|<sid>|<asker>|<tool>|<decision>|<reason>|<first 120 chars of the command or path>`.
_pa_log() {
  log_answer "$BIONIC_ROOT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)|$(_pa_clean "$BIONIC_SID")|$(_pa_clean "$PA_ASKER")|$(_pa_clean "${PA_TOOL:-unknown}")|$1|$(_pa_clean "$2")|$(_pa_clean "$PA_HEAD" 120)"
}

# _pa_finish <allow|deny-fix|deny-reserved> <reason> [<message>] — log, answer, exit 0. An
# answer that cannot be put on the record is not an allow: no answer without a line.
_pa_finish() {
  local d="$1" r="$2" m="${3-}"
  if ! _pa_log "$d" "$r" 2>/dev/null && [ "$d" = allow ]; then
    d=deny-fix
    r="the answer could not be written to the answer log"
    m="bionic: denied, because $r ($(answers_path "$BIONIC_ROOT" 2>/dev/null || printf 'no HOME')). Report it to the lead; /bionic:doctor checks the install."
  fi
  if [ "$d" = allow ]; then _pa_emit allow; else _pa_emit deny "$m"; fi
  exit 0
}

# _pa_fail <what failed> — a failure after engagement: a denial that names it (AC-1.5).
_pa_fail() {
  _pa_finish deny-fix "failure: $1" \
    "bionic could not answer this permission question, so it is denied: $1. Tell the lead (the human, if you are the lead) what failed; /bionic:doctor checks the install."
}

# The trap: an exit that printed no decision prints the failure's denial, and the hook still
# exits 0 so the platform reads it.
_pa_on_exit() {
  local rc=$?
  [ "$PA_ANSWERED" = 1 ] && return 0
  trap - EXIT
  _pa_fail "the hook stopped (exit $rc) while $PA_STAGE"
}

# ---------- from here, every exit answers ----------
#
# The trap is armed only now, after every function it calls is defined: an exit between an
# armed trap and an undefined handler would be the silence this hook exists to rule out.
# The decision goes to the stdout the platform reads, kept on fd 3; everything else this
# process might print on fd 1 goes nowhere, so the one object is the only thing it reads.
PA_ANSWERED=0
PA_STAGE="starting"
PA_ASKER="lead"
PA_AGENT=""
PA_HEAD=""
exec 3>&1 >/dev/null
trap '_pa_on_exit' EXIT
trap 'exit 143' TERM INT HUP

# ---------- the question ----------
PA_STAGE="reading the question"
[ "$PA_PARSED" = 1 ] || _pa_fail "could not read the question: the payload is not a JSON object"
[ -n "$PA_TOOL" ] || _pa_fail "could not read the question: it names no tool"
PA_AGENT="$(_pa_field .agent_id)"
PA_SCRATCH="$(_pa_field .scratchpad_dir)"
PA_CWD="$(_pa_field .cwd)"
PA_CMD=""
PA_PATH=""
case "$PA_TOOL" in
  Bash) PA_CMD="$(_pa_field .tool_input.command)"; PA_HEAD="$PA_CMD" ;;
  Write|Edit|MultiEdit|Read) PA_PATH="$(_pa_field .tool_input.file_path)"; PA_HEAD="$PA_PATH" ;;
  NotebookEdit) PA_PATH="$(_pa_field .tool_input.notebook_path)"; PA_HEAD="$PA_PATH" ;;
  *) PA_HEAD="$(printf '%s' "$BIONIC_INPUT" | jq -c '.tool_input // {}' 2>/dev/null)" ;;
esac
[ -n "$PA_AGENT" ] && PA_ASKER="agent $PA_AGENT"

# ---------- who asked ----------
#
# The payload's agent_id, read through THIS session's roster (the session id in the payload
# is the lead's for every asker, measured); no agent_id is the lead. A first occurrence of a
# key wins, as every by-key reader of the roster takes it.
_pa_row_field() {  # <row> <key> -> the value of the first <key>= field
  local rest="|${1#*|}|" k="|$2="
  case "$rest" in *"$k"*) ;; *) return 0 ;; esac
  rest="${rest#*"$k"}"
  printf '%s' "${rest%%|*}"
}

PA_STAGE="finding who asked"
PA_NAME=""
PA_ROW=""
if [ -n "$PA_AGENT" ]; then
  PA_ROSTER="$BIONIC_ROOT/.bionic/tmp/roster-$BIONIC_SID.state"
  if [ -L "$PA_ROSTER" ]; then
    _pa_fail "the roster for this session is a symlink, which bionic refuses to follow"
  elif [ ! -e "$PA_ROSTER" ]; then
    _pa_fail "there is no roster for this session, so the asking agent $PA_AGENT cannot be found"
  elif [ ! -r "$PA_ROSTER" ]; then
    _pa_fail "the roster for this session cannot be read, so the asking agent $PA_AGENT cannot be found"
  fi
  PA_ROW="$(roster_row_for_id "$PA_ROSTER" "$PA_AGENT")" \
    || _pa_fail "the roster has no row for the asking agent $PA_AGENT"
  PA_NAME="$(_pa_row_field "$PA_ROW" name)"
  # An agent dispatched without a name has a real row whose name= is empty: that is a reader
  # (a tree is recorded for a name, and it has none), not a fault. It stays labelled by its id.
  [ -z "$PA_NAME" ] || PA_ASKER="$PA_NAME"
fi

# ---------- its class ----------
PA_STAGE="deciding the class of the asker"
PA_OWN=""
PA_BOUND=0
[ "$BIONIC_RUN_WORD" = bound-open ] && PA_BOUND=1
if [ -z "$PA_AGENT" ]; then
  case "$BIONIC_RUN_WORD" in
    bound-open) PA_CLASS=lead ;;
    bound-unreadable) _pa_fail "the run this session is bound to cannot be read ($BIONIC_RUN_PLAN)" ;;
    *) PA_CLASS=unbound ;;
  esac
elif [ -z "$PA_NAME" ]; then
  PA_CLASS=reader
else
  PA_OWN="$(workspace_for_name "$BIONIC_ROOT" "$BIONIC_SID" "$PA_NAME")"
  case "$?" in
    0) PA_CLASS=writer ;;
    1) PA_CLASS=reader; PA_OWN="" ;;
    *) _pa_fail "the workspace record for this session could not be read (a symlink, or a file that cannot be opened)" ;;
  esac
fi

# ---------- its roots, as facts ----------
#
# Every root goes through grant_resolve before the grant sees it; one that does not resolve
# is dropped (a grant only narrows). The main root is the exception: it only ever narrows, so
# one that does not resolve is a failure rather than a missing fact.
PA_STAGE="collecting the roots of the asker"
PA_MAIN="$(grant_resolve "$BIONIC_ROOT")" \
  || _pa_fail "the main root of the project, $BIONIC_ROOT, does not resolve to a real location"
PA_FACTS=("main=$PA_MAIN")
_pa_root() {  # <key> <path> — the fact, resolved, or nothing
  local r
  [ -n "${2:-}" ] || return 0
  r="$(grant_resolve "$2")" || return 0
  PA_FACTS[${#PA_FACTS[@]}]="$1=$r"
}

_pa_record_dir() {  # <plan> -> the run's record directory
  local b="${1##*/}"
  b="${b%.md}"; b="${b%.plan}"
  printf '%s/record/%s' "$(docs_root "$BIONIC_ROOT")" "$b"
}

_pa_root scratch "$PA_SCRATCH"
case "$PA_CLASS" in
  lead)
    PA_PLAN="$BIONIC_RUN_PLAN"
    PA_WB="$(plan_frontmatter_get "$PA_PLAN" working-branch)"
    if [ -n "$PA_WB" ]; then
      PA_CO="$(worktree_checkout_of "$BIONIC_ROOT" "$PA_WB" 2>/dev/null)" && _pa_root checkout "$PA_CO"
    fi
    PA_TREES="$(workspaces_of_session "$BIONIC_ROOT" "$BIONIC_SID")"
    case "$?" in
      0) while IFS= read -r PA_T; do _pa_root tree "$PA_T"; done <<< "$PA_TREES" ;;
      1) : ;;
      *) _pa_fail "the workspace record for this session could not be read (a symlink, or a file that cannot be opened)" ;;
    esac
    _pa_root record "$(_pa_record_dir "$PA_PLAN")"
    _pa_root plan "$PA_PLAN"
    for PA_K in spec requirements; do
      PA_V="$(plan_frontmatter_get "$PA_PLAN" "$PA_K")"
      case "$PA_V" in
        '') ;;
        /*) _pa_root plan "$PA_V" ;;
        *) _pa_root plan "$(docs_root "$BIONIC_ROOT")/$PA_V" ;;
      esac
    done
    ;;
  writer)
    _pa_root own "$PA_OWN"
    [ "$PA_BOUND" = 1 ] && _pa_root record "$(_pa_record_dir "$BIONIC_RUN_PLAN")"
    ;;
  reader)
    # The record directory is handed as the fact the report is bounded by (the grant decides
    # whether the report lies inside it or the scratch); a report that names a directory is
    # not a file and is handed nothing (wave-25 T17, review S1).
    [ "$PA_BOUND" = 1 ] && _pa_root record "$(_pa_record_dir "$BIONIC_RUN_PLAN")"
    PA_REPORT="$(_pa_row_field "$PA_ROW" deliverable)"
    case "$PA_REPORT" in
      ''|/*) ;;
      *) PA_REPORT="$BIONIC_ROOT/$PA_REPORT" ;;
    esac
    if [ -n "$PA_REPORT" ] && PA_REPORT_R="$(grant_resolve "$PA_REPORT")" && [ ! -d "$PA_REPORT_R" ]; then
      PA_FACTS[${#PA_FACTS[@]}]="report=$PA_REPORT_R"
    fi
    ;;
esac
grant_roots "$PA_CLASS" "${PA_FACTS[@]}" 2>/dev/null \
  || _pa_fail "the grant could not be composed from the recorded roots (grant_roots rc $?)"

# ---------- what the action does ----------
#
# Bash: the command reader in its `reads` mode, so a pure reader's reads come back as R and
# RR lines beside the W, D and ? lines, and every path is resolved in ONE process by
# grant_resolve_lines (a device sink is passed through by its literal name: on Linux
# /dev/stdout resolves into /proc). A path that cannot be resolved is passed on with its mark,
# which the decision reads as outside every root. PAST PA_EFFECTS_MAX LINES NOTHING IS
# RESOLVED: the answer is one `?` and a denial, because the platform kills this hook at its
# 10 s registration and a killed hook leaves the stock dialog, the halt it exists to remove
# (wave-25 review S3: 2000 operands took 18 s at one fork per path). The file tools: one W for
# the tool's own path, resolved. Read: no effect. Any other tool: unknown.
#
# THE NUMBER, 200 lines. Measured at load 17 (T17, recorded in record/wave-25-never-paused/
# T17-place-not-spelling.md): resolving, the reserved table and the decision took 0.8 s for
# 200 effects and 2.2 s for 500, and 2.5 s for 200 effects that are each a symlink (one
# readlink fork apiece). 200 keeps that worst case inside the 10 s registration with room for
# a machine loaded several times harder; a command with more targets is denied with the fix
# to put it in a script file.
PA_EFFECTS_MAX=200
_pa_bytes() {  # <text> -> its length in bytes
  local LC_ALL=C
  printf '%s' "${#1}"
}

# _pa_more_than <lines> <n> — rc 0 when the text holds more than <n> lines. It reads at most
# n+1 of them in this process, so a small question pays no fork for the count. Read, not cut
# off the front by expansion: under bash 3.2 each `${v#*<newline>}` copies and rescans the
# whole remainder, which on 2000 lines cost seconds (measured).
_pa_more_than() {
  local line n=0
  while IFS= read -r line; do
    n=$((n + 1))
    [ "$n" -gt "$2" ] && return 0
  done <<< "$1"
  return 1
}

PA_STAGE="reading what the action does"
PA_BIG=0
PA_MANY=0
PA_RAW=""
PA_EFFECTS=""
PA_RESOLVED_PATH=""
case "$PA_TOOL" in
  Bash)
    if [ -z "$PA_CMD" ]; then
      PA_EFFECTS="?${PA_TAB}the question names no command${PA_TAB}$PA_TOOL"
    elif [ "$(_pa_bytes "$PA_CMD")" -gt 65536 ]; then
      PA_BIG=1
      PA_EFFECTS="?${PA_TAB}command too large to read${PA_TAB}$(_pa_clean "$PA_CMD" 200)"
    else
      PA_RAW="$(cmd_effects "$PA_CMD" "$PA_CWD" reads 2>/dev/null)" \
        || _pa_fail "the command reader failed (cmd_effects rc $?)"
      if [ -n "$PA_RAW" ] && _pa_more_than "$PA_RAW" "$PA_EFFECTS_MAX"; then
        PA_MANY=1
        PA_N="$(printf '%s\n' "$PA_RAW" | awk 'END { print NR }')"
        PA_EFFECTS="?${PA_TAB}too many targets to read: $PA_N, past the $PA_EFFECTS_MAX bionic reads${PA_TAB}$(_pa_clean "$PA_CMD" 200)"
      else
        PA_EFFECTS="$(grant_resolve_lines "$PA_RAW")"
      fi
    fi
    ;;
  Write|Edit|MultiEdit|NotebookEdit)
    if [ -z "$PA_PATH" ]; then
      PA_EFFECTS="?${PA_TAB}the tool names no file${PA_TAB}$PA_TOOL"
    else
      PA_RESOLVED_PATH="$(grant_resolve "$PA_PATH")"
      PA_EFFECTS="W${PA_TAB}$PA_RESOLVED_PATH"
    fi
    ;;
  Read)
    # A read has no effect; one that names no file is a question bionic cannot read.
    if [ -z "$PA_PATH" ]; then
      PA_EFFECTS="?${PA_TAB}the tool names no file${PA_TAB}$PA_TOOL"
    else
      PA_RESOLVED_PATH="$(grant_resolve "$PA_PATH")"
    fi
    ;;
  *) PA_EFFECTS="?${PA_TAB}bionic cannot read what this tool does${PA_TAB}$PA_TOOL" ;;
esac

# ---------- the verdict ----------
#
# The reserved table is asked about the PLACE as well as the spelling (wave-25 T17, review
# B3): a file tool's path typed and resolved, and for Bash, after the command's own words,
# every path line the reader printed, typed and resolved, with the home directory handed in
# as a fact (a recursive read of it reaches every credential store). Either spelling matching
# is the category. A command past PA_EFFECTS_MAX is denied whatever the table says, so its
# lines are not read again here.
PA_STAGE="checking the reserved table"
PA_CAT=""
if [ "$PA_BIG" = 0 ]; then
  case "$PA_TOOL" in
    Bash)
      PA_CAT="$(grant_reserved Bash "$PA_CMD")" || _pa_fail "the reserved table failed (grant_reserved rc $?)"
      if [ -z "$PA_CAT" ] && [ "$PA_MANY" = 0 ] && [ -n "$PA_RAW" ]; then
        # The home directory is the fact an RR line is judged against; resolved only when
        # the reader printed one, so no other question pays for it.
        PA_HOME=""
        case "$PA_NL$PA_RAW" in
          *"${PA_NL}RR$PA_TAB"*)
            [ -z "${HOME:-}" ] || PA_HOME="$(grant_resolve "$HOME")" || PA_HOME="" ;;
        esac
        PA_CAT="$(grant_reserved_effects "$PA_HOME" "$PA_RAW$PA_NL$PA_EFFECTS")" \
          || _pa_fail "the reserved table failed (grant_reserved_effects rc $?)"
      fi
      ;;
    Write|Edit|MultiEdit|NotebookEdit|Read)
      PA_CAT="$(grant_reserved "$PA_TOOL" "$PA_PATH")" || _pa_fail "the reserved table failed (grant_reserved rc $?)"
      if [ -z "$PA_CAT" ] && [ -n "$PA_RESOLVED_PATH" ] && [ "$PA_RESOLVED_PATH" != "$PA_PATH" ]; then
        PA_CAT="$(grant_reserved "$PA_TOOL" "${PA_RESOLVED_PATH#\?"$PA_TAB"}")" \
          || _pa_fail "the reserved table failed (grant_reserved rc $?)"
      fi
      ;;
  esac
fi

PA_STAGE="deciding"
PA_VERDICT="$(grant_decide "$PA_CLASS" "$GRANT_WRITE_ROOTS" "$GRANT_DELETE_ROOTS" "$PA_EFFECTS" "$PA_CAT" "$GRANT_MAIN_ROOT" 2>/dev/null)" \
  || _pa_fail "the decision could not be made (grant_decide rc $?)"

# _pa_gate <category> — the gate request for the lead (D7): one line per distinct request
# (same asker, category and head), appended to .bionic/tmp/gate-<lead sid>.state. A symlink at
# any level of that path is refused, never followed, as the roster files are.
_pa_gate() {
  local f="$BIONIC_ROOT/.bionic/tmp/gate-$BIONIC_SID.state" head key
  { [ ! -L "$BIONIC_ROOT/.bionic" ] && [ ! -L "$BIONIC_ROOT/.bionic/tmp" ] && [ ! -L "$f" ]; } || return 1
  [ ! -e "$f" ] || [ -f "$f" ] || return 1
  head="$(_pa_clean "$PA_HEAD" 120)"
  key="|session=$(_pa_clean "$BIONIC_SID")|asker=$(_pa_clean "$PA_ASKER")|category=$1|head=$head"
  if [ -f "$f" ] && PA_GATE_KEY="$key" awk '
      BEGIN { k = ENVIRON["PA_GATE_KEY"]; m = length(k) }
      { n = length($0); if (n >= m && substr($0, n - m + 1) == k) { found = 1; exit } }
      END { exit !found }' "$f" 2>/dev/null; then
    return 0
  fi
  printf 'gate/v1|at=%s%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$key" >> "$f" 2>/dev/null
}

PA_STAGE="answering"
PA_KIND="${PA_VERDICT%%"$PA_TAB"*}"
PA_REST="${PA_VERDICT#*"$PA_TAB"}"
case "$PA_KIND" in
  allow)
    # A read is no effect: only a W or D line makes this an allow of effects.
    case "$PA_NL$PA_EFFECTS" in
      *"${PA_NL}W$PA_TAB"*|*"${PA_NL}D$PA_TAB"*) _pa_finish allow "every effect is inside the workspace" ;;
      *) _pa_finish allow "no effect: nothing is written or deleted" ;;
    esac
    ;;
  deny-fix)
    # The reason may carry a resolver's mark (a TAB); the fix never does, so it is the last field.
    PA_FIX="${PA_REST##*"$PA_TAB"}"
    PA_REASON="${PA_REST%"$PA_TAB"*}"
    PA_REASON="${PA_REASON//$PA_TAB/ }"
    _pa_finish deny-fix "$PA_REASON" "bionic: $PA_REASON $PA_FIX"
    ;;
  deny-reserved)
    PA_CATEGORY="${PA_REST%%"$PA_TAB"*}"
    PA_REASON="${PA_REST#*"$PA_TAB"}"
    PA_GATED=""
    _pa_gate "$PA_CATEGORY" || PA_GATED=" (the gate request could not be recorded: the gate file was refused)"
    _pa_finish deny-reserved "$PA_CATEGORY: $PA_REASON$PA_GATED" "bionic: $PA_REASON"
    ;;
  *)
    _pa_fail "the decision printed no verdict"
    ;;
esac
