#!/bin/bash
# lib/reap.sh — which task checkouts may be removed.

# Whether a checkout may be listed for removal, from its idle days, its uncommitted flag and its
# landed flag: 0 when it may.
reap_listed() {
  local idle="$1" dirty="$2" landed="$3"
  [ "$dirty" -eq 0 ] || return 1
  [ "$landed" -eq 1 ] && [ "$idle" -ge 1 ]
}

# reap_scan <table> — the names the table lists for removal, one per line.
reap_scan() {
  local name idle dirty landed
  while read -r name idle dirty landed; do
    [ -n "$name" ] || continue
    if reap_listed "$idle" "$dirty" "$landed"; then
      printf '%s\n' "$name"
    fi
  done < "$1"
}
