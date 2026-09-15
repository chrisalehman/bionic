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

finish
