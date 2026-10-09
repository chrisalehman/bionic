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
# `brief.sh` (wave-20 T6; REQ-4, Δ10) is the contract grammar this wall and `amend` share; it
# brings `cmd-class.sh` (wave-20 T4; REQ-7, D7) in itself for CMD_RUN_NORM_AWK, the one run
# normaliser its lift pastes in, so this hook names only brief.sh and lets that source do
# the pulling.
BIONIC_LIB_WANT="context.sh fold.sh refuse.sh root.sh run.sh session.sh patrol.sh agents.sh roster.sh units.sh brief.sh"
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
# THE PLAN'S `## Tasks` LEDGER HAS ONE READER TOO (wave-15 REQ-5, D7). The full-run wall
# at the bottom of this file asks whether any row that writes tracked files is open, and it asks
# `units_rows` — the library epic-23 wave-11 built to be the only parser of that table.
# A second split in this hook is the exact defect REQ-1e removed from the evidence gate.
# shellcheck source=/dev/null
. "$BIONIC_LIB/units.sh"
# THE CONTRACT GRAMMAR IS A LIBRARY (wave-20 T6; REQ-4, D4, Δ10). lib/brief.sh holds the lift,
# the value filter, the run caps and every check the Files:/Suites:/Re-executes: fields feed;
# it brings in cmd-class.sh itself for CMD_RUN_NORM_AWK (wave-20 T4), the run normaliser the
# lift's `collapse()` shares with the writer-side budget arm. Both only define functions and
# variables, so sourcing them costs a parse and nothing else.
# shellcheck source=/dev/null
. "$BIONIC_LIB/brief.sh"
# THE MODEL-FACING ADVISORY'S EMITTER (wave-24 T14, A-orch-20): `_fold_emit_context` is the one
# builder of `hookSpecificOutput.additionalContext`, the farm-out nudge's. Functions only.
# shellcheck source=/dev/null
. "$BIONIC_LIB/fold.sh"

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

# ---------- THE WALL'S OWN DEADLINE (wave-28 T70; A-orch-205 to 212, A-orch-231) ----------
#
# THE HARNESS CANCELS A HOOK AT ITS REGISTRATION'S TIMEOUT (hooks.json: 15 s) AND ADMITS THE CALL.
# The roster append is this hook's last step, so a wall that overran left a writer running with no
# row for any later wall to judge: the suite wall refused its runs, `amend` and the Patrol could not
# see it, and the stop guard would not stop it. The session transcript shows it twice, as
# `hook_cancelled` at 15016 and 15012 ms; the eleven dispatches that session journalled took 1.0 to
# 3.8 s. The slowness itself was not reproduced (a 69-name fuzz against the real plan and the real
# 21 MB transcript ran in 1 to 2 s) — this bounds a cause nobody has seen.
#
# SO THE WALL REFUSES FIRST. A timer started here signals this shell at DP_DEADLINE_S, 3 s under
# the registration (the rule payload/scripts/lib/bounds.sh states for every inner bound: strictly
# under, margin named), and the handler denies the dispatch in the wall's own shape. It is armed
# only for an engaged session (everything above is a bystander's silent exit), and it is disarmed
# the moment the row is built, before the first byte of the roster is written, so a refusal never
# leaves a row behind. THE LIMIT, STATED: bash runs a trap between commands, so a single foreground
# command that itself outlasts the registration is not interrupted; the waits in this hook are
# bounded (the impact derivation polls at IMPACT_BOUND_S), which is why the cumulative overrun is
# the case this catches.
DP_DEADLINE_S=12
DP_DEADLINE_LIVE=0
DP_DEADLINE_PID=""
dp_deadline_hit() {
  [ "$DP_DEADLINE_LIVE" = 1 ] || return 0
  DP_DEADLINE_LIVE=0
  refuse deny dispatch "the wall ran out of time" "dispatch again" \
"The dispatch wall had not finished ${DP_DEADLINE_S} s after it started. The harness cancels a hook at its
registration's timeout and admits the call, so this wall refuses first.

Roster:  ${ROSTER_FILE:-(not reached)}
No row was written for this launch, and nothing was spawned.

Fix: dispatch again. If it recurs the machine is overloaded: wait for the running suites to finish,
     or run /bionic:doctor."
}
dp_deadline_stop() {
  [ -z "$DP_DEADLINE_PID" ] || kill "$DP_DEADLINE_PID" 2>/dev/null
  return 0
}
trap dp_deadline_hit ALRM
trap dp_deadline_stop EXIT
DP_DEADLINE_LIVE=1
# The timer is a subshell with no output of its own and no stdin, so the harness has nothing to wait
# on after the hook exits; it is a job of this shell only until `disown` drops it from the table.
( trap 'kill "$_dp_sp" 2>/dev/null; exit 0' TERM
  sleep "$DP_DEADLINE_S" & _dp_sp=$!
  wait "$_dp_sp" && kill -ALRM $$ 2>/dev/null
) >/dev/null 2>&1 </dev/null &
DP_DEADLINE_PID=$!
disown "$DP_DEADLINE_PID" 2>/dev/null || :

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
# `session_run` (lib/run.sh) — the caller's OWN bound plan when one exists. A BOUND session
# is gated on that plan alone, whatever else is open in the root (AC-1); bound to a plan
# that has since closed is treated as having no open run at all (AC-6) — the same PLAN=""
# arm this code already took for "no run".
#
# UNBOUND, THE NEWEST PLAN IS ANNOUNCED AND NEVER ACTED ON (wave-23-fixit-1810, REQ-1, D1).
# `fallback <plan>` names somebody else's run. The advisory goes out once on this gate's
# advisory channel — lib/run.sh's one sentence, the words every other consumer prints — and
# the dispatch is judged with no plan, as under `none`: no budget, no step and no ledger of
# the other run is read. One thing differs from `none`, and it is the approval checkpoint's
# business below: a root that HAS an open run is a wave in flight, and a writer launched by
# a session bound to none of it builds against a plan nobody approved for it, so a writer
# is refused there with the bind instruction — never with the other plan's step.
DP_UNBOUND_PLAN=""
PLAN="$BIONIC_RUN_PLAN"
case "$BIONIC_RUN_WORD" in
  bound-open) : ;;
  fallback)
    run_unbound_advisory "$PLAN" >&2
    DP_UNBOUND_PLAN="$PLAN"
    PLAN=""
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
# fault" means and what tests/dispatch-preflight-3.test.sh §three-arms measures.
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
# (epic-16 wave-02, R5/AC-4; a field report §3.)
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
  # letting it inherit the shell. Both are the field case read directly:
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
PATROL_FIX_NEVER="Fix: CronList, then CronCreate a RECURRING session job at the interval \`bash ${POKER_SCRIPT} interval\`
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
            # TWO CAUSES READ `dead`, and the reason says which (wave-20 T19; REQ-6, AC-6.3).
            # `patrol_verdict` also answers `dead` when Patrol marker turns ran after the stamp
            # and none of them ticked — a job whose prompt carries the marker but not the tick.
            # That is not idleness, and its repair is not a re-arm: the job exists and fires,
            # so re-creating it as it is buys the same silence. Named the way the stop wall's
            # death notice names it (payload/scripts/lib/stop.sh, stop_patrol_revive).
            case "$PATROL_WHY" in
              *"marker turn"*)
                dp_finding "the Patrol fires but never ticks" "run the tick; replace the job" \
"The Patrol was armed on this session and its job still fires, but it never ticks.
Its last tick stamp is ${PATROL_AGE}s old, and since then ${PATROL_WHY%% marker turn*} Patrol marker turn(s)
have run on this session without the tick stamping — the job's prompt carries the marker
but does not run \`bash ${POKER_SCRIPT} tick\`, so nothing has decided anything since:
    ${PATROL_STAMP_FILE}

A dispatch with no Patrol behind it is an agent nobody is waiting on.

Fix: repair the job, not the clock:
  1. Run the tick now: bash ${POKER_SCRIPT} tick
  2. CronList, and CronDelete this session's Patrol job.
  3. CronCreate a RECURRING session job at the interval \`bash ${POKER_SCRIPT} interval\`
     reports, carrying exactly the prompt \`bash ${POKER_SCRIPT} prompt\` prints.

Then retry the dispatch."
                ;;
              *)
                patrol_deny "the Patrol was armed and stopped firing" "re-arm the Patrol, both halves" \
                  "$PATROL_FIX_STOPPED" \
                  "The Patrol was armed on this session and has stopped firing." \
                  "Its last stamp is ${PATROL_AGE}s old, and this session has since sat idle for" \
                  "${PATROL_GAP}s in one stretch with no tick in it — past the ${PATROL_WINDOW}s fire window," \
                  "which is ${PATROL_INTERVAL_WORDS} plus the scheduler's jitter:" \
                  "    ${PATROL_STAMP_FILE}"
                ;;
            esac
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
# EXCEPT AN UNBOUND SESSION IN A ROOT WITH AN OPEN RUN (wave-23-fixit-1810, REQ-1, D1). Its
# `fallback` plan is announced and never acted on, so there is no plan here to read an
# approval out of — and a writer it launched would build in somebody else's run on
# nobody's approval. Before approval only the read-only roles dispatch, and an unbound
# session has approved nothing: the writer is refused with the instruction that ends the
# state (bind, or write this session's plan), and the other run's step is never named.
#
# WHY IT SITS HERE, after the Patrol checkpoint and before the roster: the roster below is
# a LEDGER, and a launch this gate is about to refuse must not be journalled as though it
# happened.
# [WALL: tests/dispatch-preflight.test.sh]
DP_SUBAGENT=$(_jq '.tool_input.subagent_type')
if ! role_is_readonly "$DP_SUBAGENT" && [ -n "$PLAN" ]; then
  # `approved-by:` IS READ BY THE FILL'S OWN READER (wave-26 T5; review 10 F2): `fill_plan_approved`
  # (lib/fill.sh), fence-aware and taking a bulleted `- approved-by:`, so the tick that FILLs a
  # row and this wall that admits its writer can never disagree about whether the plan is
  # approved. fill.sh is sourced here, lazily, at the one arm that reads it. A library directory
  # without the function REFUSES the writer, naming the reader and the file (wave-26 T56; final
  # review N2, ruled): before wave 26 the line was read inline and an unapproved plan refused,
  # and an approval this hook cannot read is no approval. Read-only roles never reach here.
  # `current:` is read only to name the step in the refusal, fence-blind as before.
  DP_CURRENT=$(awk '
    /^## SDLC State/ { st = 1; next }
    st && /^## / { exit }
    st && /^[[:space:]]*current[[:space:]]*:/ {
      sub(/^[[:space:]]*current[[:space:]]*:[[:space:]]*/, ""); gsub(/[[:space:]]/, "");
      print; exit }
  ' "$PLAN" 2>/dev/null) || DP_CURRENT=""
  if ! declare -F fill_plan_approved >/dev/null 2>&1 && [ -r "${BIONIC_LIB:-}/fill.sh" ]; then
    # shellcheck source=/dev/null
    . "$BIONIC_LIB/fill.sh"
  fi
  DP_APPROVED=""
  if ! declare -F fill_plan_approved >/dev/null 2>&1; then
    DP_APPROVED=unreadable
  elif fill_plan_approved "$PLAN"; then
    DP_APPROVED=yes
  fi
  if [ "$DP_APPROVED" = unreadable ]; then
    dp_finding "the approval reader lib/fill.sh cannot be loaded" "reinstall the plugin" \
      "Role: ${DP_SUBAGENT:-(none given, so general-purpose)}
Plan: ${PLAN}
Reader: fill_plan_approved, from ${BIONIC_LIB:-<no library directory>}/fill.sh — not there, or it
        does not define the function, so whether this plan is approved cannot be read.

A writer is admitted only on an approval this hook has read; one it cannot read is no approval.
Before approval only a read-only role dispatches: ${ROLE_READONLY_SET}.

Fix: reinstall the plugin (claude plugin install bionic@bionic) so its scripts/lib carries
     fill.sh again, then retry the dispatch."
  elif [ -z "$DP_APPROVED" ]; then
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
if ! role_is_readonly "$DP_SUBAGENT" && [ -n "$DP_UNBOUND_PLAN" ]; then
  dp_finding "this session is bound to no run" "bind it, or write its plan" \
    "Role: ${DP_SUBAGENT:-(none given, so general-purpose)}
$(run_unbound_advisory "$DP_UNBOUND_PLAN")

A writer is the first act of a plan that cannot be taken back by closing a file, and this
session has no plan of its own: the run above is the root's newest, announced and never
acted on. Before approval only a read-only role dispatches: ${ROLE_READONLY_SET}.

Fix: bind this session to the run it is working, or write this session's own plan (the
     governing-skill hook binds it on the first write), then retry the dispatch."
fi

# ==================================== A ROW THAT READS AN APPROVAL WAITS FOR IT (wave-26 T13)
# (REQ-6 AC-6.2; spec D3, ADR-043.)
#
# THE PLAN'S APPROVAL IS NOT THE ONLY ONE. A row whose `reads` cell names `approval:<name>` —
# the release reads `approval:release` — is not ready until `## SDLC State` carries
# `approved: <name> …`, a line only `session-poker.sh approve` writes, on the user's reply. The
# ready set (lib/fill.sh over lib/units.sh) never offers such a row; this arm refuses the
# dispatch that would start one anyway, whatever the role, because the thing being waited for
# is the user's act and no role is entitled to stand in for it.
#
# WHICH ROW A DISPATCH IS: ONE ANSWER, asked here once (wave-28 T55). The brief's `Row:` when it
# carries one (T7), else the row the Agent call's NAME matches, by the rule `fill_row_launched` uses —
# the id itself or the id behind a `<prefix>-`, with the `-r<n>` re-run suffix taken off. This arm,
# T7's Lands-on arm and the full-run wall's regression row all read `DP_BOUND_ROW`; none reads the name
# again. A name that is no row's id and a brief with no `Row:` bind nothing, and nothing is judged.
# A name that matches MORE than one row, with no `Row:`, binds nothing either and is refused, naming the
# rows it matched but no remedy row (wave-28 T58; the reader below carries the rule).
# `approval:plan` is the arm above.
DP_ROW_NAME=$(_jq '.tool_input.name')
# The brief is lifted here, the one place the label is read: the lift needs only the role and the
# brief, and a `Row:` is a field of it. The role goes in with the brief (wave-20 T4; REQ-7, Δ3, Δ9): it
# decides the run cap, which `brief_validate_fields` reads off the same role below. Nothing else goes
# in: the Files: reader reads an item by its own text, and this hook lists no directory for it
# (wave-27 T42, A-orch-46).
LIFTED=$(lift_contract_fields "$(_jq '.tool_input.prompt')" "$DP_SUBAGENT")
# DP_MINE_AWK: the awk function `mine(id)`, 1 when the dispatch name `nm` is row <id>'s. Only the
# reader below calls it.
DP_MINE_AWK='
    function mine(id,   b, l) {
      b = nm
      if (match(b, /-r[0-9]+$/)) b = substr(b, 1, RSTART - 1)
      if (b == id) return 1
      l = length(id)
      return (length(b) > l + 1 && substr(b, length(b) - l) == "-" id)
    }'
