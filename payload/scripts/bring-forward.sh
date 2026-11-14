#!/bin/bash
# bring-forward.sh — `bring-forward <plan>`: a version-14 run made a version-15 one, once and for good.
#
# THE ACT, in this order, each file put in place whole by one rename:
#   1. the plan and the record as they were are copied to `record/<wave>/kept/`, as `<wave>.plan.md` and
#      `record/`, with the act's gaps list as `gaps`;
#   2. `record/<wave>/run.log` is written from the translation (lib/translate.sh): the facts the old homes
#      hold, in the order they happened, each confirmation a person wrote in a criterion's block followed by
#      the approval naming the criterion, 15's one home for it (_bf_log);
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
# WHOSE KEPT COPY. A kept copy standing beside a plan not yet at 15 is this act's own only when it holds the plan as it
# stands, byte for byte, and the run's log is absent, the log the copy holds, or the log the act writes from the copy (_bf_log
# over the kept plan and record, laid out as a run of their own): then the act was broken off before it rewrote
# the plan, and this act finishes it. Any other kept copy was left by another build of the record directory or by the
# plan as it stood before a later edit, and a log neither it nor the act wrote is no log the act may judge as its own; both
# are refused in words, before anything is written (_bf_own).
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
# EXITS. 0 done; 2 not a plan at plans/<epic>/<wave>.plan.md, a plan not named *.plan.md, or a kept copy not this run's
# own; 1 a write failed, with nothing after it written.
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
# shellcheck source=/dev/null
. "$_bf_dir/lib/plan.sh" || exit 2

_bf_plan() {  # <plan> <deps file|-> <gaps out> [<criteria tasks file>] [<header keys file>] [<criteria file>] -> the plan's text brought forward
  # Read twice: the first pass learns the Tasks table's columns, each row's suites and lands-on and which
  # rows have a section of their own; the second writes. A cell keeps its text as written, `\|` included.
  # A task's own section is found by plan-read.sh's one heading rule and its one fence rule, so the act writes where
  # the brief reads: a `#` line inside a fence is the section's text, never a heading, in either pass.
  awk -v depf="$2" -v gapf="$3" -v taskf="${4:--}" -v headf="${5:--}" -v critf="${6:--}" -v nine="id step kind task deps size serves files artifact" "$_PLAN_READ_FENCE$_PLAN_READ_SECTION"'
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
    function tcell(v) { if (v == "") return "—"; gsub(/[|]/, "\\|", v); return v }
    function addcell(l, v) { sub(/[ \t]+$/, "", l); return (l ~ /[|]$/) ? l " " v " |" : l " | " v }
    function place(   k) { if (ins == "") return
      for (k = 1; k <= 2; k++) if (!none(cell[ins, w2[k]])) print w2[k] ": " unesc(cell[ins, w2[k]])
      for (k = 0; k < blanks; k++) print ""; ins = ""; blanks = 0 }
    BEGIN { nn = split(nine, w9, " "); split("suites lands-on", w2, " ")
      if (depf != "-") while ((getline l < depf) > 0) { t = index(l, "\t"); dep[substr(l, 1, t - 1)] = substr(l, t + 1) }
      if (taskf != "-") while ((getline l < taskf) > 0) { t = index(l, "\t"); if (t > 1) { tk[substr(l, 1, t - 1)] = substr(l, t + 1); tord[++ntk] = substr(l, 1, t - 1) } }
      if (headf != "-") while ((getline l < headf) > 0) { t = index(l, "\t"); if (t > 1) { hk[++nhk] = substr(l, 1, t - 1); hv[hk[nhk]] = substr(l, t + 1) } }
      if (critf != "-") while ((getline l < critf) > 0) if (split(l, x, "\t") >= 5) { ncr++; for (i = 1; i <= 5; i++) cr[ncr, i] = x[i] } }
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
    # A key the header names with no value takes the value in its place; one it does not name goes last.
    head && match($0, /^[a-z][a-z_-]*[ \t]*:[ \t]*$/) { k = $0; sub(/[ \t]*:.*$/, "", k); if ((k in hv) && !(k in hput)) { hput[k] = 1; print k ": " hv[k]; next } }
    head { if ($0 == "---") { for (i = 1; i <= nhk; i++) if (!(hk[i] in hput)) print hk[i] ": " hv[hk[i]]; head = 0 }
      else if ($0 ~ /^canonical_sdlc_version:[ \t]*["\047]?14["\047]?[ \t]*$/) $0 = "canonical_sdlc_version: 15"; print; next }
    !f && /^#+[ \t]/ { place() }
    # A plan whose criteria stood only in its matrix gets their table where the matrix stood, a row per criterion.
    !f && /^## / && sec == "Verification Matrix" && ncr && !made { made = 1
      print "## Eval design"; print ""; print "| Requirement | Criterion | Eval type | Eval | Fails when | Task |"; print "|---|---|---|---|---|---|"
      for (i = 1; i <= ncr; i++) { c = cr[i, 1]; v = "—"; if (c in tk) { cv[c] = carry(c, tk[c]); v = cv[c] }
        print "| " tcell(cr[i, 3]) " | " tcell(c) " | " tcell(cr[i, 2]) " | " tcell(cr[i, 4]) " | " tcell(cr[i, 5]) " | " v " |" }
      print "" }
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
  _bf_homes "$plan" "$w/head" > "$w/homes.gaps" || return 1
  _bf_plan "$plan" - "" > "$w/implied.plan.md" || return 1
  _bf_deps "$plan" "$w/implied.plan.md" "$w/deps" > "$w/waits.gaps" || return 1
  plan_read_criterion_task "$plan" > "$w/tasks" 2>/dev/null || :
  _bf_criteria "$plan" > "$w/criteria" || return 1
  _bf_plan "$plan" "$w/deps" "$w/cells.gaps" "$w/tasks" "$w/head" "$w/criteria" > "$w/plan" || return 1
  _bf_shared "$plan" > "$w/shared.gaps" || return 1
  cat "$w/translated.gaps" "$w/homes.gaps" "$w/waits.gaps" "$w/cells.gaps" "$w/shared.gaps" | awk '!seen[$0]++' > "$w/gaps"
}

