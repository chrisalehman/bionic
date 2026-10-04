#!/bin/bash
# payload/scripts/close-out.sh — the Step 8/9 tail, performed by one script that attests
# its own acts (epic-23 wave-13-fixit-180, REQ-4; AC-4.1, AC-4.3, AC-4.4; design ledger
# D5, D6).
#
# WHAT THIS FILE OWNS. Nine acts that were prose in `skills/canonical-sdlc/steps/8.md`
# and `steps/9.md` and nothing else — a paragraph each, performed by hand, at the end of
# a run, by whoever was still awake. Research R3 took the census: of the nine, exactly one
# (`archive_run`) had code behind it. The rest were instructions, and an instruction that
# is followed nine times out of ten leaves a run that LOOKS closed and is not.
#
#     close-out.sh <plan-path> run      perform the tail and write the two lifecycle blocks
#     close-out.sh <plan-path> check    report what `run` would do; change nothing
#
# EVERY ACT IS IDEMPOTENT BY A READBACK OF ITS OWN RESULT, never by a flag this script
# sets. The merge act asks git whether the working branch is reachable — which is true
# again on the second run and cheap to ask. The branch sweep asks `git cherry`, then
# deletes, then asks `rev-parse` whether the branch is gone. The wipe counts what is left.
# The continuation and the epic row look for what they would write before writing it. The
# whole SCRIPT is idempotent by the same rule at a larger grain: a plan whose `- Step 9:`
# line already carries `delivered:` is a closed run, and a second `run` says `already
# closed` and touches nothing (AC-4.4). That marker is `lib/run.sh`'s own — the one every
# hook in this tree already reads — so there is no second notion of "closed" to drift.
#
# THE GATE IS ASKED FIRST, AND ASKED AGAIN AS THE ATTESTATION (critic3 P-1, wave-23 T17).
# Before the first act, `run` refuses unless `current:` reads 8 and then writes phase 8's
# block into a scratch copy of the plan and asks the real gate about the copy; a refusal
# there ends the run with nothing touched, and `check` asks the same question, so the two
# verbs agree on every plan.
#
# THE GATE IS THE ATTESTATION, AND IT IS NOT OPTIONAL (D5: "a script writes a lifecycle
# artifact only where a gate validates what it wrote"). After the acts, the order is Step-8 block, then
# the dry-run, then the Step-9 flip (`current: 9`, `delivered:`, handoff): the gate must
# judge the plan while it is still OPEN, because once it reads closed the gate exits 0
# before it checks any step evidence (critic2 N-3). A refusal leaves the plan at current 8
# and never flips it. This script builds the payload a `git commit` would produce and pipes it into the REAL
# `hooks/bash-walls.sh`. rc 0 is reported as `gate: ok`; rc 2 prints the gate's own words
# and exits 2 with the plan edits LEFT IN PLACE, because those edits are what the reader
# has to fix. A script that wrote a Step-8 block the commit wall then refused would have
# automated the exact failure this task exists to end.
#
# THE DRY-RUN ARMS ITS OWN ENGAGEMENT, for its own synthetic session id, and takes it
# away again. It has to: act 3 wipes this session's own keyed state under `.bionic/tmp/`
# (Chris 2026-09-14 — the tmp directory is disposable after close; a LIVE neighbour's
# state is spared instead, REQ-1/D2, because that spare list binds a running run and a
# concurrent session sharing this root IS one), and the engagement marker lives there.
# Without this the gate would
# find an unengaged session, do nothing, exit 0, and hand back a `gate: ok` that had
# checked nothing at all — the arming partition's fail direction turned into a lie. A
# SYNTHETIC id, never the live one: removing the live session's marker at the end would
# disengage the session that is running this script.
#
# TWO ACTS ARE INSTRUCTIONS AND SAY SO. `TaskUpdate` and `CronDelete` are model tools;
# a shell script cannot call either. Printing the exact instruction is the whole of what
# this script can honestly do for them, and printing it in the same line shape as the
# seven acts it does perform is what keeps the report readable as one thing.
#
# THE ARCHIVE COMES LAST, AFTER THE GATE, AND THAT IS NOT THE ORDER THE ACTS ARE NUMBERED
# IN. `archive_run` moves a run only when every plan under its slug reads CLOSED to
# `run_open` — and this plan reads closed only once THIS script has written `delivered:`
# on the Step-9 line. Called any earlier the act is vacuous: it can only ever answer
# "still has an open run", naming the plan being closed. So the move is asked for after
# the blocks are written and after the gate has passed on them, and its one line is then
# inserted into the Step-9 block as `archived:`. The binding check does NOT wait: it runs
# in preflight, before the first act, so a drifted destination refuses while there is
# still nothing to undo.
#
# BASH 3.2. No associative arrays, no `mapfile`, no `${var^^}` — the same floor every
# library here is written to.
#
# Executed, never sourced:  bash ${CLAUDE_PLUGIN_ROOT}/scripts/close-out.sh <plan> run
#
# [WALL: tests/close-out.test.sh]

set -uo pipefail

# ─── Locating this payload ───────────────────────────────────────────────────
#
# No `dirname` here, for the reason every library in this tree gives: a script that
# needs coreutils to find itself dies on the half-broken machine it exists for.
_co_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}
CO_SCRIPTS="$(cd "$(_co_self_dir)" && pwd -P)"
CO_LIB="$CO_SCRIPTS/lib"

# The payload-integrity guard setup.sh and doctor.sh both carry. The list is what THIS
# script sources, not what the payload contains: a missing library here has no report to
# print, and the alternative is the interpreter's own error trace.
for _co_lib in roots.sh root.sh run.sh archive.sh patrol.sh units.sh; do
  if [ ! -f "${CO_LIB}/${_co_lib}" ]; then
    echo "close-out.sh: cannot find ${CO_LIB}/${_co_lib} — the payload looks incomplete." >&2
    echo "              reinstall with: claude plugin install bionic@bionic" >&2
    exit 2
  fi
done

# shellcheck source=/dev/null
. "${CO_LIB}/roots.sh"
# shellcheck source=/dev/null
. "${CO_LIB}/run.sh"
# shellcheck source=/dev/null
. "${CO_LIB}/archive.sh"
# shellcheck source=/dev/null
. "${CO_LIB}/patrol.sh"
# shellcheck source=/dev/null
. "${CO_LIB}/units.sh"

# CO_SID -> this script's own identity, read from the ambient environment BEFORE
# anything below ever touches CLAUDE_CODE_SESSION_ID (`gate_ask`'s one
# `CLAUDE_CODE_SESSION_ID=` override, shared by the pre-flight, the attestation and
# `check`, exists for its own purposes and must never be allowed to
# shadow the real one first). REQ-1's tmp-spare rule (act_tmp, D2) keys on this: an
# entry under `.bionic/tmp` belonging to a DIFFERENT, still-live session is a running
# run's state and is spared; this session's own keyed state is removed like any other
# closed run's. Empty when the script runs with no session id in its environment (a
# manual invocation) — every entry then falls to the live/dead check on its own merits,
# never to an "own session" exemption that cannot apply.
CO_SID="${CLAUDE_CODE_SESSION_ID:-}"

# ─── Voice ───────────────────────────────────────────────────────────────────
#
# ONE LINE PER ACT ON STDOUT, and refusals in the same stream: this script's whole output
# is a report that a close-out run is captured into, and a refusal split onto stderr would
# be missing from exactly the record that needed it most.
say() { printf '%s\n' "$*"; }

