#!/bin/bash
# payload/scripts/lib/units.sh — THE ONE READER OF THE PLAN'S `## Tasks` TABLE.
#
# WHAT IT OWNS (epic-23 wave-11-lean-spine, REQ-1e; spec Design §1 "Task", §2 D3/D7, §3
# ownership row "Tasks schema"). The schedule every wave runs on — one row per unit of work
# at Steps 3–9 — and the three questions asked of it. Pure functions of a file; nothing here
# writes, and nothing here runs at source time:
#
#   units_rows <plan>          one TSV line per row, the twelve fields in the FIXED order
#                              id·step·kind·task·agent·deps·size·serves·Files·status·worktree·base,
#                              in TABLE order. Exit 1 and silent when the plan carries no
#                              `## Tasks` table.
#   units_ready <plan> <step>  the ids of rows whose status is `pending` and whose every
#                              dependency has landed, whatever their step; a row of kind
#                              `integrate` or `close` also waits until <step> reaches its
#                              own (wave-20 Δ1, Δ6). One per line, table order. <step> is a
#                              number (wave scale) or `T<n>` (task scale, where the rows
#                              carry no step cell and a dependency is satisfied by `done`).
#                              Exit 2 on anything else.
#   units_validate <plan>      one line per broken invariant, each naming the offending id
#                              and the rule. Exit 1 if any line was printed, else 0.
#   units_add_row <plan> <id> <step> <kind> <task> <agent> <deps> <size> <serves> <Files>
#                              the WHOLE plan with one row added, on stdout; the file is
#                              not written (wave-20 REQ-5, AC-5.3). `task-add` is its caller.
#
# THE CALLERS (D3), all re-pointed by T8: the evidence gate's two ledger checks and its
# prototype check, the tick's FILL, the governing-skill's Step-3 wall, and any report. No
# other file parses `## Tasks` — that is the ownership claim this library exists to make,
# and tests/units.test.sh plus the caller-agreement pin are what hold it.
#
# WHY HEADER-KEYED, AND WHY THAT IS THE WHOLE POINT (AC-1e.2; measure §4.3). Two readers in
# hooks/canonical-sdlc-evidence-gate.sh took id/rigor/status as awk fields `$2`/`$4`/`$6` of
# a five-column table. This wave's ten-column table puts `agent` at `$6` and `kind` at `$4`,
# so both would have read an agent name as a status and refused every row — on this wave's
# own plan, at its own next commit. Column INDICES are taken from the header row BY CELL
# TEXT, matched case-insensitively and trimmed (`Files` is the one capitalised header the
# shipped table carries). Inserting, moving or renaming a column nobody reads is then an
# ordinary edit, and a column this library does read moves without a code change. The idiom
# is `slice_table`'s (hooks/session-poker.sh:1187), which is the reader 1e collapses into
# this one; extra columns are ignored, and a required column that is absent yields an empty
# field and a `missing column` violation rather than a silent shift.
#
# FENCE-AWARE, for the reason every other plan read in this tree is: a table inside a ```
# example is documentation ABOUT the schema, and scheduling a wave off a documented example
# is the newest-race incident in a new costume. The fence toggle runs before the section
# test, so a fenced `## Tasks` heading does not open the section either.
#
# `## Tasks` IS THE ONLY SECTION READ. A table under the RETIRED section heading this wave
# replaced — the four-column shape, spelled with the unit-of-work noun the domain dictionary
# now marks retired — is ignored even though it carries `id`, `deps` and `status` cells that
# a name-keyed reader would otherwise be happy to take. tests/units.test.sh's `decoys.md`
# fixture is what holds that, and it keeps the old heading literal for the purpose. The
# section ends at the next `##` heading or at the first line that is not a table row.
#
# ONE PARSE, THREE VERBS. `units_ready` and `units_validate` are functions of `units_rows`'
# output and never touch the file themselves, so the three answers cannot disagree about
# what one table says. `_units_read` is the single parse; it emits a `#`-prefixed control
# line naming the required columns the header lacks, which is the one fact the TSV cannot
# carry (an absent column and an empty cell are the same empty field).
#
# AND ONE PARSE PER COMMAND WHEN THE CALLER ASKS FOR IT (wave-19 REQ-6, D7). Each verb still
# reads the file itself, because a verb asked once should not depend on anything a caller set
# up. A caller that asks the same plan several questions runs them under `units_memoised
# <plan> <command…>`: the table is parsed once, and every verb the command reaches answers
# that plan from the parse. The memo lives exactly as long as the command (bash's dynamic
# scope for `local`), so no caller outside it can ever be answered from a stale read.
#
# SOURCED, NEVER EXECUTED. Only function definitions run at source time; nothing prints.
# Every caller reads a verb through `$( )`, and a library that greeted them would corrupt
# the first field of every answer.
#
# BASH 3.2 (macOS /bin/bash). No associative arrays, no `${var^^}`, no `mapfile`, and the
# awk programs stay inside POSIX awk — no `gensub`, no `length(array)`, no sorting built-in.
#
# SLOT 11 IS `worktree`, AND IT IS THE ONE OPTIONAL SLOT (wave-14 REQ-2, ADR-027). The
# `## Tasks` table is the register of in-flight units: the dispatcher writes the tree it
# created into the row, and the evidence gate reads the row back to judge a commit made from
# that tree at THAT row's step rather than at the run's single `current:`. The cell belongs
# here because this library is the only reader of the table, and a second parser for one cell
# is the thing REQ-1e existed to remove.
#
# OPTIONAL MEANS NO `missing column` VIOLATION, and that asymmetry is deliberate. Every plan
# written before this wave carries no `worktree` header, and so does every solo-writer plan
# after it; none of them is invalid for it. An absent column reads as an empty cell on every
# row — the same answer a present column with an empty cell gives — and the gate's arm treats
# "no tree named" and "this row names no tree" identically, so the two cannot disagree. The
# ten slots above stay REQUIRED: a table missing `step` is a table whose rows cannot be
# scheduled, which is a fault, while a table missing `worktree` is a table nobody dispatched
# into trees.
#
# THE RECORD IS ALWAYS ELEVEN FIELDS WIDE even when the column is absent, because a record
# whose width depended on the table's shape would put every caller back to counting cells.
#
# A CELL MAY CONTAIN A PIPE, AND MARKDOWN SPELLS IT `\|` (critic Issue 1, A-84). The
# earlier claim here — that no cell ever holds one, so there is nothing to unescape — was
# true of the raw byte and false of the table: `\|` is the one escape GFM defines for a
# table cell, it is a raw `|` to `split()`, and it opens an extra field that reads every
# later cell one slot early. This wave's own plan carries one in T23's `task` cell, and
# with it in place `units_ready` could schedule nothing at Step 5 while `units_validate`
# reported two violations against cells that were correct — a silent shift, because a
# shifted row is still a row. So `_units_read` folds `\|` to SUBSEP before the split and
# restores a LITERAL `|` in `trim`, which is what the cell means. SUBSEP (`\034`) is the
# sentinel because it is the one byte awk itself reserves for "not text", no plan file can
# carry it through a markdown table, and it needs no regex quoting on either side.
#
# LINE ENDINGS ARE NORMALISED HERE, NOT AT THE CALLER (T8). Two of the callers read plans
# a human may have written on another machine, and one of them — the evidence gate — is
# pinned on CR-only (classic-Mac) input by tests/canonical-sdlc-evidence-gate.test.sh
# 19j-cr1/19j-cr2: a CR-only file collapses to ONE awk record, so a parser that did not
# translate would find no table and say so silently. The translation is a pass of its own
# because a record split on `\n` cannot re-split itself.
#
# SLOT 3 ANSWERS TO TWO NAMES, `kind` AND `rigor` (T8). Slot 3 is the row's CLASSIFICATION
# cell. The wave-scale table this library was written for spells it `kind`; the task-scale
# registration ledger the evidence gate has read since D12 — `| id | intent | rigor |
# description | status |` — spells the same slot `rigor`, and that table is NOT widened by
# this wave. One alias is what lets `validate_task_ledger` read its rigor cell through this
# library instead of keeping a second `## Tasks` parser alive, which is the whole of
# AC-1e.1. No table carries both spellings, and the first header cell to match wins.

