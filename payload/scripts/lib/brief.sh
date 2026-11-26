#!/bin/bash
# payload/scripts/lib/brief.sh — A DISPATCH'S CONTRACT, AS ONE READER READS IT
#
# WHAT IT OWNS. The value filter every roster field passes (`sanitize`), the one reader of a brief's
# contract lines (`brief_contract`), the bound each field is stored at (`brief_field`), and the brief
# file a dispatch names: its sum, its render mark and its check (`brief_sum`, `brief_mark`,
# `brief_named`, `brief_file_read`).
#
# THE CONTRACT IS LINES, NOT PROSE. A dispatch that binds a plan row is handed the file the brief verb
# rendered for it, and its contract is that file's label lines, written by the verb in one shape. A
# dispatch that binds no row (a researcher, a test-runner, a prototype) writes the same lines in its
# prompt, and the same reader reads them there. A label is read only at the start of a line of its own,
# its value is the rest of that line, and nothing is guessed out of a sentence: a label inside prose is
# prose.
#
# THE INTERFACE.
#
#   brief_contract <text>       -> `kind=value` lines, the kinds the roster row and the wall read
#   brief_field <lines> <kind>  -> one kind's value, bounded as the roster row stores it
#   brief_sum, brief_mark, brief_named, brief_file_read  -> the brief file, below
#
# BASH 3.2. SOURCED, NEVER EXECUTED, AND SILENT AT SOURCE TIME.
#
# [WALL: tests/brief-file.test.sh]
# [WALL: tests/dispatch-preflight.test.sh]

