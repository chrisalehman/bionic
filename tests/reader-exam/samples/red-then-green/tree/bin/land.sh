#!/bin/bash
# bin/land.sh <onto> — merges the branch the current checkout has out into <onto>.
set -uo pipefail
[ "$#" -eq 1 ] || { echo "usage: land.sh <onto>" >&2; exit 2; }
branch="$(git symbolic-ref --short HEAD)" || exit 2
git checkout -q "$1" && git merge -q --no-ff -m "land $branch" "$branch" && echo "LANDED $branch onto $1"
