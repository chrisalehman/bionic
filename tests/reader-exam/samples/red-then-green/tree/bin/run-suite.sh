#!/bin/bash
# bin/run-suite.sh <suite> — runs one suite in the current checkout and appends its stamp:
#   stamp head=<sha> rc=<exit code> suite=<suite>
set -uo pipefail
[ "$#" -eq 1 ] || { echo "usage: run-suite.sh <suite>" >&2; exit 2; }
gitdir="$(git rev-parse --absolute-git-dir)" || exit 2
head="$(git rev-parse --verify -q 'HEAD^{commit}')" || exit 2
bash "$1"
rc=$?
printf 'stamp head=%s rc=%s suite=%s\n' "$head" "$rc" "$1" >> "$gitdir/trellis-stamps"
exit "$rc"