# dp_row_reader — sets DP_ROW (the brief's `Row:`, or empty), DP_NAME_ROWS (every plan row the name
# matches, one per line), DP_NAME_ROW (the first) and DP_BOUND_ROW: the row this dispatch is bound to.
# A name that matches more than one row, with no `Row:` to say which, binds NOTHING and is refused
# (wave-28 T58): the launch record records no row for such a name either (session-poker NOT-RECORDED),
# and binding the first would let the approval arm pass a second match that waits for approval.
dp_row_reader() {
  DP_ROW="$(brief_field "$LIFTED" row)"; DP_NAME_ROWS=""; DP_NAME_ROW=""; DP_NAME_AMBIG=""
  if [ -n "$PLAN" ] && [ -n "$DP_ROW_NAME" ]; then
    DP_NAME_ROWS="$(units_rows "$PLAN" 2>/dev/null | awk -F'\t' -v nm="$DP_ROW_NAME" "$DP_MINE_AWK"' $1 != "" && mine($1) { print $1 }')"
    DP_NAME_ROW="${DP_NAME_ROWS%%$'\n'*}"
    case "$DP_NAME_ROWS" in *$'\n'*) DP_NAME_AMBIG=1 ;; esac
  fi
  DP_BOUND_ROW="${DP_ROW:-$DP_NAME_ROW}"
  if [ -z "$DP_ROW" ] && [ -n "$DP_NAME_AMBIG" ]; then
    DP_BOUND_ROW=""
    _ar_rest="${DP_NAME_ROWS#*$'\n'}"
    dp_finding "the name matches rows $(bionic_trunc "$DP_NAME_ROW" 11), $(bionic_trunc "${_ar_rest%%$'\n'*}" 11)" \
      "add Row: <id>" \
      "The agent's name matches more than one row of the bound plan, and the brief has no Row: to say which:
    Dispatch: ${DP_ROW_NAME}
    Rows:     $(printf '%s' "$DP_NAME_ROWS" | tr '\n' ' ')
    Plan:     ${PLAN}

Every wall reads one row per dispatch, and the launch record records none for such a name.

Fix: add a line of its own to the brief naming the row this agent runs, as the plan's ## Tasks table
spells it —
    Row: <id>
  or name the agent for one row only.

