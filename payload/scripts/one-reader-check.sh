#!/bin/bash
# one-reader-check.sh — what the one-reader rule names in a checkout, listed and counted.
#
#   bash one-reader-check.sh [<root>]      <root> defaults to the checkout this script sits in
#
# It reads every `*.sh` file under <root>/hooks and <root>/payload/scripts (symlinks not followed) and
# prints one finding per line, `<kind>TAB<where>TAB<detail>`, then the six counts, one `key=value`
# line each and always in this order, as the last six lines:
#
#   parsers=<n>        files that parse a plan or a log, outside the reader's own files
#   plan_writers=<n>   files that write a plan
#   shared_types=<n>   event types appended by two or more functions
#   hook_refusals=<n>  refusal call sites inside a registered hook's own file
#   loader_copies=<n>  files holding a pasted copy of the loader block
#   unheard_folds=<n>  lines that take the run's fold or a reader answer and lose its exit
#
# It reports and refuses nothing: exit 0 whatever it finds, 2 when <root> holds no hooks/ and
# payload/scripts/. A comment line, or the comment a function's line ends on, is never a parse, a
# write or a refusal; the loader's BEGIN marker is the one comment read.
#
# THE DEFINITIONS, each a property of one line, so a finding names the line that makes it. A line's
# COMMAND, for an operand or a pattern, is the text from the last `|`, `;` or `&` before it, or from
# the `$(` or `<(` it sits in, quotes kept whole.
#   - A PARSE names a plan's or a log's grammar, or hands a plan or a log to a text reader.
#     The grammar is a section heading (`SDLC State`, `Verification Matrix`, `Tasks`) matched against
#     input: its `##` gap spelt as a pattern, inside `/…/` or after `^`, after awk, sed, grep or case on
#     its line, compared by `==`, `!=`, `~`, ` =`, index or match, a case arm, or alone in a string a
#     command or an assignment takes. A heading in any other words (a message, a print) is none.
#     The grammar is also a record line shape `line/v1`, `owed/v1`, `run/v1`, but not the `<shape>|ev=`
#     a writer starts its line with and not in the words a printf, echo or print starts with.
#     A text reader takes a plan or log operand when awk, sed, grep, cut, head, tail or cat is in the
#     operand's own command. When that command does not begin on the line (the line opens with a
#     program's end, or the operand follows a quote still open), a reader anywhere before it counts, or a
#     program's closing quote right before it (`' "$plan"`) on a line that is not a printf or an echo.
#     So does an operand that is the input of a `while read` loop.
#   - A PLAN OPERAND is a variable whose name holds `plan` or `PLAN` and does not end in dir, root or
#     an `s` (a directory or a list of plans); `PV_NEW`, the session-poker's working copy it installs
#     over the plan; or a quoted path ending `.plan.md`. A LOG OPERAND is `RUN_LOG` or a path ending
#     `run.log`.
#   - A PLAN WRITE puts a plan operand, never a log one, where a write lands in its own command: after
#     `>` or `>>`, as the destination of mv or cp (a flag is no source), after tee, or after `sed -i`.
#   - AN EVENT WRITER is the function holding a `log_append <type>` or `line_event <plan> <type>` call,
#     or a printed or put line starting `<shape>|ev=<type>`, not after a `^` (a search pattern). A type
#     named by a variable is listed as `?` and never paired. Two writers of one type are a `shared` finding.
#   - A REFUSAL is a refusal primitive called with its words (`refuse exit2|deny|block`, `fold_block`,
#     `dp_finding`, `patrol_deny`, `dp_not_checked`, `deny`, `block`) in a file hooks/hooks.json runs.
#   - A LOADER COPY is a file other than lib/loader.sh with the loader block's BEGIN marker.
#   - AN UNHEARD FOLD is a line outside lib/proof.sh and the reader's files that calls _proof_facts,
#     _proof_ask, reader_main, reader_facts, reader_events or the reader program and pipes it, feeds a
#     process substitution, assigns it to a local, or takes it in a $( ) whose exit no `||`, `&&`,
#     `=$?` or `if` reads on that line: a fold that failed would read there as a run with no fact.
#
# THE READER'S FILES are named once, in READER_FILES: a parse inside one of them is the reader's own
# and is admitted. Nothing else is admitted.
#
# Executed, never sourced; bash 3.2.

