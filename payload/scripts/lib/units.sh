#!/bin/bash
# payload/scripts/lib/units.sh — THE ONE READER OF THE PLAN'S `## Tasks` TABLE.
#
# WHAT IT OWNS (epic-23 wave-11-lean-spine, REQ-1e; spec Design §1 "Task", §2 D3/D7, §3
# ownership row "Tasks schema"). The schedule every wave runs on — one row per unit of work
# at Steps 3–9 — and the three questions asked of it. Pure functions of a file; nothing here
# writes, and nothing here runs at source time:
#
#   units_rows <plan>          one TSV line per row, the ten fields in the FIXED order
#                              id·step·kind·task·agent·deps·size·serves·Files·status,
#                              in TABLE order. Exit 1 and silent when the plan carries no
#                              `## Tasks` table.
#   units_ready <plan> <step>  the ids of rows whose status is `pending`, whose step is
#                              <step>, and whose every dependency has landed. One per line,
#                              table order. Exit 2 on a step that is not a number.
#   units_validate <plan>      one line per broken invariant, each naming the offending id
#                              and the rule. Exit 1 if any line was printed, else 0.
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
# SOURCED, NEVER EXECUTED. Only function definitions run at source time; nothing prints.
# Every caller reads a verb through `$( )`, and a library that greeted them would corrupt
# the first field of every answer.
#
# BASH 3.2 (macOS /bin/bash). No associative arrays, no `${var^^}`, no `mapfile`, and the
# awk programs stay inside POSIX awk — no `gensub`, no `length(array)`, no sorting built-in.
#
# A CELL NEVER CONTAINS A LITERAL `|` (the brief rule for this table), so there is no
# escaping to undo and `split($0, c, "|")` is exact.
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
    function trim(v) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); return v }

    BEGIN {
      # The contract order. `disp` is the spelling a violation names; `want` is the
      # lower-cased text a header cell is matched against.
      disp[1] = "id";    disp[2] = "step";   disp[3] = "kind";   disp[4] = "task"
      disp[5] = "agent"; disp[6] = "deps";   disp[7] = "size";   disp[8] = "serves"
      disp[9] = "Files"; disp[10] = "status"
      for (k = 1; k <= 10; k++) want[k] = tolower(disp[k])
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
      n = split($0, c, "|")
      for (i = 1; i <= n; i++) {
        t = tolower(trim(c[i]))
        if (t == "") continue
        for (k = 1; k <= 10; k++) if ((t == want[k] || t == alt[k]) && col[k] == 0) col[k] = i
      }
      if (col[1] == 0) next          # no `id` cell — not the header row
      found = 1
      state = 2
      next
    }

    # The rows. The table ends at the first line that is not a table row.
    state == 2 {
      if ($0 !~ /^[ \t]*\|/) { state = 3; next }
      n = split($0, c, "|")
      id = trim(c[col[1]])
      # The |---|---| separator, and any row whose id cell is empty or punctuation.
      if (id == "" || id ~ /^[-: ]+$/) next
      line = ""
      for (k = 1; k <= 10; k++) {
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
      for (k = 1; k <= 10; k++) if (col[k] == 0) missing = (missing == "") ? disp[k] : missing " " disp[k]
      printf "# %s\n", missing
      for (i = 1; i <= nr; i++) print row[i]
    }
  '
}

# ── THE THREE VERBS, AND THE ONE ACCESSOR ────────────────────────────────────

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
# `10` would have to be found again if the contract ever grew an eleventh field. The name
# is this library's own contract spelling, NOT the table's header text — `rigor` is
# accepted as the second name of slot 3, the same alias the header scan takes.
units_field() {  # <record> <column name> -> the cell, empty if absent; rc 1 on a bad name
  local rec="${1:-}" n
  case "${2:-}" in
    id) n=1 ;;    step) n=2 ;;   kind|rigor) n=3 ;; task) n=4 ;;  agent) n=5 ;;
    deps) n=6 ;;  size) n=7 ;;   serves) n=8 ;;     Files) n=9 ;;  status) n=10 ;;
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


# units_rows <plan> -> id·step·kind·task·agent·deps·size·serves·Files·status, tab-separated,
#                      one line per row, in TABLE order. Exit 1 when there is no table.
#
# TABLE ORDER, NOT ID ORDER, and never sorted: the sequence is the orchestrator's own
# dependency ordering, and a reader that re-sorted would answer the dispatch question in an
# order nobody chose.
units_rows() {
  local out rc
  out="$(_units_read "${1:-}")"; rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  printf '%s\n' "$out" | awk 'NR > 1'
}

