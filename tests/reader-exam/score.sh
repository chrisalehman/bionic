#!/bin/bash
# tests/reader-exam/score.sh — README step 5 as code. Sourced, it defines three functions
# (exam_meets, exam_field, exam_score) and does nothing else: tests/reader-exam.test.sh holds
# the real keys to them, and a sitting scores its records with them.
#
#   . tests/reader-exam/score.sh
#   exam_score tests/reader-exam/samples/<name>/expect.txt <record>      # prints met or missed

# exam_meets <key result> <reached result> — rc 0 when the reached result meets the key's. A
# key of `pass` is a change with no defect, and not failing it is the bar: `pass` or `flag`.
# Any other key is met by itself alone.
exam_meets() {
  case "$1" in
    pass) case "$2" in pass|flag) return 0 ;; esac; return 1 ;;
    "") return 1 ;;
    *) [ "$2" = "$1" ] ;;
  esac
}

# exam_field <expect.txt> <field> — the value of the key's first `<field>:` line, read without a
# CR before its line end or blanks after it.
exam_field() {
  sed -n "s/^$2: //p" "$1" | head -n 1 | sed 's/\r$//; s/[[:blank:]]*$//'
}

# exam_score <expect.txt> <record> — prints `met` (rc 0) or `missed` (rc 1).
#
# A record is read as passes: each flush-left `question:` line opens one, and the first pass
# also holds the lines above it. Only a pass whose question the key names is scored, so a
# one-mind reader's three passes in one file are each read on their own question, never on
# whichever `result:` comes first. Met when at least one pass is scored and every scored pass
# has: its first flush-left `result:` meeting the key's result (exam_meets); one of the key's
# tokens; and, when the key has a `names:` line, one of its identifiers. Alternatives on a
# `token:` or `names:` line are separated by ` | `. A CR before a line end, and blanks after a
# value, are not part of it. The scorer's own lines are read with an IFS of its own: a caller's
# IFS (`,`, `:` or empty) is not the separator of what the awk below prints.
exam_score() {
  local key="$1" rec="$2" kq kr kt kn passes r t n scored=0
  [ -r "$key" ] && [ -r "$rec" ] || { echo "missed"; return 1; }
  kq="$(exam_field "$key" question)"; kr="$(exam_field "$key" result)"
  kt="$(exam_field "$key" token)"; kn="$(exam_field "$key" names)"
  passes="$(KQ="$kq" KT="$kt" KN="$kn" awk '
    function value(s) { sub(/^[a-z]+:[ \t]*/, "", s); sub(/[ \t]+$/, "", s); return s }
    function any(list, text,   a, i, k) {
      if (list == "") return 1
      k = split(list, a, / \| /)
      for (i = 1; i <= k; i++) if (a[i] != "" && index(text, a[i])) return 1
      return 0
    }
    BEGIN { np = 1; split(ENVIRON["KQ"], qs, /, */); for (i in qs) keyed[qs[i]] = 1 }
    { sub(/\r$/, "") }
    /^question:/ { if (opened[np]) np++; opened[np] = 1; q[np] = value($0) }
    /^result:/ && !(np in r) { r[np] = value($0) }
    { text[np] = text[np] $0 "\n" }
    END {
      for (i = 1; i <= np; i++)
        if (opened[i] && (q[i] in keyed))
          printf "%d %d %s\n", any(ENVIRON["KT"], text[i]), any(ENVIRON["KN"], text[i]), r[i]
    }' "$rec")"
  while IFS=' ' read -r t n r; do
    [ -n "$t" ] || continue
    scored=1
    exam_meets "$kr" "$r" && [ "$t" = 1 ] && [ "$n" = 1 ] || { echo "missed"; return 1; }
  done <<EOF
$passes
EOF
  [ "$scored" = 1 ] || { echo "missed"; return 1; }
  echo "met"
}
