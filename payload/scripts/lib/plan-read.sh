#!/bin/bash
# payload/scripts/lib/plan-read.sh — THE ONE PARSER OF A PLAN'S AUTHORED PARTS.
#
#   plan_read_header <plan> [key]                    -> `key=value` per header key, or the one named
#   plan_read_row <plan> <heading> <column> <value>  -> `name=value` per cell of the row whose <column> is <value>
#
#   plan_read_table <plan> <heading> [key]           -> the header's names, then each row, then each row too wide
#   plan_read_dropped <plan>                         -> the id of each Tasks row whose status cell is dropped
#
# A plan is the words a person wrote: its header and its tables. Everything that is the run's state is
# the log's, read by lib/reader.sh, so nothing here reads a state cell for an answer or follows a header
# key to another file, but one: an older table's `dropped` status, which no event carries, so that cell
# is the only word that a row's work is no longer owed.
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
# WHERE A TABLE IS, five rules, because a table read in the wrong place is a schedule nobody wrote:
#   - a fenced block is prose: a table or a heading inside ``` is an example about the plan, not of it;
#   - the heading is `## ` and the name, its first letter in either case, and may go on after a blank
#     (`## Tasks (amended)`); the first such heading is the section, and any heading ends it;
#   - the header line is the first table line in the section that names the key column (`id` for a
#     Tasks table, the looked-up column for a row), so a note table above it is not the header;
#   - a row whose key cell is empty or only dashes and colons is no row (the separator is one);
#   - a carriage return ends a line wherever it stands, so a file saved with CR alone still has lines.
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

# _plan_read_lines <file> -> its lines, a carriage return ending a line wherever it stands. A file saved
# with CR alone is one awk record, which no later pass can split again, so this pass comes first.
_plan_read_lines() { awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$1"; }

# The walk the table readers share, over `_plan_read_lines`: `cells` splits a row and returns how many
# cells it holds, the header line's names fill head[1..nh], `name(i)` prints column i's and `line()` a
# row's cells as `name=value` joined by tabs (a tab inside a cell read as a space). The key column is
# `key`, matched in either case, at kc. The reader's own `start()` runs at the header line and `row()`
# on each row after it, its cells in r[1..rn]. NO APOSTROPHE inside it: it is single-quoted.
_PLAN_READ_TABLE='
    function cells(line, out,   n, i) {
      gsub(/\\[|]/, "\001", line); sub(/^[ \t]*[|]/, "", line); sub(/[|][ \t]*$/, "", line)
      n = split(line, out, "|")
      for (i = 1; i <= n; i++) { gsub(/^[ \t]+|[ \t]+$/, "", out[i]); gsub(/\001/, "|", out[i]) }
      return n
    }
    function name(i,   k) { k = tolower(head[i]); gsub(/[ \t]+/, "-", k); return k }
    function line(   i, o, v) { o = ""; for (i = 1; i <= nh; i++) { v = r[i]; gsub(/\t/, " ", v); o = o (i > 1 ? "\t" : "") name(i) "=" v }; return o }
    function cap(s) { return tolower(substr(s, 1, 1)) substr(s, 2) }
    function named(h,   l) { l = length(sec); return (cap(substr(h, 1, l)) == cap(sec) && (length(h) == l || substr(h, l + 1, 1) ~ /[ \t]/)) }
    { sub(/\r$/, "") }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^[ \t]*#/ { if (on) exit; if ($0 ~ /^##[ \t]/) { h = $0; sub(/^##[ \t]+/, "", h); sub(/[ \t]+$/, "", h); on = named(h) }; next }
    !on { next }
    !/^[ \t]*[|]/ { if (nh) exit; next }
    !nh { nh = cells($0, head); kc = 0; for (k = 1; k <= nh && !kc; k++) if (tolower(head[k]) == tolower(key)) kc = k
      if (!kc) { nh = 0; next }
      start(); next }
    { rn = cells($0, r); if (r[kc] == "" || r[kc] ~ /^[-: ]+$/) next; row() }
    END { exit !found }'

plan_read_row() {  # <plan> <heading> <column> <value> -> `name=value` per cell, the header's order; 1 none, 2 no plan
  [ -f "${1:-}" ] || return 2
  _plan_read_lines "$1" | awk -v sec="${2:-}" -v key="${3:-}" -v want="${4:-}" '
    function start() { }
    function row(   i) {
      if (r[kc] != want) return
      for (i = 1; i <= nh; i++) print name(i) "=" r[i]
      found = 1; exit
    }'"$_PLAN_READ_TABLE"
}

plan_read_rows() {  # <plan> <heading> [key] -> one line per row in table order, its cells `name=value` joined by tabs; 1 none, 2 no plan
  [ -f "${1:-}" ] || return 2
  _plan_read_lines "$1" | awk -v sec="${2:-}" -v key="${3:-id}" '
    function start() { }
    function row() { print line(); found = 1 }'"$_PLAN_READ_TABLE"
}

# plan_read_table <plan> <heading> [key] -> what a reader that judges the table itself needs: `#<TAB>head`
# and the header's names, tab-joined, first; then each row as plan_read_rows prints it; a row holding more
# cells than the header is followed by `#<TAB>over<TAB><key cell><TAB><its cell count>`, the mark of a raw
# `|` inside a cell, which shifts every cell after it. A table with a header and no rows answers 0.
plan_read_table() {
  [ -f "${1:-}" ] || return 2
  _plan_read_lines "$1" | awk -v sec="${2:-}" -v key="${3:-id}" '
    function start(   i, o) { o = "#\thead"; for (i = 1; i <= nh; i++) o = o "\t" name(i); print o; found = 1 }
    function row() { print line(); if (rn > nh) printf "#\tover\t%s\t%d\n", r[kc], rn }'"$_PLAN_READ_TABLE"
}

plan_read_dropped() {  # <plan> -> one id per line, in table order; 1 none, 2 no plan
  plan_read_rows "$1" Tasks | awk -F'\t' '{ split("", c); for (i = 1; i <= NF; i++) c[substr($i, 1, index($i, "=") - 1)] = substr($i, index($i, "=") + 1)
    if (c["status"] == "dropped") { print c["id"]; n++ } } END { exit !n }'
}

