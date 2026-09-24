#!/bin/bash
# worktree.sh — the worktree LEASE (bionic 1.4.0, spec AC-11/AC-28; design
# ledger C1 "worktree lease", C2 ".bionic symlink retired").
#
# WHAT THIS FILE OWNS. A spawned worktree is a leased slot, bound to the ledger
# row that dispatched its writer. The lease ends when the row is
# fact-discharged, and ending it is ONE act: merge the branch into the plan's
# working branch, remove the tree, prune. TWO callers end a lease —
# `spawn-worktree.sh land` and `hooks/stop-orders.sh standdown` — and both call
# `worktree_land_for_session`, the one path from a session to a land (wave-20
# T8, REQ-1, D1). The Patrol tick is a READER here and never a caller of the
# act: its lease-overrun line (`worktree_lease_overruns`) reports a tree that
# outlived its row, and it lands nothing and removes nothing. The behaviour
# lives here so each caller is a call site rather than another definition of
# "discharged".
#
# SOURCED, NOT EXECUTED. Function names are prefixed `worktree_` (public) or
# `_wt_` (internal); nothing here runs at source time and nothing here exits.
#
# THE SYMLINK IS BACK (D7, wave-13-fixit-180, reopens C2).
# `<worktree>/.bionic -> <main-root>/.bionic` is planted again by
# `spawn-worktree.sh create`, so a plain relative shell write — no hook in the
# loop — lands in the one project memory instead of being orphaned inside the
# tree; every HOOK read still reaches the state directory through
# project_root's git-common-dir mapping, unaffected. `worktree_legacy_links`
# lists only a link that resolves somewhere OTHER than the main root's
# `.bionic` — a correctly-pointing alias is the expected state, not a finding
# — and the teardown verbs (`remove`, `land`) delete whichever kind they meet,
# same as before.
#
# NO `--force`, ANYWHERE. git's refusal to discard uncommitted work is the
# feature; a land that forced would be a lease that ate a writer's work.

_wt_self_dir() { dirname "${BASH_SOURCE[0]}"; }
# roots.sh, THE SOFT SOURCE — the idiom this file already uses for git-argv.sh, taken at
# source time because two of this file's roots are wanted on every path through it. Every
# root resolver in the tree has one definition there (epic-22 wave-01, N1); this file is a
# caller of `claude_home` (three copies before N1: here, lib/patrol.sh, lib/deps.sh) and
# `worktree_root` (three: here as `_wt_main_root`, lib/patrol.sh, spawn-worktree.sh).
if ! declare -F claude_home >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$( cd "$(_wt_self_dir)" 2>/dev/null && pwd -P )/roots.sh"
fi

# Physical absolute path of a directory. No `realpath`: BSD's is flagless and it
# is absent on some targets, and every path this file canonicalises is a
# directory (the same finding as lib/root.sh's).
_wt_abs() {  # <dir>
  [ -d "${1:-}" ] || return 1
  ( cd "$1" 2>/dev/null && pwd -P )
}

# Is this branch one no automated write may reach? THE LIST HAS ONE HOME:
# `git_branch_protected` in the sibling git-argv.sh, which hooks/protect-main.sh
# already sources for exactly the same question about a `git push`. That wall
# reads push argv and never sees a merge, so `land` is the second reader of the
# same list — and a second COPY of the list is how two walls come to disagree
# about which branch is the branch.
#
# LOADED LAZILY, from this file's own directory, the way lib/detect.sh loads
# lib/deps.sh: every caller of this library pays for git-argv.sh only if it
# actually asks, and a caller that already sourced it pays nothing.
#
# FAIL CLOSED (design ledger S4). Exit 2 means "unknowable", not "not
# protected": a wall that cannot read its own list must refuse rather than wave
# the merge through.
_wt_branch_protected() {  # <branch> -> 0 protected, 1 not, 2 unknowable
  local lib
  if ! declare -f git_branch_protected >/dev/null 2>&1; then
    lib="$( cd "$(_wt_self_dir)" 2>/dev/null && pwd -P )/git-argv.sh"
    [ -r "$lib" ] || return 2
    # shellcheck source=/dev/null
    . "$lib" 2>/dev/null || return 2
    declare -f git_branch_protected >/dev/null 2>&1 || return 2
  fi
  git_branch_protected "${1:-}"
}


