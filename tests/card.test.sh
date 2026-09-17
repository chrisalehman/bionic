#!/bin/bash
# tests/card.test.sh — payload/scripts/card.sh, THE CARD ROW RENDERER
# (epic-23 wave-14-tune-181, T36; REQ-9 AC-9.1/AC-9.4; Chris 2026-09-15 "D4: I
# want the wrapped version" / "option 1 - renderer script and cap at 110k").
#
# WHAT THIS SUITE IS FOR. Until this task the Step-1/2/3 cards were rendered by
# the MODEL reading a printf format line written beside the card and padding the
# row by hand. Two things were wrong with that and only one of them was visible:
#
#   OVERFLOW. `%-44s` does not wrap and does not truncate — it PADS a short value
#   and prints a long one whole, so a free-text cell longer than its column pushes
#   every trailing column right and the table stops being a table. The readability
#   review measured rows at 126 and 165 columns before T31 re-cut the widths, and
#   re-cutting the widths does not fix it: the next long sentence overflows the new
#   width exactly as it overflowed the old one.
#
#   BYTES, NOT COLUMNS (A-T31.3). `%-Ns` pads to a BYTE count. An em dash is three
#   bytes and one column, so a cell carrying one comes out two columns short and
#   the table steps left from that row down — payload/scripts/lib/width.sh's own
#   "PRINTF PADS BYTES; A TERMINAL LAYS OUT COLUMNS" note, one layer up.
#
# So the format is no longer INSTRUCTION, it is CODE: card.sh owns the widths, folds
# the free cell inside its own column, and measures in columns through width.sh.
# This suite is that file's wall.
#
# THE EQUIVALENCE ROWS ARE THE POINT OF THE SUITE. Sections 2 holds the SIX printf
# formats the three templates carried at 89f6944 — the widths T31 fitted to the
# 100-column rule — and renders each kind's header and a short row from them, by
# hand, in this file. The renderer must agree BYTE FOR BYTE. That is what stops the
# widths drifting silently now that no card states them any more: a width changed in
# card.sh and not here turns this suite red rather than quietly re-laying the cards.
#
# Usage: bash tests/card.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
CARD_SH="${REPO}/payload/scripts/card.sh"
WIDTH_SH="${REPO}/payload/scripts/lib/width.sh"

# ── the formats card.sh now owns, as the three cards stated them at 89f6944 ──
OLD_FMT_REQ_A='    %-7s %s'
OLD_FMT_REQ_B='            provenance %-48s  ACs %s'
OLD_FMT_DEC='    %-4s %-44s %-14s %s'
OLD_FMT_OWN='    %-12s owner %-14s surfaces %-22s test %s'
OLD_FMT_EVAL='    %-8s %-36s %6s %5s %9s %5s %6s'
OLD_FMT_TASK='    %-5s %-30s %-10s %-13s %s'

section "Section 1: the renderer is there, and it refuses what it cannot render"

expect_true "1: payload/scripts/card.sh exists" test -f "$CARD_SH"

if [ ! -f "$CARD_SH" ]; then
  no "1a: every row below is unrunnable without the renderer" "no file at $CARD_SH"
fi

# THE USAGE WIRE. One line on stderr, exit 64 (EX_USAGE) — the payload's own
# spelling for "you called me wrong", distinct from a refusal (2) and from a
# renderer that simply printed nothing.
USAGE_OUT="$(printf '' | bash "$CARD_SH" 2>/dev/null)"; USAGE_RC=$?
expect_eq "2: no row kind exits 64" "64" "$USAGE_RC"
expect_empty "2a: …and prints nothing on stdout" "$USAGE_OUT"
USAGE_ERR="$(printf '' | bash "$CARD_SH" 2>&1 >/dev/null)"
expect_eq "2b: …and exactly one line on stderr" "1" \
  "$(printf '%s\n' "$USAGE_ERR" | grep -c . | tr -d ' ')"

BADKIND_RC=0
printf 'a\tb\n' | bash "$CARD_SH" not-a-kind >/dev/null 2>&1 || BADKIND_RC=$?
expect_eq "3: an unknown row kind exits 64" "64" "$BADKIND_RC"
BADKIND_ERR="$(printf 'a\tb\n' | bash "$CARD_SH" not-a-kind 2>&1 >/dev/null)"
expect_eq "3a: …and says so in one line" "1" \
  "$(printf '%s\n' "$BADKIND_ERR" | grep -c . | tr -d ' ')"

# THE SYNTAX GATE IS /bin/bash, WHICH ON THIS PLATFORM IS 3.2. The payload runs
# under whatever bash the machine shipped, and macOS ships 3.2.57 — a `mapfile`,
# an associative array or a `${var,,}` in card.sh would be a syntax error there
# and nowhere the author was looking.
expect_true "4: card.sh parses under /bin/bash" /bin/bash -n "$CARD_SH"
expect_eq "4a: …and /bin/bash is the 3.x this gate is about" "3" \
  "$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')"

section "Section 2: every kind renders what its former printf format rendered"

# fmt_render — the row, built one field at a time from a format, the way the card
# was hand-padded before this task. NOT `printf "$fmt"` itself: printf pads by
# BYTES and the Tasks card's `depends` cell carries an em dash, so printf and the
# shipped card disagree there. Padding here counts COLUMNS through width.sh, which
# is the reading the shipped cards were laid out in and the one card.sh must hold.
if [ -f "$WIDTH_SH" ]; then
  # shellcheck source=/dev/null
  . "$WIDTH_SH"
else
  no "5: width.sh is needed to measure a rendered row" "no file at $WIDTH_SH"
fi

cols() { bionic_cols "${1:-}"; }

