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
# caller of `worktree_root` (three copies before N1: here as `_wt_main_root`, lib/patrol.sh,
# spawn-worktree.sh). `claude_home` is only the probe for "already loaded": D1 read session
# files through it until wave-20 T8c, and reads processes now.
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
# A FACT ABOUT PROCESSES AND DIRECTORIES (wave-20 T8c; review R2-1, R2-8; critic C2-1).
# The land refuses while a `tests/run.sh` process has its SCRIPT PATH or its WORKING
# DIRECTORY inside the project root (every linked worktree under it included) or inside
# the land's target checkout. Nothing else is read.
#
# NO SESSION PLAYS ANY PART. Until T8b the predicate was a conjunction: a busy session
# file in this project AND a `tests/run.sh` anywhere on the machine. The process half never
# said where the suite ran, so a land in one repository was refused by another project's
# floor (T12 F3), and the session running the land was always busy and in-project. T8b then
# excluded the lander's own session, but in-process teammates and Agent-tool subagents have
# no session file of their own: the only busy file in the project is the orchestrator's, so
# the exclusion switched D1 off for the orchestrator's own dispatched floor, its main case.
# Where the suite runs is the whole question, and the process answers it.
#
# ONLY THE RUNNER. A lone `*.test.sh` does not count. That is T8's design: the runner is the
# floor and the integration run, and the root scope covers every tree under `.worktrees/`,
# so counting a writer's own suite in its own tree would refuse every land in the wave
# while any writer tests.
#
# UNREADABLE, NO OPINION. A process whose working directory cannot be read is judged by its
# script path alone, and a relative script path with no working directory places nothing.
# That is the stance this predicate has always taken on a machine it cannot read (it used to
# be a missing jq): D1 guards a merge under a suite, not an unreadable process table, and
# refusing on it would make the verb unusable where trees most need giving back.

# The pids whose command line names `tests/run.sh`, one per line. `pgrep -f` matches the
# full command line and, on macOS, leaves out its own ancestors, so a land that a runner
# itself drives never sees that runner. `ps` covers a machine without pgrep.
_wt_suite_pids() {
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -f -- 'tests/run\.sh' 2>/dev/null
    return 0
  fi
  ps -eo pid=,command= 2>/dev/null | awk '/tests\/run\.sh/ { print $1 }'
}

# `<pid> <cwd>` per pid whose working directory can be read, the path physical. Linux has
# /proc/<pid>/cwd. macOS has no /proc and BSD `ps` has no cwd column, so it takes ONE `lsof`
# call for all the pids, about 12 ms on this machine. An empty pid list never reaches lsof,
# because `lsof -p ""` lists every process.
_wt_proc_cwds() {  # <pid>...
  local pid list="" d
  [ "$#" -gt 0 ] || return 0
  if [ -e /proc/self/cwd ]; then
    for pid in "$@"; do
      d="$(readlink "/proc/${pid}/cwd" 2>/dev/null)" && [ -n "$d" ] && printf '%s %s\n' "$pid" "$d"
    done
    return 0
  fi
  command -v lsof >/dev/null 2>&1 || return 0
  for pid in "$@"; do list="${list:+${list},}${pid}"; done
  lsof -a -d cwd -Fn -p "$list" 2>/dev/null \
    | awk '/^p/ { p = substr($0, 2) } /^n/ && p != "" { print p " " substr($0, 2); p = "" }'
}

