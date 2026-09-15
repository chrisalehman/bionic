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
# THE GATE IS THE ATTESTATION, AND IT IS NOT OPTIONAL (D5: "a script writes a lifecycle
# artifact only where a gate validates what it wrote"). After the two blocks are written,
# this script builds the payload a `git commit` would produce and pipes it into the REAL
# `hooks/bash-walls.sh`. rc 0 is reported as `gate: ok`; rc 2 prints the gate's own words
# and exits 2 with the plan edits LEFT IN PLACE, because those edits are what the reader
# has to fix. A script that wrote a Step-8 block the commit wall then refused would have
# automated the exact failure this task exists to end.
#
# THE DRY-RUN ARMS ITS OWN ENGAGEMENT, for its own synthetic session id, and takes it
# away again. It has to: act 3 wipes the whole of `.bionic/tmp/` (Chris 2026-09-14 — the
# tmp directory is disposable after close; the running-session spare list in steps/8.md
# binds a RUNNING run), and the engagement marker lives there. Without this the gate would
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
for _co_lib in roots.sh root.sh run.sh archive.sh; do
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

# THE WORKTREE CENSUS IS SCOPED TO THIS WAVE, NEVER THE WHOLE REPO (R6 finding 1,
# architecture FAIL). A `wt/*` glob picks up every writer this project has ever spawned —
# 113 in this repository at review time, 13 of them this wave's, 32 foreign ones carrying
# commits this wave's working branch never took (A-orch-45) — and would refuse act 2 on
# branches no one in this wave created, or delete historical ones a refusal-free run
# pruned past. The prefix is this wave's own number, read off the working branch this
# script already has: `wave/NN-<slug>` names NN, and `wt/NN-*` is exactly the set this
# task's plan spawned. A working branch that is not wave/<digits>-shaped has no such
# number to scope to — falling back to the repo-wide census there would be the defect
# wearing a guard, not a fix, so this refuses instead.
WT_NUM="$(printf '%s' "$WORKING" | sed -nE 's#^wave/([0-9]+)-.*#\1#p')"
[ -n "$WT_NUM" ] || _co_refuse "the plan's working-branch '$WORKING' is not wave/<digits>-<slug> shaped — the worktree census needs a wave number to scope wt/NN-* to"
WT_PREFIX="wt/$WT_NUM-"

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
wt_branches() {
  git -C "$ROOT" for-each-ref --format='%(refname:short)' "refs/heads/${WT_PREFIX}*" 2>/dev/null
  return 0
}

# wt_unreached -> every wt/* branch carrying a commit the working branch never took.
wt_unreached() {
  local b _co_cherry
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
  done <<< "$(wt_branches)"
  return 0
}

