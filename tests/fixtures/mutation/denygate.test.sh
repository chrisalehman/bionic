#!/bin/bash
# Discriminating fixture test for the deny mechanism: it asserts the decision
# field, so flipping deny to allow takes it RED.
set -uo pipefail
GATE="$(cd "$(dirname "$0")" && pwd)/denygate.sh"

out="$(bash "$GATE" block 2>/dev/null)"
case "$out" in
  *'"permissionDecision":"deny"'*) ;;
  *) echo "FAIL: no deny decision emitted"; exit 1 ;;
esac
echo "denygate.test.sh: 1/1 passed"
