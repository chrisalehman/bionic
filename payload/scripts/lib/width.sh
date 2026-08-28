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
# MEASURED IN COLUMNS, CUT IN BYTES, AND THAT ASYMMETRY IS DELIBERATE. A
# terminal lays out COLUMNS, so the budget is a column count; but `printf`'s
# precision counts BYTES, and no byte count is ever smaller than the column
# count of the same string. Cutting to N bytes therefore yields AT MOST N
# columns — the error can only ever be a line shorter than it needed to be,
# never one past the budget. The alternative (walking characters) buys back a
# few columns on the rare row carrying a dash or an ellipsis, and costs a
# locale dependency: `${s:0:n}` slices characters under a UTF-8 locale and
# bytes under C, and the suites run under `env -i`.
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
bionic_cols() {  # <string> -> its width in terminal columns
  local s="${1:-}"
  s="${s//✓/.}"; s="${s//✗/.}"; s="${s//–/.}"; s="${s//—/.}"
  s="${s//≥/.}"; s="${s//…/.}"; s="${s//·/.}"
  printf '%s' "${#s}"
}

# One string, held inside a column budget, elided with `…` when it does not fit.
# A budget of 0 or less means "unbounded" rather than "print nothing", so a
# caller whose prefix already ate the whole line still gets its content — a row
# that printed an ellipsis and no fact would be worse than a long row.
bionic_trunc() {  # <string> <column-budget> -> string
  local s="${1:-}" max="${2:-0}" cut
  [ "$max" -gt 0 ] || { printf '%s' "$s"; return 0; }
  [ "$(bionic_cols "$s")" -le "$max" ] && { printf '%s' "$s"; return 0; }
  # One column for the ellipsis. The cut is bytes (see the header), so the
  # result is at most `max - 1` columns and the whole string at most `max`.
  cut=$(( max - 1 )); [ "$cut" -gt 0 ] || cut=0
  printf '%.*s…' "$cut" "$s"
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
  room=$(( BIONIC_LINE_WIDTH - $(bionic_cols "$prefix") ))
  budget=$(( room - $(bionic_cols "$keep") ))
  if [ -z "$keep" ] || [ "$budget" -lt 1 ]; then
    # Nothing to protect, or no room to protect it in. One bound over the whole
    # tail: a truncated instruction still beats a line the terminal wraps.
    printf '%s%s' "$prefix" "$(bionic_trunc "${tail}${keep}" "$room")"
    return 0
  fi
  printf '%s%s%s' "$prefix" "$(bionic_trunc "$tail" "$budget")" "$keep"
}
