#!/bin/bash
# payload/scripts/lib/plan-read.sh — THE ONE PARSER OF A PLAN'S AUTHORED PARTS.
#
#   plan_read_header <plan> [key]                    -> `key=value` per header key, or the one named
#   plan_read_row <plan> <heading> <column> <value>  -> `name=value` per cell of the row whose <column> is <value>
#
#   plan_read_table <plan> <heading> [key]           -> the header's names, then each row, then each row too wide
#   plan_read_dropped <plan>                         -> the id of each Tasks row whose status cell is dropped
#   plan_read_heading <plan> <name>[|<name>...]      -> the line of each `## <name>` heading outside a fence
#   plan_read_faults <plan>                          -> each part a version-15 plan has no place for, its line named
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
#   - a fenced block is prose: a table or a heading inside ``` is an example about the plan, not of it, and every
#     reader here, of a table, a heading or a section, asks `fenced()` and keeps no rule of its own;
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

# A plan's line ends translated, never deleted: `eol(record, out)` splits one input record into the lines it
# holds, a trailing CR dropped (CRLF) and each lone CR ending a line, and returns how many. Deleted, a
# CR-only plan would be one line and every key in it would read as absent. An awk helper, embedded by each
# reader of the plan, so a reader stays one process that may stop at the line it wants.
_PLAN_READ_EOL='
    function eol(rec, out,   n) { sub(/\r$/, "", rec); n = split(rec, out, "\r"); if (!n) { n = 1; out[1] = "" } return n }'

