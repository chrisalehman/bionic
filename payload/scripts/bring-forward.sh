#!/bin/bash
# bring-forward.sh — `bring-forward <plan>`: a version-14 run made a version-15 one, once and for good.
#
# THE ACT, in this order, each file put in place whole by one rename:
#   1. the plan and the record as they were are copied to `record/<wave>/kept/`, as `<wave>.plan.md` and
#      `record/`, with the act's gaps list as `gaps`;
#   2. `record/<wave>/run.log` is written from the translation (lib/translate.sh): the facts the old homes
#      hold, in the order they happened;
#   3. the plan is rewritten with no section a machine wrote (the SDLC State, the Verification Matrix and
#      the Handoff go), each Tasks row in its nine authored cells, and its version header at 15.
# It prints the gaps list, then `kept=<directory>`.
#
# ONCE. Nothing the act wrote is written again: the kept copies stand once taken, a log the act wrote is
# never rewritten, and a Tasks table already in the nine cells is left as it is. So a second act changes
# no byte and prints the same, and an act broken off part way is finished by the next one. A run whose
# writers had already moved to its log holds its facts half there: the translation reads that log as the
# newest of its homes (lib/translate.sh), so the log the act writes holds both halves. A log is the act's
# to write until the run reads as brought forward (lib/reader.sh `reader_brought`): while it stands as
# the kept copy of the record holds it, absent or the same bytes; once it differs, the act wrote it, or
# a writer appended to it after the act.
#
# THE WAITS. A row's reads and deps are read through plan_read_waits, the one reads-to-waits rule, twice:
# over the old table, and over the new one with every deps cell empty, which is what the kind and the
# step imply. A wait on a row becomes that row's id in deps, and a wait on a named approval (a decision's, the
# growth of the loaded set's) its `approval:<name>` after them, each in the order the row wrote it, so the task waits
# at 15 on what it waited on at 14; a wait implied anyway is dropped; any other (an external token, a proof
# a kind does not imply) is named on the gaps list and written nowhere, since a version-15 row holds no other wait.
#
# A DROPPED ROW stays in the Tasks table as the person wrote it: the translation writes its status cell as the
# run's `drop` event, so the log carries that its work is no longer owed, and a wait on it stays a wait, met
# as a landing meets it.
#
# A CRITERION'S TASK, the row or rows whose work proves it, was its block's `task:` line; at 15 it is the criteria
# table's `Task` cell (lib/plan-read.sh `plan_read_criterion_task`), so the act gives the `## Eval design` table that
# column, each criterion's cell what its block named, so it is owed at the same step after the act as before. Only what
# a version-15 cell can say is carried: the ids of rows the table holds, or `9` alone; any other token (the 9 beside an
# id, an id the table lacks), which the older reader passed over, and a block's task whose criterion has no Eval design
# row, are named on the gaps list, so the act never writes a page the write hook refuses. A table that already holds a
# `Task` column is left as written.
#
# A ROW'S SUITES AND LANDS-ON are a person's words about the task, so they go to the task's own section,
# a heading whose first word is its id, when the plan has one, and to the gaps list when it has none.
#
# EXITS. 0 done; 2 not a plan at plans/<epic>/<wave>.plan.md, or a plan not named *.plan.md; 1 a write failed, with
# nothing after it written.
#
# Executed, never sourced:  bash ${CLAUDE_PLUGIN_ROOT}/scripts/bring-forward.sh <plan>
# bash 3.2 (ADR-001).

