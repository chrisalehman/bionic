#!/bin/bash
# payload/scripts/card.sh — THE CARD ROW RENDERER, and the one owner of every
# card row width bionic prints (epic-23 wave-14-tune-181, T36; REQ-9 AC-9.1/AC-9.4;
# Chris 2026-09-15 "D4: I want the wrapped version" / "option 1 - renderer script
# and cap at 110k").
#
# [WALL: tests/card.test.sh]
#
# WHAT IT OWNS. The six row shapes the Step-1, Step-2 and Step-3 approval cards are
# made of — the requirement row, the decision row, the ownership row, the
# eval-design row and the task row — their column widths, their column headers, and
# what happens to a cell too wide for its column.
#
# WHY IT EXISTS, WHICH IS NOT "TO TIDY THE WIDTHS AWAY". Until this file the widths
# were INSTRUCTION: each card carried a printf format beside it and the model
# padded the row by hand against that format. Two things were wrong with that, and
# only one of them could be fixed by choosing better numbers.
#
#   A PRINTF FORMAT CANNOT WRAP. `%-44s` pads a short value and prints a long one
#   WHOLE — it neither folds nor truncates — so a decision one sentence too long
#   pushes `serves` and `ADR` right off their columns and the table stops being a
#   table. The readability review measured card rows at 126 and 165 columns; T31
#   re-cut every width to fit the 100-column rule and that fixed the SAMPLE rows
#   only, because the next long sentence overflows the new width exactly as it
#   overflowed the old one. The fix is a renderer that folds, not a better number.
#
#   PRINTF PADS BYTES, A TERMINAL LAYS OUT COLUMNS (A-T31.3). An em dash is three
#   bytes and one column, so `%-13s` holding one comes out two columns short and
#   every row under it steps left. That is `lib/width.sh`'s founding note, one
#   layer up: this file pads through `bionic_cols` and never through printf's own
#   `%-Ns`, which is why the formats below are PARSED here rather than handed to
#   printf.
#
# THE SHAPE, WHICH IS THE USER'S AND NOT THIS FILE'S. Three shapes of one row were
# put to Chris: OVERFLOW (what printf does), STAGGERED (the pre-T10 shape, trailing
# columns on a line of their own) and WRAPPED. He chose WRAPPED:
#
#     D2   A decision whose text runs well past the     REQ-2, REQ-3   none
#          forty-four column limit
#
# One free-text cell per row folds inside its own column; the trailing columns stay
# on the row's FIRST line; continuation lines are indented to the free cell's start
# column and carry nothing else. Every emitted line fits BIONIC_LINE_WIDTH.
#
# USAGE
#     bash card.sh <requirement|decision|ownership|eval-design|task>  < rows.tsv
#     bash card.sh <step1|step2|step3> <artifact>      (the whole card; no stdin)
#
# One row per input line, cells separated by TABS, in the card's own column order.
# A missing trailing cell renders empty rather than refusing: a card is a display,
# and half a row beats an error at an approval gate. An unknown kind, or no kind at
# all, is a usage error — one line on stderr, exit 64.
#
# THE LOCALE IS PINNED, AND THAT IS A MEASUREMENT DECISION. `lib/width.sh` reads a
# glyph outside its closed set CONSERVATIVELY (at its bytes) and pins `LC_ALL=C`
# inside its own functions to make that reading the same everywhere — the ruling
# tests/width.test.sh:7n holds the truncator to. This script pins the same locale
# for the padding it does itself, so the pad and the fold cannot disagree about the
# width of the same cell in a hook's stripped environment.
LC_ALL=C

set -u

CARD_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "${CARD_SELF_DIR}/lib/width.sh"
# shellcheck source=/dev/null
. "${CARD_SELF_DIR}/lib/root.sh"
# THE TWO LIBRARIES THE STEP-3 CARD ASKS ITS LAST TWO QUESTIONS OF (epic-23
# wave-18-fixit-185, T10; REQ-4 D9, REQ-3 AC-3.4). `roots.sh` owns the ONE reading of
# `.bionic/config.yaml`, so the floor line names what the dispatch wall and the landing
# gate name; `fill.sh` owns the ONE computation of "which rows may run now", so a
# per-batch width on the approval card is the same answer the tick will give when the
# batch comes up. Neither is re-implemented here: a card that counted rows its own way
# would be a second opinion at the gate where the first one is being ratified.
# shellcheck source=/dev/null
. "${CARD_SELF_DIR}/lib/roots.sh"
# shellcheck source=/dev/null
. "${CARD_SELF_DIR}/lib/fill.sh"

# THE SCALE, WHICH IS A PROPERTY OF THE ARTIFACT AND NOT OF THE ROW KIND (D8). The
# `## Tasks` ledger has two shapes — the wave's eleven columns and the task run's six,
# in a different ORDER — and until this task card.sh knew only the first, reading a
# task-scale row positionally as a wave row: `rigor` printed under a heading saying
# `kind`, `worktree` under `depends`, `status` under `agent` (research R3). The whole-card
# verbs set this from the artifact's own `scale:` frontmatter; a hand-fed TSV row leaves
# it at `wave`, which is the shape every existing caller feeds and the reason this is a
# global rather than a new row kind: a second kind would be a second name for one card
# row, and the row kinds are an interface.
CARD_SCALE="wave"

_card_usage() {  # <message>
  printf 'card.sh: %s — usage: card.sh <requirement|decision|ownership|eval-design|task> with TSV rows on stdin, or card.sh <step1|step2|step3> <artifact>\n' \
    "${1:-no row kind}" >&2
  exit 64
}

# ── THE SIX FORMATS, WHICH LIVED IN THE THREE CARDS UNTIL THIS FILE ──────────
#
# Held exactly as steps/1.md, steps/2.md and steps/3.md stated them at 89f6944,
# widths included (T31 fitted them to the 100-column rule and nothing here moves
# them). `CARD_FOLD_n` is the ZERO-BASED index, within that line's own fields, of
# the one free-text cell that folds; every other cell is structured — an id, a
# count, a filename, an agent name — and is printed as given.
#
# A KIND IS A CASE, NOT A TABLE, because /bin/bash on this platform is 3.2 and has
# no associative arrays. The same reason there is no `mapfile` and no `${var,,}`
# anywhere in this file.
_card_spec() {  # <kind> -> 0 and the spec globals, or 1 for an unknown kind
  CARD_LINES=1; CARD_FMT_1=""; CARD_FOLD_1=0; CARD_NF_1=0
  CARD_FMT_2=""; CARD_FOLD_2=0; CARD_NF_2=0
  CARD_SECTION=""; CARD_HDRCOLS=""
  # THE LABEL, WHEN A FOLDING CELL HAS ONE (epic-23 wave-15 T23; Chris's AC-10.1
  # read, 2026-09-17). `provenance ` on the requirement row's second line and
  # `surfaces ` on the ownership row are literal WORDS printed before the
  # folding cell, not alignment spacing — and until this task they lived in the
  # format's own pre-field literal, which meant a continuation line (which
  # reprints that literal as blank spaces, per the WRAPPED shape) indented under
  # the TEXT after the label rather than under the label itself, wasting exactly
  # the label's own width on every line the fold produces. Moving the label into
  # the cell's VALUE instead — and shrinking the literal to the bare separator
  # that is left — makes the label print once, on the row's own first line
  # exactly as before, and lets a continuation line start where the label
  # started and use the label's own width too. See `_card_emit`'s use of these.
  CARD_LABEL_1=""; CARD_LABEL_2=""
  case "${1:-}" in
    requirement)
      CARD_SECTION="Requirements"
      # RULE 5 (Chris's third read, one stream): the title and the provenance
      # are not two cells any more, or two lines — they are ONE word-wrapped
      # stream, title then the seam " · " then provenance, filling the text
      # column greedily. When the title leaves room on a line, provenance
      # keeps going on that same line rather than starting a fresh one
      # (rule 5's own picture: "that names none · provenance seed row 4…" on
      # the SAME line). `_CARD_AWK`'s `flush_req` builds that single string
      # for a whole card, and a hand-fed TSV row builds the identical seam by
      # hand, before this kind's row is even reached — so the fold field here
      # is ordinary text like any other kind's, no per-kind label mechanism
      # needed for it any more (rules 1/4's old CARD_LABEL_2/CARD_FMT_2 retire
      # with them; ownership's `surfaces` label is unrelated and unchanged).
      #
      # `ACs n` still lives on the row's own first line (rule 3), so the
      # stream's column still needs a width of its OWN rather than the "rest
      # of the line" fallback a trailing-less fold field would get — the
      # fallback that would otherwise let the stream run to the edge and abut
      # `ACs n` (rule 2). `_rq1_lit` is the two literals around it (id + one
      # separating space, and two spaces + "ACs" + one space); the reserve
      # past that is four columns — no shipped card has ever carried ten or
      # more acceptance criteria on one requirement, so two digits already
      # covers every real value, and the extra headroom is what keeps a
      # same-shaped-but-wider ACs cell (this suite's own placeholder, `<n>`,
      # is three columns) from tripping `_card_shrink_line`'s overflow path —
      # which has nothing safe to shrink on this line but `id`, and would
      # fold it (A-T23.1). Because the stream is now the row's ONLY fold
      # field and nothing else trails `ACs`, rule 4's right-edge bound (the
      # stream never running under `ACs n`) falls out of this ONE declared
      # width for free — there is no second field left to keep it in step
      # with.
      local _rq1_lit=$(( 4 + 7 + 1 + 2 + 3 + 1 )) _rq1_w
      _rq1_w=$(( BIONIC_LINE_WIDTH - _rq1_lit - 4 ))
      CARD_FMT_1="    %-7s %-${_rq1_w}s  ACs %s"; CARD_NF_1=3; CARD_FOLD_1=1 ;;
    decision)
      CARD_SECTION="Decisions"
      CARD_HDRCOLS="2:serves 3:ADR"
      CARD_FMT_1='    %-4s %-44s %-14s %s';            CARD_NF_1=4; CARD_FOLD_1=1 ;;
    ownership)
      CARD_SECTION="Ownership"
      # `surfaces ` moves out of the literal and into the folding cell's value
      # (see CARD_LABEL_1 above); the one space left in the literal is the
      # separator the `owner` column already printed before it.
      CARD_FMT_1='    %-12s owner %-14s %-22s test %s'; CARD_NF_1=4; CARD_FOLD_1=2
      CARD_LABEL_1="surfaces " ;;
    eval-design)
      CARD_SECTION="Eval design"
      CARD_HDRCOLS="2:static 3:unit 4:hermetic 5:live 6:human"
      CARD_FMT_1='    %-8s %-36s %6s %5s %9s %5s %6s';  CARD_NF_1=7; CARD_FOLD_1=1 ;;
    task)
      CARD_SECTION="Tasks"
      # THE HEADINGS FOLLOW THE SCALE, THE WIDTHS DO NOT. A task-scale row carries the
      # same five cells in the same five columns — id, description, and three structured
      # cells — so the format, the fold column and pin 152's equality are untouched; only
      # the three labels change, because at task scale those columns hold `rigor`,
      # `status` and `worktree` (steps/3.md:22's own column order).
      if [ "${CARD_SCALE:-wave}" = "task" ]; then
        CARD_HDRCOLS="2:rigor 3:status 4:worktree"
      else
        CARD_HDRCOLS="2:kind 3:depends 4:agent"
      fi
      CARD_FMT_1='    %-5s %-30s %-10s %-13s %s';       CARD_NF_1=5; CARD_FOLD_1=1 ;;
    *) return 1 ;;
  esac
  return 0
}

