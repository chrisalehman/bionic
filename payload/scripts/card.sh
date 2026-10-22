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
#     bash card.sh <step0|step1|step2|step3> <artifact> (the whole card; no stdin)
#     bash card.sh rigor <word>                         (a rigor level, printed with its meaning)
#     bash card.sh regression <scale> [<plan>]          (the regression line the Step-0 card prints)
#     bash card.sh inherited <requirements file>       (the inherited deferrals, tagged; close-out's)
#     bash card.sh inherited-debt <requirements file>  (its open debt: lines, which inherited withholds; close-out's)
#     bash card.sh early <plan>                         (the CARD-EARLY line, or what the release approval card settles)
#     bash card.sh release                 < facts      (the release approval card, from the facts its verb gathers)
#     bash card.sh sitrep <sheet>          < judgment   (the sitrep card, from the sheet and the model's judgment)
#     bash card.sh sitrep-check <sheet>    < card       (the sitrep card's check alone, over a card drawn elsewhere)
#     bash card.sh fold                    < lines      (each `<hang> TAB <text>` folded at the shared width)
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
# `.bionic/config.yaml`, so the regression line names what the dispatch wall and the landing
# gate name; `fill.sh` owns the ONE computation of "which rows may run now", so a
# per-batch width on the approval card is the same answer the tick will give when the
# batch comes up. Neither is re-implemented here: a card that counted rows its own way
# would be a second opinion at the gate where the first one is being ratified.
# shellcheck source=/dev/null
. "${CARD_SELF_DIR}/lib/roots.sh"
# shellcheck source=/dev/null
. "${CARD_SELF_DIR}/lib/fill.sh"
# THE ONE READING OF A RIGOR WORD (wave-28 T44; wave-30 T11, D1). A card prints a level with its
# meaning, `rigor_print`; a word that is no level is printed as such, never read as one.
# And `budget_cap`, the one reader of a person's writer cap (wave-28 T9; D15).
# shellcheck source=/dev/null
. "${CARD_SELF_DIR}/lib/run.sh"
# The integration branch is lib/plan.sh `plan_integration_branch`'s answer, the reader close-out and the gate ask too.
# shellcheck source=/dev/null
. "${CARD_SELF_DIR}/lib/plan.sh"
# THE ONE DEBT-LINE GRAMMAR (wave-36 T13; D13, AC-7.8): a carried `debt:` line is read by `DEBT_LINE_ERE`,
# the regex `debt add` holds each line to and close-out carries by, never a third copy of it here.
# shellcheck source=/dev/null
. "${CARD_SELF_DIR}/lib/debt.sh"
# THE SCALE PROFILE (wave-38 T16; D25): the Step 0 regression line's default is the scale's regression cell.
# shellcheck source=/dev/null
. "${CARD_SELF_DIR}/lib/scale.sh"

# THE SCALE, WHICH IS A PROPERTY OF THE ARTIFACT AND NOT OF THE ROW KIND (D8). The scales
# differ in their artifacts and never in the `## Tasks` ledger (wave-31 T5, D2): a task-scale
# run writes its design as a paragraph in its plan, so the Step-2 card reads it there. The
# whole-card verbs set this from the artifact's own `scale:` frontmatter; a hand-fed TSV row
# leaves it at `wave`.
CARD_SCALE="wave"

