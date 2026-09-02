#!/bin/bash
# THE PATROL-DUTIES WALL — task-dispatch-wall-channel-loss, T5.
#
# Stop. On every orchestrator turn end: if the turn was started by a PATROL TICK,
# refuse the stop once unless the tick's two standing duties were performed
# inside it — a subagent-panel refresh (`ListAgents`) and a task-list refresh
# (`TaskList`, or a write naming the active plan file). Any other turn passes
# untouched, as does any ambiguity along the way.
#
# WHY A WALL AND NOT BETTER WORDING. The duties live in the Patrol prompt today,
# and a prompt is text: it asks. Every rule in this repo that actually binds is a
# wall (memory/rules-are-walls-not-wishes), and the only event that can express
# "this must have happened before the turn ends" is the turn's END. A PreToolUse
# arm cannot say it — at the moment any single tool runs, the turn is not over
# and nothing has been skipped yet. So the predicate is retrospective by
# construction, and Stop is the one channel that can ask it.
#
# WHY ALWAYS-ON, AND WHAT SCOPES IT INSTEAD. This gate was registered in the governing
# skill's frontmatter so that it would be live exactly while that skill was — the duty
# it binds is the skill's own Patrol's. That coupling was the defect, not the design:
# a skill's registrations are looked up per session, so a `/clear`, a compaction or a
# session the skill was never invoked in left the wall installed, green in its own
# suite, and not running. The duty did not stop existing in those sessions; only the
# wall did.
#
# It is registered once in hooks/hooks.json now, on `Stop` — which still fires once per
# orchestrator turn and keeps firing on turns nothing was re-invoked. What scopes it is
# an ON-DISK fact: `active_run` under the payload's project root. A run is active while
# its plan says so, and that is the same fact that says a Patrol should be ticking.
#
# WHAT A "PATROL TICK" IS, STRUCTURALLY. The tick prompt is composed per session
# by a model and its wording is therefore not a fact anything may key on. What IS
# a fact is the command SKILL.md's Dispatch section makes the first of the
# prompt's reads: `session-poker.sh tick`. That literal in the turn's opening
# user message is the marker — the same structural-not-textual identification
# payload/scripts/lib/patrol.sh uses to recognise a Patrol cron job (T2 judgment
# call (b)), reached independently and agreeing.
#
# WHAT COUNTS, AND WHEN. Only AFTER the tick's own prompt: duties performed in
# some earlier turn are stale by exactly the interval the tick exists to cover.
# Only on the MAIN THREAD: a tool_use inside an agent context (`isSidechain`, or
# a non-empty agent key) belongs to a subagent, and a subagent's ListAgents did
# not refresh the orchestrator's panel — the mirror image of the exclusion
# hooks/session-poker.sh:399-406 makes for the same reason.
#
# THE TASK-LIST FALLBACK IS NOT A CONVENIENCE. The task tools are absent from
# some model/CLI combinations (memory/task-tools-tengu-gate: removed for fable-5
# in CLI 2.1.228–2.1.233), and in those sessions the plan's own ledger IS the
# task list. A wall that demanded `TaskList` there would be unsatisfiable, which
# is the one failure mode a blocking gate must not have. So an Edit/Write/
# NotebookEdit/Bash tool_use whose input names the active plan file discharges
# the same duty.
#
# FAIL DIRECTIONS (pinned by tests/patrol-duties-gate.test.sh):
#   - jq absent                                          -> pass, silent
#   - not a Stop payload (SubagentStop included)          -> pass, silent
#   - stop_hook_active true                               -> pass, silent (blocks ONCE)
#   - no cwd, or it is not a directory                    -> pass, silent
#   - no transcript_path, or no file there, or a symlink  -> pass, silent
#   - no user prompt in the transcript at all             -> pass, silent
#   - the last user prompt is not a Patrol tick           -> pass, silent
#   - both duties done since that prompt                  -> pass, silent
#   - either duty missing                                 -> REFUSE, naming which
#
# TWO ACCEPTED LIMITS, both a false BLOCK rather than a false silence, and both
# cheap because the refusal is once-only (stop again and the turn ends). First,
# the Stop-time transcript "isn't guaranteed to include the final message ... on
# all versions" (hooks reference, Stop input), so a duty discharged as the very
# last act of the turn may not be on disk when this reads it. Second, a Patrol
# tick that legitimately has nothing to do still owes both duties under this
# gate — which is the contract SKILL.md states, not an accident of the read.
#
# AND THERE IS NO BACKSTOP ABOVE OURS. This used to cite the hooks reference —
# "Claude Code overrides the hook and ends the turn after 8 consecutive blocks"
# — as the net under both limits. It is not one, for the same reason the same
# claim was struck from hooks/patrol-revive.sh (critic C-2, epic-19 w1): this
# gate blocks ONCE PER TURN by design (`stop_hook_active` → pass, below), and
# blocks one per turn are never consecutive, so that override can never engage
# above a hook shaped like this one. What bounds the refusal is the thing
# the reason line already names — do the two duties and stop again — not a
# counter in the CLI.
#
# IT WRITES NOTHING AND DECIDES NOTHING ELSE. No state file, no roster append, no
# stamp: this is a gate, and gates may only read (TDD §3.2). It takes no view on
# whether the tick's WORK was right, only on whether the two duties happened.
#
# Registered once on the Stop channel in hooks/hooks.json, always on, and scoped by
# `active_run` rather than by whether a skill is armed.
# [WALL: tests/patrol-duties-gate.test.sh]

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)

