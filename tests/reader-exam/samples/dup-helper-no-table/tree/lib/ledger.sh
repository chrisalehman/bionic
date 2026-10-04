#!/bin/bash
# lib/ledger.sh — reading the proof record.

PROOFS_FILE="${PROOFS_FILE:-docs/proofs.txt}"

# proof_field <line> <key> — the value of <key>= in one proof line, or nothing.
proof_field() {
  printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -n 1
}

# proof_last <kind> — the newest proof line of <kind>, or nothing.
proof_last() {
  grep -E "^proved: kind=$1 " "$PROOFS_FILE" 2>/dev/null | tail -n 1
}