# Is <path> this project? The main checkout itself, or anything under it, which takes in
# every linked worktree under its `.worktrees` — where a writer running a suite actually
# sits. A second directory, when given, counts too: the land's TARGET checkout (T8, D1),
# which `spawn-worktree.sh create` can place outside the root with an absolute parent. The
# merge happens there, so a suite running there is the one the constraint names. <path> is
# a process's working directory or its script's path.
_wt_cwd_in_project() {  # <path> <main-root> [target-checkout]
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

# The D1 predicate. Prints `pid=<pid> cwd=<cwd> script=<path>` for the first runner that
# satisfies it and returns 0; returns 1 when none does. A field that could not be read
# prints `unreadable`. The script path is the first command-line word ending in
# `tests/run.sh`, taken against the working directory when it is relative, with its
# directory made physical when that directory exists, so a symlinked spelling (`/tmp` for
# `/private/tmp`) still compares.
_wt_busy_suite() {  # <main-root> [target-checkout] -> pid=... cwd=... script=...
  local root="${1:-}" co="${2:-}" pids cwds pid cmd cwd script dir tok
  local -a words
  [ -n "$root" ] || return 1
  pids="$(_wt_suite_pids)"
  [ -n "$pids" ] || return 1
  # shellcheck disable=SC2086  # one pid per word, digits only
  cwds="$(_wt_proc_cwds $pids)"
  for pid in $pids; do
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    cmd="$(ps -o command= -p "$pid" 2>/dev/null)"
    # Re-read, not trusted from the listing: the process may have exited, or its pid been
    # reused, since pgrep answered.
    case "$cmd" in *tests/run.sh*) : ;; *) continue ;; esac
    cwd="$(printf '%s\n' "$cwds" | awk -v p="$pid" '$1 == p { sub(/^[^ ]* /, ""); print; exit }')"
    script=""
    read -r -a words <<< "$cmd"
    for tok in "${words[@]}"; do
      case "$tok" in *tests/run.sh) script="$tok"; break ;; esac
    done
    case "$script" in
      '') : ;;
      /*) : ;;
      *) if [ -n "$cwd" ]; then script="${cwd}/${script}"; else script=""; fi ;;
    esac
    if [ -n "$script" ]; then
      dir="$(cd "${script%/*}" 2>/dev/null && pwd -P)" && script="${dir}/${script##*/}"
    fi
    if _wt_cwd_in_project "$script" "$root" "$co" || _wt_cwd_in_project "$cwd" "$root" "$co"; then
      printf 'pid=%s cwd=%s script=%s' "$pid" "${cwd:-unreadable}" "${script:-unreadable}"
      return 0
    fi
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
# leaves the repository exactly as it found it — the tree's `.bionic` record link
# included (wave-26 D19). The link is dropped only just before `git worktree
# remove`, the one act that needs it gone, and put back if git refuses that.
#
# THE LANDING RULE (wave-26 D7, as ruled in A-orch-26). A tree lands on its own
# green run. It must first contain what landed since it branched only where that
# landed work touches a file the tree also changed: `not-current` names those
# files (`_wt_not_current`). `stale-proof` when the LAST line of the tree's stamp
# file (`<git-dir>/bionic-stamps`, written by the booking shim) is on another
# head, on a dirty tree, or red. No stamp file at all means no suite-class
# command ever ran in the tree, and is not refused. The head of <onto> is read
# again just before the merge, and a moved head is judged again (review 2 F7).
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
# Both are checked before anything else is read in the tree, so even the link
# drop at removal applies only to a tree this lease is actually entitled to touch.
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

