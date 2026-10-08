#!/bin/bash
# bin/run-suite.sh <suite> — runs one suite in the current checkout and appends its stamp:
#   stamp head=<sha> rc=<exit code> suite=<suite>
set -uo pipefail
[ "$#" -eq 1 ] || { echo "usage: run-suite.sh <suite>" >&2; exit 2; }
. "$(dirname "$0")/../lib/verdict.sh"
gitdir="$(git rev-parse --absolute-git-dir)" || exit 2
head="$(git rev-parse --verify -q 'HEAD^{commit}')" || exit 2
out="$(bash "$1" 2>&1)"
ran=$?
rc="$(suite_verdict "$ran" "$out")"
printf '%s\n' "$out"
printf 'stamp head=%s rc=%s suite=%s\n' "$head" "$rc" "$1" >> "$gitdir/trellis-stamps"
exit "$rc"
