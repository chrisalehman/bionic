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
# ONCE. Nothing the act wrote is written again: the kept copies stand once taken, a log that stands is
# never rewritten, and a Tasks table already in the nine cells is left as it is. So a second act changes
# no byte and prints the same, and an act broken off part way is finished by the next one. A run whose log
# stands with nothing kept is read from that log already; bringing it forward would replace its own
# facts, so it is refused.
#
# THE WAITS. A row's reads and deps are read through plan_read_waits, the one reads-to-waits rule, twice:
# over the old table, and over the new one with every deps cell empty, which is what the kind and the
# step imply. A wait on a row becomes that row's id in deps; a wait implied anyway is dropped; any other
# (an approval other than the plan's, a decision, an external token) is named on the gaps list and
# written nowhere, since a version-15 row holds no other wait.
#
# A DROPPED ROW is named by the translation, since no ruled event carries it. Its work is no longer owed,
# so it leaves the Tasks table, where the reader would read it as ready, and a wait on it is met as the
# fill meets it; both are named on the gaps list, and the row stays whole in the kept plan.
#
# A ROW'S SUITES AND LANDS-ON are a person's words about the task, so they go to the task's own section,
# a heading whose first word is its id, when the plan has one, and to the gaps list when it has none.
#
# EXITS. 0 done; 2 not a plan at plans/<epic>/<wave>.plan.md; 3 refused, a log with nothing kept; 1 a
# write failed, with nothing after it written.
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