# THE STALE-PROOF READ (wave-26 D7). Reads the LAST line of the tree's stamp file,
# `stamp/v1|head=<40-hex>|dirty=<count>|rc=<n>|at=<ISO-UTC>|cmd=<...>`, appended by the
# booking shim to `<the tree's git dir>/bionic-stamps`. Prints the reason and the fix and
# returns 0 when that line is not proof for <head>: on another head, on a dirty tree, red,
# or not a stamp at all. Returns 1 when it is proof — and when there is no stamp file, which
# means no suite-class command ever ran in the tree.
#
# `cmd=` is the last field and free text, so the read STOPS there (review 2 F2): what follows
# is the command, whatever it contains, and a `|rc=0` in it never speaks for the run. That
# holds by itself, without the shim's pipe replacement. Before `cmd=`, each of head, dirty
# and rc appears exactly once; a line giving one twice is no line the shim writes.
_wt_stale_proof() {  # <worktree abs> <head> -> why=... | nothing
  local wt="${1:-}" head="${2:-}" gd file last f s_head="" s_dirty="" s_rc=""
  local n_head=0 n_dirty=0 n_rc=0
  local again="re-run the tree's suites at its head, land again"
  local -a fields
  gd="$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)"
  [ -n "$gd" ] || { printf 'why=unreadable stamps=%s/<no git dir> — %s' "$wt" "$again"; return 0; }
  file="${gd}/bionic-stamps"
  [ -e "$file" ] || [ -L "$file" ] || return 1
  last="$(tail -n 1 "$file" 2>/dev/null)"
  case "$last" in
    'stamp/v1|'*) IFS='|' read -r -a fields <<< "$last" ;;
    *) printf 'why=unreadable stamps=%s — %s' "$file" "$again"; return 0 ;;
  esac
  for f in "${fields[@]}"; do
    case "$f" in
      cmd=*)   break ;;
      head=*)  s_head="${f#head=}";   n_head=$((n_head + 1)) ;;
      dirty=*) s_dirty="${f#dirty=}"; n_dirty=$((n_dirty + 1)) ;;
      rc=*)    s_rc="${f#rc=}";       n_rc=$((n_rc + 1)) ;;
    esac
  done
  [ "${n_head}${n_dirty}${n_rc}" = "111" ] \
    || { printf 'why=unreadable stamps=%s — %s' "$file" "$again"; return 0; }
  case "${s_head}:${s_dirty}:${s_rc}" in
    :*|*::*|*:|*[!0-9a-f:]*) printf 'why=unreadable stamps=%s — %s' "$file" "$again"; return 0 ;;
  esac
  if [ "$s_head" != "$head" ]; then
    printf 'why=head stamp_head=%s head=%s — %s' "$s_head" "$head" "$again"; return 0
  fi
  if [ "$s_dirty" != "0" ]; then
    printf 'why=dirty dirty=%s head=%s — commit or clean the tree, %s' "$s_dirty" "$head" "$again"; return 0
  fi
  if [ "$s_rc" != "0" ]; then
    printf 'why=red rc=%s head=%s — make the suites green, %s' "$s_rc" "$head" "$again"; return 0
  fi
  return 1
}

# THE NOT-CURRENT READ (wave-26 D7, as ruled in A-orch-26). Where landed work the tree lacks
# touches a file the tree also changed, the merge would combine two changes to one file that
# no green run has seen together. Prints `files=<the overlap>` and returns 0 when the tree must
# merge <onto> first; returns 1 when it may land as it is — it contains <onto head>, or nothing
# it lacks touches a file it changed. Anything git cannot answer is printed as
# `files=<unreadable>` and refused, never landed.
#
# Both sides are read from the merge base, as the merge itself reads them: the tree's side is
# what it changed since, the landed side what the merge would bring in from <onto head>. That
# holds a merge commit's own resolution, and leaves out a landed change that a later landed
# commit reverted, which the merge never brings. Renames are OFF whatever the user's diff
# config says: a rename is its old path deleted and its new path added, so a rename on either
# side of an edit on the other overlaps on the old path.
_wt_not_current() {  # <root> <onto head> <tree head> -> files=... | nothing
  local root="${1:-}" onto_head="${2:-}" head="${3:-}" mine landed f hits="" n=0 nl='
'
  case "${onto_head}:${head}" in
    :*|*:|*[!0-9a-f:]*) printf 'files=<unreadable>'; return 0 ;;
  esac
  git -C "$root" merge-base --is-ancestor "$onto_head" "$head" 2>/dev/null
  case $? in
    0) return 1 ;;
    1) : ;;
    *) printf 'files=<unreadable>'; return 0 ;;
  esac
  mine="$(git -C "$root" diff --no-renames --name-only "${onto_head}...${head}" 2>/dev/null)" \
    && landed="$(git -C "$root" diff --no-renames --name-only "${head}...${onto_head}" 2>/dev/null)" \
    || { printf 'files=<unreadable>'; return 0; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "${nl}${landed}${nl}" in
      *"${nl}${f}${nl}"*)
        n=$((n + 1))
        if [ "$n" -le 5 ]; then hits="${hits:+${hits},}${f}"; fi ;;
    esac
  done <<EOF
$mine
EOF
  [ "$n" -gt 0 ] || return 1
  if [ "$n" -gt 5 ]; then hits="${hits},+$((n - 5))-more"; fi
  printf 'files=%s' "$hits"
}