fmt_render() {  # <fmt> <val>... -> the row, padded in columns
  local fmt="$1"; shift
  local vals=("$@")
  local rest="$fmt" i=0 out="" lit dash w val vlen n pad
  while [[ "$rest" =~ ^([^%]*)%(-?)([0-9]*)s(.*)$ ]]; do
    lit="${BASH_REMATCH[1]}"; dash="${BASH_REMATCH[2]}"; w="${BASH_REMATCH[3]}"
    rest="${BASH_REMATCH[4]}"
    out="${out}${lit}"
    val="${vals[$i]:-}"; vlen="$(cols "$val")"; pad=""
    if [ -n "$w" ] && [ "$w" -gt "$vlen" ]; then n=$(( w - vlen )); pad="$(printf '%*s' "$n" '')"; fi
    if [ "$dash" = "-" ]; then out="${out}${val}${pad}"; else out="${out}${pad}${val}"; fi
    i=$(( i + 1 ))
  done
  printf '%s' "${out}${rest}"
}

fmt_starts() {  # <fmt> <val>... -> one 1-indexed start column per field, one per line
  local fmt="$1"; shift
  local vals=("$@")
  local rest="$fmt" col=1 i=0 lit w val vlen eff
  while [[ "$rest" =~ ^([^%]*)%(-?)([0-9]*)s(.*)$ ]]; do
    lit="${BASH_REMATCH[1]}"; w="${BASH_REMATCH[3]}"; rest="${BASH_REMATCH[4]}"
    col=$(( col + ${#lit} ))
    printf '%s\n' "$col"
    val="${vals[$i]:-}"; vlen="$(cols "$val")"; eff="$vlen"
    if [ -n "$w" ] && [ "$w" -gt "$vlen" ]; then eff="$w"; fi
    col=$(( col + eff )); i=$(( i + 1 ))
  done
}

hdr_build() {  # <section label> <fmt> <field-index:label>... -> the card's header line
  local label="$1" fmt="$2"; shift 2
  local starts=() pair idx lbl line="  ${label}" col
  while IFS= read -r col; do starts+=("$col"); done < <(fmt_starts "$fmt" "" "" "" "" "" "" "")
  for pair in "$@"; do
    idx="${pair%%:*}"; lbl="${pair##*:}"
    col="${starts[$idx]:-1}"
    while [ "$(( ${#line} + 1 ))" -lt "$col" ]; do line="${line} "; done
    line="${line}${lbl}"
  done
  printf '%s' "$line"
}

card() {  # <kind> — TSV rows on stdin
  bash "$CARD_SH" "$@" 2>/dev/null
}

# --- requirement (two physical lines per row, no column header) ---
REQ_VALS_A=("REQ-<id>" "<the requirement in one line>")
REQ_VALS_B=("<user quote | spec section | ticket | report>" "<n>")
REQ_WANT="$(printf '%s\n' \
  "  Requirements" \
  "$(fmt_render "$OLD_FMT_REQ_A" "${REQ_VALS_A[@]}")" \
  "$(fmt_render "$OLD_FMT_REQ_B" "${REQ_VALS_B[@]}")")"
REQ_GOT="$(printf '%s\t%s\t%s\t%s\n' "${REQ_VALS_A[0]}" "${REQ_VALS_A[1]}" "${REQ_VALS_B[0]}" "${REQ_VALS_B[1]}" | card requirement)"
expect_eq "6: the requirement kind renders the card's own two-line row" "$REQ_WANT" "$REQ_GOT"

# --- decision ---
DEC_VALS=("D<n>" "<the decision in one line>" "<REQ ids>" "<file | none>")
DEC_WANT="$(printf '%s\n' \
  "$(hdr_build "Decisions" "$OLD_FMT_DEC" "2:serves" "3:ADR")" \
  "$(fmt_render "$OLD_FMT_DEC" "${DEC_VALS[@]}")")"
DEC_GOT="$(printf '%s\t%s\t%s\t%s\n' "${DEC_VALS[@]}" | card decision)"
expect_eq "7: the decision kind renders the card's own header and row" "$DEC_WANT" "$DEC_GOT"

# --- ownership (labels are literals inside the format; header is the bare section) ---
OWN_VALS=("<concept>" "<module>" "<where it renders>" "<suite>")
OWN_WANT="$(printf '%s\n' \
  "  Ownership" \
  "$(fmt_render "$OLD_FMT_OWN" "${OWN_VALS[@]}")")"
OWN_GOT="$(printf '%s\t%s\t%s\t%s\n' "${OWN_VALS[@]}" | card ownership)"
expect_eq "8: the ownership kind renders the card's own header and row" "$OWN_WANT" "$OWN_GOT"

# --- eval-design (five RIGHT-aligned count columns, and a total row) ---
EVAL_VALS1=("REQ-<id>" "<how it is proven, one line>" "2" "1" "3" "0" "1")
EVAL_VALS2=("REQ-<id>" "<how it is proven, one line>" "1" "0" "2" "1" "0")
EVAL_VALS_T=("total" "" "3" "1" "5" "1" "1")
EVAL_WANT="$(printf '%s\n' \
  "$(hdr_build "Eval design" "$OLD_FMT_EVAL" "2:static" "3:unit" "4:hermetic" "5:live" "6:human")" \
  "$(fmt_render "$OLD_FMT_EVAL" "${EVAL_VALS1[@]}")" \
  "$(fmt_render "$OLD_FMT_EVAL" "${EVAL_VALS2[@]}")" \
  "$(fmt_render "$OLD_FMT_EVAL" "${EVAL_VALS_T[@]}")")"
EVAL_GOT="$( { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${EVAL_VALS1[@]}"
               printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${EVAL_VALS2[@]}"
               printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${EVAL_VALS_T[@]}"; } | card eval-design)"
expect_eq "9: the eval-design kind renders the card's own header and three rows" "$EVAL_WANT" "$EVAL_GOT"

# --- task ---
TASK_VALS1=("<n>" "<the task in one line>" "build" "—" "senior-implementor")
TASK_VALS2=("<n>" "<the task in one line>" "test" "<n>" "implementor")
TASK_WANT="$(printf '%s\n' \
  "$(hdr_build "Tasks" "$OLD_FMT_TASK" "2:kind" "3:depends" "4:agent")" \
  "$(fmt_render "$OLD_FMT_TASK" "${TASK_VALS1[@]}")" \
  "$(fmt_render "$OLD_FMT_TASK" "${TASK_VALS2[@]}")")"
TASK_GOT="$( { printf '%s\t%s\t%s\t%s\t%s\n' "${TASK_VALS1[@]}"
               printf '%s\t%s\t%s\t%s\t%s\n' "${TASK_VALS2[@]}"; } | card task)"
expect_eq "10: the task kind renders the card's own header and both rows" "$TASK_WANT" "$TASK_GOT"

section "Section 3: the free cell folds inside its column — the shape Chris chose"

# THE PICTURE, VERBATIM. Three shapes of one row were put to Chris at the T36
# dispatch: OVERFLOW (today's printf, trailing columns pushed right), STAGGERED
# (the pre-T10 shape, trailing columns on a line of their own) and WRAPPED. He
# chose WRAPPED — "D4: I want the wrapped version" — so the expected block below
# is his picture, transcribed, not a shape this suite invented.
WRAPPED_WANT='    D2   A decision whose text runs well past the     REQ-2, REQ-3   none
         forty-four column limit'
WRAPPED_GOT="$(printf 'D2\tA decision whose text runs well past the forty-four column limit\tREQ-2, REQ-3\tnone\n' \
  | card decision | grep -v '^  Decisions')"
expect_eq "11: a long decision cell folds at its column, trailing columns on line one" \
  "$WRAPPED_WANT" "$WRAPPED_GOT"

# The two shapes it is NOT, asserted as absences against the same row, so a
# renderer that regressed to either one fails here and names which.
case "$WRAPPED_GOT" in
  *'forty-four column limit   REQ-2, REQ-3'*|*'limit REQ'*)
    no "12: the row does not OVERFLOW (trailing columns pushed right by the long cell)" "$WRAPPED_GOT" ;;
  *) ok "12: the row does not OVERFLOW (trailing columns pushed right by the long cell)" ;;
