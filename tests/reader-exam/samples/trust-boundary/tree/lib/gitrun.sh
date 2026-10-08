#!/bin/bash
# lib/gitrun.sh — how trellis runs git.

# git_run <repo> <git argument>... — runs git in <repo> with the arguments given.
git_run() {
  local repo="$1"
  shift
  git -C "$repo" "$@"
}
