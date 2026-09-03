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
# Attestation filename is per-session (design D-5, slice 4/2):
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
# `active_run` under the payload's project root. A partition maintained by hand was
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

INPUT=$(cat)
_jq() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

# ---------- relevance first (checklist A7): the cheapest possible check,
# before any git resolution or plan-directory walk. Anything that isn't a
# subagent dispatch is none of this gate's business. ----------
TOOL_NAME=$(_jq '.tool_name')
[ "$TOOL_NAME" = "Agent" ] || exit 0

# ---------- ambiguity: cannot even locate the repo -> OPEN, silent ----------
CWD=$(_jq '.cwd')
[ -n "$CWD" ] || exit 0

# A GIT TOPLEVEL IS NO LONGER THE PRECONDITION (bionic 1.4.0, spec AC-12, Decision A2).
# It used to be: `git rev-parse --show-toplevel` had to succeed or the wall exited
# silently. That made the wall's coverage a property of the SHELL's cwd rather than of
# the project — dispatch from a non-git directory that nonetheless sits under a real
# `.bionic` root and every wall in this file went quiet, arming and containment
# included. The precondition is now the project itself: `project_root` finds the
# nearest real `.bionic` ancestor (mapping a linked worktree onto its main repository
# first), and `active_run` decides whether there is anything to protect.

# ---------- the library ----------
#
# One loader idiom, byte-identical in every hook (spec AC-16); its source of truth is
# payload/scripts/lib/loader.sh. FAIL OPEN: this wall protects a dispatch, and a
# dispatch that should have been refused can be stopped and re-run — refusing every
# Agent call on the machine because a file is missing cannot be undone as cheaply.
BIONIC_LIB_WANT="root.sh run.sh session.sh patrol.sh"
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
if [ -n "$BIONIC_LIB_MISSING" ]; then loader_fail_open "dispatch-preflight"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/patrol.sh"

# THE ROOT (spec AC-10). Every path this gate owns hangs off the answer: the
# attestation it reads, the roster it appends, the containment wall it measures
# deliverables against. A worktree that answered with its own tree would write an
# attestation the probe on the other side of the combined preflight then could not
# find — `project_root` maps a linked worktree back onto its main repository, so both
# sides land in one address space. On an ordinary checkout nothing changes.
REPO=$(project_root "$CWD")
[ -n "$REPO" ] && [ -d "$REPO" ] || exit 0


# ---------- THE RUN PREDICATE (AC-7, AC-8) ----------
#
# One reader for "is there a run to protect": lib/run.sh's `active_run`, true while the
# newest plan carrying `## SDLC State` has `current:` below 9, or 9 with no `delivered:`
# Step-9 line, and no `abandoned:` frontmatter line. This was a hand-copied block —
# resolve_docs_root, has_sdlc_state, a newest-.md walk and a `current:` parse — restated
# in five hooks and held together by an agreement suite that could only prove they had
# not drifted YET. One of them drifting was not hypothetical: a marker-less .md winning
# the newest race disarmed this very wall repo-wide for ~15 minutes on 2026-08-15
# (record/session-20260815-landing-supervision/t8-forensic-read.md).
#
# PLAN is kept because the refusals below quote it.
PLAN=$(active_run "$REPO") || exit 0
[ -n "$PLAN" ] && [ -f "$PLAN" ] || exit 0

# ---------- a wave is active: this IS a decision ----------

# Payload missing its session key: the §7 fail-direction table names this
# exact ambiguity and pins the start-side direction as open, silent — we
# cannot prove whose dispatch this is, so we cannot refuse it as foreign.
PAYLOAD_SID=$(session_id "$(_jq '.session_id')" 2>/dev/null) || PAYLOAD_SID=""
[ -n "$PAYLOAD_SID" ] || exit 0

