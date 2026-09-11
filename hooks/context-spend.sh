#!/bin/bash
# CONTEXT-SPEND: advisory Stop hook — appends ONE context-spend line per
# SDLC step boundary to $HOME/.claude/logs/<project-slug>/sdlc-audit.md —
# outside every consuming project tree (incident 0001), via audit_path() —
# reusing the log_v11_finding() line format (source: context-spend).
#
# Mechanism (epic-08 A7 / Q2 spike): Stop = trigger + transcript_path;
# last assistant message.usage (TOP-LEVEL, never iterations[]) = occupancy
# (input + cache_creation + cache_read); the active plan's `current:` line
# = step attribution; .bionic/tmp/context-spend.state = boundary detector.
# [INSTRUMENT]
#
# Failure mode: silence. Missing jq/transcript/usage/plan/current →
# exit 0, nothing appended, state untouched. NEVER blocks, NEVER writes
# stdout (a Stop hook's stdout could carry a block payload).
# [INSTRUMENT]
#
# Registered once in hooks/hooks.json, always on, and scoped by an on-disk fact rather
# than by whether a skill is armed: it asks `session_run` (which was `active_run` until
# wave-session-bound-run made run identity per-session) whether THIS SESSION has an open run
# and exits silently when it does not.

set -u

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)

PAYLOAD_SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || PAYLOAD_SID=""

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null) || TRANSCRIPT=""
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

CWD="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$CWD" ]; then
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || CWD=""
fi
[ -n "$CWD" ] && [ -d "$CWD" ] || exit 0

# ---------- the library ----------
#
# One loader idiom, byte-identical in every hook (spec AC-16). FAIL OPEN, and here that
# is barely a choice: this hook is an instrument. Its whole failure mode is silence, and
# a missing library is one more way to be silent.
BIONIC_LIB_WANT="root.sh run.sh session.sh"
# --- bionic-loader/v2 BEGIN
# Find the bionic library — pasted BYTE-IDENTICALLY into all 22 carriers, because a library
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
if [ -n "$BIONIC_LIB_MISSING" ]; then loader_fail_open "context-spend"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"

# ROOT, SESSION ID, RUN — the three facts, each from its one owner. The state file this
# hook diffs against is per (plan, session), so a root or an id spelled differently here
# than in the hook that wrote the plan produces a delta against nobody's occupancy.
ROOT=$(project_root "$CWD")
SESSION_ID=$(session_id "$PAYLOAD_SID" 2>/dev/null) || SESSION_ID=""
[ -n "$SESSION_ID" ] || SESSION_ID="unknown"
PROJECT_DIR="$ROOT"

# Incident 0001: the audit stream must live where a consuming project cannot
# commit it, regardless of that project's .gitignore. $HOME-rooted, per-project,
# durable — the same $HOME/.claude/ audit path the archived epic-10 poker used
# (that work is recoverable at tag archive/epic-10-never-die).
# Slug = <basename>-<cksum of the absolute path>: readable, deterministic, and
# collision-resistant across same-named projects under different parents.
# cksum and basename are POSIX — no new dependency.
# Byte-identical to the copies in farm-out-reminder.sh,
# canonical-sdlc-governing-skill.sh and canonical-sdlc-evidence-gate.sh —
# divergence would give one project two audit files. Deliberate per-hook
# duplication (no shared lib).
# [INSTRUMENT]
audit_path() {  # $1=project root → absolute audit-file path; rc 1 if no $HOME
  [ -n "${HOME:-}" ] || return 1
  local base sum
  base=$(basename "$1" | sed 's/[^A-Za-z0-9._-]/-/g')
  sum=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s/.claude/logs/%s-%s/sdlc-audit.md' "$HOME" "$base" "$sum"
}

# ---------- THE ENGAGEMENT SWITCH — asked before anything else ----------
#
# task-engaged-session: bionic's walls are the RUN's, not the repo's, and a run is entered
# by invoking canonical-sdlc. A session that never did is a bystander here and must not see
# a refusal, an advisory, or a state write from this hook. `engaged_session` (lib/run.sh) is
# true only for a REGULAR file at `.bionic/tmp/engaged-<sid>.state`; every unreadable state —
# absent, symlink, foreign sid, and the `unknown` fallback this hook substitutes above —
# reads as NOT engaged. Silent, exit 0: the direction §7 gives every start-side ambiguity,
# and here it is the consent boundary itself (1.3.2 close-out ruling).
engaged_session "$PROJECT_DIR" "$SESSION_ID" || exit 0