Then retry the dispatch."
  fi
}
dp_row_reader
if [ -n "$PLAN" ] && [ -n "$DP_BOUND_ROW" ]; then
  DP_APPROVAL_WAITS=$(units_rows "$PLAN" 2>/dev/null | awk -F'\t' -v id="$DP_BOUND_ROW" '
    $1 != "" && $1 == id {
      m = split($13, a, ",")
      for (k = 1; k <= m; k++) {
        t = a[k]; gsub(/^[ \t]+|[ \t]+$/, "", t)
        # A LIVE READ OF AN APPROVAL IS STILL AN APPROVAL READ (review 10 F5): readiness waits
        # on `live:approval:<name>` exactly as on the bare token, so this arm does too.
        sub(/^live:/, "", t)
        if (t ~ /^approval:[A-Za-z0-9][A-Za-z0-9._-]*$/ && t != "approval:plan") print $1 "\t" substr(t, 10)
      }
    }')
  if [ -n "$DP_APPROVAL_WAITS" ]; then
    DP_APPROVALS_HAD=$(awk '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^## SDLC State/ { st = 1; next }
      /^## / { st = 0 }
      st {
        l = $0; sub(/^[ \t]*-?[ \t]*/, "", l)
        if (l !~ /^approved[ \t]*:/) next
        sub(/^approved[ \t]*:[ \t]*/, "", l); split(l, w, /[ \t]+/)
        if (w[1] != "") printf " %s ", w[1]
      }' "$PLAN" 2>/dev/null)
    while IFS=$'\t' read -r DP_AW_ID DP_AW_NAME; do
      [ -n "$DP_AW_NAME" ] || continue
      case "$DP_APPROVALS_HAD" in *" $DP_AW_NAME "*) continue ;; esac
      dp_finding "row ${DP_AW_ID} waits for approval:${DP_AW_NAME}" \
        "record it with the approve verb" \
        "Dispatch: ${DP_ROW_NAME:-<unnamed>} (row ${DP_AW_ID} of ${PLAN})
Reads:    approval:${DP_AW_NAME} — and ## SDLC State carries no 'approved: ${DP_AW_NAME}' line.

An approval is an act of the user. The row waits for it, the ready set does not offer it, and no
dispatch starts it before the line exists.

Fix: put the decision to the user; on their reply, record it, then retry the dispatch:
       bash $(refuse_shell_word "$HOOK_DIR/session-poker.sh") approve ${DP_AW_NAME} '<the reply, verbatim>'
     Silence, a question, or a partial reply is never recorded as approval."
    done <<DP_AW
$DP_APPROVAL_WAITS
DP_AW
  fi
fi

# ======================================= ONE LEVEL OF DELEGATION (wave-20 T7, AC-9.4)
# (spec D9 and its Writer-origin invariant; design ledger Δ11 as amended by Δ12.)
#
# ONLY THE ORCHESTRATOR DISPATCHES WRITERS. A dispatch made from inside a subagent — a
# payload carrying a top-level `agent_id` (t1-probe-report §3), or the guard's channel
# variable: `is_agent_context` below — may launch a read-only role and
# nothing else. The read-only roles' own files disallow the Agent tool (agents-src), so the
# longest chain there is is orchestrator → writer → read-only helper: every writer is
# rostered, contracted and dispatched by the orchestrator. Before Δ12 nothing bounded the
# depth, and the consumer wave that reported it ran orchestrator → implementor → fork →
# dispatch, with the nested rows accreting onto the orchestrator's roster.
#
# is_agent_context — defined HERE, above its first caller, because bash resolves a function
# at the call. Two spellings mark an agent context and either one is enough:
#   * `.agent_id` — the harness's own marker, present only when the hook fires inside a
#     subagent (the Bash walls' ARM C and hooks/stop-guard.sh read the same field). The
#     dependable one: measured on a nested PreToolUse|Agent payload (T12).
#   * BIONIC_HOOK_CHANNEL=agent-context — the settings-channel guard's marker. No
#     registration hands it to THIS hook today (hooks.json runs the guard on SubagentStop
#     only), so it is kept as one spelling of two, never the one the journal relies on.
# NOT `.agent_type` (wave-20 T7b; critic C4). The harness sets it "when the session uses
# --agent or the hook fires inside a subagent", so a main session started as `claude --agent
# <x>` carries it with no `agent_id` — and that session is the orchestrator: reading it as a
# subagent refused its every writer dispatch and journalled none of its launches. A real
# subagent's payload carries `agent_id` beside its `agent_type`, so nothing is lost.
is_agent_context() {
  [ -n "$(_jq '.agent_id')" ] && return 0
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
# post-wave-04). A brief missing its duration or progress path is recorded as absent and
# warned about, and the dispatch goes through. THE JOURNAL ITSELF IS NOT OPTIONAL (wave-28
# T70, A-orch-231): this paragraph said an unwritable directory or a hostile path warned and
# let the dispatch through, and that was the wrong rule. A dispatch the roster does not carry
# is one no later wall can judge — the suite wall, `amend`, the Patrol and the stop guard all
# read the row — so a launch whose row did not build, or could not be appended, or whose
# roster path is a link, is REFUSED in this wall's own shape, naming the roster and the
# reason, and nothing is spawned. The one exit that journals nothing is the delegation
# arm's legitimate case, below, and it says so.
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
# where its two spellings are listed. A writer dispatched INTO a tree works there by
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

# ---------- the budget wall: a person's cap on writers ----------
#
# A CAP IS A PERSON'S WORD (wave-28 T9; D15, REQ-2 AC-2.9/AC-2.10). The plan's frontmatter may
# carry `parallel-budget: writers=N … source=…`, and this wall obeys its `writers=` only when a
# person wrote it: `budget_cap` (payload/scripts/lib/run.sh) answers from a line whose
# `source=` is `user` (the hand cap verb's) or `override`, and nothing otherwise. A probe's
# number caps nothing — the width is the gate's, asked by the run as it goes — so a plan with
# no line, a 1.12.0 plan carrying `source=probe`, and a line with no `source=` all dispatch
# with no ceiling here, and nothing is said about it: no plan owes the line.
#
# THE LEADING FRONTMATTER BLOCK ONLY. A `parallel-budget:` inside the plan body is prose
# — a plan quoting the header in a task description — and a wall that read it would take a
# quotation for configuration (`plan_budget_line`, which `budget_cap` reads through).
#
# THE ONE PLAN-BOUND ARM OF THIS GATE (task-engaged-session, AC-23). The cap is a property of
# the run, declared in its plan, so an engaged session with no plan on disk yet has no cap to
# be over and this wall stays silent — while every plan-free wall above and below it fires.
#
# NO WORKTREES CEILING (wave-28 T9; D15). It refused at `live trees + 1 > worktrees=`, a figure
# the probe derived from free disk at Step 0. What it stood for is checked where a tree is
# made: `spawn-worktree.sh create` refuses when the project's volume has less free than the
# largest tree already there.
PARALLEL_BUDGET=""
[ -n "$PLAN" ] && PARALLEL_BUDGET="$(plan_budget_line "$PLAN")"
DP_BUDGET_WRITERS=""
[ -n "$PLAN" ] && DP_BUDGET_WRITERS="$(budget_cap "$PLAN")"
DP_BUDGET_WRITERS="${DP_BUDGET_WRITERS#writers=}"

if [ -n "$DP_BUDGET_WRITERS" ]; then

  # OPEN ROWS, in one pass over the roster (spec AC-7).
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
  # NO SUITE IS COUNTED HERE (wave-26 T8; D8, REQ-6 AC-6.3). This pass used to count a
  # second number beside the open rows, the rows holding a suite (a declared subprocess
  # claim, or a test-runner), for a ceiling that refused the next dispatch at
  # `claimed + 1 > suites`. That booked a suite for an agent's whole life whether it ran one
  # or not, and refused a read-only agent that would run nothing. A suite run now books a
  # machine-wide place as it starts (payload/scripts/lib/slots.sh, through the Bash wall's
  # shim), so hand-out asks nothing about suites. The row's `claims=` field stays: the
  # Patrol tick reads it to name the youngest suite-running writer under memory pressure.
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
  # which this wall already owns and already reads. So the answer is ALWAYS `<open>`
  # and the exit is ALWAYS 0; a dispatch is judged against a count that may be
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
  budget_roster_counts() {  # <roster file> <transcript> -> "<open>", then the open names (exit 0)
    local f="$1" transcript="$2" line nm seen open=0 primed="" notfresh=""
    local la_out la_rc row_dark dark="" closed still_open open_names=""
    if [ ! -f "$f" ] || [ -L "$f" ]; then printf '0'; return 0; fi
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
          # THE ROW'S ROLE DECIDES WHAT IT COSTS (wave-24 T10, D11). Its NAME joins the open
          # list, and `budget_open_writers` (payload/scripts/lib/roster.sh) turns that list into
          # the writer count after the dark rows are settled, so a read-only row holds no
          # writer slot and the Patrol's tick, which calls the same function, reads the same
          # number.
          open_names="${open_names}${nm}
"
          # COUNTED BY THE FALLBACK, NOT BY A READING. The row goes on the dark list, and the
          # block below asks the roster whether it has since closed. A row the panel spoke for
          # never lands here, which is what makes that question unreachable on the fresh path.
          [ -n "$row_dark" ] && dark="${dark}${nm}
"
          ;;
        1) : ;;
      esac
    done < "$f"

    # THE DARK ROWS, SETTLED IN ONE PASS (wave-14 REQ-3, D7). One read of the roster and one
    # of the ack ledger, for every dark row at once — never per row, and never at all on a
    # turn where the panel answered for every row. A landed row gives its writer slot back.
    if [ -n "$dark" ]; then
      still_open=$(roster_open_names "$f" "$ACK_LEDGER_FILE")
      closed=$(while IFS= read -r nm; do
                 [ -n "$nm" ] || continue
                 /usr/bin/grep -qxF -- "$nm" <<< "$still_open" || printf '%s\n' "$nm"
               done <<DARKNAMES
$dark
DARKNAMES
)
      if [ -n "$closed" ]; then
        while IFS= read -r nm; do
          [ -n "$nm" ] || continue
          # A HERE-STRING, NOT A PIPE (correctness review F8; the reason
          # is stated in this comment, no rule file carries it). `grep -q` exits at its first match; under this
          # file's `set -uo pipefail` (:67), a `printf | grep -qxF` pipeline SIGPIPEs the
          # producer whenever the match sits ahead of enough trailing data to still be
          # queued when `grep` closes its read end, and `pipefail` promotes that 141 over
          # grep's own 0 — a closed row reads as still open. A here-string has no second
          # process to lose.
          /usr/bin/grep -qxF -- "$nm" <<< "$closed" || continue
          open_names=$(printf '%s' "$open_names" | /usr/bin/grep -vxF -- "$nm")
        done <<DARK
$dark
DARK
      fi
    fi

    open=$(printf '%s\n' "$open_names" | budget_open_writers "$f")
    # THE NAMES RIDE BELOW THE COUNTS (wave-24 T13, D10), one per line, so the writer-budget
    # refusal can list the rows it counted without a second reading of the roster.
    printf '%s\n%s' "$open" "$open_names"
  }

  # budget_writer_rows <roster file> <open names> -> one line per open WRITER row: its name and
  # the command that closes it. The same `budget_open_writers` that produced the count asks each
  # name alone, so the rows listed are the rows counted and a read-only row is never one of them.
  # Run on the refusal path only. The ack command is PRINTED for the orchestrator and never run
  # here: this gate executes the sweeper on no path, and the suite pins that. The path is
  # printed as ONE shell word, so a plugin root with a space pastes whole (wave-24 T29, I2).
  DP_ACK_SCRIPT="$(refuse_shell_word "${HOOK_DIR}/session-sweeper.sh")"
  budget_writer_rows() {
    local f="$1" nm
    while IFS= read -r nm; do
      [ -n "$nm" ] || continue
      [ "$(printf '%s\n' "$nm" | budget_open_writers "$f")" = "1" ] || continue
      printf '    open: %s — once it has landed, close it: bash %s ack %s\n' \
        "$nm" "$DP_ACK_SCRIPT" "$(refuse_quote "$nm")"
    done <<WRITERNAMES
$2
WRITERNAMES
  }

  # FIRST CEILING WINS, STILL (wave-14 REQ-8, D3). The ceilings are readings of
  # ONE wall and one repair — "land or stand down a row" clears whichever of them fired — so
  # reporting each would spend a line of the refusal's budget per ceiling to say one thing
  # several ways (one since wave-28 T9 removed the worktrees arm; wave-26 T8 removed suites). The guard keeps the arm's
  # pre-REQ-8 behaviour exactly: the first ceiling passed is the one named. What changed is that the wall records instead of exiting, so
  # the arms after it are read in the same pass.
  BUDGET_DENIED=""
  budget_deny() {  # <fact> <the one line naming the resource, its ceiling and its count> [rows]
    # ONE FIX FOR EVERY ARM (rows 43 and 45): the fact names which ceiling was passed
    # and the repair is the same act whichever it was. The writer arm adds the rows it counted,
    # each with the command that closes it (wave-24 T13, D10, AC-6.7).
    [ -z "$BUDGET_DENIED" ] || return 0
    BUDGET_DENIED=1
    dp_finding "$1" "land or stand down a row" \
      "    $2${3:+
$3}

budget: ${PARALLEL_BUDGET}
  declared by ${PLAN}

That cap is a person's (source=user or source=override): the hand cap verb wrote it, or
someone typed it. Nothing here raises it; raising it is that person's edit of the line.

Fix: land or stand down an open row first (\`bash ${HOOK_DIR}/stop-orders.sh
standdown\` computes the batch), or ask the user to raise the plan's writers= cap."
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
  # answers `<open>`, falling back to the roster's own open rows when there is
  # no answer to read, so the ceilings below are the only thing left between a
  # brief and its dispatch.
  BUDGET_COUNTS=$(budget_roster_counts "$ROSTER_FILE" "$BUDGET_TRANSCRIPT")
  BUDGET_OPEN_NAMES=""
  case "$BUDGET_COUNTS" in *$'\n'*) BUDGET_OPEN_NAMES="${BUDGET_COUNTS#*$'\n'}" ;; esac
  BUDGET_COUNTS="${BUDGET_COUNTS%%$'\n'*}"
  BUDGET_OPEN="$BUDGET_COUNTS"
  B_WRITERS="$DP_BUDGET_WRITERS"
  # A READ-ONLY DISPATCH ASKS FOR NO WRITER SLOT (wave-24 T10, D11): the +1 is a writer's.
  BUDGET_ASK=1
  role_is_readonly "$DP_SUBAGENT" && BUDGET_ASK=0
  [ $(( BUDGET_OPEN + BUDGET_ASK )) -gt "$B_WRITERS" ] && budget_deny \
    "this passes the run's writer budget" \
    "writers: budget=${B_WRITERS} open=${BUDGET_OPEN} with-this-dispatch=$(( BUDGET_OPEN + BUDGET_ASK ))" \
    "$(budget_writer_rows "$ROSTER_FILE" "$BUDGET_OPEN_NAMES")"

  # NO SUITES ARM (wave-26 T8; D8, REQ-6 AC-6.3). It refused a dispatch at
  # `claimed + 1 > suites`: a suite booked for every claiming agent's whole life, and one more
  # for every dispatch, read-only included. A suite run books its own machine-wide place as it
  # starts now (payload/scripts/lib/slots.sh), so hand-out counts no suites.
fi

warn() { printf 'dispatch-preflight: WARN %s\n' "$1" >&2; }

# THE VALUE FILTER AND THE LIFT LIVE IN payload/scripts/lib/brief.sh (wave-20 T6; REQ-4, D4,
# Δ10): `sanitize`, which keeps a `|` or a newline from forging a row segment, and
# `lift_contract_fields`, which reads the brief's labelled fields, with the run caps beside it.
# This file calls both; `amend` and `task-add` call the same two.

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

# THE BRIEF IS LIFTED ABOVE, at the row reader (wave-28 T55): `LIFTED` is read from here on.
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
# chose and can fix at dispatch. `re_executes_dropped=`, read by
# `brief_validate_fields` beside the dropped suite, carries this fact to a refusal instead.
C_DELIVERABLE=$(sanitize "$(field_of deliverable)" 300)
# Never both: the extractor prints ONE of these two, so a non-empty list here means
# `deliverable=` is empty and the ambiguity wall below owns the dispatch.
C_DELIVERABLE_CANDIDATES=$(sanitize "$(field_of deliverable_ambiguous)" 900)
C_DURATION=$(sanitize "$(field_of duration)" 80)
C_PROGRESS=$(sanitize "$(field_of progress)" 300)
C_CADENCE=$(sanitize "$(field_of cadence)" 80)
C_CLAIMS=$(sanitize "$(field_of claims)" 300)
C_WAIVER=$(sanitize "$(field_of waiver)" 300)
C_DONE=$(sanitize "$(field_of done)" 300)   # the Done marker (wave-24 T9, D3); on the row only when declared
# THE THREE INSTRUMENT FIELDS, READ THROUGH THE GRAMMAR (wave-20 T6; REQ-4, D4, Δ10).
# `brief_field` (payload/scripts/lib/brief.sh) bounds each kind as the roster row stores it —
# the three are list-valued and never cut — so the scaffold marks and the row below hold
# exactly the values `brief_validate_fields` judges. The lift's fault fields (a refused token,
# a dropped suite or run, a commented span) are the library's to read now; nothing here does.
C_FILES=$(brief_field "$LIFTED" files)
C_SUITES=$(brief_field "$LIFTED" suites)
C_RE_EXECUTES=$(brief_field "$LIFTED" re_executes)
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
# full-run wall all call `dp_finding` and carry on. Principle P-A reads the same way
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
# tests/dispatch-preflight-3.test.sh's §scaffold-verbatim uses to pull the same block out of
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
      # is "writers; a read-only brief omits this and keeps Suites: none" (wave-21 T7 reworded
      # it from "omit for a read-only brief", which read as "omit the instrument"),
      # `Deliverable-waiver:` is "only for a report returned by message". Marking each one purely because its own field came back empty
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
      # AN OPTIONAL LINE IS NEVER MARKED (wave-21 T7; REQ-7 AC-7.2, D7). `Subprocess claim:`
      # is declared iff the task backgrounds a watcher — a CI wait, `gh run watch` — so its
      # absence is the ordinary case and no wall reads it as a fault (the roster's absence
      # list leaves it off for the same reason). Named here, rather than left to fall
      # through, so the next label added to this case cannot sweep it in by a default arm.
      "Subprocess claim")    ;;
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
# exactly one (tests/dispatch-preflight-3.test.sh §combined and §three-arms carry the sum).
# The single-fault no-deliverable detail carries the same constant, and the shared
# brief-scaffold block (agents-src/blocks/brief-scaffold.md) says the same in its header.
DP_PROMPT_ONLY="The wall reads the prompt text only. A brief file the prompt points at is not read, so copy its scaffold lines into the prompt."
#
# A BRIEF THAT LACKS NO LINE IS SHOWN NO SCAFFOLD (wave-24 T13, D10, AC-6.7). The scaffold is
# there to say which lines to add, and its `<ADD>` marks are that answer. When it carries no
# mark the brief already has every line, the faults are state (a full budget, a name in flight),
# and nine blank template lines under them sent the author looking for a brief fault that does
# not exist. So the scaffold and the prompt-only line ride only beside a mark.
dp_refuse_findings() {
  [ "$DP_FINDING_N" -gt 0 ] || return 0
  if [ "$DP_FINDING_N" -eq 1 ]; then
    refuse deny dispatch "$DP_FIRST_FACT" "$DP_FIRST_FIX" "$DP_FIRST_DETAIL"
  fi
  local _scaffold
  _scaffold="$(dp_scaffold_marked)"
  case "$_scaffold" in
    *' <ADD>'*) _scaffold="${_scaffold}
${DP_PROMPT_ONLY}

" ;;
    *) _scaffold="" ;;
  esac
  # `DP_FAULT_LINES` and `DP_NOTCHECKED` each end in their own newline when non-empty and
  # are empty strings otherwise, so this interpolation adds no blank line when either is
  # absent — a two-fault brief with nothing unchecked renders exactly one extra line.
  refuse deny dispatch "$DP_FIRST_FACT" "$DP_FIRST_FIX" \
    "${DP_FAULT_LINES}${DP_NOTCHECKED}${_scaffold}See skills/canonical-sdlc/dispatch.md §Dispatch for why each line is required."
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

# ======================================== A READER'S QUESTIONS (wave-27 T15; REQ-5, REQ-1, D5)
#
# A READER IS DISPATCHED FOR ITS QUESTIONS. `bionic:auditor`, `bionic:critic` and
# `bionic:reviewer` answer the reading questions `evidence`, `adversarial` and `structure`, and
# the plan's rigor deals each question to one of them (`facts_owed`, lib/proof.sh). A reader's
# brief names its own on a `Questions: <q>[, <q>]` line, which `lift_contract_fields` reads as a
# set. This arm refuses a reader brief with no such line, a word outside the three, and a set
# that is not exactly what the bound plan's rigor deals that role — so the role a question was
# dealt to is the role that reads it, and a rigor that deals a role nothing dispatches it for
# nothing. The admitted set goes on the row as `questions=`, and execution-recorder.sh pushes
# that set's checks files at agent start.
#
# A PREDICATE OVER WHAT IT IS HANDED (the freeze, .claude/rules/hook-authoring.md). Rigor and
# scale are the bound plan's frontmatter, from the plan this hook already reads; `facts_owed` is a
# pure function of the two. No git, no roster. With no bound plan the line is still required and
# the dealing is not checked; a bound plan whose rigor or scale deals nothing says `not checked`.
#
# EVERY OTHER ROLE IS UNTOUCHED: the line is not required, and if present it is neither judged
# nor recorded, so nothing is pushed to that agent.
DP_QUESTIONS=""
case "$DP_SUBAGENT" in
  bionic:auditor|bionic:critic|bionic:reviewer)
    _q_set="$(brief_field "$LIFTED" questions)"
    _q_bad="$(brief_field "$LIFTED" questions_bad)"
    _q_dup="$(brief_field "$LIFTED" questions_dup)"
    _q_rigor=""; _q_scale=""; _q_owed=""; _q_dealt=""; _q_dealable=""; _q_admitted=""
    if [ -n "$PLAN" ]; then
      if ! declare -F facts_owed >/dev/null 2>&1 && [ -r "${BIONIC_LIB:-}/proof.sh" ]; then
        # shellcheck source=/dev/null
        . "$BIONIC_LIB/proof.sh"
      fi
      _q_rigor="$(plan_frontmatter_get "$PLAN" rigor)"
      _q_scale="$(plan_frontmatter_get "$PLAN" scale)"
      if declare -F facts_owed >/dev/null 2>&1 && _q_owed="$(facts_owed "$_q_rigor" "$_q_scale")"; then
        _q_dealable=1
        _q_dealt="$(printf '%s\n' "$_q_owed" | awk -F'\t' -v r="$DP_SUBAGENT" \
          '$1 == "review" && $3 == r && $4 == "piece" { printf "%s%s", (n++ ? "," : ""), $2 }')"
      else
        dp_not_checked "the Questions: dealing" "a plan rigor and scale that facts_owed deals"
      fi
    fi
    # THE LEVEL AS PRINTED (wave-28 T44; AC-16.2): a detail names the plan's rigor by its new word
    # with its meaning, lib/run.sh `rigor_print`; a word that is no level is quoted as written.
    _q_level="$(rigor_print "$_q_rigor" 2>/dev/null)" || _q_level="rigor ${_q_rigor:-none}"
    # THE FIRST LINE NAMES THE LEVEL IN THE ANNOUNCEMENT'S FORM, `<level> rigor`, with the role's
    # short name, and keeps the set the user acts on (A-orch-17): the printed form and the role as
    # typed do not fit a 100-column line beside the set, so they ride the detail.
    _q_short="$(rigor_level "$_q_rigor" 2>/dev/null)" || _q_short="${_q_rigor:-no}"
    _q_role="${DP_SUBAGENT#bionic:}"
    # The holder of each question, one line apiece, for the refusal details.
    _q_holders=""
    for _q_q in evidence adversarial structure; do
      _q_h="$(printf '%s\n' "$_q_owed" | awk -F'\t' -v q="$_q_q" \
        '$1 == "review" && $2 == q && $4 == "piece" { print $3; exit }')"
      [ -n "$_q_h" ] && _q_holders="${_q_holders}    ${_q_q} is dealt to ${_q_h}
"
    done
    _q_fixline="Questions: <q>[, <q>]"
    [ -n "$_q_dealt" ] && _q_fixline="Questions: ${_q_dealt//,/, }"
    # THE LABEL IS GIVEN ONCE (wave-27 T49; review pass 24). Two lines, even with the same set,
    # are refused naming both, since the second would otherwise be dropped in silence.
    if [ -n "$_q_dup" ]; then
      # THE TRUE COUNT (wave-27 T57; review pass 35 N2): the field is cut at a whole number, so
      # the count is the raw line's, and a list cut short says how many more it left out.
      read -r -a _q_arr <<< "$_q_dup"
      read -r -a _q_all <<< "$(printf '%s\n' "$LIFTED" | sed -n 's/^questions_dup=//p' | head -1)"
      _q_n=${#_q_all[@]}; _q_k=${#_q_arr[@]}; _q_nums=""
      [ "$_q_n" -ge "$_q_k" ] || _q_n=$_q_k
      for _q_i in "${!_q_arr[@]}"; do
        if [ "$_q_i" -eq 0 ]; then _q_nums="${_q_arr[0]}"
        elif [ "$_q_k" -eq "$_q_n" ] && [ "$_q_i" -eq $((_q_k - 1)) ]; then _q_nums="${_q_nums} and ${_q_arr[$_q_i]}"
        else _q_nums="${_q_nums}, ${_q_arr[$_q_i]}"; fi
      done
      [ "$_q_k" -lt "$_q_n" ] && _q_nums="${_q_nums} and $((_q_n - _q_k)) more"
      dp_finding "${DP_SUBAGENT} has ${_q_n} Questions: lines" "keep one Questions: line" \
        "The brief carries the Questions: label more than once, on lines ${_q_nums}:
    Role: ${DP_SUBAGENT}

A reader's questions are one set, read off one line. A second line is not merged into the
first and not ignored, so the brief is refused rather than guessed at. A line inside a
fenced block is an example, and does not count.

Fix: keep one line, on a line of its own —
    ${_q_fixline}

Then retry the dispatch."
    fi
    if [ -n "$_q_bad" ]; then
      dp_finding "unknown question: $(bionic_trunc "${_q_bad%% *}" 16)" "use evidence/adversarial/structure" \
        "The Questions: line names a word that is not a reading question:
    ${_q_bad}

A reader answers one or more of three questions: evidence, adversarial and structure. Its
checks are pushed to it at start by name, so a word outside the three is a question no
reader is held to.

Fix: name only the three questions, on a line of its own —
    ${_q_fixline}

Then retry the dispatch."
    fi
    if [ -n "$_q_dealable" ] && [ -z "$_q_dealt" ]; then
      dp_finding "${_q_short} rigor deals ${_q_role}: nothing" "dispatch its holder" \
        "The plan's rigor deals this reader no question, so there is nothing to dispatch it for:
    Role:  ${DP_SUBAGENT}
    Given: ${_q_set:-(no Questions: line)}
    Dealt: nothing at ${_q_level}, scale ${_q_scale}

Each question is read by the one role the rigor deals it to:
${_q_holders}
Fix: dispatch the role that holds the question, with its own Questions: line.

Then retry the dispatch."
    elif [ -z "$_q_set" ] && [ -z "$_q_bad" ]; then
      _q_why="With no bound plan the dealing is not checked: name the questions this reader answers,
from evidence, adversarial and structure."
      [ -n "$PLAN" ] && _q_why="The bound plan's rigor (${_q_rigor:-none}) and scale (${_q_scale:-none}) deal nothing, so the
dealing is not checked: name the questions this reader answers, from evidence,
adversarial and structure."
      [ -n "$_q_dealt" ] && _q_why="The plan deals this role the set below at ${_q_level}, and its checks are
pushed to it at start from that line."
      dp_finding "${DP_SUBAGENT} names no Questions: line" "add the Questions: line" \
        "A reader is dispatched for its questions, and this brief names none:
    Role: ${DP_SUBAGENT}

${_q_why}

Fix: add this line to the brief, on a line of its own —
    ${_q_fixline}

Then retry the dispatch."
    elif [ -n "$_q_set" ] && [ -n "$_q_dealable" ] && [ "$_q_set" != "$_q_dealt" ]; then
      dp_finding "${_q_short} rigor deals ${_q_role}: ${_q_dealt}" "use that set" \
        "The Questions: line names a set the plan's rigor does not deal this reader:
    Role:  ${DP_SUBAGENT}
    Given: ${_q_set//,/, }
    Dealt: ${_q_dealt//,/, } (${_q_level}, scale ${_q_scale})

Each question is read by the one role the rigor deals it to:
${_q_holders}
Fix: write the dealt set, on a line of its own —
    ${_q_fixline}

Then retry the dispatch."
    else
      DP_QUESTIONS="$_q_set"; _q_admitted=1
    fi
    # A READER NAMES A RECORD FOR EACH QUESTION IT IS DEALT (wave-27 T49, A-orch-83; review pass 28
    # B1). It writes one record per question, and `proof-add review` takes a record only if it is
    # the reader's own roster row `deliverable=` or one of its `files=`. A critic dealt two
    # questions with one Expected artifact: and no Files: was admitted here and then could not
    # register its second reading. So the DISTINCT paths of the artifact and the Files: line
    # (a quoted path as its stripped form, a leading ./ aside) must number at least the questions.
    # The count needs no dealing, so it holds with no bound plan too. It is judged once the set
    # itself is admitted, so a brief with a wrong set is told that first and not twice. The row is
    # unchanged.
    #
    # A RECORD IS A PATH UNDER THE RECORD ROOT (wave-27 T57; review pass 35 N1). Counting distinct
    # strings admitted a brief whose second "record" was a scratch file, a directory, a path
    # outside the tree or the artifact spelled again (`x/../a.md`, `//`), each of which the fact
    # verb refuses. So a path counts only when it sits under `<docs-root>/record/` (lib/roots.sh
    # `docs_root`, the one the fact verb resolves, loaded through run.sh) after `.`, `..` and
    # doubled slashes are resolved, a relative path read from the project root; it
    # does not end in `/`; and it is compared in that resolved form. Any other path may stay on
    # Files: (a scratch file) and is not a record.
    #
    # AN ABSOLUTE PATH IS PLACED AS THE FACT VERB PLACES IT (A-orch-101). `proof-add review` reads a
    # record's directory with a logical `cd` and then `pwd -P`, so `..` is folded in the text before
    # the physical read, and the reader exam's `/var/…/s1/.bionic/docs/record/…` is its project's
    # `/private/var/…` record. Here a path's longest existing directory is read the same way and
    # the rest stays text, and the record root the same way, so the wall and the verb give one
    # answer for one path: a symlinked directory that lands outside the root is no record, and a
    # record directory the reader has not made yet still is. ONE RULE FOR EVERY PATH (the A-T57.11
    # ruling): a relative path is anchored at the project root first and then placed the same way,
    # so a link under record/ that leads out of it is no record whichever way the path is spelt.
    #
    # LINEAR IN THE PATH (wave-27 T72; review pass 49 S2). The walk goes forward from `/` and stops
    # at the first segment that is not a directory, since no longer prefix can be one, so a missing
    # segment costs nothing: walking back from the end cost a test and a copy per missing segment,
    # and twenty paths of 2,500 took a reader's dispatch to 17 s, past this hook's 15 s
    # registration. A directory the wall cannot enter places nothing, and the path is no record.
    _dp_rec_place() {  # <path> -> the path anchored at the root, its longest existing directory physical
      local p="$1" d="" rest seg phys
      case "$p" in /*) : ;; *) p="$BIONIC_ROOT/$p" ;; esac
      rest="${p#/}"
      while :; do
        case "$rest" in */*) seg="${rest%%/*}" ;; *) break ;; esac
        [ -d "$d/$seg" ] || break
        d="$d/$seg"; rest="${rest#*/}"
      done
      phys="$(cd "${d:-/}" 2>/dev/null && pwd -P)" || return 1
      printf '%s\n' "${phys%/}/$rest"
    }
    # A RECORD IS A REGULAR FILE, OR A PATH NOT THERE YET (wave-27 T72; review pass 49 S1). The verb
    # takes only a regular file that is not a link, so a path that exists at dispatch as a
    # directory named without its slash, a symlink, a FIFO or a device is no record, and neither is
    # a path over 1,024 bytes, measured as bytes. A path that does not exist yet still is one.
    _dp_rec_candidate() {  # <path> -> its placing when it may be a record, nothing when it is not
      local p="$1" a LC_ALL=C
      [ "${#p}" -le 1024 ] || return 0
      case "$p" in /*) a="$p" ;; *) a="$BIONIC_ROOT/$p" ;; esac
      [ -L "$a" ] && return 0
      [ -e "$a" ] && [ ! -f "$a" ] && return 0
      _dp_rec_place "$p"
    }
    if [ -n "${_q_admitted:-}" ]; then
      _q_nq="$(printf '%s' "$_q_set" | awk -F, '{ print NF }')"
      _q_rroot="$BIONIC_ROOT/.bionic/docs/record"
      if declare -F docs_root >/dev/null 2>&1; then
        _q_dr="$(docs_root "$BIONIC_ROOT" 2>/dev/null)"; [ -n "$_q_dr" ] && _q_rroot="$_q_dr/record"
      fi
      _q_nr="$(printf '%s\n%s\n' "$(brief_field "$LIFTED" deliverable)" "$(brief_field "$LIFTED" files | tr ',' '\n')" \
        | while IFS= read -r _q_p; do [ -n "$_q_p" ] && _dp_rec_candidate "$_q_p"; done \
        | awk -v root="$BIONIC_ROOT" -v rr="$(_dp_rec_place "$_q_rroot")" '
          function resolve(p,   n, i, seg, out, k, dir) {
            if (p !~ /^\//) p = root "/" p
            dir = (p ~ /\/(\.\.?)?$/)
            n = split(p, seg, "/"); k = 0
            for (i = 1; i <= n; i++) {
              if (seg[i] == "" || seg[i] == ".") continue
              if (seg[i] == "..") { if (k > 0) k--; continue }
              out[++k] = seg[i]
            }
            p = ""; for (i = 1; i <= k; i++) p = p "/" out[i]
            return (p == "" ? "/" : p) (dir ? "/" : "")
          }
          BEGIN { if (rr != "") rr = resolve(rr) }
          $0 == "" || rr == "" { next }
          { r = resolve($0) }
          r ~ /\/$/ || index(r, rr "/") != 1 { next }
          !seen[r]++ { n++ }
          END { print n + 0 }')"
      if [ "$_q_nr" -lt "$_q_nq" ]; then
        _q_pl="s"; [ "$_q_nr" -eq 1 ] && _q_pl=""
        _q_ql="s"; [ "$_q_nq" -eq 1 ] && _q_ql=""
        dp_finding "dealt ${_q_nq} question${_q_ql}, names ${_q_nr} record${_q_pl}" "one Files: record per question" \
          "A reader writes one record per question it is dealt, and this brief names fewer records:
    Role:      ${DP_SUBAGENT}
    Questions: ${_q_set//,/, }
    Records:   ${_q_nr} (each path under ${_q_rroot#"$BIONIC_ROOT"/}/, the Expected artifact: and the Files: line, counted once)

The fact verb (proof-add review) takes a record only from the reader's own roster row: its
deliverable= or one of its files=. A record the brief never named is one the reader cannot
register, and amend cannot add it once the reader has closed.

Fix: list one record per question under Files:, the Expected artifact: among them —
    Files: path/one.md, path/two.md

Then retry the dispatch."
      fi
    fi
    ;;
esac

# ============================== THE CONTRACT GRAMMAR'S CHECKS (wave-20 T6; REQ-4, D4, Δ10)
#
# ONE GRAMMAR, THREE DOORS. The arms that judge Files:, Suites: and Re-executes: — a literal
# declaration, the run cap, the dropped suite, the missing instrument, the auditor's waiver —
# and the derivation of the suite set the row records, live in payload/scripts/lib/brief.sh's
# `brief_validate_fields`, which `session-poker.sh amend` and `task-add` call too. An amended
# contract is held to exactly a fresh dispatch's standard (Δ10); a copy of these arms here
# would be the three-readers defect REQ-10 removed, in a new place.
#
# NOTHING MOVED IN BEHAVIOUR. The library reports each fault to the sink in the order these
# arms ran, and the sink is `dp_finding`, so the pool, its first-fault line and every detail
# are what they were. Its loud-but-passing line goes through this file's `warn()`.
#
# RC 2 IS THE EARLY SPEND (Step-6 architecture review §2.2). The derivation overran its bound,
# its finding is already pooled, and the suite set the full-run wall below reads was never
# built. That wall is this file's, so this file says `not checked` for it and spends the pool here: there is nothing below but walls that depend on
# the derivation, and an arm added below that does NOT must be pooled above this call.
dp_brief_sink() {  # finding <fact> <fix> <detail> | warn <line>
  case "$1" in
    finding) dp_finding "$2" "$3" "$4" ;;
    warn)    warn "$2" ;;
  esac
}
DP_BRIEF_RC=0
brief_validate_fields "$LIFTED" "$DP_SUBAGENT" "$BIONIC_ROOT" dp_brief_sink || DP_BRIEF_RC=$?
SUITES_ALLOWED="$BRIEF_SUITES_ALLOWED"
SUITES_SOURCE="$BRIEF_SUITES_SOURCE"
if [ "$DP_BRIEF_RC" -eq 2 ]; then
  dp_not_checked "full-run" "a suite set"
  dp_refuse_findings
fi

# ============================================== A DECLARED DEBT (wave-27 T31; REQ-14, D23)
#
# A ROW MAY LAND RED BY DESIGN, ON ONE SUITE, UNTIL ONE NAMED BLOCKER CLEARS. A brief declares it
# on two lines of their own, `Lands-red: <suite> until <ext:slug | approval:name>` and
# `Red-evidence: <path under record/>`, and this arm is the declaration's ONE WRITER: it records
# both on the row as `lands_red=` and `red_evidence=`, `amend` refuses to add either, and `land`
# honours a red last run of exactly that suite only on a row that carries them (lib/worktree.sh).
# It refuses a declaration with no evidence line, a suite outside the set this row may run (the
# set the contract checks above derived, so it sits below them), and a token of any other shape.
# A PREDICATE OVER WHAT IT IS HANDED: the lift, the suite set and the bound plan's `## Tasks` (read
# by units.sh, as the approval and regression walls above read it); no git, no roster.
#
# AND (wave-27 T67; review pass 46 B4, S1, S4, N1, N2, N3): one declaration per brief; one suite
# FILE, `<name>.test.sh`, never the full-suite runner however it is spelled; an `approval:<name>`
# token only when a row of the bound plan reads it (the names `approve` accepts) and no integrate row
# waits on it, for a debt must clear before integration; and evidence that is a file under the run's
# record root, placed as the fact verb places a record.
DP_LANDS_RED=""; DP_RED_EVIDENCE=""
_lr_line="$(brief_field "$LIFTED" lands_red)"
if [ -n "$_lr_line" ]; then
  _lr_ev="$(brief_field "$LIFTED" red_evidence)"
  read -r _lr_suite _lr_until _lr_tok _lr_more <<DP_LR
$_lr_line
DP_LR
  _lr_suite="${_lr_suite##*/}"; _lr_ap=""
  _lr_n="$(brief_field "$LIFTED" lands_red_n)"
  if [ -n "$_lr_n" ]; then
    dp_finding "the brief has ${_lr_n} Lands-red: lines" "keep one Lands-red: line" \
      "A row lands red on ONE suite until ONE blocker clears, and this brief declares ${_lr_n}:
    First: Lands-red: ${_lr_line}