# ── THE ONE PARSE ────────────────────────────────────────────────────────────
#
# _units_read <plan> -> line 1: `# <required columns the header lacks, space-separated>`
#                       then one TSV row per data row, in table order.
#                       Exit 1 and silent when there is no `## Tasks` table.
#
# Rows are buffered and printed at END because the control line has to come first and the
# missing-column set is not known until the header has been read.
_units_read() {
  [ -n "${1:-}" ] && [ -f "$1" ] || return 1
  awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$1" | awk '
    # esc() FOLDS THE ESCAPE, trim() RESTORES IT, and every cell reaches the caller through
    # trim() — the header scan, the id test and the ten field reads alike — so there is no
    # path on which a SUBSEP survives into the TSV.
    function esc(v)  { gsub(/\\[|]/, SUBSEP, v); return v }
    function trim(v) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); gsub(SUBSEP, "|", v); return v }

    BEGIN {
      # The contract order. `disp` is the spelling a violation names; `want` is the
      # lower-cased text a header cell is matched against.
      disp[1] = "id";    disp[2] = "step";   disp[3] = "kind";   disp[4] = "task"
      disp[5] = "agent"; disp[6] = "deps";   disp[7] = "size";   disp[8] = "serves"
      disp[9] = "Files"; disp[10] = "status"; disp[11] = "worktree"; disp[12] = "base"
      for (k = 1; k <= 12; k++) want[k] = tolower(disp[k])
      alt[3] = "rigor"   # slot 3 as the task-scale ledger spells it
      state = 0   # 0 before the section · 1 in it, header not yet seen · 2 in the table · 3 done
    }

    # THE FENCE TOGGLE RUNS FIRST, so a heading or a table inside a code block is prose.
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }

    state == 3 { next }

    # A heading closes whatever we were in. The FIRST `## Tasks` is the section; a later one
    # is not reached, because reading its predecessor put us in state 3.
    /^[ \t]*#/ {
      if (state == 2 || state == 1) { state = 3; next }
      if ($0 ~ /^##[ \t]+[Tt]asks([ \t].*)?$/) state = 1
      next
    }

    # Looking for the header row: the first table row inside the section carrying an `id`
    # cell. Anything else in the section (a sentence, a blank line) is skipped.
    state == 1 {
      if ($0 !~ /^[ \t]*\|/) next
      n = split(esc($0), c, "|")
      for (i = 1; i <= n; i++) {
        t = tolower(trim(c[i]))
        if (t == "") continue
        for (k = 1; k <= 12; k++) if ((t == want[k] || t == alt[k]) && col[k] == 0) col[k] = i
      }
      if (col[1] == 0) next          # no `id` cell — not the header row
      found = 1
      hdrn = n                       # the header field count, for the raw-pipe rule below
      state = 2
      next
    }

    # The rows. The table ends at the first line that is not a table row.
    state == 2 {
      if ($0 !~ /^[ \t]*\|/) { state = 3; next }
      n = split(esc($0), c, "|")
      id = trim(c[col[1]])
      # The |---|---| separator, and any row whose id cell is empty or punctuation.
      if (id == "" || id ~ /^[-: ]+$/) next
      # A RAW `|` INSIDE A CELL, which `esc()` has NOT folded (only `\|` is folded), is an
      # ordinary separator to split() and opens a field the header does not have. The row
      # is still emitted — every caller wants the cells it can get — but the id is recorded
      # here so `units_validate` can say the one thing a reader can act on instead of the
      # three misleading ones the shift produces. Reported as the field count less the
      # trailing empty field, both sides the same way, so the two numbers compare.
      if (hdrn > 0 && n > hdrn) over = (over == "" ? "" : over " ") id "=" (n - 1)
      line = ""
      for (k = 1; k <= 12; k++) {
        f = (col[k] > 0 && col[k] <= n) ? trim(c[col[k]]) : ""
        line = (k == 1) ? f : line "\t" f
      }
      nr++
      row[nr] = line
      next
    }

    END {
      if (!found) exit 1
      missing = ""
      # THE LOOP STOPS AT 10, NOT 12: slots 11 (`worktree`) and 12 (`base`) are optional,
      # and an absent optional column is not a fault to report.
      for (k = 1; k <= 10; k++) if (col[k] == 0) missing = (missing == "") ? disp[k] : missing " " disp[k]
      # FIELD 4 NAMES WHAT THE HEADER CARRIES — every contract column present, including
      # the optional `worktree`, which field 1 deliberately cannot report (field 1 lists
      # what is MISSING, and an absent optional column is not missing). `units_has_column`
      # is its one reader, and the evidence gate worktree lead-in is why it exists: an
      # absent `worktree` column reads every row cell empty, which is indistinguishable
      # from "no row names this tree" to `units_rows` alone (wave-16 REQ-3, AC-3.2).
      # NO APOSTROPHE ON ANY LINE INSIDE THIS awk PROGRAM: it is single-quoted, and one
      # would close the quote and hand the rest of the parser to bash.
      for (k = 1; k <= 12; k++) if (col[k] > 0) present = (present == "") ? disp[k] : present " " disp[k]
      # THE CONTROL LINE IS TAB-SEPARATED: <missing columns> · <header width> · <id=width …>
      # · <columns present>. `units_rows` drops this line whole, so no caller outside this
      # file sees it; `units_validate` reads fields 2-3 and `units_has_column` field 4.
      printf "# %s\t%d\t%s\t%s\n", missing, hdrn - 1, over, present
      for (i = 1; i <= nr; i++) print row[i]
    }
  '
}

