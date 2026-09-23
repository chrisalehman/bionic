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
# Attestation filename is per-session (design D-5, task 4/2):
#     .bionic/tmp/preflight-<this session's session_id>.state
# A foreign session's attestation — however fresh — simply is not this file, so it is
# never read at all; only THIS session's own filename is ever consulted, and the legacy
# shared .bionic/tmp/preflight.state slot is not consulted either.
#
# FAIL DIRECTIONS (TDD §7, pinned by tests/dispatch-preflight.test.sh):
#   - not an Agent-tool call                            -> pass, silent  (A7 relevance hoist)
#   - cwd/repo unresolvable                              -> pass, silent (ambiguity)
#   - no active wave                                     -> pass, silent (nothing to decide)
#   - payload carries no session_id, or one that is not
#     shaped like one (anything outside [A-Za-z0-9_-])    -> pass, silent (§7 table: start=open)
#   - attestation present and keyed to THIS session_id    -> pass, silent
#   - attestation missing, unreadable, symlinked, or
#     keyed to a different session (foreign)              -> AUTO-RUN the probe, then
#     (the combined preflight, epic-16 wave-02 R5)           pass on what it finds
#   - the auto-run probe REFUSES                          -> REFUSE, quoting the probe
#     (the environment is genuinely broken; fail closed)     and naming the fix command
#   - brief declares no deliverable in a canonical label   -> REFUSE, naming the
#     and carries no waiver (the absent-deliverable wall)      label to add and the waiver
#   - brief declares a deliverable only as a <slot>        -> REFUSE (no fill): a slot is
#     template (epic-16 wave-02 R1, inference withdrawn)       not a concrete path; name it
#   - brief names MORE THAN ONE path under its             -> REFUSE, naming every
#     deliverable label (the ambiguity wall, R7/R6-1)          candidate: name exactly one
#   - brief declares a deliverable that resolves OUTSIDE   -> REFUSE, naming the
#     the repo root (the containment wall, review S-2)        path and where it lands
#
# TWO ROOTS THIS FILE NEVER RE-DERIVES (epic-16 wave-02 R9): the project root comes
# from the library's `project_root` (the nearest real `.bionic` ancestor, with a linked
# worktree mapped onto its main repository first — never the worktree or the shell's
# cwd), and every state path hangs off it, so the probe on the other side of the
# combined preflight writes where this gate reads.
#
# Exit code 2 = block the tool call entirely in Claude Code hooks.
# [WALL: tests/dispatch-preflight.test.sh]
#
# Registered ONCE, in hooks/hooks.json, for both the main thread and agent contexts.
# It used to be registered twice — once here and once in the governing skill's
# frontmatter — because the skill channel is the only one a main-thread payload
# reaches and the settings channel the only one an agent context reaches, so the pair
# was a partition rather than a duplicate. What scopes it now is an on-disk fact:
# `session_run` (which was `active_run` until wave-session-bound-run made run identity
# per-session) under the payload's project root. A partition maintained by hand was
# one edit away from covering one channel twice and the other not at all.

set -uo pipefail

# THIS SCRIPT'S OWN DIRECTORY, and therefore its siblings'. Every bionic hook and every
# script a hook invokes ships in one directory, so `$0` resolves the neighbour identically
# in a repo checkout, in a bootstrap-installed ~/.claude/hooks/, and in an installed plugin
# payload. Deliberately NOT ${CLAUDE_PLUGIN_ROOT}: the harness runs this gate straight out
# of the repo, where no plugin is mounted and that variable does not exist.
HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -n "$HOOK_DIR" ] || HOOK_DIR="$(dirname "$0")"

# The fix line a refusal hands an operator. Absolute, so it runs from any cwd (checklist A1)
# — which is what the installed-path spelling used to buy, now bought without the literal.
PREFLIGHT_CMD="bash ${HOOK_DIR}/preflight-probe.sh"

BIONIC_INPUT=$(cat)
_jq() { printf '%s' "$BIONIC_INPUT" | jq -r "$1 // empty" 2>/dev/null; }

# ---------- relevance first (checklist A7): the cheapest possible check,
# before any git resolution or plan-directory walk. Anything that isn't a
# subagent dispatch is none of this gate's business. ----------
TOOL_NAME=$(_jq '.tool_name')
[ "$TOOL_NAME" = "Agent" ] || exit 0

# A GIT TOPLEVEL IS NO LONGER THE PRECONDITION (bionic 1.4.0, spec AC-12, Decision A2).
# It used to be: `git rev-parse --show-toplevel` had to succeed or the wall exited
# silently. That made the wall's coverage a property of the SHELL's cwd rather than of
# the project — dispatch from a non-git directory that nonetheless sits under a real
# `.bionic` root and every wall in this file went quiet, arming and containment
# included. The precondition is now the project itself: `project_root` finds the
# nearest real `.bionic` ancestor (mapping a linked worktree onto its main repository
# first), and `session_run` (which was `active_run` until wave-session-bound-run made run
# identity per-session) decides whether there is anything to protect.

# ---------- the library ----------
#
# One loader idiom, byte-identical in every hook (spec AC-16); its source of truth is
# payload/scripts/lib/loader.sh. FAIL OPEN: this wall protects a dispatch, and a
# dispatch that should have been refused can be stopped and re-run — refusing every
# Agent call on the machine because a file is missing cannot be undone as cheaply.
# `cmd-class.sh` (wave-20 T4; REQ-7, D7) carries CMD_RUN_NORM_AWK, the one run normaliser the
# lift's `collapse()` pastes in — a declared run is stored by the rule the writer-side
# budget arm reads a claim with.
BIONIC_LIB_WANT="context.sh refuse.sh root.sh run.sh session.sh patrol.sh agents.sh roster.sh units.sh cmd-class.sh"
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
if [ -n "$BIONIC_LIB_MISSING" ]; then loader_fail_open "dispatch-preflight"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/context.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/refuse.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/patrol.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/agents.sh"
# The `roster-state/v1` row has one writer, and it is `roster_row` here, not the format
# string this hook used to carry (spec AC-25, design ledger D3).
# shellcheck source=/dev/null
. "$BIONIC_LIB/roster.sh"
# THE PLAN'S `## Tasks` LEDGER HAS ONE READER TOO (wave-15 REQ-5, D7). The floor-once wall
# at the bottom of this file asks whether any step-4 row is still open, and it asks
# `units_rows` — the library epic-23 wave-11 built to be the only parser of that table.
# A second split in this hook is the exact defect REQ-1e removed from the evidence gate.
# shellcheck source=/dev/null
. "$BIONIC_LIB/units.sh"
# ONE RUN RULE ON BOTH SIDES OF THE ROW (wave-20 T4; REQ-7, D7). The lift's `collapse()`
# runs `cmdnorm_run` out of CMD_RUN_NORM_AWK before a declared run is stored, the rule the
# writer-side budget arm builds its claim with. The library only defines functions and
# that one variable, so sourcing it costs a parse and nothing else.
# shellcheck source=/dev/null
. "$BIONIC_LIB/cmd-class.sh"

# THE RUN VERDICT IS ASKED FOR (epic-23 wave-14 REQ-4, spec D5). `bionic_context`
# computes it only for a caller that sets this, because the plan scan behind it is
# the preamble's most expensive value and most hooks never read the answer. This gate reads it at
# :291-292 to scope itself to the bound run.
BIONIC_CONTEXT_WANT_RUN=1

# ---------- THE ROOT AND THE SESSION KEY, from one call ----------
#
# THE ROOT (spec AC-10). Every path this gate owns hangs off the answer: the
# attestation it reads, the roster it appends, the containment wall it measures
# deliverables against. A worktree that answered with its own tree would write an
# attestation the probe on the other side of the combined preflight then could not
# find — `project_root` maps a linked worktree back onto its main repository, so both
# sides land in one address space. On an ordinary checkout nothing changes.
#
# THE SESSION KEY comes back from the same call, ABOVE THE RUN PREDICATE since
# task-engaged-session, because the engagement switch below is keyed to it and that
# switch is this gate's FIRST scoping decision.
#
# Payload missing its session key: the §7 fail-direction table names that exact
# ambiguity and pins the start-side direction as open, silent — we cannot prove whose
# dispatch this is, so we cannot refuse it as foreign. The same direction holds for a
# key that is not SHAPED like one. Every state path this gate reads or writes is built
# by interpolating this value — preflight-<sid>.state, roster-<sid>.state — and the
# symlink guards below check $STATE_DIR and those exact filenames, so a key carrying a
# path separator leaves the guarded directory entirely rather than tripping a guard
# (Step-6 review S-4). `bionic_context` applies that rule now, for all fifteen, and
# returns 1 on either ambiguity; this gate spells both as the same silent pass.
bionic_context 2>/dev/null || exit 0
[ -d "$BIONIC_ROOT" ] || exit 0


# ---------- THE ENGAGEMENT SWITCH — asked before anything else ----------
#
# task-engaged-session: bionic's walls are the RUN's, not the repo's, and a run is entered
# by invoking canonical-sdlc. A session that never did is a bystander here and must not see
# a refusal, an advisory, or a state write from this hook. `engaged_session` (lib/run.sh) is
# true only for a REGULAR file at `.bionic/tmp/engaged-<sid>.state`; every unreadable state —
# absent, symlink, foreign sid, `unknown` — reads as NOT engaged. Silent, exit 0: the
# direction §7 gives every start-side ambiguity, and here it is the consent boundary itself
# (1.3.2 close-out ruling — the arming partition IS the consent boundary).
[ "$BIONIC_ENGAGED" = 1 ] || exit 0

# ---------- THE RUN PREDICATE (AC-7, AC-8) — now DATA, not scope ----------
#
# One reader for "is there a run to protect": lib/run.sh's `session_run` (which was
# `active_run` until wave-session-bound-run made run identity per-session), true while the
# plan THIS SESSION is bound to — or, unbound, the newest plan carrying `## SDLC State` —
# has `current:` below 9, or 9 with no `delivered:` Step-9 line, and no `abandoned:`
# frontmatter line. This was a hand-copied block —
# resolve_docs_root, has_sdlc_state, a newest-.md walk and a `current:` parse — restated
# in five hooks and held together by an agreement suite that could only prove they had
# not drifted YET. One of them drifting was not hypothetical: a marker-less .md winning
# the newest race disarmed this very wall repo-wide for ~15 minutes on 2026-08-15
# (record/session-20260815-landing-supervision/t8-forensic-read.md).
#
# IT NO LONGER DECIDES WHETHER THIS GATE ACTS — engagement does (above). An engaged
# session's Step 0 precedes its plan, and its walls are owed from the first dispatch, so an
# empty PLAN skips only the arms that MEASURE against a plan. Exactly one does: the budget
# wall, which reads `parallel-budget:` out of this file. Every other wall here — the
# attestation, the Patrol checkpoint, the lease, the ambiguity/containment/absent-deliverable
# trio, the roster — is plan-free and runs unchanged (AC-23).
#
# wave-session-bound-run S5: `active_run` (no session input, newest-plan only) is now
# `session_run` (lib/run.sh) — the caller's OWN bound plan when one exists, the same
# newest-plan fallback when it does not. A BOUND session is gated on that plan alone,
# whatever else is open in the root (AC-1); UNBOUND behaves exactly as before, and this
# gate says so once on its advisory channel (AC-3); bound to a plan that has since
# closed is treated as having no open run at all (AC-6) — the same PLAN="" arm this
# code already took for "no run".
PLAN="$BIONIC_RUN_PLAN"
case "$BIONIC_RUN_WORD" in
  bound-open) : ;;
  fallback)
    echo "dispatch-preflight: run resolved by newest-plan fallback (session unbound) — $PLAN" >&2
    ;;
  bound-closed)
    echo "dispatch-preflight: bound plan closed — $PLAN; this session has no open run" >&2
    PLAN=""
    ;;
  bound-unreadable)
    # (wave-20 T1, REQ-2, D2; AC-2.3.) Named, never "no open run", and REFUSED below as a
    # pooled finding: approval and the budget are both read out of this plan, and a dispatch
    # admitted against a plan nobody can read is the same fail-open the commit gate closes.
    echo "dispatch-preflight: bound plan unreadable — $PLAN" >&2
    DP_PLAN_UNREADABLE="$PLAN"
    PLAN=""
    ;;
  none|*)
    PLAN=""
    ;;
esac
[ -n "$PLAN" ] && [ -f "$PLAN" ] || PLAN=""

# ---------- this session is engaged: this IS a decision ----------

deny() {  # <reason line>...
  # THE FRAME KEEPS ITS PARAMETERS AND LOSES ITS VOICE (task 13, D-1). Its fixed
  # headline and its Fix line are `detail` now; the caller passes the ruled fact and fix.
  local fact="$1" fix="$2"; shift 2
  local reasons="" line
  for line in "$@"; do reasons="${reasons}${line}
"; done
  refuse exit2 dispatch "$fact" "$fix" "${reasons}
This subagent start needs a working environment, and a wave is active.

Fix: ${PREFLIGHT_CMD}
Then retry the dispatch."
}

STATE_FILE="$BIONIC_ROOT/.bionic/tmp/preflight-${BIONIC_SID}.state"

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
# are the same three.
#
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
attested() {
  [ ! -L "$BIONIC_ROOT/.bionic" ] && [ ! -L "$BIONIC_ROOT/.bionic/tmp" ] \
    && [ ! -L "$STATE_FILE" ] && [ -f "$STATE_FILE" ] || return 1
  local sid
  sid=$(grep -m1 '^session_id=' "$STATE_FILE" 2>/dev/null | cut -d= -f2-)
  [ -n "$sid" ] && [ "$sid" = "$BIONIC_SID" ]
}

# ================================ THE FINDINGS LIST, DECLARED BEFORE THE FIRST ARM (D3)
#
# WHY IT IS UP HERE. Every wall below this line records into it, and the first of them —
# the arming wall — is two hundred lines above where this list used to be declared. It was
# declared beside the brief-shape arms because they were the only callers; wave-14 REQ-8
# made the state arms callers too, so the declaration moves to the top of the range it
# serves. The SPENDING point has not moved up with it: `dp_refuse_findings` is defined
# beside the scaffold it renders and called once, below the last arm and above the journal.
#
# WHAT IS ABOVE IT, AND STAYS ABOVE IT. The attestation arm (the combined preflight, next
# section) refuses where it stands, first and alone. A repo that cannot be written, or a
# redirected state directory, makes every later disk read meaningless — the roster, the
# stamp, the plan, the transcript are all read out of the tree that arm is checking — so a
# list that mixed its verdict with theirs would be reporting facts it had just been told
# not to trust. Relevance, the loader, the root and the engagement switch are above it for
# the same kind of reason and are not refusals at all.
DP_FINDING_N=0
DP_FAULT_LINES=""
DP_NOTCHECKED=""
DP_FIRST_FACT=""
DP_FIRST_FIX=""
DP_FIRST_DETAIL=""

# dp_finding <fact> <fix> <detail> — record one fault. NEVER exits.
#
# THE FIRST FAULT CONTRIBUTES NO LINE OF ITS OWN, and that is the line budget in one
# sentence (AC-8.3). `refuse` renders the first fault as the user line — `bionic: dispatch
# refused — <fact> (<fix>)` — at the top of the model's wire, so a list that repeated it
# would spend a line saying what the reader just read. Faults two and up cost exactly one
# line each, in the same `<fact> (<fix>)` shape, which is what "one line per additional
# fault" means and what tests/dispatch-preflight.test.sh §three-arms measures.
#
# THE `<detail>` OF EVERY FAULT IS STILL PASSED and still carried, because a LONE fault
# refuses in its arm's own words with its own detail block — byte for byte what that arm
# emitted before this list existed. It is the SEVERAL-fault wire that drops the details:
# a reader with three faults met three lectures before a single fix (wave-13, D11).
dp_finding() {  # <fact> <fix> <detail> — record one fault. NEVER exits.
  DP_FINDING_N=$((DP_FINDING_N + 1))
  if [ "$DP_FINDING_N" -eq 1 ]; then
    DP_FIRST_FACT="$1"; DP_FIRST_FIX="$2"; DP_FIRST_DETAIL="$3"
    return 0
  fi
  DP_FAULT_LINES="${DP_FAULT_LINES}$1 ($2)
"
}

# THE UNREADABLE BOUND PLAN, the first finding (wave-20 T1, REQ-2, D2). Resolved at the run
# predicate above, recorded here because this is where the pool starts.
if [ -n "${DP_PLAN_UNREADABLE:-}" ]; then
  dp_finding "the bound plan cannot be read" "restore read access to the plan" \
    "The plan this session is bound to exists and cannot be read: ${DP_PLAN_UNREADABLE}
Approval and the writer budget are read out of it, so neither can be measured. It is not
closed and not gone, so no other plan is read in its place.
Fix: restore read access (chmod u+r on the plan, u+rx on its folder), then dispatch."
fi

# dp_not_checked <arm> <what it needs> — record that an arm could not be evaluated (AC-8.2).
#
# AN ARM WHOSE INPUT IS ANOTHER ARM'S PRODUCT CANNOT ANSWER, and the failure this records is
# the arm going QUIET about it: the author fixes every fault named, dispatches again, and
# meets a refusal from a wall that was standing there the whole time unable to speak. The
# line says which wall and what it is waiting for, so a second refusal is expected rather
# than a surprise. Its shape is the one the budget wall's per-field reading already uses.
#
# THESE LINES RIDE THE SEVERAL-FAULT WIRE ONLY (A-T6.1). A one-fault refusal keeps its arm's
# own detail byte-identical — wave-13 pins that verbatim — and an author holding one fault
# gets the dependent arm's verdict on the very next attempt anyway.
dp_not_checked() {  # <arm> <what it needs>
  DP_NOTCHECKED="${DP_NOTCHECKED}not checked: $1, needs $2
"
}

# ==================================================== THE COMBINED PREFLIGHT
# (epic-16 wave-02, R5/AC-4; Synthesis field report §3.)
#
# WHAT THIS REPLACED. Every branch above used to end in `deny`, and the fix it
# named was a command the operator ran by hand: refused, run the probe, retry,
# dispatch. Five serialized minutes between deciding to dispatch and the agent
# existing, paid per session and again after every /clear — which re-fires the
# this-session demand mid-wave, when nothing about the machine has changed.
#
# THE ASYMMETRY THAT MAKES IT SAFE. A missing attestation is not evidence of a
# broken environment; it is the absence of evidence either way, and the way to
# turn an absent fact into a present one is to go and read it. That costs a second
# and cannot go stale, which is the whole argument against carrying a claim across
# sessions. So an absent, foreign, or unreadable attestation AUTO-RUNS the probe
# and the dispatch proceeds on what it finds.
#
# BLOCKING SURVIVES IN EXACTLY ONE PLACE ON THIS PATH: the probe REFUSING. That is
# a positive finding — no credential, an unwritable repo, an unwritable or
# redirected state directory — and it is the finding a fleet dies of collectively.
# Fail closed on it. The hostile-repo posture is unchanged and now enforced by the
# producer rather than restated here: the probe refuses on a symlinked `.bionic`,
# `.bionic/tmp`, or attestation path, so a repo can still CLOSE this wall and
# still cannot OPEN it — the planted content is never read, before or after.
if ! attested; then
  # The probe next to this script, so a test drives the real producer and an
  # installed gate finds its installed sibling. `$0` is the gate's own path on
  # both, and it is the lane that is expected to resolve on every machine: both
  # registration channels point at ONE tree, and a script's siblings are in it.
  # The config-dir form is a residual second lane for an exotic invocation, and
  # it is worth less every day — after the Step-9 legacy teardown there are no
  # hooks under `${CLAUDE_CONFIG_DIR}/hooks/` on a plugin-only machine at all.
  # Which is exactly why the miss below is a DENY and not a skip (critic C-2).
  PROBE_SCRIPT="${HOOK_DIR}/preflight-probe.sh"
  [ -f "$PROBE_SCRIPT" ] || PROBE_SCRIPT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/preflight-probe.sh"

  if [ ! -f "$PROBE_SCRIPT" ]; then
    deny "this repo has no environment attestation" "run the preflight probe" \
      "No environment attestation was found for this repo, and the probe that writes one" \
         "could not be located (looked beside this gate and under the Claude config directory)."
  fi

  # Run it AT THE PINNED ROOT and with THIS dispatch's session key, rather than
  # letting it inherit the shell. Both are the Synthesis field case read directly:
  # the attestation that had to be redone was taken against a root derived from the
  # working directory, and an attestation keyed to anything but the session whose
  # dispatch this is would be one this gate then refuses to read.
  PROBE_OUT=$(cd "$BIONIC_ROOT" 2>/dev/null && CLAUDE_CODE_SESSION_ID="$BIONIC_SID" \
                bash "$PROBE_SCRIPT" 2>&1)
  PROBE_ST=$?

  if [ "$PROBE_ST" -ne 0 ] || ! attested; then
    # The probe's own words, not a paraphrase of them: it is the component that
    # knows WHICH check failed, and an operator handed "something went wrong" has
    # to run it again by hand to learn anything. Indented so the quotation is
    # visibly the probe speaking.
    {
      refuse exit2 dispatch "the environment check ran and did not pass" "fix what the probe named" \
        "The check was run automatically for this session and did not pass:
$(printf '%s\n' "$PROBE_OUT" | sed 's/^/    /')

A fleet inherits this environment and dies collectively if it is wrong.
Fix the failure above, then retry the dispatch (or re-run by hand: ${PREFLIGHT_CMD})."
    }
  fi

  # Announced, never silent. §4 bans printing CHECK DETAIL on the allow path; this
  # is not detail, it is the gate reporting an action it took on the operator's
  # behalf — the same class as the roster's absence warning, and the operator has
  # to be able to see that a probe ran without being asked.
  printf 'dispatch-preflight: no this-session attestation was present; the environment check was run automatically and passed (%s)\n' \
    "$STATE_FILE" >&2
fi

# ============================================================== THE ARMING WALL
# (epic-17 wave-05, spec AC-6; design ledger D-C, ratified 2026-08-19.)
#
# WHAT THIS ASKS THAT NOTHING ELSE DOES. Every wall above decides whether the dispatch is
# well-formed and whether the environment it inherits is sound. This one asks whether
# anything is WATCHING. The Patrol is the run's one clock — armed at engagement, ticking the
# poker, surfacing rows that have gone past their declared duration — and a fleet launched
# under a Patrol that was never armed, or that was armed and has silently stopped firing,
# dies quiet: no notify, no landing verdict read by anyone, nothing until a human wanders
# back. The failure is measured, repeatedly, across epic-16 and epic-17.
#
# THE STAMP IS THE SIGNAL. hooks/session-poker.sh writes .bionic/tmp/patrol-<sid>.state on
# `arm` and on every `tick` BEFORE it decides anything, so the file's age measures firings
# LANDING rather than decisions succeeding. Two states refuse here and they are named
# separately, because the operator does something different about each: ABSENT is a Patrol
# that was never armed (arm it), and older than 2x the poker-interval is one that was armed
# and has died (re-arm it, and find out why the clock stopped).
#
# SCOPE IS THE PREDICATE ALREADY ABOVE — no second definition of "active". Outside a wave
# this script exited hundreds of lines ago; a dispatch reaching this point is by
# construction one the run is accountable for. The wall sits after the attestation gate on
# purpose: a broken environment is the more urgent finding, and reporting "no Patrol" to an
# operator whose repo is unwritable would name the second problem first.
#
# THE INTERVAL IS THE POKER'S OWN, obtained by invoking its `interval` verb rather than by
# re-reading `poker-interval:` here. One knob, one reader. When that read fails — no poker
# beside this gate, a malformed override the poker itself refuses — the gate has an
# AMBIGUITY rather than a finding, and takes the direction §7 assigns every start-side
# ambiguity: say so on stderr and let the dispatch through. A wall that refused because it
# could not measure would be a new failure mode, not a safety property.
#
# HONEST LIMIT, inherited from the stamp: this attests that Patrol firings are landing. It
# cannot see the CLI's cron table, so a job deleted seconds ago still looks alive for up to
# 2x the interval. That window is the price of measuring the thing that actually matters.

STATE_DIR="$BIONIC_ROOT/.bionic/tmp"
PATROL_STAMP_FILE="$STATE_DIR/patrol-${BIONIC_SID}.state"

# The poker beside this gate, so a test drives the real one and an installed gate finds its
# installed sibling — the same resolution, and the same residual config-dir second lane, the
# probe above already uses, and for the same reason: the two registration channels serve ONE
# tree, so the sibling lane is the one that answers.
#
# WHERE THIS ONE DIFFERS FROM THE PROBE'S (critic C-2, W5): a missing probe DENIES, and a
# missing poker used to skip the arming wall in silence — so on a machine where the legacy
# `${CLAUDE_CONFIG_DIR}/hooks/` copies are gone and the sibling lane somehow missed too, a
# teardown would have quietly bought a disarmed wall. The arms below now degrade per-arm
# instead: the never-armed half needs no poker at all and still refuses, and the staleness
# half says out loud that it did not run.
POKER_SCRIPT="${HOOK_DIR}/session-poker.sh"
[ -f "$POKER_SCRIPT" ] || POKER_SCRIPT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/session-poker.sh"

# THE TWO ARMS HAVE DIFFERENT REMEDIES, so the Fix block is an argument rather than a
# constant in the frame (wave-12 T2, spec D4).
#
# NEVER ARMED asks for one act and it is the CronCreate. The stamp is not a hand step any
# more: hooks/engage.sh runs `session-poker.sh arm` itself, with the session id and the
# project root it already holds, immediately after writing the engagement marker (T4). A
# refusal that still ordered `session-poker.sh arm` would be telling the model to do work
# the machine has already been given — principle P-A at its own wall — and would teach the
# hand step back into the next brief that quotes it.
#
# ARMED AND STOPPED FIRING is the other half and keeps both: the clock is what died, the
# stamp is stale rather than absent, and re-engaging is not what an operator does about a
# cron job that stopped. `arm` is offered there because a fresh stamp is what proves the
# revived clock is landing.
PATROL_FIX_NEVER="Fix: CronCreate a RECURRING session job at the interval \`bash ${POKER_SCRIPT} interval\`
  reports, carrying the patrol prompt (skills/canonical-sdlc/SKILL.md §Dispatch). That is the
  one half this model owns. The stamp is the other half and it is written for you:
  hooks/engage.sh arms it as the session engages canonical-sdlc, so a session that engaged
  has one. Engage the skill again in this session if it is still missing."

