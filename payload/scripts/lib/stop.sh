#!/bin/bash
# payload/scripts/lib/stop.sh — THE FOUR TURN-END VERDICTS, AS FUNCTIONS
# (epic-23 wave-11-lean-spine, REQ-1f (iv); spec Design §2 D4, §3 ownership row
# "turn-end verdict"; ADR-004.)
#
# WHAT IT OWNS. The bodies of the four hooks that used to fire on Stop, one
# function each, in the order hooks.json listed them:
#
#   stop_context_spend   the instrument — one audit line per SDLC step boundary
#   stop_landing_gate    the sweep and the teammate landing verdict
#   stop_patrol_duties   the fill gap and the stand-down the tick ordered
#   stop_patrol_revive   the watcher that died without a word, said once
#
# NO BEHAVIOUR MOVED (R2). Each function is the corresponding hook's body after
# its preamble, carried over verbatim — its own arms, its own reads, its own
# refusal object — with four mechanical changes, and one deliberate fifth that the
# event section below names and explains (stop_context_spend's new SubagentStop guard):
#
#   1. `exit 0`            -> `return "$_adv"`, the function's own verdict
#   2. `refuse <mode> …`   -> `fold_block <mode> …` + `return 2`
#   3. an advisory `echo … >&2` -> `fold_advise …` + `_adv=1`
#   4. every variable the body assigns is `local`
#
# (1)–(3) exist because a folded function must not exit and must not render:
# payload/scripts/lib/fold.sh runs these in the CALLER'S shell and composes what
# they stage. (4) exists because they now share one shell: `LINE`, `STATE`,
# `PLAN`, `VERDICT` and `REASON` are each assigned by more than one of the four,
# and a global would let one verdict read another's half-finished value.
#
# THE VALUES COME FROM `bionic_context`, ONCE, IN THE CALLER (REQ-1h, lib/context.sh).
# Every function below reads BIONIC_INPUT, BIONIC_ROOT, BIONIC_SID, BIONIC_ENGAGED,
# BIONIC_RUN_WORD and BIONIC_RUN_PLAN as values it did not fetch. That is what
# collapses four identical preambles into one and it is also what makes the four
# agree: four hooks each spelling the cwd ladder their own way could attribute one
# session's stop to two different roots.
#
# ── THE EVENT IS AN ARGUMENT, AND EVERY FUNCTION READS IT ─────────────────────
#
# `hooks/stop.sh` is registered on Stop AND SubagentStop, so each function is
# handed the event name and answers for itself:
#
#   stop_landing_gate    Stop -> the sweep; SubagentStop -> the landing verdict.
#                        Its own `case` moved here unchanged; it is the only one of
#                        the four with a SubagentStop arm at all.
#   stop_patrol_duties   Stop only. A subagent has no Patrol duties.
#   stop_patrol_revive   Stop only. A subagent arms no Patrol.
#   stop_context_spend   Stop only — AND THIS GUARD IS NEW, which is a change worth
#                        naming rather than burying. hooks/context-spend.sh read no
#                        `hook_event_name` at all (`grep -n hook_event_name
#                        hooks/context-spend.sh` printed nothing); it never needed
#                        to, because the manifest registered it on Stop alone. The
#                        merged process is also on SubagentStop, so without this
#                        line the instrument would start recording step boundaries
#                        on every teammate landing — a behaviour it never had. The
#                        guard preserves what it did, it does not add a rule.
#                        tests/context-spend.test.sh §1b pins the before and after.
#
# THE RE-ENTRANCY GUARD IS NOT HERE. `stop_hook_active` is read ONCE, in
# hooks/stop.sh, ahead of all four — three of the four carried an identical copy of
# it and the fourth (context-spend, again) carried none. One reading of one field is
# the point of the merge.
#
# BASH 3.2. No associative arrays, no `mapfile`.
#
# SOURCED, NEVER EXECUTED, AND SILENT AT SOURCE TIME.
#
# [WALL: tests/stop.test.sh]
# [WALL: tests/context-spend.test.sh]
# [WALL: tests/landing-gate.test.sh]
# [WALL: tests/patrol-duties-gate.test.sh]
# [WALL: tests/patrol-revive.test.sh]

declare -F bionic_need >/dev/null 2>&1 || case "${BASH_SOURCE[0]}" in */*) . "${BASH_SOURCE[0]%/*}/loader.sh" ;; *) . ./loader.sh ;; esac
bionic_need fold.sh bionic_fold

# RESOURCES.SH IS SOURCED THE SAME WAY (wave-18 T2b, R1): `hooks/stop.sh`'s own
# `BIONIC_LIB_WANT` does not name it, and this row's Files: declaration is this file
# alone, so the dependency is met here rather than by widening the hook's want-list. The gate
# (lib/gate.sh, which the fill duty asks through fill.sh) reads its readers.
bionic_need resources.sh _res_used_pct

# ─── FILE SCOPE: hooks/context-spend.sh's audit path ─────────────────────────
#
# `audit_path` LIVES IN root.sh NOW (epic-23 wave-12-fixit-171, REQ-8, spec D6). This file
# carried the third of three byte-identical copies, at column zero, under a header asking
# each next reader to keep them identical. tests/cross-gate-agreement.test.sh §AP is a COUNT
# now — exactly one definition under hooks/ and payload/ — rather than a checksum comparison
# of three bodies that could always part again.
#
# SOURCED THE WAY fold.sh IS, ten lines above, and for the same reason: hooks/stop.sh already
# sources root.sh at :153, above this library at :165, so in the shipped process this guard
# never fires. It is here for the suites that drive this file directly.
bionic_need root.sh audit_path

# ─── FILE SCOPE: the unbound advisory, said once per process ─────────────────
#
# UNBOUND MEANS NO RUN (wave-23-fixit-1810, REQ-1, D1). When `session_run` answers
# `fallback <plan>`, every arm below that would have acted on the plan announces it and
# then takes its `none` path: the plan is announced and never acted on. The words are
# lib/run.sh's `run_unbound_advisory`, never a copy, so the five arms here and the dispatch
# wall say one byte-identical thing (tests/cross-gate-agreement.test.sh §UB).
#
# ONCE PER PROCESS, because the four verdicts share one shell and one turn end. Three of
# them meet the same `fallback` on the same Stop; a reader shown the same sentence three
# times learns nothing the first did not say (tests/stop.test.sh §UB3 pins once). The first
# arm to meet it speaks and returns 0, and the caller marks its verdict advisory; every
# later arm returns 1 and stays quiet. Sourced again in a fresh process, it speaks again.
#
# run.sh IS SOURCED HERE for the suites that drive this file directly, the way root.sh is
# above; hooks/stop.sh sources it first, so in the shipped process the guard never fires.
bionic_need run.sh run_unbound_advisory
stop_unbound_advise() {  # <plan> -> 0 staged · 1 already said in this process
  [ -z "${_STOP_UNBOUND_SAID:-}" ] || return 1
  _STOP_UNBOUND_SAID=1
  fold_advise "$(run_unbound_advisory "${1:-}")"
}

# ─── FILE SCOPE: the `## Tasks` table, which this file must not parse ────────
#
# THE ROW IS THE TREE'S RECORD (epic-23 wave-17, REQ-2, D3, ADR-032). The landing gate needs
# one cell of it — the commit a task tree was cut from — and `payload/scripts/lib/units.sh`
# is the ONE reader of that table; a second parser here would be the exact duplication that
# library exists to stop, and it would be the copy nobody updates when a column moves.
#
# SOURCED THE WAY fold.sh AND root.sh ARE, and guarded on the verb this file
# actually calls. hooks/stop.sh does not source it — no other verdict in this process reads
# the table — so in the shipped process this guard is what loads it, and a caller that has it
# already (the evidence gate's own process, a suite driving this library directly) pays
# nothing. units.sh defines functions and runs nothing at source time, which is why sourcing
# it here costs one parse and no forks.
bionic_need units.sh units_rows

# ─── FILE SCOPE: the ready set, which this file must not compute twice ───────
#
# READINESS IS A PROPERTY OF THE UNIT (epic-23 wave-18, REQ-3, D2, ADR-033 decision 2).
# `stop_patrol_duties`' fill arm used to be entirely derivative of the tick having PRINTED a
# line: no `poker: FILL` in the turn, no duty. That makes a wall a function of the Patrol's
# cadence rather than of the run's state, and a turn that ended with three rows ready twenty
# minutes before the next tick ended in silence. `payload/scripts/lib/fill.sh` is the one
# computation of the ready set — the same function the tick prints from — so the arm asks the
# question itself and the two can never name different rows.
#
# SOURCED THE WAY fold.sh, root.sh AND units.sh ARE, and guarded on the verb this
# file calls. hooks/stop.sh DOES name this one in its `BIONIC_LIB_WANT` — unlike units.sh,
# which no verdict in that process reads directly — so in the shipped process the loader has
# already checked it is readable and this guard is what a suite driving the library alone
# pays. fill.sh sources units.sh under the same kind of guard, so the pair arrives together.
bionic_need fill.sh fill_ready_set

# THE RUN'S FACTS, LOADED AS THE TICK LOADS THEM. The step, the Step-3 approval, the standing order and the newest
# review proof are the reader's answers (`fill_facts_load`), so a fact the run's log alone holds is this wall's fact
# as it is the tick's, and the two never judge one turn on two readings. Once per process, and only for a bound open
# run: every verdict below that reads them reads that plan, and a SubagentStop that reaches none pays nothing. A
# reader that cannot load leaves the fill to read the plan as it does for every other caller.
stop_facts_load() {  # -> always 0
  [ -z "${_STOP_FACTS_DONE:-}" ] || return 0
  _STOP_FACTS_DONE=1
  [ "${BIONIC_RUN_WORD:-}" = bound-open ] && [ -n "${BIONIC_RUN_PLAN:-}" ] || return 0
  fill_facts_load "$BIONIC_RUN_PLAN" >/dev/null 2>&1 || :
}

# THE TICK'S DIGEST AND THE WATCH RECORD: patrol.sh owns both readers.
bionic_need patrol.sh tick_digest_path

# THE PERSON'S LEDGER AND ITS ONE SENDER (epic-23 wave-33-workhorse, T11; REQ-2, D2): owed.sh
# keeps what the person owes, and sources notify.sh beside it. NOT in hooks/stop.sh's
# `BIONIC_LIB_WANT`, and sourced only when readable: the send is never a reason for this process
# to step aside, and a library without it (a copy older than this wave) sends nothing and changes
# nothing else.
bionic_need owed.sh owed_send || :

# ─── FILE SCOPE: the hook's own directory, resolved at most once ─────────────
#
# THREE VERDICTS ASKED THE SAME QUESTION THREE TIMES (REQ-10, T11): `stop_landing_gate`
# for its sibling sweeper, `stop_patrol_duties` and `stop_patrol_revive` for the poker
# they name in a message. Each spelled it `"$(cd "$(dirname "$0")" && pwd)"` — a
# `dirname` fork, a subshell and a `cd` per ask, five forks across one Stop for a value
# that cannot change inside one process, because `$0` is the hook however deep the call
# is.
#
# TWO ANSWERS, NOT ONE, because the three call sites did not agree on the fallback and
# collapsing them would be a silent behaviour change. `_STOP_HOOK_DIR_ABS` is the
# `cd … && pwd` answer and stays EMPTY when the directory cannot be entered — which is
# exactly what `SWEEPER` interpolated. `_STOP_HOOK_DIR_RAW` is `dirname`'s own answer,
# which the two `HOOK_DIR` sites fall back to when the first is empty.
#
# NO `dirname` FORK AT ALL. `${0%/*}` is dirname's answer for every path carrying a
# slash, `.` for one that does not, and `/` for a path whose only slash is the leading
# one; a hook is always invoked by path, so this is the same string the fork returned.
_stop_hook_dirname() {  # -> _STOP_HOOK_DIR_RAW, dirname "$0" without the fork
  case "$0" in
    */*) _STOP_HOOK_DIR_RAW="${0%/*}"; [ -n "$_STOP_HOOK_DIR_RAW" ] || _STOP_HOOK_DIR_RAW="/" ;;
    *)   _STOP_HOOK_DIR_RAW="." ;;
  esac
}
_stop_hook_dirname
_STOP_HOOK_DIR_ABS="$(cd "$_STOP_HOOK_DIR_RAW" 2>/dev/null && pwd)"

# ─── FILE SCOPE: hooks/landing-gate.sh's constants and helpers ───────────────
#
# AT COLUMN ZERO, DELIBERATELY. `SWEPT_SCHEMA` and `swept_marker_write` are read
# out of this file by extraction — tests/cross-gate-agreement.test.sh §S15 pins the
# writer against a captured marker with `awk '/^swept_marker_write\(\)/,/^}/'` and
# §S15b pins the constant's assignment line with `grep -m1 '^SWEPT_SCHEMA='`. Both
# anchor at the start of a line, so these keep their margin; indenting them into a
# function would make the pin go quietly vacuous rather than red.


SWEPT_SCHEMA="landing-swept/v1"
# Reader copy of hooks/dispatch-preflight.sh's roster constant, on the same precedent
# hooks/session-sweeper.sh states for its copy: a prefix drift here is a mislabeled scan.
ROSTER_VERSION="v1"

# THE ONE WRITER (S15, AC-26; research-code-map §2.c). Defined here, not sourced from a
# shared lib file: this hook's own `BIONIC_LIB_WANT` stays "root.sh run.sh session.sh"
# unchanged, and a copy of this file (as tests/landing-gate.test.sh's own mutation-arm
# fixtures make) carries the writer with it rather than depending on a lib file resolving
# through the loader's registry/cache fallback to whatever was last landed there.
# hooks/session-poker.sh's `adopt_copy_marker` never calls this function — its job is to
# relay a line this one already wrote, verbatim — but it DOES share the `SWEPT_SCHEMA`
# constant above, spelled identically (byte-pinned, tests/cross-gate-agreement.test.sh),
# never as a second literal the way `grep -rn SWEPT_SCHEMA hooks/*.sh` could miss.
swept_marker_write() {  # <roster file> <at> <session> <name> <agent id> <state> -> 0/1
  local f="$1" at="$2" sid="$3" name="$4" aid="$5" state="$6"
  [ -n "$f" ] || return 1
  printf '%s|at=%s|session=%s|name=%s|agent_id=%s|state=%s\n' \
    "$SWEPT_SCHEMA" "$at" "$sid" "$name" "$aid" "$state" >> "$f" 2>/dev/null
  return 0
}

# ---------------------------------------------------------- FILES: RECONCILIATION (S18, AC-22)
#
# DECLARE -> DERIVE -> RECONCILE (design ledger D2). `hooks/dispatch-preflight.sh` derives a
# BUDGET from a brief's `Files:` at dispatch; these two functions are the third leg — asking,
# once a row is landed, whether the diff the agent actually produced stayed inside that same
# declared set. Called from the per-candidate loop below, never from the sweeper: the
# sweeper answers about the DELIVERABLE, this answers about the DIFF, and the two questions
# share a candidate line but not a verdict.

# The row's worktree, by the ONE mapping the fleet has for "which tree belongs to whom"
# (payload/scripts/lib/worktree.sh's `worktree_for_row`, sourced above as `BIONIC_LIB_WANT`
# declares). That function only builds a path string — it lowercases the row name and never
# stats anything — which a case-INSENSITIVE filesystem (macOS, this wave's covered
# environment) resolves against a mixed-case directory for free. A case-SENSITIVE one
# (Linux, fog) would not, so the fallback below scans the farm by lowercased basename before
# giving up; it is the one place this file re-derives any part of the mapping, and it does
# so only to absorb a filesystem property `worktree_for_row` does not, never to re-decide
# which directory a row's name means.
_lg_worktree_for_name() {  # <repo> <row name> -> abs worktree path on stdout, or nothing
  local repo="$1" name="$2" cand d base lc
  if declare -f worktree_for_row >/dev/null 2>&1; then
    cand=$(worktree_for_row "$repo" "$name" 2>/dev/null)
    if [ -n "$cand" ] && [ -d "$cand" ]; then printf '%s' "$cand"; return 0; fi
  fi
  lc=$(printf '%s' "${name#W-}" | tr '[:upper:]' '[:lower:]')
  [ -n "$lc" ] && [ -d "$repo/.worktrees" ] || return 1
  for d in "$repo"/.worktrees/*/; do
    [ -d "$d" ] || continue
    base=$(basename "$d")
    if [ "$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')" = "$lc" ]; then
      printf '%s' "${d%/}"
      return 0
    fi
  done
  return 1
}

# WHICH `## Tasks` ROW OWNS THIS TREE, AND WHAT ORIGIN IT DECLARES (epic-23 wave-17,
# REQ-2, D3, ADR-032).
#
# THE MATCH IS THE ONE THE EVIDENCE GATE ALREADY MAKES (`_eg_row_for_worktree`,
# payload/scripts/lib/walls.sh): the row's `worktree` cell, trailing slash stripped, compared
# by BASENAME — so a cell holding `17-T3`, `.worktrees/17-T3` or an absolute path all name
# the same tree, and two walls reading one record can never disagree about which row that is.
#
# THE BASENAME ARRIVES CASE-FOLDED ON A CASE-INSENSITIVE FILESYSTEM (macOS: the lowercased
# path `worktree_for_row` builds already exists, so `_lg_worktree_for_name`'s `-d` takes it
# as-is) AND IN THE TREE'S OWN CASE OTHERWISE (a case-sensitive filesystem fails that `-d`
# and the fallback scan above returns the real name, case and all) — so the cell is compared
# case-folded too (L1, hit epic-23 wave-17 T41), which covers both classes: `_want` is
# `${LG_WT##*/}` at the call site, and `LG_WT` comes from `_lg_worktree_for_name` above,
# which resolves through `worktree_for_row` — the fleet's one name-to-path mapping, whose own
# docblock says it lowercases the row name before building the path. A plan row spelled with
# capitals (every real row this wave: `17-T<n>`) then never
# matched a case-sensitive compare, so `_LG_ROW_ID`/`_LG_ROW_BASE` stayed empty and REQ-2's
# declared-base feature went silently inert. Folding both sides here, rather than un-folding
# `_want`, keeps the one mapping in one place — this function absorbs the case the mapping
# already threw away instead of trying to recover it.
#
# IT ASSIGNS RATHER THAN PRINTS, and returns 3 on a collision, for that function's own
# reasons: two answers do not fit in a command substitution, and a wall that cannot tell
# which row owns a tree must not pick one. The caller treats 3 as "no declared origin" and
# says so — the conservative direction, because the fallback it then takes is announced.
#
# A CELL THAT NAMES NO COMMIT IS NO CELL. An em dash, a hyphen, a space and an empty cell are
# one fact spelled four ways — the same reading `units_ready` gives its own `deps` cell and
# `units_validate` gives this one — and all four mean the row declares no origin.
_lg_row_for_tree() {  # <plan> <tree basename> -> assigns _LG_ROW_ID, _LG_ROW_BASE; 3 = collision
  local _plan="${1:-}" _want="${2:-}" _rows _line _cell
  _LG_ROW_ID=""; _LG_ROW_BASE=""
  [ -n "$_plan" ] && [ -n "$_want" ] || return 0
  declare -F units_rows >/dev/null 2>&1 || return 0
  _rows="$(units_rows "$_plan" 2>/dev/null)" || return 0
  _want="$(printf '%s' "$_want" | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    _cell="$(units_field "$_line" worktree)"
    [ -n "$_cell" ] || continue
    _cell="${_cell%/}"
    _cell="${_cell##*/}"
    [ "$(printf '%s' "$_cell" | tr '[:upper:]' '[:lower:]')" = "$_want" ] || continue
    if [ -n "$_LG_ROW_ID" ]; then
      _LG_ROW_ID=""; _LG_ROW_BASE=""
      return 3
    fi
    _LG_ROW_ID="$(units_field "$_line" id)"
    _LG_ROW_BASE="$(units_field "$_line" base)"
    case "$_LG_ROW_BASE" in *[A-Za-z0-9]*) ;; *) _LG_ROW_BASE="" ;; esac
  done <<< "$_rows"
  return 0
}

# Is a path the diff touched inside the declared set? Exact match, or under a declared
# DIRECTORY — "a declared directory covers its files" (S18 brief) — checked without caring
# whether the author spelled the directory with a trailing slash, or a root file with the
# leading `./` the Files: reader asks for when a bare name is not otherwise a path (wave-27
# T29; REQ-12, D21): `./Widgetfile` declares the diff path `Widgetfile`.
_lg_path_declared() {  # <diff path> <comma-joined declared files>
  local p="$1" list="$2" old_ifs entry
  old_ifs="$IFS"; IFS=','; set -f
  # shellcheck disable=SC2086
  set -- $list
  set +f; IFS="$old_ifs"
  for entry in "$@"; do
    entry="${entry%/}"
    entry="${entry#./}"
    [ -n "$entry" ] || continue
    [ "$p" = "$entry" ] && return 0
    case "$p" in "$entry"/*) return 0 ;; esac
  done
  return 1
}


# ─── THE BODIES KEEP THEIR MARGIN ────────────────────────────────────────────
#
# Every carried-over body below sits at COLUMN ZERO inside its function, which is
# not a style slip. Three things depend on it:
#
#   the diff        an indented copy is a changed copy, and this merge's whole
#                   claim is that the bodies did not change. `git show <base>:hooks/
#                   <h>.sh` and the corresponding span here differ only in the four
#                   mechanical edits the header names.
#   heredocs        `<<LGDIFF` and `<<EOF` in the sweep, and `<<BIONIC_LOADER_VER`
#                   in what they call, terminate on a line that is the tag and
#                   nothing else. Indenting the terminator makes the heredoc run to
#                   end-of-file, which is how this file first failed to parse.
#   the extractions tests/cross-gate-agreement.test.sh reads `_field()`,
#                   `swept_marker_write()` and `SWEPT_SCHEMA=` out of the source with
#                   `^`-anchored patterns.
#
# The `local` blocks that open each function are this file's own lines and are
# indented normally, so the margin change marks exactly where the new text stops and
# the carried-over text starts.


# ─── stop_context_spend ───
#
# THE HOOK'S OWN HEADER, CARRIED OVER WHOLE. It is the design record for this
# verdict — every ruling, incident and measurement that shaped it — and it
# travels with the code rather than being left behind in a deleted file.
# Where it says "this hook" it now means this function, and where it names a
# registration it means hooks/stop.sh's.
#
# CONTEXT-SPEND: advisory Stop hook — appends ONE context-spend line per
# SDLC step boundary to $HOME/.claude/logs/<project-slug>/sdlc-audit.md —
# outside every consuming project tree (incident 0001), via audit_path() —
# reusing the log_v11_finding() line format (source: context-spend).
#
# Mechanism (epic-08 A7 / Q2 spike): Stop = trigger + transcript_path;
# last assistant message.usage (TOP-LEVEL, never iterations[]) = occupancy
# (input + cache_creation + cache_read); the active plan's `current:` line
# = step attribution; .bionic/tmp/context-spend.state = boundary detector.
# [INSTRUMENT]
#
# Failure mode: silence. Missing jq/transcript/usage/plan/current →
# exit 0, nothing appended, state untouched. NEVER blocks, NEVER writes
# stdout (a Stop hook's stdout could carry a block payload).
# [INSTRUMENT]
#
# Registered once in hooks/hooks.json, always on, and scoped by an on-disk fact rather
# than by whether a skill is armed: it asks `session_run` (which was `active_run` until
# wave-session-bound-run made run identity per-session) whether THIS SESSION has an open run
# and exits silently when it does not.
#
# hooks/context-spend.sh's body. NEVER refuses and NEVER writes stdout — a Stop
# hook's stdout can carry a block payload — so its only verdicts are 0 and 1.

