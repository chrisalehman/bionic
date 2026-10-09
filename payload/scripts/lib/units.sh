#!/bin/bash
# payload/scripts/lib/units.sh — THE ONE READER OF THE PLAN'S `## Tasks` TABLE.
#
# WHAT IT OWNS (epic-23 wave-11-lean-spine, REQ-1e; spec Design §1 "Task", §2 D3/D7, §3
# ownership row "Tasks schema"). The schedule every wave runs on — one row per unit of work
# at Steps 3–9 — and the three questions asked of it. Pure functions of a file; nothing here
# writes, and nothing here runs at source time:
#
#   units_rows <plan>          one TSV line per row, the thirteen fields in the FIXED order
#                              id·step·kind·task·agent·deps·size·serves·Files·status·worktree·
#                              base·reads, in TABLE order. Exit 1 and silent when the plan
#                              carries no `## Tasks` table.
#   units_ready <plan> <step> [<roster> [<ack ledger> [<session id>]]]
#                              the ids of rows whose status is `pending` and whose every read
#                              is satisfied, whatever their step (wave-26 T2, D1: what a row
#                              reads is its `reads` cell or kind default, or in a table
#                              without that column its `deps` ids); a row of kind `integrate`
#                              or `close`, or a `doc` row at Step 7 or later (the release),
#                              also waits until <step> reaches its own (wave-20 Δ6, T10b); a
#                              row open on <roster> is left out (D9). One per line, table
#                              order. <step> is a number (wave scale) or `T<n>` (task scale,
#                              where the rows carry no step cell and a dependency is satisfied
#                              by `done`). Exit 2 on anything else.
#   units_held <plan> <step>   one line per row held for its step (would be ready but for
#                              it): `<id>: step <n> <kind> row waits for current: <n>`, and
#                              one per row held by an external prerequisite (every other read
#                              satisfied, one or more `ext:<slug>` tokens left):
#                              `<id>: held by ext:<a> [ext:<b> ...]`. A report, never an
#                              invariant (wave-20 T10b; wave-21 T4).
#   units_waiting <plan> <step>
#                              `<id><TAB><unmet read><TAB><writer id or -><TAB><writer status
#                              or ->` for every pending row that is not ready (wave-26 T2, D9).
#   units_edges <plan>         `<from id><TAB><to id><TAB><the read that joins them>`, one per
#                              wait between two open rows (wave-26 T2, D1).
#   units_validate <plan>      one line per broken invariant, each naming the offending id
#                              and the rule. Exit 1 if any line was printed, else 0.
#   units_findings <plan> <roster>
#                              one line per ledger finding — `status <id> <value>`,
#                              `evidence <id>`, `launch <id> <agent>` — the one reader the
#                              commit gate and the Patrol tick share (wave-21 T5; D4). Exit 1
#                              if any line was printed, else 0.
#   units_unlined <plan>       the T-ids with no non-empty `- <id>:` line under
#                              `## SDLC State`, whatever their status (wave-21 T5).
#   units_add_row <plan> <id> <step> <kind> <task> <agent> <deps> <size> <serves> <Files> [<reads>]
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
# THE RECORD IS ALWAYS THIRTEEN FIELDS WIDE (`worktree`, `base` and, since wave-26 T2, `reads`
# are the three optional slots) even when a column is absent, because a record
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
      disp[13] = "reads"
      for (k = 1; k <= 13; k++) want[k] = tolower(disp[k])
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
        for (k = 1; k <= 13; k++) if ((t == want[k] || t == alt[k]) && col[k] == 0) col[k] = i
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
      for (k = 1; k <= 13; k++) {
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
      # THE LOOP STOPS AT 10, NOT 13: slots 11 (`worktree`), 12 (`base`) and 13 (`reads`) are optional,
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
      for (k = 1; k <= 13; k++) if (col[k] > 0) present = (present == "") ? disp[k] : present " " disp[k]
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
#
# A MEMO ALREADY LIVE FOR THE SAME PLAN IS KEPT (wave-21 T13). A caller that memoises a plan
# and then reaches a verb that memoises it again — the tick's schedule reaching
# `fill_ready_set`, or `units_findings` — runs the inner command on the outer parse rather than
# reading the table a second time. The outer command is still running, so the answer is the
# same read the outer command already holds.
#
# THE FLOOR STATE IS THE COMMAND'S TOO (wave-26 T64). `_UNITS_MEMO_FLOOR` names a file, written
# the first time a question inside the command needs `proof_state` and read by every later one,
# subshells included; it is removed when the command returns. A command that never needs the
# state never writes it. A caller that already names one (the tick, for its whole run) keeps it,
# and removes it itself.
units_memoised() {  # <plan> <command> [args...]
  if [ -n "${_UNITS_MEMO_PLAN:-}" ] && [ "$_UNITS_MEMO_PLAN" = "${1:-}" ]; then
    shift
    "$@"
    return
  fi
  local _UNITS_MEMO_PLAN="" _UNITS_MEMO_OUT="" _UNITS_MEMO_RC=1 _UNITS_MEMO_FLOOR="${_UNITS_MEMO_FLOOR:-}" own="" rc
  _UNITS_MEMO_OUT="$(_units_read "${1:-}")"; _UNITS_MEMO_RC=$?
  _UNITS_MEMO_PLAN="${1:-}"
  if [ -z "$_UNITS_MEMO_FLOOR" ]; then
    _UNITS_MEMO_FLOOR="${TMPDIR:-/tmp}/bionic-units-floor-$$-${RANDOM}${RANDOM}"; own=1
  fi
  shift
  "$@"; rc=$?
  [ -z "$own" ] || [ ! -e "$_UNITS_MEMO_FLOOR" ] || rm -f "$_UNITS_MEMO_FLOOR"
  return "$rc"
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
    worktree) n=11 ;; base) n=12 ;; reads) n=13 ;;
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


# units_rows <plan> -> id·step·kind·task·agent·deps·size·serves·Files·status·worktree·base·reads,
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

# units_ready <plan> <step> [<roster> [<ack ledger> [<session id>]]]
#   -> the ids that may be dispatched now, one per line, table order.
#
# READY = status `pending` and EVERY READ SATISFIED (wave-26 T2; D1, ADR-043) — whatever the
# row's step. What a row reads depends on the table's shape:
#
#   - A TABLE WITH A `reads` COLUMN. The row reads its `reads` cell, comma-separated: a path in
#     the `Files` grammar · `head` · `record` · `proof:<kind>` · `approval:<name>` ·
#     `ext:<slug>`, or `live:<artifact>`. An EMPTY cell takes the row's kind default, never
#     "nothing": build `approval:plan` · verify and test `approval:plan, head` · review
#     `approval:plan, live:head` · doc `approval:plan, head` · integrate `proof:floor,
#     proof:review, head` · close `merge` (the integrate row's merge) · prototype `approval:plan`.
#     A doc row at Step 7 or later is the release and names an `approval:` read; one that names
#     none reads `approval:release` besides (`units_validate` refuses it; wave-26 T62, K2-F3).
#     Its `deps` cell may carry `ext:<slug>` and nothing else (`units_validate` refuses an id).
#   - A TABLE WITHOUT ONE. Each `deps` id reads as "wait for that task to land", exactly as
#     through 1.10, and no kind default applies: a plan written before the column schedules as
#     it always did. `ext:<slug>` is valid there too.
#
# A SETTLED READ waits for every open (`pending` or `active`) row that writes what it names,
# the row itself never counted:
#   - a path: every open row with a `Files` entry that covers it or that it covers — exact,
#     directory prefix, glob or path suffix, the `in_files` rule of brief.sh, never string
#     equality alone;
#   - `head`: every open row with a `Files` path outside the record, EXCEPT a row that itself
#     reads the settled `head`: such a row is downstream of the head, and counting it a writer
#     would make the walk wait for the release and the release for the walk (A-T2.4);
#   - `record`: the same over paths in the record (`.bionic/…`, or `record/…` spelled from the
#     docs root), excepting rows that read `record`;
#   - `merge`: every open integrate row;
#   - a task id (a table without `reads`): that row, until it lands;
#   - `proof:<kind>`: a `proved: kind=<kind>` line inside `## SDLC State`; until one exists the
#     open rows that would write it — verify and test rows for `floor`, review rows for
#     `review` — are named as its writers. A pending row whose `live:head` waits because
#     nothing landed past the review proof writes no newer proof, so it is not one (wave-26
#     T62; K2-F4): the last review of a run returns its row to pending, and integrate would
#     otherwise wait on it for ever. A FLOOR PROOF STANDS ONLY WHILE THE PASS DOES (wave-26 T64;
#     REQ-3 AC-3.4): with no open writer, `proof:floor` is satisfied when lib/proof.sh
#     `proof_state` answers `covered` or `bounded`, and waits on `unbounded` — a merge from
#     outside the run, a change the map answers with every suite or a file it answers with none,
#     or a state that cannot be computed — saying `proof:floor: the head moved past the floor
#     proof at <12 hex> in a way the map cannot bound (<its reason>); take the full run on this
#     head and record it with proof-add floor`. The state is asked only when a pending row's
#     answer turns on it, a row held for its step is judged without it, and inside
#     `units_memoised` it is asked once; `proof:review`, with no open writer, is satisfied only
#     when the UNITS_FACTS_STATE handed in reads `covered` (wave-27 T14; D3): a reading line, a
#     failing one included, is not enough;
#   - `approval:<name>`: its line inside `## SDLC State` — `approved-by:` for `plan`,
#     `approved: <name> …` otherwise. No row writes one; the user's act does.
#   - `ext:<slug>`: never, until its owner removes it from the cell.
# A writer that has LANDED or been DROPPED satisfies the read: a dropped row writes nothing
# (through 1.10 a dependency on a dropped row held its dependents for ever; A-T2.3). A token
# that names none of these is never satisfied — the cautious direction, the one `slice_ready`
# documented: a row held back costs a batch, a row dispatched early costs a writer's run.
#
# A LIVE READ, `live:<artifact>`, is satisfied by what exists and waits for nobody: the record
# always exists, a proof or an approval once its line is written, a path unless only open rows
# write it. A token that names none of these (`live:foo`, `live:ext:ci`, `live:T9`) is never
# satisfied (review 5 F4). `live:head` IS A REVIEW THAT FOLLOWS THE BUILD (wave-26 T14; D10):
# it is satisfied when landed work exists that the last `proved: kind=review` line has not read,
# and no other row of the same kind is open — none active, and no pending `live:head` row of
# that kind above it, so one pass runs at a time and the first goes first. "Past the last proof"
# compares the proof line's `head=` with THE WORKING BRANCH'S HEAD NOW, which this program does
# not fetch: the caller sets UNITS_LIVE_HEAD (the Patrol tick reads it from git; the stop wall
# sets none). A plan with no review proof yet needs no head: the first review is ready once a
# row writing outside the record has landed. With a proof and no head handed in, nothing past
# the proof can be seen, so the row waits (the cautious direction, as below). Each wait names
# why after the read: `live:head: nothing has landed yet`, `…: nothing landed past the review
# proof at <12 hex>`, `…: the head past the review proof at <12 hex> is not known here`,
# `…: review T5 is open (active)`, `…: review T3 goes first`. `units_live_range` prints the
# difference a ready review reads; `units_live_rows` the rows `proof-add review` returns to
# `pending`.
#
# AN UNMERGEABLE PATH HOLDS A ROW (D11). Rows that write one file run side by side and reconcile
# on landing; a `Files` entry ending in `!` cannot be reconciled, so a pending row is held while
# another open row declares an overlapping path and either side marks it: by an active row
# always, by a pending row only one above it in table order — two pending rows never hold each
# other for ever, and the first goes first.
#
# <step> STILL DECIDES THE GATE ACTS (wave-20 Δ6, T10b). A row of kind `integrate` or `close`,
# or — in a table WITHOUT the `reads` column — a `doc` row at Step 7 or later (the release), is
# ready only once <step> has reached its own step. In a table with the column a doc row waits for
# its reads like any row, the release for `approval:release` (wave-26 T13; D3, A-T13.1). TWO TABLE SHAPES, ONE ANSWER (wave-18 REQ-3, AC-3.3; ADR-033): passed `T<n>`, only
# task-scale rows (no step cell) are judged and a task dependency is satisfied by `done`. Any
# other <step> is a caller fault and exits 2; no table exits 1.
#
# ROWS OPEN ON THE ROSTER ARE NOT READY (D9). The launch recorder moves a launched row to
# `active`, but a table read between the launch and that write still says `pending`. Given a
# <roster>, the ids it holds open are subtracted: the open names are `roster_open_names`', and
# an id is open when `fill_row_launched` says a name is that row's — the one id-to-name rule the
# stop wall and the launch recorder already share. Both live beside this file and are sourced on
# first use; a caller that passes no roster is answered from the table alone.
units_ready() {
  local out rc open="" nm id
  out="$(_units_sched ready "${1:-}" "${2:-}")"; rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  [ -n "$out" ] || return 0
  if [ -n "${3:-}" ] && _units_roster_libs; then
    while IFS= read -r nm; do
      [ -n "$nm" ] && open="${open:+$open,}$nm"
    done <<UNITS_OPEN
$(roster_open_names "$3" "${4:-}" "${5:-}")
UNITS_OPEN
  fi
  [ -n "$open" ] || { printf '%s\n' "$out"; return 0; }
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    fill_row_launched "$id" "$open" && continue
    printf '%s\n' "$id"
  done <<UNITS_READY
$out
UNITS_READY
  return 0
}

# _units_roster_libs -> 0 once `roster_open_names` and `fill_row_launched` are defined, sourcing
# roster.sh and fill.sh from this file's own directory when they are not. fill.sh sources this
# file only when `units_ready` is undefined, so the pair cannot loop.
_units_roster_libs() {
  local d
  declare -F roster_open_names >/dev/null 2>&1 && declare -F fill_row_launched >/dev/null 2>&1 && return 0
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || return 1
  if ! declare -F roster_open_names >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    . "$d/roster.sh" >/dev/null 2>&1 || return 1
  fi
  if ! declare -F fill_row_launched >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    . "$d/fill.sh" >/dev/null 2>&1 || return 1
  fi
  declare -F roster_open_names >/dev/null 2>&1 && declare -F fill_row_launched >/dev/null 2>&1
}

# units_held <plan> <step> -> one line per row HELD FOR ITS STEP or BY THE WORLD, table order
# (wave-20 T10b; wave-21 T4): `<id>: step <n> <kind> row waits for current: <n>` for a gate act
# that would be ready but for its step, and `<id>: held by ext:<a> [ext:<b> …]` for a row whose
# every other read is satisfied and one or more `ext:` tokens remain. A row waiting on anything
# else is not named here — `units_waiting` says why. A REPORT, never an invariant; the tick
# prints these as `HELD` lines and the stop wall never counts the row as a missed fill.
units_held() { _units_sched held "$@"; }

# units_waiting <plan> <step> -> `<id><TAB><unmet read><TAB><writer id or -><TAB><writer status
# or ->`, one line per unmet read and writer, for every pending row that is not ready (D9).
# A read with several open writers prints one line per writer; one nobody in the table writes
# (an approval, `ext:`, a proof with no open writer, an unknown token) prints `-` for both. A
# gate act held for its step prints `step:<n>` first; an unmergeable hold prints the marked path
# (`lib/x.sh!`) with its holder. Same <step> rules as `units_ready`; a row open on the roster is
# not subtracted here (the verb takes no roster).
# A live read that waits on no row prints why after the read: `live:head: <why>` (wave-26 T14).
units_waiting() { _units_sched waiting "$@"; }

# units_edges <plan> -> `<from id><TAB><to id><TAB><the read that joins them>`, one per line,
# table order of <to>: every place an open row waits on another open row — a settled read the
# writer has not yet satisfied, or an unmergeable hold. Never stored; computed on every read of
# the table (D1). A live read is never an edge, a gate act's step hold is not one, and a landed
# or dropped row is at neither end: what has landed holds nobody, so the graph is the work that
# remains — the shape `units_chain` takes.
units_edges() { _units_sched edges "${1:-}" ""; }