_card_usage() {  # <message>
  printf 'card.sh: %s — usage: card.sh <requirement|decision|ownership|eval-design|task> with TSV rows on stdin, or card.sh <step0|step1|step2|step3> <artifact>, or card.sh <inherited|inherited-debt> <requirements file>, or card.sh release with its facts on stdin, or card.sh <sitrep|sitrep-check> <sheet file> with the judgment or the card on stdin, or card.sh fold with its lines on stdin\n' \
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
    ownership-reuses)
      # The ownership row, then a second line for the reuses cell (wave-27 D8): the format of
      # line 1 is `ownership`'s own, so the two kinds never disagree about a column.
      _card_spec ownership || return 1
      CARD_LINES=2; CARD_FMT_2='    reuses %s'; CARD_NF_2=1; CARD_FOLD_2=0 ;;
    eval-design)
      CARD_SECTION="Eval design"
      CARD_HDRCOLS="2:static 3:unit 4:hermetic 5:live 6:human"
      CARD_FMT_1='    %-8s %-36s %6s %5s %9s %5s %6s';  CARD_NF_1=7; CARD_FOLD_1=1 ;;
    task)
      CARD_SECTION="Tasks"
      CARD_HDRCOLS="2:kind 3:depends 4:agent"
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
# `payload/scripts/lib/proof.sh` against the ownership format's 14-column `owner`
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
    # THE LABEL PRINTS ONCE (wave-26 D13). The spec writes `**D1 — title**` and the row has an
    # id column of its own, so the leading `D<n> —` is the same word twice; it comes off here,
    # before the first sentence is taken, and a text that carries no label is left alone.
    line = clean(line)
    sub(/^D[0-9]+[ \t]*(—|--|-|:)[ \t]*/, "", line)
    print "DROW" OFS id OFS clean(firstsent(line)) OFS clean(serves)
    return
  }
  # AN UNTAGGED BULLET IS THE ARTIFACT\047S DEFECT (wave-35 T8; REQ-6 AC-6.6; D15): the section parses one
  # shape, and a bullet out of it was dropped in silence, so a spec of untagged decisions rendered an empty
  # Decisions table at exit 0. Refused as a requirement with no provenance is, naming the bullet.
  gsub(/\*\*/, "", line)
  err("decision bullet carries no (D<n>; REQ-…) tag: " words(clean(line), 10))
}
# words(s, n) -> the first n blank-separated words of s, re-joined by one space.
function words(s, n,   a, m, k, o) {
  m = split(s, a, /[ \t]+/); o = ""
  for (k = 1; k <= m && k <= n; k++) o = o (o == "" ? "" : " ") a[k]
  return o
}
# A `Worth your eye` bullet: one entry, its continuation lines joined, markup off.
function flush_worth(   t) {
  if (wbuf == "") return
  t = wbuf; wbuf = ""
  gsub(/\*\*/, "", t)
  print "WORTH" OFS clean(t)
}
function flush_adr(   line, path, rest, id) {
  if (abuf == "") return
  line = abuf; abuf = ""
  if (!match(line, /`[^`]*adr-[^`]*`/)) return
  path = substr(line, RSTART + 1, RLENGTH - 2)
  rest = line
  # AN ADR LINE CARRIES ITS GROUP (wave-35 T8; AC-6.6): a backticked adr- path with no (D<n>) group beside it
  # names an ADR no decision cites, and the ADR column would leave it out in silence.
  if (rest !~ /\(D[0-9]+[^)]*\)/) { err("ADR line names " path " with no (D<n>) group"); return }
  # EVERY DECISION A GROUP NAMES IS CREDITED (wave-43 D11; AC-13.2): `(D3; D4; REQ-2)` records the ADR
  # against D3 and D4 both. Reading the first id alone left the cell of D4 as none beside the ADR that records it.
  while (match(rest, /\(D[0-9]+[^)]*\)/)) {
    gs = RSTART; gl = RLENGTH
    grp = substr(rest, gs + 1, gl - 2)
    while (match(grp, /D[0-9]+/)) {
      print "ADR" OFS substr(grp, RSTART, RLENGTH) OFS path
      grp = substr(grp, RSTART + RLENGTH)
    }
    rest = substr(rest, gs + gl)
  }
}
function flush_all() { flush_nd(); flush_req(); flush_dec(); flush_adr(); flush_worth() }
BEGIN { OFS = "\t"; ERRMSG = ""; mrows = 0; enum = 0 }
NR == 1 && $0 == "---" { fm = 1; next }
fm == 1 && $0 == "---" { fm = 0; next }
fm == 1 {
  k = $0; sub(/:.*$/, "", k); v = $0; sub(/^[^:]*:[ \t]*/, "", v)
  if (k == "scale") SCALE = v
  else if (k == "base-sha") BASE = v
  else if (k == "rigor") RIGOR = v
  else if (k == "walk") WALK = v
  else if (k == "adrs") ADRS = v
  else if (k == "design-ledger") LEDGER = v
  else if (k == "requirements") REQSF = v
  else if (k == "spec") SPECF = v
  else if (k == "design") DPTR = v
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
  else if (h ~ /^Approach[ \t]*$/) sub2 = "approach"
  else if (h ~ /^Worth your eye[ \t]*$/) sub2 = "worth"
  else sub2 = ""
  next
}
sec == "goal" && goaldone != 1 {
  if (trim($0) == "") { if (GOAL != "") goaldone = 1 }
  else GOAL = GOAL (GOAL == "" ? "" : " ") clean($0)
  next
}
# THE APPROACH AND WORTH YOUR EYE (wave-26 D13). Both are `###` sections of `## Design`; they
# are read BEFORE the design-paragraph arm below, which would otherwise take an Approach
# that happens to be the first text under the heading for the design paragraph.
sub2 == "approach" {
  if (trim($0) != "") APPROACH = APPROACH (APPROACH == "" ? "" : " ") clean($0)
  next
}
sub2 == "worth" {
  # ANY NON-BLANK LINE CONTINUES THE OPEN BULLET, indented or not: Markdown reads an
  # unindented line under a list item as part of it, and the card must not drop it (review-3 F3).
  if (/^- /) { flush_worth(); wbuf = substr($0, 3) }
  else if (trim($0) != "" && wbuf != "") wbuf = wbuf " " trim($0)
  else if (trim($0) == "") flush_worth()
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
  # THE SERVES COLUMN IS FOUND BY ITS HEADER, because a `reads` or `base` column may sit before
  # it; the eighth cell is the fallback for a header that does not name it.
  if (trow == 1) { n = cells($0, c); servc = 8; for (i = 1; i <= n; i++) if (tolower(c[i]) == "serves") servc = i }
  if (trow <= 2) next
  n = cells($0, c)
  if (n < 6) next
  # EACH TASK WITH THE CRITERIA IT SERVES (wave-26 D12). The serves cell joins the first
  # sentence as one folding stream, the way the requirement row joins its provenance, so the
  # row kind and its widths are unchanged and a hand-fed row builds the same string.
  t = clean(firstsent(c[4]))
  sv = (servc <= n) ? c[servc] : ""
  if (sv ~ /[A-Za-z0-9]/) t = t " · serves " sv
  print "TROW" OFS c[1] OFS t OFS c[3] OFS c[6] OFS c[5]
  next
}
sec == "eval" && /^[ \t]*\|/ {
  erow++
  if (erow <= 2) next
  n = cells($0, c)
  if (n < 4) next
  r = c[1]
  ncrit++; crow[ncrit] = r OFS c[3] OFS c[4] OFS c[5] OFS c[6]
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
  # THE REUSES COLUMN (wave-27 D8): a header whose third cell reads `reuses` makes a five-cell
  # table, `concept | owner | reuses | surfaces | test`. Its row goes out as the four cells every
  # table has always sent, then the reuses cell fifth; a table without the column is untouched.
  if (orow == 1) { n = cells($0, c); own5 = (n >= 5 && tolower(trim(c[3])) == "reuses"); next }
  if (orow == 2) next
  n = cells($0, c)
  if (own5) { if (n >= 5) print "OROW" OFS c[1] OFS c[2] OFS c[4] OFS c[5] OFS c[3]; next }
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
  print "META" OFS "base" OFS BASE
  print "META" OFS "rigor" OFS RIGOR
  print "META" OFS "walk" OFS WALK
  print "META" OFS "scale" OFS SCALE
  print "META" OFS "design" OFS DESIGN
  print "META" OFS "adrs" OFS ADRS
  print "META" OFS "ledger" OFS LEDGER
  print "META" OFS "reqs" OFS REQSF
  print "META" OFS "approach" OFS APPROACH
  print "META" OFS "mrows" OFS mrows
  print "META" OFS "spec" OFS SPECF
  print "META" OFS "dptr" OFS DPTR
  for (i = 1; i <= ncrit; i++) print "CROW" OFS crow[i]
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
  WCARD_WRITERS=""; WCARD_MROWS="0"
  WCARD_LEDGER=""; WCARD_REQS=""; WCARD_APPROACH=""; WCARD_WORTH=(); WCARD_CROW=()
  WCARD_SPEC=""; WCARD_DPTR=""
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
          base) WCARD_BASE="$v" ;;       rigor) WCARD_RIGOR="$v" ;;
          walk) WCARD_WALK="$v" ;;       adrs) WCARD_ADRS="$v" ;;
          ledger) WCARD_LEDGER="$v" ;;   reqs) WCARD_REQS="$v" ;;
          approach) WCARD_APPROACH="$v" ;;
          scale) WCARD_SCALE="$v" ;;     design) WCARD_DESIGN="$v" ;;
          mrows) WCARD_MROWS="$v" ;;
          spec) WCARD_SPEC="$v" ;;       dptr) WCARD_DPTR="$v" ;;
        esac ;;
      ND)   WCARD_ND[${#WCARD_ND[@]}]="$rest" ;;
      WORTH) WCARD_WORTH[${#WCARD_WORTH[@]}]="$rest" ;;
      CROW) WCARD_CROW[${#WCARD_CROW[@]}]="$rest" ;;
      RROW) WCARD_RROW[${#WCARD_RROW[@]}]="$rest" ;;
      DROW) WCARD_DROW[${#WCARD_DROW[@]}]="$rest" ;;
      OROW) WCARD_OROW[${#WCARD_OROW[@]}]="$rest" ;;
      EROW) WCARD_EROW[${#WCARD_EROW[@]}]="$rest" ;;
      TROW) WCARD_TROW[${#WCARD_TROW[@]}]="$rest" ;;
      ADR)  WCARD_ADRK[${#WCARD_ADRK[@]}]="${rest%%"$CARD_TAB"*}"
            WCARD_ADRV[${#WCARD_ADRV[@]}]="${rest#*"$CARD_TAB"}" ;;
    esac
  done < <(printf '%s\n' "$out")
  # THE WRITERS ARE A PERSON'S CAP, READ BY FIELD (wave-28 T9; D15): `budget_cap` (lib/run.sh)
  # answers from a `parallel-budget:` line whose `source=` is `user` or `override`, one whole
  # `writers=` field. The card's own awk used to cut the first SUBSTRING `writers=`, so
  # `max_writers=9 writers=3` read 9 here and 3 to every other reader, and it took a probe's
  # number for a ceiling. With no cap the card says the writers are not declared.
  WCARD_WRITERS="$(budget_cap "$2")"; WCARD_WRITERS="${WCARD_WRITERS#writers=}"
  # THE WORKING BRANCH IS THE ANSWER OF lib/run.sh `plan_working_branch` (wave-35 T7; D14), the reader `ready`,
  # the walls and the judge ask: SDLC State, then frontmatter. The card used to read the frontmatter alone,
  # so a plan naming its branch under SDLC State showed `not declared` for a branch `ready` lands on.
  WCARD_WB="$(plan_working_branch "$2")"
  WCARD_IB="$(plan_integration_branch "$2")"
  # THE ONE ASSIGNMENT OF THE SCALE: the Step-2 card's artifact arms read it, and a whole
  # card is the only caller that can know it.
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

# THE BRANCH BLOCK, WHICH SAYS "not declared" RATHER THAN GUESSING. The two
# branches are the plan readers' answers and the base its frontmatter, or they are absent; an absent branch is a real state
# (a task-scale run, a spec written before the tree existed) and the card's job
# is to show it as one, not to infer a branch from the checkout the renderer
# happens to be standing in.
_card_branches() {  # [<indent of the heading, 2 by default>]
  local wb="$WCARD_WB" ib="$WCARD_IB" from="" ind="${1:-2}"
  [ -n "$wb" ] || wb="not declared"
  [ -n "$ib" ] || ib="not declared"
  [ -n "$WCARD_BASE" ] && from="(from ${WCARD_BASE})"
  printf '%sBranches\n' "$(_card_spaces "$ind")"
  ind="$(_card_spaces $(( ind + 2 )))"
  _card_rstrip "${ind}$(_card_pad working 14)$(_card_pad "$wb" 22)${from}"; printf '\n'
  _card_rstrip "${ind}$(_card_pad integration 14)$(_card_pad "$ib" 22)(Step 8 merges here)"; printf '\n'
}

# ── THE REGRESSION LINE PRINTS THE PLAN'S VALUE (D4, AC-12.1; wave-31 T2, T28) ─────────────
#
# THE LINE USED TO BE A LITERAL. `floor tests/run.sh` was typed into the Verification
# line's format string, so the card asserted a fact about a project it had never asked.
# Through 1.14.0 it printed the map's configured command; the file-to-suite map is deleted
# (REQ-4 AC-4.2), and the line printed an em dash. Since wave-31 T28 the line prints the
# plan's own `regression:` key, `yes` or `no`, as Step 0 wrote it with
# `session-poker.sh regression`; a plan that declares no key prints `not declared`, the
# spelling the walk and rigor lines use. The Step 0 card's line is `card.sh regression`.
#
# `_card_plan_root` resolves a plan to its project root, UNDER THE PLAN'S ROOT, NOT THE
# RENDERER'S: a card is often rendered from a worktree or from an orchestrator standing
# somewhere else entirely.
_card_plan_root() {  # <plan path> -> the project root it resolves under, or ""
  local d
  d="$(dirname "${1:-.}")"
  d="$(cd "$d" 2>/dev/null && pwd -P)" || { printf ''; return 0; }
  project_root "$d" 2>/dev/null
}

_card_floor() {  # [<plan path>] -> the plan's regression: value, or "not declared" (the name keeps the
  # word floor, an identifier, wave-30 T23)
  local v
  v="$(plan_regression "${1:-}")"
  printf '%s' "${v:-not declared}"
}

# THE STEP 0 CARD'S REGRESSION LINE (D4, AC-12.1). `card.sh regression <scale> [<plan>]` prints one line:
# the scale's default, its regression cell in lib/scale.sh (wave-38 T16, D25), marked `(scale default)`; or, when the plan carries a
# `regression-override:` line, the plan's own `regression:` value marked `(overridden)`. The override line
# is presence-only: its fields are never parsed. An absent key, or any value but the exact `no`, reads
# `yes`, as walls.sh and proof.sh read it (T27, A-T27-2).
_card_regression_line() {  # <scale> [<plan>] -> the line; returns 1 on a word that is no scale
  local scale="$1" plan="${2:-}" d v
  d="$(scale_cell "$scale" regression 2>/dev/null)" || return 1
  if [ -n "$(plan_frontmatter_get "$plan" regression-override)" ]; then
    v="$(plan_regression "$plan")"
    [ "$v" = "no" ] || v=yes
    printf 'regression %s  (overridden)\n' "$v"
  else
    printf 'regression %s  (scale default)\n' "$d"
  fi
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
# terminal word `landed` and `current:` naming the batch's highest step (never below 4). The copy is
# read and deleted; nothing under the project is written.
#
# A ROW THAT IS ALREADY LANDED IS NOT READY, and that is deliberate: a plan mid-run
# renders the widths that are LEFT, which is what a reader of a live plan wants, and a
# plan at its Step-3 gate — every row pending — renders the widths it was planned at.
#
# NO TABLE, NO RUNG, OR NO BATCH: no batch line is printed and the lines above it stand
# alone. A width this file could not compute is not a width it may guess.
#
# THE DEPTH IS READ OFF THE DERIVED GRAPH (wave-26 D12): `units_edges`, the edges the tick
# itself waits on — a read of what another row writes as much as a deps id — so the batches
# and the chain below are one graph, not a second walk over the deps cell.
_card_batch_rows() {  # <plan> -> `<batch>\t<step>\t<id>` per row, in table order
  local rows edges
  rows="$(units_rows "${1:-}" 2>/dev/null)" || return 1
  [ -n "$rows" ] || return 1
  edges="$(units_edges "${1:-}" 2>/dev/null)" || edges=""
  { printf '%s\n' "$rows" | awk -F'\t' '$1 != "" { print "N\t" $1 "\t" $2 }'
    printf '%s\n' "$edges" | awk -F'\t' 'NF >= 2 && $1 != "" { print "E\t" $1 "\t" $2 }'
  } | awk -F'\t' '
    $1 == "N" { n++; id[n] = $2; stp[n] = $3; idx[$2] = n; d[n] = 0; next }
    $1 == "E" { ne++; ef[ne] = $2; et[ne] = $3; next }
    END {
      if (n == 0) exit 1
      # RELAXATION, BOUNDED BY THE ROW COUNT, so a cycle — which units_validate refuses but
      # this file may still be handed — terminates instead of spinning.
      for (pass = 1; pass <= n; pass++) {
        changed = 0
        for (e = 1; e <= ne; e++) {
          if (!(ef[e] in idx) || !(et[e] in idx)) continue
          k = idx[ef[e]]; i = idx[et[e]]
          if (k != i && d[k] + 1 > d[i]) { d[i] = d[k] + 1; changed = 1 }
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
    # THE PROJECTION IS OF AN APPROVED PLAN. The card is shown at the approval gate, and a
    # table with a `reads` column reads `approval:plan` by default, so an unapproved copy would
    # answer every batch with nothing. A second `approved-by:` beside a real one changes nothing.
    insdlc && /^[ \t]*current[ \t]*:/ && !seen {
      print "current: " cur; print "approved-by: projection"; seen = 1; next
    }
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
      if (!seen) { print ""; print "## SDLC State"; print ""; print "current: " cur; print "approved-by: projection" }
    }' "${1:-}" > "${5:-/dev/null}"
  # THE PROJECTION PATH IS REWRITTEN PER BATCH with a different `current:`, and fill.sh
  # memoises that field per process by path — so the writer forgets it (wave-19 critic C2).
  fill_current_forget
}

_card_batch_widths() {  # <plan> <rung> -> one `batch <k> · <n> of <rung>` per batch
  local plan="${1:-}" rung="${2:-}" rows maxk k prior step
  local tmpd proj idsf n
  case "$rung" in ''|*[!0-9]*) return 1 ;; esac
  [ "$rung" -gt 0 ] || return 1
  rows="$(_card_batch_rows "$plan")" || return 1
  [ -n "$rows" ] || return 1
  maxk="$(printf '%s\n' "$rows" | awk -F'\t' 'BEGIN { m = 0 } $1 + 0 > m { m = $1 + 0 } END { print m + 0 }')"
  [ "$maxk" -gt 0 ] || return 1
  tmpd="$(mktemp -d "${TMPDIR:-/tmp}/card-batch.XXXXXX")" || return 1
  proj="${tmpd}/plan.md"
  idsf="${tmpd}/ids"
  k=1
  while [ "$k" -le "$maxk" ]; do
    prior="$(printf '%s\n' "$rows" | awk -F'\t' -v k="$k" '$1 + 0 < k { printf "%s ", $3 }')"
    : > "$idsf"
    # ONE PROJECTION PER BATCH, AT THE STEP THE RUN WILL BE ON WHEN IT COMES UP (wave-20
    # REQ-5, Δ1, Δ6). Readiness is the prerequisite graph, so a work row in batch k is
    # ready at any step once batches 1..k-1 have landed, and the per-step loop this
    # replaced asked the same set once per step it held. What the step still decides is
    # the gate acts: an `integrate` or `close` row waits for `current:` to reach its own
    # step, so the batch is asked at its HIGHEST step cell — every gate act in it is then
    # reached — and never below 4, where nothing fills (the tick never runs a batch there).
    step="$(printf '%s\n' "$rows" | awk -F'\t' -v k="$k" '
      BEGIN { m = 4 }
      $1 + 0 == k && $2 ~ /^[0-9]+$/ && $2 + 0 > m { m = $2 + 0 }
      END { print m }')"
    _card_project "$plan" "$prior" landed "$step" "$proj"
    fill_ready_set "$proj" "$rung" 0 >> "$idsf"
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

# ── THE LONGEST CHAIN AND THE PEAK WIDTH (wave-26 D12, AC-7.1) ───────────────
#
# Both are `units_chain`'s answer over the plan's derived graph: the open rows (pending or
# active) are the nodes, weighted by their `size` minutes, and `units_edges` is the edges — the
# same graph the tick schedules from. A size cell that is not a number of minutes counts 0
# (`30m` counts 30), because a row the planner did not size still sits on the graph.
#
# Sets CARD_CHAIN (ids joined by commas), CARD_CHAIN_MIN, CARD_PEAK and CARD_EDGES (the
# `units_edges` lines, kept for the depends column); returns 1 with the library's own message
# in CARD_CHAIN_ERR when it refuses (a cycle, say).
#
# THE ANSWER IS SPLIT BY PARAMETER EXPANSION, NOT `IFS=<TAB> read` (review 9 F1). A tab is IFS
# whitespace, so `read` folds a run of tabs into one delimiter, and the empty chain's
# `chain<TAB><TAB>0` put the minutes in the ids field: `no open task` could never print.
_card_chain() {  # <plan> <writer ceiling>
  local rows out line rest
  CARD_CHAIN=""; CARD_CHAIN_MIN=0; CARD_PEAK=0; CARD_CHAIN_ERR=""
  rows="$(units_rows "${1:-}" 2>/dev/null)" || rows=""
  CARD_EDGES="$(units_edges "${1:-}" 2>/dev/null)" || CARD_EDGES=""
  out="$( { printf '%s\n' "$rows" | awk -F'\t' '
              $1 != "" && ($10 == "pending" || $10 == "active") {
                m = 0; if (match($7, /^[0-9]+/)) m = substr($7, 1, RLENGTH) + 0
                print "N\t" $1 "\t" m
              }'
            printf '%s\n' "$CARD_EDGES" | awk -F'\t' 'NF >= 2 && $1 != "" && !(($1, $2) in seen) {
                seen[$1, $2] = 1; print "E\t" $1 "\t" $2 }'
          } | units_chain "${2:-1}" 2>&1 )" || { CARD_CHAIN_ERR="${out#units_chain: }"; return 1; }
  while IFS= read -r line; do
    rest="${line#*"$CARD_TAB"}"
    case "$line" in
      chain"$CARD_TAB"*)
        CARD_CHAIN="${rest%%"$CARD_TAB"*}"
        case "$rest" in *"$CARD_TAB"*) CARD_CHAIN_MIN="${rest#*"$CARD_TAB"}" ;; esac ;;
      width"$CARD_TAB"*) CARD_PEAK="${rest:-0}" ;;
    esac
  done < <(printf '%s\n' "$out")
  [ -n "$CARD_CHAIN_MIN" ] || CARD_CHAIN_MIN=0
  return 0
}

# THE DEPENDS COLUMN OF A TABLE WITH A `reads` COLUMN (review 9, answer (b)). There the deps cell
# holds only `ext:` tokens, because a row waits on what it reads, so the cell alone shows a dash
# for a row that waits on another through a read. Each task row's depends becomes the ids
# `units_edges` puts before it (the edges `_card_chain` already fetched), once each and in table
# order, then the deps cell's `ext:` tokens; a row with neither keeps a dash. The edges join open
# rows only, so a predecessor that has landed no longer shows: what remains is what it waits for.
# A deps-only table is left as the plan wrote it.
_card_reads_depends() {  # <plan> — rewrites field 4 of every WCARD_TROW entry
  local out line
  units_has_column "${1:-}" reads || return 0
  [ "${#WCARD_TROW[@]}" -gt 0 ] || return 0
  out="$( { printf '%s\n' "${CARD_EDGES:-}"; printf '\034\n'; printf '%s\n' "${WCARD_TROW[@]}"; } | awk -F'\t' '
    function trim(v) { sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); return v }
    $0 == "\034" { rows = 1; next }
    !rows { if (NF >= 2 && $1 != "" && $2 != "") before[$2, $1] = 1; next }
    $0 != "" { n++; line[n] = $0; id[n] = $1 }
    END {
      for (i = 1; i <= n; i++) {
        m = split(line[i], f, "\t")
        dep = ""
        for (j = 1; j <= n; j++) if (j != i && ((id[i], id[j]) in before)) dep = dep (dep == "" ? "" : ", ") id[j]
        k = split(f[4], tok, ",")
        for (t = 1; t <= k; t++) {
          v = trim(tok[t])
          if (v ~ /^ext:/) dep = dep (dep == "" ? "" : ", ") v
        }
        if (dep == "") dep = "—"
        f[4] = dep
        out = f[1]
        for (j = 2; j <= m; j++) out = out "\t" f[j]
        print out
      }
    }')" || return 0
  [ -n "$out" ] || return 0
  WCARD_TROW=()
  while IFS= read -r line; do
    [ -n "$line" ] && WCARD_TROW[${#WCARD_TROW[@]}]="$line"
  done < <(printf '%s\n' "$out")
}

# The writer ceiling the chain is scheduled under: the plan's writer budget, or with none
# declared the row count, so the schedule is not capped.
_card_chain_ceil() {  # <plan>
  local ceil="$WCARD_WRITERS"
  case "$ceil" in ''|*[!0-9]*|0) ceil="$(units_rows "${1:-}" 2>/dev/null | grep -c .)" ;; esac
  [ "${ceil:-0}" -gt 0 ] 2>/dev/null || ceil=1
  printf '%s' "$ceil"
}

# The wave card's width block: the chain, its minutes, the peak width against the writer
# budget, and the per-batch widths, all from the one derived graph. With no writer budget the
# line says the budget is absent. `_card_chain` has run already (its edges fill the Tasks
# block's depends column, printed above this one) and left its status in CARD_CHAIN_RC.
_card_chain_block() {  # <plan>
  local plan="$1" w="$WCARD_WRITERS" chain peak
  printf '  Chain and width\n'
  if [ "${CARD_CHAIN_RC:-1}" -eq 0 ]; then
    if [ -n "$CARD_CHAIN" ]; then
      chain="${CARD_CHAIN//,/ → } · ${CARD_CHAIN_MIN} min"
    else
      chain="no open task"
    fi
    case "$w" in
      ''|*[!0-9]*|0) peak="${CARD_PEAK} · writers not declared" ;;
      *)             peak="${CARD_PEAK} of ${w} writers" ;;
    esac
  else
    chain="not computed: ${CARD_CHAIN_ERR}"; peak="not computed"
  fi
  _card_labelled 4 "longest chain" "$chain" 15
  _card_labelled 4 "peak width" "$peak" 15
  _card_batch_widths "$plan" "$WCARD_WRITERS" || :
}

# ── INHERITED DEFERRALS (epic-23 wave-28 T43; REQ-8 AC-8.10, D21, A-orch-64) ─────────────
#
# A DEFERRAL IS FACED AGAIN. Close-out writes every open deferral under `## Deferrals` of the run's
# continuation, `record/<wave slug>/continuation.md` under the docs root (a tree `archive_run`
# never moves), one line each:
#
#     deferred: <record>#<n> <S> <reach> "<title>" stated="<sentence|->" from=<wave name>
#
# The next wave's Step 1 card lists every one until the requirements file's `## Inherited
# deferrals` section disposes of it with exactly one of three lines, `<id>` being `<record>#<n>`:
#
#     adopted: <id> as REQ-<n>   ·   again: <id>   ·   closed: <id> <reason>
#
# Any other line there disposes of nothing, so its deferral stays on the card. A disposal naming an
# id the continuation does not carry disposed of nothing either, and the card refuses rather than
# let the user believe a debt was settled.
#
# THE PREDECESSOR IS THE NEWEST CONTINUATION under the docs root, by mtime ("the next wave's Step 1
# card reads the newest continuation", D21), and never the run's own. A requirements file is named
# `<wave slug>.requirements.md`, so the run's own continuation is `record/<that slug>/continuation.md`;
# it is skipped however new it is, because close-out reads through this same function and the
# run's own continuation may already be written when it does.
#
# ONE READER, TWO CALLERS. `step1` counts the lines by disposal; close-out calls `card.sh inherited
# <requirements file>` and carries the `again` and `open` ones into the new continuation. The card
# and the carry cannot disagree about what was left open, because they are one reading.
_card_predecessor() {  # <docs root> <own wave slug> -> the newest other continuation, or nothing
  local f best=""
  for f in "$1"/record/*/continuation.md; do
    [ -f "$f" ] || continue
    [ "$f" != "$1/record/$2/continuation.md" ] || continue
    if [ -z "$best" ] || [ "$f" -nt "$best" ]; then best="$f"; fi
  done
  printf '%s' "$best"
}

_card_disposals() {  # <requirements file> -> `<adopted|again|closed>\t<id>\t<line>` per disposal
  [ -f "$1" ] && [ -r "$1" ] || return 0
  awk '
    { sub(/\r$/, ""); sub(/[ \t]+$/, "") }
    /^## / { s = ($0 == "## Inherited deferrals"); next }
    !s { next }
    /^adopted:[ \t]+[^ \t]+#[0-9]+[ \t]+as[ \t]+REQ-[0-9]+$/ { split($0, f, /[ \t]+/); print "adopted\t" f[2] "\t" $0; next }
    /^again:[ \t]+[^ \t]+#[0-9]+$/ { split($0, f, /[ \t]+/); print "again\t" f[2] "\t" $0; next }
    /^closed:[ \t]+[^ \t]+#[0-9]+[ \t]+[^ \t]/ { split($0, f, /[ \t]+/); print "closed\t" f[2] "\t" $0 }' "$1"
}

# _card_inherited <requirements file> -> one `<open|adopted|again|closed>\t<deferred line>` per line of
# the predecessor's `## Deferrals`, in its order and as written, then one `unknown\t<disposal line>`
# per disposal naming none of them. The first disposal of an id is the one that counts.
#
# A CARRIED DEBT LINE (wave-30 T32; REQ-11 AC-11.2) is read beside them: `debt: <concept> <kind> "<sites>"
# touches=<N> raised-by=<record> from=<wave>`, close-out's co_debts form, prints `open\t<line>`, so the
# Step 1 card counts it. One that does not parse (lib/debt.sh `DEBT_LINE_ERE`, wave-36 T13) prints
# `unknown\t<line>`. No disposal reaches it: it names
# no id, and it is faced by `session-poker.sh debt adopt`, which writes it into the run's ledger.
_card_inherit_from() {  # <requirements file> -> the continuation its run inherits from, or nothing
  local root slug
  root="$(_card_plan_root "$1")"
  [ -n "$root" ] || return 0
  slug="${1##*/}"; slug="${slug%.requirements.md}"
  _card_predecessor "$(docs_root "$root")" "$slug"
}

_card_inherited() {
  local cont
  [ -n "$(_card_plan_root "$1")" ] || return 0
  cont="$(_card_inherit_from "$1")"
  [ -n "$cont" ] || cont=/dev/null
  CARD_DISPOSALS="$(_card_disposals "$1")" DEBT_LINE_ERE="$DEBT_LINE_ERE" awk '
    BEGIN {
      n = split(ENVIRON["CARD_DISPOSALS"], d, "\n")
      for (i = 1; i <= n; i++) {
        if (split(d[i], p, "\t") < 3 || (p[2] in kind)) continue
        kind[p[2]] = p[1]; said[p[2]] = p[3]; ord[++m] = p[2]
      }
    }
    { sub(/\r$/, "") }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^## / { s = ($0 ~ /^## Deferrals[ \t]*$/); next }
    s && /^deferred:[ \t]/ {
      split($0, f, /[ \t]+/); seen[f[2]] = 1
      print ((f[2] in kind) ? kind[f[2]] : "open") "\t" $0
    }
    s && /^debt:[ \t]/ {
      print (($0 ~ ENVIRON["DEBT_LINE_ERE"]) ? "open" : "unknown") "\t" $0
    }
    END { for (i = 1; i <= m; i++) if (!(ord[i] in seen)) print "unknown\t" said[ord[i]] }' "$cont"
}

# THE REFUSAL IS EXIT 2 WITH NOTHING ON STDOUT: the disposal is checked before the card's first line.
_card_inherit_refuse() {  # <the disposal line>
  printf 'card.sh: step1 refused — a disposal names a deferral the newest continuation does not carry\n  %s\n' \
    "$1" >&2
  exit 2
}

_card_debt_refuse() {  # <the debt line>
  printf 'card.sh: step1 refused — the newest continuation carries a debt: line that does not parse\n  %s\n' \
    "$1" >&2
  exit 2
}

# ── THE CONFIGURATION CARD, STEP 0'S OWN STOP (wave-39 T26; D3, D23, AC-20.1; was wave-38 T17's fold) ──────
#
# TWO STOPS, BECAUSE THEY ARE TWO DECISIONS. Wave 38 (T17, D17) folded Step 0's settings into the requirements
# card as its first section, so one reply approved both. The user reopened it (wave-39 D3): "I didn't want to
# eliminate step 0 configuration card. That's different than requirements. It doesn't make sense to combine
# them." `step0 <plan>` renders the card in the 1.20.0 shape (Purpose, Seed, Run, Branches, Paths, Shape, Gates,
# Models, the question), and what the fold kept stays: it is RENDERED from the plan's frontmatter, never typed by
# the model, so what is shown is what was written. Every row folds through `_card_labelled` when it does not
# fit, and an absent value prints `unknown` rather than dropping its line. `step1` prints none of it.
#
# THE SOURCE IS THE PLAN BESIDE THE REQUIREMENTS FILE (A-T17-4): `<docs root>/plans/<the requirements
# file's directory name>/<stem>.plan.md`, the file Step 0 wrote. A plan given as the artifact (task scale)
# is its own source; with no such plan the artifact's own frontmatter answers.
_card_config_src() {  # <artifact path as given> -> the file whose frontmatter the settings are read from
  local a="$1" root d cand
  case "$a" in *.plan.md) printf '%s' "$a"; return 0 ;; esac
  root="$(_card_plan_root "$a")"
  if [ -n "$root" ]; then
    d="$(dirname "$a")"; d="${d##*/}"
    cand="$(docs_root "$root")/plans/${d}/$(_card_stem "$a").plan.md"
    [ -f "$cand" ] && { printf '%s' "$cand"; return 0; }
  fi
  printf '%s' "$a"
}

# A CONFIGURATION ROW KEEPS ITS TWO-SPACE SEPARATORS while it fits (`value  (scale default)`, the Step 0
# layout), and folds through `_card_labelled`, which joins words by one space, only when it does not.
_card_cfg_row() {  # <indent> <label> <text> <label width>
  _bionic_cols_into "$3"
  if [ $(( $1 + $4 + BIONIC_COLS )) -le "$BIONIC_LINE_WIDTH" ]; then
    _card_rstrip "$(_card_spaces "$1")$(_card_pad "$2" "$4")$3"; printf '\n'
  else
    _card_labelled "$@"
  fi
}

_card_fm() {  # <key> -> the settings source's value, or `unknown`
  local v
  v="$(plan_frontmatter_get "$CARD_CFG" "$1")"
  printf '%s' "${v:-unknown}"
}

# A REVIEW FIELD IS `(from rigor)` WHILE IT HOLDS ITS LEVEL'S DEFAULT (lib/run.sh holds the defaults), and
# `(set)` once the user set another; an absent field reads as the default, as every reader reads it.
_card_review_field() {  # <label> <value as written, or empty> <the level's default, or empty>
  local v="$2"
  [ -n "$v" ] || v="$3"
  if [ -z "$v" ]; then _card_cfg_row 4 "$1" unknown 16
  elif [ "$v" = "$3" ]; then _card_cfg_row 4 "$1" "$v  (from rigor)" 16
  else _card_cfg_row 4 "$1" "$v  (set)" 16
  fi
}

_card_model_of() {  # <model_plan value> <role> -> the tier it names for the role, or nothing
  printf '%s\n' "$1" | tr ';' '\n' | sed -n "s/^[[:space:]]*$2=//p" | head -1 | sed 's/[[:space:]]*$//'
}

_card_config() {  # <artifact path as given> — the Step-0 card's settings, Seed to Models; sets CARD_CFG
  local root scale rig lvl v t rec docs mp r f m e
  CARD_CFG="$(_card_config_src "$1")"
  root="$(_card_plan_root "$CARD_CFG")"
  scale="$(plan_frontmatter_get "$CARD_CFG" scale)"
  rig="$(plan_frontmatter_get "$CARD_CFG" rigor)"
  lvl="$(rigor_level "$rig" 2>/dev/null)"
  # The branches are the plan's when it names them (`ready` and the walls read the plan).
  if [ "$CARD_CFG" != "$1" ]; then
    v="$(plan_working_branch "$CARD_CFG")"; [ -z "$v" ] || WCARD_WB="$v"
    v="$(plan_integration_branch "$CARD_CFG")"; [ -z "$v" ] || WCARD_IB="$v"
    v="$(plan_frontmatter_get "$CARD_CFG" base-sha)"; [ -z "$v" ] || WCARD_BASE="$v"
  fi
  v="$(plan_frontmatter_get "$CARD_CFG" seed)"
  [ -z "$v" ] || { printf '\n  Seed\n'; _card_cfg_row 4 brief "$v" 14; }
  printf '\n  Run\n'
  _card_cfg_row 4 intent "$(_card_fm intent)" 16
  t="(scale default)"; [ -z "$(plan_frontmatter_get "$CARD_CFG" rigor-override)" ] || t="(overridden)"
  v="$(_card_rigor_line "$rig")"; v="${v#review rigor: }"
  [ -n "$lvl" ] || t=""
  _card_cfg_row 4 rigor "${v}${t:+  $t}" 16
  v="$(_card_regression_line "$scale" "$CARD_CFG" 2>/dev/null)" || v="unknown"
  _card_cfg_row 4 regression "${v#regression }" 16
  _card_review_field review-cadence "$(plan_frontmatter_get "$CARD_CFG" review-cadence)" \
    "$([ -n "$lvl" ] && printf '%s' "$REVIEW_CADENCE_DEFAULT")"
  _card_review_field fix-policy "$(plan_frontmatter_get "$CARD_CFG" fix-policy)" \
    "$([ -n "$lvl" ] && printf '%s' "$FIX_POLICY_DEFAULT")"
  _card_review_field fix-cap "$(plan_frontmatter_get "$CARD_CFG" fix-cap)" "$(fix_cap_default "$lvl" 2>/dev/null)"
  # THE SCALE CARRIES ITS RECOMMENDATION (AC-5.2): two sentences Step 0 wrote as `scale-recommendation:`.
  rec="$(plan_frontmatter_get "$CARD_CFG" scale-recommendation)"
  _card_cfg_row 4 scale "${scale:-unknown} — ${rec:-(no recommendation recorded)}" 16
  _card_cfg_row 4 name "$(_card_stem "$CARD_CFG")" 16
  printf '\n'
  _card_branches
  printf '\n  Paths\n'
  if [ -n "$root" ]; then
    _card_cfg_row 4 project "$root" 14
    docs="$(docs_root "$root")"; docs="${docs#"$root"/}"
    t="(default)"; [ -z "$(config_value "$root" docs-root "")" ] || t="(from config.yaml)"
    _card_cfg_row 4 docs "$docs  $t" 14
    _card_cfg_row 4 tmp ".bionic/tmp  (default)" 14
    v="$(plan_frontmatter_get "$CARD_CFG" archive-root)"
    if [ -z "$v" ]; then
      t="(default)"; [ -z "$(config_value "$root" archive-root "")" ] || t="(from config.yaml)"
      v="$(archive_root "$root")  $t"
    fi
    _card_cfg_row 4 archive "$v" 14
  else
    for v in project docs tmp archive; do _card_cfg_row 4 "$v" unknown 14; done
  fi
  printf '\n  Shape\n'
  _card_cfg_row 4 surface "$(_card_fm surface_type)" 14
  case "$(plan_frontmatter_get "$CARD_CFG" multi_agent)" in
    true) v="multi-agent, tiered dispatch" ;; false) v="single-thread" ;; *) v=unknown ;;
  esac
  _card_cfg_row 4 agents "$v" 14
  _card_cfg_row 4 deploy "$(_card_fm deploy_target)" 14
  _card_cfg_row 4 worktree "$(_card_fm use_worktree)" 14
  _card_cfg_row 4 cleanup "$(_card_fm cleanup_on_finish)" 14
  printf '\n  Gates\n'
  _card_cfg_row 4 walk "$(_card_fm walk)" 14
  v="$(plan_frontmatter_get "$CARD_CFG" design-interview)"
  case "$v" in
    false*) v="${v#false}"; v="${v# }"; v="waived (${v:-the user})" ;;
    *) v=required ;;
  esac
  _card_cfg_row 4 interview "$v" 14
  v="answered from the run's workspace"
  [ -z "$root" ] || [ "$(config_value "$root" permission-answers "")" != false ] || v=off
  _card_cfg_row 4 permissions "$v" 14
  # THE MODELS ARE model_plan's, AND A ROLE IT DOES NOT NAME RUNS AT ITS ROLE FILE'S MODEL (steps/0.md):
  # each role file beside this script answers for the role model_plan leaves out, marked so.
  printf '\n  Models\n'
  mp="$(plan_frontmatter_get "$CARD_CFG" model_plan)"
  v="$(_card_model_of "$mp" orchestrator)"
  _card_cfg_row 4 orchestrator "${v:-not declared}" 20
  for f in "${CARD_SELF_DIR}/../agents/"*.md; do
    [ -f "$f" ] || continue
    r="${f##*/}"; r="${r%.md}"
    v="$(_card_model_of "$mp" "$r")"
    if [ -z "$v" ]; then
      m="$(awk '/^model:/ { print $2; exit }' "$f")"; e="$(awk '/^effort:/ { print $2; exit }' "$f")"
      v="${m:-unknown}${e:+-$e}  (role file)"
    fi
    _card_cfg_row 4 "$r" "$v" 20
  done
}

# ── THE INHERITED LEFTOVERS, ONE LINE OF COUNTS (wave-38 T17; D5, AC-10.1) ─────────────────────────────
#
# The card used to print every open line, 68 lines on wave-37's card. It counts them instead: every line
# the newest continuation carries, then the adopted, carried (`again:`) and closed ones, and names the
# section that holds the list, the continuation's `## Deferrals` (A-T17-1). No line is printed; close-out's
# readers (`card.sh inherited`, `inherited-debt`) are unchanged.
_card_inherited_line() {  # <the _card_inherited reading> <artifact path as given>
  local root cont counts
  root="$(_card_plan_root "$2")"
  cont="$(_card_inherit_from "$2")"
  counts="$(printf '%s\n' "$1" | awk -F'\t' '$1 != "" { n++ } $1 == "adopted" { a++ } $1 == "again" { c++ }
    $1 == "closed" { k++ } END { printf "%d inherited · %d adopted · %d carried · %d closed", n, a, c, k }')"
  if [ -n "$cont" ]; then
    _card_labelled 2 Inherited "${counts} · listed in ${cont#"$root"/}#Deferrals" 11
  else
    _card_labelled 2 Inherited "${counts} · no closed run above this one" 11
  fi
}

_card_step0() {  # <artifact path as given>
  printf 'Step 0 · Plan Configuration\n\n  Purpose\n'
  _card_fold_at 4 "$WCARD_GOAL"
  _card_config "$1"
  printf '\n%s\n' "$CARD_Q_STEP0"
}

_card_step1() {  # <citation path> <artifact path as given>
  local inh l
  inh="$(_card_inherited "$2")"
  l="$(printf '%s\n' "$inh" | sed -n "s/^unknown${CARD_TAB}//p" | head -1)"
  case "$l" in
    '') ;;
    debt:*) _card_debt_refuse "$l" ;;
    *) _card_inherit_refuse "$l" ;;
  esac
  printf 'Step 1 · Requirements\n\n  Purpose\n'
  _card_fold_at 4 "$WCARD_GOAL"
  printf '\n'
  CARD_ROWS=( ${WCARD_RROW[@]+"${WCARD_RROW[@]}"} )
  _card_render_batch requirement
  printf '\n  Not Doing\n'
  local b
  for b in ${WCARD_ND[@]+"${WCARD_ND[@]}"}; do _card_fold_at 4 "$b"; done
  printf '\n'
  _card_inherited_line "$inh" "$2"
  printf '\n  Artifacts\n    requirements  %s\n\n' "$1"
  printf '%s\n' "$CARD_Q_STEP1"
  printf 'explain <requirement> · set <flag>=<value>\n'
}