act_worktrees() {
  local unreached b removed="" wt_dir
  unreached="$(wt_unreached)"
  if [ -n "$unreached" ]; then
    _co_refuse "$(printf '%s' "$unreached" | tr '\n' ' ' | sed -E 's/[[:space:]]+$//') carries a commit $WORKING never took (git cherry) — nothing was deleted, and nothing else was done"
  fi

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
# THE WHOLE DIRECTORY, not the ephemera (Chris 2026-09-14). `steps/8.md` spares every
# session-keyed file by name because another session's LIVE run shares the root; that
# spare list binds a running run, and this runs after delivery, when there is no run left
# to protect. The gate dry-run below re-arms its own marker precisely because this act
# takes the one that was there.
TMP_LINE=""
tmp_count() {
  find "$TMP_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '
  return 0
}

act_tmp() {
  local before after
  before="$(tmp_count)"
  if [ -d "$TMP_DIR" ]; then
    find "$TMP_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
  fi
  after="$(tmp_count)"
  [ "$after" = "0" ] || _co_refuse "$after entries remain under $TMP_DIR after the wipe"
  TMP_LINE="$before entries under $TMP_DIR (the whole directory; the spare list binds a running run, not a closed one)"
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
# prose somebody may reword, and `| wave |` is the table's own first cell.
EPIC_LINE=""
epic_row() {
  local spec sha
  spec="$(plan_frontmatter_get "$PLAN" "spec")"
  spec="${spec##*/}"
  [ -n "$spec" ] || spec="$WAVE_SLUG.spec.md"
  # THE SHA IS FILLED, NOT MARKED. Act 1 has already proved the working branch reachable
  # from the integration branch, so the integration head is a fact this script holds; only
  # the ADR column stays `<fill>`, because which ADRs a wave shipped is not on disk in any
  # form this row could read. A `<fill>` over a knowable fact is just work moved.
  sha="$(git -C "$ROOT" rev-parse --short "$INTEGRATION" 2>/dev/null)"
  printf '| %s | %s | `%s` | `%s`, `.requirements.md` | <fill: ADRs> | %s, %s @ %s |\n' \
    "$WAVE_NUM" "$VERSION" "${PLAN##*/}" "$spec" "$TODAY" "$INTEGRATION" "${sha:-<fill: SHA>}"
}

epic_has_row() {
  [ -f "$EPIC_PLAN" ] || return 1
  grep -qE "^\|[[:space:]]*${WAVE_NUM}[[:space:]]*\|" "$EPIC_PLAN"
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
  CO_ROW="$(epic_row)" awk '
    /^\|[[:space:]]*wave[[:space:]]*\|/ && !seen { intable = 1; seen = 1 }
    intable && !/^\|/ && !done { print ENVIRON["CO_ROW"]; done = 1; intable = 0 }
    { print }
    END { if (!done && intable) print ENVIRON["CO_ROW"] }
  ' "$EPIC_PLAN" > "$tmp" 2>/dev/null
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

# write_plan_blocks -> replaces the Step-8 line and the Step-9 line (each with whatever
# continuation lines it had), sets `current: 9`, and rewrites `## Handoff` whole.
#
# A CONTINUATION LINE IS DROPPED BY THE SAME GRAMMAR THE GATE READS IT BY
# (`extract_continuation`, walls.sh:1697): everything after a Step line up to the next
# `Step N:` line or the next line starting at column zero. Anything else and a second
# close would leave the old block's keys underneath the new one, where `block_get`'s
# first-match rule would quietly prefer them.
write_plan_blocks() {
  local tmp="$PLAN.close-out.$$"
  CO_STEP8="$(step8_block)" CO_STEP9="$(step9_block)" CO_HANDOFF="$(handoff_block)" awk '
    /^## / {
      insdlc = ($0 ~ /^## SDLC State/)
      skip = 0
      if ($0 ~ /^## Handoff/) { print ENVIRON["CO_HANDOFF"]; hskip = 1; next }
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
    insdlc && /^[[:space:]]*current[[:space:]]*:/ { print "current: 9"; next }
    insdlc && /^[[:space:]]*-?[[:space:]]*Step[[:space:]]+8[[:space:]]*:/ {
      print ENVIRON["CO_STEP8"]; skip = 1; next
    }
    insdlc && /^[[:space:]]*-?[[:space:]]*Step[[:space:]]+9[[:space:]]*:/ {
      print ENVIRON["CO_STEP9"]; skip = 1; next
    }
    { print }
  ' "$PLAN" > "$tmp" 2>/dev/null

  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    _co_refuse "could not rewrite $PLAN"
  fi
  mv "$tmp" "$PLAN"

  # A plan that carried no `## Handoff` section gets one rather than silently losing the
  # act: the section is the run's own resume point, and its absence is not consent.
  if ! grep -q 'resume point: NONE — DELIVERED at ' "$PLAN"; then
    printf '\n%s\n' "$(handoff_block)" >> "$PLAN"
  fi

  # The readback, act by act: every line this function claims to have written, asked for
  # back out of the file.
  grep -qE '^- Step 8: CLOSED ' "$PLAN" || _co_refuse "the Step-8 line did not land in $PLAN"
  grep -qE '^  attested-by: close-out.sh ' "$PLAN" || _co_refuse "the attestation did not land in $PLAN"
  grep -qE '^[[:space:]]*-?[[:space:]]*Step 9:.*delivered:' "$PLAN" \
    || _co_refuse "the Step-9 delivered: line did not land in $PLAN"
  grep -qE '^current: 9$' "$PLAN" || _co_refuse "current: did not advance to 9 in $PLAN"
  grep -q 'resume point: NONE — DELIVERED at ' "$PLAN" || _co_refuse "the handoff was not rewritten in $PLAN"
}

# ─── The gate dry-run ────────────────────────────────────────────────────────

gate_dry_run() {
  local hook sid marker input err rc
  hook="$(plugin_root)/hooks/bash-walls.sh"
  [ -f "$hook" ] || _co_refuse "no bash-walls.sh at $hook — the blocks cannot be attested"

  sid="closeout-$$"
  marker="$(engaged_marker_path "$ROOT" "$sid")" \
    || _co_refuse "could not build an engagement marker path for the dry-run"
  mkdir -p "${marker%/*}" 2>/dev/null
  : > "$marker"

  input="$(jq -n --arg s "$sid" --arg cwd "$ROOT" \
    '{session_id: $s,
      cwd: $cwd,
      hook_event_name: "PreToolUse",
      tool_name: "Bash",
      tool_input: {command: "git commit -m close-out"},
      tool_use_id: "toolu_closeout"}')"

  # The environment agrees with the payload because on a real call it does: lib/session.sh
  # takes the env value as primary and the payload as a witness, and a dry-run whose two
  # disagreed would be answered for a session that does not exist.
  err="$(CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$sid" bash "$hook" <<< "$input" 2>&1 >/dev/null)"
  rc=$?
  rm -f "$marker"

  if [ "$rc" -eq 0 ]; then
    say "gate: ok"
    return 0
  fi
  [ -n "$err" ] && printf '%s\n' "$err"
  _co_refuse "the commit gate refused the blocks this run wrote (rc=$rc) — the plan edits are left in place, because they are what to fix"
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
  local ws is verdict unreached branches wt_list wt_count count hook sid marker input rc
  ws="$(git -C "$ROOT" rev-parse --short "$WORKING" 2>/dev/null)"
  is="$(git -C "$ROOT" rev-parse --short "$INTEGRATION" 2>/dev/null)"
  if git -C "$ROOT" merge-base --is-ancestor "$WORKING" "$INTEGRATION" 2>/dev/null; then
    verdict="$WORKING @ ${ws:-?} reachable from $INTEGRATION @ ${is:-?}"
  else
    verdict="WOULD REFUSE — $WORKING @ ${ws:-?} is not reachable from $INTEGRATION @ ${is:-?}"
  fi
  say "merge: $verdict"

  # THE CENSUS NAMES THE SCOPE IT READ, NOT JUST THE RESULT. `wt_branches` is already
  # scoped to `${WT_PREFIX}*` (preflight); the report says so explicitly — the prefix and
  # how many branches it found there — so a reader can tell this is a wave-scoped count,
  # never the repo-wide one R6 flagged.
  wt_list="$(wt_branches)"
  wt_count="$(printf '%s\n' "$wt_list" | grep -c '[^[:space:]]')"
  unreached="$(wt_unreached)"
  branches="$(printf '%s' "$wt_list" | tr '\n' ' ' | sed -E 's/[[:space:]]+$//')"
  if [ -n "$unreached" ]; then
    say "worktree-removed: ${WT_PREFIX}* (${wt_count} branch(es) in scope) WOULD REFUSE — $(printf '%s' "$unreached" | tr '\n' ' ' | sed -E 's/[[:space:]]+$//') carries a commit $WORKING never took"
  else
    say "worktree-removed: ${WT_PREFIX}* (${wt_count} branch(es) in scope): ${branches:-none}"
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

  # THE GATE, ASKED WITHOUT WRITING ANYTHING — including the engagement marker, which is
  # removed again whether or not it was this call that put it there being irrelevant: the
  # id is synthetic and nothing else can be looking for it.
  hook="$(plugin_root)/hooks/bash-walls.sh"
  if [ ! -f "$hook" ]; then
    say "gate: skipped — no bash-walls.sh at $hook"
    return 0
  fi
  sid="closeout-check-$$"
  marker="$(engaged_marker_path "$ROOT" "$sid")" || { say "gate: skipped — no marker path"; return 0; }
  mkdir -p "${marker%/*}" 2>/dev/null
  : > "$marker"
  input="$(jq -n --arg s "$sid" --arg cwd "$ROOT" \
    '{session_id: $s, cwd: $cwd, hook_event_name: "PreToolUse", tool_name: "Bash",
      tool_input: {command: "git commit -m close-out"}, tool_use_id: "toolu_closeout"}')"
  CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$sid" bash "$hook" <<< "$input" >/dev/null 2>&1
  rc=$?
  rm -f "$marker"
  if [ "$rc" -eq 0 ]; then
    say "gate: ok against the plan as it stands"
  else
    say "gate: would refuse the plan as it stands (rc=$rc) — the Step-8 block run writes is what clears it"
  fi
  return 0
}

# ─── run ─────────────────────────────────────────────────────────────────────

do_run() {
  act_merge;        say "merge: $MERGE_LINE"
  act_worktrees;    say "worktree-removed: $WT_LINE"
  act_tmp;          say "tmp-wiped: $TMP_LINE"
                    say "tasks-completed: $TASKS_LINE"
  act_continuation; say "continuation: $CONT_LINE"
  act_epic;         say "epic-row: $EPIC_LINE"
                    say "patrol: $PATROL_LINE"
  write_plan_blocks
                    say "handoff: rewritten to the closed form (resume point NONE)"
                    say "step8: CLOSED $NOW, attested-by close-out.sh $VERSION"
                    say "step9: delivered: $NOW $WAVE_SLUG $VERSION"
  gate_dry_run
  act_archive
  insert_archived
                    say "archived: $ARCHIVED_LINE"
}

case "$VERB" in
  run)   do_run ;;
  check) do_check ;;
esac
exit 0