# _co_refuse <sentence> -> the one line and exit 2. `archive_run`'s own refusals are
# passed through verbatim instead (they are already in this shape), never re-wrapped.
# Named `_co_refuse`, not the bare `refuse` this file used before: the renderer in
# payload/scripts/lib/refuse.sh already owns that name (cross-gate-agreement.test.sh
# §Refuse(e), "Refuse refuse() is defined exactly once in the tree"), and the two are
# not interchangeable — the renderer takes five arguments, this one takes a sentence.
# Same rename spawn-worktree.sh's private helper took (`_wt_refuse`, ruling D-6).
_co_refuse() {
  printf 'bionic: close-out refused — %s\n' "$*"
  exit 2
}

usage() {
  echo "usage: close-out.sh <plan-path> run|check" >&2
  echo "       run    perform the Step 8/9 tail and write both lifecycle blocks" >&2
  echo "       check  report what run would do, and change nothing" >&2
}

# ─── Arguments ───────────────────────────────────────────────────────────────

PLAN="${1:-}"
VERB="${2:-}"
if [ -z "$PLAN" ] || [ -z "$VERB" ]; then
  usage
  _co_refuse "this call names no plan, or no verb — the verbs are run and check"
fi
case "$VERB" in
  run|check) : ;;
  *)
    usage
    _co_refuse "unknown verb '$VERB' — the verbs are run and check"
    ;;
esac
[ -f "$PLAN" ] || _co_refuse "no plan file at $PLAN"
# Absolutised without `dirname`, the same way this file locates itself: `${PLAN%/*}` is
# the parent for any path carrying a slash, and `.` for a bare filename.
case "$PLAN" in
  */*) _co_plan_dir="${PLAN%/*}" ;;
  *)   _co_plan_dir="." ;;
esac
PLAN="$(cd "$_co_plan_dir" 2>/dev/null && pwd -P)/${PLAN##*/}"
[ -f "$PLAN" ] || _co_refuse "no plan file at $PLAN"

# ─── Where everything is ─────────────────────────────────────────────────────

PLANS_DIR="${PLAN%/*}"
ROOT="$(project_root "$PLANS_DIR")"
[ -n "$ROOT" ] || ROOT="$(project_root)"
[ -n "$ROOT" ] || _co_refuse "no project root above $PLAN"

DROOT="$(docs_root "$ROOT")"
TMP_DIR="$(tmp_root "$ROOT")"
EPIC_PLAN="$PLANS_DIR/epic.plan.md"
WAVE_SLUG="${PLAN##*/}"
WAVE_SLUG="${WAVE_SLUG%.plan.md}"
WAVE_NUM="$(printf '%s' "$WAVE_SLUG" | sed -nE 's/^wave-([0-9]+).*/\1/p')"
CONT_REL="record/$WAVE_SLUG/continuation.md"
CONT="$DROOT/$CONT_REL"
NOW="$(date -u +%Y-%m-%dT%H:%MZ)"
TODAY="$(date -u +%Y-%m-%d)"

# co_version -> the version this payload declares, which is what `attested-by:` names.
# `unknown` rather than an empty string when the manifest cannot be read: an attestation
# that names no version is still an attestation, and a blank after "close-out.sh" reads
# like a truncation.
co_version() {
  local f="$(plugin_root)/.claude-plugin/plugin.json" v=""
  if [ -f "$f" ]; then
    v="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1)"
  fi
  printf '%s\n' "${v:-unknown}"
}
VERSION="$(co_version)"

# ─── The plan as a document ──────────────────────────────────────────────────

# sdlc_section -> the `## SDLC State` section, line endings normalized, terminated by the
# next flush-left `## ` heading. The same extraction the evidence gate makes (walls.sh
# :1372) so this script and the wall that validates it read one section.
sdlc_section() {
  normalize_newlines "$PLAN" | awk '
    /^## SDLC State/ { f = 1; next }
    f && /^## / { exit }
    f { print }'
}

# sdlc_header <key> -> the value of a flush-left `<key>: <value>` line in that section.
sdlc_header() {
  local key="$1" section="$2"
  grep -E "^[[:space:]]*${key}[[:space:]]*:" <<< "$section" \
    | head -1 \
    | sed -E "s/^[[:space:]]*${key}[[:space:]]*:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//'
  return 0
}

SECTION="$(sdlc_section)"
[ -n "$SECTION" ] || _co_refuse "$PLAN carries no ## SDLC State section"
INTEGRATION="$(sdlc_header integration-branch "$SECTION")"
WORKING="$(sdlc_header working-branch "$SECTION")"
# `run` closes a plan at Step 8 and nowhere else (critic3 P-3, wave-23 T17): the gate judges
# whatever step `current:` names, so below 8 its refusal would be about a step this script
# never writes, and above 8 there is nothing left for it to close.
CURRENT="$(sdlc_header current "$SECTION")"
STEP_REFUSAL="the plan reads current: ${CURRENT:-<none>} — advance the plan to Step 8 first"

# ─── Preflight ───────────────────────────────────────────────────────────────
#
# AC-4.4 FIRST, before any tool is even looked for: a closed run is not a run this script
# has anything to say about, and a second call must be able to answer that on a machine
# where jq has since been uninstalled.
if grep -qE '^[[:space:]]*-?[[:space:]]*Step 9:.*delivered:' <<< "$(normalize_newlines "$PLAN")"; then
  say "already closed"
  exit 0
fi

command -v git >/dev/null 2>&1 || _co_refuse "git is not on PATH"
command -v jq  >/dev/null 2>&1 || _co_refuse "jq is not on PATH — the gate dry-run cannot be built without it"
[ -n "$INTEGRATION" ] || _co_refuse "the plan's ## SDLC State names no integration-branch:"
[ -n "$WORKING" ]     || _co_refuse "the plan's ## SDLC State names no working-branch:"

# THE WORKTREE CENSUS IS THE REGISTER, NEVER A NAME (D5, REQ-6; ADR-032). A tree is
# this run's if and only if a `## Tasks` row names it — `wt_branches()` (below) reads
# the table's `worktree` cells directly instead of reconstructing a `wt/NN-*` glob
# from `working-branch:`'s shape. That shape guess used to pick up every branch this
# repository ever spawned under a wave number — foreign writers carrying commits this
# wave's working branch never took (A-orch-45) — and refused act 2 outright on any
# plan whose `working-branch:` was not `wave/<digits>-<slug>` shaped (R6 finding 1: a
# consumer's `w51/04-fixit` could never reach act 1 at all). The register has neither
# failure mode: a row is either in this plan's table or it is not, so a plan naming no
# trees gets an EMPTY census — the conservative failure, never a refusal — and a plan
# naming exactly N trees gets exactly those N, however `working-branch:` is spelled.

# THE COLUMN-LESS FALLBACK IS SCOPED EXACTLY AS 1.8.3 WAS (critic C7). A table with no
# `worktree` column at all has no register to read at all, so `wt_unreached` (below)
# falls back to a name-shape glob the way 1.8.3's ONLY census worked — but that glob has
# to be `wt/<NN>-*`, the same scope 1.8.3 used, not the unscoped `wt/*` this file shipped
# between the register's introduction and this fix (C7: 55 foreign branches in this
# repository alone, any one of which could trip a column-less consumer's close-out on a
# wave it never touched). `WT_NUM` is read off `working-branch:` exactly as 1.8.3 read it
# (`git show 72e07ec:payload/scripts/close-out.sh:244`), and a `working-branch:` that is
# not `wave/<digits>-<slug>` shaped refuses HERE — before act 1, for both `check` and
# `run`, exactly as 1.8.3 refused unconditionally — because a repo-wide census on that
# shape would be, in 1.8.3's own words, "the defect wearing a guard". A table WITH the
# `worktree` column never reaches this at all: the register names its own trees and needs
# no wave number to scope anything to (ADR-032's retirement stands, unchanged, for it).
#
# A TASK-SCALE PLAN OWNS NO WAVE (T11, AC-9.2): a small late fix closes from a branch like
# `fixit/x`, so a `scale: task` plan with no `worktree` column gets an empty `WT_NUM` and
# no refusal — there is no `wt/<NN>-*` for it to census, and `wt_unreached` (below) reports
# none. The shape refusal stays exactly as it was for every other scale.
WT_NUM=""
if ! units_has_column "$PLAN" worktree; then
  WT_NUM="$(printf '%s' "$WORKING" | sed -nE 's#^wave/([0-9]+)-.*#\1#p')"
  if [ -z "$WT_NUM" ] && [ "$(plan_frontmatter_get "$PLAN" scale)" != "task" ]; then
    _co_refuse "the plan's working-branch '$WORKING' is not wave/<digits>-<slug> shaped — the worktree census needs a wave number to scope wt/NN-* to"
  fi
