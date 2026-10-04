#!/bin/bash
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/../lib/land.sh"

r="$(scratch_repo)"
check "a clean checkout may land" "" "$(land_refusal "$r")"
mkdir -p "$r/.trellis" && : > "$r/.trellis/run.log"
check "trellis's own scratch files are not dirt" "" "$(land_refusal "$r")"
: > "$r/work.txt"
check "an untracked file is dirt" "dirty: 1 paths differ from $(tree_head "$r")" "$(land_refusal "$r")"
done_testing
