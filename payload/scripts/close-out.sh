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
#     ... run|check --deployed <what> --verified <how> --monitored <how>   when the plan names a deploy_target
#
# EVERY ACT IS IDEMPOTENT BY A READBACK OF ITS OWN RESULT, never by a flag this script
# sets. The merge act asks git whether the working branch is reachable — which is true
# again on the second run and cheap to ask. The branch sweep asks `git cherry`, then
# deletes, then asks `rev-parse` whether the branch is gone. The wipe counts what is left.
# The continuation and the epic row look for what they would write before writing it. The
# whole SCRIPT is idempotent by the same rule at a larger grain: a run the reader reads
# delivered is closed, and a second `run` says `already closed` and touches nothing.
# The delivery is the `delivered:` this script writes on the Step 9 line, read by the reader
# every other surface asks, so there is no second notion of "closed" to drift.
#
# THE GATE IS ASKED FIRST, AND ASKED AGAIN AS THE ATTESTATION (critic3 P-1, wave-23 T17).
# Before the first act, `run` refuses unless the run is at Step 8 and then writes phase 8's
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
# A ROW THE CLOSE ITSELF PROVES IS NOT OWED TO THE DRY-RUN. A matrix row owed at Step 9 is
# judged by the gate only once the Step-9 line carries `delivered:` (lib/walls.sh
# `matrix_row_deferred`), and the row whose test is the hand-holds line is written by this script
# after that line, from its last reading (`co_matrix_settle`). The pre-flight and the dry-run judge
# the plan at current 8, before either, and owe it nothing.
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
# ONE ACT IS AN INSTRUCTION AND SAYS SO. `TaskUpdate` is a model tool; a shell script
# cannot call it. Printing the exact instruction is the whole of what this script can
# honestly do for it, and printing it in the same line shape as the acts it does perform
# is what keeps the report readable as one thing.
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
# [WALL: tests/close-out-1.test.sh .. tests/close-out-6.test.sh, over tests/close-out.prelude.sh]

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
for _co_lib in loader.sh roots.sh root.sh run.sh plan.sh handoff.sh archive.sh patrol.sh units.sh proof.sh debt.sh seal.sh; do
  if [ ! -f "${CO_LIB}/${_co_lib}" ]; then
    echo "close-out.sh: cannot find ${CO_LIB}/${_co_lib} — the payload looks incomplete." >&2
    echo "              reinstall with: claude plugin install bionic@bionic" >&2
    exit 2
  fi
done
# card.sh is executed, not sourced: it holds the one reading of the deferrals a run inherited (T43).
if [ ! -f "${CO_SCRIPTS}/card.sh" ]; then
  echo "close-out.sh: cannot find ${CO_SCRIPTS}/card.sh — the payload looks incomplete." >&2
  echo "              reinstall with: claude plugin install bionic@bionic" >&2
  exit 2
fi

# shellcheck source=/dev/null
. "${CO_LIB}/loader.sh"
# shellcheck source=/dev/null
. "${CO_LIB}/roots.sh"
# shellcheck source=/dev/null
. "${CO_LIB}/run.sh"
# THE ONE READER OF THE INTEGRATION BRANCH (lib/plan.sh `plan_integration_branch`), and the handoff document's
# grammar and home file (lib/handoff.sh), which session-poker.sh `handoff` reads too.
# shellcheck source=/dev/null
. "${CO_LIB}/plan.sh"
# shellcheck source=/dev/null
. "${CO_LIB}/handoff.sh"
# shellcheck source=/dev/null
. "${CO_LIB}/archive.sh"
# THE SEAL (lib/seal.sh) that vouches for the run's plan and log: close-out lifts it before the archive moves the plan.
# shellcheck source=/dev/null
. "${CO_LIB}/seal.sh"
# shellcheck source=/dev/null
. "${CO_LIB}/patrol.sh"
# The clock's one home, asked by name: patrol.sh loads it only softly.
bionic_need time.sh _time_epoch
# shellcheck source=/dev/null
. "${CO_LIB}/units.sh"
# shellcheck source=/dev/null
. "${CO_LIB}/proof.sh"
# THE SCALE PROFILE (wave-38 T16; D25): the branch-shape refusal reads the scale's branch cell and the
# merge act its integrate cell.
# shellcheck source=/dev/null
. "${CO_LIB}/scale.sh"
# THE ONE DEBT-LINE GRAMMAR (wave-36 T13; D13, AC-7.8): the carry is rendered and checked by lib/debt.sh,
# which `debt add` and card.sh read too (co_debts, co_debt_refusal).
# shellcheck source=/dev/null
. "${CO_LIB}/debt.sh"
# THE PERSON'S LEDGER AND ITS ONE SENDER (wave-33 T12; REQ-2 AC-2.3, D2), for the delivery notice at
# the end of `run`. NOT in the list above and sourced only when readable: a payload without it
# closes a run exactly as 1.15.0 did, and nothing here can make a close refuse.
if [ -r "${CO_LIB}/owed.sh" ]; then
  # shellcheck source=/dev/null
  . "${CO_LIB}/owed.sh"
fi

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
  co_hold "${CO_HOLD_SAYS:-close-out stopped}" "bionic: close-out refused — $*"
  exit 2
}
# _co_held <what holds the merge, in a few words> <sentence> -> _co_refuse's line and exit 2, the words the ask's title
_co_held() {
  CO_HOLD_SAYS="$1"
  _co_refuse "$2"
}

# THE HELD MERGE IS THE RUN'S ASK. A close-out refused while the plan reads current: 8 leaves the run's merge waiting on
# whatever the refusal names, so it opens `hold:merge` on the register of the plan it closes (lib/owed.sh, `OWED_PLAN`),
# titled `merge held: <what holds it>` and the printed line the reply, where every reader of the run's asks finds it;
# the run that delivers closes it. The title is a person's words, and a notification's title too: what holds the merge
# in a few words, never a hash, a function or an instruction to an agent, all of which the refusal carries in the reply
# for a model to read. A refusal that says no words of its own (`_co_held`, `co_would`'s second word) is titled
# "close-out stopped". `check` holds it for the first refusal it reports: it still changes nothing of the run, and only
# says on the register what holds it. Before Step 8 the run is not at its merge, so a refusal holds nothing. A refusal
# inside a command substitution is a preview the caller reports, never this script's own exit, so it opens nothing. One
# ask for the run: the same refusal again leaves it as it is, a new one replaces it, so the title says what holds the
# merge now. The session is this script's own, else a stand-in, because the register is named by the plan and the store
# still asks for a session to write under.
CO_HOLD=no
CO_HOLD_WHY=""
CO_HOLD_SAYS=""
# co_hold_sid -> CO_HOLD_SID, the session the asks are written under: this script's own, else a stand-in made once by
# this process (lib/root.sh `bionic_id`, its dots written `-`, a session id's alphabet being letters, digits, _ and -), so a hold opened and closed later in the run meet under one session and no
# other close-out's stand-in is the same; rc 1 when no stand-in can be made.
CO_HOLD_SID=""
co_hold_sid() {
  [ -z "$CO_HOLD_SID" ] || return 0
  if [ -n "$CO_SID" ]; then CO_HOLD_SID="$CO_SID"; return 0; fi
  bionic_need root.sh bionic_id && bionic_id && CO_HOLD_SID="closeout-${BIONIC_ID//./-}"
}
co_hold() {  # <what holds the merge, in a few words> <the printed line> -> always 0, prints nothing
  local r
  [ "$CO_HOLD" = yes ] && [ "${BASH_SUBSHELL:-0}" -eq 0 ] || return 0
  declare -F owed_open >/dev/null 2>&1 && co_hold_sid || return 0
  r="$(OWED_ROOT="$ROOT" OWED_SID="$CO_HOLD_SID" OWED_PLAN="$PLAN" owed_list 2>/dev/null \
    | awk -F'\t' '$1 == "hold:merge" { print $4; exit }')"
  if [ -n "$r" ]; then
    [ "$r" = "$(printf '%s' "$2" | tr '|\t\r\n' '    ')" ] && return 0
    OWED_ROOT="$ROOT" OWED_SID="$CO_HOLD_SID" OWED_PLAN="$PLAN" owed_close hold:merge "close-out refused again" >/dev/null 2>&1
  fi
  OWED_ROOT="$ROOT" OWED_SID="$CO_HOLD_SID" OWED_PLAN="$PLAN" owed_open hold:merge "merge held: $1" "$2" >/dev/null 2>&1
  return 0
}
# co_hold_release -> always 0, prints nothing: the run delivered, its merge is no longer held, and no later refusal holds it
co_hold_release() {
  [ "$CO_HOLD" = yes ] || return 0
  CO_HOLD=no
  declare -F owed_close >/dev/null 2>&1 && co_hold_sid || return 0
  OWED_ROOT="$ROOT" OWED_SID="$CO_HOLD_SID" OWED_PLAN="$PLAN" owed_close hold:merge "close-out delivered" >/dev/null 2>&1
  return 0
}
# co_would <line> [<what holds the merge, in a few words>] -> the line said; the first such line `check` reports is the
# refusal it holds the merge for, and its words the title
co_would() {
  say "$1"
  [ -n "$CO_HOLD_WHY" ] || { CO_HOLD_WHY="$1"; CO_HOLD_SAYS="${2:-}"; }
}

usage() {
  echo "usage: close-out.sh <plan-path> run|check [--deployed <what> --verified <how> --monitored <how>]" >&2
  echo "       close-out.sh <plan-path> closed-form [<instant>]" >&2
  echo "       run          perform the Step 8/9 tail and write both lifecycle blocks" >&2
  echo "       check        report what run would do, and change nothing" >&2
  echo "       closed-form  print the closed handoff's resume point: and branch: lines, and change nothing" >&2
  echo "       --deployed, --verified, --monitored  what was deployed, how it was verified and how it is monitored," >&2
  echo "                    owed when the plan names a deploy_target and refused when it names none" >&2
}
# co_deploy_ask <deployed|verified|monitored> -> what that option asks for, in a person's words
co_deploy_ask() {
  case "$1" in deployed) printf 'what was deployed, and where' ;; verified) printf 'how the deploy was verified' ;; *) printf 'how the deploy is monitored' ;; esac
}

# ─── Arguments ───────────────────────────────────────────────────────────────

PLAN="${1:-}"
VERB="${2:-}"
if [ -z "$PLAN" ] || [ -z "$VERB" ]; then
  usage
  _co_refuse "this call names no plan, or no verb — the verbs are run and check"
fi
CO_AT=""
# THE THREE OF A DEPLOY ARE A PERSON'S WORDS, given to run and check as named options: the close is the one writer of
# its delivery's step, so it is the one place they can be written. Each value goes into one field of the run's log,
# which holds no `|` and no line break, so a value holding either is refused here, before anything is read or done.
CO_DEPLOYED=""; CO_VERIFIED=""; CO_MONITORED=""; CO_DEPLOY_GIVEN=""
case "$VERB" in
  run|check)
    shift 2
    while [ $# -gt 0 ]; do
      case "$1" in
        --deployed|--verified|--monitored)
          [ $# -ge 2 ] || { usage; _co_refuse "$1 takes one word: $(co_deploy_ask "${1#--}")"; }
          case " $CO_DEPLOY_GIVEN " in *" ${1#--} "*) usage; _co_refuse "$1 is given twice" ;; esac
          case "$2" in *'|'*|*[[:cntrl:]]*) usage; _co_refuse "$1 holds a | or a line break, which the run's log cannot hold; write it without one" ;; esac
          CO_DEPLOY_GIVEN="${CO_DEPLOY_GIVEN:+$CO_DEPLOY_GIVEN }${1#--}"
          case "$1" in --deployed) CO_DEPLOYED="$2" ;; --verified) CO_VERIFIED="$2" ;; *) CO_MONITORED="$2" ;; esac
          shift 2 ;;
        *) usage; _co_refuse "$VERB takes no word '$1' — its options are --deployed, --verified and --monitored" ;;
      esac
    done
    ;;
  closed-form)
    [ $# -le 3 ] || { usage; _co_refuse "closed-form takes the plan and at most one instant"; }
    CO_AT="${3:-}"
    case "$CO_AT" in *[[:cntrl:]]*|*[[:space:]]*) usage; _co_refuse "closed-form's instant is one word" ;; esac
    ;;
  *)
    usage
    _co_refuse "unknown verb '$VERB' — the verbs are run, check and closed-form"
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
WAVE_SLUG="$(proof_plan_slug "$PLAN")"
WAVE_NUM="$(printf '%s' "$WAVE_SLUG" | sed -nE 's/^wave-([0-9]+).*/\1/p')"
CONT_REL="record/$WAVE_SLUG/continuation.md"
CONT="$DROOT/$CONT_REL"
NOW="$(date -u +%Y-%m-%dT%H:%MZ)"
TODAY="$(date -u +%Y-%m-%d)"

# co_version -> the version this payload declares, which is what `attested-by:` names.
# `unknown` rather than an empty string when the manifest cannot be read: an attestation
# that names no version is still an attestation, and a blank after "close-out.sh" reads
# like a truncation.
co_version() { co_plugin_version "$(plugin_root)"; }
# co_plugin_version <plugin root> -> that root's manifest version, or `unknown` (co_version's reading, for any root)
co_plugin_version() {
  local f="${1:-}/.claude-plugin/plugin.json" v=""
  if [ -f "$f" ]; then
    v="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -1)"
  fi
  printf '%s\n' "${v:-unknown}"
}
VERSION="$(co_version)"

# RELEASE -> the version this run released: the plan's own `release:` frontmatter field, or
# nothing (wave-27 T4, D14). NEVER `VERSION`. The installed tool attests the tail; it is not
# what shipped, and in a consumer project it is not even the same product (wave-26 had its
# delivered line and epic row corrected by hand to the release). With no field, the delivered
# line, the epic row and the continuation header name no version at all.
RELEASE="$(plan_frontmatter_get "$PLAN" release)"

# ─── The run, as the reader answers it ───────────────────────────────────────
#
# EVERY FACT OF THE RUN THIS SCRIPT READS IS A READER ANSWER: the step and the delivery, the landings, the trees, the
# reviews, the deferrals and the debts. The reader (lib/reader.sh) reads the run's log, so a fact is read here as every
# other reader reads it. One fold
# serves every answer: the proof library keeps it (lib/proof.sh `_proof_facts`), and the judge this script asks reads
# the same one. What this script still reads of the plan is what the plan authors: its header and its rows' kinds. It
# writes nothing into the plan: what step 8 cleaned, the delivery, the archive and the handoff's place are events.
_proof_reader_load || _co_refuse "the reader (lib/reader.sh) cannot be loaded from $CO_LIB, so the run's facts cannot be read"
# THE CHECK IS ONE COMMAND, ONE FOLD (lib/proof.sh `proof_hold_begin`). Its asks run in `$( )` subshells and in the
# gate's dry walls, and outside a hold each of them folds the log again and loses its fold when it exits. So `check`
# opens the hold for its process tree, before its first ask, as the commit wall does for a commit, and the hold is
# removed on every exit. A judgment still sums the log at its entry. `check` appends nothing to the log and writes no
# plan, so nothing it reads goes stale under the hold. `run` writes the plan, the seal and the archive by paths the
# hold does not see, so it holds nothing. A check started inside a command that already holds reads that hold.
if [ "$VERB" = check ] && proof_hold_begin; then trap 'proof_hold_end' EXIT; fi
co_ask() {  # <reader question's function> [args] -> its answer, over the kept fold of this run
  local q="$1"; shift
  _proof_ask "$PLAN" "$q" "$PLAN" "$@"
}
co_facts() {  # <event type> [<field>] -> the standing facts of that type, or that field of each, in fact order; 2 when they cannot be read
  _proof_facts_read "$PLAN" -F'|' -v t="$1" -v k="${2:-}" "$_READER_AWK"'ev() == t { if (k == "") print; else print line_kv(k) }'
}
co_step9_at() {  # -> the instant of the run's delivery, or nothing; 2 when the facts cannot be read
  _proof_facts_read "$PLAN" -F'|' "$_READER_AWK"'ev() == "step" && line_kv("n") == "9" { t = line_kv("at") } END { print t }'
}
# A fold that failed reads as a run with no step, no debt and no deferral, and a reader inside a pipe or a $( ) cannot
# stop this script: before the continuation is written the fold is taken in this shell and held, so the reads that
# write it are served the facts it read; one that fails is the refusal, and nothing is written from it.
CO_UNREAD="the run's facts could not be read, so nothing is written from them; run again: bash $0 $PLAN $VERB"
co_heard() { _proof_facts "$PLAN" >/dev/null || _co_refuse "$CO_UNREAD"; }

# THE ONE READER OF THE INTEGRATION BRANCH: lib/plan.sh `plan_integration_branch`, the plan's header key, as
# session-poker.sh `handoff` and `release-check` read it.
INTEGRATION="$(plan_integration_branch "$PLAN")"
# THE ONE READER OF THE WORKING BRANCH: lib/run.sh `plan_working_branch`, the plan's header key, as `ready`, the stop
# wall, the card and the proof judge read it.
WORKING="$(plan_working_branch "$PLAN")"
# `run` closes a run at Step 8 and nowhere else: the gate judges
# whatever step the run is at, so below 8 its refusal would be about a step this script
# never writes, and above 8 there is nothing left for it to close. The step and the delivery
# are the reader's `step`: n= and state=.
CO_STEP="$(co_ask reader_q_step)" || _co_refuse "$CO_UNREAD"
CURRENT="$(printf '%s\n' "$CO_STEP" | sed -n 's/^n=//p')"
CO_STATE="$(printf '%s\n' "$CO_STEP" | sed -n 's/^state=//p')"
STEP_REFUSAL="the run is at Step ${CURRENT:-<none>} — advance it to Step 8 first"
[ "$CURRENT" != 8 ] || [ "$VERB" = closed-form ] || CO_HOLD=yes

# A PARKED WAVE IS CLOSED WITHOUT THE MERGE ACT (wave-38 T15; D17, REQ-4 AC-4.3). Parking requires an explicit
# `## Wake Note` (steps/8.md): a plan carrying a flush-left `## Wake Note` whose body is not empty and not the
# template's `(none)` is parked. `run` then performs the tail
# without the merge: no merge readback, no rows landed by a merge, no branch census and no tree or branch deleted (the
# work is kept), no archive move and no delivery notice; the Step-9 line reads `delivered: parked on <branch> @ <sha>`,
# the continuation, the epic row and the closed handoff say parked, where and why. Everything else stands: the step,
# the facts, the gate. The rule is lib/run.sh `plan_parked_why`, the one reader.
PARKED_WHY=""
PARKED=no
if PARKED_WHY="$(plan_parked_why "$PLAN")"; then PARKED=yes; fi