set -uo pipefail

READER_FILES="payload/scripts/lib/reader.sh payload/scripts/lib/plan-read.sh payload/scripts/lib/translate.sh"

case "${BASH_SOURCE[0]}" in */*) _orc_dir="${BASH_SOURCE[0]%/*}" ;; *) _orc_dir="." ;; esac
root="${1:-$(cd "$_orc_dir/../.." && pwd -P)}"
if [ ! -d "$root/hooks" ] || [ ! -d "$root/payload/scripts" ]; then
  printf 'one-reader-check: %s holds no hooks/ and payload/scripts/\n' "$root" >&2
  exit 2
fi
cd "$root" || exit 2

hook_files="$(/usr/bin/grep -o -E 'hooks/[A-Za-z0-9_.-]+\.sh' hooks/hooks.json 2>/dev/null | LC_ALL=C sort -u | tr '\n' ' ')"
files=()
while IFS= read -r f; do files+=("$f"); done < <(find hooks payload/scripts -type f -name '*.sh' | LC_ALL=C sort)

# The patterns are written so that this file's own text matches none of them: `\/` and `[#]` stand
# where the grammar has a bare character, so the check never counts itself. Lines are read as bytes:
# the walk of a command a character at a time stops on a line that is no valid UTF-8.
LC_ALL=C awk -v q="'" -v admitted=" $READER_FILES " -v hooks=" $hook_files " '
  function opname(s) {  # one operand token -> 1 when it names a plan, 2 a log
    if (s ~ /\.plan\.md"?$/) return 1
    if (s ~ /run\.log"?$/) return 2
    gsub(/["${}]/, "", s)
    if (s == "PV_NEW") return 1
    if (s == "RUN_LOG") return 2
    if (s !~ /[Pp]lan|PLAN/) return 0
    return s !~ /([Dd]ir|DIR|[Rr]oot|ROOT|[sS])$/
  }
  function cmdseg(s,   i, c, top, st, beg) {  # the command the end of s sits in; QS is 1 when that is a single quote
    top = 0; st[0] = 0; beg[0] = 1
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (st[top] == 1) { if (c == q) st[top] = 0; continue }
      if (c == "\\") { i++; continue }
      if ((c == "$" || (st[top] == 0 && c == "<")) && substr(s, i + 1, 1) == "(") { st[++top] = 0; beg[top] = i + 2; i++; continue }
      if (st[top] == 2) { if (c == "\"") st[top] = 0; continue }
      if (c == q) st[top] = 1; else if (c == "\"") st[top] = 2
      else if (c == ")" && top > 0) top--; else if (c ~ /[|;&]/) beg[top] = i + 1
    }
    QS = st[top]; return SEG = substr(s, beg[top])
  }
  function scan(s, pre, rest, tok, o) {  # sets nread and nwrite: operands this line reads and writes
    nread = 0; nwrite = 0
    rest = s
    while (match(rest, /"?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"?|"[^"$]*\$[^"]*(\.plan\.md|run\.log)"/)) {
      tok = substr(rest, RSTART, RLENGTH); pre = pre substr(rest, 1, RSTART - 1)
      rest = substr(rest, RSTART + RLENGTH)
      if (rest != "" && rest !~ /^[ \t;)|&]/) { pre = pre tok; continue }
      if (pre !~ /=$/ && (o = opname(tok))) {  # a write is of a plan, judged in the command the operand sits in
        if (o == 1 && (cmdseg(pre) ~ /(^|[^0-9<&])>>? *$/ || SEG ~ /(^|[^A-Za-z0-9_-])(mv|cp)( +-[A-Za-z]+)* +[^ ;|&-][^ ;|&]* +$/ \
            || SEG ~ /(^|[^A-Za-z0-9_-])tee( +-a)? +$/ || SEG ~ /(^|[^A-Za-z0-9_-])sed +-i/)) nwrite++
        else if (cmdseg(pre) ~ rd || ((SEG !~ known || QS == 1) && (pre ~ rd || (pre ~ (q " *$") && s !~ /(^|[^A-Za-z0-9_])(printf|echo) /))) || \
                 (pre ~ /(^|[^<])< *$/ && s ~ /(^|[^A-Za-z0-9_])(done|read) /)) nread++
      }
      pre = pre tok
    }
  }
  function grammar(s,   t, pre, b) {  # a shape counts unless it is in the words a print starts with
    gsub(/(line|owed|run)\/v1[|]ev=/, "", s); t = s
    while (match(t, /(^|[^A-Za-z0-9_-])(line|owed|run)\/v1/)) {
      pre = pre substr(t, 1, RSTART); t = substr(t, RSTART + RLENGTH); b = pre; sub(qt nq "*$", "", b)
      if (pre !~ (qt nq "*$") || b !~ /(printf|echo|print)( +-[-a-z]*)* *$/) return 1
    }
    return heading(s)
  }
  function heading(s,   pre, hd, b) {  # 1 when a section heading on the line is matched against input, not words
    while (match(s, /[#][#](\[\[:space:\]\][+*]?|\\s[+*]?|[ \t+*])+(SDLC State|Verification Matrix|Tasks)/)) {
      hd = substr(s, RSTART, RLENGTH); pre = pre substr(s, 1, RSTART - 1); s = substr(s, RSTART + RLENGTH)
      b = pre; sub(qt nq "*$", "", b)
      if (hd !~ /^[#][#] [A-Z]/ || pre ~ /[\/^][^ ]*$/ || pre ~ /(^|[^A-Za-z0-9_.-])(awk|sed|grep|case) / \
          || b ~ /(==|!=|~|[ \t]=|(index|match)\([^)]*) *$/ || s ~ ("^" qt "?[*]?[)]") \
          || (pre ~ (qt "$") && s ~ ("^[$]?" qt) && b ~ /(^[ \t]*[A-Za-z_][A-Za-z0-9_]* +|[=(]) *$/ && b !~ /(print|printf|echo) *$/)) return 1
      pre = pre hd
    }
    return 0
  }
  function unheard(s,   seen, pre, post, cut) {  # 1 when the line takes the fold or a reader answer with its exit lost
    while (match(s, /(^|[^A-Za-z0-9_-])([_]proof_facts|[_]proof_ask|reader[_]main|reader[_]facts|reader[_]events)([^A-Za-z0-9_(-]|$)|(bas[h]|s[h])( +-[a-z]+)* +"?[^ |;&]*(reader[.]sh|READE[R]\}?)"?([^A-Za-z0-9_]|$)/)) {
      pre = seen substr(s, 1, RSTART); post = substr(s, RSTART + RLENGTH - 1)
      seen = seen substr(s, 1, RSTART + RLENGTH - 1); s = substr(s, RSTART + RLENGTH - 1)
      if (pre ~ /(declare|typeset) +-[fF] *.?$|command +-v *.?$/) continue
      cut = post; sub(/(;|\|\||&&).*/, "", cut)
      if (cut ~ /(^|[^|])[|]([^|]|$)/ || pre ~ /<\(/) return 1
      if (pre !~ /\$\(/) continue
      if (pre ~ /(^|[^A-Za-z0-9_])(local|export|readonly|declare|typeset)( +-[A-Za-z]+)* +[A-Za-z_][A-Za-z0-9_]*=/) return 1
      if (pre ~ /^[ \t]*(if|elif|while|until|!)[ \t]/ || post ~ /(\|\||&&)|=\$\?/) continue
      return 1
    }
    return 0
  }
  function writer(type) {
    if (type !~ /^[a-z][a-z-]*$/) type = "?"
    wl[++nw] = "writer\t" type "\t" FILENAME ":" FNR " " fn[depth]
    if (type == "?") return
    id = FILENAME ":" fn[depth]
    if (!((type, id) in seen)) {
      seen[type, id] = 1; nwr[type]++; ids[type] = ids[type] (ids[type] == "" ? "" : " ") id
      if (!(type in tseen)) { tseen[type] = 1; tord[++nt] = type }
    }
  }
  BEGIN { qt = "[\"" q "]"; nq = "[^\"" q "]"; rd = "(^|[^A-Za-z0-9_.-])(awk|sed|grep|cut|head|tail|cat) "
    known = "^[ \t{(!]*([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*[A-Za-z_/][A-Za-z0-9_/.-]*( |$)" }
  FNR == 1 { depth = 0; fn[0] = "-"; ind[0] = -1 }
  /^[#] --- bionic-loader\/v2 BEGIN/ && FILENAME != "payload/scripts/lib/loader.sh" { ll[++nl] = "loader\t" FILENAME "\t:" FNR }
  /^[ \t]*#/ { next }
  {
    line = $0
    if (match(line, /^[ \t]*[A-Za-z_][A-Za-z0-9_:-]*[ \t]*\(\)[ \t]*(\{|\(|$)/)) {
      d = line; match(d, /^[ \t]*/); w = RLENGTH; sub(/^[ \t]*/, "", d); sub(/[ \t]*\(.*/, "", d)
      fn[++depth] = d; ind[depth] = w
      if (match(line, /^[^{]*\{[ \t]+[#]/)) line = substr(line, 1, RLENGTH - 1)  # the comment a function line ends on
    } else if (depth > 0 && match(line, /^[ \t]*\}/) && RLENGTH - 1 == ind[depth]) depth--

    scan(line)
    if (!(index(admitted, " " FILENAME " ")) && (nread || grammar(line))) {
      if (!(FILENAME in pfirst)) { pfirst[FILENAME] = FNR; pord[++np] = FILENAME }
      pn[FILENAME]++
    }
    if (!(index(admitted, " " FILENAME " ")) && FILENAME != "payload/scripts/lib/proof.sh" && unheard(line)) ul[++nu] = "unheard\t" FILENAME ":" FNR
    if (nwrite) {
      if (!(FILENAME in wfirst)) { wfirst[FILENAME] = FNR; word[++npw] = FILENAME }
      wn[FILENAME]++
    }

    if (line !~ /declare -F/ && match(line, /(^|[^A-Za-z0-9_])(log_append|line_event) +[^ ]/)) {
      r = substr(line, RSTART + RLENGTH - 1); split(r, a, /[ \t]+/)
      t = (line ~ /log_append/) ? a[1] : a[2]; gsub(/"/, "", t); writer(t)
    }
    if (match(line, /(^|[^A-Za-z0-9_^-])(line|run|owed)\/v1[|]ev=[a-z][a-z-]*/) && line ~ /_wt_proofs_put|printf|echo|>>/) {  # after ^ it is a pattern
      t = substr(line, RSTART, RLENGTH); sub(/.*ev=/, "", t); writer(t)
    }

    if (index(hooks, " " FILENAME " ") && line !~ /\(\)[ \t]*\{/ && \
        match(line, /(^|[^_[:alnum:]])(refuse (exit2|deny|block|"\$[_[:alnum:]]+") |fold_block |(dp_finding|patrol_deny|dp_not_checked|deny|block) ["$])/)) {
      p = substr(line, RSTART, RLENGTH); sub(/^[^_[:alnum:]]/, "", p); sub(/ .*/, "", p)
      rl[++nr] = "refusal\t" FILENAME ":" FNR "\t" p
    }
  }
  END {
    for (i = 1; i <= np; i++) printf "parser\t%s\tsites=%d first=%d\n", pord[i], pn[pord[i]], pfirst[pord[i]]
    for (i = 1; i <= npw; i++) printf "plan-writer\t%s\tsites=%d first=%d\n", word[i], wn[word[i]], wfirst[word[i]]
    for (i = 1; i <= nw; i++) print wl[i]
    for (i = 1; i <= nt; i++) if (nwr[tord[i]] > 1) { print "shared\t" tord[i] "\t" ids[tord[i]]; ns++ }
    for (i = 1; i <= nr; i++) print rl[i]
    for (i = 1; i <= nl; i++) print ll[i]
    for (i = 1; i <= nu; i++) print ul[i]
    printf "parsers=%d\nplan_writers=%d\nshared_types=%d\nhook_refusals=%d\nloader_copies=%d\nunheard_folds=%d\n", np, npw, ns, nr, nl, nu
  }' "${files[@]}"
exit 0
