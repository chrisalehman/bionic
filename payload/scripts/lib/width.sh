#!/bin/bash
# width.sh — the ONE column budget for everything bionic prints, and the two
# functions that hold a line inside it (epic-19 W1 S9, Step-6 ARCHITECTURE b.1 /
# DUPLICATION flag).
#
# WHAT THIS FILE OWNS. How wide a printed line may be, how wide a string IS, and
# how to shorten one that is too wide. Three questions, one owner, consumed by
# both doors that print a table: `scripts/setup.sh` and `scripts/doctor.sh`.
#
# WHY IT EXISTS. The rule is doctor's, and it is older than this file:
# *nothing printed may exceed 100 columns*, because a wrapped line is one row
# turned into two by the terminal and the whole table stops being a table
# (doctor.sh's format rules, spec AC-15). The wall that used to enforce it —
# tests/doctor.test.sh — was deleted at 8582861 (epic-18 wave-03) and nothing
# replaced it. Slice 4/3 of this wave then built a budget for setup.sh, and
# slice 4/4 added a row to doctor.sh whose detail field interpolates unbounded
# free text: on the wave's own T3 capture that row came out at 104 columns, and
# a git feed with a missing manifest puts it past 130. Two scripts, the same
# number written twice, and the copy nothing walled was the one that broke. The
# number and the truncator live here now, so there is one of each.
#
# ONE UNIT ON BOTH SIDES OF THE CUT, AND THIS IS THE WHOLE POINT OF THE FILE.
# The budget is a column count, the test is a column count, and the cut removes
# one CHARACTER at a time (`${s%?}`) until the count fits. It is not
# `printf '%.*s'`, and that is a correction, not a preference: precision on
# `%s` counts BYTES, so a length test in characters against a cut in bytes
# slices a multi-byte glyph in half and emits invalid UTF-8. The wave's Step-6
# critic reproduced exactly that in `_setup_trunc` — 3 of 5 cut offsets
# corrupted, on any `$HOME` carrying an accent — and the truncator this file
# replaces had been deleted four commits earlier carrying a comment warning
# against it: *"Cut to a column count, never to a byte count."* Restored here,
# once, for both scripts.
#
# THE LOOP FORKS NOTHING. `$(bionic_cols "$s")` inside a shrink loop is a
# subshell per iteration — hundreds of forks on a long path, on a page that
# already spends its budget on real probes. `_bionic_cols_into` writes the
# answer to a variable instead, so the loop is pure bash string work and the
# glyph set is still spelled exactly once.
#
# Sourced, never executed:  . "${CLAUDE_PLUGIN_ROOT}/scripts/lib/width.sh"

# THE NUMBER. 100 columns, the width doctor's format rules have always named.
BIONIC_LINE_WIDTH=100

# PRINTF PADS BYTES; A TERMINAL LAYS OUT COLUMNS. Every glyph bionic prints
# outside ASCII — ✓ ✗ – — ≥ … · — is three bytes wide and one column wide, so a
# `%-11s` field holding one of them comes out two columns short and the whole
# table steps left from that row down. It is not hypothetical: `—` is the
# version cell of every dependency whose mechanism keeps no version.
#
# THE SET IS CLOSED, which is what makes measuring a substitution away from
# exact — no locale to depend on, and no external process per cell. A glyph
# added to a report and not to this list measures three columns too wide, and
# the effect is a column that pads short, never a line that overflows.
_bionic_cols_into() {  # <string> — sets BIONIC_COLS; no subshell, for the loop below
  local s="${1:-}"
  s="${s//✓/.}"; s="${s//✗/.}"; s="${s//–/.}"; s="${s//—/.}"
  s="${s//≥/.}"; s="${s//…/.}"; s="${s//·/.}"
  # THE ARROW AND THE BULLET, ADDED AT bionic 1.4.0 (spec AC-23). The arrow is
  # the most-printed non-ASCII glyph bionic has — it opens every FIX line and it
  # is the first character of the instruction `bionic_line` is asked to protect
  # from a truncation — and it was not in this list. `_setup_print_plan`'s `  • `
  # row prefix was outside it too. Both were measured three columns wide, so
  # every budget computed from a prefix carrying one came out two columns short:
  # the row pads short, the table steps left, and the tail is cut two characters
  # earlier than the budget says. Found by tests/width.test.sh, which measures
  # under `LC_ALL=C` — the locale this substitution exists for, and the one a
  # stripped environment hands a hook. (Under a UTF-8 locale `${#s}` already
  # counts characters, which is why nothing noticed.)
  s="${s//→/.}"; s="${s//•/.}"
  BIONIC_COLS="${#s}"
}