# THE PARAGRAPH CARD IS FOR A DESIGN THAT IS ONE (D8), AND THE SHAPE FOLLOWS THE SPEC, NEVER
# THE SCALE (wave-43 D11; AC-13.2). A wave design is a document with decisions, an ownership
# table and an eval-design table, and the card renders those three batches. A task run may write
# "a design paragraph per non-trivial task, in the session plan" (steps/2.md:60), and for that
# spec there are no decisions to tabulate and no eval design to count: the card shows the
# paragraph, names the artifact, and asks its question, and does NOT offer `show evals` or
# `explain <decision>`, because a card that offers an affordance over content it is not carrying
# is the same lying surface the regression line was. But a task-scale run that writes the full
# spec (waves 42 and 43 did) gets the full card: keying the shape on `scale:` alone drew the
# paragraph over nine decisions and 37 evals, and the decisions reached the user by hand
# (wave-42 A-orch.8). `_card_step2_paragraph` is the one test: no decision row and no eval row.
_card_step2_paragraph() { [ "${#WCARD_DROW[@]}" -eq 0 ] && [ "${#WCARD_EROW[@]}" -eq 0 ]; }

_card_step2_task() {  # <citation path>
  local d="$WCARD_DESIGN"
  [ -n "$d" ] || d="$WCARD_GOAL"
  printf 'Step 2 · Design\n\n'
  _card_branches
  printf '\n  Design\n'
  _card_fold_at 4 "$d"
  printf '\n  Artifacts\n    plan  %s\n' "$1"
  printf '\n%s\n' "$CARD_Q_STEP2"
}

# THE DOCS ROOT, SPELLED THE WAY THE SPEC'S OWN PATH LINE IS (wave-26 D13). A frontmatter
# `adrs:`, `design-ledger:` or `requirements:` value is written under the docs root
# (`adrs/…`, `record/…`, `specs/…`), and the card prints every artifact by the path a reader
# opens — project-relative, `.bionic/docs/…` by default. The root is the configured one
# (`docs_root`, the reading every other caller uses), made relative to the project when it
# sits under it and printed whole when it does not.
_card_docs_prefix() {
  local root d
  root="$(project_root "$PWD" 2>/dev/null)"
  d="$(docs_root "$root" 2>/dev/null)"
  case "$d" in
    "$root"/*) printf '%s' "${d#"$root"/}" ;;
    *)         printf '%s' "${d:-.bionic/docs}" ;;
  esac
}

# One frontmatter path, in full. Only a value that starts `specs/`, `adrs/` or `record/` gets
# the root in front; anything else (already in full, or not under the docs root) is printed as
# written, because a path the card rewrites by guess is a path nobody can open.
_card_full_path() {  # <value> <docs prefix>
  case "$1" in
    specs/*|adrs/*|record/*) printf '%s/%s' "$2" "$1" ;;
    *)                       printf '%s' "$1" ;;
  esac
}

# A frontmatter value that names several paths joins them with " · "; each prints on a line of
# its own under the label.
_card_artifact_lines() {  # <label> <value> <docs prefix>
  local label="$1" v="$2" p
  [ -n "$v" ] || return 0
  while IFS= read -r p; do
    p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"
    [ -n "$p" ] || continue
    _card_path_line "$label" "$(_card_full_path "$p" "$3")"
  done < <(printf '%s\n' "${v// · /$'\n'}")
}

# ONE ARTIFACT LINE, HELD TO THE BUDGET (review-3 F5). A path that fits prints whole after its
# label. One that does not is cut after a `/` — the last one that still fits — and goes on under
# the path's first column, so every piece is a whole directory name and the path reads off
# top to bottom; a single name longer than the column is cut where the column ends. Paths are
# measured in bytes, which is never less than their columns.
_card_path_line() {  # <label> <path>
  local label="$1" rest="$2" ind avail head cut first=1
  ind=$(( 4 + ${#label} + 2 ))
  avail=$(( BIONIC_LINE_WIDTH - ind ))
  [ "$avail" -ge 8 ] || avail=8
  while :; do
    if [ "${#rest}" -le "$avail" ]; then
      head="$rest"; rest=""
    else
      head="${rest:0:$avail}"
      case "$head" in
        */*) cut="${head%/*}/" ;;
        *)   cut="$head" ;;
      esac
      head="$cut"; rest="${rest:${#cut}}"
    fi
    if [ "$first" -eq 1 ]; then
      printf '    %s  %s\n' "$label" "$head"; first=0
    else
      printf '%s%s\n' "$(_card_spaces "$ind")" "$head"
    fi
    [ -n "$rest" ] || break
  done
}

