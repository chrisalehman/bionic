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
#     bash <plugin-root>/hooks/session-poker.sh task-add <id> … record the birth of a row an edit added to the bound plan (writes no plan)
#     bash <plugin-root>/hooks/session-poker.sh amend …    widen a live row's Files/Suites/Re-executes (writes the roster)
#     bash <plugin-root>/hooks/session-poker.sh rule <writer> '<text>' [--words '<the user's words>'] | ruling-ack <id> | rulings <writer>
#                                                      a binding ruling for a live writer, its acknowledgement, its state (writes the roster)
#     bash <plugin-root>/hooks/session-poker.sh current <N> [--check]   advance the run's step, judged at it first (writes the run's log)
#     bash <plugin-root>/hooks/session-poker.sh proof-add <kind> <evidence>   a proof line naming the head its evidence read (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh proof-add review <record> --question <q> --reader <name>   a review: that proof line with its question, reviewer, result and scope
#     bash <plugin-root>/hooks/session-poker.sh order '<the user's words>' | order lift   the user's order every suite obeys, or its end: an order event with the words in the bound run's log (record/orders.log with no run bound)
#     bash <plugin-root>/hooks/session-poker.sh waive <question|all|AC-id> '<reply>'   the user's waiver of a review question, all three, or a criterion (writes the run's log)
#     bash <plugin-root>/hooks/session-poker.sh release-check   run the project's declared release check over the release range; its log and its check fact, failing or not (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh floor-run   run the project's regression (its floor: command, else tests/run.sh, whole, held to the full-run rules) in the working checkout and log it for proof-add floor (writes a log under record/, never the plan)
#     bash <plugin-root>/hooks/session-poker.sh share [<n>] [reserve=<cores>]   print the machine's share, the reserve the person keeps, the cores and the room, or set the share to <n>, 1 to 100, and the reserve to <cores> (the set writes the user-level files)
#     bash <plugin-root>/hooks/session-poker.sh finding-move <record>#<n> <defer|fix> '<the user's words>' '<why>' ['<changelog sentence>']   move a finding across the line on words the user typed in this session, a deferral with its sentence (writes the run's log)
#     bash <plugin-root>/hooks/session-poker.sh finding-move <record>#<n> fixed <row>   name the ## Tasks row that fixed a finding, whatever its ancestry (writes the plan)
#     bash <plugin-root>/hooks/session-poker.sh prompt     the canonical Patrol prompt for this session's CronCreate (read-only)
#     bash <plugin-root>/hooks/session-poker.sh sitrep [--line] [<plan>]   the situation report's fact sheet for the model, or the Patrol's one-line status (settles ruled decisions on the register)
#     bash <plugin-root>/hooks/session-poker.sh sitrep card [<plan>] < judgment   the sitrep card, drawn from the sheet and the model's judgment, or every reason it is refused (settles ruled decisions on the register)
#     bash <plugin-root>/hooks/session-poker.sh stop-run <name|run id|request id> [--report-only] [--machine <caller>] --why '<reason>'   stop a detached run, or end a gate request and TERM its holder's group (signals, writes ends, one hand event unless a machine caller stops it)
#     bash <plugin-root>/hooks/session-poker.sh handoff ['<purpose>'] < sections   write the handoff document under the handoffs folder of the docs record, bound or not: the composed sections from stdin, State computed, the resume line last; bound, the plan's ## Handoff becomes one pointer line (writes the file, and the plan when bound)
#     bash <plugin-root>/hooks/session-poker.sh resume <handoff.md>   the one door: engage this session when it is not, bind the plan the file names, arm at a scale with a Patrol, adopt, tick; a dozen lines to the terminal, the rest to one recap file (writes the marker, the stamp, this session's roster and the recap)
#     bash <plugin-root>/hooks/session-poker.sh decisions [--all]   the register: this run's rulings from record/<wave>/design-ledger.md and its log, or every run's with the ADRs (read-only)
#     bash <plugin-root>/hooks/session-poker.sh decisions put D<n> '<what is decided>'   a decision put: one round in the run's log, and the wait line it prints
#     bash <plugin-root>/hooks/session-poker.sh decisions rule D<n> '<reply>'   a decision ruled on the user's reply: its round in the run's log and its ask closed, in one act
#     bash <plugin-root>/hooks/session-poker.sh brief <row> [<name>]   render the dispatch brief into record/<wave>/briefs/<name>.md from the row, its plan section and the reader (writes that file, never the plan)
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
# stale — have one owner each in payload/scripts/lib, and the stub
# below finds them through payload/scripts/lib/loader.sh, the one loader. Every hook carries
# the same stub, held to `bionic_loader_pin`'s text by tests/hook-adoption.test.sh, so a
# drifted copy goes red rather than quiet.
#
# FAIL OPEN, deliberately. The poker is not a wall: it prints one decision line and holds no
# authority (ADR-003), so the cost of a missing library is a tick that cannot answer, not an
# irreversible action taken blind. It says so in one line and steps aside.
BIONIC_LIB_WANT="root.sh session.sh run.sh binding.sh patrol.sh resources.sh worktree.sh agents.sh roster.sh units.sh fill.sh observe.sh refuse.sh"
# Find the library through lib/loader.sh beside this hook; payload/scripts/lib/loader.sh says how.
_bl_dir="$(dirname "$0")"; _bl_l="$_bl_dir/../scripts/lib/loader.sh"; [ -r "$_bl_l" ] || _bl_l="$_bl_dir/../payload/scripts/lib/loader.sh"
# shellcheck source=/dev/null
if [ -r "$_bl_l" ]; then . "$_bl_l"; bionic_load; else
  BIONIC_LIB=""; BIONIC_LIB_MISSING="${BIONIC_LIB_WANT%% *}"; BIONIC_LIB_CANDS="$_bl_dir/../scripts/lib, $_bl_dir/../payload/scripts/lib"
  loader_fail_open() { echo "$1: library $BIONIC_LIB_MISSING not found at $BIONIC_LIB_CANDS — hook stepping aside; run /bionic:doctor" >&2; exit 0; }
  loader_fail_closed() { set -- "$1"; [ "${#1}" -le 25 ] || set -- "${1:0:24}…"; echo "bionic: load refused — $1 cannot load the bionic library (run /bionic:doctor)" >&2; exit 2; }
fi
[ -n "$BIONIC_LIB" ] || loader_fail_open "session-poker"
. "$BIONIC_LIB/root.sh"
. "$BIONIC_LIB/session.sh"
. "$BIONIC_LIB/run.sh"
# THE ONE READER OF THE INTEGRATION BRANCH AND THE ONE READER OF THE HANDOFF POINTER (wave-39 T16; D18, AC-12.1):
# lib/plan.sh `plan_integration_branch` (## SDLC State, then the frontmatter) for `handoff` and `release-check`, and
# lib/handoff.sh `handoff_pointer_of`/`handoff_default_of` for every reader of the run's handoff below.
# close-out.sh calls the same two, so the verb and the closed form cannot read two branches or two files.
# shellcheck source=/dev/null
. "$BIONIC_LIB/plan.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/handoff.sh"
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
# it raises, and approve and waive close the item their answer settles. NOT in
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
# The default interval is the Patrol library's one constant, which every reader falls back to when `interval` refuses.
POKER_INTERVAL_DEFAULT="${PATROL_INTERVAL_DEFAULT}s"

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
# v=3 (wave-25 T5; D7): the prompt says what the decision line's `gate=` field asks of the turn,
# so a Patrol armed under v=2 does not know it and the tick's re-arm note asks for the new job.
# v=4 (wave-26 T15; D16): an `unchanged` or a WAITING tick ends the turn's duties, the task-list
# refresh is asked only on a change, and "continue" only when something is ready or changed.
# v=5 (wave-26 T32; review-6 F2): the refresh is asked only when the tick printed its RECONCILE
# line, which it prints whenever the duty is owed (v=4 asked on a change the tick never printed),
# and a FILL asks for the dispatch alone: the launch records the row and its ledger line.
# v=6 (wave-27 T34; REQ-15, D24): a FILL left unfilled is answered by the `decline` verb, which records
# the decline on disk, and no longer by a line in the reply the user reads.
# v=7: the decline is gone, so a session armed under v=6 asks for a verb that answers unknown. A FILL
# is answered by its dispatch; a row that should wait is made not ready instead, by the forms the stop
# wall prints, and the tick's re-arm note asks for the new job.
# v=8: the prompt carries the one sentence the orchestrator says after re-arming, and no other
# instruction about what to say there, so a session armed under v=7 lacks it and the tick's re-arm
# note asks for the new job.
PATROL_PROMPT_VERSION=8