set -uo pipefail
case "${BASH_SOURCE[0]}" in */*) _bf_dir="${BASH_SOURCE[0]%/*}" ;; *) _bf_dir="." ;; esac
_bf_dir="$(cd "$_bf_dir" && pwd -P)" || exit 2
# shellcheck source=/dev/null
. "$_bf_dir/lib/reader.sh" || exit 2
# shellcheck source=/dev/null
. "$_bf_dir/lib/translate.sh" || exit 2

_bf_plan() {  # <plan> <deps file|-> <gaps out> [<criteria tasks file>] -> the plan's text brought forward
  # Read twice: the first pass learns the Tasks table's columns, each row's suites and lands-on and which
  # rows have a section of their own; the second writes. A cell keeps its text as written, `\|` included.
  # A task's own section is found by plan-read.sh's one heading rule and its one fence rule, so the act writes where
  # the brief reads: a `#` line inside a fence is the section's text, never a heading, in either pass.
  awk -v depf="$2" -v gapf="$3" -v taskf="${4:--}" -v nine="id step kind task deps size serves files artifact" "$_PLAN_READ_FENCE$_PLAN_READ_SECTION"'
    function cells(line, out,   n, i) {
      gsub(/\\[|]/, "\001", line); sub(/^[ \t]*[|]/, "", line); sub(/[|][ \t]*$/, "", line)
      n = split(line, out, "|"); for (i = 1; i <= n; i++) gsub(/^[ \t]+|[ \t]+$/, "", out[i])
      return n
    }
    function unesc(s,   o, i) { o = ""; while ((i = index(s, "\001"))) { o = o substr(s, 1, i - 1) "\\|"; s = substr(s, i + 1) }; return o s }
    function name(s) { s = tolower(s); gsub(/[ \t]+/, "-", s); return s }
    function none(s) { gsub(/—|–|-/, "", s); return s == "" }
    # carry(c, v): what a version-15 Task cell can say of criterion c whose block named v; each other token a gap.
    function carry(c, v,   n, a, j, o) {
      if (v == "9") return "9"
      gsub(/,/, " ", v); n = split(v, a, /[ \t]+/); o = ""
      for (j = 1; j <= n; j++) { if (a[j] == "") continue
        if (a[j] in row) o = o (o == "" ? "" : ", ") a[j]
        else if (gapf != "") print "gap/v1|ev=criterion|criterion=" c "|field=task:" a[j] "|why=unruled" > gapf }
      return o == "" ? "—" : o
    }
    function addcell(l, v) { sub(/[ \t]+$/, "", l); return (l ~ /[|]$/) ? l " " v " |" : l " | " v }
    function place(   k) { if (ins == "") return
      for (k = 1; k <= 2; k++) if (!none(cell[ins, w2[k]])) print w2[k] ": " unesc(cell[ins, w2[k]])
      for (k = 0; k < blanks; k++) print ""; ins = ""; blanks = 0 }
    BEGIN { nn = split(nine, w9, " "); split("suites lands-on", w2, " ")
      if (depf != "-") while ((getline l < depf) > 0) { t = index(l, "\t"); dep[substr(l, 1, t - 1)] = substr(l, t + 1) }
      if (taskf != "-") while ((getline l < taskf) > 0) { t = index(l, "\t"); if (t > 1) { tk[substr(l, 1, t - 1)] = substr(l, t + 1); tord[++ntk] = substr(l, 1, t - 1) } } }
    FNR == 1 && NR > 1 { sec = ""; nh = 0; tdone = 0; skip = 0; fence = 0 }
    { sub(/\r$/, ""); f = fenced($0) }
    !f && /^## / { sec = substr($0, 4); sub(/[ \t]+$/, "", sec) }
    FNR == NR {
      if (!f && /^#+[ \t]/) own[heading($0)] = 1
      if (sec != "Tasks" || tdone || !/^[ \t]*[|]/) { if (sec == "Tasks" && nh) tdone = 1; next }
      if (!nh) { nh = cells($0, h); for (i = 1; i <= nh; i++) { col[name(h[i])] = i; hn[name(h[i])] = h[i] }
        isnine = (nh == nn); for (i = 1; i <= nn; i++) if (!(w9[i] in col)) isnine = 0; next }
      if ($0 ~ /^[ \t]*[|][-:| \t]+$/ || !("id" in col)) next
      cells($0, r); id = r[col["id"]]; row[id] = 1
      for (k = 1; k <= 2; k++) cell[id, w2[k]] = (w2[k] in col) ? r[col[w2[k]]] : ""
      next
    }
    FNR == 1 && $0 == "---" { head = 1; print; next }
    head { if ($0 == "---") head = 0; else if ($0 ~ /^canonical_sdlc_version:[ \t]*["\047]?14["\047]?[ \t]*$/) $0 = "canonical_sdlc_version: 15"; print; next }
    !f && /^#+[ \t]/ { place() }
    !f && /^## / { skip = (sec == "SDLC State" || sec == "Verification Matrix" || sec == "Handoff") }
    skip { next }
    !f && /^#+[ \t]/ && !isnine && (heading($0) in row) { print; ins = heading($0); next }
    ins != "" && /^[ \t]*$/ { blanks++; next }
    ins != "" { for (; blanks > 0; blanks--) print "" }
    sec == "Eval design" && eh && !/^[ \t]*[|]/ { edone = 1 }
    sec == "Eval design" && ntk && !edone && /^[ \t]*[|]/ {
      if (!eh) { eh = cells($0, e); ec = 0; et = 0
        for (i = 1; i <= eh; i++) { if (name(e[i]) == "criterion") ec = i; if (name(e[i]) == "task") et = 1 }
        if (et || !ec) { edone = 1; print; next }
        print addcell($0, "Task"); next }
      if ($0 ~ /^[ \t]*[|][-:| \t]+$/) { l = $0; sub(/[ \t]+$/, "", l); print l "---|"; next }
      cells($0, r); c = r[ec]; v = "—"
      if (c in tk) { if (!(c in cv)) cv[c] = carry(c, tk[c]); v = cv[c] }
      print addcell($0, v); next
    }
    sec == "Tasks" && !tdone && !isnine && /^[ \t]*[|]/ {
      if (!nh) { nh = 1; o = "|"; s = "|"; for (i = 1; i <= nn; i++) { o = o " " ((w9[i] in hn) ? hn[w9[i]] : w9[i]) " |"; s = s "---|" }; print o; print s; next }
      if ($0 ~ /^[ \t]*[|][-:| \t]+$/) next
      cells($0, r); id = r[col["id"]]
      o = "|"
      for (i = 1; i <= nn; i++) {
        v = (w9[i] == "deps") ? ((id in dep) ? dep[id] : "—") : ((w9[i] in col) ? unesc(r[col[w9[i]]]) : "")
        if (!(w9[i] in col) && w9[i] != "deps") { v = "—"; if (gapf != "") print "gap/v1|ev=row|row=" id "|field=" w9[i] "|why=absent" > gapf }
        o = o " " v " |"
      }
      print o
      for (k = 1; k <= 2; k++) if (!(id in own) && !none(cell[id, w2[k]]) && gapf != "") print "gap/v1|ev=row|row=" id "|field=" w2[k] "|why=unruled" > gapf
      next
    }
    sec == "Tasks" && nh { tdone = 1 }
    { print }
    END { place()
      if (gapf != "" && !et) for (i = 1; i <= ntk; i++) if (!(tord[i] in cv)) print "gap/v1|ev=criterion|criterion=" tord[i] "|field=task|why=absent" > gapf }' "$1" "$1"
}

_bf_deps() {  # <old plan> <implied plan> <deps out> -> the waits that are not deps, as gaps
  # The implied plan is the new table with every deps cell empty, so its waits are what kind and step imply.
  # A WAIT THE PERSON WROTE BY NAMING THE ROW, its id or a path its Files write, stays in deps though the default names
  # the same row: a review row reading what landed after the release says so only by that wait. A row nothing but the
  # default names (`head`, `record`, `merge`, a proof) is left to the default.
  { plan_read_waits "$2"; printf '\034\n'; plan_read_waits "$1"; } | awk -F'\t' -v out="$3" '
    function named(rs, r,   m, a, k, t) {
      m = split(rs, a, ",")
      for (k = 1; k <= m; k++) { t = a[k]; gsub(/^[ \t]+|[ \t]+$/, "", t); sub(/^live:/, "", t); if (t == r || (t !~ /[ \t:!]/ && t ~ /[\/.*?]/)) return 1 }
      return 0
    }
    $0 == "\034" { old = 1; next }
    !old { if ($2 != "kind") imp[$1, $2, $3] = 1; next }
    $2 == "kind" { ord[++n] = $1; next }
    ($1, $2, $3) in imp && !($2 == "row" && named($4, $3)) { next }
    $2 == "row" { d[$1] = d[$1] (d[$1] == "" ? "" : ", ") $3; next }
    $3 ~ /^approval:[A-Za-z0-9][A-Za-z0-9._-]*$/ { a[$1] = a[$1] ", " $3; next }
    { printf "gap/v1|ev=row|row=%s|field=%s|why=unruled\n", $1, $3 }
    END { for (i = 1; i <= n; i++) { r = ord[i]; v = d[r] a[r]; sub(/^, /, "", v); if (v != "") printf "%s\t%s\n", r, v > out }; close(out) }'
}

_bf_compute() {  # <plan> <work dir> -> <work>/plan, the plan brought forward; <work>/gaps, the act's gaps list
  local plan="$1" w="$2"
  translate "$plan" gaps > "$w/translated.gaps" || return 1
  : > "$w/deps"; : > "$w/cells.gaps"
  _bf_plan "$plan" - "" > "$w/implied.plan.md" || return 1
  _bf_deps "$plan" "$w/implied.plan.md" "$w/deps" > "$w/waits.gaps" || return 1
  plan_read_criterion_task "$plan" > "$w/tasks" 2>/dev/null || :
  _bf_plan "$plan" "$w/deps" "$w/cells.gaps" "$w/tasks" > "$w/plan" || return 1
  _bf_shared "$plan" > "$w/shared.gaps" || return 1
  cat "$w/translated.gaps" "$w/waits.gaps" "$w/cells.gaps" "$w/shared.gaps" | awk '!seen[$0]++' > "$w/gaps"
}

# THE RECORD AN INCIDENT'S PLAIN plan.md JOINED. At 14 every incident's plan named plain joins one record,
# `<docs>/record/plan.md`; renamed for its directory, the plan joins its own, and the old one is read by nothing. Facts of
# several incidents cannot be told apart there, so the act writes nothing from it and names each of its files on the
# gaps list: a fact is never dropped without a word. The refusal of the plain name says to move it first when no other
# plan shares it (_bf_misnamed).
_bf_shared() {  # <plan> -> a gap line per file of the shared record, when the plan is an incident's named for its directory
  local d="${1%/*}" docs old
  [ "${1##*/}" = "${d##*/}.plan.md" ] && [ "${d%/*/*}/incidents" = "${d%/*}" ] || return 0
  docs="${d%/*/*}"; old="$docs/record/plan.md"
  [ -d "$old" ] || return 0
  ( cd "$old" && find . -type f | sed 's#^\./##' | LC_ALL=C sort ) | sed 's#^#gap/v1|ev=record|record=plan.md|field=#; s#$#|why=shared#'
}