PATROL_FIX_STOPPED="Fix: re-arm the Patrol — look first, then the clock, then the stamp:
  1. CronList — is this session's Patrol job still listed?
  2. ONLY IF it is ABSENT: CronCreate a RECURRING session job at the interval
     \`bash ${POKER_SCRIPT} interval\` reports, carrying the patrol prompt
     (skills/canonical-sdlc/SKILL.md §Dispatch).
  3. bash ${POKER_SCRIPT} arm"

# RECORDS, NEVER EXITS (wave-14 REQ-8, D3). The frame is unchanged down to the byte — a
# lone Patrol fault still refuses on `exit2` with exactly this text, because that is what
# `dp_refuse_findings` does with a list of one. What changed is that a dispatch with an
# unarmed Patrol AND a full budget AND a broken label now learns all three at once.
patrol_deny() {  # <fact> <fix> <fix-block> <state line>...
  local fact="$1" fix="$2" fixblock="$3"; shift 3
  local reasons="" line
  for line in "$@"; do reasons="${reasons}${line}
"; done
  dp_finding "$fact" "$fix" "${reasons}
A dispatch with no Patrol behind it is an agent nobody is waiting on.

${fixblock}

Then retry the dispatch."
}

# THE INTERVAL IS A THRESHOLD, NOT A PRECONDITION (critic C-2, W5). This block used to
# skip BOTH arms when the interval could not be read — so one unparseable line in
# `.bionic/config.yaml`, a file that is machine-local and agent-writable, disabled the
# whole wall. That contradicts §8 twenty lines below in this same script: a hostile repo
# may CLOSE a wall and must never be able to OPEN one. And the line that gets you there is
# the likeliest typo available — a BARE NUMBER (`poker-interval: 30`) makes the poker
# refuse, where `30m` and `30 minutes` both parse.
#
# Only the STALENESS arm needs a number. An absent stamp is absent at every interval, so
# that arm runs unconditionally now. For staleness, an unreadable config falls back to the
# poker's own POKER_INTERVAL_DEFAULT — asked for through its read-only `interval-default`
# verb rather than retyped here, because two copies of that constant drift the first time
# either moves and the gate would then be measuring against a threshold nobody configured.
PATROL_INTERVAL=""
PATROL_INTERVAL_SOURCE=configured
if [ -f "$POKER_SCRIPT" ]; then
  PATROL_INTERVAL=$( cd "$BIONIC_ROOT" 2>/dev/null && bash "$POKER_SCRIPT" interval 2>/dev/null )
  case "$PATROL_INTERVAL" in
    ''|*[!0-9]*) PATROL_INTERVAL="" ;;
  esac
  if [ -z "$PATROL_INTERVAL" ] || [ "$PATROL_INTERVAL" -le 0 ]; then
    PATROL_INTERVAL=$( bash "$POKER_SCRIPT" interval-default 2>/dev/null )
    case "$PATROL_INTERVAL" in
      ''|*[!0-9]*) PATROL_INTERVAL="" ;;
    esac
    PATROL_INTERVAL_SOURCE=default
    echo "dispatch-preflight: the Patrol interval could not be read from this project's config — interval unreadable, wall ran at default (${PATROL_INTERVAL:-none}s)." >&2
  fi
fi

# A symlink is not a stamp. The directory levels were discharged by the attestation gate
# above (it refuses outright on a symlinked `.bionic` or `.bionic/tmp`, and the probe it
# runs refuses on the same three), so only the file's own path is checked here — the same
# split the roster append below makes, and for the same reason (§8): a hostile repo may
# CLOSE this wall and must never be able to OPEN it.
#
# UNCONDITIONAL, and that is the C-2 fix in one word: this arm asks whether anything armed
# the Patrol, a question with no threshold in it.
PATROL_STAMPED=1
if [ -L "$PATROL_STAMP_FILE" ] || [ ! -f "$PATROL_STAMP_FILE" ]; then
  PATROL_STAMPED=0
  patrol_deny "no Patrol stamp exists for this session" "CronCreate the Patrol job" \
    "$PATROL_FIX_NEVER" \
    "There is no Patrol stamp for this session at:" \
    "    ${PATROL_STAMP_FILE}" \
    "The Patrol was never armed on this session (a symbolic link at that path is never" \
    "followed and reads the same way), so nothing is watching the fleet this dispatch joins."
fi

# The staleness half. Its threshold may be the project's or the poker's default; what it
# may never be is silently absent, so the one case with no number at all — the poker
# unreachable on BOTH lanes, which is what a machine looks like once the legacy
# `${CLAUDE_CONFIG_DIR}/hooks/` copies are torn down and the sibling lane misses too —
# says which half did not run rather than letting the whole wall go quiet.
# THE STALENESS HALF NEEDS A STAMP TO AGE. Until REQ-8 the never-armed arm above exited,
# so reaching here meant the file was there; it records and carries on now, and a `stat` of
# a file that is not there would print "the stamp's age could not be read" as though
# something had gone wrong with a stamp nobody ever wrote. Absent is absent, once.
if [ "$PATROL_STAMPED" = "0" ]; then
  :
elif [ -z "$PATROL_INTERVAL" ] || [ "$PATROL_INTERVAL" -le 0 ]; then
  echo "dispatch-preflight: no Patrol interval could be obtained (${POKER_SCRIPT} is not readable on either lane); the staleness half of the arming wall did not run, though the never-armed half did." >&2
else
  # THE THRESHOLD IS THE LIBRARY'S FIRE WINDOW (epic-23 wave-15 REQ-1, ADR-028). It was
  # the interval times the library's stale multiplier — twice the interval, a judgment call
  # held in a shared constant because it was written out at three sites. It is not a multiplier at all
  # now: one FIRE WINDOW is the longest idle span in which a session cron is guaranteed one
  # opportunity to fire, the interval plus the scheduler's jitter, and `patrol_fire_window`
  # is the one place that arithmetic lives. Past it the stamp is worth asking the
  # transcript about; it is not, on its own, a finding.
  PATROL_WINDOW="$(patrol_fire_window "$PATROL_INTERVAL")" || PATROL_WINDOW=""
  case "$PATROL_INTERVAL_SOURCE" in
    default) PATROL_INTERVAL_WORDS="the poker's ${PATROL_INTERVAL}s default interval (this project's configured value could not be read)" ;;
    *)       PATROL_INTERVAL_WORDS="the ${PATROL_INTERVAL}s poker-interval this project configures" ;;
  esac

  PATROL_MTIME=$(stat -f %m "$PATROL_STAMP_FILE" 2>/dev/null \
                 || stat -c %Y "$PATROL_STAMP_FILE" 2>/dev/null)
  case "$PATROL_MTIME" in
    ''|*[!0-9]*)
      echo "dispatch-preflight: the Patrol stamp's age could not be read (${PATROL_STAMP_FILE}); the staleness half of the arming wall did not run." >&2
      ;;
    *)
      PATROL_AGE=$(( $(date -u +%s) - PATROL_MTIME ))
      [ "$PATROL_AGE" -lt 0 ] && PATROL_AGE=0
      if [ -n "$PATROL_WINDOW" ] && [ "$PATROL_AGE" -gt "$PATROL_WINDOW" ]; then
        # ---------- the verdict: idle time, never wall time ----------
        #
        # A SESSION CRON FIRES ONLY WHILE THE SESSION IS IDLE, so a stamp past the window
        # says one of two things and its age cannot tell them apart: the job is gone, or
        # the orchestrator has been working. This wall is hit MID-TURN by construction —
        # a dispatch happens inside a busy turn — which makes it the likeliest of the two
        # blocking readers to meet a healthy session with a stale stamp, and on
        # 2026-09-15 that is exactly what it refused.
        #
        # `patrol_verdict` (lib/patrol.sh) answers the observable question off the
        # transcript this hook is already handed: has an idle stretch long enough for one
        # firing passed since the last proof of life, with no firing in it. Only `dead`
        # denies. `busy` and `unreadable` say what they found on stderr and let the
        # dispatch through, because a wall that cannot observe the thing it refuses on
        # does not refuse (ADR-028).
        PATROL_VLINE="$(patrol_verdict "$PATROL_STAMP_FILE" "$(_jq '.transcript_path')" "$PATROL_INTERVAL")"
        PATROL_VERDICT="$(_patrol_field "$PATROL_VLINE" verdict)"
        PATROL_GAP="$(_patrol_field "$PATROL_VLINE" gap)"
        PATROL_WHY="$(_patrol_field "$PATROL_VLINE" reason)"
        case "$PATROL_VERDICT" in
          dead)
            patrol_deny "the Patrol was armed and stopped firing" "re-arm the Patrol, both halves" \
              "$PATROL_FIX_STOPPED" \
              "The Patrol was armed on this session and has stopped firing." \
              "Its last stamp is ${PATROL_AGE}s old, and this session has since sat idle for" \
              "${PATROL_GAP}s in one stretch with no tick in it — past the ${PATROL_WINDOW}s fire window," \
              "which is ${PATROL_INTERVAL_WORDS} plus the scheduler's jitter:" \
              "    ${PATROL_STAMP_FILE}"
            ;;
          busy)
            echo "dispatch-preflight: the Patrol stamp is ${PATROL_AGE}s old, but this session has been busy — its longest idle gap since the stamp is ${PATROL_GAP}s, under the ${PATROL_WINDOW}s fire window, so the clock has had no opportunity to fire and its silence proves nothing." >&2
            ;;
          *)
            echo "dispatch-preflight: the Patrol stamp is ${PATROL_AGE}s old and this session's idle time could not be read (${PATROL_WHY:-no reason given}); the staleness half of the arming wall reached no verdict." >&2
            ;;
        esac
      fi
      ;;
  esac
fi

# ========================================= THE APPROVAL CHECKPOINT (epic-22 K2, AC-K2.4)
#
# A WRITER IS THE FIRST IRREVERSIBLE ACT OF A PLAN. Steps 0-3 produce documents the user
# can read and reject; Step 4 produces commits on a branch, in parallel, by agents that do
# not come back to ask. Design decision 2 of the wave-01-plugin-only interview put one
# fact between those two worlds — the plan's `approved-by:` line, written on the user's
# LITERAL `approved` and on nothing else — and this is the dispatch-side half of it. The
# evidence-gate half refuses the COMMIT; this one refuses the writer that would produce it,
# which is the half that arrives first and the only one that can stop the work being done.
#
# THE READ-ONLY SET PASSES; EVERY OTHER TYPE IS A WRITER (wave-20 T7, REQ-9 AC-9.1). Until
# 1.8.7 this arm named the two bionic writer roles and let everything else through, so a
# `fork`, a `general-purpose` or a `claude` agent — each of which can write the tree — was
# admitted on a plan nobody had approved (triage-B D2a, driven). The class is now an
# allow-list, asked of `role_is_readonly` (payload/scripts/lib/roster.sh): the four bionic
# read-only roles and the harness's `Explore` and `Plan`. Researchers, test-runners, auditors
# and critics still dispatch before approval as a matter of course — the research that
# informs the plan is exactly that dispatch — and an empty or unknown type is a writer.
#
# BEFORE APPROVAL, AT EVERY STEP. This arm used to be inert below Step 4 ("the plan is still
# being authored"). A writer launched at Step 2 builds against a plan nobody has seen exactly
# as one at Step 4 does, and the rule the spec states is "before Step-3 approval only these
# dispatch" (D9). So the arm reads the one fact that decides it — `approved-by:` — and
# `current:` only to name the step in the refusal. A task-scale plan (`current: T<n>`) binds
# the same way it always did.
#
# INERT WITHOUT A PLAN. An engaged session with no plan on disk has no approval to be
# missing; the arm takes the same direction the budget ceiling's does.
#
# WHY IT SITS HERE, after the Patrol checkpoint and before the roster: the roster below is
# a LEDGER, and a launch this gate is about to refuse must not be journalled as though it
# happened.
# [WALL: tests/dispatch-preflight.test.sh]
DP_SUBAGENT=$(_jq '.tool_input.subagent_type')
if ! role_is_readonly "$DP_SUBAGENT" && [ -n "$PLAN" ]; then
  # `current:` and `approved-by:` out of `## SDLC State`, in one pass each, fence-blind
  # on purpose: this arm reads two keys, and the gate that owns the section's grammar is
  # the evidence gate. A key this reader cannot find reads as absent, never as malformed.
  DP_CURRENT=$(awk '
    /^## SDLC State/ { st = 1; next }
    st && /^## / { exit }
    st && /^[[:space:]]*current[[:space:]]*:/ {
      sub(/^[[:space:]]*current[[:space:]]*:[[:space:]]*/, ""); gsub(/[[:space:]]/, "");
      print; exit }
  ' "$PLAN" 2>/dev/null) || DP_CURRENT=""
  DP_APPROVED=$(awk '
    /^## SDLC State/ { st = 1; next }
    st && /^## / { exit }
    st && /^[[:space:]]*approved-by[[:space:]]*:/ {
      sub(/^[[:space:]]*approved-by[[:space:]]*:[[:space:]]*/, "");
      sub(/[[:space:]]+$/, ""); print; exit }
  ' "$PLAN" 2>/dev/null) || DP_APPROVED=""
  if [ -z "$DP_APPROVED" ]; then
    dp_finding "the plan this writer builds is unapproved" "get the Step-3 plan approved" \
      "Role: ${DP_SUBAGENT:-(none given, so general-purpose)}
Plan: ${PLAN}
Step: ${DP_CURRENT:-(unreadable)} — writers run against an APPROVED plan, and nothing recorded one.

A writer is the first act of a plan that cannot be taken back by closing a file. Before
approval only a read-only role dispatches: ${ROLE_READONLY_SET}.

Fix: put the Step-3 card to the user and wait for the literal word 'approved'; then
     record it under '## SDLC State' in the plan above:
       approved-by: <user> <ISO-UTC> \"<verbatim reply>\"
     Silence, a question, or a partial reply is never transcribed as approval.

Then retry the dispatch."
  fi
fi

# ======================================= ONE LEVEL OF DELEGATION (wave-20 T7, AC-9.4)
# (spec D9 and its Writer-origin invariant; design ledger Δ11 as amended by Δ12.)
#
# ONLY THE ORCHESTRATOR DISPATCHES WRITERS. A dispatch made from inside a subagent — a
# payload carrying a top-level `agent_id` (t1-probe-report §3), or `agent_type`, or the
# guard's channel variable: `is_agent_context` below — may launch a read-only role and
# nothing else. The read-only roles' own files disallow the Agent tool (agents-src), so the
# longest chain there is is orchestrator → writer → read-only helper: every writer is
# rostered, contracted and dispatched by the orchestrator. Before Δ12 nothing bounded the
# depth, and the consumer wave that reported it ran orchestrator → implementor → fork →
# dispatch, with the nested rows accreting onto the orchestrator's roster.
#
# is_agent_context — defined HERE, above its first caller, because bash resolves a function
# at the call. Three spellings mark an agent context and any one is enough:
#   * `.agent_id` — the harness's own marker, present only when the hook fires inside a
#     subagent (the Bash walls' ARM C and hooks/stop-guard.sh read the same field). The
#     dependable one: measured on a nested PreToolUse|Agent payload.
#   * `.agent_type` — also set in a dispatched agent's payload.
#   * BIONIC_HOOK_CHANNEL=agent-context — the settings-channel guard's marker. No
#     registration hands it to THIS hook today (hooks.json runs the guard on SubagentStop
#     only), so it is kept as one spelling of three, never the one the journal relies on.
is_agent_context() {
  [ -n "$(_jq '.agent_id')" ] && return 0
  [ -n "$(_jq '.agent_type')" ] && return 0
  [ "${BIONIC_HOOK_CHANNEL:-}" = "agent-context" ] && return 0
  return 1
}
# [WALL: tests/dispatch-preflight.test.sh]
if is_agent_context && ! role_is_readonly "$DP_SUBAGENT"; then
  dp_finding "a subagent may launch only read-only roles" "ask the orchestrator" \
    "Type: ${DP_SUBAGENT:-(none given, so general-purpose)}
Caller: $(_jq '.agent_id')${BIONIC_HOOK_CHANNEL:+ (channel ${BIONIC_HOOK_CHANNEL})} $(_jq '.agent_type')

Only the orchestrator dispatches writers. A dispatch made from inside an agent may launch
one of: ${ROLE_READONLY_SET} — and those cannot launch further.

Fix: launch a read-only role for the help you need, or report back and let the
     orchestrator dispatch the writer on its own roster."
fi

# ================================================================== THE ROSTER
# (design D-5 + spec §Design "Roster"; task 4/3 — the LAUNCH half of AC-1.)
#
# The attestation gate has decided. Everything below is a LEDGER — it appends one
# row describing the launch that is about to happen — with exactly ONE exception,
# marked as such where it sits: the absent-deliverable wall (user-directed,
# post-wave-04). Apart from that field, starts fail open (TDD §7), so every
# failure here — an unwritable directory, a hostile path, a brief missing its
# duration or progress path — warns and lets the dispatch through. A gate that
# refused a dispatch because it could not JOURNAL it would be a new failure mode,
# not a safety property; refusing one that gave itself nothing to be checked
# against is the property the wave was built to have.
#
# WHY THIS LIVES IN THE START GATE and not in a fresh hook: the row must exist
# BEFORE the agent does. PostToolUse fires after the spawn, and the epic's whole
# warrant is that an orchestrator's memory of what it launched is the thing that
# fails. Task 4/4 completes the row from the tool response (full agent id,
# status `confirmed`); `tool_use_id` below is the key it correlates on.
#
# On printing: §4 forbids this gate from printing on the ALLOW path, and that
# still holds for its verdict — a pass says nothing. The absence warning is not
# the verdict; it is the roster reporting that a brief arrived malformed, which
# the wave design ratified as "warns and records absence" (spec §Component
# boundaries). A contract-complete brief — the ordinary case — is silent, which
# is what keeps the §7 positive-pair row ("pass in silence") true in
# tests/fail-direction-table.test.sh.
#
# Schema roster-state/v1 — one `#` header line plus one line per row, each
# `<version>|key=value|...`, read BY KEY and never by position (checklist A6),
# mirroring the observation record in hooks/stop-guard.sh so both machine
# artifacts in .bionic/tmp/ parse the same way. Per-session filename from birth
# (D-5): .bionic/tmp/roster-<session_id>.state.
#
# wave-session-bound-run S5 (spec §Roster attribution, AC-2): the row's LAST
# field is `plan=<the dispatching session's bound plan>` or the literal
# `plan=none` when unbound. This is the BINDING (lib/run.sh's `session_plan`),
# never the fallback-resolved run above — a session bound to a since-closed
# plan still gets `plan=<that plan>` here, so `adopt`'s partition (S6) can tell
# "this session's own run" from "no binding at all" without re-deriving either.

# ONE OWNER OF THE VERSION, and it is the library that writes the row it labels
# (`ROSTER_SCHEMA_VERSION`, payload/scripts/lib/roster.sh). Kept under this name because
# the READER below (`status=intended` rows, :830) and the file header both spell it this
# way, and a version the writer and the reader could disagree about is the whole reason
# the constant is not written twice.
ROSTER_VERSION="$ROSTER_SCHEMA_VERSION"
ROSTER_PREFIX="roster-"
ROSTER_SUFFIX=".state"
# STATE_DIR is set above, at the arming wall — the first thing on this path to need it.
ROSTER_FILE="$STATE_DIR/${ROSTER_PREFIX}${BIONIC_SID}${ROSTER_SUFFIX}"

# The sweeper's own ledger, named the way ROSTER_FILE is and for the same reason: a reader
# copy of `hooks/session-sweeper.sh`'s `LEDGER_SCHEMA` prefix (`sweeper-`, :341), spelled
# once here rather than at the one site that reads it. Only the budget wall below reads it,
# and only when the live panel has gone dark.
ACK_LEDGER_FILE="$STATE_DIR/sweeper-${BIONIC_SID}.state"

# ─── THE ROSTER'S OPEN NAMES — ONE PREDICATE, EVERY READER ─────────────────────────────
#
# WHO ASKS. The budget wall below counts the run's open rows on a dark panel; the
# name-in-flight arm further down asks whether ONE name is still under an open contract. Both
# ask `roster_open_names` (payload/scripts/lib/roster.sh; epic-23 wave-20 T2, D10) — the one
# close predicate the sweeper's `acked=`, the stop wall's occupancy and the tick's
# `adopt_fold` ask too. Until this wave this file carried its own reading, `dp_roster_contracts`,
# which closed a name on a `landing-swept/v1|state=MET` marker as well as on an ack; no other
# reader agreed, so this wall admitted a dispatch into a slot the stop wall still counted
# held (triage-C claim 4, driven). The ack is the one terminal state of a name (ADR-034 d1):
# a name is closed only by an ack taken AFTER its latest live launch, so a name re-dispatched
# after its ack is open again, and an unreadable stamp on either side closes nothing.

# ============================================ THE LEASE WALL AND THE BUDGET WALL
# (spec AC-14 and AC-26; plan task WALLS; assumptions WALLS/2, WALLS/3, WALLS/4, WALLS/6.)
#
# TWO REFUSALS BELOW THE LEDGER'S HEADER, and the section comment above is written for
# the append rather than for these: both sit here because both read the roster path or
# refuse before the row is written, and neither is a journalling failure. Everything
# from `warn()` down is still the fail-open ledger that comment describes.
#
# An agent context passes both — `is_agent_context`, defined at the delegation arm above,
# where its three spellings are listed. A writer dispatched INTO a tree works there by
# construction, and its own read-only helpers are launched from there.

# ---------- the lease wall: an orchestrator dispatching from a writer's tree ----------
#
# A spawned worktree is LEASED to the writer it was spawned for (design ledger C1). The
# roster this dispatch would be journalled to hangs off the MAIN checkout — project_root
# maps a linked worktree back onto its main repository, which is the whole reason the
# attestation and the ledger land in one address space — so a main-thread dispatch made
# from inside a tree is ledgered in one place by an author working in another, and the
# tree's own lease has no row that accounts for the orchestrator sitting in it.
#
# THE TEST FOR "LINKED WORKTREE" IS THE ONE scripts/lib/worktree.sh's land verb USES: a
# linked worktree's `.git` is a FILE pointing into the shared repository, the main
# checkout's is a directory. One spelling of that distinction, not two.
#
# AMBIGUITY PASSES, per §7. If the tree's main repository cannot be resolved, or the
# project root is the tree itself (a tree carrying its own `.bionic` is its own project,
# not a lease of this one), this wall has no main checkout to name and says nothing.
if ! is_agent_context; then
  LEASE_TOP=$(git -C "$BIONIC_CWD" rev-parse --show-toplevel 2>/dev/null) || LEASE_TOP=""
  if [ -n "$LEASE_TOP" ] && [ -f "$LEASE_TOP/.git" ]; then
    LEASE_TOP=$( cd "$LEASE_TOP" 2>/dev/null && pwd -P ) || LEASE_TOP=""
  else
    LEASE_TOP=""
  fi
  if [ -n "$LEASE_TOP" ] && [ "$LEASE_TOP" != "$BIONIC_ROOT" ]; then
    # `--path-format=absolute` needs git >= 2.31; the second arm resolves a relative
    # answer against the tree, exactly as lib/root.sh's own walk does.
    LEASE_COMMON=$(git -C "$LEASE_TOP" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || LEASE_COMMON=""
    if [ -z "$LEASE_COMMON" ]; then
      LEASE_COMMON=$(git -C "$LEASE_TOP" rev-parse --git-common-dir 2>/dev/null) || LEASE_COMMON=""
      case "$LEASE_COMMON" in ""|/*) ;; *) LEASE_COMMON="$LEASE_TOP/$LEASE_COMMON" ;; esac
    fi
    LEASE_MAIN=""
    [ -n "$LEASE_COMMON" ] && LEASE_MAIN=$( cd "$LEASE_COMMON/.." 2>/dev/null && pwd -P )
    if [ -n "$LEASE_MAIN" ] && [ "$LEASE_MAIN" != "$LEASE_TOP" ]; then
      dp_finding "this dispatch came from a worktree" "dispatch from the main checkout" \
        "    cwd:           ${BIONIC_CWD}
    worktree:      ${LEASE_TOP}
    main checkout: ${LEASE_MAIN}

A spawned tree is leased to the writer it was spawned for, and dispatch authority sits
with the main checkout: the roster this dispatch would be journalled to hangs off
${LEASE_MAIN}, so a dispatch made here is recorded in one address space by an author
working in another, and the tree's lease carries no row accounting for the orchestrator.

Fix: dispatch from ${LEASE_MAIN}. A dispatched agent working in its own tree may dispatch
from there — this refusal is the main thread's alone."
    fi
  fi
fi

# ---------- the budget wall: the run's parallel ceiling ----------
#
# Step 0 probes the machine and writes ONE string into the plan's frontmatter —
# `parallel-budget: writers=N suites=N worktrees=N test_jobs=N source=…` — byte-identical
# to the `budget=` value the preflight attestation records (L-RESOURCES/2). This wall
# reads that string and never re-derives it: there is one owner of the numbers and it is
# not here.
#
# INERT WITHOUT THE LINE, which is the property that matters most: every plan written
# before this wave, and every project that never ran Step 0's probe, dispatches exactly
# as it did. A budget is a ceiling a run OPTS INTO.
#
# THE LEADING FRONTMATTER BLOCK ONLY. A `parallel-budget:` inside the plan body is prose
# — this wave's own plan quotes the header in a task description — and a wall that read
# it would take a quotation for configuration.
#
# THE ONE PLAN-BOUND ARM OF THIS GATE (task-engaged-session, AC-23). The ceiling is a
# property of the run, declared in its plan, so an engaged session with no plan on disk
# yet has no ceiling to be over and this wall stays silent — while every plan-free wall
# above and below it fires. The read is guarded rather than left to awk's empty-filename
# error, so the skip is a decision this file states, not a side effect of a failed open.
#
# THE ONE BUDGET READER (epic-23 wave-20 T2, D10). `plan_budget_line` and `budget_field` in
# payload/scripts/lib/run.sh are the reading the tick, the stop wall and the governing-skill
# hook take too: the strict `parallel-budget:` line of the leading frontmatter, and one whole
# field as a decimal integer. A field that is absent or not an integer leaves its own arm
# unmeasured rather than refusing on a question this wall cannot answer — the §7 direction
# every start-side ambiguity takes — and says so once.
PARALLEL_BUDGET=""
[ -n "$PLAN" ] && PARALLEL_BUDGET="$(plan_budget_line "$PLAN")"

# NO LINE ON A LIVE PLAN IS NAMED, NEVER PASSED IN SILENCE (REQ-10 AC-10.2; ADR-035). The
# budget is a measurement every plan carries — the governing-skill hook refuses a plan Write
# without `writers=` — so a plan past Step 3 reaching here without a readable one slipped
# past that wall, by a later hand edit or a spelling no reader takes. Nothing is refused on
# it: with no ceiling there is nothing to be over, and the dispatch goes ahead. It is SAID,
# on the pass path (one WARN line) and on the refusal wire (AC-8.2's not-checked line), the
# backstop the stop wall names at turn end. Below Step 4 a plan is still being written and
# nothing is owed yet — the stop wall's own boundary (fill_ledger_live, past Step 3). A
# `current: T<n>` is a task-scale plan, past Step 3 by the approval arm's rule.
DP_BUDGET_WRITERS=""; DP_BUDGET_NAMED=""
[ -n "$PARALLEL_BUDGET" ] && DP_BUDGET_WRITERS="$(budget_field "$PARALLEL_BUDGET" writers)"
if [ -n "$PLAN" ] && [ -z "$DP_BUDGET_WRITERS" ]; then
  DP_BUDGET_CURRENT=$(awk '
    /^## SDLC State/ { st = 1; next }
    st && /^## / { exit }
    st && /^[[:space:]]*current[[:space:]]*:/ {
      sub(/^[[:space:]]*current[[:space:]]*:[[:space:]]*/, ""); gsub(/[[:space:]]/, "");
      print; exit }
  ' "$PLAN" 2>/dev/null) || DP_BUDGET_CURRENT=""
  case "$DP_BUDGET_CURRENT" in
    T[0-9]*) DP_BUDGET_STEP=4 ;;
    *) DP_BUDGET_STEP="${DP_BUDGET_CURRENT%%[!0-9]*}" ;;
  esac
  case "$DP_BUDGET_STEP" in ''|*[!0-9]*) DP_BUDGET_STEP="" ;; esac
  if [ -n "$DP_BUDGET_STEP" ] && [ "$DP_BUDGET_STEP" -ge 4 ]; then
    printf 'dispatch-preflight: WARN the plan carries no parallel-budget: line with a writers= field, so the writer budget is unmeasured (ADR-035: the budget is a measurement Step 0 writes). Plan: %s. Add Step 0'"'"'s line to its frontmatter: parallel-budget: writers=N suites=N worktrees=N test_jobs=N source=probe\n' \
      "$PLAN" >&2
    dp_not_checked "budget" "a parallel-budget: line with a writers= field in the plan (ADR-035)"
    DP_BUDGET_NAMED=1
  fi
