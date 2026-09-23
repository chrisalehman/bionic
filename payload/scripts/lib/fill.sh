#!/bin/bash
# payload/scripts/lib/fill.sh — READINESS IS A PROPERTY OF THE UNIT, NOT OF THE SCALE
# (epic-23 wave-18-fixit-185, REQ-3; spec Design §1 "Ready set"/"Fillable gap", §2 D2;
# ADR-033 decision 2).
#
# WHAT IT OWNS. The one computation of "which rows may be dispatched now", and the one
# predicate for "is this run's ledger live". Three verbs, all pure functions of the plan
# file (and, for the third, of the session's roster):
#
#   fill_ledger_live <plan>            0 when the plan's `current:` is numeric and >= 4
#                                      (wave scale) or matches `^T[0-9]+$` (task scale);
#                                      1 otherwise. The cheap gate a caller asks BEFORE
#                                      paying for a table read.
#   fill_step_token <plan>             the step the ready set is asked at: the numeric
#                                      `current:` with its sub-step letter stripped, or
#                                      `T<n>` when the table is task-shaped. Empty when the
#                                      two disagree or the field will not parse.
#   fill_ready_set <plan> <rung> <open>
#                                      the ready ids, one per line, in TABLE order, trimmed
#                                      to <rung> - <open>. Empty and silent whenever the
#                                      ledger is not live, the gap is closed, or the table
#                                      carries no ready row.
#   fill_name <roster> <task id>       the agent NAME to dispatch that id under, which is the
#                                      id itself until this session has already spent it.
#
# WHY A LIBRARY AT ALL (D2). Both of these lived inside `hooks/session-poker.sh` — the ready
# set inline in the `tick` verb, reading five shell variables the tick had built, and
# `fill_name` beside it. The tick could therefore ORDER work and nothing else could ask what
# it had ordered: `payload/scripts/lib/stop.sh`'s fill duty keyed on the tick having PRINTED
# a line, so a turn that ended with rows ready and no tick in it ended in silence. An
# invariant ("no turn past Step 3 ends with a fillable gap") needs the computation, not the
# tick's echo of it, and two implementations of readiness would be two answers the moment
# either moved. The tick calls this and prints what it says; the wall calls this and refuses
# by it; `payload/scripts/card.sh` calls it for the plan's per-batch widths.
#
# THE SIGNATURE IS THE CONTRACT. `fill_ready_set <plan> <rung> <open>` takes the width and
# the occupancy from its CALLER rather than reading them itself, because the two callers
# measure them differently and both are right: the tick counts open rows off the roster it
# is already walking, trimmed by transcript liveness, while the stop wall counts the same
# roster's rows minus acks (wave-19 REQ-5; the wall's count is never below the tick's); both take the
# width from the same reading — `pressure_level` against the budget's declared ceiling, the
# ceiling itself only when the rung will not parse (wave-18 review R1: a wall that measured
# against the ceiling refused turns naming rows the tick had withheld). What may not differ
# is the READY SET, and that is what lives here.
#
# TWO TABLE SHAPES, ONE READER. `payload/scripts/lib/units.sh` is the one parser of
# `## Tasks` at either scale, and `units_ready` grew the task-scale arm in the same wave
# (`T<n>` step, no step cell on the row, a dependency satisfied by `done`). Nothing here
# parses a table.
#
# SOURCED, NEVER EXECUTED, AND SILENT AT SOURCE TIME. Every caller reads a verb through
# `$( )`, and a library that greeted them would corrupt the first line of every answer.
#
# BASH 3.2 (macOS /bin/bash). No associative arrays, no `${var^^}`, no `mapfile`.
#
# [WALL: tests/session-poker.test.sh]
# [WALL: tests/patrol-duties-gate.test.sh]

_fill_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}
_FILL_LIB_DIR="$(cd "$(_fill_self_dir)" && pwd -P)"

# THE TABLE READER, SOURCED THE WAY payload/scripts/lib/stop.sh SOURCES IT and guarded on
# the verb this file actually calls: a caller that already has it (the poker, whose
# `BIONIC_LIB_WANT` names units.sh) pays nothing, and a caller that does not (hooks/stop.sh,
# which wants this file alone) gets it here. units.sh defines functions and runs nothing at
# source time, so the guard costs one parse and no forks.
if ! declare -F units_ready >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$_FILL_LIB_DIR/units.sh"
fi

