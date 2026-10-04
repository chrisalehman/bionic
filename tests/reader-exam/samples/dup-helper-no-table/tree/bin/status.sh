#!/bin/bash
# bin/status.sh — one line per proof kind: the head it last proved, or `none`.
. "$(dirname "$0")/../lib/ledger.sh"
for kind in floor review; do
  line="$(proof_last "$kind")"
  if [ -n "$line" ]; then
    printf '%s %s\n' "$kind" "$(proof_field "$line" head)"
  else
    printf '%s none\n' "$kind"
  fi
done