fi

# THE BINDING, ASKED BEFORE THE FIRST ACT (AC-4.2, D6). `archive_run` carries this check
# too — that is where it belongs, so every caller inherits it — but by the time the move
# is asked for, eight acts have already happened. A destination that drifted since Step 0
# is a fault in the whole call, and the honest place to say so is before anything is done.
BINDING_LINE="$(archive_binding_check "$ROOT" "$PLANS_DIR")"
if [ -n "$BINDING_LINE" ]; then
  say "$BINDING_LINE"
  exit 2
fi

# ─── Act 1: merge ────────────────────────────────────────────────────────────

MERGE_LINE=""
act_merge() {
  local ws is
  ws="$(git -C "$ROOT" rev-parse --short "$WORKING" 2>/dev/null)"
  is="$(git -C "$ROOT" rev-parse --short "$INTEGRATION" 2>/dev/null)"
  [ -n "$ws" ] || _co_refuse "the plan's working-branch '$WORKING' is not a branch in $ROOT"
  [ -n "$is" ] || _co_refuse "the plan's integration-branch '$INTEGRATION' is not a branch in $ROOT"
  if git -C "$ROOT" merge-base --is-ancestor "$WORKING" "$INTEGRATION" 2>/dev/null; then
    MERGE_LINE="$WORKING @ $ws reachable from $INTEGRATION @ $is"
    return 0
  fi
  _co_refuse "$WORKING @ $ws is not reachable from $INTEGRATION @ $is — merge the working branch before the tail runs"
}

# ─── Act 2: worktree branches ────────────────────────────────────────────────
#
# TWO PASSES, AND THE ORDER IS THE WHOLE OF AC-4.3. The census runs to completion before
# a single `branch -D`, so a refusal leaves EVERY branch standing — not just the one that
# caused it. `git cherry <upstream> <head>` prints one line per commit on <head>: `-` when
# an equivalent patch is already upstream, `+` when nothing upstream matches it. A `+` is
# work that exists only on that branch, and deleting the branch would be the last moment
# anyone could have noticed.
WT_LINE=""
# wt_branches -> the registered trees' branches, in `## Tasks` table order: for each
# row whose `worktree` cell is filled (non-empty, not `—`), `wt/<basename of the
# cell>` when this repository actually holds that branch (D5, ADR-032; A6 —
# spawn-worktree.sh's own tree<->branch contract, pinned at
# tests/spawn-worktree.test.sh's Group 11). A row naming a tree this repository does
# not hold names nothing to the census — silently absent, the same as an unfilled
# cell; there is nothing else for this function to say about it. `units_rows` returns
# rc 1 for a plan with no `## Tasks` table at all, which this treats the same as zero
# rows: an empty census, not a fault.
wt_branches() {
  local rows line cell b
  rows="$(units_rows "$PLAN")" || return 0
  [ -n "$rows" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    cell="$(units_field "$line" worktree)"
    case "$cell" in ''|'—') continue ;; esac
    cell="${cell%/}"
    b="wt/${cell##*/}"
    git -C "$ROOT" show-ref --verify --quiet "refs/heads/$b" && printf '%s\n' "$b"
  done <<< "$rows"
  return 0
}

# wt_unreached -> every wt/* branch carrying a commit the working branch never took. The
# candidate list is the register census (`wt_branches`, D5/ADR-032) when the plan's
# `## Tasks` table declares the `worktree` column. A table WITHOUT that column — every
# plan this repository shipped through wave-16, and every consumer plan on 1.8.3 (critic
# C4) — reads an empty register, and an empty register here is the PERMISSIVE failure:
# this arm's whole job is to refuse, and an empty census means it never can, silently.
# `units_has_column` (lib/units.sh — the SSoT for "does this table carry that column at
# all") tells the two shapes apart; a column-less table falls back to the pre-register
# glob census — `wt/<NN>-*`, scoped to `$WT_NUM` exactly as 1.8.3 scoped it (derived and
# validated once, above, before act 1 — a working-branch that could not supply a wave
# number is refused there, except for a task-scale plan, which reaches this function with
# an empty `$WT_NUM` and gets an empty census, the `elif` below) — and announces
# the fallback once on stderr so it is never silent either way. Critic C7: the unscoped
# `wt/*` this arm shipped with between the register's introduction and this fix could
# trip on a DIFFERENT wave's leftover branch; `wt/<NN>-*` cannot.
wt_unreached() {
  local b _co_cherry candidates
  if units_has_column "$PLAN" worktree; then
    candidates="$(wt_branches)"
  elif [ -z "$WT_NUM" ]; then
    candidates=""
  else
    echo "close-out: no worktree column in the ## Tasks table; unreached-work census falls back to wt/${WT_NUM}-* (1.8.3 census)" >&2
    candidates="$(git -C "$ROOT" for-each-ref --format='%(refname:short)' "refs/heads/wt/${WT_NUM}-*" 2>/dev/null)"
  fi
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    # THE CENSUS IS CAPTURED BEFORE IT IS SEARCHED. `git cherry … | grep -q` under
    # pipefail is the fail-DANGEROUS shape: grep exits at its first match, git takes
    # SIGPIPE, pipefail promotes 141 to the pipeline, and the `if` reads a branch that
    # DOES carry unreached work as clean. A here-string is fully written before the
    # reader starts (run_open's own §R4 note).
    _co_cherry="$(git -C "$ROOT" cherry "$WORKING" "$b" 2>/dev/null)"
    if grep -q '^+' <<< "$_co_cherry"; then
      printf '%s\n' "$b"
    fi
  done <<< "$candidates"
  return 0
}

# refuse_unreached -> the census half of act 2, alone: read-only, so `run` asks it before
# the pre-flight as well as here (T17 — every refusal that can be known before the first
# act is given before it).
refuse_unreached() {
  local unreached
  unreached="$(wt_unreached)"
  if [ -n "$unreached" ]; then
    _co_refuse "$(printf '%s' "$unreached" | tr '\n' ' ' | sed -E 's/[[:space:]]+$//') carries a commit $WORKING never took (git cherry) — nothing was deleted, and nothing else was done"
  fi
  return 0
}

