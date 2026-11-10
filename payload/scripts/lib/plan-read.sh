#!/bin/bash
# payload/scripts/lib/plan-read.sh — THE ONE PARSER OF A PLAN'S AUTHORED PARTS.
#
#   plan_read_header <plan> [key]                    -> `key=value` per header key, or the one named
#   plan_read_row <plan> <heading> <column> <value>  -> `name=value` per cell of the row whose <column> is <value>
#
# A plan is the words a person wrote: its header and its tables. Everything that is the run's state is
# the log's, read by lib/reader.sh, so nothing here reads a state cell for an answer or follows a header
# key to another file.
#
# THE HEADER is the leading `---` block alone: a `---` or a `key: value` line in the body is prose.
# A key's first line answers; one leading and one trailing quote are dropped from its value, as every
# frontmatter reader in the tree drops them.
#
# A TABLE is the first one under its `## <heading>`, ending at the first line that is not a row. Cells
# are named by the table's own header line and never counted by place, so a plan whose Tasks table
# carries the machine's columns and one that carries only the authored cells read the same: the
# shapes differ in which columns there are and where, never in what a named cell holds. A cell's
# name is printed lowercased with each run of spaces as one `-` (`Fails when` is `fails-when`), so
# every answer is a `key=value` line. An escaped `\|` inside a cell is a `|` in its value.
#
# Both exit 0 with an answer, 1 when there is none, 2 when the plan is not a file.
#
# bash 3.2 (ADR-001).

plan_read_header() {  # <plan> [key] -> `key=value` lines in the header's order; 1 none, 2 no plan
  [ -f "${1:-}" ] || return 2
  awk -v want="${2:-}" '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    {
      e = index($0, ":"); if (e < 2) next
      k = substr($0, 1, e - 1); v = substr($0, e + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", k); gsub(/^[ \t]+|[ \t]+$/, "", v)
      if (k ~ /[ \t]/ || (k in seen) || (want != "" && k != want)) next
      sub(/^["\047]/, "", v); sub(/["\047]$/, "", v)
      seen[k] = 1; n++; print k "=" v
      if (want != "") exit
    }
    END { exit !n }' "$1"
}

plan_read_row() {  # <plan> <heading> <column> <value> -> `name=value` per cell, the header's order; 1 none, 2 no plan
  [ -f "${1:-}" ] || return 2
  awk -v sec="${2:-}" -v col="${3:-}" -v want="${4:-}" '
    function cells(line, out,   n, i) {
      gsub(/\\[|]/, "\001", line); sub(/^[ \t]*[|]/, "", line); sub(/[|][ \t]*$/, "", line)
      n = split(line, out, "|")
      for (i = 1; i <= n; i++) { gsub(/^[ \t]+|[ \t]+$/, "", out[i]); gsub(/\001/, "|", out[i]) }
      return n
    }
    { sub(/\r$/, "") }
    /^## / { if (on) exit; h = substr($0, 4); sub(/[ \t]+$/, "", h); on = (h == sec); next }
    !on { next }
    !/^[ \t]*[|]/ { if (nh) exit; next }
    !nh { nh = cells($0, head); for (i = 1; i <= nh; i++) if (head[i] == col) c = i; if (!c) exit; next }
    /^[ \t]*[|][-:| \t]+$/ { next }
    {
      cells($0, r); if (r[c] != want) next
      for (i = 1; i <= nh; i++) { k = tolower(head[i]); gsub(/[ \t]+/, "-", k); print k "=" r[i] }
      found = 1; exit
    }
    END { exit !found }' "$1"
}