# plan_read_waits <plan> [id] -> per row, in table order: `<id><TAB>kind<TAB><kind>` first, then one line per
# wait, `<id><TAB>wait<TAB><token>` for one that names no row (an approval, a proof, a step, an external
# token), whose standing is the log's, and `<id><TAB>row<TAB><row id><TAB><reads>` for each row it waits on,
# <reads> the reads that name that row, comma-joined, as the row wrote them. Of <id> alone when given: 1
# when the table lacks it or there is no table, 2 when the plan is not a file.
#
# THE TOKENS ARE THE FILL'S (lib/units.sh, its scheduler): the reads cell, or the kind's default when the
# cell is empty, then the deps cell. A table with no reads cell is the nine-cell shape, whose row waits
# on its deps and on what its kind and step imply and on nothing else, so it always takes the kind's
# default. The kind default and the Files matcher are units.sh's own awk, sourced, never restated here.
# WHICH ROWS A READ NAMES IS DECIDED HERE ALONE, and the scheduler takes its writers from these lines: a
# row id is that row, itself included, so a row that waits on itself waits for ever; a path is each other
# row whose Files write it, so a row's artifact is that row; `head` is each other row writing the tracked
# tree that does not read head itself or stands at an earlier step, `record` the same over the record;
# `merge` each integrate row; `proof:<kind>` each row of the kind that writes one, and the proof itself.
# `live:` is read as what it prefixes, and a row reading `live:head` does not read the settled head, so it
# still writes it for the rows that do. An integrate or close row also waits for the run to reach its step
# (`step:<n>`). A path's writers are found once per path, from each row's Files entries split once.
plan_read_waits() {
  [ -f "${1:-}" ] || return 2
  local rows d
  rows="$(plan_read_rows "$1" Tasks)" || return 1
  if ! declare -F _units_cell_awk >/dev/null 2>&1; then
    d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
    # shellcheck source=/dev/null
    . "$d/units.sh" || return 2
  fi
  printf '%s\n' "$rows" | awk -F'\t' -v want="${2:-}" -v regno="$(_units_regno "$1")" "$(_units_files_awk)$(_units_cell_awk)"'
    function put(i, t,   j) { if (!((i, t) in said)) { said[i, t] = 1; printf "%s\t%s\n", id[i], t } }
    # row(j, o): row i waits on row j by its read o; a row named by two reads is one line naming both.
    function row(j, o) {
      if (!(j in rs)) { rr[++nr] = j; rs[j] = o }
      else if (index("," rs[j] ",", "," o ",") == 0) rs[j] = rs[j] "," o
    }
    # writers(t): the rows whose Files write the path t, space-joined, found once per path.
    function writers(t,   j, k, s) {
      if (t in pw) return pw[t]
      s = ""
      for (j = 1; j <= n; j++) for (k = 1; k <= nfe[j]; k++) if (overlap(fe[j, k], t)) { s = s " " j; break }
      pw[t] = s
      return s
    }
    {
      split("", c)
      for (k = 1; k <= NF; k++) { e = index($k, "="); if (!(substr($k, 1, e - 1) in c)) c[substr($k, 1, e - 1)] = substr($k, e + 1) }
      if ("reads" in c) hasreads = 1
      n++; id[n] = c["id"]; stp[n] = c["step"]; knd[n] = c["kind"]; fil[n] = c["files"]; rd[n] = c["reads"]; dep[n] = c["deps"]
      at[id[n]] = n
    }
    END {
      if (want != "" && !(want in at)) exit 1
      for (i = 1; i <= n; i++) if (knd[i] == "doc" && stp[i] ~ /^[0-9]+$/ && stp[i] + 0 >= 7) hasrel = 1
      for (i = 1; i <= n; i++) {
        code[i] = writes_head(fil[i]); m = split(fil[i], a, ",")
        for (k = 1; k <= m; k++) {
          e = a[k]; gsub(/`/, "", e); gsub(/^[ \t]+|[ \t]+$/, "", e); sub(/^\.\//, "", e)
          if (e == "" || e !~ /[\/.*?]/ || e ~ /[ \t]/) continue
          sub(/!$/, "", e); nfe[i]++; fe[i, nfe[i]] = e; if (in_docs(e)) docs[i] = 1
        }
        r = rd[i]; if (r !~ /[A-Za-z0-9]/) r = kdef(knd[i], stp[i])
        if (hasrel && knd[i] == "integrate" && (" " r ",") !~ /[ \t,]approval:release[ \t]*,/) r = r ", approval:release"
        m = split(r "," dep[i], a, ",")
        for (k = 1; k <= m; k++) {
          t = a[k]; gsub(/^[ \t]+|[ \t]+$/, "", t)
          '"$_UNITS_READS_NORM"'
          o = t; sub(/^live:/, "", t); sub(/^head:.*/, "head", t)
          if (t !~ /[A-Za-z0-9]/) continue
          nt[i]++; tk[i, nt[i]] = t; rk[i, nt[i]] = o; if (o == "head") rhead[i] = 1; if (o == "record") rrec[i] = 1
        }
      }
      for (i = 1; i <= n; i++) {
        if (want != "" && id[i] != want) continue
        printf "%s\tkind\t%s\n", id[i], knd[i]
        if ((knd[i] == "integrate" || knd[i] == "close" || (!hasreads && knd[i] == "doc" && stp[i] + 0 >= 7)) && stp[i] ~ /^[0-9]+$/) put(i, "wait\tstep:" stp[i])
        nr = 0; split("", rs)
        for (k = 1; k <= nt[i]; k++) {
          t = tk[i, k]; o = rk[i, k]; p = substr(t, 7)
          if (t in at) { row(at[t], o); continue }
          if (t == "head" || t == "record") {
            for (j = 1; j <= n; j++) if (j != i && (t == "head" ? code[j] : docs[j]) && (!(t == "head" ? rhead[j] : rrec[j]) || stp[j] + 0 < stp[i] + 0)) row(j, o)
          } else if (t == "merge") {
            for (j = 1; j <= n; j++) if (j != i && knd[j] == "integrate") row(j, o)
          } else if (t ~ /^proof:/) {
            for (j = 1; j <= n; j++) if (j != i && (p == "regression" && (knd[j] == "verify" || knd[j] == "test") || p == "review" && knd[j] == "review")) row(j, o)
          } else if (t !~ /[ \t:!]/ && t ~ /[\/.*?]/) {
            m = split(writers(t), w, " "); for (x = 1; x <= m; x++) if (w[x] != i) row(w[x], o)
          }
          if (t !~ /^(head|record|merge)$/ && (t ~ /[ \t:!]/ || t !~ /[\/.*?]/)) put(i, "wait\t" t)
        }
        for (x = 1; x <= nr; x++) printf "%s\trow\t%s\t%s\n", id[i], id[rr[x]], rs[rr[x]]
      }
    }'
}

# plan_read_section <plan> <id> [key] -> the task's own section: the lines under the first heading whose first word
# is <id>, a trailing `:`, `.` or `,` dropped, to the next heading, with its leading and trailing blank lines left
# out. With <key>: the value of the section's first `<key>: <value>` line. 1 when there is no such section or key,
# 2 when the plan is not a file. THE RULE IS ONE STRING, so every reader and every writer of a task's section finds
# the same heading: the act that writes a row's suites into its section takes `heading()` from here.
_PLAN_READ_SECTION='function heading(s) { sub(/^#+[ \t]+/, "", s); sub(/[ \t].*$/, "", s); sub(/[:.,]+$/, "", s); return s }'
plan_read_section() {
  [ -f "${1:-}" ] || return 2
  [ -n "${2:-}" ] || return 1
  awk -v id="$2" -v key="${3:-}" "$_PLAN_READ_SECTION"'
    { sub(/\r$/, "") }
    /^#+[ \t]/ { if (on) exit; if (heading($0) == id) on = found = 1; next }
    !on { next }
    key != "" { if (index($0, key ":") == 1) { v = substr($0, length(key) + 2); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; got = 1; exit }; next }
    /^[ \t]*$/ { if (n) blank++; next }
    { for (; blank > 0; blank--) print ""; print; n++ }
    END { exit !(key == "" ? found : got) }' "$1"
}