Only one line could be honoured, and which one would be a guess, so none is.

Fix: keep one Lands-red: line; plan a second red as a row of its own.

Then retry the dispatch."
  fi
  _lr_runner=""
  for _lr_w in $_lr_line; do
    [ "$_lr_w" = until ] && break
    [ "${_lr_w##*/}" = run.sh ] && _lr_runner=1
  done
  if [ -n "$_lr_runner" ]; then
    dp_finding "Lands-red: names the full-suite runner" "name one <name>.test.sh" \
      "The Lands-red: line names run.sh, and the full-suite runner is never a declared red:
    Given: Lands-red: ${_lr_line}

Its run speaks for every suite at once, so one declaration would land the whole regression red.
A row may land red on one suite file only.

Fix: name the one suite that is red by design —
    Lands-red: <name>.test.sh until <token>

Then retry the dispatch."
  elif case "$_lr_suite" in ?*.test.sh) false ;; *) true ;; esac; then
    dp_finding "Lands-red: names no <name>.test.sh" "name one <name>.test.sh" \
      "The Lands-red: line names no suite file:
    Given: Lands-red: ${_lr_line}

A row may land red on one suite FILE, <name>.test.sh, and nothing else.

Fix: write the line as —
    Lands-red: <name>.test.sh until <token>