# ...and the same direction for a session key that is not SHAPED like one. Every
# state path this gate reads or writes is built by interpolating this value —
# preflight-<sid>.state, roster-<sid>.state — and the symlink guards below check
# $STATE_DIR and those exact filenames, so a key carrying a path separator leaves
# the guarded directory entirely rather than tripping a guard (Step-6 review S-4).
# Session ids are harness-minted UUIDs, so this refuses nothing real; it is the
# belt every other payload value on these paths already wears via sanitize(),
# taken in the one direction §7 assigns an unreadable session key — pass, silent.
case "$PAYLOAD_SID" in *[!A-Za-z0-9_-]*) exit 0 ;; esac

deny() {  # <reason line>...
  echo "BLOCKED: this subagent start needs a working environment — a wave is active." >&2
  echo "" >&2
  local line
  for line in "$@"; do echo "$line" >&2; done
  echo "" >&2
  echo "Fix: ${PREFLIGHT_CMD}" >&2
  echo "Then retry the dispatch." >&2
  exit 2
}

STATE_FILE="$REPO/.bionic/tmp/preflight-${PAYLOAD_SID}.state"

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
  [ ! -L "$REPO/.bionic" ] && [ ! -L "$REPO/.bionic/tmp" ] \
    && [ ! -L "$STATE_FILE" ] && [ -f "$STATE_FILE" ] || return 1
  local sid
  sid=$(grep -m1 '^session_id=' "$STATE_FILE" 2>/dev/null | cut -d= -f2-)
  [ -n "$sid" ] && [ "$sid" = "$PAYLOAD_SID" ]
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
    deny "No environment attestation was found for this repo, and the probe that writes one" \
         "could not be located (looked beside this gate and under the Claude config directory)."
  fi

  # Run it AT THE PINNED ROOT and with THIS dispatch's session key, rather than
  # letting it inherit the shell. Both are the Synthesis field case read directly:
  # the attestation that had to be redone was taken against a root derived from the
  # working directory, and an attestation keyed to anything but the session whose
  # dispatch this is would be one this gate then refuses to read.
  PROBE_OUT=$(cd "$REPO" 2>/dev/null && CLAUDE_CODE_SESSION_ID="$PAYLOAD_SID" \
                bash "$PROBE_SCRIPT" 2>&1)
  PROBE_ST=$?

  if [ "$PROBE_ST" -ne 0 ] || ! attested; then
    # The probe's own words, not a paraphrase of them: it is the component that
    # knows WHICH check failed, and an operator handed "something went wrong" has
    # to run it again by hand to learn anything. Indented so the quotation is
    # visibly the probe speaking.
    {
      echo "BLOCKED: the environment check refused, so this dispatch would launch into a broken environment." >&2
      echo "" >&2
      echo "The check was run automatically for this session and did not pass:" >&2
      printf '%s\n' "$PROBE_OUT" | sed 's/^/    /' >&2
      echo "" >&2
      echo "A fleet inherits this environment and dies collectively if it is wrong." >&2
      echo "Fix the failure above, then retry the dispatch (or re-run by hand: ${PREFLIGHT_CMD})." >&2
    }
    exit 2
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

STATE_DIR="$REPO/.bionic/tmp"
PATROL_STAMP_FILE="$STATE_DIR/patrol-${PAYLOAD_SID}.state"

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