# _units_table <plan> -> `_units_read`'s output and status for <plan>: from the memo when
# `units_memoised` is running for that same path, from a fresh parse otherwise. Every verb
# reads the table through this and nothing else.
_units_table() {
  if [ -n "${_UNITS_MEMO_PLAN:-}" ] && [ "$_UNITS_MEMO_PLAN" = "${1:-}" ]; then
    printf '%s' "$_UNITS_MEMO_OUT"
    return "$_UNITS_MEMO_RC"
  fi
  _units_read "${1:-}"
}

# units_memoised <plan> <command> [args…] -> runs the command; every verb it reaches answers
# <plan> from ONE parse of the table, and the command's status is returned.
#
# THE MEMO IS THE COMMAND'S, NOT THE PROCESS'S. The three variables are `local` here, so bash's
# dynamic scope hands them to everything the command calls — subshells included, which is how
# a verb read through `$( )` still hits the memo — and takes them away when it returns. A
# process that edits a plan after asking about it (close-out, a suite reusing one fixture
# path) therefore reads the edit; only the command that asked for the memo sees the one read.
# A plan with no table is memoised as that answer, status and all, so every verb inside still
# says "no table". Another plan asked inside the command is read on its own.
units_memoised() {  # <plan> <command> [args...]
  local _UNITS_MEMO_PLAN="" _UNITS_MEMO_OUT="" _UNITS_MEMO_RC=1
  _UNITS_MEMO_OUT="$(_units_read "${1:-}")"; _UNITS_MEMO_RC=$?
  _UNITS_MEMO_PLAN="${1:-}"
  shift
  "$@"
}

# ── THE THREE VERBS, AND THE ONE ACCESSOR ────────────────────────────────────

# units_has_column <plan> <column> -> 0 when the `## Tasks` header carries that contract
# column, 1 otherwise (and 1 when there is no table at all).
#
# WHY IT IS NOT `units_validate | grep missing` (wave-16 REQ-3, AC-3.2). The missing-column
# set stops at slot 10 because `worktree` is OPTIONAL — an absent optional column is not a
# fault to report — so the one column a caller most needs to ask about is precisely the one
# that set can never mention. This verb reads the control line's fourth field, which names
# what the header HAS, and answers for required and optional columns alike.
#
# THE COLUMN NAME IS THE CONTRACT SPELLING (`Files`, not `files`); the header cell it was
# matched against may have been written in any case, because `_units_read` lower-cases both
# sides before comparing and records the contract spelling. `grep -qxF` over the field's
# words, so `status` never matches inside `worktree` and an empty needle matches nothing.
#
# NO PROCESS AFTER THE READ (wave-19 REQ-6, D7). The control line is the first line, its fourth
# tab-separated field the space-separated names, and the answer is whole-word membership —
# all three taken by parameter expansion rather than the four processes this used to pipe
# through. A needle carrying a space or a tab can never equal one of those words, so it is
# answered 1 before the membership test, which would otherwise match across a word boundary.
units_has_column() {
  local plan="${1:-}" want="${2:-}" ctl i
  [ -n "$want" ] || return 1
  case "$want" in *[' '$'\t'$'\n']*) return 1 ;; esac
  ctl="$(_units_table "$plan" 2>/dev/null)"
  ctl="${ctl%%$'\n'*}"
  [ -n "$ctl" ] || return 1
  for i in 1 2 3; do
    case "$ctl" in *$'\t'*) ctl="${ctl#*$'\t'}" ;; *) return 1 ;; esac
  done
  ctl="${ctl%%$'\t'*}"
  case " $ctl " in *" $want "*) return 0 ;; esac
  return 1
}


# units_field <record> <column> -> that column's cell of one `units_rows` line.
#
# WHY AN ACCESSOR AT ALL (T8). `IFS=\t read -r a b c ...` is the obvious way to take a TSV
# record apart and it is WRONG here: tab is IFS whitespace, so the shell folds a run of
# tabs into ONE delimiter and a row with an empty cell shifts every field after it. awk
# -F'\t' is exact but costs a process per cell, and the callers ask for two or three cells
# of every row of a twenty-row table. This is pure parameter expansion: no process, no
# fold, and an absent trailing cell reads empty rather than shifting.
#
# BY NAME, NOT BY NUMBER, for the reason the parse is header-keyed: a caller that wrote
# `10` would have to be found again if the contract ever grew a twelfth field. The name
# is this library's own contract spelling, NOT the table's header text — `rigor` is
# accepted as the second name of slot 3, the same alias the header scan takes.
units_field() {  # <record> <column name> -> the cell, empty if absent; rc 1 on a bad name
  local rec="${1:-}" n
  case "${2:-}" in
    id) n=1 ;;    step) n=2 ;;   kind|rigor) n=3 ;; task) n=4 ;;  agent) n=5 ;;
    deps) n=6 ;;  size) n=7 ;;   serves) n=8 ;;     Files) n=9 ;;  status) n=10 ;;
    worktree) n=11 ;; base) n=12 ;;
    *) return 1 ;;
  esac
  while [ "$n" -gt 1 ]; do
    case "$rec" in
      *$'\t'*) rec="${rec#*$'\t'}" ;;
      *) return 0 ;;
    esac
    n=$((n - 1))
  done
  printf '%s' "${rec%%$'\t'*}"
}