esac
if printf '%s\n' "$WRAPPED_GOT" | grep -qE '^[[:space:]]+(REQ-2|serves|ADR|none)'; then
  no "13: the row is not STAGGERED (no continuation line begins with a trailing column)" "$WRAPPED_GOT"
else
  ok "13: the row is not STAGGERED (no continuation line begins with a trailing column)"
fi

# Continuation lines carry NOTHING but the folded cell: no repeated id, no
# repeated trailing column, indented to the cell's own start column.
FOLD_CONT="$(printf '%s\n' "$WRAPPED_GOT" | sed -n '2p')"
expect_eq "14: the continuation line is indented to the free cell's start column" "9" \
  "$(printf '%s' "$FOLD_CONT" | sed -e 's/[^ ].*$//' | awk '{print length}')"
expect_absent "14a: …and carries none of the row's trailing columns" "REQ-2" "$FOLD_CONT"
expect_absent "14b: …and does not repeat the row id" "D2" "$FOLD_CONT"

# The fold is by WORD, never mid-word, and no word is lost.
FOLD_WORDS="$(printf '%s\n' "$WRAPPED_GOT" | sed -n '2p' | sed 's/^ *//')"
expect_eq "15: the fold breaks on a word boundary" "forty-four column limit" "$FOLD_WORDS"

section "Section 4: every kind's free cell folds, and every line stays inside the budget"

# ONE REPO-SCALE ROW PER KIND. Not a synthetic string of x's: a sentence the length
# a real wave writes, run through every kind, with every output line measured.
LONG='the derivation bound is owned in one file and both legs read it from there, with the margin named beside each number'
over_budget() {  # <rendered block> -> the lines wider than the budget, if any
  local _line _bad=""
  while IFS= read -r _line; do
    [ "$(cols "$_line")" -le "$BIONIC_LINE_WIDTH" ] || _bad="${_bad}${_bad:+ | }$(cols "$_line"):${_line}"
  done < <(printf '%s\n' "$1")
  printf '%s' "$_bad"
}

REQ_LONG="$(printf 'REQ-9\t%s\t%s\t4\n' "$LONG" "$LONG" | card requirement)"
expect_empty "16: requirement — no line exceeds the budget on a repo-scale row" "$(over_budget "$REQ_LONG")"
DEC_LONG="$(printf 'D4\t%s\tREQ-7, REQ-9\tadr-027-close-out-split.md\n' "$LONG" | card decision)"
expect_empty "17: decision — no line exceeds the budget on a repo-scale row" "$(over_budget "$DEC_LONG")"
OWN_LONG="$(printf 'derivation bound\tbounds.sh\t%s\ttests/stop.test.sh\n' "$LONG" | card ownership)"
expect_empty "18: ownership — no line exceeds the budget on a repo-scale row" "$(over_budget "$OWN_LONG")"
EVAL_LONG="$(printf 'REQ-9\t%s\t2\t1\t3\t0\t1\n' "$LONG" | card eval-design)"
expect_empty "19: eval-design — no line exceeds the budget on a repo-scale row" "$(over_budget "$EVAL_LONG")"
TASK_LONG="$(printf 'T36\t%s\tbuild\t—\tsenior-implementor\n' "$LONG" | card task)"
expect_empty "20: task — no line exceeds the budget on a repo-scale row" "$(over_budget "$TASK_LONG")"

# …and the fold actually happened, in every one of them: a cell this long cannot
# be one line, so a renderer that silently dropped the tail passes 16-20 too.
for _pair in "21:requirement:$REQ_LONG" "22:decision:$DEC_LONG" "23:ownership:$OWN_LONG" \
             "24:eval-design:$EVAL_LONG" "25:task:$TASK_LONG"; do
  _n="${_pair%%:*}"; _rest="${_pair#*:}"; _kind="${_rest%%:*}"; _block="${_rest#*:}"
  if [ "$(printf '%s\n' "$_block" | wc -l | tr -d ' ')" -ge 3 ]; then
    ok "${_n}: ${_kind} — the long cell folded onto continuation lines rather than being cut"
  else
    no "${_n}: ${_kind} — the long cell was not folded" "$_block"
  fi
