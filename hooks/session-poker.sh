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
#     bash <plugin-root>/hooks/session-poker.sh rule <writer> '<text>' [--words '<the user's words>'] | ruling-ack <id> | rulings <writer>
#                                                      a binding ruling for a live writer, its acknowledgement, its state (writes the roster)
#     bash <plugin-root>/hooks/session-poker.sh task-set | step-line | step-field | current | ledger-add | ledger-set …
#                                                      the plan-row verbs, each the task-add transaction (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh proof-add <kind> <evidence>   a proof line naming the head its evidence read (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh proof-add review <record> --question <q> --reader <name>   a reading: that proof line with its question, reader, result and scope
#     bash <plugin-root>/hooks/session-poker.sh waive <question> '<reply>'   the user's waiver of a reading question at the working head (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh release-check   run the project's declared release check over the release range; its log and its check fact, failing or not (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh floor-run   run the project's regression (its floor: command, else tests/run.sh, whole, held to the full-run rules) in the working checkout and log it for proof-add floor (writes a log under record/, never the plan)
#     bash <plugin-root>/hooks/session-poker.sh finding-stated <record>#<n> '<sentence>'   store a deferred finding's one changelog sentence on its deferred: line (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh share [<n>]   print the machine's share of its own resources, or set it to <n>, 1 to 100 (the set writes the user-level share file)
#     bash <plugin-root>/hooks/session-poker.sh finding-move <record>#<n> <defer|fix> '<the user's words>' '<why>'   move a finding across the line on words the user typed in this session (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh finding-move <record>#<n> fixed <row>   name the ## Tasks row that fixed a finding, whatever its ancestry (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh prompt     the canonical Patrol prompt for this session's CronCreate (read-only)
#     bash <plugin-root>/hooks/session-poker.sh fill-report [<plan>]   the run's missed-opportunity, HOLD and decline minutes (read-only)
#     bash <plugin-root>/hooks/session-poker.sh cover <question> <a>..<b>   the cover <sha> <basis> line of each commit the judge walks in that range for that question (read-only)
#     bash <plugin-root>/hooks/session-poker.sh wait <name|run id> [--for <s>]   wait on a detached run until it ends; exits with its code (read-only)
#     bash <plugin-root>/hooks/session-poker.sh stop-run <name|run id|request id> [--report-only] [--why '<reason>']   stop a detached run, or end a gate request and TERM its holder's group (signals, writes ends, ev=stop-run)
#     bash <plugin-root>/hooks/session-poker.sh regression-runs [--write]   the full-runner runs the rosters record; --write puts the count in the bound plan's header
#     bash <plugin-root>/hooks/session-poker.sh anchors check|index [<root>] [--at <commit>]   check every suite's mutation anchors where they point, or print file -> the suites anchored on it (read-only)
#     bash <plugin-root>/hooks/session-poker.sh matrix-render   write the bound plan's AC blocks from its ## Eval design, each with evidence: pending, and user-confirmed: pending at T4 (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh discharge <AC-id>   write that matrix row's auditor cell as the bare token CONFIRMED (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh handoff   rewrite the bound plan's ## Handoff in place from the plan and the machine: heads, open rows, live agents, last proof, date -u (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh brief <row>   render the row's dispatch brief into record/<wave>/briefs/<row>.md: the scaffold from the row, the head, the orchestrator's sections marked (writes that file, never the plan)
#     bash <plugin-root>/hooks/session-poker.sh task-split <id> -- <child spec>…   rewrite one pending row as two or more children, each <id>:<task>:<size>:<Files>, its waiters re-pointed (writes the plan)
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

# THE PERSON'S LEDGER AND ITS ONE SENDER (epic-23 wave-33-workhorse, T11; REQ-2, D2). owed.sh keeps
# what the person owes and sources notify.sh beside it: the tick opens and sends each GATE request
# it raises, and approve, waive and decline close the item their answer settles. NOT in
# `BIONIC_LIB_WANT`, and sourced only when readable: a library without it (one older than this wave)
# leaves every verb and every tick exactly as it was, so the ledger can never refuse a command.
if ! declare -F owed_send >/dev/null 2>&1 && [ -r "$BIONIC_LIB/owed.sh" ]; then
  # shellcheck source=/dev/null
  . "$BIONIC_LIB/owed.sh"
fi
# poker_owed_close <root> <key> <by> -> always 0, prints nothing: the answer verb closes the item.
poker_owed_close() {
  declare -F owed_close >/dev/null 2>&1 || return 0
  OWED_ROOT="$1" owed_close "$2" "$3" >/dev/null 2>&1
  return 0
}

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
# it), when that answer was first given, the decision band, whether the turn's task list is behind
# (`duty=owed|none`: advice since wave-31 T32, D6, which deleted the stop wall's task-list duty;
# no wall reads it), and the Patrol prompt version
# `arm` recorded. A tick whose hash matches the file's prints one line. The prompt version is
# bumped whenever the prompt's wording changes what a tick turn is asked to do, so a Patrol armed
# under an older one is told to re-arm.
PATROL_DIGEST_SCHEMA="patrol-digest/v1"
# THE HOLD'S REASON, AS EVERY FIX LINE PRINTS IT (wave-24 T27; critic I4): a quoted
# placeholder, so a line pasted as printed is one argument and never a redirect from a file
# named `reason`. The stop wall's stand-down refusal prints the same words
# (payload/scripts/lib/stop.sh `STANDDOWN_HOLDS`); tests/session-poker-2.test.sh §HOLD-fix pins
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
  die "  bash ${HOOK_DIR}/session-poker.sh share [<n>]   print the machine's share, 1 to 100 (92 when none is set); with <n>, set it: one integer in the user-level share file the gate reads"
  die "  bash ${HOOK_DIR}/session-poker.sh window     the instant this session's roster begins, UTC ISO-8601 (empty when it cannot be dated)"
  die "  bash ${HOOK_DIR}/session-poker.sh adopt      every open row a PREDECESSOR session left on this project's rosters"
  die "  bash ${HOOK_DIR}/session-poker.sh adopt --report-only   the same rows, with the adoption itself not taken (writes nothing)"
  die "  bash ${HOOK_DIR}/session-poker.sh sweep      delete every DEAD session's leftover state under this project's .bionic/tmp"
  die "  bash ${HOOK_DIR}/session-poker.sh sweep --report-only   the same files, listed, with nothing deleted"
  die "  bash ${HOOK_DIR}/session-poker.sh sweep --window   defer a dead session whose own newest file is younger than the poker interval"
  die "  bash ${HOOK_DIR}/session-poker.sh bind <plan>   name the open run this session is working (rewrites its binding)"
  die "  bash ${HOOK_DIR}/session-poker.sh extend <name> <reason>   re-open a MET row for <name>: a fresh row goes on the roster, launched now, so the next tick reads it live again"
  die "  bash ${HOOK_DIR}/session-poker.sh hold <name> <reason>   answer a STANDDOWN by keeping <name> up: the tick prints it held, and orders no stop, until its launch, deliverable or messages change"
  die "  bash ${HOOK_DIR}/session-poker.sh rule <writer> '<text>' [--words '<the user's words>']   record a binding ruling for a live writer: pushed with its next tool result, and its commit and ready refused until it is shown; --words quotes what the user typed, in any session the run recorded, with that session"
  die "  bash ${HOOK_DIR}/session-poker.sh ruling-ack <id>   the writer's acknowledgement of a ruling it was shown (marks it shown)"
  die "  bash ${HOOK_DIR}/session-poker.sh rulings <writer>   each ruling of that writer: recorded, pushed=, and unread or shown= (read-only)"
  die "  bash ${HOOK_DIR}/session-poker.sh decline <id>[,<id>] '<reason>' [--on <row>]   answer a FILL by recording why those ready rows wait: one line in the run's fill ledger, standing until a row it did not name is ready; --on names the row they wait on (declined-on=); a file or a word is refused"
  die "  bash ${HOOK_DIR}/session-poker.sh decline lift [<ids>]   end the standing decline for those rows (every row it answers with no ids): one ledger line, and the next tick offers the rows it ended"
  die "  bash ${HOOK_DIR}/session-poker.sh budget writers=<n> '<reply>'   record the user's cap on writers in the plan header (source=user, budget-override:)"
  die "  bash ${HOOK_DIR}/session-poker.sh regression <yes|no> '<reply>'   record the Step-0 regression setting in the plan header (regression:, and regression-override: against the scale default task no, wave yes, epic no)"
  die "  bash ${HOOK_DIR}/session-poker.sh task-add <id> <step> <kind> <task> <agent> <deps> <size> <serves> <Files> [<reads>]   add a ## Tasks row to the bound plan as a transaction: validated and dry-committed on a copy, then swapped in; <reads> fills a reads column (— for the default of its kind); --born <record>#<n>[,…] names the findings the row fixes; --born floor:<suite> marks a row born of the floor's red in that suite"
  die "  bash ${HOOK_DIR}/session-poker.sh amend <name> [--files+ <path>]... [--suites+ <suite>]... [--reexec+ '<cmd>']... --reason <why>   widen a live row's contract: a successor row, judged by the dispatch grammar"
  die "  bash ${HOOK_DIR}/session-poker.sh task-set <id>[,<id>...] <col>=<val>... [-- <id>[,<id>...] <col>=<val>...]... [--reason '<why>']   set cells of ## Tasks rows (any header column; Files only on a pending row no roster names, a launched row's Files being amend's), every group in one transaction, the table judged once"
  die "  bash ${HOOK_DIR}/session-poker.sh step-line <N|T<n>> <text> [--append]   write a - Step N: or - T<n>: line under ## SDLC State"
  die "  bash ${HOOK_DIR}/session-poker.sh step-field <N> <key>=<value>   write or replace one field of a Step N block: head, cmd, pass, total, output, merge, worktree-removed, adr, share, or walk-artifact (Step 5 only)"
  die "  bash ${HOOK_DIR}/session-poker.sh current <N>   move current: (9 is close-out's); advancing to 4 fills the Step-4 block's worktree/base-sha/branch"
  die "  bash ${HOOK_DIR}/session-poker.sh approve <name> '<reply>'   record the user's approval <name> as an approved: line under ## SDLC State (the plan's own is approved-by:, written at Step 3)"
  die "  bash ${HOOK_DIR}/session-poker.sh ledger-add <id> <col>=<val>...   add a ## Dispatch ledger row (cells not named are —)"
  die "  bash ${HOOK_DIR}/session-poker.sh ledger-set <id> <col>=<val>...   set cells of a ## Dispatch ledger row"
  die "  bash ${HOOK_DIR}/session-poker.sh row-landed <id> <commit> <at> [--by-hand <who> <why>]   the landing's row: status, step line, ledger line, one write"
  die "  bash ${HOOK_DIR}/session-poker.sh deliver <id>   a record row's own landing: its artifact checked (a review row's reading too), then row-landed at the working head"
  die "  bash ${HOOK_DIR}/session-poker.sh proof-add <floor|review|task> <evidence>   record a proof line under ## SDLC State, naming the head its evidence read; proof-add floor <log> [<log>…] takes one log or several, each opening head=<40-hex> dirty=0 and ending rc=0"
  die "  bash ${HOOK_DIR}/session-poker.sh proof-add inherited <suite>   run that suite file, red in the floor's whole run, at the plan's base in a scratch tree: red there too is inherited debt, written as an inherited: line; green there is a regression, refused"
  die "  bash ${HOOK_DIR}/session-poker.sh proof-add review <record> --question <evidence|adversarial|structure> --reader <roster name>   record a reading: the review proof with the question, reader, result and scope"
  die "  bash ${HOOK_DIR}/session-poker.sh waive <evidence|adversarial|structure> '<reply>'   record the user's waiver of that question at the working head, as a waived: line under ## SDLC State"
  die "  bash ${HOOK_DIR}/session-poker.sh release-check   run .bionic/config.yaml's release-check: command from the last release to the working head; record its log and a kind=check proof line, result=fail on a non-zero exit"
  die "  bash ${HOOK_DIR}/session-poker.sh floor-run   run the regression in the working branch's checkout, .bionic/config.yaml's floor: command, else tests/run.sh whole (held to the full-run rules); write its log, opening head=<40-hex> dirty=<n> and closing rc=<n>, for proof-add floor to cite"
  die "  bash ${HOOK_DIR}/session-poker.sh finding-stated <record>#<n> '<sentence>'   store the one changelog sentence of a deferred finding on its deferred: line under ## SDLC State"
  die "  bash ${HOOK_DIR}/session-poker.sh finding-move <record>#<n> <defer|fix> '<the user's words>' '<why>'   move a finding across the line on words the user typed in this session, as a moved: line under ## SDLC State"
  die "  bash ${HOOK_DIR}/session-poker.sh finding-move <record>#<n> fixed <row>   name the ## Tasks row that fixed a finding, landed before the reading or after it, as a moved: to=fixed line under ## SDLC State"
  die "  bash ${HOOK_DIR}/session-poker.sh disposition [<record>#<n> <fix|defer> '<the user's words>' '<why>' ['<changelog sentence>']]   render every finding of the registered readings (rating, record, fix row, state, the decision it needs), adding their debt and opening an owed item per finding the person must rule on; with a finding, record the person's ruling on it"
  die "  bash ${HOOK_DIR}/session-poker.sh launch-sync [--wait]   write every open launch the bound plan lacks (its row and its ledger line) in one transaction"
  die "  bash ${HOOK_DIR}/session-poker.sh prompt     the canonical Patrol prompt: the one a CronCreate for this session carries"
  die "  bash ${HOOK_DIR}/session-poker.sh fill-report [<plan>]   missed-opportunity, HOLD and decline minutes from the run's fill ledger"
  die "  bash ${HOOK_DIR}/session-poker.sh landing-report [--rows] [--hand-holds] [<plan>]   the run's landings, waits and runs, folded from its landing record and the gate's requests; --rows adds a line per landed row; --hand-holds adds the count of escape-hatch uses by kind, folded from the lines their verbs wrote"
  die "  bash ${HOOK_DIR}/session-poker.sh cover <question> <a>..<b>   the basis the judge holds a range by: one cover <sha> prose|born-review|born-floor|owes line per commit past <a> on <b>'s first-parent line, for evidence, adversarial or structure; the lines current 7 prints under a review ... uncovered <a>..<b> line (read-only)"
  die "  bash ${HOOK_DIR}/session-poker.sh wait <name|run id> [--for <seconds>]   wait on a detached run (booked.sh --detach) until it ends, printing its progress; exits with its code, 70 when it was LOST, 75 when --for ran out first"
  die "  bash ${HOOK_DIR}/session-poker.sh stop-run <name|run id|request id> [--report-only] [--why '<reason>']   stop a detached run: TERM its process group, then KILL every group below it still alive; records rc=137 when it wrote no end. A gate request id, or a name holding no running detached run but one open request: ends the request (by=<session> why=<reason>) and TERMs its holder's group. Either way one ev=stop-run goes to the bound run's landing record"
  die "  bash ${HOOK_DIR}/session-poker.sh regression-runs [--write]   the number of full-runner runs (tests/run.sh with no --only) the project's rosters record as ended; --write puts it in the bound plan's regression-runs: header"
  die "  bash ${HOOK_DIR}/session-poker.sh anchors check|index [<root>] [--at <commit>]   check: MOVED <suite>:<line> for each anchor whose text is not on exactly one line where it points (exit 1), nothing and exit 0 when every anchor holds; index: <file> TAB <suite>[,<suite>] per anchored file. <root> defaults to the current tree, --at reads a commit"
  die "  bash ${HOOK_DIR}/session-poker.sh matrix-render   write the bound plan's ## Verification Matrix AC blocks from its ## Eval design: provenance, fails-when, eval, task, evidence: pending, and user-confirmed: pending at a T4 row; adds only what is missing"
  die "  bash ${HOOK_DIR}/session-poker.sh discharge <AC-id>   write that matrix row's auditor cell as the bare token CONFIRMED, nothing after it"
  die "  bash ${HOOK_DIR}/session-poker.sh matrix-set <AC-id> [status=<pending|blocked|discharged|waived>] [evidence=<record/...>] [task=<id>[,<id>...]]   write that matrix row's status and evidence cells and its AC block's evidence: and task: keys; never the tier or auditor cell"
  die "  bash ${HOOK_DIR}/session-poker.sh waive-row <AC-id> '<the user's words>' '<why>'   waive that matrix row on words the user typed in this session: its block's waiver: line and its status waived"
  die "  bash ${HOOK_DIR}/session-poker.sh tasks-prose '<text>' [--replace '<first words>']   write a one-line paragraph under ## Tasks, below the table; --replace rewrites the paragraph opening with those words"
  die "  bash ${HOOK_DIR}/session-poker.sh epic-row <wave> <col>=<val>... [--plan <plan>]   set cells of that wave's row in the shipped table of the epic.plan.md beside the run's plan"
  die "  bash ${HOOK_DIR}/session-poker.sh continuation-fill '<field>=<text>' [--plan <plan>]   fill the run's continuation's <fill: field...> mark with the text"
  die "  bash ${HOOK_DIR}/session-poker.sh handoff   rewrite the bound plan's ## Handoff in place: written: (date -u), the working and integration heads, the open rows, the live agents and the last proof, with the five human lines carried; never written by hand"
  die "  bash ${HOOK_DIR}/session-poker.sh brief <row>   render that plan row's dispatch brief into record/<wave>/briefs/<row>.md: the scaffold fields from the row and the shipped scaffold, the working head, and ## Judgment marked for what only the orchestrator writes; a second call keeps what is written under ## Judgment"
  die "  bash ${HOOK_DIR}/session-poker.sh task-split <id> -- <child spec>…   rewrite one pending row as its children, each <id>:<task>:<size>:<Files>: the parent dropped with split-into, its Files partitioned, every row that waited on it waiting on a child, one validated transaction"
  die "  bash ${HOOK_DIR}/session-poker.sh debt add <record> [<plan>]   write one record/<run>/debt.md line per debt: line of the record (a reading's, a writer's, an assumptions.md hole line), each concept and kind once"
  die "  bash ${HOOK_DIR}/session-poker.sh debt touched <concept> [<plan>]   add one to the touches of each unburned item of <concept> (the dispatch wall's call)"
  die "  bash ${HOOK_DIR}/session-poker.sh debt burn <concept> <row> [<plan>]   mark each unburned item of <concept> burned by <row>"
  die "  bash ${HOOK_DIR}/session-poker.sh debt adopt <continuation> [<plan>]   write each debt: line the continuation carries under ## Deferrals into the run's ledger, its touches and raised-by kept"
  die "  bash ${HOOK_DIR}/session-poker.sh debt list [<plan>]   print the run's debt ledger, one line per item"
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
  # A RULING AND ITS READS (wave-33 T10; REQ-1, D1). `rule` takes the writer and the text, which must
  # hold something once blanks are gone: a ruling with nothing to say is nothing to deliver. `ruling-ack`
  # takes the one id the push printed; `rulings` the writer whose rulings to read.
  # `--words '<the user's words>'` (wave-36 T9; D10) quotes what the person typed: held to lib/said.sh
  # `user_said` across the run's recorded sessions, and carried in the ruling as `words="…" session=<sid>`.
  rule)
    RULE_WORDS=""
    if [ $# -eq 4 ] && [ "$3" = --words ]; then
      [ -n "${4//[[:space:]]/}" ] || usage "rule --words takes the user's words, quoted from a prompt they typed."
      RULE_WORDS="$4"; set -- "$1" "$2"
    fi
    if [ $# -ne 2 ] || [ -z "${1//[[:space:]]/}" ] || [ -z "${2//[[:space:]]/}" ]; then
      usage "rule takes two arguments, the writer's roster name and the ruling's text, and optionally --words '<the user's words>'."
    fi
    RULE_WRITER="$1"
    RULE_TEXT="$2"
    ;;
  ruling-ack)
    { [ $# -eq 1 ] && [ -n "${1//[[:space:]]/}" ]; } || usage "ruling-ack takes exactly one argument: the ruling's id."
    RULING_ID="$1"
    ;;
  rulings)
    { [ $# -eq 1 ] && [ -n "${1//[[:space:]]/}" ]; } || usage "rulings takes exactly one argument: the writer's roster name."
    RULE_WRITER="$1"
    ;;
  # THE FILL'S ANSWER, AS HOLD IS THE STAND-DOWN'S (wave-27 T34; REQ-15, D24). Two operands: the
  # ready rows, comma-joined, and the reason. No ids is the usage error, never "every row": a
  # decline names what it answers. A blank reason is no reason, as for hold.
  # `--on <row>` (wave-30 T16; REQ-12 AC-12.7, Δ13) names the row the hold waits on; it changes what
  # the verb prints and the ledger's `declined-on=`. A value that is no row of the plan (a file, a word)
  # is the verb's refusal, nothing recorded (wave-33 T7, AC-4.3). `--on` with no value is the usage
  # error, as a missing reason is.
  # `decline lift [<ids>]` (wave-35 T8; REQ-6 AC-6.2; D15) ends the standing decline for the rows named,
  # comma-joined, or for every row it answers when none is named. More than one operand is the usage error.
  decline)
    DC_ON=""; DC_LIFT=""
    if [ $# -ge 1 ] && [ "$1" = lift ]; then
      [ $# -le 2 ] || usage "decline lift takes at most one operand: the row ids to lift, comma-joined; with none it lifts every row the standing decline answers."
      DC_LIFT=yes; DC_IDS="${2:-}"; DC_REASON=""
      [ -z "$DC_IDS" ] || [ -n "${DC_IDS//[[:space:],]/}" ] || usage "decline lift: '$DC_IDS' names no row id."
      set --
    fi
    if [ -n "$DC_LIFT" ]; then
      :
    elif [ $# -eq 4 ] && [ "$3" = "--on" ] && [ -n "${4//[[:space:]]/}" ]; then
      DC_ON="$4"; set -- "$1" "$2"
    fi
    if [ -z "$DC_LIFT" ]; then
      if [ $# -ne 2 ] || [ -z "${1//[[:space:],]/}" ] || [ -z "${2//[[:space:]]/}" ]; then
        usage "decline takes two arguments, the ready row ids, comma-joined, and the reason, then optionally --on <row>, the row they wait on. There is no form that declines every row. decline lift [<ids>] ends one."
      fi
      DC_IDS="$1"
      DC_REASON="$2"
    fi
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
  # THE REGRESSION SETTING (wave-31 T27; REQ-12; D4). `yes` or `no` and the user's reply, verbatim;
  # the value's own shape is the verb's refusal (1), a missing operand or reply the usage error.
  regression)
    if [ $# -ne 2 ] || [ -z "${2//[[:space:]]/}" ]; then
      usage "regression takes exactly two arguments: yes or no, and the user's reply, verbatim."
    fi
    RG_V="$1"
    RG_REPLY="$2"
    ;;
  # THE NINE CELLS AN AUTHOR WRITES, IN THE TABLE'S OWN COLUMN ORDER (wave-20 REQ-5, AC-5.3;
  # Δ5). `status`, `worktree` and `base` are the dispatcher's cells and are not operands:
  # a new row is `pending` and names no tree. Every operand is required — `—` is how the
  # table itself spells "none" — so a short list is the usage error, never a guessed default.
  # THE TENTH, `<reads>`, IS THE ONE OPTIONAL CELL (wave-26 T59; REQ-5 AC-5.4): the reads column
  # a table may carry (wave-26 T2), from which the row's edges are computed. Left off, the row
  # is written exactly as the nine-operand form always wrote it.
  # `--born '<rating>'` (wave-30 T21; REQ-10 AC-10.2, D4) marks a row review made unasked: it comes
  # last, after the operands, as `decline`'s `--on` does, and its value is `review S<n> <on|off>`, the
  # rating the reader wrote. A missing or malformed value is the usage error; whether the rating may
  # become a row (fix-policy:, fix-cap:, the fourth fix on a component) is the verb's refusal (1).
  # `--born <record>#<n>[,<record>#<n>…]` (wave-33 T13; REQ-5, D6) names the findings the row answers, each a
  # finding of a registered reading: the rating is then read from the record, never typed. A value of neither
  # shape is the usage error; a finding the plan has not registered is the verb's refusal (1).
  # `--born floor:<suite>` (wave-36 T7; REQ-3, D9) marks a row born of the floor's red in <suite>, named by its file
  # name (`<name>.test.sh`, the key the floor's records use): the line ends ` born: floor <suite>`, which the judge
  # holds the row's landing by (lib/proof.sh `_facts_born_landings`). It is no review-born row, so fix-policy: and
  # fix-cap: do not hold it. Any other `floor:` value is the usage error. THE MARKER NAMES ITS RED (wave-36 T42; D9,
  # Δ8): the verb admits it only when the plan's floor proof owes the suite or the landing record holds an `ev=standing`
  # event for it at a commit on the working branch (`born_floor_backing`), and writes ` born: floor <suite> of=floor`
  # or ` of=standing@<12-hex>` to say which; with neither it is refused naming both facts.
  task-add)
    TA_BORN=""; TA_BORN_IDS=""; TA_BORN_FLOOR=""
    case "${*: -1}" in --born) usage "task-add: --born takes a value: the findings the row answers, <record>#<n>[,<record>#<n>…], 'review S<n> <on|off>', the reader's rating, or floor:<suite>, the suite whose floor red the row fixes." ;; esac
    if [ $# -ge 2 ] && [ "${*: -2:1}" = "--born" ]; then
      TA_BORN="${*: -1}"
      case "$TA_BORN" in
        'review S'[1-4]' on'|'review S'[1-4]' off') : ;;
        floor:*)
          TA_BORN_FLOOR="${TA_BORN#floor:}"; TA_BORN=""
          case "$TA_BORN_FLOOR" in
            *[!A-Za-z0-9._-]*|.test.sh|'') TA_BORN_FLOOR="" ;;
            *.test.sh) : ;;
            *) TA_BORN_FLOOR="" ;;
          esac
          [ -n "$TA_BORN_FLOOR" ] || usage "task-add: --born '${*: -1}' names no suite; write floor:<suite>, the suite's file name (<name>.test.sh) whose floor red the row fixes." ;;
        *)
          TA_BORN_IDS="$TA_BORN"; TA_BORN=""
          case "$TA_BORN_IDS" in
            *[[:space:]]*|,*|*,|*,,*) usage "task-add: --born '$TA_BORN_IDS' is neither findings nor a rating; write <record>#<n>[,<record>#<n>…], or 'review S<n> <on|off>', n 1 to 4." ;;
          esac
          for TA_BID in $(printf '%s' "$TA_BORN_IDS" | tr ',' ' '); do
            case "$TA_BID" in
              ?*#[1-9]|?*#[1-9]*[0-9]) case "${TA_BID##*#}" in *[!0123456789]*) TA_BID="" ;; esac ;;
              *) TA_BID="" ;;
            esac
            [ -n "$TA_BID" ] || usage "task-add: --born '$TA_BORN_IDS' is neither findings nor a rating; write <record>#<n>[,<record>#<n>…], or 'review S<n> <on|off>', n 1 to 4."
          done ;;
      esac
      set -- "${@:1:$(($# - 2))}"
    fi
    if [ $# -ne 9 ] && [ $# -ne 10 ]; then
      usage "task-add takes nine arguments and an optional tenth: <id> <step> <kind> <task> <agent> <deps> <size> <serves> <Files> [<reads>] (write — for none), then optionally --born <record>#<n>[,…], --born 'review S<n> <on|off>' or --born floor:<suite>."
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
    AMEND_FILES=""; AMEND_SUITES=""; AMEND_RUNS=""; AMEND_REASON=""; AMEND_BY=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --files+|--suites+|--reexec+|--reason|--by)
          if [ $# -lt 2 ] || [ -z "$2" ]; then usage "amend: $1 takes a value."; fi
          case "$2" in --*) usage "amend: $1 takes a value, and got the flag $2." ;; esac
          case "$1" in
            --files+)  AMEND_FILES="${AMEND_FILES}$2"$'\n' ;;
            --suites+) AMEND_SUITES="${AMEND_SUITES}$2"$'\n' ;;
            # A RUN AS THE BRIEF MARKS IT (wave-31 T11; REQ-8 AC-8.1, D9). A brief writes a run
            # between backticks, so `--reexec+ '`cmd`'` is the spelling a reader pastes; the span
            # wraps each value in its own pair, and a kept pair made ``cmd`` — an empty entry either
            # side and a repeat read as new. One matched pair comes off here, so the marked and the
            # bare spelling are one addition.
            --reexec+)
              _am_r="$2"
              case "$_am_r" in \`?*\`) _am_r="${_am_r#\`}"; _am_r="${_am_r%\`}" ;; esac
              AMEND_RUNS="${AMEND_RUNS}${_am_r}"$'\n' ;;
            --reason)  AMEND_REASON="$2" ;;
            # WHO WIDENED IT (wave-31 T11; REQ-8 AC-8.3, D9, A-orch-46.2). The Bash wall's arm A
            # admits a writer's Files amend of its own roster row and stages the call with
            # `--by writer`; this verb cannot see its caller, so the flag is how the row says who.
            --by)
              [ "$2" = writer ] || usage "amend: --by takes only writer, and got $2."
              AMEND_BY="$2" ;;
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
    # A REASON, TRAILING (wave-36 T14; D13, AC-7.7): `task-set … --reason '<why>'` also writes the session's own
    # delivered plan (bound-closed), and records the reason on each row's `- T<n>:` line. Taken off the end, as
    # epic-row's `--plan` is, before the groups are read.
    PV_REASON=""
    if [ "$VERB" = task-set ] && [ $# -ge 2 ] && [ "${*: -2:1}" = --reason ]; then
      PV_REASON="${*: -1}"; set -- "${@:1:$(($# - 2))}"
      [ -n "${PV_REASON//[[:space:]]/}" ] || usage "task-set: --reason takes why the cells are set."
    fi
    if [ $# -lt 2 ] || [ -z "$1" ]; then
      usage "$VERB takes an id and at least one <column>=<value>."
    fi
    PV_ARGS=("$@")
    # MANY ROWS, ONE TRANSACTION (wave-33 T7; REQ-4 AC-4.1, D8; A-orch-6). `task-set` takes groups,
    # `<id>[,<id>…] <col>=<val>…`, joined by `--`: each group's cells are set on each of its rows, and the
    # table is judged once, after every group, so a restructure that is invalid at every single-row step
    # can be made. A group is held as its ids and its pairs joined by the unit separator.
    PV_GROUPS=()
    if [ "$VERB" = task-set ]; then
      _pv_g="$1"; _pv_n=0; shift
      for _pv_a in "$@" --; do
        if [ -z "$_pv_g" ]; then
          case "$_pv_a" in ''|--|*=*) usage "task-set: each -- is followed by <id>[,<id>…], then at least one <column>=<value>." ;; esac
          _pv_g="$_pv_a"; _pv_n=0; continue
        fi
        case "$_pv_a" in
          --) [ "$_pv_n" -gt 0 ] || usage "task-set takes at least one <column>=<value> after $(clean "$_pv_g")."
              PV_GROUPS+=("$_pv_g"); _pv_g="" ;;
          [!=]*=*) _pv_g="$_pv_g"$'\037'"$_pv_a"; _pv_n=$((_pv_n + 1)) ;;
          *) usage "$VERB: '$_pv_a' is not <column>=<value>." ;;
        esac
      done
      set -- "${PV_ARGS[@]}"
    fi
    PV_ID="$1"; shift
    if [ "$VERB" != task-set ]; then
      for _pv_a in "$@"; do
        case "$_pv_a" in
          [!=]*=*) : ;;
          *) usage "$VERB: '$_pv_a' is not <column>=<value>." ;;
        esac
      done
    fi
    PV_PAIRS=("$@")
    ;;
  # THE MATRIX ROW'S CELLS AND BLOCK KEYS (wave-33 T7; REQ-4 AC-4.1, D8). An AC id, as discharge takes it,
  # then at least one `<key>=<value>`. The keys and the values are the verb's own refusals (1).
  matrix-set)
    { [ $# -ge 2 ] && [ -n "$1" ]; } || usage "matrix-set takes <AC> and at least one of status=<pending|blocked|discharged|waived>, evidence=<record/…>, task=<ids>."
    case "$1" in
      *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*)
        usage "matrix-set: '$(printf '%s' "${1:0:24}" | tr -d '[:cntrl:]')' is not a criterion id: letters, digits, '.', '_' or '-'." ;;
    esac
    MS_AC="$1"; shift
    for _pv_a in "$@"; do
      case "$_pv_a" in [!=]*=*) : ;; *) usage "matrix-set: '$_pv_a' is not <key>=<value>." ;; esac
    done
    MS_PAIRS=("$@")
    ;;
  # THE ROW WAIVER (wave-33 T7; REQ-4 AC-4.1, D8). Three operands, finding-move's last two: the user's words
  # as typed and why. Whether the words stand in a typed prompt is the verb's own refusal (1).
  waive-row)
    WR_USAGE="waive-row takes <AC>, the user's words as typed, and why."
    { [ $# -eq 3 ] && [ -n "$1" ] && [ -n "${2//[[:space:]]/}" ] && [ -n "${3//[[:space:]]/}" ]; } || usage "$WR_USAGE"
    case "$1" in
      *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*)
        usage "waive-row: '$(printf '%s' "${1:0:24}" | tr -d '[:cntrl:]')' is not a criterion id: letters, digits, '.', '_' or '-'." ;;
    esac
    WR_AC="$1"; WR_RAW="$2"; WR_WHY_RAW="$3"
    ;;
  # A PROSE PARAGRAPH UNDER ## Tasks (wave-33 T7; REQ-4 AC-4.1, D8). The text, then optionally
  # `--replace '<first words>'`, naming the paragraph it rewrites.
  tasks-prose)
    TP_REPLACE=""; TP_HASREP=0
    if [ $# -eq 3 ] && [ "$2" = --replace ]; then TP_HASREP=1; TP_REPLACE="$3"; set -- "$1"; fi
    { [ $# -eq 1 ] && [ -n "${1//[[:space:]]/}" ]; } || usage "tasks-prose takes '<text>', then optionally --replace '<the first words of the paragraph it rewrites>'."
    [ "$TP_HASREP" = 0 ] || [ -n "${TP_REPLACE//[[:space:]]/}" ] || usage "tasks-prose: --replace takes the first words of the paragraph it rewrites."
    TP_TEXT="$1"
    ;;
  # THE EPIC'S SHIPPED ROW AND THE RUN'S CONTINUATION (wave-33 T7; REQ-3 AC-3.3, D8). Each takes its operands,
  # then optionally `--plan <plan>`, the run they belong to, which a session close-out unbound must name.
  epic-row|continuation-fill)
    PV_PLAN_ARG=""
    if [ $# -ge 2 ] && [ "${*: -2:1}" = --plan ]; then
      PV_PLAN_ARG="${*: -1}"; set -- "${@:1:$(($# - 2))}"
      [ -n "${PV_PLAN_ARG//[[:space:]]/}" ] || usage "$VERB: --plan takes the run's plan."
    fi
    if [ "$VERB" = epic-row ]; then
      [ $# -ge 2 ] || usage "epic-row takes <wave> and at least one <column>=<value>, then optionally --plan <plan>."
      case "$1" in ''|*[!0123456789]*) usage "epic-row: '$(printf '%s' "${1:0:12}" | tr -d '[:cntrl:]')' is not a wave number." ;; esac
      EP_WAVE="$1"; shift
      for _pv_a in "$@"; do
        case "$_pv_a" in [!=]*=*) : ;; *) usage "epic-row: '$_pv_a' is not <column>=<value>." ;; esac
      done
      EP_PAIRS=("$@")
    else
      [ $# -eq 1 ] || usage "continuation-fill takes '<field>=<text>', then optionally --plan <plan>."
      case "$1" in [!=]*=*) : ;; *) usage "continuation-fill: '$(printf '%s' "${1:0:24}" | tr -d '[:cntrl:]')' is not <field>=<text>." ;; esac
      CF_FIELD="$(printf '%s' "${1%%=*}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"; CF_TEXT="${1#*=}"
      [ -n "${CF_TEXT//[[:space:]]/}" ] || usage "continuation-fill: the text for '$CF_FIELD' is empty."
    fi
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
    PV_ID="$1"; RL_COMMIT="$2"; RL_AT="$3"; RL_ARTIFACT=""
    ;;
  # A RECORD ROW LANDS ITSELF (wave-33 T6; REQ-3 AC-3.1, D5): the row id alone. The commit is the
  # working head and the instant is now, both the verb's, so neither is an operand.
  deliver)
    [ $# -eq 1 ] && [ -n "$1" ] || usage "deliver takes one argument: the row id (the head and the instant are the verb's own)."
    PV_ID="$1"; RL_COMMIT=""; RL_AT=""; RL_ARTIFACT=""; RL_BY=""; RL_WHY=""; RL_HAND=0
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
  # THE STEP-FIELD VERB (wave-28 T8; REQ-3 AC-3.5, D17): a step and one `<key>=<value>`. The shapes are the
  # usage error's (2); the key set, the line break, a step with no line and Step 9 are the verb's own refusals (1).
  step-field)
    if [ $# -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
      usage "step-field takes <N> <key>=<value>: a step number and one field."
    fi
    case "$1" in
      [0-9]|[0-9][ab]) : ;;
      *) usage "step-field: '$(printf '%s' "${1:0:12}" | tr -d '[:cntrl:]')' is not a step number (0-9, 4a)." ;;
    esac
    case "$2" in
      [!=]*=*) : ;;
      *) usage "step-field: '$(printf '%s' "${2:0:24}" | tr -d '[:cntrl:]')' is not <key>=<value>." ;;
    esac
    [ -n "${2#*=}" ] || usage "step-field: the value of '$(printf '%s' "${2%%=*}" | cut -c 1-24 | tr -d '[:cntrl:]')' is empty."
    PV_KEY="$1"; PV_FKEY="${2%%=*}"; PV_FVAL="${2#*=}"
    ;;
  current)
    [ $# -eq 1 ] && [ -n "$1" ] || usage "current takes one argument: the step number (0-8) to move to."
    case "$1" in
      9|9a|9b|[0-8]|[0-8][ab]) : ;;
      *) usage "current: '$1' is not a step number (0-8); current: is a step number at every scale." ;;
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
    PF_USAGE="proof-add takes two arguments, <floor|review|task> <evidence path under record/>, and for a reading two flags more: proof-add review <record> --question <evidence|adversarial|structure> --reader <roster name> (the head is the one the evidence names, the head= line of a run log or the end of the reviewed: a..b line of a review, never an operand); proof-add floor takes one log or several, proof-add floor <log> [<log>…], each opening head=<40-hex> dirty=0 and ending rc=0; or proof-add inherited <suite file name>, which runs that suite at the plan's base-sha: in a scratch tree."
    if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]; then usage "$PF_USAGE"; fi
    # SEVERAL LOGS ON ONE LINE (wave-36 T35; D13, AC-7.10): a floor may be the logs of several runners, each its own
    # operand after the first, newline-joined in PF_EVIDS (a path holding a line break is refused below, by name).
    PF_KIND="$1"; PF_EVID="$2"; PF_EVIDS="$2"; PF_QUESTION=""; PF_READER=""; shift 2
    while [ $# -gt 0 ]; do
      case "$1" in
        --question) [ $# -ge 2 ] && [ -n "$2" ] && [ -z "$PF_QUESTION" ] || usage "$PF_USAGE"; PF_QUESTION="$2"; shift 2 ;;
        --reader)   [ $# -ge 2 ] && [ -n "$2" ] && [ -z "$PF_READER" ] || usage "$PF_USAGE"; PF_READER="$2"; shift 2 ;;
        -*|'') usage "$PF_USAGE" ;;
        *$'\n'*) usage "$PF_USAGE" ;;
        *[!0123456789abcdefABCDEF]*|*/*) [ "$PF_KIND" = floor ] || usage "$PF_USAGE"; PF_EVIDS="$PF_EVIDS
$1"; shift ;;
        *) usage "$PF_USAGE" ;;   # a bare hex word is a head, and a head is never an operand
      esac
    done
    if [ -n "$PF_QUESTION$PF_READER" ]; then
      { [ -n "$PF_QUESTION" ] && [ -n "$PF_READER" ] && [ "$PF_KIND" = review ]; } || usage "$PF_USAGE"
    fi
    # INHERITED TAKES A SUITE'S FILE NAME (wave-35 T9; AC-1.6): a word of letters, digits, `.`, `_` and `-`, so
    # the line it writes and the path it runs hold nothing else.
    if [ "$PF_KIND" = inherited ]; then
      case "${PF_EVID##*/}" in ''|*[!A-Za-z0-9._-]*) usage "$PF_USAGE" ;; esac
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
  # FOUR OPERANDS (wave-28 T42; D34): the finding (`<record>#<n>`), where it goes (defer or fix), the
  # user's words as typed and why. A missing or blank operand, another direction or an id of another
  # shape is the usage error; whether the words stand in a typed prompt is the verb's own refusal (1).
  # OR THREE (wave-36 T8; D9): the finding, `fixed`, and the row that fixed it, `T<n>`; words or a why
  # after it are the usage error. Whether the plan's table carries the row is the verb's own refusal (1).
  finding-move)
    FM_USAGE="finding-move takes <record>#<n>, defer or fix, the user's words as typed, and why; or <record>#<n>, fixed, and the row that fixed it."
    FM_ROW=""
    case "${2:-}" in
      defer|fix) [ $# -eq 4 ] && [ -n "${3//[[:space:]]/}" ] && [ -n "${4//[[:space:]]/}" ] || usage "$FM_USAGE" ;;
      fixed)
        [ $# -eq 3 ] || usage "$FM_USAGE"
        case "$3" in T[0123456789]*) : ;; *) usage "$FM_USAGE" ;; esac
        case "${3#T}" in *[!0123456789]*) usage "$FM_USAGE" ;; esac
        FM_ROW="$3" ;;
      *) usage "$FM_USAGE" ;;
    esac
    case "$1" in
      *?#[0123456789]*) : ;;
      *) usage "finding-move: '$1' is not <record>#<n>." ;;
    esac
    case "${1##*#}" in *[!0123456789]*) usage "finding-move: '$1' is not <record>#<n>." ;; esac
    FM_ID="$1"; FM_TO="$2"; FM_RAW="${3:-}"; FM_WHY_RAW="${4:-}"
    [ -z "$FM_ROW" ] || FM_RAW=""
    ;;
  # NO OPERAND RENDERS; FOUR OR FIVE RULE (wave-33 T13; REQ-5 AC-5.1, D6): the finding (`<record>#<n>`), fix or
  # defer, the person's words as typed, why, and for a deferral optionally its changelog sentence. Another count,
  # a direction, an id of another shape or a sentence on a fix is the usage error; the rules the ruling is held to
  # are finding-move's and finding-stated's, the verb's own refusals (1).
  disposition)
    DSP_USAGE="disposition takes no argument (it renders every finding of the registered readings), or <record>#<n>, fix or defer, the person's words as typed, why, and for defer optionally its changelog sentence."
    DSP_ID=""; DSP_TO=""; DSP_RAW=""; DSP_WHY=""; DSP_SENT=""
    if [ $# -gt 0 ]; then
      { [ $# -eq 4 ] || [ $# -eq 5 ]; } && [ -n "${3//[[:space:]]/}" ] && [ -n "${4//[[:space:]]/}" ] || usage "$DSP_USAGE"
      case "$2" in defer|fix) : ;; *) usage "$DSP_USAGE" ;; esac
      case "$1" in
        *?#[0123456789]*) : ;;
        *) usage "disposition: '$1' is not <record>#<n>." ;;
      esac
      case "${1##*#}" in *[!0123456789]*) usage "disposition: '$1' is not <record>#<n>." ;; esac
      if [ $# -eq 5 ]; then
        [ "$2" = defer ] && [ -n "${5//[[:space:]]/}" ] || usage "$DSP_USAGE"
      fi
      DSP_ID="$1"; DSP_TO="$2"; DSP_RAW="$3"; DSP_WHY="$4"; DSP_SENT="${5:-}"
    fi
    ;;
  # NO OPERAND (wave-27 T16; D12): the range is the verb's own, from the last release to the working
  # head, so a base typed on the command line is the usage error, as a head is for proof-add.
  release-check)
    [ $# -eq 0 ] || usage "release-check takes no arguments: it runs from the nearest tag reachable from the plan's integration-branch that is a proper ancestor of the working head (else its base-sha) to that head."
    ;;
  # NO OPERAND (wave-28 T75; D36): the command is the project's `floor:`, else its tests/run.sh (wave-35 T10), and the
  # head is the working one.
  floor-run)
    [ $# -eq 0 ] || usage "floor-run takes no arguments: it runs .bionic/config.yaml's floor: command, else tests/run.sh, at the working branch's head."
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
    LR_ROWS=no; LR_HH=no; LR_ARG=""
    for _lr_a in "$@"; do
      case "$_lr_a" in
        --rows) [ "$LR_ROWS" = no ] || usage "landing-report takes --rows once."; LR_ROWS=yes ;;
        --hand-holds) [ "$LR_HH" = no ] || usage "landing-report takes --hand-holds once."; LR_HH=yes ;;
        -*) usage "landing-report takes the flags --rows and --hand-holds, and at most one plan." ;;
        *) [ -z "$LR_ARG" ] || usage "landing-report takes the flags --rows and --hand-holds, and at most one plan."; LR_ARG="$_lr_a" ;;
      esac
    done
    ;;
  # THE BASIS VERB (wave-37 T8; D8, REQ-4 AC-4.2). Two operands: the question the judge holds a range by, and
  # the range `<a>..<b>` its `review <q> … uncovered <a>..<b>` line names. Read-only; the lines are
  # `cover_basis`'s, the ones `cur7_judge` prints under that line. The shape of the range is the usage error (2);
  # whether both ends are commits here is the verb's refusal (1).
  cover)
    { [ $# -eq 2 ] && [ -n "$1" ] && [ -n "$2" ]; } || usage "cover takes a question and a range: cover <evidence|adversarial|structure> <a>..<b>."
    case "$1" in evidence|adversarial|structure) : ;; *) usage "cover: '$(printf '%s' "${1:0:24}" | tr -d '[:cntrl:]')' is not a question; it is evidence, adversarial or structure." ;; esac
    COV_Q="$1"; COV_A="${2%%..*}"; COV_B="${2#*..}"
    case "$2" in
      *..*) : ;;
      *) usage "cover takes its range as <a>..<b>, two commits and nothing else." ;;
    esac
    case "$COV_A:$COV_B" in
      :*|*:|-*|*:-*|*..*|*[[:space:]]*|*[[:cntrl:]]*) usage "cover takes its range as <a>..<b>, two commits and nothing else." ;;
    esac
    ;;
  # THE RUN VERBS (wave-30 T12; D6, D7d). `wait` and `stop-run` take ONE operand: a roster row's name,
  # a run id (`run=` as the shim printed it), or a run's log path. `wait` takes `--for <seconds>`, a
  # bound on this call (75 when it runs out, the run untouched); `stop-run` takes `--report-only`, the
  # promise that word makes on adopt and sweep. `regression-runs` takes `--write` only.
  wait)
    WT_ARG=""; WT_FOR=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --for) [ $# -ge 2 ] || usage "wait --for takes a number of seconds."; WT_FOR="$2"; shift 2 ;;
        -*) usage "wait takes one name and at most --for <seconds>." ;;
        *) [ -z "$WT_ARG" ] || usage "wait takes one name."; WT_ARG="$1"; shift ;;
      esac
    done
    [ -n "$WT_ARG" ] || usage "wait takes the name of a roster row (or a run id) whose run to wait on."
    case "$WT_FOR" in '') : ;; *[!0-9]*) usage "wait --for takes whole seconds." ;; esac
    ;;
  stop-run)
    SR_ARG=""; SR_REPORT_ONLY=no; SR_WHY=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --report-only) SR_REPORT_ONLY=yes; shift ;;
        --why) [ $# -ge 2 ] || usage "stop-run --why takes the reason, one line."; SR_WHY="$2"; shift 2 ;;
        -*) usage "stop-run takes one name, run id or gate request id, and at most --report-only and --why '<reason>'." ;;
        *) [ -z "$SR_ARG" ] || usage "stop-run takes one name."; SR_ARG="$1"; shift ;;
      esac
    done
    [ -n "$SR_ARG" ] || usage "stop-run takes the name of a roster row (or a run id, or a gate request id) whose run to stop."
    case "$SR_WHY" in *$'\n'*|*$'\r'*|*'|'*) usage "stop-run --why takes one line, without a '|'." ;; esac
    ;;
  regression-runs)
    RR_WRITE=no
    if [ $# -eq 1 ] && [ "$1" = --write ]; then RR_WRITE=yes
    elif [ $# -ne 0 ]; then usage "regression-runs takes at most one flag: --write."; fi
    ;;
  # THE ANCHORS (wave-35 T3; D16, D9). Read-only and session-free, so it runs here and exits: the extractor,
  # the check and the index are lib/anchors.sh's, loaded on demand rather than through BIONIC_LIB_WANT, so a
  # copied hook resolving an older library still loads (.claude/rules/lib-changes-in-worktrees.md).
  anchors)
    AN_SUB="${1:-}"; [ $# -eq 0 ] || shift
    case "$AN_SUB" in check|index) ;; *) usage "anchors takes check or index." ;; esac
    AN_ROOT=""; AN_AT=-
    while [ $# -gt 0 ]; do
      case "$1" in
        --at) [ -n "${2:-}" ] || usage "anchors --at takes a commit."; AN_AT="$2"; shift 2 ;;
        -*) usage "unknown flag for anchors: $1" ;;
        *) [ -z "$AN_ROOT" ] || usage "anchors takes at most one root."; AN_ROOT="$1"; shift ;;
      esac
    done
    [ -n "$AN_ROOT" ] || AN_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || AN_ROOT=""
    [ -n "$AN_ROOT" ] || AN_ROOT="$PWD"
    [ -d "$AN_ROOT" ] || { echo "poker: anchors: no directory $AN_ROOT" >&2; exit 2; }
    [ -n "$BIONIC_LIB" ] && [ -r "$BIONIC_LIB/anchors.sh" ] && . "$BIONIC_LIB/anchors.sh" \
      || { echo "poker: anchors: cannot load ${BIONIC_LIB:-the bionic library}/anchors.sh" >&2; exit 2; }
    if [ "$AN_AT" != - ]; then
      git -C "$AN_ROOT" rev-parse --verify -q "${AN_AT}^{commit}" >/dev/null 2>&1 \
        || { echo "poker: anchors: no commit $AN_AT in $AN_ROOT" >&2; exit 2; }
    fi
    if [ "$AN_SUB" = check ]; then anchors_check "$AN_ROOT" "$AN_AT"; exit $?; fi
    anchors_index "$AN_ROOT" "$AN_AT"; exit 0
    ;;
  # THE MATRIX VERBS (wave-30 T14; D9). matrix-render takes nothing — the bound plan is the operand every plan
  # verb has; discharge takes the one criterion id, spelled as the matrix table spells it.
  matrix-render)
    [ $# -eq 0 ] || usage "matrix-render takes no argument: it renders the bound plan's matrix from its ## Eval design."
    ;;
  handoff)
    [ $# -eq 0 ] || usage "handoff takes no argument: it rewrites the bound plan's ## Handoff from the plan and the machine."
    ;;
  # THE BRIEF, RENDERED FROM ITS ROW (wave-33 T9; REQ-4 AC-4.4, D8). The one operand is the plan row's id; the
  # id's own shape, and whether the plan has the row, are the verb's refusal (1).
  brief)
    { [ $# -eq 1 ] && [ -n "$1" ]; } || usage "brief takes exactly one argument: the plan row's id, as in: brief T2."
    BRF_ID="$1"
    ;;
  # THE SPLIT (wave-30 T17; D14d-3, design-ledger Δ11). The row, `--`, then two or more child specs
  # `<id>:<task>:<size>:<Files>`: the id before the first colon, the Files after the last, the size
  # before that, and the task between, which may hold a colon of its own. A spec of another shape,
  # or one leaving its id, task or size empty, is the usage error; what the plan can hold is the verb's.
  task-split)
    { [ $# -ge 4 ] && [ -n "$1" ] && [ "$2" = -- ]; } \
      || usage "task-split takes <id> -- <child spec> <child spec>…: two or more children, each <id>:<task>:<size>:<Files> (write — for no Files)."
    TS_ID="$1"; shift 2
    TS_ARGS=(); TS_CHECK=(); TS_IDS=""
    for _ts_s in "$@"; do
      case "$_ts_s" in
        *$'\n'*|*$'\r'*) usage "task-split: a child spec holds a line break; each child is <id>:<task>:<size>:<Files>." ;;
        *:*:*:*) : ;;
        *) usage "task-split: '$(printf '%s' "${_ts_s:0:40}" | tr -d '[:cntrl:]')' is not <id>:<task>:<size>:<Files>." ;;
      esac
      _ts_id="${_ts_s%%:*}"; _ts_r="${_ts_s#*:}"; _ts_f="${_ts_r##*:}"; _ts_r="${_ts_r%:*}"
      _ts_z="${_ts_r##*:}"; _ts_t="${_ts_r%:*}"
      { [ -n "${_ts_id//[[:space:]]/}" ] && [ -n "${_ts_t//[[:space:]]/}" ] && [ -n "${_ts_z//[[:space:]]/}" ]; } \
        || usage "task-split: '$(printf '%s' "${_ts_s:0:40}" | tr -d '[:cntrl:]')' leaves its id, task or size empty; each child is <id>:<task>:<size>:<Files>."
      TS_ARGS+=("$_ts_id" "$_ts_t" "$_ts_z" "$_ts_f"); TS_CHECK+=("$_ts_id" "$_ts_f")
      TS_IDS="${TS_IDS:+$TS_IDS, }$_ts_id"
    done
    ;;
  discharge)
    { [ $# -eq 1 ] && [ -n "$1" ]; } || usage "discharge takes exactly one argument: the criterion (AC-<n>.<m>) whose auditor cell becomes CONFIRMED."
    case "$1" in
      *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*)
        usage "discharge: '$(printf '%s' "${1:0:24}" | tr -d '[:cntrl:]')' is not a criterion id: letters, digits, '.', '_' or '-'." ;;
    esac
    DS_AC="$1"
    ;;
  # THE DEBT LEDGER (wave-30 T22; D2, P2, AC-11.2, AC-11.3). A subcommand, its operands, and at most one
  # plan last, which names the run as landing-report's does; without it, the session's bound run.
  debt)
    DEBT_SUB="${1:-}"; [ $# -eq 0 ] || shift
    DEBT_A=""; DEBT_B=""; DEBT_PLAN_ARG=""
    case "$DEBT_SUB" in
      add)     { [ $# -ge 1 ] && [ $# -le 2 ]; } || usage "debt add takes a record and at most one plan."
               DEBT_A="$1"; DEBT_PLAN_ARG="${2:-}" ;;
      touched) { [ $# -ge 1 ] && [ $# -le 2 ]; } || usage "debt touched takes a concept and at most one plan."
               DEBT_A="$1"; DEBT_PLAN_ARG="${2:-}" ;;
      burn)    { [ $# -ge 2 ] && [ $# -le 3 ]; } || usage "debt burn takes a concept, a row and at most one plan."
               DEBT_A="$1"; DEBT_B="$2"; DEBT_PLAN_ARG="${3:-}" ;;
      adopt)   { [ $# -ge 1 ] && [ $# -le 2 ]; } || usage "debt adopt takes a continuation and at most one plan."
               DEBT_A="$1"; DEBT_PLAN_ARG="${2:-}" ;;
      list)    [ $# -le 1 ] || usage "debt list takes at most one plan."
               DEBT_PLAN_ARG="${1:-}" ;;
      *) usage "debt takes add, adopt, touched, burn or list." ;;
    esac
    [ "$DEBT_SUB" = add ] || [ "$DEBT_SUB" = adopt ] || case "$DEBT_A$DEBT_B" in *'|'*|*' '*|*'	'*) usage "a debt concept or row is one word, with no | in it." ;; esac
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
# In builtins since wave-34 T11 (D19); hooks/session-sweeper.sh's copy says how.
line_field() {  # <line> <key>
  local _lf_rest="${1//$'\n'/|}|" _lf_f
  while [ -n "$_lf_rest" ]; do
    _lf_f="${_lf_rest%%|*}"; _lf_rest="${_lf_rest#*|}"
    case "$_lf_f" in "$2="*) printf '%s\n' "${_lf_f#"$2="}"; return 0 ;; esac
  done
  return 0
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
  local out="${1//[[:cntrl:]|]/ }"
  while :; do case "$out" in *"  "*) out="${out//  / }" ;; *) break ;; esac; done
  out="${out# }"; out="${out% }"
  # THE CUT IS PER-FIELD, NOT UNIVERSAL (REQ-9, carry-over P2). Every caller still gets
  # control characters and `|` folded to spaces — that half of this function is unchanged
  # and applies with no exception. What used to be unconditional is the trailing
  # 400-character cut: the LIST-valued fields (`ROSTER_LIST_FIELDS`, payload/scripts/lib/roster.sh,
  # named once: wave-37 T7, D11, which added `questions=` and `claims=` to the four it used to name
  # here) are space- or comma-joined sets (S13's suite-allowance wall and the brief's declared budget), and a
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
    re_executes)
      out="${out//\%7C/|}"
      printf '%s' "${out//\%25/%}" ;;
    *)
      case " $ROSTER_LIST_FIELDS " in
        *" ${2:-} "*) printf '%s' "$out" ;;
        *) printf '%s' "${out:0:400}" ;;
      esac ;;
  esac
}

# clean_whole <value> -> clean's fold with no 400-character cut. A LIBRARY'S OWN REFUSAL or a sentence
# naming a list (wave-30 T13: `proof-add floor` names the suites a later change owes) is list-valued
# like `files=`, and the cut would drop the very suites it names. clean() itself stays the sweeper's
# copy, code for code (tests/cross-gate-agreement.test.sh §O; wave-30 T23), so this asks the uncut
# arm clean already has for list fields rather than adding a field name only this copy knows.
clean_whole() { clean "$1" files; }

# The prose duration/cadence parser. Deliberate limits, each a refusal rather than a guess —
# see hooks/session-sweeper.sh's copy for the full rationale (its own comments there are
# specific to ITS callers, e.g. `cadence=`, which this script never reads — that is why this
# copy's comments are shorter, not why the code differs). This is that function's POST-FIX
# body, CODE-identical (§O compares it with comments on both sides stripped).
parse_seconds() {  # <prose> -> seconds on stdout; nonzero exit if it cannot be read
  local raw="$1" s pairs count nums hi unit mult n allnums line rest m k nl=$'\n'
  local re='^[0-9]+([[:space:]]*-[[:space:]]*[0-9]+)?[[:space:]]*(hours?|hrs?|minutes?|mins?|seconds?|secs?|h|m|s)([^a-z0-9]|$)'
  [ -n "$raw" ] || return 1
  s="${raw//\~/ }"; s="${s//–/-}"; s="${s//—/-}"; s="${s//,/ }"
  case "$s" in
    *[![:ascii:]]*) s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')" ;;
    *[ABCDEFGHIJKLMNOPQRSTUVWXYZ]*)
      for n in Aa Bb Cc Dd Ee Ff Gg Hh Ii Jj Kk Ll Mm Nn Oo Pp Qq Rr Ss Tt Uu Vv Ww Xx Yy Zz; do
        s="${s//${n%?}/${n#?}}"
      done ;;
  esac
  count=0; pairs=""; unit=""; rest="$s$nl"
  while [ -n "$rest" ]; do
    line="${rest%%"$nl"*}"; rest="${rest#*"$nl"}"
    while :; do
      case "$line" in *[0123456789]*) ;; *) break ;; esac
      line="${line#"${line%%[0123456789]*}"}"
      if [[ $line =~ $re ]]; then
        m="${BASH_REMATCH[0]}"; count=$((count + 1)); pairs="$m"; unit="${BASH_REMATCH[2]}"
        line="${line:${#m}}"
      else
        line="${line#"${line%%[!0123456789]*}"}"
      fi
    done
  done
  [ "$count" -eq 1 ] || return 1
  nums=""; k=0; m="$pairs"
  while :; do
    case "$m" in *[0123456789]*) ;; *) break ;; esac
    m="${m#"${m%%[0123456789]*}"}"; n="${m%%[!0123456789]*}"; m="${m#"$n"}"
    nums="${nums}${nums:+$nl}$n"; k=$((k + 1))
  done
  hi=0
  for n in $nums; do [ "$n" -gt "$hi" ] && hi="$n"; done
  [ "$hi" -gt 0 ] || return 1
  case "$unit" in
    h|hr|hrs|hour|hours)         mult=3600 ;;
    m|min|mins|minute|minutes)   mult=60 ;;
    s|sec|secs|second|seconds)   mult=1 ;;
    *) return 1 ;;
  esac
  case "$s" in *[0123456789].[0123456789]*) return 1 ;; esac
  allnums=0; m="$s"
  while :; do
    case "$m" in *[0123456789]*) ;; *) break ;; esac
    m="${m#"${m%%[0123456789]*}"}"; m="${m#"${m%%[!0123456789]*}"}"; allnums=$((allnums + 1))
  done
  [ "$allnums" -eq "$k" ] || return 1
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
# detector that cannot read cannot report. lib/said.sh no longer mirrors this scan, on purpose
# (wave-37 T5; D9, A-T5-7): the words reader decides trust and opens only this project's own
# directory names, while this one finds an address and decides nothing.

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
# (wave-26 T14; D10, review 5 F8), AND WHAT THE JUDGE READS AT IT (wave-36 T28; D9, AC-3.6). Past
# its last reading a `live:head` review is ready again only when lib/proof.sh `facts_state` reads
# one of its questions uncovered at the head, never because the head moved. Both live in git:
# the tick reads the head here, from the working branch's REF (lib/proof.sh `proof_branch_head`,
# the judge's one reading of the head; wave-35 T10, AC-1.7), never from a checkout holding it,
# and asks the judge once (lib/units.sh `_units_readings_state`, the review lines of facts_state),
# handing both to every ready-set question this tick asks through UNITS_LIVE_HEAD and
# UNITS_READINGS_STATE. Only a plan that carries a review proof needs them — before the first
# one, a landed row is enough — so a tick on any other plan runs no git. No head (no branch
# named, or a branch that names no commit) is no head: the review waits, saying so. The stop
# wall takes the tick's head from its digest (A-T14.2), and the program asks the judge itself.
sched_live_head() {  # <project root> -> sets UNITS_LIVE_HEAD and UNITS_READINGS_STATE, or clears them
  # ONCE PER PLAN PER TICK (wave-36 T40; D9, AC-3.6), as `sched_facts_state` is below: `gate_report` reads the
  # budget a second time, and the judge walks the commits on every ask, so a second ask walked one state twice.
  # The first call for a plan asks and keeps both; a later call in this process returns what it kept, clearing
  # nothing. A different plan, or a new process, asks again.
  [ "${SCHED_LIVE_PLAN:-}" = "${SCHED_PLAN:-}" ] && [ -n "${SCHED_LIVE_PLAN:-}" ] && return 0
  SCHED_LIVE_PLAN="${SCHED_PLAN:-}"
  UNITS_LIVE_HEAD=""; UNITS_READINGS_STATE=""
  [ -n "${SCHED_PLAN:-}" ] && [ -f "$SCHED_PLAN" ] || return 0
  /usr/bin/grep -q '^[[:space:]-]*proved:.*kind=review' "$SCHED_PLAN" 2>/dev/null || return 0
  if ! declare -F proof_branch_head >/dev/null 2>&1; then
    [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh" 2>/dev/null
  fi
  declare -F proof_branch_head >/dev/null 2>&1 || return 0
  UNITS_LIVE_HEAD="$(proof_branch_head "$SCHED_PLAN" "$1" 2>/dev/null)" || UNITS_LIVE_HEAD=""
  [ -z "$UNITS_LIVE_HEAD" ] || UNITS_READINGS_STATE="$(_units_readings_state "$SCHED_PLAN")"
  return 0
}

# THE FACTS THE RUN OWES, JUDGED ONCE PER TICK (wave-27 T14; D3). The integrate row's
# `proof:review` is met only when lib/proof.sh `facts_state` holds the plan at the working head,
# and that reads git, so the readiness program is handed the answer through UNITS_FACTS_STATE, as
# it is handed the head: `covered`, or the owed lines that do not hold, `; `-joined. It is asked
# only when the plan carries an open integrate row (no other read turns on it), and once per tick
# (`gate_report` reads the budget a second time). Unset, the integrate row waits, saying so.
# THE REGRESSION IS ASKED FIRST, FROM THE TICK'S OWN MEMO (`_units_floor_state`, the one proof_state run
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
    covered*) : ;;
    *) UNITS_FACTS_STATE="the readings are judged once the regression holds"; return 0 ;;
  esac
  if ! declare -F facts_state >/dev/null 2>&1; then
    [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh" 2>/dev/null
  fi
  declare -F facts_state >/dev/null 2>&1 || return 0
  # THE HEAD IS THE WORKING BRANCH'S REF (wave-35 T10; AC-1.7), `proof_branch_head`, as `current 7`/`8` and
  # close-out read it: a branch no checkout holds is judged where its ref points.
  head="${UNITS_LIVE_HEAD:-}"
  [ -n "$head" ] || head="$(proof_branch_head "$SCHED_PLAN" "$1" 2>/dev/null)" || head=""
  if [ -z "$head" ]; then
    wb="$(plan_working_branch "$SCHED_PLAN")"
    UNITS_FACTS_STATE="the working branch ${wb:-(none named)} names no commit here, so there is no head to judge them at"
    return 0
  fi
  out="$(facts_state "$SCHED_PLAN" "$head" 2>/dev/null)"; rc=$?
  case "$rc" in
    0) UNITS_FACTS_STATE=covered ;;
    2) UNITS_FACTS_STATE="the plan's rigor and scale cannot be dealt" ;;
    *) UNITS_FACTS_STATE="$(printf '%s\n' "$out" | awk -F'\t' '$NF != "covered"' \
         | awk -F'\t' '{ $1 = $1; printf "%s%s", (n++ ? "; " : ""), $0 }' OFS=' ')" ;;
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
# same optional letter, then require what remains to be all-digits.
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
#     `active` row whose agent cell names no row on the run's rosters nor its Dispatch ledger —
#     and each finding prints as `poker: LEDGER <id> <kind> [<value>]`. The rosters are
#     `units_run_rosters`' list, this tick's own first, the list the gate reads (wave-36 T29;
#     D10); with none to read (the first tick) it is the reader's no-roster rule, the gate's too.
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
$(units_findings "$SCHED_PLAN" "$(units_run_rosters "${ROSTER_FILE%/*}" "$SCHED_PLAN" "$ROSTER_FILE")" 2>/dev/null)
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
#
# A WAIT ON A SUSPECT HOLDER SAYS SO (wave-30 T16; REQ-12 AC-12.2, D14a). When `units_suspect` (the
# one suspect test, lib/units.sh) names the row and a holder its WAIT reason names, the line carries
# ` · suspect: <id> reads <holder>, shares no file — loosen it: bash <hook> task-set <id> reads=…`,
# the loosening printed and never run. The reason keeps `clean`'s 400-character cut; the clause is
# cleaned on its own and kept whole, because a cut `task-set` line is no command.
# THE CHAIN NAMES ITS SPLIT CANDIDATE (wave-30 T16; REQ-12 AC-12.4, D14d): ` · SPLIT? <id> — <size> min,
# <n> files, <k> rows wait on it`, the pending row of the chain `units_split_candidate` scores
# highest by fan-in × size × files; absent when every pending row on it scores 0. Nothing is split.
suspect_lines() {  # <plan> [<id>] -> `<id><TAB><holder><TAB><clause — loosen it: bash <hook> task-set …>`, one per suspect; the one wording the WAIT line, task-add and task-set print
  units_suspect "$@" 2>/dev/null | awk -F'\t' -v hook="${HOOK_DIR}/session-poker.sh" \
    'NF >= 4 { printf "%s\t%s\t%s — loosen it: bash %s %s\n", $1, $2, $3, hook, $4 }'
}

# A ROW WAITING ON THE USER'S APPROVAL ALONE IS THE PERSON'S BLOCK (wave-33 T35; AC-2.2, D2). A WAIT
# whose every clause is `approval:<name>` (or its live read) opens `approve:<name>` on the person's
# ledger (lib/owed.sh), the key the approve verb closes, carrying the WAIT line printed. A row that
# also waits on other work is not yet blocked on the person and opens nothing; `approval:plan` is the
# Step-3 card's. Opening is idempotent per key, so every later tick on the same wait is one item.
tick_owed_approval() {  # <reason> <printed line> -> always 0, prints nothing
  local c names=""
  declare -F owed_open >/dev/null 2>&1 || return 0
  while IFS= read -r c; do
    c="${c# }"; c="${c% }"; c="${c#live:}"
    case "$c" in
      approval:plan) return 0 ;;
      approval:[A-Za-z0-9]*) case "${c#approval:}" in *[!A-Za-z0-9._-]*) return 0 ;; esac ;;
      *) return 0 ;;
    esac
    names="$names ${c#approval:}"
  done <<TOA
$(printf '%s\n' "$1" | awk '{ n = split($0, a, /; /); for (i = 1; i <= n; i++) print a[i] }')
TOA
  for c in $names; do
    OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_open "approve:$c" "approval: $c" "$2" >/dev/null 2>&1
  done
  return 0
}

tick_wait_report() {  # -> says the WAIT lines and the CHAIN line; reads SCHED_* the FILL arm set; sets SCHED_BEHIND (the ready rows parked for width)
  local rows waiting all offered held line chain ids mins susp base sfx edges split sp_id sp_sz sp_nf sp_k wl
  [ -n "${SCHED_PLAN:-}" ] && [ -n "${SCHED_STEP:-}" ] || return 0
  rows="$(units_rows "$SCHED_PLAN" 2>/dev/null)" || return 0
  [ -n "$rows" ] || return 0
  waiting="$(units_waiting "$SCHED_PLAN" "$SCHED_STEP" 2>/dev/null)"
  susp="$(suspect_lines "$SCHED_PLAN")"
  all="${SCHED_READY_ALL:-}"
  offered="$(printf '%s' "${SCHED_READY:-}" | tr '\n' ' ')"
  # THE ROWS A ROSTER HOLDS (wave-35 T28; AC-5.5, D14): a pending row open on any roster, this
  # session's or another's, is left out of the ready set (`fill_held_ids`, lib/fill.sh), and its WAIT
  # names the writer and the roster's session: `WAIT <id> — <name> open on roster <sid, first 8>`.
  held="$(fill_held_ids "$SCHED_PLAN" "$(printf '%s\n' "$rows" | awk -F'\t' '$10 == "pending" { print $1 }')" 2>/dev/null)"
  SCHED_BEHIND=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    base="${line%%$'\037'*}"; sfx=""
    [ "$base" = "$line" ] || sfx="${line#*$'\037'}"
    case "$base" in *" — ready; no writer slot free (gap "*) SCHED_BEHIND="${SCHED_BEHIND}${SCHED_BEHIND:+ }${base%% *}" ;; esac
    wl="WAIT $(clean "$base")${sfx:+ · $(clean_whole "$sfx")}"
    say "$wl"
    tick_owed_approval "${base#* — }" "poker: $wl"
  done <<TICK_WAIT
$(printf '\034rows\n%s\n\034wait\n%s\n\034susp\n%s\n\034held\n%s\n' "$rows" "$waiting" "$susp" "$held" | awk -F'\t' \
    -v offered=" $offered " -v all=" $all " -v declined=" ${SCHED_SD_IDS:-} " -v gap="${SCHED_GAP:-0}" '
  $0 == SUBSEP "rows" { part = 1; next }
  $0 == SUBSEP "wait" { part = 2; next }
  $0 == SUBSEP "susp" { part = 3; next }
  $0 == SUBSEP "held" { part = 4; next }
  part == 3 && $1 != "" { sus[$1, $2] = $3; next }
  part == 4 && $1 != "" { hold[$1] = $2 " open on roster " substr($3, 1, 8); next }
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
        sfx = ""; split("", said)
        for (m = 1; m <= nr[i]; m++) {
          key = i SUBSEP rd[i, m]
          for (w = 1; w <= nw[key]; w++) {
            h = wid[key, w]
            if (((i, h) in sus) && !(h in said)) { said[h] = 1; sfx = sfx (sfx == "" ? "" : " · ") sus[i, h] }
          }
        }
        if (sfx != "") reason = reason "\037" sfx
      } else if (index(all, " " i " ")) {
        if (index(declined, " " i " ")) reason = "ready; answered by the standing fill-declined"
        else reason = "ready; no writer slot free (gap " gap ")"
      } else if (i in hold) {
        reason = hold[i]
      } else continue
      printf "%s — %s\n", i, reason
    }
  }')
TICK_WAIT
  edges="$(units_edges "$SCHED_PLAN" 2>/dev/null)"
  chain="$( { printf '%s\n' "$rows" | awk -F'\t' '$10 == "pending" || $10 == "active" {
                m = 0; if (match($7, /^[0-9]+/)) m = substr($7, RSTART, RLENGTH)
                printf "N\t%s\t%d\n", $1, m }'
              printf '%s\n' "$edges" | awk -F'\t' 'NF >= 2 { printf "E\t%s\t%s\n", $1, $2 }'
            } | units_chain "${SCHED_WRITERS:-$(printf '%s\n' "$rows" | grep -c .)}" 2>&1 )" || {
    say "CHAIN unknown — $(clean "$chain")"
    return 0
  }
  line="$(printf '%s\n' "$chain" | awk -F'\t' '$1 == "chain" { print $2 "\t" $3; exit }')"
  ids="${line%%$'\t'*}"; mins="${line##*$'\t'}"
  [ -n "$ids" ] || return 0
  split="$(units_split_candidate "$SCHED_PLAN" "$ids" "$edges" 2>/dev/null)"
  sp_id=""
  [ -z "$split" ] || IFS=$'\t' read -r sp_id sp_sz sp_nf sp_k <<< "$split"
  say "CHAIN ${ids//,/→} (${mins} min)${sp_id:+ · SPLIT? $(clean "$sp_id") — ${sp_sz} min, ${sp_nf} files, ${sp_k} rows wait on it}"
}

# THE PRIORITY A RECORD NEVER STATES (wave-28 T15; D19, AC-8.3). A rated reading writes the plan's
# `deferred:` lines at registration; the tick prints each such finding once, with the
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

# THE DETACHED LAUNCH-SYNC'S FAILURE, TOLD ONCE (wave-36 T12; D13, AC-7.1; C13). The launch recorder
# (hooks/execution-recorder.sh `launch_sync_start`) writes the call's output and then `rc=<n>` to
# `.bionic/tmp/launch-sync-<sid>.log`, rewriting it at each launch. A log whose last status is not 0
# and that carries no `told=` line prints
#
#   poker: launch-sync failed — <log>
#
# and gets a `told=<ISO>` line, so the line prints once per failure, never per tick: the next launch
# rewrites the log and a new failure is told again. A log with no `rc=` line is a call still running,
# or one killed before it ended, and says nothing; so does a symbolic link.
tick_launch_sync_failed() {  # <root> <session-id> -> says the line when the log holds an untold failure
  local log="$1/.bionic/tmp/launch-sync-$2.log" rc
  [ -f "$log" ] && [ ! -L "$log" ] || return 0
  rc="$(awk '/^rc=/ { r = substr($0, 4) } /^told=/ { t = 1 } END { if (!t) print r }' "$log" 2>/dev/null)"
  case "$rc" in ''|0) return 0 ;; esac
  printf 'told=%s\n' "$(iso_now)" >> "$log" 2>/dev/null || return 0
  say "launch-sync failed — $log"
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

# ---------------------------------------------------------------- the runs (wave-30 T12; D6, D7d)
#
# A RUN IS AN OBJECT, MADE AT THE SHIM (payload/scripts/booked.sh --detach, wave-30 T8). Its files
# sit side by side under `<project>/.bionic/tmp/runs`: `<id>.log` (its output, last line `rc=<n>`),
# `<id>.log.pid` (the detached shim's pid, the session leader of everything the run started),
# `<id>.log.rc` (its code, written last, by the detached side alone) and `<id>.log.progress.tsv`
# (a line per suite and per section as it opens). With --agent naming a row, the row carries the
# record too: `run_pid= run_log= run_head= run_cmd= run_started_at=` at the start, `run_rc=
# run_ended_at=` at the end (lib/roster.sh `roster_mark_run`). These readers serve `wait`,
# `stop-run`, `adopt`, the tick's RUNNING lines and `regression-runs`, one reading for all five.
#
# THREE STATES, AND NO FOURTH. FINISHED: the row carries `run_rc`, or `<log>.rc` holds a code.
# RUNNING: neither, and the pid is alive AND is still that run's detached shim (`ps` names
# booked.sh with `--run-log <log>`; a pid the system gave to someone else is not the run). LOST:
# neither, and the pid is dead or is no longer the run's — reported with the time its log was
# last written. A LOST run is never called a timeout: nothing here knows a limit was reached.
RUN_LOG=""; RUN_PID=""; RUN_NAME=""; RUN_ROSTER=""; RUN_ROW_RC=""; RUN_STARTED=""
RUN_STATE=""; RUN_RC=""; RUN_ID=""; RUN_LAST_WRITTEN=""; RUN_PROGRESS=""; RUN_ELAPSED=""

run_live() {  # <pid> <log> -> 0 when <pid> is alive and is still <log>'s detached shim
  local c
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$1" 2>/dev/null || return 1
  c="$(ps -ww -o command= -p "$1" 2>/dev/null)" || return 1
  case "$c" in *booked.sh*"--run-log $2"*) return 0 ;; esac
  return 1
}

# run_row_of <roster file> <name> -> the name's latest row on that roster carrying a run record
run_row_of() {
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  awk -v k="|name=$2|" 'index($0 "|", k) && index($0, "|run_log=") { l = $0 } END { if (l != "") print l }' "$1" 2>/dev/null
}

# run_load_row <row> <roster file> -> RUN_* from a roster row's run record; 1 when it carries none
run_load_row() {
  RUN_LOG="$(line_field "$1" run_log)"
  [ -n "$RUN_LOG" ] || return 1
  RUN_PID="$(line_field "$1" run_pid)"
  RUN_NAME="$(line_field "$1" name)"
  RUN_ROW_RC="$(line_field "$1" run_rc)"
  RUN_STARTED="$(line_field "$1" run_started_at)"
  RUN_ROSTER="$2"
  return 0
}

# run_find <project root> <name | run id | log path> -> RUN_* for the run that operand names; 1 when
# none. A NAME is looked up on every roster of the project (this session's and a predecessor's: a
# run outlives the session that started it), and the newest start wins. A RUN ID (the `run=` the
# shim printed, `<agent>-<suites>[-<n>]`) or a log path is read off the runs directory, for a run no
# row records (the main thread's).
run_find() {
  local repo="$1" arg="$2" rf row best="" bestrf="" s bs=""
  RUN_LOG=""; RUN_PID=""; RUN_NAME=""; RUN_ROSTER=""; RUN_ROW_RC=""; RUN_STARTED=""
  [ -n "$arg" ] || return 1
  case "$arg" in
    /*.log)
      [ -f "$arg" ] || return 1
      RUN_LOG="$arg"; RUN_NAME="$(basename "$arg" .log)" ;;
    *)
      for rf in "$repo/.bionic/tmp"/roster-*.state; do
        row="$(run_row_of "$rf" "$arg")" || continue
        [ -n "$row" ] || continue
        s="$(line_field "$row" run_started_at)"
        if [ -z "$best" ] || [ "$s" \> "$bs" ]; then best="$row"; bestrf="$rf"; bs="$s"; fi
      done
      if [ -n "$best" ]; then
        run_load_row "$best" "$bestrf" || return 1
      else
        case "$arg" in */*|.*) return 1 ;; esac
        [ -f "$repo/.bionic/tmp/runs/$arg.log" ] || return 1
        RUN_LOG="$repo/.bionic/tmp/runs/$arg.log"; RUN_NAME="$arg"
      fi ;;
  esac
  [ -n "$RUN_PID" ] || { read -r RUN_PID < "$RUN_LOG.pid"; } 2>/dev/null
  return 0
}

# run_read -> RUN_STATE (RUNNING | FINISHED | LOST), RUN_RC, RUN_ID, RUN_LAST_WRITTEN, RUN_PROGRESS
# (the progress file's last line, tabs as spaces) and RUN_ELAPSED (seconds since the start: the
# row's run_started_at, else the pid file's birth), for the run run_find loaded.
run_read() {
  local rc="" t0=""
  RUN_ID="${RUN_LOG##*/}"; RUN_ID="${RUN_ID%.log}"
  RUN_RC=""; RUN_LAST_WRITTEN=""; RUN_ELAPSED=""
  RUN_PROGRESS="$(tail -n 1 "$RUN_LOG.progress.tsv" 2>/dev/null)"; RUN_PROGRESS="${RUN_PROGRESS//$'\t'/ }"
  case "$RUN_ROW_RC" in ''|*[!0-9]*) { read -r rc < "$RUN_LOG.rc"; } 2>/dev/null ;; *) rc="$RUN_ROW_RC" ;; esac
  case "$rc" in
    ''|*[!0-9]*) : ;;
    *) RUN_STATE=FINISHED; RUN_RC="$rc"; return 0 ;;
  esac
  if run_live "$RUN_PID" "$RUN_LOG"; then
    RUN_STATE=RUNNING
    [ -z "$RUN_STARTED" ] || t0="$(iso_epoch "$RUN_STARTED")"
    [ -n "$t0" ] || t0="$(file_mtime "$RUN_LOG.pid")"
    case "$t0" in ''|*[!0-9]*|0) RUN_ELAPSED="" ;; *) RUN_ELAPSED=$(( $(now_epoch) - t0 )) ;; esac
    return 0
  fi
  # THE PID DIED: one more read of `<log>.rc`, then LOST. The shim's exit trap writes `.rc` and
  # exits, and that can fall between the read above and run_live's answer, so a finished run would
  # read LOST (wave-32 T22; research-red3 §2). booked.sh's booked_follow guards the same gap.
  { read -r rc < "$RUN_LOG.rc"; } 2>/dev/null
  case "$rc" in ''|*[!0-9]*) : ;; *) RUN_STATE=FINISHED; RUN_RC="$rc"; return 0 ;; esac
  RUN_STATE=LOST
  RUN_LAST_WRITTEN="$(epoch_iso "$(file_mtime "$RUN_LOG")")"
  [ -n "$RUN_LAST_WRITTEN" ] || RUN_LAST_WRITTEN=unknown
  return 0
}

# run_state_words -> the state as adopt and the tick print it, after run_read
run_state_words() {
  case "$RUN_STATE" in
    RUNNING)  printf 'RUNNING pid=%s elapsed=%ss run=%s' "$RUN_PID" "${RUN_ELAPSED:-?}" "$RUN_ID" ;;
    FINISHED) printf 'FINISHED rc=%s run=%s' "$RUN_RC" "$RUN_ID" ;;
    *)        printf 'LOST last-written=%s run=%s' "$RUN_LAST_WRITTEN" "$RUN_ID" ;;
  esac
}

# run_groups <pid> -> the process groups of <pid> and every process below it, one per line. The
# detached shim leads its own session and group, and runs its command in a group of its own (set -m),
# so stopping the run's group alone could leave the command running.
run_groups() {
  ps -ax -o pid= -o ppid= -o pgid= 2>/dev/null | awk -v root="$1" '
    { pp[$1] = $2; pg[$1] = $3; n[NR] = $1 }
    END {
      keep[root] = 1; changed = 1
      while (changed) { changed = 0
        for (i in n) { p = n[i]; if (!(p in keep) && (pp[p] in keep)) { keep[p] = 1; changed = 1 } } }
      for (p in keep) if (p in pg) g[pg[p]] = 1
      for (x in g) print x
    }'
}

# THE GATE'S HALF OF stop-run (wave-36 T11; D8, REQ-2 AC-2.2). A shim parked in `gate_ask` is no detached run:
# no `.bionic/tmp/runs/` log names it, and before D8 `gate_end` refused its never-admitted request. The verb
# reads the gate's store through lib/gate.sh's own reader and rule (`_gate_read`, `_gate_open`), never a copy.
#
# stop_run_request <operand> -> SR_REQ and rc 0 when the operand names a gate request: a whole number names
# that request's file (run ids are never bare numbers: `<agent>-<suites>[-<n>]`); a name names the one OPEN
# request whose who's agent half it is. rc 1 when it names none; rc 2 with the ids, lowest first, in
# SR_REQS when a name holds more than one open request — nothing is guessed.
stop_run_request() {
  local arg="$1" gd f
  SR_REQ=""; SR_REQS=""
  declare -F _gate_read >/dev/null 2>&1 && declare -F gate_dir >/dev/null 2>&1 || return 1
  gd="$(gate_dir)"
  case "$arg" in
    ''|*[!0-9]*) : ;;
    *) [ -f "$gd/requests/$arg" ] || return 1; SR_REQ="$arg"; return 0 ;;
  esac
  for f in "$gd"/requests/[0-9]*; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    _gate_read "$f" 2>/dev/null || continue
    [ "${_R_who#*:}" = "$arg" ] || continue
    _gate_open || continue
    SR_REQS="$SR_REQS ${f##*/}"
  done
  SR_REQS="$(printf '%s\n' $SR_REQS | sort -n | tr '\n' ' ')"; SR_REQS="${SR_REQS% }"
  case "$SR_REQS" in '') return 1 ;; *' '*) return 2 ;; esac
  SR_REQ="$SR_REQS"
  return 0
}

# stop_run_record <key=value>... -> appends `line/v1|ev=stop-run|…` (lib/line.sh `line_event`) to the landing
# record of the run this session is bound to; rc 1, nothing written, with no bound run. The hand-hold fold
# (`hand_holds_report`) counts it under its own kind: a stop is a verb act, never a by-hand one.
stop_run_record() {
  local sid
  sid="$(session_id 2>/dev/null)" || sid=""
  [ -n "$sid" ] || return 1
  resolve_run "$REPO_REAL" "$sid" 2>/dev/null
  [ -n "$POKER_RUN_PLAN" ] && [ -f "$POKER_RUN_PLAN" ] || return 1
  declare -F line_event >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1
  declare -F line_event >/dev/null 2>&1 || return 1
  line_event "$POKER_RUN_PLAN" stop-run "$@"
}

# stop_run_gate <id> -> stops gate request <id> and says what it did; rc 0, or 2 when the end could not be
# written. THE ORDER: the end is written first, `gate_end <id> 143 --by <sid> --why <reason>` (accepted on a
# never-admitted id from this call alone), so the parked or running shim, TERMed next, finds its request
# ended and its own trap's end changes nothing; then its holder's process group is TERMed (never this call's
# own group: then the holder alone), KILLed after 5 s if it lives on; then the record line.
stop_run_gate() {
  local id="$1" gd f sid who kind key state hp hs pg self what i rec=""
  gd="$(gate_dir)"; f="$gd/requests/$id"
  _gate_read "$f" 2>/dev/null || { die "stop-run — gate request $id cannot be read"; return 2; }
  who="${_R_who#*:}"; kind="$_R_kind"; key="${_R_key//|/ }"
  if [ -n "$_R_ended" ]; then
    say "stop-run request $id ${who:--} $kind $key — ended rc=${_R_rc:--}; nothing to stop"
    return 0
  fi
  _R_state=""; _gate_open 2>/dev/null || :
  state="$_R_state"
  hp=""; hs=""
  if _gate_alive; then hp="${_R_holder%%:*}"; hs="${_R_holder#*:}"; fi
  if [ "$SR_REPORT_ONLY" = yes ]; then
    if [ -n "$hp" ]; then what="would end it and TERM its holder's process group (pid $hp)"; else what="would end it; its holder is gone"; fi
    say "stop-run request $id ${who:--} $kind $key — $state; $what (report-only: nothing was sent)"
    return 0
  fi
  sid="$(session_id 2>/dev/null)" || sid=""; sid="${sid:-none}"
  if ! gate_end "$id" 143 --by "$sid" --why "${SR_WHY:--}" 2>/dev/null; then
    die "stop-run — gate request $id could not be ended (the gate's store or lock); nothing was sent"
    return 2
  fi
  what="its holder is gone, so nothing was sent"
  if [ -n "$hp" ]; then
    self="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
    pg="$(ps -o pgid= -p "$hp" 2>/dev/null | tr -d ' ')"
    case "$pg" in ''|0|1|*[!0-9]*) pg="" ;; esac
    [ "$pg" != "$self" ] || pg=""
    if [ -n "$pg" ]; then kill -TERM -- "-$pg" 2>/dev/null || kill -TERM "$hp" 2>/dev/null
    else kill -TERM "$hp" 2>/dev/null; fi
    what="TERM"
    i=0
    while [ "$i" -lt 50 ] && _slots_live "$hp" "$hs"; do sleep 0.1; i=$((i + 1)); done
    if _slots_live "$hp" "$hs"; then
      if [ -n "$pg" ]; then kill -KILL -- "-$pg" 2>/dev/null; fi
      kill -KILL "$hp" 2>/dev/null
      what="TERM, then KILL"
    fi
    what="its holder's process group stopped ($what)"
  fi
  stop_run_record "request=$id" "who=${_R_who//|/ }" "kind=$kind" "key=$key" "by=$sid" "why=${SR_WHY:--}" \
    || rec="; no bound run, so no ev=stop-run line was written"
  say "stop-run request $id ${who:--} $kind $key — $state; ended by=$sid why=${SR_WHY:--}, $what$rec"
  return 0
}

# regression_runs_count <project root> -> the number of full-runner runs the project's rosters
# record as ended (Δ6d; REQ-4 AC-4.6). One run is one `run_log`, however many rows copy it. A run
# is the FULL runner when the command it ran is a whole run (wave-31 T21; REQ-2, D3): the command
# is `<log>.key`'s lines 2 and on, as the shim wrote them with the tree on line 1, else the row's
# `run_cmd=` (booked.sh `booked_one_line`, the lossy front of the same command), and
# `cmd_whole_run` (payload/scripts/lib/cmd-class.sh) is the one judgment on it. The log's own name
# is never read: the wave-30 id `w30-T26-tests_run.sh` is the full runner, and an id ending
# `-run.sh` need not be. The root the classifier reads a script against is the key's tree, else the
# project's own.
regression_runs_count() {
  local rf files="" lg cmd key tree n=0
  for rf in "$1/.bionic/tmp"/roster-*.state; do
    [ -f "$rf" ] && [ ! -L "$rf" ] || continue
    files="${files}${rf}
"
  done
  [ -n "$files" ] || { printf '0'; return 0; }
  poker_cmdclass_load || { printf '0'; return 0; }
  while IFS=$'\t' read -r lg cmd; do
    [ -n "$lg" ] || continue
    tree="$1"
    if [ -f "$lg.key" ] && [ ! -L "$lg.key" ]; then
      key="$(cat "$lg.key" 2>/dev/null)"
      case "$key" in
        *$'\n'*) tree="${key%%$'\n'*}"; cmd="${key#*$'\n'}" ;;
      esac
    fi
    cmd_whole_run "$cmd" "$tree" && n=$((n + 1))
  done <<EOF_RUNS
$(printf '%s' "$files" | while IFS= read -r rf; do [ -n "$rf" ] && cat "$rf"; done 2>/dev/null | awk -F'|' '
    {
      lg = ""; rc = ""; cmd = ""
      for (i = 1; i <= NF; i++) {
        if (index($i, "run_log=") == 1) lg = substr($i, 9)
        else if (index($i, "run_rc=") == 1) rc = substr($i, 8)
        else if (index($i, "run_cmd=") == 1) cmd = substr($i, 9)
      }
      if (lg == "" || rc !~ /^[0-9]+$/ || lg in seen) next
      seen[lg] = 1
      print lg "\t" cmd
    }')
EOF_RUNS
  printf '%d' "$n"
}

# The classifier `regression_runs_count` asks, loaded on first use and never at the top: the tick
# runs every Patrol interval and counts at most a few runs, and a hook copied outside the repo
# resolves its libraries from a checkout that may not carry cmd-class.sh (the count is then 0).
poker_cmdclass_load() {
  declare -F cmd_whole_run >/dev/null 2>&1 && return 0
  [ -f "$BIONIC_LIB/cmd-class.sh" ] || return 1
  # shellcheck source=/dev/null
  . "$BIONIC_LIB/cmd-class.sh"
  declare -F cmd_whole_run >/dev/null 2>&1
}

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
adopt_fold() {  # <roster file> <ack ledger> -> name|id|type|deliverable|progress|cadence|launched_at|origin|plan|waiver|suites_source|done|lands_red|red_evidence|row|<source row: the merged list fields, row-shaped>
  # THE OPEN SET IS ASKED ONCE, of the one predicate, over the predecessor's roster as it
  # stands — no session filter, because every row on it carries the predecessor's own id.
  # Handed to awk through the environment rather than `-v`, which would read a backslash in
  # a name as an escape.
  AF_OPEN="$(roster_open_names "$1" "$2")" AF_LISTS="$ROSTER_LIST_FIELDS" AF_SCHEMA="roster-state/${ROSTER_SCHEMA_VERSION}" awk '
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
      nl = split(ENVIRON["AF_LISTS"], lf, " ")
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
      # THE LIST FIELDS (wave-37 T7, D11; was the three instrument fields wave-01 S13 named, then the
      # declared runs and the landing set one at a time), carried forward as the contract fields above
      # are: the merged value of each field of the set the roster library names once, in
      # `ROSTER_LIST_FIELDS`, handed in through the environment so this program holds no copy of it.
      # They are what the writer-side budget guard reads: a resumed agent whose adopted row lost
      # `suites_allowed=` would come out of a /clear with no budget on it, and the wall that refuses
      # an off-budget suite would go quiet for exactly the agents a clear leaves running longest;
      # one that lost `questions=` is no longer a reader of anything. `suites_source` is the one
      # scalar that travels beside them.
      for (li = 1; li <= nl; li++) { v = kv($0, lf[li]); if (v != "") lv[n, lf[li]] = v }
      v = kv($0, "suites_source");  if (v != "") ssrc[n]   = v
      # THE DONE MARKER (wave-24 T9, D3): the same contract, so its completion signal too.
      v = kv($0, "done");           if (v != "") dmark[n]  = v
      # THE LANDING KEYS (wave-28 T68; A-orch-216): `lands_on=` (a list field, above), `lands_red=`, `red_evidence=` and `row=` are what the
      # dispatch wall wrote from the brief, and what `ready` reads the suites and the declared debt from. Carried
      # forward as the instrument fields are, or an adopted row would be proved on its budget with its debt dropped.
      v = kv($0, "lands_red");      if (v != "") lred[n]   = v
      v = kv($0, "red_evidence");   if (v != "") revid[n]  = v
      v = kv($0, "row");            if (v != "") lrow[n]   = v
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
        # THE SOURCE ROW, LAST: row-shaped, so the caller reads a list field off it by key and the
        # tail of its `read` takes the whole of it, `|` and all. A key is there only where the
        # predecessor stated a value.
        src = ENVIRON["AF_SCHEMA"]
        for (li = 1; li <= nl; li++) if ((n, lf[li]) in lv) src = src "|" lf[li] "=" lv[n, lf[li]]
        printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n", n, id[n], stype[n], deliv[n], prog[n], cad[n], \
               launch[n], ((n in afrom) ? afrom[n] : sess[n]), \
               ((n in hasplan) ? (plan[n] == "" ? "none" : plan[n]) : ""), waiv[n], \
               ssrc[n], dmark[n], lred[n], revid[n], lrow[n], src
      }
    }
  ' "$1" 2>/dev/null
}

# AN ACK TAKEN IN ANOTHER SESSION: `adopt_cross_acks` and `adopt_acked_elsewhere` live in lib/fill.sh beside
# the roster walk (wave-35 T28; AC-5.5), because the fill and the dispatch wall read the same acks `adopt` does.

# TWO READS A CADENCE APART (wave-34 T6; REQ-14 AC-14.1, D23). A transcript's mtime says when the agent
# last wrote, which is as true of an agent SIGKILLed a minute ago as of one at work; growth between two
# reads is the evidence. `adopt` keeps each read it takes — `adopt-read/v1|id=|size=|epoch=` in
# `.bionic/tmp/adopt-reads.state`, one file for the root because a read is about the agent, not the
# session that took it — and the next adopt compares against the newest read at least one cadence old.
# `--report-only` reads the file and never writes it. Kept small: a week of reads, eight per agent.
ADOPT_READS_SCHEMA="adopt-read/v1"
adopt_read_baseline() {  # <reads> <id> <oldest epoch allowed> -> "<size> <epoch>" of the newest read at or before it
  [ -n "$1" ] || return 0
  printf '%s\n' "$1" | awk -v id="$2" -v lim="$3" '
    function kv(line, key,   i, n, p) {
      n = split(line, p, "|")
      for (i = 1; i <= n; i++) if (index(p[i], key "=") == 1) return substr(p[i], length(key) + 2)
      return ""
    }
    index($0, "adopt-read/v1|") == 1 && kv($0, "id") == id {
      e = kv($0, "epoch"); z = kv($0, "size")
      if (e ~ /^[0-9]+$/ && z ~ /^[0-9]+$/ && e + 0 <= lim + 0 && e + 0 >= best + 0) { best = e; bz = z; got = 1 }
    }
    END { if (got) print bz " " best }'
}

adopt_reads_write() {  # <file> <new lines> <now epoch> -> 0 written, 1 not
  local f="$1" tmp
  [ -n "$2" ] || return 0
  tmp_dir_ok "${f%/*}" || return 1
  [ -L "$f" ] && return 1
  tmp="$f.$$"
  { [ -f "$f" ] && cat "$f"; printf '%s\n' "$2"; } 2>/dev/null | awk -v now="$3" '
    function kv(line, key,   i, n, p) {
      n = split(line, p, "|")
      for (i = 1; i <= n; i++) if (index(p[i], key "=") == 1) return substr(p[i], length(key) + 2)
      return ""
    }
    index($0, "adopt-read/v1|") == 1 {
      id = kv($0, "id"); e = kv($0, "epoch")
      if (id == "" || e !~ /^[0-9]+$/ || e + 0 < now - 604800) next
      k = ++c[id]; r[id, k] = $0; if (!(id in seen)) { seen[id] = 1; ids[++n] = id }
    }
    END { for (i = 1; i <= n; i++) { id = ids[i]; for (k = (c[id] > 8 ? c[id] - 7 : 1); k <= c[id]; k++) print r[id, k] } }' \
    > "$tmp" 2>/dev/null && mv -f "$tmp" "$f" 2>/dev/null && return 0
  rm -f "$tmp" 2>/dev/null
  return 1
}

# THE HANDOFF, READ BACK (wave-34 T6; REQ-14 AC-14.2, D23). `handoff` writes `## Handoff` with its
# `written:` instant, and a dispatch after it starts an agent that handoff never saw — so the first verb a
# resumed session runs says whether the bound plan's handoff still stands: STALE, naming every dispatch
# stamped with that plan (the dispatch wall's `intended` row, `plan=` and `launched_at=`) later than it.
# Silent when the session is unbound or its plan carries no handoff. The handoff itself is marked by the
# plan writer that runs at dispatch (`handoff_mark_stale`, T29), from the same two readers.
handoff_written_at() {  # <plan file> -> its ## Handoff `written:` instant, empty when it has none
  awk '/^[ \t]*```/ { f = !f; next } !f && /^##[ \t]/ { h = ($0 ~ /^##[ \t]+Handoff[ \t]*$/); next }
       h && /^written: [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ { print substr($0, 10); exit }' "$1" 2>/dev/null
}

# The dispatches of <plan> after <instant>, `name<TAB>launched_at`, one line per name (its first such
# dispatch), in roster order, read off every roster in <state dir>.
handoff_dispatches_since() {  # <bound plan, raw> <state dir> <instant>
  local key pl nm la seen=""
  key="$(adopt_plan_key "$1")"
  while IFS="$(printf '\t')" read -r pl nm la; do
    [ -n "$nm" ] || continue
    [ "$(adopt_plan_key "$pl")" = "$key" ] || continue
    case ", $seen, " in *", $nm, "*) continue ;; esac
    seen="${seen:+$seen, }$nm"
    printf '%s\t%s\n' "$nm" "$la"
  done <<EOF
$(for f in "$2"/roster-*.state; do [ -f "$f" ] && [ ! -L "$f" ] && printf '%s\n' "$f"; done | awk -v at="$3" '
    function kv(line, key,   i, n, p) {
      n = split(line, p, "|")
      for (i = 1; i <= n; i++) if (index(p[i], key "=") == 1) return substr(p[i], length(key) + 2)
      return ""
    }
    { while ((getline line < $0) > 0) {
        if (index(line, "roster-state/") != 1 || kv(line, "status") != "intended") continue
        l = kv(line, "launched_at"); p = kv(line, "plan")
        if (p != "" && p != "none" && l > at) print p "\t" kv(line, "name") "\t" l
      }
      close($0) }' 2>/dev/null)
EOF
}

adopt_handoff_note() {  # <bound plan, raw> <repo root> <state dir>
  local plan at names="" n=0 nm la
  [ -n "$1" ] || return 0
  plan="$(adopt_abs "$1" "$2")"
  [ -f "$plan" ] && [ -r "$plan" ] || return 0
  at="$(handoff_written_at "$plan")"
  [ -n "$at" ] || return 0
  while IFS="$(printf '\t')" read -r nm la; do
    [ -n "$nm" ] || continue
    names="${names:+$names, }$nm"; n=$((n + 1))
  done <<EOF
$(handoff_dispatches_since "$1" "$3" "$at")
EOF
  if [ "$n" -eq 0 ]; then
    say "handoff written $at — current: no dispatch of this plan since"
  else
    say "handoff written $at — STALE: $n dispatch(es) of this plan since ($(clean "$names")); rewrite it: bash ${HOOK_DIR}/session-poker.sh handoff"
  fi
}

# THE HANDOFF MARKED WHERE IT IS READ (wave-34 T29; D24, AC-14.2). adopt saying STALE reaches only the
# session that runs adopt; a person or a session reading the plan's `## Handoff` was still told "safe to
# exit: yes" while writers dispatched after it ran (this wave's own plan, 11:32Z against T19, T22, T21).
# So the plan writer that runs at every dispatch (`launch-sync`) rewrites the block's two safety lines,
# and nothing else in it, to STALE, naming each later dispatch at its local time and its ISO instant,
# until `handoff` writes the block again. The lines are recomputed whole each time, so a second run with
# no new dispatch writes nothing. A handoff with no safety lines (written before T6) is left as it is.
handoff_local_time() {  # <ISO-8601 Z> -> `YYYY-MM-DD HH:MM <zone>` on this machine's clock, empty if unreadable
  local e
  e="$(iso_epoch "$1")"
  [ -n "$e" ] || return 0
  date -r "$e" '+%Y-%m-%d %H:%M %Z' 2>/dev/null || date -d "@$e" '+%Y-%m-%d %H:%M %Z' 2>/dev/null
}

handoff_mark_stale() {  # <bound plan, raw> <plan file in> <state dir> <out> -> 0 when <out> is <in> marked and differs from it
  local at list="" nm la loc
  at="$(handoff_written_at "$2")"
  [ -n "$at" ] || return 1
  while IFS="$(printf '\t')" read -r nm la; do
    [ -n "$nm" ] || continue
    loc="$(handoff_local_time "$la")"
    list="${list:+$list, }$(clean "$nm") at ${loc:+$loc }($la)"
  done <<EOF
$(handoff_dispatches_since "$1" "$3" "$at")
EOF
  [ -n "$list" ] || return 1
  HM_EXIT="no — STALE: dispatched after this handoff was written: $list; rewrite it: session-poker.sh handoff" \
  HM_CLEAR="no — STALE, for the same reason" awk '
    /^[ \t]*```/ { f = !f; print; next }
    f { print; next }
    /^##[ \t]/ { h = ($0 ~ /^##[ \t]+Handoff[ \t]*$/); print; next }
    h && index($0, "- safe to exit:") == 1 { print "- safe to exit: " ENVIRON["HM_EXIT"]; next }
    h && index($0, "- safe to /clear:") == 1 { print "- safe to /clear: " ENVIRON["HM_CLEAR"]; next }
    { print }' "$2" > "$4" 2>/dev/null || return 1
  ! cmp -s "$2" "$4"
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
adopt_write_row() {  # <roster file> <sid> <name> <id> <type> <deliverable> <progress> <cadence> <launched> <from-sid> <teammate address> <plan|none> <waiver> [<source row> [<suites_source> [<done> [<lands_red> <red_evidence> <row>]]]] -> 0 written/already there, 1 not
  local f="$1" sid="$2" name="$3" id="$4" typ="$5" deliv="$6" prog="$7" cad="$8"
  local launch="$9" osid="${10}" addr="${11}" plan="${12:-none}" waiver="${13:-}" d
  local src="${14:-}" ssrc="${15:-}" dmark="${16:-}"
  local lred="${17:-}" revid="${18:-}" lrow="${19:-}"
  local -a RR_ARGS
  local ROW=""
  local -a LIST_FIELDS_ARGS
  local lf
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
  # THE LIST FIELDS ARE READ OFF THE SOURCE ROW BY KEY, EVERY ONE OF THE SET (wave-37 T7, REQ-8,
  # D11). `ROSTER_LIST_FIELDS` (payload/scripts/lib/roster.sh) names them once, and `<source row>`
  # is the row-shaped string `adopt_fold` built from the predecessor's roster: the merged value of
  # each list field the name ever carried, a key present only where the predecessor stated one.
  # Each field present is passed whole, so `questions=` and `claims=` travel as `files=` does,
  # byte for byte, where they used to be dropped and written empty. The field name goes to
  # `clean` so the cut is skipped for the set and `re_executes=` is decoded (see `clean`): the
  # value reaches `roster_row` as the brief spelled it and is encoded there, once.
  #
  # THREE OF THEM TRAVEL AS A GROUP BESIDE `suites_source=`, AND ONLY WHEN THE SOURCE ROW HAD THE
  # GROUP (wave-01 S13, spec AC-20). `roster_row` emits `files=`, `suites_allowed=` and
  # `suites_source=` present-if-PASSED, and the distinction is load-bearing at the writer-side
  # guard: a row with `suites_allowed=` empty stated a budget that came out empty, while a row
  # with no such key at all was written before the wall existed. Adopting the second kind must
  # not manufacture the first. All three go or none do — an empty member of a stated group is
  # itself a statement, and splitting them would let a resumed row claim a source for a set it
  # does not carry. The group rule is unchanged by the set above: it adds the empty member a
  # stated group is missing, and nothing else.
  LIST_FIELDS_ARGS=()
  for lf in $ROSTER_LIST_FIELDS; do
    if row_has_key "$src" "$lf"; then
      LIST_FIELDS_ARGS+=("$lf=$(clean "$(line_field "$src" "$lf")" "$lf")")
    fi
  done
  if [ -n "$ssrc" ] || row_has_key "$src" files || row_has_key "$src" suites_allowed; then
    row_has_key "$src" files || LIST_FIELDS_ARGS+=("files=")
    row_has_key "$src" suites_allowed || LIST_FIELDS_ARGS+=("suites_allowed=")
    LIST_FIELDS_ARGS+=("suites_source=$(clean "$ssrc")")
  fi
  # THE ROW IS BUILT BY `roster_row` (payload/scripts/lib/roster.sh), not by a format string
  # here (spec AC-25, ledger D3). The fields this writer leaves EMPTY are still named
  # — `model=`, `duration=`, `absent=` and the rest; `claims=` is the library's own empty unless
  # the source row stated one — because an omitted key and
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
    "cadence=$(clean "$cad")"
    absent=
    "waiver=$(clean "$waiver")"
    ${LIST_FIELDS_ARGS[@]+"${LIST_FIELDS_ARGS[@]}"}
    ${dmark:+"done=$(clean "$dmark")"}
    "teammate_id=$(clean "$addr")"
    "adopted_from=$(clean "$osid")"
    tool_use_id=
    "plan=$(clean "$plan")"
    ${lred:+"lands_red=$(clean "$lred")"}
    ${revid:+"red_evidence=$(clean "$revid")"}
    ${lrow:+"row=$(clean "$lrow")"}
  )
  # THE DECLARED RUNS RIDE THE SAME LOOP (REQ-1 AC-1.1's adopt half; wave-37 T7, D11).
  # `re_executes=` is one of the list fields, so the loop above passes it with its name and
  # `clean` decodes the stored form: the value reaches `roster_row` as the brief spelled it,
  # and `roster_row` encodes it again on the way out, so the row this writer appends holds the
  # predecessor's bytes. There is one call to the builder and no fallback append: a key the
  # builder did not know would refuse the whole row here, and `roster_row` has taken every key
  # of the set (tests/session-poker-4.test.sh §LIST pins it).
  ROW="$(roster_row "${RR_ARGS[@]}")" || return 1
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
# THE SWEEP'S OWN QUESTION, ASKED OF ONE SESSION (REQ-9 AC-9.1; D10), lives in lib/fill.sh as the first
# arm of `roster_row_open` (wave-36 T10; AC-4.4): dead (not among the live ids) AND every state file older
# than the window `sweep --window` defers inside. Both halves, never one: a `/clear` leaves the
# predecessor dead within seconds while its roster is the freshest file here. The dispatch wall's hold
# asks the same function, so a row this verb counts closed is a row the wall admits over.

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

# born_floor_backing <plan> <repo> <suite> -> BFB_OF (`floor` or `standing@<12-hex>`) and rc 0 when a red the machine
# recorded backs a floor-born marker for <suite>; rc 1 otherwise, BFB_OWED and BFB_BRANCH set for the refusal's words
# (wave-36 T42; D9, design-ledger Δ8, born of critic-adversarial #1). THE TWO FACTS, asked in this order: (a) the
# plan's newest floor proof owes the suite (lib/proof.sh `_proof_last_read` floor owed, the reader `proof-add
# inherited` asks), or (b) the run's landing record (`proof_debt_record`) holds an `ev=standing` event for the suite
# whose head is a commit on the working branch's ref (`proof_branch_head`), the newest such event first. A marker the
# judge holds every chain by is no declaration. No library gives a standing event a reader; this is the one awk, over
# the file, and it reads the fields as lib/line.sh's fold does (`fv`, a suite by its file name).
BFB_OF=""; BFB_OWED=""; BFB_BRANCH=""
born_floor_backing() {
  local plan="$1" repo="$2" suite="$3" rec bh h
  BFB_OF=""; BFB_OWED="$(_proof_last_read "$plan" floor owed)"; BFB_BRANCH="$(plan_working_branch "$plan" 2>/dev/null)"
  case ",$BFB_OWED," in *",$suite,"*) BFB_OF=floor; return 0 ;; esac
  rec="$(proof_debt_record "$plan" "$repo" 2>/dev/null)" && [ -f "$rec" ] || return 1
  bh="$(proof_branch_head "$plan" "$repo")" || return 1
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    h="$(git -C "$repo" rev-parse --verify -q "${h}^{commit}" 2>/dev/null)" || continue
    git -C "$repo" merge-base --is-ancestor "$h" "$bh" 2>/dev/null || continue
    BFB_OF="standing@${h:0:12}"; return 0
  done <<BFB_STANDING
$(awk -F'|' -v want="$suite" '
    function fv(k,   i) { for (i = 3; i <= NF; i++) if (index($i, k "=") == 1) return substr($i, length(k) + 2); return "" }
    $1 == "line/v1" && $2 == "ev=standing" { s = fv("suite"); sub(/.*\//, "", s); if (s == want && fv("head") != "") h[++n] = fv("head") }
    END { for (i = n; i >= 1; i--) print h[i] }' "$rec" 2>/dev/null)
BFB_STANDING
  return 1
}

# poker_files_cell <id> <kind> <agent> <Files cell> <repo> <plan> -> PFC_OUT (the cell to write) and PFC_ART (the
# record artifact a reader row gained, or empty); returns 0, or 1 / 2 with the refusal printed. THE ONE JUDGE OF A
# ROW'S FILES CELL (wave-36 T41; REQ-7 AC-7.1, AC-10.2; D13): `task-add` writes a row's cell and `task-set files=`
# corrects a pending row's, and both are held to it. A reader row (verify, test, review) whose cell names no record
# gains <record dir>/<id>.md, the artifact `brief` gives it; the cell is then read as the dispatch wall will read it
# (`lift_contract_fields` and `brief_validate_fields`), a cell the lift reads as no path being refused now in the
# grammar's words. `—`, `-` and empty declare nothing to judge. ONE FACT IS THE BRIEF'S, NOT THE CELL'S: a `Files:`
# line alone names no suite, and here that is a note, the row going in.
PFC_OUT=""; PFC_ART=""
poker_files_cell() {
  local id="$1" kind="$2" agent="$3" files="$4" repo="$5" plan="$6" fact cell_facts=""
  PFC_OUT="$files"; PFC_ART=""
  if poker_reader_kind "$kind" && [ -z "$(poker_brief_record_entry "$files" artifact "$id")" ]; then
    PFC_ART="$(docs_root "$repo")/record/$(proof_plan_slug "$plan")/$id.md"
    case "$PFC_ART" in "$repo"/*) PFC_ART="${PFC_ART#"$repo"/}" ;; esac
    case "$files" in ''|'—'|'-') PFC_OUT="$PFC_ART" ;; *) PFC_OUT="$files, $PFC_ART" ;; esac
  fi
  case "$PFC_OUT" in
    ''|'—'|'-') return 0 ;;
  esac
  if ! poker_brief_load; then
    die "REFUSED — the contract grammar (lib/brief.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
    return 2
  fi
  POKER_BRIEF_FACTS=""; POKER_BRIEF_WORDS=""
  brief_validate_fields "$(lift_contract_fields "Files: $PFC_OUT" "$agent")" \
    "$agent" "$repo" poker_brief_sink || :
  while IFS= read -r fact; do
    [ -n "$fact" ] || continue
    case "$fact" in
      'Files: alone names no suite')
        note "$fact — a dispatch of $id will need a Suites: or Re-executes: line" ;;
      *) cell_facts="${cell_facts}${fact}"$'\n' ;;
    esac
  done <<EOF
$POKER_BRIEF_FACTS
EOF
  if [ -n "$cell_facts" ]; then
    die "REFUSED — a dispatch of $id with Files: $PFC_OUT would be refused by the dispatch grammar; the plan is unchanged:"
    printf '%s' "$POKER_BRIEF_WORDS" >&2
    return 1
  fi
  return 0
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

# ---- BEGIN the brief rendered from its row (wave-33 T9; REQ-4 AC-4.4; D8) ----
# `brief <row>` writes the dispatch brief a plan row can carry, so the orchestrator writes only the judgment the
# row cannot. THE SCAFFOLD'S LABELS ARE THE SHIPPED ONES, read out of skills/canonical-sdlc/dispatch.md's
# `### Scaffold` fence with the extractor hooks/dispatch-preflight.sh `dp_scaffold_marked` reads the same fence
# with, never a second list: a label the verb fills from the row is written, every other label is named on the
# verb's own line as the orchestrator's. THE RULES, each the row's own cell or a function of it:
#   Expected duration   the row's size, in minutes
#   Expected artifact   the dispatch ledger's artifact cell for the row; else the first Files entry under record/
#                       that is neither a progress file nor assumptions.md; else the first record path the
#                       row's task names; else, for a reader row (verify, test, review), <record dir>/<row>.md,
#                       which its Files line then carries (wave-35 T8; AC-6.1); else the slot, marked
#   Progress artifact   the Files entry that ends .progress.md, else <record dir>/<row>.progress.md; Cadence is
#                       the 15-minute rule's own number. Both only for a size of 15 or more
#   Files               the row's Files cell, verbatim; no line for a row whose cell is empty or a dash
#   Suites, Lands-on    the row's `suites` / `lands-on` cells when the table has them and the row fills them;
#                       else the *.test.sh entries of Files by file name; else, for a row whose Files write
#                       code, the suites `anchors index` names for those files at the working head, or the
#                       slot marked for the orchestrator, never none (wave-35 T8; AC-6.3); `Suites: none`
#                       and `Lands-on: none <reason>` only for a row that writes no code
#   Row                 the row's id
# The file starts with the scaffold lines, so no prose after them is a label's first hit (lib/brief.sh reads the
# first hit of an unpinned label). A re-render keeps everything from `## Judgment` on: that section is the
# orchestrator's, and the verb never writes anything into it but the two marked slots of a first render.

# poker_brief_cell <plan> <section heading> <row id> <header> -> that cell of the row, trimmed; rc 1 when the
# section, the column or the row is not there. For the cells units.sh's fixed columns do not carry.
poker_brief_cell() {
  awk -v sect="$2" -v id="$3" -v want="$4" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insec = (tolower(trim(substr($0, 3))) == tolower(sect)); hdr = 0; col = 0; next }
    !insec || $0 !~ /^[[:space:]]*\|/ { next }
    {
      n = split($0, c, "|")
      if (!hdr) { hdr = 1; for (i = 2; i < n; i++) if (tolower(trim(c[i])) == tolower(want)) col = i; next }
      if (c[2] ~ /^[ \t]*:?-+:?[ \t]*$/) next
      if (col && trim(c[2]) == id) { print trim(c[col]); found = 1; exit }
    }
    END { exit !found }' "$1"
}

# poker_brief_labels -> the shipped scaffold's label names, one per line, in its order. rc 1 when the file is not there.
poker_brief_labels() {
  local file="${HOOK_DIR}/../skills/canonical-sdlc/dispatch.md"
  [ -r "$file" ] || return 1
  /usr/bin/awk '
    /^### Scaffold/            { inb = 1; next }
    inb && /^```/              { fence++; if (fence == 2) exit; next }
    inb && fence == 1          { sub(/:.*$/, ""); print }
  ' "$file"
}

# poker_brief_none <cell> -> 0 when a table cell says nothing: empty, or a dash.
poker_brief_none() {
  case "$1" in ''|'—'|'-'|'–') return 0 ;; esac
  return 1
}

# poker_brief_suites <Files cell> -> the suites its *.test.sh entries name, by file name, in order, once each, comma-joined.
poker_brief_suites() {
  printf '%s' "$1" | awk -F',' '{
    for (i = 1; i <= NF; i++) {
      e = $i; gsub(/`/, "", e); sub(/^[ \t]+/, "", e); sub(/[ \t]+$/, "", e)
      if (e == "" || e ~ /[ \t]/ || index(e, "*") || index(e, "?") || index(e, "[")) continue
      n = split(e, p, "/"); b = p[n]
      if (length(b) <= 8 || substr(b, length(b) - 7) != ".test.sh") continue
      if (!(b in seen)) { seen[b] = 1; out = out (out == "" ? "" : ", ") b }
    }
    print out }'
}

# poker_brief_record_entry <Files cell> <artifact|progress|named> <row id> -> an entry under record/ for the row; nothing
# when none. THE ONE RULE FOR A ROW'S RECORD (wave-37 T6; REQ-7 AC-7.1, AC-7.2; D10), read by `brief` and judged by
# `task-set files=`: `named` is the entry whose basename is <row>.md or starts <row>- (never a progress file);
# `artifact` is the named entry, else the first entry that is neither a progress file nor assumptions.md; `progress`
# is the first entry ending .progress.md.
poker_brief_record_entry() {
  printf '%s' "$1" | awk -F',' -v kind="$2" -v row="$3" '{
    for (i = 1; i <= NF; i++) {
      e = $i; gsub(/`/, "", e); sub(/^[ \t]+/, "", e); sub(/[ \t]+$/, "", e)
      if (e == "" || e ~ /[ \t]/ || index(e, "record/") == 0 || substr(e, length(e) - 2) != ".md") continue
      n = split(e, p, "/"); b = p[n]
      isprog = (length(b) > 12 && substr(b, length(b) - 11) == ".progress.md")
      if (kind == "progress") { if (isprog) { print e; exit } continue }
      if (isprog || b == "assumptions.md") continue
      if (row != "" && (b == row ".md" || index(b, row "-") == 1)) { print e; hit = 1; exit }
      if (fb == "") fb = e
    }
  } END { if (!hit && kind == "artifact" && fb != "") print fb }'
}

# poker_brief_task_record <task text> -> the first record path the text names (a token holding record/ and ending .md); nothing when none.
poker_brief_task_record() {
  printf '%s\n' "$1" | awk '{
    n = split($0, w, /[ \t,;()"\047`]+/)
    for (i = 1; i <= n; i++) if (index(w[i], "record/") > 0 && w[i] ~ /\.md$/) { print w[i]; exit }
  }'
}

# poker_brief_index_suites <root> <at> <Files cell> -> lib/anchors.sh `reads_suites`, comma-joined: the suites the reads
# index names, at <at> (a commit, or - for the files under <root>), for any file an entry of the cell covers. Nothing
# when no suite reads such a file, or the library cannot be loaded (wave-35 T8; REQ-6 AC-6.3; D15, D9). THE ONE
# READER (wave-37 T3; D4): the dispatch wall's Lands-on arm calls the same `reads_suites`, and the floor's cover rule
# reads the same index.
poker_brief_index_suites() {
  declare -F reads_suites >/dev/null 2>&1 \
    || { [ -n "$BIONIC_LIB" ] && [ -r "$BIONIC_LIB/anchors.sh" ] && . "$BIONIC_LIB/anchors.sh"; } || return 0
  declare -F reads_suites >/dev/null 2>&1 || return 0
  reads_suites "$1" "$2" "$3" | awk 'NF { o = o (o == "" ? "" : ", ") $0 } END { printf "%s", o }'
}

# poker_reader_kind <kind> -> 0 for a reader row's kind (verify, test, review): its artifact is a record it writes.
poker_reader_kind() { case "$1" in verify|test|review) return 0 ;; esac; return 1; }
# ---- END the brief rendered from its row ----

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
# plan_verb_open <verb> [closed-ok] -> sets PV_REPO, PV_PLAN, PV_CUR, PV_SUM, PV_NEW, PV_DRY, PV_MARK, PV_SID
# and arms the cleanup; exits on every refusal above. `closed-ok` (task-set --reason, wave-36 T14; AC-7.7) also
# takes the session's own closed run (bound-closed) when its plan is on disk; engagement is asked first either way
# (ruling r1791954201-85499: engagement is the consent boundary).
plan_verb_open() {
  local verb="$1" closed="${2:-}" sid run
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
  PV_PLAN=""
  case "$run" in
    'bound-open '*) PV_PLAN="${run#bound-open }" ;;
    'bound-closed '*) [ "$closed" != closed-ok ] || [ ! -f "${run#bound-closed }" ] || PV_PLAN="${run#bound-closed }" ;;
  esac
  if [ -z "$PV_PLAN" ]; then
    die "REFUSED — $verb writes the plan this session is bound to, and it has no bound open run (${run:-none})."
    die "Bind this session to its run first (this script's bind verb), then run $verb again."
    case "$run" in
      'bound-closed '*) [ "$verb" != task-set ] || die "A delivered run takes task-set with --reason '<why>', which records the reason on each row's step line." ;;
    esac
    exit 1
  fi
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
    [ "$verb" = current ] && die "missing: $(pv_missing "$err")"
    exit 1
  fi
}

# pv_missing <the gate's refusal text> -> what the plan lacks, in the gate's words, as the one line `current N`'s
# refusal ends on (wave-35 T8; REQ-6 AC-6.5; D15): a step line the gate found absent, with the verb that writes it;
# the fields a step block lacks, with the verb that writes each; else the gate's first detail line as it gave it.
pv_missing() {
  local n f
  n="$(printf '%s\n' "$1" | sed -n "s/.*has no 'Step \([0-9][0-9]*[ab]\{0,1\}\):' line.*/\1/p" | head -1)"
  if [ -n "$n" ]; then
    printf "the line '- Step %s: <its evidence>' under ## SDLC State (step-line %s '<text>' writes it)" "$n" "$n"
    return 0
  fi
  n="$(printf '%s\n' "$1" | sed -n 's/.*step \([0-9][0-9]*[ab]\{0,1\}\) evidence missing required field(s): \(.*\)$/\1/p' | head -1)"
  f="$(printf '%s\n' "$1" | sed -n 's/.*step [0-9][0-9]*[ab]\{0,1\} evidence missing required field(s): \(.*\)$/\1/p' | head -1)"
  if [ -n "$n" ] && [ -n "$f" ]; then
    printf "the Step %s block's %s (step-field %s <key>=<value> writes each)" "$n" "$(printf '%s' "$f" | awk '{ for (i = 1; i <= NF; i++) printf "%s%s:", (i > 1 ? " " : ""), $i }')" "$n"
    return 0
  fi
  printf '%s\n' "$1" | awk '
    /^bionic: / { seen = 1; next }
    seen && NF { sub(/^[ \t]+/, ""); sub(/^canonical-sdlc /, ""); print; found = 1; exit }
    END { if (!found) print "the line or block that step owes (the gate gave no detail)" }'
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

# ---------------------------------------------------------------- the call a refusal names
#
# EVERY PLAN-VERB REFUSAL NAMES THE CALL THAT SUCCEEDS (wave-33 T7; REQ-4 AC-4.3, D8). A refusal
# that says what is wrong and not what to run costs one retry per guess; wave-32 met three
# (ledger-add's column names, task-add's approval read on a doc row, decline --on a file). Where the
# verb can compute the corrected call it prints it on a line of its own, `poker: next call: <call>`,
# quoted by the one rule every pasted poker command is (`launch_sync_hand`, refuse.sh
# `refuse_shell_word`), so the line runs as printed.
pv_next() {  # <verb> <operand>... -> the call on stderr, one line
  die "next call: $(launch_sync_hand "$@")"
}

# pv_fold <name> -> its letters and digits, lower-cased: the form two column names are compared in.
pv_fold() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'; }

# pv_column_guess <name> <column>... -> the one column <name> was meant as, or nothing: the column
# whose folded name equals the name's, else the ONE column whose folded name is a prefix of the
# name's or has it as a prefix (`artifacts` is `artifact`, `sizes` is `size`). Two are no guess.
pv_column_guess() {
  local want c f n=0 hit=""
  want="$(pv_fold "$1")"; shift
  [ -n "$want" ] || return 0
  for c in "$@"; do [ "$(pv_fold "$c")" = "$want" ] && { printf '%s' "$c"; return 0; }; done
  for c in "$@"; do
    f="$(pv_fold "$c")"
    [ -n "$f" ] || continue
    case "$want" in "$f"*) n=$((n + 1)); hit="$c"; continue ;; esac
    case "$f" in "$want"*) n=$((n + 1)); hit="$c" ;; esac
  done
  [ "$n" -eq 1 ] && printf '%s' "$hit"
  return 0
}

# pv_fix_pairs <columns, one per line> <name=value>... -> PV_FIXED, the pairs with each name the
# columns do not carry (compared case-blind) replaced by its one guess, and PV_UNKNOWN, the names no
# column was guessed for (comma-joined), which the corrected call leaves out.
pv_fix_pairs() {
  local cols="$1" kv n g c known
  local -a list
  list=(); PV_FIXED=(); PV_UNKNOWN=""
  shift
  while IFS= read -r c; do [ -n "$c" ] && list+=("$c"); done <<< "$cols"
  for kv in "$@"; do
    n="${kv%%=*}"; known=""
    for c in ${list[@]+"${list[@]}"}; do
      [ "$(printf '%s' "$c" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]')" ] && known=1
    done
    if [ -n "$known" ]; then PV_FIXED+=("$kv"); continue; fi
    g="$(pv_column_guess "$n" ${list[@]+"${list[@]}"})"
    if [ -n "$g" ]; then PV_FIXED+=("$g=${kv#*=}"); else PV_UNKNOWN="${PV_UNKNOWN:+$PV_UNKNOWN, }$n"; fi
  done
}

# pv_header_cells <plan> <tasks|ledger> -> the header cells of the table `units_table_cells` edits (the
# first table under the heading whose header carries an id cell), trimmed, one per line.
pv_header_cells() {
  PH_SECT="$2" awk '
    function trim(v) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); return v }
    BEGIN { sect = ENVIRON["PH_SECT"] }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^[ \t]*#/ {
      if (st) exit
      if (sect == "tasks" && $0 ~ /^##[ \t]+[Tt]asks([ \t].*)?$/) st = 1
      if (sect == "ledger" && $0 ~ /^##[ \t]+[Dd]ispatch[ \t]+[Ll]edger([ \t].*)?$/) st = 1
      next
    }
    st && /^[ \t]*\|/ {
      n = split($0, c, "|"); ok = 0
      for (i = 2; i < n; i++) if (tolower(trim(c[i])) == "id") ok = 1
      if (!ok) next
      for (i = 2; i < n; i++) if (trim(c[i]) != "") print trim(c[i])
      exit
    }' "$1" 2>/dev/null
}

# THE MATRIX ROW'S CELLS (discharge's row edit, wave-30 T14, made the one site at wave-33 T7). Inside
# `## Verification Matrix`, fences skipped, the first `|` line whose trimmed first cell is the AC id has
# each named cell (1 AC · 2 tier · 3 status · 4 evidence · 5 auditor) written ` <value> `, every other
# byte as it was. It does not fold `\|` escapes; a matrix cell holds a path or a token. Exit 3 no row ·
# 4 the row is not five cells.
matrix_row_cells() {  # <plan> <AC> <cell n>=<value>... -> the whole plan
  local plan="$1" ac="$2" set="" kv
  shift 2
  for kv in "$@"; do set="${set}${kv%%=*}	${kv#*=}
"; done
  MX_AC="$ac" MX_SET="$set" awk '
    BEGIN {
      a = ENVIRON["MX_AC"]; m = split(ENVIRON["MX_SET"], s, "\n")
      for (k = 1; k <= m; k++) if ((t = index(s[k], "\t")) > 0) v[substr(s[k], 1, t - 1) + 1] = " " substr(s[k], t + 1) " "
    }
    /^[ \t]*```/ { fence = !fence; print; next }
    fence { print; next }
    /^## / { inm = ($0 ~ /^## Verification Matrix/); print; next }
    inm && !done && /^[ \t]*\|/ {
      n = split($0, c, "|"); id = c[2]; gsub(/^[ \t]+|[ \t]+$/, "", id)
      if (id == a) {
        if (n != 7) { bad = 1; exit }
        for (j in v) c[j] = v[j]
        out = c[1]; for (j = 2; j <= n; j++) out = out "|" c[j]
        print out; done = 1; next
      }
    }
    { print }
    END { if (bad) exit 4; if (!done) exit 3 }' "$plan"
}

# matrix_row_cell <plan> <AC> <cell n> -> that cell of the AC's matrix row, trimmed (nothing: no row).
matrix_row_cell() {
  MX_AC="$2" awk -F'|' -v n="$3" '
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^## / { inm = ($0 ~ /^## Verification Matrix/); next }
    inm && /^[ \t]*\|/ { c = $2; gsub(/^[ \t]+|[ \t]+$/, "", c)
      if (c == ENVIRON["MX_AC"]) { v = $(n + 1); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit } }' "$1"
}

# THE AC BLOCK'S KEYS (wave-33 T7). The block is the `<AC>:` line under `## Verification Matrix`, text after the
# colon allowed (matrix-render writes the criterion there), and the indented lines under it (matrix-render's shape,
# the one walls.sh `matrix_block` reads); both read the heading through lib/units.sh `units_ac_head_awk` (wave-36 T24). The key's
# first line is replaced where it stands; a key the block lacks goes after its last line. Exit 3 no block.
matrix_block_key() {  # <plan> <AC> <key> <value> -> the whole plan
  MB_AC="$2" MB_KEY="$3" MB_VAL="$4" awk "$(units_ac_head_awk)"'
    BEGIN { a = ENVIRON["MB_AC"]; k = ENVIRON["MB_KEY"] ":"; line = "  " ENVIRON["MB_KEY"] ": " ENVIRON["MB_VAL"] }
    { L[++nl] = $0 }
    END {
      for (i = 1; i <= nl; i++) {
        x = L[i]
        if (x ~ /^[ \t]*```/) { fence = !fence; continue }
        if (fence) continue
        if (x ~ /^## /) { inm = (x ~ /^## Verification Matrix/); inb = 0; continue }
        if (!inm) continue
        y = x; sub(/[ \t]+$/, "", y)
        if (!found && ac_head(x, a)) { found = i; last = i; inb = 1; continue }
        if (inb && x ~ /^[ \t]+[^ \t]/) {
          last = i; sub(/^[ \t]+/, "", y)
          if (!at && index(y, k) == 1) at = i
          continue
        }
        inb = 0
      }
      if (!found) exit 3
      for (i = 1; i <= nl; i++) {
        if (i == at) { print line; continue }
        print L[i]
        if (!at && i == last) print line
      }
    }' "$1"
}

# matrix_block_has <plan> <AC> <key> -> 0 when the AC block carries that key.
matrix_block_has() {
  MB_AC="$2" MB_KEY="$3" awk "$(units_ac_head_awk)"'
    BEGIN { a = ENVIRON["MB_AC"]; k = ENVIRON["MB_KEY"] ":" }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^## / { inm = ($0 ~ /^## Verification Matrix/); inb = 0; next }
    !inm { next }
    { y = $0; sub(/[ \t]+$/, "", y) }
    ac_head($0, a) { inb = 1; next }
    inb && /^[ \t]+[^ \t]/ { sub(/^[ \t]+/, "", y); if (index(y, k) == 1) { hit = 1; exit } next }
    { inb = 0 }
    END { exit !hit }' "$1"
}

# THE FILES BESIDE THE PLAN (wave-33 T7; REQ-3 AC-3.3, D8). `epic-row` and `continuation-fill` write the
# epic plan and the run's continuation, which close-out writes after act 3 has wiped this session's
# binding (A-orch-145), so their run is the `--plan` operand when given, else the session's own run, open
# or closed. Neither file is a run plan: the commit gate reads neither, so their transaction is the
# copy, the checksum taken before the projection, the compare and the move, with no dry commit.
# pv_file_open <verb> <operand>... -> PV_REPO, PV_RPLAN, and the cleanup armed; every refusal exits.
pv_file_open() {
  local verb="$1" sid run cand="" p
  shift
  sid="$(session_id)" || sid=""
  if [ -z "$sid" ]; then
    die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
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
  PV_NEW=""
  trap 'rm -f ${PV_NEW:+"$PV_NEW" "$PV_NEW.2"}' EXIT
  if [ -n "${PV_PLAN_ARG:-}" ]; then
    for p in "$PV_PLAN_ARG" "$PV_REPO/$PV_PLAN_ARG"; do
      case "$p" in /*) : ;; *) p="$PWD/$p" ;; esac
      [ -f "$p" ] && { PV_RPLAN="$p"; return 0; }
    done
    die "REFUSED — --plan $(clean "$PV_PLAN_ARG") is no file (read from $PWD and from $PV_REPO); nothing was written."
    exit 1
  fi
  run="$(session_run "$PV_REPO" "$sid" 2>/dev/null)" || :
  case "$run" in
    'bound-open '*) PV_RPLAN="${run#bound-open }"; return 0 ;;
    'bound-closed '*) PV_RPLAN="${run#bound-closed }"; [ -f "$PV_RPLAN" ] && return 0 ;;
    'fallback '*) cand="${run#fallback }" ;;
  esac
  case "$cand" in "$PV_REPO"/*) cand="${cand#"$PV_REPO"/}" ;; esac
  die "REFUSED — $verb writes for this session's run, and the session is bound to none (${run%% *}); close-out wipes the binding, so name the run's plan. Nothing was written."
  pv_next "$verb" "$@" --plan "${cand:-<plan>}"
  exit 1
}

# pv_file_swap <verb> <file> <checksum before> <what> -> moves $PV_NEW over the file when the file still
# reads as it did; exits 0 with nothing written when the projection is the file.
pv_file_swap() {
  local verb="$1" file="$2" sum="$3" what="$4"
  if cmp -s "$PV_NEW" "$file"; then
    say "$verb — $what: the file already reads so; nothing was written."
    exit 0
  fi
  if [ "$(cksum < "$file" 2>/dev/null)" != "$sum" ]; then
    die "REFUSED — $file changed while $what was being written; nothing was written. Run $verb again."
    exit 1
  fi
  if ! mv -f "$PV_NEW" "$file"; then
    die "REFUSED — could not move the copy over $file; it is unchanged."
    exit 2
  fi
}

# THE USER'S WORDS, REFUSED IN ONE VOICE (wave-33 T7). finding-move and waive-row hold their words to
# lib/said.sh `user_said`; its three refusals are written here once, the minimum named by the library's
# own constant. <act> is what the words make: `a move`, `a waiver`.
#
# THE RUN'S SESSIONS (wave-36 T9; D10): `user_said` reads every session the plan records, then this one,
# and says which it read (SAID_SESSIONS) and asked for (SAID_TRIED); a refusal names them, so a reader can
# tell "not typed" from "typed in a session the run never recorded".
#
# THE SESSIONS THE PROJECT DOES NOT WITNESS (wave-37 T5; D9, AC-5.3): a session with no load record under
# this root, or no transcript under this project's own directory, is not read (lib/said.sh SAID_REFUSED);
# after the sentence, the refusal lists `read: <sids>` and one `refused: <sid> (<reason>)` per such session.
said_refuse() {  # <user_said rc> <the words, folded> <act> -> the refusal on stderr
  local sr_l
  case "$1" in
    2) die "REFUSED — the transcript cannot be found or read for any session read (${SAID_TRIED:-${CLAUDE_CODE_SESSION_ID:-none}} under ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects), so the words cannot be held to what the user typed; the plan is unchanged." ;;
    3) die "REFUSED — the words \"$(clean "$2")\" are too short to be the user's decision; quote at least $SAID_MIN_WORDS of their words, or their whole prompt. The plan is unchanged." ;;
    *) die "REFUSED — the words \"$(clean "$2")\" stand in no prompt the user typed in this session or another session the run recorded (read: ${SAID_SESSIONS:-none}); $3 is the user's own word, quoted from a prompt they typed. The plan is unchanged." ;;
  esac
  [ -n "${SAID_REFUSED:-}" ] || return 0
  die "read: ${SAID_SESSIONS:-none}"
  while IFS= read -r sr_l; do
    [ -z "$sr_l" ] || die "refused: $(clean "$sr_l")"
  done <<SAID_REFUSE
$SAID_REFUSED
SAID_REFUSE
}

# A FAILING QUESTION IS THE PERSON'S TO WAIVE (wave-33 T35; AC-2.2, D2). A reading whose newest fact is
# result=fail leaves the person the call: fix it, or waive the question. So the judge's every answer
# settles the ledger (lib/owed.sh) for the waivable questions: each `failing` review line opens
# `waive:<question>`, the key the waive verb closes, carrying the line the refusal prints; every other
# question's item is closed, its block gone (a passing reading over the fix). Opening is idempotent per
# key, so a second refusal on the same question is one item. Prints nothing; never changes the verdict.
cur8_owed_waivers() {  # <facts_state output> -> always 0
  local q fl
  declare -F owed_open >/dev/null 2>&1 || return 0
  for q in $PROOF_QUESTIONS; do
    fl="$(printf '%s\n' "$1" | awk -F'\t' -v q="$q" '$1 == "review" && $2 == q && $(NF - 1) == "failing" { print; exit }')"
    if [ -n "$fl" ]; then
      OWED_ROOT="$PV_REPO" owed_open "waive:$q" "waiver: $q" "$fl" >/dev/null 2>&1
    else
      poker_owed_close "$PV_REPO" "waive:$q" "no longer failing"
    fi
  done
  return 0
}

# cur7_judge <step> -> returns when lib/proof.sh `facts_state` says every fact the bound plan owes holds at
# the working head, with that head in PV_HEAD8; otherwise refuses `current <step>`, exit 1, the plan unchanged,
# printing each owed line that does not hold, in the judge's own words: the owed suite, or the commit the walk
# cannot prove (wave-27 T14; D3). The judge's rc 2, a plan it cannot deal, refuses too, printing whatever the
# judge printed, whatever the reason.
# STEPS 7 AND 8 ASK IT (wave-35 T10; D10, AC-1.2): Step 7 is entered once the floor is Step 6's last act, so
# `current 7` is held to the same judge `current 8` is, and a run never leaves Step 6 with its floor behind
# the head.
# THE HEAD IS THE WORKING BRANCH'S REF (wave-35 T10; AC-1.7): lib/proof.sh `proof_branch_head`, the judge's one
# reading of it, never the head of a checkout, so a branch no checkout holds is judged where its ref points,
# and a branch that names no commit (deleted, or never made) is refused: there is no head, so the floor is
# uncovered.
# cover_basis <plan> <question> <a> <b> -> lib/proof.sh `facts_cover`'s lines for that range and question, with its rc
# (wave-37 T8; D8, AC-4.1, AC-4.2). THE ONE CALL OF THE LIBRARY'S BASIS in this file, shared by what prints it under
# a refused line (`cur7_judge`) and what prints it on ask (the `cover` verb), so the two cannot say different
# things of one range. Never called from the tick, `sched_facts_state`, `live_judge` or any wall: a person asks.
cover_basis() {
  if ! { declare -F facts_cover >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
     || ! declare -F facts_cover >/dev/null 2>&1; then
    printf 'cover: the proof record (lib/proof.sh) cannot be loaded from %s\n' "$BIONIC_LIB" >&2
    return 2
  fi
  facts_cover "$1" "$3" "$4" "$2"
}

cur7_judge() {  # <step>   (named for Step 7, the first step it judges; it judges Step 8 too)
  local step="$1" wb out rc err
  if ! { declare -F facts_state >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
     || ! declare -F facts_state >/dev/null 2>&1; then
    die "REFUSED — current: $step is admitted on the facts the run owes, and the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
    exit 2
  fi
  wb="$(plan_working_branch "$PV_PLAN")"
  if [ -z "$wb" ]; then
    die "REFUSED — current: $step is admitted on the facts the run owes at the working head, and the plan names no working-branch: (## SDLC State or its frontmatter), so the floor is uncovered; the plan is unchanged."
    exit 1
  fi
  PV_HEAD8="$(proof_branch_head "$PV_PLAN" "$PV_REPO")" || PV_HEAD8=""
  case "$PV_HEAD8" in
    [0-9a-f]*) : ;;
    *)
      die "REFUSED — current: $step is admitted on the facts the run owes at the working head, and the working branch $wb names no commit here, so the floor is uncovered (there is no head to judge); the plan is unchanged."
      exit 1 ;;
  esac
  out="$(facts_state "$PV_PLAN" "$PV_HEAD8" 2>"$PV_NEW.judge")"; rc=$?
  err="$(cat "$PV_NEW.judge" 2>/dev/null)"; rm -f "$PV_NEW.judge"
  [ "$rc" -eq 2 ] || cur8_owed_waivers "$out"
  [ "$rc" -eq 0 ] && return 0
  if [ "$rc" -eq 2 ]; then
    die "REFUSED — current: $step is admitted on the facts the run owes, and the judge could not deal this plan (facts_state exit 2); the plan is unchanged. The judge said:"
    [ -z "$err" ] || printf '%s\n' "$err" >&2
    [ -z "$out" ] || printf '%s\n' "$out" >&2
    exit 1
  fi
  die "REFUSED — current: $step is admitted only when every fact the run owes holds at the working head $PV_HEAD8, and these do not (facts_state):"
  # THE BASIS UNDER THE LINE (wave-37 T8; D8, AC-4.1): a `review <q> … uncovered <a>..<b>` line is a judge's "no"
  # with no why; under it go the `cover <sha> <basis>` lines for that range and question, and the line ends with
  # the ask that reproduces them (the `cover` verb). The text above is the refusal's own and does not change.
  local cv_line cv_k cv_q cv_rest cv_st cv_rng
  while IFS= read -r cv_line; do
    [ -n "$cv_line" ] || continue
    IFS='	' read -r cv_k cv_q cv_rest cv_rest cv_st cv_rng <<COVER_LINE
$cv_line
COVER_LINE
    case "$cv_k:$cv_st:$cv_rng" in
      review:uncovered:?*..?*)
        printf '%s · ask: session-poker.sh cover %s %s\n' "$cv_line" "$cv_q" "$cv_rng" >&2
        cover_basis "$PV_PLAN" "$cv_q" "${cv_rng%%..*}" "${cv_rng##*..}" >&2 || : ;;
      *) printf '%s\n' "$cv_line" >&2 ;;
    esac
  done <<COVER_JUDGED
$(printf '%s\n' "$out" | awk -F'\t' '$NF != "covered"')
COVER_JUDGED
  die "Take the reading or the regression run each line names and record it with proof-add, or have the user waive a question with waive <question> '<reply>'; the plan is unchanged."
  exit 1
}

# mr_tier_keys -> one `<tier><TAB><keys>` line for each of T0..T4, the keys walls.sh `keys_for_tier` names (wave-30
# T14; D9). The list is the gate's own, read by sourcing walls.sh in a subshell, so the stubs matrix-render writes and
# the keys the Verify gate demands cannot drift apart; nothing walls.sh defines outlives the subshell. rc 1 when the
# library or the function cannot be had.
mr_tier_keys() {
  [ -f "$BIONIC_LIB/walls.sh" ] || return 1
  ( . "$BIONIC_LIB/walls.sh" >/dev/null 2>&1 || exit 1
    declare -F keys_for_tier >/dev/null 2>&1 || exit 1
    for _mr_t in T0 T1 T2 T3 T4; do printf '%s\t%s\n' "$_mr_t" "$(keys_for_tier "$_mr_t")"; done )
}

# SERVES_AWK / serves_tasks — THE ONE READ OF "WHICH CRITERIA A ROW SERVES" (wave-31 T22; REQ-15 AC-15.1, D15,
# A-orch-51). A row serves a criterion when its `serves` cell names the criterion's AC id or the REQ id in the
# Eval design's Requirement column; that two-way read is `serves_hit`, and two verbs call it, never a second reader:
# matrix-render (a criterion's `task:` cell is the one row serving it) and row-landed (the evidence a landing writes
# into every criterion its row serves). The awk functions are concatenated ahead of each verb's program
# (`awk "$SERVES_AWK$MR_AWK"`); they own these globals: nt tid[] serves[] (serves_load), and evh col[] eseen[] ne ec[]
# ereq[] eapp[] eev[] efw[] (eval_row), which the program's own pass resets as its headings go by (evh = 0).
#   serves_load(spec)  spec = `<id><TAB><serves>` per `## Tasks` row, newline-joined (serves_tasks prints it)
#   serves_hit(t, cr)  1 when row index t serves criterion cr (its AC id, or its Requirement in ereq[])
#   eval_row(line)     one `## Eval design` table line: the header row names the columns, a data row fills ereq[] etc.
#   trim(v), cells(line, out)  the table-cell reads both programs share
SERVES_AWK='
function trim(v) { gsub(/^[ \t]+|[ \t]+$/, "", v); return v }
function cells(line, out,    n, i, t) {
  gsub(/\\\|/, "\001", line)
  n = split(line, t, "|")
  for (i = 2; i < n; i++) { out[i - 1] = trim(t[i]); gsub(/\001/, "|", out[i - 1]) }
  return n - 2
}
function serves_load(spec,    n0, i, tl, tv, ns, sv, s) {
  n0 = split(spec, tl, "\n"); nt = 0
  for (i = 1; i <= n0; i++) {
    split(tl[i], tv, "\t"); if (tv[1] == "") continue
    nt++; tid[nt] = tv[1]; ns = split(tv[2], sv, /[ ,;]+/)
    for (s = 1; s <= ns; s++) if (sv[s] != "") serves[nt, sv[s]] = 1
  }
}
function serves_hit(t, cr) {
  return (((t, cr) in serves) || (ereq[cr] != "" && ((t, ereq[cr]) in serves)))
}
function eval_row(line,    nc, c, j, cr) {
  if (line ~ /^[ \t]*\|[-|: \t]*$/) return
  nc = cells(line, c)
  if (!evh) { evh = 1; delete col; for (j = 1; j <= nc; j++) col[tolower(c[j])] = j; return }
  cr = ("criterion" in col) ? c[col["criterion"]] : ""
  if (cr == "" || (cr in eseen)) return
  eseen[cr] = 1; ne++; ec[ne] = cr
  ereq[cr] = ("requirement" in col) ? c[col["requirement"]] : ""
  eapp[cr] = ("approach" in col) ? c[col["approach"]] : ""
  eev[cr] = ("eval" in col) ? c[col["eval"]] : ""
  efw[cr] = ("fails when" in col) ? c[col["fails when"]] : ""
}'
# serves_tasks <plan> -> `<id><TAB><serves>` for each `## Tasks` row (lib/units.sh units_rows, the table's one reader).
serves_tasks() {
  units_rows "$1" 2>/dev/null | awk -F'\t' '$1 != "" { print $1 "\t" $8 }'
}

# mr_requirements_file <plan> <repo> -> the requirements file the plan names, when it is a readable file: its
# `requirements:` frontmatter key, else the Step-1 evidence line's `requirements:` field (walls.sh K5's pointer),
# resolved as the gate resolves it (walls.sh resolve_requirements_path: absolute stands, `specs/` is under the docs
# root, anything else under the project root); nothing when neither names a readable file (wave-35 T8; AC-6.4).
mr_requirements_file() {
  local raw abs
  raw="$(plan_frontmatter_get "$1" requirements 2>/dev/null)"
  if [ -z "$raw" ]; then
    raw="$(awk '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && /^[[:space:]]*-?[[:space:]]*Step[[:space:]]+1[[:space:]]*:/ {
        if (match($0, /(^|[^-_[:alnum:]])requirements[[:space:]]*:[[:space:]]*/)) {
          v = substr($0, RSTART + RLENGTH); sub(/;.*$/, "", v); sub(/[[:space:]]+$/, "", v); print v
        }
        exit
      }' "$1")"
  fi
  [ -n "$raw" ] || return 0
  case "$raw" in
    /*)      abs="$raw" ;;
    specs/*) abs="$(docs_root "$2")/$raw" ;;
    *)       abs="$2/$raw" ;;
  esac
  [ -f "$abs" ] && [ -r "$abs" ] && printf '%s' "$abs"
  return 0
}

# MR_AWK — matrix-render's one pass over the plan (wave-30 T14; D9). ENVIRON: MR_KEYS (mr_tier_keys), MR_TASKS
# (`<id><TAB><serves>` per ## Tasks row), MR_WALK (the frontmatter walk: value), MR_REQFILE (the requirements file the
# plan names, mr_requirements_file; empty when none), MR_COUNT (the side file: on success
# `<blocks written><TAB><keys added><TAB><blocks unchanged>`, on a refusal `<why><TAB><ids>`). Prints the rendered
# plan; exits 3 no Eval design criteria, 4 no matrix table, 5 a criterion with no matrix row, 6 a tier with no keys.
# The reads follow the gate's: fences skipped, a table cell trimmed, an AC block a flush-left `AC-<id>:` (a list
# bullet tolerated) and the indented lines under it until the next flush-left line (walls.sh `matrix_block`).
MR_AWK='
# acline(line) -> the criterion id of a `- AC-<n> <text>` bullet (bold and a colon tolerated), its text in ACT; "" else.
function acline(line,    id) {
  if (line !~ /^[-*][ \t]+/) return ""
  sub(/^[-*][ \t]+/, "", line); gsub(/\*\*/, "", line)
  if (!match(line, /^AC-[0-9A-Za-z.]*[0-9A-Za-z]/)) return ""
  id = substr(line, 1, RLENGTH); line = substr(line, RLENGTH + 1)
  if (line !~ /^[: \t]/ && line != "") return ""
  sub(/^:?[ \t]*/, "", line)
  if (index(line, " Fails when:")) line = substr(line, 1, index(line, " Fails when:") - 1)
  ACT = trim(line)
  return id
}
# readreq(f) -> fprov[REQ-<n>] and fact[AC-<n>] from the requirements file f: under each `### REQ-<n>` heading its
# first provenance: line and its `- AC-<n>` bullets; fences skipped, a `## ` heading ends the requirement.
function readreq(f,    l, h, a, fz) {
  if (f == "") return
  while ((getline l < f) > 0) {
    sub(/\r$/, "", l)
    if (l ~ /^[ \t]*```/) { fz = !fz; continue }
    if (fz) continue
    if (l ~ /^## /) { h = ""; continue }
    if (l ~ /^### /) { h = ""; if (match(l, /^###[ \t]+REQ-[0-9A-Za-z.]+/)) { h = substr(l, RSTART, RLENGTH); sub(/^###[ \t]+/, "", h) }; continue }
    if (h == "") continue
    if (l ~ /^provenance[ \t]*:/ && !(h in fprov)) { sub(/^provenance[ \t]*:[ \t]*/, "", l); fprov[h] = trim(l); continue }
    a = acline(l); if (a != "" && !(a in fact) && ACT != "") fact[a] = ACT
  }
  close(f)
}
function actext(cr) { return (cr in fact) ? fact[cr] : ((cr in pact) ? pact[cr] : "") }
function taskof(cr,    t, n, id) {
  n = 0
  for (t = 1; t <= nt; t++)
    if (serves_hit(t, cr)) { n++; id = tid[t] }
  return (n == 1) ? id : "pending"
}
# PROVENANCE IS THE REQUIREMENT\047S (wave-35 T8; REQ-6 AC-6.4; D15): the requirements file the plan names (fprov),
# else the plan\047s own `### REQ-<n>` line (prov), else pending; the Eval design\047s Approach is never a provenance.
function val(cr, k,    r) {
  if (k == "provenance") { r = ereq[cr]; if ((r in fprov) && fprov[r] != "") return fprov[r]; if ((r in prov) && prov[r] != "") return prov[r]; return "pending" }
  if (k == "fails-when") return (efw[cr] != "") ? efw[cr] : "pending"
  if (k == "eval") return tier[cr] " — " ((eev[cr] != "") ? eev[cr] : "pending")
  if (k == "task") return taskof(cr)
  return "pending"
}
function wptr(l,   v) {  # a Step-5 line naming a real walk-artifact: value: not empty, not the stub token
  v = l; sub(/^.*walk-artifact[ \t]*:[ \t]*/, "", v); sub(/[ \t]*;.*$/, "", v); sub(/[ \t]+$/, "", v)
  if (v != "" && tolower(v) != "pending") haptr = 1
}
BEGIN {
  nk = split(ENVIRON["MR_KEYS"], kl, "\n")
  for (i = 1; i <= nk; i++) { split(kl[i], kv, "\t"); if (kv[1] != "") keys[kv[1]] = kv[2] }
  serves_load(ENVIRON["MR_TASKS"])
  walk = tolower(ENVIRON["MR_WALK"]); cf = ENVIRON["MR_COUNT"]
  readreq(ENVIRON["MR_REQFILE"])
}
{ raw[NR] = $0; ln = $0; sub(/\r$/, "", ln); L[NR] = ln }
END {
  for (i = 1; i <= NR; i++) {
    line = L[i]
    if (line ~ /^[ \t]*```/) { fence = !fence; continue }
    if (fence) continue
    # THE POINTER IN THE STEP-5 BLOCK (wave-36 T44; REQ-7 AC-7.1, D13): the walk gate reads walk-artifact: from the Step 5
    # block alone, so a plan whose block already names its record needs no matrix-level stub as the reminder of it.
    if (line ~ /^## /) { insd = (line ~ /^##[ \t]+SDLC State/); in5 = 0 }
    else if (insd) {
      if (line ~ /^[ \t]*-?[ \t]*Step[ \t]+5[ \t]*:/) { in5 = 1; if (line ~ /walk-artifact[ \t]*:/) wptr(line) }
      else if (in5 && line !~ /^[ \t]*$/) {
        if (line ~ /^[^ \t]/ || line ~ /^[ \t]*-?[ \t]*Step[ \t]+[0-9]+[ab]?[ \t]*:/) in5 = 0
        else if (line ~ /^[ \t]*walk-artifact[ \t]*:/) wptr(line)
      }
    }
    if (line ~ /^## /) {
      inm = 0; reqh = ""; evh = 0
      inev = (line ~ /^## Eval design[ \t]*$/); if (inev) sawev = 1
      if (line ~ /^## Verification Matrix/) { inm = 1; sawm = 1; mhead = i; mlast = i; cur = "" }
      continue
    }
    if (line ~ /^### /) {
      reqh = ""
      if (match(line, /^###[ \t]+REQ-[0-9A-Za-z.]+/)) { reqh = substr(line, RSTART, RLENGTH); sub(/^###[ \t]+/, "", reqh) }
      continue
    }
    if (reqh != "" && !inm && !inev && line ~ /^provenance[ \t]*:/ && !(reqh in prov)) {
      v = line; sub(/^provenance[ \t]*:[ \t]*/, "", v); prov[reqh] = trim(v)
    }
    if (reqh != "" && !inm && !inev) { v = acline(line); if (v != "" && !(v in pact) && ACT != "") pact[v] = ACT }
    if (inev && line ~ /^[ \t]*\|/) { eval_row(line); continue }
    if (!inm) continue
    if (line !~ /^[ \t]*$/) mlast = i
    if (line ~ /^[ \t]*\|/) {
      cur = ""
      if (line ~ /^[ \t]*\|[-|: \t]*$/) continue
      nc = cells(line, c)
      if (c[1] == "AC" || c[1] == "") continue
      mrows++; if (!(c[1] in tier)) tier[c[1]] = c[2]
      continue
    }
    if (line ~ /^[ \t]*stack-health[ \t]*:/ && !hassh) hassh = i
    if (line ~ /^[ \t]*walk-artifact[ \t]*:/ && !haswa) haswa = i
    if (line ~ /^[^ \t]/) {
      cur = ""; hdr = line; sub(/^[-*+][ \t]+/, "", hdr)
      if (match(hdr, /^AC-[^ \t:]+:/)) {
        cur = substr(hdr, 1, RLENGTH - 1)
        if (cur in bstart) cur = ""; else { bstart[cur] = i; bend[cur] = i }
      }
      continue
    }
    if (cur != "" && line ~ /^[ \t]+[^ \t]/) {
      bend[cur] = i; k = line; sub(/^[ \t]+/, "", k); sub(/[ \t]*:.*$/, "", k); has[cur, k] = 1
    }
  }
  if (!sawev || ne == 0) { printf "noeval\t\n" > cf; exit 3 }
  if (!sawm || mrows == 0) { printf "notable\t\n" > cf; exit 4 }
  miss = ""; badt = ""
  for (e = 1; e <= ne; e++) {
    cr = ec[e]
    if (!(cr in tier)) miss = miss ((miss == "") ? "" : ", ") cr
    else if (!(tier[cr] in keys) || keys[tier[cr]] == "") badt = badt ((badt == "") ? "" : ", ") cr " (" tier[cr] ")"
  }
  if (miss != "") { printf "norow\t%s\n", miss > cf; exit 5 }
  if (badt != "") { printf "badtier\t%s\n", badt > cf; exit 6 }
  written = 0; added = 0; same = 0; nb = ""
  heads = ""
  if (!hassh) { heads = heads "stack-health: pending\n"; added++ }
  if (walk != "exempt" && !haswa && !haptr) { heads = heads "walk-artifact: pending\n"; added++ }
  if (heads != "") { if (hassh) ins[hassh] = ins[hassh] heads; else ins[mhead] = ins[mhead] "\n" heads }
  for (e = 1; e <= ne; e++) {
    cr = ec[e]; owed = "provenance fails-when eval task evidence"
    nw = split(keys[tier[cr]], tk, " ")
    for (w = 1; w <= nw; w++) if (tk[w] != "evidence") owed = owed " " tk[w]
    no = split(owed, ok, " ")
    if (cr in bstart) {
      got = 0
      for (w = 1; w <= no; w++) if (!((cr, ok[w]) in has)) { ins[bend[cr]] = ins[bend[cr]] "  " ok[w] ": " val(cr, ok[w]) "\n"; added++; got++ }
      if (!got) same++
    } else {
      nb = nb cr ":" ((actext(cr) != "") ? " " actext(cr) : "") "\n"
      for (w = 1; w <= no; w++) nb = nb "  " ok[w] ": " val(cr, ok[w]) "\n"
      written++
    }
  }
  if (nb != "" && L[mlast] !~ /^[ \t]+[^ \t]/) nb = "\n" nb
  for (i = 1; i <= NR; i++) {
    print raw[i]
    if (i in ins) printf "%s", ins[i]
    if (i == mlast && nb != "") printf "%s", nb
  }
  printf "%d\t%d\t%d\n", written, added, same > cf
}'

# LE_AWK / landing_evidence — A LANDING WRITES ITS CRITERIA'S EVIDENCE (wave-31 T22; REQ-15 AC-15.1 to AC-15.3, D15,
# A-orch-51 ruling 3). `row-landed` is the one writer both landings call (`ready`'s publish and the hand landing), and
# it calls this once the status, the step line and the ledger line are in its copy. The copy gains, in each AC block of
# `## Verification Matrix` that the landed row SERVES (`serves_hit`, the relation matrix-render's `task:` reads; never
# the block's `task:` cell, which names split parents and is corrected by hand at Step 5), an `evidence:` cell reading
# the docs-root-relative path of the row's green log for the suite the block's `eval:` names (`<suite>.test.sh` in
# backticks). The rules, as the pass below keeps them:
#   · the log is the one the landing's own verdict names: the landing record's last `ev=verdict` line for this row,
#     this commit, this suite, `result=green` (LE_LOGS, built by landing_evidence);
#   · an eval naming a suite the landing did not run, or no suite (a T0 grep), writes nothing;
#   · the cell is written when it reads `pending` or is already a path under `record/<plan>/line/` (which only a
#     landing writes: the newer landing replaces it, AC-15.2); any other value is a hand fill and stays;
#   · a block with no `evidence:` line is left alone: the verb replaces a cell, it adds no key.
# ENVIRON: LE_TASKS (serves_tasks), LE_ROW, LE_LOGS (`<suite><TAB><docs-root-relative path>` per line), LE_SLUG (the
# plan's name), LE_COUNT (a side file: the number of cells written). Prints the plan; the fences, the section
# headings and the AC blocks are read as MR_AWK reads them.
LE_AWK='
function suite_of(ev,    t) {
  if (!match(ev, /`[^` \t]+\.test\.sh`/)) return ""
  t = substr(ev, RSTART + 1, RLENGTH - 2)
  return t
}
BEGIN {
  serves_load(ENVIRON["LE_TASKS"]); row = ENVIRON["LE_ROW"]; slug = ENVIRON["LE_SLUG"]; cf = ENVIRON["LE_COUNT"]
  nl = split(ENVIRON["LE_LOGS"], ll, "\n")
  for (i = 1; i <= nl; i++) { split(ll[i], lv, "\t"); if (lv[1] != "" && lv[2] != "") logs[lv[1]] = lv[2] }
  for (t = 1; t <= nt; t++) if (tid[t] == row) rt = t
}
{ raw[NR] = $0; ln = $0; sub(/\r$/, "", ln); L[NR] = ln }
END {
  for (i = 1; i <= NR; i++) {
    line = L[i]
    if (line ~ /^[ \t]*```/) { fence = !fence; continue }
    if (fence) continue
    if (line ~ /^## /) {
      inm = 0; evh = 0; cur = ""
      inev = (line ~ /^## Eval design[ \t]*$/)
      if (line ~ /^## Verification Matrix/) inm = 1
      continue
    }
    if (inev && line ~ /^[ \t]*\|/) { eval_row(line); continue }
    if (!inm || line ~ /^[ \t]*\|/) { if (inm) cur = ""; continue }
    if (line ~ /^[^ \t]/) {
      cur = ""; hdr = line; sub(/^[-*+][ \t]+/, "", hdr)
      if (match(hdr, /^AC-[^ \t:]+:/)) {
        cur = substr(hdr, 1, RLENGTH - 1)
        if (cur in seen) cur = ""; else { seen[cur] = 1; nb++; bord[nb] = cur }
      }
      continue
    }
    if (cur != "" && line ~ /^[ \t]+[^ \t]/) {
      k = line; sub(/^[ \t]+/, "", k); v = k; sub(/[ \t]*:.*$/, "", k); sub(/^[^:]*:[ \t]*/, "", v)
      if (k == "eval" && !(cur in beval)) beval[cur] = trim(v)
      if (k == "evidence" && !(cur in evl)) { evl[cur] = i; evv[cur] = trim(v) }
    }
  }
  written = 0
  for (b = 1; b <= nb && rt; b++) {
    cr = bord[b]
    if (!(cr in evl) || !serves_hit(rt, cr)) continue
    s = suite_of(beval[cr])
    if (s == "" || !(s in logs)) continue
    if (evv[cr] != "pending" && index(evv[cr], "record/" slug "/line/") != 1) continue
    if (evv[cr] == logs[s]) continue
    n = evl[cr]; ln = L[n]
    if (match(ln, /evidence[ \t]*:/)) { out[n] = substr(ln, 1, RSTART + RLENGTH - 1) " " logs[s]; written++ }
  }
  for (i = 1; i <= NR; i++) print ((i in out) ? out[i] : raw[i])
  printf "%d\n", written > cf
}'

# landing_evidence <plan in> <plan out> <row> <commit> <landing record> <docs root> <plan slug> -> prints the number of
# cells written; <plan out> holds the plan with them (and is left alone when none). rc 1 when the pass cannot run.
landing_evidence() {
  local in="$1" out="$2" row="$3" commit="$4" rec="$5" droot="$6" slug="$7" logs n side="$2.count"
  logs="$( [ -f "$rec" ] && awk -F'|' -v row="row=$row" -v c="commit=$commit" -v root="$droot/" '
    $2 == "ev=verdict" && $3 == row && $4 == c && $6 == "result=green" {
      s = $5; sub(/^suite=/, "", s); l = $7; sub(/^log=/, "", l)
      if (s != "" && index(l, root) == 1) last[s] = substr(l, length(root) + 1)
    }
    END { for (s in last) printf "%s\t%s\n", s, last[s] }' "$rec" 2>/dev/null )"
  if [ -z "$logs" ]; then printf '0'; return 0; fi
  LE_TASKS="$(serves_tasks "$in")" LE_ROW="$row" LE_LOGS="$logs" LE_SLUG="$slug" LE_COUNT="$side" \
    awk "$SERVES_AWK$LE_AWK" "$in" > "$out.le" 2>/dev/null || { rm -f "$out.le" "$side"; return 1; }
  n="$(cat "$side" 2>/dev/null)"; rm -f "$side"
  case "$n" in ''|*[!0-9]*) rm -f "$out.le"; return 1 ;; esac
  if [ "$n" -gt 0 ]; then mv -f "$out.le" "$out"; else rm -f "$out.le"; fi
  printf '%s' "$n"
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

# pv_roster_names_row <row id> -> 0 when a roster of this project holds a launch of the row for this plan, else 1: a
# `roster-state/` row carrying `row=<id>` whose `plan=` is this plan's, or that carries no `plan=` (the rows written
# before it existed). The one question a pending row's Files cell asks before it is the table's (wave-36 T41): a
# launch in flight has a contract, and amend is its verb. Reads the files itself, never through a quitting pipe.
pv_roster_names_row() {
  local rf pb
  pb="$(basename "$PV_PLAN")"
  for rf in "$PV_REPO"/.bionic/tmp/roster-*.state; do
    [ -f "$rf" ] && [ ! -L "$rf" ] || continue
    awk -F'|' -v id="$1" -v pb="$pb" '
      index($0, "roster-state/") == 1 {
        row = ""; plan = ""; has = 0
        for (i = 2; i <= NF; i++) {
          if (index($i, "row=") == 1) row = substr($i, 5)
          else if (index($i, "plan=") == 1) { plan = substr($i, 6); has = 1 }
        }
        n = split(plan, seg, "/"); base = seg[n]
        if (row == id && (!has || base == pb)) found = 1
      }
      END { exit found ? 0 : 1 }' "$rf" && return 0
  done
  return 1
}

# ---------------------------------------------------------------- a record row lands itself
#
# THE RECORD ROW'S OWN LANDING (wave-33 T6; REQ-3 AC-3.1, AC-3.2; D5). A test, verify or review row
# writes a record and no code, so it has no tree, no `ready` and no `published` event; wave-32 landed
# eight such rows by `row-landed --by-hand`. `deliver <row>` is its agent's last act, and the tick's
# backstop when the agent ended without it. It checks what the row owes, then lands it through the
# one landing writer, `row-landed`, in the same transaction, at the working head (the head of the
# checkout holding the plan's `working-branch:`), with the artifact written into the ledger line.
#
# THE ROW'S WRITER (wave-34 T4; burns debt row-writer-name): `ready`'s answer, lib/line.sh
# `line_row_writer`, loaded here the first time it is asked, so `deliver` and the tick's backstop hold a
# row to the writer `ready` would. Sets ROW_WRITER (empty when the row names no one); 1 when the library
# cannot be loaded.
row_writer() {  # <roster> <plan> <row> <agent cell>
  ROW_WRITER=""
  declare -F line_row_writer >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1
  declare -F line_row_writer >/dev/null 2>&1 || return 1
  line_row_writer "$@"
  ROW_WRITER="$LINE_WRITER"
  return 0
}

# deliver_check -> for the row $PV_ID of the opened plan ($PV_PLAN, $PV_REPO), sets RL_COMMIT, RL_AT
# and RL_ARTIFACT, or exits: 0 with nothing written when the row is already landed, 2 on a refusal,
# each naming what is missing and the call that answers it. In order:
#   - the row is in `## Tasks`, `pending` or `active`;
#   - it has no tree of its own and its Files write nothing the head carries (`units_writes_head`):
#     a row with a tree lands through `ready`, from that tree;
#   - it is not a live review row (`units_live_rows`): `proof-add` returns that row to `pending` at
#     each reading and the next landing makes it ready again, so landing it would end its passes;
#   - its artifact: the ledger line's `artifact` cell, else the one record under `<docs-root>/record/`
#     its Files name (a `.progress.md` and `assumptions.md` are bookkeeping, not the artifact). The
#     file exists, is no symbolic link, and lies under the docs root's `record/`;
#   - a review row: a `proved: kind=review` line under `## SDLC State` names that record;
#   - the working head reads as a commit;
#   - no ruling for the row's writer is unread.
deliver_check() {
  local row kind files wt status art docs drel abs real rel e n=0 cands="" hasl=0 lverb=ledger-set call wb head sid roster rulings
  call="bash $HOOK_DIR/session-poker.sh"
  if ! { declare -F proof_branch_head >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
     || ! declare -F proof_branch_head >/dev/null 2>&1; then
    die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
    exit 2
  fi
  row="$(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' -v id="$PV_ID" '$1 == id { print; exit }')"
  if [ -z "$row" ]; then
    die "REFUSED — the ## Tasks table of $PV_PLAN carries no row $PV_ID; the plan is unchanged."
    exit 2
  fi
  kind="$(units_field "$row" kind)"; files="$(units_field "$row" Files)"
  wt="$(units_field "$row" worktree)"; status="$(units_field "$row" status)"
  case "$status" in
    landed) say "deliver — $PV_ID is already landed; nothing was written."; exit 0 ;;
    pending|active) : ;;
    *) die "REFUSED — $PV_ID reads $(clean "$status"), and only a pending or active row lands; the plan is unchanged."; exit 2 ;;
  esac
  case "$wt" in
    *[A-Za-z0-9]*)
      die "REFUSED — $PV_ID has a tree of its own ($(clean "$wt")), and a row with a tree lands through ready, from that tree: bash <plugin-root>/scripts/spawn-worktree.sh ready. The plan is unchanged."
      exit 2 ;;
  esac
  if units_writes_head "$files"; then
    die "REFUSED — the Files of $PV_ID ($(clean "$files")) write the head, and a row that writes the head lands through ready from its tree: bash <plugin-root>/scripts/spawn-worktree.sh ready. The plan is unchanged."
    exit 2
  fi
  if [ -n "$(units_live_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' -v id="$PV_ID" '$1 == id')" ]; then
    die "REFUSED — $PV_ID is a live review row (it reads live:head): proof-add returns it to pending at each reading and the next landing makes it ready again, so deliver does not land it. The plan is unchanged."
    exit 2
  fi
  docs="$(docs_root "$PV_REPO")"; docs="$(cd "$docs" 2>/dev/null && pwd -P)"
  drel=""; case "$docs" in "$PV_REPO"/*) drel="${docs#"$PV_REPO"/}" ;; esac
  launch_sync_ledger "$PV_PLAN" >/dev/null && hasl=1
  art="$(awk -F'|' -v id="$PV_ID" '
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^##[ \t]/ { inl = ($0 ~ /^##[ \t]+Dispatch ledger[ \t]*$/); rows = 0; next }
    !inl || $0 !~ /^[ \t]*\|/ { next }
    { rows++ }
    rows == 1 { ac = 0; for (k = 2; k < NF; k++) { h = $k; gsub(/^[ \t]+|[ \t]+$/, "", h); if (h == "artifact") ac = k }; next }
    $0 ~ /^[ \t]*\|[ \t:|-]*$/ { next }
    { c = $2; gsub(/^[ \t]+|[ \t]+$/, "", c); if (c == id && ac) { v = $ac; gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit } }' "$PV_PLAN" 2>/dev/null)"
  case "$art" in *[A-Za-z0-9]*) : ;; *) art="" ;; esac
  if [ -z "$art" ]; then
    while IFS= read -r e; do
      e="${e#"${e%%[![:space:]]*}"}"; e="${e%"${e##*[![:space:]]}"}"; e="${e#!}"; e="${e#./}"
      case "$e" in *[A-Za-z0-9]*) : ;; *) continue ;; esac
      case "$e" in *.progress.md|assumptions.md|*/assumptions.md) continue ;; esac
      case "$e" in record/*) : ;; "${drel:-/}"/record/*) : ;; *) continue ;; esac
      n=$((n + 1)); cands="${cands:+$cands, }$e"; art="$e"
    done <<DELIVER_FILES
$(printf '%s\n' "$files" | tr ',' '\n')
DELIVER_FILES
    [ "$hasl" = 1 ] && launch_sync_ledger "$PV_PLAN" | awk -F'\037' -v id="$PV_ID" '$1 == id { f = 1 } END { exit !f }' || lverb=ledger-add
    if [ "$n" -eq 0 ]; then
      die "REFUSED — $PV_ID names no artifact: its ledger line has no artifact cell and its Files name no record under record/; name it: $call $lverb $PV_ID artifact=<path>, then $call deliver $PV_ID. The plan is unchanged."
      exit 2
    fi
    if [ "$n" -gt 1 ]; then
      die "REFUSED — $PV_ID names no artifact in its ledger line and its Files name $n records ($(clean "$cands")); name the one it delivers: $call $lverb $PV_ID artifact=<path>, then $call deliver $PV_ID. The plan is unchanged."
      exit 2
    fi
  fi
  case "$art" in
    *[[:space:]]*|*'|'*)
      die "REFUSED — the artifact $(clean "$art") of $PV_ID carries a blank or a |, which no plan cell can hold; the plan is unchanged."
      exit 2 ;;
  esac
  # A path is read as the plan spells it: absolute, from the docs root (`record/…`, as proof lines and
  # older ledgers write it), or from the repository (`.bionic/docs/record/…`, as Files cells do).
  case "$art" in
    /*) abs="$art" ;;
    record/*) abs="$docs/$art" ;;
    *) abs="$PV_REPO/$art" ;;
  esac
  if [ -L "$abs" ]; then
    die "REFUSED — the artifact $(clean "$art") of $PV_ID is a symbolic link, and what it points at can change after the landing; copy the record to that path, then $call deliver $PV_ID. The plan is unchanged."
    exit 2
  fi
  if [ ! -f "$abs" ]; then
    die "REFUSED — the artifact of $PV_ID, $(clean "$art"), does not exist (read as $(clean "$abs")); write it, then run $call deliver $PV_ID. The plan is unchanged."
    exit 2
  fi
  real="$(cd "$(dirname "$abs")" 2>/dev/null && pwd -P)/$(basename "$abs")"
  case "$real" in
    "$docs"/record/*) rel="${real#"$docs"/}" ;;
    *)
      die "REFUSED — the artifact $(clean "$art") of $PV_ID is not under record/ of the docs root ($docs/record/), and a record row delivers a record; the plan is unchanged."
      exit 2 ;;
  esac
  if [ "$kind" = review ]; then
    if [ -z "$(awk -v rec="$rel" "$(proof_awk)"'
        /^[[:space:]]*```/ { fence = !fence; next }
        fence { next }
        /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
        insdlc && proof_fields($0) && PROOF_KIND == "review" && PROOF_EVIDENCE == rec { print "y"; exit }' "$PV_PLAN" 2>/dev/null)" ]; then
      die "REFUSED — $PV_ID is a review row and no proved: kind=review line names its record $rel; register the reading first: $call proof-add review $rel --question <q> --reader <name>, then $call deliver $PV_ID. The plan is unchanged."
      exit 2
    fi
  fi
  # THE HEAD IS THE WORKING BRANCH'S REF (wave-36 T12; D13, AC-7.4; C30): lib/proof.sh `proof_branch_head`, the
  # judge's one reading of the head, so a merged branch whose worktree is gone still lands its record rows.
  wb="$(plan_working_branch "$PV_PLAN")"
  head="$(proof_branch_head "$PV_PLAN" "$PV_REPO")" || head=""
  case "$head" in
    [0-9a-f]*) [ "${#head}" -eq 40 ] || head="" ;;
    *) head="" ;;
  esac
  if [ -z "$head" ]; then
    die "REFUSED — the plan's working-branch ${wb:-(none named)} names no commit in $PV_REPO, so there is no head to land $PV_ID at; name the branch under ## SDLC State (working-branch: <branch>), then $call deliver $PV_ID. The plan is unchanged."
    exit 2
  fi
  # AN UNREAD RULING HOLDS THE LANDING (wave-33 T34; Δ1, ADR-052), as at the commit wall and `ready`: a
  # record row's artifact is gitignored and never commits, so deliver is its only landing. The writer
  # is `ready`'s (`row_writer`). Each ruling of it not yet shown is printed and stamped shown
  # (lib/roster.sh `ruling_take_unread`), so the same call after this one lands: this is the writer's
  # own deliver. The tick's backstop never reaches this read with a ruling unread (it refuses first,
  # without stamping, wave-34 T4).
  sid="$(session_id)" || sid=""
  roster="$PV_REPO/.bionic/tmp/roster-${sid}.state"
  if ! row_writer "$roster" "$PV_PLAN" "$PV_ID" "$(units_field "$row" agent)"; then
    die "REFUSED — the row's writer cannot be read: lib/line.sh cannot be loaded from $BIONIC_LIB; the plan is unchanged."
    exit 2
  fi
  if [ -n "$sid" ] && declare -F ruling_take_unread >/dev/null 2>&1 \
     && rulings="$(ruling_take_unread "$roster" "$ROW_WRITER" deliver)" && [ -n "$rulings" ]; then
    die "REFUSED — an orchestrator ruling for $(clean "$ROW_WRITER") is unread ($(printf '%s\n' "$rulings" | sed -n 's/^bionic ruling \([^ ]*\) .*/\1/p' | paste -sd, - | sed 's/,/, /g')); read it below, act on it, then $call deliver $PV_ID. The plan is unchanged."
    printf '%s\n' "$rulings" >&2
    exit 2
  fi
  RL_COMMIT="$head"; RL_AT="$(iso_now)"; RL_ARTIFACT="$art"
}

# ---------------------------------------------------------------- the deferral's sentence
#
# A DEFERRED FINDING'S ONE CHANGELOG SENTENCE (wave-28 T17; D21, AC-8.7). Registering a record writes
# `deferred: <record>#<n> <S> <reach> "<title>"` (lib/proof.sh `proof_finding_lines`); `finding-stated`
# appends ` stated="<sentence>"` to it, the last field of the line. The sentence is folded to one line
# of single spaces (`deferral_fold`, lib/said.sh's `said_fold`, the one fold the changelog is read through as well), and a `\` or a `"` in it is written `\\` or `\"`, so the
# quoted field ends where the line does and a title, which never holds a `"`, is still the line's
# first quoted string (`proof_findings_owed` reads it so). The other half of the debt is the changelog:
# `release-check` prints each deferral stated (the sentence is in `CHANGELOG.md`) or unstated.
deferral_fold() {  # <text> -> its white space and control characters folded to single spaces, trimmed: lib/said.sh's one fold
  declare -F said_fold >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/said.sh" ] && . "$BIONIC_LIB/said.sh"; }
  said_fold "$1"
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
# finding_owed_key <record>#<n> -> the person's-ledger key of the finding's ruling (lib/owed.sh), `finding:` and
# the identity with each character a key may not hold (lib/owed.sh `_owed_key_ok`: letters, digits and `:._-`)
# written `:` (wave-33 T13; D6, D2): `record/w/st.md#2` is `finding:record:w:st.md:2`.
finding_owed_key() {
  printf 'finding:%s' "$(printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9._-' ':')"
}
# waive_owed_findings <plan> <repo> <question> -> always 0, prints nothing: the waiver of a question is the person's
# answer to every finding of its readings ("fix it, defer it, or waive <question>", `disposition`), so it closes each
# open `finding:<record>#<n>` item of every reading the plan registers under that question (wave-34 T5; REQ-4 AC-4.2,
# D14). The readings are `disposition`'s own: `proved: kind=review` lines under ## SDLC State naming the question.
waive_owed_findings() {
  local ev pre key
  declare -F owed_list >/dev/null 2>&1 && declare -F proof_awk >/dev/null 2>&1 || return 0
  while IFS= read -r ev; do
    [ -n "$ev" ] || continue
    pre="$(finding_owed_key "$ev#")"
    for key in $(OWED_ROOT="$2" owed_list 2>/dev/null | cut -f1); do
      case "${key#"$pre"}" in "$key"|''|*[!0-9]*) continue ;; esac
      poker_owed_close "$2" "$key" "waive"
    done
  done <<< "$(awk -v q="$3" "$(proof_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION == q && PROOF_EVIDENCE != "" { print PROOF_EVIDENCE }' "$1" | sort -u)"
  return 0
}

# finding_read <plan> <repo> <record>#<n> -> 0 with the finding in FR_S, FR_R (the reader's rating), FR_P (the
# priority the plan's moves give it, lib/proof.sh `proof_finding_rating`), FR_W (its <path>:<line> or -), FR_T
# (its title) and FR_Q, FR_H (the question and head of the plan's registered reading of the record: its last
# `proved: kind=review` line naming the record as evidence); 1 with FR_WHY, one clause naming what is missing
# and the call that supplies it (wave-33 T13; REQ-5, D6). The readers: `task-add --born` and `disposition`.
finding_read() {
  local plan="$1" repo="$2" id="$3" rec n got
  FR_S=""; FR_R=""; FR_P=""; FR_W=""; FR_T=""; FR_Q=""; FR_H=""; FR_WHY=""
  if ! { declare -F proof_findings >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
     || ! declare -F proof_finding_rating >/dev/null 2>&1; then
    FR_WHY="the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB"; return 1
  fi
  rec="${id%#*}"; n="${id##*#}"
  got="$(awk -v ev="$rec" "$(proof_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION != "" && PROOF_EVIDENCE == ev { q = PROOF_QUESTION; h = PROOF_HEAD }
    END { if (q != "") print q "\t" h }' "$plan")"
  if [ -z "$got" ]; then
    FR_WHY="$(clean "$rec") is no reading registered under ## SDLC State (no proved: kind=review line names it as its evidence); register it first: proof-add review $(clean "$rec") --question <question> --reader <name>"
    return 1
  fi
  FR_Q="${got%%	*}"; FR_H="${got#*	}"
  got="$(proof_findings "$(docs_root "$repo")/$rec" 2>/dev/null)" || got=""
  if ! printf '%s\n' "$got" | awk -F'\t' -v n="$n" '$1 == n { f = 1 } END { exit !f }'; then
    FR_WHY="the reading $(clean "$rec") holds no finding $n (it holds $(printf '%s\n' "$got" | awk -F'\t' '$1 ~ /^[0-9]+$/ { printf "%s%s", (k++ ? ", " : ""), $1 } END { if (!k) printf "none" }'))"
    return 1
  fi
  IFS='	' read -r _ FR_S FR_R FR_W _ _ FR_T <<FINDING_READ
$(printf '%s\n' "$got" | awk -F'\t' -v n="$n" '$1 == n { print; exit }')
FINDING_READ
  set -- $(proof_finding_rating "$plan" "$id" "$FR_S" "$FR_R")
  FR_P="${3:-}"
  return 0
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
  # THE LEDGER'S ARRAYS ARE SET BEFORE ANY ROW IS READ (wave-35 T29). They are assigned only per existing
  # ledger row, and a header-only `## Dispatch ledger` has none: `${#LGAG[@]}` in launch_sync_ledgered and
  # `${#LGID[@]}` in the id search then read a declared-but-unset array, which bash 5.x under `set -u`
  # aborts ("LGAG: unbound variable"), the first dispatch of every fresh plan. `=()` makes them empty.
  LGID=(); LGAG=(); LGDT=()
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
#   landings: queue=<n> hand=<n> git=<n> · ready-to-landed median=<m>m p75=<m>m max=<m>m · runs: green=<n> red=<n> none=<n> discarded=<n> red-then-green=<n> run=<n> · waited median=<s>s · killed=<n>
#
# and with rows, one line per landed row in the record's order:
#
#   <row> <kind> ready=<ISO|-> landed=<ISO> minutes=<m|-> runs=<n> waited=<s>s wait=<m|-> prove=<m|-> line=<m|-> width=<J|->
#
# THE SPLIT (wave-37 T9; AC-1.3, AC-3.2). The last four fields are read from the landing record alone, never from the
# gate's requests, which are pruned after BIONIC_GATE_KEEP: wait is the row's first `ready` to its first `candidate`,
# prove is that first `candidate` to the row's last `verdict`, line is that last `verdict` to the `published` event, all
# since the row last landed and in minutes (%.1f). width is the `width=` on the row's verdict lines (lib/line.sh's drain
# writes it after `log=`; the last one numeric), `-` for a row whose verdicts carry none (written before 1.20.0, or by the
# serial line): absent, never 0. A segment missing either end prints `-`. A hand or a git landing prints all four `-`.
#
# NOTHING READS THESE NUMBERS TO DECIDE (D18). The tick prints the first line outside its digest, so a
# landing moves no decision; no hook or wall library names the report (tests/docs-pins.test.sh §W28-46).
#
# THE DEFINITIONS (the plan's T14). Ready-to-landed is a queue landing's `published` time less its row's
# FIRST `ready` since the row last landed; a hand or a git landing prints `-` and joins no figure. Median
# and p75 are linear interpolation over the sorted minutes, wave-27's baseline rule: an even set's median
# is the mean of its middle two, a set of one is that value; an empty set prints 0. Runs count `verdict`
# events by result, a ROW'S runs only, by INCLUSION (wave-28 T68): a verdict is the row's only at one of the
# row's own commits since its last landing (a `ready` commit= or a `candidate` commit=). The accepted head's
# own run, which `_line_red_owner` records under the row id at the head's commit, is at none of them and is
# counted nowhere; a row that landed before starts its own set again at its next `ready`, and a row with no
# candidate since its last landing has no commit of its own to include by, so every verdict under its id counts
# (T14's count). Red-then-green is a red then a green for one row,
# one commit and one suite with no `ready` for that row between (an unchanged tree), counted once per such pair. Run
# counts the record's `ev=run` lines, one per regression run floor-run or a detached booked.sh run recorded (wave-37
# T4; D7, AC-6.2). Waited is a request's `admitted` less its
# `asked`; killed is a request admitted that ended with an exit over 128 (a signal: 137 from the reaper, 143
# from a TERMed suite) or whose holder is dead with no `ended` line, as D18 says (lib/gate.sh `_gate_open`'s
# state, read through `_gate_read`, not retyped here; wave-28 T68, T72).
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
  local rec="$1" root="$2" rows="$3" gd f dead reqs="" out mal
  gd="${BIONIC_GATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/gate}"
  for f in "$gd"/requests/*; do
    case "${f##*/}" in ''|*[!0-9]*) continue ;; esac
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    # lib/gate.sh's reader and its one rule (`_gate_open`, T71), lock-free: a request is killed when it ended with
    # an exit over 128 (D18: the reaper writes 137, a TERMed suite's 143 reaches `gate_end`) or was admitted,
    # never ended and has no live holder. No gate library, no requests.
    _gate_read "$f" 2>/dev/null || continue
    _R_state=''; _gate_open 2>/dev/null
    dead=0
    case "$_R_state" in
      killed|dying) dead=1 ;;
      ended) case "${_R_rc:-}" in ''|*[!0-9]*) ;; *) [ "$_R_rc" -le 128 ] || dead=1 ;; esac ;;
    esac
    reqs="${reqs}${_R_asked}	${_R_admitted}	${_R_who#*:}	${_R_tree}	${dead}
"
  done
  if landing_unmeasured "$rec"; then printf 'landings: unmeasured — the landing record holds no line/v1 events\n'; return 0; fi
  [ -f "$rec" ] && [ ! -L "$rec" ] || rec=/dev/null
  out="$(printf '%s' "$reqs" | awk -v root="$root" -v rows="$rows" "$_PATROL_ISO_AWK"'
    function num(s) { return s ~ /^[0-9]+$/ }
    function seg(a, b) { return (a == "" || b == "" || b < a) ? "-" : sprintf("%.1f", (b - a) / 60) }
    function sortn(a, n,   i, j, t) { for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t } }
    function pct(a, n, p,   pos, lo, fr) {
      if (n == 0) return 0
      sortn(a, n); pos = p * (n - 1); lo = int(pos); fr = pos - lo
      return (lo + 1 < n) ? a[lo + 1] + (a[lo + 2] - a[lo + 1]) * fr : a[lo + 1]
    }
    phase == 0 { split($0, q, "\t"); nq++
      qa[nq] = q[1]; qd[nq] = q[2]; qw[nq] = q[3]; qt[nq] = q[4]; qx[nq] = q[5]; next }
    index($0, "line/v1|") != 1 { next }
    {
      split("", kv); nf = split($0, p, "|")
      for (i = 2; i <= nf; i++) { j = index(p[i], "="); if (j > 1) kv[substr(p[i], 1, j - 1)] = substr(p[i], j + 1) }
      ev = kv["ev"]; rk = kv["row"]; e = iso2epoch(kv["at"])
      g = rk SUBSEP (gen[rk] + 0)
      if (ev == "run") nrl++
      if ((ev == "candidate" || ev == "ready") && kv["commit"] != "") ownc[g SUBSEP kv["commit"]] = 1
      if (ev == "candidate") hasc[g] = 1
      if (ev == "candidate" && e >= 0 && !(rk in fc)) fc[rk] = e
      if (ev != "ready" && ev != "verdict" && ev != "published") { if (e >= 0 && t0 == "") t0 = e; next }
      if (rk == "" || e < 0) { mal++; next }
      if (ev == "verdict" && (kv["suite"] == "" || kv["result"] !~ /^(green|red|none|discarded)$/)) { mal++; next }
      if (ev == "published" && kv["kind"] !~ /^(queue|hand|git)$/) { mal++; next }
      if (t0 == "") t0 = e
      iso[e] = kv["at"]
      if (ev == "verdict") { lv[rk] = e; if (kv["width"] ~ /^[0-9]+$/) wd[rk] = kv["width"] }
    }
    ev == "ready" {
      if (!(rk in rdy)) rdy[rk] = e
      span[rk]++; nm[rk] = (kv["name"] == "" ? "-" : kv["name"]); next
    }
    ev == "verdict" {
      if ((g in hasc) && !((g SUBSEP kv["commit"]) in ownc)) next
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
      # THE SPLIT, from this record alone (wave-37 T9; AC-1.3, AC-3.2): each segment needs both its ends, else `-`.
      pw[n] = pp[n] = pl[n] = pwd[n] = "-"
      if (k == "queue") {
        fcn = ((rk in fc) ? fc[rk] : ""); lvn = ((rk in lv) ? lv[rk] : "")
        pw[n] = seg(pfrom[n], fcn); pp[n] = seg(fcn, lvn); pl[n] = seg(lvn, e)
        if (rk in wd) pwd[n] = wd[rk]
      }
      delete rdy[rk]; nrun[rk] = 0; delete nm[rk]; delete fc[rk]; delete lv[rk]; delete wd[rk]
      gen[rk]++
    }
    END {
      for (i = 1; i <= nq; i++) {
        inq[i] = (t0 != "" && num(qa[i]) && qa[i] >= t0 && (qt[i] == root || index(qt[i], root "/") == 1))
        if (!inq[i]) continue
        if (num(qd[i])) wts[++nw] = qd[i] - qa[i]
        if (num(qd[i]) && qx[i] == 1) killed++
      }
      wm = pct(wts, nw, 0.5)
      printf "landings: queue=%d hand=%d git=%d · ready-to-landed median=%.1fm p75=%.1fm max=%.1fm · runs: green=%d red=%d none=%d discarded=%d red-then-green=%d run=%d · waited median=%ds · killed=%d\n",
        kinds["queue"], kinds["hand"], kinds["git"], pct(mins, nm2, 0.5), pct(mins, nm2, 0.75), pct(mins, nm2, 1),
        cnt["green"], cnt["red"], cnt["none"], cnt["discarded"], rtg, nrl, int(wm + 0.5), killed
      if (rows == "yes") for (r = 1; r <= n; r++) {
        w = 0
        if (pname[r] != "-" && pfrom[r] != "") for (i = 1; i <= nq; i++)
          if (inq[i] && num(qd[i]) && qw[i] == pname[r] && qa[i] >= pfrom[r] && qa[i] <= pe[r]) w += qd[i] - qa[i]
        rd = "-"; mn = "-"
        if (r in pmin) { rd = iso[pfrom[r]]; mn = sprintf("%.1f", pmin[r]) }
        pre1 = sprintf("%s %s ready=%s landed=%s minutes=%s runs=%d", prow[r], pk[r], rd, pat[r], mn, pruns[r])
        wt = sprintf(" waited=%ds", w)
        tl = sprintf(" wait=%s prove=%s line=%s width=%s", pw[r], pp[r], pl[r], pwd[r])
        print pre1 wt tl
      }
      if (mal) printf "#malformed %d\n", mal
    }' phase=0 - phase=1 "$rec")"
  mal="$(printf '%s\n' "$out" | sed -n 's/^#malformed //p')"
  printf '%s\n' "$out" | /usr/bin/grep -v '^#malformed '
  [ -z "$mal" ] || die "landing-report — $mal malformed line/v1 line(s) skipped in $1"
  return 0
}


# ---------------------------------------------------------------- the run's hand-holds
#
# THE HAND-HOLD COUNT IS FOLDED FROM THE LINES THE ESCAPE-HATCH VERBS WROTE (wave-35 T12; D17, REQ-8
# AC-8.1). `landing-report --hand-holds` prints, under the landings line,
#
#   hand-holds: total=<n> · by-hand=<n> · stop-runs=<n> · declines=<n> · lifts=<n> · amends=<n> · holds=<n> · extensions=<n> · waivers=<n> · regression-2=<n> · second-floors=<n> · adoptions=<n> · fixed=<n>
#
# A hand-hold is a use of a verb that steps round the machine. Each kind is counted from the one line its
# verb wrote, and PROSE IS NEVER READ (D1): a line that says `by-hand` in a plan, a note or the orchestrator's
# own assumptions counts nothing, and so does anything the orchestrator did that no verb recorded.
#
#   by-hand        the landing record's `line/v1|ev=published|…|kind=hand|…` (lib/line.sh), one per landing.
#   stop-runs      the landing record's `line/v1|ev=stop-run|…`, one per `stop-run` that stopped a run or ended a
#                  gate request (wave-36 T11; D8, AC-2.3). A stop is a verb act: never counted as by-hand.
#   declines       the run's fill ledger's `fill-ledger/v1|…|state=decline|…` lines, one per `decline`. The Stop hook
#   lifts          writes `state=ok` and `state=hold` only, so a `hold` there is the fill's wait and not the `hold` verb.
#                  `state=lift` is `decline lift`'s line.
#   amends         the roster's `amended=<iso> <reason>` (`amend`), `held=` (`hold`) and `extended=` (`extend`).
#   holds          A roster row is re-written on every status change and copies the field, so a kind is counted by
#   extensions     DISTINCT (name, value) over the rosters whose `plan=` is this run's plan (a row of another run, or of
#                  `plan=none`, is not this run's). The roster lives in `.bionic/tmp`, which close-out's act 3 wipes,
#                  so close-out reads this line BEFORE the wipe and carries it.
#   waivers        the plan's `waived: question=…` line under `## SDLC State` (`waive`) and an AC block's indented
#                  `waiver: <who> <YYYY-MM-DD> "<words>"` under `## Verification Matrix` (`waive-row`). Fenced text is
#                  skipped, as every reader of the plan skips it.
#   regression-2   the plan's `approved: regression-2` line under `## SDLC State` (`approve`).
#   second-floors  `proved: kind=floor` lines under `## SDLC State` past the first (`proof-add floor`), read through
#                  lib/proof.sh's `proof_fields`, the one reading of a proof line.
#   adoptions      the roster row `adopt` files for each agent it adopts (`adopt_write_row`: `source=adopted`,
#                  `adopted_from=<sid>`), DISTINCT (agent_id, adopted_from) over the run's rosters, as the amends are
#                  (wave-36 T14; D13, AC-7.6). Its printed `poker-adopt/v1|…` report is kept in no file, so the row is
#                  the line the verb wrote. A verb act: never counted as by-hand.
#   fixed          the plan's `moved: <record>#<n> to=fixed row=<T> …` line under `## SDLC State` (`finding-move …
#                  fixed`, wave-36 T8), one per line (wave-36 T14; AC-7.6). A verb act: never counted as by-hand.
#
# READ-ONLY and FAIL-SOFT: an absent source counts zero. It decides nothing; nothing reads it but close-out's card and
# continuation (and a person).
hand_holds_report() {  # <landing record> <project root> <plan> -> the one hand-holds line; rc 0
  local rec="$1" root="$2" plan="$3" slug led rf hand=0 stp=0 dec=0 lif=0 amd=0 hld=0 ext=0 wv=0 r2=0 fl=0 ado=0 fix=0 pl
  slug="$(proof_plan_slug "$plan")"
  if [ -f "$rec" ] && [ ! -L "$rec" ]; then
    read -r hand stp <<< "$(awk -F'|' '
      index($0, "line/v1|") == 1 {
        ev = ""; k = ""
        for (i = 2; i <= NF; i++) { if (index($i, "ev=") == 1) ev = substr($i, 4); else if (index($i, "kind=") == 1) k = substr($i, 6) }
        if (ev == "published" && k == "hand") n++
        else if (ev == "stop-run") s++
      }
      END { print n + 0, s + 0 }' "$rec")"
  fi
  led="$(fill_ledger_path "$root" "$plan" 2>/dev/null)" || led=""
  if [ -n "$led" ] && [ -f "$led" ] && [ ! -L "$led" ]; then
    read -r dec lif <<< "$(awk -F'|' '
      index($0, "fill-ledger/v1|") == 1 {
        for (i = 2; i <= NF; i++) if (index($i, "state=") == 1) { s = substr($i, 7); if (s == "decline") d++; else if (s == "lift") l++ }
      }
      END { print d + 0, l + 0 }' "$led")"
  fi
  read -r amd hld ext ado <<< "$(for rf in "$root/.bionic/tmp"/roster-*.state; do
      [ -f "$rf" ] && [ ! -L "$rf" ] && cat "$rf"
    done 2>/dev/null | awk -F'|' -v want="/$slug.plan.md" '
      index($0, "roster-state/") == 1 {
        name = ""; plan = ""; a = ""; h = ""; x = ""; id = ""; src = ""; af = ""
        for (i = 2; i <= NF; i++) {
          if (index($i, "name=") == 1) name = substr($i, 6)
          else if (index($i, "agent_id=") == 1) id = substr($i, 10)
          else if (index($i, "source=") == 1) src = substr($i, 8)
          else if (index($i, "adopted_from=") == 1) af = substr($i, 14)
          else if (index($i, "plan=") == 1) plan = substr($i, 6)
          else if (index($i, "amended=") == 1) a = substr($i, 9)
          else if (index($i, "held=") == 1) h = substr($i, 6)
          else if (index($i, "extended=") == 1) x = substr($i, 10)
        }
        if (length(plan) < length(want) || substr(plan, length(plan) - length(want) + 1) != want) next
        if (a != "") A[name SUBSEP a] = 1
        if (h != "") H[name SUBSEP h] = 1
        if (x != "") X[name SUBSEP x] = 1
        if (src == "adopted" && af != "" && id != "") D[id SUBSEP af] = 1
      }
      END { for (k in A) na++; for (k in H) nh++; for (k in X) nx++; for (k in D) nd++; print na + 0, nh + 0, nx + 0, nd + 0 }')"
  if [ -f "$plan" ] && [ ! -L "$plan" ]; then
    if ! declare -F proof_awk >/dev/null 2>&1 && [ -f "$BIONIC_LIB/proof.sh" ]; then . "$BIONIC_LIB/proof.sh"; fi
    if declare -F proof_awk >/dev/null 2>&1; then
      read -r fl wv r2 fix <<< "$(awk "$(proof_awk)"'
        /^[ \t]*```/ { fence = !fence; next }
        fence { next }
        /^##[ \t]/ { sec = ($0 ~ /^##[ \t]+SDLC State/) ? "sdlc" : (($0 ~ /^##[ \t]+Verification Matrix/) ? "mx" : ""); inb = 0; next }
        sec == "sdlc" {
          if (proof_fields($0) && PROOF_KIND == "floor") f++
          else if ($0 ~ /^waived:[ \t]+question=/) w++
          else if ($0 ~ /^approved:[ \t]+regression-2([ \t]|$)/) r++
          else if ($0 ~ /^moved:[ \t]+[^ \t]+[ \t]+to=fixed([ \t]|$)/) x++
          next
        }
        sec == "mx" {
          if ($0 ~ /^AC-[^ \t]*:[ \t]*$/) { inb = 1; next }
          if (inb && $0 ~ /^[ \t]+[^ \t]/) {
            if ($0 ~ /^[ \t]+waiver:[ \t]+[^"]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ \t]+"/) w++
            next
          }
          inb = 0
        }
        END { print f + 0, w + 0, r + 0, x + 0 }' "$plan")"
    fi
  fi
  [ "${fl:-0}" -gt 1 ] && fl=$((fl - 1)) || fl=0
  printf 'hand-holds: total=%d · by-hand=%d · stop-runs=%d · declines=%d · lifts=%d · amends=%d · holds=%d · extensions=%d · waivers=%d · regression-2=%d · second-floors=%d · adoptions=%d · fixed=%d\n' \
    $(( hand + stp + dec + lif + amd + hld + ext + wv + r2 + fl + ado + fix )) "$hand" "$stp" "$dec" "$lif" "$amd" "$hld" "$ext" "$wv" "$r2" "$fl" "$ado" "$fix"
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
  # `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/share`; with no file the gate's share is 92. Printing it asks
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
    FR_SLUG="$(proof_plan_slug "$FR_PLAN")"
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

    # THE EVIDENCE, READ ONCE (wave-34 T6; REQ-14 AC-14.1/14.3, D23). Liveness used to be an mtime and
    # LANDED the deliverable's presence, so a SIGKILLed probe read LANDED and a just-killed one RUNNING
    # (field report 2026-10-11, item 1). Three inputs replace them: this session's newest ListAgents answer
    # (lib/agents.sh, less every agent a TaskStop after it ended) — an agent it lists is reachable by name;
    # the kept transcript reads (`adopt_read_baseline`) — growth across a cadence; and the sweeper's
    # completion signal — an agent's report, the only thing LANDED is read from. Acks are read from every
    # ledger in the root (`adopt_cross_acks`).
    ADOPT_SWEEPER="$HOOK_DIR/session-sweeper.sh"
    ADOPT_PANEL_RC=4; ADOPT_PANEL=""
    ADOPT_TR="$(session_transcript "$SESSION_ID")" || ADOPT_TR=""
    if [ -n "$ADOPT_TR" ]; then
      _la_ensure "$ADOPT_TR" 2>/dev/null; ADOPT_PANEL_RC=$?
      if [ "$ADOPT_PANEL_RC" -eq 0 ]; then
        ADOPT_PANEL="$(printf '%s\n' "$_LA_CACHE_OUT" | ADOPT_GONE="$(live_agents_since_answer "$ADOPT_TR" 2>/dev/null \
          | awk -F'\t' '$1 == "stopped" { print $2 }')" awk -F'|' '
            BEGIN { n = split(ENVIRON["ADOPT_GONE"], g, "\n"); for (i = 1; i <= n; i++) if (g[i] != "") gone[g[i]] = 1 }
            $1 != "" && !($1 in gone) { print $1 "|" $3 }')"
      fi
    fi
    ADOPT_READS_FILE="$ADOPT_DIR/adopt-reads.state"
    ADOPT_READS_OLD=""
    [ -f "$ADOPT_READS_FILE" ] && [ ! -L "$ADOPT_READS_FILE" ] && ADOPT_READS_OLD="$(cat "$ADOPT_READS_FILE" 2>/dev/null)"
    ADOPT_READS_NEW=""
    # THE ONE CLOSURE RULE (wave-36 T10; AC-4.4, D10): lib/fill.sh `roster_row_open`, which the dispatch
    # wall's hold asks too, handed the inputs this run already resolved. It reads every ledger's acks.
    roster_closure_begin "$ADOPT_DIR" "$ADOPT_LIVE_IDS" "$ADOPT_WINDOW" "$ADOPT_NOW"
    adopt_handoff_note "$ADOPT_OWN_PLAN" "$REPO_REAL" "$ADOPT_DIR"
    # THE ACTIVE READERS (wave-36 T29; REQ-4 AC-4.1; D10). A reader (auditor, critic) is swept MET when
    # its record lands and is acked on its own session's ledger, while its plan row stays `active` until
    # the orchestrator registers the reading. A `/clear` in between left it closed here, so it came out
    # on no roster and the launch arm refused its row (wave-35 A-orch-46). So a read-only role's row
    # (`role_is_readonly`) whose name is the agent cell of an `active` row of this session's bound plan
    # is carried as an open writer row is, its own ledger's ack notwithstanding; it is then listed,
    # adopted and closed by `roster_row_open` exactly as every row is. A writer stays closed by its ack:
    # a writer's tree and takeover are not a reader's. The agent cells are read once per run.
    ADOPT_ACTIVE=""
    [ -z "$ADOPT_OWN_PLAN" ] || ADOPT_ACTIVE="$(units_rows "$(adopt_abs "$ADOPT_OWN_PLAN" "$REPO_REAL")" 2>/dev/null \
      | awk -F'\t' '$10 == "active" && $5 ~ /[A-Za-z0-9]/ { print $5 }')"

    # THE WALK IS lib/fill.sh's `fill_roster_walk` (wave-35 T28; AC-5.5, D14): every regular, unlinked
    # `roster-<sid>.state` but this session's, each with its own ledger, an unreadable one said and left
    # out. The fill and the dispatch wall take the same walk, so a row this verb lists open is a row the
    # tick never offers. Read on fd 3: nothing in the body may eat the walk.
    while IFS=$'\t' read -r OSID ADOPT_RF ADOPT_LEDGER <&3; do
      [ -n "$OSID" ] || continue
      ADOPT_OUT="$(adopt_fold "$ADOPT_RF" "$ADOPT_LEDGER")"
      if [ -n "$ADOPT_ACTIVE" ]; then
        # THE SAME FOLD WITH NO ACKS, kept to the active readers of this run the open fold left out.
        while IFS= read -r ADOPT_AR; do
          ADOPT_AR_N="${ADOPT_AR%%|*}"; ADOPT_AR_T="${ADOPT_AR#*|*|}"; ADOPT_AR_T="${ADOPT_AR_T%%|*}"
          [ -n "$ADOPT_AR_N" ] && role_is_readonly "$ADOPT_AR_T" || continue
          case "
$ADOPT_ACTIVE
" in *"
$ADOPT_AR_N
"*) ;; *) continue ;; esac
          case "
$ADOPT_OUT" in *"
$ADOPT_AR_N|"*) continue ;; esac
          ADOPT_AR_P="$(printf '%s' "$ADOPT_AR" | cut -d'|' -f9)"
          [ -n "$ADOPT_OWN_KEY" ] && [ "$(adopt_plan_key "$ADOPT_AR_P")" = "$ADOPT_OWN_KEY" ] || continue
          ADOPT_OUT="${ADOPT_OUT}${ADOPT_OUT:+
}${ADOPT_AR}"
        done <<ADOPT_READERS
$(adopt_fold "$ADOPT_RF" "")
ADOPT_READERS
      fi
      [ -n "$ADOPT_OUT" ] || continue
      # COUNTED WHEN IT CONTRIBUTES, not when it is merely read. A predecessor whose every
      # row is closed is residue, and "N open row(s) from M predecessor session(s)" would be
      # a sentence naming sessions the reader was shown nothing from.
      ADOPT_SESSION_COUNTED=no

      # Resolved ONCE per predecessor session, not once per row: the walk is the same for
      # every agent that session launched.
      OSUB="$(session_subagent_dir "$OSID")" || OSUB=""
      ADOPT_VERDICTS=""; ADOPT_VERDICTS_READ=no

      while IFS='|' read -r RNAME RID RTYPE RDELIV RPROG RCAD RLAUNCH RORIG RPLAN RWAIVER \
                            RSSRC RDONE RLRED RREVID RLROW RSRC; do
        [ -n "$RNAME" ] || continue
        # THE LIST FIELDS ARE READ OFF THE SOURCE ROW, the last column, by key (wave-37 T7, D11).
        RSALLOW="$(line_field "$RSRC" suites_allowed)"
        RREX="$(line_field "$RSRC" re_executes)"

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
        #
        # THE RULE IS lib/fill.sh's `roster_row_open` (wave-36 T10; AC-4.4, D10), the one the dispatch
        # wall's hold asks, in this order: a dead, sweepable session closes (asked once per session);
        # an unreadable plan answers 2, listed UNREADABLE below; a closed run closes; an ack taken in
        # another session after the launch closes. A row the wall admits over is a row this verb skips.
        ADOPT_ROW_CLOSED=no
        ADOPT_ROW_UNREADABLE=""
        roster_row_open "$OSID" "$RNAME" "$RID" "$RLAUNCH" "$RPLAN"
        case $? in
          1) ADOPT_ROW_CLOSED=yes ;;
          2) ADOPT_ROW_UNREADABLE="$ROSTER_ROW_WHY" ;;
        esac
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

        # ---- the evidence (wave-34 T6; REQ-14 AC-14.1, D23)
        #
        # THE REPORT: the sweeper's verdict on the launching session's roster, MET with a completion
        # signal it actually read (`said=`). Asked once per roster, and only of a roster with a row
        # whose deliverable is on disk.
        REPORTED=no
        if [ -n "$RID" ] && [ "$DELIV_PRESENT" = yes ]; then
          if [ "$ADOPT_VERDICTS_READ" = no ]; then
            ADOPT_VERDICTS_READ=yes
            [ -f "$ADOPT_SWEEPER" ] && ADOPT_VERDICTS="$( cd "$REPO_REAL" 2>/dev/null \
              && CLAUDE_CODE_SESSION_ID="$OSID" bash "$ADOPT_SWEEPER" verdict 2>/dev/null )"
          fi
          printf '%s\n' "$ADOPT_VERDICTS" | awk -v k="|name=$(clean "$RNAME")|" \
            'index($0, "landing-verdict/v1|") == 1 && index($0, k) && index($0, "|state=MET|") && index($0, "said=") { f = 1 } END { exit !f }' \
            && REPORTED=yes
        fi
        # REACHABLE BY NAME: this session's fresh answer lists it, and with what status.
        PANEL_ST=""
        [ -n "$RID" ] && [ "$ADOPT_PANEL_RC" -eq 0 ] \
          && PANEL_ST="$(printf '%s\n' "$ADOPT_PANEL" | awk -F'|' -v n="$(clean "$RNAME")" '$1 == n { s = $2 } END { print s }')"
        # GROWTH: the newest kept read at least one cadence old, against this one.
        GREW=""; TX_SIZE=""; BASE_LINE=""
        if [ "$TX_PRESENT" = yes ]; then
          TX_SIZE="$(stat -f %z "$TX" 2>/dev/null || stat -c %s "$TX" 2>/dev/null)"
          case "$TX_SIZE" in ''|*[!0-9]*) TX_SIZE="" ;; esac
        fi
        if [ -n "$TX_SIZE" ]; then
          BASE_LINE="$(adopt_read_baseline "$ADOPT_READS_OLD" "$RID" $(( ADOPT_NOW - OBS_CADENCE_S )))"
          if [ -n "$BASE_LINE" ]; then
            GREW=no; [ "$TX_SIZE" -gt "${BASE_LINE%% *}" ] && GREW=yes
          fi
          ADOPT_READS_NEW="${ADOPT_READS_NEW}${ADOPT_READS_NEW:+
}${ADOPT_READS_SCHEMA}|id=${RID}|size=${TX_SIZE}|epoch=${ADOPT_NOW}"
        fi

        if [ -z "$RID" ]; then
          VERDICT=UNADDRESSABLE
        elif [ -n "$RWAIVER" ]; then
          VERDICT=WAIVED
        elif [ "$DELIV_PRESENT" = yes ] && [ "$REPORTED" = yes ]; then
          VERDICT=LANDED
        elif [ -n "$PANEL_ST" ] && [ "$PANEL_ST" != "$_LA_ROW_CLOSED_STATUS" ]; then
          VERDICT=RUNNING
        elif [ "$GREW" = yes ]; then
          VERDICT=RUNNING
        elif [ -n "$PANEL_ST" ]; then
          VERDICT=IDLE
        elif [ "$GREW" = no ]; then
          VERDICT=SILENT
        elif [ "$LIVE" = yes ]; then
          VERDICT=UNCONFIRMED
        else
          VERDICT=SILENT
        fi
        # THE SENTENCE BEHIND THE WORD, printed under the row: which evidence decided it.
        case "$ADOPT_PANEL_RC" in
          0) PANEL_WORDS="not on this session's fresh ListAgents answer" ;;
          *) PANEL_WORDS="this session has no fresh ListAgents answer to find it on" ;;
        esac
        case "$VERDICT" in
          LANDED)  EVIDENCE="its report is on record, beside the deliverable" ;;
          RUNNING) if [ -n "$PANEL_ST" ]; then EVIDENCE="on this session's fresh ListAgents answer, $PANEL_ST"
                   else EVIDENCE="its transcript grew from ${BASE_LINE%% *} to $TX_SIZE bytes since a read $(( ADOPT_NOW - ${BASE_LINE##* } ))s ago"; fi ;;
          IDLE)    EVIDENCE="on this session's fresh ListAgents answer, idle: it finished its turn with no report on record — message it" ;;
          UNCONFIRMED) EVIDENCE="written within its cadence, but $PANEL_WORDS and no read a cadence old to compare — run ListAgents, or adopt again after ${OBS_CADENCE_S}s" ;;
          SILENT)  if [ "$GREW" = no ]; then EVIDENCE="no growth since a read $(( ADOPT_NOW - ${BASE_LINE##* } ))s ago, and $PANEL_WORDS"
                   else EVIDENCE="nothing written within its cadence, and $PANEL_WORDS"; fi ;;
          *)       EVIDENCE="" ;;
        esac

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
                   "$RSRC" "$RSSRC" "$RDONE" "$RLRED" "$RREVID" "$RLROW"; then
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

        # A READER SAYS SO on its verdict line (wave-36 T29): it holds no tree and no writer slot.
        ADOPT_ROLE_WORD=""
        role_is_readonly "$RTYPE" && ADOPT_ROLE_WORD=" · reader"
        say "$(clean "$RNAME") ($(clean "$RTYPE")) from session $OSID — ${VERDICT}${ADOPT_ROLE_WORD}"
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
        [ -z "$EVIDENCE" ] || printf '  evidence    : %s\n' "$EVIDENCE"
        # THE ROW'S RUN (wave-30 T12; REQ-3 AC-3.5). A row whose agent started a detached suite run
        # (booked.sh --detach) carries its record; the run outlives the session that started it, so
        # the successor is told what it is doing: RUNNING with its pid and age, FINISHED with its
        # code, or LOST with the time its log was last written. `wait <name>` waits on it, and
        # `stop-run <name>` stops it. A row with no run record prints no line.
        if run_load_row "$(run_row_of "$ADOPT_RF" "$RNAME")" "$ADOPT_RF"; then
          run_read
          printf '  run         : %s\n' "$(run_state_words)"
        fi
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
    done 3<<ADOPT_WALK
$(fill_roster_walk "$ADOPT_DIR" "$SESSION_ID")
ADOPT_WALK

    # THE READS ARE KEPT BY THE WRITING VERB ONLY; `--report-only` writes nothing.
    if [ "$ADOPT_REPORT_ONLY" != yes ] && ! adopt_reads_write "$ADOPT_READS_FILE" "$ADOPT_READS_NEW" "$ADOPT_NOW"; then
      die "WARN — the transcript reads could not be kept in $ADOPT_READS_FILE; the next adopt has no read to judge growth against."
    fi

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
      && say "$ADOPT_CLOSED row(s) skipped: their run is closed, their session is dead and its state files are already sweepable, or an ack taken in another session closed them — there is nothing left to take over."
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
    bind_plan "$REPO_REAL" "$SESSION_ID" "$BIND_PATH" bind || BIND_RC=$?
    if [ "$BIND_RC" -eq 0 ]; then
      say "bound $BIND_PATH"
      # A DELIVERED RUN (wave-36 T14; ruling r1791955629-34788): bound, and read bound-closed, so every verb keeps
      # its closed-run refusal but task-set --reason.
      [ "${BIND_DELIVERED:-}" != yes ] \
        || say "$BIND_PATH is delivered: this session reads it bound-closed, and only task-set … --reason '<why>' writes it"
      # THE RUN'S SESSIONS (wave-36 T9; D10): `bind_plan` writes this session's `- session:` line
      # into the plan beside the marker, `by bind`; a plan that could not take it is said, not hidden.
      case "${BIND_SESSION:-}" in
        recorded) say "session $SESSION_ID recorded under ## SDLC State of $BIND_PATH" ;;
        failed) die "the session line could not be written into $BIND_PATH (the plan changed, or is not a regular file); bind again to write it" ;;
      esac
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

  # A RULING FOR A LIVE WRITER (wave-33 T10; REQ-1 AC-1.1 to AC-1.4, D1). The orchestrator's binding
  # instruction to one writer while it works: a `ruling/v1` line on this session's roster (lib/roster.sh
  # `ruling_record`, which owns the state and its one reader). hooks/ruling-push.sh carries it on the
  # writer's next tool result; the writer's commit and `ready` refuse while it is unread. `rulings` reads
  # the state; `ruling-ack` is the writer's own acknowledgement, from its tree (the session key is the
  # orchestrator's in a teammate's shell, so it finds the same roster).
  #
  # REFUSED, exit 2, with the reason (AC-1.3): a name no row of this roster carries, or a row that is
  # closed (`roster_open_names`, the one reader of "is this name closed": ended, or acked after its
  # launch). A ruling for either would never be shown, so it is never written. No session key is 3,
  # as everywhere in this file.
  rule|ruling-ack|rulings)
    SESSION_ID="$(session_id)" || SESSION_ID=""
    if [ -z "$SESSION_ID" ]; then
      die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
      die "A ruling lives on ONE session's roster, so without the key there is nothing to read or write."
      exit 3
    fi
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    ROSTER_FILE="$REPO_REAL/.bionic/tmp/roster-${SESSION_ID}.state"
    if [ ! -f "$ROSTER_FILE" ] || [ -L "$ROSTER_FILE" ]; then
      die "REFUSED — this session has no roster at $ROSTER_FILE, so it has no writer to rule for."
      exit 2
    fi
    case "$VERB" in
      rule)
        if ! grep '^roster-state/' "$ROSTER_FILE" 2>/dev/null | grep -qF "|name=${RULE_WRITER}|"; then
          die "REFUSED — no row named $RULE_WRITER on this session's roster ($ROSTER_FILE); a ruling names one live writer."
          exit 2
        fi
        if ! roster_open_names "$ROSTER_FILE" "$(roster_ack_ledger "$ROSTER_FILE")" | grep -qxF "$RULE_WRITER"; then
          die "REFUSED — $RULE_WRITER's row is closed (ended, or acked after its launch): a ruling for it would never be shown. Nothing written."
          exit 2
        fi
        if [ -n "$RULE_WORDS" ]; then
          # THE USER'S WORDS, AS finding-move HOLDS THEM (wave-36 T9; D10): looked for in every session the
          # bound plan records, then this one; refused in said_refuse's voice, exit 2 as this arm refuses.
          if ! declare -F user_said >/dev/null 2>&1 && [ -f "$BIONIC_LIB/said.sh" ]; then
            . "$BIONIC_LIB/said.sh"
          fi
          if ! declare -F user_said >/dev/null 2>&1; then
            die "REFUSED — what the user typed is read by lib/said.sh, which cannot be loaded from $BIONIC_LIB; nothing written."
            exit 2
          fi
          RULE_PLAN="$(session_plan "$REPO_REAL" "$SESSION_ID" 2>/dev/null)" || RULE_PLAN=""
          user_said "$RULE_WORDS" "$RULE_PLAN"; RULE_SAID=$?
          if [ "$RULE_SAID" -ne 0 ]; then
            said_refuse "$RULE_SAID" "$(said_fold "$RULE_WORDS")" "a ruling's quote"
            exit 2
          fi
          RULE_TEXT="$RULE_TEXT words=\"$(said_fold "$RULE_WORDS" | tr '"' "'")\" session=$SAID_SESSION"
        fi
        RULE_ID="$(ruling_record "$ROSTER_FILE" "$RULE_WRITER" "$RULE_TEXT")" || RULE_ID=""
        if [ -z "$RULE_ID" ]; then
          die "REFUSED — could not write the ruling to $ROSTER_FILE."
          exit 2
        fi
        say "ruling $RULE_ID recorded for $RULE_WRITER — its next tool result carries it, and its commit and ready are refused until it is shown; read it with: rulings $RULE_WRITER"
        exit 0 ;;
      ruling-ack)
        RA_LINE="$(ruling_fold "$ROSTER_FILE" | awk -F"$RULING_US" -v id="$RULING_ID" '$1 == id { print; exit }')"
        if [ -z "$RA_LINE" ]; then
          die "REFUSED — no ruling $RULING_ID on this session's roster ($ROSTER_FILE)."
          exit 2
        fi
        IFS="$RULING_US" read -r RA_ID RA_W RA_REC RA_P RA_C RA_S RA_B RA_T <<< "$RA_LINE"
        if [ -n "$RA_S" ]; then
          say "ruling $RA_ID was already shown to $RA_W (shown=$RA_S by=${RA_B:-?}); nothing to do"
          exit 0
        fi
        RA_NOW="$(date +%s)"
        ruling_stamp "$ROSTER_FILE" "$RA_ID" "$RA_W" "shown=$RA_NOW" "by=ack" || {
          die "REFUSED — could not write to $ROSTER_FILE."
          exit 2
        }
        say "ruling $RA_ID acknowledged — shown=$RA_NOW; your commit and ready no longer wait on it"
        exit 0 ;;
      rulings)
        RS_ANY=no
        while IFS="$RULING_US" read -r RS_ID RS_W RS_REC RS_P RS_C RS_S RS_B RS_T; do
          [ -n "$RS_ID" ] || continue
          RS_ANY=yes
          RS_STATE="unread"
          [ -z "$RS_S" ] || RS_STATE="shown=$RS_S by=${RS_B:-?}"
          say "ruling $RS_ID $RS_W recorded=$RS_REC${RS_P:+ pushed=$RS_P} $RS_STATE — $RS_T"
        done <<< "$(ruling_fold "$ROSTER_FILE" "$RULE_WRITER")"
        [ "$RS_ANY" = yes ] || say "no ruling for $RULE_WRITER on this session's roster"
        exit 0 ;;
    esac
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
    # THE LIFT (wave-35 T8; REQ-6 AC-6.2; D15). A decline stood until a row it did not name was ready, so a
    # hold the user ended ("Build on Opus") stood on and the FILL it held never printed (field report item
    # 10). `decline lift [<ids>]` appends a line of its own, `state=lift` with `lifted=` the rows it ends and
    # no `declined=`; `fill_standing_decline` takes every lift after the latest declined line off that
    # line's rows, for the tick and the stop wall alike. With no ids it ends every row the decline stands
    # for. REFUSED, nothing recorded: no decline standing (1), a row the standing decline does not answer (1).
    if [ -n "$DC_LIFT" ]; then
      DC_LED="$(fill_ledger_path "$REPO_REAL" "$SCHED_PLAN" 2>/dev/null)" || DC_LED=""
      DC_SD="$(fill_standing_decline "$DC_LED" "$SESSION_ID" "")"
      if [ -z "$DC_SD" ]; then
        die "REFUSED — decline lift: no decline stands for this session, so there is nothing to lift; nothing was recorded."
        exit 1
      fi
      IFS=$'\037' read -r _ _ DC_SD_IDS <<< "$DC_SD"
      DC_LIFTED=""; DC_NOT=""
      if [ -z "$DC_IDS" ]; then
        DC_LIFTED="$DC_SD_IDS"
      else
        IFS=', ' read -r -a DC_LIST <<< "$DC_IDS"
        for DC_ID in ${DC_LIST[@]+"${DC_LIST[@]}"}; do
          [ -n "$DC_ID" ] || continue
          case " $DC_LIFTED $DC_NOT " in *" $DC_ID "*) continue ;; esac
          case " $DC_SD_IDS " in
            *" $DC_ID "*) DC_LIFTED="${DC_LIFTED}${DC_LIFTED:+ }$DC_ID" ;;
            *) DC_NOT="${DC_NOT}${DC_NOT:+ }$(clean "$DC_ID")" ;;
          esac
        done
      fi
      if [ -n "$DC_NOT" ]; then
        die "REFUSED — decline lift names $DC_NOT, which no standing decline answers: the decline stands for $DC_SD_IDS. Nothing was recorded."
        exit 1
      fi
      if [ -z "$DC_LED" ] || [ -L "$DC_LED" ] || ! mkdir -p "${DC_LED%/*}" 2>/dev/null; then
        die "REFUSED — the run's fill ledger (${DC_LED:-no path}) cannot be written; nothing was recorded."
        exit 2
      fi
      DC_CUR="$(_fill_current_field "$SCHED_PLAN")"
      DC_LINE="fill-ledger/v1|at=$(iso_now)|session=${SESSION_ID}|turn=|current=${DC_CUR//|/ }|state=lift"
      DC_LINE="${DC_LINE}|ceiling=${SCHED_WRITERS}|width=|open=|free=|ready=|launched=|declined=|missed=0|idle=|room="
      DC_LINE="${DC_LINE}|lifted=${DC_LIFTED// /,}"
      if ! printf '%s\n' "$DC_LINE" >> "$DC_LED" 2>/dev/null; then
        die "REFUSED — could not write to $DC_LED; nothing was recorded."
        exit 2
      fi
      DC_LEFT=""
      for DC_ID in $DC_SD_IDS; do
        case " $DC_LIFTED " in *" $DC_ID "*) : ;; *) DC_LEFT="${DC_LEFT}${DC_LEFT:+ }$DC_ID" ;; esac
      done
      if [ -n "$DC_LEFT" ]; then
        say "decline lift — ${DC_LIFTED// /,}: ended; the decline still stands for $DC_LEFT. Recorded in $DC_LED; the next tick offers the rows it ended."
      else
        say "decline lift — ${DC_LIFTED// /,}: ended; no decline stands now. Recorded in $DC_LED; the next tick offers the rows it ended."
      fi
      exit 0
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
    # WHAT THE HOLD WAITS ON (wave-30 T16; REQ-12 AC-12.7, Δ13; F11: 23.4% of wave-28's build
    # wait-minutes were order holds written only in decline reasons). A row of the plan is a holder
    # the table can carry: for each declined row the `task-set` line that writes the wait as a read,
    # which the tick then judges once (`units_hold_read`). ANYTHING ELSE IS REFUSED (wave-33 T7; REQ-4
    # AC-4.3, D8): a path is a shared file, and a shared file is no dependency (`ready` reconciles it on
    # the line), and a word that is neither names nothing the tick can judge; wave-30 recorded both
    # with `declined-on=` the value, which read as a dependency nothing held. The refusal records
    # nothing and prints the call that succeeds, the same decline without `--on`.
    if [ -n "$DC_ON" ]; then
      DC_ON="$(clean "$DC_ON")"
      case "$DC_ROWS" in
        *" $DC_ON "*) : ;;
        *)
          case "$DC_ON" in
            */*|*.*) die "REFUSED — --on $DC_ON: a shared file is no dependency; \`ready\` reconciles $DC_ON on the line, and a CONFLICT returns the row to merge. Nothing was recorded." ;;
            *) die "REFUSED — --on $DC_ON names no row of $SCHED_PLAN, and only a row is a wait the tick can judge. Nothing was recorded." ;;
          esac
          pv_next decline "$DC_IDS" "$DC_REASON"
          exit 1 ;;
      esac
    fi
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
    # The line is recorded with `declined-on=` the row, or `-` with no --on (a hand-hold the tick
    # cannot judge, and the verb says so).
    DC_ON_AS=-
    [ -z "$DC_ON" ] || DC_ON_AS=row
    DC_CUR="$(_fill_current_field "$SCHED_PLAN")"
    DC_LINE="fill-ledger/v1|at=$(iso_now)|session=${SESSION_ID}|turn=|current=${DC_CUR//|/ }|state=decline"
    DC_LINE="${DC_LINE}|ceiling=${SCHED_WRITERS}|width=|open=|free=|ready=${DC_ALL// /,}|launched="
    DC_LINE="${DC_LINE}|declined=${DC_WHY}|missed=0|idle=|room=|named=${DC_NAMED// /,}"
    DC_LINE="${DC_LINE}|declined-on=$([ "$DC_ON_AS" = - ] && printf -- - || printf '%s' "$DC_ON")"
    if ! printf '%s\n' "$DC_LINE" >> "$DC_LED" 2>/dev/null; then
      die "REFUSED — could not write to $DC_LED; nothing was recorded."
      exit 2
    fi
    for DC_ID in $DC_NAMED; do poker_owed_close "$REPO_REAL" "decline:$DC_ID" "decline"; done
    say "decline — ${DC_NAMED// /,}: recorded in $DC_LED; it stands for those rows until a row it did not name is ready."
    DC_UNREC="unrecorded as a dependency: this hold is a hand-hold the tick cannot judge; it stands only in the decline's reason"
    case "$DC_ON_AS" in
      row)
        for DC_ID in $DC_NAMED; do
          DC_PAIR="$(units_hold_read "$SCHED_PLAN" "$DC_ID" "$DC_ON" 2>/dev/null)" || DC_PAIR=""
          if [ -n "$DC_PAIR" ]; then
            say "decline — $DC_ID waits on $DC_ON: make it a table fact the tick judges once: bash ${HOOK_DIR}/session-poker.sh task-set $DC_ID $(clean_whole "$DC_PAIR")"
          else
            say "decline — $DC_ID waits on $DC_ON, which writes no path to read: $DC_UNREC."
          fi
        done ;;
      *)
        say "decline — $DC_UNREC; name the row it waits on with --on <row>." ;;
    esac
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

  # THE REGRESSION SETTING (wave-31 T27; REQ-12 AC-12.1, AC-12.2; D4). Whether the run runs the
  # regression is a Step-0 setting, written once into the plan's frontmatter as `regression: <v>`,
  # which lib/walls.sh `validate_tests_block` (Step 5), lib/proof.sh `facts_owed` (Step 8) and the
  # integrate row's kind default (lib/units.sh) read. THE SCALE DEFAULT is task no, wave yes, epic no;
  # a value against it is the user's override, recorded beside the key as
  # `regression-override: <git user.name> <date> derived=<default> chosen=<v>`, budget-override:'s
  # form above and the sibling of `rigor-override:`. A value AT the default removes any override
  # line, and the one key and the one override line are rewritten, never doubled. It goes through
  # the plan transaction every plan verb takes. REFUSED: a value that is not exactly yes or no (1);
  # a reply with a line break (1); a plan whose scale: is not task, wave or epic, so there is no
  # default to record against (1); no usable git user name when an override is owed (1); a plan
  # with no leading frontmatter (1). The value in force asked again is the transaction's no-op (0).
  regression)
    case "$RG_V" in
      yes|no) : ;;
      *)
        die "REFUSED — regression $(clean "$RG_V") is not yes or no; the plan is unchanged."
        exit 1 ;;
    esac
    case "$RG_REPLY" in
      *$'\n'*|*$'\r'*)
        die "REFUSED — the user's reply carries a line break; give it on one line. The plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open regression
    RG_SCALE="$(plan_frontmatter_get "$PV_PLAN" scale)"
    case "$RG_SCALE" in
      task|epic) RG_DEF=no ;;
      wave) RG_DEF=yes ;;
      *)
        die "REFUSED — the plan's scale: is '$(clean "${RG_SCALE:-none}")', not task, wave or epic, so the regression has no default to record against; the plan is unchanged."
        exit 1 ;;
    esac
    RG_OVR=""
    if [ "$RG_V" != "$RG_DEF" ]; then
      RG_WHO="$(git -C "$PV_REPO" config user.name 2>/dev/null)"
      if [ -z "$RG_WHO" ] || ! plan_verb_value_ok "$RG_WHO"; then
        die "REFUSED — the project has no usable git user name (git config user.name) to record as the one who overrode the $RG_SCALE default; the plan is unchanged."
        exit 1
      fi
      RG_OVR="regression-override: $RG_WHO $(date -u +%Y-%m-%d) derived=$RG_DEF chosen=$RG_V"
    fi
    # THE VALUES GO IN THROUGH THE ENVIRONMENT, as budget's do. The key is rewritten where it stands,
    # its override directly after it; with no key the pair goes in above the closing `---`.
    if ! RG_V="$RG_V" RG_OVR="$RG_OVR" awk '
      function pair() { print "regression: " ENVIRON["RG_V"]; if (ENVIRON["RG_OVR"] != "") print ENVIRON["RG_OVR"]; done = 1 }
      NR == 1 && $0 == "---" { f = 1; print; next }
      f && $0 == "---" { if (!done) pair(); f = 0; closed = 1; print; next }
      f && /^regression-override:/ { next }
      f && /^regression:/ { if (!done) pair(); next }
      { print }
      END { if (!closed) exit 1 }' "$PV_PLAN" > "$PV_NEW" 2>/dev/null; then
      die "REFUSED — $PV_PLAN has no leading frontmatter to write the regression setting into; the plan is unchanged."
      exit 1
    fi
    plan_verb_swap regression "regression: $RG_V" writer
    say "regression — regression: $RG_V${RG_OVR:+ and $RG_OVR} written to $PV_PLAN; dry-committed first. The Step-5 gate reads the key$([ "$RG_V" = no ] && printf ': its block owes regression: no (Step 0, <user>) — <where it runs> in place of the floor')."
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
  # `evidence` question here as it does at dispatch (`dp_reads_evidence`, lib/brief.sh). The old
  # set plus the added suites is the budget, as the brief named it. A row 1.14.0's map DERIVED is
  # read the same way: nothing re-derives it (the map is deleted, wave-31 T23, REQ-4 AC-4.2), and
  # it keeps its `suites_source=` label.
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

    # THE BUDGET IS THE OLD SET PLUS THE ADDED SUITES, carried into the span as declared, whatever
    # the row's label. `none` is a waiver, and it yields to the first suite actually added.
    AM_DECL="$(poker_union ' ' "$AM_OLD_SA" "$(printf '%s' "$AMEND_SUITES" | tr '\n,' '  ')")"
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
    if [ "$AM_RC" -ne 0 ]; then
      die "REFUSED — a dispatch carrying $AMEND_NAME's amended contract would be refused; nothing was written:"
      printf '%s' "$POKER_BRIEF_WORDS" >&2
      exit 1
    fi

    # A waiver that nothing replaced stays the waiver.
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
    AM_ARGS+=("amended=$(iso_now) ${AMEND_BY:+widened-by: $AMEND_BY }$(clean "$AMEND_REASON")")
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

    # A READER ROW WRITES ITS RECORD (wave-35 T8; REQ-6 AC-6.1; D15). A verify, test or review row whose Files
    # name no record artifact gets <record dir>/<id>.md in its cell, the artifact `brief` gives it, so a row that
    # reads that record waits on this one (the validator refuses a record read no row's Files cover).
    # THE FILES CELL IS JUDGED BY THE DISPATCH GRAMMAR (wave-20 T9; D4, Δ10; T6 carry-over).
    # The cell becomes a brief's `Files:` line at dispatch, so it is read here exactly as the
    # dispatch wall will read it: a cell the lift reads as no path — a template slot, a bare
    # word — is refused now, in the grammar's words, rather than forty minutes later at the
    # dispatch of a row nobody can fix from the table. `—` is the table's "none" and declares
    # nothing to judge. ONE FACT IS THE BRIEF'S, NOT THE CELL'S: a `Files:` line alone names
    # no suite. A dispatch answers it with a `Suites:` or `Re-executes:` line, which the plan
    # row has no column for, so here it is a note and the row goes in.
    poker_files_cell "$TA_ID" "$TA_KIND" "$TA_AGENT" "$TA_FILES" "$REPO_REAL" "$TA_PLAN" || exit $?
    TA_FILES="$PFC_OUT"; TA_ART="$PFC_ART"

    # A ROW REVIEW MADE UNASKED (wave-30 T21; REQ-10 AC-10.1, AC-10.2; D4, Δ3). Three guards, whatever the
    # policy says, each a refusal with the plan byte-identical: (1) the rating is inside the plan's
    # fix-policy:, read verbatim (lib/run.sh `fix_policy_covers`; S1,S2-on when absent); (2) the row is
    # under fix-cap: (lib/units.sh `units_fix_cap`, the level's default when absent), counted off the
    # ledger lines' born: markers (`units_born`, the one place the count reads); (3) no Files path outside
    # the record already carries three review-born rows: the fourth fix on one component stops the run.
    # In-diff is the orchestrator's judgment and "never re-read" the proof's; neither is this verb's.
    # THE FINDINGS A ROW ANSWERS (wave-33 T13; REQ-5, D6): each is a finding of a reading the plan registered,
    # read from its record (`finding_read`); the row's rating is the gravest of them, the lowest S and then on
    # before off, and the guards below hold it as they hold a typed rating.
    # A FINDING THE PERSON MOVED TO FIX IS ASKED, NOT UNASKED (wave-35 T34; A-orch-48): its effective priority
    # (`finding_read`'s FR_P, a `moved:` line) is fix, and `disposition` tells the orchestrator to born a row of
    # it, so the policy guard holds each finding to the policy OR to the person's move, the first that is
    # neither refused with the remedy. The marker keeps the reader's rating, never re-rated.
    TA_BORN_MARK=""; TA_OFF=""; TA_OFF_RATING=""
    TA_POL="$(plan_frontmatter_get "$TA_PLAN" fix-policy)"
    if [ -z "$TA_POL" ] && ! grep -qE '^[[:space:]]*fix-policy[[:space:]]*:' "$TA_PLAN" 2>/dev/null; then
      TA_POL="$FIX_POLICY_DEFAULT"
    fi
    # A FINDING THE PERSON MOVED TO DEFER IS BORN NO ROW (wave-36 T8; REQ-4 AC-4.5, D10): its newest move
    # (lib/proof.sh `proof_move_line`) is the person's last word, whatever its reader's rating, so an S2 on the
    # fix-policy admits is refused as an S3 off is, naming the move, before the policy is asked.
    if [ -n "$TA_BORN_IDS" ]; then
      TA_BEST=""
      for TA_BID in $(printf '%s' "$TA_BORN_IDS" | tr ',' ' '); do
        if ! finding_read "$TA_PLAN" "$REPO_REAL" "$TA_BID"; then
          die "task-add refused — $FR_WHY; the plan is unchanged."
          exit 1
        fi
        if [ "$(_proof_moved_to "$TA_PLAN" "$TA_BID")" = defer ]; then
          die "task-add refused — $(clean "$TA_BID") was moved to defer, and its newest move stands: $(clean "$(proof_move_line "$TA_PLAN" "$TA_BID")"); the plan is unchanged. To fix it after all: disposition $(clean "$TA_BID") fix '<their words>' '<why>', then task-add again."
          exit 1
        fi
        TA_RANK="${FR_S#S}$( [ "$FR_R" = on ] && printf 0 || printf 1 )"
        if [ -z "$TA_BEST" ] || [ "$TA_RANK" -lt "$TA_BEST" ]; then TA_BEST="$TA_RANK"; TA_BORN="review $FR_S $FR_R"; fi
        if [ -z "$TA_OFF" ] && [ "$FR_P" != fix ] && ! fix_policy_covers "$TA_POL" "$FR_S" "$FR_R"; then
          TA_OFF="$TA_BID"; TA_OFF_RATING="review $FR_S $FR_R"
        fi
      done
      TA_BORN_MARK=" of=$TA_BORN_IDS"
      if [ -n "$TA_OFF" ]; then
        die "task-add refused — born: $TA_OFF_RATING is outside fix-policy: $TA_POL; the plan is unchanged; the finding goes to the review findings disposition (AC-10.3). To fix $(clean "$TA_OFF") anyway: disposition $(clean "$TA_OFF") fix '<their words>' '<why>', then task-add again."
        exit 1
      fi
    fi
    TA_CELL_TASK="$TA_TASK"
    if [ -n "$TA_BORN" ]; then
      TA_RATING="${TA_BORN#review }"
      if [ -z "$TA_BORN_IDS" ] && ! fix_policy_covers "$TA_POL" "${TA_RATING% *}" "${TA_RATING#* }"; then
        die "task-add refused — born: $TA_BORN is outside fix-policy: $TA_POL; the plan is unchanged; the finding goes to the review findings disposition (AC-10.3)."
        exit 1
      fi
      if ! TA_CAP="$(units_fix_cap "$TA_PLAN")"; then
        die "task-add refused — born: $TA_BORN has no cap to count against: fix-cap: '$(plan_frontmatter_get "$TA_PLAN" fix-cap)' is no count, or the plan names no rigor: to default it from; the plan is unchanged."
        exit 1
      fi
      TA_BORN_ROWS="$(units_born "$TA_PLAN")"
      TA_NBORN="$(printf '%s' "$TA_BORN_ROWS" | awk 'NF { n++ } END { print n + 0 }')"
      if [ "$TA_NBORN" -ge "$TA_CAP" ]; then
        die "task-add refused — review-born rows: $TA_NBORN of cap $TA_CAP; this finding goes to the review findings disposition (AC-10.3)."
        exit 1
      fi
      while IFS= read -r TA_PATH; do
        [ -n "$TA_PATH" ] || continue
        case "$TA_PATH" in .bionic/*|record/*) continue ;; esac
        TA_FIXERS="$(printf '%s\n' "$TA_BORN_ROWS" | while IFS=$'\t' read -r TA_BID _ TA_BFILES; do
            [ -n "$TA_BID" ] || continue
            _units_split_tokens "$TA_BFILES" | grep -Fx -- "$TA_PATH" >/dev/null && printf '%s\n' "$TA_BID"
          done)"
        if [ "$(printf '%s' "$TA_FIXERS" | awk 'NF { n++ } END { print n + 0 }')" -ge 3 ]; then
          die "task-add refused — a fourth fix on $TA_PATH: $(printf '%s' "$TA_FIXERS" | paste -sd, - | sed 's/,/, /g') already fix it; stop the run (AC-10.2)"
          exit 1
        fi
      done <<EOF
$(_units_split_tokens "$TA_FILES")
EOF
      TA_CELL_TASK="$TA_TASK · born: review"
    fi
    # A FLOOR-BORN MARKER NAMES ITS RED (wave-36 T42; D9, Δ8): the marker is admitted only with a red the machine
    # recorded behind it (`born_floor_backing`), and it records which, ` of=floor` or ` of=standing@<12-hex>`.
    TA_BORN_OF=""
    if [ -n "$TA_BORN_FLOOR" ]; then
      if ! born_floor_backing "$TA_PLAN" "$REPO_REAL" "$TA_BORN_FLOOR"; then
        die "task-add refused — born: floor $TA_BORN_FLOOR names no red the machine recorded; it is admitted when the plan's floor proof owes $TA_BORN_FLOOR (it owes ${BFB_OWED:-nothing}; proof-add floor, from a whole run that left it red) or when the landing record holds a standing event for $TA_BORN_FLOOR at a commit on ${BFB_BRANCH:-the working branch}; the plan is unchanged."
        exit 1
      fi
      TA_BORN_OF="$BFB_OF"; TA_CELL_TASK="$TA_TASK · born: floor"
    fi

    if ! units_add_row "$TA_PLAN" "$TA_ID" "$TA_STEP" "$TA_KIND" "$TA_CELL_TASK" "$TA_AGENT" \
         "$TA_DEPS" "$TA_SIZE" "$TA_SERVES" "$TA_FILES" "$TA_READS" "${TA_BORN:+$TA_BORN$TA_BORN_MARK}${TA_BORN_FLOOR:+floor $TA_BORN_FLOOR of=$TA_BORN_OF}" > "$PV_NEW" 2>/dev/null || [ ! -s "$PV_NEW" ]; then
      die "REFUSED — $TA_PLAN carries no ## Tasks table or no ## SDLC State section to add $TA_ID to; the plan is unchanged."
      exit 1
    fi

    TA_VIOL="$(units_validate "$PV_NEW" 2>&1)"
    if [ -n "$TA_VIOL" ]; then
      die "REFUSED — with $TA_ID added, the ## Tasks table breaks the Task invariants; the plan is unchanged:"
      printf '%s\n' "$TA_VIOL" >&2
      # A STEP-7 DOC ROW IS NO LONGER REFUSED FOR ITS APPROVAL READ (wave-35 T5; D13): the release
      # approval is the integrate row's read, so the one-retry wave-33 T7 printed here is gone with it.
      exit 1
    fi

    plan_verb_swap task-add "$TA_ID added" writer
    say "task-add — $TA_ID added to $TA_PLAN: the row and its - $TA_ID: line; validated and dry-committed first."
    [ -z "$TA_ART" ] || say "task-add — $TA_ID is a $TA_KIND row: its Files carry its record artifact, $TA_ART."
    [ -z "$TA_BORN" ] || say "task-add — $TA_ID is review-born ($TA_BORN): review-born rows: $((TA_NBORN + 1)) of cap $TA_CAP; say so in the review findings disposition (AC-10.2)."
    [ -z "$TA_BORN_FLOOR" ] || say "task-add — $TA_ID is floor-born ($TA_BORN_FLOOR), backed by of=$TA_BORN_OF: its landing holds every reading's cover (D9), and it counts against no fix-cap."
    # A ROW NOW ANSWERS EACH FINDING IT NAMES, so the person owes no ruling on it: its owed item closes.
    for TA_BID in $(printf '%s' "$TA_BORN_IDS" | tr ',' ' '); do
      poker_owed_close "$REPO_REAL" "$(finding_owed_key "$TA_BID")" "task-add $TA_ID"
      say "task-add — $TA_ID answers $(clean "$TA_BID")"
    done
    # THE SUSPECT TEST AT AUTHORING (wave-30 T16; REQ-12 AC-12.2, D14a): the row is in; a dependency
    # that shares no file with its holder is named, with the line that would loosen it, never run.
    suspect_lines "$TA_PLAN" "$TA_ID" | while IFS=$'\t' read -r _ _ TA_SUSPECT; do say "$(clean_whole "$TA_SUSPECT")"; done
    exit 0
    ;;

  # THE ROW-CELL VERBS (wave-24 T15; REQ-9 AC-9.1/9.2, D14). `task-set` sets cells of a
  # `## Tasks` row, `ledger-set` of a `## Dispatch ledger` row, and `ledger-add` appends a ledger
  # row; each through `units_table_cells`, on the shared transaction. A `## Tasks` column is any
  # the header carries by `units_has_column`, except `id`, the key the row is found by, and, for a row with a
  # launch behind it, `Files`: a dispatched agent's CONTRACT once it is on the roster (editing the plan row
  # changes nothing a wall reads), so the refusal names `amend`, the verb that widens it. A PENDING row no
  # roster names has no contract, and `files=<list>` is the table's to set (wave-36 T41; the pre-pass below). `task-set` is judged by `units_validate` before the
  # gate, as `task-add` is: a status, step or deps cell is a schedule change.
  task-set|ledger-add|ledger-set)
    # THE ROWS A CALL SETS (wave-33 T7). One entry per row: its id and its pairs, joined by the unit
    # separator. A ledger verb names one row; task-set's groups name many, each id with its group's pairs.
    PV_SETS=()
    if [ "$VERB" = task-set ]; then
      for _pv_g in "${PV_GROUPS[@]}"; do
        _pv_ids="${_pv_g%%$'\037'*}"; _pv_rest="${_pv_g#*$'\037'}"
        while [ -n "$_pv_ids" ]; do
          _pv_i="${_pv_ids%%,*}"
          case "$_pv_ids" in *,*) _pv_ids="${_pv_ids#*,}" ;; *) _pv_ids="" ;; esac
          _pv_i="$(printf '%s' "$_pv_i" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
          PV_SETS+=("$_pv_i"$'\037'"$_pv_rest")
        done
      done
    else
      _pv_rest=""
      for _pv_a in ${PV_PAIRS[@]+"${PV_PAIRS[@]}"}; do _pv_rest="${_pv_rest:+$_pv_rest$'\037'}$_pv_a"; done
      PV_SETS=("$PV_ID"$'\037'"$_pv_rest")
    fi
    # pv_set_pairs <set> -> PV_SET_ID and PV_SET_PAIRS, the set taken apart.
    pv_set_pairs() {
      local r="${1#*$'\037'}" p
      PV_SET_ID="${1%%$'\037'*}"; PV_SET_PAIRS=()
      while [ -n "$r" ]; do
        p="${r%%$'\037'*}"
        case "$r" in *$'\037'*) r="${r#*$'\037'}" ;; *) r="" ;; esac
        PV_SET_PAIRS+=("$p")
      done
    }
    # THE ID AND THE COLUMN NAME ARE OPERANDS TOO (wave-24 T27; Step-6 review C1). `ledger-add`
    # writes its id into the new row's first cell, and a line break there forged a plan line
    # the commit gate admitted. The id is one token of the grammar every ledger row already
    # carries (`T7`, `T22b`, `T17-critic`); a name is held to the values' own rule.
    for _pv_s in "${PV_SETS[@]}"; do
      pv_set_pairs "$_pv_s"
      if ! plan_verb_id_ok "$PV_SET_ID"; then
        die "REFUSED — '$(clean "$PV_SET_ID")' is not one row id: an id is one token of letters, digits, '.', '_' or '-', beginning with a letter or a digit. The plan is unchanged."
        exit 1
      fi
      for _pv_a in ${PV_SET_PAIRS[@]+"${PV_SET_PAIRS[@]}"}; do
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
          files) PV_FILES_ASKED=1; continue ;;  # a fixed column, judged after the plan is open, not an optional one the header lists
          id)
            die "REFUSED — id is the key task-set finds $PV_SET_ID by, not a cell to set; the plan is unchanged."
            exit 1 ;;
          rigor) _pv_l=kind ;;
        esac
        PV_COLS="${PV_COLS:-} $_pv_l"
      done
    done
    if [ -n "${PV_REASON:-}" ]; then
      if ! plan_verb_value_ok "$PV_REASON"; then
        die "REFUSED — the reason carries a |, a tab or a line break, which no step line can hold; the plan is unchanged."
        exit 1
      fi
      for _pv_s in "${PV_SETS[@]}"; do
        pv_set_pairs "$_pv_s"
        case "$PV_SET_ID" in
          T[0-9]*) : ;;
          *) die "REFUSED — a reason is recorded on the row's - T<n>: line, and $PV_SET_ID has none; the plan is unchanged."
             exit 1 ;;
        esac
      done
    fi
    plan_verb_open "$VERB" ${PV_REASON:+closed-ok}
    PV_TABLE="## Tasks"; [ "$VERB" = task-set ] || PV_TABLE="## Dispatch ledger"
    # AN UNKNOWN COLUMN NAMES THE CALL THAT SUCCEEDS (wave-33 T7; REQ-4 AC-4.3). The header's columns are
    # listed, and the call is printed again with each unknown name replaced by the one column it was
    # meant as (`pv_column_guess`); a name with no such column is left out of it, and said so.
    pv_cols_refuse() {  # <columns, one per line>
      local cols="$1" t want=1 out
      local -a call
      call=()
      for t in "${PV_ARGS[@]}"; do
        if [ "$want" = 1 ]; then call+=("$t"); want=0; continue; fi
        case "$t" in
          --) call+=("$t"); want=1; continue ;;
        esac
        pv_fix_pairs "$cols" "$t"
        [ "${#PV_FIXED[@]}" -eq 0 ] || call+=("${PV_FIXED[0]}")
        [ -z "$PV_UNKNOWN" ] || out="${out:+$out, }$PV_UNKNOWN"
      done
      [ -z "${PV_REASON:-}" ] || call+=(--reason "$PV_REASON")
      die "The $PV_TABLE columns: $(printf '%s\n' "$cols" | paste -sd, - | sed 's/,/, /g')."
      [ -z "${out:-}" ] || die "No column is like: ${out}; the call below leaves it out."
      pv_next "$VERB" "${call[@]}"
    }
    if [ "$VERB" = task-set ]; then
      PV_BAD=""
      for _pv_l in ${PV_COLS:-}; do
        # `artifact` is the row's record cell (wave-37 T6; D10): the refusal below names `artifact=<path>` as the remedy, so the
        # header's own cell takes it, though the units control line lists only the contract columns.
        units_has_column "$PV_PLAN" "$_pv_l" \
          || { [ "$_pv_l" = artifact ] && pv_header_cells "$PV_PLAN" tasks | /usr/bin/grep -ix artifact >/dev/null; } \
          || PV_BAD="${PV_BAD:+$PV_BAD, }$_pv_l"
      done
      if [ -n "$PV_BAD" ]; then
        die "REFUSED — the ## Tasks header of $PV_PLAN carries no column $PV_BAD; the plan is unchanged."
        pv_cols_refuse "$(pv_header_cells "$PV_PLAN" tasks | awk '{ l = tolower($0) } l != "id" && l != "files" { print l }')"
        exit 1
      fi
    fi
    # A PENDING ROW'S FILES CELL IS THE TABLE'S, A LAUNCHED ROW'S IS A CONTRACT (wave-36 T41; REQ-7 AC-7.1, AC-10.2;
    # D13; A-orch-5, A-orch-6, A-orch-9, A-orch-10). One rule: a row `pending` with no roster row naming it has no
    # launch behind it, so `files=<list>` replaces its cell whole and the list is judged as task-add judges a cell
    # (`poker_files_cell`); a row with a launch has a contract on a roster, which only `amend` widens, so an active,
    # landed or roster-named row (or one this same call sets to another status) is refused as it always was, naming
    # amend. The judged value takes the place of the operand in its set, so the write below is the one transaction.
    if [ "$VERB" = task-set ] && [ -n "${PV_FILES_ASKED:-}" ]; then
      PV_JUDGED=()
      for _pv_s in "${PV_SETS[@]}"; do
        pv_set_pairs "$_pv_s"
        _pv_row="$(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' -v id="$PV_SET_ID" '$1 == id { print; exit }')"
        _pv_new="$PV_SET_ID"
        for _pv_a in ${PV_SET_PAIRS[@]+"${PV_SET_PAIRS[@]}"}; do
          _pv_l="$(printf '%s' "${_pv_a%%=*}" | tr '[:upper:]' '[:lower:]')"
          if [ "$_pv_l" = files ] && [ -n "$_pv_row" ]; then
            _pv_status="$(printf '%s\n' "$_pv_row" | awk -F'\t' '{ print $10 }')"
            _pv_moved=""
            for _pv_b in ${PV_SET_PAIRS[@]+"${PV_SET_PAIRS[@]}"}; do
              case "$(printf '%s' "${_pv_b%%=*}" | tr '[:upper:]' '[:lower:]')" in
                status) [ "${_pv_b#*=}" = pending ] || _pv_moved=1 ;;
              esac
            done
            if [ "$_pv_status" != pending ] || [ -n "$_pv_moved" ] || pv_roster_names_row "$PV_SET_ID"; then
              die "REFUSED — task-set does not write Files — widen a dispatched contract with amend: bash ${HOOK_DIR}/session-poker.sh amend <name> --files+ <path> --reason <why>. The plan is unchanged."
              exit 1
            fi
            poker_files_cell "$PV_SET_ID" "$(printf '%s\n' "$_pv_row" | awk -F'\t' '{ print $3 }')" \
              "$(printf '%s\n' "$_pv_row" | awk -F'\t' '{ print $5 }')" "${_pv_a#*=}" "$PV_REPO" "$PV_PLAN" || exit $?
            # A RECORD ROW KEEPS ITS ARTIFACT (wave-37 T6; REQ-7 AC-7.3; D10; A-T6-1): a row whose cell names an entry for
            # it, or which carries an `artifact` cell, is not left with neither, by the one rule `brief` reads.
            _pv_art="$(poker_brief_cell "$PV_PLAN" Tasks "$PV_SET_ID" artifact)" || _pv_art=""
            _pv_had="$_pv_art"
            for _pv_b in ${PV_SET_PAIRS[@]+"${PV_SET_PAIRS[@]}"}; do
              case "$(printf '%s' "${_pv_b%%=*}" | tr '[:upper:]' '[:lower:]')" in artifact) _pv_art="${_pv_b#*=}" ;; esac
            done
            if { ! poker_brief_none "$_pv_had" || [ -n "$(poker_brief_record_entry "$(units_field "$_pv_row" Files)" named "$PV_SET_ID")" ]; } \
               && poker_brief_none "$_pv_art" && [ -z "$(poker_brief_record_entry "$PFC_OUT" named "$PV_SET_ID")" ]; then
              die "task-set refused — Files leaves $PV_SET_ID with no artifact: name a record $PV_SET_ID-<name>.md in Files or set artifact=<path>"
              exit 1
            fi
            _pv_a="${_pv_a%%=*}=$PFC_OUT"
          fi
          _pv_new="$_pv_new"$'\037'"$_pv_a"
        done
        PV_JUDGED+=("$_pv_new")
      done
      PV_SETS=("${PV_JUDGED[@]}")
    fi
    case "$VERB" in
      task-set)   PV_MODE=set; PV_SECT=tasks ;;
      ledger-set) PV_MODE=set; PV_SECT=ledger ;;
      ledger-add) PV_MODE=add; PV_SECT=ledger ;;
    esac
    cp "$PV_PLAN" "$PV_NEW"
    PV_WHAT=""
    for _pv_s in "${PV_SETS[@]}"; do
      pv_set_pairs "$_pv_s"
      PV_RC=0
      units_table_cells "$PV_NEW" "$PV_MODE" "$PV_SECT" "$PV_SET_ID" "${PV_SET_PAIRS[@]}" > "$PV_NEW.2" 2>/dev/null || PV_RC=$?
      case "$PV_RC" in
        0) mv -f "$PV_NEW.2" "$PV_NEW" ;;
        1) die "REFUSED — $PV_PLAN carries no $PV_TABLE table; the plan is unchanged."; exit 1 ;;
        2) if [ "$PV_MODE" = add ]; then die "REFUSED — the $PV_TABLE table already carries a row $PV_SET_ID; set its cells with ledger-set. The plan is unchanged."
           else die "REFUSED — the $PV_TABLE table carries no row $PV_SET_ID; the plan is unchanged."; fi
           exit 1 ;;
        3) die "REFUSED — the $PV_TABLE header carries no column named in: ${PV_SET_PAIRS[*]%%=*}; the plan is unchanged."
           pv_cols_refuse "$(pv_header_cells "$PV_PLAN" "$PV_SECT")"
           exit 1 ;;
        5) die "REFUSED — the $PV_TABLE table carries more than one row $PV_SET_ID; which one is meant is not the verb's to guess. The plan is unchanged."; exit 1 ;;
        *) die "REFUSED — the value cannot be written as a table cell; the plan is unchanged."; exit 1 ;;
      esac
      PV_WHAT="${PV_WHAT:+$PV_WHAT; }$PV_SET_ID ${PV_SET_PAIRS[*]}"
    done
    if [ "$VERB" = task-set ]; then
      PV_VIOL="$(units_validate "$PV_NEW" 2>&1)"
      if [ -n "$PV_VIOL" ]; then
        die "REFUSED — with that change, the ## Tasks table breaks the Task invariants; the plan is unchanged:"
        printf '%s\n' "$PV_VIOL" >&2
        exit 1
      fi
    fi
    # THE REASON ON THE STEP LINE (wave-36 T14; AC-7.7): ` reason: <why>` after each named row's own text, once (a
    # line that already ends so is left), in the same copy, so the cells and the reason are one write.
    if [ -n "${PV_REASON:-}" ]; then
      for _pv_s in "${PV_SETS[@]}"; do
        pv_set_pairs "$_pv_s"
        _pv_rest="$(units_step_text "$PV_NEW" "$PV_SET_ID" 2>/dev/null)"
        case "$_pv_rest " in *" reason: $PV_REASON "|"reason: $PV_REASON ") continue ;; esac
        if ! units_step_line "$PV_NEW" "$PV_SET_ID" "${_pv_rest:+$_pv_rest }reason: $PV_REASON" > "$PV_NEW.2" 2>/dev/null; then
          die "REFUSED — $PV_PLAN carries no ## SDLC State section for the $PV_SET_ID line; the plan is unchanged."
          exit 1
        fi
        mv -f "$PV_NEW.2" "$PV_NEW"
      done
      PV_WHAT="$PV_WHAT; reason: $PV_REASON"
    fi
    [ "$PV_MODE" = add ] && PV_WHAT="$PV_ID added to the dispatch ledger"
    plan_verb_swap "$VERB" "$PV_WHAT" writer
    say "$VERB — $PV_WHAT: written to $PV_PLAN; dry-committed first."
    # THE SUSPECT TEST AT EVERY RE-AUTHORING (wave-30 T16; AC-12.2): task-set prints it as task-add does.
    if [ "$VERB" = task-set ]; then
      for _pv_s in "${PV_SETS[@]}"; do
        pv_set_pairs "$_pv_s"
        suspect_lines "$PV_PLAN" "$PV_SET_ID" | while IFS=$'\t' read -r _ _ PV_SUSPECT; do say "$(clean_whole "$PV_SUSPECT")"; done
      done
    fi
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
  #
  # A PLACEHOLDER LEAD IS REPLACED, NOT KEPT (wave-33 T6; REQ-3 AC-3.3, D5). A line that opens
  # `pending dispatch` (the Step-3 template, `task-add`, `task-split`) gives that lead to the landing
  # text and keeps the rest of its words, a ` born: ` marker included (`units_born` reads it there):
  # `- T5: pending dispatch — .worktrees/01-T5` lands as `- T5: landed <commit> <at> — .worktrees/01-T5`.
  #
  # `deliver <row>` (wave-33 T6; D5) is this verb for a record row: `deliver_check` reads what the row
  # owes and sets the commit (the working head), the instant (now) and the artifact, which is
  # written into the ledger line's `artifact` cell beside the landed one, in this same write.
  row-landed|deliver)
    if ! plan_verb_id_ok "$PV_ID"; then
      die "REFUSED — '$(clean "$PV_ID")' is not one row id; the plan is unchanged."
      exit 1
    fi
    if ! plan_verb_value_ok "$RL_BY" || ! plan_verb_value_ok "$RL_WHY"; then
      die "REFUSED — the hand landing's name or reason carries a |, a tab or a line break, which no plan line can hold; the plan is unchanged."
      exit 1
    fi
    plan_verb_open row-landed
    [ "$VERB" != deliver ] || deliver_check
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
          " pending dispatch "*) RL_LINE="$RL_TEXT${RL_REST#pending dispatch}" ;;
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
    # A DELIVERED ROW'S LEDGER LINE NAMES ITS ARTIFACT (wave-33 T6; AC-3.1): the cell the artifact was
    # read from, or the empty one of a line this landing added. A ledger with no artifact column has
    # no cell to hold it, and the landing stands without one.
    if [ -n "$RL_ARTIFACT" ] && [ "$PV_RC" -eq 0 ]; then
      if units_table_cells "$PV_NEW" set ledger "$PV_ID" "artifact=$RL_ARTIFACT" > "$PV_NEW.2" 2>/dev/null; then
        mv -f "$PV_NEW.2" "$PV_NEW"
      else
        rm -f "$PV_NEW.2"
      fi
    fi
    # THE EVIDENCE CELLS (wave-31 T22; REQ-15 AC-15.1 to AC-15.3, D15): the criteria this row serves gain the log of
    # the suite their eval names, read off the landing record's verdicts for this row and commit (`landing_evidence`).
    # A hand landing's record carries no verdict, so it writes none. Same copy, same dry commit, same swap.
    RL_SLUG="$(proof_plan_slug "$PV_PLAN")"
    RL_N="$(landing_evidence "$PV_NEW" "$PV_NEW.2" "$PV_ID" "$RL_COMMIT" "$(_wt_proofs_path "$PV_REPO" "$PV_PLAN")" \
      "$(docs_root "$PV_REPO")" "$RL_SLUG")" || {
      die "REFUSED — the evidence cells of the criteria $PV_ID serves cannot be written; the plan is unchanged."
      exit 1
    }
    [ ! -f "$PV_NEW.2" ] || mv -f "$PV_NEW.2" "$PV_NEW"
    plan_verb_swap row-landed "$PV_ID landed at $RL_COMMIT" writer
    say "row-landed — $PV_ID landed at $RL_COMMIT: status, step line and ledger line written to $PV_PLAN in one write; dry-committed first."
    say "evidence: $RL_N cell(s) written by landing"
    [ "$VERB" != deliver ] || say "deliver — $PV_ID: artifact $RL_ARTIFACT present; landed at the working head $RL_COMMIT."
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

  # THE STEP-FIELD VERB (wave-28 T8; REQ-3 AC-3.5, D17). A `- Step N:` block is the evidence the gate reads, and
  # the fields it reads were hand edits: `units_step_fields --replace` writes one `  <key>: <value>` line under
  # the step line, after the block last line, or replaces the line where it stands (the gate reads the first
  # line of a key, so a second could not win); the rest of the plan is the same bytes. Ten keys, the ones the
  # gate reads at Steps 4, 5, 7 and 8: head cmd pass total output (the regression run), merge worktree-removed (the
  # integration), adr (the document step), share (the Step-4 fact), walk-artifact (the walk gate's pointer, Step 5
  # alone; wave-33 T7). It takes the plan transaction every row verb
  # takes (copy, dry commit through the real gate, checksum, swap), so a plan the gate would refuse is not
  # written. REFUSED (1), the plan unchanged: a key outside the ten, a value with a line break, a step with no
  # line (step-line writes it), a key the step line itself carries (step-line owns that text), and Step 9
  # (close-out writes that block). The refusals are this verb family die lines, not refuse.sh refusals.
  step-field)
    case "$PV_KEY" in
      9|9a|9b)
        die "REFUSED — the Step 9 block is close-out's to write (scripts/close-out.sh)."
        exit 1 ;;
    esac
    case "$PV_FKEY" in
      head|cmd|pass|total|output|merge|worktree-removed|adr|share|walk-artifact) : ;;
      *)
        die "REFUSED — '$(clean "${PV_FKEY:0:20}")' is not a step field; the plan is unchanged."
        die "The fields: head, cmd, pass, total, output, merge, worktree-removed, adr, share, walk-artifact (Step 5)."
        exit 1 ;;
    esac
    # THE WALK POINTER (wave-33 T7; REQ-4 AC-4.1, D8; A-orch-42). The walk gate reads `walk-artifact:`
    # from the Step-5 block alone (walls.sh `step5_evidence_block`), so the key is written there and at no
    # other step; and it refuses a path that climbs out with `..`, so the verb refuses it first.
    if [ "$PV_FKEY" = walk-artifact ]; then
      if [ "$PV_KEY" != 5 ]; then
        die "REFUSED — walk-artifact is read from the Step 5 block only (the walk gate's), not Step $PV_KEY's; the plan is unchanged."
        pv_next step-field 5 "walk-artifact=$PV_FVAL"
        exit 1
      fi
      case "/$PV_FVAL/" in
        */../*)
          die "REFUSED — the walk artifact '$(clean "$PV_FVAL")' has a '..' component, which the walk gate refuses: name it under record/. The plan is unchanged."
          exit 1 ;;
      esac
    fi
    case "$PV_FVAL" in
      *$'\n'*|*$'\r'*)
        die "REFUSED — a step field is one line, and the value has a line break; the plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open step-field
    PV_RC=0
    units_step_fields --replace "$PV_PLAN" "$PV_KEY" "$PV_FKEY=$PV_FVAL" > "$PV_NEW" 2>/dev/null || PV_RC=$?
    case "$PV_RC" in
      0) : ;;
      1) die "REFUSED — the plan has no Step $PV_KEY line; step-line writes it first. The plan is unchanged."
         exit 1 ;;
      5) die "REFUSED — the Step $PV_KEY line itself carries '$PV_FKEY:'; step-line writes that text."
         die "The plan is unchanged."
         exit 1 ;;
      *) die "REFUSED — the field cannot be written (units_step_fields exit $PV_RC); the plan is unchanged."
         exit 1 ;;
    esac
    # THE POINTER HAS ONE WRITER (wave-36 T44; REQ-7 AC-7.1, AC-10.2; D13). matrix-render writes a matrix-level
    # `walk-artifact: pending` stub that the gate refuses as a placeholder once every row is discharged, and no verb filled
    # it: the fix was a hand edit. The Step 5 block stays the walk gate's one reader; the matrix line, when the plan has
    # one, takes the same value in the same transaction. A matrix with no such line gains none.
    if [ "$PV_FKEY" = walk-artifact ]; then
      PV_RC=0
      SF_WV="$PV_FVAL" awk '
        { if ($0 ~ /^[ \t]*```/) fence = !fence }
        /^## / { m = ($0 ~ /^## Verification Matrix/) }
        !fence && m && !done && /^[ \t]*walk-artifact[ \t]*:/ {
          ind = $0; sub(/[^ \t].*$/, "", ind); print ind "walk-artifact: " ENVIRON["SF_WV"]; done = 1; next }
        { print }' "$PV_NEW" > "$PV_NEW.m" 2>/dev/null || PV_RC=$?
      if [ "$PV_RC" -ne 0 ]; then
        die "REFUSED — the matrix walk-artifact: line cannot be written (awk exit $PV_RC); the plan is unchanged."
        exit 1
      fi
      mv "$PV_NEW.m" "$PV_NEW"
    fi
    plan_verb_swap step-field "Step $PV_KEY $PV_FKEY" writer
    say "step-field — Step $PV_KEY $PV_FKEY: written to $PV_PLAN; dry-committed first."
    exit 0
    ;;

  # THE MATRIX RENDER (wave-30 T14; REQ-6 AC-6.1, D9, Δ12a). Step 3 writes the matrix and Step 5 fills it: the
  # verb reads the bound plan's `## Eval design` table and writes, under `## Verification Matrix`, one AC block per
  # criterion, in the shape the gate reads — its `AC-<n>:` line carrying the criterion's text from its `- AC-<n>`
  # bullet, `provenance:` (the requirement's `provenance:` line under its `### REQ-<n>` heading in the requirements
  # file the plan names, else in the plan, else `pending`; never the Approach: wave-35 T8, AC-6.4), `fails-when:`
  # and `eval:` (`<tier> — <Eval>`) from the table,
  # `task:` (the one `## Tasks` row whose serves cell names the criterion or its requirement, else `pending`), then
  # `evidence:` (and `user-confirmed:` at T4), the keys walls.sh `keys_for_tier` names for the tier the matrix
  # table gives the criterion, each `pending`. The matrix head gains `stack-health: pending`, and `walk-artifact: pending` unless the
  # plan is `walk: exempt`, where it has none. `pending` is the stub token (Δ12a): the gate refuses it wherever it
  # judges evidence and reads nothing of it before Step 5.
  #
  # ADDITIVE, SO IT CAN BE RUN AGAIN. A block that exists gains only the keys it lacks, after its last line; a key
  # that is there is never rewritten, whatever it says. The one line it prints counts the three outcomes: new
  # blocks, keys added (to existing blocks and the matrix head), and blocks left as they were. When there is nothing
  # to add it writes nothing. It takes the transaction every plan verb takes (copy, dry commit, checksum, swap).
  # REFUSED (1), the plan unchanged: no `## Eval design` with criteria, no matrix table, a criterion with no matrix
  # row (its tier is unknown, and a guessed tier owes the wrong keys), a tier walls.sh does not know.
  matrix-render)
    plan_verb_open matrix-render
    MR_KEYS="$(mr_tier_keys)" || MR_KEYS=""
    if [ -z "$MR_KEYS" ]; then
      die "REFUSED — the per-tier keys are walls.sh keys_for_tier's, and $BIONIC_LIB/walls.sh cannot be loaded; the plan is unchanged."
      exit 2
    fi
    MR_TASKS="$(serves_tasks "$PV_PLAN")"
    PV_RC=0
    MR_KEYS="$MR_KEYS" MR_TASKS="$MR_TASKS" MR_WALK="$(plan_frontmatter_get "$PV_PLAN" walk)" MR_COUNT="$PV_NEW.2" \
      MR_REQFILE="$(mr_requirements_file "$PV_PLAN" "$PV_REPO")" \
      awk "$SERVES_AWK$MR_AWK" "$PV_PLAN" > "$PV_NEW" 2>/dev/null || PV_RC=$?
    MR_WHY="$(cut -f2 "$PV_NEW.2" 2>/dev/null)"
    case "$PV_RC" in
      0) : ;;
      3) die "REFUSED — the plan has no ## Eval design table with a Criterion column and rows; matrix-render reads the criteria from it. The plan is unchanged."
         exit 1 ;;
      4) die "REFUSED — the plan's ## Verification Matrix has no AC tier table (| AC | tier | status | evidence | auditor |); each criterion's tier is read from it. The plan is unchanged."
         exit 1 ;;
      5) die "REFUSED — the matrix table has no row for $MR_WHY, so the tier and the keys it owes are unknown; add the row, then render. The plan is unchanged."
         exit 1 ;;
      6) die "REFUSED — no tier walls.sh knows for $MR_WHY: the tier cell is T0 to T4. The plan is unchanged."
         exit 1 ;;
      *) die "REFUSED — the matrix cannot be rendered (awk exit $PV_RC); the plan is unchanged."
         exit 2 ;;
    esac
    IFS="$(printf '\t')" read -r MR_N MR_M MR_K < "$PV_NEW.2"
    MR_LINE="matrix-render — ${MR_N:-0} blocks written, ${MR_M:-0} keys added, ${MR_K:-0} unchanged"
    if [ "$(( ${MR_N:-0} + ${MR_M:-0} ))" -eq 0 ]; then
      say "$MR_LINE; the plan already reads so, nothing was written."
      exit 0
    fi
    plan_verb_swap matrix-render "the matrix rendered" writer
    say "$MR_LINE; written to $PV_PLAN, dry-committed first."
    exit 0
    ;;

  # THE AUDITOR CELL'S ONE WRITER (wave-30 T14; REQ-6 AC-6.2, D9). The gate compares the matrix `auditor` cell with
  # the bare token `CONFIRMED` past the Verify gate and refuses anything after it; wave-28's scratch scripts wrote
  # `CONFIRMED <date>` there by hand. This verb sets the row's fifth cell to exactly `CONFIRMED` — whatever it held,
  # a dated token among them — and leaves every other byte of the plan as it was; the audit's own path belongs in the
  # row's `evidence:` key, not in this cell. A row already CONFIRMED is nothing to write. REFUSED (1), the plan
  # unchanged: an AC id the matrix table has no row for (the id is compared whole, so AC-1 is not AC-1.1), a row
  # that does not have five cells. The plan transaction, as every plan verb.
  discharge)
    plan_verb_open discharge
    PV_RC=0
    matrix_row_cells "$PV_PLAN" "$DS_AC" 5=CONFIRMED > "$PV_NEW" 2>/dev/null || PV_RC=$?
    case "$PV_RC" in
      0) : ;;
      3) die "REFUSED — the matrix table has no row $DS_AC; the plan is unchanged."
         exit 1 ;;
      4) die "REFUSED — the matrix row $DS_AC does not have five cells, so its auditor cell cannot be found; the plan is unchanged."
         exit 1 ;;
      *) die "REFUSED — the auditor cell cannot be written (awk exit $PV_RC); the plan is unchanged."
         exit 2 ;;
    esac
    plan_verb_swap discharge "$DS_AC's auditor cell CONFIRMED" writer
    say "discharge — $DS_AC: auditor CONFIRMED, written to $PV_PLAN; dry-committed first."
    exit 0
    ;;

  # THE MATRIX ROW'S CELLS AND BLOCK KEYS (wave-33 T7; REQ-4 AC-4.1, D8). Wave-32 moved its matrix by hand:
  # statuses to waived and discharged, evidence to the fix rows' records, multi-row task keys (A-orch-38, 40,
  # 41, 47). `status=` writes the table's status cell; `evidence=` the evidence cell AND the AC block's
  # `evidence:` key, so the table and the block name the same path (research G3); `task=` the block's `task:`
  # key, each id a `## Tasks` row, joined `, `. The tier cell is the plan's, set at Step 3; the auditor cell
  # is discharge's. `status=waived` stands only beside the block's `waiver:` line, which waive-row writes on
  # the user's words. Every key is judged before any is written, and the call is one plan transaction.
  # REFUSED (1), the plan unchanged: a key outside the three, a status outside the gate's four, an evidence
  # path outside record/ or with a `..`, a task id no row carries, an AC with no row, a block key on an AC
  # with no block.
  matrix-set)
    MS_HAS_S=0; MS_HAS_E=0; MS_HAS_T=0; MS_STATUS=""; MS_EV=""; MS_TASK=""
    for _pv_a in "${MS_PAIRS[@]}"; do
      _pv_k="${_pv_a%%=*}"; _pv_v="${_pv_a#*=}"
      if ! plan_verb_value_ok "$_pv_v"; then
        die "REFUSED — the value for $(clean "$_pv_k") carries a |, a tab or a line break, which no matrix cell can hold; the plan is unchanged."
        exit 1
      fi
      case "$_pv_k" in
        status)   MS_HAS_S=1; MS_STATUS="$_pv_v" ;;
        evidence) MS_HAS_E=1; MS_EV="$_pv_v" ;;
        task)     MS_HAS_T=1; MS_TASK="$_pv_v" ;;
        tier)
          die "REFUSED — the tier cell is the plan's, set at Step 3 with the criterion's eval; matrix-set never writes it. The plan is unchanged."
          exit 1 ;;
        auditor)
          die "REFUSED — the auditor cell is discharge's, and it holds the bare token CONFIRMED; the plan is unchanged."
          pv_next discharge "$MS_AC"
          exit 1 ;;
        *)
          die "REFUSED — '$(clean "$_pv_k")' is no key matrix-set writes: status, evidence or task. The plan is unchanged."
          pv_fix_pairs "$(printf 'status\nevidence\ntask\n')" "${MS_PAIRS[@]}"
          [ "${#PV_FIXED[@]}" -eq 0 ] || pv_next matrix-set "$MS_AC" "${PV_FIXED[@]}"
          exit 1 ;;
      esac
    done
    if [ "$MS_HAS_S" = 1 ]; then
      case "$MS_STATUS" in
        pending|blocked|discharged|waived) : ;;
        *)
          die "REFUSED — '$(clean "$MS_STATUS")' is no matrix status; the gate reads pending, blocked, discharged, waived. The plan is unchanged."
          exit 1 ;;
      esac
    fi
    if [ "$MS_HAS_E" = 1 ]; then
      case "$MS_EV" in
        record/?*) : ;;
        *)
          die "REFUSED — the evidence '$(clean "$MS_EV")' is not under record/: a matrix path is docs-root relative, record/<…>. The plan is unchanged."
          case "$MS_EV" in
            */record/?*) pv_fix_pairs "$(printf 'status\nevidence\ntask\n')" "${MS_PAIRS[@]/#evidence=*/evidence=record/${MS_EV#*/record/}}"
                         pv_next matrix-set "$MS_AC" "${PV_FIXED[@]}" ;;
          esac
          exit 1 ;;
      esac
      case "/$MS_EV/" in
        */../*)
          die "REFUSED — the evidence '$(clean "$MS_EV")' has a '..' component; name it under record/. The plan is unchanged."
          exit 1 ;;
      esac
    fi
    plan_verb_open matrix-set
    if [ -z "$(matrix_row_cell "$PV_PLAN" "$MS_AC" 1)" ]; then
      die "REFUSED — the matrix table has no row $MS_AC; the plan is unchanged."
      exit 1
    fi
    if [ "$MS_HAS_T" = 1 ]; then
      MS_ROWS=" $(units_rows "$PV_PLAN" 2>/dev/null | cut -f1 | tr '\n' ' ')"
      MS_IDS=""; MS_MISS=""
      for _pv_i in $(printf '%s' "$MS_TASK" | tr ',' ' '); do
        case "$MS_ROWS" in
          *" $_pv_i "*) MS_IDS="${MS_IDS:+$MS_IDS, }$_pv_i" ;;
          *) MS_MISS="${MS_MISS:+$MS_MISS, }$(clean "$_pv_i")" ;;
        esac
      done
      if [ -n "$MS_MISS" ] || [ -z "$MS_IDS" ]; then
        die "REFUSED — task=$(clean "$MS_TASK") names ${MS_MISS:-no id}, no row of the ## Tasks table; the plan is unchanged."
        exit 1
      fi
    fi
    if [ "$MS_STATUS" = waived ] && ! matrix_block_has "$PV_PLAN" "$MS_AC" waiver; then
      die "REFUSED — $MS_AC has no waiver: line, and a waived row is one the user waived in their own words; waive-row writes both. The plan is unchanged."
      pv_next waive-row "$MS_AC" "<the user's words>" "<why>"
      exit 1
    fi
    cp "$PV_PLAN" "$PV_NEW"
    MS_CELLS=()
    [ "$MS_HAS_S" = 0 ] || MS_CELLS+=("3=$MS_STATUS")
    [ "$MS_HAS_E" = 0 ] || MS_CELLS+=("4=$MS_EV")
    PV_RC=0
    if [ "${#MS_CELLS[@]}" -gt 0 ]; then
      matrix_row_cells "$PV_NEW" "$MS_AC" "${MS_CELLS[@]}" > "$PV_NEW.2" 2>/dev/null || PV_RC=$?
      [ "$PV_RC" -ne 0 ] || mv -f "$PV_NEW.2" "$PV_NEW"
    fi
    if [ "$PV_RC" -eq 0 ] && [ "$MS_HAS_E" = 1 ]; then
      matrix_block_key "$PV_NEW" "$MS_AC" evidence "$MS_EV" > "$PV_NEW.2" 2>/dev/null || PV_RC=$((10 + $?))
      [ "$PV_RC" -ne 0 ] || mv -f "$PV_NEW.2" "$PV_NEW"
    fi
    if [ "$PV_RC" -eq 0 ] && [ "$MS_HAS_T" = 1 ]; then
      matrix_block_key "$PV_NEW" "$MS_AC" task "$MS_IDS" > "$PV_NEW.2" 2>/dev/null || PV_RC=$((10 + $?))
      [ "$PV_RC" -ne 0 ] || mv -f "$PV_NEW.2" "$PV_NEW"
    fi
    case "$PV_RC" in
      0) : ;;
      4) die "REFUSED — the matrix row $MS_AC does not have five cells, so its cells cannot be found; the plan is unchanged."
         exit 1 ;;
      13) die "REFUSED — the matrix has no $MS_AC: block to hold the key; matrix-render writes it. The plan is unchanged."
          pv_next matrix-render
          exit 1 ;;
      *) die "REFUSED — the matrix cannot be written (exit $PV_RC); the plan is unchanged."
         exit 2 ;;
    esac
    plan_verb_swap matrix-set "$MS_AC ${MS_PAIRS[*]}" writer
    say "matrix-set — $MS_AC: ${MS_PAIRS[*]} written to $PV_PLAN; dry-committed first."
    exit 0
    ;;

  # THE ROW WAIVER (wave-33 T7; REQ-4 AC-4.1, D8). Wave-32's four row waivers were typed by hand (A-orch-49):
  # the AC block's `  waiver: <who> <date> "<the user's words>" — <why>` line, which the gate reads as the
  # row's waiver (walls.sh `row_is_waived`), and the status cell `waived`. The words are held to the rule a
  # finding's move is (finding-move): lib/said.sh `user_said` finds them, as whole words and at least SAID_MIN_WORDS (three)
  # of them unless they are a whole prompt, in a prompt the user typed in this session. Who is git
  # user.name, the date UTC. A second waiver of the row replaces the first line. REFUSED (1), the plan
  # unchanged: an AC with no row or no block, no git user.name, words the user did not type, too few words.
  waive-row)
    if ! declare -F user_said >/dev/null 2>&1 && [ -f "$BIONIC_LIB/said.sh" ]; then
      . "$BIONIC_LIB/said.sh"
    fi
    if ! declare -F user_said >/dev/null 2>&1; then
      die "REFUSED — what the user typed is read by lib/said.sh, which cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    WR_WORDS="$(said_fold "$WR_RAW")"; WR_WHY="$(deferral_fold "$WR_WHY_RAW")"
    plan_verb_open waive-row
    if [ -z "$(matrix_row_cell "$PV_PLAN" "$WR_AC" 1)" ]; then
      die "REFUSED — the matrix table has no row $WR_AC; the plan is unchanged."
      exit 1
    fi
    WR_WHO="$(deferral_fold "$(git -C "$PV_REPO" config user.name 2>/dev/null)")"
    if [ -z "$WR_WHO" ]; then
      die "REFUSED — no git user.name is set for $PV_REPO, and a waiver records who made it; set it, then waive again. The plan is unchanged."
      exit 1
    fi
    user_said "$WR_RAW" "$PV_PLAN"; WR_SAID=$?
    if [ "$WR_SAID" -ne 0 ]; then
      said_refuse "$WR_SAID" "$WR_WORDS" "a waiver"
      exit 1
    fi
    WR_LINE="$WR_WHO $(date -u +%Y-%m-%d) \"$(deferral_escape "$WR_WORDS")\" — $WR_WHY"
    PV_RC=0
    matrix_row_cells "$PV_PLAN" "$WR_AC" 3=waived > "$PV_NEW" 2>/dev/null || PV_RC=$?
    if [ "$PV_RC" -eq 0 ]; then
      matrix_block_key "$PV_NEW" "$WR_AC" waiver "$WR_LINE" > "$PV_NEW.2" 2>/dev/null || PV_RC=$((10 + $?))
      [ "$PV_RC" -ne 0 ] || mv -f "$PV_NEW.2" "$PV_NEW"
    fi
    case "$PV_RC" in
      0) : ;;
      4) die "REFUSED — the matrix row $WR_AC does not have five cells, so its status cannot be found; the plan is unchanged."
         exit 1 ;;
      13) die "REFUSED — the matrix has no $WR_AC: block to hold the waiver; matrix-render writes it. The plan is unchanged."
          pv_next matrix-render
          exit 1 ;;
      *) die "REFUSED — the waiver cannot be written (exit $PV_RC); the plan is unchanged."
         exit 2 ;;
    esac
    plan_verb_swap waive-row "the waiver of $WR_AC" writer
    poker_owed_close "$PV_REPO" "waive-row:$WR_AC" "waive-row"
    say "waive-row — $WR_AC waived on the user's words, by $(clean "$WR_WHO"): its waiver: line and status are on $PV_PLAN; dry-committed first."
    exit 0
    ;;

  # A PROSE PARAGRAPH UNDER ## Tasks (wave-33 T7; REQ-4 AC-4.1, D8). Wave-32's shard-table paragraph was copied
  # in and rewritten by hand (A-orch-24, 25). The paragraph is one line, written after the section's last
  # paragraph below the table (after the table, a blank line between); `--replace '<first words>'` rewrites
  # the one paragraph whose first line opens with those words, in place. A paragraph that is already there is
  # nothing to write. REFUSED (1), the plan unchanged: a line break, a text that opens with | or # (a table
  # row or a heading), no table under ## Tasks, --replace naming no paragraph or more than one.
  tasks-prose)
    case "$TP_TEXT" in
      *$'\n'*|*$'\r'*)
        die "REFUSED — a paragraph here is one line, and the text carries a line break; the plan is unchanged."
        exit 1 ;;
    esac
    TP_TEXT="$(printf '%s' "$TP_TEXT" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    TP_REPLACE="$(printf '%s' "$TP_REPLACE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    case "$TP_TEXT" in
      '|'*|'#'*)
        die "REFUSED — a paragraph that opens with | or # reads as a table row or a heading; the plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open tasks-prose
    PV_RC=0
    TP_TEXT="$TP_TEXT" TP_REPLACE="$TP_REPLACE" TP_HASREP="$TP_HASREP" TP_LIST="$PV_NEW.2" awk '
      BEGIN { text = ENVIRON["TP_TEXT"]; rep = ENVIRON["TP_REPLACE"]; hasrep = (ENVIRON["TP_HASREP"] == 1); list = ENVIRON["TP_LIST"] }
      { L[++nl] = $0 }
      END {
        for (i = 1; i <= nl; i++) {
          x = L[i]
          if (x ~ /^[ \t]*```/) fence = !fence
          if (!fence && x ~ /^##[ \t]/) { if (st) break; if (x ~ /^##[ \t]+Tasks([ \t].*)?$/) st = 1; continue }
          if (st == 1) { if (x ~ /^[ \t]*\|/) { st = 2; tend = i }; continue }
          if (st == 2) { if (x ~ /^[ \t]*\|/) { tend = i; continue }; st = 3; last = tend }
          if (st == 3) {
            if (x ~ /[^ \t]/) { last = i; if (!inp) { np++; ps[np] = i; inp = 1 }; pe[np] = i } else inp = 0
          }
        }
        if (!tend) exit 4
        if (st == 2) last = tend
        if (hasrep) {
          for (p = 1; p <= np; p++) { y = L[ps[p]]; sub(/^[ \t]+/, "", y); if (index(y, rep) == 1) { hit++; hp = p } }
          if (hit != 1) { for (p = 1; p <= np; p++) print L[ps[p]] > list; exit (hit ? 5 : 3) }
          for (i = 1; i <= nl; i++) {
            if (i == ps[hp]) { print text; continue }
            if (i > ps[hp] && i <= pe[hp]) continue
            print L[i]
          }
          exit 0
        }
        for (p = 1; p <= np; p++) if (ps[p] == pe[p] && L[ps[p]] == text) same = 1
        for (i = 1; i <= nl; i++) {
          print L[i]
          if (!same && i == last) { print ""; print text; if (i < nl && L[i + 1] ~ /[^ \t]/) print "" }
        }
      }' "$PV_PLAN" > "$PV_NEW" 2>/dev/null || PV_RC=$?
    case "$PV_RC" in
      0) : ;;
      4) die "REFUSED — the plan has no table under ## Tasks for the paragraph to follow; the plan is unchanged."
         exit 1 ;;
      3|5)
         if [ "$PV_RC" = 3 ]; then
           die "REFUSED — no paragraph under ## Tasks opens with '$(clean "$TP_REPLACE")'; the plan is unchanged."
         else
           die "REFUSED — more than one paragraph under ## Tasks opens with '$(clean "$TP_REPLACE")'; name more of its first words. The plan is unchanged."
         fi
         if [ -s "$PV_NEW.2" ]; then
           while IFS= read -r TP_P; do
             pv_next tasks-prose "$TP_TEXT" --replace "$(printf '%s' "$TP_P" | awk '{ print $1, $2, $3 }' | sed 's/[[:space:]]*$//')"
           done < "$PV_NEW.2"
         else
           pv_next tasks-prose "$TP_TEXT"
         fi
         exit 1 ;;
      *) die "REFUSED — the paragraph cannot be written (awk exit $PV_RC); the plan is unchanged."
         exit 2 ;;
    esac
    plan_verb_swap tasks-prose "the paragraph under ## Tasks" writer
    say "tasks-prose — the paragraph under ## Tasks: written to $PV_PLAN${TP_REPLACE:+ (replacing the one opening '$TP_REPLACE')}; dry-committed first."
    exit 0
    ;;

  # THE EPIC'S SHIPPED ROW (wave-33 T7; REQ-3 AC-3.3, D8). close-out.sh writes the row whole when it appends
  # it and never edits a row that is there (`act_epic`), so a `<fill: ADRs>` it left (wave-30's) could be
  # filled by no code. This verb sets cells of the row whose wave cell is <wave>, in the shipped table
  # close-out finds (the table whose header opens `wave` and carries `shipped`) of the `epic.plan.md` beside
  # the run's plan. A column is named by its header cell or that cell's first word, case-blind (`ADRs`,
  # `plan`, `spec`). The file transaction (`pv_file_open`, `pv_file_swap`). REFUSED (1), the file unchanged:
  # no epic plan, no shipped table, a column it does not carry (the columns listed, the corrected call
  # printed), the wave cell, a value with a |, a line break or a fill mark, no row for the wave.
  epic-row)
    pv_file_open epic-row "$EP_WAVE" "${EP_PAIRS[@]}"
    EP_FILE="${PV_RPLAN%/*}/epic.plan.md"
    if [ ! -f "$EP_FILE" ] || [ -L "$EP_FILE" ]; then
      die "REFUSED — no epic.plan.md beside $PV_RPLAN (or it is a link); nothing was written."
      exit 1
    fi
    EP_AWK='
      function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
      function shipped_header(line,   n, a, i) {
        n = split(line, a, "|")
        if (tolower(trim(a[2])) != "wave") return 0
        for (i = 3; i <= n; i++) if (tolower(trim(a[i])) == "shipped") return 1
        return 0
      }
      BEGIN {
        mode = ENVIRON["EP_MODE"]; w = ENVIRON["EP_WAVE"] + 0; m = split(ENVIRON["EP_SET"], s, "\n")
        for (k = 1; k <= m; k++) if ((t = index(s[k], "\t")) > 0) v[substr(s[k], 1, t - 1) + 1] = " " substr(s[k], t + 1) " "
      }
      /^[ \t]*```/ { fence = !fence; if (mode == "set") print; next }
      fence { if (mode == "set") print; next }
      !seen && /^\|/ && shipped_header($0) {
        intable = 1; seen = 1
        if (mode == "head") { n = split($0, a, "|"); for (i = 2; i < n; i++) print trim(a[i]); exit }
        print; next
      }
      intable && !/^\|/ { intable = 0 }
      intable && mode == "set" {
        n = split($0, c, "|"); x = trim(c[2])
        if (x ~ /^[0-9]+$/ && x + 0 == w) {
          hits++
          if (hits == 1) { for (j in v) c[j] = v[j]; out = c[1]; for (j = 2; j <= n; j++) out = out "|" c[j]; print out; next }
        }
      }
      mode == "set" { print }
      END { if (mode == "set") { if (!seen) exit 3; if (!hits) exit 4; if (hits > 1) exit 5 } }'
    EP_COLS="$(EP_MODE=head awk "$EP_AWK" "$EP_FILE" 2>/dev/null)"
    if [ -z "$EP_COLS" ]; then
      die "REFUSED — $EP_FILE carries no shipped table (a header whose first cell is wave and which has a shipped cell); nothing was written."
      exit 1
    fi
    EP_SET=""; EP_BAD=""; EP_FIRST=""
    for _pv_a in "${EP_PAIRS[@]}"; do
      _pv_k="${_pv_a%%=*}"; _pv_v="${_pv_a#*=}"
      _pv_f="$(pv_fold "$_pv_k")"; _pv_n=0; _pv_at=""
      while IFS= read -r _pv_c; do
        _pv_n=$((_pv_n + 1))
        if [ "$(pv_fold "$_pv_c")" = "$_pv_f" ] || [ "$(pv_fold "${_pv_c%% *}")" = "$_pv_f" ]; then _pv_at="$_pv_n"; break; fi
      done <<< "$EP_COLS"
      if [ -z "$_pv_at" ]; then EP_BAD="${EP_BAD:+$EP_BAD, }$(clean "$_pv_k")"; continue; fi
      if [ "$_pv_at" = 1 ]; then
        die "REFUSED — the wave cell is the key epic-row finds the row by, not a cell to set; nothing was written."
        exit 1
      fi
      if ! plan_verb_value_ok "$_pv_v"; then
        die "REFUSED — the value for $(clean "$_pv_k") carries a |, a tab or a line break, which no table cell can hold; nothing was written."
        exit 1
      fi
      case "$_pv_v" in
        *'<fill:'*)
          die "REFUSED — the value for $(clean "$_pv_k") is itself a fill mark; write the fact. Nothing was written."
          exit 1 ;;
      esac
      EP_SET="${EP_SET}${_pv_at}	${_pv_v}
"
    done
    if [ -n "$EP_BAD" ]; then
      die "REFUSED — the shipped table of $EP_FILE carries no column $EP_BAD; nothing was written."
      die "The columns: $(printf '%s\n' "$EP_COLS" | paste -sd, - | sed 's/,/, /g')."
      pv_fix_pairs "$(printf '%s\n' "$EP_COLS" | sed 's/ .*//')" "${EP_PAIRS[@]}"
      if [ "${#PV_FIXED[@]}" -gt 0 ]; then
        if [ -n "$PV_PLAN_ARG" ]; then pv_next epic-row "$EP_WAVE" "${PV_FIXED[@]}" --plan "$PV_PLAN_ARG"
        else pv_next epic-row "$EP_WAVE" "${PV_FIXED[@]}"; fi
      fi
      exit 1
    fi
    EP_SUM="$(cksum < "$EP_FILE" 2>/dev/null)"
    PV_NEW="$EP_FILE.epic-row.$$"
    PV_RC=0
    EP_MODE=set EP_WAVE="$EP_WAVE" EP_SET="$EP_SET" awk "$EP_AWK" "$EP_FILE" > "$PV_NEW" 2>/dev/null || PV_RC=$?
    case "$PV_RC" in
      0) : ;;
      4) die "REFUSED — the shipped table of $EP_FILE has no row for wave $EP_WAVE; close-out appends it. Nothing was written."
         exit 1 ;;
      5) die "REFUSED — the shipped table of $EP_FILE has more than one row for wave $EP_WAVE; which one is meant is not the verb's to guess. Nothing was written."
         exit 1 ;;
      *) die "REFUSED — the row cannot be written (awk exit $PV_RC); nothing was written."
         exit 2 ;;
    esac
    pv_file_swap epic-row "$EP_FILE" "$EP_SUM" "wave $EP_WAVE's row"
    EP_LEFT="$(awk -v w="$EP_WAVE" -F'|' '{ x = $2; gsub(/^[ \t]+|[ \t]+$/, "", x) } x ~ /^[0-9]+$/ && x + 0 == w + 0 && /<fill:/ { n++ } END { print n + 0 }' "$EP_FILE")"
    say "epic-row — wave $EP_WAVE: ${EP_PAIRS[*]} written to $EP_FILE; fill marks left in the row: $EP_LEFT."
    exit 0
    ;;

  # THE CONTINUATION'S FILL MARKS (wave-33 T7; REQ-3 AC-3.3, D8). close-out.sh writes the run's continuation
  # (`record/<run>/continuation.md`, under the docs root its plan sits in) with a `<fill: …>` mark wherever
  # only the orchestrator knows the fact; wave-32 completed its marks by hand (A-orch-50). This verb replaces
  # the mark whose label is <field>, or opens with it before a character that is no letter or digit
  # (`the first decision` for `<fill: the first decision, or "none">`); every copy of that mark is filled,
  # and the marks left are counted. The text may span lines. The file transaction. REFUSED (1), the file
  # unchanged: no continuation, a field naming no mark or more than one (the fields left listed), a text
  # that is itself a fill mark.
  continuation-fill)
    pv_file_open continuation-fill "$CF_FIELD=$CF_TEXT"
    CF_DOCS="$(docs_root "$PV_REPO")"
    case "$PV_RPLAN" in */plans/*) CF_DOCS="${PV_RPLAN%/plans/*}" ;; esac
    CF_SLUG="$(proof_plan_slug "$PV_RPLAN")"
    CF_FILE="$CF_DOCS/record/$CF_SLUG/continuation.md"
    if [ ! -f "$CF_FILE" ] || [ -L "$CF_FILE" ]; then
      die "REFUSED — no continuation at $CF_FILE (close-out writes it at close); nothing was written."
      exit 1
    fi
    case "$CF_TEXT" in
      *'<fill:'*)
        die "REFUSED — the text is itself a fill mark; write the fact. Nothing was written."
        exit 1 ;;
    esac
    CF_SUM="$(cksum < "$CF_FILE" 2>/dev/null)"
    PV_NEW="$CF_FILE.continuation-fill.$$"
    PV_RC=0
    CF_FIELD="$CF_FIELD" CF_TEXT="$CF_TEXT" CF_LIST="$PV_NEW.2" awk '
      BEGIN { f = ENVIRON["CF_FIELD"]; text = ENVIRON["CF_TEXT"]; list = ENVIRON["CF_LIST"] }
      { L[++nl] = $0 }
      END {
        for (i = 1; i <= nl; i++) {
          x = L[i]
          while ((p = index(x, "<fill: ")) > 0) {
            x = substr(x, p + 7); q = index(x, ">"); if (!q) break
            lab = substr(x, 1, q - 1); x = substr(x, q + 1)
            if (!(lab in seen)) { seen[lab] = 1; labs[++nlab] = lab }
          }
        }
        for (k = 1; k <= nlab; k++) if (labs[k] == f) { exact = labs[k] }
        if (exact != "") { hit = exact; nhit = 1 }
        else for (k = 1; k <= nlab; k++) {
          lab = labs[k]
          if (index(lab, f) == 1 && substr(lab, length(f) + 1, 1) !~ /[A-Za-z0-9]/) { nhit++; hit = lab }
        }
        if (nhit != 1) { for (k = 1; k <= nlab; k++) print labs[k] > list; exit (nhit ? 5 : 3) }
        mark = "<fill: " hit ">"
        for (i = 1; i <= nl; i++) {
          x = L[i]; out = ""
          while ((p = index(x, mark)) > 0) { out = out substr(x, 1, p - 1) text; x = substr(x, p + length(mark)) }
          print out x
        }
        print hit > list
      }' "$CF_FILE" > "$PV_NEW" 2>/dev/null || PV_RC=$?
    case "$PV_RC" in
      0) : ;;
      3|5)
         if [ "$PV_RC" = 3 ]; then die "REFUSED — no fill mark of $CF_FILE is named '$(clean "$CF_FIELD")'; nothing was written."
         else die "REFUSED — more than one fill mark of $CF_FILE opens with '$(clean "$CF_FIELD")'; name more of it. Nothing was written."; fi
         if [ -s "$PV_NEW.2" ]; then die "The fields left: $(paste -sd'|' - < "$PV_NEW.2" | sed 's/|/; /g')."
         else die "The continuation carries no fill mark."; fi
         exit 1 ;;
      *) die "REFUSED — the mark cannot be filled (awk exit $PV_RC); nothing was written."
         exit 2 ;;
    esac
    CF_HIT="$(cat "$PV_NEW.2" 2>/dev/null)"
    pv_file_swap continuation-fill "$CF_FILE" "$CF_SUM" "the mark <fill: $CF_HIT>"
    CF_LEFT="$(/usr/bin/grep -o '<fill:' "$CF_FILE" | wc -l | tr -d ' ')"
    CF_W=marks; [ "$CF_LEFT" = 1 ] && CF_W=mark
    say "continuation-fill — <fill: $(clean "$CF_HIT")> filled in $CF_FILE; $CF_LEFT fill $CF_W left."
    exit 0
    ;;

  # THE HANDOFF (wave-30 T15; REQ-7 AC-7.2, D11). A plan that spans sessions carries `## Handoff`, and this verb is its
  # one writer: the section is rewritten in place (between its heading and the next `## `; created before `## Not
  # Doing` when the plan has none) from five facts the machine holds, and never typed. Its first line is
  # `written: <date -u>`. Then, one bullet each: the HEADS of the plan's working and integration branches (git, in
  # the checkout the plan is bound in); the OPEN ROWS, every `## Tasks` row that is active or pending with a
  # worktree (the cells `units_rows` reads: id, agent, worktree, status) and the newest `landed` line of
  # `## SDLC State` by its time; the LIVE AGENTS, the open rows of this session's roster (`roster_open_names`, the
  # close predicate of every other reader) each with the run state the tick prints (`run_state_words`: RUNNING pid=
  # elapsed=, FINISHED rc=, LOST, or `no run`), read by the tick's own readers; and the LAST PROOF, the newest
  # `proved:` line (kind, head, at) or `none yet`. The five lines only a person can know (decisions approved this
  # session, tried and rejected, surprises, open blockers, resume instruction) are CARRIED: each is copied verbatim,
  # with its indented continuation lines, from the section it replaces, and is a stub `(to fill)` where it had none.
  # Every other line of the old section is replaced: the machine lines are rewritten, not appended.
  # It takes the plan transaction every plan verb takes (copy, dry commit through the real gate, checksum, swap).
  # REFUSED (1), the plan unchanged: no `## Tasks`, no `## SDLC State`.
  handoff)
    plan_verb_open handoff
    if ! /usr/bin/grep -qE '^##[[:space:]]+Tasks([[:space:]]|$)' "$PV_PLAN"; then
      die "REFUSED — the plan has no ## Tasks section, so there are no open rows to hand off; the plan is unchanged."
      exit 1
    fi
    if ! /usr/bin/grep -qE '^##[[:space:]]+SDLC State([[:space:]]|$)' "$PV_PLAN"; then
      die "REFUSED — the plan has no ## SDLC State section, so there is no landing or proof to hand off; the plan is unchanged."
      exit 1
    fi
    if ! { declare -F proof_awk >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_awk >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    HO_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    HO_WB="$(plan_working_branch "$PV_PLAN")"
    HO_IB="$(plan_frontmatter_get "$PV_PLAN" integration-branch)"
    [ -n "$HO_IB" ] || HO_IB="$(awk '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && /^[[:space:]]*integration-branch[[:space:]]*:/ { v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); sub(/[[:space:]].*$/, "", v); print v; exit }' "$PV_PLAN")"
    HO_HEADS=""
    for HO_B in "$HO_WB" "$HO_IB"; do
      HO_H=""
      [ -z "$HO_B" ] || HO_H="$(git -C "$PV_REPO" rev-parse --verify -q "refs/heads/$HO_B^{commit}" 2>/dev/null)" || HO_H=""
      HO_HEADS="${HO_HEADS:+$HO_HEADS · }$([ -n "$HO_B" ] && printf '%s' "$(clean "$HO_B")" || printf '(none named)') @ ${HO_H:-(no such branch)}"
    done
    HO_ROWS="$(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' '
      { st = $10; wt = $11; ag = $5
        if (ag == "") ag = "—"
        has = (wt != "" && wt != "—" && wt != "-")
        if (st == "active" || (st == "pending" && has)) print $1 " · " ag " · " (has ? wt : "—") " · " st }')"
    HO_N_ROWS=0; [ -z "$HO_ROWS" ] || HO_N_ROWS="$(printf '%s\n' "$HO_ROWS" | wc -l | tr -d ' ')"
    HO_LANDED="$(awk '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && /^- T[0-9]+:/ && match($0, /landed [0-9a-f]+ [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z/) {
        split(substr($0, RSTART, RLENGTH), f, " "); id = $2; sub(/:$/, "", id)
        if (length(f[2]) >= 7 && (best == "" || f[3] >= bat)) { best = id " " f[2] " " f[3]; bat = f[3] } }
      END { print best }' "$PV_PLAN")"
    HO_PROOF="$(awk "$(proof_awk)"'
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && proof_fields($0) {
        at = ""; if (match($0, /[ \t]at=[^ \t]+/)) at = substr($0, RSTART + 4, RLENGTH - 4)
        last = "kind=" PROOF_KIND " head=" PROOF_HEAD (at != "" ? " at=" at : "") }
      END { print last }' "$PV_PLAN")"
    HO_RF="$PV_REPO/.bionic/tmp/roster-$(session_id).state"
    # THE LIVE AGENTS ARE THE HARNESS'S, NOT THE ROSTER'S (wave-34 T6; REQ-14 AC-14.2, D23). The roster
    # records that a dispatch happened, never that an agent is alive, and reading its open rows listed two
    # researchers as live after TaskStop (field report 2026-10-11, item 2). So the list is the newest
    # ListAgents answer in this session's transcript (lib/agents.sh, the one parser of it): every agent it
    # names that is not `idle` — the one word the harness uses for "finished its turn", the rule
    # `live_row_open` keeps — less every agent a TaskStop after the answer ended. An answer a later
    # dispatch outdates, a stale one, or none at all cannot say who is live: the roster's open rows are
    # listed in its place, marked UNVERIFIED, and nothing reads as safe.
    HO_TR="$(session_transcript "$(session_id)")" || HO_TR=""
    HO_LRC=4; HO_SET=""; HO_SINCE=""
    if [ -n "$HO_TR" ]; then
      _la_ensure "$HO_TR" 2>/dev/null; HO_LRC=$?
      HO_SET="$_LA_CACHE_OUT"
      [ "$HO_LRC" -ne 0 ] || HO_SINCE="$(live_agents_since_answer "$HO_TR" 2>/dev/null)"
    fi
    HO_WHY=""
    case "$HO_LRC" in
      0) HO_DISP="$(printf '%s\n' "$HO_SINCE" | awk -F'\t' '$1 == "dispatched" { print $2; exit }')"
         [ -z "$HO_DISP" ] || HO_WHY="a dispatch at $HO_DISP postdates the newest ListAgents answer" ;;
      3) HO_WHY="the newest ListAgents answer predates the last prompt" ;;
      *) HO_WHY="no ListAgents answer in this session's transcript" ;;
    esac
    if [ -z "$HO_WHY" ]; then
      HO_NAMES="$(printf '%s\n' "$HO_SET" | HO_GONE="$(printf '%s\n' "$HO_SINCE" | awk -F'\t' '$1 == "stopped" { print $2 }')" \
        awk -F'|' -v idle="$_LA_ROW_CLOSED_STATUS" '
          BEGIN { n = split(ENVIRON["HO_GONE"], g, "\n"); for (i = 1; i <= n; i++) if (g[i] != "") gone[g[i]] = 1 }
          $1 != "" && $3 != idle && !($1 in gone) && !($1 in seen) { seen[$1] = 1; print $1 }')"
    else
      HO_NAMES="$(roster_open_names "$HO_RF" "$PV_REPO/.bionic/tmp/sweeper-$(session_id).state" "$(session_id)")"
    fi
    HO_AGENTS=""; HO_N_AG=0; HO_LIST=""
    while IFS= read -r HO_NAME; do
      [ -n "$HO_NAME" ] || continue
      HO_ST="no run"
      if run_load_row "$(run_row_of "$HO_RF" "$HO_NAME")" "$HO_RF"; then run_read; HO_ST="$(run_state_words)"; fi
      HO_AGENTS="${HO_AGENTS:+$HO_AGENTS
}  - $(clean "$HO_NAME") · $HO_ST"
      HO_LIST="${HO_LIST:+$HO_LIST, }$(clean "$HO_NAME")"
      HO_N_AG=$((HO_N_AG + 1))
    done <<< "$HO_NAMES"
    # THE TWO SAFETY LINES. Exiting ends every live agent; a `/clear` does not — the agents live on into
    # the new session — but it SIGKILLs the shell command a writer is running (exit 137), so it is the
    # weaker line and is safe only between commands. Unverified is never safe.
    HO_QUAL=""
    if [ -n "$HO_WHY" ]; then
      HO_QUAL=", UNVERIFIED — the roster's open rows, which may include stopped agents"
      HO_EXIT="no — unverified: $HO_WHY; run ListAgents, then handoff again"
      HO_CLEAR="no — unverified, for the same reason"
    elif [ "$HO_N_AG" -gt 0 ]; then
      HO_EXIT="no — $HO_N_AG writer(s) live: $HO_LIST — exiting ends them"
      HO_CLEAR="only between commands — a /clear kills the shell command a live writer is running (exit 137); the writers live on into the new session"
    else
      HO_EXIT="yes — the harness lists no writer live"
      HO_CLEAR="yes"
    fi
    HO_BLOCK="written: $HO_NOW
- heads: $HO_HEADS
- open rows ($HO_N_ROWS):"
    if [ -n "$HO_ROWS" ]; then HO_BLOCK="$HO_BLOCK
$(printf '%s\n' "$HO_ROWS" | sed 's/^/  - /')"; fi
    HO_BLOCK="$HO_BLOCK
- last landed: ${HO_LANDED:-none yet}
- live agents ($HO_N_AG)$HO_QUAL:"
    if [ -n "$HO_AGENTS" ]; then HO_BLOCK="$HO_BLOCK
$HO_AGENTS"; fi
    HO_BLOCK="$HO_BLOCK
- safe to exit: $HO_EXIT
- safe to /clear: $HO_CLEAR
- last proof: ${HO_PROOF:-none yet}"
    PV_RC=0
    HO_BLOCK="$HO_BLOCK" awk '
      function carry_one(key,   j, l, t, found) {
        found = 0
        for (j = 1; j <= n; j++) {
          l = old[j]
          if (found) { if (l ~ /^[ \t]+[^ \t]/) { print l; continue } break }
          if (ofence[j]) continue
          t = l; sub(/^[ \t]*([-*][ \t]+)?/, "", t)
          if (index(t, key ":") == 1) { found = 1; print l }
        }
        if (!found) print "- " key ": (to fill)"
      }
      function emit(   i) {
        print ""; print ENVIRON["HO_BLOCK"]
        for (i = 1; i <= nk; i++) carry_one(K[i])
        print ""
      }
      BEGIN { nk = split("decisions approved this session|tried and rejected|surprises|open blockers|resume instruction", K, "|") }
      FNR == NR {
        if ($0 ~ /^[ \t]*```/) { f1 = !f1; next }
        if (f1) next
        if ($0 ~ /^##[ \t]+Handoff[ \t]*$/) have = 1
        if ($0 ~ /^##[ \t]+Not Doing/) nd = 1
        next
      }
      {
        isfence = ($0 ~ /^[ \t]*```/)
        if (inho) {
          if (!isfence && !fence && $0 ~ /^##[ \t]/) { emit(); inho = 0 }
          else { n++; old[n] = $0; ofence[n] = (isfence || fence); if (isfence) fence = !fence; next }
        }
        if (isfence) { fence = !fence; print; next }
        if (fence) { print; next }
        if ($0 ~ /^##[ \t]+Handoff[ \t]*$/ && !wrote) { print; inho = 1; wrote = 1; n = 0; next }
        if (!have && !wrote && ((nd && $0 ~ /^##[ \t]+Not Doing/) || (!nd && $0 ~ /^##[ \t]+SDLC State/))) {
          print "## Handoff"; emit(); wrote = 1
        }
        print
      }
      END { if (inho) emit() }' "$PV_PLAN" "$PV_PLAN" > "$PV_NEW" 2>/dev/null || PV_RC=$?
    if [ "$PV_RC" -ne 0 ]; then
      die "REFUSED — the handoff cannot be written (awk exit $PV_RC); the plan is unchanged."
      exit 2
    fi
    plan_verb_swap handoff "the handoff rewritten at $HO_NOW" writer
    say "handoff — ## Handoff rewritten at $HO_NOW ($HO_N_ROWS open rows, $HO_N_AG live agents); written to $PV_PLAN, dry-committed first."
    exit 0
    ;;

  # THE BRIEF, RENDERED FROM ITS ROW (wave-33 T9; REQ-4 AC-4.4, D8). The rules are written above the helpers
  # (`poker_brief_cell`). It reads the bound plan and writes one file under record/<wave>/briefs/, so it takes
  # no plan transaction: the plan is never changed. REFUSED (1), nothing written: an id that is no row id, a
  # plan with no ## Tasks table, a row the table does not have (the refusal names the rows and a corrected
  # call), a row the table carries twice. REFUSED (2): the shipped scaffold or lib/proof.sh cannot be read.
  # A row the table fills badly is not a refusal: its slot is written as `<ORCHESTRATOR: …>`, which the dispatch
  # wall reads as an unfilled slot and marks, so a brief typed over it is the only way past.
  brief)
    plan_verb_open brief
    if ! plan_verb_id_ok "$BRF_ID"; then
      die "REFUSED — '$(clean "$BRF_ID")' is not one row id: an id is one token of letters, digits, '.', '_' or '-', beginning with a letter or a digit. Nothing was written."
      exit 1
    fi
    BRF_ROWS="$(units_rows "$PV_PLAN" 2>/dev/null)" || BRF_ROWS=""
    if [ -z "$BRF_ROWS" ]; then
      die "REFUSED — $PV_PLAN carries no ## Tasks table with a row, so there is nothing to render. Nothing was written."
      exit 1
    fi
    BRF_ROW="$(printf '%s\n' "$BRF_ROWS" | awk -F'\t' -v id="$BRF_ID" '$1 == id')"
    BRF_N=0; [ -z "$BRF_ROW" ] || BRF_N="$(printf '%s\n' "$BRF_ROW" | wc -l | tr -d ' ')"
    if [ "$BRF_N" -ne 1 ]; then
      BRF_IDS="$(printf '%s\n' "$BRF_ROWS" | awk -F'\t' '{ printf "%s%s", (n++ ? ", " : ""), $1 }')"
      BRF_EG="$(printf '%s\n' "$BRF_ROWS" | awk -F'\t' '$10 == "pending" { print $1; exit }')"
      [ -n "$BRF_EG" ] || BRF_EG="$(printf '%s\n' "$BRF_ROWS" | awk -F'\t' 'NR == 1 { print $1 }')"
      if [ "$BRF_N" -eq 0 ]; then
        die "REFUSED — the plan has no row $(clean "$BRF_ID"). Its rows: $BRF_IDS. Write: bash ${HOOK_DIR}/session-poker.sh brief $BRF_EG. Nothing was written."
      else
        die "REFUSED — the ## Tasks table carries the row $BRF_ID $BRF_N times; which one is meant is not the verb's to guess. Nothing was written."
      fi
      exit 1
    fi
    BRF_LABELS="$(poker_brief_labels)" || BRF_LABELS=""
    if [ -z "$BRF_LABELS" ]; then
      die "REFUSED — the shipped scaffold cannot be read (${HOOK_DIR}/../skills/canonical-sdlc/dispatch.md, its ### Scaffold fence); a brief is rendered from it, never from a copy. Nothing was written."
      exit 2
    fi
    BRF_TASK="$(units_field "$BRF_ROW" task)"
    BRF_KIND="$(units_field "$BRF_ROW" kind)"
    BRF_STEP="$(units_field "$BRF_ROW" step)"
    BRF_SIZE="$(units_field "$BRF_ROW" size)"
    BRF_FILES="$(units_field "$BRF_ROW" Files)"
    BRF_STATUS="$(units_field "$BRF_ROW" status)"
    BRF_SERVES="$(units_field "$BRF_ROW" serves)"
    BRF_DEPS="$(units_field "$BRF_ROW" deps)"
    BRF_WAVE="$(proof_plan_slug "$PV_PLAN")"
    BRF_DOCS="$(docs_root "$PV_REPO")"
    BRF_RECDIR="$BRF_DOCS/record/$BRF_WAVE"
    case "$BRF_RECDIR" in "$PV_REPO"/*) BRF_RECREL="${BRF_RECDIR#"$PV_REPO"/}" ;; *) BRF_RECREL="$BRF_RECDIR" ;; esac
    BRF_OUT="$BRF_RECDIR/briefs/$BRF_ID.md"

    # THE ARTIFACT (wave-37 T6; REQ-7 AC-7.1; D10): the row's own `artifact` Tasks cell, the ledger's cell for the
    # row, the Files entry named for the row, the first record entry, then the record the task names. One path or nothing.
    BRF_ART=""
    BRF_ACELL="$(poker_brief_cell "$PV_PLAN" Tasks "$BRF_ID" artifact)" || BRF_ACELL=""
    if ! poker_brief_none "$BRF_ACELL"; then
      case "$BRF_ACELL" in *[[:space:],]*) : ;; *) BRF_ART="$BRF_ACELL" ;; esac
    fi
    BRF_LEDGER="$(poker_brief_cell "$PV_PLAN" "Dispatch ledger" "$BRF_ID" artifact)" || BRF_LEDGER=""
    if [ -z "$BRF_ART" ] && ! poker_brief_none "$BRF_LEDGER"; then
      case "$BRF_LEDGER" in *[[:space:],]*) : ;; *) BRF_ART="$BRF_LEDGER" ;; esac
    fi
    [ -n "$BRF_ART" ] || BRF_ART="$(poker_brief_record_entry "$BRF_FILES" artifact "$BRF_ID")"
    [ -n "$BRF_ART" ] || BRF_ART="$(poker_brief_task_record "$BRF_TASK")"
    # A READER ROW'S ARTIFACT IS ITS RECORD (wave-35 T8; REQ-6 AC-6.1; D15): a verify, test or review row that
    # names none writes <record dir>/<row>.md, the progress artifact's convention, and its Files line carries it.
    BRF_FILES_LINE="$BRF_FILES"
    if [ -z "$BRF_ART" ] && poker_reader_kind "$BRF_KIND"; then
      BRF_ART="$BRF_RECREL/$BRF_ID.md"
      if poker_brief_none "$BRF_FILES"; then BRF_FILES_LINE="$BRF_ART"; else BRF_FILES_LINE="$BRF_FILES, $BRF_ART"; fi
    fi

    # THE HEAD: the working branch's own tip, or what is missing, in words. Never a guess.
    BRF_WB="$(plan_working_branch "$PV_PLAN")"; BRF_SHA=""
    if [ -z "$BRF_WB" ]; then
      BRF_HEAD="(the plan names no working branch)"
    else
      BRF_SHA="$(git -C "$PV_REPO" rev-parse --verify -q "refs/heads/$BRF_WB^{commit}" 2>/dev/null)" || BRF_SHA=""
      if [ -n "$BRF_SHA" ]; then BRF_HEAD="$BRF_SHA ($(clean "$BRF_WB"))"; else BRF_HEAD="(no branch $(clean "$BRF_WB") in this repository)"; fi
    fi

    # THE SUITES AND WHAT THE ROW LANDS ON: its own cells when it has them, else its Files' *.test.sh entries, in
    # order, and then (a row whose Files write the head) every further suite that reads those files at the working
    # head (wave-35 T8; wave-36 T27, REQ-6 AC-6.1, D12: the reads index, the fact the dispatch wall holds Lands-on:
    # to), sorted, once each; else the slot: `none` is a waiver nobody chose for a row that writes code.
    BRF_SUITES="$(poker_brief_cell "$PV_PLAN" Tasks "$BRF_ID" suites)" || BRF_SUITES=""
    BRF_SUITE_SLOT=""
    if poker_brief_none "$BRF_SUITES"; then
      BRF_SUITES="$(poker_brief_suites "$BRF_FILES")"
      if units_writes_head "$BRF_FILES"; then
        BRF_IDX="$(poker_brief_index_suites "$PV_REPO" "${BRF_SHA:--}" "$BRF_FILES")"
        BRF_SUITES="$(printf '%s\n%s\n' "$BRF_SUITES" "$BRF_IDX" | awk '{
          n = split($0, s, /[ \t]*,[ \t]*/)
          for (i = 1; i <= n; i++) if (s[i] != "" && !(s[i] in seen)) { seen[s[i]] = 1; o = o (o == "" ? "" : ", ") s[i] } }
          END { printf "%s", o }')"
        [ -n "$BRF_SUITES" ] || BRF_SUITE_SLOT="<ORCHESTRATOR: no suite reads these Files (reads index); write the suites that pin them>"
      fi
    fi
    BRF_LANDS="$(poker_brief_cell "$PV_PLAN" Tasks "$BRF_ID" lands-on)" || BRF_LANDS=""
    if poker_brief_none "$BRF_LANDS"; then
      BRF_LANDS="$BRF_SUITES"
      [ -n "$BRF_LANDS" ] || BRF_LANDS="$BRF_SUITE_SLOT"
      [ -n "$BRF_LANDS" ] || BRF_LANDS="none the row's Files name no suite"
    fi
    [ -n "$BRF_SUITES" ] || BRF_SUITES="${BRF_SUITE_SLOT:-none}"

    # THE SCAFFOLD, in the shipped order. A label the verb has no value for is the orchestrator's: it is named, not written.
    BRF_SLOT="<ORCHESTRATOR: the row has none; write it>"
    BRF_BODY="$(mktemp "${TMPDIR:-/tmp}/brief.XXXXXX")" || { die "REFUSED — no scratch file can be made. Nothing was written."; exit 2; }
    BRF_LEFT=""
    case "$BRF_SIZE" in ''|*[!0-9]*) BRF_BIG=no ;; *) if [ "$BRF_SIZE" -ge 15 ]; then BRF_BIG=yes; else BRF_BIG=no; fi ;; esac
    BRF_PROG="$(poker_brief_record_entry "$BRF_FILES" progress "$BRF_ID")"
    [ -n "$BRF_PROG" ] || BRF_PROG="$BRF_RECREL/$BRF_ID.progress.md"
    while IFS= read -r BRF_L; do
      case "$BRF_L" in
        "Expected duration")
          case "$BRF_SIZE" in
            ''|*[!0-9]*) printf '%s: <ORCHESTRATOR: the row'"'"'s size is %s; write the minutes>\n' "$BRF_L" "${BRF_SIZE:-empty}" ;;
            *) printf '%s: %s minutes\n' "$BRF_L" "$BRF_SIZE" ;;
          esac ;;
        "Expected artifact") printf '%s: %s\n' "$BRF_L" "${BRF_ART:-$BRF_SLOT}" ;;
        "Progress artifact") [ "$BRF_BIG" = yes ] && printf '%s: %s\n' "$BRF_L" "$BRF_PROG" ;;
        "Cadence")           [ "$BRF_BIG" = yes ] && printf '%s: 15 min\n' "$BRF_L" ;;
        "Files")             poker_brief_none "$BRF_FILES_LINE" || printf '%s: %s\n' "$BRF_L" "$BRF_FILES_LINE" ;;
        "Suites")            printf '%s: %s\n' "$BRF_L" "$BRF_SUITES" ;;
        "Row")               printf '%s: %s\n' "$BRF_L" "$BRF_ID" ;;
        "Lands-on")          printf '%s: %s\n' "$BRF_L" "$BRF_LANDS" ;;
        *)                   BRF_LEFT="${BRF_LEFT:+$BRF_LEFT, }$BRF_L" ;;
      esac
    done > "$BRF_BODY" <<BRF_EOF
$BRF_LABELS
BRF_EOF
    {
      cat "$BRF_BODY"
      printf '\n## The row\n\n%s\n\n' "$BRF_TASK"
      printf 'Row %s: kind %s, step %s, serves %s, waits on %s, status %s.\n' "$BRF_ID" "$BRF_KIND" "$BRF_STEP" "$BRF_SERVES" "$BRF_DEPS" "$BRF_STATUS"
      printf 'Working head: %s\n' "$BRF_HEAD"
      printf 'Plan: %s\n\n' "$(clean "${PV_PLAN#"$PV_REPO"/}")"
      # THE ORCHESTRATOR'S SECTION: kept whole from a brief already there, else the two marked slots.
      if [ -f "$BRF_OUT" ] && /usr/bin/grep -q '^## Judgment[[:space:]]*$' "$BRF_OUT"; then
        awk '/^## Judgment[[:space:]]*$/ { f = 1 } f { print }' "$BRF_OUT"
      else
        printf '## Judgment\n\n'
        printf 'Research to read: <ORCHESTRATOR: the record files this row reads, or none>\n'
        printf 'Rulings: <ORCHESTRATOR: the rulings that bind this row, by assumption id, or none>\n'
      fi
    } > "$BRF_BODY.new"
    mkdir -p "${BRF_OUT%/*}" 2>/dev/null
    if ! mv -f "$BRF_BODY.new" "$BRF_OUT" 2>/dev/null; then
      rm -f "$BRF_BODY" "$BRF_BODY.new"
      die "REFUSED — $BRF_OUT cannot be written. The plan is unchanged."
      exit 2
    fi
    rm -f "$BRF_BODY"
    say "brief — $BRF_ID: written to ${BRF_OUT#"$PV_REPO"/}. Scaffold lines left to the orchestrator: ${BRF_LEFT:-none}. Under ## Judgment: the research to read and the rulings."
    exit 0
    ;;

  # THE SPLIT (wave-30 T17; REQ-12 AC-12.6, D14d-3, design-ledger Δ11: "the machine finds and records
  # a split; the mind decides it"). Which row to split and where to cut it are the orchestrator's
  # (steps/4.md, "Splitting a row"); this verb performs the cut it is handed, as task-add's
  # transaction: refused below Step 4 as task-add is, on a parent that is not `pending` (an active
  # row's writer is in its tree), and on children whose Files are not a cover of the parent's
  # (`units_split_check`); then `units_split_row` projects the split onto the copy, `units_validate`
  # judges the whole plan, the copy is held to its own claim — no row waits on the dropped parent, and
  # each open row that did waits on a child (`units_split_dependents`, `units_edges`) — and only then
  # the dry commit and the swap. Any refusal leaves the plan byte-identical.
  task-split)
    plan_verb_open task-split
    TS_CUR="${PV_CUR%[ab]}"
    case "$TS_CUR" in
      ''|*[!0-9]*)
        die "REFUSED — $PV_PLAN has current: ${TS_CUR:-(none)}; task-split changes a wave plan past Step-3 approval, whose current: is a step number."
        exit 1 ;;
    esac
    if [ "$TS_CUR" -lt 4 ]; then
      die "REFUSED — $PV_PLAN is at current: $TS_CUR; before Step-3 approval the plan is written by hand and reviewed, not split."
      exit 1
    fi
    TS_REC="$(units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' -v p="$TS_ID" '$1 == p')"
    case "$(printf '%s' "$TS_REC" | /usr/bin/grep -c .)" in
      1) : ;;
      0) die "REFUSED — the ## Tasks table of $PV_PLAN carries no row $(clean "$TS_ID"); the plan is unchanged."; exit 1 ;;
      *) die "REFUSED — the ## Tasks table carries more than one row $TS_ID; which one is meant is not the verb's to guess. The plan is unchanged."; exit 1 ;;
    esac
    TS_ST="$(units_field "$TS_REC" status)"
    if [ "$TS_ST" != pending ]; then
      die "REFUSED — $TS_ID is ${TS_ST:-(no status)}; task-split rewrites a pending row only. The plan is unchanged."
      exit 1
    fi
    TS_VIOL="$(units_split_check "$TS_ID" "$(units_field "$TS_REC" Files)" "${TS_CHECK[@]}")"
    if [ -n "$TS_VIOL" ]; then
      die "REFUSED — the children's Files are not a partition of $TS_ID's; the plan is unchanged:"
      printf '%s\n' "$TS_VIOL" >&2
      exit 1
    fi
    TS_WAITERS="$(units_split_dependents "$PV_PLAN" "$TS_ID")"
    PV_RC=0
    units_split_row "$PV_PLAN" "$TS_ID" "$(iso_now)" "${TS_ARGS[@]}" > "$PV_NEW" 2>/dev/null || PV_RC=$?
    if [ "$PV_RC" -ne 0 ] || [ ! -s "$PV_NEW" ]; then
      die "REFUSED — the split of $TS_ID cannot be written (units_split_row exit $PV_RC: a value no table cell can hold, or no ## SDLC State); the plan is unchanged."
      exit 1
    fi
    TS_VIOL="$(units_validate "$PV_NEW" 2>&1)"
    if [ -n "$TS_VIOL" ]; then
      die "REFUSED — with $TS_ID split into $TS_IDS, the ## Tasks table breaks the Task invariants; the plan is unchanged:"
      printf '%s\n' "$TS_VIOL" >&2
      exit 1
    fi
    TS_LEFT="$(units_split_dependents "$PV_NEW" "$TS_ID")"
    TS_EDGES="$(units_edges "$PV_NEW" 2>/dev/null)"
    TS_OPEN="$(units_rows "$PV_NEW" 2>/dev/null | awk -F'\t' '$10 == "pending" || $10 == "active" { print $1 }')"
    for _ts_w in $TS_WAITERS; do
      /usr/bin/grep -Fxq -- "$_ts_w" <<<"$TS_OPEN" || continue
      printf '%s\n' "$TS_EDGES" | awk -F'\t' -v w="$_ts_w" -v k=", $TS_IDS," '$2 == w && index(k, ", " $1 ",") { f = 1 } END { exit !f }' \
        || TS_LEFT="${TS_LEFT:+$TS_LEFT }$_ts_w"
    done
    if [ -n "$TS_LEFT" ]; then
      die "REFUSED — after the split these rows would still wait on $TS_ID, or on no child of it: $(printf '%s' "$TS_LEFT" | tr '\n' ' ' | sed 's/ $//'); the plan is unchanged."
      exit 1
    fi
    TS_K="$(printf '%s' "$TS_WAITERS" | /usr/bin/grep -c .)"
    plan_verb_swap task-split "$TS_ID split into $TS_IDS" writer
    say "task-split — $TS_ID → $TS_IDS; $TS_K dependent(s) re-pointed; written to $PV_PLAN, dry-committed first."
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
  # At wave scale the block also gains `share: <n>`, D16's plan fact (wave-28 T8, below).
  current)
    case "$PV_KEY" in
      9|9a|9b)
        die "REFUSED — current: 9 is close-out's to write, with the Step 9 line (bash <plugin-root>/scripts/close-out.sh); the plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open current
    if ! units_set_current "$PV_PLAN" "$PV_KEY" > "$PV_NEW" 2>/dev/null; then
      die "REFUSED — $PV_PLAN carries no current: line under ## SDLC State; the plan is unchanged."
      if /usr/bin/grep -q '^##[[:space:]][[:space:]]*SDLC State' "$PV_PLAN" 2>/dev/null; then
        die "missing: the line 'current: $PV_KEY' under ## SDLC State"
      else
        die "missing: a ## SDLC State section carrying 'current: $PV_KEY', above the plan's ## Tasks"
      fi
      exit 1
    fi
    PV_FILLED=""
    if [ "$PV_KEY" = 4 ]; then
      # lib/run.sh `plan_working_branch`, the one reader: SDLC State, then frontmatter (wave-35 T7; D14).
      PV_WB="$(plan_working_branch "$PV_PLAN")"
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
        # D16's PLAN FACT (wave-28 T8; A-orch-140): at wave scale the block also records the machine share the
        # run started under, `gate_share`'s value, through the same writer; a block already carrying the line
        # keeps it (the fill never rewrites), and a plan of another scale gets none.
        if [ "$(plan_frontmatter_get "$PV_PLAN" scale 2>/dev/null)" = wave ] && declare -F gate_share >/dev/null 2>&1; then
          PV_SHARE="$(gate_share 2>/dev/null)"
          [ -z "$PV_SHARE" ] || PV_FIELDS+=("share=$PV_SHARE")
        fi
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
    # working head: the regression, and each reading its rigor and scale deal. Each line that does not
    # hold is printed as the judge gave it.
    # The mode has a name of its own: PV_DRY is the dry copy's PATH (wave-27 T76; A-orch-171).
    # STEP 7 ASKS THE JUDGE TOO (wave-35 T10; D10, AC-1.2; A-T10-12). The copy is dry-committed at Step 7 first, as
    # every other step's is, so the gate refuses what a real commit at Step 7 would refuse in its own words (a
    # declared red still owed, a missing line); then the judge holds the facts the run owes at the working head;
    # then the swap, which does not commit the copy a second time. A plan already at 7 is the swap's to say.
    PV_DRYMODE=as-is; PV_HOW="dry-committed at that step first"
    case "$PV_KEY" in
      7)
        if ! cmp -s "$PV_NEW" "$PV_PLAN"; then
          plan_verb_dry current "current: $PV_KEY" as-is "${PV_CUR%[ab]}"
          cur7_judge 7
          PV_DRYMODE=judged
          PV_HOW="dry-committed at that step first; every fact the run owes holds at $PV_HEAD8 (facts_state)"
        fi ;;
      8|8a|8b)
        cur7_judge 8
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
    poker_owed_close "$PV_REPO" "approve:$AP_NAME" "approve"
    say "approve — $AP_NAME: approved: $AP_NAME by $AP_WHO written to $PV_PLAN; dry-committed first."
    exit 0
    ;;

  # THE PROOF VERB (wave-26 T4; REQ-3 AC-3.2, D5). Nothing recorded which code state a test pass
  # or a review read, so the same code was proved again and again. A proof is one line under
  # `## SDLC State` — `proved: kind=<kind> head=<40-hex> at=<ISO-UTC> evidence=<record/ path>`
  # (payload/scripts/lib/proof.sh owns its shape and its reader, `proof_last`) — and what is
  # unproved is the difference since the head it names. The head is the one the evidence attests
  # (its run header or its reviewed: range, held against the working branch's ref; T14, wave-36 T12),
  # never an operand. The line goes in through the shared transaction; every refusal below
  # leaves the plan byte-identical and names its fix. proof.sh is loaded here, for this verb alone, as brief.sh is for task-add and amend:
  # the tick never reads it, so it is not one of the libraries every verb needs.
  proof-add)
    if ! { declare -F proof_last >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_add_line >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    # INHERITED DEBT (wave-35 T9; D8, AC-1.6; ADR-054). A suite the floor's whole run left red that is ALSO red
    # at the run's base commit is debt the run inherited, not a regression it made. This verb asks the base
    # itself: it makes a scratch tree at `base-sha:` through spawn-worktree.sh, runs the suite there (the
    # project's tests/run.sh --only <suite> when the base has one, else the suite file), keeps the run's
    # log in the record, and removes the tree and its branch. Red there, it writes
    #
    #     inherited: <suite> base=<base> head=<the floor's head> at=<ISO-UTC> evidence=record/<wave>/<log>
    #
    # under `## SDLC State` through the plan transaction, and the judge (lib/proof.sh `_proof_floor_judge`)
    # owes the floor nothing for that suite and stands on the rest. Green there, it is a regression, and the
    # verb refuses to carry it. Only a suite the floor's proof line lists as owed can be inherited: the line
    # is the whole run's own word that the suite is red at its head.
    if [ "$PF_KIND" = inherited ]; then
      PF_SUITE="${PF_EVID##*/}"
      plan_verb_open proof-add
      PF_FHEAD="$(proof_last "$PV_PLAN" floor)"
      if [ -z "$PF_FHEAD" ]; then
        die "REFUSED — $PV_PLAN carries no floor proof, so no whole run says $PF_SUITE is red at the head; run the regression and proof-add floor first. The plan is unchanged."
        exit 1
      fi
      PF_OWED="$(_proof_last_read "$PV_PLAN" floor owed)"
      case ",$PF_OWED," in
        *",$PF_SUITE,"*) : ;;
        *)
          die "REFUSED — $PF_SUITE is not red in the floor's whole run (the proof at ${PF_FHEAD:0:12} owes ${PF_OWED:-nothing}); only a suite that run left red can be inherited debt. The plan is unchanged."
          exit 1 ;;
      esac
      PF_BASE="$(proof_plan_base "$PV_PLAN" "$PV_REPO")"; PF_BASEH=""
      proof_base_id "$PF_BASE" && PF_BASEH="$(git -C "$PV_REPO" rev-parse --verify -q "${PF_BASE}^{commit}" 2>/dev/null)"
      if [ -z "$PF_BASEH" ]; then
        die "REFUSED — $PV_PLAN names no base-sha: that is a commit here${PF_BASE:+ (it says $(clean "$PF_BASE"))}, so there is no base to run $PF_SUITE at; add base-sha: <the commit the work started from>. The plan is unchanged."
        exit 1
      fi
      PF_RECD="$(proof_debt_record "$PV_PLAN" "$PV_REPO" 2>/dev/null)"; PF_RECD="${PF_RECD%/*}"
      PF_DOCS="$(cd "$(docs_root "$PV_REPO")" 2>/dev/null && pwd -P)"
      case "$PF_RECD" in
        "$PF_DOCS"/record/?*) : ;;
        *) die "REFUSED — the plan's record directory cannot be resolved under $PF_DOCS/record/; the plan is unchanged."; exit 2 ;;
      esac
      mkdir -p "$PF_RECD" 2>/dev/null
      PF_LOG="$PF_RECD/inherited-$PF_SUITE-${PF_BASEH:0:12}.log"; PF_REL="${PF_LOG#"$PF_DOCS"/}"
      PF_SW="$(cd "$BIONIC_LIB/.." 2>/dev/null && pwd -P)/spawn-worktree.sh"
      PF_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/bionic-inherited.XXXXXX" 2>/dev/null)" || PF_PARENT=""
      PF_BR="bionic-inherited/${PF_SUITE%.sh}-${PF_BASEH:0:12}-$$"
      PF_OK=""; [ -z "$PF_PARENT" ] || PF_OK="$(cd "$PV_REPO" && bash "$PF_SW" create "$PF_BASEH" "$PF_BR" "$PF_PARENT" 2>&1)"
      PF_WT="$(printf '%s
' "$PF_OK" | awk '/^spawn-worktree: OK / { for (i = 3; i <= NF; i++) if (index($i, "path=") == 1) { print substr($i, 6); exit } }')"
      _pf_drop() {
        [ -z "$PF_WT" ] || ( cd "$PV_REPO" && bash "$PF_SW" remove "$PF_WT" ) >/dev/null 2>&1
        git -C "$PV_REPO" branch -q -D "$PF_BR" >/dev/null 2>&1
        [ -z "$PF_PARENT" ] || rm -rf "$PF_PARENT"
      }
      if [ -z "$PF_WT" ] || [ ! -d "$PF_WT" ]; then
        _pf_drop
        die "REFUSED — spawn-worktree.sh could not make a scratch tree at the base ${PF_BASEH:0:12}: $(clean "$(printf '%s' "$PF_OK" | tail -n 1)"). The plan is unchanged."
        exit 2
      fi
      if [ ! -f "$PF_WT/tests/$PF_SUITE" ]; then
        _pf_drop
        die "REFUSED — $PF_SUITE is not at the base ${PF_BASEH:0:12}, so its red is this run's own, not inherited; fix it on a fix row. The plan is unchanged."
        exit 1
      fi
      if [ -f "$PF_WT/tests/run.sh" ]; then PF_CMD="bash tests/run.sh --only $PF_SUITE"; else PF_CMD="bash tests/$PF_SUITE"; fi
      ( cd "$PF_WT" && bash -c "$PF_CMD" ) > "$PF_LOG.out" 2>&1; PF_RC=$?
      { printf 'head=%s suite=%s rc=%s
command: %s
' "$PF_BASEH" "$PF_SUITE" "$PF_RC" "$PF_CMD"; cat "$PF_LOG.out" 2>/dev/null; } > "$PF_LOG"
      rm -f "$PF_LOG.out"; _pf_drop
      case "$PF_RC" in
        0)
          die "REFUSED — $PF_SUITE is green at the base ${PF_BASEH:0:12} (its log: $PF_REL): a regression, not debt; a fix row closes it. The plan is unchanged."
          exit 1 ;;
        75|69)
          die "REFUSED — $PF_SUITE did not run at the base (exit $PF_RC: the gate never admitted it; its log: $PF_REL); run proof-add inherited again. The plan is unchanged."
          exit 1 ;;
      esac
      PF_LINE="inherited: $PF_SUITE base=$PF_BASEH head=$PF_FHEAD at=$(iso_now) evidence=$PF_REL"
      if ! proof_add_line "$PV_PLAN" "$PF_LINE" > "$PV_NEW" 2>/dev/null || [ ! -s "$PV_NEW" ]; then
        die "REFUSED — $PV_PLAN carries no ## SDLC State section to hold the line; the plan is unchanged."
        exit 1
      fi
      plan_verb_swap proof-add "$PF_SUITE inherited at ${PF_BASEH:0:12}" writer
      say "proof-add — inherited: $PF_SUITE red at the base ${PF_BASEH:0:12} (rc=$PF_RC) and at the floor's head ${PF_FHEAD:0:12}; written to $PV_PLAN, its log $PF_REL; the floor stands on the rest."
      exit 0
    fi
    if ! proof_kind_ok "$PF_KIND"; then
      die "REFUSED — '$(clean "$PF_KIND")' is not a proof kind: name floor, review or task (or proof-add inherited <suite>). The plan is unchanged."
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
    # EACH LOG IS HELD TO THE SAME RECORD RULES (wave-36 T35; AC-7.10): a floor's several logs are read one by one, and
    # PF_PAIRS keeps each one's real path and its path under the docs root, tab-joined; PF_REAL and PF_REL name the
    # first, which is the evidence of every other kind.
    PF_PAIRS=""; PF_REAL=""; PF_REL=""
    while IFS= read -r PF_EVID; do
      case "$PF_EVID" in
        *[[:space:]]*|*'|'*)
          die "REFUSED — the evidence path '$(clean "$PF_EVID")' carries a space, a tab, a line break or a |, which the space-separated proof line cannot hold; rename the file. The plan is unchanged."
          exit 1 ;;
        *,*)
          if [ "$PF_KIND" = floor ] && [ "$PF_EVIDS" != "$PF_EVID" ]; then
            die "REFUSED — the evidence path '$(clean "$PF_EVID")' carries a comma, and a floor proof of several logs names them comma-joined on one evidence= field; rename the file. The plan is unchanged."
            exit 1
          fi ;;
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
      _pf_real=""
      [ -n "$PF_DOCS" ] && [ -f "$PF_ABS" ] \
        && _pf_real="$(cd "$(dirname "$PF_ABS")" 2>/dev/null && pwd -P)/$(basename "$PF_ABS")"
      if [ -z "$_pf_real" ]; then
        die "REFUSED — the evidence file $(clean "$PF_EVID") does not exist (read as $(clean "$PF_ABS")); write the record first, then add its proof. The plan is unchanged."
        exit 1
      fi
      case "$_pf_real" in
        "$PF_DOCS"/record/*) _pf_rel="${_pf_real#"$PF_DOCS"/}" ;;
        *)
          die "REFUSED — the evidence $(clean "$PF_EVID") is not under record/ of the docs root ($PF_DOCS/record/); a proof cites a record. The plan is unchanged."
          exit 1 ;;
      esac
      [ -n "$PF_REAL" ] || { PF_REAL="$_pf_real"; PF_REL="$_pf_rel"; }
      PF_PAIRS="$PF_PAIRS$_pf_real	$_pf_rel
"
    done <<PF_EVIDS_LIST
$PF_EVIDS
PF_EVIDS_LIST
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
    PF_WB="$(plan_working_branch "$PV_PLAN")"
    if [ -z "$PF_WB" ]; then
      die "REFUSED — $PV_PLAN names no working-branch:, so there is no checkout to read the head from; add 'working-branch: <branch>' under ## SDLC State. The plan is unchanged."
      exit 1
    fi
    # THE WORKING HEAD IS THE BRANCH'S REF (wave-36 T12; D13, AC-7.4; C30): lib/proof.sh `proof_branch_head`, as the
    # judge reads it, so a reading of a merged branch whose worktree is gone still registers.
    PF_HEAD="$(proof_branch_head "$PV_PLAN" "$PV_REPO")" || PF_HEAD=""
    case "$PF_HEAD" in
      [0-9a-f]*) : ;;
      *)
        die "REFUSED — working-branch $(clean "$PF_WB") names no commit in $PV_REPO, so its head cannot be read; name a branch that exists under ## SDLC State and run proof-add again. The plan is unchanged."
        exit 1 ;;
    esac
    # THE HEAD IS THE ONE THE EVIDENCE READ (wave-26 T14; review 7 F1). The working head only
    # bounds it: a run's log must have read exactly that head on a clean tree, a review a commit
    # on its history, and the proof names what the evidence attests (lib/proof.sh
    # `proof_attested`). A task landed between the run and this verb is not proved by it.
    # The plan goes too: a review's range must start at or before its last review proof (T62).
    # A reading's range starts at or before the last proof of its own question (wave-27 T2; D1).
    # The project root goes too: a config still carrying the removed floor-attestation: key is refused by name (T35).
    # The repository reads the objects and the ref's head bounds the evidence: no checkout is asked (T12).
    # A FLOOR'S LOGS ARE EACH READ, AND SHARE ONE HEAD (wave-36 T35; D13, AC-7.10): every log is judged by the floor's one
    # grammar (lib/proof.sh `_proof_floor_log`), the first refusal is the verb's, and logs that read different heads
    # are refused naming each, for a floor is the runs of one head. The owed reds are the union of each log's.
    PF_OWED=""
    if [ "$PF_KIND" = floor ]; then
      PF_FH=""; PF_FHEADS=""; PF_FRELS=""; PF_SPLIT=""; PF_RUNAT=""; PF_RUNRC=""
      while IFS='	' read -r _pf_real _pf_rel; do
        [ -n "$_pf_real" ] || continue
        if ! _pf_h="$(proof_attested floor "$_pf_real" "$PV_REPO" "$PV_PLAN" "" "$PV_REPO" "$PF_HEAD")"; then
          die "REFUSED — $(clean_whole "$_pf_h"). The plan is unchanged."
          exit 1
        fi
        # THE PROOF NAMES THE RUN IT READ (wave-37 T4; AC-6.2): the recorded run the judge matched the log to.
        _pf_run="$(proof_floor_run "$_pf_real" "$PV_PLAN" "$PV_REPO")" || _pf_run=""
        PF_RUNAT="${PF_RUNAT:+$PF_RUNAT,}$(printf '%s' "$_pf_run" | cut -d' ' -f1)"
        PF_RUNRC="${PF_RUNRC:+$PF_RUNRC,}$(printf '%s' "$_pf_run" | cut -d' ' -f3)"
        [ -z "$PF_FH" ] || [ "$_pf_h" = "$PF_FH" ] || PF_SPLIT=1
        PF_FH="${PF_FH:-$_pf_h}"
        PF_FHEADS="${PF_FHEADS:+$PF_FHEADS, }$_pf_rel read ${_pf_h:0:12}"
        PF_FRELS="${PF_FRELS:+$PF_FRELS,}$_pf_rel"
        PF_OWED="$(printf '%s,%s\n' "$PF_OWED" "$(proof_floor_owed "$_pf_real")" | awk -F, '
          { for (i = 1; i <= NF; i++) if ($i != "" && !($i in s)) { s[$i] = 1; o = o (o == "" ? "" : ",") $i } }
          END { print o }')"
      done <<PF_PAIRS_LIST
$PF_PAIRS
PF_PAIRS_LIST
      if [ -n "$PF_SPLIT" ]; then
        die "REFUSED — the logs read different heads: $(clean "$PF_FHEADS"); a floor is the runs of one head, so run each at one head and cite those logs together. The plan is unchanged."
        exit 1
      fi
      PF_HEAD="$PF_FH"; PF_REL="$PF_FRELS"
    elif ! PF_HEAD="$(proof_attested "$PF_KIND" "$PF_REAL" "$PV_REPO" "$PV_PLAN" "$PF_QUESTION" "$PV_REPO" "$PF_HEAD")"; then
      die "REFUSED — $(clean_whole "$PF_HEAD"). The plan is unchanged."
      exit 1
    fi
    # ONE RECORD PATH IS ONE PASS (wave-28 T60; REQ-8 AC-8.6, D33). A `deferred:` or `moved:` line is
    # keyed `<record>#<n>`, so a second pass registered on the path of a first would inherit its deferral
    # or its move (a #1 moved to defer defers the new pass's fix). A reading's path whose proof line names
    # another head is refused, and so is one such a line already names (lib/proof.sh `proof_bind_awk` is
    # the one predicate, T72); a relaunched reader re-registering a record no such line names (the same
    # head) is admitted as before. A `check:` line binds nothing (wave-31 T32; D6).
    if [ -n "$PF_QUESTION" ]; then
      PF_PASS="$(proof_pass_conflict "$PV_PLAN" "$PF_REL" "$PF_HEAD")"
      case "$PF_PASS" in
        head\ *)
          die "REFUSED — $(clean "$PF_REL") is already registered at $(clean "${PF_PASS#head }" | cut -c1-12), not ${PF_HEAD:0:12}: write the pass to a new record path. The plan is unchanged."
          exit 1 ;;
        settled\ *)
          die "REFUSED — $(clean "$PF_REL") at ${PF_HEAD:0:12} already has a deferred: or moved: line: write the pass to a new record path. The plan is unchanged."
          exit 1 ;;
      esac
    fi
    # A WHOLE READ STARTS AT THE RUN'S BASE (wave-27 T41; review pass 10 F5). The line carries the
    # head and not the start, so `scope: whole` over a tail would read to the judge as a read of
    # everything; it is accepted only when the range starts at the plan's base-sha: or an ancestor
    # of it (proof_attested has already resolved the start, so here it is a commit).
    if [ "$PF_SCOPE" = whole ]; then
      PF_BASE="$(proof_plan_base "$PV_PLAN" "$PV_REPO")"; PF_BASEH=""
      proof_base_id "$PF_BASE" && PF_BASEH="$(git -C "$PV_REPO" rev-parse --verify -q "$PF_BASE^{commit}" 2>/dev/null)"
      if [ -z "$PF_BASEH" ]; then
        # THE SAME PLACE THE FIRST-READING REFUSAL NAMES (wave-27 T14; review pass 20 F4), and a word
        # such as HEAD is said to be no commit id (F1).
        PF_BASEWHY="it names no base-sha:"
        if [ -n "$PF_BASE" ] && ! proof_base_id "$PF_BASE"; then PF_BASEWHY="its base-sha: $(clean "$PF_BASE") is not a commit id"
        elif [ -n "$PF_BASE" ]; then PF_BASEWHY="its base-sha: $(clean "$PF_BASE") is no commit here"; fi
        die "REFUSED — the reading $(clean "$PF_REL") says scope: whole, but $PF_BASEWHY, so nothing shows it read from the start of the run; add base-sha: <the commit the work started from> to the frontmatter of $PV_PLAN, or write scope: piece. The plan is unchanged."
        exit 1
      fi
      PF_FROMH="$(git -C "$PV_REPO" rev-parse --verify -q "$PF_FROM^{commit}" 2>/dev/null)"
      if [ -z "$PF_FROMH" ] || ! git -C "$PV_REPO" merge-base --is-ancestor "$PF_FROMH" "$PF_BASEH" 2>/dev/null; then
        die "REFUSED — the reading $(clean "$PF_REL") says scope: whole, but its range starts at $(clean "$(printf '%s' "${PF_FROMH:-$PF_FROM}" | cut -c1-12)"), past the plan's base ${PF_BASEH:0:12}; a whole reading reads from the base, so write reviewed: ${PF_BASEH:0:12}..<b>, or scope: piece. The plan is unchanged."
        exit 1
      fi
    fi
    # A READING REGISTERS AT THE HEAD IT NAMES, OPEN BUILD ROWS OR NONE (wave-36 T28; D9, AC-3.1). Through wave-35
    # a whole read was refused while a build row was open (D10), because the judge covered a whole line with any
    # whole reading whatever its head. The judge now reaches only as far as the question's chain (wave-36 T7;
    # A-T7-5), so what lands after the reading is the cover rule's to judge, and the verb holds nothing.
    PF_LINE="$(proof_line "$PF_KIND" "$PF_HEAD" "$(iso_now)" "$PF_REL" "$PF_QUESTION" "$PF_READER" "$PF_RESULT" "$PF_SCOPE")"
    # A RED WHOLE RUN'S REDS RIDE ON ITS LINE (wave-35 T9; D8, AC-1.3): proof_attested took each log and every red
    # named; the line lists them as owed, and the judge reads them there. Its evidence= is the logs, comma-joined (T35).
    if [ "$PF_KIND" = floor ]; then
      PF_LINE="$(proof_floor_line "$PF_HEAD" "$(iso_now)" "$PF_REL" "$PF_OWED" "run=$PF_RUNAT head=$PF_HEAD rc=$PF_RUNRC")"
    fi
    # A RATED READING WRITES ITS PLAN LINES (wave-28 T15; D19, D21): one `deferred:` line per finding
    # the table defers, right after its proof line, in the same write (lib/proof.sh
    # `proof_finding_lines`). No `check:` line: a reader's rating is final (wave-31 T32; D6).
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
    say "proof-add — kind=$PF_KIND head=$PF_HEAD evidence=$PF_REL$PF_FIELDS${PF_OWED:+ owed=$PF_OWED}: written to $PV_PLAN${PF_BACK:+; $PF_BACK back to pending}; dry-committed first."
    [ -z "$PF_OWED" ] || say "proof-add — the whole run left $PF_OWED red: each is owed until a later landing runs it green (a fix row), or proof-add inherited <suite> finds it red at the base too."
    [ -z "$PF_PLANL" ] || printf '%s\n' "$PF_PLANL" | while IFS= read -r _pf_l; do say "proof-add — $_pf_l"; done
    [ -n "$PF_HELD" ] && say "proof-add — $PF_HELD stays active until every question it carries is read at ${PF_HEAD:0:12}; it returns to pending on that reading."
    [ -n "$PF_NONE" ] && say "proof-add — no active live review row holds $PF_REL in its Files: $PF_NONE stays active, nothing was returned to pending. If this record is that pass, its Files name another record: write the record under that name, or amend the row's Files."
    exit 0
    ;;

  # THE WAIVER (wave-27 T9; D2). The user's act, on their reply: one line under `## SDLC State`,
  #
  #   waived: question=<q> head=<working head> by <git user.name> <ISO-UTC> "<reply>"
  #
  # covering that question up to the head the plan's working branch's ref names, the head the judge
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
    # THE HEAD IS THE WORKING BRANCH'S REF (wave-36 T12; D13, AC-7.4; C30): lib/proof.sh `proof_branch_head`, the head
    # the judge reads the waiver against.
    WV_WB="$(plan_working_branch "$PV_PLAN")"
    WV_HEAD="$(proof_branch_head "$PV_PLAN" "$PV_REPO")" || WV_HEAD=""
    case "$WV_HEAD" in
      [0-9a-f]*) : ;;
      *)
        die "REFUSED — the plan's working-branch ${WV_WB:-(none named)} names no commit in $PV_REPO, so there is no head to waive at; the plan is unchanged."
        exit 1 ;;
    esac
    WV_LINE="$(proof_waiver_line "$WV_Q" "$WV_HEAD" "$WV_WHO" "$(iso_now)" "$WV_REPLY")"
    if ! proof_add_line "$PV_PLAN" "$WV_LINE" > "$PV_NEW" 2>/dev/null || [ ! -s "$PV_NEW" ]; then
      die "REFUSED — $PV_PLAN carries no ## SDLC State section to hold the waiver; the plan is unchanged."
      exit 1
    fi
    plan_verb_swap waive "the $WV_Q waiver at $WV_HEAD" writer
    poker_owed_close "$PV_REPO" "waive:$WV_Q" "waive"
    waive_owed_findings "$PV_PLAN" "$PV_REPO" "$WV_Q"
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

  # A MOVE IS THE USER'S PROVEN WORD (wave-28 T42; REQ-8 AC-8.9, D34). A registered finding — one whose
  # record a `proved:` line names as its evidence — is moved across the line, to defer or to fix, only
  # on words lib/said.sh `user_said` finds in a prompt the user typed in this session's transcript (a
  # tool's result, a teammate's or another session's message, a hook's context and the orchestrator's
  # own text never count; rc 2, no transcript, refuses too; the words stand as WHOLE WORDS and are at
  # least SAID_MIN_WORDS (three) of them unless they are a whole typed prompt, rc 3 refusing the short ones, T66). An S1, at the rating every read gives it
  # (lib/proof.sh `proof_finding_rating`), is never deferred. The move is written in place after the
  # finding's last line, through the plan transaction:
  #
  #   moved: <record>#<n> to=<defer|fix> by=<git user.name> at=<ISO-UTC> words="<words>" session=<sid> why="<why>"
  #
  # the words are looked for in every session the plan records, then this one (wave-36 T9; D10), and
  # session= names the one whose transcript holds them (lib/said.sh SAID_SESSION);
  #
  # the words folded to one line by lib/said.sh's own fold (`said_fold`, the rule the check is made
  # through; the verb passes the raw words to `user_said`), the why by `deferral_fold` (the same fold), both escaped as a
  # deferral's sentence is (`deferral_escape`); a move to defer first writes the finding's `deferred:`
  # line when the plan holds none (placed by `proof_add_line`). Every read then takes the priority the last move gave it.
  #
  # THE THIRD MOVE (wave-36 T8; REQ-3 AC-3.4, D9; ADR-056). `finding-move <record>#<n> fixed <row>` says a row of the
  # plan's `## Tasks` table fixed the finding: landed before the reading, beside it, or still to land. It is a fact
  # about the table, not a ruling across the line, so it takes no words; the row must be one the table carries. It
  # writes, in the same place:
  #
  #   moved: <record>#<n> to=fixed row=<T> by=<git user.name> at=<ISO-UTC>
  #
  # The finding reads fix until the row lands green, and then fixed (lib/proof.sh `proof_fixed`, whatever the row's
  # ancestry); the row needs no born marker, so it counts against no fix-cap. A row now answers the finding, so its
  # owed item closes, as `task-add --born` closes it.
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
    if [ -z "$FM_ROW" ] && ! declare -F user_said >/dev/null 2>&1; then
      die "REFUSED — what the user typed is read by lib/said.sh, which cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    if [ -z "$FM_ROW" ]; then FM_WORDS="$(said_fold "$FM_RAW")"; FM_WHY="$(deferral_fold "$FM_WHY_RAW")"; fi
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
    IFS='	' read -r _ FM_S FM_R _ _ _ FM_TITLE <<FM_FINDING
$FM_F
FM_FINDING
    set -- $(proof_finding_rating "$PV_PLAN" "$FM_ID" "$FM_S" "$FM_R")
    FM_S="$1"; FM_R="$2"
    if [ "$FM_TO" = defer ] && [ "$FM_S" = S1 ]; then
      die "REFUSED — $(clean "$FM_ID") is rated S1 $FM_R, and an S1 is never deferred, whoever asks; the plan is unchanged."
      exit 1
    fi
    if [ -n "$FM_ROW" ] && ! units_rows "$PV_PLAN" 2>/dev/null | awk -F'\t' -v r="$FM_ROW" '$1 == r { f = 1 } END { exit !f }'; then
      die "REFUSED — $FM_ROW is no row of the ## Tasks table of $PV_PLAN, and a finding is fixed only by a row the plan carries; the plan is unchanged."
      exit 1
    fi
    FM_WHO="$(deferral_fold "$(git -C "$PV_REPO" config user.name 2>/dev/null)")"
    if [ -z "$FM_WHO" ]; then
      die "REFUSED — no git user.name is set for $PV_REPO, and a move records who made it; set it, then move again. The plan is unchanged."
      exit 1
    fi
    if [ -z "$FM_ROW" ]; then
      user_said "$FM_RAW" "$PV_PLAN"; FM_SAID=$?
      if [ "$FM_SAID" -ne 0 ]; then
        said_refuse "$FM_SAID" "$FM_WORDS" "a move"
        exit 1
      fi
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
    if [ -n "$FM_ROW" ]; then
      FM_LINE="moved: $FM_ID to=fixed row=$FM_ROW by=$FM_WHO at=$(iso_now)"
    else
      FM_LINE="moved: $FM_ID to=$FM_TO by=$FM_WHO at=$(iso_now) words=\"$(deferral_escape "$FM_WORDS")\" session=$SAID_SESSION why=\"$(deferral_escape "$FM_WHY")\""
    fi
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
    if [ -n "$FM_ROW" ]; then
      poker_owed_close "$PV_REPO" "$(finding_owed_key "$FM_ID")" "finding-move fixed $FM_ROW"
      say "finding-move — $(clean "$FM_ID") fixed by $FM_ROW, by $(clean "$FM_WHO"): its moved: line is on $PV_PLAN; dry-committed first. It reads fixed once $FM_ROW has landed green, and counts against no fix-cap."
      exit 0
    fi
    say "finding-move — $(clean "$FM_ID") to $FM_TO on the user's words, by $(clean "$FM_WHO"): its moved: line is on $PV_PLAN; dry-committed first."
    [ -z "$FM_DEF" ] || say "finding-move — $(clean "$FM_DEF")"
    exit 0
    ;;

  # THE REVIEW DISPOSITION (wave-33 T13; REQ-5 AC-5.1, D6). One pass over every registered reading (each record a
  # `proved: kind=review` line with a question names as its evidence, its last such line giving its question and
  # head) prints one line per finding:
  #
  #   finding <record>#<n> <S> user-facing=<on|off> record=<record> at=<path:line|-> row=<T<k>[,…]|—>
  #           state=<open|fixed|deferred|accepted> decision="<what it needs>" [stated="<sentence>"|stated=-] title="<title>"
  #
  # the state read as the judge reads it: fixed when a row born of it landed green at or after the reading's head,
  # or the row its newest move names (`moved: … to=fixed row=<T>`, wave-36 T8) landed green whatever its ancestry
  # (lib/proof.sh `proof_fixed`), decision="none: fixed by <row>, landed green at <commit>"; else by the priority
  # the plan's moves give it (`proof_finding_rating`): fix is open, defer is deferred, note is accepted. row= names
  # the rows born of it and the row a move to fixed names. An open finding no row answers and no ruling has moved
  # needs the person, and gets one owed item, `finding_owed_key` (lib/owed.sh; opening is idempotent per key). A reading's
  # debt: lines go to the run's debt ledger through `debt add`, run as a child. Nothing in the plan is written.
  #
  # A RULING (four or five operands) is the person's word on one finding, recorded through finding-move (their
  # words, typed, at least SAID_MIN_WORDS whole words; an S1 is never deferred) and, for a deferral given a sentence,
  # finding-stated, each run as a child so each keeps its own transaction; then the finding's owed item closes.
  disposition)
    if ! { declare -F proof_fixed >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_fixed >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
      exit 2
    fi
    plan_verb_open disposition
    if [ -n "$DSP_ID" ] && ! finding_read "$PV_PLAN" "$PV_REPO" "$DSP_ID"; then
      die "REFUSED — $FR_WHY; the plan is unchanged."
      exit 1
    fi
    if [ -n "$DSP_ID" ]; then
      DSP_OUT="$( cd "$PV_REPO" && "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" finding-move "$DSP_ID" "$DSP_TO" "$DSP_RAW" "$DSP_WHY" 2>&1 )"; DSP_RC=$?
      [ -z "$DSP_OUT" ] || printf '%s\n' "$DSP_OUT"
      [ "$DSP_RC" = 0 ] || exit "$DSP_RC"
      if [ -n "$DSP_SENT" ]; then
        DSP_OUT="$( cd "$PV_REPO" && "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" finding-stated "$DSP_ID" "$DSP_SENT" 2>&1 )"; DSP_RC=$?
        [ -z "$DSP_OUT" ] || printf '%s\n' "$DSP_OUT"
        [ "$DSP_RC" = 0 ] || { die "disposition — the move of $(clean "$DSP_ID") is written; its sentence is not: run finding-stated $(clean "$DSP_ID") '<sentence>' again."; exit "$DSP_RC"; }
      fi
      poker_owed_close "$PV_REPO" "$(finding_owed_key "$DSP_ID")" "disposition"
      say "disposition — $(clean "$DSP_ID") ruled $DSP_TO on the person's words; its owed item is closed."
      exit 0
    fi
    DSP_DOCS="$(docs_root "$PV_REPO")"
    DSP_FIXED="$(proof_fixed "$PV_PLAN" "$PV_REPO")"
    DSP_BORN="$(units_born_findings "$PV_PLAN" 2>/dev/null)" || DSP_BORN=""
    DSP_READS="$(awk "$(proof_awk)"'
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION != "" && PROOF_EVIDENCE != "" {
        if (!(PROOF_EVIDENCE in q)) ord[++n] = PROOF_EVIDENCE
        q[PROOF_EVIDENCE] = PROOF_QUESTION; h[PROOF_EVIDENCE] = PROOF_HEAD
      }
      END { for (i = 1; i <= n; i++) printf "%s\t%s\t%s\n", ord[i], q[ord[i]], h[ord[i]] }' "$PV_PLAN")"
    DSP_NF=0; DSP_NR=0; DSP_NP=0
    while IFS='	' read -r DSP_EV DSP_Q DSP_H; do
      [ -n "$DSP_EV" ] || continue
      DSP_NR=$((DSP_NR + 1))
      if ! DSP_GOT="$(proof_findings "$DSP_DOCS/$DSP_EV" 2>&1)"; then
        say "reading $(clean "$DSP_EV") ($DSP_Q) cannot be read: $(clean "$DSP_GOT")"
        continue
      fi
      _proof_fixed_var "$DSP_FIXED" "$DSP_EV" "$DSP_H" "$PV_REPO"
      DSP_DEBT=0
      while IFS='	' read -r DSP_N DSP_S DSP_R DSP_W _ _ DSP_T; do
        [ -n "$DSP_N" ] || continue
        [ "$DSP_N" != debt ] || { DSP_DEBT=1; continue; }
        DSP_FID="$DSP_EV#$DSP_N"
        DSP_NF=$((DSP_NF + 1))
        set -- $(proof_finding_rating "$PV_PLAN" "$DSP_FID" "$DSP_S" "$DSP_R")
        DSP_P="${3:-}"
        DSP_ROWS="$(printf '%s\n' "$DSP_BORN" | awk -F'\t' -v id="$DSP_FID" '$3 == id { printf "%s%s", (k++ ? "," : ""), $1 }')"
        if [ "$(_proof_moved_to "$PV_PLAN" "$DSP_FID")" = fixed ]; then
          DSP_MV="$(proof_move_line "$PV_PLAN" "$DSP_FID" | awk '{ sub(/^row=/, "", $4); print $4 }')"
          case ",$DSP_ROWS," in *",$DSP_MV,"*) : ;; *) DSP_ROWS="${DSP_ROWS:+$DSP_ROWS,}$DSP_MV" ;; esac
        fi
        DSP_STATED=""
        case "$_PROOF_FIXED_IDS" in
          *$'\n'"$DSP_FID"$'\n'*)
            DSP_STATE=fixed
            DSP_FROW="$(printf '%s\n' "$DSP_FIXED" | awk -F'\t' -v id="$DSP_FID" '$1 == id { print $2 "\t" $3; exit }')"
            DSP_DEC="none: fixed by ${DSP_FROW%%	*}, landed green at $(printf '%.12s' "${DSP_FROW#*	}")" ;;
          *)
            case "$DSP_P" in
              fix)
                DSP_STATE=open
                if [ -n "$DSP_ROWS" ]; then
                  DSP_DEC="none: waits on $DSP_ROWS landing green"
                elif [ -n "$(_proof_moved_to "$PV_PLAN" "$DSP_FID")" ]; then
                  DSP_DEC="a row born of it: task-add <id> … --born $DSP_FID"
                else
                  if [ "$DSP_S" = S1 ]; then DSP_DEC="the person's: fix it or waive $DSP_Q (an S1 is never deferred)"
                  else DSP_DEC="the person's: fix it, defer it, or waive $DSP_Q"; fi
                  DSP_NP=$((DSP_NP + 1))
                  if declare -F owed_open >/dev/null 2>&1; then
                    OWED_ROOT="$PV_REPO" owed_open "$(finding_owed_key "$DSP_FID")" "Finding $DSP_S needs a ruling" \
                      "$(clean "$DSP_FID") $DSP_S $DSP_R: $(clean "$DSP_T") — $DSP_DEC" >/dev/null 2>&1 || :
                  fi
                fi ;;
              defer)
                DSP_STATE=deferred
                DSP_STATED="$(deferral_sentence "$PV_PLAN" "$DSP_FID" 2>/dev/null)" || DSP_STATED=""
                if [ -n "$DSP_STATED" ]; then DSP_DEC="none: stated"
                else DSP_DEC="its changelog sentence: finding-stated $DSP_FID '<sentence>'"; fi ;;
              *) DSP_STATE=accepted; DSP_DEC="none" ;;
            esac ;;
        esac
        DSP_LINE="finding $DSP_FID $DSP_S user-facing=$DSP_R record=$DSP_EV at=$DSP_W row=${DSP_ROWS:-—} state=$DSP_STATE decision=\"$DSP_DEC\""
        if [ "$DSP_STATE" = deferred ]; then
          if [ -n "$DSP_STATED" ]; then DSP_LINE="$DSP_LINE stated=\"$DSP_STATED\""; else DSP_LINE="$DSP_LINE stated=-"; fi
        fi
        say "$DSP_LINE title=\"$DSP_T\""
      done <<DSP_FINDINGS
$DSP_GOT
DSP_FINDINGS
      if [ "$DSP_DEBT" = 1 ]; then
        ( cd "$PV_REPO" && "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" debt add "$DSP_EV" "$PV_PLAN" 2>&1 ) || :
      fi
    done <<DSP_READINGS
$DSP_READS
DSP_READINGS
    say "disposition — $DSP_NF findings in $DSP_NR registered readings; $DSP_NP need the person's ruling (disposition <record>#<n> fix|defer '<their words>' '<why>' ['<changelog sentence>'])."
    exit 0
    ;;

  # THE RELEASE CHECK (wave-27 T16; D12). A project may name one command in `.bionic/config.yaml`
  # under `release-check:`. This verb runs it in the checkout of the plan's working branch, with
  # BIONIC_CHECK_BASE at the last release and BIONIC_CHECK_HEAD at the working head, its words
  # split on blanks with globbing off.
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
    RC_WB="$(plan_working_branch "$PV_PLAN")"
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
      # shellcheck disable=SC2086  # the configured command is meant to split on blanks
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
    RC_WAVE="$(proof_plan_slug "$PV_PLAN")"
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

  # THE DECLARED REGRESSION'S RUN (wave-28 T75; REQ-17 AC-17.1, D36). A project whose regression is not tests/run.sh
  # names it in `.bionic/config.yaml` under `floor:`, split on blanks with globbing off as `release-check:`
  # is. This verb runs it in the checkout of the plan's working branch, reading the head and the dirty
  # count (`_wt_piece_dirt`, land's reading: untracked files count, the record link does not) before the
  # run and again after it: a run that moved either is not a run of the head it read, so it is refused
  # and no log is written. Otherwise every run keeps its log, `record/<wave>/floor-run-<head>.log`, the
  # n-th at one head `floor-run-<head>-<n>.log`, in the floor's one grammar (wave-36 T35; D13, AC-7.10): opening
  # `head=<40-hex> dirty=<n>`, then `command: <cmd>`, then the output, and closing `rc=<n>`, its last line; the
  # verb exits with the command's code.
  # IT RUNS AND LOGS; IT WRITES NO PROOF. `release-check` writes its own fact because a check is a run the
  # verb owns; a regression is evidence the run cites, and `proof-add floor` stays the one writer of its line
  # (lib/proof.sh `_proof_floor_log` judges the log there as it judges any log: `floor:` is a convenience, never
  # a privilege, and a project may run its regression itself and cite that log).
  #
  # WITH NO floor: KEY THE REGRESSION IS THE PROJECT'S tests/run.sh (wave-35 T10; D10, REQ-1 AC-1.8). The verb runs
  # it, whole, in the same checkout at the same head and logs it the same way, `command: tests/run.sh`; the runner
  # asks the machine's gate itself, kind whole (tests/run.sh THE ONE ADMISSION; ADR-051). Its log is the evidence
  # `proof-add floor` judges by the runner's own report (lib/proof.sh `proof_attested`): a red whole run is the
  # floor's candidate, its reds owed (wave-35 T9), so the record line is printed red or green. A run the gate never
  # admitted (exit 75, no verdict) ran nothing and writes no log. With neither key nor runner it refuses, naming the
  # other way: run the regression and cite its log. A config carrying `floor-attestation:`, a key removed in wave-36
  # (T35), is refused first, naming it (lib/proof.sh `proof_floor_retired`).
  # THE ONE PATH A RUNNER IS GIVEN THE WHOLE RUN BY, HELD TO THE FULL-RUN RULES (AC-1.8): the dispatch wall's
  # (hooks/dispatch-preflight.sh, THE FULL-RUN WALL), asked of the same facts in the same order, before anything
  # runs: `regression: no` refuses it (`plan_regression`); a row the regression waits on that still writes the head
  # refuses it (`units_floor_holds`); a covered head refuses it (`proof_state`); and a second whole run — the plan
  # already carries a floor proof, or a floor-run log of tests/run.sh — needs the user's `approved: regression-2`
  # (`proof_approved`). The bash wall's full-tree refusal names this verb as the whole run's path (lib/walls.sh).
  floor-run)
    FR_ROOT="$(project_root "$PWD")"
    FR_CMD="$(config_value "$FR_ROOT" floor "" 2>/dev/null)"
    if ! { declare -F proof_state >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
       || ! declare -F proof_state >/dev/null 2>&1; then
      die "REFUSED — the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; nothing was run."
      exit 2
    fi
    if FR_RETIRED="$(proof_floor_retired "$FR_ROOT")"; then
      die "REFUSED — $(clean "$FR_RETIRED"). Nothing was run."
      exit 1
    fi
    plan_verb_open floor-run
    FR_WB="$(plan_working_branch "$PV_PLAN")"
    FR_CO=""; [ -z "$FR_WB" ] || FR_CO="$(proof_checkout "$PV_REPO" "$FR_WB")" || FR_CO=""
    FR_HEAD=""; [ -z "$FR_CO" ] || FR_HEAD="$(git -C "$FR_CO" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)"
    case "$FR_HEAD" in
      [0-9a-f]*) : ;;
      *)
        die "REFUSED — no checkout of $PV_REPO has the plan's working-branch ${FR_WB:-(none named)} checked out, so there is no head to run the regression at; nothing was run."
        exit 1 ;;
    esac
    FR_WAVE="$(proof_plan_slug "$PV_PLAN")"
    FR_DOCS="$(docs_root "$PV_REPO")"
    FR_WHOLE=""
    if [ -z "$FR_CMD" ]; then
      if [ ! -f "$FR_CO/tests/run.sh" ]; then
        die "REFUSED — this project declares no floor: in .bionic/config.yaml, and the working checkout $(cd "$FR_CO" 2>/dev/null && pwd -P) holds no tests/run.sh to run as its regression; declare floor: <command> there, or run the regression yourself and cite its log (its first head= line head=<40-hex> dirty=0, its last line rc=0) with proof-add floor <log> [<log>…]. Nothing was run."
        exit 1
      fi
      FR_WHOLE=yes; FR_CMD="tests/run.sh"
      # RULE 1. The setting, not a run.
      if [ "$(plan_regression "$PV_PLAN")" = no ]; then
        die "REFUSED — the plan declares regression: no (Step 0), so it owes no whole run, and no approval overrides the setting; put it to the user and change it with: bash ${HOOK_DIR}/session-poker.sh regression yes '<the user's reply>'. Nothing was run."
        exit 1
      fi
      # RULE 2. A row the regression waits on still writes the head.
      FR_OPEN="$(units_floor_holds "$PV_PLAN" "" 2>/dev/null | awk -F'\t' 'NF { printf "%s%s (step %s, %s)", (n++ ? ", " : ""), $1, $2, $3 }')"
      if [ -n "$FR_OPEN" ]; then
        die "REFUSED — rows the regression waits on still write tracked files: $FR_OPEN; the whole run comes once, after the last of them lands, or it proves a head that does not survive their landing. Nothing was run."
        exit 1
      fi
      # RULE 3. A proved head owes no run.
      FR_STATE="$(proof_state "$PV_PLAN" "$PV_REPO" 2>/dev/null)"
      case "$FR_STATE" in
        covered*)
          die "REFUSED — the working head ${FR_HEAD:0:12} is already proved: the plan's floor covers it ($(clean "$(proof_last_line "$PV_PLAN" floor)")); a change landed after it is proved by the suites its row names. Nothing was run."
          exit 1 ;;
      esac
      # RULES 4 AND 5. The first whole run runs; a second is the user's word.
      FR_FIRST=""
      FR_LAST="$(proof_last "$PV_PLAN" floor)"
      [ -z "$FR_LAST" ] || FR_FIRST="the floor proof at ${FR_LAST:0:12}"
      if [ -z "$FR_FIRST" ]; then
        for _fr_l in "$FR_DOCS/record/$FR_WAVE"/floor-run-*.log; do
          [ -f "$_fr_l" ] || continue
          [ "$(sed -n 2p "$_fr_l" 2>/dev/null)" = "command: tests/run.sh" ] || continue
          FR_FIRST="the run logged at ${_fr_l#"$FR_DOCS"/}"; break
        done
      fi
      if [ -n "$FR_FIRST" ] && ! proof_approved "$PV_PLAN" regression-2; then
        FR_OWED=""; case "$FR_STATE" in owed"	"*) FR_OWED="${FR_STATE#owed	}" ;; esac
        if [ -n "$FR_OWED" ]; then
          die "REFUSED — a second whole run on this plan: the first is $FR_FIRST, and it left $FR_OWED red, each owed until a later landing runs it green. Dispatch a fix row that runs $FR_OWED; a second whole run needs the user's word: a row that reads approval:regression-2, and bash ${HOOK_DIR}/session-poker.sh approve regression-2 '<the user's reply>'. Nothing was run."
        else
          die "REFUSED — a second whole run on this plan: the first is $FR_FIRST, and the floor reads $(clean "${FR_STATE//	/ }"). A change after the whole run is proved by a fix row's suites; a second whole run needs the user's word: a row that reads approval:regression-2, and bash ${HOOK_DIR}/session-poker.sh approve regression-2 '<the user's reply>'. Nothing was run."
        fi
        exit 1
      fi
    fi
    FR_DIRT="$(_wt_piece_dirt "$FR_CO")"
    FR_DIRTY="$(printf '%s' "$FR_DIRT" | awk 'END { print NR + 0 }')"
    # A DIRTY TREE IS REFUSED BEFORE THE RUN, NOT LOGGED AFTER IT (wave-35 T32; D20, A-orch-32). The log of a dirty
    # whole run counted as the first whole run (rule 4) while proof-add floor refuses it, so the re-run its own message
    # asked for was refused as a second whole run and the one allowed run was spent on nothing. The after-the-run
    # comparison below stays: it guards a run that dirtied a clean tree.
    if [ -n "$FR_WHOLE" ] && [ "$FR_DIRTY" -ne 0 ]; then
      FR_PATHS="$(printf '%s\n' "$FR_DIRT" | sed -n '1,5p' | awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $0 }')"
      FR_MORE=""; [ "$FR_DIRTY" -le 5 ] || FR_MORE=", and $((FR_DIRTY - 5)) more"
      die "REFUSED — the working checkout $(cd "$FR_CO" 2>/dev/null && pwd -P) is dirty (dirty=$FR_DIRTY): $(clean "$FR_PATHS")$FR_MORE. The whole run proves a committed head, and a log of a dirty tree is refused by proof-add floor yet would count as the first whole run; nothing was run and no log was written; commit or stash it and run floor-run again."
      exit 1
    fi
    FR_TMP="$(mktemp "${TMPDIR:-/tmp}/bionic-floor-run.XXXXXX")" || {
      die "REFUSED — no scratch file for the regression's output can be made under ${TMPDIR:-/tmp}; nothing was run."
      exit 1
    }
    if [ -n "$FR_WHOLE" ]; then
      ( cd "$FR_CO" 2>/dev/null || exit 1
        exec bash tests/run.sh ) </dev/null > "$FR_TMP" 2>&1
    else
      ( cd "$FR_CO" 2>/dev/null || exit 1
        set -f
        # shellcheck disable=SC2086  # the configured command splits on blanks, as release-check's does
        exec $FR_CMD ) </dev/null > "$FR_TMP" 2>&1
    fi
    FR_RC=$?
    # A WHOLE RUN THE GATE NEVER ADMITTED RAN NOTHING (tests/run.sh: exit 75 before any suite, no verdict), so
    # there is no run of the head to log.
    if [ -n "$FR_WHOLE" ] && [ "$FR_RC" -eq 75 ] && ! /usr/bin/grep -q '^Gating: ' "$FR_TMP" 2>/dev/null; then
      cat "$FR_TMP"; rm -f "$FR_TMP"
      die "floor-run — the gate did not admit the whole run (exit 75), so nothing ran and no log was written; run floor-run again."
      exit 75
    fi
    FR_NOW="$(git -C "$FR_CO" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)"
    FR_DIRTY2="$(_wt_piece_dirt "$FR_CO" | awk 'END { print NR + 0 }')"
    FR_MOVED=""
    [ "$FR_NOW" = "$FR_HEAD" ] || FR_MOVED="head ${FR_HEAD:0:12} to ${FR_NOW:-<none>}"
    [ "$FR_DIRTY2" = "$FR_DIRTY" ] || FR_MOVED="${FR_MOVED:+$FR_MOVED, }dirty=$FR_DIRTY to dirty=$FR_DIRTY2"
    if [ -n "$FR_MOVED" ]; then
      cat "$FR_TMP"; rm -f "$FR_TMP"
      die "REFUSED — the regression ($(clean "$FR_CMD")) moved the working checkout $FR_CO while it ran ($FR_MOVED); no log was written. Put back what it changed and run floor-run again."
      exit 1
    fi
    FR_REL="record/$FR_WAVE/floor-run-$FR_HEAD.log"; FR_NTH=1
    while [ -e "$FR_DOCS/$FR_REL" ]; do FR_NTH=$((FR_NTH + 1)); FR_REL="record/$FR_WAVE/floor-run-$FR_HEAD-$FR_NTH.log"; done
    FR_LOG="$FR_DOCS/$FR_REL"
    if ! mkdir -p "${FR_LOG%/*}" 2>/dev/null \
       || ! { printf 'head=%s dirty=%s\ncommand: %s\n' "$FR_HEAD" "$FR_DIRTY" "$FR_CMD"; awk '{ print }' "$FR_TMP"; printf 'rc=%s\n' "$FR_RC"; } > "$FR_LOG" 2>/dev/null; then
      cat "$FR_TMP"; rm -f "$FR_TMP"
      die "REFUSED — the regression exited $FR_RC, but its log $FR_LOG cannot be written."
      exit 1
    fi
    # THE RUN IS RECORDED WHERE ITS PROOF WILL LOOK (wave-37 T4; D7, AC-6.1; ADR-057): one `ev=run` line in the plan's
    # landing record (lib/line.sh `line_event`, through `_wt_proofs_put`), the log by its record path, the head and
    # dirty count read before the run, its exit, and the log's sha256 (lib/proof.sh `_proof_sha256`), so `proof-add
    # floor` accepts this log, and this log as it is now, and no hand-written one.
    FR_SHA="$(_proof_sha256 "$FR_LOG")" || FR_SHA=""
    declare -F line_event >/dev/null 2>&1 || { [ -r "$BIONIC_LIB/line.sh" ] && . "$BIONIC_LIB/line.sh"; } >/dev/null 2>&1
    if [ -z "$FR_SHA" ] || ! declare -F line_event >/dev/null 2>&1 \
       || ! line_event "$PV_PLAN" run "log=$FR_REL" "head=$FR_HEAD" "dirty=$FR_DIRTY" "rc=$FR_RC" "sha256=$FR_SHA" 2>/dev/null; then
      die "floor-run — the run line for $FR_REL could not be written to the plan's landing record$([ -n "$FR_SHA" ] || printf ' (no sha256 tool answered)'), so proof-add floor will refuse this log as no recorded run."
    fi
    if [ -n "$FR_WHOLE" ]; then
      FR_VERDICT="$(/usr/bin/grep '^Gating: ' "$FR_TMP" 2>/dev/null | tail -n 1)"
      rm -f "$FR_TMP"
      say "floor-run — the whole run (tests/run.sh) at ${FR_HEAD:0:12} exited $FR_RC${FR_VERDICT:+ ($FR_VERDICT)}: head=$FR_HEAD dirty=$FR_DIRTY rc=$FR_RC evidence=$FR_REL"
      if [ "$FR_DIRTY" -ne 0 ]; then
        say "floor-run — the tree was dirty (dirty=$FR_DIRTY), so proof-add floor refuses this log; commit and run floor-run again."
      else
        [ "$FR_RC" -eq 0 ] || say "floor-run — a red whole run is the floor's candidate: proof-add floor records it with its red suites owed, each closed by a later landing that runs it green (a fix row)."
        say "floor-run — record it: bash ${HOOK_DIR}/session-poker.sh proof-add floor $FR_REL"
      fi
      exit "$FR_RC"
    fi
    if [ "$FR_RC" -ne 0 ]; then
      cat "$FR_TMP"; rm -f "$FR_TMP"
      die "floor-run — the regression ($(clean "$FR_CMD")) exited $FR_RC at ${FR_HEAD:0:12}; its log is $FR_REL. Fix what it names, commit, and run floor-run again."
      exit "$FR_RC"
    fi
    rm -f "$FR_TMP"
    say "floor-run — head=$FR_HEAD dirty=$FR_DIRTY rc=0 evidence=$FR_REL"
    if [ "$FR_DIRTY" -ne 0 ]; then
      say "floor-run — the tree was dirty (dirty=$FR_DIRTY), so proof-add floor refuses this log; commit and run floor-run again."
    else
      say "floor-run — record it: bash ${HOOK_DIR}/session-poker.sh proof-add floor $FR_REL"
    fi
    exit 0
    ;;

  # THE BASIS, ON ASK (wave-37 T8; D8, REQ-4 AC-4.2). `cover <question> <a>..<b>` prints, on stdout, the
  # `cover <sha> <basis>` lines `cover_basis` builds for that range and question, the ones `cur7_judge` prints under
  # its `review <question> … uncovered <a>..<b>` line, and ends that line by asking for. It writes nothing and asks
  # the judge nothing more: a range every commit of which holds prints no line, exit 0. A head that is no commit
  # here, or a plan the library cannot read, is the library's sentence on stderr and exit 1. Never called from the
  # tick or any wall.
  cover)
    plan_verb_open cover
    COV_VERB_LINES="$(cover_basis "$PV_PLAN" "$COV_Q" "$COV_A" "$COV_B")"; COV_RC=$?
    [ "$COV_RC" -ne 2 ] || exit 1
    if [ -n "${COV_VERB_LINES}" ]; then
      printf '%s\n' "$COV_VERB_LINES"
    fi
    exit 0
    ;;

  # THE RUN'S NUMBERS (wave-28 T14; D18, REQ-4). The fold and its definitions are `landing_report`'s,
  # above the verbs. The plan is the one named, resolved as fill-report resolves its operand (a path
  # from the project root, else from the docs root), or else this session's bound run; the record is
  # that plan's landing record, under the plan's own project. It writes nothing and exits 0 whatever
  # the record holds.
  # THE DEBT LEDGER (wave-30 T22; D2, P2, AC-11.2, AC-11.3). `record/<run>/debt.md` (lib/proof.sh
  # `proof_debt_ledger_path`, whose comment holds the line's shape) has this verb as its one writer, under
  # a lock beside the file (`launch_sync_lock`, the plan writer's own). `add` reads a record's `debt:`
  # lines, a reading's or any other's (`proof_record_debts`, the registering verb's debt arm; wave-36
  # T13), holds each to the one grammar (lib/debt.sh `debt_line_ok`), and writes a line per concept
  # and kind it does not hold yet; `touched` adds one to the touches of every unburned item of the
  # concept (the dispatch wall's advisory calls it); `burn` writes `burned <row>` in their last cell; `adopt`
  # reads the `debt:` lines close-out carried under `## Deferrals` of a continuation (AC-11.2's read-back,
  # wave-30 T32) and writes each as an item with its touches and raised-by kept, none burned.
  # Exit 0 done; 1 refused, the ledger unchanged; 2 the run or the record cannot be found; 75 another
  # writer held the lock for the whole wait.
  debt)
    REPO="$(project_root "$PWD")"
    REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
    if [ -z "$REPO_REAL" ]; then
      die "REFUSED — cannot resolve the working directory."
      exit 2
    fi
    DEBT_PLAN=""
    if [ -n "$DEBT_PLAN_ARG" ]; then
      case "$DEBT_PLAN_ARG" in
        /*) DEBT_PLAN="$DEBT_PLAN_ARG" ;;
        *)  DEBT_PLAN="$REPO_REAL/$DEBT_PLAN_ARG"
            [ -f "$DEBT_PLAN" ] || DEBT_PLAN="$(docs_root "$REPO_REAL")/$DEBT_PLAN_ARG" ;;
      esac
      if [ ! -f "$DEBT_PLAN" ] || [ -L "$DEBT_PLAN" ]; then
        die "REFUSED — no plan file at $DEBT_PLAN_ARG; name the plan whose debt ledger this is."
        exit 2
      fi
    else
      SESSION_ID="$(session_id)" || SESSION_ID=""
      if [ -z "$SESSION_ID" ]; then
        die "REFUSED — no session key, and no plan named; name the plan: debt $DEBT_SUB … <plan>."
        exit 3
      fi
      # A WRITER TAKES ONLY THE PLAN IT IS BOUND TO (wave-36 T13; D13, REQ-7 AC-7.3, census C25, A-orch-2).
      # `resolve_run`'s `none` arm hands an unbound session the root's newest plan by mtime, closed or
      # not, so the tick can DISARM; through it `debt adopt` at Step 1 wrote the predecessor's ledger.
      # The verb asks the binding itself: a `bound-*` verdict names this session's plan, anything else
      # refuses naming `bind`, and nothing is written.
      DEBT_BIND="$(session_run "$REPO_REAL" "$SESSION_ID" 2>/dev/null)" || :  # exit 2 is bound-closed, still bound
      case "$DEBT_BIND" in bound-*' '*) DEBT_PLAN="${DEBT_BIND#* }" ;; *) DEBT_PLAN="" ;; esac
      if [ -z "$DEBT_PLAN" ] || [ ! -f "$DEBT_PLAN" ]; then
        die "REFUSED — this session is bound to no plan, so debt $DEBT_SUB has no ledger of its own to write; bind its plan first (session-poker.sh bind <plan>), or name it: debt $DEBT_SUB … <plan>."
        exit 2
      fi
    fi
    if ! { declare -F proof_debt_items >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh" 2>/dev/null; }; } \
       || ! declare -F proof_debt_items >/dev/null 2>&1; then
      die "REFUSED — lib/proof.sh cannot be loaded, so the debt ledger cannot be read; reinstall the plugin."
      exit 2
    fi
    # THE ONE DEBT-LINE GRAMMAR (wave-36 T13; D13, AC-7.8): lib/debt.sh, which close-out and card.sh source too.
    if ! { declare -F debt_line_ok >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/debt.sh" ] && . "$BIONIC_LIB/debt.sh" 2>/dev/null; }; } \
       || ! declare -F debt_line_ok >/dev/null 2>&1; then
      die "REFUSED — lib/debt.sh cannot be loaded, so no debt line can be held to its grammar; reinstall the plugin."
      exit 2
    fi
    DEBT_ROOT="$(cd "$(project_root "${DEBT_PLAN%/*}")" 2>/dev/null && pwd -P)"
    [ -n "$DEBT_ROOT" ] || DEBT_ROOT="$REPO_REAL"
    DEBT_DOCS="$(docs_root "$DEBT_ROOT")"
    DEBT_FILE="$(proof_debt_ledger_path "$DEBT_ROOT" "$DEBT_PLAN")"
    DEBT_REL="${DEBT_FILE#"$DEBT_DOCS"/}"
    if [ "$DEBT_SUB" = list ]; then
      if [ ! -f "$DEBT_FILE" ]; then
        say "debt list — no ledger yet at $DEBT_REL"
        exit 0
      fi
      awk '!/^#/ && NF' "$DEBT_FILE"
      exit 0
    fi
    DEBT_ROWS=""; DEBT_RECREL=""
    if [ "$DEBT_SUB" = add ]; then
      case "$DEBT_A" in
        /*) DEBT_REC="$DEBT_A" ;;
        *)  DEBT_REC="$DEBT_DOCS/$DEBT_A"; [ -f "$DEBT_REC" ] || DEBT_REC="$REPO_REAL/$DEBT_A" ;;
      esac
      if [ ! -f "$DEBT_REC" ]; then
        die "REFUSED — no record at $DEBT_A; name it as proof-add does, record/<wave>/<file>."
        exit 2
      fi
      DEBT_RECREL="$DEBT_A"
      case "$DEBT_REC" in "$DEBT_DOCS"/*) DEBT_RECREL="${DEBT_REC#"$DEBT_DOCS"/}" ;; esac
      # ANY RECORD, A `reviewed:` LINE OR NOT (wave-36 T13; AC-7.2, C24): a reading's, a writer's, the
      # orchestrator's assumptions.md hole line, each read by the reading's own debt arm, `hole` a kind.
      if ! DEBT_ROWS="$(PROOF_DEBT_KINDS="$DEBT_KINDS" proof_record_debts "$DEBT_REC")"; then
        die "REFUSED — $DEBT_ROWS"
        exit 1
      fi
      DEBT_ROWS="$(printf '%s\n' "$DEBT_ROWS" | awk -F'\t' '$1 == "debt"')"
      if [ -z "$DEBT_ROWS" ]; then
        say "debt add — the record $DEBT_RECREL carries no debt: line; nothing added"
        exit 0
      fi
      # EACH LINE IS HELD TO THE GRAMMAR BEFORE ANY IS WRITTEN (AC-7.8): the line close-out would carry
      # for it, raised by this record, must parse, or the lot is refused naming it — a raised-by with a
      # space (A-orch-1's shape) is refused here, where it is written, and never reaches a continuation.
      DEBT_FROM="$(proof_plan_slug "$DEBT_PLAN")"
      DEBT_BADL="$(printf '%s\n' "$DEBT_ROWS" | while IFS="$(printf '\t')" read -r _dk _dkind _dcon _dsites _ddisp; do
        _dl="debt: $_dcon $_dkind \"$_dsites\" touches=0 raised-by=$DEBT_RECREL from=$DEBT_FROM"
        debt_line_ok "$_dl" || { printf '%s\n' "$_dl"; break; }
      done)"
      if [ -n "$DEBT_BADL" ]; then
        die "REFUSED — a debt: line of $DEBT_RECREL does not parse as a debt line: $DEBT_BADL; nothing added."
        exit 1
      fi
      mkdir -p "${DEBT_FILE%/*}" 2>/dev/null
    fi
    if [ "$DEBT_SUB" = adopt ]; then
      case "$DEBT_A" in
        /*) DEBT_REC="$DEBT_A" ;;
        *)  DEBT_REC="$DEBT_DOCS/$DEBT_A"
            [ -f "$DEBT_REC" ] || DEBT_REC="$REPO_REAL/$DEBT_A"
            [ -f "$DEBT_REC" ] || DEBT_REC="$PWD/$DEBT_A" ;;
      esac
      if [ ! -f "$DEBT_REC" ] || [ ! -r "$DEBT_REC" ]; then
        die "REFUSED — no readable continuation at $DEBT_A; name the file whose ## Deferrals carry the debt."
        exit 2
      fi
      # The carry shape (close-out's co_debts), read under the first `## Deferrals` outside a fence. A
      # `debt:` line there that the one grammar (lib/debt.sh `DEBT_LINE_ERE`, wave-36 T13) does not parse
      # is a BAD row, and one BAD row refuses the lot.
      DEBT_ROWS="$(DEBT_LINE_ERE="$DEBT_LINE_ERE" awk '
        { sub(/\r$/, "") }
        /^[ \t]*```/ { fence = !fence; next }
        fence { next }
        /^## / { s = ($0 ~ /^## Deferrals[ \t]*$/); next }
        s && /^debt:[ \t]/ {
          if ($0 !~ ENVIRON["DEBT_LINE_ERE"]) { print "BAD\t" $0; next }
          split($0, w, /[ \t]+/)
          q = index($0, "\""); r = substr($0, q + 1); e = index(r, "\""); sites = substr(r, 1, e - 1)
          split(substr(r, e + 1), t, /[ \t]+/)
          printf "debt\t%s\t%s\t%s\t%s\t%s\n", w[3], w[2], sites, substr(t[2], 9), substr(t[3], 11)
        }' "$DEBT_REC")"
      DEBT_BAD="$(printf '%s\n' "$DEBT_ROWS" | awk -F'\t' '$1 == "BAD" { print $2; exit }')"
      if [ -n "$DEBT_BAD" ]; then
        die "REFUSED — $DEBT_A carries a debt: line that does not parse; nothing adopted: $DEBT_BAD"
        exit 1
      fi
      if [ -z "$DEBT_ROWS" ]; then
        say "debt adopt — the continuation $DEBT_A carries no debt: line; nothing adopted"
        exit 0
      fi
      mkdir -p "${DEBT_FILE%/*}" 2>/dev/null
    fi
    if [ ! -d "${DEBT_FILE%/*}" ] || { [ "$DEBT_SUB" != add ] && [ "$DEBT_SUB" != adopt ] && [ ! -f "$DEBT_FILE" ]; }; then
      die "REFUSED — no debt ledger at $DEBT_REL; debt add writes it from a reading's debt: lines."
      exit 1
    fi
    launch_sync_lock "$DEBT_FILE.lock" yes; DEBT_LRC=$?
    if [ "$DEBT_LRC" != 0 ]; then
      die "WAITING — another writer held the debt ledger's lock ($DEBT_FILE.lock) for the whole wait; run the same command again."
      exit 75
    fi
    trap 'launch_sync_unlock; rm -f "$DEBT_FILE.new.$$"' EXIT
    DEBT_NEW="$DEBT_FILE.new.$$"
    case "$DEBT_SUB" in
      add)
        DEBT_SAID="$(PROOF_HAVE="$(proof_debt_items "$DEBT_FILE")" DEBT_RECREL="$DEBT_RECREL" DEBT_HEAD="$PROOF_DEBT_HEADER" awk -F'\t' -v out="$DEBT_NEW" '
          BEGIN { n = split(ENVIRON["PROOF_HAVE"], h, "\n"); for (i = 1; i <= n; i++) { split(h[i], c, "\t"); have[c[1] "\t" c[2]] = 1 } }
          { k = $3 "\t" $2
            if (k in have) { there++; print $3 " " $2 " already in the ledger"; next }
            have[k] = 1; added++
            line[added] = $3 " | " $2 " | " $4 " | raised-by " ENVIRON["DEBT_RECREL"] " | touches 0 | —"
            print $3 " " $2 " " $4 }
          END { for (i = 1; i <= added; i++) print line[i] > out; printf "%d added, %d already there", added, there }' <<< "$DEBT_ROWS")"
        if [ -f "$DEBT_FILE" ]; then cat "$DEBT_FILE"; else printf '%s\n' "$PROOF_DEBT_HEADER"; fi > "$DEBT_NEW.all" 2>/dev/null \
          && { [ ! -f "$DEBT_NEW" ] || cat "$DEBT_NEW" >> "$DEBT_NEW.all"; } && mv "$DEBT_NEW.all" "$DEBT_FILE" 2>/dev/null \
          || { rm -f "$DEBT_NEW.all"; die "REFUSED — the debt ledger at $DEBT_REL cannot be written."; exit 1; }
        printf '%s\n' "$DEBT_SAID" | while IFS= read -r _dl; do
          case "$_dl" in *' added, '*' already there') say "debt add — $_dl: $DEBT_REL" ;; *) say "debt add — $_dl" ;; esac
        done
        exit 0
        ;;
      adopt)
        # Rows are `debt <kind> <concept> <sites> <touches> <raised-by>`. The ledger keeps what it holds:
        # an item on concept and kind is there already and is not rewritten (A-T22.5), its touches its own.
        DEBT_SAID="$(PROOF_HAVE="$(proof_debt_items "$DEBT_FILE")" awk -F'\t' -v out="$DEBT_NEW" '
          BEGIN { n = split(ENVIRON["PROOF_HAVE"], h, "\n"); for (i = 1; i <= n; i++) { split(h[i], c, "\t"); have[c[1] "\t" c[2]] = 1 } }
          { k = $3 "\t" $2
            if (k in have) { there++; next }
            have[k] = 1; added++
            line[added] = $3 " | " $2 " | " $4 " | raised-by " $6 " | touches " $5 " | —" }
          END { for (i = 1; i <= added; i++) print line[i] > out; printf "%d adopted, %d already there", added, there }' <<< "$DEBT_ROWS")"
        if [ -f "$DEBT_FILE" ]; then cat "$DEBT_FILE"; else printf '%s\n' "$PROOF_DEBT_HEADER"; fi > "$DEBT_NEW.all" 2>/dev/null \
          && { [ ! -f "$DEBT_NEW" ] || cat "$DEBT_NEW" >> "$DEBT_NEW.all"; } && mv "$DEBT_NEW.all" "$DEBT_FILE" 2>/dev/null \
          || { rm -f "$DEBT_NEW.all"; die "REFUSED — the debt ledger at $DEBT_REL cannot be written."; exit 1; }
        say "debt adopt — $DEBT_SAID: $DEBT_REL"
        exit 0
        ;;
      touched|burn)
        DEBT_SAID="$(awk -v c="$DEBT_A" -v r="$DEBT_B" -v sub_="$DEBT_SUB" -v out="$DEBT_NEW" '
          { l = $0 }
          !/^#/ && NF && split($0, f, / \| /) == 6 && f[1] == c && index(f[6], "burned ") != 1 && f[5] ~ /^touches [0-9]+$/ {
            if (sub_ == "touched") { f[5] = "touches " (substr(f[5], 9) + 1); said = f[1] " " f[2] " " f[5] }
            else { f[6] = "burned " r; said = f[1] " " f[2] " burned " r }
            l = f[1]; for (i = 2; i <= 6; i++) l = l " | " f[i]
            print said
          }
          { print l > out }' "$DEBT_FILE")"
        if [ -z "$DEBT_SAID" ]; then
          die "REFUSED — no unburned item of the debt ledger at $DEBT_REL names $DEBT_A; debt list prints what it holds."
          exit 1
        fi
        mv "$DEBT_NEW" "$DEBT_FILE" 2>/dev/null \
          || { die "REFUSED — the debt ledger at $DEBT_REL cannot be written."; exit 1; }
        printf '%s\n' "$DEBT_SAID" | while IFS= read -r _dl; do say "debt $DEBT_SUB — $_dl"; done
        exit 0
        ;;
    esac
    ;;

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
    if [ "$LR_HH" = no ]; then
      landing_report "$(_wt_proofs_path "$LR_ROOT" "$LR_PLAN")" "$LR_ROOT" "$LR_ROWS"
      exit 0
    fi
    # THE HAND-HOLDS LINE sits under the landings line, above the rows (D17).
    LR_TEXT="$(landing_report "$(_wt_proofs_path "$LR_ROOT" "$LR_PLAN")" "$LR_ROOT" "$LR_ROWS")"
    printf '%s\n' "${LR_TEXT%%$'\n'*}"
    hand_holds_report "$(_wt_proofs_path "$LR_ROOT" "$LR_PLAN")" "$LR_ROOT" "$LR_PLAN"
    case "$LR_TEXT" in *$'\n'*) printf '%s\n' "${LR_TEXT#*$'\n'}" ;; esac
    exit 0
    ;;


  # THE LAUNCH SYNC (wave-26 T32; D4). Its reasoning is above the verbs, beside the functions it
  # runs. Silent, exit 0, wherever there is nothing it may write: no engagement, no bound open run,
  # a plan before Step 4 (`current:` a step below 4, or none), no roster, or a lock another writer
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
    # ONE LEDGER SHAPE (wave-31 T5; REQ-1 AC-1.2, D2): `current:` is a step number at every scale.
    # A value that is not one — the retired task-scale `T<n>` above all — is refused aloud, exit 1,
    # never skipped: the turn-end wall passes 0 and 75 only, so the plan's author is told. It is read
    # BEFORE the roster (wave-31 T43; A-orch-76), so a session with no confirmed launch is told too.
    LS_RAW="$(_fill_current_field "$LS_PLAN")"; LS_CUR="${LS_RAW%[ab]}"
    case "$LS_CUR" in
      '') exit 0 ;;
      *[!0-9]*)
        printf 'NOT-RECORDED — current: %s is not numeric; a plan in the retired task-scale shape is refused, not skipped\n' \
          "$(printf '%s' "$LS_RAW" | tr -d '[:cntrl:]')" >&2
        exit 1 ;;
    esac
    # A session that has confirmed no launch, or a plan before Step 4, has no launch to apply; a handoff
    # a later dispatch outdates is marked all the same, at any step (`handoff_mark_stale`, T29).
    LS_ROSTER="$LS_ROOT/.bionic/tmp/roster-${SESSION_ID}.state"
    LS_LAUNCH=yes
    [ "$LS_CUR" -ge 4 ] || LS_LAUNCH=no
    { [ -f "$LS_ROSTER" ] && [ ! -L "$LS_ROSTER" ] \
        && grep -qE '\|status=(confirmed|identified)\|' "$LS_ROSTER" 2>/dev/null; } || LS_LAUNCH=no
    if [ "$LS_LAUNCH" = no ]; then
      LS_AT="$(handoff_written_at "$LS_PLAN")"
      [ -n "$LS_AT" ] && [ -n "$(handoff_dispatches_since "$LS_PLAN" "$LS_ROOT/.bionic/tmp" "$LS_AT")" ] || exit 0
    fi
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
    LS_PROJECTED=no; LS_SAID=""; LS_FAILS=""; LS_HANDS=""
    if [ "$LS_LAUNCH" = yes ] && launch_sync_project "$PV_PLAN" "$PV_REPO" "$SESSION_ID" "$LS_ROSTER" \
      "$PV_REPO/.bionic/tmp/sweeper-${SESSION_ID}.state" "$PV_NEW"; then
      LS_PROJECTED=yes
    fi
    # WHAT CANNOT BE RECORDED PRINTS FIRST, so a refusal of the rest below cannot hide it.
    if [ -n "$LS_FAILS" ]; then
      printf '%s' "$LS_FAILS" | sed 's/^NOT-RECORDED /poker: NOT-RECORDED /'
      LS_RC=1
    fi
    # THE HANDOFF A LATER DISPATCH OUTDATES (T29), marked in the same write as the launches, or alone.
    LS_MARKED=no; LS_SRC="$PV_PLAN"; [ "$LS_PROJECTED" = yes ] && LS_SRC="$PV_NEW"
    if handoff_mark_stale "$PV_PLAN" "$LS_SRC" "$PV_REPO/.bionic/tmp" "$PV_NEW.2"; then
      mv -f "$PV_NEW.2" "$PV_NEW" && LS_MARKED=yes
    fi
    rm -f "$PV_NEW.2"
    if [ "$LS_PROJECTED" = yes ]; then
      LS_VIOL="$(units_validate "$PV_NEW" 2>&1)"
      if [ -n "$LS_VIOL" ]; then
        die "REFUSED — with these launches recorded, the ## Tasks table breaks the Task invariants; the plan is unchanged:"
        printf '%s\n' "$LS_VIOL" >&2
        exit 1
      fi
    fi
    if [ "$LS_PROJECTED" = yes ] || [ "$LS_MARKED" = yes ]; then
      [ "$LS_RC" = 0 ] && PV_RACE_RC=75   # a launch it could not record keeps exit 1
      LS_WHAT="$(printf '%s' "$LS_SAID" | awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $2 }')"
      LS_WHAT="${LS_WHAT:+$LS_WHAT recorded}"
      [ "$LS_MARKED" = no ] || LS_WHAT="${LS_WHAT:+$LS_WHAT, }the handoff marked stale"
      plan_verb_swap launch-sync "$LS_WHAT" writer
      LS_SWAPPED=yes
      printf '%s' "$LS_SAID" | sed 's/^/poker: /'
      [ "$LS_MARKED" = no ] || say "HANDOFF-STALE — ## Handoff now reads stale: a dispatch of this plan postdates it; rewrite it: bash ${HOOK_DIR}/session-poker.sh handoff"
    fi
    exit "$LS_RC"
    ;;

  # ---------- wait: THE RE-ENTRANT WAIT ON A DETACHED RUN (wave-30 T12; D6; AC-3.2, AC-3.3, AC-3.8) ----------
  #
  # The attach half of `booked.sh --detach`, by name, for a caller that is gone (a /clear, a stopped
  # agent, a call the harness moved to the background). It reads the run's record and never starts
  # anything, so two waits on one run are one run. It polls every BIONIC_RUN_POLL seconds (1 unless
  # set), never one long call, and prints a RUNNING line with the run's last progress line on the
  # first poll, whenever that line changes, and at least every 30 seconds. It exits with the run's
  # code once the run has one; 70 when the run is LOST (its pid gone, no end written: a kill, never a
  # timeout); 75 when `--for` ran out first, the run untouched. No session key is needed. A run that
  # ended 75 (the gate did not admit it inside its bound) is reported with the shim's one line first.
  wait)
    REPO_REAL="$(cd "$(project_root "$PWD")" 2>/dev/null && pwd -P)"
    [ -n "$REPO_REAL" ] || { die "REFUSED — cannot resolve the working directory."; exit 2; }
    if ! run_find "$REPO_REAL" "$WT_ARG"; then
      die "wait — no run named $WT_ARG: no roster row of this project carries a run for it, and there is no $REPO_REAL/.bionic/tmp/runs/$WT_ARG.log"
      exit 2
    fi
    WT_POLL="${BIONIC_RUN_POLL:-1}"
    case "$WT_POLL" in ''|*[!0-9.]*|.|*.*.*) WT_POLL=1 ;; esac
    WT_T0="$(now_epoch)"; WT_SAID=""; WT_SAID_AT=0
    while :; do
      run_read
      case "$RUN_STATE" in
        FINISHED)
          # A run the gate did not admit inside its bound ends 75 with the shim's one line in its log
          # (booked.sh, the detached side's ceiling; wave-31 T12, D10): the wait says what it waited
          # for and the command to run again, before the FINISHED line, whose text is unchanged.
          if [ "$RUN_RC" = 75 ]; then
            WT_NOTE="$(grep '^booked: the gate did not admit' "$RUN_LOG" 2>/dev/null | tail -n 1)"
            [ -z "$WT_NOTE" ] || say "$WT_NOTE"
          fi
          say "FINISHED $RUN_NAME run=$RUN_ID rc=$RUN_RC log=$RUN_LOG"; exit "$RUN_RC" ;;
        LOST)     say "LOST $RUN_NAME run=$RUN_ID last-written=$RUN_LAST_WRITTEN — its pid is gone and it wrote no end; log $RUN_LOG"; exit 70 ;;
      esac
      WT_NOW="$(now_epoch)"
      if [ "$WT_SAID_AT" = 0 ] || [ "$RUN_PROGRESS" != "$WT_SAID" ] || [ $((WT_NOW - WT_SAID_AT)) -ge 30 ]; then
        say "RUNNING $RUN_NAME run=$RUN_ID pid=$RUN_PID elapsed=${RUN_ELAPSED:-?}s progress: ${RUN_PROGRESS:-none yet}"
        WT_SAID="$RUN_PROGRESS"; WT_SAID_AT="$WT_NOW"
      fi
      if [ -n "$WT_FOR" ] && [ $((WT_NOW - WT_T0)) -ge "$WT_FOR" ]; then
        say "still RUNNING after ${WT_FOR}s — the run goes on; wait again: bash ${POKER_WORD} wait $RUN_NAME"
        exit 75
      fi
      sleep "$WT_POLL"
    done
    ;;

  # ---------- stop-run: STOPPING A DETACHED RUN ON PURPOSE (wave-30 T12; D6) ----------
  #
  # A detached run is in nobody's process group, so TaskStop and a killed caller cannot reach it; this
  # verb can. It sends TERM to the run's group (the shim's own traps then stop its command, end its
  # place at the gate, stamp and write its end), waits up to five seconds, and KILLs every process
  # group at or below the run's pid that is still there. When the run wrote no end (a KILL runs no
  # trap) it records one: `rc=137` on the log, `<log>.rc`, and the roster row's `run_rc=` through
  # `roster_mark_run`, so the run reads FINISHED rc=137, a stop, and not LOST. A run already ended or
  # LOST is reported and left alone. `--report-only` sends nothing.
  stop-run)
    REPO_REAL="$(cd "$(project_root "$PWD")" 2>/dev/null && pwd -P)"
    [ -n "$REPO_REAL" ] || { die "REFUSED — cannot resolve the working directory."; exit 2; }
    SR_FOUND=no
    if run_find "$REPO_REAL" "$SR_ARG"; then run_read; SR_FOUND=yes; fi
    # A GATE REQUEST, when the operand names no detached run that still runs (wave-36 T11; D8): a request id,
    # or the name of a holder parked in `gate_ask` or running under an admission.
    if [ "$SR_FOUND" = no ] || [ "$RUN_STATE" != RUNNING ]; then
      stop_run_request "$SR_ARG"; _sr_rc=$?
      if [ "$_sr_rc" -eq 2 ]; then
        die "stop-run — $SR_ARG holds more than one open gate request ($SR_REQS); name the one to stop by its id"
        exit 2
      fi
      if [ "$_sr_rc" -eq 0 ]; then stop_run_gate "$SR_REQ"; exit $?; fi
    fi
    if [ "$SR_FOUND" = no ]; then
      die "stop-run — no run named $SR_ARG: no roster row of this project carries a run for it, there is no $REPO_REAL/.bionic/tmp/runs/$SR_ARG.log, and no gate request is $SR_ARG or held by it"
      exit 2
    fi
    case "$RUN_STATE" in
      FINISHED) say "stop-run $RUN_NAME run=$RUN_ID — FINISHED rc=$RUN_RC; nothing to stop"; exit 0 ;;
      LOST)     say "stop-run $RUN_NAME run=$RUN_ID — LOST last-written=$RUN_LAST_WRITTEN; no process of it is left to stop"; exit 0 ;;
    esac
    if [ "$SR_REPORT_ONLY" = yes ]; then
      say "stop-run $RUN_NAME run=$RUN_ID pid=$RUN_PID — RUNNING; would TERM its process group, then KILL every group below it still alive after 5 s (report-only: nothing was sent)"
      exit 0
    fi
    # NEVER THIS CALL'S OWN GROUP: whoever runs the verb (a test, close-out, the operator's shell) is
    # not the run, whatever a pid table says about who started whom.
    SR_SELF="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
    SR_GROUPS="$(run_groups "$RUN_PID")"
    kill -TERM -- "-$RUN_PID" 2>/dev/null || kill -TERM "$RUN_PID" 2>/dev/null
    _sr_i=0
    while [ "$_sr_i" -lt 50 ] && run_live "$RUN_PID" "$RUN_LOG"; do sleep 0.1; _sr_i=$((_sr_i + 1)); done
    SR_HOW="TERM"
    if run_live "$RUN_PID" "$RUN_LOG"; then
      SR_GROUPS="$SR_GROUPS
$(run_groups "$RUN_PID")"
      for _sr_g in $(printf '%s\n' "$SR_GROUPS" | sort -u); do
        case "$_sr_g" in ''|0|1|*[!0-9]*) continue ;; esac
        [ "$_sr_g" != "$SR_SELF" ] || continue
        kill -KILL -- "-$_sr_g" 2>/dev/null
      done
      kill -KILL "$RUN_PID" 2>/dev/null
      SR_HOW="TERM, then KILL"
    fi
    _sr_i=0
    while [ "$_sr_i" -lt 30 ] && [ ! -s "$RUN_LOG.rc" ]; do sleep 0.1; _sr_i=$((_sr_i + 1)); done
    SR_RC=""; { read -r SR_RC < "$RUN_LOG.rc"; } 2>/dev/null
    case "$SR_RC" in
      ''|*[!0-9]*)
        [ -z "$(tail -c 1 "$RUN_LOG" 2>/dev/null)" ] || printf '\n' >> "$RUN_LOG"
        printf 'rc=137\n' >> "$RUN_LOG"
        printf '137\n' > "$RUN_LOG.rc"
        if [ -n "$RUN_ROSTER" ] && [ -z "$RUN_ROW_RC" ]; then
          roster_mark_run "$RUN_ROSTER" "$RUN_NAME" "$RUN_LOG" run_rc=137 "run_ended_at=$(iso_now)" 2>/dev/null || :
        fi
        say "stop-run $RUN_NAME run=$RUN_ID pid=$RUN_PID — stopped ($SR_HOW); it wrote no end, so rc=137 was recorded for it" ;;
      *)
        say "stop-run $RUN_NAME run=$RUN_ID pid=$RUN_PID — stopped ($SR_HOW); the run wrote its own end, rc=$SR_RC" ;;
    esac
    # THE ACT IS RECORDED (wave-36 T11; D8): one ev=stop-run in the bound run's landing record, as for a request.
    _sr_sid="$(session_id 2>/dev/null)" || _sr_sid=""
    stop_run_record "run=$RUN_ID" "name=$RUN_NAME" "by=${_sr_sid:-none}" "why=${SR_WHY:--}" || :
    exit 0
    ;;

  # ---------- regression-runs: THE FULL RUNS, COUNTED FROM THE RECORDS (wave-30 T12; D7d, Δ6d; AC-4.6) ----------
  #
  # The count is `regression_runs_count`'s: every ended run on this project's rosters whose command
  # is the full runner. Bare, it prints `poker: regression-runs=<n>` and needs no session. `--write`
  # puts the count in the bound plan's `regression-runs:` header through the plan-verb transaction,
  # and only when the plan carries the field and holds another value: a hand-typed number does not
  # survive it. The tick runs `--write` when its own reading of the header differs from the count,
  # so the value is the landing's, never a hand's. The one change is a number in one header line, so
  # the copy is judged here and needs no dry commit.
  regression-runs)
    REPO_REAL="$(cd "$(project_root "$PWD")" 2>/dev/null && pwd -P)"
    [ -n "$REPO_REAL" ] || { die "REFUSED — cannot resolve the working directory."; exit 2; }
    RR_N="$(regression_runs_count "$REPO_REAL")"
    if [ "$RR_WRITE" = no ]; then say "regression-runs=$RR_N"; exit 0; fi
    plan_verb_open regression-runs
    RR_HAVE="$(plan_frontmatter_get "$PV_PLAN" regression-runs)"
    [ -n "$RR_HAVE" ] && [ "$RR_HAVE" != "$RR_N" ] || exit 0
    if ! RR_N="$RR_N" awk '
      NR == 1 && $0 == "---" { f = 1; print; next }
      f && $0 == "---" { f = 0; print; next }
      f && !done && /^[[:space:]]*regression-runs[[:space:]]*:/ { print "regression-runs: " ENVIRON["RR_N"]; done = 1; next }
      { print }
      END { if (!done) exit 1 }' "$PV_PLAN" > "$PV_NEW" 2>/dev/null; then
      die "REFUSED — $PV_PLAN has no regression-runs: line in its leading frontmatter; the plan is unchanged."
      exit 1
    fi
    plan_verb_swap regression-runs "regression-runs: $RR_N" judged
    say "regression-runs — the plan header read $RR_HAVE and the run records count $RR_N: $RR_N written to $PV_PLAN"
    exit 0
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
    # ONE REGRESSION STATE PER TICK (wave-26 T64). The schedule and the change fingerprint below each
    # parse the table under their own `units_memoised`; this names the one file both keep the
    # regression state in (lib/units.sh `_units_floor_state`), so a tick runs `proof_state` once.
    [ -z "$TICK_BUF" ] || _UNITS_MEMO_FLOOR="$TICK_BUF.floor"
    TICK_DIGEST=""; TICK_UNCHANGED=no; TICK_SINCE=""; TICK_DECIDED=""; TICK_DUTY=owed; TICK_CHANGE=""; TICK_CHANGE_STORE=""
    TICK_PLAN_CUR=""; TICK_PLAN_ROWS=""
    TICK_GATE_KEYS=""; TICK_GATE_NEW=""; TICK_GATE_FIELD=""; TICK_LANDINGS=""; TICK_RUNS_LINES=""; TICK_RUNS_KEY=""
    TICK_DIGEST_FILE="$(tick_digest_file "$SESSION_ID")" || TICK_DIGEST_FILE=""
    TICK_PVER="$(tick_digest_field "$TICK_DIGEST_FILE" prompt_version)"
    TICK_REARM=""
    # ONE RESTART LINE, FROM DOCTOR'S READER (wave-35 T5; REQ-4 AC-4.5; D13). The CLI holds hooks.json,
    # the skills, the role files and the commands as they were at its start; doctor.sh `--restart-lines`
    # is the one comparison, and the tick prints its own session's line, if any, above everything else
    # on every tick, changed or unchanged. From wave-36 T2 (D7, AC-1.3) the comparison is content: the
    # session's load record against the tree a restart loads, one line naming the classes that moved
    # (`<pid> <sid> <started> <classes> <reloaded-since|->`), and `or reloaded since <ISO>` when the
    # registry installed after the record was written.
    TICK_RESTART=""
    TICK_RESTART_ROW="$(bash "$BIONIC_LIB/../doctor.sh" --restart-lines 2>/dev/null \
      | awk -F'\t' -v s="$SESSION_ID" 'NF >= 5 && $2 == s { print; exit }')"
    if [ -n "$TICK_RESTART_ROW" ]; then
      IFS=$'\t' read -r _tr_pid _ _ _tr_classes _tr_reload <<< "$TICK_RESTART_ROW"
      if [ "${_tr_reload:--}" != - ]; then
        TICK_RESTART="restart needed — ${_tr_classes} changed after this session loaded them, or reloaded since ${_tr_reload} (pid ${_tr_pid}): exit claude and start it again"
      else
        TICK_RESTART="restart needed — ${_tr_classes} changed after this session loaded them (pid ${_tr_pid}): exit claude and start it again"
      fi
    fi
    case "$TICK_PVER" in ''|*[!0-9]*) TICK_PVER_N=0 ;; *) TICK_PVER_N="$TICK_PVER" ;; esac
    if [ "$TICK_PVER_N" -lt "$PATROL_PROMPT_VERSION" ]; then
      TICK_REARM="poker: note: re-arm the Patrol — its prompt is v=${TICK_PVER:-unrecorded} and this poker prints v=${PATROL_PROMPT_VERSION}: replace the bionic-patrol job with one carrying the output of \`bash ${POKER_WORD} prompt\`, then run \`bash ${POKER_WORD} arm\`"
    fi
    tick_emit() {
      local rc=$?
      [ -n "$TICK_BUF" ] || exit "$rc"
      exec 1>&3 3>&-
      [ -z "${TICK_RESTART:-}" ] || say "$TICK_RESTART"
      if [ -n "$TICK_DIGEST" ] && [ -n "$TICK_REARM" ]; then
        printf '%s\n' "$TICK_REARM"
      fi
      if [ "$TICK_UNCHANGED" = yes ]; then
        # EVERY STANDING HOLD RIDES THE UNCHANGED TICK (wave-35 T5; REQ-4 AC-4.4; D13). The backstop runs
        # on every tick and says its NOT-LANDED lines into the buffer; an equal digest means the world
        # did not move, not that the duty is paid, so the holds it re-found print above the one line.
        /usr/bin/grep '^poker: NOT-LANDED ' "$TICK_BUF" 2>/dev/null
        say "unchanged since ${TICK_SINCE} — decision=${TICK_DECIDED}"
      else
        # THE RUN'S LANDING LINE PRINTS IN THE RE-ARM SLOT, ABOVE THE BUFFER (wave-28 T14, T62, T68; D18, AC-10.4):
        # the buffer ends with the decision line, which is the tick's last line, so this line is printed before it
        # and never after. A landing moves no decision (RP4), so it never makes a tick changed: the line shows on the
        # ticks that print in full for another reason, and an `unchanged` tick stays the one line the Patrol ends on.
        [ -z "$TICK_LANDINGS" ] || say "$TICK_LANDINGS"
        [ -z "${TICK_RUNS_LINES:-}" ] || printf '%s\n' "$TICK_RUNS_LINES"
        cat "$TICK_BUF" 2>/dev/null
        # A START IS TOLD BY THE TICK THAT PRINTED ITS LINE (wave-27 T37; review pass 36 S1).
        [ -z "${US_TOLD_PENDING:-}" ] || printf '%s' "$US_TOLD_PENDING" >> "$ROSTER_FILE" 2>/dev/null
      fi
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
    # task list, so this line is all the rule has (advice: no wall reads it since wave-31 T32): it is also owed when the
    # plan's `current:` was 3 at the last digest and is 4 now, or its row count has grown, and
    # it is owed on a QUIET tick too (a plan at approval has nothing open yet).
    # WHICH MOVE IT WAS (wave-27 T37; review pass 8 F2) is TICK_RECONCILE, `step4` or `grew`: the
    # RECONCILE line says it and names the rebuild, and the digest keeps it as `reconcile=` (read by
    # no wall since wave-31 T32; D6: the line is advice). A move into Step 4 is named first when
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
          # THE RUNS (wave-30 T12): the full-run count and each live run of this roster, by name and id.
          [ -z "${TICK_RUNS_KEY:-}" ] || printf '%s\n' "$TICK_RUNS_KEY"
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
    #
    # AND THE READY ROWS BEHIND THE GAP (wave-28 T74; A-orch-226). The rows the width parked (`WAIT <id> — ready; no
    # writer slot free`) are named too, because declining every FILL row frees their slot and the stop wall then
    # asks for them: one decline answers the set the wall counts. The `poker: FILL <ids>` line keeps its own ids.
    tick_fill_sentence() {
      say "FILL — ${SCHED_FILL} named for dispatch; the decision line carries them${SCHED_BEHIND:+ · behind the gap: ${SCHED_BEHIND} — a decline of a FILL row frees their slot; dispatch or decline them in the same turn}."
    }

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
    # The recorder's detached call has a log of its own; its failure is told once, outside the held output, so an
    # unchanged tick still says it (wave-36 T12; D13, AC-7.1).
    if [ -n "$TICK_BUF" ]; then tick_launch_sync_failed "$REPO_REAL" "$SESSION_ID" >&3
    else tick_launch_sync_failed "$REPO_REAL" "$SESSION_ID"; fi

    # ---------- THE LINE'S STANDING REDS AND STALLED ENTRIES, EACH TOLD ONCE (wave-28 T5; D8) ----------
    #
    # `ready` (lib/line.sh) appends `standing` when a red fails at the accepted head too, so the
    # branch's and not a row's, and `stalled` when an entry's suite twice gave no verdict and `ready`
    # exited 70. The first tick that reads one off the bound plan's landing record prints it as a note,
    # with its logs; the event line then goes into `.bionic/tmp/line-told-<sid>.state` and is never
    # printed again. A note enters the decision's hash, so the tick that tells one prints in full.
    resolve_run "$REPO_REAL" "$SESSION_ID"

    # ---------- THE RUNS: regression-runs AND EVERY LIVE RUN OF THIS ROSTER (wave-30 T12; D6, D7d) ----------
    #
    # `poker: regression-runs=<n>` is the count of full-runner runs the project's rosters record
    # (REQ-4 AC-4.6, `regression_runs_count`), and a `poker: RUNNING <name> run=<id> pid=<pid>
    # elapsed=<s>s progress: <line>` line names each row of this roster whose detached run is alive,
    # with the run's last progress line (AC-3.8). Both print above the buffer on every tick that
    # prints in full, as the landing line does, and both enter the decision's hash (TICK_RUNS_KEY): a
    # new full run, or a run starting or ending, is news, so the tick after it prints in full, and an
    # unchanged tick stays the one line it is (AC-4.9 of wave-24). THE HEADER: when the bound plan's
    # `regression-runs:` holds another number, the tick runs `regression-runs --write`, the
    # transaction, in a child as it runs launch-sync: a hand-typed value does not outlive the tick.
    TICK_RR="$(regression_runs_count "$REPO_REAL")"
    TICK_RUNS_LINES="poker: regression-runs=$TICK_RR"
    TICK_RUNS_KEY="regression-runs=$TICK_RR"
    if [ -f "$ROSTER_FILE" ] && [ ! -L "$ROSTER_FILE" ]; then
      for TR_NAME in $(awk -F'|' '/[|]run_log=/ { for (i = 1; i <= NF; i++) if (index($i, "name=") == 1) print substr($i, 6) }' "$ROSTER_FILE" | LC_ALL=C sort -u); do
        run_load_row "$(run_row_of "$ROSTER_FILE" "$TR_NAME")" "$ROSTER_FILE" || continue
        run_read
        [ "$RUN_STATE" = RUNNING ] || continue
        TICK_RUNS_LINES="$TICK_RUNS_LINES
poker: RUNNING $TR_NAME run=$RUN_ID pid=$RUN_PID elapsed=${RUN_ELAPSED:-?}s progress: ${RUN_PROGRESS:-none yet}"
        TICK_RUNS_KEY="$TICK_RUNS_KEY
RUNNING $TR_NAME $RUN_ID"
      done
    fi
    if [ "$POKER_RUN_OPEN" = yes ] && [ -f "$POKER_RUN_PLAN" ]; then
      TICK_RR_HAVE="$(plan_frontmatter_get "$POKER_RUN_PLAN" regression-runs)"
      if [ -n "$TICK_RR_HAVE" ] && [ "$TICK_RR_HAVE" != "$TICK_RR" ]; then
        ( cd "$REPO_REAL" && CLAUDE_CODE_SESSION_ID="$SESSION_ID" "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" regression-runs --write 2>&1 ) || :
      fi
    fi
    LT_TOLD="$REPO_REAL/.bionic/tmp/line-told-${SESSION_ID}.state"
    LT_REC=""
    [ -z "$POKER_RUN_PLAN" ] \
      || LT_REC="$(docs_root "$REPO_REAL" 2>/dev/null)/record/$(proof_plan_slug "$POKER_RUN_PLAN")/landing-proofs.log"
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
    # It is printed by the exit trap above the buffer, in the re-arm slot, so the decision stays the last line, and it enters no hash.
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
    # THE GATE ITEM'S CLOSER (wave-33 T12; REQ-2 AC-2.3, D2): a `gate:<key>` item on the person's
    # ledger is closed when the gate is no longer raised, which is when its key is not in the keys
    # just read (`gate_raised=` for the next digest). A request that left the gate file, or a gate
    # file that is gone, closes its item; a request still in the file keeps its item, and the
    # refused-file branch above kept the digest's own keys, so a symlink closes nothing. Silent,
    # never fatal, and a library without owed.sh does nothing.
    tick_gate_close() {
      local gkey
      declare -F owed_list >/dev/null 2>&1 || return 0
      declare -F owed_close >/dev/null 2>&1 || return 0
      for gkey in $(OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_list 2>/dev/null | cut -f1 | /usr/bin/grep '^gate:'); do
        case ",${TICK_GATE_KEYS}," in *",${gkey#gate:},"*) continue ;; esac
        OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_close "$gkey" "gate cleared" >/dev/null 2>&1
      done
      return 0
    }
    tick_gate_close
    # THE FIELD: how many requests this tick raises, then their categories sorted and once each,
    # `gate=2:credentials,leaves-the-machine`. The commands are on the GATE lines, not here.
    if [ -n "$TICK_GATE_NEW" ]; then
      TICK_GATE_FIELD="$(printf '%s\n' "$TICK_GATE_NEW" | awk -F'\t' '{ print $4 }' | LC_ALL=C sort -u \
        | awk -v n="$(printf '%s\n' "$TICK_GATE_NEW" | grep -c .)" '{ c = c (NR > 1 ? "," : "") $0 } END { printf "%d:%s", n, c }')"
    fi
    # THE GATE LINES, printed by whichever arm decides, after its tick_conclude: one sentence that
    # says what the turn owes, then one line per request this tick raises, asker, category and
    # command head. A request already raised prints nothing; the file still holds it.
    #
    # EACH GATE LINE IS OWED TO THE PERSON (wave-33 T11; REQ-2 AC-2.3, D2): the request opens
    # `gate:<key>` on the person's ledger, the key `gate_raised=` keeps, carrying the line printed,
    # and the tick sends the gate items it opened through the one sender, once each. The send is
    # silent and never fatal, so the lines above and the exit code are what they were.
    tick_gate_report() {
      local k st a c h
      [ -n "$TICK_GATE_NEW" ] || return 0
      say "gate act — ${TICK_GATE_FIELD%%:*} reserved request(s) bionic denied: put each GATE line below to the human once, through the human's own notify channel, and do not perform it."
      while IFS="$(printf '\t')" read -r k st a c h; do
        [ -n "$k" ] || continue
        say "GATE ${a} — ${c}: ${h}"
        if declare -F owed_open >/dev/null 2>&1; then
          OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_open "gate:$k" "gate act: ${c}" "poker: GATE ${a} — ${c}: ${h}" >/dev/null 2>&1
        fi
      done <<EOF
$TICK_GATE_NEW
EOF
      if declare -F owed_send >/dev/null 2>&1; then
        OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_send gate: >/dev/null 2>&1
      fi
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

    # ---------- THE BACKSTOP: A RECORD ROW WHOSE AGENT ENDED WITHOUT LANDING IT (wave-33 T6; REQ-3 AC-3.1; D5) ----------
    #
    # A test, verify or review row lands by its own agent's last act, `deliver`. When the agent
    # ended without it, its roster row reads MET (the deliverable landed and the agent said so)
    # while its `## Tasks` row is still `active` under that name (launch-sync wrote the name into
    # the agent cell). The tick lands such a row through `deliver` itself, run as a child as
    # launch-sync is above, so the one landing writer and every check `deliver` makes stand: a row
    # whose artifact is absent is refused there, left active, and reported here with the refusal.
    # Only a row with no tree whose Files write nothing the head carries is asked; a row with a
    # tree lands through `ready`. MET is read off this tick's one verdict read, acked or not: the
    # ack closes the agent, never the row. A landed row is no longer `active`, so it is asked once.
    if [ "${POKER_RUN_OPEN:-}" = yes ] && [ -n "${POKER_RUN_PLAN:-}" ] && [ -f "$POKER_RUN_PLAN" ]; then
      TICK_MET="$(printf '%s\n' "$VERDICT_OUT" | awk -F'|' '$1 == "landing-verdict/v1" { n = ""; s = ""
          for (i = 2; i <= NF; i++) { if ($i ~ /^name=/) n = substr($i, 6); else if ($i ~ /^state=/) s = substr($i, 7) }
          if (s == "MET" && n != "") printf " %s", n }
        END { printf " " }')"
      if [ "$TICK_MET" != " " ]; then
        # An empty cell is printed `-`: a tab is white space to `read`, so two in a row would shift a field.
        while IFS=$'\t' read -r BS_ID BS_AGENT BS_FILES BS_WT; do
          [ -n "$BS_ID" ] || continue
          case "$BS_WT" in *[A-Za-z0-9]*) continue ;; esac
          ! units_writes_head "$BS_FILES" || continue
          # AN UNREAD RULING HOLDS THE ROW AND PAGES THE PERSON (wave-34 T4; REQ-3 AC-3.1, AC-3.2; D13, D4
          # option 1). The writer has ended, so a ruling it never read is read by nobody here: the backstop
          # reads the rulings of the row's writer (`row_writer`, `ready`'s answer) without stamping them
          # (lib/roster.sh `ruling_unread`), lands nothing, and opens `ruling:<id>` on the person's ledger,
          # which an open item keeps as it is, so one item and one send per ruling however many ticks hold
          # the row. The row holds until a writer reads the ruling, or the row is re-dispatched or dropped
          # (`tick_ruling_close` below). deliver's own guard stamps: it is the writer's, who reads it.
          if row_writer "$ROSTER_FILE" "$POKER_RUN_PLAN" "$BS_ID" "$BS_AGENT" \
             && BS_RULINGS="$(ruling_unread "$ROSTER_FILE" "$ROW_WRITER")" && [ -n "$BS_RULINGS" ]; then
            BS_IDS="$(printf '%s\n' "$BS_RULINGS" | sed -n 's/^bionic ruling \([^ ]*\) .*/\1/p')"
            BS_LINE="NOT-LANDED $BS_ID — $(clean "$ROW_WRITER") ended (MET) with an orchestrator ruling unread ($(printf '%s\n' "$BS_IDS" | paste -sd, - | sed 's/,/, /g')); the row holds until a writer reads it: re-dispatch the row, or drop it"
            say "$BS_LINE"
            if declare -F owed_open >/dev/null 2>&1; then
              for BS_RID in $BS_IDS; do
                OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_open "ruling:$BS_RID" "ruling unread: $BS_ID" "poker: $BS_LINE" >/dev/null 2>&1
              done
            fi
            continue
          fi
          BS_RC=0
          BS_OUT="$( cd "$REPO_REAL" && CLAUDE_CODE_SESSION_ID="$SESSION_ID" "${BASH:-bash}" "$HOOK_DIR/session-poker.sh" deliver "$BS_ID" 2>&1 )" || BS_RC=$?
          if [ "$BS_RC" -eq 0 ]; then
            say "LANDED $BS_ID — $(clean "$BS_AGENT") ended (MET) without deliver; the tick landed its row through deliver: $(clean "$(printf '%s\n' "$BS_OUT" | sed -n 's/^poker: deliver — [^:]*: //p' | head -1)")"
          else
            say "NOT-LANDED $BS_ID — $(clean "$BS_AGENT") ended (MET) without deliver, and deliver refused it: $(clean "$(printf '%s\n' "$BS_OUT" | /usr/bin/grep -m1 'REFUSED' | sed 's/^poker: //')")"
          fi
        done <<BACKSTOP_ROWS
$(units_rows "$POKER_RUN_PLAN" 2>/dev/null | awk -F'\t' -v met="$TICK_MET" '$10 == "active" && $5 != "" && index(met, " " $5 " ") { printf "%s\t%s\t%s\t%s\n", $1, $5, ($9 == "" ? "-" : $9), ($11 == "" ? "-" : $11) }')
BACKSTOP_ROWS
        if declare -F owed_send >/dev/null 2>&1; then
          OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_send ruling: >/dev/null 2>&1
        fi
      fi
      # THE PAGE CLOSES WHEN NO ROW WAITS ON IT (wave-34 T4; REQ-3 AC-3.1, D13). An open `ruling:<id>`
      # stands while its ruling is unread and some active row's writer (`row_writer`, the backstop's own
      # answer) is the ruling's writer. A ruling shown closes its item where it is stamped (lib/roster.sh
      # `ruling_page_close`); this closes the rest at the next tick: the row re-dispatched to another
      # writer, dropped, or landed. Silent, never fatal; nothing is read while no ruling item is open.
      tick_ruling_close() {
        local keys rk fold writers=" " r a rid w x1 x2 x3 s rest why
        declare -F owed_list >/dev/null 2>&1 && declare -F owed_close >/dev/null 2>&1 || return 0
        keys="$(OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_list 2>/dev/null | cut -f1 | /usr/bin/grep '^ruling:')" || return 0
        while IFS=$'\t' read -r r a; do
          [ -n "$r" ] || continue
          row_writer "$ROSTER_FILE" "$POKER_RUN_PLAN" "$r" "$a" && [ -n "$ROW_WRITER" ] && writers="${writers}${ROW_WRITER} "
        done <<TICK_RULING_ROWS
$(units_rows "$POKER_RUN_PLAN" 2>/dev/null | awk -F'\t' '$10 == "active" { print $1 "\t" $5 }')
TICK_RULING_ROWS
        fold="$(ruling_fold "$ROSTER_FILE")"
        for rk in $keys; do
          IFS="$RULING_US" read -r rid w x1 x2 x3 s rest <<< "$(printf '%s\n' "$fold" | awk -F"$RULING_US" -v id="${rk#ruling:}" '$1 == id { print; exit }')"
          [ -n "$rid" ] || continue
          if [ -n "$s" ]; then
            why="ruling read"
          else
            case "$writers" in *" $w "*) continue ;; esac
            why="no active row is $w's: re-dispatched, dropped or landed"
          fi
          OWED_ROOT="$REPO_REAL" OWED_SID="$SESSION_ID" owed_close "$rk" "$why" >/dev/null 2>&1
        done
        return 0
      }
      tick_ruling_close
    fi

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
    SCHED_BEHIND=""

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
    # review-b finding (c)/N-2). An empty field, or a value that is not a step number (the
    # retired task-scale `T<n>` among them), is a case where this gate cannot tell which
    # step the run is on — and falling through to the readiness/budget checks on THAT basis
    # is DOUBT-then-FILL: the one shape this arm exists to prevent, measured live on a plan
    # whose `current:` carried a sub-step letter (`3b`) that the old digit-only read
    # rejected as unreadable and then filled anyway. So this differs from an unreadable
    # RUNG, which falls back to the ceiling — there is no safe fallback for "did Step 3
    # pass," only "no."
    #
    # ONE LEDGER SHAPE (wave-31 T5; D2): `fill_step_token` answers the step number or nothing,
    # at every scale, and the withhold above is that empty answer.
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
      #
      # A DECLINE ENDS WHEN ROOM APPEARS (wave-37 T18; REQ-11 AC-11.4; D13). The reader is told the
      # gate's `room=` answer (gate_report, above) and the writer slots free to ALL the ready writer rows,
      # the declined ones too, sized by the same `fill_gate_width` the offer below uses. It holds the decline
      # only while room is no or no slot is free (`fill_decline_holds`, lib/fill.sh); with room and a slot
      # the tick records the lapse once, says so, and the rows are offered below like any ready row.
      SCHED_CAP="$(fill_cap "$SCHED_PLAN")"
      SCHED_FREE_PRE=0
      if [ "${SCHED_GATE_ROOM:-}" = yes ]; then
        SCHED_FREE_PRE="$(fill_gate_width "$TICK_OCCUPIED" "$SCHED_OWED" \
          "$(fill_ready_tagged "$SCHED_PLAN" 2>/dev/null | awk -F'\t' '$2 == "w" { n++ } END { print n + 0 }')" "$SCHED_CAP")"
        case "$SCHED_FREE_PRE" in ''|*[!0-9]*) SCHED_FREE_PRE="$TICK_OCCUPIED" ;; esac
        SCHED_FREE_PRE=$(( SCHED_FREE_PRE - TICK_OCCUPIED ))
        [ "$SCHED_FREE_PRE" -lt 0 ] && SCHED_FREE_PRE=0
      fi
      SCHED_LED="$(fill_ledger_path "$REPO_REAL" "$SCHED_PLAN" 2>/dev/null)"
      SCHED_LAPSE="$(fill_decline_lapsing "$SCHED_LED" "$SESSION_ID" "$(_fill_current_field "$SCHED_PLAN")" "${SCHED_GATE_ROOM:-}" "${SCHED_FREE_PRE:-}")"
      if [ -n "$SCHED_LAPSE" ]; then
        IFS=$'\037' read -r SCHED_SD_AT SCHED_SD_WHY SCHED_SD_IDS <<< "$SCHED_LAPSE"
        SCHED_LAPSE_LINE="fill-ledger/v1|at=$(iso_now)|session=${SESSION_ID}|turn=|current=$(_fill_current_field "$SCHED_PLAN" | tr '|' ' ')|state=lapsed"
        SCHED_LAPSE_LINE="${SCHED_LAPSE_LINE}|ceiling=${SCHED_WRITERS:-}|width=|open=|free=${SCHED_FREE_PRE}|ready=|launched=|declined=|missed=0|idle=|room=${SCHED_GATE_ROOM}"
        SCHED_LAPSE_LINE="${SCHED_LAPSE_LINE}|lapsed-at=${SCHED_SD_AT}|lapsed=${SCHED_SD_IDS// /,}|lapsed-why=${SCHED_SD_WHY//|/ }"
        if [ -n "$SCHED_LED" ] && [ ! -L "$SCHED_LED" ] && printf '%s\n' "$SCHED_LAPSE_LINE" >> "$SCHED_LED" 2>/dev/null; then
          say "fill-declined lapsed — room=${SCHED_GATE_ROOM}, ${SCHED_FREE_PRE} writer slot(s) free; ${SCHED_SD_IDS// /,} asked again (declined since ${SCHED_SD_AT}: $(clean "$SCHED_SD_WHY"))"
        else
          say "fill-declined lapsed — room=${SCHED_GATE_ROOM}, ${SCHED_FREE_PRE} writer slot(s) free; ${SCHED_SD_IDS// /,} asked again, but the ledger ${SCHED_LED:-has no path} could not be written, so the lapse is not recorded"
        fi
      fi
      SCHED_SD="$(fill_standing_decline "$SCHED_LED" "$SESSION_ID" "$(_fill_current_field "$SCHED_PLAN")" "${SCHED_GATE_ROOM:-}" "${SCHED_FREE_PRE:-}")"
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
            LR_REC="$(docs_root "$REPO_REAL" 2>/dev/null)/record/$(proof_plan_slug "$SCHED_PLAN")/landing-proofs.log"
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
