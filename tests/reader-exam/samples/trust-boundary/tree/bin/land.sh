#!/bin/bash
# bin/land.sh <branch> <onto> — merges <branch> into <onto> in the current checkout.
set -uo pipefail
[ "$#" -eq 2 ] || { echo "usage: land.sh <branch> <onto>" >&2; exit 2; }
. "$(dirname "$0")/../lib/gitrun.sh"
git_run . checkout -q "$2" && git_run . merge -q --no-ff -m "land $1" "refs/heads/$1" && echo "LANDED $1 onto $2"