bionic_cols() {  # <string> -> its width in terminal columns
  _bionic_cols_into "${1:-}"
  printf '%s' "$BIONIC_COLS"
}

# One string, held inside a column budget, elided with `…` when it does not fit.
# A budget of 0 or less means "unbounded" rather than "print nothing", so a
# caller whose prefix already ate the whole line still gets its content — a row
# that printed an ellipsis and no fact would be worse than a long row.
bionic_trunc() {  # <string> <column-budget> -> string
  # THE CUT IS BYTEWISE AND THE LOCALE IS THIS FUNCTION'S OWN (wave-01 S4,
  # AC-8; S24 F-25). `${s%?}` drops one CHARACTER under a UTF-8 locale and one
  # BYTE under `LC_ALL=C` — and a hook, a cron job or a script started from a
  # stripped environment gets the C locale. So the old loop, which was written
  # against the UTF-8 reading and says so in its own comment, cut three-byte
  # glyphs into fragments there: `/Users/josé/...` came back ending in half an
  # `é`, which is invalid UTF-8 and prints as a replacement box. That is the
  # exact failure this file's header (`printf '%.*s' counts BYTES`) exists to
  # prevent, reintroduced one level down by a locale nobody chose.
  #
  # PINNING `LC_ALL=C` HERE MAKES THE READING THE SAME IN BOTH: every string
  # operation below is bytes, and the inner loop drops a whole UTF-8 character
  # by walking off its continuation bytes (0x80-0xBF) and then its lead byte.
  # `local` restores the caller's locale on return, so nothing outside this
  # function changes reading.
  local s="${1:-}" max="${2:-0}" want last
  local LC_ALL=C
  [ "$max" -gt 0 ] || { printf '%s' "$s"; return 0; }
  _bionic_cols_into "$s"
  [ "$BIONIC_COLS" -le "$max" ] && { printf '%s' "$s"; return 0; }
  # One column of the budget goes to the ellipsis.
  want=$(( max - 1 )); [ "$want" -gt 0 ] || want=0
  while [ -n "$s" ] && [ "$BIONIC_COLS" -gt "$want" ]; do
    while [ -n "$s" ]; do
      last="${s:${#s}-1}"
      s="${s%?}"
      case "$last" in
        [$'\200'-$'\277']) ;;   # a continuation byte: the character is not whole yet
        *) break ;;
      esac
    done
    _bionic_cols_into "$s"
  done
  printf '%s…' "$s"
}

# A whole row, from a fixed prefix and a free-form tail: the shape both callers
# actually have. THE BUDGET IS COMPUTED FROM THE REAL PREFIX, never assumed —
# a label longer than its column minimum (`retired permission block` already is)
# still leaves the tail bounded rather than quietly blowing the budget.
#
# AND THE THIRD ARGUMENT IS WHAT MUST SURVIVE THE CUT. Truncation takes the END
# of a string, and the end of a bionic row is where the thing to TYPE lives —
# doctor's first format rule is that a line ends with the command. A row reading
# `✗ claude() shell proxy   stale   in /very/long/path…` states a problem and
# withholds its cure, which is worse than the overflow it was avoiding. So a
# caller whose tail is `<free text><fixed instruction>` passes them separately:
# the free text absorbs the whole shortfall and the instruction is printed whole.
# Found by the wall itself — tests/rc-item.test.sh's fixture rc lives under a
# 60-column mktemp path and the first version of this file elided the row's
# `— /bionic:setup rewrites it` clean off (epic-19 W1 S9).
bionic_line() {  # <prefix> <tail> [<instruction that must survive>]
  local prefix="${1:-}" tail="${2:-}" keep="${3:-}" room budget
  _bionic_cols_into "$prefix"; room=$(( BIONIC_LINE_WIDTH - BIONIC_COLS ))
  _bionic_cols_into "$keep";   budget=$(( room - BIONIC_COLS ))
  if [ -z "$keep" ] || [ "$budget" -lt 1 ]; then
    # Nothing to protect, or no room to protect it in. One bound over the whole
    # tail: a truncated instruction still beats a line the terminal wraps.
    printf '%s%s' "$prefix" "$(bionic_trunc "${tail}${keep}" "$room")"
    return 0
  fi
  printf '%s%s%s' "$prefix" "$(bionic_trunc "$tail" "$budget")" "$keep"
}
