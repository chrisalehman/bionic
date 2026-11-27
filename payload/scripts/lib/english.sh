#!/bin/bash
# payload/scripts/lib/english.sh — THE ENGLISH A PAGE PRINTS: a list of words as prose, and a count that agrees with its
# noun. The situation report, the release card, the release approval and the doctor each wrote their own copy of these,
# so a page could say `1 commits` where its neighbour said `1 commit`; they read this one. It loads nothing and runs
# nothing when sourced. bash 3.2.
#   english_list <cap> <word>…       the words as prose, `A`, `A and B`, `A, B and C`, the first <cap> named and the rest
#                                    counted (`A, B, C and 6 more`); nothing for no word
#   english_plural <n> <one> <many>  `<n> <word>`: `1 criterion`, `3 criteria`; <n> is read as a number
#   english_noun <n> <one> <many>    the word alone, <one> only for the string `1`, so an empty or blank count is plural
#   _ENGLISH_AWK                     the one join, as awk text a program prefixes to its own: `english_join(a, n, cap)` is
#                                    the words a[1..n] as english_list prints them, returned and not printed. A caller
#                                    whose words are made in awk (a label, a case folded) builds a[] and asks it.
_ENGLISH_AWK='
function english_join(a, n, cap,   i, m, s) {
  m = (n > cap) ? cap : n
  for (i = 1; i <= m; i++) s = s ((i == 1) ? "" : ((i == m && n == m) ? " and " : ", ")) a[i]
  if (n > m) s = s " and " (n - m) " more"
  return s
}
'

english_list() {  # <cap> <word>... -> the words as prose, the first <cap> named and the rest counted
  local cap="$1"; shift
  awk -v cap="$cap" "$_ENGLISH_AWK"'BEGIN {
    n = ARGC - 1; if (n < 1) exit
    for (i = 1; i <= n; i++) w[i] = ARGV[i]
    print english_join(w, n, cap) }' "$@"
}

english_plural() {  # <n> <singular> <plural> -> `<n> <word>`
  if [ "$1" -eq 1 ]; then printf '1 %s' "$2"; else printf '%s %s' "$1" "$3"; fi
}

english_noun() {  # <n> <singular> <plural> -> the word that agrees with <n>: one task, two tasks
  if [ "${1:-}" = 1 ]; then printf '%s' "$2"; else printf '%s' "$3"; fi
}