# THE CRITERIA. At 15 a run's criteria are its `## Eval design` table's rows; at 14 a plan could hold them in its matrix
# alone, which the act takes out. Such a plan gets the table from the matrix: a row per criterion in the matrix's order,
# its tier as the Eval type (lib/scale.sh reads a `T<n>` type as that tier), its block's first `serves:`, `eval:` and
# `fails-when:` as its Requirement, Eval and Fails when, and its block's task in the Task column as a table's rows are
# given one. A plan that holds a criteria table is left as the act leaves it.
_bf_criteria() {  # <plan> -> `<criterion><TAB><tier><TAB><requirement><TAB><eval><TAB><fails when>` per matrix row; nothing when the plan holds a criteria table
  plan_read_table "$1" 'Eval design' criterion >/dev/null 2>&1 && return 0
  { plan_read_rows "$1" 'Verification Matrix' ac 2>/dev/null; printf '\034\n'; plan_read_blocks "$1" 2>/dev/null || :; } | awk -F'\t' '
    $0 == "\034" { part = 1; next }
    !part { a = ""; t = ""; for (i = 1; i <= NF; i++) { e = index($i, "="); k = substr($i, 1, e - 1); if (k == "ac") a = substr($i, e + 1); else if (k == "tier") t = substr($i, e + 1) }
      if (a != "" && !(a in seen)) { seen[a] = 1; ord[++n] = a; tier[a] = t }; next }
    $1 == "" { next }
    { l = substr($0, length($1) + 2) }
    match(l, /^[ \t]*(serves|eval|fails-when)[ \t]*:/) { k = l; sub(/^[ \t]+/, "", k); sub(/[ \t]*:.*$/, "", k)
      if (($1, k) in v) next; x = substr(l, RLENGTH + 1); gsub(/\t/, " ", x); sub(/^[ ]+/, "", x); sub(/[ ]+$/, "", x); v[$1, k] = x }
    END { for (i = 1; i <= n; i++) { a = ord[i]; printf "%s\t%s\t%s\t%s\t%s\n", a, tier[a], v[a, "serves"], v[a, "eval"], v[a, "fails-when"] } }'
}

