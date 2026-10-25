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

- **`lib/first.sh`** The first file owns the first thing. It hands the second
  thing to its caller rather than doing it itself. (D1; REQ-1)
- **`lib/second.sh`** The second file owns the second thing. (D2; REQ-2)

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
| REQ-1 | a source pin and a fixture run | AC-1.1 the first criterion | static | `grep` | the pin is gone |
| REQ-1 | a source pin and a fixture run | AC-1.2 the second criterion | hermetic | `bash tests/first.test.sh` | it reds |
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
| T1 | 4 | build | REQ-1: the first task. The fixture's first task has its own sentence. It also has a detail the card does not show. complexity: standard | implementor | — | 30 | REQ-1 | lib/first.sh | .worktrees/99-T1 | pending |
| T2 | 4 | test | REQ-2: the second task. The fixture's second task has one too. complexity: complex | senior-implementor | T1 | 45 | REQ-2 | lib/second.sh | — | pending |

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
expect_absent "59d: …nor the detail after the sentence" "a detail the card does not show" "$S3"
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
# THE STEP-2 ONE IS A COPY THIS SUITE OWNS TOO, for the same reason: a real run's spec whole, each decision given
# its opening sentence and each requirement one plain approach of at most 60 columns, as the card now requires.
REAL_SPEC="${CARD_INTREE}/wave-44-every-hand.spec.md"
cat > "$REAL_SPEC" <<'W44SPEC'
---
governing-skill: agent-skills:spec-driven-development
sdlc-step: 2
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
requirements: specs/epic-23-bionic-tech-debt/wave-44-every-hand.requirements.md
design-ledger: record/wave-44-every-hand/design-ledger.md
release: 1.27.0
---
# bionic 1.27.0 — the sitrep changes what you do next · spec (epic-23 wave-44)

## Goal

Ship bionic 1.27.0 so that a sitrep is the handful of facts that change what the user does next, drawn by code with the model's judgment on top, in under thirty seconds. The register stores the answer given to an ask and one function says whether the ask waits on the user or on an event; only the first can block the user or drive the call. The card verb draws every row that is a fact from the saved sheet, the model writes seven lines of judgment, and the check refuses only what would make the card false. The Assessment opens on what the wave is for, read from the plan. Accepted when a fixture shaped like the large-app run draws the approved mock-up in under 40 rows and three real sitreps take under thirty seconds each.

## Context and Problem

The requirements (REQ-1 to REQ-10) and three records carry it: `record/wave-44-every-hand/research-sitrep-concept.md` (the card never states what the wave is for), `research-sitrep-latency.md` (95 s median, 90% model output: first judgment 43%, refusal rewrites 34%, retyping the card 14%) and `research-sitrep-sites.md` (the sites at dd425be64). The register's `owed/v1` line has no field for an answer or for what an ask waits on; its kind is the key prefix alone (sites §REQ-1). A waiver answered "no" at the release card reaches only the approval page (`withheld:`, plan.sh:2989-2992); the `waive:<q>` item stays open and holds the merge. Three rules say what blocks the user: the sheet (sitrep.sh:1616), the card's fallback (card.sh:3139) and the handoff head (sitrep.sh:2123, yes for any open ask); the Patrol's `owed: <n>` counts every ask. The card verb accepts eight tags, requires a row per step, per open task, per metric and per open ask, binds every metric number to a word, and refuses a row over 100 columns though a fold helper exists (card.sh:2373). The rulings are the ledger's Δ1, Δ6 to Δ11: D1 "1", D6 "1", D7 "1", D8 "1", D9 "1", the cut (Δ8) and the check's rule (Δ11). The frame's D2 to D5 were named for the measure run and withdrawn with the cut.

## Design

Three owners, one each. Structure belongs to code: the card verb draws the head, the task list, the Metrics table, Blocked on you, the counted line of items waiting on events and the close's two time lines from the saved sheet, so no row that is a fact can be refused (D6). Words belong to the model: seven free lines, the purpose, the call, the grade, one to three points, a recommendation per ask that waits on the user, and the close's condition (D6, D7). Truth belongs to the check, and only truth: it refuses a number no sheet value holds, a state the sheet denies, a forbidden word, and a missing purpose, call, grade or close, and repairs everything else, folding a long line, keeping a fourth point with a note, drawing an unrecommended ask as the ask alone (Δ11). Under it, the register learns what an ask waits on by storing the answer given to it and deriving the rest in one function every reader calls (D8). The sheet gains the plan's Goal and each theme's opener, the goals reader a per-theme count and an "on course" word, task scale one goal (D1). Five decisions, one rule, 22 evals: 2 static, 10 unit, 9 hermetic, 0 live, 1 human. Added at Step 4 on Chris's word (Δ13): the plan card prints a title per task, REQ-11.

### 1. Domain model

- **An ask's answer.** What the user has said to an ask that is not yet closed: `no` to a waiver, `carry` to a finding, with the row or event named. Stored on the ask's open `owed/v1` line as `answer=<word> answered=<ISO> [event=<what>]`, by the verb that takes the answer (`reply`, `disposition`, `finding-move`). Invariants: an answer never closes the ask; the ask closes at the event it names, as it closes today; a re-open of an open key keeps its answer (`owed_open` is idempotent); a fresh open after a close starts with none.
- **What an ask waits on.** `user`, or `event <what>`. Derived, never stored, by `ask_waits_on <key>`: a decision, an approval, a gate, a ruling, a matrix ruling, a declared-missed goal, an unanswered waiver and an unanswered finding wait on the user; a waiver answered no waits on its review's next run; a finding answered carry waits on its row's landing, or on the release card when no row is named; a `carry:` item waits on the release card; `hold:merge` waits on what the waivers that hold the merge wait on; `delivered:` on nothing. Invariant: every reader of "blocked", the call's check, the handoff head and the Patrol's count call this one function.
- **A fact row.** A row of the card drawn from a sheet line by the card verb: head, step and task rows, the five Metrics lines, Blocked on you, the counted line, the close's predicted and basis lines. Invariant: a fact row is never in the judgment and never checked; it cannot be refused because nobody typed it.
- **The judgment.** Seven tags: `purpose:`, `call:`, `grade:`, `point:` (one to three), `ask <key>:` (one per ask that waits on the user), `close:` (the condition line). Invariants: free prose; a number in it is bound to a sheet value by word and place; a forbidden word refuses; a missing purpose, call, grade or close refuses by name; any other tag refuses by name; nothing else refuses.
- **The purpose.** What the wave is for and whether it is on course: the model's line, written from `run.goal` and the `goal:` lines, first under the Assessment (D1).
- **A theme's standing.** `met`, `on course` (at least one criterion discharged, none missed), `not measured` (none discharged), `not met`; one word on the sheet, the sitrep card and the release card.

### Interfaces