# THE SCALE (wave-38 T16; D25, AC-5.1): the plan's `scale:`, read at the wave row when it names none or one the profile
# does not hold. Its branch cell shapes the worktree census below; its integrate cell names a branch still waiting on its pull request.
CO_SCALE="$(plan_frontmatter_get "$PLAN" scale)"
scale_cell "$CO_SCALE" branch >/dev/null 2>&1 || CO_SCALE=wave

# THE MERGE IS READ, NEVER ASSUMED, AT EVERY SCALE. close-out merges nothing: the merge act is a readback of
# lib/line.sh `line_merge_seen`, which reads the integration branch on the remote and the host's word on the run's pull
# request, and the tail runs only once that says merged. A working branch nothing merged holds the run, whatever the
# scale's integrate cell; the cell says only how the closed form names a branch still waiting on its pull request.
CO_INTEGRATE="$(scale_cell "$CO_SCALE" integrate 2>/dev/null)" || CO_INTEGRATE=pr
# co_pr_owed -> 0 when the act is `pr` and the working branch exists and is not yet reachable from the integration
# branch; a branch that is gone was merged and deleted, so nothing is owed
co_pr_owed() {
  [ "$CO_INTEGRATE" = pr ] || return 1
  git -C "$ROOT" rev-parse --verify -q "refs/heads/$WORKING" >/dev/null 2>&1 || return 1
  ! git -C "$ROOT" merge-base --is-ancestor "$WORKING" "$INTEGRATION" 2>/dev/null
}
# co_into -> how the working branch reaches the integration branch: `merged`, or `to be pulled` while the PR is owed; a
# close that read the merge says merged, since the local integration branch is not where a remote merge shows
co_into() { if [ -z "${CO_MERGE_COMMIT:-}" ] && co_pr_owed; then printf 'to be pulled'; else printf 'merged'; fi; }
# THE CLOSED FORM'S RESUME POINT AND BRANCH LINE (wave-38 T15, AC-4.3; the one writer since wave-38 T37, D23): a
# delivered run has nothing to resume; a parked one resumes from its branch, which is kept; a pull request owed is "to be
# pulled". close-out writes both into the closed handoff, and session-poker.sh `handoff` on a closed plan prints what
# `closed-form` (below) prints, so the two doors cannot say different things.
co_resume_point() {
  if [ "$PARKED" = yes ]; then
    printf 'resume point: PARKED on %s @ %s — %s' "$WORKING" "$(git -C "$ROOT" rev-parse --short "$WORKING" 2>/dev/null || printf '?')" "$PARKED_WHY"
  else
    # The delivery's instant is its fact's, the one the step's event holds, so both doors name one; an instant asked
    # for by name, or no fact yet, is the minute close-out holds.
    local at="${CO_AT:-}"
    [ -n "$at" ] || at="$(co_step9_at 2>/dev/null)" || at=""
    [ -n "$at" ] || at="$NOW"
    printf 'resume point: NONE — DELIVERED at %s; %s @ %s.' "$at" "$INTEGRATION" "$(git -C "$ROOT" rev-parse --short "$INTEGRATION" 2>/dev/null || printf '?')"
  fi
}
co_branch_line() {
  if [ "$PARKED" = yes ]; then printf 'branch: %s kept, not merged into %s; its worktrees are kept.' "$WORKING" "$INTEGRATION"
  else printf 'branch: %s %s into %s.' "$WORKING" "$(co_into)" "$INTEGRATION"; fi
}

# `closed-form [<instant>]` (wave-38 T37): the two lines, one each, for a plan close-out closed or one it would close;
# read-only, and asked before the closed run's `already closed`. The instant is the argument, else the instant of the
# run's delivery, the reader's step 9 (close-out writes its NOW on that line), else `?`. The integration
# branch is `plan_integration_branch`'s, as every verb here reads it (wave-39 T16).
if [ "$VERB" = closed-form ]; then
  INTEGRATION="${INTEGRATION:-(none named)}"; WORKING="${WORKING:-(none named)}"
  NOW="$CO_AT"
  if [ -z "$NOW" ]; then
    NOW="$(co_step9_at)"
    case "$NOW" in [0-9][0-9][0-9][0-9]-*) : ;; *) NOW="?" ;; esac
  fi
  printf '%s\n%s\n' "$(co_resume_point)" "$(co_branch_line)"
  exit 0
fi

# ─── Preflight ───────────────────────────────────────────────────────────────
#
# AC-4.4 FIRST, before any tool is even looked for: a closed run is not a run this script
# has anything to say about, and a second call must be able to answer that on a machine
# where jq has since been uninstalled.
if [ "$CO_STATE" = delivered ]; then
  say "already closed"
  exit 0
fi

command -v git >/dev/null 2>&1 || _co_refuse "git is not on PATH"
command -v jq  >/dev/null 2>&1 || _co_refuse "jq is not on PATH — the gate dry-run cannot be built without it"
[ -n "$INTEGRATION" ] || _co_refuse "the plan names no integration-branch:; add 'integration-branch: <branch>' to the plan's header"
[ -n "$WORKING" ]     || _co_refuse "the plan names no working-branch:; add 'working-branch: <branch>' to the plan's header"

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
# co_parked_merge_line -> the merge key's value on a parked plan: where the work is, and that nothing merged it
co_parked_merge_line() {
  printf 'parked on %s @ %s — not merged into %s (%s)' "$WORKING" "$(git -C "$ROOT" rev-parse --short "$WORKING" 2>/dev/null || printf '?')" "$INTEGRATION" "$PARKED_WHY"
}
# co_merge_read -> the merge as lib/line.sh `line_merge_seen` reads it, after its own fetch: CO_MERGE_RC (0 merged, 1 not
# merged, 3 the request closed unmerged, 2 unread), CO_MERGE_COMMIT (the commit a landing names, empty unless merged),
# CO_MERGE_REF (the integration branch read), CO_MERGE_WHY and CO_MERGE_WS (the working head, short)
CO_MERGE_RC=2; CO_MERGE_COMMIT=""; CO_MERGE_REF=""; CO_MERGE_WHY=""; CO_MERGE_WS=""
co_merge_read() {
  local out c
  CO_MERGE_COMMIT=""; CO_MERGE_WS="$(git -C "$ROOT" rev-parse --short "refs/heads/$WORKING" 2>/dev/null)"
  if bionic_need line.sh line_merge_seen; then
    out="$(line_merge_seen "$PLAN" "$ROOT" --fetch)"; CO_MERGE_RC=$?
  else
    out="$(printf 'unread\t-\t%s\t%s/line.sh, the merge'"'"'s reader, cannot be loaded' "$INTEGRATION" "$CO_LIB")"; CO_MERGE_RC=2
  fi
  c="$(printf '%s' "$out" | cut -f2)"
  CO_MERGE_REF="$(printf '%s' "$out" | cut -f3)"; CO_MERGE_WHY="$(printf '%s' "$out" | cut -f4-)"
  [ "$CO_MERGE_RC" -ne 0 ] || CO_MERGE_COMMIT="$c"
  [ -n "$CO_MERGE_REF" ] && [ "$CO_MERGE_REF" != - ] || CO_MERGE_REF="$INTEGRATION"
  return 0
}
# co_merge_verdict -> the merge line: what merged it, or `WOULD REFUSE — ` and why nothing has; rc 0 merged, 1 not
co_merge_verdict() {
  local short
  short="$(git -C "$ROOT" rev-parse --short "$CO_MERGE_COMMIT" 2>/dev/null || printf '%s' "${CO_MERGE_COMMIT:0:7}")"
  case "$CO_MERGE_RC|$CO_MERGE_WHY" in
    0\|reached) printf '%s @ %s reachable from %s @ %s' "$WORKING" "${CO_MERGE_WS:-?}" "$CO_MERGE_REF" "$short" ;;
    0\|host\ *) printf '%s @ %s merged into %s by the pull request %s as %s' "$WORKING" "${CO_MERGE_WS:-?}" "$CO_MERGE_REF" "${CO_MERGE_WHY#host }" "$short" ;;
    1\|*) printf 'WOULD REFUSE — %s @ %s is not reachable from %s (%s)' "$WORKING" "${CO_MERGE_WS:-?}" "$CO_MERGE_REF" "$CO_MERGE_WHY"; return 1 ;;
    3\|*) printf 'WOULD REFUSE — %s @ %s is not merged: %s; reopen it, or park the run with a ## Wake Note' "$WORKING" "${CO_MERGE_WS:-?}" "$CO_MERGE_WHY"; return 1 ;;
    *) printf 'WOULD REFUSE — whether %s @ %s is merged cannot be read: %s' "$WORKING" "${CO_MERGE_WS:-?}" "$CO_MERGE_WHY"; return 1 ;;
  esac
}
# co_merge_holds -> the few words a merge not seen holds the run for, the ask's title
co_merge_holds() {
  case "$CO_MERGE_RC" in
    1) printf 'the working branch is not merged' ;;
    3) printf 'the pull request was closed unmerged' ;;
    *) printf 'the merge cannot be read' ;;
  esac
}
act_merge() {
  local verdict
  git -C "$ROOT" rev-parse --verify -q "refs/heads/$WORKING" >/dev/null 2>&1 \
    || _co_refuse "the plan's working-branch '$WORKING' is not a branch in $ROOT"
  co_merge_read
  if verdict="$(co_merge_verdict)"; then
    MERGE_LINE="$verdict"
    return 0
  fi
  _co_held "$(co_merge_holds)" "${verdict#WOULD REFUSE — } — the tail runs once the merge is seen"
}

# co_tag_merge <run|check> -> TAG_LINE, the tag's key: the release tagged at the merge commit and pushed, as lib/line.sh
# `line_tag_merge` decides it. The release approval in the log authorises the tag and its push, and the tag is made once
# the merge is seen, before any row lands. A tag left as it stands, or none made for want of a release or an approval,
# is said and does not hold the close; a tag that cannot be made or pushed holds it with the person's ask, and nothing
# is left made, so the close runs again once the push can be.
TAG_LINE=""; TAG_RC=0
co_tag_merge() {
  local out rc flag=""
  [ "${1:-run}" != check ] || flag=--check
  [ -n "$CO_MERGE_COMMIT" ] || { TAG_LINE="none — no merge was read, so there is no commit to tag"; return 0; }
  if ! bionic_need line.sh line_tag_merge; then
    TAG_LINE="none — $CO_LIB/line.sh, the tag's writer, cannot be loaded"; return 0
  fi
  out="$(line_tag_merge "$PLAN" "$ROOT" "$CO_MERGE_COMMIT" $flag)"; rc=$?
  TAG_LINE="$(printf '%s' "$out" | cut -f3-)"
  TAG_RC="$rc"
  [ "$rc" -ne 2 ] || [ -n "$flag" ] || _co_held "the release tag was not pushed" "$TAG_LINE — nothing was moved"
  return 0
}

# ─── Act 1b: the rows the merge lands (wave-36 T14; D13, AC-7.7; C70) ─────────
#
# THE PLAN CLOSE-OUT DELIVERS READS THE ROWS ITS MERGE LANDED AS LANDED. wave-35 closed with its integrate and close
# rows still `pending dispatch`, and the act that wiped the engaged marker had also taken the only way to write them.
# The rows the merge lands are the plan's open (pending or active) `## Tasks` rows of kind `integrate` (the merge
# itself) and `close` (the row units.sh's `merge` read binds to that merge); a build row still open is not landed
# here, because nothing showed its work on the branch. Each is landed by one `published` event at the merge commit the
# merge act read (the integration tip that reaches the working head, or the host's merge commit), of the close kind and by close-out, through the line's writer (lib/line.sh `line_published_event`); no cell is written.
# The session must be bound to this plan, and `run` refuses before its first act when it is not. Act 3 keeps the
# engaged marker for every verb a refusal later in the tail leaves to the person; the marker goes last.
LANDS_LINE=""
co_lands_rows() {  # -> the open integrate and close rows' ids, space-joined, in table order; nothing when none
  # A row is open while the reader holds no landing of it and the rows' one answer (units_rows, the run's log over the
  # cells) does not read it dropped; the kind is the row's own cell.
  units_rows "$PLAN" 2>/dev/null | CO_SHUT=" $(co_facts published row | tr '\n' ' ') " awk -F'\t' '
    ($3 == "integrate" || $3 == "close") && $10 != "dropped" && !index(ENVIRON["CO_SHUT"], " " $1 " ") { printf "%s%s", (n++ ? " " : ""), $1 }
    END { if (n) print "" }'
}
co_lands_refusal() {  # <rows> -> why this session cannot land them, or nothing
  local rows="$1" run bound
  [ -n "$rows" ] || return 0
  if [ -z "$CO_SID" ]; then
    printf 'rows %s cannot be landed: no session key (CLAUDE_CODE_SESSION_ID), and close-out lands rows only of the plan its session is bound to — run close-out from the session bound to %s' "$rows" "$PLAN"
    return 0
  fi
  run="$(session_run "$ROOT" "$CO_SID" 2>/dev/null)" || :
  bound=""
  case "$run" in 'bound-open '*) bound="${run#bound-open }" ;; esac
  [ -z "$bound" ] || bound="$(cd "${bound%/*}" 2>/dev/null && pwd -P)/${bound##*/}"
  if [ "$bound" != "$PLAN" ]; then
    printf 'rows %s cannot be landed: this session (%s) is not bound to this open run (%s), and close-out lands rows only of the plan its session is bound to — bind %s first' "$rows" "$CO_SID" "${run:-none}" "$PLAN"
  fi
  return 0
}
# co_rows_out -> returns while no row of the run has a live writer; otherwise refuses before the first act, naming each
# row out and the writer holding it. THE CLOSE LANDS NO ROW A WRITER HOLDS, and removes nothing a writer still reads:
# landed at the merge, an active close row reads finished while its writer is mid-work. Who is out is the watcher's
# own question (lib/patrol.sh `patrol_rows_out`), so the close typed by hand and the merge pass refuse on one answer;
# an answer that cannot be had refuses too. It asks whether a writer is out now, never whether one ever began a row's
# file (co_cont_owner): a writer acked or gone holds nothing, though the file it began is still its own. It is asked in a command substitution, never in this shell: the rosters'
# reader sources lib/fill.sh and through it lib/gate.sh, whose `gate_ask` would replace this file's own.
co_rows_out() {
  local held said
  held="$(patrol_rows_out "$PLAN")" \
    || _co_held "who is out cannot be read" "the rows of $PLAN or the rosters that hold them cannot be read, so whether a writer is out is unknown — nothing was done"
  [ -n "$held" ] || return 0
  said="$(printf '%s\n' "$held" | awk -F'\t' '$1 != "" { printf "%s%s (%s on roster %s)", (n++ ? ", " : ""), $1, $2, substr($3, 1, 8) }')"
  _co_held "rows of the run are out" "rows out: $said — the close runs once each writer is acked or gone — nothing was done"
}
# co_lands_open <rows> -> the close rows among <rows> that name a record none of which stands, space-joined, in table
# order. A CLOSE ROW IS FINISHED BY ITS RECORD, not by the merge: landed without it, a row whose writer never wrote it
# reads done. A close row that names no record has nothing to wait for and lands with the merge. The record is read as
# the tick reads it (lib/units.sh `units_record_stands`).
co_lands_open() {
  local id files out=""
  while IFS=$'\t' read -r id files; do
    [ -n "$id" ] || continue
    units_record_stands "$PLAN" "$id" "$files" "$ROOT" "$DROOT"; [ "$?" != 1 ] || out="$out${out:+ }$id"
  done <<< "$(units_rows "$PLAN" 2>/dev/null | CO_ROWS=" $1 " awk -F'\t' '$3 == "close" && index(ENVIRON["CO_ROWS"], " " $1 " ") { print $1 "\t" $9 }')"
  printf '%s' "$out"
}
co_lands_said() {  # <rows landed> <rows left open> <where> -> the rows-landed line's words
  if [ -n "$1" ]; then printf '%s at %s' "$1" "$3"; else printf 'none'; fi
  [ -z "$2" ] || printf '; %s left open — no record it names stands' "$2"
}
act_lands() {  # <rows> -> each landed by one published event at the integration head, a close row once its record stands; LANDS_LINE
  local rows="$1" id ih left open landed=""
  if [ -z "$rows" ]; then
    LANDS_LINE="none — no open integrate or close row"
    return 0
  fi
  ih="$CO_MERGE_COMMIT"
  [ -n "$ih" ] || _co_refuse "no merge was read, so rows $rows have no commit to land at"
  bionic_need line.sh line_published_event || _co_refuse "rows $rows cannot be landed: $CO_LIB/line.sh, the landing record's writer, cannot be loaded"
  open="$(co_lands_open "$rows")"
  for id in $rows; do
    case " $open " in *" $id "*) continue ;; esac
    line_published_event "$PLAN" "row=$id" "commit=$ih" kind=close by=close-out why=merged >/dev/null \
      || _co_refuse "the landing of $id cannot be written to the run's log — rows before it are landed; run close-out again"
    landed="$landed${landed:+ }$id"
  done
  # The readback: the act's own result, asked of the units helper rather than assumed from the writes.
  left="$(co_lands_rows)"
  [ "$left" = "$open" ] || _co_refuse "rows ${left:-none} read open after the landings were written, where only ${open:-none} should — the run's log is not as written"
  LANDS_LINE="$(co_lands_said "$landed" "$open" "$CO_MERGE_REF @ $(git -C "$ROOT" rev-parse --short "$ih" 2>/dev/null)")"
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
# co_wt_refs -> every wt/ branch this repository holds, each as ` refs/heads/wt/<name> `, from one ask of git: a tree's
# branch is then a membership test that starts no process, however many trees the register names. Taken again at each
# call, never kept, so a branch `run` deletes is not read as held after.
co_wt_refs() {
  printf ' %s ' "$(git -C "$ROOT" for-each-ref --format='%(refname)' refs/heads/wt/ 2>/dev/null | tr '\n' ' ')"
}
# wt_branches -> the registered trees' branches, in the order the reader holds the rows'
# trees: for each tree fact, `wt/<basename of its path>` when this repository actually
# holds that branch, each branch once (spawn-worktree.sh's own tree<->branch contract,
# pinned at tests/spawn-worktree.test.sh's Group 11). A tree this repository does not
# hold names nothing to the census, the same as a row with none; a run with no trees is
# an empty census, not a fault.
wt_branches() {
  local cell b seen=" " refs
  refs="$(co_wt_refs)"
  # The register is the reader's tree facts: a row's tree, as its `worktree` cell or its tree event names it.
  while IFS= read -r cell; do
    case "$cell" in ''|'—') continue ;; esac
    cell="${cell%/}"
    b="wt/${cell##*/}"
    case "$seen" in *" $b "*) continue ;; esac
    seen="$seen$b "
    case "$refs" in *" refs/heads/$b "*) printf '%s\n' "$b" ;; esac
  done <<< "$(co_facts tree path)"
  return 0
}