fi

if [ -n "$PARALLEL_BUDGET" ]; then

  # OPEN ROWS AND THE SUITES THEY CLAIM, in one pass over the roster (spec AC-7).
  #
  # "Open" no longer asks the roster whether a row was ever closed — it asks THIS
  # TURN'S ListAgents answer whether the row's agent is STILL WORKING. A dispatch row
  # starts life `status=intended` and never transitions on this file (D0: nothing
  # here owns a liveness fact, so nothing here writes one); `live_row_open` is one
  # question asked of the one reader of the harness's own recorded answer
  # (payload/scripts/lib/agents.sh). `landing-swept/v1` is NOT consulted any more — a
  # row can go un-swept forever and still close the moment its agent stops working.
  #
  # PRESENCE IS NOT THE PREDICATE, AND NEITHER IS THE WORD `running` (spec R2, AC-27;
  # S19). R2 names two ways an agent goes — "delivered and stopped, or finished and never
  # stopped" — and the harness KEEPS LISTING the second kind, with status `idle`, because
  # it stays addressable: a SendMessage would resume it. A budget that counted on presence
  # would hold a writer slot for an agent that finished an hour ago until somebody
  # remembered to stop it, which is the stuck-slot defect this wall was built to end.
  #
  # The rule is OPEN UNLESS THE HARNESS SAID `idle`, and it lives in `live_row_open`
  # (payload/scripts/lib/agents.sh) rather than here, because the Patrol tick asks the same
  # question and two spellings of it are two answers. That function's header says why the
  # rule is an inversion and what it rests on; this comment does not repeat it.
  #
  # THE STOP GUARD DELIBERATELY DOES NOT FOLLOW THIS. It resolves on PRESENCE
  # (`live_agents_has`), because an idle agent is exactly the one a stop is for. Both
  # questions are answered from ONE parse of ONE recorded answer, so the two can never
  # disagree about who is listed — only about what the status means, which is the whole
  # point of asking two questions (tests/cross-gate-agreement.test.sh §LA.5).
  #
  # A CLAIM IS READ OFF THE LEDGER, never off the process table (WALLS/3): a row whose
  # brief declared a subprocess claim spends a suite. Asking `pgrep` per row would be
  # truer to the word "running" and would put a process spawn per row on the dispatch
  # path; the ledger is the artifact this gate already owns. A claim only spends a
  # suite while its row is OPEN — a finished agent's old claim costs nothing.
  #
  # AMBIGUOUS COUNTS AS OPEN (the name present more than once) — folded into the
  # predicate's own exit 0, so this function never sees it as a separate case. The safe
  # direction is to spend a slot on a name that MIGHT still be working rather than hand
  # out budget on a reading the reader itself could not resolve (rule
  # fail-closed-constants). It is the same direction the unknown-status arm takes, for
  # the same reason: an UNRESOLVABLE row and an UNRECOGNISED status are both readings
  # nobody has taken, while an `idle` row is a reading the harness made and this wall
  # believes.
  #
  # ON A STALE OR MISSING ANSWER (exit 3/4) THIS FUNCTION STILL ANSWERS (D1, wave-12).
  # It used to refuse to — printing `<state> <age>` and returning 3/4, which the caller
  # turned into a whole-dispatch refusal naming a ListAgents call as the repair. That made
  # a chore a PRECONDITION of a judgement, and it is struck: no hook requires the model to
  # perform an act before it will judge one (spec P-A). The fallback is the roster itself,
  # which this wall already owns and already reads. So the answer is ALWAYS `<open>
  # <claimed>` and the exit is ALWAYS 0; a dispatch is judged against a count that may be
  # generous, never deferred.
  #
  # AND ON THAT DARK PATH THE ROSTER ANSWERS WITH EVERYTHING IT KNOWS (wave-14 D7, REQ-3).
  # Wave-12 counted every remaining deduped `status=intended` row OPEN, full stop — which on
  # a wave of nine tasks held nine writer slots for the rest of the session, because a row
  # that LANDED still reads `status=intended` (nothing ever transitions it). The roster
  # carries the closing fact beside the row: the ack, taken after the row's launch, that the
  # Patrol or the orchestrator journals once the agent is gone. It is read through
  # `roster_open_names` (the one close predicate, above), once, AFTER the loop, and only for
  # the rows the panel could not speak for — the generous direction is kept for every row the
  # predicate still calls open, which is what keeps this fail-closed. A landing marker closes
  # nothing here since epic-23 wave-20 T2 (D10): it did until then, and no other reader
  # agreed.
  #
  # NEVER WHILE THE PANEL IS FRESH (AC-3.3, AC-3.4). A fresh answer is the truth about who is
  # working, and a marker is a claim about who FINISHED — where both can speak, the panel
  # decides, and the fresh branch below is delimited so that a marker read can never be added
  # inside it unnoticed (tests/dispatch-preflight.test.sh's narrowed token pin).
  #
  # THE READER IS NOT DEMOTED, only made optional. A FRESH answer still decides every row
  # it can speak to — an `idle` row still closes, an absent row still closes — and the
  # Patrol tick still consumes the same reader unchanged. Only the case where there is
  # nothing to read has stopped being an error.
  budget_roster_counts() {  # <roster file> <transcript> -> "<open> <claimed>" (exit 0)
    local f="$1" transcript="$2" line nm claims seen open=0 claimed=0 primed="" notfresh=""
    local la_out la_rc row_dark dark="" closed still_open
    if [ ! -f "$f" ] || [ -L "$f" ]; then printf '0 0'; return 0; fi
    seen="|"
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in "roster-state/${ROSTER_VERSION}|status=intended|"*) ;; *) continue ;; esac
      nm=$(printf '%s' "$line" | tr '|' '\n' | sed -n 's/^name=//p' | head -1)
      [ -n "$nm" ] || continue
      case "$seen" in *"|${nm}|"*) continue ;; esac
      seen="${seen}${nm}|"

      # ONCE THE ANSWER IS UNREADABLE, STOP ASKING. Freshness is a property of the
      # TRANSCRIPT, so a reader that said STALE or NONE for one row will say it for every
      # row after it. Asking again would re-pay the reader's miss per row and could not
      # change a verdict. From here the roster is the answer: each remaining row counts
      # OPEN (`la_rc=0` below), which is what "the count of open rows IS the live-agent
      # count" means when there is no live answer to consult.
      row_dark=""
      if [ -n "$notfresh" ]; then
        la_rc=0
        row_dark=1
      else
        # ---- BEGIN fresh-panel branch — the panel decides, and no closing marker is read
        # here (wave-14 AC-3.4, narrowing wave-12 AC-7) ----
        # PRIME THE READER'S PER-PROCESS PARSE, ONCE, IN THIS SHELL (Step-6 review P-1).
        # `live_agents` memoizes its parse in shell variables keyed on the transcript's path,
        # size and mtime — but the per-row call below runs inside a command substitution, and
        # a subshell INHERITS its parent's variables while its own writes die with it. So the
        # first row would warm a cache nobody sees and every row would pay a full parse: two
        # whole-file jq passes and nine spawns, 1.22 s for twelve rows on a 4.1 MB transcript.
        # One call here, in the shell the loop actually runs in, warms it for every subshell
        # that follows. It is done lazily rather than before the loop so a roster with no
        # `status=intended` row still reads the transcript zero times. Its own answer is
        # discarded: this line is a cache fill, and the row's verdict is the predicate's.
        if [ -z "$primed" ]; then
          primed=1
          live_agents "$transcript" >/dev/null 2>&1 || :
        fi

        # THE PREDICATE IS NOT SPELLED HERE. It is `live_row_open`
        # (payload/scripts/lib/agents.sh), and its header says why the rule is an inversion.
        #
        # The reader's own stderr passes through here unchanged — one line,
        # `live-agents: <state> age=<n|none>` — captured rather than left to leak so the
        # STALE/NONE case below can hand its pieces to the caller verbatim. The predicate
        # prints nothing on stdout, so this capture is that line and nothing else.
        la_rc=0
        la_out=$( { live_row_open "$transcript" "$nm"; } 2>&1 ) || la_rc=$?
        # STALE (3) AND NONE (4) BECOME OPEN, not a refusal. The reader's own stderr line
        # stays captured in `la_out` and discarded: it named a ListAgents call as the
        # repair, which is no longer anybody's job, and letting it out would put the
        # retired chore back in front of the operator by another route.
        case "$la_rc" in
          3|4) notfresh=1; la_rc=0; row_dark=1 ;;
        esac
        # ---- END fresh-panel branch ----
      fi
      case "$la_rc" in
        0)
          open=$(( open + 1 ))
          claims=$(printf '%s' "$line" | tr '|' '\n' | sed -n 's/^claims=//p' | head -1)
          [ -n "$claims" ] && claimed=$(( claimed + 1 ))
          # COUNTED BY THE FALLBACK, NOT BY A READING. The row goes on the dark list with
          # its claim, and the block below asks the roster whether it has since closed. A
          # row the panel spoke for never lands here, which is what makes that question
          # unreachable on the fresh path.
          [ -n "$row_dark" ] && dark="${dark}${nm}|${claims}
"
          ;;
        1) : ;;
      esac
    done < "$f"

    # THE DARK ROWS, SETTLED IN ONE PASS (wave-14 REQ-3, D7). One read of the roster and one
    # of the ack ledger, for every dark row at once — never per row, and never at all on a
    # turn where the panel answered for every row. A landed row gives its writer slot back
    # AND the suite its brief claimed: a finished agent runs nothing.
    if [ -n "$dark" ]; then
      still_open=$(roster_open_names "$f" "$ACK_LEDGER_FILE")
      closed=$(while IFS='|' read -r nm claims; do
                 [ -n "$nm" ] || continue
                 /usr/bin/grep -qxF -- "$nm" <<< "$still_open" || printf '%s\n' "$nm"
               done <<DARKNAMES
$dark
DARKNAMES
)
      if [ -n "$closed" ]; then
        while IFS='|' read -r nm claims; do
          [ -n "$nm" ] || continue
          # A HERE-STRING, NOT A PIPE (correctness review F8; memory
          # grep-q-sigpipe-under-pipefail). `grep -q` exits at its first match; under this
          # file's `set -uo pipefail` (:67), a `printf | grep -qxF` pipeline SIGPIPEs the
          # producer whenever the match sits ahead of enough trailing data to still be
          # queued when `grep` closes its read end, and `pipefail` promotes that 141 over
          # grep's own 0 — a closed row reads as still open. A here-string has no second
          # process to lose.
          /usr/bin/grep -qxF -- "$nm" <<< "$closed" || continue
          open=$(( open - 1 ))
          [ -n "$claims" ] && claimed=$(( claimed - 1 ))
        done <<DARK
