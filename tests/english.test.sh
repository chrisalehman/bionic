#!/bin/bash
# tests/english.test.sh — payload/scripts/lib/english.sh, the one home of the English a page prints: a list of
# words as prose and a count that agrees with its noun.
#
# WHAT THIS SUITE OWNS. Four renderers each page that names things in a sentence used to carry its own copy of:
# the situation report's `sitrep_list` and `sitrep_noun`, the release card's `_card_list` and `_card_plural`, the
# release approval's `rr_plural`, and the doctor's `_doctor_plural`. The library holds them once, and the two awk
# programs that joined a list inline read its awk function, not a join of their own.
#
#   §LIST    english_list: nothing for no word; `A`, `A and B`, `A, B and C`; the first <cap> named and the rest
#            counted (`A, B and 2 more`); a cap equal to the count names all; words keep their spaces and quotes.
#   §PLURAL  english_plural prints `<n> <word>` (`1 criterion`, `0 criteria`, `3 criteria`).
#   §NOUN    english_noun prints the word alone, the singular only for the string `1`.
#   §JOIN    the awk function the library hands a caller's awk program reads as the shell renderer does, over the
#            same table, and a program that prefixes it gets the same words.
#   §HOMES   each retired copy is gone from the file that carried it, and the file reads the library (or, for the
#            two helpers that live in an older library, that library's function) in its place.
#
# ANTI-VACUITY. Every empty answer sits in a table beside answers read through the same door (`lib_call`, which
# joins the exit code to the output so an absent function reads `|127`, never a pass). §HOMES asserts the
# absence of a definition only in the same fixture that asserts the home's presence and the caller's use of it.
# The expected strings were measured by running the retired copies over these same arguments.
#
# Usage: bash tests/english.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

LIB="$BIONIC_SCRIPTS_DIR/payload/scripts/lib"

if [ -r "$LIB/english.sh" ] && bash -n "$LIB/english.sh" 2>/dev/null; then ok "subject present and parses: lib/english.sh"
else no "subject present and parses: lib/english.sh" "missing or unparseable"; fi

lib_call() { bash -c '. "$1/english.sh" 2>/dev/null; shift; o="$("$@")"; r=$?; printf "%s|%s" "$o" "$r"' _ "$LIB" "$@" 2>/dev/null; }

section "§LIST — english_list names the first <cap> words as prose and counts the rest"
expect_eq "LS.1 one word is the word" "A|0" "$(lib_call english_list 6 A)"
expect_eq "LS.2 two words are joined by and" "A and B|0" "$(lib_call english_list 6 A B)"
expect_eq "LS.3 three words close with and, the rest with commas" "A, B and C|0" "$(lib_call english_list 6 A B C)"
expect_eq "LS.4 six words under a cap of six name all six" "A, B, C, D, E and F|0" "$(lib_call english_list 6 A B C D E F)"
expect_eq "LS.5 a seventh word is counted, not named" "A, B, C, D, E, F and 1 more|0" "$(lib_call english_list 6 A B C D E F G)"
expect_eq "LS.6 nine words under a cap of five count the last four" "A, B, C, D, E and 4 more|0" "$(lib_call english_list 5 A B C D E F G H I)"
expect_eq "LS.7 a cap of one names the first and counts the rest" "A and 2 more|0" "$(lib_call english_list 1 A B C)"
expect_eq "LS.8 a cap of 99 over two words names both" "A and B|0" "$(lib_call english_list 99 A B)"
expect_eq "LS.9 words keep their spaces and quotes" "the plan's rows and two words|0" "$(lib_call english_list 6 "the plan's rows" "two words")"
expect_eq "LS.10 no word prints nothing and exits 0" "|0" "$(lib_call english_list 6)"

section "§PLURAL — english_plural prints the count and the word that agrees with it"
expect_eq "PL.1 one is the singular" "1 criterion|0" "$(lib_call english_plural 1 criterion criteria)"
expect_eq "PL.2 zero is the plural" "0 criteria|0" "$(lib_call english_plural 0 criterion criteria)"
expect_eq "PL.3 three is the plural" "3 criteria|0" "$(lib_call english_plural 3 criterion criteria)"
expect_eq "PL.4 a plural that is no s-word is the one handed" "2 copies|0" "$(lib_call english_plural 2 copy copies)"
expect_eq "PL.5 a count of 01 is a number one, as -eq reads it" "1 commit|0" "$(lib_call english_plural 01 commit commits)"

