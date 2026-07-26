#!/bin/bash
# Fixture test for noblock.sh. Passes; there is simply nothing to disprove.
set -uo pipefail
GATE="$(cd "$(dirname "$0")" && pwd)/noblock.sh"

out="$(bash "$GATE" 2>/dev/null)"
case "$out" in
  *advisory*) ;;
  *) echo "FAIL: advisory output missing"; exit 1 ;;
esac
echo "noblock.test.sh: 1/1 passed"
