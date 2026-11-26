#!/bin/bash
# payload/scripts/lib/time.sh — an instant, read once (wave-39 T17; D18, REQ-12 AC-12.1).
#
# WHAT IT OWNS. One question: which second is this instant? An instant is `YYYY-MM-DDTHH:MM:SSZ`, twenty characters,
# UTC, the shape every bionic record writes (`date -u +%Y-%m-%dT%H:%M:%SZ`). Anything else is no instant.
#
#     iso_epoch <ISO-8601 Z>   its epoch seconds; nothing, rc 1, for anything that is not an instant
#     _TIME_ISO_AWK            the same reading as awk functions, for a program that reads many instants in one pass
#                              (a fork per record is a cost nobody would accept): `iso2epoch(s)` is the epoch, -1 for
#                              anything that is not an instant. Prefix it to the program: awk "$_TIME_ISO_AWK"'…'
#     iso_now                  the machine clock's instant now; never the pinned clock
#     epoch_iso <epoch>        that epoch as an instant; nothing, rc 1, for anything that is not digits
#     time_now                 now in epoch seconds: BIONIC_NOW_EPOCH when it is digits, else the machine's clock
#     file_mtime <path>        the path's modified time in epoch seconds; nothing, rc 1, when it cannot be stat'ed
#
# THE ONE READER (burns debt iso-to-epoch; critic-structure, wave 38). Three stood. hooks/session-poker.sh `iso_epoch`
# asked BSD `date -j -f`, which reads `…Zx` with a warning, then GNU `date -d`, which reads almost anything. lib/patrol.sh
# carried this arithmetic in its own awk, reading a no-Z instant and a fractional `.5Z` alike. lib/gate.sh's
# `_gate_row_done` carried a third copy that range-checked nothing, so month 13 converted. D18 rules strict `…Z`, the
# poker's grammar, on the patrol's arithmetic. patrol.sh, gate.sh and the poker read through this file, and
# tests/time.test.sh §AGREE reads one table of instants through all of them.
#
# THE RANGE IS THE ONE `date` KEPT: month 1-12, day 1-31, hour 0-23, minute 0-59, second 0-60. A day past its month's
# end and second 60 carry forward, as `date -j -f` carries them (February 30 is March 2). Leap seconds are not counted.
#
# THE ARITHMETIC IS HOWARD HINNANT'S days-from-civil, exact for every date a record will carry, in POSIX awk. NO
# INTERVAL EXPRESSIONS (`[0-9]{4}`): the awk macOS ships does not carry them, so the shape is checked by position.
#
# Sourced, never executed; bash 3.2.

# A field like "08" is read by awk as decimal eight, never as octal, so no leading zero needs stripping.
_TIME_ISO_AWK='
function alldig(s,   i, c) {
  if (length(s) == 0) return 0
  for (i = 1; i <= length(s); i++) { c = substr(s, i, 1); if (c < "0" || c > "9") return 0 }
  return 1
}
function days_from_civil(y, m, d,   era, yoe, doy, doe) {
  if (m <= 2) y = y - 1
  era = int((y >= 0 ? y : y - 399) / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}
function iso2epoch(s,   y, mo, d, h, mi, se) {
  if (length(s) != 20 || substr(s, 20, 1) != "Z") return -1
  if (substr(s, 5, 1) != "-" || substr(s, 8, 1) != "-") return -1
  if (substr(s, 11, 1) != "T" || substr(s, 14, 1) != ":" || substr(s, 17, 1) != ":") return -1
  if (!alldig(substr(s, 1, 4)) || !alldig(substr(s, 6, 2)) || !alldig(substr(s, 9, 2))) return -1
  if (!alldig(substr(s, 12, 2)) || !alldig(substr(s, 15, 2)) || !alldig(substr(s, 18, 2))) return -1
  y = substr(s, 1, 4) + 0; mo = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
  h = substr(s, 12, 2) + 0; mi = substr(s, 15, 2) + 0; se = substr(s, 18, 2) + 0
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || se > 60) return -1
  return days_from_civil(y, mo, d) * 86400 + h * 3600 + mi * 60 + se
}
'

# The shell's door, one awk. The instant reaches awk through the environment, never `-v`, which would read a backslash
# in it as an escape and so could make an instant of something that is not one.
_time_epoch() {  # <ISO-8601 Z> -> epoch seconds; nothing, rc 1, when it is not an instant
  _TIME_ISO="${1:-}" awk "$_TIME_ISO_AWK"'BEGIN { e = iso2epoch(ENVIRON["_TIME_ISO"]); if (e < 0) exit 1; printf "%d\n", e }'
}
iso_epoch() { _time_epoch "${1:-}"; }   # <ISO-8601 Z> -> epoch seconds, empty if unreadable

# The stamp a record writes. It reads the machine's clock alone: a suite's pinned clock dates what a verdict reasons
# about, never the moment a line was written, so the stamp must not follow it.
iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }   # -> the instant now, UTC

# BSD `date -r` takes a word that is not a number as a file's name and prints that file's time, so only digits reach
# it. BSD is asked first and GNU second, the order of every copy: GNU's `date -r <digits>` names a file too, but
# fails when there is none, and so never prints a wrong time.
epoch_iso() {  # <epoch seconds> -> that second as an instant, UTC; nothing, rc 1, when the argument is not digits
  case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac
  date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

# A pin that is not a number is not a time: it is set aside and the machine's clock answers, so a mistyped pin can
# never be handed on as now.
time_now() {  # -> now, epoch seconds: BIONIC_NOW_EPOCH when it is digits, else the machine's clock
  case "${BIONIC_NOW_EPOCH:-}" in ''|*[!0-9]*) date -u +%s ;; *) printf '%s\n' "$BIONIC_NOW_EPOCH" ;; esac
}

# GNU stat first: GNU's `stat -f` is the filesystem's status and prints it with exit 0, so asking BSD's form first
# on GNU would read filesystem text as a time. BSD stat refuses `-c`, so on macOS the second form answers.
file_mtime() {  # <path> -> its modified time, epoch seconds; nothing, rc 1, when it cannot be stat'ed
  [ -n "${1:-}" ] || return 1
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}