_jq() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

# ---------- relevance hoist ----------
# SubagentStop is deliberately NOT accepted. A subagent has no Patrol duties, and
# a wall that refused its stop would hold a worker hostage to its orchestrator's
# obligations.
[ "$(_jq '.hook_event_name')" = "Stop" ] || exit 0

# BLOCKS ONCE. Claude Code re-enters the stop with stop_hook_active true after a
# hook blocked it; refusing again would wedge the turn in a loop it has no way
# out of. One refusal names the duties; the second stop is the orchestrator's to
# decide about. That re-entry is also this gate's safety valve: nothing it can
# ever demand is unsatisfiable, because stopping again always passes.
[ "$(_jq '.stop_hook_active')" = "true" ] && exit 0

TRANSCRIPT=$(_jq '.transcript_path')
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && [ ! -L "$TRANSCRIPT" ] || exit 0

CWD="${CLAUDE_PROJECT_DIR:-}"
[ -n "$CWD" ] || CWD=$(_jq '.cwd')
[ -n "$CWD" ] && [ -d "$CWD" ] || exit 0

# ---------- the library ----------
#
# One loader idiom, byte-identical in every hook (spec AC-16). FAIL OPEN: this gate
# refuses a STOP, and a stop refused for a missing file is a turn nobody can end.
BIONIC_LIB_WANT="root.sh run.sh"
# --- bionic-loader/v2 BEGIN
# Find the bionic library. This text is pasted BYTE-IDENTICALLY into every hook; a
# library cannot load itself, so the duplication is the design and
# tests/cross-gate-agreement.test.sh pins every copy against `bionic_loader_pin` in
# payload/scripts/lib/loader.sh. Behaviour: tests/loader.test.sh.
#
# CONTRACT. Set BIONIC_LIB_WANT to the space-separated basenames this hook sources,
# on a line above this block. Afterwards exactly one of these is non-empty:
#   BIONIC_LIB          a readable directory holding every wanted basename
#   BIONIC_LIB_MISSING  the library this hook wanted and did not get
# BIONIC_LIB_CANDS always lists, in order, every location that was tried.
#
# CANDIDATES. Later classes are evaluated only after the earlier ones fail, so a
# healthy hook pays nothing for the healing path — not a jq, not a registry read.
#  (1) beside the hook. TWO SPELLINGS OF ONE DIRECTORY, because the shipped tree has
#      two real shapes: the installed plugin root, where hooks/ and scripts/ are
#      siblings, and the repo, where payload/hooks is a symlink to the top-level
#      hooks/ and the library lives under payload/scripts/lib. "$0" is textual and
#      `..` is resolved by the kernel AFTER the symlink, so the first spelling alone
#      would find nothing in a directory-source session.
#  (2) the marketplace SOURCE TREE. installed_plugins.json names the marketplace this
#      plugin was installed from; that marketplace's source.path in
#      known_marketplaces.json is the tree. The marketplace is read, never assumed:
#      a fork installs under its own name.
#  (3) the newest version directory in that marketplace's plugin cache, by
#      THREE-INTEGER compare — 1.10.0 beats 1.3.2, which a lexical sort gets backwards.
# (2) and (3) heal a partial breakage: one location damaged, a sibling intact. An
# upstream-broken publish breaks every location equally and is not covered.
#
# TESTS OVERRIDE THE MACHINE, never the reverse. BIONIC_PLUGINS_DIR (default
# "$HOME/.claude/plugins") is the only door to the registry and the cache.
BIONIC_LIB=""; BIONIC_LIB_MISSING=""; BIONIC_LIB_CANDS=""
_bl_dir="$(dirname "$0")"
_bl_want="${BIONIC_LIB_WANT:-}"
_bl_try() {
  [ -n "${1:-}" ] || return 1
  if [ -z "$BIONIC_LIB_CANDS" ]; then BIONIC_LIB_CANDS="$1"; else BIONIC_LIB_CANDS="$BIONIC_LIB_CANDS, $1"; fi
  [ -d "$1" ] || return 1
  for _bl_f in $_bl_want; do [ -r "$1/$_bl_f" ] || return 1; done
  BIONIC_LIB="$1"
}
if ! _bl_try "$_bl_dir/../scripts/lib" && ! _bl_try "$_bl_dir/../payload/scripts/lib"; then
  _bl_pd="${BIONIC_PLUGINS_DIR:-${HOME:-/nonexistent}/.claude/plugins}"
  _bl_mk=""
  if [ -r "$_bl_pd/installed_plugins.json" ]; then
    # First key only, and the prefix stripped by parameter expansion rather than
    # `sed | head`: the block's only external commands are `dirname` and `jq`, and
    # `jq` runs with its stderr closed, so a machine missing jq degrades to
    # BIONIC_LIB_MISSING in silence instead of printing a shell diagnostic.
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
  # The name in the message is the first library this hook asked for. A candidate
  # directory qualifies only when it holds ALL of them, so with none qualifying the
  # first wanted name is the honest thing to hand the reader.
  BIONIC_LIB_MISSING="${_bl_want%% *}"
  [ -n "$BIONIC_LIB_MISSING" ] || BIONIC_LIB_MISSING="scripts/lib"