# A PLAN NOT NAMED *.plan.md is refused before anything is written. At 15 a run is found by the walk, and joined to
# its record, by that name (lib/run.sh `_run_page15`, lib/reader.sh `reader_record`); a page at 15 under any other name
# is found by no walk and judged by no gate, and every incident's plain plan.md shares one record. The words name the
# plan for its directory, which is how the skill lays an incident out; elsewhere for its own stem. For an incident's
# plain plan.md whose record stands they say what becomes of it: moved to the new name when no other plan named plain
# joins it and that name is free, so the road loses nothing; otherwise named file by file on the act's gaps list.
_bf_misnamed() {  # <plan, resolved> <its record> -> the refusal on stderr
  local dir="${1%/*}" base="${1##*/}" want to f n=0 tail
  case "$dir" in */incidents/*) want="${dir##*/}.plan.md" ;; *) want="${base%.md}.plan.md" ;; esac
  tail="name it $dir/$want and run the act again"
  if [ "$base" = plan.md ] && [ "${dir%/*}" = "${2%/record/*}/incidents" ] && [ -d "$2" ]; then
    to="${2%/*}/${want%.plan.md}"
    for f in "${2%/record/*}"/plans/"$base" "${2%/record/*}"/plans/*/"$base" "${2%/record/*}"/incidents/"$base" "${2%/record/*}"/incidents/*/"$base"; do
      [ -f "$f" ] && [ "$f" != "$1" ] && n=$((n + 1))
    done
    if [ "$n" -gt 0 ]; then
      tail="$tail; $2 is shared by $n other plan$([ "$n" -eq 1 ] || echo s) named $base, so the act will name each of its files on the gaps list"
    elif [ -e "$to" ]; then
      tail="$tail; $to already stands, so the act will name each file of $2 on the gaps list"
    else
      tail="name it $dir/$want, move $2 to $to, and run the act again"
    fi
  fi
  printf 'bring-forward: refused — %s is not named as a plan: at version 15 a run is found and joined to its record by a name ending .plan.md; %s\n' \
    "$1" "$tail" >&2
}