done

# NOTHING IS LOST IN THE FOLD. Every word of the cell comes back out, in order.
# The cell occupies columns 10-53 of every line of a decision row (the format's own
# second field), so the cell is read back by COLUMN rather than by stripping the
# trailing text with a pattern that would have to know what is in it.
DEC_WORDS="$(printf '%s\n' "$DEC_LONG" | grep -v '^  Decisions' | cut -c10-53 \
  | sed -e 's/ *$//' | tr '\n' ' ' | sed -e 's/  *$//')"
expect_eq "26: the folded cell reads back word for word" "$LONG" "$DEC_WORDS"

section "Section 5: columns, not bytes — and the edges"

# THE EM DASH IS THE BUG A-T31.3 NAMED. Three bytes, one column: a row padded by
# `printf %-Ns` comes out two columns short from that cell on. The renderer pads
# through width.sh, so the trailing column lands where it lands without it.
EM_GOT="$(printf 'T1\tan em — dash\tbuild\t—\timplementor\n' | card task | sed -n '2p')"
PLAIN_GOT="$(printf 'T1\tan em x dash\tbuild\tx\timplementor\n' | card task | sed -n '2p')"
expect_eq "27: an em dash in a cell pads by columns, not bytes (the row is as wide as its ASCII twin)" \
  "$(cols "$PLAIN_GOT")" "$(cols "$EM_GOT")"
expect_eq "27a: …and the em-dash row's trailing column starts where the ASCII row's does" \
  "$(cols "${PLAIN_GOT%%implementor*}")" "$(cols "${EM_GOT%%implementor*}")"

# A GLYPH OUTSIDE width.sh's CLOSED SET — CJK here — is measured CONSERVATIVELY,
# at its bytes, and the same in both locales. That is not an oversight: it is the
# ruling tests/width.test.sh:7n already holds bionic_trunc to ("the agreed answer
# is the CONSERVATIVE one … short of the budget, never over it, and the same in
# both places"). What this row pins is the property that matters for a card: the
# same bytes out under LC_ALL=C and under the ambient locale, and never a line
# over the budget.
CJK_ROW='T2	a 設計 decision cell	build	—	implementor'
CJK_U="$(printf '%s\n' "$CJK_ROW" | card task)"
CJK_C="$(printf '%s\n' "$CJK_ROW" | LC_ALL=C bash "$CARD_SH" task 2>/dev/null)"
expect_eq "28: a glyph outside the closed set renders the same under LC_ALL=C and under the ambient locale" \
  "$CJK_U" "$CJK_C"
expect_empty "28a: …and neither reading puts a line over the budget" "$(over_budget "$CJK_U")"
if printf '%s' "$CJK_U" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
  ok "28b: …and the row is valid UTF-8 (no cell was cut through a character)"
else
  no "28b: the row is not valid UTF-8" "$(printf '%s' "$CJK_U" | od -An -tx1 | tr -s ' ' | head -2)"
fi

# A SINGLE WORD WIDER THAN THE WHOLE COLUMN. It is split at the budget and never
# dropped: a row that silently lost a 60-character path would be worse than a row
# that broke one.
LONGWORD='payload/scripts/lib/a-single-unbreakable-path-longer-than-its-own-column.sh'
LW_GOT="$(printf 'D5\t%s\tREQ-9\tnone\n' "$LONGWORD" | card decision | grep -v '^  Decisions')"
LW_BACK="$(printf '%s\n' "$LW_GOT" | cut -c10-53 | sed -e 's/ *$//' | tr -d '\n')"
expect_eq "29: an over-long word is split at the column, never dropped" \
  "$LONGWORD" "$LW_BACK"
expect_empty "29a: …and the split row stays inside the budget" "$(over_budget "$LW_GOT")"

# AN EMPTY FREE CELL. One line, the trailing columns where they belong, no stray
# continuation line.
EMPTY_GOT="$(printf 'D6\t\tREQ-9\tnone\n' | card decision | grep -v '^  Decisions')"
expect_eq "30: an empty free cell renders one line, not two" "1" \
  "$(printf '%s\n' "$EMPTY_GOT" | grep -c . | tr -d ' ')"
expect_eq "30a: …and its trailing columns stay at their own columns" \
  "$(fmt_render "$OLD_FMT_DEC" "D6" "" "REQ-9" "none" | sed -e 's/ *$//')" \
  "$(printf '%s' "$EMPTY_GOT" | sed -e 's/ *$//')"

# A MISSING TRAILING CELL. A row short of its last column is rendered, not
# refused — the card is a display and half a row beats an error at a gate.
SHORT_GOT="$(printf 'D7\ta short decision\n' | card decision | grep -v '^  Decisions')"
expect_contains "31: a row missing its trailing cells still renders" "D7" "$SHORT_GOT"
expect_empty "31a: …with no trailing whitespace left behind" \
  "$(printf '%s' "$SHORT_GOT" | grep -n ' $' || true)"

# NO INPUT AT ALL. The header prints and nothing else: a card section with no rows
# yet is a real state at Step 2, and it is not an error.
HDRONLY="$(printf '' | card decision)"
expect_eq "32: with no rows on stdin the header prints alone" \
  "$(hdr_build "Decisions" "$OLD_FMT_DEC" "2:serves" "3:ADR")" "$HDRONLY"

section "Section 6: T10 — REQ-9 the widened glyph set and per-batch column widths"

