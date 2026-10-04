#!/bin/bash
# bin/land.sh <branch> <onto> — merges <branch> into <onto> in the current checkout.
set -uo pipefail
[ "$#" -eq 2 ] || { echo "usage: land.sh <branch> <onto>" >&2; exit 2; }
git checkout -q "$2" && git merge -q --no-ff -m "land $1" "$1" && echo "LANDED $1 onto $2"
