#!/bin/bash
# payload/scripts/lib/log.sh — THE ONE APPENDER OF A RUN'S LOG.
#
#   log_append <event type> <key>=<value>…   appends one line to the file RUN_LOG names:
#
#       run/v1|ev=<event type>|<key>=<value>|…|at=<UTC seconds>
#
# THE SHAPE. A line is `|`-separated, every field is `<key>=<value>`, and it is read by field name
# (lib/line.sh's `line_value`, `line_kv`), never by place. `ev=` comes first and is set here, `at=` comes
# last and is stamped here; a caller's field named either is refused, so no line lacks one or holds two.
# THE INSTANT is this clock's, save for one caller: the asks library stamps an ask by its own clock, which
# honours the fixed instant a suite sets and which the sheet, the card and the handoff count an ask's minutes
# on, so it hands that instant in LOG_AT for its call; a LOG_AT not in the one shape `at=` is written in is
# refused. Every other event keeps this clock: the landing line's instants stand beside real process start
# times, which no fixed clock moves.
# A value holding `|` or a line break would split a field or a line, so it is refused unwritten.
#
# THE CLOSED LIST. LOG_TYPES is every event type a line may carry: the 28 of the kernel map and `hand`
# (any act taken by hand to keep the run going). A type outside it is refused, so a misspelt or retired
# event cannot become a fact the reader has no question for.
#
# EXITS. 0 appended; 2 refused with the file untouched (no type, a type outside the list, a field that is
# not `<name>=<value>`, no RUN_LOG, a LOG_AT off the shape); 1 the write failed. The write is the landing record's one append
# (`_wt_proofs_put`: a private file copied by one write(2)), so two writers' lines never interleave.
#
# bash 3.2 (ADR-001).

_LOG_LIB_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P )"
if ! declare -F line_value >/dev/null 2>&1 || ! declare -F _wt_proofs_put >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$_LOG_LIB_DIR/line.sh"
fi

LOG_TYPES=" ready candidate verdict published returned stalled standing admitted void run walk step approval"
LOG_TYPES="${LOG_TYPES} proof finding waiver decision order bind handoff dispatch tree born ask stop debt abandon cancel hand "

log_append() {  # <event type> <key>=<value>… -> 0 appended, 2 refused, 1 not written
  local ev="${1:-}" f k line at="${LOG_AT:-}"
  case "$ev" in ''|*[!a-z]*) return 2 ;; esac
  case "$at" in '') at="$(_line_now)" ;; [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z) ;; *) return 2 ;; esac
  case "$LOG_TYPES" in *" $ev "*) ;; *) return 2 ;; esac
  [ -n "${RUN_LOG:-}" ] || return 2
  shift
  line="run/v1|ev=${ev}"
  for f in "$@"; do
    k="${f%%=*}"
    [ "$k" != "$f" ] || return 2
    case "$k" in ''|ev|at|*[!a-z0-9_-]*|[!a-z]*) return 2 ;; esac
    case "$f" in *'|'*|*$'\n'*|*$'\r'*) return 2 ;; esac
    line="${line}|${f}"
  done
  mkdir -p "${RUN_LOG%/*}" 2>/dev/null || return 1
  _wt_proofs_put "$RUN_LOG" "${line}|at=${at}" || return 1
}