Then retry the dispatch."
  fi
  _lr_tok_ok=""
  if [ "$_lr_until" = until ] && [ -n "$_lr_tok" ] && [ -z "$_lr_more" ]; then
    _lr_ext_re="$(_units_ext_re)"; _lr_ap_re='^approval:[A-Za-z0-9][A-Za-z0-9._-]*$'
    if [[ "$_lr_tok" =~ $_lr_ext_re ]] || [[ "$_lr_tok" =~ $_lr_ap_re ]]; then
      _lr_tok_ok=1
    fi
  fi
  # AN APPROVAL A DEBT CAN WAIT FOR (wave-27 T67; review pass 46 S4, N1). `approve` records only a
  # name an open row reads (units.sh `units_approval_names`), so a name no row reads can never clear;
  # and an approval an integrate row reads comes after the judgment the debt must clear before.
  case "$_lr_tok_ok:$_lr_tok" in
    1:approval:?*)
      _lr_ap="${_lr_tok#approval:}"
      _lr_names="$( { [ -n "$PLAN" ] && units_approval_names "$PLAN"; } 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
      _lr_integ="$( { [ -n "$PLAN" ] && units_rows "$PLAN"; } 2>/dev/null | awk -F'\t' -v n="$_lr_ap" '
        $3 == "integrate" { m = split($13, a, ","); for (k = 1; k <= m; k++) { t = a[k]; gsub(/^[ \t]+|[ \t]+$/, "", t); sub(/^live:/, "", t); if (t == "approval:" n) { print $1; exit } } }')"
      if [ -n "$_lr_integ" ]; then
        _lr_tok_ok=""
        dp_finding "approval:$(bionic_trunc "$_lr_ap" 18) is read at integration" "pick an earlier token" \
          "The Lands-red: line waits on an approval the integrate row reads:
    Given:     Lands-red: ${_lr_line}
    Integrate: ${_lr_integ} reads approval:${_lr_ap}