# wt_unreached -> every registered tree's wt/* branch carrying a commit the working branch never took. The
# candidates are the register's (`wt_branches`): a run that registered no tree has none, and an empty census is no
# refusal, said by name where `check` prints it.
wt_unreached() {
  local b _co_cherry candidates
  candidates="$(wt_branches)"
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
    _co_held "a branch holds commits the run never took" \
      "$(printf '%s' "$unreached" | tr '\n' ' ' | sed -E 's/[[:space:]]+$//') carries a commit $WORKING never took (git cherry) — nothing was deleted, and nothing else was done"
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

# ─── Before act 3: the orphan sweep and the run's count of full runs (wave-30 T12; D6, D7d) ──
#
# A RUN IS AN OBJECT THAT OUTLIVES ITS CALLER (booked.sh --detach, wave-30 T8), so a closing run can
# leave one behind: a detached suite run whose pid is alive and that wrote no end (`<log>.rc`) under
# `<tmp>/runs`. Nobody is waiting on it and the wipe is about to take its files, so `run` stops each
# one through `session-poker.sh stop-run` (TERM to its group, KILL to what is left, rc=137 recorded
# when it wrote no end) and names it with its last progress line; `check` names it and sends nothing.
# A run already ended, or LOST, is no process and gets no line. Nothing is refused by the sweep.
#
co_poker() { printf '%s/hooks/session-poker.sh' "$(plugin_root)"; }
# THE HAND-HOLDS, READ LAST. `landing-report --hand-holds` folds the uses of the escape-hatch verbs by kind from the
# lines the verbs wrote (hooks/poker/line.sh `hand_holds_report` owns the rules), over the window from the last build
# landing to the plan's `delivered:` time. `run` writes `delivered:` and only then takes its final reading, so every act
# it performed before it, after the release approval card as much as before, is inside the window; the card prints
# that reading, and the continuation's line, written earlier, is replaced by it. Every kind is read from the run's
# record and log, which the wipe of act 3 does not touch. A report that cannot be read is a sentence, not a count.
CO_HH_LINE=""
co_hand_holds() {  # -> sets CO_HH_LINE
  local out
  out="$(cd "$ROOT" && bash "$(co_poker)" landing-report --hand-holds "$PLAN" 2>/dev/null | /usr/bin/grep '^hand-holds: ' | head -n 1)" || out=""
  if [ -n "$out" ]; then CO_HH_LINE="$out"
  else CO_HH_LINE="hand-holds: not read — session-poker.sh landing-report --hand-holds $PLAN could not be read"; fi
}
# THE HAND ACTS, BY KIND. Each kind of act the hands question answers for the run is one line: its name, how many acts,
# and each distinct reason once, in the order it first appears, since a reason given many times is one thing the
# interface lacked. A landing by hand is a kind like the others. A kind with no act has no line, and a run with none
# has no section. The answer is the hand-holds' own source, the run's log, never a roster.
CO_HA_LINES=""
CO_HA_READ=no
co_hand_acts() {  # -> sets CO_HA_LINES, one `hand act: <kind> · <n> · <reasons>` line per kind, or the sentence of a failed read
  local ans
  CO_HA_READ=yes
  ans="$(co_ask reader_q_hands)" || { CO_HA_LINES="hand acts: not read — the run's facts could not be read"; return 0; }
  CO_HA_LINES="$(printf '%s\n' "$ans" | awk -F'|' "$_READER_AWK"'
    { k = (ev() == "published") ? "landing by hand" : line_kv("what") }
    k == "" { next }
    { if (!(k in n)) o[++m] = k; n[k]++
      w = line_kv("why"); if (w == "" || w == "-") w = "no reason given"
      if (!((k SUBSEP w) in seen)) { seen[k SUBSEP w] = 1; r[k] = r[k] (r[k] == "" ? "" : "; ") w } }
    END { for (i = 1; i <= m; i++) printf "hand act: %s · %d · %s\n", o[i], n[o[i]], r[o[i]] }')"
}
# co_hand_acts_section -> `## Hand acts` and its lines, fenced as the hand-holds are, a failed read its sentence
# unfenced; nothing at all for a run with no act by hand.
co_hand_acts_section() {
  [ "$CO_HA_READ" = yes ] || co_hand_acts
  [ -n "$CO_HA_LINES" ] || return 0
  printf '## Hand acts\n\n'
  case "$CO_HA_LINES" in
    "hand acts: not read "*) printf '%s\n' "$CO_HA_LINES" ;;
    *) printf '```\n%s\n```\n' "$CO_HA_LINES" ;;
  esac
}
# co_hand_holds_last -> the final reading, after `delivered:` is written: CO_HH_LINE, and the continuation's line this
# run wrote replaced by it. A line the continuation held before this run is a person's or an earlier close's, and stays.
co_hand_holds_last() {
  local was="$CO_HH_LINE" tmp
  co_hand_holds
  [ -n "$was" ] && [ "$was" != "$CO_HH_LINE" ] && [ "$CO_HH_CONT" = "$was" ] && [ -f "$CONT" ] || return 0
  bionic_need root.sh bionic_new && bionic_new "$CONT.close-out" || return 0
  tmp="$BIONIC_NEW"
  CO_WAS="$was" CO_NOW="$CO_HH_LINE" awk '
    /^## / { sec = ($0 == "## Hand-holds") }
    sec && !done && $0 == ENVIRON["CO_WAS"] { print ENVIRON["CO_NOW"]; done = 1; next }
    { print }' "$CONT" >| "$tmp" 2>/dev/null && mv -f "$tmp" "$CONT" || rm -f "$tmp"
}
# THE CLOSE PROVES THE CRITERIA ITS LAST READING MEASURES. A criterion is owed at the step whose task proves it. The
# ones owed at Step 9 whose test names `landing-report --hand-holds` (lib/walls.sh `matrix_close_rows`, the gate's own
# readers, asked in a subshell as the facts judge asks them) are proved by the line `co_hand_holds_last` reads after
# `delivered:`, so they are settled here, in the same act and before the archive move, while the plan still finds its
# run's log: at total=0 one proof event naming each, its evidence the continuation where the line is kept, through the
# proof library's one writer; above zero nothing is written and the criterion stays pending, the line quoted in the
# report. The plan is not written. A proof that cannot be appended is a line of the report and never a refusal: the run
# is delivered already.
CO_MX_LINES=""
co_matrix_settle() {  # -> CO_MX_LINES, one `matrix: <AC> <state>` line per criterion
  local acs ac
  CO_MX_LINES=""
  [ -f "${CO_LIB}/walls.sh" ] || return 0
  acs="$( bionic_need walls.sh matrix_close_rows || exit 0
          matrix_close_rows "$PLAN" )"
  for ac in $acs; do
    if ! /usr/bin/grep -qE '^hand-holds: total=0( |$)' <<< "$CO_HH_LINE"; then
      CO_MX_LINES="${CO_MX_LINES:+$CO_MX_LINES$'\n'}matrix: $ac blocked — $CO_HH_LINE"
    elif proof_event "$PLAN" "ac=$ac" "evidence=$CONT_REL"; then
      CO_MX_LINES="${CO_MX_LINES:+$CO_MX_LINES$'\n'}matrix: $ac discharged, evidence $CONT_REL"
    else
      CO_MX_LINES="${CO_MX_LINES:+$CO_MX_LINES$'\n'}matrix: $ac not written — its proof could not be appended to the run's log; the line it owes is $CO_HH_LINE"
    fi
  done
  return 0
}
# THE SCORECARD, READ BEFORE THE WIPE. `landing-report --scorecard` prints four lines, each against its target (human
# stops on the autonomous half, agent minutes after the final reply, the widest landing ready→landed, human-wait
# minutes), the asks put to the person and their minutes, then the fact sheet's pace, correctness and waste lines,
# byte for byte (hooks/poker/sitrep.sh `scorecard_report` owns the rules). The agent minutes are read off the rosters, which act 3 wipes, so `run` reads
# the lines before the wipe into CO_SC_LINES and the continuation's `## Scorecard` prints that one reading. Nothing
# prints them on stdout: the close-out report shows its ten parts, and the lines live in the continuation. A report
# that cannot be read is a sentence.
CO_SC_LINES=""
co_scorecard() {  # -> sets CO_SC_LINES
  local out
  out="$(cd "$ROOT" && bash "$(co_poker)" landing-report --scorecard "$PLAN" 2>/dev/null)" || out=""
  if [ -n "$out" ]; then CO_SC_LINES="$out"
  else CO_SC_LINES="scorecard: not read — session-poker.sh landing-report --scorecard $PLAN could not be read"; fi
}

# THE RELEASE ENTRY'S REVIEWS, RENDERED FROM THE PLAN. The entry's `### The reviews` part is the machine's: lib/line.sh
# `line_reviews_state` renders it, the one renderer the integrate row's `reviews-part` uses too. That verb writes it
# before the pull request opens, so the merge carries it to the integration branch and close-out finds it already
# listed and writes nothing. A run whose part no earlier verb wrote, one with no pull request among them, gets it here:
# the commit is made in the object store on the working branch's tip, under the checkout's own author, as the line
# makes its numbers commit. `run` makes it before its first act, so a commit that cannot be made refuses with nothing done,
# and publishes it after the merge acts: the branch moves to it (lib/line.sh `line_reviews_move`) and the run's log
# gains a published event, `part=reviews commit=<c> branch=<working> by=close-out`, so the branch holds no commit the
# log does not name. No `release:`, no CHANGELOG.md on the branch, no entry for the release, no review or waiver registered, or a
# part that already reads as rendered: nothing is made and no line is written.
# Sets CO_RV_LINE (the `reviews:` line's words), CO_RV_COMMIT (the commit, made, not yet published), CO_RV_BASE.
CO_RV_LINE=""; CO_RV_COMMIT=""; CO_RV_BASE=""
co_reviews_prepare() {  # <check|run> -> CO_RV_LINE, and in run CO_RV_COMMIT; rc 1 when run cannot make the commit
  local mode="$1" tip tmp why
  CO_RV_LINE=""; CO_RV_COMMIT=""; CO_RV_BASE=""
  [ -n "$RELEASE" ] || { CO_RV_LINE="none — the plan names no release:"; return 0; }
  tip="$(git -C "$ROOT" rev-parse --verify -q "refs/heads/${WORKING}^{commit}" 2>/dev/null)" \
    || { CO_RV_LINE="none — $WORKING is not a branch in $ROOT"; return 0; }
  bionic_need line.sh line_reviews_state || { CO_RV_LINE="not rendered — $CO_LIB/line.sh, the renderer and the landing record's writer, cannot be loaded"; return 1; }
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/close-out-reviews.XXXXXX")" || { CO_RV_LINE="not rendered — no temporary directory"; return 1; }
  if ! line_reviews_state "$PLAN" "$ROOT" "$tip" "$WORKING" "$tmp/new"; then
    rm -rf "$tmp"; CO_RV_LINE="not rendered — $LINE_RV_SAID"; return 1
  fi
  case "$LINE_RV_STATE" in
    none) rm -rf "$tmp"; CO_RV_LINE="none — $LINE_RV_SAID"; return 0 ;;
    listed) rm -rf "$tmp"
      CO_RV_LINE="the $LINE_RV_VER entry's ### The reviews already lists the plan's $LINE_RV_N review and waiver lines"; return 0 ;;
  esac
  if [ "$mode" = check ]; then
    rm -rf "$tmp"
    CO_RV_LINE="run would render $LINE_RV_N review and waiver lines under ### The reviews of the $LINE_RV_VER entry and commit them on $WORKING @ ${tip:0:12}"
    return 0
  fi
  why="$(line_reviews_checkout "$ROOT" "$WORKING")"
  [ -z "$why" ] || { rm -rf "$tmp"; CO_RV_LINE="not rendered — $why"; return 1; }
  if line_reviews_commit "$ROOT" "$tip" "$tmp/new" \
       "close-out: the $LINE_RV_VER entry's reviews, rendered from the plan"; then
    rm -rf "$tmp"
    CO_RV_COMMIT="$LINE_RV_COMMIT"; CO_RV_BASE="$tip"
    CO_RV_LINE="$LINE_RV_N review and waiver lines rendered under ### The reviews of the $LINE_RV_VER entry, committed ${CO_RV_COMMIT:0:12} on $WORKING"
    return 0
  fi
  rm -rf "$tmp"
  CO_RV_LINE="not rendered — on $WORKING: $LINE_RV_SAID"
  return 1
}
co_reviews_publish() {  # -> the branch at CO_RV_COMMIT and its close-out event recorded; rc 1 with CO_RV_LINE saying why
  [ -n "$CO_RV_COMMIT" ] || return 0
  if ! line_reviews_move "$ROOT" "$WORKING" "$CO_RV_COMMIT" "$CO_RV_BASE" "close-out: reviews"; then
    CO_RV_LINE="not published — $WORKING could not be moved from ${CO_RV_BASE:0:12} to ${CO_RV_COMMIT:0:12}"
    return 1
  fi
  line_published_event "$PLAN" part=reviews "commit=$CO_RV_COMMIT" "branch=$WORKING" by=close-out && return 0
  CO_RV_LINE="$WORKING moved to ${CO_RV_COMMIT:0:12}, and its published event (part=reviews commit=$CO_RV_COMMIT branch=$WORKING) could not be appended to the run's log $(reader_log "$PLAN" 2>/dev/null || printf 'of %s' "$PLAN")"
  return 1
}
# WHAT GOVERNED THE RUN, READ BEFORE THE WIPE (wave-36 T2; D7, REQ-1 AC-1.4, ADR-055). hooks/session-start.sh writes
# one load record per session start under the project's tmp (wave-36 T1): `root=`, `commit=` when the root is a
# checkout of the plugin, `started=`, then a sha256 per loaded file. A record outlives its session for this reader's
# sake, and is no sweep class, so act 3 removes it as an unkeyed entry: `run` reads it first into CO_GOV_LINES, and
# the card and the continuation both print that one reading, as the hand-holds are.
#
# THE WINDOW is the run's Step 4 to now: the first ISO instant on the `- Step 4:` line or its indented lines, else the
# plan's `approved-by:` instant (the plan's approval is Step 4's start), else every record. A session started before
# it governed none of the run's rows. One line per root and commit, dated by the first session that ran it, in that
# order: `governed-by: <root> <commit> from <ISO>`. A record with no commit ran an installed copy, named by that
# copy's own manifest: `governed-by: <root> installed <version> from <ISO>`. None in the window: the installed
# version this script runs from, `governed-by: installed <version>`. A link is never a record.
CO_GOV_LINES=""
co_iso_secs() {  # <text> -> its first ISO-8601 UTC instant as YYYY-MM-DDTHH:MM:SSZ, or nothing
  local iso
  iso="$(printf '%s\n' "${1:-}" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2})?Z' | head -n 1)"
  case "${#iso}" in
    17) printf '%s:00Z' "${iso%Z}" ;;
    20) printf '%s' "$iso" ;;
  esac
}
co_window_start() {  # -> the run's Step-4 instant, else its plan approval's, as YYYY-MM-DDTHH:MM:SSZ; nothing when neither
  local from
  from="$(co_iso_secs "$(co_facts step | awk -F'|' "$_READER_AWK"'line_kv("n") == "4" { print line_kv("at"); exit }')")"
  [ -n "$from" ] || from="$(co_iso_secs "$(co_facts approval | awk -F'|' "$_READER_AWK"'line_kv("key") == "step3" { print line_kv("at"); exit }')")"
  printf '%s' "$from"
}
co_governed_rows() {  # <window start|""> -> "<started>\t<root>\t<commit, or installed <version>>" per record in it
  local from="${1:-}" f l root commit started
  for f in "$TMP_DIR"/loaded-*.state; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    root=""; commit=""; started=""
    while IFS= read -r l || [ -n "$l" ]; do
      case "$l" in
        root=*) root="${l#root=}" ;;
        commit=*) commit="${l#commit=}" ;;
        started=*) started="${l#started=}" ;;
        *) break ;;
      esac
    done < "$f"
    [ -n "$root" ] && [ -n "$started" ] || continue
    if [ -n "$from" ] && [[ "$started" < "$from" ]]; then continue; fi
    [ -n "$commit" ] || commit="installed $(co_plugin_version "$root")"
    printf '%s\t%s\t%s\n' "$started" "$root" "$commit"
  done
  return 0
}
co_governed() {  # -> sets CO_GOV_LINES
  CO_GOV_LINES="$(co_governed_rows "$(co_window_start)" | LC_ALL=C sort \
    | awk -F'\t' '!seen[$2 FS $3]++ { printf "governed-by: %s %s from %s\n", $2, $3, $1 }')"
  [ -n "$CO_GOV_LINES" ] || CO_GOV_LINES="governed-by: installed $VERSION"
}
co_orphans() {  # <run|check> -> one `orphan:` line per live detached run under $TMP_DIR/runs
  local log out id prog
  [ -d "$TMP_DIR/runs" ] || return 0
  for log in "$TMP_DIR/runs"/*.log; do
    [ -f "$log" ] && [ -f "$log.pid" ] || continue
    [ ! -s "$log.rc" ] || continue
    id="${log##*/}"; id="${id%.log}"
    prog="$(tail -n 1 "$log.progress.tsv" 2>/dev/null | tr '\t' ' ')"
    if [ "$1" = check ]; then
      out="$(cd "$ROOT" && bash "$(co_poker)" stop-run "$log" --report-only 2>/dev/null)"
    else
      out="$(cd "$ROOT" && bash "$(co_poker)" stop-run "$log" --machine close-out --why 'an orphan at the close: no session followed it' 2>/dev/null)"
    fi
    case "$out" in
      *" — RUNNING; would TERM"*|*" — stopped ("*) say "orphan: $id — ${out#* — }; last progress: ${prog:-none}" ;;
    esac
  done
  return 0
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
# there is recognised here without a second list to keep in step. The owner is the name
# after `<class>-` up to its first dot, lib/patrol.sh's rule for every class (wave-27 T68): a
# session id holds no dot, so a per-start `start-clock-<sid>.<agent id>.state` is <sid>'s.
_co_tmp_owner() {
  local base="$1" class owner
  for class in $PATROL_STATE_CLASSES; do
    case "$base" in
      "$class"-*.state|"$class"-*.state"$PATROL_STATE_ARMED_SUFFIX")
        owner="${base#"$class"-}"
        owner="${owner%%.*}"
        [ -n "$owner" ] && printf '%s\n' "$owner"
        return 0
        ;;
    esac
  done
  return 0
}