# ONE CARD THE DESIGN IS APPROVED ON (wave-26 D13). The head says what is being built and why
# it is shaped so (Goal, Approach, Worth your eye); the tables below it say what is decided and
# how each criterion is proven; the Artifacts say where each piece lives, by the path a reader
# opens. Ownership and one requirement's evals are not on it — they are asked for, as the
# sub-views the last line offers.
_card_step2() {  # <artifact path>
  if [ "$CARD_SCALE" = "task" ] && _card_step2_paragraph; then _card_step2_task "$1"; return 0; fi
  local e dp
  printf 'Step 2 · Design\n\n  Goal\n'
  _card_fold_at 4 "$WCARD_GOAL"
  printf '\n'
  if [ -n "$WCARD_APPROACH" ]; then
    printf '  Approach\n'
    _card_fold_at 4 "$WCARD_APPROACH"
    printf '\n'
  fi
  if [ "${#WCARD_WORTH[@]}" -gt 0 ]; then
    printf '  Worth your eye\n'
    for e in "${WCARD_WORTH[@]}"; do _card_worth_entry "$e"; done
    printf '\n'
  fi
  _card_branches
  printf '\n'
  CARD_ROWS=()
  local r
  for r in ${WCARD_DROW[@]+"${WCARD_DROW[@]}"}; do
    CARD_ROWS[${#CARD_ROWS[@]}]="${r}${CARD_TAB}$(_card_adr_for "${r%%"$CARD_TAB"*}")"
  done
  _card_render_batch decision
  printf '\n'
  CARD_ROWS=( ${WCARD_EROW[@]+"${WCARD_EROW[@]}"} )
  _card_render_batch eval-design
  dp="$(_card_docs_prefix)"
  printf '\n  Artifacts\n    spec  %s\n' "$1"
  _card_artifact_lines design "$WCARD_DPTR" "$dp"
  _card_artifact_lines adr "$WCARD_ADRS" "$dp"
  _card_artifact_lines ledger "$WCARD_LEDGER" "$dp"
  _card_artifact_lines reqs "$WCARD_REQS" "$dp"
  printf '\n%s\n' "$CARD_Q_STEP2"
  printf 'show evals <req> · explain <decision> · show ownership\n'
}

# A `Worth your eye` entry: its first line flush at the block's indent, every continuation
# line two columns further in, so one entry is one visible unit. The fold budget is the
# continuation's (the narrower), which leaves the first line two columns of slack.
_card_worth_entry() {  # <text>
  local line first=1
  while IFS= read -r line; do
    if [ "$first" -eq 1 ]; then
      _card_rstrip "    ${line}"; first=0
    else
      _card_rstrip "      ${line}"
    fi
    printf '\n'
  done < <(bionic_wrap "${1:-}" $(( BIONIC_LINE_WIDTH - 6 )))
}

# ── THE STEP-2 SUB-VIEWS (wave-26 D13) ───────────────────────────────────────
# `card.sh step2 <spec> ownership` is the Ownership table and nothing else; `… evals <REQ>` is
# one requirement's Eval design rows. Both read the same parse the whole card reads, and the
# table goes through the same row kind it always did.
_card_step2_ownership() {
  CARD_ROWS=( ${WCARD_OROW[@]+"${WCARD_OROW[@]}"} )
  # A table with the `reuses` column sends five cells a row (see the awk's own-table arm): the
  # reuses cell goes on a second line under its row, in the kind that carries one.
  case "${CARD_ROWS[0]:-}" in
    *"$CARD_TAB"*"$CARD_TAB"*"$CARD_TAB"*"$CARD_TAB"*) _card_render_batch ownership-reuses ;;
    *) _card_render_batch ownership ;;
  esac
}

# A labelled line at an indent: the label once, padded, then the text folded in the column
# that is left, continuation lines under the text.
_card_labelled() {  # <indent> <label> <text> [<label width, 12 by default>]
  local ind="$1" label="$2" text="$3" line first=1 lw="${4:-12}"
  while IFS= read -r line; do
    if [ "$first" -eq 1 ]; then
      _card_rstrip "$(_card_spaces "$ind")$(_card_pad "$label" "$lw")${line}"; first=0
    else
      _card_rstrip "$(_card_spaces $(( ind + lw )))${line}"
    fi
    printf '\n'
  done < <(bionic_wrap "$text" $(( BIONIC_LINE_WIDTH - ind - lw )))
}

_card_step2_evals() {  # <REQ id>
  local row crit typ ev fails
  printf '  Eval design · %s\n' "$1"
  for row in ${WCARD_CROW[@]+"${WCARD_CROW[@]}"}; do
    _card_split "$row"
    [ "${CARD_CELLS[0]:-}" = "$1" ] || continue
    crit="${CARD_CELLS[1]:-}"; typ="${CARD_CELLS[2]:-}"; ev="${CARD_CELLS[3]:-}"; fails="${CARD_CELLS[4]:-}"
    _card_fold_at 4 "$crit"
    _card_labelled 6 type "$typ"
    _card_labelled 6 eval "$ev"
    _card_labelled 6 "fails when" "$fails"
  done
}

# THE REFUSAL IS ONE LINE AND EXIT 2 (not 64: the artifact was fine, the request was not).
_card_step2_refuse() {  # <what was wrong>
  local ids="" row r
  for row in ${WCARD_EROW[@]+"${WCARD_EROW[@]}"}; do
    r="${row%%"$CARD_TAB"*}"
    case "$r" in total|'') continue ;; esac
    ids="${ids}${ids:+ }${r}"
  done
  printf 'card.sh: %s — valid forms: step2 <spec> · step2 <spec> ownership · step2 <spec> evals <REQ-id>%s\n' \
    "$1" "${ids:+ (REQ-id: ${ids})}" >&2
  exit 2
}

# `step2 <spec> [ownership | evals <REQ-id>]`, the arguments after the artifact. The paragraph
# card offers neither view, so it refuses both; a task-scale spec holding the tables has them.
_card_step2_view() {  # <artifact path as given> <args...>
  shift
  local view="${1:-}" known=0 row r
  if [ "$CARD_SCALE" = "task" ] && _card_step2_paragraph; then _card_step2_refuse "a paragraph design has no sub-views"; fi
  case "$view" in
    ownership)
      [ "$#" -eq 1 ] || _card_step2_refuse "ownership takes no argument"
      _card_step2_ownership ;;
    evals)
      [ "$#" -eq 2 ] || _card_step2_refuse "evals takes one requirement id"
      for row in ${WCARD_EROW[@]+"${WCARD_EROW[@]}"}; do
        r="${row%%"$CARD_TAB"*}"
        [ "$r" = "$2" ] && [ "$r" != "total" ] && known=1
      done
      [ "$known" -eq 1 ] || _card_step2_refuse "no requirement '$2' in the Eval design"
      _card_step2_evals "$2" ;;
    *) _card_step2_refuse "unknown sub-view '${view}'" ;;
  esac
}

# TWO PATHS, AND THEY ARE NOT THE SAME PATH. `$1` is the CITATION — the
# project-root-relative spelling the Artifacts block prints — and `$2` is the path as
# the caller gave it, which is what the regression and the batch widths must be read from:
# a citation is for a reader to open, and `.bionic/docs/plans/…` resolves against the
# renderer's own cwd rather than against the plan.
#
# STEP 3 APPROVES THE PLAN AND THE MATRIX ONLY (wave-26 D12, D13). The design was approved on the
# Step-2 card, so this card cites it by path and repeats neither its purpose (the Goal paragraph)
# nor its eval counts. What it adds is the plan's own shape: each task with the criteria it
# serves, and the longest chain and the peak width the derived graph gives, at every scale.
_card_step3() {  # <citation path> <artifact path as given>
  # THE CHAIN IS ASKED BEFORE THE TASKS ARE RENDERED: its edges are the depends column of a
  # table with a `reads` column, and the graph is fetched once for both.
  CARD_CHAIN_RC=0
  _card_chain "$2" "$(_card_chain_ceil "$2")" || CARD_CHAIN_RC=1
  _card_reads_depends "$2"
  printf 'Step 3 · Plan\n\n'
  _card_branches
  printf '\n'
  CARD_ROWS=( ${WCARD_TROW[@]+"${WCARD_TROW[@]}"} )
  _card_render_batch task
  printf '\n'
  _card_chain_block "$2"
  # THE RIGOR HAS A LINE OF ITS OWN: its label and meaning do not fit beside a configured regression
  # inside the line budget, and the level is what the approval reads at a glance.
  printf '\n  Verification\n    %s matrix rows · regression %s · walk %s\n    %s\n' \
    "$WCARD_MROWS" "$(_card_floor "$2")" "${WCARD_WALK:-not declared}" "$(_card_rigor_line "$WCARD_RIGOR")"
  printf '\n  Artifacts\n    plan  %s\n' "$1"
  _card_artifact_lines spec "$WCARD_SPEC" "$(_card_docs_prefix)"
  printf '\n%s\n' "$CARD_Q_STEP3"
  printf 'show evals <req> · show task <n> · explain <decision>\n'
}

