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

# ---------------------------------------------------------------------------
# D1 — "never merge under a running suite", as one predicate.
#
# A CONJUNCTION, and deliberately so. `busy` alone is every session that is
# doing anything at all, and a live `tests/run.sh` alone belongs to whichever
# project started it. Together they are the world the constraint names: this
# project has a session working, and a suite is running on the machine. The
# session half carries the project scoping — a session file states its cwd —
# and the process half carries the suite scoping.
#
# A SESSION FILE OUTLIVES ITS PROCESS. `kill -0` is a builtin, so the liveness
# question is asked of the kernel rather than of the file, exactly as
# lib/patrol.sh asks it: a stale file left by a crashed CLI must never be able
# to hold a lease open forever.

# Existence only. Same shape as hooks/stop-check.sh's and session-sweeper.sh's,
# for the same reason: `pgrep -f` matches the full command line, and `ps` covers
# a machine without pgrep.
_wt_proc_running() {  # <pattern>
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -f -- "$1" >/dev/null 2>&1
    return $?
  fi
  ps -eo command 2>/dev/null | grep -qF -- "$1"
}

# Is <cwd> this project? The main checkout itself, or any linked worktree under
# its `.worktrees` — which is where a writer running a suite actually sits, and
# so the case that matters most.
_wt_cwd_in_project() {  # <cwd> <main-root>
  local cwd="${1:-}" root="${2:-}"
  [ -n "$cwd" ] && [ -n "$root" ] || return 1
  [ "$cwd" = "$root" ] && return 0
  case "$cwd/" in "$root"/*) return 0 ;; esac
  return 1
}

# The D1 predicate. Prints `session=<name> pid=<pid> cwd=<cwd>` for the first
# session that satisfies it and returns 0; returns 1 when nothing does.
#
# NO JQ, NO OPINION. jq is this repo's only parser, and a machine without it
# cannot be shown a busy session — so the predicate answers "not proven" and the
# land proceeds. Refusing on a missing parser would make the verb unusable on
# exactly the degraded machine whose trees most need giving back, and D1 is a
# guard against a merge under a suite, not a guard against an unreadable
# directory.
_wt_busy_suite() {  # <main-root> -> session=... pid=... cwd=...
  local root="${1:-}" dir f pid cwd status name
  dir="$(_wt_claude_home)/sessions"
  [ -d "$dir" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  _wt_proc_running 'tests/run.sh' || return 1
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    pid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    status="$(jq -r '.status // empty' "$f" 2>/dev/null)"
    [ "$status" = "busy" ] || continue
    cwd="$(jq -r '.cwd // empty' "$f" 2>/dev/null)"
    _wt_cwd_in_project "$cwd" "$root" || continue
    kill -0 "$pid" 2>/dev/null || continue
    name="$(jq -r '.name // .sessionId // empty' "$f" 2>/dev/null)"
    printf 'session=%s pid=%s cwd=%s' "${name:-unknown}" "$pid" "$cwd"
    return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# The land verb.
#
# ONE ACT (C1). Merge the tree's branch --no-ff into the main checkout's CURRENT
# branch, remove the tree, prune. A land that did two of the three is a lease
# half-ended, and the third would be somebody's later chore.
#
# EVERY REFUSAL BEFORE THE MERGE. The order is cheapest-and-most-local first,
# and every one of them is checked before anything is changed, so a refused land
# leaves the repository exactly as it found it — with the single, deliberate
# exception of a legacy `.bionic` link, which is deleted on the way in because
# C2 retires it whatever the verdict.
#
# THE BRANCH IS NEVER DELETED. Same contract as `remove`: the tree is the leased
# resource, the branch is the work.
_wt_say() { printf '%s: %s\n' "${WORKTREE_CONTRACT_PROG:-spawn-worktree}" "$*"; }
_wt_refuse() { _wt_say "REFUSED reason=$*"; return 2; }

worktree_land() {  # <worktree path> -> LANDED | REFUSED
  local target="${1:-}" wt_abs root branch main_branch ahead busy merge_sha

  [ -n "$target" ] && [ -d "$target" ] || { _wt_refuse "no-such-worktree path=${target:-<none>}"; return 2; }
  # A linked worktree's `.git` is a FILE pointing into the shared repository;
  # the main checkout's is a directory. That is the guard against being handed
  # the main checkout to dismantle.
  [ -f "${target}/.git" ] || { _wt_refuse "not-a-linked-worktree path=${target}"; return 2; }

  wt_abs="$(_wt_abs "$target")" || { _wt_refuse "no-such-worktree path=${target}"; return 2; }
  root="$(_wt_main_root "$wt_abs")" || { _wt_refuse "repo-root-unresolvable path=${wt_abs}"; return 2; }
  [ -n "$root" ] || { _wt_refuse "repo-root-unresolvable path=${wt_abs}"; return 2; }
  branch="$(git -C "$wt_abs" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  [ -n "$branch" ] && [ "$branch" != "HEAD" ] || { _wt_refuse "worktree-head-unreadable path=${wt_abs}"; return 2; }

  # C2's retirement, taken on the way in: a legacy link is untracked work as far
  # as git is concerned and would refuse the removal below over it.
  _wt_drop_legacy_link "$wt_abs" || :

  if [ -n "$(git -C "$wt_abs" status --porcelain 2>/dev/null)" ]; then
    _wt_refuse "dirty-tree path=${wt_abs} branch=${branch}"; return 2
  fi

  main_branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  [ -n "$main_branch" ] || { _wt_refuse "main-head-unreadable root=${root}"; return 2; }
  ahead="$(git -C "$root" rev-list --count "HEAD..${branch}" 2>/dev/null)"
  case "$ahead" in ''|*[!0-9]*) _wt_refuse "branch-unreadable branch=${branch}"; return 2 ;; esac
  if [ "$ahead" -eq 0 ]; then
    _wt_refuse "nothing-to-land branch=${branch} onto=${main_branch}"; return 2
  fi

  busy="$(_wt_busy_suite "$root")" && {
    _wt_refuse "suite-running ${busy}"; return 2
  }

  # --no-ff ALWAYS: a fast-forward would erase the fact that this was a slice,
  # and the merge commit is what the ledger row points at.
  if ! git -C "$root" merge --no-ff -m "merge ${branch} (land)" "$branch" >/dev/null 2>&1; then
    git -C "$root" merge --abort >/dev/null 2>&1
    _wt_refuse "merge-failed branch=${branch} onto=${main_branch}"; return 2
  fi
  merge_sha="$(git -C "$root" rev-parse HEAD 2>/dev/null)"

  # No --force here either. If git refuses now, the merge has landed and the
  # tree has not gone; the line says both so the operator is not left guessing
  # which half happened.
  if ! git -C "$root" worktree remove "$wt_abs" >/dev/null 2>&1; then
    _wt_refuse "worktree-remove-refused path=${wt_abs} merged=${merge_sha}"; return 2
  fi
  git -C "$root" worktree prune >/dev/null 2>&1

  _wt_say "LANDED branch=${branch} merge=${merge_sha} removed=${wt_abs}"
  return 0
}
