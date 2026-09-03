#!/bin/bash
# SESSION POKER — the tick that decides whether a dispatched session needs a nudge.
# Design: .bionic/docs/specs/epic-16-landing-contract/wave-02-fact-based-supervision.spec.md
#         §Design ("Poker"), succeeding epic-09/epic-10's resident cron poker — deliberately
#         NOT resurrected (spec §Rejected alternatives: "OS cron / launchd for the tick" is
#         residency in configuration form, ratified against).
# [WALL: tests/session-poker.test.sh]
#
# This is NOT a hook, exactly like hooks/session-sweeper.sh: it lives in hooks/ for
# test-harness pairing and to ride the payload's hooks/ directory into the mounted plugin.
# It is registered on NO channel — neither hooks/hooks.json nor a skill's frontmatter.
# It is invoked ON DEMAND, one question per invocation, and holds no process open:
#
#     bash <plugin-root>/hooks/session-poker.sh tick       one decision over this roster (read-only)
#     bash <plugin-root>/hooks/session-poker.sh arm        stamp the Patrol as alive, at engagement
#     bash <plugin-root>/hooks/session-poker.sh disarm     remove that stamp — this Patrol was ended on purpose
#     bash <plugin-root>/hooks/session-poker.sh interval   the configured Patrol interval, seconds
#     bash <plugin-root>/hooks/session-poker.sh adopt      what OTHER sessions launched here (read-only)
#
# `<plugin-root>` IS A PLACEHOLDER, NOT A SPELLING TO PASTE (epic-17 W5, spec AC-5). These
# are commands a MODEL types into its own shell, where `${CLAUDE_PLUGIN_ROOT}` is unset —
# the CLI substitutes that variable inside registered command files and nowhere else. The
# root is resolved ONCE PER SESSION, at Patrol arming, out of the CLI's own registry
# (`installed_plugins.json`, via `detect_plugin_root` in scripts/lib/detect.sh) and the
# resolved absolute path is baked into the session's own text from there on. The old
# `${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}` fallback is retired: it silently resolved to a
# bootstrap-era `~/.claude` copy that could be an older build than the installed plugin.
#
# WHAT IT IS. The poker is the decision brain of THE PATROL, not a resident process
# (spec R1). The doctrine that ARMS it lives in skills/canonical-sdlc/SKILL.md
# §Dispatch, and the mechanism is a session-scoped cron job: One clock per run, and only one.
# Arm it at engagement — never on dispatch, never one per unit — and then
# `CronDelete` the job at run close WITH `disarm` beside it, which removes the stamp: the
# cron half stops the firing and the stamp half is what says the stop was deliberate, and a
# `CronDelete` alone leaves a Patrol that every reader — hooks/patrol-revive.sh loudest —
# has to read as a death (critic C-2, epic-19 w1).
# Wakeups are recurring, never date-pinned: a one-shot
# `CronCreate` pinned to a wall-clock minute is banned, because
# a busy minute DROPS the tick rather than queuing it — so a one-shot whose single match
# minute finds the session working dies silently and never fires again. A run that needs a
# wake creates a SHORT RECURRING job and `CronDelete`s it on its first fire.
# Each Patrol tick delivers the patrol prompt, whose FIRST duty is `tick` and whose LAST is
# to continue the run's actual work rather than report on it; THIS SCRIPT DECIDES, the cron
# schedules. (Epic-17 W4 superseded the earlier mechanism, a harness self-wake primitive
# that slept `interval` seconds between calls; `interval` survives it as the cron's period.)
# `tick` is exactly ONE `verdict` read over the whole roster, plus — for any UNMET row only —
# a direct roster lookup of that one row's own `duration=`/`launched_at=` fields (verdict's
# own output carries neither). Never a per-row verdict call, never a second judgment of
# MET/UNMET/STILL-LIVE: that judgment belongs to `verdict` alone (ownership table,
# spec §Design) and this script only consumes it.
#
# WHAT IT NEVER DOES. It never stops, kills, or notifies on its own authority. The
# decision is printed on stdout as ONE machine-readable line, and the caller (the patrol
# prompt the Patrol delivers) is what turns a NOTIFY line into an actual push. Zero
# authority, exactly like `verdict` (ADR-003).
#
# THE ONE THING IT DOES RECORD IS THAT IT RAN. Every invocation of `tick` and every `arm`
# writes a session-keyed Patrol stamp beside the roster — `.bionic/tmp/patrol-<sid>.state`,
# schema `patrol-stamp/v1` — and hooks/dispatch-preflight.sh refuses a dispatch when that
# stamp is absent (the Patrol was never armed) or older than 2x the poker-interval (it was
# armed and has stopped firing). Two properties make that wall honest, and both are pinned
# by tests/session-poker.test.sh §6:
#
#   THE STAMP IS WRITTEN BEFORE ANYTHING IS DECIDED — before the sibling sweeper is even
#   located, before the roster is read, before any exit path branches. What it attests is
#   FIRINGS LANDING, not decisions succeeding. A stamp written on success would measure the
#   wrong thing: this wave's own orchestrator session produced 10+ healthy-but-REFUSED
#   pre-roster ticks across one long interview, and stamp-on-success would have aged the
#   stamp into a false refusal of the wave's first dispatch. The single exception is a tick
#   with no session key at all, which has no stamp path to write.
#
#   `arm` EXISTS BECAUSE ARMING PRECEDES DISPATCH. The doctrine arms at engagement, never on
#   dispatch, so the first stamp cannot come from a tick that has a roster to read; without
#   this verb the wall is a chicken-and-egg that refuses every first dispatch of a run.
#   `arm` therefore needs no roster and asks for none.
#
#   `disarm` EXISTS BECAUSE A DELIBERATE STOP HAS TO BE READABLE. It removes the stamp, and
#   nothing else in production ever did — so an aging stamp meant "the Patrol died" and
#   "the run ended its own Patrol" indistinguishably, and hooks/patrol-revive.sh reported
#   the second as the first on EVERY remaining turn of the session (critic C-2, epic-19 w1).
#   Its two callers are the two deliberate stops there are: the run-close ritual in
#   skills/canonical-sdlc/SKILL.md §Dispatch, beside the `CronDelete`, and the DISARM
#   decision below, which takes it as the last act of its own tick.
#
# The stamp is a LIVENESS signal, not an authority: it says the Patrol fired, and it cannot
# say the CLI's cron table still holds the job. That honest limit is the wall's too.
#
# AN ACKED ROW IS CLOSED HERE, exactly as it is for the other three consumers of the
# verdict line (hooks/landing-gate.sh, hooks/stop-orders.sh, hooks/stop-guard.sh): it is
# neither open nor notifiable. `acked=` is read PER ROW off the verdict line below, never
# from the ledger — the verb that owns the ledger is the verb that prints the answer.
#
# DECISIONS, in precedence order:
#   DISARM   the roster carries no OPEN row — an empty roster (spec's "disarmed on empty
#            roster" invariant, literally) generalizes here to the roster having nothing
#            open at all: every row MET, WAIVED or ACKED is the same "nothing left to wait
#            for" as no rows existing, so all read DISARM (S2 design decision plus epic-16
#            w2 Step-6 remediation R4, both logged to the plan). A DISARM tick REMOVES this
#            session's stamp as its last act — the decision is terminal, so the disk record
#            that a Patrol runs here has to stop saying so.
#   NOTIFY   at least one UNACKED UNMET row's elapsed time (now − launched_at) exceeds its own
#            declared `duration=`, read by the same parser `verdict` uses for `cadence=`
#            (hooks/session-sweeper.sh's parse_seconds, duplicated below — see that file's
#            fix, same commit lineage, epic-16 w2 S2). A row whose duration is unreadable or
#            whose launch time is unreadable is skipped, never guessed at — the same
#            "refuse rather than invent" rule verdict itself follows.
#   QUIET    open rows exist (UNMET-not-past-duration, STILL-LIVE, or AMBIGUOUS) but none
#            qualify for NOTIFY — the tick ran, found nothing to say, and that is reported.
#
# Exit codes mirror hooks/session-sweeper.sh's verdict verb, because a caller already knows
# how to branch on this shape:
#   0 — DISARM or QUIET
#   1 — NOTIFY (something needs surfacing)
#   2 — usage error, or a refusal (propagated from the sweeper read, or raised here)
#   3 — no session key
#
# Session key: CLAUDE_CODE_SESSION_ID, exactly as hooks/session-sweeper.sh takes it.
#
# THE SWEEPER IS THIS SCRIPT'S SIBLING, resolved exactly as hooks/landing-gate.sh resolves
# it: no PATH lookup (a hook's PATH is not ours to trust), no environment override (a seam on
# the path under test would leave the production path unverified) — so the same resolution
# holds in the repo and under the mounted plugin's hooks/, which ships both side by side.
# Registered on no channel — invoked on demand from the mounted plugin payload.

set -u

# THIS SCRIPT'S OWN PATH, so the usage it prints names the copy the operator actually
# invoked — identical in a repo checkout, in a bootstrap-installed ~/.claude/hooks/, and in
# an installed plugin payload. Deliberately NOT ${CLAUDE_PLUGIN_ROOT}: this script is run by
# hand and by the harness outside any plugin context, where that variable does not exist.
HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -n "$HOOK_DIR" ] || HOOK_DIR="$(dirname "$0")"

# ---------------------------------------------------------------- the library
#
# THE SPINE (bionic 1.4.0, spec AC-16, design §2). Four facts this script used to derive
# from its own copies or its own literals — which project this cwd belongs to, which session
# is asking, whether the run is still open, and how far past a declared interval counts as
# stale — have one owner each in payload/scripts/lib, and the block
# below is the ONE idiom that finds them. It is pasted byte-identically out of
# `bionic_loader_pin` (payload/scripts/lib/loader.sh) into every hook on the spine, because
# a library cannot load itself; tests/cross-gate-agreement.test.sh re-derives each copy from
# that function, so a drifted paste goes red rather than quiet.
#
# FAIL OPEN, deliberately. The poker is not a wall: it prints one decision line and holds no
# authority (ADR-003), so the cost of a missing library is a tick that cannot answer, not an
# irreversible action taken blind. It says so in one line and steps aside.
BIONIC_LIB_WANT="root.sh session.sh run.sh patrol.sh resources.sh"
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
[ -n "$BIONIC_LIB" ] || loader_fail_open "session-poker"
. "$BIONIC_LIB/root.sh"
. "$BIONIC_LIB/session.sh"
. "$BIONIC_LIB/run.sh"
. "$BIONIC_LIB/patrol.sh"
. "$BIONIC_LIB/resources.sh"

POKER_DECISION_SCHEMA="poker-tick/v1"
POKER_INTERVAL_DEFAULT="30m"

# The Patrol stamp — schema, and the two halves of its per-session filename. Read back by
# hooks/dispatch-preflight.sh's arming wall; the two spellings are held together by
# tests/cross-gate-agreement.test.sh §P, so a rename on one side cannot go quiet on the other.
PATROL_STAMP_SCHEMA="patrol-stamp/v1"
PATROL_STAMP_PREFIX="patrol-"
PATROL_STAMP_SUFFIX=".state"

# THE ARMING RECORD — a sibling of the stamp, whose MTIME is the instant this session armed.
# It is a second file rather than a field inside the stamp because the stamp is rewritten
# whole by every tick: a field would have to be read back and re-emitted on each of them, and
# one silent read-back failure would erase the session's arming instant for good. The marker
# is written once, by `arm`, and removed with the stamp — nothing else touches it, so it
# cannot drift. Its mtime carries full filesystem resolution, which is what lets the
# comparison below be `-nt` (the selection block's own primitive) rather than a
# whole-second arithmetic that ties.
#
# NO OTHER READER SEES IT: every consumer of the stamp addresses the exact
# `patrol-<sid>.state` path (hooks/dispatch-preflight.sh, hooks/patrol-revive.sh,
# scripts/lib/patrol.sh) — none of them globs — so a `patrol-<sid>.state.armed` beside it
# changes nothing they read, and the stamp's own shape, which the arming wall ages, is
# untouched.
PATROL_ARMED_SCHEMA="patrol-armed/v1"
PATROL_ARMED_SUFFIX=".armed"

# THE HOLD COUNTER — the third sibling of the stamp, and the ONLY state the scheduler keeps
# across ticks. NARROW fires on a hold that SURVIVES a tick (AC-30), which is a fact about
# two firings and therefore cannot be read off either one of them alone.
#
# IT IS NOT IN THE PLAN, and that is a boundary rather than a convenience. The plan header's
# `parallel-budget:` is written by Step 0 and by the orchestrator; a tick that edited it
# would make the ceiling a function of live readings, which is the exact drift
# lib/resources.sh was written to remove ("THE BUDGET IS A CEILING, NOT A CONTROLLER"). The
# tick reads pressure to THROTTLE, never to re-derive the budget — so what it carries is a
# count of consecutive holds in its own session-scoped file, and the NARROW it prints is a
# RECOMMENDATION the orchestrator acts on by writing the plan.
#
# Session-scoped like the stamp it sits beside: a hold counted in one session says nothing
# about another, and it dies with the stamp at DISARM.
PATROL_HOLDS_SUFFIX=".holds"

# `adopt`'s own schema, and the two numbers its report tail is cut with. The floor is what
# separates a REPORT from the one-line sign-offs that usually follow it in an agent's
# transcript ("done", "no task tools here"); the cap is what keeps a 40 KB report out of a
# terminal the operator has to read. Both are display constants: no decision is taken from
# either, so a bad guess costs legibility and never a wrong verdict.
ADOPT_SCHEMA="poker-adopt/v1"
ADOPT_TAIL_MIN=400
ADOPT_TAIL_CAP=2000

say()  { printf 'poker: %s\n' "$1"; }
die()  { printf 'poker: %s\n' "$1" >&2; }

