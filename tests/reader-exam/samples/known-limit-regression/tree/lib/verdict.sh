#!/bin/bash
# lib/verdict.sh — what a suite run is stamped as.

# suite_verdict <exit code> <output> — the exit code to stamp. A suite that exits 0 after printing
# a line that starts with `not ok` is stamped 1.
suite_verdict() {
  if [ "$1" -eq 0 ] && printf '%s\n' "$2" | grep -q '^not ok'; then
    echo 1
  else
    echo "$1"
  fi
}
