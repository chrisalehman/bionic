#!/bin/bash
# one-reader-check.sh — what the one-reader rule names in a checkout, listed and counted.
#
#   bash one-reader-check.sh [<root>]      <root> defaults to the checkout this script sits in
#
# It reads every `*.sh` file under <root>/hooks and <root>/payload/scripts (symlinks not followed), and for
# names alone also every file under those two, every `*.sh` file under <root>/tests outside tests/fixtures/
# and the files of the loaded skill set, and prints one finding per line, `<kind>TAB<where>TAB<detail>`,
# then the ten counts, one `key=value` line each and always in this order, as the last ten lines:
#
#   parsers=<n>        files that parse a plan or a log, outside the reader's own files
#   plan_writers=<n>   files that write a plan
#   shared_types=<n>   event types appended by two or more functions
#   hook_refusals=<n>  refusal call sites inside a registered hook's own file
#   loader_copies=<n>  files holding a pasted copy of the loader block
#   unheard_folds=<n>  lines that take the run's fold or a reader answer and lose its exit
#   names=<n>          lines that name a retired verb, read by the shape of its use, a removed file or function,
#                      or a deleted plan section, and entries of KEPT_COPIES that admit no line
#   load_guards=<n>    hand-written load-once guards and self-dirs, beside lib/loader.sh `bionic_need`
#   git_homes=<n>      lines that look up the common git directory, beside lib/root.sh `git_common_dir`
#   field_readers=<n>  lines that read a record's field by a key they are handed, beside lib/fields.sh
#
# It refuses the counts REFUSING names, the one list of them: when one of those is above nought it prints
# one line for each of its findings on stderr, `one-reader-check: refused — <kind> <file>:<line>` (a shared
# type with its writers, a kept entry by the entry), and exits 1. A count off the list is reported and
# refuses nothing, so a count is turned on by adding its name there and nowhere else; tests/lib/lint.sh
# reads the refusals, so a count turned on here is turned on at a landing too. Exit 0 when no refusing
# count is above nought, 2 when <root> holds no hooks/ and payload/scripts/. A comment line, or the
# comment a function's line ends on, is never a parse, a write or a refusal; the loader's BEGIN marker
# is the one comment read, and a name is read in a comment as in code.
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
#     or a printed or put line starting `<shape>|ev=<type>`, not after a `^` (a search pattern); in a
#     reader's file (READER_FILES) a printed one is the reader's answer and counts only when the same
#     line appends it with `>>`. A type
#     named by a variable is listed as `?` and never paired. Two writers of one type are a `shared` finding.
#     A function whose `log_append` type is a variable is a PASS-THROUGH: a call of it, before or after its
#     definition, whose first argument that is no expansion is a ruled type (lib/log.sh LOG_TYPES, asked) makes
#     the calling function a writer of that type, so a second writer by that road is a shared type too.
#   - A REFUSAL is a refusal primitive called with its words (`refuse exit2|deny|block`, `fold_block`,
#     `dp_finding`, `patrol_deny`, `dp_not_checked`, `deny`, `block`) in a file hooks/hooks.json runs.
#   - A LOADER COPY is a file other than lib/loader.sh with the loader block's BEGIN marker.
#   - A LOAD GUARD is a source of a `*.sh` file under a marker of its own (`declare -F <name>`, or `[ -n` or
#     `[ -z` of a `${VAR:-}`): the marker on the same line, or on a line above that ends in `then`, `{`, `||`
#     or `&&` and whose block, by indent, holds the source. A SELF-DIR is a function named `…dir` that reads
#     BASH_SOURCE on its line or the next. Each is a copy of lib/loader.sh `bionic_need`, outside that file;
#     the one bootstrap line a library opens with, BOOT_LINE, is admitted when it is the whole line.
#   - A LOOKUP is a line naming the flag `git-common-di[r]`, outside lib/root.sh, the home of `git_common_dir`.
#   - A FIELD READER is, outside lib/fields.sh, an awk `index(<x>, <var> "=") == 1` whose key is a variable,
#     or a shell case arm `"$<var>="*)` opening at a field: the reading `line_kv` and `line_value` do. A key
#     spelt as a literal, or a word found between blanks, is none.
#   Those three are read in hooks/ and payload/scripts/ alone, never under tests/.
#   - AN UNHEARD FOLD is a line outside lib/proof.sh and the reader's files that calls _proof_facts,
#     _proof_ask, reader_main, reader_facts, reader_events or the reader program and pipes it, feeds a
#     process substitution, assigns it to a local, or takes it in a $( ) whose exit no `||`, `&&`,
#     `=$?` or `if` reads on that line: a fold that failed would read there as a run with no fact.
#   - A NAME is a line of names_standing below: a verb the poker no longer has, in the shape of a use where the word is
#     also English (the poker run with it, a function named for it, a poker case arm), else as its own word. The
#     plan reader's list of refused keys reads an older run by those names: that is no finding. A NAME is also a removed file's name as its own
#     word: the old landing record's and the asks register's (`landing[-]proofs.log`, `asks.stat[e]`), which a reader's
#     file (READER_FILES) reads an older run by and is admitted there, and the two deleted hook scripts'
#     (`stop[-]guard.sh`, `agent[-]context[-]guard.sh`) and the deleted act's (`bring[-]forward.sh`), admitted nowhere;
#     and, as its own word, a removed function's name or a verb's that is no English word and that no other pattern
#     reads whole. In the loaded set (walls.sh `loaded_set`, the net-zero wall's one definition, asked and never
#     restated) a NAME is also a deleted plan section, by its `##` heading or by the deletion list's words for it (`the
#     verificatio[n] matrix`), and nothing there is admitted, nor is anything under tests/. A pattern brackets a hyphen or a
#     letter (`[-]`, `[t]`) so that no name stands whole in this file: its own text matches none of them, and a word search of the tree for a name finds none here.
#
# THE READER'S FILES are named once, in READER_FILES: a parse inside one of them is the reader's own
# and is admitted. THE COPIES KEPT BY NAME are KEPT_COPIES, `<file>:<function>` each: a load guard, a self-dir,
# a lookup or a field reader inside that function is admitted, and an entry whose file is read and in which it
# admits nothing is a finding counted with the names, so the list cannot outlive its copy. A root that holds no
# file of an entry, a planted root or the lint's copy of a row's files, does not judge it. Nothing else is
# admitted, and no function may write a plan.
#
# Executed, never sourced; bash 3.2.

