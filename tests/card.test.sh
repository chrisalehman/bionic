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
# THREE OF THESE ARE NOT THE 89f6944 BASELINE ANY MORE: a title is at most 30
# characters on every card, so the requirement, decision and task rows give their
# title cell 30 columns, and the task row carries a `serves` column of its own
# after the title. The constants state the CURRENT shapes; the ownership and
# eval-design formats are still the baseline.
OLD_FMT_REQ_A='    %-7s %-30s  ACs %s'
OLD_FMT_DEC='    %-4s %-30s %-14s %s'
OLD_FMT_OWN='    %-12s owner %-14s surfaces %-22s test %s'
OLD_FMT_EVAL='    %-8s %-36s %6s %5s %9s %5s %6s'
OLD_FMT_TASK='    %-5s %-30s %-12s %-9s %-12s %s'

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

# --- requirement (the id, the title, and the criteria count on one line) ---
# The row is three cells: the title is the folding cell and the count trails it
# on the row's first line. The provenance is not on the card; `explain` prints it.
REQ_ID="REQ-<id>"
REQ_TITLE="<title>"
REQ_ACS="<n>"
REQ_WANT="$(printf '%s\n' \
  "  Requirements" \
  "$(fmt_render "$OLD_FMT_REQ_A" "$REQ_ID" "$REQ_TITLE" "$REQ_ACS")")"
REQ_GOT="$(printf '%s\t%s\t%s\n' "$REQ_ID" "$REQ_TITLE" "$REQ_ACS" | card requirement)"
expect_eq "6: the requirement kind renders the card's own one-line row, ACs on it" "$REQ_WANT" "$REQ_GOT"

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
TASK_VALS1=("<n>" "<the task title>" "REQ-<n>" "build" "—" "senior-implementor")
TASK_VALS2=("<n>" "<the task title>" "REQ-<n>" "test" "<n>" "implementor")
TASK_WANT="$(printf '%s\n' \
  "$(hdr_build "Tasks" "$OLD_FMT_TASK" "2:serves" "3:kind" "4:depends" "5:agent")" \
  "$(fmt_render "$OLD_FMT_TASK" "${TASK_VALS1[@]}")" \
  "$(fmt_render "$OLD_FMT_TASK" "${TASK_VALS2[@]}")")"
TASK_GOT="$( { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${TASK_VALS1[@]}"
               printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${TASK_VALS2[@]}"; } | card task)"
expect_eq "10: the task kind renders the card's own header and both rows" "$TASK_WANT" "$TASK_GOT"

section "Section 3: the free cell folds inside its column — the shape Chris chose"

# THE PICTURE, VERBATIM. Three shapes of one row were put to Chris at the T36
# dispatch: OVERFLOW (today's printf, trailing columns pushed right), STAGGERED
# (the pre-T10 shape, trailing columns on a line of their own) and WRAPPED. He
# chose WRAPPED — "D4: I want the wrapped version" — so the expected block below
# is his picture, transcribed, not a shape this suite invented.
WRAPPED_WANT='    D2   A decision whose text runs      REQ-2, REQ-3   none
         past the thirty column limit'
WRAPPED_GOT="$(printf 'D2\tA decision whose text runs past the thirty column limit\tREQ-2, REQ-3\tnone\n' \
  | card decision | grep -v '^  Decisions')"

# The two shapes it is NOT, asserted as absences against the same row, so a
# renderer that regressed to either one fails here and names which.
case "$WRAPPED_GOT" in
  *'thirty column limit   REQ-2, REQ-3'*|*'limit REQ'*)
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
expect_eq "15: the fold breaks on a word boundary" "past the thirty column limit" "$FOLD_WORDS"

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

REQ_LONG="$(printf 'REQ-9\t%s\t4\n' "$LONG" | card requirement)"
expect_empty "16: requirement — no line exceeds the budget on a repo-scale row" "$(over_budget "$REQ_LONG")"
DEC_LONG="$(printf 'D4\t%s\tREQ-7, REQ-9\tadr-027-close-out-split.md\n' "$LONG" | card decision)"
expect_empty "17: decision — no line exceeds the budget on a repo-scale row" "$(over_budget "$DEC_LONG")"
OWN_LONG="$(printf 'derivation bound\tbounds.sh\t%s\ttests/stop.test.sh\n' "$LONG" | card ownership)"
expect_empty "18: ownership — no line exceeds the budget on a repo-scale row" "$(over_budget "$OWN_LONG")"
EVAL_LONG="$(printf 'REQ-9\t%s\t2\t1\t3\t0\t1\n' "$LONG" | card eval-design)"
expect_empty "19: eval-design — no line exceeds the budget on a repo-scale row" "$(over_budget "$EVAL_LONG")"
TASK_LONG="$(printf 'T36\t%s\tREQ-7, REQ-9\tbuild\t—\tsenior-implementor\n' "$LONG" | card task)"
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
# The cell occupies columns 10-39 of every line of a decision row (the format's own
# second field), so the cell is read back by COLUMN rather than by stripping the
# trailing text with a pattern that would have to know what is in it.
DEC_WORDS="$(printf '%s\n' "$DEC_LONG" | grep -v '^  Decisions' | cut -c10-39 \
  | sed -e 's/ *$//' | tr '\n' ' ' | sed -e 's/  *$//')"

section "Section 5: columns, not bytes — and the edges"

# THE EM DASH IS THE BUG A-T31.3 NAMED. Three bytes, one column: a row padded by
# `printf %-Ns` comes out two columns short from that cell on. The renderer pads
# through width.sh, so the trailing column lands where it lands without it.
EM_GOT="$(printf 'T1\tan em — dash\tREQ-1\tbuild\t—\timplementor\n' | card task | sed -n '2p')"
PLAIN_GOT="$(printf 'T1\tan em x dash\tREQ-1\tbuild\tx\timplementor\n' | card task | sed -n '2p')"
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
CJK_ROW='T2	a 設計 decision cell	REQ-1	build	—	implementor'
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
LW_BACK="$(printf '%s\n' "$LW_GOT" | cut -c10-39 | sed -e 's/ *$//' | tr -d '\n')"
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

# T23 rule 5 merges the title and provenance into ONE stream, so the
# AC-9.1/9.2 concern for requirement now lives in that stream's own fold
# budget: a glyph miscounted there would wrap the whole stream at the wrong
# column, so the two twins — same word count, glyphs vs their ASCII
# stand-ins, placed as the provenance half of the stream — must measure the
# same rendered width.
REQ9_G="$(printf 'REQ-9\t%s\t3\n' "$GLYPH_FOLD" | card requirement | sed -n '2p')"
REQ9_P="$(printf 'REQ-9\t%s\t3\n' "$PLAIN_FOLD" | card requirement | sed -n '2p')"
expect_eq "33: requirement — § — “ ” … in the title measure the same width as their ASCII twin" \
  "$(cols "$REQ9_P")" "$(cols "$REQ9_G")"

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

TASK9_G="$(printf 'T9\t%s\tREQ-9\tbuild\t—\timplementor\n' "$GLYPH_FOLD" | card task | grep -v '^  Tasks')"
TASK9_P="$(printf 'T9\t%s\tREQ-9\tbuild\t—\timplementor\n' "$PLAIN_FOLD" | card task | grep -v '^  Tasks')"
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
# (.claude/rules/agent-discipline.md, "Routing means invocation, not citation": the
# steps files CITED the
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

- The excluded item: the one-line reason it is out.
- A second excluded item: why it is out too.

## Requirements and acceptance criteria

### REQ-1 — the first requirement

The fixture does the first thing, so the card has a sentence to draw under its row.

provenance: user 2026-09-16 "do the thing"
- AC-1.1 the first criterion. Fails when: it does not hold.
- AC-1.2 the second criterion. Fails when: it does not hold.

### REQ-2 — the second requirement

The fixture does the second thing too.

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
rigor: double
parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=user
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
| T1 | 4 | build | REQ-1: the first task. It also has a second sentence the card does not show. complexity: standard | implementor | — | 30 | REQ-1 | lib/first.sh | .worktrees/99-T1 | pending |
| T2 | 4 | test | REQ-2: the second task. complexity: complex | senior-implementor | T1 | 45 | REQ-2 | lib/second.sh | — | pending |

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
expect_contains "43a: …and the Purpose section is labelled" "  Purpose" "$S1"
# THE BRANCHES ARE CONFIGURATION (wave-39 T26; D3): they print on the Step-0 card, rendered here over the same
# artifact (no plan beside it, so its own frontmatter answers), and the requirements card carries none.
whole_card step0 "$REQ_FIX"; S0="$WC_OUT"
expect_contains "44: Branches names the working branch from the frontmatter" \
  "working       wave/99-fixture" "$S0"
expect_contains "44a: …and the integration branch" "integration   main" "$S0"
expect_contains "44b: …and the base sha the working branch came from" "abc1234" "$S0"
expect_eq "44c: the Step-1 card carries a Purpose block and no Branches block" "1|0" \
  "$(printf '%s\n' "$S1" | /usr/bin/grep -c '^  Purpose$' | tr -d ' ')|$(printf '%s\n' "$S1" | /usr/bin/grep -c 'Branches' | tr -d ' ')"

# Every REQ row, whole: id, text, provenance and AC COUNT, each read from the
# artifact. The count is the row most likely to drift in a transcription and the
# one a reader cannot check without opening the file.
expect_absent "45a: …and no provenance, which only explain prints" 'user 2026-09-16 "do the thing"' "$S1"
expect_contains "45b: …and its AC count, which is 2" "ACs 2" "$S1"
expect_absent "46a: …nor the second requirement's provenance" "seed row 2; research row 2" "$S1"
expect_contains "46b: …and its AC count, which is 1" "ACs 1" "$S1"

expect_contains "47a: …and its second, by its title" "A second excluded item" "$S1"
expect_absent "47b: …and no reason beside either" "why it is out too" "$S1"
expect_contains "48: Artifacts names the artifact it was rendered from" "$REQ_FIX" "$S1"
expect_contains "49a: …and offers the explain affordance" "explain <requirement>" "$S1"

# NO STDIN. `whole_card` runs with descriptor 0 CLOSED, so a renderer that still
# read rows from stdin would have failed above; this row says so in its own name
# and pins the exit status a closed stdin produces.
expect_eq "50: the card is complete with stdin CLOSED, not merely empty" "0" "$WC_RC"
expect_empty "50a: …and nothing is written to stderr on a good artifact" "$WC_ERR"

# Branches absent from the frontmatter say so rather than inventing one.
whole_card step0 "$REQ_NOBRANCH"; S1_NB="$WC_OUT"
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
# The sentence is each row's fourth cell, so the TSV carries it too.
printf 'REQ-1\tthe first requirement\t2\t%s\nREQ-2\tthe second requirement\t1\t%s\n' \
  "The fixture does the first thing, so the card has a sentence to draw under its row." \
  "The fixture does the second thing too." \
  | card requirement > "${CARD_SANDBOX}/tsv.txt"
printf '%s\n' "$S1" | sed -n '/^  Requirements$/,/^$/p' | sed -e '/^$/d' \
  > "${CARD_SANDBOX}/whole.txt"
if cmp -s "${CARD_SANDBOX}/tsv.txt" "${CARD_SANDBOX}/whole.txt"; then
  ok "52: AC-10.3 — the whole card's Requirements block is byte-identical to the TSV-fed rows"
else
  no "52: AC-10.3 — the whole card's Requirements block is byte-identical to the TSV-fed rows" \
    "$(diff "${CARD_SANDBOX}/tsv.txt" "${CARD_SANDBOX}/whole.txt" | head -8)"
