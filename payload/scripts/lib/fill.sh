#!/bin/bash
# payload/scripts/lib/fill.sh — READINESS IS A PROPERTY OF THE UNIT, NOT OF THE SCALE
# (epic-23 wave-18-fixit-185, REQ-3; spec Design §1 "Ready set"/"Fillable gap", §2 D2;
# ADR-033 decision 2).
#
# WHAT IT OWNS. The one computation of "which rows may be dispatched now", and the one
# predicate for "is this run's ledger live". Three verbs, all pure functions of the plan
# file (and, for the third, of the session's roster):
#
#   fill_ledger_live <plan>            0 when the plan's `## SDLC State` carries a non-blank
#                                      `approved-by:` line (wave-26 T13; D3), 1 otherwise.
#                                      The cheap gate a caller asks BEFORE paying for a
#                                      table read.
#   fill_step_token <plan>             the step the ready set is asked at: the numeric
#                                      `current:` with its sub-step letter stripped, or
#                                      `T<n>` when the table is task-shaped. Empty when the
#                                      two disagree or the field will not parse. At wave
#                                      scale it decides only the gate acts (integrate,
#                                      close); a work row is ready at any step (wave-20 Δ1).
#   fill_ready_set <plan> <rung> <open>
#                                      the ready ids, one per line, in TABLE order, the
#                                      writers trimmed to <rung> - <open> and the rows that
#                                      take no writer slot offered whatever the gap. Empty
#                                      and silent whenever the ledger is not live or the
#                                      table carries no ready row.
#   fill_readonly_ids <plan>           the ids of the rows that take no writer slot.
#   fill_name <roster> <task id>       the agent NAME to dispatch that id under, which is the
#                                      id itself until this session has already spent it.
#   fill_row_launched <task id> <names>
#                                      0 when one of <names> (comma-joined Agent names) is a
#                                      dispatch name for that id — the inverse of fill_name.
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
# READINESS IS THE PREREQUISITE GRAPH (wave-20 REQ-5, Δ1, Δ6; ADR-036). The set this library
# returns stopped being "this step's ready rows": a pending row whose prerequisites have all
# landed is ready whatever its step, once the plan carries its approval (`fill_ledger_live`, the
# `approved-by:` line since wave-26 T13), and only an `integrate` or `close` row — and, in a
# table without the `reads` column, the release — still waits for `current:` to reach its step. The rule is `units_ready`'s; this file passes it the step token and trims the answer,
# so the tick, the wall and the card inherit it with no change of their own.
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
#
# AND THE APPROVAL, IN THE SAME PASS (wave-26 T13; D3, AC-6.2). The ledger is live on the plan's
# `approved-by:` line, which only the user's act writes, so the one read of `## SDLC State` that
# finds `current:` finds that line too: `_FILL_APPROVED` is 1 when a non-blank `approved-by:`
# sits in the section, the reading `units.sh` takes for `approval:plan`.
_FILL_CURRENT_PLAN=""
_FILL_CURRENT_VALUE=""
_FILL_APPROVED=0
fill_current_forget() {  # -> drops the memo; the next reader parses whatever path it names
  _FILL_CURRENT_PLAN=""
  _FILL_CURRENT_VALUE=""
  _FILL_APPROVED=0
}
_fill_current_load() {  # <plan path> -> sets _FILL_CURRENT_VALUE and _FILL_APPROVED; parses at most once
  local plan="${1:-}" got
  if [ -n "$plan" ] && [ "$plan" = "$_FILL_CURRENT_PLAN" ]; then
    return 0
  fi
  if [ -z "$plan" ] || [ ! -f "$plan" ]; then
    _FILL_CURRENT_VALUE=""
    _FILL_APPROVED=0
    _FILL_CURRENT_PLAN=""
    return 0
  fi
  got="$(awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$plan" 2>/dev/null | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^## SDLC State/ { flag = 1; next }
    /^## / { flag = 0 }
    flag && !got && /^[[:space:]]*current[[:space:]]*:/ {
      v = $0
      sub(/^[[:space:]]*current[[:space:]]*:[[:space:]]*/, "", v)
      gsub(/[[:space:]]/, "", v)
      cur = v
      got = 1
    }
    flag && /^[[:space:]]*-?[[:space:]]*approved-by[[:space:]]*:/ {
      v = $0
      sub(/^[[:space:]]*-?[[:space:]]*approved-by[[:space:]]*:/, "", v)
      if (v ~ /[^[:space:]]/) appr = 1
    }
    END { printf "%s\037%d", cur, appr }')"
  _FILL_CURRENT_VALUE="${got%$'\037'*}"
  _FILL_APPROVED="${got##*$'\037'}"
  case "$_FILL_APPROVED" in 1) : ;; *) _FILL_APPROVED=0 ;; esac
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
# LIVE MEANS "PAST THE APPROVAL GATE", AND THE GATE IS THE USER'S ACT (wave-26 T13; D3,
# AC-6.2). Dispatching into a task table nobody has ratified sends a writer against a plan that
# may not survive its own review (the 2026-09-05 incident the tick's approval gate closed).
# Through 1.10 this asked `current: >= 4` (or a task-scale `T<n>`), a field the orchestrator
# writes itself; it now asks the plan's `approved-by:` line, written on the user's literal
# approval and the one fact `hooks/dispatch-preflight.sh` already refuses a writer without. The
# two readers of "may a writer start" agree, and a plan approved before `current:` moves fills.
#
# IT ASKS THE LINE AND NOTHING ELSE. Whether `current:` reads against the table is
# `fill_step_token`'s question, and whether there is ROOM is the caller's: this is the cheap
# gate a caller asks before paying for a table read.
fill_ledger_live() {  # <plan> -> 0 live · 1 not
  fill_plan_approved "${1:-}"
}

