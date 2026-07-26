#!/bin/bash
# NON-DISCRIMINATING fixture test, on purpose. It asserts gate.sh's advisory
# output and never the wall, so it passes whether or not the wall exists.
#
# It differs from gate.test.sh in exactly one respect — what it asserts — and
# both point at the same enforcer. The harness must reach opposite verdicts on
# them, which is the whole claim of slice 4/2.
set -uo pipefail
GATE="$(cd "$(dirname "$0")" && pwd)/gate.sh"

out="$(bash "$GATE" block 2>/dev/null)"
case "$out" in
  *"gate v1"*) ;;
  *) echo "FAIL: advisory banner missing"; exit 1 ;;
esac
echo "gate-weak.test.sh: 1/1 passed"