$dark
DARK
      fi
    fi

    printf '%s %s' "$open" "$claimed"
  }

  # LIVE LEASES ON DISK. A directory under `.worktrees` whose `.git` is a FILE is a
  # linked worktree; anything else there is a leftover, not a lease (WALLS/4).
  budget_live_trees() {  # <project root> -> count
    local root="$1" d n=0
    [ -d "$root/.worktrees" ] || { printf '0'; return 0; }
    for d in "$root"/.worktrees/*; do
      [ -d "$d" ] || continue
      [ -f "$d/.git" ] || continue
      n=$(( n + 1 ))
    done
    printf '%s' "$n"
  }

  # FIRST CEILING WINS, STILL (wave-14 REQ-8, D3). The three ceilings are three readings of
  # ONE wall and one repair — "land or stand down a row" clears whichever of them fired — so
  # reporting all three would spend three lines of the refusal's budget to say one thing
  # three ways. The guard keeps the arm's pre-REQ-8 behaviour exactly: the first ceiling
  # passed is the one named. What changed is that the wall records instead of exiting, so
  # the arms after it are read in the same pass.
  BUDGET_DENIED=""
  budget_deny() {  # <fact> <the one line naming the resource, its ceiling and its count>
    # ONE FIX FOR ALL THREE ARMS (rows 43-45): the fact names which ceiling was passed
    # and the repair is the same act whichever it was.
    [ -z "$BUDGET_DENIED" ] || return 0
    BUDGET_DENIED=1
    dp_finding "$1" "land or stand down a row" \
      "    $2

budget: ${PARALLEL_BUDGET}
  declared by ${PLAN}

That string is derived once, at Step 0, from this machine's own resources probe, and
recorded verbatim — nothing re-derives it here, and raising it is a Step-0 act.

Fix: land or stand down an open row first (\`bash <plugin-root>/hooks/stop-orders.sh
standdown\` computes the batch), or re-run Step 0's probe and raise the line if the
machine genuinely has the room."
  }

  # THE TRANSCRIPT (spec AC-7, AC-8): the payload's own `transcript_path`, the same
  # field every other liveness reader in this wave keys off (context-spend.sh,
  # execution-recorder.sh, patrol-duties-gate.sh, stop-guard.sh).
  BUDGET_TRANSCRIPT=$(_jq '.transcript_path')

  # NO ARM BETWEEN THE COUNT AND THE CEILINGS (D1, wave-12; Chris 2026-09-13 "I don't
  # want this to happen to begin with"). There used to be one here: a STALE or absent
  # ListAgents answer refused the whole dispatch, telling the orchestrator to call the
  # tool and come back — and telling a dispatched agent, which holds no such tool, to ask
  # the orchestrator instead. Both halves are gone. `budget_roster_counts` now always
  # answers `<open> <claimed>`, falling back to the roster's own open rows when there is
  # no answer to read, so the three ceilings below are the only thing left between a
  # brief and its dispatch.
  BUDGET_COUNTS=$(budget_roster_counts "$ROSTER_FILE" "$BUDGET_TRANSCRIPT")
  BUDGET_OPEN="${BUDGET_COUNTS%% *}"
  BUDGET_CLAIMED="${BUDGET_COUNTS##* }"
  BUDGET_UNMEASURED=""

  B_WRITERS="$DP_BUDGET_WRITERS"
  if [ -n "$B_WRITERS" ]; then
    [ $(( BUDGET_OPEN + 1 )) -gt "$B_WRITERS" ] && budget_deny \
      "this passes the run's writer budget" \
      "writers: budget=${B_WRITERS} open=${BUDGET_OPEN} with-this-dispatch=$(( BUDGET_OPEN + 1 ))"
  elif [ -z "$DP_BUDGET_NAMED" ]; then
    BUDGET_UNMEASURED="${BUDGET_UNMEASURED} writers"
  fi

  B_SUITES=$(budget_field "$PARALLEL_BUDGET" suites)
  if [ -n "$B_SUITES" ]; then
    [ $(( BUDGET_CLAIMED + 1 )) -gt "$B_SUITES" ] && budget_deny \
      "this passes the run's suite budget" \
      "suites: budget=${B_SUITES} claimed=${BUDGET_CLAIMED} with-this-dispatch=$(( BUDGET_CLAIMED + 1 ))"
  else
    BUDGET_UNMEASURED="${BUDGET_UNMEASURED} suites"
  fi

  B_TREES=$(budget_field "$PARALLEL_BUDGET" worktrees)
  if [ -n "$B_TREES" ]; then
    BUDGET_LIVE=$(budget_live_trees "$BIONIC_ROOT")
    [ $(( BUDGET_LIVE + 1 )) -gt "$B_TREES" ] && budget_deny \
      "this passes the run's worktree budget" \
      "worktrees: budget=${B_TREES} live=${BUDGET_LIVE} with-this-dispatch=$(( BUDGET_LIVE + 1 ))"
  else
    BUDGET_UNMEASURED="${BUDGET_UNMEASURED} worktrees"
  fi

  # Said once, on the pass path, and only when a field the line should have carried was
  # unreadable: a wall that could not measure an arm must never go quiet about it.
  if [ -n "$BUDGET_UNMEASURED" ]; then
    printf 'dispatch-preflight: WARN the plan'"'"'s parallel-budget line carries no readable%s field; %s unmeasured. Line: %s\n' \
      "$BUDGET_UNMEASURED" "${BUDGET_UNMEASURED# }" "$PARALLEL_BUDGET" >&2
    # AND ON THE REFUSAL'S OWN WIRE (AC-8.2). The WARN above is the pass path's; a dispatch
    # being refused for something else needs the same fact where the model reads, or the
    # author repairs three faults and meets a ceiling that was never measured. This is R2's
    # per-field shape, which AC-8.2 names as the one the rest of the file should copy.
    dp_not_checked "budget" "the parallel-budget: line to carry${BUDGET_UNMEASURED}"
  fi
fi

warn() { printf 'dispatch-preflight: WARN %s\n' "$1" >&2; }

# Values are pipe-delimited on one line, so a field carrying a newline or a `|`
# would forge a row. Never a refusal — the ledger normalizes and records.
#
# THE THIRD ARGUMENT IS THE FIELD NAME (T18, REQ-9/D7 — the write-side half of the fix
# `hooks/session-poker.sh`'s `clean()` already carries for the reader side, task T9).
# `files=` and `suites_allowed=` are LIST-valued — a space- or comma-joined set — and a
# dispatch declaring enough files or naming enough suites overflows even this file's
# widest cap (900) on a perfectly ordinary brief: a 70-suite `Suites:` line runs to
# 1.7-1.8 KB. The cut then silently drops suites off the end, narrowing a budget the wall
# never agreed to. Every OTHER field this hook sanitizes — name, deliverable, duration,
# progress, cadence, claims, waiver, the ambiguity candidates, the plan path — is prose or
# a single path, where even the smallest existing cap is already more than any real value
# needs, so they keep the cut. Callers that pass no field name (every one but the two
# `C_FILES`/`C_SUITES` call sites) get today's behaviour exactly, caps unchanged.
#
# AND `re_executes=` KEEPS ITS PIPE (T4, REQ-7, D4). This filter runs on the value that is
# then handed to `roster_row`, which is the ONE writer of the row and the one place that
# knows how the row holds a `|` — it escapes the character for this field
# (`payload/scripts/lib/roster.sh`, `roster_pipe_escape`) rather than folding it. Folding
# here would destroy the pipe before the writer ever saw it, and the quote-aware lift above
# would be admitting a command the row could not carry. Every OTHER field still folds: none
# of them is read back and compared to text a human typed, so for them a forged segment is
# the only risk worth pricing and the fold is still the right answer.
sanitize() {  # <value> <max-chars> [<field name>]
  local out _s1='\n\r\t|' _s2='    '
  case "${3:-}" in re_executes) _s1='\n\r\t'; _s2='   ' ;; esac
  out="$(printf '%s' "$1" \
    | tr "$_s1" "$_s2" \
    | sed -e 's/[[:cntrl:]]/ /g' -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//')"
  case "${3:-}" in
    files|suites_allowed|re_executes) printf '%s' "$out" ;;
    *) printf '%s' "$out" | cut -c "1-$2" ;;
  esac
}

# ---------- contract-state extraction ----------
#
# The anchors are the labeled fields the dispatch brief already carries — the
# seven-field sentence in skills/canonical-sdlc/SKILL.md §Dispatch, span-pinned
# by tests/dispatch-spans.test.sh §5d, with the exemplar brief recorded at
# .bionic/docs/record/w2-ac3-run.md. This lifts the BRIEF's reading, never the
# orchestrator's restatement (spec §Design invariant).
#
# Two properties earn the awk pass over a line-oriented grep:
#   * a raw label span reaches the NEXT LABEL, not the newline — real briefs put
#     two fields on one line ("Expected duration: ~35 minutes. Progress: <path>")
#     and a line-scoped reader swallows the second into the first. That span is then
#     BOUNDED per field before use (epic-16 wave-02 R1): the deliverable takes the
#     first path-shaped token inside the label's own first sentence (never a
#     following input path — Step-6 review C-2), and duration/cadence take a value
#     bounded at the first clause boundary (never a run-on — C-1/F-3). Progress,
#     claims and the waiver reason still consume their whole span;
#   * labels nest ("progress" inside "progress artifact", "duration" inside
#     "expected duration"), so labels are matched longest-first and a shorter
#     one overlapping an accepted longer one is discarded. Without that, the
#     inner match becomes a terminator for its own outer span and every value
#     lifts empty.
# Deliverable and progress values are reduced to path-shaped tokens, because
# their consumers (tasks 4/5, 4/6) stat them; a slash-bearing token with no
# letter is a fraction ("task 4/3"), not a path.
#
# THE LIVENESS FIELDS (`cadence`, `claims`) join the same table, because task
# 4/7 shipped them into the same §Dispatch prose the labels above anchor on:
# "The progress-artifact path carries a `cadence` alongside it" and "A subprocess
# claim — a process pattern plus its output file — is conditional-required". They
# were prose-only for one task — hooks/stop-check.sh read `claims=` off a row no
# writer could produce, which the Step-6 six-axis review called for what it was
# (axis-3 FAIL: a shipped reader with no producer, its only test hand-writing an
# impossible row). Two grammar notes, both forced by that ratified sentence:
#
#   * `cadence` may be introduced by whitespace instead of a colon, because the
#     contract puts it ALONGSIDE the progress path inside one sentence
#     ("Progress: <path>, cadence ~6m") rather than on a labeled line of its own.
#     It is the only label with a relaxed separator, and the separator still has
#     to be there — `cadences` is not a hit. That relaxation is also why the hit
#     is POSITIONAL: a lexical match alone turned every prose use of the word
#     into a declaration (Step-6 critic F-2), so END additionally requires the
#     hit to fall inside the span the progress label owns — which is exactly
#     where the sentence above puts it.
#   * the subprocess claim is spelled in the contract's own words — "A subprocess
#     claim" — and those are the only two labels that lift it. A bare `claims`
#     label was tried and withdrawn: it matched "verify every claim the report
#     claims:" in an ordinary review brief and invented a subprocess for it,
#     which the P2 display then reports as `live: no`, the alarm direction.
#   * the subprocess claim declares two things in one span, and only one of them
#     has a consumer: the PATTERN, which hooks/stop-check.sh existence-checks.
#     So the pattern is what the row carries — the backticked or quoted run when
#     the author marks one, else the text up to the first comma or arrow.
LEAD_CHARS="(\"[<\`$(printf '\047')"
TRAIL_CHARS=")\"]>\`,;:!?.$(printf '\047')"
QUOTE_CHARS="\`\"$(printf '\047')"

# ---------- the re-execution cap is the auditor's (wave-20 T4; REQ-7, Δ3, Δ9) ----------
#
# THREE IS THE AUDITOR'S NUMBER. Its source is the auditor mandate — "One auditor, one pass,
# <=3 re-executions" (skills/canonical-sdlc/steps/5.md) — and it used to bind every role's
# `Re-executes:`, so a test-runner re-running a jest, pytest and go floor split it into two
# dispatches for a rule written about auditors (triage-B D3). Chris moved it (Δ3): the
# auditor keeps three; every other role is bounded by SUITES_MAX (Δ9), the count that
# already bounds `Suites:`, so the two spellings of one statement share one ceiling and no
# new number exists.
#
# THE ROLE IS MATCHED WHOLE, as the auditor arm below matches it: the prefixed name the
# harness sends and the bare word a hand-written brief uses. The answer is handed to the
# lift's awk as `-v RUNS_CAP`; the refusal texts below read the same function, so the
# number a refusal prints is the number the lift applied.
DP_AUDITOR_RUNS_MAX=3
DP_SUITES_MAX=200
dp_runs_cap() {  # <subagent_type> -> how many runs that role's Re-executes: may declare
  case "${1-}" in
    bionic:auditor|auditor) printf '%s' "$DP_AUDITOR_RUNS_MAX" ;;
    *) printf '%s' "$DP_SUITES_MAX" ;;
  esac
}
# dp_runs_cap_words <subagent_type> -> the cap as the refusal texts say it.
dp_runs_cap_words() {
  case "${1-}" in
    bionic:auditor|auditor) printf 'three' ;;
    *) printf '%s' "$DP_SUITES_MAX" ;;
  esac
}

lift_contract_fields() {  # <brief text> [<subagent_type>] -> `kind=value` lines, absent kinds omitted
  printf '%s' "$1" | awk -v LEAD="$LEAD_CHARS" -v TRAIL="$TRAIL_CHARS" -v QUOTES="$QUOTE_CHARS" \
    -v RUNS_CAP="$(dp_runs_cap "${2-}")" -v SUITES_CAP="$DP_SUITES_MAX" "$CMD_RUN_NORM_AWK"'
    # <sep> is the regex between the label and its value; the default is the
    # colon every labeled brief field uses. <bol> marks a label that only counts
    # at the START of a line — see the waiver note in BEGIN.
    function addlabel(txt, kind, sep, bol) {
      NL++; LTXT[NL] = txt; LKIND[NL] = kind
      LSEP[NL] = (sep == "" ? "[ \t]*:" : sep)
      LBOL[NL] = (bol == "" ? 0 : 1)
    }
    # True iff position p is the first non-blank thing on its line. Leading
    # whitespace still counts as a line start (an indented brief field is a
    # field); anything else before it on the line does not.
    function at_line_start(p,   k, ch) {
      k = p - 1
      while (k >= 1) {
        ch = substr(lc, k, 1)
        if (ch == " " || ch == "\t") { k--; continue }
        return (ch == "\n")
      }
      return 1
    }
    function trimtok(t,   ch) {
      while (length(t) > 0) { ch = substr(t, 1, 1);         if (index(LEAD,  ch) > 0) t = substr(t, 2);                    else break }
      while (length(t) > 0) { ch = substr(t, length(t), 1); if (index(TRAIL, ch) > 0) t = substr(t, 1, length(t) - 1);     else break }
      return t
    }
    # A token carrying an unfilled `<...>` slot is a TEMPLATE, not a path. The wall
    # message hands the author a label example and briefs in this repo quote it, so a
    # slot must never lift as a real contract — nothing could ever satisfy it
    # (Step-6 review C-1, second shape). The rule lives in `ispath()`, the one
    # predicate every declared token runs through.
    #
    # WHAT FOLLOWS FROM REJECTING IT (epic-16 wave-02 R1, inference withdrawn): a
    # template is not a concrete path, so a brief whose only deliverable is a slot
    # yields nothing and the absent-deliverable wall REFUSES it, telling the author at
    # dispatch to name it exactly. Wave-02 R4 briefly filled the slot from the agent
    # name and recorded `source=inferred`; the Step-6 critic (N-1) showed that fill is
    # a GUESS enforced with a declared fact weight, so it was withdrawn — the wall
    # never guesses a deliverable, and declaring one is the cheap, robust fix.
    #
    # The unterminated form (`<name` after trimtok has eaten a trailing `>`) counts
    # as a template too. Without that clause `.bionic/tmp/<name>` passed the four
    # shape checks and lifted as a literal path — a contract with a bracket in its
    # basename, which nothing would ever satisfy.
    # The unterminated forms are counted too, in BOTH directions, because trimtok
    # runs first and its LEAD/TRAIL sets contain both brackets: `<name>` alone comes
    # out as `name`, and `<somewhere>/out.md` comes out as `somewhere>/out.md`,
    # which passes all four shape checks and would lift as a literal path with a
    # bracket in it. An orphaned bracket on either side is the residue of a slot,
    # never a filename anyone typed.
    function istemplate(t) {
      if (t ~ /<[^<>]*>/)  return 1     # a whole slot
      if (t ~ /<[^<>]*$/)  return 1     # opening bracket, closer eaten by trimtok
      if (t ~ /^[^<>]*>/)  return 1     # closing bracket, opener eaten by trimtok
      return 0
    }
    # THE SAME QUESTION ASKED OF A TOKEN THAT NEVER MET trimtok (wave-16 T25, walk §W7).
    # The two residue arms in `istemplate` are correct for the callers it has — `ispath()`
    # and `suite_names()` both trim the token first, and the LEAD/TRAIL sets trimtok carries
    # contain both brackets, so `<somewhere>/out.md` really does arrive there as
    # `somewhere>/out.md`.
    # `marked_runs()` does NOT trim: a run is taken verbatim between its marks, so those two
    # arms meet shell redirections instead of residue and used to swallow `> out`, `2>&1`
    # and `<in` as "guidance". This predicate asks the only question that is meaningful on an
    # untrimmed run: is the token NOTHING BUT a slot. Anchored, because a run that merely
    # CONTAINS one — `cmd <in >out` matches `<[^<>]*>` — is a redirection, not a placeholder,
    # and reading it as guidance is the silent drop this closes.
    function wholeslot(t) { return (t ~ /^<[^<>]*>$/) }
    function pathshaped(t) {
      if (length(t) < 3)        return 0
      if (index(t, "/") == 0)   return 0
      if (t !~ /[A-Za-z]/)      return 0
      if (substr(t, 1, 1) == "-") return 0
      return 1
    }
    function ispath(t) { return (pathshaped(t) && !istemplate(t)) }
    # ONE COLLAPSE, TWO STRENGTHS, BOTH OUT OF payload/scripts/lib/cmd-class.sh (wave-20 T4;
    # REQ-7, D7). Every caller but one wants whitespace collapsed and nothing else — a
    # waiver reason, a claim pattern, a deliverable. The one that stores a DECLARED RUN
    # passes `run` and gets `cmdnorm_run`, the rule the writer-side budget arm builds its
    # claim with (CMD_RUN_NORM_AWK, pasted in front of this program), so the two ends of
    # the row are one rule and not two collapses that happen to agree today.
    function collapse(s, run) { return (run ? cmdnorm_run(s) : cmdnorm_ws(s)) }
    # The claimed PROCESS PATTERN out of a subprocess-claim span. Author-marked
    # first (a backticked or quoted run is unambiguous), then the punctuation the
    # sentence uses to separate the pattern from its output file.
    function claimpat(s,   i, q, a, b) {
      s = collapse(s)
      for (i = 1; i <= length(QUOTES); i++) {
        q = substr(QUOTES, i, 1)
        a = index(s, q)
        if (a == 0) continue
        b = index(substr(s, a + 1), q)
        if (b > 1) return substr(s, a + 1, b - 1)
      }
      a = index(s, ",");  if (a > 0) s = substr(s, 1, a - 1)
      a = index(s, "->"); if (a > 0) s = substr(s, 1, a - 1)
      a = index(s, "→");  if (a > 0) s = substr(s, 1, a - 1)
      return collapse(s)
    }
    function firsthit(kind,   j, best) {
      best = 0
      for (j = 1; j <= nh; j++) if (HK[j] == kind && (best == 0 || HLS[j] < HLS[best])) best = j
      return best
    }
    # The last character index of the span belonging to hit h. `skip` names one
    # hit to IGNORE when looking for the terminator, which the cadence rule in
    # END needs: it asks where the PROGRESS span would end if the cadence label
    # were not sitting inside it, and without the skip that span would end at the
    # very label whose membership is the question. (No apostrophes in here — the
    # whole program is one single-quoted shell word.)
    # The last index within s (1-based) before the first FOLLOWING line that opens a
    # short `<Word>:` head, or 0 when no such line follows. A field ends where the next
    # one begins, and the wall must not need the label table to know that a new line
    # beginning `Evidence log:` is a different field from the one above it. Bounded to
    # three words and no punctuation before the colon, so a prose sentence that merely
    # contains a colon ("it runs in three steps: first...") is not mistaken for a head;
    # written without interval expressions, which not every awk implements.
    # THE SKIPPED HIT KEEPS ITS LINE. `skipabs` is the absolute offset of the one label
    # hit this call is pretending does not exist (the cadence rule in END asks where the
    # PROGRESS span would end if the cadence label were not inside it). The contract
    # writes `Cadence:` on a line of its own beneath `Progress:`, so bounding at that
    # line would answer the question the caller is asking with the fact it is asking
    # about, and every colon-form cadence would stop lifting.
    function labelline(s, base, skipabs,   i, j, k, line, ls, le) {
      i = 1
      while ((j = index(substr(s, i), "\n")) > 0) {
        j = i + j - 1
        k = index(substr(s, j + 1), "\n")
        line = (k > 0 ? substr(s, j + 1, k - 1) : substr(s, j + 1))
        if (line ~ /^[ \t]*[A-Za-z][A-Za-z0-9_-]*([ \t][A-Za-z0-9_-]+)?([ \t][A-Za-z0-9_-]+)?:[ \t]/) {
          ls = base + j
          le = ls + length(line) - 1
          if (!(skipabs > 0 && skipabs >= ls && skipabs <= le)) return j - 1
        }
        i = j + 1
      }
      return 0
    }
    function spanend(h, skip,   j, e, s, bl, ll) {
      e = length(text)
      for (j = 1; j <= nh; j++) if (j != skip && HLS[j] > HLS[h] && HLS[j] - 1 < e) e = HLS[j] - 1
      s = substr(text, HVS[h], e - HVS[h] + 1)
      bl = index(s, "\n\n")            # a blank line ends a field, whatever follows
      if (bl > 0) e = HVS[h] + bl - 2
      # ...and so does the next LABELLED LINE, registered label or not. Before this bound
      # a brief carrying `Evidence log: <path>` on the line after `Expected artifact:
      # <path>` put both paths in one deliverable span and was refused as ambiguous, for
      # naming exactly one deliverable and one input on lines of their own
      # (wave-bionic-1.3.2, found at dispatch). A prose continuation line has no head and
      # stays inside the span, so the R6-4 window is unchanged.
      s = substr(text, HVS[h], e - HVS[h] + 1)
      ll = labelline(s, HVS[h], (skip > 0 ? HLS[skip] : 0))
      if (ll > 0 && HVS[h] + ll - 1 < e) e = HVS[h] + ll - 1
      return e
    }
    function spanof(h) { return substr(text, HVS[h], spanend(h, 0) - HVS[h] + 1) }
    # ---- bounded field extraction (epic-16 wave-02 R1) ----
    # A field value ends at the first CLAUSE boundary, never at "the next label or a
    # blank line". That run-on reading (the old spanof value) let cadence or duration
    # swallow the prose after it. On cadence= it fed parse_seconds a value it refuses,
    # flipping a visibly-alive agent to UNMET (Step-6 review C-1/F-3); on duration= it
    # silently exempted a row from overdue notification (A-2). A sentence terminator
    # (. ? !) counts only when followed by whitespace or the end, so a period inside a
    # value is never a false boundary. A comma or a bracket ends the clause too — the
    # same restraint claimpat() already applies, and the exact shape the live specimen
    # corrupted ("2m) claims=...").
    #
    # BOTH brackets, not just the closing one (Step-6 R6 critic R6-3). With `(` absent
    # from this set a balanced parenthetical truncated mid-phrase and left the bracket
    # dangling — "~45 minutes (phase 1 only" — which hooks/session-poker.sh parse_seconds
    # refuses, because it accounts for every number and the parentheticals own digit has
    # no unit. An unreadable duration silently exempts the row from overdue notification,
    # which is A-2 read from the writer side. Ending the value at the bracket yields the
    # clean "~45 minutes" the author meant.
    function bound_field(s,   i, ch, nx, out) {
      out = ""
      i = 1
      while (i <= length(s)) {
        ch = substr(s, i, 1)
        if (ch == "\n" || ch == "\r") break
        if (ch == "," || ch == ")" || ch == "(") break
        out = out ch
        if (ch == "." || ch == "?" || ch == "!") {
          nx = substr(s, i + 1, 1)
          if (nx == "" || nx == " " || nx == "\t" || nx == "\r" || nx == "\n") break
        }
        i++
      }
      return collapse(out)
    }
    # EVERY distinct path-shaped token DECLARED under a deliverable label, in position
    # order, across the WHOLE span of the label — comma-joined, so one path is a bare
    # value and two or more is the ambiguity the caller refuses on.
    #
    # WHY NOT THE FIRST ONE (Step-6 R6 critic R6-1, plan assumption 71). R1 read the
    # FIRST SENTENCE of the label and took the FIRST path in it. That is still a guess,
    # only with a smaller window: "Expected artifact: same shape as A, written to B"
    # contracted A, and "read A first, then produce B" contracted A — the F-RD harm
    # verbatim, now recorded source=declared, so the landing gate orders the agent to
    # write A, which for that second brief means overwriting the report it was told to
    # read.
    # The extra paths in a deliverable sentence are usually INPUTS, so picking by position
    # picks the wrong file more often than the right one. Assumption 48 says the wall
    # never guesses: it declares or it refuses, and choosing among candidates is guessing.
    # So the span must yield EXACTLY ONE path, and the caller refuses on zero or on many.
    #
    # AND WHY THE WHOLE SPAN. The first-sentence bound was the R1 containment for the
    # trailing-input case; with ambiguity fatal it buys nothing and costs a false block —
    # "Expected artifact: a written report. Put it at PATH when done." named a path under
    # a canonical label and was refused for naming none (R6-4). The span is the one the
    # label owns, bounded at the next label or a blank line as every other field is.
    function span_paths(h) { return paths(spanof(h), DELIV_MAX, "") }
    # The declared deliverable: walk EVERY deliverable-kind label hit in position order
    # and return the paths of the first that yields any. Iterating (rather than taking
    # only firsthit) recovers a real labeled line that an earlier, pathless
    # deliverable-kind hit shadows — a brief quoting landing-verdict prose ("...per
    # deliverable:") ahead of its real "Expected artifact:" line. A hit that yields
    # SEVERAL paths ends the walk rather than being skipped for a cleaner later one:
    # ambiguity is a fact about the brief the author must resolve, not a hit to route
    # around. The wall never guesses a deliverable from prose (epic-16 wave-02 R1, plan
    # assumption 48); a template <slot> is not a concrete path (ispath rejects it), so a
    # brief that declares only a slot yields nothing here and the absent-deliverable wall
    # refuses it.
    #
    # EVERY HIT, NOT THE FIRST THAT ANSWERS (carry-over 14, research R3 row 35; REQ-12
    # AC-12.1). The walk used to RETURN at the first deliverable-kind hit that yielded a
    # path, so the rule was POSITION and nothing else: a brief carrying
    # `Expected artifact: a.md` and, lower down, a real `Deliverable: b.md` line was
    # contracted to whichever came first, recorded `source=declared` as though a human had
    # chosen, with the other path discarded in silence. `Expected artifact` holds no
    # precedence over `Deliverable` and never did — and the ambiguity wall could not see the
    # conflict, because each hit owns its own span and each span held exactly one path.
    #
    # SO THE PATHS OF EVERY HIT ARE UNIONED, DISTINCT, IN POSITION ORDER. Two labels naming
    # two paths now reach `deliverable_ambiguous=` exactly as one label naming two paths
    # always has: one refusal, both candidates handed back, no guess — assumption 48 applied
    # to the case where the second path is under a second label instead of beside the first.
    # The same path under both labels is ONE path and is admitted: an author who repeated
    # themselves has not created an ambiguity, and refusing that would be a wall with no
    # fault to name. A pathless hit still contributes nothing, which is what kept the
    # "...per deliverable:" prose specimen from shadowing a real labelled line.
    function decl_deliverable(   j, best, t, visited, out, seen, m, k, arr) {
      out = ""
      for (;;) {
        best = 0
        for (j = 1; j <= nh; j++) {
          if (HK[j] != "deliverable") continue
          if (visited[j]) continue
          if (best == 0 || HLS[j] < HLS[best]) best = j
        }
        if (best == 0) break
        visited[best] = 1
        t = span_paths(best)
        if (t == "") continue
        m = split(t, arr, ",")
        for (k = 1; k <= m; k++) {
          if (arr[k] == "") continue
          if (arr[k] in seen) continue
          seen[arr[k]] = 1
          out = (out == "" ? arr[k] : out "," arr[k])
        }
      }
      return out
    }
    # A waiver REASON that is the angle-bracketed slot out of the wall message,
    # copied rather than filled in. A real reason never opens with one.
    function isplaceholder(v) { return (v ~ /^<[^<>]*>/) }
    # THE SUITE BASENAMES named in a span, space-joined, in position order and
    # without duplicates — or the literal `none` when the span waives the budget.
    #
    # A SUITE IS RECOGNISED BY ITS BASENAME, never by the directory in front of it:
    # `tests/x.test.sh`, `./tests/x.test.sh` and an absolute spelling are one suite,
    # and it is the basename the derived set (`tests/lib/impact.sh | cut -f1`) prints
    # too. `run.sh` is admitted ONLY with a path component, because the bare word is
    # not a suite anywhere in this repo and briefs use it in prose constantly; the
    # same restraint payload/scripts/lib/cmd-class.sh applies to argv[0].
    #
    # THE WAIVER IS A WHOLE WORD, matched on the collapsed span rather than anywhere
    # in it: a brief reading `Suites: none` waives, and one reading
    # `Suites: tests/a.test.sh — none of the others` declares one suite and does not.
    # A CAP HIT IS LOUD (T19, A-orch-19.1). SUITES_MAX/FILES_MAX bound a ROW FIELD, not a
    # judgment, and this repo has grown past the old 60-token bound on its own suite roster —
    # so the count cap silently dropping the 61st-and-up suite reproduced the exact "your own
    # suite is off your budget" refusal T9/T18 already fixed on the CHAR side.
    #
    # THE WARNING RIDES THE SAME PIPE AS EVERY OTHER LIFTED FIELD, never awks own stderr:
    # this whole awk program is invoked under a trailing 2>/dev/null (below) so a malformed
    # brief cannot leak an awk runtime diagnostic onto the real hook stderr, and that redirect
    # would silence a print to /dev/stderr here just as thoroughly (both resolve to the SAME
    # underlying fd 2 the shell already pointed at /dev/null). Printing a `<kind>_capwarn=`
    # line instead puts it on stdout, where the bash side field_of and warn() -- the same
    # path the ABSENT-field warning already uses -- carry it to the real stderr untouched.
    function suite_names(s,   nl, lines, li, n, arr, i, t, b, out, seen, c, dropped, baddrop, cmt, real) {
      nl = split(s, lines, /\n/); out = ""; c = 0; dropped = ""; baddrop = ""; cmt = 0; real = 0
      for (li = 1; li <= nl; li++) {
      n = split(lines[li], arr, /[ \t\r]+/)
      for (i = 1; i <= n; i++) {
        t = trimtok(arr[i])
        # A COMMENT ENDS ITS OWN LINE (T23, Step-6 review R1; line-scoped by T35, critic C8).
        # The brief scaffold this repo ships reads `Suites: none    # *.test.sh names or a
        # path-qualified run.sh; other runners: Re-executes:`, and an author who fills that
        # scaffold in keeps the comment.
        # Every word after the `#` is a whitespace-separated token like any other, so the drop
        # refusal below scored `#`, `read-only` and `brief;` as suites the shell runner cannot
        # run and refused briefs the base admitted — with a message pointing at `Re-executes:`
        # that never mentioned the comment, so the repair was not discoverable from it. `#`
        # STOPS THE SCAN rather than being skipped: skipping would let a word inside prose
        # ("# see tests/other.test.sh") lift onto the row as a budget entry its author never
        # declared, and the writer-side guard would then hold the agent to it.
        #
        # WHAT IT STOPS IS THE LINE, NOT THE SPAN. A span is `spanof()`: everything up to the
        # next labelled line or the next blank one, so a roster wrapped across lines is ONE
        # span and a comment on its first line used to discard every suite declared below —
        # silently, no `suites_dropped=`, nothing on the row, the loud drop arm turned into a
        # quiet budget cut (critic C8). A comment runs to end of LINE, which is what `#` means
        # everywhere else a shell reader meets it; the scan resumes at the next line, and a
        # comment that opens a continuation line contributes nothing from that line alone.
        if (substr(t, 1, 1) == "#") break
        if (t == "" || istemplate(t)) continue
        # SOMETHING REAL WAS READ. Recorded for the all-comment case below, and set here —
        # before the shape filters — because an unexpanded name and a dropped token are both
        # declarations the author made, however the arms downstream answer them.
        real = 1
        # AN UNEXPANDED NAME IS NOT A SUITE, AND NOW SAYS SO HERE (REQ-1 AC-1.4, ADR-029).
        # The refusal prose at the suite-allowance wall has promised "one path per token, no
        # shell variables" since wave-01, and nothing at dispatch enforced it: `istemplate`
        # rejects `<slot>` forms only, so `tests/$X.test.sh` was basenamed to `$X.test.sh`,
        # matched the filter and lifted onto the row as a budget entry no command could ever
        # equal. The run-time twin already exists and already says why
        # (payload/scripts/lib/walls.sh budget_refuse: "unexpanded name; allowed: …"), so
        # this is the same rule read at the moment the author can still fix it. A bare `$`
        # (a regex anchor inside a quoted pattern) is not a variable — the token must be a
        # `$` followed by a name character or a brace.
        if (t ~ /[$][A-Za-z_{]/) { print "suites_bad=" t; continue }
        b = t; sub(/.*\//, "", b)
        if (b !~ /\.test\.sh$/ && !(b == "run.sh" && index(t, "/") > 0)) {
          # A DROPPED TOKEN IS NOW A REFUSAL (T3, REQ-8; wave-17, research R3 §C1.4 option 3
          # — a repair of THIS existing check, no new I/O, D11-compliant). Until now a token
          # whose basename was neither `*.test.sh` nor a path-qualified `run.sh` — a jest
          # spec, a pytest module, a bare `run.sh` — fell off in total silence: `suites=`
          # ended up empty, and the brief then met the UNRELATED no-instrument arm below for
          # "declaring no Files: and no Suites:", forty minutes before the writer-side guard
          # refused the exact command the brief had named. `none` is the waiver (checked
          # below, on the collapsed whole span) and is never a drop.
          if (tolower(b) != "none") { baddrop = (baddrop == "" ? t : baddrop " " t) }
          continue
        }
        if (seen[b]) continue
        seen[b] = 1
        if (c < SUITES_MAX) { out = (out == "" ? b : out " " b); c++ }
        else { dropped = (dropped == "" ? b : dropped " " b) }
      }
      # The inner loop LEFT EARLY iff it met a `#`, and `i` holds that token index.
      if (i <= n) cmt = 1
      }
      if (dropped != "") {
        print "suites_capwarn=Suites: line exceeds the " SUITES_MAX "-suite cap — dropped: " dropped
      }
      if (baddrop != "") { print "suites_dropped=" baddrop }
      if (out != "") return out
      if (tolower(collapse(s)) ~ /^none([^a-z0-9]|$)/) return "none"
      # A SPAN THAT IS ALL COMMENT DECLARED A LABEL AND NOTHING ELSE (critic C9). It lifts
      # no suites, no drop and no waiver, so all four guards of the no-instrument arm read
      # empty and the brief is refused for "declaring no Files: and no Suites:" — of a brief
      # that declares `Suites:` in as many words, the self-refuting shape C3 was fixed for.
      # The refusal is right (there is no budget for the row to carry) and stays where it is;
      # this fact is what lets its DETAIL say which of the two things happened.
      if (cmt && !real) { print "suites_commented=1" }
      return ""
    }
    # THE AUTHOR-MARKED RUNS on a `Re-executes:` span — each backtick-delimited command, in
    # position order, marks KEPT, space-joined, at most RUNS_MAX of them.
    #
    # WHY THE AUTHOR MARKS THEM (D3; research R1 open question 2). A run holds spaces, and
    # commas, and quotes, so token-splitting is wrong and any punctuation separator is
    # ambiguous with a command that contains it. `claimpat()` above already prefers an
    # author-marked run for exactly this reason; this is that precedent applied to a list.
    # Text OUTSIDE the marks is not a run — a brief that writes prose on the span has
    # declared nothing, which is the honest reading and the one the cap can bound.
    #
    # THE MARKS STAY ON THE VALUE. The roster field is what the writer-side budget arm
    # compares a real command against, and "the exact marked run" is only a thing to compare
    # when the row still carries the marks. It also makes the field self-delimiting: a
    # backtick cannot occur inside a run, because a backtick is what ends one.
    #
    # FOUR REFUSALS AT THE LIFT, each naming the token (REQ-1 AC-1.4, ADR-029; wave-16 T25).
    # An UNQUOTED `|` is shell plumbing, and plumbing is not one run; a newline means the
    # marks never closed on their own line; an unexpanded `$name` is a budget entry no
    # command can equal (see the same rule on the `Suites:` span above); and an angle bracket
    # that is not a whole slot is a shell redirection, which used to be dropped in silence.
    # The refusal is made on the bash side — this prints the fact.
    #
    # THE PIPE TEST READS QUOTES (T4, REQ-7, D4). It was `index(tok, "|") > 0`, a whole-token
    # scan, so a quoted regex alternation — the ordinary way a jest repository names two
    # suites with --testPathPattern — was refused as plumbing, and its author was told to
    # leave the shell plumbing off the span about a character that was never plumbing. The
    # spelling cannot be shown in this comment: the whole awk program is one single-quoted
    # shell word. tests/dispatch-preflight.test.sh 18T4a carries it. The delimiter problem
    # that reading was defending against is solved where it lives, in the row
    # (`payload/scripts/lib/roster.sh` escapes the field), not by refusing the command.
    #
    # A CAP HIT IS A REFUSAL, NOT A WARNING (T5, REQ-8, D12). The bad-token drop on
    # `suite_names()` above (`suites_dropped=`, two screens up) is the precedent this
    # follows, not its own cap-warn sibling: a run dropped here is a run the author
    # declared and the writer-side budget arm would then refuse at run time, 40 minutes
    # later, for a reason the author was never told at dispatch — so admitting the
    # dispatch with three of the four runs on the roster is the same hole `suites_dropped=`
    # closed for `Suites:`, reopened for `Re-executes:`. `RUNS_MAX` (3) is unchanged; it is
    # the ceiling on the declaration, never a bound the field silently narrows to.
    # WHETHER A TOKEN CARRIES A PIPE THE SHELL WOULD READ AS PLUMBING (T4; REQ-7, D4).
    #
    # THE STATE MACHINE IS THE ONE THE SHELL USES, minus what a `|` cannot escape into: a single
    # quote ends only at the next single quote, a double quote only at the next double
    # quote, and outside both a backslash protects the character after it. A `|` met while
    # any of those hold is a literal character in an argument — a regex alternation, a
    # bracket expression, an awk program — and a run carrying one is still one run.
    #
    # AN UNBALANCED QUOTE ADMITS THE REST OF THE TOKEN, and that is the honest answer rather
    # than a hole: a command whose quote never closes is a shell SYNTAX error, so the pipe
    # inside it can never run as plumbing either. Refusing it here would invent a fifth
    # fault word for a brief whose real fault the shell will name the moment it is typed.
    #
    # THE QUOTE CHARACTERS ARE READ OFF `QUOTES`, never spelled, for the reason the BEGIN
    # block records beside `BT`: this whole program is one single-quoted shell word, so a
    # bare apostrophe anywhere in it — even in a comment — ends the word before awk sees it.
    function unquoted_pipe(t,   n, k, ch, q) {
      n = length(t); q = ""
      for (k = 1; k <= n; k++) {
        ch = substr(t, k, 1)
        if (q != "") { if (ch == q) q = ""; continue }
        if (ch == BS) { k++; continue }
        if (ch == SQ || ch == DQ) { q = ch; continue }
        if (ch == "|") return 1
      }
      return 0
    }
    function marked_runs(s,   i, j, tok, out, c, dropped, why) {
      out = ""; c = 0; dropped = ""
      i = 1
      for (;;) {
        j = index(substr(s, i), BT)
        if (j == 0) break
        i = i + j                              # first character after the opening mark
        j = index(substr(s, i), BT)
        if (j == 0) break                      # an unclosed mark is not a run
        tok = substr(s, i, j - 1)
        i = i + j                              # first character after the closing mark
        why = ""
        if (index(tok, "\n") > 0)       why = "a newline"
        else if (unquoted_pipe(tok))    why = "a pipe"
        else if (tok ~ /[$][A-Za-z_{]/) why = "an unexpanded shell variable"
        if (why != "") { print "re_executes_bad=" why ": " collapse(tok); continue }
        tok = collapse(tok)
        # A TEMPLATE LIFTS NOTHING (epic-23 wave-16 T20; walk finding 1). The brief scaffold
        # carries its own guidance line, `` Re-executes: `<cmd>` ``, an unfilled slot —
        # the identical shape `istemplate()` already rejects on the `Files:` and `Suites:`
        # readers (`ispath()` and `suite_names()` both call it). Without this check a brief
        # that pasted the scaffold unfilled satisfied the suite-allowance wall on a budget
        # entry no real command could ever equal, and `dp_scaffold_marked` read the
        # placeholder as a real declaration and left the whole instrument triple unmarked. A
        # template is silently skipped here exactly as on the other two readers, never a
        # `re_executes_bad` fault: the author wrote guidance, not a mistake.
        #
        # A WHOLE SLOT ONLY (wave-16 T25, walk §W7). Anything else carrying a bracket is a
        # redirection and is REFUSED with the token named, the same way `|` and `$name` are
        # one and two lines up — it used to `continue` here, and the dispatch was admitted
        # with an empty or truncated `re_executes=` that the writer-side budget arm then
        # refused at run time as undeclared, 40 minutes after the author could have fixed it.
        if (tok == "" || wholeslot(tok)) continue
        if (tok ~ /[<>]/) { print "re_executes_bad=a redirection: " tok; continue }
        # STORED THROUGH THE ONE RUN RULE (wave-20 T4; REQ-7, D7). The refusals above run
        # first and on the text as written — a declaration naming a redirection is still told
        # so (16ld3, Chris D14) — so what reaches here carries no redirection, no unquoted
        # pipe, and this is the identity today. It is here so the rule that builds the claim
        # is, by construction, the rule that built the declaration.
        tok = collapse(tok, 1)
        if (c < RUNS_MAX) {
          out = (out == "" ? BT tok BT : out " " BT tok BT)
          c++
        } else {
          dropped = (dropped == "" ? BT tok BT : dropped " " BT tok BT)
        }
      }
      # NAMED, NOT WARNED (T5, REQ-8, D12): `re_executes_dropped=` reaches the same refusal
      # channel `suites_dropped=` does — read by the bash side below, which turns a non-empty
      # value into a `dp_finding` — never `warn()`, which is the several-fault ADMIT wire the
      # old `re_executes_capwarn=` field used.
      if (dropped != "") {
        print "re_executes_dropped=" dropped
      }
      return out
    }
    function paths(s, maxn, warnlabel,   n, arr, i, t, out, seen, c, dropped) {
      n = split(s, arr, /[ \t\r\n]+/); out = ""; c = 0; dropped = ""
      for (i = 1; i <= n; i++) {
        t = trimtok(arr[i])
        if (!ispath(t) || seen[t]) continue
        seen[t] = 1
        if (c < maxn) { out = (out == "" ? t : out "," t); c++ }
        else if (warnlabel != "") { dropped = (dropped == "" ? t : dropped " " t) }
      }
      if (warnlabel != "" && dropped != "") {
        print "files_capwarn=" warnlabel " line exceeds the " maxn "-path cap — dropped: " dropped
      }
      return out
    }
    BEGIN {
      NL = 0
      # How many candidate paths a deliverable span reports before it stops counting.
      # One is the contract; anything above one is refused, and the number only has to
      # be large enough for the refusal to show the author what it saw.
      DELIV_MAX = 12
      # How many paths a `Files:` span reports and how many basenames a `Suites:`
      # span reports. Both are bounds on a ROW FIELD, not on a judgment: the row is
      # one line the fleet parses by key, and a brief that names a hundred files has
      # a problem the wall cannot fix.
      #
      # RAISED 60 -> 200 (T19, A-orch-19.1): the old 60-token bound silently dropped the
      # 61st-and-up suite of a real budget — this repo carries 70+ suites of its own, so 60
      # was already narrower than the whole roster with no headroom left. 200 holds the
      # whole roster with room to grow, and hitting IT is loud: see warncap() below, never a
      # silent exit 0.
      FILES_MAX = 200
      SUITES_MAX = SUITES_CAP + 0
      # HOW MANY RUNS A `Re-executes:` SPAN DECLARES (D3; REQ-1 AC-1.6; wave-20 T4, Δ3, Δ9).
      # The ROLE decides, on the bash side (`dp_runs_cap`, above this function): three for an
      # auditor, whose mandate states "<=3 re-executions" (skills/canonical-sdlc/steps/5.md),
      # and SUITES_MAX for every other role. Unlike FILES_MAX/SUITES_MAX this is not a bound
      # on the width of a row field — it is the ceiling of the declaration itself — so
      # hitting it is a fact about the brief, and loud: see marked_runs() above. A caller that
      # passes no cap gets SUITES_MAX, never an unbounded lift.
      RUNS_MAX = RUNS_CAP + 0
      if (RUNS_MAX <= 0) RUNS_MAX = SUITES_MAX
      # THE MARK THE AUTHOR WRITES, NAMED RATHER THAN SPELT. This whole program is one single-quoted
      # shell word, so a backtick literal inside it would be one more character the shell
      # reads before awk does; `QUOTE_CHARS` is assembled above this function with the
      # backtick first, for claimpat(), and this is the same character read off the same
      # source.
      BT = substr(QUOTES, 1, 1)
      # THE OTHER TWO, off the same source and for the same reason (T4). `QUOTE_CHARS` is
      # assembled backtick, double quote, single quote — the order claimpat() reads it in.
      # `BS` is a single backslash: in an awk string literal it is written doubled.
      DQ = substr(QUOTES, 2, 1)
      SQ = substr(QUOTES, 3, 1)
      BS = "\\"
      # LONGEST FIRST — see the nesting note above. `-` marks a label that only
      # BOUNDS a span; it is a real brief field, just not one the roster lifts.
      #
      # `input` is a second non-lifting kind. Since inference was withdrawn (R1) it
      # bounds spans exactly as `-` does — no prose path is ever lifted, and `read first`
      # / `scope constraint` are not deliverable labels, so a path under one of them is
      # out of every deliverable span and cannot become the contract. The kind is kept
      # distinct only to keep these two headings legible as inputs; nothing reads it.
      #
      # THE STATEMENT THIS COMMENT USED TO MAKE — "a path a brief tells the agent to read
      # is never taken as the deliverable" — was false while R1 shipped, and is now true
      # for a different reason than it claimed (R6 critic R6-1). An input named INSIDE the
      # deliverable label span is not out of reach of the extractor; what saves it is that
      # a span holding two paths refuses the dispatch instead of picking one. The fix for
      # such a brief is to move the reference out to its own line, which is what these
      # input headings are for and what the ambiguity refusal tells the author to do.
      #
      # `deliverable-waiver` heads the table because it is the longest label AND
      # because it nests the shortest-but-one: a brief line reading
      # `Deliverable-waiver: <reason>` must never lift as a `deliverable`. The
      # separator rule already keeps them apart (`deliverable` requires a colon,
      # and the next character here is a hyphen), but the ordering makes the
      # intent structural rather than incidental.
      #
      # It is also pinned to LINE START, and — since final-audit A-1 — so are the
      # six deliverable-kind labels below (expected artifact(s), deliverable(s),
      # artifact(s)). It is the only label that OPENS a wall rather than filling
      # a field, and briefs in this repo quote the wall message that names it
      # constantly — so a mid-sentence occurrence is documentation, not a
      # declaration (Step-6 review S-1: one quoted line silenced the landing
      # contract for the whole dispatch).
      #
      # THE SAME HAZARD REACHES THE DELIVERABLE LABELS (final-audit A-1,
      # record/w2-r7-audit.md). Every refusal this wall prints recommends the
      # same concrete, copy-paste example — Expected artifact:
      # .bionic/docs/record/my-task-notes.md — and a brief that quotes that
      # line in prose ahead of its real, later label puts each occurrence in its
      # OWN span, one path apiece, so the ambiguity wall below never sees two
      # paths in one span. decl_deliverable() then takes the FIRST hit that
      # yields any path and silently contracts the agent to a file it will never
      # write, recorded source=declared as though a human named it — the one
      # shape that routes around the ambiguity wall entirely. Pinning the six
      # deliverable-kind spellings to line start closes it the same way S-1
      # closed it for the waiver: a mid-sentence occurrence never becomes a hit.
      #
      # THE REMAINING LABELS ARE DELIBERATELY LEFT UNPINNED (cadence, duration,
      # progress, subprocess claim). None of them is quoted as a copy-paste
      # example in any wall message, so the bait mechanism above does not reach
      # them. cadence is also POSITIONAL by design (S10L) — it is meant to sit
      # mid-sentence inside the progress span (Progress: PATH, cadence ~5m), and
      # pinning it to line start would break that grammar outright. A wrong
      # duration or progress value is a misread number or path the watcher acts
      # on; a wrong deliverable is a file-write contract the landing gate later
      # enforces by ordering the agent to overwrite whatever it names. The harms
      # are not the same size, and the fix is scoped to the one that is.
      addlabel("deliverable-waiver", "waiver", "", 1)
      addlabel("subprocess claims", "claims")
      addlabel("subprocess claim",  "claims")
      addlabel("expected artifacts", "deliverable", "", 1)
      addlabel("expected artifact",  "deliverable", "", 1)
      addlabel("progress artifact",  "progress")
      addlabel("expected duration",  "duration")
      addlabel("scope constraint",   "input")
      addlabel("exit condition",     "-")
      addlabel("progress path",      "progress")
      addlabel("deliverables",       "deliverable", "", 1)
      addlabel("current step",       "-")
      addlabel("deliverable",        "deliverable", "", 1)
      addlabel("constraints",        "-")
      addlabel("your task",         "-")
      addlabel("read first",         "input")
      addlabel("artifacts",          "deliverable", "", 1)
      addlabel("artifact",           "deliverable", "", 1)
      addlabel("progress",           "progress")
      addlabel("duration",           "duration")
      addlabel("cadence",            "cadence", "([ \t]*:|[ \t])[ \t]*")
      # THE TWO INSTRUMENT LABELS (wave-01 S13, spec AC-20), BOTH PINNED TO LINE
      # START. `Files:` declares the intent — what this task will touch — and
      # `Suites:` declares the consequence directly, for a repository where no
      # impact command is configured. Both are pinned for the reason the six
      # deliverable-kind labels are: every refusal below quotes them back as a
      # copy-paste example, and a brief that repeats the example mid-sentence has
      # documented the wall, not declared a field.
      # THE THIRD INSTRUMENT LABEL (epic-23 wave-16, REQ-1, D1, ADR-029), PINNED TO LINE
      # START like the other two and for the same reason: the refusals below quote it back as
      # a copy-paste example. `Files:` declares intent and `Suites:` the shell-suite
      # consequence; `Re-executes:` declares the consequence for every OTHER runner — jest,
      # pytest, go test, a live read — which had no spelling at all until now, so a brief in
      # such a repository could declare nothing true and the walls held nothing (research R1
      # section 9.1). It sits above `suites` because the table runs longest label first.
      addlabel("re-executes",        "runs",   "", 1)
      addlabel("suites",             "suites", "", 1)
      addlabel("files",              "files",  "", 1)
      addlabel("scope",              "-")
      addlabel("model",              "-")
      addlabel("exit",               "-")
    }
    { text = text $0 "\n" }
    END {
      lc = tolower(text); nh = 0
      for (i = 1; i <= NL; i++) {
        lab = LTXT[i]; from = 1
        while (from <= length(lc)) {
          rest = substr(lc, from)
          if (match(rest, "(^|[^a-z])" lab LSEP[i]) == 0) break
          p = from + RSTART - 1
          vend = p + RLENGTH                                  # first char AFTER the colon
          ls = p
          if (substr(lc, ls, length(lab)) != lab) ls = p + 1  # the guard char matched too
          from = vend
          if (LBOL[i] && !at_line_start(ls)) continue
          clash = 0
          for (j = 1; j <= nh; j++) if (ls <= HVS[j] - 1 && vend - 1 >= HLS[j]) { clash = 1; break }
          if (clash) continue
          nh++; HLS[nh] = ls; HVS[nh] = vend; HK[nh] = LKIND[i]
        }
      }
      # THE DELIVERABLE — declared only, and EXACTLY ONE (epic-16 wave-02 R1 + R7, plan
      # assumptions 48 and 71). The wall never guesses a deliverable: not from prose, and
      # not from among the paths a declared label happens to contain. decl_deliverable()
      # walks every deliverable-kind label hit and returns the paths of the first that
      # yields any; iterating (rather than stopping at firsthit) recovers a real labeled
      # line an earlier pathless deliverable-kind hit shadows — the "...per deliverable:"
      # live specimen.
      #
      # TWO FIELDS OUT, NEVER BOTH. A single path is the contract and prints as
      # `deliverable=`. Several is an ambiguity no reader downstream could detect once a
      # winner was picked (the row would say `declared` either way), so it prints as
      # `deliverable_ambiguous=` — a value nothing lifts onto a row, read by one wall
      # below that refuses the dispatch and hands the author back every candidate. A brief
      # that declares no concrete path prints neither, and the absent-deliverable wall
      # refuses that instead. There is no inference rung and no template fill: a guessed
      # fact is a not-fact, and the whole point of the wall is that it holds only stated
      # facts.
      v = decl_deliverable()
      if (v != "") {
        if (index(v, ",") > 0) print "deliverable_ambiguous=" v
        else                   print "deliverable=" v
      }
      # Duration lifts a BOUNDED value, never a run-on span (Step-6 review C-1/F-3 +
      # A-2): the value ends at its first clause boundary. See bound_field().
      h = firsthit("duration");    if (h > 0) { v = bound_field(spanof(h));    if (v != "") print "duration=" v }
      # The progress path is the first path in its label span. Advisory only — an
      # absent one warns — so a templated or missing progress path lifts nothing and is
      # warned, never filled (the deliverable rule applied to the field with no wall).
      h = firsthit("progress")
      if (h > 0) { v = paths(spanof(h), 1, ""); if (v != "") print "progress=" v }
      # CADENCE IS POSITIONAL, not merely lexical (Step-6 critic F-2). It is the one
      # label with a relaxed separator — whitespace will do, because the contract writes
      # it inside the progress sentence rather than on a line of its own — and that
      # relaxation made every prose occurrence of the word a declaration. So the hit
      # must fall where the contract puts it: after the progress label, inside the span
      # that label owns. The value is bounded, so a run-on ("cadence 2m) claims=...", the
      # live specimen) lifts the duration token alone and never corrupts the field.
      h = firsthit("cadence")
      if (h > 0) {
        ph = firsthit("progress")
        if (ph > 0 && HLS[h] > HLS[ph] && HLS[h] <= spanend(ph, h)) {
          v = bound_field(spanof(h)); if (v != "") print "cadence=" v
        }
      }
      h = firsthit("claims");      if (h > 0) { v = claimpat(spanof(h));      if (v != "") print "claims=" v }
      # The waiver is free text — a REASON, never a path — so it lifts collapsed
      # and whole, ending where the next labelled field begins. An EMPTY value is
      # not printed, which is the whole of the "a reasonless waiver is not a
      # waiver" rule: the wall below reads presence, and presence means a reason.
      # A PLACEHOLDER value is not printed for the same reason read one step
      # further: the wall message hands the author a slot to fill, and a brief
      # that quotes the slot back unfilled has given no reason at all (S-1).
      h = firsthit("waiver")
      if (h > 0) { v = collapse(spanof(h)); if (v != "" && !isplaceholder(v)) print "waiver=" v }
      # THE FILES THE TASK DECLARES IT WILL TOUCH — every distinct path-shaped
      # token in the span, comma-joined, exactly as the deliverable label lifts
      # its candidates. Several paths is the ORDINARY case here rather than an
      # ambiguity: a task touches a set, and the wall does not have to choose
      # among them, it hands the whole set to the impact command.
      h = firsthit("files")
      if (h > 0) { v = paths(spanof(h), FILES_MAX, "Files:"); if (v != "") print "files=" v }
      # THE SUITES THE BRIEF DECLARES, NORMALISED TO BASENAMES at the moment they
      # are lifted, so the declared spelling and the derived one are the same
      # spelling on the row and the writer-side guard compares one alphabet. The
      # explicit waiver `Suites: none` lifts as the literal token `none`, which is
      # a DECLARED empty set — distinguishable on the row from a brief that stated
      # no budget at all, and refused by the guard for every suite.
      h = firsthit("suites")
      if (h > 0) { v = suite_names(spanof(h)); if (v != "") print "suites=" v }
      # THE RUNS THE BRIEF DECLARES, MARKS AND ALL (REQ-1 AC-1.1/AC-1.6). List-valued and
      # self-delimiting: the value is the author-marked runs, space-joined, so the roster row
      # carries the same spelling the author wrote and the writer-side budget arm can compare
      # a real command against an exact marked run. There is no `none` waiver here — the
      # absence of the label IS the absence of the declaration, and `Suites: none` remains the
      # one way a brief waives a budget outright.
      h = firsthit("runs")
      if (h > 0) { v = marked_runs(spanof(h)); if (v != "") print "re_executes=" v }
    }
  ' 2>/dev/null
}

# ---------- D-5 pruning ----------
#
# The same liveness rule task 4/2 established for the attestation
# (hooks/preflight-probe.sh): a session is live iff its transcript still exists
# under CLAUDE_CONFIG_DIR/projects. A LIVE foreign session's roster is never
# touched — that concurrency is the point of D-5 — and a dead session's is
# reclaimed so a stale fleet cannot answer as "ours" (the bb20f616 class). There
# is no legacy single-slot file to prune: this artifact is per-session from
# birth.
ROSTER_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

roster_session_live() {  # <session id>
  local sid="$1" d
  [ -n "$sid" ] || return 1
  [ -d "$ROSTER_CONFIG_DIR/projects" ] || return 1
  for d in "$ROSTER_CONFIG_DIR"/projects/*/; do
    [ -f "${d}${sid}.jsonl" ] && return 0
  done
  return 1
}