# units_rows <plan> -> id·step·kind·task·agent·deps·size·serves·Files·status·worktree·base,
#                      tab-separated, one line per row, in TABLE order. Exit 1 when there is
#                      no table.
#
# TABLE ORDER, NOT ID ORDER, and never sorted: the sequence is the orchestrator's own
# dependency ordering, and a reader that re-sorted would answer the dispatch question in an
# order nobody chose.
units_rows() {
  local out rc
  out="$(_units_table "${1:-}")"; rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  # Everything after the control line; nothing when the table has no rows.
  case "$out" in *$'\n'*) printf '%s\n' "${out#*$'\n'}" ;; esac
  return 0
}

# units_ready <plan> <step> -> the ids that may be dispatched now, one per line, table order.
#
# READY = status `pending` and EVERY dependency `landed` — whatever the row's step (wave-20
# REQ-5, Δ1; ADR-036). Through 1.8.6 the row's step also had to EQUAL <step>, and that one
# comparison is why a Step-6 review whose deps had landed sat unfilled while Verify ran, and
# why a Step-4 row added during Step 5 never filled at all. Order is the prerequisite graph's
# job now; the validator below is what guards a forgotten edge.
#
# <step> STILL DECIDES THE GATE ACTS (Δ6). A row of kind `integrate` or `close` is ready only
# once <step> has reached its own step: its real prerequisite is a gate passing (Verify
# CONFIRMED), not a task landing, and without this a merge writer could be named the moment
# its deps landed, before any auditor had spoken. The signature is unchanged, so every caller
# (fill.sh's `_fill_ready_rows`, which passes the plan's `current:`) is untouched.
#
# TWO TABLE SHAPES, ONE ANSWER (wave-18 REQ-3, AC-3.3; ADR-033 decision 2). <step> is the
# plan's `current:`, and this repo writes it two ways: a WAVE plan numbers its steps, a TASK
# plan names the unit it is on — `T<n>`. Passed a `T<n>`, this reads the six-column
# task-scale table (`id · intent · rigor · description · status · worktree`), whose rows
# carry neither a `step` cell nor a `deps` cell, so READY is `pending` alone. Anything that
# is neither a number nor `T<n>` is still a caller fault and still exits 2.
#
# THE ROW'S STEP CELL DECIDES WHICH ARM JUDGES IT, not the argument by itself: at task scale
# a row that CARRIES a step is a wave row and is never ready. That is what keeps the shape
# the tick's approval gate closed — a wave table sitting at `current: T1`, which used to fall
# through to the readiness checks and fill (tests/session-poker.test.sh §22g) — from
# re-opening through this door. A wave table asked at `T<n>` answers nothing, and says it
# with success rather than with the step-refusal status: the table is legible, it simply has
# no task-scale row in it.
#
# AND THE DEPENDENCY WORD IS `done` AT TASK SCALE. `done` is the one terminal word a
# task-scale ledger writes (ADR-033 decision 1); `landed` is a word that table never carries,
# and reading it as satisfaction would schedule a row against a status nobody wrote. The
# shipped six-column table has no `deps` column at all, so the arm is reached only by a table
# that grows one — it is here because the fill direction has to be stated once, not twice.
#
# A dependency cell is a comma-separated list of ids, or an em dash / hyphen / empty cell for
# "none" — all three spellings are recognised as "no alphanumeric character", which keeps a
# Unicode literal out of a bash 3.2 awk program for no gain.
#
# AN ID THIS TABLE DOES NOT CARRY IS NOT READY. An unresolvable dependency is one this reader
# cannot confirm landed, and the fill direction is the cautious one, exactly as `slice_ready`
# documented: a row held back costs a batch, a row dispatched onto an unlanded dependency
# costs the writer's whole run.
#
# ONE PASS TO REMEMBER, ONE TO DECIDE. A dependency may be named before or after the row that
# depends on it, so nothing is answerable until the whole table has been read.
units_ready() {
  local plan="${1:-}" step="${2:-}" rows scale=wave
  case "$step" in
    ''|*[!0-9]*)
      # The task-scale step token, and nothing else: a literal `T` followed by digits.
      case "$step" in
        T*) case "${step#T}" in ''|*[!0-9]*) return 2 ;; *) scale=task ;; esac ;;
        *) return 2 ;;
      esac ;;
  esac
  rows="$(units_rows "$plan")" || return 1
  [ -n "$rows" ] || return 0
  printf '%s\n' "$rows" | awk -F'\t' -v want="$step" -v scale="$scale" '
    $1 == "" { next }
    { n++; id[n] = $1; stp[n] = $2; knd[n] = $3; dep[n] = $6; st[$1] = $10 }
    END {
      # The word a dependency has to carry, by scale. One assignment, so the two arms
      # below differ in exactly the thing they are supposed to differ in.
      satisfied = (scale == "task") ? "done" : "landed"
      for (i = 1; i <= n; i++) {
        if (st[id[i]] != "pending") continue
        if (scale == "task") {
          if (stp[i] != "") continue
        } else {
          # A WAVE ROW CARRIES A NUMERIC STEP, and that is all the step still decides for a
          # work row (wave-20 Δ1): the step is a label, and readiness is the graph below.
          if (stp[i] !~ /^[0-9]+$/) continue
          # A GATE ACT WAITS FOR ITS STEP (Δ6). Its real prerequisite is a gate passing,
          # which no dependency cell can name, so it is ready only once the run has REACHED
          # its step — reached, not equalled: a gate act the run has passed is still due.
          if ((knd[i] == "integrate" || knd[i] == "close") && stp[i] + 0 > want + 0) continue
        }
        d = dep[i]
        gsub(/[ \t]/, "", d)
        if (d !~ /[A-Za-z0-9]/) { print id[i]; continue }
        m = split(d, a, ",")
        ready = 1
        for (j = 1; j <= m; j++) {
          if (a[j] == "" || a[j] !~ /[A-Za-z0-9]/) continue
          if (st[a[j]] != satisfied) { ready = 0; break }
        }
        if (ready) print id[i]
      }
    }'
}