# AC-9.1 / AC-9.2. A glyph outside the OLD closed set (§, the curly quotes) in
# the row's own folding cell must not move a trailing column — for every kind,
# not just requirement, which is what Chris's screenshot showed. Each pair below
# differs ONLY in the folding cell (glyphs vs its ASCII twin, same word count),
# fed as its OWN one-row batch so AC-9.5's per-batch widening (Section 6 below)
# cannot be what is holding the columns together — this is the measurement bug
# alone. Compared in COLUMNS via width.sh's own `bionic_cols` (already sourced
# above as `cols`), never in bytes: this repo's `/usr/bin/awk` measures
# multi-byte `length()` in bytes regardless of locale (verified live — the
# `awk length` reading the task row names would silently pass on the very bug
# this section exists to catch), so the differential is taken the way the rest
# of this suite already takes one — bash's own character-aware string ops under
# the ambient UTF-8 locale, `cols()` for the column count. See A-T10.1.
GLYPH_FOLD='a § — “x” …'
PLAIN_FOLD='a x x xxx x'

REQ9_G="$(printf 'REQ-9\treq text\t%s\t3\n' "$GLYPH_FOLD" | card requirement | sed -n '3p')"
REQ9_P="$(printf 'REQ-9\treq text\t%s\t3\n' "$PLAIN_FOLD" | card requirement | sed -n '3p')"
expect_eq "33: requirement — § — “ ” … in the provenance cell do not move ACs" \
  "$(cols "${REQ9_P%%ACs*}")" "$(cols "${REQ9_G%%ACs*}")"

DEC9_G="$(printf 'D9\t%s\tREQ-9\tnone\n' "$GLYPH_FOLD" | card decision | grep -v '^  Decisions')"
DEC9_P="$(printf 'D9\t%s\tREQ-9\tnone\n' "$PLAIN_FOLD" | card decision | grep -v '^  Decisions')"
expect_eq "34: decision — § — “ ” … in the decision cell do not move REQ-9" \
  "$(cols "${DEC9_P%%REQ-9*}")" "$(cols "${DEC9_G%%REQ-9*}")"

OWN9_G="$(printf 'concept\towner\t%s\ttests/x.test.sh\n' "$GLYPH_FOLD" | card ownership | grep -v '^  Ownership')"
OWN9_P="$(printf 'concept\towner\t%s\ttests/x.test.sh\n' "$PLAIN_FOLD" | card ownership | grep -v '^  Ownership')"
expect_eq "35: ownership — § — “ ” … in the surfaces cell do not move test" \
  "$(cols "${OWN9_P%%tests/x.test.sh*}")" "$(cols "${OWN9_G%%tests/x.test.sh*}")"

EVAL9_G="$(printf 'REQ-9\t%s\t2\t1\t3\t0\t1\n' "$GLYPH_FOLD" | card eval-design | tail -n +2)"
EVAL9_P="$(printf 'REQ-9\t%s\t2\t1\t3\t0\t1\n' "$PLAIN_FOLD" | card eval-design | tail -n +2)"
expect_eq "36: eval-design — § — “ ” … in the description cell keep every count column aligned" \
  "$(cols "$EVAL9_P")" "$(cols "$EVAL9_G")"

TASK9_G="$(printf 'T9\t%s\tbuild\t—\timplementor\n' "$GLYPH_FOLD" | card task | grep -v '^  Tasks')"
TASK9_P="$(printf 'T9\t%s\tbuild\t—\timplementor\n' "$PLAIN_FOLD" | card task | grep -v '^  Tasks')"
expect_eq "37: task — § — “ ” … in the task cell do not move build" \
  "$(cols "${TASK9_P%%build*}")" "$(cols "${TASK9_G%%build*}")"

# AC-9.3 (still holds with the widened set): a glyph-laden cell too long for its
# column still folds, the trailing columns stay on line one, and a continuation
# line carries none of them.
LONG_GLYPH='a decision whose provenance carries a § mark, an — em dash, a “quoted” phrase and … more words to force the fold onto a continuation line'
DEC_LONG_G="$(printf 'D9\t%s\tREQ-9\tnone\n' "$LONG_GLYPH" | card decision | grep -v '^  Decisions')"
expect_true "38: the glyph-laden cell actually folded (more than one line)" \
  test "$(printf '%s\n' "$DEC_LONG_G" | wc -l | tr -d ' ')" -ge 2
DEC_LONG_CONT="$(printf '%s\n' "$DEC_LONG_G" | sed -n '2,$p')"
expect_absent "38a: …and no continuation line carries the trailing REQ column" "REQ-9" "$DEC_LONG_CONT"
expect_absent "38b: …and none carries the trailing ADR column" "none" "$DEC_LONG_CONT"

# AC-9.4 (still holds): a glyph outside even the widened set (CJK) is read
# conservatively and no emitted line exceeds the budget — task kind pins this
# already (28/28a); this repeats it for a kind with a narrower fold column.
CJK_DEC="$(printf 'D9\ta 設計 decision cell\tREQ-9\tnone\n' | card decision)"
expect_empty "39: decision — a CJK cell stays inside the budget on every line" "$(over_budget "$CJK_DEC")"

# AC-9.5. Two ownership rows in ONE batch whose OWNER cells differ in width
# (`lib/x.sh` fits the format's own 14-column width; `tests/lib/impact.sh`
# does not) must still start `surfaces` and `test` on the SAME column in both
# rows — the format's declared width is a floor, not the answer, once a wider
# cell has been seen anywhere in the same card.
OWN_BATCH="$(printf 'concept a\tlib/x.sh\tsurfaces text a\ttest a\nconcept b\ttests/lib/impact.sh\tsurfaces text b\ttest b\n' \
  | card ownership | grep -v '^  Ownership')"
OWN_ROW1="$(printf '%s\n' "$OWN_BATCH" | sed -n '1p')"
OWN_ROW2="$(printf '%s\n' "$OWN_BATCH" | sed -n '2p')"
expect_eq "40: ownership — surfaces starts on the same column for both owner widths" \
  "$(cols "${OWN_ROW1%%surfaces text a*}")" "$(cols "${OWN_ROW2%%surfaces text b*}")"