prune_stale_rosters() {
  local f base sid
  for f in "$STATE_DIR"/"$ROSTER_PREFIX"*"$ROSTER_SUFFIX"; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    sid="${base#"$ROSTER_PREFIX"}"
    sid="${sid%"$ROSTER_SUFFIX"}"
    [ "$sid" = "$BIONIC_SID" ] && continue
    roster_session_live "$sid" || rm -f "$f" 2>/dev/null
  done
}

# ---------- the row ----------

AGENT_NAME=$(sanitize "$(_jq '.tool_input.name')" 200)
SUBAGENT_TYPE=$(sanitize "$(_jq '.tool_input.subagent_type')" 200)
AGENT_MODEL=$(sanitize "$(_jq '.tool_input.model')" 200)
TOOL_USE_ID=$(sanitize "$(_jq '.tool_use_id')" 200)

# ======================================================= THE NAME-IN-FLIGHT ARM
# (T22, A-orch-33; AC-4.4's prevention half. Chris, first principles: the roster is the
# identity register.)
#
# ONE NAME, ONE AGENT, PER SESSION. Everything downstream keys on the name: the stop gate
# resolves one, `session-poker.sh adopt` prints one as the message address, the landing
# sweep folds the roster to the latest row per name. A second dispatch under a name this
# session already handed out puts two agents behind one row and one address — which is how
# the stop gate came to carry an ambiguity arm, and how a SendMessage reaches the wrong
# process. The cure is the door, not the downstream: refuse here, and none of them ever
# has to choose.
#
# OPEN IS A ROSTER READING, AND ONLY A ROSTER READING (ADR-024, P-A/P-B). `intended`,
# `confirmed` and `identified` are the three live states a dispatch passes through; a name
# is FREE again once an ack taken after its latest launch closes it — `roster_open_names`,
# the one close predicate the budget wall, the sweeper, the stop wall and the poker's
# `adopt_fold` ask (epic-23 wave-20 T2, D10). A `landing-swept/v1|…|state=MET` marker freed a
# name here until then and nowhere else; it frees nothing now. No transcript is read, no live
# set is consulted, and nothing is asked of the model: the fix names a free name rather than
# a chore.
#
# THE SCOPE IS THIS SESSION. Another session's roster reserves nothing here — names are
# unique per session because the roster is per session, which is the scope every other
# reader in the fleet already uses, and a predecessor's finished names must be reusable or a
# long-lived project runs out of them.
#
# PLACED ABOVE THE BRIEF LIFT so a brief the gate is about to refuse for its name is not
# also parsed, and far above the journal, so a refused dispatch never writes a row.
#
# AN UNNAMED DISPATCH IS NOT JUDGED HERE. There is no name to be in flight, and the async
# dispatches that carry none are exactly the ones nothing addresses by name.
if [ -n "$AGENT_NAME" ] && [ -f "$ROSTER_FILE" ] && [ ! -L "$ROSTER_FILE" ]; then
  # ONE PREDICATE, ASKED OF ONE NAME. `roster_open_names` (payload/scripts/lib/roster.sh)
  # answers which names this roster still holds under contract, and the budget wall asks the
  # same function, so the two walls cannot disagree about one name.
  #
  # THE ACK LEDGER IS PASSED, as the budget wall passes it (ADR-034, wave-19 D1). The ack
  # in the sweeper ledger is the ONE terminal state of a name: the Patrol writes it only
  # when a fresh panel confirms the agent gone, and `stop-orders.sh stopped` writes it
  # beside the stop. So a name acked LATER than its last launch is free here exactly as it
  # is free to the budget — one question, one answer — and the predicate's time test keeps
  # an ack older than a relaunch from freeing the live lineage behind it. The status the
  # refusal names is the name's latest live row's: a label read off the roster, not a close.
  #
  # THE RESIDUAL RISK, NAMED: a hand-written ack for an agent that is still working
  # unlocks its name, and a second dispatch under it is the collision this arm exists to
  # prevent. That is a human act on a human's row; no reader here can tell it from a true
  # close without a live panel, which this wall does not have.
  DP_INFLIGHT=""
  if /usr/bin/grep -qxF -- "$AGENT_NAME" <<< "$(roster_open_names "$ROSTER_FILE" "$ACK_LEDGER_FILE")"; then
    DP_INFLIGHT=$(/usr/bin/awk -v want="$AGENT_NAME" -v rpfx="roster-state/${ROSTER_VERSION}|" '
      function kv(line, key,   i, n, parts) {
        n = split(line, parts, "|")
        for (i = 1; i <= n; i++) if (index(parts[i], key "=") == 1) return substr(parts[i], length(key) + 2)
        return ""
      }
      index($0, rpfx) == 1 && kv($0, "name") == want {
        st = kv($0, "status")
        if (st == "intended" || st == "confirmed" || st == "identified") last = st
      }
      END { print (last != "" ? last : "open") }
    ' "$ROSTER_FILE" 2>/dev/null) || DP_INFLIGHT="open"
  fi
  if [ -n "$DP_INFLIGHT" ]; then
    dp_finding "that name is in flight" "use the FILL line's name" \
      "    name: ${AGENT_NAME}   ·   its row on this session's roster: ${DP_INFLIGHT}

A name is an identity here. The stop gate resolves one, \`session-poker.sh adopt\` prints
one as the message address, and the landing sweep folds this roster to the latest row per
name — so two agents under one name is one contract, one address and two processes.

Fix: dispatch under the name the Patrol tick's FILL line printed for this task. It derives
one that is free: the task id, or \`<id>-r<n>\` when that id has already had a run. You never
choose a name yourself. If this row is finished, land it: the Patrol's ack, taken once the
agent is gone, frees the name — a landing marker alone does not."
  fi
fi

# THE ROLE GOES IN WITH THE BRIEF (wave-20 T4; REQ-7, Δ3, Δ9): it decides the run cap.
LIFTED=$(lift_contract_fields "$(_jq '.tool_input.prompt')" "$DP_SUBAGENT")
DP_RUNS_CAP=$(dp_runs_cap "$DP_SUBAGENT")
DP_RUNS_CAP_WORDS=$(dp_runs_cap_words "$DP_SUBAGENT")

field_of() {  # <kind>
  printf '%s\n' "$LIFTED" | grep -m1 "^$1=" | cut -d= -f2-
}
# The count-cap WARN (T19, A-orch-19.1): `suite_names()`/`paths()` print these as ordinary
# LIFTED lines rather than to awk's own stderr (see the comment beside them) — surfaced here,
# unsanitized, through the same `warn()` every other loud-but-passing condition in this file
# uses. Read before anything below narrows `$LIFTED` to a single field.
C_SUITES_CAPWARN=$(field_of suites_capwarn)
[ -n "$C_SUITES_CAPWARN" ] && warn "$C_SUITES_CAPWARN"
C_FILES_CAPWARN=$(field_of files_capwarn)
[ -n "$C_FILES_CAPWARN" ] && warn "$C_FILES_CAPWARN"
# THE RUNS CAP IS NOT ON THIS LIST (T5, REQ-8, D12). Until this wave a fourth declared run
# came through here as `re_executes_capwarn=` — the same warn-and-admit shape as the two
# caps above — so a brief that named four runs was DISPATCHED with three of them on the
# roster and no line telling the author the fourth was silently cut. `SUITES_MAX`/`FILES_MAX`
# bound a ROW FIELD's width, which is a storage limit nobody chose to hit; `RUNS_MAX` bounds
# the DECLARATION itself (`marked_runs()`'s own comment, two screens up), which the author
# chose and can fix at dispatch. `re_executes_dropped=`, read beside `C_SUITES_DROPPED`
# below, carries this fact to a `dp_finding` refusal instead.
C_DELIVERABLE=$(sanitize "$(field_of deliverable)" 300)
# Never both: the extractor prints ONE of these two, so a non-empty list here means
# `deliverable=` is empty and the ambiguity wall below owns the dispatch.
C_DELIVERABLE_CANDIDATES=$(sanitize "$(field_of deliverable_ambiguous)" 900)
C_DURATION=$(sanitize "$(field_of duration)" 80)
C_PROGRESS=$(sanitize "$(field_of progress)" 300)
C_CADENCE=$(sanitize "$(field_of cadence)" 80)
C_CLAIMS=$(sanitize "$(field_of claims)" 300)
C_WAIVER=$(sanitize "$(field_of waiver)" 300)
# THE TWO INSTRUMENT FIELDS (spec AC-20). `Files:` is the declared INTENT — the paths this
# task will touch — and `Suites:` the declared CONSEQUENCE. Both are LIST-valued, and (T18,
# REQ-9/D7) neither is cut at all any more — the max-chars argument below is vestigial for
# these two calls, kept only because `sanitize` requires one positionally; the field name in
# the third argument is what actually exempts them. A brief naming enough files or suites to
# overflow even the widest single-value cap this file has (900) is not a hypothetical: a
# 70-suite `Suites:` line runs to 1.7-1.8 KB, and truncating it silently narrows a budget the
# wall never agreed to. This is the write-side half of the fix `hooks/session-poker.sh`'s
# `clean()` already carries on the read/adopt side (task T9).
C_FILES=$(sanitize "$(field_of files)" 900 files)
C_SUITES=$(sanitize "$(field_of suites)" 900 suites_allowed)
# THE THIRD INSTRUMENT FIELD (epic-23 wave-16, REQ-1, D1, ADR-029). `Re-executes:` is the
# runner-agnostic declaration: the author-marked commands this agent will re-run, marks kept,
# space-joined. List-valued like the two above, so it passes its own field name as
# `sanitize`s third argument — three marked jest invocations run past the 300-char caps the
# single-value fields use, and a cut there would narrow a budget the wall never agreed to.
C_RE_EXECUTES=$(sanitize "$(field_of re_executes)" 900 re_executes)
# WHAT THE LIFT REFUSED TO TAKE, read here so the arm below can name it. The extractor emits
# one of these per bad token (`field_of` returns the first, which is the one the author fixes
# first); a value present means the span carried something that is not a literal command or a
# literal suite name, and the token is in the value.
#
# THE FIELD NAME IS `re_executes` (T5, T4 carry-over). Without it, `sanitize` folds this
# value's `|` to a space — the fold every field but `re_executes` keeps — so a pipe-fault
# token showed a detail that SAID "a pipe" while DISPLAYING a token with none, the exact
# character the classification named having been erased from the evidence beside it. The
# same case in `sanitize` that keeps `re_executes=` itself pipe-intact (immediately above)
# applies here for the identical reason: this value is read by a human, not compared
# against anything, and it is at most one command wide — the 300-char cut this case also
# lifts is not a budget any real single command threatens.
C_RUNS_BAD=$(sanitize "$(field_of re_executes_bad)" 300 re_executes)
C_SUITES_BAD=$(sanitize "$(field_of suites_bad)" 300)
# A Suites: TOKEN THE FILTER DROPPED (T3, REQ-8) — `suite_names()` records the exact
# tokens whose basename is neither `*.test.sh` nor a path-qualified `run.sh`, the literal
# waiver `none` excepted. Read here so the arm below can refuse on it by name, before the
# no-instrument arm gets a chance to see an empty `suites=` and blame the wrong thing.
C_SUITES_DROPPED=$(sanitize "$(field_of suites_dropped)" 300)
# A Re-executes: RUN THE CAP DROPPED (T5, REQ-8, D12) — `marked_runs()` records the exact
# backtick-marked runs past `RUNS_MAX`, mirroring `C_SUITES_DROPPED` immediately above.
# `RUNS_MAX` (3) is unchanged; only the fourth-and-up run's fate is.
C_RUNS_DROPPED=$(sanitize "$(field_of re_executes_dropped)" 300)
# A Suites: SPAN THAT WAS ENTIRELY A COMMENT (T35, critic C9). Not a fault of its own and
# not a fifth guard on the no-instrument arm below — the brief really does carry no budget,
# so it really is refused. This says WHICH of the two shapes the author wrote, so the arm's
# detail can stop telling a brief that declares `Suites:` in as many words that it declared
# no `Suites:` at all.
C_SUITES_COMMENTED=$(sanitize "$(field_of suites_commented)" 8)
# ---------- provenance (epic-16 wave-02, R1 — inference withdrawn) ----------
#
# The deliverable is DECLARED or it is ABSENT. The wall never guesses one from prose,
# so there is no inferred value and no filled template to record — `source=` carries
# exactly one non-empty value, `declared`. The field is kept because
# hooks/session-sweeper.sh reads it to resolve a brief that both declares an artifact
# AND waives it: it treats anything but `inferred` as declared, so `declared` and an
# empty source read the same there, and nothing writes `inferred` any more. Withdrawing
# inference retired the fill machinery (fill_name / slotfree_ancestor) and the
# `inferred` / `templated` / `progress_templated` awk outputs with the guesser they
# served (plan assumption 48, Step-6 critic N-1). A templated deliverable is not a
# concrete path, so it lifts nothing and the absent-deliverable wall refuses it — the
# author is told at dispatch to name it exactly.
C_SOURCE=""
if [ -n "$C_DELIVERABLE" ]; then
  C_SOURCE="declared"
fi

# What is ABSENT is recorded as a field of its own, so a consumer never has to
# guess whether an empty value means "the brief did not say" or "the brief said
# nothing". `model` is deliberately not on this list: the Agent tool inherits
# the orchestrator's model when a dispatch names none, so warning on it would
# fire on the ordinary case and train the reader past the real findings.
#
# NEITHER LIVENESS FIELD IS ON IT EITHER, for the same reason read the other way.
# The subprocess claim is CONDITIONAL-required — declared iff the task backgrounds
# a long command — so its absence is the ordinary case and carries no finding.
# `cadence` is required WITH a progress path, which makes its absence a
# conditional judgment rather than the flat fact this field records; the roster
# reports what the brief said and leaves that reading to the watcher (P3).
ABSENT=""
add_absent() { ABSENT="${ABSENT:+$ABSENT,}$1"; }
[ -n "$AGENT_NAME" ]    || add_absent name
[ -n "$C_DELIVERABLE" ] || add_absent deliverable
[ -n "$C_DURATION" ]    || add_absent duration
[ -n "$C_PROGRESS" ]    || add_absent progress

# ============================================ THE POOL IS SPENT BELOW (D3, principle P-A)
#
# THE INCIDENT, AND THE HALF OF IT WAVE-12 DID NOT FIX. Six dispatch attempts to spawn one
# researcher (2026-09-13). Wave-12 T2 pooled the five BRIEF-SHAPE arms and left every STATE
# arm refusing where it stood, on the argument that a broken environment and a typo in a
# label do not belong in one list. The measurement says otherwise: the six refusals Chris
# counted were the arming wall, then the budget, then the suite allowance — three DIFFERENT
# arms, one fault per attempt, each of them a fact the gate had already read off disk before
# it refused for the one above. The split was drawn in the right place for the wrong
# quantity. What makes two faults reportable together is not that they live in one artifact;
# it is that reading one did not depend on the other being clean (wave-14 REQ-8, D3).
#
# SO EVERYTHING BELOW THE ATTESTATION POOLS. The arming wall, the approval checkpoint, the
# lease wall, the budget, the name-in-flight arm, the five brief-shape arms and the
# one-regression wall all call `dp_finding` and carry on. Principle P-A reads the same way
# at a wall as at a precondition: where the machine already has the facts, the machine
# reports them; asking the model to rediscover them one round trip at a time is a chore on
# the normal path.
#
# THE ONE ARM THAT STAYS FIRST AND ALONE is the attestation (the combined preflight, far
# above). Its subject is the tree every other arm reads out of — the roster, the stamp, the
# plan, the transcript — so a list that set its verdict beside theirs would be reporting
# facts it had just been told not to trust. That is a dependency, not a category.
#
# AN ARM WHOSE INPUT IS ANOTHER ARM'S PRODUCT says so instead of guessing: `dp_not_checked`
# (above) puts `not checked: <arm>, needs <what>` on the same wire, so a second refusal is
# announced rather than sprung (AC-8.2). The containment arm and the ambiguity arm are the
# one pair that can never appear together, and that is by construction rather than by
# ordering: the extractor emits `deliverable=` XOR `deliverable_ambiguous=`.
#
# ONE FINDING RENDERS AS ONE REFUSAL in its arm's own words — the fact, the fix and the
# detail it already wrote — on `deny`, the same wire as several (wave-19 T4, REQ-7, D8).
#
# SEVERAL FINDINGS KEEP THE FIRST ARM'S USER LINE and put one line per remaining fault, the
# not-checked lines and the marked scaffold in `detail`, and that split is forced rather
# than chosen. AC-E1.3 gives the line one fact (100 columns) and one fix (six words, 40
# columns), and the widest arm here already spends 99 of the 100 — so a line that also
# carried a count, or named the other faults, would be REFUSED BY THE RENDERER as
# malformed. Between a line that says "this brief has 3 faults" and one that names a fault
# an author can act on, the second is worth more.
#
# AND THE LIST GOES OUT ON `deny`, WHICH IS THE HALF T2 COULD NOT REACH (its finding
# A-T2.2; ruling A-orch-10, 2026-09-13). On `exit2` there is ONE wire: `refuse`'s channel
# table ships it `detail_to_user=no` under ruling D-1, and what the user stream carries is
# what the model's synthetic tool_result carries — so a collected list emitted there was
# read by nobody, and the six-attempt loop went on running behind a better-built wall.
# `deny` is the same table's row 2: a PreToolUse verdict whose `permissionDecisionReason`
# reaches the model VERBATIM (`model_only=yes`) while the user stream stays the one line.
# The model reads every fault; the reader is still interrupted by a sentence with a
# pointer; neither half is a knob somebody has to know to set.
#
# ONE FINDING TAKES `deny` TOO, and the wire is chosen by AUDIENCE, never by fault count
# (wave-19 T4, REQ-7, D8). Until then a lone finding stayed on `exit2`, so the status of a
# refusal of one kind depended on how many faults the brief — and, through the no-impact
# arm, the repository's own config — happened to add up to (A-T4.8): one fault exited 2,
# two exited 0. Every pooled finding here is a brief-shape or state fault the dispatching
# MODEL fixes by re-writing its brief, so every one goes to the model verbatim on the
# reason field, and the user stream carries the one line. What still differs by count is
# the reason's SHAPE: a lone finding keeps its arm's own detail byte for byte, several
# carry the fault lines and the marked scaffold.
#
# THE THREE ENVIRONMENT SITES STAY ON `exit2`, and their audience is why: the loader
# fail-open (a raw `exit 2` at the top of this file, before `refuse` is even loaded), the
# missing probe (`deny()` → `refuse exit2`) and the probe that ran and failed. Their
# subject is the machine, not the brief — a missing library, an absent probe, a failing
# dependency — and the one who fixes a machine is the human at it, so the detail goes to
# BOTH readers on the one wire that paints it to the user (`detail_to_user=yes`). They are
# also refusals the pool never sees: they fire before any finding can be trusted.
#
# `deny` EXITS 0, AND THAT IS THE BLOCK. The verdict on stdout is what refuses the tool
# call; the status is not. Two consequences this file must respect: nothing else may print
# to stdout on the way here (every other message in this hook is on stderr, deliberately),
# and this call still must sit above the journal, because a refused dispatch that exits 0
# is exactly the shape that would otherwise be recorded as a launch.

# dp_scaffold_marked — the shipped brief scaffold, verbatim, with every label line whose
# field THIS brief left empty suffixed " <ADD>" and every label it already carries left
# exactly as `dispatch.md` wrote it (design ledger D3, D11). Read from the RENDERED
# dispatch.md at refusal time, never transcribed here, with the identical awk
# tests/dispatch-preflight.test.sh's §scaffold-verbatim uses to pull the same block out of
# the same `### Scaffold` fence — so the wire tracks the shipped scaffold's own drift
# instead of a second copy of it. The five labels read the same parsed fields the walls
# above already computed; no brief text is re-scanned.
dp_scaffold_marked() {
  local file="${HOOK_DIR}/../skills/canonical-sdlc/dispatch.md" line label
  [ -r "$file" ] || return 0
  while IFS= read -r line; do
    label="${line%%:*}"
    case "$label" in
      # A MARK IS WHAT THIS BRIEF LACKS, NOT WHAT IT OMITS (wave-14 REQ-6, D8). Three of
      # these labels are halves of a pair, and the scaffold's own comments say so: `Files:`
      # is "writers; omit for a read-only brief", `Deliverable-waiver:` is "only for a report
      # returned by message". Marking each one purely because its own field came back empty
      # told a read-only author to declare files it will not touch and an artifact-bearing
      # author to waive the artifact it just declared — an instruction that, followed, makes
      # the dispatch worse. Each pair is now marked only when NEITHER half is satisfied,
      # which is exactly the condition of the wall that refuses it: the suite-allowance wall
      # asks `-z "$C_FILES" && -z "$C_SUITES"`, the absent-deliverable wall asks
      # `-z "$C_DELIVERABLE" && -z "$C_WAIVER"`.
      #
      # KEYED ON THE LIFTED FIELDS, NEVER ON A LITERAL LINE (A-T2.1 read the other way; R2
      # Q7). A brief whose `Expected artifact:` span names two paths HAS the label and still
      # needs it — the extractor emits candidates and leaves `C_DELIVERABLE` empty — so the
      # question the mark asks is what the walls above already computed, not what the text
      # spelled. `Suites:` keeps the plain rule: a derivation is not a declaration, and this
      # gate is where a repo with no impact command learns to name its set.
      "Expected duration")  [ -n "$C_DURATION" ]    || line="${line} <ADD>" ;;
      # A LABEL WHOSE SPAN WAS READ AND REJECTED IS NOT AN ABSENT LABEL (critic Issue 3,
      # wave-14 T26, pre-existing at 0fe69ed). Several candidates leaves C_DELIVERABLE
      # empty on the SAME contract as zero candidates, but the two are not the same fault
      # — the ambiguity arm above already refused this brief, and marking the line <ADD>
      # here would tell the author to add a line they already wrote.
      "Expected artifact")  [ -n "$C_DELIVERABLE" ] || [ -n "$C_WAIVER" ] || \
                             [ -n "$C_DELIVERABLE_CANDIDATES" ] || line="${line} <ADD>" ;;
      # THE INSTRUMENT LABELS ARE A TRIPLE NOW, NOT A PAIR (epic-23 wave-16, REQ-1 AC-1.8).
      # `Re-executes:` satisfies the suite-allowance wall on its own, so the same rule the
      # `Files:`/`Suites:` pair has followed since wave-14 extends to all three: each is
      # marked only when NONE of the three is satisfied, which is again exactly the condition
      # of the wall that refuses the brief. Marking `Files:` beside a declared set of runs
      # would tell a jest author to name shell files they will not touch — the same wrong
      # instruction D8 removed, arriving by a new route.
      "Files")               [ -n "$C_FILES" ]       || [ -n "$C_SUITES" ] || \
                             [ -n "$C_RE_EXECUTES" ] || line="${line} <ADD>" ;;
      "Suites")              [ -n "$C_SUITES" ]      || [ -n "$C_RE_EXECUTES" ] || \
                             line="${line} <ADD>" ;;
      "Re-executes")         [ -n "$C_RE_EXECUTES" ] || [ -n "$C_SUITES" ] || \
                             [ -n "$C_FILES" ]       || line="${line} <ADD>" ;;
      "Deliverable-waiver")  [ -n "$C_WAIVER" ]      || [ -n "$C_DELIVERABLE" ] || line="${line} <ADD>" ;;
    esac
    printf '%s\n' "$line"
  done < <(/usr/bin/awk '
    /^### Scaffold/            { inb = 1; next }
    inb && /^```/              { fence++; if (fence == 2) exit; next }
    inb && fence == 1          { print }
  ' "$file")
}

# dp_refuse_findings — emit the whole list as ONE refusal and exit, or return having done
# nothing at all. Called once, after the last brief-shape arm; `refuse` owns the exit, so a
# caller cannot fall through it into the journal with findings outstanding. ONE finding and
# SEVERAL both refuse on `deny` — exit 0 with the verdict on stdout, the verdict being the
# block — so the exit status never depends on the fault count (wave-19 T4, REQ-7). ONE
# carries its arm's own detail; SEVERAL carry the fault lines and the marked scaffold
# (see the channel note above).
#
# THE SEVERAL-FAULT WIRE IS ONE LINE PER FAULT, THE NOT-CHECKED LINES, THE MARKED SCAFFOLD
# AND A POINTER — NO RATIONALE (D3, D11, wave-14 REQ-8). The shape wave-13 retired repeated
# a `<detail>` paragraph per fault; a reader with three faults got three lectures before a
# single fix. Each `dp_finding` call above still carries its `<detail>` argument — that text
# stays in the source as the documentation of WHY each arm fires, and `refuse`'s
# single-fault path still emits it unchanged — but it is not collected here.
#
# WHAT WAVE-14 ADDS IS THE FAULT LINES, and they are the reason this wire exists at all.
# Until now the several-fault wire named NO fault except through the scaffold's `<ADD>`
# markers, which can say "this brief has no Files: line" and cannot say "the Patrol is not
# armed" or "the writer budget is full" — and those are precisely the arms REQ-8 pooled.
# One line each, `<fact> (<fix>)`, the same two fields the user line is built from.
#
# THE ARITHMETIC OF AC-8.3, WRITTEN OUT, because the cap in the suite is a formula and a
# reader who cannot rebuild it will widen it instead. One refusal line + one blank + seven
# scaffold lines + one blank + one pointer is wave-13's ten (`wc -l` on the model's reason,
# which counts newlines, so eleven rendered lines read as ten). The first fault IS the
# refusal line and costs nothing. Every fault after it costs one line; so does every
# not-checked line. There is deliberately NO blank between the fault block and the
# scaffold: a separator there would cost a line the budget does not have, and the two
# blocks are already told apart by the scaffold's own labels.
#
# THE PROMPT-ONLY LINE (wave-20 T7, REQ-9 AC-9.3). Every lift above reads
# `tool_input.prompt` and nothing else, so a prompt that says "read the brief at <path>" is
# refused for lines that sit, complete, in a file this wall never opens (triage-B D1,
# driven) — and the scaffold printed below told that author to add lines they had already
# written. One line beside the scaffold says why, which grows the fixed part of the wire by
# exactly one (tests/dispatch-preflight.test.sh §combined and §three-arms carry the sum).
# The single-fault no-deliverable detail carries the same constant, and the shared
# brief-scaffold block (agents-src/blocks/brief-scaffold.md) says the same in its header.
DP_PROMPT_ONLY="The wall reads the prompt text only. A brief file the prompt points at is not read, so copy its scaffold lines into the prompt."
dp_refuse_findings() {
  [ "$DP_FINDING_N" -gt 0 ] || return 0
  if [ "$DP_FINDING_N" -eq 1 ]; then
    refuse deny dispatch "$DP_FIRST_FACT" "$DP_FIRST_FIX" "$DP_FIRST_DETAIL"
  fi
  # `DP_FAULT_LINES` and `DP_NOTCHECKED` each end in their own newline when non-empty and
  # are empty strings otherwise, so this interpolation adds no blank line when either is
  # absent — a two-fault brief with nothing unchecked renders exactly one extra line.
  refuse deny dispatch "$DP_FIRST_FACT" "$DP_FIRST_FIX" \
    "${DP_FAULT_LINES}${DP_NOTCHECKED}$(dp_scaffold_marked)
${DP_PROMPT_ONLY}

See skills/canonical-sdlc/dispatch.md §Dispatch for why each line is required."
}

# ======================================================= THE AMBIGUITY WALL
# (Step-6 R6 critic R6-1; plan assumption 71, completing assumption 48.)
#
# A deliverable label whose span names more than one path has not declared a contract —
# it has offered candidates. R1 resolved that by position (first path, first sentence),
# which is the guess assumption 48 forbids wearing a declaration's clothes: the row said
# `source=declared` whichever file the heuristic landed on, so no reader downstream could
# tell a stated fact from a picked one, and the extra paths in a deliverable sentence are
# usually the files the agent was told to READ. The landing check then stats a path the
# agent never touched, the verdict comes back UNMET, and hooks/landing-gate.sh orders the
# agent to write it — which for "read the auditor report first, then produce yours"
# means overwriting the audit.
#
# So ambiguity is fatal at the one moment it is cheap to fix: dispatch, where the author
# is still holding the brief. The refusal names every candidate rather than ranking them,
# because ranking is the thing being withdrawn.
#
# IT SITS ABOVE THE CONTAINMENT WALL and is not conditioned on the waiver. Above,
# because with several candidates there is no single path to resolve and contain. Not
# waived, because the waiver excuses declaring nothing durable — a brief that names two
# artifacts under a canonical label has declared something, unreadably, and only its
# author knows which one is the contract.
if [ -n "$C_DELIVERABLE_CANDIDATES" ]; then
  _dp_detail="The label's span offers these candidates:
$(printf '%s\n' "$C_DELIVERABLE_CANDIDATES" | tr ',' '\n' | sed '/^$/d; s/^/    /')

A deliverable is the ONE durable artifact this agent is contracted to produce, and
the wall never picks among candidates — whichever it chose would be recorded as a
declared fact, and the landing check would order this agent to write it.

Fix: name exactly one deliverable path in the label —
    Expected artifact: .bionic/docs/record/my-task-notes.md
  References and inputs the agent should READ go outside the label's span: on their
  own line, under Read first: or Scope constraint:, or after a blank line.

Then retry the dispatch."
  dp_finding "the deliverable label names several paths" "name exactly one deliverable" "$_dp_detail"
fi

# ========================================================= THE CONTAINMENT WALL
# (Step-6 review S-2.)
#
# A deliverable is a path this repo's machinery will later STAT, and — on the
# directory branch — WALK. Nothing downstream checks where it points: `abs_path`
# in hooks/session-sweeper.sh prefixes the repo root for a relative path and
# passes an absolute one straight through, so `Expected artifact: /usr/share`
# stats and walks /usr/share on every subagent stop, and the refusal text hands
# the stopping agent the mtime of whatever it found. Both halves are fixed HERE
# rather than there, because dispatch is the moment the path is still editable by
# the author who wrote it: at stop time the only available answer is to refuse an
# agent for a brief it did not write.
#
# Resolution is LEXICAL for the part that does not exist yet — the deliverable is
# by definition not on disk, so there is nothing there to realpath — and PHYSICAL
# for the ancestor that does. Both halves are needed, and the second one is not
# decoration: `git rev-parse --show-toplevel` reports the repo root with symlinks
# resolved, so on a machine where a path component is a link (macOS `/var` ->
# `/private/var`, `/tmp` -> `/private/tmp`) a brief spelling a perfectly good
# in-repo absolute path compares against a root it can never match, and the wall
# false-blocks. Resolving the existing prefix puts both sides in the same terms.
#
# It also means a symlinked ancestor INSIDE the repo that points out of it is
# caught, which is the right answer rather than a bonus: what the landing check
# will stat is where the link lands. An ancestor that cannot be entered at all is
# an ambiguity, and takes §7 direction — fall back to the lexical answer rather
# than refuse on a question this gate cannot answer.
resolve_in_repo() {  # <path> -> absolute, `.`/`..` folded, existing prefix physical
  local p="$1" abs out part had_f head rest phys
  case "$p" in
    /*) abs="$p" ;;
    *)  abs="$BIONIC_ROOT/$p" ;;
  esac
  case "$-" in *f*) had_f=1 ;; *) had_f=0 ;; esac
  set -f   # a `*` inside a brief-supplied path is a character, never a glob
  out=""
  local IFS=/
  for part in $abs; do
    case "$part" in
      ''|.) ;;
      ..)   out="${out%/*}" ;;
      *)    out="$out/$part" ;;
    esac
  done
  unset IFS
  [ "$had_f" -eq 1 ] || set +f
  out="${out:-/}"

  head="$out"; rest=""
  while [ -n "$head" ] && [ ! -d "$head" ]; do
    rest="${head##*/}${rest:+/$rest}"
    head="${head%/*}"
  done
  if [ -n "$head" ]; then
    phys=$(cd "$head" 2>/dev/null && pwd -P)
  else
    phys="/"
  fi
  [ -n "$phys" ] || { printf '%s' "$out"; return; }
  case "$phys" in
    /) printf '%s' "/$rest" ;;
    *) printf '%s' "${phys}${rest:+/$rest}" ;;
  esac
}

if [ -n "$C_DELIVERABLE" ]; then
  D_ABS=$(resolve_in_repo "$C_DELIVERABLE")
  case "$D_ABS" in
    "$BIONIC_ROOT"/*) : ;;
    *)
      _dp_detail="    ${C_DELIVERABLE}
  resolves to ${D_ABS}, which is not under ${BIONIC_ROOT}.

The landing check stats — and, for a directory, walks — whatever this names,
on every stop of the agent that owns it. It must be a path inside this repo.

Fix: name a repo-relative artifact path in the brief —
    Expected artifact: .bionic/docs/record/my-task-notes.md

Then retry the dispatch."
      dp_finding "the deliverable is outside this repository" "name a path inside the repo" "$_dp_detail"
      ;;
  esac
fi

# ======================================================= THE ABSENT-DELIVERABLE WALL
# (user-directed, epic-15 post-wave-04: "A wall. It should be a wall.")
#
# THE ONE PLACE below the verdict where this file changes the verdict, and it is
# deliberately narrow: exactly one absent field refuses, and only when the brief
# offers no waiver. Everything else on this path stays advisory — an absent
# progress path warns, an absent duration warns.
#
# Why this field and not the others: every downstream check the wave built is
# keyed on a durable artifact. The sweeper's landing verdict stats the
# deliverable path; the stop gate asks whether the thing the agent was
# sent to produce exists. A dispatch that names none is unfalsifiable by
# construction — nothing to stat when it reports done, nothing left behind when
# it dies quietly — and a warning was never going to fix that, because the
# warning arrives in the same breath as the launch it failed to prevent.
#
# THE WAIVER IS THE ESCAPE, and it is deliberately IN THE BRIEF rather than an
# environment variable or a flag: a waiver written into the dispatch text is
# lifted by the same extractor as every other contract field, lands in the roster
# row beside the absence it excuses, and is echoed on stderr as it passes. There
# is no way to take it that leaves no record — which is the property that makes
# refusing safe to live with. A waiver with no reason is not a waiver (the
# extractor prints nothing for an empty span), so the escape always costs a
# sentence.
#
# THIS SITS ABOVE the symlink and prune housekeeping on purpose. A hostile or
# merely broken roster path must not be able to OPEN this wall by making the
# journal step bail early — the same reasoning §8 applies to the attestation
# path, read here in the refuse direction.
if [ -z "$C_DELIVERABLE" ] && [ -z "$C_WAIVER" ]; then
  if [ -n "$C_DELIVERABLE_CANDIDATES" ]; then
    # THE AMBIGUITY ARM ALREADY REFUSED THIS BRIEF (critic Issue 3, wave-14 T26;
    # pre-existing at 0fe69ed — both arms already called `dp_finding` there). A label
    # offering several candidates leaves C_DELIVERABLE empty on purpose, because the
    # ambiguity arm above never guesses among them — and this arm's own "nothing was
    # declared" fact would then contradict the one already on the wire: "the deliverable
    # label names several paths" and "this brief names no deliverable" cannot both be
    # true. D3's own rule applies to this pair too: an arm whose input is another arm's
    # product says so instead of guessing.
    dp_not_checked "deliverable" "one path"
  else
    _dp_detail="An agent with nothing durable to produce cannot be checked on: there is no
path to stat when it reports done, and nothing left behind if it dies quietly.

Fix: declare a durable artifact path with a canonical label —
    Expected artifact: .bionic/docs/record/my-task-notes.md
  Any of these labels lifts one: Expected artifact(s), Deliverable(s), Artifact(s).
  Name a concrete path — the wall never guesses one from prose, and a <slot> is not a name.
  ${DP_PROMPT_ONLY}

Or waive it — the reason is recorded on the session roster either way:
    Deliverable-waiver: <why this dispatch produces nothing durable>

Then retry the dispatch."
    dp_finding "this brief names no deliverable" "add an Expected artifact: line" "$_dp_detail"
  fi
fi

# ===================================== A DECLARATION IS LITERAL TEXT (REQ-1 AC-1.4)
# (epic-23 wave-16, D1/D3, ADR-029.)
#
# THE RULE THE PROSE HAS PROMISED SINCE WAVE-01, now enforced. The suite-allowance
# refusal below has always ended "one path per token, no shell variables … a name that
# is still a variable when a hook sees it can be neither derived from nor checked
# against anything" — and nothing at dispatch checked it (research R1 Q3). A token
# `tests/$X.test.sh` was basenamed to `$X.test.sh` and lifted onto the roster row as a
# budget entry, where the writer-side guard then refused every command the agent ran,
# with its own honest message about an unexpanded name, 40 minutes after the moment the
# author could have fixed it in a word.
#
# BOTH SPELLINGS, ONE ARM. `Re-executes:` gains the rule at birth and `Suites:` gains it
# here, because a wall whose prose is true for one of two spellings of one idea is a wall
# nobody can read. A run also refuses on an UNQUOTED `|` (shell plumbing is not one run; a
# quoted one is an ordinary argument and is admitted — T4, REQ-7), on a newline (the marks
# never closed on their own line), or on an angle bracket that is not a whole slot (a
# redirection — wave-16 T25, walk §W7).
#
# THE TOKEN IS IN THE DETAIL, NOT THE ONE LINE. A command is arbitrarily long and the
# refusal line is bounded at 100 columns (AC-E1.3); the fact fits the line, the evidence
# goes where the rest of every Fix block goes.
if [ -n "$C_RUNS_BAD" ]; then
  _dp_detail="The span offered this, and it is not a command that can be re-run:
    ${C_RUNS_BAD}

A declared run is matched against what the agent actually types, before any shell has
expanded anything — so a name that is still a variable here can be neither derived from
nor checked against anything, and a run holding an unquoted pipe, a redirection, or a line
break is not one run. Declare the command; leave the shell plumbing off the span. A pipe
INSIDE quotes is an ordinary argument and is admitted, so a regex alternation needs no
rewriting. An unfilled \`<slot>\` on its own is guidance and is ignored, but a bracket
anywhere else in the run is read as redirection.

Fix: mark each run with backticks, on a line of its own, at most ${DP_RUNS_CAP_WORDS} —
    Re-executes: \`npx jest --testPathPatterns 'x'\`, \`pytest tests/unit\`

Then retry the dispatch."
  dp_finding "a declared run is not a literal command" "spell each run literally" "$_dp_detail"
fi

# AN OVER-CAP Re-executes: BRIEF IS REFUSED (T5, REQ-8, D12; mirrors the Suites: dropped-
# token refusal directly below, wave-17 T3). Until now a fourth backtick-marked run fell
# off `marked_runs()` with a loud `warn()` line but the dispatch was still ADMITTED — the
# roster row carried three of the four runs the author declared, and the fourth was refused
# by the writer-side budget arm 40 minutes later as undeclared, for a fact the author was
# never told at dispatch. `RUNS_MAX` (3) is unchanged; a brief within the cap never reaches
# this arm.
if [ -n "$C_RUNS_DROPPED" ]; then
  _dp_detail="The Re-executes: span named more runs than the ${DP_RUNS_CAP}-run cap admits for
this role (${DP_SUBAGENT:-unnamed}), and this one was dropped:
    ${C_RUNS_DROPPED}

Every declared run goes on the roster row, and the writer-side budget arm compares the
agent's own command against exactly that set — a run dropped here is a command that would
be refused there 40 minutes later, for running exactly what its own brief had named.

The cap of three is the auditor's, from its mandate's \"<=3 re-executions\"; every other
role may declare as many runs as a Suites: line may name suites (${DP_SUITES_MAX}).

Fix: mark at most ${DP_RUNS_CAP_WORDS} runs with backticks, one line —
    Re-executes: \`npx jest --testPathPatterns 'x'\`, \`pytest tests/unit\`, \`go test ./...\`

Then retry the dispatch."
  dp_finding "Re-executes: line exceeds the ${DP_RUNS_CAP}-run cap" "declare at most ${DP_RUNS_CAP_WORDS} runs" "$_dp_detail"
fi

if [ -n "$C_SUITES_BAD" ]; then
  _dp_detail="The Suites: span offered this token, and it is not a suite name:
    ${C_SUITES_BAD}

The declared set goes on the roster row and the writer-side guard compares the agent's own
command against it, both of them as literal text — so a token that is still a variable when
a hook sees it can be neither derived from nor checked against anything.

Fix: spell each suite literally, one path per token —
    Suites: tests/one.test.sh, tests/two.test.sh

Then retry the dispatch."
  dp_finding "a declared suite is not a literal name" "spell each suite literally" "$_dp_detail"
fi

# A DROPPED Suites: TOKEN IS A REFUSAL (T3, REQ-8; wave-17, research R3 §C1.4 option 3 — a
# repair of the EXISTING basename filter above, no new I/O, D11-compliant). Until now a
# token whose basename was neither `*.test.sh` nor a path-qualified `run.sh` — a jest spec,
# a pytest module, a bare `run.sh` — fell off `suite_names()` in total silence: `suites=`
# ended up empty, and a brief naming only such tokens then met the UNRELATED no-instrument
# arm below ("this brief declares no Files: and no Suites:") for having declared something
# real. This puts the drop on the SAME channel the unexpanded-variable arm above already
# uses, named, and — because the guard on the no-instrument arm below also checks this
# field — that arm is never reached by a brief that named a token here.
#
# ONE DROPPED TOKEN IS ENOUGH; THE WHOLE SPAN NEED NOT BE DROPPED (walk W4b — the code was
# always stricter than this note). `Suites: tests/one.test.sh tests/unit/foo.spec.ts`
# refuses, and should: a half-dropped line is a line whose budget is not what its author
# wrote, and the writer-side guard would refuse the jest run 40 minutes later anyway.
# What is NOT a dropped token: the literal waiver `none`, and anything from the first `#`
# onwards — `suite_names()` stops the scan there (T23, review R1), so a trailing scaffold
# comment reaches neither this arm nor the roster row.
if [ -n "$C_SUITES_DROPPED" ]; then
  _dp_detail="The Suites: span offered this, and its basename is not one this repo's shell
suite runner can run — neither \`*.test.sh\` nor a path-qualified \`run.sh\`:
    ${C_SUITES_DROPPED}

A jest spec, a pytest module or any other non-shell test file is never run by this label;
it dropped off the row in silence until now, and the writer's own command was then refused
40 minutes later for running exactly what its brief had named.

Fix: where the tests are not shell suites, name the command itself under Re-executes:,
marked with backticks —
    Re-executes: \`npx jest --testPathPatterns 'x'\`, \`pytest tests/unit\`

Or, where they are shell suites, spell the *.test.sh path —
    Suites: tests/one.test.sh

Then retry the dispatch."
  dp_finding "Suites: names a file the shell runner cannot run" "use Re-executes:" "$_dp_detail"
fi

# ============================================== THE SUITE-ALLOWANCE WALL (AC-20)
# (seed .bionic/docs/ideas/suite-allowance-wall.md items 1-2; design ledger D2,
# Chris 2026-09-05 "Option 2": a brief declares INTENT, the machine derives the
# consequences.)
#
# THE INCIDENT. Two writers finished their own hooks green at ~45 minutes and then
# spent 40 more re-running the entire test tree one suite at a time, in parallel, on
# an 8 GB machine at load 10. Their briefs said "run impacted suites only; never
# tests/run.sh; run X, Y, Z as consumers", and "consumers" was read as "everything".
# Prose in a brief is a wish. Only a wall binds a writer.
#
# WHAT THE BRIEF DECLARES. `Files:` — the paths this task will touch. That is intent,
# and it is the only thing the author reliably knows at dispatch. The CONSEQUENCE (which
# suites read those paths) is a fact about the tree, and D2 gave the tree ownership of it:
# `impact-command:` in .bionic/config.yaml names the derivation, the wall runs it over the
# declared paths, and the answer goes on the roster row for the writer-side guard to hold
# the agent to.
#
# `Suites:` IS THE OTHER HALF, not a legacy spelling. bionic runs in repositories that
# have no impact command and never will, and there the author is the only one who can
# state the set — so a declared list is a first-class input, recorded as
# `suites_source=declared` so no reader downstream mistakes a stated set for a derived
# one. It also WINS over a derivation when a brief carries both: `Suites: none` is the
# waiver, and a waiver that a derivation could overrule is not a waiver.
#
# A BRIEF WITH NEITHER IS REFUSED, and that is the whole wall. Everything else here is
# bookkeeping: without one of the two labels there is no budget on the row, and a guard
# with no budget to enforce is the prose the incident already proved does not bind.
#
# `Re-executes:` IS THE THIRD WAY THROUGH (REQ-1 AC-1.3, D1). The field is a budget
# declaration in exactly the sense this wall means: a closed set of commands, on the roster
# row, for the writer-side guard to hold the agent to. It is the only declaration available
# to an agent in a repository whose tests are not shell suites, so refusing a brief that
# carries it for "declaring no instrument" would be the wall contradicting itself.
#
# A BRIEF THAT NAMED A DROPPED TOKEN DECLARED SOMETHING (T3, REQ-8). `C_SUITES_DROPPED`
# is checked here too, so a `Suites:` line that lost ANY token to the filter above — not
# only one that lost every token — never falls through to this arm's "declares no Files:
# and no Suites:" (walk W4b). That refusal is the suite-drop arm's above, named by the
# actual token, not this one's guess that nothing was declared at all.
if [ -z "$C_FILES" ] && [ -z "$C_SUITES" ] && [ -z "$C_RE_EXECUTES" ] && [ -z "$C_SUITES_DROPPED" ]; then
  # THE CLAUSE GOES FIRST, NOT LAST (critic C9). refuse.sh folds a detail to twelve lines on
  # the channel that hands it to a reader who did not ask for it, and this detail is already
  # longer than that, so a sentence appended at the end is bytes nobody sees. One clause, at
  # the top, where the fold cannot reach it; the verdict and the fix line are untouched.
  _dp_suites_comment=""
  if [ -n "$C_SUITES_COMMENTED" ]; then
    _dp_suites_comment="Suites: was declared, but its span is a comment, so it named nothing — write \`none\` to waive.

"
  fi
  _dp_detail="${_dp_suites_comment}An agent with no declared instrument runs whatever it decides to run. Two writers
read \"run the impacted suites\" as the whole tree and spent 40 minutes each
re-proving the world; the budget only binds when it is on the roster row.

Fix: declare the files this task will touch, on a line of its own —
    Files: path/one.sh, path/two.sh
  The impact command named in .bionic/config.yaml derives the suites from them.

Where no impact command is configured, name the closed set yourself —
    Suites: tests/one.test.sh, tests/two.test.sh

Where the tests are not shell suites, name the commands themselves instead — each marked
with backticks, at most ${DP_RUNS_CAP_WORDS} —
    Re-executes: \`npx jest --testPathPatterns 'x'\`, \`pytest tests/unit\`

Or waive the budget for a brief that runs no suite at all —
    Suites: none

Either way: one path per token, no shell variables. Both labels are read out of the
brief TEXT, before any shell has expanded anything, and the writer-side guard reads
its command the same way — a name that is still a variable when a hook sees it can
be neither derived from nor checked against anything.

Then retry the dispatch."
  dp_finding "this brief declares no Files: and no Suites:" "declare Files: or Suites:" "$_dp_detail"
fi

# AN AUDITOR MAY WAIVE NOTHING (T6, REQ-4 AC-4.3/4.4; D6). `Suites: none` is a legitimate
# waiver for a role that never runs a suite — a researcher reads, a test-runner reports,
# and both pass through unchanged (AC-4.4). An auditor's whole job at Step 5 is to
# FALSIFY the matrix's evidence, which for a hermetic-tier row means re-running the named
# suite (spec §Eval design, `## Verification Matrix` "auditor" column) — a `Suites: none`
# auditor brief cannot do the one thing its role requires, so the waiver that is silence
# for every other reading role is a defect here.
#
# ROLE MATCHED WHOLE, ON `subagent_type`, THE SAME WAY THE WRITER-CLASS ARM ABOVE DOES —
# never on the brief's prose, which is a wish, not a wall. Both the fully-qualified name
# this repo's roster actually carries (`bionic:auditor`) and the bare role word are
# matched, since a brief authored by hand routinely drops the `bionic:` prefix the harness
# itself never does.
#
# `$C_SUITES` IS THE LIFTED FIELD, ALREADY NORMALISED. `suite_names()` (above) prints the
# literal token `none` for a whole-word waiver and nothing else ever equals it — a brief
# that both waives and lists suites cannot reach this arm, because `Suites:` is a single
# labelled span and its lift is one value, the waiver or the list, never both.
case "$DP_SUBAGENT" in
  bionic:auditor|auditor)
    # THE PREDICATE IS NOW "NO SUITES AND NO DECLARED RUNS" (epic-23 wave-16, REQ-1 AC-1.2,
    # D1, ADR-029). An auditor in a jest, pytest or go repository has a real re-execution to
    # declare and no shell suite to name it with; refusing that brief was this arm asking for
    # a spelling the repository does not have, and the fix text it printed named the only
    # spelling that could not answer. `Suites: none` beside a non-empty `Re-executes:` is an
    # auditor that waived the shell-suite budget and declared what it will actually re-run,
    # which is the whole of what this arm exists to require.
    if [ "$C_SUITES" = "none" ] && [ -z "$C_RE_EXECUTES" ]; then
      dp_finding "an auditor names no suites" "name the suites to re-execute" \
        "Role: ${DP_SUBAGENT}