# THE ONE SENTENCE THE ORCHESTRATOR SAYS AFTER RE-ARMING A PATROL, kept in one double-quoted literal
# because it holds an apostrophe. The dispatch rules (agents-src/blocks/orchestrator-dispatch.md) carry
# the same words, and tests/stop.test.sh §PATROL pins both sites to this one.
PATROL_REARM_SAY="Patrol re-armed: the session's cron table was empty, so I created the recurring <interval> job and stamped it. Next fire is <time>."

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
# THE RELEASE APPROVAL CARD'S ONE LINE OF USAGE, said by `usage` and by `release-approval --help`, so the two cannot disagree.
RA_USAGE="release-approval [--preview] [--against <key>]... [<plan>]   the release approval card of the bound run: Bottom line, Goals, Tests, Reviews, Findings and Decisions; --against names a decision or finding the orchestrator recommends against its default; --preview renders it whatever the facts and records nothing"
usage() {  # [message]
  [ $# -gt 0 ] && die "$1"
  die "Usage:"
  die "  bash ${HOOK_DIR}/session-poker.sh tick       one decision over this session's roster (read-only)"
  die "  bash ${HOOK_DIR}/session-poker.sh arm        stamp the Patrol as alive for this session (no roster needed)"
  die "  bash ${HOOK_DIR}/session-poker.sh disarm     remove that stamp at run close — this Patrol was ended on purpose"
  die "  bash ${HOOK_DIR}/session-poker.sh interval    the configured Patrol interval, in seconds"
  die "  bash ${HOOK_DIR}/session-poker.sh share [<n>] [reserve=<cores>]   print the machine's share (92 when none is set), the cores the person keeps (1 when none is set), the cores and the room; with <n> or reserve=<cores>, set it in the user-level file the gate reads"
  die "  bash ${HOOK_DIR}/session-poker.sh adopt [--why '<reason>']   every open row a PREDECESSOR session left on this project's rosters, each adoption one hand event with its reason (the predecessor's clear when none is given)"
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
  die "  bash ${HOOK_DIR}/session-poker.sh task-add <id> [--born …]   record the birth of row <id>, which an edit of the bound plan wrote first: the row is read back and judged as a row born mid-run, one born event is appended, and the plan is not written; a short row is refused with the lines it would accept; --born <record>#<n>[,…] names the findings the row fixes; --born regression:<suite> marks a row born of the regression's red in that suite"
  die "  bash ${HOOK_DIR}/session-poker.sh amend <name> [--files+ <path>]... [--suites+ <suite>]... [--suites=<a,b>] [--reexec+ '<cmd>']... --reason <why>   widen a live row's contract (--suites= narrows its suites, and lands_on= with them): a successor row, judged by the dispatch grammar"
  die "  bash ${HOOK_DIR}/session-poker.sh current <N> [--check]   advance the run's step: judged as a commit at <N> would be, then one step event in the run's log, the plan unwritten (9 is close-out's); --check (5-8) runs the judgment, appends nothing, and exits as the advance would"
  die "  bash ${HOOK_DIR}/session-poker.sh order '<the user's words>'   record the user's order: an order event with the words in the bound run's log, else a line in record/orders.log; while it stands tests/run.sh starts no suite"
  die "  bash ${HOOK_DIR}/session-poker.sh order lift   end the open order: an order: lifted line with the time and its words"
  die "  bash ${HOOK_DIR}/session-poker.sh approve <name> '<reply>' ['<why>']   record the user's approval <name> as one approval in the run's log: a name a row reads, plan at Step 3, or a T4 criterion the user confirms on words they typed"
  die "  bash ${HOOK_DIR}/session-poker.sh reviews-part <id>   the integrate row's render, before its push and pull request: the release entry's ### The reviews from the plan's review and waiver lines, committed on the working branch and named in the landing record (never pushed)"
  die "  bash ${HOOK_DIR}/session-poker.sh known-limits-part <id>   the entry row's render (doc or integrate): the release entry's ### Known limits from the plan's deferrals, each its stated sentence, committed on the working branch and named in the landing record (never pushed)"
  die "  bash ${HOOK_DIR}/session-poker.sh proof-add <regression|review|task|walk> <evidence>   record a proof line under ## SDLC State, naming the head its evidence read; proof-add regression <log> [<log>…] takes one log or several, each opening head=<40-hex> dirty=0 and ending rc=0"
  die "  bash ${HOOK_DIR}/session-poker.sh proof-add inherited <suite>   run that suite file, red in the regression's whole run, at the plan's base in a scratch tree: red there too is inherited debt, written as an inherited: line; green there is a regression, refused"
  die "  bash ${HOOK_DIR}/session-poker.sh proof-add review <record> --question <evidence|adversarial|structure> --reader <roster name>   record a review: the review proof with the question, reviewer, result and scope"
  die "  bash ${HOOK_DIR}/session-poker.sh proof-add walk <record>   register the walk: its | AC | verdict | why | table and one verdict: line, read as the critic's; one walk proof and one proof naming each CONFIRMED criterion go to the run's log, the plan unwritten; a record that leaves out a criterion the standing walk confirms is refused; one ev=walk line goes to the landing record"
  die "  bash ${HOOK_DIR}/session-poker.sh waive <evidence|adversarial|structure|all> '<reply>'   record the user's waiver of that question, or of all three, at the working head, one waiver event each in the run's log"
  die "  bash ${HOOK_DIR}/session-poker.sh waive <AC-id> '<the user's words>' ['<why>']   record the user's waiver of that criterion, on words they typed in this session: one waiver event naming it in the run's log, which discharges it"
  die "  bash ${HOOK_DIR}/session-poker.sh release-check   run .bionic/config.yaml's release-check: command from the last release to the working head; record its log and a kind=check proof line, result=fail on a non-zero exit"
  die "  bash ${HOOK_DIR}/session-poker.sh regression-run [--starter tick|orchestrator|person] [--reason '<why>']   run the regression in the working branch's checkout, .bionic/config.yaml's regression-command: command, else tests/run.sh whole (held to the full-run rules); write its log, opening head=<40-hex> dirty=<n> and closing rc=<n>, for proof-add regression to cite; --starter names who started it, written as starter= on its run line (orchestrator by default), and person needs --reason"
  die "  bash ${HOOK_DIR}/session-poker.sh finding-move <record>#<n> <defer|fix> '<the user's words>' '<why>' ['<changelog sentence>']   move a finding across the line on words the user typed in this session, a deferral with its one changelog sentence, as a finding event in the run's log"
  die "  bash ${HOOK_DIR}/session-poker.sh finding-move <record>#<n> fixed <row>   name the ## Tasks row that fixed a finding, landed before the review or after it, as a finding event in the run's log"
  die "  bash ${HOOK_DIR}/session-poker.sh disposition [<record>#<n> <fix|defer> '<the user's words>' '<why>' ['<changelog sentence>']]   render every finding of the registered reviews (rating, record, fix row, state, the decision it needs), adding their debt and opening an owed item per finding the person must rule on; with a finding, record the person's ruling on it"
  die "  bash ${HOOK_DIR}/session-poker.sh prompt     the canonical Patrol prompt: the one a CronCreate for this session carries"
  die "  bash ${HOOK_DIR}/session-poker.sh landing-report [--rows] [--hand-holds [--since <ISO>] [--until <ISO>]] [<plan>]   the run's landings, waits and runs, folded from its landing record and the gate's requests; --rows adds a line per landed row; --hand-holds adds the count of escape-hatch uses by kind, folded from the lines their verbs wrote, over the window from the last build landing to the release approval card, or the window --since and --until name, and the window's two ends"
  die "  bash ${HOOK_DIR}/session-poker.sh landing-report --scorecard [<plan>]   the run's scorecard: human stops on the autonomous half, agent minutes after the final reply, the widest landing and human-wait minutes, each against its target, then the sheet's pace, correctness and waste (read-only)"
  die "  bash ${HOOK_DIR}/session-poker.sh release-note [--at <commit>] [--on <ISO-UTC>] [<plan>]   the release entry's ### The landing numbers block: landing-report --rows over the landing record as it stood at the instant, naming the working head (read-only)"
  die "  bash ${HOOK_DIR}/session-poker.sh sitrep [--line] [<plan>]   the situation report's fact sheet: one fact per line, <key>: <value> — the run, the steps, every task with its state, the metrics in numbers, each goal's status, the predicted close and its arithmetic, every ask open on the run's register with what it holds, and every review; the model reads it and the user sees the card; --line prints the Patrol's status, <k> of <m> tasks · owed: <n> on you · <m> on events · close <time> (closes the asks of decisions the ledger ruled)"
  die "  bash ${HOOK_DIR}/session-poker.sh sitrep card [<plan>] < judgment   the sitrep card: the judgment on stdin, seven lines, one tagged line each (purpose:, call:, grade: <A-F>, point:, ask <key>[, <key>]: <what> — recommend <answer>, close:), checked against the sheet's facts; the card draws every row that is a fact; a card that fails its check prints nothing and exits 1, every reason on stderr"
  die "  bash ${HOOK_DIR}/session-poker.sh stop-run <name|run id|request id> --why '<reason>' [--report-only] [--machine <caller>]   stop a detached run: TERM its process group, then KILL every group below it still alive; records rc=137 when it wrote no end. A gate request id, or a name holding no running detached run but one open request: ends the request (by=<session> why=<reason>) and TERMs its holder's group. Either way one hand event, what=stop-run with its reason, goes to the bound run's log, unless --machine names the tool's own caller (close-out's sweep), whose stop is no act by hand; with no reason the stop is refused and nothing is sent"
  die "  bash ${HOOK_DIR}/session-poker.sh ${RA_USAGE}"
  die "  bash ${HOOK_DIR}/session-poker.sh reply '<the user's reply>'   replay the user's one reply to the release approval card, all default or all recommended, into approve, waive and finding-move with their words"
  die "  bash ${HOOK_DIR}/session-poker.sh handoff ['<purpose>'] < sections   write the handoff document, .bionic/docs/record/handoffs/<date>-<slug>.md, bound or not: the kind line, the title, Summary, Goal, State (computed), Findings, Decisions, Ruled out, Open, Suggested skills and Next (composed, on stdin), the resume line last; prints the path and the resume line; bound, the plan's ## Handoff becomes the one line handoff: <path> written <local time>"
  die "  bash ${HOOK_DIR}/session-poker.sh resume <handoff.md>   the one door: engage this session when it is not, bind the plan the file names, arm at a scale with a Patrol, adopt and tick; print the run in a dozen lines (bound, step, agents running, landed since, owed now, patrol) and the path of the recap file holding the rest (task-list:, settled:, open:, the Patrol job). A closed or no-run file binds nothing"
  die "  bash ${HOOK_DIR}/session-poker.sh promote <adr|design|requirement> <path>   copy one durable record into the project's tracked home (docs-tracked: in .bionic/config.yaml, docs/ when absent) as <home>/<kind>s/<name>, the run number dropped from the name; a plan, a log or a run record is refused and nothing is copied"
  die "  bash ${HOOK_DIR}/session-poker.sh decisions [--all]   the bound run's rulings, D<n> · \"<reply>\" · <who> <date> · <title>, from record/<wave>/design-ledger.md and the run's log as one list; --all: every run's, keyed by wave, with the ADRs (read-only)"
  die "  bash ${HOOK_DIR}/session-poker.sh decisions put D<n> '<what is decided>'   during a run, append the decision's put to the run's log and print its wait line: what an hour's wait moves, from the tasks that read approval:D<n> and the longest chain"
  die "  bash ${HOOK_DIR}/session-poker.sh decisions rule D<n> '<reply>'   during a run, on the user's reply, append the ruling, its reply and who said it, to the run's log and close the decision's ask; approve D<n> and a release approval card's reply rule through the same writer; a decision already ruled is refused"
  die "  bash ${HOOK_DIR}/session-poker.sh brief <row> [<name>]   render the dispatch brief of that plan row into record/<wave>/briefs/<name>.md (<name> the agent's, else the fill's for the row): the scaffold from the row, the judgment from the task's own section of the plan, the review range, Questions and Lands-red from the reader; it never rewrites a brief it did not render, and never changes the plan"
  die "  bash ${HOOK_DIR}/session-poker.sh debt add <record> [<plan>]   append one debt to the run's log per debt: line of the record (a review's, a writer's, an assumptions.md hole line), each concept and kind once"
  die "  bash ${HOOK_DIR}/session-poker.sh debt touched <concept> [<plan>]   add one to the touches of each unburned item of <concept> (the dispatch wall's call)"
  die "  bash ${HOOK_DIR}/session-poker.sh debt burn <concept> <row> [<plan>]   mark each unburned item of <concept> burned by <row>"
  die "  bash ${HOOK_DIR}/session-poker.sh debt adopt <continuation> [<plan>]   append each debt: line the continuation carries under ## Deferrals to the run's log as a debt, its touches and its raising record kept"
  die "  bash ${HOOK_DIR}/session-poker.sh debt list [<plan>]   print the run's debts, one line each, burned ones too"
  exit 2
}

[ $# -ge 1 ] || usage "a verb is required."
# THE VERB'S OLD SPELLING IS REFUSED (wave-39 T18; REQ-13 AC-13.1, D2): the line after VERB is read, before both case blocks,
# lib/alias.sh names the new one.
VERB="$1"; shift
if declare -F alias_gone >/dev/null 2>&1 && alias_gone verb "$VERB"; then die "REFUSED — $ALIAS_GONE_SAID. Nothing was run."; exit 1; fi
# THE CARD'S OLD NAME. The card the autonomous half waits on was called by another name before it was the release approval
# card, and the person's decision it asks for is the release's. The old verb still runs, as the new one, and says so once
# on stderr. Pages already written carry the old stem and
# tag, and the readers (`reply`, the situation report) go on reading them through this variable: it is the only place the
# old name is spelled, so a sweep for it finds one line and a page written under it stays readable.
RR_OLD_VERB="review-results"
if [ "$VERB" = "$RR_OLD_VERB" ]; then die "$RR_OLD_VERB is now release-approval"; VERB="release-approval"; fi

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
ADOPT_WHY=""
SWEEP_REPORT_ONLY=no
SWEEP_WINDOWED=no
BIND_ARG=""
case "$VERB" in
  adopt)
    while [ $# -gt 0 ]; do
      case "$1" in
        --report-only) [ "$ADOPT_REPORT_ONLY" = no ] || usage "adopt takes at most one flag of each kind."; ADOPT_REPORT_ONLY=yes; shift ;;
        --why) [ $# -ge 2 ] && [ -z "$ADOPT_WHY" ] || usage "adopt --why takes the reason, once."; ADOPT_WHY="$2"; shift 2 ;;
        *) usage "unknown flag for adopt: $1" ;;
      esac
    done
    case "$ADOPT_WHY" in *$'\n'*|*$'\r'*|*'|'*) usage "adopt --why takes one line, without a '|'." ;; esac
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
  # ONE OPERAND, THE ROW'S ID: the row is the edit's, written into the plan before the verb runs, and the verb reads it
  # back. `--born` comes last and names what the row was born of, the one fact no cell holds: `review S<n> <on|off>`,
  # the rating the reader wrote; `<record>#<n>[,<record>#<n>…]`, the findings it answers, their rating read from the
  # record; or `regression:<suite>`, the suite whose regression red it fixes, by its file name. A missing or malformed
  # value is the usage error; whether the birth is admitted (fix-policy:, fix-cap:, the fourth fix on a component, a
  # red the machine recorded behind a regression) is the verb's refusal (1).
  task-add)
    TA_BORN=""; TA_BORN_IDS=""; TA_BORN_SUITE=""
    case "${*: -1}" in --born) usage "task-add: --born takes a value: the findings the row answers, <record>#<n>[,<record>#<n>…], 'review S<n> <on|off>', the reviewer's rating, or regression:<suite>, the suite whose regression red the row fixes." ;; esac
    if [ $# -ge 2 ] && [ "${*: -2:1}" = "--born" ]; then
      TA_BORN="${*: -1}"
      # THE OPERAND'S OLD SPELLING IS REFUSED (wave-39 T18; REQ-13 AC-13.1): the row is not written.
      case "$TA_BORN" in *:*) if declare -F alias_gone >/dev/null 2>&1 && alias_gone born-operand "${TA_BORN%%:*}:"; then die "REFUSED — $ALIAS_GONE_SAID. The plan is unchanged."; exit 1; fi ;; esac
      case "$TA_BORN" in
        'review S'[1-4]' on'|'review S'[1-4]' off') : ;;
        regression:*)
          TA_BORN_SUITE="${TA_BORN#regression:}"; TA_BORN=""
          case "$TA_BORN_SUITE" in
            *[!A-Za-z0-9._-]*|.test.sh|'') TA_BORN_SUITE="" ;;
            *.test.sh) : ;;
            *) TA_BORN_SUITE="" ;;
          esac
          [ -n "$TA_BORN_SUITE" ] || usage "task-add: --born '${*: -1}' names no suite; write regression:<suite>, the suite's file name (<name>.test.sh) whose regression red the row fixes." ;;
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
    if [ $# -ne 1 ]; then
      usage "task-add takes the id of a row an edit of the plan has written, then optionally --born <record>#<n>[,…], --born 'review S<n> <on|off>' or --born regression:<suite>. A review row's questions are written in its task cell, ' · questions: <q>[,<q>]'."
    fi
    TA_ID="$1"
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
    AMEND_FILES=""; AMEND_SUITES=""; AMEND_NARROW=""; AMEND_RUNS=""; AMEND_REASON=""; AMEND_BY=""
    while [ $# -gt 0 ]; do
      case "$1" in
        # THE NARROWING IS ONE SET, SPELT --suites=<a,b> (comma-separated, as lands_on= is): the successor row holds
        # exactly these, and the verb refuses a name the row does not hold, since that would be a widening.
        --suites=?*) AMEND_NARROW="${AMEND_NARROW}${1#--suites=}"$'\n'; shift ;;
        --suites=) usage "amend: --suites= takes the suites to keep, comma-separated." ;;
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
    [ -n "$AMEND_FILES$AMEND_SUITES$AMEND_NARROW$AMEND_RUNS" ] \
      || usage "amend changes nothing without --files+, --suites+, --suites= or --reexec+."
    [ -z "$AMEND_NARROW" ] || [ -z "$AMEND_SUITES" ] \
      || usage "amend: --suites= sets the suites and --suites+ adds to them; give one."
    case ",$(printf '%s' "$AMEND_NARROW" | tr '\n' ','), " in *,none,*) usage "amend: --suites= narrows to suites the row keeps; none is a waiver, not a narrowing." ;; esac
    ;;
  # THE INTEGRATE ROW'S RENDER OF THE ENTRY'S REVIEWS: the row id alone; the head is the working branch's.
  reviews-part)
    [ $# -eq 1 ] && [ -n "$1" ] || usage "reviews-part takes one argument: the integrate row's id."
    PV_ID="$1"
    ;;
  # THE ENTRY ROW'S RENDER OF THE KNOWN LIMITS: the row id alone; the head is the working branch's.
  known-limits-part)
    [ $# -eq 1 ] && [ -n "$1" ] || usage "known-limits-part takes one argument: the doc or integrate row's id."
    PV_ID="$1"
    ;;
  # `current <N> --check` (wave-38 T1; D20, AC-1.3): the flag after the step, for 5 to 8, asks the advance without writing.
  current)
    { [ $# -eq 1 ] || [ $# -eq 2 ]; } && [ -n "$1" ] \
      || usage "current takes the step number (0-8) to move to, and --check after a step from 5 to 8 to ask without writing."
    case "$1" in
      9|9a|9b|[0-8]|[0-8][ab]) : ;;
      *) usage "current: '$1' is not a step number (0-8); current: is a step number at every scale." ;;
    esac
    PV_KEY="$1"; PV_CHECK=""
    if [ $# -eq 2 ]; then
      [ "$2" = --check ] || usage "current: '$(printf '%s' "${2:0:24}" | tr -d '[:cntrl:]')' is not --check, the one word current takes after the step."
      case "$1" in
        [5-8]|[5-8][ab]) PV_CHECK=1 ;;
        *) usage "current $1 --check: the check-only advance is for steps 5 to 8." ;;
      esac
    fi
    ;;
  # THE REPLY TO THE RELEASE APPROVAL CARD. One operand: the user's reply to the page `release-approval` rendered, verbatim.
  # Its words, and whether the user typed them, are the verb's own refusals (1).
  reply)
    { [ $# -eq 1 ] && [ -n "${1//[[:space:]]/}" ]; } \
      || usage "reply takes exactly one argument: the user's reply to the release approval card, verbatim."
    RP_TEXT="$1"
    ;;
  # THE RELEASE APPROVAL CARD. `--preview` once, `--against <key>` any number of times, at most one plan; `--help` says the
  # verb's usage line and exits 0 before anything else is read. A key's shape is the usage error (2); whether it names
  # anything on the page is the verb's own refusal (1).
  release-approval)
    RR_PREVIEW=no; RR_AGAINST=""; RR_ARG=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -h|--help) printf 'poker: %s\n' "$RA_USAGE"; exit 0 ;;
        --preview) [ "$RR_PREVIEW" = no ] || usage "release-approval takes --preview once."; RR_PREVIEW=yes ;;
        --against)
          case "${2:-}" in
            approve:?*|waive:?*|row:?*|finding:?*) RR_AGAINST="${RR_AGAINST}$2"$'\n'; shift ;;
            *) usage "release-approval --against takes one key: approve:<name>, waive:<question>, row:<AC> or finding:<record>#<n>." ;;
          esac ;;
        -*) usage "release-approval takes --preview, --against <key> and at most one plan." ;;
        *) [ -z "$RR_ARG" ] || usage "release-approval takes at most one plan."; RR_ARG="$1" ;;
      esac
      shift
    done
    ;;
  # THE APPROVAL VERB (wave-26 T13; D3, AC-6.2). Two operands, both required: the name a row
  # reads as `approval:<name>`, in the grammar `units_validate` admits there, and the user's
  # reply, verbatim. The name's shape is checked here, by the ASCII letters spelled out (a range
  # is a collation range under a UTF-8 locale; wave-24 T29); the reply's is the verb's own refusal.
  approve)
    if [ $# -lt 2 ] || [ $# -gt 3 ] || [ -z "$1" ] || [ -z "${2//[[:space:]]/}" ]; then
      usage "approve takes the approval's name, the user's reply, verbatim, and optionally why."
    fi
    case "$1" in
      [ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789]*) : ;;
      *) usage "approve: '$1' is not an approval name: a letter or a digit, then letters, digits, '.', '_' or '-'." ;;
    esac
    case "$1" in
      *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*)
        usage "approve: '$1' is not an approval name: a letter or a digit, then letters, digits, '.', '_' or '-'." ;;
    esac
    AP_NAME="$1"; AP_REPLY="$2"; AP_WHY="${3:-}"
    ;;
  # THE USER'S ORDER. One operand: the user's words, which must hold something once blanks are gone,
  # or the word lift, which ends the open order.
  order)
    OR_WORDS=""; OR_LIFT=""
    if [ $# -eq 1 ] && [ "$1" = lift ]; then
      OR_LIFT=yes
    elif [ $# -eq 1 ] && [ -n "${1//[[:space:]]/}" ]; then
      OR_WORDS="$1"
    else
      usage "order takes one argument: the user's words, quoted, or lift to end the open order."
    fi
    ;;
  # TWO OPERANDS AND NO THIRD (wave-26 T4; REQ-3, D5): the kind and the evidence. The head is the
  # one the evidence names, held against the working branch's checkout (T14), never typed, so a
  # head on the command line is the usage error, not a value. A READING (wave-27 T2; D1, D7) adds
  # two flags, both or neither, to a review proof only: `--question <q> --reader <name>`, in
  # either order. Without them a review proof is 1.11.0's, so a plan built under it still works.
  proof-add)
    PF_USAGE="proof-add takes two arguments, <regression|review|task|walk> <evidence path under record/>, and for a review two flags more: proof-add review <record> --question <evidence|adversarial|structure> --reader <roster name> (the head is the one the evidence names, the head= line of a run log or the end of the reviewed: a..b line of a review, never an operand); proof-add regression takes one log or several, proof-add regression <log> [<log>…], each opening head=<40-hex> dirty=0 and ending rc=0; proof-add walk <record> [--environments <name>[,<name>…]] takes the walk's record, its head the one its head: line names, else the working head, and the environments it covered; or proof-add inherited <suite file name>, which runs that suite at the plan's base-sha: in a scratch tree."
    if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]; then usage "$PF_USAGE"; fi
    # SEVERAL LOGS ON ONE LINE (wave-36 T35; D13, AC-7.10): a floor may be the logs of several runners, each its own
    # operand after the first, newline-joined in PF_EVIDS (a path holding a line break is refused below, by name).
    PF_KIND="$1"; PF_EVID="$2"; PF_EVIDS="$2"; PF_QUESTION=""; PF_READER=""; PF_ENVS=""; shift 2
    # THE KIND'S OLD SPELLING IS REFUSED (wave-39 T18; REQ-13 AC-13.1): no proof line is written.
    if declare -F alias_gone >/dev/null 2>&1 && alias_gone proof-kind "$PF_KIND"; then die "REFUSED — $ALIAS_GONE_SAID. No proof was written."; exit 1; fi
    while [ $# -gt 0 ]; do
      case "$1" in
        --question) [ $# -ge 2 ] && [ -n "$2" ] && [ -z "$PF_QUESTION" ] || usage "$PF_USAGE"; PF_QUESTION="$2"; shift 2 ;;
        --reader)   [ $# -ge 2 ] && [ -n "$2" ] && [ -z "$PF_READER" ] || usage "$PF_USAGE"; PF_READER="$2"; shift 2 ;;
        # The environments a walk covered are a field of its proof: the walk is what covers them.
        --environments) [ $# -ge 2 ] && [ "$PF_KIND" = walk ] && [ -z "$PF_ENVS" ] || usage "$PF_USAGE"
          case "$2" in ''|*[!A-Za-z0-9._,\ -]*) usage "$PF_USAGE" ;; esac; PF_ENVS="$2"; shift 2 ;;
        -*|'') usage "$PF_USAGE" ;;
        *$'\n'*) usage "$PF_USAGE" ;;
        *[!0123456789abcdefABCDEF]*|*/*) [ "$PF_KIND" = regression ] || usage "$PF_USAGE"; PF_EVIDS="$PF_EVIDS
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
  # A CRITERION IS WAIVED BY THE SAME VERB: its id where the question goes, the user's words, and optionally why, which
  # the release approval card's reply passes.
  waive)
    WV_WHY_RAW=""
    case "${1:-}" in
      evidence|adversarial|structure|all|'') [ $# -eq 2 ] || set -- ;;
      *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*) set -- ;;
      *) [ $# -eq 2 ] || { [ $# -eq 3 ] && [ -n "${3//[[:space:]]/}" ] && WV_WHY_RAW="$3"; } || set -- ;;
    esac
    if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "${2//[[:space:]]/}" ]; then
      usage "waive takes the question (evidence, adversarial, structure or all) and the user's reply, verbatim; or a criterion, the user's words as typed, and optionally why."
    fi
    WV_Q="$1"; WV_REPLY="$2"
    ;;
  # FOUR OPERANDS (wave-28 T42; D34): the finding (`<record>#<n>`), where it goes (defer or fix), the
  # user's words as typed and why. A missing or blank operand, another direction or an id of another
  # shape is the usage error; whether the words stand in a typed prompt is the verb's own refusal (1).
  # OR THREE (wave-36 T8; D9): the finding, `fixed`, and the row that fixed it, `T<n>`; words or a why
  # after it are the usage error. Whether the plan's table carries the row is the verb's own refusal (1).
  # `carried` takes the same three: the finding stays open and closes when the named row lands. A move to defer
  # takes a fifth, the deferral's one changelog sentence, a field of the move's event.
  finding-move)
    FM_USAGE="finding-move takes <record>#<n>, defer or fix, the user's words as typed, and why, and for defer optionally its changelog sentence; or <record>#<n>, fixed, and the row that fixed it; or <record>#<n>, carried, and the row whose landing closes it."
    FM_ROW=""; FM_SENT_RAW=""
    case "${2:-}" in
      defer|fix)
        { [ $# -eq 4 ] || { [ $# -eq 5 ] && [ "$2" = defer ] && [ -n "${5//[[:space:]]/}" ]; }; } \
          && [ -n "${3//[[:space:]]/}" ] && [ -n "${4//[[:space:]]/}" ] || usage "$FM_USAGE"
        FM_SENT_RAW="${5:-}" ;;
      fixed|carried)
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
  # are finding-move's, the verb's own refusals (1).
  disposition)
    DSP_USAGE="disposition takes no argument (it renders every finding of the registered reviews), or <record>#<n>, fix or defer, the person's words as typed, why, and for defer optionally its changelog sentence."
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
  # NO OPERAND: the command is the project's regression-command:, else its tests/run.sh, and the head is the working
  # one. Its flags, --starter and --reason, are the verb's own to read and refuse (hooks/poker/proof.sh
  # poker_verb_regression_run), so they pass through.
  regression-run) : ;;
  tick|arm|disarm|interval|prompt)
    [ $# -eq 0 ] || usage "$VERB takes no arguments."
    ;;
  # THE MACHINE'S SHARE. No operand prints it; a share and `reserve=<cores>`
  # set theirs, together or one at a time. A value's own shape is the verb's refusal; a third operand, or the
  # same one twice, is the usage error.
  share)
    [ $# -le 2 ] || usage "share takes at most two arguments: the share to set, 1 to 100, and reserve=<cores>."
    SH_SET=no; SH_ARG=""; SH_RSET=no; SH_RES=""
    for SH_A in "$@"; do
      case "$SH_A" in
        reserve=*) [ "$SH_RSET" = no ] || usage "share takes reserve=<cores> once."
                   SH_RSET=yes; SH_RES="${SH_A#reserve=}" ;;
        *) [ "$SH_SET" = no ] || usage "share takes one share, 1 to 100."
           SH_SET=yes; SH_ARG="$SH_A" ;;
      esac
    done
    ;;
  # ONE OPTIONAL FLAG AND ONE OPTIONAL OPERAND, IN EITHER ORDER (wave-28 T14; D18; A-orch-145): `--rows`
  # adds a line per landed row; `<plan>` names the run, for a caller with no
  # binding left (close-out writes its continuation after its tmp is wiped).
  release-note) : ;;
  landing-report)
    LR_ROWS=no; LR_HH=no; LR_SC=no; LR_ARG=""; LR_SINCE=""; LR_UNTIL=""
    # A window end is an ISO-UTC instant, the shape every source the count places carries; any other value is the
    # usage error, so a typo never reads as an open end.
    while [ $# -gt 0 ]; do
      _lr_a="$1"; shift
      case "$_lr_a" in
        --rows) [ "$LR_ROWS" = no ] || usage "landing-report takes --rows once."; LR_ROWS=yes ;;
        --hand-holds) [ "$LR_HH" = no ] || usage "landing-report takes --hand-holds once."; LR_HH=yes ;;
        --scorecard) [ "$LR_SC" = no ] || usage "landing-report takes --scorecard once."; LR_SC=yes ;;
        --since|--until)
          case "${1:-}" in
            [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
            *) usage "landing-report $_lr_a takes an ISO-UTC instant, as 2026-10-20T16:43:24Z." ;;
          esac
          if [ "$_lr_a" = --since ]; then [ -z "$LR_SINCE" ] || usage "landing-report takes --since once."; LR_SINCE="$1"
          else [ -z "$LR_UNTIL" ] || usage "landing-report takes --until once."; LR_UNTIL="$1"; fi
          shift ;;
        -*) usage "landing-report takes the flags --rows and --hand-holds (with --since and --until), and at most one plan." ;;
        *) [ -z "$LR_ARG" ] || usage "landing-report takes the flags --rows and --hand-holds (with --since and --until), and at most one plan."; LR_ARG="$_lr_a" ;;
      esac
    done
    [ "$LR_SC" = no ] || { [ "$LR_ROWS" = no ] && [ "$LR_HH" = no ]; } || usage "landing-report takes --scorecard alone, with at most one plan."
    { [ -z "$LR_SINCE" ] && [ -z "$LR_UNTIL" ]; } || [ "$LR_HH" = yes ] || usage "landing-report takes --since and --until only with --hand-holds: they bound its window."
    ;;
  # THE SITUATION REPORT. `sitrep [--line] [<plan>]` prints the fact sheet, or with --line the Patrol's status;
  # `sitrep card [<plan>]` draws the card from the sheet and the judgment on stdin. The plan, when named, is the one
  # operand; without it, the session's bound run, as landing-report's. `card` with --line, any other flag or a second
  # operand is a word the verb does not know: the usage error (2).
  sitrep)
    SR_LINE=no; SR_CARD=no; SR_ARG=""; _sr_n=0; _sr_first=""
    if [ "${1:-}" = card ]; then SR_CARD=yes; shift; fi
    for _sr_a in "$@"; do
      case "$_sr_a" in
        --line) [ "$SR_LINE" = no ] && [ "$SR_CARD" = no ] || usage "sitrep takes --line once, and never with card."; SR_LINE=yes ;;
        -*) usage "sitrep: unknown flag '$(printf '%s' "${_sr_a:0:24}" | tr -d '[:cntrl:]')'; it takes card or --line, and at most one plan." ;;
        *) _sr_n=$((_sr_n + 1)); [ -n "$_sr_first" ] || _sr_first="$_sr_a"; SR_ARG="$_sr_a" ;;
      esac
    done
    [ "$_sr_n" -le 1 ] || usage "sitrep: unknown word '$(printf '%s' "${_sr_first:0:24}" | tr -d '[:cntrl:]')'; it takes card or --line, and at most one plan."
    ;;
  # THE RUN VERB. `stop-run` takes ONE operand: a roster row's name, a run id (`run=` as
  # the shim printed it), or a run's log path; and `--report-only`, the promise that word makes on adopt and sweep.
  stop-run)
    SR_ARG=""; SR_REPORT_ONLY=no; SR_WHY=""; SR_MACHINE=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --report-only) SR_REPORT_ONLY=yes; shift ;;
        --why) [ $# -ge 2 ] || usage "stop-run --why takes the reason, one line."; SR_WHY="$2"; shift 2 ;;
        --machine) case "${2:-}" in [a-z]*) SR_MACHINE="${2//[!a-z-]/}"; shift 2 ;; *) usage "stop-run --machine takes the caller's name, as close-out." ;; esac ;;
        -*) usage "stop-run takes one name, run id or gate request id, and at most --report-only, --machine <caller> and --why '<reason>'." ;;
        *) [ -z "$SR_ARG" ] || usage "stop-run takes one name."; SR_ARG="$1"; shift ;;
      esac
    done
    [ -n "$SR_ARG" ] || usage "stop-run takes the name of a roster row (or a run id, or a gate request id) whose run to stop."
    case "$SR_WHY" in *$'\n'*|*$'\r'*|*'|'*) usage "stop-run --why takes one line, without a '|'." ;; esac
    # A person's stop is an act by hand, and an act by hand says why; so does a machine caller, whose stop is no hand
    # act (--machine). A report sends nothing and needs none.
    case "$SR_REPORT_ONLY:$SR_WHY" in
      yes:*|*:*[![:space:]-]*) ;;
      *) die "REFUSED — stop-run stops a run by hand, and says why: --why '<what went wrong, what the tool lacked>'. Nothing was stopped."; exit 2 ;;
    esac
    ;;
  # THE HANDOFF DOCUMENT. At most one operand, the purpose: what the next session is for, in words. The composed
  # sections come on stdin, never as flags; any flag is the usage error (2).
  handoff)
    HO_ARG_PATH=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -*) usage "handoff takes at most one operand, the purpose, and its composed sections on stdin: handoff ['<purpose>'] <<'HANDOFF' … HANDOFF." ;;
        *) { [ -z "$HO_ARG_PATH" ] && [ -n "$1" ]; } || usage "handoff takes at most one operand: the purpose, quoted as one word."
           HO_ARG_PATH="$1"; shift ;;
      esac
    done
    ;;
  # THE ONE DOOR (wave-38 T13; D4, AC-3.3). One operand: the handoff file, absolute, project-root-relative or
  # docs-root-relative. Whether it is one, and whether the plan it names is there, are the verb's refusals.
  resume)
    { [ $# -eq 1 ] && [ -n "$1" ]; } || usage "resume takes exactly one argument: the handoff file, as in: resume .bionic/docs/record/<wave>/handoff.md."
    RS_ARG="$1"
    ;;
  # THE PROMOTION. Exactly two operands: the kind and the record's path.
  promote)
    { [ $# -eq 2 ] && [ -n "$1" ] && [ -n "$2" ]; } || usage "promote takes exactly two arguments: the kind (adr, design or requirement) and the record's path, as in: promote adr adrs/<epic>/adr-<n>-<title>.md."
    PR_KIND="$1"; PR_ARG="$2"
    ;;
  # THE REGISTER (wave-38 T13; D24, AC-3.4). At most one flag, --all.
  decisions)
    DC_ALL=no DC_PUT="" DC_TITLE="" DC_RULE="" DC_REPLY=""
    if [ $# -eq 1 ] && [ "$1" = --all ]; then DC_ALL=yes
    elif [ $# -ge 1 ] && [ "$1" = put ]; then
      [ $# -eq 3 ] || usage "decisions put takes two arguments: the decision's number and what is decided, as in: decisions put D7 'which findings reach the user'."
      DC_PUT="$2"; DC_TITLE="$3"
    elif [ $# -ge 1 ] && [ "$1" = rule ]; then
      [ $# -eq 3 ] || usage "decisions rule takes two arguments: the decision's number and the user's reply, as in: decisions rule D7 '1'."
      DC_RULE="$2"; DC_REPLY="$3"
    elif [ $# -ne 0 ]; then usage "decisions takes --all, put D<n> '<what is decided>', or rule D<n> '<reply>'."; fi
    ;;
  # THE BRIEF, RENDERED WHOLE. The plan row's id, then the name its agent is dispatched under (the fill's name for
  # the row when left out); the id's shape, the name's, and whether the plan has the row are the verb's refusal (1).
  brief)
    { [ $# -ge 1 ] && [ $# -le 2 ] && [ -n "$1" ]; } || usage "brief takes the plan row's id and, optionally, the name its agent is dispatched under, as in: brief T2 w01-T2."
    BRF_ID="$1"; BRF_NAME="${2:-}"
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
# agent's progress file the way the sweeper reads a live one. The six are held together by
# tests/cross-gate-agreement.test.sh
# §O, which compares executable text with every pure-comment line stripped from both sides —
# epic-16 w2 Step-6 remediation R3, closing rd review D-1 (this claim used to name no test,
# and was already false for parse_seconds before that fix).

now_epoch() { date -u +%s; }
iso_now()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

# iso_epoch LEFT THE FAMILY (wave-39 T17; D18, AC-12.1; burns debt iso-to-epoch): an instant has one reader,
# lib/time.sh's (strict `…Z`, which `date -j -f` was not: it read `…Zx` with a warning), and this is the one-line call
# to it. The sweeper keeps its own `date` copy, because it sources no library; §O no longer compares the two.
iso_epoch() { _time_epoch "${1:-}"; }   # <ISO-8601 Z> -> epoch seconds, empty if unreadable

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

# ---------------------------------------------------------------- shared by the parts
#
# The helpers more than one part calls. They live here, beside the common facts above, so that no two parts call
# each other both ways; each keeps the text that explained it where it was written.

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

epoch_iso() {  # <epoch seconds> -> UTC ISO-8601, the shape the CLI stamps entries with
  date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
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
  local repo="$1" armed="${2:-}" sid="${3:-}" droot plan current
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
  # THE RUN'S PLACE IS THE READER'S (lib/run.sh `_run_place`): its step, and whether step 9 is delivered. A place that
  # cannot be read is doubt, and doubt is `open`.
  local place
  if ! place="$(_run_place "$plan" 2>/dev/null)"; then
    printf 'open|the place of %s cannot be read' "$plan"
    return 0
  fi
  current="$(sed -n 's/^n=//p' <<< "$place")"
  if [ -z "$current" ]; then
    printf 'open|%s carries no readable "current:" line' "$plan"
    return 0
  fi
  if [ "$current" != "9" ]; then
    printf 'open|%s is at current: %s' "$plan" "$current"
    return 0
  fi
  case "$place" in
    *state=delivered*) : ;;
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
  if ! declare -F proof_branch_head >/dev/null 2>&1; then
    [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh" 2>/dev/null
  fi
  declare -F proof_branch_head >/dev/null 2>&1 || return 0
  # The review proofs are the run's, read through the kept fold the schedule reads; a fold that fails is no head, and the
  # review waits.
  local pl
  pl="$(proof_lines "$SCHED_PLAN")" || return 2
  case "$pl" in *"proved: kind=review "*) : ;; *) return 0 ;; esac
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
    *) UNITS_FACTS_STATE="the reviews are judged once the regression holds"; return 0 ;;
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
  # Exit 2 is the judge's "could not deal" for a plan it cannot deal and for facts that did not fold alike; its line
  # on stderr tells them apart, so a fold that failed is never named as the plan's rigor and scale.
  out="$(facts_state "$SCHED_PLAN" "$head" 2>&1)"; rc=$?
  case "$rc:$out" in
    0:*) UNITS_FACTS_STATE=covered ;;
    2:*"could not be read"*) UNITS_FACTS_STATE="the run's facts could not be read: its facts did not fold; ask again" ;;
    2:*) UNITS_FACTS_STATE="the plan's rigor and scale cannot be dealt" ;;
    *) UNITS_FACTS_STATE="$(printf '%s\n' "$out" | awk -F'\t' 'NF > 1 && $NF != "covered"' \
         | awk -F'\t' '{ $1 = $1; printf "%s%s", (n++ ? "; " : ""), $0 }' OFS=' ')" ;;
  esac
  return 0
}

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
# A row that IS ready and was not offered says why: the writer gap is closed. Then one line for the longest remaining chain over the pending and
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
# ` · suspect: <id> reads <holder>, shares no file — loosen it: edit <id> in the plan: reads=…`,
# the loosening said and never made. The reason keeps `clean`'s 400-character cut; the clause is
# cleaned on its own and kept whole, because a cut edit names no cell.
# THE SPLIT CANDIDATE IS A DECISION WHILE WIDTH IDLES (wave-30 T16, REQ-12 AC-12.4, D14d; wave-38 T7, D22, REQ-6
# AC-6.5). The pending row of the chain `units_split_candidate` scores highest by fan-in × size × files is printed
# on its own line, after the CHAIN line,
#
#   poker: SPLIT <id> — <size> min, <n> files, <k> rows wait on it; width idles at <w>
#
# only when width idles: the gate gives room, every ready writer row was offered under the cap, and the gate
# still has room for one writer more (one `gate_room` asked past the rows offered, as `fill_gate_width` asks
# each). <w> is the writer width this tick fills to. A full fill, or no candidate (every pending row on the
# chain scores 0), prints no line. Through 1.20.0 it rode the CHAIN line as ` · SPLIT? …` on every tick, as
# advice whatever the width. Nothing is split: a split is the orchestrator's edit of the plan.
suspect_lines() {  # <plan> [<id>] -> `<id><TAB><holder><TAB><clause — loosen it: edit …>`, one per suspect; the one wording the WAIT line and task-add print
  units_suspect "$@" 2>/dev/null | awk -F'\t' 'NF >= 4 { printf "%s\t%s\t%s — loosen it: %s\n", $1, $2, $3, $4 }'
}

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
  # So are `brief=` and `brief_sum=`, the rendered file the dispatch was given and its sum: the latest row
  # is the one every reader asks, and a copy that dropped them would say the agent was given no file.
  for k in row lands_on brief brief_sum; do
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

# Order-keeping unions: the old value's members first, then each new member it lacks. A
# widening can never drop what the row already held.
poker_union() {  # <separator: , or space> <old list> <new list>... -> the union
  local sep="$1"; shift
  printf '%s\n' "$@" | awk -v sep="$sep" '
    { n = (sep == ",") ? split($0, a, ",") : split($0, a, /[ \t]+/)
      for (i = 1; i <= n; i++) if (a[i] != "" && !(a[i] in seen)) { seen[a[i]] = 1; out = out (out == "" ? "" : sep) a[i] } }
    END { print out }'
}

#
# EVERY PLAN-VERB REFUSAL NAMES THE CALL THAT SUCCEEDS (wave-33 T7; REQ-4 AC-4.3, D8). A refusal
# that says what is wrong and not what to run costs one retry per guess; wave-32 met three
# (a ledger verb's column names, task-add's approval read on a doc row, decline --on a file). Where the
# verb can compute the corrected call it prints it on a line of its own, `poker: next call: <call>`,
# quoted by the one rule every pasted poker command is (`launch_sync_hand`, refuse.sh
# `refuse_shell_word`), so the line runs as printed.
pv_next() {  # <verb> <operand>... -> the call on stderr, one line
  die "next call: $(launch_sync_hand "$@")"
}

# THE USER'S WORDS, REFUSED IN ONE VOICE. finding-move and a criterion's waiver hold their words to
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
  got="$(proof_lines "$plan")" || { FR_WHY="the run's facts cannot be read, so whether $(clean "$rec") is a registered review is not known; run it again"; return 1; }
  got="$(printf '%s\n' "$got" | awk -v ev="$rec" "$(proof_awk)"'
    proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION != "" && PROOF_EVIDENCE == ev { q = PROOF_QUESTION; h = PROOF_HEAD }
    END { if (q != "") print q "\t" h }')"
  if [ -z "$got" ]; then
    FR_WHY="$(clean "$rec") is no review the run registered (no review proof names it as its evidence); register it first: proof-add review $(clean "$rec") --question <question> --reader <name>"
    return 1
  fi
  FR_Q="${got%%	*}"; FR_H="${got#*	}"
  got="$(proof_findings "$(docs_root "$repo")/$rec" 2>/dev/null)" || got=""
  if ! printf '%s\n' "$got" | awk -F'\t' -v n="$n" '$1 == n { f = 1 } END { exit !f }'; then
    FR_WHY="the review $(clean "$rec") holds no finding $n (it holds $(printf '%s\n' "$got" | awk -F'\t' '$1 ~ /^[0-9]+$/ { printf "%s%s", (k++ ? ", " : ""), $1 } END { if (!k) printf "none" }'))"
    return 1
  fi
  IFS='	' read -r _ FR_S FR_R FR_W _ _ FR_T <<FINDING_READ
$(printf '%s\n' "$got" | awk -F'\t' -v n="$n" '$1 == n { print; exit }')
FINDING_READ
  got="$(proof_finding_rating "$plan" "$id" "$FR_S" "$FR_R")" || { FR_WHY="the run's facts could not be read, so the moves of $(clean "$id") are not known"; return 1; }
  set -- $got
  FR_P="${3:-}"
  return 0
}

# THE LAST RELEASE is lib/worktree.sh `release_base`, the one judge the verb, the hand scan and the release card read.

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

# The command a person runs for one of the plan-row verbs, quoted where it must be.
launch_sync_hand() {  # <verb> <operand>...
  local out a
  out="bash ${POKER_WORD} $1"; shift
  for a in "$@"; do out="$out $(refuse_shell_word "$a")"; done
  printf '%s' "$out"
}

sitrep_now() {  # -> now, epoch seconds: BIONIC_NOW_EPOCH when it is a number, else the clock
  case "${BIONIC_NOW_EPOCH:-}" in ''|*[!0-9]*) date -u +%s ;; *) printf '%s\n' "$BIONIC_NOW_EPOCH" ;; esac
}
sitrep_date() {  # <epoch> <strftime format> -> the local rendering, BSD date then GNU
  date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2" 2>/dev/null
}
sitrep_clock() {  # <epoch> <now epoch> -> `H:MM AM/PM`, then ` YYYY-MM-DD` when its local day is not now's
  local t
  t="$(sitrep_date "$1" '%-I:%M %p')"
  [ "$(sitrep_date "$1" '%Y-%m-%d')" = "$(sitrep_date "$2" '%Y-%m-%d')" ] || t="$t $(sitrep_date "$1" '%Y-%m-%d')"
  printf '%s\n' "$t"
}

# ---------------------------------------------------------------- the plan transaction
#
# ONE TRANSACTION FOR A VERB THAT STILL WRITES THE PLAN. The change is projected onto a
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
# is a WRITER's commit: past Step 4 the dry copy carries `current: 4`,
# because a main-root commit during Verify is held to the Step-5 block the run is still
# writing. `current` is the one exception — what it asks is
# whether the run can commit at the step it moves to, so its copy is judged as it stands.
#
# MAIN THREAD ONLY is the Bash wall's to enforce (payload/scripts/lib/walls.sh, the
# `agent_id` verb list); these refuse what the script can see: no session key (3), an
# unengaged session (decides nothing, 0), and a session with no BOUND open plan (1) — a
# writing verb never writes the newest-plan fallback.

# plan_delivered <plan> -> 0 when the file is a run closed by delivery: `run_open` calls it closed (not unreadable) and
# the reader's state, read with it, is delivered, never abandoned. 1 otherwise, silent. The plan is judged where it
# lies, so an archived plan is still its run's: lib/binding.sh `bind_delivered` asks the same of a docs-root candidate
# only, which an archived plan is not.
plan_delivered() {
  local rc=0
  [ -f "${1:-}" ] || return 1
  run_open "$1" || rc=$?
  [ "$rc" -eq 1 ] || return 1
  case "${_PROOF_PLACE:-}" in *state=delivered*) return 0 ;; esac
  return 1
}

# plan_verb_open <verb> [closed-ok] -> sets PV_REPO, PV_PLAN, PV_CUR, PV_NEW, PV_DRY, PV_MARK, PV_SID and arms the
# cleanup; exits on every refusal above. `closed-ok` (handoff) also takes the session's own closed run (bound-closed)
# when its plan is on disk. ENGAGEMENT IS THE CONSENT BOUNDARY FOR A RUN STILL MOVING, so it is asked first.
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
  PV_PLAN=""
  run="$(session_run "$PV_REPO" "$sid")"
  case "$run" in
    'bound-open '*) PV_PLAN="${run#bound-open }" ;;
    'bound-closed '*) [ "$closed" = "" ] || [ ! -f "${run#bound-closed }" ] || PV_PLAN="${run#bound-closed }" ;;
  esac
  if [ -z "$PV_PLAN" ]; then
    die "REFUSED — $verb writes the plan this session is bound to, and it has no bound open run (${run:-none})."
    die "Bind this session to its run first (this script's bind verb), then run $verb again."
    case "$run" in
    esac
    exit 1
  fi
  # The run's step as the reader answers it (lib/fill.sh over lib/proof.sh `proof_step_held`). A step that cannot be read
  # is no step, and PV_CUR_UNREAD says so: a verb that judges or writes at the step refuses on it, never on a guess.
  PV_CUR=""; PV_CUR_UNREAD=""
  if _fill_current_load "$PV_PLAN"; then PV_CUR="$_FILL_CURRENT_VALUE"; else PV_CUR_UNREAD=1; fi
  PV_NEW="${PV_PLAN}.${verb}.$$"
  PV_DRY="${PV_PLAN}.${verb}-dry.$$"
  PV_SID="planverb-$$"
  PV_MARK="$(engaged_marker_path "$PV_REPO" "$PV_SID")" || PV_MARK=""
  trap 'rm -f "$PV_NEW" "$PV_NEW.2" "$PV_DRY" ${PV_MARK:+"$PV_MARK"}' EXIT
}

# plan_verb_dry <verb> <what changed> <dry: writer|as-is|step:<N>> <current> -> the dry commit of $PV_NEW
# through the real gate, at `current: 4` for a writer past Step 4 and as written otherwise; exits 1
# on the gate's refusal, 2 when it cannot run.
# `step:<N>` judges no copy: the gate is asked about the plan itself with step N pending in its facts (BIONIC_DRY_STEP,
# honoured only for this session, lib/proof.sh `_proof_dry_step`), so the advance is judged as a commit at N would be.
plan_verb_dry() {
  local verb="$1" what="$2" dry="$3" cur="$4" err rc judged="$PV_DRY" step=""
  case "$dry" in step:*) step="${dry#step:}"; judged="$PV_PLAN" ;; esac
  if [ -n "$step" ]; then
    :
  elif [ "$dry" = writer ] && [ "$cur" -gt 4 ]; then
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
  if [ -n "$step" ]; then printf 'plan=%s\nengaged_at=%s\n' "$judged" "$(iso_now)"
  else printf 'plan=%s\ndry_of=%s\nengaged_at=%s\n' "$judged" "$PV_PLAN" "$(iso_now)"; fi > "$PV_MARK"
  err="$(cd "$PV_REPO" && BIONIC_DRY_STEP="$step" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$PV_SID" BIONIC_WALL_VERBOSE=1 \
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
    printf "the line '- Step %s: <its evidence>' under ## SDLC State (an edit of the plan writes it)" "$n"
    return 0
  fi
  n="$(printf '%s\n' "$1" | sed -n 's/.*step \([0-9][0-9]*[ab]\{0,1\}\) evidence missing required field(s): \(.*\)$/\1/p' | head -1)"
  f="$(printf '%s\n' "$1" | sed -n 's/.*step [0-9][0-9]*[ab]\{0,1\} evidence missing required field(s): \(.*\)$/\1/p' | head -1)"
  if [ -n "$n" ] && [ -n "$f" ]; then
    printf "the Step %s block's %s (an edit of the plan writes each)" "$n" "$(printf '%s' "$f" | awk '{ for (i = 1; i <= NF; i++) printf "%s%s:", (i > 1 ? " " : ""), $i }')"
    return 0
  fi
  printf '%s\n' "$1" | awk '
    /^bionic: / { seen = 1; next }
    seen && NF { sub(/^[ \t]+/, ""); sub(/^canonical-sdlc /, ""); print; found = 1; exit }
    END { if (!found) print "the line or block that step owes (the gate gave no detail)" }'
}

# ---------------------------------------------------------------- the parts' state
#
# Every global a part reads, set here before any part loads: the script runs set -u, and a part sets nothing of its
# own. Each group is headed by the part that reads it; the text that explains each value stays beside the
# functions that read it, in that part.
# the roster
RUN_LOG=""; RUN_PID=""; RUN_NAME=""; RUN_ROSTER=""; RUN_ROW_RC=""; RUN_STARTED=""
RUN_STATE=""; RUN_RC=""; RUN_ID=""; RUN_LAST_WRITTEN=""; RUN_PROGRESS=""; RUN_ELAPSED=""
ADOPT_READS_SCHEMA="adopt-read/v1"
# The handoff's two time lines: `written:` is the local clock a person reads, `instant:` the ISO instant a reader
# compares. A file from before the pair carries the instant on `written:` alone, so that form reads as a fallback.
_HANDOFF_ISO_RE='^(written|instant): [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$'
_ROW_SHORT_AWK='
  function row_short(t,   c, i) {
    c = length(t) + 1
    i = index(t, "("); if (i && i < c) c = i
    i = index(t, ". "); if (i && i < c) c = i
    i = index(t, " · "); if (i && i < c) c = i
    t = substr(t, 1, c - 1); sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t); sub(/\.$/, "", t); return t
  }'
LAUNCH_SYNC_WAIT=60
LAUNCH_SYNC_STALE=120
LAUNCH_SYNC_LOCK=""
LS_PROOFS=""; LS_PROOFS_READ=no
SWEEP_SCHEMA="poker-sweep/v1"
# the situation report; the release approval card marks a goal met, not met or not measured with these three
SCORECARD_STOP_GAP=600
SITREP_MARK_WITHIN='✅'
SITREP_MARK_OVER='✖️'
SITREP_MARK_NONE='❔'
# the tick
SCHED_HOLDS=""
TICK_CARRIERS=""; TICK_CARRIERS_READ=no
TICK_QUIET_MTIME=""; TICK_QUIET_CHANNEL=""; TICK_QUIET_AGE=""; TICK_QUIET_CAD=""
# the plan verbs
POKER_BRIEF_WORDS=""
BFB_OF=""; BFB_OWED=""; BFB_BRANCH=""
PFC_OUT=""; PFC_ART=""

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

  # THE MACHINE'S SHARE. The share is one integer, 1 to 100, in
  # `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/share`; with no file the gate's share is 92. The reserve is the
  # cores the person keeps, a decimal from 0 to the machine's cores, in `bionic/reserve` beside it; with no file
  # it is 1. Printing asks the gate's own readers (`gate_share`, `gate_reserve`, `_res_cores`, `_gate_share_cores`),
  # so what this prints is what the gate decides on and no arithmetic is kept here. Setting writes each file by
  # the SAME path expression the gate reads (not `claude_home`, which BIONIC_CLAUDE_HOME moves), through a staged
  # copy and a rename so a reader never sees half a number. It is the machine's and not a run's: no session key,
  # roster or engagement is read, and nothing but those files is written. Both values are judged before either is
  # written. REFUSED: a share that is not a whole number from 1 to 100 (leading zeros read as decimal) exits 1; a
  # reserve that `gate_reserve_ok`, the reader's own rule, refuses exits 2; a file that cannot be written exits 1; whichever
  # it is, both files are as they were. The contract-verb arm of the bash wall lists `share`, so a subagent may
  # call no form of it.
  share)
    SH_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic"
    if [ "$SH_SET" = no ] || [ "$SH_RSET" = yes ]; then
      if ! declare -F _gate_share_cores >/dev/null 2>&1; then
        die "REFUSED — lib/gate.sh did not load, so the share cannot be read."
        exit 3
      fi
    fi
    if [ "$SH_SET" = no ] && [ "$SH_RSET" = no ]; then
      printf 'share=%s reserve=%s cores=%s room=%s\n' \
        "$(gate_share)" "$(gate_reserve)" "$(_res_cores)" "$(_gate_share_cores)"
      exit 0
    fi
    if [ "$SH_SET" = yes ]; then
      case "$SH_ARG" in
        ''|*[!0-9]*) SH_BAD=yes ;;
        *) if [ "${#SH_ARG}" -gt 9 ]; then SH_BAD=yes
           else SH_N=$((10#$SH_ARG)); if [ "$SH_N" -ge 1 ] && [ "$SH_N" -le 100 ]; then SH_BAD=no; else SH_BAD=yes; fi; fi ;;
      esac
      if [ "$SH_BAD" = yes ]; then
        die "REFUSED — share $(printf '%q' "${SH_ARG:0:20}") is not a whole number from 1 to 100; the share is unchanged."
        exit 1
      fi
    fi
    if [ "$SH_RSET" = yes ] && ! gate_reserve_ok "$SH_RES"; then
      die "REFUSED — reserve $(printf '%q' "${SH_RES:0:20}") is not a decimal from 0 to the machine's cores ($(_res_cores)); usage: share [<1-100>] [reserve=<cores>]; nothing was changed."
      exit 2
    fi
    mkdir -p "$SH_DIR" 2>/dev/null || { die "REFUSED — the share file could not be written; the share is unchanged."; exit 1; }
    for SH_W in "share:$SH_SET:${SH_N:-}" "reserve:$SH_RSET:$SH_RES"; do
      IFS=: read -r SH_NAME SH_DO SH_VAL <<< "$SH_W"
      [ "$SH_DO" = yes ] || continue
      SH_TMP="$SH_DIR/$SH_NAME.tmp.$$"
      if printf '%s\n' "$SH_VAL" > "$SH_TMP" 2>/dev/null && mv -f "$SH_TMP" "$SH_DIR/$SH_NAME" 2>/dev/null; then
        say "$SH_NAME set to $SH_VAL"
      else
        rm -f "$SH_TMP" 2>/dev/null
        die "REFUSED — the $SH_NAME file could not be written; the $SH_NAME is unchanged."
        exit 1
      fi
    done
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
  # reason in prose on every tick, and all 29 of that run answered nothing a wall had asked. A FILL
  # is answered by its dispatch alone: a row that should wait is made not ready by a fact the tick
  # judges, never answered ready by a sentence, and the prompt names no verb for it. Each answer is now conditional on the line that owes it, ListAgents on an open
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
    printf 'bionic-patrol session=%s v=%s — Patrol tick. ListAgents only when the roster has an open row, then run: bash %s tick — the tick decides per row. If it printed only "unchanged", or a "poker: WAITING" line, the run is waiting on its agents and this turn owes nothing more: end it. Answer a FILL only if a "poker: FILL" line printed: dispatch every row it names (its launch records the row active and its ledger line: write neither by hand); a row that should wait is made not ready instead, by one of the three forms the stop wall prints. Answer a STANDDOWN only if a "poker: STANDDOWN" line printed: TaskStop it, or keep it up with the hold line it prints: bash %s hold NAME %s, NAME as printed and the reason inside the quotes. A gate= field on the decision line means a reserved request was denied: put each "poker: GATE" line to the human as a gate act, through the human'"'"'s own notify channel, and do not perform it. TaskList and reconcile only if a "poker: RECONCILE" line printed. After you re-arm this Patrol, say exactly: "%s" Continue the run toward its goal until a wall only when something is ready or changed.\n' \
      "${SESSION_ID:0:8}" "$PATROL_PROMPT_VERSION" "$POKER_WORD" "$POKER_WORD" "$HOLD_REASON_SLOT" "$PATROL_REARM_SAY"
    exit 0
    ;;

esac

# ---------------------------------------------------------------- the parts
#
# Every verb below lives in a part under hooks/poker/, one file per concern; the verbs above need none of them. The
# seven load here, in this order, after every global above is set, and a part defines functions only. A part calls
# only a part loaded before it: the situation report, the tick and the release check read the line's landing report,
# and the tick prints the situation report's one line. A part that cannot be read leaves its verbs unanswerable, and
# the script steps aside as it does for a missing library.
poker_part_missing() {  # <part> -> exits as loader_fail_open does, naming the part file it could not read
  BIONIC_LIB_MISSING="poker/$1.sh"; BIONIC_LIB_CANDS="$HOOK_DIR/poker"
  loader_fail_open "session-poker"
}
{ [ -r "$HOOK_DIR/poker/roster.sh" ] && . "$HOOK_DIR/poker/roster.sh"; } || poker_part_missing roster
{ [ -r "$HOOK_DIR/poker/line.sh" ] && . "$HOOK_DIR/poker/line.sh"; } || poker_part_missing line
{ [ -r "$HOOK_DIR/poker/sitrep.sh" ] && . "$HOOK_DIR/poker/sitrep.sh"; } || poker_part_missing sitrep
{ [ -r "$HOOK_DIR/poker/tick.sh" ] && . "$HOOK_DIR/poker/tick.sh"; } || poker_part_missing tick
{ [ -r "$HOOK_DIR/poker/plan.sh" ] && . "$HOOK_DIR/poker/plan.sh"; } || poker_part_missing plan
{ [ -r "$HOOK_DIR/poker/proof.sh" ] && . "$HOOK_DIR/poker/proof.sh"; } || poker_part_missing proof
{ [ -r "$HOOK_DIR/poker/judge.sh" ] && . "$HOOK_DIR/poker/judge.sh"; } || poker_part_missing judge

case "$VERB" in
  arm) poker_verb_arm "$@" ;;
  disarm) poker_verb_disarm "$@" ;;
  adopt) poker_verb_adopt "$@" ;;
  sweep) poker_verb_sweep "$@" ;;
  bind) poker_verb_bind "$@" ;;
  extend) poker_verb_extend "$@" ;;
  hold) poker_verb_hold "$@" ;;
  rule|ruling-ack|rulings) poker_verb_rule "$@" ;;
  amend) poker_verb_amend "$@" ;;
  task-add) poker_verb_task_add "$@" ;;
  reviews-part) poker_verb_reviews_part "$@" ;;
  known-limits-part) poker_verb_known_limits_part "$@" ;;
  handoff) poker_verb_handoff "$@" ;;
  brief) poker_verb_brief "$@" ;;
  current) poker_verb_current "$@" ;;
  reply) poker_verb_reply "$@" ;;
  release-approval) poker_verb_release_approval "$@" ;;
  approve) poker_verb_approve "$@" ;;
  order) poker_verb_order "$@" ;;
  proof-add) poker_verb_proof_add "$@" ;;
  waive) poker_verb_waive "$@" ;;
  finding-move) poker_verb_finding_move "$@" ;;
  disposition) poker_verb_disposition "$@" ;;
  release-check) poker_verb_release_check "$@" ;;
  regression-run) poker_verb_regression_run "$@" ;;
  debt) poker_verb_debt "$@" ;;
  landing-report) poker_verb_landing_report "$@" ;;
  release-note) poker_verb_release_note "$@" ;;
  decisions) poker_verb_decisions "$@" ;;
  promote) poker_verb_promote "$@" ;;
  resume) poker_verb_resume "$@" ;;
  sitrep) poker_verb_sitrep "$@" ;;
  stop-run) poker_verb_stop_run "$@" ;;
  tick) poker_verb_tick "$@" ;;
esac
