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
# REQ_A is the ONE exception: T23 (epic-23 wave-15, Chris's three reads
# 2026-09-16/17) collapsed the row to ONE line whose folding cell is a single
# stream — title, the seam " · provenance ", then the provenance text, fed as
# one already-joined TSV cell — with `ACs n` trailing on that same line (18
# fixed literal columns before the stream — id field + separators + "  ACs "
# — plus a four-column reserve, against BIONIC_LINE_WIDTH=100, which
# tests/lib/resolve-roots.sh never overrides). REQ_A states that CURRENT
# shape rather than the 89f6944 baseline the other four constants still do.
OLD_FMT_REQ_A='    %-7s %-78s  ACs %s'
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

# --- requirement (ONE physical line's worth of text-column stream, no header) ---
# T23 rule 5 (one stream): the title and the provenance are ONE folding cell
# — title, the seam " · provenance ", then the provenance text — fed to
# card.sh as ONE already-joined TSV cell (the seam is content, not a
# card-runtime label any more), with the trailing ACs count on the row's own
# first line (rule 3). Short placeholders here so the merged stream fits on
# one line with no fold, matching the ORIGINAL single-line intent of this
# section; Sections 3/4/9 pin the fold and the multi-line shapes.
REQ_ID="REQ-<id>"
REQ_TITLE="<title>"
REQ_PROV_TEXT="<provenance>"
REQ_ACS="<n>"
REQ_STREAM="${REQ_TITLE} · provenance ${REQ_PROV_TEXT}"
REQ_WANT="$(printf '%s\n' \
  "  Requirements" \
  "$(fmt_render "$OLD_FMT_REQ_A" "$REQ_ID" "$REQ_STREAM" "$REQ_ACS")")"
REQ_GOT="$(printf '%s\t%s\t%s\n' "$REQ_ID" "$REQ_STREAM" "$REQ_ACS" | card requirement)"
expect_eq "6: the requirement kind renders the card's own one-line stream, ACs on it" "$REQ_WANT" "$REQ_GOT"

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

REQ_LONG="$(printf 'REQ-9\t%s · provenance %s\t4\n' "$LONG" "$LONG" | card requirement)"
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

# T23 rule 5 merges the title and provenance into ONE stream, so the
# AC-9.1/9.2 concern for requirement now lives in that stream's own fold
# budget: a glyph miscounted there would wrap the whole stream at the wrong
# column, so the two twins — same word count, glyphs vs their ASCII
# stand-ins, placed as the provenance half of the stream — must measure the
# same rendered width.
REQ9_G="$(printf 'REQ-9\treq text · provenance %s\t3\n' "$GLYPH_FOLD" | card requirement | sed -n '2p')"
REQ9_P="$(printf 'REQ-9\treq text · provenance %s\t3\n' "$PLAIN_FOLD" | card requirement | sed -n '2p')"
expect_eq "33: requirement — § — “ ” … in the stream measure the same width as their ASCII twin" \
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
printf 'REQ-1\tthe first requirement in one line · provenance user 2026-09-16 "do the thing"\t2\nREQ-2\tthe second requirement in one line · provenance seed row 2; research row 2\t1\n' \
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
REAL_REQ="${CARD_ROOT_FOR_TEST}/.bionic/docs/specs/epic-23-bionic-tech-debt/wave-15-fixit-182.requirements.md"
REAL_SPEC="${CARD_ROOT_FOR_TEST}/.bionic/docs/specs/epic-23-bionic-tech-debt/wave-15-fixit-182.spec.md"
REAL_PLAN="${CARD_ROOT_FOR_TEST}/.bionic/docs/plans/epic-23-bionic-tech-debt/wave-15-fixit-182.plan.md"
whole_card step1 "$REAL_REQ"; S1_REAL="$WC_OUT"
whole_card step2 "$REAL_SPEC"; S2_REAL="$WC_OUT"
whole_card step3 "$REAL_PLAN"; S3_REAL="$WC_OUT"

expect_empty "67: no line of the in-tree Step-1 fixture card exceeds the budget, Artifacts included" \
  "$(over_budget "$S1_IT")"
expect_empty "67a: …nor of the in-tree Step-2 fixture card" "$(over_budget "$S2_IT")"
expect_empty "67b: …nor of the in-tree Step-3 fixture card" "$(over_budget "$S3_IT")"
expect_empty "67c: nor of the Step-1 card over this wave's own requirements" \
  "$(over_budget "$S1_REAL")"
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
check_artifact_resolves "68e: …the Step-1 card over this wave's own requirements" "$S1_REAL"
check_artifact_resolves "68f: …the Step-2 card over this wave's own spec" "$S2_REAL"
check_artifact_resolves "68g: …the Step-3 card over this wave's own plan" "$S3_REAL"

card_intree_cleanup


section "Section 8: T16 — no emitted line is wider than the budget, on a real card's batch"

# WHY THESE ROWS AND NOT A SYNTHETIC ONE. A-T11.5 found the defect by rendering
# this wave's OWN Step-2 and Step-3 cards from their artifacts: the ownership
# block emitted a 297-column line and the task block a 115-column one, against
# BIONIC_LINE_WIDTH=100. Section 4's repo-scale rows do not catch it, because they
# are ONE row each — the overflow needs a BATCH, so that AC-9.5's per-batch
# widening pushes the trailing column right, AND a trailing cell with no declared
# width to run off the end once it is there. So the fixture is the batch itself,
# copied out of the artifacts the live cards were rendered from
# (record/wave-15-fixit-182/T11-step{2,3}-card-live.txt, parent ab78949).
#
# THE INVARIANT IS THE HARDER RULE (AC-9.4; A-orch-20 (2)). Per-batch widening may
# not buy its alignment with a line the terminal wraps, because a wrapped line is
# one row turned into two and the table stops being a table — lib/width.sh's
# founding note. A structured column shrinks and folds INSIDE itself instead, and
# the trailing columns still start on ONE column within the card: AC-9.5 kept.

