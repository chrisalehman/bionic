#!/bin/bash
# payload/scripts/lib/fields.sh — THE RECORD'S FIELD READER, the reader's: the one reading of a line the log's appender
# writes. The landing library and the reader's library each source it from their own directory, so a script that loads
# either reads a line's fields the same way. It is awk functions a program prefixes and runs with -F'|'. Every field is
# read by its name, never by its place, so a field the writer adds or moves is still read; the first `<key>=` of a line
# is its value. The body reads any line whose fields are split by FS, so a caller that also splits on a blank reads by name.
#   line_ev()     the line's event (`ev=`), or nothing on a line that is neither `line/v1|` nor `run/v1|`
#   line_kv(k)    the value of the line's field <k>, or nothing
# A shell caller holding one line asks `line_value`. bash 3.2.
_LINE_FIELDS_AWK='
function line_kv(k,   i) { for (i = 2; i <= NF; i++) if (index($i, k "=") == 1) return substr($i, length(k) + 2); return "" }
function line_ev() { return (substr($0, 1, 8) == "line/v1|" || substr($0, 1, 7) == "run/v1|") ? line_kv("ev") : "" }
'
line_value() {  # <one record line> <key> -> the value of its field <key>, through line_kv
  printf '%s\n' "$1" | awk -F'|' -v k="$2" "$_LINE_FIELDS_AWK"'{ print line_kv(k); exit }'
}