expect_eq "41: ownership — test starts on the same column for both owner widths" \
  "$(cols "${OWN_ROW1%%test a*}")" "$(cols "${OWN_ROW2%%test b*}")"


section "Section 7: T11 — REQ-10, a whole approval card rendered from the step's artifact"

# WHAT THIS SECTION IS FOR. Until this task the three cards were rendered by the
# MODEL: it read the step file's picture, extracted the rows from the artifact by
# eye, and fed card.sh one TSV row at a time — so card.sh owned the WIDTHS and the
# model still owned the CONTENT. Every card was therefore a transcription, and a
# transcription can differ from its source without anything going red: a REQ text
# shortened in the retelling, an AC count off by one, a provenance dropped. The
# card is what an approval binds, so the card being a retelling of the artifact
# rather than a rendering of it is a correctness problem, not a tidiness one
# (memory routing-means-invocation-not-citation: the steps files CITED the
# renderer, and a citation is not an invocation).
#
# So the artifact is now the SSoT for card content (spec §3 "Card content") and
# `card.sh step1|step2|step3 <artifact>` is the one renderer. The rows below pin
# the two halves that matter: the card is COMPLETE from the artifact alone (no
# stdin, no second source), and its rows are BYTE-IDENTICAL to the same content
# fed through the row kinds — one fold and one pad, not two.
#
# HERMETIC. Every fixture is a file under one mktemp sandbox; nothing here reads
# the repository's own specs or plans.

CARD_SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/card-test.XXXXXX")" && pwd -P)"
card_cleanup() { [ -n "${CARD_SANDBOX:-}" ] && rm -rf "$CARD_SANDBOX"; }
trap card_cleanup EXIT

# whole_card — the verb under test, with STDIN CLOSED. Not `< /dev/null`: a
# closed descriptor is what proves the renderer never READS stdin, where
# /dev/null would let a `while read` that still exists simply see EOF.
#
# IT SETS GLOBALS AND PRINTS NOTHING, which is not a style choice: a helper
# called as `X="$(whole_card …)"` runs in a SUBSHELL, so an exit status it
# assigned there would never reach the assertion — every status row would read
# the initialised 0 and pass no matter what the renderer did. Caught here at RED
# (rows 42 and 63-66 passed against a renderer that has no step verbs at all).
WC_RC=0; WC_ERR=""; WC_OUT=""
whole_card() {  # <verb> [artifact] — sets WC_OUT, WC_RC, WC_ERR
  WC_RC=0
  bash "$CARD_SH" "$@" >"${CARD_SANDBOX}/.out" 2>"${CARD_SANDBOX}/.err" 0<&- || WC_RC=$?
  WC_OUT="$(cat "${CARD_SANDBOX}/.out" 2>/dev/null)"
  WC_ERR="$(cat "${CARD_SANDBOX}/.err" 2>/dev/null)"
}

# ── the fixtures ─────────────────────────────────────────────────────────────
REQ_FIX="${CARD_SANDBOX}/wave-99-fixture.requirements.md"
cat > "$REQ_FIX" <<'FIXEOF'
---
sdlc-step: 1
working-branch: wave/99-fixture
integration-branch: main
base-sha: abc1234
---

# fixture wave 99 · requirements

## Goal

Ship the fixture wave so the whole-card renderer has an artifact to read, and so
this suite can tell a rendered card from a transcribed one.

## Context

Not part of any card; here so the parser has a section to walk past.

## Not Doing

- The excluded item, and the one-line reason it is out.
- A second excluded item.

## Requirements and acceptance criteria

### REQ-1 — the first requirement in one line

provenance: user 2026-09-16 "do the thing"
- AC-1.1 the first criterion. Fails when: it does not hold.
- AC-1.2 the second criterion. Fails when: it does not hold.

### REQ-2 — the second requirement in one line

provenance: seed row 2; research row 2
- AC-2.1 the only criterion here. Fails when: it does not hold.
FIXEOF

REQ_NOBRANCH="${CARD_SANDBOX}/nobranch.requirements.md"
sed -e '/^working-branch:/d' -e '/^integration-branch:/d' -e '/^base-sha:/d' \
  "$REQ_FIX" > "$REQ_NOBRANCH"

REQ_NOGOAL="${CARD_SANDBOX}/nogoal.requirements.md"
sed -e 's/^## Goal$/## Purpose/' "$REQ_FIX" > "$REQ_NOGOAL"

REQ_NOPROV="${CARD_SANDBOX}/noprov.requirements.md"
sed -e '/^provenance: seed row 2; research row 2$/d' "$REQ_FIX" > "$REQ_NOPROV"

SPEC_FIX="${CARD_SANDBOX}/wave-99-fixture.spec.md"
cat > "$SPEC_FIX" <<'FIXEOF'
---
sdlc-step: 2
working-branch: wave/99-fixture
integration-branch: main
base-sha: abc1234
---

# fixture wave 99 · spec

## Goal

Answer the fixture's two requirements with a design small enough to read whole.

## Design

### 1. Domain model

- **Fixture** — a file this suite writes and reads back.

### 2. Component boundaries and interfaces

- **`lib/first.sh`** owns the first thing, and hands the second thing to its
  caller rather than doing it itself. (D1; REQ-1)
- **`lib/second.sh`** owns the second thing. (D2; REQ-2)

### 3. Ownership table

| concept | owning module (SSoT) | rendering surfaces | agreement test |
|---|---|---|---|
| first thing | `lib/first.sh` | `card.sh` rows | `tests/first.test.sh` |
| second thing | `lib/second.sh` | the fixture card | `tests/second.test.sh` |

### 4. Rejected alternatives

- Doing it by hand — lost to doing it in one place.

### ADR pointers