# THE SCRATCH ROOT IS SPARED BY WHO OWNS EACH FOLDER IN IT. `scratch/<session>/<agent name>/` is a dispatched
# agent's own (hooks/execution-recorder.sh), and no state class keys it, so the rule above would take every
# session's whole. Here a folder of another session stands while that session is live (`patrol_live_session_ids`),
# and in this session's own folder an agent's stands while its name is open on this session's roster (the one close
# predicate, `roster_open_names`, with the sweeper's acks applied); every other folder is removed. Asked before the
# removal pass, which takes the roster it reads. <scratch root> -> rc 0 when something under it was kept, with
# CO_SCRATCH_KEPT the folders kept; rc 1 when nothing was, and the caller removes the root.
CO_SCRATCH_KEPT=0
_co_tmp_scratch() {
  local root="$1" live own="" s n
  CO_SCRATCH_KEPT=0
  live="$(patrol_live_session_ids 2>/dev/null)"
  [ -z "$CO_SID" ] || own="$(roster_open_names "$(roster_path "$ROOT" "$CO_SID")" "$TMP_DIR/sweeper-$CO_SID.state" "$CO_SID")"
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    if [ -n "$CO_SID" ] && [ "${s##*/}" = "$CO_SID" ] && [ -d "$s" ] && [ ! -L "$s" ]; then
      while IFS= read -r n; do
        [ -n "$n" ] || continue
        case "
$own
" in
          *"
${n##*/}
"*) if [ -d "$n" ] && [ ! -L "$n" ]; then CO_SCRATCH_KEPT=$((CO_SCRATCH_KEPT + 1)); continue; fi ;;
        esac
        rm -rf "$n"
      done <<< "$(find "$s" -mindepth 1 -maxdepth 1 2>/dev/null)"
      [ -n "$(find "$s" -mindepth 1 -maxdepth 1 2>/dev/null)" ] || rm -rf "$s"
      continue
    fi
    case "
$live
" in
      *"
${s##*/}
"*) if [ -d "$s" ] && [ ! -L "$s" ]; then CO_SCRATCH_KEPT=$((CO_SCRATCH_KEPT + 1)); continue; fi ;;
    esac
    rm -rf "$s"
  done <<< "$(find "$root" -mindepth 1 -maxdepth 1 2>/dev/null)"
  [ "$CO_SCRATCH_KEPT" -gt 0 ]
}

# THIS SESSION'S ENGAGED MARKER IS KEPT, AND REMOVED AS THE LAST ACT (wave-36 T14; D13, C70). It is also the
# session's binding, and every plan verb asks it first: wiped here, a close-out refused later in the tail left the
# person with no verb to repair the plan by (NOT-ENGAGED). `act_disengage` removes it after everything else.
act_tmp() {
  local before after entry owner dead_ids spare_list="" removed=0 spared=0 is_spared keep="" kept=0 sk=0
  before="$(tmp_count)"
  if [ -n "$CO_SID" ]; then
    keep="$(engaged_marker_path "$ROOT" "$CO_SID" 2>/dev/null)" || keep=""
    [ -n "$keep" ] && [ -f "$keep" ] && [ ! -L "$keep" ] || keep=""
  fi

  if [ -d "$TMP_DIR" ]; then
    dead_ids="$(patrol_dead_sessions "$ROOT")"

    # Build the spare set FIRST, as full paths — every file keyed to a session other
    # than CO_SID that patrol_dead_sessions does not name. This session's own keyed
    # state is never in it (it is removed like a closed run's own, whatever the
    # sweeper's verdict on this pid would be), and neither is anything unkeyed.
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      if [ "$entry" = "$TMP_DIR/scratch" ] && [ -d "$entry" ] && [ ! -L "$entry" ]; then
        _co_tmp_scratch "$entry" && { spare_list="${spare_list}${entry}
"; sk=1; }
        continue
      fi
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
      if [ "$is_spared" != "yes" ] && [ -n "$keep" ] && [ "$entry" = "$keep" ]; then kept=1; continue; fi
      [ "$is_spared" = "yes" ] || { rm -rf "$entry"; removed=$((removed + 1)); }
    done <<< "$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 2>/dev/null)"
  fi

  after="$(tmp_count)"
  [ "$after" = "$((spared + kept + sk))" ] || _co_refuse "$after entries remain under $TMP_DIR after the wipe ($((spared + kept + sk)) expected, for a live neighbour's spared state, this session's engaged marker and the scratch of a live agent)"
  TMP_LINE="$before entries under $TMP_DIR ($removed removed, $spared spared for a live neighbour session"
  [ "$kept" -eq 0 ] || TMP_LINE="$TMP_LINE, 1 kept: this session's engaged marker, removed as close-out's last act"
  [ "$sk" -eq 0 ] || TMP_LINE="$TMP_LINE, scratch kept for $CO_SCRATCH_KEPT live folder(s) under it"
  TMP_LINE="$TMP_LINE; this session's own state and every dead session's are never spared)"
}

# act_disengage -> close-out's LAST act: this session's engaged marker (its binding) removed, after the continuation,
# the epic row, the blocks, the archive and the notice, so any refusal before it left the session engaged (wave-36 T14).
# The session's binding RECORD beside the seal outvotes the marker (lib/run.sh `session_plan`), so it goes with the
# marker on every road that has a session key, the marker found or not: left standing, the closed-out session would read
# as bound to the plan it closed. A record that survives its removal is a refusal, as the marker's is.
act_disengage() {
  local m="" rec="" rc=0
  if [ -z "$CO_SID" ]; then
    say "disengaged: no session key — no engaged marker to remove"
    return 0
  fi
  seal_binding_drop "$ROOT" "$CO_SID" || rc=$?
  case "$rc" in
    0) rec=" and its binding record dropped" ;;
    2) rec="" ;;
    *) _co_refuse "the session's binding record could not be dropped (exit $rc)" ;;
  esac
  if ! m="$(engaged_marker_path "$ROOT" "$CO_SID" 2>/dev/null)"; then
    say "disengaged: no engaged marker path for this session${rec:+ —$rec}"
    return 0
  fi
  if [ ! -e "$m" ] && [ ! -L "$m" ]; then
    say "disengaged: this session holds no engaged marker — nothing to remove${rec:+;$rec}"
    return 0
  fi
  rm -f "$m" 2>/dev/null
  [ ! -e "$m" ] && [ ! -L "$m" ] || _co_refuse "the engaged marker $m survived its removal"
  say "disengaged: $m removed${rec} — close-out's last act; this session is no longer engaged"
}

# ─── Act 4: the task list ────────────────────────────────────────────────────
#
# TaskUpdate is a model tool. This is the instruction, printed in the acts' own shape.
TASKS_LINE="mark every 4/*, 5–9 entry completed (TaskUpdate)"

# ─── Act 5: the continuation ─────────────────────────────────────────────────
#
# THE CONTINUATION IS WRITTEN WHOLE (wave-33 T8; D8, AC-3.3). Every field this script can derive it
# writes: the commit it closed at, the task count (the plan's build rows), the regression result (the
# floor's proof line), the reviews (the review proof lines) and the ADRs (the spec's or the plan's `adrs:`).
# A close once completed
# fourteen marks by hand; five remain, and they are the ones only a person decides: the
# first decision put to the user, what was ruled at the close, the next wave's version and ideas file, and
# its carry-overs. `co_owed_line` names each of them in the close-out output. A template that invented
# plausible values for those would produce a continuation that read true and was not.
#
# NEVER OVERWRITTEN. A continuation that already exists has been edited by the person who
# knew those answers, and the second run of a close-out is exactly when that edit would be
# destroyed.
CONT_LINE=""

# THE DEFERRALS THE CONTINUATION CARRIES (wave-28 T17; D21, AC-8.7). One line per open deferral, in
# the order the plan wrote them, in the one form the next wave's Step 1 card reads:
#
#     deferred: <record>#<n> <S> <reach> "<title>" stated="<sentence|->" from=<wave name>
#
# OPEN is what lib/proof.sh `proof_findings_owed` says: a finding with a `deferred:` line whose
# effective priority is `defer`, rated through the one place the effective rating is applied. A
# `check:` line alone is a check owed, not a deferral. The sentence is the plan line's ` stated="..."`
# field as the deferral wrote it (a `\` or a `"` in it is already written `\\` or `\"`), `-` when it
# has none; a deferral is carried whether or not it is stated. The sentence is the newest one any event of the
# finding states (lib/reader.sh `reader_events`): the standing finding is its newest word, and a move written
# after the deferral replaces it without the sentence.
co_deferrals() {  # -> the lines, or nothing: the deferrals, then the unburned debt (co_debts)
  local id s r p t owed said st
  owed="$(proof_findings_owed "$PLAN" 2>/dev/null | awk '$4 == "defer"')"
  if [ -n "$owed" ]; then
    # `<record>#<n><TAB>y<stated>` for each finding's first deferral, in event order: one read of the run's events
    said="$(reader_events "$PLAN" 2>/dev/null)" || return 2
    said="$(printf '%s\n' "$said" | awk -F'|' "$_READER_AWK"'
      ev() == "finding" { r = line_kv("ref"); if (!(r in st)) o[++n] = r; if (line_kv("stated") != "" || !(r in st)) st[r] = line_kv("stated") } END { for (i = 1; i <= n; i++) printf "%s\ty%s\n", o[i], st[o[i]] }')"
    while read -r id s r p t; do
      st="$(printf '%s\n' "$said" | CO_ID="$id" awk -F'\t' '$1 == ENVIRON["CO_ID"] { print $2; exit }')"
      [ -n "$st" ] || continue
      st="${st#y}"
      printf 'deferred: %s %s %s %s stated="%s" from=%s\n' "$id" "$s" "$r" "$t" "${st:--}" "$WAVE_SLUG"
    done <<< "$owed"
  fi
  co_debts || return 2
}

# THE DEBT THE CONTINUATION CARRIES. Every debt of the run not yet burned, the reader's debt facts in their order,
# after the deferrals and under the same heading, in the one form:
#
#     debt: <concept> <kind> "<sites>" touches=<N> raised-by=<record> from=<wave name>
#
# A burned item is paid and is not carried. The merge into an existing continuation is the deferrals'
# (co_cont_missing), so a line already under the heading is not written twice.
#
# ONLY A LINE THAT PARSES IS CARRIED. Each line is held to the one grammar, lib/debt.sh `debt_line_ok`, which
# `debt add` and card.sh read by too; a debt it refuses is never written here, and `run` refuses it, naming it,
# before its first act (co_debt_refusal), so the next run's Step-1 card is never refused on a line this run carried.
co_debt_lines() {  # -> `ok<TAB><line>` or `bad<TAB><line>` per debt not burned, in the reader's order; 2 when unread
  local l d
  d="$(co_facts debt)" || return 2
  printf '%s' "${d:+$d$'\n'}" | awk -F'|' -v w="$WAVE_SLUG" "$_READER_AWK"'line_kv("burned") == "" {
      printf "debt: %s %s \"%s\" touches=%s raised-by=%s from=%s\n", line_kv("concept"), line_kv("kind"), line_kv("sites"), line_kv("touches"), line_kv("raised-by"), w }' \
    | while IFS= read -r l; do
        if debt_line_ok "$l"; then printf 'ok\t%s\n' "$l"; else printf 'bad\t%s\n' "$l"; fi
      done
}
co_debts() {
  local d
  d="$(co_debt_lines)" || return 2
  printf '%s\n' "$d" | awk -F'\t' '$1 == "ok" { print substr($0, 4) }'
}

# co_debt_refusal -> the sentence naming the first debt whose carried line the grammar refuses; nothing when every
# debt parses. `run` refuses on it; `check` says it would.
co_debt_refusal() {
  local bad
  bad="$(co_debt_lines)" || return 2
  bad="$(printf '%s\n' "$bad" | awk -F'\t' '$1 == "bad" { print substr($0, 5); exit }')"
  [ -n "$bad" ] || return 0
  printf "the run's log carries a debt that does not parse as a debt line: %s" "$bad"
}

# THE CARD'S DEBT LINE: `debt: touched <N> · burned <M>` for the run, N the touches summed over every debt the reader
# holds, M the debts burned, never the ledger's length; `touched 0 · burned 0` when the run kept none, so the line
# is never omitted.
co_debt_card() {
  co_facts debt | awk -F'|' "$_READER_AWK"'{ t += line_kv("touches"); if (line_kv("burned") != "") b++ }
    END { printf "debt: touched %d · burned %d\n", t, b }'
}