usage() {  # [message]
  [ $# -gt 0 ] && die "$1"
  die "Usage:"
  die "  bash ${HOOK_DIR}/session-poker.sh tick       one decision over this session's roster (read-only)"
  die "  bash ${HOOK_DIR}/session-poker.sh arm        stamp the Patrol as alive for this session (no roster needed)"
  die "  bash ${HOOK_DIR}/session-poker.sh disarm     remove that stamp at run close — this Patrol was ended on purpose"
  die "  bash ${HOOK_DIR}/session-poker.sh interval    the configured Patrol interval, in seconds"
  die "  bash ${HOOK_DIR}/session-poker.sh interval-default   this script's built-in default interval, in seconds (ignores config)"
  die "  bash ${HOOK_DIR}/session-poker.sh adopt      every open row a PREDECESSOR session left on this project's rosters"
  die "  bash ${HOOK_DIR}/session-poker.sh adopt --report-only   the same rows, with the adoption itself not taken (writes nothing)"
  exit 2
}

[ $# -ge 1 ] || usage "a verb is required."
VERB="$1"; shift

# `adopt` is the ONE verb that takes a flag, and `--report-only` is the ONE flag. Everything
# else keeps the old surface exactly — one word, nothing after it — so a stray argument is
# still the usage error it always was rather than something silently ignored.
ADOPT_REPORT_ONLY=no
case "$VERB" in
  adopt)
    if [ $# -eq 1 ]; then
      [ "$1" = "--report-only" ] || usage "unknown flag for adopt: $1"
      ADOPT_REPORT_ONLY=yes
    elif [ $# -gt 1 ]; then
      usage "adopt takes at most one flag."
    fi
    ;;
  tick|arm|disarm|interval|interval-default)
    [ $# -eq 0 ] || usage "$VERB takes no arguments."
    ;;
  *) usage "unknown verb: $VERB" ;;
esac

# ---------------------------------------------------------------- portable facts
#
# DELIBERATELY DUPLICATED from hooks/session-sweeper.sh, CODE-identical (not byte-identical —
# each file's comments explain its own copy in its own terms, exactly as
# tests/cross-gate-agreement.test.sh's §I.1 already treats signature comments for its own
# duplicated family), for the reason that file's own header gives (§9 there): a sourced
# library the installer misses is a silently inert consumer, and every duplicate here answers
# the SAME question its sibling answers so the two cannot quietly drift into different
# readings of one fact. `parse_seconds` is duplicated post-fix (epic-16 w2 S2, same commit
# that fixed the original); `file_mtime` joined them for `adopt`, which reads a predecessor
# agent's progress file the way the sweeper reads a live one. The six are held together by
# tests/cross-gate-agreement.test.sh
# §O, which compares executable text with every pure-comment line stripped from both sides —
# epic-16 w2 Step-6 remediation R3, closing rd review D-1 (this claim used to name no test,
# and was already false for parse_seconds before that fix).

now_epoch() { date -u +%s; }
iso_now()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

iso_epoch() {  # <ISO-8601 Z> -> epoch seconds, empty if unreadable
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null \
    || date -u -d "$1" +%s 2>/dev/null
}

# One field out of a versioned pipe-delimited line, BY KEY, never by position — same
# rationale as hooks/session-sweeper.sh's copy: field order is not a contract.
line_field() {  # <line> <key>
  printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-
}

clean() {  # <value>
  printf '%s' "$1" | tr '\n\r\t|' '    ' | sed -e 's/[[:cntrl:]]/ /g' -e 's/  */ /g' \
    -e 's/^ *//' -e 's/ *$//' | cut -c 1-400
}

# The prose duration/cadence parser. Deliberate limits, each a refusal rather than a guess —
# see hooks/session-sweeper.sh's copy for the full rationale (its own comments there are
# specific to ITS callers, e.g. `cadence=`, which this script never reads — that is why this
# copy's comments are shorter, not why the code differs). This is that function's POST-FIX
# body, CODE-identical (§O compares it with comments on both sides stripped).
parse_seconds() {  # <prose> -> seconds on stdout; nonzero exit if it cannot be read
  local raw="$1" s pairs count nums hi unit mult n allnums
  [ -n "$raw" ] || return 1
  s="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  s="${s//\~/ }"; s="${s//–/-}"; s="${s//—/-}"; s="${s//,/ }"
  pairs="$(printf '%s' "$s" \
    | grep -oE '[0-9]+([[:space:]]*-[[:space:]]*[0-9]+)?[[:space:]]*(hours?|hrs?|minutes?|mins?|seconds?|secs?|h|m|s)([^a-z0-9]|$)')"
  count="$(printf '%s\n' "$pairs" | grep -c '[0-9]')"
  [ "$count" -eq 1 ] || return 1
  nums="$(printf '%s' "$pairs" | grep -oE '[0-9]+')"
  hi=0
  for n in $nums; do [ "$n" -gt "$hi" ] && hi="$n"; done
  [ "$hi" -gt 0 ] || return 1
  unit="$(printf '%s' "$pairs" | grep -oE '[a-z]+' | tail -1)"
  case "$unit" in
    h|hr|hrs|hour|hours)         mult=3600 ;;
    m|min|mins|minute|minutes)   mult=60 ;;
    s|sec|secs|second|seconds)   mult=1 ;;
    *) return 1 ;;
  esac
  printf '%s' "$s" | grep -qE '[0-9]+\.[0-9]+' && return 1
  allnums="$(printf '%s' "$s" | grep -oE '[0-9]+')"
  [ "$(printf '%s\n' "$allnums" | grep -c '[0-9]')" -eq "$(printf '%s\n' "$nums" | grep -c '[0-9]')" ] \
    || return 1
  printf '%s' "$((hi * mult))"
}

# ---------------------------------------------------------------- the pinned root
#
# THE COPY IS GONE (bionic 1.4.0, spec AC-10). This script used to carry one of eight
# byte-identical resolvers that asked git FIRST and walked for a `.bionic` ancestor only
# when no repository existed at all — so a git repo nested inside the workspace that holds
# the `.bionic` tree resolved to ITSELF, and the roster the tick polled was not the roster
# the wall wrote. `project_root` in payload/scripts/lib/root.sh inverts that order and maps
# a linked worktree onto its main repository, which is the property epic-16 w2's remediation
# R3 added the copy for in the first place (a worktree cwd must not read an empty roster and
# then DISARM, terminally). Every call site below passes "$PWD" and takes the library's
# answer; nothing here re-derives it.

# ---------------------------------------------------------------- the interval knob
#
# `poker-interval:` in <project>/.bionic/config.yaml — the exact convention
# hooks/context-spend.sh (`docs-root:`) and hooks/canonical-sdlc-governing-skill.sh
# (`docs-root:`, `rigor-floor:`) already use: a project-scoped key, grep'd and sed-stripped,
# never a YAML parser. ASSUMPTION (logged to the plan, S2): this is the first CONSUMER of
# that convention outside canonical-sdlc's own hooks; no config.yaml ships by default, so an
# absent file or an absent key both read as the documented default, 30m — a knob nobody has
# touched behaves as if it were never added. A malformed override REFUSES rather than
# silently falling back to the default, matching this repo's "refuse, never guess" posture
# everywhere else a prose value is read (parse_seconds itself, the two hooks above).
poker_interval_seconds() {
  local repo cfg raw ov
  repo="$(project_root "$PWD")"
  cfg="$repo/.bionic/config.yaml"
  raw="$POKER_INTERVAL_DEFAULT"
  if [ -f "$cfg" ] && [ ! -L "$cfg" ]; then
    ov="$(grep -E '^[[:space:]]*poker-interval[[:space:]]*:' "$cfg" 2>/dev/null | head -1 \
      | sed -E 's/^[[:space:]]*poker-interval[[:space:]]*:[[:space:]]*//' \
      | tr -d '\r' | sed -e 's/[[:space:]]*$//')"
    [ -n "$ov" ] && raw="$ov"
  fi
  parse_seconds "$raw"
}

# ---------------------------------------------------------------- the Patrol stamp
#
# One session-keyed file beside the roster, at the SAME pinned root the roster uses — a
# stamp written under a worktree root while the wall reads the main repository's would
# refuse a perfectly live Patrol, silently and for the rest of the run (the exact shape of
# the worktree bug ap review A-1 fixed for the roster read, epic-16 w2).
#
# Never fatal to a tick. A tick that could not stamp has still decided, and turning a
# stamp-write failure into a refused tick would hand the arming wall a second way to say
# "dead" about a Patrol that is firing fine. `arm` is the exception and checks the return:
# arming is an explicit act whose whole product is the stamp, so a silent no-op there would
# leave the operator believing a wall is satisfied when it is not.
#
# Symlinks are refused rather than followed, the same posture every other .bionic/tmp
# writer takes: a hostile repo may make this fail, and must not gain a write through a path
# it aims.
patrol_stamp_file() {  # <session-id> -> absolute path, or empty
  local repo real
  repo="$(project_root "$PWD")"
  real="$(cd "$repo" 2>/dev/null && pwd -P)"
  [ -n "$real" ] || return 1
  printf '%s/.bionic/tmp/%s%s%s' "$real" "$PATROL_STAMP_PREFIX" "$1" "$PATROL_STAMP_SUFFIX"
}

# THE .bionic/tmp WRITE GUARD, one copy for both of this script's writers — the Patrol
# stamp below and the adopted row further down. It was written inline in the stamp writer
# and is a function now because a second writer arrived (epic-20 W1 B-1): a guard this
# specific, copied by hand into a second call site, is a guard that drifts.
tmp_dir_ok() {  # <.bionic/tmp path> -> 0 safe to write in, 1 refuse
  local d="$1" _repo _target _common _root
  case "$d" in */.bionic/tmp) : ;; *) return 1 ;; esac
  if [ -L "${d%/tmp}" ]; then
    # The spawned-worktree link (.bionic -> main checkout's) is trusted only when its
    # target resolves inside this same repo — mirrors stop-guard's _bionic_symlink_in_repo.
    _repo="${d%/.bionic/tmp}"
    _target="$(cd "${d%/tmp}" 2>/dev/null && pwd -P)" || return 1
    _common="$(git -C "$_repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
    _root="$(cd "${_common%/.git}" 2>/dev/null && pwd -P)" || return 1
    case "$_target/" in "$_root"/*) : ;; *) return 1 ;; esac
  fi
  [ -L "$d" ] && return 1
  return 0
}

# The arming record's path — the stamp's, plus one suffix, so the two can never resolve to
# different directories and a mis-resolved root loses both together rather than half.
patrol_armed_file() {  # <session-id> -> absolute path, or empty
  local f
  f="$(patrol_stamp_file "$1")" || return 1
  [ -n "$f" ] || return 1
  printf '%s%s' "$f" "$PATROL_ARMED_SUFFIX"
}

# The hold counter's path — the stamp's, plus one suffix, same construction and the same
# reason as the arming record above.
patrol_holds_file() {  # <session-id> -> absolute path, or empty
  local f
  f="$(patrol_stamp_file "$1")" || return 1
  [ -n "$f" ] || return 1
  printf '%s%s' "$f" "$PATROL_HOLDS_SUFFIX"
}

# read_holds / write_holds — the consecutive-hold count, as a bare integer.
#
# UNREADABLE READS ZERO, and that is the safe direction here: NARROW is an ADVISORY line,
# so a lost count costs one tick's recommendation, where a fabricated count would tell an
# orchestrator to halve a width the machine never asked it to halve.
read_holds() {  # <session-id> -> integer on stdout (0 when absent or unreadable)
  local f v
  f="$(patrol_holds_file "$1")" || { printf '0'; return 0; }
  [ -n "$f" ] && [ -f "$f" ] && [ ! -L "$f" ] || { printf '0'; return 0; }
  v="$(head -1 "$f" 2>/dev/null | tr -dc '0-9')"
  case "${v:-}" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$v" ;; esac
}

write_holds() {  # <session-id> <count> -> 0 written, 1 not. Never fatal to a tick.
  local sid="$1" n="$2" f d
  f="$(patrol_holds_file "$sid")" || return 1
  [ -n "$f" ] || return 1
  d="${f%/*}"
  tmp_dir_ok "$d" || return 1
  mkdir -p "$d" 2>/dev/null || return 1
  [ -L "$f" ] && return 1
  printf '%s\n' "$n" > "$f" 2>/dev/null || return 1
  chmod 600 "$f" 2>/dev/null
  return 0
}

# WRITTEN BY `arm` AND BY NOTHING ELSE. Its content is for a human reading .bionic/tmp; the
# fact the tick reads is its mtime. A failure here is NOT fatal to arming: the stamp is what
# the arming wall reads, and a session armed without a marker simply never auto-DISARMs —
# which is the safe direction (ADR-002 §3), where refusing to arm would take the dispatch
# wall down over a bookkeeping file.
write_patrol_armed_marker() {  # <session-id> -> 0 written, 1 not
  local sid="$1" f d
  f="$(patrol_armed_file "$sid")" || return 1
  [ -n "$f" ] || return 1
  d="${f%/*}"
  tmp_dir_ok "$d" || return 1
  mkdir -p "$d" 2>/dev/null || return 1
  [ -L "$f" ] && return 1
  printf '%s|at=%s|session=%s\n' "$PATROL_ARMED_SCHEMA" "$(iso_now)" "$sid" \
    > "$f" 2>/dev/null || return 1
  chmod 600 "$f" 2>/dev/null
  return 0
}

write_patrol_stamp() {  # <session-id> <verb> -> 0 written, 1 not
  local sid="$1" verb="$2" f d
  f="$(patrol_stamp_file "$sid")" || return 1
  [ -n "$f" ] || return 1
  d="${f%/*}"
  tmp_dir_ok "$d" || return 1
  mkdir -p "$d" 2>/dev/null || return 1
  [ -L "$f" ] && return 1
  printf '%s|at=%s|session=%s|verb=%s\n' "$PATROL_STAMP_SCHEMA" "$(iso_now)" "$sid" "$verb" \
    > "$f" 2>/dev/null || return 1
  chmod 600 "$f" 2>/dev/null
  return 0
}

# THE OTHER END OF THE SAME RECORD, and the only writer in production that ever removes a
# stamp. Until it existed, an aging stamp had exactly one reading available to every
# consumer — "the Patrol died" — and the two deliberate stops this system takes routinely
# (the run-close `CronDelete`, and the DISARM decision below) produced that reading on a
# run that had simply finished. hooks/patrol-revive.sh then blocked the stop of EVERY
# remaining turn of the session, since one block per turn is not a block that stops
# repeating. Removing the stamp is the readable fact that closes it: the revive hook's
# ABSENT state is silent by design, so a stamp that is gone ends the notice rather than
# restarting it, and the arming wall's never-armed refusal is exactly the right thing to
# say to the next dispatch on a run whose clock was deliberately stopped.
#
# A SYMLINK IS NOT A STAMP, here as everywhere else under .bionic/tmp. It is left alone
# rather than unlinked: every reader in the fleet already treats it as absent, so there is
# nothing to close, and a script that deletes files it never wrote is a worse trade than a
# no-op. The directory shape is checked exactly as the writer checks it, so a resolution
# that landed somewhere else removes nothing.
remove_patrol_stamp() {  # <session-id> -> 0 gone (removed, or never there), 1 could not
  local sid="$1" f d a
  f="$(patrol_stamp_file "$sid")" || return 1
  [ -n "$f" ] || return 1
  d="${f%/*}"
  case "$d" in */.bionic/tmp) : ;; *) return 1 ;; esac
  # THE ARMING RECORD GOES WITH THE STAMP, best-effort. Both halves say "this session's
  # Patrol is live", so leaving one behind leaves the disk saying half of a thing that
  # ended. It is best-effort because no reader consults the marker without a stamp beside
  # it, so a survivor claims nothing — where a surviving STAMP claims a live clock, which
  # is why that one decides the return code.
  a="$(patrol_armed_file "$sid")" || a=""
  if [ -n "$a" ] && [ ! -L "$a" ] && [ -e "$a" ]; then rm -f "$a" 2>/dev/null; fi
  a="$(patrol_holds_file "$sid")" || a=""
  if [ -n "$a" ] && [ ! -L "$a" ] && [ -e "$a" ]; then rm -f "$a" 2>/dev/null; fi
  [ -L "$f" ] && return 0
  [ -e "$f" ] || return 0
  rm -f "$f" 2>/dev/null
  [ -e "$f" ] && return 1
  return 0
}