# ── THE REVIEW RIGOR, PRINTED (wave-28 T44; AC-16.2) ─────────────────────────
#
# A level prints as `review rigor: <level> (<one|two> independent mind[s])`, `single` or `double`.
# A plan that declares no rigor, or a word that is no level (a word before 1.14.0 among them), says
# so in place of the level.
_card_rigor_line() {  # <rigor word, as the plan carries it> -> the Verification block's rigor phrase
  [ -n "${1:-}" ] || { printf 'review rigor: not declared'; return 0; }
  rigor_print "$1" 2>/dev/null || printf "review rigor: '%s' is no level (single or double)" "$1"
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

# ── WHAT THE PERSON OWES (epic-23 wave-33-workhorse, T11; REQ-2 AC-2.2, D2) ─────────────
#
# A STEP CARD LEAVES THE PERSON A DECISION, so the card is where the need is declared: a whole
# card rendered for the session's own run opens `approve:step<n>` on the person's ledger
# (lib/owed.sh), titled for a push and carrying the one question the card printed, and the Stop
# that ends the turn sends it at least once (lib/stop.sh). Rendering a card closes the earlier steps'
# items, since a later card is shown only once the earlier one was answered; the Stop closes
# them all once the plan carries `approved-by:`. The question strings live here, once, and are
# what both the card and the item print.
#
# ONLY THE SESSION'S OWN RUN. The artifact must be the plan the session is bound to, or share
# its stem (`wave-01-x.requirements.md` and `wave-01-x.spec.md` beside `wave-01-x.plan.md`), so a
# card rendered over another run's artifacts (a suite's fixtures, a reader comparing waves)
# opens nothing. No session id, no binding, no library: nothing is opened, and in every case the
# card prints exactly what it printed before and exits as it did; the ledger is written silently.
CARD_Q_STEP0='Do you approve this configuration? Reply "approved" to approve it.'
CARD_Q_STEP1='Do you approve these requirements? Reply "approved" to approve it.'
CARD_Q_STEP2='Do you approve this design? Reply "approved" to approve it.'
CARD_Q_STEP3='Do you approve this plan? Reply "approved" to approve it.'

_card_phys() {  # <path> -> its absolute physical path; rc 1 when its directory does not resolve
  local d
  d="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s' "$d" "${1##*/}"
}
_card_stem() {  # <path> -> the name without `.<kind>.md`: wave-01-x.plan.md -> wave-01-x
  local b="${1##*/}"
  b="${b%.md}"
  printf '%s' "${b%.*}"
}

_card_owe() {  # <step 0-3> <artifact path as given> -> always 0, prints nothing
  local n="$1" sid="${CLAUDE_CODE_SESSION_ID:-}" art root plan m q t
  [ -n "$sid" ] && [ -n "${2:-}" ] || return 0
  [ -r "${CARD_SELF_DIR}/lib/owed.sh" ] || return 0
  declare -F session_plan >/dev/null 2>&1 && declare -F project_root >/dev/null 2>&1 || return 0
  art="$(_card_phys "$2")" || return 0
  root="$(project_root "${art%/*}" 2>/dev/null)"
  [ -n "$root" ] || return 0
  plan="$(session_plan "$root" "$sid" 2>/dev/null)" || return 0
  plan="$(_card_phys "$plan")" || return 0
  if [ "$art" != "$plan" ]; then
    case "$n" in 1|2) [ "$(_card_stem "$art")" = "$(_card_stem "$plan")" ] || return 0 ;; *) return 0 ;; esac
  fi
  declare -F owed_open >/dev/null 2>&1 || . "${CARD_SELF_DIR}/lib/owed.sh" 2>/dev/null || return 0
  case "$n" in
    0) q="$CARD_Q_STEP0"; t="approval: Step 0 configuration" ;;
    1) q="$CARD_Q_STEP1"; t="approval: Step 1 requirements" ;;
    2) q="$CARD_Q_STEP2"; t="approval: Step 2 design" ;;
    3) q="$CARD_Q_STEP3"; t="approval: Step 3 plan" ;;
    *) return 0 ;;
  esac
  m=0
  while [ "$m" -lt "$n" ]; do
    OWED_ROOT="$root" OWED_SID="$sid" owed_close "approve:step$m" "card.sh step$n" >/dev/null 2>&1
    m=$((m + 1))
  done
  OWED_ROOT="$root" OWED_SID="$sid" owed_open "approve:step$n" "$t" "$q" >/dev/null 2>&1
  return 0
}

# ── WHETHER THE RELEASE APPROVAL CARD MAY RENDER ───────────────────────────────
#
# The page itself is `session-poker.sh release-approval`; this file keeps the one owner of the three facts it is
# refused on, because the tick asks them too. `early <plan>` asks, cheapest first: an open reader row on the
# session's roster (an auditor or a critic, not acked) or a reader row past the landed release whose reading is not
# registered, an owed reading unregistered at the working head
# (lib/units.sh `_units_readings_state`, the tick's own reading), and `current <N> --check` for 6, 7 and 8 (the
# check-only advance; its exit is read and its verdict line is the reason, never a second judgment here). On the
# first that fails it prints `CARD-EARLY — <reason>` on stderr, exit 1. When all three hold it exits 0 and prints,
# on stdout, one `settles: <key>` line per item a red check owes that the page settles with a decision of the
# user's (`waive:<question>` or `row:<AC>`), so the page opens each on the person's ledger.
#
# THE SESSION'S OWN RUN. The checks act on the run the session is bound to, so a plan that is not that run is
# refused by name rather than judged against another run's advances.
_card_early_load() {  # -> 0 when the owed ledger and the roster readers are loaded beside this file
  # shellcheck source=/dev/null
  declare -F owed_list >/dev/null 2>&1 || . "${CARD_SELF_DIR}/lib/owed.sh" 2>/dev/null
  # shellcheck source=/dev/null
  declare -F roster_open_names >/dev/null 2>&1 || . "${CARD_SELF_DIR}/lib/roster.sh" 2>/dev/null
  declare -F owed_list >/dev/null 2>&1 && declare -F roster_open_names >/dev/null 2>&1
}

_card_early_ctx() {  # <plan as given> -> 0 and the CF_* context, or 1 and CF_ERR
  local bound=""
  CF_ERR=""
  CF_SID="${CLAUDE_CODE_SESSION_ID:-}"
  [ -n "$CF_SID" ] || { CF_ERR="no session key (CLAUDE_CODE_SESSION_ID is unset), and the release approval card is a session's own run"; return 1; }
  CF_PLAN="$(_card_phys "$1")" || { CF_ERR="no plan at '$1'"; return 1; }
  CF_ROOT="$(project_root "${CF_PLAN%/*}" 2>/dev/null)"
  [ -n "$CF_ROOT" ] || { CF_ERR="'$1' is under no project root"; return 1; }
  bound="$(session_plan "$CF_ROOT" "$CF_SID" 2>/dev/null)" && bound="$(_card_phys "$bound" 2>/dev/null)" || bound=""
  [ "$bound" = "$CF_PLAN" ] || {
    CF_ERR="'$1' is not the run this session is bound to (${bound:-none}); the release approval card checks the bound run"
    return 1
  }
  CF_HEAD="$(proof_branch_head "$CF_PLAN" "$CF_ROOT" 2>/dev/null)" || CF_HEAD=""
  case "$CF_HEAD" in
    [0-9a-f]*) : ;;
    *) CF_ERR="the plan's working branch names no commit, so there is no head to check"; return 1 ;;
  esac
  CF_HEAD8="${CF_HEAD:0:8}"
  CF_POKER="${CARD_SELF_DIR}/../hooks/session-poker.sh"
  [ -f "$CF_POKER" ] || { CF_ERR="no session-poker.sh beside this file (${CF_POKER}) to check the advances with"; return 1; }
  return 0
}

_card_poke() {  # <verb> <args...> -> the poker's output, stdout and stderr, run as this session in the run's root; its rc
  # The readings a tick handed this check are its alone: each advance's check judges for itself.
  ( cd "$CF_ROOT" && exec env -u UNITS_LIVE_HEAD -u UNITS_READINGS_STATE CLAUDE_CODE_SESSION_ID="$CF_SID" "${BASH:-bash}" "$CF_POKER" "$@" ) 2>&1
}

_card_early() {  # -> 0 when the page may render; 1 and CARD_EARLY_WHY on the first of the three facts that fails
  local roster ledger names n type st q head8 out rc line
  CARD_EARLY_WHY=""
  # (1) AN OPEN READER: the roster's open names (lib/roster.sh, the one closing rule), each read by its latest row's role.
  roster="$CF_ROOT/.bionic/tmp/roster-$CF_SID.state"
  if [ -f "$roster" ] && [ ! -L "$roster" ]; then
    ledger="$(roster_ack_ledger "$roster")"
    names="$(roster_open_names "$roster" "$ledger" "$CF_SID")"
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      type="$(CF_NM="$n" awk -v rpfx="roster-state/${ROSTER_SCHEMA_VERSION}|" '
        index($0, rpfx) != 1 { next }
        { np = split($0, p, "|"); nm = ""; st = ""
          for (i = 1; i <= np; i++) {
            if (substr(p[i], 1, 5) == "name=") nm = substr(p[i], 6)
            else if (substr(p[i], 1, 14) == "subagent_type=") st = substr(p[i], 15)
          }
          if (nm == ENVIRON["CF_NM"]) t = st }
        END { print t }' "$roster" 2>/dev/null)"
      case "$type" in
        *auditor|*critic) CARD_EARLY_WHY="reviewer $n open"; return 1 ;;
      esac
    done <<CF_OPEN
$names
CF_OPEN
  fi
  # A READER ROW PAST THE LANDED RELEASE (lib/units.sh `units_post_readers`), pending or active, holds the page until
  # its reading is registered, even before it is dispatched: what landed after the release is read before the person
  # is asked. Once registered, the piece reading carries its question's chain to the head, so no waiver is put for it.
  while IFS='	' read -r n st q; do
    case "$st:$q" in
      pending:unread|active:unread) CARD_EARLY_WHY="review row $n reads what landed after the release, and its review is not registered"; return 1 ;;
    esac
  done <<CF_POST
$(units_post_readers "$CF_PLAN" 2>/dev/null)
CF_POST
  # (2) A READING UNREGISTERED AT THE HEAD: facts_state's review lines at the branch ref, as the tick reads them.
  # A failing reading is registered; the advance's check below is what refuses it. The tick hands the answer its
  # `sched_live_head` already got, with the head it was asked at; this reads it when that head is this one, and
  # asks the judge itself otherwise.
  head8="$CF_HEAD8"
  if [ -n "${UNITS_READINGS_STATE:-}" ] && [ "${UNITS_LIVE_HEAD:-}" = "$CF_HEAD" ]; then
    st="$UNITS_READINGS_STATE"
  else
    st="$(_units_readings_state "$CF_PLAN")"
  fi
  if [ "$st" != covered ]; then
    q="$(printf '%s\n' "$st" | awk '{ n = split($0, a, /; /)
      for (i = 1; i <= n; i++) { split(a[i], f, " "); if (f[1] == "review" && (f[5] == "absent" || f[5] == "uncovered")) { print f[2]; exit } } }')"
    if [ -n "$q" ]; then CARD_EARLY_WHY="$q unregistered at $head8"; return 1; fi
    case "$st" in
      review" "*) : ;;
      *) CARD_EARLY_WHY="the reviews cannot be judged at $head8: $st"; return 1 ;;
    esac
  fi
  # (3) THE ADVANCES TO 6, 7 AND 8, CHECKED BY THE ADVANCE ITSELF. A red check is early unless every refusal it
  # prints is one the page settles with a decision (`_card_settles`): its lines are read as the check captured
  # them, never judged again here.
  CF_SETTLE=""
  for n in 6 7 8; do
    out="$(_card_poke current "$n" --check)"; rc=$?
    [ "$rc" -eq 0 ] && continue
    _card_settles "$out" && continue
    line="$(printf '%s\n' "$out" | awk 'NF { print; exit }')"; line="${line#poker: }"
    CARD_EARLY_WHY="${line:-current $n --check exited $rc}"
    return 1
  done
  return 0
}

# _card_t4_confirm_key -> the key a T4 row's block carries beside `evidence:`, the user's confirmation of the row's own
# check, as walls.sh `keys_for_tier` names it; nothing when walls.sh cannot be loaded, so the refusal stays early.
_card_t4_confirm_key() {
  ( . "${CARD_SELF_DIR}/lib/walls.sh" >/dev/null 2>&1 && declare -F keys_for_tier >/dev/null 2>&1 || exit 1
    for _ck in $(keys_for_tier T4); do [ "$_ck" = evidence ] || { printf '%s' "$_ck"; break; }; done )
}

# _card_unapproved -> the format of the refusal `current 8` prints while the release approval is missing, as the judge
# spells it (hooks/poker/judge.sh `cur8_unapproved_line`), read from the judge beside CF_POKER. judge.sh defines
# functions only, so sourcing it in a subshell runs nothing and defines nothing here. Nothing when the judge cannot be
# read, and then no line is settled as that refusal, so the page stays early.
_card_unapproved() {
  ( . "${CF_POKER%/*}/poker/judge.sh" >/dev/null 2>&1 && declare -F cur8_unapproved_line >/dev/null 2>&1 || exit 1
    cur8_unapproved_line )
}

# _card_review_fact, _card_review_failing -> the fact of the evidence gate's refusal while an owed review question is
# unanswered, and the printf format of its line for a question whose newest review fails, as the wall spells them
# (payload/scripts/lib/walls.sh `eg_review_unanswered_fact`, `eg_review_failing_line`), read in a subshell. Nothing
# when walls.sh cannot be loaded, and then no line is settled as that refusal, so the page stays early.
_card_review_fact() {
  ( . "${CARD_SELF_DIR}/lib/walls.sh" >/dev/null 2>&1 && declare -F eg_review_unanswered_fact >/dev/null 2>&1 || exit 1
    eg_review_unanswered_fact )
}
_card_review_failing() {
  ( . "${CARD_SELF_DIR}/lib/walls.sh" >/dev/null 2>&1 && declare -F eg_review_failing_line >/dev/null 2>&1 || exit 1
    eg_review_failing_line )
}

# _card_fmt_is <format> <line> -> 0 when <line> is <format> with each %s standing for any text. Each piece between the
# placeholders is matched as a literal, so no character of the judge's words is read as a pattern.
_card_fmt_is() {
  local f="$1" l="$2" m='%s' p
  [ -n "$f" ] || return 1
  p="${f%%"$m"*}"
  case "$l" in "$p"*) l="${l#"$p"}" ;; *) return 1 ;; esac
  f="${f#"$p"}"
  while [ -n "$f" ]; do
    f="${f#"$m"}"
    [ -n "$f" ] || return 0
    case "$f" in
      *"$m"*) p="${f%%"$m"*}" ;;
      *) case "$l" in *"$f") return 0 ;; *) return 1 ;; esac ;;
    esac
    case "$l" in *"$p"*) l="${l#*"$p"}" ;; *) return 1 ;; esac
    f="${f#"$p"}"
  done
  [ -z "$l" ]
}

# _card_settles <a red check's output> -> 0 when each refusal it prints is settled by a decision the page puts, the
# items appended to CF_SETTLE (`waive:<q>`, `row:<AC>`); 1 at the first refusal none settles. THE PAGE'S OWN
# DEFAULTS: a matrix row the auditor has not confirmed (waived with the user's words, `waive-row`), a T4 row whose
# user has not yet confirmed its check, its block's confirmation still a placeholder (confirmed, `confirm-row`, or
# waived), and a question whose newest reading fails (`waive <q>`). A placeholder of any other key is early: it is
# evidence that was never recorded. Anything else the check prints is early: a missing or red whole run (the
# regression is run before review and is never waived), a missing proof, another refused dry commit, an uncovered or
# absent reading, a declared check or debt not held, a judge that could not deal the plan. The dry commit stops at
# its first refusal, so a check names one wall at a time; the judge at 8 runs no dry commit and names every fact it
# finds, and the rows are read from the matrix, so the page puts each of them whichever refusal the dry commit
# stopped on. In the release order the advance to 8 refuses first on the missing release approval (no `approved:
# release` line, or one naming no head), before it reads any other fact: that approval is the page's own decision, so
# it is settled (`approve:release`) and the page is early only for what the advances to 6 and 7 print. That refusal is
# known by the judge's own format (`_card_unapproved`), never by a second spelling of its words here. The advance
# prints no refusal for the merge approval, so none is read here. The wall's refusal for an unanswered review question,
# and its line for a failing one, are known the same way, by the wall's own spellings (`_card_review_fact`,
# `_card_review_failing`).
_card_settles() {
  local l q k judge=0 reading=0 any=0 unap rfact rfail
  local -a _cs_f=()
  unap="$(_card_unapproved)"
  rfact="$(_card_review_fact)"; rfail="$(_card_review_failing)"
  while IFS= read -r l; do
    if [ -n "$unap" ] && _card_fmt_is "poker: $unap" "$l"; then CF_SETTLE="${CF_SETTLE}approve:release"$'\n'; any=1; continue; fi
    if [ -n "$rfact" ]; then
      case "$l" in "bionic: commit refused — $rfact "*) reading=1; any=1; continue ;; esac
    fi
    if [ "$reading" = 1 ] && [ -n "$rfail" ] && _card_fmt_is "$rfail" "$l"; then
      q="${l#- }"; q="${q%%:*}"; CF_SETTLE="${CF_SETTLE}waive:$q"$'\n'; continue
    fi
    case "$l" in
      "bionic: commit refused — the auditor has not confirmed "*)
        q="${l#bionic: commit refused — the auditor has not confirmed }"; q="${q%% *}"
        CF_SETTLE="${CF_SETTLE}row:$q"$'\n'; any=1 ;;
      "bionic: commit refused — "*" has placeholder "*" evidence (record what actually ran)")
        q="${l#bionic: commit refused — }"; k="${q#* has placeholder }"; k="${k%% evidence (*}"; q="${q%% *}"
        [ "$k" = "$(_card_t4_confirm_key)" ] || return 1
        CF_SETTLE="${CF_SETTLE}row:$q"$'\n'; any=1 ;;
      "bionic: "*) return 1 ;;
      "- "*) [ "$reading" = 1 ] && return 1 ;;
      "poker: current "*" --check: would refuse"|"poker: REFUSED — the commit gate refused the plan with current: "*) : ;;
      "poker: REFUSED — current: "*", and these do not (facts_state):") judge=1; any=1 ;;
      "poker: REFUSED"*) return 1 ;;
      *"	"*)
        [ "$judge" = 1 ] || continue
        IFS='	' read -r -a _cs_f <<< "$l"
        case "${_cs_f[0]}" in
          review)
            [ "${_cs_f[4]:-}" = failing ] || return 1
            CF_SETTLE="${CF_SETTLE}waive:${_cs_f[1]}"$'\n' ;;
          *) return 1 ;;
        esac ;;
    esac
  done <<CF_CHECKED
$1
CF_CHECKED
  [ "$any" = 1 ]
}

# ── THE RELEASE APPROVAL CARD ────────────────────────────────────────────────
#
# The release-approval verb (hooks/poker/plan.sh) gathers what the run reached and what is the user's; this file
# draws it, so the release card folds at the width every other card folds at and no second renderer drifts from it.
# The facts come on stdin, one per line, a tag then its fields, every field separated by a tab:
#
#   title       <project> <release> <clock> <head8> <tasks landed> <tasks>
#   early       <why the card is early>          preview          (a fact each, at most once)
#   criteria    <in the matrix> <waived by you>  miss <AC>        (a miss per criterion not proved)
#   check       <path>                           (one per file of the declared release check the release changes)
#   aside       <an item of the user's outside the run>
#   decision    <kind> <key> <default|other> <subject> <default label> <other label> <default phrase> <other phrase>
#   reply       <the word a reply names the first decision's other choice by>
#   goal        <status> <mark> <name> <reading> <evidence>
#   handholds | ratio | acceptance | regression | review   <the line, as the verb words it>
#   findings    <n> <fixed> <awaiting your decision> <carried> <the rows that fix them, space-separated>
#   finding     <F|A|C> <severity> <sentence>
#
# Decisions, misses, goals, reviews and findings print in the order they came. A fact the renderer does not know,
# or no title, refuses the card (64, nothing drawn): a card that silently dropped a fact would ask the user to
# approve less than the record holds.

# A line folded at BIONIC_LINE_WIDTH: a wider one breaks at its last space that fits, each continuation opening on
# <hang> spaces. Unlike bionic_wrap it keeps the spaces inside the line, which align a finding under its severity
# code. A word wider than the room prints whole.
_card_hang() {  # <hang> <text>
  local text="${2:-}" pad lead rest word line more=1
  _bionic_cols_into "$text"
  if [ "$BIONIC_COLS" -le "$BIONIC_LINE_WIDTH" ]; then printf '%s\n' "$text"; return 0; fi
  pad="$(_card_spaces "${1:-0}")"
  rest="${text#"${text%%[! ]*}"}"; lead="${text%"$rest"}"
  case "$rest" in *' '*) line="$lead${rest%% *}"; rest="${rest#* }" ;; *) line="$text"; more=0 ;; esac
  while [ "$more" = 1 ]; do
    case "$rest" in *' '*) word="${rest%% *}"; rest="${rest#* }" ;; *) word="$rest"; more=0 ;; esac
    _bionic_cols_into "$line $word"
    if [ "$BIONIC_COLS" -le "$BIONIC_LINE_WIDTH" ]; then line="$line $word"
    else _card_rstrip "$line"; printf '\n'; line="$pad$word"; fi
  done
  printf '%s\n' "$line"
}

_card_list() {  # <cap> <word>... -> `A`, `A and B`, `A, B and C`, the first <cap> named and the rest counted
  local cap="$1"; shift
  awk -v cap="$cap" 'BEGIN {
    n = ARGC - 1; if (n < 1) exit
    m = (n > cap) ? cap : n
    for (i = 1; i <= m; i++) s = s ((i == 1) ? "" : ((i == m && n == m) ? " and " : ", ")) ARGV[i]
    if (n > m) s = s " and " (n - m) " more"
    print s }' "$@"
}

_card_plural() {  # <n> <singular> <plural> -> `<n> <word>`
  if [ "$1" -eq 1 ]; then printf '1 %s' "$2"; else printf '%s %s' "$1" "$3"; fi
}

_card_release_dec_of() {  # <key> -> the decision number the card gives it; 1 when none
  local i=0
  while [ "$i" -lt "$RL_N" ]; do
    [ "${RL_DKEY[$i]}" != "$1" ] || { printf '%s' "$((i + 1))"; return 0; }
    i=$((i + 1))
  done
  return 1
}

_card_release_read() {  # facts on stdin -> the RL_* facts; 64 and a line on stderr on a fact it does not know
  local l t title=0
  RL_EARLY=""; RL_PREVIEW=no; RL_ACT=0; RL_ACW=0; RL_REPLY=""; RL_N=0; RL_HH=""; RL_TR=""; RL_TACC=""; RL_TREG=""
  RL_FN=0; RL_FNF=0; RL_FNA=0; RL_FNC=0; RL_FROWS=""
  RL_MISS=(); RL_CHK=(); RL_ASIDE=(); RL_GOAL=(); RL_REVIEW=(); RL_FIND=()
  RL_DKIND=(); RL_DKEY=(); RL_DPICK=(); RL_DSUBJ=(); RL_DLAB=(); RL_OLAB=(); RL_DPH=(); RL_OPH=()
  while IFS= read -r l || [ -n "$l" ]; do
    [ -n "$l" ] || continue
    _card_split "$l"; t="${CARD_CELLS[0]}"
    case "$t" in
      title)
        RL_PROJ="${CARD_CELLS[1]:-}"; RL_REL="${CARD_CELLS[2]:-}"; RL_CLOCK="${CARD_CELLS[3]:-}"; RL_H8="${CARD_CELLS[4]:-}"
        RL_LANDED="${CARD_CELLS[5]:-0}"; RL_TOTAL="${CARD_CELLS[6]:-0}"; title=1 ;;
      early) RL_EARLY="${CARD_CELLS[1]:-}" ;;
      preview) RL_PREVIEW=yes ;;
      criteria) RL_ACT="${CARD_CELLS[1]:-0}"; RL_ACW="${CARD_CELLS[2]:-0}" ;;
      miss) RL_MISS[${#RL_MISS[@]}]="${CARD_CELLS[1]:-}" ;;
      check) RL_CHK[${#RL_CHK[@]}]="${CARD_CELLS[1]:-}" ;;
      aside) RL_ASIDE[${#RL_ASIDE[@]}]="${CARD_CELLS[1]:-}" ;;
      decision)
        RL_DKIND[RL_N]="${CARD_CELLS[1]:-}"; RL_DKEY[RL_N]="${CARD_CELLS[2]:-}"; RL_DPICK[RL_N]="${CARD_CELLS[3]:-default}"
        RL_DSUBJ[RL_N]="${CARD_CELLS[4]:-}"; RL_DLAB[RL_N]="${CARD_CELLS[5]:-}"; RL_OLAB[RL_N]="${CARD_CELLS[6]:-}"
        RL_DPH[RL_N]="${CARD_CELLS[7]:-}"; RL_OPH[RL_N]="${CARD_CELLS[8]:-}"; RL_N=$((RL_N + 1)) ;;
      reply) RL_REPLY="${CARD_CELLS[1]:-}" ;;
      goal) RL_GOAL[${#RL_GOAL[@]}]="${l#goal"$CARD_TAB"}" ;;
      handholds) RL_HH="${CARD_CELLS[1]:-}" ;;
      ratio) RL_TR="${CARD_CELLS[1]:-}" ;;
      acceptance) RL_TACC="${CARD_CELLS[1]:-}" ;;
      regression) RL_TREG="${CARD_CELLS[1]:-}" ;;
      review) RL_REVIEW[${#RL_REVIEW[@]}]="${CARD_CELLS[1]:-}" ;;
      findings)
        RL_FN="${CARD_CELLS[1]:-0}"; RL_FNF="${CARD_CELLS[2]:-0}"; RL_FNA="${CARD_CELLS[3]:-0}"; RL_FNC="${CARD_CELLS[4]:-0}"
        RL_FROWS="${CARD_CELLS[5]:-}" ;;
      finding) RL_FIND[${#RL_FIND[@]}]="${l#finding"$CARD_TAB"}" ;;
      *) printf "card.sh: unknown release fact '%s' — card.sh release takes the facts its header names\n" "$t" >&2; return 64 ;;
    esac
  done
  [ "$title" = 1 ] || { printf 'card.sh: release: no title fact, so there is no card to draw\n' >&2; return 64; }
}

# The Bottom line: whether every check holds, what the release changes of its own check, the criteria not proved,
# what is owed, the recommendation. One phrase per decision, the rows' said once per choice over their criteria, the
# approvals given last.
_card_release_bottom() {
  local i p l n
  local -a ph=() ap=() cf=() wv=() rn=() nums=()
  if [ -n "$RL_EARLY" ]; then _card_hang 2 "- Not ready for your decisions: $RL_EARLY."
  elif [ "$RL_N" -gt 0 ]; then _card_hang 2 "- Ready for your decisions: every check holds at $RL_H8."
  else _card_hang 2 "- Every check holds at $RL_H8."; fi
  [ "${#RL_CHK[@]}" -eq 0 ] || _card_hang 2 "- This release changes the release check: $(_card_list 6 "${RL_CHK[@]}")."
  if [ "${#RL_MISS[@]}" -gt 0 ]; then
    l="$(_card_plural "${#RL_MISS[@]}" criterion criteria) not proved: $(_card_list 6 "${RL_MISS[@]}")"
    for p in "${RL_MISS[@]}"; do n="$(_card_release_dec_of "row:$p")" && nums[${#nums[@]}]="$n"; done
    # A run of decision numbers is said as a range.
    if [ "${#nums[@]}" -eq 1 ]; then l="$l (decision ${nums[0]})"
    elif [ "${#nums[@]}" -gt 1 ]; then
      n="${nums[$(( ${#nums[@]} - 1 ))]}"
      if [ "$(( n - nums[0] + 1 ))" -eq "${#nums[@]}" ]; then l="$l (decisions ${nums[0]} to $n)"
      else l="$l (decisions $(_card_list 6 "${nums[@]}"))"; fi
    fi
    _card_hang 2 "- $l."
  elif [ "$RL_ACW" -gt 0 ]; then _card_hang 2 "- Every criterion is proved or waived by you."
  elif [ "$RL_ACT" -gt 0 ]; then _card_hang 2 "- Every criterion is proved."
  else _card_hang 2 "- The matrix holds no criterion."; fi
  # An early run puts no decision: the acting render refuses it, so a preview says what the user will owe, never that
  # they owe it now, and the card says one thing.
  if [ "$RL_N" -gt 0 ] && [ -n "$RL_EARLY" ]; then
    _card_hang 2 "- Once the run is ready, you will owe $(_card_plural "$RL_N" decision decisions), listed below. Everything else has a default the record supports."
  elif [ "$RL_N" -gt 0 ]; then
    _card_hang 2 "- You owe $(_card_plural "$RL_N" decision decisions), listed below. Everything else has a default the record supports."
  else
    _card_hang 2 "- You owe nothing: every approval and waiver is recorded."
  fi
  i=0
  while [ "$i" -lt "${#RL_ASIDE[@]}" ]; do _card_hang 2 "- Also yours, outside the run: ${RL_ASIDE[$i]%.}."; i=$((i + 1)); done
  [ "$RL_N" -gt 0 ] || return 0
  for ((i = 0; i < RL_N; i++)); do
    if [ "${RL_DKIND[$i]}" = approve ] && [ "${RL_DPICK[$i]}" = default ]; then ap[${#ap[@]}]="${RL_DKEY[$i]#approve:}"
    elif [ "${RL_DKIND[$i]}" = row ]; then
      if [ "${RL_DPICK[$i]}" = default ]; then p="${RL_DPH[$i]}"; else p="${RL_OPH[$i]}"; fi
      case "${p%% *}" in
        confirm) cf[${#cf[@]}]="${RL_DKEY[$i]#row:}" ;;
        waive) wv[${#wv[@]}]="${RL_DKEY[$i]#row:}" ;;
        *) rn[${#rn[@]}]="${RL_DKEY[$i]#row:}" ;;
      esac
    elif [ "${RL_DPICK[$i]}" = default ]; then ph[${#ph[@]}]="${RL_DPH[$i]}"
    else ph[${#ph[@]}]="${RL_OPH[$i]}"; fi
    if [ "${RL_DKIND[$i]}" = row ] && { [ "$((i + 1))" -eq "$RL_N" ] || [ "${RL_DKIND[$((i + 1))]}" != row ]; }; then
      [ "${#cf[@]}" -eq 0 ] || ph[${#ph[@]}]="confirm $(_card_list 6 "${cf[@]}")"
      [ "${#wv[@]}" -eq 0 ] || ph[${#ph[@]}]="waive $(_card_list 6 "${wv[@]}")"
      [ "${#rn[@]}" -eq 0 ] || ph[${#ph[@]}]="run $(_card_list 6 "${rn[@]}")"
    fi
  done
  l=""
  for ((i = 0; i < ${#ph[@]}; i++)); do l="${l:+$l, }${ph[$i]}"; done
  [ "${#ap[@]}" -eq 0 ] || l="${l:+$l, then }$(_card_list 6 "${ap[@]}")"
  _card_hang 2 "- Recommended: $l."
}

_card_release() {  # facts on stdin -> the release approval card; 64 when the facts refuse
  local i g lab r=0 lines="" sent
  _card_release_read || return 64
  _card_hang 0 "Release approval · ${RL_PROJ}${RL_REL:+ $RL_REL} · $RL_CLOCK · head $RL_H8$([ "$RL_TOTAL" -gt 0 ] && printf ' · %d of %d tasks landed' "$RL_LANDED" "$RL_TOTAL")"
  printf '\nBottom line\n'
  _card_release_bottom
  printf '\n'
  if [ "${#RL_GOAL[@]}" -eq 0 ]; then
    printf 'Goals — none declared\n'
  else
    for ((i = 0; i < ${#RL_GOAL[@]}; i++)); do
      _card_split "${RL_GOAL[$i]}"
      [ "${CARD_CELLS[0]}" != reached ] || r=$((r + 1))
      lines="${lines}${CARD_CELLS[1]:-} ${CARD_CELLS[2]:-} — ${CARD_CELLS[3]:-}, ${CARD_CELLS[4]:-}"$'\n'
    done
    printf 'Goals — %d of %d reached\n' "$r" "${#RL_GOAL[@]}"
    while IFS= read -r g; do [ -z "$g" ] || _card_hang 3 "$g"; done <<< "$lines"
  fi
  if [ -n "$RL_HH" ] || [ -n "$RL_TR" ]; then
    printf '\n'
    [ -z "$RL_HH" ] || _card_hang 3 "$RL_HH"
    [ -z "$RL_TR" ] || _card_hang 3 "$RL_TR"
  fi
  printf '\nTests\n'
  _card_hang 3 "$RL_TACC"; _card_hang 3 "$RL_TREG"
  printf '\nReviews\n'
  for ((i = 0; i < ${#RL_REVIEW[@]}; i++)); do [ -z "${RL_REVIEW[$i]}" ] || _card_hang 3 "${RL_REVIEW[$i]}"; done
  printf '\n'
  if [ "$RL_FN" -eq 0 ]; then
    printf 'Findings — none\n'
  else
    lab=""
    [ "$RL_FNF" -eq 0 ] || lab="$RL_FNF fixed"
    [ "$RL_FNA" -eq 0 ] || lab="${lab:+$lab · }$RL_FNA for your decision"
    [ "$RL_FNC" -eq 0 ] || lab="${lab:+$lab · }$RL_FNC carried"
    _card_hang 0 "Findings — $RL_FN: $lab"
    for g in F A C; do
      lines=""
      for ((i = 0; i < ${#RL_FIND[@]}; i++)); do
        _card_split "${RL_FIND[$i]}"
        [ "${CARD_CELLS[0]}" != "$g" ] || lines="${lines}  ${CARD_CELLS[1]:-}   ${CARD_CELLS[2]:-}"$'\n'
      done
      [ -n "$lines" ] || continue
      case "$g" in
        F) lab="Fixed"
           # shellcheck disable=SC2086  # the fixing rows, one word each
           [ -z "$RL_FROWS" ] || lab="Fixed by $(_card_list 6 $RL_FROWS)" ;;
        A) lab="Awaiting your decision" ;;
        C) lab="Carried as known limits" ;;
      esac
      _card_hang 0 "$lab"
      while IFS= read -r sent; do [ -z "$sent" ] || _card_hang 7 "$sent"; done <<< "$lines"
    done
  fi
  printf '\nDecisions\n'
  if [ "$RL_N" -eq 0 ]; then
    printf 'None wait on you.\n'
  else
    for ((i = 0; i < RL_N; i++)); do
      if [ "${RL_DPICK[$i]}" = default ]; then lab="${RL_DLAB[$i]}"; else lab="${RL_OLAB[$i]}"; fi
      _card_hang 3 "$((i + 1)). ${RL_DSUBJ[$i]} — recommended: $lab · default: ${RL_DLAB[$i]}"
    done
  fi
  if [ "$RL_PREVIEW" = yes ]; then
    printf '\nPreview only: nothing is recorded, and reply cannot act on it.\n'
  elif [ "$RL_N" -gt 0 ]; then
    printf '\n'
    _card_hang 0 "Reply \"all recommended\", \"all default\", or by number, as \"1 $RL_REPLY, rest default\"."
  fi
}

# ── THE SITREP CARD ──────────────────────────────────────────────────────────
#
# The sitrep verb (hooks/poker/sitrep.sh) gathers the run's facts into the sheet and names its file; the model writes
# every row of the card as the judgment, which comes on stdin, one tagged line each:
#
#   call: <row>                                       one or more: what the user should do now
#   task: <label>: <text>                             the Task list, in the sheet's step order
#   metric: <Label>: <text>                           five: Completed, Pace, Correctness, Waste, Goals, in that order
#   grade: <A-F>                                      one
#   point: <row>                                      one to five: the Assessment's rows
#   ask <key>[, <key>...]: <what> — recommend <answer>   every ask open on the sheet answered once; one row may answer
#                                                     several keys that are one decision
#   ask +: <row>                                      any number: an ask the register lacks
#   close: <row>                                      one to three: the predicted close and what it depends on
#
# A task label is a step `N`, a task `N/x` (its id without the T) or a range of one step's tasks `N/a–N/b`.
#
# The facts are the sheet's and the words the model's: the renderer draws the head, the seven sections in this order
# (the head; Call to action; Task list; Metrics; Assessment: <grade>; Blocked on you; Predicted close), a label at 2
# columns and its rows at 4, each opening on a bullet, or in the Task list on its icon, and capitalizes each row's
# first letter. A task row's icon is the sheet's: done when its step is done with no open task, its task is done, or
# every task of its range is done. A row too wide folds under its own text; a task row is one line.
#
# THE CHECK. Nothing prints until the judgment and the drawn text both pass, because a card that drops or contradicts
# a fact would tell the user something the run does not hold. The judgment is refused when its Task list leaves out a
# step on the sheet, names a label the sheet does not hold, runs out of the sheet's step order, or writes a task's row
# in words its state on the sheet contradicts (an open task landed, a done one waiting); when its metrics are not
# the five in their order, or one states a number (each run of digits) that no measured value of its own lines holds,
# or gives a goal status another count than the goal: lines hold; when no close row names the sheet's predicted
# close; when its call says nothing is owed while an ask is open, or names a register key while none is; when it
# leaves an open ask unanswered or answers one twice, names a key the register lacks, or writes an ask row that does
# not name the label of every task its keys hold, or with no recommended answer, or as a decision's options; when it
# grades outside A to F, has no call, no point or more than five, no close or more than three, a tag the card does
# not know, or a refused word (reader, readers, reading, readings, unmeasured). The drawn text (`_card_sitrep_check`, also `card.sh sitrep-check`, so a planted card can
# prove each test) is refused for a line over BIONIC_LINE_WIDTH, a row with no bullet or icon, the sections out of
# their order or one with no row, a step row above its own tasks, a Task list row spanning two lines, and an open task
# with no row or two. A refusal prints every reason on stderr and nothing on stdout.
CARD_SITREP_NOTHING="Nothing: no decision or action is owed right now."
CARD_SITREP_SECTIONS="Call to action|Task list|Metrics|Assessment|Blocked on you|Predicted close"
CARD_SITREP_METRICS="Completed Pace Correctness Waste Goals"
# The sheet lines each metric is written from, `<Label>=<key>`, a key ending `.*` naming every line under its prefix.
# Goals is written from the goal: lines' counts by status, which _card_sitrep_load counts.
CARD_SITREP_MLINES="Completed=work.landed Completed=work.left Pace=pace.work-landed Pace=pace.time-used Pace=work.added \
Correctness=tests.* Correctness=reviews Correctness=findings.open Waste=waste.*"

# _card_sitrep_sheet <sheet file> -> its facts as tab-separated records, in the sheet's order: `R <key> <value>` per
# run. and close. fact; `S <n> <name> <state> <tasks>` per step; `T <id> <step> <state> <desc> <note>` per
# task; `A <key> <holds> <title> <raised>` per ask. A list line's value runs to the next field's ` <name>=`. A measured
# line names what it measures after its value, `<value> — <what it measures> · unit: …`; its value is the part before.
_card_sitrep_sheet() {
  awk '
    function fv(b, f, nxt,   s, r, e) {
      s = index(b, " " f "="); if (!s) return ""
      r = substr(b, s + length(f) + 2)
      if (nxt != "") { e = index(r, " " nxt "="); if (e) r = substr(r, 1, e - 1) }
      return r
    }
    function rec(tag, kind, fields,   b, n, a, i, out) {
      b = " " substr($0, length(kind) + 3); n = split(fields, a, " "); out = tag
      for (i = 1; i <= n; i++) out = out "\t" fv(b, a[i], (i < n) ? a[i + 1] : "")
      print out
    }
    /^(run|close)\.[A-Za-z.-]+: / { k = $0; sub(/: .*$/, "", k); v = substr($0, length(k) + 3); i = index(v, " — "); if (i) v = substr(v, 1, i - 1)
      print "R\t" k "\t" v; next }
    index($0, "step: ") == 1 { rec("S", "step", "n name state tasks"); next }
    index($0, "task: ") == 1 { rec("T", "task", "id step state desc note"); next }
    index($0, "ask: ") == 1 { rec("A", "ask", "key holds title raised"); next }' "$1"
}

# _card_sitrep_fact <key> -> the sheet's value for a run. or close. key in SR_RECS, `-` when it has none
_card_sitrep_fact() {
  printf '%s\n' "$SR_RECS" | awk -F'\t' -v k="$1" '$1 == "R" && $2 == k { v = $3; f = 1; exit } END { print (f && v != "") ? v : "-" }'
}

# _card_sitrep_names <text> <id>... -> 0 when the text names one of the ids as a whole word: no letter, digit or _ on
# either side, so 4/80 never names 4/8
_card_sitrep_names() {
  local text="$1"; shift
  printf '%s\n' "$text" | awk -v ids="$*" '
    function edge(c) { return c == "" || c !~ /[A-Za-z0-9_]/ }
    { t = t $0 "\n" }
    END {
      n = split(ids, w, " ")
      for (i = 1; i <= n; i++) {
        s = t; off = 0
        while ((p = index(s, w[i])) > 0) {
          if (edge(substr(t, off + p - 1, 1)) && edge(substr(t, off + p + length(w[i]), 1))) exit 0
          off += p; s = substr(s, p + 1)
        }
      }
      exit 1 }'
}

# _card_sitrep_cap <text> -> the text, its first letter capitalized when it is a to z. The letters are spelled out,
# never a range, so a locale that collates A inside a-z cannot drop a capital.
_card_sitrep_cap() {
  local lo=abcdefghijklmnopqrstuvwxyz up=ABCDEFGHIJKLMNOPQRSTUVWXYZ c="${1:0:1}" p
  case "$c" in ''|*[!abcdefghijklmnopqrstuvwxyz]*) printf '%s' "$1"; return 0 ;; esac
  p="${lo%%"$c"*}"
  printf '%s%s' "${up:${#p}:1}" "${1:1}"
}

# _card_sitrep_tasks_judge -> SJ_TDONE (1 when a task row's label is done on the sheet) and every refusal of the Task
# list in SJ_WHY: a label the sheet does not hold, a range across steps, a row out of the sheet's step order, a step
# with no row; a task's own row whose words contradict its state on the sheet. A range's tasks are its step's tasks
# numbered from one end to the other, or, when a label is not a number, the tasks between its two ends in the
# sheet's order.
#
# A row for one task that is not done never says landed, done, finished, merged or green, and a done task's row never
# says building, waiting, held or running. The task's own description is cut from the row before the words are
# looked for, so a row may copy it, and a word after "not", "not yet" or "never" is not a claim. A step row or a range
# may hold done and open tasks at once, so neither is read.
_card_sitrep_tasks_judge() {
  local i out tag val
  SJ_TDONE=()
  out="$( { printf '%s\n' "$SR_RECS"; for ((i = 0; i < ${#SJ_TLAB[@]}; i++)); do printf 'J\t%s\t%s\n' "${SJ_TLAB[$i]}" "${SJ_TTXT[$i]}"; done; } \
    | awk -F'\t' -v dash="–" '
    function lab(id) { return (substr(id, 1, 1) == "T") ? substr(id, 2) : id }
    function num(x) { return x ~ /^[0-9]+$/ }
    function why(m) { print "W\t" m }
    # said(<text> <words>) -> the first of the words the text says as a whole word, not after a negation, or ""
    function said(t, words,   n, w, i, s, off, p, b) {
      n = split(words, w, " ")
      for (i = 1; i <= n; i++) {
        s = t; off = 0
        while ((p = index(s, w[i])) > 0) {
          b = substr(t, 1, off + p - 1)
          if (substr(t, off + p - 1, 1) !~ /[a-z0-9_]/ && substr(t, off + p + length(w[i]), 1) !~ /[a-z0-9_]/ \
            && b !~ /(^|[^a-z])(not|not yet|never) $/) return w[i]
          off += p; s = substr(s, p + 1)
        }
      }
      return ""
    }
    $1 == "S" { ns++; sn[ns] = $2; at[$2] = ns; nm[$2] = $3; ss[$2] = $4; next }
    $1 == "T" { nt++; ts[nt] = $3; tl[nt] = lab($2); td[nt] = ($4 == "done"); tk[$3 "/" lab($2)] = nt; tst[nt] = $4; tds[nt] = $5
      if ($4 != "done") opn[$3] = 1; next }
    $1 == "J" { nj++; jl[nj] = $2; jt[nj] = $3 }
    END {
      last = 0
      for (i = 1; i <= nj; i++) {
        l = jl[i]; dn = 0; st = ""
        if (num(l)) {
          if (!(l in at)) why("the task row " l ": names a step the sheet does not hold")
          else { st = l; dn = (ss[l] == "done" && !(l in opn)) }
        } else if ((d = index(l, dash)) > 0) {
          a = substr(l, 1, d - 1); b = substr(l, d + length(dash))
          if (!(a in tk) || !(b in tk) || ts[tk[a]] != ts[tk[b]])
            why("the task row " l ": is no range the sheet holds: a range runs from one task of a step to another of the same step, as 4/1" dash "4/9")
          else {
            st = ts[tk[a]]; x = tl[tk[a]]; y = tl[tk[b]]; dn = 1
            if (num(x) && num(y)) {
              lo = (x + 0 < y + 0) ? x + 0 : y + 0; hi = (x + 0 < y + 0) ? y + 0 : x + 0
              for (j = 1; j <= nt; j++) if (ts[j] == st && num(tl[j]) && tl[j] + 0 >= lo && tl[j] + 0 <= hi && !td[j]) dn = 0
            } else {
              lo = (tk[a] < tk[b]) ? tk[a] : tk[b]; hi = (tk[a] < tk[b]) ? tk[b] : tk[a]
              for (j = lo; j <= hi; j++) if (ts[j] == st && !td[j]) dn = 0
            }
          }
        } else if (index(l, "/") > 0) {
          if (!(l in tk)) why("the task row " l ": names a task the sheet does not hold")
          else {
            st = ts[tk[l]]; dn = td[tk[l]]
            t = tolower(jt[i]); d = tolower(tds[tk[l]])
            if (d != "" && (p = index(t, d)) > 0) t = substr(t, 1, p - 1) " " substr(t, p + length(d))
            if (dn && (w = said(t, "building waiting held running")) != "")
              why("the task row " l ": says \"" w "\", and the sheet holds " l " as done: a finished task never says building, waiting, held or running")
            else if (!dn && (w = said(t, "landed done finished merged green")) != "")
              why("the task row " l ": says \"" w "\", and the sheet holds " l " as " tst[tk[l]] ": an open task says what it waits on, never landed, done, finished, merged or green")
          }
        } else why("the task row \"" l "\" has no label: write it as task: <step>: <text>, task: <step>/<task>: <text> or task: <step>/<a>" dash "<step>/<b>: <text>")
        print "D\t" dn
        if (st != "") {
          cov[st] = 1; o = (st in at) ? at[st] : ns + 1
          if (o < last) why("the task row " l ": comes after a row of a later step: the Task list runs in step order, as the sheet lists the steps")
          else last = o
        }
      }
      for (k = 1; k <= ns; k++) if (!(sn[k] in cov))
        why("the step " sn[k] " (" nm[sn[k]] ") has no row on the Task list: write it by its own label " sn[k] ", by one of its tasks or by a range of them")
    }')"
  while IFS="$CARD_TAB" read -r tag val; do
    case "$tag" in
      D) SJ_TDONE[${#SJ_TDONE[@]}]="$val" ;;
      W) SJ_WHY="$SJ_WHY$val"$'\n' ;;
    esac
  done <<< "$out"
}

# _card_sitrep_metrics_judge -> every refusal of the Metrics in SJ_WHY: the five labels once each in their order;
# every number a metric row states (each run of digits, so 5:46 is 5 and 46) one its own lines measure, SR_MNUMS; and
# each count a Goals row puts on a goal status that status's own count
_card_sitrep_metrics_judge() {
  local i m got="" miss="" bad=""
  for ((i = 0; i < ${#SJ_MLAB[@]}; i++)); do
    m="${SJ_MLAB[$i]}"
    case " $CARD_SITREP_METRICS " in
      *" $m "*) case " $got " in *" $m "*) bad=1; SJ_WHY="${SJ_WHY}metric: $m: is written twice: each metric has one row"$'\n' ;; esac ;;
      *) bad=1; SJ_WHY="${SJ_WHY}metric: ${m:0:30}: is no metric of the card: its metrics are $CARD_SITREP_METRICS"$'\n' ;;
    esac
    got="${got:+$got }$m"
  done
  for m in $CARD_SITREP_METRICS; do
    case " $got " in *" $m "*) ;; *) miss="${miss:+$miss, }$m" ;; esac
  done
  [ -z "$miss" ] || SJ_WHY="${SJ_WHY}the judgment has no metric row for $miss: the Metrics are $CARD_SITREP_METRICS, one row each"$'\n'
  [ -n "$miss" ] || [ -n "$bad" ] || [ "$got" = "$CARD_SITREP_METRICS" ] \
    || SJ_WHY="${SJ_WHY}the metrics run $got: the card has them in the order $CARD_SITREP_METRICS"$'\n'
  # A Goals row's count of a status is that status's count and its of-count the total: in "3 of 3 met" with 1 met,
  # every number is one the goal: lines hold, so only binding each count to its status refuses it.
  m="$( { printf '%s\n' "$SR_MNUMS"; for ((i = 0; i < ${#SJ_MLAB[@]}; i++)); do printf 'J\t%s\t%s\n' "${SJ_MLAB[$i]}" "${SJ_MTXT[$i]}"; done; } \
    | awk -F'\t' -v lines="$CARD_SITREP_MLINES" '
    function strip(x) { sub(/^0+/, "", x); return (x == "") ? "0" : x }
    BEGIN { n = split(lines, a, " ")
      for (i = 1; i <= n; i++) { c = index(a[i], "="); l = substr(a[i], 1, c - 1); from[l] = from[l] (from[l] == "" ? "" : ", ") substr(a[i], c + 1) }
      from["Goals"] = "the counts of the goal: lines"
      split("met|not met|not measured|unreadable", gs, "|"); for (i in gs) gc[gs[i]] = 0 }
    $1 == "N" { h[$2 SUBSEP $3] = 1; next }
    $1 == "G" { if ($2 == "total") gt = $3; else if ($2 in gc) gc[$2] = $3; next }
    $1 != "J" || !($2 in from) { next }
    $2 == "Goals" && !gd++ { h["Goals" SUBSEP strip(gt)] = 1; for (s in gc) h["Goals" SUBSEP gc[s]] = 1 }
    { s = $3
      while (match(s, /[0-9]+/)) {
        x = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH); y = strip(x)
        if (!(($2 SUBSEP y) in h) && !seen[$2 SUBSEP y]++)
          printf "metric %s: says %s, a number its own lines (%s) do not hold: a metric states the measured values of the lines it is written from\n", $2, x, from[$2]
      } }
    $2 == "Goals" { s = tolower($3)
      while (match(s, /[0-9]+ (of [0-9]+ )?(goals? )?(are |is )?(not met|not measured|met|missed|unreadable)/)) {
        t = substr(s, RSTART, RLENGTH); nx = substr(s, RSTART + RLENGTH, 1); s = substr(s, RSTART + RLENGTH)
        if (nx ~ /[a-z]/) continue
        match(t, /^[0-9]+/); c = strip(substr(t, 1, RLENGTH))
        st = t; sub(/^[0-9]+ (of [0-9]+ )?(goals? )?(are |is )?/, "", st); if (st == "missed") st = "not met"
        if (c != gc[st] "") printf "metric Goals: says %s %s, and the goal: lines hold %s %s: a status gets its own count\n", c, st, gc[st], st
        if (match(t, /of [0-9]+ /)) { o = strip(substr(t, RSTART + 3, RLENGTH - 4))
          if (o != gt "") printf "metric Goals: says %s of %s %s, and the sheet holds %s goals: the of-count is every goal\n", c, o, st, gt + 0 }
      } }')"
  [ -z "$m" ] || SJ_WHY="$SJ_WHY$m"$'\n'
}

# _card_sitrep_judge -> the judgment on stdin read into SJ_*, every refusal of it one line in SJ_WHY. Reads the open
# asks from SR_AKEY and SR_AHOLDS, what each metric may say from SR_MNUMS.
_card_sitrep_judge() {
  local l v key k ks i j m n pred hit lb text="" seen=" "
  SJ_CALL=(); SJ_POINT=(); SJ_GRADE=""; SJ_NG=0; SJ_CLOSE=(); SJ_TLAB=(); SJ_TTXT=(); SJ_TDONE=(); SJ_MLAB=(); SJ_MTXT=()
  SJ_ASK=(); SJ_AKEYS=()   # each Blocked on you row the judgment writes, in its order, and its keys (empty for ask +:)
  SJ_WHY=""
  while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in *[![:space:]]*) ;; *) continue ;; esac
    v="${l#*:}"; v="${v#"${v%%[! ]*}"}"
    case "$l" in
      call:*) SJ_CALL[${#SJ_CALL[@]}]="$v" ;;
      task:*|metric:*)
        case "$v" in
          *': '*) lb="${v%%: *}"; v="${v#*: }"; v="${v#"${v%%[! ]*}"}" ;;
          *:) lb="${v%:}"; v="" ;;
          *) lb="$v"; v="" ;;
        esac
        [ -n "$v" ] || SJ_WHY="${SJ_WHY}the line '${l:0:60}' has no text after its label: write it as ${l%%:*}: <label>: <text>"$'\n'
        if [ "${l%%:*}" = task ]; then SJ_TLAB[${#SJ_TLAB[@]}]="$lb"; SJ_TTXT[${#SJ_TTXT[@]}]="$v"
        else SJ_MLAB[${#SJ_MLAB[@]}]="$lb"; SJ_MTXT[${#SJ_MTXT[@]}]="$v"; fi ;;
      grade:*) SJ_GRADE="$v"; SJ_NG=$((SJ_NG + 1)) ;;
      point:*) SJ_POINT[${#SJ_POINT[@]}]="$v" ;;
      close:*) SJ_CLOSE[${#SJ_CLOSE[@]}]="$v" ;;
      'ask +:'*) SJ_ASK[${#SJ_ASK[@]}]="$v"; SJ_AKEYS[${#SJ_AKEYS[@]}]="" ;;
      'ask '*)
        key="${l#ask }"
        case "$key" in
          *': '*) v="${key#*: }"; key="${key%%: *}" ;;
          *:) key="${key%:}"; v="" ;;
          *) SJ_WHY="${SJ_WHY}the line '${l:0:60}' is no ask line: write it as ask <key>: <what> — recommend <answer>"$'\n'; continue ;;
        esac
        v="${v#"${v%%[! ]*}"}"; ks=""
        # shellcheck disable=SC2046  # one word per key
        for k in $(printf '%s' "$key" | tr ',' ' '); do ks="${ks:+$ks }$k"; done
        key="$ks"
        # shellcheck disable=SC2086  # one word per key
        for k in $key; do
          case "$seen" in *" $k "*) SJ_WHY="${SJ_WHY}two ask lines name $k: the card has one row per ask"$'\n' ;; esac
          seen="$seen$k "
        done
        case "$v" in
          *' — recommend '?*) ;;
          *) SJ_WHY="${SJ_WHY}ask ${key// /, }: says no recommended answer: write it as ask <key>: <what> — recommend <answer>"$'\n' ;;
        esac
        if printf '%s\n' "$v" | awk '/(^|[^0-9A-Za-z])[1-9][.)] .*[^0-9A-Za-z][1-9][.)] / { f = 1 } END { exit !f }'; then
          SJ_WHY="${SJ_WHY}ask ${key// /, }: lists numbered options: the card names the ask and the recommended answer, never a decision's options"$'\n'
        fi
        SJ_ASK[${#SJ_ASK[@]}]="$v"; SJ_AKEYS[${#SJ_AKEYS[@]}]="$key" ;;
      *) SJ_WHY="${SJ_WHY}the line '${l:0:60}' has a tag the card does not know: it takes call:, task:, metric:, grade:, point:, ask <key>:, ask +: and close:"$'\n'; continue ;;
    esac
    text="$text$v"$'\n'
  done
  [ "${#SJ_CALL[@]}" -gt 0 ] || SJ_WHY="${SJ_WHY}no call: line: the card opens on what the user should do now"$'\n'
  _card_sitrep_call_judge
  if [ "$SJ_NG" -eq 0 ]; then SJ_WHY="${SJ_WHY}no grade: line: the Assessment is graded A to F"$'\n'
  elif [ "$SJ_NG" -gt 1 ]; then SJ_WHY="${SJ_WHY}$SJ_NG grade: lines: the Assessment has one grade"$'\n'
  else case "$SJ_GRADE" in [A-F]) ;; *) SJ_WHY="${SJ_WHY}grade: '${SJ_GRADE:0:20}' is not one of A to F"$'\n' ;; esac; fi
  n=${#SJ_POINT[@]}
  [ "$n" -ge 1 ] && [ "$n" -le 5 ] || SJ_WHY="${SJ_WHY}$n point: lines: the Assessment holds one to five"$'\n'
  n=${#SJ_CLOSE[@]}
  [ "$n" -ge 1 ] && [ "$n" -le 3 ] || SJ_WHY="${SJ_WHY}$n close: lines: Predicted close holds one to three"$'\n'
  pred="$(_card_sitrep_fact close.predicted)"
  if [ "$pred" != - ] && [ "$n" -ge 1 ]; then
    hit=""
    for ((i = 0; i < n; i++)); do case "${SJ_CLOSE[$i]}" in *"$pred"*) hit=1 ;; esac; done
    [ -n "$hit" ] || SJ_WHY="${SJ_WHY}no close: line names the predicted close, $pred: the first close row opens on it"$'\n'
  fi
  [ "${#SJ_TLAB[@]}" -gt 0 ] || SJ_WHY="${SJ_WHY}no task: line: the Task list names every step on the sheet"$'\n'
  _card_sitrep_tasks_judge
  _card_sitrep_metrics_judge
  for ((i = 0; i < ${#SR_AKEY[@]}; i++)); do
    case "$seen" in *" ${SR_AKEY[$i]} "*) ;; *) SJ_WHY="${SJ_WHY}the ask ${SR_AKEY[$i]} is open on the register and the judgment has no ask ${SR_AKEY[$i]}: line"$'\n' ;; esac
  done
  for ((j = 0; j < ${#SJ_ASK[@]}; j++)); do
    # shellcheck disable=SC2086  # one word per key
    for k in ${SJ_AKEYS[$j]}; do
      m=-1
      for ((i = 0; i < ${#SR_AKEY[@]}; i++)); do [ "${SR_AKEY[$i]}" != "$k" ] || m=$i; done
      if [ "$m" -lt 0 ]; then
        SJ_WHY="${SJ_WHY}ask $k: names a key the register lacks: copy the key from the sheet's ask: lines, or write ask +: for an ask it lacks"$'\n'
        continue
      fi
      # What an ask holds is on the card: its row names the label of every task the sheet says it holds.
      while IFS= read -r lb; do
        [ -z "$lb" ] || _card_sitrep_names "${SJ_ASK[$j]}" "$lb" \
          || SJ_WHY="${SJ_WHY}ask $k: holds $lb and its row does not name it: write $lb in the row, so what the ask holds is on the card"$'\n'
      done <<< "$(printf '%s\n' "${SR_AHOLDS[$m]}" | awk '{ s = $0; while (match(s, /[0-9]+\/[0-9A-Za-z._-]+/)) { print substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH) } }')"
    done
  done
  # The card says review, never reading or reader, in the review sense or any other, and a goal nobody measures is
  # not measured, never unmeasured: the words are refused whole, each one on a line named with its own rule.
  SJ_WHY="$SJ_WHY$(printf '%s' "$text" | awk '{ l = " " tolower($0) " "
      while (match(l, /[^a-z](readers?|readings?|unmeasured)[^a-z]/)) {
        w = substr(l, RSTART + 1, RLENGTH - 2); l = substr(l, RSTART + RLENGTH - 1)
        r = (w == "unmeasured") ? "a goal nobody measures is not measured" : "review"
        printf "the judgment says \"%s\" (in: %s): the card says %s\n", w, substr($0, 1, 60), r } }')"
}

# _card_sitrep_call_judge -> every refusal of the call rows in SJ_WHY. With an ask open, a call that says nothing is
# owed, in the Nothing row's words or a plain form of them, tells the user the opposite of the register; with none
# open, a call naming a register key (`<kind>:<id>`) points at an ask that is not there.
_card_sitrep_call_judge() {
  local i open="" k
  for ((i = 0; i < ${#SR_AKEY[@]}; i++)); do open="${open:+$open, }${SR_AKEY[$i]}"; done
  for ((i = 0; i < ${#SJ_CALL[@]}; i++)); do
    if [ -n "$open" ]; then
      k="$(printf '%s\n' "${SJ_CALL[$i]}" | awk '{ l = " " tolower($0) " "
        n = split("nothing is owed|nothing owed|nothing for you|no decision|no action is owed|nothing waits on you|nothing is waiting on you", p, "|")
        for (j = 1; j <= n; j++) if ((c = index(l, p[j])) > 0 && substr(l, c - 1, 1) !~ /[a-z]/ && substr(l, c + length(p[j]), 1) !~ /[a-z]/) { print p[j]; exit } }')"
      [ -z "$k" ] || SJ_WHY="${SJ_WHY}call: says \"$k\", that nothing is owed, while the register holds $open open: the call is the first of them to answer, in words"$'\n'
    else
      k="$(printf '%s\n' "${SJ_CALL[$i]}" | awk '{ l = " " $0
        if (match(l, /[^A-Za-z0-9_][a-z]+:[A-Za-z0-9][A-Za-z0-9._-]*/)) print substr(l, RSTART + 1, RLENGTH - 1) }')"
      [ -z "$k" ] || SJ_WHY="${SJ_WHY}call: names the register key $k, and no ask is open: the call says in words what comes next, never a key"$'\n'
    fi
  done
}