# units_ready <plan> <step> -> the ids that may be dispatched now, one per line, table order.
#
# READY = status `pending`, step equal to <step>, and EVERY dependency `landed`.
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
  local plan="${1:-}" step="${2:-}" rows
  case "$step" in ''|*[!0-9]*) return 2 ;; esac
  rows="$(units_rows "$plan")" || return 1
  [ -n "$rows" ] || return 0
  printf '%s\n' "$rows" | awk -F'\t' -v want="$step" '
    $1 == "" { next }
    { n++; id[n] = $1; stp[n] = $2; dep[n] = $6; st[$1] = $10 }
    END {
      for (i = 1; i <= n; i++) {
        if (st[id[i]] != "pending") continue
        if (stp[i] + 0 != want + 0) continue
        d = dep[i]
        gsub(/[ \t]/, "", d)
        if (d !~ /[A-Za-z0-9]/) { print id[i]; continue }
        m = split(d, a, ",")
        ready = 1
        for (j = 1; j <= m; j++) {
          if (a[j] == "" || a[j] !~ /[A-Za-z0-9]/) continue
          if (st[a[j]] != "landed") { ready = 0; break }
        }
        if (ready) print id[i]
      }
    }'
}

# units_validate <plan> -> one line per broken invariant; exit 1 if any, else 0.
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
# THE TRANSITIVE RULE reports the FIRST Step-4 row, in table order, that the row fails to
# reach. A row is a Step-4 row by its `step` cell alone: a row whose id is also malformed is
# still one, and naming it is more useful than silently exempting it.
#
# EVERY FAULT IS REPORTED, not just the first. A writer fixing one line at a time against a
# wall that stops at the first complaint pays a round trip per fault.
units_validate() {
  local plan="${1:-}" out rc missing rows violations _c found=0

  out="$(_units_read "$plan")"; rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '## Tasks: no table found in %s\n' "${plan:-<no plan>}"
    return 1
  fi

  missing="$(printf '%s\n' "$out" | awk 'NR == 1 { sub(/^# */, ""); print }')"
  if [ -n "$missing" ]; then
    for _c in $missing; do
      printf '## Tasks: missing column %s\n' "$_c"
      found=1
    done
  fi

  rows="$(printf '%s\n' "$out" | awk 'NR > 1')"
  if [ -n "$rows" ]; then
    violations="$(printf '%s\n' "$rows" | awk -F'\t' '
      BEGIN {
        split("build test verify review doc integrate close prototype", kk, " ")
        for (i in kk) kinds[kk[i]] = 1
        split("pending active landed dropped", ss, " ")
        for (i in ss) states[ss[i]] = 1
      }
      $1 == "" { next }
      { n++; id[n] = $1; stp[n] = $2; knd[n] = $3; dep[n] = $6; sta[n] = $10; count[$1]++ }
      END {
        for (i = 1; i <= n; i++) {
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

        # THE TRANSITIVE RULE. Breadth-first over the dependency edges, once per Step-5+ row.
        # `reach` is reset per row — a rule decided once for the whole
        # table is a different rule — and a cycle terminates because an id is enqueued once.
        for (i = 1; i <= n; i++) {
          if (stp[i] !~ /^[0-9]+$/ || stp[i] + 0 < 5) continue
          split("", reach)
          qn = 0
          d = dep[i]; gsub(/[ \t]/, "", d)
          m = split(d, a, ",")
          for (j = 1; j <= m; j++)
            if (a[j] != "" && a[j] ~ /[A-Za-z0-9]/ && !(a[j] in reach)) { reach[a[j]] = 1; q[++qn] = a[j] }
          h = 1
          while (h <= qn) {
            cur = q[h++]
            for (k = 1; k <= n; k++) {
              if (id[k] != cur) continue
              dd = dep[k]; gsub(/[ \t]/, "", dd)
              mm = split(dd, b, ",")
              for (j = 1; j <= mm; j++)
                if (b[j] != "" && b[j] ~ /[A-Za-z0-9]/ && !(b[j] in reach)) { reach[b[j]] = 1; q[++qn] = b[j] }
            }
          }
          for (k = 1; k <= n; k++) {
            if (stp[k] + 0 != 4) continue
            if (id[k] in reach) continue
            printf "%s: step %s does not depend transitively on step-4 row %s\n", id[i], stp[i], id[k]
            break
          }
        }
      }')"
    if [ -n "$violations" ]; then
      printf '%s\n' "$violations"
      found=1
    fi
  fi

  [ "$found" -eq 0 ]
}