# fill_plan_approved <plan> -> 0 when `## SDLC State` carries a non-blank `approved-by:` line.
fill_plan_approved() {
  _fill_current_load "${1:-}"
  [ "$_FILL_APPROVED" = 1 ]
}

# ── WHICH STEP IS THE READY SET ASKED AT? ─────────────────────────────────────
#
# fill_step_token <plan> -> the token `units_ready` takes as its second argument, or "" when
# the plan's `current:` cannot be read against the table it carries.
#
# THE FIELD AND THE TABLE HAVE TO AGREE. A numeric `current:` is answerable whatever the
# table looks like — the wave arm holds a gate act (integrate, close) until the field reaches
# the row's own step cell, and a row with no numeric step cell is never a wave row. A `T<n>` is different: it names a unit,
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
#
# A ROW ALREADY ANSWERED IS LEFT OUT BEFORE THE TRIM (wave-24 T27; D2, AC-4.7). The optional
# fourth operand is the standing decline's ids (`fill_standing_decline`, below): those rows are
# skipped and do not take a slot, so the gap goes to the next ready row in table order — the
# rows the stop wall names when it refuses a turn for the rows the decline did not answer.
#
# A ROW THAT TAKES NO WRITER SLOT IS OFFERED OUTSIDE THE GAP (wave-26 T13; D9). The gap is the
# writer budget; a verify or review row runs a read-only role (`fill_readonly_ids`, below), so a
# full budget is no reason to hold it. Those rows are printed whenever they are ready, in their
# table place, and only the writers are trimmed, in table order — so a closed gap still prints
# the read-only rows, and the gate on the gap is the writers' alone.
fill_ready_set() {  # <plan> <rung> <open> [<answered ids, space-joined>] -> ready ids, one per line
  local plan="${1:-}" rung="${2:-}" open="${3:-}" gap
  fill_ledger_live "$plan" || return 0
  case "$rung" in ''|*[!0-9]*) return 0 ;; esac
  case "$open" in ''|*[!0-9]*) open=0 ;; esac
  gap=$(( rung - open ))
  [ "$gap" -gt 0 ] || gap=0
  units_memoised "$plan" _fill_ready_rows "$plan" "$gap" "${4:-}"
}