act_worktrees() {
  local b removed="" wt_dir
  refuse_unreached

  while IFS= read -r b; do
    [ -n "$b" ] || continue
    # The TREE first, then the branch: git refuses to delete a branch that is checked out
    # in a linked worktree, and `spawn-worktree.sh remove` is the verb that owns the
    # removal (its guards — a `.git` FILE, inside the farm — are what keep this from ever
    # being handed the main checkout).
    wt_dir="$ROOT/.worktrees/${b#wt/}"
    if [ -d "$wt_dir" ] && [ -f "$wt_dir/.git" ]; then
      bash "$CO_SCRIPTS/spawn-worktree.sh" remove "$wt_dir" >/dev/null 2>&1 || true
    fi
    git -C "$ROOT" worktree prune >/dev/null 2>&1
    git -C "$ROOT" branch -D "$b" >/dev/null 2>&1
    # The readback: the act's own result, asked of git rather than assumed from a status.
    if git -C "$ROOT" rev-parse --verify --quiet "refs/heads/$b" >/dev/null 2>&1; then
      _co_refuse "$b survived its deletion — the branch is still in $ROOT"
    fi
    removed="${removed:+$removed, }$b"
  done <<< "$(wt_branches)"

  WT_LINE="${removed:-none}"
}

# ─── Act 3: the tmp wipe ─────────────────────────────────────────────────────
#
# ITS OWN STATE, DEAD SESSIONS' STATE, AND THE EPHEMERA — NEVER A LIVE NEIGHBOUR'S
# (REQ-1, D2; corrected 2026-09-15 — Chris 2026-09-14's "the whole directory" ruling
# assumed a close-out is always the LAST session sharing this root, and that is not so:
# a concurrent session — a different wave, a different worktree — can be live under the
# same `.bionic/tmp` at the same instant, and its keyed state is a RUNNING run's, exactly
# the class `steps/8.md`'s spare list already protects). `CO_SID` (above) is this
# session's own identity. An entry keyed to another session (`<class>-<sid>.state[.armed]`,
# the classes `lib/patrol.sh`'s `PATROL_STATE_CLASSES` owns) is spared only while
# `patrol_dead_sessions` still counts that session live; this session's own keyed state,
# every dead session's, and every unkeyed entry (`context-spend.state`, `farm-out.state`,
# …) are removed exactly as before. The gate dry-run below re-arms its own marker
# regardless, because this act still takes the one that was there for THIS session.
TMP_LINE=""
tmp_count() {
  find "$TMP_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '
  return 0
}

# _co_tmp_owner <basename> -> the session id a tmp entry's basename is keyed to on
# stdout, or nothing at all when the entry is not session-keyed (an ephemera file, or
# anything shaped outside `PATROL_STATE_CLASSES`). One definition, walking the SAME
# class list `patrol_session_state_files` builds its own paths from, so a class added
# there is recognised here without a second list to keep in step.
_co_tmp_owner() {
  local base="$1" class owner
  for class in $PATROL_STATE_CLASSES; do
    case "$base" in
      "$class"-*.state|"$class"-*.state"$PATROL_STATE_ARMED_SUFFIX")
        owner="${base#"$class"-}"
        owner="${owner%"$PATROL_STATE_ARMED_SUFFIX"}"
        owner="${owner%.state}"
        [ -n "$owner" ] && printf '%s\n' "$owner"
        return 0
        ;;
    esac
  done
  return 0
}