# ---------------------------------------------------------------- the blind wall
#
# THE WALL THAT ROSTERS A DISPATCH IS REGISTERED ON THE SKILL CHANNEL, not in hooks.json:
# skills/canonical-sdlc/SKILL.md's own frontmatter registers hooks/dispatch-preflight.sh
# (that partition is deliberate — the wall is armed-scoped, not always-on). A skill-channel
# registration lives in the process's `sessionHooks` table and does NOT survive a session
# continue, a `/clear`+resume, or `/reload-plugins`. When it is gone, NOTHING SAYS SO:
# dispatches launch normally, no row is written, and the first symptom is a tick REFUSING
# with "no roster" — which reads as "nothing has been dispatched yet", the exact opposite of
# what happened. Measured live 2026-08-22; the same symptom is recorded unresolved at
# .bionic/docs/record/session-20260814-wave-detector-terminal-state/min-interactive-agent-hook.md
# §6, and the cure proven the same day is to re-invoke the skill in the same process.
#
# So the tick — which already runs inside the session and already holds its session id —
# compares TWO records of the same event:
#
#   the transcript, which the CLI writes whatever the hooks do:  every `Agent` tool_use
#   the roster,     which only the wall writes:                  every dispatch it saw
#
# A gap between them is the wall's absence, observed rather than assumed. This is a
# DIAGNOSIS, not a gate: it never refuses anything, and it never touches the roster.
#
# WHAT IS DELIBERATELY NOT COUNTED, each because counting it would make a live wall look
# blind: a tool_use inside an agent context (`isSidechain`, or an explicit agent key) — a
# teammate's dispatch never reaches this wall at all (record §5a), so it can never be
# rostered and its absence is not news; and a dispatch the wall REFUSED, which exits before
# the roster append and is therefore a wall doing its job, recognized by the CLI's own
# `PreToolUse:Agent hook error:` marker in the tool result.
#
# TWO HONEST LIMITS, both a false ALARM rather than a false silence, and both cheap because
# the cure is idempotent (re-invoking the skill changes nothing when the wall is live):
# a Step-8 cleanup that wipes `.bionic/tmp` mid-session leaves the transcript's dispatches
# with no rows to match; and a transcript that quotes the refusal marker verbatim (a record
# file read into context) inflates the refusal count, which suppresses rather than raises.
#
# The transcript is resolved EXACTLY as hooks/dispatch-preflight.sh resolves it for its own
# liveness question (`roster_session_live`): a session's transcript is `<sid>.jsonl` under
# some project directory of CLAUDE_CONFIG_DIR/projects. Not resolvable means SILENT — a
# detector that cannot read cannot report.

session_transcript() {  # <session-id> -> path on stdout, nonzero if none
  local sid="$1" cfg d f
  [ -n "$sid" ] || return 1
  cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  [ -d "$cfg/projects" ] || return 1
  for d in "$cfg"/projects/*/; do
    f="${d}${sid}.jsonl"
    if [ -f "$f" ] && [ ! -L "$f" ]; then
      printf '%s' "$f"
      return 0
    fi
  done
  return 1
}

# Occurrences, never lines: a parallel fan-out puts several `Agent` tool_uses in ONE
# assistant entry, and a line-counting read would report that batch as a single dispatch.
# The literal `"name":"Agent"` cannot be forged from prose quoting it, because inside a JSON
# string every quote is backslash-escaped and the escaped form does not contain it.
count_main_thread_dispatches() {  # <transcript> -> count on stdout
  awk '
    /"isSidechain"[[:space:]]*:[[:space:]]*true/          { next }
    /"agent_?[Ii][dD]"[[:space:]]*:[[:space:]]*"[^"]/     { next }
    { n += gsub(/"name"[[:space:]]*:[[:space:]]*"Agent"/, "") }
    END { print n+0 }
  ' "$1" 2>/dev/null
}

# A REFUSAL IS A JOIN, NOT A LITERAL. `PreToolUse:Agent hook error:` is what the CLI writes
# into a refused dispatch's tool_result — and it is ordinary text everywhere else. The plan
# that specifies this check, the reviews of it and every brief that quotes it carry the
# literal, so reading one of those files puts the marker in a tool_result of THAT read, and
# a transcript-wide grep for it counted 19 refusals in the session that wrote this line
# against a truth of 1 — the detector inert in the repository that builds it. So the marker
# is credited only where it joins BY tool_use_id to an `Agent` tool_use of this thread: the
# refused dispatch's own result. payload/scripts/lib/patrol.sh applies the identical rule
# for doctor's reconstruction, and tests/cross-gate-agreement.test.sh §Q asks both copies
# the same fixture and compares their two answers to each other.
#
# TWO REGIONS OF THE LINE, and only one of them is the result. Beside `message` the CLI
# writes a sibling `toolUseResult` field restating the same result — and for a SPAWN it
# writes the whole brief there, so a brief that quotes the marker (this one does) plants
# one on a successful dispatch's own line. The scan therefore stops at that key: `message`
# precedes it on every entry this machine has written (34k records, 0 counterexamples), and
# a tool_result never appears twice in one entry, which is what lets one line credit at
# most one refusal. If the CLI ever reorders those keys this over-credits again rather than
# going quiet — §Q's spawn-echo fixture is what would say so.
#
# ONE PASS is enough: a result cannot be written before the call it answers, so every Agent
# id is already known by the time its tool_result is read.
count_refused_dispatches() {  # <transcript> -> count on stdout
  awk '
    function quoted_value(seg,   v) {     # `"key" : "value"` -> value
      v = seg; sub(/^.*:[[:space:]]*"/, "", v); sub(/"$/, "", v); return v
    }
    /"isSidechain"[[:space:]]*:[[:space:]]*true/          { next }
    /"agent_?[Ii][dD]"[[:space:]]*:[[:space:]]*"[^"]/     { next }
    {
      # Every `Agent` tool_use on this line, by id. The CLI writes a tool_use as
      # {"type","id","name","input",...}, so the id is the last one before the name.
      rest = $0
      while (match(rest, /"name"[[:space:]]*:[[:space:]]*"Agent"/)) {
        head = substr(rest, 1, RSTART - 1)
        rest = substr(rest, RSTART + RLENGTH)
        if (match(head, /.*"id"[[:space:]]*:[[:space:]]*"[^"]+"/))
          isagent[quoted_value(substr(head, RSTART, RLENGTH))] = 1
      }

      cut = index($0, "\"toolUseResult\"")
      region = (cut > 0) ? substr($0, 1, cut - 1) : $0
      if (index(region, "PreToolUse:Agent hook error:") > 0) {
        while (match(region, /"tool_use_id"[[:space:]]*:[[:space:]]*"[^"]+"/)) {
          if (quoted_value(substr(region, RSTART, RLENGTH)) in isagent) { n++; break }
          region = substr(region, RSTART + RLENGTH)
        }
      }
    }
    END { print n+0 }
  ' "$1" 2>/dev/null
}

# One row per dispatch, and only the row the WALL itself writes: `status=intended` is
# hooks/dispatch-preflight.sh's own append (its ROW, one per Agent PreToolUse). The later
# `status=confirmed` / `status=identified` copies hooks/execution-recorder.sh appends are
# the SAME dispatch re-stated on an append-only file, so counting them would inflate the
# rostered side threefold and hide every real gap. Schema-prefix filtered first, the same
# discipline every other roster reader in the fleet follows.
count_rostered_dispatches() {  # <roster file> <session-id> -> count on stdout
  [ -f "$1" ] || { printf '0'; return 0; }
  grep -F "roster-state/v1|" "$1" 2>/dev/null \
    | grep -F "|session=$2|" \
    | grep -c -F "|status=intended|"
}

# ---------------------------------------------------------------- the run's own state
#
# WHAT THE TICK COULD NOT SEE UNTIL NOW. `open == 0` is not "this run is finished" — it is
# "nothing is dispatched at this instant", which is equally the gap between two batches of a
# live wave: every writer of one slice landed, the next slice not yet briefed. DISARM is
# terminal by doctrine (skills/canonical-sdlc/SKILL.md §Dispatch: "DISARM also ends the
# Patrol"), so taking it in that gap ended the supervision of a run with days of work left,
# silently, and the next stretch of the wave ran unwatched. That is measured on this repo's
# own epic-20 W1 dogfood, not projected (the idea file's §B-4). The roster cannot tell the
# two states apart, because a finished run and a mid-wave lull spell the same zero.
#
# THE PLAN CAN. A canonical-sdlc run publishes where it is in one line of its own plan, and
# it says it is FINISHED in exactly one way: `current: 9` with a `Step 9:` line carrying
# `delivered:`. So the tick takes ONE plan read, bounded to those two fields (D3, Chris
# 2026-08-30), and DISARM now requires the RUN to say it is delivered rather than the roster
# merely being quiet. Everything else the plan holds is none of the tick's business.
#
# THE READ IS THE LIBRARY'S, AND THERE IS NO SECOND ONE (POKER/2, ratified 2026-09-03).
# `docs_root` and `active_plan` in payload/scripts/lib/run.sh answer "which *.md answers for
# this run" for the whole fleet; this file used to carry a private copy of that walk —
# `has_sdlc_state()`, `resolve_docs_root()`, `normalize_newlines()`'s selection loop inside
# `newest_sdlc_plan()` — bounded at depth 2 and fence-aware, while the library walked 3.
# tests/cross-gate-agreement.test.sh §S.3d pinned that disagreement rather than papering over
# it, and slice SCHED closed it by moving the library to depth 2 and deleting the copy. Two
# plan readers with different bounds is the exact drift this wave exists to end.
#
# WHAT THE COPY WAS PROTECTING IS UNCHANGED, because the library carries it: the candidate
# filter is the unfenced `## SDLC State` marker, and the read translates line endings rather
# than deleting them. The UNFILTERED read is a measured incident — on 2026-08-15 a
# marker-less *.md that happened to be newest under plans/ won the newest race, `current:`
# parsed empty, and every wall reading it passed silently for ~15 minutes
# (.bionic/docs/record/session-20260815-landing-supervision/t8-forensic-read.md). A tick
# reading the plan that way would DISARM off a scrap file. hooks/patrol-revive.sh:64-70
# refused a plan read outright for that reason; the marker filter is what makes the read safe
# to take here, and it now lives in one file instead of six.
#
# FAIL DIRECTION IS `open`, without exception. No project root, no docs root, no plan, an
# unreadable plan, a plan whose `current:` will not parse, a `current: 9` with no
# `delivered:`, a delivery this session cannot place in time (no arming record), and a
# delivery that PREDATES this session's arming — every one of them answers `open`, and `open`
# never DISARMs. A wrong `open` costs a Patrol that keeps ticking over a finished run, which
# one `disarm` ends; a wrong `delivered` costs the silent, terminal end of supervision over a
# live wave, which nothing recovers. The asymmetry is the whole design.

# CRLF and CR-only line endings TRANSLATED, never deleted: a deleted CR would join two
# lines into one and hand `current:` a value that was never written. This is a TEXT utility,
# not a plan reader — the plan reader is the library's — and it survives the POKER/2
# unification because the section read below still has to see real newlines.
normalize_newlines() {
  awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$1"
}

# THE TWO FIELDS, AND NOTHING ELSE. `current:` and the `Step 9:` line are read out of the
# fence-aware `## SDLC State` section exactly as the evidence gate reads them, so a plan
# documenting the schema inside a ``` example cannot answer for the run.
#
# The `why` half is not decoration: it is the whole content of the QUIET line this feeds. A
# tick that says "no open row, but the run is not delivered" and stops there tells its reader
# nothing they can act on, and the reader is a model deciding whether the Patrol is broken.
run_state() {  # <project root> <arming-record path, may be empty> -> "delivered|<why>" or "open|<why>"
  local repo="$1" armed="${2:-}" droot plan section current line
  if [ -z "$repo" ] || [ ! -d "$repo" ]; then
    printf 'open|no project root resolved, so no plan could be read'
    return 0
  fi
  # ONE CALL EACH, AND NEITHER IS RESTATED HERE. `docs_root` is asked only so the refusal
  # below can name the directory it searched; `active_plan` is the selection itself.
  droot="$(docs_root "$repo")"
  plan="$(active_plan "$repo")" || plan=""
  if [ -z "$plan" ]; then
    printf 'open|no plan carrying an unfenced "## SDLC State" under %s/{plans,incidents}' "$droot"
    return 0
  fi
  section="$(normalize_newlines "$plan" | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^## SDLC State/ { flag=1; next }
    /^## / { flag=0 }
    flag')"
  current="$(printf '%s\n' "$section" \
             | grep -E '^[[:space:]]*current[[:space:]]*:' \
             | head -1 \
             | sed -E 's/^[[:space:]]*current[[:space:]]*:[[:space:]]*//' \
             | tr -d '[:space:]')"
  if [ -z "$current" ]; then
    printf 'open|%s carries no readable "current:" line' "$plan"
    return 0
  fi
  if [ "$current" != "9" ]; then
    printf 'open|%s is at current: %s' "$plan" "$current"
    return 0
  fi
  line="$(printf '%s\n' "$section" \
          | grep -E '^[[:space:]]*-?[[:space:]]*Step[[:space:]]+9[[:space:]]*:' \
          | head -1)"
  case "$line" in
    *delivered:*) : ;;
    *) printf 'open|%s is at current: 9 but its Step 9 line records no delivered:' "$plan"
       return 0 ;;
  esac

  # WHOSE DELIVERY IS IT? A `delivered:` on the newest plan says a run finished; it does not
  # say THIS run finished. A session that closes run W and then starts W+1 arms at Step 0 —
  # SKILL.md §Dispatch, "at engagement" — while W+1's plan, and the `## SDLC State` that
  # would answer for it, does not exist until Step 1-3. Through that whole window the newest
  # SDLC-State plan is W's, its Step-9 line still records `delivered:`, and the roster is
  # empty because nothing has been dispatched yet: the tick DISARMed, removed the stamp, and
  # the arming wall refused the new run's first dispatch (critic C-4, wave-1.3.2 Step 6).
  #
  # So a delivery counts only if it POSTDATES this Patrol's arming, and the arming instant is
  # the mtime of the record `arm` wrote. `-nt` rather than a seconds comparison: it is the
  # same primitive the selection block above uses, it carries whatever resolution the
  # filesystem has, and it resolves a tie as NOT newer — which is the fail direction this
  # whole function already takes everywhere else.
  #
  # NO RECORD IS DOUBT, AND DOUBT IS `open` (ADR-002 §3). A tick in a session that never
  # armed cannot place the delivery in time at all.
  if [ -z "$armed" ] || [ ! -f "$armed" ]; then
    printf 'open|%s records delivered:, but this session has no arming record to date it against' "$plan"
    return 0
  fi
  if [ ! "$plan" -nt "$armed" ]; then
    printf 'open|%s records delivered:, but it was delivered before this Patrol armed — that is the previous run' "$plan"
    return 0
  fi
  # THE LIBRARY'S SECOND OPINION, as a CONJUNCT and never as a replacement. `active_run`
  # (payload/scripts/lib/run.sh) is the SSoT for "is this run open" (spec §3, ownership
  # table) and it reads more plans than the block above does — depth 3, and no fence
  # filter. The read above is the evidence gate's, held body-for-body by
  # tests/cross-gate-agreement.test.sh §S, and it is the STRICTER of the two: a fenced
  # `## SDLC State` is documentation here and a run there. So the two are ANDed in the one
  # direction that cannot cost anything — where the library still calls the run open,
  # `open` wins. That is this function's fail direction everywhere else, applied to the
  # one reader that can see a plan this one cannot.
  if active_run "$repo" >/dev/null 2>&1; then
    printf 'open|%s records delivered:, but lib/run.sh:active_run still reads this run as open' "$plan"
    return 0
  fi
  printf 'delivered|%s is at current: 9 and its Step 9 line records delivered:' "$plan"
}