# ---------- THE RUN PREDICATE (AC-7, AC-8) ----------
#
# The plan AND the arming question, from one reader. This hook used to answer "which
# plan" with its own `ls -t` over three glob depths — a fourth spelling of a question
# five hooks were each answering differently, and the one that ignored the
# `## SDLC State` marker entirely, so any newest .md under plans/ could become the file
# it attributed a step boundary to.
#
# PLAN-BOUND, WHOLLY (task-engaged-session). Engagement decides WHETHER this hook acts and
# has decided yes above; what remains is the plan deciding WHAT, and every line below
# measures against it — the step boundary comes from the plan's `current:`, the state file
# is keyed by (plan, session), and the audit line names the plan. An engaged session with no
# plan on disk has no step boundary to record, so this arm skips rather than the hook being
# out of scope. The exit is an arm skip now, not the scoping decision it used to be.
#
# wave-session-bound-run S5: `active_run` (no session input) is now `session_run`
# (lib/run.sh) — a session BOUND to a plan is attributed against THAT plan alone,
# whatever else is open in the root (AC-1); UNBOUND falls back to the newest plan
# exactly as before, and this hook says so once on its advisory channel (stderr —
# this hook NEVER writes stdout, see the header) (AC-3); bound to a plan that has
# since closed takes exactly this line's existing branch — the hard exit — after
# announcing the closure (AC-6).
_RUN_VERDICT=$(session_run "$PROJECT_DIR" "$SESSION_ID")
_RUN_WORD="${_RUN_VERDICT%% *}"
PLAN="${_RUN_VERDICT#* }"
case "$_RUN_WORD" in
  bound-open) : ;;
  fallback)
    echo "context-spend: run resolved by newest-plan fallback (session unbound) — $PLAN" >&2
    ;;
  bound-closed)
    echo "context-spend: bound plan closed — $PLAN; this session has no open run" >&2
    exit 0
    ;;
  none|*)
    exit 0
    ;;
esac
[ -n "$PLAN" ] && [ -f "$PLAN" ] || exit 0

# current: from ## SDLC State — CR-normalized, fence-aware (the evidence-gate
# defect class: fenced skeletons quoting `current:` must stay invisible).
# [INSTRUMENT]
STEP=$(awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$PLAN" | awk '
  /^```/ { fence = !fence; next }
  fence { next }
  /^## SDLC State/ { insec = 1; next }
  insec && /^## / { insec = 0 }
  insec && /^current:[[:space:]]*/ { sub(/^current:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }
')
[ -n "$STEP" ] || exit 0

# Last assistant entry with usage, from a bounded tail. fromjson? swallows
# malformed lines. Emits "model<TAB>occupied" for the last qualifying entry.
_row=$(tail -n 400 "$TRANSCRIPT" 2>/dev/null | jq -Rr '
  fromjson? | select(.type == "assistant") | .message | select(.usage != null) |
  [(.model // "unknown"),
   ((.usage.input_tokens // 0) + (.usage.cache_creation_input_tokens // 0) + (.usage.cache_read_input_tokens // 0))] | @tsv
' 2>/dev/null | tail -1) || _row=""
[ -n "$_row" ] || exit 0
MODEL=${_row%	*}
OCCUPIED=${_row##*	}
case "$OCCUPIED" in ''|*[!0-9]*) exit 0 ;; esac
[ "$OCCUPIED" -gt 0 ] || exit 0

STATE_DIR="$PROJECT_DIR/.bionic/tmp"
STATE="$STATE_DIR/context-spend.state"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

s_plan=""; s_sess=""; s_step=""; s_occ=""
if [ -f "$STATE" ]; then
  IFS='	' read -r s_plan s_sess s_step s_occ < "$STATE" 2>/dev/null || true
fi

# First-seen, plan switch, or session switch: seed silently. Two
# concurrent sessions on the same plan must never diff against each
# other's occupancy — a session change re-seeds, same as a plan change.
# [INSTRUMENT]
if [ "$s_plan" != "$PLAN" ] || [ "$s_sess" != "$SESSION_ID" ] || [ -z "$s_step" ]; then
  printf '%s\t%s\t%s\t%s\n' "$PLAN" "$SESSION_ID" "$STEP" "$OCCUPIED" > "$STATE" 2>/dev/null || true
  exit 0
fi

# Same step: nothing to do (state deliberately untouched — it records the
# occupancy at the step's START boundary, so delta spans the whole step).
[ "$s_step" = "$STEP" ] && exit 0

# Boundary: emit one line for the ENDED step.
case "$s_occ" in ''|*[!0-9]*) s_occ="$OCCUPIED" ;; esac
DELTA=$((OCCUPIED - s_occ))
if [ "$DELTA" -ge 0 ]; then DELTA="+$DELTA"; fi
LINE="- $(date -u +%Y-%m-%dT%H:%M:%SZ) context-spend step-$s_step: occupied=$OCCUPIED delta=$DELTA model=$MODEL ($PLAN)"
if AUDIT_FILE=$(audit_path "$PROJECT_DIR"); then
  mkdir -p "$(dirname "$AUDIT_FILE")" 2>/dev/null && printf '%s\n' "$LINE" >> "$AUDIT_FILE" 2>/dev/null
fi
printf '%s\t%s\t%s\t%s\n' "$PLAN" "$SESSION_ID" "$STEP" "$OCCUPIED" > "$STATE" 2>/dev/null || true
exit 0