patrol_deny() {  # <state line>...
  echo "patrol checkpoint: this dispatch is refused — the Patrol is not alive for this session." >&2
  echo "" >&2
  local line
  for line in "$@"; do echo "$line" >&2; done
  echo "" >&2
  echo "A dispatch with no Patrol behind it is an agent nobody is waiting on." >&2
  echo "" >&2
  echo "Fix: re-arm the Patrol — both halves, the clock and the stamp:" >&2
  echo "  1. CronCreate a RECURRING session job at the interval \`bash ${POKER_SCRIPT} interval\`" >&2
  echo "     reports, carrying the patrol prompt (skills/canonical-sdlc/SKILL.md §Dispatch)." >&2
  echo "  2. bash ${POKER_SCRIPT} arm" >&2
  echo "" >&2
  echo "Then retry the dispatch." >&2
  exit 2
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
  PATROL_INTERVAL=$( cd "$REPO" 2>/dev/null && bash "$POKER_SCRIPT" interval 2>/dev/null )
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
if [ -L "$PATROL_STAMP_FILE" ] || [ ! -f "$PATROL_STAMP_FILE" ]; then
  patrol_deny \
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
if [ -z "$PATROL_INTERVAL" ] || [ "$PATROL_INTERVAL" -le 0 ]; then
  echo "dispatch-preflight: no Patrol interval could be obtained (${POKER_SCRIPT} is not readable on either lane); the staleness half of the arming wall did not run, though the never-armed half did." >&2
else
  # THE MULTIPLIER IS THE LIBRARY'S (spec AC-22). "Twice the interval" was a literal 2
  # written out at three sites; lib/patrol.sh exports PATROL_STALE_MULTIPLIER and its own
  # reader uses it, so a change to the judgment moves all of them at once.
  PATROL_MAX_AGE=$(( PATROL_INTERVAL * PATROL_STALE_MULTIPLIER ))
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
      if [ "$PATROL_AGE" -gt "$PATROL_MAX_AGE" ]; then
        patrol_deny \
          "The Patrol was armed on this session and has stopped firing." \
          "Its last stamp is ${PATROL_AGE}s old — past the ${PATROL_MAX_AGE}s limit," \
          "which is 2x ${PATROL_INTERVAL_WORDS}:" \
          "    ${PATROL_STAMP_FILE}"
      fi
      ;;
  esac
fi

# ================================================================== THE ROSTER
# (design D-5 + spec §Design "Roster"; slice 4/3 — the LAUNCH half of AC-1.)
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
# fails. Slice 4/4 completes the row from the tool response (full agent id,
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

ROSTER_VERSION="v1"
ROSTER_PREFIX="roster-"
ROSTER_SUFFIX=".state"
# STATE_DIR is set above, at the arming wall — the first thing on this path to need it.
ROSTER_FILE="$STATE_DIR/${ROSTER_PREFIX}${PAYLOAD_SID}${ROSTER_SUFFIX}"

warn() { printf 'dispatch-preflight: WARN %s\n' "$1" >&2; }

# Values are pipe-delimited on one line, so a field carrying a newline or a `|`
# would forge a row. Never a refusal — the ledger normalizes and records.
sanitize() {  # <value> <max-chars>
  printf '%s' "$1" \
    | tr '\n\r\t|' '    ' \
    | sed -e 's/[[:cntrl:]]/ /g' -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//' \
    | cut -c "1-$2"
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
# their consumers (slices 4/5, 4/6) stat them; a slash-bearing token with no
# letter is a fraction ("slice 4/3"), not a path.
#
# THE LIVENESS FIELDS (`cadence`, `claims`) join the same table, because slice
# 4/7 shipped them into the same §Dispatch prose the labels above anchor on:
# "The progress-artifact path carries a `cadence` alongside it" and "A subprocess
# claim — a process pattern plus its output file — is conditional-required". They
# were prose-only for one slice — hooks/stop-check.sh read `claims=` off a row no
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

lift_contract_fields() {  # <brief text> -> `kind=value` lines, absent kinds omitted
  printf '%s' "$1" | awk -v LEAD="$LEAD_CHARS" -v TRAIL="$TRAIL_CHARS" -v QUOTES="$QUOTE_CHARS" '
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
    function pathshaped(t) {
      if (length(t) < 3)        return 0
      if (index(t, "/") == 0)   return 0
      if (t !~ /[A-Za-z]/)      return 0
      if (substr(t, 1, 1) == "-") return 0
      return 1
    }
    function ispath(t) { return (pathshaped(t) && !istemplate(t)) }
    function collapse(s) { gsub(/[ \t\r\n]+/, " ", s); sub(/^ +/, "", s); sub(/ +$/, "", s); return s }
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
    function span_paths(h) { return paths(spanof(h), DELIV_MAX) }
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
    function decl_deliverable(   j, best, t, visited) {
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
        if (t != "") return t
      }
      return ""
    }
    # A waiver REASON that is the angle-bracketed slot out of the wall message,
    # copied rather than filled in. A real reason never opens with one.
    function isplaceholder(v) { return (v ~ /^<[^<>]*>/) }
    function paths(s, maxn,   n, arr, i, t, out, seen, c) {
      n = split(s, arr, /[ \t\r\n]+/); out = ""; c = 0
      for (i = 1; i <= n; i++) {
        t = trimtok(arr[i])
        if (!ispath(t) || seen[t]) continue
        seen[t] = 1
        out = (out == "" ? t : out "," t)
        if (++c >= maxn) break
      }
      return out
    }
    BEGIN {
      NL = 0
      # How many candidate paths a deliverable span reports before it stops counting.
      # One is the contract; anything above one is refused, and the number only has to
      # be large enough for the refusal to show the author what it saw.
      DELIV_MAX = 12
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
      # .bionic/docs/record/my-slice-notes.md — and a brief that quotes that
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
      addlabel("your slice",         "-")
      addlabel("read first",         "input")
      addlabel("artifacts",          "deliverable", "", 1)
      addlabel("artifact",           "deliverable", "", 1)
      addlabel("progress",           "progress")
      addlabel("duration",           "duration")
      addlabel("cadence",            "cadence", "([ \t]*:|[ \t])[ \t]*")
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
      if (h > 0) { v = paths(spanof(h), 1); if (v != "") print "progress=" v }
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
    }
  ' 2>/dev/null
}

# ---------- D-5 pruning ----------
#
# The same liveness rule slice 4/2 established for the attestation
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
    [ "$sid" = "$PAYLOAD_SID" ] && continue
    roster_session_live "$sid" || rm -f "$f" 2>/dev/null
  done
}