An auditor's Step-5 verdict is a re-run of the evidence, not a read of it — a hermetic-tier
row in the matrix is falsified by running the suite the row names, and a brief that waives
every suite gives the auditor nothing to run.

Fix: name what the matrix binds this auditor to re-execute, on a line of its own. For
shell suites —
    Suites: tests/one.test.sh, tests/two.test.sh

  For any other runner, name the commands themselves, each marked with backticks, at
  most three —
    Re-executes: \`npx jest --testPathPatterns 'x'\`, \`pytest tests/unit\`

Then retry the dispatch."
    fi
    ;;
esac

# ---------- the derivation ----------
#
# THE COMMAND IS CONFIGURATION, THE PATHS ARE THE BRIEF. The command is word-split (it is
# `bash tests/lib/impact.sh` — a runner and a script, not one word) and the declared paths
# go in as separate arguments, quoted. Nothing is eval'd: a path lifted out of a brief is
# author-supplied text, and word-splitting it into a command line is how a `Files:` line
# carrying a semicolon becomes a command. `ispath` has already rejected anything without a
# slash, but the shape of the guard here does not depend on that check holding.
#
# THE COMMITTED DEFAULT IS ABSENCE (plan A-8). `.bionic/config.yaml` is machine-local, so a
# fresh clone and every other repository bionic runs in take the declared path.
#
# A DERIVATION THAT FAILS OR ANSWERS NOTHING LEAVES `suites_allowed=` EMPTY, and empty is
# the third state: not a set, and not the `none` waiver either. The writer-side guard reads
# it as "no budget was stated" and stands aside for a named suite while still refusing
# tests/run.sh, so a broken impact command costs an over-wide instrument rather than an
# agent that can run nothing. The operator is told at dispatch, which is the moment the
# config is still fixable.
IMPACT_COMMAND=$(config_value "$BIONIC_ROOT" "impact-command" "")
SUITES_ALLOWED=""
SUITES_SOURCE=""
if [ -n "$C_SUITES" ]; then
  SUITES_ALLOWED="$C_SUITES"
  SUITES_SOURCE="declared"
elif [ -z "$C_FILES" ]; then
  # NOTHING TO DERIVE FROM, AND THE ABSENCE IS ALREADY A FINDING. Before the arms
  # collected, this branch was unreachable: the wall above exited on a brief carrying
  # neither label, so anything past it held at least one of them. It is reachable now,
  # and it must stay silent — running the derivation over an empty argument list would
  # warn that "the impact command derived no suites" (it was never asked), and falling
  # into the arm below would report a missing `impact-command:` as a SECOND fault when
  # the brief's own missing `Files:` is the one the author fixes. One fault, one finding.
  :
elif [ -n "$IMPACT_COMMAND" ]; then
  _old_ifs="$IFS"; IFS=','; set -f
  # shellcheck disable=SC2086
  set -- $C_FILES
  set +f; IFS="$_old_ifs"
  _impact_out=""
  if [ "$#" -gt 0 ]; then
    # A BOUND THE HOOK BUILDS ITSELF (review-c C-16). The derivation is the whole of the
    # gate's cost: ~0.3 s without it, ~2.9-3.1 s with it on an idle tree, and 5.06-6.51 s
    # measured while this wave's own writers were running — which is exactly the condition
    # under which a wave dispatches.
    #
    # WHY THE BOUND IS A REFUSAL AND NOT A FALLBACK. A PreToolUse hook killed on the CLI's
    # timeout does NOT exit 2. The dispatch proceeds, no roster row is written, and the
    # writer runs with no budget at all — the wall defeated by the cost of the wall. That is
    # the one failure this arm cannot have, so the overrun is refused here, in time, with a
    # message. The other derivation failures stay as they were (empty budget + a warning):
    # a command that answers nothing has still answered.
    #
    # WHICH IS WHY THE BOUND MUST SIT STRICTLY UNDER THIS HOOK'S REGISTRATION, MARGIN NAMED
    # (wave-14 D2, ratified; D1 moved both numbers). hooks/hooks.json registers this hook at
    # `"timeout": 15` and `IMPACT_BOUND_S` is 10, five seconds clear. A bound above the
    # registration cannot refuse anything in production, however many times this file's
    # suite drives it to a refusal — the suite has no CLI timeout and the machine does
    # (A-T6.5). The pair is pinned where the two files meet: cross-gate-agreement §L.4c.
    #
    # BUILT, NOT BORROWED. bionic's command discipline forbids a `timeout`/`gtimeout` binary
    # and macOS ships neither, so the bound is a backgrounded child and a `kill -0` poll.
    # THE BOUND IS NOT THIS FILE'S (wave-14 REQ-7, D4). `IMPACT_BOUND_S` lives in
    # lib/bounds.sh and is read by both legs of the fleet — this wall, once per dispatch,
    # and lib/stop.sh's landing sweep, once per sweep. Both carried their own `6` under
    # their own header, and two copies of a constant do not disagree loudly: they disagree
    # the next time a wave moves one of them, and what ships is a tree whose two legs mean
    # different things by "bounded" while every message quotes its own half (R2 Q8 found the
    # twin). Read the library's header before touching the number — it is a HANG GUARD now,
    # not a cost budget, and the answer to a slow derivation is the cache, never this.
    #
    # SOURCED THE WAY lib/stop.sh SOURCES IT, guarded on the thing it defines so a caller
    # that already has it pays nothing, and LAZILY — here, at the one arm that spends it,
    # rather than at file scope beside the loader's own seven libraries. Every dispatch that
    # declares `Suites:` outright reaches neither this branch nor this read.
    if [ -z "${IMPACT_BOUND_S:-}" ]; then
      # shellcheck source=/dev/null
      . "$BIONIC_LIB/bounds.sh"
    fi
    # THE WAIT ENDS ON A CLOCK, NOT ON A COUNT OF POLLS (wave-14 T34). This loop used to
    # spend a tick budget — `IMPACT_BOUND_TICKS=$(( IMPACT_BOUND_S * 10 ))`, one tick per
    # `sleep 0.1` — and call the budget the bound. It is not the bound. `sleep` is an
    # external binary, so every tick pays a fork and an exec on top of the 100 ms it
    # sleeps: measured at 115.3 ms a tick on a quiet Mac (T34 §2), which makes a stated
    # 20 s bound a 23.0-23.2 s wait and a stated 5 s bound a 5.77 s wait, while the
    # refusal below quotes the stated number. That is the same lie the derived budget was
    # written to prevent, one layer down — the literal was fixed, the RATE was not.
    #
    # AND THE ERROR IS PROPORTIONAL, WHICH IS THE PART THAT MATTERS. A fixed 15% would
    # only be untidy. Under the load 8-12 a wave actually dispatches at, each tick costs
    # more and the realized wait grows with it — so the one guard whose job is to stop a
    # wedged session waiting gets slower exactly when the session is wedged. A hang guard
    # cannot be denominated in a unit that stretches under the condition it guards.
    #
    # `SECONDS` IS THE CLOCK, AND IT COSTS NOTHING. Assigning it zeroes bash's own
    # elapsed-time counter and reading it is a shell builtin — no second fork per tick, on
    # a path this wave is measuring for latency. /bin/bash is 3.2 on a Mac, which has
    # neither `EPOCHREALTIME` nor `printf %(%s)T`, and bionic's command discipline forbids
    # a `timeout` binary; `date +%s` would cost a fork per tick to buy the same
    # whole-second resolution `SECONDS` gives free. Nothing else in this hook or in the
    # libraries it sources reads `SECONDS`, so zeroing it here takes nothing from anyone.
    #
    # THE RESOLUTION IS A WHOLE SECOND, AND IT ROUNDS TOWARD WAITING LESS. `SECONDS` is
    # integer, and the assignment below lands at an arbitrary point inside a second, so the
    # wait ends somewhere in [bound-1, bound] — never past the number the refusal quotes.
    # For a hang guard that is the correct direction to be wrong in: a guard that fires a
    # little early costs a re-dispatch, and one that fires late costs the thing the guard
    # exists for. The bound itself is NOT this file's to move (lib/bounds.sh, D4); this
    # changes only whether the wait honours it.
    #
    # `sleep 0.1` STAYS the poll cadence. It is what makes a prompt derivation noticed
    # promptly, and with the clock deciding, its cost no longer accumulates into the bound.
    _impact_tmp="${TMPDIR:-/tmp}/bionic-impact-$$-${RANDOM}.out"
    # shellcheck disable=SC2086  # the COMMAND is configuration and is meant to split
    ( cd "$BIONIC_ROOT" 2>/dev/null && $IMPACT_COMMAND "$@" >"$_impact_tmp" 2>/dev/null ) &
    _impact_pid=$!
    SECONDS=0
    _impact_overran=0
    while kill -0 "$_impact_pid" 2>/dev/null; do
      if [ "$SECONDS" -ge "$IMPACT_BOUND_S" ]; then
        kill -TERM "$_impact_pid" 2>/dev/null
        _impact_overran=1
        break
      fi
      sleep 0.1
    done
    wait "$_impact_pid" 2>/dev/null
    if [ "$_impact_overran" -eq 1 ]; then
      rm -f "$_impact_tmp"
      _dp_detail="The command named by \`impact-command:\` in .bionic/config.yaml turns the paths this
brief declared into the set of suites the agent may run. This hook is registered with a
timeout of its own in hooks/hooks.json, and a hook killed on that timeout does NOT refuse:
the dispatch would proceed with no roster row at all, and the writer would run with no
budget — the wall defeated by the cost of the wall. So the derivation is bounded here,
strictly under that registration.

  command: $IMPACT_COMMAND
  paths:   $*
  bound:   ${IMPACT_BOUND_S}s

Fix: narrow \`Files:\` to the paths this task really writes, or name the closed set
directly with \`Suites:\` — a declared set needs no derivation at all. If the command
itself has become slow, that is the thing to fix: it runs on every dispatch."
      dp_finding "the impact command did not answer" "fix impact-command in config.yaml" "$_dp_detail"
      # NOTHING DERIVED MEANS NOTHING TO JUDGE AGAINST (AC-8.2). The one-regression wall
      # below reads this set for `run.sh`; an overrun leaves it unbuilt, and the author
      # deserves to know that wall is still waiting rather than to meet it next attempt.
      dp_not_checked "one-regression" "a suite set"
      dp_not_checked "floor-once" "a suite set"
      # THIS SPEND IS EARLY (Step-6 architecture review §2.2). Every other arm pools into
      # one `dp_refuse_findings` at the bottom of the file; this branch spends here instead
      # because the overrun destroys the one-regression wall's own input and there is
      # nothing below THIS branch (in file order) but that wall. That is true only by arm
      # order, not by construction — an arm added below this point that does NOT depend on
      # the derivation would be silently skipped on every overrun, with no test to catch
      # it. Any arm added below here must be dependent on the derivation, or must be
      # pooled above this spend instead.
      dp_refuse_findings
    fi
    _impact_out=$(cat "$_impact_tmp" 2>/dev/null) || _impact_out=""
    rm -f "$_impact_tmp"
  fi
  SUITES_ALLOWED=$(printf '%s\n' "$_impact_out" | awk -F'\t' '$1 != "" { print $1 }' | sort -u | tr '\n' ' ')
  SUITES_ALLOWED="${SUITES_ALLOWED% }"
  SUITES_SOURCE="derived"
  if [ -z "$SUITES_ALLOWED" ]; then
    warn "the impact command derived no suites from the declared files; the row records an empty budget: $IMPACT_COMMAND"
  fi
else
  # `Files:` alone in a repository with no impact command states an intent nothing can turn
  # into a budget. AC-20: where no impact command is configured the wall requires the
  # explicit list. Refused rather than passed with an empty set, because the author is
  # holding the brief and one line fixes it.
  _dp_detail="\`Files:\` states which paths the task will touch. Turning that into the set of
suites the agent may run is the tree's job, and this repository has not named the
command that asks it.

Fix: name the closed set in the brief instead —
    Suites: tests/one.test.sh, tests/two.test.sh

Or configure the derivation once, in .bionic/config.yaml —
    impact-command: bash tests/lib/impact.sh

Then retry the dispatch."
  dp_finding "no impact command is configured here" "set impact-command in config.yaml" "$_dp_detail"
fi

# ============================================= THE ONE-REGRESSION WALL (AC-24)
# (seed item 4; the standing ruling "one regression means one" made mechanical.)
#
# The full tree is run ONCE per run, at integration close, by one dispatched runner. A
# second runner in the same run is not a mistake the orchestrator makes in ignorance — it
# is the shape a re-proof takes after a merge, a bump or a panic — so the wall does not
# forbid it, it makes it COST A WRITTEN REASON in the plan, where a reader will find it
# next to the run it explains.
#
# NEWER IS COUNTED, NOT TIMED. "A `regression-cause:` line newer than the last regression
# row" cannot be read off a clock: the plan file is rewritten after every task, so its
# mtime is newer than everything and the rule would be vacuous within minutes. It is read
# as a LEDGER instead — the Nth full-tree dispatch of a run needs the (N-1)th cause line
# on the plan — which is monotone, hermetic, and forces one new sentence per extra
# regression rather than one sentence that licenses all of them.
#
# ROWS ARE COUNTED BY NAME. hooks/execution-recorder.sh appends a `status=confirmed` copy
# of a row it did not write from scratch, so one dispatch is two or more lines carrying the
# same budget; counting lines would refuse the second half of the first regression.
#
# PLAN-FREE SESSIONS SKIP IT. An engaged session with no bound plan has nowhere to write a
# cause, and the budget wall above already binds every such dispatch.
regression_rows() {  # -> the number of DISTINCT agent names already dispatched with run.sh
  [ -f "$ROSTER_FILE" ] || { printf '0'; return 0; }
  [ -L "$ROSTER_FILE" ] && { printf '0'; return 0; }
  awk -F'|' -v ver="roster-state/${ROSTER_VERSION}" '
    $1 != ver { next }
    {
      name = ""; allowed = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^name=/)                name    = substr($i, 6)
        else if ($i ~ /^suites_allowed=/) allowed = substr($i, 16)
      }
      if (name == "" || allowed == "") next
      n = split(allowed, parts, " ")
      for (j = 1; j <= n; j++) if (parts[j] == "run.sh") { seen[name] = 1; break }
    }
    END { c = 0; for (k in seen) c++; print c }
  ' "$ROSTER_FILE" 2>/dev/null
}
regression_causes() {  # -> how many `regression-cause:` lines the plan carries under ## SDLC State
  [ -n "$PLAN" ] && [ -f "$PLAN" ] || { printf '0'; return 0; }
  awk '
    /^## SDLC State/ { instate = 1; next }
    /^## / { instate = 0 }
    instate && /^[ \t]*regression-cause[ \t]*:/ { c++ }
    END { print c + 0 }
  ' "$PLAN" 2>/dev/null
}
# THE ARM'S OWN DEPENDENCY, STATED (AC-8.2). This wall's whole input is the set built
# above — declared or derived — and a brief that produced none leaves it unable to answer
# rather than answering "no". R2 Q2 lists it as the clearest case in the file.
if [ -z "$SUITES_ALLOWED" ]; then
  dp_not_checked "one-regression" "a suite set"
  # AND THE FLOOR-ONCE WALL BELOW READS THE SAME SET, for the same reason and with the
  # same answer: two walls keyed on `run.sh` in the set, both unable to speak without one.
  dp_not_checked "floor-once" "a suite set"
fi
case " $SUITES_ALLOWED " in
  *" run.sh "*)
    if [ -n "$PLAN" ]; then
      _reg_rows=$(regression_rows); _reg_causes=$(regression_causes)
      case "$_reg_rows" in ''|*[!0-9]*) _reg_rows=0 ;; esac
      case "$_reg_causes" in ''|*[!0-9]*) _reg_causes=0 ;; esac
      if [ "$_reg_rows" -gt 0 ] && [ "$_reg_causes" -lt "$_reg_rows" ]; then
        _dp_detail="Full-tree runs on this roster: ${_reg_rows}. Recorded causes on the plan: ${_reg_causes}.
One regression means one: the tree is proved once, at integration close, and a
second full run is a deliberate act that owes its reason to the next reader.

Fix: record why this one is needed, under \`## SDLC State\` in —
    $PLAN

    regression-cause: <why the tree must be re-proved>

Then retry the dispatch. A narrower brief needs no cause: name only the suites
the change actually reaches."
        dp_finding "this run already ran the full tree" "record the cause on the plan" "$_dp_detail"
      fi
    fi
    ;;
esac

# ================================================= THE FLOOR-ONCE WALL (REQ-5, D7)
# (seed row 5, Chris DevX item 1: six full floors in wave-14; the prose rule at
# skills/canonical-sdlc/dispatch.md:12 made mechanical.)
#
# WHAT IT ASKS, AND WHY IT IS NOT THE WALL ABOVE. The one-regression wall counts full-tree
# rows on the ROSTER and charges one written cause per extra run. It says nothing about
# whether the work being proved is FINISHED, and that is the half wave-14 paid for six
# times: a floor run while Step-4 rows are still open proves a tree that no longer exists
# by the time those rows land, so its result is stale before it is read and the next floor
# is owed anyway. This wall reads the PLAN's `## Tasks` ledger instead and refuses a
# full-tree dispatch while any step-4 or fold-in row is `pending` or `active`.
#
# THE PREDICATE IS THE PLAN'S OWN VOCABULARY (A-T5.1). A row counts as open work when its
# `step` cell is 4 — the deliverable phase — OR its task text names a FOLD-IN, whatever
# step the row sits at. Fold-ins are the case the step cell cannot see: wave-14 carried
# eleven of them registered at steps 5 and 6, each one a change to the tree the floor had
# already proved (`wave-14-tune-181.plan.md` rows T14-T27, T11c). The reading is
# deliberately WIDE — a row that merely mentions a fold-in is counted — because the cost of
# a false positive here is one sentence on the plan and the cost of a false negative is a
# floor nobody can trust.
#
# THE OVERRIDE IS THE SAME LINE THE WALL ABOVE ASKS FOR, read the same way: any
# `regression-cause:` under `## SDLC State` releases this arm. Not counted, unlike the
# regression wall's ledger — a run that has stated once, in writing, that it is flooring
# over open rows has said the thing this wall exists to make it say (AC-5.3).
#
# OPEN AND SILENT WITH NOTHING TO READ. No bound plan, no `## Tasks` table, or a brief that
# does not reach the full tree, and this arm never speaks (AC-5.4). `units_rows` exits 1
# and prints nothing on a plan with no table, which is exactly the answer wanted.
#
# ONE PARSER. The ledger is read through `units_rows` (lib/units.sh), never by a split of
# this hook's own — AC-5.5, and the defect REQ-1e existed to remove.
floor_open_rows() {  # -> `id<TAB>step<TAB>status` for each open step-4/fold-in row
  [ -n "$PLAN" ] && [ -f "$PLAN" ] || return 0
  units_rows "$PLAN" 2>/dev/null | awk -F'\t' '
    {
      status = tolower($10)
      if (status != "pending" && status != "active") next
      if ($2 != "4" && index(tolower($4), "fold-in") == 0) next
      printf "%s\t%s\t%s\n", $1, $2, status
    }
  '
}
case " $SUITES_ALLOWED " in
  *" run.sh "*)
    if [ -n "$PLAN" ]; then
      _floor_open="$(floor_open_rows)"
      _floor_causes=$(regression_causes)
      case "$_floor_causes" in ''|*[!0-9]*) _floor_causes=0 ;; esac
      if [ -n "$_floor_open" ] && [ "$_floor_causes" -eq 0 ]; then
        # THE ONE LINE HAS A COLUMN BUDGET AND THE ID LIST DOES NOT (AC-E1.3). The wire is
        # `bionic: dispatch refused — <fact> (<fix>)` capped at 100 columns with the fix at
        # 40, so the fact gets 39: the ids are taken while they fit and the remainder is
        # counted rather than dropped. Every open row is named in full in `detail`, which
        # is where a reader who needs the list goes anyway.
        _floor_n=0; _floor_shown=0; _floor_ids=""; _floor_lines=""
        while IFS=$'\t' read -r _fo_id _fo_step _fo_status; do
          [ -n "$_fo_id" ] || continue
          _floor_n=$((_floor_n + 1))
          # PADDED, so a reader scans the parenthesis column rather than the ids. One fork
          # per open row, on a path that only runs when the dispatch is already refused.
          _floor_lines="${_floor_lines}    $(printf '%-4s' "$_fo_id") (step ${_fo_step}, ${_fo_status})