# With `all` after the key, every line of that key in the header answers, in its order: a key a person may write more
# than once (`goals:`) is read whole, while every other reader keeps the first line's answer.
plan_read_header() {  # <plan> [key [all]] -> `key=value` lines in the header's order; 1 none, 2 no plan
  [ -f "${1:-}" ] || return 2
  awk -v want="${2:-}" -v every="${3:-}" "$_PLAN_READ_EOL"'
    function line(s,   e, k, v) {
      if (++ln == 1) return s != "---"
      if (s == "---") return 1
      e = index(s, ":"); if (e < 2) return 0
      k = substr(s, 1, e - 1); v = substr(s, e + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", k); gsub(/^[ \t]+|[ \t]+$/, "", v)
      if (k ~ /[ \t]/ || ((k in seen) && every != "all") || (want != "" && k != want)) return 0
      sub(/^["\047]/, "", v); sub(/["\047]$/, "", v)
      seen[k] = 1; c++; print k "=" v
      return want != "" && every != "all"
    }
    { m = eol($0, L); for (i = 1; i <= m; i++) if (line(L[i])) exit }
    END { exit !c }' "$1"
}

# _plan_read_lines <file> -> its lines, a carriage return ending a line wherever it stands. A file saved
# with CR alone is one awk record, which no later pass can split again, so this pass comes first.
_plan_read_lines() { awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$1"; }

# The walk the table readers share, over `_plan_read_lines`: `cells` splits a row and returns how many
# cells it holds, the header line's names fill head[1..nh], `name(i)` prints column i's and `line()` a
# row's cells as `name=value` joined by tabs (a tab inside a cell read as a space). The key column is
# `key`, matched in either case, at kc. The reader's own `start()` runs at the header line and `row()`
# on each row after it, its cells in r[1..rn]. It reads to the end of its input and sets `stop` where it is
# done, never exiting early: its input is a pipe, and a writer cut short fails the pipeline under pipefail.
# NO APOSTROPHE inside it: it is single-quoted.
# A section is named by its heading the one way: `## ` and the name, its first letter in either case, going on
# only after a blank, so `## Design — v2` is the Design section and `## Designer notes` is not. `sec` is the name.
# What a fence is, said once for every reader and writer of a heading, so none ends a section at an example's line:
# `fenced(s)` is 1 on a ``` line, which opens or closes the block, and on each line inside one. It keeps the block in
# `fence`, so a reader calls it on every line, in order, from the file's first.
_PLAN_READ_FENCE='
    function fenced(s) { if (s !~ /^[ \t]*```/) return fence; fence = !fence; return 1 }'
_PLAN_READ_NAMED="$_PLAN_READ_FENCE"'
    function cap(s) { return tolower(substr(s, 1, 1)) substr(s, 2) }
    function named(h,   l) { l = length(sec); return (cap(substr(h, 1, l)) == cap(sec) && (length(h) == l || substr(h, l + 1, 1) ~ /[ \t]/)) }'
_PLAN_READ_TABLE="$_PLAN_READ_NAMED"'
    function cells(line, out,   n, i) {
      gsub(/\\[|]/, "\001", line); sub(/^[ \t]*[|]/, "", line); sub(/[|][ \t]*$/, "", line)
      n = split(line, out, "|")
      for (i = 1; i <= n; i++) { gsub(/^[ \t]+|[ \t]+$/, "", out[i]); gsub(/\001/, "|", out[i]) }
      return n
    }
    function name(i,   k) { k = tolower(head[i]); gsub(/[ \t]+/, "-", k); return k }
    function line(   i, o, v) { o = ""; for (i = 1; i <= nh; i++) { v = r[i]; gsub(/\t/, " ", v); o = o (i > 1 ? "\t" : "") name(i) "=" v }; return o }
    { sub(/\r$/, "") }
    stop { next }
    fenced($0) { next }
    /^[ \t]*#/ { if (on) { stop = 1; next }; if ($0 ~ /^##[ \t]/) { h = $0; sub(/^##[ \t]+/, "", h); sub(/[ \t]+$/, "", h); on = named(h) }; next }
    !on { next }
    !/^[ \t]*[|]/ { if (nh) stop = 1; next }
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
      found = stop = 1
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

# plan_read_blocks <plan> [<criterion>] -> `<criterion><TAB><line>` per line of each criterion's block in an older
# plan's `## Verification Matrix`, file order; a line of the section outside every block and outside the table (its
# head: stack-health:, walk-artifact:, false-green:) with the criterion empty. A block opens at a line whose text, a list
# leader dropped, begins `<criterion>:` with the criterion `AC-` and no blank or colon, and runs over the indented and
# blank lines under it; its heading line is not printed. With <criterion>, that block alone. Fenced lines are examples.
# 1 none, 2 no plan. The block's keys are what the person authored for the criterion; its state is never read here.
plan_read_blocks() {
  [ -f "${1:-}" ] || return 2
  _plan_read_lines "$1" | awk -v sec="Verification Matrix" -v want="${2:-}" "$_PLAN_READ_NAMED"'
    fenced($0) { next }
    /^##[ \t]/ { h = $0; sub(/^##[ \t]+/, "", h); sub(/[ \t]+$/, "", h); on = named(h); ac = ""; next }
    !on { next }
    /^[ \t]*[|]/ { ac = ""; next }
    /^[^ \t]/ { l = $0; sub(/^[-*+][ \t]+/, "", l); ac = match(l, /^AC-[^ \t:]+:/) ? substr(l, 1, RLENGTH - 1) : ""; if (ac == "" && want == "") { print "\t" $0; found = 1 }; next }
    ac == "" && $0 ~ /^[ \t]*$/ { next }
    want == "" || ac == want { print ac "\t" $0; found = 1 }
    END { exit !found }'
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
# out; a `#` line inside a fenced block is the section's text, never a heading, so a fence neither starts one nor
# ends one. With <key>: the value of the section's first `<key>: <value>` line. 1 when there is no such section or key,
# 2 when the plan is not a file. THE RULE IS ONE STRING, so every reader and every writer of a task's section finds
# the same heading: the act that writes a row's suites into its section takes `heading()` and `fenced()` from here.
_PLAN_READ_SECTION='function heading(s) { sub(/^#+[ \t]+/, "", s); sub(/[ \t].*$/, "", s); sub(/[:.,]+$/, "", s); return s }'
plan_read_section() {
  [ -f "${1:-}" ] || return 2
  [ -n "${2:-}" ] || return 1
  awk -v id="$2" -v key="${3:-}" "$_PLAN_READ_FENCE$_PLAN_READ_SECTION"'
    { sub(/\r$/, ""); f = fenced($0) }
    !f && /^#+[ \t]/ { if (on) exit; if (heading($0) == id) on = found = 1; next }
    !on { next }
    key != "" { if (index($0, key ":") == 1) { v = substr($0, length(key) + 2); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; got = 1; exit }; next }
    /^[ \t]*$/ { if (n) blank++; next }
    { for (; blank > 0; blank--) print ""; print; n++ }
    END { exit !(key == "" ? found : got) }' "$1"
}

# plan_read_heading <plan> <name>[|<name>...] -> `<line><TAB><name>` for each `## ` heading one of the names names, by
# the rule above, in file order; a heading inside a fenced block is an example and is not one. 1 when there is none,
# 2 when the plan is not a file. Lines are counted after a lone CR has ended one, so a CR-only plan names the line its
# reader sees.
plan_read_heading() {
  [ -f "${1:-}" ] || return 2
  [ -n "${2:-}" ] || return 1
  _plan_read_lines "$1" | awk -v names="$2" "$_PLAN_READ_NAMED"'
    BEGIN { n = split(names, want, "|") }
    fenced($0) { next }
    /^##[ \t]/ { h = $0; sub(/^##[ \t]+/, "", h); sub(/[ \t]+$/, "", h)
      for (i = 1; i <= n; i++) { sec = want[i]; if (named(h)) { print NR "\t" sec; found = 1; break } } }
    END { exit !found }'
}

# WHAT A VERSION-15 PLAN HOLDS is what a person wrote: its header, Goal, Problem, Design, Eval design, Tasks and a
# section per task. The machine's sections are gone to the log (the verification matrix, the state and the handoff), a
# Tasks row is its nine authored cells, and a header key stays only if the reader answers from it. The keys below were
# the run's own state written into its header (an abandon, a clean-up, the regression runs, the current step and its
# approvals), which the log carries now; the list is this one place, so a key the version-15 header loses is added here.
PLAN_READ_GONE_KEYS="abandoned cleaned current approved-by regression-runs"
PLAN_READ_GONE_SECTIONS="Verification Matrix|SDLC State|Handoff"
PLAN_READ_NINE="id step kind task deps size serves files artifact"

# plan_read_faults <plan> -> at version 15, one line per part of the plan that version has no place for, each naming
# where it is: `line <n>: ## <name>` per machine section, `line <n>: the Tasks table holds the cell <name>` per cell
# outside the nine (the header's line), `header key <key>:` per key the reader does not answer from. A plan at any other
# version has none here: both shapes are read until a version-14 plan is refused where it is written. 0 with faults,
# 1 with none, 2 when the plan is not a file.
plan_read_faults() {
  [ -f "${1:-}" ] || return 2
  local v secs cells keys
  v="$(plan_read_header "$1" canonical_sdlc_version)" || return 1
  [ "${v#*=}" = 15 ] || return 1
  secs="$(plan_read_heading "$1" "$PLAN_READ_GONE_SECTIONS" | awk -F'\t' '{
    print "line " $1 ": ## " $2 " — a version-15 plan holds no verification matrix, state or handoff section" }')" || :
  cells="$(_plan_read_lines "$1" | awk -v sec=Tasks -v key=id -v nine=" $PLAN_READ_NINE " '
    function start(   i) {
      for (i = 1; i <= nh; i++) if (index(nine, " " name(i) " ") == 0)
        print "line " NR ": the Tasks table holds the cell " name(i) " — a version-15 row is its nine authored cells"
      stop = 1
    }
    function row() { }'"$_PLAN_READ_TABLE")" || :
  keys="$(plan_read_header "$1" | awk -F= -v gone=" $PLAN_READ_GONE_KEYS " 'index(gone, " " $1 " ") {
    print "header key " $1 ": — the log holds this fact now, and the reader answers from no such key" }')" || :
  [ -n "$secs$cells$keys" ] || return 1
  local l; for l in "$secs" "$cells" "$keys"; do [ -z "$l" ] || printf '%s\n' "$l"; done
}