# _fill_ready_rows <plan> <gap> -> the step token's ready ids, the writers trimmed to <gap>. The
# body of `fill_ready_set` past its cheap gates, run under `units_memoised` so the header
# questions `fill_step_token` asks at task scale, the rows `units_ready` reads and the kinds
# `fill_readonly_ids` reads are ONE parse of the table (wave-19 REQ-6, D7; AC-6.2). The gates
# above ask only the approval line (read once per process with `current:`) and arithmetic, so a
# ledger that is not live still reads no table at all.
_fill_ready_rows() {  # <plan> <gap> [<answered ids> [tagged]]
  local plan="${1:-}" gap="${2:-0}" skip=" ${3:-} " tag="${4:-}" step ready id n=0 ro tab=$'\t'
  step="$(fill_step_token "$plan")"
  [ -n "$step" ] || return 0
  ready="$(units_ready "$plan" "$step")" || return 0
  [ -n "$ready" ] || return 0
  ro=" $(fill_readonly_ids "$plan") "
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    case "$skip" in *" $id "*) continue ;; esac
    case "$ro" in *" $id "*) printf '%s%s\n' "$id" "${tag:+${tab}r}"; continue ;; esac
    [ "$n" -lt "$gap" ] || continue
    printf '%s%s\n' "$id" "${tag:+${tab}w}"
    n=$((n + 1))
  done <<FILL_READY_ROWS
$ready
FILL_READY_ROWS
  return 0
}

# fill_ready_tagged <plan> -> every ready id, untrimmed, as `<id><TAB>w` (takes a writer slot) or
# `<id><TAB>r` (does not), table order. The stop wall's reading: it trims the writers to its own
# free slots and owes every read-only row, from the one parse `_fill_ready_rows` takes.
fill_ready_tagged() {  # <plan>
  local plan="${1:-}"
  fill_ledger_live "$plan" || return 0
  units_memoised "$plan" _fill_ready_rows "$plan" 99999 "" tagged
}

# ── THE ROWS THAT TAKE NO WRITER SLOT (wave-26 T13; D9) ───────────────────────
#
# fill_readonly_ids <plan> -> the ids, space-joined, of the rows whose kind is `verify` or
# `review`, in table order.
#
# THE RULE IS THE KIND, BECAUSE THE KIND IS WHAT THE TABLE CARRIES (A-T13.2). A writer slot is a
# writer's: an agent that edits a worktree. The dispatch wall knows the role it is launching
# (`role_is_readonly`, lib/roster.sh), but a plan row names no role — its `agent` cell is a NAME
# (`w26-T4`, `implementor`, `auditor`, whatever the author wrote), and reading a role out of
# free text would make the budget depend on spelling. The kind is an enum the validator holds:
# a `verify` row runs the floor and the walk, a `review` row reads a diff, and both write only
# their own record. Every other kind — build, test, doc, prototype, integrate, close — edits the
# tree and is trimmed to the gap. A verify row's suite run takes a place of its own (D8's
# booking), not a writer slot, so offering it outside the gap overcommits nothing the gap counts.
fill_readonly_ids() {  # <plan> -> ids, space-joined
  units_rows "${1:-}" 2>/dev/null | awk -F'\t' '
    $3 == "verify" || $3 == "review" { printf "%s%s", (n++ ? " " : ""), $1 }'
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

# ── WHICH READY ROWS A TURN LAUNCHED (wave-20 T11b; Step-6 review R4) ─────────
#
# THE INVERSE OF `fill_name`. The stop wall's fill duty counts a turn's launches against the
# plan's ready set, and a row the turn launched but has not yet ledgered `active` is still in
# that set (A-T11.1). So the wall asks, per ready id, whether one of the turn's Agent names is
# a name that row is dispatched under: the id itself or the id with `fill_name`'s `-r<n>`
# suffix, standing alone or behind a `<prefix>-` (the fleet dispatches `T5` as `w20-T5`, and a
# bed as `w-bed-T2`). Whole dash-separated tokens only: `w20-T11b` is T11b's, never T1's.
#
# THE NAME, NEVER THE PROMPT (AC-5.4). The Agent call's `name` is the roster's key for the
# launch — the dispatch wall rosters it and the occupancy already counts it — so matching it
# subtracts a launch the wall has already seen. The prompt's words are still never read.
fill_row_launched() {  # <task id> <names, comma-joined> -> 0 launched · 1 not
  local id="${1:-}" names="${2:-}" n base
  local -a list
  [ -n "$id" ] && [ -n "$names" ] || return 1
  IFS=, read -r -a list <<< "$names"
  for n in "${list[@]}"; do
    base="$n"
    case "$base" in
      *-r[0-9]*) case "${base##*-r}" in ''|*[!0-9]*) : ;; *) base="${base%-r*}" ;; esac ;;
    esac
    [ "$base" = "$id" ] && return 0
    case "$base" in *"-$id") return 0 ;; esac
  done
  return 1
}