stop_context_spend() {  # <event> -> 0 nothing · 1 advisory · 2 block
  local _ev="${1:-}" _adv=0
  local TRANSCRIPT PLAN STEP _row MODEL OCCUPIED STATE_DIR STATE
  local s_plan s_sess s_step s_occ DELTA LINE AUDIT_FILE

  # THE EVENT GUARD THE HOOK NEVER HAD — see this file's header. Stop only, and an
  # absent field is not a mismatch, so a hand-run payload still measures.
  case "$_ev" in ""|Stop) : ;; *) return 0 ;; esac

  TRANSCRIPT=$(bionic_jq .transcript_path)
  [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || return 0

# ---------- THE ENGAGEMENT SWITCH — asked before anything else ----------
#
# task-engaged-session: bionic's walls are the RUN's, not the repo's, and a run is entered
# by invoking canonical-sdlc. A session that never did is a bystander here and must not see
# a refusal, an advisory, or a state write from this hook. `engaged_session` (lib/run.sh) is
# true only for a REGULAR file at `.bionic/tmp/engaged-<sid>.state`; every unreadable state —
# absent, symlink, foreign sid — reads as NOT engaged. Silent, return "$_adv": the direction §7
# gives every start-side ambiguity, and here it is the consent boundary itself (1.3.2
# close-out ruling). `bionic_context` asked the question above; this is the answer.
[ "$BIONIC_ENGAGED" = 1 ] || return "$_adv"

# ---------- THE RUN PREDICATE (AC-7, AC-8) ----------
#
# The plan AND the arming question, from one reader. This hook used to answer "which
# plan" with its own `ls -t` over three glob depths — a fourth spelling of a question
# five hooks were each answering differently, and the one that ignored the
# `## SDLC State` marker entirely, so any newest .md under plans/ could become the file
# it attributed a step boundary to.
#
# PLAN-BOUND, WHOLLY (task-engaged-session). Engagement decides WHETHER this hook acts and
# has decided yes above; what remains is the plan deciding WHAT, and every line below
# measures against it — the step boundary comes from the plan's `current:`, the state file
# is keyed by (plan, session), and the audit line names the plan. An engaged session with no
# plan on disk has no step boundary to record, so this arm skips rather than the hook being
# out of scope. The exit is an arm skip now, not the scoping decision it used to be.
#
# wave-session-bound-run S5: `active_run` (no session input) is now `session_run`
# (lib/run.sh) — a session BOUND to a plan is attributed against THAT plan alone,
# whatever else is open in the root (AC-1); bound to a plan that has since closed takes
# exactly this line's existing branch — the hard exit — after announcing the closure (AC-6).
# UNBOUND, the newest plan is announced and never acted on (wave-23-fixit-1810, REQ-1, D1):
# the advisory goes out on this hook's advisory channel (stderr — this hook NEVER writes
# stdout, see the header) and the arm takes `none`'s exit, so no spend is recorded against
# a run that is somebody else's.
PLAN="$BIONIC_RUN_PLAN"
case "$BIONIC_RUN_WORD" in
  bound-open) : ;;
  fallback)
    stop_unbound_advise "$PLAN" && _adv=1
    return "$_adv"
    ;;
  bound-closed)
    fold_advise "context-spend: bound plan closed — $PLAN; this session has no open run"; _adv=1
    return "$_adv"
    ;;
  bound-unreadable)
    # (wave-20 T1, REQ-2, AC-2.3.) Named, never "no open run": the plan is there and this
    # instrument cannot read the step it would record. patrol-duties holds the turn for it.
    fold_advise "context-spend: bound plan unreadable — $PLAN"; _adv=1
    return "$_adv"
    ;;
  none|*)
    return "$_adv"
    ;;
esac
[ -n "$PLAN" ] && [ -f "$PLAN" ] || return "$_adv"

# The step boundary is the run's step, the reader's answer the fill duty reads too (`stop_facts_load`),
# so a step the run's log alone holds is the step this instrument attributes spend to.
# [INSTRUMENT]
stop_facts_load
STEP="$(_fill_current_field "$PLAN")"
[ -n "$STEP" ] || return "$_adv"

# Last assistant entry with usage, from a bounded tail. fromjson? swallows
# malformed lines. Emits "model<TAB>occupied" for the last qualifying entry.
#
# THE TRAILING `| tail -1` IS AN EXPANSION NOW (REQ-10, T11). jq emits one line per
# qualifying entry and the last one is wanted; `${_row##*$'\n'}` is that line, and it
# is the whole string when jq emitted exactly one. The command substitution has already
# stripped the trailing newline, so there is no empty last line to guard against.
_row=$(tail -n 400 "$TRANSCRIPT" 2>/dev/null | jq -Rr '
  fromjson? | select(.type == "assistant") | .message | select(.usage != null) |
  [(.model // "unknown"),
   ((.usage.input_tokens // 0) + (.usage.cache_creation_input_tokens // 0) + (.usage.cache_read_input_tokens // 0))] | @tsv
' 2>/dev/null) || _row=""
_row="${_row##*$'\n'}"
[ -n "$_row" ] || return "$_adv"
MODEL=${_row%	*}
OCCUPIED=${_row##*	}
case "$OCCUPIED" in ''|*[!0-9]*) return "$_adv" ;; esac
[ "$OCCUPIED" -gt 0 ] || return "$_adv"

STATE_DIR="$BIONIC_ROOT/.bionic/tmp"
STATE="$STATE_DIR/context-spend.state"
mkdir -p "$STATE_DIR" 2>/dev/null || return "$_adv"

s_plan=""; s_sess=""; s_step=""; s_occ=""
if [ -f "$STATE" ]; then
  IFS='	' read -r s_plan s_sess s_step s_occ < "$STATE" 2>/dev/null || true
fi

# First-seen, plan switch, or session switch: seed silently. Two
# concurrent sessions on the same plan must never diff against each
# other's occupancy — a session change re-seeds, same as a plan change.
# [INSTRUMENT]
if [ "$s_plan" != "$PLAN" ] || [ "$s_sess" != "$BIONIC_SID" ] || [ -z "$s_step" ]; then
  printf '%s\t%s\t%s\t%s\n' "$PLAN" "$BIONIC_SID" "$STEP" "$OCCUPIED" > "$STATE" 2>/dev/null || true
  return "$_adv"
fi

# Same step: nothing to do (state deliberately untouched — it records the
# occupancy at the step's START boundary, so delta spans the whole step).
[ "$s_step" = "$STEP" ] && return "$_adv"

# Boundary: emit one line for the ENDED step.
case "$s_occ" in ''|*[!0-9]*) s_occ="$OCCUPIED" ;; esac
DELTA=$((OCCUPIED - s_occ))
if [ "$DELTA" -ge 0 ]; then DELTA="+$DELTA"; fi
LINE="- $(date -u +%Y-%m-%dT%H:%M:%SZ) context-spend step-$s_step: occupied=$OCCUPIED delta=$DELTA model=$MODEL ($PLAN)"
if AUDIT_FILE=$(audit_path "$BIONIC_ROOT"); then
  mkdir -p "$(dirname "$AUDIT_FILE")" 2>/dev/null && printf '%s\n' "$LINE" >> "$AUDIT_FILE" 2>/dev/null
fi
printf '%s\t%s\t%s\t%s\n' "$PLAN" "$BIONIC_SID" "$STEP" "$OCCUPIED" > "$STATE" 2>/dev/null || true
return "$_adv"
}


# ─── stop_landing_gate ───
#
# THE HOOK'S OWN HEADER, CARRIED OVER WHOLE. It is the design record for this
# verdict — every ruling, incident and measurement that shaped it — and it
# travels with the code rather than being left behind in a deleted file.
# Where it says "this hook" it now means this function, and where it names a
# registration it means hooks/stop.sh's.
#
# THE LANDING SWEEP — epic-16 wave-01 (the gate), wave-03 task T4c (the sweep).
#
# Stop. On every orchestrator turn end, during an active wave: read this session's roster,
# take a landing verdict for every contract that has LANDED since the last sweep, and refuse
# the stop once if any of them named artifacts that are not on disk. Outside an active wave,
# or on any ambiguity along the way, the stop passes through untouched.
#
# WHY A SWEEP, AND WHY ON THIS EVENT. Until wave-03 this ran on the subagent's own stop and
# judged the one agent that stopped. That event cannot reach it any more, and not by
# accident: skill-frontmatter hooks live in the harness's `appState.sessionHooks`, keyed by
# SESSION id, and the subagent-stop path looks them up under `agentId ?? session.id` — the
# subagent's id, which has no entry. Every event dispatched in a subagent context is
# therefore structurally invisible to a skill-registered hook, so a wall registered there is
# installed, syntactically fine, green in its own suite, and never runs
# (record/session-20260814-wave-detector-terminal-state/t4b-probe-report.md §3, read out of
# the shipped binary and confirmed by an eleven-session dual-channel A/B).
#
# `Stop` is delivered to that channel, fires once per orchestrator turn, keeps firing on
# turns the skill was not re-invoked on — and, the fact that makes the latency a non-issue,
# is GENERATED BY a background agent's landing: the completion wakes a fresh turn, which
# closes 2.5–3.7 s later and delivers a Stop nobody asked for (§2.3, §4, two independent
# replications). So a sweep here runs both when the orchestrator pauses and shortly after
# each landing, which is exactly the two moments a landing contract cares about.
#
# HOW A LANDING IS RECOGNISED. The payload carries `background_tasks[]`, one row per
# subagent that is STILL RUNNING, keyed by the same `id` the roster's `agent_id=` holds —
# `tool_response.agentId` at dispatch, `agent_id` on SubagentStart, `background_tasks[].id`
# here, one string across all three (§2.2, §4, measured on one dispatch). A roster row whose
# id is ABSENT from that list has landed; a row still on it is skipped in silence. Nothing
# on this path reads `agent_type`, which carries the subagent TYPE and never the dispatch
# name — the join defect t4-probes-report.md §5.1 found open and this task closes.
#
# ONCE PER ROW, EVER. Stop fires every turn and a landed row stays landed, so a sweep that
# re-verdicted would refuse every turn end for the rest of the session over one agent's
# failure — the false-alarm shape this machinery exists to end. Each verdicted row is
# journalled as a `landing-swept/v1|` line in the roster file it belongs to. That is the one
# thing this script writes, and it rides IN the roster because the promise it keeps must not
# outlive the rows it is about. Inertness to the rest of the fleet is NOT a blanket property
# of every roster reader — it holds per reader, for one of two separate reasons, and both
# must be true or the marker leaks into a reader's answer (t6-review.md F-1, reproduced live:
# `hooks/session-poker.sh` read the roster with no schema filter and the marker silenced its
# overdue NOTIFY for the swept row). `hooks/execution-recorder.sh`, `hooks/session-sweeper.sh`,
# the stop guard (`_sg_roster_walk`, below), the look (`observe_roster_walk`, lib/observe.sh)
# and `hooks/stop-orders.sh` filter on the
# `roster-state/v1|` prefix before reading a row, so the marker's `landing-swept/v1|` prefix
# never matches. `hooks/dispatch-preflight.sh` does NOT filter on that prefix and is immune
# only by accident: its `owning_row_for` skips any row with no `deliverable=`, a field the
# marker never carries. That second immunity is undeclared to its own reader and untested —
# one added field to the marker's schema would turn it into a second instance of this bug.
#
# IT OWNS NO PREDICATE. The question "did this contract land" is answered by
# `hooks/session-sweeper.sh verdict <name>`, and this script parses that verb's machine line
# for `state=`, `acked=` and `detail=`. It never stats a deliverable and never forms an
# opinion about staleness, waivers or liveness-by-progress. It reads exactly two fields of
# the roster for itself — `agent_id`, which is the join key above, and `name`, which is what
# the verb must be asked about — plus `deliverable` as a pure PREFILTER: a row declaring
# nothing is MET vacuously by the verb's own rule, so skipping it cannot change an answer,
# only the cost of getting one.
#
# THE SECOND ARM: TEAMMATES LAND AT SubagentStop (session-20260815, T2; design D2).
# Everything above is true of an async subagent and false of a named teammate. A teammate
# carries THREE id namespaces that do not join — the addressing form at dispatch
# (`mate@session-7b7a693c`), the transcript form on SubagentStart/Stop
# (`amate-fdaa80c4b3cb703f`), and an opaque nine-character token in `background_tasks[]` that
# appears in no dispatch-time payload at all — and its row NEVER LEAVES that array: measured
# `status:"running"` on the last Stop of the session, 2 m 41 s after the teammate had
# delivered its own SubagentStop (t1-probe-report.md §2.1–§2.3, CLI 2.1.233). So the sweep
# predicate is not merely unjoinable for teammates, it is wrong in both directions: today
# every teammate row is skipped for want of an id, and the moment a writer fills one, every
# teammate reads as LANDED 2.8 s after dispatch, while it is still working.
#
# `SubagentStop` is the transition itself rather than a reconstruction of it, and it carries
# the id, the name and the moment in one payload. This arm therefore takes the SAME verdict
# from the SAME verb, writes the SAME marker through the SAME append, and speaks the SAME
# refusal — what differs is only which row is judged and when. It reads no live set (the
# stopping teammate is still in it), joins by `agent_id` first and by `agent_type` — which
# carries the dispatch NAME for a teammate — second, and both joins are scoped to rows
# carrying a non-empty `teammate_id=`.
#
# THAT SCOPE CUTS BOTH WAYS, and the sweep half of it is in the fold below: teammate rows are
# skipped there, with the one exception the next paragraph names. An async subagent
# stopping on this event is passed over in silence, because
# the sweep is the arm that owns it and the marker written here is exactly what would tell
# the sweep the row is already answered for — verdicting an async row here would not
# duplicate the sweep, it would silently replace the refusal the orchestrator sees with one
# delivered somewhere else.
#
# THE SUPERSESSION RECHECK (session-20260815-landing-cleanup, T3; ruling: supersede). The one
# thing the sweep does with a teammate row, and it is not a verdict. A refused teammate is
# told inside its own sidechain at the one moment it can still act, and it acts: measured
# live, the teammate read the feedback, wrote the promised artifact, and the roster still read
# `state=UNMET` when the session ended (record/session-20260815-landing-supervision/
# live-verify.md §B2). The refusal was correct and its record was a false statement about the
# world. So on any later Stop, a teammate row whose LATEST marker says UNMET and whose
# deliverable the verb now finds gets a SECOND marker appended, saying MET. Both persist, in
# order: the stream is history plus current state, and nothing is ever rewritten. It never
# refuses, it never writes a FIRST verdict for a teammate (an unmarked row stays the
# SubagentStop arm's, delivered or not), it costs nothing once the answer is MET, and it needs
# no clock of its own — Stop already fires on every turn end and shortly after every landing.
#
# WHERE THE REFUSAL GOES, stated because it differs from the sweep and the difference is not
# ours to change: a blocking Stop-hook exit on the main thread reaches the orchestrator,
# while on SubagentStop the harness delivers the feedback TO THE SUBAGENT and lets it
# continue so it can act on it (read out of the shipped CLI 2.1.233 binary:
# "additionalContext is non-error feedback delivered to the subagent; the subagent continues
# so it can act on it", beside the block-cap guidance "For Stop/SubagentStop hooks, check
# stop_hook_active in the input and return success while it is true"). So the agent that
# broke its contract is the one told about it, at the one moment it can still fix it, and the
# orchestrator-facing record is the roster marker plus the poker overdue NOTIFY that reads
# the same rows. `stop_hook_active` is honoured here for the reason the binary gives.
#
# FAIL DIRECTIONS (pinned by tests/landing-gate.test.sh):
#   - not a Stop or SubagentStop payload                 -> pass, silent (relevance hoist)
#   - SubagentStop with no agent_id, or one carrying
#     field separators                                   -> pass, silent
#   - SubagentStop matching no teammate row (a phantom
#     harness agent, or an async subagent the sweep
#     owns)                                              -> pass, silent
#   - no `background_tasks` key: nothing to tell landed
#     from live                                          -> pass, silent (ambiguity)
#   - stop_hook_active true                              -> pass, silent (blocks ONCE)
#   - cwd/repo unresolvable, or no session_id, or a
#     session_id that is not shaped like one             -> pass, silent (ambiguity)
#   - no roster for this session, or a symlinked one     -> pass, silent
#   - no active wave                                     -> pass, silent
#   - the sweeper is absent                              -> pass, silent
#   - a row with an EMPTY agent_id: it cannot be placed
#     on either side of the landed/live line             -> skip, unmarked (ambiguity)
#   - the verdict exits anything but 0 or 1, or prints
#     no line at all                                     -> skip, UNMARKED (no answer, so
#                                                          the row is still owed one)
#   - the verdict says anything but UNMET, or says UNMET
#     over an acked row                                  -> mark swept, pass
#   - the verdict says UNMET on a landed row             -> REFUSE, quoting its detail
#   - a swept teammate row, latest marker UNMET, and the
#     verdict now says MET                               -> append a superseding marker, pass
#   - the same row, verdict still anything but MET       -> nothing appended, pass, silent
#   - a teammate row with NO marker at all               -> skip, unmarked (never a first
#                                                          verdict from this event)
#
# THE Files: RECONCILIATION (S18, AC-22) rides the same per-candidate loop, once per row, on
# a "verdict" candidate only — a recheck never speaks (belt-on-belt with "supersession never
# speaks" above) and a row with no `deliverable=` never becomes a candidate at all, so it is
# out of reach of this check too, on the same "declares nothing" reasoning the deliverable
# checks already use:
#   - the row's `files=` is empty (a Suites:-only brief,
#     or a row that predates the wall)                    -> not reconciled, silent, pass
#   - the row's worktree cannot be located or is gone,
#     or its branch has no merge-base with the main
#     checkout's current branch                            -> not reconciled, silent (ambiguity)
#   - the diff has no path outside the declared `files=`   -> pass, silent
#   - the diff touches a path outside the declared
#     `files=`                                              -> REFUSE, naming the file(s)
#
# Exit code 2 = block the stop in Claude Code hooks; stderr goes back to the orchestrator,
# which is why the refusal must name the row and its artifacts rather than the rule.
# [WALL: tests/landing-gate.test.sh]
#
# Registered on both channels by hooks/hooks.json, and by nothing else: hooks/stop.sh's
# Stop entry for the main thread, and its SubagentStop entry for agent contexts. No
# SKILL.md carries a `hooks:` key — that channel was never how this hook was delivered.
#
# hooks/landing-gate.sh's body — the ONE function of the four with a SubagentStop
# arm. Its `case "$EVENT"` is carried over unchanged; what changed is where the
# event comes from (an argument, not a payload read).

stop_landing_gate() {  # <event> -> 0 nothing · 1 advisory · 2 block
  local _ev="${1:-}" _adv=0
  local EVENT MODE STOP_AGENT_ID STOP_AGENT_NAME LIVE_IDS ROSTER_FILE SWEEPER
  local CANDIDATES LINE REFUSALS REFUSE_KIND NOW AID NAME KIND CFILES
  local VERDICT VERDICT_RC STATE
  local LG_WT LG_MAIN_BRANCH LG_BASE LG_WHY LG_WORKING_BRANCH
  local LG_ROW_RC LG_ROW_ID LG_ROW_BASE LG_FALLBACK_WHY LG_BASE_SRC LG_RUN_PLAN
  local _LG_ROW_ID _LG_ROW_BASE
  local LG_OUTSIDE LG_DF LG_FIX LG_FIX_FILES

# ---------- relevance first: the cheapest checks, before any git resolution ----------

# TWO EVENTS, TWO ARMS, ONE ROSTER SPLIT BETWEEN THEM. `Stop` is the sweep (below);
# `SubagentStop` is the teammate landing verdict, and it arrives on the settings channel
# through hooks/stop.sh's SubagentStop entry because no subagent-context event reaches the skill
# frontmatter at all. An absent field is not treated as a mismatch, so a hand-run payload
# still sweeps.
EVENT="$_ev"
case "$EVENT" in
  ""|Stop)      MODE=sweep ;;
  SubagentStop) MODE=landing ;;
  *)            return "$_adv" ;;
esac

# Read on BOTH paths, so neither is a variable bound on only some of them (`set -u`), and
# read here rather than at the join so the shape checks sit beside every other one.
STOP_AGENT_ID=""
STOP_AGENT_NAME=""
LIVE_IDS=""

if [ "$MODE" = "sweep" ]; then
  # THE LIVE SET, and the whole of the landed/live discrimination. Its ABSENCE is not an empty
  # set: an empty array means every dispatch has finished (the payload says so on every turn
  # where nothing is running), while a missing key means this is not a payload that can tell
  # us, and judging on it would hold running agents to contracts they are still working on.
  #
  # THROUGH `bionic_jq`, NOT A PRIVATE `jq` (REQ-10, T11). Both expressions are
  # unchanged, character for character — they are now on lib/context.sh's roster,
  # so the one payload read that hook already made answers them and these two
  # lines fork nothing. Off the roster (a hook that never called
  # `bionic_context`) `bionic_jq` runs the same `jq -r '<expr> // empty'` these
  # lines ran, which is the same answer: appending `// empty` to either
  # expression cannot change a value it already produced.
  [ "$(bionic_jq 'if has("background_tasks") then "yes" else empty end')" = "yes" ] || return "$_adv"
  # `tr -d '\n'` IS GONE, replaced by the expansion below. It existed to flatten an
  # id that carried a newline; the `//$'\n'/` expansion does that in the shell, and
  # the command substitution around the read strips the trailing newline as before.
  LIVE_IDS=$(bionic_jq '[.background_tasks[]?.id // empty] | join("|")')
  LIVE_IDS="|${LIVE_IDS//$'\n'/}|"
else
  # THE LANDING ARM READS NO LIVE SET, and that is the point of it rather than an omission.
  # This payload carries `background_tasks[]` too, and the stopping teammate is STILL IN IT —
  # measured `status:"running"` on the last Stop of the session, 2 m 41 s after its own
  # SubagentStop, because an in-process teammate stays addressable until the session ends
  # (t1-probe-report.md §2.3). Landing-by-disappearance is a subagent-only signal; here the
  # EVENT is the landing, delivered with the id, the name and the moment in one payload.
  STOP_AGENT_ID=$(bionic_jq .agent_id)
  [ -n "$STOP_AGENT_ID" ] || return "$_adv"
  # SHAPE-CHECKED BEFORE IT BECOMES A FIELD, on the same reasoning the session key gets: this
  # value is written into a `landing-swept/v1|…|agent_id=` marker line, and a `|` or a newline
  # in it would forge a field or a whole row on the roster. The transcript form is
  # `a<name>-<16 hex>` and names are alphanumeric, so this silences nothing real.
  case "$STOP_AGENT_ID" in *[!A-Za-z0-9_.@-]*) return "$_adv" ;; esac
  # The NAME, for the fallback join, and only if it is shaped like one. `agent_type` carries
  # the dispatch name for a teammate and the subagent type for an async dispatch (t1 §2.1);
  # the harness's own phantom agents send it empty. An unusable value drops the fallback
  # rather than the whole arm — the id join above may still place the row.
  STOP_AGENT_NAME=$(bionic_jq .agent_type)
  case "$STOP_AGENT_NAME" in *[!A-Za-z0-9_-]*) STOP_AGENT_NAME="" ;; esac