# THE HEADER'S KEYS A STEP OWES AT 15. At 14 the working branch and the base were the SDLC State's: its first
# `working-branch:` line and its first `base-sha:` line, read as lib/run.sh `plan_working_branch` and lib/proof.sh
# `proof_plan_base` read them, else the Step 4 block's `branch:` and `base-sha:` fields. Step 7's document was its block's
# `adr:` or `rca:` path, or its `n/a:` reason, as lib/walls.sh `validate_document_step` asked; at 15 it is the header's
# `adrs:`, the records named, or `none` with the reason. The integration branch was the State's `integration-branch:`
# line, which the act asks of lib/plan.sh `plan_integration_branch`, the one reader, before the section goes; at 15 it finds
# the header's.
# At 15 the header holds all four and the steps' checks ask it there, so the act writes each the header lacks. One the
# run owed, past its step, and no home held is named on the gaps list; a header that holds a key keeps its own value. A
# run that held no integration branch is named nowhere: 14's one reader found none either, so the act drops nothing.
_bf_homes() {  # <plan> <header out> -> a `<key><TAB><value>` line in <header out> per key to write; a gap line per key owed and held nowhere
  local plan="$1" k v found ib fn=plan_integration_branch
  # The branch is asked of its one reader over the plan as it stands, State section in; its key is the reader's name with
  # hyphens, so the act holds no spelling of the key of its own for the tree's one-reader search to find.
  ib="${fn#plan_}"; ib="${ib//_/-}"
  # A Step block is its `- Step <n>:` line and the indented lines under it; one held (pending) is no step reached.
  found="$(_translate_section "$plan" "SDLC State" | awk '
    function word(s) { sub(/^[ \t]+/, "", s); sub(/[ \t].*$/, "", s); gsub(/^["\047]|["\047]$/, "", s); return s }
    function said(s, k) { if (!match(s, "(^|[^-_[:alnum:]])" k "[ \t]*:")) return ""; s = substr(s, RSTART + RLENGTH); sub(/;.*$/, "", s)
      sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function field(s, k) { return word(said(s, k)) }
    function first(k, v) { if (v != "" && !(k in got)) got[k] = v }
    function doc(v) { if (v != "" && !((v) in named)) { named[v] = 1; docs = docs (docs == "" ? "" : ", ") v } }
    /^- Step [0-9]+[ab]?:/ { n = substr($0, 8, index($0, ":") - 8); sub(/[ab]$/, "", n); t = substr($0, index($0, ":") + 1)
      blk = (t ~ /^[ \t]*\(pending\)[ \t]*$/) ? "" : n; if (blk != "") reached[blk] = 1 }
    !/^- Step [0-9]/ { t = $0; if (/^[^ \t]/) blk = "" }
    !curseen && /^[ \t]*current[ \t]*:/ { cur = word(substr($0, index($0, ":") + 1)) + 0; curseen = 1 }
    /^[ \t]*working-branch[ \t]*:/ { first("working-branch", word(substr($0, index($0, ":") + 1))) }
    /^[ \t]*base-sha[ \t]*:/ { first("base-sha", word(substr($0, index($0, ":") + 1))) }
    blk == "4" { if (b4 == "") b4 = field(t, "branch"); if (s4 == "") s4 = field(t, "base-sha") }
    blk == "7" { doc(field(t, "adr")); doc(field(t, "rca")); if (na == "") na = said(t, "n/a") }
    END { first("working-branch", b4); first("base-sha", s4); first("adrs", docs); if (na != "") first("adrs", "none — " na)
      for (k in got) printf "%s\t%s\n", k, got[k]
      for (n = 4; n <= 7; n += 3) if (cur >= n || (n in reached)) print "reached\t" n }')" || return 1
  : > "$2"
  for k in working-branch:4 base-sha:4 adrs:7 "$ib:"; do
    v="$(plan_read_header "$plan" "${k%:*}" 2>/dev/null)" && [ -n "${v#*=}" ] && continue
    if [ "${k%:*}" = "$ib" ]; then v="$("$fn" "$plan")"
    else v="$(awk -F'\t' -v k="${k%:*}" '$1 == k { print $2; exit }' <<< "$found")"; fi
    if [ -n "$v" ]; then printf '%s\t%s\n' "${k%:*}" "$v" >> "$2"
    elif [ -n "${k#*:}" ] && grep -qx "reached	${k#*:}" <<< "$found"; then printf 'gap/v1|ev=step|n=%s|field=%s|why=absent\n' "${k#*:}" "${k%:*}"; fi
  done
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

# THE CONFIRMATION. At 14 a person confirmed a criterion by a `user-confirmed: <who> <day> <words>` line in its block,
# which the translation carries as the field `confirmed=` of the criterion's proof or waiver; at 15 the reader takes a
# person's confirmation only from an approval naming the criterion, so the act asks the translation for that approval
# too (lib/translate.sh `_translate_matrix`). A run at 14 is read through the translation in place, and that reading
# asks for none, so it reads as it did.
_bf_log() {  # <plan> -> the run's log the act writes
  TRANSLATE_CONFIRMED=approval translate "$1" events
}

_bf_own() {  # <plan> <kept> <log> <work dir> -> 0 the kept copy is this act's own; 1 not, the refusal on stderr; 3 a copy failed
  local plan="$1" kept="$2" log="$3" name="${1##*/}" k why
  if ! cmp -s "$kept/$name" "$plan"; then
    why="the plan it holds is not $plan as it stands, so another build of the record or the plan before a later edit left it"
  elif [ ! -f "$log" ] || cmp -s "$log" "$kept/record/run.log"; then
    return 0
  else
    k="$4/kept"; mkdir -p "$k/plans" "$k/record" && cp "$kept/$name" "$k/plans/" || return 3
    [ ! -d "$kept/record" ] || cp -R "$kept/record" "$k/record/${name%.plan.md}" || return 3
    _bf_log "$k/plans/$name" 2>/dev/null | cmp -s - "$log" && return 0
    why="the run's log $log is neither the log it holds nor the one the act writes from it, so another build left the two"
  fi
  printf 'bring-forward: refused — %s is not this run'"'"'s kept copy: %s. Move it aside and run the act again; nothing was written.\n' "$kept" "$why" >&2
  return 1
}

bf_main() {  # <plan> -> the act; prints the gaps list and kept=<directory>
  local plan="${1:-}" log rec kept wave st
  if [ ! -f "$plan" ] || ! log="$(reader_log "$plan" 2>/dev/null)"; then
    printf 'bring-forward: usage: bring-forward <docs>/plans/<epic>/<wave>.plan.md\n' >&2; return 2
  fi
  plan="$(cd "$(dirname "$plan")" && pwd -P)/${plan##*/}"; wave="${plan##*/}"; rec="${log%/run.log}"; kept="$rec/kept"
  case "$wave" in *.plan.md) ;; *) _bf_misnamed "$plan" "$rec"; return 2 ;; esac
  BF_WORK="$(mktemp -d)" || return 1
  if [ -d "$kept" ] && [ "$(plan_read_header "$plan" canonical_sdlc_version 2>/dev/null)" != canonical_sdlc_version=15 ]; then
    _bf_own "$plan" "$kept" "$log" "$BF_WORK"; case $? in 0) ;; 1) return 2 ;; *) return 1 ;; esac
  fi
  _bf_compute "$plan" "$BF_WORK" || return 1
  if [ ! -d "$kept" ]; then
    mkdir -p "${rec%/*}" && st="$(mktemp -d "${rec%/*}/.kept.XXXXXX")" || return 1
    if ! { cp -p "$plan" "$st/$wave" && { [ ! -d "$rec" ] || cp -Rp "$rec" "$st/record"; } && cp "$BF_WORK/gaps" "$st/gaps" \
      && mkdir -p "$rec" && mv "$st" "$kept"; }; then rm -rf "$st"; return 1; fi
  fi
  if ! reader_brought "$plan"; then
    { _bf_log "$plan" > "$log.tmp.$$" && mv "$log.tmp.$$" "$log"; } || { rm -f "$log.tmp.$$"; return 1; }
  fi
  if ! cmp -s "$BF_WORK/plan" "$plan"; then
    { cat "$BF_WORK/plan" > "$plan.tmp.$$" && mv "$plan.tmp.$$" "$plan"; } || { rm -f "$plan.tmp.$$"; return 1; }
  fi
  cat "$kept/gaps"; printf 'kept=%s\n' "$kept"
}

BF_WORK=""
trap '[ -z "$BF_WORK" ] || rm -rf "$BF_WORK"' EXIT
bf_main "$@"
