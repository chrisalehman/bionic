#!/bin/bash
# lib/reach.sh — which suites a change reaches.

REACH_MAP="${REACH_MAP:-tests/map.txt}"

# reach_suites <file>... — one suite per line, sorted and unique, for the files given; a file
# no line of the map covers prints `unbounded` instead.
reach_suites() {
  local f prefix suite hit
  for f in "$@"; do
    hit=0
    while read -r prefix suite; do
      [ -n "$prefix" ] || continue
      case "$f" in "$prefix"*) printf '%s\n' "$suite"; hit=1 ;; esac
    done < "$REACH_MAP"
    [ "$hit" -eq 1 ] || echo unbounded
  done | sort -u
}