# ---------------------------------------------------------------- the scheduler
#
# FILL / HOLD / NARROW / EMERGENCY (spec AC-29, AC-30, AC-31; design-ledger S7).
#
# THE PROBLEM. A wave's width was a number in a brief, and a ceiling nobody reaches is a
# wave running one writer at a time by accident: this repo's own 1.4.0 wave dispatched six
# trees against a budget of twenty-two and then went quiet for a batch at a time. Nothing
# on the machine was watching for the gap, because the only thing that fires on its own is
# the Patrol tick — and the tick had no opinion about width.
#
# THE FOUR DECISIONS, and the ONE rule that orders them. Pressure is read FIRST, every tick,
# before a single fill is considered: filling a machine that is already starving is the one
# mistake that costs work rather than time (lib/resources.sh, "MEMORY IS HARD, COMPUTE IS
# SOFT" — the measured failure is a kernel SIGKILL mid-suite).
#
#   EMERGENCY  free memory under the kill floor -> name the youngest suite-running writer
#              for the orchestrator to stop through the stopping standard. Nothing is
#              filled, and the tick does not stop anything itself.
#   HOLD       free memory or load past the warning line -> no fills this tick, with the
#              measurement printed beside the verdict (a HOLD with no number is
#              indistinguishable from a bug).
#   NARROW     a hold that SURVIVES a tick -> recommend halving the test-runner width
#              carried in new briefs.
#   FILL       otherwise -> the ready slices, up to the gap between the budget's `writers`
#              and the rows already open on this session's roster.
#
# THE TICK READS PRESSURE TO THROTTLE, NEVER TO RE-DERIVE THE BUDGET. `resources_budget` is
# a pure function of machine FACTS and is written once, into the plan header, by Step 0. A
# tick that lowered `writers` because the machine was briefly busy would make the ceiling a
# function of the weather, which is the drift lib/resources.sh exists to remove. Everything
# here either reads that string or refuses to act; nothing here writes it.
#
# EVERY DECISION IS ADVISORY. The tick prints; the orchestrator dispatches, stops and edits
# the plan. hooks/patrol-duties-gate.sh is what makes a printed FILL binding — the tick's
# turn may not end until the named dispatches or an explicit decline appear — and that is a
# wall on the ORCHESTRATOR, not an action taken here. A hook that dispatched agents or
# stopped them would be a hook taking irreversible action off a reading it cannot confirm.

# One field out of a space-separated `key=value` record (resources_probe's shape, and the
# plan header's `parallel-budget:` value), BY KEY and never by position.
space_field() {  # <record> <key> -> value on stdout, empty if absent
  printf '%s' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -1
}

# The plan header's `parallel-budget:` value, or empty.
#
# THE LEADING FRONTMATTER BLOCK ONLY, byte-for-byte the read hooks/dispatch-preflight.sh's
# budget arm takes: a `parallel-budget:` inside the plan BODY is prose — this wave's own
# plan quotes the header in a slice description — and a reader that took a quotation for
# configuration would fill against a number nobody set.
plan_budget_line() {  # <plan> -> the value after `parallel-budget:`, or empty
  awk '
    NR == 1 && $0 != "---" { exit }
    NR == 1 { next }
    $0 == "---" { exit }
    /^parallel-budget:[ \t]*/ { sub(/^parallel-budget:[ \t]*/, ""); print; exit }
  ' "$1" 2>/dev/null
}

# One integer field out of that value. NOT AN INTEGER IS ABSENT: an arm this cannot measure
# goes unmeasured and says so, exactly as the dispatch wall's own budget_field does.
budget_int() {  # <budget line> <key> -> a non-negative integer, or empty
  local v
  v="$(space_field "$1" "$2")"
  case "${v:-}" in ''|*[!0-9]*) printf '' ;; *) printf '%s' "$v" ;; esac
}

# THE SLICE TABLE, read out of the active plan.
#
# WHAT IT LOOKS FOR is a table HEADER row naming `id`, `deps` and `status`, not a heading
# and not a column count. The plan's `## Slices (machine-readable …)` section is where it
# lives today and its shipped shape is four columns — `| id | deps | complexity | status |`
# — but a reader keyed on position breaks the first time a column is inserted, and a reader
# keyed on the heading breaks on a plan that words it differently. Column INDICES are taken
# from the header row by name, so both stay ordinary edits.
#
# FENCE-AWARE, for the reason every other plan read in this file is: a table inside a ```
# example is documentation about the schema, and filling a wave off a documented example is
# the newest-race incident in a new costume.
#
# Emits one `id<TAB>deps<TAB>status` record per row, in TABLE ORDER, which is the order the
# FILL line prints in — the plan's own dependency ordering, maintained by the orchestrator,
# rather than an ordering this hook invents.
slice_table() {  # <plan> -> id<TAB>deps<TAB>status, one per row
  normalize_newlines "$1" 2>/dev/null | awk '
    function trim(v) { sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v); return v }
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    !intable {
      if ($0 !~ /^[[:space:]]*\|/) next
      n = split($0, c, "|")
      idc = 0; depc = 0; stc = 0
      for (i = 1; i <= n; i++) {
        t = trim(c[i])
        if (t == "id") idc = i
        else if (t == "deps") depc = i
        else if (t == "status") stc = i
      }
      if (idc && depc && stc) intable = 1
      next
    }
    {
      if ($0 !~ /^[[:space:]]*\|/) exit
      n = split($0, c, "|")
      id = trim(c[idc])
      # The |---|---| separator row, and any row whose id cell is empty or punctuation.
      if (id == "" || id ~ /^[-: ]+$/) next
      printf "%s\t%s\t%s\n", id, trim(c[depc]), trim(c[stc])
    }'
}

# READY = a `pending` row whose EVERY dependency is `landed`.
#
# A dependency cell is a comma-separated list of ids, or an em dash / hyphen / empty cell
# for "none". An id this table does not carry is NOT ready: an unresolvable dependency is a
# dependency this reader cannot confirm landed, and the fill direction here is the cautious
# one — a slice held back costs a batch, a slice dispatched onto an unlanded dependency
# costs the writer's whole run.
slice_ready() {  # <table> -> the ready ids, one per line, in table order
  # ONE PASS TO REMEMBER, one to decide, over the same stream: a dependency may be named
  # before or after the row that depends on it, so nothing can be answered until the whole
  # table has been read. Table order is preserved by indexing on NR.
  printf '%s\n' "$1" | awk -F'\t' '
    $1 == "" { next }
    { n = n + 1; id[n] = $1; dep[n] = $2; st[$1] = $3 }
    END {
      for (i = 1; i <= n; i++) {
        if (st[id[i]] != "pending") continue
        deps = dep[i]
        gsub(/[[:space:]]/, "", deps)
        # A cell with no alphanumeric character names no dependency: the empty cell, the
        # hyphen and the em dash the plan actually uses are all spelled this one way, and
        # matching the dash byte-for-byte would put a Unicode literal in a bash 3.2 awk
        # program for no gain.
        if (deps !~ /[A-Za-z0-9]/) { print id[i]; continue }
        m = split(deps, d, ",")
        ready = 1
        for (j = 1; j <= m; j++) {
          if (d[j] == "" || d[j] !~ /[A-Za-z0-9]/) continue
          if (st[d[j]] != "landed") { ready = 0; break }
        }
        if (ready) print id[i]
      }
    }'
}

# THE YOUNGEST SUITE-RUNNING WRITER on this session's roster, as the address the stopping
# standard takes — `<name>@session-<id8>`, the one spelling both stop gates accept
# (POKER/8). Empty when there is none.
#
# "SUITE-RUNNING" IS READ OFF THE LEDGER, never off the process table (WALLS/3): an open row
# whose `claims=` field is non-empty declared a subprocess claim and therefore spends a
# suite. A `pgrep` per row would be truer to the word "running" and would put a process
# spawn per row inside a Patrol tick.
#
# "OPEN" is the roster's own predicate — a `status=intended` row whose name carries no
# `landing-swept/v1` marker — the same one lib/patrol.sh's `patrol_roster_state` uses.
#
# YOUNGEST, because the rung is a kill floor and the youngest writer has the least work to
# lose. `launched_at` is an ISO-8601 Z stamp, so a lexical max IS a chronological max.
youngest_suite_writer() {  # <roster file> <session-id> -> <name>@session-<id8>, or empty
  local roster="$1" sid="$2" swept name
  [ -n "$roster" ] && [ -f "$roster" ] && [ ! -L "$roster" ] || return 0
  swept="$(grep '^landing-swept/v1|' "$roster" 2>/dev/null || true)"
  name="$(grep '^roster-state/v1|status=intended|' "$roster" 2>/dev/null \
    | while IFS= read -r RL; do
        [ -n "$(line_field "$RL" claims)" ] || continue
        RN="$(line_field "$RL" name)"
        [ -n "$RN" ] || continue
        case "$swept" in *"|name=${RN}|"*) continue ;; esac
        printf '%s\t%s\n' "$(line_field "$RL" launched_at)" "$RN"
      done | sort | tail -1 | cut -f2-)"
  [ -n "$name" ] || return 0
  printf '%s@session-%s' "$(clean "$name")" "$(printf '%s' "$sid" | cut -c1-8)"
}

