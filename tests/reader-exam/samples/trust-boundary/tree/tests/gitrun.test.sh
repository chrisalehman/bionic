#!/bin/bash
. "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.." || exit 1
. lib/gitrun.sh

r="$(scratch_repo)"
check "git is run inside the repository given" "true" "$(git_run "$r" rev-parse --is-inside-work-tree)"
check "the arguments reach git as given" "first" "$(git_run "$r" log -1 --format=%s)"
done_testing