fi
# THE ROWS' OWN LINES DO NOT MOVE: the block with its sentence lines taken out is byte for byte the
# three-cell rows, which draw exactly what they drew before a requirement carried a sentence.
printf 'REQ-1\tthe first requirement\t2\nREQ-2\tthe second requirement\t1\n' \
  | card requirement > "${CARD_SANDBOX}/tsv3.txt"
/usr/bin/grep -v '^            ' "${CARD_SANDBOX}/whole.txt" > "${CARD_SANDBOX}/whole-rows.txt"
expect_eq "52b: …and with its sentence lines out, the block is the three-cell rows byte for byte (precondition: two sentence lines)" "2|same" \
  "$(/usr/bin/grep -c '^            ' "${CARD_SANDBOX}/whole.txt" | tr -d ' ')|$(cmp -s "${CARD_SANDBOX}/tsv3.txt" "${CARD_SANDBOX}/whole-rows.txt" && echo same)"

# ── AC-10.2: the Step-2 and Step-3 cards from their own artifacts ────────────
whole_card step2 "$SPEC_FIX"; S2="$WC_OUT"
expect_eq "53: step2 exits 0 on a well-formed spec artifact" "0" "$WC_RC"
expect_contains "53a: …and opens with the Step-2 title" "Step 2 · Design" "$S2"
expect_contains "54: the Decisions section carries D1 with its serves cell" "D1" "$S2"
expect_contains "54a: …and D1's ADR pointer rather than 'none'" "adr-099-fixture.md" "$S2"
expect_contains "54b: …and D2, whose serves cell is REQ-2" "D2" "$S2"
# T17 (wave-26 D13): Ownership is no longer on the default card — it is the `ownership`
# sub-view. 55/55a read the table's rows from the sub-view; §S2-LABEL owns the pairing.
whole_card step2 "$SPEC_FIX" ownership; S2_OWN="$WC_OUT"
expect_contains "55: the Ownership sub-view carries the spec's own table rows" \
  "owner lib/first.sh" "$S2_OWN"
expect_contains "55a: …and the second concept's test suite" "tests/second.test.sh" "$S2_OWN"
expect_contains "56: the Eval design section counts REQ-1's criteria by type" "REQ-1" "$S2"
expect_contains "56a: …and carries a total row" "total" "$S2"

whole_card step3 "$PLAN_FIX"; S3="$WC_OUT"
expect_eq "58: step3 exits 0 on a well-formed plan artifact" "0" "$WC_RC"
expect_contains "58a: …and opens with the Step-3 title" "Step 3 · Plan" "$S3"
# The ledger cell's FIRST SENTENCE, folded inside the task column like any other
# free cell — so the assertion is against the first chunk, and the sentence the
# card must NOT carry is asserted absent beside it. A card that printed the whole
# ledger cell would pass a `contains` on the opening words and fail here, which
# is the failure worth catching: the ledger cell is a brief, the card is a line.
expect_contains "59: the Tasks section carries T1's text, folded in its column" \
  "REQ-1: the first task" "$S3"
expect_absent "59d: …nor the sentence after the title" "a second sentence" "$S3"
expect_absent "59e: …nor the ledger's own complexity tag" "complexity: standard" "$S3"
expect_contains "59a: …and T1's kind, depends and agent cells" "implementor" "$S3"
expect_contains "59b: …and T2, whose depends cell is T1" "T2" "$S3"
expect_contains "60: Parallel width reads the plan's own writer budget" "8 writers" "$S3"
expect_contains "61: Verification counts the matrix rows" "3 matrix rows" "$S3"

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

# EVERY EMITTED LINE STILL FITS THE BUDGET, ARTIFACTS INCLUDED (T17, retiring
# the exemption below; audit F2, A-orch-34). The Artifacts block used to print
# the artifact path ABSOLUTE, exempted from the width check because a folded or
# truncated path is useless to a reader — and a whole card really did emit a
# 134-column line. `card.sh` now prints that path PROJECT-ROOT-RELATIVE
# (`.bionic/docs/specs/…`, the repo's own citation convention), which is short
# for every REAL Step-1/2/3 artifact — they all live under the project — so the
# exemption is retired for that case and the whole card, Artifacts included, is
# held to the budget.
#
# A path that resolves OUTSIDE the project still prints AS GIVEN (there is no
# folding a path and keeping it something a reader can open — the half of the
# old rationale that survives) and stays UNBOUND by the width invariant, which
# is why the width pin below runs against an in-tree COPY of the three fixture
# artifacts (A-T17.1) rather than the originals above, which are deliberately
# outside the project (this suite's own hermetic-fixture rule) and would still
# overflow on this machine's own $TMPDIR depth — proving nothing about the fix.
. "${REPO}/payload/scripts/lib/root.sh"
CARD_ROOT_FOR_TEST="$(project_root "$PWD")"
mkdir -p "${CARD_ROOT_FOR_TEST}/.bionic/tmp"
CARD_INTREE="$(cd "$(mktemp -d "${CARD_ROOT_FOR_TEST}/.bionic/tmp/card-test-t17.XXXXXX")" && pwd -P)"
card_intree_cleanup() { [ -n "${CARD_INTREE:-}" ] && rm -rf "$CARD_INTREE"; }
cp "$REQ_FIX" "${CARD_INTREE}/wave-99-fixture.requirements.md"
cp "$SPEC_FIX" "${CARD_INTREE}/wave-99-fixture.spec.md"
cp "$PLAN_FIX" "${CARD_INTREE}/wave-99-fixture.plan.md"
whole_card step1 "${CARD_INTREE}/wave-99-fixture.requirements.md"; S1_IT="$WC_OUT"
whole_card step2 "${CARD_INTREE}/wave-99-fixture.spec.md"; S2_IT="$WC_OUT"
whole_card step3 "${CARD_INTREE}/wave-99-fixture.plan.md"; S3_IT="$WC_OUT"

# THE WAVE'S OWN ARTIFACTS: not synthetic — the real requirements/spec/plan this
# very card renders from at every Step-1/2/3 approval gate in this wave, which
# is the case the fix exists for.
# THE STEP-1 ONE IS A COPY THIS SUITE OWNS, written in the tree beside the fixtures above: a real
# run's requirements whole, each requirement given its opening sentence as the card now requires.
# A live file changes under the suite and cannot be given what a newer rule asks of it. Its
# inherited-deferral lines are left out, because they name another run's record and the newest
# continuation they are read against moves with every close.
REAL_REQ="${CARD_INTREE}/wave-44-every-hand.requirements.md"
cat > "$REAL_REQ" <<'W44EOF'
---
governing-skill: agent-skills:idea-refine
sdlc-step: 1
epic: epic-23-bionic-tech-debt
wave: wave-44-every-hand
intent: build
rigor: single
review-cadence: once
fix-policy: S1,S2-on
fix-cap: 2
regression: yes
regression-override: Chris Lehman 2026-10-23 derived=no chosen=yes
scale: task
canonical_sdlc_version: 14
surface_type: cli-plugin
language: bash
has_ui: false
multi_agent: true
deploy_target: n/a
cleanup_on_finish: true
use_worktree: false
walk: required
design-interview: true
model_plan: orchestrator=claude-fable-5-1; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-high; auditor=opus-high; critic=opus-high
archive-root: /Users/admin/bionic-archive
working-branch: wave/44-every-hand
integration-branch: main
base-sha: dd425be64
seed: ideas/bionic-1.27.0-charter.md
source: ideas/bionic-1.27.0-charter.md §Late addition and §Cut · record/wave-44-every-hand/research-sitrep-concept.md · record/wave-44-every-hand/research-sitrep-latency.md · record/wave-44-every-hand/design-ledger.md Δ1, Δ6, Δ7, Δ8
release: 1.27.0
---
# bionic 1.27.0 — the sitrep changes what you do next · requirements

## Goal

A sitrep is the handful of facts that change what the user does next, drawn by code with the model's judgment on top, in well under a minute. Five themes, in the plan's order: the register tells an ask that waits on the user from an item that waits on an event, and only the first can block the user or drive the call; code draws every fact row, the head, the task list, the metrics, Blocked on you and the predicted close, and the model writes seven lines of judgment the check reads; the card says what the wave is for and whether it is on course, first under the Assessment; and the whole takes under thirty seconds of model output; and every card the run puts to the user, requirements, design and plan, prints a name per item and keeps the detail one keystroke away. Accepted when the card drawn on the wave-43 plan and on a fixture shaped like the large-app run reads in the approved mock-up's shape, and three sitreps in a row take under thirty seconds each.

## Context

The run was chartered as the hand-holds measure with the sitrep as a late addition, and cut to the sitrep at the design frame (charter §Cut; ledger Δ8). The cause: a large-app card of 63 rows whose Call to action restated a ruling already given, whose Assessment carried fourteen register items under five points, and whose Blocked on you named a merge that waited on a re-review, not on the user; and a measurement of the sitrep at a median of about 95 seconds, nine tenths of it the model typing and retyping rows that are facts (research-sitrep-latency.md: first judgment 43%, refusal rewrites 34%, retyping the printed card 14%, machine 10%). The concept review (research-sitrep-concept.md) found the card never states what the wave is for: the sheet carries neither the plan's Goal nor the themes' openers, and the Goals row may state only status counts. Chris ruled D7, materiality; D6, code draws the facts; D1, the purpose first under the Assessment; and approved a mock-up (ledger Δ1, Δ6, Δ7). The rulings of waves 38 to 43 that stand: the seven sections in order (w42 Δ0, Δ9), Metrics as numbers only (w42 D2), the grade (w42 D2), the task list as drawn today, bottom line up front (w38 D11), one renderer prints every fact (w38 D9, restored). Reopened on evidence: w42 D1 "2" (the model writes every word) and w42's "every open ask answered once".

## Theme 1 — the register knows what you owe

An ask waits on the user or on an event, and the register says which; only an ask that waits on the user can block the user or drive the call.

### REQ-1 — An ask says what it waits on

Every ask you are shown says whether it waits on you or on something else happening, so you can tell what is really yours.