bf_main() {  # <plan> -> the act; prints the gaps list and kept=<directory>
  local plan="${1:-}" log rec kept wave st
  if [ ! -f "$plan" ] || ! log="$(reader_log "$plan" 2>/dev/null)"; then
    printf 'bring-forward: usage: bring-forward <docs>/plans/<epic>/<wave>.plan.md\n' >&2; return 2
  fi
  plan="$(cd "$(dirname "$plan")" && pwd -P)/${plan##*/}"; wave="${plan##*/}"; rec="${log%/run.log}"; kept="$rec/kept"
  case "$wave" in *.plan.md) ;; *) _bf_misnamed "$plan" "$rec"; return 2 ;; esac
  BF_WORK="$(mktemp -d)" || return 1
  _bf_compute "$plan" "$BF_WORK" || return 1
  if [ ! -d "$kept" ]; then
    mkdir -p "${rec%/*}" && st="$(mktemp -d "${rec%/*}/.kept.XXXXXX")" || return 1
    if ! { cp -p "$plan" "$st/$wave" && { [ ! -d "$rec" ] || cp -Rp "$rec" "$st/record"; } && cp "$BF_WORK/gaps" "$st/gaps" \
      && mkdir -p "$rec" && mv "$st" "$kept"; }; then rm -rf "$st"; return 1; fi
  fi
  if ! reader_brought "$plan"; then
    { translate "$plan" events > "$log.tmp.$$" && mv "$log.tmp.$$" "$log"; } || { rm -f "$log.tmp.$$"; return 1; }
  fi
  if ! cmp -s "$BF_WORK/plan" "$plan"; then
    { cat "$BF_WORK/plan" > "$plan.tmp.$$" && mv "$plan.tmp.$$" "$plan"; } || { rm -f "$plan.tmp.$$"; return 1; }
  fi
  cat "$kept/gaps"; printf 'kept=%s\n' "$kept"
}

BF_WORK=""
trap '[ -z "$BF_WORK" ] || rm -rf "$BF_WORK"' EXIT
bf_main "$@"