- `lib/owed.sh`: `owed_answer <key> <word> [<event>]` rewrites the open line with `answer= answered= event=`; `owed_answer_of <key>` prints the answer fields; `ask_waits_on <key>` prints `user` or `event <what>` from the key's kind and its answer. `_owed_list_file` keeps its four columns.
- `reply` (hooks/poker/plan.sh:2928): an other-side `-` on a waiver row calls `owed_answer waive:<q> no "review <q> re-run"` beside its `withheld:` line. `disposition … defer|carry` and `finding-move … to=carried row=<T>` call `owed_answer finding:<id> carry "<T> lands"` and leave the item open; the landing of `<T>` closes it (line.sh:775's arm, widened); `to=fixed` closes at once as today.
- `sitrep_asks` prints a sixth field, `waits=`, from `ask_waits_on`; `sitrep_ask_lines` writes `blocks=<yes|no>` from `holds != nothing && waits == user` and appends `waits=user|event <what>` as the last field; the card's A record gains the field after `blocks=`. `_card_sitrep_load`'s re-derivation at card.sh:3139 is deleted. `ho_state` (sitrep.sh:2123) prints `Blocked on you: yes` only when some ask has `blocks=yes`. `sitrep_status` prints `owed: <n> on you · <m> on events`; the tick line carries both.
- `sitrep card`: `decisions_settle`, read the saved sheet, refresh its `ask:` lines through `sitrep_asks` alone (no second `sitrep_gather`), run card.sh. card.sh `_card_sitrep_draw` draws the fact rows from the S, T, R and A records and the metric lines; `_card_sitrep_judge` accepts the seven tags; `_card_sitrep_check` folds through `_card_hang` and refuses only the four falsehoods; the number binding of `_card_sitrep_metrics_judge` becomes `_card_bind <line> <values>` applied to every judgment line against every measured sheet value, by word and place.
- The Metrics table: five lines, label at column 3, two value groups separated by `·` and a gap, numbers from the sheet's measured values only, the pace comparison first in the Pace line, the Goals line per theme (`<theme> k of n[, REQ-a open]`) or, at task scale, `the run k of n`.
- `sitrep_gather`: `run.goal:` from the plan's `## Goal` first paragraph (the parse at card.sh:843-847 moved to lib/plan.sh as `plan_goal_paragraph`); `goal:` lines gain `for=<opener>` last, from `plan_themes` reading the first body line under each `## <theme>`; at task scale `plan_themes` yields one theme, `the run`, over every REQ with a matrix row. `plan_goal_status` maps pending with k ≥ 1 to `on course`; the release card's mark map (hooks/poker/plan.sh:2516-2524) learns the word. `tick_owed_goals` opens no `decide:goal:` for a measured goal whose miss is a declared red (a `Lands-red:` row's debt line, line.sh:828).
- `skills/sitrep/SKILL.md`: the two verbs, the seven lines, the Purpose question in place of the Goals question, the standard ("the handful of facts that change what you do next"), "nothing tonight" when every open ask waits on an event, show the tool's card once inside one fenced block and never retype it. `agents-src/templates/commands/help.md.tmpl:40` follows.
- The cards (Δ13, Δ14; REQ-11 to REQ-14): a `## Tasks` cell opens on a title of at most 30 characters, then a period and the detail; `card.sh step3` prints the title alone, `serves` in its own column and consecutive ids in `depends` as a range, refusing a longer title with its row and length named, never cutting it; `show task <n>` prints the whole cell; `steps/3.md` states the rule beside the Tasks table. The requirements card the same way: a `### REQ-<n> — <title>` title of at most 30 characters, printed with its id and criteria count on one line, the provenance under `explain <requirement>`, the rule in `steps/1.md`; its Not Doing items the same, `explain not-doing` for the reasons. The design card the same: a decision's title of at most 30 characters, the detail under `explain <decision>`, and the Worth-your-eye section renamed Risks, each item the model's own judgment in one to three sentences, drawn whole with no cap, the rule in `steps/2.md`. On every card a longer title is refused with the item named, never cut. The sitrep's task rows read the same title, since the sheet's `desc` is the cell cut at its first punctuation.
- `tests/sitrep-card.test.sh` §MOCKUP: a sheet shaped like the large-app card (17 open tasks, 14 event-waiting asks, a refused waiver holding the merge, 54 added tasks) and a seven-line judgment draw the mock-up: one call line, the task list, five Metrics lines, purpose plus points plus one counted line, `None` naming the event, three close lines, under 40 rows.

### Approach

The mock-up fixture first (T1), red at the base on the unknown `purpose:` tag, because every later row is judged by the card it draws. The register next (T2): the answer field, `ask_waits_on`, the three readers and the Patrol count on one function, `reply` and `disposition` writing the answer, the landing closing a carried finding. Then the draw and the check (T3, T4): the fact rows drawn from the saved sheet, the seven tags, the binding generalised, the fold, the four refusals and nothing else, the card verb no longer re-gathering. Then the goals (T5): `run.goal`, `for=`, the per-theme Goals line, "on course", task scale, the declared red. Then the skill and the pins (T6): SKILL.md, the help line, the judgment fixtures in sitrep-card, card, words and the rehearsal builder rewritten to seven lines. The regression runs once after the build; the critic's review follows; the thirty seconds is measured at Step 5 from three real sitreps on this plan (REQ-9).

### Worth your eye

This section is the spec's Risks (AC-11.4); it keeps the heading the card reads until T13 lands, then is renamed.

- An answering verb that forgets to record the answer leaves its ask reading "waits on you": the exact lie this run removes, guarded only by the fixture and convention.
- A carried finding now closes at its row's landing, not at its ruling, so any reader that counted closed findings at ruling time reads one fewer.
- The check binds digits, not words: "three reviews failed" passes over a sheet reading two.

### 2. Component boundaries and interfaces

- **D1 — The purpose line comes first** The Assessment opens on what the wave is for, drawn first under the grade. A required `purpose:` tag drawn first under the grade; the seven sections keep their order. (D1; REQ-7)
- **D6 — Code draws, the model judges** Code draws every row that is a fact, and the model writes only the judgment. The card verb draws every fact row from the saved sheet; the judgment is seven tags; the tool shows the card and the skill never retypes it. (D6; REQ-3, REQ-4, REQ-5, REQ-6, REQ-8)
- **D7 — The card shows what matters** The card shows only what changes the user's next move. The register tells an ask that waits on the user from an item that waits on an event; only the first blocks or drives the call; event-waiting items are one counted line; Metrics are a numbers-only table. (D7; REQ-1, REQ-2, REQ-3, REQ-10)
- **D8 — Answers stored, waits derived** An ask stores the answer it was given, and one function says what it waits on. `owed_answer` on the ask's line; `ask_waits_on` the one function every reader calls. (D8; REQ-1, REQ-2)
- **D9 — Fixtures, pins, a human clock** The fixtures and pins prove the shape, and a human clock measures the time. The thirty seconds is three real sitreps measured at Step 5. (D9; REQ-9, REQ-10)

The rule beside them (Δ11): the check refuses only a falsehood and repairs everything else.

Who owns what:

| Module | Owns | Changes |
|---|---|---|
| `payload/scripts/lib/owed.sh` | the register's grammar, `ask_waits_on` | `answer=` fields, `owed_answer`, `owed_answer_of`, `ask_waits_on` |
| `hooks/poker/plan.sh` (`reply`), `hooks/poker/proof.sh` (`disposition`, `finding-move`), `payload/scripts/lib/line.sh` (the landing's close) | the verbs that take an answer | write the answer; the landing closes a carried finding |
| `hooks/poker/sitrep.sh` | the sheet, the card verb, the handoff head, the Patrol line | `waits=` on ask lines, `run.goal:`, `for=`, `blocks=` from the one function, no re-gather at card time, `owed: n on you · m on events` |
| `payload/scripts/card.sh` | the draw and the check | fact rows drawn, seven tags, `_card_bind` over every judgment line, fold not refuse, four refusals, fallback deleted |
| `payload/scripts/lib/plan.sh`, `hooks/poker/plan.sh` (release card), `hooks/poker/tick.sh` | the goals | `plan_goal_paragraph`, openers, `on course`, task-scale theme, no ask on a declared red |
| `skills/sitrep/SKILL.md`, `agents-src/templates/commands/help.md.tmpl` | the model's instructions | the seven lines and the standard |
| `tests/sitrep-card.test.sh`, `tests/sitrep.test.sh`, `tests/card.test.sh`, `tests/words.test.sh`, `tests/handoff-file.test.sh`, `tests/lib/rehearsal-read.sh`, `tests/asks.test.sh`, `tests/release-approval.test.sh` | the pins | judgment fixtures to seven lines; §MOCKUP; the answer and `ask_waits_on` rows |

### 3. Ownership table

| concept | owning module (SSoT) | reuses | rendering surfaces | agreement test |
|---|---|---|---|---|
| what an ask waits on | `lib/owed.sh` `ask_waits_on` | the key prefix table `sitrep_holds` already keys on | the sheet's `waits=` · the card's Blocked on you and call check · the handoff head · the Patrol's `owed:` | `sitrep.test.sh` §ONE-BLOCKS: a planted answered waiver reads event on all four, and a planted divergence in any one reddens |
| an ask's answer | the register's open line `answer=` | `_owed_rewrite`'s last-word-wins | `waits=` · the release page's `withheld:` | `asks.test.sh` §ANSWER: `reply` no then `owed_answer_of` reads it, the item open |
| the fact rows | `card.sh` `_card_sitrep_draw` over the saved sheet | the S/T/R/A records and `_card_hang` | the card | `sitrep-card.test.sh` §DRAWN: a judgment with a `task:` line is refused and the drawn rows equal the sheet |
| the Metrics numbers | the sheet's measured values | `CARD_SITREP_MLINES` | the Metrics table · a judgment line's bound number | `sitrep-card.test.sh` §BIND: a number on no line refuses; the swapped pair refuses |
| what the wave is for | the plan's `## Goal` paragraph via `plan_goal_paragraph` | the requirements card's parse (card.sh:843-847), moved | `run.goal:` · the Step-1 card's Purpose | `sitrep.test.sh` §RUN-GOAL: the sheet's line equals the card's paragraph |
| a theme's standing | `lib/plan.sh` `plan_goal_status` | `_plan_theme_reads` | the sheet's `goal:` · the Goals line · the release card's mark | `sitrep.test.sh` §GOAL-AGREE: a theme at 11 of 12 reads `on course` on all three |

### 4. Rejected alternatives

- **`waits-on` written by every opener** (D8 option 2): eight writers of one field; one forgotten and the vapid call returns.
- **A Purpose section above Call to action** (D1 option 2): reopens the section order for one line the Assessment can carry first.
- **Trim in place** (D7 option 2): caps the points and collapses the asks but keeps the register blind, so the call and Blocked on you stay false.
- **Back to the plain prompt** (D7 option 3): half the time and facts that can be wrong again.
- **A scripted model for the timing** (D9 option 2): a harness for one number that proves nothing about the model.
- **A drawn-rows file beside the sheet**: a second saved artifact the model must keep consistent with the first; the card verb draws from the sheet at card time instead.
- **Optional `task:` and `metric:` overrides**: two writers of one row; the model's warmer phrasing is not worth a second truth.

### 5. Assumptions

- The `owed/v1` grammar tolerates new fields after `reply=`: every reader cuts named fields or the first four columns, none by count. `research-sitrep-sites.md` §REQ-1 lists the readers.
- `judge.sh:25` and `walls.sh:2543` re-open `waive:<q>` through `owed_open`, which leaves an open item as is, so an answer survives the next failing pass.
- The sheet's `desc` and `note` carry what the mock-up's task rows say; where a note is empty the row is the title alone.
- Three sitreps on this plan at Step 5 are a fair measure of REQ-9: the plan has few tasks, so the judgment is short; the measure is repeated once on the wave-43 plan for a fuller sheet and recorded beside it.
- No hook or wall other than the ones named reads an ask's `blocks=`; `research-sitrep-sites.md` §REQ-2 grepped `blocks=` across hooks and libraries and found three sites.

### ADR pointers

- `adrs/epic-23-bionic-tech-debt/adr-071-code-draws-the-facts-the-model-judges.md` (D6; D7; D8; REQ-1, REQ-3, REQ-4): the card's three owners and the check's rule; written at Step 7.

## Eval design

| Requirement | Approach | Criterion | Eval type | Eval | Fails when |
|---|---|---|---|---|---|
| REQ-1 | a register with one ask of each kind, one answered | AC-1.1 | hermetic | `asks.test.sh` §WAITS: `ask_waits_on` says user for a decision, an approval and an unanswered waiver, event for a waiver answered no and a finding answered carry; the sheet's `ask:` lines carry `waits=` | the refused waiver reads user, or a line lacks the field |
| REQ-1 | a register with one ask of each kind, one answered | AC-1.2 | hermetic | `asks.test.sh` §ANSWER: the item stays open with `answer=no`; the finding stays open with `answer=carry event=T9 lands` and closes when T9's landing is recorded | the item closes at the answer, or reads no answer |
| REQ-2 | the mock-up sheet and a sheet with an unanswered waiver | AC-2.1 | unit | `sitrep-card.test.sh` §BLOCKS: `None` naming T86 over the refused waiver; the unanswered waiver drawn under Blocked on you | the refused waiver is drawn, or `None` over the unanswered one |
| REQ-2 | the mock-up sheet and a sheet with an unanswered waiver | AC-2.2 | unit | `sitrep-card.test.sh` §CALL: admitted over the refused waiver, refused over the unanswered one | either verdict inverts |
| REQ-2 | the mock-up sheet and a sheet with an unanswered waiver | AC-2.3 | hermetic | `sitrep.test.sh` §ONE-BLOCKS: the sheet, the handoff head and the Patrol line agree over a planted answered waiver; `/usr/bin/grep -c 'nothing.*blocks\|blocks=' payload/scripts/card.sh` finds no re-derivation | any two disagree, or the fallback remains |
| REQ-3 | the wave-43 saved sheet and the mock-up sheet | AC-3.1 | unit | `sitrep-card.test.sh` §DRAWN: every step and task row drawn from S and T records; a `task:` line in the judgment refuses by name | a task row is missing, or `task:` is accepted |
| REQ-3 | the wave-43 saved sheet and the mock-up sheet | AC-3.2 | unit | `sitrep-card.test.sh` §TABLE: five lines, every digit run a measured value of its line, the pace comparison first | a digit no line holds, or prose |
| REQ-3 | the wave-43 saved sheet and the mock-up sheet | AC-3.3 | unit | `sitrep-card.test.sh` §COUNTED: one line "14 items wait on landings, not on you: 8 carried findings, 6 rulings given" under the Assessment | an ask is drawn as a row |
| REQ-4 | each tag present, missing and foreign, and bound numbers | AC-4.1 | unit | `sitrep-card.test.sh` §TAGS: the seven accepted; `metric:` refused by name; a missing `purpose:` refused by name | a foreign tag draws, or a missing one is unnamed |
| REQ-4 | each tag present, missing and foreign, and bound numbers | AC-4.2 | unit | `sitrep-card.test.sh` §BIND: "1 green and 11 red" over "11 green, 1 red" refuses; a number on no line refuses; the long point folds and draws | the swap passes, or the fold refuses |
| REQ-4 | each tag present, missing and foreign, and bound numbers | AC-4.3 | static | `/usr/bin/grep -n 'fenced' skills/sitrep/SKILL.md` finds the show-once rule and no "regenerate"; `sitrep-card.test.sh` §REASONS: a judgment missing purpose and holding a bad number prints both reasons on one refusal | the text asks to retype, or the second reason waits for a second run |
| REQ-5 | the skill text | AC-5.1 | static | `/usr/bin/grep -c 'task:\|metric:' skills/sitrep/SKILL.md` → 0 outside the refusal list; §SKILL rows of sitrep-card and sitrep read the seven tags and the Purpose question; `words.test.sh` §TEXTS green | an old tag remains in the example, or the Goals question |
| REQ-6 | the wave-44 plan and a fixture with openers | AC-6.1 | hermetic | `sitrep.test.sh` §RUN-GOAL: `run.goal:` equals the paragraph the Step-1 card prints; the Goal-less plan prints no line and no error | the line differs, or an error prints |
| REQ-6 | the wave-44 plan and a fixture with openers | AC-6.2 | hermetic | `sitrep.test.sh` §FOR: each `goal:` line ends `for=<opener>`; `release-approval.test.sh` §GOALS unchanged green | a line lacks `for=`, or the release card's read changes |
| REQ-7 | a judgment without purpose, and one with a false count | AC-7.1 | unit | `sitrep-card.test.sh` §PURPOSE: the first refuses by name; the second refuses on the number; a true one draws first under the grade | a card draws without it, or the false count draws |
| REQ-8 | fixtures for each theme standing, and the task-scale plan | AC-8.1 | hermetic | `sitrep.test.sh` §GOAL-AGREE: `on course` and `not measured` on the sheet, the Goals line and the release card; "Identity 10 of 11" refuses at the card | the two themes read alike, or the false count draws |
| REQ-8 | fixtures for each theme standing, and the task-scale plan | AC-8.2 | hermetic | `sitrep.test.sh` §TASK-GOAL: one `goal: name=the run` with k of n over the matrix | no goal line |
| REQ-8 | fixtures for each theme standing, and the task-scale plan | AC-8.3 | hermetic | `sitrep.test.sh` §DECLARED-RED: the tick opens no `decide:goal:`; a goal missed otherwise still opens one | the ask opens, or the real miss opens none |
| REQ-9 | three timed sitreps and the two verbs on the wave-43 plan | AC-9.1 | human | the transcript timings recorded in `record/wave-44-every-hand/sitrep-timing.md`, each under 30 s, at most one refusal | one at 30 s or more, or two refusals |
| REQ-9 | three timed sitreps and the two verbs on the wave-43 plan | AC-9.2 | hermetic | `sitrep.test.sh` §FAST: `sitrep` then `sitrep card` on a copy of the wave-43 plan and record under 5 s together | 5 s or more |
| REQ-11 | a plan whose cells open on titles, one of 31 characters | AC-11.1 | unit | `card.test.sh` §TITLES: the Step-3 card's task block prints each title alone with `serves` in its own column and `T1–T5` for a run of ids; the 31-character title is refused with its row and length named; `show task 1` prints the whole cell; `/usr/bin/grep -c 'title of at most 30' skills/canonical-sdlc/steps/3.md` → 1 | the detail prints, the long title draws, or the step text lacks the rule |
| REQ-12 | a requirements file with one 31-character title | AC-12.1 | unit | `card.test.sh` §REQ-TITLES: the Step-1 card prints `REQ-n  <title>  ACs k` per requirement and no provenance; the long title is refused with its requirement and length named; `explain REQ-1` prints the provenance; `/usr/bin/grep -c 'at most 30' skills/canonical-sdlc/steps/1.md` → 1 | a provenance prints, the long title draws, or the step text lacks the rule |
| REQ-13 | Not Doing items that open on titles, one of 31 characters | AC-13.1 | unit | `card.test.sh` §NOT-DOING-TITLES: the Step-1 card prints each item's title on one line and no reason; the long title is refused with the item named; `explain not-doing` prints the items whole | a reason prints, the long title draws, or the step text lacks the rule |
| REQ-14 | a spec with a 31-character decision title and free risks | AC-14.1 | unit | `card.test.sh` §DESIGN-TITLES: the Step-2 card prints each decision as id, title, serves and ADR and refuses the long title naming it; the Risks section draws whole under `Risks`, folded, never cut; a spec with `### Worth your eye` still draws | the long title draws, a risk is cut, or the section reads Worth your eye |
| REQ-10 | the large-app-shaped sheet | AC-10.1 | unit | `sitrep-card.test.sh` §MOCKUP: the drawn card equals the mock-up's shape line for line (sections, counts, `None`, three close lines), under 40 rows; red at dd425be64 on the unknown `purpose:` tag, T1's red log in record/ | a register item is a row, the merge reads blocked, 40 rows or more, or green at the base |

## Not Doing

As the requirements: the measure work and the Known-limit leftovers (1.28.0); new sections; the section order, numbers-only Metrics, the grade and the task list's shape; a sitrep at epic scale beyond today's sheet; the person's merge and tag.
W44SPEC
# THE STEP-3 ONE IS A COPY THIS SUITE OWNS too: a real run's plan, each Tasks cell given its plain sentence after its
# title as the card now requires, the original text kept after it as the detail. The sections the Step-3 card does not
# read are left out, and the state section keeps only its keys, so the card it draws is the live plan's card line for
# line with the sentences added.
REAL_PLAN="${CARD_INTREE}/wave-44-every-hand.plan.md"
cat > "$REAL_PLAN" <<'W44PLAN'
---
governing-skill: canonical-sdlc
sdlc-step: 0
epic: epic-23-bionic-tech-debt
wave: wave-44-every-hand
intent: build
rigor: single
review-cadence: once
fix-policy: S1,S2-on
fix-cap: 2
scale: task
scale-recommendation: "Chris ruled the scale in the charter: task scale, single rigor, integration by pull request, as 1.26.0 ran. The run was cut to the sitrep at the design frame: five build rows on one card, one plan and its Tasks table hold it."
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
base-sha: dd425be642565ce8305a19d219c5eb27637033e7
seed: ideas/bionic-1.27.0-charter.md
requirements: specs/epic-23-bionic-tech-debt/wave-44-every-hand.requirements.md
spec: specs/epic-23-bionic-tech-debt/wave-44-every-hand.spec.md
design-ledger: record/wave-44-every-hand/design-ledger.md
forecast: 8h
release: 1.27.0
adrs: docs/adrs/adr-071-code-draws-the-facts-the-model-judges.md
created: 2026-10-23
regression: yes
regression-override: Chris Lehman 2026-10-23 derived=no chosen=yes
---
# bionic 1.27.0 — the sitrep changes what you do next · plan

## Goal

Build bionic 1.27.0 so that a sitrep is the handful of facts that change what the user does next, drawn by code with the model's judgment on top, in under thirty seconds: the register tells an ask that waits on the user from an item that waits on an event, and only the first can block the user or drive the call; the verb draws the head, the task list, the metrics, Blocked on you and the predicted close, and the model writes seven lines of judgment the check reads; the card opens its Assessment on what the wave is for and whether it is on course. Accepted when the card drawn on the wave-43 plan and on a fixture shaped like the large-app run reads in the approved mock-up's shape, and three sitreps in a row take under thirty seconds each.

## Tasks

| id | step | kind | task | agent | deps | reads | size | serves | Files | worktree | base | status | suites | lands-on | artifact |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | The card draws the facts. The sitrep card draws its fact rows from the sheet, and the model writes only the judgment. The card draws the facts, and the mock-up fixture (D6, D7, D1, Δ11; AC-2.1, AC-2.2, AC-3.1 to AC-3.3, AC-4.1 to AC-4.3, AC-7.1, AC-10.1). `tests/sitrep-card.test.sh` §MOCKUP first, red at the base on the unknown `purpose:` tag: a sheet shaped like the large-app card (17 open tasks, 14 event-waiting asks with `waits=event`, a refused waiver holding the merge, 54 added tasks) and a seven-line judgment must draw the mock-up under 40 rows. Then `card.sh`: `_card_sitrep_draw` draws the head, every step and task row from the S and T records (`desc` plus `note`), the five-line Metrics table from the measured values, Blocked on you from asks with `blocks=yes` and `None` naming the nearest event otherwise, the counted line of event-waiting asks by kind under the Assessment, and the close's predicted and basis lines; `_card_sitrep_judge` accepts `purpose:`, `call:`, `grade:`, `point:` (1 to 3, a fourth kept with a note), `ask <key>:` and `close:` and refuses any other tag by name; the number binding becomes `_card_bind`, applied to every judgment line against every measured sheet value by word and place; a long line folds through `_card_hang`; the check refuses only a number no value holds, a state the sheet denies, a forbidden word and a missing purpose, call, grade or close, every reason at once; the `blocks=` fallback at card.sh:3139 is deleted and the A record gains `waits=` after `blocks=`. §DRAWN, §TABLE, §COUNTED, §TAGS, §BIND, §REASONS, §PURPOSE, §BLOCKS, §CALL in sitrep-card; card.test.sh KINDS-7 rewritten to seven lines · complexity: complex | w44-T1 | — | — | 120 | REQ-2, REQ-3, REQ-4, REQ-7, REQ-10 | payload/scripts/card.sh, tests/sitrep-card.test.sh, tests/card.test.sh, tests/CENSUS.md, .bionic/docs/record/wave-44-every-hand/T1.md | .worktrees/44-T1 | dd425be6 | landed | — | — | — |
| T2 | 4 | build | The register stores the answer. An answered ask keeps its answer, and one function says what it waits on. The register stores the answer, one function says what an ask waits on (D8; AC-1.1, AC-1.2). `lib/owed.sh`: `owed_answer <key> <word> [<event>]` rewrites the open line with `answer= answered= event=`, `owed_answer_of`, and `ask_waits_on <key>` printing `user` or `event <what>` from the key's kind and its answer (decision, approval, gate, ruling, matrix ruling, declared-missed goal, unanswered waiver and unanswered finding wait on the user; a waiver answered no on its review's re-run; a finding answered carry on its row's landing or the release card; `carry:` on the release card; `hold:merge` on what the waivers holding the merge wait on). `reply`'s other-side `-` on a waiver row calls `owed_answer waive:<q> no`; `disposition … defer` or `… carry` and `finding-move … to=carried row=<T>` call `owed_answer finding:<id> carry "<T> lands"` and leave the item open; the landing of `<T>` closes it in `lib/line.sh`'s arm; `to=fixed` closes at once as today. `_owed_list_file` keeps four columns. §WAITS and §ANSWER in asks; release-approval §TRIGGERS reads the answer · complexity: complex | w44-T2 | — | — | 90 | REQ-1 | payload/scripts/lib/owed.sh, hooks/poker/plan.sh, hooks/poker/proof.sh, payload/scripts/lib/line.sh, tests/asks.test.sh, tests/release-approval.test.sh, tests/CENSUS.md, .bionic/docs/record/wave-44-every-hand/T2.md | .worktrees/44-T2 | dd425be6 | landed | — | — | — |
| T3 | 4 | build | One function says what blocks. Every surface asks the same function whether an ask blocks the user. The sheet, the handoff head, the Patrol line and the card verb read the one function (D7, D8; AC-1.1's sheet half, AC-2.3, AC-9.2). `sitrep_asks` prints `waits=` from `ask_waits_on`; `sitrep_ask_lines` writes `blocks=yes` only for an ask that holds something and waits on the user, and appends `waits=user` or `waits=event <what>` last; `ho_state` prints `Blocked on you: yes` only when some ask has `blocks=yes`; `sitrep_status` prints `owed: <n> on you · <m> on events` and the tick line carries both; `sitrep card` runs `decisions_settle`, reads the saved sheet, refreshes its `ask:` lines through `sitrep_asks` alone and never re-gathers. §ONE-BLOCKS and §FAST in sitrep (a planted divergence between the sheet, the handoff head and the Patrol line reddens; the two verbs on a copy of the wave-43 plan under 5 s); handoff-file §HEAD HD1 to HD3 rewritten to the rule · complexity: standard | w44-T3 | — | approval:plan, .bionic/docs/record/wave-44-every-hand/T2.md | 75 | REQ-1, REQ-2, REQ-9 | hooks/poker/sitrep.sh, hooks/poker/tick.sh, tests/sitrep.test.sh, tests/handoff-file.test.sh, tests/CENSUS.md, .bionic/docs/record/wave-44-every-hand/T3.md | .worktrees/44-T3 | 8b16a4f8 | landed | — | — | — |
| T4 | 4 | build | The sheet carries the goal. The sheet says what the wave is for and where each theme stands. The sheet says what the wave is for, and a theme's standing (D1; AC-6.1, AC-6.2, AC-8.1 to AC-8.3). `plan_goal_paragraph` in `lib/plan.sh`, moved from the requirements card's parse (card.sh:843-847, which calls it); `sitrep_gather` prints `run.goal:`; `plan_themes` reads the first body line under each `## <theme>` and `_plan_theme_reads` carries it as `for=` last on the `goal:` line; at task scale `plan_themes` yields one theme, `the run`, over every REQ with a matrix row; `plan_goal_status` maps pending with at least one criterion discharged to `on course`, and the release card's mark map (hooks/poker/plan.sh:2516-2524) and the card's Goals line learn the word; the Goals line reads per theme `<theme> k of n[, REQ-a open]`; `tick_owed_goals` opens no `decide:goal:` for a measured goal whose miss is a declared red (a `Lands-red:` row's debt line). §RUN-GOAL, §FOR, §GOAL-AGREE, §TASK-GOAL, §DECLARED-RED in sitrep; release-approval §GOALS green · complexity: standard | w44-T4 | — | — | 75 | REQ-6, REQ-8 | payload/scripts/lib/plan.sh, payload/scripts/card.sh, hooks/poker/plan.sh, hooks/poker/tick.sh, hooks/poker/sitrep.sh, tests/sitrep.test.sh, tests/release-approval.test.sh, tests/CENSUS.md, .bionic/docs/record/wave-44-every-hand/T4.md | .worktrees/44-T4 | dd425be6 | landed | — | — | — |
| T5 | 4 | build | The skill, seven lines. The sitrep skill asks the model for seven lines of judgment and nothing else. The skill is the new shape, and every judgment fixture is seven lines (D6, D7; AC-4.3's text half, AC-5.1). `skills/sitrep/SKILL.md` rewritten: the two verbs, the seven lines, the standard ("the handful of facts that change what you do next"), the Purpose question in place of the Goals question, "nothing tonight" when every open ask waits on an event, show the tool's card once inside one fenced block and never retype it, a seven-line example; `agents-src/templates/commands/help.md.tmpl`'s sitrep line and its render; the judgment fixtures in sitrep-card (`SC_J_*`, `SV_J`), card (`SIT_JUDGE`), words §RENDERED and `rt_judgment` in `tests/lib/rehearsal-read.sh` rewritten to seven lines; sitrep-card §SKILL SK0 and sitrep §SKILL SK9 re-pinned to the new tags and example; words §TEXTS green · complexity: standard | w44-T5 | — | approval:plan, .bionic/docs/record/wave-44-every-hand/T1.md, .bionic/docs/record/wave-44-every-hand/T3.md, .bionic/docs/record/wave-44-every-hand/T4.md | 75 | REQ-4, REQ-5 | skills/sitrep/SKILL.md, agents-src/templates/commands/help.md.tmpl, payload/commands/help.md, payload/integrity/rendered.sha256, tests/words.test.sh, tests/lib/rehearsal-read.sh, tests/rehearsal.test.sh, tests/rehearsal-failed-review.test.sh, tests/rehearsal-release-waiting.test.sh, tests/rehearsal-stop-rule.test.sh, tests/sitrep-card.test.sh, tests/sitrep.test.sh, tests/card.test.sh, tests/CENSUS.md, .bionic/docs/record/wave-44-every-hand/T5.md, hooks/session-poker.sh | .worktrees/44-T5 | 7bc8545b | landed | — | — | — |
| T6 | 5 | verify | The walk and the matrix. A person reads the card as a user would, and the matrix fills from the landings. The walk and the matrix (walk: required). The card drawn on the wave-43 plan and on the §MOCKUP sheet read as a user would, against the approved mock-up; the matrix filled from the landings' logs · complexity: complex | w44-T6 | — | — | 45 | REQ-10 | .bionic/docs/record/wave-44-every-hand/walk.md | — | — | landed | — | — | record/wave-44-every-hand/walk.md |
| T7 | 5 | verify | The regression, once. The whole suite runs once after the build, and a red becomes a fix row. The regression, once after the build: `regression-run`, then `proof-add regression`; a red is a fix row's, never a second run · complexity: standard | — | — | approval:plan, head, .bionic/docs/record/wave-44-every-hand/walk.md | 30 | REQ-9 | .bionic/docs/record/wave-44-every-hand/T7.md | — | — | landed | — | — | record/wave-44-every-hand/T7.md |
| T8 | 5 | verify | Four sitreps timed. Four sitreps are timed from the typed command to the shown card. Four sitreps timed (AC-9.1). The orchestrator runs `/bionic:sitrep` four times on this plan after the build settled, reads each from the transcript as research-sitrep-latency.md did, typed command to shown card, and records the four timings and the refusal count in `record/wave-44-every-hand/sitrep-timing.md` · complexity: standard | — | — | approval:plan, head, .bionic/docs/record/wave-44-every-hand/T5.md, approval:D10 | 30 | REQ-9 | .bionic/docs/record/wave-44-every-hand/sitrep-timing.md | — | — | landed | — | — | record/wave-44-every-hand/sitrep-timing.md |
| T9 | 6 | review | The critic reads the whole. One independent reader reviews the whole run once. The critic's review of the whole (single rigor: evidence, adversarial, structure; one record per question) · complexity: complex | w44-T9 | — | approval:plan, head, .bionic/docs/record/wave-44-every-hand/walk.md, .bionic/docs/record/wave-44-every-hand/T7.md | 60 | REQ-10 | .bionic/docs/record/wave-44-every-hand/critic-evidence.md, .bionic/docs/record/wave-44-every-hand/critic-adversarial.md, .bionic/docs/record/wave-44-every-hand/critic-structure.md | — | — | landed | — | — | record/wave-44-every-hand/critic-evidence.md |
| T10 | 7 | doc | The release row: 1.27.0. The release is versioned, its entry written and its decision recorded. plugin.json and the command pages at 1.27.0, the CHANGELOG entry with its Known limits and landing numbers, ADR-071 "code draws the facts, the model judges" · complexity: standard | w44-T10 | — | approval:plan, tests/sitrep-card.test.sh | 30 | REQ-10 | CHANGELOG.md, payload/.claude-plugin/plugin.json, payload/commands/help.md, payload/commands/version.md, payload/integrity/rendered.sha256, docs/adrs/adr-071-code-draws-the-facts-the-model-judges.md, tests/release-check.test.sh, tests/CENSUS.md, .bionic/docs/record/wave-44-every-hand/T10.md | .worktrees/44-T10 | a2d0b7cd | landed | — | — | — |
| T11 | 8 | integrate | The pull request. The run reaches main by a pull request after its reviews are published. Open the pull request from wave/44-every-hand to main on the release approval card's word, after `reviews-part T11` · complexity: standard | — | — | — | 15 | REQ-10 | .bionic/docs/record/wave-44-every-hand/T11-pr.md | — | — | landed | — | — | — |
| T12 | 9 | close | Close-out. The run closes and reports its hand-holds reading. Close-out: the checklist, the rollback, continuation.md; the hand-holds reading reported, not judged · complexity: standard | — | — | — | 20 | REQ-10 | .bionic/docs/record/wave-44-every-hand/continuation.md | — | — | landed | — | — | — |
| T13 | 4 | build | The cards show titles. Every card prints each item's short title and refuses a longer one. (AC-11.1 to AC-11.4; Δ13.) One rule on three cards: an item opens on a title of at most 30 characters, the card prints the title, `explain` prints the rest, and a longer title is refused with the item and its length named, never cut. Step-3 card: every `## Tasks` cell opens on its title, then a period and the detail; the card prints the title alone, `serves` in its own column, consecutive ids in `depends` as a range (`T1–T5`); `show task <n>` prints the whole cell. Step-1 card: every `### REQ-<n> — <title>` title; the card prints id, title and criteria count, no provenance, which `explain <requirement>` prints; every `## Not Doing` item opens on a title, then a colon and the reason; the card prints the titles and `explain not-doing` the items. Step-2 card: every `- **D<n> — <title>**` title; the card prints a decision as id, title, serves and ADR, `explain <decision>` the detail; the `### Worth your eye` section is renamed `### Risks`, each item the model's own judgment in one to three sentences, drawn whole and folded with no cap, the old heading still accepted. The Step-1, Step-2 and Step-3 texts (agents-src templates and their renders) state the rules; `card.test.sh` §TITLES, §REQ-TITLES, §NOT-DOING-TITLES and §DESIGN-TITLES pin them · complexity: standard | w44-T13 | — | approval:plan, .bionic/docs/record/wave-44-every-hand/T1.md | 45 | REQ-11, REQ-12, REQ-13, REQ-14 | payload/scripts/card.sh, agents-src/templates/skills/canonical-sdlc/steps/1.md.tmpl, skills/canonical-sdlc/steps/1.md, agents-src/templates/skills/canonical-sdlc/steps/2.md.tmpl, skills/canonical-sdlc/steps/2.md, agents-src/templates/skills/canonical-sdlc/steps/3.md.tmpl, skills/canonical-sdlc/steps/3.md, payload/integrity/rendered.sha256, tests/card.test.sh, tests/CENSUS.md, .bionic/docs/record/wave-44-every-hand/T13.md | .worktrees/44-T13 | 41729276 | landed | — | — | — |
| T14 | 4 | build | The carry names its row. A carried finding names the row that will fix it. A verb records a carry that names a row (D8; AC-1.2 as the Eval design states it): `finding-move <record>#<n> carried T<n>`, three operands beside the `fixed` arm in `hooks/session-poker.sh`, has `poker_verb_finding_move` in `hooks/poker/proof.sh` write its `moved:` line, call `owed_answer finding:<id> carry "T<n> lands"` and leave the item open, so the landing arm T2 built in `lib/line.sh` closes it from a verb and not only from a planted answer; `fixed` and `defer` are unchanged. asks §ANSWER gains the verb arm (AN-13, AN-14) · complexity: standard | w44-T14 | — | approval:plan, .bionic/docs/record/wave-44-every-hand/T2.md | 20 | REQ-1 | hooks/session-poker.sh, hooks/poker/proof.sh, tests/asks.test.sh, tests/CENSUS.md, .bionic/docs/record/wave-44-every-hand/T14.md | .worktrees/44-T14 | 41729276 | landed | — | — | — |
| T15 | 4 | build | The blocked read quits no pipe. The check for asks that block the user never breaks its own pipe. `sitrep_blocked_on_you` in `hooks/poker/sitrep.sh` captures `sitrep_ask_lines` into a variable and matches the string (a `case` or a grep over `printf`), so no writer feeds a reader that quits early and the head never reads `no` for a true `yes` under pipefail; shell-lint BP-1 is red on the line at a2d0b7cd1 (T10-shell-lint.log, 168/169) and goes green; sitrep §ONE-BLOCKS and handoff-file §HEAD stay green · complexity: standard | w44-T15 | — | — | 10 | REQ-2 | hooks/poker/sitrep.sh, .bionic/docs/record/wave-44-every-hand/T15.md | .worktrees/44-T15 | a2d0b7cd | landed | — | — | — |
| T16 | 4 | build | The Goals row states themes. The Goals row names each theme with its count of met criteria. The sitrep card draws each theme of the sheet's `goal:` lines as `<theme> k of n[, REQ-a open]` on the Metrics Goals row (the k of n from the line's `measure=`, the open REQs from its text), not a count by status; `_card_bind` adds the `goal:` lines' numbers to the values a judgment number may match, so a true "24 of 25 criteria discharged" in the purpose draws and a false count is refused; the §MOCKUP and wave-43 fixtures' Goals rows read the themes. sitrep-card §TABLE and §BIND gain the arms (TB7, BI8); card.test.sh KINDS-7 stays green · complexity: standard · born: review | w44-T16 | — | — | 30 | REQ-6, REQ-8 | payload/scripts/card.sh, tests/sitrep-card.test.sh, tests/CENSUS.md, .bionic/docs/record/wave-44-every-hand/T16.md | .worktrees/44-T16 | afb40d25 | landed | sitrep-card.test.sh, card.test.sh | sitrep-card.test.sh, card.test.sh | — |
| T17 | 6 | review | The critic reads the fix. The critic re-reads the first fix as a piece. The critic re-reads row T16 as a piece (evidence, adversarial, structure; one record per question, a new record path each: critic-evidence-2.md, critic-adversarial-2.md, critic-structure-2.md), and whether the S2 finding it was born of now holds · complexity: complex | w44-T17 | — | approval:plan, .bionic/docs/record/wave-44-every-hand/T16.md | 30 | REQ-6, REQ-8 | .bionic/docs/record/wave-44-every-hand/critic-evidence-2.md, .bionic/docs/record/wave-44-every-hand/critic-adversarial-2.md, .bionic/docs/record/wave-44-every-hand/critic-structure-2.md | — | — | landed | — | — | .bionic/docs/record/wave-44-every-hand/critic-evidence-2.md |
| T18 | 4 | build | The Goals row keeps standing. The Goals row keeps each theme's standing word beside its count. `_card_goals_cell` in `payload/scripts/card.sh` draws each theme of the sheet's `goal:` lines as `<theme> <status>, k of n[, REQ-a open]`, the standing word read from the line's `status=` (met, on course, not met, not measured, unreadable), so a theme that is not met never draws like one on course; the binding keeps the counts T16 admitted; sitrep-card §TABLE TB7a asserts the standing word is drawn and TB7d adds a `not met` theme to the fixture; the §MOCKUP and wave-43 goldens' Goals rows follow; card.test.sh KINDS-7 stays green · complexity: standard · born: review | w44-T18 | — | — | 25 | REQ-6, REQ-8 | payload/scripts/card.sh, tests/sitrep-card.test.sh, tests/CENSUS.md, .bionic/docs/record/wave-44-every-hand/T18.md | .worktrees/44-T18 | 268aaf74 | landed | sitrep-card.test.sh, card.test.sh | sitrep-card.test.sh, card.test.sh | — |
| T19 | 6 | review | The critic reads fix two. The critic re-reads the second fix as a piece. The critic re-reads row T18 as a piece (evidence, adversarial, structure; one record per question at new paths critic-evidence-3.md, critic-adversarial-3.md, critic-structure-3.md), and whether AC-8.1 now holds at its tier · complexity: complex | w44-T19 | — | approval:plan, .bionic/docs/record/wave-44-every-hand/T18.md | 30 | REQ-6, REQ-8 | .bionic/docs/record/wave-44-every-hand/critic-evidence-3.md, .bionic/docs/record/wave-44-every-hand/critic-adversarial-3.md, .bionic/docs/record/wave-44-every-hand/critic-structure-3.md | — | — | landed | — | — | .bionic/docs/record/wave-44-every-hand/critic-evidence-3.md |
| T20 | 4 | build | The sitrep takes no argument. The sitrep reads the bound run and takes no plan argument. `skills/sitrep/SKILL.md` drops the plan argument from the user surface (D13): the sentence offering `/bionic:sitrep <plan>` and the `[<plan>]` operands in its two command blocks go, and the text says the sitrep reports on the bound run only; the verbs keep `[<plan>]` as the hermetic door the suites use; sitrep-card.test.sh (which pins the skill text) stays green · complexity: standard | — | — | — | 10 | REQ-10 | skills/sitrep/SKILL.md, .bionic/docs/record/wave-44-every-hand/T20.md | .worktrees/44-T20 | 5748e5b2 | landed | — | — | — |
| T21 | 4 | build | The Goals cell is renamed. The Goals drawing gets a name that no retired writer's pin matches. Two reds of the whole run at 8452c79d7 (regression-run-8452c79d7a0b.log, sitrep.test.sh 281/284): GO1 finds the Goals cell's old name in `payload/scripts/card.sh` because it matches the retired goals writer's pattern, so the function is renamed `_card_goals_cell` at its three sites; SK0 and SK0b pin `sitrep [<plan>]` and `sitrep card [<plan>]` in the skill text T20 changed on D13, so the two expectations read the skill as it now writes them; sitrep.test.sh, card.test.sh and sitrep-card.test.sh green · complexity: standard | w44-T21 | — | — | 15 | REQ-8 | payload/scripts/card.sh, tests/sitrep.test.sh, tests/sitrep-card.test.sh, .bionic/docs/record/wave-44-every-hand/T21.md | .worktrees/44-T21 | 8452c79d | landed | — | — | — |

The card lands first and alone with the mock-up fixture (T1), red at the base, the real card the user sees before the build fans out; the register (T2) runs beside it; T3 waits on T2; T4 runs beside T3; T5 waits on T1, T3 and T4 and rewrites their fixtures; the walk (T6), the regression (T7), the timed sitreps (T8), the critic (T9), the release row (T10), the pull request (T11) and close-out (T12) follow.

## Verification Matrix

stack-health: before, the build head a2d0b7cd1 (2026-10-24T08:34Z): every landing suite green, shell-lint red on BP-1 at that head (T10-shell-lint.log, 168/169); after, the regression at afb40d258 (2026-10-24T09:17Z, after fix row T15): 126 passed, 0 failed (regression-run-afb40d2584fbd4cb31ba9d0523096c1ff7c95dbd.log)
auditor-wave: REFUTED — the critic (w44-T9, critic-evidence.md, single rigor: the critic holds evidence) confirmed 21 of 25 rows; AC-8.1 REFUTED (fix row T16, re-read T17), AC-14.1 REFUTED (deferred S3, the user's at the release card), AC-10.1 and AC-9.1 UNVERIFIABLE (the mock-up is in no record; the thirty seconds waits on T8)
walk-artifact: record/wave-44-every-hand/walk.md

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1.1 | T2 | discharged | record/wave-44-every-hand/line/T14-asks-d85a2b342d51.log | CONFIRMED |
| AC-1.2 | T2 | discharged | record/wave-44-every-hand/line/T14-asks-d85a2b342d51.log | CONFIRMED |
| AC-2.1 | T1 | discharged | record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log | CONFIRMED |
| AC-2.2 | T1 | discharged | record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log | CONFIRMED |
| AC-2.3 | T2 | discharged | record/wave-44-every-hand/line/T3-sitrep-7bc8545b0db2.log | CONFIRMED |
| AC-3.1 | T1 | discharged | record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log | CONFIRMED |
| AC-3.2 | T1 | discharged | record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log | CONFIRMED |
| AC-3.3 | T1 | discharged | record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log | CONFIRMED |
| AC-4.1 | T1 | discharged | record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log | CONFIRMED |
| AC-4.2 | T1 | discharged | record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log | CONFIRMED |
| AC-4.3 | T0 | discharged | record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log | CONFIRMED |
| AC-5.1 | T0 | discharged | record/wave-44-every-hand/line/T5-words-a2d0b7cd15a3.log | CONFIRMED |
| AC-6.1 | T2 | discharged | record/wave-44-every-hand/line/T4-sitrep-aba61f74eced.log | CONFIRMED |
| AC-6.2 | T2 | discharged | record/wave-44-every-hand/line/T4-sitrep-aba61f74eced.log | CONFIRMED |
| AC-7.1 | T1 | discharged | record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log | CONFIRMED |
| AC-8.1 | T2 | discharged | record/wave-44-every-hand/line/T18-sitrep-card-aa948d2205fa.log | CONFIRMED |
| AC-8.2 | T2 | discharged | record/wave-44-every-hand/line/T4-sitrep-aba61f74eced.log | CONFIRMED |
| AC-8.3 | T2 | discharged | record/wave-44-every-hand/line/T4-sitrep-aba61f74eced.log | CONFIRMED |
| AC-9.1 | T4 | waived | — | pending |
| AC-9.2 | T2 | discharged | record/wave-44-every-hand/line/T3-sitrep-7bc8545b0db2.log | CONFIRMED |
| AC-10.1 | T1 | waived | record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log | pending |
| AC-11.1 | T1 | discharged | record/wave-44-every-hand/line/T13-card-97542f066e21.log | CONFIRMED |
| AC-12.1 | T1 | discharged | record/wave-44-every-hand/line/T13-card-97542f066e21.log | CONFIRMED |
| AC-13.1 | T1 | discharged | record/wave-44-every-hand/line/T13-card-97542f066e21.log | CONFIRMED |
| AC-14.1 | T1 | waived | record/wave-44-every-hand/line/T13-card-97542f066e21.log | pending |

AC-1.1: Every ask on the register reads `waits-on=user` or `waits-on=event <what>`: a decision, an approval and an unanswered waiver wait on the user; a waiver answered "no" waits on the review's next run; a finding carried to a row waits on that row's landing; the sheet's `ask:` line carries the field.
  provenance: charter §Cut (the large-app card's "Blocked on you doesn't seem like it's truly blocked"); sheet-definitions.md (an ask line carries holds= and blocks=, nothing of who it waits on)
  fails-when: the refused waiver reads user, or a line lacks the field
  eval: T2 — `asks.test.sh` §WAITS: `ask_waits_on` says user for a decision, an approval and an unanswered waiver, event for a waiver answered no and a finding answered carry; the sheet's `ask:` lines carry `waits=`
  task: T2, T14
  evidence: record/wave-44-every-hand/line/T14-asks-d85a2b342d51.log
AC-1.2: A reply of "no" to a waiver, and a finding ruled "carry" or "defer", record the answer on the ask and move it to `waits-on=event` without closing it; the ask closes as it does today, when the review passes or the row lands.
  provenance: charter §Cut (the large-app card's "Blocked on you doesn't seem like it's truly blocked"); sheet-definitions.md (an ask line carries holds= and blocks=, nothing of who it waits on)
  fails-when: the item closes at the answer, or reads no answer
  eval: T2 — `asks.test.sh` §ANSWER: the item stays open with `answer=no`; the finding stays open with `answer=carry event=T9 lands` and closes when T9's landing is recorded
  task: T2, T14
  evidence: record/wave-44-every-hand/line/T14-asks-d85a2b342d51.log
AC-2.1: Blocked on you lists the asks that wait on the user and hold a task, the release or the merge, and nothing else; with none it reads `None` and names the nearest event the run waits on.
  provenance: charter §Cut ("the Call to action is vapid"); wave 43 deferral critic-adversarial-2.md#2 (adopted: the handoff head follows the card); debt blocked-on-you (card.sh:3042, sitrep.sh:2123) and blocks-rule (sitrep.sh:1616, card.sh:3139)
  fails-when: the refused waiver is drawn, or `None` over the unanswered one
  eval: T1 — `sitrep-card.test.sh` §BLOCKS: `None` naming T86 over the refused waiver; the unanswered waiver drawn under Blocked on you
  task: T1, T5
  evidence: record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log
AC-2.2: The call may say nothing is owed while every open ask waits on an event, and must name the ask while one waits on the user and holds something; the check reads `waits-on`, not `holds`.
  provenance: charter §Cut ("the Call to action is vapid"); wave 43 deferral critic-adversarial-2.md#2 (adopted: the handoff head follows the card); debt blocked-on-you (card.sh:3042, sitrep.sh:2123) and blocks-rule (sitrep.sh:1616, card.sh:3139)
  fails-when: either verdict inverts
  eval: T1 — `sitrep-card.test.sh` §CALL: admitted over the refused waiver, refused over the unanswered one
  task: T1, T5
  evidence: record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log
AC-2.3: The handoff head's `Blocked on you`, the sitrep card and the Patrol's `blocks=` read one function, pinned by one suite row that reddens when any two disagree; the `blocks-rule` and `blocked-on-you` duplicates are gone.
  provenance: charter §Cut ("the Call to action is vapid"); wave 43 deferral critic-adversarial-2.md#2 (adopted: the handoff head follows the card); debt blocked-on-you (card.sh:3042, sitrep.sh:2123) and blocks-rule (sitrep.sh:1616, card.sh:3139)
  fails-when: any two disagree, or the fallback remains
  eval: T2 — `sitrep.test.sh` §ONE-BLOCKS: the sheet, the handoff head and the Patrol line agree over a planted answered waiver; `/usr/bin/grep -c 'nothing.*blocks|blocks=' payload/scripts/card.sh` finds no re-derivation
  task: T1, T3
  evidence: record/wave-44-every-hand/line/T3-sitrep-7bc8545b0db2.log
AC-3.1: `sitrep` prints, beside the sheet, the drawn rows of the head, the Task list (every step and task row as today, its text from the plan's task title and its state words from the sheet), the Metrics table, Blocked on you and the first two lines of Predicted close, so the model writes none of them.
  provenance: ledger Δ6 (D6 "1"); research-sitrep-latency.md causes 1 to 3; w38 D9 (one renderer prints every fact)
  fails-when: a task row is missing, or `task:` is accepted
  eval: T1 — `sitrep-card.test.sh` §DRAWN: every step and task row drawn from S and T records; a `task:` line in the judgment refuses by name
  task: T1, T5
  evidence: record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log
AC-3.2: The Metrics are a five-line table, Completed, Pace, Correctness, Waste, Goals, each cell one sheet value, numbers only, the pace comparison first in its line.
  provenance: ledger Δ6 (D6 "1"); research-sitrep-latency.md causes 1 to 3; w38 D9 (one renderer prints every fact)
  fails-when: a digit no line holds, or prose
  eval: T1 — `sitrep-card.test.sh` §TABLE: five lines, every digit run a measured value of its line, the pace comparison first
  task: T1, T5
  evidence: record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log
AC-3.3: Items that wait on events are one drawn line under the Assessment, counted by kind ("14 items wait on landings, not on you: 8 carried findings, 6 rulings given"), never one row each.
  provenance: ledger Δ6 (D6 "1"); research-sitrep-latency.md causes 1 to 3; w38 D9 (one renderer prints every fact)
  fails-when: an ask is drawn as a row
  eval: T1 — `sitrep-card.test.sh` §COUNTED: one line "14 items wait on landings, not on you: 8 carried findings, 6 rulings given" under the Assessment
  task: T1, T5
  evidence: record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log
AC-4.1: The judgment the model pipes to `sitrep card` is: `purpose:`, `call:`, `grade:`, one to three `point:` lines, one `ask <key>:` recommendation per ask that waits on the user, and one `close:` condition line; the check refuses any other tag, and refuses a missing one by name.
  provenance: ledger Δ6, Δ7; research-sitrep-latency.md (refusal classes: metric binding 4, row wrap 4, state word 2, reading/reader 2)
  fails-when: a foreign tag draws, or a missing one is unnamed
  eval: T1 — `sitrep-card.test.sh` §TAGS: the seven accepted; `metric:` refused by name; a missing `purpose:` refused by name
  task: T1, T5
  evidence: record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log
AC-4.2: Every number in a judgment line is bound to the sheet value whose word stands beside it, by word and by place, as the metrics were; a line over the card's width is folded by the renderer, never refused.
  provenance: ledger Δ6, Δ7; research-sitrep-latency.md (refusal classes: metric binding 4, row wrap 4, state word 2, reading/reader 2)
  fails-when: the swap passes, or the fold refuses
  eval: T1 — `sitrep-card.test.sh` §BIND: "1 green and 11 red" over "11 green, 1 red" refuses; a number on no line refuses; the long point folds and draws
  task: T1, T5
  evidence: record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log
AC-4.3: The tool shows the card; the skill tells the model to print the tool's output once inside one fenced block and never to retype it, and a refusal prints every reason at once.
  provenance: ledger Δ6, Δ7; research-sitrep-latency.md (refusal classes: metric binding 4, row wrap 4, state word 2, reading/reader 2)
  fails-when: the text asks to retype, or the second reason waits for a second run
  eval: T0 — `/usr/bin/grep -n 'fenced' skills/sitrep/SKILL.md` finds the show-once rule and no "regenerate"; `sitrep-card.test.sh` §REASONS: a judgment missing purpose and holding a bad number prints both reasons on one refusal
  task: T1, T5
  evidence: record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log
AC-5.1: `skills/sitrep/SKILL.md` describes the two verbs, the seven judgment lines, the Purpose question in place of the Goals question, and the rule that an ask waiting on an event owes the user nothing; its example judgment is seven lines; `words.test.sh` and the sitrep-card suite's skill section pin it.
  provenance: ledger Δ6, Δ7; skills/sitrep/SKILL.md (the six questions, the Goals question, "every open ask answered once")
  fails-when: an old tag remains in the example, or the Goals question
  eval: T0 — `/usr/bin/grep -c 'task:|metric:' skills/sitrep/SKILL.md` → 0 outside the refusal list; §SKILL rows of sitrep-card and sitrep read the seven tags and the Purpose question; `words.test.sh` §TEXTS green
  task: T5
  evidence: record/wave-44-every-hand/line/T5-words-a2d0b7cd15a3.log
AC-6.1: The sheet carries `run.goal:`, the plan's `## Goal` paragraph, so the purpose is drawn from the verb and never fetched by the model.
  provenance: charter §Late addition ("reasserting what the wave is doing"); research-sitrep-concept.md Q3; wave 41 D13
  fails-when: the line differs, or an error prints
  eval: T2 — `sitrep.test.sh` §RUN-GOAL: `run.goal:` equals the paragraph the Step-1 card prints; the Goal-less plan prints no line and no error
  task: T4
  evidence: record/wave-44-every-hand/line/T4-sitrep-aba61f74eced.log
AC-6.2: Each theme's `goal:` line carries the theme's opening sentence as its last field, `for=`, with the fields the release card reads kept in place.
  provenance: charter §Late addition ("reasserting what the wave is doing"); research-sitrep-concept.md Q3; wave 41 D13
  fails-when: a line lacks `for=`, or the release card's read changes
  eval: T2 — `sitrep.test.sh` §FOR: each `goal:` line ends `for=<opener>`; `release-approval.test.sh` §GOALS unchanged green
  task: T4
  evidence: record/wave-44-every-hand/line/T4-sitrep-aba61f74eced.log
AC-7.1: The Assessment's first row is the `purpose:` line, what the wave is for and whether it is on course; a judgment without it is refused, and its numbers are checked against the sheet as every line's are.
  provenance: charter §Late addition ("whether we're accomplishing the purpose of the wave"); ledger Δ1 (D1 "1")
  fails-when: a card draws without it, or the false count draws
  eval: T1 — `sitrep-card.test.sh` §PURPOSE: the first refuses by name; the second refuses on the number; a true one draws first under the grade
  task: T1, T5
  evidence: record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log
AC-8.1: The Goals line of the Metrics states each theme's criteria discharged and open REQs, each number bound to its theme's name; a theme with at least one criterion discharged and none missed reads `on course`, distinct from `not measured`, on the sheet, the sitrep card and the release card.
  provenance: research-sitrep-concept.md Q2, tweaks 3, 5 and 7; 1.26.0 Known limit 23
  fails-when: the two themes read alike, or the false count draws
  eval: T2 — `sitrep.test.sh` §GOAL-AGREE: `on course` and `not measured` on the sheet, the Goals line and the release card; "Identity 10 of 11" refuses at the card
  task: T4, T16, T18
  evidence: record/wave-44-every-hand/line/T21-sitrep-01f38b51335b.log
AC-8.2: At task scale the sheet reads one goal over the whole matrix, the run's criteria discharged and open REQs.
  provenance: research-sitrep-concept.md Q2, tweaks 3, 5 and 7; 1.26.0 Known limit 23
  fails-when: no goal line
  eval: T2 — `sitrep.test.sh` §TASK-GOAL: one `goal: name=the run` with k of n over the matrix
  task: T4
  evidence: record/wave-44-every-hand/line/T21-sitrep-01f38b51335b.log
AC-8.3: A goal missed by a red the plan itself declares opens no `decide:goal:<name>` ask.
  provenance: research-sitrep-concept.md Q2, tweaks 3, 5 and 7; 1.26.0 Known limit 23
  fails-when: the ask opens, or the real miss opens none
  eval: T2 — `sitrep.test.sh` §DECLARED-RED: the tick opens no `decide:goal:`; a goal missed otherwise still opens one
  task: T4
  evidence: record/wave-44-every-hand/line/T21-sitrep-01f38b51335b.log
AC-9.1: Three sitreps run in a row on a live plan, measured from the typed command to the shown card in the transcript as research-sitrep-latency.md measured, each take under 30 seconds, with at most one card refusal among the three. Evidence is the measurement recorded at Step 5.
  provenance: charter §Cut ("Right now this is fucking wasting my time!"); research-sitrep-latency.md (74 to 108 s; model output 90%)
  fails-when: one at 30 s or more, or two refusals
  eval: T4 — the transcript timings recorded in `record/wave-44-every-hand/sitrep-timing.md`, each under 30 s, at most one refusal
  task: T8
  evidence: pending
  user-confirmed: pending
  waiver: Chris Lehman 2026-10-24T16:04:40Z "option 1 - good enough. Much happier with /sitrep." — measured 64 s and 40 s typed-to-card (sitrep-timing.md), the verbs under three seconds; the rest is the model, which no sheet edit reaches; the limit is stated in the 1.27.0 entry
AC-9.2: The machine side of a sitrep, the sheet and the card together, takes under 5 seconds on the wave-43 plan.
  provenance: charter §Cut ("Right now this is fucking wasting my time!"); research-sitrep-latency.md (74 to 108 s; model output 90%)
  fails-when: 5 s or more
  eval: T2 — `sitrep.test.sh` §FAST: `sitrep` then `sitrep card` on a copy of the wave-43 plan and record under 5 s together
  task: T3
  evidence: record/wave-44-every-hand/line/T3-sitrep-7bc8545b0db2.log
AC-10.1: A fixture shaped like the large-app card (17 open tasks, 14 items waiting on events, a refused waiver holding the merge, 54 added tasks) draws the mock-up's shape: Call to action one line saying nothing is owed, the Task list as today, a five-line Metrics table, an Assessment of the purpose, at most three points and one counted line, Blocked on you `None` with the event named, Predicted close in three lines; the drawn card is under 40 rows.
  provenance: ledger Δ7 (the mock-up Chris approved: "Yes! That is what I want!")
  fails-when: a register item is a row, the merge reads blocked, 40 rows or more, or green at the base
  eval: T1 — `sitrep-card.test.sh` §MOCKUP: the drawn card equals the mock-up's shape line for line (sections, counts, `None`, three close lines), under 40 rows; red at dd425be64 on the unknown `purpose:` tag, T1's red log in record/
  task: T1, T5
  evidence: record/wave-44-every-hand/line/T5-sitrep-card-a2d0b7cd15a3.log
  waiver: Chris Lehman 2026-10-24T17:58:16Z "all recommended" — not confirmed by the auditor on this release
AC-11.1: A `## Tasks` cell opens on a title of at most 30 characters, then a period and the detail; the Step-3 card prints the title alone, `serves` in its own column and consecutive ids in `depends` as a range; `show task <n>` prints the whole cell; the Step-3 text states the rule; a longer title is refused by the card, which names the row and its length, never cut.
  provenance: user 2026-10-23 "Each task description is far too long. It's not useful whatsoever. I need a brief summary or phrase that represents what the task is. Maybe 25-30 characters max." and "Yes! That's so much more useful OMG" at the mock-up (ledger Δ13)
  fails-when: the detail prints, the long title draws, or the step text lacks the rule
  eval: T1 — `card.test.sh` §TITLES: the Step-3 card's task block prints each title alone with `serves` in its own column and `T1–T5` for a run of ids; the 31-character title is refused with its row and length named; `show task 1` prints the whole cell; `/usr/bin/grep -c 'title of at most 30' skills/canonical-sdlc/steps/3.md` → 1
  task: T13
  evidence: record/wave-44-every-hand/line/T13-card-97542f066e21.log
AC-12.1: A `### REQ-<n> — <title>` heading's title is at most 30 characters; the Step-1 card prints each requirement as its id, its title and its criteria count on one line, the provenance under `explain <requirement>` only; a longer title is refused by the card, which names the requirement and its length, never cut; the Step-1 text states the rule.
  provenance: user 2026-10-23 "Each task description is far too long. It's not useful whatsoever. I need a brief summary or phrase that represents what the task is. Maybe 25-30 characters max." and "Yes! That's so much more useful OMG" at the mock-up (ledger Δ13); user 2026-10-23 "you need to do the same thing for the requirements card. Each requirement desc needs to be capped at 30 chars."
  fails-when: a provenance prints, the long title draws, or the step text lacks the rule
  eval: T1 — `card.test.sh` §REQ-TITLES: the Step-1 card prints `REQ-n  <title>  ACs k` per requirement and no provenance; the long title is refused with its requirement and length named; `explain REQ-1` prints the provenance; `/usr/bin/grep -c 'at most 30' skills/canonical-sdlc/steps/1.md` → 1
  task: T13
  evidence: record/wave-44-every-hand/line/T13-card-97542f066e21.log
AC-13.1: Every `## Not Doing` item opens on a title of at most 30 characters, then a colon and the reason; the Step-1 card prints the titles, one per line, and `explain not-doing` prints the items whole; a longer title is refused by the card, naming the item, never cut; the Step-1 text states the rule.
  provenance: user 2026-10-23 "Not Doing is way too wordy! It needs to be summarized!"
  fails-when: a reason prints, the long title draws, or the step text lacks the rule
  eval: T1 — `card.test.sh` §NOT-DOING-TITLES: the Step-1 card prints each item's title on one line and no reason; the long title is refused with the item named; `explain not-doing` prints the items whole
  task: T13
  evidence: record/wave-44-every-hand/line/T13-card-97542f066e21.log
AC-14.1: Every `- D<n> — <title>` decision title is at most 30 characters; the Step-2 card prints each decision as its id, its title, the requirements it serves and its ADR, `explain <decision>` printing the detail; a longer title is refused by the card, naming the decision, never cut. The spec's `### Worth your eye` section is `### Risks`: each item is the model's own judgment of one risk that could change the user's decision, a sentence or two, and nothing that is not such a risk; drawn whole and folded, with no cap and no required shape; the card accepts the old heading on a spec written before 1.27.0. The Step-2 text states both.
  provenance: user 2026-10-23 "Decisions capped to 30 characters"; "the Worth your eye section should probably be called Risks"; "I thought you were summarizing to the material points only"
  fails-when: the long title draws, a risk is cut, or the section reads Worth your eye
  eval: T1 — `card.test.sh` §DESIGN-TITLES: the Step-2 card prints each decision as id, title, serves and ADR and refuses the long title naming it; the Risks section draws whole under `Risks`, folded, never cut; a spec with `### Worth your eye` still draws
  task: T13
  evidence: record/wave-44-every-hand/line/T13-card-97542f066e21.log
  waiver: Chris Lehman 2026-10-24T17:58:17Z "all recommended" — not confirmed by the auditor on this release

## SDLC State

integration-branch: main
working-branch: wave/44-every-hand
base: main @ dd425be64 (1.26.0)
intent: build
rigor: single
scale: task
current: 9
approved-by: Chris Lehman 2026-10-24T06:28Z "approved"

W44PLAN
whole_card step1 "$REAL_REQ"; S1_REAL="$WC_OUT"; S1_REAL_RC="$WC_RC"
whole_card step2 "$REAL_SPEC"; S2_REAL="$WC_OUT"; S2_REAL_RC="$WC_RC"
whole_card step3 "$REAL_PLAN"; S3_REAL="$WC_OUT"; S3_REAL_RC="$WC_RC"

expect_empty "67: no line of the in-tree Step-1 fixture card exceeds the budget, Artifacts included" \
  "$(over_budget "$S1_IT")"
expect_empty "67a: …nor of the in-tree Step-2 fixture card" "$(over_budget "$S2_IT")"
expect_empty "67b: …nor of the in-tree Step-3 fixture card" "$(over_budget "$S3_IT")"
expect_eq "67c0: precondition: the Step-1 card over the suite's copy of a real run's requirements renders (exit 0, its REQ-1 row present, 14 sentence lines at least)" "0|yes|yes" \
  "$S1_REAL_RC|$(printf '%s\n' "$S1_REAL" | /usr/bin/grep -q '^ *REQ-1 ' && echo yes)|$([ "$(printf '%s\n' "$S1_REAL" | /usr/bin/grep -c '^            [A-Z]')" -ge 14 ] && echo yes)"
expect_eq "67e0: precondition: the Step-3 card over the suite's copy of a real run's plan renders (exit 0, its T1 row present)" "0|yes" \
  "$S3_REAL_RC|$(printf '%s\n' "$S3_REAL" | /usr/bin/grep -q '^ *T1 ' && echo yes)"
# A sentence line starts at the title column, under its row and under any folded serves lines, which start further right.
expect_eq "67e1: …and draws a sentence line under each of its 21 tasks" "21" \
  "$(printf '%s\n' "$S3_REAL" | sed -n '/^  Tasks/,/^$/p' | awk '/^    T[0-9]+ / { r = 1; next } r && /^          [^ ]/ { n++; r = 0; next } !/^           / { r = 0 } END { print n + 0 }')"
expect_empty "67c: nor of the Step-1 card over the suite's copy of a real run's requirements, its sentences included" \
  "$(over_budget "$S1_REAL")"
expect_eq "67d0: precondition: the Step-2 card over the real spec renders (exit 0, its D8 row present)" "0|yes" \
  "$S2_REAL_RC|$(printf '%s\n' "$S2_REAL" | /usr/bin/grep -q '^ *D8 ' && echo yes)"
# A sentence line starts at the title column on a capital; a folded ADR cell continues far to its right.
expect_eq "67d1: …and draws a sentence line under each of its five decisions" "5" \
  "$(printf '%s\n' "$S2_REAL" | sed -n '/^  Decisions/,/^$/p' | /usr/bin/grep -c '^         [A-Z]' | tr -d ' ')"
expect_empty "67d: …nor of the Step-2 card over this wave's own spec" "$(over_budget "$S2_REAL")"
expect_empty "67e: …nor of the Step-3 card over the suite's copy of a real run's plan, its sentences included" "$(over_budget "$S3_REAL")"

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
  rel_fact regression '✅ whole suite: green at abcdef12'
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
✅ whole suite: green at abcdef12

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
| T1 | 4 | build | Parse the ledger. The ledger is parsed once. DETAIL-ALPHA the parser reads the table and nothing else, so a later row cannot change it. complexity: standard | implementor | — | 30 | REQ-1 | lib/a.sh | — | pending |
| T2 | 4 | build | ${T30}. The boundary title has a sentence too. DETAIL-BETA the boundary title is drawn whole. complexity: standard | implementor | — | 30 | REQ-1, REQ-2 | lib/b.sh | — | pending |
| T3 | 4 | build | ${T30_EM}. The dashed title has one as well. DETAIL-GAMMA a title of thirty characters with dashes in it. complexity: standard | implementor | — | 30 | REQ-2 | lib/c.sh | — | pending |
| T4 | 4 | build | Join the rows. The rows are joined in order. DETAIL-DELTA joins what T1 parsed. complexity: complex | senior-implementor | T1, T3 | 45 | REQ-2 | lib/d.sh | — | pending |
| T5 | 5 | test | Prove the join. The join is proved after the four. DETAIL-EPSILON runs after the four. complexity: standard | implementor | T1, T2, T3, T4 | 45 | REQ-2 | tests/d.test.sh | — | pending |
| T6 | 5 | test | Prove the pair. The pair is proved after two. DETAIL-ZETA runs after two. complexity: standard | implementor | T1, T2 | 45 | REQ-1 | tests/e.test.sh | — | pending |

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
    -e 's/Prove the pair\. The pair/Prove the pair of rows is right. The pair/' "$TITLES_PLAN" > "$TITLES_BAD"
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
section "§ABBR: a sentence ends at a period followed by a space and a capital, so an abbreviation never cuts a title"
# ============================================================
# A Tasks cell's title is its first sentence. `vs.`, `e.g.` and `i.e.` end in a period and a space but a lowercase word
# follows them, so the title runs on to the period that is followed by a capital or by the end of the cell. There is no
# word list to keep: the case of the next letter says it. A title cut at an abbreviation would draw "Draw the facts vs"
# at 17 columns and hide that the whole title is 31, over the cap.
# fails-when: a title is cut at an abbreviation, an abbreviation title under the cap is not drawn whole with its
# sentence beside it, one over the cap is drawn, or a period before a capital stops ending the title.
ABBR_LONG="Draw the facts vs. the judgment"
ABBR_SHORT="Fix vs. the old path"
expect_eq "ABBR-0 precondition: the long abbreviation title is 31 columns and the short one 20" "31|20" "$(cols "$ABBR_LONG")|$(cols "$ABBR_SHORT")"
ABBR_OK="${CARD_SANDBOX}/wave-04-flock.plan.md"
sed -e "s/^| T6 | 5 | test | Prove the pair\. The pair is proved after two\./| T6 | 5 | test | ${ABBR_SHORT}. The path is fixed./" "$TITLES_PLAN" > "$ABBR_OK"
expect_eq "ABBR-0b precondition: the plan holds the abbreviation row" "1" "$(/usr/bin/grep -c "^| T6 | 5 | test | ${ABBR_SHORT}\. The path is fixed\. " "$ABBR_OK")"
whole_card step3 "$ABBR_OK"; AB_OUT="$WC_OUT"
expect_eq "ABBR-1 a plan whose title holds an abbreviation within the cap draws (exit 0), silently" "0|" "$WC_RC|$WC_ERR"
expect_contains "ABBR-1b …the title whole, the abbreviation in it" "${ABBR_SHORT}" "$(printf '%s\n' "$AB_OUT" | /usr/bin/grep '^    T6 ')"
expect_contains "ABBR-1c …and the sentence after the period that is followed by a capital" "The path is fixed." "$AB_OUT"
expect_absent "ABBR-1d …and no title cut at the abbreviation" "Fix vs  " "$(printf '%s\n' "$AB_OUT" | /usr/bin/grep '^    T6 ')"
ABBR_BAD="${CARD_SANDBOX}/wave-05-flock.plan.md"
sed -e "s/^| T6 | 5 | test | Prove the pair\. The pair is proved after two\./| T6 | 5 | test | ${ABBR_LONG}. The card draws both./" "$TITLES_PLAN" > "$ABBR_BAD"
whole_card step3 "$ABBR_BAD"
expect_eq "ABBR-2 a 31-column title holding an abbreviation is refused whole: exit 1, no card on stdout" "1|" "$WC_RC|$WC_OUT"
expect_contains "ABBR-2b …naming the row, the length, the cap and the whole title" \
  "REFUSED — task T6: title is 31 characters, the cap is 30: ${ABBR_LONG}" "$WC_ERR"
expect_absent "ABBR-2c …and never the cut one" "Draw the facts vs " "$(printf '%s\n' "$WC_ERR" | sed "s/${ABBR_LONG}//")"
expect_eq "ABBR-2d …and task-cell, which the verbs call, says the same words" "REFUSED — task T6: title is 31 characters, the cap is 30: ${ABBR_LONG}" \
  "$(bash "$CARD_SH" task-cell T6 "${ABBR_LONG}. The card draws both." 2>&1 >/dev/null)"
expect_eq "ABBR-3 a title ending its cell on an abbreviation's period is the whole cell and has no sentence" \
  "REFUSED — task T6: no sentence after its title" "$(bash "$CARD_SH" task-cell T6 "${ABBR_SHORT}." 2>&1 >/dev/null)"
expect_eq "ABBR-3b control: a period before a capital ends the title, as it did" "0" \
  "$(bash "$CARD_SH" task-cell T6 "Fix the path. The path is fixed." >/dev/null 2>&1; echo $?)"

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
# THE FIXTURE IS A REAL SPEC'S SHAPE: the `(D<n>; REQ-…)` group follows the title and the detail follows the group, as
# the specs of the waves write it, so `explain` is read over text that comes after the group.
# fails-when: the card prints a decision's detail, `explain` drops the detail written after the group, a 31-character
# decision title is drawn, a risk is cut or refused for its length, the section still reads Worth your eye, or the
# Step-2 text lacks either rule.
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

- **D1 — ${T30}** (D1; REQ-1). The sync owns the merge. DETAIL-ONE the sync owns the merge and hands the list to the view.
- **D2 — Short title.** (D2; REQ-1, REQ-2). The view draws the list. DETAIL-TWO the view only draws.

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


# ============================================================
section "§DSENTENCE: a decision opens on its sentence, and the Step-2 card prints it under the row"
# ============================================================
# fails-when: a decision with nothing between its title and its group renders, one whose first sentence carries a
# backtick renders, the refusal does not name the decision, the sentence is missing from under its row, cut, or
# folded inside the title column, the row's own line changes, or `explain` loses the detail after the sentence.
DS_SHORT="The sync keeps one list on every phone that has met another."
DS_LONG="Two people who edit the same list while apart both keep their edits when their phones meet again, and each of them is told which edits came from the other phone, so nothing they typed is ever silently lost in the merge."
DS_SPEC="${CARD_SANDBOX}/wave-20-flock.spec.md"
cat > "$DS_SPEC" <<FIXEOF
---
sdlc-step: 2
working-branch: wave/20-flock
integration-branch: main
base-sha: abc1234
adrs: adrs/epic-99/adr-001-sync.md
---

# flock wave 20 · spec

## Goal

Answer the flock's two requirements with decisions that read as concepts.

## Design

The flock syncs two phones and draws one list.

### Component boundaries and interfaces

- **D1 — The sync owns the merge** ${DS_SHORT} DS-DETAIL-ONE the merge in \`lib/sync.sh\` hands the list to the view. (D1; REQ-1)
- **D2 — Short title** Two people who edit the same list while apart both keep their edits when their phones meet
  again, and each of them is told which edits came from the other phone, so nothing they typed is ever silently
  lost in the merge. DS-DETAIL-TWO the view only draws. (D2; REQ-1, REQ-2)

### ADR pointers

- ADR-001 — the sync ruling: \`adrs/epic-99/adr-001-sync.md\` (D1).

## Eval design

| Requirement | Approach | Criterion | Eval type | Eval | Fails when |
|---|---|---|---|---|---|
| REQ-1 | two phones meet and compare lists | AC-1.1 the sync | unit | \`bash tests/sync.test.sh\` | it reds |
| REQ-1 | two phones meet and compare lists | AC-1.2 the merge | hermetic | \`bash tests/merge.test.sh\` | it reds |
| REQ-2 | the view draws one list | AC-2.1 the view | unit | \`bash tests/view.test.sh\` | it reds |
FIXEOF
whole_card step2 "$DS_SPEC"; DS="$WC_OUT"
expect_eq "DSENTENCE-1 step2 draws a spec whose decisions open on their sentences, silently" "0|" "$WC_RC|$WC_ERR"
DS_BLOCK="$(printf '%s\n' "$DS" | sed -n '/^  Decisions/,/^$/p')"
# The extractor is proved on the card first: the row line is found, so the line after it is read from a real block.
expect_contains "DSENTENCE-2 the row keeps its id and its title on its own line" \
  "    D1   The sync owns the merge" "$(printf '%s\n' "$DS_BLOCK" | /usr/bin/grep '^    D1 ')"
expect_eq "DSENTENCE-2b …and the line under it is the decision's sentence, indented past the id" \
  "         ${DS_SHORT}" "$(printf '%s\n' "$DS_BLOCK" | awk '/^    D1 / { getline; print; exit }')"
DS_D2="$(printf '%s\n' "$DS_BLOCK" | awk '/^    D2 / { on = 1; next } on && /^    D[0-9]/ { exit } on && NF { print }')"
expect_eq "DSENTENCE-3 a long sentence folds onto more than one line, every line indented past the id" "yes|0" \
  "$([ "$(printf '%s\n' "$DS_D2" | /usr/bin/grep -c .)" -gt 1 ] && echo yes)|$(printf '%s\n' "$DS_D2" | /usr/bin/grep -vc '^         [^ ]' | tr -d ' ')"
expect_eq "DSENTENCE-3b …and the folded lines are the sentence whole, its source line breaks joined, nothing cut" \
  "$DS_LONG" "$(printf '%s\n' "$DS_D2" | sed -e 's/^ *//' | paste -sd' ' -)"
expect_eq "DSENTENCE-3c …folded at the card's right edge, past the title and serves columns, never inside the title column" "yes" \
  "$([ "$(cols "$(printf '%s\n' "$DS_D2" | head -1)")" -gt 80 ] && echo yes)"
expect_empty "DSENTENCE-3d …and no line of the card exceeds the width, the out-of-project artifact path aside" \
  "$(over_budget "$(printf '%s\n' "$DS" | /usr/bin/grep -v '^    spec  ')")"
expect_eq "DSENTENCE-3e no detail after the sentence is on the card" "" "$(printf '%s\n' "$DS" | /usr/bin/grep 'DS-DETAIL-')"
# THE ROW'S OWN LINES ARE THE FOUR-CELL ROWS BYTE FOR BYTE, and the five-cell TSV rows draw the whole block.
printf 'D1\tThe sync owns the merge\tREQ-1\tadr-001-sync.md\nD2\tShort title\tREQ-1, REQ-2\tnone\n' \
  | card decision > "${CARD_SANDBOX}/ds-tsv4.txt"
printf '%s\n' "$DS_BLOCK" | sed -e '/^$/d' | /usr/bin/grep -v '^         ' > "${CARD_SANDBOX}/ds-rows.txt"
expect_eq "DSENTENCE-4 with its sentence lines out, the block is the four-cell rows byte for byte (precondition: three rows)" "3|same" \
  "$(/usr/bin/grep -c . "${CARD_SANDBOX}/ds-rows.txt" | tr -d ' ')|$(cmp -s "${CARD_SANDBOX}/ds-tsv4.txt" "${CARD_SANDBOX}/ds-rows.txt" && echo same)"
printf 'D1\tThe sync owns the merge\tREQ-1\tadr-001-sync.md\t%s\nD2\tShort title\tREQ-1, REQ-2\tnone\t%s\n' "$DS_SHORT" "$DS_LONG" \
  | card decision > "${CARD_SANDBOX}/ds-tsv5.txt"
printf '%s\n' "$DS_BLOCK" | sed -e '/^$/d' > "${CARD_SANDBOX}/ds-whole.txt"
expect_true "DSENTENCE-4b the whole card's block is byte-identical to the same rows fed as TSV with their sentences" \
  cmp -s "${CARD_SANDBOX}/ds-tsv5.txt" "${CARD_SANDBOX}/ds-whole.txt"
whole_card step2 "$DS_SPEC" explain D1; DS_E="$WC_OUT"
DS_E_DETAIL="$(printf '%s\n' "$DS_E" | awk 'NR == 1 { next } /^    (serves|adr) / { exit } { print }' | sed -e 's/^ *//' | paste -sd' ' -)"
expect_eq "DSENTENCE-5 explain keeps the detail, the text after the sentence (precondition: exit 0)" \
  "0|DS-DETAIL-ONE the merge in lib/sync.sh hands the list to the view." "$WC_RC|$DS_E_DETAIL"
whole_card step2 "$DS_SPEC" explain D2
expect_contains "DSENTENCE-5b …for a sentence that spans source lines too" "DS-DETAIL-TWO the view only draws." "$WC_OUT"

# The planted cases: one decision's sentence and detail taken away, then one sentence given a backticked token.
DS_NONE="${CARD_SANDBOX}/wave-21-flock.spec.md"
sed -e "s/^- \*\*D1 — The sync owns the merge\*\* .*(D1; REQ-1)\$/- **D1 — The sync owns the merge** (D1; REQ-1)/" "$DS_SPEC" > "$DS_NONE"
expect_eq "DSENTENCE-6 precondition: the planted D1 carries nothing between its title and its group" "1" \
  "$(/usr/bin/grep -c '^- \*\*D1 — The sync owns the merge\*\* (D1; REQ-1)$' "$DS_NONE" | tr -d ' ')"
whole_card step2 "$DS_NONE"
expect_eq "DSENTENCE-6a a decision with no sentence is refused: exit 1, no card on stdout" "1|" "$WC_RC|$WC_OUT"
expect_contains "DSENTENCE-6b …naming the decision and what it lacks" \
  "REFUSED — decision D1: no sentence after its title" "$WC_ERR"
expect_eq "DSENTENCE-6c …and naming only that one" "1|0" \
  "$(printf '%s\n' "$WC_ERR" | /usr/bin/grep -c 'D1')|$(printf '%s\n' "$WC_ERR" | /usr/bin/grep -c 'D2')"
whole_card step2 "$DS_NONE" explain D2
expect_eq "DSENTENCE-6d …and the sub-view is refused with it" "1|" "$WC_RC|$WC_OUT"
DS_TICK="${CARD_SANDBOX}/wave-22-flock.spec.md"
sed -e 's/^  lost in the merge\. DS-DETAIL-TWO/  lost in `merge_lists`. DS-DETAIL-TWO/' "$DS_SPEC" > "$DS_TICK"
expect_eq "DSENTENCE-7 precondition: the planted file carries the backtick in D2's first sentence" "1" \
  "$(/usr/bin/grep -c '`merge_lists`\. DS-DETAIL-TWO' "$DS_TICK" | tr -d ' ')"
whole_card step2 "$DS_TICK"
expect_eq "DSENTENCE-7a a sentence carrying a backtick is refused: exit 1, no card on stdout" "1|" "$WC_RC|$WC_OUT"
expect_contains "DSENTENCE-7b …naming the decision and the sentence whole" \
  'REFUSED — decision D2: the sentence carries a backtick: Two people who edit the same list while apart both keep their edits when their phones meet again, and each of them is told which edits came from the other phone, so nothing they typed is ever silently lost in `merge_lists`.' "$WC_ERR"
expect_eq "DSENTENCE-7c …and a backtick in the detail after the sentence refuses nothing (D1 carries one)" "1|0" \
  "$(/usr/bin/grep -c '`lib/sync.sh`' "$DS_TICK" | tr -d ' ')|$(printf '%s\n' "$WC_ERR" | /usr/bin/grep -c 'decision D1')"

# ============================================================
section "§APPROACH: the Eval design's Approach cell is one plain line of at most 60 columns per requirement"
# ============================================================
# fails-when: an Approach cell over 60 columns, one carrying a backtick, or a second approach on one requirement
# renders, the refusal does not name the row, a 60-column cell is refused, or the Eval design line stops printing it.
AP60="two phones meet — each keeps the other's edits, none is lost"
expect_eq "APPROACH-0 precondition: the boundary approach is 60 columns and more than 60 bytes" "60|yes" \
  "$(cols "$AP60")|$([ "$(printf '%s' "$AP60" | wc -c | tr -d ' ')" -gt 60 ] && echo yes)"
AP_SPEC="${CARD_SANDBOX}/wave-23-flock.spec.md"
sed -e "s/| REQ-1 | two phones meet and compare lists |/| REQ-1 | ${AP60} |/" "$DS_SPEC" > "$AP_SPEC"
expect_eq "APPROACH-0b precondition: both REQ-1 rows carry the 60-column approach" "2" \
  "$(/usr/bin/grep -c "| REQ-1 | ${AP60} |" "$AP_SPEC" | tr -d ' ')"
whole_card step2 "$AP_SPEC"; AP="$WC_OUT"
expect_eq "APPROACH-1 a 60-column approach, the same on every row of its requirement, draws, silently" "0|" "$WC_RC|$WC_ERR"
AP_EVAL="$(printf '%s\n' "$AP" | sed -n '/^  Eval design/,/^$/p')"
printf 'REQ-1\t%s\t0\t1\t1\t0\t0\nREQ-2\tthe view draws one list\t0\t1\t0\t0\t0\ntotal\t\t0\t2\t1\t0\t0\n' "$AP60" \
  | card eval-design > "${CARD_SANDBOX}/ap-tsv.txt"
printf '%s\n' "$AP_EVAL" | sed -e '/^$/d' > "${CARD_SANDBOX}/ap-whole.txt"
expect_eq "APPROACH-1b …and the Eval design block prints the approach as the row kind always has (precondition: REQ-1 row)" "yes|same" \
  "$(printf '%s\n' "$AP_EVAL" | /usr/bin/grep -q '^    REQ-1 ' && echo yes)|$(cmp -s "${CARD_SANDBOX}/ap-tsv.txt" "${CARD_SANDBOX}/ap-whole.txt" && echo same)"
AP_LONG="${CARD_SANDBOX}/wave-24-flock.spec.md"
sed -e "s/| REQ-1 | ${AP60} |/| REQ-1 | ${AP60}. |/" "$AP_SPEC" > "$AP_LONG"
whole_card step2 "$AP_LONG"
expect_eq "APPROACH-2 an approach of 61 columns is refused: exit 64, no card on stdout" "64|" "$WC_RC|$WC_OUT"
expect_contains "APPROACH-2b …naming the row, the width and the cap" \
  "Eval design row REQ-1 AC-1.1: the Approach cell is 61 columns, the cap is 60" "$WC_ERR"
AP_TICK="${CARD_SANDBOX}/wave-25-flock.spec.md"
sed -e 's/| REQ-2 | the view draws one list |/| REQ-2 | the `view` draws one list |/' "$AP_SPEC" > "$AP_TICK"
expect_eq "APPROACH-3 precondition: the planted REQ-2 approach carries a backtick" "1" \
  "$(/usr/bin/grep -c '| REQ-2 | the `view` draws one list |' "$AP_TICK" | tr -d ' ')"
whole_card step2 "$AP_TICK"
expect_eq "APPROACH-3a an approach carrying a backtick is refused: exit 64, no card on stdout" "64|" "$WC_RC|$WC_OUT"
expect_contains "APPROACH-3b …naming the row and the cell whole" \
  'Eval design row REQ-2 AC-2.1: the Approach cell carries a backtick: the `view` draws one list' "$WC_ERR"
AP_TWO="${CARD_SANDBOX}/wave-26-flock.spec.md"
sed -e "s/| REQ-1 | ${AP60} | AC-1.2/| REQ-1 | a merge fixture | AC-1.2/" "$AP_SPEC" > "$AP_TWO"
expect_eq "APPROACH-4 precondition: REQ-1's second row carries a second approach" "1|1" \
  "$(/usr/bin/grep -c '| REQ-1 | a merge fixture | AC-1.2' "$AP_TWO" | tr -d ' ')|$(/usr/bin/grep -c "| REQ-1 | ${AP60} | AC-1.1" "$AP_TWO" | tr -d ' ')"
whole_card step2 "$AP_TWO"
expect_eq "APPROACH-4a two approaches on one requirement are refused: exit 64, no card on stdout" "64|" "$WC_RC|$WC_OUT"
expect_contains "APPROACH-4b …naming the row and both approaches" \
  "Eval design row REQ-1 AC-1.2: a second approach for REQ-1: a merge fixture (the first: ${AP60})" "$WC_ERR"
whole_card step2 "$AP_TWO" evals REQ-1
expect_eq "APPROACH-4c …and the sub-views are refused with it" "64|" "$WC_RC|$WC_OUT"

# ============================================================
section "§TSENTENCE: a Tasks cell opens on its title and then its sentence, and the Step-3 card prints the sentence under the row"
# ============================================================
# fails-when: a cell with nothing after its title renders, one whose second sentence carries a backtick renders, the
# refusal does not name the row, the sentence is missing from under its row, cut, or folded inside the title column,
# the row's own line changes, the detail or the tag after the sentence reaches the card, `show task` loses any of the
# cell, or the cell check the plan verbs call says other words than the card.
TS_SHORT="The ledger is read once, so a later row cannot change what the first one saw."
TS_LONG="Each row of the ledger is joined to the row it names, in table order, so the reader of the plan sees one line for every pair and never the same pair twice."
TS_PLAN="${CARD_SANDBOX}/wave-30-flock.plan.md"
cat > "$TS_PLAN" <<FIXEOF
---
sdlc-step: 3
walk: required
rigor: single
parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=user
working-branch: wave/30-flock
integration-branch: main
base-sha: abc1234
---

# flock wave 30 · plan

## Goal

Land the flock app's three tasks so the Step-3 card has sentences to read.

## SDLC State

integration-branch: main
current: 4

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | Parse the ledger. ${TS_SHORT} TS-DETAIL-ONE the parser reads \`lib/a.sh\` only. · complexity: standard | implementor | — | 30 | REQ-1 | lib/a.sh | — | pending |
| T2 | 4 | build | Join the rows. ${TS_LONG} TS-DETAIL-TWO the join keeps table order. complexity: complex | senior-implementor | T1 | 45 | REQ-1, REQ-2 | lib/b.sh | — | pending |
| T3 | 5 | test | Prove the join. The join is proved on two rows · complexity: standard | implementor | T2 | 30 | REQ-2 | tests/b.test.sh | — | pending |

## Verification Matrix

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1.1 | T0 | pending | — | — |
FIXEOF
whole_card step3 "$TS_PLAN"; TS="$WC_OUT"
expect_eq "TSENTENCE-1 step3 draws a plan whose cells carry their sentences, silently" "0|" "$WC_RC|$WC_ERR"
TS_BLOCK="$(printf '%s\n' "$TS" | sed -n '/^  Tasks/,/^$/p')"
# The extractor is proved on the card first: the row line is found, so the line after it is read from a real block.
expect_contains "TSENTENCE-2 the row keeps its id and its title on its own line" \
  "    T1    Parse the ledger" "$(printf '%s\n' "$TS_BLOCK" | /usr/bin/grep '^    T1 ')"
expect_eq "TSENTENCE-2b …and the line under it is the task's sentence, indented past the id to the title column" \
  "          ${TS_SHORT}" "$(printf '%s\n' "$TS_BLOCK" | awk '/^    T1 / { getline; print; exit }')"
TS_T2="$(printf '%s\n' "$TS_BLOCK" | awk '/^    T2 / { on = 1; next } on && /^    T[0-9]/ { exit } on && NF { print }')"
expect_eq "TSENTENCE-3 a long sentence folds onto more than one line, every line indented past the id" "yes|0" \
  "$([ "$(printf '%s\n' "$TS_T2" | /usr/bin/grep -c .)" -gt 1 ] && echo yes)|$(printf '%s\n' "$TS_T2" | /usr/bin/grep -vc '^          [^ ]' | tr -d ' ')"
expect_eq "TSENTENCE-3b …and the folded lines are the sentence whole, nothing cut" \
  "$TS_LONG" "$(printf '%s\n' "$TS_T2" | sed -e 's/^ *//' | paste -sd' ' -)"
expect_eq "TSENTENCE-3c …folded at the card's right edge, past the title and serves columns, never inside the title column" "yes" \
  "$([ "$(cols "$(printf '%s\n' "$TS_T2" | head -1)")" -gt 80 ] && echo yes)"
expect_eq "TSENTENCE-3d a sentence ends where the cell's tag begins, at its middle dot" \
  "          The join is proved on two rows" "$(printf '%s\n' "$TS_BLOCK" | awk '/^    T3 / { getline; print; exit }')"
expect_eq "TSENTENCE-3e no detail and no tag after the sentence is on the card" "" \
  "$(printf '%s\n' "$TS" | /usr/bin/grep -e 'TS-DETAIL-' -e 'complexity:')"
expect_empty "TSENTENCE-3f …and no line of the card exceeds the width, the out-of-project artifact path aside" \
  "$(over_budget "$(printf '%s\n' "$TS" | /usr/bin/grep -v '^    plan  ')")"
# THE ROW'S OWN LINES ARE THE SIX-CELL ROWS BYTE FOR BYTE, and the seven-cell TSV rows draw the whole block.
printf 'T1\tParse the ledger\tREQ-1\tbuild\t—\timplementor\nT2\tJoin the rows\tREQ-1, REQ-2\tbuild\tT1\tsenior-implementor\nT3\tProve the join\tREQ-2\ttest\tT2\timplementor\n' \
  | card task > "${CARD_SANDBOX}/ts-tsv6.txt"
printf '%s\n' "$TS_BLOCK" | sed -e '/^$/d' | /usr/bin/grep -v '^          ' > "${CARD_SANDBOX}/ts-rows.txt"
expect_eq "TSENTENCE-4 with its sentence lines out, the block is the six-cell rows byte for byte (precondition: header and three rows)" "4|same" \
  "$(/usr/bin/grep -c . "${CARD_SANDBOX}/ts-rows.txt" | tr -d ' ')|$(cmp -s "${CARD_SANDBOX}/ts-tsv6.txt" "${CARD_SANDBOX}/ts-rows.txt" && echo same)"
printf 'T1\tParse the ledger\tREQ-1\tbuild\t—\timplementor\t%s\nT2\tJoin the rows\tREQ-1, REQ-2\tbuild\tT1\tsenior-implementor\t%s\nT3\tProve the join\tREQ-2\ttest\tT2\timplementor\t%s\n' \
  "$TS_SHORT" "$TS_LONG" "The join is proved on two rows" | card task > "${CARD_SANDBOX}/ts-tsv7.txt"
printf '%s\n' "$TS_BLOCK" | sed -e '/^$/d' > "${CARD_SANDBOX}/ts-whole.txt"
expect_true "TSENTENCE-4b the whole card's block is byte-identical to the same rows fed as TSV with their sentences" \
  cmp -s "${CARD_SANDBOX}/ts-tsv7.txt" "${CARD_SANDBOX}/ts-whole.txt"
whole_card step3 "$TS_PLAN" task 1; TS_V="$WC_OUT"
expect_eq "TSENTENCE-5 show task 1 prints the whole cell: title, sentence, detail and tag (precondition: exit 0)" \
  "0|Parse the ledger. ${TS_SHORT} TS-DETAIL-ONE the parser reads lib/a.sh only. · complexity: standard" \
  "$WC_RC|$(printf '%s\n' "$TS_V" | sed -n '2,$p' | sed -e 's/^ *//' | paste -sd' ' -)"

# The planted cases: the first cell cut to its title, then the second cell's sentence given a backticked token.
TS_NONE="${CARD_SANDBOX}/wave-31-flock.plan.md"
sed -e 's/^| T1 | 4 | build | Parse the ledger\. .* | implementor | — |/| T1 | 4 | build | Parse the ledger. | implementor | — |/' "$TS_PLAN" > "$TS_NONE"
expect_eq "TSENTENCE-6 precondition: the planted T1 cell is its title alone" "1" \
  "$(/usr/bin/grep -c '^| T1 | 4 | build | Parse the ledger\. | implementor' "$TS_NONE" | tr -d ' ')"
whole_card step3 "$TS_NONE"
expect_eq "TSENTENCE-6a a task with no sentence is refused: exit 1, no card on stdout" "1|" "$WC_RC|$WC_OUT"
expect_eq "TSENTENCE-6b …naming the row and what it lacks, and only that row" \
  "REFUSED — task T1: no sentence after its title" "$WC_ERR"
TS_NONE_ERR="$WC_ERR"
whole_card step3 "$TS_NONE" task 2
expect_eq "TSENTENCE-6c …and the sub-view is refused with it" "1|" "$WC_RC|$WC_OUT"
TS_TICK="${CARD_SANDBOX}/wave-32-flock.plan.md"
sed -e 's/joined to the row it names, in table order/joined to the row `join_rows` names, in table order/' "$TS_PLAN" > "$TS_TICK"
TS_TICKED="${TS_LONG/the row it names/the row \`join_rows\` names}"
expect_eq "TSENTENCE-7 precondition: the planted file carries the backtick in T2's sentence" "1" \
  "$(/usr/bin/grep -c 'the row `join_rows` names' "$TS_TICK" | tr -d ' ')"
whole_card step3 "$TS_TICK"
expect_eq "TSENTENCE-7a a sentence carrying a backtick is refused: exit 1, no card on stdout" "1|" "$WC_RC|$WC_OUT"
expect_eq "TSENTENCE-7b …naming the row and the sentence whole, and no other row: a backtick in T1's detail refuses nothing" \
  "REFUSED — task T2: the sentence carries a backtick: ${TS_TICKED}" "$WC_ERR"
TS_TICK_ERR="$WC_ERR"

# THE CELL CHECK THE PLAN VERBS CALL is the card's own: the same cell gets the same line, and a good cell gets none.
TS_CELL_RC=0; TS_CELL_OUT="$(bash "$CARD_SH" task-cell T1 'Parse the ledger.' 2>"${CARD_SANDBOX}/.tc-err")" || TS_CELL_RC=$?
expect_eq "TSENTENCE-8 task-cell refuses a cell with no sentence in the card's words: exit 1, nothing on stdout" \
  "1||${TS_NONE_ERR}" "$TS_CELL_RC|$TS_CELL_OUT|$(cat "${CARD_SANDBOX}/.tc-err")"
TS_CELL_RC=0; bash "$CARD_SH" task-cell T2 "Join the rows. ${TS_TICKED} TS-DETAIL-TWO the join keeps table order. complexity: complex" \
  >/dev/null 2>"${CARD_SANDBOX}/.tc-err" || TS_CELL_RC=$?
expect_eq "TSENTENCE-8b …and a backticked sentence, in the card's words" "1|${TS_TICK_ERR}" "$TS_CELL_RC|$(cat "${CARD_SANDBOX}/.tc-err")"
TS_CELL_RC=0; TS_CELL_OUT="$(bash "$CARD_SH" task-cell T1 "Parse the ledger. ${TS_SHORT} TS-DETAIL-ONE the parser reads \`lib/a.sh\` only." 2>&1)" || TS_CELL_RC=$?
expect_eq "TSENTENCE-8c …and passes a cell with a plain sentence silently, a backtick in its detail too" "0|" "$TS_CELL_RC|$TS_CELL_OUT"
TS_CELL_RC=0; bash "$CARD_SH" task-cell T4 'Ship it · born: review' T5 'Ship it. It ships. · born: review' T6 'Ship' \
  >/dev/null 2>"${CARD_SANDBOX}/.tc-err" || TS_CELL_RC=$?
expect_eq "TSENTENCE-8d …and names every refused cell of several, a born tag being no sentence" \
  "1|REFUSED — task T4: no sentence after its title|REFUSED — task T6: no sentence after its title" \
  "$TS_CELL_RC|$(paste -sd'|' - < "${CARD_SANDBOX}/.tc-err")"

# ============================================================
section "§SETTLED: a card render opens no ask for an approval the plan already records"
# ============================================================
# A card leaves the person a decision, so its render opens the step's approval on the run's register. That is only true
# while the approval is still owed: a step below the plan's current:, Step 3 once approved-by: is written, and a
# dispatched writer's own check (the tree's git directory holds bionic-agent) put "Blocked on you" on the sitrep an hour
# after the person had answered. fails-when: any of those renders opens an ask, or the unchanged case (a plan at
# current: 3 with no approved-by:, rendered by the orchestrator) opens none.
. "$(dirname "$0")/lib/bound-marker.sh"
ST_SID="card-settled-session-s1s1s1s1"
ST_STEM="wave-99-fixture"
st_plan_text() {  # <current> <approved 0|1> -> the plan, on stdout
  sed -e "s/^current: 4\$/current: $1/" -e 's/^# flock wave 30/# fixture wave 99/' "$TS_PLAN" \
    | { if [ "$2" = 1 ]; then awk '{ print } /^current: / { print "approved-by: Dana Fixture 2026-10-11T00:00:00Z \"approved\"" }'; else cat; fi; }
}
st_root() {  # <label> <current> <approved 0|1> -> a committed git project bound to its plan, requirements beside it
  local r="${CARD_SANDBOX}/st-$1"
  mkdir -p "$r/.bionic/tmp" "$r/.bionic/docs/plans/epic-99-fixture" "$r/.bionic/docs/specs/epic-99-fixture"
  ( cd "$r" && git init -q . && git config user.name "Dana Fixture" && git config user.email dana@example.invalid ) >/dev/null 2>&1
  st_plan_text "$2" "$3" > "$r/.bionic/docs/plans/epic-99-fixture/$ST_STEM.plan.md"
  cp "$REQ_FIX" "$r/.bionic/docs/specs/epic-99-fixture/$ST_STEM.requirements.md"
  printf '%s' "$r"
}
st_bind() { bound_marker "$1" "$ST_SID" "$1/.bionic/docs/plans/epic-99-fixture/$ST_STEM.plan.md"; }
st_commit() { ( cd "$1" && git add -A -f . && git commit -qm fixture ) >/dev/null 2>&1; }
st_plan() { printf '%s/.bionic/docs/plans/epic-99-fixture/%s.plan.md' "$1" "$ST_STEM"; }
st_req()  { printf '%s/.bionic/docs/specs/epic-99-fixture/%s.requirements.md' "$1" "$ST_STEM"; }
# st_render <cwd> <verb> <artifact> -> ST_RC; the renderer runs as the session, from <cwd>
ST_RC=0
st_render() { ST_RC=0; ( cd "$1" && CLAUDE_CODE_SESSION_ID="$ST_SID" bash "$CARD_SH" "$2" "$3" >"${CARD_SANDBOX}/.st-out" 2>&1 0<&- ) || ST_RC=$?; }
# st_open <root> -> the keys of the asks the run's register holds open, one line
st_open() {
  awk -F'|' '{ k = ""; s = ""; for (i = 1; i <= NF; i++) { if ($i ~ /^key=/) k = substr($i, 5); if ($i ~ /^state=/) s = substr($i, 7) } if (s == "open") print k }' \
    "$1/.bionic/docs/record/$ST_STEM/asks.state" 2>/dev/null | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
}

ST_A="$(st_root a 3 0)"; st_bind "$ST_A"; st_commit "$ST_A"
st_render "$ST_A" step3 "$(st_plan "$ST_A")"
expect_eq "SETTLED-1 the unchanged case: a plan at current: 3 with no approved-by:, rendered by its orchestrator, opens approve:step3 (the extractor reads an open ask)" \
  "0|approve:step3" "$ST_RC|$(st_open "$ST_A")"

ST_B="$(st_root b 4 1)"; st_bind "$ST_B"; st_commit "$ST_B"
st_render "$ST_B" step3 "$(st_plan "$ST_B")"
expect_eq "SETTLED-2 a plan at current: 4 carrying approved-by: renders step3 (exit 0) and opens no approve:step3" "0|" "$ST_RC|$(st_open "$ST_B")"
expect_contains "SETTLED-2b …the card still printed (a settled render changes nothing it prints)" "Step 3" "$(cat "${CARD_SANDBOX}/.st-out")"

ST_C="$(st_root c 3 1)"; st_bind "$ST_C"; st_commit "$ST_C"
st_render "$ST_C" step3 "$(st_plan "$ST_C")"
expect_eq "SETTLED-3 Step 3 at current: 3 once approved-by: is written opens none either" "0|" "$ST_RC|$(st_open "$ST_C")"

ST_D="$(st_root d 3 0)"; st_bind "$ST_D"; st_commit "$ST_D"
st_render "$ST_D" step1 "$(st_req "$ST_D")"
expect_eq "SETTLED-4 a plan at current: 3 and its requirements: step1 opens no approve:step1 (a step below current:)" "0|" "$ST_RC|$(st_open "$ST_D")"
ST_E="$(st_root e 1 0)"; st_bind "$ST_E"; st_commit "$ST_E"
st_render "$ST_E" step1 "$(st_req "$ST_E")"
expect_eq "SETTLED-4b …while the same requirements at current: 1 open it (the differential control)" "0|approve:step1" "$ST_RC|$(st_open "$ST_E")"

# A DISPATCHED WRITER'S RENDER. spawn-worktree.sh writes the name to the linked tree's own git directory.
ST_F="$(st_root f 3 0)"; st_bind "$ST_F"; st_commit "$ST_F"
git -C "$ST_F" worktree add -q -b wt/st-writer "${CARD_SANDBOX}/st-f-writer" >/dev/null 2>&1
git -C "$ST_F" worktree add -q -b wt/st-other "${CARD_SANDBOX}/st-f-other" >/dev/null 2>&1
ST_FGD="$(git -C "${CARD_SANDBOX}/st-f-writer" rev-parse --absolute-git-dir 2>/dev/null)"
printf 'w99-T1\n' > "$ST_FGD/bionic-agent"
expect_eq "SETTLED-5 precondition: the writer's tree holds its marker and the other linked tree does not" \
  "yes|no" "$([ -f "$ST_FGD/bionic-agent" ] && echo yes || echo no)|$([ -f "$(git -C "${CARD_SANDBOX}/st-f-other" rev-parse --absolute-git-dir)/bionic-agent" ] && echo yes || echo no)"
st_render "${CARD_SANDBOX}/st-f-other" step3 "$(st_plan "$ST_F")"
expect_eq "SETTLED-5b a linked tree with no marker renders the orchestrator's plan and opens approve:step3 (the differential control)" \
  "0|approve:step3" "$ST_RC|$(st_open "$ST_F")"
rm -f "$ST_F/.bionic/docs/record/$ST_STEM/asks.state"
st_render "${CARD_SANDBOX}/st-f-writer" step3 "$(st_plan "$ST_F")"
expect_eq "SETTLED-5c the same render from the writer's tree (bionic-agent in its git directory) opens nothing" "0|" "$ST_RC|$(st_open "$ST_F")"
ST_RC=0; ( cd "$ST_F" && CLAUDE_CODE_SESSION_ID="$ST_SID" bash "$CARD_SH" step3 "$(st_plan "$ST_F")" >/dev/null 2>&1 0<&- ) || ST_RC=$?
expect_eq "SETTLED-5d …and the orchestrator's own render of the same plan opens it after all" "0|approve:step3" "$ST_RC|$(st_open "$ST_F")"

# ============================================================
section "§UNPROVED: the release card prints the full pass's state at this head, green only where the whole suite ran green here"
# ============================================================
# fails-when: the card prints green, or covered, over a whole run behind the head whose reds later landings greened;
# the landings since the run go uncounted; or a whole run green at the head reads anything but green at it.
# FIXTURE FIDELITY: the run is tests/proof-at-head.test.sh's (`pah_world`, read out of that suite by name with the
# close-out fixture's builders it stands on, out of tests/close-out.prelude.sh), so the card is drawn over the plan
# and record the other surfaces print from; the card is the real `release-approval --preview`.
# ANTI-VACUITY: UP-1 reads the red world and UP-2 the green one through the same extractor.
up_import() {  # <name> <file> -> the function, defined here, read out of <file>
  local body
  body="$(awk -v n="$1" 'index($0, n "() {") == 1 { p = 1 } p { print } p && /^}/ { exit }' "$2")"
  [ -n "$body" ] || { echo "up_import: no $1 in $2" >&2; return 1; }
  eval "$body"
}
UP_MISSING=""
for _f in in_fixture fixture_git fixture_plan_text fixture_epic_text plant_facts mk_fixture advance_to; do
  up_import "$_f" "$(dirname "$0")/close-out.prelude.sh" || UP_MISSING="$UP_MISSING $_f"
done
for _f in pah_world pah_poke pah_card_state; do up_import "$_f" "$(dirname "$0")/proof-at-head.test.sh" || UP_MISSING="$UP_MISSING $_f"; done
expect_eq "UP-0 the builders were all read out of their suites" "" "$UP_MISSING"
SANDBOX="$CARD_SANDBOX/up"; mkdir -p "$SANDBOX"; SB_HOME="$SANDBOX/home"; mkdir -p "$SB_HOME/.claude"
REPO_ROOT="$REPO"; UNITS_LIB="$REPO/payload/scripts/lib/units.sh"; PAH_LIB="$REPO/payload/scripts/lib"
PAH_POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"; PLAN_REL=".bionic/docs/plans/epic-fx/wave-01-fixture.plan.md"
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
up_line() { printf '%s\n' "$1" | /usr/bin/grep -F "whole suite: " | head -1; }  # <card> -> its whole-suite line
pah_world up-red "notify.test.sh,shell-lint.test.sh" 2
bound_marker "$PAH_P" card-up-session "$PAH_PLAN"
pah_poke "$PAH_P" card-up-session release-approval --preview "$PAH_PLAN"
expect_eq "UP-1 a whole run red at F, two landings past it greening its reds: the card prints red at F, the two counted, marked not green" \
  "0|✖️ whole suite: red at ${PAH_F:0:8}, 2 landings before this head" "$PAH_RC|$(up_line "$PAH_OUT")"
expect_absent "UP-1b …and never covered or green" "green" "$(pah_card_state "$PAH_OUT")"
pah_world up-green "" 0
bound_marker "$PAH_P" card-up-session "$PAH_PLAN"
pah_poke "$PAH_P" card-up-session release-approval --preview "$PAH_PLAN"
expect_eq "UP-2 a whole run green at the working head: the card prints green at it, marked green" \
  "0|✅ whole suite: green at ${PAH_H:0:8}" "$PAH_RC|$(up_line "$PAH_OUT")"

finish