fi
[ -d "$BIONIC_ROOT" ] || return "$_adv"

# ---------- THE ENGAGEMENT SWITCH — asked before anything else ----------
#
# task-engaged-session: bionic's walls are the RUN's, not the repo's, and a run is entered
# by invoking canonical-sdlc. A session that never did is a bystander here and must not see
# a refusal, an advisory, or a state write from this hook. `engaged_session` (lib/run.sh) is
# true only for a REGULAR file at `.bionic/tmp/engaged-<sid>.state`; every unreadable state —
# absent, symlink, foreign sid, `unknown` — reads as NOT engaged. Silent, return "$_adv": the
# direction §7 gives every start-side ambiguity, and here it is the consent boundary itself
# (1.3.2 close-out ruling — the arming partition IS the consent boundary).
[ "$BIONIC_ENGAGED" = 1 ] || return "$_adv"

ROSTER_FILE="$BIONIC_ROOT/.bionic/tmp/roster-${BIONIC_SID}.state"
# Existence first, so a session that has dispatched nothing costs one stat. The symlink
# guard is the write half of TDD §8: a repo controls its own .bionic/, and a link at any
# level redirects this script's marker append outside the repo.
[ -e "$ROSTER_FILE" ] || return "$_adv"
[ -L "$BIONIC_ROOT/.bionic" ] && return "$_adv"
[ -L "$BIONIC_ROOT/.bionic/tmp" ] && return "$_adv"
[ -L "$ROSTER_FILE" ] && return "$_adv"

# ---------- THE RUN PREDICATE IS GONE — ENGAGEMENT SCOPES THIS HOOK (task-engaged-session) --
#
# It used to take the run predicate here — `PLAN=$(active_run <repo>)`, return "$_adv" on false —
# and nothing below ever consulted
# the value: the contract this gate enforces is a roster row this
# session's own dispatch wall wrote, and the verdict is hooks/session-sweeper.sh's.
# The plan answered WHETHER, which is now engagement's question and is answered above.
#
# WHY THIS HOOK MOVES WITH THE DISPATCH WALL RATHER THAN KEEPING A RUN GATE. The four
# members of the roster lifecycle — hooks/dispatch-preflight.sh writes an `intended` row,
# this family confirms it, the landing gate takes its verdict, the stop gate polices the
# stop — have to share one scope or the lifecycle splits: the dispatch wall runs for an
# engaged session with no plan yet (AC-23, a fresh run's Step 0 precedes its plan), and a
# recorder or a gate that stayed silent for want of a plan would leave rows nothing ever
# answers for. A landing contract also OUTLIVES the run that created it — engagement does
# not end when `current:` reaches 9 (plan §Lifecycle) — and a verdict owed on an agent this
# session launched is owed after the run closes too.

# ---------- this session is engaged: sweep ----------

# The sweeper is this script's SIBLING — the payload ships every hooks/*.sh in one
# directory, so the same resolution holds in the repo and under the mounted plugin's
# hooks/ that hooks/hooks.json roots at ${CLAUDE_PLUGIN_ROOT}. No PATH
# lookup (a hook's PATH is not ours to trust) and no environment override (a seam on the
# path under test would leave the production path unverified).
SWEEPER="${_STOP_HOOK_DIR_ABS}/session-sweeper.sh"
[ -f "$SWEEPER" ] || return "$_adv"

# ONE PASS OVER THE ROSTER, and it is the only cost this script pays on a turn where nothing
# landed. The fold rule is hooks/session-sweeper.sh's own (`latest_rows`), because the verb
# is what will be asked and a reader that folded differently would ask about a row the verb
# never answers for: rows of THIS session only, keyed by name, FIRST field of a key wins
# within a row, latest row wins across them, an empty name folds to `(unnamed)`.
#
# `agent_id` is taken from the latest row that CARRIES one rather than from the latest row
# outright. The field starts empty on the `intended` row the dispatch wall writes and is
# filled by hooks/execution-recorder.sh at confirmation or identification. A teammate's
# `confirmed` row carries none (its id is learned at SubagentStart), so the latest row can
# have an empty id after an earlier one had it. This reader takes the id from the latest
# row that carries one, which is the roster's one rule for "the id's row" (the docblock of
# `roster_row_for_id`, payload/scripts/lib/roster.sh; ADR-039), and it keeps a row joinable
# if a writer ever appends without copying the id forward.
#
# The output is TAB-delimited `<agent_id> <name> <kind>`, one line per unswept, joinable,
# contract-bearing row. A tab cannot appear inside a field — every writer on this roster runs
# its values through a sanitizer that turns one into a space — and the name is folded the
# same way the verb folds it. `kind` is `verdict` for a row being answered for the first (and
# only) time, and `recheck` for the supersession arm below, which is the one caller that may
# write a SECOND marker for a row and the one that never refuses.
CANDIDATES=$(awk -v pfx="roster-state/${ROSTER_VERSION}|" -v spfx="${SWEPT_SCHEMA}|" -v sid="$BIONIC_SID" \
                 -v mode="$MODE" -v pid="$STOP_AGENT_ID" -v atype="$STOP_AGENT_NAME" '
  index($0, spfx) == 1 {
    nf = split($0, f, "|"); a = ""; mn = ""; ms = ""
    for (i = 1; i <= nf; i++) {
      if (a  == "" && substr(f[i], 1,  9) == "agent_id=") a  = substr(f[i], 10)
      if (mn == "" && substr(f[i], 1,  5) == "name=")     mn = substr(f[i], 6)
      if (ms == "" && substr(f[i], 1,  6) == "state=")    ms = substr(f[i], 7)
    }
    if (a != "") swept[a] = 1
    # THE LATEST ANSWER, PER ROW, and latest means LAST IN THE FILE: this is an append-only
    # journal, so file order is chronological and an unconditional assignment leaves the most
    # recent marker standing. The recheck arm below reads exactly these two facts — what the
    # last answer said, and which id it was keyed by — and asks for nothing the marker does
    # not already carry.
    if (mn != "") { mstate[mn] = ms; if (a != "") magent[mn] = a }
    next
  }
  index($0, pfx) != 1 { next }
  {
    name = ""; rsession = ""; aid = ""; deliv = ""; tid = ""; fls = ""
    nf = split($0, f, "|")
    for (i = 1; i <= nf; i++) {
      if (name == ""     && substr(f[i], 1, 5)  == "name=")        name     = substr(f[i], 6)
      if (rsession == "" && substr(f[i], 1, 8)  == "session=")     rsession = substr(f[i], 9)
      if (aid == ""      && substr(f[i], 1, 9)  == "agent_id=")    aid      = substr(f[i], 10)
      if (deliv == ""    && substr(f[i], 1, 12) == "deliverable=") deliv    = substr(f[i], 13)
      if (tid == ""      && substr(f[i], 1, 12) == "teammate_id=") tid      = substr(f[i], 13)
      if (fls == ""      && substr(f[i], 1, 6)  == "files=")       fls      = substr(f[i], 7)
    }
    # The roster file is already per-session; this only fires on a hand-edited or copied
    # file, and it costs one comparison to keep the sweep honest about whose promises it is
    # answering for.
    if (rsession != "" && rsession != sid) next
    if (name == "") name = "(unnamed)"
    gsub(/\t/, " ", name)
    if (!(name in seen)) { seen[name] = 1; order[++n] = name }
    if (aid != "") agent[name] = aid
    # `teammate_id` is monotone the way `agent_id` is — the launch wall never writes it and
    # the completion arm fills it once — so the latest row that CARRIES one wins, and a row
    # appended without copying it forward cannot un-teammate a contract.
    if (tid != "") tm[name] = tid
    dl[name] = deliv
    # `files=` (S18, AC-22) is read the same way `deliverable=` is: the LATEST row value,
    # whatever it is. Post-S13 every row dispatch-preflight writes carries the key (empty
    # string for a Suites:-only brief); a pre-S13 row carries no key at all and parses to the
    # same empty value either way, so one predicate downstream (non-empty or not) covers both.
    # (No apostrophes in this paragraph: it lives inside a single-quoted awk program.)
    gsub(/\t/, " ", fls)
    fl[name] = fls
  }
  END {
    # ---------- the landing arm: ONE row, the one that just stopped ----------
    if (mode == "landing") {
      nm = ""
      # BY ID FIRST. The transcript form is filled onto the row by the recorder at
      # SubagentStart, and it is the same string this payload carries — the strongest key
      # available, and the one that survives two dispatches sharing a name.
      for (i = 1; i <= n; i++) {
        k = order[i]
        if (tm[k] == "") continue
        if ((k in agent) && agent[k] != "" && agent[k] == pid) nm = k
      }
      # BY NAME SECOND, and only over teammate rows. For a teammate `agent_type` carries the
      # dispatch name; for an async dispatch it carries the subagent type, which names no row
      # and is the join wave-03 removed for cause. The scope reads the statement the row
      # writer made about dispatch mode, never a guess at the shape of an id.
      if (nm == "" && atype != "" && (atype in seen) && tm[atype] != "") nm = atype
      # A stop we cannot place is not ours to answer for: the harness sends its own internal
      # agents through this event, and their ids are on no row of ours.
      if (nm == "") exit
      if (dl[nm] == "") exit                # declares nothing; MET vacuously either way
      a = ((nm in agent) && agent[nm] != "") ? agent[nm] : pid
      if (a == "") exit
      # Both keys, because the marker may have been written under either: the row id when the
      # identification arm ran, the payload id when it did not.
      if ((a in swept) || (pid in swept)) exit
      printf "%s\t%s\t%s\t%s\n", a, nm, "verdict", fl[nm]
      exit
    }

    # ---------- the sweep: every row the payload says has landed ----------
    for (i = 1; i <= n; i++) {
      nm = order[i]
      # TEAMMATES BELONG TO THE OTHER ARM, and this skip is load-bearing rather than tidy.
      # A teammate is keyed in `background_tasks[]` under a namespace its `agent_id` is not
      # in, and it NEVER LEAVES that array anyway (t1 §2.3) — so the moment the recorder
      # fills the row id, the landed/live predicate here reads every teammate as landed on
      # the first Stop after dispatch, 2.8 s in, and refuses a contract the agent is still
      # working on. The sweep judges what it can place; the SubagentStop arm judges the rest.
      #
      # ONE EXCEPTION, AND IT IS NOT A VERDICT (session-20260815-landing-cleanup T3, AC-5).
      # A teammate refused at SubagentStop is told so INSIDE its own sidechain, at the one
      # moment it can still act — and it does: measured live, the refused teammate read the
      # feedback and wrote the promised artifact, while the roster still said UNMET when the
      # session ended (live-verify.md B2). The refusal was right and its record was a lie
      # about the world. So a teammate row whose LATEST marker says UNMET, and whose
      # contracted deliverable the verb now finds, gets a SUPERSEDING marker appended: the
      # stream carries history plus current state, nothing is rewritten, and the block-once
      # promise is untouched because a supersession never speaks. The Stop cadence is the
      # clock; no timer is added for it.
      #
      # NEVER A FIRST VERDICT. A teammate row with no marker at all is left exactly where the
      # skip above leaves it, delivered or not — the sweep cannot tell a working teammate
      # from a finished one, and answering here is the 2.8-second false refusal this whole
      # partition exists to prevent. The recheck can only ever change an answer that the
      # SubagentStop arm already gave.
      if (tm[nm] != "") {
        if (!(nm in mstate)) continue       # unanswered: not this arm to answer
        if (mstate[nm] != "UNMET") continue # the current answer is no failure; nothing to supersede
        if (dl[nm] == "") continue          # declares nothing; MET vacuously either way
        ra = ""
        # The id off the MARKER first, and the row only as a fallback: in teammate mode a row
        # carries no `agent_id=` at all (the addressing form lives in `teammate_id=`), and the
        # marker was keyed by the transcript form off the stopping payload. Superseding under
        # a different key would leave two markers no reader could tell were about one answer.
        if ((nm in magent) && magent[nm] != "") ra = magent[nm]
        # UNREACHABLE, AND THE REASON IS NO LONGER "ONE WRITER". Two files append
        # `landing-swept/v1` lines: this one ORIGINATES them (below, off `$SWEPT_SCHEMA`),
        # and the `adopt_copy_marker` in hooks/session-poker.sh COPIES one verbatim onto the
        # successor roster when a session adopts a predecessor row — it never computes a
        # verdict, so every marker in the fleet still carries the `agent_id=` that the
        # write path below refuses to append without. That, not the writer count, is
        # what keeps `magent[nm]` populated whenever `mstate[nm]` exists.
        #
        # THE GREP THIS USED TO CITE WAS A GUARANTEED FALSE NEGATIVE: `grep -rn SWEPT_SCHEMA
        # hooks/*.sh` still returns only this file, because the poker spells the schema as a
        # literal rather than through the constant. The grep that finds both writers is
        # `grep -rn landing-swept/v1 hooks/*.sh`.
        # Kept as belt-on-belt against a future writer that COMPUTES rather than copies.
        # (No apostrophes in this paragraph: it lives inside a single-quoted awk program.)
        else if ((nm in agent) && agent[nm] != "") ra = agent[nm]
        if (ra == "") continue
        printf "%s\t%s\t%s\n", ra, nm, "recheck"
        continue
      }
      if (!(nm in agent)) continue          # never confirmed: cannot be placed
      if (dl[nm] == "") continue            # declares nothing; MET vacuously either way
      if (agent[nm] in swept) continue      # already answered for, once and for all
      printf "%s\t%s\t%s\t%s\n", agent[nm], nm, "verdict", fl[nm]
    }
  }
' "$ROSTER_FILE" 2>/dev/null)

[ -n "$CANDIDATES" ] || return "$_adv"

LINE=""
_field() {  # <key> — by key, never by position, as every reader of these lines does
  printf '%s' "$LINE" | tr '|' '\n' | grep "^$1=" | head -1 | cut -d= -f2-
}

REFUSALS=""
# WHICH FACT THE ONE LINE CARRIES when a sweep finds both kinds (task 13, table rows
# 107 and 108). The gate accumulates a paragraph per failing row and prints them all;
# ruling D-1 gives the reader ONE line, so the FIRST kind found names it and every
# accumulated paragraph rides `detail`. The alternative — a third, summarising fact —
# would be user-facing text the ruled table does not carry.
REFUSE_KIND=""

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

while IFS=$'\t' read -r AID NAME KIND CFILES; do
  [ -n "$AID" ] && [ -n "$NAME" ] || continue
  # STILL IN FLIGHT — the payload says so, and an agent that is visibly still working has
  # not failed to land. No verdict, and no marker: its one answer is still owed.
  case "$LIVE_IDS" in *"|$AID|"*) continue ;; esac

  # Run from the repo, because the sweeper resolves its own state directory from the working
  # directory, and with the payload's session key. `|| exit 9` keeps a failed `cd` out of the
  # exit-1 band: exit 1 is the verb's "at least one UNMET row", and nothing else may be
  # allowed to spell it.
  VERDICT=$( cd "$BIONIC_ROOT" 2>/dev/null || exit 9
             CLAUDE_CODE_SESSION_ID="$BIONIC_SID" bash "$SWEEPER" verdict "$NAME" 2>/dev/null )
  VERDICT_RC=$?

  # AN ANSWER WE DID NOT GET IS NOT AN ANSWER. Exit 2 is a refusal (the verb was redirected
  # away from the roster and says so), 3 is no session key, anything else is an error — and
  # none of them may mark a row closed, because the row has not been judged.
  case "$VERDICT_RC" in 0|1) : ;; *) continue ;; esac

  # THE LINE THE SCOPED VERB RETURNED, and no second lookup by name. `verdict <name>`
  # answers for that name alone and folds the roster to one row per name, so its output
  # carries at most one machine line and taking the first IS taking this contract's.
  LINE=$(printf '%s\n' "$VERDICT" | grep -F 'landing-verdict/v1|' | head -1)
  [ -n "$LINE" ] || continue

  STATE=$(_field state)

  # A RECHECK SPENDS A MARKER ONLY ON A CHANGED ANSWER. The row already has one saying UNMET;
  # a second saying the same thing records nothing and would be appended on every turn end
  # for the rest of the session — the marker-spam shape. Only MET supersedes: STILL-LIVE,
  # WAIVED and AMBIGUOUS are not the recovery this arm exists to record, and UNMET is the
  # answer already standing.
  if [ "$KIND" = "recheck" ] && [ "$STATE" != "MET" ]; then
    continue
  fi

  # APPENDED HERE, PER ROW, THE MOMENT ITS VERDICT IS DECIDED — not accumulated across the
  # whole loop and written once at the end (t6-review.md F-2, measured: a sweep killed 5s
  # into a 200-candidate run, ~60 already verdicted, banked ZERO marks under the old single
  # trailing append). This is the same lock-free discipline the trailing append relied on —
  # one line, well under a pipe buffer, O_APPEND — just paid once per row instead of once
  # per sweep, so a sweep killed mid-loop still banks every verdict already decided.
  #
  # THE ONE WRITER (S15, AC-26): `swept_marker_write`, defined above, owns this printf;
  # hooks/session-poker.sh's `adopt_copy_marker` never re-spells it.
  swept_marker_write "$ROSTER_FILE" "$NOW" "$BIONIC_SID" "$NAME" "$AID" "$STATE"

  # AND A SUPERSESSION NEVER SPEAKS. Its marker is MET by construction, so nothing below
  # would fire anyway — but the reason it must not is stronger than the arithmetic: the row
  # has already been refused once, the agent has already acted on that refusal, and the whole
  # promise of this gate is that it blocks once. Recording the recovery is the entire job.
  [ "$KIND" = "recheck" ] && continue

  # ---------------------------------------------------------- Files: RECONCILIATION (S18, AC-22)
  #
  # INDEPENDENT OF THE DELIVERABLE VERDICT ABOVE, and run exactly once — this row reaches
  # this line only as a first-time "verdict" candidate (recheck already continued above,
  # and a row with no `deliverable=` never became a candidate at all — see the awk END
  # block's own "declares nothing" skips, which this check inherits rather than re-states).
  if [ -n "$CFILES" ]; then
    LG_WT=$(_lg_worktree_for_name "$BIONIC_ROOT" "$NAME")
    if [ -n "$LG_WT" ] && [ -d "$LG_WT" ]; then
      # THE BASE IS THE MERGE-BASE WITH THE PLAN'S DECLARED `working-branch:` — a BRANCH
      # NAME, not a stored sha and, since epic-23 wave-16 REQ-7 (D4), not the main
      # checkout's own current branch either. A branch is the right thing to merge-base
      # against for the same reason a stored sha is the wrong one (rejected alternative,
      # spec §4): "everything this branch has added since it diverged" has to keep meaning
      # that after a writer merges the wave tip INTO the working branch, and a moving ref
      # tracks that while a frozen sha would not. The MAIN CHECKOUT'S CURRENT BRANCH was
      # the wrong stand-in for "the wave branch" all along — it happens to be right only
      # when the orchestrator's own checkout sits on the wave tip, which is the ordinary
      # case this repo's convention produces but never the only one a session can reach
      # (bisecting, reviewing a peer wave, or simply parked on a different branch while a
      # task tree tracks its own wave). A tree cut from `wave/x` reads `wave/x`'s WHOLE
      # history as undeclared the moment the main checkout is on anything else (REQ-7,
      # AC-7.1) — the plan is the one place that names the branch a task tree was cut
      # FROM, so this reads it there instead of guessing from the checkout beside it.
      # AND SINCE WAVE-17 REQ-2 (D3, ADR-032) THE BRANCH IS THE SECOND QUESTION, NOT THE
      # FIRST. A merge-base against a branch answers "everything this branch has added since
      # it diverged", which is the tree's own cut point only while the tree was cut from that
      # branch's history. `spawn-worktree.sh` has always PRINTED the commit it cut from
      # (`base=<sha>` on its contract line) and through wave-16 nothing recorded it, so the
      # gate had nothing to prefer. The `## Tasks` row records it now. A declared origin is
      # taken as the diff base; every other path is a RECONSTRUCTION, and each one says so.
      #
      # `merge-base <declared> HEAD` RATHER THAN THE CELL ITSELF, which is not a formality:
      # it answers the cell's own sha whenever HEAD descends from it (the ordinary case, and
      # the case after a writer merges the wave tip in), and it answers NOTHING when the cell
      # names a commit this tree does not hold — which is how a wrong record is caught here
      # instead of charging a writer against a base that means nothing to its history.
      #
      # THE PLAN IS READ ONLY WHEN THIS SESSION IS BOUND TO IT AND IT IS OPEN
      # (wave-23-fixit-1810, REQ-1, D1). An unbound session's `fallback` plan is somebody
      # else's run: it is announced and never acted on, so no row of it is looked up and its
      # `working-branch:` is not read — the reconciliation takes the checkout fallback below,
      # and says why ("session unbound"). A closed or unreadable binding reads nothing either.
      LG_ROW_ID=""; LG_ROW_BASE=""; LG_FALLBACK_WHY=""; LG_ROW_RC=0; LG_RUN_PLAN=""
      case "$BIONIC_RUN_WORD" in
        bound-open) LG_RUN_PLAN="$BIONIC_RUN_PLAN" ;;
        fallback)
          stop_unbound_advise "$BIONIC_RUN_PLAN" && _adv=1
          LG_FALLBACK_WHY="session unbound"
          ;;
      esac
      if [ -n "$LG_RUN_PLAN" ]; then
        _lg_row_for_tree "$LG_RUN_PLAN" "${LG_WT##*/}" || LG_ROW_RC=$?
        LG_ROW_ID="$_LG_ROW_ID"; LG_ROW_BASE="$_LG_ROW_BASE"
      fi
      LG_BASE=""
      if [ "$LG_ROW_RC" = 3 ]; then
        LG_FALLBACK_WHY="two rows of the plan name this tree"
      elif [ -n "$LG_ROW_BASE" ]; then
        LG_BASE=$(git -C "$LG_WT" merge-base "$LG_ROW_BASE" HEAD 2>/dev/null)
        # NO APOSTROPHE IN THIS STRING, and that is not a style note: `row T1s` reads badly
        # enough to invite one, and a bare quote here re-opens the line and swallows the rest
        # of this function into a string that still parses (measured, this task: every arm
        # below it went silently unreachable and the suite reported the gate passing).
        [ -n "$LG_BASE" ] || LG_FALLBACK_WHY="row ${LG_ROW_ID} declares base ${LG_ROW_BASE}, which is not a commit this tree holds"
      elif [ -n "$LG_ROW_ID" ]; then
        LG_FALLBACK_WHY="row ${LG_ROW_ID} declares no base"
      fi

      LG_WORKING_BRANCH=""
      # lib/run.sh `plan_working_branch`, the one reader: SDLC State, then frontmatter (wave-35 T7; D14).
      [ -n "$LG_RUN_PLAN" ] && LG_WORKING_BRANCH=$(plan_working_branch "$LG_RUN_PLAN")
      LG_MAIN_BRANCH=""
      LG_BASE_SRC=""
      if [ -n "$LG_WORKING_BRANCH" ] \
        && git -C "$BIONIC_ROOT" show-ref --verify --quiet "refs/heads/${LG_WORKING_BRANCH}"; then
        LG_MAIN_BRANCH="$LG_WORKING_BRANCH"
        LG_BASE_SRC=working-branch
      else
        # TODAY'S PATH (spec A3): no plan bound, no `working-branch:` on the one that is,
        # or a name that does not resolve to a branch this repository holds — every one of
        # these takes the fallback this arm has always had, unchanged, rather than a
        # refusal or a silent skip for a plan that simply predates this field.
        LG_MAIN_BRANCH=$(git -C "$BIONIC_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
        # A DETACHED MAIN CHECKOUT IS NOT A BRANCH NAME (review-a A-5). `rev-parse
        # --abbrev-ref HEAD` prints the literal string `HEAD` there, and `HEAD` resolves
        # INSIDE the worktree to the worktree's own tip — so the merge-base comes back
        # non-empty, the diff comes back EMPTY, and every landing reconciles clean with no
        # refusal and no diagnostic. `git bisect`, `git checkout <tag>` and a checkout parked
        # on a sha are all ordinary states for this repository during an integration.
        case "$LG_MAIN_BRANCH" in HEAD) LG_MAIN_BRANCH="" ;; esac
        [ -n "$LG_MAIN_BRANCH" ] && LG_BASE_SRC=checkout
      fi

      # NO RECONSTRUCTION IS SILENT (D3, ADR-032). Two lines, because there are two of them
      # and they are not equally safe. The first is the plan's own `working-branch:`, taken
      # for a REGISTERED tree whose row declared no origin (or declared one this tree does
      # not hold, or collided): the row is named, so a reader knows which row to fix. The
      # second is the main checkout's current branch — the guess this gate has always fallen
      # back to, right only while that checkout sits on the wave tip — and it is announced
      # for EVERY tree, registered or not, because nothing about it was declared anywhere.
      #
      # A TREE NO ROW NAMES, on a plan whose `working-branch:` resolves, stays SILENT: that
      # is wave-16 REQ-7's behaviour on wave-16's own record, and a plan that predates the
      # `base` column must not start narrating every landing the day this ships. The fallback
      # it takes was declared — by the plan, in its frontmatter — which is the whole
      # distinction the two lines above draw.
      if [ -z "$LG_BASE" ] && [ -n "$LG_MAIN_BRANCH" ]; then
        if [ "$LG_BASE_SRC" = working-branch ]; then
          if [ -n "$LG_FALLBACK_WHY" ]; then
            fold_advise "landing gate: ${LG_FALLBACK_WHY}; diffing against working-branch ${LG_MAIN_BRANCH}"; _adv=1
          fi
        else
          fold_advise "landing gate: ${LG_FALLBACK_WHY:-no declared base} and no working-branch resolves; diffing against ${LG_MAIN_BRANCH}"; _adv=1
        fi
      fi

      if [ -z "$LG_BASE" ] && [ -n "$LG_MAIN_BRANCH" ]; then
        LG_BASE=$(git -C "$LG_WT" merge-base "$LG_MAIN_BRANCH" HEAD 2>/dev/null)
      fi
      if [ -z "$LG_BASE" ]; then
        # ANNOUNCED INERT, the standard tests/run.sh:310-315 sets for the adoption wall:
        # "a wall that is off and quiet is indistinguishable from a wall that is passing
        # everything". Unrelated histories, a worktree with no commits and any other
        # merge-base failure land here too, and each says so rather than passing silently.
        if [ -z "$LG_MAIN_BRANCH" ]; then
          LG_WHY="the main checkout is on no branch (detached HEAD), so there is no branch to take a merge-base from"
        else
          LG_WHY="no merge-base between ${LG_MAIN_BRANCH} and this tree"
        fi
        fold_advise "landing-gate: ${LG_WHY} — the Files: reconciliation is INERT for row ${NAME}; its diff was NOT checked against '${CFILES}'"; _adv=1
      fi
      if [ -n "$LG_BASE" ]; then
        LG_OUTSIDE=""
        # THE AMEND ARGUMENTS ARE BUILT PER PATH, NEVER SPLIT BACK OUT OF `LG_OUTSIDE`
        # (wave-24 T13, D10): that list is space-joined for reading, so a path holding a
        # space would come back as two. Each path is one quoted `--files+` word here.
        #
        # EACH PATH AS THE DIFF SPELLS IT: amend reads a `--files+` value with the one reader of a
        # brief's Files: line (lib/brief.sh `brief_contract`), which records a path at the root as
        # written, so the line printed here is one amend accepts.
        LG_FIX_FILES=""
        while IFS= read -r LG_DF; do
          [ -n "$LG_DF" ] || continue
          _lg_path_declared "$LG_DF" "$CFILES" && continue
          LG_OUTSIDE="${LG_OUTSIDE}${LG_OUTSIDE:+ }${LG_DF}"
          LG_FIX_FILES="${LG_FIX_FILES} --files+ $(refuse_quote "$LG_DF")"
        done <<LGDIFF