# Every MIS-POINTED `<main-root>/.worktrees/*/.bionic` symlink, absolute, one
# per line (D7). A link resolving to the main root's OWN `.bionic` — exactly
# what `spawn-worktree.sh create` plants — is the expected, constructive state
# and is never listed; only a link some other bionic version, or some other
# hand, pointed SOMEWHERE ELSE (including a broken target that resolves to
# nothing) is stale. A real `.bionic` directory in a tree is the branch's own
# content and is never listed either: the difference between deleting a dead
# link and deleting a writer's state is this test.
worktree_legacy_links() {  # <main-root> -> <abs path> per line
  local root d link resolved expected
  root="$(_wt_abs "${1:-}")" || return 0
  [ -d "${root}/.worktrees" ] || return 0
  expected="$(cd "${root}/.bionic" 2>/dev/null && pwd -P)"
  for d in "${root}/.worktrees"/*; do
    [ -d "$d" ] || continue
    link="${d}/.bionic"
    [ -L "$link" ] || continue
    resolved="$(cd "$link" 2>/dev/null && pwd -P)"
    [ -n "$resolved" ] && [ "$resolved" = "$expected" ] && continue
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
# so the case that matters most. A second directory, when given, counts too:
# the land's TARGET checkout (T8, D1), which `spawn-worktree.sh create` can
# place outside the root with an absolute parent. The merge happens there, so a
# suite running there is the one the constraint names.
_wt_cwd_in_project() {  # <cwd> <main-root> [target-checkout]
  local cwd="${1:-}" root="${2:-}" co="${3:-}"
  [ -n "$cwd" ] && [ -n "$root" ] || return 1
  [ "$cwd" = "$root" ] && return 0
  case "$cwd/" in "$root"/*) return 0 ;; esac
  if [ -n "$co" ]; then
    [ "$cwd" = "$co" ] && return 0
    case "$cwd/" in "$co"/*) return 0 ;; esac
  fi
  return 1
}

# The D1 predicate. Prints `session=<name> pid=<pid> cwd=<cwd>` for the first
# session that satisfies it and returns 0; returns 1 when nothing does.
#
# THE CALLER'S OWN SESSION NEVER COUNTS AGAINST ITSELF (wave-20 T8b, review R8/F3). A
# session is BUSY for the whole span of the tool call that is asking this question, so
# without an exclusion the conjunction always found at least one hit — the caller's own
# session file, busy, in this project — and D1 reduced to "any tests/run.sh anywhere,
# landed by anybody" (T12's live bed: the first head attempt was refused naming its own
# session, F3). `<exclude-sid>` is the landing session's own id, threaded down from
# `worktree_land`'s third argument; a busy session file whose `sessionId` equals it is
# skipped, but every OTHER busy session in this project still refuses the land — that
# refusal is the reason this predicate exists.
#
# NO JQ, NO OPINION. jq is this repo's only parser, and a machine without it
# cannot be shown a busy session — so the predicate answers "not proven" and the
# land proceeds. Refusing on a missing parser would make the verb unusable on
# exactly the degraded machine whose trees most need giving back, and D1 is a
# guard against a merge under a suite, not a guard against an unreadable
# directory.
_wt_busy_suite() {  # <main-root> [target-checkout] [exclude-sid] -> session=... pid=... cwd=...
  local root="${1:-}" co="${2:-}" exclude="${3:-}" dir f pid cwd status name sid
  dir="$(claude_home)/sessions"
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
    _wt_cwd_in_project "$cwd" "$root" "$co" || continue
    sid="$(jq -r '.sessionId // empty' "$f" 2>/dev/null)"
    [ -n "$exclude" ] && [ -n "$sid" ] && [ "$sid" = "$exclude" ] && continue
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
# ONE ACT (C1). Merge the tree's branch --no-ff into <onto>, IN THE CHECKOUT
# THAT HOLDS <onto>, remove the tree, prune. A land that did two of the three is
# a lease half-ended, and the third would be somebody's later chore.
#
# THE TARGET IS NAMED, NEVER READ OFF THE MAIN CHECKOUT (wave-20 T8, REQ-1, D1).
# Until 1.8.7 the merge went into whatever branch the main checkout sat on. A
# wave's integration branch lives in its own checkout under `.worktrees/`, and a
# human may have the main checkout on a feature branch of their own: the land
# merged a task into that feature branch and left the wave branch unmerged
# (report #9). <onto> is required; `worktree_land_for_session`, below, reads it
# off the session's bound plan, and that is the path every caller takes. The
# checkout holding <onto> is found in `git worktree list --porcelain`
# (`worktree_checkout_of`), and the merge runs there with `git -C`.
#
# EVERY REFUSAL BEFORE THE MERGE. The order is cheapest-and-most-local first,
# and every one of them is checked before anything is changed, so a refused land
# leaves the repository exactly as it found it — with the single, deliberate
# exception of a legacy `.bionic` link, which is deleted on the way in because
# C2 retires it whatever the verdict.
#
# TWO BOUNDS ON THE POWER (security review F1). This function merges into a
# branch and deletes a worktree; both of those are irreversible enough that
# WHICH branch and WHICH tree cannot be left to the caller's word for it.
#
#   PROTECTED BRANCH. The branch merged into — <onto> — is never `main`/`master`.
#   hooks/protect-main.sh is the wall that keeps unreviewed work off those
#   branches, and it reads `git push` argv — a local `git merge --no-ff` is
#   invisible to it. Without this refusal a land onto `main` — before T8, any
#   land from a main checkout left where every checkout starts — was an
#   unwalled write to the protected branch, with the unmerged tree deleted in
#   the same call. The list is `git_branch_protected`'s, not a second copy of it.
#
#   INSIDE THE FARM. The tree landed sits under `<main-root>/.worktrees/`,
#   the only place this lease ever hands one out. `.git`-is-a-file proves the
#   path is A linked worktree of this repository; it does not prove the lease
#   issued it, and `spawn-worktree.sh land <path>` will take any path a caller
#   names. Any other linked worktree is somebody else's and is refused rather
#   than merged and removed.
#
# Both are checked before the legacy-link deletion above, so the deliberate
# exception applies only to a tree this lease is actually entitled to touch.
#
# A CONSEQUENCE, stated rather than hidden: `spawn-worktree.sh create` honours
# an absolute parent directory outside the checkout, and a tree created that way
# is not landable by this verb. Remove it, or merge it by hand.
#
# THE BRANCH IS NEVER DELETED. Same contract as `remove`: the tree is the leased
# resource, the branch is the work.
_wt_say() { printf '%s: %s\n' "${WORKTREE_CONTRACT_PROG:-spawn-worktree}" "$*"; }
_wt_refuse() { _wt_say "REFUSED reason=$*"; return 2; }

# The checkout holding <branch>, from `git worktree list --porcelain`: one
# `worktree <path>` stanza per checkout, its `branch refs/heads/<b>` line naming
# what it holds. A detached or bare stanza holds no branch and is skipped. The
# path is printed physically (`pwd -P`), the form every other path in this file
# is compared in.
#
#   0  one checkout holds it -> its path
#   1  no checkout holds it
#   2  more than one does (`worktree add --force` makes that possible) -> the
#      paths, space-separated: which of them to merge in is not a guess to make
#   3  the one stanza's directory cannot be entered (a prunable entry) -> its path
worktree_checkout_of() {  # <root> <branch>
  local root="${1:-}" want="refs/heads/${2:-}" line path="" hits="" n=0 abs
  [ -n "${2:-}" ] || return 1
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      "branch "*)
        [ "${line#branch }" = "$want" ] || continue
        n=$((n + 1)); hits="${hits:+$hits }${path}" ;;
    esac
  done <<EOF
$(git -C "$root" worktree list --porcelain 2>/dev/null)
EOF
  [ "$n" -eq 0 ] && return 1
  if [ "$n" -gt 1 ]; then printf '%s' "$hits"; return 2; fi
  abs="$(_wt_abs "$hits")" || { printf '%s' "$hits"; return 3; }
  printf '%s' "$abs"
}

worktree_land() {  # <worktree path> <onto> [caller-sid] -> LANDED | REFUSED
  local target="${1:-}" onto="${2:-}" sid="${3:-}" wt_abs root branch co ahead busy merge_sha rc

  [ -n "$target" ] && [ -d "$target" ] || { _wt_refuse "no-such-worktree path=${target:-<none>}"; return 2; }
  # A linked worktree's `.git` is a FILE pointing into the shared repository;
  # the main checkout's is a directory. That is the guard against being handed
  # the main checkout to dismantle.
  [ -f "${target}/.git" ] || { _wt_refuse "not-a-linked-worktree path=${target}"; return 2; }

  wt_abs="$(_wt_abs "$target")" || { _wt_refuse "no-such-worktree path=${target}"; return 2; }
  root="$(worktree_root "$wt_abs")" || { _wt_refuse "repo-root-unresolvable path=${wt_abs}"; return 2; }
  [ -n "$root" ] || { _wt_refuse "repo-root-unresolvable path=${wt_abs}"; return 2; }

  # INSIDE THE FARM. Both sides are already physical absolute paths, so this is
  # a path-SEGMENT test and not a string-prefix one: the trailing slash is what
  # makes `<root>/.worktrees-decoy/x` a sibling rather than a member, and `?*`
  # is what keeps `<root>/.worktrees/` itself — the farm, not a tree — out.
  case "$wt_abs" in
    "${root}/.worktrees/"?*) : ;;
    *) _wt_refuse "outside-worktrees path=${wt_abs} root=${root}"; return 2 ;;
  esac

  # THE BRANCH MERGED INTO, named by the caller and judged before anything is
  # touched: it must be a branch, held by exactly one checkout, and not protected.
  [ -n "$onto" ] || { _wt_refuse "onto-missing path=${wt_abs}"; return 2; }
  git -C "$root" show-ref --verify --quiet "refs/heads/${onto}" \
    || { _wt_refuse "onto-unknown branch=${onto} root=${root}"; return 2; }
  co="$(worktree_checkout_of "$root" "$onto")"; rc=$?
  case $rc in
    0) : ;;
    1) _wt_refuse "onto-not-checked-out branch=${onto} root=${root}"; return 2 ;;
    2) _wt_refuse "onto-ambiguous branch=${onto} checkouts=${co// /,}"; return 2 ;;
    *) _wt_refuse "onto-checkout-unresolvable branch=${onto} checkout=${co}"; return 2 ;;
  esac
  _wt_branch_protected "$onto"
  case $? in
    0) _wt_refuse "protected-branch branch=${onto} checkout=${co}"; return 2 ;;
    2) _wt_refuse "protected-branch-unknowable branch=${onto} checkout=${co}"; return 2 ;;
  esac

  branch="$(git -C "$wt_abs" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  [ -n "$branch" ] && [ "$branch" != "HEAD" ] || { _wt_refuse "worktree-head-unreadable path=${wt_abs}"; return 2; }

  # C2's retirement, taken on the way in: a legacy link is untracked work as far
  # as git is concerned and would refuse the removal below over it.
  _wt_drop_legacy_link "$wt_abs" || :

  if [ -n "$(git -C "$wt_abs" status --porcelain 2>/dev/null)" ]; then
    _wt_refuse "dirty-tree path=${wt_abs} branch=${branch}"; return 2
  fi

  ahead="$(git -C "$root" rev-list --count "refs/heads/${onto}..${branch}" 2>/dev/null)"
  case "$ahead" in ''|*[!0-9]*) _wt_refuse "branch-unreadable branch=${branch}"; return 2 ;; esac
  if [ "$ahead" -eq 0 ]; then
    _wt_refuse "nothing-to-land branch=${branch} onto=${onto}"; return 2
  fi

  # THE TARGET CHECKOUT IS CLEAN IN WHAT GIT TRACKS. A merge into a checkout
  # holding staged or modified tracked files mixes somebody's unfinished work
  # into the merge — or fails half-way on it. Untracked files are not read: the
  # `.bionic` alias and `.worktrees/` live there by design.
  if [ -n "$(git -C "$co" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    _wt_refuse "onto-checkout-dirty checkout=${co} branch=${onto}"; return 2
  fi

  busy="$(_wt_busy_suite "$root" "$co" "$sid")" && {
    _wt_refuse "suite-running ${busy}"; return 2
  }

  # --no-ff ALWAYS: a fast-forward would erase the fact that this was a task,
  # and the merge commit is what the ledger row points at.
  if ! git -C "$co" merge --no-ff -m "merge ${branch} (land)" "$branch" >/dev/null 2>&1; then
    git -C "$co" merge --abort >/dev/null 2>&1
    _wt_refuse "merge-failed branch=${branch} onto=${onto} checkout=${co}"; return 2
  fi
  merge_sha="$(git -C "$co" rev-parse HEAD 2>/dev/null)"

  # No --force here either. If git refuses now, the merge has landed and the
  # tree has not gone; the line says both so the operator is not left guessing
  # which half happened.
  if ! git -C "$root" worktree remove "$wt_abs" >/dev/null 2>&1; then
    _wt_refuse "worktree-remove-refused path=${wt_abs} merged=${merge_sha}"; return 2
  fi
  git -C "$root" worktree prune >/dev/null 2>&1

  _wt_say "LANDED branch=${branch} onto=${onto} checkout=${co} merge=${merge_sha} removed=${wt_abs}"
  return 0
}

# THE ONE PATH FROM A SESSION TO A LAND (wave-20 T8, REQ-1, D1). `spawn-worktree.sh
# land` and `hooks/stop-orders.sh standdown` both call this and nothing else, so
# "where does this tree land" has one answer: the session's bound plan's
# `working-branch:`, read by `session_working_branch` (lib/run.sh). Every
# answer that is not a branch is a refusal naming its reason — no session id,
# `no-bound-plan` (the unbound `fallback` and `none` alike: the root's newest
# run is not this session's target), `bound-unreadable`, `no-working-branch` —
# and nothing is touched on any of them.
#
# run.sh IS LOADED LAZILY, from this file's own directory, the way
# `_wt_branch_protected` loads git-argv.sh: neither caller's library list has
# to change, and a caller that already sourced it pays nothing. A run.sh that
# cannot be loaded is a refusal, never a land onto a guessed branch.
worktree_land_for_session() {  # <worktree path> <root> <sid> -> LANDED | REFUSED
  local target="${1:-}" root="${2:-}" sid="${3:-}" lib onto
  [ -n "$sid" ] || { _wt_refuse "no-session path=${target:-<none>}"; return 2; }
  if ! declare -f session_working_branch >/dev/null 2>&1; then
    lib="$( cd "$(_wt_self_dir)" 2>/dev/null && pwd -P )/run.sh"
    # shellcheck source=/dev/null
    [ -r "$lib" ] && . "$lib" 2>/dev/null
    declare -f session_working_branch >/dev/null 2>&1 \
      || { _wt_refuse "run-library-unloadable path=${lib}"; return 2; }
  fi
  onto="$(session_working_branch "$root" "$sid")" || { _wt_refuse "${onto:-no-bound-plan}"; return 2; }
  worktree_land "$target" "$onto" "$sid"
}

# ---------------------------------------------------------------------------
# Lease overruns — a tree still standing after its row was discharged.
#
# C1's tick finding, and only a finding: this function lands nothing and
# removes nothing. A tree whose lease has ended is a slot counted against the
# worktree budget that nobody holds, and the Patrol's job is to say so.
#
# THE WALK STARTS AT THE TREES, not at the rows: what is being reported is disk
# that outlived a contract, so a discharged row with no tree is silent (its
# lease ended correctly) and a tree with no discharged row is silent (its lease
# is still running).
#
# THE MAPPING IS BY CONVENTION, and it has to be: the roster carries a row's
# name, its deliverable and its addresses, but no worktree path — nothing writes
# one. A tree at `.worktrees/<dir>` belongs to the row named `W-<DIR>`
# uppercased, which is the spelling every wave in this repo has dispatched
# under; the bare `<dir>` is accepted too, for a caller that names its rows
# without the prefix.

# One `|`-delimited field, BY KEY. Position would read the wrong value on a line
# whose schema gained a field, which is the same reason every other reader in
# this repo does it this way.
_wt_field() {  # <line> <key>
  local f
  while IFS= read -r f; do
    case "$f" in "${2}="*) printf '%s' "${f#"${2}="}"; return 0 ;; esac
  done <<EOF
$(printf '%s' "${1:-}" | tr '|' '\n')
EOF
  printf ''
}

# The discharge set, spelled the way hooks/stop-orders.sh and hooks/stop-guard.sh
# spell it: an ack, or a WAIVED contract, or a MET one. `status=` is read as well
# as `state=` so a roster row that records its own closure is understood by the
# same predicate as a sweeper verdict line.
_wt_discharged() {  # <line>
  local v
  [ "$(_wt_field "$1" acked)" = "yes" ] && return 0
  v="$(_wt_field "$1" state)"
  case "$v" in MET|CLOSED|WAIVED) return 0 ;; esac
  v="$(_wt_field "$1" status)"
  case "$v" in MET|CLOSED|WAIVED) return 0 ;; esac
  return 1
}

_wt_row_discharged() {  # <file> <row name>
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    case "$line" in '#'*) continue ;; esac
    [ "$(_wt_field "$line" name)" = "$2" ] || continue
    _wt_discharged "$line" && return 0
  done < "$1"
  return 1
}

worktree_lease_overruns() {  # <main-root> <verdict-or-roster-file> -> <path>\t<row-id>
  local root="" file="${2:-}" d base id
  root="$(_wt_abs "${1:-}")" || return 0
  [ -n "$root" ] || return 0
  [ -f "$file" ] || return 0
  [ -d "${root}/.worktrees" ] || return 0
  for d in "${root}/.worktrees"/*; do
    [ -d "$d" ] || continue
    base="${d##*/}"
    id="W-$(printf '%s' "$base" | tr '[:lower:]' '[:upper:]')"
    if _wt_row_discharged "$file" "$id"; then
      printf '%s\t%s\n' "$d" "$id"
    elif _wt_row_discharged "$file" "$base"; then
      printf '%s\t%s\n' "$d" "$base"
    fi
  done
}

# The tree a row holds, by that same convention. Exported because the standdown
# call site needs the mapping and a second spelling of it there is a second
# definition of which tree belongs to whom.
worktree_for_row() {  # <main-root> <row name> -> path (whether or not it exists)
  printf '%s/.worktrees/%s' "${1%/}" "$(printf '%s' "${2#W-}" | tr '[:upper:]' '[:lower:]')"
}
