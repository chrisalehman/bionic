#!/bin/bash
. "$(dirname "$0")/lib.sh"
run="$(cd "$(dirname "$0")/.." && pwd)/bin/run-suite.sh"

r="$(scratch_repo)"
head="$(git -C "$r" rev-parse HEAD)"
printf 'exit 1\n' > "$SCRATCH/red.test.sh"
( cd "$r" && bash "$run" "$SCRATCH/red.test.sh" )
check "the suite's exit code is passed on" "1" "$?"
check "a red run is stamped" "stamp head=$head rc=1 suite=$SCRATCH/red.test.sh" "$(cat "$r/.git/trellis-stamps")"
done_testing
