#!/bin/bash
# tests/lib.sh — what every trellis suite shares.
FAILED=0
# A suite reads no one's git configuration, and commits as a fixed name.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
SCRATCH="$(mktemp -d)" || exit 1
trap 'rm -rf "$SCRATCH"' EXIT

# check <name> <expected> <actual>
check() {
  if [ "$2" = "$3" ]; then
    echo "ok - $1"
  else
    echo "not ok - $1: expected '$2', got '$3'"
    FAILED=1
  fi
}

# scratch_repo — a new repository with one commit, under $SCRATCH; prints its path.
scratch_repo() {
  local d
  d="$(mktemp -d "$SCRATCH/repo.XXXXXX")" || return 1
  git -C "$d" init -q && git -C "$d" commit -q --allow-empty -m first && printf '%s\n' "$d"
}

# done_testing — exit with the suite's verdict.
done_testing() { exit "$FAILED"; }