# ── PARSING A FORMAT ─────────────────────────────────────────────────────────
#
# The format is read, never executed: each `%[-][width]s` becomes a literal, an
# alignment and a width, and the row is built field by field with padding counted
# in COLUMNS. Handing the same format to printf would undo the whole point of the
# file on the first em dash.
_card_parse() {  # <fmt> — sets CARD_LIT[] CARD_DASH[] CARD_W[] CARD_TAIL
  local rest="${1:-}"
  CARD_LIT=(); CARD_DASH=(); CARD_W=()
  while [[ "$rest" =~ ^([^%]*)%(-?)([0-9]*)s(.*)$ ]]; do
    CARD_LIT[${#CARD_LIT[@]}]="${BASH_REMATCH[1]}"
    CARD_DASH[${#CARD_DASH[@]}]="${BASH_REMATCH[2]}"
    CARD_W[${#CARD_W[@]}]="${BASH_REMATCH[3]}"
    rest="${BASH_REMATCH[4]}"
  done
  CARD_TAIL="$rest"
}

_card_spaces() {  # <n> -> n spaces (0 or less -> none)
  local n="${1:-0}"
  [ "$n" -gt 0 ] || { printf ''; return 0; }
  printf '%*s' "$n" ''
}

_card_rstrip() {  # <string> -> the string with its trailing spaces removed
  local s="${1:-}"
  printf '%s' "${s%"${s##*[! ]}"}"
}

# ── THE HEADER ───────────────────────────────────────────────────────────────
#
# The section label at two spaces, and each column label at the exact column its
# own field starts at — computed from the format, never typed. The drift this
# closes is the one T31 found: a Decisions header saying serves@57 over a format
# putting it at @77. With one owner there is no second number to disagree with.
_card_header() {
  local line="  ${CARD_SECTION}" pair idx lbl col i want
  if [ -n "$CARD_HDRCOLS" ]; then
    _card_parse "$CARD_FMT_1"
    for pair in $CARD_HDRCOLS; do
      idx="${pair%%:*}"; lbl="${pair##*:}"
      col=1; i=0
      while [ "$i" -lt "$idx" ]; do
        _bionic_cols_into "${CARD_LIT[$i]}"; col=$(( col + BIONIC_COLS ))
        # THE BATCH WIDTH (AC-9.5), same one _card_emit applies to the rows —
        # a header built from the format's own width alone would label a
        # column the rows no longer start there.
        want="${CARD_BW1[$i]:-}"; [ -n "$want" ] || want="${CARD_W[$i]:-}"
        [ -n "$want" ] || want=0
        col=$(( col + want ))
        i=$(( i + 1 ))
      done
      _bionic_cols_into "${CARD_LIT[$idx]}"; col=$(( col + BIONIC_COLS ))
      _bionic_cols_into "$line"
      line="${line}$(_card_spaces $(( col - 1 - BIONIC_COLS )))${lbl}"
    done
  fi
  _card_rstrip "$line"
  printf '\n'
}

# ── PER-BATCH COLUMN WIDTHS (AC-9.5) ─────────────────────────────────────────
#
# WHY A BATCH AND NOT A ROW. Every width above this point is either the
# format's own declared width or that ONE row's own cell — so a structured
# (non-folding) cell wider than its column, an owner such as
# `tests/lib/impact.sh` against the ownership format's 14-column `owner`
# field, pushed every trailing column on ITS OWN row right, and left every
# OTHER row's trailing columns exactly where the format put them. Two
# ownership rows in the same card then disagreed about where `surfaces` and
# `test` start — not a fold problem (WRAPPED already handles a cell too long
# for ITS OWN column) but a CROSS-ROW one: the same visual column meaning two
# different things on two lines of one table. Chris "approved" 2026-09-16 on
# the stated default: a structured column's width is the greater of the
# format's own width and the widest cell that column holds ANYWHERE in this
# card, so every row pads to the one number rather than to its own guess.
#
# THE FOLD COLUMN IS EXCLUDED ON PURPOSE. It already self-normalizes to its
# own declared width every row (`bionic_wrap` plus the pad below never let it
# render narrower OR wider than its budget), so batching it would only widen
# it past that budget for no reason. The one field with NO declared width
# (the row's own last cell — `ADR`, `test`, `agent`, `ACs`) is excluded too:
# nothing trails it, so there is no column left of anything to keep constant,
# and giving it a batch width would right-justify what a caller wrote to be
# read left-aligned.
CARD_BW1=(); CARD_BW2=()
CARD_FOLDSET1=(); CARD_FOLDSET2=()
_card_compute_batch_widths() {  # reads CARD_ROWS[] — sets CARD_BW1[] CARD_BW2[] CARD_FOLDSET1[] CARD_FOLDSET2[]
  CARD_FOLDSET1=(); CARD_FOLDSET2=()
  _card_parse "$CARD_FMT_1"
  local nf1="${#CARD_LIT[@]}" i=0
  CARD_BW1=()
  while [ "$i" -lt "$nf1" ]; do
    if [ "$i" -ne "$CARD_FOLD_1" ] && [ -n "${CARD_W[$i]:-}" ]; then
      CARD_BW1[$i]="${CARD_W[$i]}"
    else
      CARD_BW1[$i]=""
    fi
    i=$(( i + 1 ))
  done
  local nf2=0
  if [ "$CARD_LINES" -gt 1 ]; then
    _card_parse "$CARD_FMT_2"
    nf2="${#CARD_LIT[@]}"
    CARD_BW2=(); i=0
    while [ "$i" -lt "$nf2" ]; do
      if [ "$i" -ne "$CARD_FOLD_2" ] && [ -n "${CARD_W[$i]:-}" ]; then
        CARD_BW2[$i]="${CARD_W[$i]}"
      else
        CARD_BW2[$i]=""
      fi
      i=$(( i + 1 ))
    done
  fi

  local line
  for line in ${CARD_ROWS[@]+"${CARD_ROWS[@]}"}; do
    [ -n "$line" ] || continue
    _card_split "$line"
    i=0
    while [ "$i" -lt "$CARD_NF_1" ]; do
      if [ -n "${CARD_BW1[$i]:-}" ]; then
        _bionic_cols_into "${CARD_CELLS[$i]:-}"
        [ "$BIONIC_COLS" -gt "${CARD_BW1[$i]}" ] && CARD_BW1[$i]="$BIONIC_COLS"
      fi
      i=$(( i + 1 ))
    done
    if [ "$nf2" -gt 0 ]; then
      i=0
      while [ "$i" -lt "$CARD_NF_2" ]; do
        if [ -n "${CARD_BW2[$i]:-}" ]; then
          _bionic_cols_into "${CARD_CELLS[$(( CARD_NF_1 + i ))]:-}"
          [ "$BIONIC_COLS" -gt "${CARD_BW2[$i]}" ] && CARD_BW2[$i]="$BIONIC_COLS"
        fi
        i=$(( i + 1 ))
      done
    fi
  done

  _card_shrink_line 1
  [ "$CARD_LINES" -gt 1 ] && _card_shrink_line 2
  return 0
}

# ── THE LINE-WIDTH INVARIANT (AC-9.4), WHICH OUTRANKS THE WIDENING ───────────
#
# WHY A SHRINK EXISTS AT ALL. The widening above keeps a card's trailing columns
# on one column by making every structured column as wide as the widest cell it
# holds anywhere in the batch. On this wave's own Step-2 card that is a 38-column
# `concept` beside a 46-column `owner`, and they push `test` — the row's last
# cell, the one field the format gives no width at all — out to column 134, where
# a 160-column suite list then runs to column 297. A wrapped line is one row
# turned into two and the table stops being a table: lib/width.sh's founding note,
# and the reason AC-9.4 is the harder of the two rules. So the widening may widen
# only as far as the budget allows (A-T11.5, A-orch-20 (2); Chris may reverse the
# rule at the Step-5 read).
#
# WHAT SHRINKS, AND ONLY WHEN. Nothing at all, unless the batch's widest row
# actually overflows — a card that already fits renders byte for byte what it
# rendered before, so the invariant costs the cards that never had the problem
# nothing, and the AC-9.5 pair this suite pins (rows 40/41) does not move. When a
# batch does overflow, the widest structured column gives up ONE column at a time
# — so the next-widest takes its turn as soon as it is the widest, and they
# converge rather than one of them collapsing alone — until the trailing cell has
# CARD_MIN_TRAIL columns to fold inside. A column left narrower than a cell it
# holds then FOLDS that cell inside itself: the D4 WRAPPED shape, applied to a
# structured cell, with the trailing columns still on the row's first line and
# still starting on one column across the card. AC-9.5 kept, AC-9.4 held.
#
# THE FLOOR IS THE FORMAT'S OWN DECLARED WIDTH, dropped to a single column only if
# the trailing cell would otherwise have no room whatever. No format shipped here
# needs that second pass; it is here so the invariant cannot be defeated by a
# format added later with wider columns than the budget can hold.
CARD_MIN_TRAIL=24

# The widest cell each field holds in this batch — what the shrink needs in order
# to know which columns will have to fold once they are narrowed.
CARD_MAX=()
_card_widest_cells() {  # <line 1|2> — sets CARD_MAX[] over CARD_ROWS[]
  local nf off i line
  if [ "$1" = "2" ]; then nf="$CARD_NF_2"; off="$CARD_NF_1"; else nf="$CARD_NF_1"; off=0; fi
  CARD_MAX=()
  i=0
  while [ "$i" -lt "$nf" ]; do CARD_MAX[$i]=0; i=$(( i + 1 )); done
  for line in ${CARD_ROWS[@]+"${CARD_ROWS[@]}"}; do
    [ -n "$line" ] || continue
    _card_split "$line"
    i=0
    while [ "$i" -lt "$nf" ]; do
      _bionic_cols_into "${CARD_CELLS[$(( off + i ))]:-}"
      [ "$BIONIC_COLS" -gt "${CARD_MAX[$i]}" ] && CARD_MAX[$i]="$BIONIC_COLS"
      i=$(( i + 1 ))
    done
  done
}

# THE LABEL'S WIDTH JOINS THE FOLD FIELD'S OWN, BUT ONLY WHEN SOMETHING
# TRAILS IT (T23) — wherever CARD_W[] has just been parsed fresh from a format
# string, for a fold field that carries a label (CARD_LABEL_1/2; see
# `_card_spec`). This is called identically here and in `_card_emit`, which
# each parse the format independently and would otherwise disagree about the
# same field's width: `_card_shrink_line` deciding how much room a row needs
# using the UNEXTENDED width while `_card_emit` rendered the EXTENDED one is
# exactly the bug that shrinking the wrong candidate, or not enough of it,
# would reproduce.
#
# WHEN THE FOLD FIELD IS THE LAST FIELD ON ITS LINE (requirement's
# provenance), there is nothing downstream to protect a position for, and the
# label is not free extra room — it is content, spending the SAME budget the
# text does, because that budget is what rule 4 pins to the title field's own
# right edge (Chris's second read: nothing may print under the `ACs n`
# column). Extending it here would push provenance's right edge past the
# title's, undoing rule 4 for the sake of a label. So the extension applies
# only when `fold` is NOT the last field (`nf`) — ownership's `surfaces`,
# which `test` trails, keeps it; provenance, which nothing trails, does not.
_card_extend_fold_for_label() {  # <fold index> <line 1|2> <field count on this line>
  local fold="$1" lineno="$2" nf="$3" label=""
  [ "$fold" -lt "$(( nf - 1 ))" ] || return 0
  [ "$lineno" = "2" ] && label="$CARD_LABEL_2" || label="$CARD_LABEL_1"
  [ -n "$label" ] && [ -n "${CARD_W[$fold]:-}" ] || return 0
  _bionic_cols_into "$label"; CARD_W[$fold]=$(( CARD_W[$fold] + BIONIC_COLS ))
}

_card_shrink_line() {  # <line 1|2> — narrows CARD_BW[] and sets CARD_FOLDSET[]
  local lineno="$1" fmt fold nf i
  if [ "$lineno" = "2" ]; then fmt="$CARD_FMT_2"; fold="$CARD_FOLD_2"; nf="$CARD_NF_2"
  else fmt="$CARD_FMT_1"; fold="$CARD_FOLD_1"; nf="$CARD_NF_1"; fi
  _card_parse "$fmt"
  _card_extend_fold_for_label "$fold" "$lineno" "${#CARD_LIT[@]}"
  local nfields="${#CARD_LIT[@]}"
  [ "$nfields" -gt 0 ] || return 0
  _card_widest_cells "$lineno"

  # THE WIDTH IN FORCE for every field, and the one field that has none. `tf` is
  # the row's trailing cell — the last field the format declares no width for —
  # which is the cell that runs off the line, because nothing bounds it.
  local w=() floor=() litw=() start=() tf=-1
  i=0
  while [ "$i" -lt "$nfields" ]; do
    _bionic_cols_into "${CARD_LIT[$i]}"; litw[$i]="$BIONIC_COLS"
    floor[$i]="${CARD_W[$i]:-}"
    if [ "$lineno" = "2" ]; then w[$i]="${CARD_BW2[$i]:-}"; else w[$i]="${CARD_BW1[$i]:-}"; fi
    [ -n "${w[$i]}" ] || w[$i]="${CARD_W[$i]:-}"
    [ -n "${CARD_W[$i]:-}" ] || tf="$i"
    i=$(( i + 1 ))
  done

  # Where every field starts, and how wide the batch's widest FIRST line comes
  # out, given the widths in force. Recomputed after every column given up.
  local col over
  _card_line_extent() {
    col=1; i=0
    while [ "$i" -lt "$nfields" ]; do
      col=$(( col + ${litw[$i]} ))
      start[$i]="$col"
      [ -n "${w[$i]}" ] && col=$(( col + ${w[$i]} ))
      i=$(( i + 1 ))
    done
    if [ "$tf" -ge 0 ]; then over=$(( ${start[$tf]} - 1 + ${CARD_MAX[$tf]:-0} ))
    else over=$(( col - 1 )); fi
  }

  _card_line_extent
  if [ "$lineno" = "2" ]; then CARD_FOLDSET2=(); else CARD_FOLDSET1=(); fi
  i=0
  while [ "$i" -lt "$nfields" ]; do
    if [ "$lineno" = "2" ]; then CARD_FOLDSET2[$i]=0; else CARD_FOLDSET1[$i]=0; fi
    i=$(( i + 1 ))
  done
  # NOTHING OVERFLOWS, NOTHING MOVES.
  [ "$over" -gt "$BIONIC_LINE_WIDTH" ] || { unset -f _card_line_extent; return 0; }

  local phase=1 want widest widx floorv
  while [ "$phase" -le 2 ]; do
    if [ "$phase" -eq 1 ]; then want="$CARD_MIN_TRAIL"; else want=1; fi
    while :; do
      _card_line_extent
      if [ "$tf" -ge 0 ]; then
        [ $(( ${start[$tf]} - 1 + want )) -gt "$BIONIC_LINE_WIDTH" ] || break
      else
        [ $(( col - 1 )) -gt "$BIONIC_LINE_WIDTH" ] || break
      fi
      widest=0; widx=-1; i=0
      while [ "$i" -lt "$nfields" ]; do
        if [ "$i" -ne "$fold" ] && [ -n "${w[$i]}" ]; then
          if [ "$phase" -eq 1 ]; then floorv="${floor[$i]}"; else floorv=1; fi
          [ -n "$floorv" ] || floorv=1
          if [ "${w[$i]}" -gt "$floorv" ] && [ "${w[$i]}" -gt "$widest" ]; then
            widest="${w[$i]}"; widx="$i"
          fi
        fi
        i=$(( i + 1 ))
      done
      [ "$widx" -ge 0 ] || break
      w[$widx]=$(( widest - 1 ))
    done
    _card_line_extent
    if [ "$tf" -ge 0 ]; then
      [ $(( ${start[$tf]} )) -gt "$BIONIC_LINE_WIDTH" ] || break
    else
      [ $(( col - 1 )) -gt "$BIONIC_LINE_WIDTH" ] || break
    fi
    phase=$(( phase + 1 ))
  done
  unset -f _card_line_extent

  # The narrowed widths go back, and every column now narrower than a cell it
  # holds — plus the trailing cell, which is what all of this was for — is marked
  # to fold inside itself.
  i=0
  while [ "$i" -lt "$nfields" ]; do
    if [ "$i" -ne "$fold" ] && [ -n "${floor[$i]}" ]; then
      if [ "$lineno" = "2" ]; then CARD_BW2[$i]="${w[$i]}"; else CARD_BW1[$i]="${w[$i]}"; fi
      if [ "${CARD_MAX[$i]:-0}" -gt "${w[$i]}" ]; then
        if [ "$lineno" = "2" ]; then CARD_FOLDSET2[$i]=1; else CARD_FOLDSET1[$i]=1; fi
      fi
    fi
    i=$(( i + 1 ))
  done
  if [ "$tf" -ge 0 ] && [ "$tf" -ne "$fold" ]; then
    if [ "$lineno" = "2" ]; then CARD_FOLDSET2[$tf]=1; else CARD_FOLDSET1[$tf]=1; fi
  fi
  return 0
}

# ── ONE ROW, WHICH MAY BE MORE THAN ONE LINE ─────────────────────────────────
_card_emit() {  # <fmt> <fold index> <line 1|2> <cell>...
  local fmt="$1" fold="$2" lineno="$3"; shift 3
  local vals=("$@")
  _card_parse "$fmt"
  local nf="${#CARD_LIT[@]}"
  local i col=1 val w eff bw budget chunk
  local startcol=() effw=() folds=()

  # THE BATCH WIDTH WINS OVER THE FORMAT'S OWN, for every field this card's
  # rows actually widened — or, where the batch overflowed the budget, the
  # NARROWED width _card_shrink_line left behind (never less than the format's
  # declared width unless the trailing cell had no room at all). The same pass
  # says which fields fold; the format's own free cell always does.
  i=0
  while [ "$i" -lt "$nf" ]; do
    if [ "$lineno" = "2" ]; then bw="${CARD_BW2[$i]:-}"; folds[$i]="${CARD_FOLDSET2[$i]:-0}"
    else bw="${CARD_BW1[$i]:-}"; folds[$i]="${CARD_FOLDSET1[$i]:-0}"; fi
    [ -n "$bw" ] && CARD_W[$i]="$bw"
    [ "$i" -eq "$fold" ] && folds[$i]=1
    i=$(( i + 1 ))
  done

  # THE LABEL MOVES FROM THE LITERAL INTO THE VALUE (T23, rule 1). `_card_spec`
  # already shrank the pre-field literal down to its bare separator, so the
  # label word itself has to be printed some other way — as the FRONT of the
  # folding cell's own value, wrapped and folded exactly like the rest of it.
  # That is what lets a continuation line start under the label rather than
  # under the text after it: the literal a continuation line reprints as blank
  # is now just the separator, not the separator-plus-label.
  #
  # A FIELD WITH SOMETHING TRAILING IT (ownership's `surfaces`, which `test`
  # follows) gets its width WIDENED by the label's own column count, so the
  # text half of the cell keeps exactly the room it had before — the row's
  # first line, and every downstream column's start, comes out byte for byte
  # what it always did (proved by hand before this task's commit: literal
  # shrinks by the label's width, the field's effective width grows by the
  # same amount, and the two cancel for anything printed after it). A field
  # that is the LAST on its line (requirement's `provenance`) gets no such
  # widening — its declared width is rule 4's right-edge bound (Chris's second
  # read: nothing prints under the `ACs n` column), and the label spends that
  # same budget rather than adding to it (`_card_extend_fold_for_label`).
  local label=""
  [ "$lineno" = "2" ] && label="$CARD_LABEL_2" || label="$CARD_LABEL_1"
  [ -n "$label" ] && vals[$fold]="${label}${vals[$fold]:-}"
  _card_extend_fold_for_label "$fold" "$lineno" "$nf"

  # PASS ONE: where each cell starts, and how many columns it occupies. The start
  # is computed against the ACTUAL values of the cells BEFORE it — a preceding
  # cell wider than its column pushes this one right, and the continuation lines
  # have to land under wherever it really is. A cell that FOLDS occupies its own
  # column and no more, because folding is exactly what keeps it there.
  i=0
  while [ "$i" -lt "$nf" ]; do
    _bionic_cols_into "${CARD_LIT[$i]}"; col=$(( col + BIONIC_COLS ))
    startcol[$i]="$col"
    w="${CARD_W[$i]}"
    if [ "${folds[$i]}" = "1" ]; then
      eff="$w"; [ -n "$eff" ] || eff=0
    else
      val="${vals[$i]:-}"; _bionic_cols_into "$val"; eff="$BIONIC_COLS"
      if [ -n "$w" ] && [ "$w" -gt "$eff" ]; then eff="$w"; fi
    fi
    effw[$i]="$eff"
    col=$(( col + eff ))
    i=$(( i + 1 ))
  done

  # THE CHUNKS. A folding cell is broken inside its own column — and for a free
  # cell that ends the row (the requirement text, which has no trailing column at
  # all) that column is whatever is left of the line. Either way the fold, not
  # the terminal, decides where the text breaks. Every other cell is one chunk,
  # the value exactly as given: a cell that FITS is never passed through the fold,
  # so a batch inside the budget comes out byte for byte what it always did.
  local chflat=() choff=() chcnt=() maxc=1
  i=0
  while [ "$i" -lt "$nf" ]; do
    choff[$i]="${#chflat[@]}"
    val="${vals[$i]:-}"
    if [ "${folds[$i]}" = "1" ]; then
      budget="${CARD_W[$i]}"
      [ -n "$budget" ] || budget=$(( BIONIC_LINE_WIDTH - ${startcol[$i]} + 1 ))
      [ "$budget" -ge 1 ] || budget=1
      _bionic_cols_into "$val"
      if [ "$i" -ne "$fold" ] && [ "$BIONIC_COLS" -le "$budget" ]; then
        chflat[${#chflat[@]}]="$val"
      else
        while IFS= read -r chunk; do chflat[${#chflat[@]}]="$chunk"; done < <(bionic_wrap "$val" "$budget")
      fi
    else
      chflat[${#chflat[@]}]="$val"
    fi
    chcnt[$i]=$(( ${#chflat[@]} - ${choff[$i]} ))
    [ "${chcnt[$i]}" -gt "$maxc" ] && maxc="${chcnt[$i]}"
    i=$(( i + 1 ))
  done

  # PASS TWO: the row's own first line carries every cell's first chunk and every
  # trailing column; each further line carries the next chunk of whatever is still
  # folding, each under its own column, and nothing else — the literals that label
  # a column are printed as the spaces they occupy, so a continuation line never
  # reads as a row of its own.
  local out pad dash k=0
  while [ "$k" -lt "$maxc" ]; do
    out=""
    i=0
    while [ "$i" -lt "$nf" ]; do
      if [ "$k" -eq 0 ]; then
        out="${out}${CARD_LIT[$i]}"
      else
        _bionic_cols_into "${CARD_LIT[$i]}"; out="${out}$(_card_spaces "$BIONIC_COLS")"
      fi
      if [ "$k" -lt "${chcnt[$i]}" ]; then val="${chflat[$(( ${choff[$i]} + k ))]}"; else val=""; fi
      _bionic_cols_into "$val"; eff="$BIONIC_COLS"
      w="${effw[$i]}"; dash="${CARD_DASH[$i]}"; pad=""
      if [ "$w" -gt "$eff" ]; then pad="$(_card_spaces $(( w - eff )))"; fi
      if [ "$dash" = "-" ]; then out="${out}${val}${pad}"; else out="${out}${pad}${val}"; fi
      i=$(( i + 1 ))
    done
    _card_rstrip "${out}${CARD_TAIL}"; printf '\n'
    k=$(( k + 1 ))
  done
}
# A row's cells, split on TABS — and on tabs only. `read -a` with IFS set to a tab
# drops an empty field, and an empty free cell is a real row (a decision with no
# ADR yet), so the split is done here by hand where it can keep one.
CARD_TAB="$(printf '\t')"
_card_split() {  # <line> — sets CARD_CELLS[]
  local rest="${1:-}" cell
  CARD_CELLS=()
  while :; do
    case "$rest" in
      *"$CARD_TAB"*) cell="${rest%%"$CARD_TAB"*}"; rest="${rest#*"$CARD_TAB"}" ;;
      *) CARD_CELLS[${#CARD_CELLS[@]}]="$rest"; break ;;
    esac
    CARD_CELLS[${#CARD_CELLS[@]}]="$cell"
  done
}

# ── THE WHOLE CARD (REQ-10) ──────────────────────────────────────────────────
#
# WHY THE VERB EXISTS, WHICH IS NOT "FEWER KEYSTROKES". Above this line card.sh
# owns the WIDTHS and the caller still owns the CONTENT: the model read the step
# file's picture, lifted the rows out of the artifact by eye, and fed them back
# one TSV line at a time. So every card was a TRANSCRIPTION of its artifact, and
# a transcription can differ from its source without anything going red — a REQ
# text shortened in the retelling, an AC count off by one, a provenance dropped.
# The card is what an approval BINDS (steps/1.md: "Approval is against the card,
# and the card's own question is the gate"), so a card that is a retelling is a
# correctness problem, not an untidiness. Chris 2026-09-16: "I do want the AI to
# use the card.sh script" — lever 1, A-orch-3.
#
# THE ARTIFACT IS THE SSoT (spec §3, "Card content"). `step1 <requirements.md>`,
# `step2 <spec.md>` and `step3 <plan.md>` read the artifact and render the whole
# card; nothing is read from stdin, because a second input is a second place the
# content could come from and the whole point is that there is one.
#
# THE ROWS GO THROUGH THE ROW KINDS, unchanged (AC-10.3). The awk pass below
# produces TSV — the very same TSV a caller would have typed — and hands it to
# `_card_render_batch`, so a whole card's row and a hand-fed row of the same
# content are byte-identical by construction rather than by agreement. There is
# one fold and one pad in this file, not two.
#
# A DEFECTIVE ARTIFACT IS A USAGE ERROR, NEVER HALF A CARD (AC-10.4). The parse
# completes before anything prints: an artifact with no `## Goal`, or a `### REQ-`
# heading with no `provenance:` line, names the missing piece on stderr and exits
# 64 with an empty stdout. Half a card at an approval gate is worse than none,
# because it is the half that looks finished.
#
# MARKDOWN MARKUP IS NOT CONTENT. Backticks come off every cell: the artifact
# writes `lib/first.sh` for a reader of Markdown and the card is read in a
# terminal, where the backticks are three characters of noise inside a column
# budget. Nothing else is rewritten — the text, the provenance and the counts are
# the artifact's own (A-T11.2).

_CARD_AWK='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function clean(s) { gsub(/`/, "", s); gsub(/\t/, " ", s); return trim(s) }
# The first sentence of a cell the card shows on one line. A ledger cell and a
# design bullet each carry their whole story; the card carries the opening of it
# and the artifact path is the depth (steps/1.md: "never a paragraph").
function firstsent(s) { if (match(s, /\. /)) return substr(s, 1, RSTART); return s }
function cells(line, arr,   n, i) {
  gsub(/\\\|/, "\001", line)
  sub(/^[ \t]*\|/, "", line); sub(/\|[ \t]*$/, "", line)
  n = split(line, arr, "|")
  for (i = 1; i <= n; i++) { gsub(/\001/, "|", arr[i]); arr[i] = clean(arr[i]) }
  return n
}
function err(m) { if (ERRMSG == "") ERRMSG = m }
function flush_nd() { if (ndbuf != "") { print "ND" OFS clean(ndbuf); ndbuf = "" } }
function flush_req(   stream) {
  if (rid == "") return
  if (rprov == "") { err("REQ-" rid " has no provenance: line"); rid = ""; return }
  # RULE 5 (one stream): the title and the provenance are ONE folding cell,
  # joined here by the seam " · provenance " before the row kind ever sees
  # two separate cells — a hand-fed TSV row builds the identical string, so
  # AC-10.3 byte identity holds by construction, not by two code paths
  # agreeing to build the same seam twice.
  stream = rtext " · provenance " rprov
  print "RROW" OFS "REQ-" rid OFS stream OFS racs
  rid = ""; rtext = ""; rprov = ""; racs = 0
}
function flush_dec(   line, id, serves) {
  if (dbuf == "") return
  line = dbuf; dbuf = ""
  if (match(line, /\(D[0-9]+;[^)]*\)/)) {
    id = substr(line, RSTART + 1, RLENGTH - 2)
    serves = id; sub(/^D[0-9]+;[ \t]*/, "", serves)
    sub(/;.*$/, "", id)
    line = substr(line, 1, RSTART - 1)
    gsub(/\*\*/, "", line)
    print "DROW" OFS id OFS clean(firstsent(clean(line))) OFS clean(serves)
  }
}
function flush_adr(   line, path, rest, id) {
  if (abuf == "") return
  line = abuf; abuf = ""
  if (!match(line, /`[^`]*adr-[^`]*`/)) return
  path = substr(line, RSTART + 1, RLENGTH - 2)
  rest = line
  while (match(rest, /\(D[0-9]+[^)]*\)/)) {
    id = substr(rest, RSTART + 1, RLENGTH - 2); sub(/[^0-9D].*$/, "", id)
    print "ADR" OFS id OFS path
    rest = substr(rest, RSTART + RLENGTH)
  }
}
function flush_all() { flush_nd(); flush_req(); flush_dec(); flush_adr() }
BEGIN { OFS = "\t"; ERRMSG = ""; mrows = 0; enum = 0 }
NR == 1 && $0 == "---" { fm = 1; next }
fm == 1 && $0 == "---" { fm = 0; next }
fm == 1 {
  k = $0; sub(/:.*$/, "", k); v = $0; sub(/^[^:]*:[ \t]*/, "", v)
  if (k == "working-branch") WB = v
  else if (k == "scale") SCALE = v
  else if (k == "integration-branch") IB = v
  else if (k == "base-sha") BASE = v
  else if (k == "rigor") RIGOR = v
  else if (k == "walk") WALK = v
  else if (k == "adrs") ADRS = v
  else if (k == "parallel-budget") {
    if (match(v, /writers=[0-9]+/)) WRITERS = substr(v, RSTART + 8, RLENGTH - 8)
  }
  next
}
/^## / {
  flush_all()
  h = substr($0, 4); sub2 = ""
  if (h == "Goal") { sec = "goal"; sawgoal = 1 }
  else if (h == "Design") { sec = "design"; sawdesign = 1 }
  else if (h == "Not Doing") sec = "nd"
  else if (h == "Tasks") { sec = "tasks"; sawtasks = 1; trow = 0 }
  else if (h == "Eval design") { sec = "eval"; saweval = 1; erow = 0 }
  else if (h == "Verification Matrix") { sec = "matrix"; mrow = 0 }
  else if (h ~ /^Requirements/) sec = "reqs"
  else sec = ""
  next
}
/^### / {
  flush_all()
  h = substr($0, 5)
  if (h ~ /^REQ-/) {
    sec = "reqs"; sub2 = ""; sub(/^REQ-/, "", h)
    rid = h; sub(/[ \t].*$/, "", rid)
    rtext = h; sub(/^[^ \t]+[ \t]*/, "", rtext); sub(/^— */, "", rtext)
    rtext = clean(rtext); rprov = ""; racs = 0
  }
  else if (h ~ /Component boundaries/) sub2 = "dec"
  else if (h ~ /Ownership table/) { sub2 = "own"; orow = 0 }
  else if (h ~ /ADR pointers/) sub2 = "adr"
  else sub2 = ""
  next
}
sec == "goal" && goaldone != 1 {
  if (trim($0) == "") { if (GOAL != "") goaldone = 1 }
  else GOAL = GOAL (GOAL == "" ? "" : " ") clean($0)
  next
}
# THE DESIGN PARAGRAPH (D8). A task-scale run writes its design as a PARAGRAPH in the
# session plan and owes no `## Design` heading at all (steps/2.md:60, "no wall at task
# scale at all") — so this reads the first paragraph under the heading WHEN THERE IS ONE
# and the Step-2 card falls back to the Goal of the plan when there is not. The first
# paragraph only: a design section is a document, the card is a line, and the artifact
# path is the depth. A wave-scale spec runs through here too and nothing reads DESIGN on
# that card, because the wave card already renders the decisions, the ownership and the
# eval design the wave design is MADE of.
sec == "design" && designdone != 1 {
  if (trim($0) == "") { if (DESIGN != "") designdone = 1 }
  else DESIGN = DESIGN (DESIGN == "" ? "" : " ") clean($0)
  next
}
sec == "nd" {
  if (/^- /) { flush_nd(); ndbuf = substr($0, 3) }
  else if (/^[ \t]+[^ \t]/ && ndbuf != "") ndbuf = ndbuf " " trim($0)
  else if (trim($0) == "") flush_nd()
  next
}
sec == "reqs" && rid != "" {
  if (/^provenance:/) rprov = clean(substr($0, 12))
  else if (/^- AC-/) racs++
  next
}
sec == "tasks" && /^[ \t]*\|/ {
  trow++
  if (trow <= 2) next
  n = cells($0, c)
  if (n < 6) next
  # TWO TABLE SHAPES, TWO MAPS (D8). The wave ledger is
  # `| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |`
  # and the task ledger is `| id | intent | rigor | description | status | worktree |`
  # (steps/3.md:22/24) — six cells in a DIFFERENT ORDER, not a prefix of the eleven. Read
  # with the wave map a task row printed its rigor under `kind`, its worktree under
  # `depends` and its status under `agent`; the worktree one is the reason this is a
  # correctness defect and not a cosmetic one, because `.worktrees/18-T2` under a column
  # headed `depends` reads as a dependency that exists.
  if (SCALE == "task") print "TROW" OFS c[1] OFS clean(firstsent(c[4])) OFS c[3] OFS c[5] OFS c[6]
  else                 print "TROW" OFS c[1] OFS clean(firstsent(c[4])) OFS c[3] OFS c[6] OFS c[5]
  # THE FIRST BATCH, ASKED OF EACH TABLE IN ITS OWN TERMS. A wave row is in the first
  # batch when it is a Step-4 row depending on nothing; a task row has no step cell and
  # no deps cell to ask about — the task arm of `units_ready` says so, "READY is `pending`
  # alone" — so the question there is the status cell, and a card that kept the wave
  # predicate said "first batch not declared" on every task-scale plan ever written.
  if (SCALE == "task") {
    if (c[5] == "pending") FIRSTB = FIRSTB (FIRSTB == "" ? "" : ", ") c[1]
  }
  else if (c[2] == "4" && (c[6] == "—" || c[6] == "-" || c[6] == "")) {
    FIRSTB = FIRSTB (FIRSTB == "" ? "" : ", ") c[1]
  }
  next
}
sec == "eval" && /^[ \t]*\|/ {
  erow++
  if (erow <= 2) next
  n = cells($0, c)
  if (n < 4) next
  r = c[1]
  if (!(r in eapp)) { eapp[r] = c[2]; enum++; eord[enum] = r }
  ecnt[r, c[4]]++
  tot[c[4]]++
  next
}
sec == "matrix" && /^[ \t]*\|/ {
  mrow++
  if (mrow <= 2) next
  n = cells($0, c)
  if (n < 2 || c[1] !~ /^AC-/) next
  mrows++
  tier[c[2]]++
  next
}
sub2 == "dec" {
  if (/^- /) { flush_dec(); dbuf = substr($0, 3) }
  else if (/^[ \t]+[^ \t]/ && dbuf != "") dbuf = dbuf " " trim($0)
  else if (trim($0) == "") flush_dec()
  next
}
sub2 == "own" && /^[ \t]*\|/ {
  orow++
  if (orow <= 2) next
  n = cells($0, c)
  if (n < 4) next
  print "OROW" OFS c[1] OFS c[2] OFS c[3] OFS c[4]
  next
}
sub2 == "adr" {
  if (/^- /) { flush_adr(); abuf = substr($0, 3) }
  else if (/^[ \t]+[^ \t]/ && abuf != "") abuf = abuf " " trim($0)
  else if (trim($0) == "") flush_adr()
  next
}
END {
  flush_all()
  if (!sawgoal) err("the artifact has no ## Goal section")
  if (verb == "step3" && !sawtasks) err("the plan has no ## Tasks ledger")
  # THE EVAL TABLE IS A WAVE OBLIGATION (D8). At task scale the design is a paragraph in
  # the session plan and there is no eval-design wall at all, so demanding the table here
  # refused the very artifact the arm exists to render (research R3: exit 64 at d7e841c).
  if (verb == "step2" && !saweval && SCALE != "task") err("the spec has no ## Eval design table")
  if (ERRMSG != "") { print "ERR" OFS ERRMSG; exit 0 }
  print "GOAL" OFS GOAL
  print "META" OFS "wb" OFS WB
  print "META" OFS "ib" OFS IB
  print "META" OFS "base" OFS BASE
  print "META" OFS "rigor" OFS RIGOR
  print "META" OFS "walk" OFS WALK
  print "META" OFS "scale" OFS SCALE
  print "META" OFS "design" OFS DESIGN
  print "META" OFS "adrs" OFS ADRS
  print "META" OFS "writers" OFS WRITERS
  print "META" OFS "firstb" OFS FIRSTB
  print "META" OFS "mrows" OFS mrows
  print "META" OFS "t0" OFS (tier["T0"] + 0)
  print "META" OFS "t1" OFS (tier["T1"] + 0)
  print "META" OFS "t2" OFS (tier["T2"] + 0)
  print "META" OFS "t3" OFS (tier["T3"] + 0)
  print "META" OFS "t4" OFS (tier["T4"] + 0)
  for (i = 1; i <= enum; i++) {
    r = eord[i]
    print "EROW" OFS r OFS eapp[r] OFS (ecnt[r, "static"] + 0) OFS (ecnt[r, "unit"] + 0) \
      OFS (ecnt[r, "hermetic"] + 0) OFS (ecnt[r, "live"] + 0) OFS (ecnt[r, "human"] + 0)
  }
  if (enum > 0) {
    print "EROW" OFS "total" OFS "" OFS (tot["static"] + 0) OFS (tot["unit"] + 0) \
      OFS (tot["hermetic"] + 0) OFS (tot["live"] + 0) OFS (tot["human"] + 0)
  }
}
'

_card_load() {  # <verb> <artifact> — sets the WCARD_* globals, or WCARD_ERR and 1
  WCARD_ERR=""; WCARD_GOAL=""; WCARD_DESIGN=""; WCARD_SCALE=""
  WCARD_WB=""; WCARD_IB=""; WCARD_BASE=""; WCARD_RIGOR=""; WCARD_WALK=""; WCARD_ADRS=""
  WCARD_WRITERS=""; WCARD_FIRSTB=""; WCARD_MROWS="0"
  WCARD_T0="0"; WCARD_T1="0"; WCARD_T2="0"; WCARD_T3="0"; WCARD_T4="0"
  WCARD_ND=(); WCARD_RROW=(); WCARD_DROW=(); WCARD_OROW=(); WCARD_EROW=(); WCARD_TROW=()
  WCARD_ADRK=(); WCARD_ADRV=()
  local out line key rest k v
  out="$(awk -v verb="$1" "$_CARD_AWK" "$2" 2>/dev/null)" || {
    WCARD_ERR="the artifact could not be parsed"; return 1; }
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key="${line%%"$CARD_TAB"*}"; rest="${line#*"$CARD_TAB"}"
    case "$key" in
      ERR)  WCARD_ERR="$rest"; return 1 ;;
      GOAL) WCARD_GOAL="$rest" ;;
      META)
        k="${rest%%"$CARD_TAB"*}"; v="${rest#*"$CARD_TAB"}"
        [ "$v" != "$rest" ] || v=""
        case "$k" in
          wb) WCARD_WB="$v" ;;           ib) WCARD_IB="$v" ;;
          base) WCARD_BASE="$v" ;;       rigor) WCARD_RIGOR="$v" ;;
          walk) WCARD_WALK="$v" ;;       adrs) WCARD_ADRS="$v" ;;
          scale) WCARD_SCALE="$v" ;;     design) WCARD_DESIGN="$v" ;;
          writers) WCARD_WRITERS="$v" ;; firstb) WCARD_FIRSTB="$v" ;;
          mrows) WCARD_MROWS="$v" ;;
          t0) WCARD_T0="$v" ;; t1) WCARD_T1="$v" ;; t2) WCARD_T2="$v" ;;
          t3) WCARD_T3="$v" ;; t4) WCARD_T4="$v" ;;
        esac ;;
      ND)   WCARD_ND[${#WCARD_ND[@]}]="$rest" ;;
      RROW) WCARD_RROW[${#WCARD_RROW[@]}]="$rest" ;;
      DROW) WCARD_DROW[${#WCARD_DROW[@]}]="$rest" ;;
      OROW) WCARD_OROW[${#WCARD_OROW[@]}]="$rest" ;;
      EROW) WCARD_EROW[${#WCARD_EROW[@]}]="$rest" ;;
      TROW) WCARD_TROW[${#WCARD_TROW[@]}]="$rest" ;;
      ADR)  WCARD_ADRK[${#WCARD_ADRK[@]}]="${rest%%"$CARD_TAB"*}"
            WCARD_ADRV[${#WCARD_ADRV[@]}]="${rest#*"$CARD_TAB"}" ;;
    esac
  done < <(printf '%s\n' "$out")
  # THE ONE ASSIGNMENT OF THE SCALE, made before any row is spec'd: `_card_spec task`
  # reads it, and a whole card is the only caller that can know it.
  case "$WCARD_SCALE" in
    task) CARD_SCALE="task" ;;
    *)    CARD_SCALE="wave" ;;
  esac
  return 0
}

_card_adr_for() {  # <D-id> -> the ADR file name that names it, or the word none
  local i=0 n="${#WCARD_ADRK[@]}" v
  while [ "$i" -lt "$n" ]; do
    if [ "${WCARD_ADRK[$i]}" = "$1" ]; then v="${WCARD_ADRV[$i]}"; printf '%s' "${v##*/}"; return 0; fi
    i=$(( i + 1 ))
  done
  printf 'none'
}

# A fixed section's free text, folded at an indent through the SAME bionic_wrap
# the rows fold through — so a Purpose paragraph and a requirement cell break at
# the same kind of boundary and neither can exceed BIONIC_LINE_WIDTH.
_card_fold_at() {  # <indent> <text>
  local ind="${1:-4}" line
  while IFS= read -r line; do
    _card_rstrip "$(_card_spaces "$ind")${line}"; printf '\n'
  done < <(bionic_wrap "${2:-}" $(( BIONIC_LINE_WIDTH - ind )))
}

_card_pad() {  # <string> <width> -> the string padded to width IN COLUMNS
  local s="${1:-}"
  _bionic_cols_into "$s"
  printf '%s%s' "$s" "$(_card_spaces $(( ${2:-0} - BIONIC_COLS )))"
}

# THE ARTIFACTS PATH, PROJECT-ROOT-RELATIVE (epic-23 wave-15 T17; REQ-9 AC-9.4,
# audit F2 — the absolute path this used to print WHOLE was 134 columns against
# BIONIC_LINE_WIDTH=100, so the Artifacts block was exempted from the width
# check; the exemption is retired here rather than kept, because it was hiding
# a real overflow on the ordinary case, not a rare one).
#
# THIS IS A CITATION, NOT A FILESYSTEM OPERATION. It never checks the path
# exists (the caller already did, at `-f "$2"`) and it never changes what gets
# opened — a reader still opens the SAME file, spelled the way this repo's own
# docs already spell one another (`.bionic/docs/specs/…`, per-wave record files
# throughout). Only the SPELLING changes: absolute becomes root-relative when
# the artifact resolves under the project, and is left untouched otherwise.
#
# NO realpath (root.sh's own finding: absent or flagless on some targets this
# ships to). The directory half is resolved through `pwd -P`, the same idiom
# lib/binding.sh's `_bind_resolve` and lib/root.sh's own walk use — collapsing
# symlinks and `..` — and the final component is left alone, exactly as
# `_bind_resolve` does and for the same reason: only the directory needs
# canonicalising to decide whether the artifact is under the project.
#
# A PATH THAT RESOLVES OUTSIDE THE PROJECT PRINTS AS GIVEN. Folding or eliding a
# path defeats the one thing an Artifacts line is for — being opened — so the
# old exemption's rationale survives for exactly this case; the width invariant
# does not bind it. A directory that fails to resolve (already gone, an
# unreadable parent) prints the given path too, rather than guessing.
_card_artifact_rel() {  # <path as given by the caller>
  local given="${1:-}" abs d b root
  case "$given" in
    /*) abs="$given" ;;
    *)  abs="${PWD%/}/$given" ;;
  esac
  d="$(dirname "$abs")"; b="$(basename "$abs")"
  d="$(cd "$d" 2>/dev/null && pwd -P)" || { printf '%s' "$given"; return 0; }
  case "$d" in
    /) abs="/$b" ;;
    *) abs="$d/$b" ;;
  esac
  root="$(project_root "$PWD" 2>/dev/null)"
  case "$abs" in
    "$root"/*) printf '%s' "${abs#"$root"/}"; return 0 ;;
  esac
  printf '%s' "$given"
}

# THE BRANCH BLOCK, WHICH SAYS "not declared" RATHER THAN GUESSING. The three
# keys are frontmatter or they are absent; an absent branch is a real state
# (a task-scale run, a spec written before the tree existed) and the card's job
# is to show it as one, not to infer a branch from the checkout the renderer
# happens to be standing in.
_card_branches() {
  local wb="$WCARD_WB" ib="$WCARD_IB" from=""
  [ -n "$wb" ] || wb="not declared"
  [ -n "$ib" ] || ib="not declared"
  [ -n "$WCARD_BASE" ] && from="(from ${WCARD_BASE})"
  printf '  Branches\n'
  _card_rstrip "    $(_card_pad working 14)$(_card_pad "$wb" 22)${from}"; printf '\n'
  _card_rstrip "    $(_card_pad integration 14)$(_card_pad "$ib" 22)(Step 8 merges here)"; printf '\n'
}

# ── THE FLOOR, WHICH IS CONFIGURED AND NOT ASSUMED (D9, AC-4.3) ──────────────
#
# THE LINE USED TO BE A LITERAL. `floor tests/run.sh` was typed into the Verification
# line's format string, over a skill picture that says `floor <suite>` — so the card
# asserted a fact about a project it had never asked, at the one gate whose entire job
# is to be true, and it asserted the same one in a project that has no `tests/run.sh`.
# The configured answer is `impact-command:` in `.bionic/config.yaml`, which is what
# the dispatch wall (hooks/dispatch-preflight.sh:2904) and the landing gate already
# read, through the SAME `config_value` this calls — one reading of one file.
#
# UNDER THE PLAN'S ROOT, NOT THE RENDERER'S. A card is often rendered from a worktree
# or from an orchestrator standing somewhere else entirely, and the floor that governs
# a plan is the one configured where the plan LIVES.
#
# AN UNCONFIGURED ROOT PRINTS AN EM DASH, the card's own spelling for "declared
# nothing" (`_card_branches`'s "not declared", the ledger's `—`), because a floor this
# file invented is exactly the defect being closed.
_card_plan_root() {  # <plan path> -> the project root it resolves under, or ""
  local d
  d="$(dirname "${1:-.}")"
  d="$(cd "$d" 2>/dev/null && pwd -P)" || { printf ''; return 0; }
  project_root "$d" 2>/dev/null
}

_card_floor() {  # <plan path> -> the configured impact command, or an em dash
  local root floor=""
  root="$(_card_plan_root "${1:-}")"
  [ -n "$root" ] && floor="$(config_value "$root" "impact-command" "")"
  [ -n "$floor" ] || floor="—"
  printf '%s' "$floor"
}

# ── PER-BATCH WIDTH AGAINST THE RUNG (AC-3.4) ────────────────────────────────
#
# WHAT A BATCH IS: the rows at one DEPENDENCY DEPTH. Depth 0 rows depend on nothing and
# run together; a row whose deps are all depth 0 runs in batch 2; and so on. The card
# used to print ONE number — the writer budget — which says how wide the machine is and
# nothing about whether the plan can use it. A plan of twelve rows in six batches of two
# against a rung of eight is a plan that will run two at a time for six rounds, and the
# Step-3 gate is the last moment where re-threading the dependencies is cheap.
#
# THE READY COUNT COMES FROM `fill_ready_set`, NOT FROM COUNTING ROWS HERE. That library
# is the one computation of "which rows may be dispatched now" (wave-18 D2) — status,
# step cell, dependency word, scale, and the trim to the gap, all of it — and a card
# that counted its own way would be a second opinion displayed at the gate where the
# first one is being ratified. The card's number is therefore the number the tick will
# print when that batch comes up.
#
# WHICH MEANS A PROJECTION, because `fill_ready_set` answers about NOW and a batch past
# the first is a hypothesis: "when the batches before it are in, what runs together?" So
# each batch is asked of a copy of the plan with the earlier batches' rows carrying the
# terminal word their scale uses (`landed` at wave scale, `done` at task scale — ADR-033
# decision 1) and `current:` naming that batch's own step. The copy is read and deleted;
# nothing under the project is written.
#
# A ROW THAT IS ALREADY LANDED IS NOT READY, and that is deliberate: a plan mid-run
# renders the widths that are LEFT, which is what a reader of a live plan wants, and a
# plan at its Step-3 gate — every row pending — renders the widths it was planned at.
#
# NO TABLE, NO RUNG, OR NO BATCH: nothing is printed and the writer-budget line stands
# alone, exactly as before this task. A width this file could not compute is not a width
# it may guess.
_card_batch_rows() {  # <plan> -> `<batch>\t<step>\t<id>` per row, in table order
  local rows
  rows="$(units_rows "${1:-}" 2>/dev/null)" || return 1
  [ -n "$rows" ] || return 1
  printf '%s\n' "$rows" | awk -F'\t' '
    $1 == "" { next }
    { n++; id[n] = $1; stp[n] = $2; dep[n] = $6; idx[$1] = n; d[n] = 0 }
    END {
      if (n == 0) exit 1
      # RELAXATION, BOUNDED BY THE ROW COUNT, so a cyclic `deps` cell — which
      # units_validate refuses but this file may still be handed — terminates instead
      # of spinning. A dependency this table does not carry is not a depth either.
      for (pass = 1; pass <= n; pass++) {
        changed = 0
        for (i = 1; i <= n; i++) {
          s = dep[i]; gsub(/[ \t]/, "", s)
          if (s !~ /[A-Za-z0-9]/) continue
          m = split(s, a, ",")
          for (j = 1; j <= m; j++) {
            if (a[j] == "" || !(a[j] in idx)) continue
            k = idx[a[j]]
            if (k == i) continue
            if (d[k] + 1 > d[i]) { d[i] = d[k] + 1; changed = 1 }
          }
        }
        if (!changed) break
      }
      for (i = 1; i <= n; i++) print (d[i] + 1) "\t" stp[i] "\t" id[i]
    }'
}

# _card_project <plan> <ids> <terminal word> <current token> <out path>
#
# The copy described above. FENCE-AWARE and header-keyed for the same reason
# `lib/units.sh` is both: a plan documenting its own table inside a fence is prose, and
# the status column is wherever that table's header put it.
_card_project() {
  awk -v want="${2:-}" -v word="${3:-landed}" -v cur="${4:-}" '
    function trim(v) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); return v }
    # THE ESCAPE IS FOLDED BEFORE THE SPLIT AND RESTORED AFTER IT, exactly as
    # `lib/units.sh` does and for the same reason: this repo writes `\|` inside ledger
    # cells, and a raw split on `|` opens a field the header does not have — so the
    # status cell is rewritten one column left of where it is, the row stays pending,
    # and the batch width is wrong rather than absent. `unesc` rebuilds by
    # concatenation rather than through a gsub replacement, where a backslash is the
    # one character whose meaning is not the character.
    function esc(v)   { gsub(/\\[|]/, SUBSEP, v); return v }
    function unesc(v,   parts, m, i, out) {
      m = split(v, parts, SUBSEP)
      out = parts[1]
      for (i = 2; i <= m; i++) out = out "\\" "|" parts[i]
      return out
    }
    BEGIN { n = split(want, a, " "); for (i = 1; i <= n; i++) W[a[i]] = 1 }
    /^[ \t]*```/ { fence = !fence; print; next }
    fence { print; next }
    /^## / {
      insdlc  = ($0 ~ /^##[ \t]+SDLC State([ \t].*)?$/)
      intasks = ($0 ~ /^##[ \t]+[Tt]asks([ \t].*)?$/)
      print; next
    }
    insdlc && /^[ \t]*current[ \t]*:/ && !seen { print "current: " cur; seen = 1; next }
    intasks && /^[ \t]*\|/ {
      n = split(esc($0), f, "|")
      if (!hdr) {
        for (i = 1; i <= n; i++) {
          t = tolower(trim(f[i]))
          if (t == "id" && idc == 0) idc = i
          if (t == "status" && stc == 0) stc = i
        }
        if (idc > 0) hdr = 1
        print; next
      }
      if (idc > 0 && stc > 0 && idc <= n && stc <= n && (trim(f[idc]) in W)) {
        f[stc] = " " word " "
        line = f[1]
        for (i = 2; i <= n; i++) line = line "|" f[i]
        print unesc(line); next
      }
      print; next
    }
    { print }
    END {
      # A plan with no `## SDLC State` section has no `current:` to project onto, and a
      # ledger with no current is not live — so the section is appended rather than the
      # batch silently reading zero.
      if (!seen) { print ""; print "## SDLC State"; print ""; print "current: " cur }
    }' "${1:-}" > "${5:-/dev/null}"
}

_card_batch_widths() {  # <plan> <rung> <scale> -> one `batch <k> · <n> of <rung>` per batch
  local plan="${1:-}" rung="${2:-}" scale="${3:-wave}" rows maxk k prior steps step
  local word tmpd proj idsf n token
  case "$rung" in ''|*[!0-9]*) return 1 ;; esac
  [ "$rung" -gt 0 ] || return 1
  rows="$(_card_batch_rows "$plan")" || return 1
  [ -n "$rows" ] || return 1
  maxk="$(printf '%s\n' "$rows" | awk -F'\t' 'BEGIN { m = 0 } $1 + 0 > m { m = $1 + 0 } END { print m + 0 }')"
  [ "$maxk" -gt 0 ] || return 1
  word="landed"
  if [ "$scale" = "task" ]; then
    word="done"
    # THE TASK-SCALE TOKEN NAMES A UNIT, NOT A NUMBER (`current: T<n>`), and
    # `units_ready`'s task arm reads its SHAPE rather than its number: which unit the
    # run is on does not change which rows are dispatchable. The plan's own field is
    # used when it carries one, so the projection differs from the artifact in the one
    # thing it is supposed to differ in.
    token="$(_fill_current_field "$plan")"
    case "$token" in
      T*) case "${token#T}" in ''|*[!0-9]*) token="T1" ;; esac ;;
      *) token="T1" ;;
    esac
  fi
  tmpd="$(mktemp -d "${TMPDIR:-/tmp}/card-batch.XXXXXX")" || return 1
  proj="${tmpd}/plan.md"
  idsf="${tmpd}/ids"
  k=1
  while [ "$k" -le "$maxk" ]; do
    prior="$(printf '%s\n' "$rows" | awk -F'\t' -v k="$k" '$1 + 0 < k { printf "%s ", $3 }')"
    : > "$idsf"
    if [ "$scale" = "task" ]; then
      _card_project "$plan" "$prior" "$word" "$token" "$proj"
      fill_ready_set "$proj" "$rung" 0 >> "$idsf"
    else
      # THE STEP CELLS THIS BATCH HOLDS. A wave batch is normally one step, but a
      # Step-5 row depending on every Step-4 row sits in its own batch at its own
      # step, so the token is asked per distinct step rather than once for the plan.
      steps="$(printf '%s\n' "$rows" | awk -F'\t' -v k="$k" '$1 + 0 == k && $2 != "" { print $2 }' | sort -u)"
      for step in $steps; do
        _card_project "$plan" "$prior" "$word" "$step" "$proj"
        fill_ready_set "$proj" "$rung" 0 >> "$idsf"
      done
    fi
    # DISTINCT IDS, counted with a counter rather than `length(array)`: this platform's
    # awk is the 2007 one-true-awk and does not answer that for an array.
    n="$(awk 'NF && !($1 in seen) { seen[$1] = 1; c++ } END { print c + 0 }' "$idsf")"
    [ "$n" -le "$rung" ] || n="$rung"
    printf '    batch %s · %s of %s\n' "$k" "$n" "$rung"
    k=$(( k + 1 ))
  done
  rm -rf "$tmpd"
  return 0
}

_card_step1() {  # <artifact path>
  printf 'Step 1 · Requirements\n\n  Purpose\n'
  _card_fold_at 4 "$WCARD_GOAL"
  printf '\n'
  _card_branches
  printf '\n'
  CARD_ROWS=( ${WCARD_RROW[@]+"${WCARD_RROW[@]}"} )
  _card_render_batch requirement
  printf '\n  Not Doing\n'
  local b
  for b in ${WCARD_ND[@]+"${WCARD_ND[@]}"}; do _card_fold_at 4 "$b"; done
  printf '\n  Artifacts\n    requirements  %s\n\n' "$1"
  printf 'Do you approve these requirements? Reply "approved" to approve it.\n'
  printf 'explain <requirement>\n'
}

# THE TASK-SCALE STEP-2 CARD IS A PARAGRAPH, BECAUSE THE DESIGN IS ONE (D8). A wave
# design is a document with decisions, an ownership table and an eval-design table, and
# the card renders those three batches. A task run writes "a design paragraph per
# non-trivial task, in the session plan — a prose obligation the reviewer reads, with no
# wall at task scale at all" (steps/2.md:60), so there are no decisions to tabulate and
# no eval design to count: the card shows the paragraph, names the artifact, and asks
# its question. It does NOT offer `show evals` or `explain <decision>`, because a card
# that offers an affordance over content it is not carrying is the same lying surface
# the floor line was.
_card_step2_task() {  # <citation path>
  local d="$WCARD_DESIGN"
  [ -n "$d" ] || d="$WCARD_GOAL"
  printf 'Step 2 · Design\n\n'
  _card_branches
  printf '\n  Design\n'
  _card_fold_at 4 "$d"
  printf '\n  Artifacts\n    plan  %s\n' "$1"
  printf '\nDo you approve this design? Reply "approved" to approve it.\n'
}

_card_step2() {  # <artifact path>
  if [ "$CARD_SCALE" = "task" ]; then _card_step2_task "$1"; return 0; fi
  printf 'Step 2 · Design\n\n'
  _card_branches
  printf '\n'
  CARD_ROWS=()
  local r
  for r in ${WCARD_DROW[@]+"${WCARD_DROW[@]}"}; do
    CARD_ROWS[${#CARD_ROWS[@]}]="${r}${CARD_TAB}$(_card_adr_for "${r%%"$CARD_TAB"*}")"
  done
  _card_render_batch decision
  printf '\n'
  CARD_ROWS=( ${WCARD_OROW[@]+"${WCARD_OROW[@]}"} )
  _card_render_batch ownership
  printf '\n'
  CARD_ROWS=( ${WCARD_EROW[@]+"${WCARD_EROW[@]}"} )
  _card_render_batch eval-design
  printf '\n  Artifacts\n    spec  %s\n' "$1"
  [ -n "$WCARD_ADRS" ] && printf '    adrs  %s\n' "$WCARD_ADRS"
  printf '\nDo you approve this design? Reply "approved" to approve it.\n'
  printf 'show evals <req> · explain <decision>\n'
}

# TWO PATHS, AND THEY ARE NOT THE SAME PATH. `$1` is the CITATION — the
# project-root-relative spelling the Artifacts block prints — and `$2` is the path as
# the caller gave it, which is what the floor and the batch widths must be read from:
# a citation is for a reader to open, and `.bionic/docs/plans/…` resolves against the
# renderer's own cwd rather than against the plan.
_card_step3() {  # <citation path> <artifact path as given>
  printf 'Step 3 · Plan\n\n  Problem\n'
  _card_fold_at 4 "$WCARD_GOAL"
  printf '\n'
  _card_branches
  printf '\n'
  CARD_ROWS=( ${WCARD_TROW[@]+"${WCARD_TROW[@]}"} )
  _card_render_batch task
  local w="$WCARD_WRITERS" fb="$WCARD_FIRSTB"
  [ -n "$w" ] || w="not declared"
  [ -n "$fb" ] || fb="not declared"
  printf '\n  Parallel width\n    %s writers · first batch %s\n' "$w" "$fb"
  _card_batch_widths "$2" "$WCARD_WRITERS" "$CARD_SCALE" || :
  printf '\n  Eval design\n    %s criteria · %s static · %s unit · %s hermetic · %s live · %s human\n' \
    "$WCARD_MROWS" "$WCARD_T0" "$WCARD_T1" "$WCARD_T2" "$WCARD_T3" "$WCARD_T4"
  printf '\n  Verification\n    %s matrix rows · floor %s · walk %s · auditor %s\n' \
    "$WCARD_MROWS" "$(_card_floor "$2")" "${WCARD_WALK:-not declared}" "${WCARD_RIGOR:-not declared}"
  printf '\n  Artifacts\n    plan  %s\n\n' "$1"
  printf 'Do you approve this plan? Reply "approved" to approve it.\n'
  printf 'show evals <req> · show task <n> · explain <decision>\n'
}

# ── ONE BATCH, RENDERED ──────────────────────────────────────────────────────
#
# EVERY ROW IS READ BEFORE ANY ROW IS RENDERED (AC-9.5). A batch's per-column
# widths cannot be known until the LAST row has been seen, so the first row
# cannot be padded — or its header labelled — until then either. Both callers
# (the TSV verb and the three whole-card verbs) come through here, which is what
# makes AC-10.3's byte-identity structural rather than a coincidence two code
# paths have to keep agreeing on.
_card_render_batch() {  # <kind> — renders CARD_ROWS[], already set
  _card_spec "$1" || return 1
  _card_compute_batch_widths
  _card_header
  local _row _i
  for _row in ${CARD_ROWS[@]+"${CARD_ROWS[@]}"}; do
    _card_split "$_row"
    _card_a=()
    _i=0
    while [ "$_i" -lt "$CARD_NF_1" ]; do _card_a[$_i]="${CARD_CELLS[$_i]:-}"; _i=$(( _i + 1 )); done
    _card_emit "$CARD_FMT_1" "$CARD_FOLD_1" "1" "${_card_a[@]}"
    if [ "$CARD_LINES" -gt 1 ]; then
      _card_b=()
      _i=0
      while [ "$_i" -lt "$CARD_NF_2" ]; do
        _card_b[$_i]="${CARD_CELLS[$(( CARD_NF_1 + _i ))]:-}"; _i=$(( _i + 1 ))
      done
      _card_emit "$CARD_FMT_2" "$CARD_FOLD_2" "2" "${_card_b[@]}"
    fi
  done
  return 0
}

# ── THE COMMAND LINE ─────────────────────────────────────────────────────────
[ "$#" -ge 1 ] || _card_usage "no row kind"

case "$1" in
  step1|step2|step3)
    [ "$#" -eq 2 ] || _card_usage "$1 takes exactly one artifact path (got $(( $# - 1 )))"
    [ -f "$2" ] && [ -r "$2" ] || _card_usage "$1: no readable artifact at '$2'"
    _card_load "$1" "$2" || _card_usage "$2: ${WCARD_ERR}"
    _card_art="$(_card_artifact_rel "$2")"
    case "$1" in
      step1) _card_step1 "$_card_art" ;;
      step2) _card_step2 "$_card_art" ;;
      step3) _card_step3 "$_card_art" "$2" ;;
    esac
    exit 0 ;;
esac

[ "$#" -le 1 ] || _card_usage "one row kind at a time (got $#)"
_card_spec "$1" || _card_usage "unknown row kind '$1'"

CARD_ROWS=()
while IFS= read -r _card_row || [ -n "${_card_row:-}" ]; do
  [ -n "$_card_row" ] || continue
  CARD_ROWS[${#CARD_ROWS[@]}]="$_card_row"
done

_card_render_batch "$1"

exit 0
