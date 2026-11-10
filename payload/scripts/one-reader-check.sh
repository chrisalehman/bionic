#!/bin/bash
# one-reader-check.sh — what the one-reader rule names in a checkout, listed and counted.
#
#   bash one-reader-check.sh [<root>]      <root> defaults to the checkout this script sits in
#
# It reads every `*.sh` file under <root>/hooks and <root>/payload/scripts (symlinks not followed) and
# prints one finding per line, `<kind>TAB<where>TAB<detail>`, then the five counts, one `key=value`
# line each and always in this order, as the last five lines:
#
#   parsers=<n>        files that parse a plan or a log, outside the reader's own files
#   plan_writers=<n>   files that write a plan
#   shared_types=<n>   event types appended by two or more functions
#   hook_refusals=<n>  refusal call sites inside a registered hook's own file
#   loader_copies=<n>  files holding a pasted copy of the loader block
#
# It reports and refuses nothing: exit 0 whatever it finds, 2 when <root> holds no hooks/ and
# payload/scripts/. A comment line is never a parse, a write or a refusal; the loader's BEGIN marker
# is the one comment read.
#
# THE DEFINITIONS, each a property of one line, so a finding names the line that makes it:
#   - A PARSE names a plan's or a log's grammar (the plan's `SDLC State`, `Verification Matrix` or
#     `Tasks` section heading, however its `##` gap is spelt, or a record line shape `line/v1`, `owed/v1`, `run/v1` in any form but the `<shape>|ev=`
#     a writer starts its line with), or hands a plan or a log to a text reader: a plan or log
#     operand after awk, sed, grep, cut, head, tail or cat; right after the closing quote of a
#     program (`' "$plan"`) on a line that is not a printf or an echo; or as the input of a
#     `while read` loop.
#   - A PLAN OPERAND is a variable whose name holds `plan` or `PLAN` and does not end in dir, root or
#     an `s` (a directory or a list of plans); `PV_NEW`, the session-poker's working copy it installs
#     over the plan; or a quoted path ending `.plan.md`. A LOG OPERAND is `RUN_LOG` or a path ending
#     `run.log`.
#   - A PLAN WRITE puts a plan operand where a write lands: after `>` or `>>`, as the destination of
#     mv or cp, after tee, or after `sed -i`.
#   - AN EVENT WRITER is the function holding a `log_append <type>` or `line_event <plan> <type>` call,
#     or a printed or put line starting `<shape>|ev=<type>`. A type named by a variable is listed
#     as `?` and never paired. Two writers of one type are a `shared` finding.
#   - A REFUSAL is a refusal primitive called with its words (`refuse exit2|deny|block`, `fold_block`,
#     `dp_finding`, `patrol_deny`, `dp_not_checked`, `deny`, `block`) in a file hooks/hooks.json runs.
#   - A LOADER COPY is a file other than lib/loader.sh with the loader block's BEGIN marker.
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
# where the grammar has a bare character, so the check never counts itself.
awk -v q="'" -v admitted=" $READER_FILES " -v hooks=" $hook_files " '
  function opname(s) {  # one operand token -> 1 when it names a plan or a log
    if (s ~ /\.plan\.md"?$/ || s ~ /run\.log"?$/) return 1
    gsub(/["${}]/, "", s)
    if (s == "PV_NEW" || s == "RUN_LOG") return 1
    if (s !~ /[Pp]lan|PLAN/) return 0
    return s !~ /([Dd]ir|DIR|[Rr]oot|ROOT|[sS])$/
  }
  function scan(s, pre, rest, tok) {  # sets nread and nwrite: operands this line reads and writes
    nread = 0; nwrite = 0
    rest = s
    while (match(rest, /"?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"?|"[^"$]*\$[^"]*(\.plan\.md|run\.log)"/)) {
      tok = substr(rest, RSTART, RLENGTH); pre = pre substr(rest, 1, RSTART - 1)
      rest = substr(rest, RSTART + RLENGTH)
      if (rest != "" && rest !~ /^[ \t;)|&]/) { pre = pre tok; continue }
      if (pre !~ /=$/ && opname(tok)) {
        if (pre ~ /(^|[^0-9<&])>>? *$/ || pre ~ /(^|[^A-Za-z0-9_-])(mv|cp)( +-[A-Za-z]+)* +[^ ;|&]+ +$/ \
            || pre ~ /(^|[^A-Za-z0-9_-])tee( +-a)? +$/ || pre ~ /(^|[^A-Za-z0-9_-])sed +-i/) nwrite++
        else if (pre ~ /(^|[^A-Za-z0-9_.-])(awk|sed|grep|cut|head|tail|cat) / || \
                 (pre ~ (q " *$") && s !~ /(^|[^A-Za-z0-9_])(printf|echo) /) || \
                 (pre ~ /(^|[^<])< *$/ && s ~ /(^|[^A-Za-z0-9_])(done|read) /)) nread++
      }
      pre = pre tok
    }
  }
  function grammar(s) {
    gsub(/(line|owed|run)\/v1[|]ev=/, "", s)
    return s ~ /(^|[^A-Za-z0-9_-])(line|owed|run)\/v1/ || s ~ /[#][#](\[\[:space:\]\][+*]?|\\s[+*]?|[ \t+*])+(SDLC State|Verification Matrix|Tasks)/
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
  FNR == 1 { depth = 0; fn[0] = "-"; ind[0] = -1 }
  /^[#] --- bionic-loader\/v2 BEGIN/ && FILENAME != "payload/scripts/lib/loader.sh" { ll[++nl] = "loader\t" FILENAME "\t:" FNR }
  /^[ \t]*#/ { next }
  {
    line = $0
    if (match(line, /^[ \t]*[A-Za-z_][A-Za-z0-9_:-]*[ \t]*\(\)[ \t]*(\{|\(|$)/)) {
      d = line; match(d, /^[ \t]*/); w = RLENGTH; sub(/^[ \t]*/, "", d); sub(/[ \t]*\(.*/, "", d)
      fn[++depth] = d; ind[depth] = w
    } else if (depth > 0 && match(line, /^[ \t]*\}/) && RLENGTH - 1 == ind[depth]) depth--

    scan(line)
    if (!(index(admitted, " " FILENAME " ")) && (nread || grammar(line))) {
      if (!(FILENAME in pfirst)) { pfirst[FILENAME] = FNR; pord[++np] = FILENAME }
      pn[FILENAME]++
    }
    if (nwrite) {
      if (!(FILENAME in wfirst)) { wfirst[FILENAME] = FNR; word[++npw] = FILENAME }
      wn[FILENAME]++
    }

    if (line !~ /declare -F/ && match(line, /(^|[^A-Za-z0-9_])(log_append|line_event) +[^ ]/)) {
      r = substr(line, RSTART + RLENGTH - 1); split(r, a, /[ \t]+/)
      t = (line ~ /log_append/) ? a[1] : a[2]; gsub(/"/, "", t); writer(t)
    }
    if (match(line, /(^|[^A-Za-z0-9_-])(line|run|owed)\/v1[|]ev=[a-z][a-z-]*/) && line ~ /_wt_proofs_put|printf|echo|>>/) {
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
    printf "parsers=%d\nplan_writers=%d\nshared_types=%d\nhook_refusals=%d\nloader_copies=%d\n", np, npw, ns, nr, nl
  }' "${files[@]}"
exit 0
