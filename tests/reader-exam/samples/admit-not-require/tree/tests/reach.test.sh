#!/bin/bash
. "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.." || exit 1
. lib/reach.sh

check "a mapped library file reaches its suite" "tests/reach.test.sh" "$(reach_suites lib/reach.sh)"
check "an unmapped file is unbounded" "unbounded" "$(reach_suites docs/new/notes.md)"
done_testing