# _units_graph_awk -> the awk functions that decide the transitive rule, printed for a caller
# to put in front of its own program (wave-20 REQ-5, AC-5.2, AC-5.3).
#
# ONE DEFINITION, TWO CALLERS. `units_validate` asks it which rows break the rule and prints a
# line per row; `units_add_row` asks it which rows a new Step-4 row must be threaded into. The
# two questions are the same question — "which rows owe this id, and which of them is the
# edit" — so they are answered by one program, and the row-add verb cannot thread a plan the
# validator would then refuse.
#
# THE CALLER'S PROGRAM FILLS THE ARRAYS: `n`, and per row `id[]`, `stp[]`, `dep[]`, `sta[]`,
# with `skip[id]` set for a row the raw-pipe rule has already named (its cells cannot be
# trusted to accuse anyone). Then:
#
#   units_graph()      the CANDIDATES — rows with a numeric step of 5 or more whose status is
#                      neither `landed` nor `dropped` (`cand[1..nc]`, table order) — each with
#                      its transitive closure `R[i, <id>]`, and `M[i, k]` for every Step-4 row
#                      k that candidate i does not reach.
#   units_frontier(i)  the Step-4 ids row i must add itself (FR_IDS, comma-joined, table order;
#                      FR_CNT; FR_LIST[k]), and the candidates that reach them through it
#                      (FR_FOLD). Returns FR_CNT.
#
# LANDED AND DROPPED ROWS ARE NOT CANDIDATES (research D1 T-2). The rule is a scheduling
# invariant, and a terminal row can no longer be scheduled: a fixup Step-4 row added during
# Verify would otherwise force an edge onto the already-landed audit row, and that edge would
# record something false. They still carry edges, so a candidate reaches THROUGH them.
#
# THE FRONTIER (triage-C claim 3). Candidate i is FOLDED for Step-4 row k when it reaches
# another candidate j that also misses k, and j does not reach i: adding k to j repairs i, so
# i owes no edit of its own for k and its line would be a second instruction for one fix. The
# "j does not reach i" half is what keeps a dependency CYCLE from folding both of its rows into
# each other and printing nothing — every missing edge is still named somewhere.
_units_graph_awk() {
  printf '%s' '
    function units_graph(   i, k, m, j, d, dd, a, b, h, qn, cur, x) {
      nc = 0
      split("", R); split("", M); split("", alld)
      for (i = 1; i <= n; i++) {
        d = dep[i]; gsub(/[ \t]/, "", d)
        alld[id[i]] = alld[id[i]] "," d
      }
      for (i = 1; i <= n; i++) {
        if (id[i] in skip) continue
        if (stp[i] !~ /^[0-9]+$/ || stp[i] + 0 < 5) continue
        if (sta[i] == "landed" || sta[i] == "dropped") continue
        cand[++nc] = i
        # BREADTH-FIRST over the dependency edges. The reachable set is reset per row: a rule
        # decided once for the whole table is a different rule (tests/units.test.sh 6b), and a
        # cycle terminates because an id is enqueued once.
        split("", reach)
        qn = 0
        d = dep[i]; gsub(/[ \t]/, "", d)
        m = split(d, a, ",")
        for (j = 1; j <= m; j++)
          if (a[j] != "" && a[j] ~ /[A-Za-z0-9]/ && !(a[j] in reach)) { reach[a[j]] = 1; q[++qn] = a[j] }
        h = 1
        while (h <= qn) {
          cur = q[h++]
          dd = alld[cur]
          m = split(dd, b, ",")
          for (j = 1; j <= m; j++)
            if (b[j] != "" && b[j] ~ /[A-Za-z0-9]/ && !(b[j] in reach)) { reach[b[j]] = 1; q[++qn] = b[j] }
        }
        for (x in reach) R[i, x] = 1
        for (k = 1; k <= n; k++) {
          if (id[k] in skip) continue
          if (stp[k] + 0 != 4) continue
          if ((i, id[k]) in R) continue
          M[i, k] = 1
        }
      }
    }
    function units_frontier(i,   k, e, j, fold, hit) {
      FR_IDS = ""; FR_CNT = 0; FR_FOLD = ""
      split("", FR_LIST)
      for (k = 1; k <= n; k++) {
        if (!((i, k) in M)) continue
        fold = 0
        for (e = 1; e <= nc; e++) {
          j = cand[e]
          if (j == i || !((j, k) in M)) continue
          if (((i, id[j]) in R) && !((j, id[i]) in R)) { fold = 1; break }
        }
        if (fold) continue
        # COLLECT ONE MISSING PREREQUISITE (tests/units.test.sh 14.7 plants a break after the next line)
        FR_IDS = FR_IDS (FR_IDS == "" ? "" : ", ") id[k]; FR_CNT++; FR_LIST[k] = 1
      }
      if (FR_CNT == 0) return 0
      for (e = 1; e <= nc; e++) {
        j = cand[e]
        if (j == i) continue
        if (!((j, id[i]) in R) || ((i, id[j]) in R)) continue
        hit = 0
        for (k in FR_LIST) if ((j, k) in M) { hit = 1; break }
        if (hit) FR_FOLD = FR_FOLD (FR_FOLD == "" ? "" : ", ") id[j]
      }
      return FR_CNT
    }
  '
}