section "§NOUN — english_noun prints the word alone, the singular only for the string 1"
expect_eq "NN.1 one is the singular, with no newline" "task|0" "$(lib_call english_noun 1 task tasks)"
expect_eq "NN.2 two is the plural" "tasks|0" "$(lib_call english_noun 2 task tasks)"
expect_eq "NN.3 zero is the plural" "tasks|0" "$(lib_call english_noun 0 task tasks)"
expect_eq "NN.4 an empty count is the plural" "tasks|0" "$(lib_call english_noun "" task tasks)"
expect_eq "NN.5 is and are, the doctor's use" "are|0" "$(lib_call english_noun 3 is are)"
expect_eq "NN.6 a count with a blank before it is not the string 1" "files|0" "$(lib_call english_noun " 1" file files)"
# The word alone carries no newline, so a caller's `$n $(english_noun ...)` is one line: measure the bytes.
expect_eq "NN.7 english_noun prints the word and no byte more" "4" "$(bash -c '. "$1/english.sh" 2>/dev/null; english_noun 1 task tasks | wc -c | tr -d " "' _ "$LIB")"

section "§JOIN — the awk function reads as the shell renderer does"
awk_join() {  # <cap> <word>... -> english_join's answer, from a program that prefixes the library's awk text
  bash -c '. "$1/english.sh" 2>/dev/null; shift; cap="$1"; shift
    awk -v cap="$cap" "$_ENGLISH_AWK"'"'"'BEGIN { n = ARGC - 1; for (i = 1; i <= n; i++) w[i] = ARGV[i]; print english_join(w, n, cap) }'"'"' "$@"' _ "$LIB" "$@" 2>/dev/null
}
while IFS='|' read -r id cap words; do
  [ -n "$id" ] || continue
  # shellcheck disable=SC2086
  expect_eq "$id awk english_join over '$words' under a cap of $cap equals english_list" "$(bash -c '. "$1/english.sh" 2>/dev/null; shift; english_list "$@"' _ "$LIB" "$cap" $words 2>/dev/null)" "$(awk_join "$cap" $words)"
done <<'ROWS'
JN.1|6|A
JN.2|6|A B
JN.3|6|A B C
JN.4|6|A B C D E F G
JN.5|2|A B C D
JN.6|1|A B C
ROWS
expect_eq "JN.7 the awk join answers a measured string" "A, B, C and 1 more" "$(awk_join 3 A B C D)"
expect_eq "JN.8 the awk join of no word is empty" "" "$(awk_join 3)"

section "§HOMES — the retired copies are gone and each file reads its home"
# <file>|<retired definition>|<what the file reads in its place>
while IFS='|' read -r id file fn home; do
  [ -n "$id" ] || continue
  path="$BIONIC_SCRIPTS_DIR/$file"
  defs="$(/usr/bin/grep -c -E "^[[:space:]]*${fn}\(\)" "$path" 2>/dev/null)"; defs="${defs:-x}"
  uses="$(/usr/bin/grep -c -E "$home" "$path" 2>/dev/null)"; uses="${uses:-x}"
  expect_regex "$id $file reads its home ($home)" '^[1-9][0-9]*$' "$uses"
  expect_eq "$id $file defines no $fn" "0" "$defs"
done <<'ROWS'
HM.1|hooks/poker/sitrep.sh|sitrep_noun|english_noun
HM.2|hooks/poker/sitrep.sh|sitrep_list|english_list
HM.3|hooks/poker/plan.sh|rr_plural|english_plural
HM.4|payload/scripts/card.sh|_card_list|english_list
HM.5|payload/scripts/card.sh|_card_plural|english_plural
HM.6|payload/scripts/doctor.sh|_doctor_plural|english_noun
HM.7|payload/scripts/doctor.sh|_doctor_is_repo|is_repo
HM.8|payload/scripts/version.sh|_version_is_repo|is_repo
HM.9|payload/scripts/setup.sh|_setup_file_mode|_markers_file_mode
ROWS
for f in hooks/poker/sitrep.sh payload/scripts/card.sh; do
  expect_regex "HM.10 $f joins its inline lists through english_join" '^[1-9][0-9]*$' "$(/usr/bin/grep -c 'english_join(' "$BIONIC_SCRIPTS_DIR/$f" 2>/dev/null)"
done
expect_eq "HM.11 doctor.sh names english.sh among the libraries it needs" "1" "$(/usr/bin/grep -c 'english\.sh' "$BIONIC_SCRIPTS_DIR/payload/scripts/doctor.sh" 2>/dev/null | awk '$1 > 0 { print 1; exit } { print 0 }')"

finish