fi
# FAIL OPEN — for every hook whose work is advisory or reversible. One line, then
# stand aside. Blocking reversible work because a file is missing buys no safety and
# costs the session.
loader_fail_open() {
  echo "$1: library ${BIONIC_LIB_MISSING:-the bionic library} not found at ${BIONIC_LIB_CANDS:-(no candidate)} — hook stepping aside; run /bionic:doctor" >&2
  exit 0
}
# FAIL CLOSED — for a wall over an irreversible action. Refuse, but never lock the
# user out of the repair: four commands are permitted by WHOLE-STRING match, checked
# here, before the hook sources anything. Whole-string and not prefix, so
# `claude plugin update bionic@bionic; git push origin main` is refused like any
# other push. There is no env-var override: a variable an agent turn can set on
# itself is not a wall.
loader_fail_closed() {
  _bl_root="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)" || _bl_root=""
  [ -n "$_bl_root" ] || _bl_root="$(dirname "$0")/.."
  case "${2:-}" in
    "claude plugin update bionic@bionic"|\
    "claude plugin install bionic@bionic"|\
    "bash $_bl_root/scripts/doctor.sh"|\
    "bash $_bl_root/scripts/setup.sh") exit 0 ;;
  esac
  cat >&2 <<BIONIC_LOADER_REFUSE
BLOCKED: $1 cannot load its library (${BIONIC_LIB_MISSING:-the bionic library}), so it
cannot read this command. A wall that cannot read a command refuses it rather than
waving it through.

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
  exit 2
}
# --- bionic-loader/v2 END
if [ -n "$BIONIC_LIB_MISSING" ]; then loader_fail_open "patrol-duties-gate"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"

PROJECT_DIR=$(project_root "$CWD")

# ---------- THE RUN PREDICATE (AC-7, AC-8) ----------
#
# Before the transcript is parsed, and that placement is the point. The full-transcript
# jq pass below is this hook's whole cost, and it used to run on every Stop in every
# session on the machine — 32.5ms with no transcript, 44.7ms over a 601-line one, scaling
# with the transcript, to answer a question that is only ever asked inside a run (R-2
# §(c)). Now a project with no open run pays one directory walk.
#
# It also answers "which plan" — the same reader, so this gate and the tick it polices
# cannot disagree about which file the duty is owed against.
PLAN=$(active_run "$PROJECT_DIR") || exit 0
PLAN_NAME=""
[ -n "$PLAN" ] && [ -f "$PLAN" ] && PLAN_NAME="$(basename "$PLAN")"