- ADR-099 — the fixture ruling: `adrs/epic-99/adr-099-fixture.md` (D1).

## Eval design

| Requirement | Approach | Criterion | Eval type | Eval | Fails when |
|---|---|---|---|---|---|
| REQ-1 | source pin | AC-1.1 the first criterion | static | `grep` | the pin is gone |
| REQ-1 | fixture run | AC-1.2 the second criterion | hermetic | `bash tests/first.test.sh` | it reds |
| REQ-2 | fixture run | AC-2.1 the only criterion | unit | `bash tests/second.test.sh` | it reds |
FIXEOF

PLAN_FIX="${CARD_SANDBOX}/wave-99-fixture.plan.md"
cat > "$PLAN_FIX" <<'FIXEOF'
---
sdlc-step: 3
walk: required
rigor: peer-reviewed
parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=probe
working-branch: wave/99-fixture
integration-branch: main
base-sha: abc1234
---

# fixture wave 99 · plan

## Goal

Land the fixture's two requirements under the fixture spec's design, on the
fixture branch, with one floor at the integration head.

## SDLC State

integration-branch: main
current: 4

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | REQ-1: the first task in one line. It also has a second sentence the card does not show. complexity: standard | implementor | — | 30 | REQ-1 | lib/first.sh | .worktrees/99-T1 | pending |
| T2 | 4 | test | REQ-2: the second task in one line. complexity: complex | senior-implementor | T1 | 45 | REQ-2 | lib/second.sh | — | pending |

## Verification Matrix

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1.1 | T0 | pending | — | — |
| AC-1.2 | T2 | pending | — | — |
| AC-2.1 | T1 | pending | — | — |
FIXEOF

# ── AC-10.1: the Step-1 card, whole, from the artifact alone ─────────────────
whole_card step1 "$REQ_FIX"; S1="$WC_OUT"
expect_eq "42: step1 exits 0 on a well-formed requirements artifact" "0" "$WC_RC"
expect_contains "42a: …and opens with the card's own title" "Step 1 · Requirements" "$S1"
expect_contains "43: Purpose carries the artifact's first ## Goal paragraph" \
  "Ship the fixture wave so the whole-card renderer has an artifact to read" "$S1"
expect_contains "43a: …and the Purpose section is labelled" "  Purpose" "$S1"
expect_contains "44: Branches names the working branch from the frontmatter" \
  "working       wave/99-fixture" "$S1"
expect_contains "44a: …and the integration branch" "integration   main" "$S1"
expect_contains "44b: …and the base sha the working branch came from" "abc1234" "$S1"

# Every REQ row, whole: id, text, provenance and AC COUNT, each read from the
# artifact. The count is the row most likely to drift in a transcription and the
# one a reader cannot check without opening the file.
expect_contains "45: the REQ-1 row carries its id and its one-line text" \
  "REQ-1   the first requirement in one line" "$S1"
expect_contains "45a: …and its provenance verbatim" \
  'provenance user 2026-09-16 "do the thing"' "$S1"
expect_contains "45b: …and its AC count, which is 2" "ACs 2" "$S1"
expect_contains "46: the REQ-2 row carries its id and text" \
  "REQ-2   the second requirement in one line" "$S1"
expect_contains "46a: …and its own provenance" "provenance seed row 2; research row 2" "$S1"
expect_contains "46b: …and its AC count, which is 1" "ACs 1" "$S1"

expect_contains "47: Not Doing carries the artifact's first bullet" \
  "The excluded item, and the one-line reason it is out." "$S1"
expect_contains "47a: …and its second" "A second excluded item." "$S1"
expect_contains "48: Artifacts names the artifact it was rendered from" "$REQ_FIX" "$S1"
expect_contains "49: the card ends at its own approval question" \
  'Do you approve these requirements? Reply "approved" to approve it.' "$S1"
expect_contains "49a: …and offers the explain affordance" "explain <requirement>" "$S1"

# NO STDIN. `whole_card` runs with descriptor 0 CLOSED, so a renderer that still
# read rows from stdin would have failed above; this row says so in its own name
# and pins the exit status a closed stdin produces.
expect_eq "50: the card is complete with stdin CLOSED, not merely empty" "0" "$WC_RC"
expect_empty "50a: …and nothing is written to stderr on a good artifact" "$WC_ERR"

# Branches absent from the frontmatter say so rather than inventing one.
whole_card step1 "$REQ_NOBRANCH"; S1_NB="$WC_OUT"
expect_eq "51: an artifact with no branch keys still renders" "0" "$WC_RC"
expect_contains "51a: …and the working branch reads 'not declared'" \
  "working       not declared" "$S1_NB"
expect_contains "51b: …and so does the integration branch" \
  "integration   not declared" "$S1_NB"

# ── AC-10.3: the whole-card row IS the row kind's row, byte for byte ─────────
# The Requirements block of the whole card, against the same two rows fed to
# `card.sh requirement` as TSV. Not a spot check of one cell: `cmp` over the
# whole block, so a different fold, a different pad, a different batch width or
# a different header all fail here rather than being discovered on a card.
printf 'REQ-1\tthe first requirement in one line\tuser 2026-09-16 "do the thing"\t2\nREQ-2\tthe second requirement in one line\tseed row 2; research row 2\t1\n' \
  | card requirement > "${CARD_SANDBOX}/tsv.txt"
printf '%s\n' "$S1" | sed -n '/^  Requirements$/,/^$/p' | sed -e '/^$/d' \
  > "${CARD_SANDBOX}/whole.txt"
if cmp -s "${CARD_SANDBOX}/tsv.txt" "${CARD_SANDBOX}/whole.txt"; then
  ok "52: AC-10.3 — the whole card's Requirements block is byte-identical to the TSV-fed rows"
else
  no "52: AC-10.3 — the whole card's Requirements block is byte-identical to the TSV-fed rows" \
    "$(diff "${CARD_SANDBOX}/tsv.txt" "${CARD_SANDBOX}/whole.txt" | head -8)"
