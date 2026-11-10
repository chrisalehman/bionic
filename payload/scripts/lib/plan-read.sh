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

# The walk both table readers share: `cells` splits a row, the header line's names fill head[1..nh] and
# `name(i)` prints column i's; the reader's own `start()` runs at the header line and `row()` on each row
# after it, its cells in r[]. NO APOSTROPHE inside it: it is single-quoted.
_PLAN_READ_TABLE='
    function cells(line, out,   n, i) {
      gsub(/\\[|]/, "\001", line); sub(/^[ \t]*[|]/, "", line); sub(/[|][ \t]*$/, "", line)
      n = split(line, out, "|")
      for (i = 1; i <= n; i++) { gsub(/^[ \t]+|[ \t]+$/, "", out[i]); gsub(/\001/, "|", out[i]) }
      return n
    }
    function name(i,   k) { k = tolower(head[i]); gsub(/[ \t]+/, "-", k); return k }
    { sub(/\r$/, "") }
    /^## / { if (on) exit; h = substr($0, 4); sub(/[ \t]+$/, "", h); on = (h == sec); next }
    !on { next }
    !/^[ \t]*[|]/ { if (nh) exit; next }
    !nh { nh = cells($0, head); start(); next }
    /^[ \t]*[|][-:| \t]+$/ { next }
    { cells($0, r); row() }
    END { exit !found }'

plan_read_row() {  # <plan> <heading> <column> <value> -> `name=value` per cell, the header's order; 1 none, 2 no plan
  [ -f "${1:-}" ] || return 2
  awk -v sec="${2:-}" -v col="${3:-}" -v want="${4:-}" '
    function start(   i) { for (i = 1; i <= nh; i++) if (head[i] == col) c = i; if (!c) exit }
    function row(   i) {
      if (r[c] != want) return
      for (i = 1; i <= nh; i++) print name(i) "=" r[i]
      found = 1; exit
    }'"$_PLAN_READ_TABLE" "$1"
}

plan_read_rows() {  # <plan> <heading> -> one line per row in table order, its cells `name=value` joined by tabs; 1 none, 2 no plan
  [ -f "${1:-}" ] || return 2
  awk -v sec="${2:-}" '
    function start() { }
    function row(   i, o, v) {
      o = ""
      for (i = 1; i <= nh; i++) { v = r[i]; gsub(/\t/, " ", v); o = o (i > 1 ? "\t" : "") name(i) "=" v }
      print o; found = 1
    }'"$_PLAN_READ_TABLE" "$1"
}

# plan_read_waits <plan> [id] -> per row, in table order: `<id><TAB>kind<TAB><kind>` first, then one line per
# wait, `<id><TAB>row<TAB><row id>` for a wait on another row and `<id><TAB>wait<TAB><token>` for one that
# names no row (an approval, a proof, a step, an external token), whose standing is the log's. Of <id>
# alone when given: 1 when the table lacks it or there is no table, 2 when the plan is not a file.
#
# THE TOKENS ARE THE FILL'S (lib/units.sh, its scheduler): the reads cell, or the kind's default when the
# cell is empty, then the deps cell. A table with no reads cell is the nine-cell shape, whose row waits
# on its deps and on what its kind and step imply and on nothing else, so it always takes the kind's
# default. The kind default and the Files matcher are units.sh's own awk, sourced, never restated here.
# THE ROWS ARE THE FILL'S TOO: a row id is that row; a path is each other row whose Files write it, so a
# row's artifact is that row; `head` is each other row writing the tracked tree that does not read head
# itself or stands at an earlier step, `record` the same over the record; `merge` each integrate row;
# `proof:<kind>` each row of the kind that writes one, and the proof itself. `live:` is read as what
# it prefixes. An integrate or close row also waits for the run to reach its step (`step:<n>`).
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
    function writer(j, t,   a, m, k, e) {
      m = split(fil[j], a, ",")
      for (k = 1; k <= m; k++) {
        e = a[k]; gsub(/`/, "", e); gsub(/^[ \t]+|[ \t]+$/, "", e); sub(/^\.\//, "", e); sub(/!$/, "", e)
        if (e ~ /[\/.*?]/ && e !~ /[ \t]/ && overlap(e, t)) return 1
      }
      return 0
    }
    {
      split("", c)
      for (k = 1; k <= NF; k++) { e = index($k, "="); c[substr($k, 1, e - 1)] = substr($k, e + 1) }
      if ("reads" in c) hasreads = 1
      n++; id[n] = c["id"]; stp[n] = c["step"]; knd[n] = c["kind"]; fil[n] = c["files"]; rd[n] = c["reads"]; dep[n] = c["deps"]
      at[id[n]] = n
    }
    END {
      if (want != "" && !(want in at)) exit 1
      for (i = 1; i <= n; i++) if (knd[i] == "doc" && stp[i] ~ /^[0-9]+$/ && stp[i] + 0 >= 7) hasrel = 1
      for (i = 1; i <= n; i++) {
        code[i] = writes_head(fil[i]); m = split(fil[i], a, ",")
        for (k = 1; k <= m; k++) { e = a[k]; gsub(/^[ \t]+|[ \t]+$/, "", e); if (in_docs(e)) docs[i] = 1 }
        r = rd[i]; if (r !~ /[A-Za-z0-9]/) r = kdef(knd[i], stp[i])
        if (hasrel && knd[i] == "integrate" && (" " r ",") !~ /[ \t,]approval:release[ \t]*,/) r = r ", approval:release"
        m = split(r "," dep[i], a, ",")
        for (k = 1; k <= m; k++) {
          t = a[k]; gsub(/^[ \t]+|[ \t]+$/, "", t)
          '"$_UNITS_READS_NORM"'
          sub(/^live:/, "", t); sub(/^head:.*/, "head", t)
          if (t !~ /[A-Za-z0-9]/) continue
          nt[i]++; tk[i, nt[i]] = t; if (t == "head") rhead[i] = 1; if (t == "record") rrec[i] = 1
        }
      }
      for (i = 1; i <= n; i++) {
        if (want != "" && id[i] != want) continue
        printf "%s\tkind\t%s\n", id[i], knd[i]
        if ((knd[i] == "integrate" || knd[i] == "close" || (!hasreads && knd[i] == "doc" && stp[i] + 0 >= 7)) && stp[i] ~ /^[0-9]+$/) put(i, "wait\tstep:" stp[i])
        for (k = 1; k <= nt[i]; k++) {
          t = tk[i, k]; p = substr(t, 7)
          if (t in at) { if (at[t] != i) put(i, "row\t" t); continue }
          for (j = 1; j <= n; j++) {
            if (j == i) continue
            if (t == "head" && code[j] && (!rhead[j] || stp[j] + 0 < stp[i] + 0) || t == "record" && docs[j] && (!rrec[j] || stp[j] + 0 < stp[i] + 0) \
              || t == "merge" && knd[j] == "integrate" || t ~ /^proof:/ && (p == "regression" && (knd[j] == "verify" || knd[j] == "test") || p == "review" && knd[j] == "review") \
              || t !~ /[ \t:!]/ && t ~ /[\/.*?]/ && writer(j, t)) put(i, "row\t" id[j])
          }
          if (t !~ /^(head|record|merge)$/ && (t ~ /[ \t:!]/ || t !~ /[\/.*?]/)) put(i, "wait\t" t)
        }
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
