#!/bin/bash
# worktree.sh — the worktree LEASE (bionic 1.4.0, spec AC-11/AC-28; design
# ledger C1 "worktree lease", C2 ".bionic symlink retired").
#
# WHAT THIS FILE OWNS. A spawned worktree is a leased slot, bound to the ledger
# row that dispatched its writer. The lease ends when the row is
# fact-discharged, and ending it is ONE act: merge the branch, remove the tree,
# prune. Three callers need that act and the two facts around it —
# `spawn-worktree.sh land`, `hooks/stop-orders.sh standdown`, and the Patrol
# tick's lease-overrun line — so the behaviour lives here and each caller is a
# call site rather than a fourth definition of "discharged".
#
# SOURCED, NOT EXECUTED. Function names are prefixed `worktree_` (public) or
# `_wt_` (internal); nothing here runs at source time and nothing here exits.
#
# THE SYMLINK IS RETIRED (C2). `<worktree>/.bionic -> <main-root>/.bionic` is no
# longer planted by anything; a writer in a spawned tree reaches the state
# directory through project_root's git-common-dir mapping instead. What remains
# is the cleanup: `worktree_legacy_links` lists the ones an older bionic left
# behind, and the teardown verbs delete one when they meet it.
#
# NO `--force`, ANYWHERE. git's refusal to discard uncommitted work is the
# feature; a land that forced would be a lease that ate a writer's work.

# The CLI's config directory, through the same override chain
# payload/scripts/lib/patrol.sh reads. One chain for this directory, not two.
_wt_claude_home() {
  printf '%s' "${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
}

# Physical absolute path of a directory. No `realpath`: BSD's is flagless and it
# is absent on some targets, and every path this file canonicalises is a
# directory (the same finding as lib/root.sh's).
_wt_abs() {  # <dir>
  [ -d "${1:-}" ] || return 1
  ( cd "$1" 2>/dev/null && pwd -P )
}

# The MAIN checkout's root from anywhere inside the repository, including from
# inside a linked worktree where --show-toplevel would answer with the linked
# tree. Same resolution spawn-worktree.sh does, for the same reason.
_wt_main_root() {  # [dir]
  local d="${1:-.}" common
  common="$( cd "$d" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null )"
  [ -n "$common" ] || common="$( cd "$d" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null )"
  [ -n "$common" ] || return 1
  ( cd "$d" 2>/dev/null && cd "$common/.." 2>/dev/null && pwd -P )
}

# Every legacy `<main-root>/.worktrees/*/.bionic` that is a SYMLINK, absolute,
# one per line. A real `.bionic` directory in a tree is the branch's own content
# and is never listed: the difference between deleting a dead link and deleting
# a writer's state is this test.
worktree_legacy_links() {  # <main-root> -> <abs path> per line
  local root d link
  root="$(_wt_abs "${1:-}")" || return 0
  [ -d "${root}/.worktrees" ] || return 0
  for d in "${root}/.worktrees"/*; do
    [ -d "$d" ] || continue
    link="${d}/.bionic"
    [ -L "$link" ] || continue
    printf '%s\n' "$link"
  done
}

# Delete a legacy link if one is there, and say whether it did. Never touches a
# directory, and never follows the link.
_wt_drop_legacy_link() {  # <worktree abs> -> 0 if one was deleted
  local link="${1:-}/.bionic"
  [ -L "$link" ] || return 1
  rm -f "$link" 2>/dev/null
  return 0
}
