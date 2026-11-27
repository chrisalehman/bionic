#!/bin/bash
# payload/scripts/lib/fields.sh — THE RECORD'S FIELD READER, the reader's: the one reading of a line the log's appender
# writes. The landing library and the reader's library each source it from their own directory, so a script that loads
# either reads a line's fields the same way. It is awk functions a program prefixes and runs with -F'|'. Every field is
# read by its name, never by its place, so a field the writer adds or moves is still read; the first `<key>=` of a line
# is its value. The body reads any line whose fields are split by FS, so a caller that also splits on a blank reads by name.
#   line_ev()       the line's event (`ev=`), or nothing on a line that is neither `line/v1|` nor `run/v1|`
#   line_kv(k)      the value of the line's field <k>, or nothing
#   line_kv_of(l,k) the same of a line <l> held in a variable, split on `|`
# The awk readers skip the first field, the line's shape. A shell caller holding one line asks `line_field`, and a
# writer folds a value onto one field with `line_field_clean`. bash 3.2.
_LINE_FIELDS_AWK='
function line_kv(k,   i) { for (i = 2; i <= NF; i++) if (index($i, k "=") == 1) return substr($i, length(k) + 2); return "" }
function line_kv_of(l, k,   i, n, p) { n = split(l, p, "|"); for (i = 2; i <= n; i++) if (index(p[i], k "=") == 1) return substr(p[i], length(k) + 2); return "" }
function line_ev() { return (substr($0, 1, 8) == "line/v1|" || substr($0, 1, 7) == "run/v1|") ? line_kv("ev") : "" }
'
line_value() {  # <one record line> <key> -> the value of its field <key>, through line_kv
  printf '%s\n' "$1" | awk -F'|' -v k="$2" "$_LINE_FIELDS_AWK"'{ print line_kv(k); exit }'
}

# THE SHELL READER, in builtins so a caller reading a field per line starts no process. It walks every field, the first
# too, and a newline breaks a field as `|` does. `line_field_v` sets the named variable, empty and status 1 on a miss;
# `line_field` prints the value and a newline, or nothing on a miss, and returns 0.
line_field_v() {  # <var> <line> <key>; status 1 when no field carries <key>
  local _lfv_rest="${2:-}" _lfv_f _lfv_nl=$'\n'
  _lfv_rest="${_lfv_rest//$_lfv_nl/|}|"
  while [ -n "$_lfv_rest" ]; do
    _lfv_f="${_lfv_rest%%|*}"; _lfv_rest="${_lfv_rest#*|}"
    case "$_lfv_f" in "${3}="*) printf -v "$1" '%s' "${_lfv_f#"${3}="}"; return 0 ;; esac
  done
  printf -v "$1" '%s' ''
  return 1
}
line_field() {  # <line> <key> -> the value of its field <key>
  local _lf_v
  line_field_v _lf_v "${1:-}" "${2:-}" && printf '%s\n' "$_lf_v"
  return 0
}

# THE WRITER'S SIDE OF THE SAME FIELD. A value bound for a `|`-split line would forge a field with a `|` and a line
# with a newline, so it is folded, never refused (a writer records what it saw): newline, return, tab, `|` and every
# other control character become a space, runs of spaces one, the ends are trimmed, and with <max> only its first
# <max> characters are kept. A cleaner that keeps a `|`, folds fewer characters or cuts in the shell is another
# reading and keeps its own body beside its reason.
line_field_clean() {  # <value> [<max chars>] -> the value as one field; print it through $(...)
  printf '%s' "${1-}" | tr '\n\r\t|' '    ' \
    | sed -e 's/[[:cntrl:]]/ /g' -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//' | cut -c "1-${2:-}"
}