# COLUMN ARITHMETIC IN COLUMNS, NEVER WITH `cut -c`. The rows below carry § and —,
# and a byte-indexed cut reads the wrong column the moment one does (A-T10.1, the
# ruling Section 6 takes its differentials under). These read through width.sh's
# own character walk, which is the one card.sh pads with.
col_of() {  # <line> <needle> -> the 1-indexed column the FIRST occurrence starts at, or 0
  local line="$1" needle="$2" head
  case "$line" in
    *"$needle"*) head="${line%%"$needle"*}"; printf '%s' "$(( $(cols "$head") + 1 ))" ;;
    *) printf '0' ;;
  esac
}
from_col() {  # <line> <1-indexed column> -> the rest of the line from that column on
  # A budget of 0 is not "take nothing" to _bionic_head_cols — its "one character
  # always goes" guard would eat one — so column 1 is answered here.
  [ "${2:-1}" -gt 1 ] || { printf '%s' "${1:-}"; return 0; }
  _bionic_head_cols "${1:-}" $(( ${2:-1} - 1 )); printf '%s' "$BIONIC_TAIL"
}
mid_col() {  # <line> <1-indexed column> <width> -> that many columns, from there
  local t
  t="$(from_col "${1:-}" "${2:-1}")"
  [ -n "$t" ] || { printf ''; return 0; }
  _bionic_head_cols "$t" "${3:-1}"; printf '%s' "$BIONIC_HEAD"
}
squash() { tr '\n' ' ' | tr -s ' ' | sed -e 's/^ //' -e 's/ *$//'; }
read_col() {  # <block> <column> [<width>] -> that column of every line, in order, squashed
  local blk="$1" c="$2" w="${3:-}" l
  while IFS= read -r l; do
    if [ -n "$w" ]; then mid_col "$l" "$c" "$w"; else from_col "$l" "$c"; fi
    printf '\n'
  done < <(printf '%s\n' "$blk") | squash
}
distinct_cols() {  # <block> <needle> -> how many DIFFERENT columns the needle starts at
  local blk="$1" n="$2" l
  while IFS= read -r l; do
    case "$l" in *"$n"*) col_of "$l" "$n"; printf '\n' ;; esac
  done < <(printf '%s\n' "$blk") | sort -u | grep -c . | tr -d ' '
}

# THE STEP-2 OWNERSHIP BATCH, as `card.sh step2` builds it from this wave's spec
# (§3 Ownership table). Frozen here rather than read from the artifact: the suite
# is hermetic and the artifact moves on, but the SHAPE — a 38-column concept, a
# 46-column owner and a 160-column trailing `test` cell in one batch — is the
# defect, and it has to stay put to keep walling it.
# `read -d ''` and not `"$(cat <<EOF)"`: /bin/bash 3.2 parses a here-document
# inside a command substitution by scanning for the closing paren first, so a row
# carrying `(D1, ADR-028)` or a `<stamp>` ends up executed rather than read. The
# read leaves a trailing newline behind, which is trimmed on the next line.
IFS= read -r -d '' OWN_W15 <<'OWNEOF'
Patrol verdict	lib/patrol.sh patrol_verdict	lib/stop.sh revive notice; dispatch-preflight.sh arming half	tests/patrol-revive.test.sh, tests/dispatch-preflight.test.sh; tests/cross-gate-agreement.test.sh pins both callers invoke the helper and neither types a multiplier
Observation	lib/observe.sh observe_agent	hooks/stop-check.sh (prints), hooks/stop-guard.sh (decides)	tests/stop-check.test.sh, tests/stop-guard.test.sh over one fixture world
Suite classification and backgrounding	lib/cmd-class.sh	lib/walls.sh background-suite guard ARM 1, budget arm	tests/cmd-class.test.sh, tests/background-suite-guard.test.sh
Tasks table validity	lib/units.sh units_validate / units_rows	governing-skill hook (Write/Edit), evidence gate (commit), dispatch-preflight (REQ-5)	tests/units.test.sh; tests/cross-gate-agreement.test.sh
Suite roster and self edge	tests/lib/impact.sh	dispatch suites_allowed, landing reconcile	tests/impact.test.sh
Glyph column width	lib/width.sh	card.sh rows and whole cards; lib/fold.sh refusals	tests/width.test.sh, tests/card.test.sh
Card content	the step artifact (requirements / spec / plan)	card.sh step1	step2
Patrol duty text	agents-src/blocks/orchestrator-dispatch.md	rendered dispatch.md	tests/docs-pins.test.sh §18 (bytes), render check
OWNEOF
OWN_W15="${OWN_W15%$'\n'}"