provenance: charter §Cut (the large-app card's "Blocked on you doesn't seem like it's truly blocked"); sheet-definitions.md (an ask line carries holds= and blocks=, nothing of who it waits on)

- AC-1.1 Every ask on the register reads `waits-on=user` or `waits-on=event <what>`: a decision, an approval and an unanswered waiver wait on the user; a waiver answered "no" waits on the review's next run; a finding carried to a row waits on that row's landing; the sheet's `ask:` line carries the field. Fails when: a refused waiver reads `waits-on=user`, or an ask line lacks the field.
- AC-1.2 A reply of "no" to a waiver, and a finding ruled "carry" or "defer", record the answer on the ask and move it to `waits-on=event` without closing it; the ask closes as it does today, when the review passes or the row lands. Fails when: the answered ask still reads `waits-on=user`, or it closes before its event.

### REQ-2 — Blocked follows waits-on

Only an ask that waits on you and holds up work is shown as blocking you.

provenance: charter §Cut ("the Call to action is vapid"); wave 43 deferral critic-adversarial-2.md#2 (adopted: the handoff head follows the card); debt blocked-on-you (card.sh:3042, sitrep.sh:2123) and blocks-rule (sitrep.sh:1616, card.sh:3139)

- AC-2.1 Blocked on you lists the asks that wait on the user and hold a task, the release or the merge, and nothing else; with none it reads `None` and names the nearest event the run waits on. Fails when: an ask waiting on an event is drawn there, or `None` is drawn while an ask waiting on the user holds the merge.
- AC-2.2 The call may say nothing is owed while every open ask waits on an event, and must name the ask while one waits on the user and holds something; the check reads `waits-on`, not `holds`. Fails when: the check refuses "nothing tonight" over a refused waiver, or admits it over an unanswered one.
- AC-2.3 The handoff head's `Blocked on you`, the sitrep card and the Patrol's `blocks=` read one function, pinned by one suite row that reddens when any two disagree; the `blocks-rule` and `blocked-on-you` duplicates are gone. Fails when: `/usr/bin/grep` finds the rule in two files, or a planted divergence passes.

## Theme 2 — code draws the facts, the model writes the judgment

Every row that is a fact is drawn by the verb; the model writes only what is judgment, and the check reads only that.

### REQ-3 — The verb draws the fact rows

The facts of a sitrep are drawn by code, so the model writes only the judgment on top of them.

provenance: ledger Δ6 (D6 "1"); research-sitrep-latency.md causes 1 to 3; w38 D9 (one renderer prints every fact)

- AC-3.1 `sitrep` prints, beside the sheet, the drawn rows of the head, the Task list (every step and task row as today, its text from the plan's task title and its state words from the sheet), the Metrics table, Blocked on you and the first two lines of Predicted close, so the model writes none of them. Fails when: a task row's text or a metric number must be typed by the model, or a drawn row differs from the sheet fact it is drawn from.
- AC-3.2 The Metrics are a five-line table, Completed, Pace, Correctness, Waste, Goals, each cell one sheet value, numbers only, the pace comparison first in its line. Fails when: a cell holds a number no sheet line holds, or a line is prose.
- AC-3.3 Items that wait on events are one drawn line under the Assessment, counted by kind ("14 items wait on landings, not on you: 8 carried findings, 6 rulings given"), never one row each. Fails when: an ask waiting on an event is drawn as its own row.

### REQ-4 — Seven lines, checked for truth

The judgment on the sitrep card is seven kinds of line, and every number in it is checked against the facts.

provenance: ledger Δ6, Δ7; research-sitrep-latency.md (refusal classes: metric binding 4, row wrap 4, state word 2, reading/reader 2)

- AC-4.1 The judgment the model pipes to `sitrep card` is: `purpose:`, `call:`, `grade:`, one to three `point:` lines, one `ask <key>:` recommendation per ask that waits on the user, and one `close:` condition line; the check refuses any other tag, and refuses a missing one by name. Fails when: a `task:` or `metric:` line is accepted, or a missing `purpose:` draws a card.
- AC-4.2 Every number in a judgment line is bound to the sheet value whose word stands beside it, by word and by place, as the metrics were; a line over the card's width is folded by the renderer, never refused. Fails when: "1 green and 11 red" over "11 green, 1 red" passes, or a long point is refused for its length.
- AC-4.3 The tool shows the card; the skill tells the model to print the tool's output once inside one fenced block and never to retype it, and a refusal prints every reason at once. Fails when: the skill text asks the model to regenerate the card, or the second refusal names a reason the first could have.

### REQ-5 — The skill is the new shape

The sitrep skill describes the new card, so the model writes what the card now asks for.

provenance: ledger Δ6, Δ7; skills/sitrep/SKILL.md (the six questions, the Goals question, "every open ask answered once")

- AC-5.1 `skills/sitrep/SKILL.md` describes the two verbs, the seven judgment lines, the Purpose question in place of the Goals question, and the rule that an ask waiting on an event owes the user nothing; its example judgment is seven lines; `words.test.sh` and the sitrep-card suite's skill section pin it. Fails when: the skill text still asks for `task:` or `metric:` rows, or for every open ask.

## Theme 3 — the card says what the wave is for

The sitrep opens its judgment on what the wave set out to do and whether that is being accomplished, read from the run's own documents, at every scale.

### REQ-6 — The sheet carries the goal

The facts a sitrep reads carry what the wave is for, so its purpose is never guessed.

provenance: charter §Late addition ("reasserting what the wave is doing"); research-sitrep-concept.md Q3; wave 41 D13

- AC-6.1 The sheet carries `run.goal:`, the plan's `## Goal` paragraph, so the purpose is drawn from the verb and never fetched by the model. Fails when: a plan with a Goal paragraph prints no `run.goal:` line, or the line differs from the paragraph.
- AC-6.2 Each theme's `goal:` line carries the theme's opening sentence as its last field, `for=`, with the fields the release card reads kept in place. Fails when: a theme that opens on a sentence prints no `for=`, or the release card's reading of the line changes.

### REQ-7 — The purpose line comes first

The sitrep card opens by saying what the wave is for and whether it is on course.

provenance: charter §Late addition ("whether we're accomplishing the purpose of the wave"); ledger Δ1 (D1 "1")

- AC-7.1 The Assessment's first row is the `purpose:` line, what the wave is for and whether it is on course; a judgment without it is refused, and its numbers are checked against the sheet as every line's are. Fails when: a card draws without it, or a purpose claiming a count the sheet lacks is drawn.

### REQ-8 — Progress per theme on the card

The card shows how far each theme has come, by its name.

provenance: research-sitrep-concept.md Q2, tweaks 3, 5 and 7; 1.26.0 Known limit 23

- AC-8.1 The Goals line of the Metrics states each theme's criteria discharged and open REQs, each number bound to its theme's name; a theme with at least one criterion discharged and none missed reads `on course`, distinct from `not measured`, on the sheet, the sitrep card and the release card. Fails when: a theme at 11 of 12 reads as one at 0 of 12, or "Identity 10 of 11" over a sheet reading 9 of 11 is drawn.
- AC-8.2 At task scale the sheet reads one goal over the whole matrix, the run's criteria discharged and open REQs. Fails when: a task-scale sheet prints no `goal:` line.
- AC-8.3 A goal missed by a red the plan itself declares opens no `decide:goal:<name>` ask. Fails when: the ask opens for a declared red.

## Theme 4 — fast

A sitrep costs the user the time it takes to read it, not the time it takes to write.

### REQ-9 — Under thirty seconds

A sitrep reaches you in under thirty seconds.

provenance: charter §Cut ("Right now this is fucking wasting my time!"); research-sitrep-latency.md (74 to 108 s; model output 90%)

- AC-9.1 Three sitreps run in a row on a live plan, measured from the typed command to the shown card in the transcript as research-sitrep-latency.md measured, each take under 30 seconds, with at most one card refusal among the three. Evidence is the measurement recorded at Step 5. Fails when: one takes 30 seconds or more, or two are refused.
- AC-9.2 The machine side of a sitrep, the sheet and the card together, takes under 5 seconds on the wave-43 plan. Fails when: `time` reads 5 seconds or more.

### REQ-10 — The approved shape is pinned

The card shape you approved is held by a test, so it cannot drift.

provenance: ledger Δ7 (the mock-up Chris approved: "Yes! That is what I want!")

- AC-10.1 A fixture shaped like the large-app card (17 open tasks, 14 items waiting on events, a refused waiver holding the merge, 54 added tasks) draws the mock-up's shape: Call to action one line saying nothing is owed, the Task list as today, a five-line Metrics table, an Assessment of the purpose, at most three points and one counted line, Blocked on you `None` with the event named, Predicted close in three lines; the drawn card is under 40 rows. Fails when: a register item is drawn as a row, the merge reads blocked, or the card exceeds 40 rows.

## Theme 5 — the cards read at a glance

Every card the run puts to the user prints a name per item and keeps the detail one keystroke away, so a card is scanned, not read.

### REQ-11 — The plan card shows titles

The plan card shows each task by a short title, so the table reads at a glance.

provenance: user 2026-10-23 "Each task description is far too long. It's not useful whatsoever. I need a brief summary or phrase that represents what the task is. Maybe 25-30 characters max." and "Yes! That's so much more useful OMG" at the mock-up (ledger Δ13); user 2026-10-23 "you need to do the same thing for the requirements card. Each requirement desc needs to be capped at 30 chars."

- AC-11.1 A `## Tasks` cell opens on a title of at most 30 characters, then a period and the detail; the Step-3 card prints the title alone, `serves` in its own column and consecutive ids in `depends` as a range; `show task <n>` prints the whole cell; the Step-3 text states the rule; a longer title is refused by the card, which names the row and its length, never cut. Fails when: the card prints the detail, or a 31-character title is drawn.

### REQ-12 — The requirements card too

The requirements card shows each requirement by a short title and its count of criteria.

provenance: user 2026-10-23 "Each task description is far too long. It's not useful whatsoever. I need a brief summary or phrase that represents what the task is. Maybe 25-30 characters max." and "Yes! That's so much more useful OMG" at the mock-up (ledger Δ13); user 2026-10-23 "you need to do the same thing for the requirements card. Each requirement desc needs to be capped at 30 chars."

- AC-12.1 A `### REQ-<n> — <title>` heading's title is at most 30 characters; the Step-1 card prints each requirement as its id, its title and its criteria count on one line, the provenance under `explain <requirement>` only; a longer title is refused by the card, which names the requirement and its length, never cut; the Step-1 text states the rule. Fails when: the card prints a provenance, or a 31-character title is drawn.

### REQ-13 — Not Doing in titles

The excluded work on the requirements card is shown by title, one item per line.

provenance: user 2026-10-23 "Not Doing is way too wordy! It needs to be summarized!"

- AC-13.1 Every `## Not Doing` item opens on a title of at most 30 characters, then a colon and the reason; the Step-1 card prints the titles, one per line, and `explain not-doing` prints the items whole; a longer title is refused by the card, naming the item, never cut; the Step-1 text states the rule. Fails when: the card prints a reason, or a 31-character title is drawn.

### REQ-14 — Decisions titled, Risks judged

The design card shows each decision by a short title, and each risk is written as a judgment.

provenance: user 2026-10-23 "Decisions capped to 30 characters"; "the Worth your eye section should probably be called Risks"; "I thought you were summarizing to the material points only"

- AC-14.1 Every `- **D<n> — <title>**` decision title is at most 30 characters; the Step-2 card prints each decision as its id, its title, the requirements it serves and its ADR, `explain <decision>` printing the detail; a longer title is refused by the card, naming the decision, never cut. The spec's `### Worth your eye` section is `### Risks`: each item is the model's own judgment of one risk that could change the user's decision, a sentence or two, and nothing that is not such a risk; drawn whole and folded, with no cap and no required shape; the card accepts the old heading on a spec written before 1.27.0. The Step-2 text states both. Fails when: a 31-character decision title is drawn, a Risks item is cut or refused for its length, or the card's section still reads Worth your eye.

## Not Doing

- The measure work, to 1.28.0: Themes 1 to 4 of the charter and its Known-limit leftovers, the hand-holds window and kinds, every-cell-has-a-verb, the card and the gate reading one fact, the binding outliving the session, and REQ-23 to REQ-34 of this file's first approval, carried whole to `ideas/bionic-1.28.0-charter.md` with their research map and the debt items `tick-idle-width`, `landing-record-parser`, `publish-order` and `arm-at-task-scale`. The debt items `blocks-rule` and `blocked-on-you` burn here under REQ-2.
- Hand-holds as a judge: this run's close is not judged by it; the close reports its reading as it does today, and what the orchestrator types by hand is logged in `assumptions.md` for 1.28.0 to read.
- Reopening the card's rulings: the seven-section order, Metrics as numbers only, the grade and the task list's shape stay; Chris kept them at the mock-up.
- A new section or epic scale: no new sitrep section, and no sitrep at epic scale beyond what the sheet reads today.
- The merge and the tag: the person's, after the pull request (pr dealing).
W44EOF
# THE CARDS READ ARTIFACTS IN THE SHAPE THEY PARSE: a decision bullet carries its `(D<n>; REQ-…)` tag and every title is
# at most 30 characters, so an older run's artifacts are refused (or drew an empty table); the width pins read the newest.
REAL_SPEC="${CARD_ROOT_FOR_TEST}/.bionic/docs/specs/epic-23-bionic-tech-debt/wave-44-every-hand.spec.md"
REAL_PLAN="${CARD_ROOT_FOR_TEST}/.bionic/docs/plans/epic-23-bionic-tech-debt/wave-44-every-hand.plan.md"
whole_card step1 "$REAL_REQ"; S1_REAL="$WC_OUT"; S1_REAL_RC="$WC_RC"
whole_card step2 "$REAL_SPEC"; S2_REAL="$WC_OUT"; S2_REAL_RC="$WC_RC"
whole_card step3 "$REAL_PLAN"; S3_REAL="$WC_OUT"; S3_REAL_RC="$WC_RC"

expect_empty "67: no line of the in-tree Step-1 fixture card exceeds the budget, Artifacts included" \
  "$(over_budget "$S1_IT")"
expect_empty "67a: …nor of the in-tree Step-2 fixture card" "$(over_budget "$S2_IT")"
expect_empty "67b: …nor of the in-tree Step-3 fixture card" "$(over_budget "$S3_IT")"
expect_eq "67c0: precondition: the Step-1 card over the suite's copy of a real run's requirements renders (exit 0, its REQ-1 row present, 14 sentence lines at least)" "0|yes|yes" \
  "$S1_REAL_RC|$(printf '%s\n' "$S1_REAL" | /usr/bin/grep -q '^ *REQ-1 ' && echo yes)|$([ "$(printf '%s\n' "$S1_REAL" | /usr/bin/grep -c '^            [A-Z]')" -ge 14 ] && echo yes)"
expect_eq "67e0: precondition: the Step-3 card over this wave's own plan renders (exit 0, its T1 row present)" "0|yes" \
  "$S3_REAL_RC|$(printf '%s\n' "$S3_REAL" | /usr/bin/grep -q '^ *T1 ' && echo yes)"
expect_empty "67c: nor of the Step-1 card over the suite's copy of a real run's requirements, its sentences included" \
  "$(over_budget "$S1_REAL")"
expect_eq "67d0: precondition: the Step-2 card over the real spec renders (exit 0, its D8 row present)" "0|yes" \
  "$S2_REAL_RC|$(printf '%s\n' "$S2_REAL" | /usr/bin/grep -q '^ *D8 ' && echo yes)"
expect_empty "67d: …nor of the Step-2 card over this wave's own spec" "$(over_budget "$S2_REAL")"
expect_empty "67e: …nor of the Step-3 card over this wave's own plan" "$(over_budget "$S3_REAL")"

# The exemption's surviving half: a path OUTSIDE the project (the original
# system-tmp fixtures, S1 above) still prints AS GIVEN, whole, on ONE line —
# never folded, never elided with the truncator's … — unchanged from before T17.
S1_ART="$(printf '%s\n' "$S1" | grep -F "$REQ_FIX")"
expect_eq "68: an out-of-project artifact path is still printed on exactly one line" "1" \
  "$(printf '%s\n' "$S1_ART" | grep -c . | tr -d ' ')"
expect_eq "68a: …and whole, with nothing elided" "    requirements  ${REQ_FIX}" "$S1_ART"

# AC-9.4's other half: the printed path RESOLVES. Every requirements/spec/plan
# Artifacts line rendered above, joined to the project root when it is not
# already absolute, names a real file — so a renderer that printed a
# plausible-looking but wrong relative path is caught here even on a card that
# never overflows a line. (The `adrs` Artifacts line is a pre-existing,
# DOCS-ROOT-relative citation — spec/plan frontmatter's own convention, unrelated
# to this row — and is excluded.)
artifact_paths() {  # <rendered card> -> the requirements/spec/plan line's path
  printf '%s\n' "$1" | sed -n -e 's/^    \(requirements\|spec\|plan\)  //p'
}
check_artifact_resolves() {  # <label> <rendered card>
  local label="$1" card="$2" p _pass=1 _bad=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      /*) [ -f "$p" ] || { _pass=0; _bad="${_bad}${_bad:+, }${p}"; } ;;
      *)  [ -f "${CARD_ROOT_FOR_TEST}/${p}" ] || { _pass=0; _bad="${_bad}${_bad:+, }${p}"; } ;;
    esac
  done < <(artifact_paths "$card")
  if [ "$_pass" -eq 1 ]; then ok "$label"; else no "$label" "unresolved: $_bad"; fi
}
check_artifact_resolves "68b: the in-tree Step-1 fixture card's Artifacts path resolves to a real file" "$S1_IT"
check_artifact_resolves "68c: …the in-tree Step-2 fixture card's" "$S2_IT"
check_artifact_resolves "68d: …the in-tree Step-3 fixture card's" "$S3_IT"
check_artifact_resolves "68e: …the Step-1 card over the suite's copy of a real run's requirements" "$S1_REAL"
check_artifact_resolves "68f: …the Step-2 card over this wave's own spec" "$S2_REAL"
check_artifact_resolves "68g: …the Step-3 card over this wave's own plan" "$S3_REAL"

section "§KINDS: the release and sitrep kinds draw their cards from the facts their verbs gather"
# fails-when: the release card is drawn anywhere but this renderer, a fact is dropped or reordered on the way, or a
# fact the renderer does not know is drawn as nothing instead of refused. The sitrep kind joins this section with
# the sitrep card.
rel_fact() { local IFS=$'\t'; printf '%s\n' "$*"; }  # <tag> <field>... -> one fact line, its fields tab-separated
rel_card() {  # <facts> — sets WC_OUT, WC_RC, WC_ERR of `card.sh release` with the facts on stdin
  WC_RC=0
  printf '%s\n' "$1" | bash "$CARD_SH" release >"${CARD_SANDBOX}/.out" 2>"${CARD_SANDBOX}/.err" || WC_RC=$?
  WC_OUT="$(cat "${CARD_SANDBOX}/.out" 2>/dev/null)"
  WC_ERR="$(cat "${CARD_SANDBOX}/.err" 2>/dev/null)"
}
REL_FACTS="$(
  rel_fact title proj 1.2.0 'Tuesday 9:05 AM' abcdef12 3 4
  rel_fact criteria 2 0
  rel_fact miss AC-1.2
  rel_fact aside 'a gate the operator owes.'
  rel_fact decision row row:AC-1.2 default 'AC-1.2, not run on this release' waive 'run it' 'waive AC-1.2' 'run AC-1.2'
  rel_fact decision approve approve:release default 'Release 1.2.0' approve withhold release 'hold the release'
  rel_fact reply run
  rel_fact goal reached '✅' 'fast landings' 'one-file median under 15m' '12m'
  rel_fact goal missed '✖️' pages 'a fresh agent answers' 'no record'
  rel_fact handholds 'hand-holds: 0 nudges'
  rel_fact ratio 'test-ratio: 1/2'
  rel_fact acceptance '✖️ acceptance — 1 of 2 criteria proved; 1 not run'
  rel_fact regression '✅ regression — whole run green at this head'
  rel_fact review '✅ evidence — auditor at abcdef12'
  rel_fact findings 1 0 0 1 ''
  rel_fact finding C S3 'a message could be clearer'
)"
REL_WANT='Release approval · proj 1.2.0 · Tuesday 9:05 AM · head abcdef12 · 3 of 4 tasks landed

Bottom line
- Ready for your decisions: every check holds at abcdef12.
- 1 criterion not proved: AC-1.2 (decision 1).
- You owe 2 decisions, listed below. Everything else has a default the record supports.
- Also yours, outside the run: a gate the operator owes.
- Recommended: waive AC-1.2, then release.

Goals — 1 of 2 reached
✅ fast landings — one-file median under 15m, 12m
✖️ pages — a fresh agent answers, no record

hand-holds: 0 nudges
test-ratio: 1/2

Tests
✖️ acceptance — 1 of 2 criteria proved; 1 not run
✅ regression — whole run green at this head

Reviews
✅ evidence — auditor at abcdef12

Findings — 1: 1 carried
Carried as known limits
  S3   a message could be clearer

Decisions
1. AC-1.2, not run on this release — recommended: waive · default: waive
2. Release 1.2.0 — recommended: approve · default: approve

Reply "all recommended", "all default", or by number, as "1 run, rest default".'
rel_card "$REL_FACTS"
expect_eq "KINDS-1 card.sh release renders the facts (exit 0, nothing on stderr)" "0|" "$WC_RC|$WC_ERR"
expect_eq "KINDS-2 …the release approval card, every section in its order and every fact in its place" "$REL_WANT" "$WC_OUT"
rel_card "$REL_FACTS
$(rel_fact preview)"
expect_eq "KINDS-3 a preview fact ends the card on the preview line instead of the reply line" \
  "Preview only: nothing is recorded, and reply cannot act on it." "$(printf '%s\n' "$WC_OUT" | tail -1)"
rel_card "$REL_FACTS
$(rel_fact verdict maybe)"
expect_eq "KINDS-4 a fact the renderer does not know refuses the card: exit 64, nothing drawn" "64|" "$WC_RC|$WC_OUT"
expect_contains "KINDS-4b …naming the fact" "unknown release fact 'verdict'" "$WC_ERR"
rel_card "$(printf '%s\n' "$REL_FACTS" | /usr/bin/grep -v '^title')"
expect_eq "KINDS-5 facts with no title refuse the card: exit 64, nothing drawn" "64|" "$WC_RC|$WC_OUT"
# The release-approval verb hands its facts to this renderer; its own page renderer is gone.
KINDS_HIT="$(cd "$REPO" && /usr/bin/grep -rln 'card.sh" release' hooks payload 2>/dev/null)"
expect_eq "KINDS-6 precondition: the release-approval verb calls the release kind" "hooks/poker/plan.sh" "$KINDS_HIT"
expect_eq "KINDS-6b …and no shipped file defines or calls rr_page" "" \
  "$(cd "$REPO" && /usr/bin/grep -rn 'rr_page' hooks payload 2>/dev/null)"
expect_eq "KINDS-6c …and the release path folds through no sitrep_fold" "" \
  "$(/usr/bin/grep -n 'sitrep_fold' "$REPO/hooks/poker/plan.sh" 2>/dev/null)"
# The sitrep kind: the sheet is a file the verb names, the judgment comes on stdin. The full card and its check are
# tests/sitrep-card.test.sh's; this holds that the kind is this renderer's and that no second fold is left.
SIT_SHEET='sheet/v1 — facts for the model; the user sees the card, never this sheet
run.release: 1.2.0
run.wave: 3
run.now: Tuesday 9:05 AM
run.project: proj
step: n=0 name=Configure state=done tasks=0
step: n=1 name=Scope state=running tasks=1
task: id=T1 step=1 state=running desc=the scope note=building
work.landed: 0 tasks, 0 of 1 min, 0% — the tasks landed · unit: count, sized minutes, % of them · source: the rows with status landed
work.left: 1 task, 1 min — the tasks neither landed nor dropped · unit: count, sized minutes · source: the remaining rows
close.predicted: 11:00 AM
close.forecast: -'
SIT_JUDGE='purpose: the scope is set before the build; on course.
call: Nothing is owed; let 1/1 land.
grade: A
point: The one task is building.
point: Nothing has landed yet.
point: The scope is the only open step.
close: depends on 1/1 landing.'
sit_card() {  # <sheet> <judgment> — sets WC_OUT, WC_RC, WC_ERR of `card.sh sitrep <sheet file>` with the judgment on stdin
  printf '%s\n' "$1" > "${CARD_SANDBOX}/.sheet"
  WC_RC=0
  printf '%s\n' "$2" | bash "$CARD_SH" sitrep "${CARD_SANDBOX}/.sheet" >"${CARD_SANDBOX}/.out" 2>"${CARD_SANDBOX}/.err" || WC_RC=$?
  WC_OUT="$(cat "${CARD_SANDBOX}/.out" 2>/dev/null)"
  WC_ERR="$(cat "${CARD_SANDBOX}/.err" 2>/dev/null)"
}
sit_card "$SIT_SHEET" "$SIT_JUDGE"
expect_eq "KINDS-7 card.sh sitrep draws the sitrep card from a sheet and a judgment (exit 0, nothing on stderr)" \
  "0||Sitrep · proj 1.2.0 · wave 3 · Tuesday 9:05 AM" "$WC_RC|$WC_ERR|$(printf '%s\n' "$WC_OUT" | head -1)"
expect_eq "KINDS-7b …its last section the predicted close: the sheet's time drawn, then the judgment's condition, opening on a capital" "  Predicted close|    • 11:00 AM.|    • Depends on 1/1 landing." \
  "$(printf '%s\n' "$WC_OUT" | tail -3 | paste -sd'|' -)"
WC_RC=0; bash "$CARD_SH" sitrep </dev/null >"${CARD_SANDBOX}/.out" 2>/dev/null || WC_RC=$?
expect_eq "KINDS-7c card.sh sitrep with no sheet file is the usage error, nothing drawn" "64|" "$WC_RC|$(cat "${CARD_SANDBOX}/.out")"
KINDS_SIT="$(cd "$REPO" && /usr/bin/grep -rln 'card.sh" sitrep' hooks payload 2>/dev/null)"
expect_eq "KINDS-8 precondition: the sitrep verb calls the sitrep kind" "hooks/poker/sitrep.sh" "$KINDS_SIT"
expect_eq "KINDS-8b …and no shipped file defines or calls sitrep_fold, the sitrep's own fold" "" \
  "$(cd "$REPO" && /usr/bin/grep -rn 'sitrep_fold' hooks payload 2>/dev/null)"

section "§WIDTH: every line of the release, sitrep and Step cards fits the shared width, and the release and sitrep cards fold at it"
# fails-when: a line exceeds BIONIC_LINE_WIDTH, or the release card folds a line that fits it (the old fold at 92).
REL_FIT="✅ evidence — auditor at abcdef12"
while [ "$(cols "$REL_FIT")" -lt "$(( BIONIC_LINE_WIDTH - 3 ))" ]; do REL_FIT="$REL_FIT x"; done
REL_LONG="a finding sentence that runs well past the shared width of the card, so the renderer must fold it under its own severity code and keep going"
rel_card "$REL_FACTS
$(rel_fact review "$REL_FIT")
$(rel_fact finding C S2 "$REL_LONG")"
expect_eq "WIDTH-0 precondition: the wide facts render (exit 0) and the fitting line is wider than 92 columns" "0|yes" \
  "$WC_RC|$([ "$(cols "$REL_FIT")" -gt 92 ] && echo yes)"
expect_eq "WIDTH-1 a line that fits the shared width prints whole on one line" "1" \
  "$(printf '%s\n' "$WC_OUT" | /usr/bin/grep -cxF "$REL_FIT")"
REL_FOLD="$(printf '%s\n' "$WC_OUT" | awk '/^  S2   a finding/ { f = 1; print; next } f && /^       [^ ]/ { print; next } { f = 0 }')"
expect_eq "WIDTH-2 a line wider than the width folds under its severity code, its words all kept" \
  "$REL_LONG" "$(printf '%s\n' "$REL_FOLD" | sed 's/^  S2   //; s/^       //' | paste -sd' ' -)"
expect_eq "WIDTH-2b …on more than one line" "yes" "$([ "$(printf '%s\n' "$REL_FOLD" | /usr/bin/grep -c .)" -gt 1 ] && echo yes)"
expect_empty "WIDTH-3 no line of the release card exceeds the width" "$(over_budget "$WC_OUT")"
expect_empty "WIDTH-4 nor of the Step-1, Step-2 and Step-3 cards" "$(over_budget "$S1_IT
$S2_IT
$S3_IT")"
SIT_FIT="Let T1 land"
while [ "$(cols "    • $SIT_FIT")" -lt "$(( BIONIC_LINE_WIDTH - 2 ))" ]; do SIT_FIT="$SIT_FIT x"; done
SIT_LONG="A call that runs well past the shared width of the card, so the renderer folds it under its own text and keeps every one of its words"
sit_card "$SIT_SHEET" "$SIT_JUDGE
call: $SIT_FIT
call: $SIT_LONG"
expect_eq "WIDTH-6 precondition: the wide sitrep judgment renders (exit 0) and its fitting row is wider than 92 columns" "0|yes" \
  "$WC_RC|$([ "$(cols "    • $SIT_FIT")" -gt 92 ] && echo yes)"
expect_eq "WIDTH-6b a sitrep row that fits the shared width prints whole on one line" "1" \
  "$(printf '%s\n' "$WC_OUT" | /usr/bin/grep -cxF "    • $SIT_FIT")"
SIT_FOLD="$(printf '%s\n' "$WC_OUT" | awk '/^    • A call that/ { f = 1; print; next } f && /^      [^ ]/ { print; next } { f = 0 }')"
expect_eq "WIDTH-6c a wider one folds under its own text, six columns in, its words all kept" \
  "$SIT_LONG" "$(printf '%s\n' "$SIT_FOLD" | sed 's/^    • //; s/^      //' | paste -sd' ' -)"
expect_eq "WIDTH-6d …on more than one line" "yes" "$([ "$(printf '%s\n' "$SIT_FOLD" | /usr/bin/grep -c .)" -gt 1 ] && echo yes)"
expect_empty "WIDTH-6e no line of the sitrep card exceeds the width" "$(over_budget "$WC_OUT")"
expect_nonempty "WIDTH-5 precondition: the renderer folds at the shared width" \
  "$(/usr/bin/grep -n 'BIONIC_LINE_WIDTH' "$CARD_SH")"
expect_eq "WIDTH-5b …and holds no 92" "" "$(/usr/bin/grep -nw '92' "$CARD_SH")"

card_intree_cleanup

# ============================================================
section "§CONTENT: the Step-2 card's shape follows what the spec holds, never the scale (wave-43 D11; REQ-13 AC-13.2)"
# ============================================================
# Wave 42 and wave 43 both wrote a wave-shaped spec at task scale, and the renderer drew the
# paragraph card for it, since one line keyed the shape on `scale:`. The decisions and the eval
# counts the user was approving never reached the card, and wave 42 drew them by hand (A-orch.8).
# The rule now: a spec that holds decision rows or an eval table gets the full card and its
# sub-views, whatever the scale; a spec that holds neither keeps the paragraph card, the
# task-scale form. An ADR line naming several decisions, `(D1; D2; REQ-1)`, credits each.
# fails-when: the dispatch keys on CARD_SCALE alone (CONTENT-2 to CONTENT-4, CONTENT-6), or
# flush_adr takes only the first D of a group (CONTENT-5).
TASK_SPEC="${CARD_SANDBOX}/wave-98-task.spec.md"
sed -e 's/^sdlc-step: 2$/sdlc-step: 2\nscale: task/' \
    -e 's/`adrs\/epic-99\/adr-099-fixture.md` (D1)\./`adrs\/epic-99\/adr-099-fixture.md` (D1; D2; REQ-1)./' \
    "$SPEC_FIX" > "$TASK_SPEC"
expect_contains "CONTENT-0 precondition: the task spec declares scale: task" "scale: task" "$(cat "$TASK_SPEC")"
expect_contains "CONTENT-0b precondition: its ADR line names D1 and D2" "(D1; D2; REQ-1)" "$(cat "$TASK_SPEC")"
whole_card step2 "$TASK_SPEC"; S2_TASK="$WC_OUT"
expect_eq "CONTENT-1 step2 exits 0 on a task-scale spec that holds decisions and evals" "0" "$WC_RC"
expect_contains "CONTENT-2 …and the card carries the Decisions section with D1" "D1" "$(printf '%s\n' "$S2_TASK" | sed -n '/^  Decisions/,/^  Eval design/p')"
expect_contains "CONTENT-2b …and D2" "D2" "$(printf '%s\n' "$S2_TASK" | sed -n '/^  Decisions/,/^  Eval design/p')"
expect_contains "CONTENT-3 …and the Eval design section with its total row" "total" "$(printf '%s\n' "$S2_TASK" | sed -n '/^  Eval design/,/^  Artifacts/p')"
expect_contains "CONTENT-4 …and the sub-view line, since the content is there to show" "show evals <req>" "$S2_TASK"
expect_eq "CONTENT-5 an ADR line naming D1 and D2 credits both decisions with the ADR" "2" \
  "$(printf '%s\n' "$S2_TASK" | sed -n '/^  Decisions/,/^  Eval design/p' | /usr/bin/grep -c 'adr-099-fixture.md')"
whole_card step2 "$TASK_SPEC" ownership
expect_eq "CONTENT-6 the ownership sub-view is offered on that spec too" "0" "$WC_RC"
expect_contains "CONTENT-6b …and carries the table's rows" "lib/first.sh" "$WC_OUT"
PARA_SPEC="${CARD_SANDBOX}/wave-97-para.spec.md"
cat > "$PARA_SPEC" <<'FIXEOF'
---
sdlc-step: 2
scale: task
working-branch: wave/97-para
integration-branch: main
base-sha: abc1234
---

# fixture wave 97 · spec

## Goal

One small thing, designed in a paragraph.

## Design

The one thing lives in one file and is read by one caller; nothing else changes.
FIXEOF
whole_card step2 "$PARA_SPEC"; S2_PARA="$WC_OUT"
expect_eq "CONTENT-7 a task-scale spec holding neither decisions nor evals still exits 0" "0" "$WC_RC"
expect_contains "CONTENT-7b …and draws the paragraph card" "The one thing lives in one file" "$S2_PARA"
expect_eq "CONTENT-7c …with no Decisions section and no sub-view line" "" \
  "$(printf '%s\n' "$S2_PARA" | /usr/bin/grep -e '^  Decisions' -e 'show evals')"
whole_card step2 "$PARA_SPEC" ownership
expect_eq "CONTENT-7d …and refuses the sub-view, as before" "2" "$WC_RC"


# ============================================================
section "§TITLES: a Tasks cell opens on a title of at most 30 characters, and the Step-3 card prints the title alone"
# ============================================================
# fails-when: the card prints the detail after the title, the serves column is not its own, consecutive ids in depends
# print one by one, `task <n>` prints less than the whole cell, a 31-character title is drawn or cut, or the Step-3
# text lacks the rule.
# The names below are invented; a fixture never carries a real project, client or person.
T30="Title of exactly thirty chars!"
T31="A title that is thirty-one long"
T30_EM="Thirty — characters — in title"
expect_eq "TITLES-0 precondition: the boundary title is 30 characters and the over-long one is 31" "30|31" "${#T30}|${#T31}"
expect_eq "TITLES-0b precondition: the dashed title is 30 characters and more than 30 bytes" "30|yes" \
  "$(cols "$T30_EM")|$([ "$(printf '%s' "$T30_EM" | wc -c | tr -d ' ')" -gt 30 ] && echo yes)"
TITLES_PLAN="${CARD_SANDBOX}/wave-02-flock.plan.md"
cat > "$TITLES_PLAN" <<FIXEOF
---
sdlc-step: 3
walk: required
rigor: single
parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=user
working-branch: wave/02-flock
integration-branch: main
base-sha: abc1234
---

# flock wave 2 · plan

## Goal

Land the flock app's six tasks so the Step-3 card has a ledger to read.

## SDLC State

integration-branch: main
current: 4

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | Parse the ledger. DETAIL-ALPHA the parser reads the table and nothing else, so a later row cannot change it. complexity: standard | implementor | — | 30 | REQ-1 | lib/a.sh | — | pending |
| T2 | 4 | build | ${T30}. DETAIL-BETA the boundary title is drawn whole. complexity: standard | implementor | — | 30 | REQ-1, REQ-2 | lib/b.sh | — | pending |
| T3 | 4 | build | ${T30_EM}. DETAIL-GAMMA a title of thirty characters with dashes in it. complexity: standard | implementor | — | 30 | REQ-2 | lib/c.sh | — | pending |
| T4 | 4 | build | Join the rows. DETAIL-DELTA joins what T1 parsed. complexity: complex | senior-implementor | T1, T3 | 45 | REQ-2 | lib/d.sh | — | pending |
| T5 | 5 | test | Prove the join. DETAIL-EPSILON runs after the four. complexity: standard | implementor | T1, T2, T3, T4 | 45 | REQ-2 | tests/d.test.sh | — | pending |
| T6 | 5 | test | Prove the pair. DETAIL-ZETA runs after two. complexity: standard | implementor | T1, T2 | 45 | REQ-1 | tests/e.test.sh | — | pending |

## Verification Matrix

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1.1 | T0 | pending | — | — |
FIXEOF
whole_card step3 "$TITLES_PLAN"; TT="$WC_OUT"
expect_eq "TITLES-1 step3 draws a plan whose cells open on titles of at most 30 characters, silently" "0|" "$WC_RC|$WC_ERR"
expect_contains "TITLES-2 each task row opens on its title" "Parse the ledger" "$TT"
expect_contains "TITLES-3 a title of exactly 30 characters is drawn whole" "$T30" "$TT"
expect_contains "TITLES-3b …and so is a 30-character title that is more than 30 bytes (characters are counted, not bytes)" "$T30_EM" "$TT"
expect_eq "TITLES-4 no detail after a title is on the card" "" "$(printf '%s\n' "$TT" | /usr/bin/grep -e DETAIL- -e 'complexity:' -e 'the parser reads')"
TT_HDR="$(printf '%s\n' "$TT" | /usr/bin/grep '^  Tasks')"
TT_T1="$(printf '%s\n' "$TT" | /usr/bin/grep '^    T1 ')"
TT_T2="$(printf '%s\n' "$TT" | /usr/bin/grep '^    T2 ')"
expect_eq "TITLES-5 serves is a column of its own: the header names it and T1's REQ-1 starts under it" "yes" \
  "$([ -n "$TT_HDR" ] && [ "$(awk -v h="$TT_HDR" -v r="$TT_T1" 'BEGIN { print (index(h, "serves") == index(r, "REQ-1")) }')" = 1 ] && echo yes)"
expect_contains "TITLES-5b …and a row serving two requirements lists both there" "REQ-1, REQ-2" "$TT_T2"
expect_eq "TITLES-5c …before kind, depends and agent, which keep their columns" "yes" \
  "$(awk -v h="$TT_HDR" 'BEGIN { print (index(h, "serves") < index(h, "kind") && index(h, "kind") < index(h, "depends") && index(h, "depends") < index(h, "agent")) }' | sed 's/^1$/yes/')"
expect_contains "TITLES-6 four consecutive ids in depends print as a range" "T1–T4" "$(printf '%s\n' "$TT" | /usr/bin/grep '^    T5 ')"
expect_eq "TITLES-6b …and not one by one" "" "$(printf '%s\n' "$TT" | /usr/bin/grep '^    T5 ' | /usr/bin/grep 'T1, T2')"
expect_contains "TITLES-7 a run of two prints both ids" "T1, T2" "$(printf '%s\n' "$TT" | /usr/bin/grep '^    T6 ')"
expect_absent "TITLES-7b …with no range" "T1–T2" "$(printf '%s\n' "$TT" | /usr/bin/grep '^    T6 ')"
expect_contains "TITLES-7c ids that are not consecutive stay as written" "T1, T3" "$(printf '%s\n' "$TT" | /usr/bin/grep '^    T4 ')"
expect_empty "TITLES-8 no line of the card exceeds the width, the out-of-project artifact path aside" "$(over_budget "$(printf '%s\n' "$TT" | /usr/bin/grep -v '^    plan  ')")"
expect_contains "TITLES-8b the footer still offers the sub-views" "show evals <req> · show task <n> · explain <decision>" "$TT"

whole_card step3 "$TITLES_PLAN" task 1; TT_V="$WC_OUT"
expect_eq "TITLES-9 show task 1 exits 0" "0" "$WC_RC"
expect_contains "TITLES-9b …and prints the title" "Parse the ledger" "$TT_V"
expect_contains "TITLES-9c …and the whole cell, the detail and the tag too" "DETAIL-ALPHA the parser reads the table and nothing else, so a later row cannot change it. complexity: standard" \
  "$(printf '%s\n' "$TT_V" | sed -e 's/^ *//' | paste -sd' ' -)"
expect_empty "TITLES-9d …folded inside the width" "$(over_budget "$TT_V")"
expect_absent "TITLES-9e …and no other task's cell" "DETAIL-BETA" "$TT_V"
whole_card step3 "$TITLES_PLAN" task T4; TT_V4="$WC_OUT"
expect_contains "TITLES-9f the id may be given with its letter" "DETAIL-DELTA" "$TT_V4"
whole_card step3 "$TITLES_PLAN" task 99
expect_eq "TITLES-9g a task the plan lacks exits 2 and prints nothing on stdout" "2|" "$WC_RC|$WC_OUT"

# A 31-character title, and a second offender, in one plan: both named, no card drawn, nothing cut.
TITLES_BAD="${CARD_SANDBOX}/wave-03-flock.plan.md"
sed -e "s/^| T3 | 4 | build | ${T30_EM}\./| T3 | 4 | build | ${T31}./" \
    -e 's/Prove the pair\. DETAIL-ZETA/Prove the pair of rows is right. DETAIL-ZETA/' "$TITLES_PLAN" > "$TITLES_BAD"
whole_card step3 "$TITLES_BAD"; TB_OUT="$WC_OUT"; TB_ERR="$WC_ERR"; TB_RC="$WC_RC"
expect_eq "TITLES-10 a plan with a 31-character title is refused: exit 1, no card on stdout" "1|" "$TB_RC|$TB_OUT"
expect_contains "TITLES-10b …naming the row, the length, the cap and the title whole" \
  "REFUSED — task T3: title is 31 characters, the cap is 30: ${T31}" "$TB_ERR"
expect_contains "TITLES-10c …and every other offender in the same refusal" \
  "REFUSED — task T6: title is 31 characters, the cap is 30: Prove the pair of rows is right" "$TB_ERR"
expect_eq "TITLES-10d …on two lines and no more" "2" "$(printf '%s\n' "$TB_ERR" | /usr/bin/grep -c .)"
expect_absent "TITLES-10e …and no title cut or ellipsised" "…" "$TB_ERR"
whole_card step3 "$TITLES_BAD" task 1
expect_eq "TITLES-10f the sub-view is refused with the card" "1|" "$WC_RC|$WC_OUT"
expect_eq "TITLES-11 the Step-3 text and its template each state the rule once" "1|1" \
  "$(/usr/bin/grep -c 'title of at most 30' "${REPO}/skills/canonical-sdlc/steps/3.md")|$(/usr/bin/grep -c 'title of at most 30' "${REPO}/agents-src/templates/skills/canonical-sdlc/steps/3.md.tmpl")"

# ============================================================
section "§REQ-TITLES: a requirement heading carries a title of at most 30 characters, and the Step-1 card prints id, title and count"
# ============================================================
# fails-when: the card prints a provenance or a criterion, the count is wrong, `explain <requirement>` lacks the
# provenance, a 31-character title is drawn, or the Step-1 text lacks the rule.
RT_REQ="${CARD_SANDBOX}/wave-04-flock.requirements.md"
cat > "$RT_REQ" <<FIXEOF
---
sdlc-step: 1
working-branch: wave/04-flock
integration-branch: main
base-sha: abc1234
---

# flock wave 4 · requirements

## Goal

Ship the flock app's two requirements so the Step-1 card has titles to draw.

## Not Doing

- Nothing else: this fixture holds no excluded work.

## Requirements and acceptance criteria

### REQ-1 — ${T30}

Two phones that meet show the same list afterwards.

provenance: user 2026-09-16 "PROV-ALPHA the flock must sync"
- AC-1.1 The flock syncs when two phones meet. Fails when: the second phone shows a stale list.
- AC-1.2 A conflict keeps both edits and says so,
  on one line. Fails when: an edit is dropped.
- AC-1.3 The sync is quiet. Fails when: it prompts.

### REQ-2 — Short title

The second requirement holds as well.

provenance: report §4 PROV-BETA
- AC-2.1 The only criterion here. Fails when: it does not hold.
FIXEOF
whole_card step1 "$RT_REQ"; RT="$WC_OUT"
expect_eq "REQ-TITLES-1 step1 draws a requirements file whose titles are within the cap, silently" "0|" "$WC_RC|$WC_ERR"
RT_R1="$(printf '%s\n' "$RT" | /usr/bin/grep '^    REQ-1 ')"
expect_eq "REQ-TITLES-2 a requirement prints its id, its title and its criteria count on one line" \
  "    REQ-1   ${T30}  ACs 3" "$RT_R1"
expect_eq "REQ-TITLES-2b …and the second likewise, its count in the same column" "    REQ-2   $(printf '%-30s' 'Short title')  ACs 1" \
  "$(printf '%s\n' "$RT" | /usr/bin/grep '^    REQ-2 ')"
expect_eq "REQ-TITLES-3 the card prints no provenance and no criterion" "" \
  "$(printf '%s\n' "$RT" | /usr/bin/grep -e 'PROV-' -e provenance -e 'The flock syncs' -e 'Fails when')"
expect_empty "REQ-TITLES-3b no line of the card exceeds the width, the out-of-project artifact path aside" "$(over_budget "$(printf '%s\n' "$RT" | /usr/bin/grep -v '^    requirements  ')")"
expect_contains "REQ-TITLES-3c the footer offers explain for a requirement and for Not Doing" \
  "explain <requirement> · explain not-doing" "$RT"
whole_card step1 "$RT_REQ" explain REQ-1; RT_E="$WC_OUT"
expect_eq "REQ-TITLES-4 explain REQ-1 exits 0" "0" "$WC_RC"
expect_contains "REQ-TITLES-4b …and prints the title" "$T30" "$RT_E"
expect_contains "REQ-TITLES-4c …and the provenance whole" 'user 2026-09-16 "PROV-ALPHA the flock must sync"' \
  "$(printf '%s\n' "$RT_E" | sed -e 's/^ *//' | paste -sd' ' -)"
expect_contains "REQ-TITLES-4d …and every criterion, a wrapped one joined" "A conflict keeps both edits and says so, on one line. Fails when: an edit is dropped." \
  "$(printf '%s\n' "$RT_E" | sed -e 's/^ *//' | paste -sd' ' -)"
expect_absent "REQ-TITLES-4e …and nothing of the other requirement" "PROV-BETA" "$RT_E"
expect_empty "REQ-TITLES-4f …folded inside the width" "$(over_budget "$RT_E")"
whole_card step1 "$RT_REQ" explain 2
expect_contains "REQ-TITLES-4g the bare number names a requirement too" "PROV-BETA" "$WC_OUT"
whole_card step1 "$RT_REQ" explain REQ-9
expect_eq "REQ-TITLES-4h a requirement the file lacks exits 2 and prints nothing on stdout" "2|" "$WC_RC|$WC_OUT"

RT_BAD="${CARD_SANDBOX}/wave-05-flock.requirements.md"
sed -e "s/^### REQ-2 — Short title/### REQ-2 — ${T31}/" "$RT_REQ" > "$RT_BAD"
whole_card step1 "$RT_BAD"
expect_eq "REQ-TITLES-5 a 31-character requirement title is refused: exit 1, no card on stdout" "1|" "$WC_RC|$WC_OUT"
expect_contains "REQ-TITLES-5b …naming the requirement, the length, the cap and the title whole" \
  "REFUSED — requirement REQ-2: title is 31 characters, the cap is 30: ${T31}" "$WC_ERR"
whole_card step1 "$RT_BAD" explain REQ-1
expect_eq "REQ-TITLES-5c …and the sub-view is refused with it" "1|" "$WC_RC|$WC_OUT"
expect_eq "REQ-TITLES-6 the Step-1 text and its template each state the rule on one line" "1|1" \
  "$(/usr/bin/grep -c 'at most 30' "${REPO}/skills/canonical-sdlc/steps/1.md")|$(/usr/bin/grep -c 'at most 30' "${REPO}/agents-src/templates/skills/canonical-sdlc/steps/1.md.tmpl")"

# ============================================================
section "§NOT-DOING-TITLES: a Not Doing item opens on a title and a colon, and the card prints the titles"
# ============================================================
# fails-when: the card prints a reason, `explain not-doing` prints less than the items, a 31-character title is drawn,
# or the Step-1 text lacks the rule.
ND_REQ="${CARD_SANDBOX}/wave-06-flock.requirements.md"
sed -e '/^- Nothing else: this fixture holds no excluded work\.$/d' "$RT_REQ" > "$ND_REQ"
awk '{ print } /^## Not Doing$/ { print ""
  print "- Offline mode: ND-REASON-ALPHA the flock only syncs when two phones are in range, so no queue is kept."
  print "  A second line of the same reason, ND-REASON-BETA."
  print "- Group chat: ND-REASON-GAMMA out of scope."
  print "- Short item without a reason" }' "$ND_REQ" > "${ND_REQ}.n" && mv "${ND_REQ}.n" "$ND_REQ"
whole_card step1 "$ND_REQ"; NT="$WC_OUT"
NT_BLOCK="$(printf '%s\n' "$NT" | sed -n '/^  Not Doing$/,/^$/p')"
expect_eq "NOT-DOING-TITLES-1 step1 draws, silently" "0|" "$WC_RC|$WC_ERR"
expect_eq "NOT-DOING-TITLES-2 the Not Doing block is each item's title on a line of its own" \
  "  Not Doing
    Offline mode
    Group chat
    Short item without a reason
" "${NT_BLOCK}
"
expect_eq "NOT-DOING-TITLES-3 no reason is on the card" "" "$(printf '%s\n' "$NT" | /usr/bin/grep -e ND-REASON -e 'only syncs' -e 'out of scope')"
whole_card step1 "$ND_REQ" explain not-doing; NT_E="$WC_OUT"
NT_E_FLAT="$(printf '%s\n' "$NT_E" | sed -e 's/^ *//' | paste -sd' ' -)"
expect_eq "NOT-DOING-TITLES-4 explain not-doing exits 0" "0" "$WC_RC"
expect_contains "NOT-DOING-TITLES-4b …and prints the first item whole, its wrapped line joined" \
  "Offline mode: ND-REASON-ALPHA the flock only syncs when two phones are in range, so no queue is kept. A second line of the same reason, ND-REASON-BETA." "$NT_E_FLAT"
expect_contains "NOT-DOING-TITLES-4c …and the second whole" "Group chat: ND-REASON-GAMMA out of scope." "$NT_E_FLAT"
expect_empty "NOT-DOING-TITLES-4d …folded inside the width" "$(over_budget "$NT_E")"

ND_BAD="${CARD_SANDBOX}/wave-07-flock.requirements.md"
sed -e "s/^- Group chat: ND-REASON-GAMMA/- ${T31}: ND-REASON-GAMMA/" "$ND_REQ" > "$ND_BAD"
whole_card step1 "$ND_BAD"
expect_eq "NOT-DOING-TITLES-5 a 31-character title is refused: exit 1, no card on stdout" "1|" "$WC_RC|$WC_OUT"
expect_contains "NOT-DOING-TITLES-5b …naming the item, the length and the title whole" \
  "REFUSED — not-doing 2: title is 31 characters, the cap is 30: ${T31}" "$WC_ERR"
ND_NOCOLON="${CARD_SANDBOX}/wave-08-flock.requirements.md"
sed -e "s/^- Short item without a reason$/- ${T31} and no colon after it/" "$ND_REQ" > "$ND_NOCOLON"
whole_card step1 "$ND_NOCOLON"
expect_contains "NOT-DOING-TITLES-5c an item with no colon is all title, and refused when it is over the cap" \
  "REFUSED — not-doing 3: title is 53 characters, the cap is 30: ${T31} and no colon after it" "$WC_ERR"
expect_eq "NOT-DOING-TITLES-6 the Step-1 text states the colon rule" "1|1" \
  "$(/usr/bin/grep -c '<title>: <reason>' "${REPO}/skills/canonical-sdlc/steps/1.md")|$(/usr/bin/grep -c '<title>: <reason>' "${REPO}/agents-src/templates/skills/canonical-sdlc/steps/1.md.tmpl")"

# ============================================================
section "§SENTENCE: a requirement opens on its sentence, and the Step-1 card prints it under the row"
# ============================================================
# fails-when: a requirement with no opening paragraph renders, one whose paragraph carries a backtick renders, the
# refusal does not name the requirement, the sentence is missing from under its row, cut, or folded inside the title
# column, or the row's own line changes.
SN_SHORT="The flock keeps one list on every phone that has met another."
SN_LONG="Two people who edit the same list while apart both keep their edits when their phones meet again, and each of them is told which edits came from the other phone, so nothing they typed is ever silently lost in the merge."
SN_REQ="${CARD_SANDBOX}/wave-10-flock.requirements.md"
cat > "$SN_REQ" <<FIXEOF
---
sdlc-step: 1
working-branch: wave/10-flock
integration-branch: main
base-sha: abc1234
---

# flock wave 10 · requirements

## Goal

Ship the flock app's two requirements so the Step-1 card has sentences to draw.

## Not Doing

- Nothing else: this fixture holds no excluded work.

## Requirements and acceptance criteria

### REQ-1 — The flock keeps one list

${SN_SHORT}

provenance: user 2026-10-24 "PROV-ALPHA the flock must sync"
- AC-1.1 The flock syncs when two phones meet. Fails when: the second phone shows a stale list.

### REQ-2 — Short title

Two people who edit the same list while apart both keep their edits when their phones meet again,
and each of them is told which edits came from the other phone, so nothing they typed is ever
silently lost in the merge.

provenance: report §4 PROV-BETA
- AC-2.1 The only criterion here. Fails when: it does not hold.
- AC-2.2 A second criterion. Fails when: it does not hold.
FIXEOF
whole_card step1 "$SN_REQ"; SN="$WC_OUT"
expect_eq "SENTENCE-1 step1 draws a requirements file whose requirements open on their sentences, silently" "0|" "$WC_RC|$WC_ERR"
SN_BLOCK="$(printf '%s\n' "$SN" | sed -n '/^  Requirements$/,/^$/p')"
# The extractor is proved on the card first: the row line is found, so the line after it is read from a real block.
expect_eq "SENTENCE-2 the row keeps its id, its title and its count on its own line" \
  "    REQ-1   $(printf '%-30s' 'The flock keeps one list')  ACs 1" "$(printf '%s\n' "$SN_BLOCK" | /usr/bin/grep '^    REQ-1 ')"
expect_eq "SENTENCE-2b …and the line under it is the requirement's sentence, indented past the id" \
  "            ${SN_SHORT}" "$(printf '%s\n' "$SN_BLOCK" | awk '/^    REQ-1 / { getline; print; exit }')"
SN_R2="$(printf '%s\n' "$SN_BLOCK" | awk '/^    REQ-2 / { on = 1; next } on && /^    REQ-/ { exit } on && NF { print }')"
expect_eq "SENTENCE-3 a long sentence folds onto more than one line, every line indented past the id" "yes|0" \
  "$([ "$(printf '%s\n' "$SN_R2" | /usr/bin/grep -c .)" -gt 1 ] && echo yes)|$(printf '%s\n' "$SN_R2" | /usr/bin/grep -vc '^            [^ ]' | tr -d ' ')"
expect_eq "SENTENCE-3b …and the folded lines are the sentence whole, its source line breaks joined, nothing cut" \
  "$SN_LONG" "$(printf '%s\n' "$SN_R2" | sed -e 's/^ *//' | paste -sd' ' -)"
expect_eq "SENTENCE-3c …folded at the card's right edge, past the title and count columns, never inside the title column" "yes" \
  "$([ "$(cols "$(printf '%s\n' "$SN_R2" | head -1)")" -gt 80 ] && echo yes)"
expect_empty "SENTENCE-3d …and no line of the card exceeds the width, the out-of-project artifact path aside" \
  "$(over_budget "$(printf '%s\n' "$SN" | /usr/bin/grep -v '^    requirements  ')")"
expect_eq "SENTENCE-3e the second row keeps its own line too, its count in the same column" \
  "    REQ-2   $(printf '%-30s' 'Short title')  ACs 2" "$(printf '%s\n' "$SN_BLOCK" | /usr/bin/grep '^    REQ-2 ')"
# THE TSV KIND DRAWS THE SAME TWO LINES from a fourth cell, and a three-cell row draws its one line as before.
printf 'REQ-1\tThe flock keeps one list\t1\t%s\nREQ-2\tShort title\t2\t%s\n' "$SN_SHORT" "$SN_LONG" | card requirement > "${CARD_SANDBOX}/sn-tsv.txt"
printf '%s\n' "$SN_BLOCK" | sed -e '/^$/d' > "${CARD_SANDBOX}/sn-whole.txt"
expect_true "SENTENCE-4 the whole card's block is byte-identical to the same rows fed as TSV with their sentences" \
  cmp -s "${CARD_SANDBOX}/sn-tsv.txt" "${CARD_SANDBOX}/sn-whole.txt"
expect_eq "SENTENCE-4b a three-cell TSV row draws its one line and nothing under it" \
  "  Requirements
    REQ-2   $(printf '%-30s' 'Short title')  ACs 2" "$(printf 'REQ-2\tShort title\t2\n' | card requirement)"
whole_card step1 "$SN_REQ" explain REQ-2; SN_E="$WC_OUT"
expect_eq "SENTENCE-5 explain keeps the provenance and the criteria" "PROV-BETA|A second criterion" \
  "$(printf '%s\n' "$SN_E" | /usr/bin/grep -o 'PROV-BETA' | head -1)|$(printf '%s\n' "$SN_E" | /usr/bin/grep -o 'A second criterion' | head -1)"

# The planted cases: the same file, one requirement's sentence taken away, then one given a backticked token.
SN_NONE="${CARD_SANDBOX}/wave-11-flock.requirements.md"
awk -v s="$SN_SHORT" '$0 != s { print }' "$SN_REQ" > "$SN_NONE"
expect_eq "SENTENCE-6 precondition: the planted file lost exactly the one sentence line" "1" \
  "$(( $(/usr/bin/grep -c . "$SN_REQ") - $(/usr/bin/grep -c . "$SN_NONE") ))"
whole_card step1 "$SN_NONE"
expect_eq "SENTENCE-6a a requirement with no opening paragraph is refused: exit 1, no card on stdout" "1|" "$WC_RC|$WC_OUT"
expect_contains "SENTENCE-6b …naming the requirement and what it lacks" \
  "REFUSED — requirement REQ-1: no sentence before its provenance: line" "$WC_ERR"
expect_eq "SENTENCE-6c …and naming only that one" "1|0" \
  "$(printf '%s\n' "$WC_ERR" | /usr/bin/grep -c 'REQ-1')|$(printf '%s\n' "$WC_ERR" | /usr/bin/grep -c 'REQ-2')"
whole_card step1 "$SN_NONE" explain REQ-2
expect_eq "SENTENCE-6d …and the sub-view is refused with it" "1|" "$WC_RC|$WC_OUT"
SN_TICK="${CARD_SANDBOX}/wave-12-flock.requirements.md"
sed -e 's/^silently lost in the merge\.$/silently lost in `merge_lists`./' "$SN_REQ" > "$SN_TICK"
expect_eq "SENTENCE-7 precondition: the planted file carries the backtick in REQ-2's paragraph" "1" \
  "$(/usr/bin/grep -c '`merge_lists`' "$SN_TICK" | tr -d ' ')"
whole_card step1 "$SN_TICK"
expect_eq "SENTENCE-7a a sentence carrying a backtick is refused: exit 1, no card on stdout" "1|" "$WC_RC|$WC_OUT"
expect_contains "SENTENCE-7b …naming the requirement and the sentence whole" \
  'REFUSED — requirement REQ-2: the sentence carries a backtick: Two people who edit the same list while apart both keep their edits when their phones meet again, and each of them is told which edits came from the other phone, so nothing they typed is ever silently lost in `merge_lists`.' "$WC_ERR"
# A provenance line before the paragraph is not the opening: the sentence is the paragraph BEFORE provenance.
SN_LATE="${CARD_SANDBOX}/wave-13-flock.requirements.md"
awk -v s="$SN_SHORT" '$0 == s { held = 1; next } { print } held && /^provenance:/ { print ""; print s; held = 0 }' "$SN_REQ" > "$SN_LATE"
whole_card step1 "$SN_LATE"
expect_contains "SENTENCE-8 a paragraph after the provenance line does not open the requirement: refused" \
  "REFUSED — requirement REQ-1: no sentence before its provenance: line" "$WC_ERR"
# One refusal names every offender, a title over the cap beside a missing sentence.
SN_BOTH="${CARD_SANDBOX}/wave-14-flock.requirements.md"
sed -e "s/^### REQ-2 — Short title/### REQ-2 — ${T31}/" "$SN_NONE" > "$SN_BOTH"
whole_card step1 "$SN_BOTH"
expect_eq "SENTENCE-9 a missing sentence and a long title are named in the one refusal" "1|2" \
  "$WC_RC|$(printf '%s\n' "$WC_ERR" | /usr/bin/grep -c '^REFUSED — requirement ')"

# ============================================================
section "§DESIGN-TITLES: a decision carries a title of at most 30 characters, and the Risks section is drawn whole"
# ============================================================
# fails-when: the card prints a decision's detail, a 31-character decision title is drawn, a risk is cut or refused
# for its length, the section still reads Worth your eye, or the Step-2 text lacks either rule.
DT_SPEC="${CARD_SANDBOX}/wave-09-flock.spec.md"
RISK_LONG="The sync trusts the phone clock, so two phones a minute apart can each believe the other edit is newer, and the list then keeps whichever edit it saw last. We have not measured how often that happens in the field, and a wrong guess here loses a real edit. A fix would add a counter to every row, which is a larger change than this run takes."
cat > "$DT_SPEC" <<FIXEOF
---
sdlc-step: 2
working-branch: wave/09-flock
integration-branch: main
base-sha: abc1234
adrs: adrs/epic-99/adr-001-sync.md
---

# flock wave 9 · spec

## Goal

Answer the flock's two requirements with a design small enough to read whole.

## Design

The flock syncs two phones and draws one list.

### Component boundaries and interfaces

- **D1 — ${T30}** DETAIL-ONE the sync owns the merge and hands the list to the view. (D1; REQ-1)
- **D2 — Short title.** DETAIL-TWO the view only draws. (D2; REQ-1, REQ-2)

### ADR pointers

- ADR-001 — the sync ruling: \`adrs/epic-99/adr-001-sync.md\` (D1).

### Approach

The sync first, then the view.

### Risks

- ${RISK_LONG}
- A short one.

## Eval design

| Requirement | Approach | Criterion | Eval type | Eval | Fails when |
|---|---|---|---|---|---|
| REQ-1 | fixture run | AC-1.1 the sync | unit | \`bash tests/sync.test.sh\` | it reds |
FIXEOF
whole_card step2 "$DT_SPEC"; DT="$WC_OUT"
expect_eq "DESIGN-TITLES-1 step2 draws a spec whose decision titles are within the cap, silently" "0|" "$WC_RC|$WC_ERR"
DT_D1="$(printf '%s\n' "$DT" | /usr/bin/grep '^    D1 ')"
DT_HDR="$(printf '%s\n' "$DT" | /usr/bin/grep '^  Decisions')"
expect_contains "DESIGN-TITLES-2 a decision prints its id and its title, a 30-character one whole" "D1   ${T30}" "$DT_D1"
expect_contains "DESIGN-TITLES-2b …its serves and its ADR" "REQ-1" "$DT_D1"
expect_contains "DESIGN-TITLES-2c …the ADR by file name" "adr-001-sync.md" "$DT_D1"
expect_contains "DESIGN-TITLES-2d …and none for a decision no ADR names" "none" "$(printf '%s\n' "$DT" | /usr/bin/grep '^    D2 ')"
expect_eq "DESIGN-TITLES-2e …the title with its trailing period taken off" "Short title" \
  "$(printf '%s\n' "$DT" | /usr/bin/grep '^    D2 ' | sed -e 's/^    D2   //' -e 's/ *REQ-.*$//')"
expect_eq "DESIGN-TITLES-3 no decision detail is on the card" "" "$(printf '%s\n' "$DT" | /usr/bin/grep 'DETAIL-')"
expect_contains "DESIGN-TITLES-3b the header names serves and ADR" "serves" "$DT_HDR"
expect_empty "DESIGN-TITLES-3c no line of the card exceeds the width, the out-of-project artifact path aside" "$(over_budget "$(printf '%s\n' "$DT" | /usr/bin/grep -v '^    spec  ')")"
whole_card step2 "$DT_SPEC" explain D1; DT_E="$WC_OUT"
expect_eq "DESIGN-TITLES-4 explain D1 exits 0" "0" "$WC_RC"
expect_contains "DESIGN-TITLES-4b …and prints the detail" "DETAIL-ONE the sync owns the merge and hands the list to the view." \
  "$(printf '%s\n' "$DT_E" | sed -e 's/^ *//' | paste -sd' ' -)"
expect_absent "DESIGN-TITLES-4c …and not the other decision's" "DETAIL-TWO" "$DT_E"
whole_card step2 "$DT_SPEC" explain D9
expect_eq "DESIGN-TITLES-4d a decision the spec lacks exits 2 and prints nothing on stdout" "2|" "$WC_RC|$WC_OUT"

DT_RISKS="$(printf '%s\n' "$DT" | sed -n '/^  Risks$/,/^$/p')"
expect_eq "DESIGN-TITLES-5 the section is drawn under the word Risks" "1|0" \
  "$(printf '%s\n' "$DT" | /usr/bin/grep -c '^  Risks$')|$(printf '%s\n' "$DT" | /usr/bin/grep -c 'Worth your eye')"
expect_eq "DESIGN-TITLES-5b a three-sentence risk is drawn whole, folded, none of its words cut" "$RISK_LONG" \
  "$(printf '%s\n' "$DT_RISKS" | sed -n '2,$p' | awk '/^    A short one\./ { exit } { print }' | sed -e 's/^ *//' | paste -sd' ' -)"
expect_eq "DESIGN-TITLES-5c …on more than one line, each inside the width" "yes|" \
  "$([ "$(printf '%s\n' "$DT_RISKS" | /usr/bin/grep -c .)" -gt 3 ] && echo yes)|$(over_budget "$DT_RISKS")"
expect_contains "DESIGN-TITLES-5d …and a short risk beside it" "    A short one." "$DT_RISKS"
expect_absent "DESIGN-TITLES-5e …and no ellipsis anywhere in the section" "…" "$DT_RISKS"

DT_OLD="${CARD_SANDBOX}/wave-10-flock.spec.md"
sed -e 's/^### Risks$/### Worth your eye/' "$DT_SPEC" > "$DT_OLD"
whole_card step2 "$DT_OLD"
expect_eq "DESIGN-TITLES-6 a spec written with the old heading still draws, under the word Risks" "0|1|0" \
  "$WC_RC|$(printf '%s\n' "$WC_OUT" | /usr/bin/grep -c '^  Risks$')|$(printf '%s\n' "$WC_OUT" | /usr/bin/grep -c 'Worth your eye')"
expect_contains "DESIGN-TITLES-6b …with the risk whole" "$(printf '%s' "$RISK_LONG" | cut -c1-40)" "$WC_OUT"

DT_BAD="${CARD_SANDBOX}/wave-11-flock.spec.md"
sed -e "s/^- \*\*D2 — Short title\.\*\*/- **D2 — ${T31}**/" "$DT_SPEC" > "$DT_BAD"
whole_card step2 "$DT_BAD"
expect_eq "DESIGN-TITLES-7 a 31-character decision title is refused: exit 1, no card on stdout" "1|" "$WC_RC|$WC_OUT"
expect_contains "DESIGN-TITLES-7b …naming the decision, the length and the title whole" \
  "REFUSED — decision D2: title is 31 characters, the cap is 30: ${T31}" "$WC_ERR"
whole_card step2 "$DT_BAD" ownership
expect_eq "DESIGN-TITLES-7c …and the sub-views are refused with it" "1|" "$WC_RC|$WC_OUT"
yn() { [ "$1" -ge 1 ] && echo yes || echo no; }
D2_TXT="${REPO}/skills/canonical-sdlc/steps/2.md"; D2_TMPL="${REPO}/agents-src/templates/skills/canonical-sdlc/steps/2.md.tmpl"
expect_eq "DESIGN-TITLES-8 the Step-2 text and its template name the Risks section and not the old heading" "yes|yes|0|0" \
  "$(yn "$(/usr/bin/grep -c '### Risks' "$D2_TXT")")|$(yn "$(/usr/bin/grep -c '### Risks' "$D2_TMPL")")|$(/usr/bin/grep -c 'Worth your eye' "$D2_TXT")|$(/usr/bin/grep -c 'Worth your eye' "$D2_TMPL")"
expect_eq "DESIGN-TITLES-8b …and state the decision title rule and the judged, uncapped risk" "1|1" \
  "$(/usr/bin/grep -c 'the title at most 30 characters' "$D2_TXT")|$(/usr/bin/grep -c 'own judgment, one to three sentences' "$D2_TXT")"


finish