$(git -C "$LG_WT" diff --name-only "${LG_BASE}..HEAD" 2>/dev/null)
LGDIFF
        if [ -n "$LG_OUTSIDE" ]; then
          [ -n "$REFUSE_KIND" ] || REFUSE_KIND=undeclared
          # THE FIX IS A COMMAND, PRINTED WHOLE (wave-24 T13, D10, AC-6.5): the amend that
          # declares these paths on this row, with the real plugin root, the row name and
          # every path quoted as one shell word, ready to paste. Reverting them is the other
          # way out, and has no single command to print. The script path is one word too: a
          # plugin root with a space would otherwise paste as two (wave-24 T27; critic I2).
          LG_FIX="bash $(refuse_shell_word "$(refuse_plugin_root)/hooks/session-poker.sh") amend $(refuse_quote "$NAME")${LG_FIX_FILES} --reason $(refuse_quote "the landing diff touched files Files: did not declare")"
  REFUSALS="${REFUSALS}LANDING DIFF OUTSIDE Files: — ${NAME} touched: ${LG_OUTSIDE} — not declared. Declare them (main runs it), or revert them before landing:
    ${LG_FIX}
"
        fi
      fi
    fi
  fi
  # A Suites:-only brief (AC-20's other half), or a pre-S13 row, declared no Files: at all,
  # so there is no declared set to reconcile the diff against. SILENT, on the same footing
  # as every other "cannot judge this" path in this file: this is the ordinary case for most
  # of the fleet today (Files: is the newer of AC-20's two labels), and a stderr line on
  # every such landing would turn the common case into noise on every turn end — the exact
  # false-alarm shape the rest of this gate exists to end. The disposition is documented
  # once, above, in the FAIL DIRECTIONS table; it is not re-announced per row.

  [ "$VERDICT_RC" -eq 1 ] || continue
  [ "$STATE" = "UNMET" ] || continue

  # AN ACKED ROW IS CLOSED FOR EVERY READER (epic-16 wave-02 task S3, R2). The orchestrator
  # verified this agent's completion and made that durable; reporting it again over artifacts
  # a human has already accounted for is the false alarm this wave exists to end. Read off
  # the verdict line, which is where the one reader of that ledger publishes it (S9).
  [ "$(_field acked)" = "yes" ] && continue

  # The refusal is the verb's own detail, unedited, prefixed by the row it is about. It names
  # every failing conjunct — `missing=`, `empty=`, `stale=` with both stamps — because a
  # reader told only "unmet" has nothing to act on. The ROW NAME is what the sweep adds and
  # the per-agent gate did not need: a sweep answers about contracts rather than about
  # whoever is stopping, so without it the reader cannot tell which dispatch to chase.
  [ -n "$REFUSE_KIND" ] || REFUSE_KIND=unmet
  REFUSALS="${REFUSALS}LANDING CONTRACT UNMET — ${NAME}: $(_field detail). Land the contract (write the named artifacts), or stop again to pass — this gate blocks once.
"
done <<EOF
$CANDIDATES
EOF

[ -n "$REFUSALS" ] || return "$_adv"
# WHOSE FIX, BY EVENT. On SubagentStop the refusal goes to the writer whose contract it is, on the only channel that
# event has. On Stop it is the orchestrator's sweep, and the fix is the orchestrator's: a duty, one quiet line in the
# window and the whole list behind `session-poker.sh duty`.
local LG_CHANNEL=exit2
[ "$_ev" = Stop ] && LG_CHANNEL=duty
case "$REFUSE_KIND" in
  undeclared) fold_block "$LG_CHANNEL" stop "this branch touched undeclared files" "declare them, or revert them" "$REFUSALS" ;;
  *)          fold_block "$LG_CHANNEL" stop "a dispatched agent's contract is unmet" "write the named artifacts" "$REFUSALS" ;;
esac
return 2
}

# stop_wait_cell <plan> -> `<cell> <row>`: the Tasks cell a person edits to make a row wait, and the word the edit adds
# for the open row it waits on. A version-15 page holds a task's waits in its deps cell, a row by its id and a ruling as
# `approval:DN`; an older page in its reads cell, a row by its record, the ruling the same.
stop_wait_cell() {
  bionic_need plan-read.sh plan_read_header
  case "$(plan_read_header "${1:-}" canonical_sdlc_version 2>/dev/null)" in
    canonical_sdlc_version=15) printf 'deps RID\n' ;;
    *) printf 'reads RECORD\n' ;;
  esac
}

# ─── stop_patrol_duties ───
#
# THE HOOK'S OWN HEADER, CARRIED OVER WHOLE. It is the design record for this
# verdict — every ruling, incident and measurement that shaped it — and it
# travels with the code rather than being left behind in a deleted file.
# Where it says "this hook" it now means this function, and where it names a
# registration it means hooks/stop.sh's.
#
# THE PATROL-DUTIES WALL — task-dispatch-wall-channel-loss, T5.
#
# Stop. On every orchestrator turn end: refuse the stop once when a stand-down the tick
# ordered since the previous turn end, or a fillable gap, is left unanswered. THE TASK-LIST DUTIES ARE GONE: a tick turn owes
# no task-list refresh and a dispatch turn no task entry set in progress, a process check the
# turn's end demanded of the model with nothing behind it to do; the tick still prints
# `poker: RECONCILE` as advice no wall reads. THAT IS THE TICK ARM'S HALF ONLY. The
# GAP arm (wave-20 Δ7, ADR-033 d2) judges EVERY Stop, Patrol or not: a live ledger with
# fillable ready rows the turn left undispatched is refused. A row that should wait is made not
# ready by a fact of the plan (a read of the record of an open row, a read of an unruled decision,
# the user's order), so it is never owed, and nothing the turn says answers a ready row. A turn that is neither a tick nor a fillable gap
# passes untouched, as does any ambiguity along the way.
#
# WHY A WALL AND NOT BETTER WORDING. The duties live in the Patrol prompt today,
# and a prompt is text: it asks. Prose rules and reminder hooks were measured not to
# bind a model that had already decided; the walls were what did, so every rule here
# that actually binds is a wall, and the only event that can express
# "this must have happened before the turn ends" is the turn's END. A PreToolUse
# arm cannot say it — at the moment any single tool runs, the turn is not over
# and nothing has been skipped yet. So the predicate is retrospective by
# construction, and Stop is the one channel that can ask it.
#
# WHY ALWAYS-ON, AND WHAT SCOPES IT INSTEAD. This gate was registered in the governing
# skill's frontmatter so that it would be live exactly while that skill was — the duty
# it binds is the skill's own Patrol's. That coupling was the defect, not the design:
# a skill's registrations are looked up per session, so a `/clear`, a compaction or a
# session the skill was never invoked in left the wall installed, green in its own
# suite, and not running. The duty did not stop existing in those sessions; only the
# wall did.
#
# It is registered once in hooks/hooks.json now, on `Stop` — which still fires once per
# orchestrator turn and keeps firing on turns nothing was re-invoked. What scopes it is
# an ON-DISK fact: `session_run` (which was `active_run` until wave-session-bound-run made
# run identity per-session) under the payload's project root. A run is active while
# its plan says so.
#
# WHAT COUNTS, AND WHEN. Only in this turn: an answer given in an earlier turn answered
# that turn's orders. Only on the MAIN THREAD: a tool_use inside an agent context (`isSidechain`, or
# a non-empty agent key) belongs to a subagent, and a subagent's ListAgents did
# not refresh the orchestrator's panel — the mirror image of the exclusion
# hooks/session-poker.sh:399-406 makes for the same reason.
#
# THE TASK-LIST FALLBACK IS NOT A CONVENIENCE. The task tools are absent from
# some model/CLI combinations (removed for fable-5 in CLI 2.1.228–2.1.233; the census
# is the rationale block in payload/scripts/lib/env.sh), and in those sessions the plan's own ledger IS the
# task list. A wall that demanded `TaskList` there would be unsatisfiable, which
# is the one failure mode a blocking gate must not have. So an Edit/Write/
# NotebookEdit/Bash tool_use whose input names the active plan file discharges
# the same duty.
#
# FAIL DIRECTIONS (pinned by tests/patrol-duties-gate.test.sh):
#   - jq absent                                          -> pass, silent
#   - not a Stop payload (SubagentStop included)          -> pass, silent
#   - stop_hook_active true                               -> pass, silent (blocks ONCE)
#   - no cwd, or it is not a directory                    -> pass, silent
#   - no transcript_path, or no file there, or a symlink  -> pass, silent
#   - no user prompt in the transcript at all             -> pass, silent
#   - a live ledger with no free slot or no ready row      -> pass, silent (the ready set and
#                                                           occupancy computed)
#   - the machine reads HOLD or EMERGENCY                 -> pass, silent (measured here)
#   - a row that waits: an open row's record, an unruled decision or an order -> not ready, pass
#   - a free slot and a ready row after the launches      -> REFUSE, naming the ready rows
#   - a printed FILL or withheld line, anywhere           -> ignored (advice, not evidence)
#   - a stand-down the tick ordered since the previous turn end, unanswered -> REFUSE, naming it
#
# TWO ACCEPTED LIMITS, both a false BLOCK rather than a false silence, and both
# cheap because the refusal is once-only (stop again and the turn ends). First,
# the Stop-time transcript "isn't guaranteed to include the final message ... on
# all versions" (hooks reference, Stop input), so a duty discharged as the very
# last act of the turn may not be on disk when this reads it. Second, a Patrol
# tick that legitimately has nothing to do still owes both duties under this
# gate — which is the contract SKILL.md states, not an accident of the read.
#
# AND THERE IS NO BACKSTOP ABOVE OURS. This used to cite the hooks reference —
# "Claude Code overrides the hook and ends the turn after 8 consecutive blocks"
# — as the net under both limits. It is not one, for the same reason the same
# claim was struck from hooks/patrol-revive.sh (critic C-2, epic-19 w1): this
# gate blocks ONCE PER TURN by design (`stop_hook_active` → pass, below), and
# blocks one per turn are never consecutive, so that override can never engage
# above a hook shaped like this one. What bounds the refusal is the thing
# the reason line already names — do the two duties and stop again — not a
# counter in the CLI.
#
# IT WRITES NOTHING AND DECIDES NOTHING ELSE. No state file, no roster append, no
# stamp: this is a gate, and gates may only read (TDD §3.2). It takes no view on
# whether the tick's WORK was right, only on whether the two duties happened. The turn's
# `stop` event is written by `stop_fill_ledger` (below), a recorder hooks/stop.sh runs before
# this gate, never by the gate itself (wave-20 REQ-5).
#
# Registered once on the Stop channel in hooks/hooks.json, and scoped by ENGAGEMENT — this
# session having invoked canonical-sdlc — not by the repo merely holding an open plan
# (task-engaged-session). The plan still answers "which plan", never "whether".
# [WALL: tests/patrol-duties-gate.test.sh]
#
# hooks/patrol-duties-gate.sh's body. Stop only: a subagent has no Patrol duties,
# and a wall that refused its stop would hold a worker hostage to its
# orchestrator's obligations.

stop_patrol_duties() {  # <event> -> 0 nothing · 1 advisory · 2 block
  local _ev="${1:-}" _adv=0
  local TRANSCRIPT HOOK_DIR PLAN PLAN_NAME STREAM
  local FILL_MISSING FILL_REASON FILL_FORMS _fill_detail
  local FILL_SRC FILL_FACT FILL_FIX _FF_SHOWN _FF_MORE _FF_ID _fd_cell _fd_row _fd_what
  local -a _FF_IDS
  local STANDDOWN_MISSING STANDDOWN_REASON _SD_BOUND _SD_SET

  case "$_ev" in Stop) : ;; *) return 0 ;; esac

TRANSCRIPT=$(bionic_jq .transcript_path)
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && [ ! -L "$TRANSCRIPT" ] || return "$_adv"

# THIS SCRIPT'S OWN DIRECTORY, so the poker the ritual message names is the same
# file a model would actually run — resolved the way hooks/patrol-revive.sh
# resolves its sibling, never through PATH and never a placeholder.
HOOK_DIR="$_STOP_HOOK_DIR_ABS"
[ -n "$HOOK_DIR" ] || HOOK_DIR="$_STOP_HOOK_DIR_RAW"
# ---------- THE ENGAGEMENT SWITCH — asked before anything else ----------
#
# task-engaged-session: bionic's walls are the RUN's, not the repo's, and a run is entered
# by invoking canonical-sdlc. A session that never did is a bystander here and must not see
# a refusal, an advisory, or a state write from this hook. `engaged_session` (lib/run.sh) is
# true only for a REGULAR file at `.bionic/tmp/engaged-<sid>.state`; every unreadable state —
# absent, symlink, foreign sid, `unknown` — reads as NOT engaged. Silent, return "$_adv": the
# direction §7 gives every start-side ambiguity, and here it is the consent boundary itself
# (1.3.2 close-out ruling — the arming partition IS the consent boundary). It is also what
# ends this gate's largest cost on a bystander turn: the full-transcript jq pass below never
# starts.
[ "$BIONIC_ENGAGED" = 1 ] || return "$_adv"

# ---------- THE RUN PREDICATE (AC-7, AC-8) ----------
#
# Before the transcript is parsed, and that placement is the point. The full-transcript
# jq pass below is this hook's whole cost, and it used to run on every Stop in every
# session on the machine — 32.5ms with no transcript, 44.7ms over a 601-line one, scaling
# with the transcript, to answer a question that is only ever asked inside a run (R-2
# §(c)). Now a project with no open run pays one directory walk.
#
# It also answers "which plan" — the same reader, so this gate and the tick it polices
# cannot disagree about which file the duty is owed against.
#
# IT NO LONGER DECIDES WHETHER THIS GATE ACTS — engagement does (above). Both of this
# gate's duties are owed to a TICK, not to a plan: the ritual arm reads clear/resume
# markers, and the duties and FILL arms fold the tick's own output out of the transcript.
# The plan contributes one thing, a basename that lets a write to the plan file count as
# the task-list refresh, and the fold below already treats an empty name as matching
# nothing. So an engaged session with no plan is policed exactly as one with a plan, minus
# that one alternative way to discharge the refresh.
#
# wave-session-bound-run S5: `active_run` (no session input) is now `session_run`
# (lib/run.sh) — a session BOUND to a plan is policed against THAT plan's basename
# alone, whatever else is open in the root (AC-1); bound to a plan that has since closed
# is policed exactly as engaged-with-no-plan (AC-6) — the basename discharge is the only
# thing a missing plan costs. UNBOUND, the newest plan is announced and never acted on
# (wave-23-fixit-1810, REQ-1, D1): the advisory goes out once on stderr and the turn is
# policed as engaged-with-no-plan too, so a write naming somebody else's plan discharges
# nothing, and the fill duty below has no ledger to charge (`stop_turn_facts`).
PLAN="$BIONIC_RUN_PLAN"
case "$BIONIC_RUN_WORD" in
  bound-open) : ;;
  fallback)
    stop_unbound_advise "$PLAN" && _adv=1
    PLAN=""
    ;;
  bound-closed)
    fold_advise "patrol-duties-gate: bound plan closed — $PLAN; this session has no open run"; _adv=1
    PLAN=""
    ;;
  bound-unreadable)
    # THE TURN IS HELD, ONCE (wave-20 T1, REQ-2, D2; AC-2.3). A bound plan that is there and
    # cannot be read is a run this session may still be in, with every wall that measures
    # against it blind — the commit gate refuses, the tick cannot fill, the budget cannot be
    # read. Saying so on the advisory channel alone lets the turn end on it. The refusal is
    # once per turn by construction: hooks/stop.sh reads `stop_hook_active` ahead of every
    # verdict, so the re-entered Stop passes and this cannot loop.
    fold_advise "patrol-duties-gate: bound plan unreadable — $PLAN"
    fold_block block stop "the bound plan cannot be read" "restore read access to the plan" \
      "The plan this session is bound to exists and cannot be read: $PLAN
It is not closed and it is not gone, so no other plan is read in its place. Until it can be
read, commits against it are refused and the tick cannot fill from it.
Fix: restore read access (chmod u+r on the plan, u+rx on its folder)."
    return 2
    ;;
  none|*)
    PLAN=""
    ;;
esac
PLAN_NAME=""
# `${PLAN##*/}` IS `basename`'s ANSWER WITHOUT THE FORK (REQ-10, T11). `$PLAN` here is a
# plan path `session_run` produced from a `find -type f`, so it names a regular file and
# carries no trailing slash — the one case the two spellings disagree about.
[ -n "$PLAN" ] && [ -f "$PLAN" ] && PLAN_NAME="${PLAN##*/}"

# ---------- the plan's BASENAME ----------
#
# Only the basename is kept. The path a tool_use carries may be absolute, repo-relative
# or cwd-relative depending on which tool wrote it, and the basename is the one form all
# three contain. An empty name matches nothing — guarded at the awk boundary, because an
# empty needle would otherwise make every write in the turn discharge the duty.

# ---------- reading the turn ----------
#
# THE TURN'S FACTS ARE COMPUTED ONCE PER STOP, by `stop_turn_facts` below, and shared with the
# fill ledger's recorder (wave-20 REQ-5, D5): `hooks/stop.sh` runs the recorder BEFORE its
# re-entry guard, so on an ordinary Stop the transcript pass and the fill arithmetic have
# already run by the time this duty asks, and the ledger line and this verdict are one
# computation — they cannot disagree. The stream's records, the window and the scoping of
# each marker are documented there.
stop_turn_facts || return "$_adv"
STREAM="$_ST_STREAM"
[ -n "$STREAM" ] || return "$_adv"