# ---------------------------------------------------------------- adoption
#
# WHAT A `/clear`+RESUME ACTUALLY LOSES, and what it does not. Lost: the completion message
# (the CLI delivers it to the conversation that dispatched, and that conversation is gone)
# and the orchestrator's in-memory dispatch ledger. NOT lost: the agent itself — same
# process, still working — its artifacts, its transcript under
# `<config>/projects/<slug>/<old-sid>/subagents/agent-<id>.jsonl`, and its roster row, which
# lives in the PROJECT's `.bionic/tmp` rather than in any session.
#
# So the successor session can read every one of those files and still be unable to ACT on
# the agent, because the one thing it cannot re-derive is the AGENT ID — the identity the
# CLI handed back at launch and only the dead conversation held. `SendMessage` and
# `TaskStop` both take it, and hooks/stop-guard.sh refuses a stop by NAME for exactly this
# reason ("a NAME is not an identity — it is reused across waves"), naming the full agent id
# as the deliberate way through. The id is on disk the whole time: hooks/execution-recorder.sh
# writes it onto the row as `status=identified|agent_id=`.
#
# `adopt` is the verb that reads it back. For every roster in this project's `.bionic/tmp`
# that belongs to some OTHER session, it prints each row that is still open, its id, and the
# three addresses derived from that id — observe, message, stop — plus a verdict taken from
# disk rather than from memory.
#
# IT WRITES EXACTLY ONE THING, AND IT IS THIS SESSION'S OWN ROSTER. Everything else this
# verb touches is read: no PREDECESSOR roster is ever written (that session may still be
# appending to it), no Patrol stamp is taken (this is not a tick and must not age the
# arming wall's clock), and nothing is stopped or messaged.
#
# The one write is the adoption itself, and it exists because printing an id was only half
# a cure (epic-20 W1 B-1). Every wall downstream of the id asks THIS session's roster
# whether the agent is ours — hooks/stop-guard.sh establishes ownership from a
# `confirmed`/`identified` row carrying the resolved id, hooks/stop-check.sh classifies
# from the same accepted set — so with no row of ours the predecessor's agent classifies
# FOREIGN and every stop of it is refused. `adopt_write_row` below is the successor saying
# on disk what this verb has just said on the terminal: this contract is mine now.
#
# THIS SESSION'S OWN ROWS ARE NEVER ADOPTED. They are not lost — the running session still
# holds them — and printing them would invite the successor to re-ledger work it is already
# tracking, which is the double-counting the roster exists to prevent.

