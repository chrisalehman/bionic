#!/bin/bash
# bin/reap.sh <table> — prints the checkouts the table lists for removal.
set -uo pipefail
[ "$#" -eq 1 ] || { echo "usage: reap.sh <table>" >&2; exit 2; }
. "$(dirname "$0")/../lib/reap.sh"
reap_scan "$1"