# units_validate <plan> -> one line per broken invariant; exit 1 if any, else 0.
#
# `worktree` AND `base` EACH CARRY ONE INVARIANT, and both stop short of the machine: an
# `active` row must name a tree (§12), and a `base` cell, when it holds anything, must be a
# 7–40 hex commit id or one of the four spellings of "declared nothing" — em dash, hyphen,
# blank, empty (§13). Neither arm asks git whether the name or the id is real — this library
# stays a pure function of a file — so the gate that does fork git still judges at `current:`
# and says so when a name doesn't resolve, which is the fail-safe direction; a wall here would
# refuse plans for trees that had simply been torn down.
#
# THE INVARIANTS (spec Design §1 "Task", verbatim): id unique and matching `^T[0-9]+$`; step
# in 3–9; kind in build · test · verify · review · doc · integrate · close · prototype;
# status in pending · active · landed · dropped; every dep naming an id present in the table;
# and a Step-N row with N ≥ 5 depending TRANSITIVELY on every Step-4 row.
#
# EVERY LINE NAMES THE OFFENDING ID AND THE RULE, because the Step-3 wall prints these back
# to whoever tried to write the plan and "the table is invalid" is not a thing anyone can act
# on. Table-level faults — an absent section, a missing column — are named against
# `## Tasks`, since there is no row to blame.
#
# THE TRANSITIVE RULE reports EVERY Step-4 row, in table order, that the row fails to reach
# (wave-17 REQ-5, AC-5.2). It used to stop at the first, which made an unthreaded row cost
# one refused commit per missing edge — wave-16's A-orch-59 is the ten-edge specimen — and
# made this arm the one exception to the paragraph below. A row is a Step-4 row by its
# `step` cell alone: a row whose id is also malformed is still one, and naming it is more
# useful than silently exempting it. Reachability is keyed on the ID, so a duplicated id
# that the row reaches is reached in both of its rows.
#
# ONE LINE PER OFFENDING ROW, NOT PER MISSING EDGE (wave-20 REQ-5, AC-5.2; triage-C claim 3).
# `<id>: step <n> is missing <count> step-4 prerequisite(s): <ids>` — through 1.8.6 a row
# missing forty edges printed forty lines, and one mid-run row on a large table buried a
# one-edge fix under N×M of them. Only FRONTIER rows get a line: a row that reaches another
# offending row missing the same id is folded into that row's line, `(<rows> reach it through
# <id>)`, so the line count is the number of edits the author owes. `landed` and `dropped`
# rows are exempt. The closures and the fold are `_units_graph_awk`'s, above.
#
# EVERY FAULT IS REPORTED, not just the first. A writer fixing one line at a time against a
# wall that stops at the first complaint pays a round trip per fault.
units_validate() {
  local plan="${1:-}" out rc ctl missing cols over rows violations _c _o found=0 haswt

  out="$(_units_table "$plan")"; rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '## Tasks: no table found in %s\n' "${plan:-<no plan>}"
    return 1
  fi

  ctl="$(printf '%s\n' "$out" | awk 'NR == 1')"
  missing="$(printf '%s\n' "$ctl" | awk -F'\t' '{ sub(/^# */, "", $1); print $1 }')"
  cols="$(printf '%s\n' "$ctl" | awk -F'\t' '{ print $2 }')"
  over="$(printf '%s\n' "$ctl" | awk -F'\t' '{ print $3 }')"
  if [ -n "$missing" ]; then
    for _c in $missing; do
      printf '## Tasks: missing column %s\n' "$_c"
      found=1
    done
  fi

  # THE RAW PIPE, NAMED ONCE PER ROW — and it comes FIRST, before the per-row block, because
  # it is the cause and everything that row would otherwise be accused of is the symptom.
  # The repair is spelled out because `\|` is the only escape a GFM cell defines and nothing
  # else in this output could tell a reader that.
  for _o in $over; do
    printf '%s: %s cells for %s columns — a raw | inside a cell? escape it as %s\n' \
      "${_o%%=*}" "${_o##*=}" "$cols" '\|'
    found=1
  done

  # THE HEADER IS ASKED ONCE, HERE, AND THE ANSWER IS HANDED TO awk (wave-17 REQ-1, AC-1.2).
  # Slot 11 is optional, so `units_field` reads an ABSENT column as an empty cell on every
  # row — indistinguishable, inside the row loop, from a column that is there and blank. The
  # arm below must fire on the second and never on the first, and `units_has_column` is the
  # only reader that can tell them apart (its own docblock, wave-16 AC-3.2). Asked outside
  # the loop because it is a fact about the table, not about a row.
  haswt=0
  if units_has_column "$plan" worktree; then haswt=1; fi

  rows="$(printf '%s\n' "$out" | awk 'NR > 1')"
  if [ -n "$rows" ]; then
    violations="$(printf '%s\n' "$rows" | awk -F'\t' -v over="$over" -v haswt="$haswt" "$(_units_graph_awk)"'
      BEGIN {
        # EVERY CELL OF A SHIFTED ROW IS SUSPECT, so the row is neither accused nor used to
        # accuse: its step cell cannot be trusted to make it a Step-4 row others must reach.
        # It stays a legal dependency TARGET — slot 1 is before any shift, so its id is the
        # one cell a raw pipe cannot move.
        m0 = split(over, o0, " ")
        for (i0 = 1; i0 <= m0; i0++) { sub(/=.*$/, "", o0[i0]); if (o0[i0] != "") skip[o0[i0]] = 1 }
        split("build test verify review doc integrate close prototype", kk, " ")
        for (i in kk) kinds[kk[i]] = 1
        split("pending active landed dropped", ss, " ")
        for (i in ss) states[ss[i]] = 1
      }
      $1 == "" { next }
      { n++; id[n] = $1; stp[n] = $2; knd[n] = $3; dep[n] = $6; sta[n] = $10; wtc[n] = $11
        bsc[n] = $12; count[$1]++ }
      END {
        for (i = 1; i <= n; i++) {
          if (id[i] in skip) continue
          # IDs. Duplicate is reported once, on the second occurrence.
          if (id[i] !~ /^T[0-9]+$/)
            printf "%s: id does not match ^T[0-9]+$\n", id[i]
          seen[id[i]]++
          if (seen[id[i]] > 1 && !dup[id[i]]) { dup[id[i]] = 1; printf "%s: duplicate id\n", id[i] }

          if (stp[i] !~ /^[0-9]+$/ || stp[i] + 0 < 3 || stp[i] + 0 > 9)
            printf "%s: step %s is outside 3-9\n", id[i], (stp[i] == "" ? "(empty)" : stp[i])

          if (!(knd[i] in kinds))
            printf "%s: kind %s is not one of build test verify review doc integrate close prototype\n", \
              id[i], (knd[i] == "" ? "(empty)" : knd[i])

          if (!(sta[i] in states))
            printf "%s: status %s is not one of pending active landed dropped\n", \
              id[i], (sta[i] == "" ? "(empty)" : sta[i])

          # THE ROW IS THE RECORD OF THE TREE (wave-17 REQ-1, AC-1.2, D2, ADR-032).
          # `active` means a writer is in a tree right now, and the evidence gate resolves
          # that writer commit by matching the basename of this very cell — so a row that
          # claims a writer and names no tree makes the gate fall through and judge a task
          # commit by the arms of the run. Through wave-16 that was every row of every plan
          # this repo shipped (research R1), and the only symptom was an orchestrator
          # regressing `current:` by hand. Reported at the WRITE, the one place that can
          # still fix it cheaply.
          #
          # NAMES NO TREE IS THE ABSENCE OF AN ALPHANUMERIC, not equality with the em dash:
          # an em dash, a hyphen, a space and an empty cell are one fact spelled four ways,
          # and `deps` already reads its own "none" exactly this way two arms down. A real
          # basename cannot be alphanumeric-free.
          #
          # ONLY `active`. A `pending` row has no tree yet, a `landed` or `dropped` one may
          # have had its tree torn down (close-out does exactly that), and refusing either
          # would refuse the ordinary end state of every wave.
          # NO APOSTROPHE ANYWHERE ABOVE: this comment is inside the single-quoted awk
          # program, and one would close the quote (the header note says so).
          if (haswt == 1 && sta[i] == "active" && wtc[i] !~ /[A-Za-z0-9]/)
            printf "%s: active row names no worktree\n", id[i]

          # THE ORIGIN IS DECLARED BESIDE THE IDENTITY (wave-17 REQ-2, AC-2.1, D3, ADR-032).
          # Slot 12 is the commit the tree was cut from, as spawn-worktree.sh printed it, and
          # the landing gate takes it as the diff base. A cell that is not a commit id would
          # send that gate to `git merge-base <junk> HEAD`, which fails silently and lands the
          # tree on the announced fallback — the record would be wrong and the gate would
          # never say so. Checked here, at the write, for the same reason the worktree arm is.
          #
          # NO COLUMN QUESTION IS ASKED, unlike the worktree arm two lines up. That arm has to
          # tell an absent column from a blank cell because it fires on ABSENCE; this one fires
          # only on a cell that HOLDS something, and an absent column reads empty on every row.
          #
          # DECLARING NOTHING IS LEGAL. An em dash, a hyphen, a space and an empty cell are one
          # fact spelled four ways (the deps cell reads its own none this way), and a row with
          # no declared origin is exactly what the landing gate announces its fallback for.
          #
          # LENGTH RATHER THAN A BOUNDED REPETITION: an interval like {7,40} is not portable
          # across the awks this fleet runs under, and the two comparisons say the same thing.
          if (bsc[i] ~ /[A-Za-z0-9]/ \
              && (bsc[i] !~ /^[0-9a-fA-F]+$/ || length(bsc[i]) < 7 || length(bsc[i]) > 40))
            printf "%s: base %s is not a commit id\n", id[i], bsc[i]

          d = dep[i]
          gsub(/[ \t]/, "", d)
          if (d ~ /[A-Za-z0-9]/) {
            m = split(d, a, ",")
            for (j = 1; j <= m; j++) {
              if (a[j] == "" || a[j] !~ /[A-Za-z0-9]/) continue
              if (!(a[j] in count)) printf "%s: dep %s names no row in the table\n", id[i], a[j]
            }
          }
        }

        # THE TRANSITIVE RULE, ONE LINE PER OFFENDING ROW (wave-20 REQ-5, AC-5.2). The
        # closures and the frontier are `_units_graph_awk`s, the one definition this verb
        # and `units_add_row` share; this loop only prints what they found.
        units_graph()
        for (c = 1; c <= nc; c++) {
          i = cand[c]
          if (units_frontier(i) == 0) continue
          printf "%s: step %s is missing %d step-4 prerequisite%s: %s%s\n", id[i], stp[i], \
            FR_CNT, (FR_CNT == 1 ? "" : "s"), FR_IDS, \
            (FR_FOLD == "" ? "" : " (" FR_FOLD " reach " (FR_CNT == 1 ? "it" : "them") " through " id[i] ")")
        }
      }')"
    if [ -n "$violations" ]; then
      printf '%s\n' "$violations"
      found=1
    fi
  fi

  [ "$found" -eq 0 ]
}