declare -F bionic_need >/dev/null 2>&1 || case "${BASH_SOURCE[0]}" in */*) . "${BASH_SOURCE[0]%/*}/loader.sh" ;; *) . ./loader.sh ;; esac

# THE ONE RUN RULE ON BOTH SIDES OF THE ROW: a declared run is stored through `cmdnorm_run`, the rule the
# writer-side budget arm builds its claim with, so the two compare one spelling. THE ONE SUITE-NAME GRAMMAR:
# a `Lands-on:` entry is named by suite.sh's `suite_name`, the function line.sh reads a roster's `lands_on=`
# with. Each is guarded on a function the same file defines beside that variable, so a caller that has sourced
# the file already pays nothing.
bionic_need cmd-class.sh _cmd_class_awk
bionic_need suite.sh bionic_suite_start
bionic_need fields.sh line_field_clean

# Values are pipe-delimited on one line, so a field carrying a newline or a `|` would forge a row. Never a
# refusal: the ledger normalizes and records. The third argument is the field name: `files=`,
# `suites_allowed=` and `re_executes=` are list-valued and never cut, since a cut silently narrows a budget;
# every other field is prose or one path and keeps its cap. `re_executes=` keeps its `|`, which the row
# writer (`roster_row`, lib/roster.sh) escapes for that field alone, because a declared run is read back and
# compared to what an agent typed.
# Every field but `re_executes=` is lib/fields.sh's `line_field_clean`; that one keeps its own fold, since it
# keeps the `|`.
sanitize() {  # <value> <max-chars> [<field name>]
  case "${3:-}" in
    re_executes)
      printf '%s' "$1" | tr '\n\r\t' '   ' | sed -e 's/[[:cntrl:]]/ /g' -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//' ;;
    files|suites_allowed) line_field_clean "$1" ;;
    *) line_field_clean "$1" "$2" ;;
  esac
}

# brief_contract <text> -> one `kind=value` line per contract label the text carries, absent kinds omitted.
# THE LABELS, each read once, its first line winning; matched without regard to case, at the start of a line
# outside a ``` fence, after any indent and one list mark:
#   Expected artifact(s)  deliverable   one path (a `/` in it, or an extension), its first word
#   Expected duration     duration      the value to its first full stop, comma or bracket
#   Progress artifact     progress      one path, its first word
#   Cadence               cadence       the value to its first full stop, comma or bracket
#   Subprocess claim      claims        the backticked run, else the text before a comma or an arrow
#   Done marker           done          one path, its first word
#   Deliverable-waiver    waiver        the whole value
#   Files                 files         comma-separated paths; a rendered `<path>  # (pinned by …)` line below adds one
#   Suites                suites        suite file names (a path-qualified run.sh among them), space-joined, or `none`
#   Re-executes           re_executes   each backticked run, through the one run rule (lib/cmd-class.sh)
#   Questions             questions     evidence, adversarial, structure, in that order, comma-joined
#   Lands-on              lands_on      suites as lib/suite.sh names them and backticked commands, comma-joined;
#                                       `none <reason>` is lands_on=none and lands_on_reason=
#   Lands-red, Red-evidence, Row, Kind, Throwaway tree   lands_red, red_evidence, row, kind, tree: the value
# A trailing ` # …` is a note, never a value, and a `<slot>` is no value.
brief_contract() {
  printf '%s\n' "${1-}" | awk "${CMD_RUN_NORM_AWK}${BIONIC_SUITE_NAME_AWK}"'
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function nonote(s) { if (match(s, /(^|[ \t])#/)) s = substr(s, 1, RSTART - 1); return trim(s) }
    function bare(s) { gsub(/^[`"(\[]+|[`")\],;:]+$/, "", s); sub(/\.$/, "", s); return s }
    function slot(s) { return (s ~ /<[^>]*>/) }
    function word(s,   w) { split(nonote(s), w, /[ \t]+/); s = bare(w[1]); return (slot(s) ? "" : s) }
    function path(s) { s = word(s); return ((index(s, "/") || s ~ /\.[A-Za-z][A-Za-z0-9]*$/) ? s : "") }
    function sentence(s) { s = nonote(s); sub(/\.([ \t].*)?$/, "", s); sub(/[ \t]*[(;,].*$/, "", s); return (slot(s) ? "" : trim(s)) }
    function addfile(e) {
      e = trim(bare(trim(e)))
      if (e == "" || e == "-" || tolower(e) == "none" || e ~ /[ \t]/ || slot(e) || index("," F ",", "," e ",")) return
      F = (F == "" ? e : F "," e)
    }
    function files(v,   n, a, i) { n = split(nonote(v), a, ","); for (i = 1; i <= n; i++) addfile(a[i]) }
    function suites(v,   n, a, i, t) {
      v = nonote(v); if (tolower(v) == "none") return "none"
      n = split(v, a, /[ \t,]+/); o = ""
      for (i = 1; i <= n; i++) {
        t = bare(a[i]); if (t ~ /.\/run\.sh$/) t = "run.sh"; else { sub(/.*\//, "", t); if (t == "run.sh") continue }
        if ((t != "run.sh" && t !~ /^[A-Za-z0-9_][A-Za-z0-9_.-]*\.test\.sh$/) || index(" " o " ", " " t " ")) continue
        o = (o == "" ? t : o " " t)
      }
      return o
    }
    function runs(v,   o, r, k) {
      o = ""
      while ((k = index(v, "`")) > 0) {
        v = substr(v, k + 1); k = index(v, "`"); if (k == 0) break
        r = cmdnorm_run(substr(v, 1, k - 1)); v = substr(v, k + 1)
        if (r != "" && !slot(r) && index(" " o " ", " `" r "` ") == 0) o = (o == "" ? "`" r "`" : o " `" r "`")
      }
      return o
    }
    function questions(v,   q, n, a, i, o) {
      n = split(tolower(v), a, /[ \t,]+/); for (i = 1; i <= n; i++) q[a[i]] = 1
      o = ""; if ("evidence" in q) o = "evidence"
      if ("adversarial" in q) o = o (o == "" ? "" : ",") "adversarial"
      if ("structure" in q) o = o (o == "" ? "" : ",") "structure"
      return o
    }
    function claims(v,   a, b) {
      a = index(v, "`"); if (a > 0) { b = index(substr(v, a + 1), "`"); if (b > 1) return substr(v, a + 1, b - 1) }
      v = nonote(v); a = index(v, ","); if (a > 0) v = substr(v, 1, a - 1)
      a = index(v, "->"); if (a > 0) v = substr(v, 1, a - 1)
      a = index(v, "\342\206\222"); if (a > 0) v = substr(v, 1, a - 1)
      v = trim(v); return (slot(v) ? "" : v)
    }
    function landson(v,   o, k, n, a, i, t) {
      v = nonote(v); o = ""
      if (tolower(v) ~ /^none([ \t,;:.]|$)/) {
        v = substr(v, 5); sub(/^[^A-Za-z0-9]+/, "", v)
        print "lands_on=none"; if (v ~ /[A-Za-z0-9]/) print "lands_on_reason=" v
        return
      }
      while (v != "") {
        k = index(v, "`")
        n = split(k ? substr(v, 1, k - 1) : v, a, /[ \t,]+/)
        for (i = 1; i <= n; i++) { t = suite_name(a[i]); if (t != "" && !index("," o ",", "," t ",")) o = (o == "" ? t : o "," t) }
        if (!k) break
        v = substr(v, k + 1); k = index(v, "`"); if (!k) break
        t = cmdnorm_run(substr(v, 1, k - 1)); v = substr(v, k + 1)
        if (t != "") { t = lands_cmd(t); if (!index("," o ",", "," t ",")) o = (o == "" ? t : o "," t) }
      }
      if (o != "") print "lands_on=" o
    }
    BEGIN {
      K["expected artifact"] = K["expected artifacts"] = "deliverable"; K["expected duration"] = "duration"
      K["progress artifact"] = "progress"; K["cadence"] = "cadence"; K["subprocess claim"] = "claims"
      K["done marker"] = "done"; K["deliverable-waiver"] = "waiver"; K["files"] = "files"; K["suites"] = "suites"
      K["re-executes"] = "re_executes"; K["questions"] = "questions"; K["lands-on"] = "lands_on"
      K["lands-red"] = "lands_red"; K["red-evidence"] = "red_evidence"; K["row"] = "row"; K["kind"] = "kind"
      K["throwaway tree"] = "tree"
    }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    {
      l = trim($0); sub(/^([-*+]|[0-9]+[.)])[ \t]+/, "", l)
      if (infiles && index(l, "# (pinned by ") && !match(l, /^[A-Za-z][A-Za-z -]*:/)) { addfile(nonote(l)); next }
      infiles = 0
      if (!match(l, /^[A-Za-z][A-Za-z -]*:/)) next
      k = K[tolower(trim(substr(l, 1, RLENGTH - 1)))]; v = trim(substr(l, RLENGTH + 1))
      if (k == "" || (k in SEEN)) next
      SEEN[k] = 1
      if (k == "files") { files(v); infiles = 1 }
      else if (k == "deliverable" || k == "progress" || k == "done") { v = path(v); if (v != "") print k "=" v }
      else if (k == "duration" || k == "cadence") { v = sentence(v); if (v != "") print k "=" v }
      else if (k == "suites") { v = suites(v); if (v != "") print "suites=" v }
      else if (k == "re_executes") { v = runs(v); if (v != "") print "re_executes=" v }
      else if (k == "questions") { v = questions(v); if (v != "") print "questions=" v }
      else if (k == "claims") { v = claims(v); if (v != "") print "claims=" v }
      else if (k == "lands_on") landson(v)
      else if (k == "row" || k == "red_evidence" || k == "kind") { v = word(v); if (v != "") print k "=" v }
      else { v = (k == "waiver" ? v : nonote(v)); gsub(/[ \t]+/, " ", v); if (v ~ /^`[^`]*`$/) v = substr(v, 2, length(v) - 2)
             if (v != "" && !slot(v)) print k "=" v }
    }
    END { if (F != "") print "files=" F }'
}

# brief_field <lines> <kind> -> the first `<kind>=` value of `brief_contract`'s lines, bounded as the roster row
# stores it. The list-valued fields are never cut: a 70-suite Suites: line runs to 1.8 KB, and a cut there would
# narrow a budget nobody agreed to (`sanitize`'s third argument exempts them).
brief_field() {
  local v
  v=$(printf '%s\n' "${1-}" | grep -m1 "^$2=" | cut -d= -f2-)
  case "$2" in
    questions|row)          sanitize "$v" 40 ;;
    lands_red|red_evidence) sanitize "$v" 300 ;;
    lands_on)               sanitize "$v" 900 suites_allowed ;;
    lands_on_reason)        sanitize "$v" 300 ;;
    files)                  sanitize "$v" 900 files ;;
    suites)                 sanitize "$v" 900 suites_allowed ;;
    re_executes)            sanitize "$v" 900 re_executes ;;
    *)                      printf '%s' "$v" ;;
  esac
}

# ---------- THE BRIEF FILE A DISPATCH NAMES ---------------------------------------------------------
#
# A brief is one file per dispatch, written by `session-poker.sh brief <row> <name>`. Its first line is
# the render's mark: the row and the name it was rendered for, and the sha256 of every line after the
# mark. The mark is the only place that sum lives before the dispatch, so an edit made after the render
# is read as a sum that differs, and the fix is always the same one: render again.
#
# The verb writes the mark (`brief_mark`) and the dispatch wall reads it back (`brief_file_read`), so
# the two cannot spell it two ways. A mark with no sum was written before the sum existed; such a file
# is rendered again, never trusted.
#
# THE PROMPT NAMES THE FILE ON ITS FIRST LINE, the whole line a path ending in `briefs/<name>.md`, with
# an optional `brief:` label and one pair of backticks. One fixed place, read by position: a path named
# further down is prose.

brief_sum() {  # <file> -> the sha256 of its lines after the first, 64 hex; rc 1 when no tool answers
  local s=""
  if command -v shasum >/dev/null 2>&1; then s="$(tail -n +2 "$1" 2>/dev/null | shasum -a 256 2>/dev/null)"
  elif command -v sha256sum >/dev/null 2>&1; then s="$(tail -n +2 "$1" 2>/dev/null | sha256sum 2>/dev/null)"
  fi
  s="${s%% *}"
  case "$s" in *[!0-9a-f]*|'') return 1 ;; esac
  [ "${#s}" -eq 64 ] || return 1
  printf '%s' "$s"
}

brief_mark() {  # <row> <name> <sum> -> the first line of a rendered brief
  printf '<!-- brief: rendered from row %s for %s; sum %s; render it again to change it, never edit it -->' "$1" "$2" "$3"
}

brief_named() {  # <prompt> -> the brief path its first non-blank line names, else nothing (rc 1)
  local l
  l="$(printf '%s\n' "$1" | awk 'NF { print; exit }')"
  l="${l#"${l%%[![:space:]]*}"}"; l="${l%"${l##*[![:space:]]}"}"
  case "$(printf '%s' "${l%%:*}" | tr '[:upper:]' '[:lower:]')" in
    brief|'brief file') l="${l#*:}"; l="${l#"${l%%[![:space:]]*}"}" ;;
  esac
  case "$l" in '`'*'`') l="${l#\`}"; l="${l%\`}" ;; esac
  case "$l" in *[[:space:]\`]*|'') return 1 ;; esac
  case "$l" in briefs/*.md|*/briefs/*.md) printf '%s' "$l" ;; *) return 1 ;; esac
}

# brief_file_read <root> <path as the prompt names it> -> sets, for the dispatch wall to judge:
#   BRIEF_FILE_STATE  ok | outside (not a plain file under <root>) | absent | unrendered (no mark) |
#                     unsummed (a mark with no sum) | edited (the sum differs) | unsummable (no tool)
#   BRIEF_FILE_REL    the path from <root>      BRIEF_FILE_ROW, BRIEF_FILE_NAME  what the mark names
#   BRIEF_FILE_SUM    the file's own sum        BRIEF_FILE_TEXT  its text, once the file is read
brief_file_read() {
  local root="$1" p="$2" f l1 rest declared
  BRIEF_FILE_STATE=""; BRIEF_FILE_REL=""; BRIEF_FILE_ROW=""; BRIEF_FILE_NAME=""; BRIEF_FILE_SUM=""; BRIEF_FILE_TEXT=""
  case "$p" in /*) f="$p" ;; *) f="$root/$p" ;; esac
  case "/$f/" in */../*|*/./*) BRIEF_FILE_STATE=outside; return 0 ;; esac
  case "$f" in "$root"/*) BRIEF_FILE_REL="${f#"$root"/}" ;; *) BRIEF_FILE_STATE=outside; return 0 ;; esac
  if [ -L "$f" ]; then BRIEF_FILE_STATE=outside; return 0; fi
  if [ ! -f "$f" ] || [ ! -r "$f" ]; then BRIEF_FILE_STATE=absent; return 0; fi
  BRIEF_FILE_TEXT="$(< "$f")"
  l1="${BRIEF_FILE_TEXT%%$'\n'*}"
  case "$l1" in '<!-- brief: rendered from row '*' for '*';'*) ;; *) BRIEF_FILE_STATE=unrendered; return 0 ;; esac
  rest="${l1#'<!-- brief: rendered from row '}"
  BRIEF_FILE_ROW="${rest%% *}"
  rest="${rest#* for }"; BRIEF_FILE_NAME="${rest%%;*}"
  case "$l1" in *'; sum '*) declared="${l1#*; sum }"; declared="${declared%%;*}" ;; *) BRIEF_FILE_STATE=unsummed; return 0 ;; esac
  BRIEF_FILE_SUM="$(brief_sum "$f")" || { BRIEF_FILE_STATE=unsummable; return 0; }
  if [ "$BRIEF_FILE_SUM" != "$declared" ]; then BRIEF_FILE_STATE=edited; return 0; fi
  BRIEF_FILE_STATE=ok
}
