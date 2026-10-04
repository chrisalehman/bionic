#!/bin/bash
# lib/tree.sh — what trellis knows about a checkout.

# tree_head <dir> — the commit <dir> has checked out.
tree_head() {
  git -C "$1" rev-parse --verify -q 'HEAD^{commit}'
}

# tree_dirty_count <dir> — how many paths in <dir> differ from its head. trellis keeps its own
# scratch files under .trellis/, which are not the work's, so they are not counted.
tree_dirty_count() {
  git -C "$1" status --porcelain 2>/dev/null | grep -cvxF -- '?? .trellis/'
}