set -uo pipefail

READER_FILES="payload/scripts/lib/reader.sh payload/scripts/lib/plan-read.sh payload/scripts/lib/fields.sh"
# Each is an install root: the script finds its own folder before any library, the loader among them, is found.
KEPT_COPIES="payload/scripts/doctor.sh:_doctor_self_dir payload/scripts/setup.sh:_setup_self_dir payload/scripts/version.sh:_version_self_dir payload/scripts/close-out.sh:_co_self_dir"
REFUSING="parsers plan_writers shared_types loader_copies names"
# Built by printf, so that no line of this file is the bootstrap line or reads as a guard: each `|` and `.` is an argument.
BOOT_LINE="$(printf 'declare -F bionic_need >/dev/null 2>&1 %s%s case "${BASH_SOURCE[0]}" in */*) %s "${BASH_SOURCE[0]%%/*}/loader.sh" ;; *) %s ./loader.sh ;; esac' '|' '|' . .)"

case "${BASH_SOURCE[0]}" in */*) _orc_dir="${BASH_SOURCE[0]%/*}" ;; *) _orc_dir="." ;; esac
root="${1:-$(cd "$_orc_dir/../.." && pwd -P)}"
if [ ! -d "$root/hooks" ] || [ ! -d "$root/payload/scripts" ]; then
  printf 'one-reader-check: %s holds no hooks/ and payload/scripts/\n' "$root" >&2
  exit 2
fi
# The loaded set is the net-zero wall's, asked of the walls library beside this script and read in <root>.
loaded_members="$( . "$_orc_dir/lib/walls.sh" >/dev/null 2>&1 && loaded_set)"
if [ -z "$loaded_members" ]; then
  printf 'one-reader-check: %s/lib/walls.sh names no loaded set\n' "$_orc_dir" >&2
  exit 2
fi
# The ruled types are the log's closed list, asked of the appender beside this script as the loaded set is.
ruled_types="$( . "$_orc_dir/lib/log.sh" >/dev/null 2>&1 && printf '%s' "${LOG_TYPES:-}")"
case "$ruled_types" in *[a-z]*) ;; *) printf 'one-reader-check: %s/lib/log.sh names no event type\n' "$_orc_dir" >&2; exit 2 ;; esac
cd "$root" || exit 2