A declared debt must be cleared before integration is admitted, and this approval
comes after the step a debt must clear before: the debt could be covered only after the
judgment it must precede.

Fix: wait on an approval a row before integration reads, or on an ext:<slug> token.

Then retry the dispatch."
      elif case " $_lr_names " in *" $_lr_ap "*) false ;; *) true ;; esac; then
        _lr_tok_ok=""
        dp_finding "approval:$(bionic_trunc "$_lr_ap" 25) is read by no row" "name one a row reads" \
          "The Lands-red: line waits on an approval no row of the bound plan reads:
    Given:     Lands-red: ${_lr_line}
    Rows read: ${_lr_names:-(no named approval)}

session-poker.sh approve records only a name a row reads, so this one could never be recorded
and the debt could never clear.

Fix: name one of the approvals the rows read, or add a row that reads this one.

Then retry the dispatch."
      fi ;;
  esac
  # A line naming the runner is told that, once: its suite and token are not judged besides.
  if [ -z "$_lr_tok_ok" ] && [ -z "${_lr_ap:-}" ] && [ -z "$_lr_runner" ]; then
    dp_finding "Lands-red: names no blocker token" "use ext:<slug> or approval:<name>" \
      "The Lands-red: line does not read <suite> until <token>, its token one of two forms:
    Given: Lands-red: ${_lr_line}

A declared red lands until ONE named blocker clears, and the judge can only tell when a
token of these two forms has cleared:
    ext:<slug>        an external blocker, as the ## Tasks reads cells write it
    approval:<name>   the user's act, written by session-poker.sh approve <name>

Fix: write the line as —
    Lands-red: ${_lr_suite:-<suite>} until approval:<name>

Then retry the dispatch."
  fi
  if [ -z "$_lr_ev" ]; then
    dp_finding "Lands-red: with no Red-evidence: line" "add the Red-evidence: line" \
      "The brief declares a suite that lands red, and names no evidence of why:
    Given: Lands-red: ${_lr_line}

A red is honoured at land only beside an evidence file under record/ that names the head it
was red at (a line head: <40-hex>), so the row can say why it is red by design.

Fix: add this line to the brief, on a line of its own —
    Red-evidence: <path under record/>

Then retry the dispatch."
  fi
  _lr_in=""
  case "$_lr_suite" in ''|*[[:space:]]*) : ;; *) case " $SUITES_ALLOWED " in *" $_lr_suite "*) _lr_in=1 ;; esac ;; esac
  if [ -z "$_lr_in" ] && [ -z "$_lr_runner" ]; then
    # The name rides in the fact, cut to what the 100-column line leaves it (wave-27 T67; review pass
    # 46 S1): `bionic: dispatch refused — `, the fixed words and ` (<fix>)` take 85.
    dp_finding "Lands-red: $(bionic_trunc "${_lr_suite:-<none>}" 15) is outside Suites:" "name a suite the row runs" \
      "A row may land red only on a suite it runs, and this one's suite set does not hold it:
    Given:  Lands-red: ${_lr_line}
    Suites: ${SUITES_ALLOWED:-(none)}

Fix: name one of the row's own suites on the Lands-red: line, or add the suite to the brief's
Suites: or Files: line so the row runs it.

Then retry the dispatch."
  fi
  # THE EVIDENCE IS A FILE UNDER THE RUN'S RECORD ROOT (wave-27 T67; review pass 46 N3), placed as
  # the fact verb places a record: a `record/…` path from the docs root, any other relative path from
  # the project root, an absolute one as given; the longest existing directory read physically, the
  # rest in the text with `.` and `..` resolved; the record root read the same way.
  _lr_ev_ok=""
  if [ -n "$_lr_ev" ]; then
    _lr_docs="$BIONIC_ROOT/.bionic/docs"
    if declare -F docs_root >/dev/null 2>&1; then
      _lr_d="$(docs_root "$BIONIC_ROOT" 2>/dev/null)"; [ -n "$_lr_d" ] && _lr_docs="$_lr_d"
    fi
    _lr_place() {  # <absolute path> -> its longest existing directory physical, the rest resolved in the text
      local p="$1" d rest phys
      d="${p%/*}"; rest="${p##*/}"
      while [ -n "$d" ] && [ ! -d "$d" ]; do rest="${d##*/}/$rest"; d="${d%/*}"; done
      phys="$(cd "${d:-/}" 2>/dev/null && pwd -P)" && p="${phys%/}/$rest"
      printf '%s\n' "$p" | awk '{ n = split($0, s, "/"); k = 0
        for (i = 1; i <= n; i++) { if (s[i] == "" || s[i] == ".") continue; if (s[i] == "..") { if (k > 0) k--; continue } o[++k] = s[i] }
        p = ""; for (i = 1; i <= k; i++) p = p "/" o[i]; print (p == "" ? "/" : p) }'
    }
    case "$_lr_ev" in
      /*) _lr_abs="$_lr_ev" ;;
      record/*) _lr_abs="$_lr_docs/$_lr_ev" ;;
      *) _lr_abs="$BIONIC_ROOT/${_lr_ev#./}" ;;
    esac
    _lr_rr="$(_lr_place "$_lr_docs/record/x")"; _lr_rr="${_lr_rr%/x}"
    case "$_lr_ev" in */) _lr_at="" ;; *) _lr_at="$(_lr_place "$_lr_abs")" ;; esac
    case "$_lr_at" in "$_lr_rr"/?*) _lr_ev_ok=1 ;; esac
    if [ -z "$_lr_ev_ok" ]; then
      dp_finding "Red-evidence: is not under record/" "put the file under record/" \
        "The Red-evidence: path is not a file under the run's record root:
    Given:   Red-evidence: ${_lr_ev}
    Read as: ${_lr_at:-(a directory)}
    Root:    ${_lr_rr}/

The evidence is the run's record of why the row is red at its head, so it lives where the run's
records live, read as the fact verb reads one: a record/... path from the docs root, any other
relative path from the project root, an absolute one as given.

Fix: write the evidence under record/ and name it there —
    Red-evidence: record/<wave>/<row>-red.md

Then retry the dispatch."
    fi
  fi
  if [ -n "$_lr_tok_ok" ] && [ -n "$_lr_ev" ] && [ -n "$_lr_ev_ok" ] && [ -n "$_lr_in" ] && [ -z "$_lr_n" ] \
     && [ -z "$_lr_runner" ] && case "$_lr_suite" in ?*.test.sh) true ;; *) false ;; esac; then
    DP_LANDS_RED="$_lr_suite until $_lr_tok"; DP_RED_EVIDENCE="$_lr_ev"
  fi
fi

# ================================ THE ROW AND THE SUITES IT LANDS ON (wave-28 T7; REQ-1, REQ-3, D4, D17)
#
# A BRIEF NAMES ITS ROW AND THE SUITES THAT ROW LANDS ON. `Row: <id>` binds the dispatch to a row of
# the bound plan; the launch record, the fill, the stop wall, the landing, the approval arm and the
# full-run regression read it first and the name match after (a `Row:` that contradicts the name's row is
# refused below). `Lands-on: <suite>[, <suite>]` names the suites `ready`
# runs, exactly those; `Lands-on: none <reason>` names none, and says why. The lift writes both in one
# spelling (brief.sh); this arm is their one writer onto the row and refuses: a writer that binds a row
# and carries no Lands-on: line; `none` with no reason; a suite outside the set the checks above
# derived (`SUITES_ALLOWED`, the set a declared red is held to); and a Row: naming no row of the plan.
# A dispatch that binds no row (no Row: label, and a name that is no row id) has no row to land, so
# it owes no Lands-on: line.
DP_LANDS_ON="$(brief_field "$LIFTED" lands_on)"
_lo_reason="$(brief_field "$LIFTED" lands_on_reason)"; _lo_bad="$(brief_field "$LIFTED" lands_on_bad)"
_lo_ids=""
[ -n "$PLAN" ] && [ -f "$PLAN" ] && _lo_ids="$(units_rows "$PLAN" 2>/dev/null | awk -F'\t' '$1 != "" { print $1 }')"
# Membership by a whole line, read in the shell: a quitting `grep -q` fed from a pipe is the idiom
# cross-gate §BP refuses (the writer can die of SIGPIPE).
_lo_known=""
case $'\n'"$_lo_ids"$'\n' in *$'\n'"$DP_ROW"$'\n'*) _lo_known=1 ;; esac
if [ -n "$DP_ROW" ] && [ -n "$_lo_ids" ] && [ -z "$_lo_known" ]; then
  dp_finding "Row: $(bionic_trunc "$DP_ROW" 20) names no plan row" "name a ## Tasks row id" \
    "The Row: label binds this dispatch to a row of the bound plan, and the plan has no such row:
    Given: Row: ${DP_ROW}
    Plan:  ${PLAN}

Fix: name the id of the row this agent runs, as the plan's ## Tasks table spells it.