_bf_plan() {  # <plan> <deps file|-> <gaps out> <dropped ids> -> the plan's text brought forward
  # Read twice: the first pass learns the Tasks table's columns, each row's suites and lands-on and which
  # rows have a section of their own; the second writes. A cell keeps its text as written, `\|` included.
  awk -v depf="$2" -v gapf="$3" -v drop=" $4 " -v nine="id step kind task deps size serves files artifact" '
    function cells(line, out,   n, i) {
      gsub(/\\[|]/, "\001", line); sub(/^[ \t]*[|]/, "", line); sub(/[|][ \t]*$/, "", line)
      n = split(line, out, "|"); for (i = 1; i <= n; i++) gsub(/^[ \t]+|[ \t]+$/, "", out[i])
      return n
    }
    function unesc(s,   o, i) { o = ""; while ((i = index(s, "\001"))) { o = o substr(s, 1, i - 1) "\\|"; s = substr(s, i + 1) }; return o s }
    function name(s) { s = tolower(s); gsub(/[ \t]+/, "-", s); return s }
    function none(s) { gsub(/—|–|-/, "", s); return s == "" }
    function heading(s) { sub(/^#+[ \t]+/, "", s); sub(/[ \t].*$/, "", s); sub(/[:.,]+$/, "", s); return s }
    function place(   k) { if (ins == "") return
      for (k = 1; k <= 2; k++) if (!none(cell[ins, w2[k]])) print w2[k] ": " unesc(cell[ins, w2[k]])
      for (k = 0; k < blanks; k++) print ""; ins = ""; blanks = 0 }
    BEGIN { nn = split(nine, w9, " "); split("suites lands-on", w2, " ")
      if (depf != "-") while ((getline l < depf) > 0) { t = index(l, "\t"); dep[substr(l, 1, t - 1)] = substr(l, t + 1) } }
    FNR == 1 && NR > 1 { sec = ""; nh = 0; tdone = 0; skip = 0 }
    { sub(/\r$/, "") }
    /^## / { sec = substr($0, 4); sub(/[ \t]+$/, "", sec) }
    FNR == NR {
      if (/^#+[ \t]/) own[heading($0)] = 1
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
    /^#/ { place() }
    /^## / { skip = (sec == "SDLC State" || sec == "Verification Matrix" || sec == "Handoff") }
    skip { next }
    /^#+[ \t]/ && !isnine && (heading($0) in row) && !index(drop, " " heading($0) " ") { print; ins = heading($0); next }
    ins != "" && /^[ \t]*$/ { blanks++; next }
    ins != "" { for (; blanks > 0; blanks--) print "" }
    sec == "Tasks" && !tdone && !isnine && /^[ \t]*[|]/ {
      if (!nh) { nh = 1; o = "|"; s = "|"; for (i = 1; i <= nn; i++) { o = o " " ((w9[i] in hn) ? hn[w9[i]] : w9[i]) " |"; s = s "---|" }; print o; print s; next }
      if ($0 ~ /^[ \t]*[|][-:| \t]+$/) next
      cells($0, r); id = r[col["id"]]; if (index(drop, " " id " ")) next
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
    END { place() }' "$1" "$1"
}

_bf_deps() {  # <old plan> <implied plan> <dropped ids> <deps out> -> the waits that are not deps, as gaps
  # The implied plan is the new table with every deps cell empty, so its waits are what kind and step imply.
  { plan_read_waits "$2"; printf '\034\n'; plan_read_waits "$1"; } | awk -F'\t' -v drop=" $3 " -v out="$4" '
    $0 == "\034" { old = 1; next }
    !old { if ($2 != "kind") imp[$1, $2, $3] = 1; next }
    $2 == "kind" { ord[++n] = $1; next }
    index(drop, " " $1 " ") { next }
    $2 == "row" && index(drop, " " $3 " ") { printf "gap/v1|ev=row|row=%s|field=%s|why=dropped\n", $1, $3; next }
    ($1, $2, $3) in imp { next }
    $2 == "row" { d[$1] = d[$1] (d[$1] == "" ? "" : ", ") $3; next }
    { printf "gap/v1|ev=row|row=%s|field=%s|why=unruled\n", $1, $3 }
    END { for (i = 1; i <= n; i++) if (d[ord[i]] != "") printf "%s\t%s\n", ord[i], d[ord[i]] > out; close(out) }'
}

_bf_compute() {  # <plan> <work dir> -> <work>/plan, the plan brought forward; <work>/gaps, the act's gaps list
  local plan="$1" w="$2" dropped
  translate "$plan" gaps > "$w/translated.gaps" || return 1
  dropped="$(sed -n 's/^gap\/v1|ev=dropped|row=\([^|]*\)|.*/\1/p' "$w/translated.gaps" | tr '\n' ' ')"
  : > "$w/deps"; : > "$w/cells.gaps"
  _bf_plan "$plan" - "" "$dropped" > "$w/implied.plan.md" || return 1
  _bf_deps "$plan" "$w/implied.plan.md" "$dropped" "$w/deps" > "$w/waits.gaps" || return 1
  _bf_plan "$plan" "$w/deps" "$w/cells.gaps" "$dropped" > "$w/plan" || return 1
  cat "$w/translated.gaps" "$w/waits.gaps" "$w/cells.gaps" | awk '!seen[$0]++' > "$w/gaps"
}

bf_main() {  # <plan> -> the act; prints the gaps list and kept=<directory>
  local plan="${1:-}" log rec kept wave st
  if [ ! -f "$plan" ] || ! log="$(reader_log "$plan" 2>/dev/null)"; then
    printf 'bring-forward: usage: bring-forward <docs>/plans/<epic>/<wave>.plan.md\n' >&2; return 2
  fi
  plan="$(cd "$(dirname "$plan")" && pwd -P)/${plan##*/}"; wave="${plan##*/}"; rec="${log%/run.log}"; kept="$rec/kept"
  if [ ! -d "$kept" ] && [ -e "$log" ]; then
    printf 'bring-forward: %s stands and nothing is kept: the run is read from its log, so it is not brought forward\n' "$log" >&2
    return 3
  fi
  BF_WORK="$(mktemp -d)" || return 1
  _bf_compute "$plan" "$BF_WORK" || return 1
  if [ ! -d "$kept" ]; then
    mkdir -p "${rec%/*}" && st="$(mktemp -d "${rec%/*}/.kept.XXXXXX")" || return 1
    if ! { cp -p "$plan" "$st/$wave" && { [ ! -d "$rec" ] || cp -Rp "$rec" "$st/record"; } && cp "$BF_WORK/gaps" "$st/gaps" \
      && mkdir -p "$rec" && mv "$st" "$kept"; }; then rm -rf "$st"; return 1; fi
  fi
  if [ ! -e "$log" ]; then
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