_wt_refuse_not_current() {  # <branch> <onto> <onto head> <files=...>
  _wt_refuse "not-current branch=${1} onto=${2} onto_head=${3:-<none>} ${4} — merge ${2} into the tree, re-run its suites, land again"
}

worktree_land() {  # <worktree path> <onto> -> LANDED | REFUSED
  local target="${1:-}" onto="${2:-}" wt_abs root branch co ahead busy merge_sha rc
  local dirt onto_head head why link_to overlap now

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

  # The record link is not work. In a project that ignores `.bionic` only in its
  # directory shape, or not at all, git reads the link as `?? .bionic`; that one
  # entry is passed here and the link itself is dropped just before the removal.
  dirt="$(git -C "$wt_abs" status --porcelain 2>/dev/null)"
  [ -L "${wt_abs}/.bionic" ] && dirt="$(printf '%s\n' "$dirt" | grep -vxF '?? .bionic')"
  if [ -n "$dirt" ]; then
    _wt_refuse "dirty-tree path=${wt_abs} branch=${branch}"; return 2
  fi

  ahead="$(git -C "$root" rev-list --count "refs/heads/${onto}..${branch}" 2>/dev/null)"
  case "$ahead" in ''|*[!0-9]*) _wt_refuse "branch-unreadable branch=${branch}"; return 2 ;; esac
  if [ "$ahead" -eq 0 ]; then
    _wt_refuse "nothing-to-land branch=${branch} onto=${onto}"; return 2
  fi

  # NOT CURRENT: what landed since the tree branched must be in it wherever it
  # touches a file the tree also changed, so no file the merge combines is untested.
  onto_head="$(git -C "$root" rev-parse --verify --quiet "refs/heads/${onto}" 2>/dev/null)"
  head="$(git -C "$wt_abs" rev-parse --verify --quiet HEAD 2>/dev/null)"
  overlap="$(_wt_not_current "$root" "$onto_head" "$head")" && {
    _wt_refuse_not_current "$branch" "$onto" "$onto_head" "$overlap"; return 2
  }

  why="$(_wt_stale_proof "$wt_abs" "$head")" && {
    _wt_refuse "stale-proof ${why}"; return 2
  }

  # THE TARGET CHECKOUT IS CLEAN IN WHAT GIT TRACKS. A merge into a checkout
  # holding staged or modified tracked files mixes somebody's unfinished work
  # into the merge — or fails half-way on it. Untracked files are not read: the
  # `.bionic` alias and `.worktrees/` live there by design.
  if [ -n "$(git -C "$co" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    _wt_refuse "onto-checkout-dirty checkout=${co} branch=${onto}"; return 2
  fi

  busy="$(_wt_busy_suite "$root" "$co")" && {
    _wt_refuse "suite-running ${busy}"; return 2
  }

  # THE HEAD IS READ AGAIN JUST BEFORE THE MERGE (review 2 F7). Another land onto
  # <onto> may have gone through since the read above; if the head moved, the
  # not-current decision is taken again against the head the merge will meet.
  # What remains is the gap between this read and `git merge`'s own read of HEAD.
  now="$(git -C "$root" rev-parse --verify --quiet "refs/heads/${onto}" 2>/dev/null)"
  if [ "$now" != "$onto_head" ]; then
    onto_head="$now"
    overlap="$(_wt_not_current "$root" "$onto_head" "$head")" && {
      _wt_refuse_not_current "$branch" "$onto" "$onto_head" "$overlap"; return 2
    }
  fi

  # --no-ff ALWAYS: a fast-forward would erase the fact that this was a task,
  # and the merge commit is what the ledger row points at. The head merged is
  # the one judged above, not whatever the branch holds by now.
  if ! git -C "$co" merge --no-ff -m "merge ${branch} (land)" "$head" >/dev/null 2>&1; then
    git -C "$co" merge --abort >/dev/null 2>&1
    _wt_refuse "merge-failed branch=${branch} onto=${onto} checkout=${co}"; return 2
  fi
  merge_sha="$(git -C "$co" rev-parse HEAD 2>/dev/null)"

  # No --force here either. If git refuses now, the merge has landed and the
  # tree has not gone; the line says both so the operator is not left guessing
  # which half happened. The record link goes only now — git would refuse the
  # removal over an unignored one — and comes back if the removal is refused.
  link_to="$(readlink "${wt_abs}/.bionic" 2>/dev/null)"
  _wt_drop_legacy_link "$wt_abs" || :
  if ! git -C "$root" worktree remove "$wt_abs" >/dev/null 2>&1; then
    [ -n "$link_to" ] && [ ! -e "${wt_abs}/.bionic" ] && ln -s "$link_to" "${wt_abs}/.bionic" 2>/dev/null
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
  worktree_land "$target" "$onto"
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

# ---------------------------------------------------------------------------
# Workspaces — the tree recorded for a name (wave-25 T1, REQ-2, D3).
#
# THE ACT THAT CREATES A TREE RECORDS WHOSE IT IS. `spawn-worktree.sh create --for <name>`
# appends one line, after the tree is verified, to `<main-root>/.bionic/tmp/workspaces-<sid>.state`:
#
#   workspace/v1|session=<sid>|name=<agent name>|path=<absolute tree>|branch=<branch>|base=<sha>|plan=<absolute plan or none>|at=<ISO-UTC>
#
# and the two readers below answer from that file alone. That is the whole difference from
# `worktree_for_row` above: the convention says which tree a name WOULD have, this record
# says which tree was MADE for it. Nothing here falls back to the convention — a name nobody
# recorded has no tree, whatever `.worktrees/` holds. Not a roster key: the tree exists
# before the roster row does.
#
# APPEND-ONLY, THE LAST LINE WINS. A second create for one name appends a second line;
# `workspace_for_name` returns the later tree, `workspaces_of_session` every tree in order.
#
# THE SYMLINK REFUSAL IS THE ROSTER'S (hooks/dispatch-preflight.sh `attested`): `.bionic`,
# `.bionic/tmp` and the file itself are each refused when they are a symlink, by the writer
# and by both readers, so a planted link can neither carry a record out of the tree nor hand
# a session somebody else's.
#
# THE READERS' NAMES ARE THE PLAN'S INTERFACE, verbatim, which is why they carry no
# `worktree_` prefix. Status: 0 an answer, 1 nothing recorded, 2 refused (a link on the
# path, a file that cannot be read, or a session id no file can be named for).

WORKSPACE_SCHEMA="workspace/v1"

# The file for <root> <sid>, rc 1 when the session id cannot name one. The shape rule is
# `engaged_marker_path`'s (lib/run.sh): a session that can have a marker can have this file.
_wt_workspaces_file() {  # <root> <sid>
  local root="${1:-}" sid="${2:-}"
  [ -n "$root" ] && [ -n "$sid" ] || return 1
  [ "$sid" = "unknown" ] && return 1
  case "$sid" in *[!A-Za-z0-9_-]*) return 1 ;; esac
  printf '%s/.bionic/tmp/workspaces-%s.state' "${root%/}" "$sid"
}