# `<config>/projects/<slug>/<sid>/subagents` — the same walk session_transcript does, one
# level deeper, and keyed on the DIRECTORY rather than the session's own `.jsonl`: an old
# session's transcript can be reclaimed while its agents' files survive, and the agents are
# what this verb is about.
session_subagent_dir() {  # <session-id> -> path on stdout, nonzero if none
  local sid="$1" cfg d
  [ -n "$sid" ] || return 1
  cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  [ -d "$cfg/projects" ] || return 1
  for d in "$cfg"/projects/*/; do
    if [ -d "${d}${sid}/subagents" ]; then
      printf '%s' "${d}${sid}/subagents"
      return 0
    fi
  done
  return 1
}

# THE REPORT, RECOVERED FROM THE TRANSCRIPT — the recovery skills/canonical-sdlc/SKILL.md
# §Dispatch already prescribes by hand ("the report is the last long `assistant` text block
# in that agent's file"), done by machine. Each assistant entry's text blocks are joined and
# re-emitted as ONE JSON string per entry, because a text block spans lines and a
# line-oriented pass would cut a report in half. The LAST block over the floor wins; if
# nothing clears it, the last block of any size does, so a short-report agent is quoted
# rather than dropped.
#
# It is a QUOTE, not an artifact. SKILL.md's own rule stands: persist it under
# `<docs-root>/record/` before acting on it — a transcript is one cleanup away from gone.
#
# AND IT IS UNTRUSTED TEXT. What is quoted here is whatever the agent typed, printed into
# the operator's terminal by a verb they ran to find out what a predecessor left behind —
# an escape sequence in it would repaint or rewrite that terminal rather than be read. The
# control characters are stripped for that reason, tab and newline excepted because the
# report's own line structure is what the caller indents.
agent_report_tail() {  # <transcript> -> the tail on stdout, nonzero if nothing to quote
  local raw
  [ -f "$1" ] || return 1
  command -v jq >/dev/null 2>&1 || {
    printf '(report tail unavailable: jq is not on PATH)'
    return 0
  }
  raw="$(jq -r 'select(.type == "assistant")
                | ((.message.content // []) | map(select(.type == "text") | .text) | join("\n"))
                | select(length > 0)
                | @json' "$1" 2>/dev/null \
    | awk -v min="$ADOPT_TAIL_MIN" '
        { any = $0 }
        length($0) - 2 >= min { last = $0 }
        END { if (last != "") print last; else if (any != "") print any }')"
  [ -n "$raw" ] || return 1
  printf '%s' "$raw" | jq -r '.' 2>/dev/null | tr -d '\000-\010\013-\037\177' | head -c "$ADOPT_TAIL_CAP"
}

# ONE FOLD PER PREDECESSOR ROSTER, and the same rule the fleet's other three folds keep: the
# file is append-only, a contract advances along it (`intended` -> `confirmed` ->
# `identified`), every writer copies the contract fields forward, so the LAST row carrying a
# name is the authoritative one (tests/cross-gate-agreement.test.sh §P). Two departures,
# both because this fold answers a question the others do not:
#
#   THE ID IS TAKEN OFF `identified`/`confirmed` ONLY, never off `intended` — the same
#   accepted set hooks/stop-guard.sh and hooks/stop-check.sh use for ownership, and for the
#   same reason: `intended` carries `agent_id=` empty by design, and a row that never
#   advanced past it has no identity to offer. That row is the UNADDRESSABLE case, reported
#   with its cure rather than skipped, because a silent skip is how a predecessor's agent
#   becomes invisible twice.
#
#   A ROW IS CLOSED BY A LANDED MARKER OR BY AN ACK, and by nothing else. `landing-swept/v1`
#   with `state=MET` is hooks/landing-gate.sh saying the contract landed; the ack ledger is
#   the orchestrator saying so by hand, and the sweeper's own ledger comment already binds
#   it across sessions ("an ack taken in a session that has since died is still in force in
#   its successor"). A `landing-swept` marker reading UNMET closes NOTHING here: an answered
#   failure is exactly the row a resumed session most needs to see.
#
# THE ORIGIN IS CARRIED OUT WITH THE ROW, and it is what the stop address is built from
# (T3 FINDING 1). `adopted_from=` wins over `session=` when the row has one: a row that was
# itself adopted is filed under the session that TOOK it, while the harness's teammate table
# keeps naming the session that made the `Agent` call, and `adopted_from` is the only field
# on the row that still points there. Absent both, the caller falls back to the roster
# file's own session — the invariant every roster writer keeps.
#
# Output is one `|`-delimited record per open row. `|` rather than a tab because every value
# on a roster row is cleaned of `|` at write time, while the shell collapses runs of tabs
# and would silently merge two empty fields into one.
adopt_fold() {  # <roster file> <ack ledger file> -> name|id|type|deliverable|progress|cadence|launched_at|origin
  awk -v ackfile="$2" '
    function kv(line, key,   n, a, i, eq, k) {
      n = split(line, a, "|")
      for (i = 1; i <= n; i++) {
        eq = index(a[i], "=")
        if (eq == 0) continue
        k = substr(a[i], 1, eq - 1)
        if (k == key) return substr(a[i], eq + 1)
      }
      return ""
    }
    BEGIN {
      if (ackfile != "") {
        while ((getline l < ackfile) > 0) {
          if (l !~ /^sweeper-ledger\/v1\|/) continue
          if (kv(l, "event") != "ack") continue
          an = kv(l, "name")
          if (an != "") acked[an] = 1
        }
        close(ackfile)
      }
    }
    /^roster-state\/v1\|/ {
      n = kv($0, "name"); if (n == "") next
      if (!(n in seen)) { seen[n] = 1; order[++cnt] = n }
      v = kv($0, "subagent_type"); if (v != "") stype[n] = v
      v = kv($0, "deliverable");   if (v != "") deliv[n] = v
      v = kv($0, "progress");      if (v != "") prog[n]  = v
      v = kv($0, "cadence");       if (v != "") cad[n]   = v
      v = kv($0, "launched_at");   if (v != "") launch[n] = v
      v = kv($0, "session");       if (v != "") sess[n]   = v
      v = kv($0, "adopted_from");  if (v != "") afrom[n]  = v
      st = kv($0, "status")
      if (st == "identified" || st == "confirmed") {
        v = kv($0, "agent_id"); if (v != "") id[n] = v
      }
      next
    }
    /^landing-swept\/v1\|/ {
      n = kv($0, "name")
      if (n != "" && kv($0, "state") == "MET") met[n] = 1
      next
    }
    END {
      for (i = 1; i <= cnt; i++) {
        n = order[i]
        if (n in met) continue
        if (n in acked) continue
        printf "%s|%s|%s|%s|%s|%s|%s|%s\n", n, id[n], stype[n], deliv[n], prog[n], cad[n], \
               launch[n], ((n in afrom) ? afrom[n] : sess[n])
      }
    }
  ' "$1" 2>/dev/null
}

# THE ADOPTED ROW — the verb's one write, and the second half of the B-1 cure. What it
# records is an ownership fact, and each field is there because a named reader asks for it:
#
#   status=identified   the accepted set hooks/stop-guard.sh and hooks/stop-check.sh
#                       establish ownership BY ID from. `confirmed` would do as well and
#                       says less: the id is known, which is exactly what `identified` means.
#   agent_id=           the TRANSCRIPT form, the only form either gate resolves a target to.
#   teammate_id=        the ADDRESSING form `<name>@session-<id8>`, the only spelling the
#                       platform's stop primitive takes for a teammate — built from the
#                       session that LAUNCHED the agent, never from ours (T3 FINDING 1). The
#                       teammate table keys on the session that made the `Agent` call and a
#                       `/clear` does not move it; hooks/stop-guard.sh reads this recorded
#                       address before it constructs one, so a row carrying our own eight
#                       would put the string the harness rejects into every refusal it
#                       prints. The caller hands it in already built, for the same reason
#                       the address is printed from there: one construction, one origin.
#   adopted_from=       provenance. The agent is still filed under the predecessor's own
#                       subagents directory, and that directory is what hooks/stop-guard.sh
#                       must widen its resolution to; without this field it cannot know
#                       which session to widen to, and a blind project-wide walk is exactly
#                       the name-oracle the 4/9 ownership rule removed.
#   the contract        deliverable/progress/cadence, copied forward unchanged — the same
#                       forward-copy every roster writer in the fleet performs, so the
#                       successor's readers see the contract the predecessor declared.
#
# THE APPEND IDIOM IS hooks/dispatch-preflight.sh's (:1339-1347), copied deliberately:
# header-if-absent, `chmod 600`, ONE `printf` of one line, NO LOCK. A single O_APPEND write
# of well under a pipe buffer is not interleaved by the kernel; a read-modify-write here
# would drop rows another writer appended in between (hooks/execution-recorder.sh:399-419).
#
# IDEMPOTENT BY READ-BEFORE-APPEND. `adopt` is the first verb a resumed session runs and it
# is run again at the next resume, so a row already carrying this agent's id AND a
# provenance is left alone — otherwise the roster would grow one row per run without
# carrying one new fact. The read is ADVISORY, never a lock: a lost race duplicates a row,
# which every reader in the fleet already tolerates (the last row carrying a name wins).
#
# A ROW WITH NO ID IS NEVER WRITTEN. That is the UNADDRESSABLE verdict's whole content —
# there is no identity to file — and a row carrying `agent_id=` empty would be inert at
# every by-id reader while looking like an adoption on disk.
adopt_write_row() {  # <roster file> <sid> <name> <id> <type> <deliverable> <progress> <cadence> <launched> <from-sid> <teammate address> -> 0 written/already there, 1 not
  local f="$1" sid="$2" name="$3" id="$4" typ="$5" deliv="$6" prog="$7" cad="$8"
  local launch="$9" osid="${10}" addr="${11}" d
  [ -n "$id" ] || return 1
  [ -n "$sid" ] || return 1
  d="${f%/*}"
  tmp_dir_ok "$d" || return 1
  [ -L "$f" ] && return 1
  if [ -f "$f" ] && awk -v k="|agent_id=${id}|" '
        index($0, k) > 0 && index($0, "|adopted_from=") > 0 { found = 1 }
        END { exit !found }' "$f" 2>/dev/null; then
    return 0
  fi
  mkdir -p "$d" 2>/dev/null || return 1
  if [ ! -e "$f" ]; then
    printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' \
      >> "$f" 2>/dev/null && chmod 600 "$f" 2>/dev/null
  fi
  printf 'roster-state/v1|status=identified|session=%s|name=%s|agent_id=%s|launched_at=%s|subagent_type=%s|model=|deliverable=%s|source=adopted|duration=|progress=%s|claims=|cadence=%s|absent=|waiver=|teammate_id=%s|adopted_from=%s|tool_use_id=\n' \
    "$sid" "$(clean "$name")" "$(clean "$id")" "$(clean "$launch")" "$(clean "$typ")" \
    "$(clean "$deliv")" "$(clean "$prog")" "$(clean "$cad")" \
    "$(clean "$addr")" "$(clean "$osid")" \
    >> "$f" 2>/dev/null || return 1
  return 0
}

# A roster path is absolute or project-relative, exactly as the row's writer left it.
adopt_abs() {  # <path> <repo root>
  case "$1" in
    /*) printf '%s' "$1" ;;
    '') : ;;
    *)  printf '%s/%s' "$2" "$1" ;;
  esac
}

# ---------------------------------------------------------------- verbs

case "$VERB" in

  interval)
    SECS="$(poker_interval_seconds)" || {
      die "REFUSED — the configured poker-interval could not be read as a duration."
      die "Fix or remove the 'poker-interval:' line in .bionic/config.yaml; the default is $POKER_INTERVAL_DEFAULT."
      exit 2
    }
    printf '%s\n' "$SECS"
    exit 0
    ;;

  # THE DEFAULT, WITHOUT THE CONFIG — added for hooks/dispatch-preflight.sh's arming wall
  # (critic C-2, W5). That wall needs a threshold even when `interval` above REFUSES,
  # because a project's config file is machine-local and agent-writable and one unparseable
  # line there must not be able to disarm a wall. It could have retyped 1800; then this
  # script's constant and the gate's would drift the first time either moved, which is the
  # duplication this repo's ownership rule exists to forbid. So the constant and the
  # duration parse stay here, where they already lived, and the gate asks.
  #
  # NOTHING ELSE READS THE CONFIG ON THIS PATH, deliberately: the whole value of this verb
  # to its caller is that a hostile or broken config.yaml cannot change what it answers.
  interval-default)
    SECS="$(parse_seconds "$POKER_INTERVAL_DEFAULT")" || {
      die "REFUSED — this script's own POKER_INTERVAL_DEFAULT ('$POKER_INTERVAL_DEFAULT') is not a duration."
      exit 2
    }
    printf '%s\n' "$SECS"
    exit 0
    ;;

  arm)
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "A Patrol stamp answers for ONE session, so without the key there is nothing to write."
      exit 3
    fi
    if ! write_patrol_stamp "$SESSION_ID" arm; then
      die "REFUSED — the Patrol stamp could not be written; this session is NOT armed."
      die "Check that .bionic/tmp is a writable real directory under the project root."
      exit 2
    fi
    # THE SECOND HALF OF ARMING: the instant, recorded so a later tick can tell THIS run's
    # delivery from the previous one's (R-13). Advisory — a session armed without it keeps
    # ticking and never auto-DISARMs, which is the safe direction — so it warns and the arm
    # still stands.
    write_patrol_armed_marker "$SESSION_ID" \
      || die "WARN — the arming instant could not be recorded; this Patrol will not auto-DISARM (run \`disarm\` to stop it)."
    say "armed — the Patrol stamp is fresh for this session: $(patrol_stamp_file "$SESSION_ID")"
    exit 0
    ;;

  # THE DELIBERATE STOP. Paired with `CronDelete` at run close (the ritual is stated in
  # skills/canonical-sdlc/SKILL.md §Dispatch, and both halves belong to it): `CronDelete`
  # stops the firing, this stops the CLAIM that something is still firing. Either half
  # alone leaves a Patrol that is half-stopped in the direction that lies.
  #
  # IDEMPOTENT, AND SILENT ABOUT NOTHING. A ritual is a thing a model runs from a list, so
  # running it twice, or on a session that never armed, answers 0 and says which of the two
  # it was — a no-op reported as a failure is a line the operator has to stop and interpret
  # at exactly the moment the run is trying to end.
  disarm)
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "A Patrol stamp answers for ONE session, so without the key there is nothing to remove."
      exit 3
    fi
    DISARM_STAMP="$(patrol_stamp_file "$SESSION_ID")" || DISARM_STAMP=""
    if [ -n "$DISARM_STAMP" ] && [ -f "$DISARM_STAMP" ] && [ ! -L "$DISARM_STAMP" ]; then
      if remove_patrol_stamp "$SESSION_ID"; then
        say "disarmed — the Patrol stamp for this session is removed: $DISARM_STAMP"
        say "CronDelete the Patrol job too if it is still in the table; this half only stops the claim that it fires."
        exit 0
      fi
      die "REFUSED — the Patrol stamp could not be removed, so this session still reads as armed."
      die "Remove it by hand or the death notice keeps firing every turn: $DISARM_STAMP"
      exit 2
    fi
    say "already disarmed — no Patrol stamp for this session${DISARM_STAMP:+: $DISARM_STAMP}"
    exit 0
    ;;

  adopt)
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "adopt answers 'what did the OTHER sessions launch here', and without this session's"
      die "own key it cannot tell their rows from ours."
      exit 3
    fi

    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    ADOPT_DIR="$REPO_REAL/.bionic/tmp"
    # The ONE file this verb writes: this session's own roster. Named here, once, so the
    # loop below cannot be read as writing anything it iterates over.
    ADOPT_OWN_ROSTER="$ADOPT_DIR/roster-${SESSION_ID}.state"
    ADOPT_ROWS=0
    ADOPT_SESSIONS=0
    ADOPT_NOW="$(now_epoch)"

    for ADOPT_RF in "$ADOPT_DIR"/roster-*.state; do
      [ -f "$ADOPT_RF" ] || continue
      # Symlinks are not followed, the same posture every other .bionic/tmp reader takes.
      [ -L "$ADOPT_RF" ] && continue
      OSID="${ADOPT_RF##*/}"; OSID="${OSID#roster-}"; OSID="${OSID%.state}"
      [ -n "$OSID" ] || continue
      [ "$OSID" = "$SESSION_ID" ] && continue

      ADOPT_LEDGER="$ADOPT_DIR/sweeper-${OSID}.state"
      [ -f "$ADOPT_LEDGER" ] && [ ! -L "$ADOPT_LEDGER" ] || ADOPT_LEDGER=""
      ADOPT_OUT="$(adopt_fold "$ADOPT_RF" "$ADOPT_LEDGER")"
      [ -n "$ADOPT_OUT" ] || continue
      ADOPT_SESSIONS=$((ADOPT_SESSIONS + 1))

      # Resolved ONCE per predecessor session, not once per row: the walk is the same for
      # every agent that session launched.
      OSUB="$(session_subagent_dir "$OSID")" || OSUB=""

      while IFS='|' read -r RNAME RID RTYPE RDELIV RPROG RCAD RLAUNCH RORIG; do
        [ -n "$RNAME" ] || continue
        ADOPT_ROWS=$((ADOPT_ROWS + 1))

        # ---- THE STOP ADDRESS, BUILT FROM THE SESSION THAT LAUNCHED THE AGENT
        #
        # T3 FINDING 1, live 2026-09-03. This was the ADOPTING session's eight until a real
        # `/clear` was driven against a real harness: `TaskStop PROBE-AGENT@session-<adopting
        # 8>` came back `No task found with ID: … Running teammates:
        # PROBE-AGENT@session-<launching 8>`. The probe that argued for the adopting session
        # was right about the env — `CLAUDE_CODE_SESSION_ID` does re-key — and wrong about
        # the teammate table, which keys on the session that made the `Agent` call and does
        # not re-key with it. So the suffix comes off the ROW (its `adopted_from=`, else its
        # own `session=`, else the roster file's session), never off ours.
        #
        # EMPTY WITHOUT AN ID, because the address is only ever offered beside one: a row
        # with no identity has no stop line to carry it, and a machine field that named an
        # address the UNADDRESSABLE branch refuses to print would contradict its own row.
        ADOPT_ADDR_SID="${RORIG:-$OSID}"
        ADOPT_ADDR=""
        [ -n "$RID" ] \
          && ADOPT_ADDR="$(clean "$RNAME")@session-$(printf '%s' "$ADOPT_ADDR_SID" | cut -c1-8)"

        # ---- the deliverable, on disk or not
        RDELIV_ABS="$(adopt_abs "$RDELIV" "$REPO_REAL")"
        DELIV_PRESENT=no
        [ -n "$RDELIV_ABS" ] && [ -e "$RDELIV_ABS" ] && DELIV_PRESENT=yes

        # ---- the progress file's age against the cadence its own row declared
        RPROG_ABS="$(adopt_abs "$RPROG" "$REPO_REAL")"
        PROG_AGE=""
        [ -n "$RPROG_ABS" ] && [ -f "$RPROG_ABS" ] \
          && PROG_AGE=$(( ADOPT_NOW - $(file_mtime "$RPROG_ABS") ))
        CAD_S="$(parse_seconds "$RCAD")" || CAD_S=""

        # ---- the three addresses, all of them derived from the one id
        TX=""
        TX_PRESENT=no
        TX_AGE=""
        if [ -n "$RID" ]; then
          if [ -n "$OSUB" ]; then
            TX="$OSUB/agent-${RID}.jsonl"
            if [ -f "$TX" ]; then
              TX_PRESENT=yes
              # THE SECOND LIVENESS INPUT. The harness appends to this file on every turn
              # the agent takes, so its mtime is a fact about the agent rather than a
              # promise the agent has to remember to keep.
              TX_AGE=$(( ADOPT_NOW - $(file_mtime "$TX") ))
            fi
          else
            # The slug could not be resolved — say where to look rather than inventing a
            # path that would read as a fact.
            TX="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/*/${OSID}/subagents/agent-${RID}.jsonl"
          fi
        fi

        # ---- the verdict
        #
        # UNADDRESSABLE OUTRANKS THE REST, because it is the only one of the four that is
        # about this verb's own subject — the id. A row without one cannot be messaged or
        # stopped whatever its artifacts say, and the cure is prospective (it fixes the NEXT
        # dispatch, not this row). The deliverable's state is still printed underneath, so
        # nothing is hidden by the ordering.
        # LIVE ON EITHER MTIME, STALE ONLY ON BOTH (1.6, AC-6). The progress file is a
        # promise the agent keeps by hand — the first thing to lapse when the work gets
        # absorbing, and impossible for a role with no Write tool — so reading it alone
        # called working agents SILENT. The transcript is the harness's own record of the
        # agent taking a turn, at the very path this verb already prints as the observe
        # address, so it costs one stat and answers the question the progress file was
        # standing in for. SILENT now means neither a written line nor a turn taken inside
        # the window, which is a state worth waking someone for.
        #
        # THE WINDOW is `PATROL_STALE_MULTIPLIER × cadence`, out of the library
        # (payload/scripts/lib/patrol.sh) rather than an inline `* 2` — one constant, three
        # readers, spec AC-22. It is more than one cadence because a row promising a line
        # every 10 minutes is, at any random instant, up to 10 minutes stale while perfectly
        # healthy; a threshold at the cadence itself would call half the live fleet SILENT.
        # Same slack hooks/dispatch-preflight.sh allows the Patrol stamp.
        LIVE=no
        if [ -n "$CAD_S" ]; then
          STALE_LIMIT=$(( CAD_S * PATROL_STALE_MULTIPLIER ))
          [ -n "$PROG_AGE" ] && [ "$PROG_AGE" -le "$STALE_LIMIT" ] && LIVE=yes
          [ -n "$TX_AGE" ] && [ "$TX_AGE" -le "$STALE_LIMIT" ] && LIVE=yes
        fi

        if [ -z "$RID" ]; then
          VERDICT=UNADDRESSABLE
        elif [ "$DELIV_PRESENT" = yes ]; then
          VERDICT=LANDED
        elif [ "$LIVE" = yes ]; then
          VERDICT=RUNNING
        else
          VERDICT=SILENT
        fi

        printf '%s|at=%s|session=%s|from=%s|name=%s|verdict=%s|agent_id=%s|address=%s|subagent_type=%s|deliverable=%s|deliverable_present=%s|progress=%s|progress_age=%s|cadence=%s|transcript=%s|transcript_present=%s|transcript_age=%s\n' \
          "$ADOPT_SCHEMA" "$(iso_now)" "$SESSION_ID" "$OSID" "$(clean "$RNAME")" "$VERDICT" \
          "$RID" "$ADOPT_ADDR" "$(clean "$RTYPE")" "$(clean "$RDELIV_ABS")" "$DELIV_PRESENT" \
          "$(clean "$RPROG_ABS")" "${PROG_AGE:-unknown}" "${CAD_S:-unknown}" \
          "$(clean "$TX")" "$TX_PRESENT" "${TX_AGE:-unknown}"

        # ---- the adoption itself, written before it is printed
        #
        # The row is what makes the address below TRUE: hooks/stop-guard.sh accepts
        # `<name>@session-<this session>` as an identity because THIS session's roster
        # records it, and resolves the agent at all because the row names the session it is
        # filed under. Printing the address without writing the row would hand the operator
        # a second line they cannot use.
        # THE WRITE'S ANSWER IS READ, because `die()` prints and RETURNS — it does not exit
        # (:156, and every other caller depends on that). A warning followed by the address
        # block below would hand the operator a `TaskStop` line that both stop gates refuse
        # as FOREIGN, since ownership is taken from the row that was just NOT written
        # (review-a C-3). So the row's own state decides which rendering it gets.
        #
        # `--report-only` TAKES THE SAME ROW AND DOES NOT FILE IT. The rendering below is
        # unchanged — same verdict, same addresses, same tail — because the whole point of
        # the flag is that the operator reads exactly what `adopt` would then write. The
        # stop address it prints is the address the write MAKES true, so it is printed as
        # the instruction it is: run `adopt`, and this line works. AC-4's "identical rows"
        # is pinned in tests/session-poker.test.sh §8i by comparing the two renderings.
        ROW_JOURNALLED=no
        if [ -n "$RID" ] && [ "$ADOPT_REPORT_ONLY" = yes ]; then
          ROW_JOURNALLED=yes
        elif [ -n "$RID" ]; then
          if adopt_write_row "$ADOPT_OWN_ROSTER" "$SESSION_ID" "$RNAME" "$RID" "$RTYPE" \
               "$RDELIV" "$RPROG" "$RCAD" "$RLAUNCH" "$OSID" "$ADOPT_ADDR"; then
            ROW_JOURNALLED=yes
          else
            die "WARN — this row could not be journalled to $ADOPT_OWN_ROSTER; the stop gate will not treat $RNAME as ours."
          fi
        fi

        say "$(clean "$RNAME") ($(clean "$RTYPE")) from session $OSID — $VERDICT"
        if [ -n "$RID" ] && [ "$ROW_JOURNALLED" = yes ]; then
          printf '  agent id    : %s\n' "$RID"
          printf '  observe     : %s (%s)\n' "$TX" \
            "$([ "$TX_PRESENT" = yes ] && echo 'on disk' || echo 'not on disk')"
          printf '  message     : SendMessage to:%s\n' "$RID"
          # THE ADDRESS THE PLATFORM ACCEPTS, not the one this verb happens to hold. The id
          # on the roster is the TRANSCRIPT form; the stop primitive takes
          # `<name>@session-<id8>` for a teammate and rejects the transcript form (capture
          # record/session-20260814-wave-detector-terminal-state/min/logs/A-p3.jsonl:9), so
          # printing the id cost the operator a refusal they could not clear.
          #
          # ONE SUFFIXED SPELLING, AND IT IS THE LAUNCHING SESSION'S (T3 FINDING 1). The
          # alternate — this session's eight — was printed here until a live `/clear` drive
          # refused it by name and the harness named the launching session's in its place.
          # See the construction above for what the row is read for.
          #
          # AND THE BARE NAME BENEATH IT, because it is the one address that survived every
          # step of that drive: it reached the stop wall before the `/clear` and after it,
          # and it is what finally stopped the adopted agent when the suffixed form did not
          # resolve. Neither stop gate keys on the suffix — each resolves on the base name
          # and takes ownership from the id on this session's roster
          # (tests/stop-guard.test.sh §14, tests/stop-check.test.sh §10(d)) — so offering
          # both costs the operator nothing and covers the case where the suffix is stale.
          printf '  stop        : TaskStop %s\n' "$ADOPT_ADDR"
          printf '                TaskStop %s — the bare name, the address that always survives\n' \
            "$(clean "$RNAME")"
        elif [ -n "$RID" ]; then
          # ADDRESSABLE FOR EVERYTHING BUT THE STOP. The id is real and the transcript and
          # the message address do not depend on this session's roster — only ownership
          # does, and that is precisely what the failed write cost. So the two true lines
          # are still printed and the one that would be false is replaced by its cause,
          # which is the UNADDRESSABLE shape below applied to the half that is missing.
          printf '  agent id    : %s\n' "$RID"
          printf '  observe     : %s (%s)\n' "$TX" \
            "$([ "$TX_PRESENT" = yes ] && echo 'on disk' || echo 'not on disk')"
          printf '  message     : SendMessage to:%s\n' "$RID"
          printf '  stop        : unavailable — this adoption was NOT journalled to\n'
          printf '                %s\n' "$ADOPT_OWN_ROSTER"
          printf '  cure        : both stop gates take ownership from THIS session'"'"'s roster, so\n'
          printf '                until that write lands every stop of %s is refused as\n' "$(clean "$RNAME")"
          printf '                FOREIGN. Clear that path — a symlink where the roster goes, or\n'
          printf '                a .bionic/tmp that is not a writable real directory — and re-run adopt.\n'
        else
          printf '  agent id    : (none — no identified row on that roster)\n'
          printf '  observe     : unavailable without an id\n'
          printf '  message     : unavailable without an id\n'
          printf '  stop        : unavailable without an id\n'
          printf '  cure        : the predecessor'"'"'s dispatch wall or execution recorder was dead when\n'
          printf '                this row was written — re-invoke /bionic:canonical-sdlc before\n'
          printf '                dispatching, or the same thing happens again.\n'
        fi
        printf '  launched    : %s\n' "${RLAUNCH:-unknown}"
        printf '  deliverable : %s (%s)\n' "${RDELIV_ABS:-none declared}" \
          "$([ "$DELIV_PRESENT" = yes ] && echo 'on disk' || echo 'not on disk')"
        printf '  progress    : %s (%s)\n' "${RPROG_ABS:-none declared}" \
          "$([ -n "$PROG_AGE" ] && printf '%ss old, cadence %ss' "$PROG_AGE" "${CAD_S:-unknown}" || echo 'not on disk')"
        if [ "$TX_PRESENT" = yes ]; then
          TAIL_TEXT="$(agent_report_tail "$TX")" || TAIL_TEXT=""
          if [ -n "$TAIL_TEXT" ]; then
            printf '  report tail (last long assistant block, capped at %s chars — quote it into\n' "$ADOPT_TAIL_CAP"
            printf '  the record before acting on it; a transcript is not an artifact):\n'
            printf '%s\n' "$TAIL_TEXT" | sed 's/^/    | /'
          fi
        fi
        printf '\n'
      done <<EOF
$ADOPT_OUT
EOF
    done

    printf '%s|at=%s|session=%s|scanned=%s|open=%s\n' \
      "$ADOPT_SCHEMA" "$(iso_now)" "$SESSION_ID" "$ADOPT_SESSIONS" "$ADOPT_ROWS"
    if [ "$ADOPT_ROWS" -eq 0 ]; then
      say "nothing to adopt — no other session has an open row on this project's rosters."
      exit 0
    fi
    say "$ADOPT_ROWS open row(s) from $ADOPT_SESSIONS predecessor session(s) — ledger every one BY AGENT ID before dispatching anything new."
    # ONE EXTRA LINE, and the rows above untouched: the mode is stated where it changes what
    # the reader should do next, not woven through a rendering that has to stay comparable.
    [ "$ADOPT_REPORT_ONLY" = yes ] \
      && say "report-only: nothing was written — run 'adopt' to take these rows onto this session's roster."
    exit 1
    ;;

  tick)
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "A tick answers for ONE session's roster, so without the key there is nothing to read."
      exit 3
    fi

    # THE WALK, TAKEN BEFORE THE STAMP IS WRITTEN, and that ordering is load-bearing.
    # `write_patrol_stamp` mkdir -p's `<resolved root>/.bionic/tmp`, so a tick that resolved
    # the WRONG root creates a `.bionic` there as its first act — and every walk taken after
    # that point reports the root it just manufactured as `chosen`. Read here, the walk still
    # describes the filesystem the tick actually arrived in, which is the only version of it
    # an operator can act on and the one AC-38's two arms are told apart by.
    TICK_ROOT_WALK="$(project_root_candidates "$PWD")"
    TICK_ROOT_TAG="$(printf '%s\n' "$TICK_ROOT_WALK" | tail -1 | awk -F'\t' '{ print $2 }')"

    # STAMP FIRST, BEFORE ANYTHING IS READ OR DECIDED. Every line below this one can end in
    # a refusal, and each of those refusals is a HEALTHY Patrol firing into a state it has
    # nothing to say about. What the stamp attests is the firing, so it is taken here — the
    # first thing after the session key exists to name the file with.
    write_patrol_stamp "$SESSION_ID" tick \
      || die "WARN — the Patrol stamp could not be written; the tick itself is unaffected."

    # The sweeper is this script's sibling — same resolution as hooks/landing-gate.sh's.
    SWEEPER="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/session-sweeper.sh"
    if [ ! -f "$SWEEPER" ]; then
      die "REFUSED — sibling hooks/session-sweeper.sh not found; nothing was read."
      exit 2
    fi

    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    ROSTER_FILE="$REPO_REAL/.bionic/tmp/roster-${SESSION_ID}.state"

    # THE BLIND-WALL CHECK IS GONE (bionic 1.4.0, spec AC-7). It compared main-thread
    # `Agent` tool_uses in the transcript against rows on the roster and raised a NOTIFY
    # when dispatches outnumbered them, on the reasoning that the dispatch wall lived in
    # the governing skill's frontmatter and therefore died with a `/clear`, a continue or
    # a `/reload-plugins`. Every wall is registered in hooks/hooks.json now and survives
    # all three, so the condition it detected cannot arise the way it did — while its
    # false positive could and did: the check had no "no active run" branch, so a session
    # that had simply not engaged a run read as a session whose wall had died (observed
    # 20:07Z, 2026-09-02). A diagnosis for a failure mode the registration change removes,
    # firing on sessions that have nothing wrong with them, is worth less than nothing.

    # EXACTLY ONE verdict read over the whole roster (no name argument), run from the repo
    # root exactly as landing-gate.sh runs it. `|| exit 9` keeps a failed `cd` out of the
    # exit-1 band, which is NOTIFY's alone.
    VERDICT_OUT=$( cd "$REPO_REAL" 2>/dev/null || exit 9
                   CLAUDE_CODE_SESSION_ID="$SESSION_ID" bash "$SWEEPER" verdict 2>&1 )
    VERDICT_RC=$?
    if [ "$VERDICT_RC" -eq 9 ]; then
      die "REFUSED — could not enter $REPO_REAL to read the roster."
      exit 2
    fi
    # 2 (a refusal the sweeper itself raised — a symlinked roster or ledger) and 3 (no
    # session key, unreachable here since SESSION_ID was already checked) propagate
    # verbatim: a tick that cannot trust its one read has nothing to decide from.
    if [ "$VERDICT_RC" -eq 2 ] || [ "$VERDICT_RC" -eq 3 ]; then
      die "REFUSED — the verdict read did not complete: $VERDICT_OUT"
      exit "$VERDICT_RC"
    fi

    TOTAL=0; OPEN=0; NOTIFY_ROWS=""; NOTIFY_DETAIL=""
    while IFS= read -r LINE; do
      case "$LINE" in "landing-verdict/v1|"*) : ;; *) continue ;; esac
      TOTAL=$((TOTAL + 1))
      RNAME="$(line_field "$LINE" name)"
      RSTATE="$(line_field "$LINE" state)"

      # THE ACK CLOSES THE ROW HERE TOO, before the state is looked at at all: excluded from
      # OPEN and therefore from DISARM's precondition, and excluded from NOTIFY eligibility.
      # Read per row off the verdict line this loop is already walking — never from the
      # ledger, whose one owner is the verb that prints this line (hooks/session-sweeper.sh,
      # S9) — and spelled exactly as the three consumers that already read it:
      # hooks/landing-gate.sh:214, hooks/stop-orders.sh:319, hooks/stop-guard.sh:491.
      # This is what makes the ack verb's own closing sentence true —
      #   hooks/session-sweeper.sh:817 "an acked row is closed for every reader"
      # — which it was not while this script was the fourth reader that ignored the field
      # (cs review C-4, epic-16 w2 Step-6 remediation R4). Two structural consequences were
      # riding on the omission, both worse than the noise: an acked-UNMET row is never MET
      # and never WAIVED, and its artifact was accounted for by a human rather than written
      # to disk, so it held OPEN above zero PERMANENTLY and DISARM — the end of the
      # self-wake — was unreachable by the ordinary path that closes an artifact-less row;
      # and every tick re-notified the same closed work, growing the NOTIFY set
      # monotonically across a wave. AC-7's contract moves with this (assumption 41), which
      # is why tests/session-poker.test.sh §3 re-authors the accelerated-clock cases rather
      # than re-running them.
      #
      # TOTAL still counts an acked row: it is on the roster, and "how many contracts does
      # this session carry" is not the question the ack answers. Only `open=` moves.
      [ "$(line_field "$LINE" acked)" = "yes" ] && continue

      case "$RSTATE" in
        MET|WAIVED) : ;;                      # closed — not open
        *)          OPEN=$((OPEN + 1)) ;;      # STILL-LIVE, UNMET, AMBIGUOUS — open
      esac
      [ "$RSTATE" = "UNMET" ] || continue

      # Duration is a SECOND, ADVISORY-ONLY read of this one row — never a re-judgment of
      # MET/UNMET, which stays verdict's alone. The roster is append-only; the last line
      # carrying this name is its latest contract, the same row verdict itself just folded.
      # Filtered to the roster-state/v1 schema FIRST (t6-review.md F-1): a landing-swept/v1
      # marker for this same name also carries `|name=<name>|` and is appended AFTER the
      # roster rows, so an unfiltered `tail -1` takes the marker instead — it has no
      # duration=/launched_at=, and the row's overdue NOTIFY goes silent for the rest of the
      # session. Same schema-prefix discipline as every other roster reader in the fleet
      # (e.g. hooks/execution-recorder.sh's `roster-state/${ROSTER_VERSION}|` filters).
      ROW_LINE="$(grep -F "roster-state/v1|" "$ROSTER_FILE" 2>/dev/null \
        | grep -F "|name=${RNAME}|" | tail -1)"
      [ -n "$ROW_LINE" ] || continue
      DUR_RAW="$(line_field "$ROW_LINE" duration)"
      LAUNCHED_RAW="$(line_field "$ROW_LINE" launched_at)"
      DUR_S="$(parse_seconds "$DUR_RAW")" || continue
      LE="$(iso_epoch "$LAUNCHED_RAW")"
      [ -n "$LE" ] || continue
      AGE=$(( $(now_epoch) - LE ))
      [ "$AGE" -gt "$DUR_S" ] || continue
      NOTIFY_ROWS="${NOTIFY_ROWS}${NOTIFY_ROWS:+,}$(clean "$RNAME")"
      NOTIFY_DETAIL="${NOTIFY_DETAIL}${NOTIFY_DETAIL:+; }$(clean "$RNAME"): $(line_field "$LINE" detail) (elapsed ${AGE}s past declared duration \"$DUR_RAW\" (${DUR_S}s))"
    done <<EOF