# units_live_range <plan> [<row id>] -> `<last review proof head>..<UNITS_LIVE_HEAD>`, the
# difference a `live:head` review reads (wave-26 T14; AC-6.5): only what landed past the last
# review, never the whole diff again. Nothing when the plan has no review proof yet (the first
# review reads all the landed work, from the wave's base), when no head is handed in, or when the
# head has not moved past the proof. GIVEN A READ ROW (wave-27 T10; D4), one reading
# `live:head:<q>[+<q>]`, the range is that row's, and nothing while one of its questions has no
# reading yet (it reads from the base). A bare `live:head` row, an unknown id or none gets the one
# range above.
# A READ ROW'S START IS THE OLDEST BY COMMIT ANCESTRY (wave-27 T43; review pass 17 F2), never by
# line order: of the last heads of its questions not read at the head asked, the one that is an
# ancestor of every other. A last head that is no ancestor of the head asked, or names no commit,
# counts as no reading, and so do heads on two lines of history with no such start: no range, the
# row reads from the base. A reversed range is never printed. The program hands those last heads
# out (`range` mode) and `_units_live_start` asks git, here and not in the program, which stays a
# function of the plan (A-T10.1); only a caller that already reads git asks for a row id.
units_live_range() {
  local out
  out="$(_units_sched range "${1:-}" "${2:-}")" || return $?
  case "$out" in
    '') return 0 ;;
    *..*) printf '%s\n' "$out" ;;
    *) _units_live_start "$(_units_plan_tree "${1:-}")" "$out" ;;
  esac
}

# _units_live_start <tree> <last heads, one per line> -> `<start>..<UNITS_LIVE_HEAD>`, or nothing:
# the start is the head that is an ancestor of every other, each an ancestor of the head handed
# in and not that head. Any git that cannot answer is no reading: no range (the cautious side).
_units_live_start() {
  local tree="$1" h c d s="" ok n=0
  h="$(git -C "$tree" rev-parse --verify -q "${UNITS_LIVE_HEAD:-}^{commit}" 2>/dev/null)" || return 0
  for c in $2; do
    d="$(git -C "$tree" rev-parse --verify -q "$c^{commit}" 2>/dev/null)" || return 0
    [ "$d" = "$h" ] && continue
    git -C "$tree" merge-base --is-ancestor "$d" "$h" 2>/dev/null || return 0
    n=$((n + 1))
  done
  [ "$n" -gt 0 ] || return 0
  for c in $2; do
    [ "$(git -C "$tree" rev-parse --verify -q "$c^{commit}" 2>/dev/null)" = "$h" ] && continue
    ok=1
    for d in $2; do git -C "$tree" merge-base --is-ancestor "$c" "$d" 2>/dev/null || { ok=0; break; }; done
    [ "$ok" = 1 ] && { s="$c"; break; }
  done
  [ -n "$s" ] && printf '%s..%s\n' "$s" "$(printf '%s' "$UNITS_LIVE_HEAD" | tr 'A-F' 'a-f')"
  return 0
}

# _units_plan_tree <plan> -> the tree a plan's git questions are put to: the project root it sits
# under (`<root>/.bionic/…`), or the plan's own directory, whose repository git finds. The root is
# the one nearest the plan: a project kept under another one's `.bionic/` (a scratch fixture) is
# its own repository, not the outer one (wave-27 T43).
_units_plan_tree() {
  case "${1:-}" in
    */.bionic/*) printf '%s' "${1%/.bionic/*}" ;;
    .bionic/*) printf '.' ;;
    */*) printf '%s' "${1%/*}" ;;
    *) printf '.' ;;
  esac
}

# units_live_rows <plan> [--question <q>] [<path>...] -> `<id><TAB><kind><TAB><status>` for every
# row reading `live:head`, an empty cell's kind default and `live:head:<q>[+<q>]` included, table
# order (wave-26 T14). Handed paths, only the rows whose `Files` cover one of them (the overlap rule
# a read uses): `proof-add review` hands its evidence, in both spellings, and returns that row alone
# to `pending` — the proof of another review (the final one, settled on the head) moves no live row
# mid-pass (wave-26 T46; review 10 F3). HANDED A QUESTION (wave-27 T10; D4), a read row is named
# when it carries that question, whatever its `Files` say, and not otherwise; a row naming no
# question is still matched by its `Files`. AND A READER (wave-27 T43; review pass 17 F3), the
# rows that reader's reading returns: a read row only when its `agent` cell is that reader and
# every question it carries was last read at the head of this question's last reading, so a row
# with two questions returns on the second; a bare row by its `Files`, as before.
units_live_rows() {
  local plan="${1:-}" q="" r=""; shift
  if [ "${1:-}" = --question ]; then q="${2:-}"; shift 2 2>/dev/null || shift; fi
  if [ "${1:-}" = --reader ]; then r="${2:-}"; shift 2 2>/dev/null || shift; fi
  _UNITS_EVIDENCE="$*" _UNITS_QUESTION="$q" _UNITS_READER="$r" _units_sched liverows "$plan" ""
}

# A READ AFTER A FIX IS TOLD WHAT MOVED (wave-27 T43; D10; A-orch-48, A-orch-71). Once a question has
# its `scope=whole` reading, a later read of it covers the fixes that landed past that reading, and
# the tick names them beside the RANGE line. A row's landing is read from the run's LANDING RECORD,
# `<docs-root>/record/<plan name>/landing-proofs.log`, which `land` appends (T44): one header line
# per landing, `landed: row=<id|—> branch=<b> head=<40-hex> merge=<40-hex> at=<ISO-UTC>`, with
# `stamp/v1|…` lines under it. A row's landing is the `merge=` of the LAST header carrying its row.
# Never the prose of a state line, and never git: which merges lie inside a range is the caller's
# answer (the tick's, which already reads git), handed in on stdin.
#
# units_whole_read <plan> <row id> -> exit 0 when the row reads `live:head:<q>[+<q>]` and every one
# of its questions has a `scope=whole` reading; 1 otherwise, a bare row included (it names none).
units_whole_read() {
  [ "$(_units_sched whole "${1:-}" "${2:-}" 2>/dev/null)" = whole ]
}

# units_landings <plan> <record> -> `<row id><TAB><merge or -><TAB><owed or ->`, table order: each
# `## Tasks` row the record names, with its last merge, and each `build` row that is `landed` or
# `done` with none, as `-`. `owed` marks a landed or done build row: it must carry a landing, so the
# caller counts it unknown when the record has none or its merge is no commit. A header whose
# `row=` is `—` or an id the table lacks names no row; a merge that is not hex is no landing.
units_landings() { _units_landed landings "${1:-}" "" "${2:-}" < /dev/null; }

# units_rows_in_range <plan> <a>..<b> <record> -> `<row id><TAB><serves><TAB><criteria>` for each
# row whose landing is one of the merges on stdin (one per line: those the caller found inside
# <a>..<b>), table order; criteria are the `## Verification Matrix` rows of each requirement it
# serves, `AC-<n>.<m>` for `REQ-<n>`, comma-joined. Nothing, exit 0, when none is; exit 2 when the
# range is not `<a>..<b>`.
units_rows_in_range() {
  case "${2:-}" in ?*..?*) ;; *) return 2 ;; esac
  _units_landed inrange "${1:-}" "${2:-}" "${3:-}"
}

# units_unrecorded <plan> <record> -> each commit on stdin (one per line: the range's first-parent
# commits, the caller's one `git rev-list`) that is the `merge=` of no header naming a row of the
# plan, in the order given (wave-27 T34; review pass 30 should-fix 1 and 2, A-orch-86). A header
# with `row=—` or an id the table lacks names no row; a merge of 7 to 40 hex names the commit it is
# a prefix of. The tick prints the MOVED list only when this prints nothing.
units_unrecorded() { _units_landed unrecorded "${1:-}" "" "${2:-}"; }

# _units_landed <landings|inrange> <plan> <range> <record> — the one program behind the two verbs:
# the rows (`units_rows`), the record's header lines, the plan's matrix, then stdin's merges.
_units_landed() {
  local mode="$1" plan="$2" rec="$4" rows
  rows="$(units_rows "$plan" 2>/dev/null)" || return 1
  {
    printf '\034rows\n'; printf '%s\n' "$rows"
    printf '\034rec\n'; [ -f "$rec" ] && awk '{ sub(/\r$/, ""); print }' "$rec" 2>/dev/null
    printf '\034plan\n'; awk '{ sub(/\r$/, ""); print }' "$plan" 2>/dev/null
    printf '\034in\n'; [ "$mode" = landings ] || cat
  } | awk -F'\t' -v mode="$mode" '
    function trim(v) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); return v }
    $0 == "\034rows" { part = 1; next }
    $0 == "\034rec" { part = 2; next }
    $0 == "\034plan" { part = 3; next }
    $0 == "\034in" { part = 4; next }
    part == 1 { if ($1 == "") next; n++; id[n] = $1; knd[n] = $3; srv[n] = $8; st[n] = $10; at[$1] = n; next }
    part == 2 {
      if ($0 !~ /^landed:[ \t]/) next
      r = ""; m = ""; nf = split($0, f, /[ \t]+/)
      for (k = 2; k <= nf; k++) {
        if (f[k] ~ /^row=/) r = substr(f[k], 5)
        else if (f[k] ~ /^merge=/) m = tolower(substr(f[k], 7))
      }
      if (!(r in at)) next
      lm[r] = (m ~ /^[0-9a-f]+$/ && length(m) >= 7 && length(m) <= 40) ? m : "-"
      if (lm[r] != "-") rm[lm[r]] = 1
      next
    }
    part == 3 {
      if ($0 ~ /^[ \t]*```/) { fence = !fence; next }
      if (fence) next
      if ($0 ~ /^## /) { inm = ($0 ~ /^## Verification Matrix/); next }
      if (!inm || $0 !~ /^\|[ \t]*AC-[0-9]+\./) next
      split($0, c, "|"); ac = trim(c[2]); q = ac; sub(/^AC-/, "", q); sub(/\..*$/, "", q)
      crit[q] = (q in crit) ? crit[q] ", " ac : ac
      next
    }
    part == 4 { v = tolower(trim($0)); if (v != "") { inr[v] = 1; ord[++no] = v }; next }
    # A recorded merge names a commit it is a prefix of: the record may hold 7 to 40 hex, the
    # caller full commits.
    function named(mg, set,   v) { for (v in set) if (index(v, mg) == 1) return 1; return 0 }
    END {
      if (mode == "unrecorded") {
        for (x = 1; x <= no; x++) {
          hit = 0
          for (mg in rm) if (index(ord[x], mg) == 1) { hit = 1; break }
          if (!hit) print ord[x]
        }
        exit
      }
      for (i = 1; i <= n; i++) {
        owed = (knd[i] == "build" && (st[i] == "landed" || st[i] == "done"))
        if (mode == "landings") {
          if (id[i] in lm) printf "%s\t%s\t%s\n", id[i], lm[id[i]], (owed ? "owed" : "-")
          else if (owed) printf "%s\t-\towed\n", id[i]
          continue
        }
        if (!(id[i] in lm) || lm[id[i]] == "-" || !named(lm[id[i]], inr)) continue
        cr = ""; ns = split(srv[i], sv, ",")
        for (k = 1; k <= ns; k++) {
          q = trim(sv[k]); if (q !~ /^REQ-[0-9]+$/) continue
          q = substr(q, 5); if (q in crit) cr = cr (cr == "" ? "" : ", ") crit[q]
        }
        printf "%s\t%s\t%s\n", id[i], srv[i], cr
      }
    }'
}

# units_floor_holds <plan> [<id>] -> `<id><TAB><step><TAB><status>`, table order, for each row the
# FLOOR waits on that has not landed (or been dropped) and writes a tracked file (wave-26 T52;
# review 14 B1, ruling R1). The floor is row <id>; with no id, every open verify or test row, the
# rows `proof:floor` names as its writers. "Waits on" is the ready set's own judgment of each of
# the floor's reads and deps (`judge` below), so a row downstream of the floor — the release,
# which waits FOR the floor — never holds it; "writes a tracked file" is `writes_head`, so a row
# whose Files are all record paths never does. The dispatch wall asks this before it admits a
# full run: a run now proves a head these rows are about to move.
units_floor_holds() { _units_sched holds "${1:-}" "${2:-}"; }

# units_approval_names <plan> -> each name an OPEN row reads as `approval:<name>` or
# `live:approval:<name>`, once, sorted (wave-26 T46; review 10 F6). `approve` records only these:
# a name no row reads would be recorded once while the row it was meant for waits. A name read
# only by a landed or dropped row satisfies nothing either, so it is not one of them (T52; review
# 14 N4). The match is exact, case included, as the readiness program keys it. `plan` is a read
# like any other here.
units_approval_names() {
  units_rows "${1:-}" 2>/dev/null | awk -F'\t' '{
    s = tolower($10); if (s != "pending" && s != "active") next
    m = split($13, a, ",")
    for (k = 1; k <= m; k++) {
      t = a[k]; gsub(/^[ \t]+|[ \t]+$/, "", t); sub(/^live:/, "", t)
      if (t ~ /^approval:[A-Za-z0-9][A-Za-z0-9._-]*$/) print substr(t, 10)
    }
  }' | sort -u
}

# _units_ext_re -> the shape of an external prerequisite token, as an awk ERE (wave-21 T4; D3).
# ONE SPELLING for the validator that admits it and the readiness program that reports it, so
# a token the validator lets into a plan is exactly a token the held report names. A bare
# `ext:`, a slug opening on punctuation and an upper-case prefix are not this shape, and the
# validator refuses them the way it refuses any id the table does not carry.
_units_ext_re() { printf '%s' '^ext:[A-Za-z0-9][A-Za-z0-9._-]*$'; }

# _units_proof_awk -> proof.sh's `proof_awk`, the one reading of a proof line (wave-26 T14;
# review 7 F6). proof.sh is sourced from this file's own directory once, when this file is
# loaded (below), not per question: readiness is asked inside command substitutions, where a
# lazy source would be paid again on every call. If it cannot be loaded, a function that reads
# no line as a proof: no proof is the cautious answer for a settled read.
_units_proof_lib() {
  local d
  declare -F proof_awk >/dev/null 2>&1 && return 0
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
  [ -n "$d" ] && [ -f "$d/proof.sh" ] && . "$d/proof.sh" >/dev/null 2>&1
  return 0
}
_units_proof_lib
_units_proof_awk() {
  if declare -F proof_awk >/dev/null 2>&1; then
    proof_awk
  else
    printf '%s' ' function proof_fields(s) { PROOF_KIND = ""; PROOF_HEAD = ""; return 0 } '
  fi
}

# _units_sched <ready|held|waiting|edges> <plan> <step> — THE ONE PROGRAM behind the four verbs,
# so a row the ready set leaves out is the row `units_waiting` explains and the edge
# `units_edges` prints. One stream: the rows (`units_rows`, so a memoised caller pays no second
# parse), then the plan's text, from which `## SDLC State`'s approval and proof lines are read
# fence-aware, the `_units_ledger` way.
# ONE VALUE FROM OUTSIDE THE PLAN (wave-26 T14; review 5 F8): UNITS_LIVE_HEAD, the working
# branch's head as the caller read it, which `live:head` compares with the last review proof's
# `head=`. Unset, a plan with a review proof cannot see past it, and its live review waits.
# AND ONE ANSWER (wave-27 T14; D3): UNITS_FACTS_STATE, `covered` when lib/proof.sh `facts_state`
# holds the plan at that head, else the lines that do not hold; `proof:review` is met only by
# `covered`. The tick computes it once (session-poker.sh `sched_facts_state`); unset, it waits.
# `holds` (units_floor_holds) takes the floor row's id, or nothing, in the <step> slot.
_units_sched() {
  local mode="${1:-}" plan="${2:-}" step="${3:-}" out ctl rows scale=wave hasreads=0 i fst rc
  if [ "$mode" != edges ] && [ "$mode" != range ] && [ "$mode" != liverows ] && [ "$mode" != holds ] && [ "$mode" != whole ]; then
    case "$step" in
      ''|*[!0-9]*)
        case "$step" in
          T*) case "${step#T}" in ''|*[!0-9]*) return 2 ;; *) scale=task ;; esac ;;
          *) return 2 ;;
        esac ;;
    esac
  fi
  out="$(_units_table "$plan")" || return 1
  case "$out" in *$'\n'*) rows="${out#*$'\n'}" ;; *) rows="" ;; esac
  [ -n "$rows" ] || return 0
  # THE CONTROL LINE'S FOURTH FIELD names the columns the header carries (`units_has_column`'s
  # reading, taken here from the parse already in hand).
  ctl="${out%%$'\n'*}"
  for i in 1 2 3; do ctl="${ctl#*$'\t'}"; done
  ctl="${ctl%%$'\t'*}"
  case " $ctl " in *" reads "*) hasreads=1 ;; esac
  # THE FLOOR STATE IS ASKED ONLY WHEN AN ANSWER TURNS ON IT (wave-26 T64; REQ-3 AC-3.4). The
  # program runs without it; when a pending row it judges reads a `proof:floor` that a proof line
  # and no open writer would satisfy, it prints nothing and exits 3, and only then is
  # `proof_state` run (once per memoised command, `_units_floor_state`) and the program run again
  # with the answer. Every other plan, and every other moment of this one, runs no git here.
  fst="$(_units_floor_kept "$plan")"
  _units_sched_run "$mode" "$plan" "$step" "$scale" "$hasreads" "$rows" "$fst"; rc=$?
  if [ "$rc" -eq 3 ] && [ -z "$fst" ]; then
    fst="$(_units_floor_state "$plan")"
    _units_sched_run "$mode" "$plan" "$step" "$scale" "$hasreads" "$rows" "$fst"; rc=$?
  fi
  return "$rc"
}

