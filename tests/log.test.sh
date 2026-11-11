#!/bin/bash
# tests/log.test.sh — payload/scripts/lib/log.sh, the one appender of a run's log.
#
# `log_append <type> <key>=<value>…` writes `run/v1|ev=<type>|<key>=<value>|…|at=<UTC seconds>` to the
# file RUN_LOG names, and refuses (exit 2, file unchanged) what would break the shape or the list.
#
#   §SHAPE   a line matches the shape and reads back by field name; no type, a bare word, a `|` in a
#            value and a caller's own `at=` are refused; LOG_AT stamps the line when in the shape, is refused
#            when not, and only lib/owed.sh sets it.
#   §TYPES   `matrix-set` and a retired word are refused; each of the 29 listed types is accepted.
#
# FIXTURE FIDELITY. The log is a real file in a scratch directory; only its path is synthesized.

set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/log.sh"

export RUN_LOG; RUN_LOG="$(mktemp -d)/record/w/run.log"
refused() {  # <label> <args…> -> exit 2 and the file byte-for-byte as it was
  local before; before="$(cat "$RUN_LOG")"; local l="$1"; shift
  log_append "$@" 2>/dev/null; expect_eq "$l: exit 2" 2 "$?"
  expect_eq "$l: file unchanged" "$before" "$(cat "$RUN_LOG")"
}

section "SHAPE"
log_append ready row=T6 name=w50-T6; expect_eq "a valid call exits 0" 0 "$?"
log_append step n=4 by=me; line="$(tail -n 1 "$RUN_LOG")"
expect_regex "the line is run/v1, ev, fields, at as UTC seconds" \
  '^run/v1\|ev=step\|n=4\|by=me\|at=[0-9]{4}(-[0-9]{2}){2}T[0-9]{2}(:[0-9]{2}){2}Z$' "$line"
expect_eq "a field reads back by name" "me" "$(line_value "$line" by)"
refused "no event type"
refused "a bare word" step n
refused "a value with a bar" step "why=a|b"
refused "a key that sets at" step at=1
LOG_AT=2026-10-06T11:48:01Z log_append ask key=a:b
expect_eq "a caller's instant in the log's shape stamps the line" "2026-10-06T11:48:01Z" "$(line_value "$(tail -n 1 "$RUN_LOG")" at)"
LOG_AT=2026-10-06T11:48Z refused "a caller's instant off the log's shape" ask key=a:b
expect_eq "no file but the asks library hands the appender an instant" "payload/scripts/lib/owed.sh" \
  "$(cd "$BIONIC_SCRIPTS_DIR" && /usr/bin/grep -rl 'LOG_AT=' payload hooks | LC_ALL=C sort | paste -sd' ' -)"

section "TYPES"
refused "ev=matrix-set" matrix-set row=T1
refused "a retired type" settled row=T1
refused "a type holding a space" "ready step" row=T1
for t in ready candidate verdict published returned stalled standing admitted void run walk step \
  approval proof finding waiver decision order bind handoff dispatch tree born ask stop debt \
  abandon cancel hand; do
  log_append "$t" k=v 2>/dev/null; rc=$?; n=$((${n:-0} + 1)); expect_eq "$t is accepted" 0 "$rc"
done
expect_eq "twenty-nine types were driven" 29 "$n"

finish