# THE DEFERRALS THIS RUN INHERITED AND DID NOT SETTLE (wave-28 T43; D21, AC-8.10). The run's
# requirements file disposes of what the newest continuation before it left open, under `## Inherited
# deferrals`: `adopted: <id> as REQ-<n>`, `again: <id>`, `closed: <id> <reason>`. Every line deferred
# again, and every one not disposed of, is carried after this run's own, AS THE OLD CONTINUATION WROTE
# IT, its `from=` kept; an adopted or a closed one is not. The reading is card.sh's (`card.sh inherited`),
# the one the Step 1 card listed them from, so the card and the carry are one answer. A plan that names
# no requirements file, or one that is not there, disposed of nothing: the path handed over is then
# `<plans dir>/<wave slug>.requirements.md`, whose name still tells card.sh which run's own continuation
# to skip.
CO_CARRIED=""
co_requirements() {  # -> the run's requirements file, or the path naming none
  local r
  r="$(plan_frontmatter_get "$PLAN" requirements)"
  case "$r" in
    '') ;;
    /*) ;;
    *)  r="$DROOT/$r" ;;
  esac
  [ -n "$r" ] && [ -f "$r" ] || r="$PLANS_DIR/$WAVE_SLUG.requirements.md"
  printf '%s\n' "$r"
}
co_carried() {  # -> every inherited deferred: line deferred again or left undisposed, as written,
  # then every inherited debt: line the run's ledger does not hold (co_carried_debts)
  local out
  out="$(bash "$CO_SCRIPTS/card.sh" inherited "$(co_requirements)" 2>/dev/null)" || return 1
  printf '%s\n' "$out" | awk -F '\t' '$1 == "again" || $1 == "open" { print substr($0, length($1) + 2) }'
  co_carried_debts
}
# AN INHERITED DEBT NOBODY ADOPTED IS CARRIED AGAIN (wave-30 T23; A-orch-44). `debt adopt` writes a
# continuation's `debt:` lines into the run's ledger (wave-30 T32), and co_debts carries the ledger's
# unburned items; an item adopted and burned is paid. A line nobody adopted is in no ledger, so it is
# carried as the old continuation wrote it, its `from=` kept, unless the ledger holds its concept and
# kind, whose own line (or burn) is the answer. Before this it was dropped at the next close-out.
co_carried_debts() {  # -> the inherited debt: lines whose concept and kind the run's ledger lacks
  local have="" out
  out="$(bash "$CO_SCRIPTS/card.sh" inherited-debt "$(co_requirements)" 2>/dev/null)" || return 1
  [ -n "$out" ] || return 0
  have="$(co_facts debt | awk -F'|' "$_READER_AWK"'{ print line_kv("concept") "\t" line_kv("kind") }')"
  printf '%s\n' "$out" | CO_HAVE="$have" awk '
    BEGIN { n = split(ENVIRON["CO_HAVE"], h, "\n"); for (i = 1; i <= n; i++) if (h[i] != "") held[h[i]] = 1 }
    $1 == "debt:" && !(($2 "\t" $3) in held) { print }'
}
# co_cont_has_deferrals -> 0 when the existing continuation carries the heading outside a code fence
# (a pasted example of the form is not the section; read-adversarial-p15 #4)
co_cont_has_heading() {  # <heading> -> 0 when the existing continuation carries it outside a code fence
  CO_HEAD="$1" awk '/^[[:space:]]*```/ { fence = !fence; next } !fence && $0 == ENVIRON["CO_HEAD"] { found = 1; exit }
       END { exit !found }' "$CONT" 2>/dev/null
}
co_cont_has_deferrals() { co_cont_has_heading "## Deferrals"; }
# co_deferrals_section -> the heading and its lines, written whether or not there is anything under it:
# this run's own deferrals first, then what it carries (CO_CARRIED, read by act_continuation)
co_deferrals_section() {
  local lines="$CO_DEFER"
  [ -z "$CO_CARRIED" ] || lines="${lines:+$lines
}$CO_CARRIED"
  printf '## Deferrals\n'
  [ -z "$lines" ] || printf '\n%s\n' "$lines"
}

# THE MERGE INTO A CONTINUATION THAT ALREADY CARRIES THE HEADING (wave-28 T50; A-orch-74 supersedes
# A-T17.6's "with the heading, never touched"). Every line close-out would write — this run's own
# deferrals, then what it carries — that is not under the first `## Deferrals` heading outside a fence,
# byte for byte, is added at the end of that section, each once; what a person wrote there stays. A
# continuation holding every line is left as it stands.
co_cont_missing() {  # -> the lines owed that are not under the heading yet, in order: co_cont_missing_under's reading
  # of ## Deferrals (wave-38 T15 burns debt continuation-section-reader: one section reader, not two)
  # ## Deferrals is read unfenced (A-T14-4), so a line inside a fence there is not counted as present.
  CO_UNFENCED=1 co_cont_missing_under "## Deferrals" "" "$CO_DEFER${CO_CARRIED:+
$CO_CARRIED}"
}
# A SECTION THAT IS ONE FENCED LIST TAKES THE LINES INSIDE ITS FENCE (wave-36 T14; D13, C38). The lines went after the
# section's last non-blank line, and a closing fence is one, so a line owed to close-out's own fenced sections
# (## Hand-holds, ## Governed by, ## Inherited debt) landed under the fence, outside its list. When the section's first
# and last non-blank lines are the two fence lines of its one fenced block, the lines go before the closing fence; any
# other section takes them after its last non-blank line, as before. ## Deferrals is read unfenced by every reader
# (card.sh's inherited reader, `debt adopt`, `co_cont_missing` above), so its lines always go after: a carried line in a
# fence there is one the next run never reads (A-T14-4).
# ONE WRITER FOR BOTH ADDS (wave-38 T15 burns debt continuation-section-writer). `co_cont_write <heading> <text> lines`
# adds the text at the end of the heading's section by the rule above; `co_cont_write <heading> <text> section` adds the
# text as a new section after the end of the heading's section, a blank line before it and the section's own trailing
# blank lines kept after it. Both walk the file once, holding the section's lines until the next unfenced `## ` heading
# or the end; a heading the file does not carry is a refusal, nothing written.
co_cont_write() {  # <heading> <text> <lines|section> -> $CONT with the text added
  local tmp why="could not add to $1 in the continuation at $CONT"
  [ "$3" = lines ] || why="could not add a section to the continuation at $CONT"
  { bionic_need root.sh bionic_new && bionic_new "$CONT.close-out"; } || _co_refuse "$why"
  tmp="$BIONIC_NEW"
  CO_ADD="$2" CO_HEAD="$1" CO_MODE="$3" awk '
    function isfence(l) { return l ~ /^[[:space:]]*```/ }
    function fin(more,   i, f, l, nf, add) {
      add = ENVIRON["CO_ADD"]; f = 0; l = 0; nf = 0
      for (i = 1; i <= nb; i++) { if (isfence(buf[i])) nf++; if (buf[i] ~ /^[[:space:]]*$/) continue; if (!f) f = i; l = i }
      if (ENVIRON["CO_MODE"] == "section") {
        for (i = 1; i <= l; i++) print buf[i]
        print ""; print add
        for (i = l + 1; i <= nb; i++) print buf[i]
        if (more && l == nb) print ""
      } else if (!l) { print ""; print add; if (more) print "" }
      else if (ENVIRON["CO_HEAD"] != "## Deferrals" && nf == 2 && f < l && isfence(buf[f]) && isfence(buf[l])) {
        for (i = 1; i < l; i++) print buf[i]
        print add
        for (i = l; i <= nb; i++) print buf[i]
      } else {
        for (i = 1; i <= l; i++) print buf[i]
        print add
        for (i = l + 1; i <= nb; i++) print buf[i]
      }
      insec = 0; done = 1; nb = 0
    }
    /^[[:space:]]*```/ { fence = !fence }
    done { print; next }
    !insec { print; if (!fence && $0 == ENVIRON["CO_HEAD"]) insec = 1; next }
    !fence && /^## / { fin(1); print; next }
    { buf[++nb] = $0 }
    END { if (!done && insec) fin(0); if (!done) exit 3 }' "$CONT" >| "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; _co_refuse "$why"; }
  [ -s "$tmp" ] || { rm -f "$tmp"; _co_refuse "$why"; }
  mv "$tmp" "$CONT" 2>/dev/null || { rm -f "$tmp"; _co_refuse "$why"; }
}
co_added_phrase() {  # <lines> -> "<n> deferred line(s)"
  local n
  n="$(printf '%s\n' "$1" | wc -l | tr -d ' ')"
  printf '%s deferred line%s' "$n" "$([ "$n" = 1 ] || echo s)"
}
co_added_ids() {  # <lines> -> the ids, space-joined
  printf '%s\n' "$1" | awk '{ printf "%s%s", (NR > 1 ? " " : ""), $2 } END { print "" }'
}

# THE MERGE OF THE HAND-HOLDS AND THE INHERITED DEBT INTO A CONTINUATION THAT EXISTS (wave-35 T33; D20, A-orch-32;
# critic-adversarial #5). The template writes both sections, and an existing continuation is never overwritten, so
# both take the deferrals' road: the section is inserted under its heading when the file has none, a line the
# section lacks is added at its end, a line already there (fenced or not) is never written twice, and a person's
# text is not touched. The hand-holds line counts as there when the section holds ANY `hand-holds: ` line: a second
# close-out reads a later window, so another count, and a second, contradicting line would be worse than the
# first reading standing (A-T33-1). The inherited lines match byte for byte, as the deferrals do.
co_cont_missing_under() {  # <heading> <prefix|""> <wanted lines> -> the wanted lines the section lacks, in order;
  # CO_UNFENCED=1 counts only the section's unfenced lines as present
  CO_WANT="$3" CO_HEAD="$1" CO_PFX="$2" CO_UNF="${CO_UNFENCED:-}" awk '
    BEGIN { n = split(ENVIRON["CO_WANT"], w, "\n"); p = ENVIRON["CO_PFX"]; unf = (ENVIRON["CO_UNF"] == "1") }
    /^[[:space:]]*```/ { fence = !fence; next }
    !fence && !first && $0 == ENVIRON["CO_HEAD"] { first = insec = 1; next }
    !fence && /^## / { insec = 0; next }
    insec && !(unf && fence) { have[$0] = 1; if (p != "" && index($0, p) == 1) pfx = 1 }
    END { for (i = 1; i <= n; i++) if (w[i] != "" && !have[w[i]] && !pfx && !seen[w[i]]++) print w[i] }' "$CONT"
}
co_cont_sections() {  # <write|check> -> CO_SEC_MSG: what was (write) or would be (check) added; empty when nothing
  local phr="" lines miss n mode="$1"
  CO_SEC_MSG=""
  [ -n "$CO_HH_LINE" ] || co_hand_holds
  if ! co_cont_has_heading "## Hand-holds"; then
    phr="the ## Hand-holds section"
    [ "$mode" != write ] || co_cont_write "## Deferrals" "$(co_hand_holds_section)" section
  else
    miss="$(co_cont_missing_under "## Hand-holds" "hand-holds: " "$CO_HH_LINE")"
    if [ -n "$miss" ]; then
      phr="the hand-holds line under ## Hand-holds"
      [ "$mode" != write ] || co_cont_write "## Hand-holds" "$miss" lines
    fi
  fi
  lines="$(proof_inherited_lines "$PLAN" 2>/dev/null)" \
    || _co_refuse "the run's facts cannot be read, so the inherited debt it carries is not known; run close-out again"
  if [ -n "$lines" ]; then
    if ! co_cont_has_heading "## Inherited debt"; then
      phr="${phr:+$phr and }the ## Inherited debt section"
      [ "$mode" != write ] || co_cont_write "## Hand-holds" "$(co_inherited_section)" section
    else
      miss="$(co_cont_missing_under "## Inherited debt" "" "$lines")"
      if [ -n "$miss" ]; then
        n="$(printf '%s\n' "$miss" | wc -l | tr -d ' ')"
        phr="${phr:+$phr and }$n inherited line$([ "$n" = 1 ] || echo s) under ## Inherited debt"
        [ "$mode" != write ] || co_cont_write "## Inherited debt" "$miss" lines
      fi
    fi
  fi
  # THE GOVERNED-BY LINES (wave-36 T2): the hand-holds' road. The section goes in after ## Hand-holds (so before an
  # ## Inherited debt inserted above), and it counts as there when it holds ANY `governed-by: ` line: a second close
  # reads no record (the first one's wipe took them), and its installed line must not contradict the first reading.
  [ -n "$CO_GOV_LINES" ] || co_governed
  if ! co_cont_has_heading "## Governed by"; then
    phr="${phr:+$phr and }the ## Governed by section"
    [ "$mode" != write ] || co_cont_write "## Hand-holds" "$(co_governed_section)" section
  else
    miss="$(co_cont_missing_under "## Governed by" "governed-by: " "$CO_GOV_LINES")"
    if [ -n "$miss" ]; then
      phr="${phr:+$phr and }the governed-by lines under ## Governed by"
      [ "$mode" != write ] || co_cont_write "## Governed by" "$miss" lines
    fi
  fi
  # THE HAND ACTS: the hand-holds' road, inserted last after ## Hand-holds so they stand next to it, as the template
  # puts them; a line already in the section is never written twice.
  [ "$CO_HA_READ" = yes ] || co_hand_acts
  if [ -n "$CO_HA_LINES" ]; then
    if ! co_cont_has_heading "## Hand acts"; then
      phr="${phr:+$phr and }the ## Hand acts section"
      [ "$mode" != write ] || co_cont_write "## Hand-holds" "$(co_hand_acts_section)" section
    else
      miss="$(co_cont_missing_under "## Hand acts" "" "$CO_HA_LINES")"
      if [ -n "$miss" ]; then
        phr="${phr:+$phr and }the hand act lines under ## Hand acts"
        [ "$mode" != write ] || co_cont_write "## Hand acts" "$miss" lines
      fi
    fi
  fi
  # THE SCORECARD (wave-38 T15; D26): the hand-holds' road, after ## Governed by (so last, as the template puts it). It
  # counts as there when the file holds the heading at all: a
  # second close reads no roster (the first one's wipe took it), and its line must not contradict the first reading.
  [ -n "$CO_SC_LINES" ] || co_scorecard
  if ! co_cont_has_heading "## Scorecard"; then
    phr="${phr:+$phr and }the ## Scorecard section"
    [ "$mode" != write ] || co_cont_write "## Governed by" "$(co_scorecard_section)" section
  fi
  CO_SEC_MSG="$phr"
}

# THE RUN'S NUMBERS (wave-28 T14; D18, AC-4.5). A continuation written from the template carries the
# report's line and one line per landed row, as `session-poker.sh landing-report --rows <plan>` prints
# them, fenced. The plan is NAMED: act 3 has wiped the session's binding by the time act 5 writes this
# (ruling A-orch-145). The report runs in a child, so lib/gate.sh's `gate_ask` never meets this file's.
# A report that cannot be read is said in a sentence (wave-33 T8: a mark would be a placeholder this script wrote).
co_landings_section() {
  local out
  out="$(bash "$(plugin_root)/hooks/session-poker.sh" landing-report --rows "$PLAN" 2>/dev/null)" || out=""
  printf '## Landings\n\n'
  if [ -n "$out" ]; then
    case "$out" in
      "landings: unmeasured "*) printf '%s\n' "$out" ;;
      *) printf '```\n%s\n```\n' "$out" ;;
    esac
  else
    printf 'landings: not read — session-poker.sh landing-report --rows %s could not be read.\n' "$PLAN"
  fi
}

# co_hand_holds_section -> `## Hand-holds` and the line `co_hand_holds` read before the wipe, fenced as the
# landings are; a reading that failed is its sentence, unfenced. Read now only when nothing read it before.
co_hand_holds_section() {
  [ -n "$CO_HH_LINE" ] || co_hand_holds
  printf '## Hand-holds\n\n'
  case "$CO_HH_LINE" in
    "hand-holds: not read "*) printf '%s\n' "$CO_HH_LINE" ;;
    *) printf '```\n%s\n```\n' "$CO_HH_LINE" ;;
  esac
}

# co_scorecard_section -> `## Scorecard` and the lines `co_scorecard` read before the wipe, fenced as the hand-holds are;
# a reading that failed is its sentence, unfenced.
co_scorecard_section() {
  [ -n "$CO_SC_LINES" ] || co_scorecard
  printf '## Scorecard\n\n'
  case "$CO_SC_LINES" in
    "scorecard: not read "*) printf '%s\n' "$CO_SC_LINES" ;;
    *) printf '```\n%s\n```\n' "$CO_SC_LINES" ;;
  esac
}

# co_governed_section -> `## Governed by` and the lines `co_governed` read before the wipe, fenced as the hand-holds are.
co_governed_section() {
  [ -n "$CO_GOV_LINES" ] || co_governed
  printf '## Governed by\n\n```\n%s\n```\n' "$CO_GOV_LINES"
}

# co_inherited_section -> `## Inherited debt` and every inherited suite of the run, one `inherited:` line each, as the verb
# wrote it, fenced as the hand-holds are; nothing at all for a plan that carries none, and the template then prints
# nothing for it, so that continuation is byte for byte what it was (wave-35
# T10; AC-1.6 "carried into the continuation", A-orch-18). The lines are lib/proof.sh `proof_inherited_lines`, the
# one reader the floor's judge reads them through: debt the run inherited, red at its base and at its floor.
co_inherited_section() {
  local lines
  lines="$(proof_inherited_lines "$PLAN" 2>/dev/null)" || return 2
  [ -n "$lines" ] || return 0
  printf '## Inherited debt\n\n```\n%s\n```\n' "$lines"
}

# co_task_count -> the build rows of the plan's ## Tasks table that the rows' one answer does not read dropped: the
# tasks the template says went RED then GREEN. Zero when the plan carries no table.
co_task_count() {
  units_rows "$PLAN" 2>/dev/null | awk -F'\t' '$3 == "build" && $10 != "dropped" { n++ } END { print n + 0 }'
}

# co_reviews_text -> `Reviews: <question> <scope> <result> (<reader>); …. ADRs: <cell>.`, one entry per
# question and scope in the order the reader first holds a review proof of it, each with the result of its newest.
co_reviews_text() {
  local revs adrs
  revs="$(co_ask reader_q_reviews | awk -F'|' "$(proof_fact_awk)"'
    proof_fact() && PROOF_KIND == "review" && PROOF_QUESTION != "" {
      k = PROOF_QUESTION " " PROOF_SCOPE
      if (!(k in res)) order[++n] = k
      res[k] = PROOF_RESULT " (" PROOF_READER ")"
    }
    END { for (i = 1; i <= n; i++) printf "%s%s %s", (i > 1 ? "; " : ""), order[i], res[order[i]]; print "" }')"
  adrs="$(epic_adrs_cell 2>/dev/null)"
  case "$adrs" in ''|—) adrs="none shipped" ;; esac
  printf 'Reviews: %s. ADRs: %s.' "${revs:-none recorded}" "$adrs"
}

continuation_template() {
  local sha tasks regress reviews inherited acts head resume ws line at ev whole_text
  # The integration branch at the merge this close read; the local branch only when no merge was read (a parked run).
  sha="$(git -C "$ROOT" rev-parse --short "${CO_MERGE_COMMIT:-$INTEGRATION}" 2>/dev/null)"
  acts="$(co_hand_acts_section)"
  inherited="$(co_inherited_section)" \
    || _co_refuse "the run's facts cannot be read, so the inherited debt it carries is not known; run close-out again"
  tasks="$(co_task_count)"
  # THE REGRESSION is the full pass's state at the working head, from the one printer the release card and the
  # scorecard draw too (lib/proof.sh `proof_whole_text`), then the proof's instant and log; it is never read off the
  # proof line alone, whose head says nothing of the landings since. A plan that says `regression: no` owed none.
  if [ "$(proof_regression "$PLAN")" = no ]; then
    regress='the regression was not owed (regression: no)'
  else
    line="$(proof_last_line "$PLAN" regression)"
    if [ -z "$line" ]; then
      regress='the regression: no proof is recorded in the plan'
    else
      at="$(printf '%s\n' "$line" | sed -n 's/.* at=\([^ ]*\).*/\1/p')"
      ev="$(printf '%s\n' "$line" | sed -n 's/.* evidence=\([^ ]*\).*/\1/p')"
      whole_text="$(proof_whole_text "$PLAN" "$ROOT")"
      regress="$(printf 'the regression: whole suite %s (proved %s, %s)' "${whole_text:-unverified}" "${at:-?}" "${ev:-no record}")"
    fi
  fi
  reviews="$(co_reviews_text)"
  # A PARKED RUN SAYS SO IN ITS HEADER (wave-38 T15; AC-4.3): parked, where the work is, and why; nothing was merged.
  if [ "$PARKED" = yes ]; then
    ws="$(git -C "$ROOT" rev-parse --short "$WORKING" 2>/dev/null)"
    head="Parked $NOW on \`$WORKING\` @ ${ws:-?}; the merge into \`$INTEGRATION\` ($INTEGRATION at $sha) was not made: $PARKED_WHY
$tasks tasks, every one RED→GREEN; $regress."
    resume="Resume from \`$WORKING\` @ ${ws:-?}: the run is parked, and its branch and worktrees are kept. Why: $PARKED_WHY"
  else
    head="Closed $NOW. $INTEGRATION at $sha. Wave branch \`$WORKING\` $(co_into) into