# ── THE LEDGER'S OWN FIELD ────────────────────────────────────────────────────
#
# _fill_current_field <plan> -> the RAW `current:` value (whitespace stripped), or "" when
# there is no plan, no `## SDLC State` section, or no `current:` line inside it.
#
# THE ONE READER OF THE FIELD (wave-19 REQ-6, D7; AC-6.1). `hooks/session-poker.sh`'s
# `_sched_plan_current_field` is a one-line wrapper over this function (the tick sources this
# file), and §CG of tests/cross-gate-agreement.test.sh, which extracts the poker's wrapper as
# text, sources this file beside it — so the grammar §CG binds to `run.sh`'s `run_open` is
# this parser's. §32 of tests/session-poker.test.sh drives the wrapper and this function over
# one table of shapes and pins that the wrapper parses nothing itself.
#
# FENCE-AWARE, and the line endings are translated rather than deleted, for the reason every
# other plan read in this tree gives: a plan documenting its own `## SDLC State` inside a
# fence is prose, and a CR-only file that collapsed to one record would read as "no section"
# — the fail-dangerous direction. TWO PROCESSES, NOT SIX: the translation is its own `awk`
# (the same program `normalize_newlines` runs, because splitting a record on CR inside the
# reader would be a second spelling of it), and the section walk, the first `current:` line,
# the prefix strip and the whitespace strip are one pass after it. The pass reads to the end
# of its input rather than exiting at the match, so the translating `awk` upstream is never
# cut off mid-write.
#
# READ ONCE PER PROCESS (AC-6.2). One Stop asks this field three times — `fill_ledger_live`
# at the gate, then `fill_step_token` and `fill_ledger_live` again inside `fill_ready_set` —
# and a tick asks it as often. `_fill_current_load` keeps the last answer in two scalars keyed
# by the plan path; every reader goes through it. Because a value set inside `$( )` dies with
# that subshell, the memo is only as wide as the shell that first asks: the stop wall's gate
# and the tick both ask in their own shell before any `$( )` reader runs, and every subshell
# after that inherits the answer. The key is the path alone. The stop wall and the tick never
# write a plan, so for them the path is the whole identity. ONE READER WRITES: `card.sh step3`
# rewrites one projection path per batch, each with a different `current:`, and asks the ready
# set in its own shell — so its writer, `_card_project`, calls `fill_current_forget` after
# every write (wave-19 critic C2: a Step-5 batch answered at the Step-4 projection's step read
# `0 of <rung>`). A key on mtime and size would not have caught it — the step-4 and step-5
# projections are the same size and land in the same second — and a content hash is a fork on
# every read, the cost this memo exists to remove. So the contract is the writer's: a process
# that rewrites a plan it has read through this file forgets it after the write. A path that
# is not a file is answered "" and never memoised, so a plan created later in the same process
# is still read. Sourcing this file resets the memo.
_FILL_CURRENT_PLAN=""
_FILL_CURRENT_VALUE=""
fill_current_forget() {  # -> drops the memo; the next reader parses whatever path it names
  _FILL_CURRENT_PLAN=""
  _FILL_CURRENT_VALUE=""
}
_fill_current_load() {  # <plan path> -> sets _FILL_CURRENT_VALUE for it; parses at most once
  local plan="${1:-}"
  if [ -n "$plan" ] && [ "$plan" = "$_FILL_CURRENT_PLAN" ]; then
    return 0
  fi
  if [ -z "$plan" ] || [ ! -f "$plan" ]; then
    _FILL_CURRENT_VALUE=""
    _FILL_CURRENT_PLAN=""
    return 0
  fi
  _FILL_CURRENT_VALUE="$(awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$plan" 2>/dev/null | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence || got { next }
    /^## SDLC State/ { flag = 1; next }
    /^## / { flag = 0 }
    flag && /^[[:space:]]*current[[:space:]]*:/ {
      v = $0
      sub(/^[[:space:]]*current[[:space:]]*:[[:space:]]*/, "", v)
      gsub(/[[:space:]]/, "", v)
      printf "%s", v
      got = 1
    }')"
  _FILL_CURRENT_PLAN="$plan"
}
_fill_current_field() {  # <plan path> -> the raw current: value, or ""
  _fill_current_load "${1:-}"
  printf '%s' "$_FILL_CURRENT_VALUE"
}

