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
#     bash <plugin-root>/hooks/session-poker.sh sweep      delete what DEAD sessions left here (writes, deletes)
#     bash <plugin-root>/hooks/session-poker.sh task-add … add a ## Tasks row to the bound plan, as a transaction (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh amend …    widen a live row's Files/Suites/Re-executes (writes the roster)
#     bash <plugin-root>/hooks/session-poker.sh task-set | step-line | current | ledger-add | ledger-set …
#                                                      the plan-row verbs, each the task-add transaction (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh proof-add <kind> <evidence>   a proof line naming the head its evidence read (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh proof-add review <record> --question <q> --reader <name>   a reading: that proof line with its question, reader, result and scope
#     bash <plugin-root>/hooks/session-poker.sh waive <question> '<reply>'   the user's waiver of a reading question at the working head (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh release-check   run the project's declared release check over the release range; its log and its check fact, failing or not (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh finding-stated <record>#<n> '<sentence>'   store a deferred finding's one changelog sentence on its deferred: line (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh share [<n>]   print the machine's share of its own resources, or set it to <n>, 1 to 100 (the set writes the user-level share file)
#     bash <plugin-root>/hooks/session-poker.sh finding-check <record>#<n> <settled <S> <reach>|refuted|unsettled> <check record>   settle a check a finding owes, on its check: line (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh finding-move <record>#<n> <defer|fix> '<the user's words>' '<why>'   move a finding across the line on words the user typed in this session (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh prompt     the canonical Patrol prompt for this session's CronCreate (read-only)
#     bash <plugin-root>/hooks/session-poker.sh fill-report [<plan>]   the run's missed-opportunity, HOLD and decline minutes (read-only)
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
# `bind` IS THE ONE VERB THIS TABLE DOES NOT DESCRIBE, and it is listed rather than left to
# be inferred (review readability F6). It answers about a WRITE, not about a roster, so its
# 1 is a refusal and not a NOTIFY:
#   0 — bound, or NOT-ENGAGED (nothing decided, and that is not a fault)
#   1 — REFUSED: the operand is not a member of this root's open-run set
#   2 — the marker write failed, or a usage error (this file's one argument-error code)
#   3 — no session key, exactly as above
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
BIONIC_LIB_WANT="root.sh session.sh run.sh binding.sh patrol.sh resources.sh worktree.sh agents.sh roster.sh units.sh fill.sh observe.sh refuse.sh"
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
[ -n "$BIONIC_LIB" ] || loader_fail_open "session-poker"
. "$BIONIC_LIB/root.sh"
. "$BIONIC_LIB/session.sh"
. "$BIONIC_LIB/run.sh"
. "$BIONIC_LIB/binding.sh"
. "$BIONIC_LIB/patrol.sh"
. "$BIONIC_LIB/resources.sh"
. "$BIONIC_LIB/worktree.sh"
. "$BIONIC_LIB/agents.sh"
# `adopt` writes a `roster-state/v1` row, and `roster_row` is the one writer of that
# shape — the same function hooks/dispatch-preflight.sh calls (spec AC-25, ledger D3).
. "$BIONIC_LIB/roster.sh"
# THE ONE READER OF `## Tasks` (REQ-1e, spec §2 D3). The FILL arm takes its ready set
# from here; this hook parses no plan table of its own.
# shellcheck source=/dev/null
. "$BIONIC_LIB/units.sh"
# THE ONE COMPUTATION OF READINESS (wave-18 REQ-3, D2; ADR-033 decision 2). The FILL arm
# below asks `fill_ready_set` for the ids and `fill_step_token` for the step it asks them at,
# and `fill_name` — which lived in this file — moved there with them. What that buys is a
# SECOND reader: `payload/scripts/lib/stop.sh`'s fill duty computes the same set at the end
# of every turn, so a turn that ends with rows ready is refused whether or not a tick fired
# in it, and the two can never name different rows.
# shellcheck source=/dev/null
. "$BIONIC_LIB/fill.sh"
# THE GATE (wave-28 T13; D14, AC-2.8): `gate_room` is the one answer on width, asked once per
# ready row (`fill_gate_width`, lib/fill.sh), and `gate_state` gives the tick its gate line.
# Sourced softly, beside the want-list rather than in it: a hook copied outside the repo
# resolves its libraries from a checkout that may not carry gate.sh yet, and the tick then says
# the gate is unreadable and offers nothing, rather than failing to load at all.
if ! declare -F gate_room >/dev/null 2>&1 && [ -f "$BIONIC_LIB/gate.sh" ]; then
  # shellcheck source=/dev/null
  . "$BIONIC_LIB/gate.sh"
fi
# THE ONE PREDICATE FOR "TOO QUIET" (REQ-10 AC-10.1, D9; ADR-028). `observe_class` classifies
# a dispatched row `delivered`/`alive`/`idle` from two mtimes against the cadence the row's
# own brief declared. Both readers in this file — the tick's row loop and `adopt`'s liveness
# verdict — ask it, so the fleet holds two staleness arithmetics (a stamp against its fire
# window, a row against its cadence) where it held four: this verb used to multiply a cadence
# by a second multiplier of its own and the tick measured no cadence at all.
#
# THIS FILE'S OWN `file_mtime`, `line_field` and `parse_seconds` are defined BELOW this line
# and are CODE-IDENTICAL to the library's (tests/cross-gate-agreement.test.sh §C and §O hold
# all three copies together), so the redefinitions that follow change nothing either caller
# reads.
# shellcheck source=/dev/null
. "$BIONIC_LIB/observe.sh"
# THE PASTED POKER PATH (wave-24 T29; critic I2, A-T27.8). The Patrol prompt, the STANDDOWN
# line and the re-arm note print this script's path for a reader to paste; it is ONE shell
# word, so a plugin root with a space pastes whole. refuse.sh's `refuse_shell_word` owns the rule.
# shellcheck source=/dev/null
. "$BIONIC_LIB/refuse.sh"
POKER_WORD="$(refuse_shell_word "${HOOK_DIR}/session-poker.sh")"

POKER_DECISION_SCHEMA="poker-tick/v1"
POKER_INTERVAL_DEFAULT="20m"

# THE SHARED CONSTANT (S15, AC-26; research-code-map §2.c). hooks/landing-gate.sh is the one
# ORIGINATOR of this marker — its own `swept_marker_write` owns the printf — and this file's
# `adopt_copy_marker` (below) is the second appender, but it only ever RELAYS a line the
# originator already wrote; it never computes one. Before this wave `adopt_copy_marker`
# spelled the schema as a bare literal inside its own grep pattern rather than through a
# named constant, which is exactly the shape research-code-map §2.c calls out as a hazard:
# "the grep that finds both writers is `grep -rn 'landing-swept/v1' hooks/*.sh` — a
# derivation that greps for the constant NAME misses the literal spelling". Both files now
# carry a `SWEPT_SCHEMA=` line naming it, byte-identical, pinned in
# tests/cross-gate-agreement.test.sh so the two spellings cannot drift apart unnoticed — the
# same duplicated-but-pinned shape payload/scripts/lib/loader.sh's own block uses, for the
# same reason: two separate hook processes have no shared memory to source a single
# in-process constant from.
SWEPT_SCHEMA="landing-swept/v1"

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

# THE TICK DIGEST AND THE PROMPT VERSION (wave-24 T7, REQ-4; D4, D5; ADR-041). The digest file
# holds what one tick carries to the next: a hash of what the tick decided (no timestamp enters
# it), when that answer was first given, the decision band, whether the turn owes the task-list
# duty (`duty=owed|none`, read by the stop wall's collector), and the Patrol prompt version
# `arm` recorded. A tick whose hash matches the file's prints one line. The prompt version is
# bumped whenever the prompt's wording changes what a tick turn is asked to do, so a Patrol armed
# under an older one is told to re-arm.
PATROL_DIGEST_SCHEMA="patrol-digest/v1"
# THE HOLD'S REASON, AS EVERY FIX LINE PRINTS IT (wave-24 T27; critic I4): a quoted
# placeholder, so a line pasted as printed is one argument and never a redirect from a file
# named `reason`. The stop wall's stand-down refusal prints the same words
# (payload/scripts/lib/stop.sh `STANDDOWN_HOLDS`); tests/session-poker.test.sh §HOLD-fix pins
# the three sites.
HOLD_REASON_SLOT="'why it stays up'"
# THE DECLINE'S REASON, the same kind of placeholder (wave-27 T34; D24): the prompt's FILL answer and
# the turn-end wall's refusal (payload/scripts/lib/stop.sh) print it in the decline command.
DECLINE_REASON_SLOT="'why they wait'"
# v=3 (wave-25 T5; D7): the prompt says what the decision line's `gate=` field asks of the turn,
# so a Patrol armed under v=2 does not know it and the tick's re-arm note asks for the new job.
# v=4 (wave-26 T15; D16): an `unchanged` or a WAITING tick ends the turn's duties, the task-list
# refresh is asked only on a change, and "continue" only when something is ready or changed.
# v=5 (wave-26 T32; review-6 F2): the refresh is asked only when the tick printed its RECONCILE
# line, which it prints whenever the duty is owed (v=4 asked on a change the tick never printed),
# and a FILL asks for the dispatch alone: the launch records the row and its ledger line.
# v=6 (wave-27 T34; REQ-15, D24): a FILL left unfilled is answered by the `decline` verb, which records
# the decline on disk, and no longer by a `fill-declined:` line in the reply the user reads.
PATROL_PROMPT_VERSION=6

# THE SCHEDULER KEEPS NO STATE ACROSS TICKS (S8). There used to be a third sibling of the
# stamp here — a `.holds` counter of consecutive holds, the one fact the tick carried from
# one firing to the next, and the input to a halve-the-width recommendation that fired on
# the second of them. Both are gone. Width is read at the gate at the moment of use
# (`gate_room`, lib/gate.sh; wave-28 T13, D14): the load over the last minute and the last
# five, plus the work promised and not yet showing, against the machine's share — and a fact
# nobody stores is a fact that cannot go stale. What the tick owes the operator is therefore a
# REPORT of the gate, printed every tick, not advice to act on.

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

# ONE EXIT CODE FOR EVERY ARGUMENT ERROR IN THIS FILE, AND IT IS 2. `bind` briefly had a 3
# of its own (wave-session-bound-run S6, on the reading that a missing operand is the same
# class as the missing session key the verb refuses ten lines on). It is not: the session key
# is an ENVIRONMENT fact the caller cannot type, and 3 is what this file says about the
# environment; an operand the caller left off the command line is a usage error like every
# other usage error here, and one verb spelling it differently is a surface the operator has
# to learn per verb. Reverted at S8 with the `USAGE_EXIT` indirection deleted with it —
# tests/session-poker.test.sh 16g asserts the 2.
usage() {  # [message]
  [ $# -gt 0 ] && die "$1"
  die "Usage:"
  die "  bash ${HOOK_DIR}/session-poker.sh tick       one decision over this session's roster (read-only)"
  die "  bash ${HOOK_DIR}/session-poker.sh arm        stamp the Patrol as alive for this session (no roster needed)"
  die "  bash ${HOOK_DIR}/session-poker.sh disarm     remove that stamp at run close — this Patrol was ended on purpose"
  die "  bash ${HOOK_DIR}/session-poker.sh interval    the configured Patrol interval, in seconds"
  die "  bash ${HOOK_DIR}/session-poker.sh interval-default   this script's built-in default interval, in seconds (ignores config)"
  die "  bash ${HOOK_DIR}/session-poker.sh share [<n>]   print the machine's share, 1 to 100 (80 when none is set); with <n>, set it: one integer in the user-level share file the gate reads"
  die "  bash ${HOOK_DIR}/session-poker.sh window     the instant this session's roster begins, UTC ISO-8601 (empty when it cannot be dated)"
  die "  bash ${HOOK_DIR}/session-poker.sh adopt      every open row a PREDECESSOR session left on this project's rosters"
  die "  bash ${HOOK_DIR}/session-poker.sh adopt --report-only   the same rows, with the adoption itself not taken (writes nothing)"
  die "  bash ${HOOK_DIR}/session-poker.sh sweep      delete every DEAD session's leftover state under this project's .bionic/tmp"
  die "  bash ${HOOK_DIR}/session-poker.sh sweep --report-only   the same files, listed, with nothing deleted"
  die "  bash ${HOOK_DIR}/session-poker.sh sweep --window   defer a dead session whose own newest file is younger than the poker interval"
  die "  bash ${HOOK_DIR}/session-poker.sh bind <plan>   name the open run this session is working (rewrites its binding)"
  die "  bash ${HOOK_DIR}/session-poker.sh extend <name> <reason>   re-open a MET row for <name>: a fresh row goes on the roster, launched now, so the next tick reads it live again"
  die "  bash ${HOOK_DIR}/session-poker.sh hold <name> <reason>   answer a STANDDOWN by keeping <name> up: the tick prints it held, and orders no stop, until its launch, deliverable or messages change"
  die "  bash ${HOOK_DIR}/session-poker.sh decline <id>[,<id>] '<reason>'   answer a FILL by recording why those ready rows wait: one line in the run's fill ledger, standing until a row it did not name is ready"
  die "  bash ${HOOK_DIR}/session-poker.sh budget writers=<n> '<reply>'   record the user's cap on writers in the plan header (source=user, budget-override:)"
  die "  bash ${HOOK_DIR}/session-poker.sh task-add <id> <step> <kind> <task> <agent> <deps> <size> <serves> <Files> [<reads>]   add a ## Tasks row to the bound plan as a transaction: validated and dry-committed on a copy, then swapped in; <reads> fills a reads column (— for the default of its kind)"
  die "  bash ${HOOK_DIR}/session-poker.sh amend <name> [--files+ <path>]... [--suites+ <suite>]... [--reexec+ '<cmd>']... --reason <why>   widen a live row's contract: a successor row, judged by the dispatch grammar"
  die "  bash ${HOOK_DIR}/session-poker.sh task-set <id> <col>=<val>...   set cells of a ## Tasks row (any header column but Files, which amend widens)"
  die "  bash ${HOOK_DIR}/session-poker.sh step-line <N|T<n>> <text> [--append]   write a - Step N: or - T<n>: line under ## SDLC State"
  die "  bash ${HOOK_DIR}/session-poker.sh current <N|T<n>>   move current: (9 is close-out's); advancing to 4 fills the Step-4 block's worktree/base-sha/branch"
  die "  bash ${HOOK_DIR}/session-poker.sh approve <name> '<reply>'   record the user's approval <name> as an approved: line under ## SDLC State (the plan's own is approved-by:, written at Step 3)"
  die "  bash ${HOOK_DIR}/session-poker.sh ledger-add <id> <col>=<val>...   add a ## Dispatch ledger row (cells not named are —)"
  die "  bash ${HOOK_DIR}/session-poker.sh ledger-set <id> <col>=<val>...   set cells of a ## Dispatch ledger row"
  die "  bash ${HOOK_DIR}/session-poker.sh row-landed <id> <commit> <at> [--by-hand <who> <why>]   the landing's row: status, step line, ledger line, one write"
  die "  bash ${HOOK_DIR}/session-poker.sh proof-add <floor|review|task> <evidence>   record a proof line under ## SDLC State, naming the head its evidence read"
  die "  bash ${HOOK_DIR}/session-poker.sh proof-add review <record> --question <evidence|adversarial|structure> --reader <roster name>   record a reading: the review proof with the question, reader, result and scope"
  die "  bash ${HOOK_DIR}/session-poker.sh waive <evidence|adversarial|structure> '<reply>'   record the user's waiver of that question at the working head, as a waived: line under ## SDLC State"
  die "  bash ${HOOK_DIR}/session-poker.sh release-check   run .bionic/config.yaml's release-check: command from the last release to the working head; record its log and a kind=check proof line, result=fail on a non-zero exit"
  die "  bash ${HOOK_DIR}/session-poker.sh finding-stated <record>#<n> '<sentence>'   store the one changelog sentence of a deferred finding on its deferred: line under ## SDLC State"
  die "  bash ${HOOK_DIR}/session-poker.sh finding-check <record>#<n> <settled <S> <reach>|refuted|unsettled> <check record>   settle the check an unsure finding owes, on its check: line under ## SDLC State"
  die "  bash ${HOOK_DIR}/session-poker.sh finding-move <record>#<n> <defer|fix> '<the user's words>' '<why>'   move a finding across the line on words the user typed in this session, as a moved: line under ## SDLC State"
  die "  bash ${HOOK_DIR}/session-poker.sh launch-sync [--wait]   write every open launch the bound plan lacks (its row and its ledger line) in one transaction"
  die "  bash ${HOOK_DIR}/session-poker.sh prompt     the canonical Patrol prompt: the one a CronCreate for this session carries"
  die "  bash ${HOOK_DIR}/session-poker.sh fill-report [<plan>]   missed-opportunity, HOLD and decline minutes from the run's fill ledger"
  die "  bash ${HOOK_DIR}/session-poker.sh landing-report [--rows] [<plan>]   the run's landings, waits and runs, folded from its landing record and the gate's requests; --rows adds a line per landed row"
  exit 2
}

[ $# -ge 1 ] || usage "a verb is required."
VERB="$1"; shift

# `--report-only` IS THE ONE FLAG MOST VERBS TAKE, and `adopt` and `sweep` are the two that
# take it — the same word for the same promise on both, so an operator who has learned it
# once has learned it. `bind` is the ONE verb that takes an operand, and it is required.
# Everything else keeps the old surface exactly — one word, nothing after it — so a stray
# argument is still the usage error it always was rather than something silently ignored.
#
# `sweep` ALSO TAKES `--window` (REQ-9/D5's prune half, T9) — OPT-IN, never the default.
# Without it, `sweep` still "answers 'clear what nobody can act on here', a question about
# the directory rather than about a session anyone would have to name": PID-liveness alone,
# every dead session's files gone in one pass, exactly as `tests/session-sweep.test.sh`
# pins today (sections 1-6, none of which ever pass this flag — that suite is untouched by
# this addition). WITH it, each dead session's OWN newest file must also be older than the
# poker interval, or that one session — and only that one — is deferred and named in the
# report; see the verb's own comments. The two flags combine freely, in either order.
ADOPT_REPORT_ONLY=no
SWEEP_REPORT_ONLY=no
SWEEP_WINDOWED=no
BIND_ARG=""
FILL_REPORT_ARG=""
case "$VERB" in
  adopt)
    if [ $# -eq 1 ]; then
      [ "$1" = "--report-only" ] || usage "unknown flag for adopt: $1"
      ADOPT_REPORT_ONLY=yes
    elif [ $# -gt 1 ]; then
      usage "adopt takes at most one flag."
    fi
    ;;
  sweep)
    # THE WORDING "at most one flag" IS PINNED VERBATIM (tests/session-sweep.test.sh
    # §6.7, from when this verb took only one possible flag). Repeating either flag still
    # refuses with that exact phrase — accurate under the wider surface too, read as "at
    # most one of each" — so that pin holds unchanged; only a genuinely UNKNOWN flag or too
    # many total tokens gets a different message.
    if [ $# -gt 2 ]; then
      usage "sweep takes at most two flags, and at most one flag of each kind."
    fi
    while [ $# -gt 0 ]; do
      case "$1" in
        --report-only)
          [ "$SWEEP_REPORT_ONLY" = no ] || usage "sweep takes at most one flag of each kind (repeated: --report-only)."
          SWEEP_REPORT_ONLY=yes
          ;;
        --window)
          [ "$SWEEP_WINDOWED" = no ] || usage "sweep takes at most one flag of each kind (repeated: --window)."
          SWEEP_WINDOWED=yes
          ;;
        *) usage "unknown flag for sweep: $1" ;;
      esac
      shift
    done
    ;;
  bind)
    # THE OPERAND IS THE WHOLE POINT OF THE VERB, so its absence is a refusal rather than a
    # default. `bind` with no plan cannot mean "unbind" — engagement owns writing `plan=none`
    # (AC-7) and a verb that also unbound would give the marker a second writer with a second
    # rule. It exits 2, this file's one code for an argument error, like every other verb.
    if [ $# -ne 1 ] || [ -z "$1" ]; then
      usage "bind takes exactly one argument: the plan this session is working."
    fi
    BIND_ARG="$1"
    ;;
  # THE SECOND (AND ONLY OTHER) TWO-OPERAND SHAPE (T-h; D11; REQ-10). `bind`'s comment above
  # explains why one required operand is a refusal rather than a default; the same holds for
  # both of these: `extend` with a name but no reason would ask the sweeper's verdict to
  # explain itself out of nothing, and a default reason would make every extension look the
  # same on a roster meant to say what the agent is actually doing.
  extend)
    if [ $# -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
      usage "extend takes exactly two arguments: the name to re-open and the reason."
    fi
    EXTEND_NAME="$1"
    EXTEND_REASON="$2"
    ;;
  # THE THIRD, and for the same reason: a hold is an answer, and an answer with no reason is
  # one the tick could not print back (wave-24 T7, D1). A reason of only blanks is no reason
  # either: the tick would print the hold with nothing after its dash (T27, review C3).
  hold)
    if [ $# -ne 2 ] || [ -z "$1" ] || [ -z "${2//[[:space:]]/}" ]; then
      usage "hold takes exactly two arguments: the name to keep up and the reason."
    fi
    HOLD_NAME="$1"
    HOLD_REASON="$2"
    ;;
  # THE FILL'S ANSWER, AS HOLD IS THE STAND-DOWN'S (wave-27 T34; REQ-15, D24). Two operands: the
  # ready rows, comma-joined, and the reason. No ids is the usage error, never "every row": a
  # decline names what it answers. A blank reason is no reason, as for hold.
  decline)
    if [ $# -ne 2 ] || [ -z "${1//[[:space:],]/}" ] || [ -z "${2//[[:space:]]/}" ]; then
      usage "decline takes exactly two arguments: the ready row ids, comma-joined, and the reason. There is no form that declines every row."
    fi
    DC_IDS="$1"
    DC_REASON="$2"
    ;;
  # THE USER'S WRITER CAP (wave-27 T34; REQ-15 AC-15.4, D24). `writers=<n>` and the user's reply,
  # verbatim; the value's own shape is the verb's refusal (1), its absence or another field the
  # usage error.
  budget)
    if [ $# -ne 2 ] || [ -z "${2//[[:space:]]/}" ]; then
      usage "budget takes exactly two arguments: writers=<n> and the user's reply, verbatim."
    fi
    case "$1" in
      writers=*) : ;;
      *) usage "budget: '$1' is not writers=<n>; the writer cap is the one value this verb records." ;;
    esac
    BG_N="${1#writers=}"
    BG_REPLY="$2"
    ;;
  # THE NINE CELLS AN AUTHOR WRITES, IN THE TABLE'S OWN COLUMN ORDER (wave-20 REQ-5, AC-5.3;
  # Δ5). `status`, `worktree` and `base` are the dispatcher's cells and are not operands:
  # a new row is `pending` and names no tree. Every operand is required — `—` is how the
  # table itself spells "none" — so a short list is the usage error, never a guessed default.
  # THE TENTH, `<reads>`, IS THE ONE OPTIONAL CELL (wave-26 T59; REQ-5 AC-5.4): the reads column
  # a table may carry (wave-26 T2), from which the row's edges are computed. Left off, the row
  # is written exactly as the nine-operand form always wrote it.
  task-add)
    if [ $# -ne 9 ] && [ $# -ne 10 ]; then
      usage "task-add takes nine arguments and an optional tenth: <id> <step> <kind> <task> <agent> <deps> <size> <serves> <Files> [<reads>] (write — for none)."
    fi
    TA_ID="$1"; TA_STEP="$2"; TA_KIND="$3"; TA_TASK="$4"; TA_AGENT="$5"
    TA_DEPS="$6"; TA_SIZE="$7"; TA_SERVES="$8"; TA_FILES="$9"; TA_READS="${10:-}"
    ;;
  # THE ONE VERB WITH REPEATABLE FLAGS (wave-20 T9, REQ-4; spec D4). Each `--files+`,
  # `--suites+` and `--reexec+` names ONE addition and may be given again; `--reason` is
  # required, for the reason `extend`'s is — a roster meant to say why a contract changed
  # cannot default that sentence. The additions are held newline-joined rather than in
  # arrays: this file runs `set -u` under bash 3.2, where an empty array is unbound.
  # A flag with no change flag at all is a usage error; a change the row already carries is
  # the verb's own refusal (exit 1), because only the row can say so.
  amend)
    if [ $# -lt 1 ] || [ -z "$1" ]; then
      usage "amend takes a name, then --files+/--suites+/--reexec+ additions and --reason."
    fi
    AMEND_NAME="$1"; shift
    AMEND_FILES=""; AMEND_SUITES=""; AMEND_RUNS=""; AMEND_REASON=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --files+|--suites+|--reexec+|--reason)
          if [ $# -lt 2 ] || [ -z "$2" ]; then usage "amend: $1 takes a value."; fi
          case "$2" in --*) usage "amend: $1 takes a value, and got the flag $2." ;; esac
          case "$1" in
            --files+)  AMEND_FILES="${AMEND_FILES}$2"$'\n' ;;
            --suites+) AMEND_SUITES="${AMEND_SUITES}$2"$'\n' ;;
            --reexec+) AMEND_RUNS="${AMEND_RUNS}$2"$'\n' ;;
            --reason)  AMEND_REASON="$2" ;;
          esac
          shift 2 ;;
        *) usage "unknown argument for amend: $1" ;;
      esac
    done
    [ -n "$AMEND_REASON" ] || usage "amend takes --reason <why>: the roster says why a contract changed."
    [ -n "$AMEND_FILES$AMEND_SUITES$AMEND_RUNS" ] \
      || usage "amend changes nothing without --files+, --suites+ or --reexec+."
    ;;
  # THE PLAN-ROW VERBS (wave-24 T15; REQ-9, D14). A row verb takes an id and one or more
  # `<column>=<value>` operands; the shape is checked here and the content in the verb, so a
  # malformed call is the usage error (2) and a value the plan cannot hold is the verb's own
  # refusal (1), with the plan untouched either way. Operands are kept in an array, not
  # newline-joined as amend's are: a value with a line break must reach the verb to be refused
  # by name, not split into two operands here.
  task-set|ledger-add|ledger-set)
    if [ $# -lt 2 ] || [ -z "$1" ]; then
      usage "$VERB takes an id and at least one <column>=<value>."
    fi
    PV_ID="$1"; shift
    for _pv_a in "$@"; do
      case "$_pv_a" in
        [!=]*=*) : ;;
        *) usage "$VERB: '$_pv_a' is not <column>=<value>." ;;
      esac
    done
    PV_PAIRS=("$@")
    ;;
  # THE LANDING'S ROW (wave-28 T6; D7, A-orch-81): an id, the landed commit (40 hex) and the
  # publish's instant (ISO-UTC); a hand landing adds `--by-hand <who> <why>`. The shapes are the
  # usage error's; the values a plan cannot hold are the verb's own refusal.
  row-landed)
    RL_BY=""; RL_WHY=""; RL_HAND=0
    if [ $# -eq 6 ] && [ "$4" = "--by-hand" ]; then RL_HAND=1; RL_BY="$5"; RL_WHY="$6"; set -- "$1" "$2" "$3"; fi
    [ $# -eq 3 ] && [ -n "$1" ] || usage "row-landed takes <id> <40-hex commit> <ISO-UTC> [--by-hand <who> <why>]."
    case "$2" in *[!0-9a-f]*|'') usage "row-landed: '$2' is not a 40-hex commit." ;; esac
    [ "${#2}" -eq 40 ] || usage "row-landed: '$2' is not a 40-hex commit."
    case "$3" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
      *) usage "row-landed: '$3' is not an ISO-UTC instant (YYYY-MM-DDTHH:MM:SSZ)." ;;
    esac
    PV_ID="$1"; RL_COMMIT="$2"; RL_AT="$3"
    ;;
  step-line)
    PV_APPEND=""
    if [ $# -eq 3 ] && [ "$3" = "--append" ]; then PV_APPEND=append; set -- "$1" "$2"; fi
    if [ $# -ne 2 ] || [ -z "$2" ]; then
      usage "step-line takes <N|T<n>> <text> [--append]."
    fi
    case "$1" in
      [0-9]|[0-9][ab]) : ;;
      T[0-9]*) case "${1#T}" in *[!0-9]*) usage "step-line: '$1' is not a task id (T<n>)." ;; esac ;;
      *) usage "step-line: '$1' is neither a step number (0-9, 4a) nor a task id (T<n>)." ;;
    esac
    PV_KEY="$1"; PV_TEXT="$2"
    ;;
  current)
    [ $# -eq 1 ] && [ -n "$1" ] || usage "current takes one argument: the step number (0-8) or the task id (T<n>) to move to."
    case "$1" in
      9|9a|9b|[0-8]|[0-8][ab]) : ;;
      T[0-9]*) case "${1#T}" in *[!0-9]*) usage "current: '$1' is not a task id (T<n>)." ;; esac ;;
      *) usage "current: '$1' is neither a step number (0-8) nor a task id (T<n>)." ;;
    esac
    PV_KEY="$1"
    ;;
  # THE APPROVAL VERB (wave-26 T13; D3, AC-6.2). Two operands, both required: the name a row
  # reads as `approval:<name>`, in the grammar `units_validate` admits there, and the user's
  # reply, verbatim. The name's shape is checked here, by the ASCII letters spelled out (a range
  # is a collation range under a UTF-8 locale; wave-24 T29); the reply's is the verb's own refusal.
  approve)
    if [ $# -ne 2 ] || [ -z "$1" ] || [ -z "${2//[[:space:]]/}" ]; then
      usage "approve takes exactly two arguments: the approval's name and the user's reply, verbatim."
    fi
    case "$1" in
      [ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789]*) : ;;
      *) usage "approve: '$1' is not an approval name: a letter or a digit, then letters, digits, '.', '_' or '-'." ;;
    esac
    case "$1" in
      *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*)
        usage "approve: '$1' is not an approval name: a letter or a digit, then letters, digits, '.', '_' or '-'." ;;
    esac
    AP_NAME="$1"; AP_REPLY="$2"
    ;;
  # TWO OPERANDS AND NO THIRD (wave-26 T4; REQ-3, D5): the kind and the evidence. The head is the
  # one the evidence names, held against the working branch's checkout (T14), never typed, so a
  # head on the command line is the usage error, not a value. A READING (wave-27 T2; D1, D7) adds
  # two flags, both or neither, to a review proof only: `--question <q> --reader <name>`, in
  # either order. Without them a review proof is 1.11.0's, so a plan built under it still works.
  proof-add)
    PF_USAGE="proof-add takes two arguments, <floor|review|task> <evidence path under record/>, and for a reading two flags more: proof-add review <record> --question <evidence|adversarial|structure> --reader <roster name> (the head is the one the evidence names, the head= line of a run log or the end of the reviewed: a..b line of a review, never an operand)."
    if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]; then usage "$PF_USAGE"; fi
    PF_KIND="$1"; PF_EVID="$2"; PF_QUESTION=""; PF_READER=""; shift 2
    while [ $# -gt 0 ]; do
      case "$1" in
        --question) [ $# -ge 2 ] && [ -n "$2" ] && [ -z "$PF_QUESTION" ] || usage "$PF_USAGE"; PF_QUESTION="$2"; shift 2 ;;
        --reader)   [ $# -ge 2 ] && [ -n "$2" ] && [ -z "$PF_READER" ] || usage "$PF_USAGE"; PF_READER="$2"; shift 2 ;;
        *) usage "$PF_USAGE" ;;
      esac
    done
    if [ -n "$PF_QUESTION$PF_READER" ]; then
      { [ -n "$PF_QUESTION" ] && [ -n "$PF_READER" ] && [ "$PF_KIND" = review ]; } || usage "$PF_USAGE"
    fi
    ;;
  # THE WAIVER VERB (wave-27 T9; D2). Two operands, both required: the reading question and the
  # user's reply, verbatim. The question's membership and the reply's shape are the verb's own
  # refusals (1), as proof-add's question is; a missing or blank operand is the usage error.
  waive)
    if [ $# -ne 2 ] || [ -z "$1" ] || [ -z "${2//[[:space:]]/}" ]; then
      usage "waive takes exactly two arguments: the question (evidence, adversarial or structure) and the user's reply, verbatim."
    fi
    WV_Q="$1"; WV_REPLY="$2"
    ;;
  # TWO OPERANDS (wave-28 T17; D21): the finding, as its deferred: line names it (`<record>#<n>`), and
  # the one sentence the changelog will carry for it. Whether the line exists and what the sentence
  # folds to are the verb's own refusals (1), as waive's reply is; a missing or blank operand is the
  # usage error.
  finding-stated)
    if [ $# -ne 2 ] || [ -z "$1" ] || [ -z "${2//[[:space:]]/}" ]; then
      usage "finding-stated takes exactly two arguments: the finding (<record>#<n>, as its deferred: line names it) and its changelog sentence."
    fi
    case "$1" in
      *?#[0123456789]*) : ;;
      *) usage "finding-stated: '$1' is not <record>#<n>." ;;
    esac
    case "${1##*#}" in *[!0123456789]*) usage "finding-stated: '$1' is not <record>#<n>." ;; esac
    FS_ID="$1"; FS_RAW="$2"
    ;;
  # THREE FORMS (wave-28 T41; D33): the finding, as its check: line names it (`<record>#<n>`), how the
  # check came out — `settled <S> <reach>`, `refuted` or `unsettled` — and the check record. A fourth
  # form, a missing operand or an id of another shape is the usage error; whether the rating is on the
  # scale, the line exists and the record is a third agent's are the verb's own refusals (1).
  finding-check)
    FC_USAGE="finding-check takes <record>#<n> (as its check: line names it), then settled <S> <reach>, refuted or unsettled, then the check record."
    case "${2:-}" in
      settled) [ $# -eq 5 ] || usage "$FC_USAGE"; FC_S="$3"; FC_R="$4"; FC_REC="$5" ;;
      refuted|unsettled) [ $# -eq 3 ] || usage "$FC_USAGE"; FC_S=""; FC_R=""; FC_REC="$3" ;;
      *) usage "$FC_USAGE" ;;
    esac
    case "$1" in
      *?#[0123456789]*) : ;;
      *) usage "finding-check: '$1' is not <record>#<n>." ;;
    esac
    case "${1##*#}" in *[!0123456789]*) usage "finding-check: '$1' is not <record>#<n>." ;; esac
    [ -n "$FC_REC" ] || usage "$FC_USAGE"
    FC_ID="$1"; FC_HOW="$2"
    ;;
  # FOUR OPERANDS (wave-28 T42; D34): the finding (`<record>#<n>`), where it goes (defer or fix), the
  # user's words as typed and why. A missing or blank operand, another direction or an id of another
  # shape is the usage error; whether the words stand in a typed prompt is the verb's own refusal (1).
  finding-move)
    FM_USAGE="finding-move takes <record>#<n>, defer or fix, the user's words as typed, and why."
    [ $# -eq 4 ] && [ -n "${3//[[:space:]]/}" ] && [ -n "${4//[[:space:]]/}" ] || usage "$FM_USAGE"
    case "$2" in defer|fix) : ;; *) usage "$FM_USAGE" ;; esac
    case "$1" in
      *?#[0123456789]*) : ;;
      *) usage "finding-move: '$1' is not <record>#<n>." ;;
    esac
    case "${1##*#}" in *[!0123456789]*) usage "finding-move: '$1' is not <record>#<n>." ;; esac
    FM_ID="$1"; FM_TO="$2"; FM_RAW="$3"; FM_WHY_RAW="$4"
    ;;
  # NO OPERAND (wave-27 T16; D12): the range is the verb's own, from the last release to the working
  # head, so a base typed on the command line is the usage error, as a head is for proof-add.
  release-check)
    [ $# -eq 0 ] || usage "release-check takes no arguments: it runs from the nearest tag reachable from the plan's integration-branch that is a proper ancestor of the working head (else its base-sha) to that head."
    ;;
  # ONE OPTIONAL FLAG (wave-26 T32; D4): `--wait` waits for another writer's lock, which only the
  # launch recorder's detached call can afford; the tick and the turn-end wall leave a held lock
  # to its holder.
  launch-sync)
    LS_WAIT=no
    if [ $# -eq 1 ] && [ "$1" = --wait ]; then LS_WAIT=yes
    elif [ $# -ne 0 ]; then usage "launch-sync takes at most one flag: --wait."; fi
    ;;
  tick|arm|disarm|interval|interval-default|window|prompt)
    [ $# -eq 0 ] || usage "$VERB takes no arguments."
    ;;
  # THE MACHINE'S SHARE (wave-28 T10; REQ-2 AC-2.1, D16). No operand prints it; one operand sets it. The
  # value's own shape is the verb's refusal (1); a second operand is the usage error.
  share)
    [ $# -le 1 ] || usage "share takes at most one argument: the share to set, 1 to 100."
    SH_SET=no; SH_ARG=""
    if [ $# -eq 1 ]; then SH_SET=yes; SH_ARG="$1"; fi
    ;;
  # ONE OPTIONAL OPERAND (wave-20 REQ-5, AC-5.6): the plan whose ledger to read. Without it, the
  # session's own run — the one every other verb here resolves.
  fill-report)
    [ $# -le 1 ] || usage "fill-report takes at most one argument: the plan whose fill ledger to read."
    FILL_REPORT_ARG="${1:-}"
    ;;
  # ONE OPTIONAL FLAG AND ONE OPTIONAL OPERAND, IN EITHER ORDER (wave-28 T14; D18; A-orch-145): `--rows`
  # adds a line per landed row; `<plan>` names the run, as fill-report's does, for a caller with no
  # binding left (close-out writes its continuation after its tmp is wiped).
  landing-report)
    LR_ROWS=no; LR_ARG=""
    for _lr_a in "$@"; do
      case "$_lr_a" in
        --rows) [ "$LR_ROWS" = no ] || usage "landing-report takes --rows once."; LR_ROWS=yes ;;
        -*) usage "landing-report takes one flag, --rows, and at most one plan." ;;
        *) [ -z "$LR_ARG" ] || usage "landing-report takes one flag, --rows, and at most one plan."; LR_ARG="$_lr_a" ;;
      esac
    done
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
# agent's progress file the way the sweeper reads a live one. The seven are held together by
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

# Whether a versioned pipe-delimited line CARRIES a key at all — present-and-empty and absent
# are different rows to a by-key reader, and `line_field` returns "" for both. This is a
# SUBSTRING PRESENCE test, not a row assembler: §S13.4 (tests/cross-gate-agreement.test.sh)
# now discriminates the two by shape — an assembler's `=...|<key>=$` against a presence
# test's `*"|<key>="*` — so `$2` staying a parameter here is ordinary genericity across the
# six callers, not a runtime-joined literal kept to dodge a blunter pin (that dodge, needed
# before §S13.4 could tell the two shapes apart, is gone — REQ-13, wave-19 T9).
row_has_key() {  # <line> <key>
  case "|$1" in *"|$2="*) return 0 ;; esac
  return 1
}

clean() {  # <value> [<field name>]
  local out
  out="$(printf '%s' "$1" | tr '\n\r\t|' '    ' | sed -e 's/[[:cntrl:]]/ /g' -e 's/  */ /g' \
    -e 's/^ *//' -e 's/ *$//')"
  # THE CUT IS PER-FIELD, NOT UNIVERSAL (REQ-9, carry-over P2). Every caller still gets
  # control characters and `|` folded to spaces — that half of this function is unchanged
  # and applies with no exception. What used to be unconditional is the trailing
  # `cut -c 1-400`: `suites_allowed=` and `files=` are LIST-valued fields (a space- or
  # comma-joined set, S13's suite-allowance wall and the impact-derived budget), and a
  # dispatch touching enough files or naming enough suites overflows 400 characters on a
  # perfectly ordinary brief — the cut then silently drops suites off the end, which is a
  # budget the wall never agreed to and the operator never asked for. Every OTHER field
  # (name, deliverable, progress, waiver, …) is prose or a path, where a length this
  # generous is already more than any real value needs, so the cut stays for them. Callers
  # that pass no field name (every one but the two below) get today's behaviour exactly.
  # AND `re_executes=` IS DECODED, NOT JUST UNCUT (T4, REQ-7/D4). This function reads a
  # field off a roster row that `adopt_write_row` then hands back to `roster_row`, and the
  # row stores the declared runs percent-encoded (`payload/scripts/lib/roster.sh`, which
  # owns that encoding and carries the reasoning). Plain in memory, encoded on disk: the
  # value goes back to the writer as the brief spelled it and the writer encodes it again,
  # so the row this hook appends is byte-identical to the row it read. Decoding without
  # that symmetry would put a raw pipe on the line and forge a segment; re-encoding an
  # already-encoded value would turn `%7C` into `%257C` and hand a resumed agent a budget
  # holding a command no shell could run. It joins the two LIST-valued fields in skipping
  # the cut for the reason they do — a declared run is a command, and a command cut at 400
  # characters is a budget entry nothing can ever equal — and because a cut landing inside
  # an escape would decode into garbage.
  case "${2:-}" in
    suites_allowed|files) printf '%s' "$out" ;;
    re_executes)
      out="${out//\%7C/|}"
      printf '%s' "${out//\%25/%}" ;;
    *) printf '%s' "$out" | cut -c 1-400 ;;
  esac
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
  grep -qE '[0-9]+\.[0-9]+' <<< "$s" && return 1
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
# absent file or an absent key both read as the documented default, 20m — a knob nobody has
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

# THE WINDOW. `file_birth` is the creation time the filesystem itself recorded — `stat %B`
# here, `%W` on GNU, where 0 means "this filesystem does not keep one" and is not an answer.
# Never mtime: the roster is append-only, so its mtime is the LAST dispatch, and scoping to
# that would hide every gap but the newest.
file_birth() {  # <path> -> epoch seconds, empty when the platform has none
  local b
  b="$(stat -f %B "$1" 2>/dev/null || stat -c %W "$1" 2>/dev/null)" || return 1
  case "$b" in ''|*[!0-9]*|0) return 1 ;; esac
  printf '%s' "$b"
}

epoch_iso() {  # <epoch seconds> -> UTC ISO-8601, the shape the CLI stamps entries with
  date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

# roster_window <roster file> <session id> -> the ISO instant this roster's own record of
# this session begins, or nothing when neither file can date it (see the block comment).
# The Patrol stamp is the fallback because it is written at ARMING, which precedes the
# first dispatch by doctrine — so on a session whose roster was never written it still
# dates the stretch this session is answerable for.
roster_window() {
  local b
  b="$(file_birth "$1")" || b="$(file_birth "$(patrol_stamp_file "$2")" 2>/dev/null)" || return 1
  [ -n "$b" ] || return 1
  epoch_iso "$b"
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

# THE DIGEST FILE'S PATH, beside the stamp under the same resolved root. The path and its
# reader, `tick_digest_field`, are lib/patrol.sh's (`tick_digest_path`), which the stop
# collector calls too (wave-24 T27; critic I3).
tick_digest_file() {  # <session-id> -> absolute path, or empty
  local f
  f="$(patrol_stamp_file "$1")" || return 1
  [ -n "$f" ] || return 1
  tick_digest_path "${f%/.bionic/tmp/*}" "$1"
}

# The digest file is rewritten whole, under the stamp's write guard. `arm` writes only the
# version, so the first tick after an arm prints in full. A tick's digest carries `at=`, the
# instant it was written: `since=` is the instant the facts last changed and an unchanged tick
# keeps it, so only `at=` tells the stop collector the digest is this turn's (critic I3).
# `gate_raised=` is the set of gate requests already raised (below), and `arm` carries it over,
# so a re-arm does not raise them a second time. `change=` is the fingerprint of the plan's
# `## Tasks` statuses and its ready set (wave-26 T15; D16): the task-list duty is owed only when
# it moved, so `arm` does not carry it and the first tick after an arm compares against nothing.
write_tick_digest() {  # <session-id> <version> [<digest> <since> <decision> <duty> [<gate keys> [<change> [<live head> [<plan current> <plan rows> [<facts state> [<reconcile cause>]]]]]]] -> 0 written, 1 not
  local f d
  f="$(tick_digest_file "$1")" || return 1
  [ -n "$f" ] || return 1
  d="${f%/*}"
  tmp_dir_ok "$d" || return 1
  mkdir -p "$d" 2>/dev/null || return 1
  [ -L "$f" ] && return 1
  {
    printf '%s\n' "$PATROL_DIGEST_SCHEMA"
    [ -n "$2" ] && printf 'prompt_version=%s\n' "$2"
    if [ -n "${3:-}" ]; then
      printf 'digest=%s\nsince=%s\ndecision=%s\nduty=%s\nat=%s\n' "$3" "$4" "$5" "$6" "$(iso_now)"
    fi
    if [ -n "${7:-}" ]; then
      printf 'gate_raised=%s\n' "$7"
    fi
    if [ -n "${8:-}" ]; then
      printf 'change=%s\n' "$8"
    fi
    # THE HEAD THIS TICK JUDGED `live:head` AGAINST (wave-26 T32; A-T14.2), so the turn-end wall,
    # which reads no git, hands the same head to the same ready set on this tick's turn.
    if [ -n "${9:-}" ]; then
      printf 'head=%s\n' "$9"
    fi
    # THE PLAN'S `current:` AND ITS `## Tasks` ROW COUNT, as this tick read them (wave-27 T13; D20):
    # the next tick asks for a task-list reconcile when current: went 3 to 4 or the count grew.
    # `arm` carries neither, so the first tick after an arm compares against nothing.
    if [ -n "${10:-}" ]; then
      printf 'plan_current=%s\n' "${10}"
    fi
    if [ -n "${11:-}" ]; then
      printf 'plan_rows=%s\n' "${11}"
    fi
    # THE FACTS STATE THIS TICK JUDGED (wave-27 T43; A-orch-82), `sched_facts_state`'s answer, so
    # the turn-end wall, which runs no judge and reads no git, hands the integrate row's
    # `proof:review` the same answer on this tick's turn, as it hands the head above. One line.
    if [ -n "${12:-}" ]; then
      printf 'facts_state=%s\n' "$(printf '%s' "${12}" | tr '\n' ' ')"
    fi
    # WHY THE RECONCILE IS OWED, when the plan moved (wave-27 T37): `step4` or `grew`, read by the
    # turn-end wall (lib/stop.sh `stop_turn_facts`) so its refusal gives the tick's own cause.
    if [ -n "${13:-}" ]; then
      printf 'reconcile=%s\n' "${13}"
    fi
  } > "$f" 2>/dev/null || return 1
  chmod 600 "$f" 2>/dev/null
  return 0
}

# THE GATE REQUESTS (wave-25 T5, REQ-4 AC-4.3; D7). hooks/permission-answer.sh denies a reserved
# action and appends one line per distinct request to `.bionic/tmp/gate-<lead sid>.state`:
#   gate/v1|at=<ISO-UTC>|session=<lead sid>|asker=<name or lead>|category=<category>|head=<command head>
# The tick reads that file and the lead raises each request with the human once. The file is the
# record and nothing here rewrites it; "raised" lives in the digest file as `gate_raised=`, the
# keys of the requests the last tick saw. A request is PENDING while its key is not in that set.
#
# THE KEY IS THE HOOK'S DEDUPE KEY (asker, category, head; the session is the file's), hashed so
# the digest file holds a short token per request rather than a command. The hash is computed in
# awk under the C locale, over bytes: `cksum` per line would cost a process per request per tick.
# A line that is not `gate/v1`, names another session, or lacks an asker, a category of the
# reserved table's shape or a head is skipped: a malformed line raises nothing and stops nothing.
gate_requests() {  # <gate file> <session id> <raised keys, comma-separated>
                   # -> one line per distinct request: <key> TAB <new|raised> TAB <asker> TAB <category> TAB <head>
  LC_ALL=C awk -v sid="$2" -v raised=",$3," '
    BEGIN { for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i }
    function key(s,   h, i, n) {
      h = 0; n = length(s)
      for (i = 1; i <= n; i++) h = (h * 31 + ord[substr(s, i, 1)]) % 2147483647
      return h "-" n
    }
    index($0, "gate/v1|") != 1 { next }
    {
      se = ""; a = ""; c = ""; hd = ""; has_head = 0
      nf = split($0, f, "|")
      for (i = 2; i <= nf; i++) {
        if (index(f[i], "session=") == 1) se = substr(f[i], 9)
        else if (index(f[i], "asker=") == 1) a = substr(f[i], 7)
        else if (index(f[i], "category=") == 1) c = substr(f[i], 10)
        else if (index(f[i], "head=") == 1) { hd = substr(f[i], 6); has_head = 1 }
      }
      if (se != sid || a == "" || c !~ /^[a-z][a-z-]*$/ || !has_head) next
      k = key(a "|" c "|" hd)
      if (k in seen) next
      seen[k] = 1
      print k "\t" (index(raised, "," k ",") ? "raised" : "new") "\t" a "\t" c "\t" hd
    }' "$1" 2>/dev/null
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
#
# <since> is the window's ISO instant, empty for "the whole transcript". Comparison is on the
# entry's own `timestamp` truncated to the second — the CLI writes fractional seconds and a
# raw string compare would sort `…:23.9Z` BEFORE `…:23Z` and drop an in-window entry.
count_main_thread_dispatches() {  # <transcript> [<since ISO>] -> count on stdout
  awk -v since="${2:-}" '
    function in_window(   t) {
      if (since == "") return 1
      if (match($0, /"timestamp"[[:space:]]*:[[:space:]]*"[^"]+"/) == 0) return 1
      t = substr($0, RSTART, RLENGTH)
      sub(/^.*:[[:space:]]*"/, "", t); sub(/"$/, "", t)
      return (substr(t, 1, 19) >= substr(since, 1, 19))
    }
    /"isSidechain"[[:space:]]*:[[:space:]]*true/          { next }
    /"agent_?[Ii][dD]"[[:space:]]*:[[:space:]]*"[^"]/     { next }
    {
      # THE CHEAP TEST FIRST. A line with no compact `"name":"Agent"` literal — the shape
      # every entry this partition can count is written in, the CLI own compact
      # serialization, never a hand-spaced one — cannot hold a dispatch, so a plain
      # substring index() runs before the per-line timestamp match() inside in_window()
      # ever does. `line` is `$0` SAVED FIRST, into its own variable, because the counting
      # `gsub` below mutates whatever it is pointed at — targeting `line` rather than the
      # bare (implicit-`$0`) form keeps `$0` intact for the match() inside in_window() to
      # test against the untouched record.
      line = $0
      if (index(line, "\"name\":\"Agent\"") == 0) next
      if (in_window()) n += gsub(/"name"[[:space:]]*:[[:space:]]*"Agent"/, "", line)
    }
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
#
# THE SAME WINDOW as the dispatch count, and for the same reason: a refusal from the wave
# before this roster would otherwise be subtracted from a gap in this one, turning a real
# blind wall silent.
count_refused_dispatches() {  # <transcript> [<since ISO>] -> count on stdout
  awk -v since="${2:-}" '
    function quoted_value(seg,   v) {     # `"key" : "value"` -> value
      v = seg; sub(/^.*:[[:space:]]*"/, "", v); sub(/"$/, "", v); return v
    }
    function in_window(   t) {
      if (since == "") return 1
      if (match($0, /"timestamp"[[:space:]]*:[[:space:]]*"[^"]+"/) == 0) return 1
      t = substr($0, RSTART, RLENGTH)
      sub(/^.*:[[:space:]]*"/, "", t); sub(/"$/, "", t)
      return (substr(t, 1, 19) >= substr(since, 1, 19))
    }
    /"isSidechain"[[:space:]]*:[[:space:]]*true/          { next }
    /"agent_?[Ii][dD]"[[:space:]]*:[[:space:]]*"[^"]/     { next }
    !in_window()                                          { next }
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

# ---------------------------------------------------------------- the run's own state
#
# WHAT THE TICK COULD NOT SEE UNTIL NOW. `open == 0` is not "this run is finished" — it is
# "nothing is dispatched at this instant", which is equally the gap between two batches of a
# live wave: every writer of one task landed, the next task not yet briefed. DISARM is
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
# it, and task SCHED closed it by moving the library to depth 2 and deleting the copy. Two
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
# lines into one and hand `current:` a value that was never written. That text utility is
# `normalize_newlines`, and it is payload/scripts/lib/run.sh's now (epic-23
# wave-12-fixit-171, REQ-8, spec D6) — sourced at :255, above every reader below. It had
# three definitions, two of them taking a file argument like this one and one reading stdin;
# `"$@"` is what made them one body rather than one of them winning. run.sh was already in
# this hook's `BIONIC_LIB_WANT`, so nothing widened to reach it.

# THE TWO FIELDS, AND NOTHING ELSE. `current:` and the `Step 9:` line are read out of the
# fence-aware `## SDLC State` section exactly as the evidence gate reads them, so a plan
# documenting the schema inside a ``` example cannot answer for the run.
#
# The `why` half is not decoration: it is the whole content of the QUIET line this feeds. A
# tick that says "no open row, but the run is not delivered" and stops there tells its reader
# nothing they can act on, and the reader is a model deciding whether the Patrol is broken.
# ---------------------------------------------------------------- whose run is this?
#
# THE TICK HAS TWO PLAN READERS — the run-state read below and the FILL scheduler's budget
# and task table — and before wave-session-bound-run both asked the ROOT: `active_plan`, the
# newest plan carrying an unfenced `## SDLC State`. A root with two runs in it has one newest
# plan and two sessions, so one of them was always reading the other's run: the session whose
# run was mid-flight DISARMed off the neighbour's close-out, and the session whose run had
# closed kept ticking off the neighbour's open plan (spec AC-1, AC-6).
#
# ONE RESOLUTION, TWO CONSUMERS, ONE ANNOUNCEMENT. Both readers call this and it answers
# once — `session_run` is a find over the docs tree and the announcement is a fact about the
# tick, not about the site that asked. Saying it twice would read as two resolutions.
#
# WHAT EACH VERDICT MEANS HERE (payload/scripts/lib/run.sh:414):
#   bound-open <p>    this session's own run, and it is open        -> p, open
#   fallback <p>      no binding, and the root has an open run that is somebody's: said out
#                     loud with how to bind, and acted on by nothing -> no plan, NOT open
#   bound-closed <p>  this session's own run, and it has closed     -> p, NOT open
#   bound-unreadable <p>  its own run's plan is there, unreadable   -> p, OPEN=unreadable:
#                     named, never "no open run"; run_state keeps the Patrol (doubt is open)
#                     and the scheduler fills nothing from a plan it cannot read (wave-20 T1)
#   none              no binding and no open run in the root        -> today's newest plan,
#                                                                      NOT open
#
# THE `none` ARM IS WHY THIS IS NOT A ONE-LINE SUBSTITUTION. `session_run` answers `none`
# when there is no binding AND `active_run` has nothing — which is exactly the state a
# DELIVERED run leaves behind, and exactly the state the tick has to read a plan in to decide
# DISARM at all. Taking `none` as "no plan" would make DISARM unreachable for every unbound
# session in the fleet, so the arm falls back to `active_plan` — the same call this function
# made before the wave, on the one path where the wave has nothing to say. For an unbound
# session the pair (plan, open) this sets is therefore identical to (`active_plan`,
# `active_run` succeeded) at every input: today's behaviour, verbatim (AC-3).
POKER_RUN_PLAN=""
POKER_RUN_OPEN=no
POKER_RUN_RESOLVED=no
# ANSWERS ONCE PER PROCESS, AND THE ARGUMENTS OF EVERY LATER CALL ARE IGNORED — not keyed
# on them, discarded (review readability F7). The guard below returns before `$1` and `$2`
# are ever read, so this is a latch and not a memo table: a second call naming a DIFFERENT
# root would silently receive the first root's answer. It is safe because both call sites
# pass the same pair — `run_state` (below) and the FILL scheduler — and a poker process
# serves exactly one project root and one session key for its whole life. A third caller
# with a different pair would have to key the latch rather than reuse it.
resolve_run() {  # <project root> <session id> -> sets POKER_RUN_PLAN / POKER_RUN_OPEN
  [ "$POKER_RUN_RESOLVED" = yes ] && return 0
  POKER_RUN_RESOLVED=yes
  local repo="$1" sid="${2:-}" raw word path
  raw="$(session_run "$repo" "$sid")" || :
  word="${raw%% *}"
  path="${raw#* }"
  case "$word" in
    bound-open)
      POKER_RUN_PLAN="$path"; POKER_RUN_OPEN=yes ;;
    fallback)
      # UNBOUND MEANS NO RUN (wave-23-fixit-1810, REQ-1, D1; T11 after the Step-6 review).
      # The plan is ANNOUNCED — lib/run.sh's one advisory, never a copy — and never acted
      # on: the variables are the ones a session with no run gets, so the tick prints its
      # no-run line and the scheduler fills nothing from another session's task table. `die`
      # prints and does not exit; the verb carries on, which is the point.
      POKER_RUN_PLAN=""; POKER_RUN_OPEN=no
      die "$(run_unbound_advisory "$path")" ;;
    bound-closed)
      # A BINDING IS A COMMITMENT (design ledger D2). The plan is carried through rather
      # than dropped, because the 1.3.2 read below is what turns "closed" into a DISARM the
      # operator can read — and it is carried WITHOUT the open verdict, so the library's
      # second opinion cannot re-open a run this session already finished.
      POKER_RUN_PLAN="$path"; POKER_RUN_OPEN=no
      die "bound plan closed — $path; this session has no open run" ;;
    bound-unreadable)
      # A BINDING IS A COMMITMENT, AND AN UNREADABLE ONE IS STILL ONE (wave-20 T1, REQ-2).
      # The plan is carried, the neighbour's is never read, and "open" is neither yes nor no.
      POKER_RUN_PLAN="$path"; POKER_RUN_OPEN=unreadable
      die "bound plan unreadable — $path; restore read access to it" ;;
    none)
      POKER_RUN_PLAN="$(active_plan "$repo")" || POKER_RUN_PLAN=""
      POKER_RUN_OPEN=no ;;
    *)
      # A WORD THIS TICK DOES NOT KNOW RESOLVES NOTHING. This arm was `none`'s, and a verdict
      # added to `session_run` without an arm here fell into `active_plan` — another run's
      # plan (wave-20 T1, REQ-2). `none` keeps that read by name, for the reason above.
      POKER_RUN_PLAN=""; POKER_RUN_OPEN=no ;;
  esac
  return 0
}

run_state() {  # <project root> <arming-record path, may be empty> <session id> -> "delivered|<why>" or "open|<why>"
  local repo="$1" armed="${2:-}" sid="${3:-}" droot plan section current line
  if [ -z "$repo" ] || [ ! -d "$repo" ]; then
    printf 'open|no project root resolved, so no plan could be read'
    return 0
  fi
  # ONE CALL EACH, AND NEITHER IS RESTATED HERE. `docs_root` is asked only so the refusal
  # below can name the directory it searched; `resolve_run` is the selection itself, and it
  # is THIS SESSION's rather than the root's (see its header).
  droot="$(docs_root "$repo")"
  resolve_run "$repo" "$sid"
  plan="$POKER_RUN_PLAN"
  if [ -z "$plan" ]; then
    printf 'open|no plan carrying an unfenced "## SDLC State" under %s/{plans,incidents}' "$droot"
    return 0
  fi
  # A BOUND PLAN THAT IS GONE. `session_run` reports a missing binding as `bound-closed`, so
  # the path can name a file no longer on disk — and every read below would then be an awk
  # error on stderr and an empty answer. DOUBT IS `open` (ADR-002 §3), which is the same
  # answer the no-plan arm above gives, so the Patrol keeps its stamp rather than stopping
  # on a file nobody can read.
  if [ ! -f "$plan" ] && [ "$POKER_RUN_OPEN" != unreadable ]; then
    printf 'open|%s is this session'"'"'s bound plan and it is not on disk' "$plan"
    return 0
  fi
  # AN UNREADABLE BOUND PLAN IS DOUBT, AND DOUBT IS `open` (ADR-002 §3; wave-20 T1, REQ-2).
  # It is not gone — the arm above would say "not on disk", which for a plan inside an
  # unopenable folder is false — and nothing below could read its `current:`.
  if [ "$POKER_RUN_OPEN" = unreadable ]; then
    printf 'open|%s is this session'"'"'s bound plan and it cannot be read' "$plan"
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
  # THE LIBRARY'S SECOND OPINION, as a CONJUNCT and never as a replacement. `lib/run.sh` is
  # the SSoT for "is this run open" (spec §3, ownership table) and it reads more plans than
  # the block above does — depth 3, and no fence filter. The read above is the evidence
  # gate's, held body-for-body by tests/cross-gate-agreement.test.sh §S, and it is the
  # STRICTER of the two: a fenced `## SDLC State` is documentation here and a run there. So
  # the two are ANDed in the one direction that cannot cost anything — where the library
  # still calls the run open, `open` wins. That is this function's fail direction everywhere
  # else, applied to the one reader that can see a plan this one cannot.
  #
  # THE OPINION IS NOW ABOUT THIS SESSION'S PLAN, not the root's newest (AC-6). It is
  # `resolve_run`'s own verdict — `run_open` on the very file this function just read —
  # rather than a second `active_run` call, which in a two-run root would answer for the
  # neighbour and keep a finished Patrol alive forever.
  if [ "$POKER_RUN_OPEN" = yes ]; then
    printf 'open|%s records delivered:, but lib/run.sh still reads this run as open' "$plan"
    return 0
  fi
  printf 'delivered|%s is at current: 9 and its Step 9 line records delivered:' "$plan"
}

# ---------------------------------------------------------------- the scheduler
#
# FILL, sized at the gate (spec AC-17, AC-29, AC-31; design-ledger D3; wave-28 T13, D14).
#
# THE PROBLEM. A wave's width was a number in a brief, and a ceiling nobody reaches is a
# wave running one writer at a time by accident: this repo's own 1.4.0 wave dispatched six
# trees against a budget of twenty-two and then went quiet for a batch at a time. Nothing
# on the machine was watching for the gap, because the only thing that fires on its own is
# the Patrol tick — and the tick had no opinion about width.
#
# THE WIDTH IS THE GATE'S (wave-28 T13; D14, AC-2.5, AC-2.8; the owner's "Option 2"). The
# tick fills by asking `gate_room` once per ready row, the writers not yet showing counted as
# owed, and stops at the first no (`fill_gate_width`, lib/fill.sh); a person's cap (`fill_cap`,
# the stop wall's reader too) still caps. It prints ONE gate line on every tick, in place of the
# rung, the HOLD and the EMERGENCY that came before it:
#
#   gate share=<n> used=<n>% load=<1m>/<5m> of <cores> promised=<n> admitted=<n> waiting=<n> room=<yes|no>
#
# and, while memory is over the share, `over share — used=<n>% admitted: <keys>`. The gate
# admits no run past memory's share, so nothing is left for a tick to stop: the line names what
# holds the memory and leaves the act to the orchestrator.
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

# THE PLAN HEADER'S BUDGET IS READ BY run.sh (epic-23 wave-20 T2, D10). `plan_budget_line`
# (the strict `parallel-budget:` line of the leading frontmatter) and `budget_field` (one
# whole field, as a decimal integer) moved there from this file, so the tick, the stop wall,
# dispatch preflight and the governing-skill hook size a run from one reading. NOT AN INTEGER
# IS ABSENT: an arm this cannot measure goes unmeasured and says so.

# THE TASK TABLE IS NOT READ HERE ANY MORE (REQ-1e, spec §2 D3). `slice_table` and
# `slice_ready` — a header-keyed `id`/`deps`/`status` parse and the readiness pass over it
# — lived at this point in the file and are now `units_rows` and `units_ready` in
# payload/scripts/lib/units.sh, sourced above. The idiom is theirs, unchanged: column
# indices from the header row by NAME, fence-aware, table order preserved, and the cautious
# fill direction (an id the table does not carry is NOT ready, because a task held back
# costs a batch and a task dispatched onto an unlanded dependency costs the writer's whole
# run). What the move buys is the STEP: the widened table carries one, so a tick at
# `current: 5` fills Step-5 rows and not the Step-6 rows sitting ready behind them.

# ---------------------------------------------------------------- the gate report
#
# THE CEILINGS STEP 0 MEASURED, read once. Both may be absent — a project with no plan, or a
# plan that slipped past the governing-skill hook's budget arm (wave-19 REQ-3, ADR-035) —
# and the caller then says why it is not filling and fills nothing; the stop wall refuses
# the turn on the same absence, naming the key.
#
# THE SAME RUN EVERY OTHER DECISION THIS TICK WAS TAKEN ON. `resolve_run` answers once per
# process and memoizes, so calling this twice on one tick costs one `plan_budget_line` and
# nothing else — which is what lets the report below be reached from three exit paths
# without any of them re-deciding which run they are in.
sched_budget_read() {  # <project root> <session id> -> sets SCHED_PLAN/SCHED_BUDGET/SCHED_WRITERS/SCHED_JOBS
  resolve_run "$1" "${2:-}"
  SCHED_PLAN="$POKER_RUN_PLAN"
  SCHED_BUDGET=""
  [ -n "$SCHED_PLAN" ] && [ "$POKER_RUN_OPEN" != unreadable ] \
    && SCHED_BUDGET="$(plan_budget_line "$SCHED_PLAN")"
  # A PERSON'S CAP, OR NONE (wave-28 T9; D15): `budget_cap` (lib/run.sh) answers only from a
  # line whose `source=` is `user` or `override`, so a probe's `writers=` sizes nothing here.
  SCHED_WRITERS=""
  [ -n "$SCHED_BUDGET" ] && SCHED_WRITERS="$(budget_cap "$SCHED_PLAN")"
  SCHED_WRITERS="${SCHED_WRITERS#writers=}"
  SCHED_JOBS="$(budget_field "$SCHED_BUDGET" test_jobs)"
  sched_live_head "$1"
  sched_facts_state "$1"
}

# THE WORKING BRANCH'S HEAD, the one fact the readiness program cannot read from the plan
# (wave-26 T14; D10, review 5 F8). A `live:head` review is ready again once the head has moved
# past the last `proved: kind=review` line, and the head lives in git: the tick reads it here,
# from the checkout holding the plan's `working-branch:` (lib/proof.sh `proof_head`, the same
# answer `proof-add` records), and hands it to every ready-set question this tick asks through
# UNITS_LIVE_HEAD. Only a plan that carries a review proof needs it — before the first one, a
# landed row is enough — so a tick on any other plan runs no git. No head (no branch, no
# checkout) is no head: the review waits, saying so. The stop wall reads no git of its own, so
# it hands in none (A-T14.2).
sched_live_head() {  # <project root> -> sets UNITS_LIVE_HEAD, or clears it
  UNITS_LIVE_HEAD=""
  [ -n "${SCHED_PLAN:-}" ] && [ -f "$SCHED_PLAN" ] || return 0
  /usr/bin/grep -q '^[[:space:]-]*proved:.*kind=review' "$SCHED_PLAN" 2>/dev/null || return 0
  if ! declare -F proof_head >/dev/null 2>&1; then
    [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh" 2>/dev/null
  fi
  declare -F proof_head >/dev/null 2>&1 && declare -F proof_working_branch >/dev/null 2>&1 || return 0
  UNITS_LIVE_HEAD="$(proof_head "$1" "$(proof_working_branch "$SCHED_PLAN")" 2>/dev/null)" || UNITS_LIVE_HEAD=""
  return 0
}

# THE FACTS THE RUN OWES, JUDGED ONCE PER TICK (wave-27 T14; D3). The integrate row's
# `proof:review` is met only when lib/proof.sh `facts_state` holds the plan at the working head,
# and that reads git, so the readiness program is handed the answer through UNITS_FACTS_STATE, as
# it is handed the head: `covered`, or the owed lines that do not hold, `; `-joined. It is asked
# only when the plan carries an open integrate row (no other read turns on it), and once per tick
# (`gate_report` reads the budget a second time). Unset, the integrate row waits, saying so.
# THE FLOOR IS ASKED FIRST, FROM THE TICK'S OWN MEMO (`_units_floor_state`, the one proof_state run
# the schedule spends anyway): while it does not hold, integrate waits on proof:floor whatever the
# readings say, so the judge, which would run proof_state again, is not asked.
sched_facts_state() {  # <project root> -> sets UNITS_FACTS_STATE, or clears it
  local wb head out rc fst
  [ "${SCHED_FACTS_PLAN:-}" = "${SCHED_PLAN:-}" ] && [ -n "${SCHED_FACTS_PLAN:-}" ] && return 0
  SCHED_FACTS_PLAN="${SCHED_PLAN:-}"
  UNITS_FACTS_STATE=""
  [ -n "${SCHED_PLAN:-}" ] && [ -f "$SCHED_PLAN" ] || return 0
  units_rows "$SCHED_PLAN" 2>/dev/null | awk -F'\t' '$3 == "integrate" && ($10 == "pending" || $10 == "active") { f = 1 } END { exit !f }' \
    || return 0
  fst="$(_units_floor_state "$SCHED_PLAN" 2>/dev/null)"
  case "$fst" in
    covered*|bounded*) : ;;
    *) UNITS_FACTS_STATE="the readings are judged once the floor holds"; return 0 ;;
  esac
  if ! declare -F facts_state >/dev/null 2>&1; then
    [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh" 2>/dev/null
  fi
  declare -F facts_state >/dev/null 2>&1 || return 0
  head="${UNITS_LIVE_HEAD:-}"
  if [ -z "$head" ]; then
    wb="$(proof_working_branch "$SCHED_PLAN")"
    [ -z "$wb" ] || head="$(proof_head "$1" "$wb" 2>/dev/null)" || head=""
  fi
  if [ -z "$head" ]; then
    UNITS_FACTS_STATE="no checkout holds the working branch, so there is no head to judge them at"
    return 0
  fi
  out="$(facts_state "$SCHED_PLAN" "$head" 2>/dev/null)"; rc=$?
  case "$rc" in
    0) UNITS_FACTS_STATE=covered ;;
    2) UNITS_FACTS_STATE="the plan's rigor and scale cannot be dealt" ;;
    *) UNITS_FACTS_STATE="$(printf '%s\n' "$out" | awk -F'\t' '$NF != "covered" { $1 = $1; printf "%s%s", (n++ ? "; " : ""), $0 }' OFS=' ')" ;;
  esac
  return 0
}

# ── THE APPROVAL GATE (epic-21 T4, AC-5). A printed FILL is a dispatch instruction — the
# duties gate (hooks/patrol-duties-gate.sh) refuses the turn until every named task is
# either dispatched or explicitly declined — and dispatching into a plan that has not
# reached Step 4 sends a writer against a task table nobody has ratified: Steps 0-3 are
# research/spec/plan/REVIEW, and `current:` only reaches 4 once Step 3's approval is given
# (SKILL.md §Steps). Observed 2026-09-05T17:54Z: the tick printed `FILL S1 S2 S3 S4 S12 S14
# S15 S16` against the wave-01 plan sitting at `current: 3`.
#
# THE SAME FENCE-AWARE READ `run_state` USES ABOVE, deliberately duplicated rather than
# shared. `run_state` answers a different question (has THIS run delivered) off a plan
# resolved through its own `resolve_run` call, and folding this into it would couple the
# DISARM decision to the FILL decision — two arms this wave's scope keeps apart. Sharing the
# awk/grep/sed pipeline, not the caller, keeps the two readings from ever disagreeing about
# what one `current:` line says.
#
# AND THE PARSER IS THE LIBRARY'S (wave-19 REQ-6, D7; AC-6.1). The fence-aware read described
# above lives once, in `payload/scripts/lib/fill.sh`'s `_fill_current_field` (sourced above
# with units.sh), which the stop wall's fill duty reads through as well. This name stays as a
# one-line wrapper rather than disappearing: §CG of tests/cross-gate-agreement.test.sh
# extracts it as text and drives it beside `run_open` with fill.sh sourced, and §32 of
# tests/session-poker.test.sh drives it beside the library — a poker that called the library
# directly would leave §32 comparing one function with itself.
_sched_plan_current_field() {  # <plan path> -> the RAW current: value (trimmed), or ""
  _fill_current_field "$@"
}

# THE ONE GRAMMAR THIS REPO ALREADY HAS (Step-6 review-a C-5, review-b finding (c)/N-2).
# payload/scripts/lib/run.sh's run_open strips a trailing a/b sub-step letter before it
# ever looks at digits (`local step="${current%[ab]}"`) — `current: 3b` and `current: 4b`
# are recognized, in-repo forms, not malformed ones. This mirrors exactly that: strip the
# same optional letter, then require what remains to be all-digits. A task-scale `current:
# T<n>` needs no special case to land here — "T1" ends in neither `a` nor `b`, so the strip
# is a no-op and the leftover `T` fails the digit test on its own, same as it always has.
sched_plan_current() {  # <plan path> -> the current: value (digits only, sub-step letter
                        # stripped), or "" if the raw value is unreadable
  local plan="$1" current step
  current="$(_sched_plan_current_field "$plan")"
  step="${current%[ab]}"
  case "$step" in ''|*[!0-9]*) printf '' ;; *) printf '%s' "$step" ;; esac
}

# ── THE GATE LINE, ON EVERY TICK (wave-28 T13; D14, AC-2.8). One `gate_state` and one
# `gate_room` with the writers not yet showing as owed, printed as one line from every exit
# path, as the rung line was (AC-17: the first tick of a run takes the armed arm, and the DISARM
# arm exits above the scheduler). `gate_state` takes the gate's lock, so the tick is also one of
# the gate's samplers: each line raises the peak of every admitted run.
#
# NO GATE IS NO ROOM. A gate.sh that did not load is a width this tick does not have, and the
# line says so; a fill sized on nothing would be the guess the gate exists to replace.
gate_report() {  # <project root> <session id> -> sets SCHED_GATE_ROOM/SCHED_OWED, says one line
  local st rm used share keys
  sched_budget_read "$1" "${2:-}"
  SCHED_GATE_ROOM=no; SCHED_OVER=no
  SCHED_OWED="$(sched_owed)"
  if ! declare -F gate_room >/dev/null 2>&1 || ! declare -F fill_gate_width >/dev/null 2>&1; then
    say "gate unreadable — lib/gate.sh did not load, so no row is offered"
    return 0
  fi
  st="$(gate_state 2>/dev/null)"
  rm="$(gate_room --owed "$SCHED_OWED" 2>/dev/null)"
  share="$(space_field "$st" share)"; used="$(space_field "$st" used)"
  SCHED_GATE_ROOM="$(space_field "$rm" room)"
  say "gate share=${share:--} used=${used:--}% load=$(space_field "$rm" load) of $(space_field "$rm" cores) promised=$(space_field "$rm" promised) admitted=$(space_field "$st" admitted) waiting=$(space_field "$st" waiting) room=${SCHED_GATE_ROOM:-no}"
  case "$used$share" in *[!0-9]*|'') return 0 ;; esac
  [ "$used" -gt "$share" ] || return 0
  SCHED_OVER=yes
  keys="$(gate_list 2>/dev/null | awk '$2 == "admitted" && match($0, / key=/) { printf "%s%s", (n++ ? ", " : ""), substr($0, RSTART + 5) }')"
  say "over share — used=${used}% admitted: ${keys:-none}"
}

# THE WRITERS NOT YET SHOWING (D14): the open writer rows of this tick whose agent has not asked
# the gate for a run, read by `fill_gate_owed` (lib/fill.sh) — the count the stop wall takes too.
sched_owed() {
  if ! declare -F fill_gate_owed >/dev/null 2>&1; then printf '0'; return 0; fi
  printf '%s' "${TICK_OCC_NAMES:-}" | fill_gate_owed "${ROSTER_FILE:-}" "${SESSION_ID:-}"
}

# ---------------------------------------------------------------- the plan report
#
# THE HOLDS AND THE LEDGER, ON EVERY TICK THAT DECIDES (wave-21 T13; REQ-3 AC-3.3, REQ-4
# AC-4.1/AC-4.2; the audit's refutation at 3b45d05). Through T5 both reports lived inside the
# FILL branch, and three reachable states never reached it: the first tick of a run (no roster
# yet: rung, QUIET, exit), HOLD or EMERGENCY under machine pressure, and a plan with no
# `parallel-budget`. The commit gate reads the ledger in every state, so a plan the gate
# refused ticked clean — AC-4.1's fails-when, word for word. Neither report has anything to do
# with the machine or the budget, so neither waits on them: every arm that decides calls this
# once, after its gate line and before its own sentence, and no arm prints them a second time.
#
#   HELD (T4; D3, ADR-037 decision 2). `units_held` names two kinds of row the ready set leaves
#     out: one held FOR ITS STEP (a gate act ahead of `current:`) and one held BY THE WORLD
#     (`ext:<slug>` left in its deps cell). Each ext-held row prints as
#     `poker: HELD <id> ext:<slug>`: the one report of a wait nothing mechanical lifts,
#     addressed to the only actor who can lift it (remove the token from the cell). The
#     step-held lines are left in `SCHED_HOLDS` for the no-FILL line, where they have always
#     been printed.
#   LEDGER (T5; D4, ADR-037 decision 3). `units_findings` is the reader the commit gate refuses
#     on — a status off the enum, a row at its terminal word with no `- T<n>:` line, an
#     `active` row whose agent cell names no row on THIS session's roster — and each finding
#     prints as `poker: LEDGER <id> <kind> [<value>]`. The roster is the one this tick reads;
#     a missing one (the first tick) is the reader's no-roster rule, which is the gate's too.
#
# AN UNREADABLE BOUND PLAN, OR NO PLAN, REPORTS NOTHING: there is no table to read, and the
# arms that decide say why themselves. A `current:` that will not parse still lints the
# ledger — the findings ask no step — and only the holds, which are a readiness question,
# need the step token.
#
# CALLED UNDER `tick_plan_memoised`, so the holds, the findings and — on the arm that fills —
# the ready set are answered from ONE parse of the table (review-bed/perf/report.md measured
# four parses per tick before this).
SCHED_HOLDS=""
tick_plan_report() {  # -> says the HELD and LEDGER lines; sets SCHED_HOLDS
  local step hold finding kind rest val
  SCHED_HOLDS=""
  [ -n "${SCHED_PLAN:-}" ] && [ "$POKER_RUN_OPEN" != unreadable ] || return 0
  _fill_current_load "$SCHED_PLAN"
  step="$(fill_step_token "$SCHED_PLAN")"
  [ -z "$step" ] || SCHED_HOLDS="$(units_held "$SCHED_PLAN" "$step" 2>/dev/null)"
  while IFS= read -r hold; do
    case "$hold" in
      *": held by ext:"*) say "HELD ${hold%%: held by *} ${hold#*: held by }" ;;
    esac
  done <<EOF
$SCHED_HOLDS
EOF
  while IFS= read -r finding; do
    [ -n "$finding" ] || continue
    kind="${finding%% *}"
    rest="${finding#* }"
    val=""
    case "$rest" in *" "*) val="${rest#* }" ;; esac
    say "LEDGER ${rest%% *} ${kind}${val:+ $(clean "$val")}"
  done <<EOF
$(units_findings "$SCHED_PLAN" "$ROSTER_FILE" 2>/dev/null)
EOF
  return 0
}

# ---------------------------------------------------------------- why each row waits
#
# WAIT AND CHAIN, AFTER THE FILL DECISION (wave-26 T13; REQ-6 AC-6.6, D9). Through 1.10 a pending
# row the FILL left out appeared only in one sentence ("no pending task is ready: none has all
# its dependencies landed …"), which named no row and no read. Now every pending row the FILL did
# not offer gets one line:
#
#   poker: WAIT <id> — <reason>
#
# the reason built from `units_waiting` (lib/units.sh), one clause per unmet read, joined `; `:
#   - a read no row writes is named as itself: `approval:release`, `ext:vendor-fix`, `proof:floor`;
#   - a task id read (a table without `reads`) is `waits for T2 (active)`;
#   - any other read names its writers: `reads payload/x.sh, written by T1 (active)`;
#   - a gate act held for its step: `step 8 integrate row waits for current: 8`.
# A row that IS ready and was not offered says why: the writer gap is closed, or the standing
# fill-declined answered it. Then one line for the longest remaining chain over the pending and
# active rows — sizes from the `size` column (its leading digits, minutes), edges from
# `units_edges`, through `units_chain` at the plan's writer ceiling:
#
#   poker: CHAIN <id>→<id>… (<n> min)
#
# A chain `units_chain` refuses (a cycle) is printed as unknown with its reason, never dropped.
# Called inside the scheduler's one parse of the table (`tick_plan_memoised`), so the rows, the
# waiting reads, the edges and the ready set are one reading.
tick_wait_report() {  # -> says the WAIT lines and the CHAIN line; reads SCHED_* the FILL arm set
  local rows waiting all offered line chain ids mins
  [ -n "${SCHED_PLAN:-}" ] && [ -n "${SCHED_STEP:-}" ] || return 0
  rows="$(units_rows "$SCHED_PLAN" 2>/dev/null)" || return 0
  [ -n "$rows" ] || return 0
  waiting="$(units_waiting "$SCHED_PLAN" "$SCHED_STEP" 2>/dev/null)"
  all="${SCHED_READY_ALL:-}"
  offered="$(printf '%s' "${SCHED_READY:-}" | tr '\n' ' ')"
  while IFS= read -r line; do
    [ -n "$line" ] && say "WAIT $(clean "$line")"
  done <<TICK_WAIT
$(printf '\034rows\n%s\n\034wait\n%s\n' "$rows" "$waiting" | awk -F'\t' \
    -v offered=" $offered " -v all=" $all " -v declined=" ${SCHED_SD_IDS:-} " -v gap="${SCHED_GAP:-0}" '
  $0 == SUBSEP "rows" { part = 1; next }
  $0 == SUBSEP "wait" { part = 2; next }
  part == 1 && $1 != "" { n++; id[n] = $1; knd[$1] = $3; st[$1] = $10; next }
  part == 2 && $1 != "" {
    key = $1 SUBSEP $2
    if (!(key in seen)) { seen[key] = 1; nr[$1]++; rd[$1, nr[$1]] = $2 }
    if ($3 != "-") { nw[key]++; wid[key, nw[key]] = $3; wst[key, nw[key]] = $4 }
    next
  }
  END {
    for (k = 1; k <= n; k++) {
      i = id[k]
      if (st[i] != "pending" || index(offered, " " i " ")) continue
      reason = ""
      if (nr[i] > 0) {
        for (m = 1; m <= nr[i]; m++) {
          r = rd[i, m]; key = i SUBSEP r
          if (substr(r, 1, 5) == "step:") {
            p = substr(r, 6); t = "step " p " " knd[i] " row waits for current: " p
          } else if (nw[key] == 0) {
            t = r
          } else if (nw[key] == 1 && wid[key, 1] == r) {
            t = "waits for " r " (" wst[key, 1] ")"
          } else {
            t = "reads " r ", written by "
            for (w = 1; w <= nw[key]; w++) t = t (w > 1 ? ", " : "") wid[key, w] " (" wst[key, w] ")"
          }
          reason = reason (reason == "" ? "" : "; ") t
        }
      } else if (index(all, " " i " ")) {
        if (index(declined, " " i " ")) reason = "ready; answered by the standing fill-declined"
        else reason = "ready; no writer slot free (gap " gap ")"
      } else continue
      printf "%s — %s\n", i, reason
    }
  }')
TICK_WAIT
  chain="$( { printf '%s\n' "$rows" | awk -F'\t' '$10 == "pending" || $10 == "active" {
                m = 0; if (match($7, /^[0-9]+/)) m = substr($7, RSTART, RLENGTH)
                printf "N\t%s\t%d\n", $1, m }'
              units_edges "$SCHED_PLAN" 2>/dev/null | awk -F'\t' 'NF >= 2 { printf "E\t%s\t%s\n", $1, $2 }'
            } | units_chain "${SCHED_WRITERS:-$(printf '%s\n' "$rows" | grep -c .)}" 2>&1 )" || {
    say "CHAIN unknown — $(clean "$chain")"
    return 0
  }
  line="$(printf '%s\n' "$chain" | awk -F'\t' '$1 == "chain" { print $2 "\t" $3; exit }')"
  ids="${line%%$'\t'*}"; mins="${line##*$'\t'}"
  [ -n "$ids" ] || return 0
  say "CHAIN ${ids//,/→} (${mins} min)"
}

# THE PRIORITY A RECORD NEVER STATES (wave-28 T15; D19, AC-8.3). A rated reading writes the plan's
# `deferred:` and `check:` lines at registration; the tick prints each such finding once, with the
# priority the table gives its rating (lib/proof.sh `proof_findings_owed`, which `release-check`
# prints too):
#
#   poker: FINDING <record>#<n> <S> <reach> <fix|defer|note> "<title>"
#
# Silent on a plan that carries none. Called beside the WAIT lines, on the scheduler's one parse.
tick_finding_report() {  # -> says one FINDING line per finding the plan defers or owes a check for
  local line
  [ -n "${SCHED_PLAN:-}" ] && [ -f "$SCHED_PLAN" ] || return 0
  /usr/bin/grep -qE '^(deferred|check):[[:space:]]' "$SCHED_PLAN" 2>/dev/null || return 0
  declare -F proof_findings_owed >/dev/null 2>&1 \
    || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh" 2>/dev/null; }
  declare -F proof_findings_owed >/dev/null 2>&1 || return 0
  while IFS= read -r line; do
    [ -n "$line" ] && say "FINDING $(clean "$line")"
  done <<TICK_FINDINGS
$(proof_findings_owed "$SCHED_PLAN" 2>/dev/null)
TICK_FINDINGS
}

# tick_plan_memoised <command> [args…] -> runs the command with the bound plan's table parsed
# once for everything it asks (`units_memoised`, payload/scripts/lib/units.sh); a tick with no
# readable plan runs it bare, since there is no table to hold.
tick_plan_memoised() {
  if [ -n "${SCHED_PLAN:-}" ] && [ "$POKER_RUN_OPEN" != unreadable ]; then
    units_memoised "$SCHED_PLAN" "$@"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------- the agent name
#
# THE NAME A DISPATCH USES IS DERIVED, NEVER CHOSEN (T22, A-orch-33; Chris, first
# principles: the roster is the identity register).
#
# `fill_name` AND ITS REASONING MOVED TO payload/scripts/lib/fill.sh (wave-18 REQ-3, D2).
# It went where the ready set went: `payload/scripts/lib/stop.sh`'s fill duty names rows this
# tick may also have printed, and a second idea of which name is free would let the two
# disagree about what "dispatch T5" means. The body is unchanged, and the tick and `adopt`
# call it exactly as they did.

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
  # THE C1 BLOCK GOES TOO (Step-6 security review S-6). `tr -d '\000-\010\013-\037\177'`
  # removes ESC and DEL and leaves `U+0080`–`U+009F` — of which `U+009B` is CSI, a control
  # sequence introducer that needs no ESC in front of it on a terminal that honours C1. Those
  # arrive as the two UTF-8 bytes `0xC2 0x80`–`0xC2 0x9F`, which a byte-oriented `tr` cannot
  # name, so the pair is deleted by `sed` before the byte-wise strip runs. Ordered first
  # because the byte strip would otherwise leave a bare `0xC2` behind.
  printf '%s' "$raw" | jq -r '.' 2>/dev/null \
    | LC_ALL=C sed 's/'"$(printf '\302')"'['"$(printf '\200')"'-'"$(printf '\237')"']//g' \
    | tr -d '\000-\010\013-\037\177' | head -c "$ADOPT_TAIL_CAP"
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
#   A ROW IS CLOSED BY AN ACK TAKEN AFTER ITS LATEST LAUNCH, and by nothing else — the one
#   close predicate, `roster_open_names` (payload/scripts/lib/roster.sh; epic-23 wave-20 T2,
#   D10; ADR-034 d1), which dispatch preflight, the sweeper's `acked=` and the stop wall's
#   occupancy ask too. The ack ledger binds across sessions ("an ack taken in a session that
#   has since died is still in force in its successor"). A `landing-swept/v1` marker closes
#   NOTHING here, MET or not: until wave-20 a MET marker did, so an agent swept MET and never
#   acked — still alive on the panel — came out of a `/clear` with no row on the new roster,
#   and no stop could reach it (the code in `roster_open_names` is the rule). An ack older than a
#   relaunch closes nothing either: the relaunched agent is the one to adopt.
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
adopt_fold() {  # <roster file> <ack ledger> -> name|id|type|deliverable|progress|cadence|launched_at|origin|plan|waiver|files|suites_allowed|suites_source|re_executes|done
  # THE OPEN SET IS ASKED ONCE, of the one predicate, over the predecessor's roster as it
  # stands — no session filter, because every row on it carries the predecessor's own id.
  # Handed to awk through the environment rather than `-v`, which would read a backslash in
  # a name as an escape.
  AF_OPEN="$(roster_open_names "$1" "$2")" awk '
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
      no = split(ENVIRON["AF_OPEN"], ol, "\n")
      for (i = 1; i <= no; i++) if (ol[i] != "") isopen[ol[i]] = 1
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
      # THE WAIVER, carried forward the same way the contract fields are (S17, AC-12 attempt
      # 2). Before this fix it was the one field this fold read off the source row and then
      # dropped: `adopt_write_row` hard-coded `waiver=` empty on every adopted row, so a
      # dispatch this session waived at launch came out the far side of a clear looking like
      # one that never was — the `verdict_row` function in hooks/session-sweeper.sh reads
      # `waiver=` straight off the row (no marker involved) and calls a non-empty one WAIVED
      # before it ever asks about a deliverable, so an empty copy verdicted as an unmet
      # SILENT row instead.
      v = kv($0, "waiver");        if (v != "") waiv[n]   = v
      # THE THREE INSTRUMENT FIELDS (wave-01 S13, spec AC-20), carried forward exactly as
      # the contract fields above are. They are what the writer-side budget guard reads:
      # a resumed agent whose adopted row lost `suites_allowed=` would come out of a
      # /clear with no budget on it, and the wall that refuses an off-budget suite would
      # go quiet for exactly the agents a clear leaves running longest.
      v = kv($0, "files");          if (v != "") files[n]  = v
      v = kv($0, "suites_allowed"); if (v != "") sallow[n] = v
      v = kv($0, "suites_source");  if (v != "") ssrc[n]   = v
      # THE DECLARED RUNS (REQ-1 AC-1.1, this wave). A trailing optional field carried
      # forward exactly as the three instrument fields above are, and for the same reason:
      # it is a BUDGET declaration, and the writer-side guard reads it off the row for the
      # agent own id. A resumed writer whose adopted row lost it comes out of a clear with
      # no budget on it. An apostrophe cannot appear in this comment: the awk program is one
      # single-quoted argument.
      v = kv($0, "re_executes");    if (v != "") rex[n]    = v
      # THE DONE MARKER (wave-24 T9, D3): the same contract, so its completion signal too.
      v = kv($0, "done");           if (v != "") dmark[n]  = v
      # THE ATTRIBUTION, carried forward exactly as the contract fields are. It is the bound
      # plan of the session that dispatched the row, stamped at the instant the row was
      # written (hooks/dispatch-preflight.sh). Rows written before this wave carry no such
      # field at all — a THIRD state, not an empty plan, and the caller partitions on the
      # difference (spec AC-2, A2). An apostrophe cannot appear in this comment: the awk
      # program is one single-quoted argument.
      if (index($0, "|plan=") > 0) { plan[n] = kv($0, "plan"); hasplan[n] = 1 }
      st = kv($0, "status")
      if (st == "identified" || st == "confirmed") {
        v = kv($0, "agent_id"); if (v != "") id[n] = v
      }
      next
    }
    END {
      for (i = 1; i <= cnt; i++) {
        n = order[i]
        if (!(n in isopen)) continue
        printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n", n, id[n], stype[n], deliv[n], prog[n], cad[n], \
               launch[n], ((n in afrom) ? afrom[n] : sess[n]), \
               ((n in hasplan) ? (plan[n] == "" ? "none" : plan[n]) : ""), waiv[n], \
               files[n], sallow[n], ssrc[n], rex[n], dmark[n]
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
#   waiver=             S17 (AC-12 attempt 2). Copied forward for the same reason: it is a
#                       contract field, and `hooks/session-sweeper.sh verdict_row` reads it
#                       directly off THIS row (no marker involved) to decide WAIVED before it
#                       ever looks at a deliverable. A row with a real waiver and an empty
#                       copy of it verdicts as if the waiver had never been declared.
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
#
# THE ROW CARRIES THE ADOPTING SESSION'S BINDING, in the same trailing `plan=` field
# hooks/dispatch-preflight.sh:1703 writes on the rows it creates — one field name, one
# position, two writers (spec §Ownership table, "roster attribution"; cross-gate §RA).
# Without it an adopted row was the one row on any roster with no attribution at all, so a
# THIRD session bound to the same plan re-read this session's own adoption as
# `unattributed` and declined to take it: the partition would quietly stop working exactly
# where two sessions hand a run back and forth. The value is the ADOPTER's binding, because
# the adopter is now the session that owns the row — the launching session is already
# recorded, separately, in `adopted_from=`.
adopt_write_row() {  # <roster file> <sid> <name> <id> <type> <deliverable> <progress> <cadence> <launched> <from-sid> <teammate address> <plan|none> <waiver> <files> <suites_allowed> <suites_source> <re_executes> [<done>] -> 0 written/already there, 1 not
  local f="$1" sid="$2" name="$3" id="$4" typ="$5" deliv="$6" prog="$7" cad="$8"
  local launch="$9" osid="${10}" addr="${11}" plan="${12:-none}" waiver="${13:-}" d
  local files="${14:-}" sallow="${15:-}" ssrc="${16:-}" rex="${17:-}" dmark="${18:-}"
  local -a RR_ARGS
  local ROW=""
  local -a INSTRUMENT_FIELDS
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
  # A LIVE NAME NEVER GETS A SECOND LIVE ROW (T6, AC-6.1; research R1 §5). The idempotence
  # check above is by agent_id — a SECOND agent, under a DIFFERENT id, adopted under the SAME
  # name is not caught by it, and two live rows of one name is exactly the ambiguity
  # `hooks/stop-guard.sh`'s own stop refusal exists to police (T29 §7). `live_ids_of_name` is
  # that refusal's own predicate, moved to the one library both files source
  # (`payload/scripts/lib/roster.sh`): a non-empty answer means this name is already live
  # here, so this adopt takes the `-r<n>` search (`fill_name`, the fleet's one convention for a
  # spent id, payload/scripts/lib/fill.sh) instead of the name it was asked for, and says so once
  # on stderr — this call site is otherwise silent.
  local ROSTER_FILE="$f"
  if [ -n "$(live_ids_of_name "$name")" ]; then
    local renamed
    renamed="$(fill_name "$f" "$name")"
    if [ -n "$renamed" ] && [ "$renamed" != "$name" ]; then
      echo "adopt: '${name}' is already live on this session's roster — writing this row as '${renamed}'" >&2
      name="$renamed"
    fi
  fi
  mkdir -p "$d" 2>/dev/null || return 1
  if [ ! -e "$f" ]; then
    roster_header >> "$f" 2>/dev/null && chmod 600 "$f" 2>/dev/null
  fi
  # EVERY FIELD THROUGH `clean()`, `session=` INCLUDED (Step-6 security review S-4). It was
  # the one interpolation of the thirteen that took its value raw, which is character for
  # character the defect this wave fixed on the other row writer one task earlier
  # (hooks/dispatch-preflight.sh: "a value carrying a `|` or a newline forges a segment …
  # the asymmetry between the two writers was itself the defect"). Every by-key reader in
  # the fleet takes the FIRST match, so a forged `name=` ahead of the real one wins outright.
  # Unreachable today — `engaged_marker_path` refuses a session id outside `[A-Za-z0-9_-]`
  # before any verb decides anything — and that is a guard in another file for another
  # reason, not this writer's own.
  #
  # THE THREE INSTRUMENT FIELDS TRAVEL AS A GROUP, AND ONLY WHEN THE SOURCE ROW HAD THEM
  # (wave-01 S13, spec AC-20). `roster_row` emits them present-if-PASSED, and the
  # distinction is load-bearing at the writer-side guard: a row with `suites_allowed=`
  # empty stated a budget that came out empty, while a row with no such key at all was
  # written before the wall existed. Adopting the second kind must not manufacture the
  # first. All three go or none do — an empty member of a stated group is itself a
  # statement, and splitting them would let a resumed row claim a source for a set it
  # does not carry.
  INSTRUMENT_FIELDS=()
  if [ -n "$files" ] || [ -n "$sallow" ] || [ -n "$ssrc" ]; then
    INSTRUMENT_FIELDS=("files=$(clean "$files" files)" \
                       "suites_allowed=$(clean "$sallow" suites_allowed)" \
                       "suites_source=$(clean "$ssrc")")
  fi
  # THE ROW IS BUILT BY `roster_row` (payload/scripts/lib/roster.sh), not by a format string
  # here (spec AC-25, ledger D3). The eleven fields this writer leaves EMPTY are still named
  # — `model=`, `duration=`, `claims=`, `absent=` and the rest — because an omitted key and
  # an empty one are different rows to a by-key reader, and this writer has always emitted
  # both of the fields no other writer does (`teammate_id=`, `adopted_from=`), empty address
  # included. `clean()` stays here: it is this file's cap on a value, while the row's SHAPE
  # is the library's.
  RR_ARGS=(
    status=identified
    "session=$(clean "$sid")"
    "name=$(clean "$name")"
    "agent_id=$(clean "$id")"
    "launched_at=$(clean "$launch")"
    "subagent_type=$(clean "$typ")"
    model=
    "deliverable=$(clean "$deliv")"
    source=adopted
    duration=
    "progress=$(clean "$prog")"
    claims=
    "cadence=$(clean "$cad")"
    absent=
    "waiver=$(clean "$waiver")"
    ${INSTRUMENT_FIELDS[@]+"${INSTRUMENT_FIELDS[@]}"}
    ${dmark:+"done=$(clean "$dmark")"}
    "teammate_id=$(clean "$addr")"
    "adopted_from=$(clean "$osid")"
    tool_use_id=
    "plan=$(clean "$plan")"
  )
  # THE DECLARED RUNS, CARRIED BY NAME (REQ-1 AC-1.1's adopt half). `re_executes=` is a
  # trailing optional field of the row, and the row's SHAPE is `roster_row`'s — so it is
  # passed there first and appended here only if that writer does not know the key yet.
  # `roster_row` returns 2 on an unknown key rather than emitting a row, and dropping the
  # field on that answer would hand a resumed writer an empty budget: the exact failure the
  # three instrument fields are carried forward to prevent. The fallback is a TRAILING
  # append, which is where the field lives either way, and every reader in the fleet reads a
  # row BY KEY — so the two spellings differ in position and in nothing a reader sees.
  #
  # THE FIELD NAME IS PASSED (T4, REQ-7/D4) so `clean` decodes the stored form and skips
  # the 400-character cut — see its own comment. The value below is therefore the command
  # as the brief spelled it, and `roster_row` encodes it again on the way out. The fallback
  # branch bypasses that writer, so it encodes the value itself rather than appending a raw
  # pipe that would forge a segment on the line it is appending to.
  if [ -n "$rex" ]; then
    local _rex_plain; _rex_plain="$(clean "$rex" re_executes)"
    ROW="$(roster_row "${RR_ARGS[@]}" "re_executes=$_rex_plain")" || ROW=""
    if [ -z "$ROW" ]; then
      ROW="$(roster_row "${RR_ARGS[@]}")" || return 1
      ROW="${ROW}|re_executes=$(roster_pipe_escape "$_rex_plain")"
    fi
  else
    ROW="$(roster_row "${RR_ARGS[@]}")" || return 1
  fi
  [ -n "$ROW" ] || return 1
  printf '%s\n' "$ROW" >> "$f" 2>/dev/null || return 1
  return 0
}

# THE MARKER COPY (S17, AC-12 attempt 2) — the other half of the contract-verdict fix beside
# the waiver above. `adopt_write_row` puts the row on this session's roster; this puts the
# SOURCE roster's own landing verdict for that name beside it, verbatim, so a reader that
# trusts the marker rather than re-deriving from disk (`hooks/session-start.sh`'s
# `open_rows`, which scans the roster it was handed for a `landing-swept/v1|…|name=<X>|`
# line) sees the same answer on the successor that stood on the predecessor.
#
# payload/scripts/lib/stop.sh (`stop_landing_gate`, reached from hooks/stop.sh) is this
# schema's one ORIGINATING writer. This call site is the second writer, made deliberately
# narrow: it never COMPUTES a verdict, it only APPENDS a line that
# writer already produced, byte for byte, off the source roster this verb is only ever
# permitted to read (never write — the row above is still the one file this verb writes to).
#
# THE LATEST LINE, because the marker stream is append-only the same way the roster is: a
# name can be superseded (UNMET -> MET) and the last line wins. `adopt_fold` excludes a
# closed name through the same `roster_open_names` predicate (an ack later than the row's
# launch), not a `met[]` filter, so a name that reaches this call was never offered one to
# adopt in the first place, and the only history left to find is whatever the source
# roster's own ack state has not yet closed.
#
# IDEMPOTENT BY EXACT-LINE PRESENCE, the same posture `adopt_write_row` takes: the source
# session is the one and only writer of ITS OWN marker lines, so a line copied once from it
# never changes shape on a later read, and comparing the verbatim text is enough to know this
# adopt already carried it.
adopt_copy_marker() {  # <source roster> <own roster> <name> -> 0 copied/already there, 1 nothing to copy
  local src="$1" own="$2" name="$3" line
  [ -n "$name" ] && [ -f "$src" ] && [ ! -L "$src" ] || return 1
  # THE SHARED CONSTANT (declared above), NOT A SECOND SPELLING (S15, AC-26). This used to
  # grep the bare literal 'landing-swept/v1' — see the constant's own comment for why a
  # literal here was the exact hazard research-code-map §2.c named.
  line="$(grep "^${SWEPT_SCHEMA}|" "$src" 2>/dev/null | grep -F "|name=${name}|" | tail -1)"
  [ -n "$line" ] || return 1
  grep -qF "$line" "$own" 2>/dev/null && return 0
  [ -f "$own" ] && [ ! -L "$own" ] || return 1
  printf '%s\n' "$line" >> "$own" 2>/dev/null || return 1
  return 0
}

# TWO PLAN PATHS ARE THE SAME PLAN when they name the same file, and the two sides of the
# comparison come from different writers: the caller's marker holds whatever `bind_plan` was
# given, while a roster row holds whatever `session_plan` returned in the session that
# dispatched it. A worktree cwd, a `/tmp` that is really `/private/tmp`, a `.`/`..` in the
# middle — each of those makes two spellings of one file, and a string compare would call the
# row another run's and refuse to adopt this session's own agent.
#
# ONE SITE, AND IT IS `_bind_resolve` (AC-23). This function used to carry its own copy of
# the "resolve the directory, leave the leaf" rule, and `bind` carried a third — three
# canonicalizers that agreed in the middle and disagreed at every edge: `_bind_resolve`
# refuses a relative path, this one degraded to the raw string, bind's degraded to EMPTY.
# The divergence was latent only because `bind_plan` stores the canonical spelling, so
# nothing yet compared two spellings that had been through different resolvers. The next
# comparison added on either side would have been the bug.
#
# THE DIRECTORY IS RESOLVED AND THE LEAF IS NOT — the rule's reason is stated at
# payload/scripts/lib/binding.sh: `find` does not resolve leaves either, so resolving this
# one would make a plan reached through a symlink compare unequal to the same plan as
# `open_runs` reports it. A trailing slash is stripped by that function's `dirname`/
# `basename` split, which is why `<p>/a.md` and `<p>/a.md/` land on one spelling here.
#
# RELATIVE IS MADE ABSOLUTE FIRST, because `_bind_resolve` refuses a relative operand
# outright (binding.sh:57) and a roster row may carry either. The base is the CALLER'S cwd,
# which is what this function resolved against before — a change of base would silently
# re-attribute rows written by a session standing somewhere else.
#
# IT NEVER FAILS. An unresolvable directory — a plan whose tree has since been removed —
# degrades to the raw string, which still compares equal to an identical raw string. A
# comparison that errored here would silently turn every row unattributable.
adopt_plan_key() {  # <plan path> -> a comparable spelling of it
  local p="$1" out
  [ -n "$p" ] || { printf ''; return 0; }
  case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
  out="$(_bind_resolve "$p")" || { printf '%s' "$1"; return 0; }
  printf '%s' "$out"
}

# A roster path is absolute or project-relative, exactly as the row's writer left it.
adopt_abs() {  # <path> <repo root>
  case "$1" in
    /*) printf '%s' "$1" ;;
    '') : ;;
    *)  printf '%s/%s' "$2" "$1" ;;
  esac
}

# ---------------------------------------------------------------- is this session's residue gone?
#
# THE SWEEP'S OWN QUESTION, ASKED OF ONE SESSION (REQ-9 AC-9.1; D10). `adopt` offered every
# row on every roster in the project, so a wave released two days ago was still offering its
# agents at every resume. A session nobody can act on, whose state files the next
# SessionStart deletes, has nothing left to adopt — and the two halves of that sentence are
# the two facts the `sweep` verb already decides with: the session is not in
# `patrol_live_session_ids`, and its own newest state file is older than the window a
# windowed sweep defers inside.
#
# BOTH HALVES, NEVER ONE. Deadness alone is the WRONG answer here and would break the verb's
# whole purpose: a `/clear` leaves the predecessor id dead within seconds while its roster is
# the freshest file in the directory, and that is precisely the roster `adopt` exists to read.
# The sweep defers exactly that session (hooks/session-start.sh passes `--window`), so this
# verb defers with it and the two agree by construction.
#
# THE LIVE SET IS RESOLVED ONCE PER RUN, by the caller, and handed in: it reads one file per
# running process out of the claude home and is the same answer for every roster in the walk.
#
# A SESSION WHOSE FILES CANNOT BE STAT'D AT ALL is treated as old enough, exactly as the
# sweep treats it (its own comment: an age gate exists to protect a session that JUST died,
# not to withhold state this verb can no longer measure).
adopt_residue_swept() {  # <root> <sid> <live id list> <window s> <now> -> 0 the sweep would take it
  local root="$1" sid="$2" live="$3" window="$4" now="$5" f mt newest=0
  [ -n "$sid" ] || return 1
  case "
$live
" in
    *"
$sid
"*) return 1 ;;
  esac
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    mt="$(file_mtime "$f")"
    case "$mt" in ''|*[!0-9]*) continue ;; esac
    [ "$mt" -gt "$newest" ] && newest="$mt"
  done <<EOF
$(patrol_session_state_files "$root" "$sid")
EOF
  [ "$newest" -gt 0 ] && [ $(( now - newest )) -lt "$window" ] && return 1
  return 0
}

# ---------------------------------------------------------------- is this row too quiet?
#
# ONE PREDICATE, AND IT IS THE LIBRARY'S (REQ-10 AC-10.1; D9). The tick used to decide a row
# needed surfacing from `duration=` alone, while skills/canonical-sdlc/dispatch.md promised
# the opposite in so many words: "a row is quiet when it is quieter than the `cadence` its own
# brief declared". Nothing in the tick opened the progress artifact or the transcript. This
# function is the missing read, and it is `observe_class`'s answer rather than a fifth
# arithmetic: the row's declared cadence, both activity channels, one window.
#
# THE WINDOW IS ONE CADENCE, not two. `adopt` doubled it on the reasoning that a row
# promising a line every ten minutes is, at any random instant, up to ten minutes stale while
# perfectly healthy — true, and the library's own answer to it is the same one the liveness
# contract ratified: "too quiet" means quieter than the AUTHOR'S OWN declaration, and an
# author who wants slack declares it. Two readers, one number (D9).
#
# WHAT IS RESET, AND WHY ALL OF IT. `observe_class` reads six globals that `observe_agent`
# normally fills. This caller already holds the row, so it fills them itself and clears every
# one first: a value left over from the previous row would be read as this row's evidence.
#
# NOTHING OBSERVED IS NOT SILENCE (exit 2). A row that declared no progress artifact and
# whose agent has no transcript on disk offers no mtime to measure or to print — and a NOTIFY
# that names no evidence is the noise this read exists to replace. The duration arm still
# answers for such a row.
#
# THE DELIVERY STATE IS `none` DELIBERATELY. `observe_class` ranks `delivered` above `alive`,
# and this caller is inside the UNMET arm of a verdict the sweeper has already taken over the
# same contract — re-deriving delivery from disk here would be a second answer to a question
# one owner already answered (D0).
# THE PROJECT DIRECTORY A SESSION'S LOGS LIVE UNDER (D8; REQ-8; epic-23 wave-20 T5). One
# level above `<project-dir>/<session-id>/subagents/…` — the directory `agent_log_newest`
# (payload/scripts/lib/observe.sh) globs. Tried through the session's own transcript first
# (`<project-dir>/<sid>.jsonl`, the ordinary case), falling back to the parent of its
# subagents directory: a session's `.jsonl` can be reclaimed while its directory survives
# (`session_subagent_dir`'s own comment). Returns nothing when neither resolves.
agent_project_dir_for() {  # <session-id> -> project directory on stdout, nonzero if unresolved
  local sid="$1" tx sub
  [ -n "$sid" ] || return 1
  tx="$(session_transcript "$sid")" && { printf '%s\n' "${tx%/*}"; return 0; }
  sub="$(session_subagent_dir "$sid")" && { printf '%s\n' "${sub%/*/*}"; return 0; }
  return 1
}

# THE SHARED NEWEST-LOG PREFERENCE (D8; REQ-8; epic-23 wave-20 T5; supersedes the T1d
# this-session/adopted_from chain, walk W-3). An ADOPTED row's transcript lives under
# whichever session last spoke to the agent — and after a SECOND `/clear` that can be an
# INTERMEDIATE adopter this row names nowhere, because `adopted_from=` always names the
# ORIGINAL launcher. `agent_log_newest` globs every session directory of the project for
# the exact agent id and returns the newest by mtime, so no chain of sessions has to be
# walked and no intermediate adopter can be missed. Both readers of the working log —
# `row_quiet` (the tick's own liveness read) and `adopt`'s report (the ADOPT_SCHEMA block
# below) — call it through this project-directory resolution.

TICK_QUIET_MTIME=""; TICK_QUIET_CHANNEL=""; TICK_QUIET_AGE=""; TICK_QUIET_CAD=""
row_quiet() {  # <roster-state row> <now epoch> -> 0 quiet, 1 alive, 2 nothing to observe
  local row="$1" now="$2" cad cad_s prog pm=0 id proj tx lm=0

  TICK_QUIET_MTIME=""; TICK_QUIET_CHANNEL=""; TICK_QUIET_AGE=""; TICK_QUIET_CAD=""
  OBS_DELIV_STATE=none
  OBS_LOG_MTIME=0; OBS_LOG_AGE=0
  OBS_PROGRESS_STATE=unnamed; OBS_PROGRESS_AGE=0
  OBS_CADENCE_S="$OBSERVE_CADENCE_DEFAULT_S"

  # THE DECLARED CADENCE, and the library's own fallback when the row declared none or
  # declared it unreadably — the same default `observe_agent` applies, for the same reason:
  # a guess about the number is worse than the rule the liveness contract widened.
  cad="$(line_field "$row" cadence)"
  if [ -n "$cad" ]; then
    cad_s="$(parse_seconds "$cad")" && [ -n "$cad_s" ] && OBS_CADENCE_S="$cad_s"
  fi
  TICK_QUIET_CAD="$OBS_CADENCE_S"

  # CHANNEL 1 — the contracted progress artifact, as the row spells it.
  prog="$(adopt_abs "$(line_field "$row" progress)" "$REPO_REAL")"
  if [ -n "$prog" ] && [ -f "$prog" ]; then
    OBS_PROGRESS_STATE=present
    pm="$(file_mtime "$prog")"
    OBS_PROGRESS_AGE=$(( now - pm ))
    [ "$OBS_PROGRESS_AGE" -lt 0 ] && OBS_PROGRESS_AGE=0
  fi

  # CHANNEL 2 — the agent's own transcript, which the harness appends to on every turn it
  # takes. It is the channel a role with no Write tool has, and the one a working agent
  # cannot forget to keep. An ADOPTED row's `adopted_from=` records the session that
  # LAUNCHED it, which is where its file lives until this session speaks to the agent.
  tx=""
  id="$(line_field "$row" agent_id)"
  if [ -n "$id" ]; then
    # THE NEWEST COPY, ANYWHERE IN THE PROJECT (D8, REQ-8) — never a this-session/
    # adopted_from CHAIN. The harness files an agent's transcript under whichever session
    # is talking to it NOW, and after a SECOND `/clear` that can be an intermediate adopter
    # `adopted_from=` never names (it always names the ORIGINAL launcher) — reading only
    # the launcher's copy, or only this session's, reported a working agent quiet (R1 Q4,
    # bed3; triage-A). `adopted_from=` itself is still provenance and is never rewritten:
    # adopt's idempotence keys on it.
    proj="$(agent_project_dir_for "$SESSION_ID")" || proj=""
    tx=""
    [ -n "$proj" ] && { tx="$(agent_log_newest "$id" "$proj")" || tx=""; }
    if [ -n "$tx" ]; then
      OBS_LOG_MTIME="$(file_mtime "$tx")"
      lm="$OBS_LOG_MTIME"
      OBS_LOG_AGE=$(( now - OBS_LOG_MTIME ))
      [ "$OBS_LOG_AGE" -lt 0 ] && OBS_LOG_AGE=0
    fi
  fi

  [ "$OBS_PROGRESS_STATE" = present ] || [ "$lm" -gt 0 ] || return 2

  # THE MTIME THE READER IS SHOWN is the NEWEST of the two, because that is the one the
  # verdict rests on: the row is quiet only if BOTH channels are, so the later of them is
  # what "last heard from" means. Printed as an instant and not only as an age — an age is
  # relative to a tick nobody kept.
  if [ "$lm" -gt "$pm" ]; then
    TICK_QUIET_CHANNEL="transcript $tx"
    TICK_QUIET_MTIME="$(epoch_iso "$lm")"
    TICK_QUIET_AGE="$OBS_LOG_AGE"
  else
    TICK_QUIET_CHANNEL="progress $prog"
    TICK_QUIET_MTIME="$(epoch_iso "$pm")"
    TICK_QUIET_AGE="$OBS_PROGRESS_AGE"
  fi

  [ "$(observe_class)" = idle ] && return 0
  return 1
}

# ---------------------------------------------------------------- the decision line
#
# THE TICK'S LAST LINE, AND THE ONLY PLACE THIS SCHEMA IS PRINTED (REQ-10 AC-10.2/10.4; D5).
# Four arms used to print it inline and three of them followed it with the sentence that
# explained it, so the last thing an operator read was never reliably the answer. One printer
# means one field order, one place a field is added, and a caller that cannot print its
# sentence afterwards by accident.
#
# `decision=` IS THE RANKED MAXIMUM DISARM > NOTIFY > FILL > QUIET. Each band is raised by a
# fact this tick computed; the highest wins the field and every lower one keeps its own, so a
# tick that ordered work and found an overdue row reports both rather than whichever arm ran
# first. DISARM is terminal and exits above the fold, so the fold there is over three.
#
# THE SCHEMA NAME IS UNCHANGED AND THE NEW FIELDS ARE TRAILING (A2). `fill=` and `trees=`
# print only when they carry something: a reader that does not know them is inert to them,
# and the existing `decision=|total=|open=` run stays byte-adjacent for the readers that
# match on it (tests/cross-gate-agreement.test.sh's `la6_open_tick`). `rows=`/`detail=` keep
# their positions, which is why they are passed through this printer rather than appended by
# the NOTIFY arm. `gate=` (wave-25 T5; D7) is the last of them: how many reserved requests this
# tick raises and their categories, `gate=1:leaves-the-machine`.
tick_decision_line() {  # <decision> <total> <open> [rows] [detail] [fill ids] [tree paths] [gate]
  local line
  line="$(printf '%s|at=%s|session=%s|decision=%s|total=%s|open=%s' \
    "$POKER_DECISION_SCHEMA" "$(iso_now)" "$SESSION_ID" "$1" "$2" "$3")"
  [ -n "${4:-}" ] && line="${line}|rows=${4}"
  [ -n "${5:-}" ] && line="${line}|detail=${5}"
  [ -n "${6:-}" ] && line="${line}|fill=${6}"
  [ -n "${7:-}" ] && line="${line}|trees=${7}"
  [ -n "${8:-}" ] && line="${line}|gate=${8}"
  printf '%s\n' "$line"
}

# A FACT, NOT AN ALARM (REQ-10 AC-10.3/10.4; D5). Three things the tick knows and nobody can
# act on differently for knowing them — a standing worktree, a panel too stale to write
# against, a plan with no budget — used to print as ordinary lines, two of them BELOW the
# decision. `poker: note:` is what a fact gets, and every note prints above the decision line.
note() { printf 'poker: note: %s\n' "$1"; }

# ---------------------------------------------------------------- a successor row
#
# ONE COPY OF A ROW, FOR THE TWO VERBS THAT APPEND ONE (wave-20 T9; research D2 REQ-4).
# `extend` and `amend` both write a row for a name that already has one, and they differ
# only in what they override: `extend` a fresh launch instant and its reason, `amend` the
# three instrument fields and its reason. `roster_row` assigns its arguments in order, so a
# caller overrides a field by passing it again AFTER these. Every field is copied verbatim
# but the session (the caller's own key) and `re_executes=`, which the row stores encoded
# and `roster_row` encodes again, so it goes back plain (`clean … re_executes`, the same
# decode `adopt_write_row` takes). The present-if-passed fields travel only when the source
# row had them, the discipline `adopt_write_row`'s INSTRUMENT_FIELDS group keeps: an absent
# key and a present-but-empty one are different rows to a by-key reader. The two audit keys
# (`amended=`, `extended=`) are NOT copied — each belongs to the row that did the act, and
# the history is the row sequence.
# THE DONE MARKER TRAVELS with `hold` and `amend`, which continue the contract, and not with
# `extend`, which re-opens it for new work signalled afresh (wave-24 T9, D3; A-orch-31): the
# verdict reads the latest row, so a copy that dropped `done=` would un-say a finished agent.
ROW_COPY_ARGS=()
row_copy_args() {  # <row> <session id> [drop-done] -> sets ROW_COPY_ARGS
  local row="$1" k
  ROW_COPY_ARGS=("session=$2")
  for k in status name agent_id launched_at subagent_type model deliverable source duration \
           progress claims cadence absent waiver tool_use_id plan; do
    ROW_COPY_ARGS+=("$k=$(line_field "$row" "$k")")
  done
  # `questions=` too (wave-27 T34; T15's report item 2, A-orch-73): a reader's questions are part
  # of its contract, so the amend, hold and extend rows keep them.
  for k in files suites_allowed suites_source teammate_id adopted_from questions; do
    row_has_key "$row" "$k" && ROW_COPY_ARGS+=("$k=$(line_field "$row" "$k")")
  done
  # `row=` and `lands_on=` too (wave-28 T7; D4, D17): the row a dispatch binds and the suites it
  # lands on are its contract, read off its latest row, so an amended, held or extended row keeps them.
  for k in row lands_on; do
    row_has_key "$row" "$k" && ROW_COPY_ARGS+=("$k=$(line_field "$row" "$k")")
  done
  # `pushed=` too (wave-28 T15; A-orch-9): what a reader was pushed at start decides how its record
  # is read (lib/proof.sh `proof_pushed_severity`), so an amended, held or extended reader row keeps
  # it. Only where `roster_row` knows the key (wave-28 T16), so a copy never fails on it.
  if row_has_key "$row" pushed && roster_row pushed=x >/dev/null 2>&1; then
    ROW_COPY_ARGS+=("pushed=$(line_field "$row" pushed)")
  fi
  if [ "${3-}" != drop-done ] && row_has_key "$row" done; then
    ROW_COPY_ARGS+=("done=$(line_field "$row" done)")
  fi
  if row_has_key "$row" re_executes; then
    ROW_COPY_ARGS+=("re_executes=$(clean "$(line_field "$row" re_executes)" re_executes)")
  fi
  return 0
}

# ---------------------------------------------------------------- the hold's fingerprint
#
# A HOLD STANDS WHILE ITS FACTS DO (wave-24 T7, REQ-4; D1, ADR-041 d1). The fingerprint is the
# three facts a stand-down answer rests on: the row's launch (a re-dispatch is a new contract),
# its deliverable's mtime (a rewrite is new work), and how many completion messages the agent
# has sent (a new report is a new answer to read). It holds no instant of the tick that computed
# it, so two ticks over the same facts compute the same string. A deliverable list takes the
# newest mtime across its paths; a missing path reads 0.
#
# THE MESSAGE COUNT IS READ AS THE SWEEPER READS A REPLY (hooks/session-sweeper.sh
# `read_followups`): a `<teammate-message teammate_id="<name>">` or `<agent-message
# from="<name>">` envelope in a user record or a queued-command attachment of this session's own
# transcript, an idle notice excluded — an idle notice says a turn ended, and one arrives after
# every report, so counting it would void every hold on the agent's next idle. No transcript or
# no jq counts 0, the same on every tick, so the fingerprint stays comparable.
hold_reply_count() {  # <transcript> <name> [<teammate address>] -> the count on stdout
  local tr="$1" name="$2" tid="${3:-}"
  tid="${tid%%@*}"
  if [ -z "$tr" ] || [ ! -f "$tr" ] || ! command -v jq >/dev/null 2>&1; then
    printf '0'; return 0
  fi
  grep -F -e '<teammate-message' -e '<agent-message' "$tr" 2>/dev/null \
    | jq -R -r --arg n "$name" --arg t "$tid" '
        def replies:
          [scan("<(?:teammate-message teammate_id|agent-message from)=\"([^\"]+)\"[^>]*>((?:(?!</(?:teammate-message|agent-message)>)[\\s\\S])*)")]
          | .[]
          | select((.[1] | (fromjson? // null) | type == "object" and .type == "idle_notification") | not)
          | .[0];
        (fromjson? // empty)
        | select(type == "object" and .isSidechain != true)
        | if .type == "user" then
            (.message.content
             | if type == "string" then .
               elif type == "array" then ([.[] | select(type == "object" and .type == "text") | .text] | join("\n"))
               else "" end | replies)
          elif .type == "attachment" then
            (.attachment | select(type == "object" and .type == "queued_command")
             | .prompt | select(type == "string") | replies)
          else empty end
        | sub(" \\[[^]]*\\]$"; "") | sub("@.*$"; "")
        | select(. == $n or ($t != "" and . == $t))' 2>/dev/null \
    | awk 'END { printf "%d", NR }'
}

hold_fingerprint() {  # <roster row> <repo root> <transcript> -> <launched_at>:<mtime>:<count>
  local row="$1" repo="$2" tr="$3" deliv p m newest=0 old
  deliv="$(line_field "$row" deliverable)"
  old="$IFS"; IFS=','; set -f
  # shellcheck disable=SC2086
  set -- $deliv
  set +f; IFS="$old"
  for p in "$@"; do
    p="$(printf '%s' "$p" | sed -e 's/^ *//' -e 's/ *$//')"
    [ -n "$p" ] || continue
    case "$p" in /*) : ;; *) p="$repo/$p" ;; esac
    m=0
    [ -e "$p" ] && m="$(file_mtime "$p")"
    case "$m" in ''|*[!0-9]*) m=0 ;; esac
    [ "$m" -gt "$newest" ] && newest="$m"
  done
  printf '%s:%s:%s' "$(line_field "$row" launched_at)" "$newest" \
    "$(hold_reply_count "$tr" "$(line_field "$row" name)" "$(line_field "$row" teammate_id)")"
}

# THE IDENTITY OF A SUCCESSOR ROW (epic-23 wave-22 T1; REQ-1 AC-1.1/AC-1.2, D1; ADR-039). The
# rule is payload/scripts/lib/roster.sh's, stated once above `roster_row_for_id`: every row
# written after an agent's id is known carries that id, and the status the id was learned
# under. `row_copy_args` copies the name's LATEST row, and for a teammate that row can be the
# recorder's `status=confirmed` copy, which carries no id (the recorder learns the transcript
# id one event later and writes it on the `identified` row; the two land in either order). A
# successor copied from it had no id either, and every by-id reader — the suite-budget wall
# first — kept reading the row before it (wave-22 seed). So `extend` and `amend` append these
# three fields AFTER the copy, and `roster_row`'s last-wins assignment makes them the row's.
#
# THE SOURCE is the name's latest row whose `agent_id=` is non-empty, within the SAME DISPATCH
# CYCLE as the latest row — the same `tool_use_id=`, when the latest row carries one. A name
# dispatched again is a new agent under an old name; the earlier agent's id is not its id, and
# stamping it would hand the old id the new contract while the new agent's identification
# (which joins `intended|confirmed` rows by name) skipped the successor. No row in the cycle
# carries an id yet → nothing is appended, the copy is today's, and the recorder's
# `identified` row later inherits it whole. `teammate_id=` travels only when that row has the
# key — present-if-passed, as `row_copy_args` keeps it. On an async roster the latest row IS
# the id-bearing one, so the three values equal the copy's and the row is byte-identical.
# Sets POKER_ID too: the id the walls will key this agent on, or empty. The roster-state prefix is
# `roster_row_for_id`'s — any `roster-state/` row, not one schema — so the verb's self-check and the
# wall's pick read the same rows (wave-22 T10; review 5).
POKER_ID_ARGS=()
POKER_ID=""
identity_args() {  # <roster> <name> <the name's latest row> -> sets POKER_ID_ARGS, POKER_ID
  local tuid row
  POKER_ID_ARGS=(); POKER_ID=""
  tuid="$(line_field "$3" tool_use_id)"
  row="$(grep '^roster-state/' "$1" 2>/dev/null | grep -F "|name=${2}|" \
    | POKER_TUID="$tuid" awk -F'|' '
        { id = ""; tu = ""; gi = 0; gt = 0
          for (i = 1; i <= NF; i++) {
            if (!gi && index($i, "agent_id=") == 1)    { id = substr($i, 10); gi = 1 }
            if (!gt && index($i, "tool_use_id=") == 1) { tu = substr($i, 13); gt = 1 }
          }
          if (id != "" && (ENVIRON["POKER_TUID"] == "" || tu == ENVIRON["POKER_TUID"])) last = $0 }
        END { if (last != "") print last }')"
  [ -n "$row" ] || return 0
  POKER_ID="$(line_field "$row" agent_id)"
  POKER_ID_ARGS=("status=$(line_field "$row" status)" "agent_id=$POKER_ID")
  row_has_key "$row" teammate_id && POKER_ID_ARGS+=("teammate_id=$(line_field "$row" teammate_id)")
  return 0
}

# ---------------------------------------------------------------- the contract grammar
#
# THE DISPATCH WALL'S GRAMMAR, AT THIS FILE'S TWO DOORS (wave-20 T9; spec D4, ledger Δ10).
# `amend` widens a live contract and `task-add` writes a Files cell a brief is later built
# from; both hand what they were given to payload/scripts/lib/brief.sh's
# `brief_validate_fields`, so a contract that enters here is held to exactly a fresh
# dispatch's standard. Loaded on first use, never at the top: the tick runs every Patrol
# interval and needs none of it.
poker_brief_load() {
  declare -F brief_validate_fields >/dev/null 2>&1 && return 0
  [ -f "$BIONIC_LIB/brief.sh" ] || return 1
  # shellcheck source=/dev/null
  . "$BIONIC_LIB/brief.sh"
  declare -F brief_validate_fields >/dev/null 2>&1
}

# The sink `brief_validate_fields` calls: a finding is collected — its fact alone, and its
# fact, fix and detail as the words a refusal prints — and a loud pass is a note.
POKER_BRIEF_FACTS=""; POKER_BRIEF_WORDS=""
poker_brief_sink() {  # finding <fact> <fix> <detail> | warn <line>
  case "$1" in
    finding)
      POKER_BRIEF_FACTS="${POKER_BRIEF_FACTS}$2"$'\n'
      POKER_BRIEF_WORDS="${POKER_BRIEF_WORDS}  $2 — $3"$'\n'"$(printf '%s\n' "$4" | sed 's/^/    /')"$'\n\n'
      ;;
    warn) note "$2" ;;
  esac
}

# A brief span out of newline-joined additions: `Files:` and `Suites:` take the words as
# they are, `Re-executes:` marks each run with backticks, the one spelling the lift reads a
# run from. <runs, marked> is text already in that shape (a row's stored value).
poker_brief_span() {  # <files lines> <suites lines> <runs, marked> <runs lines> -> brief text
  local f s r="$3" line
  # Files: is a comma-separated list (wave-27 T42), so its lines join with commas: two
  # additions joined by a space would read as one item holding white space, which is prose.
  f="$(printf '%s\n' "$1" | awk 'NF { printf "%s%s", (n++ ? ", " : ""), $0 }')"
  s="$(printf '%s' "$2" | tr '\n,' '  ')"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    r="${r:+$r }\`${line}\`"
  done <<EOF
$4
EOF
  case "$f" in *[![:space:]]*) printf 'Files: %s\n' "$f" ;; esac
  case "$s" in *[![:space:]]*) printf 'Suites: %s\n' "$s" ;; esac
  [ -n "$r" ] && printf 'Re-executes: %s\n' "$r"
  return 0
}

# Order-keeping unions: the old value's members first, then each new member it lacks. A
# widening can never drop what the row already held.
poker_union() {  # <separator: , or space> <old list> <new list>... -> the union
  local sep="$1"; shift
  printf '%s\n' "$@" | awk -v sep="$sep" '
    { n = (sep == ",") ? split($0, a, ",") : split($0, a, /[ \t]+/)
      for (i = 1; i <= n; i++) if (a[i] != "" && !(a[i] in seen)) { seen[a[i]] = 1; out = out (out == "" ? "" : sep) a[i] } }
    END { print out }'
}

# The marked runs of a stored `re_executes=` value, one per line: the text between each pair
# of backticks. The same reading the budget arm takes of the field.
poker_marked_runs() {  # <runs, marked> -> one run per line
  printf '%s' "$1" | awk -F'`' '{ for (i = 2; i <= NF; i += 2) if ($i != "") print $i }'
}

# ---- BEGIN the set of an agent its start did not place (wave-27 T38; review pass 8 F3) ----
# `amend <agent id>` for an id no named row carries: see the verb. The row is the budget wall's
# alone. Its name is the id, so it shadows no other name's latest row; `status=unplaced` is no
# status a reader of live rows counts; the waiver keeps the verdict from judging a deliverable
# nobody owes. The additions are judged by the dispatch grammar, as every amend's are. The set is
# the union of the id's current one and the additions.
# A READER IS HELD TO THREE (wave-27 T74; review pass 53 B1). The role is the one the agent's start
# recorded: the `role=` of the id's last `start-unchecked/v1|event=start|` line, the line the tick's
# NOTIFY is built from. A reader there (auditor, critic, reviewer: `dp_is_reader`) is judged with
# its role and `Questions: evidence`, so the dispatch wall's own count in brief.sh holds it to three
# in total, suites and runs together: the door cannot know which candidate launch was the agent's,
# so it takes the strict side. A start that recorded no role is judged with none, as before.
amend_unplaced() {  # <agent id> <the last row carrying it, or empty> -> the verb's exit status
  local aid="$1" prior="$2" tr sub old_sa="" old_runs="" decl lift rc=0 sa new_runs r row pick
  local role="" span us
  case "$aid" in
    ''|*[!A-Za-z0-9._@-]*)
      die "REFUSED — no row is named $(clean "$aid"), and it is not an agent id; nothing was written."
      return 1 ;;
  esac
  if [ -z "$prior" ]; then
    tr="$(session_transcript "$SESSION_ID")" || tr=""
    if [ -z "$tr" ]; then
      die "REFUSED — no row is named or carries the agent id $aid, and this session's transcript cannot be found to check it is one of its agents; nothing was written."
      return 1
    fi
    sub="${tr%.jsonl}/subagents/agent-${aid}.jsonl"
    if [ ! -f "$sub" ] || [ -L "$sub" ]; then
      die "REFUSED — no row is named or carries the agent id $aid, and no agent $aid ran in this session (no transcript at $sub); nothing was written."
      return 1
    fi
  fi
  if [ -n "$AMEND_FILES" ]; then
    die "REFUSED — $aid is an agent its start did not place, and a Files: contract belongs to its dispatched row; add suites or runs here, or amend that row by name. Nothing was written."
    return 1
  fi
  if ! poker_brief_load; then
    die "REFUSED — the contract grammar (lib/brief.sh) cannot be loaded from $BIONIC_LIB; nothing was written."
    return 2
  fi
  if [ -n "$prior" ]; then
    old_sa="$(line_field "$prior" suites_allowed)"
    row_has_key "$prior" re_executes && old_runs="$(clean "$(line_field "$prior" re_executes)" re_executes)"
  fi
  [ "$old_sa" = none ] && old_sa=""
  decl="$(poker_union ' ' "$old_sa" "$(printf '%s' "$AMEND_SUITES" | tr '\n,' '  ')")"
  us="$(grep -F 'start-unchecked/v1|event=start|' "$ROSTER_FILE" 2>/dev/null | grep -F "|agent_id=${aid}|" | tail -1)"
  [ -n "$us" ] && role="$(clean "$(line_field "$us" role)")"
  span="$(poker_brief_span "" "$decl" "$old_runs" "$AMEND_RUNS")"
  dp_is_reader "$role" && span="${span}"$'\n'"Questions: evidence"
  lift="$(lift_contract_fields "$span" "$role")"
  POKER_BRIEF_FACTS=""; POKER_BRIEF_WORDS=""
  brief_validate_fields "$lift" "$role" "$REPO_REAL" poker_brief_sink || rc=$?
  if [ "$rc" -ne 0 ]; then
    die "REFUSED — a dispatch carrying these additions for $aid would be refused; nothing was written:"
    printf '%s' "$POKER_BRIEF_WORDS" >&2
    case "$POKER_BRIEF_FACTS" in
      *-run\ cap*) dp_is_reader "$role" \
        && die "A reader its start did not place is held to three in all: stop it and dispatch it again." \
        && die "($aid started as $role; the NOTIFY line asks the same.)" ;;
    esac
    return 1
  fi
  sa="${BRIEF_SUITES_ALLOWED:-$old_sa}"
  new_runs="$old_runs"
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    grep -qxF -- "$r" <<< "$(poker_marked_runs "$old_runs")" && continue
    new_runs="${new_runs:+$new_runs }\`${r}\`"
  done <<EOF
$(poker_marked_runs "$(brief_field "$lift" re_executes)")
EOF
  if [ "$sa" = "$old_sa" ] && [ "$new_runs" = "$old_runs" ]; then
    die "REFUSED — this amend changes nothing: every addition is already on the set recorded for $aid, or is not a suite or run the dispatch grammar reads. Nothing was written."
    return 1
  fi
  row="$(roster_row status=unplaced "session=$SESSION_ID" "name=$aid" "agent_id=$aid" \
    "launched_at=$(iso_now)" "waiver=the suite set of an agent its start did not place; no contract" \
    "suites_allowed=$sa" suites_source=declared ${new_runs:+"re_executes=$new_runs"} \
    "amended=$(iso_now) $(clean "$AMEND_REASON")")" || row=""
  if [ -z "$row" ]; then
    die "REFUSED — could not build the row for $aid."
    return 2
  fi
  printf '%s\n' "$row" >> "$ROSTER_FILE" 2>/dev/null || {
    die "REFUSED — could not write to $ROSTER_FILE."
    return 2
  }
  pick="$(roster_row_for_id "$ROSTER_FILE" "$aid")" || pick=""
  if [ "$pick" != "$row" ]; then
    die "amend written, but the budget wall reads another row for $aid — a later row carrying that id was written after it"
    return 1
  fi
  say "amended — $aid, an agent its start did not place: suites=${sa:-(none)}${new_runs:+ runs=$new_runs}; the budget wall reads this row from now on."
  return 0
}
# ---- END the set of an agent its start did not place ----

# ---------------------------------------------------------------- the plan transaction
#
# ONE TRANSACTION, SIX DOORS (wave-24 T15; REQ-9, D14). `task-add` (wave-20 Δ5) was the one
# verb that wrote the plan, and everything a run did to its plan besides — a status cell, a
# `- T<n>:` line, `current:`, a dispatch-ledger row — was a hand edit (research-R5 item 6: 339
# plan-writing commands across nine sessions). The five plan-row verbs take task-add's
# transaction whole, and task-add now takes it from here too: the change is projected onto a
# COPY through units.sh, the copy is judged by a dry `git commit` through the REAL
# hooks/bash-walls.sh, the plan's checksum is compared with the one taken BEFORE the
# projection read it, and only then is the copy moved over the plan. On any refusal the plan
# is byte-identical and the words that refused it print.
#
# THE DRY RUN IS BOUND TO THE COPY, NEVER TO THE PLAN: its own engagement marker for a
# synthetic session whose `plan=` names the dry copy, removed after (close-out.sh's pattern).
# Both copies sit beside the plan under names that do not end in `.md`, so no plan walk can
# read one as a run. The marker also names the plan the copy was made from (`dry_of=`), and
# goes with it: the commit gate reads that plan's landing record for its declared debts, since
# the copy's name names none (wave-27 T76; lib/proof.sh `proof_debt_origin`). The judged copy
# is a WRITER's commit (task-add's rule): past Step 4 the dry copy carries `current: 4`,
# because a main-root commit during Verify is held to the Step-5 block the run is still
# writing. `current` is the one exception — what it asks is
# whether the run can commit at the step it moves to, so its copy is judged as it stands.
#
# MAIN THREAD ONLY is the Bash wall's to enforce (payload/scripts/lib/walls.sh, the
# `agent_id` verb list); these refuse what the script can see: no session key (3), an
# unengaged session (decides nothing, 0), and a session with no BOUND open plan (1) — a
# writing verb never writes the newest-plan fallback.

# A plan another writer replaced while the copy was judged exits 1, or PV_RACE_RC when the caller
# set it: launch-sync sets 75, the one refusal the next caller repairs by running again (T51).
# Set here, before any verb runs, so a value in the caller's environment never chooses the exit
# (wave-26 T54; review 17 N2).
PV_RACE_RC=""
# plan_verb_open <verb> -> sets PV_REPO, PV_PLAN, PV_CUR, PV_SUM, PV_NEW, PV_DRY, PV_MARK, PV_SID
# and arms the cleanup; exits on every refusal above.
plan_verb_open() {
  local verb="$1" sid run
  sid="$(session_id)" || sid=""
  if [ -z "$sid" ]; then
    die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
    die "$verb writes ONE session's bound plan, so without the key there is nothing to write."
    exit 3
  fi
  if ! engaged_session "$(project_root "$PWD")" "$sid"; then
    say "NOT-ENGAGED — this session has not invoked /bionic:canonical-sdlc; nothing decided"
    exit 0
  fi
  PV_REPO="$(cd "$(project_root "$PWD")" 2>/dev/null && pwd -P)"
  if [ -z "$PV_REPO" ]; then
    die "REFUSED — cannot resolve the working directory."
    exit 2
  fi
  run="$(session_run "$PV_REPO" "$sid")"
  case "$run" in
    'bound-open '*) PV_PLAN="${run#bound-open }" ;;
    *)
      die "REFUSED — $verb writes the plan this session is bound to, and it has no bound open run (${run:-none})."
      die "Bind this session to its run first (this script's bind verb), then run $verb again."
      exit 1 ;;
  esac
  PV_CUR="$(_fill_current_field "$PV_PLAN")"
  # THE CHECKSUM IS TAKEN HERE, BEFORE ANY PROJECTION READS THE PLAN, so an edit that lands
  # between the read and the swap is an edit the comparison sees.
  PV_SUM="$(cksum < "$PV_PLAN" 2>/dev/null)"
  PV_NEW="${PV_PLAN}.${verb}.$$"
  PV_DRY="${PV_PLAN}.${verb}-dry.$$"
  PV_SID="planverb-$$"
  PV_MARK="$(engaged_marker_path "$PV_REPO" "$PV_SID")" || PV_MARK=""
  trap 'rm -f "$PV_NEW" "$PV_NEW.2" "$PV_DRY" ${PV_MARK:+"$PV_MARK"}' EXIT
}

# plan_verb_swap <verb> <what changed> <dry: writer|as-is|judged> -> judges $PV_NEW and moves it over
# $PV_PLAN; exits 1 on a refusal, 2 when the dry commit cannot run. Returns 0 once swapped,
# and exits 0 with nothing written when the projection IS the plan. `judged` runs no dry commit:
# the caller has judged the copy itself (`current 8`, on lib/proof.sh `facts_state`; wave-27 T14).
# plan_verb_dry <verb> <what changed> <dry: writer|as-is> <current> -> the dry commit of $PV_NEW
# through the real gate, at `current: 4` for a writer past Step 4 and as written otherwise; exits 1
# on the gate's refusal, 2 when it cannot run. plan_verb_swap's, split out so `judged` can skip it.
plan_verb_dry() {
  local verb="$1" what="$2" dry="$3" cur="$4" err rc
  if [ "$dry" = writer ] && [ "$cur" -gt 4 ]; then
    awk '
      /^[[:space:]]*```/ { fence = !fence; print; next }
      fence { print; next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); print; next }
      insdlc && !done && /^[[:space:]]*current[[:space:]]*:/ { print "current: 4"; done = 1; next }
      { print }' "$PV_NEW" > "$PV_DRY"
  else
    cp "$PV_NEW" "$PV_DRY"
  fi
  if [ ! -f "$HOOK_DIR/bash-walls.sh" ] || [ -z "$PV_MARK" ] || ! command -v jq >/dev/null 2>&1; then
    die "REFUSED — the dry commit cannot be run (no bash-walls.sh beside this script, no marker path, or no jq); the plan is unchanged."
    exit 2
  fi
  mkdir -p "${PV_MARK%/*}" 2>/dev/null
  printf 'plan=%s\ndry_of=%s\nengaged_at=%s\n' "$PV_DRY" "$PV_PLAN" "$(iso_now)" > "$PV_MARK"
  err="$(cd "$PV_REPO" && CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$PV_SID" BIONIC_WALL_VERBOSE=1 \
    bash "$HOOK_DIR/bash-walls.sh" 2>&1 >/dev/null <<< "$(jq -n --arg s "$PV_SID" --arg cwd "$PV_REPO" --arg v "$verb" \
      '{session_id: $s, cwd: $cwd, hook_event_name: "PreToolUse", tool_name: "Bash",
        tool_input: {command: ("git commit -m " + $v)}, tool_use_id: "toolu_planverb"}')")"
  rc=$?
  rm -f "$PV_MARK"
  if [ "$rc" -ne 0 ]; then
    [ -n "$err" ] && printf '%s\n' "$err" >&2
    die "REFUSED — the commit gate refused the plan with $what (rc=$rc); the plan is unchanged."
    [ "$verb" = current ] && die "Write what that step owes first (step-line <N> <text>, and its block), then move current: again."
    exit 1
  fi
}

plan_verb_swap() {
  local verb="$1" what="$2" dry="$3" cur
  if cmp -s "$PV_NEW" "$PV_PLAN"; then
    say "$verb — $what: the plan already reads so; nothing was written."
    exit 0
  fi
  cur="${PV_CUR%[ab]}"
  case "$cur" in
    ''|*[!0-9]*) [ "$dry" = judged ] || dry=as-is ;;
  esac
  [ "$dry" = judged ] || plan_verb_dry "$verb" "$what" "$dry" "$cur"
  if [ "$(cksum < "$PV_PLAN" 2>/dev/null)" != "$PV_SUM" ]; then
    die "REFUSED — $PV_PLAN changed while the plan with $what was being judged; nothing was written. Run $verb again."
    exit "${PV_RACE_RC:-1}"
  fi
  if ! mv -f "$PV_NEW" "$PV_PLAN"; then
    die "REFUSED — could not move the judged copy over $PV_PLAN; the plan is unchanged."
    exit 2
  fi
  return 0
}

# cur8_judge -> returns when lib/proof.sh `facts_state` says every fact the bound plan owes holds at
# the working head (the head of the checkout holding the plan's `working-branch:`, the head `waive`
# and `proof-add` record), with that head in PV_HEAD8; otherwise refuses `current 8`, exit 1, the
# plan unchanged, printing each owed line that does not hold (wave-27 T14; D3). The judge's rc 2, a
# plan it cannot deal, refuses too, printing whatever the judge printed, whatever the reason.
cur8_judge() {
  local wb out rc err
  if ! { declare -F facts_state >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
     || ! declare -F facts_state >/dev/null 2>&1; then
    die "REFUSED — current: 8 is admitted on the facts the run owes, and the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
    exit 2
  fi
  wb="$(proof_working_branch "$PV_PLAN")"
  PV_HEAD8=""; [ -z "$wb" ] || PV_HEAD8="$(proof_head "$PV_REPO" "$wb")" || PV_HEAD8=""
  case "$PV_HEAD8" in
    [0-9a-f]*) : ;;
    *)
      die "REFUSED — current: 8 is admitted on the facts the run owes at the working head, and no checkout of $PV_REPO has the plan's working-branch ${wb:-(none named)} checked out; the plan is unchanged."
      exit 1 ;;
  esac
  out="$(facts_state "$PV_PLAN" "$PV_HEAD8" 2>"$PV_NEW.judge")"; rc=$?
  err="$(cat "$PV_NEW.judge" 2>/dev/null)"; rm -f "$PV_NEW.judge"
  [ "$rc" -eq 0 ] && return 0
  if [ "$rc" -eq 2 ]; then
    die "REFUSED — current: 8 is admitted on the facts the run owes, and the judge could not deal this plan (facts_state exit 2); the plan is unchanged. The judge said:"
    [ -z "$err" ] || printf '%s\n' "$err" >&2
    [ -z "$out" ] || printf '%s\n' "$out" >&2
    exit 1
  fi
  die "REFUSED — current: 8 is admitted only when every fact the run owes holds at the working head $PV_HEAD8, and these do not (facts_state):"
  printf '%s\n' "$out" | awk -F'\t' '$NF != "covered"' >&2
  die "Take the reading or the floor run each line names and record it with proof-add, or have the user waive a question with waive <question> '<reply>'; the plan is unchanged."
  exit 1
}

# cur8_checks -> returns when no check a finding owes is open on the bound plan; otherwise refuses
# `current 8`, exit 1, the plan unchanged, naming each open check (wave-28 T41; REQ-8 AC-8.6, D33).
# The open set is lib/proof.sh `proof_checks_open`'s, the one reader the judge (`facts_state`) asks too.
cur8_checks() {
  local open
  if ! { declare -F proof_checks_open >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
     || ! declare -F proof_checks_open >/dev/null 2>&1; then
    die "REFUSED — current: 8 is admitted only when no check a finding owes is open, and the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
    exit 2
  fi
  open="$(proof_checks_open "$PV_PLAN" 2>/dev/null)"
  [ -n "$open" ] || return 0
  die "REFUSED — current: 8 waits on each check a finding owes; these check: lines are open (no settled=, no refuted):"
  printf '%s\n' "$open" | awk '{ id = $1; s = $2; r = $3; t = $0; sub(/^[^"]*/, "", t); print "- " id " " s " " r " " t }' >&2
  die "Settle each with finding-check <record>#<n> <settled <S> <reach>|refuted|unsettled> <check record>, a record written by an agent that is neither the finding's reviewer nor the code's writer; the plan is unchanged."
  exit 1
}

# A cell value the plan can hold: no pipe, tab or line break (AC-9.2). 0 when it can.
plan_verb_value_ok() {
  case "$1" in *'|'*|*$'\t'*|*$'\n'*|*$'\r'*) return 1 ;; esac
  return 0
}

# A row id the table can key on: one token, a letter or digit first, then letters, digits,
# `.`, `_` or `-` (wave-24 T27, C1). 0 when it is one.
# ASCII BY SPELLING, NOT BY RANGE (wave-24 T29; critic addendum A3): `[A-Za-z]` is a collation
# range, and /bin/bash 3.2 under a UTF-8 locale matched é, ö, ß and a fullwidth Ｔ with it, so
# `Ｔ9` keyed a row that reads as T9. Every admitted character is listed, so no locale widens it.
PV_ID_ALNUM='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
plan_verb_id_ok() {
  case "$1" in ["$PV_ID_ALNUM"]*) : ;; *) return 1 ;; esac
  case "$1" in *[!"$PV_ID_ALNUM"._-]*) return 1 ;; esac
  return 0
}

# ---------------------------------------------------------------- the deferral's sentence
#
# A DEFERRED FINDING'S ONE CHANGELOG SENTENCE (wave-28 T17; D21, AC-8.7). Registering a record writes
# `deferred: <record>#<n> <S> <reach> "<title>"` (lib/proof.sh `proof_finding_lines`); `finding-stated`
# appends ` stated="<sentence>"` to it, the last field of the line. The sentence is folded to one line
# of single spaces (`deferral_fold`, the one fold the changelog is read through as well), and a `\` or a `"` in it is written `\\` or `\"`, so the
# quoted field ends where the line does and a title, which never holds a `"`, is still the line's
# first quoted string (`proof_findings_owed` reads it so). The other half of the debt is the changelog:
# `release-check` prints each deferral stated (the sentence is in `CHANGELOG.md`) or unstated.
deferral_fold() {  # <text> -> its white space and control characters folded to single spaces, trimmed
  printf '%s' "$1" | LC_ALL=C tr -s '[:space:][:cntrl:]' ' ' | sed -e 's/^ //' -e 's/ $//'
}
deferral_escape() {  # <folded sentence> -> as the plan holds it: \ for a backslash, \" for a quote
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
deferral_line() {  # <plan> <record>#<n> -> the first deferred: line of ## SDLC State naming it (exit 1: none)
  awk -v id="$2" '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && !found && /^deferred:[ \t]/ { split($0, f, /[ \t]+/); if (f[2] == id) { found = 1; line = $0 } }
    END { if (found) print line; exit (found ? 0 : 1) }' "$1"
}
deferral_sentence() {  # <plan> <record>#<n> -> the stated sentence, unescaped (nothing when none); exit 1: no deferred: line
  local l
  l="$(deferral_line "$1" "$2")" || return 1
  printf '%s\n' "$l" | sed -n 's/^.* stated="\(.*\)"[[:space:]]*$/\1/p' | sed -e 's/\\\(.\)/\1/g'
}
# release_deferrals <plan> <changelog file> -> a line `release-check — deferral <id>: stated|unstated`
# for each open deferral (a finding with a deferred: line whose effective priority is defer), in the
# order the plan wrote them. Refuses nothing: the caller's exit is not read from it.
release_deferrals() {
  local plan="$1" cl="$2" DS_CL="" _id _s _r _p _t DS_ST DS_ANS
  [ -f "$cl" ] && DS_CL="$(deferral_fold "$(cat "$cl")")"
  proof_findings_owed "$plan" 2>/dev/null | while read -r _id _s _r _p _t; do
    [ "$_p" = defer ] || continue
    DS_ST="$(deferral_sentence "$plan" "$_id")" || continue
    DS_ANS=unstated
    [ -n "$DS_ST" ] && case "$DS_CL" in *"$DS_ST"*) DS_ANS=stated ;; esac
    say "release-check — deferral $(clean "$_id"): $DS_ANS"
  done
}

# ---------------------------------------------------------------- the launch sync
#
# ONE TRANSACTION FOR EVERY LAUNCH THE PLAN LACKS (wave-26 T32; D4, review-3 F1, F2, F6). Through
# T12 the launch recorder ran `task-set` and then `ledger-add` inside its own hook, about a second
# each, under a 10 s limit: a batch of launches outran it and the later ones printed the busy
# refusal. `launch-sync` reads this session's roster and the bound plan and writes, in ONE
# validated, dry-committed write (the shared transaction above), every open launch whose row is
# not yet active under it or whose ledger line is missing. The recorder starts it without
# waiting; the Patrol tick and the turn-end wall run it too. Whichever runs first does the work,
# and the others find nothing to do and say nothing.
#
# WHICH LAUNCHES: the OPEN names of this session's roster (`roster_open_names`, the predicate the
# ready set reads), each by its latest `confirmed` or `identified` row. A finished agent's launch
# is never applied again, so a row returned to `pending` (a review row after its proof) is not
# re-activated under an old name. A name maps to a `## Tasks` row by `fill_row_launched`; a row
# that is `landed` or `dropped` is left alone.
#
# WHAT IS WRITTEN, PER LAUNCH, AND ALL OF IT OR NONE OF IT: the row's `status=active` and agent,
# its empty `worktree` and `base` filled from the tree spawn-worktree.sh recorded for the name;
# and one `## Dispatch ledger` line, `<role> (<name>)`, the launch minute, the brief duration, the
# deliverable, and `<tree> @ <base>` in the notes. A row's agent cell is its LATEST open launch,
# so a `-r<n>` re-dispatch moves the cell and gets its own line, keyed `<id>r<n>` (F1). A launch
# with no tree of its own (a reviewer or a test-runner whose row's Files name nothing outside the
# docs root, `units_writes_head`) goes active with an empty worktree cell, which units_validate
# admits for exactly such a row, and takes the Step-4 block's `worktree:` and `base-sha:` for its
# ledger line only: the wave's tree in the row would read to the commit gate as the row's own. A
# row that writes the head with no tree recorded cannot go active at all and is printed. A plan with no
# `## Dispatch ledger` heading keeps no ledger, and its launches get the row alone.
#
# NEVER HALF A LAUNCH (F2, F6). The row and its line are projected together on a scratch copy and
# kept only when both project; the batch is validated and dry-committed once, and the plan is
# replaced by one rename. A run killed before the rename leaves the plan byte-identical and the
# next caller applies the launch whole; the copy it left is removed by the next run once its pid
# is gone. The T12 case of a ledger-add refusing after task-set succeeded cannot arise.
#
# ONE WRITER: a lock under `.bionic/tmp`, mkdir and pid. `--wait` (the recorder's detached call)
# waits up to LAUNCH_SYNC_WAIT seconds; the tick and the turn-end wall leave a held lock to its
# holder. A holder whose pid is gone, or a lock older than LAUNCH_SYNC_STALE seconds, is taken
# over.
#
# WHAT IT PRINTS: `poker: LAUNCHED <id> <name> — <what was written>` once, by whichever caller
# wrote it; `poker: NOT-RECORDED <id> <name> — <why>` and the commands to run by hand, by every
# caller, until it is fixed (exit 1). Nothing at all when there is nothing to do.
LAUNCH_SYNC_WAIT=60
LAUNCH_SYNC_STALE=120
LAUNCH_SYNC_LOCK=""

launch_sync_unlock() {
  [ -n "$LAUNCH_SYNC_LOCK" ] && rm -rf "$LAUNCH_SYNC_LOCK" 2>/dev/null
  LAUNCH_SYNC_LOCK=""
  return 0
}

# EVERY PASS IS BOUNDED, AND A LOCK THAT CANNOT BE MADE IS SAID AT ONCE (wave-26 T51; review 13
# F1). Through T32 a takeover went straight back to the top of the loop, past the wait bound, and
# when mkdir failed because the lock's directory was missing or could not be written there was
# never a lock to take over: the loop ran for ever, and the tick's and the turn-end wall's calls
# with it. The bound is now the first thing each pass asks (the waiting call's seconds, or three
# passes for a call that does not wait), a takeover that removed nothing waits like a held lock,
# and a failed mkdir under a directory that is not there or not writable returns 2 at once.
#
# A MKDIR THAT FAILS WITH NO LOCK THERE IS NOT A HELD LOCK EITHER (wave-26 T54; review 17 N1). The
# directory exists and can be written, yet mkdir fails and nothing is there to wait for or take
# over: a full disk, a quota, an I/O error. Through T51 the takeover arm removed nothing and went
# straight back to the top without sleeping, so the waiting call spun to its 60 s, and every caller
# then exited 0 in silence. Such a pass now sleeps like a held lock, and three of them in a row
# return 3: one is a holder releasing between this call's mkdir and its look (A-T51.2), three
# 0.2 s apart are not.
launch_sync_lock() {  # <lock dir> <wait: yes|no> -> 0 held, 1 another writer holds it, 2 no lock can be made here, 3 mkdir keeps failing with no lock there
  local d="$1" wait="$2" pid start="$SECONDS" pass=0 bare=0
  while :; do
    if [ "$wait" = yes ]; then
      [ $((SECONDS - start)) -lt "$LAUNCH_SYNC_WAIT" ] || return 1
    else
      [ "$pass" -lt 3 ] || return 1
    fi
    pass=$((pass + 1))
    if mkdir "$d" 2>/dev/null; then
      printf '%s' "$$" > "$d/pid" 2>/dev/null
      LAUNCH_SYNC_LOCK="$d"
      return 0
    fi
    [ -d "${d%/*}" ] && [ -w "${d%/*}" ] || return 2
    if [ ! -e "$d" ]; then
      bare=$((bare + 1))
      [ "$bare" -lt 3 ] || return 3
      sleep 0.2
      continue
    fi
    bare=0
    pid="$(cat "$d/pid" 2>/dev/null)"
    if { [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; } \
      || [ $(( $(now_epoch) - $(file_mtime "$d") )) -gt "$LAUNCH_SYNC_STALE" ]; then
      rm -rf "$d" 2>/dev/null
      [ -e "$d" ] || continue
    fi
    [ "$wait" = yes ] || return 1
    sleep 0.2
  done
}

# The tree and base spawn-worktree.sh recorded for <name> in this session, `path<TAB>base`, or
# nothing. worktree.sh owns the read (`workspace_record_for_name`, wave-26 T40): a path counts
# only where git lists it as a linked worktree (wave-25 T18), so a line any script appended
# naming the main checkout never fills a row; the last line that counts wins.
launch_sync_workspace() {  # <root> <sid> <name>
  declare -F workspace_record_for_name >/dev/null 2>&1 || return 0
  workspace_record_for_name "$1" "$2" "$3" 2>/dev/null || return 0
}

# A recorded tree as the plan writes it: relative to the project root when it sits under it.
launch_sync_rel() {  # <root> <absolute tree>
  local root="$1" p="$2" root_p
  [ -d "$p" ] && p="$(cd "$p" 2>/dev/null && pwd -P)"
  root_p="$(cd "$root" 2>/dev/null && pwd -P)"
  case "$p" in
    "$root"/*)   p="${p#"$root"/}" ;;
    "$root_p"/*) p="${p#"$root_p"/}" ;;
  esac
  printf '%s' "$p"
}

# The brief duration as the ledger writes it: `60 minutes`, `~45 minutes.` -> `60 min`, `45 min`;
# anything else verbatim.
launch_sync_minutes() {  # <duration>
  local d="$1" n
  d="${d#\~}"; d="${d%.}"
  n="${d%%[!0-9]*}"
  case "${d#"$n"}" in
    ' min'|' mins'|' minute'|' minutes'|min|mins|m) [ -n "$n" ] && { printf '%s min' "$n"; return 0; } ;;
  esac
  printf '%s' "$1"
}

# The Step-4 block's `worktree:` and `base-sha:`, `tree<TAB>base`, or nothing.
launch_sync_step4() {  # <plan>
  awk '
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^##[ \t]/ { sdlc = ($0 ~ /^##[ \t]+SDLC State/); inb = 0; next }
    !sdlc { next }
    /^[ \t]*-?[ \t]*Step[ \t]+4[ \t]*:/ { inb = 1; next }
    inb && /^[ \t]*- / { inb = 0 }
    inb && /^[ \t]+worktree[ \t]*:/ { v = $0; sub(/^[ \t]+worktree[ \t]*:[ \t]*/, "", v); sub(/[ \t].*$/, "", v); wt = v }
    inb && /^[ \t]+base-sha[ \t]*:/ { v = $0; sub(/^[ \t]+base-sha[ \t]*:[ \t]*/, "", v); sub(/[ \t].*$/, "", v); bs = v }
    END { if (wt != "") print wt "\t" bs }' "$1" 2>/dev/null
}

# The dispatch ledger's rows, `id agent-cell dispatched-cell` joined by the unit separator (the
# dispatched cell found by its header, empty when the table has none); exit 1 when the plan has no
# ## Dispatch ledger.
launch_sync_ledger() {  # <plan>
  awk '
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^##[ \t]/ { inl = ($0 ~ /^##[ \t]+Dispatch ledger[ \t]*$/ && !done); if (inl) seen = 1; else if (seen) done = 1; rows = 0; next }
    !inl || $0 !~ /^[ \t]*\|/ { next }
    { rows++ }
    rows == 1 { dc = 0; n = split($0, c, "|"); for (k = 2; k <= n; k++) { h = c[k]; gsub(/^[ \t]+|[ \t]+$/, "", h); if (h == "dispatched") dc = k }; next }
    $0 ~ /^[ \t]*\|[ \t:|-]*$/ { next }
    { n = split($0, c, "|"); id = c[2]; ag = c[3]; dt = (dc ? c[dc] : "")
      gsub(/^[ \t]+|[ \t]+$/, "", id); gsub(/^[ \t]+|[ \t]+$/, "", ag); gsub(/^[ \t]+|[ \t]+$/, "", dt)
      if (id != "") print id "\037" ag "\037" dt }
    END { exit(seen ? 0 : 1) }' "$1" 2>/dev/null
}

# IS THIS LAUNCH ALREADY LEDGERED (wave-26 T32, A-T32.14; T54, review 17 S1). A ledger line names
# its launch `<role> (<name>)`, and a name an ack freed can be dispatched again: a line of the same
# name counts for this launch only when its `dispatched=` minute is not older than this launch's
# first minute (`launch_sync_launches`). A line whose cell is not an ISO minute, or a launch with no
# minute, keeps the name alone as the key, as before. Reads the projection's LGAG and LGDT.
launch_sync_ledgered() {  # <name> <launched_at> -> 0 when a ledger line records this launch
  local name="$1" m="" k=0 d
  case "$2" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]*) m="${2:0:16}Z" ;; esac
  while [ "$k" -lt "${#LGAG[@]}" ]; do
    case "${LGAG[k]}" in
      *"($name)")
        d="${LGDT[k]}"
        case "$d" in
          [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]*) [ -n "$m" ] && [ "${d:0:16}Z" \< "$m" ] || return 0 ;;
          *) return 0 ;;
        esac ;;
    esac
    k=$((k + 1))
  done
  return 1
}

# The open launches, `name launched_at duration deliverable subagent_type` joined by the unit
# separator (\037: a field may be empty, and `read` folds runs of a whitespace separator), each by
# its latest confirmed or identified row, in the roster order of that row. The launch minute is the
# FIRST of the name's latest launch (wave-26 T51; review 13 F4): `extend` appends a row launched now
# for a reviewer it re-opens, and that is the same launch, which a proof of its row may already have
# read. ONE LAUNCH, NOT ONE NAME (wave-26 T54; review 17 S1): a name an ack freed can be dispatched
# again, and that is a new pass, which the old pass's first minute would date before the proof that
# read the old pass. So the minute is the earliest among the rows of the latest row's lineage: those
# that share its agent id or its tool_use_id. `extend`, `amend` and `hold` copy both, and the
# recorder's rows of one dispatch share the tool_use_id (a teammate's confirmed row carries no agent
# id until its identified row), while a new dispatch has neither. A latest row with neither falls
# back to every row of the name.
launch_sync_launches() {  # <roster> <sid> <open names, one per line>
  LS_OPEN="$3" LS_SID="$2" awk -F'|' '
    BEGIN { n = split(ENVIRON["LS_OPEN"], o, "\n"); for (i = 1; i <= n; i++) if (o[i] != "") open[o[i]] = 1
            sid = ENVIRON["LS_SID"] }
    $1 != "roster-state/v1" { next }
    {
      split("", kv)
      for (i = 2; i <= NF; i++) {
        e = index($i, "="); if (e < 2) continue
        k = substr($i, 1, e - 1); if (!(k in kv)) kv[k] = substr($i, e + 1)
      }
      if (kv["status"] != "confirmed" && kv["status"] != "identified") next
      nm = kv["name"]; if (nm == "" || !(nm in open)) next
      if (kv["session"] != "" && kv["session"] != sid) next
      at[nm] = NR; r++; last[nm] = r
      rn[r] = nm; ri[r] = kv["agent_id"]; rt[r] = kv["tool_use_id"]; rl[r] = kv["launched_at"]
      rec[nm] = kv["duration"] "\037" kv["deliverable"] "\037" kv["subagent_type"] "\037" kv["row"]
    }
    END {
      for (q = 1; q <= r; q++) {
        nm = rn[q]; l = last[nm]
        if (ri[l] != "" || rt[l] != "")
          if (!((ri[l] != "" && ri[q] == ri[l]) || (rt[l] != "" && rt[q] == rt[l]))) continue
        if (rl[q] != "" && (!(nm in la) || rl[q] < la[nm])) la[nm] = rl[q]
      }
      for (k in at) print at[k] "\t" k "\037" la[k] "\037" rec[k] }' "$1" 2>/dev/null | sort -n | cut -f2-
}

# The command a person runs for one of the plan-row verbs, quoted where it must be.
launch_sync_hand() {  # <verb> <operand>...
  local out a
  out="bash ${POKER_WORD} $1"; shift
  for a in "$@"; do out="$out $(refuse_shell_word "$a")"; done
  printf '%s' "$out"
}

# Removes what a run killed before its rename left beside the plan: the copies and the dry
# commit's engagement marker of a pid that is gone.
launch_sync_sweep() {  # <plan> <root>
  local f pid m
  for f in "$1".launch-sync.* "$1".launch-sync-dry.*; do
    [ -e "$f" ] || continue
    pid="${f#"$1".launch-sync}"; pid="${pid#-dry}"; pid="${pid#.}"; pid="${pid%%.*}"
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$pid" 2>/dev/null && continue
    rm -f "$f" 2>/dev/null
    m="$(engaged_marker_path "$2" "planverb-$pid" 2>/dev/null)" && [ -n "$m" ] && rm -f "$m" 2>/dev/null
  done
  return 0
}

# IS THIS LAUNCH A PASS ITS ROW'S OWN PROOF ALREADY READ (wave-26 T51; review 13 F2, F4). A review
# row returns to `pending` on its proof while its reviewer may still be open, and a launch older
# than that proof is the pass the proof read: it is not applied again (T32, A-T32.17). Since T46 a
# proof returns only the row whose Files hold its evidence (`units_live_rows`, both spellings, as
# proof-add hands them), so a launch is judged against the proofs of ITS row alone: the proof of
# another review, the final one among them, says nothing about it, and a live launch the sync had
# not yet applied when such a proof landed is applied. Newest proof first; the first one not newer
# than the launch ends the search. The proofs are read once per transaction, and only when a pending
# row has a launch to judge.
LS_PROOFS=""; LS_PROOFS_READ=no
launch_sync_read() {  # <plan> <root> <row id> <launched_at> -> 0 when a review proof of that row is newer than the launch
  local plan="$1" root="$2" id="$3" la="$4" at ev q doc
  [ -n "$la" ] || return 1
  if [ "$LS_PROOFS_READ" = no ]; then
    LS_PROOFS="$(awk '
      /^[ \t]*```/ { f = !f; next }
      f { next }
      /^##[ \t]/ { insdlc = ($0 ~ /^##[ \t]+SDLC State/); next }
      insdlc && /^proved:[ \t]/ && / kind=review( |$)/ && match($0, / at=[^ ]+/) {
        a = substr($0, RSTART + 4, RLENGTH - 4); q = ""
        if (match($0, / question=[^ ]+/)) q = substr($0, RSTART + 10, RLENGTH - 10)
        if (match($0, / evidence=[^ ]+/)) print a "\t" substr($0, RSTART + 10, RLENGTH - 10) "\t" q
      }' "$plan" 2>/dev/null | sort -r)"
    LS_PROOFS_READ=yes
  fi
  [ -n "$LS_PROOFS" ] || return 1
  doc="$(docs_root "$root" 2>/dev/null)"
  case "$doc" in "$root"/*) doc="${doc#"$root"/}" ;; *) doc="" ;; esac
  # A READING IS ITS QUESTION'S ROW'S PROOF (wave-27 T10; D4): a proof carrying question= is
  # matched to the read row carrying that question, as proof-add returned it, not by its Files.
  while IFS="$(printf '\t')" read -r at ev q; do
    [ -n "$at" ] && [ -n "$ev" ] || continue
    [ "$la" \< "$at" ] || return 1
    units_live_rows "$plan" ${q:+--question "$q"} "$ev" ${doc:+"$doc/$ev"} 2>/dev/null \
      | awk -F'\t' -v id="$id" '$1 == id && $2 == "review" { f = 1 } END { exit !f }' && return 0
  done <<EOF
$LS_PROOFS
EOF
  return 1
}

# launch_sync_project <plan> <root> <sid> <roster> <ack ledger> <out>
#   -> writes the projected plan to <out>; sets LS_SAID (lines for what it applies), LS_FAILS
#   (lines for what it cannot) and LS_HANDS (every applied launch's commands, for a batch the
#   gate refuses). 0 when something was projected, 1 when nothing was.
launch_sync_project() {
  local plan="$1" root="$2" sid="$3" roster="$4" acks="$5" out="$6"
  local open rec i j n=0 nl=0 hits h hasl=0 haswt=0 hasbs=0 s4 s4wt s4bs
  local name la du dl ty st ag wt bs fil ws wsbs wtnew bsnew treeless noroom what lid sfx k role rc hand
  local us=$'\037'
  local -a RID RFIL RAG RST RWT RBS LN LLA LDU LDL LTY LBR LROW FINAL LGID LGAG LGDT pairs lpairs
  LS_SAID=""; LS_FAILS=""; LS_HANDS=""; LS_PROOFS=""; LS_PROOFS_READ=no
  open="$(roster_open_names "$roster" "$acks" "$sid" 2>/dev/null)"
  [ -n "$open" ] || return 1
  while IFS="$us" read -r name la du dl ty rw; do
    [ -n "$name" ] || continue
    LN[nl]="$name"; LLA[nl]="$la"; LDU[nl]="$du"; LDL[nl]="$dl"; LTY[nl]="$ty"; LBR[nl]="$rw"; nl=$((nl + 1))
  done <<EOF
$(launch_sync_launches "$roster" "$sid" "$open")
EOF
  [ "$nl" -gt 0 ] || return 1
  while IFS="$us" read -r rec _ _ _ ag _ _ _ fil st wt bs _; do
    [ -n "$rec" ] || continue
    RID[n]="$rec"; RFIL[n]="$fil"; RAG[n]="$ag"; RST[n]="$st"; RWT[n]="$wt"; RBS[n]="$bs"; FINAL[n]=-1
    n=$((n + 1))
  done <<EOF
$(units_rows "$plan" 2>/dev/null | tr '\t' '\037')
EOF
  [ "$n" -gt 0 ] || return 1
  j=0
  while [ "$j" -lt "$nl" ]; do
    hits=0; h=-1; i=0
    # THE ROW LABEL FIRST (wave-28 T7; D17): a launch whose row carries `row=` is that row's, by the
    # id itself; only a launch with none is matched by its name.
    while [ "$i" -lt "$n" ]; do
      if [ -n "${LBR[j]}" ]; then
        [ "${RID[i]}" = "${LBR[j]}" ] && { hits=$((hits + 1)); h="$i"; }
      elif fill_row_launched "${RID[i]}" "${LN[j]}"; then hits=$((hits + 1)); h="$i"; fi
      i=$((i + 1))
    done
    LROW[j]=-1
    if [ "$hits" -gt 1 ]; then
      LS_FAILS="${LS_FAILS}NOT-RECORDED ? ${LN[j]} — the name maps to more than one ## Tasks row; set the row it runs by hand: $(launch_sync_hand task-set '<id>' status=active "agent=${LN[j]}")"$'\n'
    elif [ "$hits" -eq 1 ]; then
      case "${RST[h]}" in pending|active) LROW[j]="$h"; FINAL[h]="$j" ;; esac
    fi
    j=$((j + 1))
  done
  units_has_column "$plan" worktree && haswt=1
  units_has_column "$plan" base && hasbs=1
  if launch_sync_ledger "$plan" > "$out.ledger"; then hasl=1; fi
  i=0
  while IFS="$us" read -r lid ag la; do
    [ -n "$lid" ] || continue
    LGID[i]="$lid"; LGAG[i]="$ag"; LGDT[i]="$la"; i=$((i + 1))
  done < "$out.ledger"
  rm -f "$out.ledger"
  s4="$(launch_sync_step4 "$plan")"; s4wt="${s4%%$'\t'*}"; s4bs="${s4#*$'\t'}"; [ -n "$s4" ] || s4bs=""
  cp "$plan" "$out" || return 1
  j=0
  while [ "$j" -lt "$nl" ]; do
    i="${LROW[j]}"
    if [ "$i" -lt 0 ]; then j=$((j + 1)); continue; fi
    name="${LN[j]}"; st="${RST[i]}"; ag="${RAG[i]}"; wt="${RWT[i]}"; bs="${RBS[i]}"; fil="${RFIL[i]}"
    pairs=(); lpairs=(); what=""; treeless=0; wtnew=""; bsnew=""
    ws="$(launch_sync_workspace "$root" "$sid" "$name")"
    if [ -n "$ws" ]; then
      case "$wt" in *[A-Za-z0-9]*) : ;; *) [ "$haswt" = 1 ] && wtnew="$(launch_sync_rel "$root" "${ws%%$'\t'*}")" ;; esac
      case "$bs" in *[A-Za-z0-9]*) : ;; *)
        case "${ws#*$'\t'}" in *[A-Za-z0-9]*) [ "$hasbs" = 1 ] && bsnew="$(printf '%s' "${ws#*$'\t'}" | cut -c1-8)" ;; esac ;;
      esac
    fi
    # A LAUNCH WITH NO TREE OF ITS OWN: no record for the name, an empty cell, and a Files cell
    # that names nothing outside the docs root (units.sh `units_writes_head`, the predicate the
    # validator asks before it owes the row a tree).
    case "$wt" in *[A-Za-z0-9]*) : ;; *)
      if [ -z "$wtnew" ] && [ "$haswt" = 1 ]; then
        units_writes_head "$fil" || treeless=1
      fi ;;
    esac
    noroom=0
    # A PENDING ROW WHOSE LAUNCH IS ALREADY LEDGERED WAS PUT BACK ON PURPOSE (wave-26 T14: a review
    # row returns to `pending` on its proof while its reviewer may still be open). The launch was
    # recorded once; it is not re-applied to the row, and the next pass is its own launch, under
    # a name of its own or under this one again once an ack freed it (`launch_sync_ledgered`).
    lid=""
    if [ "$st" = pending ] && [ "$hasl" = 1 ] && launch_sync_ledgered "$name" "${LLA[j]}"; then
      lid=have
    fi
    if [ -z "$lid" ] && [ "$st" = pending ] && launch_sync_read "$plan" "$root" "${RID[i]}" "${LLA[j]}"; then
      lid=read
    fi
    if [ -n "$lid" ]; then j=$((j + 1)); continue; fi
    if [ "${FINAL[i]}" = "$j" ]; then
      if [ "$st" = pending ] && [ "$treeless" = 1 ]; then
        pairs=(status=active "agent=$name")
        what="row active with no tree of its own (its Files write nothing the head carries)"
      elif [ "$st" = pending ] && [ "$haswt" = 1 ] && [ -z "$wtnew" ] && { case "$wt" in *[A-Za-z0-9]*) false ;; *) true ;; esac; }; then
        noroom=1
        pairs=(status=active "agent=$name" 'worktree=<tree>' 'base=<sha>')
      elif [ "$st" = pending ]; then
        pairs=(status=active "agent=$name")
        [ -n "$wtnew" ] && pairs+=("worktree=$wtnew")
        [ -n "$bsnew" ] && pairs+=("base=$bsnew")
        what="row active${wtnew:+ in $wtnew}"
      elif [ "$ag" != "$name" ]; then
        pairs=("agent=$name")
        [ -n "$bsnew" ] && pairs+=("base=$bsnew")
        what="the agent cell was ${ag:-empty}"
      fi
    fi
    lid=""
    if [ "$hasl" = 1 ]; then
      launch_sync_ledgered "$name" "${LLA[j]}" && lid=have
      if [ -z "$lid" ]; then
        lid="${RID[i]}"
        sfx="${name##*-r}"; case "$name" in *-r[0-9]*) case "$sfx" in *[!0-9]*) sfx=1 ;; esac ;; *) sfx=1 ;; esac
        while :; do
          k=0
          while [ "$k" -lt "${#LGID[@]}" ] && [ "${LGID[k]}" != "$lid" ]; do k=$((k + 1)); done
          [ "$k" -lt "${#LGID[@]}" ] || break
          lid="${RID[i]}r$sfx"; sfx=$((sfx + 1))
        done
        role="${LTY[j]##*:}"; [ -n "$role" ] || role=agent
        la="${LLA[j]}"
        case "$la" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]*Z) la="${la:0:16}Z" ;; esac
        du="$(launch_sync_minutes "${LDU[j]}")"
        lpairs=("agent=$role ($name)")
        [ -n "$la" ] && lpairs+=("dispatched=$la")
        [ -n "$du" ] && lpairs+=("expected=$du")
        [ -n "${LDL[j]}" ] && lpairs+=("artifact=${LDL[j]}")
        if [ -n "$ws" ]; then
          wsbs=""; case "${ws#*$'\t'}" in *[A-Za-z0-9]*) wsbs="$(printf '%s' "${ws#*$'\t'}" | cut -c1-8)" ;; esac
          lpairs+=("notes=$(launch_sync_rel "$root" "${ws%%$'\t'*}")${wsbs:+ @ $wsbs}")
        elif [ "$treeless" = 1 ] && [ -n "$s4wt" ]; then
          lpairs+=("notes=$s4wt${s4bs:+ @ $s4bs}")
        else
          case "$wt" in *[A-Za-z0-9]*)
            case "$bs" in *[A-Za-z0-9]*) lpairs+=("notes=$wt @ $bs") ;; *) lpairs+=("notes=$wt") ;; esac ;;
          esac
        fi
      else
        lid=""
      fi
    fi
    # A ROW THAT CANNOT GO ACTIVE: nothing of the launch is written, and both commands print.
    if [ "$noroom" = 1 ]; then
      LS_FAILS="${LS_FAILS}NOT-RECORDED ${RID[i]} $name — no tree is recorded for $name and row ${RID[i]} names none, so it cannot go active (spawn its tree with spawn-worktree.sh create --for $name, or fill the cells by hand). Nothing of this launch was written; run:
  $(launch_sync_hand task-set "${RID[i]}" "${pairs[@]}")${lid:+
  $(launch_sync_hand ledger-add "$lid" "${lpairs[@]}")}"$'\n'
      j=$((j + 1)); continue
    fi
    if [ "${#pairs[@]}" -eq 0 ] && [ -z "$lid" ]; then j=$((j + 1)); continue; fi
    # THE LAUNCH WHOLE OR NOT AT ALL: both halves on a scratch copy, kept only together.
    rc=0
    cp "$out" "$out.l" || return 1
    if [ "${#pairs[@]}" -gt 0 ]; then
      units_table_cells "$out.l" set tasks "${RID[i]}" "${pairs[@]}" > "$out.r" 2>/dev/null || rc=$?
      if [ "$rc" -ne 0 ]; then
        LS_FAILS="${LS_FAILS}NOT-RECORDED ${RID[i]} $name — row ${RID[i]} of ## Tasks could not take ${pairs[*]} (units_table_cells exit $rc). Nothing of this launch was written; run:
  $(launch_sync_hand task-set "${RID[i]}" "${pairs[@]}")${lid:+
  $(launch_sync_hand ledger-add "$lid" "${lpairs[@]}")}"$'\n'
        rm -f "$out.l" "$out.r"; j=$((j + 1)); continue
      fi
      mv -f "$out.r" "$out.l"
    fi
    if [ -n "$lid" ]; then
      units_table_cells "$out.l" add ledger "$lid" "${lpairs[@]}" > "$out.r" 2>/dev/null || rc=$?
      if [ "$rc" -ne 0 ]; then
        hand=""
        [ "${#pairs[@]}" -gt 0 ] && hand="  $(launch_sync_hand task-set "${RID[i]}" "${pairs[@]}")"$'\n'
        LS_FAILS="${LS_FAILS}NOT-RECORDED ${RID[i]} $name — the ## Dispatch ledger could not take its line (units_table_cells exit $rc: a header without one of agent, dispatched, expected, artifact or notes, or the id $lid taken). Nothing of this launch was written; run:
${hand}  $(launch_sync_hand ledger-add "$lid" "${lpairs[@]}")"$'\n'
        rm -f "$out.l" "$out.r"; j=$((j + 1)); continue
      fi
      mv -f "$out.r" "$out.l"
      LGID[${#LGID[@]}]="$lid"; LGAG[${#LGAG[@]}]="$role ($name)"; LGDT[${#LGDT[@]}]="$la"
      what="${what:+$what, }ledger line $lid"
    fi
    mv -f "$out.l" "$out"
    [ "${#pairs[@]}" -gt 0 ] && RAG[i]="$name"
    LS_SAID="${LS_SAID}LAUNCHED ${RID[i]} $name — $what"$'\n'
    [ "${#pairs[@]}" -gt 0 ] && LS_HANDS="${LS_HANDS}  $(launch_sync_hand task-set "${RID[i]}" "${pairs[@]}")"$'\n'
    [ -n "$lid" ] && LS_HANDS="${LS_HANDS}  $(launch_sync_hand ledger-add "$lid" "${lpairs[@]}")"$'\n'
    j=$((j + 1))
  done
  [ -n "$LS_SAID" ] || { rm -f "$out"; return 1; }
  return 0
}

# ---------------------------------------------------------------- the sweep
#
# THE OTHER HALF OF `adopt` (fixit 1.5.1 T5; ideas/fixit-1.5.2-dead-session-sweep.md).
# `adopt` reads a predecessor's residue back so a resumed session can act on it. Nothing has
# ever removed that residue once NO session can act on it — so a project's `.bionic/tmp`
# grows one set of files per `/clear`, forever, while every one of those files declares
# itself machine-local and safe to delete in its own first line, and doctor proves the
# sessions dead and then names no way to clear them.
#
# THE HARNESS COMPUTES DEADNESS, A HUMAN RUNS THE VERB (D-5). Deadness is
# `patrol_live_sessions` and nothing else: `kill -0` against the pid the CLI itself wrote
# into its own session file — never `ps`, never an mtime heuristic, and never a judgment of
# the rows inside the file. A dead session's agents are dead by construction, so MET, UNMET,
# acked and open are all the same fact once nobody can act on any of them. Auto-sweeping was
# rejected on the record (D-5): the residue is exactly what `adopt` reads, so a hook that
# cleared it at engagement would delete the evidence of the thing it was helping with.
#
# THE SESSION-KEYED CLASSES, and no others — scripts/lib/patrol.sh's PATROL_STATE_CLASSES.
# Each is `<class>-<session id>.state` under `<root>/.bionic/tmp`, plus the Patrol stamp's
# `.armed` sibling:
#
#   roster-<sid>.state         hooks/dispatch-preflight.sh   the dispatch ledger
#   preflight-<sid>.state      hooks/preflight-probe.sh      the budget attestation
#   engaged-<sid>.state        scripts/lib/binding.sh        the engagement marker
#   sweeper-<sid>.state        hooks/session-sweeper.sh      the ack ledger
#   patrol-<sid>.state[.armed] this file                     the Patrol stamp and its marker
#   stop-orders-<sid>.state    hooks/stop-orders.sh          the order queue
#   tick-digest-<sid>.state    this file                     the tick's digest and duty
#   workspaces-<sid>.state     scripts/lib/worktree.sh       the run's workspace record
#   gate-<sid>.state           hooks/permission-answer.sh    the reserved requests to escalate
#
# THE FILES THAT ARE NOT SESSION-KEYED ARE THEREFORE UNREACHABLE FROM HERE, and that
# is a property of the enumeration rather than a list to maintain: `context-spend.state` and
# `farm-out.state` carry no session id in their names, so no id this walk derives can ever
# address one. A future non-session file is safe on arrival for the same reason.
# (`stop-check.state` was the third of these until epic-23 wave-15 deleted the observation
# record itself — ADR-028.)
SWEEP_SCHEMA="poker-sweep/v1"

# THE ENUMERATION IS THE LIBRARY'S, NOT A COPY (T5 phase 2). Which files belong
# to a session, and which sessions are dead, are read through
# `patrol_state_session_ids`, `patrol_session_state_files` and
# `patrol_dead_sessions` in scripts/lib/patrol.sh — the same three functions
# scripts/lib/checks.sh's dead-session detector calls. They have to agree: a
# class this verb did not delete but the detector counted would put a row on
# doctor's page whose named cure clears nothing, and a second copy of the class
# list here is exactly how that drift arrives. The library's own header carries
# the class table and the reason the unkeyed files are unreachable.

# NO LONGER A FUNCTION (REQ-9/D5's prune half). This used to be `sweep_unlink`, called once
# per candidate file — one `rm -f` subprocess per call, the dominant cost once
# hooks/session-start.sh's own report loops were bounded (T6/T16). The `sweep` verb below
# now queues every non-symlink candidate from every session it decides is old enough (never
# a symlink; never rewritten here) and deletes them all in ONE `xargs -0 rm -f` pass, then
# confirms each with a plain `[ -e ]` — no second `rm`, no per-file function call. See the
# verb's own comments for the full shape, including the per-session age gate that decides
# which sessions reach the delete list at all.

# ---------------------------------------------------------------- the run's numbers
#
# THE RUN'S NUMBERS ARE FOLDED FROM THE TWO RECORDS, AND ONLY PRINTED (wave-28 T14; D18, REQ-4).
# `landing_report` reads the landing record's `line/v1` events and the gate's request files, and prints
#
#   landings: queue=<n> hand=<n> git=<n> · ready-to-landed median=<m>m p75=<m>m max=<m>m · runs: green=<n> red=<n> none=<n> discarded=<n> red-then-green=<n> · waited median=<s>s · killed=<n>
#
# and with rows, one line per landed row in the record's order:
#
#   <row> <kind> ready=<ISO|-> landed=<ISO> minutes=<m|-> runs=<n> waited=<s>s
#
# NOTHING READS THESE NUMBERS TO DECIDE (D18). The tick prints the first line outside its digest, so a
# landing moves no decision; no hook or wall library names the report (tests/docs-pins.test.sh §W28-46).
#
# THE DEFINITIONS (the plan's T14). Ready-to-landed is a queue landing's `published` time less its row's
# FIRST `ready` since the row last landed; a hand or a git landing prints `-` and joins no figure. Median
# and p75 are linear interpolation over the sorted minutes, wave-27's baseline rule: an even set's median
# is the mean of its middle two, a set of one is that value; an empty set prints 0. Runs count `verdict`
# events by result, a ROW'S runs only: the accepted head's own run, which `_line_red_owner` records under
# the row id at the head's commit, is not the row's (a verdict at the base of one of the row's candidates
# and at none of its own commits) and is counted nowhere. Red-then-green is a red then a green for one row,
# one commit and one suite with no `ready` for that row between (an unchanged tree), counted once per such pair. Waited is a request's `admitted` less its
# `asked`; killed is a request admitted whose holder is dead with no `ended` line, or that ended over 128.
# A request counts when its `tree=` is the project or under it and it was asked at or after the record's
# first `line/v1` event; a row's own wait is its requests by the roster name its `ready` carries, asked
# from its first ready to its landing. Times are the events' own `at=`, never a message's.
#
# UNMEASURED (wave-28 T62). A record that holds `landed:` lines and no `line/v1` event (a run open across the
# upgrade) prints the one line `landings: unmeasured — the landing record holds no line/v1 events`, and no row.
#
# FAIL-SOFT. An absent or empty record is the line with zeros. A `line/v1` line this fold reads (`ready`,
# `verdict`, `published`) that lacks a field it needs is skipped and counted, and the count is one line
# on stderr; an event of another kind, and every line that is not `line/v1`, is not this fold's. A
# request line the fold does not know (`peak=`, anything newer) is ignored. The gate's lock is not
# taken: this is a read, and a request the gate is writing reads as it stands.
landing_unmeasured() {  # <record> -> rc 0 when it holds `landed:` lines and no `line/v1` event
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  /usr/bin/grep -q '^landed:' "$1" 2>/dev/null || return 1
  ! /usr/bin/grep -q '^line/v1|' "$1" 2>/dev/null
}
landing_report() {  # <record> <project root> <rows yes|no> -> the line [and rows]; rc 0
  local rec="$1" root="$2" rows="$3" gd f l asked adm ended rc who tree holder dead reqs="" out mal
  gd="${BIONIC_GATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/gate}"
  for f in "$gd"/requests/*; do
    case "${f##*/}" in ''|*[!0-9]*) continue ;; esac
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    asked='' adm='' ended='' rc='' who='' tree='' holder=''
    while IFS= read -r l || [ -n "$l" ]; do
      case "$l" in
        asked=*) asked="${l#asked=}" ;;
        admitted=*) adm="${l#admitted=}" ;;
        ended=*) ended="${l#ended=}" ;;
        rc=*) rc="${l#rc=}" ;;
        who=*) who="${l#who=}" ;;
        tree=*) tree="${l#tree=}" ;;
        holder=*) holder="${l#holder=}" ;;
      esac
    done < "$f"
    dead=0
    if [ -n "$adm" ] && [ -z "$ended" ]; then
      case "$holder" in
        ''|-) dead=1 ;;
        *) if declare -F _slots_live >/dev/null 2>&1; then _slots_live "${holder%%:*}" "${holder#*:}" || dead=1
           else kill -0 "${holder%%:*}" 2>/dev/null || dead=1; fi ;;
      esac
    fi
    reqs="${reqs}${asked}	${adm}	${ended}	${rc}	${who#*:}	${tree}	${dead}
"
  done
  if landing_unmeasured "$rec"; then printf 'landings: unmeasured — the landing record holds no line/v1 events\n'; return 0; fi
  [ -f "$rec" ] && [ ! -L "$rec" ] || rec=/dev/null
  out="$(printf '%s' "$reqs" | awk -v root="$root" -v rows="$rows" "$_PATROL_ISO_AWK"'
    function num(s) { return s ~ /^[0-9]+$/ }
    function sortn(a, n,   i, j, t) { for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t } }
    function pct(a, n, p,   pos, lo, fr) {
      if (n == 0) return 0
      sortn(a, n); pos = p * (n - 1); lo = int(pos); fr = pos - lo
      return (lo + 1 < n) ? a[lo + 1] + (a[lo + 2] - a[lo + 1]) * fr : a[lo + 1]
    }
    phase == 0 { split($0, q, "\t"); nq++
      qa[nq] = q[1]; qd[nq] = q[2]; qe[nq] = q[3]; qr[nq] = q[4]; qw[nq] = q[5]; qt[nq] = q[6]; qx[nq] = q[7]; next }
    index($0, "line/v1|") != 1 { next }
    {
      split("", kv); nf = split($0, p, "|")
      for (i = 2; i <= nf; i++) { j = index(p[i], "="); if (j > 1) kv[substr(p[i], 1, j - 1)] = substr(p[i], j + 1) }
      ev = kv["ev"]; rk = kv["row"]; e = iso2epoch(kv["at"])
      if (ev == "candidate" && kv["base"] != "") headc[rk SUBSEP kv["base"]] = 1
      if ((ev == "candidate" || ev == "ready") && kv["commit"] != "") ownc[rk SUBSEP kv["commit"]] = 1
      if (ev != "ready" && ev != "verdict" && ev != "published") { if (e >= 0 && t0 == "") t0 = e; next }
      if (rk == "" || e < 0) { mal++; next }
      if (ev == "verdict" && (kv["suite"] == "" || kv["result"] !~ /^(green|red|none|discarded)$/)) { mal++; next }
      if (ev == "published" && kv["kind"] !~ /^(queue|hand|git)$/) { mal++; next }
      if (t0 == "") t0 = e
      iso[e] = kv["at"]
    }
    ev == "ready" {
      if (!(rk in rdy)) rdy[rk] = e
      span[rk]++; nm[rk] = (kv["name"] == "" ? "-" : kv["name"]); next
    }
    ev == "verdict" {
      if ((rk SUBSEP kv["commit"]) in headc && !((rk SUBSEP kv["commit"]) in ownc)) next
      res = kv["result"]; cnt[res]++; nrun[rk]++
      vk = rk SUBSEP span[rk] SUBSEP kv["commit"] SUBSEP kv["suite"]
      if (res == "red") red[vk] = 1
      else if (res == "green" && (vk in red)) { rtg++; delete red[vk] }
      next
    }
    ev == "published" {
      k = kv["kind"]; kinds[k]++; n++
      prow[n] = rk; pk[n] = k; pat[n] = kv["at"]; pe[n] = e; pruns[n] = nrun[rk] + 0
      pfrom[n] = ((rk in rdy) ? rdy[rk] : ""); pname[n] = ((rk in nm) ? nm[rk] : "-")
      if (k == "queue" && pfrom[n] != "") { pmin[n] = (e - pfrom[n]) / 60; mins[++nm2] = pmin[n] }
      delete rdy[rk]; nrun[rk] = 0; delete nm[rk]
    }
    END {
      for (i = 1; i <= nq; i++) {
        inq[i] = (t0 != "" && num(qa[i]) && qa[i] >= t0 && (qt[i] == root || index(qt[i], root "/") == 1))
        if (!inq[i]) continue
        if (num(qd[i])) wts[++nw] = qd[i] - qa[i]
        if (num(qd[i]) && ((qe[i] == "" && qx[i] == 1) || (qe[i] != "" && qr[i] + 0 > 128))) killed++
      }
      wm = pct(wts, nw, 0.5)
      printf "landings: queue=%d hand=%d git=%d · ready-to-landed median=%.1fm p75=%.1fm max=%.1fm · runs: green=%d red=%d none=%d discarded=%d red-then-green=%d · waited median=%ds · killed=%d\n",
        kinds["queue"], kinds["hand"], kinds["git"], pct(mins, nm2, 0.5), pct(mins, nm2, 0.75), pct(mins, nm2, 1),
        cnt["green"], cnt["red"], cnt["none"], cnt["discarded"], rtg, int(wm + 0.5), killed
      if (rows == "yes") for (r = 1; r <= n; r++) {
        w = 0
        if (pname[r] != "-" && pfrom[r] != "") for (i = 1; i <= nq; i++)
          if (inq[i] && num(qd[i]) && qw[i] == pname[r] && qa[i] >= pfrom[r] && qa[i] <= pe[r]) w += qd[i] - qa[i]
        if (r in pmin) printf "%s %s ready=%s landed=%s minutes=%.1f runs=%d waited=%ds\n", prow[r], pk[r], iso[pfrom[r]], pat[r], pmin[r], pruns[r], w
        else printf "%s %s ready=- landed=%s minutes=- runs=%d waited=%ds\n", prow[r], pk[r], pat[r], pruns[r], w
      }
      if (mal) printf "#malformed %d\n", mal
    }' phase=0 - phase=1 "$rec")"
  mal="$(printf '%s\n' "$out" | sed -n 's/^#malformed //p')"
  printf '%s\n' "$out" | /usr/bin/grep -v '^#malformed '
  [ -z "$mal" ] || die "landing-report — $mal malformed line/v1 line(s) skipped in $1"
  return 0
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

  # THE MACHINE'S SHARE (wave-28 T10; REQ-2 AC-2.1, D16). The share is one integer, 1 to 100, in
  # `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/share`; with no file the gate's share is 80. Printing it asks
  # `gate_share`, the one reader, so what this prints is what the gate decides on. Setting it writes that
  # file by the SAME path expression `gate_share` reads (not `claude_home`, which BIONIC_CLAUDE_HOME moves),
  # through a staged copy and a rename so a reader never sees half a number. It is the machine's and not a
  # run's: no session key, roster or engagement is read, and nothing but the file is written. REFUSED (1):
  # a value that is not a whole number from 1 to 100 (leading zeros read as decimal), or a file that cannot be
  # written; either way the share is as it was. The contract-verb arm of the bash wall lists `share`, so a
  # subagent may call neither form.
  share)
    SH_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/share"
    if [ "$SH_SET" = no ]; then
      if ! declare -F gate_share >/dev/null 2>&1; then
        die "REFUSED — lib/gate.sh did not load, so the share cannot be read."
        exit 3
      fi
      gate_share
      exit 0
    fi
    case "$SH_ARG" in
      ''|*[!0-9]*) SH_BAD=yes ;;
      *) if [ "${#SH_ARG}" -gt 9 ]; then SH_BAD=yes
         else SH_N=$((10#$SH_ARG)); if [ "$SH_N" -ge 1 ] && [ "$SH_N" -le 100 ]; then SH_BAD=no; else SH_BAD=yes; fi; fi ;;
    esac
    if [ "$SH_BAD" = yes ]; then
      die "REFUSED — share $(printf '%q' "${SH_ARG:0:20}") is not a whole number from 1 to 100; the share is unchanged."
      exit 1
    fi
    SH_TMP="${SH_FILE}.tmp.$$"
    if mkdir -p "${SH_FILE%/*}" 2>/dev/null && printf '%s\n' "$SH_N" > "$SH_TMP" 2>/dev/null \
       && mv -f "$SH_TMP" "$SH_FILE" 2>/dev/null; then
      say "share set to $SH_N"
      exit 0
    fi
    rm -f "$SH_TMP" 2>/dev/null
    die "REFUSED — the share file could not be written; the share is unchanged."
    exit 1
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

  # THE WINDOW, ANSWERED BY ITS OWNER. "Since when does THIS roster's own record of this
  # session begin" is a question two readers ask: hooks/session-poker.sh's own counters
  # (`count_main_thread_dispatches`, `count_refused_dispatches`, both of which take the
  # instant as `<since>`) and payload/scripts/lib/patrol.sh, which reconstructs the same
  # tally for doctor. patrol.sh cannot source this file, so without this verb it would grow
  # its own copy of `file_birth`/`epoch_iso`/`roster_window` — a second, silently driftable
  # answer to one question. `patrol_window()` shells out here instead, the same call
  # `patrol_interval()` already makes for the interval and for the identical reason.
  #
  # OUTSIDE THE ENGAGEMENT GATE, exactly like `interval` above it. The gate in this script
  # is per-verb (`adopt`, `sweep`, `tick`), and it guards verbs that DECIDE something about
  # a run. This one decides nothing: it reports a file's creation instant to whoever asks.
  # A session that never engaged bionic still has a doctor page, and that page must not
  # silently fall back to a whole-transcript count because a read-only date refused.
  #
  # READ-ONLY, and — unlike `tick` and `arm` — it writes no stamp: a caller asking "what
  # window would you use" is not itself a firing, and a stamp written here would make
  # doctor's own diagnosis look like a live Patrol.
  window)
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "A window answers for ONE session's roster, so without the key there is nothing to date."
      exit 3
    fi
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    ROSTER_FILE="$REPO_REAL/.bionic/tmp/roster-${SESSION_ID}.state"
    WINDOW="$(roster_window "$ROSTER_FILE" "$SESSION_ID")" || WINDOW=""
    [ -n "$WINDOW" ] && printf '%s\n' "$WINDOW"
    exit 0
    ;;

  # THE CANONICAL PATROL PROMPT (wave-20 REQ-6, AC-6.1; D6). Report #1: a Patrol job created
  # with a composed prompt — the bare tick command, or the marker without the tick — produced
  # turns the stop wall never saw as ticks, or ticks that never ran. The prompt is a fact of
  # the session and of this poker's own path, so it is printed rather than composed: the
  # marker `bionic-patrol session=<sid[0:8]>` FIRST (the stop wall's TICK_MARK, and the prefix
  # the resume ritual deletes stray jobs by), then the tick by this script's absolute path.
  # One line, because it is a CronCreate prompt. READ-ONLY and outside the engagement gate,
  # like `interval`: it decides nothing.
  #
  # IT ASKS ONLY FOR WHAT THE TICK PRINTED (wave-24 T7, REQ-4; D5). Through 1.8.10 it asked for a
  # `fill-declined:` line on every tick, and all 29 declines of that run answered nothing a wall
  # had asked. Each answer is now conditional on the line that owes it, ListAgents on an open
  # row, the task-list refresh only on a change of a row's status or the ready set (wave-26 T15;
  # D16), which the tick prints as its RECONCILE line (T32), nothing at all after `unchanged` or
  # WAITING, and `v=` after the
  # marker names the prompt's version so `arm` can record it and a later tick can ask for a
  # re-arm when the poker has moved on.
  prompt)
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "The prompt carries THIS session's marker, so without the key there is no prompt to print."
      exit 3
    fi
    printf 'bionic-patrol session=%s v=%s — Patrol tick. ListAgents only when the roster has an open row, then run: bash %s tick — the tick decides per row. If it printed only "unchanged", or a "poker: WAITING" line, the run is waiting on its agents and this turn owes nothing more: end it. Answer a FILL only if a "poker: FILL" line printed: dispatch every row it names (its launch records the row active and its ledger line: write neither by hand) or record why they wait: bash %s decline IDS %s, IDS the rows as printed, comma-joined, the reason inside the quotes. Answer a STANDDOWN only if a "poker: STANDDOWN" line printed: TaskStop it, or keep it up with the hold line it prints: bash %s hold NAME %s, NAME as printed and the reason inside the quotes. A gate= field on the decision line means a reserved request was denied: put each "poker: GATE" line to the human as a gate act, through the human'"'"'s own notify channel, and do not perform it. TaskList and reconcile only if a "poker: RECONCILE" line printed. Continue the run toward its goal until a wall only when something is ready or changed.\n' \
      "${SESSION_ID:0:8}" "$PATROL_PROMPT_VERSION" "$POKER_WORD" "$POKER_WORD" "$DECLINE_REASON_SLOT" "$POKER_WORD" "$HOLD_REASON_SLOT"
    exit 0
    ;;

  # THE FILL'S MEASURE (wave-20 REQ-5, AC-5.6; Δ2; ADR-036 decision 4). The stop library appends
  # one `fill-ledger/v1` line per Stop of an engaged run; this folds them into the run's
  # missed-opportunity minutes (a free slot, a ready row, nothing launched — target zero), with
  # HOLD and declines listed separately with their idle cost. The path and the fold are
  # lib/patrol.sh's (`fill_ledger_path`, `fill_ledger_report`), the ones the recorder writes by.
  #
  # THE PLAN: the operand — absolute, project-root-relative or docs-root-relative, `bind`'s
  # three spellings — or, without one, the session's own run as `resolve_run` names it. OPEN is
  # `run_open`'s answer: an open run's last line owns the interval to now, a closed one's owns
  # nothing. READ-ONLY and outside the engagement gate, like `window`.
  fill-report)
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    FR_PLAN=""
    if [ -n "$FILL_REPORT_ARG" ]; then
      case "$FILL_REPORT_ARG" in
        /*) FR_PLAN="$FILL_REPORT_ARG" ;;
        *)  FR_PLAN="$REPO_REAL/$FILL_REPORT_ARG"
            [ -f "$FR_PLAN" ] || FR_PLAN="$(docs_root "$REPO_REAL")/$FILL_REPORT_ARG" ;;
      esac
      if [ ! -f "$FR_PLAN" ] || [ -L "$FR_PLAN" ]; then
        die "REFUSED — no plan file at $FILL_REPORT_ARG; name the plan whose fill ledger to read."
        exit 2
      fi
    else
      SESSION_ID="$(session_id)" || SESSION_ID=""
      if [ -z "$SESSION_ID" ]; then
        die "REFUSED — no session key, and no plan named; a report without an operand is for THIS session's run."
        exit 3
      fi
      resolve_run "$REPO_REAL" "$SESSION_ID"
      FR_PLAN="$POKER_RUN_PLAN"
      if [ -z "$FR_PLAN" ] || [ ! -f "$FR_PLAN" ]; then
        die "REFUSED — this session has no run to report on; name the plan: fill-report <plan>."
        exit 2
      fi
    fi
    FR_SLUG="${FR_PLAN##*/}"; FR_SLUG="${FR_SLUG%.plan.md}"
    FR_OPEN=no
    run_open "$FR_PLAN" && FR_OPEN=yes
    FR_FILE="$(fill_ledger_path "$REPO_REAL" "$FR_PLAN")"
    if [ ! -f "$FR_FILE" ] || [ -L "$FR_FILE" ]; then
      say "fill-report — no fill ledger yet for ${FR_SLUG}: ${FR_FILE} (the stop hook writes it from the first Stop past Step 3)"
    fi
    FR_OUT="$(fill_ledger_report "$FR_FILE" "$FR_SLUG" "$FR_OPEN" "${BIONIC_NOW_EPOCH:-}")"
    printf '%s\n' "$FR_OUT"
    # IDLE MINUTES AND PEAK WIDTH (wave-26 T16, D17). Both are read from times code wrote with the
    # clock and never from the plan's text: the ledger's `at=` and `idle=`, the roster's
    # `launched_at=` and the sweeper ledger's ack stamps, through the roster lib's own close rule.
    FR_NOW="${BIONIC_NOW_EPOCH:-}"
    case "$FR_NOW" in ''|*[!0-9]*) FR_NOW="$(date -u +%s)" ;; esac
    FR_LED_IN=/dev/null
    [ -f "$FR_FILE" ] && [ ! -L "$FR_FILE" ] && FR_LED_IN="$FR_FILE"
    # Idle: the lines are folded by turn (the last of a turn wins, as the report above folds them),
    # ordered by `at`, and a line whose idle= is non-empty owns the interval to the next line; the
    # last one owns the interval to now only while the run is open. An interval counts once, however
    # many rows idled in it.
    FR_IDLE_S="$(awk -v open="$FR_OPEN" -v now="$FR_NOW" "$_PATROL_ISO_AWK"'
      function fr_field(line, key,   i, n, parts) {
        n = split(line, parts, "|")
        for (i = 2; i <= n; i++) if (index(parts[i], key "=") == 1) return substr(parts[i], length(key) + 2)
        return ""
      }
      index($0, "fill-ledger/v1|") == 1 {
        e = iso2epoch(fr_field($0, "at"))
        if (e < 0) next
        k = fr_field($0, "turn")
        if (k != "" && (k in slot)) { i = slot[k] } else { i = ++n; if (k != "") slot[k] = i }
        ep[i] = e; id[i] = fr_field($0, "idle")
      }
      END {
        for (i = 1; i <= n; i++) ord[i] = i
        for (i = 2; i <= n; i++) {
          v = ord[i]; j = i - 1
          while (j >= 1 && ep[ord[j]] > ep[v]) { ord[j + 1] = ord[j]; j-- }
          ord[j + 1] = v
        }
        idle = 0
        for (x = 1; x <= n; x++) {
          i = ord[x]
          if (id[i] == "") continue
          if (x < n) end = ep[ord[x + 1]]
          else end = (open == "yes" ? now : ep[i])
          if (end > ep[i]) idle += end - ep[i]
        }
        printf "%d\n", idle
      }' "$FR_LED_IN")"
    case "$FR_IDLE_S" in ''|*[!0-9]*) FR_IDLE_S=0 ;; esac
    # Width: every session the ledger names (and this one) has a roster; each live row is open from
    # its occupancy stamp to the ack that closes its name (`_roster_acks`, `_roster_discharged`:
    # an ack strictly later than the launch), or to now. A row's `intended`, `confirmed` and
    # `identified` lines share a name and a stamp, so (name, stamp) is one interval.
    FR_SIDS="$(awk -F'|' '
      index($0, "fill-ledger/v1|") == 1 {
        for (i = 2; i <= NF; i++) if (index($i, "session=") == 1) print substr($i, 9)
      }' "$FR_LED_IN" | sort -u)"
    FR_SID_NOW="$(session_id 2>/dev/null)" || FR_SID_NOW=""
    FR_SIDS="$(printf '%s\n%s\n' "$FR_SIDS" "$FR_SID_NOW" | sort -u)"
    FR_SPANS=""
    for FR_S in $FR_SIDS; do
      case "$FR_S" in ''|*[!A-Za-z0-9_-]*) continue ;; esac
      FR_RF="$REPO_REAL/.bionic/tmp/roster-${FR_S}.state"
      FR_AF="$REPO_REAL/.bionic/tmp/sweeper-${FR_S}.state"
      { [ -f "$FR_RF" ] && [ ! -L "$FR_RF" ] && [ -r "$FR_RF" ]; } || continue
      { [ -f "$FR_AF" ] && [ ! -L "$FR_AF" ] && [ -r "$FR_AF" ]; } || FR_AF=""
      FR_SPANS="${FR_SPANS}$(FR_RF="$FR_RF" FR_AF="$FR_AF" awk -v now="$FR_NOW" \
        -v rpfx="roster-state/${ROSTER_VERSION:-$ROSTER_SCHEMA_VERSION}|" "$_PATROL_ISO_AWK$_ROSTER_OPEN_AWK"'
        BEGIN {
          _roster_acks(ENVIRON["FR_AF"], ACK)
          f = ENVIRON["FR_RF"]
          while ((getline line < f) > 0) {
            if (index(line, rpfx) != 1) continue
            if (!_roster_live(_roster_kv(line, "status"))) continue
            nm = _roster_kv(line, "name"); if (nm == "") nm = "(unnamed)"
            st = _roster_occupied_at(line); if (!_roster_stamp_ok(st)) continue
            key = nm SUBSEP st; if (key in seen) continue
            seen[key] = 1
            b = iso2epoch(st); en = now
            if ((nm in ACK) && _roster_discharged(st, ACK[nm])) en = iso2epoch(ACK[nm])
            if (en < b) en = b
            printf "%d %d\n", b, en
          }
          close(f)
        }' </dev/null)
"
    done
    FR_PEAK="$(printf '%s' "$FR_SPANS" | awk '
      NF == 2 { n++; s[n] = $1; e[n] = $2 }
      END {
        peak = 0
        for (i = 1; i <= n; i++) {
          c = 0
          for (j = 1; j <= n; j++) if (s[j] <= s[i] && (s[i] < e[j] || j == i)) c++
          if (c > peak) peak = c
        }
        printf "%d\n", peak
      }')"
    case "$FR_PEAK" in ''|*[!0-9]*) FR_PEAK=0 ;; esac
    printf 'idle minutes: %d\n' "$(( (FR_IDLE_S + 30) / 60 ))"
    printf 'peak width: %d\n' "$FR_PEAK"
    FR_HEAD="$(printf '%s\n' "$FR_OUT" | head -n 1)"
    FR_M="${FR_HEAD#*|missed=}"; FR_M="${FR_M%%|*}"
    FR_H="${FR_HEAD#*|hold=}"; FR_H="${FR_H%%|*}"
    FR_D="${FR_HEAD#*|declined=}"; FR_D="${FR_D%%|*}"
    say "fill-report ${FR_SLUG}: missed opportunity ${FR_M} min (a free slot, a ready row, nothing launched) · HOLD ${FR_H} min · declined ${FR_D} min$( [ "$FR_OPEN" = yes ] && printf ' · run open, last interval to now')"
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
    # THE PROMPT VERSION THIS ARM PAIRS WITH (wave-24 T7; D5). An arm follows the CronCreate of
    # `prompt`'s output, so the version this poker prints is the one the job now carries. The
    # digest it replaces is dropped with it: the first tick after an arm prints in full. The gate
    # requests already raised are kept (wave-25 T5): a re-arm is not a reason to raise them again.
    write_tick_digest "$SESSION_ID" "$PATROL_PROMPT_VERSION" "" "" "" "" \
      "$(tick_digest_field "$(tick_digest_file "$SESSION_ID")" gate_raised)" \
      || die "WARN — the prompt version could not be recorded; the tick will ask for a re-arm."
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

    # ---------- THE ENGAGEMENT GUARD (AC-10): is this session bionic's at all? ----------
    #
    # BEFORE ANYTHING IS READ, DECIDED OR WRITTEN — above the stamp, above the roster,
    # above the sweeper. Chris, 2026-09-03: "all guardrails imposed by bionic should only
    # apply when exercising bionic. Nothing should apply until bionic is triggered" — and
    # the trigger is the canonical-sdlc skill, which writes
    # `.bionic/tmp/engaged-<sid>.state` at the instant it is invoked. The Patrol prompt
    # runs this verb, and a Patrol inherited by a session that never invoked the skill
    # must decide nothing about it rather than deciding wrongly.
    #
    # ONE LINE, EXIT 0, and not a refusal: the tick fired correctly and found nothing it
    # is entitled to judge. `arm` is deliberately not guarded (writing a stamp for a
    # session that asked for one is harmless) and neither is `disarm`, which removes the
    # stamp and leaves this marker exactly where it is — a session that invoked the skill
    # is bionic's for its whole life, so every hook still binds after a disarm (AC-15).
    # [WALL: tests/session-poker.test.sh]
    if ! engaged_session "$(project_root "$PWD")" "$SESSION_ID"; then
      say "NOT-ENGAGED — this session has not invoked /bionic:canonical-sdlc; nothing decided"
      exit 0
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

    # ---------- THE PARTITION (spec AC-2; design ledger T2) ----------
    #
    # THE BUG THIS CLOSES is symptom 2 of the report: this loop walked every roster in the
    # project and offered every open row on every one of them, filtered by nothing but the
    # filename. Two runs sharing a root meant each session was handed the other run's agents
    # to ledger, message and stop.
    #
    # ATTRIBUTION, NOT A SECOND SCAN. hooks/dispatch-preflight.sh stamps the dispatching
    # session's bound plan onto every row it writes, and a BOUND caller compares that field
    # against its own binding: same plan is its own work, a different plan is another run in
    # this root, no field at all is a roster written before this wave (A2). Only the first is
    # written to this session's roster; the other two are LISTED, because a predecessor's
    # agent that is invisible is exactly the failure `adopt` exists to prevent — the operator
    # still needs to see that something is running here, even when taking it is not theirs.
    #
    # AN UNBOUND CALLER HAS NOTHING TO COMPARE AGAINST and gets today's behaviour verbatim:
    # every row, adopted, `partition=all` (AC-3). `session_plan` is the RAW binding rather
    # than `session_run`'s resolution, deliberately — a session bound to a plan that has
    # since closed still owns the rows it dispatched under it, and the fallback plan of an
    # unbound session was never anyone's attribution.
    ADOPT_OWN_PLAN="$(session_plan "$REPO_REAL" "$SESSION_ID")" || ADOPT_OWN_PLAN=""
    ADOPT_OWN_KEY=""
    [ -n "$ADOPT_OWN_PLAN" ] && ADOPT_OWN_KEY="$(adopt_plan_key "$ADOPT_OWN_PLAN")"
    ADOPT_ADOPTED=0
    ADOPT_LISTED=0
    ADOPT_CLOSED=0
    ADOPT_UNREADABLE=0
    ADOPT_DUPES=0
    ADOPT_LAST_PART=""
    # THE IDS THIS RUN HAS ALREADY OFFERED (REQ-9 AC-9.2; D10). Adoption files a copy of the
    # row on the ADOPTER's roster, so an agent resumed N times leaves N rows for one agent id
    # across N rosters — and this walk read all of them, offering one running agent as N
    # things to ledger, message and stop. The id is the identity; the name is not (a rename
    # under `-r<n>` is this verb's own convention). First row carrying an id wins, in roster
    # order, which is the same "the last row of a name wins / the first sighting of an id
    # counts" direction every other reader in the fleet takes.
    ADOPT_SEEN_IDS="|"
    # CLOSURE'S TWO INPUTS, RESOLVED ONCE PER RUN. The live session set is one file per
    # running process out of the claude home, and the window is this project's own poker
    # interval — the same knob the `sweep` verb reads for `--window`, with the same fallback
    # to this script's built-in default so a malformed override cannot disable the read.
    ADOPT_LIVE_IDS="$(patrol_live_session_ids)"
    ADOPT_LIVE_IDS="${ADOPT_LIVE_IDS}${ADOPT_LIVE_IDS:+
}${SESSION_ID}"
    ADOPT_WINDOW="$(poker_interval_seconds 2>/dev/null)"
    case "$ADOPT_WINDOW" in ''|*[!0-9]*) ADOPT_WINDOW="$(parse_seconds "$POKER_INTERVAL_DEFAULT" 2>/dev/null)" ;; esac
    case "$ADOPT_WINDOW" in ''|*[!0-9]*) ADOPT_WINDOW=1200 ;; esac
    # ONE ANSWER PER PREDECESSOR SESSION, not one per row: the residue question is about the
    # session's files, and every row on a roster shares them.
    ADOPT_SESSION_SWEPT=no

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
      # THE RESIDUE QUESTION, ONCE PER ROSTER (REQ-9 AC-9.1). A dead session whose files the
      # next sweep takes has nothing to hand over; its rows are counted `closed` below and
      # printed nowhere.
      ADOPT_SESSION_SWEPT=no
      adopt_residue_swept "$REPO_REAL" "$OSID" "$ADOPT_LIVE_IDS" "$ADOPT_WINDOW" "$ADOPT_NOW" \
        && ADOPT_SESSION_SWEPT=yes
      # COUNTED WHEN IT CONTRIBUTES, not when it is merely read. A predecessor whose every
      # row is closed is residue, and "N open row(s) from M predecessor session(s)" would be
      # a sentence naming sessions the reader was shown nothing from.
      ADOPT_SESSION_COUNTED=no

      # Resolved ONCE per predecessor session, not once per row: the walk is the same for
      # every agent that session launched.
      OSUB="$(session_subagent_dir "$OSID")" || OSUB=""

      while IFS='|' read -r RNAME RID RTYPE RDELIV RPROG RCAD RLAUNCH RORIG RPLAN RWAIVER \
                            RFILES RSALLOW RSSRC RREX RDONE; do
        [ -n "$RNAME" ] || continue

        # ---- IS THIS ROW STILL SOMEBODY'S WORK? (REQ-9 AC-9.1/9.2; D10)
        #
        # CLOSURE IS DERIVED, NEVER STORED (spec §1). Two independent facts close a row for
        # this verb, and neither is a new field: the run its own `plan=` names is closed
        # (`run_open`, the same predicate `bind` and the tick's run-state read use), or the
        # session that launched it is dead and its files are already sweepable. Either way
        # there is nothing to take over, and a row offered anyway costs the operator a ledger
        # entry, a message address and a stop for work that no longer exists.
        #
        # CHECKED BEFORE THE PARTITION, AND ABOVE `own` INCLUDED. The plan partition answers
        # "whose run is this row"; closure answers "is there a run at all". A row of OUR OWN
        # closed binding is residue exactly as a neighbour's is, and adopting it would take
        # ownership of an agent whose contract nothing is left to discharge.
        #
        # A GONE PLAN IS NOT A CLOSED ONE. `run_open` says nothing about a path that is not
        # a file here — another root's plan, a plan since deleted — so the row keeps today's
        # partition and is listed. A verb that cannot read a fact does not guess it.
        #
        # AND AN UNREADABLE PLAN IS NEITHER (wave-20 T18, REQ-2, D2; T1's carry-over). A plan
        # that is THERE and cannot be read — mode 000, or inside a folder that cannot be
        # opened (`plan_unreadable`, lib/run.sh) — was read two wrong ways here: at mode 000
        # `-f` held and `run_open` failed, so its rows were counted closed and printed
        # nowhere; in an unopenable folder `-f` failed, so the row fell through to the
        # partition and an unbound caller ADOPTED it. Its run may be mid-flight and nothing
        # about it can be read, so the row is listed as UNREADABLE with the path, never
        # adopted and never counted closed — `session_run`'s `bound-unreadable`, asked of the
        # row's plan instead of the session's (cross-gate §S.4g).
        ADOPT_ROW_CLOSED=no
        ADOPT_ROW_UNREADABLE=""
        if [ "$ADOPT_SESSION_SWEPT" = yes ]; then
          ADOPT_ROW_CLOSED=yes
        elif [ -n "$RPLAN" ] && [ "$RPLAN" != none ]; then
          ADOPT_ROW_PLAN_ABS="$(adopt_abs "$RPLAN" "$REPO_REAL")"
          if plan_unreadable "$ADOPT_ROW_PLAN_ABS" >/dev/null; then
            ADOPT_ROW_UNREADABLE="$ADOPT_ROW_PLAN_ABS"
          elif [ -f "$ADOPT_ROW_PLAN_ABS" ] && ! run_open "$ADOPT_ROW_PLAN_ABS"; then
            ADOPT_ROW_CLOSED=yes
          fi
        fi
        if [ "$ADOPT_ROW_CLOSED" = yes ]; then
          ADOPT_CLOSED=$((ADOPT_CLOSED + 1))
          continue
        fi

        # ---- ONE AGENT ID, ONE OFFER (AC-9.2). An empty id is never deduped: an
        # UNADDRESSABLE row has no identity to be the same as another's, and folding two of
        # them together would hide a row the operator has to fix at its source.
        if [ -n "$RID" ]; then
          case "$ADOPT_SEEN_IDS" in
            *"|${RID}|"*) ADOPT_DUPES=$((ADOPT_DUPES + 1)); continue ;;
          esac
          ADOPT_SEEN_IDS="${ADOPT_SEEN_IDS}${RID}|"
        fi

        if [ "$ADOPT_SESSION_COUNTED" = no ]; then
          ADOPT_SESSIONS=$((ADOPT_SESSIONS + 1))
          ADOPT_SESSION_COUNTED=yes
        fi
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
        PROG_MTIME=0
        if [ -n "$RPROG_ABS" ] && [ -f "$RPROG_ABS" ]; then
          PROG_MTIME="$(file_mtime "$RPROG_ABS")"
          PROG_AGE=$(( ADOPT_NOW - PROG_MTIME ))
        fi
        CAD_S="$(parse_seconds "$RCAD")" || CAD_S=""

        # ---- the three addresses, all of them derived from the one id
        #
        # RESOLVED THROUGH THE SAME NEWEST-COPY PREFERENCE `row_quiet` USES (D8, REQ-8;
        # supersedes T1d, walk W-3). This report used to quote ONLY the launching session's
        # copy, unconditionally — so a re-run of `adopt --report-only` after this session
        # had already exchanged a turn with the agent (the file now sitting under THIS
        # session's subagents dir) still named the launcher's stale path and age, while the
        # next tick's `row_quiet` read the fresh one: one row, two disagreeing readers. A
        # chain of "this session, else the launcher" also missed an INTERMEDIATE adopter
        # between two `/clear`s — `agent_log_newest` is the one function both readers ask
        # now, and it globs every session directory rather than walking a chain.
        TX=""
        TX_PRESENT=no
        TX_AGE=""
        TX_MTIME=0
        if [ -n "$RID" ]; then
          # THIS SESSION'S PROJECT DIRECTORY FIRST, falling back to the PREDECESSOR's — the
          # two are ordinarily the same physical directory, but this session may never have
          # spoken to any agent yet (no transcript, no subagents dir of its own), while the
          # predecessor's directory is exactly what this walk is iterating over.
          TX_PROJ="$(agent_project_dir_for "$SESSION_ID")" || TX_PROJ=""
          [ -n "$TX_PROJ" ] || TX_PROJ="$(agent_project_dir_for "$OSID")" || TX_PROJ=""
          TX=""
          [ -n "$TX_PROJ" ] && { TX="$(agent_log_newest "$RID" "$TX_PROJ")" || TX=""; }
          if [ -n "$TX" ]; then
            TX_PRESENT=yes
            # THE SECOND LIVENESS INPUT. The harness appends to this file on every turn
            # the agent takes, so its mtime is a fact about the agent rather than a
            # promise the agent has to remember to keep.
            TX_MTIME="$(file_mtime "$TX")"
            TX_AGE=$(( ADOPT_NOW - TX_MTIME ))
          elif [ -n "$OSUB" ]; then
            # NEITHER SESSION HAS SPOKEN TO THE AGENT YET — still name the launcher's path
            # (where the file will land once it does) rather than nothing.
            TX="$OSUB/agent-${RID}.jsonl"
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
        #
        # WAIVED IS NEXT (S17, AC-12 attempt 2), ahead of LANDED/RUNNING/SILENT, and for the
        # same reason `session-sweeper.sh verdict_row` puts it first: a carried `waiver=` is
        # an explicit designation that this row's contract is not held, so its deliverable's
        # absence is not "quiet for now" — it was never open. Printing SILENT for such a row,
        # which is what happened before the field was carried at all, read as an unmet
        # contract for one that was closed at dispatch (the live T4 walk this fixes).
        # LIVE ON EITHER MTIME, STALE ONLY ON BOTH (1.6, AC-6). The progress file is a
        # promise the agent keeps by hand — the first thing to lapse when the work gets
        # absorbing, and impossible for a role with no Write tool — so reading it alone
        # called working agents SILENT. The transcript is the harness's own record of the
        # agent taking a turn, at the very path this verb already prints as the observe
        # address, so it costs one stat and answers the question the progress file was
        # standing in for. SILENT now means neither a written line nor a turn taken inside
        # the window, which is a state worth waking someone for.
        #
        # THE WINDOW IS ONE CADENCE, AND THE CLASSIFICATION IS THE LIBRARY'S (REQ-10 D9).
        # This arm used to compute twice the cadence here, from a constant of its own, on the
        # reasoning
        # that a row promising a line every ten minutes is up to ten minutes stale at any
        # random instant while perfectly healthy. The reasoning is sound and the consequence
        # was not: `observe_class` (payload/scripts/lib/observe.sh) answers the SAME question
        # at ONE cadence for the stop gates, so one row was alive to one reader and silent to
        # another, and the fleet carried four staleness arithmetics for three questions. Both
        # readers ask the function now; an author who wants slack declares it in the cadence,
        # which is the liveness contract's own rule ("too quiet" means quieter than the
        # AUTHOR'S OWN declaration).
        #
        # THE SIX INPUTS ARE FILLED BY HAND because this caller already holds the row and the
        # two stats — `observe_agent` would re-resolve a target against THIS session's roster,
        # which is not where these rows live. Delivery is left `none`: the verdict order below
        # asks about the deliverable itself one branch later, and `observe_class` outranking it
        # here would answer the same question twice.
        LIVE=no
        OBS_DELIV_STATE=none
        OBS_PROGRESS_STATE=unnamed; OBS_PROGRESS_AGE=0
        OBS_LOG_MTIME=0; OBS_LOG_AGE=0
        OBS_CADENCE_S="${CAD_S:-$OBSERVE_CADENCE_DEFAULT_S}"
        if [ -n "$PROG_AGE" ]; then
          OBS_PROGRESS_STATE=present; OBS_PROGRESS_AGE="$PROG_AGE"
        fi
        if [ -n "$TX_AGE" ]; then
          OBS_LOG_MTIME="$TX_MTIME"; OBS_LOG_AGE="$TX_AGE"
        fi
        [ "$(observe_class)" = alive ] && LIVE=yes

        if [ -z "$RID" ]; then
          VERDICT=UNADDRESSABLE
        elif [ -n "$RWAIVER" ]; then
          VERDICT=WAIVED
        elif [ "$DELIV_PRESENT" = yes ]; then
          VERDICT=LANDED
        elif [ "$LIVE" = yes ]; then
          VERDICT=RUNNING
        else
          VERDICT=SILENT
        fi

        # ---- WHOSE RUN IS THIS ROW? (AC-2)
        #
        # `plan=none` READS AS UNATTRIBUTED, not as another run. `none` is the marker's own
        # word for "this session had no binding" (payload/scripts/lib/run.sh:378), so a row
        # carrying it names no run at all — and calling it "another run in this root" would
        # assert a run that does not exist. Both answers are un-adoptable, so the choice
        # only decides which heading the operator reads it under.
        #
        # UNREADABLE OUTRANKS ALL FOUR, `own` and `all` included: ownership is taken against a
        # run, and this row's run cannot be read.
        if [ -n "$ADOPT_ROW_UNREADABLE" ]; then
          PARTITION=unreadable
        elif [ -z "$ADOPT_OWN_KEY" ]; then
          PARTITION=all
        elif [ -z "$RPLAN" ] || [ "$RPLAN" = none ]; then
          PARTITION=unattributed
        elif [ "$(adopt_plan_key "$RPLAN")" = "$ADOPT_OWN_KEY" ]; then
          PARTITION=own
        else
          PARTITION=other
        fi
        case "$PARTITION" in
          own|all)    ADOPT_ADOPTED=$((ADOPT_ADOPTED + 1)) ;;
          unreadable) ADOPT_UNREADABLE=$((ADOPT_UNREADABLE + 1)) ;;
          *)          ADOPT_LISTED=$((ADOPT_LISTED + 1)) ;;
        esac

        # THE HEADING IS A GROUP SEPARATOR, printed when the partition CHANGES rather than
        # once for the whole report. Rows arrive in roster order and a predecessor session
        # dispatched under one binding, so in practice each kind is one contiguous run and
        # gets exactly one heading; a session that rebound mid-flight interleaves them and
        # gets the heading again, which is right — a heading standing over rows of another
        # kind would be worse than a repeated one. An unbound caller sees neither line.
        if [ "$PARTITION" != "$ADOPT_LAST_PART" ]; then
          case "$PARTITION" in
            other)        say "other runs in this root — listed, never adopted" ;;
            unattributed) say "unattributed rows (pre-wave rosters) — listed, never adopted" ;;
            unreadable)   say "UNREADABLE — rows whose plan is there and cannot be read — listed, never adopted, never counted closed" ;;
          esac
        fi
        ADOPT_LAST_PART="$PARTITION"

        # THE TWO NEW FIELDS ARE TRAILING, so every existing field keeps its position for a
        # reader that counts rather than looks up by key. `plan=` is the row's own
        # attribution (`none` when it carried none) and `partition=` is what this caller
        # decided about it.
        printf '%s|at=%s|session=%s|from=%s|name=%s|verdict=%s|agent_id=%s|address=%s|subagent_type=%s|deliverable=%s|deliverable_present=%s|progress=%s|progress_age=%s|cadence=%s|transcript=%s|transcript_present=%s|transcript_age=%s|plan=%s|partition=%s\n' \
          "$ADOPT_SCHEMA" "$(iso_now)" "$SESSION_ID" "$OSID" "$(clean "$RNAME")" "$VERDICT" \
          "$RID" "$ADOPT_ADDR" "$(clean "$RTYPE")" "$(clean "$RDELIV_ABS")" "$DELIV_PRESENT" \
          "$(clean "$RPROG_ABS")" "${PROG_AGE:-unknown}" "${CAD_S:-unknown}" \
          "$(clean "$TX")" "$TX_PRESENT" "${TX_AGE:-unknown}" \
          "$(clean "${RPLAN:-none}")" "$PARTITION"

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
        #
        # AND THE PARTITION DECIDES WHETHER IT IS FILED AT ALL (AC-2). A row belonging to
        # another run in this root is never written to this session's roster: the write is
        # what makes the stop address true, so writing it would take ownership of an agent
        # this session did not launch and is not steering — the exact harm the partition
        # exists to prevent. It is still printed, one arm down.
        ROW_JOURNALLED=no
        ROW_LISTED_ONLY=no
        case "$PARTITION" in
          own|all)
            if [ -n "$RID" ] && [ "$ADOPT_REPORT_ONLY" = yes ]; then
              ROW_JOURNALLED=yes
            elif [ -n "$RID" ]; then
              if adopt_write_row "$ADOPT_OWN_ROSTER" "$SESSION_ID" "$RNAME" "$RID" "$RTYPE" \
                   "$RDELIV" "$RPROG" "$RCAD" "$RLAUNCH" "$OSID" "$ADOPT_ADDR" \
                   "${ADOPT_OWN_PLAN:-none}" "$RWAIVER" \
                   "$RFILES" "$RSALLOW" "$RSSRC" "$RREX" "$RDONE"; then
                ROW_JOURNALLED=yes
                # THE MARKER COPY (S17, AC-12 attempt 2). `payload/scripts/lib/stop.sh`
                # (`stop_landing_gate`, reached from hooks/stop.sh) is this schema's one
                # ORIGINATING writer. This is a second writer, deliberately: adopt never
                # ORIGINATES a `landing-swept/v1` verdict, it only COPIES a line that writer
                # already produced onto the roster this session is now the owner of, so
                # `hooks/session-start.sh`'s `open_rows` — which still reads a marker
                # straight off the SAME roster file as ground truth, with no re-derivation —
                # sees the same history on the successor that stood on the predecessor. A
                # closed name can never reach here: `adopt_fold` excludes it through the
                # `roster_open_names` predicate (an ack later than the row's launch), not a
                # `met[]` filter, so only a still-open history is ever offered to copy.
                adopt_copy_marker "$ADOPT_RF" "$ADOPT_OWN_ROSTER" "$(clean "$RNAME")"
              else
                die "WARN — this row could not be journalled to $ADOPT_OWN_ROSTER; the stop gate will not treat $RNAME as ours."
              fi
            fi ;;
          *) ROW_LISTED_ONLY=yes ;;
        esac

        say "$(clean "$RNAME") ($(clean "$RTYPE")) from session $OSID — $VERDICT"
        # THE PATH, ON EVERY UNREADABLE ROW WHATEVER ITS ID, because the cure is on the plan.
        [ "$PARTITION" = unreadable ] \
          && printf '  plan        : UNREADABLE — %s is there and cannot be read\n' "$(clean "$ADOPT_ROW_UNREADABLE")"
        if [ -n "$RID" ] && [ "$ROW_JOURNALLED" = yes ]; then
          printf '  agent id    : %s\n' "$RID"
          printf '  observe     : %s (%s)\n' "$TX" \
            "$([ "$TX_PRESENT" = yes ] && echo 'on disk' || echo 'not on disk')"
          # THE MESSAGE ADDRESS IS THE NAME (T22, A-orch-33), and the id keeps the two lines
          # it is genuinely the key for — the observe path above and the stop below. It was
          # the transcript-form id here until 2026-09-14, when a SendMessage to an id a
          # `/clear` had re-keyed made the harness RESUME A COPY of the agent while the
          # original was still running: two processes, one contract, one roster row. The
          # agent table does not survive a `/clear`; the TEAMMATE table, keyed on the name,
          # does — so the name is the address that keeps meaning the same agent.
          printf '  message     : SendMessage to:%s\n' "$(clean "$RNAME")"
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
        elif [ "$ROW_LISTED_ONLY" = yes ] && [ -n "$RID" ]; then
          # LISTED, NOT ADOPTED. Everything that does not depend on this session's roster is
          # still printed — the id, the observe address, the message address all belong to
          # the agent rather than to us — and the one line that would be a lie is replaced by
          # the reason it is missing. The operator can still SEE and MESSAGE an agent of the
          # other run; taking ownership of it is what they may not do, and the cure is the
          # other session, not a retry here.
          printf '  agent id    : %s\n' "$RID"
          printf '  observe     : %s (%s)\n' "$TX" \
            "$([ "$TX_PRESENT" = yes ] && echo 'on disk' || echo 'not on disk')"
          printf '  message     : SendMessage to:%s\n' "$(clean "$RNAME")"
          if [ "$PARTITION" = unreadable ]; then
            printf '  stop        : not adopted — this row'"'"'s plan cannot be read, so there is no\n'
            printf '                run to take ownership against. Restore read access and re-run adopt.\n'
          elif [ "$PARTITION" = other ]; then
            printf '  stop        : not adopted — this row belongs to another run in this root\n'
            printf '                (%s), and ownership stays with the session working it.\n' "${RPLAN:-none}"
          else
            printf '  stop        : not adopted — this row carries no plan= attribution\n'
            printf '                (a roster written before session-bound runs existed), so it\n'
            printf '                cannot be told from another run in this root.\n'
          fi
        elif [ -n "$RID" ]; then
          # ADDRESSABLE FOR EVERYTHING BUT THE STOP. The id is real and the transcript and
          # the message address do not depend on this session's roster — only ownership
          # does, and that is precisely what the failed write cost. So the two true lines
          # are still printed and the one that would be false is replaced by its cause,
          # which is the UNADDRESSABLE shape below applied to the half that is missing.
          printf '  agent id    : %s\n' "$RID"
          printf '  observe     : %s (%s)\n' "$TX" \
            "$([ "$TX_PRESENT" = yes ] && echo 'on disk' || echo 'not on disk')"
          printf '  message     : SendMessage to:%s\n' "$(clean "$RNAME")"
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
        # THE BUDGET, BESIDE THE LAUNCH (T6, REQ-5, AC-5.1). A resumed orchestrator needs the
        # row's allowance to widen it, and a row can carry only declared RUNS: its suites cell
        # is then empty, so the line names both cells rather than reading as no budget.
        _AD_RUNS="$(clean "$RREX" re_executes)"
        if [ -z "$RSALLOW" ] && [ -z "$_AD_RUNS" ]; then
          printf '  budget      : none\n'
        else
          printf '  budget      : suites=%s runs=%s\n' "${RSALLOW:-none}" "${_AD_RUNS:-none}"
        fi
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

    # THE TWO NEW COUNTERS ARE TRAILING AND ADDITIVE (REQ-9 AC-9.1/9.2). A row this verb
    # dropped is invisible by design — that is the fix — so the COUNT of what was dropped is
    # on the line that answers for the run, or the drop could not be told from a walk that
    # found nothing.
    # `unreadable=` TRAILS THEM, the same way (wave-20 T18): a row neither adopted, listed as
    # another run's, nor closed is counted where the operator reads the other three.
    printf '%s|at=%s|session=%s|scanned=%s|open=%s|adopted=%s|listed=%s|closed=%s|dupes=%s|unreadable=%s\n' \
      "$ADOPT_SCHEMA" "$(iso_now)" "$SESSION_ID" "$ADOPT_SESSIONS" "$ADOPT_ROWS" \
      "$ADOPT_ADOPTED" "$ADOPT_LISTED" "$ADOPT_CLOSED" "$ADOPT_DUPES" "$ADOPT_UNREADABLE"
    # SAID ONCE, AND ONLY WHEN THERE IS SOMETHING TO SAY. An operator who expected a
    # predecessor's rows and was shown none is owed the reason.
    [ "$ADOPT_CLOSED" -gt 0 ] \
      && say "$ADOPT_CLOSED row(s) skipped: their run is closed, or their session is dead and its state files are already sweepable — there is nothing left to take over."
    [ "$ADOPT_UNREADABLE" -gt 0 ] \
      && say "$ADOPT_UNREADABLE row(s) UNREADABLE: their plan is there and cannot be read, so they are neither adopted nor counted closed — restore read access and re-run adopt."
    [ "$ADOPT_DUPES" -gt 0 ] \
      && say "$ADOPT_DUPES duplicate row(s) folded: one agent id is one agent, however many rosters carry a row for it."
    if [ "$ADOPT_ROWS" -eq 0 ]; then
      say "nothing to adopt — no other session has an open row on this project's rosters."
      exit 0
    fi
    say "$ADOPT_ROWS open row(s) from $ADOPT_SESSIONS predecessor session(s) — ledger every one BY AGENT ID before dispatching anything new."
    # THE SECOND LINE EXISTS ONLY WHEN IT SAYS SOMETHING. A caller that adopted everything it
    # found is the case this verb has always described, and a count of zero listed rows would
    # be a line the operator has to read to learn nothing.
    [ "$ADOPT_LISTED" -gt 0 ] \
      && say "$ADOPT_ADOPTED adopted onto this session's roster, $ADOPT_LISTED listed only — a row belonging to another run in this root is never adopted."
    # ONE EXTRA LINE, and the rows above untouched: the mode is stated where it changes what
    # the reader should do next, not woven through a rendering that has to stay comparable.
    [ "$ADOPT_REPORT_ONLY" = yes ] \
      && say "report-only: nothing was written — run 'adopt' to take these rows onto this session's roster."
    exit 1
    ;;

  # ---------------------------------------------------------------- sweep
  #
  # NOT ENGAGEMENT-GATED, AND DELIBERATELY (D-4). The engagement marker is itself one of the
  # files this verb removes: a session that never invoked the skill still leaves preflight
  # and roster state behind when it dies, and a cleanup that refused to run without
  # engagement would refuse hardest on the machines carrying the most residue. The guard the
  # other verbs take exists so bionic decides nothing about a session that never asked it to;
  # this verb decides nothing about any session at all — it removes files whose owners the
  # kernel says are gone AND whose newest file is old enough that nobody dispatching it a
  # moment ago could still be looking at it (below).
  #
  # IT TAKES NO SESSION ID, and that is the surface staying closed rather than an omission.
  # The question is "what here can nobody act on any more", which is a question about the
  # directory; an id operand would be a second way to ask it, and the one thing a caller
  # could do with it that the walk does not already do is name a session the walk skipped —
  # which is exactly the live one this verb refuses.
  #
  # PER-SESSION AGE IS OPT-IN, VIA `--window` (REQ-6/D5's prune half, moved here from T6).
  # Without the flag this verb is exactly what `tests/session-sweep.test.sh` has always
  # pinned it as (sections 1-6, none of which ever pass it): PID-liveness alone decides
  # dead-or-live, and every dead session's files go in one pass, aged or not — a question
  # about the directory, not about time. `hooks/session-start.sh`'s own auto-sweep gate
  # asks a cruder, SEPARATE question before it ever calls this verb at all: is ANY file
  # anywhere under `.bionic/tmp` younger than a poker interval, and if so, skip calling
  # `sweep` for the WHOLE run — every dead session's files, ancient or brand new, wait
  # together for the next session start (that gate is unchanged by this task; it is not in
  # this file). A batch dying by the hour meant `.bionic/tmp` only grew: the newest corpse
  # always blocked the oldest one's cleanup. `--window` is this verb's own, finer answer to
  # the SAME question, FOR A CALLER THAT ASKS FOR IT: each dead session's own newest file
  # must itself be older than the poker interval, or that one session — and only that one
  # — is deferred and named in the report, instead of the whole directory waiting on it.
  #
  # THE EXIT CODE SAYS WHETHER ANYTHING IS LEFT THAT THIS VERB MAY NOT TOUCH:
  #   0  the sweep completed — dead state removed (or listed), or there was none to begin with
  #      (with `--window`, a dead session deferred for being too young is not a fault either)
  #   1  nothing swept: every session with state here is LIVE, so there was nothing to remove
  #   2  usage, or a `.bionic/tmp` this verb will not delete inside
  # A live session's state is not a fault and the 1 is not a scolding — it is the one answer
  # a caller cannot read off "0 files removed", which is also what a live-only run and an
  # empty directory would otherwise share. A dead-but-deferred session (`--window` only) is
  # reported by name (never silently folded into either bucket) and does not turn a real
  # sweep into a 1: the 1 means "everything here is LIVE", not "nothing was old enough yet".
  sweep)
    # The current session's own key, when it has one. It is not required — this verb answers
    # for the DIRECTORY, not for a session — but when it is present the session is live by
    # construction, and adding it by hand means a claude-home this process cannot read (an
    # unreadable `~/.claude/sessions`, a missing `jq`) can never let a session sweep its own
    # state out from under itself.
    SESSION_ID="$(session_id)" || SESSION_ID=""

    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    SWEEP_DIR="$REPO_REAL/.bionic/tmp"

    # THE SAME GUARD THE WRITERS TAKE, because a delete is a write. `tmp_dir_ok` is this
    # file's one copy of the rule (a `.bionic` symlinked outside the repo, a `tmp` that is
    # itself a link), and taking it here means the walk below cannot enumerate a single path
    # inside a directory the stamp writer would have refused.
    if ! tmp_dir_ok "$SWEEP_DIR"; then
      die "REFUSED — $SWEEP_DIR is not a directory this verb will delete inside."
      die "A .bionic or a tmp that is a symlink out of this repo is refused, never followed."
      exit 2
    fi
    if [ ! -d "$SWEEP_DIR" ]; then
      say "nothing to sweep — this project has no .bionic/tmp."
      exit 0
    fi

    # LIVE, NOT DEAD — one walk, not two (T6, 63405b0, reused: ownership moved here at
    # T6-fixup/971afdb). `patrol_dead_sessions` would answer this by calling
    # `patrol_state_session_ids` a second time internally and subtracting the live set; this
    # verb already walks that same id set once below, so asking the LIVE side once here and
    # comparing inline reaches the identical verdict without the second walk.
    # `patrol_live_session_ids` costs nothing proportional to residue under `.bionic/tmp` (it
    # reads `${CLAUDE_CONFIG_DIR}/sessions/*.json`, one file per running process, a
    # different and much smaller set). This session's own key is added by hand, live by
    # construction, so an unreadable claude-home can never let a session sweep itself.
    SWEEP_LIVE_IDS="$(patrol_live_session_ids)"
    [ -z "$SESSION_ID" ] || SWEEP_LIVE_IDS="${SWEEP_LIVE_IDS}${SWEEP_LIVE_IDS:+
}${SESSION_ID}"

    # THE WINDOW — read only when `--window` asked for it, so a plain `sweep` call costs
    # nothing extra and touches no new fact. This session's own poker interval, the exact
    # knob hooks/session-start.sh's own auto-sweep gate reads through a subprocess call to
    # this same verb. A malformed `.bionic/config.yaml` REFUSES the `interval` verb
    # elsewhere in this file, which is right for a caller that needs an exact answer; here
    # it must not disable pruning altogether, so a bad override falls back to this script's
    # own built-in default instead (a dead session's files still eventually clear rather
    # than accumulating forever behind a typo).
    SWEEP_WINDOW=0
    SWEEP_NOW=0
    SWEEP_STAT_GNU=no
    if [ "$SWEEP_WINDOWED" = yes ]; then
      SWEEP_WINDOW="$(poker_interval_seconds 2>/dev/null)"
      case "$SWEEP_WINDOW" in ''|*[!0-9]*) SWEEP_WINDOW="$(parse_seconds "$POKER_INTERVAL_DEFAULT" 2>/dev/null)" ;; esac
      case "$SWEEP_WINDOW" in ''|*[!0-9]*) SWEEP_WINDOW=1200 ;; esac
      SWEEP_NOW="$(now_epoch)"

      # THE STAT FLAVOUR, PROBED ONCE — the identical GNU/BSD discrimination
      # hooks/session-start.sh's own age gate uses (its own comment there has the full
      # rationale: GNU's `-f` is a different flag, `--file-system`, so trying the BSD form
      # first and treating any non-empty capture as success reads a filesystem report as a
      # timestamp). Duplicated rather than sourced: the two hooks share no process to read
      # one answer from.
      case "$(stat -c %Y /dev/null 2>/dev/null)" in
        ''|*[!0-9]*) SWEEP_STAT_GNU=no ;;
        *) SWEEP_STAT_GNU=yes ;;
      esac
    fi

    SWEEP_SCANNED=0
    SWEEP_DEAD=0
    SWEEP_KEPT=0
    SWEEP_YOUNG=0
    SWEEP_FILES=0
    SWEEP_REMOVED=0
    SWEEP_REFUSED=0

    # ONE PASS OVER THE DISK TO DECIDE AND DESCRIBE, ONE MORE TO DELETE — never a second
    # walk to RE-DERIVE the report (T6, A-T6.3: a two-walk shape that deletes first and then
    # re-lists a now-emptied directory undercounts every dead session to zero files, and at
    # "everything just got swept" can misreport "nothing swept: all sessions are LIVE").
    # `SWEEP_OUT` accumulates the WHOLE report as this loop goes, with a `?`-prefixed
    # placeholder standing in for any file this pass QUEUES (into `SWEEP_BULK`) rather than
    # deletes immediately. Every other line — live-kept, deferred, a symlink refused — is
    # final the moment it is written. Only after the loop does ONE `xargs -0 rm -f` pass run,
    # and only then are the placeholders resolved, by checking each path once more against
    # disk (never a second `rm`).
    SWEEP_OUT=""
    SWEEP_BULK=""
    # THE PER-START FILES, READ ONCE FOR THE WHOLE WALK (T83): handed to every
    # `patrol_session_state_files` call below, which then picks a session's own from this
    # list instead of globbing the directory once per class per session.
    SWEEP_PER_START="$(patrol_per_start_files "$REPO_REAL")"
    while IFS= read -r SWEEP_SID; do
      [ -n "$SWEEP_SID" ] || continue
      SWEEP_SCANNED=$((SWEEP_SCANNED + 1))

      # Newline-delimited containment against the LIVE set: an id counts as live
      # only as a whole line, so a dead session whose id is a prefix of a live
      # one is not mistaken for it.
      case "
$SWEEP_LIVE_IDS
" in
        *"
$SWEEP_SID
"*)
          SWEEP_KEPT=$((SWEEP_KEPT + 1))
          SWEEP_OUT="${SWEEP_OUT}$SWEEP_SID — live, kept
"
          continue
          ;;
        *) ;;
      esac

      SWEEP_DEAD=$((SWEEP_DEAD + 1))
      SWEEP_SESSION_FILES="$(patrol_session_state_files "$REPO_REAL" "$SWEEP_SID" "$SWEEP_PER_START")"

      # THIS SESSION'S OWN NEWEST FILE, and nobody else's — the whole of the "per-session,
      # not all-or-nothing" fix, and gated on `--window` so a plain `sweep` never pays for
      # or exhibits it (see the verb's own header comment). A session dies once and its own
      # files age together, so one newest mtime among ITS files (never compared across
      # sessions) is the one fact this decision needs. Batched per session (one
      # flavour-probed `xargs stat` call for however many of the five classes this one
      # session actually left) rather than one `stat` fork per file — the exact shape that
      # made 400 dead sessions' worth of per-file forking the dominant cost T6/T16 spent
      # this wave cutting down elsewhere in this same call chain.
      if [ "$SWEEP_WINDOWED" = yes ]; then
        SWEEP_NEWEST=0
        if [ -n "$SWEEP_SESSION_FILES" ]; then
          if [ "$SWEEP_STAT_GNU" = yes ]; then
            SWEEP_SESSION_MTS="$(printf '%s\n' "$SWEEP_SESSION_FILES" | tr '\n' '\0' | xargs -0 stat -c %Y 2>/dev/null)"
          else
            SWEEP_SESSION_MTS="$(printf '%s\n' "$SWEEP_SESSION_FILES" | tr '\n' '\0' | xargs -0 stat -f %m 2>/dev/null)"
          fi
          while IFS= read -r SWEEP_MT; do
            case "$SWEEP_MT" in ''|*[!0-9]*) continue ;; esac
            [ "$SWEEP_MT" -gt "$SWEEP_NEWEST" ] && SWEEP_NEWEST="$SWEEP_MT"
          done <<EOF
$SWEEP_SESSION_MTS
EOF
        fi

        # YOUNGER THAN THE WINDOW: DEFER THIS SESSION, INDIVIDUALLY. Nothing about any
        # OTHER dead session is touched by this — the property the all-or-nothing shape did
        # not have. A session whose files could not be stat'd at all (`SWEEP_NEWEST` still
        # 0, the empty-file-list or every-stat-failed case) is treated as old enough rather
        # than perpetually deferred: an age gate exists to protect a session that JUST
        # died, not to withhold state this verb can no longer even measure.
        if [ "$SWEEP_NEWEST" -gt 0 ] && [ $(( SWEEP_NOW - SWEEP_NEWEST )) -lt "$SWEEP_WINDOW" ]; then
          SWEEP_YOUNG=$((SWEEP_YOUNG + 1))
          SWEEP_N=0
          while IFS= read -r SWEEP_F; do
            [ -n "$SWEEP_F" ] || continue
            SWEEP_N=$((SWEEP_N + 1))
          done <<EOF
$SWEEP_SESSION_FILES
EOF
          SWEEP_OUT="${SWEEP_OUT}$SWEEP_SID — dead, deferred ($SWEEP_N file(s) younger than the ${SWEEP_WINDOW}s window)
"
          continue
        fi
      fi

      SWEEP_N=0
      SWEEP_LINES=""
      while IFS= read -r SWEEP_F; do
        [ -n "$SWEEP_F" ] || continue
        SWEEP_FILES=$((SWEEP_FILES + 1))
        SWEEP_N=$((SWEEP_N + 1))
        if [ "$SWEEP_REPORT_ONLY" = yes ]; then
          # A LINK IS NAMED AS A LINK EVEN HERE, so the report of what would happen matches
          # what happens: a run that listed a symlink as a file to delete and then left it
          # would have lied about its own next invocation.
          if [ -L "$SWEEP_F" ]; then
            SWEEP_REFUSED=$((SWEEP_REFUSED + 1))
            SWEEP_LINES="${SWEEP_LINES}  refused (symlink, left alone): $SWEEP_F
"
          else
            SWEEP_LINES="${SWEEP_LINES}  $SWEEP_F
"
          fi
          continue
        fi
        # A SYMLINK IS NOT A FILE THIS SCRIPT WROTE, so it is refused rather than followed
        # and left in place rather than unlinked — the identical posture `remove_patrol_stamp`
        # takes, and for the identical reason: every reader in the fleet already treats a
        # symlinked state file as absent, so there is nothing to clear, and a hostile repo
        # must not gain a delete through a path it aimed. Everything else is queued for the
        # ONE bulk delete below, never removed here one fork at a time.
        if [ -L "$SWEEP_F" ]; then
          SWEEP_REFUSED=$((SWEEP_REFUSED + 1))
          SWEEP_LINES="${SWEEP_LINES}  refused (symlink or not a file, left alone): $SWEEP_F
"
        else
          SWEEP_BULK="${SWEEP_BULK}${SWEEP_F}
"
          SWEEP_LINES="${SWEEP_LINES}?${SWEEP_F}
"
        fi
      done <<EOF
$SWEEP_SESSION_FILES
EOF

      SWEEP_OUT="${SWEEP_OUT}$SWEEP_SID — dead, $SWEEP_N file(s)
${SWEEP_LINES}"
    done <<EOF
$(patrol_state_session_ids "$REPO_REAL")
EOF

    # THE ONE DELETE. Nothing above ever appends to `SWEEP_BULK` when `SWEEP_REPORT_ONLY=yes`
    # or when a session was deferred (both `continue` before reaching it), so report-only and
    # an all-deferred run both reach here with an empty list and this is a no-op for them.
    if [ -n "$SWEEP_BULK" ]; then
      printf '%s' "$SWEEP_BULK" | tr '\n' '\0' | xargs -0 rm -f -- 2>/dev/null
    fi

    # RESOLVE THE PLACEHOLDERS. Every `?`-prefixed line named a file that was NOT a symlink
    # at enumeration time and was just queued in the one `rm` pass above; the only question
    # left is whether that `rm` actually removed it (the ordinary case) or left it behind
    # (permissions, a concurrent writer) — decided with a plain existence check, never a
    # second `rm`. Every other line already carries its final wording and passes through as-is.
    if [ -n "$SWEEP_OUT" ]; then
      SWEEP_RESOLVED=""
      while IFS= read -r SWEEP_L; do
        case "$SWEEP_L" in
          '?'*)
            SWEEP_RF="${SWEEP_L#?}"
            if [ ! -e "$SWEEP_RF" ]; then
              SWEEP_REMOVED=$((SWEEP_REMOVED + 1))
              SWEEP_RESOLVED="${SWEEP_RESOLVED}  $SWEEP_RF
"
            else
              SWEEP_REFUSED=$((SWEEP_REFUSED + 1))
              SWEEP_RESOLVED="${SWEEP_RESOLVED}  refused (symlink or not a file, left alone): $SWEEP_RF
"
            fi
            ;;
          *)
            SWEEP_RESOLVED="${SWEEP_RESOLVED}${SWEEP_L}
"
            ;;
        esac
      done <<EOF
$SWEEP_OUT
EOF
      SWEEP_OUT="$SWEEP_RESOLVED"
    fi

    printf '%s' "$SWEEP_OUT" | while IFS= read -r SWEEP_L; do
      [ -n "$SWEEP_L" ] && say "$SWEEP_L"
    done

    # `deferred=` IS APPENDED AFTER `refused=`, never inserted between the six original
    # fields (AC-9.2's spirit extended to this line): `tests/session-sweep.test.sh` pins
    # several of them as ADJACENT substrings (`|dead=2|live=1|`, and so on), and a plain
    # `sweep` call — which never sets `SWEEP_YOUNG` above 0 — must keep emitting a byte-
    # identical line up through `refused=` for those pins to hold.
    printf '%s|at=%s|session=%s|mode=%s|scanned=%s|dead=%s|live=%s|files=%s|removed=%s|refused=%s|deferred=%s\n' \
      "$SWEEP_SCHEMA" "$(iso_now)" "${SESSION_ID:-none}" \
      "$([ "$SWEEP_REPORT_ONLY" = yes ] && printf 'report-only' || printf 'sweep')" \
      "$SWEEP_SCANNED" "$SWEEP_DEAD" "$SWEEP_KEPT" "$SWEEP_FILES" "$SWEEP_REMOVED" "$SWEEP_REFUSED" "$SWEEP_YOUNG"

    if [ "$SWEEP_SCANNED" -eq 0 ]; then
      say "nothing to sweep — no session-keyed state under $SWEEP_DIR."
      exit 0
    fi

    if [ "$SWEEP_DEAD" -eq 0 ]; then
      die "REFUSED — nothing swept: all $SWEEP_KEPT session(s) with state under $SWEEP_DIR are LIVE."
      die "A live session's state is its own to keep; this verb removes only what nobody can act on."
      exit 1
    fi

    # BOTH SUMMARY LINES NAME THE DEFERRED COUNT SEPARATELY FROM THE DEAD ONE. `SWEEP_DEAD`
    # counts every session the liveness check ruled dead, deferred ones included — the exit-1
    # refusal above depends on that (a batch that is ALL deferred is not "everything here is
    # live" and must not read as one). The dead-session count in these two prose lines is
    # `SWEEP_DEAD - SWEEP_YOUNG`, on purpose: it is the count of sessions this run actually
    # acted on (swept, or listed to be), so it still says "0" rather than a number that
    # includes sessions nothing happened to.
    if [ "$SWEEP_REPORT_ONLY" = yes ]; then
      say "report-only: $SWEEP_FILES file(s) across $((SWEEP_DEAD - SWEEP_YOUNG)) dead session(s) would be deleted — nothing was written."
      [ "$SWEEP_YOUNG" -gt 0 ] \
        && say "$SWEEP_YOUNG dead session(s) deferred — their files are younger than the ${SWEEP_WINDOW}s window."
      say "run 'sweep' to delete them."
      exit 0
    fi

    say "swept $SWEEP_REMOVED file(s) across $((SWEEP_DEAD - SWEEP_YOUNG)) dead session(s); $SWEEP_KEPT live session(s) kept."
    [ "$SWEEP_YOUNG" -gt 0 ] \
      && say "$SWEEP_YOUNG dead session(s) deferred — their files are younger than the ${SWEEP_WINDOW}s window."
    [ "$SWEEP_REFUSED" -gt 0 ] \
      && say "$SWEEP_REFUSED path(s) refused and left alone — a symlink under .bionic/tmp is never followed."
    exit 0
    ;;

  # ---------------------------------------------------------------- bind
  #
  # THE ACT THAT NAMES THIS SESSION'S RUN (spec AC-8; design ledger D1). Identity is
  # DECLARED, never inferred by a scan: engagement binds a session when the root holds
  # exactly one open run and writes `plan=none` when it holds several (AC-7), so a session
  # resumed into a two-run root is deliberately left unbound until it says which run is its
  # own. This verb is how it says so.
  #
  # AND IT IS THE ONLY WAY A BINDING CHANGES AFTER ENGAGEMENT, besides the governing skill's
  # bind-on-first-write (hooks/canonical-sdlc-governing-skill.sh, AC-9). D1 rejected both
  # alternatives on the record: an argument on the engage hook turns a hook into a command,
  # and a hand-edited marker abandons the one-writer invariants that make the file readable
  # at all. Nothing else in this file writes the marker.
  #
  # THE INVARIANTS ARE THE LIBRARY'S, NOT A SECOND COPY. `bind_plan`
  # (payload/scripts/lib/binding.sh) owns the two-line shape, mode 600, the symlink refusal
  # and — the one that matters here — MEMBERSHIP in `open_runs`, the same set `session_run`
  # will later rule on. This verb's own work is to say WHICH refusal happened, because
  # `bind_plan` answers 0/1/2 and an operator handed a bare "refused" cannot tell a typo
  # from a closed run.
  bind)
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "A binding answers for ONE session, so without the key there is nothing to write."
      exit 3
    fi

    # THE ENGAGEMENT GUARD, above everything, for `adopt`'s reason verbatim (AC-10): nothing
    # bionic does applies until the session invoked the skill. Note that this guard also
    # answers the planted-symlink case — `engaged_session` refuses a symlink at the marker
    # path before it is followed (payload/scripts/lib/run.sh:351) — so the link's target is
    # never written through, one line before `bind_plan` would have refused it too.
    if ! engaged_session "$(project_root "$PWD")" "$SESSION_ID"; then
      say "NOT-ENGAGED — this session has not invoked /bionic:canonical-sdlc; nothing decided"
      exit 0
    fi

    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi

    # ABSOLUTE, BECAUSE THE MARKER IS READ FROM EVERY CWD IN THE FLEET. A relative operand is
    # taken against the PROJECT ROOT rather than `$PWD`: the plan path an operator has to
    # hand is the one their editor shows, which is project-relative, and a worktree cwd would
    # otherwise resolve it against a tree that does not hold the run.
    #
    # AND AGAINST THE DOCS ROOT WHEN THAT MISSES (S10b phase 2). hooks/session-start.sh
    # prints the open-run listing DOCS-root-relative — `plans/<epic>/<wave>.md` — because
    # every absolute path in that listing shares one long prefix. An operator who copies a
    # listed line straight into this verb was handing over a project-relative path that does
    # not exist, and getting a refusal that reads as if the PLAN were wrong rather than the
    # spelling. Both spellings now bind.
    #
    # THE PROJECT ROOT IS TRIED FIRST AND WINS TIES, so every operand that resolved before
    # resolves to exactly the same file now: the docs root is reached only when the
    # project-relative spelling is not a regular file, which is the case that used to refuse.
    # A miss under both leaves `BIND_PATH` at the project-root spelling, so the refusal names
    # the path an operator typing a repo path would expect to see.
    # A TRAILING SLASH IS NOT A DIFFERENT PLAN (S8). Shell completion on a path an operator
    # is still typing leaves one behind, and `[ -f "<file>/" ]` is FALSE — so the docs-root
    # fallback below used to miss on the one spelling and hit on the other, and the two
    # operands that name one file bound to two different things. The canonicalizer strips it
    # anyway (`dirname`/`basename`); stripping it here is what lets both spellings reach the
    # same probe. `/` keeps its slash: it is the path, not a decoration on one.
    BIND_ARG_P="$BIND_ARG"
    while [ ${#BIND_ARG_P} -gt 1 ]; do
      case "$BIND_ARG_P" in */) BIND_ARG_P="${BIND_ARG_P%/}" ;; *) break ;; esac
    done
    case "$BIND_ARG_P" in
      /*) BIND_PATH="$BIND_ARG_P" ;;
      *)
        BIND_PATH="$REPO/$BIND_ARG_P"
        if [ ! -f "$BIND_PATH" ]; then
          BIND_DOCS_TRY="$(docs_root "$REPO")/$BIND_ARG_P"
          [ -f "$BIND_DOCS_TRY" ] && BIND_PATH="$BIND_DOCS_TRY"
        fi ;;
    esac

    BIND_RC=0
    bind_plan "$REPO_REAL" "$SESSION_ID" "$BIND_PATH" || BIND_RC=$?
    if [ "$BIND_RC" -eq 0 ]; then
      say "bound $BIND_PATH"
      exit 0
    else
      if [ "$BIND_RC" -ge 2 ]; then
        die "REFUSED — marker write failed"
        die "The binding was valid; the marker could not be written. Check that"
        die "$REPO_REAL/.bionic/tmp is a writable real directory."
        exit 2
      fi
      # WHICH REFUSAL, decided POSITIONALLY. `bind_plan` returns one code for every invalid
      # binding, so the reason is re-derived here from where the path is: a regular file in a
      # plan directory of this root is a plan that is not OPEN (delivered, abandoned, or
      # carrying no readable `## SDLC State`), and anything else is not a plan of this root
      # at all. The marker-symlink case is listed for completeness — the guard above answers
      # it first — so that every 1 from the library leaves this verb with something to say.
      BIND_MARKER="$(engaged_marker_path "$REPO_REAL" "$SESSION_ID")" || BIND_MARKER=""
      BIND_DOCS="$(docs_root "$REPO_REAL")"
      # THE SAME CANONICALIZER `bind_plan` JUST USED (AC-23). This arm carried its own copy
      # of the resolve-the-directory rule and degraded to an EMPTY `BIND_REAL` when the
      # directory would not resolve — which then fell through the location `case` below and
      # was reported as "not a plan under this root", a sentence about the wrong thing: the
      # path may well be under this root, it is the directory above it that is missing.
      # `BIND_PATH` is absolute by construction above, which is what `_bind_resolve` requires.
      BIND_REAL=""
      BIND_RESOLVED=yes
      BIND_REAL="$(_bind_resolve "$BIND_PATH")" || { BIND_REAL=""; BIND_RESOLVED=no; }
      if [ -n "$BIND_MARKER" ] && [ -L "$BIND_MARKER" ]; then
        BIND_WHY="marker is a symlink"
      elif [ "$BIND_RESOLVED" = no ]; then
        BIND_WHY="its directory does not resolve"
      else
        # THE SAME DEPTH BOUND THE SET IS BUILT WITH (review D8c, S10b). `open_runs` walks
        # `find <plans|incidents> -maxdepth 2`, so `plans/<a>/<b>/x.md` is not a candidate
        # at all. A `case` glob matches across `/`, so the location test used to call that
        # file a plan of this root and blame its CONTENT ("not an open run") for a miss the
        # walk decided before ever opening it. `BIND_TAIL` is the path below `plans/` or
        # `incidents/`: no slash is depth 1, one slash is depth 2, two or more is outside.
        BIND_TAIL=""
        case "$BIND_REAL" in
          "$BIND_DOCS"/plans/*|"$BIND_DOCS"/incidents/*)
            BIND_TAIL="${BIND_REAL#"$BIND_DOCS"/}"
            BIND_TAIL="${BIND_TAIL#*/}" ;;
        esac
        case "$BIND_TAIL" in
          ''|*/*/*)
            # Outside the walk: not under a plan directory of this root, or nested deeper
            # than the walk reaches.
            BIND_WHY="not a plan under this root" ;;
          *)
            if [ -f "$BIND_PATH" ]; then
              BIND_WHY="not an open run"
            else
              BIND_WHY="not a plan under this root"
            fi ;;
        esac
      fi
      die "REFUSED — $BIND_WHY: $BIND_PATH"
      die "A binding names a member of this root's OPEN-RUN SET — a plan under"
      die "$BIND_DOCS/{plans,incidents} whose run is still open. This session's binding is unchanged."
      exit 1
    fi
    ;;

  # THE RE-OPEN (T-h; D11; REQ-10). `verdict_row` (hooks/session-sweeper.sh) reads a name's
  # LAST roster row alone, and nothing else — `waiver=`, `deliverable=`, `launched_at=`, the
  # `claims=`/`progress=`/`cadence=` triple. `standdown-declined:` is written as a `hold`
  # (wave-26 T15), which keeps the launch; `ack` closes a row rather than opening one. Neither
  # re-opens a MET
  # lineage, so this verb is a plain append: a fresh row for the same name, launched NOW,
  # with the operator's reason recorded as `extended=<iso> <reason>`. It used to ride
  # `claims=`, the process pattern the sweeper hands to `pgrep -f`, so a reason carrying
  # `.*` held the row STILL-LIVE on any process at all (wave-20 T9, AC-4.4); `claims=` is
  # now copied from the row, like every field but the launch. The already-written deliverable then
  # dates before the new launch instant — `landing_conjunct` returns its `stale=` conjunct —
  # the verdict leaves MET for STILL-LIVE or UNMET, and the name drops off
  # `STANDDOWN_NAMES` and rejoins `OPEN`: the truthful accounting, the agent is still
  # working. The roster is APPEND-ONLY (same invariant `adopt_write_row` keeps at :1799,
  # above) — this never rewrites the row it found, only adds one after it — and `adopt_fold`
  # folds by KEY, last non-empty value per field per name, so the bumped `launched_at=` (and
  # the unmoved `deliverable=`) are exactly what a later `adopt` rebuilds from (AC-10.2).
  extend)
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "An extension answers for ONE session's roster, so without the key there is nothing to write."
      exit 3
    fi

    # THE ENGAGEMENT GUARD (AC-10), same reason and the same shape `bind` and `adopt` take
    # above: nothing bionic does applies until the session invoked the skill.
    if ! engaged_session "$(project_root "$PWD")" "$SESSION_ID"; then
      say "NOT-ENGAGED — this session has not invoked /bionic:canonical-sdlc; nothing decided"
      exit 0
    fi

    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    ROSTER_FILE="$REPO_REAL/.bionic/tmp/roster-${SESSION_ID}.state"
    if [ ! -f "$ROSTER_FILE" ] || [ -L "$ROSTER_FILE" ]; then
      die "REFUSED — no row named $EXTEND_NAME: this session has no roster at $ROSTER_FILE."
      exit 1
    fi

    # THE LAST ROW CARRYING THIS NAME IS ITS LATEST CONTRACT — the same by-name reading
    # every other reader in this file takes (e.g. the duration arm inside `tick`, below).
    # Any `roster-state/` row, the prefix `identity_args` reads, so the copy and the id stamp
    # come from one row under a schema bump (wave-22 T13; critic-3598752 I4).
    EXTEND_ROW="$(grep '^roster-state/' "$ROSTER_FILE" 2>/dev/null \
      | grep -F "|name=${EXTEND_NAME}|" | tail -1)"
    if [ -z "$EXTEND_ROW" ]; then
      die "REFUSED — no row named $EXTEND_NAME on this session's roster ($ROSTER_FILE)."
      exit 1
    fi

    EXTEND_NOW="$(iso_now)"
    # THE COPY IS `row_copy_args`'s, shared with `amend`; this verb overrides two fields: the
    # launch, bumped to now (the whole point — the old deliverable then predates it), and
    # its reason, as data. `claims=` travels with the copy, untouched.
    row_copy_args "$EXTEND_ROW" "$SESSION_ID" drop-done
    identity_args "$ROSTER_FILE" "$EXTEND_NAME" "$EXTEND_ROW"
    EXTEND_RR_ARGS=("${ROW_COPY_ARGS[@]}")
    EXTEND_RR_ARGS+=(${POKER_ID_ARGS[@]+"${POKER_ID_ARGS[@]}"})
    EXTEND_RR_ARGS+=("launched_at=$EXTEND_NOW" "extended=$EXTEND_NOW $(clean "$EXTEND_REASON")")

    EXTEND_NEW_ROW="$(roster_row "${EXTEND_RR_ARGS[@]}")" || EXTEND_NEW_ROW=""
    if [ -z "$EXTEND_NEW_ROW" ]; then
      die "REFUSED — could not build the extended row for $EXTEND_NAME."
      exit 2
    fi
    printf '%s\n' "$EXTEND_NEW_ROW" >> "$ROSTER_FILE" 2>/dev/null || {
      die "REFUSED — could not write to $ROSTER_FILE."
      exit 2
    }
    say "extended — $EXTEND_NAME is open again: $ROSTER_FILE"
    exit 0
    ;;

  # THE STANDING ANSWER TO A STAND-DOWN (wave-24 T7; REQ-4, AC-4.3; spec D1, ADR-041 d1). A
  # finished agent kept up on purpose — an auditor held for a second pass — was ordered down
  # on every tick, because the only answer the stop wall read was a `standdown-declined:` line
  # in that one turn's text. `hold` writes the answer where the tick reads its facts: a
  # successor row of the name, copied as `extend` and `amend` copy it, carrying `held=<at>
  # <reason> fp=<fingerprint>`. While the fingerprint is unchanged the tick prints `held <name>`
  # and writes no stop order, so the stop wall's stand-down set — computed from orders — has
  # nothing to ask. Any change voids it without a write: a new launch, a rewritten deliverable,
  # a new completion message. The row's launch is the copy's, so the row stays MET; unlike
  # `extend`, nothing re-opens.
  #
  # REFUSED: no session key (3), an unengaged session (decides nothing, 0), no row of the name,
  # a row that is not MET or is already closed (1). A subagent cannot reach this verb: the Bash
  # wall refuses it with `amend`, `extend` and `task-add` (payload/scripts/lib/walls.sh).
  hold)
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "A hold answers for ONE session's roster, so without the key there is nothing to write."
      exit 3
    fi
    if ! engaged_session "$(project_root "$PWD")" "$SESSION_ID"; then
      say "NOT-ENGAGED — this session has not invoked /bionic:canonical-sdlc; nothing decided"
      exit 0
    fi
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    ROSTER_FILE="$REPO_REAL/.bionic/tmp/roster-${SESSION_ID}.state"
    if [ ! -f "$ROSTER_FILE" ] || [ -L "$ROSTER_FILE" ]; then
      die "REFUSED — no row named $HOLD_NAME: this session has no roster at $ROSTER_FILE."
      exit 1
    fi
    HOLD_ROW="$(grep '^roster-state/' "$ROSTER_FILE" 2>/dev/null \
      | grep -F "|name=${HOLD_NAME}|" | tail -1)"
    if [ -z "$HOLD_ROW" ]; then
      die "REFUSED — no row named $HOLD_NAME on this session's roster ($ROSTER_FILE)."
      exit 1
    fi
    # THE VERDICT IS THE SWEEPER'S, read as the tick reads it. A hold answers a stand-down, and
    # only a MET, unacked row is ever stood down.
    SWEEPER="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/session-sweeper.sh"
    HOLD_VERDICT="$( cd "$REPO_REAL" 2>/dev/null && CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
      bash "$SWEEPER" verdict "$HOLD_NAME" 2>/dev/null | grep -F "landing-verdict/v1|" | tail -1 )"
    HOLD_STATE="$(line_field "$HOLD_VERDICT" state)"
    if [ "$HOLD_STATE" != MET ] || [ "$(line_field "$HOLD_VERDICT" acked)" = yes ]; then
      die "REFUSED — $HOLD_NAME reads ${HOLD_STATE:-no verdict}$( [ "$(line_field "$HOLD_VERDICT" acked)" = yes ] && printf ', closed'); a hold answers a stand-down, and only a MET, open row is stood down."
      exit 1
    fi
    HOLD_TR="$(session_transcript "$SESSION_ID")" || HOLD_TR=""
    HOLD_FP="$(hold_fingerprint "$HOLD_ROW" "$REPO_REAL" "$HOLD_TR")"
    HOLD_NOW="$(iso_now)"
    row_copy_args "$HOLD_ROW" "$SESSION_ID"
    identity_args "$ROSTER_FILE" "$HOLD_NAME" "$HOLD_ROW"
    HOLD_RR_ARGS=("${ROW_COPY_ARGS[@]}")
    HOLD_RR_ARGS+=(${POKER_ID_ARGS[@]+"${POKER_ID_ARGS[@]}"})
    HOLD_RR_ARGS+=("held=$HOLD_NOW $(clean "$HOLD_REASON") fp=$HOLD_FP")
    HOLD_NEW_ROW="$(roster_row "${HOLD_RR_ARGS[@]}")" || HOLD_NEW_ROW=""
    if [ -z "$HOLD_NEW_ROW" ]; then
      die "REFUSED — could not build the held row for $HOLD_NAME."
      exit 2
    fi
    printf '%s\n' "$HOLD_NEW_ROW" >> "$ROSTER_FILE" 2>/dev/null || {
      die "REFUSED — could not write to $ROSTER_FILE."
      exit 2
    }
    say "held — $HOLD_NAME stays up while its launch, deliverable and messages are unchanged (fp=$HOLD_FP); the tick prints it held and orders no stop: $ROSTER_FILE"
    exit 0
    ;;

  # THE FILL'S ANSWER, RECORDED (wave-27 T34; REQ-15 AC-15.1, AC-15.5; D24; design ledger Δ9). The
  # turn-end wall read its answer out of the reply, so the orchestrator answered it with a
  # `fill-declined:` line the user read on every turn. As `hold` writes the stand-down's answer where
  # the tick reads its facts, this verb writes the fill's where the wall and the tick read it: the
  # line a reply-form turn leaves in the run's fill ledger (`fill_ledger_path`), `ready=` the rows it
  # answers, `declined=` the reason, `at=` the time, `session=` this session. So
  # `fill_standing_decline` (lib/fill.sh), the one reader of both, applies its one rule: the line
  # answers those rows and stands until a row it did not name is ready. The rows a decline already
  # standing answers ride into the new line, as a reply-form turn's ready set carries them, so a
  # second decline never un-answers the first's rows. `named=` keeps this call's ids; `state=decline`
  # and an empty `turn=` say no Stop wrote it, so `fill-report` charges the interval after it to the
  # decline as one interval of its own. One printf, appended; a ledger that is a symlink is not
  # written through.
  #
  # REFUSED: no session key (3), an unengaged session (decides nothing, 0), no run (1), an id that is
  # no row of the plan or a row that is not ready (1, naming each), a reason with no letter or digit
  # (1), a ledger that cannot be written (2). A subagent cannot reach this verb: walls.sh refuses it.
  decline)
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "A decline answers for ONE session's turn-end wall, so without the key there is nothing to write."
      exit 3
    fi
    if ! engaged_session "$(project_root "$PWD")" "$SESSION_ID"; then
      say "NOT-ENGAGED — this session has not invoked /bionic:canonical-sdlc; nothing decided"
      exit 0
    fi
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    sched_budget_read "$REPO_REAL" "$SESSION_ID"
    if [ -z "$SCHED_PLAN" ] || [ "$POKER_RUN_OPEN" = unreadable ]; then
      die "REFUSED — a decline answers this session's run, and no readable plan was resolved (${SCHED_PLAN:-none}); nothing was recorded."
      exit 1
    fi
    # THE SAME READY SET THE WALL OWES: every ready row, untrimmed (`fill_ready_tagged`), at the head
    # the tick reads (`sched_budget_read` set it).
    DC_ROWS=" $(units_rows "$SCHED_PLAN" 2>/dev/null | cut -f1 | tr '\n' ' ')"
    DC_READY=" $(fill_ready_tagged "$SCHED_PLAN" 2>/dev/null | cut -f1 | tr '\n' ' ')"
    DC_NAMED=""; DC_NOROW=""; DC_NOTREADY=""
    IFS=', ' read -r -a DC_LIST <<< "$DC_IDS"
    for DC_ID in ${DC_LIST[@]+"${DC_LIST[@]}"}; do
      [ -n "$DC_ID" ] || continue
      case " $DC_NAMED $DC_NOROW $DC_NOTREADY " in *" $DC_ID "*) continue ;; esac
      case "$DC_ROWS" in
        *" $DC_ID "*) : ;;
        *) DC_NOROW="${DC_NOROW}${DC_NOROW:+ }$(clean "$DC_ID")"; continue ;;
      esac
      case "$DC_READY" in
        *" $DC_ID "*) DC_NAMED="${DC_NAMED}${DC_NAMED:+ }$DC_ID" ;;
        *) DC_NOTREADY="${DC_NOTREADY}${DC_NOTREADY:+ }$DC_ID" ;;
      esac
    done
    if [ -n "$DC_NOROW" ]; then
      die "REFUSED — decline names $DC_NOROW, no row of $SCHED_PLAN; nothing was recorded."
      exit 1
    fi
    if [ -n "$DC_NOTREADY" ]; then
      DC_RNOW="$(printf '%s' "$DC_READY" | sed 's/^ *//; s/ *$//')"
      die "REFUSED — decline names $DC_NOTREADY, not ready, and only a ready row is declined (ready now: ${DC_RNOW:-none}); nothing was recorded."
      exit 1
    fi
    DC_WHY="$(printf '%s' "$DC_REASON" | tr '|\n\r\t' '    ')"
    DC_WHY="${DC_WHY:0:200}"
    # THE PRINTED PLACEHOLDER IS NO REASON (wave-27 T37; review pass 42 N1, A-orch-112): the wall's
    # refusal prints this verb with DECLINE_REASON_SLOT where the reason goes, and the line run as
    # printed recorded the placeholder as the reason.
    DC_SLOT="${DECLINE_REASON_SLOT//\'/}"
    DC_TRIM="$(printf '%s' "$DC_WHY" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    if [ "$DC_TRIM" = "$DC_SLOT" ]; then
      die "REFUSED — '$DC_SLOT' is the placeholder the refusal prints, not a reason: put the reason in its place; nothing was recorded."
      exit 1
    fi
    case "$DC_WHY" in
      *[[:alnum:]]*) : ;;
      *)
        die "REFUSED — a decline is a reason, and '$(clean "$DC_WHY")' carries no letter or digit; nothing was recorded."
        exit 1 ;;
    esac
    DC_LED="$(fill_ledger_path "$REPO_REAL" "$SCHED_PLAN" 2>/dev/null)" || DC_LED=""
    DC_ALL="$DC_NAMED"
    DC_SD="$(fill_standing_decline "$DC_LED" "$SESSION_ID" "")"
    if [ -n "$DC_SD" ]; then
      IFS=$'\037' read -r _ _ DC_SD_IDS <<< "$DC_SD"
      for DC_ID in $DC_SD_IDS; do
        case "$DC_READY" in *" $DC_ID "*) : ;; *) continue ;; esac
        case " $DC_ALL " in *" $DC_ID "*) : ;; *) DC_ALL="${DC_ALL} ${DC_ID}" ;; esac
      done
    fi
    if [ -z "$DC_LED" ] || [ -L "$DC_LED" ] || ! mkdir -p "${DC_LED%/*}" 2>/dev/null; then
      die "REFUSED — the run's fill ledger (${DC_LED:-no path}) cannot be written; nothing was recorded."
      exit 2
    fi
    DC_CUR="$(_fill_current_field "$SCHED_PLAN")"
    DC_LINE="fill-ledger/v1|at=$(iso_now)|session=${SESSION_ID}|turn=|current=${DC_CUR//|/ }|state=decline"
    DC_LINE="${DC_LINE}|ceiling=${SCHED_WRITERS}|width=|open=|free=|ready=${DC_ALL// /,}|launched="
    DC_LINE="${DC_LINE}|declined=${DC_WHY}|missed=0|idle=|room=|named=${DC_NAMED// /,}"
    if ! printf '%s\n' "$DC_LINE" >> "$DC_LED" 2>/dev/null; then
      die "REFUSED — could not write to $DC_LED; nothing was recorded."
      exit 2
    fi
    say "decline — ${DC_NAMED// /,}: recorded in $DC_LED; it stands for those rows until a row it did not name is ready."
    exit 0
    ;;

  # THE USER'S WRITER CAP (wave-27 T34; REQ-15 AC-15.4; D24; design ledger Δ10). A cap the user
  # chose is a fact, not a decline to repeat on every turn: it is written once into the plan header
  # every reader of the ceiling already reads (`plan_budget_line`, `budget_field` in lib/run.sh: the
  # dispatch wall, the tick and the turn-end wall). `parallel-budget:` keeps its other fields, its
  # `writers=` becomes the user's and its `source=` reads `user`; the frontmatter gains
  # `budget-override: <git user.name> <date> derived=<n> chosen=<n>`, the sibling of
  # `rigor-override:`. `derived=` is the probe's value, read from an override already there so a
  # second cap keeps it, and the one override line is rewritten, never doubled.
  # THE VERB ONLY LOWERS (wave-27 T37; review pass 42 N2, A-orch-112). It takes a reply nothing can
  # verify, so it must not be a way for a model to raise its own cap: a value above the derived
  # ceiling is refused, and raising it is the user's own edit of the plan's `parallel-budget:` line.
  # (T74 narrowed "the derived ceiling" to the cap in force; see below.)
  # A PLAN WITH NO LINE GETS ONE (wave-28 T9; D15, REQ-2 AC-2.10). No plan owes a budget line, so
  # the verb no longer refuses a plan without one: it writes `parallel-budget: writers=<n>
  # source=user` directly below the opening `---`, and `budget-override: <who> <date> chosen=<n>`
  # under it, with no `derived=` because nothing was derived.
  # It goes through the plan transaction every plan verb takes. REFUSED: a value that is not a
  # whole number, or 0 (1); one above the cap in force (1); a reply with a line break (1); a
  # `writers=`/`derived=` on the plan's lines that is not 1 to 4 digits, or a plan with no
  # leading frontmatter to write into (1).
  # The cap in force asked again is the plan transaction's no-op: "already reads so" (0).
  budget)
    case "$BG_N" in
      ''|*[!0-9]*)
        die "REFUSED — writers=$(clean "$BG_N") is not a whole number of writers; the plan is unchanged."
        exit 1 ;;
    esac
    if [ "${#BG_N}" -gt 9 ]; then
      die "REFUSED — writers=$BG_N is past any machine's budget; the plan is unchanged."
      exit 1
    fi
    BG_N=$((10#$BG_N))
    if [ "$BG_N" -eq 0 ]; then
      die "REFUSED — writers=0 is no budget: a run with no writer slot fills nothing. Name one or more; the plan is unchanged."
      exit 1
    fi
    case "$BG_REPLY" in
      *$'\n'*|*$'\r'*)
        die "REFUSED — the user's reply carries a line break; give it on one line. The plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open budget
    # THE CAP IN FORCE IS THE PLAN'S OWN (wave-27 T74; review pass 53 N4 ruled, A-orch-145). "At or
    # below the ceiling the machine derived" let a reply undo the user's 3 back up to the probe's 8.
    # The verb now records n only at or below the cap the plan states NOW: the `parallel-budget:`
    # line's `writers=`, the one value every reader of the ceiling reads, which the verb's own
    # override writes and a user's hand edit sets. A raise, by any amount, is the user's own edit.
    # A CEILING THAT IS NOT A NUMBER REFUSES (N5): each `writers=` and `derived=` the verb reads off
    # the frontmatter is one to four digits, or the verb names the line and records nothing; it
    # never compares as "not greater". `derived=` is the probe's value, carried as a record.
    BG_LINES="$(awk '
      NR == 1 && $0 == "---" { f = 1; next }
      f && $0 == "---" { exit }
      f && /^(parallel-budget|budget-override):/ { print }' "$PV_PLAN")"
    BG_HAVE=""; BG_DERIVED=""
    for BG_KF in parallel-budget:writers budget-override:derived; do
      BG_K="${BG_KF%%:*}"; BG_F="${BG_KF#*:}"
      BG_L="$(printf '%s\n' "$BG_LINES" | grep -m1 "^${BG_K}:")" || BG_L=""
      [ -n "$BG_L" ] || continue
      BG_S=" ${BG_L#*:} "; BG_S="${BG_S//$'\t'/ }"
      case "$BG_S" in
        *" ${BG_F}="*) BG_V="${BG_S#* "${BG_F}"=}"; BG_V="${BG_V%% *}" ;;
        *) continue ;;
      esac
      case "$BG_V" in
        [0-9]|[0-9][0-9]|[0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]) : ;;
        *)
          die "REFUSED — the plan's ${BG_K}: line holds a ${BG_F}= that is not one to four digits."
          die "Nothing was recorded; the plan is unchanged. The line: $(clean "$BG_L" | cut -c1-160) (in $PV_PLAN)"
          exit 1 ;;
      esac
      if [ "$BG_F" = writers ]; then BG_HAVE=$((10#$BG_V)); else BG_DERIVED=$((10#$BG_V)); fi
    done
    # THE CAP IN FORCE IS A PERSON'S (wave-28 T9; D15): `budget_cap`, which answers only from a
    # `source=user` or `source=override` line. A probe's `writers=` caps nothing, so the verb
    # records any n over it; the probe's figure is still carried as `derived=`.
    BG_CAP="$(budget_cap "$PV_PLAN")"; BG_CAP="${BG_CAP#writers=}"
    [ -n "$BG_DERIVED" ] || BG_DERIVED="$BG_HAVE"
    if [ -n "$BG_CAP" ] && [ "$BG_N" -gt "$BG_CAP" ]; then
      die "REFUSED — writers=$BG_N is above the cap in force ($BG_CAP): budget only lowers it."
      die "Raising it is the user's own edit of the plan's parallel-budget: line in $PV_PLAN; the plan is unchanged."
      exit 1
    fi
    BG_LINE=1
    case "$BG_LINES" in 'parallel-budget:'*|*$'\n''parallel-budget:'*) : ;; *) BG_LINE=0 ;; esac
    BG_WHO="$(git -C "$PV_REPO" config user.name 2>/dev/null)"
    if [ -z "$BG_WHO" ] || ! plan_verb_value_ok "$BG_WHO"; then
      die "REFUSED — the project has no usable git user name (git config user.name) to record as the one who capped it; the plan is unchanged."
      exit 1
    fi
    BG_OVR="budget-override: $BG_WHO $(date -u +%Y-%m-%d)${BG_DERIVED:+ derived=$BG_DERIVED} chosen=$BG_N"
    # THE VALUES GO IN THROUGH THE ENVIRONMENT, as approve's line does: `-v` would read a backslash
    # in a user name as an escape.
    if ! BG_OVR="$BG_OVR" BG_N="$BG_N" BG_LINE="$BG_LINE" awk '
      NR == 1 && $0 == "---" {
        f = 1; print
        if (ENVIRON["BG_LINE"] == "0") {
          print "parallel-budget: writers=" ENVIRON["BG_N"] " source=user"
          print ENVIRON["BG_OVR"]; done = 1
        }
        next
      }
      f && $0 == "---" { f = 0; print; next }
      f && /^budget-override:/ { next }
      f && !done && /^parallel-budget:/ {
        v = $0; sub(/^parallel-budget:[ \t]*/, "", v)
        n = split(v, w, /[ \t]+/); out = ""; wr = 0; src = 0
        for (i = 1; i <= n; i++) {
          if (w[i] == "") continue
          if (!wr && w[i] ~ /^writers=/) { w[i] = "writers=" ENVIRON["BG_N"]; wr = 1 }
          else if (!src && w[i] ~ /^source=/) { w[i] = "source=user"; src = 1 }
          out = out (out == "" ? "" : " ") w[i]
        }
        if (!wr) out = "writers=" ENVIRON["BG_N"] (out == "" ? "" : " ") out
        if (!src) out = out " source=user"
        print "parallel-budget: " out
        print ENVIRON["BG_OVR"]
        done = 1; next
      }
      { print }
      END { if (!done) exit 1 }' "$PV_PLAN" > "$PV_NEW" 2>/dev/null; then
      die "REFUSED — $PV_PLAN has no leading frontmatter to write the cap into; the plan is unchanged."
      exit 1
    fi
    plan_verb_swap budget "writers=$BG_N (source=user)" writer
    say "budget — writers=$BG_N source=user and $BG_OVR written to $PV_PLAN; dry-committed first. The dispatch wall, the tick and the turn-end wall read it from the header."
    exit 0
    ;;

  # THE CONTRACT CHANGE (wave-20 T9; REQ-4, AC-4.1/4.2; spec D4, ledger Δ10). A writer's
  # Files:, Suites: and Re-executes: are read from its roster row, captured at dispatch —
  # editing the plan row changes nothing — and until this verb the only way to widen one was
  # a re-dispatch. `amend` appends a SUCCESSOR row, copied from the name's latest
  # (`row_copy_args`, the copy `extend` takes), with each addition merged in: a union, old
  # members first, never a narrowing. `launched_at=` and `tool_use_id=` are the copy's; the
  # identity — `status=`, `agent_id=`, `teammate_id=` — is the agent's latest identified
  # self (`identity_args`, wave-22 T1, D1), because the budget wall keys on the id, NOT the
  # name, and a teammate's latest row can carry none. The one rule is
  # payload/scripts/lib/roster.sh's, above `roster_row_for_id`; the success line asks that
  # function whether the wall will read the row just written (D3) before it says so.
  # `amended=<iso> <reason>` records when and why; `session=` who.
  #
  # THE MERGED FIELDS ARE JUDGED BY THE DISPATCH WALL'S GRAMMAR (Δ10). The verb builds the
  # span a brief carrying the merged contract would hold — `Files:`, `Suites:`,
  # `Re-executes:` — and hands it to `brief_validate_fields` with the row's own role and its
  # `questions=` as a `Questions:` line, so the three-run cap binds a reader holding the
  # `evidence` question here as it does at dispatch (`dp_reads_evidence`, lib/brief.sh). A declared budget stays
  # declared (the old set plus the added suites); a DERIVED one is re-derived from the
  # merged files by the configured impact command, and the old set is kept beside it.
  #
  # THE TARGET is a name, or an agent id (wave-27 T38): an id a named row carries amends that
  # row; an id no row carries, of an agent of this session, is recorded by `amend_unplaced`.
  #
  # REFUSED: no session key (3), an unengaged session (decides nothing, 0), no row of the
  # name and no agent of the id, a CLOSED row — `roster_open_names`, the one close predicate: an ack later than the
  # latest launch — and a change the row already carries (1), and anything the grammar
  # refuses (1). A subagent cannot reach this verb at all: the Bash wall refuses `amend`,
  # `extend` and `task-add` in any payload carrying an `agent_id` (payload/scripts/lib/walls.sh).
  amend)
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "An amendment answers for ONE session's roster, so without the key there is nothing to write."
      exit 3
    fi
    if ! engaged_session "$(project_root "$PWD")" "$SESSION_ID"; then
      say "NOT-ENGAGED — this session has not invoked /bionic:canonical-sdlc; nothing decided"
      exit 0
    fi
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    ROSTER_FILE="$REPO_REAL/.bionic/tmp/roster-${SESSION_ID}.state"
    if [ ! -f "$ROSTER_FILE" ] || [ -L "$ROSTER_FILE" ]; then
      die "REFUSED — no row named $AMEND_NAME: this session has no roster at $ROSTER_FILE."
      exit 1
    fi
    # Any `roster-state/` row, as `identity_args` reads (wave-22 T13; critic-3598752 I4).
    AM_ROW="$(grep '^roster-state/' "$ROSTER_FILE" 2>/dev/null \
      | grep -F "|name=${AMEND_NAME}|" | tail -1)"
    # ---- BEGIN amend by agent id (wave-27 T38; review pass 8 F3) ----
    # THE TARGET A BUDGET REFUSAL PRINTS FOR AN AGENT NO ROW CARRIES is its agent id: a start the
    # recorder could not place (two launches of its type, or a type that is not a bionic: role) has
    # no row until its launch call returns, and a foreground call returns when it has finished. So
    # `amend` reads its target as a name first and as an agent id second. An id a named row carries
    # amends that row. An id no row carries, that ran as an agent of this session (its transcript
    # is on disk), gets a row of its own: `status=unplaced`, named by the id, carrying the added
    # suites and runs and no contract (a waiver says so, so no verdict judges it, and no reader of
    # live rows counts it). The budget wall keys on the id, so it reads that row from the next call.
    # An id that is neither is refused, saying why; this verb never exits 0 having changed nothing.
    # AFTER THE PLACING (wave-27 T37; review pass 36 N2): an `unplaced` row named by the id, written
    # before the agent was placed, is not the id's row any more once a placed row carries the id
    # after it. The amend goes to the placed row, and the set the unplaced row recorded goes with
    # it as additions, so one row speaks for the agent and holds both; no second unplaced row is
    # written to shadow the placed one.
    if [ -z "$AM_ROW" ] || [ "$(line_field "$AM_ROW" status)" = unplaced ]; then
      AM_IDROW="$(roster_row_for_id "$ROSTER_FILE" "$AMEND_NAME")" || AM_IDROW=""
      AM_IDNAME="$(line_field "$AM_IDROW" name)"
      if [ -n "$AM_IDNAME" ] && [ "$(line_field "$AM_IDROW" status)" != unplaced ] \
         && { [ -z "$AM_ROW" ] || [ "$AM_IDNAME" != "$AMEND_NAME" ]; }; then
        if [ -n "$AM_ROW" ]; then
          AM_UP_SA="$(line_field "$AM_ROW" suites_allowed)"
          [ "$AM_UP_SA" = none ] || AMEND_SUITES="${AMEND_SUITES}${AM_UP_SA}"$'\n'
          if row_has_key "$AM_ROW" re_executes; then
            AMEND_RUNS="${AMEND_RUNS}$(poker_marked_runs "$(clean "$(line_field "$AM_ROW" re_executes)" re_executes)")"$'\n'
          fi
        fi
        AMEND_NAME="$AM_IDNAME"
        AM_ROW="$(grep '^roster-state/' "$ROSTER_FILE" 2>/dev/null \
          | grep -F "|name=${AMEND_NAME}|" | tail -1)"
      else
        amend_unplaced "$AMEND_NAME" "$AM_IDROW"
        exit $?
      fi
    fi
    # ---- END amend by agent id ----
    if [ -z "$AM_ROW" ]; then
      die "REFUSED — no row named $AMEND_NAME on this session's roster ($ROSTER_FILE)."
      exit 1
    fi
    AM_OPEN="$(roster_open_names "$ROSTER_FILE" "$REPO_REAL/.bionic/tmp/sweeper-${SESSION_ID}.state" "$SESSION_ID")"
    if ! grep -qxF -- "$AMEND_NAME" <<< "$AM_OPEN"; then
      die "REFUSED — $AMEND_NAME is closed: it was acked after its latest launch, or holds no live row. A closed contract is not amended; dispatch the work again."
      exit 1
    fi
    if ! poker_brief_load; then
      die "REFUSED — the contract grammar (lib/brief.sh) cannot be loaded from $BIONIC_LIB; nothing was written."
      exit 2
    fi

    AM_ROLE="$(line_field "$AM_ROW" subagent_type)"
    AM_OLD_FILES="$(line_field "$AM_ROW" files)"
    AM_OLD_SA="$(line_field "$AM_ROW" suites_allowed)"
    AM_OLD_SRC="$(line_field "$AM_ROW" suites_source)"
    AM_OLD_RUNS=""
    row_has_key "$AM_ROW" re_executes && AM_OLD_RUNS="$(clean "$(line_field "$AM_ROW" re_executes)" re_executes)"

    # THE ADDITIONS AS THE GRAMMAR READS THEM, alone: what each flag contributes once lifted.
    # The Files: reader is the dispatch wall's (wave-27 T29, T42; REQ-12, D21), so
    # `--files+ CONTEXT.md` is the path a dispatch would have recorded.
    # EACH --files+ VALUE ON ITS OWN (wave-27 T34; review pass 19 should-fix 2, A-orch-70), as the
    # dispatch wall reads one line: joined into one Files: line, a ` #` note in one value hid every
    # later one. A value the reader records nothing from goes to the grammar as typed, below.
    AM_ADD="$(lift_contract_fields "$(poker_brief_span "" "$AMEND_SUITES" "" "$AMEND_RUNS")" "$AM_ROLE")"
    AM_ADD_FILES=""; AM_TYPED=""
    while IFS= read -r AM_F; do
      [ -n "$AM_F" ] || continue
      AM_FL="$(brief_field "$(lift_contract_fields "Files: $AM_F" "$AM_ROLE")" files)"
      AM_ADD_FILES="$(poker_union , "$AM_ADD_FILES" "$AM_FL")"
      if [ -n "$AM_FL" ]; then AM_TYPED="${AM_TYPED}$(printf '%s' "$AM_FL" | tr ',' '\n')"$'\n'
      else AM_TYPED="${AM_TYPED}${AM_F}"$'\n'; fi
    done <<< "$AMEND_FILES"
    AM_NEW_FILES="$(poker_union , "$AM_OLD_FILES" "$AM_ADD_FILES")"
    AM_Q="$(line_field "$AM_ROW" questions)"

    # THE DECLARED HALF OF THE BUDGET. A declared (or unlabelled) budget carries its old set
    # into the span; a derived one is not a declaration and is re-derived below. `none` is a
    # waiver, and it yields to the first suite actually added.
    AM_DECL=""
    [ "$AM_OLD_SRC" = derived ] || AM_DECL="$AM_OLD_SA"
    AM_DECL="$(poker_union ' ' "$AM_DECL" "$(printf '%s' "$AMEND_SUITES" | tr '\n,' '  ')")"
    case " $AM_DECL " in
      *" none "*) [ "$AM_DECL" = none ] \
                    || AM_DECL="$(printf '%s' "$AM_DECL" | tr ' ' '\n' | awk '$0 != "none" && $0 != ""' | tr '\n' ' ')"
                  AM_DECL="${AM_DECL% }" ;;
    esac

    # The additions go into the span as typed, beside the merged set, so an entry the reader
    # does not read as a path reaches the grammar and is refused by name, never dropped.
    AM_SPAN="$(poker_brief_span "$(printf '%s' "$AM_NEW_FILES" | tr ',' '\n')"$'\n'"$AM_TYPED" "$AM_DECL" "$AM_OLD_RUNS" "$AMEND_RUNS")"
    # THE ROW'S QUESTIONS GO WITH IT (wave-27 T34; T15's report item 1, A-orch-73), so a reader
    # holding `evidence` meets the cap a dispatch of it would.
    [ -n "$AM_Q" ] && AM_SPAN="${AM_SPAN}"$'\n'"Questions: ${AM_Q//,/, }"
    AM_LIFT="$(lift_contract_fields "$AM_SPAN" "$AM_ROLE")"
    POKER_BRIEF_FACTS=""; POKER_BRIEF_WORDS=""
    AM_RC=0
    brief_validate_fields "$AM_LIFT" "$AM_ROLE" "$REPO_REAL" poker_brief_sink || AM_RC=$?
    AM_SA="$BRIEF_SUITES_ALLOWED"; AM_SRC="$BRIEF_SUITES_SOURCE"
    # A derived budget with suites added too: the span declared, so nothing was derived — ask
    # the impact command for the merged files on their own.
    if [ "$AM_RC" -eq 0 ] && [ "$AM_OLD_SRC" = derived ] && [ -n "$AM_DECL" ] && [ -n "$AM_NEW_FILES" ]; then
      brief_validate_fields "$(lift_contract_fields "Files: $AM_NEW_FILES" "$AM_ROLE")" \
        "$AM_ROLE" "$REPO_REAL" poker_brief_sink || AM_RC=$?
      AM_SA="$(poker_union ' ' "$AM_SA" "$BRIEF_SUITES_ALLOWED")"
    fi
    if [ "$AM_RC" -ne 0 ]; then
      die "REFUSED — a dispatch carrying $AMEND_NAME's amended contract would be refused; nothing was written:"
      printf '%s' "$POKER_BRIEF_WORDS" >&2
      exit 1
    fi

    # THE UNION ON THE ROW. A derived budget keeps its old set beside the new derivation, and a
    # waiver that nothing replaced stays the waiver.
    [ "$AM_OLD_SRC" = derived ] && AM_SA="$(poker_union ' ' "$AM_OLD_SA" "$AM_SA")"
    [ -n "$AM_SA" ] || AM_SA="$AM_OLD_SA"
    AM_SRC="${AM_OLD_SRC:-$AM_SRC}"
    AM_NEW_RUNS="$AM_OLD_RUNS"
    AM_OLD_RUN_SET="$(poker_marked_runs "$AM_OLD_RUNS")"
    while IFS= read -r AM_R; do
      [ -n "$AM_R" ] || continue
      grep -qxF -- "$AM_R" <<< "$AM_OLD_RUN_SET" && continue
      AM_NEW_RUNS="${AM_NEW_RUNS:+$AM_NEW_RUNS }\`${AM_R}\`"
    done <<EOF
$(poker_marked_runs "$(brief_field "$AM_ADD" re_executes)")
EOF

    if [ "$AM_NEW_FILES" = "$AM_OLD_FILES" ] && [ "$AM_SA" = "$AM_OLD_SA" ] \
       && [ "$AM_NEW_RUNS" = "$AM_OLD_RUNS" ]; then
      die "REFUSED — this amend changes nothing: every addition is already on $AMEND_NAME's row, or is not a path, suite or run the dispatch grammar reads. Nothing was written."
      exit 1
    fi

    row_copy_args "$AM_ROW" "$SESSION_ID"
    identity_args "$ROSTER_FILE" "$AMEND_NAME" "$AM_ROW"
    AM_ARGS=("${ROW_COPY_ARGS[@]}")
    AM_ARGS+=(${POKER_ID_ARGS[@]+"${POKER_ID_ARGS[@]}"})
    { [ -n "$AM_NEW_FILES" ] || row_has_key "$AM_ROW" files; } && AM_ARGS+=("files=$AM_NEW_FILES")
    if [ -n "$AM_SA" ] || row_has_key "$AM_ROW" suites_allowed; then
      AM_ARGS+=("suites_allowed=$AM_SA")
      [ -n "$AM_SRC" ] && AM_ARGS+=("suites_source=$AM_SRC")
    fi
    { [ -n "$AM_NEW_RUNS" ] || row_has_key "$AM_ROW" re_executes; } && AM_ARGS+=("re_executes=$AM_NEW_RUNS")
    AM_ARGS+=("amended=$(iso_now) $(clean "$AMEND_REASON")")
    AM_NEW_ROW="$(roster_row "${AM_ARGS[@]}")" || AM_NEW_ROW=""
    if [ -z "$AM_NEW_ROW" ]; then
      die "REFUSED — could not build the amended row for $AMEND_NAME."
      exit 2
    fi
    printf '%s\n' "$AM_NEW_ROW" >> "$ROSTER_FILE" 2>/dev/null || {
      die "REFUSED — could not write to $ROSTER_FILE."
      exit 2
    }
    # THE SUCCESS LINE CHECKS ITSELF (wave-22 T1; REQ-1 AC-1.6, D3). It used to print
    # unconditionally, and the wall it promised went on reading the pre-amend row (wave-22
    # seed). Now the verb asks `roster_row_for_id` — the budget wall's own pick, one function
    # in payload/scripts/lib/roster.sh — whether the row it just wrote is the row the wall
    # reads for this agent's id. No id yet: no wall keys on this agent before it is
    # identified (the budget arm's actor is the transcript id), and the recorder's
    # `identified` row inherits this successor whole, so the line says when, not now.
    # AN ID-LESS ROW (wave-27 T38): the set is recorded, on the row the identification copies — the
    # recorder's start join, or its launch call's return (ARM 2 copies the launch's last row). An
    # agent of it already running unplaced is not that row's until then; its refusal prints its id.
    if [ -z "$POKER_ID" ]; then
      say "amended — the walls read this row once $AMEND_NAME is identified, at its start or its launch call's return; an agent already running unplaced is amended by the agent id its refusal prints"
      exit 0
    fi
    AM_PICK="$(roster_row_for_id "$ROSTER_FILE" "$POKER_ID")" || AM_PICK=""
    if [ "$AM_PICK" != "$AM_NEW_ROW" ]; then
      AM_WROTE_ID="$(line_field "$AM_NEW_ROW" agent_id)"
      if [ -z "$AM_PICK" ]; then
        AM_WHY="no row carries that id"
      elif [ "$AM_WROTE_ID" != "$POKER_ID" ]; then
        AM_WHY="the row amend wrote carries agent_id=${AM_WROTE_ID:-(empty)}, so a wall keyed on $POKER_ID never reaches it"
      else
        AM_WHY="a later row carrying that id was written after it"
      fi
      die "amend written, but the budget wall reads $(line_field "$AM_PICK" status) row for $POKER_ID — $AM_WHY"
      exit 1
    fi
    # The stop wall and observe pick an id's row from `confirmed|identified` rows only
    # (stop-guard.sh), so a successor that copied a `duplicate-start` row is read by the budget
    # wall alone — the line names only the walls that read it (wave-22 T10; review 4).
    case "$(line_field "$AM_NEW_ROW" status)" in
      confirmed|identified) AM_WALLS="the stop and budget walls read" ;;
      *)                    AM_WALLS="the budget wall reads" ;;
    esac
    say "amended — $AMEND_NAME: files=${AM_NEW_FILES:-(none)} suites=${AM_SA:-(none)}${AM_NEW_RUNS:+ runs=$AM_NEW_RUNS}; $AM_WALLS this row from now on."
    exit 0
    ;;

  # THE ROW-ADD VERB (wave-20 REQ-5, AC-5.3; Δ5, research D1 §3). A schedule change is a
  # TRANSACTION: `units_add_row` projects the row onto a COPY of the bound plan (the row and its
  # `- <id>:` line, and no other row), the copy is
  # judged twice — by `units_validate`, and by a dry `git commit` through the REAL
  # hooks/bash-walls.sh — and only a copy both admit is moved over the plan. On any refusal
  # the plan is byte-identical and the words that refused it print. The precedent is
  # close-out.sh's D5: a script writes a lifecycle artifact only where a gate validates what
  # it wrote. Nothing else judges a Bash write of the plan: the governing-skill hook sees
  # Write and Edit only.
  #
  # THE TRANSACTION IS SHARED (wave-24 T15): `plan_verb_open` and `plan_verb_swap`, above the
  # verbs, carry the dry commit — a writer's, judged by the task arms, so the dry copy carries
  # `current: 4` when the run is past it and the copy swapped in keeps the run's own
  # `current:` — the copy's own engagement marker, the checksum and the swap. What is task-add's
  # alone is below: a run below Step 4 is refused, the Files cell is judged by the dispatch
  # grammar, and the projection is `units_add_row`, judged by `units_validate` before the gate.
  task-add)
    plan_verb_open task-add
    TA_PLAN="$PV_PLAN"; REPO_REAL="$PV_REPO"
    TA_CUR="${PV_CUR%[ab]}"
    case "$TA_CUR" in
      ''|*[!0-9]*)
        die "REFUSED — $TA_PLAN has current: ${TA_CUR:-(none)}; task-add changes a wave plan past Step-3 approval, whose current: is a step number."
        exit 1 ;;
    esac
    if [ "$TA_CUR" -lt 4 ]; then
      die "REFUSED — $TA_PLAN is at current: $TA_CUR; before Step-3 approval the plan is written by hand and reviewed, not added to."
      exit 1
    fi

    # A READ NEEDS A COLUMN TO GO IN (wave-26 T59; REQ-5 AC-5.4). The projection drops a value
    # its table has no column for, so a reads operand on a table without one would be accepted
    # and lost, and the row would wait on nothing it declared. Refused instead, in one line.
    # `—` (or `-`, or empty) declares nothing and is the nine-operand form; in a reads table it
    # is the cell `—`, which the readiness program reads as the kind's default (lib/units.sh).
    case "$TA_READS" in
      ''|'—'|'-') : ;;
      *)
        if ! units_has_column "$TA_PLAN" reads; then
          die "REFUSED — the ## Tasks table of $TA_PLAN has no reads column, so the reads operand '$(clean "$TA_READS")' has nowhere to go; add the column, or name what $TA_ID waits for in its deps. The plan is unchanged."
          exit 1
        fi
        ;;
    esac

    # THE FILES CELL IS JUDGED BY THE DISPATCH GRAMMAR (wave-20 T9; D4, Δ10; T6 carry-over).
    # The cell becomes a brief's `Files:` line at dispatch, so it is read here exactly as the
    # dispatch wall will read it: a cell the lift reads as no path — a template slot, a bare
    # word — is refused now, in the grammar's words, rather than forty minutes later at the
    # dispatch of a row nobody can fix from the table. `—` is the table's "none" and declares
    # nothing to judge. TWO FACTS ARE THE REPOSITORY'S, NOT THE CELL'S: no configured impact
    # command, and one that overran its bound. A dispatch answers either with a `Suites:`
    # line, which the plan row has no column for, so here they are notes and the row goes in.
    case "$TA_FILES" in
      ''|'—'|'-') : ;;
      *)
        if ! poker_brief_load; then
          die "REFUSED — the contract grammar (lib/brief.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
          exit 2
        fi
        POKER_BRIEF_FACTS=""; POKER_BRIEF_WORDS=""
        brief_validate_fields "$(lift_contract_fields "Files: $TA_FILES" "$TA_AGENT")" \
          "$TA_AGENT" "$REPO_REAL" poker_brief_sink || :
        TA_CELL_FACTS=""
        while IFS= read -r TA_FACT; do
          [ -n "$TA_FACT" ] || continue
          case "$TA_FACT" in
            'no impact command is configured here'|'the impact command did not answer')
              note "$TA_FACT — a dispatch of $TA_ID whose brief carries only this Files: line will need a Suites: line" ;;
            *) TA_CELL_FACTS="${TA_CELL_FACTS}${TA_FACT}"$'\n' ;;
          esac
        done <<EOF
$POKER_BRIEF_FACTS
EOF
        if [ -n "$TA_CELL_FACTS" ]; then
          die "REFUSED — a dispatch of $TA_ID with Files: $TA_FILES would be refused by the dispatch grammar; the plan is unchanged:"
          printf '%s' "$POKER_BRIEF_WORDS" >&2
          exit 1
        fi
        ;;
    esac

    if ! units_add_row "$TA_PLAN" "$TA_ID" "$TA_STEP" "$TA_KIND" "$TA_TASK" "$TA_AGENT" \
         "$TA_DEPS" "$TA_SIZE" "$TA_SERVES" "$TA_FILES" "$TA_READS" > "$PV_NEW" 2>/dev/null || [ ! -s "$PV_NEW" ]; then
      die "REFUSED — $TA_PLAN carries no ## Tasks table or no ## SDLC State section to add $TA_ID to; the plan is unchanged."
      exit 1
    fi

    TA_VIOL="$(units_validate "$PV_NEW" 2>&1)"
    if [ -n "$TA_VIOL" ]; then
      die "REFUSED — with $TA_ID added, the ## Tasks table breaks the Task invariants; the plan is unchanged:"
      printf '%s\n' "$TA_VIOL" >&2
      exit 1
    fi

    plan_verb_swap task-add "$TA_ID added" writer
    say "task-add — $TA_ID added to $TA_PLAN: the row and its - $TA_ID: line; validated and dry-committed first."
    exit 0
    ;;

  # THE ROW-CELL VERBS (wave-24 T15; REQ-9 AC-9.1/9.2, D14). `task-set` sets cells of a
  # `## Tasks` row, `ledger-set` of a `## Dispatch ledger` row, and `ledger-add` appends a ledger
  # row; each through `units_table_cells`, on the shared transaction. A `## Tasks` column is any
  # the header carries by `units_has_column` — `rigor` is slot 3's task-scale name — except two:
  # `id`, the key the row is found by, and `Files`, which is a dispatched agent's CONTRACT once
  # it is on the roster (editing the plan row changes nothing a wall reads), so the refusal
  # names `amend`, the verb that widens it. `task-set` is judged by `units_validate` before the
  # gate, as `task-add` is: a status, step or deps cell is a schedule change.
  task-set|ledger-add|ledger-set)
    # THE ID AND THE COLUMN NAME ARE OPERANDS TOO (wave-24 T27; Step-6 review C1). `ledger-add`
    # writes its id into the new row's first cell, and a line break there forged a plan line
    # the commit gate admitted. The id is one token of the grammar every ledger row already
    # carries (`T7`, `T22b`, `T17-critic`); a name is held to the values' own rule.
    if ! plan_verb_id_ok "$PV_ID"; then
      die "REFUSED — '$(clean "$PV_ID")' is not one row id: an id is one token of letters, digits, '.', '_' or '-', beginning with a letter or a digit. The plan is unchanged."
      exit 1
    fi
    for _pv_a in ${PV_PAIRS[@]+"${PV_PAIRS[@]}"}; do
      _pv_n="${_pv_a%%=*}"
      if ! plan_verb_value_ok "$_pv_n"; then
        die "REFUSED — the column name '$(clean "$_pv_n")' carries a |, a tab or a line break, which no table header can hold; the plan is unchanged."
        exit 1
      fi
      if ! plan_verb_value_ok "${_pv_a#*=}"; then
        die "REFUSED — the value for $_pv_n carries a |, a tab or a line break, which no table cell can hold; the plan is unchanged."
        exit 1
      fi
      [ "$VERB" = task-set ] || continue
      _pv_l="$(printf '%s' "$_pv_n" | tr '[:upper:]' '[:lower:]')"
      case "$_pv_l" in
        files)
          die "REFUSED — task-set does not write Files — widen a dispatched contract with amend: bash ${HOOK_DIR}/session-poker.sh amend <name> --files+ <path> --reason <why>. The plan is unchanged."
          exit 1 ;;
        id)
          die "REFUSED — id is the key task-set finds $PV_ID by, not a cell to set; the plan is unchanged."
          exit 1 ;;
        rigor) _pv_l=kind ;;
      esac
      PV_COLS="${PV_COLS:-} $_pv_l"
    done
    plan_verb_open "$VERB"
    if [ "$VERB" = task-set ]; then
      for _pv_l in ${PV_COLS:-}; do
        if ! units_has_column "$PV_PLAN" "$_pv_l"; then
          die "REFUSED — the ## Tasks header of $PV_PLAN carries no column $_pv_l; the plan is unchanged."
          exit 1
        fi
      done
    fi
    case "$VERB" in
      task-set)   PV_MODE=set; PV_SECT=tasks ;;
      ledger-set) PV_MODE=set; PV_SECT=ledger ;;
      ledger-add) PV_MODE=add; PV_SECT=ledger ;;
    esac
    PV_RC=0
    units_table_cells "$PV_PLAN" "$PV_MODE" "$PV_SECT" "$PV_ID" "${PV_PAIRS[@]}" > "$PV_NEW" 2>/dev/null || PV_RC=$?
    PV_TABLE="## Tasks"; [ "$PV_SECT" = ledger ] && PV_TABLE="## Dispatch ledger"
    case "$PV_RC" in
      0) : ;;
      1) die "REFUSED — $PV_PLAN carries no $PV_TABLE table; the plan is unchanged."; exit 1 ;;
      2) if [ "$PV_MODE" = add ]; then die "REFUSED — the $PV_TABLE table already carries a row $PV_ID; set its cells with ledger-set. The plan is unchanged."
         else die "REFUSED — the $PV_TABLE table carries no row $PV_ID; the plan is unchanged."; fi
         exit 1 ;;
      3) die "REFUSED — the $PV_TABLE header carries no column named in: ${PV_PAIRS[*]%%=*}; the plan is unchanged."; exit 1 ;;
      5) die "REFUSED — the $PV_TABLE table carries more than one row $PV_ID; which one is meant is not the verb's to guess. The plan is unchanged."; exit 1 ;;
      *) die "REFUSED — the value cannot be written as a table cell; the plan is unchanged."; exit 1 ;;
    esac
    if [ "$VERB" = task-set ]; then
      PV_VIOL="$(units_validate "$PV_NEW" 2>&1)"
      if [ -n "$PV_VIOL" ]; then
        die "REFUSED — with that change, the ## Tasks table breaks the Task invariants; the plan is unchanged:"
        printf '%s\n' "$PV_VIOL" >&2
        exit 1
      fi
    fi
    PV_WHAT="$PV_ID ${PV_PAIRS[*]}"
    [ "$PV_MODE" = add ] && PV_WHAT="$PV_ID added to the dispatch ledger"
    plan_verb_swap "$VERB" "$PV_WHAT" writer
    say "$VERB — $PV_WHAT: written to $PV_PLAN; dry-committed first."
    exit 0
    ;;

  # THE LANDING'S ROW (wave-28 T6; REQ-3 AC-3.2, D7; ruling A-orch-81). `line_publish`
  # (lib/line.sh) runs this verb, as a command, inside its publish lock once the fast-forward and
  # its `published` event are written: the row's status `landed` (`units_table_cells` on the tasks
  # table, judged by `units_validate` as `task-set` judges a status), its `- T<n>:` line
  # (`units_step_line`) and its dispatch-ledger row's `landed` cell (`units_table_cells` on the
  # ledger), onto ONE copy and through ONE `plan_verb_swap ... writer`: all three lines or none.
  # Writer mode is the point: past Step 4 the dry copy reads `current: 4`, so the declared debt the
  # publish has just written (T5) cannot refuse the publish's own bookkeeping, and the debt stays
  # in the bound plan's landing record for the gate to read at the next step move (wave-27 passes
  # 60 and 63: the dry copy is `plan_verb_open`'s own, so the gate resolves it to the real plan).
  # The step line gains ` landed <commit> <at>` after its own text (a hand landing: ` landed-by-hand:
  # <who> <at> "<why>"`, the hand landing's interface), once: a text already there is not added
  # again. The ledger cell reads `landed <at> <commit>`; a ledger with no row of that id gains one,
  # and a plan with no `## Dispatch ledger` table has no ledger line to write. A run again of the
  # same landing finds the plan already so and writes nothing.
  row-landed)
    if ! plan_verb_id_ok "$PV_ID"; then
      die "REFUSED — '$(clean "$PV_ID")' is not one row id; the plan is unchanged."
      exit 1
    fi
    if ! plan_verb_value_ok "$RL_BY" || ! plan_verb_value_ok "$RL_WHY"; then
      die "REFUSED — the hand landing's name or reason carries a |, a tab or a line break, which no plan line can hold; the plan is unchanged."
      exit 1
    fi
    plan_verb_open row-landed
    PV_RC=0
    units_table_cells "$PV_PLAN" set tasks "$PV_ID" status=landed > "$PV_NEW" 2>/dev/null || PV_RC=$?
    case "$PV_RC" in
      0) : ;;
      1) die "REFUSED — $PV_PLAN carries no ## Tasks table; the plan is unchanged."; exit 1 ;;
      2) die "REFUSED — the ## Tasks table carries no row $PV_ID; the plan is unchanged."; exit 1 ;;
      5) die "REFUSED — the ## Tasks table carries more than one row $PV_ID; the plan is unchanged."; exit 1 ;;
      *) die "REFUSED — the ## Tasks row $PV_ID cannot take status landed; the plan is unchanged."; exit 1 ;;
    esac
    PV_VIOL="$(units_validate "$PV_NEW" 2>&1)"
    if [ -n "$PV_VIOL" ]; then
      die "REFUSED — with $PV_ID landed, the ## Tasks table breaks the Task invariants; the plan is unchanged:"
      printf '%s\n' "$PV_VIOL" >&2
      exit 1
    fi
    case "$PV_ID" in
      T[0-9]*)
        RL_TEXT="landed $RL_COMMIT $RL_AT"
        [ "$RL_HAND" -eq 0 ] || RL_TEXT="landed-by-hand: $RL_BY $RL_AT \"$RL_WHY\""
        RL_REST="$(units_step_text "$PV_NEW" "$PV_ID" 2>/dev/null)"
        case " $RL_REST " in
          *" $RL_TEXT "*) RL_LINE="$RL_REST" ;;
          *) RL_LINE="${RL_REST:+$RL_REST }$RL_TEXT" ;;
        esac
        if ! units_step_line "$PV_NEW" "$PV_ID" "$RL_LINE" > "$PV_NEW.2" 2>/dev/null; then
          die "REFUSED — $PV_PLAN carries no ## SDLC State section for the $PV_ID line; the plan is unchanged."
          exit 1
        fi
        mv -f "$PV_NEW.2" "$PV_NEW" ;;
    esac
    PV_RC=0
    units_table_cells "$PV_NEW" set ledger "$PV_ID" "landed=landed $RL_AT $RL_COMMIT" > "$PV_NEW.2" 2>/dev/null || PV_RC=$?
    if [ "$PV_RC" -eq 2 ]; then
      PV_RC=0
      units_table_cells "$PV_NEW" add ledger "$PV_ID" "landed=landed $RL_AT $RL_COMMIT" > "$PV_NEW.2" 2>/dev/null || PV_RC=$?
    fi
    case "$PV_RC" in
      0) mv -f "$PV_NEW.2" "$PV_NEW" ;;
      1) rm -f "$PV_NEW.2" ;;
      3) die "REFUSED — the ## Dispatch ledger header carries no landed column; the plan is unchanged."; exit 1 ;;
      5) die "REFUSED — the ## Dispatch ledger table carries more than one row $PV_ID; the plan is unchanged."; exit 1 ;;
      *) die "REFUSED — the ledger row $PV_ID cannot take its landed cell; the plan is unchanged."; exit 1 ;;
    esac
    plan_verb_swap row-landed "$PV_ID landed at $RL_COMMIT" writer
    say "row-landed — $PV_ID landed at $RL_COMMIT: status, step line and ledger line written to $PV_PLAN in one write; dry-committed first."
    exit 0
    ;;

  # THE STEP-LINE VERB (wave-24 T15; REQ-9 AC-9.6, D14). The `- Step N:` and `- T<n>:` lines
  # under `## SDLC State` are the run's evidence, and the gate reads them; `units_step_line`
  # rewrites one line's text (or adds the line, after its kind's last), and never the block
  # under it. Step 9 is close-out's, as `current: 9` is (payload/scripts/close-out.sh).
  step-line)
    case "$PV_KEY" in
      9|9a|9b)
        die "REFUSED — the Step 9 line is close-out's to write, with current: 9 (bash <plugin-root>/scripts/close-out.sh); the plan is unchanged."
        exit 1 ;;
    esac
    case "$PV_TEXT" in
      *$'\n'*|*$'\r'*)
        die "REFUSED — a step line is one line, and the text carries a line break; the plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open step-line
    if ! units_step_line "$PV_PLAN" "$PV_KEY" "$PV_TEXT" "$PV_APPEND" > "$PV_NEW" 2>/dev/null; then
      die "REFUSED — $PV_PLAN carries no ## SDLC State section; the plan is unchanged."
      exit 1
    fi
    PV_LABEL="$PV_KEY"; case "$PV_KEY" in T*) : ;; *) PV_LABEL="Step $PV_KEY" ;; esac
    plan_verb_swap step-line "the $PV_LABEL line written" writer
    say "step-line — $PV_LABEL: written to $PV_PLAN${PV_APPEND:+ (appended)}; dry-committed first."
    exit 0
    ;;

  # THE STEP MOVE (wave-24 T15; REQ-9 AC-9.5, D14; A-orch-8). `current:` moves through
  # `units_set_current`, and the copy is judged AT the step it moves to — the advance is the
  # commit the gate is asked about, so a step whose block is not written yet is refused here,
  # in the gate's words, and not at the first commit after it. `current: 9` is close-out's.
  #
  # ADVANCING TO 4 WRITES WHAT THE FIRST WRITER'S COMMIT IS REFUSED WITHOUT. The Step-4 block's
  # `worktree:`, `base-sha:` and `branch:` (walls.sh `shape_block`) are facts of the moment of
  # the advance: the branch is the plan's own `working-branch:`, its head is the base every
  # writer starts from, and the checkout holding it is the worktree. Each field the block lacks
  # is filled from those (`units_step_fields`); a field already written is never rewritten, and
  # a fact that cannot be read is not guessed — the field stays absent and the gate says so.
  current)
    case "$PV_KEY" in
      9|9a|9b)
        die "REFUSED — current: 9 is close-out's to write, with the Step 9 line (bash <plugin-root>/scripts/close-out.sh); the plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open current
    if ! units_set_current "$PV_PLAN" "$PV_KEY" > "$PV_NEW" 2>/dev/null; then
      die "REFUSED — $PV_PLAN carries no current: line under ## SDLC State; the plan is unchanged."
      exit 1
    fi
    PV_FILLED=""
    if [ "$PV_KEY" = 4 ]; then
      PV_WB="$(awk '
        /^[[:space:]]*```/ { fence = !fence; next }
        fence { next }
        /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
        insdlc && /^[[:space:]]*working-branch[[:space:]]*:/ {
          v = $0; sub(/^[[:space:]]*working-branch[[:space:]]*:[[:space:]]*/, "", v); sub(/[[:space:]].*$/, "", v)
          print v; exit }' "$PV_PLAN")"
      if [ -n "$PV_WB" ]; then
        PV_FIELDS=()
        PV_WT="$(git -C "$PV_REPO" worktree list --porcelain 2>/dev/null \
          | awk -v b="branch refs/heads/$PV_WB" '/^worktree / { p = substr($0, 10) } $0 == b { print p; exit }')"
        if [ -n "$PV_WT" ]; then
          PV_WT="$(cd "$PV_WT" 2>/dev/null && pwd -P)"
          case "$PV_WT" in
            "$PV_REPO") PV_FIELDS+=("worktree=.") ;;
            "$PV_REPO"/*) PV_FIELDS+=("worktree=${PV_WT#"$PV_REPO"/}") ;;
            ?*) PV_FIELDS+=("worktree=$PV_WT") ;;
          esac
        fi
        PV_SHA="$(git -C "$PV_REPO" rev-parse --short --verify -q "refs/heads/$PV_WB" 2>/dev/null)"
        [ -n "$PV_SHA" ] && PV_FIELDS+=("base-sha=$PV_SHA")
        PV_FIELDS+=("branch=$PV_WB")
        if units_step_fields "$PV_NEW" 4 "${PV_FIELDS[@]}" > "$PV_NEW.2" 2>/dev/null; then
          cmp -s "$PV_NEW.2" "$PV_NEW" || PV_FILLED="; the Step-4 block gained what it lacked of: ${PV_FIELDS[*]}"
          mv -f "$PV_NEW.2" "$PV_NEW"
        fi
      fi
    fi
    # STEP 8 IS ADMITTED ON THE JUDGE, NOT ON A DRY COMMIT (wave-27 T14; D3, D14, AC-2.3, AC-2.4,
    # AC-3.1, AC-7.1). The dry commit at Step 8 asked for the Step-8 block, which close-out writes
    # and judges through the gate itself (close-out.sh `gate_preflight`), so a run closed by its
    # tools alone could never take this step. 8 is exempt from it as 9 is from this verb, and is
    # refused instead unless lib/proof.sh `facts_state` says every fact the run owes holds at the
    # working head: the floor, and each reading its rigor and scale deal. Each line that does not
    # hold is printed as the judge gave it.
    # The mode has a name of its own: PV_DRY is the dry copy's PATH (wave-27 T76; A-orch-171).
    PV_DRYMODE=as-is; PV_HOW="dry-committed at that step first"
    case "$PV_KEY" in
      8|8a|8b)
        cur8_checks
        cur8_judge
        PV_DRYMODE=judged; PV_HOW="every fact the run owes holds at $PV_HEAD8 (facts_state)" ;;
    esac
    plan_verb_swap current "current: $PV_KEY" "$PV_DRYMODE"
    say "current — current: $PV_KEY in $PV_PLAN (was ${PV_CUR:-none})$PV_FILLED; $PV_HOW."
    exit 0
    ;;

  # THE APPROVAL (wave-26 T13; D3, AC-6.2). A row that reads `approval:<name>` is not ready, and
  # the dispatch wall refuses it, until `## SDLC State` carries
  #
  #   approved: <name> by <who> <ISO-UTC> "<reply>"
  #
  # written here on the user's reply and nowhere else: `<who>` is the project's git user name,
  # the instant is `date -u`, the reply is the user's own words. It goes through the plan
  # transaction every row verb takes (copy, dry commit through the real gate, checksum, swap),
  # beside the approval lines already there — after the last `approved:` or `approved-by:` line,
  # else after `current:`. An approval is recorded once: a second `approve` of a name the plan
  # already carries is refused, so the first reply stands. `plan` is refused by name: the plan's
  # approval is the `approved-by:` line Step 3 writes, which `approval:plan` reads.
  approve)
    if [ "$AP_NAME" = plan ]; then
      die "REFUSED — approval:plan is the plan's approved-by: line, written at Step 3 when the user approves the plan card; approve records any other approval a row reads (approval:<name>). The plan is unchanged."
      exit 1
    fi
    case "$AP_REPLY" in
      *$'\n'*|*$'\r'*)
        die "REFUSED — an approval line is one line, and the reply carries a line break; the plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open approve
    # A NAME NO ROW READS IS REFUSED (wave-26 T46; review 10 F6). `approve relase` used to be
    # recorded "once" while the release kept waiting in silence; the names the rows read, as
    # `approval:<name>` or `live:approval:<name>` (units.sh `units_approval_names`), are the only
    # names an approval can satisfy. Exact match, case included, as readiness keys it.
    AP_READ="$(units_approval_names "$PV_PLAN" | /usr/bin/grep -v '^plan$' | tr '\n' ' ' | sed 's/ $//')"
    case " $AP_READ " in
      *" $AP_NAME "*) : ;;
      *)
        die "REFUSED — no row in $PV_PLAN reads approval:$AP_NAME, so recording it would satisfy nothing; the rows read: ${AP_READ:-(no named approval)}. Approve one of those names exactly; the plan is unchanged."
        exit 1 ;;
    esac
    AP_HAVE="$(awk -v want="$AP_NAME" '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc {
        l = $0; sub(/^[ \t]*-?[ \t]*/, "", l)
        if (l !~ /^approved[ \t]*:/) next
        sub(/^approved[ \t]*:[ \t]*/, "", l); split(l, w, /[ \t]+/)
        if (w[1] == want) { print $0; exit }
      }' "$PV_PLAN")"
    if [ -n "$AP_HAVE" ]; then
      die "REFUSED — $PV_PLAN already records this approval: $(clean "$AP_HAVE"). An approval is recorded once; the plan is unchanged."
      exit 1
    fi
    AP_WHO="$(git -C "$PV_REPO" config user.name 2>/dev/null)"
    if [ -z "$AP_WHO" ] || ! plan_verb_value_ok "$AP_WHO"; then
      die "REFUSED — the project has no usable git user name (git config user.name) to record as the approver; the plan is unchanged."
      exit 1
    fi
    AP_LINE="approved: $AP_NAME by $AP_WHO $(date -u +%Y-%m-%dT%H:%M:%SZ) \"$AP_REPLY\""
    # THE LINE GOES IN THROUGH THE ENVIRONMENT, not `-v`, which would read a backslash in the
    # user's reply as an escape and write a different reply than the one given.
    if ! AP_LINE="$AP_LINE" awk '
      { L[++n] = $0 }
      END {
        for (i = 1; i <= n; i++) {
          if (L[i] ~ /^[[:space:]]*```/) { fence = !fence; continue }
          if (fence) continue
          if (L[i] ~ /^##[[:space:]]/) { if (insdlc) break; insdlc = (L[i] ~ /^##[[:space:]]+SDLC State/); continue }
          if (!insdlc) continue
          if (L[i] ~ /^[[:space:]]*approved(-by)?[[:space:]]*:/) at = i
          else if (!at && !cur && L[i] ~ /^[[:space:]]*current[[:space:]]*:/) cur = i
        }
        if (!at) at = cur
        if (!at) exit 1
        for (i = 1; i <= n; i++) { print L[i]; if (i == at) print ENVIRON["AP_LINE"] }
      }' "$PV_PLAN" > "$PV_NEW" 2>/dev/null; then
      die "REFUSED — $PV_PLAN carries no current: line under ## SDLC State to write the approval beside; the plan is unchanged."
      exit 1
    fi
    plan_verb_swap approve "approved: $AP_NAME" writer
    say "approve — $AP_NAME: approved: $AP_NAME by $AP_WHO written to $PV_PLAN; dry-committed first."
    exit 0
    ;;

  # THE PROOF VERB (wave-26 T4; REQ-3 AC-3.2, D5). Nothing recorded which code state a test pass
  # or a review read, so the same code was proved again and again. A proof is one line under
  # `## SDLC State` — `proved: kind=<kind> head=<40-hex> at=<ISO-UTC> evidence=<record/ path>`
  # (payload/scripts/lib/proof.sh owns its shape and its reader, `proof_last`) — and what is
  # unproved is the difference since the head it names. The head is the one the evidence attests
  # (its run header or its reviewed: range, held against the working-branch checkout; T14),
  # never an operand. The line goes in through the shared transaction; every refusal below
  # leaves the plan byte-identical and names its fix. proof.sh is loaded here, for this verb alone, as brief.sh is for task-add and amend:
  # the tick never reads it, so it is not one of the libraries every verb needs.
  proof-add)
    if ! { declare -F proof_last >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_add_line >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    if ! proof_kind_ok "$PF_KIND"; then
      die "REFUSED — '$(clean "$PF_KIND")' is not a proof kind: name floor, review or task. The plan is unchanged."
      exit 1
    fi
    # A CHECK FACT IS WRITTEN BY THE VERB THAT RAN THE CHECK (wave-27 T16; D12): a log handed in
    # here was written by nobody's run.
    if [ "$PF_KIND" = check ]; then
      die "REFUSED — a check proof is written by release-check, which runs the project's declared command and keeps its log; run release-check. The plan is unchanged."
      exit 1
    fi
    if [ -n "$PF_QUESTION" ] && ! proof_question_ok "$PF_QUESTION"; then
      die "REFUSED — '$(clean "$PF_QUESTION")' is not a reading question: name evidence, adversarial or structure. The plan is unchanged."
      exit 1
    fi
    # THE READER'S NAME IS MATCHED AS TYPED (wave-27 T41; review pass 10 F3): letters, digits, `_`
    # and `-`, spelled out (PV_ID_ALNUM: a range is a collation range under a UTF-8 locale), so no
    # escape a reader of it might decode, and no character the space-separated line cannot hold.
    case "$PF_READER" in
      *[!"$PV_ID_ALNUM"_-]*)
        die "REFUSED — the reader name '$(clean "$PF_READER")' carries a character outside A-Z, a-z, 0-9, _ and -, and a reader name is matched byte for byte against its roster row; name the reader as its roster row does. The plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open proof-add
    PF_DOCS="$(docs_root "$PV_REPO")"
    PF_DOCS="$(cd "$PF_DOCS" 2>/dev/null && pwd -P)"
    case "$PF_EVID" in
      *[[:space:]]*|*'|'*)
        die "REFUSED — the evidence path '$(clean "$PF_EVID")' carries a space, a tab, a line break or a |, which the space-separated proof line cannot hold; rename the file. The plan is unchanged."
        exit 1 ;;
    esac
    case "$PF_EVID" in
      /*) PF_ABS="$PF_EVID" ;;
      *)  PF_ABS="$PF_DOCS/$PF_EVID" ;;
    esac
    # A SYMLINK IS NOT A RECORD (wave-26 T46; review 10 F7). The check below resolves the
    # directory, not the file, so a link under record/ to a log elsewhere would be admitted and the
    # evidence it cites could change after the proof. Refused by name, before it is read.
    if [ -L "$PF_ABS" ]; then
      die "REFUSED — the evidence $(clean "$PF_EVID") is a symbolic link (to $(clean "$(readlink "$PF_ABS")")), and what it points at can change after the proof; copy the log into the record (cp it to that path) and run proof-add again. The plan is unchanged."
      exit 1
    fi
    PF_REAL=""
    [ -n "$PF_DOCS" ] && [ -f "$PF_ABS" ] \
      && PF_REAL="$(cd "$(dirname "$PF_ABS")" 2>/dev/null && pwd -P)/$(basename "$PF_ABS")"
    if [ -z "$PF_REAL" ]; then
      die "REFUSED — the evidence file $(clean "$PF_EVID") does not exist (read as $(clean "$PF_ABS")); write the record first, then add its proof. The plan is unchanged."
      exit 1
    fi
    case "$PF_REAL" in
      "$PF_DOCS"/record/*) PF_REL="${PF_REAL#"$PF_DOCS"/}" ;;
      *)
        die "REFUSED — the evidence $(clean "$PF_EVID") is not under record/ of the docs root ($PF_DOCS/record/); a proof cites a record. The plan is unchanged."
        exit 1 ;;
    esac
    # A READING CARRIES ITS QUESTION, ITS RESULT AND ITS SCOPE (wave-27 T2; D1, AC-2.1). The record's
    # own flush-left lines say them, and for `structure` it answers every check id the shipped
    # checks file names, the file resolved through this hook's own lib root, as execution-recorder
    # resolves survival.md (lib/proof.sh `proof_reading`). A reading record holds exactly one pass and
    # a second is refused (T45), each value whole, and a structure result is one its checks bear out
    # (T41; review pass 10 F1, F2, F6); the start of its range comes back too, for the whole-read check below.
    PF_RESULT=""; PF_SCOPE=""; PF_FROM=""; PF_ROLE=""; PF_SEV=""
    if [ -n "$PF_QUESTION" ]; then
      # THE READER WAS PUSHED THE SEVERITY SCALE (wave-28 T15; D19, AC-8.1, AC-8.8): the `pushed=` of
      # the last row naming this reader, dealt this question and past `intended`, on any roster of the
      # project, read by key as `questions=` is. When it names `severity` (lib/proof.sh
      # `proof_pushed_severity`) the record must carry its findings and its result is the one they
      # derive; otherwise it is read as 1.12.0 read it. The row checks themselves follow below.
      PF_PUSHED=""
      for _pf_rf in "$PV_REPO/.bionic/tmp"/roster-*.state; do
        [ -f "$_pf_rf" ] && [ ! -L "$_pf_rf" ] || continue
        _pf_p="$(PF_WANT="$PF_READER" PF_Q="$PF_QUESTION" awk "$_ROSTER_OPEN_AWK"'
          index($0, "roster-state/") == 1 && (_roster_kv($0, "name") "") == (ENVIRON["PF_WANT"] "") {
            s = _roster_kv($0, "status"); if (s == "" || s == "intended") next
            m = split(_roster_kv($0, "questions"), qs, ","); d = 0
            for (i = 1; i <= m; i++) if (qs[i] == ENVIRON["PF_Q"]) d = 1
            if (d) { p = _roster_kv($0, "pushed"); f = 1 } }
          END { if (f) print "=" p }' "$_pf_rf" 2>/dev/null)"
        [ -z "$_pf_p" ] || PF_PUSHED="${_pf_p#=}"
      done
      proof_pushed_severity "$PF_PUSHED" && PF_SEV=1
      if ! PF_RS="$(proof_reading "$PF_REAL" "$PF_QUESTION" "$BIONIC_LIB/../../context/checks-structure.md" "$PF_SEV")"; then
        die "REFUSED — $(clean "$PF_RS"). The plan is unchanged."
        exit 1
      fi
      PF_RESULT="${PF_RS%% *}"; PF_FROM="${PF_RS#* }"; PF_SCOPE="${PF_FROM%% *}"; PF_FROM="${PF_FROM#* }"
      # THE READER IS A ROW THE DISPATCH RECORDED (wave-27 T2; D7, AC-1.4). Every roster of this
      # project is read, every session's, for a reader whose session has ended still has its row
      # there until close-out; each row naming the reader must be a reader role, and one of them
      # must have been dealt the question (`questions=`). A name no row carries is refused, so the
      # orchestrator cannot register a reading in a reader's name, and a name any writer row
      # carries is refused, so a writer cannot read its own code under it. The name is compared
      # byte for byte, handed to awk through its environment, never `-v`, which decodes escapes
      # (T41; review pass 10 F3).
      # THE RECORD IS THE READER'S OWN (T41; review pass 10 F4). A row dealt the question that got
      # past `intended` (its agent started) must name this record as its `deliverable=` or among its
      # `files=`, each entry read from the project root unless absolute and compared by its real
      # path, so no record is registered under the name of a reader that never wrote it. The roster
      # files themselves take any write; that residual is the walls' known one (walls.sh, "habit,
      # not an adversary").
      PF_ROWS=""
      for _pf_rf in "$PV_REPO/.bionic/tmp"/roster-*.state; do
        [ -f "$_pf_rf" ] && [ ! -L "$_pf_rf" ] || continue
        PF_ROWS="$PF_ROWS$(PF_WANT="$PF_READER" awk "$_ROSTER_OPEN_AWK"'
          index($0, "roster-state/") == 1 && (_roster_kv($0, "name") "") == (ENVIRON["PF_WANT"] "") {
            t = _roster_kv($0, "subagent_type"); if (t == "") t = "(none)"
            print t "\t" _roster_kv($0, "questions") "\t" _roster_kv($0, "status") "\t" _roster_kv($0, "deliverable") "\t" _roster_kv($0, "files") "\t" _roster_kv($0, "name") }' "$_pf_rf" 2>/dev/null)
"
      done
      PF_LOOK="$(printf '%s' "$PF_ROWS" | PROOF_ROLES="$PROOF_READER_ROLES" PF_Q="$PF_QUESTION" awk -F'\t' '
        BEGIN { n = split(ENVIRON["PROOF_ROLES"], r, " "); for (i = 1; i <= n; i++) ok[r[i]] = 1; q = ENVIRON["PF_Q"] }
        NF { rows++
             if (!($1 in ok)) { if (bad == "") bad = $1; next }
             d = 0; m = split($2, qs, ","); for (i = 1; i <= m; i++) if (qs[i] == q) d = 1
             if (!d) next
             dealt = 1; role = $1; name = $6
             if ($3 == "" || $3 == "intended") next
             past = 1
             if ($4 != "" && !($4 in seen)) { seen[$4] = 1; own[++c] = $4 }
             m = split($5, fs, ","); for (i = 1; i <= m; i++) if (fs[i] != "" && !(fs[i] in seen)) { seen[fs[i]] = 1; own[++c] = fs[i] } }
        END {
          if (!rows) { print "none"; exit }
          if (bad != "") { print "writer\t" bad; exit }
          if (!dealt) { print "undealt"; exit }
          if (!past) { print "intended"; exit }
          print "ok\t" role "\t" name
          for (i = 1; i <= c; i++) print own[i] }')"
      PF_ROLE="${PF_LOOK%%
*}"
      case "$PF_ROLE" in
        none)
          die "REFUSED — no roster row on this machine names the reader $(clean "$PF_READER"), so nothing records it as a reader; register a reading under the name its dispatch recorded. The plan is unchanged."
          exit 1 ;;
        writer*)
          die "REFUSED — the reader $(clean "$PF_READER") has a roster row of role $(clean "${PF_ROLE#*	}"), which is not a reader role ($PROOF_READER_ROLES); a reading is registered for a reader, never a writer. The plan is unchanged."
          exit 1 ;;
        undealt)
          die "REFUSED — the reader $(clean "$PF_READER") was not dealt the $PF_QUESTION question (the questions= of its roster row does not name it); register the reading for the reader dealt it. The plan is unchanged."
          exit 1 ;;
        intended)
          die "REFUSED — the reader $(clean "$PF_READER") dealt the $PF_QUESTION question has no roster row past status=intended: its launch was recorded and never started, so it read nothing; register the reading once its agent has run. The plan is unchanged."
          exit 1 ;;
      esac
      PF_OWN=""
      while IFS= read -r _pf_c; do
        case "$_pf_c" in '') continue ;; /*) _pf_p="$_pf_c" ;; *) _pf_p="$PV_REPO/${_pf_c#./}" ;; esac
        [ -f "$_pf_p" ] || continue
        if [ "$(cd "$(dirname "$_pf_p")" 2>/dev/null && pwd -P)/$(basename "$_pf_p")" = "$PF_REAL" ]; then PF_OWN=1; break; fi
      done <<PF_OWN_LIST
$(printf '%s\n' "$PF_LOOK" | sed 1d)
PF_OWN_LIST
      if [ -z "$PF_OWN" ]; then
        die "REFUSED — the record $(clean "$PF_REL") was not written by the reader $(clean "$PF_READER"): no roster row of that reader names it as its deliverable= or among its files=, and a reading is the record its reader was dispatched to write; register it under the reader whose row names it. The plan is unchanged."
        exit 1
      fi
      # A RECORD IS ONE READER'S (wave-27 T45; review pass 16 finding 2). A pass carries no reader of
      # its own, so a record that another roster row also names as its deliverable= or among its
      # files= could be registered under either name; it is refused, naming that row, whichever
      # reader is typed. Each entry is compared by real path, as above.
      # ONLY A ROW THAT CAN STILL WRITE IT COUNTS (wave-27 T14; review pass 20 F3): a row of a
      # DIFFERENT name, past `intended` (confirmed or identified) and still open by the one reader
      # of "is this name closed" (`roster_open_names`, its roster's ack ledger beside it). An
      # `intended` launch read nothing, a closed or acked one reads no more, and a row of the
      # reader's own name is its own relaunch, so a reader dispatched again to the record of an
      # earlier launch can register what it read.
      PF_OTHER=""
      for _pf_rf in "$PV_REPO/.bionic/tmp"/roster-*.state; do
        [ -f "$_pf_rf" ] && [ ! -L "$_pf_rf" ] && [ -z "$PF_OTHER" ] || continue
        _pf_rs="${_pf_rf##*/roster-}"; _pf_rs="${_pf_rs%.state}"
        _pf_open=" $(roster_open_names "$_pf_rf" "${_pf_rf%/*}/sweeper-${_pf_rs}.state" 2>/dev/null | tr '\n' ' ')"
        while IFS=$'\037' read -r _pf_on _pf_ot _pf_c; do
          case "$_pf_c" in '') continue ;; /*) _pf_p="$_pf_c" ;; *) _pf_p="$PV_REPO/${_pf_c#./}" ;; esac
          [ -f "$_pf_p" ] || continue
          if [ "$(cd "$(dirname "$_pf_p")" 2>/dev/null && pwd -P)/$(basename "$_pf_p")" = "$PF_REAL" ]; then
            PF_OTHER="$_pf_on (${_pf_ot:-no subagent_type})"; break
          fi
        done <<PF_OTHER_LIST
$(PF_WANT="$PF_READER" PF_OPEN="$_pf_open" awk "$_ROSTER_OPEN_AWK"'
  index($0, "roster-state/") == 1 && (_roster_kv($0, "name") "") != (ENVIRON["PF_WANT"] "") &&
    (_roster_kv($0, "status") == "confirmed" || _roster_kv($0, "status") == "identified") &&
    index(ENVIRON["PF_OPEN"], " " _roster_kv($0, "name") " ") {
    o = _roster_kv($0, "name") "\037" _roster_kv($0, "subagent_type") "\037"
    m = split(_roster_kv($0, "deliverable") "," _roster_kv($0, "files"), e, ",")
    for (i = 1; i <= m; i++) if (e[i] != "") print o e[i] }' "$_pf_rf" 2>/dev/null)
PF_OTHER_LIST
      done
      if [ -n "$PF_OTHER" ]; then
        die "REFUSED — the record $(clean "$PF_REL") is also named by the roster row $(clean "$PF_OTHER") as its deliverable= or among its files=; a reading record is one reader's, so each reader writes a record of its own. The plan is unchanged."
        exit 1
      fi
      PF_ROLE="${PF_ROLE#*	}"; PF_READER="${PF_ROLE#*	}"; PF_ROLE="${PF_ROLE%%	*}"
    fi
    PF_WB="$(proof_working_branch "$PV_PLAN")"
    if [ -z "$PF_WB" ]; then
      die "REFUSED — $PV_PLAN names no working-branch:, so there is no checkout to read the head from; add 'working-branch: <branch>' under ## SDLC State. The plan is unchanged."
      exit 1
    fi
    PF_HEAD="$(proof_head "$PV_REPO" "$PF_WB")" || PF_HEAD=""
    case "$PF_HEAD" in
      [0-9a-f]*) : ;;
      *)
        die "REFUSED — no checkout of $PV_REPO has working-branch $(clean "$PF_WB") checked out, so its head cannot be read; check the branch out (its worktree) and run proof-add again. The plan is unchanged."
        exit 1 ;;
    esac
    # THE HEAD IS THE ONE THE EVIDENCE READ (wave-26 T14; review 7 F1). The checkout's head only
    # bounds it: a run's log must have read exactly that head on a clean tree, a review a commit
    # on its history, and the proof names what the evidence attests (lib/proof.sh
    # `proof_attested`). A task landed between the run and this verb is not proved by it.
    # The plan goes too: a review's range must start at or before its last review proof (T62).
    # A reading's range starts at or before the last proof of its own question (wave-27 T2; D1).
    PF_CO="$(proof_checkout "$PV_REPO" "$PF_WB")"
    if ! PF_HEAD="$(proof_attested "$PF_KIND" "$PF_REAL" "$PF_CO" "$PV_PLAN" "$PF_QUESTION")"; then
      die "REFUSED — $(clean "$PF_HEAD"). The plan is unchanged."
      exit 1
    fi
    # A WHOLE READ STARTS AT THE RUN'S BASE (wave-27 T41; review pass 10 F5). The line carries the
    # head and not the start, so `scope: whole` over a tail would read to the judge as a read of
    # everything; it is accepted only when the range starts at the plan's base-sha: or an ancestor
    # of it (proof_attested has already resolved the start, so here it is a commit).
    if [ "$PF_SCOPE" = whole ]; then
      PF_BASE="$(proof_plan_base "$PV_PLAN" "$PF_CO")"; PF_BASEH=""
      proof_base_id "$PF_BASE" && PF_BASEH="$(git -C "$PF_CO" rev-parse --verify -q "$PF_BASE^{commit}" 2>/dev/null)"
      if [ -z "$PF_BASEH" ]; then
        # THE SAME PLACE THE FIRST-READING REFUSAL NAMES (wave-27 T14; review pass 20 F4), and a word
        # such as HEAD is said to be no commit id (F1).
        PF_BASEWHY="it names no base-sha:"
        if [ -n "$PF_BASE" ] && ! proof_base_id "$PF_BASE"; then PF_BASEWHY="its base-sha: $(clean "$PF_BASE") is not a commit id"
        elif [ -n "$PF_BASE" ]; then PF_BASEWHY="its base-sha: $(clean "$PF_BASE") is no commit here"; fi
        die "REFUSED — the reading $(clean "$PF_REL") says scope: whole, but $PF_BASEWHY, so nothing shows it read from the start of the run; add base-sha: <the commit the work started from> to the frontmatter of $PV_PLAN, or write scope: piece. The plan is unchanged."
        exit 1
      fi
      PF_FROMH="$(git -C "$PF_CO" rev-parse --verify -q "$PF_FROM^{commit}" 2>/dev/null)"
      if [ -z "$PF_FROMH" ] || ! git -C "$PF_CO" merge-base --is-ancestor "$PF_FROMH" "$PF_BASEH" 2>/dev/null; then
        die "REFUSED — the reading $(clean "$PF_REL") says scope: whole, but its range starts at $(clean "$(printf '%s' "${PF_FROMH:-$PF_FROM}" | cut -c1-12)"), past the plan's base ${PF_BASEH:0:12}; a whole reading reads from the base, so write reviewed: ${PF_BASEH:0:12}..<b>, or scope: piece. The plan is unchanged."
        exit 1
      fi
    fi
    # A WHOLE READ WAITS FOR THE LAST BUILD PIECE (wave-27 T45; review pass 13 F2; D10). The judge
    # covers a whole line with any whole reading whatever its head, so its time is held here, on the
    # plan text the verb already holds: refused while a `## Tasks` row of kind build is pending or
    # active, naming them. A plan with no `## Tasks` table is not held to it.
    if [ "$PF_SCOPE" = whole ]; then
      PF_OPEN="$(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' '
        $3 == "build" && ($10 == "pending" || $10 == "active") { printf "%s%s (%s)", (n++ ? ", " : ""), $1, $10 }')"
      if [ -n "$PF_OPEN" ]; then
        die "REFUSED — the reading $(clean "$PF_REL") says scope: whole, but build rows are still open: $(clean "$PF_OPEN"); a whole read is taken once the last build piece has landed (D10), so register it after they land, or scope: piece. The plan is unchanged."
        exit 1
      fi
    fi
    PF_LINE="$(proof_line "$PF_KIND" "$PF_HEAD" "$(iso_now)" "$PF_REL" "$PF_QUESTION" "$PF_READER" "$PF_RESULT" "$PF_SCOPE")"
    # A RATED READING WRITES ITS PLAN LINES (wave-28 T15; D19, D21, D33): one `deferred:` line per
    # finding the table defers and one `check:` line per unsure finding, right after its proof line,
    # in the same write (lib/proof.sh `proof_finding_lines`).
    PF_PLANL=""
    [ "$PF_SEV" = 1 ] && PF_PLANL="$(proof_finding_lines "$PF_REL" "$(proof_findings "$PF_REAL")")"
    [ -z "$PF_PLANL" ] || PF_LINE="$PF_LINE
$PF_PLANL"
    if ! proof_add_line "$PV_PLAN" "$PF_LINE" > "$PV_NEW" 2>/dev/null || [ ! -s "$PV_NEW" ]; then
      die "REFUSED — $PV_PLAN carries no ## SDLC State section to hold the proof; the plan is unchanged."
      exit 1
    fi
    # A REVIEW THAT FOLLOWS THE BUILD GOES BACK TO WAITING (wave-26 T14; D10). The active review
    # row reading `live:head` (`units_live_rows`, the kind default included) whose `Files` hold
    # this evidence returns to `pending` in the same write — that row alone: the proof of another
    # review, the settled final one among them, leaves a live pass still running where it is
    # (wave-26 T46; review 10 F3). A READING RETURNS THE ROW CARRYING ITS QUESTION (wave-27 T10;
    # D4): handed --question, `units_live_rows` finds a read row by the question it read, not by
    # its Files, so a second pass written under a new name still returns its row, and that row
    # alone; a bare row is still found by its Files. The evidence is handed in both spellings, from the docs root
    # (`record/…`) and from the repository, so a Files cell in either matches. It returns with
    # its agent, worktree and base cells cleared: the row is one row across every pass, each pass
    # its own launch — the launch recorder sets it active again and adds that pass's ledger line,
    # so the ledger is not touched here (A-T14.4). The next landing past this proof makes it
    # ready again (units.sh `live_head`).
    # A READ ROW RETURNS ONLY TO ITS OWN READER, AND ONLY WHOLE (wave-27 T43; review pass 17 F3):
    # handed --reader, `units_live_rows` names a read row only when its agent cell is this reader
    # and every question it carries now has a reading at this head; until then it stays active and
    # is not offered, and PF_HELD names it. A row abandoned part-way is returned by task-set.
    PF_BACK=""; PF_HELD=""
    if [ "$PF_KIND" = review ]; then
      PF_DOCREL="$(docs_root "$PV_REPO")"
      case "$PF_DOCREL" in "$PV_REPO"/*) PF_DOCREL="${PF_DOCREL#"$PV_REPO"/}/$PF_REL" ;; *) PF_DOCREL="" ;; esac
      [ -z "$PF_QUESTION" ] || PF_HELD="$(units_live_rows "$PV_NEW" --question "$PF_QUESTION" 2>/dev/null \
        | awk -F'\t' '$2 == "review" && $3 == "active" { printf "%s%s", (n++ ? " " : ""), $1 }')"
      for _pf_id in $(units_live_rows "$PV_NEW" ${PF_QUESTION:+--question "$PF_QUESTION" --reader "$PF_READER"} "$PF_REL" $PF_DOCREL 2>/dev/null | awk -F'\t' '$2 == "review" && $3 == "active" { print $1 }'); do
        _pf_cells=(status=pending agent=—)
        units_has_column "$PV_NEW" worktree && _pf_cells+=(worktree=—)
        units_has_column "$PV_NEW" base && _pf_cells+=(base=—)
        if ! units_table_cells "$PV_NEW" set tasks "$_pf_id" "${_pf_cells[@]}" > "$PV_NEW.back" 2>/dev/null || [ ! -s "$PV_NEW.back" ]; then
          rm -f "$PV_NEW.back"
          die "REFUSED — review row $_pf_id could not be returned to pending in $PV_PLAN; the plan is unchanged."
          exit 1
        fi
        mv "$PV_NEW.back" "$PV_NEW"
        PF_BACK="${PF_BACK:+$PF_BACK }$_pf_id"
        PF_HELD=" $PF_HELD "; PF_HELD="${PF_HELD/ $_pf_id / }"; PF_HELD="${PF_HELD# }"; PF_HELD="${PF_HELD% }"
      done
      [ -z "$PF_HELD" ] || PF_HELD="$(units_rows "$PV_NEW" 2>/dev/null | awk -F'\t' -v ids=" $PF_HELD " -v r="$PF_READER" \
        'index(ids, " " $1 " ") && $5 == r { printf "%s%s", (n++ ? " " : ""), $1 }')"
    fi
    # A REVIEW PROOF THAT RETURNS NO LIVE ROW WHILE ONE IS ACTIVE SAYS SO (wave-26 T51; review 14
    # S4). The record of a live pass written under another name than its row's Files returns
    # nothing, rightly, and the pass is then never offered again; through T46 the success line
    # said nothing of it. The active live review rows are named with their Files, so the mismatch
    # is seen at once. None is reset: a proof moves only the row whose Files hold it (T46, review
    # 10 F3), and the final review's proof is one such. With no live review active it says nothing.
    PF_NONE=""
    if [ "$PF_KIND" = review ] && [ -z "$PF_BACK" ] && [ -z "$PF_HELD" ]; then
      _pf_live=" $(units_live_rows "$PV_NEW" 2>/dev/null | awk -F'\t' '$2 == "review" && $3 == "active" { printf "%s ", $1 }')"
      [ "$_pf_live" = " " ] || PF_NONE="$(units_rows "$PV_NEW" 2>/dev/null | awk -F'\t' -v ids="$_pf_live" '
        index(ids, " " $1 " ") { printf "%s%s (%s)", (n++ ? ", " : ""), $1, $9 }')"
    fi
    plan_verb_swap proof-add "the $PF_KIND proof at $PF_HEAD" writer
    PF_FIELDS=""; [ -z "$PF_QUESTION" ] || PF_FIELDS=" question=$PF_QUESTION reader=$PF_READER result=$PF_RESULT scope=$PF_SCOPE ($PF_ROLE)"
    say "proof-add — kind=$PF_KIND head=$PF_HEAD evidence=$PF_REL$PF_FIELDS: written to $PV_PLAN${PF_BACK:+; $PF_BACK back to pending}; dry-committed first."
    [ -z "$PF_PLANL" ] || printf '%s\n' "$PF_PLANL" | while IFS= read -r _pf_l; do say "proof-add — $_pf_l"; done
    [ -n "$PF_HELD" ] && say "proof-add — $PF_HELD stays active until every question it carries is read at ${PF_HEAD:0:12}; it returns to pending on that reading."
    [ -n "$PF_NONE" ] && say "proof-add — no active live review row holds $PF_REL in its Files: $PF_NONE stays active, nothing was returned to pending. If this record is that pass, its Files name another record: write the record under that name, or amend the row's Files."
    exit 0
    ;;

  # THE WAIVER (wave-27 T9; D2). The user's act, on their reply: one line under `## SDLC State`,
  #
  #   waived: question=<q> head=<working head> by <git user.name> <ISO-UTC> "<reply>"
  #
  # covering that question up to the head of the plan's working-branch checkout, the head the judge
  # (lib/proof.sh `facts_state`) is asked about. It goes in through the plan transaction, placed
  # with the proof lines by `proof_add_line`, so a fact written after it is newer than it.
  waive)
    if ! { declare -F proof_waiver_line >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_waiver_line >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    if ! proof_question_ok "$WV_Q"; then
      die "REFUSED — '$(clean "$WV_Q")' is not a reading question: name evidence, adversarial or structure. The plan is unchanged."
      exit 1
    fi
    case "$WV_REPLY" in
      *$'\n'*|*$'\r'*)
        die "REFUSED — a waiver line is one line, and the reply carries a line break; the plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open waive
    WV_WHO="$(git -C "$PV_REPO" config user.name 2>/dev/null)"
    if [ -z "$WV_WHO" ] || ! plan_verb_value_ok "$WV_WHO"; then
      die "REFUSED — the project has no usable git user name (git config user.name) to record as the one who waived; the plan is unchanged."
      exit 1
    fi
    WV_WB="$(proof_working_branch "$PV_PLAN")"
    WV_HEAD=""; [ -z "$WV_WB" ] || WV_HEAD="$(proof_head "$PV_REPO" "$WV_WB")" || WV_HEAD=""
    case "$WV_HEAD" in
      [0-9a-f]*) : ;;
      *)
        die "REFUSED — no checkout of $PV_REPO has the plan's working-branch ${WV_WB:-(none named)} checked out, so there is no head to waive at; the plan is unchanged."
        exit 1 ;;
    esac
    WV_LINE="$(proof_waiver_line "$WV_Q" "$WV_HEAD" "$WV_WHO" "$(iso_now)" "$WV_REPLY")"
    if ! proof_add_line "$PV_PLAN" "$WV_LINE" > "$PV_NEW" 2>/dev/null || [ ! -s "$PV_NEW" ]; then
      die "REFUSED — $PV_PLAN carries no ## SDLC State section to hold the waiver; the plan is unchanged."
      exit 1
    fi
    plan_verb_swap waive "the $WV_Q waiver at $WV_HEAD" writer
    say "waive — question=$WV_Q head=$WV_HEAD by $WV_WHO: written to $PV_PLAN; dry-committed first."
    exit 0
    ;;

  # THE DEFERRAL'S SENTENCE (wave-28 T17; D21, AC-8.7). Stores the one changelog sentence of a deferred
  # finding on its `deferred:` line, through the plan transaction, as ` stated="<sentence>"` (the
  # helpers above hold the form). Stating twice replaces; the line is never given a second field.
  # A finding with no `deferred:` line (a note, a fix, a check owed) is not stated: the verb refuses
  # it. A sentence of `-` is refused, for `-` is what the continuation writes for no sentence.
  finding-stated)
    FS_SENT="$(deferral_fold "$FS_RAW")"
    if [ -z "$FS_SENT" ]; then
      die "REFUSED — the sentence is empty once its white space is folded; the plan is unchanged."
      exit 1
    fi
    if [ "$FS_SENT" = "-" ]; then
      die "REFUSED — '-' is what the continuation writes for a deferral with no sentence, so it cannot be one; the plan is unchanged."
      exit 1
    fi
    plan_verb_open finding-stated
    if ! deferral_line "$PV_PLAN" "$FS_ID" >/dev/null; then
      die "REFUSED — $PV_PLAN carries no deferred: line for $(clean "$FS_ID") under ## SDLC State, and only a deferral is stated; the plan is unchanged."
      exit 1
    fi
    FS_TAIL=" stated=\"$(deferral_escape "$FS_SENT")\""
    FS_TAIL="$FS_TAIL" awk -v id="$FS_ID" '
      /^[[:space:]]*```/ { fence = !fence; print; next }
      fence { print; next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); print; next }
      insdlc && !done && /^deferred:[ \t]/ {
        split($0, f, /[ \t]+/)
        if (f[2] == id) {
          done = 1; l = $0; i = index(l, " stated=\"")
          if (i) l = substr(l, 1, i - 1)
          sub(/[ \t]+$/, "", l); print l ENVIRON["FS_TAIL"]; next
        }
      }
      { print }' "$PV_PLAN" > "$PV_NEW"
    plan_verb_swap finding-stated "the sentence of $FS_ID" writer
    say "finding-stated — $(clean "$FS_ID"): its sentence is on the deferred: line of $PV_PLAN; dry-committed first."
    exit 0
    ;;

  # THE CHECK A FINDING OWES, SETTLED (wave-28 T41; REQ-8 AC-8.6, D33). An `unsure:` finding wrote
  # `check: <record>#<n> <S> <reach> "<title>"` at registration (lib/proof.sh `proof_finding_lines`);
  # this appends how its check came out to that line, in place, through the plan transaction:
  #
  #   settled <S> <reach>   ` settled=<S>:<reach> by=<check record>`    the rating every read now takes
  #   refuted               ` refuted by=<check record>`                 every read drops the finding
  #   unsettled             ` settled=<its own S>:<reach> by=<…>`        the rating it was registered at stands
  #
  # A settlement the table defers writes the finding's `deferred:` line as well (placed by
  # `proof_add_line`), unless the plan already holds one. THE CHECK IS A THIRD AGENT'S: the check record
  # is a file under record/ of the docs root, as a proof's evidence is, and its flush-left
  # `written-by: <name>` line names who wrote it — never the reader on the finding's proof line, nor the
  # agent of a `## Tasks` row whose Files hold the file the finding names. A check is settled once.
  finding-check)
    if ! { declare -F proof_findings_owed >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F _proof_check_state >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    if [ "$FC_HOW" = settled ] && ! proof_priority "$FC_S" "$FC_R" >/dev/null; then
      die "REFUSED — '$(clean "$FC_S $FC_R")' is no rating on the severity scale: write <S1|S2|S3|S4> <on|off>. The plan is unchanged."
      exit 1
    fi
    plan_verb_open finding-check
    FC_LINE="$(awk -v id="$FC_ID" '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && /^check:[ \t]/ { split($0, f, /[ \t]+/); if (f[2] == id) { print; exit } }' "$PV_PLAN")"
    if [ -z "$FC_LINE" ]; then
      die "REFUSED — $PV_PLAN carries no check: line for $(clean "$FC_ID") under ## SDLC State, and only a check a finding owes is settled; the plan is unchanged."
      exit 1
    fi
    FC_ST="$(_proof_check_state "$PV_PLAN" "$FC_ID")"
    if [ "$FC_ST" != open ]; then
      die "REFUSED — the check of $(clean "$FC_ID") is already $FC_ST on its check: line, and a check is settled once; the plan is unchanged."
      exit 1
    fi
    FC_DOCS="$(docs_root "$PV_REPO")"
    FC_DOCS="$(cd "$FC_DOCS" 2>/dev/null && pwd -P)"
    case "$FC_REC" in
      *[[:space:]]*|*'|'*)
        die "REFUSED — the check record '$(clean "$FC_REC")' carries a space, a tab, a line break or a |, which the check: line cannot hold; rename the file. The plan is unchanged."
        exit 1 ;;
    esac
    case "$FC_REC" in /*) FC_ABS="$FC_REC" ;; *) FC_ABS="$FC_DOCS/$FC_REC" ;; esac
    if [ -L "$FC_ABS" ]; then
      die "REFUSED — the check record $(clean "$FC_REC") is a symbolic link, and what it points at can change after the settlement; copy it into the record. The plan is unchanged."
      exit 1
    fi
    FC_REAL=""
    [ -n "$FC_DOCS" ] && [ -f "$FC_ABS" ] && FC_REAL="$(cd "$(dirname "$FC_ABS")" 2>/dev/null && pwd -P)/$(basename "$FC_ABS")"
    if [ -z "$FC_REAL" ]; then
      die "REFUSED — the check record $(clean "$FC_REC") does not exist (read as $(clean "$FC_ABS")); write the check's record first, then settle it. The plan is unchanged."
      exit 1
    fi
    case "$FC_REAL" in
      "$FC_DOCS"/record/*) FC_REL="${FC_REAL#"$FC_DOCS"/}" ;;
      *)
        die "REFUSED — the check record $(clean "$FC_REC") is not under record/ of the docs root ($FC_DOCS/record/); a check is settled by a record. The plan is unchanged."
        exit 1 ;;
    esac
    FC_BY="$(awk '/^written-by:[ \t]/ { v = $0; sub(/^written-by:[ \t]+/, "", v); sub(/[ \t].*$/, "", v); print v; exit }' "$FC_REAL" 2>/dev/null)"
    if [ -z "$FC_BY" ]; then
      die "REFUSED — the check record $(clean "$FC_REL") does not say who wrote it; write written-by: <the checking agent's roster name> in it, an agent that is neither the finding's reviewer nor the code's writer. The plan is unchanged."
      exit 1
    fi
    # The reviewer: the reader its proof line names (the last one citing the record). The writers: the
    # agent of each `## Tasks` row whose Files hold the file the finding names (`-` names none).
    FC_RECD="${FC_ID%#*}"; FC_N="${FC_ID##*#}"
    FC_READER="$(awk -v ev="$FC_RECD" '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && /^proved:[ \t]/ { e = ""; r = ""; m = split($0, f, /[ \t]+/)
        for (i = 2; i <= m; i++) { if (f[i] == "evidence=" ev) e = 1; else if (f[i] ~ /^reader=/) r = substr(f[i], 8) }
        if (e) who = r }
      END { print who }' "$PV_PLAN")"
    FC_PATH="$(proof_findings "$FC_DOCS/$FC_RECD" 2>/dev/null | awk -F'\t' -v n="$FC_N" '$1 == n { print $4; exit }')"
    FC_PATH="${FC_PATH%:*}"; [ "$FC_PATH" != - ] || FC_PATH=""
    FC_WRITERS=""
    [ -z "$FC_PATH" ] || FC_WRITERS=" $(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' -v p="$FC_PATH" '
      { a = $5; sub(/[ (].*$/, "", a); if (a == "" || a == "—") next
        m = split($9, fs, /[ ,]+/); for (i = 1; i <= m; i++) { gsub(/`/, "", fs[i]); if (fs[i] == p) { print a; break } } }' | tr '\n' ' ')"
    if [ -n "$FC_READER" ] && [ "$FC_BY" = "$FC_READER" ]; then
      die "REFUSED — the check record $(clean "$FC_REL") was written by $(clean "$FC_BY"), the reader of $(clean "$FC_RECD"); a check is written by an agent that is neither the finding's reviewer nor the code's writer. The plan is unchanged."
      exit 1
    fi
    case "$FC_WRITERS" in
      *" $FC_BY "*)
        die "REFUSED — the check record $(clean "$FC_REL") was written by $(clean "$FC_BY"), the agent of the ## Tasks row whose Files hold $(clean "$FC_PATH"); a check is written by an agent that is neither the finding's reviewer nor the code's writer. The plan is unchanged."
        exit 1 ;;
    esac
    case "$FC_HOW" in
      unsettled)
        FC_S="$(printf '%s\n' "$FC_LINE" | awk '{ print $3 }')"; FC_R="$(printf '%s\n' "$FC_LINE" | awk '{ print $4 }')"
        FC_TAIL=" settled=$FC_S:$FC_R by=$FC_REL" ;;
      settled)   FC_TAIL=" settled=$FC_S:$FC_R by=$FC_REL" ;;
      refuted)   FC_TAIL=" refuted by=$FC_REL" ;;
    esac
    FC_TAIL="$FC_TAIL" awk -v id="$FC_ID" '
      /^[[:space:]]*```/ { fence = !fence; print; next }
      fence { print; next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); print; next }
      insdlc && !done && /^check:[ \t]/ {
        split($0, f, /[ \t]+/)
        if (f[2] == id) { done = 1; l = $0; sub(/[ \t]+$/, "", l); print l ENVIRON["FC_TAIL"]; next }
      }
      { print }' "$PV_PLAN" > "$PV_NEW"
    FC_DEF=""
    if [ "$FC_HOW" != refuted ] && [ "$(proof_priority "$FC_S" "$FC_R")" = defer ] && ! deferral_line "$PV_PLAN" "$FC_ID" >/dev/null; then
      FC_DEF="deferred: $FC_ID $FC_S $FC_R $(printf '%s\n' "$FC_LINE" | awk '{ if (match($0, /"[^"]*"/)) print substr($0, RSTART, RLENGTH); else print "\"\"" }')"
      if ! proof_add_line "$PV_NEW" "$FC_DEF" > "$PV_NEW.2" 2>/dev/null || [ ! -s "$PV_NEW.2" ]; then
        die "REFUSED — the deferred: line for $(clean "$FC_ID") could not be placed under ## SDLC State; the plan is unchanged."
        exit 1
      fi
      mv -f "$PV_NEW.2" "$PV_NEW"
    fi
    plan_verb_swap finding-check "the check of $FC_ID" writer
    say "finding-check — $(clean "$FC_ID"):$(clean "$FC_TAIL") on its check: line of $PV_PLAN; dry-committed first."
    [ -z "$FC_DEF" ] || say "finding-check — $(clean "$FC_DEF")"
    exit 0
    ;;

  # A MOVE IS THE USER'S PROVEN WORD (wave-28 T42; REQ-8 AC-8.9, D34). A registered finding — one whose
  # record a `proved:` line names as its evidence — is moved across the line, to defer or to fix, only
  # on words lib/said.sh `user_said` finds in a prompt the user typed in this session's transcript (a
  # tool's result, a teammate's or another session's message, a hook's context and the orchestrator's
  # own text never count; rc 2, no transcript, refuses too; the words stand as WHOLE WORDS and are at
  # least three of them unless they are a whole typed prompt, rc 3 refusing the short ones, T66). An S1, at the rating every read gives it
  # (lib/proof.sh `proof_finding_rating`), is never deferred. The move is written in place after the
  # finding's last line, through the plan transaction:
  #
  #   moved: <record>#<n> to=<defer|fix> by=<git user.name> at=<ISO-UTC> words="<words>" why="<why>"
  #
  # the words folded to one line by lib/said.sh's own fold (`said_fold`, the rule the check is made
  # through; the verb passes the raw words to `user_said`), the why by `deferral_fold`, both escaped as a
  # deferral's sentence is (`deferral_escape`); a move to defer first writes the finding's `deferred:`
  # line when the plan holds none (placed by `proof_add_line`). Every read then takes the priority the last move gave it.
  # Main thread only, by the existing arm's list (lib/walls.sh `_wall_poker_contract_verb`).
  finding-move)
    if ! { declare -F proof_finding_rating >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F _proof_moved_to >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    if ! declare -F user_said >/dev/null 2>&1 && [ -f "$BIONIC_LIB/said.sh" ]; then
      . "$BIONIC_LIB/said.sh"
    fi
    if ! declare -F user_said >/dev/null 2>&1; then
      die "REFUSED — what the user typed is read by lib/said.sh, which cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    FM_WORDS="$(said_fold "$FM_RAW")"; FM_WHY="$(deferral_fold "$FM_WHY_RAW")"
    plan_verb_open finding-move
    FM_REC="${FM_ID%#*}"; FM_N="${FM_ID##*#}"
    if ! awk -v ev="$FM_REC" '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && /^proved:[ \t]/ { m = split($0, f, /[ \t]+/); for (i = 2; i <= m; i++) if (f[i] == "evidence=" ev) hit = 1 }
      END { exit !hit }' "$PV_PLAN"; then
      die "REFUSED — $(clean "$FM_REC") is no reading registered under ## SDLC State (no proved: line names it as its evidence), and only a registered finding is moved; the plan is unchanged."
      exit 1
    fi
    FM_DOCS="$(docs_root "$PV_REPO")"
    FM_F="$(proof_findings "$FM_DOCS/$FM_REC" 2>/dev/null | awk -F'\t' -v n="$FM_N" '$1 == n { print; exit }')"
    if [ -z "$FM_F" ]; then
      die "REFUSED — the reading $(clean "$FM_REC") holds no finding $FM_N (read as $(clean "$FM_DOCS/$FM_REC")); the plan is unchanged."
      exit 1
    fi
    IFS='	' read -r _ FM_S FM_R _ _ _ _ FM_TITLE <<FM_FINDING
$FM_F
FM_FINDING
    set -- $(proof_finding_rating "$PV_PLAN" "$FM_ID" "$FM_S" "$FM_R")
    if [ $# -lt 3 ]; then
      die "REFUSED — $(clean "$FM_ID") was refuted by its check, so there is no finding to move; the plan is unchanged."
      exit 1
    fi
    FM_S="$1"; FM_R="$2"
    if [ "$FM_TO" = defer ] && [ "$FM_S" = S1 ]; then
      die "REFUSED — $(clean "$FM_ID") is rated S1 $FM_R, and an S1 is never deferred, whoever asks; the plan is unchanged."
      exit 1
    fi
    FM_WHO="$(deferral_fold "$(git -C "$PV_REPO" config user.name 2>/dev/null)")"
    if [ -z "$FM_WHO" ]; then
      die "REFUSED — no git user.name is set for $PV_REPO, and a move records who made it; set it, then move again. The plan is unchanged."
      exit 1
    fi
    user_said "$FM_RAW"; FM_SAID=$?
    if [ "$FM_SAID" -eq 2 ]; then
      die "REFUSED — this session's transcript cannot be found or read (session ${CLAUDE_CODE_SESSION_ID:-none} under ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects), so the words cannot be held to what the user typed; the plan is unchanged."
      exit 1
    fi
    if [ "$FM_SAID" -eq 3 ]; then
      die "REFUSED — the words \"$(clean "$FM_WORDS")\" are too short to be the user's decision; quote at least three of their words, or their whole prompt. The plan is unchanged."
      exit 1
    fi
    if [ "$FM_SAID" -ne 0 ]; then
      die "REFUSED — the words \"$(clean "$FM_WORDS")\" stand in no prompt the user typed in this session; a move is the user's own word, quoted from a prompt they typed. The plan is unchanged."
      exit 1
    fi
    cp "$PV_PLAN" "$PV_NEW"
    FM_DEF=""
    if [ "$FM_TO" = defer ] && ! deferral_line "$PV_PLAN" "$FM_ID" >/dev/null; then
      FM_DEF="deferred: $FM_ID $FM_S $FM_R \"$(printf '%s' "$FM_TITLE" | tr '"' "'")\""
      if ! proof_add_line "$PV_NEW" "$FM_DEF" > "$PV_NEW.2" 2>/dev/null || [ ! -s "$PV_NEW.2" ]; then
        die "REFUSED — the deferred: line for $(clean "$FM_ID") could not be placed under ## SDLC State; the plan is unchanged."
        exit 1
      fi
      mv -f "$PV_NEW.2" "$PV_NEW"
    fi
    FM_LINE="moved: $FM_ID to=$FM_TO by=$FM_WHO at=$(iso_now) words=\"$(deferral_escape "$FM_WORDS")\" why=\"$(deferral_escape "$FM_WHY")\""
    # IN PLACE: after the last line of the block naming the finding (its deferred:, check: or an earlier
    # moved: line), else after the last proof line naming its record; else where proof_add_line puts it.
    FM_LINE="$FM_LINE" awk -v id="$FM_ID" -v ev="$FM_REC" '
      BEGIN { L = ENVIRON["FM_LINE"] }
      { row[NR] = $0 }
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && /^(deferred|check|moved):[ \t]/ { split($0, f, /[ \t]+/); if (f[2] == id) own = NR }
      insdlc && /^proved:[ \t]/ { m = split($0, f, /[ \t]+/); for (i = 2; i <= m; i++) if (f[i] == "evidence=" ev) pr = NR }
      END {
        at = own ? own : pr
        if (!at) exit 1
        for (i = 1; i <= NR; i++) { print row[i]; if (i == at) print L }
      }' "$PV_NEW" > "$PV_NEW.2" && [ -s "$PV_NEW.2" ] || {
      die "REFUSED — the moved: line for $(clean "$FM_ID") could not be placed under ## SDLC State; the plan is unchanged."
      exit 1
    }
    mv -f "$PV_NEW.2" "$PV_NEW"
    plan_verb_swap finding-move "the move of $FM_ID" writer
    say "finding-move — $(clean "$FM_ID") to $FM_TO on the user's words, by $(clean "$FM_WHO"): its moved: line is on $PV_PLAN; dry-committed first."
    [ -z "$FM_DEF" ] || say "finding-move — $(clean "$FM_DEF")"
    exit 0
    ;;

  # THE RELEASE CHECK (wave-27 T16; D12). A project may name one command in `.bionic/config.yaml`
  # under `release-check:`. This verb runs it in the checkout of the plan's working branch, with
  # BIONIC_CHECK_BASE at the last release and BIONIC_CHECK_HEAD at the working head, its words
  # split on blanks with globbing off as `impact-command:` is run (lib/proof.sh `_proof_map`).
  # THE LAST RELEASE is the nearest tag reachable from the plan's `integration-branch:` that is a
  # PROPER ancestor of the working head (the fewest commits from it to the head): a tag on the head,
  # or on a commit that is not on the head's history, is no base, for the range it opens would hold
  # nothing or the wrong thing (wave-27 T31; review pass 22 S2). With none, the plan's `base-sha:`.
  # A range holding no commit is refused, never judged.
  # EVERY RUN KEEPS ITS LOG AND ITS FACT (T31; S3): `record/<wave>/release-check-<head>.log`, the
  # n-th run at one head `release-check-<head>-<n>.log`, so no run overwrites another's; it opens
  # with a `check-changed: <path>` line per tracked path the command names as a word and the range
  # changes (B1: the check's own files are covered code, and the user is told when they moved), then
  # `head=<40-hex> rc=<exit>`. On exit 0 the `kind=check` proof line names it (lib/proof.sh
  # `proof_attested` holds the log against the checkout); on any other exit the command's output is
  # printed and the line carries ` result=fail`, which the judge reads as the head's last word. With
  # no key it runs, writes and prints nothing.
  release-check)
    RC_CMD="$(config_value "$(project_root "$PWD")" release-check "" 2>/dev/null)"
    [ -n "$RC_CMD" ] || exit 0
    if ! { declare -F proof_line >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_add_line >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; nothing was run and the plan is unchanged."
      exit 2
    fi
    plan_verb_open release-check
    RC_WB="$(proof_working_branch "$PV_PLAN")"
    RC_CO=""; [ -z "$RC_WB" ] || RC_CO="$(proof_checkout "$PV_REPO" "$RC_WB")" || RC_CO=""
    RC_HEAD=""; [ -z "$RC_CO" ] || RC_HEAD="$(git -C "$RC_CO" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)"
    case "$RC_HEAD" in
      [0-9a-f]*) : ;;
      *)
        die "REFUSED — no checkout of $PV_REPO has the plan's working-branch ${RC_WB:-(none named)} checked out, so there is no head to check; nothing was run and the plan is unchanged."
        exit 1 ;;
    esac
    # THE COMMAND RUNS ON THE HEAD ALONE: the log says it ran at that head, and a command that reads
    # the working files would read uncommitted changes as the head's. The index is refreshed first,
    # so a file whose stat moved and whose content did not is not called a change (T31; S4).
    git -C "$RC_CO" update-index -q --refresh >/dev/null 2>&1
    if ! git -C "$RC_CO" diff-index --quiet HEAD -- 2>/dev/null \
       || [ -n "$(git -C "$RC_CO" ls-files --others --exclude-standard 2>/dev/null)" ]; then
      die "REFUSED — the working checkout $RC_CO has uncommitted changes, so the check would not read the head $RC_HEAD alone; commit them and run release-check again. Nothing was run and the plan is unchanged."
      exit 1
    fi
    RC_IB="$(plan_frontmatter_get "$PV_PLAN" integration-branch 2>/dev/null)"
    RC_BASE=""; RC_FROM=""; RC_BEST=""
    if [ -n "$RC_IB" ]; then
      while IFS= read -r RC_TAG; do
        [ -n "$RC_TAG" ] || continue
        RC_TC="$(git -C "$RC_CO" rev-parse --verify -q "refs/tags/$RC_TAG^{commit}" 2>/dev/null)" || continue
        [ "$RC_TC" != "$RC_HEAD" ] || continue
        git -C "$RC_CO" merge-base --is-ancestor "$RC_TC" "$RC_HEAD" 2>/dev/null || continue
        RC_TN="$(git -C "$RC_CO" rev-list --count "$RC_TC..$RC_HEAD" 2>/dev/null)" || continue
        if [ -z "$RC_BEST" ] || [ "$RC_TN" -lt "$RC_BEST" ]; then
          RC_BEST="$RC_TN"; RC_BASE="$RC_TC"; RC_FROM="tag $RC_TAG on $RC_IB"
        fi
      done <<RC_TAGS
$(git -C "$RC_CO" tag --merged "refs/heads/$RC_IB" 2>/dev/null)
RC_TAGS
    fi
    if [ -z "$RC_BASE" ]; then
      RC_BS="$(proof_plan_base "$PV_PLAN" "$RC_CO")"
      [ -z "$RC_BS" ] || RC_BASE="$(git -C "$RC_CO" rev-parse --verify -q "$RC_BS^{commit}" 2>/dev/null)"
      RC_FROM="base-sha $RC_BS"
    fi
    if [ -z "$RC_BASE" ]; then
      die "REFUSED — no tag reachable from the plan's integration-branch (${RC_IB:-none named}) is a proper ancestor of the working head and its base-sha (${RC_BS:-none}) is no commit here, so the release range has no start; nothing was run and the plan is unchanged."
      exit 1
    fi
    if [ "$(git -C "$RC_CO" rev-list --count "$RC_BASE..$RC_HEAD" 2>/dev/null)" = 0 ]; then
      die "REFUSED — the release range ${RC_BASE:0:12}..${RC_HEAD:0:12} ($RC_FROM) holds no commit, so there is nothing for the check to judge; name the last release as the plan's base-sha, or tag it. Nothing was run and the plan is unchanged."
      exit 1
    fi
    # THE CHECK'S OWN FILES (T31; review pass 22 B1). Each word of the command that names one tracked
    # file, read literally (no glob, no shell parsing), and that the range changes. The case arm
    # opens with `(`: bash 3.2, the shebang's interpreter, reads an unopened arm's `)` inside a
    # `$( )` as the substitution's end (T80).
    RC_CHG="$(set -f
      for RC_W in $RC_CMD; do
        RC_P="$(git --literal-pathspecs -C "$RC_CO" ls-files --full-name --error-unmatch -- "$RC_W" 2>/dev/null)" || continue
        case "$RC_P" in (''|*"
"*) continue ;; esac
        git --literal-pathspecs -C "$RC_CO" diff --quiet "$RC_BASE" "$RC_HEAD" -- "$RC_P" >/dev/null 2>&1 \
          || printf 'check-changed: %s\n' "$RC_P"
      done | awk '!seen[$0]++')"
    RC_OUT="$(cd "$RC_CO" 2>/dev/null || exit 1
      set -f
      export BIONIC_CHECK_BASE="$RC_BASE" BIONIC_CHECK_HEAD="$RC_HEAD" BIONIC_CHECK_TREE="$(pwd -P)"
      # shellcheck disable=SC2086  # the configured command splits on blanks, as impact-command does
      exec $RC_CMD </dev/null 2>&1)"; RC_RC=$?
    # WHAT THE CHECK LEFT (wave-27 T67; review pass 46 N7), looked at as `land` looks after its own run
    # (lib/worktree.sh `_wt_check_left`): the checkout's HEAD where it was, and no tracked file changed
    # (the index refreshed first). A check that moved either is refused as a failing check is: its log,
    # and a result=fail check fact at the head it ran on.
    git -C "$RC_CO" update-index -q --refresh >/dev/null 2>&1
    RC_LEFT=""; RC_NOW="$(git -C "$RC_CO" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)"
    [ "$RC_NOW" = "$RC_HEAD" ] || RC_LEFT="moved the head of $RC_CO from ${RC_HEAD:0:12} to ${RC_NOW:-<none>}"
    git -C "$RC_CO" diff-index --quiet HEAD -- 2>/dev/null \
      || RC_LEFT="${RC_LEFT:+$RC_LEFT and }left tracked files changed in $RC_CO (git -C $RC_CO status)"
    RC_WAVE="${PV_PLAN##*/}"; RC_WAVE="${RC_WAVE%.plan.md}"
    RC_DOCS="$(docs_root "$PV_REPO")"
    RC_REL="record/$RC_WAVE/release-check-$RC_HEAD.log"; RC_NTH=1
    while [ -e "$RC_DOCS/$RC_REL" ]; do RC_NTH=$((RC_NTH + 1)); RC_REL="record/$RC_WAVE/release-check-$RC_HEAD-$RC_NTH.log"; done
    RC_LOG="$RC_DOCS/$RC_REL"
    RC_SAID=""; [ -z "$RC_CHG" ] || RC_SAID=" $(printf '%s\n' "$RC_CHG" | tr '\n' ' ' | sed 's/ $//')"
    if [ "$RC_RC" -ne 0 ]; then
      [ -z "$RC_OUT" ] || printf '%s\n' "$RC_OUT"
    fi
    if ! mkdir -p "${RC_LOG%/*}" 2>/dev/null \
       || ! { [ -z "$RC_CHG" ] || printf '%s\n' "$RC_CHG"
              printf 'head=%s rc=%s\nbase=%s (%s)\ncommand: %s\n' "$RC_HEAD" "$RC_RC" "$RC_BASE" "$RC_FROM" "$RC_CMD"
              [ -z "$RC_LEFT" ] || printf 'check-dirtied: the check %s\n' "$RC_LEFT"
              printf '\n'
              [ -z "$RC_OUT" ] || printf '%s\n' "$RC_OUT"; } > "$RC_LOG" 2>/dev/null; then
      die "REFUSED — the check exited $RC_RC, but its log $RC_LOG cannot be written; the plan is unchanged.$RC_SAID"
      exit 1
    fi
    if [ "$RC_RC" -ne 0 ] || [ -n "$RC_LEFT" ]; then
      if ! proof_add_line "$PV_PLAN" "$(proof_line check "$RC_HEAD" "$(iso_now)" "$RC_REL") result=fail" > "$PV_NEW" 2>/dev/null || [ ! -s "$PV_NEW" ]; then
        die "REFUSED — the declared release-check ($(clean "$RC_CMD")) exited $RC_RC over ${RC_BASE:0:12}..${RC_HEAD:0:12} ($RC_FROM), and $PV_PLAN carries no ## SDLC State section to hold its failing fact; its log is $RC_LOG.$RC_SAID"
        exit 1
      fi
      plan_verb_swap release-check "the failing check at $RC_HEAD" writer
      if [ -n "$RC_LEFT" ]; then
        die "REFUSED — check-dirtied: the declared release-check ($(clean "$RC_CMD")) $RC_LEFT, as land refuses a check that does; its log $RC_REL and a result=fail check fact at ${RC_HEAD:0:12} were written. Put back what it changed, make the check change nothing, and run release-check again.$RC_SAID"
        exit 1
      fi
      die "REFUSED — the declared release-check ($(clean "$RC_CMD")) exited $RC_RC over ${RC_BASE:0:12}..${RC_HEAD:0:12} ($RC_FROM); its log $RC_REL and a result=fail check fact at that head were written. Fix what it names, commit, and run release-check again.$RC_SAID"
      exit 1
    fi
    if ! RC_AT="$(proof_attested check "$RC_LOG" "$RC_CO")"; then
      die "REFUSED — $(clean "$RC_AT"). The plan is unchanged."
      exit 1
    fi
    if ! proof_add_line "$PV_PLAN" "$(proof_line check "$RC_AT" "$(iso_now)" "$RC_REL")" > "$PV_NEW" 2>/dev/null || [ ! -s "$PV_NEW" ]; then
      die "REFUSED — $PV_PLAN carries no ## SDLC State section to hold the check proof; the plan is unchanged."
      exit 1
    fi
    plan_verb_swap release-check "the check proof at $RC_AT" writer
    say "release-check — kind=check head=$RC_AT base=$RC_BASE ($RC_FROM) evidence=$RC_REL: written to $PV_PLAN; dry-committed first.$RC_SAID"
    # THE PRIORITY A RECORD NEVER STATES (wave-28 T15; D19): each finding the plan defers or owes a
    # check for, with the table's priority (lib/proof.sh `proof_findings_owed`, the tick's own line).
    proof_findings_owed "$PV_PLAN" 2>/dev/null | while IFS= read -r _rc_f; do say "release-check — finding $(clean "$_rc_f")"; done
    # THE DEFERRALS' OTHER DEBT (wave-28 T17; D21): each says whether its sentence is in the head's CHANGELOG.md.
    # It refuses nothing, and the exit below is the check's own.
    release_deferrals "$PV_PLAN" "$RC_CO/CHANGELOG.md"
    # THE RUN'S NUMBERS (wave-28 T14; D18): the report's line and each landed row, read and printed only.
    landing_report "$(_wt_proofs_path "$PV_REPO" "$PV_PLAN")" "$(cd "$PV_REPO" 2>/dev/null && pwd -P)" yes \
      | while IFS= read -r _rc_l; do say "release-check — $_rc_l"; done
    exit 0
    ;;

  # THE RUN'S NUMBERS (wave-28 T14; D18, REQ-4). The fold and its definitions are `landing_report`'s,
  # above the verbs. The plan is the one named, resolved as fill-report resolves its operand (a path
  # from the project root, else from the docs root), or else this session's bound run; the record is
  # that plan's landing record, under the plan's own project. It writes nothing and exits 0 whatever
  # the record holds.
  landing-report)
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    LR_PLAN=""
    if [ -n "$LR_ARG" ]; then
      case "$LR_ARG" in
        /*) LR_PLAN="$LR_ARG" ;;
        *)  LR_PLAN="$REPO_REAL/$LR_ARG"
            [ -f "$LR_PLAN" ] || LR_PLAN="$(docs_root "$REPO_REAL")/$LR_ARG" ;;
      esac
      if [ ! -f "$LR_PLAN" ] || [ -L "$LR_PLAN" ]; then
        die "REFUSED — no plan file at $LR_ARG; name the plan whose landings to report."
        exit 2
      fi
    else
      SESSION_ID="$(session_id)" || SESSION_ID=""
      if [ -z "$SESSION_ID" ]; then
        die "REFUSED — no session key, and no plan named; a report without an operand is for THIS session's run."
        exit 3
      fi
      resolve_run "$REPO_REAL" "$SESSION_ID"
      LR_PLAN="$POKER_RUN_PLAN"
      if [ -z "$LR_PLAN" ] || [ ! -f "$LR_PLAN" ]; then
        die "REFUSED — this session has no run to report on; bind its plan first."
        exit 2
      fi
    fi
    LR_ROOT="$(cd "$(project_root "${LR_PLAN%/*}")" 2>/dev/null && pwd -P)"
    [ -n "$LR_ROOT" ] || LR_ROOT="$REPO_REAL"
    landing_report "$(_wt_proofs_path "$LR_ROOT" "$LR_PLAN")" "$LR_ROOT" "$LR_ROWS"
    exit 0
    ;;


  # THE LAUNCH SYNC (wave-26 T32; D4). Its reasoning is above the verbs, beside the functions it
  # runs. Silent, exit 0, wherever there is nothing it may write: no engagement, no bound open run,
  # a plan before Step 4 (`current:` not a step of 4 or more), no roster, or a lock another writer
  # holds when the caller does not wait. What it cannot write prints, and the exit says whether a
  # retry repairs it (wave-26 T51; review 13 F6): 75 when another writer replaced the plan while
  # this one judged its copy, which the next caller repairs by running again, and when the lock's
  # mkdir keeps failing with no lock there (T54; review 17 N1), said in one line; 1 for every refusal
  # no retry repairs (a launch the plan cannot take, the validator or the commit gate refusing the
  # batch, a lock that cannot be made); 2 when the dry commit cannot run at all.
  launch-sync)
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "launch-sync applies ONE session's launches, so without the key there is nothing to read."
      exit 3
    fi
    LS_ROOT="$(cd "$(project_root "$PWD")" 2>/dev/null && pwd -P)" || LS_ROOT=""
    [ -n "$LS_ROOT" ] || exit 0
    engaged_session "$LS_ROOT" "$SESSION_ID" || exit 0
    LS_RUN="$(session_run "$LS_ROOT" "$SESSION_ID" 2>/dev/null)" || LS_RUN=""
    case "$LS_RUN" in 'bound-open '*) LS_PLAN="${LS_RUN#bound-open }" ;; *) exit 0 ;; esac
    # THE ROSTER FIRST: a session that has confirmed no launch has nothing to apply, and the
    # turn-end wall runs this on every Stop, so the plan is not read for it (patrol-duties-gate 70).
    LS_ROSTER="$LS_ROOT/.bionic/tmp/roster-${SESSION_ID}.state"
    [ -f "$LS_ROSTER" ] && [ ! -L "$LS_ROSTER" ] || exit 0
    grep -qE '\|status=(confirmed|identified)\|' "$LS_ROSTER" 2>/dev/null || exit 0
    LS_CUR="$(_fill_current_field "$LS_PLAN")"; LS_CUR="${LS_CUR%[ab]}"
    case "$LS_CUR" in ''|*[!0-9]*) exit 0 ;; esac
    [ "$LS_CUR" -ge 4 ] || exit 0
    tmp_dir_ok "$LS_ROOT/.bionic/tmp" || exit 0
    # A LOCK THAT CANNOT BE MADE IS NOT A LOCK ANOTHER WRITER HOLDS (wave-26 T51; review 13 F1):
    # held, the holder writes the launches and this call says nothing; not makeable, no caller
    # can write them until the directory can be written, so it is said, exit 1, as a refusal.
    LS_LOCK_RC=0
    launch_sync_lock "$LS_ROOT/.bionic/tmp/launch-sync.lock" "$LS_WAIT" || LS_LOCK_RC=$?
    case "$LS_LOCK_RC" in
      0) : ;;
      2)
        die "REFUSED — the launch-sync lock $LS_ROOT/.bionic/tmp/launch-sync.lock cannot be made: its directory is missing or not writable. Nothing was written; no launch of this session is recorded in the plan until it can be."
        exit 1 ;;
      3)
        die "launch-sync — the lock $LS_ROOT/.bionic/tmp/launch-sync.lock could not be made although its directory can be written (a full disk or a quota?). No launch was applied by this call; the next tick applies them once it can be."
        exit 75 ;;
      *) exit 0 ;;
    esac
    trap 'launch_sync_unlock' EXIT
    plan_verb_open launch-sync
    # THE CHECKSUM AGAIN, NOW THE LOCK IS HELD: plan_verb_open took it before this run owned the
    # plan, and a writer that finished in between is not a change this transaction has to refuse.
    PV_SUM="$(cksum < "$PV_PLAN" 2>/dev/null)"
    LS_SWAPPED=no
    launch_sync_exit() {
      local rc=$?
      rm -f "$PV_NEW" "$PV_NEW.2" "$PV_NEW.l" "$PV_NEW.r" "$PV_NEW.ledger" "$PV_DRY" ${PV_MARK:+"$PV_MARK"} 2>/dev/null
      if [ "$rc" -ne 0 ] && [ "$LS_SWAPPED" = no ] && [ -n "${LS_HANDS:-}" ]; then
        die "launch-sync: nothing was written. Fix what refused it, then run these by hand (or let the next tick retry):"
        printf '%s' "$LS_HANDS" >&2
      fi
      launch_sync_unlock
    }
    trap launch_sync_exit EXIT
    launch_sync_sweep "$PV_PLAN" "$PV_REPO"
    LS_RC=0
    LS_PROJECTED=no
    launch_sync_project "$PV_PLAN" "$PV_REPO" "$SESSION_ID" "$LS_ROSTER" \
      "$PV_REPO/.bionic/tmp/sweeper-${SESSION_ID}.state" "$PV_NEW" && LS_PROJECTED=yes
    # WHAT CANNOT BE RECORDED PRINTS FIRST, so a refusal of the rest below cannot hide it.
    if [ -n "$LS_FAILS" ]; then
      printf '%s' "$LS_FAILS" | sed 's/^NOT-RECORDED /poker: NOT-RECORDED /'
      LS_RC=1
    fi
    if [ "$LS_PROJECTED" = yes ]; then
      LS_VIOL="$(units_validate "$PV_NEW" 2>&1)"
      if [ -n "$LS_VIOL" ]; then
        die "REFUSED — with these launches recorded, the ## Tasks table breaks the Task invariants; the plan is unchanged:"
        printf '%s\n' "$LS_VIOL" >&2
        exit 1
      fi
      [ "$LS_RC" = 0 ] && PV_RACE_RC=75   # a launch it could not record keeps exit 1
      plan_verb_swap launch-sync "$(printf '%s' "$LS_SAID" | awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $2 }') recorded" writer
      LS_SWAPPED=yes
      printf '%s' "$LS_SAID" | sed 's/^/poker: /'
    fi
    exit "$LS_RC"
    ;;

  tick)
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "A tick answers for ONE session's roster, so without the key there is nothing to read."
      exit 3
    fi

    # ---------- THE ENGAGEMENT GUARD (AC-10): is this session bionic's at all? ----------
    #
    # BEFORE ANYTHING IS READ, DECIDED OR WRITTEN — above the stamp, above the roster,
    # above the sweeper. Chris, 2026-09-03: "all guardrails imposed by bionic should only
    # apply when exercising bionic. Nothing should apply until bionic is triggered" — and
    # the trigger is the canonical-sdlc skill, which writes
    # `.bionic/tmp/engaged-<sid>.state` at the instant it is invoked. The Patrol prompt
    # runs this verb, and a Patrol inherited by a session that never invoked the skill
    # must decide nothing about it rather than deciding wrongly.
    #
    # ONE LINE, EXIT 0, and not a refusal: the tick fired correctly and found nothing it
    # is entitled to judge. `arm` is deliberately not guarded (writing a stamp for a
    # session that asked for one is harmless) and neither is `disarm`, which removes the
    # stamp and leaves this marker exactly where it is — a session that invoked the skill
    # is bionic's for its whole life, so every hook still binds after a disarm (AC-15).
    # [WALL: tests/session-poker.test.sh]
    if ! engaged_session "$(project_root "$PWD")" "$SESSION_ID"; then
      say "NOT-ENGAGED — this session has not invoked /bionic:canonical-sdlc; nothing decided"
      exit 0
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

    # ---------- THE TICK SAYS WHAT CHANGED, OR "unchanged" (wave-24 T7, REQ-4; D4, D5) ----------
    #
    # THE DEFECT (research-R1). Every tick printed its whole reading — the rung, the holds, the
    # stand-downs, the fill — whether or not anything had moved since the last one, and the
    # Patrol prompt asked the model to answer each of them every time. A tick over the same
    # facts now prints one line: `poker: unchanged since <at> — decision=<band>`.
    #
    # THE OUTPUT IS HELD UNTIL THE DECISION. Every line the tick prints below goes to a buffer;
    # `tick_conclude` hashes what was decided (the band, the sorted per-row verdicts, the named
    # lines, the fill, `current:`, the pressure band — never an instant) and compares it with the
    # hash `tick_digest_file` kept from the last tick. The exit trap then prints the buffer, or
    # the one line, and writes the file. A tick that exits on a refusal prints its buffer as it
    # always did and writes no digest. stderr is not held: a warning is a warning on every tick.
    #
    # THE PROMPT VERSION rides the same file: `arm` records the version its prompt carried, and a
    # tick that finds none, or an older one, prints one re-arm line above everything else.
    TICK_BUF="$(mktemp "${TMPDIR:-/tmp}/bionic-poker-tick.XXXXXX" 2>/dev/null)" || TICK_BUF=""
    # ONE FLOOR STATE PER TICK (wave-26 T64). The schedule and the change fingerprint below each
    # parse the table under their own `units_memoised`; this names the one file both keep the
    # floor state in (lib/units.sh `_units_floor_state`), so a tick runs `proof_state` once.
    [ -z "$TICK_BUF" ] || _UNITS_MEMO_FLOOR="$TICK_BUF.floor"
    TICK_DIGEST=""; TICK_UNCHANGED=no; TICK_SINCE=""; TICK_DECIDED=""; TICK_DUTY=owed; TICK_CHANGE=""; TICK_CHANGE_STORE=""
    TICK_PLAN_CUR=""; TICK_PLAN_ROWS=""
    TICK_GATE_KEYS=""; TICK_GATE_NEW=""; TICK_GATE_FIELD=""; TICK_LANDINGS=""
    TICK_DIGEST_FILE="$(tick_digest_file "$SESSION_ID")" || TICK_DIGEST_FILE=""
    TICK_PVER="$(tick_digest_field "$TICK_DIGEST_FILE" prompt_version)"
    TICK_REARM=""
    case "$TICK_PVER" in ''|*[!0-9]*) TICK_PVER_N=0 ;; *) TICK_PVER_N="$TICK_PVER" ;; esac
    if [ "$TICK_PVER_N" -lt "$PATROL_PROMPT_VERSION" ]; then
      TICK_REARM="poker: note: re-arm the Patrol — its prompt is v=${TICK_PVER:-unrecorded} and this poker prints v=${PATROL_PROMPT_VERSION}: replace the bionic-patrol job with one carrying the output of \`bash ${POKER_WORD} prompt\`, then run \`bash ${POKER_WORD} arm\`"
    fi
    tick_emit() {
      local rc=$?
      [ -n "$TICK_BUF" ] || exit "$rc"
      exec 1>&3 3>&-
      if [ -n "$TICK_DIGEST" ] && [ -n "$TICK_REARM" ]; then
        printf '%s\n' "$TICK_REARM"
      fi
      if [ "$TICK_UNCHANGED" = yes ]; then
        say "unchanged since ${TICK_SINCE} — decision=${TICK_DECIDED}"
      else
        cat "$TICK_BUF" 2>/dev/null
        # A START IS TOLD BY THE TICK THAT PRINTED ITS LINE (wave-27 T37; review pass 36 S1).
        [ -z "${US_TOLD_PENDING:-}" ] || printf '%s' "$US_TOLD_PENDING" >> "$ROSTER_FILE" 2>/dev/null
      fi
      # THE RUN'S LANDING LINE PRINTS ON A TICK THAT IS NOT `unchanged`, OUTSIDE THE DIGEST (wave-28 T14, T62;
      # D18): a landing moves no decision (RP4), so it never makes a tick changed; the line shows on the
      # ticks that print in full for another reason, and an `unchanged` tick stays the one line the Patrol ends on.
      [ "$TICK_UNCHANGED" = yes ] || [ -z "$TICK_LANDINGS" ] || say "$TICK_LANDINGS"
      rm -f "$TICK_BUF" "$TICK_BUF.floor" 2>/dev/null
      if [ -n "$TICK_DIGEST" ]; then
        write_tick_digest "$SESSION_ID" "$TICK_PVER" "$TICK_DIGEST" "$TICK_SINCE" "$TICK_DECIDED" "$TICK_DUTY" "$TICK_GATE_KEYS" "$TICK_CHANGE_STORE" "${UNITS_LIVE_HEAD:-}" "$TICK_PLAN_CUR" "$TICK_PLAN_ROWS" "${UNITS_FACTS_STATE:-}" "${TICK_RECONCILE:-}" \
          || die "WARN — the tick digest could not be written; the next tick prints in full."
      fi
      exit "$rc"
    }
    if [ -n "$TICK_BUF" ]; then
      exec 3>&1 1>"$TICK_BUF"
      trap tick_emit EXIT
    fi

    # THE DECISION, HASHED (D4). Called once, by whichever arm decides, BEFORE that arm prints
    # its sentence and its decision line — so the buffer holds exactly the lines the decision
    # was reached on. What enters the hash: the band, the decision line's counts and lists, the
    # pressure band (its state and rung), `current:`, every row's verdict as `name|state|acked`
    # sorted, and the named lines the tick printed reduced to their kind and subject (a
    # STANDDOWN, a held row, a GONE report, a duplicate tell, an ext: hold, a ledger finding, a
    # standing fill decline, a note). Never an instant, an age or a measurement: those move on every tick by themselves.
    # DISARM is terminal and a tick over the share names what holds the memory, so both always
    # print in full.
    #
    # THE GATE (wave-25 T5; D7). A pending gate request raises the band to NOTIFY unless it is
    # DISARM, which outranks it; the caller passes the band it reached without the gate and reads
    # the answer back from TICK_DECIDED. The hash takes that band and the keys of every request in
    # the gate file, raised or not, so the tick after the one that raised a request hashes the
    # same and prints the unchanged line; a new request is a new key and prints in full. No file,
    # or one with no request in it, adds nothing to the hash.
    #
    # THE DUTY (wave-26 T15, REQ-4 AC-4.5; D16, research-R2 §3 P4). The task-list refresh is
    # owed only when a `## Tasks` row's status or the ready set moved since the last tick: that
    # is what the ledger can fall behind on. A tick whose news is a progress file's age, a load
    # band or a roster row's liveness prints in full and owes nothing. `TICK_CHANGE` is that
    # fingerprint, kept in the digest as `change=` beside the whole-decision hash and entered
    # into it too, so a tick that says `unchanged` has, by construction, nothing to reconcile.
    # A QUIET tick owes no reconcile for a status move: with a row open it prints WAITING, which
    # asks for nothing, and with none open there is nothing running to reconcile against
    # (A-orch-4). It does owe one when the plan MOVED (`tick_plan_moved`, below). The stop wall's
    # collector reads this line, so a turn is not refused for a chore with nothing behind it.
    tick_change_rows() {  # -> the plan's id|status lines in table order, then its ready set
      units_rows "$SCHED_PLAN" 2>/dev/null | awk -F'\t' 'NF { print $1 "|" $10 }'
      printf 'ready=%s\n' "$(fill_ready_set "$SCHED_PLAN" 99999 0 2>/dev/null | tr '\n' ' ')"
    }
    # THE TASK LIST IS REBUILT AT PLAN APPROVAL (wave-27 T13; D20; steps/3.md). No hook reads a
    # task list, so this line is the only wall the rule has: the duty is also owed when the
    # plan's `current:` was 3 at the last digest and is 4 now, or its row count has grown, and
    # it is owed on a QUIET tick too (a plan at approval has nothing open yet).
    # WHICH MOVE IT WAS (wave-27 T37; review pass 8 F2) is TICK_RECONCILE, `step4` or `grew`: the
    # RECONCILE line says it and names the rebuild, and the digest keeps it as `reconcile=` so
    # the turn-end wall's refusal gives the same cause. A move into Step 4 is named first when
    # the table also grew: the rebuild it asks for covers the new rows.
    TICK_RECONCILE=""
    tick_plan_moved() {  # -> 0 when the digest's last reading of the plan is behind this one
      local pc pr
      TICK_RECONCILE=""
      pc="$(tick_digest_field "$TICK_DIGEST_FILE" plan_current)"
      pr="$(tick_digest_field "$TICK_DIGEST_FILE" plan_rows)"
      if [ "$pc" = 3 ] && [ "$TICK_PLAN_CUR" = 4 ]; then TICK_RECONCILE=step4; return 0; fi
      case "$pr" in ''|*[!0-9]*) return 1 ;; esac
      [ -n "$TICK_PLAN_ROWS" ] && [ "$TICK_PLAN_ROWS" -gt "$pr" ] || return 1
      TICK_RECONCILE=grew
    }
    tick_conclude() {  # <decision before the gate>
      local cur="" prev=""
      TICK_DECIDED="$1"
      if [ -n "$TICK_GATE_NEW" ] && [ "$1" != DISARM ]; then
        TICK_DECIDED=NOTIFY
      fi
      if [ -n "${SCHED_PLAN:-}" ] && [ -f "${SCHED_PLAN:-}" ]; then
        cur="$(_sched_plan_current_field "$SCHED_PLAN")"
      fi
      TICK_CHANGE="none"
      if [ -n "${SCHED_PLAN:-}" ] && [ -f "${SCHED_PLAN:-}" ] && [ "$POKER_RUN_OPEN" != unreadable ]; then
        TICK_CHANGE="$(tick_plan_memoised tick_change_rows | cksum | awk '{ print $1 "-" $2 }')"
        TICK_PLAN_CUR="$(sched_plan_current "$SCHED_PLAN")"
        TICK_PLAN_ROWS="$(tick_plan_memoised tick_change_rows | grep -vc '^ready=')"
      fi
      if [ -n "$TICK_BUF" ]; then
        TICK_DIGEST="$( {
          printf 'change=%s\n' "$TICK_CHANGE"
          printf 'decision=%s|total=%s|open=%s|notify=%s|fill=%s|trees=%s\n' "$1" "$TOTAL" "$OPEN" \
            "${NOTIFY_ROWS:-}" "${SCHED_FILL:-}" "${LEASE_TREES:-}"
          printf 'room=%s|current=%s\n' "${SCHED_GATE_ROOM:-}" "$cur"
          [ -z "$TICK_GATE_KEYS" ] || printf 'gate=%s\n' "$TICK_GATE_KEYS"
          printf '%s\n' "$VERDICT_OUT" | awk -F'|' '
            $1 == "landing-verdict/v1" {
              n = ""; st = ""; ak = ""
              for (i = 2; i <= NF; i++) {
                if (index($i, "name=") == 1) n = substr($i, 6)
                else if (index($i, "state=") == 1) st = substr($i, 7)
                else if (index($i, "acked=") == 1) ak = substr($i, 7)
              }
              print n "|" st "|" ak
            }' | LC_ALL=C sort
          # A reader started without its checks: the whole line, and the ids beside it (T37; S1).
          [ -z "${US_NOTIFY_IDS:-}" ] || printf 'unchecked=%s\n' "$US_NOTIFY_IDS"
          awk '
            $1 != "poker:" { next }
            $2 == "note:" { print $3, $4, $5; next }
            $2 == "NOTIFY" && index($0, " started without its checks: ") > 0 { print; next }
            $2 ~ /^(STANDDOWN|held|GONE|GONE\?|DUPLICATE-SESSION|DUPLICATE-START|HELD|LEDGER|fill-declined|LAUNCHED|NOT-RECORDED|RANGE|NOTIFY)$/ { print $2, $3, $4 }
            # An open check is told once (wave-28 T41; D33): a new one, or one settled, moves the hash.
            $2 == "FINDING" && $6 == "check" { print $2, $3, $6 }
          ' "$TICK_BUF" | LC_ALL=C sort
        } | cksum | awk '{ print $1 "-" $2 }' )"
      fi
      # THE STORED FINGERPRINT IS THE LAST ONE A DUTY WAS JUDGED AGAINST (wave-26 T32; review-6
      # F1). A QUIET tick owes nothing, so it writes back the value it read: a status move it saw
      # first is still owed by the next tick that can owe it. Through T15 every tick wrote its own,
      # and a move first seen while the run WAITED was used up. The whole-decision hash above still
      # takes this tick's own fingerprint, so a QUIET tick over a move prints in full. With no
      # value stored yet (the first tick after an arm), the QUIET tick's own is the baseline.
      TICK_CHANGE_STORE="$TICK_CHANGE"
      if [ "$TICK_DECIDED" = QUIET ]; then
        prev="$(tick_digest_field "$TICK_DIGEST_FILE" change)"
        [ -n "$prev" ] && TICK_CHANGE_STORE="$prev"
      fi
      prev="$(tick_digest_field "$TICK_DIGEST_FILE" digest)"
      if [ -n "$TICK_DIGEST" ] && [ "$1" != DISARM ] && [ "${SCHED_OVER:-}" != yes ] \
         && [ -z "$TICK_GATE_NEW" ] && [ "$TICK_DIGEST" = "$prev" ]; then
        TICK_UNCHANGED=yes
        TICK_SINCE="$(tick_digest_field "$TICK_DIGEST_FILE" since)"
        [ -n "$TICK_SINCE" ] || TICK_SINCE="$(iso_now)"
        TICK_DUTY=none
        return 0
      fi
      TICK_SINCE="$(iso_now)"
      TICK_DUTY=none
      # THE DUTY IS PRINTED (wave-26 T32; review-6 F2). It used to live only in the digest
      # file, so the Patrol prompt asked for the refresh on a change the model could not see.
      # The prompt and the stop wall's refusal both name this line. A plan move is asked first,
      # in its own words (wave-27 T37): a status change beside it is covered by the rebuild.
      if tick_plan_moved; then
        TICK_DUTY=owed
        case "$TICK_RECONCILE" in
          step4) say "RECONCILE — the plan moved from approval into Step 4 since the last tick: TaskList, and rebuild the task list in execution order (delete every pending entry and recreate them)" ;;
          *)     say "RECONCILE — the ## Tasks table grew since the last tick: TaskList, and rebuild the task list in execution order (delete the pending entries after the new row and recreate them)" ;;
        esac
      elif [ "$TICK_DECIDED" != QUIET ] && [ "$TICK_CHANGE" != "$(tick_digest_field "$TICK_DIGEST_FILE" change)" ]; then
        TICK_DUTY=owed
        say "RECONCILE — a ## Tasks status or the ready set changed since the last tick: TaskList, and bring the task list in line with the plan"
      fi
      tick_write_orders
      return 0
    }

    # THE RANKED BAND, ONE COPY FOR BOTH ARMS THAT DECIDE (REQ-10 AC-10.2, D5; wave-26 T59). The
    # roster arm and the armed first tick both rank this tick's contributors here, so the
    # decision line agrees with what the tick printed whichever arm printed it: a first tick
    # that named a FILL decides FILL, with the same `fill=` field. The ranking and its reasons
    # are documented where the roster arm calls it.
    tick_band() {  # -> TICK_DECISION, the band left standing once tick_conclude has run
      TICK_DECISION=QUIET
      [ -n "$SD_ORDER_NAMES" ] && TICK_DECISION=STANDDOWN
      [ -n "${SCHED_FILL:-}" ] && TICK_DECISION=FILL
      [ -n "$NOTIFY_ROWS" ] && TICK_DECISION=NOTIFY
      # A PENDING GATE REQUEST IS THE THIRD CONTRIBUTOR (wave-25 T5; D7): tick_conclude raises the
      # band to NOTIFY for it, so the band is read back from there.
      tick_conclude "$TICK_DECISION"
      TICK_DECISION="$TICK_DECIDED"
    }
    # THE FILL BAND'S OWN SENTENCE. The `poker: FILL <ids>` line the duty wall reads was printed
    # by the scheduler where it was decided; this says what the decision line then says, so the
    # two channels agree on one tick (D5).
    tick_fill_sentence() { say "FILL — ${SCHED_FILL} named for dispatch; the decision line carries them."; }

    # THE STOP ORDERS THIS TICK OWES, written once the decision is known (wave-24 T7; D1, D4). An
    # unchanged tick writes none: the stop wall reads its stand-down set off this tick's orders,
    # and a turn told only "unchanged" must not be refused for a STANDDOWN it was never shown.
    # The answer the last turn gave stands until a fact moves.
    SD_ORDER_NAMES=""
    tick_write_orders() {
      local n out
      for n in $SD_ORDER_NAMES; do
        if [ -f "$ORDERS" ]; then
          out=$( cd "$REPO_REAL" 2>/dev/null || exit 9
                 CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
                 bash "$ORDERS" order "$n" --by patrol 2>&1 ) \
            || say "STANDDOWN ${n} — the order could NOT be written, so the stop gate will still ask: $(clean "$(printf '%s' "$out" | head -1)")"
        else
          say "STANDDOWN ${n} — sibling hooks/stop-orders.sh not found, so no order was written; order it yourself before stopping."
        fi
      done
      return 0
    }

    # The sweeper is this script's sibling — same resolution as hooks/landing-gate.sh's.
    SWEEPER="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/session-sweeper.sh"
    if [ ! -f "$SWEEPER" ]; then
      die "REFUSED — sibling hooks/session-sweeper.sh not found; nothing was read."
      exit 2
    fi
    # THE ORDER WRITER, resolved the same way and NOT required to exist. The tick's whole
    # value is the reading it does from the roster; a missing sibling costs the stand-down
    # its order (and says so, once, on the row it was for) rather than costing the session
    # its tick. The sweeper above is required because nothing can be decided without it.
    ORDERS="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/stop-orders.sh"

    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    ROSTER_FILE="$REPO_REAL/.bionic/tmp/roster-${SESSION_ID}.state"

    # ---------- THE LAUNCHES THE PLAN LACKS, WRITTEN BEFORE THE PLAN IS READ (wave-26 T32; D4) ----
    #
    # The launch recorder starts `launch-sync` and does not wait for it, so the tick runs the same
    # transaction before anything below reads the plan: a launch the detached call did not record
    # is recorded here (its LAUNCHED line enters this tick's output and its status this tick's
    # change fingerprint), and one that cannot be recorded prints its NOT-RECORDED line and the
    # commands to run by hand. A child process, as the recorder runs it: its refusals exit, and a
    # tick must not. It leaves a lock another writer holds to that writer.
    if [ -f "$ROSTER_FILE" ]; then
      ( cd "$REPO_REAL" && CLAUDE_CODE_SESSION_ID="$SESSION_ID" "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" launch-sync 2>&1 ) || :
    fi

    # ---------- THE LINE'S STANDING REDS AND STALLED ENTRIES, EACH TOLD ONCE (wave-28 T5; D8) ----------
    #
    # `ready` (lib/line.sh) appends `standing` when a red fails at the accepted head too, so the
    # branch's and not a row's, and `stalled` when an entry's suite twice gave no verdict and `ready`
    # exited 70. The first tick that reads one off the bound plan's landing record prints it as a note,
    # with its logs; the event line then goes into `.bionic/tmp/line-told-<sid>.state` and is never
    # printed again. A note enters the decision's hash, so the tick that tells one prints in full.
    resolve_run "$REPO_REAL" "$SESSION_ID"
    LT_TOLD="$REPO_REAL/.bionic/tmp/line-told-${SESSION_ID}.state"
    LT_REC=""
    [ -z "$POKER_RUN_PLAN" ] \
      || LT_REC="$(docs_root "$REPO_REAL" 2>/dev/null)/record/$(basename "$POKER_RUN_PLAN" .plan.md)/landing-proofs.log"
    if [ -n "$LT_REC" ] && [ -f "$LT_REC" ] && [ ! -L "$LT_TOLD" ] && tmp_dir_ok "${LT_TOLD%/*}"; then
      lt_f() { printf '%s\n' "$LT_EV" | tr '|' '\n' | sed -n "s/^$1=//p" | head -1; }   # <key> -> its value in the event
      while IFS= read -r LT_EV; do
        [ -n "$LT_EV" ] || continue
        [ -f "$LT_TOLD" ] && /usr/bin/grep -qxF -- "$LT_EV" "$LT_TOLD" && continue
        case "$LT_EV" in
          *'|ev=standing|'*) LT_H="$(lt_f head)"
            note "standing $(lt_f suite) at ${LT_H:0:12} — $(lt_f lines) failing line(s) fail at the accepted head too: a red the branch carries, not one a row added; log $(lt_f log)" ;;
          *) note "stalled $(lt_f row) — two runs ended with no verdict and no third starts; logs $(lt_f logs)" ;;
        esac
        printf '%s\n' "$LT_EV" >> "$LT_TOLD"
      done <<EOF
$(/usr/bin/grep -E '^line/v1\|ev=(standing|stalled)\|' "$LT_REC" 2>/dev/null)
EOF
    fi
    # THE RUN'S LANDING LINE (wave-28 T14; D18): the report's first line, once the record holds a landing.
    # It is printed by the exit trap after the decision and enters no hash.
    if [ -n "$LT_REC" ] && { /usr/bin/grep -q '^line/v1|ev=published|' "$LT_REC" 2>/dev/null || landing_unmeasured "$LT_REC"; }; then
      TICK_LANDINGS="$(landing_report "$LT_REC" "$REPO_REAL" no 2>/dev/null | head -1)"
    fi

    # ---------- THE GATE REQUESTS, READ ONCE (wave-25 T5, REQ-4 AC-4.3; D7) ----------
    #
    # Read here, above every arm that decides, so the armed tick before any dispatch and the
    # DISARM tick see the same requests as the full one. `gate_requests` (above) says which are
    # pending; the keys of all of them become the digest's `gate_raised=` when this tick writes
    # it, which is what makes the next tick read them as raised. No file is nothing pending.
    # A symlinked file, or one under a symlinked `.bionic/tmp`, is refused as the roster files
    # are and says so in a note; the set already raised is kept, so replacing the link with the
    # real file later does not raise them all a second time.
    TICK_GATE_FILE="$REPO_REAL/.bionic/tmp/gate-${SESSION_ID}.state"
    if [ -L "$TICK_GATE_FILE" ] || ! tmp_dir_ok "${TICK_GATE_FILE%/*}"; then
      TICK_GATE_KEYS="$(tick_digest_field "$TICK_DIGEST_FILE" gate_raised)"
      note "gate file ${TICK_GATE_FILE} is a symlink or sits under one — not read, so no reserved request is raised from it"
    elif [ -f "$TICK_GATE_FILE" ]; then
      TICK_GATE_ROWS="$(gate_requests "$TICK_GATE_FILE" "$SESSION_ID" "$(tick_digest_field "$TICK_DIGEST_FILE" gate_raised)")"
      TICK_GATE_KEYS="$(printf '%s\n' "$TICK_GATE_ROWS" | awk -F'\t' 'NF { printf "%s%s", (n++ ? "," : ""), $1 }')"
      TICK_GATE_NEW="$(printf '%s\n' "$TICK_GATE_ROWS" | awk -F'\t' '$2 == "new"')"
    fi
    # THE FIELD: how many requests this tick raises, then their categories sorted and once each,
    # `gate=2:credentials,leaves-the-machine`. The commands are on the GATE lines, not here.
    if [ -n "$TICK_GATE_NEW" ]; then
      TICK_GATE_FIELD="$(printf '%s\n' "$TICK_GATE_NEW" | awk -F'\t' '{ print $4 }' | LC_ALL=C sort -u \
        | awk -v n="$(printf '%s\n' "$TICK_GATE_NEW" | grep -c .)" '{ c = c (NR > 1 ? "," : "") $0 } END { printf "%d:%s", n, c }')"
    fi
    # THE GATE LINES, printed by whichever arm decides, after its tick_conclude: one sentence that
    # says what the turn owes, then one line per request this tick raises, asker, category and
    # command head. A request already raised prints nothing; the file still holds it.
    tick_gate_report() {
      local k st a c h
      [ -n "$TICK_GATE_NEW" ] || return 0
      say "gate act — ${TICK_GATE_FIELD%%:*} reserved request(s) bionic denied: put each GATE line below to the human once, through the human's own notify channel, and do not perform it."
      while IFS="$(printf '\t')" read -r k st a c h; do
        [ -n "$k" ] || continue
        say "GATE ${a} — ${c}: ${h}"
      done <<EOF
$TICK_GATE_NEW
EOF
      return 0
    }

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
    # THE CADENCE HALF OF THE NOTIFY DETAIL, kept apart from the duration half so each gets
    # the sentence that describes it and the machine line gets both (REQ-10 AC-10.1).
    QUIET_DETAIL=""
    # THE MET LINEAGES THIS SESSION HAS NOT CLOSED (T22, A-orch-33). `payload/scripts/lib/stop.sh`
    # used to refuse the end of a Patrol turn until the transcript showed a ListAgents call —
    # a chore demanded of the model before a gate would judge, which is the rule ADR-024
    # exists to end. The obligation behind it was real: eighteen finished agents once sat
    # idle on one panel because nobody stopped them. It is answered here instead, from the
    # roster, by the one process that already walks every row and every verdict.
    STANDDOWN_NAMES=""
    # THE NAMES THIS SESSION HAS ALREADY CLOSED, carried out of the walk (T1, D2). Two
    # readers below need it — the stand-down arm, which must not close a row twice, and the
    # DUPLICATE-START tell, which repeated for the life of the session because it applied no
    # ack filter at all. The verdict line this loop is already reading is the one place that
    # says so: the ack ledger has exactly ONE reader in the fleet and it is not this file
    # (hooks/session-sweeper.sh:817). `clean` has already folded `|` out of every name, so a
    # `|`-delimited blob cannot be forged by a roster value.
    TICK_ACKED_NAMES="|"
    # THE SWEPT SET IS READ ONCE, BEFORE THE WALK (Step-6 delta review P1). The membership
    # test below used to be `grep -F … "$ROSTER_FILE" | grep -qF …` INSIDE the per-row loop:
    # a whole-file read and two forks per MET row, on a file that grows monotonically for the
    # life of the session — O(MET x roster), and MET rows are the majority of a wave by its
    # close. One read, then an in-shell `case`, costs the same on the first row and nothing on
    # the rest. Adds no `jq` call and no transcript read: the §19i pin is untouched.
    #
    # THE MATCH STAYS LITERAL. `grep -qF` treated the name as a fixed string; a `case` pattern
    # does too as long as the variable is QUOTED inside it, which is what keeps a roster name
    # carrying `*` or `?` from globbing against this blob.
    SWEPT_ALL="$(grep -F "$SWEPT_SCHEMA|" "$ROSTER_FILE" 2>/dev/null)"
    # The names of the rows the verdict leaves open, kept so the live set can trim them
    # AFTER this walk rather than inside it: one transcript resolution per tick, not one
    # per row, and the roster count survives as its own number (S19).
    OPEN_NAMES=""
    # THE FILL'S OCCUPANCY IS THE STOP WALL'S PREDICATE (wave-19 REQ-5, ADR-034 d2; audit V-2,
    # T2d): every roster row of this session that is NOT ACKED. `OPEN` above is a different
    # number with a different job. It drops MET/WAIVED rows, it is trimmed by liveness, and it
    # decides `open=`, QUIET and DISARM. The fill used to be sized from it, and on the
    # end-of-batch shape (a MET row whose agent is still idle on the panel, so no ack yet) the
    # tick's gap was one wider than the wall's: writers=2, one such row, two ready rows, and the
    # tick filled two where payload/scripts/lib/stop.sh demands one. The names are collected
    # here, off the verdict line (which folds the roster by name and filters by session exactly
    # as the wall's awk does), and counted AFTER the stand-down arm below has written this
    # tick's own acks. So a MET row gone from a fresh panel is closed and not counted, and a
    # MET row still listed is counted until its ack.
    TICK_UNACKED_NAMES=""
    # THE NAMES A GONE-AGENT REPORT CAN NAME (wave-19 audit V-2 delta review R2-6). An UNMET,
    # STILL-LIVE or AMBIGUOUS row that is unacked and whose agent a fresh panel does not list
    # now holds a `TICK_OCCUPIED` slot (A-T2.13) with nothing pointing at the closer T1e
    # built. This is the candidate set the stand-down arm below checks against the panel it
    # already warms for `$STANDDOWN_NAMES`; it names MET rows only, so the two sets never
    # overlap. The report never acks: the tick has no authority over an UNMET verdict (ADR-003),
    # and closing one is `stop-orders.sh stopped`'s job alone (T1e).
    GONE_CANDIDATE_NAMES=""
    # THE STATE AND DETAIL RIDE ALONG (audit V3-2). `stopped` does not accept every row in
    # the candidate set above: it refuses AMBIGUOUS unconditionally and refuses a STILL-LIVE
    # row whose own detail names a claimed process pattern still matching a live process
    # (hooks/stop-orders.sh:618-663, T1g/A-T1.13 — not exposed as a sourceable function, so
    # its acceptance predicate is mirrored below rather than re-derived; A-T2.18). The report
    # line has to know which shape a row is BEFORE it prints, so `$RSTATE` and the row's
    # `detail=` are captured here, one newline-joined `name|state|detail` record per
    # candidate, in the same pass that already reads `$LINE` for this row — never a second
    # parse of `$VERDICT_OUT` later.
    GONE_CANDIDATE_INFO=""
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
      if [ "$(line_field "$LINE" acked)" = "yes" ]; then
        TICK_ACKED_NAMES="${TICK_ACKED_NAMES}$(clean "$RNAME")|"
        continue
      fi
      TICK_UNACKED_NAMES="${TICK_UNACKED_NAMES}$(clean "$RNAME")
"

      case "$RSTATE" in
        MET|WAIVED)
          # EVERY MET ROW IS A CANDIDATE, SWEPT OR NOT (T10, A-orch-20). A `landing-swept/v1`
          # marker records that a landing was SEEN, not that the agent LEFT: for a teammate it
          # is written at its own SubagentStop — the moment it reports — while it is still on
          # the panel. Excluding a swept name here made the common shape at the end of a batch
          # (every writer landed, still idle on the panel) print nothing, which is the 1.7.1
          # pile-up this arm exists to end. Presence is the panel's fact alone (spec
          # §Assumptions), and the marker never closes a name either: only the ack does
          # (wave-19 T1, ADR-034 d1), which the close below writes when a fresh panel shows
          # the agent gone.
          if [ "$RSTATE" = "MET" ]; then
            STANDDOWN_NAMES="${STANDDOWN_NAMES}${STANDDOWN_NAMES:+ }$(clean "$RNAME")"
          fi
          ;;                                  # closed — not open
        *)          OPEN=$((OPEN + 1))        # STILL-LIVE, UNMET, AMBIGUOUS — open
                    OPEN_NAMES="${OPEN_NAMES}${RNAME}
"
                    # A candidate for the GONE report (R2-6): unacked (this branch is only
                    # reached past the acked-row `continue` above) and not MET/WAIVED, so a
                    # fresh panel showing it gone is a row nothing has ever named.
                    GONE_CANDIDATE_NAMES="${GONE_CANDIDATE_NAMES}${GONE_CANDIDATE_NAMES:+ }$(clean "$RNAME")"
                    # `$RSTATE` is one of STILL-LIVE/UNMET/AMBIGUOUS here (this branch's own
                    # `case`), never `|`-bearing. `clean` on the detail strips any `|` (and
                    # tab/newline) a brief's free text could otherwise smuggle in, which is
                    # what keeps this record's third field from being mistaken for a fourth.
                    GONE_CANDIDATE_INFO="${GONE_CANDIDATE_INFO}$(clean "$RNAME")|${RSTATE}|$(clean "$(line_field "$LINE" detail)")
"
                    ;;
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

      # ---- ARM 1: past its declared DURATION. Unchanged arithmetic, restructured off
      # `continue` so that an unreadable duration no longer skips the row entirely — the
      # cadence read below is a second, independent question about the same row, and a row
      # whose `duration=` will not parse is exactly the row most worth asking it about.
      ROW_OVERDUE=no
      DUR_RAW="$(line_field "$ROW_LINE" duration)"
      LAUNCHED_RAW="$(line_field "$ROW_LINE" launched_at)"
      DUR_S="$(parse_seconds "$DUR_RAW")" || DUR_S=""
      LE="$(iso_epoch "$LAUNCHED_RAW")"
      if [ -n "$DUR_S" ] && [ -n "$LE" ]; then
        AGE=$(( $(now_epoch) - LE ))
        if [ "$AGE" -gt "$DUR_S" ]; then
          ROW_OVERDUE=yes
          NOTIFY_ROWS="${NOTIFY_ROWS}${NOTIFY_ROWS:+,}$(clean "$RNAME")"
          NOTIFY_DETAIL="${NOTIFY_DETAIL}${NOTIFY_DETAIL:+; }$(clean "$RNAME"): $(line_field "$LINE" detail) (elapsed ${AGE}s past declared duration \"$DUR_RAW\" (${DUR_S}s))"
        fi
      fi

      # ---- ARM 2: QUIETER THAN ITS OWN DECLARED CADENCE (REQ-10 AC-10.1; D9). The read the
      # Patrol prompt has promised since wave-01 and no code took: the row's `progress=` and
      # `cadence=` through `observe_class`, with the mtime that decided it printed beside the
      # verdict so the reader can check it. A row is named ONCE however many arms found it.
      if row_quiet "$ROW_LINE" "$(now_epoch)"; then
        [ "$ROW_OVERDUE" = yes ] \
          || NOTIFY_ROWS="${NOTIFY_ROWS}${NOTIFY_ROWS:+,}$(clean "$RNAME")"
        QUIET_DETAIL="${QUIET_DETAIL}${QUIET_DETAIL:+; }$(clean "$RNAME"): no line for ${TICK_QUIET_AGE}s against cadence ${TICK_QUIET_CAD}s (${TICK_QUIET_CHANNEL}, mtime ${TICK_QUIET_MTIME})"
      fi
    done <<EOF
$VERDICT_OUT
EOF

    # ---------- THE PANEL IS REFRESHED FROM THE ROSTER, NOT FROM A TOOL CALL (T22) -------
    #
    # One line per MET lineage still on this session's register. It is a TELL: the tick holds
    # no authority (ADR-003), stops nothing, and refuses nothing. What it replaces is
    # `stop_patrol_duties`'s ListAgents duty, which asked the model to look at a panel so
    # that a gate would let the turn end — and never named a single thing to do about what
    # it saw.
    #
    # THE ARM MOVED DOWN (T1, D1/D2). It used to print here, from the roster alone, and say
    # `TASKSTOP <name>`. The roster alone cannot tell the two cases apart: a MET row whose
    # agent is STILL LISTED is somebody's TaskStop to make, and a MET row whose agent is GONE
    # is a row nothing will ever close — the adopted-MET case, named on every tick forever
    # until a human typed an `ack`. Both readings need the PANEL, which is warmed a few lines
    # below, so the decision is taken there and `$STANDDOWN_NAMES` is what carries the
    # candidates to it.

    # ---------- THE LIVE SET TRIMS `open=` AND THE FILL (S19, auditor F-14) ----------
    #
    # THE DEFECT. The spec's ownership table names this tick a rendering surface of the LIVE
    # AGENT SET; it read no such thing. It counted roster rows by sweeper verdict, while the
    # dispatch wall counts a row open only while the harness still calls its agent live
    # (AC-27). One row, two answers: a finished-but-unstopped teammate is NOT open to the
    # wall and WAS open here, so the Patrol could print a FILL the wall was about to refuse
    # — or withhold one it would have allowed. The number below is now the wall's number,
    # because both sides ask the same function.
    #
    # THE TICK DECIDES AND NEVER WRITES. No roster row, marker or verdict moves here: the
    # row stays exactly as the sweeper left it, still counted in `total=`, still eligible to
    # NOTIFY when it is overdue. Only the arithmetic this tick prints is trimmed. That is
    # what keeps the roster readable by every other consumer (D0: one owner per liveness
    # truth, and the ROSTER's owner is not this file).
    #
    # ONLY WHEN THERE IS SOMETHING TO TRIM. A roster with no open row has nothing whose
    # openness a live answer could settle — the same reasoning the dispatch wall's empty-
    # roster arm takes — so the reader is not called and no line is printed. A fallback
    # sentence on every quiet tick of every session is noise a reader learns to skip.
    #
    # ON A STALE OR MISSING ANSWER THE ROSTER COUNT STANDS, and this is deliberately NOT
    # the wall's refuse-and-name-the-fix behaviour. The Patrol's prompt runs this tick
    # BEFORE any ListAgents, so a refusal here would refuse the first tick of every session
    # — a wall that fires on the healthy path is not a wall. The tick holds no authority
    # (ADR-003): it prints a line and the operator acts. The ENFORCEMENT is the dispatch
    # wall, which does refuse on a stale read, so the honest thing here is to say which
    # number this is and point at the gate that will insist.
    OPEN_ROSTER="$OPEN"
    TICK_LIVE_STATE=""
    # RESOLVED AT MOST ONCE PER TICK, by whichever arm needs it first: the trim below, or the
    # stand-down arm after it. A tick with nothing open and nothing MET reads no transcript.
    TICK_TR=""
    if [ "$OPEN_ROSTER" -gt 0 ]; then
      TICK_TR="$(session_transcript "$SESSION_ID")" || TICK_TR=""
      if [ -z "$TICK_TR" ]; then
        TICK_LIVE_STATE="none"
      else
        TICK_OPEN_LIVE=0
        # PRIME THE READER'S PER-PROCESS PARSE, ONCE, IN THIS SHELL (Step-6 review P-4, the
        # tick half of the finding the budget wall's loop already answers). `live_agents`
        # memoizes its parse in shell variables keyed on the transcript's path, size and
        # mtime — but the per-row call below runs inside a command substitution, and a
        # subshell INHERITS its parent's variables while its own writes die with it. So the
        # first row would warm a cache nobody sees and every open row would pay a full
        # parse: two whole-file `jq` passes and nine spawns. Measured on this machine, one
        # tick over twelve open rows and a 4.1 MB transcript ran jq 24 times.
        #
        # LAZILY, INSIDE THE `OPEN_ROSTER > 0` ARM, for the same reason the wall does it
        # lazily: a roster with nothing open reads the transcript zero times. Its answer is
        # discarded — this line is a cache fill, and every row's verdict is the predicate's.
        live_agents "$TICK_TR" >/dev/null 2>&1 || :
        while IFS= read -r TICK_NAME; do
          [ -n "$TICK_NAME" ] || continue
          # The predicate prints nothing on stdout, so this capture is the reader's one
          # contract line — `live-agents: <state> age=<n|none>` — and nothing else.
          TICK_LRC=0
          TICK_LERR=$( { live_row_open "$TICK_TR" "$TICK_NAME"; } 2>&1 ) || TICK_LRC=$?
          case "$TICK_LRC" in
            0) TICK_OPEN_LIVE=$(( TICK_OPEN_LIVE + 1 )) ;;
            1) : ;;
            *) # 3 STALE / 4 NONE. Freshness is a property of the TRANSCRIPT, not of any
               # one name, so every remaining row would read the same way: stop asking.
               TICK_LIVE_STATE="${TICK_LERR#live-agents: }"
               TICK_LIVE_STATE="${TICK_LIVE_STATE%% *}"
               break ;;
          esac
        done <<EOF
$OPEN_NAMES
EOF
        [ -n "$TICK_LIVE_STATE" ] || OPEN="$TICK_OPEN_LIVE"

        # ---------- THE DUPLICATE-SESSION TELL (AC-4.3, T21) ----------
        #
        # THE CLAIM WAS PROSE ONLY. skills/canonical-sdlc/dispatch.md promises "A listed agent
        # with NO ledger row is surfaced as a duplicate-session tell, never silently stopped",
        # and nothing computed it. Chris, 2026-09-14 (A-orch-29): "Add a test" — the tell
        # becomes tick machinery, with its own test.
        #
        # THE QUESTION, for every name THIS session's ListAgents answer calls live: does ANY
        # roster under this PROJECT's `.bionic/tmp` — not only this session's own — carry a row
        # for it, by `name=` or `agent_id=` (payload/scripts/lib/roster.sh)? A live agent no
        # roster remembers is either another session's dispatch (never rostered here) or a
        # resumed copy of a finished one — either way this session cannot tell which, so it
        # NAMES the gap and stops there: no stop, no roster write, no effect on FILL, QUIET or
        # NOTIFY. `ANY roster`, not `open`: a landed/MET row still proves the wall once knew the
        # agent, so a closed row clears the name exactly as an open one would.
        #
        # THE ALREADY-WARMED SLOT, NOT A SECOND CALL (S19I's own pin, P-4). The priming line
        # above filled `agents.sh`'s one-process cache directly (no subshell), and the loop
        # that follows it only ever reads that cache through subshelled predicate calls whose
        # writes die with them — so the cache this process holds is still exactly what the
        # priming line put there. A second call to `live_agents "$TICK_TR"` here would normally
        # be a cache HIT and cost nothing — but S19I's own anti-vacuity arm proves the opposite
        # case by deleting the priming line and nothing else, and against THAT doctored copy a
        # second `live_agents` call would pay its own full parse (the row loop's cache writes
        # are already lost to their subshells, so nothing upstream would have warmed it either)
        # and move the "twelve, not two" pin it exists to hold. Reading the cache SLOT directly
        # copies neither cost: a real tick sees exactly what the priming line read (correct data,
        # zero extra jq calls), and a doctored one — where nothing ever warmed it — sees empty
        # (no tell, and still zero extra calls; S19I is not testing this feature).
        #
        # ONLY WHEN THE ANSWER CARRIES A SET. NONE reads as an empty set here exactly as it
        # does for the trim above (AC-4.1: the tick never demands a ListAgents call), and a
        # STALE answer still names a real — if possibly outdated — live set worth surfacing,
        # the same asymmetry `live_agents`'s own header documents.
        TICK_DUP_SET="$_LA_CACHE_OUT"
        if [ -n "$TICK_DUP_SET" ]; then
          while IFS='|' read -r TICK_DUP_NAME TICK_DUP_TYPE TICK_DUP_STATUS; do
            [ -n "$TICK_DUP_NAME" ] || continue
            TICK_DUP_FOUND=0
            for TICK_DUP_RF in "$REPO_REAL/.bionic/tmp"/roster-*.state; do
              [ -f "$TICK_DUP_RF" ] || continue
              # Symlinks are not followed, the same posture every other .bionic/tmp reader
              # in this file takes.
              [ -L "$TICK_DUP_RF" ] && continue
              if grep -qF "|name=${TICK_DUP_NAME}|" "$TICK_DUP_RF" 2>/dev/null \
                 || grep -qF "|agent_id=${TICK_DUP_NAME}|" "$TICK_DUP_RF" 2>/dev/null; then
                TICK_DUP_FOUND=1
                break
              fi
            done
            [ "$TICK_DUP_FOUND" -eq 1 ] \
              || say "DUPLICATE-SESSION ${TICK_DUP_NAME} — live here, on no roster of this project (another session's dispatch or a resumed copy); never stop it silently"
          done <<EOF
$TICK_DUP_SET
EOF
        fi
      fi
      if [ -n "$TICK_LIVE_STATE" ]; then
        say "live set $TICK_LIVE_STATE — open= counted from the roster"
      elif [ "$OPEN" -ne "$OPEN_ROSTER" ]; then
        # THE TRIM IS SAID OUT LOUD, or `open=0` over a roster carrying two unmet
        # contracts is a number with no story. Only when it actually moved: a tick whose
        # live set agrees with its roster has nothing to explain.
        say "live set fresh — ${OPEN_ROSTER} open row(s) on this roster, ${OPEN} still live; open= is sized from the live set, the fill from every row not yet acked"
      fi
    fi

    # ---------- THE DUPLICATE-START TELL (T22 row (d), delta review C2) ----------
    #
    # hooks/execution-recorder.sh journals `status=duplicate-start` when one agent id starts a
    # SECOND time in this session — a resumed copy working a contract the first process still
    # holds. That row was accepted as the answer BECAUSE a SubagentStart hook cannot block
    # (A-T22.4): the door that closes is the dispatch wall, one event earlier, and the record
    # exists so that somebody SEES the case the door was not asked about. Until this block
    # nothing read the field: the DUPLICATE-SESSION tell above asks a different question — a
    # live name NO roster of this project carries — and a duplicate start is carried by `name=`
    # AND by `agent_id=`, so that tell is silent on exactly this row.
    #
    # ROSTER-ONLY, AND OUTSIDE THE LIVE-SET ARM. The fact is on disk. A tell that needed a
    # ListAgents answer, or an open row to trim, would go quiet in precisely the degraded
    # session that produces the row — one that just lost its agent table across a `/clear`.
    #
    # ONE LINE PER ROW, NOT PER NAME: two duplicate starts are two events, and collapsing them
    # would hide the second. It is a TELL and nothing else — no stop, no roster write, no
    # effect on FILL, QUIET, NOTIFY or `open=`.
    #
    # THE TWO MARKS THAT CLOSE A ROW CLOSE THIS TELL TOO (T1, D2). Until 1.8.0 this loop
    # applied NO ack filter and NO swept filter, and the roster is append-only with nothing
    # that ever supersedes the row — so the tell repeated on every tick for the life of the
    # session, long after the duplicate process was gone, and no act available to the reader
    # could quiet it. It is the same closing rule the rest of this file already keeps
    # (session-poker.sh: "A ROW IS CLOSED BY A LANDED MARKER OR BY AN ACK, and by nothing
    # else"), applied here for the first time. The stand-down arm below writes that ack when
    # the panel shows the agent gone, so the ordinary life of a duplicate start is now: told
    # once, closed in the same tick, silent after it.
    DUP_START_NAMES="|"
    if [ -f "$ROSTER_FILE" ] && [ ! -L "$ROSTER_FILE" ]; then
      DUP_START_ROWS="$(grep -F "|status=duplicate-start|" "$ROSTER_FILE" 2>/dev/null)"
      if [ -n "$DUP_START_ROWS" ]; then
        while IFS= read -r DS_LINE; do
          # The schema prefix is checked here as every other roster reader in this file checks
          # it: `|status=` is not unique to a roster-state row by construction, only in practice.
          case "$DS_LINE" in "roster-state/v1|"*) : ;; *) continue ;; esac
          DS_NAME="$(clean "$(line_field "$DS_LINE" name)")"
          [ -n "$DS_NAME" ] || continue
          case "$TICK_ACKED_NAMES" in *"|${DS_NAME}|"*) continue ;; esac
          case "$SWEPT_ALL" in *"|name=${DS_NAME}|"*) continue ;; esac
          # ONE LINE PER ROW, NOT PER NAME (unchanged): two duplicate starts are two events.
          # The CANDIDATE set below is per NAME, because an ack closes a name and writing two
          # for one row would be two ledger lines saying the same thing.
          say "DUPLICATE-START ${DS_NAME} — a second start under an id that already has a live row; the dispatch wall is the door that closes"
          case "$DUP_START_NAMES" in
            *"|${DS_NAME}|"*) : ;;
            *) DUP_START_NAMES="${DUP_START_NAMES}${DS_NAME}|" ;;
          esac
        done <<EOF
$DUP_START_ROWS
EOF
      fi
    fi
    [ "$DUP_START_NAMES" = "|" ] && DUP_START_NAMES=""

    # ---- BEGIN a reader started without its checks (wave-27 T38; review pass 31 F2) ----
    # hooks/execution-recorder.sh appends `start-unchecked/v1|event=start|…` to the roster when a
    # reader's start could not be placed and its candidates carry different `questions=`: no
    # checks file was pushed, and its own log line is stderr nobody reads. The tick says so ONCE
    # per agent id and writes `event=told` beside it, so the orchestrator stops that reader and
    # dispatches it again. Nothing else: no stop, no ack.
    # THE LINE IS HASHED WHOLE, AND TOLD ONLY ONCE PRINTED (wave-27 T37; review pass 36 S1). Under
    # its kind alone every such line hashed as `NOTIFY — a`, so a second reader's line on a later
    # tick left the decision unchanged, was dropped, and was still marked told. Now `tick_conclude`
    # hashes the whole line and the agent ids in US_NOTIFY_IDS (two readers of one role and one
    # candidate set print the same words), and `event=told` waits in US_TOLD_PENDING for the exit
    # trap, which writes it only when it prints the buffer. Unbuffered, the line is out already.
    # A told line ends at its id, so the id is matched at a line end as well as before a `|`.
    US_NOTIFY_IDS=""; US_TOLD_PENDING=""
    if [ -f "$ROSTER_FILE" ] && [ ! -L "$ROSTER_FILE" ]; then
      US_TOLD="$(grep -F 'start-unchecked/v1|event=told|' "$ROSTER_FILE" 2>/dev/null)"$'\n'
      while IFS= read -r US_LINE; do
        case "$US_LINE" in "start-unchecked/v1|event=start|"*) : ;; *) continue ;; esac
        US_AID="$(line_field "$US_LINE" agent_id)"
        [ -n "$US_AID" ] || continue
        case "$US_TOLD" in *"|agent_id=${US_AID}|"*|*"|agent_id=${US_AID}"$'\n'*) continue ;; esac
        say "NOTIFY — a $(clean "$(line_field "$US_LINE" role)") started without its checks: candidates $(clean "$(line_field "$US_LINE" candidates)" | sed 's/,/, /g')"
        US_NOTIFY_IDS="${US_NOTIFY_IDS:+$US_NOTIFY_IDS,}${US_AID}"
        US_TOLD_LINE="$(printf 'start-unchecked/v1|event=told|at=%s|session=%s|agent_id=%s' "$(iso_now)" "$SESSION_ID" "$US_AID")"
        if [ -n "$TICK_BUF" ]; then
          US_TOLD_PENDING="${US_TOLD_PENDING}${US_TOLD_LINE}"$'\n'
        else
          printf '%s\n' "$US_TOLD_LINE" >> "$ROSTER_FILE" 2>/dev/null
        fi
        US_TOLD="${US_TOLD}|agent_id=${US_AID}|"
      done < <(grep -F 'start-unchecked/v1|event=start|' "$ROSTER_FILE" 2>/dev/null)
    fi
    # ---- END a reader started without its checks ----

    # ---------- THE STAND-DOWN: the tick names it, and writes the order (T1; D1, D2) ------
    #
    # THE DEFECT IT ENDS. `TASKSTOP <name>` was a tell and nothing else. The reader who acted
    # on it then met the stop gate, which refuses a stop of a live agent whose contract it
    # cannot see discharged — so the instruction the Patrol printed was routinely refused by
    # the wall one turn later, and the operator learned to ack rows by hand instead. Worse,
    # the tell could not tell a stoppable row from a moot one: an ADOPTED MET row is never
    # swept by anything (adopt_fold excludes MET names, the Stop-sweep skips teammate rows,
    # and the adopted agent's SubagentStop belongs to the session that launched it), so it
    # was named on every tick, forever, for an agent that had been gone for hours.
    #
    # THE PANEL IS WHAT SEPARATES THEM, and it is the fact this tick already holds — read
    # alone, never stood in for by the `landing-swept/v1` marker (T10, A-orch-20): that marker
    # records a landing SEEN, and for a teammate it is written at its own SubagentStop while it
    # is still on the panel, so "swept" is not "gone".
    #
    #   MET, STILL LISTED -> somebody has to stop it, swept marker or not. The tick says so by
    #     name AND writes the stop order (hooks/stop-orders.sh order <name> --by patrol), so the
    #     TaskStop that answers is not refused by the stop gate. `by=patrol` is the honest
    #     label: an order used to mean "a human said stop" and now means "a human or a
    #     verified landing said stop" (D1).
    #   MET, NOT LISTED, already carrying a `landing-swept/v1` marker -> the row is closed
    #     already; a second closing act would be a ledger line that says nothing new. Nothing
    #     is printed and nothing is acked (A-T1.9, extended: the predicate that matters is
    #     ABSENT, not unswept).
    #   MET, NOT LISTED, no marker, or a `duplicate-start` row whose agent is gone -> there is
    #     nobody to stop and no prior close on record. The row is moot and the world says so,
    #     so the tick closes it the way a human would: `session-sweeper.sh ack <name> --by
    #     patrol --reason moot-and-gone` (D2). Nothing is printed — a stand-down tell for an
    #     agent that does not exist is the noise this arm exists to remove — and the evidence
    #     is the ledger line, which names the author and what it was read off.
    #
    # THE TICK STILL STOPS NOTHING (ADR-003, unchanged). An order is a permission and an ack
    # is a bookkeeping fact; neither ends a process. The one act this arm performs on a
    # RUNNING agent is to make the operator's stop legal.
    #
    # AN UNKNOWN PANEL IS NOT AN EMPTY ONE. With no usable answer (`none` — the state of
    # every session before its first ListAgents) the tick does NEITHER thing: it neither
    # names a row for a stop it cannot justify nor closes one on evidence it does not have.
    #
    # FRESH ONLY (A-orch-31, T6). This arm used to take the same FRESH/STALE asymmetry the
    # read-only DUPLICATE-SESSION tell above takes — "a stale answer still names a real, if
    # slightly old, set of agents" — but that reasoning does not survive contact with a WRITE.
    # Measured 20:55Z: a STALE reading (the panel's last-known answer, not a fresh one) still
    # named a MET row and wrote a SECOND stop order for an agent the Patrol's own prior order
    # had already had stopped eighteen minutes earlier. A tell can afford to be a little old;
    # an order and an ack cannot — both are acts this arm cannot take back. So STALE now reads
    # the same as NONE: the arm defers rather than guesses, naming nothing, ordering nothing,
    # acking nothing, and saying once that the next tick's fresh ListAgents will decide.
    TICK_ACKED_NOW="|"
    if [ -n "$STANDDOWN_NAMES" ] || [ -n "$DUP_START_NAMES" ] || [ -n "$GONE_CANDIDATE_NAMES" ]; then
      # THE ALREADY-WARMED PARSE, or one read of our own — never a second parse of a
      # transcript this tick has already read. `live_agents` memoizes per process on the
      # transcript's path, size and mtime, and the trim above primes it IN THIS SHELL, so on
      # a roster with open rows the call below is a cache hit costing nothing. On a roster
      # whose every row is MET (`OPEN_ROSTER = 0`, the common shape at the end of a batch)
      # the trim never ran and this is the tick's one and only parse.
      [ -n "$TICK_TR" ] || TICK_TR="$(session_transcript "$SESSION_ID")" || TICK_TR=""
      SD_PANEL=""; SD_PANEL_KNOWN=0
      if [ -n "$TICK_TR" ]; then
        SD_LRC=0
        live_agents "$TICK_TR" >/dev/null 2>&1 || SD_LRC=$?
        case "$SD_LRC" in
          0)
            SD_PANEL_KNOWN=1
            # The cache SLOT, read directly for the reason the DUPLICATE-SESSION arm states
            # above it: a second call would be a hit on a real tick and a full parse against
            # §19i's doctored copy, which is not this arm's property to move.
            while IFS='|' read -r SD_PN SD_PT SD_PS; do
              [ -n "$SD_PN" ] || continue
              SD_PANEL="${SD_PANEL}${SD_PN}|"
            done <<EOF
$_LA_CACHE_OUT
EOF
            [ -n "$SD_PANEL" ] && SD_PANEL="|${SD_PANEL}"
            ;;
        esac
      fi

      if [ "$SD_PANEL_KNOWN" -eq 1 ]; then
        # ONE ACK PER NAME PER TICK. A name can be a MET candidate and a duplicate-start row
        # at once; two ledger lines would say the same thing twice.
        SD_CLOSED="|"
        for SD_NAME in $STANDDOWN_NAMES; do
          case "$SD_PANEL" in
            *"|${SD_NAME}|"*)
              # A HELD ROW IS ANSWERED ALREADY (wave-24 T7; D1, ADR-041 d1). Its latest row
              # carries the orchestrator's `held=<at> <reason> fp=<fingerprint>`; while the
              # fingerprint computed now is the one recorded, the tick prints the hold and writes
              # no order. A changed fingerprint falls through to the stand-down, writing nothing
              # to void it: the next `hold` is a new answer to new facts.
              SD_ROW="$(grep -F "roster-state/v1|" "$ROSTER_FILE" 2>/dev/null \
                | grep -F "|name=${SD_NAME}|" | tail -1)"
              SD_HELD="$(line_field "$SD_ROW" held)"
              if [ -n "$SD_HELD" ] && [ "${SD_HELD##* fp=}" != "$SD_HELD" ] \
                 && [ "${SD_HELD##* fp=}" = "$(hold_fingerprint "$SD_ROW" "$REPO_REAL" "$TICK_TR")" ]; then
                SD_HELD_REST="${SD_HELD#* }"
                say "held ${SD_NAME} since ${SD_HELD%% *} — ${SD_HELD_REST% fp=*}"
                continue
              fi
              say "STANDDOWN ${SD_NAME} — contract MET and the agent is still on the panel; TaskStop it (the order is written), or keep it up with: bash ${POKER_WORD} hold ${SD_NAME} ${HOLD_REASON_SLOT}"
              SD_ORDER_NAMES="${SD_ORDER_NAMES}${SD_ORDER_NAMES:+ }${SD_NAME}"
              ;;
            *)
              case "$SD_CLOSED" in *"|${SD_NAME}|"*) continue ;; esac
              SD_CLOSED="${SD_CLOSED}${SD_NAME}|"
              # THE ACK IS THE CLOSE (wave-19 T1; D2, ADR-034 d1). Skipped only for a name the
              # ledger already closed — the verdict walk records those in TICK_ACKED_NAMES —
              # never for a `landing-swept/v1` marker: the marker says a landing was SEEN, and
              # skipping on it left every writer that declared an artifact and reported open for
              # the life of the session (ideas row 16; R1 F1). This branch runs only under a
              # FRESH panel (SD_PANEL_KNOWN=1 above) that does not list the name.
              case "$TICK_ACKED_NAMES" in *"|${SD_NAME}|"*) continue ;; esac
              # THE REASON SAYS WHAT CLOSED IT. A row that declared a deliverable and met it
              # LANDED; a row that declared nothing stats MET for want of anything to hold it
              # to, and is closed only because it is moot and gone. Read off the row's latest
              # contract (schema-filtered: a marker also carries `|name=`), once per close —
              # a name reaches here at most once in its life, so this is no per-tick walk.
              SD_REASON=moot-and-gone
              SD_ROW="$(grep -F "roster-state/v1|" "$ROSTER_FILE" 2>/dev/null \
                | grep -F "|name=${SD_NAME}|" | tail -1)"
              [ -n "$(line_field "$SD_ROW" deliverable)" ] && SD_REASON=landed
              if SD_OUT=$( cd "$REPO_REAL" 2>/dev/null || exit 9
                           CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
                           bash "$SWEEPER" ack "$SD_NAME" --by patrol --reason "$SD_REASON" 2>&1 ); then
                TICK_ACKED_NOW="${TICK_ACKED_NOW}${SD_NAME}|"
              else
                say "NOTIFY ${SD_NAME} — contract MET, the agent is gone, and the row could NOT be closed: $(clean "$(printf '%s' "$SD_OUT" | head -1)")"
              fi
              ;;
          esac
        done
        SD_DUPS="${DUP_START_NAMES}"
        SD_DUPS="${SD_DUPS//|/ }"
        for SD_NAME in $SD_DUPS; do
          case "$SD_PANEL" in *"|${SD_NAME}|"*) continue ;; esac
          case "$SD_CLOSED" in *"|${SD_NAME}|"*) continue ;; esac
          SD_CLOSED="${SD_CLOSED}${SD_NAME}|"
          if SD_OUT=$( cd "$REPO_REAL" 2>/dev/null || exit 9
                       CLAUDE_CODE_SESSION_ID="$SESSION_ID" \
                       bash "$SWEEPER" ack "$SD_NAME" --by patrol --reason moot-and-gone 2>&1 ); then
            TICK_ACKED_NOW="${TICK_ACKED_NOW}${SD_NAME}|"
          else
            say "NOTIFY ${SD_NAME} — a duplicate start whose agent is gone could NOT be closed: $(clean "$(printf '%s' "$SD_OUT" | head -1)")"
          fi
        done

        # THE GONE REPORT (wave-19 audit V-2 delta review R2-6). An unacked, not-MET/WAIVED
        # row whose agent this fresh panel does not list now holds a `TICK_OCCUPIED` slot
        # (A-T2.13) with nothing pointing at the fix: T1e's `stopped` close. This is a
        # NOTIFY-band report only — never an ack, never an order — because the tick has no
        # authority to decide an UNMET verdict is done (ADR-003); closing one is the human
        # verb's job alone. Printed in the same place the STANDDOWN lines print, so it never
        # changes what this tick decided (QUIET stays QUIET; a FILL sized before this point
        # is unaffected).
        #
        # THE LINE NAMES A VERB THAT WILL RUN (audit V3-2). `GONE_CANDIDATE_NAMES` covers
        # STILL-LIVE, UNMET and AMBIGUOUS alike, but `stopped` does not accept all three: it
        # refuses AMBIGUOUS unconditionally, and refuses a STILL-LIVE row whose own detail
        # names a claimed process pattern still matching a live process — a fact about a real
        # OS process the panel cannot speak to (hooks/stop-orders.sh:618-663, T1g/A-T1.13).
        # `stopped` is not exposed as a sourceable predicate (A-T2.18), so its acceptance
        # rule is mirrored here rather than re-derived, kept beside this comment so the two
        # copies are found together. A row the verb WILL close prints the verdict it actually
        # holds (never a hardcoded "UNMET") and the runnable command; a row the verb WILL
        # REFUSE prints `GONE?` instead, naming the verdict and the refusal reason, so the
        # operator is told rather than misdirected into a command that fails.
        while IFS='|' read -r SD_GNAME SD_GSTATE SD_GDETAIL; do
          [ -n "$SD_GNAME" ] || continue
          case "$SD_PANEL" in *"|${SD_GNAME}|"*) continue ;; esac
          SD_REFUSE=0
          SD_WHY=""
          SD_VERDICT="$SD_GSTATE"
          case "$SD_GSTATE" in
            UNMET)
              SD_VERDICT="UNMET"
              ;;
            FOLLOW-UP)
              # MET, with a message the agent never answered (wave-20 T9, Δ8): gone from a
              # fresh panel, the reply cannot come, and `stopped` closes it `landed`.
              SD_VERDICT="FOLLOW-UP (met; the follow-up went unanswered)"
              ;;
            STILL-LIVE)
              if grep -q 'claimed process pattern' <<< "$SD_GDETAIL"; then
                SD_REFUSE=1
                SD_WHY="a claimed process pattern still matches a live process; the panel showing it gone does not close this on its own"
              else
                SD_AGE="$(printf '%s' "$SD_GDETAIL" | grep -oE 'last changed [0-9]+s ago' | grep -oE '[0-9]+')"
                SD_CAD="$(printf '%s' "$SD_GDETAIL" | grep -oE '\([0-9]+s\)' | tr -d '()s')"
                SD_VERDICT="STILL-LIVE (progress ${SD_AGE:-?}s old, cadence ${SD_CAD:-?}s)"
              fi
              ;;
            *)
              # AMBIGUOUS — `stopped`'s verdict-state `case` refuses it unconditionally,
              # before it ever reads a panel (hooks/stop-orders.sh:618-630).
              SD_REFUSE=1
              SD_WHY="two or more contracts share this name; stopped always refuses ${SD_GSTATE}"
              ;;
          esac
          if [ "$SD_REFUSE" -eq 1 ]; then
            say "GONE? ${SD_GNAME} — ${SD_VERDICT} and absent from a fresh panel; stopped will refuse it: ${SD_WHY}"
          else
            say "GONE ${SD_GNAME} — ${SD_VERDICT} and absent from a fresh panel; close it with: bash ${ORDERS} stopped ${SD_GNAME}"
          fi
        done <<EOF
$GONE_CANDIDATE_INFO
EOF
      else
        # A-orch-31: something WOULD have been decided (a MET row, a duplicate start, or a
        # GONE report is sitting in the candidate sets above) but the panel reading is not
        # fresh enough to trust with a write or a report. One line, said once, never a
        # STANDDOWN, a GONE report, an order or an ack.
        # NAMED, AND TRUTHFUL ABOUT WHY (wave-20 T9, REQ-4, AC-4.5; consumer report #11). The
        # line names every row it held back — the union of the three candidate sets, once each
        # — so the operator knows which agent waits on a ListAgents. `stale` is a reading that
        # exists but predates the last prompt (`live_agents` rc 3); no answer at all (rc 4) or
        # no transcript is `absent`, and used to be called stale too.
        SD_DEFERRED="$(poker_union ' ' "$STANDDOWN_NAMES" "${DUP_START_NAMES//|/ }" "$GONE_CANDIDATE_NAMES")"
        SD_WHY=absent
        [ -n "$TICK_TR" ] && [ "${SD_LRC:-4}" -eq 3 ] && SD_WHY=stale
        note "stand-down deferred for ${SD_DEFERRED} — the panel reading is ${SD_WHY}; ListAgents and the next tick decides"
      fi
    fi

    # THE FILL'S OCCUPANCY, COUNTED NOW (T2d; the declaration above the verdict walk says why).
    # Every unacked name the walk saw, minus every name the arm above has just acked. Only an
    # ack that WROTE counts as a close: a refused `ack` left the row open, and the wall will
    # count it too.
    #
    # THE WRITERS AMONG THEM (wave-24 T10, REQ-7 AC-7.1, D11). A read-only role holds no writer
    # slot, so it is not occupancy: the names go through `budget_open_writers`
    # (payload/scripts/lib/roster.sh), the same function the dispatch wall counts its `open=`
    # with, and a Patrol that read a researcher as a full seat would hold a FILL the wall
    # would have admitted.
    TICK_OCC_NAMES=""
    while IFS= read -r OCC_NAME; do
      [ -n "$OCC_NAME" ] || continue
      case "$TICK_ACKED_NOW" in *"|${OCC_NAME}|"*) continue ;; esac
      TICK_OCC_NAMES="${TICK_OCC_NAMES}${OCC_NAME}
"
    done <<EOF
$TICK_UNACKED_NAMES
EOF
    TICK_OCCUPIED="$(printf '%s' "$TICK_OCC_NAMES" | budget_open_writers "$ROSTER_FILE")"
    case "$TICK_OCCUPIED" in ''|*[!0-9]*) TICK_OCCUPIED=0 ;; esac

    # ─────────────────────────────────────── the scheduler, defined once for two callers
    #
    # ONE SITE, TWO ARMS (wave-26 T59; REQ-6 AC-6.6). The gate line, the budget and the
    # scheduler's body below are what every tick that decides prints its
    # FILL, RANGE, WAIT and CHAIN lines from. The armed first tick (no roster yet, just below)
    # exits above the place this is called on every other tick, so it calls it too: the one tick
    # where every ready row is still unstarted names them, from this same code. Defined here,
    # ahead of both, and called once by whichever arm the tick takes.
    tick_scheduler() {
    # THE FILL THIS TICK ORDERED, empty until the scheduler names one — the FILL band's own
    # input to the ranked decision below (D5).
    SCHED_FILL=""

    # The plan and its budget, read once. Both may be absent — a project with no plan, or a
    # plan written before Step 0 ever probed — and the tick then fills nothing and says why.
    # The budget is a MEASUREMENT Step 0 writes (wave-19 REQ-3, ADR-035): the governing-skill
    # hook refuses a plan Write without it, so an absent key here is a backstop the note
    # below names, and the stop wall refuses the turn on the same absence.
    #
    # THE SAME RUN THE DECISION ABOVE WAS TAKEN ON. `resolve_run` answers once per tick, so
    # a session bound to its own plan fills from its own task table and quotes its own
    # ceiling — a tick that stood its ground correctly and then filled the neighbour's
    # tasks would be worse than either failure alone (AC-1).
    sched_budget_read "$REPO_REAL" "$SESSION_ID"

    # THE SCHEDULER'S BODY, RUN UNDER ONE PARSE OF THE TABLE (wave-21 T13; review-bed/perf).
    # The holds, the findings and the ready set are three questions of one table; asked bare
    # they parsed it four times a tick. Defined here and called once, just below its body, so
    # every assignment it makes is this shell's — nothing in it runs in a subshell.
    tick_schedule() {
    # THE REPORT, AND THE CEILINGS IT IS TAKEN AGAINST — both in `gate_report` above, which
    # the DISARM arm, exiting above this block, calls for itself (AC-17, Step-6 review C-5);
    # the armed first tick calls this whole scheduler instead (T59).
    # The budget read is memoized, so reaching it a second time here costs one plan read.
    gate_report "$REPO_REAL" "$SESSION_ID"

    # THE HOLDS AND THE LEDGER, BEFORE ANY ARM (wave-21 T13). Every arm below — no plan, an
    # unreadable `current:`, Step-3 approval pending, no budget, no room at the gate, a fill —
    # gets them once, here, and none prints them again.
    tick_plan_report

    # THE UNTRIMMED READY SET, ASKED ONCE FOR EVERY ARM (wave-26 T13; review-6 F3). The WAIT
    # lines read it, and so does the WAITING line below the decision: "nothing ready" is said
    # only when this is empty. A row that is ready and not offered — a full writer budget, a
    # standing decline, a machine HOLD — is not "nothing ready".
    SCHED_READY_ALL=""
    if [ -n "${SCHED_PLAN:-}" ] && [ "$POKER_RUN_OPEN" != unreadable ]; then
      SCHED_READY_ALL="$(fill_ready_set "$SCHED_PLAN" 99999 0 2>/dev/null | tr '\n' ' ')"
    fi

    # ── FILL. gap = the GATE's width − RUNNING, ready = pending tasks whose deps all landed.
    #
    # RUNNING IS `open` (WALLS/2): the rows already counted above, on THIS session's
    # roster — a `status=intended` row with no `landing-swept/v1` marker and no ack. It is
    # the loop's own count rather than a second walk, because two definitions of "running"
    # in one file is the drift the count exists to prevent.
    #
    # THE APPROVAL GATE COMES FIRST, ahead of the budget/readiness checks below (AC-5). A
    # plan below `current: 4` has not passed Step 3, and no reading of the budget or the
    # task table changes that — so this is a wall in front of the rest of the arm, not one
    # more branch beside them.
    #
    # AN UNREADABLE `current:` WITHHOLDS TOO, UNCONDITIONALLY (Step-6 review-a C-5,
    # review-b finding (c)/N-2). An empty field, a line that will not parse, or a `T<n>`
    # against a table that NUMBERS its rows are all cases where this gate cannot tell which
    # unit the run is on — and falling through to the readiness/budget checks on THAT basis
    # is DOUBT-then-FILL: the one shape this arm exists to prevent, measured live on a plan
    # whose `current:` carried a sub-step letter (`3b`) that the old digit-only read
    # rejected as unreadable and then filled anyway. So this differs from an unreadable
    # RUNG, which falls back to the ceiling — there is no safe fallback for "did Step 3
    # pass," only "no."
    #
    # A TASK-SCALE `current: T<n>` IS READABLE NOW, against a task-shaped table (wave-18
    # REQ-3, D2; ADR-033 decision 2). It names the unit the run is on, which is a run past
    # its plan, and `fill_step_token` is what pairs the field with the table's shape: the
    # token is the number at wave scale, `T<n>` at task scale, and empty when the two
    # disagree. The withhold above is exactly that empty answer, so the shape this arm was
    # built for — a wave table sitting at `current: T1` (§22g) — still fills nothing.
    # ONE READ OF THE FIELD FOR THE WHOLE TICK (wave-19 REQ-6, D7): loaded here, in this
    # shell, so every `$( )` reader below — the step, the approval gate, the unreadable
    # report, the ready set — inherits the answer instead of parsing the plan again.
    #
    # AN UNREADABLE BOUND PLAN FILLS NOTHING, AND SAYS WHICH PLAN (wave-20 T1, REQ-2). Its
    # `current:`, its approval and its task table are all unreadable, and no other plan is
    # read in its place; the three reads below are skipped so the line names the cause
    # rather than a symptom ("current: unreadable (none)").
    SCHED_CURRENT=""; SCHED_STEP=""
    if [ -n "$SCHED_PLAN" ] && [ "$POKER_RUN_OPEN" != unreadable ]; then
      _fill_current_load "$SCHED_PLAN"
      SCHED_CURRENT="$(sched_plan_current "$SCHED_PLAN")"
      SCHED_STEP="$(fill_step_token "$SCHED_PLAN")"
    fi
    if [ "$POKER_RUN_OPEN" = unreadable ]; then
      say "no FILL — bound plan unreadable — ${SCHED_PLAN}"
    elif [ -n "$SCHED_PLAN" ] && [ -z "$SCHED_STEP" ]; then
      SCHED_CURRENT_RAW="$(_sched_plan_current_field "$SCHED_PLAN")"
      say "no FILL — plan current: unreadable (${SCHED_CURRENT_RAW:-none})"
    elif [ -n "$SCHED_PLAN" ] && ! fill_plan_approved "$SCHED_PLAN"; then
      # THE GATE IS THE APPROVAL LINE, NOT THE STEP (wave-26 T13; D3, AC-6.2): the one fact
      # `fill_ledger_live` and the dispatch wall key on. The step is named because it is
      # what a reader looks for; the line says which fact is missing.
      say "no FILL — plan at current: ${SCHED_CURRENT:-$(_sched_plan_current_field "$SCHED_PLAN")}, Step-3 approval pending: ## SDLC State carries no approved-by: line"
    elif [ -z "$SCHED_PLAN" ]; then
      note "no FILL — no plan carrying an unfenced \"## SDLC State\" to read a budget or a task table from."
    else
      # NO CAP IS NOT A FAULT (wave-28 T9; D15, REQ-2 AC-2.9). Until wave-28 a plan with no
      # `parallel-budget: writers=<n>` took a note here telling Step 0 to write one. No plan owes
      # the line now, and a probe's number is no cap: with no person's cap the width below is the
      # gate's alone (`fill_cap` answers nothing, so `fill_gate_width` runs uncapped).
      # THE HOLDS AND THE LEDGER were printed by `tick_plan_report` above, and `SCHED_HOLDS`
      # still carries the step holds for the no-FILL line below (wave-21 T13).
      # THE STANDING FILL DECLINE (wave-24 T27; D2, AC-4.7; Step-6 review C2/U1). The stop wall
      # treats the rows the session's latest `fill-declined:` answered as answered until the
      # ready set gains a row it did not see (wave-26 T15; D16), so a FILL naming them asked
      # again for an answer already given.
      # One reader, `fill_standing_decline` (lib/fill.sh), the stop collector's own: the tick
      # prints the decline while it stands and the ready set below leaves its rows out.
      SCHED_SD="$(fill_standing_decline "$(fill_ledger_path "$REPO_REAL" "$SCHED_PLAN" 2>/dev/null)" "$SESSION_ID" "$(_fill_current_field "$SCHED_PLAN")")"
      SCHED_SD_AT=""; SCHED_SD_WHY=""; SCHED_SD_IDS=""
      if [ -n "$SCHED_SD" ]; then
        IFS=$'\037' read -r SCHED_SD_AT SCHED_SD_WHY SCHED_SD_IDS <<< "$SCHED_SD"
        say "fill-declined standing since ${SCHED_SD_AT} — $(clean "$SCHED_SD_WHY")"
      fi
      # THE WIDTH IS THE GATE'S (wave-28 T13; D14, AC-2.5). The writer rows ready and not
      # answered by the standing decline are offered one at a time: `fill_gate_width` asks
      # `gate_room` once per row, with the open writers not yet showing plus the rows already
      # offered on this reading counted as owed, and stops at the first no or at a person's cap.
      # A gate line that read no room offers none, so the line and the fill never disagree.
      SCHED_CAP="$(fill_cap "$SCHED_PLAN")"
      SCHED_READY_W="$(fill_ready_tagged "$SCHED_PLAN" 2>/dev/null \
        | awk -F'\t' -v sd=" $SCHED_SD_IDS " '$2 == "w" && index(sd, " " $1 " ") == 0 { n++ } END { print n + 0 }')"
      SCHED_WIDTH="$TICK_OCCUPIED"
      [ "${SCHED_GATE_ROOM:-}" = yes ] \
        && SCHED_WIDTH="$(fill_gate_width "$TICK_OCCUPIED" "$SCHED_OWED" "$SCHED_READY_W" "$SCHED_CAP")"
      case "$SCHED_WIDTH" in ''|*[!0-9]*) SCHED_WIDTH="$TICK_OCCUPIED" ;; esac
      SCHED_GAP=$(( SCHED_WIDTH - TICK_OCCUPIED ))
      [ "$SCHED_GAP" -lt 0 ] && SCHED_GAP=0
      # A FULL WRITER BUDGET STILL OFFERS THE READ-ONLY ROWS (wave-26 T13; D9): a verify or
      # review row takes no writer slot, and `fill_ready_set` offers it whatever the gap. So
      # the set is asked at a closed gap too, and "the budget is full" is said only when it
      # offered nothing.
      SCHED_RO_READY=""
      [ "$SCHED_GAP" -eq 0 ] && SCHED_RO_READY="$(fill_ready_set "$SCHED_PLAN" "$SCHED_WIDTH" "$TICK_OCCUPIED" "$SCHED_SD_IDS")"
      if [ "$SCHED_GAP" -eq 0 ] && [ -z "$SCHED_RO_READY" ] && [ "$SCHED_READY_W" -gt 0 ]; then
        SCHED_READY=""
        if [ -n "$SCHED_CAP" ] && [ "$TICK_OCCUPIED" -ge "$SCHED_CAP" ]; then
          say "no FILL — the cap writers=${SCHED_CAP} is reached by ${TICK_OCCUPIED} unacked roster row(s); ${SCHED_READY_W} writer row(s) wait."
        else
          say "no FILL — the gate gives no room (its line above); ${SCHED_READY_W} writer row(s) wait."
        fi
      else
        # READY IS THE PREREQUISITE GRAPH (wave-20 REQ-5, Δ1, Δ6; ADR-036). Through
        # 1.8.6 ready was asked at the step the plan is on (REQ-1e, AC-1e.4), and a
        # Step-6 review whose deps had landed sat unfilled all through Verify. A work
        # row is now ready when it is pending and every dependency has landed, whatever
        # its step; only a gate act — an integrate or close row, or a doc row at Step 7
        # or later (the release; T10b) — still waits for `current:` to reach its step.
        # `SCHED_STEP` is still passed — it is what holds those gate acts — already read
        # and already proven readable by the approval gate above, which is why this needs
        # no second parse and no fallback: a `current:` that would not parse took the
        # withhold arm and never reached here.
        #
        # AND THE SET IS THE LIBRARY'S, TRIM INCLUDED (wave-18 REQ-3, D2; ADR-033
        # decision 2). `fill_ready_set` is what `payload/scripts/lib/stop.sh`'s fill
        # duty computes at the end of every turn, so the rows this tick ORDERS and the
        # rows that turn's end REFUSES to leave undispatched are one answer rather than
        # two. It takes the width and the occupancy this arm measured: the gate's width, and
        # the roster's unacked rows after this tick's own acks. The wall measures both the
        # same way (the width from `fill_gate_width`, the occupancy by the same predicate:
        # wave-19 audit V-2, T2d), so what it names is what this prints.
        SCHED_READY="${SCHED_RO_READY:-$(fill_ready_set "$SCHED_PLAN" "$SCHED_WIDTH" "$TICK_OCCUPIED" "$SCHED_SD_IDS")}"
        SCHED_IDS=""; SCHED_N=0; SCHED_OFFERED=""
        while IFS= read -r TASK_ID; do
          [ -n "$TASK_ID" ] || continue
          # THE LINE PRINTS THE AGENT NAME, NOT THE TASK ID (T22, A-orch-33). They are the
          # same string for a task that has never run, which is why every fixture and every
          # doc example still reads `FILL T1 T2`. They diverge when the id is already spent,
          # and then the ONLY safe token to print is the free one: see `fill_name` for why
          # the roster, and not the plan, is what "spent" is read from.
          SCHED_IDS="${SCHED_IDS}${SCHED_IDS:+ }$(fill_name "$ROSTER_FILE" "$(clean "$TASK_ID")")"
          SCHED_N=$((SCHED_N + 1)); SCHED_OFFERED="${SCHED_OFFERED} $(clean "$TASK_ID")"
        done <<EOF
$SCHED_READY
EOF
        if [ "$SCHED_N" -gt 0 ]; then
          # THE PRINTED LINE IS THE DUTY WALL'S (payload/scripts/lib/stop.sh reads
          # `poker: FILL ` out of this turn's raw tool result) and is unchanged to the byte.
          # WHAT CHANGES is that the ids are also carried to the decision line, so a tick
          # that ordered work stops reporting that nothing was wanted (REQ-10 AC-10.2, D5:
          # observed 19:00:46Z as `poker: FILL T13` above `decision=QUIET`).
          say "FILL ${SCHED_IDS}"
          SCHED_FILL="$SCHED_IDS"
          # THE RANGE AN OFFERED REVIEW READS (wave-26 T32; T14, AC-6.5): one line per offered
          # row that reads `live:head`, naming the difference past the last review proof, from
          # the head this tick already read (UNITS_LIVE_HEAD; no git here). Before the first
          # review proof there is no range, and no line: the review reads all the landed work.
          # THE RANGE IS THE ROW'S (wave-27 T10; D4): a read row's starts at the oldest last
          # reading among its own questions, so two rows offered at once can print two ranges;
          # a bare `live:head` row's is the one range 1.11.0 printed.
          # WHAT MOVED INSIDE IT (wave-27 T43; D10; A-orch-48, A-orch-71): once every question
          # the row reads has its whole reading, a `MOVED` line names each plan row whose landing
          # lies inside the range, with the matrix criteria it serves. A landing is a merge the
          # run's landing record (`landing-proofs.log`, written by land) gives a row.
          # THE LIST IS PRINTED ONLY WHEN IT IS THE WHOLE RANGE (wave-27 T34; review pass 30
          # should-fix 1 and 2, A-orch-86): this tick lists the range's first-parent commits with
          # ONE `git rev-list` per offered row and hands them to the library, which runs no git.
          # When every one is the merge of a header naming a row (`units_unrecorded` prints
          # none), the rows are named (`units_rows_in_range`); otherwise one `MOVED unknown` line
          # says how many are not, in place of every other, and the read is the whole range. A
          # header with `row=—`, a commit made straight on the working branch and a landed row
          # of any kind that left no header are all that case. `MOVED none` is an empty range.
          while IFS="$(printf '\t')" read -r LR_ID _; do
            [ -n "$LR_ID" ] || continue
            case "$SCHED_OFFERED " in *" $LR_ID "*) ;; *) continue ;; esac
            SCHED_RANGE="$(units_live_range "$SCHED_PLAN" "$LR_ID" 2>/dev/null)"
            [ -n "$SCHED_RANGE" ] && say "RANGE $LR_ID ${SCHED_RANGE} — the review reads what landed past the last review proof, and no more"
            [ -n "$SCHED_RANGE" ] && units_whole_read "$SCHED_PLAN" "$LR_ID" || continue
            LR_REC="$(docs_root "$REPO_REAL" 2>/dev/null)/record/$(basename "$SCHED_PLAN" .plan.md)/landing-proofs.log"
            if ! LR_IN="$(git -C "$REPO_REAL" rev-list --first-parent "$SCHED_RANGE" 2>/dev/null)"; then
              say "MOVED unknown — the range's commits cannot be listed"
              continue
            fi
            [ -n "$LR_IN" ] || { say "MOVED none"; continue; }
            LR_UNK="$(printf '%s\n' "$LR_IN" | units_unrecorded "$SCHED_PLAN" "$LR_REC" 2>/dev/null | awk 'NF { n++ } END { print n + 0 }')"
            LR_MOVED=""
            [ "$LR_UNK" = 0 ] && LR_MOVED="$(printf '%s\n' "$LR_IN" | units_rows_in_range "$SCHED_PLAN" "$SCHED_RANGE" "$LR_REC" 2>/dev/null)"
            if [ -z "$LR_MOVED" ]; then
              # A range every commit of which a header names, and no row's last landing among
              # them, cannot be listed whole either: said as the same one line.
              [ "$LR_UNK" = 0 ] && LR_UNK="$(printf '%s\n' "$LR_IN" | awk 'NF { n++ } END { print n + 0 }')"
              say "MOVED unknown — ${LR_UNK} commit(s) in the range are no recorded landing"
              continue
            fi
            while IFS="$(printf '\t')" read -r LM_ID _ LM_CRIT; do
              [ -n "$LM_ID" ] && say "MOVED $LM_ID — ${LM_CRIT:-no criterion in the matrix}"
            done <<EOF_MV
$LR_MOVED
EOF_MV
          done <<EOF
$(units_live_rows "$SCHED_PLAN" 2>/dev/null)
EOF
        else
          # A READY ROW THE STANDING DECLINE ANSWERED IS NOT "NOT READY" (T27): the line says
          # which answer holds the rows, and the standing line above says why.
          if [ -n "$SCHED_SD_IDS" ] && [ -n "${SCHED_READY_ALL// /}" ]; then
            say "no FILL — every ready row is answered by the standing fill-declined (${SCHED_SD_IDS}); it stands until a row it did not see is ready."
          else
            # THE REASONS ARE PER ROW NOW (wave-26 T13; D9, AC-6.6). Through 1.10 this line
            # carried one sentence for every waiting row and named only the step holds; each
            # waiting row is on its own WAIT line below, with the read it lacks and the row
            # that writes it, the step holds among them.
            say "no FILL — width=${SCHED_WIDTH} occupied=${TICK_OCCUPIED} gap=${SCHED_GAP}, and no pending task is ready."
          fi
        fi
      fi
      tick_wait_report
      tick_finding_report
    fi

    }
    tick_plan_memoised tick_schedule
    }

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
        # THE SCHEDULER, FROM ITS ONE SITE (wave-26 T59; REQ-6 AC-6.6), above the decision line.
        # The rung (AC-17: on EVERY tick); the holds and the ledger (wave-21 T13: no roster yet
        # is the reader's no-roster rule, the gate's own, so what prints is what the gate would
        # refuse a writer's first commit on); then the ready set, FILL, WAIT and CHAIN, or the
        # line saying why there is none, the approval gate first. This is the first tick of every
        # run, so it is the tick where the batch not yet sent is most worth naming. Through T58
        # this arm printed the first two and exited, and the batch went unnamed.
        tick_scheduler
        # THE SENTENCE FIRST, THE DECISION LINE LAST (REQ-10 AC-10.4). Every band in this
        # verb prints its explanation above its machine line, so the last line a tick prints
        # is always the answer — whichever arm answered.
        #
        # THE BAND IS THE ROSTER ARM'S, FROM THE SAME `tick_band` (wave-26 T59; D5): a FILL this
        # tick printed makes it FILL, with its `fill=` field, exit 0; nothing ready, or approval
        # pending, leaves it QUIET, exit 0, stamp kept; a gate request raises it to NOTIFY.
        tick_band
        if [ "$TICK_DECISION" = NOTIFY ]; then
          tick_gate_report
          tick_decision_line NOTIFY "$TOTAL" "$OPEN" "" "" "${SCHED_FILL:-}" "" "$TICK_GATE_FIELD"
          exit 1
        fi
        if [ "$TICK_DECISION" = FILL ]; then
          tick_fill_sentence
          tick_decision_line FILL "$TOTAL" "$OPEN" "" "" "$SCHED_FILL"
          exit 0
        fi
        say "QUIET — armed, nothing dispatched yet on this session"
        tick_decision_line QUIET "$TOTAL" "$OPEN"
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
    # THE TERMINAL DECISION KEEPS THE ROSTER'S COUNT, never the live set's (S19). DISARM
    # removes the stamp and ends the Patrol for the rest of the session, and the state it
    # would fire on here is precisely the one that most needs supervising: a row whose
    # contract is UNMET and whose agent has finished without delivering. `open=` and the
    # fill are advisory arithmetic and may be trimmed; this may not.
    if [ "$OPEN_ROSTER" -eq 0 ]; then
      # RESOLVED HERE, IN THIS SHELL, FIRST: `run_state` below runs in a command substitution,
      # so a latch it sets dies with the subshell and `sched_budget_read` would resolve and
      # announce a second time. One resolution in the parent, one announcement.
      resolve_run "$REPO_REAL" "$SESSION_ID"
      RUN_STATE_RAW="$(run_state "$REPO_REAL" "$(patrol_armed_file "$SESSION_ID")" "$SESSION_ID")"
      RUN_STATE="${RUN_STATE_RAW%%|*}"
      RUN_STATE_WHY="${RUN_STATE_RAW#*|}"
    fi

    # DISARM — no open row AND a run that says it is delivered, in a delivery that POSTDATES
    # this Patrol's arming (R-13: an older one is the previous run's close-out, still newest
    # while the new run's plan does not exist yet). "No open row" alone was the whole
    # predicate until 1.3.2, and it is also exactly what a live wave looks like between two
    # batches: every writer of a task landed, the next not yet briefed. The tick ended the
    # Patrol there, terminally, and the rest of the wave ran unsupervised (epic-20 W1
    # dogfood, idea §B-4; R-4, AC-13/AC-14). The first conjunct still generalizes the spec's
    # literal "disarmed on empty roster" to a roster whose every row is MET/WAIVED/acked (S2
    # design decision, logged to the plan); the second is what tells a finish from a lull.
    #
    # An empty roster on a run that has not delivered falls through to QUIET below, and QUIET
    # KEEPS THE STAMP — which is the half that matters on disk. The clock keeps running, the
    # arming wall stays satisfied, and hooks/patrol-revive.sh has nothing to report.
    if [ "$OPEN_ROSTER" -eq 0 ] && [ "$RUN_STATE" = delivered ]; then
      # THE RUNG ON THE TERMINAL TICK TOO (AC-17). The number is moot to a Patrol that is
      # stopping, and that is not the point: the acceptance criterion is that every tick
      # reports it, and an operator reading the last tick of a run in a transcript should not
      # have to know which arm printed the line and which did not.
      gate_report "$REPO_REAL" "$SESSION_ID"
      # …AND THE PLAN REPORT, for the same reason (wave-21 T13): a delivered run whose ledger
      # still carries a finding is one the gate would refuse, and this is the last tick to say so.
      tick_plan_memoised tick_plan_report
      tick_conclude DISARM
      tick_gate_report
      say "DISARM — no open row on this roster and the run is delivered (${RUN_STATE_WHY}); the Patrol may stop."
      tick_decision_line DISARM "$TOTAL" "$OPEN" "" "" "" "" "$TICK_GATE_FIELD"
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

    # ─────────────────────────────────────── the lease overrun (spec AC-28)
    #
    # A spawned worktree is a leased slot bound to the ledger row that dispatched its
    # writer, and the lease ends when that row is fact-discharged (design ledger C1). A tree
    # still standing after that is a slot counted against the worktree budget that nobody
    # holds — and nothing else in the fleet walks `.worktrees` against the roster, so it
    # stays invisible until someone runs out of budget.
    #
    # READ OFF THE VERDICT THIS TICK ALREADY TOOK. `$VERDICT_OUT` is one
    # `session-sweeper.sh verdict` over the whole roster, and it is where the discharge
    # vocabulary lives: `state=MET`/`WAIVED`, and the `acked=` the sweeper folds in from its
    # own ledger. A roster read on its own would miss every acked row. The library takes a
    # FILE, so the lines this tick is already holding are spilled to a temporary one and
    # removed again — never into `.bionic/tmp`, which is state the operator reads.
    #
    # THE CONVENTION AND THE PREDICATE ARE THE LIBRARY'S, not a second copy here:
    # `.worktrees/<dir>` belongs to the row named `W-<DIR>` uppercased, and "discharged"
    # means acked or MET/CLOSED/WAIVED. Three callers share that definition
    # (payload/scripts/lib/worktree.sh's header names them); this is the third.
    #
    # PLACED AFTER DISARM, BEFORE THE SCHEDULER. A run that has DELIVERED exits above, and
    # its standing trees are the integration step's assertion to make rather than a Patrol
    # line nobody is left to read.
    #
    # IT REMOVES NOTHING. `spawn-worktree.sh land` is the act and the orchestrator runs it;
    # the tick says the tree is standing and stops there.
    #
    # AND IT IS A NOTE, NOT A BAND (REQ-10 AC-10.3; D5). This walk used to feed NOTIFY, so a
    # tree left standing after its row was discharged raised the exit-1 band on EVERY tick
    # for the life of the tree — nothing here is remembered between ticks — and buried the
    # decision the roster had actually reached. A standing tree is a fact about disk: it
    # prints as `poker: note:` and it rides the decision line in a `trees=` field of its own,
    # where a reader that wants to act on it can find it without the tick having claimed
    # something was wrong.
    LEASE_TREES=""
    LEASE_FILE="$(mktemp "${TMPDIR:-/tmp}/bionic-poker-verdict.XXXXXX" 2>/dev/null)" || LEASE_FILE=""
    if [ -n "$LEASE_FILE" ]; then
      printf '%s\n' "$VERDICT_OUT" > "$LEASE_FILE" 2>/dev/null
      while IFS= read -r LEASE_LINE; do
        [ -n "$LEASE_LINE" ] || continue
        LEASE_PATH="$(printf '%s' "$LEASE_LINE" | cut -f1)"
        LEASE_ROW="$(printf '%s' "$LEASE_LINE" | cut -f2)"
        [ -n "$LEASE_PATH" ] && [ -n "$LEASE_ROW" ] || continue
        note "tree stands $LEASE_PATH — row discharged; land or remove"
        LEASE_TREES="${LEASE_TREES}${LEASE_TREES:+,}$(clean "$LEASE_PATH")"
      done <<EOF
$(worktree_lease_overruns "$REPO_REAL" "$LEASE_FILE")
EOF
      rm -f "$LEASE_FILE" 2>/dev/null || :
    else
      die "WARN — no temporary file for the lease walk; standing worktrees were not checked."
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
    # not negotiable and why nothing here re-derives the budget. The armed first tick exits
    # above this line and calls the same `tick_scheduler` there (wave-26 T59).
    tick_scheduler

    # ─────────────────────────────────────── the ranked decision (REQ-10 AC-10.2; D5)
    #
    # ONE NOTIFY BAND, TWO CONTRIBUTORS, AND THEY ARE BOTH ABOUT A ROW: past its declared
    # duration, or quieter than its declared cadence. The standing worktree was the third
    # until this wave and is not one any more — it is a fact, printed as a note above and
    # carried in `trees=` below (AC-10.3). The rows and details are concatenated rather than
    # given a field each, so no consumer of this schema has to learn a new key to see them.
    #
    # THE BAND IS THE RANKED MAXIMUM, ascending: QUIET is the floor, a stand-down raises it to
    # STANDDOWN, a fill to FILL, a row needing surfacing to NOTIFY. DISARM is terminal and has
    # already exited. Every lower band keeps its own field, so nothing this tick learned is lost
    # to the band that won — a NOTIFY tick still reports the fill it ordered.
    #
    # STANDDOWN JOINS THE BAND (wave-24 T7, REQ-4 AC-4.2; D4). It fed none, so a tick that had
    # just named an agent to stop printed `decision=QUIET` under the line that named it.
    #
    # ONE COPY: `tick_band`, defined beside `tick_conclude` above, which the armed first tick
    # calls too (wave-26 T59).
    tick_band

    if [ "$TICK_DECISION" = NOTIFY ]; then
      # THE SENTENCES FIRST, ONE PER ARM THAT HAS SOMETHING — a tick holding only the other
      # arm's finding must not print an empty one.
      tick_gate_report
      [ -n "$NOTIFY_DETAIL" ] && say "NOTIFY — past declared duration: $NOTIFY_DETAIL"
      [ -n "$QUIET_DETAIL" ] && say "NOTIFY — quieter than the declared cadence: $QUIET_DETAIL"
      tick_decision_line NOTIFY "$TOTAL" "$OPEN" "$NOTIFY_ROWS" \
        "$(clean "${NOTIFY_DETAIL}${NOTIFY_DETAIL:+${QUIET_DETAIL:+; }}${QUIET_DETAIL}")" \
        "$SCHED_FILL" "$LEASE_TREES" "$TICK_GATE_FIELD"
      exit 1
    fi

    # THE QUIET LINE HAS TWO READINGS NOW, and printing the wrong one is how this fix would
    # be mistaken for the bug it repairs. "0 open row(s), none past their declared duration"
    # over a mid-run lull says nothing about why the Patrol did not stop, and its reader is a
    # model deciding whether the Patrol is broken. So the empty-roster reading names the run
    # state it decided from — which plan, and where that plan says the run is.
    # KEYED ON THE ROSTER'S COUNT, not the live one (S19). `RUN_STATE_WHY` is read only on
    # the empty-roster path above, and — more to the point — "no open row on this roster" is
    # a statement about the roster, which a liveness reading does not get to make false. The
    # live number is `open=` on the decision line, and the trim line above says so
    # whenever the two differ.
    if [ "$TICK_DECISION" = FILL ]; then
      tick_fill_sentence
    elif [ "$TICK_DECISION" = STANDDOWN ]; then
      say "STANDDOWN — ${SD_ORDER_NAMES} met and still on the panel; TaskStop each, or hold it."
    elif [ "$OPEN_ROSTER" -eq 0 ]; then
      say "QUIET — no open row on this roster, but the run is not delivered (${RUN_STATE_WHY}); the Patrol keeps its stamp and its clock."
    else
      # NAMING BOTH READINGS, because both are now taken: a row can be inside its duration
      # and still have gone quiet, and a QUIET tick that named only the duration was the
      # sentence B5 reported as true-but-silent.
      say "QUIET — $OPEN_ROSTER open row(s) on this roster, none past their declared duration and none quieter than its declared cadence."
      # THE RUN IS WAITING ON ITS AGENTS (wave-26 T15, REQ-4 AC-4.5; D16, research-R2 §3 P5).
      # Nothing filled, nothing stands down, nothing needs surfacing, and a row is open: every
      # writer slot is taken or no row is ready. The Patrol prompt asks for nothing after this
      # line, and the duty above is none, so the turn ends here.
      #
      # ONLY WHEN NOTHING IS READY (wave-26 T13; review-6 F3). A QUIET tick can also be one
      # where a row IS ready and not offered: the writer budget is full, or the standing
      # fill-declined answered it. "nothing ready" is false there, and each such row already
      # has its WAIT line saying why, so the line is left out.
      case "${SCHED_READY_ALL:-}" in
        *[!\ ]*) : ;;
        *) say "WAITING — ${OPEN_ROSTER} running, nothing ready" ;;
      esac
    fi
    tick_decision_line "$TICK_DECISION" "$TOTAL" "$OPEN" "" "" "$SCHED_FILL" "$LEASE_TREES"
    exit 0
    ;;
esac