# _units_sched_run <mode> <plan> <step> <scale> <hasreads> <rows> <floor state> -> the program's
# answer and its status: 3, with nothing printed, when the answer needs a floor state not handed in.
_units_sched_run() {
  {
    printf '\034rows\n'; printf '%s\n' "$6"
    printf '\034plan\n'; awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$2" 2>/dev/null
  } | _UNITS_FLOOR_ST="$7" _UNITS_FACTS_ST="${UNITS_FACTS_STATE:-}" awk -F'\t' -v mode="$1" -v want="$3" -v scale="$4" -v hasreads="$5" \
      -v livehead="$(printf '%s' "${UNITS_LIVE_HEAD:-}" | tr 'A-F' 'a-f')" -v evid="${_UNITS_EVIDENCE:-}" \
      -v liveq="${_UNITS_QUESTION:-}" -v pq="${PROOF_QUESTIONS:-}" \
      -v extre="$(_units_ext_re)" "$(_units_proof_awk)$(_units_files_awk)$(_units_sched_awk)"
}

# _units_floor_state <plan> -> what lib/proof.sh `proof_state` says of the change since the plan's
# last floor proof: `covered…`, `bounded…` or `unbounded<TAB><reason>`, one line. The tree it asks
# is the project root the plan sits under (`<root>/.bionic/…`), or the plan's own directory, whose
# repository git finds. Inside `units_memoised` the answer is kept in a file for the rest of the
# command, so the tick's three questions and its ready set run `proof_state` once between them.
# WHEN THE STATE CANNOT BE COMPUTED, THE READ IS NOT SATISFIED (the fail direction): proof.sh not
# loadable, no git, no checkout, a map that fails or overruns all answer `unbounded` with the
# reason, and a floor proof at the head is always the way out, because `covered` asks no map.
_units_floor_state() {
  local plan="${1:-}" tree st=""
  st="$(_units_floor_kept "$plan")"
  [ -z "$st" ] || { printf '%s\n' "$st"; return 0; }
  tree="$(_units_plan_tree "$plan")"
  if declare -F proof_state >/dev/null 2>&1; then
    st="$(proof_state "$plan" "$tree" 2>/dev/null | awk 'NR == 1')"
  fi
  case "$st" in
    covered*|bounded*|unbounded*) ;;
    *) st="$(printf 'unbounded\tthe proof state cannot be computed here (lib/proof.sh)')" ;;
  esac
  [ -z "${_UNITS_MEMO_FLOOR:-}" ] || printf '%s\n%s\n' "$plan" "$st" > "$_UNITS_MEMO_FLOOR" 2>/dev/null
  printf '%s\n' "$st"
}

# _units_floor_kept <plan> -> the state the memo file keeps for <plan>, or nothing: the file's
# first line is the plan it was asked for, the second the state. Read with the shell alone.
_units_floor_kept() {
  local p="" st=""
  [ -n "${_UNITS_MEMO_FLOOR:-}" ] && [ -f "$_UNITS_MEMO_FLOOR" ] || return 0
  { IFS= read -r p; IFS= read -r st; } < "$_UNITS_MEMO_FLOOR" 2>/dev/null
  [ "$p" = "${1:-}" ] && printf '%s' "$st"
  return 0
}