# units_add_row <plan> <id> <step> <kind> <task> <agent> <deps> <size> <serves> <Files>
#   -> the WHOLE plan with one `## Tasks` row added, on stdout; exit 1 and silent when the plan
#      carries no `## Tasks` table or no `## SDLC State` section. Nothing is written.
#
# THE PROJECTOR UNDER `task-add` (wave-20 REQ-5, AC-5.3; Δ5). A mid-run row needs three edits
# to pass the two walls that read the table (memory note: mid-run task row needs evidence and
# deps), and a hand edit that forgets one stalls every writer in the wave at its next commit:
#
#   1. THE ROW, as the table's last data row, cells placed by the HEADER's column order (the
#      table is header-keyed, so the projection follows whatever order this plan carries);
#      status `pending`, and `—` for `worktree`, `base` and any column this library does not
#      read. A `|` inside a value is written `\|`, the one escape a GFM cell defines.
#   2. ITS `- <id>:` LINE under `## SDLC State`, after the last `- T<n>:` line and that line's
#      indented continuation — or at the end of the section when the plan carries none yet.
#      `pending dispatch — added by task-add at <iso>` is not a placeholder to the evidence
#      gate (`is_placeholder_value` refuses only the bare words).
#   3. FOR A STEP-4 ROW, THE THREADING: the id appended to the `deps` cell of every FRONTIER
#      row that owes it — `_units_graph_awk`'s answer, the same one `units_validate` prints —
#      so the projection is threaded exactly as far as the validator demands and no further.
#      A row at any other step threads nothing: the only ordering rule is Step-5+ reaching
#      every Step-4 row.
#
# PURE, AS EVERY VERB HERE IS: it prints and never writes, so `task-add` can judge the
# projection (the validator, then a dry commit through the real gate) before anything is
# swapped in, and a refusal leaves the plan byte-identical. Fence-aware like `_units_read`:
# a table or a state line inside a ``` example is documentation and is never edited.
units_add_row() {
  local plan="${1:-}" nid="${2:-}" nstep="${3:-}" thread="" now
  [ -n "$plan" ] && [ -f "$plan" ] || return 1
  _units_table "$plan" >/dev/null 2>&1 || return 1
  if [ "$nstep" = 4 ]; then
    thread="$( { units_rows "$plan"; printf '%s\t%s\t\t\t\t%s\t\t\t\tpending\t\t\n' "$nid" "$nstep" "${7:-}"; } \
      | awk -F'\t' -v newid="$nid" "$(_units_graph_awk)"'
        $1 == "" { next }
        { n++; id[n] = $1; stp[n] = $2; dep[n] = $6; sta[n] = $10 }
        END {
          units_graph()
          kx = 0
          for (k = 1; k <= n; k++) if (id[k] == newid) kx = k
          if (kx == 0) exit 0
          for (c = 1; c <= nc; c++) {
            i = cand[c]
            units_frontier(i)
            if (kx in FR_LIST) printf "%s ", id[i]
          }
        }')"
  fi
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  awk -v nid="$nid" -v nstep="$nstep" -v nkind="${4:-}" -v ntask="${5:-}" -v nagent="${6:-}" \
      -v ndeps="${7:-}" -v nsize="${8:-}" -v nserves="${9:-}" -v nfiles="${10:-}" \
      -v thread=" $thread " -v now="$now" '
    function trim(v) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); return v }
    # A VALUE BECOMES A CELL: tabs and line breaks to spaces, every `|` escaped by
    # concatenation (a backslash in a gsub replacement is the one character awks disagree on),
    # and an empty value spelled `—`, which is how the table itself writes "none".
    function cellv(v,   parts, m, i, out) {
      gsub(/[\t\r\n]/, " ", v); v = trim(v)
      m = split(v, parts, "|"); out = parts[1]
      for (i = 2; i <= m; i++) out = out "\\" "|" parts[i]
      return (out == "" ? "—" : out)
    }
    # A CELL IS SPLIT ON THE UNESCAPED PIPE ONLY: `\|` is folded to SUBSEP first and restored
    # verbatim, so a row this projection rewrites keeps every escape it carried.
    function esc(v)   { gsub(/\\[|]/, SUBSEP, v); return v }
    function unesc(v,   parts, m, i, out) {
      m = split(v, parts, SUBSEP); out = parts[1]
      for (i = 2; i <= m; i++) out = out "\\" "|" parts[i]
      return out
    }
    { L[++nl] = $0 }
    END {
      state = 0; sdlc = 0
      for (i = 1; i <= nl; i++) {
        line = L[i]
        if (line ~ /^[ \t]*```/) { fence = !fence; continue }
        if (fence) continue
        if (line ~ /^##[ \t]/) {
          if (tstate == 2 || tstate == 1) tstate = 3
          if (sdlc == 1) sdlc = 2
          if (!seensdlc && line ~ /^##[ \t]+SDLC State([ \t].*)?$/) { sdlc = 1; seensdlc = 1; sdlc_head = i; sdlc_last = i; continue }
          if (!seentasks && line ~ /^##[ \t]+[Tt]asks([ \t].*)?$/) { tstate = 1; seentasks = 1 }
          continue
        }
        if (sdlc == 1) {
          if (line ~ /[^ \t]/) sdlc_last = i
          if (line ~ /^[ \t]*-?[ \t]*T[0-9]+[ \t]*:/) { tline = i; intl = 1; continue }
          if (intl && line ~ /^[ \t]+[^ \t]/ && line !~ /^[ \t]*-/) { tline = i; continue }
          intl = 0
        }
        if (tstate == 1) {
          if (line !~ /^[ \t]*\|/) continue
          nh = split(esc(line), hc, "|")
          for (c = 1; c <= nh; c++) {
            t = tolower(trim(hc[c]))
            if (t != "" && !(t in col)) { col[t] = c; name[c] = t }
          }
          if (!("id" in col)) { split("", col); split("", name); continue }
          tstate = 2; continue
        }
        if (tstate == 2) {
          if (line !~ /^[ \t]*\|/) { tstate = 3; continue }
          lastrow = i                   # the separator counts: an empty table takes its first row
          m = split(esc(line), f, "|")
          rid = trim(f[col["id"]])
          if (rid == "" || rid ~ /^[-: ]+$/) continue
          if (("deps" in col) && index(thread, " " rid " ") > 0) {
            dc = col["deps"]; d = trim(f[dc])
            f[dc] = " " ((d ~ /[A-Za-z0-9]/) ? d ", " nid : nid) " "
            out = f[1]; for (c = 2; c <= m; c++) out = out "|" f[c]
            L[i] = unesc(out)
          }
        }
      }
      if (!lastrow || !seensdlc) exit 1
      val["id"] = nid; val["step"] = nstep; val["kind"] = nkind; val["rigor"] = nkind
      val["task"] = ntask; val["agent"] = nagent; val["deps"] = ndeps; val["size"] = nsize
      val["serves"] = nserves; val["files"] = nfiles; val["status"] = "pending"
      row = "|"
      for (c = 2; c < nh; c++) row = row " " ((name[c] in val) ? cellv(val[name[c]]) : "—") " |"
      at = (tline ? tline : sdlc_last)
      for (i = 1; i <= nl; i++) {
        print L[i]
        if (i == at) printf "- %s: pending dispatch — added by task-add at %s\n", nid, now
        if (i == lastrow) print row
      }
    }' "$plan"
}