act_tmp() {
  local before after entry owner dead_ids spare_list="" removed=0 spared=0 is_spared
  before="$(tmp_count)"

  if [ -d "$TMP_DIR" ]; then
    dead_ids="$(patrol_dead_sessions "$ROOT")"

    # Build the spare set FIRST, as full paths — every file keyed to a session other
    # than CO_SID that patrol_dead_sessions does not name. This session's own keyed
    # state is never in it (it is removed like a closed run's own, whatever the
    # sweeper's verdict on this pid would be), and neither is anything unkeyed.
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      owner="$(_co_tmp_owner "${entry##*/}")"
      [ -n "$owner" ] || continue
      [ "$owner" = "$CO_SID" ] && continue
      # SET MEMBERSHIP, SPELLED IN `case`. Both lists here are newline-delimited, so a
      # name is "in" the list when the list — wrapped in a leading and trailing newline
      # — contains that name wrapped in a leading and trailing newline too: the wrapper
      # is what keeps "ab" from matching a list entry "a" or "b" on a bare substring
      # test. `$dead_ids` gets both wrappers spelled here; the second case below (testing
      # `$spare_list`) already ends in one from how `spare_list` is built, so only the
      # leading newline is added there — same idiom, one wrapper already paid for.
      case "
$dead_ids
" in
        *"
$owner
"*) continue ;;   # dead — falls through to the removal pass below
      esac
      spare_list="${spare_list}${entry}
"
      spared=$((spared + 1))
    done <<< "$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 2>/dev/null)"

    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      is_spared="no"
      case "
$spare_list" in
        *"
$entry
"*) is_spared="yes" ;;
      esac
      [ "$is_spared" = "yes" ] || { rm -rf "$entry"; removed=$((removed + 1)); }
    done <<< "$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 2>/dev/null)"
  fi

  after="$(tmp_count)"
  [ "$after" = "$spared" ] || _co_refuse "$after entries remain under $TMP_DIR after the wipe ($spared expected, for a live neighbour's spared state)"
  TMP_LINE="$before entries under $TMP_DIR ($removed removed, $spared spared for a live neighbour session; this session's own state and every dead session's are never spared)"
}

# ─── Act 4: the task list ────────────────────────────────────────────────────
#
# TaskUpdate is a model tool. This is the instruction, printed in the acts' own shape.
TASKS_LINE="mark every 4/*, 5–9 entry completed (TaskUpdate)"

# ─── Act 5: the continuation ─────────────────────────────────────────────────
#
# `<fill>` MARKS WHAT ONLY THE ORCHESTRATOR KNOWS, and marks it rather than guessing it.
# The task count, the floor result, the rulings, the carry-overs and the next wave's ideas
# file are facts about the run, not about the tree; a template that invented plausible
# values for them would produce a continuation that read true and was not. The shape is
# wave-12-fixit-171's, heading for heading.
#
# NEVER OVERWRITTEN. A continuation that already exists has been edited by the person who
# knew those answers, and the second run of a close-out is exactly when that edit would be
# destroyed.
CONT_LINE=""
continuation_template() {
  local sha
  sha="$(git -C "$ROOT" rev-parse --short "$INTEGRATION" 2>/dev/null)"
  cat <<CONT_TEMPLATE
# continuation — $WAVE_SLUG (bionic $VERSION)

Closed $NOW. $INTEGRATION at ${sha:-<fill: SHA>}. Wave branch \`$WORKING\` merged into
\`$INTEGRATION\`: <fill: task count> tasks, every one RED→GREEN; <fill: floor result>.
<fill: reviews, audits, ADRs>.

## Chris decides (one decision each)

1. <fill: the first decision, or "none">

## Ruled at close

- <fill: what was ruled at this close, or "none">

## Next wave: <fill: version> — \`<fill: ideas path>\`

<fill: carry-overs from this wave>

## Resume instruction

Nothing to resume: the run is delivered. <fill: Patrol job id> deleted and the stamp
disarmed at close. The epic plan (\`${EPIC_PLAN#"$DROOT"/}\`) carries this wave's row;
this file is the wave-local copy.
CONT_TEMPLATE
}

act_continuation() {
  if [ -f "$CONT" ]; then
    CONT_LINE="$CONT_REL already written — left as it stands"
    return 0
  fi
  mkdir -p "${CONT%/*}" 2>/dev/null
  continuation_template > "$CONT" 2>/dev/null
  [ -s "$CONT" ] || _co_refuse "could not write the continuation at $CONT"
  CONT_LINE="$CONT_REL written from the close-out template (<fill> marks what only the orchestrator knows)"
}

# ─── Act 6: the epic's shipped-wave row ──────────────────────────────────────
#
# KEYED ON THE WAVE NUMBER, which is the only column that cannot be two things at once.
# The table is found by its HEADER ROW rather than by the heading above it: a heading is
# prose somebody may reword, and the header is the table's own. An epic can carry more than
# one table headed `wave` (a planned one beside the shipped one), so the header is the one
# whose first cell is `wave` AND which has a `shipped` cell.
EPIC_LINE=""

# epic_shipped_table <file> [<row>] -> the ONE locator for that table, shared by the reader
# (`epic_has_row`), the presence check (`presence_missing`) and the writer (`act_epic`).
# With no row: prints the table, header through its last row (the rows run to the first
# line not starting `|`), or nothing when the file has no such table. With a row: prints the
# whole file with the row appended to that table. The row travels in the environment, not
# `-v`, because `-v` would interpret the backslashes a spec path can carry.
epic_shipped_table() {
  CO_ROW="${2:-}" awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function shipped_header(line,   n, a, i) {
      n = split(line, a, "|")
      if (tolower(trim(a[2])) != "wave") return 0
      for (i = 3; i <= n; i++) if (tolower(trim(a[i])) == "shipped") return 1
      return 0
    }
    BEGIN { row = ENVIRON["CO_ROW"] }
    !seen && /^\|/ && shipped_header($0) { intable = 1; seen = 1 }
    intable && !/^\|/ { if (row != "" && !done) { print row; done = 1 } intable = 0 }
    row != "" || intable { print }
    END { if (row != "" && intable && !done) print row }
  ' "$1" 2>/dev/null
}

# epic_adrs -> the ADR numbers this wave shipped, `040, 041`, or nothing. The spec the
# plan's `spec:` line names carries `adrs:` as paths joined by ` · `; the plan's own `adrs:`
# is the fallback for a spec without one. Each segment yields its first `adr-<digits>`.
epic_adrs() {
  local specrel specfile adrs
  specrel="$(plan_frontmatter_get "$PLAN" "spec")"
  [ -n "$specrel" ] || specrel="$WAVE_SLUG.spec.md"
  specfile="$DROOT/$specrel"
  [ -f "$specfile" ] || specfile="$(find "$DROOT/specs" -name "${specrel##*/}" -type f 2>/dev/null | head -1)"
  [ -n "$specfile" ] && adrs="$(plan_frontmatter_get "$specfile" "adrs")" || adrs=""
  [ -n "$adrs" ] || adrs="$(plan_frontmatter_get "$PLAN" "adrs")"
  printf '%s\n' "$adrs" | awk '
    {
      n = split($0, seg, / · /)
      for (i = 1; i <= n; i++) {
        s = seg[i]; sub(/^.*\//, "", s)
        if (match(s, /adr-[0-9]+/)) printf "%s%s", (out++ ? ", " : ""), substr(s, RSTART + 4, RLENGTH - 4)
      }
    }'
}

epic_row() {
  local spec sha adrs
  spec="$(plan_frontmatter_get "$PLAN" "spec")"
  spec="${spec##*/}"
  [ -n "$spec" ] || spec="$WAVE_SLUG.spec.md"
  # THE SHA IS FILLED, NOT MARKED. Act 1 has already proved the working branch reachable
  # from the integration branch, so the integration head is a fact this script holds. The
  # ADR cell is read from the spec's `adrs:` line; it stays `<fill: ADRs>` only when neither
  # the spec nor the plan names one, because "none shipped" and "not recorded" look the same
  # on disk.
  sha="$(git -C "$ROOT" rev-parse --short "$INTEGRATION" 2>/dev/null)"
  adrs="$(epic_adrs)"
  printf '| %s | %s | `%s` | `%s`, `.requirements.md` | %s | %s, %s @ %s |\n' \
    "$WAVE_NUM" "$VERSION" "${PLAN##*/}" "$spec" "${adrs:-<fill: ADRs>}" "$TODAY" "$INTEGRATION" "${sha:-<fill: SHA>}"
}

epic_has_row() {
  [ -f "$EPIC_PLAN" ] || return 1
  epic_shipped_table "$EPIC_PLAN" | grep -qE "^\|[[:space:]]*${WAVE_NUM}[[:space:]]*\|"
}

act_epic() {
  if [ ! -f "$EPIC_PLAN" ]; then
    EPIC_LINE="none — no epic.plan.md beside this plan"
    return 0
  fi
  if epic_has_row; then
    EPIC_LINE="wave $WAVE_NUM is already listed in ${EPIC_PLAN##*/} — left as it stands"
    return 0
  fi
  local tmp="$EPIC_PLAN.close-out.$$"
  epic_shipped_table "$EPIC_PLAN" "$(epic_row)" > "$tmp"
  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    _co_refuse "could not rewrite ${EPIC_PLAN##*/} to add the wave $WAVE_NUM row"
  fi
  mv "$tmp" "$EPIC_PLAN"
  epic_has_row || _co_refuse "the wave $WAVE_NUM row did not land in ${EPIC_PLAN##*/}"
  EPIC_LINE="wave $WAVE_NUM appended to ${EPIC_PLAN##*/}"
}

# ─── Act 8: the Patrol ───────────────────────────────────────────────────────
#
# CronDelete is a model tool and `disarm` is a hook verb; both sides have to be stopped
# (dispatch.md:24), so both are named in one line.
PATROL_LINE="CronDelete the bionic-patrol job, then: bash $(plugin_root)/hooks/session-poker.sh disarm"

# ─── Act 9 and the two lifecycle blocks ──────────────────────────────────────
#
# EVERY KEY ON ITS OWN CONTINUATION LINE, NEVER SEMICOLON-JOINED. `block_get`
# (walls.sh:1856) reads a block with a line-anchored `^<key>:` regex and takes the FIRST
# match, so `merge: a; worktree-removed: b` on one line is a block with ONE key in it and
# every other key reads as missing — A-orch-49's finding, and 39 keys across 34 blocks were
# added to clear it once.
#
# `delivered:` IS INLINE ON THE STEP-9 LINE, with exactly one space after `Step 9:`.
# `run_open` (run.sh:293) greps `^[[:space:]]*-?[[:space:]]*Step 9:.*delivered:` — a
# literal single space, no `[[:space:]]+` tolerance, unlike the gate's own regex beside
# it. A `delivered:` written onto a continuation line satisfies the gate and leaves the
# run OPEN to every other reader in the fleet, forever.
step8_block() {
  cat <<STEP8
- Step 8: CLOSED $NOW — $WORKING merged into $INTEGRATION; the tail was performed by close-out.sh $VERSION
  merge: $MERGE_LINE
  worktree-removed: $WT_LINE
  cleanup: done
  tmp-wiped: $TMP_LINE
  tasks-completed: $TASKS_LINE
  attested-by: close-out.sh $VERSION
STEP8
}

step9_block() {
  cat <<STEP9
- Step 9: delivered: $NOW $WAVE_SLUG $VERSION — the Step 8/9 tail was performed by close-out.sh and attested against the commit gate; continuation at $CONT_REL
  attested-by: close-out.sh $VERSION
STEP9
}

handoff_block() {
  local main_sha
  main_sha="$(git -C "$ROOT" rev-parse --short "$INTEGRATION" 2>/dev/null)"
  cat <<HANDOFF
## Handoff

- resume point: NONE — DELIVERED at $NOW; $INTEGRATION @ ${main_sha:-<fill: SHA>}.
- branch: $WORKING merged into $INTEGRATION.
- patrol: $PATROL_LINE
- continuation: $CONT_REL
HANDOFF
}

# write_plan_blocks <8|9> [target] — the plan is written in TWO PHASES so the commit gate can judge
# the Step-8 block while the plan is still open (critic2 N-3, wave-23 T16).
#   8  replaces the Step-8 line with whatever continuation lines it had. `current:` stays
#      at 8, so the plan still reads OPEN to `run_open` and the bound dry-run is judged by
#      the gate's step-evidence checks, not short-circuited by `bound-closed`.
#   9  replaces the Step-9 line, sets `current: 9`, and rewrites `## Handoff` whole. After
#      this the plan reads closed and the gate exits 0 before it looks at evidence.
# [target] defaults to the plan; the pre-flight (below) passes a scratch copy of it instead.
#
# A CONTINUATION LINE IS DROPPED BY THE SAME GRAMMAR THE GATE READS IT BY
# (`extract_continuation`, walls.sh:1697): everything after a Step line up to the next
# `Step N:` line or the next line starting at column zero. Anything else and a second
# close would leave the old block's keys underneath the new one, where `block_get`'s
# first-match rule would quietly prefer them.
write_plan_blocks() {
  local phase="$1" target="${2:-$PLAN}"
  local tmp="$target.close-out.$$"
  CO_PHASE="$phase" CO_STEP8="$(step8_block)" CO_STEP9="$(step9_block)" CO_HANDOFF="$(handoff_block)" awk '
    /^## / {
      insdlc = ($0 ~ /^## SDLC State/)
      skip = 0
      if ($0 ~ /^## Handoff/ && ENVIRON["CO_PHASE"] == "9") { print ENVIRON["CO_HANDOFF"]; hskip = 1; next }
      hskip = 0
      print; next
    }
    hskip { next }
    skip {
      if ($0 ~ /^[[:space:]]*$/) next
      if ($0 ~ /^[^[:space:]]/) { skip = 0 }
      else if ($0 ~ /^[[:space:]]*-?[[:space:]]*Step[[:space:]]+[0-9]/) { skip = 0 }
      else next
    }
    insdlc && ENVIRON["CO_PHASE"] == "9" && /^[[:space:]]*current[[:space:]]*:/ { print "current: 9"; next }
    insdlc && ENVIRON["CO_PHASE"] == "8" && /^[[:space:]]*-?[[:space:]]*Step[[:space:]]+8[[:space:]]*:/ {
      print ENVIRON["CO_STEP8"]; skip = 1; next
    }
    insdlc && ENVIRON["CO_PHASE"] == "9" && /^[[:space:]]*-?[[:space:]]*Step[[:space:]]+9[[:space:]]*:/ {
      print ENVIRON["CO_STEP9"]; skip = 1; next
    }
    { print }
  ' "$target" > "$tmp" 2>/dev/null

  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    _co_refuse "could not rewrite $target"
  fi
  mv "$tmp" "$target"

  if [ "$phase" = 8 ]; then
    grep -qE '^- Step 8: CLOSED ' "$target" || _co_refuse "the Step-8 line did not land in $target"
    grep -qE '^  attested-by: close-out.sh ' "$target" || _co_refuse "the attestation did not land in $target"
    return 0
  fi

  # A plan that carried no `## Handoff` section gets one rather than silently losing the
  # act: the section is the run's own resume point, and its absence is not consent.
  if ! grep -q 'resume point: NONE — DELIVERED at ' "$PLAN"; then
    printf '\n%s\n' "$(handoff_block)" >> "$PLAN"
  fi

  # The readback, act by act: every phase-9 line this function claims to have written,
  # asked for back out of the file (phase 8 read its own back above).
  grep -qE '^[[:space:]]*-?[[:space:]]*Step 9:.*delivered:' "$PLAN" \
    || _co_refuse "the Step-9 delivered: line did not land in $PLAN"
  grep -qE '^current: 9$' "$PLAN" || _co_refuse "current: did not advance to 9 in $PLAN"
  grep -q 'resume point: NONE — DELIVERED at ' "$PLAN" || _co_refuse "the handoff was not rewritten in $PLAN"
}

# ─── The gate ────────────────────────────────────────────────────────────────

# gate_ask <plan-file> <sid> -> GATE_RC, GATE_ERR (the gate's whole stderr) and GATE_LINE
# (its one refusal line) for a `git commit` judged against <plan-file>. Status 9, with
# GATE_LINE saying why, when there is no gate to ask; 0 otherwise, whatever the verdict.
#
# THE MARKER IS BOUND TO THE FILE UNDER CHECK (wave-23-fixit-1810 T12). An empty marker is
# the unbound state, whose commit-gate verdict is an announcement and exit 0, so the
# dry-run would attest nothing. The two-line shape binding.sh's bind_plan writes, with the
# plan stored directly: bind_plan refuses any file that `open_runs` does not list, and the
# pre-flight's scratch copy is deliberately not one (its name does not end `.plan.md`, so
# no other session's walk can ever pick it up).
#
# The environment agrees with the payload because on a real call it does: lib/session.sh
# takes the env value as primary and the payload as a witness, and a dry-run whose two
# disagreed would be answered for a session that does not exist.
GATE_RC=0
GATE_ERR=""
GATE_LINE=""
gate_ask() {
  local plan="$1" sid="$2" hook marker input
  GATE_RC=9; GATE_ERR=""; GATE_LINE=""
  hook="$(plugin_root)/hooks/bash-walls.sh"
  [ -f "$hook" ] || { GATE_LINE="no bash-walls.sh at $hook"; return 9; }
  marker="$(engaged_marker_path "$ROOT" "$sid")" \
    || { GATE_LINE="could not build an engagement marker path for the dry-run"; return 9; }
  mkdir -p "${marker%/*}" 2>/dev/null
  printf 'plan=%s\nengaged_at=%s\n' "$plan" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$marker"
  input="$(jq -n --arg s "$sid" --arg cwd "$ROOT" \
    '{session_id: $s,
      cwd: $cwd,
      hook_event_name: "PreToolUse",
      tool_name: "Bash",
      tool_input: {command: "git commit -m close-out"},
      tool_use_id: "toolu_closeout"}')"
  GATE_ERR="$(CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$sid" bash "$hook" <<< "$input" 2>&1 >/dev/null)"
  GATE_RC=$?
  rm -f "$marker"
  GATE_LINE="$(grep -m1 '^bionic: ' <<< "$GATE_ERR")"
  [ -n "$GATE_LINE" ] || GATE_LINE="$(grep -m1 '[^[:space:]]' <<< "$GATE_ERR")"
  return 0
}

# gate_dry_run -> the ATTESTATION: the gate asked about the plan as this run wrote it, Step-8
# block in place and still open at current 8. A refusal here is rare now that the pre-flight
# asked the same question first; it is kept because the pre-flight judged a copy and this
# judges the file the commit will carry.
gate_dry_run() {
  gate_ask "$PLAN" "closeout-$$" || _co_refuse "$GATE_LINE — the blocks cannot be attested"
  if [ "$GATE_RC" -eq 0 ]; then
    say "gate: ok"
    return 0
  fi
  [ -n "$GATE_ERR" ] && printf '%s\n' "$GATE_ERR"
  _co_refuse "the commit gate refused the blocks this run wrote (rc=$GATE_RC) — the plan edits are left in place, because they are what to fix"
}

# ─── The pre-flight: the gate's question, asked before the first act ─────────
#
# ASKED OF A COPY, BEFORE ANYTHING IS TOUCHED (critic3 P-1, wave-23 T17). The attestation
# above judges the plan after acts 1–6, and by then the `wt/*` branches are deleted, this
# session's tmp state is wiped and the continuation and epic row are written. A refusal the
# Step-8 block cannot clear (a matrix, evidence or ledger fault) used to land there, on a
# half-closed run. So the same question is asked first: the plan is copied to a hidden
# scratch file beside it (same directory, so every path the gate resolves from the plan
# resolves the same), phase 8's block is written into the copy, a synthetic marker is bound
# to the copy, and the real gate judges it. The copy is removed whatever the answer, and by
# the EXIT trap if the script dies in between.
#
# THE BLOCK CARRIES PREDICTIONS, NOT RESULTS. The merge, census and wipe have not run yet,
# so their lines are what they will say. The gate's Step-8 check is presence-only
# (walls.sh `validate_integrate_step` -> `shape_block`); a gate that ever reads those
# values is caught by the attestation, which judges the real ones.
#
# PREFLIGHT_RC is GATE_RC, or 9 when the block could not be written or there is no gate;
# PREFLIGHT_LINE is the one line to show, PREFLIGHT_ERR the gate's whole answer. Every
# mention of the scratch path is put back to the plan's, because the copy is gone by the
# time anyone reads it.
CO_SCRATCH=""
trap '[ -n "$CO_SCRATCH" ] && rm -f "$CO_SCRATCH"' EXIT
PREFLIGHT_RC=0
PREFLIGHT_LINE=""
PREFLIGHT_ERR=""
preview_block_lines() {
  local ws is wt
  ws="$(git -C "$ROOT" rev-parse --short "$WORKING" 2>/dev/null)"
  is="$(git -C "$ROOT" rev-parse --short "$INTEGRATION" 2>/dev/null)"
  MERGE_LINE="$WORKING @ ${ws:-?} reachable from $INTEGRATION @ ${is:-?}"
  wt="$(wt_branches | tr '\n' ',' | sed -E 's/,$//; s/,/, /g')"
  WT_LINE="${wt:-none}"
  TMP_LINE="$(tmp_count) entries under $TMP_DIR (not yet wiped)"
}

# presence_missing -> the first thing a later act needs and the files do not carry, or
# nothing. Both used to be readbacks that fired AFTER the destructive acts (critic4 Q-1):
# phase 9 replaces a `- Step 9:` line it never finds and then refuses because none landed,
# and act 6 appends to a `| wave |` table it never finds and then refuses because no row
# landed. Each is known before the first act, so each is asked here, by presence alone.
presence_missing() {
  if ! awk '
    /^## / { insdlc = ($0 ~ /^## SDLC State/) }
    insdlc && /^[[:space:]]*-?[[:space:]]*Step[[:space:]]+9[[:space:]]*:/ { found = 1 }
    END { exit !found }
  ' "$PLAN" 2>/dev/null; then
    printf 'no Step 9 line in ## SDLC State of %s (add `- Step 9: (pending)`)' "$PLAN"
    return 0
  fi
  if [ -f "$EPIC_PLAN" ] && [ -z "$(epic_shipped_table "$EPIC_PLAN")" ]; then
    printf 'no | wave | table with a shipped column in %s for the wave %s row to be written into' "${EPIC_PLAN##*/}" "$WAVE_NUM"
  fi
  return 0
}

gate_preflight() {
  local copy out
  copy="$PLANS_DIR/.${PLAN##*/}.preflight.$$"
  CO_SCRATCH="$copy"
  PREFLIGHT_RC=9; PREFLIGHT_LINE=""; PREFLIGHT_ERR=""
  preview_block_lines
  if ! cp "$PLAN" "$copy" 2>/dev/null; then
    rm -f "$copy"; CO_SCRATCH=""
    PREFLIGHT_LINE="could not copy the plan to $copy"
    return 0
  fi
  # A SUBSHELL, so write_plan_blocks' own refusal ends it and not this script: `check`
  # must still report, and `run` refuses below with the reason in hand.
  if ! out="$(write_plan_blocks 8 "$copy")"; then
    rm -f "$copy"; CO_SCRATCH=""
    out="${out//"$copy"/$PLAN}"
    PREFLIGHT_LINE="${out#bionic: close-out refused — }"
    return 0
  fi
  gate_ask "$copy" "closeout-preflight-$$"
  rm -f "$copy"; CO_SCRATCH=""
  [ "$GATE_RC" -eq 9 ] && { PREFLIGHT_LINE="$GATE_LINE"; return 0; }
  PREFLIGHT_RC="$GATE_RC"
  PREFLIGHT_LINE="${GATE_LINE//"$copy"/$PLAN}"
  PREFLIGHT_ERR="${GATE_ERR//"$copy"/$PLAN}"
  return 0
}

# ─── Act 7: the archive ──────────────────────────────────────────────────────
#
# ITS LINES ARE COLLAPSED ONTO ONE. `archive_run` prints one line for a skip or a refusal
# and one PER MOVED TREE for a move (up to three: specs, plans, adrs). `archived:` is a
# block continuation line, and a value carrying a newline would be read by `block_get` as
# one key followed by two lines of nothing — so the lines are joined with `; ` and the
# value stays a value.
ARCHIVED_LINE=""
act_archive() {
  local out rc
  out="$(archive_run "$PLANS_DIR" 2>&1)"
  rc=$?
  ARCHIVED_LINE="$(printf '%s' "$out" | tr '\n' '\036' | sed -E 's/\036$//; s/\036/; /g')"
  if [ "$rc" -ne 0 ]; then
    say "$out"
    _co_refuse "the archive step refused; the plan is closed and the refusal above is what to fix"
  fi
  return 0
}

# insert_archived -> writes the `archived:` key into the Step-9 block, immediately under
# the `delivered:` line. The plan may have MOVED: `archive_run` renames the whole run
# directory, and the line it printed is where it went.
insert_archived() {
  local target="$PLAN" moved tmp
  if [ ! -f "$target" ]; then
    moved="$(printf '%s' "$ARCHIVED_LINE" \
      | tr ';' '\n' \
      | sed -nE 's/.*bionic: archived .*plans\/[^ ]+ -> ([^ ]+).*/\1/p' \
      | head -1)"
    [ -n "$moved" ] && [ -f "$moved/${PLAN##*/}" ] && target="$moved/${PLAN##*/}"
  fi
  [ -f "$target" ] || _co_refuse "the plan is no longer at $PLAN and the archive line does not say where it went"

  tmp="$target.close-out.$$"
  CO_ARCHIVED="  archived: $ARCHIVED_LINE" awk '
    { print }
    /^[[:space:]]*-?[[:space:]]*Step 9:.*delivered:/ && !done { print ENVIRON["CO_ARCHIVED"]; done = 1 }
  ' "$target" > "$tmp" 2>/dev/null
  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    _co_refuse "could not write the archived: line into $target"
  fi
  mv "$tmp" "$target"
  grep -qE '^  archived: ' "$target" || _co_refuse "the archived: line did not land in $target"
}

# ─── check ───────────────────────────────────────────────────────────────────
#
# A DIAGNOSIS IS NOT A FAILURE (doctor.sh's rule, applied here). `check` reports what the
# tail would do and what the gate says about the plan AS IT STANDS — which, at Step 8, is
# usually a refusal, because the block `run` is about to write is not written yet. That is
# the answer, not an error, so this verb exits 0 either way.
do_check() {
  local ws is verdict unreached branches wt_list wt_count wt_word wt_desc count
  if [ "$CURRENT" = 8 ]; then
    say "step: current: 8"
  else
    say "step: WOULD REFUSE — $STEP_REFUSAL"
  fi
  MISSING="$(presence_missing)"
  [ -z "$MISSING" ] || say "presence: WOULD REFUSE — $MISSING"
  ws="$(git -C "$ROOT" rev-parse --short "$WORKING" 2>/dev/null)"
  is="$(git -C "$ROOT" rev-parse --short "$INTEGRATION" 2>/dev/null)"
  if git -C "$ROOT" merge-base --is-ancestor "$WORKING" "$INTEGRATION" 2>/dev/null; then
    verdict="$WORKING @ ${ws:-?} reachable from $INTEGRATION @ ${is:-?}"
  else
    verdict="WOULD REFUSE — $WORKING @ ${ws:-?} is not reachable from $INTEGRATION @ ${is:-?}"
  fi
  say "merge: $verdict"

  # THE CENSUS NAMES ITS SOURCE, NOT JUST ITS RESULT (D5). `wt_branches` reads the
  # register now — no scoped glob to report — so the line instead says how many
  # `## Tasks` rows it found trees for, a number a reader can check against the plan
  # by eye. Zero registered trees is the conservative failure and says so BY NAME
  # rather than printing an empty list a reader could mistake for a scan that found
  # nothing to scan.
  #
  # THE TWO CENSUSES CAN DISAGREE (C4). `wt_unreached` falls back to the unregistered
  # `wt/*` glob on a column-less table (above), so `unreached` can be non-empty while
  # the REGISTER's own `wt_count` reads zero — a plan with no `worktree` column at all
  # registers nothing, but its fallback census can still name a branch to refuse on.
  # The WOULD-REFUSE clause is therefore keyed on `unreached` alone, never gated behind
  # `wt_count`, so `check` never goes silent on exactly the plans C4 found silent.
  wt_list="$(wt_branches)"
  wt_count="$(printf '%s\n' "$wt_list" | grep -c '[^[:space:]]')"
  unreached="$(wt_unreached)"
  branches="$(printf '%s' "$wt_list" | tr '\n' ' ' | sed -E 's/[[:space:]]+$//')"
  wt_word="tree"; [ "$wt_count" = 1 ] || wt_word="trees"
  if [ "$wt_count" -eq 0 ]; then
    wt_desc="census: no registered trees"
  else
    wt_desc="${branches} (${wt_count} registered ${wt_word})"
  fi
  if [ -n "$unreached" ]; then
    say "worktree-removed: ${wt_desc} WOULD REFUSE — $(printf '%s' "$unreached" | tr '\n' ' ' | sed -E 's/[[:space:]]+$//') carries a commit $WORKING never took"
  else
    say "worktree-removed: ${wt_desc}"
  fi

  count="$(tmp_count)"
  say "tmp-wiped: $count entries under $TMP_DIR"
  say "tasks-completed: $TASKS_LINE"
  if [ -f "$CONT" ]; then
    say "continuation: $CONT_REL already written — left as it stands"
  else
    say "continuation: $CONT_REL would be written from the close-out template"
  fi
  if [ ! -f "$EPIC_PLAN" ]; then
    say "epic-row: none — no epic.plan.md beside this plan"
  elif epic_has_row; then
    say "epic-row: wave $WAVE_NUM is already listed in ${EPIC_PLAN##*/}"
  else
    say "epic-row: $(epic_row)"
  fi
  say "patrol: $PATROL_LINE"
  say "handoff: would be rewritten to the closed form (resume point NONE)"
  # THE ARCHIVE IS NAMED, NEVER ASKED. `archive_run` has no dry mode and this verb has no
  # licence to move anything, so `check` reports the destination the binding fixed and
  # leaves the verdict to `run`, which asks once the plan reads closed.
  say "archived: archive_run would be asked for $PLANS_DIR into $(archive_root "$ROOT") once the plan reads closed"

  # THE GATE, ASKED TWICE, WRITING NOTHING BUT A SCRATCH COPY AND A SYNTHETIC MARKER, both
  # removed again.
  #
  # AS IT STANDS: at Step 8 this is usually a refusal, because the block `run` writes is
  # not written yet. It is the witness that the gate reads this plan and discriminates on
  # what the script writes into it (§4's 4e beside §1's 1af/1ag).
  #
  # AS RUN WOULD WRITE IT: the pre-flight `run` itself asks before its first act, so this
  # line and `run`'s outcome cannot disagree (critic3 P-1). Its refusal is the gate's own
  # line, never a sentence of this script's about what would clear it.
  gate_ask "$PLAN" "closeout-check-$$" || { say "gate: skipped — $GATE_LINE"; return 0; }
  if [ "$GATE_RC" -eq 0 ]; then
    say "gate: ok against the plan as it stands"
  else
    say "gate: would refuse the plan as it stands (rc=$GATE_RC): $GATE_LINE"
  fi
  if [ "$CURRENT" != 8 ]; then
    say "gate: not asked for the plan run would write — run stops at the step line above first"
    return 0
  fi
  gate_preflight
  if [ "$PREFLIGHT_RC" -eq 0 ]; then
    say "gate: ok against the plan run would write"
  elif [ "$PREFLIGHT_RC" -eq 9 ]; then
    say "gate: WOULD REFUSE before the gate is asked — $PREFLIGHT_LINE"
  else
    say "gate: WOULD REFUSE the plan run would write (rc=$PREFLIGHT_RC): $PREFLIGHT_LINE"
  fi
  return 0
}

# ─── run ─────────────────────────────────────────────────────────────────────

do_run() {
  # NOTHING IS TOUCHED UNTIL ALL FIVE OF THESE PASS (critic3 P-1, P-3), in this order: the
  # step `run` closes, the two presence checks (a Step-9 line, a `| wave |` table), the merge verdict (act 1 is a readback and touches nothing), the
  # branch census, and the gate's answer about the plan `run` will write. Any refusal leaves
  # every branch, every tmp entry, the plan and the epic plan exactly as they were.
  [ "$CURRENT" = 8 ] || _co_refuse "$STEP_REFUSAL"
  MISSING="$(presence_missing)"
  [ -z "$MISSING" ] || _co_refuse "$MISSING — nothing was done"
  act_merge
  refuse_unreached
  gate_preflight
  [ "$PREFLIGHT_RC" -eq 9 ] && _co_refuse "$PREFLIGHT_LINE — nothing was done"
  if [ "$PREFLIGHT_RC" -ne 0 ]; then
    [ -n "$PREFLIGHT_ERR" ] && printf '%s\n' "$PREFLIGHT_ERR"
    _co_refuse "the commit gate would refuse the plan this run would write (rc=$PREFLIGHT_RC) — nothing was done: no branch deleted, no tmp wiped, no continuation or epic row written"
  fi
                    say "preflight: the commit gate allows the plan this run will write"
  act_merge;        say "merge: $MERGE_LINE"
  act_worktrees;    say "worktree-removed: $WT_LINE"
  act_tmp;          say "tmp-wiped: $TMP_LINE"
                    say "tasks-completed: $TASKS_LINE"
  act_continuation; say "continuation: $CONT_LINE"
  act_epic;         say "epic-row: $EPIC_LINE"
                    say "patrol: $PATROL_LINE"
  # ORDER (critic2 N-3): Step-8 block -> gate dry-run -> Step-9 flip. The dry-run judges
  # the plan while it is still OPEN at current 8; flipping first made the bound marker
  # resolve bound-closed, and the gate exits 0 before it checks step evidence. A refusal
  # here leaves the plan at current 8 with the Step-8 block in place and no `delivered:`.
  write_plan_blocks 8
                    say "step8: CLOSED $NOW, attested-by close-out.sh $VERSION"
  gate_dry_run
  write_plan_blocks 9
                    say "handoff: rewritten to the closed form (resume point NONE)"
                    say "step9: delivered: $NOW $WAVE_SLUG $VERSION"
  act_archive
  insert_archived
                    say "archived: $ARCHIVED_LINE"
}

case "$VERB" in
  run)   do_run ;;
  check) do_check ;;
esac
exit 0