# ── IS THE LEDGER LIVE? ───────────────────────────────────────────────────────
#
# fill_ledger_live <plan> -> 0 when this run has a schedule to fill from, 1 when it does not.
#
# LIVE MEANS "PAST THE APPROVAL GATE". At wave scale that is `current:` numeric and >= 4:
# Steps 0-3 are research, spec, plan and REVIEW, and dispatching into a task table nobody has
# ratified sends a writer against a plan that may not survive its own review (the 2026-09-05
# incident the tick's approval gate closed). At task scale there is no numbered step to
# compare — the field names the UNIT the run is on, `T<n>` — and a run on a unit is a run
# past its plan.
#
# THE SUB-STEP LETTER IS THIS REPO'S OWN GRAMMAR (`current: 4b`), stripped before the digits
# are tested, exactly as `run_open` and the tick's reader strip it.
#
# IT ASKS THE FIELD AND NOTHING ELSE. Whether the table AGREES with the field is
# `fill_step_token`'s question, and whether there is ROOM is the caller's: this is the cheap
# gate a caller asks before paying for a table read.
fill_ledger_live() {  # <plan> -> 0 live · 1 not
  local raw step
  _fill_current_load "${1:-}"
  raw="$_FILL_CURRENT_VALUE"
  [ -n "$raw" ] || return 1
  step="${raw%[ab]}"
  case "$step" in
    ''|*[!0-9]*) : ;;
    *) [ "$step" -ge 4 ] 2>/dev/null && return 0
       return 1 ;;
  esac
  case "$raw" in
    T*) case "${raw#T}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac ;;
  esac
  return 1
}

# ── WHICH STEP IS THE READY SET ASKED AT? ─────────────────────────────────────
#
# fill_step_token <plan> -> the token `units_ready` takes as its second argument, or "" when
# the plan's `current:` cannot be read against the table it carries.
#
# THE FIELD AND THE TABLE HAVE TO AGREE. A numeric `current:` is answerable whatever the
# table looks like — the wave arm compares it against each row's own step cell and a table
# with no step cells simply has no row at that step. A `T<n>` is different: it names a unit,
# and a table that NUMBERS its rows has no unit called `T1` to be on. That shape is a plan in
# mid-edit (or a fixture), and the honest answer is the one the tick has given since the
# approval gate landed — UNREADABLE, and no fill. Reading it as task-scale instead would make
# every pending row of a wave table ready, which is the DOUBT-then-FILL failure that gate
# exists to prevent.
#
# THE SHAPE QUESTION IS THE HEADER'S, asked through `units_has_column` — the one reader of
# `## Tasks` — so a table that grows or loses a column moves this answer without a code
# change here. A plan with NO TABLE AT ALL is unreadable too, and deliberately: it is not a
# table of units either, nothing about it says which shape the run is, and answering
# otherwise would change what the tick says about a plan that has always been "unreadable"
# to it (`no FILL — plan current: unreadable (T5)`) while filling exactly as much: nothing.
#
# THE WAVE QUESTION IS ASKED FIRST because a wave plan answers it in one parse; only a plan
# whose rows are unnumbered pays the second read.
fill_step_token() {  # <plan> -> a numeric step, a `T<n>`, or ""
  local plan="${1:-}" raw step
  _fill_current_load "$plan"
  raw="$_FILL_CURRENT_VALUE"
  [ -n "$raw" ] || { printf ''; return 0; }
  step="${raw%[ab]}"
  case "$step" in
    ''|*[!0-9]*) : ;;
    *) printf '%s' "$step"; return 0 ;;
  esac
  case "$raw" in
    T*) case "${raw#T}" in
          ''|*[!0-9]*) : ;;
          *) if units_has_column "$plan" step; then
               printf ''                       # a table that NUMBERS its rows
             elif units_has_column "$plan" id; then
               printf '%s' "$raw"              # a table of units
             else
               printf ''                       # no table at all
             fi
             return 0 ;;
        esac ;;
  esac
  printf ''
}