# ---------- the plan's BASENAME ----------
#
# Only the basename is kept. The path a tool_use carries may be absolute, repo-relative
# or cwd-relative depending on which tool wrote it, and the basename is the one form all
# three contain. An empty name matches nothing — guarded at the awk boundary, because an
# empty needle would otherwise make every write in the turn discharge the duty.

# ---------- reading the turn ----------
#
# One pass, two stages. jq flattens each transcript line into at most one record
# per event we care about; awk then folds that stream, resetting at every user
# PROMPT so that what survives to END describes the LAST turn only.
#
# A user-typed entry is a PROMPT only if it carries text. The `user` type is also
# how the CLI records every TOOL RESULT, and treating those as prompts would end
# the tick's turn at its first tool call — the wall would then be permanently
# silent, passing every tick in the fleet while looking installed and green.
#
# Newlines and tabs are squashed inside values because the stream is
# line-and-tab delimited; a prompt is many lines long and would otherwise forge
# records. Nothing downstream reads a value except by substring, so squashing
# costs no fidelity.
STREAM=$(jq -Rr '
  fromjson?
  | select((.isSidechain // false) != true)
  | select((((.agentId // .agent_id) // "") | tostring) == "")
  | if .type == "user" then
      ( if (.message.content | type) == "string" then .message.content
        else ([.message.content[]? | select(.type == "text") | .text] | join(" "))
        end ) as $t
      | select(($t // "") != "")
      | "USER\t" + ($t | gsub("[\n\t\r]"; " "))
    elif .type == "assistant" then
      .message.content[]?
      | select(.type == "tool_use")
      | "TOOL\t" + (.name // "")
        + "\t" + (((.input.file_path // .input.path // .input.command // "") | tostring) | gsub("[\n\t\r]"; " "))
    else empty
    end
' "$TRANSCRIPT" 2>/dev/null) || STREAM=""
[ -n "$STREAM" ] || exit 0

# TICK / LISTAGENTS / TASKLIST, folded over the last turn.
VERDICT=$(printf '%s\n' "$STREAM" | awk -F'\t' -v plan="$PLAN_NAME" '
  $1 == "USER" {
    tick = (index($0, "session-poker.sh tick") > 0)
    la = 0; tl = 0
    next
  }
  $1 == "TOOL" {
    if ($2 == "ListAgents") { la = 1; next }
    if ($2 == "TaskList")   { tl = 1; next }
    if (plan != "" && index($3, plan) > 0) {
      if ($2 == "Edit" || $2 == "Write" || $2 == "NotebookEdit" || $2 == "Bash") tl = 1
    }
    next
  }
  END {
    if (!tick) { print "quiet"; exit }
    if (la && tl) { print "quiet"; exit }
    if (!la && !tl) { print "both"; exit }
    if (!la) { print "listagents"; exit }
    print "tasklist"
  }
')

[ "$VERDICT" = "quiet" ] && exit 0
[ -n "$VERDICT" ] || exit 0

# ---------- the refusal ----------
#
# THE REASON NAMES WHAT IS MISSING AND NOTHING ELSE. A reason that recites both
# duties whichever one was skipped makes the reader re-derive the answer the gate
# already knows, and a gate that fires on every tick with the same paragraph is
# read as noise inside two ticks. Each string is a LITERAL: no payload value and
# no path is interpolated into it, so there is no JSON-quoting surface here at
# all.
case "$VERDICT" in
  both)
    REASON='Patrol duties incomplete: no ListAgents call, and no task-list refresh — TaskList or a plan-ledger write. Do both, then stop again — this gate blocks once.' ;;
  listagents)
    REASON='Patrol duties incomplete: no ListAgents call since this Patrol tick. Refresh the subagent panel, then stop again — this gate blocks once.' ;;
  tasklist)
    REASON='Patrol duties incomplete: no task-list refresh since this Patrol tick — TaskList or a plan-ledger write. Do one, then stop again — this gate blocks once.' ;;
  *)
    exit 0 ;;
esac

# The JSON decision payload on STDOUT with exit 0, the form Design (T5) names.
# (hooks/landing-gate.sh refuses through exit 2 + stderr instead; both are live
# Stop-hook block channels in this CLI, and the two gates deliberately do not
# share a mechanism they never share a code path with.)
jq -nc --arg r "$REASON" '{decision:"block",reason:$r}'
exit 0