# ---------- the row ----------

AGENT_NAME=$(sanitize "$(_jq '.tool_input.name')" 200)
SUBAGENT_TYPE=$(sanitize "$(_jq '.tool_input.subagent_type')" 200)
AGENT_MODEL=$(sanitize "$(_jq '.tool_input.model')" 200)
TOOL_USE_ID=$(sanitize "$(_jq '.tool_use_id')" 200)
LIFTED=$(lift_contract_fields "$(_jq '.tool_input.prompt')")

field_of() {  # <kind>
  printf '%s\n' "$LIFTED" | grep -m1 "^$1=" | cut -d= -f2-
}
C_DELIVERABLE=$(sanitize "$(field_of deliverable)" 300)
# Never both: the extractor prints ONE of these two, so a non-empty list here means
# `deliverable=` is empty and the ambiguity wall below owns the dispatch.
C_DELIVERABLE_CANDIDATES=$(sanitize "$(field_of deliverable_ambiguous)" 900)
C_DURATION=$(sanitize "$(field_of duration)" 80)
C_PROGRESS=$(sanitize "$(field_of progress)" 300)
C_CADENCE=$(sanitize "$(field_of cadence)" 80)
C_CLAIMS=$(sanitize "$(field_of claims)" 300)
C_WAIVER=$(sanitize "$(field_of waiver)" 300)
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
  echo "BLOCKED: this dispatch brief names more than one path under its deliverable label — a wave is active." >&2
  echo "" >&2
  echo "The label's span offers these candidates:" >&2
  printf '%s\n' "$C_DELIVERABLE_CANDIDATES" | tr ',' '\n' | while IFS= read -r _cand; do
    [ -n "$_cand" ] || continue
    echo "    ${_cand}" >&2
  done
  echo "" >&2
  echo "A deliverable is the ONE durable artifact this agent is contracted to produce, and" >&2
  echo "the wall never picks among candidates — whichever it chose would be recorded as a" >&2
  echo "declared fact, and the landing check would order this agent to write it." >&2
  echo "" >&2
  echo "Fix: name exactly one deliverable path in the label —" >&2
  echo "    Expected artifact: .bionic/docs/record/my-slice-notes.md" >&2
  echo "  References and inputs the agent should READ go outside the label's span: on their" >&2
  echo "  own line, under Read first: or Scope constraint:, or after a blank line." >&2
  echo "" >&2
  echo "Then retry the dispatch." >&2
  exit 2
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
    *)  abs="$REPO/$p" ;;
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
    "$REPO"/*) : ;;
    *)
      echo "BLOCKED: this dispatch names a deliverable outside the repository — a wave is active." >&2
      echo "" >&2
      echo "    ${C_DELIVERABLE}" >&2
      echo "  resolves to ${D_ABS}, which is not under ${REPO}." >&2
      echo "" >&2
      echo "The landing check stats — and, for a directory, walks — whatever this names," >&2
      echo "on every stop of the agent that owns it. It must be a path inside this repo." >&2
      echo "" >&2
      # A CONCRETE NAME, never a <slot> (Step-6 R6 critic R6-2). This message hands the
      # author a line to copy, and briefs in this repo quote wall text verbatim — so the
      # example must be a brief that every wall here ACCEPTS. The slot form it used to
      # recommend is refused by the sibling wall below (a template is not a path), and
      # tests/cross-gate-agreement.test.sh §N.4 pins that refusal: this file was
      # recommending, in one message, the exact string another of its messages rejects.
      # tests/dispatch-preflight.test.sh S18 drives each refusal's own Fix: line back
      # through the gate so the two can never drift apart again.
      echo "Fix: name a repo-relative artifact path in the brief —" >&2
      echo "    Expected artifact: .bionic/docs/record/my-slice-notes.md" >&2
      echo "" >&2
      echo "Then retry the dispatch." >&2
      exit 2
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
  echo "BLOCKED: this dispatch brief names no deliverable — a wave is active." >&2
  echo "" >&2
  echo "An agent with nothing durable to produce cannot be checked on: there is no" >&2
  echo "path to stat when it reports done, and nothing left behind if it dies quietly." >&2
  echo "" >&2
  echo "Fix: declare a durable artifact path with a canonical label —" >&2
  echo "    Expected artifact: .bionic/docs/record/my-slice-notes.md" >&2
  echo "  Any of these labels lifts one: Expected artifact(s), Deliverable(s), Artifact(s)." >&2
  echo "  Name a concrete path — the wall never guesses one from prose, and a <slot> is not a name." >&2
  echo "" >&2
  echo "Or waive it — the reason is recorded on the session roster either way:" >&2
  echo "    Deliverable-waiver: <why this dispatch produces nothing durable>" >&2
  echo "" >&2
  echo "Then retry the dispatch." >&2
  exit 2
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
# So the channel, not the payload, decides: the guard sets this variable and
# nothing else does, which keeps the reading local to the one caller that knows
# which channel it is. Silent, and on the pass side — a dispatch that got this far
# has been allowed, and this line only declines to write it down.
if [ "${BIONIC_HOOK_CHANNEL:-}" = "agent-context" ]; then
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

ROW="roster-state/${ROSTER_VERSION}|status=intended|session=${PAYLOAD_SID}|name=${AGENT_NAME}|agent_id=|launched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)|subagent_type=${SUBAGENT_TYPE}|model=${AGENT_MODEL}|deliverable=${C_DELIVERABLE}|source=${C_SOURCE}|duration=${C_DURATION}|progress=${C_PROGRESS}|claims=${C_CLAIMS}|cadence=${C_CADENCE}|absent=${ABSENT}|waiver=${C_WAIVER}|tool_use_id=${TOOL_USE_ID}"

WROTE=1
if [ ! -e "$ROSTER_FILE" ]; then
  # A concurrent dispatch in the same session can lose this race and write the
  # header twice; both are comment lines and every reader skips them. The ROWS
  # are what must not interleave, and each is a single short append.
  printf '# bionic session roster — schema roster-state/%s — machine-local, safe to delete\n' \
    "$ROSTER_VERSION" >> "$ROSTER_FILE" 2>/dev/null && chmod 600 "$ROSTER_FILE" 2>/dev/null
fi
printf '%s\n' "$ROW" >> "$ROSTER_FILE" 2>/dev/null || WROTE=0

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