\`$INTEGRATION\`: $tasks tasks, every one RED→GREEN; $regress."
    resume="Nothing to resume: the run is delivered."
  fi
  cat <<CONT_TEMPLATE
# continuation — $WAVE_SLUG${RELEASE:+ ($RELEASE)}

$head
$reviews

## Chris decides (one decision each)

1. <fill: the first decision, or "none">

## Ruled at close

- <fill: what was ruled at this close, or "none">

## Next wave: <fill: version> — \`<fill: ideas path>\`

<fill: carry-overs from this wave>

$(co_deferrals_section)

$(co_landings_section)

$(co_hand_holds_section)
${acts:+
$acts
}
$(co_governed_section)
${inherited:+
$inherited
}
$(co_scorecard_section)

## Resume instruction

$resume The epic plan (\`${EPIC_PLAN#"$DROOT"/}\`) carries this wave's row;
this file is the wave-local copy.
CONT_TEMPLATE
}

# co_owed_line -> the marks left in the continuation, named: what only a person decides. Said after the
# continuation is written or found, so a hand-written one reports what it still owes too.
co_owed_line() {
  local names n
  names="$(grep -o '<fill: [^>]*>' "$CONT" 2>/dev/null | sed -e 's/^<fill: //' -e 's/>$//' | awk '{ printf "%s%s", (NR > 1 ? "; " : ""), $0 } END { print "" }')"
  n="$(grep -o '<fill: [^>]*>' "$CONT" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${n:-0}" = 0 ]; then
    printf 'continuation-owed: none'
  else
    printf 'continuation-owed: %s mark%s only a person can fill — %s' "$n" "$([ "$n" = 1 ] || echo s)" "$names"
  fi
}

# CO_HH_CONT: the hand-holds line act_continuation wrote into the continuation, empty when it wrote none (the file
# already held one); the final reading replaces only that line.
CO_HH_CONT=""
co_cont_hh_none() {  # -> 0 when the continuation holds no `hand-holds: ` line under its ## Hand-holds heading
  [ -f "$CONT" ] || return 0
  ! awk '/^## / { s = ($0 == "## Hand-holds"); next } s && index($0, "hand-holds: ") == 1 { f = 1 } END { exit !f }' "$CONT"
}
# THE CONTINUATION HAS ONE WRITER. A close row whose Files name it, and which was ever dispatched (the run's log holds a
# dispatch of it, whether or not the launch was taken back since), has a writer of its own for that file, so the close
# writes none of it, the file there or not: two writers of one file is how a close appended to a continuation its row's
# writer was still writing, or had begun before the stand-down took its launch back. A close row nobody dispatched has
# no writer, and the close stays the file's one writer, as before. Files entries are read from the project's root and
# from the docs root, the two spellings a planner writes. Whether a writer is out NOW is another question, the one that
# holds the close (co_rows_out); this one asks whether a writer ever began the file.
# co_rows_sent -> every row the run's log ever dispatched, one per line: read off the log's lines, since a cancel takes
# the dispatch out of the standing facts. 2 when the lines cannot be read.
co_rows_sent() {
  local said
  bionic_need reader.sh reader_events || return 2
  said="$(reader_events "$PLAN")" || return 2
  printf '%s\n' "$said" | awk -F'|' "$_READER_AWK"'ev() == "dispatch" { print line_kv("row") }'
}
# co_cont_owner -> the id of the close row that owns the continuation, or nothing
co_cont_owner() {
  local rows id files e
  rows="$(units_rows "$PLAN" 2>/dev/null | CO_SENT=" $(co_rows_sent 2>/dev/null | tr '\n' ' ') " awk -F'\t' '
    $3 == "close" && $10 != "dropped" && index(ENVIRON["CO_SENT"], " " $1 " ") { print $1 "\t" $9 }')"
  while IFS=$'\t' read -r id files; do
    [ -n "$id" ] || continue
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      if [ "$ROOT/$e" = "$CONT" ] || [ "$DROOT/$e" = "$CONT" ]; then printf '%s' "$id"; return 0; fi
    done <<< "$(_units_files_tokens "$files")"
  done <<< "$rows"
  return 0
}
act_continuation() {
  local hh_none=no owner
  owner="$(co_cont_owner)"
  if [ -n "$owner" ]; then
    CONT_LINE="$CONT_REL is the close row $owner's to write (its Files name it) — the close writes none of it"
    return 0
  fi
  co_cont_hh_none && hh_none=yes
  act_continuation_write
  if [ "$hh_none" = yes ] && ! co_cont_hh_none; then CO_HH_CONT="$CO_HH_LINE"; fi
}
act_continuation_write() {
  local missing
  co_heard; CO_DEFER="$(co_deferrals)" || _co_refuse "$CO_UNREAD"
  CO_CARRIED="$(co_carried)" \
    || _co_refuse "could not read the deferrals this run inherited (card.sh inherited) — no continuation written"
  if [ -f "$CONT" ]; then
    # A CONTINUATION WRITTEN BEFORE THIS CLOSE-OUT KEEPS EVERY BYTE IT HAS; the deferrals the plan
    # owes are appended under their heading when it carries none, and merged into the section when it
    # does (each line once, a person's lines kept), so the debt is never dropped. The hand-holds and the
    # inherited debt follow the same road (co_cont_sections), after the Deferrals section is there.
    CONT_LINE="$CONT_REL already written — left as it stands"
    if ! co_cont_has_deferrals; then
      { printf '\n'; co_deferrals_section; } >> "$CONT" 2>/dev/null \
        || _co_refuse "could not append the deferrals to the continuation at $CONT"
      CONT_LINE="$CONT_LINE, with the ## Deferrals section appended"
    fi
    missing="$(co_cont_missing)"
    if [ -n "$missing" ]; then
      co_cont_write "## Deferrals" "$missing" lines
      CONT_LINE="$CONT_LINE, with $(co_added_phrase "$missing") added under ## Deferrals"
    fi
    co_cont_sections write
    [ -z "$CO_SEC_MSG" ] || CONT_LINE="$CONT_LINE; added $CO_SEC_MSG"
    return 0
  fi
  git -C "$ROOT" rev-parse --short "$INTEGRATION" >/dev/null 2>&1 \
    || _co_refuse "the integration branch '$INTEGRATION' has no commit to name in the continuation — no continuation written"
  mkdir -p "${CONT%/*}" 2>/dev/null
  continuation_template > "$CONT" 2>/dev/null
  [ -s "$CONT" ] || _co_refuse "could not write the continuation at $CONT"
  CONT_LINE="$CONT_REL written from the close-out template (every derivable field filled; the marks left are named below)"
}

# ─── Act 6: the epic's shipped-wave row ──────────────────────────────────────
#
# THE CLOSE WRITES NO PLAN. It prints the wave's row for the orchestrator to add to the epic plan's shipped table by an
# edit of its own, so the epic plan is the person's and the orchestrator's text alone, and the close never reads that
# table back to learn whether the row is there. The row is KEYED ON THE WAVE NUMBER, the only column that cannot be
# two things at once.

# epic_adrs_value -> the raw `adrs:` this wave's sources carry: the spec the plan's `spec:` line names
# first, the plan's own when the spec has none. Nothing when neither says anything. The spec's `adrs:` is
# paths joined by ` · `.
epic_adrs_value() {
  local specrel specfile adrs
  specrel="$(plan_frontmatter_get "$PLAN" "spec")"
  [ -n "$specrel" ] || specrel="$WAVE_SLUG.spec.md"
  specfile="$DROOT/$specrel"
  [ -f "$specfile" ] || specfile="$(find "$DROOT/specs" -name "${specrel##*/}" -type f 2>/dev/null | head -1)"
  [ -n "$specfile" ] && adrs="$(plan_frontmatter_get "$specfile" "adrs")" || adrs=""
  [ -n "$adrs" ] || adrs="$(plan_frontmatter_get "$PLAN" "adrs")"
  printf '%s\n' "$adrs"
}

# epic_adrs -> the ADR numbers this wave shipped, `040, 041`, or nothing. Each segment of the value yields
# its first `adr-<digits>`.
epic_adrs() {
  epic_adrs_value | awk '
    {
      n = split($0, seg, / · /)
      for (i = 1; i <= n; i++) {
        s = seg[i]; sub(/^.*\//, "", s)
        if (match(s, /adr-[0-9]+/)) printf "%s%s", (out++ ? ", " : ""), substr(s, RSTART + 4, RLENGTH - 4)
      }
    }'
}

# epic_adrs_cell -> the ADR cell of the epic row, exit 0: the numbers, or `—` when the sources say, in so
# many words, that the wave shipped none (`adrs: none`), or the value as written when it names an ADR by a
# path with no `adr-<n>` (the record is named, it has no number to give). Exit 1, nothing printed, when no
# source says either way. "None shipped" and "not recorded" look the same on disk, so only the first is
# written; the second refuses the row, and the refusal says which line to write.
epic_adrs_cell() {
  local raw nums word
  raw="$(epic_adrs_value)"
  nums="$(epic_adrs)"
  if [ -n "$nums" ]; then printf '%s' "$nums"; return 0; fi
  word="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$word" in
    none|"—"|-|n/a|na|n/a:*) printf '—'; return 0 ;;
    '') return 1 ;;
  esac
  printf '%s' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/ · /, /g' | tr -d '|\n'
  return 0
}

# epic_row_missing -> a sentence naming what the epic row for this wave cannot be written whole without,
# or nothing. The row is written from the plan and the merge, never marked for the orchestrator.
epic_row_missing() {
  if ! epic_adrs_cell >/dev/null; then
    printf 'the wave %s row of %s cannot be written whole: neither the spec nor the plan carries an adrs: line naming the ADRs this wave shipped (adr-<n> paths joined by " · ") — write "adrs: none" in the plan if it shipped none' "$WAVE_NUM" "${EPIC_PLAN##*/}"
    return 0
  fi
  if ! git -C "$ROOT" rev-parse --short "$(co_epic_branch)" >/dev/null 2>&1; then
    printf 'the wave %s row of %s cannot be written whole: the branch %s has no commit to name as the SHA' "$WAVE_NUM" "${EPIC_PLAN##*/}" "$(co_epic_branch)"
  fi
  return 0
}
# co_epic_branch -> the branch the epic row names: the integration branch the merge reached, or on a parked plan the
# working branch the work is kept on (wave-38 T15; AC-4.3)
co_epic_branch() { if [ "$PARKED" = yes ]; then printf '%s' "$WORKING"; else printf '%s' "$INTEGRATION"; fi; }

epic_row() {
  local spec sha adrs missing
  spec="$(plan_frontmatter_get "$PLAN" "spec")"
  spec="${spec##*/}"
  [ -n "$spec" ] || spec="$WAVE_SLUG.spec.md"
  # THE ROW IS WRITTEN WHOLE (wave-33 T8; D8). The SHA is the integration head, a fact this script holds
  # (act 1 proved the working branch reachable from it). The ADR cell is the spec's `adrs:` line, else the
  # plan's, and `—` when that line says none. A source that says nothing refuses the row, naming the
  # field, before any act (`presence_missing` asks first); there is no placeholder to complete by hand.
  # The version cell is the plan's `release:`, and `—` (the table's own empty cell) when the plan names none.
  missing="$(epic_row_missing)"
  [ -z "$missing" ] || _co_refuse "$missing"
  sha="$(git -C "$ROOT" rev-parse --short "$(co_epic_branch)" 2>/dev/null)"
  adrs="$(epic_adrs_cell)"
  # The shipped cell of a parked wave reads `parked <date>, <working branch> @ <sha>` (wave-38 T15; AC-4.3).
  printf '| %s | %s | `%s` | `%s`, `.requirements.md` | %s | %s%s, %s @ %s |\n' \
    "$WAVE_NUM" "${RELEASE:-—}" "${PLAN##*/}" "$spec" "$adrs" "$([ "$PARKED" = yes ] && printf 'parked ')" "$TODAY" "$(co_epic_branch)" "$sha"
}

# co_epic_print -> the epic's row and the one line that says the edit is the orchestrator's: this close writes no plan.
# The header of the shipped table travels with it, for an epic plan that has none yet.
EPIC_SHIPPED_HEADER='| wave | version | plan | spec / requirements | ADRs | shipped |'
co_epic_print() {
  if [ ! -f "$EPIC_PLAN" ]; then
    say "shipped-row: none — no epic.plan.md beside this plan"
    return 0
  fi
  say "shipped-row: $(epic_row)"
  say "epic-edit: add the row above to the shipped table of ${EPIC_PLAN##*/} by an edit of your own; this close writes no plan (a plan with no shipped table takes the header $EPIC_SHIPPED_HEADER and its rule line first)"
}

# ─── Act 9: the step's events ────────────────────────────────────────────────
#
# WHAT THE CLOSE GIVES ITS STEPS is written through the step's one writer (lib/proof.sh `proof_step_event`): at 8 what
# it cleaned, at 9 the delivery's words and, once the plan is archived, the archive's line. The merge and the trees are
# asked of the landing and tree events, never said again here. No field value may hold a `|` or a newline (the log's
# grammar); the writer refuses one, and the close refuses with it.

# co_delivered_words -> the delivery's words, step 9's `delivered=`: the minute and the run, the release when the plan
# names one, or where a parked run's work is kept.
co_delivered_words() {
  if [ "$PARKED" = yes ]; then
    printf 'parked on %s @ %s — %s (%s %s); the Step 8/9 tail was performed by close-out.sh without the merge act and attested against the commit gate; continuation at %s' \
      "$WORKING" "$(git -C "$ROOT" rev-parse --short "$WORKING" 2>/dev/null || printf '?')" "$PARKED_WHY" "$NOW" "$WAVE_SLUG" "$CONT_REL"
    return 0
  fi
  printf '%s %s%s — the Step 8/9 tail was performed by close-out.sh and attested against the commit gate; continuation at %s' \
    "$NOW" "$WAVE_SLUG" "${RELEASE:+ $RELEASE}" "$CONT_REL"
}

# co_close_facts -> the facts this close's acts will write, as the judgment before them carries them pending (lib/proof.sh
# `_proof_dry_step`): its step 8 with the fields it will give, the landing of each row its merge lands, and each tree it
# removes. A parked close lands and removes nothing. The wipe has not run, so its field is what the census reads now.
co_close_facts() {
  local ih id refs
  printf '8|cleanup=done|tmp-wiped=%s entries under %s (not yet wiped)|tasks-completed=%s' "$(tmp_count)" "$TMP_DIR" "$TASKS_LINE"
  [ "$PARKED" = no ] || return 0
  # A row is landed only on a merge read: with none, the judgment folds no landing, as the run would write none.
  ih="$CO_MERGE_COMMIT"
  [ -z "$ih" ] || for id in $(co_lands_rows); do printf '\npublished|row=%s|commit=%s|kind=close|by=close-out|why=merged' "$id" "$ih"; done
  refs="$(co_wt_refs)"
  co_ask reader_trees | awk -F'|' "$_READER_AWK"'{ p = line_kv("path"); sub(/\/$/, "", p); if (p != "" && p != "—") print line_kv("row") "\t" p }' \
    | while IFS=$'\t' read -r id p; do
        case "$refs" in *" refs/heads/wt/${p##*/} "*) printf '\ntree|row=%s|path=' "$id" ;; esac
      done
  return 0
}

# co_close_step8 -> the run's step 8 carries what this close cleaned. A step 8 already standing with its fields is the
# record of a close whose attestation refused after its acts ran: it is kept, since this close's wipe of what that one
# left would say less than the wipe that happened.
CO_STEP8_KEPT=no
co_close_step8() {
  local st
  st="$(co_ask reader_q_step)" || _co_refuse "$CO_UNREAD"
  case "$st" in "n=8"$'\n'*cleanup=*) CO_STEP8_KEPT=yes; return 0 ;; esac
  proof_step_event "$PLAN" 8 cleanup=done "tmp-wiped=$TMP_LINE" "tasks-completed=$TASKS_LINE" \
    || _co_refuse "what step 8 cleaned could not be appended to the run's log of $PLAN"
  st="$(co_ask reader_q_step)" || _co_refuse "$CO_UNREAD"
  case "$st" in "n=8"$'\n'*cleanup=*) ;; *) _co_refuse "step 8's fields did not land in the run's log of $PLAN" ;; esac
}

# THE DEPLOY IS ASKED BY THE GATE'S OWN QUESTIONS. Whether the plan names a target is lib/walls.sh `deploy_target_named`
# over the header's deploy_target, read by the header's one grammar, and a value is refused as empty by the gate's own
# ban, `is_placeholder_value`: both asked in a subshell that sources the gate's library, as co_matrix_settle asks it.
# A target named owes all three, written on the delivery's step; a target not named owes none, and a word given for one
# is refused as having no job here, never dropped. A question that cannot be asked refuses: the close cannot tell
# whether a deploy is owed, and a delivery that skipped it could not be taken back.
CO_TARGET=""; CO_DEPLOY_NAMED=no; CO_DEPLOY_WHY=""; CO_DEPLOY_SAYS=""
CO_DEPLOY_FIELDS=()
co_walls_ask() {  # <lib/walls.sh function> [args] -> its exit status, asked of the gate's library in a subshell; 9 when it cannot be asked
  ( bionic_need walls.sh "$1" || exit 9
    DEPLOY_TARGET="$CO_TARGET"
    "$@" )
}
co_deploy_value() {  # <deployed|verified|monitored> -> the value given for it, or nothing
  case "$1" in deployed) printf '%s' "$CO_DEPLOYED" ;; verified) printf '%s' "$CO_VERIFIED" ;; *) printf '%s' "$CO_MONITORED" ;; esac
}
co_deploy_judge() {  # -> CO_DEPLOY_WHY, why the close cannot take the deploy as given, or nothing; CO_DEPLOY_FIELDS when owed
  local k v rc miss=""
  CO_TARGET="$(plan_frontmatter_get "$PLAN" deploy_target)"
  co_walls_ask deploy_target_named; rc=$?
  case "$rc" in
    0) CO_DEPLOY_NAMED=yes ;;
    1) [ -z "$CO_DEPLOY_GIVEN" ] && return 0
       CO_DEPLOY_SAYS="deploy words given with no deploy target"
       CO_DEPLOY_WHY="the plan names no deploy target (deploy_target: ${CO_TARGET:-none}), so the words given to --${CO_DEPLOY_GIVEN// / --} have no job here: give them only for a run whose plan names the target it deployed to"
       return 0 ;;
    *) CO_DEPLOY_SAYS="the deploy question cannot be asked"
       CO_DEPLOY_WHY="the gate's deploy question (lib/walls.sh deploy_target_named) cannot be asked from $CO_LIB, so whether this run owes a deploy cannot be read"
       return 0 ;;
  esac
  for k in deployed verified monitored; do
    v="$(co_deploy_value "$k")"
    case "$v" in *[![:space:]]*) ;; *) miss="${miss:+$miss, }$k (--$k '<$(co_deploy_ask "$k")>')"; continue ;; esac
    co_walls_ask is_placeholder_value "$v"; rc=$?
    case "$rc" in
      1) CO_DEPLOY_FIELDS+=("$k=$v") ;;
      0) miss="${miss:+$miss, }$k, whose '$v' is a placeholder (--$k '<$(co_deploy_ask "$k")>')" ;;
      *) CO_DEPLOY_SAYS="the deploy question cannot be asked"
         CO_DEPLOY_WHY="the gate's placeholder ban (lib/walls.sh is_placeholder_value) cannot be asked from $CO_LIB, so the deploy's words cannot be judged"
         return 0 ;;
    esac
  done
  [ -n "$miss" ] || return 0
  CO_DEPLOY_FIELDS=()
  CO_DEPLOY_SAYS="the deploy is not answered"
  CO_DEPLOY_WHY="the plan names a deploy target (deploy_target: $CO_TARGET), and the delivery owes what was deployed, how it was verified and how it is monitored; not given: $miss"
}

# co_close_step9 -> the delivery appended at its own second, read back closed; CO_DELIVERED_AT the instant it holds. The
# three of a deploy ride the same event, so no reading of the log finds the run delivered and its deploy unanswered.
CO_DELIVERED=""; CO_DELIVERED_AT=""
co_close_step9() {
  local st
  CO_DELIVERED="$(co_delivered_words)"
  proof_step_event "$PLAN" 9 "delivered=$CO_DELIVERED" ${CO_DEPLOY_FIELDS[@]+"${CO_DEPLOY_FIELDS[@]}"} \
    || _co_refuse "the delivery could not be appended to the run's log of $PLAN"
  st="$(co_ask reader_q_step)" || _co_refuse "$CO_UNREAD"
  case "$st" in *state=delivered) ;; *) _co_refuse "the delivery did not land: the run's log of $PLAN reads it open" ;; esac
  CO_DELIVERED_AT="$(co_step9_at)" || _co_refuse "$CO_UNREAD"
}

# THE HANDOFF DOCUMENT IS THE STORE. The closed run's document goes to the run's handoff file, the one the reader's
# handoff answer names (a logged place), else the
# run's home file in the handoffs folder (lib/handoff.sh `handoff_default_of`). It is the document session-poker.sh `handoff` writes, in its shape: the kind
# line, the title, the sections in their order, the door last. Its State is the closed run's, and its two closed
# lines are `closed-form`'s, the branch line under the verb's `working branch:` label. A section a session composed
# into that document before the close is kept as it stands, title included; a section it lacks is the one line
# `- none.`. A file of the old shape (the kind line, then facts and five human lines) is carried whole: mid-flight and
# risks into Open, order into Next, rulings into Decisions, lessons into Findings, every other line into State after
# the closed run's own, a line under a key State writes itself marked `was`. The page is not folded: every reader
# joins a folded line back, so a long line reads the same. Where it was written is a fact of the run's log, given through
# the handoff's one writer (lib/proof.sh `proof_handoff_event`), and read back as every reader of it asks.
CO_HO_FILE=""; CO_HO_REL=""; CO_HO_WRITTEN=""; CO_HO_LOCAL=""; CO_HO_CLOCK=""
co_handoff_where() {  # -> sets CO_HO_FILE/REL (the pointer's path, else the default) and the instant, once
  local rel
  [ -z "$CO_HO_FILE" ] || return 0
  rel="$(co_ask reader_q_handoff 2>/dev/null | sed -n 's/^path=//p')"
  case "$rel" in '') CO_HO_FILE="$(handoff_default_of "$PLAN" "$ROOT")" ;; /*) CO_HO_FILE="$rel" ;; *) CO_HO_FILE="$ROOT/$rel" ;; esac
  CO_HO_REL="${CO_HO_FILE#"$ROOT"/}"
  CO_HO_WRITTEN="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  CO_HO_LOCAL="$(date '+%Y-%m-%d %H:%M %Z')"
  CO_HO_CLOCK="$(date '+%-I:%M %p')"
}
co_handoff_closed() {  # -> 0 when the handoff document's resume point is the closed one
  co_handoff_where
  [ -f "$CO_HO_FILE" ] || return 1
  case "$(handoff_line "$CO_HO_FILE" "resume point")" in 'resume point: NONE — DELIVERED at '*|'resume point: PARKED on '*) return 0 ;; esac
  return 1
}
co_handoff_write() {  # -> writes the closed document to the handoff file, a session's sections kept; rc 1 not written
  local src=/dev/null title="" tmp old=0
  co_handoff_where
  mkdir -p "${CO_HO_FILE%/*}" 2>/dev/null || return 1
  [ ! -L "$CO_HO_FILE" ] || return 1
  if handoff_is_one "$CO_HO_FILE" link-ok; then
    title="$(sed -n '2{/^Handoff · /p;}' "$CO_HO_FILE" 2>/dev/null)"
    src="$CO_HO_FILE"
    [ -n "$title" ] || old=1
  fi
  [ -n "$title" ] || title="Handoff · ${ROOT##*/} · $(date '+%A %-I:%M %p') · $WAVE_SLUG · closed"
  bionic_need root.sh bionic_new && bionic_new "$CO_HO_FILE.close-out" || return 1
  tmp="$BIONIC_NEW"
  {
    printf 'bionic-handoff/v1\n%s\n\n' "$title"
    CO_HO_STATE="$(printf 'written: %s\ninstant: %s\nplan: %s\n%s\nworking branch: %s\ncontinuation: %s' \
        "$CO_HO_CLOCK" "$CO_HO_WRITTEN" "${PLAN#"$ROOT"/}" "$(co_resume_point)" "$(co_branch_line | sed 's/^branch: //')" \
        "$CONT_REL")" \
      awk -v secs="$HANDOFF_SECTIONS" -v old="$old" '
        BEGIN {
          n = split(secs, h, "|"); for (i = 1; i <= n; i++) H[h[i]] = 1
          # an old-shape file: its five human lines go to the section that holds their kind of thing
          M["mid-flight"] = "Open"; M["order"] = "Next"; M["rulings"] = "Decisions"; M["lessons"] = "Findings"; M["risks"] = "Open"
          # the keys the closed State writes itself: an old line under one of them is kept, marked "was"
          K["written"] = K["instant"] = K["plan"] = K["resume point"] = K["working branch"] = K["continuation"] = 1
        }
        FNR == 1 { next }
        old {
          L[++ln] = $0; next
        }
        FNR == 2 { next }
        ($0 in H) { cur = $0; next }
        $0 == "" { cur = ""; next }
        cur != "" { B[cur] = B[cur] $0 "\n" }
        END {
          if (old) {
            if (ln > 0 && L[ln] ~ /^\/bionic:canonical-sdlc /) ln--
            for (j = 1; j <= ln; j++) {
              t = L[j]
              if (t == "") continue
              if (t ~ /^ / && mode != "") {
                if (mode == "h") { sub(/^ +/, "", t); I[tgt] = I[tgt] " " t } else X = X "\n" t
                continue
              }
              key = t; mode = "m"
              if (match(t, /^[^ :][^:]*:( |$)/)) key = substr(t, 1, RLENGTH - 1); sub(/:$/, "", key)
              if (key in M) { mode = "h"; tgt = ++nh; S[nh] = M[key]; I[nh] = "- " t; continue }
              if (key in K) t = "was " t
              X = X (X == "" ? "" : "\n") t
            }
            for (j = 1; j <= nh; j++) B[S[j]] = B[S[j]] I[j] "\n"
          }
          for (i = 1; i <= n; i++) {
            if (h[i] == "Resume") break
            print h[i]
            if (h[i] == "State") { print ENVIRON["CO_HO_STATE"]; if (X != "") print X }
            else if (B[h[i]] != "") printf "%s", B[h[i]]
            else print "- none."
            print ""
          }
          print "Resume"
        }' "$src"
    printf '/bionic:canonical-sdlc %s\n' "$CO_HO_REL"
  } >| "$tmp" 2>/dev/null && mv -f "$tmp" "$CO_HO_FILE" 2>/dev/null && return 0
  rm -f "$tmp" 2>/dev/null
  return 1
}

# co_close_handoff -> the closed handoff written, its place appended to the run's log, both read back
co_close_handoff() {
  local got
  co_handoff_write || _co_refuse "the closed handoff could not be written to $CO_HO_FILE"
  co_handoff_closed || _co_refuse "the closed form did not land in the handoff file $CO_HO_FILE"
  proof_handoff_event "$PLAN" "$CO_HO_REL" || _co_refuse "the handoff's place could not be appended to the run's log of $PLAN"
  got="$(co_ask reader_q_handoff | sed -n 's/^path=//p')" || _co_refuse "$CO_UNREAD"
  [ "$got" = "$CO_HO_REL" ] || _co_refuse "the run's log does not name the handoff at $CO_HO_REL (it names ${got:-none})"
}

# ─── The gate ────────────────────────────────────────────────────────────────

# gate_ask <plan-file> <sid> [<the facts pending, honoured for a dry session only>] -> GATE_RC, GATE_ERR (the gate's whole stderr) and GATE_LINE
# (its one refusal line) for a `git commit` judged against <plan-file>. Status 9, with
# GATE_LINE saying why, when there is no gate to ask; 0 otherwise, whatever the verdict.
#
# THE MARKER IS BOUND TO THE FILE UNDER CHECK (wave-23-fixit-1810 T12). An empty marker is
# the unbound state, whose commit-gate verdict is an announcement and exit 0, so the
# dry-run would attest nothing. The two-line shape binding.sh's bind_plan writes, with the
# plan stored directly.
#
# The environment agrees with the payload because on a real call it does: lib/session.sh
# takes the env value as primary and the payload as a witness, and a dry-run whose two
# disagreed would be answered for a session that does not exist.
#
# THE ASKS IT RAISES ARE THE RUN'S. The stand-in session is in no plan's session list, so
# `OWED_PLAN` names the plan this close-out acts for: a
# waiver the gate asks for is opened in that run's register (lib/owed.sh), where the run's
# pages read it, never in a session file nothing reads.
GATE_RC=0
GATE_ERR=""
GATE_LINE=""
gate_ask() {
  local plan="$1" sid="$2" step="${3:-}" hook marker input
  GATE_RC=9; GATE_ERR=""; GATE_LINE=""
  hook="$(plugin_root)/hooks/bash-walls.sh"
  [ -f "$hook" ] || { GATE_LINE="no bash-walls.sh at $hook"; return 9; }
  marker="$(engaged_marker_path "$ROOT" "$sid")" \
    || { GATE_LINE="could not build an engagement marker path for the dry-run"; return 9; }
  mkdir -p "${marker%/*}" 2>/dev/null
  printf 'plan=%s\nengaged_at=%s\n' "$plan" "$(iso_now)" > "$marker"
  input="$(jq -n --arg s "$sid" --arg cwd "$ROOT" \
    '{session_id: $s,
      cwd: $cwd,
      hook_event_name: "PreToolUse",
      tool_name: "Bash",
      tool_input: {command: "git commit -m close-out"},
      tool_use_id: "toolu_closeout"}')"
  GATE_ERR="$(BIONIC_DRY_STEP="$step" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$sid" OWED_PLAN="$PLAN" bash "$hook" <<< "$input" 2>&1 >/dev/null)"
  GATE_RC=$?
  rm -f "$marker"
  GATE_LINE="$(grep -m1 '^bionic: ' <<< "$GATE_ERR")"
  [ -n "$GATE_LINE" ] || GATE_LINE="$(grep -m1 '[^[:space:]]' <<< "$GATE_ERR")"
  return 0
}

# gate_dry_run -> the ATTESTATION: the gate asked, as a real session, about the run as this close left it, its step 8
# in the log and still open at 8. A refusal here is rare now that the pre-flight asked the same question first; it is
# kept because the pre-flight judged what the acts would write and this judges what they wrote.
gate_dry_run() {
  { bionic_need root.sh bionic_id && bionic_id; } || _co_refuse "no id could be made for the attestation's session — the close cannot be attested"
  gate_ask "$PLAN" "closeout-${BIONIC_ID//./-}" || _co_refuse "$GATE_LINE — the close cannot be attested"
  if [ "$GATE_RC" -eq 0 ]; then
    say "gate: ok"
    return 0
  fi
  [ -n "$GATE_ERR" ] && printf '%s\n' "$GATE_ERR"
  _co_refuse "the commit gate refused the run as this close left it (rc=$GATE_RC) — its step 8 stands in the run's log and the run is open at 8; fix what the gate names and run close-out again"
}

# ─── The pre-flight: the gate's question, asked before the first act ─────────
#
# ASKED BEFORE ANYTHING IS TOUCHED. The attestation above judges the run after the acts, and by then the
# `wt/*` branches are deleted, this session's tmp state is wiped and the continuation and epic row are written. A
# refusal the close cannot clear (a matrix, evidence or ledger fault) used to land there, on a half-closed run. So the
# same question is asked first, of the plan itself, under the close's own dry session, with the facts its acts will
# write pending (`co_close_facts`): nothing is appended and nothing is held while they are.
#
# PREFLIGHT_RC is GATE_RC, or 9 when there is no gate; PREFLIGHT_LINE is the one line to show, PREFLIGHT_ERR the gate's
# whole answer.
PREFLIGHT_RC=0
PREFLIGHT_LINE=""
PREFLIGHT_ERR=""

# co_parked_wt_line -> the worktree-removed key's value on a parked plan: nothing removed, the registered trees named
co_parked_wt_line() {
  local wt
  wt="$(wt_branches | tr '\n' ',' | sed -E 's/,$//; s/,/, /g')"
  printf 'none — parked, the work is kept%s' "${wt:+ ($wt)}"
}

# presence_missing -> the first thing a later act needs and the files do not carry, or
# nothing. It used to be a readback that fired AFTER the destructive acts (critic4 Q-1): act
# 6 appends to a `| wave |` table it never finds and then refuses because no row landed.
# That is known before the first act, so it is asked here, by presence alone.
presence_missing() {
  # A RELEASE THAT WOULD SPLIT A CELL (wave-27 T14; A-orch-28). The epic row carries `release:` in
  # its version cell, and a `|` in it gives the row a cell more than its header, so it is refused
  # here, before any act, as the plan verbs refuse a pipe in a cell.
  case "$RELEASE" in
    *'|'*) printf 'the release: field of the plan holds a | (%s), which would split the version cell of the epic row; write the release without one' "$RELEASE"; return 0 ;;
  esac
  # The row is printed whole or the close refuses before any act; the epic plan's own table is never read.
  if [ -f "$EPIC_PLAN" ]; then
    epic_row_missing
  fi
  return 0
}

# ─── The facts the run owes ──────────────────────────────────────────────────
#
# THE RUN IS CLOSED ON THE JUDGE (wave-27 T14; D3, AC-7.1). `session-poker.sh current 8` admits
# Step 8 only when lib/proof.sh `facts_state` says every fact the run owes holds at the working
# head; `run` and `check` ask the same function of the same head, the working branch's, and refuse
# the same way, so a fix landed after `current 8` is read before the tail runs. FACTS_RC is the
# judge's rc (0 covered, 1 not, 2 the plan cannot be dealt, 9 the judge could not be asked),
# FACTS_HEAD the head judged, FACTS_LINES the owed lines that do not hold, FACTS_WHY the sentence, FACTS_SAYS what it
# holds the merge on in a person's few words.
FACTS_RC=9; FACTS_HEAD=""; FACTS_LINES=""; FACTS_WHY=""; FACTS_SAYS="the run's proofs cannot be read"
facts_judge() {
  # The close judges on the run's log, never the kept facts the tick reads (lib/proof.sh `_PROOF_FRESH`).
  local out err ah ef _PROOF_FRESH=1
  if ! declare -F facts_state >/dev/null 2>&1; then
    FACTS_WHY="the proof record (lib/proof.sh) cannot be loaded from $CO_LIB, so the facts the run owes cannot be judged"
    return 0
  fi
  # THE HEAD IS THE WORKING BRANCH'S REF (wave-35 T10; AC-1.7): lib/proof.sh `proof_branch_head`, `refs/heads/<branch>`,
  # the judge's one reading of it, which `current 7` and `current 8` ask too; never a checkout's head, and never
  # whatever else git resolves the bare name to (a tag of the same name is not the branch).
  FACTS_HEAD="$(proof_branch_head "$PLAN" "$ROOT" 2>/dev/null)" || FACTS_HEAD=""
  if [ -z "$FACTS_HEAD" ]; then
    FACTS_WHY="the working branch $WORKING names no commit here, so the regression is uncovered and there is no head to judge the facts the run owes at"
    FACTS_SAYS="the working branch has no commit"
    return 0
  fi
  # THE APPROVED HEAD: whenever the plan has a row that integrates, whatever its other rows, or is in the release order
  # (lib/units.sh `units_release_asked`), the head closed is the one the newest `approved: release` line names
  # (lib/proof.sh `proof_approved_head`), or one that only prose past it follows (`proof_prose_past`), as `current 8`
  # admits it; a code commit landed after the approval is refused here, naming both heads. A plan with neither is asked
  # no approval.
  if units_release_asked "$PLAN" >/dev/null 2>&1; then
    ah="$(proof_approved_head "$PLAN" release 2>/dev/null)" || ah=""
    if [ -z "$ah" ]; then
      FACTS_RC=1
      FACTS_WHY="no approved: release line names a head, so the head the user approved for release cannot be read; the user's word for the working head $FACTS_HEAD is approve release '<reply>'"
      ! units_order "$PLAN" >/dev/null 2>&1 || FACTS_WHY="the plan is in the release order and $FACTS_WHY"
      FACTS_SAYS="the release is not approved"
      return 0
    fi
    if [ "$ah" != "$FACTS_HEAD" ] && ! proof_prose_past "$PLAN" "$ah" "$FACTS_HEAD"; then
      FACTS_RC=1
      FACTS_WHY="the working head ${FACTS_HEAD:0:12} is not the head the user approved for release, ${ah:0:12}, and a commit past it is code or a release-set file; land only docs past the approval, or have the user approve this head (approve release '<reply>')"
      FACTS_SAYS="code landed after the release approval"
      return 0
    fi
  fi
  ef=/dev/null; ! bionic_need root.sh bionic_new || ! bionic_new "$TMP_DIR/.facts-judge" || ef="$BIONIC_NEW"
  out="$(facts_state "$PLAN" "$FACTS_HEAD" 2>|"$ef")"; FACTS_RC=$?
  err=""; [ "$ef" = /dev/null ] || { err="$(cat "$ef" 2>/dev/null)"; rm -f "$ef"; }
  case "$FACTS_RC" in
    0) FACTS_WHY="" ;;
    2) FACTS_LINES="$(printf '%s\n%s' "$err" "$out" | awk 'NF')"
       FACTS_WHY="the judge could not deal this plan (facts_state exit 2), so the facts the run owes cannot be judged; what the judge said is printed with this line" ;;
    *) FACTS_RC=1
       FACTS_LINES="$(printf '%s\n' "$out" | awk -F'\t' '$NF != "covered"')"
       FACTS_WHY="the facts the run owes do not all hold at the working head $FACTS_HEAD (facts_state); record each with proof-add, or have the user waive a question"
       # A MERGE NO WHOLE RUN PROVED AT THIS HEAD carries its own exit on the judge's line: the person's word on the
       # release card, or the pass. Neither is a proof-add or a waiver, so the sentence names it.
       ah="$(printf '%s\n' "$FACTS_LINES" | awk -F'\t' '$1 == "regression" && $2 == "unproved" { print $4; exit }')"
       [ -z "$ah" ] || FACTS_WHY="$FACTS_WHY; the whole suite has not run at this head: $ah"
       FACTS_SAYS="$(co_facts_says "$FACTS_LINES")" ;;
  esac
  return 0
}

# co_facts_says <facts_state lines that do not hold> -> what the first of them holds the merge on, in a few words, and
# how many more there are: "the structure review failed, and 1 more". A review's piece and whole are one review here.
co_facts_says() {
  printf '%s\n' "$1" | awk -F'\t' '
    NF == 0 { next }
    { st = ""; for (i = 2; i <= NF; i++) if ($i ~ /^(uncovered|owed|failing|absent|unproved)$/) { st = $i; break }
      if ($1 == "review") w = "the " $2 " review"; else if ($1 == "regression") w = "the regression"
      else if ($1 == "check") w = "the release check"; else if ($1 == "debt") w = $2; else w = "a proof the run owes"
      if (w in seen) next
      seen[w] = 1; n++
      if (n > 1) next
      if ($1 == "debt") s = w " is still red"
      else if (st == "failing") s = w " failed"
      else if (st == "owed") s = w " has red suites"
      else if (st == "unproved") s = "the merge waits on your word: the whole suite has not run at this head"
      else s = w " has not run at this head" }
    END { if (n == 0) s = "the run\047s proofs do not all hold"; else if (n > 1) s = s ", and " (n - 1) " more"; print s }'
}

gate_preflight() {
  PREFLIGHT_RC=9; PREFLIGHT_LINE=""; PREFLIGHT_ERR=""
  { bionic_need root.sh bionic_id && bionic_id; } || { PREFLIGHT_LINE="no id could be made for the pre-flight's session"; return 0; }
  gate_ask "$PLAN" "closeout-preflight-${BIONIC_ID//./-}" "$(co_close_facts)"
  [ "$GATE_RC" -eq 9 ] && { PREFLIGHT_LINE="$GATE_LINE"; return 0; }
  PREFLIGHT_RC="$GATE_RC"; PREFLIGHT_LINE="$GATE_LINE"; PREFLIGHT_ERR="$GATE_ERR"
  return 0
}

# ─── Act 7: the archive ──────────────────────────────────────────────────────
#
# ITS LINES ARE COLLAPSED ONTO ONE. `archive_run` prints one line for a skip or a refusal
# and one PER MOVED TREE for a move (up to three: specs, plans, adrs). The archive's field
# is one value of one log line, so the lines are joined with `; `.
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

# co_lift_seal -> the run's seal removed, or a refusal. It stands between the delivery's event and the archive's move: the
# seal names the plan where it is, so a seal left standing would read the move of a closed run as the plan gone, and the
# lifting before the delivery would leave the delivery's own events unvouched. No home (2) is no seal to lift; the lock
# not had (75) is refused, because the move that follows would strand a seal that names a plan no longer there.
co_lift_seal() {
  local rc=0
  seal_remove "$PLAN" || rc=$?
  case "$rc" in
    0|2) return 0 ;;
    75)  _co_refuse "the run's seal could not be lifted: its lock was held (exit 75); the plan is closed and was not archived, so say the same close again once the holder is done" ;;
    *)   _co_refuse "the run's seal could not be lifted (exit $rc); the plan is closed and was not archived" ;;
  esac
}

# co_close_archived <the run's log, found before the move> -> the delivery's step restated with the archive's line.
# The archive moves the plan and never its record, so the plan's new place joins no log: the log found before the move
# is named to the step's writer, which takes only a log that is there. The restated step carries the delivery's own
# second, so every reader of when the run was delivered reads one instant; it stands after the lines written between
# the two by the log's written order. A step given again replaces the first by its number, so it restates the deploy too.
co_close_archived() {
  local log="$1" last
  LOG_AT="$CO_DELIVERED_AT" proof_step_event "$log" 9 "delivered=$CO_DELIVERED" ${CO_DEPLOY_FIELDS[@]+"${CO_DEPLOY_FIELDS[@]}"} "archived=$ARCHIVED_LINE" \
    || _co_refuse "the archive's line could not be appended to the run's log $log"
  last="$(
    reader_events() { cat "$log"; }
    reader_q_step "$PLAN" 2>/dev/null
  )"
  case $'\n'"$last" in *$'\n'archived=*) ;; *) _co_refuse "the archive's line did not land in the run's log $log" ;; esac
}

# ─── check ───────────────────────────────────────────────────────────────────
#
# A DIAGNOSIS IS NOT A FAILURE (doctor.sh's rule, applied here). `check` reports what the
# tail would do and what the gate says about the plan AS IT STANDS — which, at Step 8, is
# usually a refusal, because the block `run` is about to write is not written yet. That is
# the answer, not an error, so this verb exits 0 either way.
do_check() {
  local ws is verdict unreached branches wt_list wt_count wt_word wt_desc count missing CK_LINE CK_OWNER
  if [ "$CURRENT" = 8 ]; then
    say "step: current: 8"
  else
    co_would "step: WOULD REFUSE — $STEP_REFUSAL"
  fi
  co_deploy_judge
  if [ -n "$CO_DEPLOY_WHY" ]; then co_would "deploy: WOULD REFUSE — $CO_DEPLOY_WHY" "$CO_DEPLOY_SAYS"
  elif [ "$CO_DEPLOY_NAMED" = yes ]; then say "deploy: deployed, verified and monitored given for $CO_TARGET; run writes them on the delivery's step"
  else say "deploy: none owed — the plan names no deploy target"; fi
  MISSING="$(presence_missing)"
  [ -z "$MISSING" ] || co_would "presence: WOULD REFUSE — $MISSING" "the epic plan's row cannot be written"
  facts_judge
  if [ "$FACTS_RC" -eq 0 ]; then
    say "facts: every fact the run owes holds at $FACTS_HEAD"
  else
    co_would "facts: WOULD REFUSE — $FACTS_WHY" "$FACTS_SAYS"
    [ -z "$FACTS_LINES" ] || printf '%s\n' "$FACTS_LINES" | sed 's/^/  /'
  fi
  if [ "$PARKED" = yes ]; then
    verdict="parked ($PARKED_WHY)"
  else
    co_merge_read
    verdict="$(co_merge_verdict)"
  fi
  case "$verdict" in "WOULD REFUSE"*) co_would "merge: $verdict" "$(co_merge_holds)" ;; *) say "merge: $verdict" ;; esac
  is="$(git -C "$ROOT" rev-parse --short "$CO_MERGE_COMMIT" 2>/dev/null)"
  if [ "$PARKED" = yes ]; then say "tag: none — parked, no merge is tagged"
  else
    co_tag_merge check
    if [ "$TAG_RC" -eq 2 ]; then co_would "tag: WOULD REFUSE — $TAG_LINE" "the release tag cannot be made"; else say "tag: $TAG_LINE"; fi
  fi
  CO_LANDS="$(co_lands_rows)"
  if [ "$PARKED" = yes ]; then
    say "rows-landed: none — parked, no merge lands a row"
  elif [ -z "$CO_LANDS" ]; then
    say "rows-landed: none — no open integrate or close row"
  elif [ -n "$(co_lands_refusal "$CO_LANDS")" ]; then
    co_would "rows-landed: WOULD REFUSE — $(co_lands_refusal "$CO_LANDS")" "this session is not bound to the run"
  elif [ -z "$CO_MERGE_COMMIT" ]; then
    say "rows-landed: none — run lands $CO_LANDS only once the merge is seen"
  else
    local ck_open ck_id ck_land=""
    ck_open="$(co_lands_open "$CO_LANDS")"
    for ck_id in $CO_LANDS; do case " $ck_open " in *" $ck_id "*) ;; *) ck_land="$ck_land${ck_land:+ }$ck_id" ;; esac; done
    say "rows-landed: run would land $(co_lands_said "$ck_land" "$ck_open" "$CO_MERGE_REF @ ${is:-?}")"
  fi

  # THE CENSUS NAMES ITS SOURCE, NOT JUST ITS RESULT (D5). `wt_branches` reads the
  # register now — no scoped glob to report — so the line instead says how many
  # `## Tasks` rows it found trees for, a number a reader can check against the plan
  # by eye. Zero registered trees is the conservative failure and says so BY NAME
  # rather than printing an empty list a reader could mistake for a scan that found
  # nothing to scan.
  wt_list="$(wt_branches)"
  wt_count="$(printf '%s\n' "$wt_list" | grep -c '[^[:space:]]')"
  unreached=""
  [ "$PARKED" = yes ] || unreached="$(wt_unreached)"
  branches="$(printf '%s' "$wt_list" | tr '\n' ' ' | sed -E 's/[[:space:]]+$//')"
  wt_word="tree"; [ "$wt_count" = 1 ] || wt_word="trees"
  if [ "$wt_count" -eq 0 ]; then
    wt_desc="census: no registered trees"
  else
    wt_desc="${branches} (${wt_count} registered ${wt_word})"
  fi
  if [ "$PARKED" = yes ]; then
    say "worktree-removed: $(co_parked_wt_line)"
  elif [ -n "$unreached" ]; then
    co_would "worktree-removed: ${wt_desc} WOULD REFUSE — $(printf '%s' "$unreached" | tr '\n' ' ' | sed -E 's/[[:space:]]+$//') carries a commit $WORKING never took" \
      "a branch holds commits the run never took"
  else
    say "worktree-removed: ${wt_desc}"
  fi
  co_reviews_prepare check
  say "reviews: $CO_RV_LINE"

  co_orphans check
  co_hand_holds
  say "$CO_HH_LINE"
  co_governed
  say "$CO_GOV_LINES"
  count="$(tmp_count)"
  say "tmp-wiped: $count entries under $TMP_DIR"
  say "tasks-completed: $TASKS_LINE"
  say "$(co_debt_card)"
  CO_DEBT_BAD="$(co_debt_refusal)" || _co_refuse "$CO_UNREAD"
  [ -z "$CO_DEBT_BAD" ] || co_would "debt-lines: WOULD REFUSE — $CO_DEBT_BAD" "a carried debt line does not parse"
  CK_OWNER="$(co_cont_owner)"
  if [ -n "$CK_OWNER" ]; then
    say "continuation: $CONT_REL is the close row $CK_OWNER's to write (its Files name it) — run writes none of it"
  elif [ -f "$CONT" ]; then
    if ! co_cont_has_deferrals; then
      CK_LINE="continuation: $CONT_REL already written — run appends the ## Deferrals section"
    else
      CO_CARRIED="$(co_carried)" \
        || _co_refuse "could not read the deferrals this run inherited (card.sh inherited)"
      CO_DEFER="$(co_deferrals)" || _co_refuse "$CO_UNREAD"
      missing="$(co_cont_missing)"
      if [ -n "$missing" ]; then
        CK_LINE="continuation: $CONT_REL already written — run adds $(co_added_phrase "$missing") under ## Deferrals: $(co_added_ids "$missing")"
      else
        CK_LINE="continuation: $CONT_REL already written — left as it stands"
      fi
    fi
    co_cont_sections check
    say "$CK_LINE${CO_SEC_MSG:+; run also adds $CO_SEC_MSG}"
  else
    say "continuation: $CONT_REL would be written from the close-out template"
  fi
  if [ -f "$EPIC_PLAN" ] && [ -n "$(epic_row_missing)" ]; then
    co_would "shipped-row: WOULD REFUSE — $(epic_row_missing)" "the epic plan's row cannot be written"
  else
    co_epic_print
  fi
  co_handoff_where
  if [ "$PARKED" = yes ]; then
    say "handoff: would write the closed form ($(co_resume_point)) to $CO_HO_REL; the run's log would name it"
    say "archived: not asked — the run is parked, not delivered; its plan stays where it is"
  else
    say "handoff: would write the closed form (resume point NONE) to $CO_HO_REL; the run's log would name it"
    # THE ARCHIVE IS NAMED, NEVER ASKED. `archive_run` has no dry mode and this verb has no
    # licence to move anything, so `check` reports the destination the binding fixed and
    # leaves the verdict to `run`, which asks once the plan reads closed.
    say "archived: archive_run would be asked for $PLANS_DIR into $(archive_root "$ROOT") once the plan reads closed"
  fi

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
  { bionic_need root.sh bionic_id && bionic_id; } || { say "gate: skipped — no id could be made for the check's session"; return 0; }
  gate_ask "$PLAN" "closeout-check-${BIONIC_ID//./-}" || { say "gate: skipped — $GATE_LINE"; return 0; }
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
    co_would "gate: WOULD REFUSE before the gate is asked — $PREFLIGHT_LINE" "the commit gate would refuse the closed plan"
  else
    co_would "gate: WOULD REFUSE the plan run would write (rc=$PREFLIGHT_RC): $PREFLIGHT_LINE" "the commit gate would refuse the closed plan"
  fi
  return 0
}

# ─── run ─────────────────────────────────────────────────────────────────────

do_run() {
  # NOTHING IS TOUCHED UNTIL ALL TEN OF THESE PASS, in this order: the step `run` closes, nobody out on a row of the
  # run (co_rows_out), the deploy the plan owes (co_deploy_judge), the presence check (a `| wave |` table, a release
  # with no `|`), every debt line the
  # continuation carries parsing (co_debt_refusal), this session bound to the plan when it has rows the merge lands
  # (co_lands_refusal), the merge verdict (act 1 is a readback and touches nothing), the branch census, the facts the
  # run owes (`facts_judge`), and the gate's answer about the plan `run` will write. Any refusal leaves every branch,
  # every tmp entry, the plan and the epic plan exactly as they were.
  [ "$CURRENT" = 8 ] || _co_refuse "$STEP_REFUSAL"
  co_rows_out
  co_deploy_judge
  [ -z "$CO_DEPLOY_WHY" ] || _co_held "$CO_DEPLOY_SAYS" "$CO_DEPLOY_WHY — nothing was done"
  MISSING="$(presence_missing)"
  [ -z "$MISSING" ] || _co_held "the epic plan's row cannot be written" "$MISSING — nothing was done"
  # A DEBT LINE THAT WOULD NOT PARSE IS REFUSED HERE, NAMED (wave-36 T13; AC-7.8), never carried.
  CO_DEBT_BAD="$(co_debt_refusal)" || _co_refuse "$CO_UNREAD"
  [ -z "$CO_DEBT_BAD" ] || _co_held "a carried debt line does not parse" "$CO_DEBT_BAD — nothing was done"
  # THE ROWS THE MERGE LANDS NEED THIS SESSION BOUND TO THIS PLAN (wave-36 T14; AC-7.7), asked before any act.
  # A PARKED PLAN IS CLOSED WITHOUT THE MERGE ACT (wave-38 T15; AC-4.3): no rows a merge lands, no merge readback, and
  # no branch census, because nothing is deleted.
  CO_LANDS=""
  if [ "$PARKED" = no ]; then
    CO_LANDS="$(co_lands_rows)"
    CO_LANDS_BAD="$(co_lands_refusal "$CO_LANDS")"
    [ -z "$CO_LANDS_BAD" ] || _co_held "this session is not bound to the run" "$CO_LANDS_BAD — nothing was done"
    act_merge
    refuse_unreached
  fi
  facts_judge
  if [ "$FACTS_RC" -ne 0 ]; then
    [ -n "$FACTS_LINES" ] && printf '%s\n' "$FACTS_LINES"
    _co_held "$FACTS_SAYS" "$FACTS_WHY — nothing was done"
  fi
  gate_preflight
  [ "$PREFLIGHT_RC" -eq 9 ] && _co_held "the commit gate would refuse the closed plan" "$PREFLIGHT_LINE — nothing was done"
  if [ "$PREFLIGHT_RC" -ne 0 ]; then
    [ -n "$PREFLIGHT_ERR" ] && printf '%s\n' "$PREFLIGHT_ERR"
    _co_held "the commit gate would refuse the closed plan" \
      "the commit gate would refuse the plan this run would write (rc=$PREFLIGHT_RC) — nothing was done: no branch deleted, no tmp wiped, no continuation or epic row written"
  fi
                    say "preflight: the commit gate allows the plan this run will write"
  co_reviews_prepare run || _co_held "the release entry's reviews cannot be rendered" "$CO_RV_LINE — nothing was done"
  # THE PART IS PUBLISHED BEFORE THE MERGE READBACK. The branch moves to the part's commit first, so the readback reads the
  # branch the person is asked to merge: a part that main does not hold is a part the release entry lies about, and a run
  # whose part close-out itself rendered holds at the readback until that tip is merged. The normal path has the integrate row
  # publish the part before its merge, so nothing is rendered here and the readback is unmoved.
  co_reviews_publish || _co_held "the release entry's reviews are not published" "$CO_RV_LINE"
                    say "reviews: $CO_RV_LINE"
  if [ "$PARKED" = yes ]; then
    MERGE_LINE="$(co_parked_merge_line)"; say "merge: $MERGE_LINE"
    LANDS_LINE="none — parked, no merge lands a row"; say "rows-landed: $LANDS_LINE"
    WT_LINE="$(co_parked_wt_line)"; say "worktree-removed: $WT_LINE"
  else
    act_merge;      say "merge: $MERGE_LINE"
    co_tag_merge run; say "tag: $TAG_LINE"
    act_lands "$CO_LANDS"; say "rows-landed: $LANDS_LINE"
    act_worktrees;  say "worktree-removed: $WT_LINE"
  fi
  co_orphans run
  co_governed;      say "$CO_GOV_LINES"
  # Read before act_tmp wipes the rosters it counts: the continuation's `## Scorecard` prints this reading.
  co_scorecard
  act_tmp;          say "tmp-wiped: $TMP_LINE"
                    say "tasks-completed: $TASKS_LINE"
                    say "$(co_debt_card)"
  # The close's instant, read again here: the continuation, the epic row, the delivery's words and the handoff
  # carry it, and `delivered:` ends the hand-holds window, so every act above (the merge, the landings, the wipe) is
  # inside the minute it names or before it.
  NOW="$(date -u +%Y-%m-%dT%H:%MZ)"
  act_continuation; say "continuation: $CONT_LINE"
                    say "$(co_owed_line)"
  co_epic_print
  # ORDER: step 8's event -> the attestation -> step 9's. The attestation judges the run while it is
  # still OPEN at 8; delivering first would close it, and the gate checks no evidence of a closed run. A refusal here
  # leaves step 8 standing in the log with what the close cleaned, and no delivery.
  co_close_step8
  if [ "$CO_STEP8_KEPT" = yes ]; then say "step8: the step 8 standing in the run's log is kept, attested-by close-out.sh $VERSION"
  else                say "step8: CLOSED $NOW, attested-by close-out.sh $VERSION"; fi
  gate_dry_run
  co_close_step9
  co_close_handoff
  co_hand_holds_last; say "$CO_HH_LINE"
  co_matrix_settle; [ -z "$CO_MX_LINES" ] || say "$CO_MX_LINES"
  co_hold_release
  if [ "$PARKED" = yes ]; then
    # A PARKED RUN IS NOT ARCHIVED AND SENDS NO DELIVERY NOTICE: its plan is where the resume reads it (wave-38 T15).
                    say "handoff: the closed form ($(co_resume_point)) written to $CO_HO_REL; the run's log names it"
                    say "step9: delivered: parked on $WORKING @ $(git -C "$ROOT" rev-parse --short "$WORKING" 2>/dev/null) — $PARKED_WHY"
                    say "archived: not asked — the run is parked, not delivered; its plan stays where it is"
  else
                    say "handoff: the closed form (resume point NONE) written to $CO_HO_REL; the run's log names it"
                    say "step9: delivered: $NOW $WAVE_SLUG${RELEASE:+ $RELEASE}"
    CO_LOG="$(reader_log "$PLAN" 2>/dev/null)" || _co_refuse "the run's log of $PLAN cannot be found, so the archive's line has nowhere to go; nothing was moved"
    co_lift_seal
    act_archive
    co_close_archived "$CO_LOG"
                    say "archived: $ARCHIVED_LINE"
    co_deliver_notice
  fi
  act_disengage
}

# THE DELIVERY CALLS THE PERSON (wave-33 T12; REQ-2 AC-2.3, D2). A run that reached `delivered:` and
# was archived opens one item on this session's ledger, `delivered:<run>`, sends it at least once through the
# one sender and closes it: it is news, not a need, so nothing stays owed. Only when a channel is
# declared, so a machine without one writes no ledger and prints what 1.15.0 printed; silent either
# way, and never fatal, so no send can change this script's output or its exit code. A second `run`
# says `already closed` and never reaches here, which keeps the notice from being opened twice. With no session
# id (a hand-run script) there is no ledger to key it on and nothing is sent.
co_deliver_notice() {
  local key
  declare -F owed_open >/dev/null 2>&1 || return 0
  declare -F notify_declared >/dev/null 2>&1 || return 0
  notify_declared || return 0
  key="delivered:$(printf '%s' "$WAVE_SLUG" | tr -c 'A-Za-z0-9._-' '-')"
  OWED_ROOT="$ROOT" OWED_SID="$CO_SID" owed_open "$key" "delivered: $WAVE_SLUG" \
    "close-out: step9: delivered: $NOW $WAVE_SLUG${RELEASE:+ $RELEASE}" >/dev/null 2>&1 || return 0
  OWED_ROOT="$ROOT" OWED_SID="$CO_SID" owed_send delivered: >/dev/null 2>&1
  OWED_ROOT="$ROOT" OWED_SID="$CO_SID" owed_close "$key" delivered >/dev/null 2>&1
  return 0
}

case "$VERB" in
  run)   do_run ;;
  check) do_check; [ -z "$CO_HOLD_WHY" ] || co_hold "${CO_HOLD_SAYS:-close-out stopped}" "close-out check: $CO_HOLD_WHY" ;;
esac
exit 0
