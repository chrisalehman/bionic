#!/bin/bash
. "$(dirname "$0")/lib.sh"
land="$(cd "$(dirname "$0")/.." && pwd)/bin/land.sh"

r="$(scratch_repo)"
base="$(git -C "$r" symbolic-ref --short HEAD)"
git -C "$r" checkout -q -b task
: > "$r/a.txt"
git -C "$r" add a.txt && git -C "$r" commit -q -m a
out="$(cd "$r" && bash "$land" task "$base")"
check "a branch lands onto its base" "LANDED task onto $base" "$out"
check "the base holds the branch's file" "a.txt" "$(git -C "$r" ls-files a.txt)"
done_testing