# THE STEP-3 TASK BATCH, likewise, from the same wave's plan (## Tasks). Its own
# overflow has a different driver: `depends` widens to 44 columns on the floor
# row's dependency list and pushes `agent` off the end.
IFS= read -r -d '' TASK_W15 <<'TASKEOF'
T1	REQ-1 (D1, ADR-028): patrol_verdict <stamp> <transcript> <interval> in lib/patrol.sh — reference instant = later of stamp mtime and last bionic-patrol session= user record; idle gaps from record timestamps (bounded tail moved beside it); dead iff an idle gap ≥ interval + interval/10 with no tick, busy, unreadable (reason named).	build	—	senior-implementor
T2	REQ-2 (D2, ADR-028): extract the observation from hooks/stop-check.sh into payload/scripts/lib/observe.sh (observe_agent, observe_class → alive/idle/delivered; cadence from the roster row's contract, default per the verb's existing classification); stop-check.sh becomes a thin verb printing the same machine line; stop-guard.sh sources it, looks in-process, refuses only alive+undelivered with the four facts printed, allows idle/delivered/landed with the look on stderr; delete the record-lookup, D-1/D-2/D-3/D-6 arms, the consume lock and the duplicated helpers; delete execution-recorder.sh's observation-record arm; verify session-poker.sh and lib/patrol.sh mentions of stop-check.state are sweep references (spec assumption 4 — if a reader, keep the file and amend AC-2.5 with attribution in assumptions.md); name/id and fail-direction fixtures and §12 stop order preserved.	build	—	senior-implementor
T3	REQ-3 (D5): in agents-src/blocks/orchestrator-dispatch.md the task-list duty line becomes "TaskList, then statuses reconciled with verified reality" (the reorder instruction removed); render; dispatch.md shrinks below 34,993 B; lib/stop.sh:1170 header comment drops the ListAgents duty claim; docs-pins §18 green; patrol-duties-gate §1–§3 unchanged and green.	build	T1	implementor
T4	REQ-4 AC-4.1/4.2 (D6): tests/lib/impact.sh emits the self edge for any argument matching tests/*.test.sh whether or not the file exists; every other edge still from the ls roster; a non-suite path gains no self edge.	build	—	implementor
T5	REQ-5 (D7): dispatch-preflight.sh gains units.sh in BIONIC_LIB_WANT and one arm — when the brief's declared or derived suites include tests/run.sh, read the bound plan's ## Tasks via units_rows; refuse naming every step-4/fold-in row at pending/active unless ## SDLC State carries regression-cause:; admit when all landed/dropped; open and silent with no bound plan or no table; no second Tasks parser.	build	T1	senior-implementor
T6	REQ-4 AC-4.3/4.4 (D6): dispatch-preflight.sh refuses a brief whose subagent_type names the auditor role with Suites: none (fix "name the suites the auditor may re-execute"); researcher/test-runner briefs with Suites: none unchanged; a writer brief naming a not-yet-existing tests/<new>.test.sh under Files: gets it on its roster row (end-to-end of T4).	build	T5, T4	implementor
T7	REQ-6 (D8): lib/cmd-class.sh — setsid joins the suite wrappers; new cmd_backgrounded <command> (trailing & outside quotes and not &&/2>&1, or a nohup/setsid wrapper); lib/walls.sh ARM 1 sets IS_BACKGROUND=yes when the tool flag is true OR cmd_backgrounded; the six shell forms refused, foreground forms and the main thread untouched; B0/B7/B11 green.	build	—	implementor
T8	REQ-7 (D9): tests/landing-gate.test.sh:1483-1488 timing row prints info: (centiseconds, cap) and never fails; the four expect_* rows at :1453-1458 untouched; a mutation check (copy with the expected status flipped goes red) recorded in the task's evidence; stop.test.sh 6r/6s/6t and cross-gate §L.4c green.	test	—	implementor
T9	REQ-8 REQUIRED (D10): units_validate names a raw pipe once (T<n>: <k> cells for <m> columns — a raw pipe inside a cell? escape it as backslash-pipe) and suppresses that row's per-column violations; canonical-sdlc-governing-skill.sh:575-590 builds CONTENT for Edit as the post-edit file (old_string→new_string, // under replace_all; old_string absent ⇒ arm skipped); header comment states both directions; evidence gate reports the same line through the same library; units §9 (escaped pipe) green.	build	—	senior-implementor
T10	REQ-9 (D11 + AC-9.5): lib/width.sh closed one-column set gains § — “ ” … (plus any other glyph the three steps files' cards use, verified); card.sh computes each structured column's width per batch as max(format width, widest cell) so trailing columns align within a card; WRAPPED shape and all existing card/width pins unchanged; unknown glyphs still conservative.	build	—	implementor
T11	REQ-10 (D12): card.sh step1 <requirements.md>, step2 <spec.md>, step3 <plan.md> — awk over frontmatter and headings builds the rows and feeds the existing per-kind renderer; Purpose from the first ## Goal paragraph; Branches from working-branch:/integration-branch:/base-sha: ("not declared" when absent); Not Doing bullets; Artifacts; approval line; whole-card row byte-identical to the TSV row; defective artifact ⇒ usage error exit 64; the three steps tmpl files replace their Rows: line with the whole-card invocation (one line each), render, docs-pins §18 green.	build	T10	senior-implementor
T16	FOLD-IN (A-T11.5, A-orch-20; REQ-9 AC-9.4 line-width invariant vs AC-9.5 per-batch widening): card.sh never emits a line wider than BIONIC_LINE_WIDTH.	build	T11	senior-implementor
T12	Step-5 floor, ONCE at the integration head: FARM_OUT_ALLOW=1 BIONIC_TEST_JOBS_CEILING=8 bash tests/run.sh in a detached worktree at the head after T1–T11 and T16 land, output to record/wave-15-fixit-182/floor-<sha>.txt; plus the AC-1.1 live read (patrol_verdict against this session's real stamp and transcript → busy) and the AC-10.1 human read (card.sh step1 over this wave's requirements file, shown to Chris) recorded in the walk artifact.	test	T1, T2, T3, T4, T5, T6, T7, T8, T9, T10, T11, T16	test-runner
T13	Step-5 independent auditor over the 45-row matrix at the floored head: falsify each row's evidence at its tier; verdict per row (CONFIRMED / REFUTED / UNVERIFIABLE) to record/wave-15-fixit-182/audit-<sha>.md; Suites: every suite named in the matrix.	verify	T12	auditor
T14	Step-6 six-axis review (correctness, readability, architecture, security, performance, duplication) at the audited head to record/wave-15-fixit-182/review-summary-<sha>.md; critic only on rows raised to audited (none at approval).	review	T13	senior-implementor
T15	Version bump 1.8.2 (plugin manifest, help/version examples, rendered manifest) judged at current: 7; ADR-028 status → Accepted with the ratification note.	build	T14	implementor
TASKEOF
TASK_W15="${TASK_W15%$'\n'}"

OWN_W15_OUT="$(printf '%s\n' "$OWN_W15" | card ownership)"
TASK_W15_OUT="$(printf '%s\n' "$TASK_W15" | card task)"

# ── AC-9.4: the invariant itself ─────────────────────────────────────────────
expect_empty "69: ownership — no line of a real Step-2 ownership batch exceeds the budget" \
  "$(over_budget "$OWN_W15_OUT")"
expect_empty "70: task — no line of a real Step-3 task batch exceeds the budget" \
  "$(over_budget "$TASK_W15_OUT")"

# ── AC-9.5 kept: the trailing columns still start on ONE column ───────────────
#
# The ownership format writes its column labels as LITERALS inside the row, so
# the row's own ` owner `, ` surfaces ` and ` test ` are where those columns
# start — one column each across the whole batch, or the widening bought nothing.
expect_eq "69a: …and every row starts its owner column on the same column" "1" \
  "$(distinct_cols "$OWN_W15_OUT" " owner ")"
expect_eq "69b: …and its surfaces column" "1" \
  "$(distinct_cols "$OWN_W15_OUT" " surfaces ")"
expect_eq "69c: …and its test column" "1" \
  "$(distinct_cols "$OWN_W15_OUT" " test ")"

# A continuation line carries FOLDED CELL TEXT and nothing else — never a repeat
# of the row's own column labels, which is what would make it read as a new row.
OWN_CONT="$(printf '%s\n' "$OWN_W15_OUT" | grep -vF ' test ' | grep -v '^  Ownership$')"
expect_absent "69d: no continuation line repeats the owner label" " owner " "$OWN_CONT"
expect_absent "69e: …nor the surfaces label" " surfaces " "$OWN_CONT"

# ── NOTHING IS LOST IN THE SHRINK ────────────────────────────────────────────
#
# Every word of the trailing `test` column comes back, in order, read off the
# rendered block BY COLUMN. A renderer that met the invariant by truncating the
# cell would pass every row above this one and fail here.
OWN_TESTCOL="$(( $(col_of "$(printf '%s\n' "$OWN_W15_OUT" | grep -F ' test ' | sed -n '1p')" " test ") + 6 ))"
# COMPARED WITH THE LAYOUT REMOVED, and that is the renderer's own rule rather
# than a slack assertion: a suite path is longer than the column the shrink left,
# and an over-long WORD is split at the column instead of being dropped (row 29,
# width.sh's bionic_wrap). So the fold puts a line break inside `…patrol-revive.test`
# / `.sh`, where no space ever was. What must hold here is that no CHARACTER was
# lost and none was reordered; where the breaks fall is rows 15 and 29's business.
nospace() { tr -d '[:space:]'; }
expect_eq "69f: the trailing test column reads back character for character, every row" \
  "$(printf '%s\n' "$OWN_W15" | awk -F'\t' '{print $4}' | nospace)" \
  "$(read_col "$(printf '%s\n' "$OWN_W15_OUT" | tail -n +2)" "$OWN_TESTCOL" | nospace)"

# The task card's own two: the structured `depends` column that had to shrink,
# and the trailing `agent` column it was shrunk for. Both are read at the column
# the HEADER labels, which pins the header to the rows it labels at the same time.
TASK_HDR="$(printf '%s\n' "$TASK_W15_OUT" | sed -n '1p')"
TASK_DEPCOL="$(col_of "$TASK_HDR" "depends")"
TASK_AGCOL="$(col_of "$TASK_HDR" "agent")"
TASK_BODY="$(printf '%s\n' "$TASK_W15_OUT" | tail -n +2)"
expect_eq "70a: the depends column reads back word for word, every row" \
  "$(printf '%s\n' "$TASK_W15" | awk -F'\t' '{print $4}' | squash)" \
  "$(read_col "$TASK_BODY" "$TASK_DEPCOL" "$(( TASK_AGCOL - TASK_DEPCOL ))")"
expect_eq "70b: …and so does the trailing agent column" \
  "$(printf '%s\n' "$TASK_W15" | awk -F'\t' '{print $5}' | squash)" \
  "$(read_col "$TASK_BODY" "$TASK_AGCOL")"

# ── A BATCH THAT FITS IS UNTOUCHED ───────────────────────────────────────────
#
# The shrink is a response to an OVERFLOW, not a new default: a batch whose widest
# row still fits the budget renders exactly what AC-9.5's widening alone rendered,
# byte for byte, with no column narrowed and no structured cell folded. This is
# Section 6's own AC-9.5 pair (rows 40/41) pinned as BYTES rather than as two
# start columns, which is what stops a shrink rule from paying for the invariant
# with every card that never had the problem.
OWN_FIT_FMT='    %-12s owner %-19s surfaces %-22s test %s'
OWN_FIT_WANT="$(printf '%s\n' \
  "  Ownership" \
  "$(fmt_render "$OWN_FIT_FMT" 'concept a' 'lib/x.sh' 'surfaces text a' 'test a' | sed -e 's/ *$//')" \
  "$(fmt_render "$OWN_FIT_FMT" 'concept b' 'tests/lib/impact.sh' 'surfaces text b' 'test b' | sed -e 's/ *$//')")"
OWN_FIT_GOT="$(printf 'concept a\tlib/x.sh\tsurfaces text a\ttest a\nconcept b\ttests/lib/impact.sh\tsurfaces text b\ttest b\n' | card ownership)"
expect_eq "71: a batch that fits renders byte for byte what per-batch widening alone rendered" \
  "$OWN_FIT_WANT" "$OWN_FIT_GOT"

section "Section 9: T23 — the requirement row's shape (Chris's three reads)"

# THE FIVE RULES, verbatim in substance from Chris's reads of the live Step-1
# card (2026-09-17): (3) the trailing `ACs n` column sits on the row's own
# FIRST line, beside the title; (2) a folded line always keeps at least one
# column of space before a trailing column — "stop" must never abut "ACs 6";
# (1) a continuation line indents to the fold cell's own start column (the
# title-text column), never deeper; (4) no line's rendered text may reach as
# far as the `ACs n` column; (5, "one stream") the title and the provenance
# are not two cells or two lines any more — they are ONE word-wrapped stream,
# title then the seam " · provenance " then the provenance text, filling the
# text column greedily, so provenance CONTINUES on the title's own line when
# there is room rather than always starting a fresh one.
#
# REQ-1 and REQ-2's OWN real title and provenance text, frozen out of this
# wave's own requirements.md (Chris's own screenshot was of exactly this row)
# rather than read from the artifact live — Section 8's own rule, for the same
# reason: the shape that was wrong has to stay put to keep walling it. The
# seam is built here exactly as `_CARD_AWK`'s `flush_req` builds it for a
# whole card (rule 5), so this is also a hand-fed twin of that construction.
REQ23_1_TITLE='The Patrol death notice judges on idle time, not wall time'
REQ23_1_PROV='seed row 1 (RULED option 3, user 2026-09-16 "Option 3"; A-orch-4); field 2026-09-15 (stamp 2459 s vs the 2400 s limit while the orchestrator was busy — two ticks could not fire; Chris "the orchestrator is simply busy"); research row 1 (stop_patrol_revive() at payload/scripts/lib/stop.sh:1927-2101; the limit is the literal INTERVAL * 2 at :2026, not PATROL_STALE_MULTIPLIER from lib/patrol.sh:67 that session-start.sh:667 and dispatch-preflight.sh:653 read; the notice at :2077-2092 never mentions CronList; every transcript record carries .timestamp; the emitter at :1477-1487 already selects the current turn'"'"'s user record and does not emit its timestamp; the scan window is tail -n 2000 at :1445-1457)'
REQ23_2_TITLE='The stop guard observes its target at the instant of the stop'
REQ23_2_PROV='seed row 2 (RULED option 1, user 2026-09-16 "Option 1"; A-orch-5); field 2026-09-15 ("no observation exists in this repo" refused a stop of an agent nobody had examined); wave-14 A-orch-72; research row 2 (stop-guard.sh:900-1092 — record lookup, D-3 own-look, D-1 freshness, D-6 progress artifact, D-2 consume, all over stop-check.state written only by execution-recorder.sh:1094; stop-check.sh is an 841-line verb registered on no channel; the human order at stop-guard.sh:819-860 allows immediately and is TTL-bounded)'
REQ23_1_STREAM="${REQ23_1_TITLE} · provenance ${REQ23_1_PROV}"
REQ23_2_STREAM="${REQ23_2_TITLE} · provenance ${REQ23_2_PROV}"

REQ23_OUT="$(printf 'REQ-1\t%s\t5\nREQ-2\t%s\t6\n' "$REQ23_1_STREAM" "$REQ23_2_STREAM" | card requirement)"
expect_empty "72: the real REQ-1/REQ-2 batch stays inside the budget on every line" \
  "$(over_budget "$REQ23_OUT")"

REQ23_L1="$(printf '%s\n' "$REQ23_OUT" | grep 'REQ-1   ')"
REQ23_L2="$(printf '%s\n' "$REQ23_OUT" | grep 'REQ-2   ')"

# Rule 3: ACs is on the row's own first line, beside the title.
expect_contains "73: rule 3 — REQ-1's ACs count is on the same line as its title" \
  "ACs 5" "$REQ23_L1"
expect_contains "73a: …and REQ-2's ACs count is on the same line as its title" \
  "ACs 6" "$REQ23_L2"

# Rule 2: at least one column of space always separates a folded cell from a
# trailing column — REQ-2's title ends in the exact word ("stop") Chris found
# abutting "ACs 6".
gap_before() {  # <line> <landmark> -> columns of whitespace right before its first occurrence
  local line="$1" landmark="$2" pre n=0
  case "$line" in
    *"$landmark"*) pre="${line%%"$landmark"*}" ;;
    *) printf '0'; return 0 ;;
  esac
  while [ "${pre: -1}" = " " ]; do pre="${pre%?}"; n=$(( n + 1 )); done
  printf '%s' "$n"
}
case "$REQ23_L2" in
  *'stopACs'*) no "74: rule 2 — REQ-2's title does not abut ACs 6" "$REQ23_L2" ;;
  *) ok "74: rule 2 — REQ-2's title does not abut ACs 6" ;;
esac
expect_true "74a: …and at least one column of space separates them" \
  test "$(gap_before "$REQ23_L2" "ACs 6")" -ge 1

# Rule 1: a continuation line of the stream indents to the fold cell's own
# start column (13: four leading spaces, the seven-column id field, one
# separator) — the general WRAPPED rule every other kind already gets, now
# true here too because title and provenance are one fold field, not two.
REQ23_CONT1="$(printf '%s\n' "$REQ23_OUT" | sed -n '/REQ-1   /,/REQ-2   /p' | sed -n '2p')"
REQ23_INDENT="$(printf '%s' "$REQ23_CONT1" | sed -e 's/[^ ].*$//' | awk '{print length}')"
expect_eq "75: rule 1 — a continuation line indents to the fold cell's own column" \
  "12" "$REQ23_INDENT"
expect_absent "75a: …and does not repeat the row's own id" "REQ-1" "$REQ23_CONT1"

# Rule 4: the RIGHT edge lines up too — no continuation line (every line of
# the row but its own first, which legitimately carries `ACs n` itself) may
# print under the `ACs n` column. "Honor the column structure, left-aligned …
# that's the whole point, so it's easy to read." The bound is read off REQ-1's
# own first line (where "ACs" itself starts, minus the two-space gap rule 2
# guarantees) rather than hardcoded, so a reserve changed in card.sh cannot
# silently stop this row from meaning anything.
right_edge_ok() {  # <block-of-continuation-lines> <bound col> -> true if none reaches it
  local blk="$1" bound="$2" l
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    [ "$(cols "$l")" -lt "$bound" ] || return 1
  done < <(printf '%s\n' "$blk")
  return 0
}
REQ23_1_CONTLINES="$(printf '%s\n' "$REQ23_OUT" | sed -n '/REQ-1   /,/REQ-2   /p' | sed '1d;$d')"
REQ23_ACS_COL="$(col_of "$REQ23_L1" "ACs")"
expect_true "80: rule 4 — no continuation line of REQ-1's row reaches under ACs n" \
  right_edge_ok "$REQ23_1_CONTLINES" "$REQ23_ACS_COL"

# Rule 5 (one stream): the seam " · provenance " appears exactly once in
# REQ-1's row — never duplicated by a second fold pass — and provenance picks
# up wherever the title's own wrap left off, on the SAME line when there was
# room (REQ-1's title plus the seam plus the word "seed" all fit before the
# 78-column budget: the stream's own first line carries the seam, not a
# provenance line of its own).
expect_eq "85: rule 5 — the seam appears exactly once in REQ-1's row" "1" \
  "$(printf '%s\n' "$REQ23_OUT" | sed -n '/REQ-1   /,/REQ-2   /p' | sed '$d' | grep -c ' · provenance ')"
expect_contains "85a: …and it lands on the row's own first line, beside the title" \
  ' · provenance ' "$REQ23_L1"

# ── rule 2, once per OTHER row kind with a folding cell ──────────────────────
#
# Every one of these already carries a DECLARED width on its folding cell, so
# the pad that follows it is guaranteed by the same padding pass that has
# always run — this pins that guarantee rather than assuming it, on the
# Section 4 repo-scale fixtures whose fold cell is genuinely at its widest.
expect_true "76: decision — rule 2, a repo-scale fold never abuts its trailing serves column" \
  test "$(gap_before "$(printf '%s\n' "$DEC_LONG" | grep -v '^  Decisions')" "REQ-7, REQ-9")" -ge 1
expect_true "77: ownership — rule 2, a repo-scale fold never abuts its trailing test column" \
  test "$(gap_before "$(printf '%s\n' "$OWN_LONG" | grep -v '^  Ownership')" " test ")" -ge 1
expect_true "78: eval-design — rule 2, a repo-scale fold never abuts its first count column" \
  test "$(gap_before "$(printf '%s\n' "$EVAL_LONG" | tail -n +2 | sed -n '1p')" "2")" -ge 1
expect_true "79: task — rule 2, a repo-scale fold never abuts its trailing kind column" \
  test "$(gap_before "$(printf '%s\n' "$TASK_LONG" | grep -v '^  Tasks')" "build")" -ge 1

# ── rule 4, once per OTHER row kind with a folding cell ──────────────────────
#
# No CONTINUATION line reaches as far as the column its own row's trailing
# structured column starts at — structural wherever the fold field has a
# declared width (padded or wrapped to EXACTLY that width, never more), so a
# continuation line's blank-literal-plus-chunk can never run past where the
# next field's own literal begins. Pinned on Section 4's repo-scale fixtures.
DEC_LONG_NOHDR="$(printf '%s\n' "$DEC_LONG" | grep -v '^  Decisions')"
expect_true "81: decision — rule 4, no continuation line reaches under serves" \
  right_edge_ok "$(printf '%s\n' "$DEC_LONG_NOHDR" | tail -n +2)" \
  "$(col_of "$(printf '%s\n' "$DEC_LONG_NOHDR" | sed -n 1p)" "REQ-7, REQ-9")"
OWN_LONG_NOHDR="$(printf '%s\n' "$OWN_LONG" | grep -v '^  Ownership')"
expect_true "82: ownership — rule 4, no continuation line reaches under test" \
  right_edge_ok "$(printf '%s\n' "$OWN_LONG_NOHDR" | tail -n +2)" \
  "$(col_of "$(printf '%s\n' "$OWN_LONG_NOHDR" | sed -n 1p)" " test ")"
EVAL_LONG_NOHDR="$(printf '%s\n' "$EVAL_LONG" | tail -n +2)"
expect_true "83: eval-design — rule 4, no continuation line reaches under the first count column" \
  right_edge_ok "$(printf '%s\n' "$EVAL_LONG_NOHDR" | tail -n +2)" \
  "$(col_of "$(printf '%s\n' "$EVAL_LONG_NOHDR" | sed -n 1p)" "2")"
TASK_LONG_NOHDR="$(printf '%s\n' "$TASK_LONG" | grep -v '^  Tasks')"
expect_true "84: task — rule 4, no continuation line reaches under kind" \
  right_edge_ok "$(printf '%s\n' "$TASK_LONG_NOHDR" | tail -n +2)" \
  "$(col_of "$(printf '%s\n' "$TASK_LONG_NOHDR" | sed -n 1p)" "build")"


section "Section 10: T10 — the task-scale card, the configured floor, and per-batch widths (REQ-4 D8/D9; REQ-3 AC-3.4)"

# WHAT THIS SECTION OWNS. Until this task `card.sh` knew ONE table: the wave-scale
# eleven-column `## Tasks` ledger. It read the six-column TASK-scale table with the
# same positional map, so a task-scale card printed the `rigor` cell under a heading
# saying `kind`, the `worktree` cell under `depends` — a row whose tree existed
# rendered `.worktrees/18-T2` under a column headed `depends`, which is worse than a
# blank — and the `status` cell under `agent` (research R3, card.sh:781 at d7e841c).
# The first-batch line keyed on a wave-scale `step` cell holding the literal `4`, a
# cell the task table does not have, so every task-scale card said "first batch not
# declared". The Verification line's floor was the LITERAL `tests/run.sh` in the
# format string, over a skill picture that says `floor <suite>` — a lying surface at
# every scale, at a gate whose whole job is to be true. And `step2` refused a
# task-scale plan outright, because a task-scale run writes a design PARAGRAPH in its
# plan and owes no `## Eval design` table (steps/2.md:60, "no wall at task scale at
# all").
#
# HERMETIC, and the fixtures live in their OWN roots under the sandbox, because the
# floor row is a question about `.bionic/config.yaml` under the PLAN's project root
# and the answer must not be able to come from this repo's own config.

T10_ROOT_CFG="${CARD_SANDBOX}/root-configured"
T10_ROOT_BARE="${CARD_SANDBOX}/root-bare"
mkdir -p "${T10_ROOT_CFG}/.bionic" "${T10_ROOT_BARE}/.bionic"
printf 'poker-interval: 20m\nimpact-command: bash tests/lib/impact.sh\n' \
  > "${T10_ROOT_CFG}/.bionic/config.yaml"

# ── the task-scale plan fixture ──────────────────────────────────────────────
# Six columns in the contract's own order (steps/3.md:22,
# `| id | intent | rigor | description | status | worktree |`), trees spelled the
# way the product spells them — `<NN>-T<n>`, capital T (wave-17 L1, the charter's
# standing fixture condition) — a `done` row so the pending predicate has something
# to exclude, and a design paragraph under its own heading.
T10_TASK_PLAN="${T10_ROOT_CFG}/task-run-18.plan.md"
cat > "$T10_TASK_PLAN" <<'FIXEOF'
---
sdlc-step: 3
scale: task
walk: exempt
rigor: audited
parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=probe
---

# fixture task run 18 · plan

## Goal

Land the fixture task run's three units under one plan, so the card has a
task-scale artifact to render.

## Design

The fixture's design paragraph, written in the plan itself because a task-scale run
carries no spec and owes no heading in one.

A second paragraph the card does not show.

## SDLC State

current: T1

## Tasks

| id | intent | rigor | description | status | worktree |
|---|---|---|---|---|---|
| T1 | build | audited | The first unit in one line. It has a second sentence the card does not show. | pending | .worktrees/18-T1 |
| T2 | test | peer-reviewed | The second unit in one line. | pending | .worktrees/18-T2 |
| T3 | doc | self-verified | The third unit, already landed. | done | — |

## Verification Matrix

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1.1 | T2 | pending | — | — |
| AC-1.2 | T0 | pending | — | — |
FIXEOF

# The same plan under a root with NO `impact-command:` — one fixture, two roots, so
# the floor row varies in exactly the thing it is about.
T10_TASK_PLAN_BARE="${T10_ROOT_BARE}/task-run-18.plan.md"
cp "$T10_TASK_PLAN" "$T10_TASK_PLAN_BARE"

# …and the same plan with NO `## Design` heading at all, which is the shape the
# contract actually obliges (steps/2.md:60): the design paragraph degrades to the
# plan's Goal rather than printing nothing.
T10_TASK_NODESIGN="${T10_ROOT_CFG}/task-run-18-nodesign.plan.md"
awk '/^## Design$/ { skip = 1; next } /^## SDLC State$/ { skip = 0 } skip != 1' \
  "$T10_TASK_PLAN" > "$T10_TASK_NODESIGN"

# ── AC-4.1: the six columns under their own headings ─────────────────────────
whole_card step3 "$T10_TASK_PLAN"; T10_S3="$WC_OUT"
expect_eq "154: AC-4.1 — step3 exits 0 on a task-scale plan" "0" "$WC_RC"
expect_empty "154a: …and writes nothing to stderr" "$WC_ERR"
T10_HDR="$(printf '%s\n' "$T10_S3" | grep -m1 '^  Tasks')"
T10_ROW1="$(printf '%s\n' "$T10_S3" | grep -m1 '^    T1 ')"
T10_ROW2="$(printf '%s\n' "$T10_S3" | grep -m1 '^    T2 ')"
expect_contains "155: AC-4.1 — the Tasks header names rigor, not kind" "rigor" "$T10_HDR"
expect_contains "155a: …and status" "status" "$T10_HDR"
expect_contains "155b: …and worktree" "worktree" "$T10_HDR"
expect_absent "155c: …and no longer says depends over a task table" "depends" "$T10_HDR"
expect_absent "155d: …nor agent" "agent" "$T10_HDR"
expect_absent "155e: …nor kind" "kind" "$T10_HDR"

# THE COLUMN, NOT THE PRESENCE. A cell is under the heading it belongs to only if it
# STARTS at that heading's own column — which is the whole defect: at d7e841c the
# worktree cell was present and printed under the word `depends`.
expect_eq "156: AC-4.1 — T1's worktree cell starts at the worktree heading's column" \
  "$(col_of "$T10_HDR" "worktree")" "$(col_of "$T10_ROW1" ".worktrees/18-T1")"
expect_eq "156a: …and T1's status cell at the status heading's column" \
  "$(col_of "$T10_HDR" "status")" "$(col_of "$T10_ROW1" "pending")"
expect_eq "156b: …and T1's rigor cell at the rigor heading's column" \
  "$(col_of "$T10_HDR" "rigor")" "$(col_of "$T10_ROW1" "audited")"
expect_eq "156c: …and T2's rigor cell too, so the batch width holds for both rows" \
  "$(col_of "$T10_HDR" "rigor")" "$(col_of "$T10_ROW2" "peer-reviewed")"
expect_contains "156d: …and the description column carries the unit's first sentence" \
  "The first unit in one line." "$T10_ROW1"
expect_absent "156e: …and not the rest of the description cell" \
  "second sentence the card does not show" "$T10_S3"

# ── AC-4.2: the first-batch line is read from the task table's own status cells ──
T10_PW="$(printf '%s\n' "$T10_S3" | grep -m1 'first batch')"
expect_absent "157: AC-4.2 — a task-scale card never says the first batch is undeclared" \
  "first batch not declared" "$T10_S3"
expect_contains "157a: …it names the pending rows" "first batch T1, T2" "$T10_PW"
expect_absent "157b: …and never the row that is already done" "T3" "$T10_PW"

# ── AC-4.3: the floor is the configured impact command, or an em dash ────────
T10_V="$(printf '%s\n' "$T10_S3" | grep -m1 'matrix rows')"
expect_contains "158: AC-4.3 — the floor is the root's own impact-command" \
  "floor bash tests/lib/impact.sh" "$T10_V"
expect_absent "158a: …and never the literal that was in the format string" \
  "floor tests/run.sh" "$T10_S3"
whole_card step3 "$T10_TASK_PLAN_BARE"; T10_S3_BARE="$WC_OUT"
T10_V_BARE="$(printf '%s\n' "$T10_S3_BARE" | grep -m1 'matrix rows')"
expect_contains "158b: AC-4.3 — a root with no impact-command renders an em dash" \
  "floor —" "$T10_V_BARE"
expect_absent "158c: …and still never the literal tests/run.sh" \
  "floor tests/run.sh" "$T10_S3_BARE"

# ── AC-4.4: step2 accepts a task-scale plan and renders its design paragraph ──
whole_card step2 "$T10_TASK_PLAN"; T10_S2="$WC_OUT"
expect_eq "159: AC-4.4 — step2 exits 0 on a task-scale plan" "0" "$WC_RC"
expect_absent "159a: …and never demands an Eval design table" \
  "no ## Eval design table" "$WC_ERR"
expect_contains "159b: …and carries the plan's own design paragraph" \
  "written in the plan itself because a task-scale run" "$T10_S2"
expect_absent "159c: …and only the FIRST paragraph of it" \
  "A second paragraph the card does not show" "$T10_S2"
expect_contains "159d: …and closes on the Step-2 approval question" \
  'Do you approve this design? Reply "approved" to approve it.' "$T10_S2"
whole_card step2 "$T10_TASK_NODESIGN"; T10_S2_ND="$WC_OUT"
expect_eq "160: AC-4.4 — a task-scale plan with no ## Design heading still renders" "0" "$WC_RC"
expect_contains "160a: …and degrades to the plan's Goal, the shape steps/2.md:60 obliges" \
  "Land the fixture task run's three units" "$T10_S2_ND"

# ── AC-3.4: per-batch width against the rung ─────────────────────────────────
# Rows grouped by dependency DEPTH: three rows depend on nothing, two depend on
# those, so the plan runs in two batches against a rung of 8. The numbers are the
# ready set `fill_ready_set` names at each batch, not a row count this file does
# again in its own way.
T10_WAVE_2B="${T10_ROOT_CFG}/wave-98-twobatch.plan.md"
cat > "$T10_WAVE_2B" <<'FIXEOF'
---
sdlc-step: 3
scale: wave
walk: required
rigor: audited
parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=probe
working-branch: wave/98-twobatch
integration-branch: main
base-sha: abc1234
---

# fixture wave 98 · plan

## Goal

Land five tasks in two dependency batches, so the card has something to measure a
per-batch width against.

## SDLC State

integration-branch: main
current: 4

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | REQ-1: the first task, whose cell carries an escaped \| pipe. complexity: standard | implementor | — | 30 | REQ-1 | lib/a.sh | — | pending |
| T2 | 4 | build | REQ-1: the second task. complexity: standard | implementor | — | 30 | REQ-1 | lib/b.sh | — | pending |
| T3 | 4 | build | REQ-2: the third task. complexity: standard | implementor | — | 30 | REQ-2 | lib/c.sh | — | pending |
| T4 | 4 | test | REQ-1: the fourth task. complexity: standard | implementor | T1 | 30 | REQ-1 | lib/d.sh | — | pending |
| T5 | 4 | test | REQ-2: the fifth task. complexity: standard | implementor | T1, T2, T3 | 30 | REQ-2 | lib/e.sh | — | pending |

## Verification Matrix

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1.1 | T2 | pending | — | — |
FIXEOF

whole_card step3 "$T10_WAVE_2B"; T10_2B="$WC_OUT"
expect_eq "161: AC-3.4 — step3 exits 0 on the two-batch plan" "0" "$WC_RC"
expect_contains "161a: AC-3.4 — the first batch's width is its ready set against the rung" \
  "batch 1 · 3 of 8" "$T10_2B"
expect_contains "161b: …and the second batch's own width" "batch 2 · 2 of 8" "$T10_2B"
expect_absent "161c: …and there is no third batch to name" "batch 3 ·" "$T10_2B"
expect_contains "161d: …under the Parallel width heading, beside the writer budget" \
  "8 writers" "$T10_2B"
# THE ESCAPED PIPE IN T1 IS WHAT MAKES 161b DISCRIMINATE, and it is in the fixture for
# that reason: this repo writes `\|` inside ledger cells and `lib/units.sh` folds the
# escape before it splits. A batch pass that split on every `|` reads T1 status cell one
# field left of where it is, so T1 is never satisfied — both rows of batch 2 depend on
# T1, and the card reports `batch 2 · 1 of 8`. A wrong number at the approval gate, not
# a crash: the shape this row exists to keep out.
expect_contains "161e: AC-3.4 — the escaped pipe reaches the card as an ordinary pipe" \
  "cell carries an escaped |" "$T10_2B"
# THE PIN IS NOT VACUOUS: the task-scale plan has ONE batch (its table carries no
# deps column at all), and it is counted the same way — two pending rows of three.
expect_contains "162: AC-3.4 — the task-scale plan renders its one batch's width" \
  "batch 1 · 2 of 8" "$T10_S3"
expect_absent "162a: …and names no second batch it does not have" "batch 2 ·" "$T10_S3"

# ── AC-4.5: the new cards obey the same budget every other card does ─────────
# THE ARTIFACTS PATH IS EXCLUDED, and only it: these fixtures live OUTSIDE the
# project (this suite's hermetic-fixture rule), and an out-of-project artifact path
# prints AS GIVEN, whole, unbound by the width invariant — Section 7's rows 67/68
# own that exemption and its rationale. Everything this task renders is bound.
without_artifact_path() {  # <rendered card> -> the card without its Artifacts path line
  printf '%s\n' "${1:-}" | grep -v '^    \(requirements\|spec\|plan\)  /'
}
expect_empty "163: AC-4.5 — no line of the task-scale Step-3 card exceeds the budget" \
  "$(over_budget "$(without_artifact_path "$T10_S3")")"
expect_empty "163a: …nor of the task-scale Step-2 card" \
  "$(over_budget "$(without_artifact_path "$T10_S2")")"
expect_empty "163b: …nor of the two-batch wave card" \
  "$(over_budget "$(without_artifact_path "$T10_2B")")"

# THE WAVE-SCALE CARD IS UNTOUCHED BY ALL OF IT (AC-4.5). Section 7's own fixture,
# rendered again here, still reads its eleven columns under the wave headings — a
# scale switch that fired on the wrong table would show up here rather than on a
# card at an approval gate.
whole_card step3 "$PLAN_FIX"; T10_WAVE="$WC_OUT"
T10_WHDR="$(printf '%s\n' "$T10_WAVE" | grep -m1 '^  Tasks')"
expect_contains "164: AC-4.5 — a wave-scale plan still reads its headings as kind" "kind" "$T10_WHDR"
expect_contains "164a: …and depends" "depends" "$T10_WHDR"
expect_contains "164b: …and agent" "agent" "$T10_WHDR"
expect_absent "164c: …and never the task-scale headings" "worktree" "$T10_WHDR"

# ── AC-11.1 (wave-19 REQ-11, D12): a task-scale plan carries its own requirements ──
# THE PARSER WAS NEVER THE GAP. `_card_step1` is scale-blind: it renders whatever
# `### REQ-<id> — <title>` + `provenance:` blocks sit under a `## Requirements`
# heading, at any scale. The T10 plan above carries none, because the task-scale plan
# shape in steps/3.md defined none, so its Step-1 card printed an empty block. The
# fix is the shape (steps/3.md's task-scale paragraph); these rows pin that the shape
# it names is the one the card reads, on the T10 plan with that section added. The
# heading is READ FROM THE RENDERED steps/3.md, not restated here, so a text that names
# a shape the parser does not read goes red on this row rather than at a Step-1 gate.
card_reqs_block() {  # <rendered card> -> the non-blank lines between Requirements and Not Doing
  printf '%s\n' "${1:-}" | awk '/^  Requirements$/ { f = 1; next } /^  [A-Z]/ { f = 0 } f && NF'
}
T11_STEP3="${BIONIC_SKILLS_DIR}/canonical-sdlc/steps/3.md"
T11_REQ_HEAD="$( { grep -o '`### REQ-<n> — <title>`' "$T11_STEP3" 2>/dev/null || true; } | head -1 | tr -d '`' \
  | sed -e 's/<n>/1/' -e 's/<title>/The card renders what the plan carries/')"
T11_REQ_PLAN="${T10_ROOT_CFG}/task-run-19-reqs.plan.md"
awk -v head="$T11_REQ_HEAD" '/^## SDLC State$/ {
       print "## Requirements\n"
       print head "\n"
       print "provenance: user 2026-09-22 \"renders the Requirements block\"\n"
       print "- AC-1.1\n"
     } { print }' "$T10_TASK_PLAN" > "$T11_REQ_PLAN"
whole_card step1 "$T11_REQ_PLAN"; T11_S1="$WC_OUT"
expect_eq "165: AC-11.1 — step1 exits 0 on a task-scale plan carrying a REQ line" "0" "$WC_RC"
T11_REQS="$(card_reqs_block "$T11_S1")"
expect_contains "165a: …and its Requirements block renders the requirement" \
  "REQ-1   The card renders what the plan carries" "$T11_REQS"
expect_contains "165b: …with its provenance in the same cell" "provenance user 2026-09-22" "$T11_REQS"
# THE PAIRED NEGATIVE: the same plan without the section is the RED this criterion
# names — an empty block — so 165a/165b are about the section, not about step1.
whole_card step1 "$T10_TASK_PLAN"
expect_empty "165c: …and the T10 plan, which carries no ## Requirements, renders an empty block" \
  "$(card_reqs_block "$WC_OUT")"

finish