fi

# ── AC-10.2: the Step-2 and Step-3 cards from their own artifacts ────────────
whole_card step2 "$SPEC_FIX"; S2="$WC_OUT"
expect_eq "53: step2 exits 0 on a well-formed spec artifact" "0" "$WC_RC"
expect_contains "53a: …and opens with the Step-2 title" "Step 2 · Design" "$S2"
expect_contains "54: the Decisions section carries D1 with its serves cell" "D1" "$S2"
expect_contains "54a: …and D1's ADR pointer rather than 'none'" "adr-099-fixture.md" "$S2"
expect_contains "54b: …and D2, whose serves cell is REQ-2" "D2" "$S2"
expect_contains "55: the Ownership section carries the spec's own table rows" \
  "owner lib/first.sh" "$S2"
expect_contains "55a: …and the second concept's test suite" "tests/second.test.sh" "$S2"
expect_contains "56: the Eval design section counts REQ-1's criteria by type" "REQ-1" "$S2"
expect_contains "56a: …and carries a total row" "total" "$S2"
expect_contains "57: the Step-2 card ends at its own approval question" \
  'Do you approve this design? Reply "approved" to approve it.' "$S2"

whole_card step3 "$PLAN_FIX"; S3="$WC_OUT"
expect_eq "58: step3 exits 0 on a well-formed plan artifact" "0" "$WC_RC"
expect_contains "58a: …and opens with the Step-3 title" "Step 3 · Plan" "$S3"
# The ledger cell's FIRST SENTENCE, folded inside the task column like any other
# free cell — so the assertion is against the first chunk, and the sentence the
# card must NOT carry is asserted absent beside it. A card that printed the whole
# ledger cell would pass a `contains` on the opening words and fail here, which
# is the failure worth catching: the ledger cell is a brief, the card is a line.
expect_contains "59: the Tasks section carries T1's text, folded in its column" \
  "REQ-1: the first task in one" "$S3"
expect_absent "59d: …and not the rest of the ledger cell's brief" \
  "second sentence the card does not show" "$S3"
expect_absent "59e: …nor the ledger's own complexity tag" "complexity: standard" "$S3"
expect_contains "59a: …and T1's kind, depends and agent cells" "implementor" "$S3"
expect_contains "59b: …and T2, whose depends cell is T1" "T2" "$S3"
expect_contains "60: Parallel width reads the plan's own writer budget" "8 writers" "$S3"
expect_contains "61: Verification counts the matrix rows" "3 matrix rows" "$S3"
expect_contains "61a: …and names the walk and the auditor rigor" "peer-reviewed" "$S3"
expect_contains "62: the Step-3 card ends at its own approval question" \
  'Do you approve this plan? Reply "approved" to approve it.' "$S3"

# ── AC-10.4: a defective artifact is a usage error, never half a card ────────
whole_card step1 "$REQ_NOGOAL"; S1_NG="$WC_OUT"
expect_eq "63: an artifact with no ## Goal exits 64" "64" "$WC_RC"
expect_empty "63a: …and prints no card at all, not half of one" "$S1_NG"
expect_contains "63b: …and names the missing piece on stderr" "## Goal" "$WC_ERR"

whole_card step1 "$REQ_NOPROV"; S1_NP="$WC_OUT"
expect_eq "64: a REQ heading with no provenance: line exits 64" "64" "$WC_RC"
expect_empty "64a: …and prints no card" "$S1_NP"
expect_contains "64b: …and names the requirement that lacks it" "REQ-2" "$WC_ERR"
expect_contains "64c: …and says what is missing" "provenance" "$WC_ERR"

whole_card step1 "${CARD_SANDBOX}/there-is-no-such-file.md"; S1_MISSING="$WC_OUT"
expect_eq "65: a step verb with an unreadable artifact exits 64" "64" "$WC_RC"
expect_empty "65a: …and prints nothing on stdout" "$S1_MISSING"

whole_card step1; S1_NOARG="$WC_OUT"
expect_eq "66: a step verb with no artifact path exits 64" "64" "$WC_RC"
expect_empty "66a: …and prints nothing on stdout" "$S1_NOARG"

# EVERY EMITTED LINE STILL FITS THE BUDGET, on a whole card as on a row: the
# fixed sections are folded by the same width.sh the rows are padded by.
#
# THE ARTIFACTS BLOCK IS EXEMPT, AND THAT IS width.sh's OWN RULE, not a hole cut
# for a failing row. An artifact line is a PATH — the thing the reader opens —
# and `bionic_line` already exists because "the end of a bionic row is where the
# thing to TYPE lives": a path folded across two lines cannot be copied and a
# path truncated to fit cannot be opened, so a long docs root wins over the
# column budget here and nowhere else. The exemption is paid for by row 68,
# which pins the path out WHOLE, on one line, with nothing elided (A-T11.3).
no_artifacts() { printf '%s\n' "$1" | sed -e '/^  Artifacts$/,/^$/d'; }
expect_empty "67: no line of the Step-1 card exceeds the budget" \
  "$(over_budget "$(no_artifacts "$S1")")"
expect_empty "67a: …nor of the Step-2 card" "$(over_budget "$(no_artifacts "$S2")")"
expect_empty "67b: …nor of the Step-3 card" "$(over_budget "$(no_artifacts "$S3")")"

# The exemption's other half: the path is printed WHOLE, on ONE line, however
# long the docs root is — never folded, never elided with the truncator's ….
S1_ART="$(printf '%s\n' "$S1" | grep -F "$REQ_FIX")"
expect_eq "68: the artifact path is printed on exactly one line" "1" \
  "$(printf '%s\n' "$S1_ART" | grep -c . | tr -d ' ')"
expect_eq "68a: …and whole, with nothing elided" "    requirements  ${REQ_FIX}" "$S1_ART"

finish