_card_sitrep_row() {  # <text> -> the row at 4 columns on a bullet, folded under its text, its first letter a capital
  _card_hang 6 "    • $(_card_sitrep_cap "$1")"
}

# _card_sitrep_draw -> the card from SR_* and SJ_*: the head from the sheet, every row from the judgment
_card_sitrep_draw() {
  local i h rel wave icon
  rel="$(_card_sitrep_fact run.release)"; wave="$(_card_sitrep_fact run.wave)"
  h="Sitrep · $(_card_sitrep_fact run.project)"; [ "$rel" = - ] || h="$h $rel"
  [ "$wave" = - ] || h="$h · wave $wave"
  printf '%s · %s\n\n  Call to action\n' "$h" "$(_card_sitrep_fact run.now)"
  for ((i = 0; i < ${#SJ_CALL[@]}; i++)); do _card_sitrep_row "${SJ_CALL[$i]}"; done
  printf '\n  Task list\n'
  for ((i = 0; i < ${#SJ_TLAB[@]}; i++)); do
    if [ "${SJ_TDONE[$i]:-0}" = 1 ]; then icon="✅"; else icon="⬜"; fi
    _card_hang 7 "    $icon ${SJ_TLAB[$i]}: $(_card_sitrep_cap "${SJ_TTXT[$i]}")"
  done
  printf '\n  Metrics\n'
  for ((i = 0; i < ${#SJ_MLAB[@]}; i++)); do _card_sitrep_row "${SJ_MLAB[$i]}: ${SJ_MTXT[$i]}"; done
  printf '\n  Assessment: %s\n' "${SJ_GRADE:--}"
  for ((i = 0; i < ${#SJ_POINT[@]}; i++)); do _card_sitrep_row "${SJ_POINT[$i]}"; done
  printf '\n  Blocked on you\n'
  for ((i = 0; i < ${#SJ_ASK[@]}; i++)); do _card_sitrep_row "${SJ_ASK[$i]}"; done
  [ "${#SJ_ASK[@]}" -gt 0 ] || _card_sitrep_row "$CARD_SITREP_NOTHING"
  printf '\n  Predicted close\n'
  for ((i = 0; i < ${#SJ_CLOSE[@]}; i++)); do _card_sitrep_row "${SJ_CLOSE[$i]}"; done
}

# _card_sitrep_check <card> -> one line per way the drawn card breaks its shape (THE CHECK, above), nothing when it
# holds. The open tasks are SR_RECS'.
_card_sitrep_check() {
  local l n=0 open
  while IFS= read -r l; do
    n=$((n + 1)); _bionic_cols_into "$l"
    [ "$BIONIC_COLS" -le "$BIONIC_LINE_WIDTH" ] \
      || printf 'line %d is %d columns, over the %d the card may use: %s\n' "$n" "$BIONIC_COLS" "$BIONIC_LINE_WIDTH" "${l:0:60}"
  done <<< "$1"
  open="$(printf '%s\n' "$SR_RECS" | awk -F'\t' '$1 == "T" && $4 != "done" { id = $2; if (substr(id, 1, 1) == "T") id = substr(id, 2)
    k = $3 "/" id; if (!(k in s)) { s[k] = 1; printf "%s ", k } }')"
  printf '%s\n' "$1" | awk -v want="$CARD_SITREP_SECTIONS" -v open="$open" '
    function bad(m) { print m }
    function row_label(t,   c) { c = index(t, ": "); return c ? substr(t, 1, c - 1) : "" }
    BEGIN { ns = split(want, sec, "|") }
    NR == 1 { if (index($0, "Sitrep · ") != 1) bad("the card does not open on its head, Sitrep · …"); next }
    $0 == "" { next }
    {
      match($0, /^ */); ind = RLENGTH; t = substr($0, ind + 1)
      if (ind == 2) {
        k = t; if (index(k, "Assessment: ") == 1) k = "Assessment"
        at++; got[at] = k; cur = k; prev = "label"; rows[k] += 0; next
      }
      if (ind == 4) {
        if (index(t, "• ") != 1 && index(t, "✅ ") != 1 && index(t, "⬜ ") != 1) bad("a row with no bullet or icon, line " NR ": " t)
        else if (cur == "Task list" && index(t, "• ") != 1) {
          lb = row_label(substr(t, index(t, " ") + 1))
          if (lb ~ /^[0-9]+$/) above[lb] = NR
          else if ((p = index(lb, "/")) > 0) {
            st = substr(lb, 1, p - 1)
            if (st in above) bad("the step row " st ": on line " above[st] " sits above its own task " lb)
            if (index(lb, "–") == 0) cnt[lb]++
          }
        }
        if (cur == "") bad("a row before any section, line " NR ": " t)
        rows[cur]++; prev = "row"; next
      }
      if (ind >= 5 && (prev == "row" || prev == "cont")) {
        if (cur == "Task list") bad("a task row spans two lines, line " NR ": " t)
        prev = "cont"; next
      }
      bad("a row with no bullet or icon, line " NR ": " t)
    }
    END {
      s = ""; for (i = 1; i <= at; i++) s = s (i > 1 ? "|" : "") got[i]
      if (s != want) bad("the sections are " (s == "" ? "none" : s) "; the card is " want ", in that order")
      for (i = 1; i <= ns; i++) if ((sec[i] in rows) && rows[sec[i]] == 0) bad("the section " sec[i] " has no row")
      n = split(open, o, " ")
      for (i = 1; i <= n; i++) {
        c = cnt[o[i]] + 0
        if (c == 0) bad("the open task " o[i] " has no row in the Task list")
        else if (c > 1) bad("the open task " o[i] " has " c " rows in the Task list; it has one")
      }
    }'
}

# _card_sitrep_load <sheet file> -> SR_RECS, the open asks SR_AKEY and SR_AHOLDS, and SR_MNUMS: what each metric may
# say, as tab-separated records: `N <Label> <number>` per run of digits in the measured value (the text before ` — `)
# of a line the metric is written from (CARD_SITREP_MLINES), leading zeros cut; `G <status> <count>` per goal status
# and `G total <count>`, counted from the goal: lines, since the sheet prints no goal count. A clock, a date, the
# release, a step number or a unit's words are no metric's measured value, so none of them vouches for a number.
_card_sitrep_load() {
  local k h
  SR_RECS="$(_card_sitrep_sheet "$1")"; SR_AKEY=(); SR_AHOLDS=()
  SR_MNUMS="$(awk -v lines="$CARD_SITREP_MLINES" '
    BEGIN { n = split(lines, a, " "); for (i = 1; i <= n; i++) { c = index(a[i], "="); lab[substr(a[i], c + 1)] = substr(a[i], 1, c - 1) } }
    function label_of(k,   p) { if (k in lab) return lab[k]; p = k; sub(/\..*$/, ".*", p); return (p in lab) ? lab[p] : "" }
    index($0, "goal: ") == 1 {
      st = $0; s = index(st, " status="); st = s ? substr(st, s + 8) : ""; e = index(st, " measure="); if (e) st = substr(st, 1, e - 1)
      g[st]++; gt++; next }
    /^[a-z][a-z.-]*: / {
      k = $0; sub(/: .*$/, "", k); m = label_of(k); if (m == "") next
      v = substr($0, length(k) + 3); i = index(v, " — "); if (i) v = substr(v, 1, i - 1)
      while (match(v, /[0-9]+/)) { x = substr(v, RSTART, RLENGTH); v = substr(v, RSTART + RLENGTH); sub(/^0+/, "", x); if (x == "") x = "0"
        if (!seen[m SUBSEP x]++) print "N\t" m "\t" x } }
    END { print "G\ttotal\t" gt + 0; for (s in g) print "G\t" s "\t" g[s] }' "$1")"
  while IFS="$CARD_TAB" read -r _ k h _; do
    [ -n "$k" ] || continue
    SR_AKEY[${#SR_AKEY[@]}]="$k"; SR_AHOLDS[${#SR_AHOLDS[@]}]="${h:-nothing}"
  done <<< "$(printf '%s\n' "$SR_RECS" | awk -F'\t' '$1 == "A"')"
}

_card_sitrep() {  # <sheet file>, the judgment on stdin -> the card, or 1 and every reason on stderr
  local card why
  _card_sitrep_load "$1"
  _card_sitrep_judge
  card="$(_card_sitrep_draw)"
  # the two lists joined on a line break, since a command substitution drops the last one of the first
  why="$SJ_WHY"$'\n'"$(_card_sitrep_check "$card")"
  if [ -n "${why//[[:space:]]/}" ]; then
    printf '%s\n' "$why" | awk 'NF { print "card.sh: sitrep card refused: " $0 }' >&2
    return 1
  fi
  printf '%s\n' "$card"
}

# ── THE COMMAND LINE ─────────────────────────────────────────────────────────
[ "$#" -ge 1 ] || _card_usage "no row kind"

case "$1" in
  rigor)
    [ "$#" -eq 2 ] || _card_usage "rigor takes exactly one word (got $(( $# - 1 )))"
    rigor_print "$2" && exit 0
    printf "card.sh: '%s' is no review rigor — use single or double\n" "$2" >&2
    exit 1 ;;
  regression)
    [ "$#" -ge 2 ] && [ "$#" -le 3 ] || _card_usage "regression takes a scale and an optional plan (got $(( $# - 1 )) arguments)"
    if _card_regression_line "$2" "${3:-}"; then
      # The Step-0 card's regression line names the plan the run was configured into: that card
      # leaves the person the configuration to approve (T11; D2). Without a plan it opens nothing.
      _card_owe 0 "${3:-}"
      exit 0
    fi
    printf "card.sh: '%s' is no scale — use task, wave or epic\n" "$2" >&2
    exit 1 ;;
  inherited)
    # THE READING CLOSE-OUT CARRIES FROM (T43): `card.sh inherited <requirements file>`. A path that
    # names no file disposes of nothing; its name still says whose run it is.
    [ "$#" -eq 2 ] || _card_usage "inherited takes exactly one requirements file path (got $(( $# - 1 )))"
    # The carry of a debt is the ledger's (close-out's co_debts), so a debt line read from here would be
    # carried twice: the card lists it, this reading withholds it (A-T32.2).
    _card_inherited "$2" | /usr/bin/grep -v -e "^unknown${CARD_TAB}" -e "^open${CARD_TAB}debt: "
    exit 0 ;;
  inherited-debt)
    # THE DEBT LINES THE READING ABOVE WITHHOLDS (wave-30 T23; A-orch-44): `card.sh inherited-debt
    # <requirements file>` prints each open `debt:` line of the newest continuation, as written. An item
    # nobody ran `debt adopt` on is in no ledger, so close-out re-carries it from here unless its run's
    # ledger holds the concept and kind; withheld above, it was dropped at the next close-out.
    [ "$#" -eq 2 ] || _card_usage "inherited-debt takes exactly one requirements file path (got $(( $# - 1 )))"
    _card_inherited "$2" | awk -F '\t' '$1 == "open" && index($2, "debt: ") == 1 { print substr($0, 6) }'
    exit 0 ;;
  sitrep|sitrep-check)
    # The sitrep card, from the sheet the sitrep verb names and the judgment on stdin; or, for a planted card on stdin,
    # its check alone, the one the card is held to before it prints.
    [ "$#" -eq 2 ] || _card_usage "$1 takes exactly one sheet file; the $([ "$1" = sitrep ] && echo judgment || echo card) comes on stdin (got $(( $# - 1 )))"
    [ -f "$2" ] && [ -r "$2" ] || _card_usage "$1: no readable sheet at '$2'"
    if [ "$1" = sitrep ]; then _card_sitrep "$2" || exit 1; exit 0; fi
    _card_sitrep_load "$2"
    _card_sitrep_why="$(_card_sitrep_check "$(cat)")"
    [ -z "$_card_sitrep_why" ] || { printf '%s\n' "$_card_sitrep_why" | sed 's/^/card.sh: sitrep card refused: /' >&2; exit 1; }
    exit 0 ;;
  fold)
    # A page's lines folded at the shared width, each `<hang> TAB <text>` on stdin: a line wider than BIONIC_LINE_WIDTH
    # breaks at its last space that fits, every continuation opening on <hang> spaces. The handoff folds through it.
    [ "$#" -eq 1 ] || _card_usage "fold takes no argument; its lines come on stdin (got $(( $# - 1 )))"
    while IFS= read -r _card_l || [ -n "${_card_l:-}" ]; do
      case "$_card_l" in
        *"$CARD_TAB"*) _card_k="${_card_l%%"$CARD_TAB"*}"; _card_l="${_card_l#*"$CARD_TAB"}" ;;
        *) _card_k=0 ;;
      esac
      case "$_card_k" in ''|*[!0-9]*) _card_k=0 ;; esac
      _card_hang "$_card_k" "$_card_l"
    done
    exit 0 ;;
  release)
    # The release approval card, drawn from the facts the release-approval verb gathers, on stdin.
    [ "$#" -eq 1 ] || _card_usage "release takes no argument; its facts come on stdin (got $(( $# - 1 )))"
    _card_release || exit 64
    exit 0 ;;
  early)
    # Whether the release approval card may render: the three facts, and what a red check owes that the page settles.
    [ "$#" -eq 2 ] || _card_usage "$1 takes exactly one plan path (got $(( $# - 1 )))"
    [ -f "$2" ] && [ -r "$2" ] || _card_usage "$1: no readable plan at '$2'"
    _card_early_load || { printf 'card.sh: %s: lib/owed.sh and lib/roster.sh cannot be loaded beside this file\n' "$1" >&2; exit 1; }
    _card_early_ctx "$2" || { printf 'card.sh: %s: %s\n' "$1" "$CF_ERR" >&2; exit 1; }
    if ! _card_early; then printf 'CARD-EARLY — %s\n' "$CARD_EARLY_WHY" >&2; exit 1; fi
    printf '%s' "$CF_SETTLE" | awk 'NF && !seen[$0]++ { print "settles: " $0 }'
    exit 0 ;;
  step0|step1|step2|step3)
    if [ "$1" = step2 ]; then
      [ "$#" -ge 2 ] || _card_usage "$1 takes exactly one artifact path (got $(( $# - 1 )))"
    else
      [ "$#" -eq 2 ] || _card_usage "$1 takes exactly one artifact path (got $(( $# - 1 )))"
    fi
    [ -f "$2" ] && [ -r "$2" ] || _card_usage "$1: no readable artifact at '$2'"
    _card_load "$1" "$2" || _card_usage "$2: ${WCARD_ERR}"
    if [ "$1" = step2 ] && [ "$#" -gt 2 ]; then
      shift
      _card_step2_view "$@"
      exit 0
    fi
    _card_art="$(_card_artifact_rel "$2")"
    case "$1" in
      step0) _card_step0 "$2" ;;
      step1) _card_step1 "$_card_art" "$2" ;;
      step2) _card_step2 "$_card_art" ;;
      step3) _card_step3 "$_card_art" "$2" ;;
    esac
    _card_owe "${1#step}" "$2"
    exit 0 ;;
esac

_card_spec "$1" || _card_usage "unknown row kind '$1'"
[ "$#" -le 1 ] || _card_usage "one row kind at a time (got $#)"

CARD_ROWS=()
while IFS= read -r _card_row || [ -n "${_card_row:-}" ]; do
  [ -n "$_card_row" ] || continue
  CARD_ROWS[${#CARD_ROWS[@]}]="$_card_row"
done

_card_render_batch "$1"

exit 0
