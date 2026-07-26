#!/bin/bash
# DISCRIMINATING fixture test: it asserts the wall itself, so neutering gate.sh's
# blocking paths takes it RED. That is what makes a pointer to it honest.
set -uo pipefail
GATE="$(cd "$(dirname "$0")" && pwd)/gate.sh"

fail=0
bash "$GATE" block >/dev/null 2>&1
[ "$?" -eq 2 ] || { echo "FAIL: 'block' did not exit 2"; fail=1; }
bash "$GATE" force >/dev/null 2>&1
[ "$?" -eq 2 ] || { echo "FAIL: 'force' did not exit 2"; fail=1; }
bash "$GATE" ok >/dev/null 2>&1
[ "$?" -eq 0 ] || { echo "FAIL: 'ok' did not exit 0"; fail=1; }

[ "$fail" -eq 0 ] || exit 1
echo "gate.test.sh: 3/3 passed"