# ── THE READY SET ─────────────────────────────────────────────────────────────
#
# fill_ready_set <plan> <rung> <open> -> the ids that may be dispatched RIGHT NOW, one per
# line, in table order, at most <rung> - <open> of them.
#
# THREE GATES, CHEAPEST FIRST, and each of them prints nothing when it holds:
#
#   1. the ledger — `fill_ledger_live`, which is the Step-3 gate: a numeric `current:` below
#      4, or a field that will not parse, is not live;
#   2. the arithmetic — a rung that is not a non-negative integer offers nothing to fill
#      AGAINST (a plan with no readable width has no ceiling to fill to), and a gap of zero or
#      less is a full budget;
#   3. the table — the step token (empty when `current:` and the table's shape disagree),
#      then `units_ready` at that token, trimmed to the gap in TABLE order, which is the
#      orchestrator's own dependency ordering and never re-sorted. Only this gate reads the
#      table, and it reads it once (`_fill_ready_rows`, below).
#
# THE TRIM IS HERE, NOT IN THE CALLER. Two callers trimming their own way is how the tick and
# the wall would come to name different rows on one turn, which is the disagreement this
# library exists to make impossible.
#
# IT PRINTS IDS, NOT NAMES. `fill_name` is the id -> agent-name map and it needs a roster,
# which is a session's fact rather than a plan's; the tick maps what it prints, the wall
# names the rows.
fill_ready_set() {  # <plan> <rung> <open> -> ready ids, one per line
  local plan="${1:-}" rung="${2:-}" open="${3:-}" gap
  fill_ledger_live "$plan" || return 0
  case "$rung" in ''|*[!0-9]*) return 0 ;; esac
  case "$open" in ''|*[!0-9]*) open=0 ;; esac
  gap=$(( rung - open ))
  [ "$gap" -gt 0 ] || return 0
  units_memoised "$plan" _fill_ready_rows "$plan" "$gap"
}

# _fill_ready_rows <plan> <gap> -> the step token's ready ids, trimmed to <gap>. The body of
# `fill_ready_set` past its cheap gates, run under `units_memoised` so the header questions
# `fill_step_token` asks at task scale and the rows `units_ready` reads are ONE parse of the
# table (wave-19 REQ-6, D7; AC-6.2). The gates above ask only `current:` (already read once
# per process) and arithmetic, so a closed gap or a ledger that is not live still reads no
# table at all; which gate refuses first changes nothing, since each of them prints nothing.
_fill_ready_rows() {  # <plan> <gap>
  local plan="${1:-}" gap="${2:-0}" step ready id n=0
  step="$(fill_step_token "$plan")"
  [ -n "$step" ] || return 0
  ready="$(units_ready "$plan" "$step")" || return 0
  [ -n "$ready" ] || return 0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    [ "$n" -lt "$gap" ] || break
    printf '%s\n' "$id"
    n=$((n + 1))
  done <<FILL_READY_ROWS
$ready
FILL_READY_ROWS
  return 0
}

# ── THE NAME A ROW IS DISPATCHED UNDER ────────────────────────────────────────
#
# THE TICK PRINTS THE NAME, THE ORCHESTRATOR COPIES IT, AND THE DISPATCH WALL REFUSES
# ANYTHING ELSE (T22, A-orch-33). Moved here from `hooks/session-poker.sh` with the wave-17
# reasoning intact, because the fill duty's refusal names rows the tick may also have
# printed and a second spelling of "which name is free" would let the two disagree.
#
# THE ROSTER IS WHAT "SPENT" MEANS, not the plan. The plan's `## Tasks` row keeps its id —
# `T5` is still `T5` to a human reading the ledger — and the roster is the record of which
# names THIS SESSION has actually handed out. A name is spent if any row carries it, in any
# state: an open row obviously cannot be reused, and a CLOSED one is the common case (a
# landed task being run again) where reuse would put a second lineage on a name the sweep has
# already discharged.
#
# PER SESSION, exactly as the dispatch wall's in-flight arm reads it, so the two cannot
# disagree about which names are available. A predecessor's roster reserves nothing.
#
# THE COUNT IS A SEARCH, NOT AN INCREMENT: `-r2`, then `-r3`, until a name no row carries. A
# rule that always appended `-r2` would hand out a taken name on the third run.
fill_name() {  # <roster file> <task id> -> the agent name to dispatch under
  local f="$1" id="$2" n=2 cand
  [ -n "$id" ] || return 0
  if [ ! -f "$f" ] || [ -L "$f" ] || ! grep -qF "|name=${id}|" "$f" 2>/dev/null; then
    printf '%s' "$id"; return 0
  fi
  # A bound, so a corrupt roster cannot spin here. Ninety-eight runs of one task is a
  # different problem than this function can solve, and printing the id back is the
  # fail-visible answer: the dispatch wall refuses it and says the name is in flight.
  while [ "$n" -le 99 ]; do
    cand="${id}-r${n}"
    grep -qF "|name=${cand}|" "$f" 2>/dev/null || { printf '%s' "$cand"; return 0; }
    n=$((n + 1))
  done
  printf '%s' "$id"
}