Then retry the dispatch."
fi
# A LABEL AND A NAME THAT DISAGREE ARE A LIE (wave-28 T55): the label binds the dispatch to one row and
# the name's match to another. Only a name that matches a row is judged; a name that matches none with
# a Row: that names one is T7's design and stays admitted.
_lo_agrees=""
case $'\n'"$DP_NAME_ROWS"$'\n' in *$'\n'"$DP_ROW"$'\n'*) _lo_agrees=1 ;; esac
if [ -n "$DP_ROW" ] && [ -n "$_lo_known" ] && [ -n "$DP_NAME_ROWS" ] && [ -z "$_lo_agrees" ]; then
  dp_finding "Row: $(bionic_trunc "$DP_ROW" 11) is not the name's row $(bionic_trunc "$DP_NAME_ROW" 11)" \
    "rename or drop Row:" \
    "The Row: label binds this dispatch to one row of the bound plan and the agent's name to another:
    Row:  ${DP_ROW}
    Name: ${DP_ROW_NAME} (row ${DP_NAME_ROW})
    Plan: ${PLAN}

Every wall reads one row per dispatch, so a label and a name that disagree leave the walls asking
different rows. A name that matches no row may carry any Row:.

Fix: name the agent for its row (the name the Patrol's FILL line printed), or give Row: the id that
name matches, or drop Row: and let the name bind.

Then retry the dispatch."
fi
_lo_binds=""
[ -z "$DP_BOUND_ROW" ] || _lo_binds=1
if [ -z "$DP_LANDS_ON" ] && [ -z "$_lo_bad" ] && [ -n "$_lo_binds" ] && ! role_is_readonly "$DP_SUBAGENT"; then
  dp_finding "the brief has no Lands-on: line" "add Lands-on: <suites> or none <why>" \
    "A writer's row lands on the suites its brief names, and this brief names none:
    Dispatch: ${DP_ROW_NAME:-<unnamed>}${DP_ROW:+ (Row: ${DP_ROW})}
    Suites:   ${SUITES_ALLOWED:-(none)}

ready runs exactly the suites the row's launch line names, so a row with none cannot land.

Fix: add a line of its own naming the suites this row lands on, from its suite set —
    Lands-on: <suite>[, <suite>]
  or, for a row no suite proves —
    Lands-on: none <reason>

Then retry the dispatch."
fi
if [ "$DP_LANDS_ON" = none ] && [ -z "$_lo_reason" ]; then
  dp_finding "Lands-on: none gives no reason" "write the reason after none" \
    "A row may land on no suite only with a reason the reader can check:
    Given: Lands-on: none

Fix: say why no suite proves this row, on the same line —
    Lands-on: none <reason>

Then retry the dispatch."
fi
_lo_out=""
if [ -n "$_lo_bad" ]; then
  _lo_out="${_lo_bad%% *}"
elif [ -n "$DP_LANDS_ON" ] && [ "$DP_LANDS_ON" != none ]; then
  for _lo_s in ${DP_LANDS_ON//,/ }; do
    case " $SUITES_ALLOWED " in *" $_lo_s "*) : ;; *) _lo_out="$_lo_s"; break ;; esac
  done
fi
if [ -n "$_lo_out" ]; then
  # The name rides in the fact, cut as the declared red's is: the fixed words and the fix take 84.
  dp_finding "Lands-on: $(bionic_trunc "$_lo_out" 15) is outside Suites:" "name a suite the row runs" \
    "A row lands only on suites it runs, and this one's suite set does not hold this one:
    Given:  Lands-on: ${DP_LANDS_ON:+${DP_LANDS_ON} }${_lo_bad}
    Suites: ${SUITES_ALLOWED:-(none)}

Fix: name only suites of the row's own set, each as <name>.test.sh or tests/<name>.test.sh, or add
the suite to the brief's Suites: or Files: line so the row runs it.

Then retry the dispatch."
fi

# ===================================================== THE FULL-RUN WALL (wave-26 REQ-3, D6)
# (replaces the one-regression wall, AC-24, and the regression-once wall, REQ-5 D7, of 1.10.)
#
# THE FULL SUITE IS TIED TO THE CODE STATE, NOT TO A COUNT OF RUNS. Through 1.10 this file
# counted full-tree rows on the roster and charged one written cause line on the plan per
# extra run, and a sibling arm held the regression while any step-4 row was open unless such a line
# released it. A count says nothing about what the tree needs: a re-proof after an outside merge
# cost a sentence, and a second run over a head already proved cost one too. Both arms, and the
# cause line, are gone.
#
# ONE QUESTION, ASKED OF THE PROOF RECORD. `proof_state` (lib/proof.sh) is the one place that
# runs git for this decision, and it answers in three words: `covered` (the working branch's head
# is the one the last regression proof names), `bounded` (the change since that proof is provable by
# the suites the map names for it) or `unbounded` (anything else, with its reason). A full run is
# owed only when the change cannot be bounded; covered and bounded are refused, and the bounded
# refusal names the suites that prove the change.
#
# AND ONE HOLD, ASKED OF THE READY SET. Unbounded is not enough while a row the regression waits on
# still writes tracked files: a run now proves a head that does not survive the row landing.
# ONLY THE REGRESSION'S OWN WAITS HOLD IT (wave-26 T52; review 14 B1, ruling R1). Through T5 this arm
# counted every open row with its own reading of `Files`, so the release, which waits FOR the
# regression, held the regression for ever, and a `record/…` path read as tracked. Now lib/units.sh
# `units_floor_holds` answers: the rows the regression row waits on through its deps and its reads,
# judged by the ready set's own program, not landed, that write a tracked file by its
# `writes_head` — one owner for both questions. The regression row is the dispatch's own, by
# `DP_BOUND_ROW`, the one reader (wave-28 T55: the brief's `Row:`, else the row its name matches); a
# dispatch that binds no row is held by what the plan's open verify and test rows wait on.
#
# LOADED LAZILY, LIKE brief.sh's BOUND. proof.sh is sourced at the one arm that spends it, from
# the directory the loader settled on. A copied hook whose library directory predates proof.sh
# says `not checked` for this arm rather than refusing a dispatch for a library it cannot see.
#
# PLAN-FREE SESSIONS SKIP IT. With no bound plan there is no proof record and no ledger.
fr_open_writers() {  # -> `id<TAB>step<TAB>status` for each row the regression waits on that writes the head
  local floor=""
  [ -n "$PLAN" ] && [ -f "$PLAN" ] || return 0
  [ -z "$DP_BOUND_ROW" ] || floor="$(units_rows "$PLAN" 2>/dev/null \
    | awk -F'\t' -v id="$DP_BOUND_ROW" '$1 != "" && $1 == id { print $1; exit }')"
  units_floor_holds "$PLAN" "$floor" 2>/dev/null
}
# fr_fit <budget> <item>... -> the items comma-joined while they fit <budget> columns, then
# ` +<n>` for the rest; at least the first item, cut to the budget, is always named.
fr_fit() {
  local budget="$1" out="" shown=0 n=0 full=0 sep cand; shift
  for cand in "$@"; do
    n=$((n + 1))
    [ "$full" -eq 0 ] || continue
    sep=""; [ -z "$out" ] || sep=", "
    if [ $((${#out} + ${#sep} + ${#cand})) -le "$budget" ]; then
      out="$out$sep$cand"; shown=$((shown + 1))
    else
      full=1
    fi
  done
  if [ "$shown" -eq 0 ] && [ "$n" -gt 0 ]; then
    out="$(printf '%s' "$1" | cut -c1-"$budget")"; shown=1
  fi
  [ "$shown" -lt "$n" ] && out="$out +$((n - shown))"
  printf '%s' "$out"
}
if [ -z "$SUITES_ALLOWED" ]; then
  # THE ARM'S OWN DEPENDENCY, STATED (AC-8.2): its whole input is the set built above, and a
  # brief that produced none leaves it unable to answer rather than answering "no".
  dp_not_checked "full-run" "a suite set"
fi
case " $SUITES_ALLOWED " in
  *" run.sh "*)
    if [ -n "$PLAN" ]; then
      if ! declare -F proof_state >/dev/null 2>&1 && [ -r "${BIONIC_LIB:-}/proof.sh" ]; then
        # shellcheck source=/dev/null
        . "$BIONIC_LIB/proof.sh"
      fi
      _fr_state=""
      if declare -F proof_state >/dev/null 2>&1; then
        _fr_state="$(proof_state "$PLAN" "$BIONIC_ROOT" 2>/dev/null)"
      fi
      _fr_moment="The full suite runs once, on the head being released; after that pass a later
change is proved by its affected suites, and a second full run is needed only when the
change cannot be bounded: a merge from outside the run, or a changed file the map answers
with every suite or with none."
      _fr_proof="$(proof_last_line "$PLAN" floor 2>/dev/null)"
      _fr_head="$(proof_last "$PLAN" floor 2>/dev/null)"
      _fr_short="$(printf '%.7s' "$_fr_head")"
      case "$_fr_state" in
        '')
          dp_not_checked "full-run" "the proof record (lib/proof.sh)" ;;
        covered*)
          # THE RELEASED HEAD IS NAMED (T52; review 14 N6). proof_state says which working head it
          # judged; an empty change since the proof is covered too (A-T5.5), so that head can
          # differ from the proof's, and the line names the head being released.
          _fr_cur="${_fr_state#covered}"; _fr_cur="${_fr_cur#$'\t'}"
          _fr_tree=""
          if [ -n "$_fr_cur" ] && [ "$_fr_cur" != "$_fr_head" ]; then
            _fr_tree=" (the tree proved at ${_fr_short})"
            _fr_short="$(printf '%.7s' "$_fr_cur")"
          fi
          _dp_detail="The working branch's head ${_fr_short}${_fr_tree} is the tree the plan's last regression proof read:
    ${_fr_proof}

${_fr_moment}

Fix: dispatch no full run. That proof stands for this head; a change landed after
it is proved by the suites it affects, named when the full run is refused again."
          dp_finding "head ${_fr_short} is already proved" "keep the regression proof; run nothing" "$_dp_detail" ;;
        bounded*)
          _fr_suites="${_fr_state#*$'\t'}"
          # THE LIST STAYS READABLE AND THE FIX STAYS WHOLE (A-T5.4). The detail lists at most
          # twelve suites, one per line, then counts the rest; the `Suites:` line below it names
          # every one, because a brief built from a shortened list would prove less than the
          # change needs.
          _fr_n=0; _fr_list=""; _fr_line=""
          set -f
          for _fr_s in $_fr_suites; do
            _fr_n=$((_fr_n + 1))
            [ "$_fr_n" -le 12 ] && _fr_list="${_fr_list}    ${_fr_s}
"
            _fr_line="${_fr_line:+$_fr_line }tests/${_fr_s}"
          done
          [ "$_fr_n" -gt 12 ] && _fr_list="${_fr_list}    … and $((_fr_n - 12)) more
"
          # shellcheck disable=SC2086
          _fr_names="$(fr_fit 26 $_fr_suites)"
          set +f
          _dp_detail="The change since the regression proof at ${_fr_short} is bounded: the map answers every
changed file, and ${_fr_n} suite(s) prove it:
${_fr_list}
${_fr_moment}

Fix: dispatch those suites instead of the full tree. This brief line names all ${_fr_n}:
    Suites: ${_fr_line}"
          dp_finding "bounded: ${_fr_names}" "run those suites, not the tree" "$_dp_detail" ;;
        unbounded*)
          _fr_why="${_fr_state#*$'\t'}"
          _fr_open=""
          # A copied hook whose units.sh predates the regression's holds cannot ask; it says so.
          if declare -F units_floor_holds >/dev/null 2>&1; then
            _fr_open="$(fr_open_writers)"
          else
            dp_not_checked "full-run hold" "the regression's holds (lib/units.sh units_floor_holds)"
          fi
          if [ -n "$_fr_open" ]; then
            _fr_lines=""; _fr_idv=""
            while IFS=$'\t' read -r _fo_id _fo_step _fo_status; do
              [ -n "$_fo_id" ] || continue
              _fr_lines="${_fr_lines}    $(printf '%-4s' "$_fo_id") (step ${_fo_step}, ${_fo_status})
"
              _fr_idv="${_fr_idv:+$_fr_idv }$_fo_id"
            done <<FR_OPEN_ROWS