# ---------- THE THIRD DUTY: no turn ends on a fillable gap (AC-29; wave-20 REQ-5, Δ7) ----
#
# WHY THIS IS A WALL AND NOT A LINE IN THE PROMPT. The tick can compute the gap between the
# budget and the roster, and it can name the tasks that are ready — but it cannot dispatch,
# and a recommendation nobody is obliged to answer is how this repo's own 1.4.0 wave ran six
# writers against a budget of twenty-two. The turn's END is the only moment at which "the
# gap went unfilled" is a fact, so it is the moment this asks.
#
# THE WALL COMPUTES THE TURN'S FACTS; IT OVERHEARS NOTHING (Δ7; ADR-036 decision 3). Until
# wave-20 this duty read the tick's printed `poker: FILL <ids>` and `poker: fill withheld`
# lines out of the transcript and answered each printed id by finding it in an Agent call's
# words. Every way of planting those lines reproduced (research D1 §4): the model's own prose
# planted a FILL, a `cat` of a file planted a HOLD exemption, a grep of a reply line planted an
# answer, and an Agent prompt that mentioned an id answered it. Now:
#   - the READY SET is the plan's (`fill_ready_set`, T10's prerequisite graph), untrimmed;
#   - the OCCUPANCY is the roster's (`roster_open_names`), which a dispatch joins at launch,
#     so it already counts this turn's launches when the Stop fires;
#   - the WIDTH is the gate's (`fill_gate_width`, lib/fill.sh; wave-28 T13, D14), asked here
#     the way the tick asks it rather than read back out of the tick's words;
#   - the only transcript fact is the turn's launches: nothing the model writes answers a row.
# JUDGED BY COUNT: after the turn's launches, `missed = min(free writer slots, ready writer rows
# this turn did not launch) + the ready read-only rows it did not launch` (a verify or review row
# takes no writer slot; wave-26 T13, D9) is what the ledger records, and a turn with a ready row
# undispatched and a gate that gave room is refused once, naming EVERY such row
# (wave-36 T32; D13, AC-7.1): until wave-36 it named `min(free, ready)` of them, so one free slot
# and fourteen ready rows took fourteen turns. No id is ever matched against a
# dispatch's PROMPT words. A dispatched row leaves the plan's ready set when the launch recorder
# (hooks/execution-recorder.sh, wave-26 T12) sets it `active`, and until then the turn that
# launched it is not charged for it: its dispatch NAME (`fill_row_launched`,
# the inverse of `fill_name`) takes it out of what the turn missed (wave-20 T11b, A-T11b.2).
# The headline names the ready rows the turn did not launch.
#
# A ROW THAT SHOULD WAIT IS MADE NOT READY, NEVER ANSWERED IN WORDS. There are good reasons not to
# fill (a row landing this minute, a decision the user has not ruled, an order), and each is a
# fact of the plan the tick judges once: a read of the record of the row it waits on, a read of
# the decision (`approval:D<n>`), or the user's order in the run's log. A reason written in
# a reply was read again on every turn end and judged by nothing. So the refusal names the three
# forms, and the predicate is "a ready row is undispatched", never "a reason was given".
#
# NO PLAN OWES A BUDGET LINE (wave-28 T9; D15, REQ-2 AC-2.9). Until wave-28 a live ledger whose
# plan carried no readable `writers=` was refused once here, naming the key Step 0 wrote from
# the machine probe. A line caps a run only when a person wrote it (`budget_cap`, lib/run.sh),
# so a plan with none is an ordinary plan and this wall says nothing about it.
FILL_SRC=""
FILL_MISSING=""
if [ "${_ST_GAP:-0}" -gt 0 ] 2>/dev/null && [ "$_ST_STATE" = ok ]; then
  FILL_SRC="GAP"
  FILL_MISSING="$_ST_NAMED"
fi