"
          if [ "$_floor_n" -eq "$((_floor_shown + 1))" ]; then
            _floor_cand="${_floor_ids:+$_floor_ids, }$_fo_id"
            if [ "${#_floor_cand}" -le 17 ]; then
              _floor_ids="$_floor_cand"; _floor_shown=$((_floor_shown + 1))
            fi
          fi
        done <<FLOOR_OPEN_ROWS
$_floor_open
FLOOR_OPEN_ROWS
        # AT LEAST ONE ID IS ALWAYS NAMED. A single id longer than the whole budget would
        # otherwise leave the fact saying "+1" and naming nothing.
        if [ "$_floor_shown" -eq 0 ]; then
          _floor_ids="$(printf '%s' "${_floor_open%%$'\t'*}" | cut -c1-17)"
          _floor_shown=1
        fi
        if [ "$_floor_shown" -lt "$_floor_n" ]; then
          _floor_ids="$_floor_ids +$((_floor_n - _floor_shown))"
        fi
        _dp_detail="Open rows on the plan's \`## Tasks\` ledger:
${_floor_lines}
The full tree is proved ONCE per run, at integration close, over a tree nobody is
still writing to. A floor run while Step-4 rows are open proves a tree that does not
survive them landing: the result is stale before it is read, and the next floor is
owed anyway. Six of wave-14's floors were spent that way.