$_fr_open
FR_OPEN_ROWS
            set -f
            # shellcheck disable=SC2086
            _fr_ids="$(fr_fit 9 $_fr_idv)"
            set +f
            _dp_detail="The change since the last regression proof cannot be bounded (${_fr_why}),
so a full run is owed. But rows the regression waits on still write tracked files, and a run now
proves a head that does not survive them landing:
${_fr_lines}
${_fr_moment}

Fix: land or drop those rows, then dispatch the full run."
            dp_finding "rows write tracked files: ${_fr_ids}" "land them, then dispatch it" "$_dp_detail"
          fi
          ;;
      esac
    fi
    ;;
esac

# ================================================ THE ONE REFUSAL, FOR EVERY FAULT
#
# THE LAST ARM THAT CAN FIND A FAULT IS ABOVE THIS LINE, and everything below is the
# LEDGER. So this is where the list is spent: one refusal carrying every fault every arm
# from the arming wall down found, in file order, or a silent return when they found none.
#
# IT MOVED DOWN PAST THE FULL-RUN WALL (wave-14 REQ-8; the one-regression wall then).
# It used to sit between the
# brief-shape arms and that wall, which was right while only the brief-shape arms pooled
# and wrong the moment the state arms joined them: a dispatch over budget AND re-running
# the full tree was refused for the budget, and met the full-run wall on the next
# attempt — the exact shape AC-8.1 forbids ("fixing the first alone produces a refusal
# naming a fault the first could have named").
#
# IT STAYS ABOVE THE JOURNAL, for the reason each arm used to exit where it stood: a
# dispatch the gate is about to refuse must never be journalled as a launch — and `deny`
# exits 0, which is exactly the status the ledger below would otherwise read as a launch.
dp_refuse_findings

# ============================= THE BRIEF BODY ADVISORY (wave-24 T14; REQ-8, D13)
#
# A dispatch that reached this line is allowed, so what follows is only ever said, never decided.
# `brief_body_advisories` (payload/scripts/lib/brief.sh) reads the PROSE the contract grammar
# never sees for the two shapes that meet a wall minutes later — a `bash tests/x.test.sh` the
# row does not budget, and an edit of a path outside `Files:` — and each finding goes out on
# the model's channel, ending in the `amend` line that would declare it. Placed below the spend
# so a refused dispatch carries only its refusal, and above the ledger so the advice precedes the
# journalled launch; nothing it does can change the exit status (AC-8.4).
#
# THE CHANNEL IS THE MODEL'S (A-orch-20): `hookSpecificOutput.additionalContext` on stdout, exit 0.
# An advisory the model never reads is silence, and AC-8.1/8.3 fail on silence; stderr from a
# passing PreToolUse reaches nobody the author is, and is not on refuse.sh's measured channel
# table at all. That table scores `additionalContext` model:no, but it was a headless stream-json
# measurement. Observed live in the interactive orchestrator session (2026-10-03): walls.sh's
# farm-out tier-1 nudge, which rides this same field, arrived as "PreToolUse:Bash hook additional
# context: farm-out checkpoint ...", so the channel does reach the model there.
#
# THE EMITTER IS THE FARM-OUT NUDGE'S, NOT A SECOND ONE: `_fold_emit_context` (lib/fold.sh) builds
# the object through `jq`, so no JSON is escaped by hand here. This is the only stdout this path
# prints (a refusal exited above, and nothing below writes to it), so it is one object by
# construction. With no `jq` the lines fall back to `warn`, as fold.sh does for its own nudge.
# The poker path goes in as ONE shell word (wave-24 T29, critic I2): the amend line prints it
# verbatim, and a plugin root with a space split in two when pasted.
_dp_adv_all=$(brief_body_advisories "$(_jq '.tool_input.prompt')" "$AGENT_NAME" "$C_FILES" "$SUITES_ALLOWED" "$C_RE_EXECUTES" "$(refuse_shell_word "$HOOK_DIR/session-poker.sh")")
# THE DEBT ARM (wave-30 T22; D2, P2, AC-11.3). Debt is burned by the next row whose Files touch its
# concept, so an allowed brief whose `Files:` covers a site of an unburned item of the run's ledger
# (lib/proof.sh `proof_debt_hits`: the path, a directory above it, or a glob over it) carries the item,
# and the item's touches go up by one through the ledger's one writer, `session-poker.sh debt touched`,
# whose answer is the count printed. A touch the verb cannot write is still advised, at the count the
# ledger holds. Below the spend for the reason the body advisory is: a refused dispatch touches nothing.
_dp_debt=""
if [ -n "$PLAN" ] && [ -n "$C_FILES" ]; then
  if ! declare -F proof_debt_hits >/dev/null 2>&1 && [ -r "${BIONIC_LIB:-}/proof.sh" ]; then
    # shellcheck source=/dev/null
    . "$BIONIC_LIB/proof.sh"
  fi
  if declare -F proof_debt_hits >/dev/null 2>&1; then
    _dp_debt_hits="$(proof_debt_hits "$(proof_debt_ledger_path "$BIONIC_ROOT" "$PLAN" 2>/dev/null)" "$C_FILES" 2>/dev/null | awk -F'\t' '$6 == "-"')"
    _dp_dseen=" "; _dp_dall=""
    while IFS='	' read -r _dp_dc _dp_dk _ _ _dp_dn _; do
      [ -n "$_dp_dc" ] || continue
      # One call per concept: the verb touches every unburned item of it, whatever its kind.
      case "$_dp_dseen" in *" $_dp_dc "*) : ;; *)
        _dp_dseen="$_dp_dseen$_dp_dc "
        _dp_dall="$_dp_dall
$(cd "$BIONIC_ROOT" 2>/dev/null && bash "$HOOK_DIR/session-poker.sh" debt touched "$_dp_dc" "$PLAN" 2>/dev/null)" ;;
      esac
      _dp_dsaid="$(printf '%s\n' "$_dp_dall" | awk -v c="$_dp_dc" -v k="$_dp_dk" \
        '$1 == "poker:" && $2 == "debt" && $3 == "touched" && $5 == c && $6 == k && $7 == "touches" && $8 ~ /^[0-9]+$/ { print $8; exit }')"
      _dp_debt="${_dp_debt:+$_dp_debt
}debt: $_dp_dc $_dp_dk touches ${_dp_dsaid:-$_dp_dn} — burn it in this row or say why not"
    done <<DP_DEBT_EOF
$_dp_debt_hits
DP_DEBT_EOF
  fi
fi
[ -z "$_dp_debt" ] || _dp_adv_all="${_dp_adv_all:+$_dp_adv_all
}$_dp_debt"
if [ -n "$_dp_adv_all" ]; then
  _dp_adv_ctx="brief advisory (the dispatch is allowed; nothing was refused):
$_dp_adv_all"
  _dp_adv_json=$(_fold_emit_context PreToolUse "$_dp_adv_ctx")
  if [ -n "$_dp_adv_json" ]; then
    printf '%s\n' "$_dp_adv_json"
  else
    while IFS= read -r _dp_adv; do
      [ -n "$_dp_adv" ] && warn "$_dp_adv"
    done <<ADV_EOF
$_dp_adv_all
ADV_EOF
  fi
fi

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
# On the pass side — a dispatch that got this far has been allowed (and, from inside an agent,
# is a read-only role by the delegation arm), and this line only declines to write it down.
# THIS EXIT IS REACHABLE ONLY BY A READ-ONLY ROLE LAUNCHED FROM INSIDE AN AGENT: the delegation
# arm above refuses every other dispatch made there, so nothing that needs a roster row (a
# writer, which is budgeted, contracted and suite-walled) can arrive here. That is what makes
# not journalling safe, and it is why the ruling (wave-28 T70, A-orch-231) keeps the ledger at
# depth one (S20) and does not widen the roster's readers for a `source=delegated` row. It is
# not silent any more: one stderr line says what happened, so the dispatching agent sees that
# this admission carries no row.
if is_agent_context; then
  printf '%s\n' "bionic: dispatch admitted without a roster row — a read-only role launched from inside an agent; the ledger stays at depth one" >&2
  exit 0
fi

# The directory levels of this path were already discharged: the attestation
# check above refuses outright if `.bionic` or `.bionic/tmp` is a symlink, so
# reaching here means both are real directories. The roster FILE is its own
# path and gets its own check — a hostile repo may make this gate fail to
# journal, but must not gain an append to a file it points at (§8).
if [ -L "$ROSTER_FILE" ]; then
  refuse deny dispatch "the roster path is a symbolic link" "remove the link" \
"Roster:  ${ROSTER_FILE}
Reason:  it is a symbolic link, and nothing is ever written through one.

No row was written, so the launch is not admitted: a dispatch the roster does not carry is one no
later wall can judge.

Fix: remove the link (rm ${ROSTER_FILE}), then dispatch again."
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
  ${C_DONE:+"done=${C_DONE}"} \
  "tool_use_id=${TOOL_USE_ID}" \
  "plan=${ROSTER_PLAN}" \
  ${DP_QUESTIONS:+"questions=${DP_QUESTIONS}"} \
  ${DP_LANDS_RED:+"lands_red=${DP_LANDS_RED}"} \
  ${DP_RED_EVIDENCE:+"red_evidence=${DP_RED_EVIDENCE}"} \
  ${DP_ROW:+"row=${DP_ROW}"} \
  ${DP_LANDS_ON:+"lands_on=${DP_LANDS_ON}"}) || ROW=""

# THE ROW IS BUILT AND THE ROSTER IS WRITTEN LAST, and a launch the roster cannot carry is refused
# (wave-28 T70). `roster_row` refuses a field name no reader knows rather than writing it, so an
# empty `$ROW` is a defect in this hook or its library — refused, never appended blank and never
# called journalled. The deadline is disarmed here, before the first byte is written: past this line
# the dispatch is the roster's, and a timer firing between the append and the exit would refuse a
# launch it had already recorded.
DP_DEADLINE_LIVE=0
if [ -z "$ROW" ]; then
  refuse deny dispatch "the launch row did not build" "run /bionic:doctor" \
"Roster:  ${ROSTER_FILE}
Reason:  roster_row (payload/scripts/lib/roster.sh) refused a field of this launch.

No row was written, so the launch is not admitted: a dispatch the roster does not carry is one no
later wall can judge.

Fix: run /bionic:doctor; if it reports nothing, the library and this hook are from different
     versions — reinstall the plugin."
fi
if [ ! -e "$ROSTER_FILE" ]; then
  # A concurrent dispatch in the same session can lose this race and write the
  # header twice; both are comment lines and every reader skips them. The ROWS
  # are what must not interleave, and each is a single short append.
  { roster_header >> "$ROSTER_FILE"; } 2>/dev/null && chmod 600 "$ROSTER_FILE" 2>/dev/null
fi
# No lock, unlike the observation record: that one is a read-modify-write of the whole file, this
# one is a single O_APPEND write of well under a pipe buffer, which the kernel does not interleave.
# A failed append is the shell's own message, read back so the refusal can name the reason.
DP_WERR=""
DP_WROTE=1
DP_WERR=$( { printf '%s\n' "$ROW" >> "$ROSTER_FILE"; } 2>&1 ) || DP_WROTE=0
if [ "$DP_WROTE" -eq 0 ]; then
  refuse deny dispatch "the roster cannot be written" "make it writable" \
"Roster:  ${ROSTER_FILE}
Reason:  ${DP_WERR##*: }

No row was written, so the launch is not admitted: a dispatch the roster does not carry is one no
later wall can judge (the suite wall, amend, the Patrol and the stop guard all read the row).

Fix: make ${STATE_DIR} and the roster writable by this user, then dispatch again."
fi

# The roster carries the launch; what follows is only ever said.
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