hook_files="$(/usr/bin/grep -o -E 'hooks/[A-Za-z0-9_.-]+\.sh' hooks/hooks.json 2>/dev/null | LC_ALL=C sort -u | tr '\n' ' ')"
files=()
while IFS= read -r f; do files+=("$f"); done < <(find hooks payload/scripts -type f -name '*.sh' | LC_ALL=C sort)
[ "${#files[@]}" -gt 0 ] || files=(/dev/null)
suite_files=(); loaded_files=()
while IFS= read -r f; do suite_files+=("$f"); done < <(find tests -type f -name '*.sh' ! -path 'tests/fixtures/*' 2>/dev/null | LC_ALL=C sort)
# Unquoted, so each member's `*` is expanded here, in <root>.
for f in $loaded_members; do [ -f "$f" ] && loaded_files+=("$f"); done

names_found() {  # <file or directory>... -> `<file>:<line>:<text>` for each line naming a retired verb, one line per search
  local g='anchor[s]|patro[l]|wai[t]|cove[r]|epic[-]row|continuation[-]fill|interval[-]default|windo[w]|fill[-]report|dispositio[n]'
  /usr/bin/grep -rnE 'launch[-]sync|ledger[-](add|set)|task[-](set|split)|tasks[-]prose|row[-_]landed|session-poker\.sh"? delive[r]|`delive[r]`|delive[r] <(row|id)>|^ *delive[r]\)' "$@"
  /usr/bin/grep -rnE 'matrix[-](set|retier|render)|waive[-]row|poker_verb_discharg[e]|discharg[e]\)|(session-poker\.sh|plan_verb_open|plan_verb_swa[p]|pv_next) discharg[e]' "$@"
  /usr/bin/grep -rnE "(session-poker\\.sh|\\\$\\{?[A-Za-z_]*(poker|POKER)[A-Za-z_]*\\}?)[\"']? ($g)([^a-z_-]|\$)|poker_verb_(${g//[-]/_})([^a-z_]|\$)" "$@"
  /usr/bin/grep -rnE --include='*poker*.sh' "^ *([a-z-]+\\|)*($g)(\\|[a-z-]+)*\\)" "$@"
  /usr/bin/grep -rnE 'step[-](line|field)|regressio[n][-]runs|regression_runs_coun[t]|units_set_curren[t]|units_step_(line|fields)|poker_verb_regressio[n]\b|\|budge[t]\||\|regressio[n]\|shar[e]\||confirm[-_]row|matrix_block_ke[y]|poker_verb_budge[t]|budge[t][-]override|session-poker\.sh"? budge[t]|^  budge[t]\)$' "$@" \
    | /usr/bin/grep -v -e 'PLAN_READ_GONE_KEYS='
  /usr/bin/grep -rnE '(^|[^A-Za-z0-9_])(landing[-]proofs\.log|asks\.stat[e])([^A-Za-z0-9_]|$)' "$@" \
    | awk -F: -v r=" $READER_FILES " '!index(r, " " $1 " ")'
  /usr/bin/grep -rnE '(^|[^A-Za-z0-9_])(stop[-]guard|agent[-]context[-]guard|bring[-]forward|translat[e])\.sh([^A-Za-z0-9_]|$)' "$@"
  /usr/bin/grep -rnE '(^|[^A-Za-z0-9_-])translat[e] +("[^"]*"|[$][^ ]*) +(events|gaps)([^A-Za-z0-9_]|$)|declare -F translat[e]([^A-Za-z0-9_]|$)' "$@"
  /usr/bin/grep -rnE '(^|[^A-Za-z0-9_])(plan_verb_swa[p]|plan_bring_forwar[d]|ensure_walk_pointe[r]|walk_pointer_wante[d]|lift_contract_field[s]|brief_validate_field[s]|brief_body_advisorie[s]|dp_scaffold_marke[d]|scale_branch_numbe[r]|units_step_fiel[d]|bf_mai[n]|matrix_bloc[k]|matrix_hea[d]|matrix_row_waive[r]|matrix_v1[5]|units_suspec[t]|suspect_line[s]|_units_dep_aw[k]|units_thread_row[s]|alias_gone_cel[l]|reader_brough[t]|reader_brought_a[t]|reader_landing_recor[d]|reader_sessio[n]|plan_read_droppe[d]|plan_read_block[s]|proof_debt_ledger_pat[h]|co_debt_gap[s]|co_debt_gaps_loa[d]|co_debt_note[s]|_run_translatio[n]|translate_has_stat[e]|translate_state_ke[y]|translate_ledge[r]|TRANSLATE_HOME[S]|finding[-]stated|continuation[-]fill|interval[-]default|fill[-]report)([^A-Za-z0-9_]|$)' "$@"
}