_wt_workspaces_unlinked() {  # <root> <file> -> 0 when no level of the path is a symlink
  [ ! -L "${1%/}/.bionic" ] && [ ! -L "${1%/}/.bionic/tmp" ] && [ ! -L "$2" ]
}

# A value that would break the line: empty, or carrying the separator or a line break.
_wt_workspace_value_bad() {  # <value>
  case "${1:-}" in ''|*'|'*|*$'\n'*|*$'\r'*) return 0 ;; esac
  return 1
}

# The session's bound plan as the engaged marker names it, or `none`. Never the root's
# newest open run: that fallback is somebody else's run (lib/run.sh `session_run`).
_wt_workspace_plan() {  # <root> <sid>
  local lib p
  if ! declare -f session_plan >/dev/null 2>&1; then
    lib="$( cd "$(_wt_self_dir)" 2>/dev/null && pwd -P )/run.sh"
    # shellcheck source=/dev/null
    [ -r "$lib" ] && . "$lib" 2>/dev/null
    declare -f session_plan >/dev/null 2>&1 || return 1
  fi
  p="$(session_plan "$1" "$2" 2>/dev/null)" || p=""
  case "$p" in /*) printf '%s' "$p" ;; *) printf 'none' ;; esac
}

# Could <name> be recorded for <sid> under <root>? Silent rc 0, or the reason on stdout and
# rc 1. `create` asks BEFORE it makes anything, so a create that could not record is refused
# with nothing to undo; `worktree_record_workspace` asks again at the append.
worktree_workspace_refusal() {  # <root> <sid> <name>
  local f
  _wt_workspace_value_bad "${3:-}" && { printf 'invalid-name'; return 1; }
  f="$(_wt_workspaces_file "${1:-}" "${2:-}")" || { printf 'invalid-session'; return 1; }
  _wt_workspaces_unlinked "$1" "$f" || { printf 'workspace-file-symlinked'; return 1; }
  [ ! -e "$f" ] || [ -f "$f" ] || { printf 'workspace-file-unwritable'; return 1; }
  return 0
}

# Append the one line. Silent rc 0, or the reason on stdout and rc 1.
worktree_record_workspace() {  # <root> <sid> <name> <abs tree> <branch> <base sha>
  local root="${1:-}" sid="${2:-}" name="${3:-}" path="${4:-}" branch="${5:-}" base="${6:-}" f plan v
  worktree_workspace_refusal "$root" "$sid" "$name" || return 1
  f="$(_wt_workspaces_file "$root" "$sid")"
  case "$path" in /*) : ;; *) printf 'workspace-path-not-absolute'; return 1 ;; esac
  plan="$(_wt_workspace_plan "$root" "$sid")" || { printf 'run-library-unloadable'; return 1; }
  for v in "$path" "$branch" "$base" "$plan"; do
    _wt_workspace_value_bad "$v" && { printf 'workspace-field-unrecordable'; return 1; }
  done
  mkdir -p "${f%/*}" 2>/dev/null || { printf 'workspace-file-unwritable'; return 1; }
  _wt_workspaces_unlinked "$root" "$f" || { printf 'workspace-file-symlinked'; return 1; }
  printf '%s|session=%s|name=%s|path=%s|branch=%s|base=%s|plan=%s|at=%s\n' \
    "$WORKSPACE_SCHEMA" "$sid" "$name" "$path" "$branch" "$base" "$plan" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$f" 2>/dev/null \
    || { printf 'workspace-file-unwritable'; return 1; }
}

# Both readers in one walk, read by key. A line counts when it is this schema, names THIS
# session (the file name alone is not trusted for that) and carries an absolute path; a
# CRLF ending is translated, never kept in the path.
_wt_workspace_paths() {  # <root> <sid> <name> <all: 1 or 0>
  local f out
  f="$(_wt_workspaces_file "$1" "$2")" || return 2
  _wt_workspaces_unlinked "$1" "$f" || return 2
  [ -e "$f" ] || return 1
  { [ -f "$f" ] && [ -r "$f" ]; } || return 2
  out="$(WT_SID="$2" WT_NAME="$3" WT_ALL="$4" awk -F'|' -v schema="$WORKSPACE_SCHEMA" '
    BEGIN { sid = ENVIRON["WT_SID"]; want = ENVIRON["WT_NAME"]; all = ENVIRON["WT_ALL"] }
    { sub(/\r$/, "") }
    $1 != schema { next }
    {
      s = ""; n = ""; p = ""; hn = 0
      for (i = 2; i <= NF; i++) {
        if (index($i, "session=") == 1) s = substr($i, 9)
        else if (index($i, "name=") == 1) { n = substr($i, 6); hn = 1 }
        else if (index($i, "path=") == 1) p = substr($i, 6)
      }
      if (s != sid || substr(p, 1, 1) != "/") next
      if (all == "1") print p
      else if (hn && n == want) last = p
    }
    END { if (all != "1" && last != "") print last }' "$f" 2>/dev/null)" || return 2
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

workspace_for_name() {  # <root> <sid> <name> -> the last tree recorded for <name>; 1 none, 2 refused
  [ -n "${3:-}" ] || return 1
  _wt_workspace_paths "${1:-}" "${2:-}" "$3" 0
}

workspaces_of_session() {  # <root> <sid> -> every tree recorded, one per line; 1 none, 2 refused
  _wt_workspace_paths "${1:-}" "${2:-}" "" 1
}