$VERDICT_OUT
EOF

    # "No roster" and "empty roster" are different facts, and only the latter may DISARM
    # (ap review A-1, item 2). A roster with zero verdict lines because the file plain does
    # not exist is indistinguishable, from the arithmetic alone, from a roster that exists
    # and legitimately has nothing open yet — but the first case is usually the wrong project
    # root having been resolved, and DISARM is silent and terminal for the rest of the
    # session (doctrine, skills/canonical-sdlc/SKILL.md §Dispatch: "DISARM also ends the
    # Patrol"). Checked only on the TOTAL=0 path: any row at all on the roster proves the
    # file exists, so OPEN=0-with-TOTAL>0 can never be the absent-file case.
    if [ "$TOTAL" -eq 0 ] && [ ! -e "$ROSTER_FILE" ]; then
      # AC-38 (fold-in ratified 2026-09-03): THE ARM SPLITS. "No roster" was one refusal
      # covering two states that deserve opposite answers, and the wrong one was observed on
      # this wave's own Patrol tick #1 — an orchestrator that had armed at engagement, was
      # standing in the right project, and had simply not dispatched anything yet got
      # REFUSED with a wall of candidate paths describing a root that was perfectly correct.
      # Arming precedes dispatch by design (SKILL.md §Dispatch: "arm at engagement"), so the
      # first tick of every run reaches this line, and answering it with a refusal teaches
      # the reader to ignore the one message that also reports a mis-resolved root.
      #
      # THE TWO STATES, and the fact that tells them apart:
      #   armed here, and the walk CHOSE a real `.bionic`  -> QUIET. The Patrol is doing its
      #     job; there is simply nothing on the roster yet. Exit 0, stamp kept (it was
      #     written above), one line, and no candidate walk — the root is not in doubt.
      #   anything else                                     -> the refusal below, unchanged.
      #
      # THE ARMING RECORD IS THE LOAD-BEARING HALF. It is written only by `arm`, and its
      # path is resolved against the SAME root the roster's is, so a tick that resolved the
      # wrong root finds no arming record there either and refuses — which is exactly the
      # failure the refusal exists to report. The root tag is the second guard, and it is
      # read off the walk taken ABOVE the stamp write for the reason given there.
      TICK_ARMED="$(patrol_armed_file "$SESSION_ID")" || TICK_ARMED=""
      if [ -n "$TICK_ARMED" ] && [ -f "$TICK_ARMED" ] && [ ! -L "$TICK_ARMED" ] \
         && [ "$TICK_ROOT_TAG" = "chosen" ]; then
        printf '%s|at=%s|session=%s|decision=QUIET|total=%s|open=%s\n' \
          "$POKER_DECISION_SCHEMA" "$(iso_now)" "$SESSION_ID" "$TOTAL" "$OPEN"
        say "QUIET — armed, nothing dispatched yet on this session"
        exit 0
      fi
      die "REFUSED — no roster at $ROSTER_FILE; this is not the same as an empty one."
      die "An armed session with nothing dispatched yet is QUIET, and was answered above — so"
      die "reaching this line means the Patrol never armed here, or the wrong project root was"
      die "resolved. Either way nothing was read to decide DISARM from, and DISARM ends the"
      die "Patrol for the rest of this session."
      # THE WALK, SHOWN (2.4, AC-13). The sentence above names the likely cause and then
      # leaves the reader with the one question they cannot answer from a message: WHICH
      # ancestor was taken, and what was passed over to get there. That answer is a property
      # of the filesystem above their cwd, so it is printed rather than described —
      # `project_root_candidates` is the same walk `project_root` just took, one line per
      # ancestor with the reason it was rejected, and the chosen one marked. A phantom
      # `.bionic` nested under a project, a symlinked one, a `.bionic` that only exists
      # inside $HOME: each shows up as its own line with its own tag.
      die "The root came from this walk over the ancestors of $PWD (path, then verdict):"
      printf '%s\n' "$TICK_ROOT_WALK" | while IFS= read -r ROOT_CAND; do
        die "  $ROOT_CAND"
      done
      exit 2
    fi

    # THE RUN-STATE READ, taken only where it can change the answer. `TOTAL == 0` implies
    # `OPEN == 0` — the loop that raises OPEN is the loop that raises TOTAL — so this single
    # test covers both arms of the old predicate, and a roster with open work never pays for
    # a find over the docs tree.
    RUN_STATE=open
    RUN_STATE_WHY="the roster still carries open work"
    if [ "$OPEN" -eq 0 ]; then
      RUN_STATE_RAW="$(run_state "$REPO_REAL" "$(patrol_armed_file "$SESSION_ID")")"
      RUN_STATE="${RUN_STATE_RAW%%|*}"
      RUN_STATE_WHY="${RUN_STATE_RAW#*|}"
    fi

    # DISARM — no open row AND a run that says it is delivered, in a delivery that POSTDATES
    # this Patrol's arming (R-13: an older one is the previous run's close-out, still newest
    # while the new run's plan does not exist yet). "No open row" alone was the whole
    # predicate until 1.3.2, and it is also exactly what a live wave looks like between two
    # batches: every writer of a slice landed, the next not yet briefed. The tick ended the
    # Patrol there, terminally, and the rest of the wave ran unsupervised (epic-20 W1
    # dogfood, idea §B-4; R-4, AC-13/AC-14). The first conjunct still generalizes the spec's
    # literal "disarmed on empty roster" to a roster whose every row is MET/WAIVED/acked (S2
    # design decision, logged to the plan); the second is what tells a finish from a lull.
    #
    # An empty roster on a run that has not delivered falls through to QUIET below, and QUIET
    # KEEPS THE STAMP — which is the half that matters on disk. The clock keeps running, the
    # arming wall stays satisfied, and hooks/patrol-revive.sh has nothing to report.
    if [ "$OPEN" -eq 0 ] && [ "$RUN_STATE" = delivered ]; then
      printf '%s|at=%s|session=%s|decision=DISARM|total=%s|open=%s\n' \
        "$POKER_DECISION_SCHEMA" "$(iso_now)" "$SESSION_ID" "$TOTAL" "$OPEN"
      say "DISARM — no open row on this roster and the run is delivered (${RUN_STATE_WHY}); the Patrol may stop."
      # THE LAST ACT OF A DISARM TICK. The decision is terminal — "the Patrol may stop" —
      # so the stamp this very tick wrote before it decided has to stop claiming a live
      # clock, or hooks/patrol-revive.sh reads the stop this line just chose as a death and
      # blocks every remaining turn of the session demanding a re-arm nobody wants (critic
      # C-2, epic-19 w1). It is LAST so that nothing above it can be skipped by it: the
      # decision line is already printed, and a removal that fails costs a late notice
      # rather than a lost decision.
      remove_patrol_stamp "$SESSION_ID" \
        || die "WARN — the Patrol stamp could not be removed; the death notice may fire on later turns."
      exit 0
    fi

    # ─────────────────────────────────────── the scheduler: pressure, then fills
    #
    # PLACED HERE, after DISARM and before NOTIFY/QUIET, and the placement is the contract.
    # DISARM exits above: a run that has DELIVERED gets no fills, because there is nothing
    # left to fill. Everything else — a live wave, a lull between batches, a roster with an
    # overdue row — gets both the pressure reading and the fill decision, and then the
    # decision line it was already going to get. A tick that filled instead of notifying
    # would trade a report the operator asked for against one they did not.
    #
    # PRESSURE FIRST, ALWAYS. See the block comment above `space_field` for why the order is
    # not negotiable and why nothing here re-derives the budget.
    SCHED_CORES="$(space_field "$(resources_probe)" cores)"
    case "${SCHED_CORES:-}" in ''|*[!0-9]*) SCHED_CORES=1 ;; esac
    [ "$SCHED_CORES" -ge 1 ] || SCHED_CORES=1
    SCHED_PRESSURE="$(resources_pressure "$SCHED_CORES" 2>/dev/null)" || SCHED_PRESSURE=""
    SCHED_STATE="$(space_field "$SCHED_PRESSURE" state)"
    SCHED_FREE="$(space_field "$SCHED_PRESSURE" free_mb)"
    SCHED_LOAD="$(space_field "$SCHED_PRESSURE" load_1m)"
    # A pressure read that will not parse is not an emergency and not a hold: it is a
    # reading this tick does not have, and the fill decision proceeds on the budget alone.
    # Refusing to fill on an unreadable probe would let one broken `vm_stat` stall a wave.
    case "${SCHED_STATE:-}" in ok|hold|emergency) : ;; *) SCHED_STATE=ok ;; esac

    # The plan and its budget, read once. Both may be absent — a project with no plan, or a
    # plan written before Step 0 ever probed — and absence is INERT: the tick says why it is
    # not filling and fills nothing, exactly as the dispatch wall's budget arm goes inert on
    # the same missing line. A budget is a ceiling a run opts into.
    SCHED_PLAN="$(active_plan "$REPO_REAL")" || SCHED_PLAN=""
    SCHED_BUDGET=""
    [ -n "$SCHED_PLAN" ] && SCHED_BUDGET="$(plan_budget_line "$SCHED_PLAN")"
    SCHED_WRITERS="$(budget_int "$SCHED_BUDGET" writers)"
    SCHED_JOBS="$(budget_int "$SCHED_BUDGET" test_jobs)"

    if [ "$SCHED_STATE" = emergency ]; then
      # THE KILL FLOOR. The tick NAMES the writer and stops nothing itself: stopping a
      # writer destroys work, and an irreversible act taken by a hook off a single reading
      # is the one thing this design refuses (design-ledger S7). The orchestrator executes
      # it through the stopping standard, which is why the line carries the address that
      # standard takes rather than a name.
      SCHED_TARGET="$(youngest_suite_writer "$ROSTER_FILE" "$SESSION_ID")"
      if [ -n "$SCHED_TARGET" ]; then
        say "EMERGENCY free_mb=${SCHED_FREE} — stop youngest suite-running writer ${SCHED_TARGET}"
      else
        say "EMERGENCY free_mb=${SCHED_FREE} — no suite-running writer on this roster to stop; the pressure is not this session's to relieve"
      fi
    fi

    if [ "$SCHED_STATE" = hold ] || [ "$SCHED_STATE" = emergency ]; then
      SCHED_HOLDS=$(( $(read_holds "$SESSION_ID") + 1 ))
      write_holds "$SESSION_ID" "$SCHED_HOLDS" \
        || die "WARN — the hold counter could not be written; NARROW will not fire on the next tick."
      [ "$SCHED_STATE" = hold ] && \
        say "HOLD free_mb=${SCHED_FREE} load_1m=${SCHED_LOAD} — no fills"
      # NARROW ON THE SECOND CONSECUTIVE HOLD, and on every one after it. One hold is a
      # burst — a suite starting, a build finishing — and halving the fleet's width off a
      # burst is a wave that runs at half speed for the rest of the day. A hold that
      # survives a whole interval is sustained, and that is what the counter measures.
      #
      # THE HALVING IS A RECOMMENDATION, not an edit. `test_jobs` lives in the plan header
      # and the orchestrator owns that line; a tick that wrote it would be a controller.
      # Floored at 1 because a width of zero is not a width.
      if [ "$SCHED_HOLDS" -ge 2 ] && [ -n "$SCHED_JOBS" ]; then
        SCHED_HALF=$(( SCHED_JOBS / 2 ))
        [ "$SCHED_HALF" -ge 1 ] || SCHED_HALF=1
        say "NARROW test_jobs=${SCHED_HALF}"
      fi
    else
      # OK CLEARS THE COUNTER, so "two consecutive" means consecutive. A counter that only
      # ever rose would make NARROW inevitable on a long enough wave.
      [ "$(read_holds "$SESSION_ID")" = "0" ] || write_holds "$SESSION_ID" 0 || :

      # ── FILL. gap = writers − RUNNING, ready = pending slices whose deps all landed.
      #
      # RUNNING IS `open` (WALLS/2): the rows already counted above, on THIS session's
      # roster — a `status=intended` row with no `landing-swept/v1` marker and no ack. It is
      # the loop's own count rather than a second walk, because two definitions of "running"
      # in one file is the drift the count exists to prevent.
      if [ -z "$SCHED_WRITERS" ]; then
        if [ -z "$SCHED_PLAN" ]; then
          say "no FILL — no plan carrying an unfenced \"## SDLC State\" to read a budget or a slice table from."
        else
          say "no FILL — ${SCHED_PLAN} carries no readable parallel-budget: writers field in its frontmatter; a budget is a ceiling a run opts into."
        fi
      else
        SCHED_GAP=$(( SCHED_WRITERS - OPEN ))
        [ "$SCHED_GAP" -lt 0 ] && SCHED_GAP=0
        if [ "$SCHED_GAP" -eq 0 ]; then
          say "no FILL — writers=${SCHED_WRITERS} and ${OPEN} open row(s): the budget is full."
        else
          SCHED_READY="$(slice_ready "$(slice_table "$SCHED_PLAN")")"
          SCHED_IDS=""; SCHED_N=0
          while IFS= read -r SLICE_ID; do
            [ -n "$SLICE_ID" ] || continue
            [ "$SCHED_N" -lt "$SCHED_GAP" ] || break
            SCHED_IDS="${SCHED_IDS}${SCHED_IDS:+ }$(clean "$SLICE_ID")"
            SCHED_N=$((SCHED_N + 1))
          done <<EOF
