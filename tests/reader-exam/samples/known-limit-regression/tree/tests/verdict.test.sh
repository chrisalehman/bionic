#!/bin/bash
. "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.." || exit 1
. lib/verdict.sh

check "a clean exit with clean output is stamped 0" "0" "$(suite_verdict 0 "ok - a")"
check "a failing exit is stamped as it is" "3" "$(suite_verdict 3 "ok - a")"
check "a clean exit after a not ok line is stamped 1" "1" "$(suite_verdict 0 "$(printf 'ok - a\nnot ok - b')")"
done_testing