# _units_files_awk -> the awk functions `in_docs(entry)`, `writes_head(cell)`, and (wave-28 T8, A-orch-159) the
# Files matcher `isglob`, `glob_re`, `covers(entry, path)` and `cell_covers(cell, path)`, lifted here out of the
# scheduler's program so a verb that asks "which rows write this path" asks the matcher the scheduler asks.
# `in_docs` is 1
# when a `Files` path entry is the record, not the tracked tree: under `.bionic/`, or spelled from
# the docs root as `record/…` (the spelling proof lines and older plans use; review 10 F4).
# `writes_head` is 1 when a `Files` cell names a path that is not, the tracked tree a writer
# commits to the head; 0 when every path entry is the record, or the cell names no path at all (a
# bare word or a dash declares nothing).
# ONE PREDICATE, THREE READERS (wave-26 T32, T46): the scheduler asks it which rows write the head
# a floor proves and which landed rows a first live review reads, `units_validate` which active
# rows owe a tree of their own, and fill.sh `fill_readonly_ids` which verify or review rows take
# no writer slot; the scheduler asks `in_docs` which rows write what a `record` read waits on.
# Prepended to each program; NO APOSTROPHE inside it (it is single-quoted).
_units_files_awk() {
  printf '%s' '
    function in_docs(e) { return (index(e, ".bionic/") == 1 || index(e, "record/") == 1) }
    function writes_head(cell,   a, m, k, e) {
      m = split(cell, a, ",")
      for (k = 1; k <= m; k++) {
        e = a[k]; sub(/^[ \t]+/, "", e); sub(/[ \t]+$/, "", e); sub(/^\.\//, "", e)
        if (e == "" || e !~ /[\/.*?]/ || e ~ /[ \t]/) continue
        if (!in_docs(e)) return 1
      }
      return 0
    }
    function isglob(e) { return (index(e, "*") > 0 || index(e, "?") > 0) }
    # glob_re(g): the glob as an anchored ERE, built once per entry. The grammar globs with * and
    # ? only, so a bracket is a character like any other: `[` is escaped with the rest, and a
    # `Files` entry carrying one can never become a broken regex that stops every verb (T35 F5;
    # `units_validate` refuses the entry, naming its row). A `]` outside a class is literal already.
    function glob_re(g,   o) {
      if (g in gre) return gre[g]
      o = g
      gsub(/[.+^$(){}|\\]/, "\\\\&", g); gsub(/\[/, "\\\\&", g); gsub(/\*/, ".*", g); gsub(/\?/, ".", g)
      gre[o] = "^" g "$"
      return gre[o]
    }
    # covers(e, p): the Files entry e covers the path p (brief.sh `in_files`, one pair).
    function covers(e, p,   ls, lp) {
      if (e == p) return 1
      if (isglob(e)) return (p ~ glob_re(e))
      if (substr(e, length(e)) == "/" && index(p, e) == 1) return 1
      if (index(p, e "/") == 1) return 1
      ls = length(e); lp = length(p)
      if (ls > lp && substr(e, ls - lp) == "/" p) return 1
      if (lp > ls && substr(p, lp - ls) == "/" e) return 1
      return 0
    }
    # cell_covers(cell, p): some entry of the Files cell (comma-separated; a backtick, a leading ./ and the
    # white space around an entry are not part of it) covers the path p. THE ONE MATCHER OF THE DISPATCH GRAMMAR
    # for a shell caller: the scheduler overlap test and the finding-check code writer ask covers through it.
    function cell_covers(cell, p,   a, m, k, e) {
      sub(/^\.\//, "", p)
      m = split(cell, a, /[ \t]*,[ \t]*/)
      for (k = 1; k <= m; k++) {
        e = a[k]; gsub(/`/, "", e); sub(/^[ \t]+/, "", e); sub(/[ \t]+$/, "", e); sub(/^\.\//, "", e)
        if (e != "" && covers(e, p)) return 1
      }
      return 0
    }
'
}

# units_writes_head <Files cell> -> 0 when the cell names a path outside the record, 1 when not:
# the same predicate, for a shell caller (session-poker.sh launch-sync).
units_writes_head() {
  printf '%s\n' "${1:-}" | awk "$(_units_files_awk)"'{ exit !writes_head($0) }'
}

# _units_questions_awk -> the awk function `isq(q)`: 1 when q is exactly one of lib/proof.sh
# PROOF_QUESTIONS, handed in as `pq`. ONE TEST, TWO READERS (wave-27 T43; review pass 17 F4): the
# readiness program and `units_validate` both ask it of each `+` part of `live:head:<q>[+<q>]`, so
# a token the validator admits is a token the scheduler can satisfy. Whole words only: a part
# holding a blank, a dot or nothing is no question.
_units_questions_awk() {
  printf '%s' '
    function isq(q,   a, m, k) {
      if (q == "") return 0
      m = split(pq, a, " ")
      for (k = 1; k <= m; k++) if (a[k] == q) return 1
      return 0
    }
'
}

# _units_sched_awk -> the awk program `_units_sched` runs. Printed by a function so the comments
# can sit beside the code; NO APOSTROPHE anywhere inside it (it is single-quoted). It opens with
# the question test it shares with the validator.
_units_sched_awk() {
  _units_questions_awk
  printf '%s' '
    $0 == SUBSEP "rows" { part = 1; next }
    $0 == SUBSEP "plan" { part = 2; next }
    part == 1 {
      if ($1 == "") next
      n++; id[n] = $1; stp[n] = $2; knd[n] = $3; agt[n] = $5; dep[n] = $6; fil[n] = $9; st[n] = $10; rd[n] = $13
      at[$1] = n
      next
    }
    # THE PLAN TEXT: approval and proof lines inside `## SDLC State`, fences skipped.
    part == 2 {
      if ($0 ~ /^[[:space:]]*```/) { fence = !fence; next }
      if (fence) next
      if ($0 ~ /^## SDLC State/) { insec = 1; next }
      if ($0 ~ /^## /) insec = 0
      if (!insec) next
      l = $0; sub(/^[ \t]*-?[ \t]*/, "", l)
      if (l ~ /^approved-by[ \t]*:/) {
        v = l; sub(/^approved-by[ \t]*:[ \t]*/, "", v)
        if (v ~ /[^ \t]/) appr["plan"] = 1
      } else if (l ~ /^approved[ \t]*:/) {
        v = l; sub(/^approved[ \t]*:[ \t]*/, "", v); split(v, aw, /[ \t]+/)
        if (aw[1] != "") appr[aw[1]] = 1
      } else if (proof_fields($0)) {
        # ONE READING OF A PROOF LINE, proof.sh `proof_fields` (wave-26 T14; review 7 F6), the one
        # `proof_last` reads through. THE HEAD IS KEPT (review 5 F8): the last line of a kind is
        # the newest, the order the writer appends in, so `live:head` compares against it.
        proved[PROOF_KIND] = 1; prvh[PROOF_KIND] = PROOF_HEAD
        # A CHAIN PER QUESTION (wave-27 T10; D4): a reading is also the last proof of its own
        # question, kept with its place among the proof lines, the order that says which is older.
        # A line with no question (1.11.0) is the last proof of no question (A-T2.4).
        pn++
        if (PROOF_KIND == "review" && PROOF_QUESTION != "") { prvq[PROOF_QUESTION] = PROOF_HEAD; prvn[PROOF_QUESTION] = pn }
        # A WHOLE READING (wave-27 T43; D10) is remembered per question: units_whole_read asks it.
        if (PROOF_KIND == "review" && PROOF_QUESTION != "" && PROOF_SCOPE == "whole") wholeq[PROOF_QUESTION] = 1
      }
      next
    }

    function trim(v) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); return v }
    function isopen(j) { return (st[j] == "pending" || st[j] == "active") }
    # overlap(a, b): either covers the other; two globs overlap when one literal prefix is a
    # prefix of the other (the fail-safe reading: a pair that might collide is held).
    function overlap(a, b,   pa, pb) {
      if (covers(a, b) || covers(b, a)) return 1
      if (isglob(a) && isglob(b)) {
        pa = a; sub(/[*?].*$/, "", pa); pb = b; sub(/[*?].*$/, "", pb)
        return (index(pa, pb) == 1 || index(pb, pa) == 1)
      }
      return 0
    }
    function writes(j, p,   k) {
      for (k = 1; k <= nfe[j]; k++) if (overlap(fe[j, k], p)) return 1
      return 0
    }

    # THE PATH INDEX (T35 F7): every Files entry of an open row, filed once per parse under the keys
    # a literal path can reach it by, so a read or an unmergeable hold asks a handful of keys
    # instead of every entry of every row. For a literal entry e and a literal path t, covers(e, t)
    # or covers(t, e) holds exactly when one of these does — `E:` e itself, which t reaches as
    # itself, as a prefix ending at a slash or just before one, or as a tail after a slash; `P:` each
    # prefix of e ending at a slash, which t reaches when t (or t plus a slash) is one; `S:` each
    # tail of e after a slash, which t reaches as itself. A glob entry is listed, not filed (gl*
    # every glob, gm* the marked ones), and a glob t falls back to the scan.
    function ixput(key, j, k) { ixn[key]++; ixj[key, ixn[key]] = j; ixk[key, ixn[key]] = k }
    function ixadd(j, k,   e, l, p) {
      e = fe[j, k]
      if (isglob(e)) {
        ngl++; glj[ngl] = j; glk[ngl] = k
        if (bg[j, k]) { ngm++; gmj[ngm] = j; gmk[ngm] = k }
        return
      }
      ixput("E:" e, j, k)
      l = length(e)
      for (p = 1; p <= l; p++) {
        if (substr(e, p, 1) != "/") continue
        ixput("P:" substr(e, 1, p), j, k)
        if (p < l) ixput("S:" substr(e, p + 1), j, k)
      }
    }
    function ixlk(key, mk,   q) {
      for (q = 1; q <= ixn[key]; q++) {
        if (mk && !bg[ixj[key, q], ixk[key, q]]) continue
        nc++; cj[nc] = ixj[key, q]; ck[nc] = ixk[key, q]
      }
    }
    # entries(t, mk) -> every (row, entry) pair of an open row whose entry overlaps t, in
    # cj[1..nc] / ck[1..nc], unordered and possibly repeated; only marked entries when mk is set.
    function entries(t, mk,   l, p, q, j, k) {
      nc = 0
      if (isglob(t)) {
        for (j = 1; j <= n; j++) {
          if (!isopen(j)) continue
          for (k = 1; k <= nfe[j]; k++)
            if ((!mk || bg[j, k]) && overlap(fe[j, k], t)) { nc++; cj[nc] = j; ck[nc] = k }
        }
        return
      }
      ixlk("E:" t, mk)
      l = length(t)
      for (p = 1; p <= l; p++) {
        if (substr(t, p, 1) != "/") continue
        ixlk("E:" substr(t, 1, p), mk)
        if (p > 1) ixlk("E:" substr(t, 1, p - 1), mk)
        if (p < l) ixlk("E:" substr(t, p + 1), mk)
      }
      if (substr(t, l) == "/") ixlk("P:" t, mk)
      ixlk("P:" t "/", mk)
      ixlk("S:" t, mk)
      if (mk) { for (q = 1; q <= ngm; q++) if (overlap(fe[gmj[q], gmk[q]], t)) { nc++; cj[nc] = gmj[q]; ck[nc] = gmk[q] } }
      else    { for (q = 1; q <= ngl; q++) if (overlap(fe[glj[q], glk[q]], t)) { nc++; cj[nc] = glj[q]; ck[nc] = glk[q] } }
    }
    # open_writers(t) -> the open rows writing the path t, ascending, in ow[1..now]; worked out
    # once per path and kept, since the answer does not depend on who asks.
    function open_writers(t,   c, j, s, x) {
      if (!(t in owc)) {
        entries(t, 0); s = ""
        for (c = 1; c <= nc; c++) x[cj[c]] = 1
        for (j = 1; j <= n; j++) if (j in x) s = s " " j
        owc[t] = s
      }
      now = split(owc[t], ow, " ")
    }
    function kdef(k) {
      if (k == "verify" || k == "test" || k == "doc") return "approval:plan, head"
      if (k == "review") return "approval:plan, live:head"
      if (k == "integrate") return "proof:floor, proof:review, head"
      if (k == "close") return "merge"
      return "approval:plan"
    }
    function addtok(i, t) {
      t = trim(t)
      if (t == "" || t !~ /[A-Za-z0-9]/) return
      ntk[i]++; tk[i, ntk[i]] = t
      if (t == "head") rhead[i] = 1
      if (t == "record") rrec[i] = 1
      if (t == "live:head") rlive[i] = 1
      else if (substr(t, 1, 10) == "live:head:") { rlive[i] = 1; addq(i, substr(t, 11)) }
    }
    # addq(i, s) -> the questions of a read row, `<q>[+<q>]` (wave-27 T10; D4), in rq[i, 1..nq[i]]
    # and hasq[i, q]. A question outside the set, an empty one, or a read row that is not a review
    # marks the row rbadq: the validator refuses it, and its live read is never satisfied.
    function addq(i, s,   m, k, qa) {
      if (knd[i] != "review") rbadq[i] = 1
      m = split(s, qa, "+")
      if (m == 0) rbadq[i] = 1
      for (k = 1; k <= m; k++) {
        if (!isq(qa[k])) { rbadq[i] = 1; continue }
        if ((i, qa[k]) in hasq) continue
        hasq[i, qa[k]] = 1; nq[i]++; rq[i, nq[i]] = qa[k]
        qlab[i] = (nq[i] > 1 ? qlab[i] "+" : "") qa[k]
      }
    }
    # qshare(i, j) -> 1 when rows i and j read a question in common. A review row naming no
    # question (a bare live:head, a settled head read) shares every one: it holds and is held as
    # through 1.11.0, the cautious direction.
    function qshare(i, j,   k) {
      if (!nq[i] || !nq[j]) return 1
      for (k = 1; k <= nq[i]; k++) if ((j, rq[i, k]) in hasq) return 1
      return 0
    }
    # live_oldest(i, past) -> of row i questions, the one whose last reading is the oldest line,
    # only among those whose head is not the head handed in when past is set; nothing when one of
    # them has no reading yet (that question reads from the base) or none qualifies. It answers
    # whether the head is past the row reading and which question a wait names; where a range
    # starts is decided by ancestry, outside this program (units_live_range; T43, review 17 F2).
    function live_oldest(i, past,   k, q, o) {
      o = ""
      for (k = 1; k <= nq[i]; k++) {
        q = rq[i, k]
        if (!(q in prvq)) return ""
        if (past && prvq[q] == livehead) continue
        if (o == "" || prvn[q] < prvn[o]) o = q
      }
      return o
    }

    # LIVE: a live read is satisfied when its artifact exists: the record always does; a proof or
    # an approval when its line is written; a path unless the only rows that write it are still
    # open (none has landed it). Anything else names no artifact and is never satisfied (review 5
    # F4: `live:foo`, `live:ext:ci`, `live:T9` fell into the path arm and read as ready). `head`
    # is live_head below.
    function live_sat(i, a,   j, lw, ow) {
      if (a == "head" || substr(a, 1, 5) == "head:") return live_head(i)
      if (a == "record") return 1
      if (substr(a, 1, 6) == "proof:") return (substr(a, 7) in proved)
      if (substr(a, 1, 9) == "approval:") return (substr(a, 10) in appr)
      if (a !~ /[\/.*?]/ || a ~ /[ \t:!]/) return 0
      lw = 0; ow = 0
      for (j = 1; j <= n; j++) {
        if (j == i || st[j] == "dropped" || !writes(j, a)) continue
        if (st[j] == "landed") lw = 1; else if (isopen(j)) ow = 1
      }
      return (lw || !ow)
    }
    # live_head(i) -> 1 when row i may read the moving head now (wave-26 T14; D10): no other row
    # of its kind open, and landed work past the last review proof — any landed row writing
    # outside .bionic/ while there is no proof, the head handed in (livehead) differing from the
    # proof head once there is one. The head is compared, not its ancestry: the range the review
    # reads, proof..head, is the work on the head that the proof never saw, rewritten history
    # included (A-T14.1). A wait sets lwhy, which units_waiting prints after the read.
    # A READ ROW IS JUDGED PER QUESTION (wave-27 T10; D4): only a row sharing one of its questions
    # holds it, a pending row above that has nothing to read holds no read row below it, and
    # past the proof means past the last reading of one of its own questions. A question with no
    # reading yet reads from the base, so the row is ready once work has landed, as a first review.
    # THE IDLE ROW ABOVE MAY BE BARE (wave-27 T43; review pass 17 F1): only the row below need name
    # a question. A bare row is idle after every pass, and a bare row above that held for good would
    # hold the read row, and the integrate row through it. Between two bare rows 1.11.0 holds.
    function live_head(i,   j, h, k, o) {
      if (rbadq[i]) { lwhy = "the read names a question outside " pq " or sits on a row that is not a review"; return 0 }
      for (j = 1; j <= n; j++) {
        if (j == i || knd[j] != knd[i] || !qshare(i, j)) continue
        if (st[j] == "active") { lwhy = knd[i] " " id[j] " is open (active)"; return 0 }
        if (st[j] == "pending" && rlive[j] && j < i && !(nq[i] && live_idle(j))) { lwhy = knd[i] " " id[j] " goes first"; return 0 }
      }
      if (nq[i]) {
        for (k = 1; k <= nq[i]; k++) if (!(rq[i, k] in prvq)) {
          for (j = 1; j <= n; j++) if (j != i && st[j] == satisfied && code[j]) return 1
          lwhy = "nothing has landed yet"; return 0
        }
        if (livehead == "") {
          o = live_oldest(i, 0)
          lwhy = "the head past the " o " review proof at " substr(prvq[o], 1, 12) " is not known here"; return 0
        }
        if (live_oldest(i, 1) == "") { lwhy = "nothing landed past the " qlab[i] " review proof at " substr(livehead, 1, 12); return 0 }
        return 1
      }
      if (!("review" in prvh)) {
        for (j = 1; j <= n; j++) if (j != i && st[j] == satisfied && code[j]) return 1
        lwhy = "nothing has landed yet"; return 0
      }
      h = prvh["review"]
      if (livehead == "") { lwhy = "the head past the review proof at " substr(h, 1, 12) " is not known here"; return 0 }
      if (livehead == h) { lwhy = "nothing landed past the review proof at " substr(h, 1, 12); return 0 }
      return 1
    }

    # live_idle(j) -> 1 when row j live:head read waits because nothing landed past the review proof:
    # the head handed in is the one the proof names. A pending row whose live read is idle writes
    # no newer proof until something lands (wave-26 T62; K2-F4); with the head unknown it may. A
    # read row is idle when every one of its questions was last read at that head (wave-27 T10).
    function live_idle(j,   k) {
      if (!nq[j]) return (("review" in prvh) && livehead != "" && livehead == prvh["review"])
      if (livehead == "") return 0
      for (k = 1; k <= nq[j]; k++) if (!(rq[j, k] in prvq) || prvq[rq[j, k]] != livehead) return 0
      return 1
    }

    # judge(i, t) -> 1 when row i read t is satisfied; otherwise 0, with the rows named as its
    # writers in wj[1..nw] (those still open, plus a task-id row in any unsatisfied state), and
    # for a live read that waits on no row, why in lwhy.
    function judge(i, t,   j, a, q) {
      nw = 0; lwhy = ""
      if (t ~ extre) return 0
      if (substr(t, 1, 9) == "approval:") return (substr(t, 10) in appr)
      if (substr(t, 1, 5) == "live:") return live_sat(i, substr(t, 6))
      # A PROOF IS SETTLED ONLY WHEN NOTHING OPEN WILL WRITE A NEWER ONE (T35 F2): a re-floor row
      # added after the floor was proved makes that line stale, so the open writers are asked
      # first and the line counts only when there are none.
      if (substr(t, 1, 6) == "proof:") {
        a = substr(t, 7)
        for (j = 1; j <= n; j++) {
          if (j == i || !isopen(j)) continue
          if ((a == "floor" && (knd[j] == "verify" || knd[j] == "test")) || (a == "review" && knd[j] == "review"))
            if (!(st[j] == "pending" && rlive[j] && live_idle(j))) wj[++nw] = j
        }
        # THE REVIEW IS MET BY THE JUDGE, NOT BY A LINE (wave-27 T14; D3, D4). A `proved: kind=review`
        # line was enough here, a `result=fail` reading among them (A-orch-40). Now the read is met
        # only when lib/proof.sh `facts_state` answered covered for the plan at the working head:
        # the tick asks it once and hands the answer in (factsst), as it hands the floor state in.
        # Not handed in, it is not known here, and the row waits saying so (the cautious direction).
        if (a == "review") {
          if (nw) return 0
          if (factsst == "covered") return 1
          if (factsst == "") lwhy = "the facts the run owes are judged by the tick (facts_state) and are not known here"
          else lwhy = "the facts the run owes do not hold (facts_state): " factsst
          return 0
        }
        # THE FLOOR PROOF STANDS ONLY WHILE THE PASS DOES (wave-26 T64; REQ-3 AC-3.4). A line
        # with no open writer satisfies the read when the change since its head is covered or
        # bounded; unbounded, or a state that could not be computed, is a wait naming the way
        # out. Unknown here (floorst empty) is reported through needfloor, and the shell runs
        # this program again with the state; a row held for its step is judged without it.
        if (nw == 0 && a == "floor" && (a in proved) && !skipfloor) {
          if (floorst == "") needfloor = 1
          else if (floorst !~ /^(covered|bounded)/) {
            fr = floorst; sub(/^[^\t]*\t?/, "", fr)
            if (fr == "") fr = "the proof state could not be computed"
            lwhy = "the head moved past the floor proof at " substr(prvh["floor"], 1, 12) \
              " in a way the map cannot bound (" fr "); take the full run on this head and record it with proof-add floor"
            return 0
          }
        }
        return (nw == 0 && (a in proved))
      }
      # A ROW THAT READS THE SETTLED head STILL WRITES IT FOR A ROW AT A LATER STEP (T35 F1). The
      # exception A-T2.4 made is kept between equals and toward earlier steps — the walk does not
      # wait for the release — but a test, doc or build row at Step 4 that reads head and writes
      # code holds the Step-5 floor. `record` takes the same rule over record paths.
      if (t == "head" || t == "record") {
        for (j = 1; j <= n; j++) {
          if (j == i || !isopen(j)) continue
          q = (t == "head") ? rhead[j] : rrec[j]
          if ((t == "head" ? code[j] : docs[j]) && (!q || stp[j] + 0 < stp[i] + 0)) wj[++nw] = j
        }
        return (nw == 0)
      }
      if (t == "merge") {
        for (j = 1; j <= n; j++) if (j != i && isopen(j) && knd[j] == "integrate") wj[++nw] = j
        return (nw == 0)
      }
      if (t in at) {
        j = at[t]
        if (st[j] == satisfied || st[j] == "dropped") return 1
        wj[++nw] = j
        return 0
      }
      if (t ~ /^T[0-9]+$/) return 0
      if (t ~ /[\/.*?]/ && t !~ /[ \t:!]/) {
        open_writers(t)
        for (q = 1; q <= now; q++) if (ow[q] != i) wj[++nw] = ow[q]
        return (nw == 0)
      }
      return 0
    }

    # bang(i) -> the rows holding row i on an unmergeable path, in hb[1..nh] with the marked path
    # in hp[1..nh]: open rows declaring an overlapping path either side marked, that are active,
    # or pending and above row i. Per holder, the first of row i entries that meets it, and for an
    # unmarked entry the holder first marked one — the pair the walk over every pair found first,
    # now found through the index (T35 F7), and not looked for at all in a table with no mark.
    function bang(i,   j, k, m, c) {
      nh = 0
      if (!nbg) return 0
      bgen++
      for (k = 1; k <= nfe[i]; k++) {
        entries(fe[i, k], !bg[i, k])
        for (c = 1; c <= nc; c++) {
          j = cj[c]; m = ck[c]
          if (j == i || !(st[j] == "active" || j < i)) continue
          if (hgen[j] != bgen) { hgen[j] = bgen; hk[j] = k; hm[j] = m }
          else if (hk[j] == k && m < hm[j]) hm[j] = m
        }
      }
      for (j = 1; j <= n; j++) {
        if (hgen[j] != bgen) continue
        nh++; hb[nh] = j; hp[nh] = (bg[i, hk[j]] ? fe[i, hk[j]] : fe[j, hm[j]]) "!"
      }
      return nh
    }

    # rowheld(i) -> 2 when this answer does not judge pending row i at all, 1 when it is a gate
    # act held for its step, 0 otherwise. A WAVE ROW CARRIES A NUMERIC STEP, and that is all the
    # step still decides for a work row (wave-20 Δ1). A GATE ACT WAITS FOR ITS STEP (Δ6; T10b):
    # ready only once the run has REACHED its step, reached and not equalled. A DOC ROW WAITS FOR
    # ITS READS (wave-26 T13; D3): in a table with the reads column the release reads
    # approval:release and nothing about it is a step. A table without the column has no approval
    # to read, so its Step-7 doc row keeps the hold (A-T13.1).
    function rowheld(i,   gate) {
      if (scale == "task") return (stp[i] != "") ? 2 : 0
      if (stp[i] !~ /^[0-9]+$/) return 2
      gate = (knd[i] == "integrate" || knd[i] == "close" || (!hasreads && knd[i] == "doc" && stp[i] + 0 >= 7))
      return (gate && stp[i] + 0 > want + 0) ? 1 : 0
    }

    END {
      satisfied = (scale == "task") ? "done" : "landed"
      floorst = ENVIRON["_UNITS_FLOOR_ST"]
      factsst = ENVIRON["_UNITS_FACTS_ST"]
      for (i = 1; i <= n; i++) {
        # THE FILES CELL: path entries only (a bare word or a dash declares nothing), the mark
        # taken off and remembered; code[] and docs[] say which side of the record it writes.
        m = split(fil[i], a, ",")
        for (k = 1; k <= m; k++) {
          e = trim(a[k]); sub(/^\.\//, "", e)
          if (e == "" || e !~ /[\/.*?]/ || e ~ /[ \t]/) continue
          mark = (substr(e, length(e)) == "!")
          if (mark) e = substr(e, 1, length(e) - 1)
          nfe[i]++; fe[i, nfe[i]] = e; bg[i, nfe[i]] = mark; nbg += mark
          if (in_docs(e)) docs[i] = 1
          if (isopen(i)) ixadd(i, nfe[i])
        }
        code[i] = writes_head(fil[i])
        r = rd[i]
        if (hasreads && r !~ /[A-Za-z0-9]/) r = kdef(knd[i])
        if (hasreads) { m = split(r, a, ","); for (k = 1; k <= m; k++) addtok(i, a[k]) }
        # THE RELEASE READS ITS APPROVAL (wave-26 T62; K2-F3; D3). A doc row at Step 7 or later
        # whose own cell names no approval (the kind default names only the plan) would be ready
        # beside the floor; the validator refuses it, and a plan that got past the validator
        # still never offers it before approved: release.
        if (hasreads && knd[i] == "doc" && stp[i] ~ /^[0-9]+$/ && stp[i] + 0 >= 7 && rd[i] !~ /(^|[ \t,:])approval:[A-Za-z0-9]/) addtok(i, "approval:release")
        m = split(dep[i], a, ",")
        for (k = 1; k <= m; k++) addtok(i, a[k])
      }
      # THE RANGE OF ONE READ ROW (wave-27 T10; D4): the last heads of its questions not read at the
      # head handed in, one per line, and nothing while one has no reading; units_live_range picks
      # the start among them by ancestry (T43; review pass 17 F2). A bare row, an unknown id, or no
      # id at all is answered here, as through 1.11.0.
      # THE WHOLE READ OF ONE READ ROW (wave-27 T43): every question it carries has a whole reading.
      if (mode == "whole") {
        if (!(want in at) || !nq[at[want]] || rbadq[at[want]]) exit
        i = at[want]
        for (k = 1; k <= nq[i]; k++) if (!(rq[i, k] in wholeq)) exit
        print "whole"
        exit
      }
      if (mode == "range") {
        if ((want in at) && nq[at[want]]) {
          i = at[want]
          if (rbadq[i] || livehead == "" || live_oldest(i, 1) == "") exit
          for (k = 1; k <= nq[i]; k++) {
            h = prvq[rq[i, k]]
            if (h != livehead && !(h in pst)) { pst[h] = 1; print h }
          }
          exit
        }
        if (("review" in prvh) && livehead != "" && livehead != prvh["review"]) print prvh["review"] ".." livehead
        exit
      }
      # Handed a question (wave-27 T10), the read rows are matched by it, never by their Files: a
      # pass is the row carrying the question it read, whatever its record is called. A row with
      # no question is matched by its Files, as before.
      # Handed a reader too (T43; review pass 17 F3), a read row is returned only as that reader
      # own row, once every question it carries was last read at the head this question just was.
      if (mode == "liverows") {
        ne = split(evid, ev, " "); liver = ENVIRON["_UNITS_READER"]
        for (i = 1; i <= n; i++) {
          if (!rlive[i]) continue
          if (liveq != "" && nq[i]) {
            if (!((i, liveq) in hasq)) continue
            if (liver != "") {
              if (agt[i] != liver || !(liveq in prvq)) continue
              for (k = 1; k <= nq[i]; k++) if (!(rq[i, k] in prvq) || prvq[rq[i, k]] != prvq[liveq]) break
              if (k <= nq[i]) continue
            }
          }
          else if (ne) { for (k = 1; k <= ne; k++) if (writes(i, ev[k])) break; if (k > ne) continue }
          printf "%s\t%s\t%s\n", id[i], knd[i], st[i]
        }
        exit
      }
      # THE FLOOR HOLDS (T52; review 14 B1, R1): every writer the floor row (want, or each open
      # verify or test row when want is empty) waits on through judge, kept when it has not
      # landed and writes the tracked tree. judge never names a row downstream of the floor.
      if (mode == "holds") {
        for (i = 1; i <= n; i++) {
          if (want != "") { if (id[i] != want) continue }
          else if (!(isopen(i) && (knd[i] == "verify" || knd[i] == "test"))) continue
          for (k = 1; k <= ntk[i]; k++) {
            if (judge(i, tk[i, k])) continue
            for (w = 1; w <= nw; w++) {
              j = wj[w]
              if (code[j] && st[j] != satisfied && st[j] != "dropped") hold[j] = 1
            }
          }
        }
        for (j = 1; j <= n; j++) if (j in hold) printf "%s\t%s\t%s\n", id[j], stp[j], st[j]
        exit
      }
      # THE FLOOR STATE, ASKED BEFORE ANYTHING IS PRINTED (wave-26 T64). A pending row this answer
      # judges, not held for its step, whose proof:floor read a proof line and no open writer would
      # satisfy needs the state; without it the program prints nothing and exits 3 (_units_sched).
      if ((mode == "ready" || mode == "held" || mode == "waiting") && floorst == "") {
        for (i = 1; i <= n; i++) {
          if (st[i] != "pending" || rowheld(i) != 0) continue
          for (k = 1; k <= ntk[i]; k++) if (tk[i, k] == "proof:floor") { judge(i, tk[i, k]); if (needfloor) exit 3 }
        }
      }
      for (i = 1; i <= n; i++) {
        if (mode == "edges") {
          if (!isopen(i)) continue
          for (k = 1; k <= ntk[i]; k++) {
            if (judge(i, tk[i, k])) continue
            for (w = 1; w <= nw; w++) if (isopen(wj[w])) printf "%s\t%s\t%s\n", id[wj[w]], id[i], tk[i, k]
          }
          if (st[i] == "pending" && bang(i) > 0) for (h = 1; h <= nh; h++) printf "%s\t%s\t%s\n", id[hb[h]], id[i], hp[h]
          continue
        }
        if (st[i] != "pending") continue
        held = rowheld(i)
        if (held == 2) continue
        skipfloor = held
        if (mode == "waiting" && held) printf "%s\tstep:%s\t-\t-\n", id[i], stp[i]
        # THE READY AND HELD ANSWERS STOP AT THE FIRST READ THAT DECIDES THEM (T35 F7): ready needs
        # one unmet read to say no, held one unmet read that is not ext:. Waiting names them all.
        unmet = 0; other = 0; ext = ""
        for (k = 1; k <= ntk[i]; k++) {
          if ((mode == "ready" && unmet) || (mode == "held" && other)) break
          t = tk[i, k]
          if (judge(i, t)) continue
          unmet++
          if (t ~ extre) ext = ext (ext == "" ? "" : " ") t; else other++
          if (mode != "waiting") continue
          if (nw == 0) printf "%s\t%s\t-\t-\n", id[i], (lwhy == "" ? t : t (t ~ /:$/ ? " " : ": ") lwhy)
          for (w = 1; w <= nw; w++) printf "%s\t%s\t%s\t%s\n", id[i], t, id[wj[w]], st[wj[w]]
        }
        if ((mode == "ready" && unmet) || (mode == "held" && other)) continue
        if (bang(i) > 0) {
          unmet++; other++
          if (mode == "waiting") for (h = 1; h <= nh; h++) printf "%s\t%s\t%s\t%s\n", id[i], hp[h], id[hb[h]], st[hb[h]]
        }
        if (mode == "ready" && !held && unmet == 0) print id[i]
        if (mode == "held" && other == 0) {
          if (held) printf "%s: step %s %s row waits for current: %s\n", id[i], stp[i], knd[i], stp[i]
          if (ext != "") printf "%s: held by %s\n", id[i], ext
        }
      }
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
# status in pending · active · landed · dropped; every dep naming an id present in the table
# or an external prerequisite `ext:<slug>` (wave-21 T4; `_units_ext_re` is its one shape).
# A TABLE WITH A `reads` COLUMN (wave-26 T2; D1) adds two: its deps cells carry `ext:<slug>`
# and nothing else — a task id there is refused, because the row waits on what it reads — and
# each read names a path in the `Files` grammar, `head`, `record`, `merge`, `proof:<floor|
# review|task|check>` (`check` wave-27 T16), `approval:<name>`, `ext:<slug>`, or `live:` before one of the artifacts or a
# path; on a review row, `live:head:<q>[+<q>]` too, each question one of lib/proof.sh
# PROOF_QUESTIONS (wave-27 T10; D4). And an open verify or test row whose written cell holds no
# bare `head` is refused, naming the row and the token (wave-30 T13; AC-4.3, D7): the default
# `approval:plan, head` is the structural readiness of a full run, and the cell may not drop it.
#
# NO ORDERING RULE (wave-26 T2; D2). Through 1.10 a Step-N row with N ≥ 5 had to depend,
# transitively, on every Step-4 row, and a mid-run build row re-barriered every later row
# (research R3 B4, B6). A row now waits for what it reads; the validator has nothing to say
# about which rows precede which.
#
# EVERY LINE NAMES THE OFFENDING ID AND THE RULE, because the Step-3 wall prints these back
# to whoever tried to write the plan and "the table is invalid" is not a thing anyone can act
# on. Table-level faults — an absent section, a missing column — are named against
# `## Tasks`, since there is no row to blame.
#
# EVERY FAULT IS REPORTED, not just the first. A writer fixing one line at a time against a
# wall that stops at the first complaint pays a round trip per fault.
units_validate() {
  local plan="${1:-}" out rc ctl missing cols over rows violations cycles _c _o found=0 haswt hasreads

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
  hasreads=0
  if units_has_column "$plan" reads; then hasreads=1; fi

  rows="$(printf '%s\n' "$out" | awk 'NR > 1')"
  if [ -n "$rows" ]; then
    violations="$(printf '%s\n' "$rows" | awk -F'\t' -v over="$over" -v haswt="$haswt" -v hasreads="$hasreads" \
      -v extre="$(_units_ext_re)" -v pq="${PROOF_QUESTIONS:-}" "$(_units_questions_awk)$(_units_files_awk)"'
      BEGIN {
        # EVERY CELL OF A SHIFTED ROW IS SUSPECT, so the row is neither accused nor used to
        # accuse: none of its cells can be trusted to name what it breaks.
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
      { n++; id[n] = $1; stp[n] = $2; knd[n] = $3; dep[n] = $6; fil[n] = $9; sta[n] = $10; wtc[n] = $11
        bsc[n] = $12; rd[n] = $13; count[$1]++ }
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
          #
          # ONLY A ROW THAT WRITES THE HEAD (wave-26 T32). A row whose Files cell names no
          # tracked path (a verify, a review, a doc record under the docs root) commits nothing
          # a gate must attribute, so it runs active with no tree of its own; writes_head is
          # the predicate the scheduler asks of the same cell.
          if (haswt == 1 && sta[i] == "active" && wtc[i] !~ /[A-Za-z0-9]/ && writes_head(fil[i]))
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

          # BLANKS AROUND A TOKEN ARE PADDING; A BLANK INSIDE ONE IS NOT (wave-21 T13). The
          # cell used to lose every blank before it was split, so `ext:ci green` was admitted
          # as `ext:cigreen`, a token nobody wrote. Each token is trimmed at its ends only, and
          # one still holding a blank is refused naming what the author wrote.
          d = dep[i]
          if (d ~ /[A-Za-z0-9]/) {
            m = split(d, a, ",")
            for (j = 1; j <= m; j++) {
              gsub(/^[ \t]+|[ \t]+$/, "", a[j])
              if (a[j] == "" || a[j] !~ /[A-Za-z0-9]/) continue
              # AN EXTERNAL PREREQUISITE NAMES NO ROW BY DESIGN (wave-21 T4; D3, ADR-037
              # decision 2): `ext:<slug>` in its one shape is admitted in either table shape.
              if (a[j] ~ extre) continue
              # A TABLE WITH A reads COLUMN TAKES NOTHING ELSE IN deps (wave-26 T2; D1): a row
              # there waits for what it reads, and a task id beside the column is the hand-kept
              # edge the column exists to retire.
              if (hasreads) { printf "%s: dep %s is not ext:<slug>; a table with a reads column waits on what a row reads, never on a task id\n", id[i], a[j]; continue }
              if (a[j] ~ /[ \t]/) { printf "%s: dep %s names no row in the table\n", id[i], a[j]; continue }
              # Any other id the table does not carry, a malformed token included, is refused.
              if (!(a[j] in count)) printf "%s: dep %s names no row in the table\n", id[i], a[j]
            }
          }

          # A READ NAMES SOMETHING (wave-26 T2; D1): a path in the Files grammar, a named
          # artifact, `ext:<slug>`, or `live:` before an artifact or a path. A token naming
          # none of them is refused here, and the readiness program never reads it satisfied.
          ap = 0; hh = 0
          r = rd[i]
          if (hasreads && r ~ /[A-Za-z0-9]/) {
            m = split(r, a, ",")
            for (j = 1; j <= m; j++) {
              gsub(/^[ \t]+|[ \t]+$/, "", a[j])
              if (a[j] == "" || a[j] !~ /[A-Za-z0-9]/) continue
              t = a[j]
              if (t == "head") hh = 1
              if (t ~ extre) continue
              # A READ ROW NAMES ITS QUESTIONS (wave-27 T10; D4): `live:head:<q>[+<q>]`, each one
              # of lib/proof.sh PROOF_QUESTIONS, on a review row and nowhere else.
              if (substr(t, 1, 10) == "live:head:") {
                if (knd[i] != "review") { printf "%s: read %s names questions; only a review row reads them\n", id[i], a[j]; continue }
                nqa = split(substr(t, 11), qa, "+"); qbad = (nqa == 0)
                for (k = 1; k <= nqa; k++) if (!isq(qa[k])) qbad = 1
                if (qbad) printf "%s: read %s names a question outside %s\n", id[i], a[j], pq
                continue
              }
              if (substr(t, 1, 5) == "live:") t = substr(t, 6)
              if (t ~ /^approval:[A-Za-z0-9]/) ap = 1
              if (t == "head" || t == "record" || t == "merge") continue
              if (t ~ /^proof:(floor|review|task|check)$/ || t ~ /^approval:[A-Za-z0-9][A-Za-z0-9._-]*$/) continue
              if (t ~ /[\/.*?]/ && t !~ /[ \t:!]/) {
                if (index(t, "[") || index(t, "]")) printf "%s: read %s has a bracket; paths glob with * and ? only, so it would match the bracket as itself\n", id[i], a[j]
                continue
              }
              printf "%s: read %s names no artifact\n", id[i], a[j]
            }
            # A VERIFY OR TEST ROW READS head (wave-30 T13; REQ-4 AC-4.3; D7, Delta-6a). Its kind default,
            # approval:plan, head, waits on every open row that writes code, so a full run is never
            # ready beside an open build; wave-28 overrode the cell with a record path and ran it
            # early. A cell that is written and holds no bare head is refused, naming the row and the
            # token. live:head is not head: it waits on no open writer. An empty cell takes the
            # default; a doc row is not held (its Files are not code); and only an OPEN row, since a
            # landed or dropped one schedules nothing and a plan carrying one must still commit
            # (A-T13.1).
            if ((knd[i] == "verify" || knd[i] == "test") && !hh && (sta[i] == "pending" || sta[i] == "active")) {
              rc0 = r; gsub(/^[ \t]+|[ \t]+$/, "", rc0)
              printf "%s: reads %s drops head; a %s row must read head (its default approval:plan, head waits on every open row that writes code)\n", id[i], rc0, knd[i]
            }
          }

          # THE RELEASE READS ITS APPROVAL (wave-26 T62; critic 2 K2-F3; D3). A doc row at Step 7
          # or later is the release, the row the hold of a table without the column names so; on
          # its kind default it would be ready beside the floor with no approval at all. An open
          # one names the approval it waits for, approval:release, or approval:plan for a
          # document that needs no release.
          if (hasreads && !ap && knd[i] == "doc" && stp[i] ~ /^[0-9]+$/ && stp[i] + 0 >= 7 && (sta[i] == "pending" || sta[i] == "active"))
            printf "%s: a doc row at step 7 or later is the release and must read the approval it waits for; add approval:release to its reads (approval:plan for a document that needs no release)\n", id[i]

          # A BRACKET IN A Files ENTRY CANNOT BE COMPILED AS WRITTEN (wave-26 T35; review 5 F5). The
          # grammar globs with * and ? only; the readiness program reads a bracket as itself, so an
          # author who wrote a class would get a literal match. Entries are taken the way the
          # readiness program takes them: a bare word, a dash or an entry with a blank declares
          # nothing, and the unmergeable mark is not part of the path.
          m = split(fil[i], a, ",")
          for (j = 1; j <= m; j++) {
            gsub(/^[ \t]+|[ \t]+$/, "", a[j]); sub(/^\.\//, "", a[j])
            if (a[j] == "" || a[j] !~ /[\/.*?]/ || a[j] ~ /[ \t]/) continue
            sub(/!$/, "", a[j])
            if (index(a[j], "[") || index(a[j], "]")) printf "%s: Files entry %s has a bracket; Files globs with * and ? only, so it would match the bracket as itself\n", id[i], a[j]
          }
        }
      }')"
    if [ -n "$violations" ]; then
      printf '%s\n' "$violations"
      found=1
    fi

    # A CYCLE OF WAITS IS A DEADLOCK NOTHING ELSE REPORTS (wave-26 T35; review 5 F3). Each row on
    # it is waiting, each names the other as its writer, and a wall built on "nothing ready, all
    # waiting" sees an ordinary wait. The edges are `units_edges`' own, so the check sees every
    # wait the scheduler acts on: a settled read, a task-id dep, and the unmergeable hold, which
    # closes a loop as surely as a read (`lib/x.sh!` held by one row that reads what the other
    # writes). Only PENDING rows can be stuck: an active row is already running and lands, and
    # the wait clears, so a loop through one is no deadlock. One line per cycle, named against
    # its first row in table order; a row that merely waits behind a cycle is not on it.
    cycles="$({ printf '%s\n' "$rows"; printf '\034edges\n'; _units_sched edges "$plan" "" 2>/dev/null; } \
      | awk -F'\t' '
      $0 == SUBSEP "edges" { part = 1; next }
      !part { if ($1 != "") { n++; id[n] = $1; at[$1] = n; if ($10 == "pending") pend[n] = 1 }; next }
      {
        f = at[$1]; t = at[$2]
        if (!f || !t || !pend[f] || !pend[t] || ((f, t) in e)) next
        e[f, t] = 1; nout[f]++; out[f, nout[f]] = t; nin[t]++; inn[t, nin[t]] = f
      }
      END {
        # PRUNE what cannot be on a cycle: a row nothing waits on, or that waits on nothing left.
        for (i = 1; i <= n; i++) if (pend[i]) { live[i] = 1; din[i] = nin[i]; dout[i] = nout[i] }
        do {
          gone = 0
          for (i = 1; i <= n; i++) {
            if (!live[i] || (din[i] && dout[i])) continue
            live[i] = 0; gone = 1
            for (k = 1; k <= nout[i]; k++) din[out[i, k]]--
            for (k = 1; k <= nin[i]; k++) dout[inn[i, k]]--
          }
        } while (gone)
        # WHAT IS LEFT lies on a cycle or between two; a cycle is a set of rows each reaching the
        # others, so each left row is grouped with the rows it reaches and is reached by.
        for (i = 1; i <= n; i++) {
          if (!live[i] || grp[i]) continue
          split("", fw); split("", bw); fw[i] = 1; bw[i] = 1
          do { more = 0
            for (a = 1; a <= n; a++) {
              if (!live[a]) continue
              if (fw[a]) for (k = 1; k <= nout[a]; k++) if (live[out[a, k]] && !fw[out[a, k]]) { fw[out[a, k]] = 1; more = 1 }
              if (bw[a]) for (k = 1; k <= nin[a]; k++) if (live[inn[a, k]] && !bw[inn[a, k]]) { bw[inn[a, k]] = 1; more = 1 }
            }
          } while (more)
          s = ""; c = 0
          for (a = 1; a <= n; a++) if (fw[a] && bw[a]) { grp[a] = 1; s = s (c++ ? ", " : "") id[a] }
          # A ROW THAT WAITS ON ITSELF is a cycle of one (wave-26 T32; review 7 F5): its group
          # holds only itself, so the count alone never named it, and it was never ready.
          if (c > 1 || ((i, i) in e)) printf "%s: read cycle through %s; each waits on the next, so none can ever be ready\n", id[i], s
        }
      }')"
    if [ -n "$cycles" ]; then
      printf '%s\n' "$cycles"
      found=1
    fi
  fi

  [ "$found" -eq 0 ]
}

# units_findings <plan> <roster> -> one line per LEDGER FINDING, table order; exit 1 if any.
#
# THE ONE LEDGER READER (wave-21 T5; REQ-4, AC-4.1, AC-4.3; D4, ADR-037 decision 3). Three
# findings and no more, each naming its row:
#
#   status <id> <value>    the row's status is outside the scale's enum — `(empty)` for a blank
#                          cell, the spelling `units_validate` uses
#   evidence <id>          the row is at the scale's terminal word and `## SDLC State` carries
#                          no non-empty `- <id>:` line for it
#   launch <id> <agent>    the row is `active`, its agent cell names someone, and no
#                          `roster-state/` row on <roster> carries that `name=`
#
# BOTH CALLERS ASK THIS AND NEITHER PARSES THE TABLE. The commit gate refuses on these lines and
# the Patrol tick prints them as `poker: LEDGER <id> <kind> [<value>]`, so a plan the gate would
# refuse cannot tick clean and a plan that ticks a finding cannot commit (AC-4.1).
#
# LAUNCHED IS WHAT THE ROSTER SAYS (Δ4, Chris "Option 3"). The `- T<n>:` line was a hand copy of
# the launch record the dispatch hook writes to the roster, owed at `active` and checked by
# nothing until a writer's first commit. The roster is now the record: an `active` row whose
# agent cell is a roster `name=` owes no line. The line is owed where it carries something only
# a human can write — the evidence — at `done` (task scale) or `landed` (wave scale).
#
# SELF-OWNED IS AN AGENT CELL WITH NO ALPHANUMERIC — empty, an em dash, a hyphen — the same
# four-spellings-of-nothing reading the `deps` and `worktree` cells take. Nobody was launched
# for that row, so neither a roster row nor a line is asked of it. A task-scale table has no
# agent column at all, so every task-scale row is self-owned.
#
# NO ROSTER TO READ, TODAY'S RULE (spec assumption 1). An empty <roster>, a path naming no
# regular file, or a symlink (the fleet never follows one into a roster) computes no `launch`
# finding: an agent-named `active` row then owes its line, exactly as it did before this
# reader. A missing roster therefore fails toward the old refusal, never toward silence.
#
# THE SCALE COMES FROM THE HEADER, the discriminator the gate's row arm already uses: a table
# with a `step` column is a wave table (pending · active · landed · dropped, terminal `landed`);
# one without is the task-scale ledger (pending · active · done · dropped, terminal `done`).
#
# ONLY `T<digit>…` ROWS ARE JUDGED, as the gate's arms have always filtered: a legend or a
# non-unit row in the table is not a ledger row. No table is no finding, exit 0.
#
# ONE PARSE PER CALL. The reader asks the table twice — its rows, then whether the header
# carries `step` — so it runs under `units_memoised`; a caller already holding a memo for the
# plan (the tick) pays nothing more (wave-21 T13; review-bed/perf/report.md observation 3).
units_findings() { units_memoised "${1:-}" _units_ledger findings "${1:-}" "${2:-}"; }

# units_unlined <plan> -> the `T<digit>…` ids with no non-empty `- <id>:` line under
# `## SDLC State`, table order, whatever their status; always exit 0.
#
# THE LOOKUP THE GATE'S ADDRESSED-UNIT ARM COUNTS (wave-21 T5). It lived in walls.sh as
# `missing_evidence_ids`, a grep over the gate's own `## SDLC State` extract asked once per row;
# it is the same question `units_findings` asks for its `evidence` finding, so it is answered by
# the same program and the two cannot disagree about whether a row has its line.
units_unlined() { _units_ledger unlined "${1:-}" ""; }

# _units_ledger <findings|unlined> <plan> <roster> — the ONE program behind both verbs.
#
# THE `- <id>:` LOOKUP IS THE GATE'S, TO THE BYTE OF ITS MEANING: line endings normalised
# (`normalize_newlines`' two substitutions), fences skipped, every `## SDLC State` section read
# up to the next `## ` heading, and for each id the FIRST line shaped
# `^[[:space:]]*-?[[:space:]]*<id>[[:space:]]*:` — its value trimmed, an empty value counting as
# no line. Keyed on the whole id, so `- T1:` never answers for T10.
#
# ONE STREAM, THREE PARTS, each opened by a SUBSEP-led marker line no table row, plan line or
# roster row can begin with: the rows (`units_rows`, so a memoised caller pays no second parse),
# the plan's text, and — only when there is one to read — the roster.
_units_ledger() {
  local mode="${1:-}" plan="${2:-}" roster="${3:-}" rows scale=wave useroster=0
  rows="$(units_rows "$plan")" || return 0
  [ -n "$rows" ] || return 0
  units_has_column "$plan" step || scale=task
  if [ -n "$roster" ] && [ -f "$roster" ] && [ ! -L "$roster" ]; then useroster=1; fi
  {
    printf '\034rows\n'; printf '%s\n' "$rows"
    printf '\034plan\n'; awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$plan" 2>/dev/null
    if [ "$useroster" -eq 1 ]; then printf '\034roster\n'; cat "$roster" 2>/dev/null; fi
  } | awk -F'\t' -v mode="$mode" -v scale="$scale" -v useroster="$useroster" '
    $0 == SUBSEP "rows"   { part = 1; next }
    $0 == SUBSEP "plan"   { part = 2; next }
    $0 == SUBSEP "roster" { part = 3; next }
    part == 1 {
      if ($1 == "") next
      n++; id[n] = $1; ag[n] = $5; st[n] = $10
      next
    }
    part == 2 {
      if ($0 ~ /^[[:space:]]*```/) { fence = !fence; next }
      if (fence) next
      if ($0 ~ /^## SDLC State/) { insec = 1; next }
      if ($0 ~ /^## /) { insec = 0 }
      if (!insec) next
      l = $0
      sub(/^[[:space:]]*-?[[:space:]]*/, "", l)
      c = index(l, ":")
      if (c == 0) next
      k = substr(l, 1, c - 1)
      sub(/[[:space:]]+$/, "", k)
      if (k == "" || (k in seen)) next
      seen[k] = 1
      v = substr(l, c + 1)
      sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
      val[k] = v
      next
    }
    part == 3 {
      # A LAUNCH ROW, by its schema prefix — never a `landing-swept/` marker, which carries a
      # `name=` too. The FIRST `name=` field, the fleet-wide by-key reading (roster.sh).
      if (index($0, "roster-state/") != 1) next
      m = split($0, f, "|")
      for (j = 2; j <= m; j++) if (index(f[j], "name=") == 1) { names[substr(f[j], 6)] = 1; break }
      next
    }
    END {
      if (scale == "task") { split("pending active done dropped", e, " "); term = "done" }
      else                 { split("pending active landed dropped", e, " "); term = "landed" }
      for (i in e) enum[e[i]] = 1
      found = 0
      for (i = 1; i <= n; i++) {
        if (id[i] !~ /^T[0-9]/) continue
        lined = ((id[i] in val) && val[id[i]] != "")
        if (mode == "unlined") { if (!lined) print id[i]; continue }
        if (!(st[i] in enum)) {
          printf "status %s %s\n", id[i], (st[i] == "" ? "(empty)" : st[i]); found = 1; continue
        }
        if (st[i] == term) {
          if (!lined) { printf "evidence %s\n", id[i]; found = 1 }
          continue
        }
        if (st[i] != "active" || ag[i] !~ /[A-Za-z0-9]/) continue
        if (useroster == 1) {
          if (!(ag[i] in names)) { printf "launch %s %s\n", id[i], ag[i]; found = 1 }
        } else if (!lined) { printf "evidence %s\n", id[i]; found = 1 }
      }
      exit (found ? 1 : 0)
    }'
}

# units_add_row <plan> <id> <step> <kind> <task> <agent> <deps> <size> <serves> <Files> [<reads>]
#   -> the WHOLE plan with one `## Tasks` row added, on stdout; exit 1 and silent when the plan
#      carries no `## Tasks` table or no `## SDLC State` section. Nothing is written.
#
# THE PROJECTOR UNDER `task-add` (wave-20 REQ-5, AC-5.3; Δ5). A mid-run row needs two edits to
# pass the commit gate, which refuses any commit while a task row has no `- T<n>:` line under
# `## SDLC State` — and it refuses the WRITER, not the author of the row, so a hand edit that
# forgets the line stalls every writer in the wave at its next commit:
#
#   1. THE ROW, as the table's last data row, cells placed by the HEADER's column order (the
#      table is header-keyed, so the projection follows whatever order this plan carries);
#      status `pending`, `reads` from the optional eleventh operand (a table without the column
#      drops it, as it drops any value it has no column for), and `—` for `worktree`, `base`
#      and any column this library does not read. A `|` inside a value is written `\|`, the
#      one escape a GFM cell defines.
#   2. ITS `- <id>:` LINE under `## SDLC State`, after the last `- T<n>:` line and that line's
#      indented continuation — or at the end of the section when the plan carries none yet.
#      `pending dispatch — added by task-add at <iso>` is not a placeholder to the evidence
#      gate (`is_placeholder_value` refuses only the bare words).
#
# NO OTHER ROW IS EDITED IN A TABLE WITH reads (wave-26 T2; D2): its rows wait on what they read,
# the floor on `head`, so a new row changes nothing but itself and its line. A TABLE WITHOUT THE
# COLUMN KEEPS 1.10's THREADING (wave-26 T62; critic 2 K2-F1): there the deps are the only thing
# that holds the floor, so a Step-4 id is appended to the deps of every open Step-5+ row on the
# frontier — those that do not reach it, less any that reaches another of them which does not
# reach it back. The validator no longer demands the edge; the floor needs it.
#
# PURE, AS EVERY VERB HERE IS: it prints and never writes, so `task-add` can judge the
# projection (the validator, then a dry commit through the real gate) before anything is
# swapped in, and a refusal leaves the plan byte-identical. Fence-aware like `_units_read`:
# a table or a state line inside a ``` example is documentation and is never edited.
units_add_row() {
  local plan="${1:-}" nid="${2:-}" nstep="${3:-}" now
  [ -n "$plan" ] && [ -f "$plan" ] || return 1
  _units_table "$plan" >/dev/null 2>&1 || return 1
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  # EVERY OPERAND REACHES awk THROUGH ENVIRON, NEVER -v (wave-20 T10b, review R6). `-v`
  # interprets backslash escapes, so `C:\new\table` arrived as `C:<newline>ew<tab>able` and a
  # `\t` in a serves cell became a space. ENVIRON hands awk the bytes the author typed — the
  # rule roster.sh's docblock already states for file paths.
  UA_NID="$nid" UA_NSTEP="$nstep" UA_NKIND="${4:-}" UA_NTASK="${5:-}" UA_NAGENT="${6:-}" \
  UA_NDEPS="${7:-}" UA_NSIZE="${8:-}" UA_NSERVES="${9:-}" UA_NFILES="${10:-}" UA_NREADS="${11:-}" \
  UA_NOW="$now" awk '
    BEGIN {
      nid = ENVIRON["UA_NID"]; nstep = ENVIRON["UA_NSTEP"]; nkind = ENVIRON["UA_NKIND"]
      ntask = ENVIRON["UA_NTASK"]; nagent = ENVIRON["UA_NAGENT"]; ndeps = ENVIRON["UA_NDEPS"]
      nsize = ENVIRON["UA_NSIZE"]; nserves = ENVIRON["UA_NSERVES"]; nfiles = ENVIRON["UA_NFILES"]
      nreads = ENVIRON["UA_NREADS"]; now = ENVIRON["UA_NOW"]
    }
    function trim(v) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); return v }
    # A VALUE BECOMES A CELL: tabs and line breaks to spaces, every RAW `|` escaped by
    # concatenation (a backslash in a gsub replacement is the one character awks disagree on),
    # and an empty value spelled `—`, which is how the table itself writes "none". An author
    # who already wrote `\|` wrote the cell escape; it is folded aside first and kept as typed
    # (T10b), where escaping it again would print `\\|`.
    function cellv(v,   parts, m, i, out) {
      gsub(/[\t\r\n]/, " ", v); v = trim(v)
      v = esc(v)
      m = split(v, parts, "|"); out = parts[1]
      for (i = 2; i <= m; i++) out = out "\\" "|" parts[i]
      out = unesc(out)
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
    # reach(s, c) -> R[c, <id>] for every id candidate c reaches through deps from row s,
    # breadth-first; an id is queued once, so a cycle ends.
    function reach(s, c,   q, h, qn, k, n2, b) {
      qn = 0; split("", seen)
      n2 = split(adj[s], b, ",")
      for (k = 1; k <= n2; k++) if (b[k] ~ /[A-Za-z0-9]/ && !(b[k] in seen)) { seen[b[k]] = 1; q[++qn] = b[k] }
      for (h = 1; h <= qn; h++) {
        R[c, q[h]] = 1
        n2 = split(adj[q[h]], b, ",")
        for (k = 1; k <= n2; k++) if (b[k] ~ /[A-Za-z0-9]/ && !(b[k] in seen)) { seen[b[k]] = 1; q[++qn] = b[k] }
      }
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
          if (nstep != "4" || ("reads" in col) || !("deps" in col)) continue
          split(esc(line), f, "|"); rid = trim(f[col["id"]])
          if (rid == "" || rid ~ /^[-: ]+$/) continue
          nr++; rl[nr] = i; rid_[nr] = rid; rstp[nr] = trim(f[col["step"]]); rsta[nr] = trim(f[col["status"]])
          d = f[col["deps"]]; gsub(/[ \t]/, "", d); adj[rid] = d
        }
      }
      if (!lastrow || !seensdlc) exit 1
      # A TABLE WITHOUT reads KEEPS 1.10 THREADING (wave-26 T62; critic 2 K2-F1). With no head
      # read, a mid-run Step-4 row holds the floor only through deps, so its id goes into every
      # open Step-5+ row that does not reach it, except one that reaches another such row that
      # does not reach it back: that row repairs it (the frontier of c81d865e units_add_row).
      if (nr) {
        adj[nid] = ndeps; gsub(/[ \t]/, "", adj[nid])
        nc = 0
        for (r = 1; r <= nr; r++) {
          if (rstp[r] !~ /^[0-9]+$/ || rstp[r] + 0 < 5 || rsta[r] == "landed" || rsta[r] == "dropped") continue
          cr[++nc] = r; reach(rid_[r], nc)
        }
        for (c = 1; c <= nc; c++) {
          if ((c, nid) in R) continue
          fold = 0
          for (e = 1; e <= nc && !fold; e++)
            if (e != c && !((e, nid) in R) && ((c, rid_[cr[e]]) in R) && !((e, rid_[cr[c]]) in R)) fold = 1
          if (!fold) thread[rl[cr[c]]] = 1
        }
        for (r in thread) {
          m = split(esc(L[r]), f, "|"); dc = col["deps"]; d = trim(f[dc])
          f[dc] = " " ((d ~ /[A-Za-z0-9]/) ? d ", " nid : nid) " "
          out = f[1]; for (c = 2; c <= m; c++) out = out "|" f[c]
          L[r] = unesc(out)
        }
      }
      val["id"] = nid; val["step"] = nstep; val["kind"] = nkind; val["rigor"] = nkind
      val["task"] = ntask; val["agent"] = nagent; val["deps"] = ndeps; val["size"] = nsize
      val["serves"] = nserves; val["files"] = nfiles; val["status"] = "pending"; val["reads"] = nreads
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

# ── THE PLAN-ROW PROJECTORS (wave-24 T15; REQ-9, D14) ─────────────────────────
#
# Four more projectors in `units_add_row`'s mould, one per hand edit a run used to make to its
# own plan: a cell of a table row, a `- Step N:` or `- T<n>:` line, `current:`, and the
# fields of a step's evidence block. The poker's plan-row verbs (`task-set`, `ledger-add`,
# `ledger-set`, `step-line`, `current`) each run one of them onto a COPY and judge the copy
# before anything is swapped in — the task-add transaction, unchanged.
#
# PURE, AS EVERY VERB HERE IS: each prints the WHOLE plan and writes nothing. Fence-aware like
# `_units_read`: a table or a state line inside a ``` example is documentation and is never
# edited. Every operand reaches awk through ENVIRON, never -v (T10b: -v interprets
# backslashes). Every line a projector does not own is printed as it was read, byte for byte,
# so `git diff` of a projection shows the target line and nothing else.
#
# A VALUE MAY CARRY NO `|`, TAB OR LINE BREAK (AC-9.2). `units_add_row` escapes a pipe because
# its operands are an author's prose; these operands are cell values typed at a prompt, and a
# pipe there is far likelier a slip than a cell meant to hold one. The caller refuses first,
# and each projector refuses again (exit 4) rather than trust it.

# units_table_cells <plan> <set|add> <section> <id> <name=value>… -> the whole plan with the
#   row whose id cell is <id> given those cells (`set`), or a new row with that id appended
#   after the table's last row (`add`; unnamed cells `—`). <section> is `tasks` (the first
#   `## Tasks` table, the one `_units_read` parses) or `ledger` (the first `## Dispatch ledger`
#   table). Names are the header's own cells, matched case-insensitively; `kind` and `rigor`
#   name slot 3 at either scale, as `_units_read` takes them.
#   Exit 1 no such table · 2 `set`: no row with that id, `add`: the id is taken · 3 a name the
#   header does not carry · 4 a value with a forbidden byte · 5 `set`: more than one row with
#   that id. Silent on every refusal.
#
# THE ROW IS RE-JOINED CELL FOR CELL. A set cell is written ` <value> `; every other cell keeps
# its bytes, `\|` escapes included — they are folded to SUBSEP before the split and restored
# after, the rule `units_add_row` states.
units_table_cells() {
  local plan="${1:-}" mode="${2:-}" sect="${3:-}" id="${4:-}" pairs="" kv
  [ -n "$plan" ] && [ -f "$plan" ] && [ -n "$id" ] || return 1
  case "$mode" in set|add) : ;; *) return 1 ;; esac
  case "$sect" in tasks|ledger) : ;; *) return 1 ;; esac
  shift 4
  for kv in "$@"; do
    case "$kv" in *=*) : ;; *) return 3 ;; esac
    case "$kv" in *'|'*|*$'\t'*|*$'\n'*|*$'\r'*) return 4 ;; esac
    pairs="${pairs}${kv%%=*}"$'\t'"${kv#*=}"$'\n'
  done
  UT_MODE="$mode" UT_SECT="$sect" UT_ID="$id" UT_PAIRS="$pairs" awk '
    function trim(v) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); return v }
    function esc(v)  { gsub(/\\[|]/, SUBSEP, v); return v }
    function unesc(v,   parts, m, i, out) {
      m = split(v, parts, SUBSEP); out = parts[1]
      for (i = 2; i <= m; i++) out = out "\\" "|" parts[i]
      return out
    }
    BEGIN {
      mode = ENVIRON["UT_MODE"]; sect = ENVIRON["UT_SECT"]; want = ENVIRON["UT_ID"]
      np = split(ENVIRON["UT_PAIRS"], pl, "\n")
      for (p = 1; p <= np; p++) {
        if (pl[p] == "") continue
        t = index(pl[p], "\t")
        k = tolower(substr(pl[p], 1, t - 1)); v = substr(pl[p], t + 1)
        if (sect == "tasks" && k == "rigor") k = "kind"
        nk++; key[nk] = k; val[k] = (trim(v) == "" ? "—" : trim(v))
      }
    }
    { L[++nl] = $0 }
    END {
      state = 0
      for (i = 1; i <= nl; i++) {
        line = L[i]
        if (line ~ /^[ \t]*```/) { fence = !fence; continue }
        if (fence) continue
        if (line ~ /^[ \t]*#/) {
          if (state == 1 || state == 2) { state = 3; continue }
          if (state == 0 && sect == "tasks" && line ~ /^##[ \t]+[Tt]asks([ \t].*)?$/) state = 1
          if (state == 0 && sect == "ledger" && line ~ /^##[ \t]+[Dd]ispatch[ \t]+[Ll]edger([ \t].*)?$/) state = 1
          continue
        }
        if (state == 1) {
          if (line !~ /^[ \t]*\|/) continue
          nh = split(esc(line), hc, "|")
          for (c = 1; c <= nh; c++) {
            t = tolower(trim(hc[c]))
            if (sect == "tasks" && t == "rigor") t = "kind"
            if (t != "" && !(t in col)) { col[t] = c; name[c] = t }
          }
          if (!("id" in col)) { split("", col); split("", name); continue }
          state = 2; continue
        }
        if (state == 2) {
          if (line !~ /^[ \t]*\|/) { state = 3; continue }
          lastrow = i
          m = split(esc(line), f, "|")
          if (trim(f[col["id"]]) == want) { hits++; at = i }
        }
      }
      if (!lastrow) exit 1
      for (p = 1; p <= nk; p++) if (!(key[p] in col)) exit 3
      if (mode == "set" && hits == 0) exit 2
      if (mode == "set" && hits > 1) exit 5
      if (mode == "add" && hits > 0) exit 2
      if (mode == "set") {
        m = split(esc(L[at]), f, "|")
        for (p = 1; p <= nk; p++) f[col[key[p]]] = " " val[key[p]] " "
        out = f[1]; for (c = 2; c <= m; c++) out = out "|" f[c]
        L[at] = unesc(out)
      } else {
        val["id"] = want
        row = "|"
        for (c = 2; c < nh; c++) row = row " " ((name[c] in val) ? val[name[c]] : "—") " |"
      }
      for (i = 1; i <= nl; i++) {
        print L[i]
        if (mode == "add" && i == lastrow) print row
      }
    }' "$plan"
}

# units_step_line <plan> <N|T<n>> <text> [append] -> the whole plan with that line of
#   `## SDLC State` reading `- Step N: <text>` (or `- T<n>: <text>`); with `append`, <text>
#   follows the line's own text after `; `. A line that is not there is added: a step line
#   after the last `Step M:` line and its indented block, a task line after the last `- T<n>:`
#   line (or, with none, at the end of the section). Exit 1 no `## SDLC State` · 4 a text with
#   a line break.
#
# THE LINE IS FOUND AS THE GATE FINDS IT: `^[ \t]*-?[ \t]*Step[ \t]+N[ \t]*:` (walls.sh's own
# pattern), the first one in the section. Its prefix — indent, marker, key, colon — is kept;
# only the text after it is replaced, and the block lines under it are not touched.
units_step_line() {
  local plan="${1:-}" key="${2:-}" text="${3:-}" app="${4:-}"
  [ -n "$plan" ] && [ -f "$plan" ] || return 1
  case "$text" in *$'\n'*|*$'\r'*) return 4 ;; esac
  US_KEY="$key" US_TEXT="$text" US_APP="$app" awk '
    BEGIN {
      key = ENVIRON["US_KEY"]; text = ENVIRON["US_TEXT"]; app = (ENVIRON["US_APP"] == "append")
      isstep = (key !~ /^T/)
      kq = key; gsub(/[.]/, "[.]", kq)
      pat = isstep ? ("^[ \t]*-?[ \t]*Step[ \t]+" kq "[ \t]*:") : ("^[ \t]*-?[ \t]*" kq "[ \t]*:")
    }
    { L[++nl] = $0 }
    END {
      for (i = 1; i <= nl; i++) {
        line = L[i]
        if (line ~ /^[ \t]*```/) { fence = !fence; continue }
        if (fence) continue
        if (line ~ /^##[ \t]/) {
          if (sdlc == 1) sdlc = 2
          if (!seen && line ~ /^##[ \t]+SDLC State([ \t].*)?$/) { sdlc = 1; seen = 1; last = i }
          continue
        }
        if (sdlc != 1) continue
        if (line ~ /[^ \t]/) last = i
        if (!at && match(line, pat)) at = i
        if (line ~ /^[ \t]*-?[ \t]*Step[ \t]+[0-9]+[ab]?[ \t]*:/) { sline = i; inst = 1; intl = 0; continue }
        if (line ~ /^[ \t]*-?[ \t]*T[0-9]+[ \t]*:/) { if (!tfirst) tfirst = i; tline = i; intl = 1; inst = 0; continue }
        if ((inst || intl) && line ~ /^[ \t]+[^ \t]/ && line !~ /^[ \t]*-/) {
          if (inst) sline = i; else tline = i
          continue
        }
        inst = 0; intl = 0
      }
      if (!seen) exit 1
      if (at) {
        line = L[at]; match(line, pat)
        pre = substr(line, 1, RLENGTH); rest = substr(line, RLENGTH + 1)
        sub(/^[ \t]+/, "", rest); sub(/[ \t]+$/, "", rest)
        L[at] = pre " " ((app && rest != "") ? rest "; " text : text)
      } else {
        # AFTER a line, or BEFORE the first task line when a step line has no step to follow.
        newl = (isstep ? "- Step " key ": " : "- " key ": ") text
        if (isstep && !sline && tfirst) before = tfirst
        else after = isstep ? (sline ? sline : last) : (tline ? tline : last)
      }
      for (i = 1; i <= nl; i++) {
        if (i == before) print newl
        print L[i]
        if (i == after) print newl
      }
    }' "$plan"
}

# units_step_text <plan> <N|T<n>> -> the text of that line of `## SDLC State`, found exactly as
#   `units_step_line` finds the line it writes (its pattern, fences skipped, the first one in the
#   section), blanks trimmed; nothing when the line is absent (wave-28 T6: `row-landed` adds to the
#   text a row's line already has). Exit 1 no `## SDLC State`.
units_step_text() {
  local plan="${1:-}" key="${2:-}"
  [ -n "$plan" ] && [ -f "$plan" ] || return 1
  US_KEY="$key" awk '
    BEGIN {
      key = ENVIRON["US_KEY"]; kq = key; gsub(/[.]/, "[.]", kq)
      pat = (key !~ /^T/) ? ("^[ \t]*-?[ \t]*Step[ \t]+" kq "[ \t]*:") : ("^[ \t]*-?[ \t]*" kq "[ \t]*:")
    }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^##[ \t]/ { if (sdlc == 1) sdlc = 2; if (!seen && $0 ~ /^##[ \t]+SDLC State([ \t].*)?$/) { sdlc = 1; seen = 1 }; next }
    sdlc == 1 && !found && match($0, pat) {
      r = substr($0, RLENGTH + 1); sub(/^[ \t]+/, "", r); sub(/[ \t]+$/, "", r); print r; found = 1
    }
    END { if (!seen) exit 1 }' "$plan"
}

# ── THE SPLIT (wave-30 T17; REQ-12 AC-12.6, D14d-3, Δ11) ──────────────────────
#
# Three readers under `session-poker.sh task-split`, the verb that rewrites one pending row as its
# children. The machine records a split; which row to split and where to cut it are the
# orchestrator's (steps/4.md, "Splitting a row"), so nothing here chooses either.
#
# units_split_check <parent id> <parent Files> <child id> <child Files> [<child id> <child Files>…]
#   -> one line per fault, exit 1 if any, else 0. THE CHILDREN ARE A COVER OF THE PARENT'S FILES:
#   each child entry is one of the parent's (`<child>: Files entry <path> is not one of <parent>'s
#   Files`), and each parent entry is some child's (`<parent>: Files entry <path> is in no child's
#   Files`). Entries are compared as the readiness program reads a Files cell: comma-split, blanks
#   trimmed, a leading `./` and the unmergeable `!` mark set aside, and an entry with no letter or
#   digit (`—`) declaring nothing. Two children may name one entry: a test file both halves edit
#   is ordinary, and the orchestrator orders them by their reads.
_units_split_tokens() {  # <Files cell> -> one entry per line, as compared
  printf '%s\n' "${1:-}" | tr ',' '\n' \
    | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); sub(/^\.\//, ""); sub(/!$/, ""); if ($0 ~ /[A-Za-z0-9]/) print }'
}
units_split_check() {
  local pid="${1:-}" ptok all="" cid t found=0
  ptok="$(_units_split_tokens "${2:-}")"
  shift 2 2>/dev/null || return 1
  while [ $# -ge 2 ]; do
    cid="$1"
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      all="${all}${t}"$'\n'
      printf '%s\n' "$ptok" | grep -Fxq -- "$t" && continue
      printf "%s: Files entry %s is not one of %s's Files\n" "$cid" "$t" "$pid"; found=1
    done <<EOF
$(_units_split_tokens "$2")
EOF
    shift 2
  done
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    printf '%s' "$all" | grep -Fxq -- "$t" && continue
    printf "%s: Files entry %s is in no child's Files\n" "$pid" "$t"; found=1
  done <<EOF
$ptok
EOF
  [ "$found" -eq 0 ]
}

# units_split_dependents <plan> <id> -> the ids of the rows that wait on <id>, table order, one per
#   line: an edge from it (`units_edges`: a read it satisfies, `head` among them, or an unmergeable
#   hold), or a deps token naming it, whatever the row's status. Exit 1 when there is no table.
units_split_dependents() {
  local plan="${1:-}" pid="${2:-}" rows
  rows="$(units_rows "$plan")" || return 1
  { units_edges "$plan" 2>/dev/null | awk -F'\t' -v p="$pid" '$1 == p { print "\034\t" $2 }'
    printf '%s\n' "$rows"; } | awk -F'\t' -v p="$pid" '
    $1 == "\034" { w[$2] = 1; next }
    $1 == "" || $1 == p { next }
    {
      n = split($6, d, ",")
      for (k = 1; k <= n; k++) { t = d[k]; gsub(/^[ \t]+|[ \t]+$/, "", t); if (t == p) w[$1] = 1 }
      if (($1 in w) && !($1 in out)) { out[$1] = 1; print $1 }
    }'
}

# units_split_row <plan> <parent> <instant> <id> <task> <size> <Files> [<id> <task> <size> <Files>…]
#   -> the whole plan with <parent> split into the children, on stdout; the file is not written.
#   Exit 1 no table or no `## SDLC State` · 2 no row <parent> · 3 the parent is not `pending` ·
#   4 fewer than two children, a short spec, or a value no cell can hold · 5 more than one row
#   <parent>. Silent on every refusal; `units_split_check` is the caller's, before this.
#
# THE EXISTING PROJECTORS, IN ORDER, ON ONE COPY: (1) every deps cell naming the parent has that
# token replaced by each child the cell does not already name (`units_table_cells`) — a row that
# waited on the whole of the parent still does; (2) the parent's status `dropped` and its task
# ` · split-into: <ids>`; (3) each child by `units_add_row`, carrying the parent's step, kind,
# deps, serves and reads, its own task, size and Files, and the parent's agent with the parent's
# id at its end renamed to the child's (`w30-T17` -> `w30-T33`; any other agent kept); (4) each
# child's line `- <id>: pending dispatch — split from <parent> at <instant>` and the parent's
# `- <parent>: split into <ids> at <instant>` (`units_step_line`). The deps are re-pointed BEFORE
# the children are added, so `units_add_row`'s threading (a table without reads) finds the frontier
# already reaching each child and threads nothing twice. A reader in a reads table needs no edit:
# it names the path, and the child whose Files hold that path is now its writer.
units_split_row() {
  local plan="${1:-}" pid="${2:-}" now="${3:-}" wd cur nxt rec n i ids="" cid
  local step kind task agent deps serves reads pre cagent rid rdeps nd seen lst t c rc=0
  [ -n "$plan" ] && [ -f "$plan" ] && [ -n "$pid" ] || return 1
  shift 3 2>/dev/null || return 4
  [ $# -ge 8 ] && [ $(( $# % 4 )) -eq 0 ] || return 4
  _units_table "$plan" >/dev/null 2>&1 || return 1
  rec="$(units_rows "$plan" | awk -F'\t' -v p="$pid" '$1 == p')"
  n="$(printf '%s' "$rec" | grep -c .)"
  [ "$n" -ge 1 ] || return 2
  [ "$n" -eq 1 ] || return 5
  [ "$(units_field "$rec" status)" = pending ] || return 3
  step="$(units_field "$rec" step)"; kind="$(units_field "$rec" kind)"; task="$(units_field "$rec" task)"
  agent="$(units_field "$rec" agent)"; deps="$(units_field "$rec" deps)"; serves="$(units_field "$rec" serves)"
  reads="$(units_field "$rec" reads)"
  i=1
  for c in "$@"; do
    [ $(( i % 4 )) -eq 1 ] && ids="${ids:+$ids, }$c"
    i=$((i + 1))
  done
  wd="$(mktemp -d "${TMPDIR:-/tmp}/units-split.XXXXXX")" || return 1
  cur="$wd/plan"; nxt="$wd/next"
  cp "$plan" "$cur" || { rm -rf "$wd"; return 1; }
  # (1) the deps cells that name the parent; `seen` keeps the cell free of a repeated token
  while IFS="$(printf '\037')" read -r rid rdeps; do
    [ -n "$rid" ] && [ "$rid" != "$pid" ] || continue
    nd=""; seen=","; c=0
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      if [ "$t" = "$pid" ]; then c=1; lst="$(printf '%s' "$ids" | tr -d ',')"; else lst="$t"; fi
      for t in $lst; do
        case "$seen" in *",$t,"*) continue ;; esac
        seen="$seen$t,"; nd="${nd:+$nd, }$t"
      done
    done <<EOF
$(printf '%s\n' "$rdeps" | tr ',' '\n' | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }')
EOF
    [ "$c" -eq 1 ] || continue
    units_table_cells "$cur" set tasks "$rid" "deps=$nd" > "$nxt" || { rc=$?; break; }
    mv "$nxt" "$cur"
  done <<EOF
$(units_rows "$plan" | awk -F'\t' '{ print $1 "\037" $6 }')
EOF
  # (2) the parent
  if [ "$rc" -eq 0 ]; then
    if units_table_cells "$cur" set tasks "$pid" status=dropped "task=$task · split-into: $ids" > "$nxt"; then
      mv "$nxt" "$cur"
    else rc=$?; fi
  fi
  # (3) the children, (4) their lines
  while [ "$rc" -eq 0 ] && [ $# -ge 4 ]; do
    cid="$1"
    pre="${agent%"$pid"}"; cagent="$agent"
    if [ "$pre" != "$agent" ]; then
      case "$pre" in ''|*[!A-Za-z0-9]) cagent="$pre$cid" ;; esac
    fi
    if units_add_row "$cur" "$cid" "$step" "$kind" "$2" "$cagent" "$deps" "$3" "$serves" "$4" "$reads" > "$nxt" \
       && [ -s "$nxt" ] && mv "$nxt" "$cur" \
       && units_step_line "$cur" "$cid" "pending dispatch — split from $pid at $now" > "$nxt" && mv "$nxt" "$cur"; then
      shift 4
    else rc=4; fi
  done
  if [ "$rc" -eq 0 ]; then
    units_step_line "$cur" "$pid" "split into $ids at $now" > "$nxt" && mv "$nxt" "$cur" || rc=4
  fi
  [ "$rc" -eq 0 ] && cat "$cur"
  rm -rf "$wd"
  case "$rc" in 0) return 0 ;; 1) return 1 ;; 2|5) return 5 ;; *) return 4 ;; esac
}

# units_set_current <plan> <value> -> the whole plan with the first `current:` line of
#   `## SDLC State` reading `current: <value>`. Exit 1 when the section or the line is absent.
#   Which values are legal is the caller's (the poker refuses 9, close-out's alone); this only
#   moves the line, which is all a hand edit of it ever did.
units_set_current() {
  local plan="${1:-}" v="${2:-}"
  [ -n "$plan" ] && [ -f "$plan" ] && [ -n "$v" ] || return 1
  case "$v" in *[!A-Za-z0-9]*) return 4 ;; esac
  UC_V="$v" awk '
    BEGIN { v = ENVIRON["UC_V"] }
    /^[ \t]*```/ { fence = !fence; print; next }
    fence { print; next }
    /^##[ \t]/ { insdlc = ($0 ~ /^##[ \t]+SDLC State([ \t].*)?$/) && !seen; if (insdlc) seen = 1; print; next }
    insdlc && !done && /^current[ \t]*:/ { print "current: " v; done = 1; next }
    { print }
    END { if (!done) exit 1 }' "$plan"
}

# units_step_fields [--replace] <plan> <N> <key=value>… -> the whole plan with each named field written as
#   an indented `  key: value` line under `- Step N:` — after the block's last line — when the
#   block does not carry that key already. WITHOUT THE FLAG a key the block has is left as written: this
#   fills what is missing and never rewrites what is there (`current 4` fills the Step-4 block so).
#   `--replace` (wave-28 T8; REQ-3 AC-3.5, D17) is the mode `session-poker.sh step-field` writes through: a
#   key the block has is REPLACED where it stands, its place kept, and a second line of the same key in the
#   block goes (the gate reads the first, so a stale second could only mislead); a key the block lacks is
#   written after the block's last line as above. The rest of the plan is the same bytes.
#   Exit 1 no `Step N:` line in `## SDLC State` · 3 an operand with no `=` · 4 a value with a line break ·
#   5 (`--replace` only) a key the step line itself carries: the gate reads that text before any indented
#   line, so a line written beside it could not win, and rewriting the step line is `step-line`'s.
#
# THE BLOCK IS THE GATE'S: the indented lines under the step line, up to the next line that is
# not indented (walls.sh `extract_continuation`), blank lines skipped; a key is present when a
# line of it starts `key:` (walls.sh `block_has`).
units_step_fields() {
  local mode=fill plan n pairs="" kv
  if [ "${1:-}" = --replace ]; then mode=replace; shift; fi
  plan="${1:-}"; n="${2:-}"
  [ -n "$plan" ] && [ -f "$plan" ] && [ -n "$n" ] || return 1
  shift 2
  for kv in "$@"; do
    case "$kv" in *=*) : ;; *) return 3 ;; esac
    case "$kv" in *$'\n'*|*$'\r'*) return 4 ;; esac
    pairs="${pairs}${kv%%=*}"$'\t'"${kv#*=}"$'\n'
  done
  UF_N="$n" UF_PAIRS="$pairs" UF_MODE="$mode" awk '
    BEGIN {
      pat = "^[ \t]*-?[ \t]*Step[ \t]+" ENVIRON["UF_N"] "[ \t]*:"
      replace = (ENVIRON["UF_MODE"] == "replace")
      np = split(ENVIRON["UF_PAIRS"], pl, "\n")
      for (p = 1; p <= np; p++) {
        if (pl[p] == "") continue
        t = index(pl[p], "\t"); nk++
        key[nk] = substr(pl[p], 1, t - 1); val[nk] = substr(pl[p], t + 1)
      }
    }
    { L[++nl] = $0 }
    END {
      for (i = 1; i <= nl; i++) {
        line = L[i]
        if (line ~ /^[ \t]*```/) { fence = !fence; continue }
        if (fence) continue
        if (line ~ /^##[ \t]/) {
          if (sdlc == 1) sdlc = 2
          if (!seen && line ~ /^##[ \t]+SDLC State([ \t].*)?$/) { sdlc = 1; seen = 1 }
          continue
        }
        if (sdlc != 1) continue
        if (!at) {
          if (match(line, pat)) {
            at = i; endb = i; inb = 1
            rest = substr(line, RLENGTH + 1); sub(/^[ \t]+/, "", rest)
            for (p = 1; p <= nk; p++) if (rest ~ ("^" key[p] "[ \t]*:")) { has[p] = 1; onstep[p] = 1 }
          }
          continue
        }
        if (!inb) continue
        if (line ~ /^[ \t]*$/) continue
        if (line ~ /^[^ \t]/ || line ~ /^[ \t]*-?[ \t]*Step[ \t]+[0-9]+[ab]?[ \t]*:/) { inb = 0; continue }
        endb = i
        for (p = 1; p <= nk; p++) if (index(line, key[p]) && line ~ ("^[ \t]*" key[p] "[ \t]*:")) {
          if (has[p] && !onstep[p]) drop[i] = 1
          else if (!has[p]) hit[p] = i
          has[p] = 1
        }
      }
      if (!at) exit 1
      if (replace) for (p = 1; p <= nk; p++) if (onstep[p]) exit 5
      for (p = 1; p <= nk; p++) if (hit[p]) at_line[hit[p]] = p
      for (i = 1; i <= nl; i++) {
        if (replace && (i in at_line)) print "  " key[at_line[i]] ": " val[at_line[i]]
        else if (!(replace && drop[i])) print L[i]
        if (i == endb) for (p = 1; p <= nk; p++) if (!has[p]) print "  " key[p] ": " val[p]
      }
    }' "$plan"
}

# units_chain <writer ceiling> — the longest chain of dependent work and the widest the plan can
# run (wave-26 T3, REQ-7). Pure over stdin; it reads no plan, so the card hands it the nodes and
# the edges it already holds:
#
#   N<TAB><id><TAB><minutes>     a unit of work
#   E<TAB><from><TAB><to>        `to` cannot start before `from` ends
#
# Prints `chain<TAB><id>,<id>…<TAB><minutes>` — the path with the largest sum of minutes, every
# node on it counted, a tie going to the path whose ids come first in input order — and
# `width<TAB><n>`: every node scheduled at its earliest start (the latest end among the nodes it
# waits for, 0 with none), at most <writer ceiling> running at once, ready nodes taken in input
# order when more are ready than there is room; the width is the largest number running at one
# instant. A cycle, an edge naming an unknown id or a minutes value that is not a whole number
# prints one line on stderr and returns 2 with nothing on stdout.
units_chain() {
  awk -F'\t' -v ceil="${1-}" '
    function die(msg) { print "units_chain: " msg > "/dev/stderr"; bad = 1; exit 2 }
    BEGIN {
      if (ceil !~ /^[0-9]+$/ || ceil + 0 < 1) die("writer ceiling is not a whole number of at least 1: \"" ceil "\"")
    }
    { sub(/\r$/, "") }
    $0 ~ /^[ \t]*$/ { next }
    $1 == "N" {
      if (NF != 3 || $2 == "") die("malformed node line: " $0)
      if ($3 !~ /^[0-9]+$/) die("minutes of " $2 " is not a whole number: \"" $3 "\"")
      if ($2 in at) die("node " $2 " is declared twice")
      n++; id[n] = $2; at[$2] = n; mins[n] = $3 + 0
      next
    }
    $1 == "E" {
      if (NF != 3) die("malformed edge line: " $0)
      ne++; ef[ne] = $2; et[ne] = $3
      next
    }
    { die("unknown line kind \"" $1 "\": " $0) }
    END {
      if (bad) exit 2
      for (k = 1; k <= ne; k++) {
        if (!(ef[k] in at)) die("edge " ef[k] " -> " et[k] " names unknown id " ef[k])
        if (!(et[k] in at)) die("edge " ef[k] " -> " et[k] " names unknown id " et[k])
        a = at[ef[k]]; b = at[et[k]]
        out[a] = out[a] " " b; indeg[b]++
      }
      # Kahn: a topological order, or the nodes a cycle keeps from one.
      for (i = 1; i <= n; i++) { rem[i] = indeg[i] + 0; if (rem[i] == 0) q[++qt] = i }
      for (qh = 1; qh <= qt; qh++) {
        m = split(out[q[qh]], s, " ")
        for (j = 1; j <= m; j++) if (--rem[s[j]] == 0) q[++qt] = s[j]
      }
      if (qt < n) {
        for (i = 1; i <= n; i++) if (rem[i] > 0) members = members (members == "" ? "" : " ") id[i]
        die("cycle among: " members)
      }
      # Longest chain: f[i] is the heaviest path that starts at i; the best successor is the
      # heaviest, the lowest input position on a tie, which makes the whole path the one whose
      # ids come first. Sources only start a chain.
      for (qh = n; qh >= 1; qh--) {
        i = q[qh]; best = 0; nx[i] = 0
        m = split(out[i], s, " ")
        for (j = 1; j <= m; j++) {
          c = s[j]
          if (nx[i] == 0 || f[c] > best || (f[c] == best && c < nx[i])) { best = f[c]; nx[i] = c }
        }
        f[i] = mins[i] + best
      }
      start = 0
      for (i = 1; i <= n; i++) if (indeg[i] + 0 == 0 && (start == 0 || f[i] > f[start])) start = i
      path = ""
      for (i = start; i != 0; i = nx[i]) path = path (path == "" ? "" : ",") id[i]
      # Width: an earliest-start schedule under the ceiling. Waiting is the count of a node'"'"'s
      # unfinished predecessor edges; time moves to the next end once nothing more can start.
      for (i = 1; i <= n; i++) wait[i] = indeg[i] + 0
      t = 0; done = 0; run = 0; peak = 0
      while (done < n) {
        do {
          moved = 0
          for (i = 1; i <= n; i++) if (running[i] && fin[i] <= t) {
            running[i] = 0; run--; done++; moved = 1
            m = split(out[i], s, " ")
            for (j = 1; j <= m; j++) wait[s[j]]--
          }
          for (i = 1; i <= n && run < ceil; i++) if (!began[i] && wait[i] == 0) {
            began[i] = 1; running[i] = 1; run++; fin[i] = t + mins[i]; moved = 1
          }
        } while (moved)
        if (run > peak) peak = run
        nextt = -1
        for (i = 1; i <= n; i++) if (running[i] && (nextt < 0 || fin[i] < nextt)) nextt = fin[i]
        if (nextt < 0) break
        t = nextt
      }
      printf "chain\t%s\t%d\nwidth\t%d\n", path, f[start], peak
    }'
}