# ── THE STANDING FILL DECLINE (wave-24 T8, T27; D2, AC-4.7) ──────────────────
#
# A DECLINE STANDS AGAINST THE READY SET IT ANSWERED. A `fill-declined: <reason>` whose reason
# still holds next turn ("T7 waits on T6's merge") used to have to be written again on every
# turn end. The fill ledger keeps each Stop's ready set, `current:` and decline, so the
# session's latest declined line is the standing answer: the ids it answered are its ready set
# less the rows that turn launched, and it stands while `current:` reads as it did then. A row
# it never saw, or a moved `current:`, is unanswered. Another session's line is not this
# conversation's answer.
#
# ONE READER, TWO PROCESSES (Step-6 review C2/U1). The stop wall's collector refuses a turn
# only for the rows this does not answer, and the tick prints it and leaves those rows out of
# its FILL; both call this, so the row the wall treats as answered is never the row the tick
# asks for. `tests/cross-gate-agreement.test.sh` §SD asks both over one fixture.
#
# A DECLINE IS A REASON (A-T8.7): the line's `declined=` must carry a letter or a digit, the
# rule the turn's own decline is held to, so a line written before that rule with `declined=—`
# answers nothing (review C4). Read from the ledger's last FILL_STANDING_WINDOW lines; a decline
# older than that stands for nothing, which refuses more. A ledger that is a symlink is not read.
#
# Prints `<at>US<reason>US<ids, space-joined>` (US = \037), or nothing when no decline stands.
FILL_STANDING_WINDOW=2000
fill_standing_decline() {  # <ledger path> <session id> <current: as read now>
  local led="${1:-}" sid="${2:-}" cur="${3:-}" line at st_cur ready launched reason id ids=""
  [ -n "$led" ] && [ -n "$sid" ] && [ -f "$led" ] && [ ! -L "$led" ] || return 0
  line="$(tail -n "$FILL_STANDING_WINDOW" "$led" 2>/dev/null | awk -v sid="$sid" '
    function kv(line, key,   i, n, parts) {
      n = split(line, parts, "|")
      for (i = 2; i <= n; i++) if (index(parts[i], key "=") == 1) return substr(parts[i], length(key) + 2)
      return ""
    }
    index($0, "fill-ledger/v1|") == 1 && kv($0, "session") == sid && kv($0, "declined") ~ /[[:alnum:]]/ {
      last = kv($0, "at") "\037" kv($0, "current") "\037" kv($0, "ready") "\037" kv($0, "launched") "\037" kv($0, "declined")
    }
    END { if (last != "") print last }')"
  [ -n "$line" ] || return 0
  IFS=$'\037' read -r at st_cur ready launched reason <<< "$line"
  [ "$st_cur" = "$cur" ] || return 0
  for id in ${ready//,/ }; do
    fill_row_launched "$id" "$launched" && continue
    ids="${ids}${ids:+ }${id}"
  done
  [ -n "$ids" ] || return 0
  printf '%s\037%s\037%s\n' "$at" "$reason" "$ids"
}