if [ "$FILL_SRC" = "GAP" ]; then
  # ONE LINE, EVERY READY ROW. This was once a six-line
  # paragraph naming `min(free slots, ready rows)` of the rows. The user reads one line naming every
  # ready row the turn left (`_ST_NAMED`); the rule behind it lives in the dispatch doctrine ('The
  # FILL line is advice; the wall counts'). The model's copy adds the rows comma-joined in one
  # dispatch line and the three forms that make a row wait, two an edit of the cell that holds the row's waits
  # (`stop_wait_cell`: deps at 15, reads before) and one a command: ID, RECORD, RID, N and WORDS are upper-case words,
  # never `<...>` a shell reads as a redirect. An edit adds to what the cell holds, an empty reads cell being its kind's
  # default, so the row keeps the waits that already hold it.
  # `FILL_REASON` is the same facts as one line, the form a duty paragraph takes when this refusal
  # rides beside a stand-down's.
  _fd_poker="$(refuse_shell_word "${HOOK_DIR}/session-poker.sh")"
  read -r _fd_cell _fd_row <<< "$(stop_wait_cell "$PLAN")"
  _fd_what="the record of the open row it waits on; an empty cell is its kind's default, written out first"
  [ "$_fd_row" = RECORD ] || _fd_what="the id of the open row it waits on"
  FILL_FORMS="dispatch ${FILL_MISSING// /,}, or make each wait by one of three forms:"
  FILL_FORMS="${FILL_FORMS}"$'\n'"a dependency: edit ID's ${_fd_cell} cell in the plan to add ${_fd_row} (${_fd_row}: ${_fd_what})"
  FILL_FORMS="${FILL_FORMS}"$'\n'"a read of a ruling: edit ID's ${_fd_cell} cell in the plan to add approval:DN (DN: the decision nobody has ruled)"
  FILL_FORMS="${FILL_FORMS}"$'\n'"an order: bash ${_fd_poker} order 'WORDS' (WORDS: what the user said)"
  FILL_REASON="ready with room: ${FILL_MISSING}; dispatch them, or make each wait: a dependency (add ${_fd_row} to ID's ${_fd_cell} cell in the plan), a read of a ruling (add approval:DN to it) or an order (bash ${_fd_poker} order 'WORDS')"
  # THE LINE HAS width.sh's 100 COLUMNS, and refuse.sh writes it `bionic: stop refused — <fact>
  # (<fix>)`: 23 columns before the fact and 30 after it with this fix, so the fact keeps to 44 and
  # the line to 97. Every id when they fit; else the ids that fit with "+N more" for the rest, which
  # the dispatch line names in full.
  FILL_FIX="dispatch, or make each wait"
  FILL_FACT="ready with room:"
  _FF_SHOWN=""; _FF_MORE=0
  read -r -a _FF_IDS <<< "$FILL_MISSING"
  if [ $(( ${#FILL_FACT} + 1 + ${#FILL_MISSING} )) -le 44 ]; then
    _FF_SHOWN=" ${FILL_MISSING}"
  else
    for _FF_ID in ${_FF_IDS[@]+"${_FF_IDS[@]}"}; do
      if [ "$_FF_MORE" -eq 0 ] && [ $(( ${#FILL_FACT} + ${#_FF_SHOWN} + 1 + ${#_FF_ID} )) -le 34 ]; then
        _FF_SHOWN="${_FF_SHOWN} ${_FF_ID}"
      else
        _FF_MORE=$((_FF_MORE + 1))
      fi
    done
  fi
  FILL_FACT="${FILL_FACT}${_FF_SHOWN}"
  [ "$_FF_MORE" -gt 0 ] && FILL_FACT="${FILL_FACT} +${_FF_MORE} more"
else
  FILL_REASON=""
fi

# ---------- THE FOURTH DUTY: a stand-down the tick ordered is answered before the turn ends ----
#
# (AC-1.2; T1, D1.) The mirror of the FILL, and it exists for the same reason. The tick can
# see that a contract landed while its agent is still on the panel, and it can write the stop
# order that makes the stop legal — but it cannot stop anything, and a recommendation nobody
# is obliged to answer is how eighteen finished agents came to sit idle on one panel while a
# wave ran around them. The turn END is the only moment at which "the stand-down went
# unanswered" is a fact.
#
# THE SET IS COMPUTED, NEVER OVERHEARD (wave-20 T19; T11's carry-over, the AC-5.4 plants on
# this duty). It used to be read off the tick's printed `poker: STANDDOWN <name>` lines in the
# transcript — the channel AC-5.4 closed for the FILL: the model's own prose planted a name, a
# `cat` of a file forged one, and a tick output that never reached the transcript let every
# name go. It is now what the tick WROTE: `stop_standdown_set` (below) reads this session's
# stop orders and roster verdicts from disk. The tick still prints the line, for the human.
#
# ANSWERED MEANS ONE OF THREE, per name:
#   - a main-thread `TaskStop` tool_use naming the agent — by its name or by the
#     `name@session-xxxxxxxx` address the roster carries, which contains the name and so
#     matches the same word-boundary test — whose tool_result was not an error: a stop the
#     harness refused stopped nothing;
#   - an ack closing the row (the sweeper's, which `stop-orders.sh stopped` writes): the
#     computed set leaves out an acked row, so it is never asked about;
#   - a `standdown-declined: <name> <reason>` line at the start of a line of the model's own
#     reply: never thinking, a tool input or a tool result.
#     The reason is required (wave-24 T8, AC-4.10): a name alone is not an answer. It stands as
#     a hold does (wave-26 T15, AC-4.6; D16): below, the wall writes it to the roster through
#     `session-poker.sh hold`, so the tick reads it with the hold's fingerprint check and orders
#     no stop while the agent's launch, deliverable and messages are unchanged;
#   - a HOLD written since this turn's tick (wave-24 T8; D1, AC-4.12): `session-poker.sh hold
#     <name> <reason>` appends the row with `held=<iso> …`, and `stop_standdown_set` leaves out
#     a row held at or after the bound. Read off the roster, never the command's words. The
#     refusal names `hold` because it is the answer that lasts past this turn.
# The decline is not a loophole, it is the point: an agent still writing its record is a good
# reason not to stop it, and that reason is worth one line in the record. What is refused is
# SILENCE.
#
# THE LOWER BOUND IS THE PREVIOUS TURN END (`_ST_PREV_END`). The orders this turn answers are the
# ones the tick wrote since the turn before it ended: the watcher's pass between the two turns, or a
# tick this turn ran itself. An order older than that was owed by an earlier turn, which was told.
#
# NAMED, NOT COUNTED, and per agent: a turn that stopped two of three is missing one, and the
# reason says which. Ids are validated against `[A-Za-z0-9_.-]+` before they are echoed back,
# and a `.` inside one is escaped to a literal before it is spliced into the boundary pattern.
STANDDOWN_MISSING=""
_SD_BOUND="$_ST_PREV_END"
_SD_SET="$(stop_standdown_set "$_SD_BOUND")"
if [ -n "$_SD_SET" ]; then
  STANDDOWN_MISSING=$(printf '%s\n' "$STREAM" | awk -F'\t' -v want="$_SD_SET" '
    $1 == "USER" { n = 0; answered = " "; next }
    $1 == "SD-DECLINE" { answered = answered $2 " "; next }
    $1 == "STOP"       { n++; sw[n] = $2; sid[n] = $3; next }
    $1 == "AGENTERR"   { if ($2 != "") err[$2] = 1; next }
    END {
      for (i = 1; i <= n; i++) {
        if (sid[i] != "" && (sid[i] in err)) continue
        answered = answered sw[i] " "
      }
      m = split(want, names, /[ \t\n]+/)
      missing = ""
      for (i = 1; i <= m; i++) {
        id = names[i]
        if (id == "" || id !~ /^[A-Za-z0-9_.-]+$/) continue
        pat = id
        gsub(/\./, "[.]", pat)
        if (answered ~ ("(^|[^A-Za-z0-9_.-])" pat "([^A-Za-z0-9_.-]|$)")) continue
        if (index(" " missing " ", " " id " ") > 0) continue
        missing = missing (missing == "" ? "" : " ") id
      }
      if (missing != "") print missing
    }
  ')
fi

# A STAND-DOWN DECLINE STANDS AS A HOLD DOES (wave-26 T15, REQ-4 AC-4.6; D16, research-R2 §3
# P3). It answered its own turn and no other, so the next tick that printed in full ordered the
# same unchanged agent down again and the turn had to decline it again. Each name of the set
# this turn declined with a reason is now written as the `hold` verb writes it: a successor row
# carrying `held=<at> <reason> fp=<fingerprint>`. The tick's own check then leaves it standing
# until the agent's launch, deliverable or messages move. The verb is the writer, so the row is
# the one a typed `hold` would have written. A hold the verb refuses changes nothing here: the
# decline still answers this turn, as it always did. The re-entered Stop of the same turn writes
# no second row, because a name held at or after the bound has left `_SD_SET`
# (`stop_standdown_set`).
if [ -n "$_SD_SET" ] && [ -f "${HOOK_DIR}/session-poker.sh" ]; then
  printf '%s\n' "$STREAM" | awk -F'\t' '
    $1 == "USER" { n = 0; split("", why); next }
    $1 == "SD-DECLINE" { if (!($2 in why)) order[++n] = $2; why[$2] = $3; next }
    END { for (i = 1; i <= n; i++) printf "%s\t%s\n", order[i], why[order[i]] }
  ' | while IFS=$'\t' read -r _sd_name _sd_why; do
    case " $_SD_SET " in *" $_sd_name "*) : ;; *) continue ;; esac
    ( cd "$BIONIC_ROOT" 2>/dev/null || exit 9
      CLAUDE_CODE_SESSION_ID="$BIONIC_SID" bash "${HOOK_DIR}/session-poker.sh" hold "$_sd_name" "$_sd_why" ) >/dev/null 2>&1
  done
fi

if [ -n "$STANDDOWN_MISSING" ]; then
  # ONE hold COMMAND PER NAME, each pasteable as printed (wave-24 T27; critic I4): the real
  # name, and the reason as the tick's own quoted placeholder (`HOLD_REASON_SLOT` in
  # hooks/session-poker.sh), never a bare `<reason>` a shell reads as a redirect. The poker path
  # is one shell word, as the tick prints it (wave-24 T29; critic addendum A2), so a plugin root
  # with a space pastes whole.
  STANDDOWN_HOLDS=""
  _sd_poker="$(refuse_shell_word "${HOOK_DIR}/session-poker.sh")"
  for _sd_hold in $STANDDOWN_MISSING; do
    STANDDOWN_HOLDS="${STANDDOWN_HOLDS}${STANDDOWN_HOLDS:+; }bash ${_sd_poker} hold ${_sd_hold} 'why it stays up'"
  done
  STANDDOWN_REASON="Patrol stand-down unanswered: the tick stood down ${STANDDOWN_MISSING} (contract MET, the agent still on the panel, the stop order written) and this turn neither stopped, held nor declined them. TaskStop each. To keep an idle agent up, run: ${STANDDOWN_HOLDS} — the tick then stops ordering it while nothing about it changes. Then stop again — this gate blocks once."
else
  STANDDOWN_REASON=""
fi

# THE TELL-ANSWERING DUTIES TRAVEL TOGETHER from here: a turn that left a FILL and a stand-down
# unanswered is told both things once, because the next stop passes by design and a duty not
# named in the first refusal is a duty never named at all.
TELL_REASON="$FILL_REASON"
[ -n "$STANDDOWN_REASON" ] && TELL_REASON="${TELL_REASON}${TELL_REASON:+ }${STANDDOWN_REASON}"
# The tells are judged TOGETHER, so a turn that left two of them is told both things once.
# Blocking on one and staying silent about the other would hide the second behind the
# one-shot: the next stop passes by design.
if [ -n "$TELL_REASON" ]; then
  # THE FACT NAMES WHICH TELL WENT UNANSWERED, and the pair keeps the FILL wording it
  # always had. Both halves are budgeted: `bionic: stop refused — <fact> (<fix>)` is capped
  # at 100 columns and the fix at six words (payload/scripts/lib/refuse.sh), which is why
  # these read as tightly as they do.
  if [ -n "$FILL_REASON" ] && [ -n "$STANDDOWN_REASON" ]; then
    fold_block duty stop "a FILL and a STANDDOWN went unanswered" \
      "dispatch, make wait, stop, or hold" "$TELL_REASON"
  elif [ -n "$FILL_REASON" ]; then
    # THE FACT AND THE FIX COME FROM THE ARM THAT FIRED (REQ-3): the computed gap. Its detail is
    # the dispatch line and the three forms, each on a line of its own so it pastes whole.
    _fill_detail="$FILL_FORMS"
    fold_block duty stop "$FILL_FACT" "$FILL_FIX" "$_fill_detail"
  else
    fold_block duty stop "a STANDDOWN went unanswered" "stop each agent, or decline" \
      "$TELL_REASON"
  fi
  return 2
fi
return "$_adv"
}


# ─── stop_turn_facts and stop_fill_ledger (epic-23 wave-20, REQ-5 part 2 and REQ-6; D5, D6) ───
#
# ONE COMPUTATION OF A TURN'S FACTS, TWO READERS. The fill duty above judges a turn and its
# `stop` event records it; if each computed its own facts, the
# verdict and the record could disagree, and the record is what a run's fill is measured by.
# So `stop_turn_facts` computes them once per process into `_ST_*` globals, and both call it:
# `hooks/stop.sh` runs `stop_fill_ledger` BEFORE its re-entry guard, then `bionic_fold` runs the
# duty, which finds the facts already computed.
#
# WHAT IT SETS, and nothing else:
#   _ST_STREAM      the transcript records below, one per line, tab-separated
#   _ST_PLAN        the run's plan — bound-open alone — or empty. A `fallback` plan is
#                   announced and never acted on (wave-23-fixit-1810, REQ-1, D1): it is
#                   somebody else's run, so an unbound session has no ledger to fill from,
#                   records no stop event, and is never refused for its ready rows
#   _ST_LIVE        1 when that plan's ledger is live (past Step 3), else 0
#   _ST_PREV_END    the instant the turn before this one ended: the last turn-end record (`stop_hook_summary`)
#                   before this turn's prompt. With none in the window the duties are owed, as the watch
#                   reader refuses on a transcript it cannot read: the bound is then the epoch's start
#   _ST_TURN        the turn key: the prompt record's uuid, else its timestamp, else empty
#   _ST_MARK_TS     the prompt record's timestamp, or empty
#   _ST_LAUNCHED    comma-joined names of this turn's main-thread Agent calls, less the ones
#                   whose result was an error (a dispatch the preflight refused); once the
#                   roster is read, each name whose row carries `row=` is that id (wave-28 T7)
#   _ST_CURRENT _ST_STATE _ST_CEILING _ST_WIDTH _ST_OPEN _ST_FREE   the ledger's numbers
#   _ST_READY       every ready id, space-joined, untrimmed — the plan's set, launches included
#   _ST_READY_N     how many ids _ST_READY holds
#   _ST_SENT        how many of them this turn launched (`fill_row_launched`, by dispatch name)
#   _ST_MISSED      min(free, |ready not launched this turn|) — after this turn's launches, since
#                   the roster holds them. The ledger records it raw
#   _ST_GAP         |ready not launched|, the writers among them counted only while a slot is
#                   free — what the wall refuses on
#   _ST_NAMED       those ids, every one, the ones a refusal names: a slot free is room for the
#                   refusal, never a trim of it
#   (`_ST_TICK_DUTY`, `_ST_RECONCILE` and `_ST_ENTERED`, the task-list duties' inputs, went with
#   those duties at wave-31 T32; the tick still writes `duty=` and `reconcile=`, read by no wall)
# Return 0 when the turn could be read at all (a Stop, an engaged session, a transcript), 1
# otherwise — and the caller then has nothing to judge and nothing to record.
#
# THE RECORDS. jq flattens each transcript line into at most a few records; the awk folds
# below reset at every user PROMPT so that what survives describes the LAST turn only.
#   USER <text> <timestamp> <uuid>   a user record carrying text — a turn's prompt. The `user`
#                                    type is also how the CLI records every TOOL RESULT, and
#                                    treating those as prompts would end the tick's turn at its
#                                    first tool call. Nor is every user TEXT record a prompt:
#                                    the CLI writes two into the turn they interrupt, and they
#                                    open no turn (wave-20 T11b; Step-6 review R3, critic C1):
#                                      the Stop hook's refusal fed back — isMeta (the stream-json
#                                        spelling is isSynthetic) and text starting
#                                        "Stop hook feedback:" (refuse.sh's channel table);
#                                      a companion record — turnCompanion: a skill's body after a
#                                        Skill call or a slash command, an attached image.
#                                    isMeta ALONE marks neither: a scheduled prompt is isMeta
#                                    too, and it is a turn. So the re-entry Stop after a
#                                    refusal keeps the prompt's key, launches and previous turn
#                                    end, and a launch made before a Skill call stays the turn's.
#                                    Survey behind the rule: A-T11b.1.
#   TOOL <name> <path/cmd> <fields>  a main-thread assistant tool_use
#   AGENT <name> <tool_use id>       a main-thread Agent tool_use — the launch the ledger names
#   AGENTERR <tool_use id>           a tool_result with `is_error: true`: a refused dispatch,
#                                    which writes no roster row and launched nothing — or a
#                                    refused TaskStop, which stopped nothing (any tool's error)
#   STOP <task id words> <tool_use id>  a main-thread TaskStop tool_use — the stand-down's answer
#   END <timestamp>                  a turn-end record (`type: system`, `subtype: stop_hook_summary`),
#                                    the record the watch reader dates a turn end by
#   SD-DECLINE <name> <reason>       `standdown-declined: <name> <reason>` at a LINE START of a
#                                    main-thread assistant TEXT block — never thinking, never a
#                                    tool_use input, never a tool result, so prose quoting,
#                                    a file read and a grep plant nothing. The name alone is not an answer:
#                                    the reason must carry a letter or digit (wave-24 T8, D2,
#                                    AC-4.10). The tick's printed `poker: STANDDOWN` line is
#                                    no longer a record at all: the set is computed from disk
#                                    (`stop_standdown_set`), never read out of the transcript
# Newlines and tabs are squashed inside values because the stream is line-and-tab delimited.
#
# THE WINDOW (review, performance finding 1). Every fact here is a "since the most recent X"
# fact, so a 2000-line tail suffices provided it holds a whole orchestrator turn: the largest
# single turn in this repo's two busiest wave transcripts is 264 records (measured 2026-09-03),
# so the window carries ~7.5x the worst turn observed.
SCAN_WINDOW_LINES=2000
stop_turn_facts() {  # -> 0 facts computed · 1 nothing to read
  [ "${_ST_DONE:-0}" = 1 ] && return "${_ST_RC:-1}"
  _ST_DONE=1; _ST_RC=1
  _ST_STREAM=""; _ST_PLAN=""; _ST_LIVE=0; _ST_PREV_END=""; _ST_TURN=""; _ST_MARK_TS=""
  _ST_LAUNCHED=""; _ST_CURRENT=""; _ST_STATE=""; _ST_CEILING=""
  _ST_WIDTH=""; _ST_OPEN=""; _ST_FREE=""; _ST_READY=""; _ST_MISSED=""; _ST_NAMED=""
  _ST_READY_N=0; _ST_SENT=0
  _ST_GAP=""; _ST_LIVE_HEAD=""; _ST_FACTS=""
  local tr fold rest ready count want cap owed FILL_ROSTER FILL_ACKS FILL_OPEN
  local digest at rvat gap rcount rgap slot

  [ "$(bionic_jq .hook_event_name)" = Stop ] || return 1
  [ "${BIONIC_ENGAGED:-0}" = 1 ] || return 1
  tr="$(bionic_jq .transcript_path)"
  [ -n "$tr" ] && [ -f "$tr" ] && [ ! -L "$tr" ] || return 1

  case "$BIONIC_RUN_WORD" in
    bound-open) _ST_PLAN="$BIONIC_RUN_PLAN" ;;
  esac
  [ -n "$_ST_PLAN" ] && [ -f "$_ST_PLAN" ] || _ST_PLAN=""
  stop_facts_load

  _ST_STREAM=$(tail -n "$SCAN_WINDOW_LINES" "$tr" 2>/dev/null | jq -Rr '
    . as $line
    | (($line | fromjson?) // null) as $r
    | ($r != null
       and (($r.isSidechain // false) != true)
       and ((((($r.agentId // $r.agent_id) // "") | tostring)) == "")) as $main
    | (
        if ($main | not) then ""
        elif $r.type == "user" then
          ( if ($r.message.content | type) == "string" then $r.message.content
            else ([$r.message.content[]? | select(.type == "text") | .text] | join(" "))
            end )
        else $line
        end
      ) as $auth
    | ($main and $r.type == "user"
       and ( (($r.turnCompanion // false) == true)
             or ( ((($r.isMeta // false) == true) or (($r.isSynthetic // false) == true))
                  and (($auth // "") | startswith("Stop hook feedback:")) ) )) as $cont
    | (if ($r != null and $r.type == "system" and $r.subtype == "stop_hook_summary")
       then "END\t" + ((($r.timestamp // "") | tostring) | gsub("[\n\t\r]"; " ")) else empty end),
      ( if ($main and $r.type == "user" and (($r.message.content // []) | type) == "array") then
          $r.message.content[]?
          | select(.type == "tool_result" and (.is_error // false) == true)
          | "AGENTERR\t" + ((.tool_use_id // "") | tostring)
        else empty end ),
      ( if ($main and $r.type == "assistant" and (($r.message.content // []) | type) == "array") then
          ([$r.message.content[]? | select(.type == "text") | .text] | join("\n"))
          | [scan("(?:^|\n)standdown-declined:[ \t]*([A-Za-z0-9_.-]+)[^A-Za-z0-9_.\n-]([^\n]*[[:alnum:]])")] | .[]
          | "SD-DECLINE\t" + .[0] + "\t" + (.[1] | gsub("[\t\r]"; " "))
        else empty end ),
      (
        if ($main | not) then empty
        elif $r.type == "user" then
          ( if ($r.message.content | type) == "string" then $r.message.content
            else ([$r.message.content[]? | select(.type == "text") | .text] | join(" "))
            end ) as $t
          | select(($t // "") != "" and ($cont | not))
          | "USER\t" + ($t | gsub("[\n\t\r]"; " "))
            + "\t" + ((($r.timestamp // "") | tostring) | gsub("[\n\t\r]"; " "))
            + "\t" + ((($r.uuid // "") | tostring) | gsub("[\n\t\r]"; " "))
        elif $r.type == "assistant" then
          $r.message.content[]?
          | select(.type == "tool_use")
          | ( "TOOL\t" + (.name // "")
              + "\t" + (((.input.file_path // .input.path // .input.command // "") | tostring) | gsub("[\n\t\r]"; " "))
              + "\t" + (([.input.name?, .input.description?, .input.subagent_type?, .input.prompt?,
                          .input.task_id?]
                         | map(select(. != null) | tostring) | join(" ")) | gsub("[\n\t\r]"; " ")) ),
            ( if .name == "Agent" then
                "AGENT\t" + (((.input.name // .input.subagent_type // "agent") | tostring) | gsub("[\n\t\r|, ]"; "_"))
                + "\t" + ((.id // "") | tostring)
              else empty end ),
            ( if .name == "TaskStop" then
                "STOP\t" + (([.input.task_id?, .input.name?, .input.shell_id?]
                              | map(select(. != null) | tostring) | join(" ")) | gsub("[\n\t\r]"; " "))
                + "\t" + ((.id // "") | tostring)
              else empty end )
        else empty
        end
      )
  ' 2>/dev/null) || _ST_STREAM=""
  [ -n "$_ST_STREAM" ] || return 1
  _ST_RC=0

  # THE TURN, FOLDED ONCE. One output line, its fields joined by the unit separator (0x1f):
  # a tab is whitespace to `read`, so two empty fields in a row would collapse into one.
  fold="$(printf '%s\n' "$_ST_STREAM" | awk -F'\t' '
    $1 == "END"  { if ($2 != "") lastend = $2; next }
    $1 == "USER" {
      prev = lastend
      ts = $3; key = ($4 != "" ? $4 : $3)
      n = 0
      next
    }
    $1 == "AGENT"    { n++; an[n] = $2; aid[n] = $3; next }
    $1 == "AGENTERR" { if ($2 != "") err[$2] = 1; next }
    END {
      launched = ""
      for (i = 1; i <= n; i++) {
        if (aid[i] != "" && (aid[i] in err)) continue
        launched = launched (launched == "" ? "" : ",") an[i]
      }
      printf "%s\037%s\037%s\037%s\n", (prev == "" ? "0000-00-00T00:00:00Z" : prev), key, ts, launched
    }')"
  IFS=$'\037' read -r _ST_PREV_END _ST_TURN _ST_MARK_TS _ST_LAUNCHED <<< "$fold"
  [ -n "$_ST_PREV_END" ] || _ST_PREV_END="0000-00-00T00:00:00Z"

  # THE TICK'S DIGEST (wave-24 T8; wave-26 T32): its path and reader are the tick's own (lib/patrol.sh
  # `tick_digest_path`, `tick_digest_field`), under the session's root. Its
  # `duty=` and `reconcile=` lines fed the task-list duty, which went at wave-31 T32 (D6); what is
  # read here now is the head and the facts state below.
  #
  # A DIGEST OLDER THAN THE PREVIOUS TURN END IS NO DIGEST. The tick this turn answers ran
  # since that turn ended, the watcher's pass or one the turn ran itself; a tick that exits on a refusal
  # writes none, so the digest's `at=` must not be earlier than that end. A digest with no `at=` is no digest.
  digest="$(tick_digest_path "$BIONIC_ROOT" "$BIONIC_SID")"
  at="$(tick_digest_field "$digest" at)"
  {
    # THE HEAD THE TICK JUDGED `live:head` AGAINST (wave-26 T32; A-T14.2), from the same fresh
    # digest: the wall reads no git, so on a tick's turn it hands the tick's head to the ready set
    # below, and a follow-up review the tick offered is a review the wall owes. With a stale digest
    # there is no head, and a live review waits here as before.
    #
    # A HEAD OLDER THAN THE NEWEST REVIEW PROOF IS NOT HANDED IN (wave-26 T51; review 13 F3, review 10
    # (a)). The digest can be fresh for the turn and still older than a `proof-add review` made
    # after the tick at a newer head (a landing, then the proof): handed in, the tick's head reads
    # as a landing past that proof and the wall would owe a review of nothing. So the head goes in
    # only when the digest's `at=` is newer than the newest review proof's `at=`; otherwise
    # there is none, as off a tick's turn, and the review waits for the next tick. Both stamps are
    # the wall's already: the digest it reads above and the run's facts. No git is read. A run whose facts
    # this shell could not load gives no instant, so no head is handed in and the review waits, as off a tick.
    # A TIE HANDS IN NO HEAD (wave-26 T54; review 17 N4): a proof in the tick's own second cannot
    # be ordered against it, and the soft side is a review that waits one tick, not one owed for
    # nothing.
    # PER QUESTION, THE READY SET JUDGES; THIS RULE STAYS GLOBAL (wave-27 T10; D4). The head goes
    # into units.sh, which keys each read row's last proof by its own questions, so the wall owes
    # what the tick offered row by row. Which head goes in is still decided against the newest
    # review proof of ANY question, a reading included: a reading newer than the digest withholds
    # the head from every row, never owes one, and costs one tick's wait.
    # THE FACTS STATE THE TICK JUDGED (wave-27 T43; A-orch-82): the integrate row's `proof:review`
    # is met only by the judge's `covered` (T14), and the wall runs no judge, so it hands in the
    # digest's `facts_state=` under the same two tests as the head: a digest of this turn, and no
    # review proof newer than it. Otherwise it hands nothing, and integrate waits, as off a tick.
    if [ -n "$at" ] && ! [ "${at:0:19}" \< "${_ST_PREV_END:0:19}" ]; then
      _ST_LIVE_HEAD="$(tick_digest_field "$digest" head)"
      _ST_FACTS="$(tick_digest_field "$digest" facts_state)"
      if { [ -n "$_ST_LIVE_HEAD" ] || [ -n "$_ST_FACTS" ]; } && [ -n "$_ST_PLAN" ]; then
        if ! rvat="$(fill_review_at "$_ST_PLAN")"; then _ST_LIVE_HEAD=""; _ST_FACTS=""
        elif [ -n "$rvat" ] && ! [ "${rvat:0:19}" \< "${at:0:19}" ]; then _ST_LIVE_HEAD=""; _ST_FACTS=""; fi
      fi
    fi
  }

  # THE FILL'S NUMBERS — only on a live ledger (past Step 3), exactly as before: a run at
  # Steps 0-3, a run with no plan, or a `current:` that will not parse stops here without
  # touching the table, and records no ledger line.
  [ -n "$_ST_PLAN" ] && fill_ledger_live "$_ST_PLAN" || return 0
  _ST_LIVE=1
  _ST_CURRENT="$(_fill_current_field "$_ST_PLAN")"
  # A PERSON'S CAP, OR NONE (wave-28 T9; D15), read ONCE: `fill_cap` (lib/fill.sh) calls
  # `budget_cap` (lib/run.sh), which answers only from a line whose `source=` is `user` or
  # `override`. The width below and the ledger's `ceiling=` both take this one value, so a probe's
  # number caps neither.
  _ST_CEILING="$(fill_cap "$_ST_PLAN")"

  # THE STATE IS THE GATE'S (wave-28 T13; D14): `hold` when it gives no room for one ready
  # writer row, read below beside the width; `ok` otherwise. A gate that will not answer is
  # `ok` with no room, so a turn is never refused on a width nobody could read.
  _ST_STATE=ok

  # NO CAP IS NOT A FAULT (D15): with none, the width below is the gate's alone. Until wave-28 a
  # live ledger with no readable `writers=` refused the turn once here, naming the key.

  # THE OCCUPANCY IS THE ONE CLOSE PREDICATE'S OPEN SET (wave-20 T2, D10): this session's
  # roster rows not closed by a later ack. A roster or ledger that is a symlink is not read,
  # and the numbers are left unknown rather than judged on zero — zero refuses more.
  FILL_ROSTER="$BIONIC_ROOT/.bionic/tmp/roster-${BIONIC_SID}.state"
  FILL_ACKS="$BIONIC_ROOT/.bionic/tmp/sweeper-${BIONIC_SID}.state"
  if [ -L "$FILL_ROSTER" ] || [ -L "$FILL_ACKS" ]; then
    return 0
  fi
  # THE ROW LABEL FIRST (wave-28 T7; D17): a launch whose roster row carries `row=` counts as that
  # row's, by the id itself; only a launch with none is matched by its name. The ledger records the
  # same list.
  if declare -F fill_launched_rows >/dev/null 2>&1; then
    _ST_LAUNCHED="$(fill_launched_rows "$FILL_ROSTER" "$BIONIC_SID" "$_ST_LAUNCHED")"
  fi
  # THE WRITERS AMONG THEM (wave-24 T13, D11): `budget_open_writers` (lib/roster.sh) leaves a
  # read-only role out, as the dispatch wall and the tick's `TICK_OCCUPIED` do, so the three
  # readers of the open set count the same slots.
  FILL_OPEN="$(roster_open_names "$FILL_ROSTER" "$FILL_ACKS" "$BIONIC_SID" | budget_open_writers "$FILL_ROSTER")"
  case "$FILL_OPEN" in ''|*[!0-9]*) FILL_OPEN=0 ;; esac
  _ST_OPEN="$FILL_OPEN"

  # EVERY READY ROW, UNTRIMMED, in one parse of the table (wave-19 REQ-6, D7): the width passed
  # is wide enough that `fill_ready_set`'s own trim never bites, and the trim to the free
  # slots is taken here, so the ledger records the whole ready set and the refusal names the
  # rows a free slot could have taken.
  #
  # A ROW THIS TURN LAUNCHED IS NEVER MISSED (wave-20 T11b; Step-6 review R4, T12 F7). A launch
  # joins the roster at PreToolUse, so it is already in `open` and has already taken its slot;
  # its plan row stays ready until the launch recorder appends its dispatch. Counting it
  # ready as well charged one launch twice, and the refusal named the rows the turn had just
  # sent. So the ledger's ready set stays the plan's, and what the turn missed is that set less
  # the rows this turn launched, matched by the dispatch name `fill_name` hands out.
  #
  # THE TICK'S SET, READ-ONLY ROWS INCLUDED (wave-26 T13; D9, AC-6.7). A verify or review row
  # takes no writer slot (`fill_readonly_ids`), so the tick offers it whatever the gap, and the
  # wall owes it the same way: the writers are trimmed to the free slots, the read-only rows are
  # counted and named in full. A row that waits for a read is not in this set at all, so it is
  # never demanded.
  ready="$(UNITS_LIVE_HEAD="$_ST_LIVE_HEAD" UNITS_FACTS_STATE="$_ST_FACTS" fill_ready_tagged "$_ST_PLAN" 2>/dev/null)"

  # THE WIDTH, ASKED AS THE TICK ASKS IT (wave-28 T13; D14, AC-2.8): the ready writer rows this
  # turn did not launch, offered one `gate_room` at a time (`fill_gate_width`), the open writers
  # not yet showing counted as owed (`fill_gate_owed`), and a person's cap obeyed. The tick and
  # this wall size their fill by the one function, so on one reading they name the same rows, every
  # one while a slot is free. ONE QUESTION, NOT TWO: `fill_gate_width`'s first ask,
  # `gate_room --owed <owed>`, is the tick's own gate line (`gate_report`, hooks/session-poker.sh),
  # so on one reading a tick that ends `no FILL — the gate gives no room` and this wall agree; a
  # later reading answers for the turn's end, after its acks and launches (tests/stop.test.sh
  # §GAP). A gate that gives no row when a row waits and no cap holds it is the HOLD the
  # ledger records: a machine fact the plan cannot hold. Counted in this shell, never inside
  # `$( )`: bash 3.2 reads a `case` pattern's `)` there as the substitution's end.
  want=0
  while IFS=$'\t' read -r rest slot; do
    [ "$slot" = w ] || continue
    fill_row_launched "$rest" "$_ST_LAUNCHED" && continue
    want=$((want + 1))
  done <<ST_WANT
$ready
ST_WANT
  cap="$_ST_CEILING"
  owed="$(roster_open_names "$FILL_ROSTER" "$FILL_ACKS" "$BIONIC_SID" | fill_gate_owed "$FILL_ROSTER" "$BIONIC_SID")"
  _ST_WIDTH="$(fill_gate_width "$_ST_OPEN" "$owed" "$want" "$cap")"
  case "$_ST_WIDTH" in ''|*[!0-9]*) _ST_WIDTH="$_ST_OPEN" ;; esac
  _ST_FREE=$(( _ST_WIDTH - _ST_OPEN ))
  [ "$_ST_FREE" -ge 0 ] || _ST_FREE=0
  if [ "$want" -gt 0 ] && [ "$_ST_FREE" -eq 0 ] && { [ -z "$cap" ] || [ "$_ST_OPEN" -lt "$cap" ]; }; then
    _ST_STATE=hold
  fi
  count=0; gap=0; rcount=0; rgap=0; _ST_READY=""; _ST_NAMED=""
  while IFS=$'\t' read -r rest slot; do
    [ -n "$rest" ] || continue
    _ST_READY_N=$((_ST_READY_N + 1))
    _ST_READY="${_ST_READY}${_ST_READY:+ }${rest}"
    if fill_row_launched "$rest" "$_ST_LAUNCHED"; then
      _ST_SENT=$((_ST_SENT + 1))
      continue
    fi
    if [ "$slot" = r ]; then
      rcount=$((rcount + 1))
      rgap=$((rgap + 1))
      _ST_NAMED="${_ST_NAMED}${_ST_NAMED:+ }${rest}"
      continue
    fi
    count=$((count + 1))
    gap=$((gap + 1))
    [ "$_ST_FREE" -gt 0 ] && _ST_NAMED="${_ST_NAMED}${_ST_NAMED:+ }${rest}"
  done <<ST_READY
$ready
ST_READY
  _ST_MISSED=$(( (count < _ST_FREE ? count : _ST_FREE) + rcount ))
  _ST_GAP=$(( (_ST_FREE > 0 ? gap : 0) + rgap ))
  return 0
}

# THE TURN END CALLS THE PERSON (epic-23 wave-33-workhorse, T11; REQ-2 AC-2.2, AC-2.5; D2). Every
# open item on the person's ledger (lib/owed.sh) not yet sent is sent at least once, through the one sender
# (lib/notify.sh), carrying the line the run printed for its block; a later turn on the same open
# item sends nothing. It rides the recorder below, and so runs BEFORE `hooks/stop.sh`'s re-entry
# guard, for the reason the recorder does: after a refusal the Stop that actually ends the turn
# carries `stop_hook_active` and runs nothing past the guard. A send inside the fold would miss it.
#
# THE PERSON'S TURN END ONLY: `Stop`, never `SubagentStop` — a writer's stop is not the turn the
# person is waiting on. First the step items a plan has answered are closed: once the bound plan
# carries `approved-by:`, no Step card is still owed (the cards close the earlier steps as they
# render; this closes the last one, and every one a task-scale run never rendered past).
#
# NEVER A VERDICT. It prints nothing, refuses nothing and swallows every failure: owed_send is
# bounded (one five-second attempt per failing turn) and returns 0, so the guard and the fold
# decide exactly what they decided before, channel or no channel.
stop_owed_send() {  # <event> -> always 0
  [ "${1:-}" = Stop ] || return 0
  declare -F owed_send >/dev/null 2>&1 || return 0
  local k
  stop_facts_load
  if [ "${BIONIC_RUN_WORD:-}" = bound-open ] && [ -n "${BIONIC_RUN_PLAN:-}" ] \
     && fill_plan_approved "$BIONIC_RUN_PLAN" >/dev/null 2>&1; then
    for k in approve:step0 approve:step1 approve:step2 approve:step3; do
      owed_close "$k" "plan approved-by" >/dev/null 2>&1
    done
  fi
  owed_send >/dev/null 2>&1
  return 0
}

# THE TURN'S END IS THE RUN'S `stop` EVENT. One event per Stop of an
# engaged run whose ledger is live, appended to the run's log through its one appender (lib/line.sh `line_event`),
# and to no other home, so the reader answers it from the log alone:
#
#   run/v1|ev=stop|session|turn|current|state|ceiling|width|open|free|ready|launched|declined|missed|idle|room|at
#
# `idle` and `room` close the facts: the ready rows nothing launched while a slot was free, and the free slots.
# `declined` IS KEPT, EMPTY: nothing answers a ready row in words now. The instant is the appender's, last, as on every
# event.
#
# A RECORDER, NOT A WALL. It never refuses and is silent on every failure, a log it cannot write and an appender
# that refuses the line among them: the stop it rides on is a turn somebody has to be able to end. It runs BEFORE
# `hooks/stop.sh`'s re-entry guard, so the Stop that ends a refused turn — the one carrying the launches the model
# made after the refusal — is recorded too; the idle fold reads events by `turn=`, so a refused turn's two events
# count once, as the later. That holds because the refusal the CLI feeds back ("Stop hook feedback:") opens no turn
# in `stop_turn_facts`: both carry the prompt's key, and the later one still holds the launches made before it.
#
# ONE APPEND PER STOP, the appender's single write, so a crash leaves at most an event that did not happen and a
# concurrent reader never sees a rewrite. The appender refuses a value holding a bar or a line break, so every free
# value is squashed of both first and no field can forge another or lose the event.
stop_fill_ledger() {  # <event> -> always 0
  stop_owed_send "${1:-}"
  [ "${1:-}" = Stop ] || return 0
  stop_turn_facts || return 0
  [ "$_ST_LIVE" = 1 ] || return 0
  local ready launched idle turn current
  bionic_need line.sh line_event || return 0
  ready="${_ST_READY// /,}"
  launched="$_ST_LAUNCHED"
  # THE ROWS THAT SAT IDLE: ready, not launched this turn, while a writer slot
  # was free. The idle fold charges the interval to the next event. The ids are the plan's own,
  # space-split here exactly as `stop_turn_facts` matched them.
  idle=""
  if [ "${_ST_FREE:-0}" -gt 0 ] 2>/dev/null; then
    local -a idle_ids
    local id
    read -r -a idle_ids <<< "$_ST_READY"
    for id in ${idle_ids[@]+"${idle_ids[@]}"}; do
      fill_row_launched "$id" "$_ST_LAUNCHED" && continue
      idle="${idle}${idle:+,}${id}"
    done
  fi
  # Every value is a number this function computed or is squashed here of a bar and a line break.
  turn="${_ST_TURN//[|$'\r\n']/ }"; current="${_ST_CURRENT//[|$'\r\n']/ }"
  launched="${launched//[|$'\r\n']/_}"; idle="${idle//[|$'\r\n']/_}"; ready="${ready//[|$'\r\n']/_}"
  line_event "$_ST_PLAN" stop "session=${BIONIC_SID//[|$'\r\n']/ }" "turn=${turn}" "current=${current}" "state=${_ST_STATE}" "ceiling=${_ST_CEILING}" "width=${_ST_WIDTH}" "open=${_ST_OPEN}" "free=${_ST_FREE}" "ready=${ready}" "launched=${launched}" "declined=" "missed=${_ST_MISSED}" "idle=${idle}" "room=${_ST_FREE}" >/dev/null 2>&1
  return 0
}

# THE STAND-DOWN SET, COMPUTED FROM WHAT THE TICK WROTE (wave-20 T19; T11's carry-over; the
# AC-5.4 plants on the fourth duty). `session-poker.sh tick` stands a row down by doing two
# things at once: it prints `poker: STANDDOWN <name>` for the human, and it writes
# `stop-orders.sh order <name> --by patrol` so the TaskStop it asks for passes the stop gate.
# The line is words in a transcript anyone can type; the order is a fact on disk only the verb
# writes. So the set is:
#   this session's `by=patrol` stop orders stamped at or after <lower bound>   (what this
#       turn's tick decided — a human's order is an instruction to the stop gate, not a
#       stand-down the tick made)
#   whose row the sweeper's verdict still reads MET and not acked               (a row closed
#       since, or no longer landed — a FOLLOW-UP, a re-dispatch — is owed nothing)
# ONE `verdict` read over the whole roster, and only when an order is in the window: the same
# verb, the same fold and the same `acked=` the tick's own stand-down arm reads, so the two
# cannot disagree about a row (tests/cross-gate-agreement.test.sh CG-standdown).
#
# SILENT ON EVERY UNREADABLE FACT — no bound, no orders file, a symlink where it goes, a
# verdict the sweeper refused: nothing is named. A wall that cannot read what the tick wrote
# does not invent a duty from it.
stop_standdown_set() {  # <lower bound ISO, or empty> -> the names, space-joined
  local lb="${1:-}" orders targets vout roster held t
  [ -n "$lb" ] || return 0
  orders="$BIONIC_ROOT/.bionic/tmp/stop-orders-${BIONIC_SID}.state"
  [ -f "$orders" ] && [ ! -L "$orders" ] && [ -r "$orders" ] || return 0
  targets="$(awk -v lb="${lb:0:19}" -v sid="$BIONIC_SID" '
    function kv(line, key,   i, n, parts) {
      n = split(line, parts, "|")
      for (i = 1; i <= n; i++) if (index(parts[i], key "=") == 1) return substr(parts[i], length(key) + 2)
      return ""
    }
    index($0, "stop-order/v1|") == 1 {
      if (kv($0, "by") != "patrol") next
      s = kv($0, "session"); if (s != "" && s != sid) next
      at = substr(kv($0, "at"), 1, 19); if (at == "" || at < lb) next
      t = kv($0, "target"); if (t !~ /^[A-Za-z0-9_.-]+$/) next
      if (!(t in last) || at > last[t]) last[t] = at
    }
    END { for (t in last) printf "%s %s\n", t, last[t] }' "$orders" 2>/dev/null)"
  [ -n "$targets" ] || return 0
  # A HOLD WRITTEN AFTER A NAME'S LAST ORDER ANSWERS IT. `hold` appends
  # the name's row with `held=<iso> <reason> fp=…`, and the latest row of a name is its row. The
  # tick orders no held name while the hold's fingerprint stands, so an order newer than the hold
  # says something about the agent has changed since, and that order stands.
  roster="$BIONIC_ROOT/.bionic/tmp/roster-${BIONIC_SID}.state"
  held=""
  if [ -f "$roster" ] && [ ! -L "$roster" ] && [ -r "$roster" ]; then
    held="$(awk '
      function kv(line, key,   i, n, parts) {
        n = split(line, parts, "|")
        for (i = 1; i <= n; i++) if (index(parts[i], key "=") == 1) return substr(parts[i], length(key) + 2)
        return ""
      }
      index($0, "roster-state/") == 1 { nm = kv($0, "name"); if (nm != "") h[nm] = kv($0, "held") }
      END { for (nm in h) { at = substr(h[nm], 1, 19); if (at != "") printf "%s %s\n", nm, at } }' "$roster" 2>/dev/null)"
  fi
  targets="$(printf '%s\n' "$targets" | awk -v held="$held" '
    BEGIN { n = split(held, l, "\n"); for (i = 1; i <= n; i++) { split(l[i], p, " "); if (p[1] != "") h[p[1]] = p[2] } }
    NF == 2 && !(($1 in h) && h[$1] >= $2) { printf "%s ", $1 }')"
  [ -n "$targets" ] || return 0
  [ -f "${_STOP_HOOK_DIR_ABS}/session-sweeper.sh" ] || return 0
  # Run from the root with the session key, exactly as the landing sweep above asks it;
  # `|| exit 9` keeps a failed `cd` out of the verb's exit-1 band.
  vout=$( cd "$BIONIC_ROOT" 2>/dev/null || exit 9
          CLAUDE_CODE_SESSION_ID="$BIONIC_SID" bash "${_STOP_HOOK_DIR_ABS}/session-sweeper.sh" verdict 2>/dev/null )
  case "$?" in 0|1) : ;; *) return 0 ;; esac
  printf '%s\n' "$vout" | awk -v want=" $targets" '
    function kv(line, key,   i, n, parts) {
      n = split(line, parts, "|")
      for (i = 1; i <= n; i++) if (index(parts[i], key "=") == 1) return substr(parts[i], length(key) + 2)
      return ""
    }
    index($0, "landing-verdict/v1|") == 1 {
      nm = kv($0, "name")
      if (kv($0, "state") != "MET" || kv($0, "acked") != "no") next
      if (index(want, " " nm " ") == 0 || (nm in seen)) next
      seen[nm] = 1; out = out (out == "" ? "" : " ") nm
    }
    END { if (out != "") print out }'
}


# ─── stop_patrol_revive ───
#
# THE WATCHER THAT DIED WITHOUT A WORD, said once at the turn end. Stop only, engaged only, on a bound open
# run whose scale has a Patrol: a worker's turn end proves nothing about the orchestrator's watch, and a
# bystander session sees nothing from this function. It never blocks: the turn-end hook starts the next
# watcher at this same turn end, so there is nothing for the model to do.
# [WALL: tests/patrol-revive.test.sh]

stop_patrol_revive() {  # <event> -> 0 nothing · 1 advisory · 2 block
  local _ev="${1:-}" _adv=0
  local HOOK_DIR _RUN_PLAN _lost

  case "$_ev" in Stop) : ;; *) return 0 ;; esac

# THIS SCRIPT'S OWN DIRECTORY, so the poker it measures against and the poker it
# NAMES are the same file — resolved the way hooks/dispatch-preflight.sh resolves
# its sibling, never through PATH (a hook's PATH is not ours to trust) and never
# through an env seam (a seam on the path under test leaves the production path
# unverified).
HOOK_DIR="$_STOP_HOOK_DIR_ABS"
[ -n "$HOOK_DIR" ] || HOOK_DIR="$_STOP_HOOK_DIR_RAW"
[ -d "$BIONIC_ROOT" ] || return "$_adv"

# ---------- THE ENGAGEMENT SWITCH — asked before anything else ----------
#
# task-engaged-session: bionic's walls are the RUN's, not the repo's, and a run is entered
# by invoking canonical-sdlc. A session that never did is a bystander here and must not see
# a refusal, an advisory, or a state write from this hook. `engaged_session` (lib/run.sh) is
# true only for a REGULAR file at `.bionic/tmp/engaged-<sid>.state`; every unreadable state —
# absent, symlink, foreign sid, `unknown` — reads as NOT engaged. Silent, return "$_adv": the
# direction §7 gives every start-side ambiguity, and here it is the consent boundary itself
# (1.3.2 close-out ruling — the arming partition IS the consent boundary).
[ "$BIONIC_ENGAGED" = 1 ] || return "$_adv"

# ---------- THE RUN PREDICATE (AC-7, AC-8) ----------
#
# The first of this hook's two scope conditions (see SCOPE in the header). No open run,
# no Patrol to be dead, and nothing for a monitor to say.
#
# PLAN-BOUND AND KEPT (task-engaged-session). This hook has exactly one arm and its whole
# subject is a Patrol serving a run: the duties a revived Patrol would resume — FILL, the
# task-list refresh, the roster read — are the run's, so a session engaged with no plan yet
# has nothing for this monitor to be about. Engagement decides WHETHER; here the plan still
# decides WHAT, and there is only the one thing.
#
# wave-session-bound-run S5: `active_run` (no session input) is now `session_run`
# (lib/run.sh) — a session BOUND to a plan proceeds on THAT plan alone, whatever
# else is open in the root (AC-1); bound to a plan that has since closed takes exactly
# this line's existing branch — return "$_adv" — after announcing the closure (AC-6).
# UNBOUND, the newest plan is announced and never acted on (wave-23-fixit-1810, REQ-1,
# D1): the advisory goes out once on stderr and this hook returns as under `none` — a
# Patrol serving somebody else's run is not this session's to revive.
_RUN_PLAN="$BIONIC_RUN_PLAN"
case "$BIONIC_RUN_WORD" in
  bound-open) : ;;
  fallback)
    stop_unbound_advise "$_RUN_PLAN" && _adv=1
    return "$_adv"
    ;;
  bound-closed)
    fold_advise "patrol-revive: bound plan closed — $_RUN_PLAN; this session has no open run"; _adv=1
    return "$_adv"
    ;;
  bound-unreadable)
    # (wave-20 T1, REQ-2, AC-2.3.) Named, never "no open run"; patrol-duties holds the turn.
    fold_advise "patrol-revive: bound plan unreadable — $_RUN_PLAN"; _adv=1
    return "$_adv"
    ;;
  none|*)
    return "$_adv"
    ;;
esac

# ---------- does the bound run's scale have a Patrol at all ----------
#
# WHETHER THE SCALE HAS A PATROL (lib/scale.sh `scale_patrol`), asked as resume, the tick and the dispatch wall ask
# it: a scale with none, the task row, has no Patrol, so any stamp on this session is not one to judge
# and nothing here is `Patrol dead`. The scale is the bound plan's frontmatter `scale:`, the file this arm already
# holds the path of. A plan whose scale cannot be read, or a library without scale.sh, judges as before: a Patrol
# is assumed, so a wave-scale run loses nothing. Sourced here and not at file scope, behind the guard patrol.sh
# carries below, for the same reason: a bystander turn does not parse a table it will not ask.
bionic_need scale.sh scale_patrol || :
if declare -F scale_patrol >/dev/null 2>&1 && [ "$(scale_patrol "$_RUN_PLAN")" = no ]; then
  return "$_adv"
fi

# ---------- a watcher that died without a word ----------
#
# ONE LINE, ONCE, AND NO BLOCK. hooks/watch.sh starts a new watcher at this same turn end, so there is nothing for the
# model to do: the line tells the person the watch was lost and is starting again. The two hooks run together in no
# fixed order, so the dead watcher is read from the record whichever came first: a record still saying watching over
# the dead process, or the new watcher's claim, which keeps the dead pid as `lost=`. `said=` on the record is what
# keeps a later turn end from saying it again.
bionic_need patrol.sh watch_lost || :
if declare -F watch_lost >/dev/null 2>&1 && _lost="$(watch_lost "$BIONIC_ROOT" "$BIONIC_SID")"; then
  fold_advise "bionic watch: stopped — the watcher (pid ${_lost}) died without a word; this turn's end starts another"
  _adv=1
  watch_lost_said "$BIONIC_ROOT" "$BIONIC_SID" "$_lost" >/dev/null 2>&1 || :
fi

return "$_adv"
}

# ─── THE STOP LINE: the turn end that leaves the run waiting only on the person says so, once ───────────────
#
# The watcher rests when only the person can move the run, and it can say nothing as it does: a watcher's
# exit 0 adds nothing to the window. So the turn-end hook says it, on the person's quiet channel (`fold_say`, a
# `systemMessage`, which the platform paints as one grey line under the reply with no error look and no turn for
# the model). The platform prefixes it `Stop says: `, fourteen columns, so the line keeps to 66 and the window's
# line to 80. It names the return, because the person's reply is what starts the watch again.
#
# WHAT IS READ. The watch record (lib/patrol.sh `watch_record_path`), the one fact about the watch: a rest on the
# person, written since this turn's prompt, with no roster row open. A rest older than the prompt is the person's
# return, which the watch answers by starting again; a rest for any other reason is not the person's to end.
#
# THE RACE. The platform starts this hook and the watcher together at the turn end, and the watcher's first pass
# decides whether it rests. So the hook waits, within a bound counted from its own start, kept well inside the
# Stop hook's timeout: while this turn end's watcher (a claim at or after this hook's start, less a few seconds'
# slack, whose process lives) is still on its pass; and, for a few seconds only, while the record still shows the
# turn before (a rest older than the prompt, or a watcher that died) and the new claim may be about to land. A
# watcher claimed before this turn end goes on watching and is not waited for, and a session with no record at
# all never ran a watcher, so nothing is waited for either.
#
# ONCE. The key is the tick's digest at the rest, the same state twice is one key; it is kept in the session's
# `stop-said-` file, and written only when the line goes out. This function runs last in the fold, so a turn some
# wall refused, which shows no line, marks nothing said.
STOP_WATCH_LINE="bionic watch: stopped - waiting on you; your reply starts it again"
STOP_WATCH_WAIT_DEFAULT=6
STOP_WATCH_CLAIM_GRACE=3
STOP_WATCH_SLACK=5

stop_said_path() {  # <root> <sid> -> the session's record of the last stop line said, or nothing
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  case "$2" in *[!A-Za-z0-9_-]*) return 1 ;; esac
  printf '%s/.bionic/tmp/stop-said-%s.state' "$1" "$2"
}

stop_watch_line() {  # <event> -> 0 nothing · 1 the line staged
  [ "${1:-}" = Stop ] || return 0
  [ "${BIONIC_ENGAGED:-0}" = 1 ] || return 0
  [ "${BIONIC_FOLD_BLOCKS:-0}" -eq 0 ] || return 0
  declare -F watch_record_path >/dev/null 2>&1 || return 0
  local rec prompt bound grace fresh live said key tmp
  rec="$(watch_record_path "$BIONIC_ROOT" "$BIONIC_SID")" || return 0
  _watch_read "$rec" || return 0
  stop_turn_facts >/dev/null 2>&1
  prompt="${_ST_MARK_TS%%.*}"; prompt="${prompt%Z}"
  [ -n "$prompt" ] || return 0
  prompt="${prompt}Z"
  bound="${BIONIC_STOP_WATCH_WAIT:-$STOP_WATCH_WAIT_DEFAULT}"
  case "$bound" in ''|*[!0-9]*) bound="$STOP_WATCH_WAIT_DEFAULT" ;; esac
  grace="$STOP_WATCH_CLAIM_GRACE"; [ "$grace" -le "$bound" ] || grace="$bound"
  fresh="$(date -u -v-"$((SECONDS + STOP_WATCH_SLACK))"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null     || date -u -d "-$((SECONDS + STOP_WATCH_SLACK)) seconds" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  while :; do
    case "$_WR_STATE" in
      resting)
        [[ "$_WR_AT" < "$prompt" ]] || break
        [ "$SECONDS" -lt "$grace" ] || break ;;
      watching)
        live=no
        case "$_WR_PID" in ''|*[!0-9]*) : ;; *) kill -0 "$_WR_PID" 2>/dev/null && live=yes ;; esac
        if [ "$live" = yes ] && [ -n "$fresh" ] && ! [[ "$_WR_AT" < "$fresh" ]]; then
          [ "$SECONDS" -lt "$bound" ] || break
        else
          [ "$live" = no ] && [ "$SECONDS" -lt "$grace" ] || break
        fi ;;
      *) [ "$SECONDS" -lt "$grace" ] || break ;;
    esac
    sleep 0.2
    _watch_read "$rec" || return 0
  done
  [ "$_WR_STATE" = resting ] && [ "$_WR_WHY" = person ] || return 0
  [[ "$_WR_AT" < "$prompt" ]] && return 0
  [ -z "$(roster_open_names "$BIONIC_ROOT/.bionic/tmp/roster-$BIONIC_SID.state" \
    "$BIONIC_ROOT/.bionic/tmp/sweeper-$BIONIC_SID.state" "$BIONIC_SID" 2>/dev/null)" ] || return 0
  key="$(tick_digest_field "$(tick_digest_path "$BIONIC_ROOT" "$BIONIC_SID")" digest)"
  key="digest=${key:-at $_WR_AT}"
  said="$(stop_said_path "$BIONIC_ROOT" "$BIONIC_SID")" || return 0
  [ -f "$said" ] && [ ! -L "$said" ] && [ "$(cat "$said" 2>/dev/null)" = "$key" ] && return 0
  # Written whole beside it and renamed in, never through a link; a line that cannot be marked said is not said,
  # so it can never repeat on every turn end.
  [ -L "$said" ] && return 0
  tmp="$(mktemp "${said%/*}/.stop-said.XXXXXX" 2>/dev/null)" || return 0
  printf '%s\n' "$key" > "$tmp" 2>/dev/null && mv -f "$tmp" "$said" 2>/dev/null || { rm -f "$tmp"; return 0; }
  fold_say "$STOP_WATCH_LINE"
  return 1
}

# ─── THE STOP GUARD: the judgement of a TaskStop, its words and its roster writes ─────────────
#
# hooks/stop.sh's TaskStop arm reads its payload, loads this library, resolves the context and calls
# `stop_guard` with its own directory; the hook decides nothing and says nothing of its own. A
# stop is irreversible, so the guard is closed and loud once the session is engaged: a target it
# cannot establish is refused with the fact named, and the person's order is the one override.
#
#   stop_guard <hook-dir>                 judges the stop in BIONIC_INPUT; 0 admits, a refusal exits 2
#   stop_guard_keys                       every refusal's key, one per line
#   stop_guard_say <key> [facts...]       sets SG_FACT, SG_FIX and SG_DETAIL; 2 with all three empty
#                                         for a key it does not know
#   stop_guard_refuse <key> [facts...]    says the key and refuses on exit2; never returns
#   stop_guard_unrostered_write <roster> <sid> <name> <why>   the closed row of an unrostered stop
#   stop_guard_reason_write <roster> <agent-id> <why>         the agent's latest row again, reason=<why>
#   stop_verdict_line <root> <sid> <sweeper> <name>           the landing verdict's line for one name
#   stop_agent_armed                      whether an agent's stop is one this session's walls judge
#
# A PATH A FIX PRINTS COMES FROM THE HOOK'S DIRECTORY, passed in, so a fix names the command beside
# the hook and never one beside this library. Nothing a say function prints is read from a file.

SG_FACT=""; SG_FIX=""; SG_DETAIL=""

stop_guard_keys() {
  printf '%s\n' deadline no-target no-transcript state-link unrecorded no-row ambiguous alias no-id
}

# The frame every refusal about the target shares: <fact> <fix> <hook-dir> <typed target> <reason line>...
# The fix it prints stays runnable as printed, so an empty target prints the placeholder.
_sg_frame() {
  local fact="$1" fix="$2" hook="$3" target="${4:-<agent-name-or-id>}" reasons="" line
  shift 4
  for line in "$@"; do reasons="${reasons}${line}
"; done
  SG_FACT="$fact"; SG_FIX="$fix"
  SG_DETAIL="${reasons}A stop is irreversible, and a wave is active.

This gate took its own look at the target. To read the whole evidence tier yourself:

Fix: bash ${hook}/stop-check.sh ${target}
     (pass each contracted deliverable path as a further argument)

If a human ordered this stop, it executes — record the order and stop again:
     bash ${hook}/stop-orders.sh order ${target}
A stop the human performs themselves does not reach this gate at all."
}

stop_guard_say() {  # <key> [facts...] -> SG_FACT, SG_FIX, SG_DETAIL
  local key="${1:-}"
  shift
  SG_FACT=""; SG_FIX=""; SG_DETAIL=""
  case "$key" in
    deadline)  # <hook-dir> <seconds>
      SG_FACT="the stop guard did not finish in ${2:-} s"; SG_FIX="stop again"
      SG_DETAIL="The stop guard had not judged this stop ${2:-} s after it began. The harness cancels a hook at its
registration's timeout and admits the call, so the guard refuses first: a stop it cannot judge is not made.

Nothing was stopped.

Fix: stop again. If a human ordered this stop, record the order and it executes without the look:
     bash ${1:-}/stop-orders.sh order <the agent>" ;;
    no-target)  # <hook-dir> <typed target>
      _sg_frame "this stop names no target" "name the agent to stop" "${1:-}" "${2:-}" \
        "The stop names no target: tool_input.task_id is empty." ;;
    no-transcript)  # <hook-dir> <typed target>
      _sg_frame "this stop carries no transcript path" "run /bionic:doctor" "${1:-}" "${2:-}" \
        "This stop request carries no usable transcript path, so its session's agents cannot be resolved." ;;
    state-link)  # <hook-dir> <typed target>
      _sg_frame "the state directory is a symlink" "remove that symlink" "${1:-}" "${2:-}" \
        "This repo's .bionic state directory is a symlink; nothing here will read through it." ;;
    unrecorded)  # <typed target> <roster> <state dir>
      SG_FACT="the stop could not be recorded"; SG_FIX="make the roster writable"
      SG_DETAIL="Target '${1:-}' is recorded as an unrostered stop, but the roster could not take the row for it:
    ${2:-}
The stop is the roster's to carry (the sweeper and the Patrol read the row), so it is not made while
the row cannot be written. Nothing was stopped.

Fix: make ${3:-} and the roster writable by this user, then stop again." ;;
    no-row)  # <hook-dir> <typed target>
      _sg_frame "this target is on no roster row of this session" "name a rostered agent or id" "${1:-}" "${2:-}" \
        "Target '${2:-}' is on no roster row of this session and wears no agent-address or" \
        "background-bash-task-id shape, so this gate cannot tell which Agent-tool dispatch," \
        "if any, it names (REQ-5, D8)." ;;
    ambiguous)  # <hook-dir> <typed target> <live rows> <name> <ids, one per line>
      _sg_frame "that name has more than one live row" "name the full agent id" "${1:-}" "${2:-}" \
        "Target '${2:-}' is ambiguous: ${3:-} rows of this session's roster are live for '${4:-}'." \
        "The agent ids they carry, each of which names exactly one of them:" \
        "$(printf '%s\n' "${5:-}" | sed 's/^/    /')" \
        "A name is an identity here, and two open contracts are carrying this one. The" \
        "@session- alias cannot separate them: it names the session that LAUNCHED an agent," \
        "and this is that session's own roster. Stop the one you mean by its agent id above," \
        "or land the row that is finished — its landing-swept marker frees the name." ;;
    alias)  # <hook-dir> <typed target> <name> <accepted spellings, one per line>
      _sg_frame "that alias is not accepted for this agent" "use the agent's own name" "${1:-}" "${2:-}" \
        "Target '${2:-}' is not an accepted alias for '${3:-}'." \
        "An alias suffix names the session that LAUNCHED the agent, spelled" \
        "@session-<first eight of that session's id>, and it is checked against that" \
        "session's own roster: the roster named here does not carry a row for '${3:-}'." \
        "A suffix naming any other session is a guess wearing an identity's shape." \
        "The spellings this gate accepts for it are:" \
        "${4:-}" ;;
    no-id)  # <hook-dir> <typed target> <name>
      _sg_frame "the session roster carries no id for it" "stop it yourself or order it" "${1:-}" "${2:-}" \
        "Target '${2:-}' is not on this session's register: the roster carries no agent id for '${3:-}'." \
        "An observation is a look at a particular agent's working log, and the log is filed" \
        "under its agent id — which a dispatch records on its roster row when the agent starts" \
        '(status `identified`), and which nothing else in this repo knows. Without it there is' \
        "no evidence channel for this target, so there is nothing that could discharge the stop." \
        "If this agent was launched outside bionic's dispatch, stop it yourself or record an order." ;;
    *) return 2 ;;
  esac
  return 0
}

stop_guard_refuse() {  # <key> [facts...] -> never returns; an unknown key refuses its own call
  stop_guard_say "$@"
  refuse exit2 stop "$SG_FACT" "$SG_FIX" "$SG_DETAIL"
}

# THE ORCHESTRATOR'S RECORDED STOP OF AN AGENT NO ROSTER SAW, spent by its own act: the stop is
# written as a CLOSED row carrying `reason=`, so the name then has a row and a second stop of it
# meets the ordinary refusal. Not `waiver=`, which the sweeper reads as a waived contract; not
# `source=`, which says where a deliverable's path came from. A new roster gets its header, mode 600.
stop_guard_unrostered_write() {  # <roster> <sid> <name> <why> -> 0 written; 1 not
  local roster="$1" row
  row=$(roster_row status=closed "session=$2" "name=$3" agent_id= \
    "launched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" "reason=$4" plan=none) || return 1
  [ -n "$row" ] || return 1
  if [ ! -e "$roster" ]; then
    { roster_header >> "$roster"; } 2>/dev/null && chmod 600 "$roster" 2>/dev/null
  fi
  { printf '%s\n' "$row" >> "$roster"; } 2>/dev/null
}

# THE VERDICT ON A STOP OF A LIVE AGENT WITH ITS CONTRACT UNDELIVERED, written on its roster row: the
# agent's latest row copied whole (one printf of one line, no lock, no rewrite), any `reason=` it
# carried dropped and the new one placed where `roster_row` writes it, just before `tool_use_id=`, so
# every by-key reader of the latest row sees the contract and the verdict together.
stop_guard_reason_write() {  # <roster> <agent-id> <why> -> 0 written; 1 not
  local roster="$1" row
  [ -f "$roster" ] && [ ! -L "$roster" ] && [ -w "$roster" ] || return 1
  row="$(roster_row_for_id "$roster" "$2" 2>/dev/null)" || return 1
  [ -n "$row" ] || return 1
  row="$(printf '%s\n' "$row" | SG_WHY="$3" awk -F'|' '
    { o = $1; put = 0
      for (i = 2; i <= NF; i++) {
        if (index($i, "reason=") == 1) continue
        if (!put && index($i, "tool_use_id=") == 1) { o = o "|reason=" ENVIRON["SG_WHY"]; put = 1 }
        o = o "|" $i
      }
      if (!put) o = o "|reason=" ENVIRON["SG_WHY"]
      print o }')"
  [ -n "$row" ] || return 1
  { printf '%s\n' "$row" >> "$roster"; } 2>/dev/null
}

# THE LANDING'S VERDICT FOR ONE NAME, asked of the sweeper beside the hook, in the project's root and
# under the session the roster is keyed by: the first verdict line of the call scoped to the name, or
# nothing. The guard and the order verb ask it; the sweeper's verb owns the predicate and its ledger.
stop_verdict_line() {  # <root> <sid> <sweeper> <name> -> the line, or nothing
  local out
  out=$( cd "$1" 2>/dev/null || exit 9
         CLAUDE_CODE_SESSION_ID="$2" bash "$3" verdict "$4" 2>/dev/null )
  printf '%s\n' "$out" | grep -F 'landing-verdict/v1|' | head -1
}

# AN AGENT'S STOP IS JUDGED ONLY IN A SESSION THAT ENGAGED BIONIC AND DISPATCHED: the roster is
# written at the session's first dispatch, so an unarmed session pays one stat. A link anywhere on
# the path to the roster is not followed: a repo pointing this at another tree's roster would be a
# repo choosing which session it belongs to. Read after `bionic_context`.
stop_agent_armed() {  # -> 0 armed; 1 not
  [ -d "${BIONIC_ROOT:-}" ] || return 1
  [ "${BIONIC_ENGAGED:-}" = 1 ] || return 1
  [ ! -L "$BIONIC_ROOT/.bionic" ] && [ ! -L "$BIONIC_ROOT/.bionic/tmp" ] || return 1
  local roster="$BIONIC_ROOT/.bionic/tmp/roster-${BIONIC_SID}.state"
  [ ! -L "$roster" ] && [ -f "$roster" ]
}

# ─── stop_guard: the judgement, in the order the stop's facts can be had ────────────────────
#
# FAIL DIRECTIONS. Open and silent before the engagement verdict: an unconfigured machine is not a
# stop decision. Closed and loud after it: the ambiguous case is exactly what the wall exists for.
#
# ITS OWN DEADLINE. The harness cancels a hook at its registration's timeout and admits the call, so
# a timer signals this shell at SG_DEADLINE_S, under the registration, and the handler refuses: a stop
# the guard cannot judge is not made. A human order read before the alarm is honoured with its own
# sentence. A trap runs between commands, so one foreground command that outlasts it is not cut.
#
# THE LOOK IS THE GUARD'S OWN. It reads the target's working log, its progress artifact and its
# deliverables at the instant of the stop through `observe_agent` (lib/observe.sh), the function
# hooks/stop-check.sh prints. A live target with its contract undelivered is allowed, and the verdict
# is written on its roster row as `reason=`; idle, delivered and landed targets pass with the look.
#
# THE ROSTER DECIDES WHO THE TARGET IS: this session's roster is the identity register the dispatch
# wall, the recorder and `adopt` write. A name is not an identity, so an ambiguous name is refused and
# its agent ids are printed as the way out; a target this session has no standing over is refused,
# except a background shell's id, which names no Agent-tool dispatch at all.
SG_DEADLINE_S=7
SG_DEADLINE_LIVE=0
SG_DEADLINE_PID=""
SG_ORDER_HONOURED=""
SG_HOOK_DIR=""
SG_ORDER_TTL_S=1800
SG_ORDER_SCHEMA="stop-order/v1"
SG_UNROSTERED_SCHEMA="stop-unrostered/v1"

sg_deadline_hit() {
  [ "$SG_DEADLINE_LIVE" = 1 ] || return 0
  SG_DEADLINE_LIVE=0
  if [ -n "$SG_ORDER_HONOURED" ]; then
    echo "STOP ORDERED (by ${ORDER_BY:-human}) — executing. The contract verdict was not read in time." >&2
    exit 0
  fi
  stop_guard_refuse deadline "$SG_HOOK_DIR" "$SG_DEADLINE_S"
}
# One field of the payload, as the guard has always read it: `// empty`, errors silent.
_sg_jq() { printf '%s' "${BIONIC_INPUT:-}" | jq -r "$1 // empty" 2>/dev/null; }
sg_deadline_stop() {
  [ -z "$SG_DEADLINE_PID" ] || kill "$SG_DEADLINE_PID" 2>/dev/null
  return 0
}

# The session's own subagent directory, `<transcript-dir>/<session-id>/subagents`: a session can only
# stop its own tasks, and the recorder scopes its writes the same way.
_sg_subagents_dir() {  # <transcript-path>
  local tr="$1"
  [ -n "$tr" ] || return 1
  case "$tr" in *.jsonl) : ;; *) return 1 ;; esac
  printf '%s/subagents\n' "${tr%.jsonl}"
}

# A spawned tree's .bionic links to the main checkout's so a wave shares one plan tree; that one link
# is trusted when its target resolves under the parent of the git common dir, which a hostile repo
# cannot point at another repository's tree.
_sg_symlink_in_repo() {  # <repo> -> 0 iff $repo/.bionic resolves under this repo's own root
  local repo="$1" target common root
  target="$(cd "$repo/.bionic" 2>/dev/null && pwd -P)" || return 1
  common="$(git_common_dir "$repo")" || return 1
  root="$(cd "${common%/.git}" 2>/dev/null && pwd -P)" || return 1
  case "$target/" in "$root"/*) return 0 ;; *) return 1 ;; esac
}

# A repo controls its own .bionic contents, and a link at either level would let it choose which roster,
# orders and contracts this guard reads: refused, the stop with it, except the in-repo tree link above.
_sg_state_dir() {  # <repo> -> the state directory; nonzero if unsafe
  local repo="$1"
  if [ -L "$repo/.bionic" ]; then
    _sg_symlink_in_repo "$repo" || return 1
  fi
  [ -L "$repo/.bionic/tmp" ] && return 1
  printf '%s\n' "$repo/.bionic/tmp"
}

# ONE AWK PASS OVER THIS SESSION'S ROSTER, BY BOTH KEYS. The dispatch writes the contract and the
# recorder writes the id one state later, so the last row of a name is the current statement about it
# while the id may sit on an earlier one: by id, by name, and by name with an id are collected apart.
# Only a `confirmed` or `identified` row lends an id; an `intended` row's id is a claim about a launch
# nothing has observed. A roster that is a link or cannot be opened is not read: its unreadability is
# carried in ROSTER_UNREADABLE instead, and lands on the closed side.
_sg_roster_walk() {  # <key-name>
  local key="$1" rows
  ROW_BY_ID=""; ROW_BY_NAME=""; ROW_WITH_ID=""
  [ -f "$ROSTER_FILE" ] || return 0
  [ -L "$ROSTER_FILE" ] && return 0
  [ -r "$ROSTER_FILE" ] || return 0
  rows="$(SG_WK="$key" SG_WV="roster-state/${ROSTER_VERSION}|" awk "$_ROSTER_OPEN_AWK"'
    index($0, ENVIRON["SG_WV"]) != 1 { next }
    {
      k = ENVIRON["SG_WK"]
      id = _roster_kv($0, "agent_id"); nm = _roster_kv($0, "name"); st = _roster_kv($0, "status")
      if (st == "confirmed" || st == "identified") {
        if (id != "" && id == k) by_id = $0
        if (id != "" && nm != "" && nm == k) with_id = $0
      }
      if (nm != "" && nm == k) by_name = $0
    }
    END { print by_id; print by_name; print with_id }' "$ROSTER_FILE" 2>/dev/null)"
  { IFS= read -r ROW_BY_ID; IFS= read -r ROW_BY_NAME; IFS= read -r ROW_WITH_ID; } <<< "$rows"
  return 0
}

# The contract's verdict, read once: a name that cleans to nothing would scope the sweeper to every
# row, so it is not asked.
_sg_take_verdict() {
  [ "$V_TAKEN" -eq 1 ] && return 0
  V_TAKEN=1
  [ -f "$SWEEPER" ] || return 0
  [ -n "$AGENT_NAME" ] || return 0
  case "$(printf '%s' "$AGENT_NAME" | tr -d '[:space:][:cntrl:]|')" in "") return 0 ;; esac
  local line
  line=$(stop_verdict_line "$BIONIC_ROOT" "$BIONIC_SID" "$SWEEPER" "$AGENT_NAME")
  [ -n "$line" ] || return 0
  V_STATE=$(line_field "$line" state)
  V_DETAIL=$(line_field "$line" detail)
  V_ACKED=$(line_field "$line" acked)
  return 0
}

# THE ONE READER OF THE ORDERS FILE: the first line of <schema> whose target is one of the names given
# and whose epoch is current, in ORDER_LINE; 1 when none. An instruction is current when it is given and
# stops being current, so an order has a window; a future-dated record is a skewed clock or a hand edit,
# and a minute of tolerance absorbs only the first.
_sg_orders_current() {  # <schema> <name>... -> 0 and ORDER_LINE set · 1
  local schema="$1" f="$ORDERS_FILE" line t e now delta n ok
  shift
  ORDER_LINE=""
  [ -L "$f" ] && return 1
  [ -f "$f" ] || return 1
  now=$(date -u +%s)
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "${schema}|"*) : ;; *) continue ;; esac
    t=$(line_field "$line" target)
    [ -n "$t" ] || continue
    ok=0
    for n in "$@"; do [ -n "$n" ] && [ "$t" = "$n" ] && { ok=1; break; }; done
    [ "$ok" -eq 1 ] || continue
    e=$(line_field "$line" epoch)
    case "$e" in ''|*[!0-9]*) continue ;; esac
    delta=$((now - e))
    if [ "$delta" -le "$SG_ORDER_TTL_S" ] && [ "$delta" -ge -60 ]; then
      ORDER_LINE="$line"
      return 0
    fi
  done < "$f"
  return 1
}
# The person's order, matched on what was typed, the agent's name or its id; `by=` says on whose word.
_sg_order_current() {
  ORDER_BY=""
  _sg_orders_current "$SG_ORDER_SCHEMA" "$RAW" "$AGENT_NAME" "$AGENT_ID" || return 1
  ORDER_BY=$(line_field "$ORDER_LINE" by)
  case "$ORDER_BY" in human|patrol) : ;; *) ORDER_BY=human ;; esac
  return 0
}
# The orchestrator's unrostered record: honoured once, only for a name no roster of the project holds.
_sg_unrostered_current() {
  _sg_orders_current "$SG_UNROSTERED_SCHEMA" "$RAW" "$BASE" || return 1
  UNROSTERED_WHY=$(line_field "$ORDER_LINE" why)
  return 0
}
_sg_unrostered_anywhere() {  # -> 0 when no roster of the project has a row of the name
  [ -z "$(roster_sessions_with_name "$STATE_DIR" "$BASE")" ]
}

# An agent address: `name@session-xxxx`, or the transcript form `a<hex>` / `a<name>-<16hex>`.
_sg_address_shaped() {  # <typed> -> 0 if it wears an agent-address shape
  local t="$1"
  case "$t" in *@session-*) return 0 ;; esac
  grep -qE '^a[0-9a-f]+$' <<< "$t" && return 0
  grep -qE '^a.+-[0-9a-f]{16}$' <<< "$t" && return 0
  return 1
}

# A background shell's id: one the payload's own transcript records as `"backgroundTaskId"`, else the
# one spelling the harness has used, `[bt]` and eight lowercase alphanumerics. The leading letter keeps
# the carve from widening to a bare name that happens to be short.
_sg_bash_task_shaped() {  # <typed> -> 0 if it is a recorded background-shell id or wears the shape
  if [ -n "${TRANSCRIPT:-}" ] && [ -f "$TRANSCRIPT" ] && [ ! -L "$TRANSCRIPT" ] \
     && grep -qF -- "\"backgroundTaskId\":\"$1\"" "$TRANSCRIPT" 2>/dev/null; then
    return 0
  fi
  grep -qE '^[bt][a-z0-9]{8}$' <<< "$1"
}

# Every roster in this root that carries the name, as the addresses the platform's stop primitive takes,
# built from the roster's filename because that is the session that wrote the row.
_sg_accepted_addresses() {  # -> "    <name>@session-xxxxxxxx" per launcher, newline separated
  local sid out=""
  while IFS='|' read -r sid _; do
    [ -n "$sid" ] || continue
    out="${out}    ${BASE}@session-$(printf '%s' "$sid" | cut -c1-8)
"
  done <<< "$(roster_sessions_with_name "$STATE_DIR" "$BASE")"
  printf '%s' "$out"
}

# Standing is either fact, and neither needs a transcript: an agent-address shape, or a row of this
# session's roster. An unreadable roster grants standing and leaves the id unestablished, which lands
# on the closed side with the fact named.
_sg_has_standing() {
  _sg_address_shaped "$RAW" && return 0
  [ -n "$ROW_BY_NAME" ] && return 0
  [ -n "$ROSTER_UNREADABLE" ] && return 0
  return 1
}

stop_guard() {  # <hook-dir> -> 0 admits; a refusal exits 2
  SG_HOOK_DIR="$1"
  [ -d "$BIONIC_ROOT" ] || return 0
  [ "$BIONIC_ENGAGED" = 1 ] || return 0

  trap sg_deadline_hit ALRM
  trap sg_deadline_stop EXIT
  SG_DEADLINE_LIVE=1
  ( trap 'kill "$_sg_sp" 2>/dev/null; exit 0' TERM
    sleep "$SG_DEADLINE_S" & _sg_sp=$!
    wait "$_sg_sp" && kill -ALRM $$ 2>/dev/null
  ) >/dev/null 2>&1 </dev/null &
  SG_DEADLINE_PID=$!
  disown "$SG_DEADLINE_PID" 2>/dev/null || :

  RAW=$(_sg_jq '.tool_input.task_id')
  [ -n "$RAW" ] || stop_guard_refuse no-target "$SG_HOOK_DIR" "$RAW"

  TRANSCRIPT=$(_sg_jq '.transcript_path')
  SUB=$(_sg_subagents_dir "$TRANSCRIPT") || stop_guard_refuse no-transcript "$SG_HOOK_DIR" "$RAW"

  # The state directory first: resolution reads the roster, for the id and for an alias's launcher.
  STATE_DIR=$(_sg_state_dir "$BIONIC_ROOT") || stop_guard_refuse state-link "$SG_HOOK_DIR" "$RAW"

  # The typed reference: a bare name, that name with an `@session-<launcher>` suffix, or the id.
  BASE="${RAW%@*}"; [ -n "$BASE" ] || BASE="$RAW"
  ALIAS_SUFFIX=""
  case "$RAW" in *@*) ALIAS_SUFFIX="${RAW##*@}" ;; esac

  ROSTER_FILE="$STATE_DIR/roster-${BIONIC_SID}.state"
  ROW_BY_ID=""; ROW_BY_NAME=""; ROW_WITH_ID=""
  ROSTER_UNREADABLE=""
  [ -L "$ROSTER_FILE" ] && ROSTER_UNREADABLE=1
  [ -e "$ROSTER_FILE" ] && [ ! -r "$ROSTER_FILE" ] && ROSTER_UNREADABLE=1
  _sg_roster_walk "$BASE"

  # An id becomes the name its row carries, and the second walk is by that name. The row the id names
  # is kept: it is that row, and not the last row of its name, that the look and the contract read.
  TYPED_AS_ID=""
  TYPED_ROW=""
  if [ -n "$ROW_BY_ID" ]; then
    TYPED_AS_ID=1
    TYPED_ROW="$ROW_BY_ID"
    BASE=$(line_field "$ROW_BY_ID" name)
    _sg_roster_walk "$BASE"
  fi

  AGENT_NAME="$BASE"
  ROSTER_ROW="$ROW_BY_NAME"
  AGENT_ID=""
  [ -n "$ROW_WITH_ID" ] && AGENT_ID=$(line_field "$ROW_WITH_ID" agent_id)
  if [ -n "$TYPED_ROW" ]; then
    ROSTER_ROW="$TYPED_ROW"
    AGENT_ID=$(line_field "$TYPED_ROW" agent_id)
  fi

  # THE ORDER IS READ BEFORE STANDING, so a person's order for a name with no row is honoured: the
  # refusal's own detail promises that an order executes. What an unmet contract earns is one line.
  SWEEPER="${SG_HOOK_DIR}/session-sweeper.sh"
  ORDERS_FILE="$STATE_DIR/stop-orders-${BIONIC_SID}.state"
  V_TAKEN=0; V_STATE=""; V_DETAIL=""; V_ACKED=""
  ORDER_BY=""; ORDER_LINE=""; UNROSTERED_WHY=""
  if _sg_order_current; then
    SG_ORDER_HONOURED=1
    _sg_take_verdict
    if [ -z "$V_STATE" ]; then
      echo "STOP ORDERED (by ${ORDER_BY}) — executing. No contract row of this name is on the session roster." >&2
    elif [ "$V_STATE" = "MET" ] || [ "$V_STATE" = "WAIVED" ]; then
      echo "STOP ORDERED (by ${ORDER_BY}) — executing. Its contract stands ${V_STATE}: nothing is given up." >&2
    else
      echo "STOP ORDERED (by ${ORDER_BY}) — executing. Contract ${V_STATE}, giving up: ${V_DETAIL}" >&2
    fi
    return 0
  fi

  # THE ORCHESTRATOR'S UNROSTERED RECORD, only over a roster it can read and write. The deadline is
  # spent before the write, so a late alarm cannot refuse a stop whose row is on disk.
  if [ -z "$ROW_BY_NAME" ] && [ -z "$ROSTER_UNREADABLE" ] && [ -z "$TYPED_AS_ID" ] && _sg_unrostered_current && _sg_unrostered_anywhere; then
    SG_DEADLINE_LIVE=0
    stop_guard_unrostered_write "$ROSTER_FILE" "$BIONIC_SID" "$BASE" "$UNROSTERED_WHY" \
      || stop_guard_refuse unrecorded "$RAW" "$ROSTER_FILE" "$STATE_DIR"
    echo "STOP RECORDED (unrostered, by the orchestrator) — executing. Reason: ${UNROSTERED_WHY}" >&2
    return 0
  fi

  if ! _sg_has_standing; then
    if _sg_bash_task_shaped "$RAW"; then
      echo "PASSTHROUGH: '${RAW}' wears a background-bash-task-id shape and carries no agent metadata — not an Agent-tool dispatch this gate has standing to guard. The stop proceeds." >&2
      return 0
    fi
    stop_guard_refuse no-row "$SG_HOOK_DIR" "$RAW"
  fi

  # AMBIGUITY, COUNTED ON THE REGISTER: two rows of one name under open contracts with different ids
  # (`live_ids_of_name`, lib/roster.sh). Not for an id, which names one row and is the way out.
  AMBIG_IDS=""
  [ -z "$TYPED_AS_ID" ] && AMBIG_IDS=$(live_ids_of_name "$BASE")
  AMBIG_N=0
  [ -n "$AMBIG_IDS" ] && AMBIG_N=$(printf '%s\n' "$AMBIG_IDS" | grep -c .)
  if [ "$AMBIG_N" -gt 1 ]; then
    stop_guard_refuse ambiguous "$SG_HOOK_DIR" "$RAW" "$AMBIG_N" "$BASE" "$AMBIG_IDS"
  fi

  # `name@session-<launcher>` IS AN ALIAS AND ONLY THAT: accepted when it is the row's recorded
  # teammate address, or when the launcher's own roster (matched by the printed eight-character prefix)
  # carries a row of the name.
  if [ -n "$ALIAS_SUFFIX" ]; then
    local teammate alias_ok=0 want af accepted
    teammate=$(line_field "$ROSTER_ROW" teammate_id)
    if [ -n "$teammate" ] && [ "$RAW" = "$teammate" ]; then
      alias_ok=1
    else
      case "$ALIAS_SUFFIX" in
        session-*)
          want="${ALIAS_SUFFIX#session-}"
          case "$want" in
            ''|*[!A-Za-z0-9-]*) : ;;
            *)
              for af in "$STATE_DIR"/roster-"$want"*.state; do
                [ -f "$af" ] || continue
                [ -L "$af" ] && continue
                grep -qF "|name=${BASE}|" "$af" || continue
                alias_ok=1
                break
              done
              ;;
          esac
          ;;
      esac
    fi
    if [ "$alias_ok" -eq 0 ]; then
      accepted=$(_sg_accepted_addresses)
      [ -n "$accepted" ] || accepted="    (no roster in this repo carries the name '${BASE}')
"
      stop_guard_refuse alias "$SG_HOOK_DIR" "$RAW" "$BASE" "${accepted%
}"
    fi
  fi

  # WHAT DISCHARGES: an ack (the orchestrator verified completion), a waiver, or a MET over a row that
  # declared a deliverable. A MET over a row that declared nothing is an absence of a contract, not a
  # landing, and does not discharge.
  _sg_take_verdict
  [ "$V_ACKED" = "yes" ] && return 0
  case "$V_STATE" in
    WAIVED) return 0 ;;
    MET)    [ -n "$(line_field "$ROSTER_ROW" deliverable)" ] && return 0 ;;
  esac

  # The look needs the agent id, and only a confirmed or identified row carries it.
  [ -n "$AGENT_ID" ] || stop_guard_refuse no-id "$SG_HOOK_DIR" "$RAW" "$AGENT_NAME"

  # THE LOOK, in process and by the agent id, so it lands on the row this guard resolved.
  OBSERVE_ROOT="$BIONIC_ROOT"
  OBSERVE_SESSION="$BIONIC_SID"
  OBSERVE_TRANSCRIPT="$TRANSCRIPT"
  OBSERVE_DOCS_ROOT="$(docs_root "$BIONIC_ROOT")"
  OBSERVE_ROSTER="$ROSTER_FILE"
  OBSERVE_PROGRESS_ARG=""
  OBSERVE_CLAIMS_ARG=""
  observe_agent "$AGENT_ID"
  LOOK="$(observe_look_line)"

  if [ "$OBS_CLASS" = "alive" ]; then
    # Allowed, and the verdict is the guard's own, never a word the caller supplied. A roster that
    # cannot take the row does not bring the refusal back: stderr says the verdict was not written.
    SG_DEADLINE_LIVE=0
    local why said
    why="unmet: deliverable ${OBS_DELIV_STATE}${OBS_DELIV_PATHS:+ — ${OBS_DELIV_PATHS}}; progress ${OBS_PROGRESS_STATE}"
    why="${why//|/ }"; why="${why//$'\n'/ }"; why="${why//$'\r'/ }"; why="${why//$'\t'/ }"
    if [ -z "$ROSTER_UNREADABLE" ] && stop_guard_reason_write "$ROSTER_FILE" "$AGENT_ID" "$why"; then
      said="its roster row records the verdict as reason=: ${why}"
    else
      said="the verdict could not be written to ${ROSTER_FILE}: ${why}"
    fi
    {
      echo "STOP ALLOWED — '${RAW}' (${AGENT_ID}) is ALIVE and its contract is undelivered; ${said}."
      echo "    working log:  ${OBS_LOG}"
      echo "    last write:   $(fmt_age "$OBS_LOG_AGE") ago, inside the declared cadence of ${OBS_CADENCE_S}s (${OBS_CADENCE_SOURCE})"
      echo "    progress:     ${OBS_PROGRESS_STATE}${OBS_PROGRESS:+ — ${OBS_PROGRESS}}"
      echo "    deliverable:  ${OBS_DELIV_STATE}${OBS_DELIV_PATHS:+ — ${OBS_DELIV_PATHS}}"
    } >&2
    return 0
  fi

  echo "STOP PERMITTED — ${AGENT_NAME} is ${OBS_CLASS}: ${LOOK}" >&2
  return 0
}