Fix: land or drop those rows, then retry the dispatch.

Or, if this floor is deliberate, say so once under \`## SDLC State\` in —
    $PLAN

    regression-cause: <why the tree must be re-proved with rows open>

A narrower brief needs no cause: name only the suites the change actually reaches."
        dp_finding "Step-4 rows open: ${_floor_ids}" "land them, or state the cause" "$_dp_detail"
      fi
    fi
    ;;
esac

# ================================================ THE ONE REFUSAL, FOR EVERY FAULT
#
# THE LAST ARM THAT CAN FIND A FAULT IS ABOVE THIS LINE, and everything below is the
# LEDGER. So this is where the list is spent: one refusal carrying every fault every arm
# from the arming wall down found, in file order, or a silent return when they found none.
#
# IT MOVED DOWN PAST THE ONE-REGRESSION WALL (wave-14 REQ-8). It used to sit between the
# brief-shape arms and that wall, which was right while only the brief-shape arms pooled
# and wrong the moment the state arms joined them: a dispatch over budget AND re-running
# the full tree was refused for the budget, and met the regression wall on the next
# attempt — the exact shape AC-8.1 forbids ("fixing the first alone produces a refusal
# naming a fault the first could have named").
#
# IT STAYS ABOVE THE JOURNAL, for the reason each arm used to exit where it stood: a
# dispatch the gate is about to refuse must never be journalled as a launch — and `deny`
# exits 0, which is exactly the status the ledger below would otherwise read as a launch.
dp_refuse_findings

# ---------- THE LEDGER STOPS AT DEPTH ONE ----------
# (session-20260815-landing-supervision T6; design D1 "writers stay put".)
#
# Every wall above this line has now run, and that is the whole of what travels
# into an agent context: hooks/agent-context-guard.sh registers THIS script on the
# settings channel so a dispatch made from inside a teammate or subagent meets the
# same refusals a main-thread one does. What must NOT travel is the journal. The
# roster is the depth-one ledger of what the orchestrator launched, read by the
# landing verdict and the poker as the set of contracts this session owes; a
# teammate's own subagents accreting rows into it would add contracts nobody
# confirms, nobody lands, and nobody was ever going to check — a teammate's
# deliverable subsumes its subtree.
#
# THE PAYLOAD DECIDES (wave-20 T7, AC-9.2). This skip used to key on the guard's
# BIONIC_HOOK_CHANNEL alone — and hooks.json registers the guard on SubagentStop only, so
# no dispatch ever reached here carrying it: every nested launch was journalled onto the
# orchestrator's roster as a contract it owed (triage-B D2c, driven). It asks
# `is_agent_context` now, whose first spelling is the payload's own top-level `agent_id`.
# Silent, and on the pass side — a dispatch that got this far has been allowed (and, from
# inside an agent, is a read-only role by the delegation arm), and this line only declines
# to write it down.
if is_agent_context; then
  exit 0
fi

# The directory levels of this path were already discharged: the attestation
# check above refuses outright if `.bionic` or `.bionic/tmp` is a symlink, so
# reaching here means both are real directories. The roster FILE is its own
# path and gets its own check — a hostile repo may make this gate fail to
# journal, but must not gain an append to a file it points at (§8).
if [ -L "$ROSTER_FILE" ]; then
  warn "the roster path is a symbolic link; nothing was written through it: $ROSTER_FILE"
  exit 0
fi

prune_stale_rosters

# ---------- same-path contention (epic-16 wave-02, R8/AC-12) ----------
#
# Read BEFORE the append, or the row about to be written answers for itself. Two
# dispatches contracted to one file is not an error and is never refused — it is
# how a takeover, a retry, or a deliberately split task legitimately looks — but it
# is the shape behind a whole class of confusing verdicts: whichever agent stops
# second inherits a contract the first one landed, so the landing gate says MET on
# work this agent did not do. Naming the owning row at dispatch is the cheapest
# moment to notice, and the operator is the one who knows which case it is.
#
# "OWNS" IS READ AS "IS ON THIS SESSION'S ROSTER", and that is a deliberately wide
# reading. Closure is not a fact any hook writes — no writer ever sets a status
# meaning `done`, because whether a contract is discharged is computed from disk by
# the verdict, which this gate is forbidden to re-implement or even to invoke. So
# the alternatives were a wide warning or no warning at all. A warning is the tier
# where a false positive costs a sentence, which is the right side to be wrong on.
owning_row_for() {  # <deliverable path> -> the owning row's name, or ""
  [ -n "$1" ] && [ -f "$ROSTER_FILE" ] || return 0
  awk -F'|' -v want="$1" '
    /^#/ { next }
    {
      name = ""; deliv = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^name=/)        name  = substr($i, 6)
        else if ($i ~ /^deliverable=/) deliv = substr($i, 13)
      }
      if (deliv == "") next
      n = split(deliv, parts, ",")
      for (j = 1; j <= n; j++) {
        p = parts[j]; gsub(/^ +| +$/, "", p)
        if (p != "" && p == want) { print name; exit }
      }
    }
  ' "$ROSTER_FILE" 2>/dev/null
}

CONTENDED_OWNER=""
CONTENDED_PATH=""
if [ -n "$C_DELIVERABLE" ]; then
  _old_ifs="$IFS"; IFS=','; set -f
  # shellcheck disable=SC2086
  set -- $C_DELIVERABLE
  set +f; IFS="$_old_ifs"
  for _d in "$@"; do
    _d="${_d# }"; _d="${_d% }"
    [ -n "$_d" ] || continue
    CONTENDED_OWNER=$(owning_row_for "$_d")
    if [ -n "$CONTENDED_OWNER" ]; then CONTENDED_PATH="$_d"; break; fi
  done
fi

# THROUGH THE FILE'S OWN FILTER, like every other interpolated field (S10a, review SEC F3).
# A plan path is a FILENAME the operator chose, so it is as untrusted as any other value on
# this row: `sanitize` exists because the row is pipe-delimited on one line and a value
# carrying a `|` or a newline forges a segment. This was the one field the wave added and
# the one field that skipped it — while the parallel writer in `session-poker.sh adopt`
# filtered the same value through `clean()`, so the asymmetry between the two writers was
# itself the defect. 400 chars matches what `adopt` allows.
ROSTER_PLAN=$(sanitize "$(session_plan "$BIONIC_ROOT" "$BIONIC_SID")" 400)
[ -n "$ROSTER_PLAN" ] || ROSTER_PLAN="none"

# EVERY FIELD NAMED, AND THE ROW ITSELF BUILT ELSEWHERE (spec AC-25). What this hook owns
# is the VALUES — where each comes from, and the per-field cap `sanitize` applies to it.
# What the row IS — which fields, in what order, with what separator — belongs to
# `roster_row` (payload/scripts/lib/roster.sh), which `hooks/session-poker.sh`'s `adopt`
# also calls, so the two writers can no longer drift apart. The empty `agent_id=` is
# passed explicitly rather than omitted: a launch-time row has no id yet, and saying so is
# the field's content, not its absence.
#
# THE FOUR INSTRUMENT FIELDS ARE ALWAYS NAMED HERE (spec AC-20; `re_executes=` added epic-23
# wave-16, REQ-1), even when the wall above derived an empty set, for the same reason: a
# launch row that reached this line passed the suite-allowance wall, so it HAS a budget
# statement, and an omitted key would say the row predates the wall entirely. They are
# optional in `roster_row` so the captured rows in tests/fixtures/roster-row.captured —
# written before this task existed — still rebuild byte for byte; they are not optional to
# this writer.
ROW=$(roster_row \
  status=intended \
  "session=${BIONIC_SID}" \
  "name=${AGENT_NAME}" \
  agent_id= \
  "launched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "subagent_type=${SUBAGENT_TYPE}" \
  "model=${AGENT_MODEL}" \
  "deliverable=${C_DELIVERABLE}" \
  "source=${C_SOURCE}" \
  "duration=${C_DURATION}" \
  "progress=${C_PROGRESS}" \
  "claims=${C_CLAIMS}" \
  "cadence=${C_CADENCE}" \
  "absent=${ABSENT}" \
  "waiver=${C_WAIVER}" \
  "files=${C_FILES}" \
  "suites_allowed=${SUITES_ALLOWED}" \
  "suites_source=${SUITES_SOURCE}" \
  "re_executes=${C_RE_EXECUTES}" \
  "tool_use_id=${TOOL_USE_ID}" \
  "plan=${ROSTER_PLAN}") || ROW=""

WROTE=1
if [ ! -e "$ROSTER_FILE" ]; then
  # A concurrent dispatch in the same session can lose this race and write the
  # header twice; both are comment lines and every reader skips them. The ROWS
  # are what must not interleave, and each is a single short append.
  roster_header >> "$ROSTER_FILE" 2>/dev/null && chmod 600 "$ROSTER_FILE" 2>/dev/null
fi
# A ROW THAT DID NOT BUILD IS NOT APPENDED. `roster_row` refuses a field name no reader
# knows rather than writing it, and an empty `$ROW` here would put a blank line on the
# roster and call it journalled. The existing WROTE=0 path already says the launch could
# not be journalled, which is the true thing to say in both cases.
if [ -n "$ROW" ]; then
  printf '%s\n' "$ROW" >> "$ROSTER_FILE" 2>/dev/null || WROTE=0
else
  WROTE=0
fi

# No lock, unlike the observation record: that one is a read-modify-write of the
# whole file, this one is a single O_APPEND write of well under a pipe buffer,
# which the kernel does not interleave. A lock here would put a failure mode
# (a wedged lock directory) in front of a dispatch, on the fail-open side.
if [ "$WROTE" -eq 0 ]; then
  warn "the launch could not be journalled to the roster (the dispatch is unaffected): $ROSTER_FILE"
else
  if [ -n "$ABSENT" ]; then
    warn "roster row for \"${AGENT_NAME:-(unnamed)}\" records absent brief field(s): ${ABSENT//,/, }"
  fi
  # The waiver echo. A dispatch that took the escape says so out loud as it
  # passes, with the reason it gave — so the operator reads the waiver at the
  # moment it is spent, not only later off the roster row that also holds it.
  if [ -n "$C_WAIVER" ]; then
    warn "the absent-deliverable wall was waived by the brief: ${C_WAIVER}"
  fi
  if [ -n "$CONTENDED_OWNER" ]; then
    warn "the deliverable ${CONTENDED_PATH} is already owned by an open roster row: \"${CONTENDED_OWNER}\" — two rows on one artifact make the second landing verdict unfalsifiable"
  fi
fi

# Present and mine: pass in silence — the allow path prints NOTHING about the check it
# just passed, which is what §4 "The start gate" bans ("Parses no check detail... Never:
# print on the allow path"). The invariant is narrower than the quote reads: what may
# never appear here is check DETAIL, the gate narrating its own reasoning. Two warn-only
# lines above do print on this path, both ratified and neither a check detail — the
# absent-brief-fields warning (a fact about the row just journalled) and the waiver echo
# (the reason a brief gave for producing nothing durable). Both are advisory, both leave
# the exit status untouched, and a silent pass is still the common case.
#
# A THIRD warn-only line stood here until epic-16 wave-02: the unarmed-sweeper nag, which
# asked a resident watcher whether it was alive and named the command to arm one. The
# watcher is deleted — supervision reads facts at the moment of decision instead of
# depending on a process staying up — so there is no arming left to nag about.
exit 0