$SCHED_READY
EOF
          if [ "$SCHED_N" -gt 0 ]; then
            say "FILL ${SCHED_IDS}"
          else
            say "no FILL — writers=${SCHED_WRITERS} open=${OPEN} gap=${SCHED_GAP}, and no pending slice has all its dependencies landed."
          fi
        fi
      fi
    fi

    if [ -n "$NOTIFY_ROWS" ]; then
      printf '%s|at=%s|session=%s|decision=NOTIFY|total=%s|open=%s|rows=%s|detail=%s\n' \
        "$POKER_DECISION_SCHEMA" "$(iso_now)" "$SESSION_ID" "$TOTAL" "$OPEN" \
        "$NOTIFY_ROWS" "$(clean "$NOTIFY_DETAIL")"
      say "NOTIFY — past declared duration: $NOTIFY_DETAIL"
      exit 1
    fi

    printf '%s|at=%s|session=%s|decision=QUIET|total=%s|open=%s\n' \
      "$POKER_DECISION_SCHEMA" "$(iso_now)" "$SESSION_ID" "$TOTAL" "$OPEN"
    # THE QUIET LINE HAS TWO READINGS NOW, and printing the wrong one is how this fix would
    # be mistaken for the bug it repairs. "0 open row(s), none past their declared duration"
    # over a mid-run lull says nothing about why the Patrol did not stop, and its reader is a
    # model deciding whether the Patrol is broken. So the empty-roster reading names the run
    # state it decided from — which plan, and where that plan says the run is.
    if [ "$OPEN" -eq 0 ]; then
      say "QUIET — no open row on this roster, but the run is not delivered (${RUN_STATE_WHY}); the Patrol keeps its stamp and its clock."
    else
      say "QUIET — $OPEN open row(s) on this roster, none past their declared duration."
    fi
    exit 0
    ;;
esac