names_standing() {  # -> `<file>:<line>:<text>` for each line naming a retired verb or, in the loaded set, a deleted plan section
  {
    names_found hooks payload/scripts ${suite_files[@]+"${suite_files[@]}"} ${loaded_files[@]+"${loaded_files[@]}"}
    [ "${#loaded_files[@]}" -eq 0 ] || /usr/bin/grep -HniE \
      '[#][#] +(verification matri[x]|sdlc stat[e]|handof[f]|dispatch ledge[r])|the (verificatio[n] matrix|stat[e] section|handof[f] section|dispatc[h] ledger)' \
      "${loaded_files[@]}"
  } | LC_ALL=C sort -t: -k1,1 -k2,2n -u
}

# The patterns are written so that this file's own text matches none of them: `\/` and `[#]` stand
# where the grammar has a bare character, so the check never counts itself. Lines are read as bytes:
# the walk of a command a character at a time stops on a line that is no valid UTF-8.
NAMED="$(names_standing)" BOOT_LINE="$BOOT_LINE" LC_ALL=C awk -v q="'" -v admitted=" $READER_FILES " -v hooks=" $hook_files " -v ruled=" $ruled_types " \
  -v kept=" $KEPT_COPIES " -v refusing=" $REFUSING " '
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
  function writer(type, file, fnr, f) {
    if (type !~ /^[a-z][a-z-]*$/) type = "?"
    wl[++nw] = "writer\t" type "\t" file ":" fnr " " f
    if (type == "?") return
    id = file ":" f
    if (!((type, id) in seen)) {
      seen[type, id] = 1; nwr[type]++; ids[type] = ids[type] (ids[type] == "" ? "" : " ") id
      at[type] = at[type] (at[type] == "" ? "" : ", ") file ":" fnr " " f
      if (!(type in tseen)) { tseen[type] = 1; tord[++nt] = type }
    }
  }
  function rf(c) { return index(refusing, " " c " ") > 0 }  # 1 when count <c> refuses
  function copy(kind, cnt, where, detail, f,   k) {  # one copy of an idiom with a home, unless its function is kept
    k = FILENAME ":" f
    if (index(kept, " " k " ")) { kadm[k] = 1; return }
    ncp++; cpk[ncp] = kind; cpc[ncp] = cnt; cpw[ncp] = where; cpd[ncp] = detail; ncnt[cnt]++
  }
  function passed(s,   n, w, i, j, t) {  # the ruled type a call of a pass-through on line s hands it, or nothing
    n = split(s, w, /[ \t]+/)
    for (i = 1; i < n; i++) {
      t = w[i]; sub(/^[!({]*([$][(])?/, "", t)
      if (!(t in pass)) continue
      for (j = i + 1; j <= n; j++) {
        if (w[j] ~ /[;|&)]/) break
        t = w[j]; gsub(qt, "", t)
        if (t ~ /^[$]/) continue
        if (index(ruled, " " t " ")) return t
        break
      }
    }
    return ""
  }
  BEGIN { qt = "[\"" q "]"; nq = "[^\"" q "]"; rd = "(^|[^A-Za-z0-9_.-])(awk|sed|grep|cut|head|tail|cat) "
    rt = ruled; gsub(/^ +| +$/, "", rt); gsub(/ +/, "|", rt); rre = "[ \t]\"?(" rt ")\"?([ \t;)]|$)"
    known = "^[ \t{(!]*([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*[A-Za-z_/][A-Za-z0-9_/.-]*( |$)"
    boot = ENVIRON["BOOT_LINE"]; loader = "payload/scripts/lib/loader.sh"; rootlib = "payload/scripts/lib/root.sh"
    fieldslib = "payload/scripts/lib/fields.sh"
    srcre = "(^|[;&|(){!]|[ \t](then|do|else))[ \t]*([.]|source)[ \t]+[\"$/A-Za-z_.~].*[.]sh([\"" q " \t;)|&]|$)"
    markre = "declare -F [A-Za-z_]|[[][[]? +-[nz] +\"?[$][{][A-Za-z_][A-Za-z0-9_]*:-[}]\"? +[]]"
    awkkv = "index[(][^,()]+,[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*\"=\"[)][ \t]*==[ \t]*1"
    shkv = "(^|[ \t(])\"[$][{]?[A-Za-z_0-9]+[}]?=\"[*][)]"
    lg = "use bionic_need (" loader ")" }
  FNR == 1 { depth = 0; fn[0] = "-"; ind[0] = -1; gopen = 0; pend = ""; readf[FILENAME] = 1 }
  /^[#] --- bionic-loader\/v2 BEGIN/ && FILENAME != "payload/scripts/lib/loader.sh" { ll[++nl] = "loader\t" FILENAME "\t:" FNR }
  /^[ \t]*#/ { next }
  {
    line = $0; isdef = 0
    if (match(line, /^[ \t]*[A-Za-z_][A-Za-z0-9_:-]*[ \t]*\(\)[ \t]*(\{|\(|$)/)) {
      d = line; match(d, /^[ \t]*/); w = RLENGTH; sub(/^[ \t]*/, "", d); sub(/[ \t]*\(.*/, "", d)
      fn[++depth] = d; ind[depth] = w; isdef = 1
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

    # A call of the loader that names the appender as the marker it waits for writes no event: it is cut before the
    # writer rule reads the line, so a call of the appender after it is still read.
    wln = line; gsub(/bionic_need +[^ ;|&]+ +[A-Za-z_][A-Za-z0-9_]*/, "", wln)
    if (wln !~ /declare -F/ && match(wln, /(^|[^A-Za-z0-9_])(log_append|line_event) +[^ ]/)) {
      r = substr(wln, RSTART + RLENGTH - 1); split(r, a, /[ \t]+/)
      t = (wln ~ /log_append/) ? a[1] : a[2]; gsub(/"/, "", t); writer(t, FILENAME, FNR, fn[depth])
      if (t ~ /^[$]/ && fn[depth] != "-") pass[fn[depth]] = 1
    } else if (line ~ rre) { cl[++nc] = line; cf[nc] = FILENAME; cn[nc] = FNR; cfn[nc] = fn[depth] }
    if (match(line, /(^|[^A-Za-z0-9_^-])(line|run|owed)\/v1[|]ev=[a-z][a-z-]*/) && line ~ (index(admitted, " " FILENAME " ") ? ">>" : "_wt_proofs_put|printf|echo|>>")) {  # after ^ it is a pattern; in a reader file a printed one is an answer
      t = substr(line, RSTART, RLENGTH); sub(/.*ev=/, "", t); writer(t, FILENAME, FNR, fn[depth])
    }

    if (index(hooks, " " FILENAME " ") && line !~ /\(\)[ \t]*\{/ && \
        match(line, /(^|[^_[:alnum:]])(refuse (exit2|deny|block|"\$[_[:alnum:]]+") |fold_block |(dp_finding|patrol_deny|dp_not_checked|deny|block) ["$])/)) {
      p = substr(line, RSTART, RLENGTH); sub(/^[^_[:alnum:]]/, "", p); sub(/ .*/, "", p)
      rl[++nr] = "refusal\t" FILENAME ":" FNR "\t" p
    }

    # The idioms with a home elsewhere. A guard block is the lines under its marker line indented past it; a blank
    # line neither opens nor closes one.
    if (line !~ /[^ \t]/) next
    match(line, /^[ \t]*/); w = RLENGTH; wh = FILENAME ":" FNR
    inblk = gopen && w > gind; if (!inblk) gopen = 0
    if (pend != "") { if (line ~ /BASH_SOURCE/) copy("load-guard", "load_guards", FILENAME ":" pendn, "self-dir " pend ": " lg, pend); pend = "" }
    if (FILENAME != loader && line != boot) {
      if (line ~ srcre && (inblk || line ~ markre)) copy("load-guard", "load_guards", wh, "guard: " lg, fn[depth])
      if (!gopen && line ~ markre && line ~ /(then|[{]|[|][|]|&&)[ \t]*$/) { gopen = 1; gind = w }
      if (isdef && d ~ /dir$/) {
        if (line ~ /BASH_SOURCE/) copy("load-guard", "load_guards", wh, "self-dir " d ": " lg, d)
        else if (line ~ /[{][ \t]*$/) { pend = d; pendn = FNR }
      }
    }
    if (FILENAME != rootlib && line ~ /git-common-di[r]/) copy("git-home", "git_homes", wh, "lookup: use git_common_dir (" rootlib ")", fn[depth])
    if (FILENAME != fieldslib) {
      if (line ~ awkkv) copy("field-reader", "field_readers", wh, "awk reader: use line_kv (" fieldslib ")", fn[depth])
      else if (line ~ shkv) copy("field-reader", "field_readers", wh, "shell reader: use line_value (" fieldslib ")", fn[depth])
    }
  }
  END {
    r = "one-reader-check: refused — "; e = "/dev/stderr"
    nn = split(ENVIRON["NAMED"], nm, "\n")
    for (i = 1; i <= nc; i++) if ((t = passed(cl[i])) != "") writer(t, cf[i], cn[i], cfn[i])
    for (i = 1; i <= np; i++) { printf "parser\t%s\tsites=%d first=%d\n", pord[i], pn[pord[i]], pfirst[pord[i]]; if (rf("parsers")) print r "parser " pord[i] ":" pfirst[pord[i]] > e }
    for (i = 1; i <= npw; i++) { printf "plan-writer\t%s\tsites=%d first=%d\n", word[i], wn[word[i]], wfirst[word[i]]; if (rf("plan_writers")) print r "plan-writer " word[i] ":" wfirst[word[i]] > e }
    for (i = 1; i <= nw; i++) print wl[i]
    for (i = 1; i <= nt; i++) if (nwr[tord[i]] > 1) { print "shared\t" tord[i] "\t" ids[tord[i]]; if (rf("shared_types")) print r "shared " tord[i] " " at[tord[i]] > e; ns++ }
    for (i = 1; i <= nr; i++) { print rl[i]; split(rl[i], x, "\t"); if (rf("hook_refusals")) print r "refusal " x[2] > e }
    for (i = 1; i <= nl; i++) { print ll[i]; split(ll[i], x, "\t"); if (rf("loader_copies")) print r "loader " x[2] x[3] > e }
    for (i = 1; i <= nu; i++) { print ul[i]; split(ul[i], x, "\t"); if (rf("unheard_folds")) print r "unheard " x[2] > e }
    for (i = 1; i <= nn; i++) { split(nm[i], f, ":"); t = nm[i]; sub(/^[^:]*:[^:]*:[ \t]*/, "", t)
      print "name\t" f[1] ":" f[2] "\t" t; if (rf("names")) print r "name " f[1] ":" f[2] > e }
    nk = split(kept, ke, " ")
    for (i = 1; i <= nk; i++) { t = ke[i]; sub(/:[^:]*$/, "", t)
      if ((t in readf) && !(ke[i] in kadm)) { print "kept\t" ke[i] "\tadmits no line"; nn++; if (rf("names")) print r "kept " ke[i] > e } }
    for (i = 1; i <= ncp; i++) { print cpk[i] "\t" cpw[i] "\t" cpd[i]; if (rf(cpc[i])) print r cpk[i] " " cpw[i] > e }
    printf "parsers=%d\nplan_writers=%d\nshared_types=%d\nhook_refusals=%d\nloader_copies=%d\nunheard_folds=%d\nnames=%d\n", np, npw, ns, nr, nl, nu, nn
    printf "load_guards=%d\ngit_homes=%d\nfield_readers=%d\n", ncnt["load_guards"], ncnt["git_homes"], ncnt["field_readers"]
    c["parsers"] = np; c["plan_writers"] = npw; c["shared_types"] = ns; c["hook_refusals"] = nr; c["loader_copies"] = nl
    c["unheard_folds"] = nu; c["names"] = nn; c["load_guards"] = ncnt["load_guards"]; c["git_homes"] = ncnt["git_homes"]
    c["field_readers"] = ncnt["field_readers"]; n = split(refusing, x, " "); bad = 0
    for (i = 1; i <= n; i++) bad += c[x[i]]
    exit (bad > 0)
  }' "${files[@]}"
