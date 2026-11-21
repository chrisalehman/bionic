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
# THE CLOSED LIST. LOG_TYPES is every event type a line may carry: the 28 of the kernel map, `hand`
# (any act taken by hand to keep the run going), `drop` (a row's work no longer owed, in the person's
# words) and `ruling` (the orchestrator's binding word to one row's writer, its push and its reading:
# lib/roster.sh). A type outside it is refused, so a misspelt or retired event cannot become a fact the reader has
# no question for.
#
# EXITS. 0 appended; 2 refused with the file untouched (no type, a type outside the list, a field that is
# not `<name>=<value>`, no RUN_LOG, a LOG_AT off the shape); 1 the write failed. The write is the landing record's one append
# (`_wt_proofs_put`: a private file copied by one write(2)), so two writers' lines never interleave.
#
# THE SEAL (lib/seal.sh). A line for a run's log is written inside `seal_write`: under the seal's short lock
# the run is checked against its seal, the line is written, and the run is sealed again from its files on disk.
# The check comes first so that an honest line written after a change made around the tool cannot vouch for
# that change: whatever the check catches is kept in the seal as changed, the line is still appended, and no
# later append clears it. The run is the plan the log is joined to by the record's name (`_log_plan`, the
# inverse of lib/reader.sh `reader_log`, confirmed by it); a log no plan names, or one in no repository, takes
# the line with nothing sealed. A lock that cannot be had in its wait (many writers at once) leaves the line
# appended unsealed, a note of it left first beside the seal (`seal_owe`), so the next check reads that line,
# and only that line, as the tool's own: an honest writer that met the lock is never a change caught, and a
# line no note names is caught beside it. A call out of shape (64) leaves no note, and its line is caught.
# A RUN FOUND WITH NO SEAL is sealed as it stands, and the sealing is written first, as one `hand` line,
# `what=seal`, through the hand events' one writer, then the caller's line. Only a run that a fresh fold of its
# log reads open is sealed so, never one a kept answer reads open, and never under a dry call (BIONIC_DRY_STEP),
# whose step is not the run's: a closed run, or a dry call, takes its line with no seal made. A seal that
# stands is checked and kept under a dry call as under any other, since the line it writes is real.
#
# bash 3.2 (ADR-001).

_LOG_LIB_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P )"
if ! declare -F line_value >/dev/null 2>&1 || ! declare -F _wt_proofs_put >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$_LOG_LIB_DIR/line.sh"
fi
# shellcheck source=/dev/null
declare -F seal_write >/dev/null 2>&1 || . "$_LOG_LIB_DIR/seal.sh"

LOG_TYPES=" ready candidate verdict published returned stalled standing admitted void run walk step approval"
LOG_TYPES="${LOG_TYPES} proof finding waiver decision order bind handoff dispatch tree born ask stop debt abandon cancel hand drop ruling "

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
  _log_put "$RUN_LOG" "${line}|at=${at}" || return 1
}

LOG_SEALED_WHY="no seal stood for this open run, so it was sealed as it was found"

_log_put() {  # <log> <line> -> 0 appended, 1 not; inside the seal when the log is a run's
  local rc
  _log_put_line "$@"; rc=$?
  _log_moved
  return "$rc"
}
_log_put_line() {
  local log plan
  log="$(_seal_canon "$1")"
  _log_plan "$log" || { _wt_proofs_put "$1" "$2"; return; }
  plan="$_LOG_PLAN"
  seal_stands "$plan"
  case "$?" in
    0) ;;
    1) if [ -n "${BIONIC_DRY_STEP:-}" ] || ! _log_open "$plan"; then _wt_proofs_put "$1" "$2"; return; fi
       seal_write "$plan" "$log"
       if [ "$SEAL_WAS" = none ] && [ "$(_seal_canon "$(line_log "$plan" 2>/dev/null)")" = "$log" ]; then
         line_hand_event "$plan" seal "$LOG_SEALED_WHY" >/dev/null 2>&1
       fi ;;
    *) _wt_proofs_put "$1" "$2"; return ;;
  esac
  seal_write "$plan" "$log" _wt_proofs_put "$1" "$2"
  case "$?" in
    75) seal_owe "$plan" "$2"; _wt_proofs_put "$1" "$2"; return ;;
    64) _wt_proofs_put "$1" "$2"; return ;;
  esac
  return "$SEAL_RC"
}

# _log_moved -> a log was written to. Inside a held command (lib/proof.sh `_proof_facts_held`) every key line the command
# holds is removed, so the next ask in any of its processes sums the log again and folds what this line added; the
# files folded under the old key stay, and serve again only if the sum finds it unchanged. Counted (`append`,
# tests/speed-counts.test.sh) when BIONIC_COUNT names a file.
_log_moved() {
  [ -z "${BIONIC_COUNT:-}" ] || printf 'append _log_put\n' 2>/dev/null >>"$BIONIC_COUNT" || :
  case "${BIONIC_HELD:-}" in */bionic-held-*) ;; *) return 0 ;; esac
  [ -d "$BIONIC_HELD" ] && [ ! -L "$BIONIC_HELD" ] && [ -O "$BIONIC_HELD" ] || return 0
  set -- "$BIONIC_HELD"/key-*
  [ ! -e "$1" ] || rm -f "$@" 2>/dev/null
  return 0
}

# _log_plan <canonical log> -> _LOG_PLAN, the plan of the run whose log it is; rc 1 when no plan is. The record is
# `<docs>/record/<name>/run.log`, and a plan is joined to it at the places the run walk admits one: <name>.plan.md
# in plans/ or incidents/ or one folder below, or an epic's epic.plan.md in the folder <name>. Each place is
# confirmed by the reader's own join, so this never names a plan the reader would not.
_log_plan() {
  local log="$1" rec name docs c
  _LOG_PLAN=""
  case "$log" in */record/*/run.log) ;; *) return 1 ;; esac
  rec="${log%/run.log}"; name="${rec##*/}"; docs="${rec%/record/*}"
  for c in "$docs/plans/$name.plan.md" "$docs/plans/"*"/$name.plan.md" "$docs/plans/$name/epic.plan.md" \
           "$docs/incidents/$name.plan.md" "$docs/incidents/"*"/$name.plan.md" "$docs/incidents/$name/epic.plan.md"; do
    [ -f "$c" ] || continue
    _log_reader || return 1
    [ "$(reader_log "$c" 2>/dev/null)" = "$log" ] || continue
    _LOG_PLAN="$c"; return 0
  done
  return 1
}

_log_reader() {  # -> 0 once lib/reader.sh, beside this file, is loaded
  declare -F reader_main >/dev/null 2>&1 && return 0
  # shellcheck source=/dev/null
  . "$_LOG_LIB_DIR/reader.sh" >/dev/null 2>&1
  declare -F reader_main >/dev/null 2>&1
}

# _log_open <plan> -> 0 when the run is open, by lib/run.sh `run_open`'s rule (state open, at a step 0 to 9) over a
# fresh fold of the log: the kept answer `run_open` serves is a fact kept between asks, and a seal is made from the
# files alone.
_log_open() {
  local place n
  place="$(reader_main "$1" step 2>/dev/null)" || return 1
  case "$place" in *state=open*) ;; *) return 1 ;; esac
  n=""; case "$place" in n=*) n="${place%%$'\n'*}"; n="${n#n=}" ;; esac
  n="${n%[ab]}"
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  [ "$((10#$n))" -le 9 ]
}
